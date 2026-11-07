function buildFooter(app, page)
    % Show the app status at the bottom of the window.
    footer = uipanel(page, 'BorderType', 'none', ...
        'BackgroundColor', [0 0 0]);
    footer.Layout.Row = 3;
    layout = uigridlayout(footer, [1 1]);
    layout.Padding = [24 8 24 8];
    layout.BackgroundColor = [0 0 0];
    app.StatusLabel = uilabel(layout, ...
        'Text', '', 'WordWrap', 'on', ...
        'FontSize', 12, 'FontColor', [1 1 1]);
end
