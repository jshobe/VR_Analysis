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
% - Pos: 6 binary square pulse position predictors evenly tiling the environment (0 or 1)
% - Context: 0=A, 1=B
%   - Blocks 1+3: Context starts with 1 (B,B,A,A)
%   - Block 2: Context constant at 0 (A,A,A,A)
% - Objects: Chair(C), Drum(D), Star(S)
%   - Mid-scene: start at bin 20 with value 0, linearly ramp to 1 at bin 67, then 0
%   - End-scene: start at bin 87 with value 0, linearly ramp to 1 at bin 133, then 0
%   - No overlap within a trial (mid ends <= 67; end starts >= 87)
%   - Star uses same timing as other objects
% - 4 panels appended (rows = 133 x 4):
%   - Block 1 or 3: TT1, TT2, TT3, TT4 (B, B, A, A)
%   - Block 2: TT1, TT2, TT5, TT6 (A, A, A, A)
% - TT mapping:
%   Odd:  TT1=C_S (B), TT2=S_D (B), TT3=C_S (A), TT4=S_D (A), TT5=S_C (A), TT6=D_S (A)
%   Even: TT1=S_C (B), TT2=D_S (B), TT3=S_C (A), TT4=D_S (A), TT5=C_S (A), TT6=S_D (A)

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

% Create 6 binary square pulse position predictors
nPositions = 6;
PosPredictor = create_binary_position_predictors(nBins, nPositions);

% Helper to build a single nBins-row panel for spec 'X_Y' and context ctx (0/1)
build_panel = @(spec, ctx) build_one_panel(spec, ctx, PosPredictor, nBins, ...
                                           midStartBin, midEndBin, ...
                                           endStartBin, endEndBin, ...
                                           rampStartVal, rampEndVal);

% ---------------- Odd parity files ----------------
% Block 1/3: TT1, TT2, TT3, TT4 (B,B,A,A) - starts with context B (1)
T_odd_13 = [
    build_panel('C_S', 1);  % TT1 B
    build_panel('S_D', 1);  % TT2 B
    build_panel('C_S', 0);  % TT3 A
    build_panel('S_D', 0)   % TT4 A
];
writetable(T_odd_13, fullfile(pwd, 'Predictors_Odd_Block13.xlsx'));

% Block 2: TT1, TT2, TT5, TT6 (A,A,A,A) - all context A (0), swapped positions
T_odd_2 = [
    build_panel('C_S', 0);  % TT1 A
    build_panel('S_D', 0);  % TT2 A
    build_panel('S_C', 0);  % TT5 A (swap)
    build_panel('D_S', 0)   % TT6 A (swap)
];
writetable(T_odd_2, fullfile(pwd, 'Predictors_Odd_Block2.xlsx'));

% ---------------- Even parity files ----------------
% Block 1/3: TT1, TT2, TT3, TT4 (B,B,A,A) - starts with context B (1)
T_even_13 = [
    build_panel('S_C', 1);  % TT1 B
    build_panel('D_S', 1);  % TT2 B
    build_panel('S_C', 0);  % TT3 A
    build_panel('D_S', 0)   % TT4 A
];
writetable(T_even_13, fullfile(pwd, 'Predictors_Even_Block13.xlsx'));

% Block 2: TT1, TT2, TT5, TT6 (A,A,A,A) - all context A (0), swapped positions
T_even_2 = [
    build_panel('S_C', 0);  % TT1 A
    build_panel('D_S', 0);  % TT2 A
    build_panel('C_S', 0);  % TT5 A (swap)
    build_panel('S_D', 0)   % TT6 A (swap)
];
writetable(T_even_2, fullfile(pwd, 'Predictors_Even_Block2.xlsx'));

fprintf('[make_predictors_once] Wrote 4 files to %s\n', pwd);

% ---------------- Local functions (script-local) ----------------
function basisMat = create_binary_position_predictors(nBins, nPositions)
    % Create binary square pulse position predictors that evenly tile the environment
    % Each predictor is 1 in its segment, 0 elsewhere
    % - Perfect orthogonality (correlation = 0)
    % - Even tiling with no gaps or overlap
    % - Simple interpretation: each predictor = one spatial region
    
    % Divide environment into equal segments
    segmentWidth = nBins / nPositions;
    
    % Create basis matrix: nBins x nPositions
    basisMat = zeros(nBins, nPositions);
    
    for i = 1:nPositions
        % Define segment boundaries
        segStart = round((i - 1) * segmentWidth + 1);
        segEnd = round(i * segmentWidth);
        
        % Binary pulse: 1 in segment, 0 elsewhere
        basisMat(segStart:segEnd, i) = 1;
        
        fprintf('  Pos%d: bins %d-%d (width=%d bins)\n', ...
                i, segStart, segEnd, segEnd-segStart+1);
    end
    
    % Verify coverage and correlation (diagnostic)
    coverage = sum(basisMat, 2);
    fprintf('\nPosition coverage - Min: %.3f, Max: %.3f, Mean: %.3f\n', ...
            min(coverage), max(coverage), mean(coverage));
    
    if min(coverage) ~= 1 || max(coverage) ~= 1
        warning('Coverage is not exactly 1 everywhere - check bin assignments');
    end
    
    corrMat = corrcoef(basisMat);
    maxOffDiagCorr = max(abs(corrMat(~eye(size(corrMat)))));
    fprintf('Max correlation between position predictors: %.4f\n\n', maxOffDiagCorr);
end

function T = build_one_panel(spec, ctx, PosPredictor, nBins, ...
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
    % Position: 6 binary columns (Pos1, Pos2, ..., Pos6)
    Pos1    = PosPredictor(:, 1);
    Pos2    = PosPredictor(:, 2);
    Pos3    = PosPredictor(:, 3);
    Pos4    = PosPredictor(:, 4);
    Pos5    = PosPredictor(:, 5);
    Pos6    = PosPredictor(:, 6);
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

    % Compose table with 6 position columns
    T = table(Pos1, Pos2, Pos3, Pos4, Pos5, Pos6, Context, Chair, Drum, Star);
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