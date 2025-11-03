%% GLM_from_MasterTable_ALLBLOCKS_PAR.m
% Parallel GLM for ALL 3 blocks using MasterTable_VR.
% - Auto-picks predictor file by mouse odd/even & block
% - FRxTTxBlock -> response y (4 segments * 133 bins = 532)
% - Block 2: 4 predictors (no Context) but 5-wide outputs (Context=NaN)
% - No row mask; keep NaN/Inf safeguard
% - GLM fits on *smoothed* X and y (smoothdata, gaussian, window 3) *within segments*
% - QA: for 3 random units per block, plot predictors (top) and rate (bottom),
%       showing *both raw (dotted)* and *smoothed (solid)*, and annotate betas/p from the smoothed fit.

clearvars; clc;

%% --- Constants -----------------------------------------------------------
SEG_LEN      = 133;         % bins per segment (4 * 133 = 532)
SMOOTH_X     = false;        % smooth predictors used in GLM
SMOOTH_Y     = false;        % smooth response used in GLM
SM_METHOD    = 'gaussian';  % smoothdata method
SM_WINDOW    = 3;           % smoothdata window length (bins)
PLOT_QA  = true;              % set false to skip plots entirely
QA_UNITS = [118 42 7];       % e.g., [118 42 7]; leave [] to auto-pick random 3

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
for iChk = 1:numel(req_files)
    assert(isfile(req_files{iChk}), 'Missing predictor file: %s', req_files{iChk});
end

% Read with deterministic column order
wanted    = {'Pos','Context','Chair','Drum','Star'};   % B1+3
wanted_b2 = {'Pos','Chair','Drum','Star'};             % B2 (no Context)

T_odd_b13  = readtable(fn_pred.odd.b13);
T_even_b13 = readtable(fn_pred.even.b13);
assert(all(ismember(wanted, T_odd_b13.Properties.VariableNames)),  'Odd B1+3 file missing expected columns.');
assert(all(ismember(wanted, T_even_b13.Properties.VariableNames)), 'Even B1+3 file missing expected columns.');
T_odd_b13  = T_odd_b13(:,  wanted);
T_even_b13 = T_even_b13(:, wanted);

T_odd_b2   = readtable(fn_pred.odd.b2);
T_even_b2  = readtable(fn_pred.even.b2);
assert(all(ismember(wanted_b2, T_odd_b2.Properties.VariableNames)),  'Odd B2 file missing expected columns.');
assert(all(ismember(wanted_b2, T_even_b2.Properties.VariableNames)), 'Even B2 file missing expected columns.');
T_odd_b2   = T_odd_b2(:,  wanted_b2);
T_even_b2  = T_even_b2(:, wanted_b2);

X_odd_b13  = table2array(T_odd_b13);     % 532×5  [Pos Ctx Chair Drum Star]
X_even_b13 = table2array(T_even_b13);    % 532×5
X_odd_b2   = table2array(T_odd_b2);      % 532×4  [Pos Chair Drum Star]
X_even_b2  = table2array(T_even_b2);     % 532×4

assert(size(X_odd_b13,1)==532 && size(X_even_b13,1)==532 && ...
       size(X_odd_b2,1)==532   && size(X_even_b2,1)==532, ...
       'Predictor files must have 532 rows.');

%% --- Prepare inputs for parallel run -------------------------------------
n       = height(MasterTable_VR); % number of cells
Animals = string(MasterTable_VR.Animal);
FRblk   = MasterTable_VR.FRxTTxBlock;  % n×3, each {i,blk} is 7×1 cell of 1×133 doubles

Intercept = nan(n,3);
Dev       = nan(n,3);
Coeffs    = cell(n,3);   % [Pos,Context,Chair,Drum,Star]
Pvals     = cell(n,3);

if isempty(gcp('nocreate')), parpool; end

% Block → TT mapping (confirm this matches your design)
TTmap = { [1 2 3 4], [1 2 5 6], [1 2 3 4] };

%% --- Parallel loop (B2 has 4 predictors; outputs are 5-wide) ------------
%% --- Parallel loop (B2 has 4 predictors; outputs are 5-wide) ------------
parfor i = 1:n
    try
        % odd/even
        tok = regexp(Animals(i), '(\d+)', 'tokens', 'once');
        if isempty(tok), continue; end
        isOdd = mod(str2double(tok{1}),2)==1;

        for blk = 1:3
            % Build y (4×133 stacking)
            Fblk_i = FRblk{i, blk};
            if ~iscell(Fblk_i) || numel(Fblk_i) < 6, continue; end
            ti = TTmap{blk};
            y_raw  = zeros(4*SEG_LEN,1); ok = true;
            for k = 1:4
                seg = Fblk_i{ti(k)};
                if ~isnumeric(seg) || numel(seg)~=SEG_LEN, ok=false; break; end
                y_raw((k-1)*SEG_LEN+(1:SEG_LEN)) = seg(:);
            end
            if ~ok, continue; end

            % Smooth only y within segments
            y_fit = smooth_by_segments(y_raw, SEG_LEN, 'gaussian', 3);

            % Pick predictors for this block (raw, no smoothing)
            if blk == 2
                X_fit = iff(isOdd, X_odd_b2,  X_even_b2);   % 532×4
            else
                X_fit = iff(isOdd, X_odd_b13, X_even_b13);  % 532×5
            end

            % Safeguard
            if any(~isfinite(y_fit)) || any(~isfinite(X_fit(:)))
                warning('Non-finite values detected for cell %d block %d; skipping.', i, blk);
                continue
            end

            % Fit GLM (identity link, Gaussian)
            [b, d, stats] = glmfit(X_fit, y_fit, 'normal','link','identity','constant','on');

            % Store outputs (5-wide schema)
            Intercept(i,blk) = b(1);
            if blk == 2
                % B2: 4 predictors map into [Pos, Context(=NaN), Chair, Drum, Star]
                bb = [NaN NaN NaN NaN NaN];  pp = [NaN NaN NaN NaN NaN];
                bb([1 3 4 5]) = reshape(b(2:5), 1, []);
                if isfield(stats,'p'), pp([1 3 4 5]) = reshape(stats.p(2:5), 1, []); end
            else
                bb = nan(1,5);  pp = nan(1,5);
                m  = min(5, numel(b)-1);
                bb(1:m) = reshape(b(2:1+m), 1, []);
                if isfield(stats,'p'), pp(1:m) = reshape(stats.p(2:1+m), 1, []); end
            end
            Coeffs{i,blk} = bb;
            Pvals{i,blk}  = pp;
            Dev(i,blk)    = d;
        end
    catch
        % optional logging
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

%% ================= QA overlays: wide figure per unit (2 rows x 3 cols) =================
if PLOT_QA
    rng('shuffle');

    % pick units
    if ~isempty(QA_UNITS)
        pickIdx = unique(QA_UNITS(:).');                 % row vector
        pickIdx = pickIdx(pickIdx>=1 & pickIdx<=n);      % clamp to [1..n]
        if isempty(pickIdx)
            warning('QA_UNITS out of range; falling back to 3 random units.');
            pickIdx = randperm(n, min(3, n));
        end
    else
        pickIdx = randperm(n, min(3, n));
    end

    for ii = 1:numel(pickIdx)
        i = pickIdx(ii);

        % odd/even from Animal
        tok = regexp(string(Animals(i)), '(\d+)', 'tokens', 'once');
        if isempty(tok), continue; end
        isOdd = mod(str2double(tok{1}),2)==1;

        % Create one very wide figure for this unit (2x3 grid: blocks 1..3)
        fig = figure('Name', sprintf('Unit %d | All Blocks', i), ...
                     'Color','w', 'Units','normalized', ...
                     'Position',[0.02 0.1 0.96 0.72]);  % very wide
        tl = tiledlayout(fig, 2, 3, 'TileSpacing','compact', 'Padding','compact');

        for blk = 1:3
            % ---------- Build predictors (raw; no smoothing) ----------
            if blk == 2
                X = iff(isOdd, X_odd_b2,  X_even_b2);     % 532×4: [Pos Chair Drum Star]
                predNames = {'Pos','Chair','Drum','Star'};
            else
                X = iff(isOdd, X_odd_b13, X_even_b13);    % 532×5: [Pos Ctx Chair Drum Star]
                predNames = {'Pos','Ctx','Chair','Drum','Star'};
            end

            % ---------- Build y_raw exactly like GLM (4×133 stacking) ----------
            Fblk_i = FRblk{i, blk};
            if ~iscell(Fblk_i) || numel(Fblk_i) < 6, continue; end
            ti = TTmap{blk};
            y_raw = zeros(4*SEG_LEN,1); ok = true;
            for k = 1:4
                seg = Fblk_i{ti(k)};
                if ~isnumeric(seg) || numel(seg) ~= SEG_LEN, ok=false; break; end
                y_raw((k-1)*SEG_LEN+(1:SEG_LEN)) = seg(:);
            end
            if ~ok, continue; end

            % ---------- Smooth only y for fitting & plot overlay ----------
            y_sm = smooth_by_segments(y_raw, SEG_LEN, 'gaussian', 3);

            % ---------- Safeguard ----------
            if any(~isfinite(y_sm)) || any(~isfinite(X(:)))
                warning('Non-finite detected for unit %d block %d; skipping.', i, blk);
                continue
            end

            % ---------- Fit GLM on smoothed y and raw X ----------
            [b, d, stats] = glmfit(X, y_sm, 'normal','link','identity','constant','on');
            betas = reshape(b(2:end), 1, []);
            pvals = nan(size(betas));
            if isfield(stats,'p'), pvals = reshape(stats.p(2:end), 1, []); end

            % ---------- TOP PANEL (predictors raw) ----------
            ax1 = nexttile(tl, blk);  % row 1, col = blk
            hold(ax1,'on');
            for j = 1:size(X,2)
                plot(ax1, X(:,j), 'LineWidth', 1);
            end
            xline(ax1, SEG_LEN+1, '--'); xline(ax1, 2*SEG_LEN+1, '--'); xline(ax1, 3*SEG_LEN+1, '--');
            title(ax1, sprintf('Block %d | Predictors (raw)', blk));
            if blk==1, ylabel(ax1, 'Predictor value'); end
            legend(ax1, predNames, 'Location','bestoutside');
            grid(ax1,'on');

            % ---------- BOTTOM PANEL (rate: raw dotted, smoothed solid) ----------
            ax2 = nexttile(tl, 3+blk);  % row 2, col = blk
            hold(ax2,'on');
            plot(ax2, y_raw, ':', 'LineWidth', 1.3);
            plot(ax2, y_sm,  'LineWidth', 1.8);
            xline(ax2, SEG_LEN+1, '--'); xline(ax2, 2*SEG_LEN+1, '--'); xline(ax2, 3*SEG_LEN+1, '--');
            title(ax2, 'Firing rate: raw (dotted) vs smoothed (solid)');
            xlabel(ax2, 'Bin (1..532)');
            if blk==1, ylabel(ax2, 'Rate (a.u.)'); end
            grid(ax2,'on');

            % ---------- Beta + p annotation (from smoothed-y GLM) ----------
            lines = cell(1, numel(predNames));
            for j = 1:numel(predNames)
                if j <= numel(betas)
                    lines{j} = sprintf('%s:  \\beta=%.3g,  p=%.3g', predNames{j}, betas(j), pvals(j));
                else
                    lines{j} = sprintf('%s:  \\beta=NaN,  p=NaN', predNames{j});
                end
            end
            % place box near the top-right of each block's bottom panel
            pos = ax2.Position;
            annotation(fig, 'textbox', [pos(1)+pos(3)-0.12, pos(2)+pos(4)-0.10, 0.11, 0.095], ...
                'String', strjoin(lines, newline), ...
                'EdgeColor','k','LineWidth',0.5,'FontSize',9, ...
                'BackgroundColor',[1 1 1 0.85]);
        end

        % Global title for the whole figure
        title(tl, sprintf('Unit %d | Blocks 1–3 (top: predictors, bottom: rate)', i), ...
              'FontWeight','bold');
    end
end


%% --- Helpers ---
function out = iff(cond, A, B)
    if cond, out = A; else, out = B; end
end

function Yout = smooth_by_segments(Yin, seglen, method, win)
% Smooths each 133-bin segment independently (no leakage across TT boundaries).
% Yin can be (532x1) or (532xP). Returns same size.
    [R,C] = size(Yin);
    nSeg = R / seglen;
    Yout = zeros(R,C);
    for s = 1:nSeg
        idx = (s-1)*seglen + (1:seglen);
        Yout(idx,:) = smoothdata(Yin(idx,:), 1, method, win);
    end
end
