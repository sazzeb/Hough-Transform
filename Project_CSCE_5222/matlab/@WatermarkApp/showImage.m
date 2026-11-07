function showImage(app, name, imageData)
    axesHandle = app.PreviewAxes.(name);
    cla(axesHandle);

    if isempty(imageData)
        text(axesHandle, 0.5, 0.5, 'No image yet', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 11, 'Color', [0 0 0]);
        xlim(axesHandle, [0 1]);
        ylim(axesHandle, [0 1]);
        app.PreviewDetails.(name).Text = 'No image yet';
    else
        if ismatrix(imageData)
            imagesc(axesHandle, imageData, [0 255]);
            colormap(axesHandle, gray(256));
        else
            image(axesHandle, imageData);
        end
        axis(axesHandle, 'image');
        app.PreviewDetails.(name).Text = sprintf( ...
            '%d × %d px', size(imageData, 2), size(imageData, 1));
    end
    axis(axesHandle, 'off');
end
