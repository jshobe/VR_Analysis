function [groupStarts, groupEnds, groupSizesUsed] = get_lap_group_ranges(nTrials, cfg)
% GET_LAP_GROUP_RANGES
% Returns consecutive lap ranges shared by speed and acceleration summaries.
%
% Preferred configuration:
%   cfg.lapGroupSizes = [34 33 33];
%
% For fewer than 100 plotted laps, the final available group is truncated.
% For backward compatibility, cfg.accelerationLapBlockSize is used only when
% cfg.lapGroupSizes is absent.

if ~isscalar(nTrials) || ~isfinite(nTrials) || ...
        nTrials < 1 || mod(nTrials, 1) ~= 0
    error('nTrials must be a positive integer.');
end

if isfield(cfg, 'lapGroupSizes') && ~isempty(cfg.lapGroupSizes)
    groupSizes = cfg.lapGroupSizes(:).';

    if any(~isfinite(groupSizes)) || any(groupSizes < 1) || ...
            any(mod(groupSizes, 1) ~= 0)
        error('cfg.lapGroupSizes must contain positive integers.');
    end

    % If a future configuration plots more laps than the explicitly listed
    % groups cover, retain all remaining laps as one final group.
    if sum(groupSizes) < nTrials
        groupSizes(end + 1) = nTrials - sum(groupSizes);
    end

    groupStartsAll = [1, 1 + cumsum(groupSizes(1:end-1))];
    groupEndsAll = cumsum(groupSizes);

    keep = groupStartsAll <= nTrials;
    groupStarts = groupStartsAll(keep);
    groupEnds = min(groupEndsAll(keep), nTrials);
    groupSizesUsed = groupEnds - groupStarts + 1;
    return
end

% Legacy equal-block fallback.
if ~isfield(cfg, 'accelerationLapBlockSize') || ...
        ~isscalar(cfg.accelerationLapBlockSize) || ...
        ~isfinite(cfg.accelerationLapBlockSize) || ...
        cfg.accelerationLapBlockSize < 1 || ...
        mod(cfg.accelerationLapBlockSize, 1) ~= 0
    error(['Define cfg.lapGroupSizes or provide a positive integer ' ...
           'cfg.accelerationLapBlockSize.']);
end

blockSize = cfg.accelerationLapBlockSize;
groupStarts = 1:blockSize:nTrials;
groupEnds = min(groupStarts + blockSize - 1, nTrials);
groupSizesUsed = groupEnds - groupStarts + 1;

end
