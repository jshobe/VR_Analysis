%% GLM_build_summaries.m
% Build long-format and region-level summaries from MasterTable_VR with GLM results.

clearvars; clc;

%% --- Load the GLM-augmented MasterTable_VR --------------------------------
[matfile, matpath] = uigetfile('*.mat', 'Select the MAT with MasterTable_VR + GLM_* columns');
assert(~isequal(matfile,0), 'No file selected.');
S = load(fullfile(matpath, matfile), 'MasterTable_VR');
assert(isfield(S,'MasterTable_VR'), 'Selected file is missing MasterTable_VR.');
MasterTable_VR = S.MasterTable_VR;

needCols = {'Animal','Folder','CellType','Region', ...
            'GLM_Block1_Coeffs','GLM_Block1_pvals', ...
            'GLM_Block2_Coeffs','GLM_Block2_pvals', ...
            'GLM_Block3_Coeffs','GLM_Block3_pvals'};
assert(all(ismember(needCols, MasterTable_VR.Properties.VariableNames)), ...
    'MasterTable_VR lacks required GLM columns.');

%% --- Build long-format table: one row per Unit x Block x Predictor -------
n = height(MasterTable_VR);
predictors = ["Pos","Context","Chair","Drum","Star"];
blocks = 1:3;

% Helper to coerce cell column of 1x5 vectors into Nx5 numeric
coerce5 = @(C) cellfun(@(x) pad_to5(x), C, 'UniformOutput', false);
pad5_to_mat = @(C) cell2mat(coerce5(C));   % N x 5

B1 = pad5_to_mat(MasterTable_VR.GLM_Block1_Coeffs);
P1 = pad5_to_mat(MasterTable_VR.GLM_Block1_pvals);
B2 = pad5_to_mat(MasterTable_VR.GLM_Block2_Coeffs);
P2 = pad5_to_mat(MasterTable_VR.GLM_Block2_pvals);
B3 = pad5_to_mat(MasterTable_VR.GLM_Block3_Coeffs);
P3 = pad5_to_mat(MasterTable_VR.GLM_Block3_pvals);

% Stack blockwise
B_all = [B1; B2; B3];                % (3N) x 5
P_all = [P1; P2; P3];

% Expand identifiers per predictor and per block
Animal  = repmat(repelem(string(MasterTable_VR.Animal), 5, 1), 3, 1);
Folder  = repmat(repelem(string(MasterTable_VR.Folder), 5, 1), 3, 1);  % PPC/VC
CellTyp = repmat(repelem(string(MasterTable_VR.CellType), 5, 1), 3, 1);
Region  = repmat(repelem(string(MasterTable_VR.Region), 5, 1), 3, 1);
Block   = [repelem(1, n*5)'; repelem(2, n*5)'; repelem(3, n*5)'];
Predictor = repmat(repmat(predictors(:), n, 1), 3, 1);

Beta = B_all(:);
Pval = P_all(:);
isSig = Pval < 0.05;
isPos = Beta > 0;
isNeg = Beta < 0;

GLM_Long = table(Animal, Folder, CellTyp, Region, Block, categorical(Predictor), ...
                 Beta, Pval, isSig, isPos, isNeg, ...
                 'VariableNames', {'Animal','Folder','CellType','Region','Block','Predictor', ...
                                   'Beta','Pval','isSig','isPos','isNeg'});

%% --- Region-level summaries (PPC vs VC = Folder) -------------------------
grpF = {'Folder','Block','Predictor'};

T_N   = varfun(@numel, GLM_Long, 'InputVariables','Beta', ...
               'GroupingVariables', grpF);               % -> numel_Beta
T_mu  = varfun(@(x) mean(x,'omitnan'),   GLM_Long, 'InputVariables','Beta', 'GroupingVariables', grpF);
T_md  = varfun(@(x) median(x,'omitnan'), GLM_Long, 'InputVariables','Beta', 'GroupingVariables', grpF);
T_sd  = varfun(@(x) std(x,'omitnan'),    GLM_Long, 'InputVariables','Beta', 'GroupingVariables', grpF);
T_sum = varfun(@sum, GLM_Long, 'InputVariables', {'isSig','isPos','isNeg'}, ...
               'GroupingVariables', grpF);

% Clean column names
T_mu.Properties.VariableNames{end}  = 'mean_Beta';
T_md.Properties.VariableNames{end}  = 'median_Beta';
T_sd.Properties.VariableNames{end}  = 'std_Beta';
T_sum.Properties.VariableNames(end-2:end) = {'sum_isSig','sum_isPos','sum_isNeg'};

GLM_Summary_Folder = innerjoin(innerjoin(innerjoin(T_N, T_mu, 'Keys', grpF), T_md, 'Keys', grpF), T_sd, 'Keys', grpF);
GLM_Summary_Folder = innerjoin(GLM_Summary_Folder, T_sum, 'Keys', grpF);

N = GLM_Summary_Folder.numel_Beta;
GLM_Summary_Folder.PropSig = GLM_Summary_Folder.sum_isSig ./ N;
GLM_Summary_Folder.PosFrac = GLM_Summary_Folder.sum_isPos ./ N;
GLM_Summary_Folder.NegFrac = GLM_Summary_Folder.sum_isNeg ./ N;



%% --- Alternative region summaries (true Region label, e.g., dHC/vHC/etc.) -
grpR = {'Region','Block','Predictor'};

R_N   = varfun(@numel, GLM_Long, 'InputVariables','Beta', 'GroupingVariables', grpR);
R_mu  = varfun(@(x) mean(x,'omitnan'),   GLM_Long, 'InputVariables','Beta', 'GroupingVariables', grpR);
R_md  = varfun(@(x) median(x,'omitnan'), GLM_Long, 'InputVariables','Beta', 'GroupingVariables', grpR);
R_sd  = varfun(@(x) std(x,'omitnan'),    GLM_Long, 'InputVariables','Beta', 'GroupingVariables', grpR);
R_sum = varfun(@sum, GLM_Long, 'InputVariables', {'isSig','isPos','isNeg'}, 'GroupingVariables', grpR);

R_mu.Properties.VariableNames{end}  = 'mean_Beta';
R_md.Properties.VariableNames{end}  = 'median_Beta';
R_sd.Properties.VariableNames{end}  = 'std_Beta';
R_sum.Properties.VariableNames(end-2:end) = {'sum_isSig','sum_isPos','sum_isNeg'};

GLM_Summary_Region = innerjoin(innerjoin(innerjoin(R_N, R_mu, 'Keys', grpR), R_md, 'Keys', grpR), R_sd, 'Keys', grpR);
GLM_Summary_Region = innerjoin(GLM_Summary_Region, R_sum, 'Keys', grpR);

NR = GLM_Summary_Region.numel_Beta;
GLM_Summary_Region.PropSig = GLM_Summary_Region.sum_isSig ./ NR;
GLM_Summary_Region.PosFrac = GLM_Summary_Region.sum_isPos ./ NR;
GLM_Summary_Region.NegFrac = GLM_Summary_Region.sum_isNeg ./ NR;



%% --- Folder × CellType summaries (PPC/VC split + interneuron/pyramidal) --
grpFC = {'Folder','CellType','Block','Predictor'};

FC_N   = varfun(@numel, GLM_Long, 'InputVariables','Beta', 'GroupingVariables', grpFC);
FC_mu  = varfun(@(x) mean(x,'omitnan'),   GLM_Long, 'InputVariables','Beta', 'GroupingVariables', grpFC);
FC_md  = varfun(@(x) median(x,'omitnan'), GLM_Long, 'InputVariables','Beta', 'GroupingVariables', grpFC);
FC_sd  = varfun(@(x) std(x,'omitnan'),    GLM_Long, 'InputVariables','Beta', 'GroupingVariables', grpFC);
FC_sum = varfun(@sum, GLM_Long, 'InputVariables', {'isSig','isPos','isNeg'}, 'GroupingVariables', grpFC);

FC_mu.Properties.VariableNames{end}  = 'mean_Beta';
FC_md.Properties.VariableNames{end}  = 'median_Beta';
FC_sd.Properties.VariableNames{end}  = 'std_Beta';
FC_sum.Properties.VariableNames(end-2:end) = {'sum_isSig','sum_isPos','sum_isNeg'};

GLM_Summary_FolderCellType = innerjoin(innerjoin(innerjoin(FC_N, FC_mu, 'Keys', grpFC), FC_md, 'Keys', grpFC), FC_sd, 'Keys', grpFC);
GLM_Summary_FolderCellType = innerjoin(GLM_Summary_FolderCellType, FC_sum, 'Keys', grpFC);

NFC = GLM_Summary_FolderCellType.numel_Beta;
GLM_Summary_FolderCellType.PropSig = GLM_Summary_FolderCellType.sum_isSig ./ NFC;
GLM_Summary_FolderCellType.PosFrac = GLM_Summary_FolderCellType.sum_isPos ./ NFC;
GLM_Summary_FolderCellType.NegFrac = GLM_Summary_FolderCellType.sum_isNeg ./ NFC;

%% --- Save alongside the source file --------------------------------------
out_mat = fullfile(matpath, sprintf('%s_GLM_SUMMARIES.mat', erase(matfile, '.mat')));
save(out_mat, 'MasterTable_VR', 'GLM_Long', ...
              'GLM_Summary_Folder', 'GLM_Summary_Region', 'GLM_Summary_FolderCellType', '-v7.3');
fprintf('Saved:\n  %s\n', out_mat);

%% --- Helper: pad any coeff/pval row to 1x5
function v = pad_to5(x)
    if isempty(x)
        v = nan(1,5);
        return
    end
    x = x(:).';           % row
    m = min(5, numel(x));
    v = nan(1,5);
    v(1:m) = x(1:m);
end
