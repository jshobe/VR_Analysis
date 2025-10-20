function run_spatial_analysis_v2(animal_folder, kilo_folder, out_folder, varargin)
% RUN_SPATIAL_ANALYSIS_V2
% - Computes fast-gated 4 cm binned rates and counts
% - Saves session-wide and per-block mean rate maps (by trial type)
% - Exports unfiltered spike times for FSC (session-wide, per-block, per-trial)
% - Optionally creates plots (disabled by default via DoPlots=false)
%
% Usage:
% run_spatial_analysis_v2(animal_folder, kilo_folder, out_folder, ...
%     'Blocks', {12:174, 178:337, 341:520}, 'DoPlots', false)

% ---------------- Configuration with overrides ----------------
cfg = struct();
cfg.SmoothingWin_cm   = 12;
cfg.MinOccSec         = 0.10;
cfg.BinEdges4cm       = 0:4:534;
cfg.Blocks            = {12:174, 178:337, 341:520};
cfg.SavePNGs          = false;
cfg.PDFName           = 'AllUnits_SpatialAnalysis_V2.pdf';
cfg.TitlePrefix       = '[V2] ';
cfg.ShowTrialIDs      = false;
cfg.RasterMarkerSize  = 9;
cfg.DoPlots           = false;  % default: skip plots

if ~isempty(varargin)
    p = inputParser;
    addParameter(p, 'Blocks',         cfg.Blocks, @(x)iscell(x));
    addParameter(p, 'SmoothingWin',   cfg.SmoothingWin_cm, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
    addParameter(p, 'MinOccSec',      cfg.MinOccSec, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
    addParameter(p, 'BinEdges4cm',    cfg.BinEdges4cm, @(v)isvector(v)&&issorted(v));
    addParameter(p, 'SavePNGs',       cfg.SavePNGs, @islogical);
    addParameter(p, 'PDFName',        cfg.PDFName, @(s)ischar(s)||isstring(s));
    addParameter(p, 'TitlePrefix',    cfg.TitlePrefix, @(s)ischar(s)||isstring(s));
    addParameter(p, 'ShowTrialIDs',   cfg.ShowTrialIDs, @islogical);
    addParameter(p, 'RasterMarkerSize', cfg.RasterMarkerSize, @(x)isnumeric(x)&&isscalar(x)&&x>0);
    addParameter(p, 'DoPlots',        cfg.DoPlots, @islogical);
    parse(p, varargin{:});

    cfg.Blocks           = p.Results.Blocks;
    cfg.SmoothingWin_cm  = p.Results.SmoothingWin;
    cfg.MinOccSec        = p.Results.MinOccSec;
    cfg.BinEdges4cm      = p.Results.BinEdges4cm(:)'; % ensure row
    cfg.SavePNGs         = p.Results.SavePNGs;
    cfg.PDFName          = char(p.Results.PDFName);
    cfg.TitlePrefix      = char(p.Results.TitlePrefix);
    cfg.ShowTrialIDs     = p.Results.ShowTrialIDs;
    cfg.RasterMarkerSize = p.Results.RasterMarkerSize;
    cfg.DoPlots          = p.Results.DoPlots;
else
    cfg.BinEdges4cm = cfg.BinEdges4cm(:)'; % ensure row
end

% ---------------- Setup output folder ----------------
if nargin < 3 || isempty(out_folder)
    out_folder = fullfile(kilo_folder, 'Derived_V2');
end
if ~exist(out_folder, 'dir'), mkdir(out_folder); end

% ---------------- Step 1: Behavior preprocessing ----------------
[interval_data, occupancy_4cm, halls, trans_beg, trans_end, maxRHD_ts] = process_behavioral_data(animal_folder);

% Optional min-occupancy NaN-masking
if ~isempty(occupancy_4cm) && isfinite(cfg.MinOccSec) && cfg.MinOccSec > 0
    occ_mask = occupancy_4cm < cfg.MinOccSec;
    occupancy_4cm(occ_mask) = NaN;
end

% Clip Blocks to valid trial indices
Blocks = clip_blocks_to_trials(cfg.Blocks, numel(trans_beg));

% ---------------- Step 2: Spike processing (fast-only rates) ----------------
[rate_4cm_3D, raster_data, cluster_id_good] = process_spike_data( ...
    kilo_folder, interval_data, occupancy_4cm, halls, trans_beg, trans_end, maxRHD_ts);

[nTrials, nBins, nUnits] = size(rate_4cm_3D);
fprintf('[V2] Trials=%d, Bins(4cm)=%d, Units=%d\n', nTrials, nBins, nUnits);

% ---------------- Step 3: Means by trial type (session-wide and per-block) ----------------
% Session-wide
[RateMeansByType, TrialCountsByType] = compute_rate_means_by_type(rate_4cm_3D, halls);

% Per-block cell averages
[rate_mean_halls, TrialCountsByTypeByBlock, Blocks] = analyze_blocks(rate_4cm_3D, halls, 'Blocks', Blocks);

% Per-block 4D numeric array: [nUnits x nBins x 7 x nBlocks]
nBlocks = numel(Blocks);
RateMeansByTypeByBlock = NaN(nUnits, nBins, 7, nBlocks);
for b = 1:nBlocks
    Rb = rate_mean_halls{b};
    if ~isempty(Rb)
        RateMeansByTypeByBlock(:,:,:,b) = Rb;
    end
end

% ---------------- Step 4: 3D 4 cm spike counts (fast-only) ----------------
counts4cm_3D = build_counts4cm_3D(raster_data, cfg.BinEdges4cm); % [trials x bins x units]

% ---------------- Step 5: Unfiltered spike times for FSC ----------------
[spikes_all_session, spikes_by_block, block_windows, unit_summary, spikes_by_trial] = ...
    build_unfiltered_spike_times(kilo_folder, cluster_id_good, trans_beg, trans_end, Blocks, maxRHD_ts, ...
    'SessionStart', trans_beg(1), ...
    'SessionEnd', maxRHD_ts, ...
    'IncludePerTrial', true);

% ---------------- Step 6: Create plots (optional, skipped by default) ----------------
if cfg.DoPlots
    create_all_plots(rate_mean_halls, raster_data, halls, cluster_id_good, out_folder, ...
        'Blocks', Blocks, ...
        'BinEdges', cfg.BinEdges4cm, ...
        'SmoothingWin', cfg.SmoothingWin_cm, ...
        'SavePNGs', cfg.SavePNGs, ...
        'PDFName', cfg.PDFName, ...
        'TitlePrefix', cfg.TitlePrefix, ...
        'ShowTrialIDs', cfg.ShowTrialIDs, ...
        'RasterMarkerSize', cfg.RasterMarkerSize);
else
    fprintf('[V2] Skipping plot creation (DoPlots=false)\n');
end

% ---------------- Step 7: Save outputs ----------------
save(fullfile(out_folder, 'spatial_analysis_v2.mat'), ...
    'rate_4cm_3D', 'counts4cm_3D', ...
    'RateMeansByType', 'TrialCountsByType', ...                       % session-wide
    'rate_mean_halls', 'RateMeansByTypeByBlock', ...                  % per-block means (cell + 4D numeric)
    'TrialCountsByTypeByBlock', 'Blocks', ...                         % per-block counts and validated blocks
    'occupancy_4cm', 'halls', 'cluster_id_good', 'trans_beg', 'trans_end', ...
    'cfg');

save(fullfile(out_folder, 'fsc_spikes_unfiltered.mat'), ...
    'spikes_all_session', 'spikes_by_block', 'block_windows', 'spikes_by_trial', ...
    'unit_summary', 'cluster_id_good', 'Blocks', 'trans_beg', 'trans_end');

fprintf('[V2] Done. Outputs saved in %s\n', out_folder);
end

% ==================== Local helpers ====================
function BlocksOut = clip_blocks_to_trials(BlocksIn, nTrials)
BlocksOut = BlocksIn;
for b = 1:numel(BlocksIn)
    bb = BlocksIn{b}(:);
    bb = bb(isfinite(bb) & bb >= 1 & bb <= nTrials);
    BlocksOut{b} = unique(bb, 'stable');
end
end

function [RateMeansByType, TrialCountsByType] = compute_rate_means_by_type(rate_4cm_3D, halls)
% RateMeansByType: [nUnits x nBins x 7], TrialCountsByType: [1 x 7]
nTypes = 7;
[~, nBins, nUnits] = size(rate_4cm_3D);
RateMeansByType   = NaN(nUnits, nBins, nTypes);
TrialCountsByType = zeros(1, nTypes);
halls = halls(:);
for TT = 1:nTypes
    idx = find(halls == TT);
    TrialCountsByType(TT) = numel(idx);
    if isempty(idx), continue; end
    Rm = mean(rate_4cm_3D(idx, :, :), 1, 'omitnan'); % [1 x nBins x nUnits]
    RateMeansByType(:, :, TT) = permute(Rm, [3 2 1]);
end
end

function counts4cm_3D = build_counts4cm_3D(raster_data, BinEdges4cm)
% counts4cm_3D : [nTrials x nBins x nUnits]
BinEdges4cm = BinEdges4cm(:)';
nBins   = numel(BinEdges4cm) - 1;
nUnits  = size(raster_data, 1);
nTrials = size(raster_data, 2);
counts4cm_3D = zeros(nTrials, nBins, nUnits, 'double');
for u = 1:nUnits
    for tr = 1:nTrials
        C = raster_data{u, tr};
        if isempty(C) || ~isfield(C, 'positions') || isempty(C.positions)
            continue;
        end
        rp = C.positions(:);
        counts4cm_3D(tr, :, u) = histcounts(rp, BinEdges4cm);
    end
end
end

function [spikes_all_session, spikes_by_block, block_windows, unit_summary, spikes_by_trial] = ...
    build_unfiltered_spike_times(KiloFolder, cluster_id_good, trans_beg, trans_end, Blocks, maxRHD_ts, varargin)

p = inputParser;
addParameter(p, 'SessionStart', [], @(x)isnumeric(x)&&isscalar(x));
addParameter(p, 'SessionEnd', [], @(x)isnumeric(x)&&isscalar(x));
addParameter(p, 'IncludePerTrial', true, @islogical);
parse(p, varargin{:});
opt = p.Results;

if isempty(opt.SessionStart), opt.SessionStart = min(trans_beg(:)); end
if isempty(opt.SessionEnd),   opt.SessionEnd   = maxRHD_ts;          end

% Load spikes
Fs = 30000; % Hz
try
    st_samp = double(readNPY(fullfile(KiloFolder,'spike_times.npy'))); % samples
    sc_all  = double(readNPY(fullfile(KiloFolder,'spike_clusters.npy'))); % cluster ids
catch ME
    error('build_unfiltered_spike_times:NPYReadFailed', 'Failed to read NPY files: %s', ME.message);
end
st_s = st_samp ./ Fs; % seconds

% Restrict to session window
session_mask = isfinite(st_s) & (st_s >= opt.SessionStart) & (st_s <= opt.SessionEnd) & isfinite(sc_all);
st_s = st_s(session_mask);
sc   = sc_all(session_mask);

% Prepare
nUnits  = numel(cluster_id_good);
nTrials = numel(trans_beg);
nBlocks = numel(Blocks);
spikes_all_session = cell(nUnits, 1);
spikes_by_block    = cell(nUnits, nBlocks);
if opt.IncludePerTrial
    spikes_by_trial = cell(nUnits, nTrials);
else
    spikes_by_trial = {};
end

% Block windows
block_windows = nan(nBlocks, 2);
for b = 1:nBlocks
    trials_b = Blocks{b}(:);
    trials_b = trials_b(isfinite(trials_b) & trials_b >= 1 & trials_b <= nTrials);
    if isempty(trials_b)
        block_windows(b,:) = [NaN NaN];
        continue;
    end
    block_windows(b,1) = min(trans_beg(trials_b));
    block_windows(b,2) = max(trans_end(trials_b));
end

% Collect spikes
unit_summary = struct();
unit_summary.cluster_id_good = cluster_id_good(:);
unit_summary.session_counts  = zeros(nUnits,1);
unit_summary.block_counts    = zeros(nUnits, nBlocks);
if opt.IncludePerTrial
    unit_summary.trial_counts = zeros(nUnits, nTrials);
end

for u = 1:nUnits
    cid = cluster_id_good(u);
    ts_u = st_s(sc == cid);

    % Session-wide
    spikes_all_session{u} = ts_u(:);
    unit_summary.session_counts(u) = numel(ts_u);

    % By block
    for b = 1:nBlocks
        t0 = block_windows(b,1);
        t1 = block_windows(b,2);
        if ~isfinite(t0) || ~isfinite(t1) || isempty(ts_u)
            spikes_by_block{u,b} = [];
            continue;
        end
        spikes_by_block{u,b} = ts_u(ts_u >= t0 & ts_u <= t1);
        unit_summary.block_counts(u,b) = numel(spikes_by_block{u,b});
    end

    % Per-trial (optional)
    if opt.IncludePerTrial
        for tr = 1:nTrials
            t0 = trans_beg(tr);
            t1 = trans_end(tr);
            if isempty(ts_u) || ~isfinite(t0) || ~isfinite(t1)
                spikes_by_trial{u,tr} = [];
                continue;
            end
            spikes_by_trial{u,tr} = ts_u(ts_u >= t0 & ts_u <= t1);
            unit_summary.trial_counts(u,tr) = numel(spikes_by_trial{u,tr});
        end
    end
end
end

function [rate_mean_halls, counts, Blocks] = analyze_blocks(rate_4cm_3D, halls, varargin)
% ANALYZE_BLOCKS -> per-block means by trial type
p = inputParser;
addParameter(p, 'Blocks', {12:174, 178:337, 341:520}, @iscell);
parse(p, varargin{:});
Blocks = p.Results.Blocks;

[nTrials, nBins, nUnits] = size(rate_4cm_3D);
halls = halls(:);
if numel(halls) < nTrials
    halls = [halls; NaN(nTrials - numel(halls), 1)];
end

Blocks = clip_blocks(Blocks, nTrials);
nBlocks = numel(Blocks);

rate_mean_halls = cell(1, nBlocks);
counts          = cell(1, nBlocks);

for b = 1:nBlocks
    [rate_mean_halls{b}, counts{b}] = compute_block_averages(...
        rate_4cm_3D, halls, Blocks{b}, nUnits, nBins);
end
end

function Blocks = clip_blocks(Blocks, nTrials)
% Clip block indices to valid trial range and remove invalid blocks
valid_blocks = false(1, numel(Blocks));
for b = 1:numel(Blocks)
    bb = Blocks{b}(:);
    bb = bb(isfinite(bb) & bb >= 1 & bb <= nTrials);
    Blocks{b} = unique(bb, 'stable');
    valid_blocks(b) = ~isempty(Blocks{b});
end
Blocks = Blocks(valid_blocks);
end

function [rate_mean, trial_counts] = compute_block_averages(rate_4cm_3D, halls, block_trials, nUnits, nBins)
% One block: rate_mean [nUnits x nBins x 7], trial_counts [1 x 7]
nTypes = 7;
rate_mean    = NaN(nUnits, nBins, nTypes);
trial_counts = zeros(1, nTypes);
if isempty(block_trials), return; end

block_data  = rate_4cm_3D(block_trials, :, :);
block_halls = halls(block_trials);

for TT = 1:nTypes
    idx = (block_halls == TT);
    trial_counts(TT) = sum(idx);
    if trial_counts(TT) == 0, continue; end
    type_data = block_data(idx, :, :);
    type_mean = mean(type_data, 1, 'omitnan'); % [1 x nBins x nUnits]
    rate_mean(:, :, TT) = squeeze(type_mean)';
end
end