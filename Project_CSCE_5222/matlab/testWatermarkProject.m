function testWatermarkProject()
% Check embedding, recovery, image loading, and saved PNGs.
    previousRandomState = rng;

    randomCleanup = onCleanup( ...
        @()rng(previousRandomState));

    rng(42);

    blocks = double(randi([0 255], 1000, 4));

    assert(isequal( ...
        HaarTransform.inverse(HaarTransform.forward(blocks)), ...
        blocks));

    metricCover = repmat(uint8(100), 8, 8, 3);
    metricChanged = repmat(uint8(110), 8, 8, 3);
    assert(WatermarkEngine.ssim(metricCover, metricCover) == 1);
    assert(isinf(WatermarkEngine.psnr(metricCover, metricCover)));
    assert(abs(WatermarkEngine.psnr(metricCover, metricChanged) - ...
        20*log10(255/10)) < 1e-10);
    assert(WatermarkEngine.ssim(metricCover, metricChanged) < 1);
    metricOriginal = uint8([1 0]);
    metricRecovered = uint8([1 1]);
    assert(WatermarkEngine.bitErrorRate( ...
        metricOriginal, metricRecovered) == 1/16);
    assert(abs(WatermarkEngine.normalizedCorrelation( ...
        metricOriginal, metricRecovered) - 1/sqrt(2)) < 1e-12);
    assert(isnan(WatermarkEngine.normalizedCorrelation( ...
        uint8([0 0]), metricRecovered)));

    studyCover = repmat(uint8(128), 192, 192);
    studyMark = reshape(uint8(0:255), 16, 16);
    study = WatermarkEngine.evaluateRobustness( ...
        studyCover, studyMark);
    assert(size(study.details, 1) == 72);
    assert(size(study.summary, 1) == 24);
    assert(study.skippedConfigurations == 18);
    unchanged = strcmp(study.details(:, 4), 'Unchanged PNG');
    assert(all(strcmp(study.details(unchanged, 5), ...
        'Verified exact')));
    assert(all(cell2mat(study.details(unchanged, 8)) == 0));
    assert(all(cell2mat(study.summary(:, 5)) >= 0 & ...
        cell2mat(study.summary(:, 5)) <= 1));

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
        fullfile(projectFolder, 'matlab', 'source', ...
            'images', 'sample_cover.jpg'));
    sampleResult = WatermarkEngine.embed(photograph, sample);
    sampleRecovered = WatermarkEngine.extract(sampleResult.image);
    assert(isequal( ...
        sampleRecovered.watermark, sampleResult.preparedWatermark));

    gallery = ExampleGallery();
    assert(numel(gallery.Entries) >= 10);
    previousCover = '';
    for roundNumber = 1:2
        seenCovers = cell(1, numel(gallery.Entries));
        for exampleIndex = 1:numel(gallery.Entries)
            example = gallery.nextExample();
            assert(~strcmp(example.coverPath, previousCover));
            assert(~strcmp(example.coverPath, example.watermarkPath));
            assert(isfile(example.coverPath));
            assert(isfile(example.watermarkPath));
            assert(startsWith(example.coverSource, ...
                'https://unsplash.com/photos/'));
            seenCovers{exampleIndex} = example.coverPath;
            previousCover = example.coverPath;

            if roundNumber == 1
                [exampleCover, exampleWatermark] = ...
                    gallery.loadExample(example);
                assert(isequal(size(exampleCover), [768 1152 3]));
                assert(isequal(size(exampleWatermark), [96 96]));
                for exampleMode = {'classic', 'balanced', 'durable'}
                    for exampleStrength = [8 16 32]
                        embeddedExample = WatermarkEngine.embed( ...
                            exampleCover, exampleWatermark, ...
                            exampleStrength, [32 32], exampleMode{1});
                        recoveredExample = WatermarkEngine.extract( ...
                            embeddedExample.image);
                        assert(recoveredExample.verified, ...
                            'Example recovery failed: %s (%s, %d)', ...
                            example.title, exampleMode{1}, ...
                            exampleStrength);
                        assert(isequal(recoveredExample.watermark, ...
                            embeddedExample.preparedWatermark));
                    end
                end
            end
        end
        assert(numel(unique(seenCovers)) == numel(gallery.Entries));
    end

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

    largePngPath = fullfile(folder, 'large-original.png');
    imwrite(zeros(5000, 5000, 'uint8'), largePngPath);
    mustFail(@()ImageStore.read(largePngPath, true));

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

    wideMark = repmat(uint8(70), 16, 32);
    fittedMark = WatermarkEngine.prepareWatermark( ...
        wideMark, [32 32]);
    assert(all(fittedMark(1:8, :) == 255, 'all'));
    assert(all(fittedMark(9:24, :) == 70, 'all'));

    improvedCover = repmat(uint8(128), 512, 512, 3);
    for mode = {'balanced', 'durable'}
        improved = WatermarkEngine.embed( ...
            improvedCover, wideMark, 24, [32 32], mode{1});
        damaged = improved.image;
        damaged(:, :, 1) = improvedCover(:, :, 1);
        recovered = WatermarkEngine.extract(damaged);
        assert(isequal( ...
            recovered.watermark, improved.preparedWatermark));
        changedRows = any(improved.image ~= improvedCover, [2 3]);
        assert(find(changedRows, 1, 'last') > 400);
        improvedPath = ImageStore.savePng( ...
            fullfile(folder, [mode{1} '.png']), improved.image);
        reopened = ImageStore.read(improvedPath, true);
        reopenedMark = WatermarkEngine.extract(reopened);
        assert(isequal( ...
            reopenedMark.watermark, improved.preparedWatermark));
    end

    fixtureMark = reshape(uint8(0:255), 16, 16).';
    fixture = WatermarkEngine.embed( ...
        improvedCover, fixtureMark, 16, [16 16], 'balanced');
    fixtureValues = double(reshape( ...
        permute(fixture.image, [3 2 1]), 1, []));
    assert(sum(fixtureValues) == 100663296);
    assert(sum(fixtureValues.^2) == 12886360320);
    assert(mod(sum(fixtureValues .* ...
        (1:numel(fixtureValues))), 2^32) == 4252447456);

    durableGray = WatermarkEngine.embed( ...
        repmat(uint8(128), 512, 512), fixtureMark, ...
        32, [16 16], 'durable');
    payloadBitsPerCopy = numel(fixtureMark) * 8;
    payloadBlocks = payloadBitsPerCopy * 5 / 2;
    remainingBlocks = 512 * 512 / 4 - 288;
    copySlots = [0 payloadBitsPerCopy 2*payloadBitsPerCopy];
    selectedBlocks = 288 + floor( ...
        (floor(copySlots/2) + 0.5) * ...
        remainingBlocks / payloadBlocks);
    approximateImage = flipSlots( ...
        durableGray.image, 2*selectedBlocks, 24);
    approximate = WatermarkEngine.extract(approximateImage);
    assert(~approximate.verified);
    assert(~isequal( ...
        approximate.watermark, durableGray.preparedWatermark));

    fprintf( ...
        ['Passed %d recovery cases and the validation, storage, ' ...
         'damage and fixture checks.\n'], ...
        caseCount);
end

function mustFail(operation)
    % Confirm that a bad input raises a watermark error.
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
    % Change chosen wavelet values to test damage recovery.
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
