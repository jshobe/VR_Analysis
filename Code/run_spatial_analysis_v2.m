function run_spatial_analysis_v2(animal_folder, kilo_folder, out_folder, varargin)
% RUN_SPATIAL_ANALYSIS_V2
% Driver that:
%   - runs the spatial analysis using your existing speed threshold (no override)
%   - saves 3D 4 cm data structures (rates and counts)
%   - builds and saves unfiltered spike times for FSC (session-wide and by block)
%   - creates PDFs using your existing plotting pipeline
%
% Usage:
%   run_spatial_analysis_v2(animal_folder, kilo_folder, out_folder)
%   run_spatial_analysis_v2(..., 'Blocks', {12:174, 178:337}, 'SmoothingWin', 12)
%
% Inputs:
%   animal_folder : folder containing behavior artifacts (CSVtableRHDts_Nans.*)
%   kilo_folder   : folder containing spike_times.npy / spike_clusters.npy (region folder, e.g., PPC)
%   out_folder    : output folder for PDFs and MAT files
%
% Name-Value Overrides (optional; no speed threshold override here):
%   'Blocks'        : 1xB cell array of trial-index vectors per block (default: {12:174, 178:337})
%   'SmoothingWin'  : Gaussian sigma in cm for plotting (default: 12)
%   'MinOccSec'     : minimum fast occupancy per bin in seconds (NaN bins below; default: 0.10)
%   'BinEdges4cm'   : bin edges for 4 cm bins (default: 0:4:534)
%   'SavePNGs'      : save PNGs in addition to the PDF (default: false)
%   'PDFName'       : output PDF filename (default: 'AllUnits_SpatialAnalysis_V2.pdf')
%   'TitlePrefix'   : prefix for plot titles (default: '[V2] ')
%   'ShowTrialIDs'  : show trial IDs on plots (default: false)
%   'RasterMarkerSize' : marker size for rasters (default: 9)

    % ---------------- Configuration with overrides ----------------
    cfg = struct();
    cfg.SmoothingWin_cm   = 12;
    cfg.MinOccSec         = 0.10;
    cfg.BinEdges4cm       = 0:4:534;
    cfg.Blocks            = {12:174, 178:337};
    cfg.SavePNGs          = false;
    cfg.PDFName           = 'AllUnits_SpatialAnalysis_V2.pdf';
    cfg.TitlePrefix       = '[V2] ';
    cfg.ShowTrialIDs      = false;
    cfg.RasterMarkerSize  = 9;

    % Parse Name-Value overrides
    if ~isempty(varargin)
        p = inputParser;
        addParameter(p, 'Blocks', cfg.Blocks, @(x)iscell(x));
        addParameter(p, 'SmoothingWin', cfg.SmoothingWin_cm, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
        addParameter(p, 'MinOccSec', cfg.MinOccSec, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
        addParameter(p, 'BinEdges4cm', cfg.BinEdges4cm, @(v)isvector(v)&&issorted(v));
        addParameter(p, 'SavePNGs', cfg.SavePNGs, @islogical);
        addParameter(p, 'PDFName', cfg.PDFName, @(s)ischar(s)||isstring(s));
        addParameter(p, 'TitlePrefix', cfg.TitlePrefix, @(s)ischar(s)||isstring(s));
        addParameter(p, 'ShowTrialIDs', cfg.ShowTrialIDs, @islogical);
        addParameter(p, 'RasterMarkerSize', cfg.RasterMarkerSize, @(x)isnumeric(x)&&isscalar(x)&&x>0);
        parse(p, varargin{:});

        cfg.Blocks            = p.Results.Blocks;
        cfg.SmoothingWin_cm   = p.Results.SmoothingWin;
        cfg.MinOccSec         = p.Results.MinOccSec;
        cfg.BinEdges4cm       = p.Results.BinEdges4cm(:)';
        cfg.SavePNGs          = p.Results.SavePNGs;
        cfg.PDFName           = char(p.Results.PDFName);
        cfg.TitlePrefix       = char(p.Results.TitlePrefix);
        cfg.ShowTrialIDs      = p.Results.ShowTrialIDs;
        cfg.RasterMarkerSize  = p.Results.RasterMarkerSize;
    else
        cfg.BinEdges4cm = cfg.BinEdges4cm(:)'; % ensure row
    end

    % ---------------- Setup output folder ----------------
    if nargin < 3 || isempty(out_folder)
        out_folder = fullfile(kilo_folder, 'Derived_V2'); % per-region outputs
    end
    if ~exist(out_folder, 'dir'), mkdir(out_folder); end

    % ---------------- Step 1: Behavior preprocessing (no override) ----------------
    % Use your existing process_behavioral_data as-is, with its internal speed threshold.
    [interval_data, occupancy_4cm, halls, trans_beg, trans_end, maxRHD_ts] = ...
        process_behavioral_data(animal_folder);

    % Optional minimum-occupancy stabilization (fast-only bins from your function)
    if ~isempty(occupancy_4cm) && isfinite(cfg.MinOccSec) && cfg.MinOccSec > 0
        occ_mask = occupancy_4cm < cfg.MinOccSec;
        occupancy_4cm(occ_mask) = NaN;
    end

    % Clip Blocks to valid trial indices
    Blocks = clip_blocks_to_trials(cfg.Blocks, numel(trans_beg));

    % ---------------- Step 2: Spike processing (fast-only rates, unchanged) ----------------
    [rate_4cm_3D, raster_data, cluster_id_good] = process_spike_data( ...
        kilo_folder, interval_data, occupancy_4cm, halls, trans_beg, trans_end, maxRHD_ts);

    [nTrials, nBins, nUnits] = size(rate_4cm_3D);
    fprintf('[V2] Trials=%d, Bins(4cm)=%d, Units=%d\n', nTrials, nBins, nUnits);

    % ---------------- Step 3: Aggregate mean rates by trial type ----------------
    [RateMeansByType, TrialCountsByType] = compute_rate_means_by_type(rate_4cm_3D, halls);
    % Prepare for plotting: per-block cell; using global means per type for all blocks.
    rate_mean_halls = cell(1, numel(Blocks));
    rate_mean_halls(:) = {RateMeansByType}; % [nUnits x nBins x 7] per block

    % ---------------- Step 4: Build 3D 4 cm spike counts (fast-only) ----------------
    counts4cm_3D = build_counts4cm_3D(raster_data, cfg.BinEdges4cm); % [trials x bins x units]

    % ---------------- Step 5: Unfiltered spike times for FSC (no speed gating) ----------------
    [spikes_all_session, spikes_by_block, block_windows, unit_summary, spikes_by_trial] = ...
        build_unfiltered_spike_times(kilo_folder, cluster_id_good, trans_beg, trans_end, Blocks, maxRHD_ts, ...
        'SessionStart', trans_beg(1), ...
        'SessionEnd',   maxRHD_ts, ...
        'IncludePerTrial', true);

    % ---------------- Step 6: Create plots ----------------
    create_all_plots(rate_mean_halls, raster_data, halls, cluster_id_good, out_folder, ...
        'Blocks',        Blocks, ...
        'BinEdges',      cfg.BinEdges4cm, ...
        'SmoothingWin',  cfg.SmoothingWin_cm, ...
        'SavePNGs',      cfg.SavePNGs, ...
        'PDFName',       cfg.PDFName, ...
        'TitlePrefix',   cfg.TitlePrefix, ...
        'ShowTrialIDs',  cfg.ShowTrialIDs, ...
        'RasterMarkerSize', cfg.RasterMarkerSize);

    % ---------------- Step 7: Save outputs ----------------
    % Spatial analysis artifacts (fast-only)
    save(fullfile(out_folder, 'spatial_analysis_v2.mat'), ...
        'rate_4cm_3D', 'counts4cm_3D', 'RateMeansByType', 'TrialCountsByType', ...
        'occupancy_4cm', 'halls', 'cluster_id_good', 'trans_beg', 'trans_end', ...
        'Blocks', 'cfg');

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
% Compute mean rates per trial type (1..7) from [trials x bins x units].
% Outputs:
%   RateMeansByType   : [nUnits x nBins x 7]
%   TrialCountsByType : [1 x 7]

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
        RateMeansByType(:, :, TT) = permute(Rm, [3 2 1]); % -> [nUnits x nBins]
    end
end

function counts4cm_3D = build_counts4cm_3D(raster_data, BinEdges4cm)
% Build 3D 4 cm spike counts from fast-only raster_data.
% Output:
%   counts4cm_3D : [nTrials x nBins x nUnits] (double)

    BinEdges4cm = BinEdges4cm(:)';
    nBins = numel(BinEdges4cm) - 1;

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
% Collects all spike times (no speed gating) for curated good units:
%   - across the behavioral session window
%   - broken out by block (union of trials in each block)
%   - optionally, per-trial breakout (absolute times)
%
% Inputs:
%   KiloFolder       : path to folder containing spike_times.npy / spike_clusters.npy
%   cluster_id_good  : [nUnits x 1] curated unit IDs
%   trans_beg        : [nTrials x 1] trial start times (seconds)
%   trans_end        : [nTrials x 1] trial end times (seconds)
%   Blocks           : 1xB cell, each a vector of trial indices for that block
%   maxRHD_ts        : scalar, maximum behavior timestamp (seconds)
%
% Name-Value Options:
%   'SessionStart'   : default = min(trans_beg)
%   'SessionEnd'     : default = maxRHD_ts
%   'IncludePerTrial': true/false, also return per-trial spikes (default: true)
%
% Outputs:
%   spikes_all_session : {nUnits x 1} absolute spike times in [SessionStart, SessionEnd]
%   spikes_by_block    : {nUnits x nBlocks} absolute spike times for each block window
%   block_windows      : [nBlocks x 2] start/end times (seconds) computed from trials in each block
%   unit_summary       : struct with counts per unit (session, per-block, per-trial)
%   spikes_by_trial    : {nUnits x nTrials} absolute spike times per trial (if IncludePerTrial=true)

    % ---------------- Options ----------------
    p = inputParser;
    addParameter(p, 'SessionStart', [], @(x)isnumeric(x)&&isscalar(x));
    addParameter(p, 'SessionEnd', [], @(x)isnumeric(x)&&isscalar(x));
    addParameter(p, 'IncludePerTrial', true, @islogical);
    parse(p, varargin{:});
    opt = p.Results;

    if isempty(opt.SessionStart)
        opt.SessionStart = min(trans_beg(:));
    end
    if isempty(opt.SessionEnd)
        opt.SessionEnd = maxRHD_ts;
    end

    % ---------------- Load spikes ----------------
    Fs = 30000; % Hz
    try
        st_samp = double(readNPY(fullfile(KiloFolder,'spike_times.npy')));    % samples
        sc_all  = double(readNPY(fullfile(KiloFolder,'spike_clusters.npy'))); % per-spike cluster id
    catch ME
        error('build_unfiltered_spike_times:NPYReadFailed', 'Failed to read NPY files: %s', ME.message);
    end
    st_s = st_samp ./ Fs; % seconds

    % Restrict to session window
    session_mask = isfinite(st_s) & (st_s >= opt.SessionStart) & (st_s <= opt.SessionEnd) & isfinite(sc_all);
    st_s = st_s(session_mask);
    sc   = sc_all(session_mask);

    % ---------------- Prepare ----------------
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

    % Compute block windows from trial ranges
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

    % ---------------- Collect spikes ----------------
    unit_summary = struct();
    unit_summary.cluster_id_good = cluster_id_good(:);
    unit_summary.session_counts  = zeros(nUnits,1);
    unit_summary.block_counts    = zeros(nUnits, nBlocks);
    if opt.IncludePerTrial
        unit_summary.trial_counts = zeros(nUnits, nTrials);
    end

    for u = 1:nUnits
        cid = cluster_id_good(u);
        ts_u = st_s(sc == cid); % all spikes for this unit within session window

        % Session-wide
        spikes_all_session{u} = ts_u(:);
        unit_summary.session_counts(u) = numel(ts_u);

        % By block (absolute times)
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

        % Optional: per-trial (absolute times)
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