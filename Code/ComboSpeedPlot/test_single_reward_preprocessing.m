function test_single_reward_preprocessing()
% TEST_SINGLE_REWARD_PREPROCESSING Synthetic regression test.
% Verifies that duplicate event rows are retained as events but cannot
% change speed at genuine position-update rows.

cfg = struct();
cfg.track_cm = 480;
cfg.positionPlateauTolerance_cm = 1e-9;

% Baseline kinematic sequence.
D0 = struct();
D0.t = (0:0.1:0.7)';
D0.pos_deg = [0; 1.5; 3; 4.5; 6; 7.5; 9; 10.5];
D0.reward = zeros(8, 1);
D0.lick = zeros(8, 1);
D0.brake = zeros(8, 1);

% Expanded event-driven sequence. Rows 4, 7, and 10 repeat position.
D = struct();
D.t = [0; 0.1; 0.2; 0.205; 0.3; 0.4; 0.405; 0.5; 0.6; 0.605; 0.7];
D.pos_deg = [0; 1.5; 3; 3; 4.5; 6; 6; 7.5; 9; 9; 10.5];
D.reward = [0; 0; 0; 1; 0; 0; 0; 0; 0; 0; 0];
D.lick =   [0; 0; 0; 0; 0; 0; 1; 0; 0; 1; 0];
D.brake = zeros(size(D.t));

source = struct('name', 'synthetic.txt', 'fullPath', 'synthetic.txt', ...
    'bytes', NaN, 'modifiedDatenum', NaN, 'modifiedText', '', ...
    'sha256', 'synthetic');

S0 = build_preprocessed_single_reward_session(D0, source, cfg);
S = build_preprocessed_single_reward_session(D, source, cfg);

assert(S.Audit.passed, 'Processed-session audit failed.');
assert(S.Audit.nRawRows == 11, 'Unexpected raw-row count.');
assert(S.Audit.nKinematicRows == 8, 'Unexpected kinematic-row count.');
assert(S.Audit.nRedundantPositionRows == 3, ...
    'Unexpected redundant-row count.');
assert(sum(S.Samples.reward > 0) == 1, 'Reward event was not preserved.');
assert(sum(S.Samples.lick > 0) == 2, 'Lick events were not preserved.');

[speed0, speedK0] = compute_session_window_speed(S0, 5);
[speed, speedK, speedAudit] = compute_session_window_speed(S, 5);

assert(speedAudit.passed, 'Shared speed audit failed.');
assert(isequaln(speedK, speedK0), ...
    'Duplicate event rows changed kinematic speed values.');
assert(all(isnan(speed(S.Samples.is_redundant_position_row))), ...
    'Redundant rows received finite speed values.');
assert(isequaln(speed(S.Kinematics.original_row), speed0), ...
    'Mapped speed differs from baseline kinematic speed.');

fprintf('test_single_reward_preprocessing: PASSED\n');

end
