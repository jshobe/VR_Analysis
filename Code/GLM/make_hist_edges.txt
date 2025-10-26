function edgesByPred = make_hist_edges(predList, limitsStruct, binWidth, numBins)
% Build consistent histogram edges per predictor using provided limits
edgesByPred = struct();
for p = 1:numel(predList)
    pred = predList{p};
    lim = limitsStruct.(pred);
    mn = lim(1); mx = lim(2);
    if mn == mx
        delta = max(1e-6, max(1e-6, abs(mn)*0.01));
        mn = mn - delta; mx = mx + delta;
    end
    if ~isempty(binWidth)
        startEdge = floor(mn/binWidth)*binWidth;
        endEdge   = ceil(mx/binWidth)*binWidth;
        edges = startEdge:binWidth:endEdge;
        if numel(edges) < 2
            edges = [mn, mx];
        end
    elseif ~isempty(numBins)
        edges = linspace(mn, mx, round(numBins)+1);
    else
        edges = linspace(mn, mx, 30+1);
    end
    edgesByPred.(pred) = edges;
end
end