function [FastSummaryWide, UnfSummaryWide] = extra_filter2()
% EXTRA_FILTER (multi-animal)
% Multi-select VR## folders; build and save per-unit summaries for each animal.
% Returns concatenated Fast/Unfiltered summary tables across all selected animals.
% Also saves a cohort-wide MAT in the base VR mice folder:
%   <BASE>\AllVR_PerUnitSummary.mat

%% --- pick one or more VR## folders ---
roots = pick_vr_dirs();
if isempty(roots), error('No folders selected.'); end

% collectors across animals (returned)
FastSummaryWide = table();
UnfSummaryWide  = table();

%% --- loop animals ---
for aidx = 1:numel(roots)
    root = roots{aidx};
    [~, animal] = fileparts(root);

    
    FastUnitTrials = table();   % Animal, Region, Block, Trial, UnitID, Count
    UnfUnitTrials  = table();

    if isfolder(fullfile(root, 'PPC')) && isfolder(fullfile(root, 'VC')) % if both VC and PPC
        regions = {'PPC','VC'};
    elseif isfolder(fullfile(root, 'PPC'))
        regions = {'PPC'};
    elseif isfolder(fullfile(root, 'VC'))
        regions = {'VC'};
    end
    
    % -------- per region load --------
    for i = 1:numel(regions)
        region_folder = fullfile(root, regions{i});
        if ~isfolder(region_folder), error('Region folder not found: %s', region_folder); end
        v2mat = fullfile(region_folder,'Derived_V2','spatial_analysis_v2.mat');
        if ~isfile(v2mat), error('V2 MAT not found: %s', v2mat); end

        S = load(v2mat,'Blocks','raster_data','unit_summary','cluster_id_good');
        req = {'Blocks','raster_data','unit_summary','cluster_id_good'};
        for k = 1:numel(req)
            if ~isfield(S, req{k}), error('Missing field "%s" in %s', req{k}, v2mat); end
        end
        if ~isfield(S.unit_summary,'trial_counts')
            error('Missing unit_summary.trial_counts in %s', v2mat);
        end

        Blocks      = S.Blocks;                       % {1x3} cell
        raster_data = S.raster_data;                  % {nUnits x nTrials}
        trialCounts = S.unit_summary.trial_counts;    % [nUnits x nTrials]
        unitIDs     = S.cluster_id_good(:);

        % strict checks
        if numel(Blocks) ~= 3
            error('Expected exactly 3 blocks; found %d in %s', numel(Blocks), v2mat);
        end
        if size(trialCounts,1) ~= numel(unitIDs)
            error('trial_counts rows (%d) != number of units (%d)', size(trialCounts,1), numel(unitIDs));
        end
        if size(raster_data,1) ~= numel(unitIDs)
            error('raster_data rows (%d) != number of units (%d)', size(raster_data,1), numel(unitIDs));
        end

        % ---- FAST: per unit per trial ----
        f_rows = [];
        for b = 1:3
            trList = Blocks{b}(:)';
            for tr = trList
                for u = 1:numel(unitIDs)
                    c = 0;
                    C = raster_data{u,tr};
                    if ~isempty(C) && isfield(C,'positions') && ~isempty(C.positions)
                        c = numel(C.positions);
                    end
                    f_rows = [f_rows; b, tr, unitIDs(u), c]; %#ok<AGROW>
                end
            end
        end
        Ft = table( repmat(string(animal), size(f_rows,1),1), ...
                    repmat(string(regions{i}), size(f_rows,1),1), ...
                    f_rows(:,1), f_rows(:,2), f_rows(:,3), f_rows(:,4), ...
                    'VariableNames', {'Animal','Region','Block','Trial','UnitID','Count'});
        FastUnitTrials = [FastUnitTrials; Ft]; %#ok<AGROW>

        % ---- UNFILTERED: per unit per trial ----
        u_rows = [];
        for b = 1:3
            trList = Blocks{b}(:)';
            for tr = trList
                for u = 1:numel(unitIDs)
                    c = trialCounts(u,tr);
                    u_rows = [u_rows; b, tr, unitIDs(u), c]; %#ok<AGROW>
                end
            end
        end
        Ut = table( repmat(string(animal), size(u_rows,1),1), ...
                    repmat(string(regions{i}), size(u_rows,1),1), ...
                    u_rows(:,1), u_rows(:,2), u_rows(:,3), u_rows(:,4), ...
                    'VariableNames', {'Animal','Region','Block','Trial','UnitID','Count'});
        UnfUnitTrials = [UnfUnitTrials; Ut]; %#ok<AGROW>
    end

    % --- per-animal summaries ---
    FastSummaryWide_one = make_wide(FastUnitTrials);
    UnfSummaryWide_one  = make_wide(UnfUnitTrials);

    % --- build RawData with one table per unit (Trial x Count) ---
    RawData.Fast = struct();
    RawData.Unfiltered = struct();

    % FAST units
    uFast = unique(FastUnitTrials.UnitID);
    for k = 1:numel(uFast)
        u = uFast(k);
        sub = FastUnitTrials(FastUnitTrials.UnitID==u, {'Trial','Count'});
        RawData.Fast.(sprintf('Unit_%03d', u)) = sortrows(sub,'Trial');
    end
    % UNF units
    uUnf = unique(UnfUnitTrials.UnitID);
    for k = 1:numel(uUnf)
        u = uUnf(k);
        sub = UnfUnitTrials(UnfUnitTrials.UnitID==u, {'Trial','Count'});
        RawData.Unfiltered.(sprintf('Unit_%03d', u)) = sortrows(sub,'Trial');
    end

    % --- save per-animal structure ---
    SummaryStruct = struct( ...
        'Animal',            animal, ...
        'Folder',            root, ...
        'FastSummary',       FastSummaryWide_one, ...
        'UnfilteredSummary', UnfSummaryWide_one, ...
        'RawData',           RawData ...
    );
    outMat = fullfile(root, sprintf('%s_PerUnitSummary.mat', animal));
    save(outMat, 'SummaryStruct', '-v7.3');
    fprintf('\nSaved structured summary to:\n  %s\n', outMat);

    % --- accumulate to outputs (across animals) ---
    FastSummaryWide = [FastSummaryWide; FastSummaryWide_one]; %#ok<AGROW>
    UnfSummaryWide  = [UnfSummaryWide;  UnfSummaryWide_one];  %#ok<AGROW>
end

%% --- cohort-wide save in base VR mice folder ---
cohort_dir = common_parent_dir(roots);                 % deepest common parent
animal_names = arrayfun(@(p) base_name(roots{p}), 1:numel(roots), 'UniformOutput', false);

CohortStruct = struct( ...
    'CohortFolder',     cohort_dir, ...
    'Animals',          string(animal_names), ...
    'FastSummaryWide',  FastSummaryWide, ...
    'UnfSummaryWide',   UnfSummaryWide ...
);
cohort_mat = fullfile(cohort_dir, 'AllVR_PerUnitSummary.mat');
save(cohort_mat, 'CohortStruct', '-v7.3');
fprintf('\nSaved cohort summary to:\n  %s\n', cohort_mat);
end

%% -------- helper: multi-select directory picker --------
function roots = pick_vr_dirs()
roots = {};
try
    import javax.swing.JFileChooser
    jfc = JFileChooser(pwd);
    jfc.setFileSelectionMode(JFileChooser.DIRECTORIES_ONLY);
    jfc.setMultiSelectionEnabled(true);
    status = jfc.showOpenDialog([]);
    if status == JFileChooser.APPROVE_OPTION
        files = jfc.getSelectedFiles();
        for k = 1:numel(files)
            roots{end+1} = char(files(k).getAbsolutePath()); %#ok<AGROW>
        end
    end
catch
    while true
        d = uigetdir(pwd, 'Select VR## folder (Cancel to finish)');
        if isequal(d,0), break; end
        roots{end+1} = d; %#ok<AGROW>
    end
end
roots = unique(roots);
end

%% ===================== Helper =====================
function SummaryWide = make_wide(Tin)
Tin = sortrows(Tin, {'Animal','Region','UnitID','Block','Trial'});
blocks = unique(Tin.Block);
if numel(blocks) ~= 3, error('Expected exactly 3 blocks, found %d', numel(blocks)); end

G = findgroups(Tin.Animal, Tin.Region, Tin.UnitID, Tin.Block);
A = splitapply(@(x)x(1), Tin.Animal, G);
R = splitapply(@(x)x(1), Tin.Region, G);
U = splitapply(@(x)x(1), Tin.UnitID, G);
B = splitapply(@(x)x(1), Tin.Block,  G);
TotalSpikes    = splitapply(@sum,  Tin.Count, G);
SpikesPerTrial = splitapply(@mean, Tin.Count, G);

Tstat = table(A,R,U,B,TotalSpikes,SpikesPerTrial, ...
    'VariableNames', {'Animal','Region','UnitID','Block','TotalSpikes','SpikesPerTrial'});

units = unique(Tstat(:,{'Animal','Region','UnitID'}),'rows');
nU = height(units);
BlockTotals = nan(nU,3);
BlockMeans  = nan(nU,3);
for b = 1:3
    ix = (Tstat.Block == b);
    if any(ix)
        [~, ia] = intersect(units, Tstat(ix,{'Animal','Region','UnitID'}), 'rows');
        BlockTotals(ia,b) = Tstat.TotalSpikes(ix);
        BlockMeans(ia,b)  = Tstat.SpikesPerTrial(ix);
    end
end

SummaryWide = units;
SummaryWide.Block1_total_spikes = BlockTotals(:,1);
SummaryWide.Block2_total_spikes = BlockTotals(:,2);
SummaryWide.Block3_total_spikes = BlockTotals(:,3);
SummaryWide.Block1_spikes_per_trial = BlockMeans(:,1);
SummaryWide.Block2_spikes_per_trial = BlockMeans(:,2);
SummaryWide.Block3_spikes_per_trial = BlockMeans(:,3);

V = [SummaryWide.Block1_spikes_per_trial, ...
     SummaryWide.Block2_spikes_per_trial, ...
     SummaryWide.Block3_spikes_per_trial];
SummaryWide.Mean_spikes_per_trial_3blocks = mean(V,2,'omitnan');
SummaryWide.Min_spikes_per_trial_3blocks  = min(V,[],2,'omitnan');
SummaryWide.Max_spikes_per_trial_3blocks  = max(V,[],2,'omitnan');
ratio = SummaryWide.Max_spikes_per_trial_3blocks ./ SummaryWide.Min_spikes_per_trial_3blocks;
ratio(~isfinite(ratio)) = NaN;
SummaryWide.Ratio_max_to_min_3blocks = ratio;

SummaryWide = SummaryWide(:,{'Animal','Region','UnitID', ...
    'Block1_total_spikes','Block2_total_spikes','Block3_total_spikes', ...
    'Block1_spikes_per_trial','Block2_spikes_per_trial','Block3_spikes_per_trial', ...
    'Mean_spikes_per_trial_3blocks','Min_spikes_per_trial_3blocks', ...
    'Max_spikes_per_trial_3blocks','Ratio_max_to_min_3blocks'});
end

%% -------- tiny helpers for cohort save --------
function d = common_parent_dir(paths)
sp = cellfun(@(p) strsplit(char(p), filesep), paths, 'UniformOutput', false);
minlen = min(cellfun(@numel, sp));
k = 1;
while k <= minlen
    tokens = cellfun(@(c) c{k}, sp, 'UniformOutput', false);
    if ~all(strcmp(tokens{1}, tokens)), break; end
    k = k + 1;
end
d = strjoin(sp{1}(1:k-1), filesep);
if isempty(d), d = filesep; end
end

function name = base_name(pathstr)
[~, name] = fileparts(pathstr);
end
