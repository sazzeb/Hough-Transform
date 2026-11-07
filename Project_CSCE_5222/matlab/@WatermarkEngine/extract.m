function result = extract(imageData)
    WatermarkEngine.validateImage(imageData);

    split = WatermarkEngine.HEADER_SLOTS;
    availableSlots = 2 * floor(size(imageData, 1)/2) * ...
        floor(size(imageData, 2)/2);

    if availableSlots < split
        error('Watermark:Header', ...
            'The image is too small for a watermark header.');
    end

    channelCount = 1;
    if ndims(imageData) == 3
        channelCount = 3;
    end
    headerCopies = zeros( ...
        channelCount, WatermarkEngine.HEADER_BYTES, 'uint8');
    for channel = 1:channelCount
        headerBlocks = WatermarkEngine.readBlocks( ...
            imageData, split/2, channel);
        headerCoefficients = HaarTransform.forward(headerBlocks);
        headerSlots = reshape( ...
            headerCoefficients(:, 2:3).', 1, []);
        headerCopies(channel, :) = WatermarkEngine.decodeSlots( ...
            headerSlots, WatermarkEngine.HEADER_BYTES, ...
            WatermarkEngine.HEADER_STRENGTH);
    end
    header = WatermarkEngine.mergeCopies(headerCopies);

    body = header(1:20);

    storedHeaderCrc = WatermarkEngine.unpackUnsigned( ...
        header(21:24));

    if double(WatermarkEngine.crc32(body)) ~= storedHeaderCrc
        error('Watermark:Header', ...
            'No valid watermark header was found, or it is damaged.');
    end

    strength = double(body(5));
    repeats = double(body(6));
    flags = double(body(8));
    height = WatermarkEngine.unpackUnsigned(body(9:10));
    width = WatermarkEngine.unpackUnsigned(body(11:12));
    payloadLength = WatermarkEngine.unpackUnsigned(body(13:16));
    expectedCrc = WatermarkEngine.unpackUnsigned(body(17:20));

    isClassic = isequal(body(1:4), uint8('WVM1')) && ...
        repeats == 3 && isequal(body(7:8), uint8([1 0]));
    isImproved = isequal(body(1:4), uint8('WVM2')) && ...
        body(7) == 1 && ...
        ((repeats == 3 && flags == 3) || ...
        (repeats == 5 && flags == 7));
    if ~(isClassic || isImproved) || ...
            strength < 8 || strength > 32 || ...
            height < 8 || height > 64 || ...
            width < 8 || width > 64 || ...
            payloadLength ~= height * width

        error('Watermark:Format', ...
            'The watermark format is invalid or unsupported.');
    end

    lastSlot = split + payloadLength * 8 * repeats;

    if lastSlot > availableSlots
        error('Watermark:Incomplete', ...
            ['The watermark is incomplete; ' ...
             'image dimensions may have changed.']);
    end

    payloadCopies = zeros(channelCount, payloadLength, 'uint8');
    if isImproved
        indices = WatermarkEngine.blockIndices( ...
            imageData, payloadLength * 8 * repeats / 2);
    end
    for channel = 1:channelCount
        if isImproved
            payloadBlocks = WatermarkEngine.readSelectedBlocks( ...
                imageData, indices, channel);
            coefficients = HaarTransform.forward(payloadBlocks);
            localStrengths = WatermarkEngine.adaptiveStrengths( ...
                coefficients, strength);
            slotStrengths = repelem(localStrengths, 2);
            slots = reshape(coefficients(:, 2:3).', 1, []);
            bits = mod(floor(slots ./ slotStrengths + 0.5), 2);
            votes = reshape(bits, payloadLength*8, repeats);
            recoveredBits = sum(votes, 2) >= ...
                floor(repeats/2) + 1;
            payloadCopies(channel, :) = ...
                WatermarkEngine.bitsToBytes(recoveredBits);
        else
            payloadBlocks = WatermarkEngine.readBlocks( ...
                imageData, lastSlot/2, channel);
            coefficients = HaarTransform.forward(payloadBlocks);
            slots = reshape(coefficients(:, 2:3).', 1, []);
            payloadCopies(channel, :) = ...
                WatermarkEngine.decodeSlots( ...
                    slots(split+1:lastSlot), ...
                    payloadLength, strength);
        end
    end
    payload = WatermarkEngine.mergeCopies(payloadCopies);

    verified = double(WatermarkEngine.crc32(payload)) == expectedCrc;
    if ~verified && ~(isImproved && flags == 7)
        error('Watermark:Checksum', ...
            'Watermark checksum failed. The embedded data is damaged.');
    end

    recovered = reshape(payload, width, height).';

    result = struct( ...
        'watermark', recovered, ...
        'strength', strength, ...
        'verified', verified);
end
