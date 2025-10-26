% File: +glmplots/plot_line.m
function plot_line(ax, x, y, color, lw, style, vis, name)
% Small wrapper to keep plotting concise
if nargin < 6 || isempty(style), style = '-'; end
if nargin < 7 || isempty(vis),   vis   = 'off'; end
if nargin < 8,                   name  = ''; end
plot(ax, x, y, 'Color', color, 'LineWidth', lw, 'LineStyle', style, ...
    'HandleVisibility', vis, 'DisplayName', name);
end