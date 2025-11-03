function [Summary, Details] = GLM_dropout_diagnostics()
% GLM_dropout_diagnostics (backward-compatible)
% Inspect per-unit dropouts by block and report causes.
% Prompts for a MAT containing MasterTable_VR.

clc
[matfile, matpath] = uigetfile('*.mat','Select MAT with MasterTable_VR');
assert(~isequal(matfile,0),'No file selected.');
S = load(fullfile(matpath,matfile),'MasterTable_VR');
assert(isfield(S,'MasterTable_VR'),'Variable MasterTable_VR not found.');
T = S.MasterTable_VR;

% --- expected fields (soft check)
needCols = {'Animal','Region','CellType','ClusterID','FRxTTxBlock'};
assert(all(ismember(needCols, T.Properties.VariableNames)), ...
    'MasterTable_VR must contain: %s', strjoin(needCols, ', '));

% --- block trial-index mapping (adjust if your design differs)
TT.B1 = [1 2 3 4];
TT.B2 = [1 2 5 6];
TT.B3 = [3 4 5 6];

% --- helpers
preds = {'Pos','Context','Chair','Drum','Star'};
Bcol  = @(b,p) sprintf('B%d_%s',b,p);

% Causes as a cell array of char (not string array)
causes = {'OK', 'Missing FR segments', 'Too few finite bins (<40)', ...
          'GLM absent/continued', 'All betas NaN', 'Some betas NaN (dropped/collinear)'};
cause_counts = zeros(3, numel(causes));

% Details collector
d_rows = {};  % {Animal, CellType, Region, ClusterID, Block, Reason, PredictorsMissing, nFiniteBins}
add_detail = @(i,blk,reason,missPred,nfinite) ...
    assignin('caller','d_rows', [d_rows; {T.Animal(i), T.CellType(i), T.Region(i), ...
                                          T.ClusterID(i), blk, reason, strjoin(missPred,','), nfinite}]); %#ok<NASGU>

rows = height(T);
for i = 1:rows
    F = T.FRxTTxBlock{i};  % expected 7x1 cell, each 1x133 double
    for blk = 1:3
        % --- Choose TT indices for this block
        tt_field = sprintf('B%d', blk);
        tt_idx = TT.(tt_field);

        % --- Check FR segments exist and are 133 long; build y
        fr_ok = true; y = [];
        if ~iscell(F)
            fr_ok = false;
        else
            for k = 1:numel(tt_idx)
                tti = tt_idx(k);
                if tti>numel(F) || ~isnumeric(F{tti}) || numel(F{tti})~=133
                    fr_ok = false; break
                end
                y = [y; F{tti}(:)]; %#ok<AGROW>
            end
        end
        if ~fr_ok
            cause_counts(blk, strcmp(causes,'Missing FR segments')) = cause_counts(blk, strcmp(causes,'Missing FR segments'))+1;
            missPred = {};
            nfinite = NaN;
            d_rows = [d_rows; {T.Animal(i), T.CellType(i), T.Region(i), T.ClusterID(i), blk, 'Missing FR segments', strjoin(missPred,','), nfinite}]; %#ok<AGROW>
            continue
        end

        % --- Finite bin count (your GLM mask threshold)
        nfinite = sum(isfinite(y));
        if nfinite < 40
            cause_counts(blk, strcmp(causes,'Too few finite bins (<40)')) = cause_counts(blk, strcmp(causes,'Too few finite bins (<40)'))+1;
            missPred = {};
            d_rows = [d_rows; {T.Animal(i), T.CellType(i), T.Region(i), T.ClusterID(i), blk, 'Too few finite bins (<40)', strjoin(missPred,','), nfinite}]; %#ok<AGROW>
            continue
        end

        % --- GLM results presence (from your save step)
        cfield = sprintf('GLM_Block%d_Coeffs', blk);
        hasGLM = ismember(cfield, T.Properties.VariableNames) && i<=height(T) && ...
                 ~isempty(T.(cfield){i});
        if ~hasGLM
            cause_counts(blk, strcmp(causes,'GLM absent/continued')) = cause_counts(blk, strcmp(causes,'GLM absent/continued'))+1;
            missPred = {};
            d_rows = [d_rows; {T.Animal(i), T.CellType(i), T.Region(i), T.ClusterID(i), blk, 'GLM absent/continued', strjoin(missPred,','), nfinite}]; %#ok<AGROW>
            continue
        end

        % --- Wide betas, if present (to detect dropped predictors)
        missPred = {};
        anyWide = all(ismember({Bcol(blk,'Pos'),Bcol(blk,'Context'),Bcol(blk,'Chair'),Bcol(blk,'Drum'),Bcol(blk,'Star')}, ...
                               T.Properties.VariableNames));
        if anyWide
            v = nan(1, numel(preds));
            for p = 1:numel(preds)
                v(p) = T.(Bcol(blk,preds{p}))(i);
            end
            if all(isnan(v))
                cause_counts(blk, strcmp(causes,'All betas NaN')) = cause_counts(blk, strcmp(causes,'All betas NaN'))+1;
                missPred = preds;
                d_rows = [d_rows; {T.Animal(i), T.CellType(i), T.Region(i), T.ClusterID(i), blk, 'All betas NaN', strjoin(missPred,','), nfinite}]; %#ok<AGROW>
                continue
            end
            isMiss = isnan(v);
            if any(isMiss)
                cause_counts(blk, strcmp(causes,'Some betas NaN (dropped/collinear)')) = ...
                    cause_counts(blk, strcmp(causes,'Some betas NaN (dropped/collinear)'))+1;
                missPred = preds(isMiss);
                d_rows = [d_rows; {T.Animal(i), T.CellType(i), T.Region(i), T.ClusterID(i), blk, 'Some betas NaN (dropped/collinear)', strjoin(missPred,','), nfinite}]; %#ok<AGROW>
                continue
            end
        end

        % --- OK
        cause_counts(blk, strcmp(causes,'OK')) = cause_counts(blk, strcmp(causes,'OK'))+1;
    end
end

% --- Build Summary & Details tables
Summary = array2table(cause_counts, ...
    'VariableNames', {'OK','Missing FR segments','Too few finite bins (<40)', ...
                      'GLM absent/continued','All betas NaN','Some betas NaN (dropped/collinear)'}, ...
    'RowNames', {'Block1','Block2','Block3'});

% Expected headers for Details (8 columns):
detailNames = {'Animal','CellType','Region','ClusterID','Block','Reason','PredictorsMissing','nFiniteBins'};

% Robust construction even when d_rows is empty
if isempty(d_rows)
    Details = table('Size',[0 numel(detailNames)], ...
        'VariableTypes', {'string','string','string','double','double','string','string','double'}, ...
        'VariableNames', detailNames);
else
    % Ensure each row has exactly 8 elements
    d_rows = cellfun(@(r) r, d_rows, 'UniformOutput', false); %#ok<NASGU> % no-op, keeps cell type
    % If any row is short, pad it
    for k = 1:size(d_rows,1)
        if numel(d_rows(k,:)) < numel(detailNames)
            d_rows(k, end+1:numel(detailNames)) = {[]}; %#ok<AGROW>
        end
    end
    Details = cell2table(d_rows, 'VariableNames', detailNames);
end

disp('=== Dropout summary (counts) ==='); disp(Summary);
disp('=== Failed cases (details) ===');  disp(Details);

% Optional: write CSVs next to the MAT file
out_sum = fullfile(matpath, 'GLM_dropout_summary.csv');
out_det = fullfile(matpath, 'GLM_dropout_details.csv');
try
    writetable(Summary, out_sum, 'WriteRowNames', true);
    writetable(Details, out_det);
    fprintf('Saved:\n  %s\n  %s\n', out_sum, out_det);
catch
    % ignore if no write permission
end

% Optional: write CSVs next to the MAT file
out_sum = fullfile(matpath, 'GLM_dropout_summary.csv');
out_det = fullfile(matpath, 'GLM_dropout_details.csv');
try
    writetable(Summary, out_sum, 'WriteRowNames', true);
    writetable(Details, out_det);
    fprintf('Saved:\n  %s\n  %s\n', out_sum, out_det);
catch
    % ignore if no write permission
end
end
