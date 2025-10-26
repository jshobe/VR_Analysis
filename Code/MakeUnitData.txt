function MakeUnitData()
% MAKEUNITDATA - Build unitdata struct from CSV and MAT (minimal, fail-fast)
% Handles PPC and VC regions; saves per-unit trialtypes and Blocks (all blocks)

% 1) Select VR## folder
vrFolder = uigetdir('Z:\Justin\VR mice', 'Select VR animal folder (VR##)');
if isequal(vrFolder, 0), error('No folder selected.'); end
[~, animalName] = fileparts(vrFolder);

% 2) Process each region (PPC, VC)
regions = {'PPC', 'VC'};
nProcessed = 0;

for r = 1:numel(regions)
    region = regions{r};
    regionFolder = fullfile(vrFolder, region);
    if ~isfolder(regionFolder)
        error('Region folder not found: %s', regionFolder); % fail-fast (adjust to continue if desired)
    end

    % Paths
    csvPath = fullfile(regionFolder, 'UnitMetrics', sprintf('%s_GoodUnitInfo.csv', animalName));
    matPath = fullfile(regionFolder, 'Derived_V2', 'spatial_analysis_v2.mat');
    if ~exist(csvPath, 'file') || ~exist(matPath, 'file')
        error('Missing CSV or MAT for %s. CSV=%d MAT=%d', region, exist(csvPath,'file'), exist(matPath,'file'));
    end

    fprintf('\n=== Processing %s ===\n', region);
    fprintf('CSV: %s\nMAT: %s\n', csvPath, matPath);

    % 3) Load table and MAT (with required-vars check)
    unitTable = readtable(csvPath);
    unitdata  = table2struct(unitTable);  % struct array, one per unit

    S = load(matPath);
    requiredVars = {'RateMeansByType','RateMeansByTypeByBlock','cluster_id_good'};
    for k = 1:numel(requiredVars)
        if ~isfield(S, requiredVars{k})
            error('Missing "%s" in %s', requiredVars{k}, matPath);
        end
    end

    RateMeansByType        = S.RateMeansByType;               % [nUnits x nBins x 7]
    RateMeansByTypeByBlock = S.RateMeansByTypeByBlock;        % [nUnits x nBins x 7 x nBlocks]
    cluster_id_good        = S.cluster_id_good(:);            % [nUnits x 1]

    % 4) Validate counts and ordering
    nUnits = numel(cluster_id_good);
    % Robust numeric ClusterID compare (CSV first col may be string/cell)
    csvIDs = unitTable.ClusterID;
    if iscell(csvIDs) || isstring(csvIDs), csvIDs = str2double(string(csvIDs)); end
    if any(~isfinite(csvIDs)), error('Non-numeric ClusterID values in CSV'); end

    if numel(unitdata) ~= nUnits
        error('%s: Unit count mismatch (CSV=%d, MAT=%d)', region, numel(unitdata), nUnits);
    end
    if any(cluster_id_good' ~= csvIDs(:)')
        error('%s: ClusterID order mismatch between CSV and MAT.', region);
    end

    [nUnitsM, nBins, ~] = size(RateMeansByType);
    if nUnitsM ~= nUnits, error('RateMeansByType units mismatch: %d vs %d.', nUnitsM, nUnits); end
    nBlocks = size(RateMeansByTypeByBlock, 4);
    if nBlocks < 1, error('RateMeansByTypeByBlock has no blocks.'); end

    % 5) Populate trialtypes (vectorized into 1x7 row cells)
    % Take c-th unit slice -> [nBins x 7], transpose to [7 x nBins], then mat2cell rows
    for c = 1:nUnits
        M = squeeze(RateMeansByType(c, :, :));     % [nBins x 7]
        unitdata(c).trialtypes = mat2cell(M.', ones(1,7), nBins); % 1x7 cells of 1 x nBins
    end

    % 6) Populate Blocks (all blocks; 1x7 cell per block of row vectors)
    % Keeps data for any number of blocks (no truncation)
    BlocksCell = cell(1, nBlocks);
    for b = 1:nBlocks
        Mb = squeeze(RateMeansByTypeByBlock(:, :, :, b)); % [nUnits x nBins x 7]
        for c = 1:nUnits
            Mc = squeeze(Mb(c, :, :));                           % [nBins x 7]
            BlocksCell{b} = BlocksCell{b};                       % ensure exists
            unitdata(c).Blocks{b} = mat2cell(Mc.', ones(1,7), nBins);
        end
    end

    % 7) Optionally attach provenance context if present (kept minimal)
    if isfield(S, 'Blocks'), blk = S.Blocks; else, blk = []; end
    if isfield(S, 'TrialCountsByTypeByBlock'), tcb = S.TrialCountsByTypeByBlock; else, tcb = []; end
    header = struct('animal', animalName, 'region', region, 'nUnits', nUnits, 'nBins', nBins, 'nBlocks', nBlocks, ...
                    'cluster_id_good', cluster_id_good, 'Blocks', blk, 'TrialCountsByTypeByBlock', tcb);

    % 8) Save
    outDir  = fullfile(regionFolder, 'Derived_V2');
    if ~exist(outDir, 'dir'), mkdir(outDir); end
    outPath = fullfile(outDir, sprintf('%s_%s_unitdata.mat', animalName, region));
    save(outPath, 'unitdata', 'header', '-v7.3');

    fprintf('Saved: %s\nUnits: %d | Bins: %d | Blocks: %d\n\n', outPath, nUnits, nBins, nBlocks);
    nProcessed = nProcessed + 1;
end

if nProcessed == 0
    error('No regions processed. Check folder structure and files.');
end

fprintf('Done.\n');
end