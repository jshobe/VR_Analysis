function copy_m_to_txt()
% copy_m_to_txt
% Select a folder; create .txt copies of all .m files within (recursively).
% Each .txt is an exact text duplicate saved alongside the .m file.

    % Choose a starting folder (adjust defaultRoot as you like)
    defaultRoot = 'Z:\Justin\VR mice';
    root = uigetdir(defaultRoot, 'Select folder containing .m files');
    if isequal(root, 0)
        fprintf('No folder selected. Aborting.\n');
        return;
    end

    % Settings
    includeSubfolders = true;   % set false to only process the selected folder
    overwriteExisting = true;  % set true to overwrite existing .txt files

    % Find .m files
    fileList = {};
    if includeSubfolders
        % Robust across MATLAB versions: use genpath to gather subfolders
        p = genpath(root);
        folders = strsplit(p, pathsep);
        for i = 1:numel(folders)
            d = folders{i};
            if isempty(d) || ~isfolder(d), continue; end
            S = dir(fullfile(d, '*.m'));
            for k = 1:numel(S)
                fileList{end+1} = fullfile(S(k).folder, S(k).name); %#ok<AGROW>
            end
        end
    else
        S = dir(fullfile(root, '*.m'));
        for k = 1:numel(S)
            fileList{end+1} = fullfile(S(k).folder, S(k).name); %#ok<AGROW>
        end
    end

    if isempty(fileList)
        fprintf('No .m files found in "%s".\n', root);
        return;
    end

    fprintf('Found %d .m file(s).\n', numel(fileList));

    % Copy each .m to a .txt with the same base name
    nCopied = 0;
    nSkipped = 0;
    for i = 1:numel(fileList)
        mPath = fileList{i};
        [folder, base, ~] = fileparts(mPath);
        txtPath = fullfile(folder, [base '.txt']);

        if ~overwriteExisting && exist(txtPath, 'file') == 2
            nSkipped = nSkipped + 1;
            fprintf('Skip (exists): %s\n', txtPath);
            continue;
        end

        try
            content = fileread(mPath);   % read as text
            fid = fopen(txtPath, 'w');   % write as text
            if fid == -1
                warning('Failed to open for write: %s', txtPath);
                continue;
            end
            fwrite(fid, content, 'char');
            fclose(fid);
            nCopied = nCopied + 1;
            fprintf('Copied: %s -> %s\n', mPath, txtPath);
        catch ME
            warning('Failed to copy "%s": %s', mPath, ME.message);
        end
    end

    fprintf('Done. Copied: %d, Skipped: %d, Total: %d\n', nCopied, nSkipped, numel(fileList));
end