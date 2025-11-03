%% GLM_unpack_restrict_long_ABS.m
% Like GLM_unpack_restrict_long_flags.m, but also produces absolute-value betas.
% - Lets you pick which MasterTable to trim
% - Excludes Block_Filter==0
% - Unpacks GLM coeffs/pvals into separate columns
% - Builds long-format with flags + ABS variants (BetaAbs, BetaAbs_Pos, BetaAbs_Neg)

clearvars; clc;

%% --- Load MAT file and let user pick table --------------------------------
[matfile, matpath] = uigetfile('*.mat','Select MAT file containing MasterTable(s)');
assert(~isequal(matfile,0),'No file selected.');
data = load(fullfile(matpath,matfile));

vars = fieldnames(data);
fprintf('\nAvailable tables in file:\n');
for i = 1:numel(vars), fprintf('  %2d) %s\n', i, vars{i}); end
idx = input('\nEnter the number of the table to trim: ');
assert(idx >= 1 && idx <= numel(vars), 'Invalid selection.');
MT = data.(vars{idx});
fprintf('Selected table: %s\n\n', vars{idx});

%% --- Filter out failed units ---------------------------------------------
if ismember('Block_Filter', MT.Properties.VariableNames)
    n0 = height(MT);
    MT = MT(MT.Block_Filter > 0, :);
    fprintf('Excluded %d units failing Block_Filter (%.1f%%)\n\n', ...
            n0 - height(MT), 100*(n0 - height(MT))/n0);
else
    warning('No Block_Filter column found — proceeding without exclusion.');
end

%% --- Define predictors and blocks ----------------------------------------
predictors = {'Pos','Context','Chair','Drum','Star'};
blocks     = 1:3;

%% --- Unpack GLM coefficients and p-values --------------------------------
for blk = blocks
    colB = sprintf('GLM_Block%d_Coeffs', blk);
    colP = sprintf('GLM_Block%d_pvals', blk);

    if ismember(colB, MT.Properties.VariableNames)
        B = cell2mat(cellfun(@(x) pad_to5(x), MT.(colB), 'UniformOutput', false));
        for p = 1:numel(predictors)
            MT.(sprintf('B%d_%s', blk, predictors{p})) = B(:,p);
        end
    end

    if ismember(colP, MT.Properties.VariableNames)
        P = cell2mat(cellfun(@(x) pad_to5(x), MT.(colP), 'UniformOutput', false));
        for p = 1:numel(predictors)
            MT.(sprintf('P%d_%s', blk, predictors{p})) = P(:,p);
        end
    end
end

%% --- Keep only relevant columns ------------------------------------------
keepVars = {'Animal','CellType','Region','Block_Filter','ClusterID'};
bCols = startsWith(MT.Properties.VariableNames,'B');
pCols = startsWith(MT.Properties.VariableNames,'P');
keepVars = [keepVars, MT.Properties.VariableNames(bCols | pCols)];
MT_reduced = MT(:, keepVars);

%% --- Build long-format (with ABS variants) --------------------------------
n = height(MT_reduced);
LongAbs = table();

for blk = blocks
    for p = 1:numel(predictors)
        beta_col = sprintf('B%d_%s', blk, predictors{p});
        pval_col = sprintf('P%d_%s', blk, predictors{p});

        if ismember(beta_col, MT_reduced.Properties.VariableNames)
            Ttemp = table();
            Ttemp.Animal      = MT_reduced.Animal;
            Ttemp.CellType    = MT_reduced.CellType;
            Ttemp.Region      = MT_reduced.Region;
            Ttemp.Block       = repmat(blk, n, 1);
            Ttemp.BlockFilter = MT_reduced.Block_Filter;
            Ttemp.ClusterID   = MT_reduced.ClusterID;
            Ttemp.Predictor   = repmat(string(predictors{p}), n, 1);

            % Raw beta / pval
            Ttemp.Beta  = MT_reduced.(beta_col);
            if ismember(pval_col, MT_reduced.Properties.VariableNames)
                Ttemp.Pval = MT_reduced.(pval_col);
            else
                Ttemp.Pval = nan(n,1);
            end

            % Flags (significance & sign)
            Ttemp.isSig = Ttemp.Pval < 0.05;
            Ttemp.isPos = Ttemp.Beta > 0;
            Ttemp.isNeg = Ttemp.Beta < 0;

            % Split betas by sign (raw)
            Ttemp.Beta_Pos = Ttemp.Beta;
            Ttemp.Beta_Pos(~Ttemp.isPos) = NaN;
            Ttemp.Beta_Neg = Ttemp.Beta;
            Ttemp.Beta_Neg(~Ttemp.isNeg) = NaN;

            % --- Absolute-value columns
            Ttemp.BetaAbs      = abs(Ttemp.Beta);
            Ttemp.BetaAbs_Pos  = abs(Ttemp.Beta_Pos);   % positive betas kept, abs applied
            Ttemp.BetaAbs_Neg  = abs(Ttemp.Beta_Neg);   % negative betas kept, abs applied

            LongAbs = [LongAbs; Ttemp]; %#ok<AGROW>
        end
    end
end

%% --- Save outputs ---------------------------------------------------------
base = erase(matfile, '.mat');
out_reduced = fullfile(matpath, sprintf('%s_%s_GLMreduced.mat', base, vars{idx}));
out_longabs = fullfile(matpath, sprintf('%s_%s_GLMLong_abs.mat', base, vars{idx}));

save(out_reduced, 'MT_reduced', '-v7.3');
save(out_longabs, 'LongAbs', '-v7.3');

fprintf('\nSaved trimmed and ABS long-format tables:\n');
fprintf('  Reduced: %s\n', out_reduced);
fprintf('  LongAbs: %s\n', out_longabs);

%% --- Helper ---------------------------------------------------------------
function v = pad_to5(x)
    if isempty(x)
        v = nan(1,5);
        return
    end
    x = x(:).';
    v = nan(1,5);
    v(1:min(5,numel(x))) = x(1:min(5,numel(x)));
end
