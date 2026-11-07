function showStage(app, name, imageData)
    axesHandle = app.StageAxes.(name);
    cla(axesHandle);
    if isempty(imageData)
        text(axesHandle, 0.5, 0.5, 'Waiting', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 9, 'Color', [0 0 0]);
        xlim(axesHandle, [0 1]);
        ylim(axesHandle, [0 1]);
    elseif ismatrix(imageData)
        imagesc(axesHandle, imageData, [0 255]);
        colormap(axesHandle, gray(256));
        axis(axesHandle, 'image');
    else
        image(axesHandle, imageData);
        axis(axesHandle, 'image');
    end
    axis(axesHandle, 'off');
end
