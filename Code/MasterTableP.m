%% MasterTable_PARFOR_clean.m
% Build cohort-wide Merged table with unitdata + spikes.
% - Parallelized over animals
% - MAT save only (no CSV)
% - FRxTT stays 7x1 cell per row (from unitdata.trialtypes)
% - SpikeTS_All is a double vector
% - SpikeTSxBlock shows as 3 subcolumns (one per block)
% - All FR summary columns from FastSummaryWide are preserved

%% --- CONFIG ---------------------------------------------------------------
allvr_mat_path  = 'Z:\Justin\VR mice\AllVR_PerUnitSummary.mat';
spikes_filename = 'fsc_spikes_unfiltered.mat';
Threshold       = 5.5;    % Block_Filter threshold
DoSave          = true;   % Save MAT only

%% --- LOAD COHORT & BUILD SCAFFOLD ----------------------------------------
assert(isfile(allvr_mat_path), 'File not found: %s', allvr_mat_path);
S = load(allvr_mat_path, 'CohortStruct'); 
C = S.CohortStruct;
cohort_dir = string(C.CohortFolder);

T0 = C.FastSummaryWide;
assert(all(ismember({'Animal','Region','UnitID'}, T0.Properties.VariableNames)), ...
    'Cohort table missing Animal/Region/UnitID');

% Ensure Block_Filter (1/0)
if ismember('Block_Filter', T0.Properties.VariableNames)
    T0.Block_Filter = double(T0.Block_Filter > 0);
elseif ismember('Ratio_max_to_min_3blocks', T0.Properties.VariableNames)
    T0.Block_Filter = double(T0.Ratio_max_to_min_3blocks <= Threshold);
else
    error('Cannot derive Block_Filter (Ratio_max_to_min_3blocks missing).');
end

% Standardize strings; build Folder (PPC/VC) for keying
T0.Animal = string(T0.Animal);
T0.Region = string(T0.Region);
T0.Folder = T0.Region;           % join key will be Animal, Folder, UnitID

% We want Region from unitdata (can be HC/dHC/vHC), so drop cohort Region
Scaffold = T0;
Scaffold(:, 'Region') = [];      % avoid duplicate Region after join

% Animals list
animals = unique(string(C.Animals(:)));
animals = animals(strlength(animals) > 0);
assert(~isempty(animals), 'CohortStruct.Animals is empty.');

%% --- COLLECT UNITDATA + SPIKES (PARFOR) ----------------------------------
regions = ["PPC","VC"];                 % constant for parfor
U_parts = cell(numel(animals),1);       % partial table per animal

parfor a = 1:numel(animals)
    animal = animals(a);
    Ua = table();

    for r = 1:numel(regions)
        reg = regions(r);
        base_dir = fullfile(cohort_dir, animal, reg, 'Derived_V2');

        % unitdata
        ud_file = fullfile(base_dir, sprintf('%s_%s_unitdata.mat', animal, reg));
        if ~isfile(ud_file), continue; end
        D = load(ud_file, 'unitdata');
        assert(isstruct(D.unitdata) && ~isempty(D.unitdata), 'Empty unitdata: %s', ud_file);

        T = struct2table(D.unitdata);
        assert(ismember('ClusterID', T.Properties.VariableNames), 'No ClusterID in %s', ud_file);

        % spikes (strict)
        sp_file = fullfile(base_dir, spikes_filename);
        assert(isfile(sp_file), 'Missing spikes file: %s', sp_file);
        Sx = load(sp_file);
        assert(all(isfield(Sx, {'spikes_by_block','spikes_all_session','cluster_id_good'})), ...
               'Missing fields in %s', sp_file);

        cid = Sx.cluster_id_good(:);  
        assert(isvector(cid), 'cluster_id_good must be a vector');

        % identifiers (final names)
        n = height(T);
        T.Animal = repmat(animal, n, 1);
        T.Folder = repmat(reg,    n, 1);   % PPC/VC
        T.UnitID = T.ClusterID;

        if ismember('Region', T.Properties.VariableNames)
            T.Region = string(T.Region);
        else
            T.Region = repmat(missing, n, 1);
        end

        % spikes placeholders (final column names)
        T.SpikeTSxBlock = cell(n,1);      % will become 3 subcolumns
        T.SpikeTS_All   = cell(n,1);      % double vector

        % attach spikes strictly by UnitID match
        [tf, loc] = ismember(T.UnitID, cid);
        sb = Sx.spikes_by_block;
        sa = Sx.spikes_all_session;
        for k = 1:n
            if tf(k)
                rr = loc(k);
                % 1x3 cell row for block spikes + double vector for session spikes
                try, T.SpikeTSxBlock{k} = sb(rr, :); catch, T.SpikeTSxBlock{k} = sb(rr); end
                T.SpikeTS_All{k} = sa{rr};
            end
        end

        % keep only columns we need from unitdata (include FR sources)
        keep = unique([ ...
            {'Animal','Folder','Region','UnitID','ClusterID','Channel','Shank','XPosition','Depth','CellType'}, ...
            {'trialtypes','Blocks'}, ...       % -> FRxTT / FRxTTxBlock
            {'SpikeTSxBlock','SpikeTS_All'} ...
        ], 'stable');
        have = intersect(keep, T.Properties.VariableNames, 'stable');
        T = T(:, have);

        Ua = [Ua; T]; %#ok<PFBNS>
    end

    % de-duplicate within this animal by Animal/Folder/UnitID
    if ~isempty(Ua)
        [~, ia] = unique(Ua(:, {'Animal','Folder','UnitID'}), 'rows', 'stable');
        Ua = Ua(ia, :);
    end
    U_parts{a} = Ua;
end

% combine animals
U_all = vertcat(U_parts{:});

%% --- MERGE WITH SCAFFOLD -------------------------------------------------
Merged = outerjoin(Scaffold, U_all, ...
    'Keys', {'Animal','Folder','UnitID'}, ...
    'MergeKeys', true, ...
    'Type', 'left');

%% --- RENAME / NORMALIZE ---------------------------------------------------
% trialtypes/Blocks -> FRxTT/FRxTTxBlock
if ismember('trialtypes', Merged.Properties.VariableNames)
    Merged.Properties.VariableNames{'trialtypes'} = 'FRxTT';
end
if ismember('Blocks', Merged.Properties.VariableNames)
    Merged.Properties.VariableNames{'Blocks'} = 'FRxTTxBlock';
end
if ismember('num_spike', Merged.Properties.VariableNames)
    Merged.Properties.VariableNames{'num_spike'} = 'SpikeCount';
end

% Ensure FRxTT is 7x1 cell (column cell array)
if ismember('FRxTT', Merged.Properties.VariableNames)
    for i = 1:height(Merged)
        ci = Merged.FRxTT{i};
        if iscell(ci), Merged.FRxTT{i} = ci(:); end
    end
end

% Normalize SpikeTSxBlock to n-by-3 subcolumns for display
if ismember('SpikeTSxBlock', Merged.Properties.VariableNames)
    nRows = height(Merged);
    if size(Merged.SpikeTSxBlock,2) == 1
        tmp = cell(nRows,3);
        for i = 1:nRows
            ci = Merged.SpikeTSxBlock{i};
            if iscell(ci)
                for b = 1:min(3, numel(ci))
                    tmp{i,b} = ci{b};
                end
            end
        end
        Merged.SpikeTSxBlock = tmp;   % table renders as 3 subcolumns
    end
end

% Region relabel: HC -> dHC / vHC by Folder
if ismember('Region', Merged.Properties.VariableNames)
    Merged.Region = strip(lower(string(Merged.Region)));
    F = strip(upper(string(Merged.Folder)));
    isHC = Merged.Region == "hc";
    Merged.Region(isHC & F == "PPC") = "dHC";
    Merged.Region(isHC & F == "VC")  = "vHC";
    Merged.Region = regexprep(Merged.Region, '^dhc$', 'dHC', 'ignorecase');
    Merged.Region = regexprep(Merged.Region, '^vhc$', 'vHC', 'ignorecase');
end

%% --- FINAL COLUMN ORDER (keep everything; just front-load key columns) ---
front = {'Animal','Folder','CellType','Region','ClusterID','Channel','Shank', ...
         'XPosition','Depth','SpikeCount','Block_Filter','FRxTT','FRxTTxBlock', ...
         'SpikeTS_All','SpikeTSxBlock'};
existing = Merged.Properties.VariableNames;
front = front(ismember(front, existing));
rest  = setdiff(existing, front, 'stable');
Merged = Merged(:, [front, rest]);   % preserves *all* FR summary columns

fprintf('\nRows: Merged=%d\n', height(Merged));

%% --- SAVE (MAT ONLY) ------------------------------------------------------
if DoSave
    [fldr, base] = fileparts(allvr_mat_path);
    out_mat = fullfile(fldr, sprintf('%s_master.mat', base));
    save(out_mat, 'Merged', '-v7.3');
    fprintf('Saved: %s\n', out_mat);
end
