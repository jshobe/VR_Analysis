function Stats = MT_beta_posneg_stats_gui()
% MT_beta_posneg_stats_gui
% GUI workflow:
%   1) Pick a data file (MAT / CSV / TXT).
%   2) If MAT: choose which TABLE variable to analyze.
%   3) Pick one or more CellType×Region groups from the table (interactive list).
%   4) Compute +stats (β>0) and -stats (β<0) per Block×Predictor for each group.
%
% OUTPUT:
%   Stats.(CellTypeKey).(RegionKey).pos(block).(Predictor) and .neg(...):
%       n, mean, sem, median, iqr, str
%
% NOTES:
%   - Expects columns B{1..3}_{Pos,Context,Chair,Drum,Star}
%   - Expects metadata columns: CellType, Region (ClusterID/Animal optional)

    % 1) Pick a file
    [file, path] = uigetfile({'*.mat;*.csv;*.txt','MAT / CSV / TXT (*.mat,*.csv,*.txt)'; ...
                              '*.*','All files'}, ...
                              'Select a data file');
    assert(~isequal(file,0),'No file selected.');
    f = fullfile(path,file);
    [~,~,ext] = fileparts(f);

    % 2) Load into a MATLAB table
    T = load_table_from_file(f, ext);

    % 3) Let user pick CellType×Region groups from the data
    groups = pick_groups_from_table(T);
    assert(~isempty(groups), 'No groups selected.');

    % 4) Compute stats & print grids
    Stats = compute_stats_from_table(T, groups);
end

% ======================================================================
function T = load_table_from_file(f, ext)
    switch lower(ext)
        case '.mat'
            % enumerate variables
            vars = whos('-file', f);
            varNames = {vars.name};
            assert(~isempty(varNames),'No variables found in MAT file.');
            % Prefer those already known to be table class
            isTable = strcmp({vars.class}, 'table');
            if any(isTable)
                candidates = varNames(isTable);
            else
                candidates = varNames; % ask user; validate after load
            end

            % choose variable
            if numel(candidates) == 1
                pickName = candidates{1};
            else
                [idx, ok] = listdlg('ListString', candidates, ...
                                    'SelectionMode','single', ...
                                    'PromptString','Select the TABLE variable to analyze:', ...
                                    'Name','Choose Table');
                assert(ok==1, 'No table selected.');
                pickName = candidates{idx};
            end

            S = load(f, pickName);
            T = S.(pickName);
            assert(istable(T), 'Selected variable "%s" is not a table.', pickName);

        otherwise % CSV/TXT
            try
                opts = detectImportOptions(f);
                T = readtable(f, opts);
            catch
                % try common delimiters
                try
                    T = readtable(f, 'Delimiter', ',');
                catch
                    try
                        T = readtable(f, 'Delimiter', '\t');
                    catch
                        T = readtable(f, 'Delimiter', ';');
                    end
                end
            end
    end
end

% ======================================================================
function groups = pick_groups_from_table(T)
    % Create a normalized region column for matching
    T.Region_norm = lower(string(T.Region));

    % Discover unique combinations
    ct = string(T.CellType);
    rg = string(T.Region_norm);

    % Guard if columns missing
    if ~ismember('CellType', T.Properties.VariableNames) || ~ismember('Region', T.Properties.VariableNames)
        error('Table must contain "CellType" and "Region" columns.');
    end

    pairs = unique([ct, rg], 'rows');
    % Build labels and counts for display
    labels = strings(size(pairs,1),1);
    for i = 1:size(pairs,1)
        mask = ct==pairs(i,1) & rg==pairs(i,2);
        nrow = nnz(mask);
        labels(i) = sprintf('%s | %s   (n=%d rows)', pairs(i,1), upper(pairs(i,2)), nrow);
    end

    [idx, ok] = listdlg('ListString', cellstr(labels), ...
                        'SelectionMode','multiple', ...
                        'PromptString','Select one or more CellType × Region groups:', ...
                        'Name','Pick Groups');
    assert(ok==1, 'No groups selected.');
    sel = pairs(idx,:);

    % Convert to struct array with fields CellType, Region
    groups = repmat(struct('CellType',"", 'Region',""), size(sel,1), 1);
    for k = 1:size(sel,1)
        groups(k).CellType = char(sel(k,1));
        groups(k).Region   = char(sel(k,2));  % already lowercased
    end
end

% ======================================================================
function Stats = compute_stats_from_table(T, groups)
    % Normalize region for matching, keep original for display
    T.Region_norm = lower(string(T.Region));

    % (Soft) metadata check
    req = {'Animal','CellType','Region','ClusterID'};
    have = ismember(req, T.Properties.VariableNames);
    if ~all(have)
        warning('Missing metadata columns: %s', strjoin(req(~have), ', '));
    end

    Blocks     = 1:3;
    Predictors = {'Pos','Context','Chair','Drum','Star'};

    fmt   = @(m,sem,med,iqr) sprintf('%.3g \x00B1 %.3g | %.3g [%.3g–%.3g]', m, sem, med, iqr(1), iqr(2));
    semfn = @(x) std(x, 'omitnan') ./ max(1, sqrt(sum(~isnan(x))));

    Stats = struct();

    for g = 1:numel(groups)
        ct = groups(g).CellType;
        rg = lower(groups(g).Region);

        mask = strcmpi(T.CellType, ct) & strcmp(T.Region_norm, rg);
        S = T(mask, :);

        ctk = matlab.lang.makeValidName(ct);
        rgk = matlab.lang.makeValidName(rg);

        for b = Blocks
            for p = 1:numel(Predictors)
                pred = Predictors{p};
                betaName = sprintf('B%d_%s', b, pred);
                if ~ismember(betaName, T.Properties.VariableNames)
                    warning('Column %s not found. Skipping.', betaName);
                    continue
                end
                x = S.(betaName);

                % Positive-only
                xp = x(x > 0);
                pos.n      = numel(xp);
                pos.mean   = mean(xp, 'omitnan');
                pos.sem    = semfn(xp);
                pos.median = median(xp, 'omitnan');
                pos.iqr    = iqr_bounds(xp);
                pos.str    = fmt(pos.mean, pos.sem, pos.median, pos.iqr);

                % Negative-only
                xn = x(x < 0);
                neg.n      = numel(xn);
                neg.mean   = mean(xn, 'omitnan');
                neg.sem    = semfn(xn);
                neg.median = median(xn, 'omitnan');
                neg.iqr    = iqr_bounds(xn);
                neg.str    = fmt(neg.mean, neg.sem, neg.median, neg.iqr);

                % Store
                Stats.(ctk).(rgk).pos(b).(pred) = pos;
                Stats.(ctk).(rgk).neg(b).(pred) = neg;
            end
        end
    end

    % Pretty print like your mockup
    fprintf('\n================  Beta statistics (β>0 and β<0)  ================\n');
    for g = 1:numel(groups)
        ct = groups(g).CellType;   ctk = matlab.lang.makeValidName(ct);
        rg = lower(groups(g).Region); rgk = matlab.lang.makeValidName(rg);

        header = sprintf('%s in %s', ct, upper(rg));
        fprintf('\n%-40s   %s\n', header, '(β>0: "+stats", β<0: "-stats")');

        plusBlock  = strings(numel(Predictors), numel(Blocks));
        minusBlock = strings(numel(Predictors), numel(Blocks));

        for b = Blocks
            for p = 1:numel(Predictors)
                pred = Predictors{p};
                if isfield(Stats.(ctk).(rgk),'pos') && isfield(Stats.(ctk).(rgk).pos(b), pred)
                    plusBlock(p,b)  = Stats.(ctk).(rgk).pos(b).(pred).str;
                    minusBlock(p,b) = Stats.(ctk).(rgk).neg(b).(pred).str;
                else
                    plusBlock(p,b)  = "<missing>";
                    minusBlock(p,b) = "<missing>";
                end
            end
        end

        rowNames = string(Predictors(:));
        colNames = "Block" + string(Blocks);

        fprintf('\n  +stats (β>0)\n');
        print_string_table(rowNames, colNames, plusBlock);

        fprintf('\n  -stats (β<0)\n');
        print_string_table(rowNames, colNames, minusBlock);
    end

    fprintf('\nNote: "+stats" = mean±SEM | median [IQR] using only β>0;  "-stats" uses only β<0.\n');
end

% ======================================================================
function q = iqr_bounds(x)
    if isempty(x); q = [NaN NaN]; return; end
    q = prctile(x, [25 75]);
end

function print_string_table(rowNames, colNames, M)
    % Ensure everything we print is char (not string) for fprintf
    rowNames = cellstr(rowNames);           % string -> cellstr
    colNames = cellstr(colNames);
    M        = cellstr(M);                  % string matrix -> cellstr matrix

    R = numel(rowNames);
    C = numel(colNames);

    % Compute column widths (chars)
    wRow = max(cellfun(@numel, rowNames)) + 2;
    wCol = max(max(cellfun(@numel, M))) + 2;

    % Build char format specs
    fmtRow = sprintf('%%-%ds', wRow);
    fmtCol = sprintf('%%-%ds', wCol);

    % Header
    fprintf(['    ' fmtRow], '');           % indent + blank row header
    for c = 1:C
        fprintf(fmtCol, colNames{c});
    end
    fprintf('\n');

    % Rows
    for r = 1:R
        fprintf(['    ' fmtRow], rowNames{r});
        for c = 1:C
            fprintf(fmtCol, M{r,c});
        end
        fprintf('\n');
    end
end
