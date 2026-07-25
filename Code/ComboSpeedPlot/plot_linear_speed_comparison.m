function plot_linear_speed_comparison(Pall, cfg, labels, ax)

axes(ax);
hold(ax, 'on');

nFiles = numel(Pall);
curveHandles = gobjects(nFiles,1);

% Center of x-axis is the reward location from the first selected plot
referenceRewardDeg = Pall{1}.reward_deg;

allY = [];

for f = 1:nFiles

    P = Pall{f};

    switch lower(cfg.outerSpeedStatistic)
        case 'mean'
            y = nanmean(P.speedMat, 1);

        case 'median'
            y = nanmedian(P.speedMat, 1);

        otherwise
            error('outerSpeedStatistic must be ''mean'' or ''median''.');
    end

    if cfg.smoothMeanSpeedBins > 1
        y = movmean(y, cfg.smoothMeanSpeedBins, 'omitnan');
    end

    deg = P.centers_cm / cfg.track_cm * 360;

    % Rotate track coordinates so reference reward is centered at x = 180
    plotDeg = mod(deg - referenceRewardDeg + 180, 360);

    [plotDegSort, sortIdx] = sort(plotDeg);
    ySort = y(sortIdx);

    curveHandles(f) = plot(plotDegSort, ySort, 'LineWidth', 2);

    allY = [allY, ySort]; %#ok<AGROW>
end

validY = allY(~isnan(allY));

if ~isempty(validY)
    yMin  = min(validY);
    yMean = mean(validY);
    yMax  = max(validY);

    yline(yMin,  ':', sprintf('Min %.1f', yMin), ...
        'LineWidth', 1.2);

    yline(yMean, ':', sprintf('Mean %.1f', yMean), ...
        'LineWidth', 1.2);

    yline(yMax,  ':', sprintf('Max %.1f', yMax), ...
        'LineWidth', 1.2);
end

%% Reward lines matched to curve colors
%% Reward lines
for f = 1:nFiles
    thisRewardDeg = Pall{f}.reward_deg;
    rewardX = mod(thisRewardDeg - referenceRewardDeg + 180, 360);

    xline(rewardX, '--', sprintf('Reward %.0f°', thisRewardDeg), ...
        'Color', curveHandles(f).Color, ...
        'LineWidth', 1.3, ...
        'HandleVisibility', 'off');
end

xlim([0 360]);

xticks([0 90 180 270 360]);

xticklabels({ ...
    sprintf('%.0f°', mod(referenceRewardDeg - 180, 360)), ...
    sprintf('%.0f°', mod(referenceRewardDeg - 90,  360)), ...
    sprintf('%.0f°', mod(referenceRewardDeg,       360)), ...
    sprintf('%.0f°', mod(referenceRewardDeg + 90,  360)), ...
    sprintf('%.0f°', mod(referenceRewardDeg + 180, 360))});

xlabel(sprintf('Track position, centered on first selected reward location %.0f°', ...
    referenceRewardDeg));

ylabel('Average speed (cm/s)');
title('Average speed comparison across sessions');

legend(labels, 'Interpreter', 'none', 'Location', 'best');

set(gca, 'FontSize', cfg.axisFontSize);
grid on;

end
