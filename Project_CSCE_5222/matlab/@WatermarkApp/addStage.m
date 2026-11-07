function addStage(app, parent, name, title, detailText, index)
    card = uipanel(parent, 'BorderType', 'line', ...
        'BackgroundColor', [1 1 1]);
    card.Layout.Row = ceil(index/2);
    card.Layout.Column = mod(index-1, 2) + 1;
    layout = uigridlayout(card, [3 1]);
    layout.RowHeight = {28, '1x', 32};
    layout.Padding = [12 10 12 10];
    layout.RowSpacing = 2;
    titleLabel = uilabel(layout, 'Text', title, ...
        'FontSize', 12, 'FontWeight', 'bold', ...
        'FontColor', [38 100 53]/255);
    titleLabel.Layout.Row = 1;
    axesHandle = uiaxes(layout);
    axesHandle.Layout.Row = 2;
    axesHandle.Toolbar.Visible = 'off';
    app.StageAxes.(name) = axesHandle;
    detail = uilabel(layout, 'Text', detailText, ...
        'WordWrap', 'on', 'FontSize', 11, ...
        'FontColor', [0 0 0]);
    detail.Layout.Row = 3;
    app.StageDetails.(name) = detail;
end
