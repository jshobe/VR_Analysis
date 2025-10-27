function lut = get_scene_lookup(fileNum, isEvenFile, blockIndex)
% GET_SCENE_LOOKUP
% Map TT codes to scene labels for one block, using A/B/C/D logic:
% - Odd blocks: TT3/TT4 are Nov labels
% - Even blocks: TT5/TT6 are Swap labels
% - TT1/TT2: Familiar labels in all blocks
% - TT7: No objects

if ~isscalar(fileNum) || ~isnumeric(fileNum) || isnan(fileNum)
    error('get_scene_lookup:InvalidFileNum','fileNum must be a finite scalar.');
end
if ~isscalar(isEvenFile) || (~islogical(isEvenFile) && ~ismember(isEvenFile, [0 1]))
    error('get_scene_lookup:InvalidEvenFlag','isEvenFile must be logical.');
end
if ~isscalar(blockIndex) || ~isnumeric(blockIndex) || blockIndex < 1
    error('get_scene_lookup:InvalidBlock','blockIndex must be a positive scalar.');
end

% Three variants (idx):
%  idx=1 : "early even"  (isEvenFile && fileNum <= 30)
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
    C = C_odd; D = D_odd;   % NOV (odd block)
else
    C = C_even; D = D_even; % SWAP (even block)
end

% Build TT -> Label map
lut = containers.Map('KeyType','double','ValueType','char');
lut(1) = A{idx};  % TT1
lut(2) = B{idx};  % TT2

if mod(blockIndex,2) == 1
    lut(3) = C{idx};  % TT3 (odd block)
    lut(4) = D{idx};  % TT4 (odd block)
else
    lut(5) = C{idx};  % TT5 (even block)
    lut(6) = D{idx};  % TT6 (even block)
end

lut(7) = 'No objects';  % TT7
end
