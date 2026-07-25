function cues = extract_cue_epochs(session, cfg)

cueValid = ~isnan(session.blackout_cue_id);
cueOnsetIdx  = find(diff([0; cueValid]) == 1);
cueOffsetIdx = find(diff([cueValid; 0]) == -1);

keepCue = false(size(cueOnsetIdx));
cueIdentityVal  = nan(size(cueOnsetIdx));
cueIdentityName = cell(size(cueOnsetIdx));
cueTrackPosDeg  = nan(size(cueOnsetIdx));
cueLocationDeg  = nan(size(cueOnsetIdx));
targetRewardDeg = nan(size(cueOnsetIdx));

for c = 1:numel(cueOnsetIdx)

    val = session.blackout_cue_id(cueOnsetIdx(c));
    match = find(cfg.cueIdentityValues == val, 1, 'first');

    if isempty(match)
        continue
    end

    keepCue(c) = true;
    cueIdentityVal(c) = val;
    cueIdentityName{c} = cfg.cueIdentityNames{match};
    cueTrackPosDeg(c) = mod(session.pos_deg_wrapped(cueOnsetIdx(c)), 360);

    angDiff = abs(mod(cueTrackPosDeg(c) - cfg.cue_deg_all + 180, 360) - 180);
    [minDiff, locIdx] = min(angDiff);

    if minDiff <= cfg.cueTolerance_deg
        cueLocationDeg(c) = cfg.cue_deg_all(locIdx);
    else
        cueLocationDeg(c) = NaN;
    end

    targetRewardDeg(c) = cfg.cueToRewardMap_deg(match);
end

cues = struct();
cues.cueOnsetIdx     = cueOnsetIdx(keepCue);
cues.cueOffsetIdx    = cueOffsetIdx(keepCue);
cues.cueIdentityVal  = cueIdentityVal(keepCue);
cues.cueIdentityName = cueIdentityName(keepCue);
cues.cueTrackPosDeg  = cueTrackPosDeg(keepCue);
cues.cueLocationDeg  = cueLocationDeg(keepCue);
cues.targetRewardDeg = targetRewardDeg(keepCue);

end