classdef ExampleGallery < handle
    % Shuffle and load the bundled example images.

    properties (SetAccess = private)
        Entries
        CatalogFolder
        Remaining = []
        LastIndex = []
    end

    methods
        function gallery = ExampleGallery(catalogPath)
            % Read the example list and check its image entries.
            if nargin == 0
                projectFolder = fileparts(fileparts(mfilename('fullpath')));
                catalogPath = fullfile(projectFolder, 'matlab', ...
                    'source', 'images', 'catalog.json');
            end

            gallery.CatalogFolder = fileparts(catalogPath);
            gallery.Entries = jsondecode(fileread(catalogPath));
            identifiers = {gallery.Entries.id};
            if numel(identifiers) < 10 || ...
                    numel(unique(identifiers)) ~= numel(identifiers)
                error('ExampleGallery:InvalidCatalog', ...
                    'The example gallery needs at least 10 unique photos.');
            end
        end

        function example = nextExample(gallery)
            % Pick an example without repeating one in the round.
            if isempty(gallery.Remaining)
                gallery.Remaining = randperm(numel(gallery.Entries));
                if ~isempty(gallery.LastIndex) && ...
                        gallery.Remaining(end) == gallery.LastIndex
                    gallery.Remaining([1 end]) = gallery.Remaining([end 1]);
                end
            end

            coverIndex = gallery.Remaining(end);
            gallery.Remaining(end) = [];
            gallery.LastIndex = coverIndex;
            watermarkIndex = mod(coverIndex - 1 + 5, ...
                numel(gallery.Entries)) + 1;
            cover = gallery.Entries(coverIndex);
            watermark = gallery.Entries(watermarkIndex);

            example = struct( ...
                'title', cover.title, ...
                'coverSource', cover.source_url, ...
                'watermarkSource', watermark.source_url, ...
                'coverPath', fullfile(gallery.CatalogFolder, ...
                    [cover.id '.jpg']), ...
                'watermarkPath', fullfile(gallery.CatalogFolder, ...
                    [watermark.id '.jpg']));
        end

        function [cover, watermark] = loadExample(~, example)
            % Load a cover and make a watermark from another photo.
            cover = ImageStore.read(example.coverPath);
            watermarkPhoto = ImageStore.read(example.watermarkPath);
            side = min(size(watermarkPhoto, 1), size(watermarkPhoto, 2));
            top = floor((size(watermarkPhoto, 1) - side)/2) + 1;
            left = floor((size(watermarkPhoto, 2) - side)/2) + 1;
            square = watermarkPhoto(top:top+side-1, ...
                left:left+side-1, :);
            watermark = imresize(rgb2gray(square), [96 96]);
        end
    end
end
