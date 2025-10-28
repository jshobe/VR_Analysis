function [FastSummaryWide, UnfSummaryWide] = extra_filter2()
% EXTRA_FILTER
% Pick a VR## folder and build per-unit, per-region wide summaries.
% Saves a structured .mat file containing summary tables and hierarchical
% trial-by-trial RawData per unit.
%
% OUTPUT .mat structure layout:
%   SummaryStruct.Animal
%   SummaryStruct.Folder
%   SummaryStruct.FastSummary
%   SummaryStruct.UnfilteredSummary
%   SummaryStruct.RawData.Fast.Unit_001.trial_001.Block / Count / etc.
%   SummaryStruct.RawData.Unfiltered.Unit_001.trial_001.Block / Count / etc.

%% --- Select animal folder ---
root = uigetdir(pwd, 'Select VR## animal folder');
if isequal(root,0)
    error('No folder selected.');
end
[~, animal] = fileparts(root);

regions = {'PPC','VC'};
FastUnitTrials = table();   % Animal, Region, Block, Trial, UnitID, Count
UnfUnitTrials  = table();

%% --- Load data from each region ---
for i = 1:numel(regions)
    region_folder = fullfile(root, regions{i});
    if ~isfolder(region_folder)
        error('Region folder not found: %s', region_folder);
    end

    v2mat = fullfile(region_folder, 'Derived_V2', 'spatial_analysis_v2.mat');
    if ~isfile(v2mat)
        error('V2 MAT not found: %s', v2mat);
    end

    S = load(v2mat, 'Blocks', 'raster_data', 'unit_summary', 'cluster_id_good');
    req = {'Blocks','raster_data','unit_summary','cluster_id_good'};
    for k = 1:numel(req)
        if ~isfield(S, req{k})
            error('Missing field "%s" in %s', req{k}, v2mat);
        end
    end
    if ~isfield(S.unit_summary, 'trial_counts')
        error('Missing unit_summary.trial_counts in %s', v2mat);
    end

    Blocks      = S.Blocks;                       % {1x3} cell, trial indices
    raster_data = S.raster_data;                  % {nUnits x nTrials} with .positions
    trialCounts = S.unit_summary.trial_counts;    % [nUnits x nTrials]
    unitIDs     = S.cluster_id_good(:);

    % sanity checks
    if numel(Blocks) ~= 3
        error('Expected exactly 3 blocks; found %d in %s', numel(Blocks), v2mat);
    end
    if size(trialCounts,1) ~= numel(unitIDs)
        error('trial_counts rows (%d) != number of units (%d)', size(trialCounts,1), numel(unitIDs));
    end
    if size(raster_data,1) ~= numel(unitIDs)
        error('raster_data rows (%d) != number of units (%d)', size(raster_data,1), numel(unitIDs));
    end

    % ---- FAST-ONLY: per unit per trial ----
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
    Ft = table(repmat(string(animal), size(f_rows,1),1), ...
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
    Ut = table(repmat(string(animal), size(u_rows,1),1), ...
               repmat(string(regions{i}), size(u_rows,1),1), ...
               u_rows(:,1), u_rows(:,2), u_rows(:,3), u_rows(:,4), ...
               'VariableNames', {'Animal','Region','Block','Trial','UnitID','Count'});
    UnfUnitTrials = [UnfUnitTrials; Ut]; %#ok<AGROW>
end

%% --- Create per-unit wide summaries ---
FastSummaryWide = make_wide(FastUnitTrials);
UnfSummaryWide  = make_wide(UnfUnitTrials);

%% --- Build RawData with one table per unit (Trial x Count) ---
RawData.Fast = struct();
RawData.Unfiltered = struct();

% ---- FAST ----
uFast = unique(FastUnitTrials.UnitID);
for k = 1:numel(uFast)
    u = uFast(k);
    sub = FastUnitTrials(FastUnitTrials.UnitID==u, {'Trial','Count'});
    sub = sortrows(sub, 'Trial');
    RawData.Fast.(sprintf('Unit_%03d', u)) = sub;  % table with Trial, Count
end

% ---- UNFILTERED ----
uUnf = unique(UnfUnitTrials.UnitID);
for k = 1:numel(uUnf)
    u = uUnf(k);
    sub = UnfUnitTrials(UnfUnitTrials.UnitID==u, {'Trial','Count'});
    sub = sortrows(sub, 'Trial');
    RawData.Unfiltered.(sprintf('Unit_%03d', u)) = sub;  % table with Trial, Count
end

% --- Combine and save ---
SummaryStruct = struct( ...
    'Animal',            animal, ...
    'Folder',            root, ...
    'FastSummary',       FastSummaryWide, ...
    'UnfilteredSummary', UnfSummaryWide, ...
    'RawData',           RawData ...
);

outMat = fullfile(root, sprintf('%s_PerUnitSummary.mat', animal));
save(outMat, 'SummaryStruct', '-v7.3');
fprintf('\nSaved structured summary to:\n  %s\n', outMat);


%% --- Combine everything into one structure and save ---
SummaryStruct = struct( ...
    'Animal',            animal, ...
    'Folder',            root, ...
    'FastSummary',       FastSummaryWide, ...
    'UnfilteredSummary', UnfSummaryWide, ...
    'RawData',           RawData ...
);

outMat = fullfile(root, sprintf('%s_PerUnitSummary.mat', animal));
save(outMat, 'SummaryStruct', '-v7.3');  % v7.3 allows large nested structures
fprintf('\nSaved structured summary to:\n  %s\n', outMat);
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
