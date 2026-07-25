function plot_split_profiles(allProfileSpeed, allProfileSiteDeg, allProfileScenario, sessionTitle, cfg)

scenarioOrder = { ...
    'cue_expected', ...
    'preReward_nonTarget_60', ...
    'preReward_nonTarget_150', ...
    'preReward_target_near_60', ...
    'preReward_target_near_150', ...
    'preReward_target_far_240', ...
    'preReward_target_far_330'};

scenarioLabels = { ...
    'Cue expected', ...
    'Pre-reward non-target 60°', ...
    'Pre-reward non-target 150°', ...
    'Pre-reward target near 60°', ...
    'Pre-reward target near 150°', ...
    'Pre-reward target far 240°', ...
    'Pre-reward target far 330°'};

if isempty(allProfileSpeed)
    error('No speed profiles were collected.');
end

figure;
tiledlayout(1, numel(cfg.activeReward_deg));

for s = 1:numel(cfg.activeReward_deg)

    thisSiteDeg = cfg.activeReward_deg(s);

    nexttile;
    hold on

    plotHandles = gobjects(0);
    plotLabels = {};

    for st = 1:numel(scenarioOrder)

        idx = allProfileSiteDeg == thisSiteDeg & strcmp(allProfileScenario, scenarioOrder{st});
        if ~any(idx)
            continue
        end

        profileMat = allProfileSpeed(idx,:);
        profileVec = nan(1, size(profileMat,2));

        for bb = 1:size(profileMat,2)
            vals = profileMat(:,bb);
            vals = vals(~isnan(vals));
            if ~isempty(vals)
                profileVec(bb) = cfg.summaryFcn(vals);
            end
        end

        h = plot(cfg.profileCenters_deg, profileVec, 'LineWidth', 2);
        plotHandles(end+1) = h; %#ok<AGROW>
        plotLabels{end+1} = scenarioLabels{st}; %#ok<AGROW>
    end

    xlabel('Degrees before site', 'FontSize', cfg.labelFontSize);
    ylabel(sprintf('%s speed (cm/s)', cfg.summaryMethodName), 'FontSize', cfg.labelFontSize);

    title(sprintf('%s | Approach to %.0f° site', sessionTitle, thisSiteDeg), ...
        'FontSize', cfg.titleFontSize);

    xlim([-cfg.profileWindow_deg -cfg.excludeFinal_deg]);
    xline(-cfg.excludeFinal_deg, 'k--', 'LineWidth', 1);

    set(gca, 'FontSize', cfg.axisFontSize);
    grid on

    if s == numel(cfg.activeReward_deg) && ~isempty(plotHandles)
        legend(plotHandles, plotLabels, 'FontSize', cfg.legendFontSize, 'Location', 'best');
    end
end

end