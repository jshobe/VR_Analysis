function run_full_pipeline(animal_path, region_names, varargin)
% RUN_FULL_PIPELINE  Compute Derived_V2 data and make legacy plots.
%
% Example:
% run_full_pipeline('Z:\Justin\VR mice\VR42', {'PPC','VC'}, ...
%     'Blocks', {12:174,178:337}, 'SmoothingWin', 12, ...
%     'PDFName', 'Legacy_AllUnits.pdf');

p = inputParser;
addParameter(p, 'Blocks', {[]}, @(x) iscell(x) || isnumeric(x));
addParameter(p, 'SmoothingWin', 12, @isscalar);
addParameter(p, 'PDFName', 'Legacy_AllUnits.pdf', @ischar);
addParameter(p, 'PNGDir', '', @ischar);
addParameter(p, 'SkipPlot', false, @islogical);
parse(p, varargin{:});
opt = p.Results;

for r = 1:numel(region_names)
    region      = region_names{r};
    region_path = fullfile(animal_path, region);
    derived_path = fullfile(region_path, 'Derived_V2');
    if ~exist(derived_path, 'dir'), mkdir(derived_path); end

    % ---- Step 1: Compute + save Derived_V2 data ----
    save_v2_data(animal_path, region_path, derived_path, ...
        'Blocks', opt.Blocks, 'SmoothingWin', opt.SmoothingWin);

    % ---- Step 2: Make legacy figures ----
    if ~opt.SkipPlot
        plot_legacy_from_v2(animal_path, {region}, ...
            'PDFName', opt.PDFName, 'PNGDir', opt.PNGDir);
    end
end

log_msg('All regions complete for %s', animal_path);
end
