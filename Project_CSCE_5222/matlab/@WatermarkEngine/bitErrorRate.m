function rate = bitErrorRate(original, recovered)
    % Count wrong bits in the recovered watermark.
    WatermarkEngine.validateImage(original);
    WatermarkEngine.validateImage(recovered);
    if ~isequal(size(original), size(recovered))
        error('Watermark:Shape', ...
            'BER requires watermarks with identical shapes.');
    end
    changed = bitxor(original(:), recovered(:));
    bitErrors = 0;
    for bit = 1:8
        bitErrors = bitErrors + sum(bitget(changed, bit));
    end
    rate = double(bitErrors) / (8 * numel(changed));
end
