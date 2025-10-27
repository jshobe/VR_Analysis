function [rate_mean_halls, counts, Blocks] = analyze_blocks(rate_4cm_3D, halls, varargin)
% ANALYZE_BLOCKS
% Computes block-wise averages of firing rates per trial type
%
% Inputs:
%   rate_4cm_3D : [nTrials x nBins x nUnits] firing rate data
%   halls       : [nTrials x 1] trial type codes (1-7)
%
% Options:
%   'Blocks'    : {12:174, 178:337, 341:520} - trial blocks to analyze
%
% Outputs:
%   rate_mean_halls : {1 x nBlocks} cell of [nUnits x nBins x 7] averages
%   counts          : {1 x nBlocks} cell of [1 x 7] trial counts per type
%   Blocks          : validated block indices (clipped to [1..nTrials])

    % ---------------- Parse options ----------------
    p = inputParser;
    % Default blocks can be dataset-specific; feel free to change default to {[]} if you prefer "all trials"
    addParameter(p, 'Blocks', {12:174, 178:337, 341:520}, @(x) iscell(x) || isnumeric(x));
    parse(p, varargin{:});
    Blocks = p.Results.Blocks;

    % Accept numeric vector for convenience -> wrap into a single block
    if isnumeric(Blocks)
        Blocks = {Blocks};
    end

    % ---------------- Validate inputs ----------------
    [nTrials, nBins, nUnits] = size(rate_4cm_3D);
    halls = halls(:);

    % Pad or trim halls to exactly nTrials
    if numel(halls) < nTrials
        halls = [halls; NaN(nTrials - numel(halls), 1)];
    elseif numel(halls) > nTrials
        halls = halls(1:nTrials);
    end

    % Clip blocks to valid trial range
    Blocks = clip_blocks(Blocks, nTrials);
    nBlocks = numel(Blocks);

    % Initialize outputs
    rate_mean_halls = cell(1, nBlocks);
    counts          = cell(1, nBlocks);

    % ---------------- Process each block ----------------
    for b = 1:nBlocks
        [rate_mean_halls{b}, counts{b}] = compute_block_averages( ...
            rate_4cm_3D, halls, Blocks{b}, nUnits, nBins);
    end
end

%% ==================== Helper Functions ====================

function Blocks = clip_blocks(Blocks, nTrials)
    % Clip block indices to [1..nTrials] and remove empty blocks
    valid_blocks = false(1, numel(Blocks));
    for b = 1:numel(Blocks)
        bb = Blocks{b}(:);
        bb = bb(isfinite(bb) & bb >= 1 & bb <= nTrials);
        Blocks{b} = unique(bb, 'stable');
        valid_blocks(b) = ~isempty(Blocks{b});
    end
    Blocks = Blocks(valid_blocks);
end

function [rate_mean, trial_counts] = compute_block_averages(rate_4cm_3D, halls, block_trials, nUnits, nBins)
    % Compute average firing rates per trial type for one block
    
    nTypes = 7;
    rate_mean    = NaN(nUnits, nBins, nTypes);
    trial_counts = zeros(1, nTypes);
    
    if isempty(block_trials)
        return;
    end
    
    % Get data for this block
    block_data  = rate_4cm_3D(block_trials, :, :);  % [nBlockTrials x nBins x nUnits]
    block_halls = halls(block_trials);
    
    for TT = 1:nTypes
        idx = (block_halls == TT);
        trial_counts(TT) = sum(idx);
        if trial_counts(TT) == 0, continue; end
        
        % Trials of this type: [nTrialsOfType x nBins x nUnits]
        type_data  = block_data(idx, :, :);
        
        % Average across trials -> [1 x nBins x nUnits]
        type_mean  = mean(type_data, 1, 'omitnan');
        
        % Reorder to [nUnits x nBins] for storage
        % Either of these is fine:
        % m = squeeze(type_mean)';                      % [nBins x nUnits] -> transpose
        % rate_mean(:, :, TT) = m';                     % [nUnits x nBins]
        rate_mean(:, :, TT) = permute(type_mean, [3 2 1]);  % [nUnits x nBins x 1]
    end
end
