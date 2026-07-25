function [lapMode, lapPct, lapStartPct, lapEndPct, lapLabel] = prompt_lap_selection()

lapChoice = menu( ...
    'Analyze which part of each session by laps?', ...
    'Entire session', ...
    'First % of laps', ...
    'Last % of laps', ...
    'Custom % range of laps');

if isequal(lapChoice, 0)
    error('No lap range selected.');
end

lapMode = 'entire';
lapPct = NaN;
lapStartPct = NaN;
lapEndPct = NaN;
lapLabel = 'Entire session';

switch lapChoice
    case 1
        lapMode = 'entire';
        lapLabel = 'Entire session';

    case 2
        answer = inputdlg({'Enter percent of laps to analyze (0-100):'}, ...
                          'First % of laps', [1 50], {'20'});
        if isempty(answer), error('No lap percentage entered.'); end
        lapPct = str2double(answer{1});
        if ~isfinite(lapPct) || lapPct <= 0 || lapPct > 100
            error('Percent must be > 0 and <= 100.');
        end
        lapMode = 'first';
        lapLabel = sprintf('First %.1f%% of laps', lapPct);

    case 3
        answer = inputdlg({'Enter percent of laps to analyze (0-100):'}, ...
                          'Last % of laps', [1 50], {'20'});
        if isempty(answer), error('No lap percentage entered.'); end
        lapPct = str2double(answer{1});
        if ~isfinite(lapPct) || lapPct <= 0 || lapPct > 100
            error('Percent must be > 0 and <= 100.');
        end
        lapMode = 'last';
        lapLabel = sprintf('Last %.1f%% of laps', lapPct);

    case 4
        answer = inputdlg({'Enter start percent of laps (0-100):', ...
                           'Enter end percent of laps (0-100):'}, ...
                          'Custom % range of laps', [1 50], {'80','100'});
        if isempty(answer), error('No lap range entered.'); end

        lapStartPct = str2double(answer{1});
        lapEndPct   = str2double(answer{2});

        if ~isfinite(lapStartPct) || ~isfinite(lapEndPct) || ...
           lapStartPct < 0 || lapEndPct > 100 || lapStartPct >= lapEndPct
            error('Custom range must satisfy 0 <= start < end <= 100.');
        end

        lapMode = 'custom';
        lapLabel = sprintf('%.1f%%-%.1f%% of laps', lapStartPct, lapEndPct);
end
end