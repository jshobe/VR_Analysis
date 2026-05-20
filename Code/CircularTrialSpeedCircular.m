clear; clc;

%% USER SETTINGS
track_cm = 540;             % circular track length
binSize_cm = 5;             % spatial bin size
minSpeed_cm_s = 1;          % minimum speed threshold
useSpeedThreshold = true;   % false = ignore threshold

% Color scaling
usePercentileColorMax = true;
colorMaxPercentile = 99;

% Appearance
showCueRewardLines = true;
rewardDotSize = 18;
guideLineWidth = 1.5;

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
% New column order:
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

t                     = C{1};
distance_traveled     = C{2}; %#ok<NASGU>
pos_deg               = C{3};
visual_state          = C{4}; %#ok<NASGU>
next_RW_location_idx  = C{5}; %#ok<NASGU>
reward                = C{6};
brake                 = C{7};
lick                  = C{8}; %#ok<NASGU>
blackout_cue_identity = C{9}; %#ok<NASGU>

valid = ~isnan(t) & ~isnan(pos_deg) & ~isnan(reward) & ~isnan(brake);
t = t(valid);
pos_deg = pos_deg(valid);
reward = reward(valid);
brake = brake(valid);

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
excludeMask = (brake == 1);

if useSpeedThreshold
    excludeMask = excludeMask | (speed_cm_s < minSpeed_cm_s);
end

speed_cm_s(excludeMask) = NaN;

%% Detect laps from 360 -> 0 wrap
lapStartIdx = [1; find(diff(pos_deg) < -180) + 1];

if numel(lapStartIdx) < 2
    error('No complete laps detected.');
end

nTrials = numel(lapStartIdx) - 1;

%% Position bins
edges_cm = 0:binSize_cm:track_cm;
nBins = numel(edges_cm) - 1;
thetaEdges = edges_cm / track_cm * 2*pi;

%% Build trial x position matrix
% Rows = trials, Columns = position bins
speedMat = nan(nTrials, nBins);

% Store actual reward deliveries
rewardTheta = [];
rewardRadius = [];

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

    % Actual reward deliveries in this trial, excluding brake samples
    rewardIdx = trialIdx(reward(trialIdx) > 0 & brake(trialIdx) == 0);
    if ~isempty(rewardIdx)
        rewardTheta = [rewardTheta; pos_cm_wrapped(rewardIdx) / track_cm * 2*pi];
        rewardRadius = [rewardRadius; tr * ones(numel(rewardIdx),1)];
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

%% Plot circular heatmap using patches
figure;
hold on
axis equal off

for tr = 1:nTrials
    r1 = tr - 0.5;
    r2 = tr + 0.5;

    for b = 1:nBins
        val = speedMat(tr, b);
        if isnan(val)
            continue
        end

        valClamped = min(max(val, cmin), cmax);
        idxColor = round(1 + (size(cmap,1)-1) * (valClamped - cmin) / max(cmax-cmin, eps));
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
colorbar;

%% Actual reward deliveries as red dots
if ~isempty(rewardTheta)
    [xReward, yReward] = pol2cart(rewardTheta, rewardRadius);
    plot(xReward, yReward, 'r.', 'MarkerSize', rewardDotSize);
end

%% Potential cue/reward radial guide lines
if showCueRewardLines
    maxR = nTrials + 0.5;

    rewardThetaGuide = reward_deg / 360 * 2*pi;
    for i = 1:length(rewardThetaGuide)
        [xg, yg] = pol2cart([rewardThetaGuide(i) rewardThetaGuide(i)], [0.5 maxR]);
        plot(xg, yg, 'r-', 'LineWidth', guideLineWidth);
    end

    cueThetaGuide = cue_deg / 360 * 2*pi;
    for i = 1:length(cueThetaGuide)
        [xg, yg] = pol2cart([cueThetaGuide(i) cueThetaGuide(i)], [0.5 maxR]);
        plot(xg, yg, 'k-', 'LineWidth', guideLineWidth);
    end
end

%% Optional trial rings
for tr = 1:nTrials
    th = linspace(0, 2*pi, 300);
    [xr, yr] = pol2cart(th, tr + 0.5);
    plot(xr, yr, 'k:', 'LineWidth', 0.25);
end

title([mouseName, '  ', sessionDate, ' | Circular speed by trial'], ...
    'Interpreter', 'none', 'FontSize', titleFontSize);

set(gca, 'FontSize', axisFontSize);