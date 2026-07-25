function plot_circular_speed_figure(P, cfg, mouseName, sessionDate, trialLabel, ax)

axes(ax);
hold(ax, 'on');
axis(ax, 'equal');
axis(ax, 'off');

vals = P.speedMat(~isnan(P.speedMat));

if isempty(vals)
    error('No valid speed values after exclusions.');
end

if cfg.usePercentileColorMax
    cmax = prctile(vals, cfg.colorMaxPercentile);
else
    cmax = max(vals);
end

cmin = 0;
cmap = parula(256);

%% Trial heatmap
for p = 1:P.nTrials
    r1 = cfg.innerHoleR + cfg.heatmapScale * (p - 0.5);
    r2 = cfg.innerHoleR + cfg.heatmapScale * (p + 0.5);

    for b = 1:(numel(P.thetaEdges)-1)
        val = P.speedMat(p,b);

        if isnan(val)
            continue
        end

        valClamped = min(max(val, cmin), cmax);

        idxColor = round(1 + (size(cmap,1)-1) * ...
            (valClamped - cmin) / max(cmax-cmin, eps));

        idxColor = max(1, min(size(cmap,1), idxColor));
        thisColor = cmap(idxColor,:);

        th1 = P.thetaEdges(b);
        th2 = P.thetaEdges(b+1);

        xPatch = [r1*cos(th1), r2*cos(th1), r2*cos(th2), r1*cos(th2)];
        yPatch = [r1*sin(th1), r2*sin(th1), r2*sin(th2), r1*sin(th2)];

        patch(xPatch, yPatch, thisColor, 'EdgeColor', 'none');
    end
end

colormap(ax, cmap);
caxis(ax, [cmin cmax]);
cb = colorbar(ax);
ylabel(cb, 'Speed cm/s');

%% Center hole
thHole = linspace(0, 2*pi, 500);
[xHole, yHole] = pol2cart(thHole, cfg.innerHoleR * ones(size(thHole)));
fill(xHole, yHole, 'w', 'EdgeColor', 'k', 'LineWidth', 1.2);


%% Other licks as white circles
if ~isempty(P.lickTheta)
    [xLick, yLick] = pol2cart(P.lickTheta, P.lickRadius);
    plot(xLick, yLick, 'wo', ...
        'MarkerSize', cfg.lickDotSize, ...
        'MarkerFaceColor', 'w', ...
        'LineWidth', 0.5);
end


%% Reward omission trial licks (pink)

if isfield(P,'omissionLickTheta') && ~isempty(P.omissionLickTheta)

    [xOmit,yOmit] = pol2cart( ...
        P.omissionLickTheta, ...
        P.omissionLickRadius);

plot(xOmit, yOmit, 'o', ...
    'MarkerSize', cfg.omissionLickDotSize, ...
    'MarkerFaceColor', [1.0 0.4 0.75], ...
    'MarkerEdgeColor', [1.0 0.4 0.75], ...
    'LineWidth', 0.5);
end


%% Rewards
if ~isempty(P.rewardTheta)
    [xReward, yReward] = pol2cart(P.rewardTheta, P.rewardRadius);
    plot(xReward, yReward, 'r.', 'MarkerSize', cfg.rewardDotSize);
end

%% Outer speed plot
outerMaxR = cfg.innerHoleR + cfg.heatmapScale * (P.nTrials + 0.5);

minCenterSpeed = NaN;
avgCenterSpeed = NaN;
maxCenterSpeed = NaN;

if cfg.showOuterMeanSpeed

    switch lower(cfg.outerSpeedStatistic)
        case 'mean'
            centerSpeed = nanmean(P.speedMat, 1);
        case 'median'
            centerSpeed = nanmedian(P.speedMat, 1);
        otherwise
            error('outerSpeedStatistic must be ''mean'' or ''median''.');
    end

    nPerBin = sum(~isnan(P.speedMat), 1);
    semSpeed = nanstd(P.speedMat, 0, 1) ./ sqrt(nPerBin);
    semSpeed(nPerBin == 0) = NaN;

    if cfg.smoothMeanSpeedBins > 1
        centerSpeed = movmean(centerSpeed, cfg.smoothMeanSpeedBins, 'omitnan');
        semSpeed = movmean(semSpeed, cfg.smoothMeanSpeedBins, 'omitnan');
    end

    validCenter = centerSpeed(~isnan(centerSpeed));

    if ~isempty(validCenter)

        maxTrialR = cfg.innerHoleR + cfg.heatmapScale * (P.nTrials + 0.5);
        outerBaseR = maxTrialR + cfg.outerGapR;

        centerScaled = (centerSpeed - cfg.outerSpeedMin_cm_s) ./ ...
            (cfg.outerSpeedMax_cm_s - cfg.outerSpeedMin_cm_s);

        semScaled = semSpeed ./ ...
            (cfg.outerSpeedMax_cm_s - cfg.outerSpeedMin_cm_s);

        centerScaled(centerScaled < 0) = 0;
        centerScaled(centerScaled > 1) = 1;

        rCenter = outerBaseR + cfg.outerAmpR * centerScaled;
        rSEMlow = outerBaseR + cfg.outerAmpR * max(centerScaled - semScaled, 0);
        rSEMhigh = outerBaseR + cfg.outerAmpR * min(centerScaled + semScaled, 1);

        outerMaxR = outerBaseR + cfg.outerAmpR;

        thetaClosed = [P.thetaCenters, P.thetaCenters(1)];
        rCenterClosed = [rCenter, rCenter(1)];
        rLowClosed = [rSEMlow, rSEMlow(1)];
        rHighClosed = [rSEMhigh, rSEMhigh(1)];

        %% Purple fill between zero-speed circle and center-speed line
        goodCenter = ~isnan(rCenterClosed);

        [xBaseFill, yBaseFill] = pol2cart(thetaClosed(goodCenter), ...
            outerBaseR * ones(1, sum(goodCenter)));

        [xCenterFill, yCenterFill] = pol2cart(thetaClosed(goodCenter), ...
            rCenterClosed(goodCenter));

        fill([xBaseFill, fliplr(xCenterFill)], ...
             [yBaseFill, fliplr(yCenterFill)], ...
             [0.75 0.60 0.90], ...
             'FaceAlpha', 0.25, ...
             'EdgeColor', 'none');

        %% Grey SEM band
        goodSEM = ~isnan(rLowClosed) & ~isnan(rHighClosed);

        [xLow, yLow] = pol2cart(thetaClosed(goodSEM), rLowClosed(goodSEM));
        [xHigh, yHigh] = pol2cart(thetaClosed(goodSEM), rHighClosed(goodSEM));

        fill([xLow, fliplr(xHigh)], ...
             [yLow, fliplr(yHigh)], ...
             [0.40 0.40 0.40], ...
             'FaceAlpha', 0.45, ...
             'EdgeColor', 'none');

        %% Solid minimum-speed reference circle
        th = linspace(0, 2*pi, 500);
        [xZeroSpeed, yZeroSpeed] = pol2cart(th, outerBaseR * ones(size(th)));

        plot(xZeroSpeed, yZeroSpeed, ...
            'k-', ...
            'LineWidth', 1.5);

        %% Summary circles
        validSmoothedCenter = centerSpeed(~isnan(centerSpeed));

        minCenterSpeed = min(validSmoothedCenter);
        avgCenterSpeed = mean(validSmoothedCenter);
        maxCenterSpeed = max(validSmoothedCenter);

        summarySpeeds = [minCenterSpeed, avgCenterSpeed, maxCenterSpeed];

        thSummary = linspace(0, 2*pi, 500);

        if cfg.showMeanSpeedSummaryCircles
            for s = 1:numel(summarySpeeds)
                summaryScaled = (summarySpeeds(s) - cfg.outerSpeedMin_cm_s) ./ ...
                    (cfg.outerSpeedMax_cm_s - cfg.outerSpeedMin_cm_s);

                summaryScaled = max(0, min(1, summaryScaled));

                rSummary = outerBaseR + cfg.outerAmpR * summaryScaled;

                [xSummary, ySummary] = pol2cart(thSummary, ...
                    rSummary * ones(size(thSummary)));

                plot(xSummary, ySummary, ...
                    'Color', cfg.summaryCircleColor, ...
                    'LineStyle', cfg.summaryCircleLineStyle, ...
                    'LineWidth', cfg.summaryCircleLineWidth);
            end
        end

        %% Center-speed line
        [xCenter, yCenter] = pol2cart(thetaClosed(goodCenter), ...
            rCenterClosed(goodCenter));

        plot(xCenter, yCenter, 'k-', 'LineWidth', cfg.outerLineWidth);
    end
end

%% Optional reward guide line
if cfg.showRewardGuideLine
    guideLineStartR = cfg.innerHoleR;
    guideLineEndR   = cfg.innerHoleR + cfg.heatmapScale * (P.nTrials + 0.5);

    rewardThetaGuide = P.reward_deg / 360 * 2*pi;

    [xg, yg] = pol2cart( ...
        [rewardThetaGuide rewardThetaGuide], ...
        [guideLineStartR guideLineEndR]);

    plot(xg, yg, ...
        'Color', cfg.rewardGuideColor, ...
        'LineStyle', cfg.rewardGuideLineStyle, ...
        'LineWidth', cfg.rewardGuideLineWidth);
end

%% Redraw center hole and direction arrow
fill(xHole, yHole, 'w', 'EdgeColor', 'k', 'LineWidth', 1.2);

text(0, 0, '↺', ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'FontSize', 28, ...
    'FontWeight', 'bold', ...
    'Color', 'k');

%% Axis limits with room for caption
captionPad = 22;
axisLimitLeft = outerMaxR + 15;
axisLimitRight = outerMaxR + 15;
axisLimitTop = outerMaxR + 8;
axisLimitBottom = outerMaxR + captionPad;

xlim([-axisLimitLeft axisLimitRight]);
ylim([-axisLimitBottom axisLimitTop]);

%% Bottom caption: laps and min/mean/max
if strcmpi(cfg.outerSpeedStatistic, 'median')
    centerLabel = 'Median';
else
    centerLabel = 'Mean';
end

captionText = sprintf('All %d laps   Min %.1f | %s %.1f | Max %.1f cm/s', ...
    P.nTrialsTotal, minCenterSpeed, centerLabel, avgCenterSpeed, maxCenterSpeed);

text(0, -outerMaxR - 10, captionText, ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'top', ...
    'FontSize', cfg.axisFontSize - 2, ...
    'Color', [0.25 0.25 0.25]);

%% Title: animal ID and date only
title(sprintf('%s  %s', mouseName, sessionDate), ...
    'Interpreter', 'none', ...
    'FontSize', cfg.titleFontSize);

set(gca, 'FontSize', cfg.axisFontSize);

end