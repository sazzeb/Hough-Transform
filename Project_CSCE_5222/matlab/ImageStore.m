
classdef ImageStore
    properties (Constant)
        MaxWorkingPixels = 12000000
        MaxSourcePixels = 100000000
        MaxWatermarkedPixels = 24000000
    end

    methods (Static)
        function imageData = read(filename, isWatermarked)
            if nargin < 2
                isWatermarked = false;
            end

            if ~(ischar(filename) || ...
                    (isstring(filename) && isscalar(filename)))
                error('Watermark:File', ...
                    'Provide a valid image filename.');
            end

            filename = char(filename);

            if ~isfile(filename)
                error('Watermark:File', ...
                    'The selected image file does not exist.');
            end

            fileDetails = dir(filename);

            if isempty(fileDetails) || fileDetails(1).isdir
                error('Watermark:File', ...
                    'The selected path is not a valid file.');
            end

            if fileDetails(1).bytes <= 0
                error('Watermark:File', ...
                    'The selected image file is empty.');
            end

            info = imfinfo(filename);

            if numel(info) ~= 1
                error('Watermark:File', ...
                    'Use a single-frame image.');
            end

            sourcePixels = double(info.Width) * double(info.Height);

            if isWatermarked && ...
                    sourcePixels > ImageStore.MaxWatermarkedPixels
                error('Watermark:Image', ...
                    ['The selected file is %d × %d pixels (%.1f MP), ' ...
                     'above the 24 MP recovery limit. If this is your ' ...
                     'original photo, load it in Create, embed the ' ...
                     'watermark, and select the PNG saved with ' ...
                     'Save watermarked PNG. Resizing this file ' ...
                     'cannot recover a watermark.'], ...
                    info.Width, info.Height, sourcePixels/1000000);
            end

            if sourcePixels > ImageStore.MaxSourcePixels
                error('Watermark:Image', ...
                    'The source image exceeds the 100 megapixel safety limit.');
            end

            format = lower(info.Format);

            if ~any(strcmp(format, {'png', 'jpg', 'jpeg', 'bmp'}))
                error('Watermark:File', ...
                    'Supported inputs are PNG, JPEG and BMP.');
            end

            alpha = [];

            if strcmp(format, 'png')
                [raw, map, alpha] = imread(filename);
            else
                [raw, map] = imread(filename);
            end

            simpleTransparency = ...
                isfield(info, 'SimpleTransparencyData') && ...
                ~isempty(info.SimpleTransparencyData);

            if simpleTransparency && isempty(alpha)
                error('Watermark:Alpha', ...
                    ['Convert this transparency layout to an ' ...
                     '8-bit RGBA or flattened PNG first.']);
            end

            if isWatermarked
                if ~strcmp(format, 'png') || ~isempty(map) || ...
                        ~isempty(alpha) || ~isa(raw, 'uint8')

                    error('Watermark:File', ...
                        ['This file is not an opaque 8-bit grayscale ' ...
                         'or RGB PNG. Choose the exact file saved ' ...
                         'with Save watermarked PNG. An original ' ...
                         'photo or recovered watermark cannot be ' ...
                         'used for recovery.']);
                end

                imageData = raw;
            else
                if ~isa(raw, 'uint8') && ~islogical(raw)
                    error('Watermark:File', ...
                        'Convert the input to an 8-bit image before loading.');
                end

                if sourcePixels > ImageStore.MaxWorkingPixels
                    scale = sqrt( ...
                        ImageStore.MaxWorkingPixels / sourcePixels);
                    workingHeight = max(1, floor(double(info.Height) * scale));
                    workingWidth = max(1, floor(double(info.Width) * scale));

                    if isempty(map)
                        raw = imresize(raw, ...
                            [workingHeight workingWidth], 'bilinear');
                    else
                        raw = imresize(raw, ...
                            [workingHeight workingWidth], 'nearest');
                    end

                    if ~isempty(alpha)
                        alpha = imresize(alpha, ...
                            [workingHeight workingWidth], 'bilinear');
                    end
                end

                if ~isempty(map)
                    indices = double(raw) + 1;
                    colors = uint8(floor(255 * map + 0.5));

                    imageData = reshape( ...
                        colors(indices(:), :), ...
                        size(raw, 1), size(raw, 2), 3);

                elseif islogical(raw)
                    imageData = uint8(raw) * 255;

                else
                    imageData = raw;
                end

                if ~isempty(alpha)
                    if ~isa(alpha, 'uint8') || ...
                            ~isequal(size(alpha), ...
                            [size(raw, 1), size(raw, 2)])

                        error('Watermark:Alpha', ...
                            'Unsupported transparency representation.');
                    end

                    if ismatrix(imageData)
                        imageData = repmat(imageData, 1, 1, 3);
                    end

                    opacity = double(alpha);

                    for channel = 1:3
                        values = double(imageData(:, :, channel));

                        imageData(:, :, channel) = uint8(floor( ...
                            (values .* opacity + ...
                            255 * (255-opacity)) / 255 + 0.5));
                    end
                end
            end

            WatermarkEngine.validateImage(imageData);
        end

        function saved = savePng(filename, imageData)
            if ~(ischar(filename) || ...
                    (isstring(filename) && isscalar(filename)))
                error('Watermark:File', ...
                    'Provide a valid output filename.');
            end

            WatermarkEngine.validateImage(imageData);

            filename = char(filename);
            [folder, ~, extension] = fileparts(filename);

            if ~strcmpi(extension, '.png')
                error('Watermark:File', ...
                    'Output filenames must end in .png.');
            end

            if isempty(folder)
                folder = pwd;
                filename = fullfile(folder, filename);
            end

            if ~isfolder(folder)
                error('Watermark:File', ...
                    'The output directory does not exist.');
            end

            temporary = [tempname(folder) '.png'];
            temporaryCleanup = onCleanup( ...
                @()ImageStore.deleteIfExists(temporary));

            imwrite(imageData, temporary, 'png');
            reloaded = ImageStore.read(temporary, true);

            if ~isequal(imageData, reloaded)
                error('Watermark:File', ...
                    'PNG verification failed; the output was not replaced.');
            end

            [moved, message] = movefile(temporary, filename, 'f');

            if ~moved
                error('Watermark:File', ...
                    'Could not save PNG: %s', message);
            end

            saved = filename;
        end
    end

    methods (Static, Access = private)
        function deleteIfExists(filename)
            if isfile(filename)
                delete(filename);
            end
        end
    end
end
