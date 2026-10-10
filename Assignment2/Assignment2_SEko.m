%% This section loads the source image, checks required tools, and displays the original.
% Save this script beside the photograph before running the complete assignment.
% Run the entire script so every task and helper function becomes available.

clear;
clc;
close all;

imageFilename = 'victoria.jpg';

noiseMean = 0;
noiseVariance = 0.01;
filterWindow = [5, 5];

sobelThresholds = [0.04, 0.12];
cannyThresholds = [
    0.05, 0.15
    0.15, 0.35
];

cannySigma = 1.4;
resizeFactors = [0.75, 0.50, 0.25];

requiredFunctions = {'imnoise', 'wiener2', 'edge', 'imresize'};

for functionIndex = 1:numel(requiredFunctions)
    functionName = requiredFunctions{functionIndex};

    if exist(functionName, 'file') == 0
        error('Assignment2:MissingToolbox', ...
            ['The function "%s" is unavailable. Install or enable ' ...
             'Image Processing Toolbox before running this script.'], ...
            functionName);
    end
end

projectFolder = fileparts(mfilename('fullpath'));

if isempty(projectFolder)
    projectFolder = pwd;
end

imagePath = fullfile(projectFolder, imageFilename);

if ~isfile(imagePath)
    error('Assignment2:MissingImage', ...
        ['Cannot find the image:\n%s\n' ...
         'Place it beside Assignment2_SEko.m or update imageFilename.'], ...
        imagePath);
end

[originalImage, colorMap] = imread(imagePath);

if ~isempty(colorMap)
    originalImage = ind2rgb(originalImage, colorMap);
end

originalImage = im2double(originalImage);
grayscaleImage = convertToGrayscale(originalImage);

[originalHeight, originalWidth] = size(grayscaleImage);

displayImages( ...
    'Task 1: Original Image', ...
    {originalImage}, ...
    {'Original image'}, ...
    1, 1);

fprintf('Loaded image: %s\n', imageFilename);
fprintf('Original size: %d rows by %d columns.\n', ...
    originalHeight, originalWidth);


%% This section adds Gaussian noise and compares the original and noisy images.

% Keep the random seed fixed so repeated runs produce matching noise results.
rng(21, 'twister');

noisyImage = imnoise( ...
    originalImage, 'gaussian', noiseMean, noiseVariance);

assert(isequal(size(noisyImage), size(originalImage)), ...
    'Adding noise must preserve the original image dimensions.');

displayImages( ...
    'Task 2: Gaussian Noise', ...
    {originalImage, noisyImage}, ...
    {
        'Original image'
        sprintf('Gaussian noise: variance = %.3f', noiseVariance)
    }, ...
    1, 2);


%% This section reduces Gaussian noise and displays the filtered image for comparison.

denoisedImage = reduceGaussianNoise( ...
    noisyImage, filterWindow, noiseVariance);

assert(isequal(size(denoisedImage), size(originalImage)), ...
    'Noise reduction must preserve the original image dimensions.');

displayImages( ...
    'Task 3: Noise Reduction', ...
    {originalImage, noisyImage, denoisedImage}, ...
    {
        'Original image'
        'Image with Gaussian noise'
        'After Wiener filtering'
    }, ...
    1, 3);

noisyError = mean((originalImage(:) - noisyImage(:)).^2);
denoisedError = mean((originalImage(:) - denoisedImage(:)).^2);

fprintf('\nMean squared error compared with the original:\n');
fprintf('Before filtering: %.6f\n', noisyError);
fprintf('After filtering:  %.6f\n', denoisedError);
fprintf('A smaller error means a closer match to the original.\n');


%% This section applies automatic Sobel and Canny edge detection to the original image.

% Detect edges from the original grayscale image before adding any noise.
[sobelAutomatic, sobelAutomaticThreshold] = ...
    edge(grayscaleImage, 'Sobel');

[cannyAutomatic, cannyAutomaticThresholds] = ...
    edge(grayscaleImage, 'Canny', [], cannySigma);

displayImages( ...
    'Task 4: Automatic Edge Detection', ...
    {grayscaleImage, sobelAutomatic, cannyAutomatic}, ...
    {
        'Original grayscale image'
        sprintf('Sobel: automatic T = %.4f', ...
            sobelAutomaticThreshold)
        sprintf('Canny: automatic [%.4f %.4f]', ...
            cannyAutomaticThresholds(1), ...
            cannyAutomaticThresholds(2))
    }, ...
    1, 3);


%% This section repeats both edge methods using two different threshold settings.

sobelThresholdImages = cell(1, numel(sobelThresholds));
cannyThresholdImages = cell(1, size(cannyThresholds, 1));

for thresholdIndex = 1:numel(sobelThresholds)
    sobelThresholdImages{thresholdIndex} = edge( ...
        grayscaleImage, 'Sobel', ...
        sobelThresholds(thresholdIndex));

    cannyThresholdImages{thresholdIndex} = edge( ...
        grayscaleImage, 'Canny', ...
        cannyThresholds(thresholdIndex, :), cannySigma);
end

thresholdTitles = {
    sprintf('Sobel: T = %.2f', sobelThresholds(1))
    sprintf('Sobel: T = %.2f', sobelThresholds(2))
    sprintf('Canny: [%.2f %.2f]', ...
        cannyThresholds(1, 1), cannyThresholds(1, 2))
    sprintf('Canny: [%.2f %.2f]', ...
        cannyThresholds(2, 1), cannyThresholds(2, 2))
};

displayImages( ...
    'Task 5: Threshold Comparison', ...
    {
        grayscaleImage
        sobelThresholdImages{1}
        sobelThresholdImages{2}
        grayscaleImage
        cannyThresholdImages{1}
        cannyThresholdImages{2}
    }, ...
    {
        'Original grayscale image'
        thresholdTitles{1}
        thresholdTitles{2}
        'Original grayscale image'
        thresholdTitles{3}
        thresholdTitles{4}
    }, ...
    2, 3);


%% This section resizes the original image and repeats edge detection at every scale.

numberOfScales = numel(resizeFactors);

resizedColorImages = cell(numberOfScales, 1);
resizedGrayImages = cell(numberOfScales, 1);

resizedSobelEdges = cell(numberOfScales, 3);
resizedCannyEdges = cell(numberOfScales, 3);

for scaleIndex = 1:numberOfScales
    currentScale = resizeFactors(scaleIndex);

    % Resize directly from the original image to avoid repeated resizing losses.
    resizedImage = imresize( ...
        originalImage, currentScale, ...
        'bicubic', 'Antialiasing', true);

    resizedImage = min(max(resizedImage, 0), 1);
    resizedGrayscale = convertToGrayscale(resizedImage);

    expectedSize = ceil( ...
        [originalHeight, originalWidth] * currentScale);

    assert(isequal(size(resizedGrayscale), expectedSize), ...
        'The resized image dimensions do not match the requested scale.');

    resizedColorImages{scaleIndex} = resizedImage;
    resizedGrayImages{scaleIndex} = resizedGrayscale;

    [resizedSobelEdges{scaleIndex, 1}, resizedSobelThreshold] = ...
        edge(resizedGrayscale, 'Sobel');

    [resizedCannyEdges{scaleIndex, 1}, resizedCannyThresholds] = ...
        edge(resizedGrayscale, 'Canny', [], cannySigma);

    % Keep manual thresholds unchanged when comparing images with different dimensions.
    for thresholdIndex = 1:numel(sobelThresholds)
        resizedSobelEdges{scaleIndex, thresholdIndex + 1} = edge( ...
            resizedGrayscale, 'Sobel', ...
            sobelThresholds(thresholdIndex));

        resizedCannyEdges{scaleIndex, thresholdIndex + 1} = edge( ...
            resizedGrayscale, 'Canny', ...
            cannyThresholds(thresholdIndex, :), cannySigma);
    end

    displayImages( ...
        sprintf('Task 6: Scale %.2f', currentScale), ...
        {
            resizedImage
            resizedSobelEdges{scaleIndex, 1}
            resizedSobelEdges{scaleIndex, 2}
            resizedSobelEdges{scaleIndex, 3}
            resizedGrayscale
            resizedCannyEdges{scaleIndex, 1}
            resizedCannyEdges{scaleIndex, 2}
            resizedCannyEdges{scaleIndex, 3}
        }, ...
        {
            sprintf('Scale %.2f: %d rows x %d columns', ...
                currentScale, size(resizedImage, 1), ...
                size(resizedImage, 2))
            sprintf('Sobel: automatic T = %.4f', ...
                resizedSobelThreshold)
            thresholdTitles{1}
            thresholdTitles{2}
            'Resized grayscale image'
            sprintf('Canny: automatic [%.4f %.4f]', ...
                resizedCannyThresholds(1), ...
                resizedCannyThresholds(2))
            thresholdTitles{3}
            thresholdTitles{4}
        }, ...
        2, 4);

    fprintf('Scale %.2f: %d rows by %d columns.\n', ...
        currentScale, size(resizedImage, 1), size(resizedImage, 2));
end


%% This section saves every result image and verifies the stored pixel contents.

[~, imageBaseName] = fileparts(imageFilename);

outputFolder = fullfile( ...
    projectFolder, 'Assignment2_Results', imageBaseName);

resultsToSave = {
    '01_original.png', originalImage
    '02_original_grayscale.png', grayscaleImage
    '03_gaussian_noise.png', noisyImage
    '04_wiener_denoised.png', denoisedImage
    '05_sobel_automatic.png', sobelAutomatic
    '06_canny_automatic.png', cannyAutomatic
    '07_sobel_threshold_1.png', sobelThresholdImages{1}
    '08_sobel_threshold_2.png', sobelThresholdImages{2}
    '09_canny_threshold_1.png', cannyThresholdImages{1}
    '10_canny_threshold_2.png', cannyThresholdImages{2}
};

settingNames = {'automatic', 'threshold_1', 'threshold_2'};

for scaleIndex = 1:numberOfScales
    scaleLabel = sprintf( ...
        'scale_%03d', round(resizeFactors(scaleIndex) * 100));

    resultsToSave(end + 1, :) = {
        [scaleLabel, '_original.png'], ...
        resizedColorImages{scaleIndex}
    };

    resultsToSave(end + 1, :) = {
        [scaleLabel, '_grayscale.png'], ...
        resizedGrayImages{scaleIndex}
    };

    for settingIndex = 1:numel(settingNames)
        settingName = settingNames{settingIndex};

        resultsToSave(end + 1, :) = {
            sprintf('%s_sobel_%s.png', scaleLabel, settingName), ...
            resizedSobelEdges{scaleIndex, settingIndex}
        };

        resultsToSave(end + 1, :) = {
            sprintf('%s_canny_%s.png', scaleLabel, settingName), ...
            resizedCannyEdges{scaleIndex, settingIndex}
        };
    end
end

savedImageCount = saveResultImages(outputFolder, resultsToSave);

fprintf('\nAll seven tasks finished successfully.\n');
fprintf('Saved and verified %d PNG images.\n', savedImageCount);
fprintf('Results folder:\n%s\n', outputFolder);


%% These local helper functions validate images, display results, and save verified files.

function grayscaleImage = convertToGrayscale(inputImage)
% Accept grayscale or RGB input and return normalized grayscale image values.

    validateattributes(inputImage, {'numeric', 'logical'}, ...
        {'nonempty', 'real', 'finite', 'nonsparse'});

    if ismatrix(inputImage)
        grayscaleImage = im2double(inputImage);

    elseif ndims(inputImage) == 3 && size(inputImage, 3) == 3
        grayscaleImage = rgb2gray(im2double(inputImage));

    else
        error('Assignment2:UnsupportedImage', ...
            'The image must be grayscale or have three RGB channels.');
    end

    assert(all(grayscaleImage(:) >= 0 & grayscaleImage(:) <= 1), ...
        'Normalized image values must remain between zero and one.');
end


function denoisedImage = reduceGaussianNoise( ...
    noisyImage, neighborhoodSize, noiseVariance)
% Filter each color channel separately so noise decreases without mixing colors.

    validateattributes(neighborhoodSize, {'numeric'}, ...
        {'vector', 'numel', 2, 'integer', 'positive'});

    validateattributes(noiseVariance, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'positive'});

    noisyImage = im2double(noisyImage);
    denoisedImage = zeros(size(noisyImage));

    for channelIndex = 1:size(noisyImage, 3)
        denoisedImage(:, :, channelIndex) = wiener2( ...
            noisyImage(:, :, channelIndex), ...
            neighborhoodSize, noiseVariance);
    end

    denoisedImage = min(max(denoisedImage, 0), 1);

    assert(all(isfinite(denoisedImage(:))), ...
        'The filtered image contains invalid pixel values.');
end


function displayImages( ...
    figureName, imageList, titleList, rowCount, columnCount)
% Display related images together with clear titles for direct visual comparison.

    assert(numel(imageList) == numel(titleList), ...
        'Each displayed image must have one matching title.');

    assert(numel(imageList) <= rowCount * columnCount, ...
        'The selected layout does not have enough image panels.');

    figure( ...
        'Name', figureName, ...
        'NumberTitle', 'off', ...
        'Color', 'white');

    for imageIndex = 1:numel(imageList)
        subplot(rowCount, columnCount, imageIndex);
        imshow(imageList{imageIndex});
        title(titleList{imageIndex}, 'Interpreter', 'none');
    end

    drawnow;
end


function savedImageCount = saveResultImages(outputFolder, resultList)
% Save each result as PNG and verify that stored pixels match prepared values.

    if ~isfolder(outputFolder)
        [folderCreated, folderMessage] = mkdir(outputFolder);

        if ~folderCreated
            error('Assignment2:OutputFolder', ...
                'Cannot create the results folder: %s', folderMessage);
        end
    end

    savedImageCount = 0;

    for imageIndex = 1:size(resultList, 1)
        outputFilename = resultList{imageIndex, 1};
        resultImage = resultList{imageIndex, 2};

        validateattributes(resultImage, {'numeric', 'logical'}, ...
            {'nonempty', 'real', 'finite', 'nonsparse'});

        % Convert each result to eight-bit pixels before checking its saved copy.
        preparedImage = im2uint8(resultImage);
        outputPath = fullfile(outputFolder, outputFilename);

        imwrite(preparedImage, outputPath, 'png');

        savedImage = imread(outputPath);

        if ~isequal(savedImage, preparedImage)
            error('Assignment2:SaveVerification', ...
                'Saved pixels do not match the prepared image: %s', ...
                outputFilename);
        end

        savedImageCount = savedImageCount + 1;
    end
end