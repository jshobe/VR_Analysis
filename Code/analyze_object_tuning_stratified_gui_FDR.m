function analyze_object_tuning_stratified_gui_FDR
% Stratified object-tuning analysis with per-unit FDR (Benjamini–Hochberg)
% across the 5 predictors (Pos, Context, Chair, Drum, Star), by Region × CellType.
%
% INPUT TABLE (wide format, required columns):
%   B1_Pos,B1_Context,B1_Chair,B1_Drum,B1_Star,
%   B2_Pos,B2_Context,B2_Chair,B2_Drum,B2_Star,
%   B3_Pos,B3_Context,B3_Chair,B3_Drum,B3_Star
%   P1_Pos,... P3_Star  (p-values; required for FDR & prevalence)
%
% FILTERS (hard-coded):
%   Regions   ∈ {DHC, VHC, PPC, VC}
%   CellTypes ∈ {Narrow Interneuron, Wide Interneuron, Pyramidal Cell}
%
% OUTPUT:
%   - Console summaries by Region × CellType:
%       * B2 vs B1 and B2 vs B3 for |β| (Chair/Drum/Star) and SI
%       * FDR<0.05 prevalence per object and AnyObj for B1, B2, B3
%   - Optional CSV export of group-level metrics (toggle SAVE_CSV).

%% ---------------- Config ----------------
SAVE_CSV = true;                  % set false to skip CSV export
ALPHA    = 0.05;                  % FDR decision threshold
PRED     = ["Pos","Context","Chair","Drum","Star"];
OBJ_IDX  = [3 4 5];               % indices of Chair, Drum, Star in PRED

VALID_REGIONS   = ["DHC","VHC","PPC","VC"];
VALID_CELLTYPES = ["Narrow Interneuron","Wide Interneuron","Pyramidal Cell"];

%% -------------- Load table --------------
clc;
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
n0 = height(T);
col = string(T.Properties.VariableNames);

%% --------- Require needed columns -------
blocksB = ["B1","B2","B3"];
blocksP = ["P1","P2","P3"];

needB = (blocksB(:) + "_" + PRED); needB = needB(:);               % 15 beta names
needP = (blocksP(:) + "_" + PRED); needP = needP(:);               % 15 p names

missB = setdiff(needB, col);
missP = setdiff(needP, col);
assert(isempty(missB), "Missing beta columns: %s", strjoin(missB, ", "));
assert(isempty(missP), "Missing p-value columns: %s", strjoin(missP, ", "));

%% -------- Filter Region / CellType ------
% Normalize and filter
if ~ismember("Region", col)
    error('Table must contain a "Region" column.');
end
if ~ismember("CellType", col)
    error('Table must contain a "CellType" column.');
end

T.Region   = upper(string(T.Region));     % normalize region to uppercase
T.CellType = string(T.CellType);

keep = ismember(T.Region, VALID_REGIONS) & ismember(T.CellType, VALID_CELLTYPES);
T = T(keep,:);
fprintf('\nKept %d / %d units after Region/CellType filter.\n', height(T), n0);

% Recompute for filtered table
n = height(T);
col = string(T.Properties.VariableNames);

%% -------- Extract betas & p-values ------
B = cell(1,3); P = cell(1,3);
for b = 1:3
    bcols = blocksB(b) + "_" + PRED;      % ensure exactly Pos,Context,Chair,Drum,Star order
    pcols = blocksP(b) + "_" + PRED;

    [~,ixB] = ismember(bcols, col);
    [~,ixP] = ismember(pcols, col);

    B{b} = T{:, ixB};                     % n × 5
    P{b} = T{:, ixP};                     % n × 5
end

%% -------- Per-unit FDR per block --------
Padj = cell(1,3);     % adjusted p-values per block, n × 5
Sig  = cell(1,3);     % struct with logical fields Chair/Drum/Star/AnyObj (FDR<ALPHA)

for b = 1:3
    Pmat = P{b};
    padj = nan(size(Pmat));
    for j = 1:n
        pj = Pmat(j,:);
        if all(isnan(pj))
            continue;
        end
        % BH-FDR across the 5 predictors for this unit in this block
        padj(j,:) = mafdr(pj,'BHFDR',true);
    end
    Padj{b} = padj;

    Sig{b}.Chair  = padj(:,3) < ALPHA;
    Sig{b}.Drum   = padj(:,4) < ALPHA;
    Sig{b}.Star   = padj(:,5) < ALPHA;
    Sig{b}.AnyObj = any([Sig{b}.Chair Sig{b}.Drum Sig{b}.Star], 2);
end

%% ---------- Magnitudes & Selectivity ----
absObj = @(M) abs(M(:,OBJ_IDX));                 % |β| for objects only
A1 = absObj(B{1}); A2 = absObj(B{2}); A3 = absObj(B{3});    % n × 3

SI = @(A) max(A,[],2) ./ max(eps, sum(A,2));    % selectivity index in [1/3,1]
SI1 = SI(A1); SI2 = SI(A2); SI3 = SI(A3);

%% ---------- Stratified reporting --------
regions   = VALID_REGIONS;                       % already uppercase
celltypes = VALID_CELLTYPES;

% Prepare an optional summary collector for CSV
Summary = table(); rowCollect = 0;

fprintf('\n================ Stratified object-tuning results (FDR per unit) ================\n');

for r = regions
    for ct = celltypes
        idxG = (T.Region==r) & (T.CellType==ct);
        if ~any(idxG), continue; end
        ng = sum(idxG);
        fprintf('\n[%s  ×  %s]  n = %d units\n', r, ct, ng);

        % Subsets
        gA1=A1(idxG,:); gA2=A2(idxG,:); gA3=A3(idxG,:);
        gSI1=SI1(idxG); gSI2=SI2(idxG); gSI3=SI3(idxG);

        gSig1 = Sig{1}; gSig2 = Sig{2}; gSig3 = Sig{3};

        % Valid rows for paired comparisons
        v12 = all(isfinite(gA1),2) & all(isfinite(gA2),2);
        v23 = all(isfinite(gA2),2) & all(isfinite(gA3),2);
        n12 = sum(v12); n23 = sum(v23);

        %% ----- B2 vs B1: |β| per object & SI -----
        fprintf('  B2 vs B1:\n');
        d12 = nan(1,3); p12 = nan(1,3);
        for k=1:3
            [p12(k),~,~] = signrank(gA2(v12,k), gA1(v12,k), 'method','approx');
            d12(k) = median(gA2(v12,k) - gA1(v12,k));
            fprintf('     |%s| Δ=%.4g, p=%.3g  (n=%d)\n', string(PRED(OBJ_IDX(k))), d12(k), p12(k), n12);
        end
        [pSI12,~,~] = signrank(gSI2(v12), gSI1(v12), 'method','approx');
        dSI12 = median(gSI2(v12)-gSI1(v12));
        fprintf('     SI Δ=%.4g, p=%.3g  (n=%d)\n', dSI12, pSI12, n12);

        % Prevalence (FDR<ALPHA) per object & any
        pr1 = [ mean(gSig1.Chair(idxG)), mean(gSig1.Drum(idxG)), mean(gSig1.Star(idxG)), mean(gSig1.AnyObj(idxG)) ];
        pr2 = [ mean(gSig2.Chair(idxG)), mean(gSig2.Drum(idxG)), mean(gSig2.Star(idxG)), mean(gSig2.AnyObj(idxG)) ];
        fprintf('     Prevalence FDR<%.2f  B1: Chair=%.1f%% Drum=%.1f%% Star=%.1f%% Any=%.1f%%\n', ...
            ALPHA, 100*pr1(1),100*pr1(2),100*pr1(3),100*pr1(4));
        fprintf('                              B2: Chair=%.1f%% Drum=%.1f%% Star=%.1f%% Any=%.1f%% (Δ Any=%.1f%%)\n', ...
            100*pr2(1),100*pr2(2),100*pr2(3),100*pr2(4), 100*(pr2(4)-pr1(4)));

        %% ----- B2 vs B3: |β| per object & SI -----
        fprintf('  B2 vs B3:\n');
        d23 = nan(1,3); p23 = nan(1,3);
        for k=1:3
            [p23(k),~,~] = signrank(gA2(v23,k), gA3(v23,k), 'method','approx');
            d23(k) = median(gA2(v23,k) - gA3(v23,k));
            fprintf('     |%s| Δ=%.4g, p=%.3g  (n=%d)\n', string(PRED(OBJ_IDX(k))), d23(k), p23(k), n23);
        end
        [pSI23,~,~] = signrank(gSI2(v23), gSI3(v23), 'method','approx');
        dSI23 = median(gSI2(v23)-gSI3(v23));
        fprintf('     SI Δ=%.4g, p=%.3g  (n=%d)\n', dSI23, pSI23, n23);

        pr3 = [ mean(gSig3.Chair(idxG)), mean(gSig3.Drum(idxG)), mean(gSig3.Star(idxG)), mean(gSig3.AnyObj(idxG)) ];
        fprintf('     Prevalence FDR<%.2f  B3: Chair=%.1f%% Drum=%.1f%% Star=%.1f%% Any=%.1f%% (Δ Any=%.1f%% vs B2)\n', ...
            ALPHA, 100*pr3(1),100*pr3(2),100*pr3(3),100*pr3(4), 100*(pr2(4)-pr3(4)));

        %% ----- Collect to summary table (optional CSV) -----
        if SAVE_CSV
            rowCollect = rowCollect + 1;
            Summary(rowCollect,:) = table( ...
                string(r), string(ct), ng, ...
                n12, d12(1), p12(1), d12(2), p12(2), d12(3), p12(3), dSI12, pSI12, ...
                n23, d23(1), p23(1), d23(2), p23(2), d23(3), p23(3), dSI23, pSI23, ...
                100*pr1(1),100*pr1(2),100*pr1(3),100*pr1(4), ...
                100*pr2(1),100*pr2(2),100*pr2(3),100*pr2(4), ...
                100*pr3(1),100*pr3(2),100*pr3(3),100*pr3(4), ...
                'VariableNames', { ...
                    'Region','CellType','n_units', ...
                    'n_pairs_B2vsB1','d12_Chair','p12_Chair','d12_Drum','p12_Drum','d12_Star','p12_Star','d12_SI','p12_SI', ...
                    'n_pairs_B2vsB3','d23_Chair','p23_Chair','d23_Drum','p23_Drum','d23_Star','p23_Star','d23_SI','p23_SI', ...
                    'Prev_B1_Chair','Prev_B1_Drum','Prev_B1_Star','Prev_B1_Any', ...
                    'Prev_B2_Chair','Prev_B2_Drum','Prev_B2_Star','Prev_B2_Any', ...
                    'Prev_B3_Chair','Prev_B3_Drum','Prev_B3_Star','Prev_B3_Any' ...
                } ...
            );
        end
    end
end

fprintf('\n===============================================================================\n');

%% ----------------- Save CSV (optional) -----------------
if SAVE_CSV && ~isempty(Summary)
    csv_name = fullfile(matpath, erase(matfile,'.mat') + "_ObjectTuning_Stratified_FDR.csv");
    writetable(Summary, csv_name);
    fprintf('Saved summary CSV:\n  %s\n', csv_name);
end

fprintf('Done.\n');
end
