%% analyze_object_tuning_gui.m
clearvars; clc;

%% --- Select MAT file -----------------------------------------------------
[matfile, matpath] = uigetfile('*.mat','Select a MAT file (e.g., MT_reduced.mat)');
assert(~isequal(matfile,0),'No file selected.');
S = load(fullfile(matpath,matfile));
vars = fieldnames(S);

fprintf('\nAvailable variables in file:\n');
for i = 1:numel(vars), fprintf('  %2d) %s\n', i, vars{i}); end
idx = input('\nEnter the number of the table variable to analyze: ');
assert(idx>=1 && idx<=numel(vars),'Invalid selection.');
T = S.(vars{idx});
assert(istable(T),'Selected variable is not a table.');
colnames = string(T.Properties.VariableNames);
n = height(T);

%% --- Define predictors/blocks & build expected names ---------------------
preds  = ["Pos","Context","Chair","Drum","Star"];
blocks = ["B1","B2","B3"];
pblocks = ["P1","P2","P3"];

% beta column names (B#_Predictor)
betaNames = strings(0,1);
for b = 1:numel(blocks)
    betaNames = [betaNames; blocks(b) + "_" + preds]; %#ok<AGROW>
end

% p-value column names (P#_Predictor) - optional
pNames = strings(0,1);
for b = 1:numel(pblocks)
    pNames = [pNames; pblocks(b) + "_" + preds]; %#ok<AGROW>
end

% verify betas exist
missingB = setdiff(betaNames, colnames);
assert(isempty(missingB), "Table is missing beta columns: %s", strjoin(missingB, ", "));

% p-values may or may not be present; if absent we’ll fill with NaN
hasP = all(ismember(pNames, colnames));

%% --- Extract betas & p-values into numeric matrices ----------------------
B = cell(1,3); P = cell(1,3);
for b = 1:3
    betaCols = blocks(b) + "_" + preds;          % e.g., "B2_Chair"
    B{b} = T{:, betaCols};                       % n x 5
    if hasP
        pCols  = pblocks(b) + "_" + preds;       % e.g., "P2_Chair"
        P{b} = T{:, pCols};                      % n x 5
    else
        P{b} = nan(n,5);
    end
end

%% --- Object tuning metrics -----------------------------------------------
OBJ = [3 4 5];                                   % Chair, Drum, Star
absObj = @(M) abs(M(:,OBJ));                     % |β| for objects
A1 = absObj(B{1}); A2 = absObj(B{2}); A3 = absObj(B{3});

SI = @(A) max(A,[],2) ./ max(eps, sum(A,2));     % selectivity index in [1/3,1]
SI1 = SI(A1); SI2 = SI(A2); SI3 = SI(A3);

alpha = 0.05;
anySig = @(Pmat) any(Pmat(:,OBJ) < alpha, 2);
S1 = anySig(P{1}); S2 = anySig(P{2}); S3 = anySig(P{3});

valid12 = all(isfinite(A1),2) & all(isfinite(A2),2);
valid23 = all(isfinite(A2),2) & all(isfinite(A3),2);

%% --- Stats: Block 2 vs 1 -------------------------------------------------
fprintf('\n=== Object tuning: Block 2 vs Block 1 ===\n');
for k = 1:3
    [p,~,~] = signrank(A2(valid12,k), A1(valid12,k), 'method','approx');
    d = median(A2(valid12,k) - A1(valid12,k));
    fprintf(' |%s|: n=%d, medianΔ=%.4g, p=%.3g\n', preds(OBJ(k)), sum(valid12), d, p);
end
[pSI,~,~] = signrank(SI2(valid12), SI1(valid12), 'method','approx');
dSI = median(SI2(valid12) - SI1(valid12));
fprintf(' SI: n=%d, medianΔ=%.4g, p=%.3g\n', sum(valid12), dSI, pSI);
fprintf(' Any-object sig: B1=%.1f%%, B2=%.1f%%, Δ=%.1f%%\n', ...
    100*mean(S1(valid12)), 100*mean(S2(valid12)), 100*(mean(S2(valid12))-mean(S1(valid12))));

%% --- Stats: Block 2 vs 3 -------------------------------------------------
fprintf('\n=== Object tuning: Block 2 vs Block 3 ===\n');
for k = 1:3
    [p,~,~] = signrank(A2(valid23,k), A3(valid23,k), 'method','approx');
    d = median(A2(valid23,k) - A3(valid23,k));
    fprintf(' |%s|: n=%d, medianΔ=%.4g, p=%.3g\n', preds(OBJ(k)), sum(valid23), d, p);
end
[pSI,~,~] = signrank(SI2(valid23), SI3(valid23), 'method','approx');
dSI = median(SI2(valid23) - SI3(valid23));
fprintf(' SI: n=%d, medianΔ=%.4g, p=%.3g\n', sum(valid23), dSI, pSI);
fprintf(' Any-object sig: B3=%.1f%%, B2=%.1f%%, Δ=%.1f%%\n', ...
    100*mean(S3(valid23)), 100*mean(S2(valid23)), 100*(mean(S2(valid23))-mean(S3(valid23))));

%% --- Quick plots (optional) ----------------------------------------------
figure('Name','Object tuning'); tiledlayout(1,2);
nexttile; 
boxchart([A1(:,1);A2(:,1);A3(:,1)], [ones(n,1);2*ones(n,1);3*ones(n,1)]);
xlabel('Block'); ylabel('|Chair β|'); title('|Chair| magnitude');

nexttile;
boxchart([SI1;SI2;SI3], [ones(n,1);2*ones(n,1);3*ones(n,1)]);
xlabel('Block'); ylabel('Selectivity Index'); title('Object selectivity (SI)');
