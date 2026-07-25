clear; clc;

cfg = get_single_reward_config();

[file, path] = uigetfile('*.txt', ...
    'Select VR session file(s)', ...
    'MultiSelect', 'on');

if isequal(file,0)
    error('No file selected.');
end

if ischar(file)
    file = {file};
end

%% Sort files chronologically using date in filename

fileDates = NaT(numel(file),1);

for k = 1:numel(file)

    tok = regexp(file{k}, '(\d{4}-\d{2}-\d{2})', ...
        'tokens', 'once');

    if ~isempty(tok)
        fileDates(k) = datetime(tok{1}, ...
            'InputFormat', 'yyyy-MM-dd');
    else
        fileDates(k) = NaT;
    end
end

[~, sortIdx] = sort(fileDates);

file = file(sortIdx);

nFiles = numel(file);

figure;
tiledlayout(2, nFiles, 'TileSpacing', 'compact', 'Padding', 'compact');

Pall = cell(nFiles,1);
labels = cell(nFiles,1);

for f = 1:nFiles

    fname = fullfile(path, file{f});

    [mouseName, sessionDate] = parse_mouse_date(file{f});
    labels{f} = sprintf('%s %s', mouseName, sessionDate);

    D = read_vr_session_txt(fname);

    D.pos_cm_wrapped   = mod((D.pos_deg / 360) * cfg.track_cm, cfg.track_cm);
    D.pos_cm_unwrapped = rad2deg(unwrap(deg2rad(D.pos_deg))) / 360 * cfg.track_cm;

    D.speed_cm_s = compute_window_speed( ...
        D.t, D.pos_cm_unwrapped, cfg.speedWindow_cm_forPlot);

    if cfg.useSpeedThreshold
        D.speed_cm_s(D.speed_cm_s < cfg.minSpeed_cm_s) = NaN;
    end

    lapStartIdx = detect_laps_from_wrap(D.pos_deg);

nTrialsTotal = numel(lapStartIdx) - 1;

trialNums = 1:nTrialsTotal;
trialLabel = sprintf('all %d laps', nTrialsTotal);

P = build_circular_speed_matrix(D, lapStartIdx, trialNums, cfg);
P.nTrialsTotal = nTrialsTotal;
P.trialLabel = trialLabel;
P.label = labels{f};

fprintf('%s reward position = %.1f deg\n', labels{f}, P.reward_deg);

Pall{f} = P;

    ax = nexttile(f);
    plot_circular_speed_figure(P, cfg, mouseName, sessionDate, trialLabel, ax);
end

axLinear = nexttile(nFiles + 1, [1 nFiles]);
plot_linear_speed_comparison(Pall, cfg, labels, axLinear);