function P = build_circular_speed_matrix(D, lapStartIdx, trialNums, cfg)

edges_cm = 0:cfg.binSize_cm:cfg.track_cm;
centers_cm = edges_cm(1:end-1) + cfg.binSize_cm/2;
nBins = numel(edges_cm) - 1;

thetaEdges = edges_cm / cfg.track_cm * 2*pi;
thetaCenters = centers_cm / cfg.track_cm * 2*pi;

nTrials = numel(trialNums);

speedMat = nan(nTrials, nBins);

rewardTheta = [];
rewardRadius = [];

lickTheta = [];
lickRadius = [];

omissionLickTheta = [];
omissionLickRadius = [];

%% Infer actual session reward location
allRewardIdx = find(D.reward > 0);

if ~isempty(allRewardIdx)
    sessionRewardDeg = median(mod(D.pos_deg(allRewardIdx), 360), 'omitnan');
else
    sessionRewardDeg = cfg.reward_deg;
end

%% Build speed matrix and event overlays
for p = 1:nTrials

    tr = trialNums(p);

    idx1 = lapStartIdx(tr);
    idx2 = lapStartIdx(tr+1) - 1;

    if idx2 <= idx1
        continue
    end

    trialIdx = idx1:idx2;

    %% Speed matrix
    for b = 1:nBins
        idxBin = trialIdx(D.pos_cm_wrapped(trialIdx) >= edges_cm(b) & ...
                          D.pos_cm_wrapped(trialIdx) <  edges_cm(b+1));

        x = D.speed_cm_s(idxBin);
        x = x(~isnan(x));

        if ~isempty(x)
            speedMat(p,b) = mean(x);
        end
    end

    %% Reward delivery onset only
    rewardLogicalTrial = D.reward(trialIdx) > 0;
    rewardOnsetLocal = find(diff([0; rewardLogicalTrial]) == 1);

    isRewardOmissionTrial = isempty(rewardOnsetLocal);

    if ~isRewardOmissionTrial
        rewardIdx = trialIdx(rewardOnsetLocal);

        rewardTheta = [rewardTheta; ...
            D.pos_cm_wrapped(rewardIdx) / cfg.track_cm * 2*pi];

        rewardRadius = [rewardRadius; ...
            cfg.innerHoleR + cfg.heatmapScale * p * ones(numel(rewardIdx),1)];
    end

    %% Licks
    lickIdx = trialIdx(D.lick(trialIdx) > 0);

    if ~isempty(lickIdx)

        if isRewardOmissionTrial
            omissionLickTheta = [omissionLickTheta; ...
                D.pos_cm_wrapped(lickIdx) / cfg.track_cm * 2*pi];

            omissionLickRadius = [omissionLickRadius; ...
                cfg.innerHoleR + cfg.heatmapScale * p * ones(numel(lickIdx),1)];

        else
            lickTheta = [lickTheta; ...
                D.pos_cm_wrapped(lickIdx) / cfg.track_cm * 2*pi];

            lickRadius = [lickRadius; ...
                cfg.innerHoleR + cfg.heatmapScale * p * ones(numel(lickIdx),1)];
        end
    end
end

%% Output structure
P.speedMat = speedMat;
P.edges_cm = edges_cm;
P.centers_cm = centers_cm;
P.thetaEdges = thetaEdges;
P.thetaCenters = thetaCenters;
P.nTrials = nTrials;

P.rewardTheta = rewardTheta;
P.rewardRadius = rewardRadius;

P.lickTheta = lickTheta;
P.lickRadius = lickRadius;

P.omissionLickTheta = omissionLickTheta;
P.omissionLickRadius = omissionLickRadius;

P.reward_deg = sessionRewardDeg;

end