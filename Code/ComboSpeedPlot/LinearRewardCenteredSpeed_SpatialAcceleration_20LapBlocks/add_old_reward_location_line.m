function h = add_old_reward_location_line(ax, P, showLabel)
% ADD_OLD_REWARD_LOCATION_LINE
% Adds the first session's reward location to a later reward-centered plot.
%
% The current session reward remains at x = 0. The old reward position is
% expressed relative to the current reward center.

h = gobjects(0);

if nargin < 3
    showLabel = false;
end

if ~isfield(P, 'showOldRewardLine') || ~P.showOldRewardLine
    return
end

if ~isfield(P, 'oldRewardRelative_deg') || ...
        ~isfinite(P.oldRewardRelative_deg)
    return
end

oldX = P.oldRewardRelative_deg;
oldColor = [0.00 0.60 0.10];

h = xline(ax, oldX, '-', ...
    'Color', oldColor, ...
    'LineWidth', 1.7, ...
    'HandleVisibility', 'off');

if showLabel
    yl = ylim(ax);

    if strcmpi(ax.YDir, 'reverse')
        yText = yl(1) + 0.03 * diff(yl);
    else
        yText = yl(2) - 0.03 * diff(yl);
    end

    if oldX >= 0
        horizontalAlignment = 'right';
        xText = oldX - 2;
    else
        horizontalAlignment = 'left';
        xText = oldX + 2;
    end

    text(ax, ...
        xText, ...
        yText, ...
        'old reward location', ...
        'Color', oldColor, ...
        'Rotation', 90, ...
        'HorizontalAlignment', horizontalAlignment, ...
        'VerticalAlignment', 'top', ...
        'FontSize', max(ax.FontSize - 1, 7), ...
        'FontWeight', 'bold', ...
        'Interpreter', 'none', ...
        'Clipping', 'on');
end

end
