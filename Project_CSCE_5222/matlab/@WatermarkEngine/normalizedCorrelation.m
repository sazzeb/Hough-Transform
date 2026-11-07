function score = normalizedCorrelation(original, recovered)
    % Measure how closely the watermark pixels line up.
    WatermarkEngine.validateImage(original);
    WatermarkEngine.validateImage(recovered);
    if ~isequal(size(original), size(recovered))
        error('Watermark:Shape', ...
            'NCC requires watermarks with identical shapes.');
    end
    first = double(original(:));
    second = double(recovered(:));
    denominator = sqrt(sum(first.^2) * sum(second.^2));
    score = NaN;
    if denominator > 0
        score = sum(first.*second) / denominator;
    end
end
