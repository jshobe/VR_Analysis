function shared = compute_shared_reward_centered_scales(Pall, cfg)
% COMPUTE_SHARED_REWARD_CENTERED_SCALES
% Calculates common display scales for all selected sessions.
%
% Returned fields:
%   heatmapCLim       [minimum maximum] speed color limits
%   speedYLim         [minimum maximum] speed y-axis
%   accelerationYLim  symmetric grouped-acceleration y-axis

nFiles = numel(Pall);

if nFiles < 1
    error('Pall is empty.');
end

%% Shared heatmap color scale
localColorMax = nan(nFiles, 1);

for f = 1:nFiles
    vals = Pall{f}.speedMat(isfinite(Pall{f}.speedMat));

    if isempty(vals)
        continue
    end

    if cfg.usePercentileColorMax
        localColorMax(f) = prctile(vals, cfg.colorMaxPercentile);
    else
        localColorMax(f) = max(vals);
    end
end

validColor = isfinite(localColorMax);

if ~any(validColor)
    error('No finite speed values were found for the heatmap scale.');
end

heatmapMax = max(localColorMax(validColor));
shared.heatmapCLim = [0 max(heatmapMax, eps)];

%% Shared speed y-axis
allSpeedValues = [];

showGroups = isfield(cfg, 'showSpeedLapBlockCurves') && ...
    cfg.showSpeedLapBlockCurves;

for f = 1:nFiles
    P = Pall{f};

    switch lower(cfg.outerSpeedStatistic)
        case 'mean'
            centerSpeed = mean(P.speedMat, 1, 'omitnan');

        case 'median'
            centerSpeed = median(P.speedMat, 1, 'omitnan');

        otherwise
            error('cfg.outerSpeedStatistic must be ''mean'' or ''median''.');
    end

    nPerBin = sum(isfinite(P.speedMat), 1);
    semSpeed = std(P.speedMat, 0, 1, 'omitnan') ./ sqrt(nPerBin);
    semSpeed(nPerBin == 0) = NaN;

    if cfg.smoothMeanSpeedBins > 1
        centerSpeed = movmean( ...
            centerSpeed, ...
            cfg.smoothMeanSpeedBins, ...
            'omitnan');

        semSpeed = movmean( ...
            semSpeed, ...
            cfg.smoothMeanSpeedBins, ...
            'omitnan');
    end

    lowerSpeed = centerSpeed - semSpeed;
    upperSpeed = centerSpeed + semSpeed;

    allSpeedValues = [ ...
        allSpeedValues, ...
        lowerSpeed(isfinite(lowerSpeed)), ...
        upperSpeed(isfinite(upperSpeed))]; %#ok<AGROW>

    if showGroups
        Gs = compute_speed_lap_group_curves(P, cfg);
        groupValues = Gs.meanSpeed(isfinite(Gs.meanSpeed));
        allSpeedValues = [ ...
            allSpeedValues, ...
            groupValues(:).']; %#ok<AGROW>
    end
end

if isempty(allSpeedValues)
    error('No finite speed values were found.');
end

speedMin = min(allSpeedValues);
speedMax = max(allSpeedValues);
speedRange = speedMax - speedMin;

speedPad = max(2, 0.10 * max(speedRange, 1));

speedYMin = max(0, floor(speedMin - speedPad));
speedYMax = ceil(speedMax + speedPad);

if speedYMax <= speedYMin
    speedYMax = speedYMin + 5;
end

shared.speedYLim = [speedYMin speedYMax];

%% Shared symmetric acceleration y-axis based on all lap-block curves
allAccelMagnitude = [];

for f = 1:nFiles

    G = compute_acceleration_lap_group_curves(Pall{f}, cfg);

    for g = 1:G.nGroups

        if cfg.showAccelerationGroupSEM
            lowerAccel = G.meanAccel(g, :) - G.semAccel(g, :);
            upperAccel = G.meanAccel(g, :) + G.semAccel(g, :);

            values = [ ...
                lowerAccel(isfinite(lowerAccel)), ...
                upperAccel(isfinite(upperAccel))];
        else
            curve = G.meanAccel(g, :);
            values = curve(isfinite(curve));
        end

        allAccelMagnitude = [ ...
            allAccelMagnitude, ...
            abs(values)]; %#ok<AGROW>
    end
end

if isempty(allAccelMagnitude)
    accelLimit = 1;
else
    accelLimit = 1.10 * max(allAccelMagnitude);
end

if accelLimit <= 10
    accelLimit = ceil(accelLimit);
elseif accelLimit <= 50
    accelLimit = ceil(accelLimit / 5) * 5;
else
    accelLimit = ceil(accelLimit / 10) * 10;
end

accelLimit = max(accelLimit, 1);

shared.accelerationYLim = [-accelLimit accelLimit];

end
