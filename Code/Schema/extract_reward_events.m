function rewards = extract_reward_events(session, cfg)

rewardLogical = session.reward > 0;
rewardOnsetIdx = find(diff([0; rewardLogical]) == 1);

rewards = struct();
rewards.rewardOnsetIdx = [];
rewards.rewardSiteDeg = [];

if isempty(rewardOnsetIdx)
    return
end

rewardSiteDeg = nan(size(rewardOnsetIdx));
keepReward = false(size(rewardOnsetIdx));

for r = 1:numel(rewardOnsetIdx)
    rp = mod(session.pos_deg_wrapped(rewardOnsetIdx(r)), 360);
    angDiff = abs(mod(rp - cfg.activeReward_deg + 180, 360) - 180);
    [minDiff, locIdx] = min(angDiff);

    if minDiff <= cfg.rewardTolerance_deg
        rewardSiteDeg(r) = cfg.activeReward_deg(locIdx);
        keepReward(r) = true;
    end
end

rewards.rewardOnsetIdx = rewardOnsetIdx(keepReward);
rewards.rewardSiteDeg  = rewardSiteDeg(keepReward);

end