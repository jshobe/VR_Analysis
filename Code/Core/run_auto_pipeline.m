function run_auto_pipeline(mouseID)
% RUN_AUTO_PIPELINE  Strict GUI driver for VR analysis.
% - If mouseID is given (e.g., 'VR29'), runs that one.
% - Otherwise, opens a list dialog of VR* folders under Z:\Justin\VR mice\.
% - No configs, no hidden fallbacks. Errors if anything is missing.

%% ---------------- USER CONSTANTS ----------------
DATA_ROOT      = 'Z:\Justin\VR mice';   % base path
REGIONS        = {'PPC','VC'};          % regions to process
BLOCKS         = {[]};                  % passed to run_full_pipeline
SMOOTHING_WIN  = 12;                    % passed to run_full_pipeline
MAKE_PLOTS     = true;                  % set false to skip figures
OUTPUT_ROOT    = fullfile(DATA_ROOT, 'Output');
%% ------------------------------------------------

% Validate data root
assert(isfolder(DATA_ROOT), 'Data root not found: %s', DATA_ROOT);
if ~isfolder(OUTPUT_ROOT), mkdir(OUTPUT_ROOT); end

% If no mouseID: choose via simple GUI list
if nargin < 1 || isempty(mouseID)
    vrDirs = dir(fullfile(DATA_ROOT, 'VR*'));
    vrDirs = vrDirs([vrDirs.isdir]);
    assert(~isempty(vrDirs), 'No VR## folders found under: %s', DATA_ROOT);

    vrNames = {vrDirs.name}';
    [idx, ok] = listdlg( ...
        'PromptString', 'Select mouse (VR##):', ...
        'SelectionMode','single', ...
        'ListString',   vrNames, ...
        'ListSize',     [300 400]);

    if ~ok, error('Selection canceled. No mouse chosen.'); end
    mouseID = vrNames{idx};
end

% Validate chosen mouse folder
mousePath = fullfile(DATA_ROOT, mouseID);
assert(isfolder(mousePath), 'Mouse folder not found: %s', mousePath);

% Validate regions (strict)
for r = 1:numel(REGIONS)
    regionPath = fullfile(mousePath, REGIONS{r});
    assert(isfolder(regionPath), 'Missing region folder: %s', regionPath);
end

% Prepare output locations
outDir = fullfile(OUTPUT_ROOT, mouseID);
if ~isfolder(outDir), mkdir(outDir); end
pdfPath = fullfile(outDir, 'Legacy_AllUnits.pdf');
pngDir  = fullfile(outDir, 'PNGs');
if ~isfolder(pngDir), mkdir(pngDir); end

fprintf('[%s] Running pipeline for %s\n', datestr(now), mouseID);

% Strict call to the per-session driver
run_full_pipeline(mousePath, REGIONS, ...
    'Blocks',       BLOCKS, ...
    'SmoothingWin', SMOOTHING_WIN, ...
    'PDFName',      pdfPath, ...
    'PNGDir',       pngDir, ...
    'SkipPlot',     ~MAKE_PLOTS);

fprintf('[%s] Finished %s\n', datestr(now), mouseID);
end
