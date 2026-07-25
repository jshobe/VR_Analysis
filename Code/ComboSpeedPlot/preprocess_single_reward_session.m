function [Session, processedPath] = preprocess_single_reward_session( ...
    txtFile, cfg, processedPath)
% PREPROCESS_SINGLE_REWARD_SESSION
% Reads one raw VR text file, builds a canonical processed session, runs QC,
% and saves it atomically as a versioned MAT file.

if nargin < 2 || isempty(cfg)
    cfg = get_single_reward_config();
end

if ~isfield(cfg, 'positionPlateauTolerance_cm') || ...
        isempty(cfg.positionPlateauTolerance_cm)
    cfg.positionPlateauTolerance_cm = 1e-9;
end

if ~isfield(cfg, 'processedSessionSubfolder') || ...
        isempty(cfg.processedSessionSubfolder)
    cfg.processedSessionSubfolder = 'ProcessedSessions';
end

txtFile = char(txtFile);
if ~isfile(txtFile)
    error('Raw text file not found: %s', txtFile);
end

[rawFolder, rawBase] = fileparts(txtFile);

if nargin < 3 || isempty(processedPath)
    processedFolder = fullfile(rawFolder, cfg.processedSessionSubfolder);
    processedPath = fullfile(processedFolder, [rawBase '_processed.mat']);
else
    processedPath = char(processedPath);
    processedFolder = fileparts(processedPath);
end

if ~isfolder(processedFolder)
    [ok, msg] = mkdir(processedFolder);
    if ~ok
        error('Could not create processed-session folder: %s', msg);
    end
end

source = get_file_fingerprint(txtFile, true);
D = read_vr_session_txt(txtFile);
Session = build_preprocessed_single_reward_session(D, source, cfg);

% Atomic save prevents a partial cache file if MATLAB is interrupted.
temporaryPath = [tempname(processedFolder) '.mat'];
cleanupObj = onCleanup(@() delete_if_present(temporaryPath)); %#ok<NASGU>

save(temporaryPath, 'Session', '-v7.3');
[ok, msg] = movefile(temporaryPath, processedPath, 'f');
if ~ok
    error('Could not finalize processed session: %s', msg);
end

% Reopen the exact delivered cache and verify its identity.
verify = load(processedPath, 'Session');
if ~isfield(verify, 'Session') || ...
        ~strcmp(verify.Session.PreprocessorVersion, ...
        single_reward_preprocessor_version()) || ...
        ~verify.Session.Audit.passed || ...
        ~strcmpi(verify.Session.Audit.sourceSHA256, source.sha256)
    error('Post-save verification failed for %s.', processedPath);
end

Session = verify.Session;

fprintf(['Preprocessed %s -> %s\n' ...
    '  raw rows: %d | kinematic rows: %d | redundant rows: %d (%.1f%%)\n'], ...
    source.name, processedPath, ...
    Session.Audit.nRawRows, ...
    Session.Audit.nKinematicRows, ...
    Session.Audit.nRedundantPositionRows, ...
    100 * Session.Audit.redundantFraction);

end

function delete_if_present(filePath)
if isfile(filePath)
    delete(filePath);
end
end
