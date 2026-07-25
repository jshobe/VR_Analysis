function [summaryMethodName, summaryFcn] = prompt_summary_method()

summaryChoice = menu( ...
    'Use mean or median for speed summaries?', ...
    'Median', ...
    'Mean');

if isequal(summaryChoice, 0)
    error('No summary method selected.');
end

if summaryChoice == 1
    summaryMethodName = 'median';
    summaryFcn = @(x) median(x);
else
    summaryMethodName = 'mean';
    summaryFcn = @(x) mean(x);
end
end