function score = ssim(original, modified)
    %SSIM Mean structural similarity over nonoverlapping 8x8 blocks.
    WatermarkEngine.validateImage(original);
    WatermarkEngine.validateImage(modified);
    if ~isequal(size(original), size(modified))
        error('Watermark:Shape', ...
            'SSIM requires images with identical shapes.');
    end
    first = double(original);
    second = double(modified);
    if ndims(first) == 3
        weights = reshape([0.299 0.587 0.114], 1, 1, 3);
        first = sum(first .* weights, 3);
        second = sum(second .* weights, 3);
    end
    height = 8 * floor(size(first, 1) / 8);
    width = 8 * floor(size(first, 2) / 8);
    if height == 0 || width == 0
        error('Watermark:Shape', 'SSIM needs at least 8x8 pixels.');
    end
    first = reshape(first(1:height, 1:width), ...
        8, height/8, 8, width/8);
    second = reshape(second(1:height, 1:width), ...
        8, height/8, 8, width/8);
    average = @(data) mean(mean(data, 1), 3);
    meanFirst = average(first);
    meanSecond = average(second);
    varianceFirst = average(first.^2) - meanFirst.^2;
    varianceSecond = average(second.^2) - meanSecond.^2;
    covariance = average(first.*second) - ...
        meanFirst.*meanSecond;
    c1 = (0.01 * 255)^2;
    c2 = (0.03 * 255)^2;
    blocks = ((2*meanFirst.*meanSecond+c1) .* ...
        (2*covariance+c2)) ./ ...
        ((meanFirst.^2+meanSecond.^2+c1) .* ...
        (varianceFirst+varianceSecond+c2));
    score = mean(blocks(:));
end
