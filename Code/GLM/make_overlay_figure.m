% File: +glmplots/make_overlay_figure.m
function make_overlay_figure(T, pred, blockList, xi_eval, edges, opt, blockColors)
fig = figure('Name', sprintf('Overlays: %s', pred), 'Color', 'w');
ax  = axes(fig); hold(ax, 'on'); grid(ax, 'on');
title(ax, sprintf('Overall KDE overlays by block — %s', pred), 'Interpreter', 'none');
xlabel(ax, sprintf('%s', pred), 'Interpreter', 'none');
ylabel(ax, 'Density');

for ib = 1:numel(blockList)
    b = blockList(ib);
    [vecAll, ~] = glmplots.get_block_data(T, pred, b);
    if ~opt.OverlaySmooth || numel(vecAll) < opt.MinN
        continue;
    end
    [f_overall, bw_overall] = glmplots.compute_kde(vecAll, xi_eval, opt.OverlaySmoothBandwidth);
    if opt.Verbose
        fprintf('[Figure A] Block %d, %s: BW=%.4g (n=%d)\n', b, pred, bw_overall, numel(vecAll));
    end
    glmplots.plot_line(ax, xi_eval, f_overall, blockColors(b,:), opt.OverlayLineWidth, '-', 'off', sprintf('Block %d', b));
end

xlim(ax, [edges(1) edges(2)]);
legend(ax, 'off'); % keep clean; turn on if desired
hold(ax, 'off');
end