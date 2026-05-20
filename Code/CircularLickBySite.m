clear; clc;

%% ===================== USER SETTINGS =====================
track_cm = 540;

% Track geometry
reward_deg_all = [0 90 180 270]; %#ok<NASGU>
cue_deg_all    = [30 120 210 300];

% Active reward pair for this mouse/session
activeReward_deg = [0 180];   % JB5 example

% Cue identity values in blackout_cue_identity column
cueIdentityValues = [0 30];
cueIdentityNames  = {'basketball','star'};

% Map cue identity to active reward location
cueToRewardMap_deg = [0 180];

% Lick raster window around site
rasterWindow_deg = 90;   % show licks from -90 deg before site
rasterPost_deg   = 20;   % show licks to +20 deg after site

% Tolerances / options
rewardTolerance_deg = 35;
cueTolerance_deg    = 35;
skipCueRewardMismatches = true;

% Plot settings
axisFontSize   = 12;
labelFontSize  = 14;
titleFontSize  = 15;

%% ===================== REMEMBER LAST FOLDER =====================
settingsFile = fullfile(tempdir, 'lastVRFolder_lickRasterAnalysis.mat');

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

%% ===================== SELECT FILES =====================
[file, path] = uigetfile(fullfile(startFolder, '*.txt'), ...
    'Select newest-format VR session files', 'MultiSelect', 'on');

if isequal(file,0)
    error('No file selected.');
end

if ischar(file)
    file = {file};
end

lastFolder = path;
save(settingsFile, 'lastFolder');

%% ===================== SESSION PORTION BY LAPS =====================
lapChoice = menu( ...
    'Analyze which part of each session by laps?', ...
    'Entire session', ...
    'First % of laps', ...
    'Last % of laps', ...
    'Custom % range of laps');

if isequal(lapChoice, 0)
    error('No lap range selected.');
end

lapMode = 'entire';
lapPct = NaN;
lapStartPct = NaN;
lapEndPct = NaN;
lapLabel = 'Entire session';

switch lapChoice
    case 1
        lapMode = 'entire';
        lapLabel = 'Entire session';

    case 2
        answer = inputdlg({'Enter percent of laps to analyze (0-100):'}, ...
                          'First % of laps', [1 50], {'20'});
        if isempty(answer)
            error('No lap percentage entered.');
        end
        lapPct = str2double(answer{1});
        if ~isfinite(lapPct) || lapPct <= 0 || lapPct > 100
            error('Percent must be > 0 and <= 100.');
        end
        lapMode = 'first';
        lapLabel = sprintf('First %.1f%% of laps', lapPct);

    case 3
        answer = inputdlg({'Enter percent of laps to analyze (0-100):'}, ...
                          'Last % of laps', [1 50], {'20'});
        if isempty(answer)
            error('No lap percentage entered.');
        end
        lapPct = str2double(answer{1});
        if ~isfinite(lapPct) || lapPct <= 0 || lapPct > 100
            error('Percent must be > 0 and <= 100.');
        end
        lapMode = 'last';
        lapLabel = sprintf('Last %.1f%% of laps', lapPct);

    case 4
        answer = inputdlg({'Enter start percent of laps (0-100):', ...
                           'Enter end percent of laps (0-100):'}, ...
                          'Custom % range of laps', [1 50], {'80','100'});
        if isempty(answer)
            error('No lap range entered.');
        end
        lapStartPct = str2double(answer{1});
        lapEndPct   = str2double(answer{2});

        if ~isfinite(lapStartPct) || ~isfinite(lapEndPct) || ...
           lapStartPct < 0 || lapEndPct > 100 || ...
           lapStartPct >= lapEndPct
            error('Custom range must satisfy 0 <= start < end <= 100.');
        end

        lapMode = 'custom';
        lapLabel = sprintf('%.1f%%-%.1f%% of laps', lapStartPct, lapEndPct);
end

%% ===================== CONTAINERS =====================
eventRows = {};

varNames = { ...
    'sessionName', ...
    'siteDeg', ...
    'state', ...
    'cueIdentityVal', ...
    'cueIdentityName', ...
    'cueOnsetIdx', ...
    'cueOffsetIdx', ...
    'rewardIdx', ...
    'rewardSiteDeg', ...
    'crossingIdx', ...
    'rewardRelDeg', ...
    'lickRelDeg'};

%% ===================== MAIN LOOP =====================
for f = 1:numel(file)

    thisFile = file{f};
    fname = fullfile(path, thisFile);

    % ---------- parse session label ----------
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

    sessionLabel = [mouseName '  ' sessionDate];

    % ---------- read file ----------
    fid = fopen(fname, 'r');
    if fid == -1
        warning('Could not open file: %s', thisFile);
        continue
    end

    fgetl(fid); % skip header

    % 1 time_s
    % 2 distance_traveled
    % 3 position(deg)
    % 4 visual_state
    % 5 next_RW_location_idx
    % 6 reward_delivered
    % 7 brake_applied
    % 8 lick_detection
    % 9 blackout_cue_identity
    C = textscan(fid, '%f%f%f%f%f%f%f%f%f', 'TreatAsEmpty', {'NaN','nan'});
    fclose(fid);

    if numel(C) < 9 || isempty(C{1})
        warning('Could not parse file: %s', thisFile);
        continue
    end

    t                    = C{1};
    pos_deg              = C{3};
    reward               = C{6};
    lick                 = C{8};
    blackout_cue_id      = C{9};

    valid = ~isnan(t) & ~isnan(pos_deg) & ~isnan(reward);
    t               = t(valid);
    pos_deg         = pos_deg(valid);
    reward          = reward(valid);
    lick            = lick(valid);
    blackout_cue_id = blackout_cue_id(valid);

    if numel(t) < 10
        warning('Too few valid samples in file: %s', thisFile);
        continue
    end

    % ---------- continuous position ----------
    pos_deg_wrapped  = mod(pos_deg, 360);
    pos_cm_unwrapped = rad2deg(unwrap(deg2rad(pos_deg_wrapped))) / 360 * track_cm;

    % ---------- restrict to selected portion of session by laps ----------
    lapNumber = floor((pos_cm_unwrapped - pos_cm_unwrapped(1)) ./ track_cm) + 1;
    totalLaps = lapNumber(end);

    if totalLaps < 1
        warning('Could not determine laps in file: %s', thisFile);
        continue
    end

    switch lapMode
        case 'entire'
            keepLap = true(size(lapNumber));

        case 'first'
            nKeep = max(1, ceil(totalLaps * lapPct / 100));
            lastLapToKeep = nKeep;
            keepLap = lapNumber <= lastLapToKeep;

        case 'last'
            nKeep = max(1, ceil(totalLaps * lapPct / 100));
            firstLapToKeep = max(1, totalLaps - nKeep + 1);
            keepLap = lapNumber >= firstLapToKeep;

        case 'custom'
            firstLapToKeep = max(1, floor(totalLaps * lapStartPct / 100) + 1);
            lastLapToKeep  = max(firstLapToKeep, ceil(totalLaps * lapEndPct / 100));
            keepLap = lapNumber >= firstLapToKeep & lapNumber <= lastLapToKeep;

        otherwise
            error('Unknown lapMode.');
    end

    t                = t(keepLap);
    pos_deg          = pos_deg(keepLap);
    pos_deg_wrapped  = pos_deg_wrapped(keepLap);
    pos_cm_unwrapped = pos_cm_unwrapped(keepLap);
    reward           = reward(keepLap);
    lick             = lick(keepLap);
    blackout_cue_id  = blackout_cue_id(keepLap);

    if numel(t) < 10
        warning('Too few samples remain after lap cropping in file: %s', thisFile);
        continue
    end

    % ---------- reward onsets ----------
    rewardLogical = reward > 0;
    rewardOnsetIdx = find(diff([0; rewardLogical]) == 1);

    if isempty(rewardOnsetIdx)
        warning('No reward onsets found in file: %s', thisFile);
        continue
    end

    rewardSiteDeg = nan(size(rewardOnsetIdx));
    keepReward = false(size(rewardOnsetIdx));

    for r = 1:numel(rewardOnsetIdx)
        rp = mod(pos_deg_wrapped(rewardOnsetIdx(r)), 360);
        angDiff = abs(mod(rp - activeReward_deg + 180, 360) - 180);
        [minDiff, locIdx] = min(angDiff);

        if minDiff <= rewardTolerance_deg
            rewardSiteDeg(r) = activeReward_deg(locIdx);
            keepReward(r) = true;
        end
    end

    rewardOnsetIdx = rewardOnsetIdx(keepReward);
    rewardSiteDeg  = rewardSiteDeg(keepReward);

    if isempty(rewardOnsetIdx)
        warning('No reward onsets matched active reward pair in file: %s', thisFile);
        continue
    end

    % ---------- cue blackout epochs ----------
    cueValid = ~isnan(blackout_cue_id);
    cueOnsetIdx  = find(diff([0; cueValid]) == 1);
    cueOffsetIdx = find(diff([cueValid; 0]) == -1);

    keepCue = false(size(cueOnsetIdx));
    cueIdentityVal  = nan(size(cueOnsetIdx));
    cueIdentityName = cell(size(cueOnsetIdx));
    targetRewardDeg = nan(size(cueOnsetIdx));

    for c = 1:numel(cueOnsetIdx)
        val = blackout_cue_id(cueOnsetIdx(c));
        match = find(cueIdentityValues == val, 1, 'first');

        if isempty(match)
            continue
        end

        keepCue(c) = true;
        cueIdentityVal(c) = val;
        cueIdentityName{c} = cueIdentityNames{match};
        targetRewardDeg(c) = cueToRewardMap_deg(match);
    end

    cueOnsetIdx     = cueOnsetIdx(keepCue);
    cueOffsetIdx    = cueOffsetIdx(keepCue);
    cueIdentityVal  = cueIdentityVal(keepCue);
    cueIdentityName = cueIdentityName(keepCue);
    targetRewardDeg = targetRewardDeg(keepCue);

    if isempty(cueOnsetIdx)
        warning('No valid cue epochs found in file: %s', thisFile);
        continue
    end

    %% ===================== CUE -> REWARD INTERVALS =====================
    for c = 1:numel(cueOnsetIdx)

        thisCueOn  = cueOnsetIdx(c);
        thisCueOff = cueOffsetIdx(c);
        thisCueVal = cueIdentityVal(c);
        thisCueName = cueIdentityName{c};
        thisTargetRewardDeg = targetRewardDeg(c);

        % Next reward after cue onset
        rNext = find(rewardOnsetIdx > thisCueOn, 1, 'first');
        if isempty(rNext)
            continue
        end

        thisRewardIdx = rewardOnsetIdx(rNext);
        thisRewardSiteDeg = rewardSiteDeg(rNext);

        % Cue identity should match actual reward site
        if thisRewardSiteDeg ~= thisTargetRewardDeg
            warning('Cue->reward mismatch in %s: cue %s predicts %.0f deg, actual next reward at %.0f deg.', ...
                thisFile, thisCueName, thisTargetRewardDeg, thisRewardSiteDeg);

            if skipCueRewardMismatches
                continue
            end
        end

        idxStart = thisCueOff;
        idxEnd   = thisRewardIdx;

        if idxEnd <= idxStart + 1
            continue
        end

        % Target is actual rewarded crossing
        targetCrossIdx = thisRewardIdx;

        % Non-target is the other active site if crossed before reward
        nonTargetSiteDeg = activeReward_deg(activeReward_deg ~= thisTargetRewardDeg);
        nonTargetCrossIdx = find_last_crossing(nonTargetSiteDeg, idxStart, idxEnd, pos_cm_unwrapped, track_cm);

        % Near/far split
        if isnan(nonTargetCrossIdx)
            targetState = 'preReward_target_near';
        else
            targetState = 'preReward_target_far';
        end

        % ---------- collect target licks ----------
        lickRelDeg = get_lick_positions_relative_to_site( ...
            targetCrossIdx, thisTargetRewardDeg, pos_cm_unwrapped, lick, track_cm, rasterWindow_deg, rasterPost_deg);

        rewardRelDeg = get_reward_position_relative_to_site( ...
            thisRewardIdx, targetCrossIdx, thisTargetRewardDeg, pos_cm_unwrapped, track_cm);

        eventRows(end+1,:) = { ...
            sessionLabel, ...
            thisTargetRewardDeg, ...
            targetState, ...
            thisCueVal, ...
            thisCueName, ...
            thisCueOn, ...
            thisCueOff, ...
            thisRewardIdx, ...
            thisRewardSiteDeg, ...
            targetCrossIdx, ...
            rewardRelDeg, ...
            lickRelDeg}; %#ok<SAGROW>

        % ---------- collect non-target licks ----------
        if ~isempty(nonTargetSiteDeg) && ~isnan(nonTargetCrossIdx)
            lickRelDeg = get_lick_positions_relative_to_site( ...
                nonTargetCrossIdx, nonTargetSiteDeg, pos_cm_unwrapped, lick, track_cm, rasterWindow_deg, rasterPost_deg);

            eventRows(end+1,:) = { ...
                sessionLabel, ...
                nonTargetSiteDeg, ...
                'preReward_nonTarget', ...
                thisCueVal, ...
                thisCueName, ...
                thisCueOn, ...
                thisCueOff, ...
                thisRewardIdx, ...
                thisRewardSiteDeg, ...
                nonTargetCrossIdx, ...
                NaN, ...
                lickRelDeg}; %#ok<SAGROW>
        end
    end
end

%% ===================== BUILD TABLE =====================
if isempty(eventRows)
    error('No usable lick-raster events found.');
end

R = cell2table(eventRows, 'VariableNames', varNames);

numericVars = {'siteDeg','cueIdentityVal','cueOnsetIdx','cueOffsetIdx', ...
               'rewardIdx','rewardSiteDeg','crossingIdx','rewardRelDeg'};
for k = 1:numel(numericVars)
    v = R.(numericVars{k});
    if iscell(v)
        R.(numericVars{k}) = cell2mat(v);
    end
end

%% ===================== SESSION TITLE =====================
sessionList = unique(R.sessionName, 'stable');

if numel(sessionList) == 1
    sessionTitle = sessionList{1};
else
    sessionTitle = sprintf('%s + %d more sessions', sessionList{1}, numel(sessionList)-1);
end

sessionTitle = sprintf('%s | %s', sessionTitle, lapLabel);

%% ===================== RASTER PLOT SETTINGS =====================
stateOrder = {'preReward_nonTarget','preReward_target_near','preReward_target_far'};
stateLabels = {'Pre-reward non-target','Pre-reward target near','Pre-reward target far'};

%% ===================== FIGURE 1: FIRST REWARD SITE =====================
plot_lick_raster_figure(R, activeReward_deg(1), stateOrder, stateLabels, ...
    rasterWindow_deg, rasterPost_deg, sessionTitle, axisFontSize, labelFontSize, titleFontSize);

%% ===================== FIGURE 2: SECOND REWARD SITE =====================
plot_lick_raster_figure(R, activeReward_deg(2), stateOrder, stateLabels, ...
    rasterWindow_deg, rasterPost_deg, sessionTitle, axisFontSize, labelFontSize, titleFontSize);

%% ===================== LOCAL FUNCTIONS =====================
function crossIdx = find_last_crossing(siteDeg, idxStart, idxEnd, pos_cm_unwrapped_local, track_cm_local)

    crossIdx = NaN;

    if idxEnd <= idxStart + 1
        return
    end

    site_cm = siteDeg / 360 * track_cm_local;
    pseg = pos_cm_unwrapped_local(idxStart:idxEnd);

    minPosSeg = min(pseg);
    maxPosSeg = max(pseg);

    lapStart = floor((minPosSeg - site_cm) / track_cm_local) - 1;
    lapEnd   = ceil((maxPosSeg - site_cm) / track_cm_local) + 1;

    crossings = [];

    for lap = lapStart:lapEnd
        cp = site_cm + lap * track_cm_local;
        localIdx = find(pseg(1:end-1) < cp & pseg(2:end) >= cp);

        if ~isempty(localIdx)
            crossings = [crossings; idxStart - 1 + localIdx(:) + 1]; %#ok<AGROW>
        end
    end

    if ~isempty(crossings)
        crossIdx = crossings(end);
    end
end

function lickRelDeg = get_lick_positions_relative_to_site( ...
    crossIdx, siteDeg, pos_cm_unwrapped, lick, track_cm, rasterWindow_deg, rasterPost_deg)

    site_cm = siteDeg / 360 * track_cm;
    cp = site_cm + round((pos_cm_unwrapped(crossIdx) - site_cm) / track_cm) * track_cm;

    rel_cm = pos_cm_unwrapped - cp;
    rel_deg = rel_cm / track_cm * 360;

    lickIdx = lick > 0 & rel_deg >= -rasterWindow_deg & rel_deg <= rasterPost_deg;
    lickRelDeg = rel_deg(lickIdx)';
end

function rewardRelDeg = get_reward_position_relative_to_site( ...
    rewardIdx, crossIdx, siteDeg, pos_cm_unwrapped, track_cm)

    site_cm = siteDeg / 360 * track_cm;

    % aligned site crossing position in unwrapped cm
    cp = site_cm + round((pos_cm_unwrapped(crossIdx) - site_cm) / track_cm) * track_cm;

    % actual reward position in unwrapped cm
    rewardPos_cm = pos_cm_unwrapped(rewardIdx);

    % convert difference to degrees
    rewardRelDeg = (rewardPos_cm - cp) / track_cm * 360;
end

function plot_lick_raster_figure(R, siteDeg, stateOrder, stateLabels, ...
    rasterWindow_deg, rasterPost_deg, sessionTitle, axisFontSize, labelFontSize, titleFontSize)

    figure;
    tiledlayout(3,1, 'TileSpacing','compact', 'Padding','compact');

    for s = 1:numel(stateOrder)
        nexttile;
        hold on

        idx = R.siteDeg == siteDeg & strcmp(R.state, stateOrder{s});
        S = R(idx,:);

        for tr = 1:height(S)
            x = S.lickRelDeg{tr};
            if ~isempty(x)
                y0 = tr - 0.4;
                y1 = tr + 0.4;

                for k = 1:numel(x)
                    plot([x(k) x(k)], [y0 y1], 'k-', 'LineWidth', 1);
                end
            end

            % Mark actual reward delivery location for target trials
            if strcmp(stateOrder{s}, 'preReward_target_near') || strcmp(stateOrder{s}, 'preReward_target_far')
                if ~isnan(S.rewardRelDeg(tr))
                    plot(S.rewardRelDeg(tr), tr, 'r.', 'MarkerSize', 14);
                end
            end
        end

        xline(0, 'r--', 'LineWidth', 1.2);

        xlim([-rasterWindow_deg rasterPost_deg]);
        ylim([0 max(1,height(S)+1)]);
        set(gca, 'FontSize', axisFontSize);

        ylabel('Trial', 'FontSize', labelFontSize);
        title(sprintf('%s | %.0f° site | n = %d', stateLabels{s}, siteDeg, height(S)), ...
            'FontSize', titleFontSize);
        grid on
    end

    xlabel('Degrees relative to aligned site crossing (0 = nominal site)', 'FontSize', labelFontSize);
    sgtitle(sprintf('%s | Lick raster around %.0f° reward site', sessionTitle, siteDeg), ...
        'FontSize', titleFontSize + 1);
end