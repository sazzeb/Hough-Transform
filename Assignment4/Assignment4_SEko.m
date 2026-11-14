%% Fourier and Spatial Image Filtering
% Compare Fourier high-pass filtering with an equivalent spatial filter.
% Requires Image Processing Toolbox and MATLAB R2024b+ for the image display.
%
% This script and its reusable local functions form the complete project.
% Edit imageFilename to use an installed sample or your own image file.
% Examples: 'cameraman.tif', 'coins.png', 'rice.png', and 'moon.tif'.
%
% The centered rectangular mask removes a frequency when its horizontal
% and vertical components are both within the cutoff frequency.
% Circular boundaries give the Fourier and spatial filters the same behavior.
% Signed filtered values are preserved when computing the similarity score.


%% Processing settings

imageFilename = 'cameraman.tif';

cutoffFrequency = 0.08;

showFigures = true;
runSelfChecks = true;


%% Read the image and complete the filtering tasks.
% All intermediate results are kept in a structure for further inspection.

imageFilteringResults = createImageFilteringResults( ...
    imageFilename, cutoffFrequency, false);

[originalImage, reconstructedImage, ...
    spatiallyFilteredImage, similarityScore] = ...
    getImageResults(imageFilteringResults);

printProcessingSummary(imageFilteringResults);


%% Check the filtering functions and the current image results.

if runSelfChecks
    selfCheckReport = checkImageFilteringFunctions();
end

assert(imageFilteringResults.comparisonMetrics.matchesWithinTolerance, ...
    'The Fourier and spatial filtering results must agree.');


%% Display the original image, Fourier matrices, and filtering results.

if showFigures
    resultFigure = displayProcessingResults(imageFilteringResults);
end


%% Local functions
% These functions accept other image files and numeric image arrays.

function imageResults = createImageFilteringResults( ...
    imageSource, cutoffFrequency, showFigures)
% Read one image, apply the filters, and return a structure of results.

    %% Processing settings

    if nargin < 1
        imageSource = "cameraman.tif";
    end
    if nargin < 2
        cutoffFrequency = 0.08;
    end

    if nargin < 3
        showFigures = true;
    end

    validateattributes(cutoffFrequency, {'numeric'}, ...
        {'real', 'finite', 'scalar', '>', 0, '<=', 0.5}, ...
        mfilename, 'cutoffFrequency');
    validateattributes(showFigures, {'logical'}, {'scalar'}, ...
        mfilename, 'showFigures');

    if isempty(ver('images'))
        error('FourierImageFiltering:MissingToolbox', ...
            'Image Processing Toolbox is required.');
    end

    imageResults = struct();
    imageResults.cutoffFrequency = double(cutoffFrequency);

    %% Task 1: Read an image and prepare grayscale values.

    [imageResults.originalImage, imageResults.sourceDescription] = ...
        readImageSource(imageSource);
    imageResults = processImageTasks(imageResults);

    if showFigures
        printProcessingSummary(imageResults);
        displayProcessingResults(imageResults);
    end
end


function [originalImage, reconstructedImage, ...
    spatiallyFilteredImage, similarityScore] = ...
    getImageResults(imageResults)
% Return the image arrays and similarity score to the caller.

    originalImage = imageResults.originalImage;
    reconstructedImage = imageResults.reconstructedImage;
    spatiallyFilteredImage = imageResults.spatiallyFilteredImage;
    similarityScore = imageResults.similarityScore;
end


function printProcessingSummary(imageResults)
% Report agreement using the original signed filtering results.

    fprintf('\nFOURIER AND SPATIAL IMAGE FILTERING\n');
    fprintf('Source: %s\n', imageResults.sourceDescription);

    fprintf('Image size: %d x %d pixels\n', ...
        size(imageResults.originalImage, 1), ...
        size(imageResults.originalImage, 2));
    fprintf('Rectangular low-frequency cutoff: %.4f cycles/pixel\n', ...
        imageResults.cutoffFrequency);
    fprintf('Removed Fourier coefficients: %d of %d\n', ...
        nnz(~imageResults.highPassMask), ...
        numel(imageResults.highPassMask));
    fprintf('Structural similarity score (identical = 1): %.12f\n', ...
        imageResults.similarityScore);
    fprintf('Root mean square error: %.3e\n', ...
        imageResults.comparisonMetrics.rootMeanSquareError);
    fprintf('Maximum absolute error: %.3e\n', ...
        imageResults.comparisonMetrics.maximumAbsoluteError);
    fprintf('Agreement within %.3e: %d (1 = pass)\n', ...
        imageResults.comparisonMetrics.comparisonTolerance, ...
        imageResults.comparisonMetrics.matchesWithinTolerance);
end


function figureHandle = displayProcessingResults(imageResults)
% Display each task in a labeled panel for easy comparison.

    if exist('imageshow', 'file') == 0
        error('FourierImageFiltering:DisplayUnavailable', ...
            ['This display requires imageshow (MATLAB R2024b+). ' ...
             'Use showFigures=false to compute without a display.']);
    end

    figureHandle = uifigure('Name', 'Fourier and Spatial Image Filtering', ...
        'Position', [80, 80, 1360, 780]);
    figureLayout = uigridlayout(figureHandle, [3, 4]);
    figureLayout.RowHeight = {48, '1x', '1x'};
    similarityScoreLabel = uilabel(figureLayout, 'FontSize', 15, ...
        'HorizontalAlignment', 'center', ...
        'Text', sprintf( ...
        ['Structural similarity = %.12f   |   ' ...
         'Root mean square error = %.3e'], ...
        imageResults.similarityScore, ...
        imageResults.comparisonMetrics.rootMeanSquareError));
    similarityScoreLabel.Layout.Row = 1;
    similarityScoreLabel.Layout.Column = [1, 4];

    differenceImage = abs(imageResults.spatiallyFilteredImage ...
        - imageResults.reconstructedImage);

    maximumFilteredMagnitude = max([ ...
        abs(imageResults.reconstructedImage(:)); ...
        abs(imageResults.spatiallyFilteredImage(:)); eps]);

    maximumKernelMagnitude = max( ...
        max(abs(imageResults.spatialKernel(:))), eps);

    displayImages = {
        imageResults.originalImage
        imageResults.fourierMagnitudeImage
        imageResults.fourierPhaseMatrix
        double(imageResults.highPassMask)
        imageResults.reconstructedImage
        imageResults.spatiallyFilteredImage
        differenceImage
        fftshift(imageResults.spatialKernel)
    };

    imageTitles = {
        'Figure 1: Original Grayscale Image'
        'Figure 2: Fourier Logarithmic Magnitude'
        'Figure 3: Fourier Phase in Radians'
        'Figure 4: Retained Frequency Components'
        'Figure 5: Reconstructed Image'
        'Figure 6: Spatially Filtered Image'
        'Figure 7: Absolute Pixel Difference'
        'Figure 8: Centered Spatial Filter'
    };

    displayRanges = {
        [0, 1]
        [0, max(imageResults.fourierMagnitudeImage(:)) + eps]
        [-pi, pi]
        [0, 1]
        [-maximumFilteredMagnitude, maximumFilteredMagnitude]
        [-maximumFilteredMagnitude, maximumFilteredMagnitude]
        [0, max(differenceImage(:)) + eps]
        [-maximumKernelMagnitude, maximumKernelMagnitude]
    };

    for imageIndex = 1:numel(displayImages)
        imageViewer = viewer2d(figureLayout);
        imageViewer.Layout.Row = 2 + floor((imageIndex - 1) / 4);
        imageViewer.Layout.Column = 1 + mod(imageIndex - 1, 4);

        if imageIndex == 3
            imageColormap = hsv(256);
        else
            imageColormap = gray(256);
        end

        imageshow(displayImages{imageIndex}, 'Parent', imageViewer, ...
            'DisplayRange', displayRanges{imageIndex}, ...
            'Colormap', imageColormap);

        title(imageViewer, imageTitles{imageIndex});
    end

    drawnow;
end


function imageResults = processImageTasks(imageResults)
% Complete the numerical tasks without changing display intensities.

    %% Task 2: Apply the two-dimensional Fourier transform.

    imageResults.fourierCoefficients = ...
        fftshift(fft2(imageResults.originalImage));

    %% Task 3: Prepare the frequency magnitude and phase images.
    % Logarithmic magnitude makes weaker frequencies visible.

    imageResults.fourierMagnitudeImage = ...
        log1p(abs(imageResults.fourierCoefficients));

    imageResults.fourierPhaseMatrix = ...
        angle(imageResults.fourierCoefficients);

    %% Task 4: Remove the low-frequency Fourier coefficients.
    % Frequency coordinates work for odd and even image dimensions.

    [rowCount, columnCount] = size(imageResults.originalImage);

    rowFrequencies = ...
        (-floor(rowCount / 2):ceil(rowCount / 2) - 1) / rowCount;

    columnFrequencies = ...
        (-floor(columnCount / 2):ceil(columnCount / 2) - 1) / columnCount;

    lowPassRowMask = ...
        abs(rowFrequencies) <= imageResults.cutoffFrequency;

    lowPassColumnMask = ...
        abs(columnFrequencies) <= imageResults.cutoffFrequency;

    imageResults.highPassMask = ...
        ~(lowPassRowMask(:) & lowPassColumnMask);

    imageResults.filteredFourierCoefficients = ...
        imageResults.fourierCoefficients .* imageResults.highPassMask;

    %% Task 5: Reconstruct the image from the filtered coefficients.
    % Preserve negative values because this is a high-pass response.

    complexReconstruction = ...
        ifft2(ifftshift(imageResults.filteredFourierCoefficients));

    imageResults.reconstructedImage = real(complexReconstruction);

    %% Task 6: Construct and apply the equivalent spatial filter.
    % The high-pass kernel equals an impulse minus a low-pass kernel.
    % Inverse transforms construct the kernels; spatial convolution
    % applies them independently to the original image.

    verticalLowPassKernel = ...
        real(ifft(ifftshift(double(lowPassRowMask)))).';

    horizontalLowPassKernel = ...
        real(ifft(ifftshift(double(lowPassColumnMask))));

    imageResults.spatialKernel = ...
        -(verticalLowPassKernel * horizontalLowPassKernel);

    imageResults.spatialKernel(1, 1) = ...
        imageResults.spatialKernel(1, 1) + 1;

    lowPassFilteredImage = ...
        applyCircularSpatialConvolution( ...
        imageResults.originalImage, ...
        verticalLowPassKernel, horizontalLowPassKernel);

    imageResults.spatiallyFilteredImage = ...
        imageResults.originalImage - lowPassFilteredImage;

    %% Task 7: Compute the similarity score and numerical errors.
    % Use one shared shift and intensity range for both signed images.
    % Do not clip them or normalize them separately before comparison.

    sharedMinimumIntensity = min([ ...
        imageResults.reconstructedImage(:); ...
        imageResults.spatiallyFilteredImage(:); 0]);

    sharedMaximumIntensity = max([ ...
        imageResults.reconstructedImage(:); ...
        imageResults.spatiallyFilteredImage(:); 1]);

    imageResults.similarityScore = ssim( ...
        imageResults.spatiallyFilteredImage - sharedMinimumIntensity, ...
        imageResults.reconstructedImage - sharedMinimumIntensity, ...
        'DynamicRange', sharedMaximumIntensity - sharedMinimumIntensity);

    pixelDifferences = imageResults.spatiallyFilteredImage ...
        - imageResults.reconstructedImage;

    comparisonTolerance = ...
        1e-10 * max(1, max(abs(imageResults.originalImage(:))));

    imageResults.comparisonMetrics = struct( ...
        'structuralSimilarityIndex', imageResults.similarityScore, ...
        'rootMeanSquareError', sqrt(mean(pixelDifferences(:).^2)), ...
        'maximumAbsoluteError', max(abs(pixelDifferences(:))), ...
        'comparisonTolerance', comparisonTolerance, ...
        'matchesWithinTolerance', ...
            max(abs(pixelDifferences(:))) <= comparisonTolerance, ...
        'maximumImaginaryResidual', ...
            max(abs(imag(complexReconstruction(:)))));
end


function [grayscaleImage, sourceDescription] = ...
    readImageSource(imageSource)
% Read the first frame and prepare normalized grayscale values.
% Transparency is ignored so the stored color values are preserved.

    if ischar(imageSource) ...
            || (isstring(imageSource) && isscalar(imageSource))

        if isempty(imageSource) || strlength(string(imageSource)) == 0
            error('FourierImageFiltering:InvalidSource', ...
                'Image filename cannot be empty.');
        end

        % Request alpha explicitly so PNG reading does not composite
        % stored colors against its default background.
        [imageData, colorMap, ~] = imread(imageSource);
        sourceDescription = char(imageSource);

        if ~isempty(colorMap)
            imageData = ind2gray(imageData, colorMap);
        end

    else
        imageData = imageSource;
        sourceDescription = 'Provided image array';
    end

    validateattributes(imageData, ...
        {'uint8', 'uint16', 'single', 'double', 'logical'}, ...
        {'nonempty', 'real', 'finite', 'nonsparse'}, mfilename, 'imageSource');

    if ndims(imageData) > 3 || ~ismember(size(imageData, 3), [1, 3]) ...
            || size(imageData, 1) < 2 || size(imageData, 2) < 2
        error('FourierImageFiltering:InvalidImageShape', ...
            ['Use a grayscale matrix or a three-channel color image. ' ...
             'The height and width must each be at least two pixels.']);
    end

    imageData = im2double(imageData);

    if any(imageData(:) < 0 | imageData(:) > 1)
        error('FourierImageFiltering:InvalidImageRange', ...
            'Floating-point images must contain values in [0,1].');
    end

    grayscaleImage = im2gray(imageData);
end


function filteredImage = applyCircularSpatialConvolution( ...
    imageData, verticalLowPassKernel, horizontalLowPassKernel)
% Convolve in the spatial domain and wrap the boundary contributions.
% Both kernels have zero lag at their first element. This convention
% avoids shifting the result when an image dimension is even.

    [rowCount, columnCount] = size(imageData);

    horizontalConvolution = ...
        conv2(imageData, horizontalLowPassKernel, 'full');

    horizontalFilteredImage = horizontalConvolution(:, 1:columnCount);

    horizontalFilteredImage(:, 1:columnCount - 1) = ...
        horizontalFilteredImage(:, 1:columnCount - 1) ...
        + horizontalConvolution(:, columnCount + 1:end);

    verticalConvolution = ...
        conv2(verticalLowPassKernel, horizontalFilteredImage, 'full');

    filteredImage = verticalConvolution(1:rowCount, :);

    filteredImage(1:rowCount - 1, :) = filteredImage(1:rowCount - 1, :) ...
        + verticalConvolution(rowCount + 1:end, :);
end


function testReport = checkImageFilteringFunctions()
%CHECKIMAGEFILTERINGFUNCTIONS Test filter agreement, expected behavior, and inputs.
% These checks do not open figures or change the random number state.

    [columnCoordinates, rowCoordinates] = meshgrid(0:17, 0:14);

    texturedTestImage = (sin(0.73 * rowCoordinates) ...
        .* cos(0.41 * columnCoordinates) + 1) / 2;

    impulseTestImage = zeros(16, 18);
    impulseTestImage(1, 1) = 1;

    redGreenBlueTestImage = cat(3, texturedTestImage, ...
        texturedTestImage.^2, sqrt(texturedTestImage));

    testImages = {
        texturedTestImage
        texturedTestImage(1:14, :)
        texturedTestImage(:, 1:17)
        texturedTestImage(1:14, 1:17)
        zeros(12)
        ones(13, 16)
        impulseTestImage
        redGreenBlueTestImage
        uint8(round(255 * texturedTestImage))
        uint16(round(65535 * texturedTestImage))
        single(texturedTestImage)
        texturedTestImage > 0.5
        [0, 1; 1, 0]
        texturedTestImage
    };

    testNames = [
        "Odd-even dimensions"
        "Even-even dimensions"
        "Odd-odd dimensions"
        "Even-odd dimensions"
        "Zero image"
        "Constant image"
        "Impulse response"
        "Red, green, and blue conversion"
        "Unsigned eight-bit input"
        "Unsigned sixteen-bit input"
        "Single precision input"
        "Logical input"
        "Smallest image"
        "Remove all frequencies"
    ];

    testCutoffFrequencies = repmat(0.12, numel(testImages), 1);
    testCutoffFrequencies(end) = 0.5;
    maximumAbsoluteErrors = zeros(numel(testImages), 1);
    similarityScores = zeros(numel(testImages), 1);

    for testIndex = 1:numel(testImages)
        testResults = createImageFilteringResults( ...
            testImages{testIndex}, testCutoffFrequencies(testIndex), false);

        assert(testResults.comparisonMetrics.matchesWithinTolerance, ...
            'Spatial/Fourier mismatch: %s', testNames(testIndex));

        assert(isfinite(testResults.similarityScore) && ...
            abs(testResults.similarityScore - 1) < 1e-9, ...
            'Structural similarity must be one: %s', testNames(testIndex));

        removedCoefficients = testResults.filteredFourierCoefficients( ...
            ~testResults.highPassMask);

        assert(all(removedCoefficients == 0), ...
            'Removed Fourier coefficients must be exactly zero.');

        assert(abs(sum(testResults.spatialKernel(:))) < 1e-10, ...
            'A high-pass kernel must have zero gain at zero frequency.');

        assert(abs(mean(testResults.reconstructedImage(:))) < 1e-10, ...
            'Removing the zero-frequency term must produce zero mean.');

        assert( ...
            testResults.comparisonMetrics.maximumImaginaryResidual < 1e-10, ...
            'The symmetric mask must preserve a real reconstruction.');

        if testIndex == 5 || testIndex == 6 ...
                || testIndex == numel(testImages)

            assert(max(abs(testResults.reconstructedImage(:))) < 1e-10, ...
                'Constant inputs/all-stop masks must produce zero.');
        elseif testIndex == 7
            impulseResponseDifference = testResults.reconstructedImage ...
                - testResults.spatialKernel;

            assert(max(abs(impulseResponseDifference(:))) < 1e-10, ...
                'The impulse response must equal the spatial kernel.');

        elseif testIndex == 8
            expectedGrayscaleImage = im2gray(redGreenBlueTestImage);

            assert(isequal( ...
                testResults.originalImage, expectedGrayscaleImage), ...
                'Color input must convert to grayscale correctly.');
        end

        maximumAbsoluteErrors(testIndex) = ...
            testResults.comparisonMetrics.maximumAbsoluteError;

        similarityScores(testIndex) = testResults.similarityScore;
    end

    % Known sinusoids independently verify pass/stop behavior.
    [horizontalCoordinates, verticalCoordinates] = meshgrid(0:31, 0:23);

    lowFrequencyPattern = 0.2 * cos(2 * pi * horizontalCoordinates / 32);

    highFrequencyPattern = 0.2 * cos(2 * pi ...
        * (10 * horizontalCoordinates / 32 + 8 * verticalCoordinates / 24));

    frequencyPatternResults = createImageFilteringResults( ...
        0.5 + lowFrequencyPattern + highFrequencyPattern, 0.10, false);

    frequencyPatternDifference = ...
        frequencyPatternResults.reconstructedImage - highFrequencyPattern;

    assert(max(abs(frequencyPatternDifference(:))) < 1e-10, ...
        'Reject the low-frequency pattern and preserve the high one.');

    % Compare separable application with an independent, explicit
    % 2-D sum of shifted pixels on a small non-square image.
    smallImageResults = createImageFilteringResults( ...
        texturedTestImage(1:5, 1:6), 0.25, false);

    directConvolutionImage = zeros(size(smallImageResults.originalImage));

    for rowLag = 0:4
        for columnLag = 0:5
            directConvolutionImage = directConvolutionImage + ...
                smallImageResults.spatialKernel(rowLag + 1, columnLag + 1) ...
                * circshift(smallImageResults.originalImage, ...
                [rowLag, columnLag]);
        end
    end
    directConvolutionDifference = directConvolutionImage ...
        - smallImageResults.spatiallyFilteredImage;

    assert(max(abs(directConvolutionDifference(:))) < 1e-10, ...
        'Separable filtering must equal full 2-D spatial convolution.');

    invalidInputFunctions = {
        @() createImageFilteringResults([], 0.1, false)
        @() createImageFilteringResults(NaN(4), 0.1, false)
        @() createImageFilteringResults(Inf(4), 0.1, false)
        @() createImageFilteringResults(ones(4) * 2, 0.1, false)
        @() createImageFilteringResults(zeros(4, 4, 2), 0.1, false)
        @() createImageFilteringResults(ones(1, 4), 0.1, false)
        @() createImageFilteringResults(ones(4), 0, false)
        @() createImageFilteringResults(ones(4), 0.6, false)
        @() createImageFilteringResults(ones(4), NaN, false)
        @() createImageFilteringResults(ones(4), [0.1, 0.2], false)
    };

    for invalidInputIndex = 1:numel(invalidInputFunctions)
        inputWasRejected = false;

        try
            invalidInputFunctions{invalidInputIndex}();
        catch
            inputWasRejected = true;
        end

        assert(inputWasRejected, ...
            'Invalid input %d was accepted.', invalidInputIndex);
    end

    testReport = table(testNames, maximumAbsoluteErrors, similarityScores, ...
        'VariableNames', {'TestCase', 'MaximumAbsoluteError', ...
        'StructuralSimilarityIndex'});

    disp(testReport);

    fprintf(['Passed: %d image cases, frequency rejection, ' ...
        'direct spatial convolution, and %d invalid inputs.\n'], ...
        numel(testImages), numel(invalidInputFunctions));
end
