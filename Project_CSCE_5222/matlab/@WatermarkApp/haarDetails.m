function [horizontal, vertical] = haarDetails(~, imageData)
    % Get the horizontal and vertical Haar detail values.
    values = double(imageData);
    if ndims(values) == 3
        values = 0.299*values(:,:,1) + ...
            0.587*values(:,:,2) + 0.114*values(:,:,3);
    end
    height = 2*floor(min(512, size(values, 1))/2);
    width = 2*floor(min(512, size(values, 2))/2);
    a = values(1:2:height, 1:2:width);
    b = values(1:2:height, 2:2:width);
    c = values(2:2:height, 1:2:width);
    d = values(2:2:height, 2:2:width);
    horizontal = (a-b+c-d)/2;
    vertical = (a+b-c-d)/2;
end
