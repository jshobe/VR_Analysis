function io_asserts_metadata(metadata_table)
% IO_ASSERTS_METADATA  Validate metadata table and ClusterID column.
if ~istable(metadata_table)
    error('metadata_table must be a table.');
end
if ~ismember('ClusterID', metadata_table.Properties.VariableNames)
    error('metadata_table must contain a ''ClusterID'' column.');
end
cid = metadata_table.ClusterID;
if ~isnumeric(cid)
    try
        cid = str2double(string(cid));
    catch
        error('metadata_table.ClusterID must be numeric or convertible to numeric.');
    end
    if any(isnan(cid))
        error('metadata_table.ClusterID contains non-convertible values.');
    end
end
end
