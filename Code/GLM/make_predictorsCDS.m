% make_predictors_objects_only.m
% One-time script to build and save four predictor files with ONLY object predictors.
% Files:
%   - Predictors_Odd_Block13.xlsx
%   - Predictors_Odd_Block2.xlsx
%   - Predictors_Even_Block13.xlsx
%   - Predictors_Even_Block2.xlsx
%
% Spec:
% - Scene length: nBins = 133 (1 bin = 4 cm)
% - Objects: Chair(C), Drum(D), Star(S)
%   - Mid-scene: start at bin 20 with value 0, linearly ramp to 1 at bin 67, then 0
%   - End-scene: start at bin 87 with value 0, linearly ramp to 1 at bin 133, then 0
% - 4 panels appended (rows = 133 x 4):
%   - Block 1 or 3: TT1, TT2, TT3, TT4
%   - Block 2: TT1, TT2, TT5, TT6
% - TT mapping:
%   Odd:  TT1=C_S, TT2=S_D, TT3=C_S, TT4=S_D, TT5=S_C, TT6=D_S
%   Even: TT1=S_C, TT2=D_S, TT3=S_C, TT4=D_S, TT5=C_S, TT6=S_D

% ---------------- Parameters ----------------
nBins        = 133;
scale        = nBins / 133;

firstHalfEnd = round(66 * scale);
midStartBin  = round(20 * scale);   % first 0 value for mid
midEndBin    = round(67 * scale);   % mid target (end of mid ramp)
endStartBin  = round(87 * scale);   % first 0 value for end
endEndBin    = nBins;               % end target (end of end ramp)

% Ensure no overlap by construction
midEndBin    = min(midEndBin, firstHalfEnd);          % mid ramp ends in first half
endStartBin  = max(endStartBin, firstHalfEnd + 1);    % end ramp starts in second half

rampStartVal = 0;    % first ramp value
rampEndVal   = 1.0;  % peak value at target bin

% Helper to build a single nBins-row panel for spec 'X_Y'
build_panel = @(spec) build_one_panel(spec, nBins, ...
                                      midStartBin, midEndBin, ...
                                      endStartBin, endEndBin, ...
                                      rampStartVal, rampEndVal);

% ---------------- Odd parity files ----------------
% Block 1/3: TT1, TT2, TT3, TT4
T_odd_13 = [
    build_panel('C_S');  % TT1
    build_panel('S_D');  % TT2
    build_panel('C_S');  % TT3
    build_panel('S_D')   % TT4
];
writetable(T_odd_13, fullfile(pwd, 'CDS_Odd_Block13.xlsx'));

% Block 2: TT1, TT2, TT5, TT6
T_odd_2 = [
    build_panel('C_S');  % TT1
    build_panel('S_D');  % TT2
    build_panel('S_C');  % TT5
    build_panel('D_S')   % TT6
];
writetable(T_odd_2, fullfile(pwd, 'CDS_Odd_Block2.xlsx'));

% ---------------- Even parity files ----------------
% Block 1/3: TT1, TT2, TT3, TT4
T_even_13 = [
    build_panel('S_C');  % TT1
    build_panel('D_S');  % TT2
    build_panel('S_C');  % TT3
    build_panel('D_S')   % TT4
];
writetable(T_even_13, fullfile(pwd, 'CDS_Even_Block13.xlsx'));

% Block 2: TT1, TT2, TT5, TT6
T_even_2 = [
    build_panel('S_C');  % TT1
    build_panel('D_S');  % TT2
    build_panel('C_S');  % TT5
    build_panel('S_D')   % TT6
];
writetable(T_even_2, fullfile(pwd, 'CDS_Even_Block2.xlsx'));

fprintf('[make_predictors_objects_only] Wrote 4 files to %s\n', pwd);

% ---------------- Local functions (script-local) ----------------
function T = build_one_panel(spec, nBins, ...
                             midStart, midEnd, endStart, endEnd, ...
                             startVal, endVal)
    % Parse spec like 'C_S'
    parts = strsplit(strrep(spec, ' ', ''), '_');
    if numel(parts) ~= 2
        error('Invalid spec "%s". Expected "X_Y" with X,Y in {C,D,S}.', spec);
    end
    midObj = upper(parts{1});
    endObj = upper(parts{2});

    % Initialize object columns only
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

    % Compose table with only object columns
    T = table(Chair, Drum, Star);
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