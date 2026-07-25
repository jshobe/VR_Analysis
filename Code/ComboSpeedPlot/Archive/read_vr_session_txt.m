function D = read_vr_session_txt(fname)

fid = fopen(fname, 'r');
if fid == -1
    error('Could not open file: %s', fname);
end

fgetl(fid);

C = textscan(fid, '%f%f%f%f%f%f%f%f%f', ...
    'TreatAsEmpty', {'NaN','nan'});

fclose(fid);

t       = C{1};
pos_deg = C{3};
reward  = C{6};
lick    = C{8};

valid = ~isnan(t) & ~isnan(pos_deg) & ~isnan(reward) & ~isnan(lick);

D.t       = t(valid);
D.pos_deg = pos_deg(valid);
D.reward  = reward(valid);
D.lick    = lick(valid);

if numel(D.t) < 2
    error('Not enough valid samples.');
end

end