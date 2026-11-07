function quality = psnr(original, modified)
    WatermarkEngine.validateImage(original);
    WatermarkEngine.validateImage(modified);

    if ~isequal(size(original), size(modified))
        error('Watermark:Shape', ...
            'PSNR requires images with identical shapes.');
    end

    difference = double(original(:)) - double(modified(:));
    mse = mean(difference .^ 2);

    if mse == 0
        quality = Inf;
    else
        quality = 10 * log10(255^2 / mse);
    end
end
