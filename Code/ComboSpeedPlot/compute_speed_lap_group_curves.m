function G = compute_speed_lap_group_curves(P, cfg)
% COMPUTE_SPEED_LAP_GROUP_CURVES
% Computes mean speed +/- SEM for the same consecutive lap groups used by
% the acceleration panel.

if ~isfield(P, 'speedMat')
    error('P.speedMat is missing.');
end

nTrials = size(P.speedMat, 1);

if isfield(P, 'trialNums') && numel(P.trialNums) == nTrials
    trialNums = P.trialNums;
else
    trialNums = 1:nTrials;
end

[groupStarts, groupEnds, groupSizesUsed, labels] = ...
    get_lap_group_ranges(trialNums, cfg);

nGroups = numel(groupStarts);
nBins = size(P.speedMat, 2);

meanSpeed = nan(nGroups, nBins);
semSpeed = nan(nGroups, nBins);

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

end

colors = cfg.accelerationGroupColors;

if size(colors, 1) < nGroups
    % cool() contains blue/cyan/magenta tones and avoids yellow.
    colors = cool(nGroups);
else
    colors = colors(1:nGroups, :);
end

G.meanSpeed = meanSpeed;
G.semSpeed = semSpeed;
G.labels = labels;
G.colors = colors;
G.groupStarts = groupStarts;
G.groupEnds = groupEnds;
G.groupSizes = groupSizesUsed;
G.nGroups = nGroups;

end
