function report = verify_occupancy_threeway(vrFolder, varargin)
% VERIFY_OCCUPANCY_THREEWAY
% Strict three-way comparison of occupancy_4cm between:
%   1) Behavior cache: Derived/behavior_cache.mat
%   2) Artifact:       Derived/Occupancy/occupancy_artifacts.mat
%   3) V2 per-region:  <Region>/Derived_V2/spatial_analysis_v2.mat
%
% No fallbacks, no recompute. If any of the three files are missing,
% the script reports missing paths and skips comparisons for that region.
%
% Usage:
%   verify_occupancy_threeway('Z:\Justin\VR mice\VR29');
%   verify_occupancy_threeway('Z:\...\VR##', 'Regions', {'PPC','VC'}, 'Verbose', true);
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
%       .sizes: behaviorSize, artifactSize, v2Size
%       .allThreePresent
%       .allSameSize
%       .pairwise:
%            .beh_vs_v2: exactMatch, mismatchCount, maxAbsDiff
%            .beh_vs_art: exactMatch, mismatchCount, maxAbsDiff
%            .art_vs_v2: exactMatch, mismatchCount, maxAbsDiff
%       .allThreeEqual
%
% Notes:
% - Exact match treats NaNs as equal (like isequaln).
% - maxAbsDiff ignores NaN positions and is NaN if no finite overlaps.
%
% Author: standalone utility (no fallbacks)

p = inputParser;
addParameter(p, 'Regions', {'PPC','VC'}, @(c)iscell(c)&&all(cellfun(@ischar,c)));
addParameter(p, 'Verbose', true, @islogical);
parse(p, varargin{:});
opt = p.Results;

if nargin < 1 || isempty(vrFolder)
    defaultRoot = 'Z:\Justin\VR mice';
    vrFolder = uigetdir(defaultRoot, 'Select VR animal folder (VR##)');
    if isequal(vrFolder, 0), error('No folder selected.'); end
end
if ~isfolder(vrFolder), error('VR folder not found: %s', vrFolder); end

derivedDir = fullfile(vrFolder, 'Derived');
artifactDir = fullfile(derivedDir, 'Occupancy');

% ---------------- Load behavior cache (no fallback) ----------------
report = struct();
report.vrFolder = vrFolder;

paths = struct();
present = struct();

paths.behavior = fullfile(derivedDir, 'behavior_cache.mat');
present.behavior = exist(paths.behavior, 'file') == 2;

paths.artifact = fullfile(artifactDir, 'occupancy_artifacts.mat');
present.artifact = exist(paths.artifact, 'file') == 2;

report.paths = paths;
report.present = present;

occBehavior = [];
occArtifact = [];
report.behaviorSpeedThresh = NaN;
report.behaviorUseMedianSpeedMask = NaN;
report.artifactSpeedThresh = NaN;
report.artifactUseMedianSpeedMask = NaN;

if present.behavior
    try
        Sb = load(paths.behavior);
        assert(isfield(Sb,'occupancy_4cm'), 'Missing occupancy_4cm in behavior cache');
        occBehavior = Sb.occupancy_4cm;
        if isfield(Sb,'speed_thresh'), report.behaviorSpeedThresh = Sb.speed_thresh; end
        if isfield(Sb,'use_median_speed'), report.behaviorUseMedianSpeedMask = Sb.use_median_speed; end
    catch ME
        error('Failed to load behavior cache: %s', ME.message);
    end
end

if present.artifact
    try
        Sa = load(paths.artifact);
        assert(isfield(Sa,'occupancy_4cm'), 'Missing occupancy_4cm in artifact MAT');
        occArtifact = Sa.occupancy_4cm;
        if isfield(Sa,'SpeedThresh'), report.artifactSpeedThresh = Sa.SpeedThresh; end
        if isfield(Sa,'UseMedianSpeedMask'), report.artifactUseMedianSpeedMask = Sa.UseMedianSpeedMask; end
    catch ME
        error('Failed to load artifact MAT: %s', ME.message);
    end
end

% ---------------- Per-region V2 comparison ----------------
regions = opt.Regions(:)';
regionResults = repmat(makeRegionResultTemplate(), 1, numel(regions));

for i = 1:numel(regions)
    region = regions{i};
    R = makeRegionResultTemplate();
    R.region = region;
    R.paths.v2 = fullfile(vrFolder, region, 'Derived_V2', 'spatial_analysis_v2.mat');
    R.present.v2 = exist(R.paths.v2, 'file') == 2;

    if ~present.behavior || ~present.artifact || ~R.present.v2
        R.allThreePresent = false;
        R.sizes.behaviorSize = sizeOrEmpty(occBehavior);
        R.sizes.artifactSize = sizeOrEmpty(occArtifact);
        R.sizes.v2Size = [NaN NaN];
        if R.present.v2
            try
                S = load(R.paths.v2);
                if isfield(S,'occupancy_4cm')
                    R.sizes.v2Size = size(S.occupancy_4cm);
                end
                if isfield(S,'cfg') && isstruct(S.cfg) && isfield(S.cfg,'SpeedThresh')
                    R.v2SpeedThresh = S.cfg.SpeedThresh;
                end
            catch
                % leave sizes/speed as defaults
            end
        end

        if opt.Verbose
            fprintf('[%s] %s: Missing files; skipping comparisons.\n', timeStr(), region);
            if ~present.behavior, fprintf('   - Missing behavior cache: %s\n', paths.behavior); end
            if ~present.artifact, fprintf('   - Missing artifact MAT:   %s\n', paths.artifact); end
            if ~R.present.v2,     fprintf('   - Missing V2 MAT:         %s\n', R.paths.v2); end
        end
        regionResults(i) = R;
        continue;
    end

    % All three present
    R.allThreePresent = true;

    % Load V2 occupancy and cfg
    try
        Sv2 = load(R.paths.v2);
        assert(isfield(Sv2,'occupancy_4cm'), 'Missing occupancy_4cm in V2 MAT');
        occV2 = Sv2.occupancy_4cm;
        if isfield(Sv2,'cfg') && isstruct(Sv2.cfg) && isfield(Sv2.cfg,'SpeedThresh')
            R.v2SpeedThresh = Sv2.cfg.SpeedThresh;
        end
    catch ME
        % If V2 MAT loads but occupancy missing or error, mark as not present for comparison
        if opt.Verbose
            fprintf('[%s] %s: Failed loading V2 occupancy: %s\n', timeStr(), region, ME.message);
        end
        R.allThreePresent = false;
        regionResults(i) = R;
        continue;
    end

    % Sizes
    R.sizes.behaviorSize = sizeOrEmpty(occBehavior);
    R.sizes.artifactSize = sizeOrEmpty(occArtifact);
    R.sizes.v2Size       = sizeOrEmpty(occV2);
    R.allSameSize = isequal(R.sizes.behaviorSize, R.sizes.artifactSize) && ...
                    isequal(R.sizes.behaviorSize, R.sizes.v2Size);

    % Pairwise comparisons (only if sizes match pairwise)
    R.pairwise.beh_vs_v2 = compare_arrays(occBehavior, occV2);
    R.pairwise.beh_vs_art = compare_arrays(occBehavior, occArtifact);
    R.pairwise.art_vs_v2 = compare_arrays(occArtifact, occV2);

    % All three equal iff all pairwise exact
    R.allThreeEqual = R.pairwise.beh_vs_v2.exactMatch && ...
                      R.pairwise.beh_vs_art.exactMatch && ...
                      R.pairwise.art_vs_v2.exactMatch;

    if opt.Verbose
        fprintf('[%s] %s:\n', timeStr(), region);
        fprintf('   Sizes: behavior=%s | artifact=%s | V2=%s | allSameSize=%d\n', ...
            mat2str(R.sizes.behaviorSize), mat2str(R.sizes.artifactSize), mat2str(R.sizes.v2Size), R.allSameSize);
        fprintf('   SpeedThresh: behavior=%s | artifact=%s | V2=%s\n', ...
            num2str_nan(report.behaviorSpeedThresh), num2str_nan(report.artifactSpeedThresh), num2str_nan(R.v2SpeedThresh));

        p = R.pairwise;
        printPair('behavior vs V2', p.beh_vs_v2);
        printPair('behavior vs artifact', p.beh_vs_art);
        printPair('artifact vs V2', p.art_vs_v2);

        if R.allThreeEqual
            fprintf('   RESULT: ALL THREE MATCH (including NaNs)\n');
        else
            fprintf('   RESULT: MISMATCHES present (see pairwise stats above)\n');
        end
    end

    regionResults(i) = R;
end

report.regions = regionResults;

% Summary
if opt.Verbose
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
        if ~R.allThreePresent
            fprintf('  %s: missing at least one of the three files. V2 present=%d\n', R.region, R.present.v2);
        else
            fprintf('  %s: allThreeEqual=%d | sizes=%s/%s/%s\n', R.region, R.allThreeEqual, ...
                mat2str(R.sizes.behaviorSize), mat2str(R.sizes.artifactSize), mat2str(R.sizes.v2Size));
        end
    end
end
end

% --------------- Helpers ---------------
function R = makeRegionResultTemplate()
R = struct();
R.region = '';
R.paths = struct('v2','');
R.present = struct('v2', false);
R.v2SpeedThresh = NaN;
R.sizes = struct('behaviorSize', [NaN NaN], 'artifactSize', [NaN NaN], 'v2Size', [NaN NaN]);
R.allThreePresent = false;
R.allSameSize = false;
pairT = struct('exactMatch', false, 'mismatchCount', NaN, 'maxAbsDiff', NaN);
R.pairwise = struct('beh_vs_v2', pairT, 'beh_vs_art', pairT, 'art_vs_v2', pairT);
R.allThreeEqual = false;
end

function s = sizeOrEmpty(x)
if isempty(x), s = [0 0];
else, s = size(x);
end
end

function out = compare_arrays(A, B)
% Treat NaNs as equal; compute mismatch count and max abs diff over finite overlaps.
out = struct('exactMatch', false, 'mismatchCount', NaN, 'maxAbsDiff', NaN);
if isempty(A) || isempty(B) || ~isequal(size(A), size(B))
    out.exactMatch = false;
    return;
end
eqMask = (A == B) | (isnan(A) & isnan(B));
out.exactMatch = all(eqMask(:));
out.mismatchCount = nnz(~eqMask);

finiteMask = isfinite(A) & isfinite(B);
if any(finiteMask(:))
    diffs = abs(A(finiteMask) - B(finiteMask));
    out.maxAbsDiff = max(diffs(:));
else
    out.maxAbsDiff = NaN;
end
end

function printPair(label, P)
fprintf('   %-20s -> exact=%d, mismatches=%s, max|Δ|=%s\n', ...
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