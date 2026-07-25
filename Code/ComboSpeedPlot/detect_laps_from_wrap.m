function lapStartIdx = detect_laps_from_wrap(pos_deg)

lapStartIdx = [1; find(diff(pos_deg) < -180) + 1];

if numel(lapStartIdx) < 2
    error('No complete laps detected.');
end

end