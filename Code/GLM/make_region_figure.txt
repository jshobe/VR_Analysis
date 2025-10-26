% File: +glmplots/make_region_figure.m
function make_region_figure(T, pred, blockList, xi_eval, edges, opt, blockColors)
fig = figure('Name', sprintf('Region overlays: %s', pred), 'Color', 'w');
tlo = tiledlayout(fig, numel(blockList), 1, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tlo, sprintf('KDE overlays by region (PPC/VC/HC) — %s', pred), 'Interpreter', 'none');

for ib = 1:numel(blockList)
    b  = blockList(ib);
    ax = nexttile(tlo); hold(ax, 'on'); grid(ax, 'on');

    [vecAll, regionAll] = glmplots.get_block_data(T, pred, b);
    if numel(vecAll) < opt.RegionFigureMinN
        title(ax, sprintf('Block %d — insufficient data (n=%d)', b, numel(vecAll)));
        hold(ax, 'off'); continue;
    end

    % Overall curve (optional, faint)
    bw_overall = [];
    if opt.RegionFigureShowOverall
        [f_overall, bw_overall] = glmplots.compute_kde(vecAll, xi_eval, opt.OverlaySmoothBandwidth);
        colOverall = blockColors(b,:);
        glmplots.plot_line(ax, xi_eval, f_overall, colOverall, max(0.75, opt.OverlayLineWidth-0.5), '-', 'off', '');
    end

    % Choose bandwidth mode
    if strcmpi(opt.OverlayRegionBandwidthMode, 'global')
        if ~isempty(opt.OverlaySmoothBandwidth)
            bw_use = opt.OverlaySmoothBandwidth;
        elseif ~isempty(bw_overall)
            bw_use = bw_overall;
        else
            % derive from all data if no overall computed
            [~, bw_use] = glmplots.compute_kde(vecAll, xi_eval, []);
        end
    else
        bw_use = []; % auto per region
    end

    % Region overlays
    for r = 1:numel(opt.OverlayRegions)
        rn  = char(opt.OverlayRegions{r});
        idx = strcmp(regionAll, rn);
        n_r = nnz(idx);
        if n_r < opt.RegionFigureMinN
            if opt.Verbose
                fprintf('[Figure B] %s skipped (Block %d, %s): n=%d < %d\n', rn, b, pred, n_r, opt.RegionFigureMinN);
            end
            continue;
        end

        if isempty(bw_use)
            [f_r, bw_r] = glmplots.compute_kde(vecAll(idx), xi_eval, opt.OverlaySmoothBandwidth);
            modeLabel = 'auto';
        else
            [f_r, bw_r] = glmplots.compute_kde(vecAll(idx), xi_eval, bw_use);
            modeLabel = 'global';
        end

        % Pick color for region
        if isfield(opt.OverlayRegionColors, rn)
            col = opt.OverlayRegionColors.(rn);
        else
            col = [0 0 0];
        end

        glmplots.plot_line(ax, xi_eval, f_r, col, opt.OverlayRegionLineWidth, '--', ...
            glmplots.tern(opt.OverlayRegionShowLegend, 'on', 'off'), sprintf('%s (%s)', rn, modeLabel));

        if opt.Verbose
            fprintf('[Figure B] %s BW (%s) (Block %d, %s): %.4g (n=%d)\n', rn, modeLabel, b, pred, bw_r, n_r);
        end
    end

    xlim(ax, [edges(1) edges(2)]);
    ylabel(ax, 'Density');
    title(ax, sprintf('Block %d — %s', b, pred), 'Interpreter', 'none');
    if opt.OverlayRegionShowLegend
        legend(ax, 'show', 'Location', 'best');
    end
    hold(ax, 'off');
end

xlabel(tlo, sprintf('%s', pred), 'Interpreter', 'none');
end