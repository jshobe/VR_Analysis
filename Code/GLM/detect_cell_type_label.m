function label = detect_cell_type_label(u)
% Return a cell-type label from common unit fields; fallback to 'Unknown'
candidates = {'CellType','cell_type','WaveformClass','waveform_class','Type','type','Class','class'};
label = 'Unknown';
for i = 1:numel(candidates)
    fn = candidates{i};
    if isfield(u, fn) && ~isempty(u.(fn))
        v = u.(fn);
        try
            if isstring(v) || ischar(v)
                vstr = string(v);
                if strlength(vstr) > 0
                    label = char(vstr);
                    return;
                end
            elseif isnumeric(v)
                label = sprintf('Class%d', v);
                return;
            end
        catch
            % ignore and continue
        end
    end
end
end