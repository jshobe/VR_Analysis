function [Xfiltered, outlierMask, stats] = ...
    filter_acceleration_outliers_by_position(X, thresholdRobustSD, minLaps)
% FILTER_ACCELERATION_OUTLIERS_BY_POSITION
% Removes isolated lap-level acceleration outliers independently at each
% spatial bin. No spatial smoothing or interpolation is performed.
%
% For each position bin:
%   1. Find the median acceleration across laps.
%   2. Estimate robust spread as 1.4826 * MAD.
%   3. Mark values farther than thresholdRobustSD robust standard
%      deviations from the median.
%   4. Replace only those values with NaN in Xfiltered.
%
% Outliers are evaluated across laps at the SAME spatial location. This
% preserves acceleration patterns that are shared across laps, even when
% they are large, while excluding isolated lap-specific spikes.
%
% Inputs:
%   X                   laps x position-bins acceleration matrix
%   thresholdRobustSD   positive scalar; recommended default = 5
%   minLaps             minimum finite laps needed in a bin; default = 8
%
% Outputs:
%   Xfiltered           copy of X with detected outliers replaced by NaN
%   outlierMask         logical matrix, true only for removed values
%   stats               audit information

if nargin < 3
    error(['filter_acceleration_outliers_by_position requires X, ' ...
           'thresholdRobustSD, and minLaps.']);
end

if ~ismatrix(X) || isempty(X) || ~isnumeric(X)
    error('X must be a nonempty numeric two-dimensional matrix.');
end

if ~isscalar(thresholdRobustSD) || ...
        ~isfinite(thresholdRobustSD) || thresholdRobustSD <= 0
    error('thresholdRobustSD must be a positive finite scalar.');
end

if ~isscalar(minLaps) || ~isfinite(minLaps) || ...
        minLaps < 3 || mod(minLaps, 1) ~= 0
    error('minLaps must be an integer >= 3.');
end

[nLaps, nBins] = size(X);

if minLaps > nLaps
    error('minLaps cannot exceed the number of rows in X.');
end

Xfiltered = X;
outlierMask = false(size(X));
finiteBefore = isfinite(X);

centerPerBin = nan(1, nBins);
robustScalePerBin = nan(1, nBins);
nFinitePerBin = sum(finiteBefore, 1);

for b = 1:nBins

    rowIdx = find(finiteBefore(:, b));

    if numel(rowIdx) < minLaps
        continue
    end

    values = X(rowIdx, b);
    centerValue = median(values);
    absDeviation = abs(values - centerValue);

    % Convert median absolute deviation to a robust estimate of SD.
    robustScale = 1.4826 * median(absDeviation);

    % A zero MAD can occur when many values are identical. Use an IQR
    % estimate as a conservative fallback. If both spreads are zero, there
    % is no defensible scale for automated rejection, so leave the bin
    % unchanged rather than deleting values arbitrarily.
    if ~isfinite(robustScale) || robustScale <= eps(max(abs(values)) + 1)
        quartiles = prctile(values, [25 75]);
        robustScale = (quartiles(2) - quartiles(1)) / 1.349;
    end

    if ~isfinite(robustScale) || robustScale <= eps(max(abs(values)) + 1)
        continue
    end

    isOutlierLocal = ...
        abs(values - centerValue) > thresholdRobustSD * robustScale;

    if any(isOutlierLocal)
        rowsToRemove = rowIdx(isOutlierLocal);
        Xfiltered(rowsToRemove, b) = NaN;
        outlierMask(rowsToRemove, b) = true;
    end

    centerPerBin(b) = centerValue;
    robustScalePerBin(b) = robustScale;
end

nFiniteBefore = nnz(finiteBefore);
nRemoved = nnz(outlierMask);

stats.thresholdRobustSD = thresholdRobustSD;
stats.minLaps = minLaps;
stats.nLaps = nLaps;
stats.nBins = nBins;
stats.nFiniteBefore = nFiniteBefore;
stats.nRemoved = nRemoved;
stats.fractionRemoved = nRemoved / max(nFiniteBefore, 1);
stats.nFinitePerBin = nFinitePerBin;
stats.nRemovedPerBin = sum(outlierMask, 1);
stats.centerPerBin = centerPerBin;
stats.robustScalePerBin = robustScalePerBin;

end
