function write_manifest(path, stage, opts, extras)
[manDir,~] = fileparts(path);
if ~exist(manDir,'dir'), mkdir(manDir); end
S = struct('stage',stage, ...
           'timestamp',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')), ...
           'opts',opts, 'extras',extras);
fid = fopen(path,'w'); fprintf(fid, jsonencode(S,'PrettyPrint',true)); fclose(fid);
end
