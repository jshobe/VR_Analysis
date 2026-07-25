function speed_cm_s = compute_window_speed(t, pos_cm_unwrapped, speedWindow_cm)

speed_cm_s = nan(size(pos_cm_unwrapped));

for i = 1:numel(pos_cm_unwrapped)
    targetPos = pos_cm_unwrapped(i) - speedWindow_cm;

    j = find(pos_cm_unwrapped <= targetPos, 1, 'last');

    if ~isempty(j) && t(i) > t(j)
        speed_cm_s(i) = ...
            (pos_cm_unwrapped(i) - pos_cm_unwrapped(j)) / ...
            (t(i) - t(j));
    end
end

speed_cm_s(~isfinite(speed_cm_s)) = NaN;

end