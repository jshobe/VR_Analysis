function lut = get_scene_lookup(fileNum, isEvenFile, blockIndex)
% GET_SCENE_LOOKUP
% Map TT codes to scene labels for one block, using your A/B/C/D logic:
% - Odd blocks: TT3/TT4 are Nov labels
% - Even blocks: TT5/TT6 are Swap labels
% - TT1/TT2 are Fam labels in all blocks
% - TT7: No objects
%
% Inputs:
%   fileNum     : numeric file/session number (from filename)
%   isEvenFile  : boolean (true if even-numbered file)
%   blockIndex  : 1-based block index
%
% Output:
%   lut : containers.Map (double -> char) TT -> label

    % Base label sets from your script
    % Three variants (idx):
    %  idx=1 : "early even" (isEvenFile && fileNum <= 30)
    %  idx=2 : "recent even" (isEvenFile && fileNum > 30)
    %  idx=3 : "odd file"    (~isEvenFile)
    A = {'Fam D-S' , 'Fam S-C', 'Fam C-S'};
    B = {'Fam S-C' , 'Fam D-S', 'Fam S-D'};

    % Odd block (NOV) label sets
    C_odd = {'Nov D-S' , 'Nov S-C', 'Nov C-S'};
    D_odd = {'Nov S-C' , 'Nov D-S', 'Nov S-D'};

    % Even block (SWAP) label sets
    C_even = {'Swap S-D','Swap C-S','Swap S-C'};
    D_even = {'Swap C-S','Swap S-D','Swap D-S'};

    % Select index by file parity/number
    if isEvenFile && isfinite(fileNum) && fileNum <= 30
        idx = 1;           % early even
    elseif isEvenFile
        idx = 2;           % recent even
    else
        idx = 3;           % odd file
    end

    % Choose C/D sets by block parity
    if mod(blockIndex, 2) == 1
        C = C_odd; D = D_odd;   % NOV
    else
        C = C_even; D = D_even; % SWAP
    end

    % Build TT -> Label map
    lut = containers.Map('KeyType','double','ValueType','char');
    lut(1) = A{idx};  % TT1
    lut(2) = B{idx};  % TT2

    if mod(blockIndex, 2) == 1
        lut(3) = C{idx};  % TT3 (odd block)
        lut(4) = D{idx};  % TT4 (odd block)
    else
        lut(5) = C{idx};  % TT5 (even block)
        lut(6) = D{idx};  % TT6 (even block)
    end

    lut(7) = 'No objects';  % TT7
end