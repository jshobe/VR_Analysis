function save_occupancy_maps(animal_folder, occupancy_4cm, halls, Blocks, varargin)
% SAVE_OCCUPANCY_MAPS
% Save non–region-specific occupancy visualizations in the animal's Derived folder.
%
% Inputs:
%   animal_folder  : path to VR## folder
%   occupancy_4cm  : [nTrials x nBins] seconds per bin (NaN for masked bins)
%   halls          : [nTrials x 1] trial type codes (1..7)
%   Blocks         : 1xB cell array of trial-index vectors per block (optional; can be {})
%
% Name-Value options:
%   'BinEdges4cm'        : spatial bin edges (default: 0:4:534)
%   'PDFName'            : output PDF filename (default: 'Occupancy_Maps.pdf')
%   'SavePNGs'           : also save PNGs per panel (default: false)
%   'SpeedThresh'        : for labeling; used in behavior compute (default: NaN)
%   'UseMedianSpeedMask' : for labeling; used in behavior compute (default: [])
%
% Outputs:
%   - PDF and optional PNGs in <animal_folder>/Derived/Occupancy
%   - MAT file 'occupancy_artifacts.mat' with inputs and options

p = inputParser;
addParameter(p, 'BinEdges4cm', 0:4:534, @(v)isnumeric(v)&&isvector(v)&&numel(v)>=2&&issorted(v));
addParameter(p, 'PDFName', 'Occupancy_Maps.pdf', @(s)ischar(s)||isstring(s));
addParameter(p, 'SavePNGs', false, @islogical);
addParameter(p, 'SpeedThresh', NaN, @(x)isnumeric(x)&&isscalar(x));
addParameter(p, 'UseMedianSpeedMask', [], @(x)(islogical(x)&&isscalar(x)) || isempty(x));
parse(p, varargin{:});
opt = p.Results;

% Output folders
derived_dir   = fullfile(animal_folder, 'Derived');
occup_dir     = fullfile(derived_dir, 'Occupancy');
if ~exist(derived_dir, 'dir'), mkdir(derived_dir); end
if ~exist(occup_dir, 'dir'), mkdir(occup_dir); end

% Save a MAT with provenance
try
    BinEdges4cm = opt.BinEdges4cm; %#ok<NASGU>
    SpeedThresh = opt.SpeedThresh;  %#ok<NASGU>
    UseMedianSpeedMask = opt.UseMedianSpeedMask; %#ok<NASGU>
    save(fullfile(occup_dir, 'occupancy_artifacts.mat'), ...
        'occupancy_4cm', 'halls', 'Blocks', 'BinEdges4cm', ...
        'SpeedThresh', 'UseMedianSpeedMask', '-v7.3');
catch ME
    fprintf('[occupancy] Warning: failed to save artifacts MAT (%s)\n', ME.message);
end

% Common geometry
binEdges   = opt.BinEdges4cm(:)';
binCenters = (binEdges(1:end-1) + binEdges(2:end))/2;
nTrials    = size(occupancy_4cm, 1);
nBins      = size(occupancy_4cm, 2);

% Build multipage PDF
pdf_path = fullfile(occup_dir, char(opt.PDFName));
if exist(pdf_path, 'file'), delete(pdf_path); end

% Panel 1: Per-trial occupancy heatmap with NaNs in light gray
fig1 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [50 50 1200 800]);
ax1  = axes(fig1);
data = occupancy_4cm; % seconds per bin
imagesc(ax1, binCenters, 1:nTrials, data);
set(ax1,'YDir','normal'); colormap(ax1, parula);
cb = colorbar(ax1); cb.Label.String = 'Seconds per bin';
xlabel(ax1, 'Position (cm)'); ylabel(ax1, 'Trial');
title(ax1, compose_title('Occupancy by trial', opt.SpeedThresh, opt.UseMedianSpeedMask));
% Show NaNs in light gray via transparency
set(get(ax1,'Children'), 'AlphaData', ~isnan(data));
set(ax1, 'Color', [0.95 0.95 0.95]);
% Block separators if provided
if ~isempty(Blocks) && iscell(Blocks)
    hold(ax1,'on');
    ysep = [];
    for b = 1:numel(Blocks)
        trials = Blocks{b}(:);
        trials = trials(trials>=1 & trials<=nTrials);
        if isempty(trials), continue; end
        ysep(end+1,:) = [min(trials) max(trials)]; %#ok<AGROW>
        xline(ax1, binEdges(1), 'k-'); % left border
    end
    for b = 1:size(ysep,1)-1
        yline(ax1, ysep(b,2)+0.5, 'k--', 'LineWidth', 1);
    end
end
exportgraphics(fig1, pdf_path, 'ContentType', 'image', 'BackgroundColor', 'white');
if opt.SavePNGs
    exportgraphics(fig1, fullfile(occup_dir, 'occupancy_heatmap.png'), 'Resolution', 150, 'BackgroundColor', 'white');
end
close(fig1);

% Panel 2: Session-wide mean occupancy curves by trial type
fig2 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [50 50 1200 800]);
tl = tiledlayout(fig2, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax2 = nexttile(tl,1); hold(ax2,'on'); grid(ax2,'on');
colors = lines(7);
labels = arrayfun(@(tt) sprintf('TT%d', tt), 1:7, 'UniformOutput', false);
for tt = 1:7
    tr_ix = find(halls(:) == tt);
    if isempty(tr_ix), continue; end
    m = nanmean(occupancy_4cm(tr_ix, :), 1);
    plot(ax2, binCenters, m, 'Color', colors(tt,:), 'LineWidth', 2);
end
xlabel(ax2, 'Position (cm)'); ylabel(ax2, 'Mean occupancy (s/bin)');
legend(ax2, labels, 'Location', 'best'); title(ax2, 'Session-wide mean occupancy by trial type');

% Panel 3: Per-block mean occupancy (if Blocks provided)
ax3 = nexttile(tl,2); hold(ax3,'on'); grid(ax3,'on');
if ~isempty(Blocks) && iscell(Blocks)
    for b = 1:numel(Blocks)
        tr = Blocks{b}(:);
        tr = tr(tr>=1 & tr<=nTrials);
        if isempty(tr), continue; end
        m = nanmean(occupancy_4cm(tr, :), 1);
        plot(ax3, binCenters, m, 'LineWidth', 2, 'DisplayName', sprintf('Block %d', b));
    end
    legend(ax3, 'Location', 'best');
end
xlabel(ax3, 'Position (cm)'); ylabel(ax3, 'Mean occupancy (s/bin)');
title(ax3, 'Per-block mean occupancy (all trial types)');

exportgraphics(fig2, pdf_path, 'ContentType', 'image', 'BackgroundColor', 'white', 'Append', true);
if opt.SavePNGs
    exportgraphics(fig2, fullfile(occup_dir, 'occupancy_means.png'), 'Resolution', 150, 'BackgroundColor', 'white');
end
close(fig2);

fprintf('[occupancy] Saved PDF: %s\n', pdf_path);
end

function t = compose_title(base, speedThresh, useMask)
parts = {base};
if isfinite(speedThresh), parts{end+1} = sprintf('SpeedThresh=%.3f cm/s', speedThresh); end
if ~isempty(useMask) && islogical(useMask), parts{end+1} = sprintf('UseMedianSpeedMask=%d', useMask); end
t = strjoin(parts, ' | ');
end