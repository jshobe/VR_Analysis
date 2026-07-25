%% GLM_CDS_objects_only_from_MasterTable_ALLBLOCKS_PAR.m
% Parallel GLM for ALL 3 blocks, using ONLY object predictors (Chair/Drum/Star)
% - Ignores position and context
% - Uses the same MasterTable_VR and predictor Excel files as the full 10-predictor GLM
% - Outputs 5-wide betas per block: [Pos, Context, Chair, Drum, Star]
%   with Pos = NaN, Context = NaN, and Chair/Drum/Star from the CDS-only model

clearvars; clc;

%% --- Constants -----------------------------------------------------------
SEG_LEN      = 133;         % bins per segment (4 * 133 = 532)
TOTAL_BINS   = 4 * SEG_LEN;

SMOOTH_X     = false;       % smoothing for predictors going into GLM
SMOOTH_Y     = false;       % smoothing for response going into GLM
SM_METHOD    = 'gaussian';
SM_WINDOW    = 3;

PLOT_QA      = true;        % set false to skip QA plots
QA_UNITS     = [118 42 7];          % e.g. [118 42 7]; [] => pick random
RNG_SEED     = 13;

objNames     = ["Chair","Drum","Star"];  % the only predictors in this model

%% --- Locate & load MasterTable_VR ---------------------------------------
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

Animals = string(MasterTable_VR.Animal);
FRblk   = MasterTable_VR.FRxTTxBlock;
n       = height(MasterTable_VR);

%% --- Predictor files (reuse same Excel files) ---------------------------
fn_pred.odd.b13  = fullfile(base_dir, 'CDS_Odd_Block13.xlsx');
fn_pred.even.b13 = fullfile(base_dir, 'CDS_Even_Block13.xlsx');
fn_pred.odd.b2   = fullfile(base_dir, 'CDS_Odd_Block2.xlsx');
fn_pred.even.b2  = fullfile(base_dir, 'CDS_Even_Block2.xlsx');

% --- Read
T_odd_b13  = readtable(fn_pred.odd.b13);
T_even_b13 = readtable(fn_pred.even.b13);
T_odd_b2   = readtable(fn_pred.odd.b2);
T_even_b2  = readtable(fn_pred.even.b2);

% --- Validate and select ONLY object columns
for tnm = ["T_odd_b13","T_even_b13","T_odd_b2","T_even_b2"]
    Ttmp = eval(tnm);
    assert(all(ismember(objNames, Ttmp.Properties.VariableNames)), ...
        '%s missing object columns.', tnm);
end

X_odd_obj_b13  = table2array(T_odd_b13(:,  objNames));   % 532×3 [Chair Drum Star]
X_even_obj_b13 = table2array(T_even_b13(:, objNames));   % 532×3
X_odd_obj_b2   = table2array(T_odd_b2(:,   objNames));   % 532×3
X_even_obj_b2  = table2array(T_even_b2(:,  objNames));   % 532×3

assert(size(X_odd_obj_b13,1)==TOTAL_BINS && size(X_even_obj_b13,1)==TOTAL_BINS && ...
       size(X_odd_obj_b2,1)==TOTAL_BINS  && size(X_even_obj_b2,1)==TOTAL_BINS, ...
       'Predictor files must have %d rows.', TOTAL_BINS);

%% --- Storage -------------------------------------------------------------
Intercept_obj = nan(n,3);   % n × 3 blocks
Dev_obj       = nan(n,3);

% 5-wide legacy format: [Pos, Context, Chair, Drum, Star]
Coeffs_obj    = cell(n,3);  % each: 1×5
Pvals_obj     = cell(n,3);  % each: 1×5

%% --- Parallel pool -------------------------------------------------------
if isempty(gcp('nocreate')), parpool; end

%% --- TT mapping per block -----------------------------------------------
% which 4 of the 6 FR segments are stacked for each block
TTmap = { [1 2 3 4], [1 2 5 6], [1 2 3 4] };

%% --- Helper --------------------------------------------------------------
iff = @(cond,a,b) cond.*a + (~cond).*b;

%% --- Main parallel loop --------------------------------------------------
parfor i = 1:n
    try
        % odd/even by animal ID number
        tok = regexp(Animals(i), '(\d+)', 'tokens', 'once');
        if isempty(tok), continue; end
        isOdd = mod(str2double(tok{1}),2)==1;

        for blk = 1:3
            % ---------- Build y (4×133 stacking) ----------
            Fblk_i = FRblk{i, blk};
            if ~iscell(Fblk_i) || numel(Fblk_i) < 6, continue; end
            ti    = TTmap{blk};
            y_raw = zeros(TOTAL_BINS,1); ok = true;
            for k = 1:4
                seg = Fblk_i{ti(k)};
                if ~isnumeric(seg) || numel(seg)~=SEG_LEN, ok=false; break; end
                y_raw((k-1)*SEG_LEN+(1:SEG_LEN)) = seg(:);
            end
            if ~ok, continue; end

            % ---------- Pick object predictors only ----------
            if blk == 2
                X_raw = iff(isOdd, X_odd_obj_b2,  X_even_obj_b2);   % 532×3 [Chair Drum Star]
            else
                X_raw = iff(isOdd, X_odd_obj_b13, X_even_obj_b13);  % 532×3
            end

            % ---------- Optional smoothing ----------
            X_fit = X_raw;
            if SMOOTH_X
                for c = 1:size(X_fit,2)
                    X_fit(:,c) = smooth_by_segments(X_fit(:,c), SEG_LEN, SM_METHOD, SM_WINDOW);
                end
            end
            y_fit = y_raw;
            if SMOOTH_Y
                y_fit = smooth_by_segments(y_fit, SEG_LEN, SM_METHOD, SM_WINDOW);
            end

            if any(~isfinite(y_fit)) || any(~isfinite(X_fit(:)))
                continue;
            end

            % ---------- GLM fit (Gaussian identity) ----------
            [b, d, stats] = glmfit(X_fit, y_fit, 'normal','link','identity','constant','on');
            Intercept_obj(i,blk) = b(1);
            Dev_obj(i,blk)       = d;

            bw = b(2:end);               % 3×1: [Chair; Drum; Star]
            pp = nan(size(bw));
            if isfield(stats,'p'), pp = stats.p(2:end); end

            chair = bw(1);
            drum  = bw(2);
            star  = bw(3);

            p_chair = pp(1);
            p_drum  = pp(2);
            p_star  = pp(3);

            % 5-wide legacy format: [Pos, Context, Chair, Drum, Star]
            Coeffs_obj{i,blk} = [NaN, NaN, chair, drum, star];
            Pvals_obj{i,blk}  = [NaN, NaN, p_chair, p_drum, p_star];
        end
    catch
        % optional logging per unit
    end
end

%% --- Attach outputs to table --------------------------------------------
for blk = 1:3
    MasterTable_VR.(sprintf('GLM_Block%d_Intercept', blk)) = Intercept_obj(:,blk);
    MasterTable_VR.(sprintf('GLM_Block%d_Coeffs',    blk)) = Coeffs_obj(:,blk);  % 1×5 [Pos, Context, Chair, Drum, Star]
    MasterTable_VR.(sprintf('GLM_Block%d_pvals',     blk)) = Pvals_obj(:,blk);  % 1×5
    MasterTable_VR.(sprintf('GLM_Block%d_Dev',       blk)) = Dev_obj(:,blk);
end

%% --- Save (CDS in filename) ---------------------------------------------
[outfile, outpath] = uiputfile( ...
    fullfile(matpath, strrep(matfile,'.mat','_GLM_CDS_5wide.mat')), ...
    'Save MasterTable_VR with CDS-only 5-wide GLM fields');

if ~isequal(outfile,0)
    MasterTable_VR_GLM = MasterTable_VR; %#ok<NASGU>
    save(fullfile(outpath,outfile), 'MasterTable_VR_GLM','-v7.3');
    fprintf('Saved: %s\n', fullfile(outpath,outfile));
end

%% --- QA plots: one figure per unit, per-block panels --------------------
if PLOT_QA
    rng(RNG_SEED);
    if isempty(QA_UNITS), QA_UNITS = randperm(n, min(3,n)); end

    RAW_LW   = 0.5;
    OBJ_LW   = 1.6;

    for ui = 1:numel(QA_UNITS)
        i = QA_UNITS(ui);
        fig = figure('Name', sprintf('QA CDS Unit %d', i), 'Color','w');
        tl  = tiledlayout(3,2,'TileSpacing','compact','Padding','compact');

        pred_axes = gobjects(0);
        rate_axes = gobjects(0);
        all_axes  = gobjects(0);

        tok   = regexp(Animals(i), '(\d+)', 'tokens', 'once');
        isOdd = ~isempty(tok) && mod(str2double(tok{1}),2)==1;

        for blk = 1:3
            % --- y (raw & smoothed) ---
            Fblk_i = FRblk{i, blk};
            if ~iscell(Fblk_i) || numel(Fblk_i) < 6, continue; end
            ti    = TTmap{blk};
            y_raw = zeros(TOTAL_BINS,1); ok = true;
            for k = 1:4
                seg = Fblk_i{ti(k)};
                if ~isnumeric(seg) || numel(seg)~=SEG_LEN, ok=false; break; end
                y_raw((k-1)*SEG_LEN+(1:SEG_LEN)) = seg(:);
            end
            if ~ok, continue; end
            y_sm = y_raw;
            if SMOOTH_Y, y_sm = smooth_by_segments(y_raw, SEG_LEN, SM_METHOD, SM_WINDOW); end

            % --- X (objects only) ---
            if blk == 2
                X_raw = iff(isOdd, X_odd_obj_b2, X_even_obj_b2);
            else
                X_raw = iff(isOdd, X_odd_obj_b13, X_even_obj_b13);
            end
            X_sm = X_raw;
            if SMOOTH_X
                for c = 1:size(X_sm,2)
                    X_sm(:,c) = smooth_by_segments(X_sm(:,c), SEG_LEN, SM_METHOD, SM_WINDOW);
                end
            end

            % --- TOP: object predictors ---
            ax1 = nexttile(tl);
            hold(ax1,'on');
            for c = 1:size(X_sm,2)
                plot(ax1, X_raw(:,c), ':', 'LineWidth', RAW_LW);
                plot(ax1, X_sm(:,c),  '-', 'LineWidth', OBJ_LW);
            end
            title(ax1, sprintf('Unit %d – Block %d CDS predictors', i, blk));
            xlabel(ax1, 'Time (bins)'); ylabel(ax1, 'Predictor value');
            legend(ax1, cellstr(objNames), 'Location','eastoutside');
            box(ax1,'on'); hold(ax1,'off');

            % --- BOTTOM: rate + GLM fit ---
            ax2 = nexttile(tl);
            plot(ax2, y_raw, ':', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.8); hold(ax2,'on');
            plot(ax2, y_sm,  '-', 'Color', [0.3 0.3 0.3], 'LineWidth', 1.2);

            b0   = Intercept_obj(i,blk);
            bvec = Coeffs_obj{i,blk};      % [NaN NaN Chair Drum Star]
            pvec = Pvals_obj{i,blk};

            % extract just the CDS part for prediction
            b_cds = bvec(3:5);             % [Chair Drum Star]
            X_for_pred = X_sm;

            if any(isnan(b_cds)) || all(b_cds==0)
                y_hat = b0 * ones(size(y_sm));
            else
                y_hat = b0 + X_for_pred * b_cds(:);
            end
            plot(ax2, y_hat, 'r-', 'LineWidth', 1.4);

            title(ax2, sprintf('Rate & CDS-only GLM fit — Block %d', blk));
            xlabel(ax2, 'Time (bins)'); ylabel(ax2, 'Firing rate'); box(ax2,'on');

            % β / p annotation (CDS only)
            txt = strings(numel(objNames),1);
            for c = 1:numel(objNames)
                bc = b_cds(c);
                pc = pvec(2+c);  % slots 3..5 correspond to Chair/Drum/Star
                if isnan(bc)
                    txt(c) = sprintf('%s: \\beta=NaN, p=NaN', objNames(c));
                else
                    if isnan(pc), pcs = 'NaN'; else, pcs = sprintf('%.3g', pc); end
                    txt(c) = sprintf('%s: \\beta=%.3f, p=%s', objNames(c), bc, pcs);
                end
            end
            xl = xlim(ax2); yl = ylim(ax2);
            text(ax2, xl(2), yl(2), strjoin(cellstr(txt), '\n'), ...
                'HorizontalAlignment','right','VerticalAlignment','top', ...
                'FontSize',8,'Interpreter','tex','BackgroundColor','w','Margin',2);

            pred_axes(end+1) = ax1; %#ok<AGROW>
            rate_axes(end+1) = ax2; %#ok<AGROW>
            all_axes(end+1)  = ax1; %#ok<AGROW>
            all_axes(end+1)  = ax2; %#ok<AGROW>
        end

        if ~isempty(all_axes),  linkaxes(all_axes,  'x'); end
        if ~isempty(pred_axes), linkaxes(pred_axes, 'y'); end
        if ~isempty(rate_axes), linkaxes(rate_axes, 'y'); end
    end
end

%% --- Helper --------------------------------------------------------------
function ysm = smooth_by_segments(y, seglen, method, win)
    ysm = y;
    for s = 1:4
        rng = (s-1)*seglen + (1:seglen);
        ysm(rng) = smoothdata(y(rng), method, win);
    end
end
