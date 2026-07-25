function [eventRows, profileSpeedMat, profileSiteDeg, profileState, profileScenario] = ...
    build_interval_events(session, rewards, cues, cfg)

eventRows = {};
profileSpeedMat = [];
profileSiteDeg = [];
profileState = {};
profileScenario = {};

eventCounter = 0;
intervalCounter = 0;

%% ===================== 1) CUE -> REWARD INTERVALS =====================
for c = 1:numel(cues.cueOnsetIdx)

    thisCueOn  = cues.cueOnsetIdx(c);
    thisCueOff = cues.cueOffsetIdx(c);
    thisCueVal = cues.cueIdentityVal(c);
    thisCueName = cues.cueIdentityName{c};
    thisCueTrackDeg = cues.cueTrackPosDeg(c);
    thisCueLocDeg = cues.cueLocationDeg(c);
    thisTargetRewardDeg = cues.targetRewardDeg(c);

    % Forward cue->target distance in degrees
    if ~isnan(thisCueLocDeg)
        cueToTargetDistDeg = mod(thisTargetRewardDeg - thisCueLocDeg, 360);
    else
        cueToTargetDistDeg = NaN;
    end

    % Next reward after cue onset
    rNext = find(rewards.rewardOnsetIdx > thisCueOn, 1, 'first');
    if isempty(rNext)
        continue
    end

    thisRewardIdx = rewards.rewardOnsetIdx(rNext);
    thisRewardSiteDeg = rewards.rewardSiteDeg(rNext);

    % Cue identity should match actual reward site
    if thisRewardSiteDeg ~= thisTargetRewardDeg
        warning('Cue->reward mismatch in %s: cue %s predicts %.0f deg, actual next reward at %.0f deg.', ...
            session.fileName, thisCueName, thisTargetRewardDeg, thisRewardSiteDeg);

        if cfg.skipCueRewardMismatches
            continue
        end
    end

    % Interval is from cue offset to reward onset
    idxStart = thisCueOff;
    idxEnd   = thisRewardIdx;

    if idxEnd <= idxStart + 1
        continue
    end

    intervalCounter = intervalCounter + 1;

    % Target is the actual rewarded crossing
    targetCrossIdx = thisRewardIdx;

    % Non-target is the other active reward site, if crossed before reward
    nonTargetSiteDeg = cfg.activeReward_deg(cfg.activeReward_deg ~= thisTargetRewardDeg);
    nonTargetCrossIdx = find_last_crossing( ...
        nonTargetSiteDeg, idxStart, idxEnd, session.pos_cm_unwrapped, cfg.track_cm);

    % Forward cue->non-target distance in degrees
    if ~isnan(thisCueLocDeg) && ~isempty(nonTargetSiteDeg)
        cueToNonTargetDistDeg = mod(nonTargetSiteDeg - thisCueLocDeg, 360);
    else
        cueToNonTargetDistDeg = NaN;
    end

    % Split target into near/far
    if isnan(nonTargetCrossIdx)
        targetState = 'preReward_target_near';
    else
        targetState = 'preReward_target_far';
    end

    % ---------- target event ----------
    cp = get_crossing_position_cm( ...
        thisTargetRewardDeg, targetCrossIdx, session.pos_cm_unwrapped, cfg.track_cm);

    if cfg.lickNearRewardEnabled
        hasLickNearReward = check_lick_near_reward( ...
            thisRewardIdx, targetCrossIdx, thisTargetRewardDeg, ...
            session.pos_cm_unwrapped, session.lick, cfg.track_cm, cfg.lickNearRewardWindow_deg);

        if ~hasLickNearReward
            continue
        end
    end

    [approachSpeed, decelNearSpeed, decelControlSpeed, rawDecel] = get_event_metrics( ...
        cp, session.pos_cm_RS, session.speed_cm_s, ...
        cfg.speedWindow_cm, cfg.decelPreWindow_cm, cfg.decelControlWindow_cm, ...
        cfg.excludeFinal_cm, cfg.summaryFcn);

    if ~isnan(approachSpeed) || ~isnan(rawDecel)

        eventCounter = eventCounter + 1;

        eventRows(end+1,:) = { ...
            session.label, ...
            'cueToReward', ...
            intervalCounter, ...
            eventCounter, ...
            thisTargetRewardDeg, ...
            sprintf('%.0fdeg_site', thisTargetRewardDeg), ...
            targetState, ...
            thisCueVal, ...
            thisCueName, ...
            thisCueOn, ...
            thisCueOff, ...
            thisCueTrackDeg, ...
            thisCueLocDeg, ...
            thisTargetRewardDeg, ...
            thisRewardIdx, ...
            thisRewardSiteDeg, ...
            targetCrossIdx, ...
            approachSpeed, ...
            decelNearSpeed, ...
            decelControlSpeed, ...
            rawDecel}; %#ok<AGROW>

        profileSpeed = get_speed_profile_before_site( ...
            cp, session.pos_cm_RS, session.speed_cm_s, ...
            cfg.track_cm, cfg.profileEdges_deg, cfg.summaryFcn);

        if strcmp(targetState, 'preReward_target_near')
            if cueToTargetDistDeg == 60
                scenarioLabel = 'preReward_target_near_60';
            elseif cueToTargetDistDeg == 150
                scenarioLabel = 'preReward_target_near_150';
            else
                scenarioLabel = 'preReward_target_near_other';
            end
        elseif strcmp(targetState, 'preReward_target_far')
            if cueToTargetDistDeg == 240
                scenarioLabel = 'preReward_target_far_240';
            elseif cueToTargetDistDeg == 330
                scenarioLabel = 'preReward_target_far_330';
            else
                scenarioLabel = 'preReward_target_far_other';
            end
        else
            scenarioLabel = targetState;
        end

        profileSpeedMat(end+1,:) = profileSpeed; %#ok<AGROW>
        profileSiteDeg(end+1,1) = thisTargetRewardDeg; %#ok<AGROW>
        profileState{end+1,1} = targetState; %#ok<AGROW>
        profileScenario{end+1,1} = scenarioLabel; %#ok<AGROW>
    end

    % ---------- non-target event ----------
    if ~isempty(nonTargetSiteDeg) && ~isnan(nonTargetCrossIdx)

        cp = get_crossing_position_cm( ...
            nonTargetSiteDeg, nonTargetCrossIdx, session.pos_cm_unwrapped, cfg.track_cm);

        [approachSpeed, decelNearSpeed, decelControlSpeed, rawDecel] = get_event_metrics( ...
            cp, session.pos_cm_RS, session.speed_cm_s, ...
            cfg.speedWindow_cm, cfg.decelPreWindow_cm, cfg.decelControlWindow_cm, ...
            cfg.excludeFinal_cm, cfg.summaryFcn);

        if ~isnan(approachSpeed) || ~isnan(rawDecel)

            eventCounter = eventCounter + 1;

            eventRows(end+1,:) = { ...
                session.label, ...
                'cueToReward', ...
                intervalCounter, ...
                eventCounter, ...
                nonTargetSiteDeg, ...
                sprintf('%.0fdeg_site', nonTargetSiteDeg), ...
                'preReward_nonTarget', ...
                thisCueVal, ...
                thisCueName, ...
                thisCueOn, ...
                thisCueOff, ...
                thisCueTrackDeg, ...
                thisCueLocDeg, ...
                thisTargetRewardDeg, ...
                thisRewardIdx, ...
                thisRewardSiteDeg, ...
                nonTargetCrossIdx, ...
                approachSpeed, ...
                decelNearSpeed, ...
                decelControlSpeed, ...
                rawDecel}; %#ok<AGROW>

            profileSpeed = get_speed_profile_before_site( ...
                cp, session.pos_cm_RS, session.speed_cm_s, ...
                cfg.track_cm, cfg.profileEdges_deg, cfg.summaryFcn);

            if cueToNonTargetDistDeg == 60
                scenarioLabel = 'preReward_nonTarget_60';
            elseif cueToNonTargetDistDeg == 150
                scenarioLabel = 'preReward_nonTarget_150';
            else
                scenarioLabel = 'preReward_nonTarget_other';
            end

            profileSpeedMat(end+1,:) = profileSpeed; %#ok<AGROW>
            profileSiteDeg(end+1,1) = nonTargetSiteDeg; %#ok<AGROW>
            profileState{end+1,1} = 'preReward_nonTarget'; %#ok<AGROW>
            profileScenario{end+1,1} = scenarioLabel; %#ok<AGROW>
        end
    end
end

%% ===================== 2) REWARD -> NEXT CUE INTERVALS =====================
for r = 1:numel(rewards.rewardOnsetIdx)

    thisRewardIdx = rewards.rewardOnsetIdx(r);

    cNext = find(cues.cueOnsetIdx > thisRewardIdx, 1, 'first');
    if isempty(cNext)
        continue
    end

    thisCueOn = cues.cueOnsetIdx(cNext);

    idxStart = thisRewardIdx;
    idxEnd   = thisCueOn;

    if idxEnd <= idxStart + 1
        continue
    end

    intervalCounter = intervalCounter + 1;

    for s = 1:numel(cfg.activeReward_deg)

        thisSiteDeg = cfg.activeReward_deg(s);
        crossIdx = find_last_crossing( ...
            thisSiteDeg, idxStart, idxEnd, session.pos_cm_unwrapped, cfg.track_cm);

        if isnan(crossIdx)
            continue
        end

        cp = get_crossing_position_cm( ...
            thisSiteDeg, crossIdx, session.pos_cm_unwrapped, cfg.track_cm);

        [approachSpeed, decelNearSpeed, decelControlSpeed, rawDecel] = get_event_metrics( ...
            cp, session.pos_cm_RS, session.speed_cm_s, ...
            cfg.speedWindow_cm, cfg.decelPreWindow_cm, cfg.decelControlWindow_cm, ...
            cfg.excludeFinal_cm, cfg.summaryFcn);

        if isnan(approachSpeed) && isnan(rawDecel)
            continue
        end

        eventCounter = eventCounter + 1;

        eventRows(end+1,:) = { ...
            session.label, ...
            'cueExpected', ...
            intervalCounter, ...
            eventCounter, ...
            thisSiteDeg, ...
            sprintf('%.0fdeg_site', thisSiteDeg), ...
            'cue_expected', ...
            NaN, ...
            '', ...
            NaN, ...
            NaN, ...
            NaN, ...
            NaN, ...
            NaN, ...
            thisRewardIdx, ...
            rewards.rewardSiteDeg(r), ...
            crossIdx, ...
            approachSpeed, ...
            decelNearSpeed, ...
            decelControlSpeed, ...
            rawDecel}; %#ok<AGROW>

        profileSpeed = get_speed_profile_before_site( ...
            cp, session.pos_cm_RS, session.speed_cm_s, ...
            cfg.track_cm, cfg.profileEdges_deg, cfg.summaryFcn);

        profileSpeedMat(end+1,:) = profileSpeed; %#ok<AGROW>
        profileSiteDeg(end+1,1) = thisSiteDeg; %#ok<AGROW>
        profileState{end+1,1} = 'cue_expected'; %#ok<AGROW>
        profileScenario{end+1,1} = 'cue_expected'; %#ok<AGROW>
    end
end

end