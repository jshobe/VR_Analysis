clear; clc;

%% USER SETTINGS
track_cm = 480;
binSize_cm = 3;

% Outer speed statistic
outerSpeedStatistic = 'mean';   % options: 'mean' or 'median'

% Remove bins near 0/360 wrap from outer speed plot
excludeWrapBins = 0;              % try 0, 1, 2, or 3

% Single reward location
reward_deg = 90;   % change if needed; guide line is off by default

% Speed exclusion
minSpeed_cm_s = 0.1;
useSpeedThreshold = false;

speedWindow_cm_forPlot = 5;   % use 5 cm window; increase to 10 for smoother speed

% Outer mean speed smoothing
smoothMeanSpeedBins = 1;   % 1 = no smoothing, 3/5/7 = more smoothing

% Color scaling
usePercentileColorMax = true;
colorMaxPercentile = 99;

% Dots
rewardDotSize = 10;
lickDotSize   = 0.5;

% Reward guide line
showRewardGuideLine = false;
rewardGuideColor = [1 0 0];
rewardGuideLineStyle = '-';
rewardGuideLineWidth = 1.5;

% Summary circles
showMeanSpeedSummaryCircles = true;
summaryCircleColor = [0.25 0.25 0.25];
summaryCircleLineStyle = ':';
summaryCircleLineWidth = 1.2;

% Heatmap radial layout
heatmapScale = 0.78;
innerHoleR = 30;

% Outer average-speed line graph
showOuterMeanSpeed = true;
outerGapR = 8;
outerAmpR = 50;
outerLineWidth = 1;

% Absolute speed scale for outer line
outerSpeedMin_cm_s = 20;
outerSpeedMax_cm_s = 120;

axisFontSize  = 14;
titleFontSize = 16;

%% Remember last folder
settingsFile = fullfile(tempdir, 'lastVRFolder_singleRewardCircular.mat');

if exist(settingsFile, 'file')
    S = load(settingsFile, 'lastFolder');
    if isfield(S, 'lastFolder') && exist(S.lastFolder, 'dir')
        startFolder = S.lastFolder;
    else
        startFolder = pwd;
    end
else
    startFolder = pwd;
end

%% Select file
[file, path] = uigetfile(fullfile(startFolder, '*.txt'), 'Select VR session file');

if isequal(file,0)
    error('No file selected.');
end

fname = fullfile(path, file);
lastFolder = path;
save(settingsFile, 'lastFolder');

%% Parse mouse/date from filename
[~, baseName, ~] = fileparts(file);

% Works for JB mice, MS mice, and similar two-letter mouse IDs
mouseTok = regexp(baseName, '([A-Za-z]{2}\d+)', 'tokens', 'once');

if ~isempty(mouseTok)
    mouseName = mouseTok{1};
else
    mouseName = 'UnknownMouse';
end

dateTok = regexp(baseName, '(\d{4}-\d{2}-\d{2})', 'tokens', 'once');
if ~isempty(dateTok)
    sessionDate = dateTok{1};
else
    sessionDate = 'UnknownDate';
end

%% Read file
% Expected text format:
% 1 time_s
% 2 distance_traveled
% 3 position(deg)
% 4 visual_state
% 5 next_RW_location_idx
% 6 reward_delivered
% 7 brake_applied, ignored
% 8 lick_detection
% 9 blackout_cue_identity, ignored

fid = fopen(fname, 'r');
if fid == -1
    error('Could not open file.');
end

fgetl(fid); % skip header
C = textscan(fid, '%f%f%f%f%f%f%f%f%f', 'TreatAsEmpty', {'NaN','nan'});
fclose(fid);

t       = C{1};
pos_deg = C{3};
reward  = C{6};
lick    = C{8};

valid = ~isnan(t) & ~isnan(pos_deg) & ~isnan(reward) & ~isnan(lick);

t       = t(valid);
pos_deg = pos_deg(valid);
reward  = reward(valid);
lick    = lick(valid);

if numel(t) < 2
    error('Not enough valid samples.');
end

%% Position variables
pos_cm_wrapped   = mod((pos_deg / 360) * track_cm, track_cm);
pos_cm_unwrapped = rad2deg(unwrap(deg2rad(pos_deg))) / 360 * track_cm;

%% Window-based speed from unwrapped position


speed_cm_s = nan(size(pos_cm_unwrapped));

for i = 1:numel(pos_cm_unwrapped)

    targetPos = pos_cm_unwrapped(i) - speedWindow_cm_forPlot;

    j = find(pos_cm_unwrapped <= targetPos, 1, 'last');

    if ~isempty(j) && t(i) > t(j)
        speed_cm_s(i) = (pos_cm_unwrapped(i) - pos_cm_unwrapped(j)) / ...
                        (t(i) - t(j));
    end
end

speed_cm_s(~isfinite(speed_cm_s)) = NaN;

%% Optional low-speed exclusion
if useSpeedThreshold
    speed_cm_s(speed_cm_s < minSpeed_cm_s) = NaN;
end

%% Diagnostic plots
raw_dt = diff(t);
raw_dpos_cm = abs(diff(pos_cm_unwrapped));
raw_speed = [NaN; raw_dpos_cm ./ raw_dt];

figure
subplot(3,1,1)
plot(raw_speed,'k')
ylabel('Speed')
title('Raw speed')

subplot(3,1,2)
plot(raw_dt,'k')
ylabel('dt')
title('Time step')

subplot(3,1,3)
plot(raw_dpos_cm,'k')
ylabel('dPos')
xlabel('Sample')
title('Position step')

%% Diagnose raw speed spikes
raw_dt = diff(t);
raw_dpos_cm = abs(diff(pos_cm_unwrapped));
raw_speed = [NaN; raw_dpos_cm ./ raw_dt];

spikeThresh_cm_s = 300;   % adjust after inspection
spikeIdx = find(raw_speed > spikeThresh_cm_s);

fprintf('\nFound %d raw speed spikes > %.1f cm/s\n', ...
    numel(spikeIdx), spikeThresh_cm_s);

% Show first 20 spikes with neighboring rows
nShow = min(20, numel(spikeIdx));

for ii = 1:nShow
    i = spikeIdx(ii);

    fprintf('\n--- Spike %d at row %d ---\n', ii, i);
    fprintf('speed = %.1f cm/s\n', raw_speed(i));
    fprintf('dt = %.6f s\n', raw_dt(i-1));
    fprintf('dpos = %.4f cm\n', raw_dpos_cm(i-1));
    fprintf('pos prev/current = %.3f / %.3f deg\n', pos_deg(i-1), pos_deg(i));
    fprintf('reward prev/current = %.0f / %.0f\n', reward(i-1), reward(i));
    fprintf('lick prev/current = %.0f / %.0f\n', lick(i-1), lick(i));
end

%% Reward logging artifact correction
% Remove reward-onset sample and immediately following sample,
% then interpolate replacement speed values.

rewardLogical = reward > 0;
rewardOnsetIdx = find(diff([0; rewardLogical]) == 1);

badIdx = [];

for k = 1:numel(rewardOnsetIdx)
    idx = [rewardOnsetIdx(k); rewardOnsetIdx(k)+1];
    idx(idx > numel(speed_cm_s)) = [];
    badIdx = [badIdx; idx(:)];
end

badIdx = unique(badIdx);

speedTmp = speed_cm_s;
speedTmp(badIdx) = NaN;

good = ~isnan(speedTmp);

if sum(good) >= 2
    speed_cm_s = interp1(t(good), speedTmp(good), t, 'linear', NaN);
end

figure
subplot(2,1,1)
plot(speedTmp,'k')
title('After removing reward-adjacent samples')

subplot(2,1,2)
plot(speed_cm_s,'r')
title('After interpolation')

fprintf('Removed %d reward-adjacent samples\n', numel(badIdx));


%% Optional low-speed exclusion
if useSpeedThreshold
    speed_cm_s(speed_cm_s < minSpeed_cm_s) = NaN;
end

%% Optional low-speed exclusion
if useSpeedThreshold
    speed_cm_s(speed_cm_s < minSpeed_cm_s) = NaN;
end

%% Detect laps/trials from 360 -> 0 wrap
lapStartIdx = [1; find(diff(pos_deg) < -180) + 1];

if numel(lapStartIdx) < 2
    error('No complete laps detected.');
end

nTrials = numel(lapStartIdx) - 1;

%% Position bins
edges_cm = 0:binSize_cm:track_cm;
centers_cm = edges_cm(1:end-1) + binSize_cm/2;
nBins = numel(edges_cm) - 1;

thetaEdges = edges_cm / track_cm * 2*pi;
thetaCenters = centers_cm / track_cm * 2*pi;

%% Build trial x position speed matrix
speedMat = nan(nTrials, nBins);

rewardTheta = [];
rewardRadius = [];

lickTheta = [];
lickRadius = [];

for tr = 1:nTrials
    idx1 = lapStartIdx(tr);
    idx2 = lapStartIdx(tr+1) - 1;

    if idx2 <= idx1
        continue
    end

    trialIdx = idx1:idx2;

    for b = 1:nBins
        idxBin = trialIdx(pos_cm_wrapped(trialIdx) >= edges_cm(b) & ...
                          pos_cm_wrapped(trialIdx) <  edges_cm(b+1));

        x = speed_cm_s(idxBin);
        x = x(~isnan(x));

        if ~isempty(x)
            speedMat(tr, b) = mean(x);
        end
    end

    % Reward delivery onset only
    rewardLogicalTrial = reward(trialIdx) > 0;
    rewardOnsetLocal = find(diff([0; rewardLogicalTrial]) == 1);

    if ~isempty(rewardOnsetLocal)
        rewardIdx = trialIdx(rewardOnsetLocal);

        rewardTheta = [rewardTheta; pos_cm_wrapped(rewardIdx) / track_cm * 2*pi];
        rewardRadius = [rewardRadius; innerHoleR + heatmapScale * tr * ones(numel(rewardIdx),1)];
    end

    % Licks
    lickIdx = trialIdx(lick(trialIdx) > 0);

    if ~isempty(lickIdx)
        lickTheta = [lickTheta; pos_cm_wrapped(lickIdx) / track_cm * 2*pi];
        lickRadius = [lickRadius; innerHoleR + heatmapScale * tr * ones(numel(lickIdx),1)];
    end
end

%% Color scaling
vals = speedMat(~isnan(speedMat));
if isempty(vals)
    error('No valid speed values after exclusions.');
end

if usePercentileColorMax
    cmax = prctile(vals, colorMaxPercentile);
else
    cmax = max(vals);
end

cmin = 0;
cmap = parula(256);

%% Plot circular trial heatmap
figure;
hold on
axis equal off

for tr = 1:nTrials
    r1 = innerHoleR + heatmapScale * (tr - 0.5);
    r2 = innerHoleR + heatmapScale * (tr + 0.5);

    for b = 1:nBins
        val = speedMat(tr, b);

        if isnan(val)
            continue
        end

        valClamped = min(max(val, cmin), cmax);

        idxColor = round(1 + (size(cmap,1)-1) * ...
                  (valClamped - cmin) / max(cmax-cmin, eps));

        idxColor = max(1, min(size(cmap,1), idxColor));
        thisColor = cmap(idxColor, :);

        th1 = thetaEdges(b);
        th2 = thetaEdges(b+1);

        xPatch = [r1*cos(th1), r2*cos(th1), r2*cos(th2), r1*cos(th2)];
        yPatch = [r1*sin(th1), r2*sin(th1), r2*sin(th2), r1*sin(th2)];

        patch(xPatch, yPatch, thisColor, 'EdgeColor', 'none');
    end
end

colormap(cmap);
caxis([cmin cmax]);
cb = colorbar;
ylabel(cb, 'Speed cm/s');

%% Add white center hole
thHole = linspace(0, 2*pi, 500);
[xHole, yHole] = pol2cart(thHole, innerHoleR * ones(size(thHole)));
fill(xHole, yHole, 'w', 'EdgeColor', 'k', 'LineWidth', 1.2);

%% Plot licks as white circles
if ~isempty(lickTheta)
    [xLick, yLick] = pol2cart(lickTheta, lickRadius);
    plot(xLick, yLick, 'wo', ...
        'MarkerSize', lickDotSize, ...
        'MarkerFaceColor', 'w', ...
        'LineWidth', 0.5);
end

%% Plot rewards as red dots
if ~isempty(rewardTheta)
    [xReward, yReward] = pol2cart(rewardTheta, rewardRadius);
    plot(xReward, yReward, 'r.', 'MarkerSize', rewardDotSize);
end

%% Outer circular average-speed line graph
outerMaxR = innerHoleR + heatmapScale * (nTrials + 0.5);

if showOuterMeanSpeed

    %% Center speed statistic: mean or median
    switch lower(outerSpeedStatistic)
        case 'mean'
            centerSpeed = nanmean(speedMat, 1);

        case 'median'
            centerSpeed = nanmedian(speedMat, 1);

        otherwise
            error('outerSpeedStatistic must be ''mean'' or ''median''.');
    end

    %% SEM is still based on trial-by-trial spread
    nPerBin  = sum(~isnan(speedMat), 1);
    semSpeed = nanstd(speedMat, 0, 1) ./ sqrt(nPerBin);
    semSpeed(nPerBin == 0) = NaN;

    %% Optional smoothing
    if smoothMeanSpeedBins > 1
        centerSpeed = movmean(centerSpeed, smoothMeanSpeedBins, 'omitnan');
        semSpeed    = movmean(semSpeed,    smoothMeanSpeedBins, 'omitnan');
    end

    %% Remove wrap-edge bins from outer speed curve only
    if excludeWrapBins > 0
        nBinsOuter = numel(centerSpeed);

        if excludeWrapBins * 2 < nBinsOuter
            centerSpeed(1:excludeWrapBins) = NaN;
            centerSpeed(end-excludeWrapBins+1:end) = NaN;

            semSpeed(1:excludeWrapBins) = NaN;
            semSpeed(end-excludeWrapBins+1:end) = NaN;
        end
    end

    validCenter = centerSpeed(~isnan(centerSpeed));

    if ~isempty(validCenter)

        maxTrialR = innerHoleR + heatmapScale * (nTrials + 0.5);
        outerBaseR = maxTrialR + outerGapR;

        centerScaled = (centerSpeed - outerSpeedMin_cm_s) ./ ...
                       (outerSpeedMax_cm_s - outerSpeedMin_cm_s);

        semScaled = semSpeed ./ ...
                    (outerSpeedMax_cm_s - outerSpeedMin_cm_s);

        centerScaled(centerScaled < 0) = 0;
        centerScaled(centerScaled > 1) = 1;

        rCenter = outerBaseR + outerAmpR * centerScaled;

        rSEMlow  = outerBaseR + outerAmpR * max(centerScaled - semScaled, 0);
        rSEMhigh = outerBaseR + outerAmpR * min(centerScaled + semScaled, 1);

        outerMaxR = outerBaseR + outerAmpR;

        %% Do NOT close curve across 360/0 boundary
        thetaClosed = thetaCenters;
        rCenterClosed = rCenter;
        rLowClosed  = rSEMlow;
        rHighClosed = rSEMhigh;

        %% Purple shading between minimum speed circle and center-speed line
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

        %% Summary circles from smoothed center-speed curve
        validSmoothedCenter = centerSpeed(~isnan(centerSpeed));

        minCenterSpeed = min(validSmoothedCenter);
        avgCenterSpeed = mean(validSmoothedCenter);
        maxCenterSpeed = max(validSmoothedCenter);

        summarySpeeds = [minCenterSpeed, avgCenterSpeed, maxCenterSpeed];

        thSummary = linspace(0, 2*pi, 500);

        if showMeanSpeedSummaryCircles
            for s = 1:numel(summarySpeeds)
                summaryScaled = (summarySpeeds(s) - outerSpeedMin_cm_s) ./ ...
                                (outerSpeedMax_cm_s - outerSpeedMin_cm_s);

                summaryScaled = max(0, min(1, summaryScaled));

                rSummary = outerBaseR + outerAmpR * summaryScaled;

                [xSummary, ySummary] = pol2cart(thSummary, ...
                    rSummary * ones(size(thSummary)));

                plot(xSummary, ySummary, ...
                    'Color', summaryCircleColor, ...
                    'LineStyle', summaryCircleLineStyle, ...
                    'LineWidth', summaryCircleLineWidth);
            end
        end

        %% Summary speed value list on left side
        labelPad = 70;
        labelX = -outerMaxR - labelPad;
        labelY = outerMaxR * 0.45;

        summaryLabelText = sprintf(['Min: %.1f cm/s\n' ...
                                    'Mean: %.1f cm/s\n' ...
                                    'Max: %.1f cm/s'], ...
                                    minCenterSpeed, avgCenterSpeed, maxCenterSpeed);

        text(labelX, labelY, summaryLabelText, ...
            'FontSize', axisFontSize, ...
            'Color', summaryCircleColor, ...
            'HorizontalAlignment', 'left', ...
            'VerticalAlignment', 'top');

        axisLimitLeft = outerMaxR + labelPad + 70;
        axisLimitRight = outerMaxR + 15;

        xlim([-axisLimitLeft axisLimitRight]);
        ylim([-outerMaxR - 5 outerMaxR + 5]);

        %% Center-speed line
        [xCenter, yCenter] = pol2cart(thetaClosed(goodCenter), ...
                                      rCenterClosed(goodCenter));

        plot(xCenter, yCenter, 'k-', 'LineWidth', outerLineWidth);
    end
end

%% Optional single reward guide line
if showRewardGuideLine
    guideLineStartR = innerHoleR;
    guideLineEndR   = innerHoleR + heatmapScale * (nTrials + 0.5);

    rewardThetaGuide = reward_deg / 360 * 2*pi;

    [xg, yg] = pol2cart( ...
        [rewardThetaGuide rewardThetaGuide], ...
        [guideLineStartR guideLineEndR]);

    plot(xg, yg, ...
        'Color', rewardGuideColor, ...
        'LineStyle', rewardGuideLineStyle, ...
        'LineWidth', rewardGuideLineWidth);
end

%% Re-draw white center hole on top and label lap count
fill(xHole, yHole, 'w', 'EdgeColor', 'k', 'LineWidth', 1.2);

text(0, 0, sprintf('%d\nlaps', nTrials), ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'FontSize', 16, ...
    'FontWeight', 'bold', ...
    'Color', 'k');

%% Title
title([mouseName, '  ', sessionDate, ...
       ' | Single-reward circular speed plot'], ...
       'Interpreter', 'none', 'FontSize', titleFontSize);

set(gca, 'FontSize', axisFontSize);