
% Build unitdata struct by selecting the VR## animal folder once.
% Automatically finds:
%   - Curated CSV:   <VR##>\<Region>\UnitMetrics\<VR##_GoodUnitInfo.csv>
%   - Analysis MAT:  <VR##>\<Region>\Derived_V2\spatial_analysis_v2.mat>
%
% Adds per-unit fields:
%   unitdata(c).trialtypes : 1x7 cells (session-wide mean rate curves)
%   unitdata(c).Block1     : 1x7 cells (Block 1 mean rate curves)
%   unitdata(c).Block2     : 1x7 cells (Block 2 mean rate curves)
%   unitdata(c).Block3     : 1x7 cells (Block 3 mean rate curves)
%
% Assumes spatial_analysis_v2.mat contains:
%   RateMeansByType        [nUnits x nBins x 7]
%   RateMeansByTypeByBlock [nUnits x nBins x 7 x nBlocks]
%   cluster_id_good        [nUnits x 1]

% 1) Select VR## animal folder
defaultRoot = 'Z:\Justin\VR mice';
vrFolder = uigetdir(defaultRoot, 'Select VR animal folder (VR##)');
if isequal(vrFolder, 0)
    error('No animal folder selected.');
end
[~, animalName] = fileparts(vrFolder);  % e.g., 'VR29'
if isempty(regexp(animalName, '^VR\d+$', 'once'))
    warning('Selected folder name "%s" does not match VR## pattern. Proceeding anyway...', animalName);
end

% 2) Auto-detect region folder and input files
candidateRegions = {'PPC','VC'};
selectedRegion = '';
csvPath = '';
matPath = '';

for i = 1:numel(candidateRegions) % big loop for each region
    region = candidateRegions{i};
    regionFolder = fullfile(vrFolder, region);
    if ~isfolder(regionFolder), continue; end

    % Expected file locations
    tryCsv  = fullfile(regionFolder, 'UnitMetrics', sprintf('%s_GoodUnitInfo.csv', animalName));
    tryMat  = fullfile(regionFolder, 'Derived_V2', 'spatial_analysis_v2.mat');

    if exist(tryCsv, 'file') == 2 && exist(tryMat, 'file') == 2
        selectedRegion = region;
        csvPath = tryCsv;
        matPath = tryMat;
        break;  % pick the first region that has both files
    end
end %% this needs to end @ outer loop in bottom

if isempty(selectedRegion)
    error('Could not automatically find both CSV and MAT in PPC/VC. Expected:\n  UnitMetrics\\%s_GoodUnitInfo.csv\n  Derived_V2\\spatial_analysis_v2.mat', animalName);
end

fprintf('Selected region: %s\n', selectedRegion);
fprintf('CSV: %s\n', csvPath);
fprintf('MAT: %s\n', matPath);

% 3) Load curated unit CSV and analysis MAT
unitTable = readtable(csvPath);
unitdata  = table2struct(unitTable);

S = load(matPath);
requiredVars = {'RateMeansByType','RateMeansByTypeByBlock','cluster_id_good'};
for k = 1:numel(requiredVars)
    if ~isfield(S, requiredVars{k})
        error('Missing "%s" in %s', requiredVars{k}, matPath);
    end
end

RateMeansByType        = S.RateMeansByType;        % [nUnits x nBins x 7]
RateMeansByTypeByBlock = S.RateMeansByTypeByBlock; % [nUnits x nBins x 7 x nBlocks]
cluster_id_good        = S.cluster_id_good(:);     % [nUnits x 1]

% 4) Validate ordering and dimensions
nUnits = numel(cluster_id_good);
if numel(unitdata) ~= nUnits
    error('Unit count mismatch: CSV has %d units; MAT has %d units.', numel(unitdata), nUnits);
end
if any(cluster_id_good' ~= [unitdata.ClusterID])
    error('ClusterID order mismatch between CSV and MAT.');
end

[nUnitsM, nBins, ~] = size(RateMeansByType);
if nUnitsM ~= nUnits
    error('RateMeansByType units mismatch: %d vs %d.', nUnitsM, nUnits);
end
nBlocks = size(RateMeansByTypeByBlock, 4);
if nBlocks < 1
    error('RateMeansByTypeByBlock has no blocks.');
end

% 5) Populate session-wide trial types (TT=1..7)
for c = 1:nUnits
    unitdata(c).trialtypes = arrayfun(@(tt) reshape(RateMeansByType(c, :, tt), 1, nBins), 1:7, 'UniformOutput', false);
end

% 6) Populate Block1/Block2/Block3 (each 1x7 cells of 1 x nBins row vectors)
for c = 1:nUnits
    % Block 1
    if nBlocks >= 1
        unitdata(c).Block1 = arrayfun(@(tt) reshape(RateMeansByTypeByBlock(c, :, tt, 1), 1, nBins), 1:7, 'UniformOutput', false);
    else
        unitdata(c).Block1 = cell(1, 7);
    end

    % Block 2
    if nBlocks >= 2
        unitdata(c).Block2 = arrayfun(@(tt) reshape(RateMeansByTypeByBlock(c, :, tt, 2), 1, nBins), 1:7, 'UniformOutput', false);
    else
        unitdata(c).Block2 = cell(1, 7);
    end

    % Block 3
    if nBlocks >= 3
        unitdata(c).Block3 = arrayfun(@(tt) reshape(RateMeansByTypeByBlock(c, :, tt, 3), 1, nBins), 1:7, 'UniformOutput', false);
    else
        unitdata(c).Block3 = cell(1, 7);
    end
end

fprintf('unitdata updated for %s (%s). Units: %d, Bins: %d, Blocks: %d\n', animalName, selectedRegion, nUnits, nBins, nBlocks);

% Optional: save the enriched unitdata next to the MAT for convenience
outStructPath = fullfile(vrFolder, selectedRegion, 'Derived_V2', sprintf('%s_%s_unitdata.mat', animalName, selectedRegion));
try
    save(outStructPath, 'unitdata', '-v7.3');
    fprintf('Saved unitdata to %s\n', outStructPath);
% catch ME
%     warning('Failed to save unitdata: %s', ME.message);
end