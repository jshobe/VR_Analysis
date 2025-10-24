function legacy_plot_unit_page(fig, unit, clusterID, rate_mean_halls, raster_data, halls, ...
    Blocks, tt_counts, binCenters, xMin, xMax, sc_all, metadataTable, opt, unit_spike_counts)
% LEGACY_PLOT_UNIT_PAGE
% One page per unit: raster + rate panels per block, with informative labels via get_scene_lookup.
%
% NEW: unit_spike_counts parameter (optional) - [7 x nBlocks] spike counts per type per block

% Handle optional spike counts
if nargin < 14
    unit_spike_counts = [];
end

nBlocks = numel(Blocks);

% Tiled layout
tl = tiledlayout(fig, 1 + nBlocks, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% Row 1: Raster
axR = nexttile(tl, 1);
plot_raster_legacy(axR, raster_data, halls, unit, Blocks, xMin, xMax, opt.ShowTrialIDs, opt.RasterMarkerSize);
title(axR, 'Position Raster - All Trials');
xlim(axR, [xMin, xMax]);

% Rows 2+: Rate curves per block (with scene labels and spike counts)
axRates = plot_rate_curves_legacy(tl, rate_mean_halls, unit, Blocks, tt_counts, binCenters, xMin, xMax, nBlocks, opt, unit_spike_counts);

% Shared y-limits across rate panels
set_shared_ylims(axRates);

% Title with metadata
add_title_legacy(tl, unit, clusterID, sc_all, metadataTable, opt);
end

%% ==================== Plotting functions ====================
function plot_raster_legacy(ax, raster_data, halls, unit, Blocks, xMin, xMax, showTrialIDs, markerSize)
hold(ax, 'on');
colors = get_trial_type_colormap();
nCols = size(raster_data, 2);
y = 1;
y_ticks = [];
y_labels = [];
block_starts = zeros(1, numel(Blocks));
block_ends   = zeros(1, numel(Blocks));
block_spike_counts = zeros(1, numel(Blocks));

% Collect all spikes for vectorized plotting
all_x = [];
all_y = [];
all_colors = [];

for b = 1:numel(Blocks)
    block_starts(b) = y;
    trials = Blocks{b}(:);
    block_spikes = 0;
    for k = 1:numel(trials)
        tr = trials(k);
        if tr < 1 || tr > nCols || unit < 1 || unit > size(raster_data, 1)
            y = y + 1;
            continue;
        end
        C = raster_data{unit, tr};
        if isempty(C) || ~isfield(C, 'positions') || isempty(C.positions)
            y = y + 1;
            continue;
        end
        xs = C.positions;
        if ~isempty(xs)
            % Determine color
            col = [0.5 0.5 0.5];
            if tr <= numel(halls) && isfinite(halls(tr)) && halls(tr) >= 1 && halls(tr) <= 7
                col = colors(halls(tr), :);
            end
            nSpikes  = numel(xs);
            all_x    = [all_x; xs(:)]; %#ok<AGROW>
            all_y    = [all_y; y*ones(nSpikes, 1)]; %#ok<AGROW>
            all_colors = [all_colors; repmat(col, nSpikes, 1)]; %#ok<AGROW>
            block_spikes = block_spikes + nSpikes;
        end
        if showTrialIDs
            y_ticks(end+1) = y; %#ok<AGROW>
            y_labels(end+1) = tr; %#ok<AGROW>
        end
        y = y + 1;
    end
    block_ends(b) = y - 1;
    block_spike_counts(b) = block_spikes;
    if b < numel(Blocks)
        plot(ax, [xMin, xMax], [y-0.5, y-0.5], 'k-', 'LineWidth', 1.2);
        y = y + 1;
    end
end

if ~isempty(all_x)
    scatter(ax, all_x, all_y, markerSize, all_colors, 'filled', 'MarkerEdgeColor', 'none');
end

xlabel(ax, 'Position (cm)');
ylabel(ax, 'Trial');
xlim(ax, [xMin, xMax]);
ylim(ax, [0.5, max(1.5, y-0.5)]);
set(ax, 'YDir', 'reverse');
grid(ax, 'on');

% Corridor boundaries (visual guides)
xline(ax, xMin + 266.5, 'k--', 'LineWidth', 1.0);

% Block labels
for b = 1:numel(Blocks)
    yMid = (block_starts(b) + block_ends(b)) / 2;
    text(ax, xMin + 50, yMid, sprintf('Block %d\n(%d spikes)', b, block_spike_counts(b)), ...
        'FontSize', 10, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
end

% Y-axis labels
if showTrialIDs && ~isempty(y_ticks)
    maxTicks = 30;
    if numel(y_ticks) > maxTicks
        idx = round(linspace(1, numel(y_ticks), maxTicks));
        set(ax, 'YTick', y_ticks(idx), 'YTickLabel', y_labels(idx));
    else
        set(ax, 'YTick', y_ticks, 'YTickLabel', y_labels);
    end
end
end

function axRates = plot_rate_curves_legacy(tl, rate_mean_halls, unit, Blocks, tt_counts, binCenters, xMin, xMax, nBlocks, opt, unit_spike_counts)
% Handle optional spike counts
if nargin < 11
    unit_spike_counts = [];
end

axRates = gobjects(1, nBlocks);
cmap = get_trial_type_colormap();
lineStyle = repmat({'-'}, 1, 7);
lineWidth = 2 * ones(1, 7);
lineStyle{7} = '--';
lineWidth(7) = 1.0;

% Bin width in cm
binWidth_cm = (numel(binCenters) >= 2) * (binCenters(2) - binCenters(1)) + (numel(binCenters) < 2) * 4;
sigma_bins = max(0, opt.SmoothingWin) / binWidth_cm; % convert sigma from cm to bins

% Allowed trial types per block parity (legacy behavior)
allowedTTs = cell(1, nBlocks);
for b = 1:nBlocks
    if mod(b, 2) == 1
        allowedTTs{b} = [1 2 3 4 7]; % odd blocks
    else
        allowedTTs{b} = [1 2 5 6 7]; % even blocks
    end
end

% Build label map per block via get_scene_lookup
for b = 1:nBlocks
    ax = nexttile(tl, b + 1);
    axRates(b) = ax;
    hold(ax, 'on');
    grid(ax, 'on');

    Rb = [];
    if iscell(rate_mean_halls) && numel(rate_mean_halls) >= b
        Rb = rate_mean_halls{b};
    end
    if isempty(Rb)
        title(ax, sprintf('Block %d - Firing Rates (no data)', b));
        xlim(ax, [xMin, xMax]);
        continue;
    end

    plottedHandles = gobjects(0);
    plottedLabels  = {};

    % Scene label lookup for this block
    try
        labelMap = get_scene_lookup(opt.FileNum, opt.IsEvenFile, b);
    catch
        % Fallback if helper is missing
        labelMap = containers.Map('KeyType','double','ValueType','char');
        labelMap(1) = 'Familiar A'; labelMap(2) = 'Familiar B';
        if mod(b,2)==1
            labelMap(3)='Novel C'; labelMap(4)='Novel D';
        else
            labelMap(5)='Swap C'; labelMap(6)='Swap D';
        end
        labelMap(7) = 'No objects';
    end

    for TT = allowedTTs{b}
        if tt_counts{b}(TT) == 0, continue; end
        r = get_unit_type_slice(Rb, unit, TT);
        if isempty(r) || ~any(isfinite(r)), continue; end
        r = gaussian_smooth(r, sigma_bins);
        if ~any(isfinite(r)), continue; end

        % Label text
        if isKey(labelMap, TT)
            labelStr = labelMap(TT);
        else
            labelStr = sprintf('TT%d', TT);
        end

        h = plot(ax, binCenters, r, 'Color', cmap(TT,:), 'LineStyle', lineStyle{TT}, 'LineWidth', lineWidth(TT));
        plottedHandles(end+1) = h; %#ok<AGROW>
        
        % Build legend label with spike counts (when available)
        if ~isempty(unit_spike_counts) && size(unit_spike_counts, 2) >= b && size(unit_spike_counts, 1) >= TT
            spike_count = unit_spike_counts(TT, b);
            plottedLabels{end+1} = sprintf('%s (n=%d, spikes=%d)', labelStr, tt_counts{b}(TT), spike_count); %#ok<AGROW>
        else
            plottedLabels{end+1} = sprintf('%s (n=%d)', labelStr, tt_counts{b}(TT)); %#ok<AGROW>
        end
    end

    xlim(ax, [xMin, xMax]);
    xlabel(ax, 'Position (cm)');
    ylabel(ax, 'Firing Rate (Hz)');

    % Block title includes concise set of labels
    if ~isempty(plottedLabels)
        title(ax, sprintf('Block %d - Firing Rates [%s]', b, strjoin(plottedLabels, ', ')));
    else
        title(ax, sprintf('Block %d - Firing Rates (no data)', b));
    end

    if ~isempty(plottedHandles)
        lg = legend(ax, plottedHandles, plottedLabels, 'Location', 'best');
        set(lg, 'AutoUpdate', 'off');
    end
end

fprintf('[plot] SmoothingWin=%.2f cm -> sigma_bins=%.2f\n', opt.SmoothingWin, sigma_bins);
end

function set_shared_ylims(axRates)
yMin = inf; yMax = -inf;
for b = 1:numel(axRates)
    if ~isgraphics(axRates(b)), continue; end
    yl = ylim(axRates(b));
    yMin = min(yMin, yl(1));
    yMax = max(yMax, yl(2));
end
if isfinite(yMin) && isfinite(yMax)
    if yMin == yMax, yMin = 0; yMax = max(1, yMax); end
    pad = 0.05 * (yMax - yMin);
    for b = 1:numel(axRates)
        if isgraphics(axRates(b)), ylim(axRates(b), [yMin - pad, yMax + pad]); end
    end
end
end

function add_title_legacy(tl, unit, clusterID, sc_all, metadataTable, opt)
titleLine1 = sprintf('%sUnit %d | ClusterID: %g', char(opt.TitlePrefix), unit, clusterID);

% Spike counts
[spikeCount_npy, spikeCount_csv] = get_spike_counts(sc_all, clusterID, metadataTable);

% Metadata line
[metaLine, hasMeta] = get_metadata_line(metadataTable, clusterID);

% Alignment note
inSpike = NaN;
if ~isempty(sc_all), inSpike = any(sc_all == clusterID); end
spikeInfo = '';
if ~isnan(spikeCount_npy) && ~isnan(spikeCount_csv)
    spikeInfo = sprintf(' | Spikes: NPY=%d, CSV=%d', spikeCount_npy, spikeCount_csv);
elseif ~isnan(spikeCount_npy)
    spikeInfo = sprintf(' | Spikes: NPY=%d', spikeCount_npy);
elseif ~isnan(spikeCount_csv)
    spikeInfo = sprintf(' | Spikes: CSV=%d', spikeCount_csv);
end
alignNote = sprintf('InSpikeFile:%s | Meta:%s%s', tern(isnan(inSpike),'n/a',tern(inSpike,'Yes','No')), tern(hasMeta,'OK','No'), spikeInfo);

% Title
if hasMeta
    sgtitle(tl, {titleLine1, metaLine, alignNote}, 'Interpreter', 'none');
else
    sgtitle(tl, {titleLine1, alignNote}, 'Interpreter', 'none');
end
end

%% ==================== Local helpers ====================
function cmap = get_trial_type_colormap()
cmap = [
    0.000, 0.447, 0.741; % TT1 familiar
    0.850, 0.325, 0.098; % TT2 familiar
    0.929, 0.694, 0.125; % TT3 novel (odd)
    0.494, 0.184, 0.556; % TT4 novel (odd)
    0.466, 0.674, 0.188; % TT5 swapped (even)
    0.301, 0.745, 0.933; % TT6 swapped (even)
    0.635, 0.078, 0.184  % TT7 no objects
];
end

function r = get_unit_type_slice(Rb, unit, TT)
r = [];
if isempty(Rb) || ndims(Rb) ~= 3, return; end
[nUnits, ~, nTypes] = size(Rb);
if unit > nUnits || TT > nTypes, return; end
r = squeeze(Rb(unit, :, TT));
r = r(:)'; % row vector
end

function y = gaussian_smooth(x, sigma_bins)
x = double(x(:)');
if ~isfinite(sigma_bins) || sigma_bins <= 0 || all(~isfinite(x))
    y = x; return;
end
halfWidth = ceil(3 * sigma_bins);
g = exp(-(((-halfWidth:halfWidth).^2) / (2 * sigma_bins^2)));
g = g / sum(g);
valid = isfinite(x);
xf = x; xf(~valid) = 0;
yNum = conv(xf, g, 'same');
yDen = conv(double(valid), g, 'same');
y = yNum ./ yDen;
y(yDen < 0.1) = NaN;
end

function [spikeCount_npy, spikeCount_csv] = get_spike_counts(sc_all, clusterID, metadataTable)
spikeCount_npy = NaN;
spikeCount_csv = NaN;
if ~isempty(sc_all), spikeCount_npy = sum(sc_all == clusterID); end
if isempty(metadataTable), return; end
try
    cidCol = metadataTable{:, 1};
    if iscell(cidCol), cidCol = str2double(string(cidCol)); end
    matchIdx = find(cidCol == clusterID, 1);
    if isempty(matchIdx), return; end
    if any(strcmpi(metadataTable.Properties.VariableNames, 'num_spikes'))
        val = metadataTable{matchIdx, 'num_spikes'};
    elseif width(metadataTable) >= 8
        val = metadataTable{matchIdx, 8};
    else
        return;
    end
    if iscell(val), val = val{1}; end
    if isnumeric(val) && isfinite(val)
        spikeCount_csv = round(val);
    elseif ischar(val) || isstring(val)
        num = str2double(val);
        if isfinite(num), spikeCount_csv = round(num); end
    end
catch
end
end

function [metaLine, ok] = get_metadata_line(metadataTable, clusterID)
ok = false; metaLine = '';
if isempty(metadataTable), return; end
try
    cidCol = metadataTable{:, 1};
    if iscell(cidCol), cidCol = str2double(string(cidCol)); end
    matchIdx = find(cidCol == clusterID, 1);
    if isempty(matchIdx), return; end
    ch = get_field(metadataTable, matchIdx, 'Channel', NaN);
    sh = get_field(metadataTable, matchIdx, 'Shank', NaN);
    dp = get_field(metadataTable, matchIdx, 'Depth', NaN);
    ct = get_field(metadataTable, matchIdx, 'CellType', "Unknown");
    rg = get_field(metadataTable, matchIdx, 'Region', "Unknown");
    metaLine = sprintf('Channel: %s | Shank: %s | Depth: %s µm | CellType: %s | Region: %s', ...
        num2str(ch), num2str(sh), num2str(dp), char(ct), char(rg));
    ok = true;
catch
end
end

function val = get_field(T, rowIdx, fieldName, defaultVal)
val = defaultVal;
if isempty(T) || rowIdx < 1 || rowIdx > height(T), return; end
varNames = T.Properties.VariableNames;
idx = find(strcmpi(varNames, fieldName), 1);
if isempty(idx), return; end
try
    val = T{rowIdx, idx};
    if iscell(val), val = val{1}; end
    if ischar(val), val = string(val); end
    if (isstring(val) || ischar(val)) && isnumeric(defaultVal)
        num = str2double(val);
        if isfinite(num), val = num; end
    end
catch
end
end

function s = tern(c, a, b)
if c, s = a; else, s = b; end
end