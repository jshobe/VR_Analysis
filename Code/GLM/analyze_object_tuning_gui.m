function analyze_object_tuning_gui
% Compare object tuning across blocks using |beta| and a selectivity index.
% Works with wide-format tables that have B#_* (betas) and optionally P#_* (p-values).

clearvars -except ans; clc;

%% --- Pick MAT file & variable ---
[matfile, matpath] = uigetfile('*.mat','Select a MAT file containing your wide table (e.g., MT_reduced.mat)');
assert(~isequal(matfile,0),'No file selected.');
S = load(fullfile(matpath,matfile));
vars = fieldnames(S);

fprintf('\nAvailable variables in file:\n');
for i = 1:numel(vars), fprintf('  %2d) %s\n', i, vars{i}); end
idx = input('\nEnter the number of the table variable to analyze: ');
assert(idx>=1 && idx<=numel(vars),'Invalid selection.');
T = S.(vars{idx});
assert(istable(T),'Selected variable is not a table.');
n = height(T);
col = string(T.Properties.VariableNames);

%% --- Define predictor names & blocks ---
preds   = ["Pos","Context","Chair","Drum","Star"];
blocksB = ["B1","B2","B3"];
blocksP = ["P1","P2","P3"];    % optional

% Build expected column names for betas/pvals (order-agnostic)
needB = (blocksB(:) + "_" + preds); needB = needB(:);    % 15×1
optP  = (blocksP(:) + "_" + preds); optP  = optP(:);     % 15×1

% Check presence of beta columns
missingB = setdiff(needB, col);
assert(isempty(missingB), "Missing beta columns: %s", strjoin(missingB, ", "));
hasP = all(ismember(optP, col));

% Grab beta (and optional p) matrices per block regardless of column order
B = cell(1,3); P = cell(1,3);
for b = 1:3
    % beta columns for this block (ensure in the 5-predictor order)
    bcols = blocksB(b) + "_" + preds;
    [~,ix] = ismember(bcols, col);
    B{b} = T{:, ix};                % n × 5 (Pos,Context,Chair,Drum,Star)
    
    % p-value columns for this block (if present)
    if hasP
        pcols = blocksP(b) + "_" + preds;
        [~,ixp] = ismember(pcols, col);
        P{b} = T{:, ixp};           % n × 5
    else
        P{b} = nan(n,5);
    end
end

%% --- Object tuning metrics ---
OBJ = [3 4 5];                         % Chair, Drum, Star
absObj = @(M) abs(M(:,OBJ));           % |β| for objects
A1 = absObj(B{1}); A2 = absObj(B{2}); A3 = absObj(B{3});

% Selectivity index: max(|β_obj|)/sum(|β_obj|)
SI = @(A) max(A,[],2) ./ max(eps, sum(A,2));
SI1 = SI(A1); SI2 = SI(A2); SI3 = SI(A3);

% Any-object significant prevalence (if P not present -> all NaN -> false)
alpha = 0.05;
anySig = @(Pmat) any(Pmat(:,OBJ) < alpha, 2);
S1 = anySig(P{1}); S2 = anySig(P{2}); S3 = anySig(P{3});

% Valid rows (finite) for paired comparisons
valid12 = all(isfinite(A1),2) & all(isfinite(A2),2);
valid23 = all(isfinite(A2),2) & all(isfinite(A3),2);

%% --- Stats: Block 2 vs 1 ---
fprintf('\n=== Object tuning: Block 2 vs Block 1 ===\n');
for k = 1:3
    [p,~,~] = signrank(A2(valid12,k), A1(valid12,k), 'method','approx');
    d = median(A2(valid12,k) - A1(valid12,k));
    fprintf(' |%s|: n=%d, medianΔ=%.4g, p=%.3g\n', preds(OBJ(k)), sum(valid12), d, p);
end
[pSI,~,~] = signrank(SI2(valid12), SI1(valid12), 'method','approx');
dSI = median(SI2(valid12) - SI1(valid12));
fprintf(' SI: n=%d, medianΔ=%.4g, p=%.3g\n', sum(valid12), dSI, pSI);
fprintf(' Any-object sig: B1=%.1f%%, B2=%.1f%% (Δ=%.1f%%)\n', ...
    100*mean(S1(valid12)), 100*mean(S2(valid12)), 100*(mean(S2(valid12))-mean(S1(valid12))));

%% --- Stats: Block 2 vs 3 ---
fprintf('\n=== Object tuning: Block 2 vs Block 3 ===\n');
for k = 1:3
    [p,~,~] = signrank(A2(valid23,k), A3(valid23,k), 'method','approx');
    d = median(A2(valid23,k) - A3(valid23,k));
    fprintf(' |%s|: n=%d, medianΔ=%.4g, p=%.3g\n', preds(OBJ(k)), sum(valid23), d, p);
end
[pSI,~,~] = signrank(SI2(valid23), SI3(valid23), 'method','approx');
dSI = median(SI2(valid23) - SI3(valid23));
fprintf(' SI: n=%d, medianΔ=%.4g, p=%.3g\n', sum(valid23), dSI, pSI);
fprintf(' Any-object sig: B3=%.1f%%, B2=%.1f%% (Δ=%.1f%%)\n', ...
    100*mean(S3(valid23)), 100*mean(S2(valid23)), 100*(mean(S2(valid23))-mean(S3(valid23))));

%% --- Quick plots (optional) ---
try
    figure('Name','Object tuning'); tiledlayout(1,2);
    nexttile;
    grp = [ones(n,1); 2*ones(n,1); 3*ones(n,1)];
    boxchart([A1(:,1);A2(:,1);A3(:,1)], grp);
    xlabel('Block'); ylabel('|Chair β|'); title('|Chair| magnitude');

    nexttile;
    boxchart([SI1;SI2;SI3], grp);
    xlabel('Block'); ylabel('Selectivity Index'); title('Object selectivity (SI)');
catch
    % plotting optional; ignore if running headless
end

fprintf('\n✅ Analysis complete for %s → %s.\n', matpath, matfile);
end
