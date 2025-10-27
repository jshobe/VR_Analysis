function save_v2_data(animal_path, region_path, derived_path, varargin)
% save_v2_data
% Builds opts, loads region inputs, runs process_region (with plotting),
% and writes Derived_V2.mat

% ------------ Parse options (opts) ------------
p = inputParser;
p.addParameter('Blocks',           {[]},   @(x) iscell(x) || isnumeric(x));
p.addParameter('SmoothingWin',     12,     @isscalar);
p.addParameter('SpeedThresh',      [],     @(x) isempty(x) || (isscalar(x) && isfinite(x)));

% Plotting & outputs (legacy)
p.addParameter('MakeLegacyPlots',  true,   @islogical);
p.addParameter('SavePNGs',         false,  @islogical);
p.addParameter('SaveFIGs',         false,  @islogical);
p.addParameter('ShowTrialIDs',     false,  @islogical);
p.addParameter('PDFName',          'AllUnits_SpatialAnalysis.pdf', @ischar);
p.addParameter('PDFContent',       'image', @ischar);
p.addParameter('RasterMarkerSize', 2,      @isscalar);

% Cache/IO behavior
p.addParameter('Overwrite',        false,  @islogical);
p.addParameter('SaveIntermediates',true,   @islogical);

p.parse(varargin{:});
opts = p.Results;

% ------------ Ensure derived_path exists ------------
if ~exist(derived_path, 'dir'), mkdir(derived_path); end

% ------------ Load required inputs for process_region ------------
% We try Derived/ first, then region root.
interval_data = load_var_search(region_path, 'interval_data.mat', 'interval_data');
occupancy_4cm = load_var_search(region_path, 'occupancy_4cm.mat', 'occupancy_4cm');
halls         = load_var_search(region_path, 'halls.mat',          'halls');

% trans_beg/trans_end may be in same file; try flexible loads
[trans_beg, trans_end] = load_transitions(region_path);

maxRHD_ts    = load_var_search(region_path, 'maxRHD_ts.mat', 'maxRHD_ts');

% ------------ Run Core region processing (plots ON by default) ------------
R = process_region( ...
    region_path, ...      % region_folder
    interval_data, ...    % interval_data
    occupancy_4cm, ...    % occupancy_4cm
    halls, ...            % halls
    trans_beg, ...        % trans_beg
    trans_end, ...        % trans_end
    maxRHD_ts, ...        % maxRHD_ts
    animal_path, ...      % animal_folder
    opts);                % opts (struct)

% ------------ Validate return struct ------------
if ~isstruct(R), error('process_region must return a struct.'); end
if ~isfield(R,'tt_counts'),  error('process_region result missing field: tt_counts');  end
if ~isfield(R,'binCenters'), error('process_region result missing field: binCenters'); end

tt_counts  = R.tt_counts;
binCenters = R.binCenters;
if isempty(binCenters) || ~isvector(binCenters)
    error('binCenters must be a non-empty vector.');
end
xMin = binCenters(1);
xMax = binCenters(end);

% ------------ Assemble & save Derived_V2 ------------
[~, region_name] = fileparts(region_path);
[~, animal_name] = fileparts(animal_path);

DerivedV2 = struct();
DerivedV2.animal_path   = animal_path;
DerivedV2.animal_name   = animal_name;
DerivedV2.region_path   = region_path;
DerivedV2.region_name   = region_name;
DerivedV2.created_on    = datestr(now, 'yyyy-mm-dd HH:MM:SS');

DerivedV2.blocks_used       = opts.Blocks;
DerivedV2.smoothing_window  = opts.SmoothingWin;
DerivedV2.speed_thresh      = opts.SpeedThresh;

DerivedV2.tt_counts   = tt_counts;
DerivedV2.binCenters  = binCenters;
DerivedV2.xMin        = xMin;
DerivedV2.xMax        = xMax;

outFile = fullfile(derived_path, 'Derived_V2.mat');
save(outFile, 'DerivedV2', '-v7');
fprintf('Saved Derived_V2: %s\n', outFile);
end

% ======================== Helpers ========================
function val = load_var_search(region_path, fname, varname)
% Look under Derived/ first, then region root.
cand = { fullfile(region_path,'Derived',fname), fullfile(region_path,fname) };
for i = 1:numel(cand)
    if exist(cand{i}, 'file')
        S = load(cand{i});
        if isfield(S, varname)
            val = S.(varname);
            return;
        end
    end
end
error('Missing required variable "%s" (looked for %s in Derived/ and region root).', varname, fname);
end

function [trans_beg, trans_end] = load_transitions(region_path)
% Try common possibilities:
candidates = { ...
    {'transitions.mat', {'trans_beg','trans_end'}}, ...
    {'trans_beg_end.mat', {'trans_beg','trans_end'}}, ...
    {'trans_beg.mat', {'trans_beg'}}, ...
    {'trans_end.mat', {'trans_end'}} ...
};

trans_beg = [];
trans_end = [];

for k = 1:numel(candidates)
    fname = candidates{k}{1};
    fields = candidates{k}{2};
    % Search Derived/ then root
    cand = { fullfile(region_path,'Derived',fname), fullfile(region_path,fname) };
    for i = 1:numel(cand)
        if exist(cand{i}, 'file')
            S = load(cand{i});
            for f = 1:numel(fields)
                if isfield(S, fields{f})
                    switch fields{f}
                        case 'trans_beg', trans_beg = S.trans_beg;
                        case 'trans_end', trans_end = S.trans_end;
                    end
                end
            end
        end
    end
    if ~isempty(trans_beg) && ~isempty(trans_end)
        return;
    end
end

% Final validation:
if isempty(trans_beg) || isempty(trans_end)
    error('Missing required transitions: trans_beg/trans_end (checked several common files in Derived/ and region root).');
end
end
