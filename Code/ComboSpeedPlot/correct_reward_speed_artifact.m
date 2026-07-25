function [speedCorrected, audit] = correct_reward_speed_artifact( ...
    t, reward, speedInput, samplesAfterOnset)
% CORRECT_REWARD_SPEED_ARTIFACT
% Removes the speed estimate at each reward-onset sample and a configurable
% number of immediately following samples, then linearly interpolates only
% those targeted samples.
%
% This preserves the validated correction used in the earlier circular
% analysis while avoiding an unintended side effect of the original code:
% unrelated NaN speed samples are left unchanged.
%
% Inputs
%   t                   time vector
%   reward              reward-delivery vector; reward > 0 is treated as on
%   speedInput          speed estimate aligned sample-by-sample with t
%   samplesAfterOnset   number of samples after onset to replace (default 1)
%
% Outputs
%   speedCorrected      corrected speed vector, same shape as speedInput
%   audit               structure containing indices, values, and QC checks

if nargin < 4 || isempty(samplesAfterOnset)
    samplesAfterOnset = 1;
end

if ~isscalar(samplesAfterOnset) || ~isfinite(samplesAfterOnset) || ...
        samplesAfterOnset < 0 || samplesAfterOnset ~= round(samplesAfterOnset)
    error('samplesAfterOnset must be a nonnegative integer scalar.');
end

originalSize = size(speedInput);

t = t(:);
reward = reward(:);
speedInputColumn = speedInput(:);

n = numel(t);

if numel(reward) ~= n || numel(speedInputColumn) ~= n
    error('t, reward, and speedInput must contain the same number of samples.');
end

if any(~isfinite(t))
    error('t must contain only finite values.');
end

rewardLogical = reward > 0;
rewardOnsetIdx = find(diff([false; rewardLogical]) == 1);

offsets = 0:samplesAfterOnset;
correctedIdx = [];

for k = 1:numel(rewardOnsetIdx)
    idx = rewardOnsetIdx(k) + offsets;
    idx = idx(idx >= 1 & idx <= n);
    correctedIdx = [correctedIdx; idx(:)]; %#ok<AGROW>
end

correctedIdx = unique(correctedIdx);

speedCorrectedColumn = speedInputColumn;
valuesBefore = speedInputColumn(correctedIdx);

if ~isempty(correctedIdx)
    speedMasked = speedInputColumn;
    speedMasked(correctedIdx) = NaN;

    good = isfinite(t) & isfinite(speedMasked);

    if sum(good) >= 2
        tGood = t(good);
        speedGood = speedMasked(good);

        % interp1 requires unique, increasing x values. Keep the last speed
        % value for any duplicated timestamp, then sort by time.
        [tGood, sortIdx] = sort(tGood);
        speedGood = speedGood(sortIdx);
        [tGood, uniqueIdx] = unique(tGood, 'last');
        speedGood = speedGood(uniqueIdx);

        if numel(tGood) >= 2
            replacement = interp1( ...
                tGood, ...
                speedGood, ...
                t(correctedIdx), ...
                'linear', ...
                NaN);

            % Deliberately replace only reward-targeted samples. Other NaNs
            % remain untouched.
            speedCorrectedColumn(correctedIdx) = replacement;
        else
            speedCorrectedColumn(correctedIdx) = NaN;
        end
    else
        speedCorrectedColumn(correctedIdx) = NaN;
    end
end

valuesAfter = speedCorrectedColumn(correctedIdx);

changedMask = values_changed(speedInputColumn, speedCorrectedColumn);
targetMask = false(n, 1);
targetMask(correctedIdx) = true;
nonTargetChangedIdx = find(changedMask & ~targetMask);

finiteBefore = valuesBefore(isfinite(valuesBefore));
finiteAfter = valuesAfter(isfinite(valuesAfter));

audit = struct();
audit.nSamples = n;
audit.samplesAfterOnset = samplesAfterOnset;
audit.rewardOnsetIdx = rewardOnsetIdx;
audit.nRewardOnsets = numel(rewardOnsetIdx);
audit.correctedIdx = correctedIdx;
audit.nTargetSamples = numel(correctedIdx);
audit.valuesBefore = valuesBefore;
audit.valuesAfter = valuesAfter;
audit.nInterpolated = sum(isfinite(valuesAfter));
audit.nRemainingNaN = sum(~isfinite(valuesAfter));
audit.nonTargetChangedIdx = nonTargetChangedIdx;
audit.nonTargetChangedCount = numel(nonTargetChangedIdx);
audit.onlyTargetSamplesChanged = isempty(nonTargetChangedIdx);
audit.timestampsStrictlyIncreasing = all(diff(t) > 0);
audit.timestampsNondecreasing = all(diff(t) >= 0);

audit.maxBefore = finite_stat(finiteBefore, @max);
audit.maxAfter = finite_stat(finiteAfter, @max);
audit.medianBefore = finite_stat(finiteBefore, @median);
audit.medianAfter = finite_stat(finiteAfter, @median);

audit.passed = audit.onlyTargetSamplesChanged && ...
    all(correctedIdx >= 1 & correctedIdx <= n);

speedCorrected = reshape(speedCorrectedColumn, originalSize);

end

function changed = values_changed(a, b)
% Exact equality is appropriate because values outside target indices are
% copied without arithmetic. NaN-to-NaN is treated as unchanged.
changed = false(size(a));

bothNaN = isnan(a) & isnan(b);
bothFiniteEqual = isfinite(a) & isfinite(b) & (a == b);
bothSameInf = isinf(a) & isinf(b) & (sign(a) == sign(b));

changed(~(bothNaN | bothFiniteEqual | bothSameInf)) = true;
end

function value = finite_stat(x, fn)
if isempty(x)
    value = NaN;
else
    value = fn(x);
end
end
