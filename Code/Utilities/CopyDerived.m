% CopyDerived.m - Copy Derived_V2 files, AllUnits_SpatialAnalysis.pdf, and GoodUnitInfo.csv with date backup

% Configuration
basePath = 'Z:\Justin\VR mice';
regions = {'VC', 'PPC'};
derivedFolder = 'Derived_V2';
figuresFolder = 'Figures';
unitMetricsFolder = 'UnitMetrics';

% Create date folder name
dateFolder = datestr(now, 'yyyy-mm-dd');

% Get all VR folders
vrFolders = dir(fullfile(basePath, 'VR*'));
vrFolders = vrFolders([vrFolders.isdir]);

fprintf('Starting copy process for %d VR folders...\n\n', length(vrFolders));

% Loop through each VR folder
for i = 1:length(vrFolders)
    vrName = vrFolders(i).name;
    vrPath = fullfile(basePath, vrName);
    
    fprintf('Processing %s...\n', vrName);
    
    % Process each region (VC and PPC)
    for r = 1:length(regions)
        region = regions{r};
        
        % === Copy Derived_V2 files ===
        derivedPath = fullfile(vrPath, region, derivedFolder);
        
        if exist(derivedPath, 'dir')
            % Create date backup folder
            backupPath = fullfile(derivedPath, dateFolder);
            if ~exist(backupPath, 'dir')
                mkdir(backupPath);
            end
            
            % Get all .mat files in Derived_V2
            matFiles = dir(fullfile(derivedPath, '*.mat'));
            
            % Copy each file
            for f = 1:length(matFiles)
                sourceFile = fullfile(derivedPath, matFiles(f).name);
                destFile = fullfile(backupPath, matFiles(f).name);
                copyfile(sourceFile, destFile);
            end
            
            fprintf('  ✓ %s: Copied %d files from Derived_V2\n', region, length(matFiles));
        else
            fprintf('  ✗ %s: Derived_V2 folder not found\n', region);
        end
        
        % === Copy AllUnits_SpatialAnalysis.pdf from Figures ===
        figuresPath = fullfile(vrPath, region, figuresFolder);
        pdfFile = fullfile(figuresPath, 'AllUnits_SpatialAnalysis.pdf');
        
        if exist(pdfFile, 'file')
            % Create date backup folder in Figures
            backupFiguresPath = fullfile(figuresPath, dateFolder);
            if ~exist(backupFiguresPath, 'dir')
                mkdir(backupFiguresPath);
            end
            
            destPdf = fullfile(backupFiguresPath, 'AllUnits_SpatialAnalysis.pdf');
            copyfile(pdfFile, destPdf);
            fprintf('  ✓ %s: Copied AllUnits_SpatialAnalysis.pdf\n', region);
        else
            fprintf('  ✗ %s: AllUnits_SpatialAnalysis.pdf not found\n', region);
        end
        
        % === Copy VR##_GoodUnitInfo.csv from UnitMetrics ===
        unitMetricsPath = fullfile(vrPath, region, unitMetricsFolder);
        csvFile = fullfile(unitMetricsPath, [vrName '_GoodUnitInfo.csv']);
        
        if exist(csvFile, 'file')
            % Create date backup folder in UnitMetrics
            backupUnitMetricsPath = fullfile(unitMetricsPath, dateFolder);
            if ~exist(backupUnitMetricsPath, 'dir')
                mkdir(backupUnitMetricsPath);
            end
            
            destCsv = fullfile(backupUnitMetricsPath, [vrName '_GoodUnitInfo.csv']);
            copyfile(csvFile, destCsv);
            fprintf('  ✓ %s: Copied %s_GoodUnitInfo.csv\n', region, vrName);
        else
            fprintf('  ✗ %s: %s_GoodUnitInfo.csv not found\n', region, vrName);
        end
    end
    
    fprintf('\n');
end

fprintf('Copy process complete!\n');