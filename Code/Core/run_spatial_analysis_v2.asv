function run_spatial_analysis_v2(animal_folder, kilo_folder, out_folder, varargin)
% RUN_SPATIAL_ANALYSIS_V2 (no fallbacks)
% - Computes fast-gated 4 cm binned rates and counts
% - Saves session-wide and per-block mean rate maps (by trial type)
% - Exports unfiltered spike times for FSC (session-wide, per-block, per-trial)
% - Computes total spike counts per unit/type/block
% - Optionally creates plots (DoPlots flag; default = false)
%
% Usage:
% run_spatial_analysis_v2(animal_folder, kilo_folder, out_folder, ...
%   'Blocks', {12:174, 178:337}, 'SpeedThresh', 2.5, ...
%   'UseMedianSpeedMask', true, 'DoPlots', false)

% ---------------- Configuration with overrides ----------------
cfg = struct();
cfg.SmoothingWin_cm    = 12;           % for plotting (Gaussian sigma in cm)
cfg.MinOccSec          = 0.0;         % NaN any occupancy bin below this (seconds); 0 disables
cfg.BinEdges4cm        = 0:4:534;      % spatial bin edges (cm)
cfg.Blocks             = {12:66, 67:120, 121:174, 178:230, 231:282, 283:337: 348:402, 403:450};
cfg.SavePNGs           = false;
cfg.PDFName            = 'AllUnits_SpatialAnalysis_V2.pdf';
cfg.TitlePrefix        = '[V2] ';
cfg.ShowTrialIDs       = false;
cfg.RasterMarkerSize   = 9;
cfg.DoPlots            = false;        % default off to save time
cfg.SpeedThresh        = 2.5;          % cm/s
cfg.UseMedianSpeedMask = true;         % propagate to process_behavioral_data
cfg.SaveFIGs           = false;
cfg.FIGDir             = '';
cfg.PDFContent         = 'image';      % 'image' or 'vector'

% Parse Name-Value overrides
if ~isempty(varargin)
    p = inputParser;
    addParameter(p, 'Blocks',            cfg.Blocks, @(x)iscell(x));
    addParameter(p, 'SmoothingWin',      cfg.SmoothingWin_cm, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
    addParameter(p, 'MinOccSec',         cfg.MinOccSec, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
    addParameter(p, 'BinEdges4cm',       cfg.BinEdges4cm, @(v)isnumeric(v)&&isvector(v)&&numel(v)>=2&&issorted(v));
    addParameter(p, 'SavePNGs',          cfg.SavePNGs, @islogical);
    addParameter(p, 'PDFName',           cfg.PDFName, @(s)ischar(s)||isstring(s));
    addParameter(p, 'TitlePrefix',       cfg.TitlePrefix, @(s)ischar(s)||isstring(s));
    addParameter(p, 'ShowTrialIDs',      cfg.ShowTrialIDs, @islogical);
    addParameter(p, 'RasterMarkerSize',  cfg.RasterMarkerSize, @(x)isnumeric(x)&&isscalar(x)&&x>0);
    addParameter(p, 'DoPlots',           cfg.DoPlots, @islogical);
    addParameter(p, 'SpeedThresh',       cfg.SpeedThresh, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
    addParameter(p, 'UseMedianSpeedMask',cfg.UseMedianSpeedMask, @(x)islogical(x)&&isscalar(x));
    addParameter(p, 'SaveFIGs',          cfg.SaveFIGs, @islogical);
    addParameter(p, 'FIGDir',            cfg.FIGDir, @(s)ischar(s)||isstring(s));
    addParameter(p, 'PDFContent',        cfg.PDFContent, @(s)ischar(s)||isstring(s));
    parse(p, varargin{:});

    cfg.Blocks             = p.Results.Blocks;
    cfg.SmoothingWin_cm    = p.Results.SmoothingWin;
    cfg.MinOccSec          = p.Results.MinOccSec;
    cfg.BinEdges4cm        = p.Results.BinEdges4cm(:)'; % ensure row
    cfg.SavePNGs           = p.Results.SavePNGs;
    cfg.PDFName            = char(p.Results.PDFName);
    cfg.TitlePrefix        = char(p.Results.TitlePrefix);
    cfg.ShowTrialIDs       = p.Results.ShowTrialIDs;
    cfg.RasterMarkerSize   = p.Results.RasterMarkerSize;
    cfg.DoPlots            = p.Results.DoPlots;
    cfg.SpeedThresh        = p.Results.SpeedThresh;
    cfg.UseMedianSpeedMask = p.Results.UseMedianSpeedMask;
    cfg.SaveFIGs           = p.Results.SaveFIGs;
    cfg.FIGDir             = char(p.Results.FIGDir);
    cfg.PDFContent         = char(p.Results.PDFContent);
else
    cfg.BinEdges4cm = cfg.BinEdges4cm(:)'; % ensure row
end

% ---------------- Setup output folder ----------------
if nargin < 3 || isempty(out_folder)
    out_folder = fullfile(kilo_folder, 'Derived_V2'); % per-region outputs
end
if ~exist(out_folder, 'dir'), mkdir(out_folder); end

% ---------------- Step 1: Behavior preprocessing ----------------
[interval_data, occupancy_4cm, halls, trans_beg, trans_end, maxRHD_ts] = ...
    process_behavioral_data(animal_folder, ...
                            'SpeedThresh',        cfg.SpeedThresh, ...
                            'UseMedianSpeedMask', cfg.UseMedianSpeedMask);

% Optional min-occupancy NaN-masking (fast-only bins from your function)
if ~isempty(occupancy_4cm) && isfinite(cfg.MinOccSec) && cfg.MinOccSec > 0
    occ_mask = occupancy_4cm < cfg.MinOccSec;
    occupancy_4cm(occ_mask) = NaN;
end

% Clip Blocks to valid trial indices
Blocks = clip_blocks_to_trials(cfg.Blocks, numel(trans_beg));

% ---------------- Step 2: Spike processing (fast-only rates) ----------------
[rate_4cm_3D, raster_data, cluster_id_good] = process_spike_data( ...
    kilo_folder, interval_data, occupancy_4cm, halls, trans_beg, trans_end, maxRHD_ts, ...
    'SpeedThresh', cfg.SpeedThresh, 'BinEdges4cm', cfg.BinEdges4cm);

[nTrials, nBins, nUnits] = size(rate_4cm_3D);
fprintf('[V2] Trials=%d, Bins(4cm)=%d, Units=%d\n', nTrials, nBins, nUnits);

% ---------------- Step 2.5: Compute spike counts per unit, per trial type, per block ----------------
% Output: unit_spike_counts_3D [nUnits x 7 x nBlocks]
% Counts total spikes (from raster_data positions) for each unit/type/block combination

nBlocks = numel(Blocks);
unit_spike_counts_3D = zeros(nUnits, 7, nBlocks);

for u = 1:nUnits
    for b = 1:nBlocks
        trials_in_block = Blocks{b}(:);
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

fprintf('[V2] Computed spike counts: [%d units x 7 types x %d blocks]\n', nUnits, nBlocks);

% ---------------- Step 3: Means by trial type (session-wide and per-block) ----------------
% Session-wide means
[RateMeansByType, TrialCountsByType] = compute_rate_means_by_type(rate_4cm_3D, halls);

% Per-block means and counts
RateMeansByTypeByBlock   = NaN(nUnits, nBins, 7, nBlocks);
TrialCountsByTypeByBlock = zeros(nBlocks, 7);
rate_mean_halls          = cell(1, nBlocks);

for b = 1:nBlocks
    tr_ix = Blocks{b}(:);
    tr_ix = tr_ix(isfinite(tr_ix) & tr_ix >= 1 & tr_ix <= nTrials);
    if isempty(tr_ix), continue; end

    halls_b = halls(:);
    halls_b = halls_b(1:nTrials);
    Rb = NaN(nUnits, nBins, 7);
    tbcounts = zeros(1,7);

    for tt = 1:7
        trials_tt = tr_ix(halls_b(tr_ix) == tt);
        if isempty(trials_tt), continue; end
        tbcounts(tt) = numel(trials_tt);
        % mean over trials (dimension 1) -> [1 x nBins x nUnits]
        m = nanmean(rate_4cm_3D(trials_tt, :, :), 1);
        % reshape to [nUnits x nBins]
        Rb(:, :, tt) = permute(m, [3 2 1]);
    end

    RateMeansByTypeByBlock(:,:,:,b) = Rb;
    TrialCountsByTypeByBlock(b,:)   = tbcounts;
    rate_mean_halls{b}              = Rb; % [nUnits x nBins x 7]
end

% ---------------- Step 4: 3D 4 cm spike counts (fast-only) ----------------
counts4cm_3D = build_counts4cm_3D(raster_data, cfg.BinEdges4cm); % [trials x bins x units]

% ---------------- Step 5: Unfiltered spike times for FSC (no speed gating) ----------------
[spikes_all_session, spikes_by_block, block_windows, unit_summary, spikes_by_trial] = ...
    build_unfiltered_spike_times(kilo_folder, cluster_id_good, trans_beg, trans_end, Blocks, maxRHD_ts, ...
                                 'SessionStart', trans_beg(1), ...
                                 'SessionEnd',   maxRHD_ts, ...
                                 'IncludePerTrial', true);

% ---------------- Step 6: Create plots (optional) ----------------
if cfg.DoPlots
    create_all_plots(rate_mean_halls, raster_data, halls, cluster_id_good, out_folder, ...
        'Blocks',          Blocks, ...
        'BinEdges',        cfg.BinEdges4cm, ...
        'SmoothingWin',    cfg.SmoothingWin_cm, ...
        'SavePNGs',        cfg.SavePNGs, ...
        'PDFName',         cfg.PDFName, ...
        'PDFContent',      cfg.PDFContent, ...
        'TitlePrefix',     cfg.TitlePrefix, ...
        'ShowTrialIDs',    cfg.ShowTrialIDs, ...
        'RasterMarkerSize',cfg.RasterMarkerSize, ...
        'SaveFIGs',        cfg.SaveFIGs, ...
        'FIGDir',          fullfile(out_folder, 'FIGs'),...
        'SpikeCountsByTypeByBlock', unit_spike_counts_3D);  % NEW: Pass spike counts
else
    fprintf('[V2] Skipping plot creation (DoPlots=false)\n');
end

% ---------------- Step 7: Save outputs ----------------
% Spatial analysis artifacts (fast-only)
try
    save(fullfile(out_folder, 'spatial_analysis_v2.mat'), ...
        'cfg', 'occupancy_4cm', 'halls', 'Blocks', 'trans_beg', 'trans_end', ...
        'rate_4cm_3D', 'raster_data', 'cluster_id_good', 'counts4cm_3D', ...
        'RateMeansByType', 'TrialCountsByType', ...
        'RateMeansByTypeByBlock', 'TrialCountsByTypeByBlock', ...
        'unit_spike_counts_3D', ...  % NEW: total spike counts per unit/type/block
        'spikes_all_session', 'spikes_by_block', 'block_windows', 'unit_summary', ...
        'spikes_by_trial', '-v7.3');
    fprintf('[V2] Saved: %s\n', fullfile(out_folder, 'spatial_analysis_v2.mat'));
% catch ME
%     warning('[V2] Failed to save outputs: %s', ME.message);
end

% FSC spike times (unfiltered, absolute times)
save(fullfile(out_folder, 'fsc_spikes_unfiltered.mat'), ...
    'spikes_all_session', 'spikes_by_block', 'block_windows', 'spikes_by_trial', ...
    'unit_summary', 'cluster_id_good', 'Blocks', 'trans_beg', 'trans_end');

fprintf('[V2] Done. Outputs saved in %s\n', out_folder);
end

% ---------------- Local helpers ----------------
function BlocksOut = clip_blocks_to_trials(BlocksIn, nTrials)
BlocksOut = BlocksIn;
for b = 1:numel(BlocksIn)
    bb = BlocksIn{b}(:);
    bb = bb(isfinite(bb) & bb >= 1 & bb <= nTrials);
    BlocksOut{b} = unique(bb, 'stable');
end
end

function [RateMeansByType, TrialCountsByType] = compute_rate_means_by_type(rate_4cm_3D, halls)
% Compute mean rates per trial type across all trials (session-wide)
nTypes = 7;
[nTrials, nBins, nUnits] = size(rate_4cm_3D);
RateMeansByType   = NaN(nUnits, nBins, nTypes);
TrialCountsByType = zeros(1, nTypes);
halls = halls(:);
if numel(halls) < nTrials
    halls = [halls; NaN(nTrials - numel(halls), 1)];
end
for tt = 1:nTypes
    tr_ix = find(halls(1:nTrials) == tt);
    TrialCountsByType(tt) = numel(tr_ix);
    if isempty(tr_ix), continue; end
    m = nanmean(rate_4cm_3D(tr_ix, :, :), 1);     % [1 x nBins x nUnits]
    RateMeansByType(:,:,tt) = permute(m, [3 2 1]); % [nUnits x nBins]
end
end

function counts4cm_3D = build_counts4cm_3D(raster_data, BinEdges4cm)
% Build 3D 4 cm spike counts from fast-only raster_data.
% Output: counts4cm_3D : [nTrials x nBins x nUnits] (double)
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
        rp = C.positions(:); % cm, fast-only spikes
        counts4cm_3D(tr, :, u) = histcounts(rp, BinEdges4cm);
    end
end
end

function [spikes_all_session, spikes_by_block, block_windows, unit_summary, spikes_by_trial] = ...
    build_unfiltered_spike_times(KiloFolder, cluster_id_good, trans_beg, trans_end, Blocks, maxRHD_ts, varargin)
% BUILD_UNFILTERED_SPIKE_TIMES
% Collect all spike times (no speed gating) for curated good units:
% - across the session window
% - per block (union of trials)
% - optionally, per-trial (absolute times)

p = inputParser;
addParameter(p, 'SessionStart', [], @(x)isnumeric(x)&&isscalar(x));
addParameter(p, 'SessionEnd',   [], @(x)isnumeric(x)&&isscalar(x));
addParameter(p, 'IncludePerTrial', true, @islogical);
parse(p, varargin{:});
opt = p.Results;

if isempty(opt.SessionStart), opt.SessionStart = min(trans_beg(:)); end
if isempty(opt.SessionEnd),   opt.SessionEnd   = maxRHD_ts;          end

% Load spikes
Fs = 30000; % Hz
st_samp = double(readNPY(fullfile(KiloFolder,'spike_times.npy')));     % samples
sc_all  = double(readNPY(fullfile(KiloFolder,'spike_clusters.npy')));  % per-spike cluster id
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
unit_summary = struct('session_counts', zeros(nUnits,1), 'block_counts', zeros(nUnits, nBlocks), ...
                      'trial_counts', zeros(nUnits, nTrials));
if opt.IncludePerTrial
    spikes_by_trial = cell(nUnits, nTrials);
else
    spikes_by_trial = {};
end

% Compute block windows from trial ranges
block_windows = nan(nBlocks, 2);
for b = 1:nBlocks
    tix = Blocks{b}(:);
    tix = tix(isfinite(tix) & tix >= 1 & tix <= nTrials);
    if isempty(tix)
        block_windows(b,:) = [NaN NaN];
    else
        block_windows(b,:) = [min(trans_beg(tix)), max(trans_end(tix))];
    end
end

% Build outputs
for u = 1:nUnits
    cid = cluster_id_good(u);
    ts_u = st_s(sc == cid);

    % Session
    spikes_all_session{u} = ts_u(:);
    unit_summary.session_counts(u) = numel(spikes_all_session{u});

    % Blocks
    for b = 1:nBlocks
        t0 = block_windows(b,1); t1 = block_windows(b,2);
        if ~isfinite(t0) || ~isfinite(t1)
            spikes_by_block{u,b} = [];
            continue;
        end
        spikes_by_block{u,b} = ts_u(ts_u >= t0 & ts_u <= t1);
        unit_summary.block_counts(u,b) = numel(spikes_by_block{u,b});
    end

    % Trials (optional)
    if opt.IncludePerTrial
        for tr = 1:nTrials
            t0 = trans_beg(tr); t1 = trans_end(tr);
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