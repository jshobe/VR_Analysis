function session = load_session_and_crop_laps(fname, cfg)

session = [];

[~, baseName, ext] = fileparts(fname);
thisFile = [baseName ext];

mouseTok = regexp(baseName, '(JB\d+)', 'tokens', 'once');
if ~isempty(mouseTok)
    mouseName = mouseTok{1};
else
    mouseName = 'UnknownMouse';
end

dateTok = regexp(baseName, '(\d{4}-\d{2}-\d{2})', 'tokens', 'once');
if ~isempty(dateTok)
    sessionDate = dateTok{1};
else
    sessionDate = 'UnknownDate';
end

sessionLabel = [mouseName '  ' sessionDate];

fid = fopen(fname, 'r');
if fid == -1
    warning('Could not open file: %s', thisFile);
    return
end

fgetl(fid);
C = textscan(fid, '%f%f%f%f%f%f%f%f%f', 'TreatAsEmpty', {'NaN','nan'});
fclose(fid);

if numel(C) < 9 || isempty(C{1})
    warning('Could not parse file: %s', thisFile);
    return
end

t               = C{1};
pos_deg         = C{3};
reward          = C{6};
brake           = C{7};
lick            = C{8};
blackout_cue_id = C{9};

valid = ~isnan(t) & ~isnan(pos_deg) & ~isnan(reward);
t               = t(valid);
pos_deg         = pos_deg(valid);
reward          = reward(valid);
brake           = brake(valid);
lick            = lick(valid);
blackout_cue_id = blackout_cue_id(valid);

if numel(t) < 10
    warning('Too few valid samples in file: %s', thisFile);
    return
end

pos_deg_wrapped  = mod(pos_deg, 360);
pos_cm_unwrapped = rad2deg(unwrap(deg2rad(pos_deg_wrapped))) / 360 * cfg.track_cm;

lapNumber = floor((pos_cm_unwrapped - pos_cm_unwrapped(1)) ./ cfg.track_cm) + 1;
totalLaps = lapNumber(end);

if totalLaps < 1
    warning('Could not determine laps in file: %s', thisFile);
    return
end

switch cfg.lapMode
    case 'entire'
        keepLap = true(size(lapNumber));
    case 'first'
        nKeep = max(1, ceil(totalLaps * cfg.lapPct / 100));
        keepLap = lapNumber <= nKeep;
    case 'last'
        nKeep = max(1, ceil(totalLaps * cfg.lapPct / 100));
        firstLapToKeep = max(1, totalLaps - nKeep + 1);
        keepLap = lapNumber >= firstLapToKeep;
    case 'custom'
        firstLapToKeep = max(1, floor(totalLaps * cfg.lapStartPct / 100) + 1);
        lastLapToKeep  = max(firstLapToKeep, ceil(totalLaps * cfg.lapEndPct / 100));
        keepLap = lapNumber >= firstLapToKeep & lapNumber <= lastLapToKeep;
    otherwise
        error('Unknown lapMode.');
end

t                = t(keepLap);
pos_deg          = pos_deg(keepLap);
pos_deg_wrapped  = pos_deg_wrapped(keepLap);
pos_cm_unwrapped = pos_cm_unwrapped(keepLap);
reward           = reward(keepLap);
brake            = brake(keepLap);
lick             = lick(keepLap);
blackout_cue_id  = blackout_cue_id(keepLap);

if numel(t) < 10
    warning('Too few samples remain after lap cropping in file: %s', thisFile);
    return
end

% ===== Arduino-compatible resampled speed reconstruction =====
resampleHz = 150;
resampleDt = 1 / resampleHz;

[t_unique, uix] = unique(t, 'stable');
pos_cm_unique   = pos_cm_unwrapped(uix);
brake_unique    = brake(uix);

if numel(t_unique) < 2
    warning('Too few unique timestamps after deduplication in file: %s', thisFile);
    return
end

t_RS = t_unique(1):resampleDt:t_unique(end);

if numel(t_RS) < 2
    warning('Too few resampled samples in file: %s', thisFile);
    return
end

pos_cm_RS = interp1(t_unique, pos_cm_unique, t_RS, 'linear');

if any(~isfinite(pos_cm_RS))
    pos_cm_RS = fillmissing(pos_cm_RS, 'linear', 'EndValues', 'nearest');
end

brake_RS = interp1(t_unique, double(brake_unique), t_RS, 'previous', 'extrap');
brake_RS = brake_RS > 0.5;

speed_cm_s_RS = abs(gradient(pos_cm_RS, t_RS));
speed_cm_s_RS(~isfinite(speed_cm_s_RS)) = NaN;

speed_cm_s_RS(brake_RS) = NaN;

if cfg.minSpeed_cm_s > 0
    speed_cm_s_RS(speed_cm_s_RS < cfg.minSpeed_cm_s) = NaN;
end

session.fileName = thisFile;
session.label = sessionLabel;

% raw cropped data
session.t = t;
session.pos_deg = pos_deg;
session.pos_deg_wrapped = pos_deg_wrapped;
session.pos_cm_unwrapped = pos_cm_unwrapped;
session.reward = reward;
session.brake = brake;
session.lick = lick;
session.blackout_cue_id = blackout_cue_id;

% resampled data for speed analysis
session.t_RS = t_RS(:);
session.pos_cm_RS = pos_cm_RS(:);
session.brake_RS = brake_RS(:);
session.speed_cm_s = speed_cm_s_RS(:);

end