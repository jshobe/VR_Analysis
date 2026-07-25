function [fileList, basePath, cfg] = prompt_circular_split_curve_inputs(cfg)

settingsFile = fullfile(tempdir, 'lastVRFolder_intervalCueAnalysis.mat');

if exist(settingsFile, 'file')
    S = load(settingsFile, 'lastFolder');
    if isfield(S, 'lastFolder') && exist(S.lastFolder, 'dir')
        startFolder = S.lastFolder;
    else
        startFolder = pwd;
    end
else
    startFolder = pwd;
end

[fileList, basePath] = uigetfile(fullfile(startFolder, '*.txt'), ...
    'Select newest-format VR session files', 'MultiSelect', 'on');

if isequal(fileList,0)
    error('No file selected.');
end

if ischar(fileList)
    fileList = {fileList};
end

lastFolder = basePath; %#ok<NASGU>
save(settingsFile, 'lastFolder');

[cfg.lapMode, cfg.lapPct, cfg.lapStartPct, cfg.lapEndPct, cfg.lapLabel] = prompt_lap_selection();
[cfg.lickNearRewardEnabled, cfg.lickNearRewardWindow_deg] = prompt_lick_window();
[cfg.summaryMethodName, cfg.summaryFcn] = prompt_summary_method();

end