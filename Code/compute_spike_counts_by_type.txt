function [SpikeCountsByType, SpikeCountsByTypeByBlock] = compute_spike_counts_by_type(counts4cm_3D, halls, Blocks)
% COMPUTE_SPIKE_COUNTS_BY_TYPE
% Derive per-unit, per-trial-type spike counts from counts4cm_3D (the canonical fast-gated source).
%
% Inputs:
%   counts4cm_3D : [nTrials x nBins x nUnits] 3D array of spike counts per bin (fast-gated)
%   halls        : [nTrials x 1] trial type codes (1..7)
%   Blocks       : cell array of trial indices per block
%
% Outputs:
%   SpikeCountsByType         : [nUnits x 7] total spikes per type (session-wide)
%   SpikeCountsByTypeByBlock  : [nUnits x 7 x nBlocks] total spikes per type per block

[nTrials, ~, nUnits] = size(counts4cm_3D);
nBlocks = numel(Blocks);

% Ensure halls is sized to nTrials
halls = halls(:);
if numel(halls) < nTrials
    halls = [halls; NaN(nTrials - numel(halls), 1)];
elseif numel(halls) > nTrials
    halls = halls(1:nTrials);
end

% Session-wide spike counts
SpikeCountsByType = zeros(nUnits, 7);
for tt = 1:7
    trials_tt = find(halls(:) == tt);
    trials_tt = trials_tt(trials_tt >= 1 & trials_tt <= nTrials);
    if isempty(trials_tt), continue; end
    
    % Sum across bins (dim 2) and trials (dim 1) for each unit
    % counts4cm_3D(trials_tt, :, :) -> [nTrials_tt x nBins x nUnits]
    % sum over dims 1 and 2 -> [1 x 1 x nUnits] -> squeeze to [nUnits x 1]
    spike_counts_tt = squeeze(sum(sum(counts4cm_3D(trials_tt, :, :), 1), 2));
    
    % Handle scalar case (nUnits == 1)
    if isscalar(spike_counts_tt)
        spike_counts_tt = spike_counts_tt(:);
    end
    
    SpikeCountsByType(:, tt) = spike_counts_tt;
end

% Per-block spike counts
SpikeCountsByTypeByBlock = zeros(nUnits, 7, nBlocks);
for b = 1:nBlocks
    tr_ix = Blocks{b}(:);
    tr_ix = tr_ix(isfinite(tr_ix) & tr_ix >= 1 & tr_ix <= nTrials);
    if isempty(tr_ix), continue; end
    
    for tt = 1:7
        trials_tt = tr_ix(halls(tr_ix) == tt);
        if isempty(trials_tt), continue; end
        
        % Sum across bins and trials for this block/type
        spike_counts_tt = squeeze(sum(sum(counts4cm_3D(trials_tt, :, :), 1), 2));
        
        % Handle scalar case
        if isscalar(spike_counts_tt)
            spike_counts_tt = spike_counts_tt(:);
        end
        
        SpikeCountsByTypeByBlock(:, tt, b) = spike_counts_tt;
    end
end
end