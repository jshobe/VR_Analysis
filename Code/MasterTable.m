%% MasterTable.m
% Standalone script: merges AllVR_PerUnitSummary with per-animal PPC/VC unitdata
% and attaches spikes_by_block / spikes_all_session per unit (strict, no fallbacks).
% Runs immediately (script). Leaves Merged in base workspace.

%% --- CONFIG ---------------------------------------------------------------
allvr_mat_path = 'Z:\Justin\VR mice\AllVR_PerUnitSummary.mat';
Threshold      = 5.5;       % Block_Filter: ratio <= Threshold => 1 else 0
DoSave         = true;      % save MAT + CSV next to cohort file
ShowProgress   = false;     % minimal prints; set true for FOUND/MISS lines

% Spikes file name (strict, no fallback)
spikes_filename = 'fsc_spikes_unfiltered.mat';

%% --- LOAD COHORT ----------------------------------------------------------
assert(isfile(allvr_mat_path), 'File not found: %s', allvr_mat_path);
S = load(allvr_mat_path,'CohortStruct');
assert(isfield(S,'CohortStruct'), 'CohortStruct missing in %s', allvr_mat_path);
C = S.CohortStruct;
cohort_dir = string(C.CohortFolder);

T0 = C.FastSummaryWide;
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

% Scaffold
T0.Animal = string(T0.Animal);
T0.Region = string(T0.Region);
Scaffold = T0(:, {'Animal','Region','UnitID','Block_Filter'});
Scaffold.Properties.VariableNames{'Region'} = 'Region_summary';

%% --- DISCOVER ANIMALS ----------------------------------------------------
animals = unique(string(C.Animals(:)));
animals = animals(strlength(animals) > 0);
assert(~isempty(animals), 'CohortStruct.Animals is empty—cannot locate mouse folders.');

%% --- COLLECT UNITDATA + SPIKES -------------------------------------------
regions = {'PPC','VC'};
U_all = table();

for a = 1:numel(animals)
    animal = animals(a);
    for r = 1:numel(regions)
        reg = string(regions{r});
        base_dir = fullfile(cohort_dir, animal, reg, 'Derived_V2');

        ud_file = fullfile(base_dir, sprintf('%s_%s_unitdata.mat', animal, reg));
        if ~isfile(ud_file)
            if ShowProgress, fprintf('MISS  : %s\n', ud_file); end
            continue;
        end

        D = load(ud_file,'unitdata');
        assert(isfield(D,'unitdata') && isstruct(D.unitdata) && ~isempty(D.unitdata), ...
               'Invalid or empty "unitdata" in %s', ud_file);
        T = struct2table(D.unitdata);
        assert(ismember('ClusterID', T.Properties.VariableNames), ...
               'unitdata missing ClusterID in %s', ud_file);

        spikes_file = fullfile(base_dir, spikes_filename);
        assert(isfile(spikes_file), 'Missing spikes file: %s', spikes_file);
        Sx = load(spikes_file);
        assert(all(isfield(Sx, {'spikes_by_block','spikes_all_session','cluster_id_good'})), ...
               'Missing required fields in %s', spikes_file);

        cid = Sx.cluster_id_good(:);
        assert(isvector(cid), 'cluster_id_good must be a vector in %s', spikes_file);

        T.Animal         = repmat(animal, height(T), 1);
        T.Region_summary = repmat(reg,    height(T), 1);
        T.UnitID         = T.ClusterID;
        if ismember('Region', T.Properties.VariableNames)
            T.Region_unitdata = string(T.Region);
        else
            T.Region_unitdata = repmat(missing, height(T), 1);
        end

        % Prepare spike columns
        T.SpikesByBlock    = repmat({[]}, height(T), 1);
        T.SpikesAllSession = repmat({[]}, height(T), 1);

        % Attach spikes (no nested cells for SpikeTS_All)
        [tf, loc] = ismember(T.UnitID, cid);
        for k = 1:height(T)
            if tf(k)
                rr = loc(k);
                sb = Sx.spikes_by_block;       % 1x3 cell per unit row
                sa = Sx.spikes_all_session;    % 1x1 cell per unit row -> double vector
                T.SpikesByBlock{k}    = sb(rr, :);   % keep as 1x3 cell for now
                T.SpikesAllSession{k} = sa{rr};      % store the double vector (no nested cell)
            end
        end

        if ShowProgress
            fprintf('FOUND : %s (matched %d/%d units)\n', ud_file, sum(tf), numel(tf));
        end

        keycols = {'Animal','Region_summary','UnitID','Region_unitdata','SpikesByBlock','SpikesAllSession'};
        rest    = setdiff(T.Properties.VariableNames, keycols, 'stable');
        T       = T(:, [keycols, rest]);
        U_all   = [U_all; T]; %#ok<AGROW>
    end
end

if ~isempty(U_all)
    [~, ia] = unique(U_all(:, {'Animal','Region_summary','UnitID'}), 'rows', 'stable');
    U_all = U_all(ia, :);
end

%% --- MERGE SCAFFOLD + UNITDATA -------------------------------------------
Merged = outerjoin(Scaffold, U_all, ...
    'Keys', {'Animal','Region_summary','UnitID'}, ...
    'MergeKeys', true, 'Type', 'left');

%% --- POST-PROCESS ---------------------------------------------------------
% Rename columns
if ismember('Region_summary', Merged.Properties.VariableNames)
    Merged.Properties.VariableNames{'Region_summary'} = 'Folder';
end
if ismember('trialtypes', Merged.Properties.VariableNames)
    Merged.Properties.VariableNames{'trialtypes'} = 'FRxTT';
end
if ismember('Blocks', Merged.Properties.VariableNames)
    Merged.Properties.VariableNames{'Blocks'} = 'FRxTTxBlock';
end
if ismember('num_spike', Merged.Properties.VariableNames)
    Merged.Properties.VariableNames{'num_spike'} = 'SpikeCount';
end
if ismember('SpikesByBlock', Merged.Properties.VariableNames)
    Merged.Properties.VariableNames{'SpikesByBlock'} = 'SpikeTSxBlock';
end
if ismember('SpikesAllSession', Merged.Properties.VariableNames)
    Merged.Properties.VariableNames{'SpikesAllSession'} = 'SpikeTS_All';
end

% Normalize HC → dHC/vHC
Merged.Region = strip(lower(string(Merged.Region)));
Merged.Folder = strip(upper(string(Merged.Folder)));
isHC  = (Merged.Region == "hc");
isPPC = (Merged.Folder == "PPC");
isVC  = (Merged.Folder == "VC");
Merged.Region(isHC & isPPC) = "dHC";
Merged.Region(isHC & isVC)  = "vHC";
Merged.Region = regexprep(Merged.Region, '^dhc$', 'dHC', 'ignorecase');
Merged.Region = regexprep(Merged.Region, '^vhc$', 'vHC', 'ignorecase');

%% --- FRxTT: keep as a single 7x1 cell per row (no subcolumns) ------------
if ismember('FRxTT', Merged.Properties.VariableNames)
    nRows = height(Merged);
    for i = 1:nRows
        if iscell(Merged.FRxTT{i})
            Merged.FRxTT{i} = Merged.FRxTT{i}(:);  % ensure column shape (7x1)
        end
    end
end

%% --- Normalize SpikeTSxBlock to n-by-3 (3 subcolumns) --------------------
if ismember('SpikeTSxBlock', Merged.Properties.VariableNames)
    nRows = height(Merged);
    if size(Merged.SpikeTSxBlock,2) == 1
        tmp = cell(nRows,3);
        for i = 1:nRows
            ci = Merged.SpikeTSxBlock{i};   % a 1x3 cell
            if iscell(ci)
                for b = 1:min(3, numel(ci))
                    tmp{i,b} = ci{b};       % each is a double vector
                end
            end
        end
        Merged.SpikeTSxBlock = tmp;         % shows as 3 subcolumns
    end
end

%% --- Final column order --------------------------------------------------
desiredOrder = {'Animal','Folder','CellType','Region','ClusterID','Channel','Shank', ...
                'XPosition','Depth','SpikeCount','Block_Filter','FRxTT','FRxTTxBlock', ...
                'SpikeTS_All','SpikeTSxBlock'};
existing = ismember(desiredOrder, Merged.Properties.VariableNames);
Merged = Merged(:, desiredOrder(existing));

fprintf('\nRows: Merged=%d\n', height(Merged));

%% --- SAVE ----------------------------------------------------------------
if DoSave
    [fldr, base] = fileparts(allvr_mat_path);
    out_mat = fullfile(fldr, sprintf('%s_master.mat', base));
    out_csv = fullfile(fldr, sprintf('%s_master.csv',  base));
    save(out_mat, 'Merged', '-v7.3');
    writetable(Merged, out_csv);
    fprintf('\nSaved:\n  %s\n  %s\n', out_mat, out_csv);
end
