function test_lap_group_ranges()
% TEST_LAP_GROUP_RANGES
% Confirms the requested 34/33/33 partition and truncation behavior.

cfg.lapGroupSizes = [34 33 33];

[s, e, n] = get_lap_group_ranges(100, cfg);
assert(isequal(s, [1 35 68]));
assert(isequal(e, [34 67 100]));
assert(isequal(n, [34 33 33]));

[s, e, n] = get_lap_group_ranges(80, cfg);
assert(isequal(s, [1 35 68]));
assert(isequal(e, [34 67 80]));
assert(isequal(n, [34 33 13]));

fprintf('test_lap_group_ranges passed.\n');

end
