function [groupStarts, groupEnds, groupSizesUsed, labels] = ...
    get_lap_group_ranges(trialNums, ~)
% GET_LAP_GROUP_RANGES
% Returns three balanced, consecutive groups of selected laps.
%
% A scalar input retains compatibility with callers that provide only a lap
% count. A vector supplies the original lap numbers used in group labels.

if isscalar(trialNums)
    nTrials = trialNums;

    if ~isfinite(nTrials) || nTrials < 1 || mod(nTrials, 1) ~= 0
        error('The lap count must be a positive integer.');
    end

    trialNums = 1:nTrials;
else
    trialNums = trialNums(:).';
    nTrials = numel(trialNums);

    if isempty(trialNums) || any(~isfinite(trialNums)) || ...
            any(trialNums < 1) || any(mod(trialNums, 1) ~= 0) || ...
            any(diff(trialNums) <= 0)
        error('trialNums must contain increasing positive integers.');
    end
end

if nTrials < 3
    error('At least three selected laps are required for three lap groups.');
end

nGroups = 3;
baseSize = floor(nTrials / nGroups);
nLargerGroups = mod(nTrials, nGroups);

groupSizesUsed = baseSize * ones(1, nGroups);
groupSizesUsed(1:nLargerGroups) = ...
    groupSizesUsed(1:nLargerGroups) + 1;

groupStarts = [1, 1 + cumsum(groupSizesUsed(1:end-1))];
groupEnds = cumsum(groupSizesUsed);

labels = cell(nGroups, 1);

for g = 1:nGroups
    labels{g} = sprintf( ...
        'Laps %d-%d', ...
        trialNums(groupStarts(g)), ...
        trialNums(groupEnds(g)));
end

end
