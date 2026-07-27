clear; clc;

% Reward-to-first-lick latency analysis for single-reward VR sessions.
%
% For the selected sessions, this script:
%   1. loads the canonical processed session;
%   2. detects complete laps from the position wrap;
%   3. pairs each valid reward onset with the first new lick onset;
%   4. plots one chronological reward/lick raster per session; and
%   5. compares rolling-median latency curves and, for paired layouts,
%      trial-level session medians with bootstrap confidence intervals.
%
% When exactly four sessions from one mouse are selected, the first and
% third chronological sessions form the top comparison block, while the
% second and fourth form the bottom comparison block.
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
    'FigureFIGPath', '', ...
    'FigurePDFPath', '', ...
    'FigureSVGPath', '');

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

comparisonBlocks = [];
if nFiles == 4 && numel(unique(mouseNames)) == 1
    comparisonBlocks = [1 2 1 2];
end

fig = plot_lick_latency( ...
    latencyTables, ...
    cfg, ...
    mouseNames, ...
    sessionDates, ...
    comparisonBlocks);

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

pdfPath = fullfile( ...
    outputFolder, ...
    [figureBaseName '.pdf']);

svgPath = fullfile( ...
    outputFolder, ...
    [figureBaseName '.svg']);

if ~isempty(comparisonBlocks)
    set(findall(fig, '-property', 'FontName'), ...
        'FontName', ...
        'Arial');
    fig.Renderer = 'painters';
    fig.Color = 'w';
    fig.InvertHardcopy = 'off';
    fig.PaperPositionMode = 'auto';
end

drawnow;
savefig(fig, figPath);

if isempty(comparisonBlocks)
    exportgraphics(fig, pngPath, 'Resolution', 300);
else
    figureVisibility = fig.Visible;
    close(fig);
    fig = openfig(figPath, 'invisible');
    temporaryPngPath = [tempname '.png'];
    temporaryPngCleanup = onCleanup(@() delete_if_present( ...
        temporaryPngPath));
    temporaryPdfPath = [tempname '.pdf'];
    temporaryPdfCleanup = onCleanup(@() delete_if_present( ...
        temporaryPdfPath));
    temporarySvgPath = [tempname '.svg'];
    temporarySvgCleanup = onCleanup(@() delete_if_present( ...
        temporarySvgPath));

    set(findall(fig, '-property', 'FontName'), ...
        'FontName', ...
        'Arial');
    fig.Renderer = 'painters';
    fig.Color = 'w';
    fig.InvertHardcopy = 'off';
    fig.PaperPositionMode = 'auto';

    drawnow;
    exportgraphics(fig, temporaryPngPath, 'Resolution', 300);
    exportgraphics( ...
        fig, ...
        temporaryPdfPath, ...
        'ContentType', ...
        'vector', ...
        'BackgroundColor', ...
        'white');
    print(fig, temporarySvgPath, '-dsvg', '-vector');

    finalize_export(temporaryPngPath, pngPath, 'PNG');
    finalize_export(temporaryPdfPath, pdfPath, 'PDF');
    finalize_export(temporarySvgPath, svgPath, 'SVG');

    clear temporaryPngCleanup
    clear temporaryPdfCleanup
    clear temporarySvgCleanup
    fig.Visible = figureVisibility;
end

for f = 1:nFiles
    LatencyResults(f).Figure = fig;
    LatencyResults(f).FigurePNGPath = pngPath;
    LatencyResults(f).FigureFIGPath = figPath;

    if ~isempty(comparisonBlocks)
        LatencyResults(f).FigurePDFPath = pdfPath;
        LatencyResults(f).FigureSVGPath = svgPath;
    end
end

if isempty(comparisonBlocks)
    fprintf([ ...
        'Saved lick-latency figure:\n' ...
        '  PNG: %s\n' ...
        '  FIG: %s\n'], ...
        pngPath, ...
        figPath);
else
    fprintf([ ...
        'Saved lick-latency figure:\n' ...
        '  PNG: %s\n' ...
        '  FIG: %s\n' ...
        '  PDF (vector): %s\n' ...
        '  SVG (painters vector): %s\n'], ...
        pngPath, ...
        figPath, ...
        pdfPath, ...
        svgPath);
end


function finalize_export(temporaryPath, finalPath, formatName)

[moveSucceeded, moveMessage] = movefile( ...
    temporaryPath, ...
    finalPath, ...
    'f');

if ~moveSucceeded
    error( ...
        'Could not finalize paired %s: %s', ...
        formatName, ...
        moveMessage);
end

end


function delete_if_present(filePath)

if isfile(filePath)
    delete(filePath);
end

end
