clear; clc;

%% USER SETTINGS
track_cm = 540;                 % track length
rewardMarkerSize = 18;          % size of reward dots
blackoutMarkerSize = 18;        % size of blackout-start dots
lineWidth = 1.5;                % guide-line width

% Lick rectangles
lickRectWidth_cm = 0.3;         % rectangle width in cm
lickRectHeight   = 0.6;        % rectangle height in lap units
% Shading
shadeColor = [0.85 0.85 0.85];  % light gray
shadeFaceAlpha = 0.35;          % transparency

% Potential task locations
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

%% Select files
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

%% Process each file
for f = 1:length(file)
    thisFile = file{f};
    fname = fullfile(path, thisFile);

    % Parse mouse/date from filename
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

    %% Read file
    fid = fopen(fname, 'r');
    if fid == -1
        warning('Could not open file: %s', thisFile);
        continue
    end

    fgetl(fid); % skip header
    C = textscan(fid, '%f%f%f%f%f%f%f%f');
    fclose(fid);

    t           = C{1};
    posDeg      = C{3};
    visualState = C{4};
    reward      = C{6};
    brake       = C{7};
    lick        = C{8};

    valid = ~isnan(t) & ~isnan(posDeg) & ~isnan(visualState) & ...
            ~isnan(reward) & ~isnan(brake) & ~isnan(lick);

    t           = t(valid);
    posDeg      = posDeg(valid);
    visualState = visualState(valid);
    reward      = reward(valid);
    brake       = brake(valid);
    lick        = lick(valid);

    if numel(posDeg) < 2
        warning('Not enough valid samples in file: %s', thisFile);
        continue
    end

    % Wrapped position: 0 to 540 cm each lap
    posCmWrapped = mod((posDeg / 360) * track_cm, track_cm);

    % Detect lap starts from wraparound in degrees
    lapStartIdx = [1; find(diff(posDeg) < -180) + 1];

    if numel(lapStartIdx) < 2
        warning('No complete laps detected in file: %s', thisFile);
        continue
    end

    nLaps = numel(lapStartIdx) - 1;

    %% Convert task positions to cm
    reward_cm = reward_deg / 360 * track_cm;
    cue_cm    = cue_deg / 360 * track_cm;

    %% Make raster
    figure;
    hold on

    % Horizontal shading for odd laps
    for lap = 1:nLaps
        if mod(lap,2) == 1
            patch([0 track_cm track_cm 0], ...
                  [lap-0.5 lap-0.5 lap+0.5 lap+0.5], ...
                  shadeColor, ...
                  'EdgeColor', 'none', ...
                  'FaceAlpha', shadeFaceAlpha);
        end
    end

    for lap = 1:nLaps
        idx1 = lapStartIdx(lap);
        idx2 = lapStartIdx(lap+1) - 1;

        if idx2 <= idx1
            continue
        end

        lapIdx = idx1:idx2;

        % Exclude brake samples for lick/reward plotting
        lapIdxNoBrake = lapIdx(brake(lapIdx) == 0);

        %% Lick events within this lap
        lickIdx = lapIdxNoBrake(lick(lapIdxNoBrake) > 0);
        if ~isempty(lickIdx)
            xLick = posCmWrapped(lickIdx);
            yLick = lap * ones(size(xLick));

            for k = 1:length(xLick)
                rectangle('Position', ...
                    [xLick(k) - lickRectWidth_cm/2, ...
                     yLick(k) - lickRectHeight/2, ...
                     lickRectWidth_cm, ...
                     lickRectHeight], ...
                     'FaceColor', 'k', ...
                     'EdgeColor', 'k');
            end
        end

        %% Reward delivery events within this lap
        rewardIdx = lapIdxNoBrake(reward(lapIdxNoBrake) > 0);
        if ~isempty(rewardIdx)
            xReward = posCmWrapped(rewardIdx);
            yReward = lap * ones(size(xReward));
            plot(xReward, yReward, 'r.', 'MarkerSize', rewardMarkerSize);
        end

        %% Actual blackout starts within this lap
        % blackout begins when visual_state enters 0
        vsLap = visualState(lapIdx);
        blackoutStartLocal = find(diff([NaN; vsLap == 0]) == 1);

        if ~isempty(blackoutStartLocal)
            blackoutStartIdx = lapIdx(blackoutStartLocal);
            xBlackout = posCmWrapped(blackoutStartIdx);
            yBlackout = lap * ones(size(xBlackout));

            plot(xBlackout, yBlackout, 'k.', 'MarkerSize', blackoutMarkerSize);
        end
    end

    %% Potential location guide lines
    for i = 1:length(reward_cm)
        xline(reward_cm(i), 'r-', 'LineWidth', lineWidth, 'HandleVisibility', 'off');
    end

    for i = 1:length(cue_cm)
        xline(cue_cm(i), 'k-', 'LineWidth', lineWidth, 'HandleVisibility', 'off');
    end

    xlabel('Position within lap (cm)')
    ylabel('Lap')
    title([mouseName, '  ', sessionDate, ' | Lick raster by lap'], ...
        'Interpreter', 'none')
    xlim([0 track_cm])
    ylim([0 nLaps + 1])
    set(gca, 'YDir', 'reverse')
    grid on
end