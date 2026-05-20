clear; clc;

%% USER SETTINGS
track_cm = 540;             % circular track length
binSize_cm = 3;             % spatial bin size in cm
minSpeed_cm_s = 1;          % minimum speed threshold in cm/s
useSpeedThreshold = true;   % set false to ignore threshold

smoothSpan_bins = 3;        % 1 = no smoothing, 3/5/etc = moving average across bins

% Plot appearance
mainLineWidth   = 2.5;      % thickness of plotted mean line
semFaceAlpha    = 0.20;     % transparency of SEM shading
guideLineWidth  = 2.4;      % thickness of reward/cue guide lines

% Font sizes
axisFontSize   = 14;        % axis tick labels (numbers)
labelFontSize  = 16;        % x/y axis labels
titleFontSize  = 16;        % figure title
legendFontSize = 15;        % legend text

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

%% Select multiple files
[file, path] = uigetfile(fullfile(startFolder, '*.txt'), ...
    'Select VR session files', 'MultiSelect', 'on');

if isequal(file, 0)
    error('No file selected.');
end

if ischar(file)
    file = {file};
end

lastFolder = path;
save(settingsFile, 'lastFolder');

%% Spatial bins
edges = 0:binSize_cm:track_cm;
centers = edges(1:end-1) + binSize_cm/2;

%% Prepare figure
figure;
hold on

plotHandles = [];
legendEntries = {};

%% Process each file separately
for f = 1:length(file)
    thisFile = file{f};
    fname = fullfile(path, thisFile);

    % Parse mouse name and date from filename
    [~, baseName, ~] = fileparts(thisFile);

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

    labelText = [mouseName, '  ', sessionDate];

    %% Read file
    fid = fopen(fname, 'r');
    if fid == -1
        warning('Could not open file: %s', thisFile);
        continue
    end

    fgetl(fid); % skip header
    C = textscan(fid, '%f%f%f%f%f%f%f%f');
    fclose(fid);

    t = C{1};
    pos_deg = C{3};
    brake = C{7};

    valid = ~isnan(t) & ~isnan(pos_deg) & ~isnan(brake);
    t = t(valid);
    pos_deg = pos_deg(valid);
    brake = brake(valid);

    if numel(t) < 2
        warning('Not enough valid samples in file: %s', thisFile);
        continue
    end

    %% Position
    pos_cm_wrapped = mod((pos_deg / 360) * track_cm, track_cm);
    pos_cm_unwrapped = rad2deg(unwrap(deg2rad(pos_deg))) / 360 * track_cm;

    %% Speed from position
    dt = diff(t);
    speed_cm_s = [NaN; abs(diff(pos_cm_unwrapped) ./ dt)];
    speed_cm_s(~isfinite(speed_cm_s)) = NaN;

    %% Exclude brake periods regardless of speed
    excludeMask = (brake == 1);

    if useSpeedThreshold
        excludeMask = excludeMask | (speed_cm_s < minSpeed_cm_s);
    end

    speed_cm_s(excludeMask) = NaN;

    %% Lap stats
    totalDistance_cm = pos_cm_unwrapped(end) - pos_cm_unwrapped(1);
    nLaps_est = totalDistance_cm / track_cm;
    sessionDuration_min = (t(end) - t(1)) / 60;
    lapsPerMin = nLaps_est / sessionDuration_min;

    %% Detect lap starts
    lapStartIdx = [1; find(diff(pos_deg) < -180) + 1];

    if numel(lapStartIdx) < 2
        warning('No complete laps detected in file: %s', thisFile);
        continue
    end

    nCompleteLaps = numel(lapStartIdx) - 1;

    %% Build lap x bin matrix
    lapBinSpeed = nan(nCompleteLaps, length(centers));

    for lap = 1:nCompleteLaps
        idx1 = lapStartIdx(lap);
        idx2 = lapStartIdx(lap+1) - 1;

        if idx2 <= idx1
            continue
        end

        lapIdx = idx1:idx2;

        for b = 1:length(centers)
            idxBin = lapIdx(pos_cm_wrapped(lapIdx) >= edges(b) & pos_cm_wrapped(lapIdx) < edges(b+1));
            x = speed_cm_s(idxBin);
            x = x(~isnan(x));
            if ~isempty(x)
                lapBinSpeed(lap, b) = mean(x);
            end
        end
    end

    %% Mean and SEM across laps
    meanCurve = nanmean(lapBinSpeed, 1);
    nPerBin = sum(~isnan(lapBinSpeed), 1);
    semCurve = nanstd(lapBinSpeed, 0, 1) ./ sqrt(nPerBin);

    % Avoid divide-by-zero issues
    semCurve(nPerBin == 0) = NaN;

    %% Optional smoothing across bins
    if smoothSpan_bins > 1
        meanCurve = movmean(meanCurve, smoothSpan_bins, 'omitnan');
        %semCurve  = movmean(semCurve,  smoothSpan_bins, 'omitnan');
    end

    %% Plot SEM band
    good = ~isnan(meanCurve) & ~isnan(semCurve);
    if any(good)
        xPatch = [centers(good), fliplr(centers(good))];
        yPatch = [meanCurve(good) - semCurve(good), fliplr(meanCurve(good) + semCurve(good))];

        hp = patch(xPatch, yPatch, 'k', ...
            'EdgeColor', 'none', ...
            'FaceAlpha', semFaceAlpha, ...
            'HandleVisibility', 'off');
    else
        hp = [];
    end

    %% Plot mean line
    h = plot(centers, meanCurve, '-', 'LineWidth', mainLineWidth);

    if ~isempty(hp)
        hp.FaceColor = h.Color;
    end

    plotHandles(end+1) = h; %#ok<SAGROW>
    legendEntries{end+1} = sprintf('%s | laps=%d | laps/min=%.2f', ...
        labelText, nCompleteLaps, lapsPerMin); %#ok<SAGROW>
end

%% Add reward and cue lines
reward_cm = reward_deg / 360 * track_cm;
cue_cm    = cue_deg / 360 * track_cm;

for i = 1:length(reward_cm)
    xline(reward_cm(i), 'r-', 'LineWidth', guideLineWidth, 'HandleVisibility', 'off');
end

for i = 1:length(cue_cm)
    xline(cue_cm(i), 'k-', 'LineWidth', guideLineWidth, 'HandleVisibility', 'off');
end

%% Final formatting
xlabel('Position on track (cm)', 'FontSize', labelFontSize)
ylabel('Speed from position(deg) (cm/s)', 'FontSize', labelFontSize)
xlim([0 track_cm])
grid on
set(gca, 'FontSize', axisFontSize)

if useSpeedThreshold
    title(['Speed by track position, mean \pm SEM across laps, excluding brakes, min speed = ', ...
        num2str(minSpeed_cm_s), ' cm/s, bin = ', num2str(binSize_cm), ...
        ' cm, smooth span = ', num2str(smoothSpan_bins), ' bins'], ...
        'Interpreter', 'tex', 'FontSize', titleFontSize)
else
    title(['Speed by track position, mean \pm SEM across laps, excluding brakes, bin = ', ...
        num2str(binSize_cm), ' cm, smooth span = ', num2str(smoothSpan_bins), ' bins'], ...
        'Interpreter', 'tex', 'FontSize', titleFontSize)
end

if ~isempty(plotHandles)
    lgd = legend(plotHandles, legendEntries, ...
        'Interpreter', 'none', 'Location', 'best');
    lgd.FontSize = legendFontSize;
end