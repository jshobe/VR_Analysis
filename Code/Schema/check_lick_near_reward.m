function hasLickNearReward = check_lick_near_reward( ...
    rewardIdx, crossIdx, siteDeg, pos_cm_unwrapped, lick, track_cm, lickNearRewardWindow_deg)

site_cm = siteDeg / 360 * track_cm;

cp = site_cm + round((pos_cm_unwrapped(crossIdx) - site_cm) / track_cm) * track_cm;

rewardPos_cm = pos_cm_unwrapped(rewardIdx);
rewardRelDeg = (rewardPos_cm - cp) / track_cm * 360;

relDeg = (pos_cm_unwrapped - cp) / track_cm * 360;

lickMask = lick > 0 & ...
           relDeg >= (rewardRelDeg - lickNearRewardWindow_deg) & ...
           relDeg <= (rewardRelDeg + lickNearRewardWindow_deg);

hasLickNearReward = any(lickMask);

end