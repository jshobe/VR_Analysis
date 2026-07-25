function P = build_reward_centered_speed_matrix( ...
    D, lapStartIdx, trialNums, cfg)
% BUILD_REWARD_CENTERED_SPEED_MATRIX
% Builds reward-centered lap-by-position speed matrices and derives signed
% acceleration from the kinematic-cleaned, unthresholded spatial speed profile.
%
% Relative position:
%   -180 deg = half a lap before reward
%      0 deg = reward center
%   +180 deg = half a lap after reward
%
% Rewarded-trial licks and reward-omission-trial licks are stored
% separately for plotting.

%% Position bins in the original 0-360 coordinate system
edges_cm = 0:cfg.binSize_cm:cfg.track_cm;

if edges_cm(end) < cfg.track_cm
    edges_cm(end + 1) = cfg.track_cm;
end

centers_cm = edges_cm(1:end-1) + diff(edges_cm) / 2;
nBins = numel(centers_cm);

baseCenters_deg = centers_cm / cfg.track_cm * 360;

nTrials = numel(trialNums);

% Displayed/averaged speed can include the configured low-speed threshold.
speedMatBase = nan(nTrials, nBins);

% Spatial acceleration uses the kinematic-cleaned, unthresholded speed trace.
speedMatUnthresholdedBase = nan(nTrials, nBins);

if isfield(D, 'speed_cm_s_unthresholded')
    speedForAcceleration = D.speed_cm_s_unthresholded;
else
    speedForAcceleration = D.speed_cm_s;
end

%% Infer the actual reward location from reward-delivery samples
allRewardIdx = find(D.reward > 0);

if ~isempty(allRewardIdx)
    rewardDegVals = mod(D.pos_deg(allRewardIdx), 360);
    rewardDegVals = rewardDegVals(isfinite(rewardDegVals));

    if isempty(rewardDegVals)
        sessionRewardDeg = mod(cfg.reward_deg, 360);
    else
        % Circular mean handles rewards near the 0/360 boundary.
        meanSin = mean(sind(rewardDegVals));
        meanCos = mean(cosd(rewardDegVals));
        sessionRewardDeg = mod(atan2d(meanSin, meanCos), 360);
    end
else
    sessionRewardDeg = mod(cfg.reward_deg, 360);
end

%% Event containers in reward-centered coordinates
rewardX_deg = [];
rewardLap = [];

lickX_deg = [];
lickLap = [];

omissionLickX_deg = [];
omissionLickLap = [];

%% Build matrices and collect events
for p = 1:nTrials

    tr = trialNums(p);

    idx1 = lapStartIdx(tr);
    idx2 = lapStartIdx(tr + 1) - 1;

    if idx2 <= idx1
        continue
    end

    trialIdx = idx1:idx2;

    for b = 1:nBins
        inBin = ...
            D.pos_cm_wrapped(trialIdx) >= edges_cm(b) & ...
            D.pos_cm_wrapped(trialIdx) <  edges_cm(b + 1);

        idxBin = trialIdx(inBin);

        displaySpeedValues = D.speed_cm_s(idxBin);
        displaySpeedValues = displaySpeedValues(isfinite(displaySpeedValues));

        if ~isempty(displaySpeedValues)
            speedMatBase(p, b) = mean(displaySpeedValues);
        end

        rawSpeedValues = speedForAcceleration(idxBin);
        rawSpeedValues = rawSpeedValues(isfinite(rawSpeedValues));

        if ~isempty(rawSpeedValues)
            speedMatUnthresholdedBase(p, b) = mean(rawSpeedValues);
        end
    end

    %% Reward delivery onset(s)
    rewardLogicalTrial = D.reward(trialIdx) > 0;
    rewardOnsetLocal = find(diff([false; rewardLogicalTrial]) == 1);

    isRewardOmissionTrial = isempty(rewardOnsetLocal);

    if ~isRewardOmissionTrial
        rewardIdx = trialIdx(rewardOnsetLocal);

        rewardDeg = mod(D.pos_deg(rewardIdx), 360);
        rewardRelDeg = mod( ...
            rewardDeg - sessionRewardDeg + 180, 360) - 180;

        rewardX_deg = [rewardX_deg; rewardRelDeg(:)]; %#ok<AGROW>
        rewardLap = [rewardLap; ...
            p * ones(numel(rewardRelDeg), 1)]; %#ok<AGROW>
    end

    %% Licks
    lickIdx = trialIdx(D.lick(trialIdx) > 0);

    if ~isempty(lickIdx)
        lickDeg = mod(D.pos_deg(lickIdx), 360);
        lickRelDeg = mod( ...
            lickDeg - sessionRewardDeg + 180, 360) - 180;

        if isRewardOmissionTrial
            omissionLickX_deg = [ ...
                omissionLickX_deg; lickRelDeg(:)]; %#ok<AGROW>

            omissionLickLap = [ ...
                omissionLickLap; ...
                p * ones(numel(lickRelDeg), 1)]; %#ok<AGROW>
        else
            lickX_deg = [lickX_deg; lickRelDeg(:)]; %#ok<AGROW>
            lickLap = [lickLap; ...
                p * ones(numel(lickRelDeg), 1)]; %#ok<AGROW>
        end
    end
end

%% Reorder matrices so reward is centered at relative 0 deg
relativeCenters_deg = mod( ...
    baseCenters_deg - sessionRewardDeg + 180, 360) - 180;

[relativeCenters_deg, sortIdx] = sort(relativeCenters_deg);

speedMat = speedMatBase(:, sortIdx);
speedMatUnthresholded = speedMatUnthresholdedBase(:, sortIdx);

%% Derive spatial acceleration lap by lap
accelMat = compute_spatial_acceleration_from_speed_matrix( ...
    speedMatUnthresholded, ...
    relativeCenters_deg, ...
    cfg);

%% Output structure
P.speedMat = speedMat;
P.speedMatUnthresholded = speedMatUnthresholded;
P.accelMat = accelMat;

P.baseCenters_deg = baseCenters_deg;
P.relativeCenters_deg = relativeCenters_deg;

P.nTrials = nTrials;
P.trialNums = trialNums(:);

P.reward_deg = sessionRewardDeg;

P.rewardX_deg = rewardX_deg;
P.rewardLap = rewardLap;

P.lickX_deg = lickX_deg;
P.lickLap = lickLap;

P.omissionLickX_deg = omissionLickX_deg;
P.omissionLickLap = omissionLickLap;

end
