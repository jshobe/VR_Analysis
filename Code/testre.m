% analyze_object_tuning.m (run after your GLM has populated MasterTable_VR)

T = MT_reduced;  % assumes fields GLM_Block{1,2,3}_Coeffs and _pvals exist
n = height(T);

predNames = {'Pos','Context','Chair','Drum','Star'};
OBJ_IDX   = [3 4 5];  % columns for Chair, Drum, Star in your 5-col scheme

% Helper to unpack a cell column of 1x5 coefs/pvals into numeric Nx5
unpack = @(C) cellfun(@(x) (isempty(x) || all(isnan(x))) * nan(1,5) + (~isempty(x))*x, C, 'uni', 0);
toMat  = @(C) cell2mat(unpack(C)');

B = cell(1,3); P = cell(1,3);
for b = 1:3
    B{b} = toMat(T.(sprintf('GLM_Block%d_Coeffs',b)));   % n x 5
    P{b} = toMat(T.(sprintf('GLM_Block%d_pvals', b)));   % n x 5
end

% Keep only units with finite object betas in the blocks being compared
valid12 = all(isfinite(B{1}(:,OBJ_IDX)),2) & all(isfinite(B{2}(:,OBJ_IDX)),2);
valid23 = all(isfinite(B{2}(:,OBJ_IDX)),2) & all(isfinite(B{3}(:,OBJ_IDX)),2);

% |beta| magnitudes per object
absObj = @(M) abs(M(:,OBJ_IDX));           % returns n x 3 (Chair,Drum,Star)
A1 = absObj(B{1}); A2 = absObj(B{2}); A3 = absObj(B{3});

% Selectivity index: max(|β_obj|)/sum(|β_obj|)
SI = @(A) max(A,[],2) ./ max(eps, sum(A,2));  % n x 1, in [1/3,1]
SI1 = SI(A1); SI2 = SI(A2); SI3 = SI(A3);

% Significance prevalence for objects (any object significant)
alpha = 0.05;
anySig = @(Pmat) any(Pmat(:,OBJ_IDX) < alpha, 2);  % n x 1 logical
S1 = anySig(P{1}); S2 = anySig(P{2}); S3 = anySig(P{3});

% ----- Paired stats: B2 vs B1 -----
fprintf('\n=== Object tuning: Block 2 vs Block 1 ===\n');
idx = valid12;
for k = 1:3
    [p,~,stats] = signrank(A2(idx,k), A1(idx,k), 'method','approx');  % Wilcoxon
    d = median(A2(idx,k) - A1(idx,k));                                % median paired diff
    fprintf(' |%s|: n=%d, medianΔ=%.4g, p=%.3g (signed-rank)\n', predNames{OBJ_IDX(k)}, sum(idx), d, p);
end
[pSI,~,~] = signrank(SI2(idx), SI1(idx), 'method','approx');
dSI = median(SI2(idx) - SI1(idx));
fprintf(' SI (selectivity): n=%d, medianΔ=%.4g, p=%.3g\n', sum(idx), dSI, pSI);

% Prevalence change (any object significant)
n12 = sum(idx);
prop1 = mean(S1(idx)); prop2 = mean(S2(idx));
fprintf(' Any-object significant: B1=%.1f%%, B2=%.1f%% (Δ=%.1f%%)\n', 100*prop1, 100*prop2, 100*(prop2-prop1));

% ----- Paired stats: B2 vs B3 -----
fprintf('\n=== Object tuning: Block 2 vs Block 3 ===\n');
idx = valid23;
for k = 1:3
    [p,~,~] = signrank(A2(idx,k), A3(idx,k), 'method','approx');
    d = median(A2(idx,k) - A3(idx,k));
    fprintf(' |%s|: n=%d, medianΔ=%.4g, p=%.3g (signed-rank)\n', predNames{OBJ_IDX(k)}, sum(idx), d, p);
end
[pSI,~,~] = signrank(SI2(idx), SI3(idx), 'method','approx');
dSI = median(SI2(idx) - SI3(idx));
fprintf(' SI (selectivity): n=%d, medianΔ=%.4g, p=%.3g\n', sum(idx), dSI, pSI);

prop3 = mean(S3(idx));
fprintf(' Any-object significant: B3=%.1f%%, B2=%.1f%% (Δ=%.1f%%)\n', 100*prop3, 100*prop2, 100*(prop2-prop3));

% ----- Optional: FDR across 3 object tests per contrast -----
% Collect p-values for |Chair|, |Drum|, |Star| in each contrast and FDR-correct
collect_p = @(Aref,Abase,idx) [ ...
    signrank(Aref(idx,1), Abase(idx,1), 'method','approx'); ...
    signrank(Aref(idx,2), Abase(idx,2), 'method','approx'); ...
    signrank(Aref(idx,3), Abase(idx,3), 'method','approx') ];
p12 = collect_p(A2,A1,valid12);
p23 = collect_p(A2,A3,valid23);
bh = @(p) p .* numel(p) ./ (1:numel(p))';  % simple BH (assumes sorted ascending)
[ps12,ord12] = sort(p12); q12 = bh(ps12); q12(ord12) = q12;
[ps23,ord23] = sort(p23); q23 = bh(ps23); q23(ord23) = q23;
fprintf('\nFDR q-values (B2>B1) for |Chair|,|Drum|,|Star|: [%0.3g  %0.3g  %0.3g]\n', q12);
fprintf('FDR q-values (B2>B3) for |Chair|,|Drum|,|Star|: [%0.3g  %0.3g  %0.3g]\n', q23);
