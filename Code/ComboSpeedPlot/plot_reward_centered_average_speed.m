function S = plot_reward_centered_average_speed(P, cfg, ax)
% PLOT_REWARD_CENTERED_AVERAGE_SPEED
% Plots the overall within-session speed +/- SEM. When enabled, colored
% curves show the same sequential lap blocks used by the acceleration panel.

axes(ax);
cla(ax);
hold(ax, 'on');

%% Across-lap center and SEM
switch lower(cfg.outerSpeedStatistic)
    case 'mean'
        centerSpeed = mean(P.speedMat, 1, 'omitnan');
        centerLabel = 'Mean';

    case 'median'
        centerSpeed = median(P.speedMat, 1, 'omitnan');
        centerLabel = 'Median';

    otherwise
        error('cfg.outerSpeedStatistic must be ''mean'' or ''median''.');
end

nPerBin = sum(isfinite(P.speedMat), 1);
semSpeed = std(P.speedMat, 0, 1, 'omitnan') ./ sqrt(nPerBin);
semSpeed(nPerBin == 0) = NaN;

if cfg.smoothMeanSpeedBins > 1
    centerSpeed = movmean( ...
        centerSpeed, ...
        cfg.smoothMeanSpeedBins, ...
        'omitnan');

    semSpeed = movmean( ...
        semSpeed, ...
        cfg.smoothMeanSpeedBins, ...
        'omitnan');
end

validCenter = isfinite(centerSpeed);

if ~any(validCenter)
    error('No valid across-lap speed curve.');
end

%% Matching lap-block speed curves
showGroups = isfield(cfg, 'showSpeedLapBlockCurves') && ...
    cfg.showSpeedLapBlockCurves;

if showGroups
    G = compute_speed_lap_group_curves(P, cfg);
else
    G = [];
end

%% Close the unfolded overall curve
edgeCenter = mean( ...
    [centerSpeed(1), centerSpeed(end)], ...
    'omitnan');

edgeSEM = mean( ...
    [semSpeed(1), semSpeed(end)], ...
    'omitnan');

xPlot = [-180, P.relativeCenters_deg, 180];
centerPlot = [edgeCenter, centerSpeed, edgeCenter];
semPlot = [edgeSEM, semSpeed, edgeSEM];

lowerPlot = centerPlot - semPlot;
upperPlot = centerPlot + semPlot;

goodBand = isfinite(xPlot) & ...
           isfinite(lowerPlot) & ...
           isfinite(upperPlot);

%% Select y-axis limits
if isfield(cfg, 'sharedSpeedYLim')
    speedYLim = cfg.sharedSpeedYLim;
else
    finiteValues = [ ...
        lowerPlot(isfinite(lowerPlot)), ...
        upperPlot(isfinite(upperPlot))];

    if showGroups
        groupValues = G.meanSpeed(isfinite(G.meanSpeed));
        finiteValues = [ ...
            finiteValues, ...
            groupValues(:).']; %#ok<AGROW>
    end

    if isempty(finiteValues)
        finiteValues = centerSpeed(validCenter);
    end

    dataMin = min(finiteValues);
    dataMax = max(finiteValues);
    dataRange = dataMax - dataMin;

    yPad = max(2, 0.10 * max(dataRange, 1));

    yMin = max(0, floor(dataMin - yPad));
    yMax = ceil(dataMax + yPad);

    if yMax <= yMin
        yMax = yMin + 5;
    end

    speedYLim = [yMin yMax];
end

%% Purple fill beneath overall curve
goodFill = isfinite(centerPlot);

fill(ax, ...
    [xPlot(goodFill), fliplr(xPlot(goodFill))], ...
    [speedYLim(1) * ones(1, sum(goodFill)), ...
     fliplr(centerPlot(goodFill))], ...
    [0.75 0.60 0.90], ...
    'FaceAlpha', 0.18, ...
    'EdgeColor', 'none', ...
    'HandleVisibility', 'off');

%% SEM band for overall curve
fill(ax, ...
    [xPlot(goodBand), fliplr(xPlot(goodBand))], ...
    [lowerPlot(goodBand), fliplr(upperPlot(goodBand))], ...
    [0.40 0.40 0.40], ...
    'FaceAlpha', 0.25, ...
    'EdgeColor', 'none', ...
    'HandleVisibility', 'off');

%% Overall speed curve
plot(ax, ...
    xPlot, ...
    centerPlot, ...
    'k-', ...
    'LineWidth', cfg.outerLineWidth, ...
    'DisplayName', sprintf('Overall %s', lower(centerLabel)));

%% Colored speed curves for the same lap blocks as acceleration
if showGroups
    for g = 1:G.nGroups

        groupCurve = G.meanSpeed(g, :);
        groupEdge = mean( ...
            [groupCurve(1), groupCurve(end)], ...
            'omitnan');

        groupPlot = [groupEdge, groupCurve, groupEdge];

        plot(ax, ...
            xPlot, ...
            groupPlot, ...
            '-', ...
            'Color', G.colors(g, :), ...
            'LineWidth', cfg.speedGroupLineWidth, ...
            'HandleVisibility', 'off');
    end
end

%% Summary values and reference lines
validValues = centerSpeed(validCenter);

minCenterSpeed = min(validValues);
avgCenterSpeed = mean(validValues);
maxCenterSpeed = max(validValues);

summarySpeeds = [ ...
    minCenterSpeed, ...
    avgCenterSpeed, ...
    maxCenterSpeed];

if cfg.showMeanSpeedSummaryCircles
    for k = 1:numel(summarySpeeds)
        yline(ax, summarySpeeds(k), ...
            'Color', cfg.summaryCircleColor, ...
            'LineStyle', cfg.summaryCircleLineStyle, ...
            'LineWidth', cfg.summaryCircleLineWidth, ...
            'HandleVisibility', 'off');
    end
end

%% Current and old reward locations
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
    'YLim', speedYLim, ...
    'XTick', relativeTicks, ...
    'XTickLabel', tickLabels, ...
    'FontSize', cfg.axisFontSize, ...
    'Layer', 'top');

xlabel(ax, 'Track position');
ylabel(ax, 'Speed (cm/s)');

if isfield(P, 'nTrialsTotal') && P.nTrials < P.nTrialsTotal
    lapCaption = sprintf( ...
        'First %d of %d laps', ...
        P.nTrials, ...
        P.nTrialsTotal);
else
    lapCaption = sprintf('All %d laps', P.nTrials);
end

mainTitle = sprintf( ...
    '%s   Min %.1f | %s %.1f | Max %.1f cm/s', ...
    lapCaption, ...
    minCenterSpeed, ...
    centerLabel, ...
    avgCenterSpeed, ...
    maxCenterSpeed);

if showGroups
    groupCaption = strjoin(G.labels(:).', ' | ');
    title(ax, ...
        {mainTitle; ['Colored curves: ' groupCaption]}, ...
        'FontWeight', 'normal', ...
        'FontSize', max(cfg.axisFontSize - 1, 8));
else
    title(ax, mainTitle, ...
        'FontWeight', 'normal', ...
        'FontSize', max(cfg.axisFontSize - 1, 8));
end

grid(ax, 'on');
box(ax, 'on');

S.minSpeed = minCenterSpeed;
S.centerSpeed = avgCenterSpeed;
S.maxSpeed = maxCenterSpeed;
S.rewardDeg = P.reward_deg;
S.nTrials = P.nTrials;

if showGroups
    S.groupMeanSpeed = G.meanSpeed;
    S.groupSEMSpeed = G.semSpeed;
    S.groupLabels = G.labels;
end

end
