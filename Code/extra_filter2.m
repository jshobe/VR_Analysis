function [FastSummaryWide, UnfSummaryWide] = extra_filter()
% EXTRA_FILTER (multi-animal)
% Multi-select VR## folders; build and save per-unit summaries for each animal.
% Returns concatenated Fast/Unfiltered summary tables across all selected animals.

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

    regions = {'PPC','VC'};
    FastUnitTrials = table();   % Animal, Region, Block, Trial, UnitID, Count
    UnfUnitTrials  = table();

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
end

%% -------- helper: multi-select directory picker --------
function roots = pick_vr_dirs()
% Returns cell array of selected directories (multi-select). Falls back to single uigetdir loop.
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
    % Fallback: repeated uigetdir until user cancels
    while true
        d = uigetdir(pwd, 'Select VR## folder (Cancel to finish)');
        if isequal(d,0), break; end
        roots{end+1} = d; %#ok<AGROW>
        % Ask whether to add another? (skip to keep it minimal)
    end
end
roots = unique(roots); % de-dup
end


%% ===================== Helper =====================
function SummaryWide = make_wide(Tin)
% Tin columns: Animal, Region, UnitID, Block, Trial, Count
Tin = sortrows(Tin, {'Animal','Region','UnitID','Block','Trial'});

blocks = unique(Tin.Block);
if numel(blocks) ~= 3
    error('Expected exactly 3 blocks, found %d', numel(blocks));
end

% per (Animal,Region,UnitID,Block) stats
G = findgroups(Tin.Animal, Tin.Region, Tin.UnitID, Tin.Block);

A = splitapply(@(x)x(1), Tin.Animal, G);
R = splitapply(@(x)x(1), Tin.Region, G);
U = splitapply(@(x)x(1), Tin.UnitID, G);
B = splitapply(@(x)x(1), Tin.Block,  G);

TotalSpikes    = splitapply(@sum,  Tin.Count, G);
SpikesPerTrial = splitapply(@mean, Tin.Count, G);

Tstat = table(A,R,U,B,TotalSpikes,SpikesPerTrial, ...
    'VariableNames', {'Animal','Region','UnitID','Block','TotalSpikes','SpikesPerTrial'});

% one row per unit
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

% assemble wide table
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

% Basic stats across the 3 blocks
SummaryWide.Mean_spikes_per_trial_3blocks = mean(V,2,'omitnan');
SummaryWide.Min_spikes_per_trial_3blocks  = min(V,[],2,'omitnan');
SummaryWide.Max_spikes_per_trial_3blocks  = max(V,[],2,'omitnan');

% Handle division by zero or NaN safely for ratio
ratio = SummaryWide.Max_spikes_per_trial_3blocks ./ SummaryWide.Min_spikes_per_trial_3blocks;
ratio(~isfinite(ratio)) = NaN;   % avoid Inf or NaN errors
SummaryWide.Ratio_max_to_min_3blocks = ratio;

% Reorder columns for final output
SummaryWide = SummaryWide(:,{'Animal','Region','UnitID', ...
    'Block1_total_spikes','Block2_total_spikes','Block3_total_spikes', ...
    'Block1_spikes_per_trial','Block2_spikes_per_trial','Block3_spikes_per_trial', ...
    'Mean_spikes_per_trial_3blocks','Min_spikes_per_trial_3blocks', ...
    'Max_spikes_per_trial_3blocks','Ratio_max_to_min_3blocks'});

end
