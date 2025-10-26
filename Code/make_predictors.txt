% make_predictors_once.m
% One-time script to build and save four predictor files in the current folder (pwd).
% Files:
%   - Predictors_Odd_Block13.xlsx
%   - Predictors_Odd_Block2.xlsx
%   - Predictors_Even_Block13.xlsx
%   - Predictors_Even_Block2.xlsx
%
% Spec:
% - Scene length: nBins = 133 (1 bin = 4 cm) [can change; landmarks scale by nBins/133]
% - Pos: binary (0 for bins 1..66, 1 for bins 67..133)
% - Context: 0=A, 1=B
% - Objects: Chair(C), Drum(D), Star(S)
%   - Mid-scene: start at bin 20 with value 0.25, linearly ramp to 1 at bin 67, then 0
%   - End-scene: start at bin 87 with value 0.25, linearly ramp to 1 at bin 133, then 0
%   - No overlap within a trial (mid ends <= 67; end starts >= 87)
%   - Star uses same timing as other objects
% - 4 panels appended (rows = 133 x 4):
%   - Block 1 or 3: TT1, TT2, TT3, TT4 (A, A, B, B)
%   - Block 2: TT1, TT2, TT5, TT6 (A, A, A, A)
% - TT mapping:
%   Odd:  TT1=C_S (A), TT2=S_D (A), TT3=C_S (B), TT4=S_D (B), TT5=S_C (A), TT6=D_S (A)
%   Even: TT1=S_C (A), TT2=D_S (A), TT3=S_C (B), TT4=D_S (B), TT5=C_S (A), TT6=S_D (A)

% ---------------- Parameters ----------------
nBins        = 133;
scale        = nBins / 133;

firstHalfEnd = round(66 * scale);   % Pos=0 for 1..66; Pos=1 for 67..nBins
midStartBin  = round(20 * scale);   % first 0.25 value for mid
midEndBin    = round(67 * scale);   % mid target (end of mid ramp)
endStartBin  = round(87 * scale);   % first 0.25 value for end (UPDATED)
endEndBin    = nBins;               % end target (end of end ramp)

% Ensure no overlap by construction
midEndBin    = min(midEndBin, firstHalfEnd);          % mid ramp ends in first half
endStartBin  = max(endStartBin, firstHalfEnd + 1);    % end ramp starts in second half

rampStartVal = 0.25; % first ramp value
rampEndVal   = 1.0;  % peak value at target bin

% Binary Pos column
PosBinary = [zeros(firstHalfEnd,1); ones(nBins - firstHalfEnd,1)];

% Helper to build a single nBins-row panel for spec 'X_Y' and context ctx (0/1)
build_panel = @(spec, ctx) build_one_panel(spec, ctx, PosBinary, nBins, ...
                                           midStartBin, midEndBin, ...
                                           endStartBin, endEndBin, ...
                                           rampStartVal, rampEndVal);

% ---------------- Odd parity files ----------------
% Block 1/3: TT1, TT2, TT3, TT4 (A,A,B,B)
T_odd_13 = [
    build_panel('C_S', 0);  % TT1 A
    build_panel('S_D', 0);  % TT2 A
    build_panel('C_S', 1);  % TT3 B
    build_panel('S_D', 1)   % TT4 B
];
writetable(T_odd_13, fullfile(pwd, 'Predictors_Odd_Block13.xlsx'));

% Block 2: TT1, TT2, TT5, TT6 (A,A,A,A) swapped positions
T_odd_2 = [
    build_panel('C_S', 0);  % TT1 A
    build_panel('S_D', 0);  % TT2 A
    build_panel('S_C', 0);  % TT5 A (swap)
    build_panel('D_S', 0)   % TT6 A (swap)
];
writetable(T_odd_2, fullfile(pwd, 'Predictors_Odd_Block2.xlsx'));

% ---------------- Even parity files ----------------
% Block 1/3: TT1, TT2, TT3, TT4 (A,A,B,B)
T_even_13 = [
    build_panel('S_C', 0);  % TT1 A
    build_panel('D_S', 0);  % TT2 A
    build_panel('S_C', 1);  % TT3 B
    build_panel('D_S', 1)   % TT4 B
];
writetable(T_even_13, fullfile(pwd, 'Predictors_Even_Block13.xlsx'));

% Block 2: TT1, TT2, TT5, TT6 (A,A,A,A) swapped positions
T_even_2 = [
    build_panel('S_C', 0);  % TT1 A
    build_panel('D_S', 0);  % TT2 A
    build_panel('C_S', 0);  % TT5 A (swap)
    build_panel('S_D', 0)   % TT6 A (swap)
];
writetable(T_even_2, fullfile(pwd, 'Predictors_Even_Block2.xlsx'));

fprintf('[make_predictors_once] Wrote 4 files to %s\n', pwd);

% ---------------- Local functions (script-local) ----------------
function T = build_one_panel(spec, ctx, PosBinary, nBins, ...
                             midStart, midEnd, endStart, endEnd, ...
                             startVal, endVal)
    % Parse spec like 'C_S'
    parts = strsplit(strrep(spec, ' ', ''), '_');
    if numel(parts) ~= 2
        error('Invalid spec "%s". Expected "X_Y" with X,Y in {C,D,S}.', spec);
    end
    midObj = upper(parts{1});
    endObj = upper(parts{2});

    % Initialize columns
    Pos     = PosBinary;
    Context = ctx * ones(nBins,1);
    Chair   = zeros(nBins,1);
    Drum    = zeros(nBins,1);
    Star    = zeros(nBins,1);

    % Mid ramp: 0 before start; startVal at start; linear to 1 at midEnd; 0 after
    if ~isempty(midObj)
        vMid = ramp_segment(nBins, midStart, midEnd, startVal, endVal);
        switch midObj
            case 'C', Chair = max(Chair, vMid);
            case 'D', Drum  = max(Drum,  vMid);
            case 'S', Star  = max(Star,  vMid);
            otherwise, error('Invalid mid object "%s"', midObj);
        end
    end

    % End ramp: 0 before start; startVal at start; linear to 1 at endEnd; 0 after
    if ~isempty(endObj)
        vEnd = ramp_segment(nBins, endStart, endEnd, startVal, endVal);
        switch endObj
            case 'C', Chair = max(Chair, vEnd);
            case 'D', Drum  = max(Drum,  vEnd);
            case 'S', Star  = max(Star,  vEnd);
            otherwise, error('Invalid end object "%s"', endObj);
        end
    end

    % Clip to [0,1]
    Chair = min(max(Chair,0),1);
    Drum  = min(max(Drum,0),1);
    Star  = min(max(Star,0),1);

    % Compose table
    T = table(Pos, Context, Chair, Drum, Star);
end

function v = ramp_segment(nBins, startIx, endIx, startVal, endVal)
    % Build a ramp with no post-peak plateau:
    % - 0 before startIx
    % - startVal at startIx
    % - linear to endVal at endIx (inclusive)
    % - 0 after endIx
    startIx = min(max(round(startIx), 1), nBins);
    endIx   = min(max(round(endIx),   1), nBins);
    v = zeros(nBins,1);
    if endIx < startIx
        v(startIx) = startVal;
        return;
    end
    n = endIx - startIx;
    vals = linspace(startVal, endVal, n+1);
    v(startIx:endIx) = vals(:);
    if endIx < nBins
        v(endIx+1:end) = 0.0;
    end
end