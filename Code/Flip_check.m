clear; clc;

%% ===================== USER SETTINGS =====================
track_cm = 540;

approachWindow_cm = 20;        % final 20 cm before site
controlWindow_cm  = [40 60];   % control window before site

possibleReward_deg = [0 180];
possibleReward_names = {'0deg_site','180deg_site'};

% ASSUMED mapping for next_RW_location_idx
% Change this if needed after inspection
nextRwIdxValues = [1 2];
nextRwDegMap    = [0 180];

rewardTolerance_deg = 30;   % snapping actual reward position to 0 or 180

%% ===================== SELECT ONE FILE =====================
[file, path] = uigetfile('*.txt', 'Select newest-format VR session file');

if isequal(file,0)
    error('No file selected.');
end

fname = fullfile(path, file);

%% ===================== READ FILE =====================
fid = fopen(fname, 'r');
if fid == -1
    error('Could not open file.');
end

headerLine = fgetl(fid); %#ok<NASGU>

% 1 time_s
% 2 distance_traveled
% 3 position(deg)
% 4 visual_state
% 5 next_RW_location_idx
% 6 blackout_object_position
% 7 reward_delivered
% 8 brake_applied
% 9 lick_detection
C = textscan(fid, '%f%f%f%f%f%f%f%f%f', 'TreatAsEmpty', {'NaN','nan'});
fclose(fid);

t            = C{1};
distance_cm  = C{2}; %#ok<NASGU>
pos_deg      = C{3};
visual_state = C{4}; %#ok<NASGU>
next_rw_idx  = C{5};
blackout_pos = C{6};
reward       = C{7};
brake        = C{8};
lick         = C{9}; %#ok<NASGU>

valid = ~isnan(t) & ~isnan(pos_deg) & ~isnan(reward);
t            = t(valid);
pos_deg      = pos_deg(valid);
next_rw_idx  = next_rw_idx(valid);
blackout_pos = blackout_pos(valid);
reward       = reward(valid);
brake        = brake(valid);

if numel(t) < 10
    error('Too few valid samples.');
end

%% ===================== POSITION / SPEED =====================
pos_cm_unwrapped = rad2deg(unwrap(deg2rad(pos_deg))) / 360 * track_cm;
pos_cm_wrapped   = mod((pos_deg / 360) * track_cm, track_cm); %#ok<NASGU>

dt = diff(t);
speed_cm_s = [NaN; abs(diff(pos_cm_unwrapped) ./ dt)];
speed_cm_s(~isfinite(speed_cm_s)) = NaN;

% exclude brake samples from speed windows
speed_cm_s(brake > 0) = NaN;

%% ===================== EVENT ONSETS =====================
rewardLogical = reward > 0;
rewardOnsetIdx = find(diff([0; rewardLogical]) == 1);

cueLogical = ~isnan(blackout_pos);
cueOnsetIdx = find(diff([0; cueLogical]) == 1);

fprintf('\nFound %d reward onsets\n', numel(rewardOnsetIdx));
fprintf('Found %d cue onsets\n', numel(cueOnsetIdx));

if isempty(rewardOnsetIdx)
    error('No reward onsets found.');
end

%% ===================== BUILD APPROACH EVENTS =====================
rows = {};

varNames = { ...
    'eventNumber', ...
    'siteDeg', ...
    'siteName', ...
    'state', ...
    'cueIdxUsed', ...
    'cuePos', ...
    'activeTargetIdx', ...
    'activeTargetDeg', ...
    'crossingIdx', ...
    'prevRewardIdx', ...
    'nextRewardIdx', ...
    'nextRewardSiteDeg', ...
    'matchesNextReward', ...
    'preSpeed', ...
    'controlSpeed', ...
    'decelIndex'};

eventCounter = 0;

for s = 1:numel(possibleReward_deg)

    thisSiteDeg  = possibleReward_deg(s);
    thisSiteName = possibleReward_names{s};
    thisSite_cm  = thisSiteDeg / 360 * track_cm;

    minPos = min(pos_cm_unwrapped);
    maxPos = max(pos_cm_unwrapped);

    lapStart = floor((minPos - thisSite_cm) / track_cm) - 1;
    lapEnd   = ceil((maxPos - thisSite_cm) / track_cm) + 1;

    crossingPositions = thisSite_cm + (lapStart:lapEnd) * track_cm;

    for cp = crossingPositions

        crossIdx = find(pos_cm_unwrapped(1:end-1) < cp & pos_cm_unwrapped(2:end) >= cp, 1, 'first');
        if isempty(crossIdx)
            continue
        end
        crossIdx = crossIdx + 1;

        if crossIdx < 3
            continue
        end

        prevRewardIdx = rewardOnsetIdx(find(rewardOnsetIdx < crossIdx, 1, 'last'));
        nextRewardIdx = rewardOnsetIdx(find(rewardOnsetIdx > crossIdx, 1, 'first'));

        if isempty(prevRewardIdx), prevRewardIdx = NaN; end
        if isempty(nextRewardIdx), nextRewardIdx = NaN; end

        % Determine whether cue has happened since previous reward
        if isnan(prevRewardIdx)
            cueAfterPrevReward = cueOnsetIdx(cueOnsetIdx < crossIdx);
        else
            cueAfterPrevReward = cueOnsetIdx(cueOnsetIdx > prevRewardIdx & cueOnsetIdx < crossIdx);
        end

        cueIdxUsed = NaN;
        cuePos = NaN;
        activeTargetIdx = NaN;
        activeTargetDeg = NaN;
        state = '';

        if isempty(cueAfterPrevReward)
            state = 'cue_expected';
        else
            cueIdxUsed = cueAfterPrevReward(end);
            cuePos = blackout_pos(cueIdxUsed);

            vals = next_rw_idx(cueIdxUsed:crossIdx);
            vals = vals(~isnan(vals));

            if isempty(vals)
                continue
            end

            activeTargetIdx = vals(end);

            mapMatch = find(nextRwIdxValues == activeTargetIdx, 1, 'first');
            if isempty(mapMatch)
                fprintf('Unmapped next_RW_location_idx value: %.3f at crossing %d\n', activeTargetIdx, crossIdx);
                continue
            end

            activeTargetDeg = nextRwDegMap(mapMatch);

            if thisSiteDeg == activeTargetDeg
                state = 'preReward_target';
            else
                state = 'preReward_nonTarget';
            end
        end

        % Actual next reward site
        nextRewardSiteDeg = NaN;
        matchesNextReward = NaN;

        if ~isnan(nextRewardIdx)
            rewardPos = mod(pos_deg(nextRewardIdx), 360);

            angDiff = abs(mod(rewardPos - possibleReward_deg + 180, 360) - 180);
            [minDiff, locIdx] = min(angDiff);

            if minDiff <= rewardTolerance_deg
                nextRewardSiteDeg = possibleReward_deg(locIdx);
                matchesNextReward = (thisSiteDeg == nextRewardSiteDeg);
            end
        end

        % Speed windows before crossing
        beforeMask = (1:numel(pos_cm_unwrapped))' < crossIdx;

        preMask = pos_cm_unwrapped >= (cp - approachWindow_cm) & ...
                  pos_cm_unwrapped <  cp;
        preMask = preMask & beforeMask;

        controlMask = pos_cm_unwrapped >= (cp - controlWindow_cm(2)) & ...
                      pos_cm_unwrapped <  (cp - controlWindow_cm(1));
        controlMask = controlMask & beforeMask;

        preVals = speed_cm_s(preMask);
        preVals = preVals(~isnan(preVals));

        controlVals = speed_cm_s(controlMask);
        controlVals = controlVals(~isnan(controlVals));

        if isempty(preVals) || isempty(controlVals)
            continue
        end

        preSpeed = mean(preVals);
        controlSpeed = mean(controlVals);
        decelIndex = controlSpeed - preSpeed;

        eventCounter = eventCounter + 1;

        rows(end+1,:) = { ...
            eventCounter, ...
            thisSiteDeg, ...
            thisSiteName, ...
            state, ...
            cueIdxUsed, ...
            cuePos, ...
            activeTargetIdx, ...
            activeTargetDeg, ...
            crossIdx, ...
            prevRewardIdx, ...
            nextRewardIdx, ...
            nextRewardSiteDeg, ...
            matchesNextReward, ...
            preSpeed, ...
            controlSpeed, ...
            decelIndex}; %#ok<SAGROW>
    end
end

if isempty(rows)
    error('No usable approach events found.');
end

T = cell2table(rows, 'VariableNames', varNames);

numericVars = {'eventNumber','siteDeg','cueIdxUsed','cuePos','activeTargetIdx', ...
               'activeTargetDeg','crossingIdx','prevRewardIdx','nextRewardIdx', ...
               'nextRewardSiteDeg','matchesNextReward','preSpeed','controlSpeed','decelIndex'};

for k = 1:numel(numericVars)
    if iscell(T.(numericVars{k}))
        T.(numericVars{k}) = cell2mat(T.(numericVars{k}));
    end
end

%% ===================== PRINT MAIN CHECKS =====================
fprintf('\n===== STATE COUNTS =====\n');
disp(groupsummary(T, 'state'));

fprintf('\n===== PRE-REWARD CHECK: DOES LABEL MATCH ACTUAL NEXT REWARD SITE? =====\n');
D = T(strcmp(T.state,'preReward_target') | strcmp(T.state,'preReward_nonTarget'), :);
D = D(~isnan(D.nextRewardSiteDeg), :);

targetMask = strcmp(D.state,'preReward_target');
nonTargetMask = strcmp(D.state,'preReward_nonTarget');

fprintf('preReward_target:    %d / %d match next reward site (%.1f%%)\n', ...
    sum(D.matchesNextReward(targetMask)), sum(targetMask), ...
    100 * sum(D.matchesNextReward(targetMask)) / max(sum(targetMask),1));

fprintf('preReward_nonTarget: %d / %d match next reward site (%.1f%%)\n', ...
    sum(D.matchesNextReward(nonTargetMask)), sum(nonTargetMask), ...
    100 * sum(D.matchesNextReward(nonTargetMask)) / max(sum(nonTargetMask),1));

fprintf('\n===== DOES activeTargetDeg MATCH ACTUAL NEXT REWARD SITE? =====\n');
validActive = ~isnan(D.activeTargetDeg);
fprintf('activeTargetDeg matches nextRewardSiteDeg: %d / %d (%.1f%%)\n', ...
    sum(D.activeTargetDeg(validActive) == D.nextRewardSiteDeg(validActive)), ...
    sum(validActive), ...
    100 * sum(D.activeTargetDeg(validActive) == D.nextRewardSiteDeg(validActive)) / max(sum(validActive),1));

fprintf('\n===== FIRST 40 PRE-REWARD EVENTS =====\n');
disp(D(1:min(40,height(D)), ...
    {'eventNumber','siteDeg','state','activeTargetIdx','activeTargetDeg', ...
     'nextRewardSiteDeg','matchesNextReward','cuePos','cueIdxUsed','crossingIdx','nextRewardIdx'}));

fprintf('\n===== MISMATCHED TARGET EVENTS =====\n');
badTarget = D(strcmp(D.state,'preReward_target') & D.matchesNextReward == 0, :);
disp(badTarget(1:min(40,height(badTarget)), ...
    {'eventNumber','siteDeg','state','activeTargetIdx','activeTargetDeg', ...
     'nextRewardSiteDeg','matchesNextReward','cuePos','cueIdxUsed','crossingIdx','nextRewardIdx'}));

fprintf('\n===== MISMATCHED activeTargetDeg EVENTS =====\n');
badActive = D(validActive & D.activeTargetDeg ~= D.nextRewardSiteDeg, :);
disp(badActive(1:min(40,height(badActive)), ...
    {'eventNumber','siteDeg','state','activeTargetIdx','activeTargetDeg', ...
     'nextRewardSiteDeg','matchesNextReward','cuePos','cueIdxUsed','crossingIdx','nextRewardIdx'}));

%% ===================== QUICK VISUAL CHECK =====================
stateOrder = {'cue_expected','preReward_nonTarget','preReward_target'};
stateLabels = {'Cue expected','Pre-reward non-target','Pre-reward target'};
siteOrder = [0 180];

M = nan(numel(siteOrder), numel(stateOrder));
SEM = nan(numel(siteOrder), numel(stateOrder));

for i = 1:numel(siteOrder)
    for j = 1:numel(stateOrder)
        idx = T.siteDeg == siteOrder(i) & strcmp(T.state, stateOrder{j});
        vals = T.decelIndex(idx);
        vals = vals(~isnan(vals));
        if ~isempty(vals)
            M(i,j) = mean(vals);
            SEM(i,j) = std(vals) / sqrt(numel(vals));
        end
    end
end

figure;
bh = bar(M);
hold on
for j = 1:numel(stateOrder)
    xBar = bh(j).XEndPoints;
    errorbar(xBar, M(:,j), SEM(:,j), 'k.', 'LineWidth', 1.2);
end
set(gca, 'XTick', 1:2, 'XTickLabel', {'0 deg','180 deg'});
ylabel('Mean deceleration index');
title('Deceleration by site and state');
legend(stateLabels, 'Location', 'best');
grid on;

%% ===================== OPTIONAL SAVE TABLE =====================
[saveFile, savePath] = uiputfile('flip_check_output.csv', 'Save debug table as CSV');
if ~isequal(saveFile,0)
    writetable(T, fullfile(savePath, saveFile));
    fprintf('\nSaved debug table to:\n%s\n', fullfile(savePath, saveFile));
end