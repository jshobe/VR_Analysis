function save_v2_data(animal_path, region_path, derived_path, varargin)
% SAVE_V2_DATA
% Compute and save "Derived_V2" data for a single region.
% Strict version: expects process_region to return ONE struct with fields:
%   - tt_counts
%   - binCenters
%
% Called by run_full_pipeline:
%   save_v2_data(animal_path, region_path, derived_path, ...
%       'Blocks', {[]}, 'SmoothingWin', 12)

% -------------------- Parse options --------------------
p = inputParser;
p.addParameter('Blocks',        {[]}, @(x) iscell(x) || isnumeric(x));
p.addParameter('SmoothingWin',  12,   @isscalar);
p.parse(varargin{:});
opt = p.Results;

% -------------------- Ensure output dir --------------------
if ~exist(derived_path, 'dir')
    mkdir(derived_path);
end

% -------------------- Run region processing ----------------
% STRICT: process_region must return a single struct with required fields.
R = process_region( ...
    animal_path, ...
    region_path, ...
    'Blocks',       opt.Blocks, ...
    'SmoothingWin', opt.SmoothingWin);

% -------------------- Validate shape ----------------------
if ~isstruct(R)
    error('process_region must return a struct. Got: %s', class(R));
end
if ~isfield(R, 'tt_counts')
    error('process_region result missing field: tt_counts');
end
if ~isfield(R, 'binCenters')
    error('process_region result missing field: binCenters');
end

tt_counts  = R.tt_counts;
binCenters = R.binCenters;

% -------------------- Derive axis limits -------------------
if isempty(binCenters) || ~isvector(binCenters)
    error('binCenters must be a non-empty vector.');
end
xMin = binCenters(1);
xMax = binCenters(end);

% -------------------- Minimal metadata --------------------
[~, region_name] = fileparts(region_path);
[~, animal_name] = fileparts(animal_path);

DerivedV2 = struct();
DerivedV2.animal_path   = animal_path;
DerivedV2.animal_name   = animal_name;
DerivedV2.region_path   = region_path;
DerivedV2.region_name   = region_name;
DerivedV2.created_on    = datestr(now, 'yyyy-mm-dd HH:MM:SS');

DerivedV2.blocks_used       = opt.Blocks;
DerivedV2.smoothing_window  = opt.SmoothingWin;

% Primary outputs needed by legacy plotting
DerivedV2.tt_counts   = tt_counts;
DerivedV2.binCenters  = binCenters;
DerivedV2.xMin        = xMin;
DerivedV2.xMax        = xMax;

% -------------------- Save -------------------------------
outFile = fullfile(derived_path, 'Derived_V2.mat');
save(outFile, 'DerivedV2', '-v7');

fprintf('Saved Derived_V2: %s\n', outFile);
end
