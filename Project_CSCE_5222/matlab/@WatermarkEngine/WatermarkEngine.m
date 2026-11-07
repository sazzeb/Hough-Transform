
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

            scale = min(height/size(values, 1), ...
                width/size(values, 2));
            fittedHeight = max(1, min(height, ...
                round(size(values, 1) * scale)));
            fittedWidth = max(1, min(width, ...
                round(size(values, 2) * scale)));
            sourceRows = linspace(1, size(values, 1), fittedHeight);
            sourceColumns = linspace(1, size(values, 2), fittedWidth);
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
            fitted = uint8(floor( ...
                top .* (1-rowWeight).' + bottom .* rowWeight.' + 0.5));
            prepared = repmat(uint8(255), height, width);
            firstRow = floor((height-fittedHeight)/2) + 1;
            firstColumn = floor((width-fittedWidth)/2) + 1;
            prepared(firstRow:firstRow+fittedHeight-1, ...
                firstColumn:firstColumn+fittedWidth-1) = fitted;
        end

        function capacity = capacityBytes(imageData, mode)
            if nargin < 2
                mode = 'classic';
            end
            WatermarkEngine.validateImage(imageData);

            if ~any(strcmp(mode, {'classic', 'balanced', 'durable'}))
                error('Watermark:Option', ...
                    'Mode must be classic, balanced or durable.');
            end

            slots = 2 * floor(size(imageData, 1)/2) * ...
                floor(size(imageData, 2)/2);

            repeats = 3;
            if strcmp(mode, 'durable')
                repeats = 5;
            end
            capacity = max(0, floor( ...
                (slots-WatermarkEngine.HEADER_SLOTS) / (8*repeats)));
        end

        quality = psnr(original, modified)

        score = ssim(original, modified)

        rate = bitErrorRate(original, recovered)

        score = normalizedCorrelation(original, recovered)

        report = evaluateRobustness(cover, watermark, progress)

        result = embed(cover, watermark, strength, targetSize, mode)

        result = extract(imageData)

    end

    methods (Static, Access = private)
        changed = applyStudyChange(imageData, changeIndex)

        function deleteStudyFile(filename)
            if isfile(filename)
                delete(filename);
            end
        end

        result = embedImproved(cover, prepared, strength, mode)

        function indices = blockIndices(imageData, blockCount)
            headerBlocks = WatermarkEngine.HEADER_SLOTS / 2;
            available = floor(size(imageData, 1)/2) * ...
                floor(size(imageData, 2)/2);
            remaining = available - headerBlocks;
            if blockCount > remaining
                error('Watermark:Capacity', ...
                    'The cover cannot hold this watermark.');
            end
            indices = headerBlocks + floor( ...
                ((0:blockCount-1) + 0.5) * remaining / blockCount);
        end

        function blocks = readSelectedBlocks(imageData, indices, channel)
            if ismatrix(imageData)
                plane = imageData;
            else
                plane = imageData(:, :, channel);
            end
            columns = floor(size(plane, 2)/2);
            rows = 2 * floor(indices / columns) + 1;
            cols = 2 * mod(indices, columns) + 1;
            blocks = zeros(numel(indices), 4);
            offsets = [0 0; 0 1; 1 0; 1 1];
            for index = 1:4
                positions = sub2ind(size(plane), ...
                    rows + offsets(index, 1), ...
                    cols + offsets(index, 2));
                blocks(:, index) = double(plane(positions(:)));
            end
        end

        function output = writeSelectedBlocks( ...
                imageData, indices, blocks, channel)
            output = imageData;
            if ismatrix(output)
                plane = output;
            else
                plane = output(:, :, channel);
            end
            rounded = floor(blocks + 0.5);
            if any(rounded(:) < 0 | rounded(:) > 255)
                error('Watermark:Range', ...
                    'Reconstructed pixels exceed uint8.');
            end
            columns = floor(size(plane, 2)/2);
            rows = 2 * floor(indices / columns) + 1;
            cols = 2 * mod(indices, columns) + 1;
            offsets = [0 0; 0 1; 1 0; 1 1];
            for index = 1:4
                positions = sub2ind(size(plane), ...
                    rows + offsets(index, 1), ...
                    cols + offsets(index, 2));
                plane(positions) = uint8(rounded(:, index));
            end
            if ismatrix(output)
                output = plane;
            else
                output(:, :, channel) = plane;
            end
        end

        function strengths = adaptiveStrengths(coefficients, strength)
            quietStrength = max(8, floor(0.75 * strength + 0.5));
            strengths = repmat(strength, 1, size(coefficients, 1));
            strengths(abs(coefficients(:, 4)) < 16) = quietStrength;
        end

        function coefficients = stabilizeAdaptiveDetails(coefficients)
            % Keep the texture decision stable after pixel rounding.
            details = coefficients(:, 4);
            quiet = abs(details) < 16;
            details(quiet) = min(12, max(-12, details(quiet)));
            details(~quiet) = sign(details(~quiet)) .* ...
                max(20, abs(details(~quiet)));
            coefficients(:, 4) = details;
        end

        function bytes = mergeCopies(copies)
            if size(copies, 1) == 1
                bytes = copies;
                return;
            end
            bytes = zeros(1, size(copies, 2), 'uint8');
            for bit = 1:8
                votes = sum(bitget(copies, 9-bit), 1) >= 2;
                bytes = bitor(bytes, ...
                    bitshift(uint8(votes), 8-bit));
            end
        end

        function bits = makeBitsWithRepeats(bytes, repeats)
            bits = zeros(1, numel(bytes)*8);
            for bit = 1:8
                bits(bit:8:end) = double(bitget(bytes, 9-bit));
            end
            bits = repmat(bits, 1, repeats);
        end

        function bytes = bitsToBytes(bits)
            bytes = zeros(1, numel(bits)/8, 'uint8');
            for bit = 1:8
                bytes = bitor(bytes, ...
                    bitshift(uint8(bits(bit:8:end).'), 8-bit));
            end
        end

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

        blocks = readBlocks(imageData, blockCount, channel)

        output = writeBlocks(imageData, blocks, channel)

        function bits = makeBits(bytes)
            bits = zeros(1, numel(bytes)*8);

            for bit = 1:8
                bits(bit:8:end) = double(bitget(bytes, 9-bit));
            end

            bits = repmat(bits, 1, WatermarkEngine.REPEATS);
        end

        function changed = quantize(slots, bits, strength)
            changed = strength .* ...
                (2 * floor((slots./strength-bits)/2 + 0.5) + bits);
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
