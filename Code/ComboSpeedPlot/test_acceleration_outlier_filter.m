function test_acceleration_outlier_filter()
% TEST_ACCELERATION_OUTLIER_FILTER
% Confirms that isolated lap-level spikes are removed without smoothing or
% altering a large acceleration feature shared across laps.

nLaps = 25;
nBins = 7;

lapOffset = linspace(-2, 2, nLaps).';
positionProfile = [0 5 10 40 10 5 0];
X = lapOffset + positionProfile;

% Two isolated artificial spikes.
X(4, 2) = 1000;
X(20, 6) = -1000;

% Preserve the input for a non-modification check.
Xoriginal = X;

[Xfiltered, mask, stats] = ...
    filter_acceleration_outliers_by_position(X, 5, 8);

assert(isequaln(X, Xoriginal), ...
    'The source acceleration matrix was modified.');

assert(mask(4, 2), ...
    'The positive artificial spike was not detected.');

assert(mask(20, 6), ...
    'The negative artificial spike was not detected.');

assert(isnan(Xfiltered(4, 2)) && isnan(Xfiltered(20, 6)), ...
    'Detected spikes were not replaced by NaN.');

assert(~any(mask(:, 4)), ...
    'A shared position-specific acceleration feature was removed.');

assert(stats.nRemoved == nnz(mask), ...
    'The audit count does not match the outlier mask.');

fprintf(['test_acceleration_outlier_filter passed: ' ...
    '%d isolated values removed.\n'], stats.nRemoved);

end
