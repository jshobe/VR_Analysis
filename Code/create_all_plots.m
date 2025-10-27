function create_all_plots(rate_mean_halls, raster_data, halls, cluster_id_good, out_folder, varargin)
% CREATE_ALL_PLOTS (Core, legacy-only; Ghostscript default ON)
% Builds a single multi-page PDF (and optional PNG/FIGs) with one page per unit,
% using "legacy" visuals (no V2 branches).
%
% Inputs
%   rate_mean_halls : {1 x nBlocks} cell; each cell [nUnits x nBins x 7]
%   raster_data     : {nUnits x nTrials} spike structs with .positions
%   halls           : [nTrials x 1] TT codes (1..7)
%   cluster_id_good : [nUnits x 1] cluster IDs (double/int)
%   out_folder      : output directory for figures
%
% Name-Value Options
%   'Blocks'                    : { ... } trial blocks used (for legends/labels)
%   'SmoothingWin'              : scalar, smoothing sigma in cm (default 8)
%   'SavePNGs'                  : logical (save per-unit PNGs)
%   'PDFName'                   : char/string, final PDF file name (default 'AllUnits_SpatialAnalysis.pdf')
%   'PDFContent'                : accepted but not used for branching ('image'|'vector')
%   'ShowTrialIDs'              : logical
%   'TitlePrefix'               : char/string
%   'RasterMarkerSize'          : scalar
%   'SaveFIGs'                  : logical (save per-unit .fig)
%   'FIGDir'                    : char/string
%   'SpikeCountsByTypeByBlock'  : [nUnits x 7 x nBlocks] (or a single [7 x nBlocks]) for legends
%   'FileNum'                   : numeric (scene labels)
%   'IsEvenFile'                : logical (scene labels)
%   'UseGhostscript'            : logical (DEFAULT true) -> fast PDF merge if GS is on PATH

% -------- Parse options --------
p = inputParser;
addParameter(p,'Blocks',[], @(x) iscell(x) || isnumeric(x));
addParameter(p,'SmoothingWin', 8, @isscalar);
addParameter(p,'SavePNGs', false, @islogical);
addParameter(p,'PDFName', 'AllUnits_SpatialAnalysis.pdf', @(x) ischar(x) || isstring(x));
addParameter(p,'PDFContent', 'image', @(x) ischar(x) || isstring(x)); %#ok<NVREPL>
addParameter(p,'ShowTrialIDs', false, @islogical);
addParameter(p,'TitlePrefix', '', @(x) ischar(x) || isstring(x));
addParameter(p,'RasterMarkerSize', 2, @isscalar);
addParameter(p,'SaveFIGs', false, @islogical);
addParameter(p,'FIGDir', '', @(x) ischar(x) || isstring(x));
addParameter(p,'SpikeCountsByTypeByBlock', [], @(x) isnumeric(x) || isempty(x));
addParameter(p,'FileNum', NaN, @isscalar);
addParameter(p,'IsEvenFile', false, @islogical);

% DEFAULT: Ghostscript ON
addParameter(p,'UseGhostscript', true, @islogical);

parse(p, varargin{:});
opt = p.Results;

% Normalize Blocks
if isnumeric(opt.Blocks), opt.Blocks = {opt.Blocks}; end
Blocks = opt.Blocks;
if isempty(Blocks)
    % default: use all trials as one block
    nTrials = size(raster_data, 2);
    Blocks = {1:nTrials};
end

% Ensure output dirs
if isempty(opt.FIGDir), opt.FIGDir = fullfile(out_folder, 'FIGs'); end
if ~exist(out_folder, 'dir'), mkdir(out_folder); end
if opt.SaveFIGs && ~exist(opt.FIGDir, 'dir'), mkdir(opt.FIGDir); end

% -------- Infer sizes & x-axis --------
nBlocks = numel(rate_mean_halls);
nBins = [];
for b = 1:nBlocks
    if ~isempty(rate_mean_halls{b})
        nBins = size(rate_mean_halls{b}, 2);
        break;
    end
end
if isempty(nBins), nBins = 1; end
binCenters = (1:nBins)';   % legacy strict default
xMin = binCenters(1);
xMax = binCenters(end);

% -------- Trial counts per block & TT (for legends) --------
tt_counts = cell(1, numel(Blocks));
for b = 1:numel(Blocks)
    trials = Blocks{b}(:);
    tr_halls = halls(trials);
    counts = zeros(1,7);
    for TT = 1:7
        counts(TT) = sum(tr_halls == TT);
    end
    tt_counts{b} = counts;
end

% -------- PDF init --------
pdf_name  = char(opt.PDFName);
pdf_path  = fullfile(out_folder, pdf_name);
if exist(pdf_path,'file'), delete(pdf_path); end

% Ghostscript availability
gsExe   = '';
useGS   = false;
if opt.UseGhostscript
    try
        gsExe = find_ghostscript();
        useGS = ~isempty(gsExe);
    catch
        gsExe = ''; useGS = false;
    end
end
if opt.UseGhostscript && ~useGS
    warning('create_all_plots:GSNotFound', ...
        'UseGhostscript=true but Ghostscript not found on PATH. Falling back to exportgraphics.');
end

% Temp storage if GS is used
tmp_pages = {};
tmp_dir   = fullfile(out_folder, 'tmp_pages');
if useGS && ~exist(tmp_dir,'dir'), mkdir(tmp_dir); end

% -------- Iterate units and draw pages --------
nUnits = size(raster_data, 1);
if isempty(cluster_id_good)
    cluster_id_good = (1:nUnits)'; % fallback IDs
end

for u = 1:nUnits
    fig = figure('Color','w','Units','pixels','Position',[100 100 1000 800]);
    try
        % Select spike counts for this unit if provided as [nUnits x 7 x nBlocks]
        unit_spike_counts = [];
        if ~isempty(opt.SpikeCountsByTypeByBlock)
            S = opt.SpikeCountsByTypeByBlock;
            if ndims(S) == 3 && size(S,1) >= u
                unit_spike_counts = squeeze(S(u, :, :)); % [7 x nBlocks]
            elseif ismatrix(S) && size(S,2) == numel(Blocks) && size(S,1) == 7
                unit_spike_counts = S; % already 7 x nBlocks
            end
        end

        legacy_plot_unit_page( ...
            fig, ...
            u, ...
            cluster_id_good(u), ...
            rate_mean_halls, ...
            raster_data, ...
            halls, ...
            Blocks, ...
            tt_counts, ...
            binCenters, ...
            xMin, ...
            xMax, ...
            [], ...            % sc_all (optional)
            table(), ...       % metadataTable (optional)
            struct('SmoothingWin',   opt.SmoothingWin, ...
                   'ShowTrialIDs',   opt.ShowTrialIDs, ...
                   'RasterMarkerSize', opt.RasterMarkerSize, ...
                   'TitlePrefix',    char(opt.TitlePrefix), ...
                   'FileNum',        opt.FileNum, ...
                   'IsEvenFile',     opt.IsEvenFile), ...
            unit_spike_counts);

        drawnow;

        if useGS
            % FAST path: save page as its own PDF (then merge with GS)
            page_pdf = fullfile(tmp_dir, sprintf('unit_%04d.pdf', u));
            try
                % --- Page-fit & orientation to prevent "figure too large" warnings ---
                try
                    pos = get(fig,'Position'); % [x y w h] in pixels
                    if pos(3) >= pos(4)
                        orient(fig,'landscape');
                        papersz = [11 8.5];   % Letter landscape (inches)
                    else
                        orient(fig,'portrait');
                        papersz = [8.5 11];   % Letter portrait (inches)
                    end
                catch
                    papersz = [11 8.5]; % fallback
                end
                set(fig,'PaperUnits','inches');
                set(fig,'PaperPositionMode','auto');
                set(fig,'PaperSize', papersz);

                % Scale to fit the page (prevents cutoff)
                print(fig, '-dpdf', '-bestfit', '-r200', page_pdf);
                tmp_pages{end+1} = page_pdf; %#ok<AGROW>
            catch ME
                warning('create_all_plots:PageWriteFailed','Unit %d PDF write failed: %s', u, ME.message);
            end
        else
            % Portable path: append directly via exportgraphics
            appended = false;
            try
                exportgraphics(fig, pdf_path, 'ContentType','vector', 'Append', true);
                appended = true;
            catch
                try
                    exportgraphics(fig, pdf_path, 'ContentType','image', 'BackgroundColor','white', 'Append', true);
                    appended = true;
                catch ME2
                    warning('create_all_plots:AppendFailed','Unit %d append failed: %s', u, ME2.message);
                end
            end
            if ~appended
                warning('create_all_plots:PDFAppend', 'Could not append page %d to PDF.', u);
            end
        end

        % Save PNG (optional)
        if opt.SavePNGs
            png_path = fullfile(out_folder, sprintf('unit_%04d.png', u));
            try
                exportgraphics(fig, png_path, 'Resolution', 200, 'BackgroundColor', 'white');
            catch
                try
                    print(fig, '-dpng', '-r200', png_path);
                catch
                end
            end
        end

        % Save FIG (optional)
        if opt.SaveFIGs
            try
                savefig(fig, fullfile(opt.FIGDir, sprintf('unit_%04d.fig', u)));
            catch
            end
        end

    catch ME
        warning('create_all_plots:UnitPlotError', 'Unit %d: %s', u, ME.message);
    end
    close(fig);
end

% -------- Merge with Ghostscript (if enabled) --------
if useGS && ~isempty(tmp_pages)
    try
        merge_pdfs_with_gs(gsExe, pdf_path, tmp_pages);
        % Cleanup temp pages folder
        try
            rmdir(tmp_dir, 's');
        catch
        end
        fprintf('Legacy PDF written (GS): %s\n', pdf_path);
    catch ME
        warning('create_all_plots:GhostscriptMergeFailed', 'GS merge failed: %s', ME.message);
    end
else
    fprintf('Legacy PDF written: %s\n', pdf_path);
end
end

% ======================= Helpers =======================

function exe = find_ghostscript()
% Try common names across platforms; return full path or empty
candidates = {};
if ispc
    candidates = {'gswin64c.exe','gswin32c.exe','gs.exe'};
    queryCmd  = @(nm) sprintf('where %s', nm);
else
    candidates = {'gs'};
    queryCmd  = @(nm) sprintf('which %s', nm);
end
exe = '';
for i = 1:numel(candidates)
    try
        [st, out] = system(queryCmd(candidates{i}));
        if st == 0
            lines = regexp(strtrim(out), '[\r\n]+', 'split');
            if ~isempty(lines)
                exe = strtrim(lines{1});
                return;
            end
        end
    catch
    end
end
end

function merge_pdfs_with_gs(gsExe, out_pdf, page_list)
% Concatenate PDFs with Ghostscript (fast). Overwrites out_pdf.
assert(~isempty(gsExe), 'Ghostscript not found on PATH.');

% Ensure output folder exists
out_dir = fileparts(out_pdf);
if ~exist(out_dir,'dir'), mkdir(out_dir); end

% Quote paths
quoted = cellfun(@(p) ['"' p '"'], page_list, 'UniformOutput', false);
out_q  = ['"' out_pdf '"'];

% /prepress keeps high quality; adjust to /ebook or /screen for smaller files
cmd = sprintf('"%s" -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress -sOutputFile=%s %s', ...
    gsExe, out_q, strjoin(quoted, ' '));

[status, msg] = system(cmd);
if status ~= 0
    error('Ghostscript failed (%d): %s', status, msg);
end
end
