function fingerprint = get_file_fingerprint(filePath, includeHash)
% GET_FILE_FINGERPRINT Collects stable source-file identity information.

if nargin < 2 || isempty(includeHash)
    includeHash = true;
end

filePath = char(filePath);
info = dir(filePath);

if isempty(info) || info.isdir
    error('Source file not found: %s', filePath);
end

fingerprint = struct();
fingerprint.name = info.name;
fingerprint.folder = info.folder;
fingerprint.fullPath = fullfile(info.folder, info.name);
fingerprint.bytes = info.bytes;
fingerprint.modifiedDatenum = info.datenum;
fingerprint.modifiedText = info.date;

if includeHash
    fingerprint.sha256 = compute_file_sha256(filePath);
else
    fingerprint.sha256 = '';
end

end
