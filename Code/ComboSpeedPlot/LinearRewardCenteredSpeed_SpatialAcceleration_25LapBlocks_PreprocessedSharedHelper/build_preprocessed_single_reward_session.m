function Session = build_preprocessed_single_reward_session(D, source, cfg)
% BUILD_PREPROCESSED_SINGLE_REWARD_SESSION
% Converts the raw event-driven VR log into a canonical processed session.
%
% The complete raw-aligned sample stream is retained in Session.Samples.
% Session.Kinematics contains one row per genuine position update: the first
% row of each consecutive constant-position plateau. Reward and lick event
% rows remain available in Session.Samples and Session.Events but cannot be
% used as independent kinematic samples.

requiredFields = {'t', 'pos_deg', 'reward', 'lick'};
for k = 1:numel(requiredFields)
    if ~isfield(D, requiredFields{k})
        error('Raw session is missing required field D.%s.', requiredFields{k});
    end
end

if ~isfield(cfg, 'track_cm') || ~isscalar(cfg.track_cm) || ...
        ~isfinite(cfg.track_cm) || cfg.track_cm <= 0
    error('cfg.track_cm must be a positive finite scalar.');
end

if ~isfield(cfg, 'positionPlateauTolerance_cm') || ...
        isempty(cfg.positionPlateauTolerance_cm)
    cfg.positionPlateauTolerance_cm = 1e-9;
end

tol = cfg.positionPlateauTolerance_cm;
if ~isscalar(tol) || ~isfinite(tol) || tol < 0
    error('cfg.positionPlateauTolerance_cm must be nonnegative and finite.');
end

% Normalize required aligned vectors to columns.
D.t = D.t(:);
D.pos_deg = D.pos_deg(:);
D.reward = D.reward(:);
D.lick = D.lick(:);

nRows = numel(D.t);
if numel(D.pos_deg) ~= nRows || numel(D.reward) ~= nRows || ...
        numel(D.lick) ~= nRows
    error('Required raw-session fields must have the same number of rows.');
end

if isfield(D, 'brake')
    D.brake = D.brake(:);
    if numel(D.brake) ~= nRows
        error('D.brake must have the same number of rows as D.t.');
    end
else
    D.brake = zeros(nRows, 1);
end

% Preserve all raw-aligned fields while adding canonical spatial variables.
D.pos_cm_wrapped = mod((D.pos_deg / 360) * cfg.track_cm, cfg.track_cm);
D.pos_cm_unwrapped = ...
    rad2deg(unwrap(deg2rad(D.pos_deg))) / 360 * cfg.track_cm;

finiteMask = isfinite(D.t) & isfinite(D.pos_cm_unwrapped);
keepMask = false(nRows, 1);
redundantMask = false(nRows, 1);

havePrevious = false;
previousPosition = NaN;

for i = 1:nRows
    if ~finiteMask(i)
        havePrevious = false;
        previousPosition = NaN;
        continue
    end

    if ~havePrevious || ...
            abs(D.pos_cm_unwrapped(i) - previousPosition) > tol
        keepMask(i) = true;
        previousPosition = D.pos_cm_unwrapped(i);
        havePrevious = true;
    else
        redundantMask(i) = true;
    end
end

D.is_kinematic_row = keepMask;
D.is_redundant_position_row = redundantMask;

kinematicRows = find(keepMask);

Kinematics = struct();
Kinematics.original_row = kinematicRows;
Kinematics.time_s = D.t(keepMask);
Kinematics.position_deg = D.pos_deg(keepMask);
Kinematics.position_cm_wrapped = D.pos_cm_wrapped(keepMask);
Kinematics.position_cm_unwrapped = D.pos_cm_unwrapped(keepMask);

% Explicit events plus redundant event/logging rows form a convenient event
% stream. The complete row set remains preserved in Session.Samples.
rewardMask = isfinite(D.reward) & D.reward > 0;
lickMask = isfinite(D.lick) & D.lick > 0;
brakeMask = isfinite(D.brake) & D.brake > 0;
eventMask = rewardMask | lickMask | brakeMask | redundantMask;
eventRows = find(eventMask);

lastKinematicOriginalRow = zeros(nRows, 1);
lastRow = 0;
for i = 1:nRows
    if keepMask(i)
        lastRow = i;
    end
    lastKinematicOriginalRow(i) = lastRow;
end

firstKinematicRow = find(keepMask, 1, 'first');
if isempty(firstKinematicRow)
    error('No finite kinematic position rows were found.');
end
lastKinematicOriginalRow(lastKinematicOriginalRow == 0) = firstKinematicRow;

Events = struct();
Events.original_row = eventRows;
Events.time_s = D.t(eventMask);
Events.position_deg = D.pos_deg(eventMask);
Events.position_cm_wrapped = D.pos_cm_wrapped(eventMask);
Events.reward = D.reward(eventMask);
Events.lick = D.lick(eventMask);
Events.brake = D.brake(eventMask);
Events.is_redundant_position_row = redundantMask(eventMask);
Events.nearest_preceding_kinematic_original_row = ...
    lastKinematicOriginalRow(eventMask);

rewardOnsetMask = false(nRows, 1);
rewardOnsetMask(find(diff([false; rewardMask]) == 1)) = true;
Events.is_reward_onset = rewardOnsetMask(eventMask);

finiteTimes = D.t(isfinite(D.t));
if numel(finiteTimes) > 1
    timestampsStrictlyIncreasing = all(diff(finiteTimes) > 0);
else
    timestampsStrictlyIncreasing = true;
end

wrapCount = sum(diff(D.pos_deg(finiteMask)) < -180);

Audit = struct();
Audit.schemaVersion = 'single_reward_processed_session_v1';
Audit.preprocessorVersion = single_reward_preprocessor_version();
Audit.created = datestr(now, 30);
Audit.kinematicCleaningApplied = true;
Audit.track_cm = cfg.track_cm;
Audit.positionPlateauTolerance_cm = tol;
Audit.nRawRows = nRows;
Audit.nFinitePositionRows = sum(finiteMask);
Audit.nKinematicRows = sum(keepMask);
Audit.nRedundantPositionRows = sum(redundantMask);
Audit.redundantFraction = sum(redundantMask) / max(sum(finiteMask), 1);
Audit.nEventRows = sum(eventMask);
Audit.nRewardRows = sum(rewardMask);
Audit.nRewardOnsets = sum(rewardOnsetMask);
Audit.nLickRows = sum(lickMask);
Audit.nBrakeRows = sum(brakeMask);
Audit.nPositionWraps = wrapCount;
Audit.timestampsStrictlyIncreasing = timestampsStrictlyIncreasing;
Audit.rowAccountingPassed = ...
    sum(keepMask) + sum(redundantMask) == sum(finiteMask);
Audit.eventsPreserved = ...
    isequal(Events.reward, D.reward(eventMask)) && ...
    isequal(Events.lick, D.lick(eventMask));
Audit.passed = timestampsStrictlyIncreasing && ...
    Audit.rowAccountingPassed && Audit.eventsPreserved;

if isfield(source, 'name'), Audit.sourceFileName = source.name; else, Audit.sourceFileName = ''; end
if isfield(source, 'fullPath'), Audit.sourceFullPath = source.fullPath; else, Audit.sourceFullPath = ''; end
if isfield(source, 'bytes'), Audit.sourceBytes = source.bytes; else, Audit.sourceBytes = NaN; end
if isfield(source, 'modifiedDatenum'), Audit.sourceModifiedDatenum = source.modifiedDatenum; else, Audit.sourceModifiedDatenum = NaN; end
if isfield(source, 'modifiedText'), Audit.sourceModifiedText = source.modifiedText; else, Audit.sourceModifiedText = ''; end
if isfield(source, 'sha256'), Audit.sourceSHA256 = source.sha256; else, Audit.sourceSHA256 = ''; end

if ~Audit.passed
    error('Preprocessing QC failed for source file %s.', Audit.sourceFileName);
end

Session = struct();
Session.SchemaVersion = Audit.schemaVersion;
Session.PreprocessorVersion = Audit.preprocessorVersion;
Session.Source = source;
Session.Samples = D;
Session.Kinematics = Kinematics;
Session.Events = Events;
Session.Audit = Audit;

end
