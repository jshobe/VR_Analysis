function R = process_region(animal_path, region_path, varargin)
% PROCESS_REGION (STRICT)
% Returns a struct R with:
%   R.tt_counts   : [T x ...] time-series counts/rates (already computed upstream)
%   R.binCenters  : [T x 1]   x-axis for the time base
%
% This function is intentionally strict:
% - It DOES NOT guess at raw formats or do new computations.
% - It only loads existing precomputed time-series if present, then
%   applies optional block selection and optional smoothing.
% - If required inputs are missing, it errors with explicit instructions.
%
% Expected sources (any ONE of these must exist inside region_path):
%   1) <region_path>\Derived_V2\Derived_V2.mat with struct DerivedV2
%         containing fields: tt_counts, binCenters
%   2) <region_path>\Derived\tt_counts.mat with variables: tt_counts, binCenters
%   3) <region_path>\Processed\tt_counts.mat with variables: tt_counts, binCenters
%
% Optional parameters:
%   'Blocks'        : {[]} or cell array of index ranges (e.g., {12:174,178:337})
%   'SmoothingWin'  : scalar integer window for simple moving average (default 12)
%
% Example:
%   R = process_region('Z:\Justin\VR mice\VR42', '...\PPC', ...
%                      'Blocks',{12:174,178:337}, 'SmoothingWin',12);

% -------------------- Parse options --------------------
p = inputParser;
p.addParameter('Blocks',       {[]}, @(x) iscell(x) || isnumeric(x) || isempty(x));
p.addParameter('SmoothingWin', 12,    @(x) isnumeric(x) && isscalar(x) && x>=1);
p.parse(varargin{:});
opt = p.Results;

% -------------------- Resolve candidate sources --------------------
cand = {
    fullfile(region_path, 'Derived_V2', 'Derived_V2.mat'), 'DerivedV2';   % struct with fields
    fullfile(region_path, 'Derived',    'tt_counts.mat'),  '';            % plain vars
    fullfile(region_path, 'Processed',  'tt_counts.mat'),  ''             % plain vars
};

tt_counts = [];
binCenters = [];

for i = 1:size(cand,1)
    f = cand{i,1};
    key = cand{i,2};
    if exist(f,'file')
        S = load(f);
        if ~isempty(key)
            if ~isfield(S, key)
                error('File found but missing struct "%s": %s', key, f);
            end
            D = S.(key);
            require_field(D, 'tt_counts', f, 'DerivedV2.tt_counts');
            require_field(D, 'binCenters', f, 'DerivedV2.binCenters');
            tt_counts  = D.tt_counts;
            binCenters = D.binCenters;
        else
            % Expect plain variables
            require_field(S, 'tt_counts', f, 'tt_counts');
            require_field(S, 'binCenters', f, 'binCenters');
            tt_counts  = S.tt_counts;
            binCenters = S.binCenters;
        end
        break;
    end
end

if isempty(tt_counts) || isempty(binCenters)
    msg = sprintf(['process_region could not find precomputed time-series.\n' ...
                   'Looked for:\n' ...
                   ' 1) %s (DerivedV2.tt_counts / .binCenters)\n' ...
                   ' 2) %s (tt_counts, binCenters)\n' ...
                   ' 3) %s (tt_counts, binCenters)\n' ...
                   '\nPlease ensure one of these files exists and contains the variables.\n'], ...
                   cand{1,1}, cand{2,1}, cand{3,1});
    error(msg);
end

% -------------------- Basic validation --------------------
if ~isvector(binCenters)
    error('binCenters must be a vector (got size %s).', mat2str(size(binCenters)));
end
binCenters = binCenters(:); % force column

T = numel(binCenters);
if size(tt_counts,1) ~= T
    error('tt_counts first dimension (%d) must match numel(binCenters) (%d).', size(tt_counts,1), T);
end

% -------------------- Apply block selection (optional) --------------------
idx = 1:T;
if iscell(opt.Blocks)
    % Merge cell of ranges into one logical mask
    if isempty(opt.Blocks) || (numel(opt.Blocks)==1 && isempty(opt.Blocks{1}))
        % keep all
    else
        mask = false(1, T);
        for k = 1:numel(opt.Blocks)
            rngk = opt.Blocks{k};
            check_range(rngk, T, 'Blocks{%d}', k);
            mask(rngk) = true;
        end
        idx = find(mask);
        binCenters = binCenters(idx);
        tt_counts  = tt_counts(idx, :);
    end
elseif isnumeric(opt.Blocks) && ~isempty(opt.Blocks)
    rngk = opt.Blocks(:).';
    check_range(rngk, T, 'Blocks', 0);
    binCenters = binCenters(rngk);
    tt_counts  = tt_counts(rngk, :);
else
    % keep all
end

% -------------------- Apply smoothing (optional) --------------------
win = round(opt.SmoothingWin);
if win > 1
    % simple moving average over time dimension
    kernel = ones(win,1) / win;
    if isvector(tt_counts)
        tt_counts = conv(tt_counts(:), kernel, 'same');
    else
        % apply per column
        tt_counts = conv2(tt_counts, kernel, 'same');
    end
end

% -------------------- Return struct --------------------
R = struct();
R.tt_counts  = tt_counts;
R.binCenters = binCenters;

end

% ======== helpers ========

function require_field(S, fld, filePath, qualName)
if ~isfield(S, fld)
    error('Missing required field "%s" in %s (expected %s).', fld, filePath, qualName);
end
end

function check_range(rngk, T, label, kidx)
if ~isnumeric(rngk) || any(~isfinite(rngk)) || any(rngk < 1) || any(rngk > T)
    if kidx>0
        error('%s must be valid indices within [1..%d]. Got: %s', sprintf(label,kidx), T, mat2str(rngk));
    else
        error('%s must be valid indices within [1..%d]. Got: %s', label, T, mat2str(rngk));
    end
end
end
