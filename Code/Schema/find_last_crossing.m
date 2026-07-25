function crossIdx = find_last_crossing(siteDeg, idxStart, idxEnd, pos_cm_unwrapped_local, track_cm_local)

crossIdx = NaN;

if idxEnd <= idxStart + 1
    return
end

site_cm = siteDeg / 360 * track_cm_local;
pseg = pos_cm_unwrapped_local(idxStart:idxEnd);

minPosSeg = min(pseg);
maxPosSeg = max(pseg);

lapStart = floor((minPosSeg - site_cm) / track_cm_local) - 1;
lapEnd   = ceil((maxPosSeg - site_cm) / track_cm_local) + 1;

crossings = [];

for lap = lapStart:lapEnd
    cp = site_cm + lap * track_cm_local;
    localIdx = find(pseg(1:end-1) < cp & pseg(2:end) >= cp);

    if ~isempty(localIdx)
        crossings = [crossings; idxStart - 1 + localIdx(:) + 1]; %#ok<AGROW>
    end
end

if ~isempty(crossings)
    crossIdx = crossings(end);
end

end