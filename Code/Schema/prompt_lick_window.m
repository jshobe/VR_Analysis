function [lickNearRewardEnabled, lickNearRewardWindow_deg] = prompt_lick_window()

keepOnlyTrialsWithLickNearReward = menu( ...
    'Keep only target trials with a lick near reward delivery?', ...
    'No', ...
    'Yes');

if isequal(keepOnlyTrialsWithLickNearReward, 0)
    error('No lick-near-reward option selected.');
end

lickNearRewardEnabled = (keepOnlyTrialsWithLickNearReward == 2);

if lickNearRewardEnabled
    answer = inputdlg({'Enter lick window around reward delivery (deg):'}, ...
                      'Lick near reward window', [1 50], {'5'});
    if isempty(answer)
        error('No lick window entered.');
    end
    lickNearRewardWindow_deg = str2double(answer{1});
    if ~isfinite(lickNearRewardWindow_deg) || lickNearRewardWindow_deg <= 0
        error('lickNearRewardWindow_deg must be > 0.');
    end
else
    lickNearRewardWindow_deg = 5;
end
end