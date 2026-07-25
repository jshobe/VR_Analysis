clear; clc;

cfg = get_circular_split_curve_config();

[fileList, basePath, cfg] = prompt_circular_split_curve_inputs(cfg);

allRows = {};
allProfileSpeed = [];
allProfileSiteDeg = [];
allProfileState = {};
allProfileScenario = {};

for f = 1:numel(fileList)
    fname = fullfile(basePath, fileList{f});

    session = load_session_and_crop_laps(fname, cfg);
    if isempty(session)
        continue
    end

    rewards = extract_reward_events(session, cfg);
    if isempty(rewards.rewardOnsetIdx)
        warning('No reward onsets matched active reward pair in file: %s', session.fileName);
        continue
    end

    cues = extract_cue_epochs(session, cfg);
    if isempty(cues.cueOnsetIdx)
        warning('No valid cue epochs found in file: %s', session.fileName);
    end

    [eventRows, profileSpeed, profileSiteDeg, profileState, profileScenario] = ...
        build_interval_events(session, rewards, cues, cfg);

    if ~isempty(eventRows)
        allRows = [allRows; eventRows]; %#ok<AGROW>
        allProfileSpeed = [allProfileSpeed; profileSpeed]; %#ok<AGROW>
        allProfileSiteDeg = [allProfileSiteDeg; profileSiteDeg]; %#ok<AGROW>
        allProfileState = [allProfileState; profileState]; %#ok<AGROW>
        allProfileScenario = [allProfileScenario; profileScenario]; %#ok<AGROW>
    end
end

if isempty(allRows)
    error('No usable interval-based events found.');
end

[T, rawDecelTable, sessionTitle] = finalize_event_table( ...
    allRows, allProfileSpeed, allProfileSiteDeg, allProfileState, allProfileScenario, cfg);

disp('Raw deceleration values organized by bar:')
disp(rawDecelTable)

disp('Counts by state:')
disp(groupsummary(T, 'state'))

disp('Counts by site and state:')
disp(groupsummary(T, {'siteDeg','state'}))

fprintf('%ss by state:\n', cfg.summaryMethodName)
disp(groupsummary(T, 'state', cfg.summaryMethodName, ...
    {'approachSpeed','decelNearSpeed','decelControlSpeed','rawDecel'}))

fprintf('%ss by site and state:\n', cfg.summaryMethodName)
disp(groupsummary(T, {'siteDeg','state'}, cfg.summaryMethodName, ...
    {'approachSpeed','decelNearSpeed','decelControlSpeed','rawDecel'}))

plot_summary_bars(T, sessionTitle, cfg);
plot_split_profiles(allProfileSpeed, allProfileSiteDeg, allProfileScenario, sessionTitle, cfg);

%% ===================== OPTIONAL SAVE TABLE =====================
saveCsvChoice = menu('Save event table as CSV?', 'No', 'Yes');

if isequal(saveCsvChoice, 2)
    [outFile, outPath] = uiputfile('interval_based_cue_analysis.csv', ...
        'Save event table as CSV');

    if ~isequal(outFile,0)
        writetable(T, fullfile(outPath, outFile));
        fprintf('Saved table to: %s\n', fullfile(outPath, outFile));
    end
end