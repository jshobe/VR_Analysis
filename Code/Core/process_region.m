function R = process_region(region_folder, interval_data, occupancy_4cm, halls, ...
    trans_beg, trans_end, maxRHD_ts, animal_folder, opts)
% Process spike data and create plots for one region (legacy pipeline)
%
% MODIFIED: now also RETURNS a struct R for the new pipeline:
%   R.tt_counts   : [nBins x nUnits] mean across selected trials/blocks
%   R.binCenters  : [nBins x 1]      default 1:nBins (explicit; replace if you have true centers)
%
% Adds (legacy features preserved):
% - Adjustable SpeedThresh passed to process_spike_data
% - Manual cache management (no auto-overwrite): saves speed_thresh and warns on mismatch
% - MakeLegacyPlots toggle: compute/load caches and block means; skip legacy plotting if false
% - Spike count computation per unit/type/block for legend display

% Output folders
out_folder = fullfile(region_folder, 'Figures');
if ~exist(out_folder, 'dir'), mkdir(out_folder); end
region_derived = fullfile(region_folder, 'Derived');
if ~exist(region_derived, 'dir'), mkdir(region_derived); end

cache_file = fullfile(region_derived, 'spikes_cache.mat');

% ---------------- Load or compute spike data (manual cache workflow) ----------------
rate_4cm_3D = [];
raster_data = {};
cluster_id_good = [];

if exist(cache_file, 'file') && isfield(opts, 'Overwrite') && ~opts.Overwrite
    try
        S = load(cache_file, 'rate_4cm_3D', 'raster_data', 'cluster_id_good', 'speed_thresh');
        rate_4cm_3D = S.rate_4cm_3D;
        raster_data = S.raster_data;
        cluster_id_good = S.cluster_id_good;
        log_msg('Loaded spike cache');
        
        if isfield(S, 'speed_thresh') && isfield(opts, 'SpeedThresh') && ...
           isfinite(S.speed_thresh) && S.speed_thresh ~= opts.SpeedThresh
            log_msg('WARNING: cache built with SpeedThresh=%.3f; current=%.3f. Using cached spikes (no auto-overwrite).', ...
                S.speed_thresh, opts.SpeedThresh);
        end
    catch ME
        log_msg('Failed to load spike cache: %s. Recomputing...', ME.message);
    end
end

if isempty(rate_4cm_3D)
    % Compute spikes with adjustable speed gate
    speedArg = {};
    if isfield(opts, 'SpeedThresh')
        speedArg = {'SpeedThresh', opts.SpeedThresh};
        log_msg('Computing spikes (SpeedThresh=%.3f)...', opts.SpeedThresh);
    else
        log_msg('Computing spikes (default speed threshold)...');
    end

    [rate_4cm_3D, raster_data, cluster_id_good] = process_spike_data( ...
        region_folder, interval_data, occupancy_4cm, halls, trans_beg, trans_end, maxRHD_ts, speedArg{:});

    % Save cache with speed threshold metadata (manual workflow: no auto-overwrite)
    if isfield(opts, 'SaveIntermediates') && opts.SaveIntermediates
        try
            if isfield(opts, 'SpeedThresh')
                speed_thresh = opts.SpeedThresh; %#ok<NASGU>
                save(cache_file, 'rate_4cm_3D', 'raster_data', 'cluster_id_good', 'speed_thresh', '-v7.3');
                log_msg('Saved spike cache (SpeedThresh=%.3f)', opts.SpeedThresh);
            else
                save(cache_file, 'rate_4cm_3D', 'raster_data', 'cluster_id_good', '-v7.3');
                log_msg('Saved spike cache (default speed threshold)');
            end
        catch ME
            log_msg('WARNING: Failed to save spike cache: %s', ME.message);
        end
    end
end

% ---------------- Check data ----------------
if isempty(rate_4cm_3D) || size(rate_4cm_3D, 3) == 0
    log_msg('No units found. Skipping region.');
    % Return empty R with required fields for strictness
    R = struct('tt_counts', [], 'binCenters', []);
    return;
end
[nTrials, nBins, nUnits] = size(rate_4cm_3D);
log_msg('Loaded %d units, %d trials, %d bins', nUnits, nTrials, nBins);

% ---------------- Compute block averages (legacy) ----------------
blocks_to_use = opts.Blocks;
[rate_mean_halls, ~, blocks_used] = analyze_blocks(rate_4cm_3D, halls, 'Blocks', blocks_to_use);
log_msg('Blocks: %s', format_blocks(blocks_used));

% ---------------- NEW: Compute spike counts per unit, per trial type, per block ----------------
nBlocks = numel(blocks_used);
unit_spike_counts_3D = zeros(nUnits, 7, nBlocks);

for u = 1:nUnits
    for b = 1:nBlocks
        trials_in_block = blocks_used{b}(:);
        trials_in_block = trials_in_block(isfinite(trials_in_block) & trials_in_block >= 1 & trials_in_block <= nTrials);
        
        for TT = 1:7
            % Find trials of this type within this block
            trials_of_type = trials_in_block(halls(trials_in_block) == TT);
            total_spikes = 0;
            
            for tr = trials_of_type(:)'
                C = raster_data{u, tr};
                if ~isempty(C) && isfield(C, 'positions') && ~isempty(C.positions)
                    total_spikes = total_spikes + numel(C.positions);
                end
            end
            
            unit_spike_counts_3D(u, TT, b) = total_spikes;
        end
    end
end

log_msg('Computed spike counts: [%d units x 7 types x %d blocks]', nUnits, nBlocks);

% ---------------- === RETURN VALUES FOR NEW PIPELINE === ----------------
% Build a strict time-by-unit matrix for the selected trials/blocks:
%   - Gather all trials from blocks_used
%   - Average across those trials to get [nBins x nUnits]
if nBlocks > 0
    selTrials = unique(cat(2, blocks_used{:}));
    selTrials = selTrials(isfinite(selTrials) & selTrials >= 1 & selTrials <= nTrials);
else
    selTrials = 1:nTrials;
end
if isempty(selTrials)
    tt_counts = zeros(nBins, nUnits);
else
    tt_counts = squeeze(nanmean(rate_4cm_3D(selTrials, :, :), 1));  % [nBins x nUnits]
end

% We don't have explicit spatial bin centers here; keep it explicit & strict:
binCenters = (1:nBins)';  % replace with true centers if available elsewhere

R = struct();
R.tt_counts  = tt_counts;
R.binCenters = binCenters;

% ---------------- Option B: Skip legacy plotting when MakeLegacyPlots=false ----------------
if isfield(opts, 'MakeLegacyPlots') && ~opts.MakeLegacyPlots
    log_msg('Skipping legacy plots for this region (MakeLegacyPlots=false)');
    % Caches and block means are ready; no PDFs will be created.
    return;
end

% ---------------- Create plots (legacy) ----------------
[~, animal_name] = fileparts(animal_folder);
[~, region_name] = fileparts(region_folder);
title_prefix = sprintf('%s | %s | ', animal_name, region_name);

% Defaults for options if missing (preserve logical types)
def = struct('SmoothingWin', 8, ...
             'SavePNGs', false, ...
             'PDFName', 'AllUnits_SpatialAnalysis.pdf', ...
             'PDFContent', 'image', ...
             'ShowTrialIDs', false, ...
             'RasterMarkerSize', 2, ...
             'LegendOutside', false, ...
             'UseParallel', true);

% Safe getters that preserve types
function val = getOptVal(opts, name, dflt)
    if isfield(opts, name) && ~isempty(opts.(name)), val = opts.(name); else, val = dflt; end
end
function val = aslogical(x, dflt)
    if nargin < 2, dflt = false; end
    if islogical(x)
        val = x;
    elseif isnumeric(x)
        val = logical(x);
    else
        val = dflt;
    end
end

savePNGs     = isfield(opts,'SavePNGs')     && islogical(opts.SavePNGs)     && opts.SavePNGs;
showTrialIDs = isfield(opts,'ShowTrialIDs') && islogical(opts.ShowTrialIDs) && opts.ShowTrialIDs;
saveFIGs     = isfield(opts,'SaveFIGs')     && islogical(opts.SaveFIGs)     && opts.SaveFIGs;

% Call create_all_plots with spike counts
create_all_plots(rate_mean_halls, raster_data, halls, cluster_id_good, out_folder, ...
    'Blocks',           blocks_used, ...
    'SmoothingWin',     opts.SmoothingWin, ...
    'SavePNGs',         savePNGs, ...
    'PDFName',          opts.PDFName, ...
    'PDFContent',       opts.PDFContent, ...
    'ShowTrialIDs',     showTrialIDs, ...
    'TitlePrefix',      title_prefix, ...
    'RasterMarkerSize', opts.RasterMarkerSize, ...
    'SaveFIGs',         saveFIGs, ...
    'FIGDir',           fullfile(out_folder, 'FIGs'), ...
    'SpikeCountsByTypeByBlock', unit_spike_counts_3D);  % NEW: Pass spike counts

log_msg('Finished region (legacy)');
end

% ==================== Local helpers ====================
function log_msg(fmt, varargin)
% Simple logging with timestamp
fprintf('[%s] %s\n', datestr(now, 'HH:MM:SS'), sprintf(fmt, varargin{:}));
end

function s = format_blocks(blocks)
% Format block ranges for display
try
    parts = cellfun(@(b) sprintf('%d:%d (n=%d)', min(b), max(b), numel(b)), ...
        blocks, 'UniformOutput', false);
    s = strjoin(parts, ' | ');
catch
    s = '(invalid)';
end
end
