function accelMat = compute_spatial_acceleration_from_speed_matrix( ...
    speedMat, relativeCenters_deg, cfg)
% COMPUTE_SPATIAL_ACCELERATION_FROM_SPEED_MATRIX
% Estimates signed acceleration from each lap's spatial speed profile using
% a local polynomial fit and the one-dimensional identity:
%
%   acceleration = speed * d(speed)/d(position)
%
% The fit window is circular, so bins near -180/+180 use neighbors from the
% opposite end of the unfolded track. Missing center bins can be estimated
% from neighboring finite bins when enough points remain in the window.
%
% Required configuration fields:
%   cfg.track_cm
%   cfg.spatialAccelerationWindowBins   odd integer >= 3
%   cfg.spatialAccelerationPolyOrder    usually 2
%   cfg.spatialAccelerationMinPoints    >= polynomial order + 1

if ~ismatrix(speedMat) || isempty(speedMat)
    error('speedMat must be a nonempty two-dimensional matrix.');
end

relativeCenters_deg = relativeCenters_deg(:).';

[nLaps, nBins] = size(speedMat);

if numel(relativeCenters_deg) ~= nBins
    error('relativeCenters_deg must have one value per speed-matrix column.');
end

windowBins = cfg.spatialAccelerationWindowBins;
polyOrder = cfg.spatialAccelerationPolyOrder;
minPoints = cfg.spatialAccelerationMinPoints;

if ~isscalar(windowBins) || windowBins < 3 || ...
        mod(windowBins, 2) ~= 1 || mod(windowBins, 1) ~= 0
    error('cfg.spatialAccelerationWindowBins must be an odd integer >= 3.');
end

if windowBins > nBins
    error('The spatial acceleration window cannot exceed the number of bins.');
end

if ~isscalar(polyOrder) || polyOrder < 1 || ...
        mod(polyOrder, 1) ~= 0
    error('cfg.spatialAccelerationPolyOrder must be a positive integer.');
end

if polyOrder >= windowBins
    error('The polynomial order must be smaller than the window size.');
end

minimumRequired = polyOrder + 1;

if ~isscalar(minPoints) || minPoints < minimumRequired || ...
        minPoints > windowBins || mod(minPoints, 1) ~= 0
    error(['cfg.spatialAccelerationMinPoints must be an integer from ' ...
           '%d through %d.'], minimumRequired, windowBins);
end

% Convert the reward-centered degree coordinates to centimeters.
xCenters_cm = relativeCenters_deg / 360 * cfg.track_cm;
halfWindow = floor(windowBins / 2);
neighborOffsets = -halfWindow:halfWindow;

accelMat = nan(nLaps, nBins);

for lap = 1:nLaps

    speedCurve = speedMat(lap, :);

    for centerBin = 1:nBins

        neighborBins = mod( ...
            (centerBin - 1) + neighborOffsets, ...
            nBins) + 1;

        % Signed shortest circular displacement from the center bin.
        dx_cm = xCenters_cm(neighborBins) - xCenters_cm(centerBin);
        dx_cm = mod(dx_cm + cfg.track_cm/2, cfg.track_cm) ...
            - cfg.track_cm/2;

        localSpeed = speedCurve(neighborBins);

        good = isfinite(dx_cm) & isfinite(localSpeed);

        if sum(good) < minPoints
            continue
        end

        dxGood = dx_cm(good).';
        speedGood = localSpeed(good).';

        % Scale position before fitting to improve numerical conditioning.
        xScale = max(abs(dxGood));

        if ~isfinite(xScale) || xScale <= 0
            continue
        end

        z = dxGood / xScale;

        design = ones(numel(z), polyOrder + 1);

        for power = 1:polyOrder
            design(:, power + 1) = z .^ power;
        end

        if rank(design) < polyOrder + 1
            continue
        end

        coefficients = design \ speedGood;

        % At z = 0, the intercept is fitted speed at the center. The first
        % linear coefficient divided by xScale is d(speed)/d(position).
        fittedCenterSpeed = max(coefficients(1), 0);
        dSpeed_dPosition = coefficients(2) / xScale;

        accelMat(lap, centerBin) = ...
            fittedCenterSpeed * dSpeed_dPosition;
    end
end

end
