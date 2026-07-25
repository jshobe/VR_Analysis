function hashHex = compute_file_sha256(filePath)
% COMPUTE_FILE_SHA256 Returns the lowercase SHA-256 hash of a file.

if ~(ischar(filePath) || (isstring(filePath) && isscalar(filePath)))
    error('filePath must be a character vector or scalar string.');
end

filePath = char(filePath);

if ~isfile(filePath)
    error('File not found: %s', filePath);
end

fid = fopen(filePath, 'rb');
if fid < 0
    error('Could not open file for hashing: %s', filePath);
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

try
    md = javaMethod('getInstance', 'java.security.MessageDigest', 'SHA-256');
catch ME
    error(['SHA-256 hashing requires MATLAB Java support. ' ...
        'Original error: %s'], ME.message);
end

while true
    bytes = fread(fid, 1024 * 1024, '*uint8');
    if isempty(bytes)
        break
    end
    md.update(typecast(bytes(:), 'int8'));
end

digest = typecast(md.digest(), 'uint8');
hashHex = lower(reshape(dec2hex(digest, 2).', 1, []));

end
