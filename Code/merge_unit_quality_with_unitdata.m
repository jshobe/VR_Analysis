%% merge_unit_quality_with_unitdata_script.m
% Standalone script: merges AllVR_PerUnitSummary with per-animal PPC/VC unitdata.
% Runs immediately (no function header), leaves variables in base workspace.

%% --- CONFIG (edit these and hit Run) -------------------------------------
allvr_mat_path = 'Z:\Justin\VR mice\AllVR_PerUnitSummary.mat';
Source         = 'Fast';    % 'Fast' or 'Unfiltered'
Threshold      = 5.5;       % Block_Filter: ratio <= Threshold => 1 else 0
DoSave         = true;      % save MAT + CSV next to cohort file
ShowProgress   = true;      % fprintf progress per mouse/region

%% --- LOAD COHORT ---------------------------------------------------------
assert(isfile(allvr_mat_path), 'File not found: %s', allvr_mat_path);
S = load(allvr_mat_path,'CohortStruct');
assert(isfield(S,'CohortStruct'), 'CohortStruct missing in %s', allvr_mat_path);
C = S.CohortStruct;
cohort_dir = string(C.CohortFolder);

switch lower(string(Source))
    case "fast",        T0 = C.FastSummaryWide;
    case "unfiltered",  T0 = C.UnfSummaryWide;
    otherwise, error('Source must be "Fast" or "Unfiltered".');
end

assert(all(ismember({'Animal','Region','UnitID'}, T0.Properties.VariableNames)), ...
    'Cohort table missing Animal/Region/UnitID');

% Ensure Block_Filter exists (1/0)
if ~ismember('Block_Filter', T0.Properties.VariableNames)
    assert(ismember('Ratio_max_to_min_3blocks', T0.Properties.VariableNames), ...
        'Missing Ratio_max_to_min_3blocks; cannot derive Block_Filter.');
    T0.Block_Filter = double(T0.Ratio_max_to_min_3blocks <= Threshold);
else
    T0.Block_Filter = double(T0.Block_Filter > 0);
end

% Scaffold with the minimal columns
T0.Animal = string(T0.Animal);
T0.Region = string(T0.Region);
Scaffold = T0(:, {'Animal','Region','UnitID','Block_Filter'});
Scaffold.Properties.VariableNames{'Region'} = 'Region_summary';

%% --- DISCOVER ANIMALS (from cohort list; dedup) --------------------------
animals = unique(string(C.Animals(:)));
animals = animals(strlength(animals) > 0);

if isempty(animals)
    error('CohortStruct.Animals is empty—cannot locate mouse folders.');
end

%% --- COLLECT UNITDATA FOR PPC + VC ---------------------------------------
regions = {'PPC','VC'};
U_all = table();

for a = 1:numel(animals)
    animal = animals(a);
    for r = 1:numel(regions)
        reg = string(regions{r});
        ud_file = fullfile(cohort_dir, animal, reg, 'Derived_V2', ...
                           sprintf('%s_%s_unitdata.mat', animal, reg));
        if ~isfile(ud_file)
            if ShowProgress, fprintf('MISS  : %s\n', ud_file); end
            continue;
        end

        D = load(ud_file,'unitdata');
        if ~isfield(D,'unitdata') || ~isstruct(D.unitdata) || isempty(D.unitdata)
            warning('Invalid or empty "unitdata" in %s (skipping).', ud_file);
            continue;
        end

        T = struct2table(D.unitdata);
        if ~ismember('ClusterID', T.Properties.VariableNames)
            warning('unitdata missing ClusterID in %s (skipping).', ud_file);
            continue;
        end

        T.Animal          = repmat(animal, height(T), 1);
        T.Region_summary  = repmat(reg,    height(T), 1);
        T.UnitID          = T.ClusterID;
        if ismember('Region', T.Properties.VariableNames)
            T.Region_unitdata = string(T.Region);
        else
            T.Region_unitdata = repmat(missing, height(T), 1);
        end

        keycols = {'Animal','Region_summary','UnitID','Region_unitdata'};
        rest    = setdiff(T.Properties.VariableNames, keycols, 'stable');
        T       = T(:, [keycols, rest]);

        U_all = [U_all; T]; %#ok<AGROW>
        if ShowProgress, fprintf('FOUND : %s\n', ud_file); end
    end
end

% Deduplicate by (Animal, Region_summary, UnitID)
if ~isempty(U_all)
    [~, ia] = unique(U_all(:, {'Animal','Region_summary','UnitID'}), 'rows', 'stable');
    U_all = U_all(ia, :);
end

%% --- MERGE SCAFFOLD + UNITDATA ------------------------------------------
Merged = outerjoin(Scaffold, U_all, ...
    'Keys', {'Animal','Region_summary','UnitID'}, ...
    'MergeKeys', true, 'Type', 'left');

%% --- SLIM VIEW (10 columns, ordered) -------------------------------------
Slim = table();
Slim.Animal          = string(Merged.Animal);
Slim.Region_summary  = string(Merged.Region_summary);
Slim.UnitID          = Merged.UnitID;
Slim.Block_Filter    = Merged.Block_Filter;
Slim.Region_unitdata = string(Merged.Region_unitdata);

% Inline numeric/string fillers (no local functions)
if ismember('Channel', Merged.Properties.VariableNames)
    Slim.Channel = double(Merged.Channel);
else
    Slim.Channel = nan(height(Merged),1);
end

if ismember('Shank', Merged.Properties.VariableNames)
    Slim.Shank = double(Merged.Shank);
else
    Slim.Shank = nan(height(Merged),1);
end

if ismember('XPosition', Merged.Properties.VariableNames)
    Slim.XPosition = double(Merged.XPosition);
else
    Slim.XPosition = nan(height(Merged),1);
end

if ismember('Depth', Merged.Properties.VariableNames)
    Slim.Depth = double(Merged.Depth);
else
    Slim.Depth = nan(height(Merged),1);
end

if ismember('CellType', Merged.Properties.VariableNames)
    Slim.CellType = string(Merged.CellType);
else
    Slim.CellType = strings(height(Merged),1); Slim.CellType(:) = missing;
end


%% --- Post-processing: rename, delete, reorder ----------------------------
% 1) Rename columns in Merged
if ismember('Region_summary', Merged.Properties.VariableNames)
    Merged.Properties.VariableNames{'Region_summary'} = 'Folder';
end
if ismember('trialtypes', Merged.Properties.VariableNames)
    Merged.Properties.VariableNames{'trialtypes'} = 'FRxTT';
end
if ismember('Blocks', Merged.Properties.VariableNames)
    Merged.Properties.VariableNames{'Blocks'} = 'FRxTTxBlock';
end
% Map num_spike -> SpikeCount (valid MATLAB name)
if ismember('num_spike', Merged.Properties.VariableNames)
    Merged.Properties.VariableNames{'num_spike'} = 'SpikeCount';
end

% 2) Delete columns 5 and 3 by POSITION (after the renames above)
%    If you’d rather be robust, skip this and rely on the named reorder below.
if width(Merged) >= 5
    Merged(:, [5, 3]) = [];
else
    warning('Merged has fewer than 5 columns; skipping positional deletion.');
end

% 3) Reorder to exactly these (any missing names are skipped gracefully)
desiredOrder = {'Animal','Folder','CellType','Region','ClusterID','Channel','Shank', ...
                'XPosition','Depth','SpikeCount','Block_Filter','FRxTT','FRxTTxBlock'};
existing = ismember(desiredOrder, Merged.Properties.VariableNames);
Merged = Merged(:, desiredOrder(existing));

fprintf('\nRows: Merged=%d, Slim=%d\n', height(Merged), height(Slim));

%% --- Normalize Region by Folder for HC entries ---------------------------
% Make sure types are strings (works if they were char/cell/categorical)
if ismember('Region', Merged.Properties.VariableNames)
    if iscategorical(Merged.Region), Merged.Region = string(Merged.Region); end
    if iscellstr(Merged.Region),     Merged.Region = string(Merged.Region); end
    if ~isstring(Merged.Region),     Merged.Region = string(Merged.Region); end
else
    error('Merged table has no "Region" column to edit.');
end

if ismember('Folder', Merged.Properties.VariableNames)
    if iscategorical(Merged.Folder), Merged.Folder = string(Merged.Folder); end
    if iscellstr(Merged.Folder),     Merged.Folder = string(Merged.Folder); end
    if ~isstring(Merged.Folder),     Merged.Folder = string(Merged.Folder); end
else
    error('Merged table has no "Folder" column (was Region_summary renamed earlier?).');
end

% Optional: trim whitespace & unify case
Merged.Region = strip(lower(Merged.Region));
Merged.Folder = strip(upper(Merged.Folder));  % Folder is PPC/VC; normalize to uppercase

% Build masks and relabel
isHC    = (Merged.Region == "hc");     % original HC (case-insensitive handled via lower)
isPPC   = (Merged.Folder == "PPC");
isVC    = (Merged.Folder == "VC");

Merged.Region(isHC & isPPC) = "dHC";
Merged.Region(isHC & isVC)  = "vHC";

% If you want Region in TitleCase afterward:
Merged.Region = regexprep(Merged.Region, '^dhc$', 'dHC', 'ignorecase');
Merged.Region = regexprep(Merged.Region, '^vhc$', 'vHC', 'ignorecase');

%% --- SAVE OUTPUTS (optional) ---------------------------------------------
if DoSave
    [fldr, base] = fileparts(allvr_mat_path);
    out_mat = fullfile(fldr, sprintf('%s_%s_unitmerge.mat',  base, lower(string(Source))));
    out_csv = fullfile(fldr, sprintf('%s_%s_unitmerge_SLIM.csv', base, lower(string(Source))));
    save(out_mat, 'Merged', 'Slim', '-v7.3');
    writetable(Slim, out_csv);
    fprintf('\nSaved:\n  %s\n  %s\n', out_mat, out_csv);
end


