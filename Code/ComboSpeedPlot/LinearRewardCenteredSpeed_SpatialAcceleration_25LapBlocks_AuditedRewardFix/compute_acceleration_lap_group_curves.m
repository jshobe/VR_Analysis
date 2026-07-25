function G = compute_acceleration_lap_group_curves(P, cfg)
% COMPUTE_ACCELERATION_LAP_GROUP_CURVES
% Calculates signed-acceleration curves for sequential lap blocks.
%
% Default grouping:
%   Laps 1-25, 26-50, 51-75, and 76-100.
%
% The final group ends at the last plotted lap when fewer than a complete
% block remain. The block size is controlled by:
%
%   cfg.accelerationLapBlockSize

if ~isfield(P, 'accelMat')
    error('P.accelMat is missing.');
end

if ~isfield(cfg, 'accelerationLapBlockSize') || ...
        ~isscalar(cfg.accelerationLapBlockSize) || ...
        cfg.accelerationLapBlockSize < 1 || ...
        mod(cfg.accelerationLapBlockSize, 1) ~= 0
    error('cfg.accelerationLapBlockSize must be a positive integer.');
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

for g = 1:nGroups

    rows = groupStarts(g):groupEnds(g);
    X = P.accelMat(rows, :);

    meanAccel(g, :) = mean(X, 1, 'omitnan');

    nPerBin = sum(isfinite(X), 1);
    semAccel(g, :) = std(X, 0, 1, 'omitnan') ./ sqrt(nPerBin);
    semAccel(g, nPerBin == 0) = NaN;

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

G.meanAccel = meanAccel;
G.semAccel = semAccel;
G.labels = labels;
G.colors = colors;
G.groupStarts = groupStarts;
G.groupEnds = groupEnds;
G.nGroups = nGroups;
G.blockSize = blockSize;

end
