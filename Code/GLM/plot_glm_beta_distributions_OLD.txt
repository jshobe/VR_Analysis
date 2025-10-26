function plot_glm_beta_distributions(varargin)
% PLOT_GLM_BETA_DISTRIBUTIONS
% Select a VR## animal; loads PPC and VC GLM unitdata and plots beta
% distributions per block with linked x-axis across blocks (per predictor).
%
% Options (Name-Value):
%   'BaseFolder'    : 'Z:\Justin\VR mice'
%   'Regions'       : {'PPC','VC'}
%   'GroupBy'       : 'none'|'region'|'celltype'
%   'SavePNGs'      : false
%   'OutDir'        : ''                % default: <VR##>/Derived_V2/GLM_Beta_Distributions
%   'FigureVisible' : 'on'|'off'
%   'LinkAcrossBlocks' : true           % harmonize x-limits per predictor across blocks
%   'HistBinWidth'     : []             % e.g., 0.05 (takes precedence over HistNumBins)
%   'HistNumBins'      : 500            % e.g., 30
%   'XLimPadding'      : 0.05           % fraction to pad global x-limits (per predictor), can be 0
%   'OverlayLineWidth'       : 1.0      % line width for overlay hist "stairs" in the 4th figure
%   'OverlaySmooth'          : false    % optional smoothing (kernel density) on the 4th figure
%   'OverlaySmoothBandwidth' : []       % bandwidth for ksdensity (if empty, MATLAB default is used)
%   'OverlaySmoothNumPoints' : 256      % evaluation points for smoothing curves
%   'OverlaySmoothLineWidth' : 1      % line width for smoothing curves
%
% Blocks/predictors:
%   Block 1 and 3 → 5 predictors: Pos, Context, Chair, Drum, Star
%   Block 2       → 4 predictors: Pos, Chair, Drum, Star (Context removed)
%
% GLM inputs:
%   unitdata(c).GLM.BlockN.names and b_coeffs, as produced by GLM_bare_auto.

% ---------------- Parse inputs ----------------
p = inputParser;
addParameter(p, 'BaseFolder', 'Z:\Justin\VR mice', @(s)ischar(s)||isstring(s));
addParameter(p, 'Regions', {'PPC','VC'}, @iscell);
addParameter(p, 'GroupBy', 'none', @(s)ischar(s)||isstring(s));
addParameter(p, 'SavePNGs', false, @islogical);
addParameter(p, 'OutDir', '', @(s)ischar(s)||isstring(s));
addParameter(p, 'FigureVisible', 'on', @(s)ischar(s)||isstring(s));
addParameter(p, 'LinkAcrossBlocks', true, @islogical);
addParameter(p, 'HistBinWidth', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
addParameter(p, 'HistNumBins', 500, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
addParameter(p, 'XLimPadding', 0.05, @(x) isnumeric(x) && isscalar(x) && x>=0);
addParameter(p, 'OverlayLineWidth', 0.01, @(x) isnumeric(x) && isscalar(x) && x>0);
addParameter(p, 'OverlaySmooth', true, @islogical);
addParameter(p, 'OverlaySmoothBandwidth', 0.1, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
addParameter(p, 'OverlaySmoothNumPoints', 256, @(x) isnumeric(x) && isscalar(x) && x>=32);
addParameter(p, 'OverlaySmoothLineWidth', 1.5, @(x) isnumeric(x) && isscalar(x) && x>0);
parse(p, varargin{:});
opt = p.Results;

% ---------------- Select animal ----------------
vrFolder = uigetdir(opt.BaseFolder, 'Select VR animal folder (VR##)');
if isequal(vrFolder, 0), error('No animal folder selected.'); end
[~, animalName] = fileparts(vrFolder);
fprintf('[beta plots] Animal: %s\n', animalName);

% ---------------- Load GLM unitdata per region ----------------
unitsAll = []; % pooled PPC+VC
for i = 1:numel(opt.Regions)
    region = opt.Regions{i};
    glmPath = fullfile(vrFolder, region, 'Derived_V2', sprintf('%s_%s_unitdata_GLM.mat', animalName, region));
    if exist(glmPath, 'file') ~= 2
        fprintf('[beta plots] Missing GLM file for %s: %s (skipping)\n', region, glmPath);
        continue;
    end
    S = load(glmPath);
    if ~isfield(S, 'unitdata') || isempty(S.unitdata)
        fprintf('[beta plots] unitdata missing/empty in %s (skipping)\n', glmPath);
        continue;
    end
    u = S.unitdata;
    % augment tags
    for c = 1:numel(u)
        u(c).Region = region;
        u(c).GroupLabel_celltype = detect_cell_type_label(u(c));
        u(c).GroupLabel_region   = region;
    end
    unitsAll = [unitsAll; u(:)]; %#ok<AGROW>
    fprintf('[beta plots] Loaded %d units from %s\n', numel(u), region);
end
if isempty(unitsAll), error('No units loaded from specified regions.'); end

% ---------------- Define blocks and predictor schemas ----------------
BlockKinds = {'13','2','13'};  % Block 1,2,3
PredictorsByBlock = {
    {'Pos','Context','Chair','Drum','Star'},  % Block 1
    {'Pos','Chair','Drum','Star'},            % Block 2
    {'Pos','Context','Chair','Drum','Star'}   % Block 3
};
allPredictors = {'Pos','Context','Chair','Drum','Star'};

% ---------------- Build group labels ----------------
groupMode = lower(string(opt.GroupBy));
switch groupMode
    case "none"
        groupNames = "AllUnits";           % string scalar instead of cell
        groupFunc  = @(u) repmat("AllUnits", numel(u), 1);
    case "region"
        groupNames = unique(string({unitsAll.GroupLabel_region}),'stable');
        groupFunc  = @(u) string({u.GroupLabel_region})';
    case "celltype"
        groupNames = unique(string({unitsAll.GroupLabel_celltype}), 'stable');
        groupFunc  = @(u) string({u.GroupLabel_celltype})';
    otherwise
        error('Invalid GroupBy: %s', opt.GroupBy);
end

% ---------------- Compute global x-limits per predictor (across blocks) ----------------
globalLimits = compute_global_limits(unitsAll, allPredictors, BlockKinds, opt.XLimPadding);

% ---------------- Output directory and figure visibility ----------------
outDir = char(opt.OutDir);
if isempty(outDir)
    outDir = fullfile(vrFolder, 'Derived_V2', 'GLM_Beta_Distributions');
end
if ~exist(outDir, 'dir'), mkdir(outDir); end

set(0, 'DefaultFigureVisible', opt.FigureVisible);
cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', 'on'));

% ---------------- Plot per block with linked x-axis limits ----------------
groups = groupFunc(unitsAll);
for b = 1:numel(BlockKinds)
    expectedPredictors = PredictorsByBlock{b};

    % Collect betas per predictor per group for this block
    betaByGroup = collect_betas_for_block(unitsAll, b, expectedPredictors, groups, groupNames);

    % Prepare histogram edges per predictor (consistent across blocks/groups)
    edgesByPred = make_hist_edges(expectedPredictors, globalLimits, opt.HistBinWidth, opt.HistNumBins);

    % Plot
    fig = figure('Color','w','Units','pixels','Position',[100 100 1200 800]);
    tl = tiledlayout(fig, numel(expectedPredictors), 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf('%s | Block %d (%s) | GroupBy: %s', animalName, b, BlockKinds{b}, opt.GroupBy), 'Interpreter','none');

    cmap = lines(numel(groupNames));
    for pIx = 1:numel(expectedPredictors)
        pred = expectedPredictors{pIx};
        ax = nexttile(tl, pIx);
        hold(ax, 'on'); grid(ax, 'on');

        edges = edgesByPred.(pred);
        xlim(ax, [edges(1), edges(end)]);  % linked x-axis per predictor across blocks

        hasData = false(1, numel(groupNames));
        for g = 1:numel(groupNames)
            vec = betaByGroup(g).(pred);
            vec = vec(isfinite(vec));
            if isempty(vec), continue; end
            hasData(g) = true;
            histogram(ax, vec, 'BinEdges', edges, 'Normalization', 'pdf', ...
                      'FaceColor', cmap(g,:), 'FaceAlpha', 0.25, 'EdgeColor', 'none');
            % Kernel density overlay (optional, robust)
            if numel(vec) >= 5
                try
                    [f, xi] = ksdensity(vec);
                    plot(ax, xi, f, 'Color', cmap(g,:), 'LineWidth', 2, 'DisplayName', sprintf('%s (n=%d)', groupNames{g}, numel(vec)));
                catch
                    % skip if ksdensity unavailable
                end
            else
                m = mean(vec, 'omitnan');
                xline(ax, m, '-', sprintf('%s mean=%.3f (n=%d)', groupNames{g}, m, numel(vec)), 'Color', cmap(g,:), 'LineWidth', 1.5);
            end
        end

        xlabel(ax, sprintf('Beta (%s)', pred));
        ylabel(ax, 'Density');
        title(ax, pred);
        if any(hasData), legend(ax, 'Location', 'best'); else, text(ax, 0.5, 0.5, 'No data', 'Units','normalized', 'HorizontalAlignment','center'); end
    end

    % Save PNG (optional)
    if opt.SavePNGs
        outPng = fullfile(outDir, sprintf('%s_Block%d_%s_GroupBy_%s.png', animalName, b, BlockKinds{b}, opt.GroupBy));
        try
            exportgraphics(fig, outPng, 'Resolution', 200);
            fprintf('[beta plots] Saved %s\n', outPng);
        % catch ME
        %     warning('[beta plots] Failed to save PNG: %s', ME.message);
        end
    end
end

% ---------------- Fourth figure: overlay blocks per predictor (pooled across groups) ----------------
% Strict: only overlay blocks that include the predictor. Context is absent in Block 2.
overlayEdgesByPred = make_hist_edges(allPredictors, globalLimits, opt.HistBinWidth, opt.HistNumBins);

% Pre-collect betas per block/group using the strict collector (then pool groups)
betaByGroupCell = cell(1, numel(BlockKinds));
for b = 1:numel(BlockKinds)
    betaByGroupCell{b} = collect_betas_for_block(unitsAll, b, PredictorsByBlock{b}, groups, groupNames);
end

blockColors = lines(numel(BlockKinds));  % distinct color per block
fig = figure('Color','w','Units','pixels','Position',[100 100 1200 800]);
tl = tiledlayout(fig, numel(allPredictors), 1, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, sprintf('%s | Overlay across Blocks (pooled) | GroupBy: %s', animalName, opt.GroupBy), 'Interpreter','none');

for pIx = 1:numel(allPredictors)
    pred = allPredictors{pIx};
    ax = nexttile(tl, pIx);
    hold(ax, 'on'); grid(ax, 'on');

    % Common edges and x-limits for overlay per predictor
    edges = overlayEdgesByPred.(pred);
    xlim(ax, [edges(1), edges(end)]);

    lgHandles = gobjects(0);
    lgLabels  = {};
    hasAnyData = false;

    for b = 1:numel(BlockKinds)
        % Strict: only plot if this block actually includes the predictor
        if ~any(strcmp(PredictorsByBlock{b}, pred))
            continue;
        end

        % Pool betas across all groups for this block and predictor
        vecAll = [];
        BBG = betaByGroupCell{b};
        for g = 1:numel(BBG)
            if isfield(BBG(g), pred)
                vecAll = [vecAll, BBG(g).(pred)]; %#ok<AGROW>
            end
        end
        vecAll = vecAll(isfinite(vecAll));
        if isempty(vecAll)
            continue;
        end
        hasAnyData = true;

        % Overlay as "stairs" outlines for clarity
        h = histogram(ax, vecAll, 'BinEdges', edges, 'Normalization', 'pdf', ...
                      'DisplayStyle', 'stairs', 'EdgeColor', blockColors(b,:), 'LineWidth', opt.OverlayLineWidth, ...
                      'FaceColor', 'none', 'DisplayName', sprintf('Block %d (%s) n=%d', b, BlockKinds{b}, numel(vecAll)));
        lgHandles(end+1) = h; %#ok<AGROW>
        lgLabels{end+1}  = h.DisplayName; %#ok<AGROW>

        % Optional smoothing (kernel density) overlay for this block
% Optional smoothing (kernel density) overlay for this block
if opt.OverlaySmooth && numel(vecAll) >= 5
    try
        xi_eval = linspace(edges(1), edges(end), opt.OverlaySmoothNumPoints);

        if ~isempty(opt.OverlaySmoothBandwidth)
            % Use the specified bandwidth and capture it
            [f, xi_eval, bw] = ksdensity(vecAll, xi_eval, 'Bandwidth', opt.OverlaySmoothBandwidth);
        else
            % Use MATLAB's automatic bandwidth selection and capture it
            [f, xi_eval, bw] = ksdensity(vecAll, xi_eval);
        end

        % Print chosen bandwidth to Command Window
        fprintf('Overlay BW (Block %d, %s): %.4g (n=%d)\n', b, pred, bw, numel(vecAll));

        % Plot the smoothed curve
        plot(ax, xi_eval, f, 'Color', blockColors(b,:), 'LineWidth', opt.OverlaySmoothLineWidth, ...
             'LineStyle', '-', 'HandleVisibility', 'off'); % hide to keep legend clean
    catch
        % If ksdensity errors (e.g., all identical values), skip smoothing for this block
    end
end
    end

    xlabel(ax, sprintf('Beta (%s)', pred));
    ylabel(ax, 'Density');
    title(ax, pred);
    if hasAnyData
        legend(ax, lgHandles, lgLabels, 'Location', 'best');
    else
        text(ax, 0.5, 0.5, 'No data', 'Units','normalized', 'HorizontalAlignment','center');
    end
end

% Save PNG (optional)
if opt.SavePNGs
    outPng = fullfile(outDir, sprintf('%s_OverlayBlocks_Pooled.png', animalName));
    try
        exportgraphics(fig, outPng, 'Resolution', 200);
        fprintf('[beta plots] Saved %s\n', outPng);
    % catch ME
    %     warning('[beta plots] Failed to save PNG: %s', ME.message);
    end
end

fprintf('[beta plots] Done. Output dir: %s\n', outDir);
end

% ---------------- Helpers ----------------
function label = detect_cell_type_label(u)
candidates = {'CellType','cell_type','WaveformClass','waveform_class','Type','type','Class','class'};
label = 'Unknown';
for i = 1:numel(candidates)
    fn = candidates{i};
    if isfield(u, fn) && ~isempty(u.(fn))
        try
            v = string(u.(fn));
            if strlength(v) > 0
                label = char(v);
                return;
            end
        catch
        end
    end
end
end

function globalLimits = compute_global_limits(unitsAll, predictors, BlockKinds, padFrac)
% Aggregate all betas across all blocks and compute global min/max per predictor
globalLimits = struct();
for p = 1:numel(predictors)
    pred = predictors{p};
    allVals = [];
    for b = 1:numel(BlockKinds)
        glmField = sprintf('Block%d', b);
        for c = 1:numel(unitsAll)
            if ~isfield(unitsAll(c),'GLM') || ~isfield(unitsAll(c).GLM, glmField), continue; end
            G = unitsAll(c).GLM.(glmField);
            if ~isfield(G,'b_coeffs') || ~isfield(G,'names') || isempty(G.b_coeffs), continue; end
            names = string(G.names(:)');
            betas = double(G.b_coeffs(:)');
            ix = find(names == string(pred), 1, 'first');
            if ~isempty(ix)
                val = betas(ix);
                if isfinite(val), allVals(end+1) = val; %#ok<AGROW>
                end
            end
        end
    end
    if isempty(allVals)
        globalLimits.(pred) = [-1, 1]; % fallback
    else
        mn = min(allVals);
        mx = max(allVals);
        if mn == mx
            % expand tiny range so bins work
            delta = max(1e-6, abs(mn)*0.01);
            mn = mn - delta; mx = mx + delta;
        end
        span = mx - mn;
        pad = padFrac * span;
        globalLimits.(pred) = [mn - pad, mx + pad];
    end
end
end

function edgesByPred = make_hist_edges(predList, globalLimits, binWidth, numBins)
% Build consistent histogram edges per predictor using global limits
edgesByPred = struct();
for p = 1:numel(predList)
    pred = predList{p};
    lim = globalLimits.(pred);
    if ~isempty(binWidth)
        % Fixed width edges
        start = lim(1);
        stop  = lim(2);
        nSteps = max(1, ceil((stop - start) / binWidth));
        edges = linspace(start, stop, nSteps+1);
    elseif ~isempty(numBins)
        edges = linspace(lim(1), lim(2), numBins+1);
    else
        % MATLAB default NumBins with consistent edges per tile: choose 30
        edges = linspace(lim(1), lim(2), 30+1);
    end
    edgesByPred.(pred) = edges;
end
end

function betaByGroup = collect_betas_for_block(unitsAll, blockNum, expectedPredictors, groups, groupNames)
% Build struct per group with vectors of betas per expected predictor for one block
% Strict: no fallbacks; normalizes groupNames/groups to string arrays.

% Normalize types
groupNames = string(groupNames(:));  % ensure column string array
groups     = string(groups(:));      % ensure column string array

% Initialize output struct
betaByGroup = struct();
for g = 1:numel(groupNames)
    betaByGroup(g).Group = groupNames(g);  % keep as string
    for p = 1:numel(expectedPredictors)
        betaByGroup(g).(expectedPredictors{p}) = [];
    end
end

% Iterate units
for c = 1:numel(unitsAll)
    gName = groups(c);
    gIdx  = find(groupNames == gName, 1, 'first');
    if isempty(gIdx), continue; end

    glmField = sprintf('Block%d', blockNum);
    if ~isfield(unitsAll(c), 'GLM') || ~isfield(unitsAll(c).GLM, glmField)
        continue;
    end
    G = unitsAll(c).GLM.(glmField);
    if ~isfield(G,'b_coeffs') || ~isfield(G,'names') || isempty(G.b_coeffs) || isempty(G.names)
        continue;
    end

    names = string(G.names(:)');
    betas = double(G.b_coeffs(:)');

    % Map betas into expected predictor order; missing predictors get NaN
    for p = 1:numel(expectedPredictors)
        pred = string(expectedPredictors{p});
        ix = find(names == pred, 1, 'first');
        val = NaN;
        if ~isempty(ix)
            val = betas(ix);
        end
        predChar = char(pred);  % dynamic field name must be char
        betaByGroup(gIdx).(predChar) = [betaByGroup(gIdx).(predChar), val]; %#ok<AGROW>
    end
end
end