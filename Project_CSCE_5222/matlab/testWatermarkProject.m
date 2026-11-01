function testWatermarkProject()
% Verify Haar-transform embedding and exact extraction from unchanged PNGs,
% validation, PNG storage, alpha compositing, and palette-image support.
    previousRandomState = rng;

    randomCleanup = onCleanup( ...
        @()rng(previousRandomState));

    rng(42);

    blocks = double(randi([0 255], 1000, 4));

    assert(isequal( ...
        HaarTransform.inverse(HaarTransform.forward(blocks)), ...
        blocks));

    watermark = uint8(randi([0 255], 37, 49, 3));

    shapes = {
        [256 256], ...
        [257 259 3], ...
        [512 512 3]
    };

    caseCount = 0;

    for shapeIndex = 1:numel(shapes)
        shape = shapes{shapeIndex};

        [columns, rows] = meshgrid( ...
            0:shape(2)-1, 0:shape(1)-1);

        checker = uint8(mod(rows+columns, 2) * 255);

        if numel(shape) == 3
            checker = repmat(checker, 1, 1, 3);
        end

        covers = {
            zeros(shape, 'uint8'), ...
            repmat(uint8(255), shape), ...
            checker, ...
            uint8(randi([0 255], shape))
        };

        for strength = 8:32
            for coverIndex = 1:numel(covers)
                cover = covers{coverIndex};

                result = WatermarkEngine.embed( ...
                    cover, watermark, strength);

                extracted = WatermarkEngine.extract(result.image);

                assert(isequal( ...
                    extracted.watermark, result.preparedWatermark));

                assert(extracted.strength == strength);
                assert(isa(result.image, 'uint8'));
                assert(isequal(size(result.image), size(cover)));

                if ndims(cover) == 3
                    assert(any(result.image(:) ~= cover(:)));
                end

                if mod(shape(1), 2) == 1
                    assert(isequal( ...
                        result.image(end, :, :), cover(end, :, :)));
                end

                if mod(shape(2), 2) == 1
                    assert(isequal( ...
                        result.image(:, end, :), cover(:, end, :)));
                end

                caseCount = caseCount + 1;
            end
        end
    end

    cover = repmat(uint8(128), 256, 256);

    for strength = [0 7 33 8.5 NaN Inf]
        mustFail(@()WatermarkEngine.embed( ...
            cover, watermark, strength));
    end

    mustFail(@()WatermarkEngine.embed( ...
        double(cover), watermark));

    mustFail(@()WatermarkEngine.embed( ...
        zeros(0, 5, 'uint8'), watermark));

    mustFail(@()WatermarkEngine.embed( ...
        zeros(16, 16, 4, 'uint8'), watermark));

    mustFail(@()WatermarkEngine.extract( ...
        zeros(256, 256, 'uint8')));

    mustFail(@()WatermarkEngine.extract( ...
        zeros(1, 1, 'uint8')));

    mustFail(@()WatermarkEngine.embed( ...
        cover, watermark, 16, [7 8]));

    mustFail(@()WatermarkEngine.embed( ...
        zeros(64, 64, 'uint8'), watermark, 16, [8 8]));

    exactCover = repmat(uint8(128), 66, 64);

    assert(WatermarkEngine.capacityBytes(exactCover) == 64);

    WatermarkEngine.embed( ...
        exactCover, watermark, 16, [8 8]);

    for targetSize = {[8 31], [24 24], [64 64]}
        result = WatermarkEngine.embed( ...
            repmat(uint8(128), 512, 512), ...
            watermark, 11, targetSize{1});

        assert(isequal( ...
            size(result.preparedWatermark), targetSize{1}));
    end

    result = WatermarkEngine.embed(cover, watermark);

    sample = sampleWatermark();
    assert(isequal(size(sample), [96 96]));
    assert(numel(unique(sample)) > 2);

    projectFolder = fileparts(fileparts(mfilename('fullpath')));
    photograph = ImageStore.read( ...
        fullfile(projectFolder, 'python', 'sample_cover.jpg'));
    sampleResult = WatermarkEngine.embed(photograph, sample);
    sampleRecovered = WatermarkEngine.extract(sampleResult.image);
    assert(isequal( ...
        sampleRecovered.watermark, sampleResult.preparedWatermark));

    repaired = WatermarkEngine.extract( ...
        flipSlots(result.image, [0 576], 16));

    assert(isequal( ...
        repaired.watermark, result.preparedWatermark));

    mustFail(@()WatermarkEngine.extract( ...
        flipSlots(result.image, [0 192], 16)));

    mustFail(@()WatermarkEngine.extract( ...
        flipSlots(result.image, [576 576+8192], 16)));

    mustFail(@()WatermarkEngine.extract( ...
        result.image(1:100, :)));

    folder = tempname;
    mkdir(folder);

    fileCleanup = onCleanup( ...
        @()rmdir(folder, 's'));

    path = ImageStore.savePng( ...
        fullfile(folder, 'watermarked.png'), result.image);

    reloaded = ImageStore.read(path, true);

    assert(isequal(reloaded, result.image));

    recovered = WatermarkEngine.extract(reloaded);

    assert(isequal( ...
        recovered.watermark, result.preparedWatermark));

    ImageStore.savePng( ...
        fullfile(folder, 'extracted.png'), recovered.watermark);

    mustFail(@()ImageStore.savePng( ...
        fullfile(folder, 'invalid.jpg'), result.image));

    largeImagePath = fullfile(folder, 'large-input.jpg');
    imwrite(zeros(5000, 5000, 'uint8'), largeImagePath);
    resizedInput = ImageStore.read(largeImagePath);
    assert(numel(resizedInput) <= ImageStore.MaxWorkingPixels);
    assert(size(resizedInput, 1) < 5000);
    assert(size(resizedInput, 2) < 5000);
    largeInfo = imfinfo(largeImagePath);
    assert(largeInfo.Width == 5000 && largeInfo.Height == 5000);
    clear resizedInput;

    alphaSource = repmat( ...
        reshape(uint8([100 150 200]), 1, 1, 3), ...
        8, 8);

    alphaPath = fullfile(folder, 'alpha.png');

    imwrite( ...
        alphaSource, alphaPath, ...
        'Alpha', repmat(uint8(128), 8, 8));

    composited = ImageStore.read(alphaPath);

    assert(isequal( ...
        reshape(composited(1, 1, :), 1, 3), ...
        uint8([177 202 227])));

    mustFail(@()ImageStore.read(alphaPath, true));

    palettePath = fullfile(folder, 'palette.png');

    imwrite( ...
        zeros(8, 8, 'uint8'), ...
        [1 0 0; 0 0 0], ...
        palettePath);

    paletteImage = ImageStore.read(palettePath);

    assert(isequal( ...
        reshape(paletteImage(1, 1, :), 1, 3), ...
        uint8([255 0 0])));

    % These values are also checked by the Python test suite.
    goldenCover = reshape( ...
        uint8(mod(0:65535, 256)), 256, 256).';

    goldenMark = reshape(uint8(0:63), 8, 8).';

    golden = WatermarkEngine.embed( ...
        goldenCover, goldenMark, 12, [8 8]);

    values = double(reshape(golden.image.', 1, []));

    assert(sum(values) == 8357952);

    assert( ...
        mod(sum(values .* (1:65536)), 2^32) == 3586566448);

    assert(sum(values.^2) == 1422849056);

    fprintf( ...
        ['Passed %d recovery cases and the validation, storage, ' ...
         'damage and fixture checks.\n'], ...
        caseCount);
end

function mustFail(operation)
    failed = false;

    try
        operation();
    catch exception
        assert( ...
            startsWith(exception.identifier, 'Watermark:'), ...
            exception.message);

        failed = true;
    end

    assert(failed, ...
        'An invalid operation was unexpectedly accepted.');
end

function output = flipSlots(imageData, positions, strength)
    output = imageData;
    blockColumns = floor(size(imageData, 2)/2);

    for position = positions
        block = floor(position/2);

        row = 2 * floor(block/blockColumns) + 1;
        column = 2 * mod(block, blockColumns) + 1;

        part = output(row:row+1, column:column+1);

        coefficients = HaarTransform.forward( ...
            reshape(double(part.'), 1, 4));

        detail = 2 + mod(position, 2);
        coefficients(detail) = coefficients(detail) + strength;

        changed = floor( ...
            HaarTransform.inverse(coefficients) + 0.5);

        assert(all(changed >= 0 & changed <= 255));

        output(row:row+1, column:column+1) = ...
            reshape(uint8(changed), 2, 2).';
    end
end
