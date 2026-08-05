clear; clc;

% Linear, reward-centered single-reward kinematics.
%
% For each selected session:
%   top:    lap-by-position speed heatmap
%   middle: overall speed +/- SEM with three matching lap-group curves
%   bottom: spatially derived signed acceleration in three lap groups
%
% Spatial acceleration is calculated after canonical preprocessed speed is binned by position:
%   a = v * dv/dx
% A local quadratic fit supplies dv/dx within a fixed position window.
%
% Multiple-session behavior:
%   - files are sorted chronologically
%   - the first plotted session defines the "old reward location"
%   - later sessions with a shifted reward receive a green old-reward line
%   - each heatmap uses its own session-specific color scale
%   - average-speed and acceleration panels can retain shared scales
%
% The user selects which complete laps are plotted and analyzed.

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

% Heatmaps intentionally use separate session-specific color scales.
if ~isfield(cfg, 'useSharedHeatmapScale')
    cfg.useSharedHeatmapScale = false;
end

% Preserve shared y-axes for speed and acceleration unless explicitly disabled.
if ~isfield(cfg, 'useSharedSpeedScale')
    cfg.useSharedSpeedScale = cfg.useSharedSessionScales;
end

if ~isfield(cfg, 'useSharedAccelerationScale')
    cfg.useSharedAccelerationScale = cfg.useSharedSessionScales;
end

% Prevent small reward-delivery jitter from being treated as a true shift.
if ~isfield(cfg, 'rewardShiftTolerance_deg')
    cfg.rewardShiftTolerance_deg = 5;
end

if ~isfield(cfg, 'showSpeedLapBlockCurves')
    cfg.showSpeedLapBlockCurves = true;
end

% Purple, blue, and green: deliberately no yellow curve.
nExpectedGroups = 3;
defaultGroupColors = [ ...
    0.25 0.10 0.65; ...  % purple
    0.00 0.45 0.74; ...  % blue
    0.35 0.70 0.25];     % green

% Apply the requested no-yellow palette to both speed and acceleration.
if nExpectedGroups <= size(defaultGroupColors, 1)
    cfg.accelerationGroupColors = ...
        defaultGroupColors(1:nExpectedGroups, :);
else
    cfg.accelerationGroupColors = cool(nExpectedGroups);
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

% Robustly reject isolated lap-level acceleration spikes at each position.
% This is not smoothing: rejected values are set to NaN only in a
% temporary block-summary copy. P.accelMat remains unchanged.
if ~isfield(cfg, 'removeAccelerationOutliers')
    cfg.removeAccelerationOutliers = true;
end

if ~isfield(cfg, 'accelerationOutlierThresholdRobustSD')
    cfg.accelerationOutlierThresholdRobustSD = 5;
end

if ~isfield(cfg, 'accelerationOutlierMinLaps')
    cfg.accelerationOutlierMinLaps = 8;
end


%% Canonical preprocessing and cache settings
% Raw text files are never modified. Each source file receives a processed
% MAT cache containing:
%   Session.Samples     complete raw-aligned event/sample rows
%   Session.Kinematics one row per genuine position update
%   Session.Events     reward, lick, brake, and redundant logging rows
%   Session.Audit      source identity, preprocessing version, and QC
%
% The main driver automatically rebuilds a cache when it is missing, stale,
% or made by an older preprocessor.
if ~isfield(cfg, 'processedSessionSubfolder')
    cfg.processedSessionSubfolder = 'ProcessedSessions';
end

if ~isfield(cfg, 'positionPlateauTolerance_cm')
    cfg.positionPlateauTolerance_cm = 1e-9;
end

if ~isfield(cfg, 'forcePreprocess')
    cfg.forcePreprocess = false;
end

if ~isfield(cfg, 'verifyProcessedSourceHash')
    cfg.verifyProcessedSourceHash = true;
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

    [Session, processedPath, preprocessingStatus] = ...
        load_or_preprocess_single_reward_session(fname, cfg);

    D = Session.Samples;

    %% Shared distance-window speed from canonical kinematic rows
    [D.speed_cm_s_unthresholded, ~, speedAudit] = ...
        compute_session_window_speed( ...
            Session, ...
            cfg.speedWindow_cm_forPlot);

    if ~speedAudit.passed
        error('Shared speed QC failed for %s.', file{f});
    end

    fprintf([ ...
        'Preprocessing %s: %s | %d raw rows | %d kinematic rows | ' ...
        '%d redundant rows excluded from speed.\n'], ...
        file{f}, ...
        preprocessingStatus.action, ...
        Session.Audit.nRawRows, ...
        Session.Audit.nKinematicRows, ...
        Session.Audit.nRedundantPositionRows);

    % Keep a thresholded display copy. Spatial acceleration uses the
    % canonical, unthresholded kinematic speed above.
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

    [trialNums, trialLabel] = select_laps_to_plot(nTrialsTotal);
    nTrialsPlotted = numel(trialNums);

    P = build_reward_centered_speed_matrix( ...
        D, ...
        lapStartIdx, ...
        trialNums, ...
        cfg);

    P.nTrialsTotal = nTrialsTotal;
    P.nTrialsPlotted = nTrialsPlotted;
    P.trialNums = trialNums(:);
    P.trialLabel = trialLabel;
    P.fileName = file{f};
    P.preprocessingAudit = Session.Audit;
    P.speedAudit = speedAudit;
    P.processedSessionPath = processedPath;

    Pall{f} = P;
    keepFile(f) = true;

    fprintf([ ...
        '%s %s: plotting %s, ' ...
        'reward center %.1f deg\n'], ...
        mouseName, ...
        sessionDate, ...
        trialLabel, ...
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

%% Calculate requested common scales across selected sessions
% Remove any pre-existing shared limits so disabled scale types cannot leak
% in from a user-edited configuration structure.
sharedLimitFields = { ...
    'sharedHeatmapCLim', ...
    'sharedSpeedYLim', ...
    'sharedAccelerationYLim'};

for k = 1:numel(sharedLimitFields)
    if isfield(cfg, sharedLimitFields{k})
        cfg = rmfield(cfg, sharedLimitFields{k});
    end
end

useAnySharedScale = ...
    cfg.useSharedHeatmapScale || ...
    cfg.useSharedSpeedScale || ...
    cfg.useSharedAccelerationScale;

if nFiles > 1 && useAnySharedScale
    shared = compute_shared_reward_centered_scales(Pall, cfg);

    if cfg.useSharedHeatmapScale
        cfg.sharedHeatmapCLim = shared.heatmapCLim;

        fprintf('Shared heatmap scale: %.1f to %.1f cm/s\n', ...
            cfg.sharedHeatmapCLim(1), ...
            cfg.sharedHeatmapCLim(2));
    else
        fprintf('Heatmaps use individual session-specific color scales.\n');
    end

    if cfg.useSharedSpeedScale
        cfg.sharedSpeedYLim = shared.speedYLim;

        fprintf('Shared average-speed scale: %.1f to %.1f cm/s\n', ...
            cfg.sharedSpeedYLim(1), ...
            cfg.sharedSpeedYLim(2));
    end

    if cfg.useSharedAccelerationScale
        cfg.sharedAccelerationYLim = shared.accelerationYLim;

        fprintf('Shared acceleration scale: %.1f to %.1f cm/s^2\n', ...
            cfg.sharedAccelerationYLim(1), ...
            cfg.sharedAccelerationYLim(2));
    end
elseif ~cfg.useSharedHeatmapScale
    fprintf('Heatmaps use individual session-specific color scales.\n');
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
