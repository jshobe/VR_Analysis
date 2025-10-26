% File: +glmplots/get_block_data.m
function [vecAll, regionAll] = get_block_data(T, pred, b)
subset = T(T.block==b & strcmp(string(T.pred), pred), :);
vecAll    = subset.beta;
regionAll = cellstr(subset.region);
end