function addStatusCard(app, parent, column, title, value, name)
    % Create a small box that shows current progress.
    card = uipanel(parent, 'BorderType', 'line', ...
        'BackgroundColor', [1 1 1]);
    card.Layout.Column = column;
    layout = uigridlayout(card, [2 1]);
    layout.RowHeight = {23, '1x'};
    layout.Padding = [12 7 12 7];
    layout.BackgroundColor = [1 1 1];
    heading = uilabel(layout, 'Text', title, ...
        'FontSize', 10, 'FontWeight', 'bold', ...
        'FontColor', [38 100 53]/255);
    heading.Layout.Row = 1;
    detail = uilabel(layout, 'Text', value, ...
        'FontSize', 12, 'FontWeight', 'bold', ...
        'FontColor', [0 0 0]);
    detail.Layout.Row = 2;
    app.StatusCards.(name) = detail;
end
