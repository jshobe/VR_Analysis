function R = process_region(region_folder, interval_data, occupancy_4cm, halls, ...
    trans_beg, trans_end, maxRHD_ts, animal_folder, opts)
% Process spike data and create legacy plots for one region.
%
% RETURNS:
%   R.tt_counts  : [nBins x nUnits] average across selected trials/blocks
%   R.binCenters : [nBins x 1] integer bins (replace if you have true centers)

% --- make opts optional & default legacy plotting ON ---
if nargin < 9 || isempty(opts)
    opts = get_default_opts();   % must exist in Code/Core/
end

% Core-safe defaults; legacy behavior by default
if ~isfield(opts,'MakeLegacyPlots'),    opts.MakeLegacyPlots    = true;  end   % plots ON by default
if ~isfield(opts,'Overwrite'),          opts.Overwrite          = false; end
if ~isfield(opts,'SaveIntermediates'),  opts.SaveIntermediates  = true;  end
if ~isfield(opts,'Blocks'),             opts.Blocks             = {[]};  end   % normalize later
if ~isfield(opts,'SpeedThresh'),        opts.SpeedThresh        = [];    end   % [] => default in process_spike_data
if ~isfield(opts,'SmoothingWin'),       opts.SmoothingWin       = 8;     end
if ~isfield(opts,'PDFName'),            opts.PDFName            = 'AllUnits_SpatialAnalysis.pdf'; end
if ~isfield(opts,'PDFContent'),         opts.PDFContent         = 'image'; end
if ~isfield(opts,'ShowTrialIDs'),       opts.ShowTrialIDs       = false; end
if ~isfield(opts,'RasterMarkerSize'),   opts.RasterMarkerSize   = 2;     end
if ~isfield(opts,'SaveFIGs'),           opts.SaveFIGs           = false; end
if ~isfield(opts,'SavePNGs'),           opts.SavePNGs           = false; end

% ---------- Output folders ----------
out_folder = fullfile(region_folder, 'Figures');
if ~exist(out_folder, 'dir'), mkdir(out_folder); end
region_derived = fullfile(region_folder, 'Derived');
if ~exist(region_derived, 'dir'), mkdir(region_derived); end
cache_file = fullfile(region_derived, 'spikes_cache.mat');

% ---------- Load or compute spike data (manual cache workflow) ----------
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

        % Warn if cached speed threshold mismatches current
        if isfield(S,'speed_thresh') ...
           && isfield(opts,'SpeedThresh') && ~isempty(opts.SpeedThresh) && isfinite_scalar(opts.SpeedThresh) ...
           && isfinite_scalar(S.speed_thresh) && (S.speed_thresh ~= opts.SpeedThresh)
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
    if isfield(opts,'SpeedThresh') && ~isempty(opts.SpeedThresh) && isfinite_scalar(opts.SpeedThresh)
        speedArg = {'SpeedThresh', opts.SpeedThresh};
        log_msg('Computing spikes (SpeedThresh=%.3f)...', opts.SpeedThresh);
    else
        log_msg('Computing spikes (default speed threshold)...');
    end

    [rate_4cm_3D, raster_data, cluster_id_good] = process_spike_data( ...
        region_folder, interval_data, occupancy_4cm, halls, trans_beg, trans_end, maxRHD_ts, speedArg{:});

    % Save cache with speed threshold metadata (manual workflow: no auto-overwrite)
    if isfield(opts,'SaveIntermediates') && opts.SaveIntermediates
        try
            if isfield(opts,'SpeedThresh') && ~isempty(opts.SpeedThresh) && isfinite_scalar(opts.SpeedThresh)
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

% ---------- Check data ----------
if isempty(rate_4cm_3D) || size(rate_4cm_3D, 3) == 0
    log_msg('No units found. Skipping region.');
    R = struct('tt_counts', [], 'binCenters', []);
    return;
end
[nTrials, nBins, nUnits] = size(rate_4cm_3D);
log_msg('Loaded %d units, %d trials, %d bins', nUnits, nTrials, nBins);

% ---------- Normalize Blocks & compute block averages (legacy) ----------
if isempty(opts.Blocks) || (iscell(opts.Blocks) && isempty([opts.Blocks{:}]))
    blocks_to_use = {1:nTrials};      % all trials in one block
else
    blocks_to_use = opts.Blocks;
end
[rate_mean_halls, ~, blocks_used] = analyze_blocks(rate_4cm_3D, halls, 'Blocks', blocks_to_use);
log_msg('Blocks: %s', format_blocks(blocks_used));

% ---------- Spike counts per unit, per trial type, per block (for legends/summary) ----------
nBlocks = numel(blocks_used);
unit_spike_counts_3D = zeros(nUnits, 7, nBlocks);

for u = 1:nUnits
    for b = 1:nBlocks
        trials_in_block = blocks_used{b}(:);
        trials_in_block = trials_in_block(isfinite(trials_in_block) & trials_in_block >= 1 & trials_in_block <= nTrials);
        for TT = 1:7
            trials_of_type = trials_in_block(halls(trials_in_block) == TT);
            total_spikes = 0;
            for tr = trials_of_type(:)'
                C = raster_data{u, tr};
                if ~isempty(C) && isfield(C,'positions') && ~isempty(C.positions)
                    total_spikes = total_spikes + numel(C.positions);
                end
            end
            unit_spike_counts_3D(u, TT, b) = total_spikes;
        end
    end
end
log_msg('Computed spike counts: [%d units x 7 types x %d blocks]', nUnits, nBlocks);

% ---------- RETURN strict time-by-unit matrix across selected trials ----------
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
binCenters = (1:nBins)';   % replace with real centers if available
R = struct('tt_counts', tt_counts, 'binCenters', binCenters);

% ---------- Plotting (legacy only) ----------
if isfield(opts,'MakeLegacyPlots') && ~opts.MakeLegacyPlots
    log_msg('Skipping legacy plots for this region (MakeLegacyPlots=false)');
    return;
end

[~, animal_name] = fileparts(animal_folder);
[~, region_name] = fileparts(region_folder);
title_prefix = sprintf('%s | %s | ', animal_name, region_name);

savePNGs     = islogical_true(opts, 'SavePNGs');
showTrialIDs = islogical_true(opts, 'ShowTrialIDs');
saveFIGs     = islogical_true(opts, 'SaveFIGs');

create_all_plots(rate_mean_halls, raster_data, halls, cluster_id_good, out_folder, ...
    'Blocks',             blocks_used, ...
    'SmoothingWin',       opts.SmoothingWin, ...
    'SavePNGs',           savePNGs, ...
    'PDFName',            opts.PDFName, ...
    'PDFContent',         opts.PDFContent, ...
    'ShowTrialIDs',       showTrialIDs, ...
    'TitlePrefix',        title_prefix, ...
    'RasterMarkerSize',   opts.RasterMarkerSize, ...
    'SaveFIGs',           saveFIGs, ...
    'FIGDir',             fullfile(out_folder, 'FIGs'), ...
    'SpikeCountsByTypeByBlock', unit_spike_counts_3D);

log_msg('Finished region (legacy)');
end

% ==================== Local helpers ====================
function tf = isfinite_scalar(x)
tf = isnumeric(x) && isscalar(x) && isfinite(x);
end

function tf = islogical_true(s, fld)
tf = isfield(s, fld) && islogical(s.(fld)) && s.(fld);
end

function log_msg(fmt, varargin)
fprintf('[%s] %s\n', datestr(now, 'HH:MM:SS'), sprintf(fmt, varargin{:}));
end

function s = format_blocks(blocks)
try
    parts = cellfun(@(b) sprintf('%d:%d (n=%d)', min(b), max(b), numel(b)), ...
        blocks, 'UniformOutput', false);
    s = strjoin(parts, ' | ');
catch
    s = '(invalid)';
end
end
