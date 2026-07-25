function G = compute_speed_lap_group_curves(P, cfg)
% COMPUTE_SPEED_LAP_GROUP_CURVES
% Computes mean speed +/- SEM for the same consecutive lap blocks used by
% the acceleration panel.

if ~isfield(P, 'speedMat')
    error('P.speedMat is missing.');
end

if ~isfield(cfg, 'accelerationLapBlockSize') || ...
        ~isscalar(cfg.accelerationLapBlockSize) || ...
        cfg.accelerationLapBlockSize < 1 || ...
        mod(cfg.accelerationLapBlockSize, 1) ~= 0
    error('cfg.accelerationLapBlockSize must be a positive integer.');
end

nTrials = size(P.speedMat, 1);
blockSize = cfg.accelerationLapBlockSize;

groupStarts = 1:blockSize:nTrials;
groupEnds = min(groupStarts + blockSize - 1, nTrials);

nGroups = numel(groupStarts);
nBins = size(P.speedMat, 2);

meanSpeed = nan(nGroups, nBins);
semSpeed = nan(nGroups, nBins);
labels = cell(nGroups, 1);

for g = 1:nGroups

    rows = groupStarts(g):groupEnds(g);
    X = P.speedMat(rows, :);

    meanSpeed(g, :) = mean(X, 1, 'omitnan');

    nPerBin = sum(isfinite(X), 1);
    semSpeed(g, :) = std(X, 0, 1, 'omitnan') ./ sqrt(nPerBin);
    semSpeed(g, nPerBin == 0) = NaN;

    if cfg.smoothMeanSpeedBins > 1
        meanSpeed(g, :) = movmean( ...
            meanSpeed(g, :), ...
            cfg.smoothMeanSpeedBins, ...
            'omitnan');

        semSpeed(g, :) = movmean( ...
            semSpeed(g, :), ...
            cfg.smoothMeanSpeedBins, ...
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

G.meanSpeed = meanSpeed;
G.semSpeed = semSpeed;
G.labels = labels;
G.colors = colors;
G.groupStarts = groupStarts;
G.groupEnds = groupEnds;
G.nGroups = nGroups;
G.blockSize = blockSize;

end
