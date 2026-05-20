clear; clc;

%% ===================== USER SETTINGS =====================
track_cm = 540;

% Track geometry
reward_deg_all = [0 90 180 270]; %#ok<NASGU>
cue_deg_all    = [30 120 210 300];

% Active reward pair for this mouse/session
% Examples:
%   [0 180]
%   [90 270]
activeReward_deg = [0 180]; %JB5 0  180

% Cue identity values in blackout_cue_identity column
% Current setup:
%   0  = basketball
%   30 = star
%   
cueIdentityValues = [0 30];
cueIdentityNames  = {'basketball','star'};

% Map cue identity to active reward location
% Example for JB5-style training:
%   star (0)       -> 180
%   basketball(30) -> 0
cueToRewardMap_deg = [0 180]; %JB5 

% Speed analysis windows
approachWindow_cm = 5;        % final 20 cm before event site
controlWindow_cm  = [60 70];   % control window before same site

% Exclusions
minSpeed_cm_s = 0;             % set to 0 to disable low-speed exclusion

% Angular snapping tolerances
rewardTolerance_deg = 35;
cueTolerance_deg    = 35;

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

%% ===================== CONTAINERS =====================
allRows = {};

varNames = { ...
    'sessionName', ...
    'intervalType', ...          % cueExpected or cueToReward
    'intervalNumber', ...
    'eventNumber', ...
    'siteDeg', ...
    'siteName', ...
    'state', ...                 % cue_expected / preReward_target / preReward_nonTarget
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
    'preSpeed', ...
    'controlSpeed', ...
    'decelIndex'};

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
    lick                 = C{8}; %#ok<NASGU>
    blackout_cue_id      = C{9};

    valid = ~isnan(t) & ~isnan(pos_deg) & ~isnan(reward);
    t               = t(valid);
    pos_deg         = pos_deg(valid);
    reward          = reward(valid);
    brake           = brake(valid);
    blackout_cue_id = blackout_cue_id(valid);

    if numel(t) < 10
        warning('Too few valid samples in file: %s', thisFile);
        continue
    end

    % ---------- continuous position / speed ----------
    pos_deg_wrapped  = mod(pos_deg, 360);
    pos_cm_unwrapped = rad2deg(unwrap(deg2rad(pos_deg_wrapped))) / 360 * track_cm;

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
    cueOnsetIdx = find(diff([0; cueValid]) == 1);
    cueOffsetIdx = find(diff([cueValid; 0]) == -1);

    % Keep only cue epochs with recognized identities
    keepCue = false(size(cueOnsetIdx));
    cueIdentityVal = nan(size(cueOnsetIdx));
    cueIdentityName = cell(size(cueOnsetIdx));
    cueTrackPosDeg = nan(size(cueOnsetIdx));
    cueLocationDeg = nan(size(cueOnsetIdx));
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

        % Next reward after cue onset
        rNext = find(rewardOnsetIdx > thisCueOn, 1, 'first');
        if isempty(rNext)
            continue
        end

        thisRewardIdx = rewardOnsetIdx(rNext);
        thisRewardSiteDeg = rewardSiteDeg(rNext);

        % Optional consistency check: cue identity should match actual reward site
        if thisRewardSiteDeg ~= thisTargetRewardDeg
        warning('Skipping cue->reward mismatch in %s: cue %s predicts %.0f deg, actual next reward at %.0f deg.', ...
        thisFile, thisCueName, thisTargetRewardDeg, thisRewardSiteDeg);
        continue
        end

        % Interval is from cue offset to reward onset
        idxStart = thisCueOff;
        idxEnd   = thisRewardIdx;

        if idxEnd <= idxStart + 1
            continue
        end

        intervalCounter = intervalCounter + 1;

        % Target event is the actual rewarded crossing
        targetCrossIdx = thisRewardIdx;

        % Final non-target crossing before reward
        nonTargetSiteDeg = activeReward_deg(activeReward_deg ~= thisTargetRewardDeg);
        nonTargetCrossIdx = find_last_crossing(nonTargetSiteDeg, idxStart, idxEnd, pos_cm_unwrapped, track_cm);

        % ----- target event -----
        if ~isnan(targetCrossIdx)
            beforeMask = (1:numel(pos_cm_unwrapped))' < targetCrossIdx;

            cp = thisTargetRewardDeg / 360 * track_cm + ...
                 round((pos_cm_unwrapped(targetCrossIdx) - (thisTargetRewardDeg / 360 * track_cm)) / track_cm) * track_cm;

            preMask = pos_cm_unwrapped >= (cp - approachWindow_cm) & pos_cm_unwrapped < cp;
            preMask = preMask & beforeMask;

            controlMask = pos_cm_unwrapped >= (cp - controlWindow_cm(2)) & pos_cm_unwrapped < (cp - controlWindow_cm(1));
            controlMask = controlMask & beforeMask;

            preVals = speed_cm_s(preMask);
            preVals = preVals(~isnan(preVals));
            ctrlVals = speed_cm_s(controlMask);
            ctrlVals = ctrlVals(~isnan(ctrlVals));

            if ~isempty(preVals) && ~isempty(ctrlVals)
                eventCounter = eventCounter + 1;

                preMean = mean(preVals);
                controlMean = mean(ctrlVals);
                decelIndex = controlMean - preMean;

                allRows(end+1,:) = { ...
                    sessionLabel, ...
                    'cueToReward', ...
                    intervalCounter, ...
                    eventCounter, ...
                    thisTargetRewardDeg, ...
                    sprintf('%.0fdeg_site', thisTargetRewardDeg), ...
                    'preReward_target', ...
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
                    preMean, ...
                    controlMean, ...
                    decelIndex}; %#ok<SAGROW>
            end
        end

        % ----- non-target event -----
        if ~isempty(nonTargetSiteDeg) && ~isnan(nonTargetCrossIdx)
            beforeMask = (1:numel(pos_cm_unwrapped))' < nonTargetCrossIdx;

            cp = nonTargetSiteDeg / 360 * track_cm + ...
                 round((pos_cm_unwrapped(nonTargetCrossIdx) - (nonTargetSiteDeg / 360 * track_cm)) / track_cm) * track_cm;

            preMask = pos_cm_unwrapped >= (cp - approachWindow_cm) & pos_cm_unwrapped < cp;
            preMask = preMask & beforeMask;

            controlMask = pos_cm_unwrapped >= (cp - controlWindow_cm(2)) & pos_cm_unwrapped < (cp - controlWindow_cm(1));
            controlMask = controlMask & beforeMask;

            preVals = speed_cm_s(preMask);
            preVals = preVals(~isnan(preVals));
            ctrlVals = speed_cm_s(controlMask);
            ctrlVals = ctrlVals(~isnan(ctrlVals));

            if ~isempty(preVals) && ~isempty(ctrlVals)
                eventCounter = eventCounter + 1;

                preMean = mean(preVals);
                controlMean = mean(ctrlVals);
                decelIndex = controlMean - preMean;

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
                    preMean, ...
                    controlMean, ...
                    decelIndex}; %#ok<SAGROW>
            end
        end
    end

    %% ===================== 2) REWARD -> NEXT CUE INTERVALS (CUE EXPECTED) =====================
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

            beforeMask = (1:numel(pos_cm_unwrapped))' < crossIdx;

            cp = thisSiteDeg / 360 * track_cm + ...
                 round((pos_cm_unwrapped(crossIdx) - (thisSiteDeg / 360 * track_cm)) / track_cm) * track_cm;

            preMask = pos_cm_unwrapped >= (cp - approachWindow_cm) & pos_cm_unwrapped < cp;
            preMask = preMask & beforeMask;

            controlMask = pos_cm_unwrapped >= (cp - controlWindow_cm(2)) & pos_cm_unwrapped < (cp - controlWindow_cm(1));
            controlMask = controlMask & beforeMask;

            preVals = speed_cm_s(preMask);
            preVals = preVals(~isnan(preVals));
            ctrlVals = speed_cm_s(controlMask);
            ctrlVals = ctrlVals(~isnan(ctrlVals));

            if isempty(preVals) || isempty(ctrlVals)
                continue
            end

            eventCounter = eventCounter + 1;

            preMean = mean(preVals);
            controlMean = mean(ctrlVals);
            decelIndex = controlMean - preMean;

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
                preMean, ...
                controlMean, ...
                decelIndex}; %#ok<SAGROW>
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
               'rewardIdx','rewardSiteDeg','crossingIdx','preSpeed','controlSpeed','decelIndex'};

for k = 1:numel(numericVars)
    v = T.(numericVars{k});
    if iscell(v)
        T.(numericVars{k}) = cell2mat(v);
    end
end

%% ===================== SUMMARIES =====================
disp('Counts by state:')
disp(groupsummary(T, 'state'))

disp('Counts by site and state:')
disp(groupsummary(T, {'siteDeg','state'}))

disp('Means by state:')
disp(groupsummary(T, 'state', 'mean', {'preSpeed','controlSpeed','decelIndex'}))

disp('Means by site and state:')
disp(groupsummary(T, {'siteDeg','state'}, 'mean', {'preSpeed','controlSpeed','decelIndex'}))

preTbl = T(strcmp(T.intervalType,'cueToReward'), :);
if ~isempty(preTbl)
    disp('Means by cue identity and state:')
    disp(groupsummary(preTbl, {'cueIdentityName','state'}, 'mean', {'preSpeed','controlSpeed','decelIndex'}))

    disp('Means by cue location and state:')
    disp(groupsummary(preTbl, {'cueLocationDeg','state'}, 'mean', {'preSpeed','controlSpeed','decelIndex'}))
end

%% ===================== SANITY CHECKS =====================
D = T(strcmp(T.state,'preReward_target') | strcmp(T.state,'preReward_nonTarget'), :);
matchesGroundTruth = (D.siteDeg == D.rewardSiteDeg);

fprintf('\nGround-truth sanity check:\n');

targetMask = strcmp(D.state, 'preReward_target');
nonTargetMask = strcmp(D.state, 'preReward_nonTarget');

fprintf('preReward_target matches rewardSiteDeg: %d / %d (%.1f%%)\n', ...
    sum(matchesGroundTruth(targetMask)), sum(targetMask), ...
    100 * sum(matchesGroundTruth(targetMask)) / max(sum(targetMask),1));

fprintf('preReward_nonTarget matches rewardSiteDeg: %d / %d (%.1f%%)\n', ...
    sum(matchesGroundTruth(nonTargetMask)), sum(nonTargetMask), ...
    100 * sum(matchesGroundTruth(nonTargetMask)) / max(sum(nonTargetMask),1));

%% ===================== SINGLE SUMMARY PLOT ONLY =====================
stateOrder = {'cue_expected','preReward_nonTarget','preReward_target'};
stateLabels = {'Cue expected','Pre-reward non-target','Pre-reward target'};

siteOrder = activeReward_deg;
siteLabels = arrayfun(@(x) sprintf('%.0f deg', x), siteOrder, 'UniformOutput', false);

M = nan(numel(siteOrder), numel(stateOrder));
SEM = nan(numel(siteOrder), numel(stateOrder));

for s = 1:numel(siteOrder)
    for st = 1:numel(stateOrder)
        idx = T.siteDeg == siteOrder(s) & strcmp(T.state, stateOrder{st});
        vals = T.decelIndex(idx);
        vals = vals(~isnan(vals));
        if ~isempty(vals)
            M(s,st) = mean(vals);
            SEM(s,st) = std(vals) / sqrt(numel(vals));
        end
    end
end

figure;
bh = bar(M);
hold on

for st = 1:numel(stateOrder)
    xBar = bh(st).XEndPoints;
    errorbar(xBar, M(:,st), SEM(:,st), 'k.', 'LineWidth', 1.2);
end

set(gca, 'XTick', 1:numel(siteOrder), ...
         'XTickLabel', siteLabels, ...
         'FontSize', axisFontSize);

ylabel('Mean deceleration index', 'FontSize', labelFontSize);
xlabel('Location (deg)', 'FontSize', labelFontSize);
title('Deceleration by location and behavioral state', 'FontSize', titleFontSize);
legend(stateLabels, 'FontSize', legendFontSize, 'Location', 'best');
grid on

%% ===================== OPTIONAL SAVE TABLE =====================
[outFile, outPath] = uiputfile('interval_based_cue_analysis.csv', ...
    'Save event table as CSV');
if ~isequal(outFile,0)
    writetable(T, fullfile(outPath, outFile));
    fprintf('Saved table to: %s\n', fullfile(outPath, outFile));
end

%% ===================== LOCAL FUNCTION =====================
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