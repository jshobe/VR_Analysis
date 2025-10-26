function io_asserts_clusterIDs(clusterIDs)
% IO_ASSERTS_CLUSTERIDS  Validate clusterIDs vector.
validateattributes(clusterIDs, {'numeric'}, {'vector','nonempty'}, mfilename, 'clusterIDs');
if any(~isfinite(clusterIDs))
    error('clusterIDs contains non-finite values.');
end
% All OK, including 0 as a valid label.
end
