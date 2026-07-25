function run_single_reward_preprocessing_audit(txtFile)
% RUN_SINGLE_REWARD_PREPROCESSING_AUDIT
% Rebuilds one processed session, verifies the exact saved cache, and checks
% the shared speed helper. Supply txtFile or select one interactively.

if nargin < 1 || isempty(txtFile)
    [file, path] = uigetfile('*.txt', 'Select raw VR session to audit');
    if isequal(file, 0)
        error('No file selected.');
    end
    txtFile = fullfile(path, file);
end

cfg = get_single_reward_config();
cfg.forcePreprocess = true;
if ~isfield(cfg, 'positionPlateauTolerance_cm')
    cfg.positionPlateauTolerance_cm = 1e-9;
end
if ~isfield(cfg, 'processedSessionSubfolder')
    cfg.processedSessionSubfolder = 'ProcessedSessions';
end
if ~isfield(cfg, 'verifyProcessedSourceHash')
    cfg.verifyProcessedSourceHash = true;
end

[Session, processedPath, status] = ...
    load_or_preprocess_single_reward_session(txtFile, cfg);

[~, ~, speedAudit] = compute_session_window_speed( ...
    Session, cfg.speedWindow_cm_forPlot);

% Re-open without force to confirm that the delivered cache is accepted.
cfg.forcePreprocess = false;
[Session2, processedPath2, status2] = ...
    load_or_preprocess_single_reward_session(txtFile, cfg);

assert(strcmp(processedPath, processedPath2), ...
    'Cache path changed between audit passes.');
assert(strcmp(status.action, 'rebuilt_cache'), ...
    'Forced audit did not rebuild the cache.');
assert(strcmp(status2.action, 'loaded_valid_cache'), ...
    'Fresh cache was not accepted on the second pass.');
assert(strcmpi(Session.Audit.sourceSHA256, ...
    Session2.Audit.sourceSHA256), 'Source hash changed between passes.');
assert(speedAudit.passed, 'Shared speed audit failed.');

A = Session.Audit;
fprintf('\nPREPROCESSING AUDIT PASSED\n');
fprintf('Source: %s\n', A.sourceFullPath);
fprintf('Processed: %s\n', processedPath);
fprintf('Version: %s\n', A.preprocessorVersion);
fprintf('Raw rows: %d\n', A.nRawRows);
fprintf('Kinematic rows: %d\n', A.nKinematicRows);
fprintf('Redundant position rows: %d (%.2f%%)\n', ...
    A.nRedundantPositionRows, 100 * A.redundantFraction);
fprintf('Reward rows/onsets: %d / %d\n', ...
    A.nRewardRows, A.nRewardOnsets);
fprintf('Lick rows: %d\n', A.nLickRows);
fprintf('Position wraps: %d\n', A.nPositionWraps);
fprintf('Finite speed values: %d\n', ...
    speedAudit.nFiniteKinematicSpeeds);
fprintf('Source SHA-256: %s\n', A.sourceSHA256);

end
