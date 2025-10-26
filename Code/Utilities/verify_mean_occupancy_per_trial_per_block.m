function report = verify_mean_occupancy_per_trial_per_block_gui()
% VERIFY_MEAN_OCCUPANCY_PER_TRIAL_PER_BLOCK_GUI
% GUI-based, strict three-way comparison of per-trial mean occupancy (seconds/bin averaged across bins)
% for each block, between:
%   1) Behavior cache: Derived/behavior_cache.mat (occupancy_4cm)
%   2) Artifact:       Derived/Occupancy/occupancy_artifacts.mat (occupancy_4cm)
%   3) V2 per-region:  <Region>/Derived_V2/spatial_analysis_v2.mat (occupancy_4cm, Blocks)
%
% No fallbacks and no recompute. If any file is missing, it reports missing paths and skips comparisons.
% Blocks are taken from the V2 MAT.
%
% Usage:
%   report = verify_mean_occupancy_per_trial_per_block_gui();
%
% Output (report struct):
%   .vrFolder
%   .paths.behavior, .paths.artifact
%   .present.behavior, .present.artifact
%   .behaviorSpeedThresh, .behaviorUseMedianSpeedMask
%   .artifactSpeedThresh, .artifactUseMedianSpeedMask
%   .regions(i):
%       .region
%       .paths.v2
%       .present.v2
%       .v2SpeedThresh
%       .allThreePresent
%       .sizes: behaviorSize, artifactSize, v2Size
%       .blocks(j):
%           .blockIndex
%           .trialIndices
%           .allSameLength
%           .pairwise:
%               .beh_vs_v2: exactMatch, mismatchCount, maxAbsDiff
%               .beh_vs_art: exactMatch, mismatchCount, maxAbsDiff
%               .art_vs_v2: exactMatch, mismatchCount, maxAbsDiff
%           .allThreeEqual
%
% Notes:
% - Exact match treats NaNs as equal (like isequaln).
% - maxAbsDiff ignores NaN positions and is NaN if no finite overlaps.
% - V2 MAT must contain 'occupancy_4cm' and 'Blocks'. These are saved by run_spatial_analysis_v2.
%   See MakeUnitData.txt (e.g., Pages 5, 20) showing 'occupancy_4cm' and 'Blocks' saved with V2 outputs.

% ---------------- GUI: Select VR## folder ----------------
defaultRoot = 'Z:\Justin\VR mice';
vrFolder = uigetdir(defaultRoot, 'Select VR animal folder (VR##)');
if isequal(vrFolder, 0)
    error('No folder selected.');
end
if ~isfolder(vrFolder), error('VR folder not found: %s', vrFolder); end

% ---------------- Discover regions with V2 outputs ----------------
regionNames = list_regions_with_v2(vrFolder);
if isempty(regionNames)
    uiwait(errordlg('No regions with Derived_V2/spatial_analysis_v2.mat found under the selected VR folder.', ...
        'No V2 outputs', 'modal'));
end

% Ask user to select regions from those found (if any)
if ~isempty(regionNames)
    [selIdx, ok] = listdlg( ...
        'ListString', regionNames, ...
        'SelectionMode', 'multiple', ...
        'Name', 'Select Regions', ...
        'PromptString', 'Select regions to compare:', ...
        'ListSize', [300 200]);
    if ~ok
        error('No regions selected.');
    end
    regionsSelected = regionNames(selIdx);
else
    regionsSelected = {};
end

% ---------------- Load behavior cache and artifact (strict) ----------------
derivedDir  = fullfile(vrFolder, 'Derived');
artifactDir = fullfile(derivedDir, 'Occupancy');

report = struct();
report.vrFolder = vrFolder;

paths = struct();
present = struct();

paths.behavior = fullfile(derivedDir, 'behavior_cache.mat');
present.behavior = exist(paths.behavior, 'file') == 2;

paths.artifact = fullfile(artifactDir, 'occupancy_artifacts.mat');
present.artifact = exist(paths.artifact, 'file') == 2;

report.paths   = paths;
report.present = present;

occBehavior = [];
occArtifact = [];
report.behaviorSpeedThresh        = NaN;
report.behaviorUseMedianSpeedMask = NaN;
report.artifactSpeedThresh        = NaN;
report.artifactUseMedianSpeedMask = NaN;

% Behavior cache
if present.behavior
    Sb = load(paths.behavior);
    assert(isfield(Sb,'occupancy_4cm'), 'Missing occupancy_4cm in behavior cache');
    occBehavior = Sb.occupancy_4cm;
    if isfield(Sb,'speed_thresh'),      report.behaviorSpeedThresh        = Sb.speed_thresh; end
    if isfield(Sb,'use_median_speed'),  report.behaviorUseMedianSpeedMask = Sb.use_median_speed; end
else
    fprintf('[%s] Missing behavior cache: %s\n', timeStr(), paths.behavior);
end

% Artifact
if present.artifact
    Sa = load(paths.artifact);
    assert(isfield(Sa,'occupancy_4cm'), 'Missing occupancy_4cm in artifact MAT');
    occArtifact = Sa.occupancy_4cm;
    if isfield(Sa,'SpeedThresh'),        report.artifactSpeedThresh        = Sa.SpeedThresh; end
    if isfield(Sa,'UseMedianSpeedMask'), report.artifactUseMedianSpeedMask = Sa.UseMedianSpeedMask; end
else
    fprintf('[%s] Missing artifact MAT:   %s\n', timeStr(), paths.artifact);
end

% ---------------- Per-region V2 comparisons (strict) ----------------
regionResults = repmat(makeRegionTemplate(), 1, numel(regionsSelected));
for i = 1:numel(regionsSelected)
    region = regionsSelected{i};
    R = makeRegionTemplate();
    R.region      = region;
    R.paths.v2    = fullfile(vrFolder, region, 'Derived_V2', 'spatial_analysis_v2.mat');
    R.present.v2  = exist(R.paths.v2, 'file') == 2;

    if ~present.behavior || ~present.artifact || ~R.present.v2
        R.allThreePresent = false;
        % Sizes (if available)
        R.sizes.behaviorSize = sizeOrEmpty(occBehavior);
        R.sizes.artifactSize = sizeOrEmpty(occArtifact);
        R.sizes.v2Size       = [NaN NaN];

        if R.present.v2
            Sv2 = safeLoad(R.paths.v2);
            if isfield(Sv2,'occupancy_4cm'), R.sizes.v2Size = size(Sv2.occupancy_4cm); end
            if hasSpeedThresh(Sv2),          R.v2SpeedThresh = Sv2.cfg.SpeedThresh;     end
        end

        fprintf('[%s] %s: Missing at least one file; skipping comparisons.\n', timeStr(), region);
        if ~present.behavior, fprintf('   - Missing behavior cache: %s\n', paths.behavior); end
        if ~present.artifact, fprintf('   - Missing artifact MAT:   %s\n', paths.artifact); end
        if ~R.present.v2,     fprintf('   - Missing V2 MAT:         %s\n', R.paths.v2); end

        regionResults(i) = R;
        continue;
    end

    % All three present: load V2 occupancy and Blocks
    Sv2 = safeLoad(R.paths.v2);
    assert(isfield(Sv2,'occupancy_4cm'), 'Missing occupancy_4cm in V2 MAT');
    assert(isfield(Sv2,'Blocks'),        'Missing Blocks in V2 MAT');
    occV2  = Sv2.occupancy_4cm;
    Blocks = Sv2.Blocks;
    if hasSpeedThresh(Sv2), R.v2SpeedThresh = Sv2.cfg.SpeedThresh; end

    % Sizes
    R.allThreePresent     = true;
    R.sizes.behaviorSize  = sizeOrEmpty(occBehavior);
    R.sizes.artifactSize  = sizeOrEmpty(occArtifact);
    R.sizes.v2Size        = sizeOrEmpty(occV2);

    % Trial count match check
    sameTrials = (size(occBehavior,1) == size(occArtifact,1)) && ...
                 (size(occBehavior,1) == size(occV2,1));
    if ~sameTrials
        fprintf('[%s] %s: Trial count mismatch. beh=%d, art=%d, v2=%d\n', ...
            timeStr(), region, size(occBehavior,1), size(occArtifact,1), size(occV2,1));
        regionResults(i) = R;
        continue;
    end

    % Clip blocks to valid trials
    nTrials = size(occV2,1);
    Blocks  = clipBlocks(Blocks, nTrials);
    R.blocks = repmat(makeBlockTemplate(), 1, numel(Blocks));

    for b = 1:numel(Blocks)
        trials_b = Blocks{b}(:);
        B = makeBlockTemplate();
        B.blockIndex   = b;
        B.trialIndices = trials_b(:)';

        if isempty(trials_b)
            fprintf('[%s] %s Block %d: empty block; skipping.\n', timeStr(), region, b);
            R.blocks(b) = B;
            continue;
        end

        % Compute per-trial mean occupancy across bins (ignore NaNs)
        beh_vec = mean(occBehavior(trials_b, :), 2, 'omitnan');
        art_vec = mean(occArtifact(trials_b, :), 2, 'omitnan');
        v2_vec  = mean(occV2(trials_b, :), 2, 'omitnan');

        % Compare pairwise
        B.allSameLength = (numel(beh_vec) == numel(art_vec)) && (numel(beh_vec) == numel(v2_vec));
        B.pairwise.beh_vs_v2  = compare_vectors(beh_vec, v2_vec);
        B.pairwise.beh_vs_art = compare_vectors(beh_vec, art_vec);
        B.pairwise.art_vs_v2  = compare_vectors(art_vec, v2_vec);

        % All three equal if all pairwise exact
        B.allThreeEqual = B.pairwise.beh_vs_v2.exactMatch && ...
                          B.pairwise.beh_vs_art.exactMatch && ...
                          B.pairwise.art_vs_v2.exactMatch;

        % Print
        fprintf('[%s] %s Block %d:\n', timeStr(), region, b);
        fprintf('   Trials: %s\n', mat2str(B.trialIndices));
        fprintf('   vec lengths: beh=%d | art=%d | v2=%d | allSameLength=%d\n', ...
            numel(beh_vec), numel(art_vec), numel(v2_vec), B.allSameLength);
        printPair('behavior vs V2',       B.pairwise.beh_vs_v2);
        printPair('behavior vs artifact', B.pairwise.beh_vs_art);
        printPair('artifact vs V2',       B.pairwise.art_vs_v2);
        if B.allThreeEqual
            fprintf('   RESULT: ALL THREE MATCH\n');
        else
            fprintf('   RESULT: MISMATCHES present\n');
        end

        R.blocks(b) = B;
    end

    regionResults(i) = R;
end

report.regions = regionResults;

% ---------------- Summary ----------------
fprintf('\nSummary for %s\n', vrFolder);
fprintf('Behavior cache: %s [%s]\n', paths.behavior, presentStr(present.behavior));
fprintf('Artifact MAT:   %s [%s]\n', paths.artifact,  presentStr(present.artifact));
if isfinite(report.behaviorSpeedThresh)
    fprintf('  behavior.speed_thresh = %g\n', report.behaviorSpeedThresh);
end
if isfinite(report.behaviorUseMedianSpeedMask)
    fprintf('  behavior.use_median_speed = %d\n', report.behaviorUseMedianSpeedMask);
end
if isfinite(report.artifactSpeedThresh)
    fprintf('  artifact.SpeedThresh = %g\n', report.artifactSpeedThresh);
end
if isfinite(report.artifactUseMedianSpeedMask)
    fprintf('  artifact.UseMedianSpeedMask = %d\n', report.artifactUseMedianSpeedMask);
end
for i = 1:numel(regionResults)
    R = regionResults(i);
    if isempty(R.region), continue; end
    fprintf('  %s: V2 MAT [%s], allThreePresent=%d\n', R.region, presentStr(R.present.v2), R.allThreePresent);
    if R.allThreePresent
        for b = 1:numel(R.blocks)
            B = R.blocks(b);
            fprintf('    Block %d: allThreeEqual=%d\n', B.blockIndex, B.allThreeEqual);
        end
    else
        fprintf('    Missing at least one of the three files; comparisons skipped.\n');
    end
end
end

% ==================== Local helpers ====================
function names = list_regions_with_v2(vrFolder)
% Return subfolder names that contain Derived_V2/spatial_analysis_v2.mat
S = dir(vrFolder);
names = {};
for i = 1:numel(S)
    if ~S(i).isdir, continue; end
    nm = S(i).name;
    if nm(1) == '.', continue; end
    matPath = fullfile(vrFolder, nm, 'Derived_V2', 'spatial_analysis_v2.mat');
    if exist(matPath, 'file') == 2
        names{end+1} = nm; %#ok<AGROW>
    end
end
end

function R = makeRegionTemplate()
R = struct();
R.region = '';
R.paths = struct('v2','');
R.present = struct('v2', false);
R.v2SpeedThresh = NaN;
R.sizes = struct('behaviorSize', [NaN NaN], 'artifactSize', [NaN NaN], 'v2Size', [NaN NaN]);
R.allThreePresent = false;
R.blocks = struct([]);  % array of block templates
end

function B = makeBlockTemplate()
B = struct();
B.blockIndex = NaN;
B.trialIndices = [];
B.allSameLength = false;
pairT = struct('exactMatch', false, 'mismatchCount', NaN, 'maxAbsDiff', NaN);
B.pairwise = struct('beh_vs_v2', pairT, 'beh_vs_art', pairT, 'art_vs_v2', pairT);
B.allThreeEqual = false;
end

function S = safeLoad(p)
S = load(p);
end

function tf = hasSpeedThresh(S)
tf = isfield(S,'cfg') && isstruct(S.cfg) && isfield(S.cfg,'SpeedThresh');
end

function s = sizeOrEmpty(x)
if isempty(x), s = [0 0]; else, s = size(x); end
end

function Blocks = clipBlocks(Blocks, nTrials)
% Clip Block trial indices to valid range (consistent with V2 saving)
valid_blocks = false(1, numel(Blocks));
for b = 1:numel(Blocks)
    bb = Blocks{b}(:);
    bb = bb(isfinite(bb) & bb >= 1 & bb <= nTrials);
    Blocks{b} = unique(bb, 'stable');
    valid_blocks(b) = ~isempty(Blocks{b});
end
Blocks = Blocks(valid_blocks);
end

function out = compare_vectors(a, b)
% Treat NaNs as equal. Compute mismatch count and max abs diff over finite overlaps.
out = struct('exactMatch', false, 'mismatchCount', NaN, 'maxAbsDiff', NaN);
if isempty(a) || isempty(b) || ~isequal(size(a), size(b))
    out.exactMatch = false;
    return;
end
eqMask = (a == b) | (isnan(a) & isnan(b));
out.exactMatch    = all(eqMask(:));
out.mismatchCount = nnz(~eqMask);

finiteMask = isfinite(a) & isfinite(b);
if any(finiteMask(:))
    diffs = abs(a(finiteMask) - b(finiteMask));
    out.maxAbsDiff = max(diffs(:));
else
    out.maxAbsDiff = NaN;
end
end

function printPair(label, P)
fprintf('   %-24s -> exact=%d, mismatches=%s, max|Δ|=%s\n', ...
    label, P.exactMatch, num2str_nan(P.mismatchCount), num2str_nan(P.maxAbsDiff));
end

function s = num2str_nan(x)
if isempty(x) || ~isfinite(x), s = 'n/a'; else, s = sprintf('%g', x); end
end

function s = presentStr(tf)
if tf, s = 'present'; else, s = 'missing'; end
end

function s = timeStr()
s = datestr(now, 'HH:MM:SS');
end