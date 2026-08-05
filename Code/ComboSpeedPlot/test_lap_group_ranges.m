function test_lap_group_ranges()
% TEST_LAP_GROUP_RANGES
% Confirms balanced three-way splits and original-lap-number labels.

cfg = struct();

[s, e, n, labels] = get_lap_group_ranges(100, cfg);
assert(isequal(s, [1 35 68]));
assert(isequal(e, [34 67 100]));
assert(isequal(n, [34 33 33]));
assert(isequal(labels, {'Laps 1-34'; 'Laps 35-67'; 'Laps 68-100'}));

[s, e, n] = get_lap_group_ranges(80, cfg);
assert(isequal(s, [1 28 55]));
assert(isequal(e, [27 54 80]));
assert(isequal(n, [27 27 26]));

[~, ~, n] = get_lap_group_ranges(120, cfg);
assert(isequal(n, [40 40 40]));

[~, ~, n] = get_lap_group_ranges(150, cfg);
assert(isequal(n, [50 50 50]));

customLaps = 51:100;
[s, e, n, labels] = get_lap_group_ranges(customLaps, cfg);
assert(isequal(s, [1 18 35]));
assert(isequal(e, [17 34 50]));
assert(isequal(n, [17 17 16]));
assert(isequal(labels, ...
    {'Laps 51-67'; 'Laps 68-84'; 'Laps 85-100'}));

cfg.smoothMeanSpeedBins = 1;
cfg.smoothAccelerationBins = 1;
cfg.accelerationGroupColors = zeros(3, 3);
cfg.removeAccelerationOutliers = false;

P.trialNums = customLaps(:);
P.speedMat = repmat(customLaps(:), 1, 2);
P.accelMat = P.speedMat;

speedGroups = compute_speed_lap_group_curves(P, cfg);
accelerationGroups = compute_acceleration_lap_group_curves(P, cfg);

assert(isequal(speedGroups.labels, labels));
assert(isequal(accelerationGroups.labels, labels));

fprintf('test_lap_group_ranges passed.\n');

end
