clear; clc;

%% USER SETTINGS
track_cm = 540;             % circular track length
binSize_cm = 5;             % spatial bin size
minSpeed_cm_s = 1;          % minimum speed threshold
useSpeedThreshold = true;   % false = ignore threshold

% Heatmap color scaling
usePercentileColorMax = true;   % true = cap color axis at percentile
colorMaxPercentile = 99;        % e.g. 95, 98, 99

% Plot appearance
showCueRewardLines = true;
rewardDotSize = 20;             % size of reward delivery dots

reward_deg = [0 90 180 270];
cue_deg    = [30 120 210 300];

axisFontSize  = 14;
labelFontSize = 16;
titleFontSize = 16;

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
fid = fopen(fname, 'r');
if fid == -1
    error('Could not open file.');
end

fgetl(fid); % skip header
C = textscan(fid, '%f%f%f%f%f%f%f%f');
fclose(fid);

t       = C{1};
pos_deg = C{3};
reward  = C{6};
brake   = C{7};

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
edges = 0:binSize_cm:track_cm;
binCenters = edges(1:end-1) + binSize_cm/2;
nBins = numel(binCenters);

%% Build trial x position matrix
% Rows = trials, Columns = position bins
speedMat = nan(nTrials, nBins);

% Store actual reward deliveries by trial
rewardX = [];
rewardY = [];

for tr = 1:nTrials
    idx1 = lapStartIdx(tr);
    idx2 = lapStartIdx(tr+1) - 1;

    if idx2 <= idx1
        continue
    end

    trialIdx = idx1:idx2;

    % Bin speed by position for this trial
    for b = 1:nBins
        idxBin = trialIdx(pos_cm_wrapped(trialIdx) >= edges(b) & pos_cm_wrapped(trialIdx) < edges(b+1));
        x = speed_cm_s(idxBin);
        x = x(~isnan(x));

        if ~isempty(x)
            speedMat(tr, b) = mean(x);
        end
    end

    % Actual reward deliveries in this trial, excluding brake samples
    rewardIdx = trialIdx(reward(trialIdx) > 0 & brake(trialIdx) == 0);
    if ~isempty(rewardIdx)
        rewardX = [rewardX; pos_cm_wrapped(rewardIdx)];
        rewardY = [rewardY; tr * ones(numel(rewardIdx),1)];
    end
end

%% Plot heatmap
figure;
imagesc(binCenters, 1:nTrials, speedMat);
set(gca, 'YDir', 'reverse');   % puts trial 1 at the top

colormap(parula);
colorbar;

% Limit color scale so plot is not overly blue
if usePercentileColorMax
    vals = speedMat(~isnan(speedMat));
    if ~isempty(vals)
        caxis([0 prctile(vals, colorMaxPercentile)]);
    end
end

hold on

% Actual reward delivery dots
if ~isempty(rewardX)
    plot(rewardX, rewardY, 'r.', 'MarkerSize', rewardDotSize);
end

% Potential cue/reward location guide lines
if showCueRewardLines
    reward_cm = reward_deg / 360 * track_cm;
    cue_cm    = cue_deg / 360 * track_cm;

    for i = 1:length(reward_cm)
        xline(reward_cm(i), 'r-', 'LineWidth', 1.5);
    end

    for i = 1:length(cue_cm)
        xline(cue_cm(i), 'k-', 'LineWidth', 1.5);
    end
end

xlabel('Position on track (cm)', 'FontSize', labelFontSize);
ylabel('Trial number', 'FontSize', labelFontSize);
title([mouseName, '  ', sessionDate, ' | Speed by trial and position'], ...
    'Interpreter', 'none', 'FontSize', titleFontSize);

set(gca, 'FontSize', axisFontSize);