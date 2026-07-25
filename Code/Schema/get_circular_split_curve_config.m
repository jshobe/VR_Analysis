function cfg = get_circular_split_curve_config()

cfg.track_cm = 540;

cfg.reward_deg_all = [0 90 180 270];
cfg.cue_deg_all    = [30 120 210 300];
%JB5 0 180  0 30 %JB2 90 270  60 90

cfg.activeReward_deg = [90 270];

cfg.cueIdentityValues = [60 90];
cfg.cueIdentityNames  = {'basketball','star'};
cfg.cueToRewardMap_deg = [90 270];

cfg.speedWindow_cm = 5;
cfg.decelPreWindow_cm = 5;
cfg.decelControlWindow_cm = [30 40];

cfg.excludeFinal_deg = 2;
cfg.excludeFinal_cm  = cfg.track_cm * cfg.excludeFinal_deg / 360;

cfg.profileWindow_deg = 90;
cfg.profileBin_deg    = 5;
cfg.profileEdges_deg   = -cfg.profileWindow_deg:cfg.profileBin_deg:-cfg.excludeFinal_deg;
cfg.profileCenters_deg = cfg.profileEdges_deg(1:end-1) + cfg.profileBin_deg/2;

cfg.minSpeed_cm_s = 2;

cfg.rewardTolerance_deg = 35;
cfg.cueTolerance_deg    = 35;
cfg.skipCueRewardMismatches = false;

cfg.axisFontSize   = 13;
cfg.labelFontSize  = 15;
cfg.titleFontSize  = 16;
cfg.legendFontSize = 11;

cfg.varNames = { ...
    'sessionName', ...
    'intervalType', ...
    'intervalNumber', ...
    'eventNumber', ...
    'siteDeg', ...
    'siteName', ...
    'state', ...
    'cueIdentityVal', ...
    'cueIdentityName', ...
    'cueOnsetIdx', ...
    'cueOffsetIdx', ...
    'cueTrackPosDeg', ...
    'cueLocationDeg', ...
    'targetRewardDeg', ...
    'rewardIdx', ...
    'rewardSiteDeg', ...
    'crossingIdx', ...
    'approachSpeed', ...
    'decelNearSpeed', ...
    'decelControlSpeed', ...
    'rawDecel'};

if numel(cfg.activeReward_deg) ~= 2
    error('activeReward_deg must contain exactly two reward locations.');
end

if numel(cfg.cueIdentityValues) ~= 2 || numel(cfg.cueToRewardMap_deg) ~= 2
    error('cueIdentityValues and cueToRewardMap_deg must each contain exactly two values.');
end

if ~all(ismember(cfg.cueToRewardMap_deg, cfg.activeReward_deg))
    error('cueToRewardMap_deg must map to the two active reward locations.');
end
end