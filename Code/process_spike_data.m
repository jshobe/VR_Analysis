function [rate_4cm_3D, raster_data, cluster_id_good] = process_spike_data( ...
    KiloFolder, interval_data, occupancy_4cm, halls, trans_beg, trans_end, maxRHD_ts)
% PROCESS_SPIKE_DATA
% Accurate spike processing with curated GoodUnit CSV, RS-sample speed gating, and 4 cm binning.
%
% Inputs:
%   KiloFolder    : path to region folder containing Kilosort outputs
%   interval_data : 1xN cell array per trial with fields:
%                   - ts_RS (seconds), ps_RS (cm) resampled uniformly
%   occupancy_4cm : [nTrials x nBins] seconds per bin, NaN for low-speed bins
%   halls         : [nTrials x 1] trial type codes (unused here)
%   trans_beg     : [nTrials x 1] trial start times (seconds)
%   trans_end     : [nTrials x 1] trial end times (seconds)
%   maxRHD_ts     : maximum behavior timestamp to restrict spikes (seconds)
%
% Outputs:
%   rate_4cm_3D   : [nTrials x nBins x nUnits] firing rates (Hz), NaN for invalid bins
%   raster_data   : {nUnits x nTrials} cells with fields:
%                   - times     (seconds relative to trial start)
%                   - positions (cm at RS samples for kept spikes)
%   cluster_id_good : [nUnits x 1] curated good unit IDs (CSV order preserved)
%
% Notes:
%   - Requires UnitMetrics/VR##_GoodUnitInfo.csv (first column = ClusterID). No fallback used.
%   - Raster gating uses instantaneous speed from gradient(ps_RS, ts_RS) > 2.5 cm/s.
%   - Rate maps bin raw spike positions into 4 cm edges: 0:4:534.
%   - Occupancy_4cm should be computed from fast RS samples and NaN-masked by bin median speed.

    % ---------------- Load spikes ----------------
    Fs = 30000; % Hz
    try
        st_samp = double(readNPY(fullfile(KiloFolder,'spike_times.npy')));    % samples
        sc_all  = double(readNPY(fullfile(KiloFolder,'spike_clusters.npy'))); % per-spike cluster id
    catch ME
        error('process_spike_data:NPYReadFailed', 'Failed to read NPY files: %s', ME.message);
    end
    st_s = st_samp ./ Fs; % seconds

    % Restrict to behavior window and valid clusters
    mask_behavior = isfinite(st_s) & (st_s <= maxRHD_ts) & isfinite(sc_all);
    st_s = st_s(mask_behavior);
    sc   = sc_all(mask_behavior);

    % Drop noise cluster 0 if present
    sc(sc == 0) = [];

    sc_unique = unique(sc(:));
    if isempty(sc_unique)
        warning('process_spike_data:NoSpikesInBehavior', 'No spikes within behavior window.');
        rate_4cm_3D = []; raster_data = cell(0,0); cluster_id_good = [];
        return;
    end

    % ---------------- Read curated GoodUnit CSV ----------------
    animal_name = '';
    try
        % Extract VR## animal name from path
        path_parts = strsplit(KiloFolder, filesep);
        for p = 1:numel(path_parts)
            if ~isempty(regexp(path_parts{p}, '^VR\d+$', 'once'))
                animal_name = path_parts{p};
                break;
            end
        end
    catch
        % leave animal_name empty
    end

    if isempty(animal_name)
        error('process_spike_data:AnimalNameParse', ...
              'Could not extract VR## animal name from path: %s', KiloFolder);
    end

    good_csv_path = fullfile(KiloFolder, 'UnitMetrics', sprintf('%s_GoodUnitInfo.csv', animal_name));
    if ~exist(good_csv_path, 'file')
        error('process_spike_data:GoodCSVMissing', ...
              'Required curated good unit file not found: %s', good_csv_path);
    end

    try
        Tgood = readtable(good_csv_path);
    catch ME
        error('process_spike_data:GoodCSVReadFailed', 'Error reading %s: %s', good_csv_path, ME.message);
    end

    if width(Tgood) < 1 || height(Tgood) < 1
        error('process_spike_data:GoodCSVEmpty', ...
              'Curated good unit CSV has no rows/columns: %s', good_csv_path);
    end

    % First column holds ClusterIDs (CSV order preserved)
    good_ids_col = Tgood{:,1};
    if iscell(good_ids_col),   good_ids_col = str2double(string(good_ids_col)); end
    if isstring(good_ids_col), good_ids_col = str2double(good_ids_col); end
    cluster_id_good = good_ids_col(:);
    cluster_id_good = cluster_id_good(isfinite(cluster_id_good));

    if isempty(cluster_id_good)
        error('process_spike_data:GoodIDsInvalid', ...
              'First column of %s produced no valid ClusterIDs.', good_csv_path);
    end

    % Keep only IDs that actually appear in spike_clusters within behavior window
    present_mask = ismember(cluster_id_good, sc_unique);
    cluster_id_good = cluster_id_good(present_mask);

    if isempty(cluster_id_good)
        error('process_spike_data:NoGoodUnitsPresent', ...
              'None of the curated good units are present in spike_clusters for this session.');
    end

    fprintf('[process_spike_data] Using %d curated good units from %s\n', ...
        numel(cluster_id_good), good_csv_path);

    % ---------------- Validate inputs ----------------
    Bin_edges = 0:4:534;
    nBins   = numel(Bin_edges) - 1;
    nTrials = numel(trans_beg);
    nUnits  = numel(cluster_id_good);

    if size(occupancy_4cm,1) ~= nTrials || size(occupancy_4cm,2) ~= nBins
        error('process_spike_data:OccupancySize', ...
            'occupancy_4cm size mismatch. Expected [%d x %d]. Got [%d x %d].', ...
            nTrials, nBins, size(occupancy_4cm,1), size(occupancy_4cm,2));
    end

    % ---------------- Preallocate ----------------
    rate_4cm_3D = NaN(nTrials, nBins, nUnits, 'double');
    raster_data = cell(nUnits, nTrials);

    % ---------------- Main loop ----------------
    speed_thresh = 2.5; % cm/s (instantaneous RS-sample speed for raster gating)

    for u = 1:nUnits
        cid = cluster_id_good(u);
        unit_spikes = st_s(sc == cid);

        % Pre-fill empty rasters for this unit
        for tr = 1:nTrials
            raster_data{u,tr} = struct('times', [], 'positions', []);
        end

        if isempty(unit_spikes)
            % No spikes for this unit within behavior window
            for tr = 1:nTrials
                occ_row = occupancy_4cm(tr, :);
                rate = zeros(1, nBins);
                rate(~isfinite(occ_row)) = NaN;
                rate_4cm_3D(tr, :, u) = rate;
            end
            continue;
        end

        for tr = 1:nTrials
            t0 = trans_beg(tr); t1 = trans_end(tr);
            id = interval_data{tr};
            if isempty(id) || ~isfield(id,'ts_RS') || ~isfield(id,'ps_RS') ...
                    || isempty(id.ts_RS) || isempty(id.ps_RS)
                continue;
            end

            ts_RS = id.ts_RS(:);
            ps_RS = id.ps_RS(:);
            N = numel(ts_RS);
            occ_row = occupancy_4cm(tr, :);

            % Spikes within trial
            in_trial = (unit_spikes >= t0) & (unit_spikes <= t1);
            ts_tr = unit_spikes(in_trial);
            if isempty(ts_tr)
                rate = zeros(1, nBins);
                rate(~isfinite(occ_row)) = NaN;
                rate_4cm_3D(tr, :, u) = rate;
                continue;
            end

            % Map spikes -> nearest RS sample index
            idx = rmmissing(interp1(ts_RS, (1:N)', ts_tr, 'nearest', 'extrap'));
            if isempty(idx)
                rate = zeros(1, nBins);
                rate(~isfinite(occ_row)) = NaN;
                rate_4cm_3D(tr, :, u) = rate;
                continue;
            end
            idx = min(max(round(idx), 1), N);

            % Instantaneous speed at RS samples (centered derivative)
            v_inst = gradient(ps_RS, ts_RS); % cm/s
            fast_mask = v_inst > speed_thresh;

            % Raster gating: keep spikes whose nearest RS sample is fast
            keep = fast_mask(idx);
            if ~any(keep)
                rate = zeros(1, nBins);
                rate(~isfinite(occ_row)) = NaN;
                rate_4cm_3D(tr, :, u) = rate;
                continue;
            end

            idx_keep = idx(keep);

            % Raster data: times relative to trial start, positions at RS samples
            raster_times     = ts_tr(keep) - t0;
            raster_positions = ps_RS(idx_keep);
            raster_data{u, tr} = struct('times', raster_times, 'positions', raster_positions);

            % Spike binning for rate maps: edges over raw positions
            if isempty(raster_positions)
                spike_counts = zeros(1, nBins);
            else
                spike_counts = histcounts(raster_positions, Bin_edges);
            end

            % Firing rate (Hz): spikes per second using occupancy_4cm
            rate = spike_counts ./ occ_row;
            rate(~isfinite(rate)) = NaN;
            rate_4cm_3D(tr, :, u) = rate;
        end
    end

    % ---------------- Diagnostics (optional) ----------------
    % Sanity: no negative rates
    if any(rate_4cm_3D(:) < 0 & isfinite(rate_4cm_3D(:)))
        warning('process_spike_data:NegativeRates', ...
            'Negative firing rates detected; check occupancy and binning.');
    end

end