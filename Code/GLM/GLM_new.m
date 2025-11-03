%% GLM_from_MasterTable_ALLBLOCKS_PAR.m
% Parallel GLM for ALL 3 blocks using MasterTable_VR.
% - Auto-picks predictor file by mouse odd/even & block
% - FRxTTxBlock -> response y (4 segments * 133 bins = 532)
% - Standardizes predictors to 5 cols: [Pos, Context, Chair, Drum, Star]
% - Saves results back into MasterTable_VR

clearvars; clc;

%% --- Locate & load MasterTable_VR ----------------------------------------
base_dir = 'Z:\Justin\VR mice';
[matfile, matpath] = uigetfile(fullfile(base_dir, '*.mat'), ...
    'Select a MasterTable MAT (contains variable "MasterTable_VR")');
assert(~isequal(matfile,0), 'No file selected.');

S = load(fullfile(matpath, matfile), 'MasterTable_VR');
assert(isfield(S,'MasterTable_VR'), 'Selected file missing variable "MasterTable_VR".');
MasterTable_VR = S.MasterTable_VR;

needCols = {'Animal','FRxTTxBlock'};
assert(all(ismember(needCols, MasterTable_VR.Properties.VariableNames)), ...
    'MasterTable_VR must contain: %s', strjoin(needCols, ', '));

%% --- Predictor files -----------------------------------------------------
fn_pred.odd.b13  = fullfile(base_dir, 'Predictors_OddMice_Block1+3.xlsx');
fn_pred.odd.b2   = fullfile(base_dir, 'Predictors_OddMice_Block2.xlsx');
fn_pred.even.b13 = fullfile(base_dir, 'Predictors_EvenMice_Block1+3.xlsx');
fn_pred.even.b2  = fullfile(base_dir, 'Predictors_EvenMice_Block2.xlsx');

req_files = {fn_pred.odd.b13, fn_pred.odd.b2, fn_pred.even.b13, fn_pred.even.b2};
for i = 1:numel(req_files)
    assert(isfile(req_files{i}), 'Missing predictor file: %s', req_files{i});
end

X_odd_b13  = table2array(readtable(fn_pred.odd.b13));   % 532x5
X_even_b13 = table2array(readtable(fn_pred.even.b13));  % 532x5
X_odd_b2   = table2array(readtable(fn_pred.odd.b2));    % 532x4 (no Context)
X_even_b2  = table2array(readtable(fn_pred.even.b2));   % 532x4 (no Context)

assert(size(X_odd_b13,1)==532 && size(X_even_b13,1)==532 && ...
       size(X_odd_b2,1)==532   && size(X_even_b2,1)==532, ...
       'Predictor files must have 532 rows.');

%% --- Prepare inputs for parallel run -------------------------------------
n       = height(MasterTable_VR); % number of cells
Animals = string(MasterTable_VR.Animal);
FRblk   = MasterTable_VR.FRxTTxBlock;     % 7x1 cells, each [1x133 double]

Intercept = nan(n,3);
Dev       = nan(n,3);
Coeffs    = cell(n,3);   % [Pos,Context,Chair,Drum,Star]
Pvals     = cell(n,3);

if isempty(gcp('nocreate')), parpool; end

%% --- Parallel loop -------------------------------------------------------
% Block → TT mapping (your design)
% Block → TT mapping
TTmap = { [1 2 3 4], [1 2 5 6], [1 2 3 4] };

parfor i = 1:n
    try
        % odd/even mouse
        tok = regexp(Animals(i), '(\d+)', 'tokens', 'once'); % mouse ID
        if isempty(tok), continue; end
        isOdd = mod(str2double(tok{1}),2)==1;

        for blk = 1:3
            % predictors (B1 & B3 share Block1+3 file; B2 has no Context)
            if blk==2
                Xraw = ternary(isOdd, X_odd_b2,  X_even_b2);   % 532×4
            else
                Xraw = ternary(isOdd, X_odd_b13, X_even_b13);  % 532×5
            end

            % --- pull THIS block’s 7×1 TT cell (your layout: n×3 top-level) ---
            Fblk = FRblk{i, blk};                    % <-- 7×1 cell of 1×133 doubles
            if ~iscell(Fblk) || numel(Fblk) < 6, continue; end

            % build y from the block’s TT set, in TT order
            tt_idx = TTmap{blk};
            y = [];
            ok = true;
            for kTT = 1:numel(tt_idx) % each of the 4 trial types within a block, stacking ?
                seg = Fblk{tt_idx(kTT)};             % 1×133 double
                if ~isnumeric(seg) || numel(seg)~=133, ok=false; break; end
                y = [y; seg(:)]; %#ok<AGROW>
            end
            if ~ok || numel(y)~=532, continue; end

            % standardize predictors to 5 cols and fit
            X = ensure_5cols(Xraw);
            mask = isfinite(y) & all(isfinite(X),2);
            if nnz(mask) < 40, continue; end %% get rid of this shit, idk what the mask is doing. seems concerning. also you don't need ensure_5cols

            [b, d, stats] = glmfit(X(mask,:), y(mask), 'normal','link','identity','constant','on'); % actual glm
            
            % [y_pred,dylo,dyhi]= glmval(b, X(mask,:) ,'identity',stats); % this is yhat and 95% confidence bounds
            % figure; plot(y(mask)); hold on; plot(y_pred);

            Intercept(i,blk) = b(1);
            bb = nan(1,5); pp = nan(1,5);
            m  = min(5, numel(b)-1);
            bb(1:m) = b(2:1+m);
            if isfield(stats,'p'), pp(1:m) = stats.p(2:1+m); end
            Coeffs{i,blk} = bb;
            Pvals{i,blk}  = pp;
            Dev(i,blk)    = d;
        end
    catch
        % (optional) log ME.message
    end
end


%% --- Attach results back -------------------------------------------------
for blk = 1:3
    MasterTable_VR.(sprintf('GLM_Block%d_Intercept', blk)) = Intercept(:,blk);
    MasterTable_VR.(sprintf('GLM_Block%d_Coeffs',    blk)) = Coeffs(:,blk);
    MasterTable_VR.(sprintf('GLM_Block%d_pvals',     blk)) = Pvals(:,blk);
    MasterTable_VR.(sprintf('GLM_Block%d_Dev',       blk)) = Dev(:,blk);
end

%% --- Save ---------------------------------------------------------------
out_mat = fullfile(matpath, sprintf('%s_GLM_AllBlocks_PAR.mat', erase(matfile, '.mat')));
save(out_mat, 'MasterTable_VR', '-v7.3');
fprintf('Saved GLM results (all blocks, parallel):\n  %s\n', out_mat);



%% --- Helper functions ----------------------------------------------------
function X5 = ensure_5cols(X)
    % Standardize to [Pos, Context, Chair, Drum, Star]
    if size(X,2)==5
        X5 = X;
    elseif size(X,2)==4
        X5 = [X(:,1), zeros(size(X,1),1), X(:,2:4)];
    else
        error('Predictor matrix must have 4 or 5 columns.');
    end
end

function out = ternary(cond, A, B)
    if cond, out = A; else, out = B; end
end


