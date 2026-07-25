function PreprocessSingleRewardSessions()
% PREPROCESSSINGLEREWARDSESSIONS
% Optional batch driver. The main analysis also preprocesses automatically
% whenever a cache is missing, stale, or made by an older preprocessor.

cfg = get_single_reward_config();

if ~isfield(cfg, 'positionPlateauTolerance_cm')
    cfg.positionPlateauTolerance_cm = 1e-9;
end
if ~isfield(cfg, 'processedSessionSubfolder')
    cfg.processedSessionSubfolder = 'ProcessedSessions';
end

[file, path] = uigetfile('*.txt', ...
    'Select raw VR session file(s) to preprocess', ...
    'MultiSelect', 'on');

if isequal(file, 0)
    error('No file selected.');
end

if ischar(file)
    file = {file};
end

for k = 1:numel(file)
    txtFile = fullfile(path, file{k});
    preprocess_single_reward_session(txtFile, cfg);
end

fprintf('Finished preprocessing %d session file(s).\n', numel(file));

end
