function profileSpeed = get_speed_profile_before_site( ...
    cp, pos_cm_RS, speed_cm_s_RS, track_cm, profileEdges_deg, summaryFcn)

edges_cm = profileEdges_deg / 360 * track_cm;
nBins = numel(profileEdges_deg) - 1;

profileSpeed = nan(1, nBins);

rel_cm = pos_cm_RS - cp;

for b = 1:nBins
    binMask = rel_cm >= edges_cm(b) & rel_cm < edges_cm(b+1);
    vals = speed_cm_s_RS(binMask);
    vals = vals(~isnan(vals));

    if ~isempty(vals)
        profileSpeed(b) = summaryFcn(vals);
    end
end

end