
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

        function rate = bitErrorRate(original, recovered)
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

        function score = normalizedCorrelation(original, recovered)
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

        function report = evaluateRobustness(cover, watermark, progress)
            %EVALUATEROBUSTNESS Compare recovery under specified changes.
            % The cover is fitted within 512 pixels to bound study runtime.
            if nargin < 3
                progress = [];
            end
            WatermarkEngine.validateImage(cover);
            WatermarkEngine.validateImage(watermark);
            scale = min(1, 512/max(size(cover, 1), size(cover, 2)));
            if scale < 1
                workingCover = imresize(cover, scale, 'bilinear');
            else
                workingCover = cover;
            end

            modes = {'classic', 'balanced', 'durable'};
            strengths = [8 16 32];
            sides = [16 32 64];
            changes = {'Unchanged PNG', 'JPEG 95', 'JPEG 75', ...
                'JPEG 50', 'Crop 5% each edge', ...
                'Crop 10% each edge', 'Resize 75%', 'Resize 50%'};
            skipped = 0;
            configuration = 0;
            totalConfigurations = numel(modes)*numel(strengths)*numel(sides);
            details = cell(totalConfigurations*numel(changes), 9);
            detailCount = 0;

            for modeIndex = 1:numel(modes)
                mode = modes{modeIndex};
                capacity = WatermarkEngine.capacityBytes( ...
                    workingCover, mode);
                for strength = strengths
                    for side = sides
                        configuration = configuration + 1;
                        if ~isempty(progress)
                            progress(configuration, totalConfigurations);
                        end
                        if side^2 > capacity
                            skipped = skipped + 1;
                            continue;
                        end
                        embedded = WatermarkEngine.embed( ...
                            workingCover, watermark, strength, ...
                            [side side], mode);
                        quality = WatermarkEngine.psnr( ...
                            workingCover, embedded.image);
                        structure = WatermarkEngine.ssim( ...
                            workingCover, embedded.image);
                        for changeIndex = 1:numel(changes)
                            changed = WatermarkEngine.applyStudyChange( ...
                                embedded.image, changeIndex);
                            bitRate = NaN;
                            correlation = NaN;
                            try
                                recovered = WatermarkEngine.extract(changed);
                                if isequal(size(recovered.watermark), ...
                                        size(embedded.preparedWatermark))
                                    bitRate = WatermarkEngine.bitErrorRate( ...
                                        embedded.preparedWatermark, ...
                                        recovered.watermark);
                                    correlation = ...
                                        WatermarkEngine.normalizedCorrelation( ...
                                        embedded.preparedWatermark, ...
                                        recovered.watermark);
                                end
                                if recovered.verified && bitRate == 0
                                    state = 'Verified exact';
                                elseif recovered.verified
                                    state = 'Verified, pixels differ';
                                else
                                    state = 'Checksum failed; approximate';
                                end
                            catch exception
                                if strcmp(exception.identifier, ...
                                        'Watermark:Checksum')
                                    state = 'Payload checksum failed';
                                elseif any(strcmp(exception.identifier, ...
                                        {'Watermark:Header', ...
                                        'Watermark:Format'}))
                                    state = 'Header unreadable';
                                elseif strcmp(exception.identifier, ...
                                        'Watermark:Incomplete')
                                    state = 'Incomplete payload';
                                else
                                    rethrow(exception);
                                end
                            end
                            detailCount = detailCount + 1;
                            details(detailCount, :) = {mode, strength, side, ...
                                changes{changeIndex}, state, ...
                                quality, structure, bitRate, correlation};
                        end
                    end
                end
            end

            details = details(1:detailCount, :);
            summary = cell(numel(modes)*numel(changes), 10);
            summaryCount = 0;
            for modeIndex = 1:numel(modes)
                for changeIndex = 1:numel(changes)
                    selected = strcmp(details(:, 1), modes{modeIndex}) & ...
                        strcmp(details(:, 4), changes{changeIndex});
                    rows = details(selected, :);
                    if isempty(rows)
                        continue;
                    end
                    states = rows(:, 5);
                    exactCount = sum(strcmp(states, 'Verified exact'));
                    unreadableCount = sum(strcmp( ...
                        states, 'Header unreadable'));
                    incompleteCount = sum(strcmp( ...
                        states, 'Incomplete payload'));
                    failedCount = sum(contains(states, 'checksum failed', ...
                        'IgnoreCase', true));
                    bitRates = cell2mat(rows(:, 8));
                    correlations = cell2mat(rows(:, 9));
                    validBits = bitRates(isfinite(bitRates));
                    validCorrelations = correlations( ...
                        isfinite(correlations));
                    meanBitRate = NaN;
                    meanCorrelation = NaN;
                    if ~isempty(validBits)
                        meanBitRate = mean(validBits);
                    end
                    if ~isempty(validCorrelations)
                        meanCorrelation = mean(validCorrelations);
                    end
                    summaryCount = summaryCount + 1;
                    summary(summaryCount, :) = {modes{modeIndex}, ...
                        changes{changeIndex}, exactCount, size(rows, 1), ...
                        exactCount/size(rows, 1), unreadableCount, ...
                        incompleteCount, failedCount, ...
                        meanBitRate, meanCorrelation};
                end
            end
            summary = summary(1:summaryCount, :);
            report = struct('details', {details}, 'summary', {summary}, ...
                'workingSize', size(workingCover), ...
                'skippedConfigurations', skipped);
        end

        function result = embed(cover, watermark, strength, targetSize, mode)
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
    end

    methods (Static, Access = private)
        function changed = applyStudyChange(imageData, changeIndex)
            switch changeIndex
                case 1
                    filename = [tempname '.png'];
                    cleanup = onCleanup( ...
                        @()WatermarkEngine.deleteStudyFile(filename));
                    imwrite(imageData, filename, 'png');
                    changed = imread(filename);
                case {2, 3, 4}
                    qualities = [95 75 50];
                    filename = [tempname '.jpg'];
                    cleanup = onCleanup( ...
                        @()WatermarkEngine.deleteStudyFile(filename));
                    imwrite(imageData, filename, 'jpg', ...
                        'Quality', qualities(changeIndex-1));
                    changed = imread(filename);
                case {5, 6}
                    fractions = [0.05 0.10];
                    amount = fractions(changeIndex-4);
                    trimRows = floor(amount*size(imageData, 1));
                    trimColumns = floor(amount*size(imageData, 2));
                    changed = imageData( ...
                        trimRows+1:end-trimRows, ...
                        trimColumns+1:end-trimColumns, :);
                case {7, 8}
                    factors = [0.75 0.5];
                    changed = imresize(imageData, ...
                        factors(changeIndex-6), 'bilinear');
                otherwise
                    error('Watermark:Option', ...
                        'Unknown robustness study change.');
            end
        end

        function deleteStudyFile(filename)
            if isfile(filename)
                delete(filename);
            end
        end

        function result = embedImproved(cover, prepared, strength, mode)
            repeats = 3;
            flags = 3;
            if strcmp(mode, 'durable')
                repeats = 5;
                flags = 7;
            end

            payload = reshape(prepared.', 1, []);
            payloadBits = WatermarkEngine.makeBitsWithRepeats( ...
                payload, repeats);
            availableBlocks = floor(size(cover, 1)/2) * ...
                floor(size(cover, 2)/2);
            headerBlocks = WatermarkEngine.HEADER_SLOTS / 2;
            payloadBlockCount = numel(payloadBits) / 2;

            if payloadBlockCount > availableBlocks - headerBlocks
                error('Watermark:Capacity', ...
                    ['The cover cannot hold this watermark. ' ...
                     'Choose a smaller watermark size or a larger cover.']);
            end

            body = [ ...
                uint8('WVM2'), uint8([strength repeats 1 flags]), ...
                WatermarkEngine.packUnsigned(size(prepared, 1), 2), ...
                WatermarkEngine.packUnsigned(size(prepared, 2), 2), ...
                WatermarkEngine.packUnsigned(numel(payload), 4), ...
                WatermarkEngine.packUnsigned( ...
                    WatermarkEngine.crc32(payload), 4)];
            header = [body, WatermarkEngine.packUnsigned( ...
                WatermarkEngine.crc32(body), 4)];
            headerBits = WatermarkEngine.makeBits(header);
            headerIndices = 0:headerBlocks-1;
            payloadIndices = WatermarkEngine.blockIndices( ...
                cover, payloadBlockCount);
            margin = max(strength, WatermarkEngine.HEADER_STRENGTH) + 8;
            output = cover;
            channelCount = 1;
            if ndims(cover) == 3
                channelCount = 3;
            end

            for channel = 1:channelCount
                headerPixels = WatermarkEngine.readSelectedBlocks( ...
                    cover, headerIndices, channel);
                headerPixels = min(255-margin, max(margin, headerPixels));
                headerCoefficients = HaarTransform.forward(headerPixels);
                headerSlots = reshape( ...
                    headerCoefficients(:, 2:3).', 1, []);
                headerCoefficients(:, 2:3) = reshape( ...
                    WatermarkEngine.quantize( ...
                        headerSlots, headerBits, ...
                        WatermarkEngine.HEADER_STRENGTH), 2, []).';
                output = WatermarkEngine.writeSelectedBlocks( ...
                    output, headerIndices, ...
                    HaarTransform.inverse(headerCoefficients), channel);

                payloadPixels = WatermarkEngine.readSelectedBlocks( ...
                    cover, payloadIndices, channel);
                payloadPixels = min(255-margin, max(margin, payloadPixels));
                payloadCoefficients = HaarTransform.forward(payloadPixels);
                localStrengths = WatermarkEngine.adaptiveStrengths( ...
                    payloadCoefficients, strength);
                payloadCoefficients = ...
                    WatermarkEngine.stabilizeAdaptiveDetails( ...
                        payloadCoefficients);
                slotStrengths = repelem(localStrengths, 2);
                slots = reshape(payloadCoefficients(:, 2:3).', 1, []);
                payloadCoefficients(:, 2:3) = reshape( ...
                    WatermarkEngine.quantize( ...
                        slots, payloadBits, slotStrengths), 2, []).';
                output = WatermarkEngine.writeSelectedBlocks( ...
                    output, payloadIndices, ...
                    HaarTransform.inverse(payloadCoefficients), channel);
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
