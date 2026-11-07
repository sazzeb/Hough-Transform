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
