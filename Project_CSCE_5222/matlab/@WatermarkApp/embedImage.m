function embedImage(app)
    [valid, strength, side, message] = app.settings();
    if ~valid
        error('Watermark:Option', '%s', message);
    end
    if isempty(app.Images.cover) || isempty(app.Images.watermark)
        error('Watermark:Input', ...
            'Choose an original image and an image to hide.');
    end

    result = WatermarkEngine.embed( ...
        app.Images.cover, app.Images.watermark, ...
        strength, [side side], app.selectedMode());
    recovered = WatermarkEngine.extract(result.image);
    app.Images.prepared = result.preparedWatermark;
    app.Images.watermarked = result.image;
    app.Images.extracted = recovered.watermark;
    app.LastQuality = result.psnr;
    app.LastRecoveredStrength = recovered.strength;
    app.LastRecoveryVerified = recovered.verified;
    app.LastRecoveryState = app.recoveryState( ...
        recovered, app.Images.prepared);
    app.LastSavedPath = '';
    app.PreviewOnly = false;
    app.PreviewCover = [];
    app.showImage('prepared', app.Images.prepared);
    app.showImage('watermarked', app.Images.watermarked);
    app.showImage('extracted', app.Images.extracted);
    app.refreshComparison();
    app.StatusCards.verification.Text = app.LastRecoveryState;
    app.StatusCards.saved.Text = 'Not saved';
    app.setStatus( ...
        'Created and verified. Save the watermarked PNG to keep it.');
end
