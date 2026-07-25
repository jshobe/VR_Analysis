function [Session, processedPath, status] = ...
    load_or_preprocess_single_reward_session(txtFile, cfg)
% LOAD_OR_PREPROCESS_SINGLE_REWARD_SESSION
% Loads a valid processed-session cache or rebuilds it when missing/stale.

if nargin < 2 || isempty(cfg)
    cfg = get_single_reward_config();
end

if ~isfield(cfg, 'processedSessionSubfolder') || ...
        isempty(cfg.processedSessionSubfolder)
    cfg.processedSessionSubfolder = 'ProcessedSessions';
end

if ~isfield(cfg, 'positionPlateauTolerance_cm') || ...
        isempty(cfg.positionPlateauTolerance_cm)
    cfg.positionPlateauTolerance_cm = 1e-9;
end

if ~isfield(cfg, 'forcePreprocess')
    cfg.forcePreprocess = false;
end

if ~isfield(cfg, 'verifyProcessedSourceHash')
    cfg.verifyProcessedSourceHash = true;
end

txtFile = char(txtFile);
[rawFolder, rawBase] = fileparts(txtFile);
processedFolder = fullfile(rawFolder, cfg.processedSessionSubfolder);
processedPath = fullfile(processedFolder, [rawBase '_processed.mat']);

status = struct();
status.action = '';
status.reasons = {};

if cfg.forcePreprocess
    status.reasons{end + 1} = 'cfg.forcePreprocess is true';
elseif ~isfile(processedPath)
    status.reasons{end + 1} = 'processed cache is missing';
else
    try
        loaded = load(processedPath, 'Session');
        if ~isfield(loaded, 'Session')
            status.reasons{end + 1} = 'MAT file does not contain Session';
        else
            Session = loaded.Session;
            status.reasons = validate_cache(Session, txtFile, cfg);
        end
    catch ME
        status.reasons{end + 1} = ...
            ['processed cache could not be read: ' ME.message];
    end
end

if isempty(status.reasons)
    status.action = 'loaded_valid_cache';
    fprintf('Loaded valid processed session: %s\n', processedPath);
    return
end

[Session, processedPath] = preprocess_single_reward_session( ...
    txtFile, cfg, processedPath);
status.action = 'rebuilt_cache';

fprintf('Processed cache rebuilt because:\n');
for k = 1:numel(status.reasons)
    fprintf('  - %s\n', status.reasons{k});
end

end

function reasons = validate_cache(Session, txtFile, cfg)
reasons = {};
expectedVersion = single_reward_preprocessor_version();

if ~isstruct(Session)
    reasons{end + 1} = 'Session is not a structure';
    return
end

requiredTop = {'Samples', 'Kinematics', 'Events', 'Audit'};
for k = 1:numel(requiredTop)
    if ~isfield(Session, requiredTop{k})
        reasons{end + 1} = ['Session.' requiredTop{k} ' is missing'];
    end
end
if ~isempty(reasons)
    return
end

A = Session.Audit;

if ~isfield(A, 'passed') || ~A.passed
    reasons{end + 1} = 'stored preprocessing audit did not pass';
end

if ~isfield(A, 'kinematicCleaningApplied') || ...
        ~A.kinematicCleaningApplied
    reasons{end + 1} = 'kinematic cleaning was not recorded';
end

if ~isfield(A, 'preprocessorVersion') || ...
        ~strcmp(A.preprocessorVersion, expectedVersion)
    reasons{end + 1} = 'preprocessor version is outdated';
end

if ~isfield(A, 'track_cm') || A.track_cm ~= cfg.track_cm
    reasons{end + 1} = 'track length differs from current configuration';
end

if ~isfield(A, 'positionPlateauTolerance_cm') || ...
        A.positionPlateauTolerance_cm ~= cfg.positionPlateauTolerance_cm
    reasons{end + 1} = ...
        'position-plateau tolerance differs from current configuration';
end

source = get_file_fingerprint(txtFile, cfg.verifyProcessedSourceHash);

if ~isfield(A, 'sourceBytes') || A.sourceBytes ~= source.bytes
    reasons{end + 1} = 'raw source byte count changed';
end

if cfg.verifyProcessedSourceHash
    if ~isfield(A, 'sourceSHA256') || isempty(A.sourceSHA256) || ...
            ~strcmpi(A.sourceSHA256, source.sha256)
        reasons{end + 1} = 'raw source SHA-256 changed';
    end
end

if ~isfield(A, 'nRawRows') || ...
        numel(Session.Samples.t) ~= A.nRawRows
    reasons{end + 1} = 'cached sample-row count is inconsistent';
end

if ~isfield(Session.Kinematics, 'original_row') || ...
        ~isfield(A, 'nKinematicRows') || ...
        numel(Session.Kinematics.original_row) ~= A.nKinematicRows
    reasons{end + 1} = 'cached kinematic-row count is inconsistent';
end

end
