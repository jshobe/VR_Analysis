function [mouseName, sessionDate] = parse_mouse_date(file)

[~, baseName, ~] = fileparts(file);

mouseTok = regexp(baseName, '([A-Za-z]{2}\d+)', 'tokens', 'once');

if ~isempty(mouseTok)
    mouseName = mouseTok{1};
else
    mouseName = 'UnknownMouse';
end

dateTok = regexp(baseName, '(\d{4}-\d{2}-\d{2})', 'tokens', 'once');

if ~isempty(dateTok)
    sessionDate = dateTok{1};
else
    sessionDate = 'UnknownDate';
end

end