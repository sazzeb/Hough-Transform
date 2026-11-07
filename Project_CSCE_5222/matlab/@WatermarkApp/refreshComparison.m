function refreshComparison(app)
    % Show the original, marked, or difference image.
    compared = [];
    original = app.Images.cover;
    if app.PreviewOnly
        original = app.PreviewCover;
    end
    if ~isempty(app.Images.cover) && ...
            ~isempty(app.Images.watermarked)
        switch app.ComparisonMenu.Value
            case 'Original'
                compared = original;
            case 'Watermarked'
                compared = app.Images.watermarked;
            otherwise
                difference = abs(double(original) - ...
                    double(app.Images.watermarked));
                if ndims(difference) == 3
                    difference = max(difference, [], 3);
                end
                compared = uint8(min(255, 4*difference));
        end
    end
    app.Images.comparison = compared;
    app.showImage('comparison', compared);
    if ~isempty(compared) && ...
            strcmp(app.ComparisonMenu.Value, 'Difference')
        app.PreviewDetails.comparison.Text = ...
            'Difference amplified 4× for display';
    end
    app.refreshEvidence();
end
