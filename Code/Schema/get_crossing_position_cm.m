function cp = get_crossing_position_cm(siteDeg, crossIdx, pos_cm_unwrapped, track_cm)

site_cm = siteDeg / 360 * track_cm;

cp = site_cm + ...
     round((pos_cm_unwrapped(crossIdx) - site_cm) / track_cm) * track_cm;

end