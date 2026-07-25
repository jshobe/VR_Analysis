function rawDecelTable = build_raw_decel_table(T, cfg)

stateOrder_bar = { ...
    'cue_expected', ...
    'preReward_nonTarget', ...
    'preReward_target_near', ...
    'preReward_target_far'};

siteOrder = cfg.activeReward_deg;

colNames = { ...
    sprintf('site_%g_cueExpected', siteOrder(1)), ...
    sprintf('site_%g_nonTarget',   siteOrder(1)), ...
    sprintf('site_%g_targetNear',  siteOrder(1)), ...
    sprintf('site_%g_targetFar',   siteOrder(1)), ...
    sprintf('site_%g_cueExpected', siteOrder(2)), ...
    sprintf('site_%g_nonTarget',   siteOrder(2)), ...
    sprintf('site_%g_targetNear',  siteOrder(2)), ...
    sprintf('site_%g_targetFar',   siteOrder(2))};

rawCols = cell(1, numel(colNames));
maxLen = 0;
colCounter = 0;

for s = 1:numel(siteOrder)
    for st = 1:numel(stateOrder_bar)
        colCounter = colCounter + 1;

        idx = T.siteDeg == siteOrder(s) & strcmp(T.state, stateOrder_bar{st});
        vals = T.rawDecel(idx);
        vals = vals(~isnan(vals));

        rawCols{colCounter} = vals(:);
        maxLen = max(maxLen, numel(vals));
    end
end

for i = 1:numel(rawCols)
    v = rawCols{i};
    if numel(v) < maxLen
        v(end+1:maxLen,1) = NaN;
    end
    rawCols{i} = v;
end

rawDecelTable = table(rawCols{1}, rawCols{2}, rawCols{3}, rawCols{4}, ...
                      rawCols{5}, rawCols{6}, rawCols{7}, rawCols{8}, ...
                      'VariableNames', colNames);

end