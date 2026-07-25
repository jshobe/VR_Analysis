function [T, rawDecelTable, sessionTitle] = finalize_event_table( ...
    allRows, allProfileSpeed, allProfileSiteDeg, allProfileState, allProfileScenario, cfg)

T = cell2table(allRows, 'VariableNames', cfg.varNames);

numericVars = {'intervalNumber','eventNumber','siteDeg','cueIdentityVal','cueOnsetIdx', ...
               'cueOffsetIdx','cueTrackPosDeg','cueLocationDeg','targetRewardDeg', ...
               'rewardIdx','rewardSiteDeg','crossingIdx','approachSpeed', ...
               'decelNearSpeed','decelControlSpeed','rawDecel'};

for k = 1:numel(numericVars)
    v = T.(numericVars{k});
    if iscell(v)
        T.(numericVars{k}) = cell2mat(v);
    end
end

rawDecelTable = build_raw_decel_table(T, cfg);

sessionList = unique(T.sessionName, 'stable');

if numel(sessionList) == 1
    sessionTitle = sessionList{1};
else
    sessionTitle = sprintf('%s + %d more sessions', sessionList{1}, numel(sessionList)-1);
end

if cfg.lickNearRewardEnabled
    lickFilterLabel = sprintf('lick within ±%.1f° of reward required', cfg.lickNearRewardWindow_deg);
else
    lickFilterLabel = 'no lick-near-reward exclusion';
end

sessionTitle = sprintf('%s | %s | %s | %s | exclude final %.1f°', ...
    sessionTitle, cfg.lapLabel, lickFilterLabel, cfg.summaryMethodName, cfg.excludeFinal_deg);

end