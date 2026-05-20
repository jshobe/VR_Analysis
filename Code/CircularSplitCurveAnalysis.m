clear; clc;

%% ===================== USER SETTINGS =====================
track_cm = 540;

% Track geometry
reward_deg_all = [0 90 180 270]; %#ok<NASGU>
cue_deg_all    = [30 120 210 300];

% Active reward pair for this mouse/session
% Examples:
%   JB5: [0 180]
%   JB2: [90 270]
activeReward_deg = [90 270];

% Cue identity values in blackout_cue_identity column
cueIdentityValues = [60 90];
cueIdentityNames  = {'basketball','star'};

% Map cue identity to active reward location
cueToRewardMap_deg = [90 270];

% Figure 1 approach-speed window
speedWindow_cm = 5;

% Figure 1 raw deceleration windows
decelPreWindow_cm     = 5;
decelControlWindow_cm = [30 40];

% Exclude final region near nominal site to avoid reward-jitter contamination
excludeFinal_deg = 2;
excludeFinal_cm  = track_cm * excludeFinal_deg / 360;

% Figure 2 speed profile settings
profileWindow_deg = 90;
profileBin_deg    = 2;

% Stop profiles at -excludeFinal_deg, not at 0
profileEdges_deg   = -profileWindow_deg:profileBin_deg:-excludeFinal_deg;
profileCenters_deg = profileEdges_deg(1:end-1) + profileBin_deg/2;

% Exclusions
minSpeed_cm_s = 5;   % set to 0 to disable low-speed exclusion

% Angular snapping tolerances
rewardTolerance_deg = 35;
cueTolerance_deg    = 35;

% If cue-predicted target and actual reward site disagree, skip interval
skipCueRewardMismatches = false;

% Plot settings
axisFontSize   = 13;
labelFontSize  = 15;
titleFontSize  = 16;
legendFontSize = 11;

%% ===================== BASIC CHECKS =====================
if numel(activeReward_deg) ~= 2
    error('activeReward_deg must contain exactly two reward locations.');
end

if numel(cueIdentityValues) ~= 2 || numel(cueToRewardMap_deg) ~= 2
    error('cueIdentityValues and cueToRewardMap_deg must each contain exactly two values.');
end

if ~all(ismember(cueToRewardMap_deg, activeReward_deg))
    error('cueToRewardMap_deg must map to the two active reward locations.');
end

%% ===================== REMEMBER LAST FOLDER =====================
settingsFile = fullfile(tempdir, 'lastVRFolder_intervalCueAnalysis.mat');

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

%% ===================== LICK-NEAR-REWARD EXCLUSION =====================
keepOnlyTrialsWithLickNearReward = menu( ...
    'Keep only target trials with a lick near reward delivery?', ...
    'No', ...
    'Yes');

if isequal(keepOnlyTrialsWithLickNearReward, 0)
    error('No lick-near-reward option selected.');
end

lickNearRewardEnabled = (keepOnlyTrialsWithLickNearReward == 2);

if lickNearRewardEnabled
    answer = inputdlg({'Enter lick window around reward delivery (deg):'}, ...
                      'Lick near reward window', [1 50], {'5'});
    if isempty(answer)
        error('No lick window entered.');
    end
    lickNearRewardWindow_deg = str2double(answer{1});
    if ~isfinite(lickNearRewardWindow_deg) || lickNearRewardWindow_deg <= 0
        error('lickNearRewardWindow_deg must be > 0.');
    end
else
    lickNearRewardWindow_deg = 5;
end

%% ===================== CENTRAL TENDENCY SETTING =====================
summaryChoice = menu( ...
    'Use mean or median for speed summaries?', ...
    'Median', ...
    'Mean');

if isequal(summaryChoice, 0)
    error('No summary method selected.');
end

if summaryChoice == 1
    summaryMethodName = 'median';
    summaryFcn = @(x) median(x);
else
    summaryMethodName = 'mean';
    summaryFcn = @(x) mean(x);
end

%% ===================== CONTAINERS =====================
allRows = {};

varNames = { ...
    'sessionName', ...
    'intervalType', ...
    'intervalNumber', ...
    'eventNumber', ...
    'siteDeg', ...
    'siteName', ...
    'state', ...
    'cueIdentityVal', ...
    'cueIdentityName', ...
    'cueOnsetIdx', ...
    'cueOffsetIdx', ...
    'cueTrackPosDeg', ...
    'cueLocationDeg', ...
    'targetRewardDeg', ...
    'rewardIdx', ...
    'rewardSiteDeg', ...
    'crossingIdx', ...
    'approachSpeed', ...
    'decelNearSpeed', ...
    'decelControlSpeed', ...
    'rawDecel'};

allProfileSpeed = [];
allProfileSiteDeg = [];
allProfileState = {};
allProfileScenario = {};

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

    % New format:
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
    distance_traveled    = C{2}; %#ok<NASGU>
    pos_deg              = C{3};
    visual_state         = C{4}; %#ok<NASGU>
    next_rw_location_idx = C{5}; %#ok<NASGU>
    reward               = C{6};
    brake                = C{7};
    lick                 = C{8};
    blackout_cue_id      = C{9};

    valid = ~isnan(t) & ~isnan(pos_deg) & ~isnan(reward);
    t               = t(valid);
    pos_deg         = pos_deg(valid);
    reward          = reward(valid);
    brake           = brake(valid);
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
    brake            = brake(keepLap);
    lick             = lick(keepLap);
    blackout_cue_id  = blackout_cue_id(keepLap);

    if numel(t) < 10
        warning('Too few samples remain after lap cropping in file: %s', thisFile);
        continue
    end

    % ---------- speed ----------
    dt = diff(t);
    speed_cm_s = [NaN; abs(diff(pos_cm_unwrapped) ./ dt)];
    speed_cm_s(~isfinite(speed_cm_s)) = NaN;

    % Exclude brake samples
    speed_cm_s(brake > 0) = NaN;

    % Exclude very low speeds if desired
    if minSpeed_cm_s > 0
        speed_cm_s(speed_cm_s < minSpeed_cm_s) = NaN;
    end

    % ---------- reward onsets ----------
    rewardLogical = reward > 0;
    rewardOnsetIdx = find(diff([0; rewardLogical]) == 1);

    if isempty(rewardOnsetIdx)
        warning('No reward onsets found in file: %s', thisFile);
        continue
    end

    % Snap actual reward onsets to active reward pair
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
    cueTrackPosDeg  = nan(size(cueOnsetIdx));
    cueLocationDeg  = nan(size(cueOnsetIdx));
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
        cueTrackPosDeg(c) = mod(pos_deg_wrapped(cueOnsetIdx(c)), 360);

        angDiff = abs(mod(cueTrackPosDeg(c) - cue_deg_all + 180, 360) - 180);
        [minDiff, locIdx] = min(angDiff);

        if minDiff <= cueTolerance_deg
            cueLocationDeg(c) = cue_deg_all(locIdx);
        else
            cueLocationDeg(c) = NaN;
        end

        targetRewardDeg(c) = cueToRewardMap_deg(match);
    end

    cueOnsetIdx     = cueOnsetIdx(keepCue);
    cueOffsetIdx    = cueOffsetIdx(keepCue);
    cueIdentityVal  = cueIdentityVal(keepCue);
    cueIdentityName = cueIdentityName(keepCue);
    cueTrackPosDeg  = cueTrackPosDeg(keepCue);
    cueLocationDeg  = cueLocationDeg(keepCue);
    targetRewardDeg = targetRewardDeg(keepCue);

    if isempty(cueOnsetIdx)
        warning('No valid cue epochs found in file: %s', thisFile);
    end

    eventCounter = 0;
    intervalCounter = 0;

    %% ===================== 1) CUE -> REWARD INTERVALS =====================
    for c = 1:numel(cueOnsetIdx)

        thisCueOn  = cueOnsetIdx(c);
        thisCueOff = cueOffsetIdx(c);
        thisCueVal = cueIdentityVal(c);
        thisCueName = cueIdentityName{c};
        thisCueTrackDeg = cueTrackPosDeg(c);
        thisCueLocDeg = cueLocationDeg(c);
        thisTargetRewardDeg = targetRewardDeg(c);

        % Forward cue->target distance in degrees
        if ~isnan(thisCueLocDeg)
            cueToTargetDistDeg = mod(thisTargetRewardDeg - thisCueLocDeg, 360);
        else
            cueToTargetDistDeg = NaN;
        end

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

        % Interval is from cue offset to reward onset
        idxStart = thisCueOff;
        idxEnd   = thisRewardIdx;

        if idxEnd <= idxStart + 1
            continue
        end

        intervalCounter = intervalCounter + 1;

        % Target is the actual rewarded crossing
        targetCrossIdx = thisRewardIdx;

        % Non-target is the other active reward site, if crossed before reward
        nonTargetSiteDeg = activeReward_deg(activeReward_deg ~= thisTargetRewardDeg);
        nonTargetCrossIdx = find_last_crossing(nonTargetSiteDeg, idxStart, idxEnd, pos_cm_unwrapped, track_cm);

        % Forward cue->non-target distance in degrees
        if ~isnan(thisCueLocDeg) && ~isempty(nonTargetSiteDeg)
            cueToNonTargetDistDeg = mod(nonTargetSiteDeg - thisCueLocDeg, 360);
        else
            cueToNonTargetDistDeg = NaN;
        end

        % Split target into near/far
        if isnan(nonTargetCrossIdx)
            targetState = 'preReward_target_near';
        else
            targetState = 'preReward_target_far';
        end

        % ---------- target event ----------
        cp = get_crossing_position_cm(thisTargetRewardDeg, targetCrossIdx, pos_cm_unwrapped, track_cm);

        % Optionally exclude target trials with no lick near actual reward delivery
        if lickNearRewardEnabled
            hasLickNearReward = check_lick_near_reward( ...
                thisRewardIdx, targetCrossIdx, thisTargetRewardDeg, ...
                pos_cm_unwrapped, lick, track_cm, lickNearRewardWindow_deg);

            if ~hasLickNearReward
                continue
            end
        end

        [approachSpeed, decelNearSpeed, decelControlSpeed, rawDecel] = get_event_metrics( ...
            cp, targetCrossIdx, pos_cm_unwrapped, speed_cm_s, ...
            speedWindow_cm, decelPreWindow_cm, decelControlWindow_cm, ...
            excludeFinal_cm, summaryFcn);

        if ~isnan(approachSpeed) || ~isnan(rawDecel)

            eventCounter = eventCounter + 1;

            allRows(end+1,:) = { ...
                sessionLabel, ...
                'cueToReward', ...
                intervalCounter, ...
                eventCounter, ...
                thisTargetRewardDeg, ...
                sprintf('%.0fdeg_site', thisTargetRewardDeg), ...
                targetState, ...
                thisCueVal, ...
                thisCueName, ...
                thisCueOn, ...
                thisCueOff, ...
                thisCueTrackDeg, ...
                thisCueLocDeg, ...
                thisTargetRewardDeg, ...
                thisRewardIdx, ...
                thisRewardSiteDeg, ...
                targetCrossIdx, ...
                approachSpeed, ...
                decelNearSpeed, ...
                decelControlSpeed, ...
                rawDecel}; %#ok<SAGROW>

            profileSpeed = get_speed_profile_before_site( ...
                cp, pos_cm_unwrapped, speed_cm_s, track_cm, profileEdges_deg, summaryFcn);

            if strcmp(targetState, 'preReward_target_near')
                if cueToTargetDistDeg == 60
                    scenarioLabel = 'preReward_target_near_60';
                elseif cueToTargetDistDeg == 150
                    scenarioLabel = 'preReward_target_near_150';
                else
                    scenarioLabel = 'preReward_target_near_other';
                end
            elseif strcmp(targetState, 'preReward_target_far')
                if cueToTargetDistDeg == 240
                    scenarioLabel = 'preReward_target_far_240';
                elseif cueToTargetDistDeg == 330
                    scenarioLabel = 'preReward_target_far_330';
                else
                    scenarioLabel = 'preReward_target_far_other';
                end
            else
                scenarioLabel = targetState;
            end

            allProfileSpeed(end+1,:) = profileSpeed; %#ok<SAGROW>
            allProfileSiteDeg(end+1,1) = thisTargetRewardDeg; %#ok<SAGROW>
            allProfileState{end+1,1} = targetState; %#ok<SAGROW>
            allProfileScenario{end+1,1} = scenarioLabel; %#ok<SAGROW>
        end

        % ---------- non-target event ----------
        if ~isempty(nonTargetSiteDeg) && ~isnan(nonTargetCrossIdx)

            cp = get_crossing_position_cm(nonTargetSiteDeg, nonTargetCrossIdx, pos_cm_unwrapped, track_cm);

            [approachSpeed, decelNearSpeed, decelControlSpeed, rawDecel] = get_event_metrics( ...
                cp, nonTargetCrossIdx, pos_cm_unwrapped, speed_cm_s, ...
                speedWindow_cm, decelPreWindow_cm, decelControlWindow_cm, ...
                excludeFinal_cm, summaryFcn);

            if ~isnan(approachSpeed) || ~isnan(rawDecel)

                eventCounter = eventCounter + 1;

                allRows(end+1,:) = { ...
                    sessionLabel, ...
                    'cueToReward', ...
                    intervalCounter, ...
                    eventCounter, ...
                    nonTargetSiteDeg, ...
                    sprintf('%.0fdeg_site', nonTargetSiteDeg), ...
                    'preReward_nonTarget', ...
                    thisCueVal, ...
                    thisCueName, ...
                    thisCueOn, ...
                    thisCueOff, ...
                    thisCueTrackDeg, ...
                    thisCueLocDeg, ...
                    thisTargetRewardDeg, ...
                    thisRewardIdx, ...
                    thisRewardSiteDeg, ...
                    nonTargetCrossIdx, ...
                    approachSpeed, ...
                    decelNearSpeed, ...
                    decelControlSpeed, ...
                    rawDecel}; %#ok<SAGROW>

                profileSpeed = get_speed_profile_before_site( ...
                    cp, pos_cm_unwrapped, speed_cm_s, track_cm, profileEdges_deg, summaryFcn);

                if cueToNonTargetDistDeg == 60
                    scenarioLabel = 'preReward_nonTarget_60';
                elseif cueToNonTargetDistDeg == 150
                    scenarioLabel = 'preReward_nonTarget_150';
                else
                    scenarioLabel = 'preReward_nonTarget_other';
                end

                allProfileSpeed(end+1,:) = profileSpeed; %#ok<SAGROW>
                allProfileSiteDeg(end+1,1) = nonTargetSiteDeg; %#ok<SAGROW>
                allProfileState{end+1,1} = 'preReward_nonTarget'; %#ok<SAGROW>
                allProfileScenario{end+1,1} = scenarioLabel; %#ok<SAGROW>
            end
        end
    end

    %% ===================== 2) REWARD -> NEXT CUE INTERVALS =====================
    for r = 1:numel(rewardOnsetIdx)

        thisRewardIdx = rewardOnsetIdx(r);

        % Next cue after this reward
        cNext = find(cueOnsetIdx > thisRewardIdx, 1, 'first');

        if isempty(cNext)
            continue
        end

        thisCueOn = cueOnsetIdx(cNext);

        idxStart = thisRewardIdx;
        idxEnd   = thisCueOn;

        if idxEnd <= idxStart + 1
            continue
        end

        intervalCounter = intervalCounter + 1;

        % Keep last crossing to each active reward site in this interval
        for s = 1:numel(activeReward_deg)

            thisSiteDeg = activeReward_deg(s);
            crossIdx = find_last_crossing(thisSiteDeg, idxStart, idxEnd, pos_cm_unwrapped, track_cm);

            if isnan(crossIdx)
                continue
            end

            cp = get_crossing_position_cm(thisSiteDeg, crossIdx, pos_cm_unwrapped, track_cm);

            [approachSpeed, decelNearSpeed, decelControlSpeed, rawDecel] = get_event_metrics( ...
                cp, crossIdx, pos_cm_unwrapped, speed_cm_s, ...
                speedWindow_cm, decelPreWindow_cm, decelControlWindow_cm, ...
                excludeFinal_cm, summaryFcn);

            if isnan(approachSpeed) && isnan(rawDecel)
                continue
            end

            eventCounter = eventCounter + 1;

            allRows(end+1,:) = { ...
                sessionLabel, ...
                'cueExpected', ...
                intervalCounter, ...
                eventCounter, ...
                thisSiteDeg, ...
                sprintf('%.0fdeg_site', thisSiteDeg), ...
                'cue_expected', ...
                NaN, ...
                '', ...
                NaN, ...
                NaN, ...
                NaN, ...
                NaN, ...
                NaN, ...
                thisRewardIdx, ...
                rewardSiteDeg(r), ...
                crossIdx, ...
                approachSpeed, ...
                decelNearSpeed, ...
                decelControlSpeed, ...
                rawDecel}; %#ok<SAGROW>

            profileSpeed = get_speed_profile_before_site( ...
                cp, pos_cm_unwrapped, speed_cm_s, track_cm, profileEdges_deg, summaryFcn);

            allProfileSpeed(end+1,:) = profileSpeed; %#ok<SAGROW>
            allProfileSiteDeg(end+1,1) = thisSiteDeg; %#ok<SAGROW>
            allProfileState{end+1,1} = 'cue_expected'; %#ok<SAGROW>
            allProfileScenario{end+1,1} = 'cue_expected'; %#ok<SAGROW>
        end
    end
end

%% ===================== BUILD TABLE =====================
if isempty(allRows)
    error('No usable interval-based events found.');
end

T = cell2table(allRows, 'VariableNames', varNames);

numericVars = {'intervalNumber','eventNumber','siteDeg','cueIdentityVal','cueOnsetIdx', ...
               'cueOffsetIdx','cueTrackPosDeg','cueLocationDeg','targetRewardDeg', ...
               'rewardIdx','rewardSiteDeg','crossingIdx','approachSpeed', ...
               'decelNearSpeed','decelControlSpeed','rawDecel'};

for k = 1:numel(numericVars)
    v = T.(numericVars{k});
    if iscell(v)
        T.(numericVars{k}) = cell2mat(v);
    end
end

%% ===================== RAW DECELERATION TABLE BY BAR =====================
stateOrder_bar = { ...
    'cue_expected', ...
    'preReward_nonTarget', ...
    'preReward_target_near', ...
    'preReward_target_far'};

siteOrder = activeReward_deg;

colNames = { ...
    sprintf('site_%g_cueExpected',      siteOrder(1)), ...
    sprintf('site_%g_nonTarget',        siteOrder(1)), ...
    sprintf('site_%g_targetNear',       siteOrder(1)), ...
    sprintf('site_%g_targetFar',        siteOrder(1)), ...
    sprintf('site_%g_cueExpected',      siteOrder(2)), ...
    sprintf('site_%g_nonTarget',        siteOrder(2)), ...
    sprintf('site_%g_targetNear',       siteOrder(2)), ...
    sprintf('site_%g_targetFar',        siteOrder(2))};

rawCols = cell(1, numel(colNames));
maxLen = 0;
colCounter = 0;

for s = 1:numel(siteOrder)
    for st = 1:numel(stateOrder_bar)
        colCounter = colCounter + 1;

        idx = T.siteDeg == siteOrder(s) & strcmp(T.state, stateOrder_bar{st});
        vals = T.rawDecel(idx);
        vals = vals(~isnan(vals));

        rawCols{colCounter} = vals(:);
        maxLen = max(maxLen, numel(vals));
    end
end

for i = 1:numel(rawCols)
    v = rawCols{i};
    if numel(v) < maxLen
        v(end+1:maxLen,1) = NaN;
    end
    rawCols{i} = v;
end

rawDecelTable = table(rawCols{1}, rawCols{2}, rawCols{3}, rawCols{4}, ...
                      rawCols{5}, rawCols{6}, rawCols{7}, rawCols{8}, ...
                      'VariableNames', colNames);

disp('Raw deceleration values organized by bar:')
disp(rawDecelTable)

%% ===================== SUMMARIES =====================
disp('Counts by state:')
disp(groupsummary(T, 'state'))

disp('Counts by site and state:')
disp(groupsummary(T, {'siteDeg','state'}))

fprintf('%ss by state:\n', summaryMethodName)
disp(groupsummary(T, 'state', summaryMethodName, {'approachSpeed','decelNearSpeed','decelControlSpeed','rawDecel'}))

fprintf('%ss by site and state:\n', summaryMethodName)
disp(groupsummary(T, {'siteDeg','state'}, summaryMethodName, {'approachSpeed','decelNearSpeed','decelControlSpeed','rawDecel'}))

%% ===================== SANITY CHECKS =====================
D = T(strcmp(T.state,'preReward_target_near') | ...
      strcmp(T.state,'preReward_target_far')  | ...
      strcmp(T.state,'preReward_nonTarget'), :);

matchesGroundTruth = (D.siteDeg == D.rewardSiteDeg);

fprintf('\nGround-truth sanity check:\n');

targetMask = strcmp(D.state,'preReward_target_near') | strcmp(D.state,'preReward_target_far');
nonTargetMask = strcmp(D.state,'preReward_nonTarget');

fprintf('preReward_target near/far matches rewardSiteDeg: %d / %d (%.1f%%)\n', ...
    sum(matchesGroundTruth(targetMask)), sum(targetMask), ...
    100 * sum(matchesGroundTruth(targetMask)) / max(sum(targetMask),1));

fprintf('preReward_nonTarget matches rewardSiteDeg: %d / %d (%.1f%%)\n', ...
    sum(matchesGroundTruth(nonTargetMask)), sum(nonTargetMask), ...
    100 * sum(matchesGroundTruth(nonTargetMask)) / max(sum(nonTargetMask),1));

%% ===================== SESSION TITLE =====================
sessionList = unique(T.sessionName, 'stable');

if numel(sessionList) == 1
    sessionTitle = sessionList{1};
else
    sessionTitle = sprintf('%s + %d more sessions', sessionList{1}, numel(sessionList)-1);
end

if lickNearRewardEnabled
    lickFilterLabel = sprintf('lick within ±%.1f° of reward required', lickNearRewardWindow_deg);
else
    lickFilterLabel = 'no lick-near-reward exclusion';
end

sessionTitle = sprintf('%s | %s | %s | %s | exclude final %.1f°', ...
    sessionTitle, lapLabel, lickFilterLabel, summaryMethodName, excludeFinal_deg);

%% ===================== FIGURE 1: SPEED AND RAW DECELERATION =====================
stateOrder_bar = { ...
    'cue_expected', ...
    'preReward_nonTarget', ...
    'preReward_target_near', ...
    'preReward_target_far'};

stateLabels_bar = { ...
    'Cue expected', ...
    'Pre-reward non-target', ...
    'Pre-reward target near', ...
    'Pre-reward target far'};

siteOrder = activeReward_deg;
siteLabels = arrayfun(@(x) sprintf('%.0f deg', x), siteOrder, 'UniformOutput', false);

M_speed = nan(numel(siteOrder), numel(stateOrder_bar));
SEM_speed = nan(numel(siteOrder), numel(stateOrder_bar));

M_decel = nan(numel(siteOrder), numel(stateOrder_bar));
SEM_decel = nan(numel(siteOrder), numel(stateOrder_bar));

for s = 1:numel(siteOrder)
    for st = 1:numel(stateOrder_bar)

        idx = T.siteDeg == siteOrder(s) & strcmp(T.state, stateOrder_bar{st});

        valsSpeed = T.approachSpeed(idx);
        valsSpeed = valsSpeed(~isnan(valsSpeed));

        valsDecel = T.rawDecel(idx);
        valsDecel = valsDecel(~isnan(valsDecel));

        if ~isempty(valsSpeed)
            M_speed(s,st) = summaryFcn(valsSpeed);
            SEM_speed(s,st) = std(valsSpeed) / sqrt(numel(valsSpeed));
        end

        if ~isempty(valsDecel)
            M_decel(s,st) = summaryFcn(valsDecel);
            SEM_decel(s,st) = std(valsDecel) / sqrt(numel(valsDecel));
        end
    end
end

figure;
tiledlayout(1,2);

% ---------- LEFT: APPROACH SPEED ----------
nexttile;
bh1 = bar(M_speed);
hold on

for st = 1:numel(stateOrder_bar)
    xBar = bh1(st).XEndPoints;
    errorbar(xBar, M_speed(:,st), SEM_speed(:,st), 'k.', 'LineWidth', 1.2);
end

set(gca, 'XTick', 1:numel(siteOrder), ...
         'XTickLabel', siteLabels, ...
         'FontSize', axisFontSize);

ylabel(sprintf('%s speed in window ending %.1f° before site (cm/s)', ...
    summaryMethodName, excludeFinal_deg), ...
    'FontSize', labelFontSize);

xlabel('Reward site', 'FontSize', labelFontSize);
title('Approach speed', 'FontSize', titleFontSize);
grid on

% ---------- RIGHT: RAW DECELERATION ----------
nexttile;
bh2 = bar(M_decel);
hold on

for st = 1:numel(stateOrder_bar)
    xBar = bh2(st).XEndPoints;
    errorbar(xBar, M_decel(:,st), SEM_decel(:,st), 'k.', 'LineWidth', 1.2);
end

set(gca, 'XTick', 1:numel(siteOrder), ...
         'XTickLabel', siteLabels, ...
         'FontSize', axisFontSize);

ylabel(sprintf('Raw deceleration: %.0f-%.0f cm speed minus window ending %.1f° before site (cm/s)', ...
    decelControlWindow_cm(1), decelControlWindow_cm(2), excludeFinal_deg), ...
    'FontSize', labelFontSize);

xlabel('Reward site', 'FontSize', labelFontSize);
title('Raw deceleration', 'FontSize', titleFontSize);
grid on

legend(stateLabels_bar, 'FontSize', legendFontSize, 'Location', 'best');

sgtitle(sprintf('%s | Speed and raw deceleration by reward site and behavioral state', sessionTitle), ...
    'FontSize', titleFontSize + 1);

%% ===================== FIGURE 2: SPEED PROFILE PLOT =====================
scenarioOrder = { ...
    'cue_expected', ...
    'preReward_nonTarget_60', ...
    'preReward_nonTarget_150', ...
    'preReward_target_near_60', ...
    'preReward_target_near_150', ...
    'preReward_target_far_240', ...
    'preReward_target_far_330'};

scenarioLabels = { ...
    'Cue expected', ...
    'Pre-reward non-target 60°', ...
    'Pre-reward non-target 150°', ...
    'Pre-reward target near 60°', ...
    'Pre-reward target near 150°', ...
    'Pre-reward target far 240°', ...
    'Pre-reward target far 330°'};

if isempty(allProfileSpeed)
    error('No speed profiles were collected.');
end

figure;
tiledlayout(1, numel(siteOrder));

for s = 1:numel(siteOrder)

    thisSiteDeg = siteOrder(s);

    nexttile;
    hold on

    plotHandles = gobjects(0);
    plotLabels = {};

    for st = 1:numel(scenarioOrder)

        idx = allProfileSiteDeg == thisSiteDeg & strcmp(allProfileScenario, scenarioOrder{st});

        if ~any(idx)
            continue
        end

        profileMat = allProfileSpeed(idx,:);
        profileVec = nan(1, size(profileMat,2));

        for bb = 1:size(profileMat,2)
            vals = profileMat(:,bb);
            vals = vals(~isnan(vals));
            if ~isempty(vals)
                profileVec(bb) = summaryFcn(vals);
            end
        end

        h = plot(profileCenters_deg, profileVec, 'LineWidth', 2);
        plotHandles(end+1) = h; %#ok<SAGROW>
        plotLabels{end+1} = scenarioLabels{st}; %#ok<SAGROW>
    end

    xlabel('Degrees before site', 'FontSize', labelFontSize);
    ylabel(sprintf('%s speed (cm/s)', summaryMethodName), 'FontSize', labelFontSize);

    title(sprintf('%s | Approach to %.0f° site', sessionTitle, thisSiteDeg), ...
        'FontSize', titleFontSize);

    xlim([-profileWindow_deg -excludeFinal_deg]);
    xline(-excludeFinal_deg, 'k--', 'LineWidth', 1);

    set(gca, 'FontSize', axisFontSize);
    grid on

    if s == numel(siteOrder) && ~isempty(plotHandles)
        legend(plotHandles, plotLabels, 'FontSize', legendFontSize, 'Location', 'best');
    end
end

%% ===================== OPTIONAL SAVE TABLE =====================
[outFile, outPath] = uiputfile('interval_based_cue_analysis.csv', ...
    'Save event table as CSV');

if ~isequal(outFile,0)
    writetable(T, fullfile(outPath, outFile));
    fprintf('Saved table to: %s\n', fullfile(outPath, outFile));
end

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

function cp = get_crossing_position_cm(siteDeg, crossIdx, pos_cm_unwrapped, track_cm)

    site_cm = siteDeg / 360 * track_cm;

    cp = site_cm + ...
         round((pos_cm_unwrapped(crossIdx) - site_cm) / track_cm) * track_cm;
end

function [approachSpeed, decelNearSpeed, decelControlSpeed, rawDecel] = get_event_metrics( ...
    cp, crossIdx, pos_cm_unwrapped, speed_cm_s, ...
    speedWindow_cm, decelPreWindow_cm, decelControlWindow_cm, ...
    excludeFinal_cm, summaryFcn)

    beforeMask = (1:numel(pos_cm_unwrapped))' < crossIdx;

    % Approach window ends excludeFinal_cm before site
    speedMask = pos_cm_unwrapped >= (cp - excludeFinal_cm - speedWindow_cm) & ...
                pos_cm_unwrapped <  (cp - excludeFinal_cm);
    speedMask = speedMask & beforeMask;

    % Near-site deceleration window also ends excludeFinal_cm before site
    decelNearMask = pos_cm_unwrapped >= (cp - excludeFinal_cm - decelPreWindow_cm) & ...
                    pos_cm_unwrapped <  (cp - excludeFinal_cm);
    decelNearMask = decelNearMask & beforeMask;

    % Control window unchanged
    decelControlMask = pos_cm_unwrapped >= (cp - decelControlWindow_cm(2)) & ...
                       pos_cm_unwrapped <  (cp - decelControlWindow_cm(1));
    decelControlMask = decelControlMask & beforeMask;

    speedVals = speed_cm_s(speedMask);
    speedVals = speedVals(~isnan(speedVals));

    decelNearVals = speed_cm_s(decelNearMask);
    decelNearVals = decelNearVals(~isnan(decelNearVals));

    decelControlVals = speed_cm_s(decelControlMask);
    decelControlVals = decelControlVals(~isnan(decelControlVals));

    if isempty(speedVals)
        approachSpeed = NaN;
    else
        approachSpeed = summaryFcn(speedVals);
    end

    if isempty(decelNearVals)
        decelNearSpeed = NaN;
    else
        decelNearSpeed = summaryFcn(decelNearVals);
    end

    if isempty(decelControlVals)
        decelControlSpeed = NaN;
    else
        decelControlSpeed = summaryFcn(decelControlVals);
    end

    if isnan(decelNearSpeed) || isnan(decelControlSpeed)
        rawDecel = NaN;
    else
        rawDecel = decelControlSpeed - decelNearSpeed;
    end
end

function profileSpeed = get_speed_profile_before_site( ...
    cp, pos_cm_unwrapped, speed_cm_s, track_cm, profileEdges_deg, summaryFcn)

    edges_cm = profileEdges_deg / 360 * track_cm;
    nBins = numel(profileEdges_deg) - 1;

    profileSpeed = nan(1, nBins);

    rel_cm = pos_cm_unwrapped - cp;

    for b = 1:nBins
        binMask = rel_cm >= edges_cm(b) & rel_cm < edges_cm(b+1);
        vals = speed_cm_s(binMask);
        vals = vals(~isnan(vals));

        if ~isempty(vals)
            profileSpeed(b) = summaryFcn(vals);
        end
    end
end

function hasLickNearReward = check_lick_near_reward( ...
    rewardIdx, crossIdx, siteDeg, pos_cm_unwrapped, lick, track_cm, lickNearRewardWindow_deg)

    site_cm = siteDeg / 360 * track_cm;

    % Aligned site crossing in unwrapped cm
    cp = site_cm + round((pos_cm_unwrapped(crossIdx) - site_cm) / track_cm) * track_cm;

    % Actual reward position relative to aligned site
    rewardPos_cm = pos_cm_unwrapped(rewardIdx);
    rewardRelDeg = (rewardPos_cm - cp) / track_cm * 360;

    % All lick positions relative to aligned site
    relDeg = (pos_cm_unwrapped - cp) / track_cm * 360;

    lickMask = lick > 0 & ...
               relDeg >= (rewardRelDeg - lickNearRewardWindow_deg) & ...
               relDeg <= (rewardRelDeg + lickNearRewardWindow_deg);

    hasLickNearReward = any(lickMask);
end