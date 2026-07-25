function plot_summary_bars(T, sessionTitle, cfg)

stateOrder_bar = { ...
    'cue_expected', ...
    'preReward_nonTarget', ...
    'preReward_target_near', ...
    'preReward_target_far'};

stateLabels_bar = { ...
    'Cue expected', ...
    'Pre-reward non-target', ...
    'Pre-reward target near', ...
    'Pre-reward target far'};

siteOrder = cfg.activeReward_deg;
siteLabels = arrayfun(@(x) sprintf('%.0f deg', x), siteOrder, 'UniformOutput', false);

M_speed = nan(numel(siteOrder), numel(stateOrder_bar));
SEM_speed = nan(numel(siteOrder), numel(stateOrder_bar));
M_decel = nan(numel(siteOrder), numel(stateOrder_bar));
SEM_decel = nan(numel(siteOrder), numel(stateOrder_bar));

for s = 1:numel(siteOrder)
    for st = 1:numel(stateOrder_bar)

        idx = T.siteDeg == siteOrder(s) & strcmp(T.state, stateOrder_bar{st});

        valsSpeed = T.approachSpeed(idx);
        valsSpeed = valsSpeed(~isnan(valsSpeed));

        valsDecel = T.rawDecel(idx);
        valsDecel = valsDecel(~isnan(valsDecel));

        if ~isempty(valsSpeed)
            M_speed(s,st) = cfg.summaryFcn(valsSpeed);
            SEM_speed(s,st) = std(valsSpeed) / sqrt(numel(valsSpeed));
        end

        if ~isempty(valsDecel)
            M_decel(s,st) = cfg.summaryFcn(valsDecel);
            SEM_decel(s,st) = std(valsDecel) / sqrt(numel(valsDecel));
        end
    end
end

figure;
tiledlayout(1,2);

nexttile;
bh1 = bar(M_speed);
hold on

for st = 1:numel(stateOrder_bar)
    xBar = bh1(st).XEndPoints;
    errorbar(xBar, M_speed(:,st), SEM_speed(:,st), 'k.', 'LineWidth', 1.2);
end

set(gca, 'XTick', 1:numel(siteOrder), ...
         'XTickLabel', siteLabels, ...
         'FontSize', cfg.axisFontSize);

ylabel(sprintf('%s speed in window ending %.1f° before site (cm/s)', ...
    cfg.summaryMethodName, cfg.excludeFinal_deg), ...
    'FontSize', cfg.labelFontSize);

xlabel('Reward site', 'FontSize', cfg.labelFontSize);
title('Approach speed', 'FontSize', cfg.titleFontSize);
grid on

nexttile;
bh2 = bar(M_decel);
hold on

for st = 1:numel(stateOrder_bar)
    xBar = bh2(st).XEndPoints;
    errorbar(xBar, M_decel(:,st), SEM_decel(:,st), 'k.', 'LineWidth', 1.2);
end

set(gca, 'XTick', 1:numel(siteOrder), ...
         'XTickLabel', siteLabels, ...
         'FontSize', cfg.axisFontSize);

ylabel(sprintf('Raw deceleration: %.0f-%.0f cm speed minus window ending %.1f° before site (cm/s)', ...
    cfg.decelControlWindow_cm(1), cfg.decelControlWindow_cm(2), cfg.excludeFinal_deg), ...
    'FontSize', cfg.labelFontSize);

xlabel('Reward site', 'FontSize', cfg.labelFontSize);
title('Raw deceleration', 'FontSize', cfg.titleFontSize);
grid on

legend(stateLabels_bar, 'FontSize', cfg.legendFontSize, 'Location', 'best');

sgtitle(sprintf('%s | Speed and raw deceleration by reward site and behavioral state', sessionTitle), ...
    'FontSize', cfg.titleFontSize + 1);

end