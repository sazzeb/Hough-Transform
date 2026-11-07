function runSample(app)
    % Load a shuffled example and create its watermark.
    example = app.Gallery.nextExample();
    [app.Images.cover, app.Images.watermark] = ...
        app.Gallery.loadExample(example);
    app.clearEvaluation();
    app.ImagePaths.cover = example.coverPath;
    app.ImagePaths.watermark = example.watermarkPath;
    app.StrengthField.Value = '16';
    app.StrengthSlider.Value = 33;
    app.StrengthPercentLabel.Text = ...
        'Watermark strength: 33%  •  16/32';
    app.SizeField.Value = '32';
    app.PresetMenu.Value = 'Recommended';
    app.showImage('cover', app.Images.cover);
    app.showImage('watermark', app.Images.watermark);
    app.embedImage();
    app.setStatus(sprintf( ...
        ['Example: %s. Exact recovery passed. Compare the ' ...
         'images, then save the watermarked PNG if desired.'], ...
        example.title));
end
