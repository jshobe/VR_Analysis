function results = test_reward_speed_artifact_correction()
% TEST_REWARD_SPEED_ARTIFACT_CORRECTION
% Deterministic regression tests for correct_reward_speed_artifact.m.
%
% Run from the MATLAB command window:
%   results = test_reward_speed_artifact_correction();
%
% The function throws an error if any required invariant fails.

results = struct();

%% Test 1: two reward events, onset + next sample corrected
% Baseline speed is linear, so interpolation has an exact expected value.
t = (0:19)';
baseline = 20 + 2*t;
speed = baseline;
reward = zeros(size(t));
reward([6 14]) = 1;

speed([6 7 14 15]) = [500 450 600 550];

[corrected, audit] = correct_reward_speed_artifact(t, reward, speed, 1);
expectedIdx = [6; 7; 14; 15];

assert(isequal(audit.correctedIdx, expectedIdx), ...
    'Test 1 failed: incorrect target indices.');
assert(max(abs(corrected(expectedIdx) - baseline(expectedIdx))) < 1e-12, ...
    'Test 1 failed: interpolation did not recover expected values.');
assert(audit.nonTargetChangedCount == 0, ...
    'Test 1 failed: a non-target sample changed.');
assert(audit.passed, 'Test 1 failed: audit did not pass.');
results.twoRewardEvents = true;

%% Test 2: unrelated NaN remains NaN
speed2 = speed;
speed2(10) = NaN;
[corrected2, audit2] = correct_reward_speed_artifact(t, reward, speed2, 1);

assert(isnan(corrected2(10)), ...
    'Test 2 failed: unrelated NaN was filled.');
assert(audit2.nonTargetChangedCount == 0, ...
    'Test 2 failed: a non-target sample changed.');
results.unrelatedNaNPreserved = true;

%% Test 3: no reward means exact identity
reward3 = zeros(size(t));
[corrected3, audit3] = correct_reward_speed_artifact(t, reward3, speed2, 1);

assert(isequaln(corrected3, speed2), ...
    'Test 3 failed: no-reward input was changed.');
assert(audit3.nRewardOnsets == 0, ...
    'Test 3 failed: false reward onset detected.');
results.noRewardIdentity = true;

%% Test 4: final-sample reward stays NaN because extrapolation is disabled
reward4 = zeros(size(t));
reward4(end) = 1;
speed4 = baseline;
speed4(end) = 900;
[corrected4, audit4] = correct_reward_speed_artifact(t, reward4, speed4, 1);

assert(isnan(corrected4(end)), ...
    'Test 4 failed: boundary artifact should remain NaN.');
assert(audit4.nonTargetChangedCount == 0, ...
    'Test 4 failed: a non-target sample changed.');
results.boundaryNoExtrapolation = true;

%% Test 5: row-vector shape is preserved
t5 = t.';
reward5 = reward.';
speed5 = speed.';
[corrected5, ~] = correct_reward_speed_artifact(t5, reward5, speed5, 1);
assert(isequal(size(corrected5), size(speed5)), ...
    'Test 5 failed: input shape was not preserved.');
results.shapePreserved = true;

fprintf('All reward-artifact correction regression tests passed.\n');

end
