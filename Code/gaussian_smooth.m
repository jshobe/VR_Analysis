function y = gaussian_smooth(x, sigma_bins)
x = double(x(:)');
if ~isfinite(sigma_bins) || sigma_bins <= 0 || all(~isfinite(x))
    y = x; return;
end
halfWidth = ceil(sigma_bins);

%halfWidth = ceil(3 * sigma_bins);
g = exp(-(((-halfWidth:halfWidth).^2) / (2 * sigma_bins^2)));
g = g / sum(g);
valid = isfinite(x);
xf = x; xf(~valid) = 0;
yNum = conv(xf, g, 'same');
yDen = conv(double(valid), g, 'same');
y = yNum ./ yDen;
y(yDen < 0.1) = NaN;
end