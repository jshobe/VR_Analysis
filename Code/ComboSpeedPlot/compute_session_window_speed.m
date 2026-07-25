function [speedFull_cm_s, speedKinematic_cm_s, audit] = ...
    compute_session_window_speed(Session, speedWindow_cm)
% COMPUTE_SESSION_WINDOW_SPEED
% Shared speed helper for every analysis using processed single-reward data.
% Speed is computed only from Session.Kinematics and mapped back to the
% original sample rows. Event-only/redundant rows remain NaN.

if ~isstruct(Session) || ~isfield(Session, 'Samples') || ...
        ~isfield(Session, 'Kinematics') || ~isfield(Session, 'Audit')
    error('Input is not a canonical processed single-reward Session.');
end

if ~Session.Audit.passed || ~Session.Audit.kinematicCleaningApplied
    error('Processed-session audit is missing or failed.');
end

if ~strcmp(Session.Audit.preprocessorVersion, ...
        single_reward_preprocessor_version())
    error('Processed session was made by an outdated preprocessor.');
end

K = Session.Kinematics;
nSamples = numel(Session.Samples.t);

requiredK = {'original_row', 'time_s', 'position_cm_unwrapped'};
for k = 1:numel(requiredK)
    if ~isfield(K, requiredK{k})
        error('Session.Kinematics.%s is missing.', requiredK{k});
    end
end

originalRows = K.original_row(:);
time_s = K.time_s(:);
pos_cm = K.position_cm_unwrapped(:);

if numel(originalRows) ~= numel(time_s) || numel(time_s) ~= numel(pos_cm)
    error('Kinematic fields have inconsistent lengths.');
end

if any(originalRows < 1) || any(originalRows > nSamples) || ...
        any(diff(originalRows) <= 0)
    error('Kinematic original-row mapping is invalid.');
end

speedKinematic_cm_s = compute_window_speed(time_s, pos_cm, speedWindow_cm);
speedFull_cm_s = nan(nSamples, 1);
speedFull_cm_s(originalRows) = speedKinematic_cm_s;

redundantMask = Session.Samples.is_redundant_position_row(:);
duplicateRowsHaveNaNSpeed = all(isnan(speedFull_cm_s(redundantMask)));
nonMappedRowsHaveNaNSpeed = all(isnan(speedFull_cm_s(setdiff((1:nSamples)', originalRows))));

finiteTimes = time_s(isfinite(time_s));
if numel(finiteTimes) > 1
    timestampsStrictlyIncreasing = all(diff(finiteTimes) > 0);
else
    timestampsStrictlyIncreasing = true;
end

audit = struct();
audit.preprocessorVersion = Session.Audit.preprocessorVersion;
audit.speedWindow_cm = speedWindow_cm;
audit.nSampleRows = nSamples;
audit.nKinematicRows = numel(originalRows);
audit.nFiniteKinematicSpeeds = sum(isfinite(speedKinematic_cm_s));
audit.duplicateRowsHaveNaNSpeed = duplicateRowsHaveNaNSpeed;
audit.nonMappedRowsHaveNaNSpeed = nonMappedRowsHaveNaNSpeed;
audit.timestampsStrictlyIncreasing = timestampsStrictlyIncreasing;
audit.passed = duplicateRowsHaveNaNSpeed && ...
    nonMappedRowsHaveNaNSpeed && timestampsStrictlyIncreasing;

if ~audit.passed
    error('Shared session-speed audit failed.');
end

end
