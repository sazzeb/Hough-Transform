%% 1. Read the original photograph and display its colors.
% Place both photos in the same folder, then run this script.
% Load the original and reference images before starting the work.

clear;
clc;
close all;

originalImageFilename = 'farmer_market.jpg';
referenceImageFilename = 'evening_street.jpg';

% Stop the script if the source image is missing from the folder.
assert(isfile(originalImageFilename), ...
    'The original image is missing from the current folder.');

% Stop the script if the reference image is missing from the folder.
assert(isfile(referenceImageFilename), ...
    'The reference image is missing from the current folder.');

% Read the market photo and confirm it has RGB color channels.
originalColorImage = imread(originalImageFilename);

assert(ndims(originalColorImage) == 3 && ...
    size(originalColorImage, 3) == 3, ...
    'The original photograph must have three RGB color channels.');

[originalHeight, originalWidth, ~] = size(originalColorImage);

% Show the original photo so the user can compare later results.
figure('Name', 'Original Photograph');
imshow(originalColorImage);
title('Original Farmer Market Photograph');


%% 2. Convert the photograph to HSV and display each channel.

% Convert the image to HSV and display each channel separately.
hueSaturationValueImage = rgb2hsv(originalColorImage);

hueChannel = hueSaturationValueImage(:, :, 1);
saturationChannel = hueSaturationValueImage(:, :, 2);
valueChannel = hueSaturationValueImage(:, :, 3);

% Each panel shows one HSV channel as a grayscale brightness map.
figure('Name', 'HSV Channels');

subplot(1, 3, 1);
imshow(hueChannel, [0, 1]);
title('Hue');

subplot(1, 3, 2);
imshow(saturationChannel, [0, 1]);
title('Saturation');

subplot(1, 3, 3);
imshow(valueChannel, [0, 1]);
title('Value');

% Check that the HSV values stay inside the valid zero to one range.
assert(all(hueSaturationValueImage(:) >= 0 & ...
    hueSaturationValueImage(:) <= 1), ...
    'Every HSV channel value must remain between zero and one.');


%% 3. Double the image dimensions and crop its center.

% Enlarge the image and crop the center to keep the original size.
enlargedColorImage = imresize(originalColorImage, 2, 'bicubic');

cropStartColumn = floor( ...
    (size(enlargedColorImage, 2) - originalWidth) / 2) + 1;

cropStartRow = floor( ...
    (size(enlargedColorImage, 1) - originalHeight) / 2) + 1;

% Use the crop rectangle to remove extra border pixels cleanly.
cropRectangle = [cropStartColumn, cropStartRow, ...
    originalWidth - 1, originalHeight - 1];

croppedColorImage = imcrop(enlargedColorImage, cropRectangle);

% Show the enlarged image beside the centered crop for comparison.
figure('Name', 'Enlarged and Cropped Photographs');

subplot(1, 2, 1);
imshow(enlargedColorImage);
title(sprintf('Enlarged: %d Rows, %d Columns', ...
    size(enlargedColorImage, 1), size(enlargedColorImage, 2)));

subplot(1, 2, 2);
imshow(croppedColorImage);
title(sprintf('Cropped: %d Rows, %d Columns', ...
    size(croppedColorImage, 1), size(croppedColorImage, 2)));

% Confirm the enlarged image doubles each original dimension correctly.
assert(size(enlargedColorImage, 1) == 2 * originalHeight && ...
    size(enlargedColorImage, 2) == 2 * originalWidth, ...
    'The enlarged photograph must double both original image dimensions.');

assert(isequal(size(croppedColorImage), size(originalColorImage)), ...
    'The cropped photograph must match the original image dimensions.');



%% 4. Remove color while keeping the photograph's brightness information.

% Remove color information while keeping the image brightness values.
grayscaleImage = rgb2gray(originalColorImage);

% Compare the color photo with its grayscale version side by side.
figure('Name', 'Color and Grayscale Comparison');

subplot(1, 2, 1);
imshow(originalColorImage);
title('Original Color Photograph');

subplot(1, 2, 2);
imshow(grayscaleImage);
title('Grayscale Photograph');

% Confirm the grayscale image contains one channel only.
assert(ismatrix(grayscaleImage), ...
    'The grayscale photograph must contain only one image channel.');




%% 5. Display how pixel brightness spreads across the photograph.

% Build a grayscale histogram to show pixel brightness distribution.
grayscaleHistogramCounts = imhist(grayscaleImage, 256);

grayscaleHistogramFigure = figure('Name', 'Grayscale Histogram');

% Plot the brightness counts and label the axes clearly.
imhist(grayscaleImage, 256);
title('Farmer Market Grayscale Histogram');
xlabel('Pixel Brightness');
ylabel('Number of Pixels');
grid on;

% Verify that the histogram counts cover every pixel in the image.
assert(sum(grayscaleHistogramCounts) == numel(grayscaleImage), ...
    'The histogram must count every pixel in the grayscale photograph.');


%% 6. Match the market brightness distribution to the street reference.

% Read the street reference image used for brightness matching.
referenceImage = imread(referenceImageFilename);

% Match the market brightness to the street reference for comparison.
[matchedGrayscaleImage, referenceGrayscaleImage, ...
    sourceGrayscaleImage] = matchGrayscaleHistogram( ...
    referenceImage, originalColorImage);

% Show the reference, source, and matched image in one layout.
histogramMatchingFigure = figure('Name', 'Histogram Matching');

subplot(2, 3, 1);
imshow(referenceGrayscaleImage);
title('Street Reference');

subplot(2, 3, 2);
imshow(sourceGrayscaleImage);
title('Market Before Matching');

subplot(2, 3, 3);
imshow(matchedGrayscaleImage);
title('Market After Matching');

subplot(2, 3, 4);
imhist(referenceGrayscaleImage, 256);
title('Reference Histogram');

subplot(2, 3, 5);
imhist(sourceGrayscaleImage, 256);
title('Original Histogram');

subplot(2, 3, 6);
imhist(matchedGrayscaleImage, 256);
title('Matched Histogram');

% Confirm the matched image keeps the original size and shape.
assert(isequal(size(matchedGrayscaleImage), ...
    size(sourceGrayscaleImage)), ...
    'Histogram matching must preserve the original grayscale image dimensions.');

% Check that grayscale and color inputs produce the same result.
matchedFromGrayscaleInputs = matchGrayscaleHistogram( ...
    referenceGrayscaleImage, sourceGrayscaleImage);

assert(isequal(matchedFromGrayscaleInputs, matchedGrayscaleImage), ...
    'Color and grayscale inputs must produce the same matching result.');

referenceHistogramCounts = imhist(referenceGrayscaleImage, 256);
sourceHistogramCounts = imhist(sourceGrayscaleImage, 256);
matchedHistogramCounts = imhist(matchedGrayscaleImage, 256);

% Compute the histogram difference to measure how closely they match.
referenceCumulativeDistribution = cumsum( ...
    referenceHistogramCounts / sum(referenceHistogramCounts));

sourceCumulativeDistribution = cumsum( ...
    sourceHistogramCounts / sum(sourceHistogramCounts));

matchedCumulativeDistribution = cumsum( ...
    matchedHistogramCounts / sum(matchedHistogramCounts));

histogramDifferenceBefore = mean(abs( ...
    referenceCumulativeDistribution - sourceCumulativeDistribution));

histogramDifferenceAfter = mean(abs( ...
    referenceCumulativeDistribution - matchedCumulativeDistribution));

% Print the before and after matching values for quick review.
fprintf('Mean cumulative histogram difference before matching: %.6f\n', ...
    histogramDifferenceBefore);

fprintf('Mean cumulative histogram difference after matching: %.6f\n', ...
    histogramDifferenceAfter);

% Confirm the matched histogram still counts every output pixel.
assert(sum(matchedHistogramCounts) == numel(matchedGrayscaleImage), ...
    'The matched histogram must count every output image pixel.');


%% 7. Save the resulting images and check their saved copies.
% Save the output images into a results folder for review.
% Create the folder only if it does not already exist.

outputFolder = fullfile(pwd, 'ColorAndHistogramExplorerResults');

if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

% Place each result image in the output folder with a clear name.
resultImages = {
    originalColorImage
    hueChannel
    saturationChannel
    valueChannel
    enlargedColorImage
    croppedColorImage
    grayscaleImage
    referenceGrayscaleImage
    matchedGrayscaleImage
    };

resultFilenames = {
    'original_market_color.png'
    'market_hue_channel.png'
    'market_saturation_channel.png'
    'market_value_channel.png'
    'enlarged_market_color.png'
    'center_cropped_market_color.png'
    'original_market_grayscale.png'
    'reference_street_grayscale.png'
    'histogram_matched_market_grayscale.png'
    };

for imageNumber = 1:numel(resultImages)
    imageToSave = resultImages{imageNumber};

    % Save PNG files and reopen them to confirm the pixels match.
    if isfloat(imageToSave)
        imageToSave = im2uint8(imageToSave);
    end

    outputFilename = fullfile( ...
        outputFolder, resultFilenames{imageNumber});

    imwrite(imageToSave, outputFilename);

    savedImage = imread(outputFilename);

    assert(isequal(savedImage, imageToSave), ...
        'The saved image pixels must match the prepared output pixels.');
end

grayscaleHistogramFilename = fullfile( ...
    outputFolder, 'market_grayscale_histogram.png');

histogramComparisonFilename = fullfile( ...
    outputFolder, 'histogram_matching_comparison.png');

% Export the histogram charts as image files for the final report.
exportgraphics(grayscaleHistogramFigure, ...
    grayscaleHistogramFilename, 'Resolution', 150);

exportgraphics(histogramMatchingFigure, ...
    histogramComparisonFilename, 'Resolution', 150);

% Confirm that both saved charts were created correctly.
assert(isfile(grayscaleHistogramFilename), ...
    'The grayscale histogram chart must exist after the saving step.');

assert(isfile(histogramComparisonFilename), ...
    'The histogram comparison chart must exist after the saving step.');

% Tell the user where the finished results were saved.
fprintf('All programmed checks passed, and the results were saved.\n');
fprintf('Open this results folder to inspect the saved images:\n%s\n', ...
    outputFolder);



function [matchedGrayscaleImage, referenceGrayscaleImage, ...
    sourceGrayscaleImage] = matchGrayscaleHistogram( ...
    referenceImage, sourceImage)
% Convert both images to grayscale before matching brightness values.

referenceGrayscaleImage = convertToGrayscale(referenceImage);
sourceGrayscaleImage = convertToGrayscale(sourceImage);

referenceHistogramCounts = imhist(referenceGrayscaleImage, 256);

matchedGrayscaleImage = histeq( ...
    sourceGrayscaleImage, referenceHistogramCounts);
end


function grayscaleImage = convertToGrayscale(inputImage)
% Accept either grayscale or RGB input and return one grayscale image.

validateattributes(inputImage, {'numeric', 'logical'}, ...
    {'nonempty', 'real', 'finite', 'nonsparse'}, ...
    mfilename, 'inputImage');

if ismatrix(inputImage)
    grayscaleImage = inputImage;

elseif ndims(inputImage) == 3 && size(inputImage, 3) == 3
    grayscaleImage = rgb2gray(inputImage);

else
    error('The input must be grayscale or contain three RGB channels.');
end

% Check the numeric range before continuing with the image match.
if isfloat(grayscaleImage)
    assert(all(grayscaleImage(:) >= 0 & grayscaleImage(:) <= 1), ...
        'Decimal image values must remain between zero and one.');
end

% Use the same brightness scale for both matching inputs.
grayscaleImage = im2uint8(grayscaleImage);
end