function output = writeBlocks(imageData, blocks, channel)
    % Put changed 2-by-2 blocks back into the image.
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
