function watermark = sampleWatermark()
% Make the small grayscale logo used in the sample workflow.
    watermark = repmat(uint8(245), 96, 96);
    watermark(5:92, 5:92) = 232;
    watermark(5:8, 5:92) = 25;
    watermark(89:92, 5:92) = 25;
    watermark(5:92, 5:8) = 25;
    watermark(5:92, 89:92) = 25;

    [columns, rows] = meshgrid(1:96, 1:96);
    points = [15 24; 27 72; 48 39; 69 72; 81 24];

    for segment = 1:size(points, 1)-1
        startPoint = points(segment, :);
        endPoint = points(segment+1, :);
        direction = endPoint - startPoint;

        fraction = ((columns-startPoint(1))*direction(1) + ...
            (rows-startPoint(2))*direction(2)) / sum(direction.^2);

        fraction = min(1, max(0, fraction));
        nearestColumn = startPoint(1) + fraction*direction(1);
        nearestRow = startPoint(2) + fraction*direction(2);
        distanceSquared = (columns-nearestColumn).^2 + ...
            (rows-nearestRow).^2;

        watermark(distanceSquared <= 25) = 20;
    end
end
