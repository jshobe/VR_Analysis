function [PerUnit, PerTrial] = extract_spikes_per_trial_by_block(v2mat, varargin)
% EXTRACT_SPIKES_PER_TRIAL_BY_BLOCK
% Build tables of spike counts per trial grouped by block from V2 outputs.
%
% Inputs
%   v2mat   : path to region's Derived_V2/spatial_analysis_v2.mat
%
% Name-Value Options
%   'Variant'          : 'both' | 'fast' | 'unfiltered'   (default 'both')
%   'WriteCSV'         : true|false                        (default false)
%   'CSVPrefix'        : file name prefix for CSVs         (default '')
%   'AddTrialType'     : true|false (adds TT column)       (default true)
%   'AddSceneLabels'   : true|false (needs get_scene_lookup & FileNum/IsEvenFile) (default false)
%   'FileNum'          : numeric (for get_scene_lookup)    (default NaN)
%   'IsEvenFile'       : logical (for get_scene_lookup)    (default false)
%
% Outputs (tables)
%   PerUnit  : [Block, Trial, UnitID, Variant, Count, (optional TT, Label)]
%   PerTrial : [Block, Trial, Variant, Count, (optional TT, Label)]
%
% Example
%   [PU, PT] = extract_spikes_per_trial_by_block( ...
%       fullfile(regionFolder,'Derived_V2','spatial_analysis_v2.mat'), ...
%       'Variant','both','WriteCSV',true,'CSVPrefix','VR23_PPC_', ...
%       'AddTrialType',true,'AddSceneLabels',true,'FileNum',18,'IsEvenFile',true);

% ---------- Parse options ----------
p = inputParser;
addParameter(p, 'Variant', 'both', @(s)ischar(s) || isstring(s));
addParameter(p, 'WriteCSV', false, @islogical);
addParameter(p, 'CSVPrefix', '', @(s)ischar(s) || isstring(s));
addParameter(p, 'AddTrialType', true, @islogical);
addParameter(p, 'AddSceneLabels', false, @islogical);
addParameter(p, 'FileNum', NaN, @(x)isnumeric(x)&&isscalar(x));
addParameter(p, 'IsEvenFile', false, @islogical);
parse(p, varargin{:});
opt = p.Results;
variant = lower(string(opt.Variant));

% ---------- Load required artifacts ----------
S = load(v2mat, 'Blocks', 'raster_data', 'unit_summary', 'cluster_id_good', 'halls');
Blocks      = S.Blocks;
raster_data = S.raster_data;
unitIDs     = S.cluster_id_good(:);
halls       = [];
if isfield(S,'halls'), halls = S.halls(:); end
[nUnits, nTrials] = size(raster_data);

% ---------- Builders ----------
wantFast = variant=="both" || variant=="fast";
wantUnf  = variant=="both" || variant=="unfiltered";

PerUnitParts  = cell(0,1);
PerTrialParts = cell(0,1);

if wantFast
    [PUf, PTf] = build_fast_tables(Blocks, raster_data, unitIDs);
    PUf.Variant = repmat("fast_only", height(PUf), 1);
    PTf.Variant = repmat("fast_only", height(PTf), 1);
    PerUnitParts{end+1}  = PUf; %#ok<*AGROW>
    PerTrialParts{end+1} = PTf;
end

if wantUnf
    trialCountsUnf = S.unit_summary.trial_counts; % [nUnits x nTrials]
    [PUu, PTu] = build_unfiltered_tables(Blocks, trialCountsUnf, unitIDs);
    PUu.Variant = repmat("unfiltered", height(PUu), 1);
    PTu.Variant = repmat("unfiltered", height(PTu), 1);
    PerUnitParts{end+1}  = PUu;
    PerTrialParts{end+1} = PTu;
end

% Concatenate
PerUnit  = vertcat(PerUnitParts{:});
PerTrial = vertcat(PerTrialParts{:});

% ---------- Optional columns: TrialType (TT) and Scene Labels ----------
if opt.AddTrialType && ~isempty(halls)
    % Map trial index -> TT
    TTmap = arrayfun(@(tr) (tr>=1 && tr<=numel(halls)) * halls(tr) + ...
                            (~(tr>=1 && tr<=numel(halls))) * NaN, ...
                     PerUnit.Trial);
    PerUnit.TT  = TTmap(:);
    % For PerTrial, all rows with same Trial share TT
    PerTrial.TT = arrayfun(@(tr) (tr>=1 && tr<=numel(halls)) * halls(tr) + ...
                                (~(tr>=1 && tr<=numel(halls))) * NaN, ...
                           PerTrial.Trial);
end

if opt.AddSceneLabels
    PerUnit.Label  = repmat("", height(PerUnit), 1);
    PerTrial.Label = repmat("", height(PerTrial), 1);
    hasLookup = (exist('get_scene_lookup','file')==2);
    for b = 1:numel(Blocks)
        % Get labels for this block (if possible)
        lab = containers.Map('KeyType','double','ValueType','char');
        if hasLookup
            try
                lab = get_scene_lookup(opt.FileNum, opt.IsEvenFile, b);
            catch
                % fall through to default labels below
            end
        end
        if isempty(lab) || lab.Count==0
            lab(1)='TT1'; lab(2)='TT2';
            if mod(b,2)==1, lab(3)='TT3'; lab(4)='TT4'; else, lab(5)='TT5'; lab(6)='TT6'; end
            lab(7)='TT7';
        end
        % Apply to rows of this block (using TT if present)
        if ismember('TT', PerUnit.Properties.VariableNames)
            ixU = find(PerUnit.Block==b & isfinite(PerUnit.TT));
            for k = ixU'
                tt = PerUnit.TT(k);
                if isKey(lab, tt), PerUnit.Label(k) = string(lab(tt)); end
            end
        end
        if ismember('TT', PerTrial.Properties.VariableNames)
            ixT = find(PerTrial.Block==b & isfinite(PerTrial.TT));
            for k = ixT'
                tt = PerTrial.TT(k);
                if isKey(lab, tt), PerTrial.Label(k) = string(lab(tt)); end
            end
        end
    end
end

% ---------- Optional CSV write ----------
if opt.WriteCSV
    outDir = fileparts(v2mat);
    if isempty(outDir), outDir = pwd; end
    pref = char(opt.CSVPrefix);
    writetable(PerUnit,  fullfile(outDir, [pref 'spikes_per_unit_per_trial_by_block.csv']));
    writetable(PerTrial, fullfile(outDir, [pref 'spikes_per_trial_by_block.csv']));
end
end

% ================= Helpers =================
function [PU, PT] = build_fast_tables(Blocks, raster_data, unitIDs)
[nUnits, ~] = size(raster_data);
rows = {};
for b = 1:numel(Blocks)
    trList = Blocks{b}(:)';
    data_b = zeros(numel(trList)*nUnits, 4); % Block, Trial, UnitID(idx), Count
    k = 1;
    for tr = trList
        for u = 1:nUnits
            C = raster_data{u, tr};
            c = 0;
            if ~isempty(C) && isfield(C,'positions') && ~isempty(C.positions)
                c = numel(C.positions);
            end
            data_b(k,:) = [b, tr, u, c]; k = k + 1;
        end
    end
    rows{end+1} = data_b(1:k-1, :);
end
A = vertcat(rows{:});
PU = table(A(:,1), A(:,2), unitIDs(A(:,3)), A(:,4), ...
    'VariableNames', {'Block','Trial','UnitID','Count'});
PT = groupsummary(PU, {'Block','Trial'}, 'sum', 'Count');
PT.Properties.VariableNames(end) = {'Count'};
end

function [PU, PT] = build_unfiltered_tables(Blocks, trialCountsUnf, unitIDs)
[nUnits, nTrials] = size(trialCountsUnf); %#ok<ASGLU>
rows = {};
for b = 1:numel(Blocks)
    trList = Blocks{b}(:)';
    [TR, U] = ndgrid(trList, 1:numel(unitIDs));
    idx = U + (TR-1)*numel(unitIDs);       % linear indices (column-major)
    counts = trialCountsUnf(idx);
    rows{end+1} = [ ...
        b*ones(numel(counts),1), ...       % Block
        TR(:), ...                         % Trial
        unitIDs(U(:)), ...                 % UnitID
        counts(:)];                        % Count
end
B = vertcat(rows{:});
PU = table(B(:,1), B(:,2), B(:,3), B(:,4), ...
    'VariableNames', {'Block','Trial','UnitID','Count'});
PT = groupsummary(PU, {'Block','Trial'}, 'sum', 'Count');
PT.Properties.VariableNames(end) = {'Count'};
end
