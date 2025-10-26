function save_v2_data(animal_path, region_path, derived_path, varargin)
% SAVE_V2_DATA  Compute & save Derived_V2/*.mat for the legacy plotting pipeline.
%
% Example:
% save_v2_data('Z:\Justin\VR mice\VR42', 'Z:\Justin\VR mice\VR42\PPC', ...
%              'Z:\Justin\VR mice\VR42\PPC\Derived_V2', ...
%              'Blocks', {12:174, 178:337}, 'SmoothingWin', 12);
%
% Notes:
% - Keeps ClusterID==0 units (no filtering).
% - Writes a fixed set of .mat files under Derived_V2/.
% - No v2 plotting here — plotting is done via plot_legacy_from_v2.m.

if nargin < 3 || isempty(derived_path)
    derived_path = fullfile(region_path, 'Derived_V2');
end
if ~exist(derived_path, 'dir'), mkdir(derived_path); end

p = inputParser;
addParameter(p, 'Blocks', {[]}, @(x) iscell(x) || isnumeric(x));
addParameter(p, 'SmoothingWin', 12, @(x) isscalar(x) && isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

% 1) Lookup / binning
halls = get_scene_lookup(); %#ok<NASGU> % (kept for completeness if process_region uses it)

% 2) Region data (behavior + spikes → aligned unit rasters/rates/metadata)
[rate_mean_halls, raster_data, clusterIDs, metadata_table, halls, Blocks, ...
    tt_counts, binCenters, xMin, xMax] = process_region( ...
        animal_path, region_path, ...
        'Blocks', opt.Blocks, ...
        'SmoothingWin', opt.SmoothingWin);

% 3) Block aggregations (idempotent; keep explicit separation)
[rate_mean_halls, tt_counts, binCenters, xMin, xMax] = analyze_blocks( ...
    rate_mean_halls, halls, Blocks);

% 4) Schema checks (lightweight defensive validation)
io_asserts_clusterIDs(clusterIDs);
io_asserts_metadata(metadata_table);
io_asserts_blocks(Blocks);
io_asserts_realvec(binCenters);

% 5) Save artifacts with fixed filenames
save(fullfile(derived_path, 'clusterIDs.mat'),      'clusterIDs');
save(fullfile(derived_path, 'metadata_table.mat'),  'metadata_table');
save(fullfile(derived_path, 'halls.mat'),           'halls');
save(fullfile(derived_path, 'Blocks.mat'),          'Blocks');
save(fullfile(derived_path, 'raster_data.mat'),     'raster_data');
save(fullfile(derived_path, 'rate_mean_halls.mat'), 'rate_mean_halls');
save(fullfile(derived_path, 'tt_counts.mat'),       'tt_counts');
save(fullfile(derived_path, 'binCenters.mat'),      'binCenters');
save(fullfile(derived_path, 'xMin.mat'),            'xMin');
save(fullfile(derived_path, 'xMax.mat'),            'xMax');

log_msg('Derived_V2 saved at %s', derived_path);
end
