function adjustLayout(app)
    app.RootPanel.Position = [1 1 app.Window.Position(3:4)];
    if isempty(app.PreviewGrid) || ...
            ~isgraphics(app.PreviewGrid)
        return;
    end

    names = {'cover', 'watermark', 'prepared', ...
        'watermarked', 'extracted', 'comparison'};
    if app.Window.Position(3) < 1080
        app.WorkspaceLayout.ColumnWidth = {300, '1x'};
    else
        app.WorkspaceLayout.ColumnWidth = {340, '1x'};
    end
    app.RightLayout.RowHeight = ...
        {78, 27, 1100, 270, 55, 27, 1280};
    app.PreviewGrid.RowHeight = {420, 420, 420};
    app.PreviewGrid.ColumnWidth = {'1x', '1x'};

    for index = 1:numel(names)
        card = app.PreviewCards.(names{index});
        card.Layout.Row = ceil(index/2);
        card.Layout.Column = mod(index-1, 2) + 1;
    end
end
