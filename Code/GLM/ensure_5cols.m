function X5 = ensure_5cols(X)
    % Standardize to [Pos, Context, Chair, Drum, Star]
    if size(X,2)==5
        X5 = X;
    elseif size(X,2)==4
        X5 = [X(:,1), zeros(size(X,1),1), X(:,2:4)];
    else
        error('Predictor matrix must have 4 or 5 columns.');
    end
end