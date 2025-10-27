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
SAVE_PNGS      = true;                  % save PNGs alongside the region PDF
PDF_FILENAME   = 'Legacy_AllUnits.pdf'; % FILENAME only (create_all_plots joins with region Figures/)
%% ------------------------------------------------

% Validate data root
assert(isfolder(DATA_ROOT), 'Data root not found: %s', DATA_ROOT);

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

fprintf('[%s] Running pipeline for %s\n', datestr(now), mouseID);

% Strict call to the per-session driver (no PNGDir/SkipPlot; PDFName is a filename)
run_full_pipeline(mousePath, REGIONS, ...
    'Blocks',          BLOCKS, ...
    'SmoothingWin',    SMOOTHING_WIN, ...
    'PDFName',         PDF_FILENAME, ...
    'SavePNGs',        SAVE_PNGS, ...
    'MakeLegacyPlots', MAKE_PLOTS);

fprintf('[%s] Finished %s\n', datestr(now), mouseID);
end
