function setPreviewScale(app, name, useActualPixels)
    % Switch a preview between fit and actual pixel size.
    imageData = app.Images.(name);
    if isempty(imageData)
        return;
    end

    axesHandle = app.PreviewAxes.(name);
    width = size(imageData, 2);
    height = size(imageData, 1);
    if useActualPixels
        visibleWidth = min(width, max(1, axesHandle.Position(3)));
        visibleHeight = min(height, max(1, axesHandle.Position(4)));
        xlim(axesHandle, ...
            [(width-visibleWidth)/2, (width+visibleWidth)/2] + 0.5);
        ylim(axesHandle, ...
            [(height-visibleHeight)/2, (height+visibleHeight)/2] + 0.5);
    else
        xlim(axesHandle, [0.5 width+0.5]);
        ylim(axesHandle, [0.5 height+0.5]);
    end
end
