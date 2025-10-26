function io_asserts_blocks(Blocks)
% IO_ASSERTS_BLOCKS  Validate Blocks (cell of vectors or a vector).
if isnumeric(Blocks)
    Blocks = {Blocks}; % allow single vector
end
if ~iscell(Blocks)
    error('Blocks must be a cell array of index vectors or a numeric vector.');
end
for i = 1:numel(Blocks)
    b = Blocks{i};
    if ~isnumeric(b) || ~isvector(b)
        error('Each Blocks{%d} must be a numeric vector of trial indices.', i);
    end
    if any(~isfinite(b)) || any(b<=0)
        error('Blocks{%d} must contain positive finite indices.', i);
    end
end
end
