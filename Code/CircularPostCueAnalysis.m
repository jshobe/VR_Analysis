%% CircularPostCueAnalysis
% Post-cue speed analysis using 45 degree spatial windows
% Cue locations are shifted from reward sites:
% rewards = [0 90 180 270]
% cues    = [30 120 210 300]

clearvars; close all; clc;

%% ---------------- USER SETTINGS ----------------

track_cm = 540;

postCueDeg = 45;
preCueDeg  = 45;

nearFarCutoffDeg = 90;
minSamplesPerWindow = 3;

reward_deg = [0 90 180 270];
cue_deg    = [30 120 210 300];

%% ---------------- LOAD FILE ----------------

[file, path] = uigetfile('*.txt', 'Select VR session file');

if isequal(file,0)
    error('No file selected.');
end

fname = fullfile(path, file);
[~, baseName, ~] = fileparts(file);

mouseTok = regexp(baseName, '(JB\d+)', 'tokens', 'once');

if ~isempty(mouseTok)
    mouseName = mouseTok{1};
else
    error('Could not extract mouse name from file name.');
end

%% ---------------- MOUSE-SPECIFIC CUE-REWARD MAP ----------------

cueRewardDeg = containers.Map('KeyType','double','ValueType','double');

switch mouseName

    case 'JB5'
        cueRewardDeg(0)  = 0;      % cue identity 0 predicts reward at 0 deg
        cueRewardDeg(30) = 180;    % cue identity 30 predicts reward at 180 deg

    otherwise
        error('No cue-reward mapping defined for mouse %s.', mouseName);

end

validCueIDs = cell2mat(keys(cueRewardDeg));

fprintf('Mouse detected: %s\n', mouseName);
disp('Valid cue IDs expected by code:')
disp(validCueIDs)

%% ---------------- READ FILE ----------------
% Expected column order:
% 1 time_s
% 2 distance_traveled
% 3 position(deg)
% 4 visual_state
% 5 next_RW_location_idx
% 6 reward_delivered
% 7 brake_applied
% 8 lick_detection
% 9 blackout_cue_identity

fid = fopen(fname, 'r');

if fid == -1
    error('Could not open file.');
end

fgetl(fid); % skip header
C = textscan(fid, '%f%f%f%f%f%f%f%f%f');
fclose(fid);

t        = C{1};
pos_deg  = C{3};
reward   = C{6};
brake    = C{7};
lick     = C{8};
cueIDraw = C{9};

valid = ~isnan(t) & ~isnan(pos_deg) & ~isnan(brake);

t        = t(valid);
pos_deg  = pos_deg(valid);
reward   = reward(valid);
brake    = brake(valid);
lick     = lick(valid);
cueIDraw = cueIDraw(valid);

if numel(t) < 2
    error('Not enough valid samples.');
end

pos_deg_wrapped = mod(pos_deg, 360);

disp('Unique non-NaN cue identities actually found in file:')
disp(unique(cueIDraw(~isnan(cueIDraw)))')

%% ---------------- SPEED FROM POSITION ----------------

pos_cm_unwrapped = rad2deg(unwrap(deg2rad(pos_deg))) / 360 * track_cm;

dt = diff(t);
dp = diff(pos_cm_unwrapped);

speed_cm_s = nan(size(t));

validDt = dt > 0 & isfinite(dt) & isfinite(dp);

speed_cm_s(2:end) = abs(dp ./ dt);
speed_cm_s([false; ~validDt]) = NaN;

% Exclude brake periods from speed values
speed_cm_s(brake == 1) = NaN;

%% ---------------- FIND CUE ONSETS ----------------
% Important:
% Cue identity 0 is a real cue for JB5.
% Therefore do NOT use cueIDraw > 0.
% Also do NOT require brake == 0 here, because cue can occur during brake.
% Brake is excluded later from speed calculation.

cueSamples = find(ismember(cueIDraw, validCueIDs));

if isempty(cueSamples)
    error('No valid cue samples found. Check cue identities and column 9.');
end

cueStartIdx = cueSamples([true; diff(cueSamples) > 1]);

fprintf('Detected %d cue presentations.\n', numel(cueStartIdx));

%% ---------------- ANALYSIS ----------------

results = table();

for i = 1:numel(cueStartIdx)

    idx = cueStartIdx(i);

    cueID = cueIDraw(idx);

    if ~isKey(cueRewardDeg, cueID)
        continue
    end

    expectedRewardDeg = cueRewardDeg(cueID);

    % Raw position when cue appeared
    rawCuePosDeg = pos_deg_wrapped(idx);

    % Snap cue to nearest of the 4 possible shifted cue locations
    cuePosDeg = nearestCircularAngle(rawCuePosDeg, cue_deg);

    % Forward circular distance from cue location to expected reward site
    cueToRewardDeg = mod(expectedRewardDeg - cuePosDeg, 360);

    if cueToRewardDeg <= nearFarCutoffDeg
        proximityGroup = "Near";
    else
        proximityGroup = "Far";
    end

    % 45 degree post-cue window
    postStart = cuePosDeg;
    postEnd   = mod(cuePosDeg + postCueDeg, 360);

    % 45 degree pre-cue baseline window
    preStart  = mod(cuePosDeg - preCueDeg, 360);
    preEnd    = cuePosDeg;

    postMask = circularWindowMask(pos_deg_wrapped, postStart, postEnd);
    preMask  = circularWindowMask(pos_deg_wrapped, preStart, preEnd);

    % Restrict post window to samples after cue onset
    postMask(1:idx-1) = false;

    % Restrict pre window to samples before cue onset
    preMask(idx+1:end) = false;

    % Exclude brake periods from speed windows
    postMask = postMask & brake == 0;
    preMask  = preMask  & brake == 0;

    postSpeed = speed_cm_s(postMask);
    preSpeed  = speed_cm_s(preMask);

    postSpeed = postSpeed(isfinite(postSpeed));
    preSpeed  = preSpeed(isfinite(preSpeed));

    if numel(postSpeed) < minSamplesPerWindow || numel(preSpeed) < minSamplesPerWindow
        continue
    end

    meanPreSpeed  = mean(preSpeed);
    meanPostSpeed = mean(postSpeed);
    deltaSpeed    = meanPostSpeed - meanPreSpeed;
    peakPostSpeed = max(postSpeed);

    newRow = table( ...
        idx, cueID, rawCuePosDeg, cuePosDeg, expectedRewardDeg, cueToRewardDeg, ...
        string(proximityGroup), ...
        meanPreSpeed, meanPostSpeed, deltaSpeed, peakPostSpeed, ...
        numel(preSpeed), numel(postSpeed), ...
        'VariableNames', { ...
            'CueIndex', ...
            'CueID', ...
            'RawCuePositionDeg', ...
            'SnappedCuePositionDeg', ...
            'ExpectedRewardDeg', ...
            'CueToRewardDeg', ...
            'ProximityGroup', ...
            'MeanPreSpeed', ...
            'MeanPostSpeed', ...
            'DeltaSpeed', ...
            'PeakPostSpeed', ...
            'NumPreSamples', ...
            'NumPostSamples' ...
        });

    results = [results; newRow];

end

if isempty(results)
    error('No valid cue events survived filtering. Try lowering minSamplesPerWindow or inspect brake periods.');
end

disp(results)

%% ---------------- SAVE RESULTS ----------------

outName = fullfile(path, [baseName '_PostCueSpeedResults.csv']);
writetable(results, outName);

fprintf('\nSaved results to:\n%s\n', outName);

%% ---------------- PLOTS ----------------

figure;
boxchart(categorical(results.ProximityGroup), results.DeltaSpeed);
ylabel('Post-cue speed change, cm/s');
xlabel('Cue-to-reward proximity');
title('Post-cue speed change: 45 degree window');
yline(0, '--');

figure;
boxchart(categorical(results.CueID), results.DeltaSpeed);
ylabel('Post-cue speed change, cm/s');
xlabel('Cue identity');
title('Post-cue speed change by cue identity');
yline(0, '--');

figure;
boxchart(categorical(results.SnappedCuePositionDeg), results.DeltaSpeed);
ylabel('Post-cue speed change, cm/s');
xlabel('Cue position, degrees');
title('Post-cue speed change by shifted cue location');
yline(0, '--');

figure;
scatter(results.CueToRewardDeg, results.DeltaSpeed, 45, 'filled');
xlabel('Forward cue-to-expected-reward distance, degrees');
ylabel('Post-cue speed change, cm/s');
title('Post-cue speed change vs expected reward distance');
yline(0, '--');

%% ---------------- HELPER FUNCTIONS ----------------

function mask = circularWindowMask(posDeg, startDeg, endDeg)

    startDeg = mod(startDeg, 360);
    endDeg   = mod(endDeg, 360);

    if startDeg < endDeg
        mask = posDeg >= startDeg & posDeg <= endDeg;
    elseif startDeg > endDeg
        mask = posDeg >= startDeg | posDeg <= endDeg;
    else
        mask = true(size(posDeg));
    end

end

function nearestDeg = nearestCircularAngle(angleDeg, allowedDeg)

    d = abs(mod(angleDeg - allowedDeg + 180, 360) - 180);
    [~, k] = min(d);
    nearestDeg = allowedDeg(k);

end