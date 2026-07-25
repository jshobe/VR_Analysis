clear; clc;

% Linear, reward-centered single-reward kinematics.
%
% For each selected session:
%   top:    lap-by-position speed heatmap
%   middle: overall speed +/- SEM with matching 20-lap speed curves
%   bottom: spatially derived signed acceleration in 20-lap blocks
%
% Spatial acceleration is calculated after speed is binned by position:
%   a = v * dv/dx
% A local quadratic fit supplies dv/dx within a fixed position window.
%
% Multiple-session behavior:
%   - files are sorted chronologically
%   - the first plotted session defines the "old reward location"
%   - later sessions with a shifted reward receive a green old-reward line
%   - all selected sessions use shared heatmap, speed, and acceleration scales
%
% A maximum of the first 100 complete laps is plotted and analyzed.

cfg = get_single_reward_config();

%% Analysis and display settings
% Number of consecutive spatial bins used for each local polynomial fit.
% Must be an odd integer. With 3 cm bins, 5 bins span about 15 cm.
if ~isfield(cfg, 'spatialAccelerationWindowBins')
    cfg.spatialAccelerationWindowBins = 5;
end

% Quadratic local fit. The first derivative at the center gives dv/dx.
if ~isfield(cfg, 'spatialAccelerationPolyOrder')
    cfg.spatialAccelerationPolyOrder = 2;
end

% Minimum finite speed bins required within the local fit window.
if ~isfield(cfg, 'spatialAccelerationMinPoints')
    cfg.spatialAccelerationMinPoints = 3;
end

if ~isfield(cfg, 'smoothAccelerationBins')
    cfg.smoothAccelerationBins = cfg.smoothMeanSpeedBins;
end

if ~isfield(cfg, 'useSharedSessionScales')
    cfg.useSharedSessionScales = true;
end

if ~isfield(cfg, 'maxLapsToPlot')
    cfg.maxLapsToPlot = 100;
end

% Prevent small reward-delivery jitter from being treated as a true shift.
if ~isfield(cfg, 'rewardShiftTolerance_deg')
    cfg.rewardShiftTolerance_deg = 5;
end

% Speed and acceleration curves use the same consecutive lap blocks.
if ~isfield(cfg, 'accelerationLapBlockSize')
    cfg.accelerationLapBlockSize = 20;
end

if ~isfield(cfg, 'showSpeedLapBlockCurves')
    cfg.showSpeedLapBlockCurves = true;
end

% Use a sequential colormap so early-to-late lap blocks are easy to follow.
nExpectedGroups = ceil(cfg.maxLapsToPlot / cfg.accelerationLapBlockSize);

if ~isfield(cfg, 'accelerationGroupColors') || ...
        size(cfg.accelerationGroupColors, 1) < nExpectedGroups
    cfg.accelerationGroupColors = parula(nExpectedGroups);
end

if ~isfield(cfg, 'accelerationGroupLineWidth')
    cfg.accelerationGroupLineWidth = 1.8;
end

if ~isfield(cfg, 'speedGroupLineWidth')
    cfg.speedGroupLineWidth = 1.4;
end

% SEM bands for every colored acceleration block can be visually crowded.
if ~isfield(cfg, 'showAccelerationGroupSEM')
    cfg.showAccelerationGroupSEM = false;
end

[file, path] = uigetfile('*.txt', ...
    'Select VR session file(s)', ...
    'MultiSelect', 'on');

if isequal(file, 0)
    error('No file selected.');
end

if ischar(file)
    file = {file};
end

%% Sort selected files chronologically
fileDates = NaT(numel(file), 1);

for k = 1:numel(file)
    tok = regexp(file{k}, '(\d{4}-\d{2}-\d{2})', ...
        'tokens', 'once');

    if ~isempty(tok)
        fileDates(k) = datetime(tok{1}, ...
            'InputFormat', 'yyyy-MM-dd');
    end
end

[~, sortIdx] = sort(fileDates);
file = file(sortIdx);

nFiles = numel(file);

%% First pass: process every session
Pall = cell(nFiles, 1);
mouseNames = cell(nFiles, 1);
sessionDates = cell(nFiles, 1);
keepFile = false(nFiles, 1);

for f = 1:nFiles

    fname = fullfile(path, file{f});

    [mouseName, sessionDate] = parse_mouse_date(file{f});
    mouseNames{f} = mouseName;
    sessionDates{f} = sessionDate;

    D = read_vr_session_txt(fname);

    D.pos_cm_wrapped = mod( ...
        (D.pos_deg / 360) * cfg.track_cm, ...
        cfg.track_cm);

    D.pos_cm_unwrapped = ...
        rad2deg(unwrap(deg2rad(D.pos_deg))) / 360 * cfg.track_cm;

    %% Window-based speed
    % Keep an unthresholded copy for acceleration. The display threshold,
    % when enabled, is applied only to the heatmap and speed summaries.
    D.speed_cm_s_unthresholded = compute_window_speed( ...
        D.t, ...
        D.pos_cm_unwrapped, ...
        cfg.speedWindow_cm_forPlot);

    D.speed_cm_s = D.speed_cm_s_unthresholded;

    if cfg.useSpeedThreshold
        D.speed_cm_s(D.speed_cm_s < cfg.minSpeed_cm_s) = NaN;
    end

    lapStartIdx = detect_laps_from_wrap(D.pos_deg);
    nTrialsTotal = numel(lapStartIdx) - 1;

    if nTrialsTotal < 1
        warning('No complete laps in %s. File skipped.', file{f});
        continue
    end

    % Use the first 100 complete laps, or all laps when fewer than 100 exist.
    nTrialsPlotted = min(nTrialsTotal, cfg.maxLapsToPlot);
    trialNums = 1:nTrialsPlotted;

    P = build_reward_centered_speed_matrix( ...
        D, ...
        lapStartIdx, ...
        trialNums, ...
        cfg);

    P.nTrialsTotal = nTrialsTotal;
    P.nTrialsPlotted = nTrialsPlotted;
    P.fileName = file{f};

    Pall{f} = P;
    keepFile(f) = true;

    fprintf([ ...
        '%s %s: plotting first %d of %d complete laps, ' ...
        'reward center %.1f deg\n'], ...
        mouseName, ...
        sessionDate, ...
        nTrialsPlotted, ...
        nTrialsTotal, ...
        P.reward_deg);
end

%% Remove skipped files
Pall = Pall(keepFile);
mouseNames = mouseNames(keepFile);
sessionDates = sessionDates(keepFile);
file = file(keepFile);

nFiles = numel(Pall);

if nFiles == 0
    error('None of the selected files contained a complete lap.');
end

%% Define old reward location from the first plotted session
referenceRewardDeg = Pall{1}.reward_deg;

fprintf('Old reward reference from first plotted session: %.1f deg\n', ...
    referenceRewardDeg);

for f = 1:nFiles

    P = Pall{f};

    rewardShiftDeg = mod( ...
        P.reward_deg - referenceRewardDeg + 180, 360) - 180;

    oldRewardRelativeDeg = mod( ...
        referenceRewardDeg - P.reward_deg + 180, 360) - 180;

    P.referenceReward_deg = referenceRewardDeg;
    P.rewardShift_deg = rewardShiftDeg;
    P.oldRewardRelative_deg = oldRewardRelativeDeg;

    P.showOldRewardLine = ...
        f > 1 && ...
        abs(rewardShiftDeg) > cfg.rewardShiftTolerance_deg;

    Pall{f} = P;

    if P.showOldRewardLine
        fprintf([ ...
            '%s %s: reward shifted by %.1f deg; ' ...
            'old reward line at relative %.1f deg\n'], ...
            mouseNames{f}, ...
            sessionDates{f}, ...
            rewardShiftDeg, ...
            oldRewardRelativeDeg);
    end
end

%% Calculate common scales across all selected sessions
if cfg.useSharedSessionScales && nFiles > 1
    shared = compute_shared_reward_centered_scales(Pall, cfg);

    cfg.sharedHeatmapCLim = shared.heatmapCLim;
    cfg.sharedSpeedYLim = shared.speedYLim;
    cfg.sharedAccelerationYLim = shared.accelerationYLim;

    fprintf('Shared heatmap scale: %.1f to %.1f cm/s\n', ...
        cfg.sharedHeatmapCLim(1), cfg.sharedHeatmapCLim(2));

    fprintf('Shared average-speed scale: %.1f to %.1f cm/s\n', ...
        cfg.sharedSpeedYLim(1), cfg.sharedSpeedYLim(2));

    fprintf('Shared acceleration scale: %.1f to %.1f cm/s^2\n', ...
        cfg.sharedAccelerationYLim(1), ...
        cfg.sharedAccelerationYLim(2));
end

%% Create figure after all scales are known
figWidth = min(0.98, max(0.58, 0.29 * nFiles));

figure( ...
    'Color', 'w', ...
    'Units', 'normalized', ...
    'Position', [(1-figWidth)/2, 0.04, figWidth, 0.91]);

% Heatmap occupies the upper two rows.
tl = tiledlayout(4, nFiles, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

%% Second pass: plot every session
for f = 1:nFiles

    P = Pall{f};

    axHeat = nexttile(tl, f, [2 1]);
    plot_reward_centered_trial_speed( ...
        P, ...
        cfg, ...
        mouseNames{f}, ...
        sessionDates{f}, ...
        axHeat);

    axSpeed = nexttile(tl, 2*nFiles + f);
    plot_reward_centered_average_speed(P, cfg, axSpeed);

    axAccel = nexttile(tl, 3*nFiles + f);
    plot_reward_centered_average_acceleration(P, cfg, axAccel);

    linkaxes([axHeat, axSpeed, axAccel], 'x');
end
