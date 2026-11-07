function result = embed(cover, watermark, strength, targetSize, mode)
    % Place the prepared watermark in Haar detail values.
    if nargin < 3
        strength = 16;
    end

    if nargin < 4
        targetSize = [32 32];
    end
    if nargin < 5
        mode = 'classic';
    end

    WatermarkEngine.validateImage(cover);

    strength = WatermarkEngine.checkInteger( ...
        strength, 8, 32, 'Strength');

    prepared = WatermarkEngine.prepareWatermark( ...
        watermark, targetSize);

    if any(strcmp(mode, {'balanced', 'durable'}))
        result = WatermarkEngine.embedImproved( ...
            cover, prepared, strength, mode);
        return;
    end

    if ~strcmp(mode, 'classic')
        error('Watermark:Option', ...
            'Mode must be classic, balanced or durable.');
    end

    payload = reshape(prepared.', 1, []);
    capacity = WatermarkEngine.capacityBytes(cover);

    if numel(payload) > capacity
        error('Watermark:Capacity', ...
            ['Watermark needs %d bytes; cover holds %d. ' ...
             'Use a smaller watermark size or a larger cover.'], ...
            numel(payload), capacity);
    end

    % The header records the settings, size, and checksums.
    body = [ ...
        uint8('WVM1'), ...
        uint8([strength 3 1 0]), ...
        WatermarkEngine.packUnsigned(size(prepared, 1), 2), ...
        WatermarkEngine.packUnsigned(size(prepared, 2), 2), ...
        WatermarkEngine.packUnsigned(numel(payload), 4), ...
        WatermarkEngine.packUnsigned( ...
            WatermarkEngine.crc32(payload), 4) ...
    ];

    header = [ ...
        body, ...
        WatermarkEngine.packUnsigned( ...
            WatermarkEngine.crc32(body), 4) ...
    ];

    headerBits = WatermarkEngine.makeBits(header);
    payloadBits = WatermarkEngine.makeBits(payload);

    usedSlots = numel(headerBits) + numel(payloadBits);

    margin = max(strength, WatermarkEngine.HEADER_STRENGTH);

    output = cover;
    channelCount = 1;
    if ndims(cover) == 3
        channelCount = 3;
    end

    % Store the bits in each available image channel.
    for channel = 1:channelCount
        blocks = WatermarkEngine.readBlocks( ...
            cover, usedSlots/2, channel);
        blocks = min(255-margin, max(margin, blocks));
        coefficients = HaarTransform.forward(blocks);
        slots = reshape(coefficients(:, 2:3).', 1, []);

        split = WatermarkEngine.HEADER_SLOTS;
        slots(1:split) = WatermarkEngine.quantize( ...
            slots(1:split), headerBits, ...
            WatermarkEngine.HEADER_STRENGTH);
        slots(split+1:end) = WatermarkEngine.quantize( ...
            slots(split+1:end), payloadBits, strength);
        coefficients(:, 2:3) = reshape(slots, 2, []).';

        output = WatermarkEngine.writeBlocks( ...
            output, HaarTransform.inverse(coefficients), channel);
    end

    % Recover the mark once before returning the image.
    checked = WatermarkEngine.extract(output);

    if ~isequal(checked.watermark, prepared)
        error('Watermark:SelfCheck', ...
            'The embedding self-check failed.');
    end

    result = struct( ...
        'image', output, ...
        'preparedWatermark', prepared, ...
        'strength', strength, ...
        'psnr', WatermarkEngine.psnr(cover, output));
end
