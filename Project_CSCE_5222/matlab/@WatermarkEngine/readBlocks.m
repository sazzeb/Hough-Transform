function blocks = readBlocks(imageData, blockCount, channel)
    % Read 2-by-2 pixel blocks for the classic mode.
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
