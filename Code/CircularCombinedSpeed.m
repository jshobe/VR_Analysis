clear; clc;

%% USER SETTINGS
track_cm = 540;
binSize_cm = 5;
minSpeed_cm_s = 1;
useSpeedThreshold = false;
smoothMeanSpeedBins = 3;   % 1 = no smoothing, 3/5/7 = more smoothing

% Color scaling
usePercentileColorMax = true;
colorMaxPercentile = 99;

% Appearance
showRewardGuideLines = true;
showCueGuideLines    = true;

rewardDotSize = 10;
lickDotSize   = 5;
guideLineWidth = 1.5;

showRewardGuideLines = false;
showCueGuideLines    = false;

rewardGuideColor = [1 0 0];
cueGuideColor    = [0 0 0];

rewardGuideLineStyle = '-';
cueGuideLineStyle    = '-';

rewardGuideLineWidth = 1.5;
cueGuideLineWidth    = 1.5;

showMeanSpeedSummaryCircles = true;

summaryCircleColor = [0.25 0.25 0.25];
summaryCircleLineStyle = ':';
summaryCircleLineWidth = 1.2;

cueID_circle  = 60;   % change to actual cue identity
cueID_diamond = 90;    % change to actual cue identity

cueCircleDotSize  = 5;
cueDiamondDotSize = 5;

% Heatmap radial layout
heatmapScale = 0.78;
innerHoleR = 30;              % white center hole radius

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

reward_deg = [0 90 180 270];
cue_deg    = [30 120 210 300];

%% Remember last folder
settingsFile = fullfile(tempdir, 'lastVRFolder.mat');

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

mouseTok = regexp(baseName, '(JB\d+)', 'tokens', 'once');
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
% Expected column order:
% 1 time_s
% 2 distance_traveled
% 3 position(deg)
% 4 visual_state
% 5 next_RW_location_idx
% 6 reward_delivered
% 7 brake_applied
% 8 lick_detection
% 9 blackout_cue_identity

fid = fopen(fname, 'r');
if fid == -1
    error('Could not open file.');
end

fgetl(fid); % skip header
C = textscan(fid, '%f%f%f%f%f%f%f%f%f');
fclose(fid);

t        = C{1};
pos_deg  = C{3};
reward   = C{6};
brake    = C{7};
lick     = C{8};
blackout_cue_identity = C{9};

% Treat NaN cue values as "no cue"


valid = ~isnan(t) & ~isnan(pos_deg) & ~isnan(reward) & ...
        ~isnan(brake) & ~isnan(lick);

t       = t(valid);
pos_deg = pos_deg(valid);
reward  = reward(valid);
brake   = brake(valid);
lick    = lick(valid);
blackout_cue_identity = blackout_cue_identity(valid);

if numel(t) < 2
    error('Not enough valid samples.');
end

%% Position variables
pos_cm_wrapped   = mod((pos_deg / 360) * track_cm, track_cm);
pos_cm_unwrapped = rad2deg(unwrap(deg2rad(pos_deg))) / 360 * track_cm;

%% Speed from position
dt = diff(t);
speed_cm_s = [NaN; abs(diff(pos_cm_unwrapped) ./ dt)];
speed_cm_s(~isfinite(speed_cm_s)) = NaN;

%% Exclude brake periods and low-speed samples
excludeMask = brake == 1;

if useSpeedThreshold
    excludeMask = excludeMask | speed_cm_s < minSpeed_cm_s;
end

speed_cm_s(excludeMask) = NaN;

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

cueCircleTheta = [];
cueCircleRadius = [];

cueDiamondTheta = [];
cueDiamondRadius = [];

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

    % Actual reward deliveries, excluding brake samples
    rewardIdx = trialIdx(reward(trialIdx) > 0 & brake(trialIdx) == 0);
    if ~isempty(rewardIdx)
        rewardTheta = [rewardTheta; pos_cm_wrapped(rewardIdx) / track_cm * 2*pi];
        rewardRadius = [rewardRadius; innerHoleR + heatmapScale * tr * ones(numel(rewardIdx),1)];
    end

    % Licks, including brake samples
    lickIdx = trialIdx(lick(trialIdx) > 0);

    if ~isempty(lickIdx)
    lickTheta = [lickTheta; pos_cm_wrapped(lickIdx) / track_cm * 2*pi];
    lickRadius = [lickRadius; innerHoleR + heatmapScale * tr * ones(numel(lickIdx),1)];
    end

    % Cue presentations, including brake samples
    % Any non-NaN blackout_cue_identity value counts as cue:
    % positive, negative, or zero.
    cueCircleIdx  = trialIdx(blackout_cue_identity(trialIdx) == cueID_circle);
    cueDiamondIdx = trialIdx(blackout_cue_identity(trialIdx) == cueID_diamond);

    if ~isempty(cueCircleIdx)
        cueCircleTheta = [cueCircleTheta; pos_cm_wrapped(cueCircleIdx) / track_cm * 2*pi];
        cueCircleRadius = [cueCircleRadius; innerHoleR + heatmapScale * tr * ones(numel(cueCircleIdx),1)];
    end

    if ~isempty(cueDiamondIdx)
        cueDiamondTheta = [cueDiamondTheta; pos_cm_wrapped(cueDiamondIdx) / track_cm * 2*pi];
        cueDiamondRadius = [cueDiamondRadius; innerHoleR + heatmapScale * tr * ones(numel(cueDiamondIdx),1)];
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

%% Plot licks as small black dots
if ~isempty(lickTheta)
    [xLick, yLick] = pol2cart(lickTheta, lickRadius);
    plot(xLick, yLick, 'w.', 'MarkerSize', lickDotSize);
end

%% Plot actual rewards as red dots
if ~isempty(rewardTheta)
    [xReward, yReward] = pol2cart(rewardTheta, rewardRadius);
    plot(xReward, yReward, 'r.', 'MarkerSize', rewardDotSize);
end

%% Plot cue presentations by identity
if ~isempty(cueCircleTheta)
    [xCueCircle, yCueCircle] = pol2cart(cueCircleTheta, cueCircleRadius);
    plot(xCueCircle, yCueCircle, 'ko', ...
        'MarkerSize', cueCircleDotSize, ...
        'MarkerFaceColor', 'k', ...
        'LineWidth', 0.5);
end

if ~isempty(cueDiamondTheta)
    [xCueDiamond, yCueDiamond] = pol2cart(cueDiamondTheta, cueDiamondRadius);
    plot(xCueDiamond, yCueDiamond, 'kd', ...
        'MarkerSize', cueDiamondDotSize, ...
        'MarkerFaceColor', 'c', ...
        'LineWidth', 0.5);
end


%% Outer circular average-speed line graph
outerMaxR = innerHoleR + heatmapScale * (nTrials + 0.5);

if showOuterMeanSpeed
    meanSpeed = nanmean(speedMat, 1);

    nPerBin  = sum(~isnan(speedMat), 1);
    semSpeed = nanstd(speedMat, 0, 1) ./ sqrt(nPerBin);
    semSpeed(nPerBin == 0) = NaN;

    if smoothMeanSpeedBins > 1
        meanSpeed = movmean(meanSpeed, smoothMeanSpeedBins, 'omitnan');
        semSpeed  = movmean(semSpeed,  smoothMeanSpeedBins, 'omitnan');
    end

    validMean = meanSpeed(~isnan(meanSpeed));

    if ~isempty(validMean)

        maxTrialR = innerHoleR + heatmapScale * (nTrials + 0.5);
        outerBaseR = maxTrialR + outerGapR;

        meanScaled = (meanSpeed - outerSpeedMin_cm_s) ./ ...
                     (outerSpeedMax_cm_s - outerSpeedMin_cm_s);

        semScaled = semSpeed ./ ...
                    (outerSpeedMax_cm_s - outerSpeedMin_cm_s);

        meanScaled(meanScaled < 0) = 0;
        meanScaled(meanScaled > 1) = 1;

        rMean = outerBaseR + outerAmpR * meanScaled;

        rSEMlow  = outerBaseR + outerAmpR * max(meanScaled - semScaled, 0);
        rSEMhigh = outerBaseR + outerAmpR * min(meanScaled + semScaled, 1);

        outerMaxR = outerBaseR + outerAmpR;

        thetaClosed = [thetaCenters, thetaCenters(1)];
        rMeanClosed = [rMean, rMean(1)];
        rLowClosed  = [rSEMlow, rSEMlow(1)];
        rHighClosed = [rSEMhigh, rSEMhigh(1)];

        %% Purple shading between minimum speed circle and mean-speed line
        goodMean = ~isnan(rMeanClosed);

        [xBaseFill, yBaseFill] = pol2cart(thetaClosed(goodMean), ...
            outerBaseR * ones(1, sum(goodMean)));

        [xMeanFill, yMeanFill] = pol2cart(thetaClosed(goodMean), ...
            rMeanClosed(goodMean));

        fill([xBaseFill, fliplr(xMeanFill)], ...
             [yBaseFill, fliplr(yMeanFill)], ...
             [0.75 0.60 0.90], ...
             'FaceAlpha', 0.25, ...
             'EdgeColor', 'none');

        %% Grey SEM band around mean-speed line
        goodSEM = ~isnan(rLowClosed) & ~isnan(rHighClosed);

        [xLow, yLow] = pol2cart(thetaClosed(goodSEM), rLowClosed(goodSEM));
        [xHigh, yHigh] = pol2cart(thetaClosed(goodSEM), rHighClosed(goodSEM));

        fill([xLow, fliplr(xHigh)], ...
             [yLow, fliplr(yHigh)], ...
             [0.40 0.40 0.40], ...
             'FaceAlpha', 0.45, ...
             'EdgeColor', 'none');

        %% Solid 0-speed reference circle
        th = linspace(0, 2*pi, 500);

        [xZeroSpeed, yZeroSpeed] = pol2cart( ...
        th, outerBaseR * ones(size(th)));

        plot(xZeroSpeed, yZeroSpeed, ...
        'k-', ...
        'LineWidth', 1.5);


        %% Dashed summary circles from smoothed mean speed
        validSmoothedMean = meanSpeed(~isnan(meanSpeed));

        minMeanSpeed = min(validSmoothedMean);
        avgMeanSpeed = mean(validSmoothedMean);
        maxMeanSpeed = max(validSmoothedMean);

        summarySpeeds = [minMeanSpeed, avgMeanSpeed, maxMeanSpeed];

        thSummary = linspace(0, 2*pi, 500);

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

%% Summary speed value list on left side, outside plot
labelPad = 70;
labelX = -outerMaxR - labelPad;
labelY = outerMaxR * 0.45;

summaryLabelText = sprintf(['Min: %.1f cm/s\n' ...
                            'Mean: %.1f cm/s\n' ...
                            'Max: %.1f cm/s'], ...
                            minMeanSpeed, avgMeanSpeed, maxMeanSpeed);

text(labelX, labelY, summaryLabelText, ...
    'FontSize', axisFontSize, ...
    'Color', summaryCircleColor, ...
    'HorizontalAlignment', 'left', ...
    'VerticalAlignment', 'top');

% Expand plot limits so the text is visible and does not overlap the circle
axisLimitLeft = outerMaxR + labelPad + 70;
axisLimitRight = outerMaxR + 15;

xlim([-axisLimitLeft axisLimitRight]);
ylim([-outerMaxR - 5 outerMaxR + 5]);

        %% Mean-speed line
        [xMean, yMean] = pol2cart(thetaClosed(goodMean), rMeanClosed(goodMean));
        plot(xMean, yMean, 'k-', 'LineWidth', outerLineWidth);

 

    end
end

%% Potential cue/reward radial guide lines
if showRewardGuideLines || showCueGuideLines
    guideLineStartR = innerHoleR;
    guideLineEndR   = innerHoleR + heatmapScale * (nTrials + 0.5);

    if showRewardGuideLines
        rewardThetaGuide = reward_deg / 360 * 2*pi;

        for i = 1:length(rewardThetaGuide)
            [xg, yg] = pol2cart( ...
                [rewardThetaGuide(i) rewardThetaGuide(i)], ...
                [guideLineStartR guideLineEndR]);

            plot(xg, yg, ...
                'Color', rewardGuideColor, ...
                'LineStyle', rewardGuideLineStyle, ...
                'LineWidth', rewardGuideLineWidth);
        end
    end

    if showCueGuideLines
        cueThetaGuide = cue_deg / 360 * 2*pi;

        for i = 1:length(cueThetaGuide)
            [xg, yg] = pol2cart( ...
                [cueThetaGuide(i) cueThetaGuide(i)], ...
                [guideLineStartR guideLineEndR]);

            plot(xg, yg, ...
                'Color', cueGuideColor, ...
                'LineStyle', cueGuideLineStyle, ...
                'LineWidth', cueGuideLineWidth);
        end
    end
end

%% Re-draw white center hole on top so it stays clean
fill(xHole, yHole, 'w', 'EdgeColor', 'k', 'LineWidth', 1.2);

%% Title
title([mouseName, '  ', sessionDate, ...
       ' | Trial speed heatmap with outer mean speed line'], ...
       'Interpreter', 'none', 'FontSize', titleFontSize);

set(gca, 'FontSize', axisFontSize);