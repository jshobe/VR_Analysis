function betaByGroup = collect_betas_for_block(unitsAll, blockNum, expectedPredictors, groups, groupNames)
% Build struct per group with vectors of betas per expected predictor for one block.
% Missing predictors get NaN; non-finite values are retained for later filtering.

% Normalize types
groupNames = string(groupNames(:));  % column string array
groups     = string(groups(:));      % column string array

% Initialize output struct
betaByGroup = struct();
for g = 1:numel(groupNames)
    betaByGroup(g).Group = groupNames(g);
    for p = 1:numel(expectedPredictors)
        betaByGroup(g).(expectedPredictors{p}) = [];
    end
end

% Iterate units
glmField = sprintf('Block%d', blockNum);
for c = 1:numel(unitsAll)
    gName = groups(c);
    gIdx  = find(groupNames == gName, 1, 'first');
    if isempty(gIdx), continue; end

    if ~isfield(unitsAll(c), 'GLM') || ~isfield(unitsAll(c).GLM, glmField)
        continue;
    end
    G = unitsAll(c).GLM.(glmField);
    if ~isfield(G,'b_coeffs') || ~isfield(G,'names') || isempty(G.b_coeffs) || isempty(G.names)
        continue;
    end

    names = string(G.names(:)');
    betas = double(G.b_coeffs(:)');

    % Map betas into expected predictor order; missing predictors get NaN
    for p = 1:numel(expectedPredictors)
        pred = string(expectedPredictors{p});
        ix = find(names == pred, 1, 'first');
        if isempty(ix)
            val = NaN;
        else
            val = betas(ix);
        end
        predChar = char(pred);  % dynamic field name must be char
        betaByGroup(gIdx).(predChar) = [betaByGroup(gIdx).(predChar), val]; %#ok<AGROW>
    end
end
end