function [trialNums, trialLabel] = select_laps_to_plot(nTrialsTotal)

trialChoice = menu( ...
    sprintf('Detected %d complete laps. Which laps should be plotted?', nTrialsTotal), ...
    'All laps', ...
    'First N laps', ...
    'Last N laps', ...
    'Custom lap range');

if isequal(trialChoice, 0)
    error('No trial selection made.');
end

switch trialChoice
    case 1
        trialNums = 1:nTrialsTotal;
        trialLabel = sprintf('all %d laps', nTrialsTotal);

    case 2
        answer = inputdlg({'Enter number of first laps to plot:'}, ...
            'First N laps', [1 50], {num2str(nTrialsTotal)});

        if isempty(answer)
            error('No trial number entered.');
        end

        nPlot = round(str2double(answer{1}));
        if ~isfinite(nPlot) || nPlot < 1
            error('Number of laps must be >= 1.');
        end

        nPlot = min(nPlot, nTrialsTotal);
        trialNums = 1:nPlot;
        trialLabel = sprintf('first %d of %d laps', nPlot, nTrialsTotal);

    case 3
        answer = inputdlg({'Enter number of last laps to plot:'}, ...
            'Last N laps', [1 50], {num2str(min(50,nTrialsTotal))});

        if isempty(answer)
            error('No trial number entered.');
        end

        nPlot = round(str2double(answer{1}));
        if ~isfinite(nPlot) || nPlot < 1
            error('Number of laps must be >= 1.');
        end

        nPlot = min(nPlot, nTrialsTotal);
        trialNums = (nTrialsTotal - nPlot + 1):nTrialsTotal;
        trialLabel = sprintf('last %d of %d laps', nPlot, nTrialsTotal);

    case 4
        answer = inputdlg({'Start lap:', 'End lap:'}, ...
            'Custom lap range', [1 50], {'1', num2str(nTrialsTotal)});

        if isempty(answer)
            error('No lap range entered.');
        end

        lapStart = round(str2double(answer{1}));
        lapEnd   = round(str2double(answer{2}));

        if ~isfinite(lapStart) || ~isfinite(lapEnd) || ...
           lapStart < 1 || lapEnd > nTrialsTotal || lapStart > lapEnd
            error('Invalid lap range.');
        end

        trialNums = lapStart:lapEnd;
        trialLabel = sprintf('laps %d-%d of %d', lapStart, lapEnd, nTrialsTotal);
end

end