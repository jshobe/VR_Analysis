function accel_cm_s2 = compute_window_acceleration( ...
    t, speed_cm_s, window_s, minPoints)
% COMPUTE_WINDOW_ACCELERATION
% Estimates signed acceleration from a speed-time trace using a local
% least-squares slope within a centered time window.
%
% Positive values indicate speeding up.
% Negative values indicate slowing down.
%
% This avoids direct sample-to-sample differencing, which is unstable when
% timestamps are irregular or contain very short intervals.

if nargin < 4 || isempty(minPoints)
    minPoints = 5;
end

t = t(:);
speed_cm_s = speed_cm_s(:);

if numel(t) ~= numel(speed_cm_s)
    error('t and speed_cm_s must have the same number of elements.');
end

if ~isscalar(window_s) || ~isfinite(window_s) || window_s <= 0
    error('window_s must be a positive finite scalar.');
end

if any(~isfinite(t))
    error('Time values must be finite.');
end

if any(diff(t) < 0)
    error('Time values must be nondecreasing.');
end

n = numel(t);
accel_cm_s2 = nan(n, 1);

valid = isfinite(speed_cm_s);

% Cumulative sums allow the local regression slope to be computed without
% repeatedly extracting and fitting each complete window.
m = double(valid);
y = speed_cm_s;
y(~valid) = 0;

cN  = [0; cumsum(m)];
cT  = [0; cumsum(t .* m)];
cY  = [0; cumsum(y)];
cTT = [0; cumsum((t.^2) .* m)];
cTY = [0; cumsum((t .* y))];

halfWindow = window_s / 2;

leftIdx = 1;
rightIdx = 0;

for i = 1:n

    if ~valid(i)
        continue
    end

    lowerTime = t(i) - halfWindow;
    upperTime = t(i) + halfWindow;

    while leftIdx < n && t(leftIdx) < lowerTime
        leftIdx = leftIdx + 1;
    end

    if rightIdx < i
        rightIdx = i;
    end

    while rightIdx < n && t(rightIdx + 1) <= upperTime
        rightIdx = rightIdx + 1;
    end

    a = leftIdx;
    b = rightIdx;

    nLocal = cN(b + 1) - cN(a);
    if nLocal < minPoints
        continue
    end

    sumT  = cT(b + 1)  - cT(a);
    sumY  = cY(b + 1)  - cY(a);
    sumTT = cTT(b + 1) - cTT(a);
    sumTY = cTY(b + 1) - cTY(a);

    denominator = nLocal * sumTT - sumT^2;

    if denominator <= eps(max(abs([nLocal * sumTT, sumT^2, 1])))
        continue
    end

    accel_cm_s2(i) = ...
        (nLocal * sumTY - sumT * sumY) / denominator;
end

end
