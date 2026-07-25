function plot_reward_centered_trial_speed( ...
    P, cfg, mouseName, sessionDate, ax)
% PLOT_REWARD_CENTERED_TRIAL_SPEED
% Linear reward-centered lap-by-position speed heatmap.
%
% Lap 1 is at the top. Later laps progress downward.
% Short missing runs can be interpolated for display only. P.speedMat is
% never modified, so speed averages and acceleration calculations are unchanged.

axes(ax);
cla(ax);
hold(ax, 'on');

vals = P.speedMat(isfinite(P.speedMat));

if isempty(vals)
    error('No valid speed values after exclusions.');
end

%% Select color limits
% By default, every heatmap derives its own color maximum from that
% session. A shared limit is used only when explicitly enabled.
useSharedHeatmapScale = ...
    isfield(cfg, 'useSharedHeatmapScale') && ...
    cfg.useSharedHeatmapScale && ...
    isfield(cfg, 'sharedHeatmapCLim');

if useSharedHeatmapScale
    heatmapCLim = cfg.sharedHeatmapCLim;
else
    if cfg.usePercentileColorMax
        cmax = prctile(vals, cfg.colorMaxPercentile);
    else
        cmax = max(vals);
    end

    heatmapCLim = [0 max(cmax, eps)];
end

%% Heatmap display copy
% Interpolation is applied only to this local plotting matrix. The original
% P.speedMat remains unchanged and is still used by all downstream analyses.
if ~isfield(cfg, 'interpolateHeatmapForDisplay')
    cfg.interpolateHeatmapForDisplay = true;
end

if ~isfield(cfg, 'heatmapDisplayMaxGapBins')
    cfg.heatmapDisplayMaxGapBins = 2;
end

speedMatDisplay = P.speedMat;

if cfg.interpolateHeatmapForDisplay
    speedMatDisplay = fill_short_circular_nan_gaps( ...
        speedMatDisplay, ...
        cfg.heatmapDisplayMaxGapBins);
end

hImg = imagesc( ...
    ax, ...
    P.relativeCenters_deg, ...
    1:P.nTrials, ...
    speedMatDisplay);

set(hImg, 'AlphaData', isfinite(speedMatDisplay));

set(ax, ...
    'YDir', 'reverse', ...
    'Color', [0 0 0], ...
    'Layer', 'top', ...
    'FontSize', cfg.axisFontSize);

colormap(ax, parula(256));
caxis(ax, heatmapCLim);

xlim(ax, [-180 180]);
ylim(ax, [0.5 P.nTrials + 0.5]);

%% Current reward center
xline(ax, 0, ':', ...
    'Color', [0.25 0.25 0.25], ...
    'LineWidth', 1.2);

%% Old reward location for shifted later sessions
add_old_reward_location_line(ax, P, true);

%% Rewarded-trial licks: white
if ~isempty(P.lickX_deg)
    scatter(ax, ...
        P.lickX_deg, ...
        P.lickLap, ...
        max(cfg.lickDotSize, 1)^2, ...
        'o', ...
        'filled', ...
        'MarkerFaceColor', [1 1 1], ...
        'MarkerEdgeColor', [1 1 1]);
end

%% Reward-omission-trial licks: pink
if ~isempty(P.omissionLickX_deg)
    scatter(ax, ...
        P.omissionLickX_deg, ...
        P.omissionLickLap, ...
        max(cfg.omissionLickDotSize, 1)^2, ...
        'o', ...
        'filled', ...
        'MarkerFaceColor', [1.0 0.4 0.75], ...
        'MarkerEdgeColor', [1.0 0.4 0.75]);
end

%% Reward deliveries: red
if ~isempty(P.rewardX_deg)
    scatter(ax, ...
        P.rewardX_deg, ...
        P.rewardLap, ...
        max(cfg.rewardDotSize, 1)^2, ...
        '.', ...
        'MarkerEdgeColor', [1 0 0]);
end

%% Labels
ylabel(ax, 'Lap');

title(ax, sprintf('%s  %s', mouseName, sessionDate), ...
    'Interpreter', 'none', ...
    'FontSize', cfg.titleFontSize);

set(ax, ...
    'XTick', [-180 -90 0 90 180], ...
    'XTickLabel', []);

cb = colorbar(ax);
ylabel(cb, 'Speed cm/s');

box(ax, 'on');

end


function Mout = fill_short_circular_nan_gaps(Min, maxGapBins)
% FILL_SHORT_CIRCULAR_NAN_GAPS
% Linearly fills short NaN runs within each heatmap row. The first and last
% spatial bins are treated as adjacent because the track is circular.
%
% This helper is intentionally local to the plotting function so the filled
% values cannot propagate into speed summaries or acceleration calculations.

Mout = Min;

if isempty(Min) || ~isfinite(maxGapBins) || maxGapBins < 1
    return
end

maxGapBins = floor(maxGapBins);

for r = 1:size(Min, 1)
    y = Min(r, :);
    finiteIdx = find(isfinite(y));

    if numel(finiteIdx) < 2
        continue
    end

    % Rotate so the row begins with a measured value. This converts any gap
    % crossing the -180/180 display boundary into a trailing circular gap.
    firstFinite = finiteIdx(1);
    yRot = circshift(y, 1 - firstFinite);
    n = numel(yRot);

    i = 2;
    while i <= n
        if isfinite(yRot(i))
            i = i + 1;
            continue
        end

        gapStart = i;
        while i <= n && ~isfinite(yRot(i))
            i = i + 1;
        end

        gapEnd = i - 1;
        gapLength = gapEnd - gapStart + 1;

        if gapLength > maxGapBins
            continue
        end

        leftIndex = gapStart - 1;
        leftValue = yRot(leftIndex);

        if i <= n
            rightIndex = i;
            rightValue = yRot(rightIndex);
        else
            % Circular continuation: bin n is followed by bin 1.
            rightIndex = n + 1;
            rightValue = yRot(1);
        end

        if ~isfinite(leftValue) || ~isfinite(rightValue)
            continue
        end

        for k = gapStart:gapEnd
            fraction = (k - leftIndex) / (rightIndex - leftIndex);
            yRot(k) = leftValue + fraction * (rightValue - leftValue);
        end
    end

    Mout(r, :) = circshift(yRot, firstFinite - 1);
end

end
