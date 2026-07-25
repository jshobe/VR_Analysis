clear; clc;
% RUN_REWARD_ARTIFACT_AUDIT
% Select one or more raw VR session files and compare uncorrected versus
% corrected window-based speed at reward onsets. This does not alter files.
%
% Required helpers on the MATLAB path:
%   get_single_reward_config.m
%   read_vr_session_txt.m
%   compute_window_speed.m
%   correct_reward_speed_artifact.m
%   detect_laps_from_wrap.m

cfg = get_single_reward_config();

if ~isfield(cfg, 'rewardArtifactSamplesAfterOnset')
    cfg.rewardArtifactSamplesAfterOnset = 1;
end

[file, path] = uigetfile('*.txt', ...
    'Select raw VR session file(s) for reward-artifact audit', ...
    'MultiSelect', 'on');

if isequal(file, 0)
    error('No file selected.');
end

if ischar(file)
    file = {file};
end

nFiles = numel(file);
rows = cell(nFiles, 13);

for f = 1:nFiles
    fname = fullfile(path, file{f});
    D = read_vr_session_txt(fname);

    pos_cm_unwrapped = ...
        rad2deg(unwrap(deg2rad(D.pos_deg))) / 360 * cfg.track_cm;

    speedBefore = compute_window_speed( ...
        D.t, pos_cm_unwrapped, cfg.speedWindow_cm_forPlot);

    [speedAfter, A] = correct_reward_speed_artifact( ...
        D.t, D.reward, speedBefore, cfg.rewardArtifactSamplesAfterOnset);

    lapStartBefore = detect_laps_from_wrap(D.pos_deg);
    lapStartAfter = detect_laps_from_wrap(D.pos_deg); % position is unchanged

    finiteBefore = A.valuesBefore(isfinite(A.valuesBefore));
    finiteAfter = A.valuesAfter(isfinite(A.valuesAfter));

    maxBefore = local_stat(finiteBefore, @max);
    maxAfter = local_stat(finiteAfter, @max);
    medianBefore = local_stat(finiteBefore, @median);
    medianAfter = local_stat(finiteAfter, @median);

    rows(f, :) = { ...
        file{f}, ...
        numel(D.t), ...
        A.nRewardOnsets, ...
        A.nTargetSamples, ...
        A.nInterpolated, ...
        A.nRemainingNaN, ...
        A.nonTargetChangedCount, ...
        maxBefore, ...
        maxAfter, ...
        medianBefore, ...
        medianAfter, ...
        numel(lapStartBefore) - 1, ...
        isequal(lapStartBefore, lapStartAfter) && A.passed};
end

AuditTable = cell2table(rows, 'VariableNames', { ...
    'File', ...
    'Samples', ...
    'RewardOnsets', ...
    'TargetSamples', ...
    'InterpolatedSamples', ...
    'TargetSamplesLeftNaN', ...
    'NonTargetSamplesChanged', ...
    'TargetMaxBefore_cm_s', ...
    'TargetMaxAfter_cm_s', ...
    'TargetMedianBefore_cm_s', ...
    'TargetMedianAfter_cm_s', ...
    'CompleteLaps', ...
    'AuditPassed'});

disp(AuditTable);

if any(AuditTable.NonTargetSamplesChanged ~= 0)
    error('Audit failed: at least one non-target speed sample changed.');
end

if any(~AuditTable.AuditPassed)
    error('Audit failed for at least one selected file.');
end

fprintf('All selected files passed reward-artifact invariants.\n');

function value = local_stat(x, fn)
if isempty(x)
    value = NaN;
else
    value = fn(x);
end
end
