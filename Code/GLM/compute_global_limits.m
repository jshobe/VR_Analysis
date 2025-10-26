function globalLimits = compute_global_limits(unitsAll, predictors, BlockKinds, padFrac)
% Compute global [min, max] limits per predictor across all blocks and units.
% Applies padding by padFrac to widen the range slightly.
%
% Inputs
%   unitsAll   : array of unit structs, each with GLM.BlockN.names and b_coeffs
%   predictors : cellstr list, e.g., {'Pos','Context','Chair','Drum','Star'}
%   BlockKinds : cellstr list of block labels (only used for the number of blocks)
%   padFrac    : scalar >= 0, fraction of range to pad on both sides
%
% Output
%   globalLimits : struct with fields for each predictor, each a 1x2 [min max]

if nargin < 4 || isempty(padFrac), padFrac = 0.05; end
nBlocks = numel(BlockKinds);
globalLimits = struct();

for p = 1:numel(predictors)
    pred = predictors{p};
    allVals = [];

    % Gather values across blocks and units
    for b = 1:nBlocks
        glmField = sprintf('Block%d', b);
        for c = 1:numel(unitsAll)
            if ~isfield(unitsAll(c),'GLM') || ~isfield(unitsAll(c).GLM, glmField), continue; end
            G = unitsAll(c).GLM.(glmField);
            if ~isfield(G,'b_coeffs') || ~isfield(G,'names') || isempty(G.b_coeffs), continue; end

            names = string(G.names(:)');
            betas = double(G.b_coeffs(:)');
            ix = find(names == string(pred), 1, 'first');
            if ~isempty(ix)
                val = betas(ix);
                if isfinite(val), allVals(end+1) = val; %#ok<AGROW>
                end
            end
        end
    end

    % Set limits
    if isempty(allVals)
        % Fallback when predictor not present anywhere
        globalLimits.(pred) = [-1, 1];
    else
        mn = min(allVals);
        mx = max(allVals);
        if mn == mx
            % Expand tiny range so histograms/density kernels work
            delta = max(1e-6, max(1e-6, abs(mn)*0.01));
            mn = mn - delta;
            mx = mx + delta;
        end
        span = mx - mn;
        pad = padFrac * span;
        globalLimits.(pred) = [mn - pad, mx + pad];
    end
end
end