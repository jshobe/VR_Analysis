clear; clc;

track_cm = 540;

% Set for this mouse/session
activeReward_deg = [90 270];   % example for JB2
rewardTolerance_deg = 35;

[file, path] = uigetfile('*.txt', 'Select VR session file(s)', 'MultiSelect', 'on');
if isequal(file,0)
    error('No file selected.');
end
if ischar(file)
    file = {file};
end

allJitterDeg = [];
allRewardSiteDeg = [];
allSessionLabel = {};

for f = 1:numel(file)

    thisFile = file{f};
    fname = fullfile(path, thisFile);

    [~, baseName, ~] = fileparts(thisFile);

    mouseTok = regexp(baseName, '(JB\d+)', 'tokens', 'once');
    if ~isempty(mouseTok)
        mouseName = mouseTok{1};
    else
        mouseName = 'UnknownMouse';
    end

    dateTok = regexp(baseName, '(\d{4}-\d{2}-\d{2})', 'tokens', 'once');
    if ~isempty(dateTok)
        sessionDate = dateTok{1};
    else
        sessionDate = 'UnknownDate';
    end

    sessionLabel = [mouseName '  ' sessionDate];

    fid = fopen(fname, 'r');
    if fid == -1
        warning('Could not open file: %s', thisFile);
        continue
    end

    fgetl(fid); % skip header
    C = textscan(fid, '%f%f%f%f%f%f%f%f%f', 'TreatAsEmpty', {'NaN','nan'});
    fclose(fid);

    if numel(C) < 9 || isempty(C{1})
        warning('Could not parse file: %s', thisFile);
        continue
    end

    t        = C{1};
    pos_deg  = C{3};
    reward   = C{6};

    valid = ~isnan(t) & ~isnan(pos_deg) & ~isnan(reward);
    pos_deg = pos_deg(valid);
    reward  = reward(valid);

    if numel(pos_deg) < 10
        warning('Too few valid samples in file: %s', thisFile);
        continue
    end

    pos_deg_wrapped = mod(pos_deg, 360);

    rewardLogical = reward > 0;
    rewardOnsetIdx = find(diff([0; rewardLogical]) == 1);

    if isempty(rewardOnsetIdx)
        warning('No reward onsets found in file: %s', thisFile);
        continue
    end

    for r = 1:numel(rewardOnsetIdx)
        idx = rewardOnsetIdx(r);
        actualDeg = pos_deg_wrapped(idx);

        angDiff = abs(mod(actualDeg - activeReward_deg + 180, 360) - 180);
        [minDiff, locIdx] = min(angDiff);

        if minDiff <= rewardTolerance_deg
            nominalDeg = activeReward_deg(locIdx);

            % signed jitter in [-180, 180]
            jitterDeg = mod(actualDeg - nominalDeg + 180, 360) - 180;

            allJitterDeg(end+1,1) = jitterDeg; %#ok<SAGROW>
            allRewardSiteDeg(end+1,1) = nominalDeg; %#ok<SAGROW>
            allSessionLabel{end+1,1} = sessionLabel; %#ok<SAGROW>
        end
    end
end

if isempty(allJitterDeg)
    error('No usable reward jitter values found.');
end

fprintf('\nReward jitter summary (deg):\n');
fprintf('n = %d\n', numel(allJitterDeg));
fprintf('mean   = %.3f\n', mean(allJitterDeg));
fprintf('median = %.3f\n', median(allJitterDeg));
fprintf('std    = %.3f\n', std(allJitterDeg));
fprintf('min    = %.3f\n', min(allJitterDeg));
fprintf('max    = %.3f\n', max(allJitterDeg));
fprintf('abs median = %.3f\n', median(abs(allJitterDeg)));
fprintf('abs 95th percentile = %.3f\n', prctile(abs(allJitterDeg),95));

for s = 1:numel(activeReward_deg)
    site = activeReward_deg(s);
    vals = allJitterDeg(allRewardSiteDeg == site);
    if ~isempty(vals)
        fprintf('\nSite %.0f deg:\n', site);
        fprintf('  n = %d\n', numel(vals));
        fprintf('  mean   = %.3f\n', mean(vals));
        fprintf('  median = %.3f\n', median(vals));
        fprintf('  std    = %.3f\n', std(vals));
        fprintf('  min    = %.3f\n', min(vals));
        fprintf('  max    = %.3f\n', max(vals));
        fprintf('  abs median = %.3f\n', median(abs(vals)));
    end
end

figure;
histogram(allJitterDeg, 30);
xlabel('Reward jitter (deg)');
ylabel('Count');
title('Reward jitter distribution');
grid on

figure;
gscatter(allRewardSiteDeg, allJitterDeg, allRewardSiteDeg);
xlabel('Nominal reward site (deg)');
ylabel('Reward jitter (deg)');
title('Reward jitter by reward site');
grid on