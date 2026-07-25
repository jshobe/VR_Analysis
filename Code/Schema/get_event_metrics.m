function [approachSpeed, decelNearSpeed, decelControlSpeed, rawDecel] = get_event_metrics( ...
    cp, pos_cm_RS, speed_cm_s_RS, ...
    speedWindow_cm, decelPreWindow_cm, decelControlWindow_cm, ...
    excludeFinal_cm, summaryFcn)

speedMask = pos_cm_RS >= (cp - excludeFinal_cm - speedWindow_cm) & ...
            pos_cm_RS <  (cp - excludeFinal_cm);

decelNearMask = pos_cm_RS >= (cp - excludeFinal_cm - decelPreWindow_cm) & ...
                pos_cm_RS <  (cp - excludeFinal_cm);

decelControlMask = pos_cm_RS >= (cp - decelControlWindow_cm(2)) & ...
                   pos_cm_RS <  (cp - decelControlWindow_cm(1));

speedVals = speed_cm_s_RS(speedMask);
speedVals = speedVals(~isnan(speedVals));

decelNearVals = speed_cm_s_RS(decelNearMask);
decelNearVals = decelNearVals(~isnan(decelNearVals));

decelControlVals = speed_cm_s_RS(decelControlMask);
decelControlVals = decelControlVals(~isnan(decelControlVals));

if isempty(speedVals)
    approachSpeed = NaN;
else
    approachSpeed = summaryFcn(speedVals);
end

if isempty(decelNearVals)
    decelNearSpeed = NaN;
else
    decelNearSpeed = summaryFcn(decelNearVals);
end

if isempty(decelControlVals)
    decelControlSpeed = NaN;
else
    decelControlSpeed = summaryFcn(decelControlVals);
end

if isnan(decelNearSpeed) || isnan(decelControlSpeed)
    rawDecel = NaN;
else
    rawDecel = decelControlSpeed - decelNearSpeed;
end

end