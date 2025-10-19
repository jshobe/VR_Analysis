function select_vr_animal_plots(varargin)
% SELECT_VR_ANIMAL_PLOTS
% Main driver: processes behavior once per animal, then analyzes spikes per region
%
% Key Options:
%   'AnimalFolder'   : path to VR## folder (or '' to select via GUI)
%   'Regions'        : {'PPC','VC'} - brain regions to analyze
%   'Blocks'         : {12:174, 178:337, 341:520} - trial blocks
%   'Overwrite'      : false - recompute cached data
%   'SmoothingWin'   : 8 - Gaussian sigma for rate smoothing (in cm)
%   'ShowTrialIDs'   : false - show trial numbers on raster
%   'RasterMarkerSize': 2 - size of raster dots
%
% Notes:
%   - V2 FSC + 3D 4cm analysis is invoked per region via run_spatial_analysis_v2.
%   - Ensure run_spatial_analysis_v2.m is on your MATLAB path.

    % Parse inputs
    p = inputParser;
    addParameter(p, 'BaseFolder', 'Z:\Justin\VR mice', @(s)ischar(s)||isstring(s));
    addParameter(p, 'AnimalFolder', '', @(s)ischar(s)||isstring(s));
    addParameter(p, 'Regions', {'PPC','VC'}, @iscell);
    addParameter(p, 'Blocks', {12:174, 178:337, 341:520}, @iscell);
    addParameter(p, 'Overwrite', false, @islogical);
    addParameter(p, 'SaveIntermediates', true, @islogical);
    addParameter(p, 'FiguresVisible', 'off', @ischar);
    addParameter(p, 'SmoothingWin', 8, @(x)isnumeric(x)&&x>=0); % in cm, not bins
    addParameter(p, 'SavePNGs', false, @islogical);
    addParameter(p, 'PDFName', 'AllUnits_SpatialAnalysis.pdf', @ischar);
    addParameter(p, 'PDFContent', 'image', @ischar);
    addParameter(p, 'ShowTrialIDs', false, @islogical);
    addParameter(p, 'RasterMarkerSize', 2, @(v)isnumeric(v)&&v>0);
    parse(p, varargin{:});
    opts = p.Results;

    % Set figure visibility
    set(0, 'DefaultFigureVisible', opts.FiguresVisible);
    cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', 'on'));

    % Get animal folder
    animal_folder = get_animal_folder(opts.BaseFolder, opts.AnimalFolder);
    if isempty(animal_folder), return; end

    derived_dir = fullfile(animal_folder, 'Derived');
    if ~exist(derived_dir, 'dir'), mkdir(derived_dir); end

    log_msg('Animal: %s', animal_folder);
    log_msg('Regions: %s', strjoin(opts.Regions, ', '));
    log_msg('Blocks: %s', format_blocks(opts.Blocks));

    % Load or compute behavior (legacy cache path)
    [interval_data, occupancy_4cm, halls, trans_beg, trans_end, maxRHD_ts] = ...
        load_behavior_data(animal_folder, derived_dir, opts.Overwrite, opts.SaveIntermediates);

    % Process each region (legacy plots + V2 FSC/3D 4cm)
    for r = 1:numel(opts.Regions)
        region = opts.Regions{r};
        region_folder = fullfile(animal_folder, region);

        if ~isfolder(region_folder)
            log_msg('Skipping %s (not found)', region);
            continue;
        end

        log_msg('Processing %s (legacy)...', region);
        process_region(region_folder, interval_data, occupancy_4cm, halls, ...
            trans_beg, trans_end, maxRHD_ts, animal_folder, opts);

        % V2: FSC + 3D 4cm analysis (per region)
        try
            out_folder_v2 = fullfile(region_folder, 'Derived_V2'); % keep V2 outputs with the region
            if ~exist(out_folder_v2, 'dir'), mkdir(out_folder_v2); end

            % You can pass your Blocks and plotting overrides through to V2
            run_spatial_analysis_v2(animal_folder, region_folder, out_folder_v2, ...
                'Blocks', opts.Blocks, ...
                'SmoothingWin', opts.SmoothingWin, ...
                'SavePNGs', opts.SavePNGs, ...
                'PDFName', opts.PDFName, ...
                'TitlePrefix', sprintf('%s | %s | ', get_name(animal_folder), get_name(region_folder)), ...
                'ShowTrialIDs', opts.ShowTrialIDs, ...
                'RasterMarkerSize', opts.RasterMarkerSize);

            log_msg('[V2] FSC + 3D 4cm analysis finished for %s. See %s', region, out_folder_v2);
        catch ME
            log_msg('[V2] Run failed for %s: %s', region, ME.message);
        end
    end

    log_msg('Done');
end



%% ==================== Helper Functions ====================

function animal_folder = get_animal_folder(base_folder, animal_folder_input)
    % Get animal folder from input or GUI selection
    if isempty(animal_folder_input)
        if ~isfolder(base_folder)
            base_folder = pwd;
        end
        animal_folder = uigetdir(base_folder, 'Select VR animal folder');
        if isequal(animal_folder, 0)
            log_msg('No folder selected. Aborting.');
            animal_folder = [];
        end
    else
        animal_folder = animal_folder_input;
        if ~isfolder(animal_folder)
            error('Animal folder not found: %s', animal_folder);
        end
    end
end

function [interval_data, occupancy_4cm, halls, trans_beg, trans_end, maxRHD_ts] = ...
    load_behavior_data(animal_folder, derived_dir, overwrite, save_intermediates)
    % Load cached behavior or compute from scratch

    cache_file = fullfile(derived_dir, 'behavior_cache.mat');

    if exist(cache_file, 'file') && ~overwrite
        log_msg('Loading behavior cache...');
        S = load(cache_file, 'interval_data', 'occupancy_4cm', 'halls', ...
            'trans_beg', 'trans_end', 'maxRHD_ts');
        interval_data = S.interval_data;
        occupancy_4cm = S.occupancy_4cm;
        halls = S.halls;
        trans_beg = S.trans_beg;
        trans_end = S.trans_end;
        maxRHD_ts = S.maxRHD_ts;
        log_msg('Loaded %d trials, %d bins', numel(interval_data), size(occupancy_4cm, 2));
    else
        log_msg('Computing behavior...');
        [interval_data, occupancy_4cm, halls, trans_beg, trans_end, maxRHD_ts] = ...
            process_behavioral_data(animal_folder);
        log_msg('Computed %d trials, %d bins', numel(interval_data), size(occupancy_4cm, 2));

        if save_intermediates
            save(cache_file, 'interval_data', 'occupancy_4cm', 'halls', ...
                'trans_beg', 'trans_end', 'maxRHD_ts', '-v7.3');
            log_msg('Saved behavior cache');
        end
    end
end

function process_region(region_folder, interval_data, occupancy_4cm, halls, ...
    trans_beg, trans_end, maxRHD_ts, animal_folder, opts)
    % Process spike data and create plots for one region (legacy pipeline)

    out_folder = fullfile(region_folder, 'Figures');
    if ~exist(out_folder, 'dir'), mkdir(out_folder); end

    region_derived = fullfile(region_folder, 'Derived');
    if ~exist(region_derived, 'dir'), mkdir(region_derived); end

    cache_file = fullfile(region_derived, 'spikes_cache.mat');

    % Load or compute spike data
    if exist(cache_file, 'file') && ~opts.Overwrite
        log_msg('Loading spike cache...');
        S = load(cache_file, 'rate_4cm_3D', 'raster_data', 'cluster_id_good');
        rate_4cm_3D = S.rate_4cm_3D;
        raster_data = S.raster_data;
        cluster_id_good = S.cluster_id_good;
    else
        [rate_4cm_3D, raster_data, cluster_id_good] = process_spike_data(...
            region_folder, interval_data, occupancy_4cm, halls, ...
            trans_beg, trans_end, maxRHD_ts);

        if opts.SaveIntermediates
            save(cache_file, 'rate_4cm_3D', 'raster_data', 'cluster_id_good', '-v7.3');
            log_msg('Saved spike cache');
        end
    end

    % Check if we have data
    if isempty(rate_4cm_3D) || size(rate_4cm_3D, 3) == 0
        log_msg('No units found. Skipping region.');
        return;
    end

    [nTrials, nBins, nUnits] = size(rate_4cm_3D);
    log_msg('Loaded %d units, %d trials, %d bins', nUnits, nTrials, nBins);

    % Compute block averages (legacy)
    [rate_mean_halls, ~, blocks_used] = analyze_blocks(rate_4cm_3D, halls, 'Blocks', opts.Blocks);
    log_msg('Blocks: %s', format_blocks(blocks_used));

    % Create plots (legacy)
    [~, animal_name] = fileparts(animal_folder);
    [~, region_name] = fileparts(region_folder);
    title_prefix = sprintf('%s | %s | ', animal_name, region_name);

    create_all_plots(rate_mean_halls, raster_data, halls, cluster_id_good, out_folder, ...
        'Blocks', blocks_used, ...
        'SmoothingWin', opts.SmoothingWin, ...
        'SavePNGs', opts.SavePNGs, ...
        'PDFName', opts.PDFName, ...
        'PDFContent', opts.PDFContent, ...
        'ShowTrialIDs', opts.ShowTrialIDs, ...
        'TitlePrefix', title_prefix, ...
        'RasterMarkerSize', opts.RasterMarkerSize);

    log_msg('Finished region (legacy)');
end

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

function name = get_name(pathstr)
    % Extract terminal folder name (animal or region)
    [~, name] = fileparts(pathstr);
end