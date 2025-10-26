function GLM_bare_auto()
% GLM_BARE_AUTO (strict, no fallbacks)
% - Select a VR## folder once.
% - Processes PPC and VC (if present).
% - Loads UnitMetrics/<VR##_GoodUnitInfo.csv> and Derived_V2/spatial_analysis_v2.mat.
% - Chooses predictor files by parity (Odd/Even) and block kind (13 or 2).
% - Fits GLM per unit per block with strict design matrices:
%     Block 1/3: X = [Pos, Context, Chair, Drum, Star]   (5 predictors)
%     Block 2  : X = [Pos, Chair, Drum, Star]            (4 predictors; Context removed)
% - No automatic column dropping or header guessing; errors on mismatch.
% - Saves GLM results into unitdata for each region in Derived_V2.

% ---------------- Configuration ----------------
BaseFolder       = 'Z:\Justin\VR mice';
PredictorFolder  = 'Z:\Justin\VR mice';
RegionsToProcess = {'PPC','VC'};

% ---------------- Select VR animal folder ----------------
vrFolder = uigetdir(BaseFolder, 'Select VR animal folder (VR##)');
if isequal(vrFolder, 0)
    error('No animal folder selected.');
end
[~, animalName] = fileparts(vrFolder);  % e.g., 'VR29'
vrNum = parse_vr_number(animalName);
isEven = mod(vrNum, 2) == 0;
parityStr = tern(isEven, 'Even', 'Odd');

fprintf('[GLM_bare_auto] Animal: %s (parity=%s)\n', animalName, parityStr);

% ---------------- Process regions ----------------
for r = 1:numel(RegionsToProcess)
    region = RegionsToProcess{r};
    regionFolder = fullfile(vrFolder, region);
    if ~isfolder(regionFolder)
        fprintf('[GLM_bare_auto] Skipping %s (folder missing)\n', region);
        continue;
    end

    % Required inputs per region
    csvPath = fullfile(regionFolder, 'UnitMetrics', sprintf('%s_GoodUnitInfo.csv', animalName));
    matPath = fullfile(regionFolder, 'Derived_V2', 'spatial_analysis_v2.mat');
    if ~(exist(csvPath,'file')==2 && exist(matPath,'file')==2)
        fprintf('[GLM_bare_auto] Missing CSV or MAT in %s. Expected:\n  %s\n  %s\n', regionFolder, csvPath, matPath);
        continue;
    end

    % Load curated unit table and spatial analysis
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
    [nUnits, nBins, ~]     = size(RateMeansByType);
    nBlocks                = size(RateMeansByTypeByBlock, 4);

    % Align unitdata length with nUnits if needed (we store GLM here)
    if numel(unitdata) ~= nUnits
        fprintf('[GLM_bare_auto] WARNING: unitdata length (%d) ~= nUnits (%d). Proceeding with nUnits=%d.\n', numel(unitdata), nUnits, nUnits);
        if isempty(unitdata)
            unitdata = repmat(struct(), nUnits, 1);
        elseif numel(unitdata) < nUnits
            unitdata(end+1:nUnits,1) = struct();
        else
            unitdata = unitdata(1:nUnits);
        end
    end

    % Block -> TT lists and predictor kinds
    % Block 1/3: TT1, TT2, TT3, TT4 (contexts A, A, B, B)
    % Block 2  : TT1, TT2, TT5, TT6 (swap; all A)
    blockTTs   = { [1 2 3 4], [1 2 5 6], [1 2 3 4] };
    blockKinds = { '13', '2', '13' };

    % Prepare GLM container
    for c = 1:nUnits
        unitdata(c).GLM = struct();
    end

    % Loop over up to 3 blocks
    for b = 1:min(nBlocks,3)
        % Predictor file by parity + block kind
        predFile = fullfile(PredictorFolder, sprintf('Predictors_%s_Block%s.xlsx', parityStr, blockKinds{b}));
        if exist(predFile,'file') ~= 2
            error('Predictor file not found: %s', predFile);
        end
        predictor_tab = readtable(predFile);

        % Remove legacy INDEX if present (safe to drop; not part of schema)
        if any(strcmpi(predictor_tab.Properties.VariableNames, 'INDEX'))
            predictor_tab.INDEX = [];
        end

        % Strict design matrix per block kind
        includeContext = strcmp(blockKinds{b}, '13');
        [X, Xnames] = build_design_matrix_strict(predictor_tab, includeContext);

        % Must match 4 × nBins rows
        expectedRows = 4 * nBins;
        if height(predictor_tab) ~= expectedRows
            error('Predictor row count mismatch for %s: got %d, expected %d (4 × %d).', ...
                  predFile, height(predictor_tab), expectedRows, nBins);
        end

        % Warn if any predictor column is constant or NaN-only; do NOT drop
        colStd  = std(X, 0, 1, 'omitnan');
        nanOnly = ~any(isfinite(X),1);
        constCols = (colStd == 0) | nanOnly;
        if any(constCols)
            fprintf('[GLM] WARNING: Degenerate predictors in Block %d: %s\n', ...
                b, strjoin(Xnames(constCols), ', '));
        end

        ttList = blockTTs{b};
        fprintf('[GLM_bare_auto] %s | %s | Block %d | Predictors: %s | X=[%s] (p=%d)\n', ...
                animalName, region, b, predFile, strjoin(Xnames, ', '), numel(Xnames));

        for c = 1:nUnits
            % Build rmap by concatenating 4 TT segments from RateMeansByTypeByBlock (numeric 4D array)
            rmap = [];
            for t = 1:numel(ttList)
                tt  = ttList(t);
                seg = squeeze(RateMeansByTypeByBlock(c, :, tt, b)); % [nBins x 1]
                if isempty(seg)
                    seg = nan(nBins, 1);
                end
                rmap = [rmap; seg(:)]; %#ok<AGROW>
            end

            % Length check
            if numel(rmap) ~= size(X,1)
                error('Length mismatch: rmap=%d vs predictors=%d. Check nBins=%d and predictor rows=%d in %s.', ...
                      numel(rmap), size(X,1), nBins, size(X,1), predFile);
            end

            % Fit GLM (identity link, intercept on)
            [b_all, dev, stats] = glmfit(X, rmap, 'normal', 'link', 'identity', 'constant', 'on');

            % Store results
            glmOut = struct();
            glmOut.b_int    = b_all(1);
            glmOut.b_coeffs = b_all(2:end);
            glmOut.pval     = stats.p(2:end);
            glmOut.dev      = dev;
            glmOut.stats    = stats;
            glmOut.names    = Xnames;  % {'Pos','Context','Chair','Drum','Star'} or {'Pos','Chair','Drum','Star'}

            unitdata(c).GLM.(sprintf('Block%d', b)) = glmOut;
        end
    end

    % Save GLM-enriched unitdata for this region
    outStructPath = fullfile(regionFolder, 'Derived_V2', sprintf('%s_%s_unitdata_GLM.mat', animalName, region));
    try
        save(outStructPath, 'unitdata', '-v7.3');
        fprintf('[GLM_bare_auto] Saved GLM unitdata to %s\n', outStructPath);
    % catch ME
    %     warning('[GLM_bare_auto] Failed to save unitdata: %s', ME.message);
    end
end

fprintf('[GLM_bare_auto] Done.\n');

% ---------------- Local helpers ----------------
function [X, names] = build_design_matrix_strict(predictor_tab, includeContext)
% Strict design matrix (no fallbacks, no auto-dropping).
% - If includeContext=true: require headers exactly: Pos, Context, Chair, Drum, Star (any order ok; we enforce order in X).
% - Else: require headers exactly: Pos, Chair, Drum, Star.
% Errors if headers are missing; always includes Pos.

varNames = predictor_tab.Properties.VariableNames;

idxPos     = find(strcmpi(varNames,'Pos'),     1, 'first');
idxContext = find(strcmpi(varNames,'Context'), 1, 'first');
idxChair   = find(strcmpi(varNames,'Chair'),   1, 'first');
idxDrum    = find(strcmpi(varNames,'Drum'),    1, 'first');
idxStar    = find(strcmpi(varNames,'Star'),    1, 'first');

if includeContext
    if any([isempty(idxPos), isempty(idxContext), isempty(idxChair), isempty(idxDrum), isempty(idxStar)])
        error('Block 1/3 predictors must have headers: Pos, Context, Chair, Drum, Star. Got: %s', strjoin(varNames, ', '));
    end
    X = [predictor_tab{:, idxPos}, ...
         predictor_tab{:, idxContext}, ...
         predictor_tab{:, idxChair}, ...
         predictor_tab{:, idxDrum}, ...
         predictor_tab{:, idxStar}];
    names = {'Pos','Context','Chair','Drum','Star'};
else
    if any([isempty(idxPos), isempty(idxChair), isempty(idxDrum), isempty(idxStar)])
        error('Block 2 predictors must have headers: Pos, Chair, Drum, Star. Got: %s', strjoin(varNames, ', '));
    end
    X = [predictor_tab{:, idxPos}, ...
         predictor_tab{:, idxChair}, ...
         predictor_tab{:, idxDrum}, ...
         predictor_tab{:, idxStar}];
    names = {'Pos','Chair','Drum','Star'};
end

% Type/size guard
X = double(X);
if any(~isfinite(X(:)))
    fprintf('[GLM] WARNING: Non-finite values detected in predictors (NaN/Inf). glmfit will ignore them.\n');
end
end

function n = parse_vr_number(vrname)
tok = regexp(vrname, 'VR(\d+)', 'tokens', 'once');
if isempty(tok), error('Cannot parse VR number from "%s"', vrname); end
n = str2double(tok{1});
end

function s = tern(c, a, b)
if c, s = a; else, s = b; end
end
end