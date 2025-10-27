function [interval_data, occupancy_4cm, halls, trans_beg, trans_end, maxRHD_ts] = process_behavioral_data(CsvFolder, varargin)
% PROCESS_BEHAVIORAL_DATA
% Drop-in replacement matching legacy I/O, with RS-sample occupancy and speed gating.
% Preserves:
%   - pos_x < 9 filter
%   - transitions by diff(pos_y) < -300 (now paired robustly)
%   - trimming of trans_beg/trans_end (applied to paired starts/ends together)
%   - halls extraction aligned to trimmed pairs
%   - 150 Hz resample and adjustable speed threshold (cm/s)
%
% Improvements:
%   - Occupancy computed from uniformly resampled samples (RS), summing dt per bin using only "fast" samples
%   - Optional bin-level median speed gating (bins with median speed <= threshold => NaN)
%   - Instantaneous speed via centered derivative (gradient)
%   - interval_data enriched with rs_bin_idx and fast RS indices

    % ---------- Parse options ----------
    p = inputParser;
    addParameter(p, 'SpeedThresh', 2.5, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
    addParameter(p, 'UseMedianSpeedMask', true, @(x)islogical(x)&&isscalar(x));
    parse(p, varargin{:});
    opt = p.Results;

    % ---------- Find CSV (folder or parent) ----------
    fname_candidates = {'CSVtableRHDts_Nans.csv','CSVtableRHDts_Nans'};
    search_paths = {CsvFolder};
    parent = fileparts(CsvFolder);
    if ~strcmp(parent, CsvFolder), search_paths{end+1} = parent; end

    fpath = '';
    for sp = 1:numel(search_paths)
        for fc = 1:numel(fname_candidates)
            cand = fullfile(search_paths{sp}, fname_candidates{fc});
            if exist(cand, 'file'), fpath = cand; break; end
        end
        if ~isempty(fpath), break; end
    end
    if isempty(fpath)
        error('CSVtableRHDts_Nans not found in %s or parent', CsvFolder);
    end

    % ---------- Load & scale ----------
    tbl_loc = readtable(fpath);
    tbl_loc.pos_y = tbl_loc.pos_y * 5.3;   % Convert to cm
    maxRHD_ts = max(tbl_loc.RHD_ts);

    % ---------- ORIGINAL FILTER ----------
    tbl_loc = tbl_loc(tbl_loc.pos_x < 9, :);

    % ---------- ORIGINAL TRANSITIONS (robust pairing + trimming) ----------
    trans = find(diff(tbl_loc.pos_y) < -300);  % indices in raw stream

    % Candidate start/end times from same indices (note the +/- 1)
    beg_candidates = tbl_loc.RHD_ts(trans + 1);
    end_candidates = tbl_loc.RHD_ts(trans);

    % Valid pairs require end > beg
    valid = isfinite(beg_candidates) & isfinite(end_candidates) & (end_candidates > beg_candidates);

    if any(valid)
        beg_candidates = beg_candidates(valid);
        end_candidates = end_candidates(valid);
        trans_valid_idx = trans(valid);  % keep aligned indices for halls

        % Inner trimming (drop edge artifacts) applied to paired vectors together
        inner = (end_candidates > min(beg_candidates)) & (beg_candidates < max(end_candidates));
        trans_beg = beg_candidates(inner);
        trans_end = end_candidates(inner);
        trans_idx_for_halls = trans_valid_idx(inner);  % aligned with trimmed pairs
    else
        trans_beg = [];
        trans_end = [];
        trans_idx_for_halls = [];
    end

    % HALLS extraction aligned to trimmed pairs
    if ~isempty(trans_idx_for_halls)
        halls = tbl_loc.pos_x(trans_idx_for_halls + 1);
    else
        halls = [];
    end

    % ---------- Early exit if no trials ----------
    if isempty(trans_beg) || isempty(trans_end)
        fprintf('[behavior] WARNING: No trials detected (transitions=%d). Check inputs.\n', numel(trans));
        interval_data = {};
        occupancy_4cm = zeros(0, numel(0:4:534)-1);
        return;
    end

    % ---------- Parameters ----------
    upsam_freq   = 150;               % Hz
    dt           = 1 / upsam_freq;    % seconds per RS sample
    Bin_edges    = 0:4:534;           % 4 cm bin edges
    nBins        = numel(Bin_edges) - 1;
    speed_thresh = opt.SpeedThresh;

    % ---------- Outputs ----------
    occupancy_4cm = NaN(length(trans_beg), nBins);
    interval_data = cell(1, length(trans_beg));

    % ---------- Process each trial ----------
    for i = 1:length(trans_beg)
        % Within-trial mask
        mask = (tbl_loc.RHD_ts >= trans_beg(i)) & (tbl_loc.RHD_ts <= trans_end(i));
        ts = tbl_loc.RHD_ts(mask);
        ps = tbl_loc.pos_y(mask);

        % Deduplicate timestamps to avoid interp1 issues
        if ~isempty(ts)
            [ts, uix] = unique(ts, 'stable');
            ps = ps(uix);
        end

        % Uniform resample
        ts_RS = trans_beg(i):dt:trans_end(i);
        ps_RS = interp1(ts, ps, ts_RS, 'linear');

        % Fill small gaps (including ends if needed)
        if any(~isfinite(ps_RS))
            ps_RS = fillmissing(ps_RS, 'linear', 'EndValues', 'nearest');
        end

        % Instantaneous speed (cm/s) via centered derivative
        v_inst    = gradient(ps_RS, ts_RS);
        fast_mask = v_inst > speed_thresh;  % forward-only, match legacy intent

        % RS sample-to-bin mapping
        rs_bin_idx = discretize(ps_RS, Bin_edges);

        % Occupancy from fast RS samples: sum dt per bin
        valid_fast = fast_mask & ~isnan(rs_bin_idx);
        if any(valid_fast)
            occ_counts = accumarray(rs_bin_idx(valid_fast)', dt * ones(nnz(valid_fast),1), [nBins,1], @sum, 0);
            occ_row = occ_counts';
        else
            occ_row = zeros(1, nBins);
        end

        % Median speed per bin (diagnostic; optional masking)
        valid_idx = ~isnan(rs_bin_idx);
        if any(valid_idx)
            bin_speed = accumarray(rs_bin_idx(valid_idx)', v_inst(valid_idx)', [nBins,1], @nanmedian, NaN);
        else
            bin_speed = nan(nBins,1);
        end

        % Apply bin-level median speed gate if enabled
        if opt.UseMedianSpeedMask
            low_speed_bins = bin_speed <= speed_thresh;
            occ_row(low_speed_bins) = NaN;
        end

        % Store occupancy row
        occupancy_4cm(i, :) = occ_row;

        % Build interval_data for downstream usage
        bin_centers       = Bin_edges(1:end-1) + 2;      % center of each 4 cm bin
        speed_idx_raster  = find(fast_mask);             % indices of fast RS samples (for raster gating)
        interval_data{i} = struct( ...
            'ts_RS', ts_RS, ...
            'ps_RS', ps_RS, ...
            'speed_idx_raster', speed_idx_raster, ...
            'valid_pos_idx', speed_idx_raster, ...     % same as fast_mask indices
            'rs_bin_idx', rs_bin_idx, ...
            'speed_bins', bin_speed(:)', ...           % per-bin median speed (cm/s)
            'bin_centers', bin_centers);
    end

    fprintf('[behavior] %s | trials=%d, bins=%d | SpeedThresh=%.3f | UseMedianSpeedMask=%d\n', ...
        fpath, numel(interval_data), size(occupancy_4cm,2), speed_thresh, opt.UseMedianSpeedMask);
end
