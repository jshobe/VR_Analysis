function plot_glm_beta_distributions(varargin)
% Overlay-only driver with fixed x-axis:
% - Shaded histogram bins (raw data)
% - Non-shaded KDE curves (smoothed data) on the same plot
% - X-axis fixed to a specified range (default: [-15, 15]) for all subplots
% - One figure per region (e.g., PPC and VC), pooled within each region
% - Centered zero line in every subplot
%
% Requires helpers on path:
%   collect_betas_for_block.m
%   detect_cell_type_label.m (optional)
%
% Options (Name-Value):
%   'BaseFolder'             : 'Z:\Justin\VR mice'
%   'Regions'                : {'PPC','VC'}
%   'SavePNGs'               : false
%   'OutDir'                 : ''            % default: <VR##>/Derived_V2/GLM_Beta_Distributions
%   'FigureVisible'          : 'on'|'off'
%   'HistBinWidth'           : []            % used for raw hist bins; if empty uses HistNumBins
%   'HistNumBins'            : 500
%   'OverlayLineWidth'       : 1.5           % line width for KDE curves
%   'OverlaySmooth'          : true          % draw KDE lines in addition to hist
%   'OverlaySmoothBandwidth' : []            % [] => auto ksdensity bandwidth; you can override
%   'OverlaySmoothNumPoints' : 256
%   'ShadeAlpha'             : 0.25          % transparency for shaded histograms
%   'FixedXLim'              : [-15 15]      % fix x-axis for all plots to this range
%   'Verbose'                : false
%   'FigureYOffsetInches'    : 0.5           % move figure down by this amount

% ---------------- Parse inputs ----------------
p = inputParser;
addParameter(p, 'BaseFolder', 'Z:\Justin\VR mice', @(s)ischar(s)||isstring(s));
addParameter(p, 'Regions', {'PPC','VC'}, @(c) iscellstr(c) || isstring(c));
addParameter(p, 'SavePNGs', false, @islogical);
addParameter(p, 'OutDir', '', @(s)ischar(s)||isstring(s));
addParameter(p, 'FigureVisible', 'on', @(s)ischar(s)||isstring(s));
addParameter(p, 'HistBinWidth', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
addParameter(p, 'HistNumBins', 500, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
addParameter(p, 'OverlayLineWidth', 1.5, @(x) isnumeric(x) && isscalar(x) && x>0);
addParameter(p, 'OverlaySmooth', true, @islogical);
addParameter(p, 'OverlaySmoothBandwidth', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
addParameter(p, 'OverlaySmoothNumPoints', 256, @(x) isnumeric(x) && isscalar(x) && x>=32);
addParameter(p, 'ShadeAlpha', 0.25, @(x) isnumeric(x) && isscalar(x) && x>=0 && x<=1);
addParameter(p, 'FixedXLim', [-15 15], @(v) isnumeric(v) && isvector(v) && numel(v)==2 && v(1)<v(2));
addParameter(p, 'Verbose', false, @islogical);
addParameter(p, 'FigureYOffsetInches', 0.5, @(x) isnumeric(x) && isscalar(x));
parse(p, varargin{:});
opt = p.Results;

% ---------------- Select animal ----------------
vrFolder = uigetdir(opt.BaseFolder, 'Select VR animal folder (VR##)');
if isequal(vrFolder, 0), error('No animal folder selected.'); end
[~, animalName] = fileparts(vrFolder);
fprintf('[beta plots] Animal: %s\n', animalName);

% ---------------- Load GLM unitdata per region ----------------
unitsAll = [];
for i = 1:numel(opt.Regions)
    region = char(opt.Regions{i});
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
    for c = 1:numel(u)
        u(c).Region = region;
        if exist('detect_cell_type_label', 'file')
            u(c).GroupLabel_celltype = detect_cell_type_label(u(c));
        else
            u(c).GroupLabel_celltype = 'Unknown';
        end
        u(c).GroupLabel_region   = region;
    end
    unitsAll = [unitsAll; u(:)]; %#ok<AGROW>
    fprintf('[beta plots] Loaded %d units from %s\n', numel(u), region);
end
if isempty(unitsAll), error('No units loaded from specified regions.'); end

% ---------------- Predictor schemas ----------------
PredictorsByBlock = {
    {'Pos','Context','Chair','Drum','Star'},  % Block 1
    {'Pos','Chair','Drum','Star'},            % Block 2 (no Context)
    {'Pos','Context','Chair','Drum','Star'}   % Block 3
};
allPredictors = {'Pos','Context','Chair','Drum','Star'};

% ---------------- Fixed edges for histograms (shared across predictors) ----------------
fixedMin = opt.FixedXLim(1);
fixedMax = opt.FixedXLim(2);

edgesFixedByPred = struct();
for pIx = 1:numel(allPredictors)
    pred = allPredictors{pIx};
    if ~isempty(opt.HistBinWidth)
        edges = fixedMin:opt.HistBinWidth:fixedMax;
        if edges(end) < fixedMax
            edges(end+1) = fixedMax; %#ok<AGROW>
        end
        if numel(edges) < 2
            edges = [fixedMin, fixedMax];
        end
    else
        edges = linspace(fixedMin, fixedMax, round(opt.HistNumBins)+1);
    end
    edgesFixedByPred.(pred) = edges;
end

% ---------------- Output directory (define once) ----------------
outDir = char(opt.OutDir);
if isempty(outDir)
    outDir = fullfile(vrFolder, 'Derived_V2', 'GLM_Beta_Distributions');
end
if ~exist(outDir, 'dir'), mkdir(outDir); end

% ---------------- Two figures: one for each requested region ----------------
set(0, 'DefaultFigureVisible', opt.FigureVisible);
cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', 'on'));

regionList = string(opt.Regions);  % e.g., ["PPC","VC"]
for rIx = 1:numel(regionList)
    regionName = regionList(rIx);

    % Filter units to this region
    unitsR = unitsAll(strcmp(string({unitsAll.Region}), regionName));
    if isempty(unitsR)
        fprintf('[beta plots] No units for %s; skipping figure.\n', char(regionName));
        continue;
    end

    % Build a trivial grouping (pool all units)
    groupNamesR = "AllUnits";
    groupsR     = repmat("AllUnits", numel(unitsR), 1);

    % Collect betas per block for this region only
    betaByGroupCellR = cell(1, 3);
    for b = 1:3
        betaByGroupCellR{b} = collect_betas_for_block(unitsR, b, PredictorsByBlock{b}, groupsR, groupNamesR);
    end

    % New figure for this region
    fig = figure('Color','w','Units','pixels','Position',[100 100 1200 800]);
    try
        set(fig,'Units','inches'); pos = get(fig,'Position');
        pos(2) = max(0, pos(2) - opt.FigureYOffsetInches);
        set(fig,'Position',pos); set(fig,'Units','pixels');
    catch
    end

    tl = tiledlayout(fig, numel(allPredictors), 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf('%s | %s | Overlay across Blocks (fixed x-axis [%g, %g]) | Hist shaded + KDE line', ...
        animalName, char(regionName), fixedMin, fixedMax), 'Interpreter','none');

    blockColors = lines(3);
    blockLabels = {'Block 1 (13)','Block 2 (2)','Block 3 (13)'};

    for pIx = 1:numel(allPredictors)
        pred = allPredictors{pIx};
        ax = nexttile(tl, pIx);
        hold(ax, 'on'); grid(ax, 'on');

        edges = edgesFixedByPred.(pred);
        xlim(ax, [fixedMin, fixedMax]);

        % Vertical zero line
        xline(ax, 0, '-', 'Color', [0 0 0], 'LineWidth', 1, 'HandleVisibility', 'off');

        lgHandles = gobjects(0);
        lgLabels  = {};
        hasAnyData = false;

        for b = 1:3
            % Only overlay if this block includes the predictor
            if ~any(strcmp(PredictorsByBlock{b}, pred)), continue; end

            % Raw data vector (betas) for this region/block/predictor
            vecAll = [];
            BBG = betaByGroupCellR{b};
            for g = 1:numel(BBG)
                if isfield(BBG(g), pred)
                    vecAll = [vecAll, BBG(g).(pred)]; %#ok<AGROW>
                end
            end
            vecAll = vecAll(isfinite(vecAll));
            if isempty(vecAll), continue; end
            hasAnyData = true;

            % 1) Raw histogram (shaded bins, no edges)
            histogram(ax, vecAll, 'BinEdges', edges, 'Normalization', 'pdf', ...
                      'FaceColor', blockColors(b,:), 'FaceAlpha', opt.ShadeAlpha, ...
                      'EdgeColor', 'none', 'HandleVisibility', 'off');

            % 2) KDE line (optional)
            if opt.OverlaySmooth && numel(vecAll) >= 5
                xi_eval = linspace(fixedMin, fixedMax, opt.OverlaySmoothNumPoints);
                if ~isempty(opt.OverlaySmoothBandwidth)
                    [f, xi_eval] = ksdensity(vecAll, xi_eval, 'Bandwidth', opt.OverlaySmoothBandwidth);
                    bw_used = opt.OverlaySmoothBandwidth;
                else
                    % Get auto bandwidth, then use a reduced bandwidth for less smoothing (factor = 5)
                    [~, ~, bw_auto] = ksdensity(vecAll, xi_eval);
                    bw_used = bw_auto/5;
                    [f, xi_eval] = ksdensity(vecAll, xi_eval, 'Bandwidth', bw_used);
                end
                hL = plot(ax, xi_eval, f, 'Color', blockColors(b,:), 'LineWidth', opt.OverlayLineWidth, ...
                          'LineStyle', '-', 'DisplayName', sprintf('%s n=%d', blockLabels{b}, numel(vecAll)));
                lgHandles(end+1) = hL; lgLabels{end+1} = hL.DisplayName;

                if opt.Verbose
                    fprintf('[beta plots] %s BW (Block %d, %s): %.4g (n=%d)\n', char(regionName), b, pred, bw_used, numel(vecAll));
                end
            else
                % If smoothing disabled or too few samples, show a mean marker
                m = mean(vecAll, 'omitnan');
                hMean = xline(ax, m, '-', 'Color', blockColors(b,:), 'LineWidth', opt.OverlayLineWidth, ...
                              'DisplayName', sprintf('%s n=%d (mean=%.3f)', blockLabels{b}, numel(vecAll), m));
                lgHandles(end+1) = hMean; lgLabels{end+1} = hMean.DisplayName;
            end
        end

        xlabel(ax, sprintf('Beta (%s)', pred));
        ylabel(ax, 'Density');
        title(ax, pred);
        if hasAnyData
            legend(ax, lgHandles, lgLabels, 'Location', 'best');
        else
            text(ax, 0.5, 0.5, 'No data', 'Units','normalized', 'HorizontalAlignment', 'center');
        end
    end

    % --- Optional save per region ---
    if opt.SavePNGs
        % Optional: save into a region subfolder for clarity
        outDirR = fullfile(outDir, char(regionName));  % e.g., .../GLM_Beta_Distributions/PPC
        if ~exist(outDirR, 'dir'), mkdir(outDirR); end

        outPng = fullfile(outDirR, sprintf('%s_%s_OverlayBlocks_FixedAxis.png', animalName, char(regionName)));
        try
            drawnow;  % ensure figure is rendered
            exportgraphics(fig, outPng, 'Resolution', 200);
            fprintf('[beta plots] Saved %s\n', outPng);
        catch ME
            warning('Failed to save %s: %s', outPng, ME.message);
        end

        % Optional: close(fig);  % to reduce window clutter
    end
end

fprintf('[beta plots] Done. Output dir: %s\n', outDir);
end