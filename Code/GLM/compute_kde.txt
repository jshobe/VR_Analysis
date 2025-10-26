% File: +glmplots/compute_kde.m
function [f, bw] = compute_kde(vec, xi_eval, bw_user)
% Returns density f at xi_eval and the bandwidth used
if ~isempty(bw_user)
    [f, ~, bw] = ksdensity(vec, xi_eval, 'Bandwidth', bw_user);
else
    [f, ~, bw] = ksdensity(vec, xi_eval);
end
end