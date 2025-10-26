function plot_legacy_from_v2(animal_path, region_names, varargin)
% PLOT_LEGACY_FROM_V2  Load Derived_V2/*.mat and emit legacy figure PDF/PNGs.
%
% Example:
% plot_legacy_from_v2('Z:\Justin\VR mice\VR42', {'PPC','VC'}, ...
%    'PDFName','Legacy_AllUnits.pdf', 'PNGDir','');

p = inputParser;
addParameter(p, 'PDFName', 'Legacy_AllUnits.pdf', @ischar);
addParameter(p, 'PNGDir', '', @ischar);
addParameter(p, 'ContentType', 'vector', @(s) any(strcmpi(s, {'vector','image'})));
parse(p, varargin{:});
opt = p.Results;

for r = 1:numel(region_names)
    region      = region_names{r};
    region_path = fullfile(animal_path, region);
    drv         = fullfile(region_path, 'Derived_V2');
    figs        = fullfile(region_path, 'Figures');
    if ~exist(figs,'dir'), mkdir(figs); end
    if ~isempty(opt.PNGDir) && ~exist(opt.PNGDir, 'dir'), mkdir(opt.PNGDir); end

    % --- Load exactly what save_v2_data wrote ---
    S = struct();
    load(fullfile(drv,'rate_mean_halls.mat'), 'rate_mean_halls'); S.rate_mean_halls = rate_mean_halls;
    load(fullfile(drv,'raster_data.mat'),     'raster_data');     S.raster_data     = raster_data;
    load(fullfile(drv,'clusterIDs.mat'),      'clusterIDs');      S.clusterIDs      = clusterIDs;
    load(fullfile(drv,'metadata_table.mat'),  'metadata_table');  S.metadata_table  = metadata_table;
    load(fullfile(drv,'halls.mat'),           'halls');           S.halls           = halls;
    load(fullfile(drv,'Blocks.mat'),          'Blocks');          S.Blocks          = Blocks;
    load(fullfile(drv,'tt_counts.mat'),       'tt_counts');       S.tt_counts       = tt_counts;
    load(fullfile(drv,'binCenters.mat'),      'binCenters');      S.binCenters      = binCenters;
    load(fullfile(drv,'xMin.mat'),            'xMin');            S.xMin            = xMin;
    load(fullfile(drv,'xMax.mat'),            'xMax');            S.xMax            = xMax;

    temp_pdf = fullfile(figs, ['_tmp_legacy_', region, '.pdf']);
    if exist(temp_pdf,'file'), delete(temp_pdf); end

    for u = 1:numel(S.clusterIDs)
        cid = S.clusterIDs(u);  % 0 allowed
        fig = figure('Units','pixels','Position',[100 100 900 700], ...
                     'Color','w','Visible','off');
        try
            % Adjust args to match your legacy_plot_unit_page signature if needed
            legacy_plot_unit_page(fig, u, cid, ...
                S.rate_mean_halls, S.raster_data, S.halls, S.Blocks, S.tt_counts, ...
                S.binCenters, S.xMin, S.xMax, S.clusterIDs, S.metadata_table);

            exportgraphics(fig, temp_pdf, 'ContentType', opt.ContentType);
            if ~isempty(opt.PNGDir)
                exportgraphics(fig, fullfile(opt.PNGDir, sprintf('unit_%04d.png', u)), ...
                               'Resolution', 150);
            end
        catch ME
            warning('Legacy page failed for unit %d (cid=%g): %s', u, cid, ME.message);
        end
        close(fig);
    end

    final_pdf = fullfile(figs, opt.PDFName);
    if exist(final_pdf,'file'), delete(final_pdf); end
    movefile(temp_pdf, final_pdf);
    log_msg('Legacy PDF written: %s', final_pdf);
end
end
