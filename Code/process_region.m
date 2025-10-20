function process_region(region_folder, interval_data, occupancy_4cm, halls, ...
    trans_beg, trans_end, maxRHD_ts, animal_folder, opts)
% Process spike data and create plots for one region (legacy pipeline)
%
% Adds:
% - Adjustable SpeedThresh passed to process_spike_data
% - Manual cache management (no auto-overwrite): saves speed_thresh and warns on mismatch
% - MakeLegacyPlots toggle: compute/load caches and block means; skip legacy plotting if false

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
    log_msg('Loading spike cache...');
    try
        S = load(cache_file, 'rate_4cm_3D', 'raster_data', 'cluster_id_good', 'speed_thresh');
        rate_4cm_3D   = S.rate_4cm_3D;
        raster_data   = S.raster_data;
        cluster_id_good = S.cluster_id_good;
        if isfield(S, 'speed_thresh') && isfinite(S.speed_thresh) ...
                && isfield(opts, 'SpeedThresh') && isfinite(opts.SpeedThresh) ...
                && S.speed_thresh ~= opts.SpeedThresh
            log_msg('WARNING: spike cache built with SpeedThresh=%.3f; current=%.3f. Using cached spikes (no overwrite).', ...
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
    return;
end
[nTrials, nBins, nUnits] = size(rate_4cm_3D);
log_msg('Loaded %d units, %d trials, %d bins', nUnits, nTrials, nBins);

% ---------------- Compute block averages (legacy) ----------------
blocks_to_use = opts.Blocks;
[rate_mean_halls, ~, blocks_used] = analyze_blocks(rate_4cm_3D, halls, 'Blocks', blocks_to_use);
log_msg('Blocks: %s', format_blocks(blocks_used));

% ---------------- Option B: Skip legacy plotting when MakeLegacyPlots=false ----------------
if isfield(opts, 'MakeLegacyPlots') && ~opts.MakeLegacyPlots
    log_msg('Skipping legacy plots for this region (MakeLegacyPlots=false)');
    % All caches and block means are ready; no PDFs will be created.
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
getOpt = @(name, dflt) (isfield(opts, name) && ~isempty(opts.(name))) * 0 + 0; %#ok<NASGU>
function val = getOptVal(opts, name, dflt)
    if isfield(opts, name) && ~isempty(opts.(name)), val = opts.(name); else, val = dflt; end
end
function val = aslogical(x, dflt)
    if nargin < 2, dflt = false; end
    if islogical(x)
        val = x;
    elseif isnumeric(x)
        val = x ~= 0;
    elseif ischar(x) || isstring(x)
        s = lower(strtrim(char(x)));
        val = any(strcmp(s, {'true','1','yes'}));
    else
        val = dflt;
    end
end

% Resolve and type-correct options
smoothWin      = getOptVal(opts, 'SmoothingWin',  def.SmoothingWin);
savePNGs       = aslogical(getOptVal(opts, 'SavePNGs', def.SavePNGs), def.SavePNGs);
pdfName        = char(getOptVal(opts, 'PDFName',  def.PDFName));
pdfContent     = char(getOptVal(opts, 'PDFContent', def.PDFContent));
showTrialIDs   = aslogical(getOptVal(opts, 'ShowTrialIDs', def.ShowTrialIDs), def.ShowTrialIDs);
rasterMarkerSz = getOptVal(opts, 'RasterMarkerSize', def.RasterMarkerSize);
legendOutside  = aslogical(getOptVal(opts, 'LegendOutside', def.LegendOutside), def.LegendOutside);
useParallel    = aslogical(getOptVal(opts, 'UseParallel', def.UseParallel), def.UseParallel);
savePNGs     = isfield(opts,'SavePNGs')     && islogical(opts.SavePNGs)     && opts.SavePNGs;
showTrialIDs = isfield(opts,'ShowTrialIDs') && islogical(opts.ShowTrialIDs) && opts.ShowTrialIDs;
saveFIGs     = isfield(opts,'SaveFIGs')     && islogical(opts.SaveFIGs)     && opts.SaveFIGs;


% Call create_all_plots with correctly typed values
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
    'FIGDir',           fullfile(out_folder, 'FIGs'));  % or opts.FIGDir if you add it to the 
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