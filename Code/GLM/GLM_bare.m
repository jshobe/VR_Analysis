% Minimal GLM (nested Blocks structure: unitdata(c).Blocks{block,1}{row,1}, rows=1..4)
clearvars; close all;

%% Load unitdata
base_dir = 'Z:\Justin\VR mice';
[unitdata_filename, unitdata_path] = uigetfile(base_dir, 'Select a unitdata.mat file');
load(fullfile(unitdata_path, unitdata_filename), 'unitdata');

%% Select block
block_choice = input('Which block to analyze? (1=Block1, 2=Block2, 3=Block3): ');
if ~ismember(block_choice, [1 2 3])
    error('Invalid block_choice. Must be 1, 2, or 3.');
end

%% Load predictors
[pred_file, pred_dir] = uigetfile('*.xlsx', 'Select the predictor Excel file');
if isequal(pred_file, 0), error('No predictor file selected.'); end
predictor_path = fullfile(pred_dir, pred_file);

% Minimal predictor cleanup
predictor_tab = readtable(predictor_path);
if any(strcmp(predictor_tab.Properties.VariableNames, 'INDEX'))
    predictor_tab.INDEX = [];  % drop INDEX if present
end
predictors = table2array(predictor_tab);
if size(predictors, 2) >= 2
    predictors(:, 1:2) = [];   % drop first two non-predictor columns if present
end
if ~isnumeric(predictors)
    error('Predictor sheet contains non-numeric entries after cleanup.');
end

%% Dimension check using first unit (4 TT rows from nested Blocks{block,1}{row,1})
c1 = 1;
inner_c1 = unitdata(c1).Blocks{block_choice, 1};
if ~iscell(inner_c1) || size(inner_c1,1) < 4
    error('Blocks{%d,1} must be a cell with at least 4 rows (TT1–TT4 or TT1–TT2–TT5–TT6).', block_choice);
end
nBinsTT = numel(inner_c1{1,1});
expected_rows = 4 * nBinsTT;          % 4 segments × nBins
if size(predictors, 1) ~= expected_rows
    error('Predictor rows (%d) must equal 4*nBins (%d).', size(predictors, 1), expected_rows);
end

%% Fit GLM (Gaussian/identity) per unit with NaN audit
for c = 1:numel(unitdata)
    inner = unitdata(c).Blocks{block_choice, 1};  % nested TT container for this block
    % Concatenate TT1, TT2, row3, row4 (odd: TT3/TT4; even: TT5/TT6)
    rmap_row = [inner{1,1}, inner{2,1}, inner{3,1}, inner{4,1}];
    rmap = rmap_row(:);  % column vector [4*nBins x 1]

    % NaN audit (glmfit will drop these silently)
    mask = isfinite(rmap) & all(isfinite(predictors), 2);
    if c == 1
        fprintf('glmfit will exclude %d/%d rows due to NaNs\n', numel(rmap) - nnz(mask), numel(rmap));
    end

    % Fit (normal/Gaussian with identity link)
    X = predictors(mask, :);
    y = rmap(mask);
    [all_b_coeffs, dev, stats] = glmfit(X, y, 'normal', 'link', 'identity', 'constant', 'on');

    % Store minimal results
    unitdata(c).GLM.block    = block_choice;
    unitdata(c).GLM.b_int    = all_b_coeffs(1);
    unitdata(c).GLM.b_coeffs = all_b_coeffs(2:end);
    unitdata(c).GLM.pval     = stats.p(2:end);  % skip intercept
    unitdata(c).GLM.dev      = dev;
end

%% Save results
mouse_name = regexp(unitdata_path, 'VR\d+', 'match', 'once');
save_path = fullfile(unitdata_path, sprintf('%s_GLM_Block%d.mat', mouse_name, block_choice));
save(save_path, 'unitdata', '-v7.3');
fprintf('Saved results to: %s\n', save_path);