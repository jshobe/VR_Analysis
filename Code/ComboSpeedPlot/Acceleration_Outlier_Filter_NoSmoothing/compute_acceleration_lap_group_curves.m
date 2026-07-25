function G = compute_acceleration_lap_group_curves(P, cfg)
% COMPUTE_ACCELERATION_LAP_GROUP_CURVES
% Calculates signed-acceleration curves for sequential lap blocks.
%
% Default grouping:
%   Laps 1-25, 26-50, 51-75, and 76-100.
%
% Optional robust outlier rejection is performed independently at each
% spatial bin across the laps within each block. Detected values are set to
% NaN only in a temporary summary copy. P.accelMat is never modified.
%
% Required grouping field:
%   cfg.accelerationLapBlockSize
%
% Outlier fields:
%   cfg.removeAccelerationOutliers
%   cfg.accelerationOutlierThresholdRobustSD
%   cfg.accelerationOutlierMinLaps

if ~isfield(P, 'accelMat')
    error('P.accelMat is missing.');
end

if ~isfield(cfg, 'accelerationLapBlockSize') || ...
        ~isscalar(cfg.accelerationLapBlockSize) || ...
        cfg.accelerationLapBlockSize < 1 || ...
        mod(cfg.accelerationLapBlockSize, 1) ~= 0
    error('cfg.accelerationLapBlockSize must be a positive integer.');
end

if ~isfield(cfg, 'removeAccelerationOutliers')
    cfg.removeAccelerationOutliers = true;
end

if ~isfield(cfg, 'accelerationOutlierThresholdRobustSD')
    cfg.accelerationOutlierThresholdRobustSD = 5;
end

if ~isfield(cfg, 'accelerationOutlierMinLaps')
    cfg.accelerationOutlierMinLaps = 8;
end

nTrials = size(P.accelMat, 1);
blockSize = cfg.accelerationLapBlockSize;

groupStarts = 1:blockSize:nTrials;
groupEnds = min(groupStarts + blockSize - 1, nTrials);

nGroups = numel(groupStarts);
nBins = size(P.accelMat, 2);

meanAccel = nan(nGroups, nBins);
semAccel = nan(nGroups, nBins);
labels = cell(nGroups, 1);

filteredAccelMat = P.accelMat;
outlierMask = false(size(P.accelMat));
outliersRemovedPerGroup = zeros(nGroups, 1);
finiteValuesPerGroup = zeros(nGroups, 1);

for g = 1:nGroups

    rows = groupStarts(g):groupEnds(g);
    Xraw = P.accelMat(rows, :);
    X = Xraw;

    finiteValuesPerGroup(g) = nnz(isfinite(Xraw));

    if cfg.removeAccelerationOutliers && ...
            size(Xraw, 1) >= cfg.accelerationOutlierMinLaps

        [X, localMask] = filter_acceleration_outliers_by_position( ...
            Xraw, ...
            cfg.accelerationOutlierThresholdRobustSD, ...
            cfg.accelerationOutlierMinLaps);

        filteredAccelMat(rows, :) = X;
        outlierMask(rows, :) = localMask;
        outliersRemovedPerGroup(g) = nnz(localMask);
    end

    meanAccel(g, :) = mean(X, 1, 'omitnan');

    nPerBin = sum(isfinite(X), 1);
    semAccel(g, :) = std(X, 0, 1, 'omitnan') ./ sqrt(nPerBin);
    semAccel(g, nPerBin == 0) = NaN;

    % This remains available but no smoothing is introduced by the
    % outlier filter. Set cfg.smoothAccelerationBins = 1 for none.
    if cfg.smoothAccelerationBins > 1
        meanAccel(g, :) = movmean( ...
            meanAccel(g, :), ...
            cfg.smoothAccelerationBins, ...
            'omitnan');

        semAccel(g, :) = movmean( ...
            semAccel(g, :), ...
            cfg.smoothAccelerationBins, ...
            'omitnan');
    end

    labels{g} = sprintf( ...
        'Laps %d-%d', ...
        groupStarts(g), ...
        groupEnds(g));
end

colors = cfg.accelerationGroupColors;

if size(colors, 1) < nGroups
    colors = parula(nGroups);
else
    colors = colors(1:nGroups, :);
end

nFiniteValues = sum(finiteValuesPerGroup);
nOutliersRemoved = nnz(outlierMask);

G.meanAccel = meanAccel;
G.semAccel = semAccel;
G.labels = labels;
G.colors = colors;
G.groupStarts = groupStarts;
G.groupEnds = groupEnds;
G.nGroups = nGroups;
G.blockSize = blockSize;

% Audit outputs. The source matrix remains available in P.accelMat.
G.filteredAccelMat = filteredAccelMat;
G.outlierMask = outlierMask;
G.nOutliersRemoved = nOutliersRemoved;
G.outlierFraction = nOutliersRemoved / max(nFiniteValues, 1);
G.outliersRemovedPerGroup = outliersRemovedPerGroup;
G.finiteValuesPerGroup = finiteValuesPerGroup;
G.outlierFilterApplied = logical(cfg.removeAccelerationOutliers);
G.outlierThresholdRobustSD = ...
    cfg.accelerationOutlierThresholdRobustSD;
G.outlierMinLaps = cfg.accelerationOutlierMinLaps;

end
