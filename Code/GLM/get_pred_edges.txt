% File: +glmplots/get_pred_edges.m
function edges = get_pred_edges(T, pred, opt)
% Robust x-range based on percentiles across all blocks for this predictor
subset = T(strcmp(string(T.pred), pred), :);
if height(subset) == 0
    edges = [-1 1]; % fallback
    return;
end
x = subset.beta;
lo = prctile(x, 1);
hi = prctile(x, 99);
pad = 0.05*(hi-lo + eps);
edges = [lo-pad, hi+pad];
end