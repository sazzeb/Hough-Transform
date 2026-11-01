
classdef WatermarkEngine
    properties (Constant, Access = private)
        HEADER_BYTES = 24
        HEADER_SLOTS = 576
        HEADER_STRENGTH = 16
        REPEATS = 3
    end

    methods (Static)
        function validateImage(imageData)
            validShape = ismatrix(imageData) || ...
                (ndims(imageData) == 3 && size(imageData, 3) == 3);

            if ~isa(imageData, 'uint8') || isempty(imageData) || ~validShape
                error('Watermark:Image', ...
                    'Use a nonempty uint8 grayscale or RGB image.');
            end
        end

        function prepared = prepareWatermark(imageData, targetSize)
            if nargin < 2
                targetSize = [32 32];
            end

            WatermarkEngine.validateImage(imageData);

            if ~isnumeric(targetSize) || numel(targetSize) ~= 2
                error('Watermark:Size', ...
                    'Watermark size must be [height width].');
            end

            height = WatermarkEngine.checkInteger( ...
                targetSize(1), 8, 64, 'Watermark height');

            width = WatermarkEngine.checkInteger( ...
                targetSize(2), 8, 64, 'Watermark width');

            values = double(imageData);

            if ndims(imageData) == 3
                values = (299 * values(:, :, 1) + ...
                    587 * values(:, :, 2) + ...
                    114 * values(:, :, 3)) / 1000;
            end

            sourceRows = (0:height-1) * (size(values, 1)-1) / (height-1) + 1;
            sourceColumns = (0:width-1) * ...
                (size(values, 2)-1) / (width-1) + 1;
            row0 = floor(sourceRows);
            column0 = floor(sourceColumns);
            row1 = min(row0 + 1, size(values, 1));
            column1 = min(column0 + 1, size(values, 2));
            rowWeight = sourceRows - row0;
            columnWeight = sourceColumns - column0;

            top = values(row0, column0) .* (1-columnWeight) + ...
                values(row0, column1) .* columnWeight;
            bottom = values(row1, column0) .* (1-columnWeight) + ...
                values(row1, column1) .* columnWeight;
            prepared = uint8(floor( ...
                top .* (1-rowWeight).' + bottom .* rowWeight.' + 0.5));
        end

        function capacity = capacityBytes(imageData)
            WatermarkEngine.validateImage(imageData);

            slots = 2 * floor(size(imageData, 1)/2) * ...
                floor(size(imageData, 2)/2);

            capacity = max( ...
                0, floor(slots / 24) - WatermarkEngine.HEADER_BYTES);
        end

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

        function result = embed(cover, watermark, strength, targetSize)
            if nargin < 3
                strength = 16;
            end

            if nargin < 4
                targetSize = [32 32];
            end

            WatermarkEngine.validateImage(cover);

            strength = WatermarkEngine.checkInteger( ...
                strength, 8, 32, 'Strength');

            prepared = WatermarkEngine.prepareWatermark( ...
                watermark, targetSize);

            payload = reshape(prepared.', 1, []);
            capacity = WatermarkEngine.capacityBytes(cover);

            if numel(payload) > capacity
                error('Watermark:Capacity', ...
                    ['Watermark needs %d bytes; cover holds %d. ' ...
                     'Use a smaller watermark size or a larger cover.'], ...
                    numel(payload), capacity);
            end

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

        function result = extract(imageData)
            WatermarkEngine.validateImage(imageData);

            split = WatermarkEngine.HEADER_SLOTS;
            availableSlots = 2 * floor(size(imageData, 1)/2) * ...
                floor(size(imageData, 2)/2);

            if availableSlots < split
                error('Watermark:Header', ...
                    'The image is too small for a watermark header.');
            end

            headerBlocks = WatermarkEngine.readBlocks( ...
                imageData, split/2, 1);

            headerCoefficients = HaarTransform.forward(headerBlocks);
            headerSlots = reshape( ...
                headerCoefficients(:, 2:3).', 1, []);

            header = WatermarkEngine.decodeSlots( ...
                headerSlots, ...
                WatermarkEngine.HEADER_BYTES, ...
                WatermarkEngine.HEADER_STRENGTH);

            body = header(1:20);

            storedHeaderCrc = WatermarkEngine.unpackUnsigned( ...
                header(21:24));

            if double(WatermarkEngine.crc32(body)) ~= storedHeaderCrc
                error('Watermark:Header', ...
                    'No valid watermark header was found, or it is damaged.');
            end

            strength = double(body(5));
            height = WatermarkEngine.unpackUnsigned(body(9:10));
            width = WatermarkEngine.unpackUnsigned(body(11:12));
            payloadLength = WatermarkEngine.unpackUnsigned(body(13:16));
            expectedCrc = WatermarkEngine.unpackUnsigned(body(17:20));

            if ~isequal(body(1:4), uint8('WVM1')) || ...
                    ~isequal(body(6:8), uint8([3 1 0])) || ...
                    strength < 8 || strength > 32 || ...
                    height < 8 || height > 64 || ...
                    width < 8 || width > 64 || ...
                    payloadLength ~= height * width

                error('Watermark:Format', ...
                    'The watermark format is invalid or unsupported.');
            end

            lastSlot = split + payloadLength * 24;

            if lastSlot > availableSlots
                error('Watermark:Incomplete', ...
                    ['The watermark is incomplete; ' ...
                     'image dimensions may have changed.']);
            end

            payloadBlocks = WatermarkEngine.readBlocks( ...
                imageData, lastSlot/2, 1);

            coefficients = HaarTransform.forward(payloadBlocks);
            slots = reshape(coefficients(:, 2:3).', 1, []);

            payload = WatermarkEngine.decodeSlots( ...
                slots(split+1:lastSlot), payloadLength, strength);

            if double(WatermarkEngine.crc32(payload)) ~= expectedCrc
                error('Watermark:Checksum', ...
                    'Watermark checksum failed. The embedded data is damaged.');
            end

            recovered = reshape(payload, width, height).';

            result = struct( ...
                'watermark', recovered, ...
                'strength', strength);
        end
    end

    methods (Static, Access = private)
        function value = checkInteger(value, minimum, maximum, label)
            if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
                    ~isfinite(value) || value ~= floor(value) || ...
                    value < minimum || value > maximum

                error('Watermark:Option', ...
                    '%s must be a whole number from %d to %d.', ...
                    label, minimum, maximum);
            end

            value = double(value);
        end

        function blocks = readBlocks(imageData, blockCount, channel)
            if nargin < 3
                channel = 1;
                if ndims(imageData) == 3
                    channel = 3;
                end
            end

            if ismatrix(imageData)
                plane = imageData;
            else
                plane = imageData(:, :, channel);
            end

            width = 2 * floor(size(plane, 2)/2);
            blocksPerRow = width/2;
            available = floor(size(plane, 1)/2) * blocksPerRow;

            if nargin < 2
                blockCount = available;
            end

            if blockCount < 0 || blockCount > available || ...
                    blockCount ~= floor(blockCount)
                error('Watermark:Blocks', ...
                    'Requested image blocks are unavailable.');
            end

            if blockCount == 0
                blocks = zeros(0, 4);
                return;
            end

            height = 2 * ceil(blockCount/blocksPerRow);

            offsets = [1 1; 1 2; 2 1; 2 2];
            blocks = zeros(height*width/4, 4);

            for index = 1:4
                part = plane( ...
                    offsets(index, 1):2:height, ...
                    offsets(index, 2):2:width);

                blocks(:, index) = double(reshape(part.', [], 1));
            end

            blocks = blocks(1:blockCount, :);
        end

        function output = writeBlocks(imageData, blocks, channel)
            output = imageData;
            if nargin < 3
                channel = 1;
            end

            plane = output(:, :, channel);

            height = 2 * floor(size(plane, 1)/2);
            width = 2 * floor(size(plane, 2)/2);

            rounded = floor(blocks + 0.5);

            if any(rounded(:) < 0 | rounded(:) > 255)
                error('Watermark:Range', ...
                    'Internal error: reconstructed pixels exceed uint8.');
            end

            offsets = [1 1; 1 2; 2 1; 2 2];

            for index = 1:4
                rows = offsets(index, 1):2:height;
                columns = offsets(index, 2):2:width;

                part = plane(rows, columns);
                values = reshape(part.', [], 1);

                values(1:size(blocks, 1)) = uint8(rounded(:, index));

                plane(rows, columns) = reshape( ...
                    values, width/2, height/2).';
            end

            output(:, :, channel) = plane;
        end

        function bits = makeBits(bytes)
            bits = zeros(1, numel(bytes)*8);

            for bit = 1:8
                bits(bit:8:end) = double(bitget(bytes, 9-bit));
            end

            bits = repmat(bits, 1, WatermarkEngine.REPEATS);
        end

        function changed = quantize(slots, bits, strength)
            changed = strength * ...
                (2 * floor((slots/strength-bits)/2 + 0.5) + bits);
        end

        function bytes = decodeSlots(slots, byteCount, strength)
            bits = mod(floor(slots/strength + 0.5), 2);

            votes = reshape( ...
                bits, byteCount*8, WatermarkEngine.REPEATS);

            recovered = sum(votes, 2) >= 2;
            bytes = zeros(1, byteCount, 'uint8');

            for bit = 1:8
                bytes = bitor( ...
                    bytes, ...
                    bitshift(uint8(recovered(bit:8:end).'), 8-bit));
            end
        end

        function bytes = packUnsigned(value, count)
            value = uint32(value);
            bytes = zeros(1, count, 'uint8');

            for index = count:-1:1
                bytes(index) = uint8(bitand(value, uint32(255)));
                value = bitshift(value, -8);
            end
        end

        function value = unpackUnsigned(bytes)
            value = sum( ...
                double(bytes) .* 256.^(numel(bytes)-1:-1:0));
        end

        function checksum = crc32(bytes)
            persistent table

            if isempty(table)
                table = zeros(1, 256, 'uint32');
                polynomial = uint32(hex2dec('EDB88320'));

                for index = 0:255
                    value = uint32(index);

                    for bit = 1:8
                        if bitand(value, uint32(1)) ~= 0
                            value = bitxor( ...
                                bitshift(value, -1), polynomial);
                        else
                            value = bitshift(value, -1);
                        end
                    end

                    table(index+1) = value;
                end
            end

            checksum = uint32(hex2dec('FFFFFFFF'));

            for value = reshape(bytes, 1, [])
                index = double(bitand( ...
                    bitxor(checksum, uint32(value)), ...
                    uint32(255))) + 1;

                checksum = bitxor( ...
                    bitshift(checksum, -8), table(index));
            end

            checksum = bitcmp(checksum);
        end
    end
end
