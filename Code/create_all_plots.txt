function create_all_plots(rate_mean_halls, raster_data, halls, cluster_id_good, out_folder, varargin)
% CREATE_ALL_PLOTS
% Creates one PDF per region with one unit per page
% - Row 1: Position raster (all trials) with block separators
% - Rows 2+: Firing rate curves per block (stacked vertically)
%
% Key Options:
% 'Blocks'           : {12:174, 178:337, 341:520} - trial blocks
% 'BinEdges'         : 0:4:534 - spatial edges (cm)
% 'SmoothingWin'     : 1.5 - Gaussian sigma in cm (0 = no smoothing)
% 'SavePNGs'         : false - also save individual PNGs
% 'PNGDir'           : '' - optional PNG output directory
% 'PDFName'          : 'AllUnits_SpatialAnalysis.pdf'
% 'PDFContent'       : 'image' or 'vector' (validated here)
% 'ShowTrialIDs'     : false - show trial numbers on raster
% 'TitlePrefix'      : '' - prefix for unit titles
% 'LegendOutside'    : false - reserved
% 'UseParallel'      : true - parallel processing of units
% 'RasterMarkerSize' : 9 - size of raster dots
% NEW:
% 'SaveFIGs'         : false - also save MATLAB .fig per unit
% 'FIGDir'           : '' - optional FIG output directory

% Parse options
p = inputParser;
addParameter(p, 'Blocks', {12:174, 178:337});
addParameter(p, 'BinEdges', 0:4:534, @isnumeric);
addParameter(p, 'SmoothingWin', 1.5, @(v)isnumeric(v)&&isscalar(v)&&v>=0);
addParameter(p, 'SavePNGs', false, @islogical);
addParameter(p, 'PNGDir', '', @(s)ischar(s)||isstring(s));
addParameter(p, 'PDFName', 'AllUnits_SpatialAnalysis.pdf', @(s)ischar(s)||isstring(s));
addParameter(p, 'PDFContent', 'image', @(s)ischar(s)||isstring(s));
addParameter(p, 'ShowTrialIDs', false, @islogical);
addParameter(p, 'TitlePrefix', '', @(s)ischar(s)||isstring(s));
addParameter(p, 'LegendOutside', false, @islogical);
addParameter(p, 'UseParallel', true, @islogical);
addParameter(p, 'RasterMarkerSize', 9, @(v)isnumeric(v)&&isscalar(v)&&v>0);
% NEW options
addParameter(p, 'SaveFIGs', false, @islogical);
addParameter(p, 'FIGDir', '', @(s)ischar(s)||isstring(s));

parse(p, varargin{:});
opt = p.Results;

% Validate PDF content type
ct = lower(strtrim(char(opt.PDFContent)));
if ~ismember(ct, {'image','vector'})
    warning('[create_all_plots] Invalid PDFContent "%s". Using "image".', opt.PDFContent);
    ct = 'image';
end
opt.PDFContent = ct;

% Setup
if nargin < 5 || ~isfolder(out_folder), out_folder = pwd; end
region_folder = fileparts(out_folder);
if isempty(region_folder), region_folder = pwd; end

% Validate and clip blocks to valid trial range
nTrials = size(raster_data, 2);
Blocks = clip_blocks_to_trials(opt.Blocks, nTrials);
nBlocks = numel(Blocks);

% Ensure halls matches trial count
halls = halls(:);
if numel(halls) < nTrials
    halls = [halls; NaN(nTrials - numel(halls), 1)];
end

% Setup output paths
out_pdf = fullfile(out_folder, char(opt.PDFName));
if exist(out_pdf, 'file'), delete(out_pdf); end

png_dir = [];
if opt.SavePNGs
    png_dir = char(opt.PNGDir);
    if isempty(png_dir), png_dir = fullfile(out_folder, 'PNGs'); end
    if ~exist(png_dir, 'dir'), mkdir(png_dir); end
end

% NEW: FIG directory
fig_dir = [];
if opt.SaveFIGs
    fig_dir = char(opt.FIGDir);
    if isempty(fig_dir), fig_dir = fullfile(out_folder, 'FIGs'); end
    if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
end

% Spatial bins
binEdges = opt.BinEdges(:)';
binCenters = (binEdges(1:end-1) + binEdges(2:end)) / 2;
xMin = binEdges(1);
xMax = binEdges(end);

% Precompute trial counts per block/type
tt_counts = compute_trial_type_counts(Blocks, halls);

% Load metadata once
sc_all = load_spike_clusters(region_folder);
metadata_table = load_metadata_csv(region_folder);

% Process units
nUnits = numel(cluster_id_good);
temp_pdf_files = arrayfun(@(u) fullfile(tempdir, sprintf('unit_%04d_temp.pdf', u)), 1:nUnits, 'UniformOutput', false);
fprintf('[create_all_plots] Processing %d units...\n', nUnits);
tStart = tic;

% Parallel or serial processing
if opt.UseParallel && nUnits > 1
    if isempty(gcp('nocreate')), parpool('local'); end
    parfor unit = 1:nUnits
        process_unit(unit, cluster_id_good(unit), rate_mean_halls, raster_data, ...
            halls, Blocks, tt_counts, binCenters, xMin, xMax, sc_all, metadata_table, ...
            region_folder, opt, temp_pdf_files{unit}, png_dir, fig_dir, nBlocks);
    end
else
    for unit = 1:nUnits
        process_unit(unit, cluster_id_good(unit), rate_mean_halls, raster_data, ...
            halls, Blocks, tt_counts, binCenters, xMin, xMax, sc_all, metadata_table, ...
            region_folder, opt, temp_pdf_files{unit}, png_dir, fig_dir, nBlocks);
        if mod(unit, 10) == 0
            fprintf(' Progress: %d/%d (%.1f%%) - %.1f sec\n', unit, nUnits, 100*unit/nUnits, toc(tStart));
        end
    end
end

fprintf('[create_all_plots] Processing complete (%.1f sec, %.2f sec/unit)\n', toc(tStart), toc(tStart)/max(1,nUnits));

% Merge PDFs
fprintf('[create_all_plots] Merging PDFs...\n');
existing_pdfs = {};
missing_count = 0;
for u = 1:nUnits
    if exist(temp_pdf_files{u}, 'file')
        existing_pdfs{end+1} = temp_pdf_files{u}; %#ok<AGROW>
    else
        missing_count = missing_count + 1;
        if missing_count <= 5
            warning('[create_all_plots] Missing PDF for unit %d (cluster %g)', u, cluster_id_good(u));
        end
    end
end
if missing_count > 5
    fprintf('[create_all_plots] ... and %d more missing PDFs\n', missing_count - 5);
end
if isempty(existing_pdfs)
    error('[create_all_plots] No PDFs were created. Check errors above.');
end
fprintf('[create_all_plots] Found %d/%d PDFs to merge\n', numel(existing_pdfs), nUnits);

try
    merge_pdfs_ghostscript(existing_pdfs, out_pdf);
    cellfun(@(f) delete(f), existing_pdfs);
    if exist(out_pdf, 'file')
        info = dir(out_pdf);
        fprintf('[create_all_plots] SUCCESS: %s (%.1f MB)\n', out_pdf, info.bytes/1024^2);
    else
        error('[create_all_plots] Merge completed but output PDF not found');
    end
catch ME
    error('[create_all_plots] PDF merge failed: %s', ME.message);
end
end

%% ==================== Unit processing ====================
function process_unit(unit, clusterID, rate_mean_halls, raster_data, halls, ...
    Blocks, tt_counts, binCenters, xMin, xMax, sc_all, metadata_table, region_folder, opt, ...
    temp_pdf_file, png_dir, fig_dir, nBlocks)

% Create figure
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [100 100 1200 800]);

% Plot the multi-panel page
plot_unit_page(fig, unit, clusterID, rate_mean_halls, raster_data, halls, ...
    Blocks, tt_counts, binCenters, xMin, xMax, sc_all, metadata_table, region_folder, opt);

% Save per-unit PDF (image or vector content)
try
    exportgraphics(fig, temp_pdf_file, 'ContentType', opt.PDFContent, 'BackgroundColor', 'white');
catch ME
    warning('[create_all_plots] exportgraphics failed for unit %d: %s. Falling back to print.', unit, ME.message);
    try
        set(fig, 'PaperPositionMode', 'auto');
        print(fig, '-dpdf', temp_pdf_file);
    catch ME2
        warning('[create_all_plots] print -dpdf failed for unit %d: %s', unit, ME2.message);
    end
end

% Optional: Save per-unit PNG
if ~isempty(png_dir) && islogical(opt.SavePNGs) && opt.SavePNGs
    try
        png_file = fullfile(png_dir, sprintf('unit_%04d.png', unit));
        exportgraphics(fig, png_file, 'Resolution', 150, 'BackgroundColor', 'white');
    catch ME
        warning('[create_all_plots] Failed to save PNG for unit %d: %s', unit, ME.message);
    end
end

% NEW: Save MATLAB .fig (full fidelity) if requested
if ~isempty(fig_dir) && islogical(opt.SaveFIGs) && opt.SaveFIGs
    try
        fig_file = fullfile(fig_dir, sprintf('unit_%04d.fig', unit));
        savefig(fig, fig_file);
    catch ME
        warning('[create_all_plots] Failed to save FIG for unit %d: %s', unit, ME.message);
    end
end

% Close figure to free memory
close(fig);
end

%% ==================== Page plotting ====================
function plot_unit_page(fig, unit, clusterID, rate_mean_halls, raster_data, halls, ...
    Blocks, tt_counts, binCenters, xMin, xMax, sc_all, metadataTable, region_folder, opt)

nBlocks = numel(Blocks);

% Create tiled layout
tl = tiledlayout(fig, 1 + nBlocks, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% Row 1: Raster
axR = nexttile(tl, 1);
plot_raster(axR, raster_data, halls, unit, Blocks, xMin, xMax, opt.ShowTrialIDs, opt.RasterMarkerSize);
title(axR, 'Position Raster - All Trials');
xlim(axR, [xMin, xMax]);

% Rows 2+: Rate curves per block
axRates = plot_rate_curves(tl, rate_mean_halls, unit, Blocks, tt_counts, binCenters, xMin, xMax, nBlocks, opt);

% Shared y-limits across rate panels
set_shared_ylims(axRates);

% Title with metadata
add_title(tl, unit, clusterID, sc_all, metadataTable, opt);
end

function plot_raster(ax, raster_data, halls, unit, Blocks, xMin, xMax, showTrialIDs, markerSize)
hold(ax, 'on');
colors = get_trial_type_colormap();
nCols = size(raster_data, 2);
y = 1;
y_ticks = [];
y_labels = [];
block_starts = zeros(1, numel(Blocks));
block_ends = zeros(1, numel(Blocks));
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
            % Append to arrays
            nSpikes = numel(xs);
            all_x = [all_x; xs(:)]; %#ok<AGROW>
            all_y = [all_y; y*ones(nSpikes, 1)]; %#ok<AGROW>
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
    % Draw separator
    if b < numel(Blocks)
        plot(ax, [xMin, xMax], [y-0.5, y-0.5], 'k-', 'LineWidth', 1.2);
        y = y + 1;
    end
end

% Vectorized plotting
if ~isempty(all_x)
    scatter(ax, all_x, all_y, markerSize, all_colors, 'filled', 'MarkerEdgeColor', 'none');
end

% Formatting
xlabel(ax, 'Position (cm)');
ylabel(ax, 'Trial');
xlim(ax, [xMin, xMax]);
ylim(ax, [0.5, max(1.5, y-0.5)]);
set(ax, 'YDir', 'reverse');
grid(ax, 'on');

% Corridor boundaries
xline(ax, xMin + 133, 'k--', 'LineWidth', 0.5);
xline(ax, xMin + 266.5, 'k--', 'LineWidth', 0.5);
xline(ax, xMin + 400, 'k--', 'LineWidth', 0.5);

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

function axRates = plot_rate_curves(tl, rate_mean_halls, unit, Blocks, tt_counts, binCenters, xMin, xMax, nBlocks, opt)
axRates = gobjects(1, nBlocks);
cmap = get_trial_type_colormap();
lineStyle = repmat({'-'}, 1, 7);
lineWidth = 2 * ones(1, 7);
lineStyle{7} = '--';
lineWidth(7) = 1.0;

% Bin width in cm (assumes uniform bins from centers)
if numel(binCenters) >= 2
    binWidth_cm = binCenters(2) - binCenters(1);
else
    binWidth_cm = 4; % fallback
end
sigma_bins = max(0, opt.SmoothingWin) / binWidth_cm; % convert sigma from cm to bins

% Allowed trial types per block parity (retain legacy behavior)
allowedTTs = cell(1, nBlocks);
for b = 1:nBlocks
    if mod(b, 2) == 1
        allowedTTs{b} = [1 2 3 4 7]; % odd blocks
    else
        allowedTTs{b} = [1 2 5 6 7]; % even blocks
    end
end

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
    plottedLabels = {};
    for TT = allowedTTs{b}
        if tt_counts{b}(TT) == 0, continue; end
        r = get_unit_type_slice(Rb, unit, TT);
        if isempty(r) || ~any(isfinite(r)), continue; end

        % True Gaussian smoothing with sigma specified in cm (converted to bins)
        r = gaussian_smooth(r, sigma_bins);
        if ~any(isfinite(r)), continue; end

        % Plot
        h = plot(ax, binCenters, r, ...
            'Color', cmap(TT, :), 'LineStyle', lineStyle{TT}, ...
            'LineWidth', lineWidth(TT));
        plottedHandles(end+1) = h; %#ok<AGROW>
        plottedLabels{end+1} = sprintf('TT%d (n=%d)', TT, tt_counts{b}(TT)); %#ok<AGROW>
    end

    xlim(ax, [xMin, xMax]);
    xlabel(ax, 'Position (cm)');
    ylabel(ax, 'Firing Rate (Hz)');
    title(ax, sprintf('Block %d - Firing Rates', b));

    if ~isempty(plottedHandles)
        lg = legend(ax, plottedHandles, plottedLabels, 'Location', 'best');
        set(lg, 'AutoUpdate', 'off');
    end
end

fprintf('[plot] SmoothingWin=%.2f cm -> sigma_bins=%.2f\n', opt.SmoothingWin, sigma_bins);
end

function set_shared_ylims(axRates)
yMin = inf;
yMax = -inf;
for b = 1:numel(axRates)
    if ~isgraphics(axRates(b)), continue; end
    yl = ylim(axRates(b));
    yMin = min(yMin, yl(1));
    yMax = max(yMax, yl(2));
end
if isfinite(yMin) && isfinite(yMax)
    if yMin == yMax
        yMin = 0;
        yMax = max(1, yMax);
    end
    pad = 0.05 * (yMax - yMin);
    for b = 1:numel(axRates)
        if isgraphics(axRates(b))
            ylim(axRates(b), [yMin - pad, yMax + pad]);
        end
    end
end
end

function add_title(tl, unit, clusterID, sc_all, metadataTable, opt)
titleLine1 = sprintf('%sUnit %d | ClusterID: %g', char(opt.TitlePrefix), unit, clusterID);

% Get spike counts
[spikeCount_npy, spikeCount_csv] = get_spike_counts(sc_all, clusterID, metadataTable);

% Get metadata
[metaLine, hasMeta] = get_metadata_line(metadataTable, clusterID);

% Build alignment note
inSpike = NaN;
if ~isempty(sc_all)
    inSpike = any(sc_all == clusterID);
end
spikeInfo = '';
if ~isnan(spikeCount_npy) && ~isnan(spikeCount_csv)
    spikeInfo = sprintf(' | Spikes: NPY=%d, CSV=%d', spikeCount_npy, spikeCount_csv);
elseif ~isnan(spikeCount_npy)
    spikeInfo = sprintf(' | Spikes: NPY=%d', spikeCount_npy);
elseif ~isnan(spikeCount_csv)
    spikeInfo = sprintf(' | Spikes: CSV=%d', spikeCount_csv);
end
alignNote = sprintf('InSpikeFile:%s | Meta:%s%s', ...
    tern(isnan(inSpike), 'n/a', tern(inSpike, 'Yes', 'No')), ...
    tern(hasMeta, 'OK', 'No'), spikeInfo);

% Set title
if hasMeta
    sgtitle(tl, {titleLine1, metaLine, alignNote}, 'Interpreter', 'none');
else
    sgtitle(tl, {titleLine1, alignNote}, 'Interpreter', 'none');
end
end

%% ==================== Helper Functions ====================
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
[nUnits, nBins, nTypes] = size(Rb);
if unit > nUnits || TT > nTypes, return; end
r = squeeze(Rb(unit, :, TT));
r = r(:)'; % row vector
end

function y = gaussian_smooth(x, sigma_bins)
x = double(x(:)');
if ~isfinite(sigma_bins) || sigma_bins <= 0 || all(~isfinite(x))
    y = x;
    return;
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
if ~isempty(sc_all)
    spikeCount_npy = sum(sc_all == clusterID);
end
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
ok = false;
metaLine = '';
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

function Blocks = clip_blocks_to_trials(Blocks, nTrials)
for b = 1:numel(Blocks)
    bb = Blocks{b}(:);
    bb = bb(isfinite(bb) & bb >= 1 & bb <= nTrials);
    Blocks{b} = unique(bb, 'stable');
end
end

function tt_counts = compute_trial_type_counts(Blocks, halls)
nBlocks = numel(Blocks);
nTypes = 7;
tt_counts = cell(1, nBlocks);
for b = 1:nBlocks
    tt_counts{b} = zeros(1, nTypes);
    if isempty(Blocks{b}), continue; end
    hB = halls(Blocks{b});
    for TT = 1:nTypes
        tt_counts{b}(TT) = sum(hB == TT);
    end
end
end

function sc_all = load_spike_clusters(region_folder)
sc_all = [];
try
    sc_all = double(readNPY(fullfile(region_folder, 'spike_clusters.npy')));
catch
end
end

function metadata_table = load_metadata_csv(region_folder)
metadata_table = [];
try
    path_parts = strsplit(region_folder, filesep);
    animal_name = '';
    for p = 1:numel(path_parts)
        if ~isempty(regexp(path_parts{p}, '^VR\d+$', 'once'))
            animal_name = path_parts{p};
            break;
        end
    end
    if isempty(animal_name), return; end
    csv_path = fullfile(region_folder, 'UnitMetrics', sprintf('%s_GoodUnitInfo.csv', animal_name));
    if exist(csv_path, 'file')
        metadata_table = readtable(csv_path);
        fprintf('[metadata] Loaded %d units from CSV\n', height(metadata_table));
    end
catch
end
end

%% ==================== Robust Ghostscript Merge ====================
function merge_pdfs_ghostscript(pdf_list, output_pdf)
% Merge PDFs using Ghostscript in chunks to avoid Windows command-length limits.
% Also captures diagnostic output from Ghostscript for easier debugging.

if isempty(pdf_list)
    error('merge_pdfs_ghostscript:EmptyList', 'No input PDFs provided.');
end

% Ensure output folder exists
outDir = fileparts(output_pdf);
if ~isempty(outDir) && ~exist(outDir, 'dir'), mkdir(outDir); end

% Locate Ghostscript executable
gsExe = find_ghostscript_exe();
if isempty(gsExe)
    error('merge_pdfs_ghostscript:GSNotFound', ...
        'Ghostscript executable not found on PATH. Ensure gswin64c or gswin32c is installed and on PATH.');
end

% Normalize list to existing files
pdf_list = pdf_list(:)';
existsMask = cellfun(@(f) exist(f, 'file') == 2, pdf_list);
if ~all(existsMask)
    missing = pdf_list(~existsMask);
    warning('merge_pdfs_ghostscript:MissingInputs', 'Skipping %d missing PDFs (e.g., "%s").', sum(~existsMask), missing{1});
    pdf_list = pdf_list(existsMask);
end
if isempty(pdf_list)
    error('merge_pdfs_ghostscript:NoInputsRemain', 'All input PDFs were missing; nothing to merge.');
end

% Heuristic chunk size to avoid command-length limit.
chunkSize = 75;

% Create chunk PDFs
chunkFiles = {};
n = numel(pdf_list);
chunkIdx = 1;
i = 1;
while i <= n
    j = min(i + chunkSize - 1, n);
    chunkInputs = pdf_list(i:j);
    chunkOut = fullfile(tempdir, sprintf('pdf_chunk_%03d.pdf', chunkIdx));
    run_ghostscript_merge(gsExe, chunkOut, chunkInputs);
    chunkFiles{end+1} = chunkOut; %#ok<AGROW>
    chunkIdx = chunkIdx + 1;
    i = j + 1;
end

% If only one chunk, finalize
if numel(chunkFiles) == 1
    try
        copyfile(chunkFiles{1}, output_pdf);
        delete(chunkFiles{1});
        return;
    catch ME
        error('merge_pdfs_ghostscript:MoveFailed', 'Failed to finalize output: %s', ME.message);
    end
end

% Merge chunk PDFs into final
run_ghostscript_merge(gsExe, output_pdf, chunkFiles);

% Cleanup
for k = 1:numel(chunkFiles)
    if exist(chunkFiles{k}, 'file'), delete(chunkFiles{k}); end
end

% Verify output
if ~(exist(output_pdf, 'file') == 2)
    error('merge_pdfs_ghostscript:OutputMissing', 'Ghostscript merge completed but output file not found.');
end
end

function run_ghostscript_merge(gsExe, output_pdf, input_files)
% Run Ghostscript to merge input_files into output_pdf.
% Captures cmd output for diagnostics.

if isempty(input_files)
    error('run_ghostscript_merge:NoInputs', 'No input files to merge.');
end

% Quote paths
inputsQuoted = strjoin(cellfun(@(f) sprintf('"%s"', f), input_files, 'UniformOutput', false), ' ');
gsExeQuoted = sprintf('"%s"', gsExe);
outputQuoted = sprintf('"%s"', output_pdf);

% Build command (avoid -q so we can see errors)
cmd = sprintf('%s -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -sOutputFile=%s %s', gsExeQuoted, outputQuoted, inputsQuoted);
[status, cmdout] = system(cmd);
if status ~= 0
    % Try 32-bit variant if 64-bit fails
    if contains(lower(gsExe), 'gswin64c')
        cmd32 = strrep(cmd, gsExeQuoted, '"gswin32c"');
        [status2, cmdout2] = system(cmd32);
        if status2 == 0, return; end
        error('run_ghostscript_merge:GSFail', ...
            'Ghostscript merge failed.\n64-bit cmd:\n%s\nOutput:\n%s\n\n32-bit cmd:\n%s\nOutput:\n%s', ...
            cmd, cmdout, cmd32, cmdout2);
    else
        error('run_ghostscript_merge:GSFail', 'Ghostscript merge failed.\nCmd:\n%s\nOutput:\n%s', cmd, cmdout);
    end
end
end

function gsExe = find_ghostscript_exe()
% Try to locate Ghostscript (64-bit preferred)
gsExe = '';
[s64, out64] = system('where gswin64c');
if s64 == 0
    paths = strsplit(strtrim(out64), newline);
    gsExe = strtrim(paths{1});
    return;
end
[s32, out32] = system('where gswin32c');
if s32 == 0
    paths = strsplit(strtrim(out32), newline);
    gsExe = strtrim(paths{1});
    return;
end
% Try common install locations (adjust versions if needed)
candidates = {
    'C:\Program Files\gs\gs10.00.0\bin\gswin64c.exe'
    'C:\Program Files\gs\gs9.55.0\bin\gswin64c.exe'
    'C:\Program Files\gs\gs9.52\bin\gswin64c.exe'
    'C:\Program Files (x86)\gs\gs9.55.0\bin\gswin32c.exe'
};
for i = 1:numel(candidates)
    if exist(candidates{i}, 'file')
        gsExe = candidates{i};
        return;
        end
    end
end