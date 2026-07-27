clear; clc;

% Reward-to-first-lick latency analysis for single-reward VR sessions.
%
% For the selected sessions, this script:
%   1. loads the canonical processed session;
%   2. detects complete laps from the position wrap;
%   3. pairs each valid reward onset with the first new lick onset;
%   4. plots one chronological reward/lick raster per session; and
%   5. overlays every session's rolling-median latency curve.
%
% Omission laps are retained as gaps. Laps containing more than one reward
% onset are flagged and excluded from latency calculations.

cfg = get_single_reward_config();

%% Lick-latency settings
% First-lick searches stop at the earlier of the lap end or this limit.
cfg.maxLickLatency_s = 10;

% Rolling median shown in the lower panel.
cfg.latencyRollingWindow_laps = 10;

% Match the existing single-reward figures unless changed here.
if ~isfield(cfg, 'maxLapsToPlot')
    cfg.maxLapsToPlot = 100;
end

%% Canonical preprocessing and cache settings
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

%% Select and sort sessions
[file, path] = uigetfile( ...
    '*.txt', ...
    'Select VR session file(s) for lick-latency analysis', ...
    'MultiSelect', 'on');

if isequal(file, 0)
    error('No file selected.');
end

if ischar(file)
    file = {file};
end

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

%% Analyze each session
nFiles = numel(file);

emptyResult = struct( ...
    'FileName', '', ...
    'MouseName', '', ...
    'SessionDate', '', ...
    'ProcessedSessionPath', '', ...
    'PreprocessingStatus', struct(), ...
    'LatencyTable', table(), ...
    'Figure', gobjects(1), ...
    'FigurePNGPath', '', ...
    'FigureFIGPath', '');

LatencyResults = repmat(emptyResult, nFiles, 1);

for f = 1:nFiles
    fname = fullfile(path, file{f});

    [mouseName, sessionDate] = parse_mouse_date(file{f});

    [Session, processedPath, preprocessingStatus] = ...
        load_or_preprocess_single_reward_session(fname, cfg);

    D = Session.Samples;
    lapStartIdx = detect_laps_from_wrap(D.pos_deg);
    nCompleteLaps = numel(lapStartIdx) - 1;
    nLapsAnalyzed = min(nCompleteLaps, cfg.maxLapsToPlot);
    trialNums = (1:nLapsAnalyzed)';

    T = compute_first_lick_latency( ...
        D, ...
        lapStartIdx, ...
        trialNums, ...
        cfg);

    LatencyResults(f).FileName = file{f};
    LatencyResults(f).MouseName = mouseName;
    LatencyResults(f).SessionDate = sessionDate;
    LatencyResults(f).ProcessedSessionPath = processedPath;
    LatencyResults(f).PreprocessingStatus = preprocessingStatus;
    LatencyResults(f).LatencyTable = T;

    validLatency = T.LickLatency_s(T.HasFirstLick);
    medianLatency = median(validLatency, 'omitnan');

    fprintf([ ...
        '%s %s: %d laps analyzed | %d rewarded | %d omissions | ' ...
        '%d first licks within %.1f s | median latency %.3f s\n'], ...
        mouseName, ...
        sessionDate, ...
        height(T), ...
        sum(T.IsRewardedLap), ...
        sum(T.IsOmissionLap), ...
        sum(T.HasFirstLick), ...
        cfg.maxLickLatency_s, ...
        medianLatency);

    if any(T.HasMultipleRewards)
        warning([ ...
            '%s %s contains %d lap(s) with multiple reward onsets. ' ...
            'Those laps were excluded from latency calculations.'], ...
            mouseName, ...
            sessionDate, ...
            sum(T.HasMultipleRewards));
    end
end

%% Plot all sessions together in chronological order
latencyTables = {LatencyResults.LatencyTable};
mouseNames = {LatencyResults.MouseName};
sessionDates = {LatencyResults.SessionDate};

fig = plot_lick_latency( ...
    latencyTables, ...
    cfg, ...
    mouseNames, ...
    sessionDates);

%% Save a non-overwriting PNG and editable MATLAB figure
outputFolder = fullfile(path, 'LickLatencyFigures');

if ~isfolder(outputFolder)
    [ok, msg] = mkdir(outputFolder);
    if ~ok
        error('Could not create figure output folder: %s', msg);
    end
end

mouseList = sort(unique(mouseNames));
dateList = sort(unique(sessionDates));

mouseLabel = strjoin(mouseList, '-');

if numel(dateList) == 1
    dateLabel = dateList{1};
else
    dateLabel = sprintf( ...
        '%s_to_%s', ...
        dateList{1}, ...
        dateList{end});
end

runTimestamp = char(datetime( ...
    'now', ...
    'Format', 'yyyyMMdd_HHmmss_SSS'));

figureBaseName = sprintf( ...
    'LickLatency_%s_%s_%s', ...
    mouseLabel, ...
    dateLabel, ...
    runTimestamp);

figureBaseName = regexprep( ...
    figureBaseName, ...
    '[^A-Za-z0-9_-]', ...
    '_');

pngPath = fullfile( ...
    outputFolder, ...
    [figureBaseName '.png']);

figPath = fullfile( ...
    outputFolder, ...
    [figureBaseName '.fig']);

drawnow;
exportgraphics(fig, pngPath, 'Resolution', 300);
savefig(fig, figPath);

for f = 1:nFiles
    LatencyResults(f).Figure = fig;
    LatencyResults(f).FigurePNGPath = pngPath;
    LatencyResults(f).FigureFIGPath = figPath;
end

fprintf([ ...
    'Saved lick-latency figure:\n' ...
    '  PNG: %s\n' ...
    '  FIG: %s\n'], ...
    pngPath, ...
    figPath);
