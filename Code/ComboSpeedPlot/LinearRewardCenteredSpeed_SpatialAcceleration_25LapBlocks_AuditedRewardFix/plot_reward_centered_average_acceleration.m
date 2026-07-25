function S = plot_reward_centered_average_acceleration(P, cfg, ax)
% PLOT_REWARD_CENTERED_AVERAGE_ACCELERATION
% Plots spatially derived signed acceleration for sequential within-session
% lap blocks.
%
% Positive values indicate speeding up.
% Negative values indicate slowing down.

axes(ax);
cla(ax);
hold(ax, 'on');

G = compute_acceleration_lap_group_curves(P, cfg);

%% Determine acceleration y-axis before optional SEM fills
if isfield(cfg, 'sharedAccelerationYLim')
    accelerationYLim = cfg.sharedAccelerationYLim;
else
    finiteMagnitude = [];

    for g = 1:G.nGroups
        if cfg.showAccelerationGroupSEM
            lowerCurve = G.meanAccel(g, :) - G.semAccel(g, :);
            upperCurve = G.meanAccel(g, :) + G.semAccel(g, :);

            finiteValues = [ ...
                lowerCurve(isfinite(lowerCurve)), ...
                upperCurve(isfinite(upperCurve))];
        else
            curve = G.meanAccel(g, :);
            finiteValues = curve(isfinite(curve));
        end

        finiteMagnitude = [ ...
            finiteMagnitude, ...
            abs(finiteValues)]; %#ok<AGROW>
    end

    if isempty(finiteMagnitude)
        yLimit = 1;
    else
        yLimit = 1.10 * max(finiteMagnitude);
    end

    if yLimit <= 10
        yLimit = ceil(yLimit);
    elseif yLimit <= 50
        yLimit = ceil(yLimit / 5) * 5;
    else
        yLimit = ceil(yLimit / 10) * 10;
    end

    yLimit = max(yLimit, 1);
    accelerationYLim = [-yLimit yLimit];
end

%% Plot each lap-block curve
lineHandles = gobjects(G.nGroups, 1);

for g = 1:G.nGroups

    meanCurve = G.meanAccel(g, :);
    semCurve = G.semAccel(g, :);

    edgeMean = mean( ...
        [meanCurve(1), meanCurve(end)], ...
        'omitnan');

    edgeSEM = mean( ...
        [semCurve(1), semCurve(end)], ...
        'omitnan');

    xPlot = [-180, P.relativeCenters_deg, 180];
    meanPlot = [edgeMean, meanCurve, edgeMean];
    semPlot = [edgeSEM, semCurve, edgeSEM];

    if cfg.showAccelerationGroupSEM
        lowerPlot = meanPlot - semPlot;
        upperPlot = meanPlot + semPlot;

        goodBand = isfinite(xPlot) & ...
                   isfinite(lowerPlot) & ...
                   isfinite(upperPlot);

        fill(ax, ...
            [xPlot(goodBand), fliplr(xPlot(goodBand))], ...
            [lowerPlot(goodBand), fliplr(upperPlot(goodBand))], ...
            G.colors(g, :), ...
            'FaceAlpha', 0.10, ...
            'EdgeColor', 'none', ...
            'HandleVisibility', 'off');
    end

    lineHandles(g) = plot(ax, ...
        xPlot, ...
        meanPlot, ...
        '-', ...
        'Color', G.colors(g, :), ...
        'LineWidth', cfg.accelerationGroupLineWidth, ...
        'DisplayName', G.labels{g});
end

%% Zero and reward references
yline(ax, 0, '--', ...
    'Color', [0.35 0.35 0.35], ...
    'LineWidth', 1.0, ...
    'HandleVisibility', 'off');

xline(ax, 0, '-', ...
    'Color', cfg.rewardGuideColor, ...
    'LineWidth', cfg.rewardGuideLineWidth, ...
    'HandleVisibility', 'off');

add_old_reward_location_line(ax, P, true);

%% Actual track-degree labels
relativeTicks = [-180 -90 0 90 180];
actualTicks = mod(P.reward_deg + relativeTicks, 360);

tickLabels = arrayfun( ...
    @(x) sprintf('%.0f%c', x, char(176)), ...
    actualTicks, ...
    'UniformOutput', false);

set(ax, ...
    'XLim', [-180 180], ...
    'YLim', accelerationYLim, ...
    'XTick', relativeTicks, ...
    'XTickLabel', tickLabels, ...
    'FontSize', cfg.axisFontSize, ...
    'Layer', 'top');

xlabel(ax, 'Track position');
ylabel(ax, 'Acceleration (cm/s^2)');

windowCm = cfg.spatialAccelerationWindowBins * cfg.binSize_cm;

title(ax, { ...
    sprintf('Signed acceleration by %d-lap block', ...
        cfg.accelerationLapBlockSize); ...
    sprintf('a = v dv/dx | quadratic fit, %d bins (~%.0f cm)', ...
        cfg.spatialAccelerationWindowBins, windowCm)}, ...
    'FontWeight', 'normal', ...
    'FontSize', max(cfg.axisFontSize - 1, 8));

lgd = legend(ax, ...
    lineHandles, ...
    G.labels, ...
    'Location', 'best', ...
    'Box', 'off', ...
    'FontSize', max(cfg.axisFontSize - 2, 7));

if G.nGroups > 5
    try
        lgd.NumColumns = 2;
    catch
    end
end

grid(ax, 'on');
box(ax, 'on');

S.groupMeanAcceleration = G.meanAccel;
S.groupSEMAcceleration = G.semAccel;
S.groupLabels = G.labels;
S.rewardDeg = P.reward_deg;
S.nTrials = P.nTrials;
S.spatialWindowBins = cfg.spatialAccelerationWindowBins;
S.spatialPolynomialOrder = cfg.spatialAccelerationPolyOrder;

end
