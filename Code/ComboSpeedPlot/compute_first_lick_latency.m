function T = compute_first_lick_latency( ...
    D, lapStartIdx, trialNums, cfg)
% COMPUTE_FIRST_LICK_LATENCY
% Pairs each valid reward onset with the first subsequent new lick onset.
%
% The output contains one row per requested complete lap. Reward omissions
% remain in the table with NaN event times. A valid latency requires exactly
% one reward onset in the lap and a new lick onset after that reward, before
% both the lap end and cfg.maxLickLatency_s.

requiredFields = {'t', 'pos_deg', 'reward', 'lick'};
for k = 1:numel(requiredFields)
    if ~isfield(D, requiredFields{k})
        error('Session samples are missing D.%s.', requiredFields{k});
    end
end

if nargin < 4 || isempty(cfg)
    cfg = struct();
end

if ~isfield(cfg, 'maxLickLatency_s')
    cfg.maxLickLatency_s = 10;
end

if ~isscalar(cfg.maxLickLatency_s) || ...
        isnan(cfg.maxLickLatency_s) || ...
        cfg.maxLickLatency_s <= 0
    error('cfg.maxLickLatency_s must be a positive scalar.');
end

t = D.t(:);
pos_deg = D.pos_deg(:);
reward = D.reward(:);
lick = D.lick(:);

nRows = numel(t);
if numel(pos_deg) ~= nRows || ...
        numel(reward) ~= nRows || ...
        numel(lick) ~= nRows
    error('D.t, D.pos_deg, D.reward, and D.lick must align row by row.');
end

if any(~isfinite(t)) || any(diff(t) <= 0)
    error('Session timestamps must be finite and strictly increasing.');
end

lapStartIdx = lapStartIdx(:);
if numel(lapStartIdx) < 2 || ...
        any(diff(lapStartIdx) <= 0) || ...
        lapStartIdx(1) < 1 || ...
        lapStartIdx(end) > nRows
    error('lapStartIdx is invalid for the supplied session samples.');
end

nCompleteLaps = numel(lapStartIdx) - 1;

if nargin < 3 || isempty(trialNums)
    trialNums = (1:nCompleteLaps)';
else
    trialNums = trialNums(:);
end

if any(~isfinite(trialNums)) || ...
        any(trialNums ~= round(trialNums)) || ...
        any(trialNums < 1) || ...
        any(trialNums > nCompleteLaps)
    error('trialNums must contain valid complete-lap numbers.');
end

% A sustained positive signal is one event. A new event requires a
% non-positive sample followed by a positive sample.
rewardMask = isfinite(reward) & reward > 0;
lickMask = isfinite(lick) & lick > 0;

rewardOnsetMask = rewardMask & [true; ~rewardMask(1:end-1)];
lickOnsetMask = lickMask & [true; ~lickMask(1:end-1)];

rewardOnsetIdx = find(rewardOnsetMask);
lickOnsetIdx = find(lickOnsetMask);

nTrials = numel(trialNums);

Lap = trialNums;
LapStartTime_s = nan(nTrials, 1);
LapEndTime_s = nan(nTrials, 1);
RewardCount = zeros(nTrials, 1);
RewardIndex = nan(nTrials, 1);
RewardTime_s = nan(nTrials, 1);
RewardPosition_deg = nan(nTrials, 1);
SearchEndTime_s = nan(nTrials, 1);
FirstLickIndex = nan(nTrials, 1);
FirstLickTime_s = nan(nTrials, 1);
FirstLickPosition_deg = nan(nTrials, 1);
LickLatency_s = nan(nTrials, 1);

for j = 1:nTrials
    lap = Lap(j);
    lapFirst = lapStartIdx(lap);
    lapLast = lapStartIdx(lap + 1) - 1;

    LapStartTime_s(j) = t(lapFirst);
    LapEndTime_s(j) = t(lapLast);

    lapRewardIdx = rewardOnsetIdx( ...
        rewardOnsetIdx >= lapFirst & ...
        rewardOnsetIdx <= lapLast);

    RewardCount(j) = numel(lapRewardIdx);

    % Omission and multiple-reward laps are deliberately not assigned a
    % reward-to-lick latency.
    if RewardCount(j) ~= 1
        continue
    end

    rewardIdx = lapRewardIdx(1);
    rewardTime = t(rewardIdx);
    searchEndTime = min( ...
        t(lapLast), ...
        rewardTime + cfg.maxLickLatency_s);

    RewardIndex(j) = rewardIdx;
    RewardTime_s(j) = rewardTime;
    RewardPosition_deg(j) = pos_deg(rewardIdx);
    SearchEndTime_s(j) = searchEndTime;

    lapLickIdx = lickOnsetIdx( ...
        lickOnsetIdx > rewardIdx & ...
        lickOnsetIdx <= lapLast & ...
        t(lickOnsetIdx) <= searchEndTime);

    if isempty(lapLickIdx)
        continue
    end

    firstLickIdx = lapLickIdx(1);

    FirstLickIndex(j) = firstLickIdx;
    FirstLickTime_s(j) = t(firstLickIdx);
    FirstLickPosition_deg(j) = pos_deg(firstLickIdx);
    LickLatency_s(j) = t(firstLickIdx) - rewardTime;
end

IsRewardedLap = RewardCount == 1;
IsOmissionLap = RewardCount == 0;
HasMultipleRewards = RewardCount > 1;
HasFirstLick = IsRewardedLap & isfinite(LickLatency_s);

T = table( ...
    Lap, ...
    LapStartTime_s, ...
    LapEndTime_s, ...
    RewardCount, ...
    RewardIndex, ...
    RewardTime_s, ...
    RewardPosition_deg, ...
    SearchEndTime_s, ...
    FirstLickIndex, ...
    FirstLickTime_s, ...
    FirstLickPosition_deg, ...
    LickLatency_s, ...
    IsRewardedLap, ...
    IsOmissionLap, ...
    HasMultipleRewards, ...
    HasFirstLick);

end

