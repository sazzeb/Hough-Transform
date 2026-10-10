
%% Assignment 3: Straight Line Detection Using Hough Transform
% This program detects straight lines using length and width settings.
% The detected lines are displayed on the original image.

clear;
clc;
close all;

imageFilename = 'nature.jpg';

minimumLineLength = 80;
requiredLineWidth = 8;

runSelfChecks = true;

requiredFunctions = {
    'edge'
    'hough'
    'houghpeaks'
    'houghlines'
    'imshow'
};

for functionIndex = 1:numel(requiredFunctions)
    functionName = requiredFunctions{functionIndex};

    if exist(functionName, 'file') == 0
        error('Assignment3:MissingToolbox', ...
            'The required MATLAB function "%s" is unavailable.', ...
            functionName);
    end
end


%% Task 1: Read an image into the MATLAB workspace.
% Find the image in the same folder as this script.

projectFolder = fileparts(mfilename('fullpath'));

if isempty(projectFolder)
    projectFolder = pwd;
end

imagePath = fullfile(projectFolder, imageFilename);

if ~isfile(imagePath)
    error('Assignment3:MissingImage', ...
        ['Cannot find the image: %s\n' ...
         'Place the image beside the script or update imageFilename.'], ...
        imagePath);
end

[originalImage, imageMap] = imread(imagePath);

if ~isempty(imageMap)
    originalImage = ind2rgb(originalImage, imageMap);
end

grayscaleImage = prepareGrayscaleImage(originalImage);

[imageHeight, imageWidth] = size(grayscaleImage);

fprintf('\nASSIGNMENT 3: HOUGH LINE DETECTION\n');
fprintf('Image: %s\n', imageFilename);
fprintf('Image size: %d x %d pixels\n', imageHeight, imageWidth);
fprintf('Minimum line length: %.1f pixels\n', minimumLineLength);
fprintf('Requested line width: %.1f pixels\n', requiredLineWidth);


%% Task 2: Detect straight lines using a minimum length.
% The Hough transform finds possible lines from image edges.
% Only lines that meet the requested length are returned.

[lengthOnlyLines, edgeImage, houghMatrix, ...
    thetaValues, rhoValues] = detectLinesByLength( ...
    grayscaleImage, minimumLineLength);

fprintf('\nTASK 2: LENGTH DETECTION\n');
fprintf('Lines meeting the minimum length: %d\n', ...
    numel(lengthOnlyLines));

for lineIndex = 1:numel(lengthOnlyLines)
    fprintf('Line %d: length = %.2f pixels\n', ...
        lineIndex, lengthOnlyLines(lineIndex).length);
end


%% Task 3: Detect straight lines using width and length.
% Two parallel edges can mark the sides of a thick line.
% Their distance gives an estimate of the line width.

[widthMatchedLines, widthEdgeImage] = detectLinesByWidth( ...
    grayscaleImage, minimumLineLength, requiredLineWidth);

fprintf('\nTASK 3: LENGTH AND WIDTH DETECTION\n');
fprintf('Lines matching both settings: %d\n', ...
    numel(widthMatchedLines));

for lineIndex = 1:numel(widthMatchedLines)
    fprintf('Line %d: length = %.2f, width = %.2f pixels\n', ...
        lineIndex, ...
        widthMatchedLines(lineIndex).length, ...
        widthMatchedLines(lineIndex).width);
end


%% Task 4: Test the detection functions.
% Use a simple test image with a known line size.
% This check does not create an image file.

if runSelfChecks
    checkLineDetectionFunctions();
end

assert(isequal(size(edgeImage), size(grayscaleImage)), ...
    'The edge map must match the image size.');

assert(isequal(size(widthEdgeImage), size(grayscaleImage)), ...
    'The width edge map must match the image size.');

if ~isempty(lengthOnlyLines)
    assert(all([lengthOnlyLines.length] >= minimumLineLength), ...
        'A detected line is shorter than the minimum length.');
end

if ~isempty(widthMatchedLines)
    measuredLengths = [widthMatchedLines.length];
    measuredWidths = [widthMatchedLines.width];

    widthTolerance = max(1.5, requiredLineWidth * 0.25);

    assert(all(measuredLengths >= minimumLineLength), ...
        'A width-matched line is too short.');

    assert(all(abs(measuredWidths - requiredLineWidth) ...
        <= widthTolerance + 1e-9), ...
        'A detected line does not match the requested width.');
end


%% Task 5: Visualize the detected straight lines.
% Compare the original image, edge map, and Hough results.

figure( ...
    'Name', 'Assignment 3: Hough Line Detection', ...
    'NumberTitle', 'off', ...
    'Color', 'white', ...
    'Position', [100, 100, 1250, 760]);

subplot(2, 3, 1);
imshow(originalImage);
title('Figure 1: Original Image');

subplot(2, 3, 2);
imshow(grayscaleImage);
title('Figure 2: Grayscale Image');

subplot(2, 3, 3);
imshow(edgeImage);
title('Figure 3: Canny Edge Detection');

subplot(2, 3, 4);
imagesc(thetaValues, rhoValues, houghMatrix);
axis on;
axis normal;
colormap(gca, hot);
colorbar;
xlabel('Theta (degrees)');
ylabel('Rho (pixels)');
title('Figure 4: Hough Transform');

subplot(2, 3, 5);
showDetectedLines( ...
    originalImage, lengthOnlyLines, [1, 0.25, 0.10], false);
title(sprintf('Figure 5: Lines >= %.0f Pixels', ...
    minimumLineLength));

subplot(2, 3, 6);
showDetectedLines( ...
    originalImage, widthMatchedLines, [0.10, 0.85, 0.30], true);
title(sprintf('Figure 6: Length >= %.0f, Width = %.0f', ...
    minimumLineLength, requiredLineWidth));

drawnow;

fprintf('\nVISUALIZATION COMPLETE\n');

if isempty(widthMatchedLines)
    fprintf(['No lines matched the requested length and width.\n' ...
             'Try different settings or another image.\n']);
end

fprintf('All image and result validation checks passed.\n');


%% Local functions
% The functions below are reusable with other images.


function grayscaleImage = prepareGrayscaleImage(inputImage)
% Convert RGB or grayscale images into grayscale values.

    validateattributes(inputImage, {'numeric', 'logical'}, ...
        {'nonempty', 'real', 'finite', 'nonsparse'});

    if ismatrix(inputImage)
        grayscaleImage = im2double(inputImage);

    elseif ndims(inputImage) == 3 && size(inputImage, 3) == 3
        grayscaleImage = rgb2gray(im2double(inputImage));

    else
        error('Assignment3:UnsupportedImage', ...
            'The input image must be grayscale or RGB.');
    end

    if any(grayscaleImage(:) < 0 | grayscaleImage(:) > 1)
        error('Assignment3:InvalidPixels', ...
            'Image values must be between zero and one.');
    end
end


function [detectedLines, edgeImage, houghMatrix, ...
    thetaValues, rhoValues] = detectLinesByLength( ...
    inputImage, minimumLength)
% Detect straight lines that meet the minimum length.

    validateattributes(minimumLength, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'positive'});

    grayscaleImage = prepareGrayscaleImage(inputImage);

    [candidates, edgeImage, houghMatrix, ...
        thetaValues, rhoValues] = findHoughCandidates( ...
        grayscaleImage, minimumLength);

    detectedLines = struct( ...
        'point1', {}, ...
        'point2', {}, ...
        'length', {});

    for candidateIndex = 1:numel(candidates)
        firstPoint = double(candidates(candidateIndex).point1);
        secondPoint = double(candidates(candidateIndex).point2);

        segmentLength = norm(secondPoint - firstPoint);

        if segmentLength < minimumLength
            continue;
        end

        newLine.point1 = firstPoint;
        newLine.point2 = secondPoint;
        newLine.length = segmentLength;

        detectedLines(end + 1) = newLine;
    end
end


function [detectedLines, edgeImage] = detectLinesByWidth( ...
    inputImage, minimumLength, requiredWidth)
% Find thick lines using their length and two parallel edges.
% The two edges must surround a consistent bright or dark region.

    validateattributes(minimumLength, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'positive'});

    validateattributes(requiredWidth, {'numeric'}, ...
        {'scalar', 'real', 'finite', '>=', 2});

    grayscaleImage = prepareGrayscaleImage(inputImage);

    [candidates, edgeImage] = findHoughCandidates( ...
        grayscaleImage, minimumLength);

    detectedLines = struct( ...
        'point1', {}, ...
        'point2', {}, ...
        'length', {}, ...
        'width', {});

    widthTolerance = max(1.5, requiredWidth * 0.25);
    minimumParallelScore = cosd(4);

    contrastThreshold = max( ...
        0.035, 0.12 * std(grayscaleImage(:)));

    for firstIndex = 1:numel(candidates)

        firstPoints = double([
            candidates(firstIndex).point1
            candidates(firstIndex).point2
        ]);

        firstVector = firstPoints(2, :) - firstPoints(1, :);
        firstLength = norm(firstVector);

        if firstLength < minimumLength
            continue;
        end

        direction = firstVector / firstLength;
        normal = [-direction(2), direction(1)];

        firstRho = dot(firstPoints(1, :), normal);
        firstPosition = firstPoints * direction';

        for secondIndex = firstIndex + 1:numel(candidates)

            secondPoints = double([
                candidates(secondIndex).point1
                candidates(secondIndex).point2
            ]);

            secondVector = ...
                secondPoints(2, :) - secondPoints(1, :);

            secondLength = norm(secondVector);

            if secondLength < minimumLength
                continue;
            end

            secondDirection = secondVector / secondLength;

            parallelScore = abs(dot(direction, secondDirection));

            if parallelScore < minimumParallelScore
                continue;
            end

            secondRho = dot(secondPoints(1, :), normal);
            measuredWidth = abs(secondRho - firstRho);

            if abs(measuredWidth - requiredWidth) > widthTolerance
                continue;
            end

            secondPosition = secondPoints * direction';

            overlapStart = max( ...
                min(firstPosition), min(secondPosition));

            overlapEnd = min( ...
                max(firstPosition), max(secondPosition));

            sharedLength = overlapEnd - overlapStart;

            if sharedLength < minimumLength
                continue;
            end

            lowerRho = min(firstRho, secondRho);
            upperRho = max(firstRho, secondRho);

            isRealLine = checkLineContrast( ...
                grayscaleImage, direction, normal, ...
                overlapStart, overlapEnd, ...
                lowerRho, upperRho, ...
                requiredWidth, contrastThreshold);

            if ~isRealLine
                continue;
            end

            middleRho = (firstRho + secondRho) / 2;

            middleStart = ...
                overlapStart * direction + middleRho * normal;

            middleEnd = ...
                overlapEnd * direction + middleRho * normal;

            newLine.point1 = middleStart;
            newLine.point2 = middleEnd;
            newLine.length = norm(middleEnd - middleStart);
            newLine.width = measuredWidth;

            detectedLines(end + 1) = newLine;
        end
    end

    detectedLines = removeDuplicateLines( ...
        detectedLines, requiredWidth);
end


function [candidateLines, edgeImage, houghMatrix, ...
    thetaValues, rhoValues] = findHoughCandidates( ...
    grayscaleImage, minimumLength)
% Find possible line segments using the Hough transform.
% Keep nearby parallel peaks so thick lines can be measured.

    edgeImage = edge(grayscaleImage, 'Canny');

    [houghMatrix, thetaValues, rhoValues] = hough( ...
        edgeImage, ...
        'Theta', -90:0.5:89.5, ...
        'RhoResolution', 1);

    candidateLines = struct('point1', {}, 'point2', {});

    highestVote = max(houghMatrix(:));

    if highestVote == 0
        return;
    end

    maximumPeaks = min( ...
        180, max(20, ceil(nnz(edgeImage) / 45)));

    peakThreshold = max( ...
        3, ceil(0.20 * highestVote));

    peaks = houghpeaks( ...
        houghMatrix, maximumPeaks, ...
        'Threshold', peakThreshold, ...
        'NHoodSize', [3, 5], ...
        'Theta', thetaValues);

    if isempty(peaks)
        return;
    end

    gapSize = max(3, round(minimumLength * 0.12));
    candidateMinimumLength = max(3, floor(minimumLength * 0.55));

    candidateLines = houghlines( ...
        edgeImage, thetaValues, rhoValues, peaks, ...
        'FillGap', gapSize, ...
        'MinLength', candidateMinimumLength);
end


function isMatchingLine = checkLineContrast( ...
    grayscaleImage, direction, normal, ...
    overlapStart, overlapEnd, ...
    lowerRho, upperRho, requiredWidth, contrastThreshold)
% Check that both sides of the line differ from its center.
% This helps reject unrelated parallel edges.

    isMatchingLine = false;

    sampleCount = 9;
    sampleMargin = min(3, (overlapEnd - overlapStart) * 0.05);

    samplePositions = linspace( ...
        overlapStart + sampleMargin, ...
        overlapEnd - sampleMargin, ...
        sampleCount)';

    middleRho = (lowerRho + upperRho) / 2;
    outsideDistance = max(2, requiredWidth * 0.35);

    centerPoints = ...
        samplePositions * direction + middleRho * normal;

    firstOutsidePoints = ...
        samplePositions * direction + ...
        (lowerRho - outsideDistance) * normal;

    secondOutsidePoints = ...
        samplePositions * direction + ...
        (upperRho + outsideDistance) * normal;

    centerValues = interp2( ...
        grayscaleImage, ...
        centerPoints(:, 1), centerPoints(:, 2), ...
        'linear', NaN);

    firstOutsideValues = interp2( ...
        grayscaleImage, ...
        firstOutsidePoints(:, 1), firstOutsidePoints(:, 2), ...
        'linear', NaN);

    secondOutsideValues = interp2( ...
        grayscaleImage, ...
        secondOutsidePoints(:, 1), secondOutsidePoints(:, 2), ...
        'linear', NaN);

    validSamples = ...
        isfinite(centerValues) & ...
        isfinite(firstOutsideValues) & ...
        isfinite(secondOutsideValues);

    if nnz(validSamples) < 5
        return;
    end

    firstDifference = median( ...
        centerValues(validSamples) - ...
        firstOutsideValues(validSamples));

    secondDifference = median( ...
        centerValues(validSamples) - ...
        secondOutsideValues(validSamples));

    brightLine = ...
        firstDifference > contrastThreshold && ...
        secondDifference > contrastThreshold;

    darkLine = ...
        firstDifference < -contrastThreshold && ...
        secondDifference < -contrastThreshold;

    isMatchingLine = brightLine || darkLine;
end


function uniqueLines = removeDuplicateLines(detectedLines, lineWidth)
% Remove repeated detections of the same thick line.

    uniqueLines = detectedLines([]);

    if isempty(detectedLines)
        return;
    end

    [~, sortedIndices] = sort( ...
        [detectedLines.length], 'descend');

    for sortedIndex = 1:numel(sortedIndices)

        currentLine = detectedLines(sortedIndices(sortedIndex));

        currentPoints = [
            currentLine.point1
            currentLine.point2
        ];

        currentDirection = ...
            (currentPoints(2, :) - currentPoints(1, :)) ...
            / currentLine.length;

        currentNormal = ...
            [-currentDirection(2), currentDirection(1)];

        currentCenter = mean(currentPoints, 1);
        currentPositions = currentPoints * currentDirection';

        isDuplicate = false;

        for savedIndex = 1:numel(uniqueLines)

            savedLine = uniqueLines(savedIndex);

            savedPoints = [
                savedLine.point1
                savedLine.point2
            ];

            savedDirection = ...
                (savedPoints(2, :) - savedPoints(1, :)) ...
                / savedLine.length;

            if abs(dot(currentDirection, savedDirection)) < cosd(4)
                continue;
            end

            savedCenter = mean(savedPoints, 1);

            separation = abs(dot( ...
                currentCenter - savedCenter, currentNormal));

            savedPositions = savedPoints * currentDirection';

            sharedLength = max(0, ...
                min(max(currentPositions), max(savedPositions)) ...
                - max(min(currentPositions), min(savedPositions)));

            shorterLength = min( ...
                currentLine.length, savedLine.length);

            if separation <= max(2, lineWidth * 0.25) && ...
                    sharedLength >= 0.70 * shorterLength

                isDuplicate = true;
                break;
            end
        end

        if ~isDuplicate
            uniqueLines(end + 1) = currentLine;
        end
    end
end


function showDetectedLines( ...
    backgroundImage, detectedLines, displayColor, displayWidth)
% Draw the detected lines over the original image.

    imshow(backgroundImage);
    hold on;

    if isempty(detectedLines)
        text(0.5, 0.5, 'No matching lines detected', ...
            'Units', 'normalized', ...
            'HorizontalAlignment', 'center', ...
            'Color', 'yellow', ...
            'FontSize', 11, ...
            'FontWeight', 'bold');

        hold off;
        return;
    end

    for lineIndex = 1:numel(detectedLines)

        currentLine = detectedLines(lineIndex);

        endpoints = [
            currentLine.point1
            currentLine.point2
        ];

        plot( ...
            endpoints(:, 1), endpoints(:, 2), ...
            '-', 'Color', displayColor, 'LineWidth', 2);

        plot( ...
            endpoints(1, 1), endpoints(1, 2), ...
            'o', 'Color', displayColor, ...
            'MarkerFaceColor', displayColor, ...
            'MarkerSize', 4);

        if displayWidth && lineIndex <= 15

            lineCenter = mean(endpoints, 1);

            text( ...
                lineCenter(1), lineCenter(2), ...
                sprintf('%.1f px', currentLine.width), ...
                'Color', 'yellow', ...
                'FontSize', 9, ...
                'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'black', ...
                'Margin', 2);
        end
    end

    hold off;
end


function checkLineDetectionFunctions()
% Test both functions using a line with a known size.

    testImage = ones(220, 320);

    testImage(70:79, 30:290) = 0.10;

    testMinimumLength = 100;
    testLineWidth = 10;

    [testLengthLines, testEdges] = detectLinesByLength( ...
        testImage, testMinimumLength);

    [testWidthLines, ~] = detectLinesByWidth( ...
        testImage, testMinimumLength, testLineWidth);

    assert(any(testEdges(:)), ...
        'The test image must produce detectable edges.');

    assert(~isempty(testLengthLines), ...
        'The length detector did not find the test line.');

    assert(~isempty(testWidthLines), ...
        'The width detector did not find the test line.');

    assert(all([testLengthLines.length] >= testMinimumLength), ...
        'The length detector returned a line that is too short.');

    assert(all([testWidthLines.length] >= testMinimumLength), ...
        'The width detector returned a line that is too short.');

    testTolerance = max(1.5, testLineWidth * 0.25);

    assert(all(abs([testWidthLines.width] - testLineWidth) ...
        <= testTolerance + 1e-9), ...
        'The detected test width is outside the allowed range.');

    fprintf('\nTEST RESULTS\n');
    fprintf('Synthetic image: 220 x 320 pixels\n');
    fprintf('Expected width: 10 pixels\n');
    fprintf('Minimum length: 100 pixels\n');
    fprintf('Length detections: %d\n', numel(testLengthLines));
    fprintf('Width detections: %d\n', numel(testWidthLines));
    fprintf('Synthetic line checks passed.\n');
end
