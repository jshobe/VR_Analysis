function create_all_plots(rate_mean_halls, raster_data, halls, cluster_id_good, out_folder, varargin)
% CREATE_ALL_PLOTS (refactored legacy)
% Orchestrates per-unit legacy plotting and merges a single PDF.
%
% New options:
% 'FileNum'                  : numeric file/session number used for label mapping (default: NaN)
% 'IsEvenFile'               : boolean parity of the file/session (default: false)
% 'SpikeCountsByTypeByBlock' : [nUnits x 7 x nBlocks] spike counts (optional)

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
% NEW
addParameter(p, 'SaveFIGs', false, @islogical);
addParameter(p, 'FIGDir', '', @(s)ischar(s)||isstring(s));
addParameter(p, 'FileNum', NaN, @(x)isnumeric(x)&&isscalar(x));
addParameter(p, 'IsEvenFile', false, @islogical);
addParameter(p, 'SpikeCountsByTypeByBlock', [], @(x)isempty(x)||isnumeric(x));  % NEW

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

% Validate and clip blocks
nTrials = size(raster_data, 2);
Blocks = clip_blocks_to_trials(opt.Blocks, nTrials);
nBlocks = numel(Blocks);

% Ensure halls length
halls = halls(:);
if numel(halls) < nTrials
    halls = [halls; NaN(nTrials - numel(halls), 1)];
end

% Output paths
out_pdf = fullfile(out_folder, char(opt.PDFName));
if exist(out_pdf, 'file'), delete(out_pdf); end

png_dir = [];
if opt.SavePNGs
    png_dir = char(opt.PNGDir);
    if isempty(png_dir), png_dir = fullfile(out_folder, 'PNGs'); end
    if ~exist(png_dir, 'dir'), mkdir(png_dir); end
end

fig_dir = [];
if opt.SaveFIGs
    fig_dir = char(opt.FIGDir);
    if isempty(fig_dir), fig_dir = fullfile(out_folder, 'FIGs'); end
    if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
end

% Spatial bins
binEdges   = opt.BinEdges(:)';
binCenters = (binEdges(1:end-1) + binEdges(2:end)) / 2;
xMin = binEdges(1);
xMax = binEdges(end);

% Trial counts per block/type
tt_counts = compute_trial_type_counts(Blocks, halls);

% Load metadata once (optional)
sc_all         = load_spike_clusters(region_folder);
metadata_table = load_metadata_csv(region_folder);

% Process units
nUnits = numel(cluster_id_good);
temp_pdf_files = arrayfun(@(u) fullfile(tempdir, sprintf('unit_%04d_temp.pdf', u)), 1:nUnits, 'UniformOutput', false);
fprintf('[create_all_plots] Processing %d units...\n', nUnits);
tStart = tic;

% Parallel or serial
if opt.UseParallel && nUnits > 1
    if isempty(gcp('nocreate')), parpool('local'); end
    parfor unit = 1:nUnits
        % Extract spike counts for this unit if provided
        unit_spike_counts = [];
        if ~isempty(opt.SpikeCountsByTypeByBlock)
            unit_spike_counts = squeeze(opt.SpikeCountsByTypeByBlock(unit, :, :)); % [7 x nBlocks]
        end
        
        process_unit(unit, cluster_id_good(unit), rate_mean_halls, raster_data, ...
            halls, Blocks, tt_counts, binCenters, xMin, xMax, sc_all, metadata_table, ...
            opt, temp_pdf_files{unit}, png_dir, fig_dir, nBlocks, unit_spike_counts);  % NEW arg
    end
else
    for unit = 1:nUnits
        % Extract spike counts for this unit if provided
        unit_spike_counts = [];
        if ~isempty(opt.SpikeCountsByTypeByBlock)
            unit_spike_counts = squeeze(opt.SpikeCountsByTypeByBlock(unit, :, :)); % [7 x nBlocks]
        end
        
        process_unit(unit, cluster_id_good(unit), rate_mean_halls, raster_data, ...
            halls, Blocks, tt_counts, binCenters, xMin, xMax, sc_all, metadata_table, ...
            opt, temp_pdf_files{unit}, png_dir, fig_dir, nBlocks, unit_spike_counts);  % NEW arg
        
        if mod(unit, 10) == 0
            fprintf(' Progress: %d/%d (%.1f%%) - %.1f sec\n', unit, nUnits, 100*unit/nUnits, toc(tStart));
        end
    end
end
fprintf('[create_all_plots] Processing complete (%.1f sec, %.2f sec/unit)\n', toc(tStart), toc(tStart)/max(1,nUnits));

% Merge PDFs
fprintf('[create_all_plots] Merging PDFs...\n');
existing_pdfs = temp_pdf_files(cellfun(@(f) exist(f,'file')==2, temp_pdf_files));
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
    Blocks, tt_counts, binCenters, xMin, xMax, sc_all, metadata_table, ...
    opt, temp_pdf_file, png_dir, fig_dir, nBlocks, unit_spike_counts)  % NEW arg

% Create figure
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [100 100 1200 800]);

% Plot the multi-panel page (delegated)
legacy_plot_unit_page(fig, unit, clusterID, rate_mean_halls, raster_data, halls, ...
    Blocks, tt_counts, binCenters, xMin, xMax, sc_all, metadata_table, opt, unit_spike_counts);  % NEW arg

% Save per-unit PDF
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

% Optional PNG
if ~isempty(png_dir) && opt.SavePNGs
    try
        png_file = fullfile(png_dir, sprintf('unit_%04d.png', unit));
        exportgraphics(fig, png_file, 'Resolution', 150, 'BackgroundColor', 'white');
    catch ME
        warning('[create_all_plots] Failed to save PNG for unit %d: %s', unit, ME.message);
    end
end

% Optional FIG
if ~isempty(fig_dir) && opt.SaveFIGs
    try
        fig_file = fullfile(fig_dir, sprintf('unit_%04d.fig', unit));
        savefig(fig, fig_file);
    catch ME
        warning('[create_all_plots] Failed to save FIG for unit %d: %s', unit, ME.message);
    end
end

close(fig);
end

%% ==================== Helpers kept in main ====================
function Blocks = clip_blocks_to_trials(Blocks, nTrials)
for b = 1:numel(Blocks)
    bb = Blocks{b}(:);
    bb = bb(isfinite(bb) & bb >= 1 & bb <= nTrials);
    Blocks{b} = unique(bb, 'stable');
end
end

function tt_counts = compute_trial_type_counts(Blocks, halls)
nBlocks = numel(Blocks);
nTypes  = 7;
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

function merge_pdfs_ghostscript(pdf_list, output_pdf)
if isempty(pdf_list), error('merge_pdfs_ghostscript:EmptyList', 'No input PDFs provided.'); end
outDir = fileparts(output_pdf);
if ~isempty(outDir) && ~exist(outDir, 'dir'), mkdir(outDir); end
gsExe = find_ghostscript_exe();
if isempty(gsExe)
    error('merge_pdfs_ghostscript:GSNotFound', 'Ghostscript executable not found on PATH.');
end
pdf_list = pdf_list(:)';
existsMask = cellfun(@(f) exist(f, 'file') == 2, pdf_list);
pdf_list = pdf_list(existsMask);
chunkSize = 75; chunkFiles = {};
n = numel(pdf_list); chunkIdx = 1; i = 1;
while i <= n
    j = min(i + chunkSize - 1, n);
    chunkInputs = pdf_list(i:j);
    chunkOut = fullfile(tempdir, sprintf('pdf_chunk_%03d.pdf', chunkIdx));
    run_ghostscript_merge(gsExe, chunkOut, chunkInputs);
    chunkFiles{end+1} = chunkOut;
    chunkIdx = chunkIdx + 1; i = j + 1;
end
if numel(chunkFiles) == 1
    copyfile(chunkFiles{1}, output_pdf); delete(chunkFiles{1}); return;
end
run_ghostscript_merge(gsExe, output_pdf, chunkFiles);
for k = 1:numel(chunkFiles), if exist(chunkFiles{k}, 'file'), delete(chunkFiles{k}); end, end
if ~(exist(output_pdf, 'file') == 2), error('merge_pdfs_ghostscript:OutputMissing', 'Output file not found.'); end
end

function run_ghostscript_merge(gsExe, output_pdf, input_files)
if isempty(input_files), error('run_ghostscript_merge:NoInputs', 'No input files to merge.'); end
inputsQuoted = strjoin(cellfun(@(f) sprintf('"%s"', f), input_files, 'UniformOutput', false), ' ');
gsExeQuoted = sprintf('"%s"', gsExe);
outputQuoted = sprintf('"%s"', output_pdf);
cmd = sprintf('%s -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -sOutputFile=%s %s', gsExeQuoted, outputQuoted, inputsQuoted);
[status, cmdout] = system(cmd);
if status ~= 0
    if contains(lower(gsExe), 'gswin64c')
        cmd32 = strrep(cmd, gsExeQuoted, '"gswin32c"');
        [status2, cmdout2] = system(cmd32);
        if status2 == 0, return; end
        error('run_ghostscript_merge:GSFail', 'Ghostscript merge failed.\n64-bit:\n%s\nOut:\n%s\n32-bit:\n%s\nOut:\n%s', cmd, cmdout, cmd32, cmdout2);
    else
        error('run_ghostscript_merge:GSFail', 'Ghostscript merge failed.\nCmd:\n%s\nOut:\n%s', cmd, cmdout);
    end
end
end

function gsExe = find_ghostscript_exe()
gsExe = '';
[s64, out64] = system('where gswin64c'); if s64 == 0, paths = strsplit(strtrim(out64), newline); gsExe = strtrim(paths{1}); return; end
[s32, out32] = system('where gswin32c'); if s32 == 0, paths = strsplit(strtrim(out32), newline); gsExe = strtrim(paths{1}); return; end
candidates = {
    'C:\Program Files\gs\gs10.00.0\bin\gswin64c.exe'
    'C:\Program Files\gs\gs9.55.0\bin\gswin64c.exe'
    'C:\Program Files\gs\gs9.52\bin\gswin64c.exe'
    'C:\Program Files (x86)\gs\gs9.55.0\bin\gswin32c.exe'
};
for i = 1:numel(candidates), if exist(candidates{i}, 'file'), gsExe = candidates{i}; return; end, end
end