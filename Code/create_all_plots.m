function create_all_plots(rate_mean_halls, raster_data, halls, cluster_id_good, out_folder, varargin)
% CREATE_ALL_PLOTS
% Creates one PDF per region with one unit per page
%   - Row 1: Position raster (all trials) with block separators
%   - Rows 2+: Firing rate curves per block (stacked vertically)
%
% Key Options:
%   'Blocks'          : {12:174, 178:337, 341:520} - trial blocks
%   'BinEdges'        : 0:4:534 - spatial edges (cm)
%   'SmoothingWin'    : 1.5 - Gaussian sigma in cm (0 = no smoothing)
%   'SavePNGs'        : false - also save individual PNGs
%   'PNGDir'          : '' - optional PNG output directory
%   'PDFName'         : 'AllUnits_SpatialAnalysis.pdf'
%   'PDFContent'      : 'image' or 'vector' (validated here)
%   'ShowTrialIDs'    : false - show trial numbers on raster
%   'TitlePrefix'     : '' - prefix for unit titles
%   'LegendOutside'   : false - reserved
%   'UseParallel'     : true - parallel processing of units
%   'RasterMarkerSize': 9 - size of raster dots

    % Parse options
    p = inputParser;
    addParameter(p, 'Blocks', {12:174, 178:337});
    addParameter(p, 'BinEdges', 0:4:534, @isnumeric);
    addParameter(p, 'SmoothingWin', 1.5, @(v)isnumeric(v)&&v>=0);
    addParameter(p, 'SavePNGs', false, @islogical);
    addParameter(p, 'PNGDir', '', @ischar);
    addParameter(p, 'PDFName', 'AllUnits_SpatialAnalysis.pdf', @ischar);
    addParameter(p, 'PDFContent', 'image', @ischar);
    addParameter(p, 'ShowTrialIDs', false, @islogical);
    addParameter(p, 'TitlePrefix', '', @ischar);
    addParameter(p, 'LegendOutside', false, @islogical);
    addParameter(p, 'UseParallel', true, @islogical);
    addParameter(p, 'RasterMarkerSize', 9, @(v)isnumeric(v)&&v>0);
    parse(p, varargin{:});
    opt = p.Results;

    % Validate PDF content type
    ct = lower(strtrim(opt.PDFContent));
    if ~ismember(ct, {'image','vector'})
        warning('[create_all_plots] Invalid PDFContent "%s". Using "image".', opt.PDFContent);
        ct = 'image';
    end
    opt.PDFContent = ct;

    % Setup
    if nargin < 5 || ~isfolder(out_folder)
        out_folder = pwd;
    end
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
    out_pdf = fullfile(out_folder, opt.PDFName);
    if exist(out_pdf, 'file'), delete(out_pdf); end

    png_dir = [];
    if opt.SavePNGs
        png_dir = opt.PNGDir;
        if isempty(png_dir), png_dir = fullfile(out_folder, 'PNGs'); end
        if ~exist(png_dir, 'dir'), mkdir(png_dir); end
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
    temp_pdf_files = arrayfun(@(u) fullfile(tempdir, sprintf('unit_%04d_temp.pdf', u)), ...
        1:nUnits, 'UniformOutput', false);

    fprintf('[create_all_plots] Processing %d units...\n', nUnits);
    tStart = tic;

    % Parallel or serial processing
    if opt.UseParallel && nUnits > 1
        if isempty(gcp('nocreate'))
            parpool('local');
        end
        parfor unit = 1:nUnits
            process_unit(unit, cluster_id_good(unit), rate_mean_halls, raster_data, ...
                halls, Blocks, tt_counts, binCenters, xMin, xMax, sc_all, metadata_table, ...
                region_folder, opt, temp_pdf_files{unit}, png_dir, nBlocks);
        end
    else
        for unit = 1:nUnits
            process_unit(unit, cluster_id_good(unit), rate_mean_halls, raster_data, ...
                halls, Blocks, tt_counts, binCenters, xMin, xMax, sc_all, metadata_table, ...
                region_folder, opt, temp_pdf_files{unit}, png_dir, nBlocks);
            if mod(unit, 10) == 0
                fprintf('  Progress: %d/%d (%.1f%%) - %.1f sec\n', ...
                    unit, nUnits, 100*unit/nUnits, toc(tStart));
            end
        end
    end

    fprintf('[create_all_plots] Processing complete (%.1f sec, %.2f sec/unit)\n', ...
        toc(tStart), toc(tStart)/max(1,nUnits));

    % Merge PDFs
    fprintf('[create_all_plots] Merging PDFs...\n');
    
    % Collect existing PDFs
    existing_pdfs = {};
    missing_count = 0;
    for u = 1:nUnits
        if exist(temp_pdf_files{u}, 'file')
            existing_pdfs{end+1} = temp_pdf_files{u}; %#ok<AGROW>
        else
            missing_count = missing_count + 1;
            if missing_count <= 5
                warning('[create_all_plots] Missing PDF for unit %d (cluster %g)', ...
                    u, cluster_id_good(u));
            end
        end
    end
    
    if missing_count > 5
        fprintf('[create_all_plots] ... and %d more missing PDFs\n', missing_count - 5);
    end
    
    if isempty(existing_pdfs)
        error('[create_all_plots] No PDFs were created. Check errors above.');
    end
    
    fprintf('[create_all_plots] Found %d/%d PDFs to merge\n', ...
        numel(existing_pdfs), nUnits);
    
    try
        merge_pdfs_ghostscript(existing_pdfs, out_pdf);
        cellfun(@(f) delete(f), existing_pdfs);
        
        if exist(out_pdf, 'file')
            info = dir(out_pdf);
            fprintf('[create_all_plots] SUCCESS: %s (%.1f MB)\n', ...
                out_pdf, info.bytes/1024^2);
        else
            error('[create_all_plots] Merge completed but output PDF not found');
        end
    catch ME
        error('[create_all_plots] PDF merge failed: %s', ME.message);
    end
end

%% ==================== Helper Functions ====================

function Blocks = clip_blocks_to_trials(Blocks, nTrials)
    % Clip block indices to valid trial range
    for b = 1:numel(Blocks)
        bb = Blocks{b}(:);
        bb = bb(isfinite(bb) & bb >= 1 & bb <= nTrials);
        Blocks{b} = unique(bb, 'stable');
    end
end

function tt_counts = compute_trial_type_counts(Blocks, halls)
    % Count trials per type per block
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
    % Load spike_clusters.npy
    sc_all = [];
    try
        sc_all = double(readNPY(fullfile(region_folder, 'spike_clusters.npy')));
    catch
    end
end

function metadata_table = load_metadata_csv(region_folder)
    % Load VR##_GoodUnitInfo.csv
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
        
        csv_path = fullfile(region_folder, 'UnitMetrics', ...
            sprintf('%s_GoodUnitInfo.csv', animal_name));
        
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
    if ~isempty(outDir) && ~exist(outDir, 'dir')
        mkdir(outDir);
    end

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
        warning('merge_pdfs_ghostscript:MissingInputs', ...
                'Skipping %d missing PDFs (e.g., "%s").', sum(~existsMask), missing{1});
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
    gsExeQuoted  = sprintf('"%s"', gsExe);
    outputQuoted = sprintf('"%s"', output_pdf);

    % Build command (avoid -q so we can see errors)
    cmd = sprintf('%s -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -sOutputFile=%s %s', ...
        gsExeQuoted, outputQuoted, inputsQuoted);

    [status, cmdout] = system(cmd);
    if status ~= 0
        % Try 32-bit variant if 64-bit fails
        if contains(lower(gsExe), 'gswin64c')
            cmd32 = strrep(cmd, gsExeQuoted, '"gswin32c"');
            [status2, cmdout2] = system(cmd32);
            if status2 == 0
                return;
            end
            error('run_ghostscript_merge:GSFail', ...
                'Ghostscript merge failed.\n64-bit cmd:\n%s\nOutput:\n%s\n\n32-bit cmd:\n%s\nOutput:\n%s', ...
                cmd, cmdout, cmd32, cmdout2);
        else
            error('run_ghostscript_merge:GSFail', ...
                'Ghostscript merge failed.\nCmd:\n%s\nOutput:\n%s', cmd, cmdout);
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