function addPreview(app, parent, name, title, row, column)
    card = uipanel(parent, 'BorderType', 'line', ...
        'BackgroundColor', [1 1 1]);
    card.Layout.Row = row;
    card.Layout.Column = column;
    app.PreviewCards.(name) = card;
    layout = uigridlayout(card, [4 1]);
    layout.RowHeight = {32, '1x', 24, 34};
    layout.RowSpacing = 4;
    layout.Padding = [10 8 10 8];
    layout.BackgroundColor = [1 1 1];

    if strcmp(name, 'comparison')
        app.ComparisonMenu = uidropdown(layout, ...
            'Items', {'Difference', 'Original', 'Watermarked'}, ...
            'Value', 'Difference', ...
            'ValueChangedFcn', @(~, ~)app.refreshComparison());
        app.ComparisonMenu.Layout.Row = 1;
    else
        heading = uilabel(layout, 'Text', title, ...
            'FontSize', 13, 'FontWeight', 'bold', ...
            'FontColor', [0 0 0]);
        heading.Layout.Row = 1;
    end

    axesHandle = uiaxes(layout);
    axesHandle.Layout.Row = 2;
    axesHandle.Toolbar.Visible = 'off';
    app.PreviewAxes.(name) = axesHandle;

    detail = uilabel(layout, ...
        'Text', 'No image yet', ...
        'FontSize', 10, 'FontColor', [0 0 0]);
    detail.Layout.Row = 3;
    app.PreviewDetails.(name) = detail;

    actions = uigridlayout(layout, [1 2]);
    actions.Layout.Row = 4;
    actions.ColumnWidth = {'1x', '1x'};
    actions.Padding = [0 0 0 0];
    actions.BackgroundColor = [1 1 1];
    uibutton(actions, 'push', 'Text', 'Fit', ...
        'ButtonPushedFcn', @(~, ~)app.setPreviewScale(name, false));
    uibutton(actions, 'push', 'Text', '100%', ...
        'ButtonPushedFcn', @(~, ~)app.setPreviewScale(name, true));
    app.showImage(name, []);
end
