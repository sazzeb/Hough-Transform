function previewStrength(app, percentage)
    if app.Busy
        return;
    end
    percentage = round(percentage);
    strength = 8 + round(24 * percentage / 100);
    app.StrengthField.Value = num2str(strength);
    app.StrengthPercentLabel.Text = sprintf( ...
        'Watermark strength: %d%%  •  %d/32', ...
        percentage, strength);
    app.PresetMenu.Value = 'Custom';
    if isempty(app.Images.cover) || isempty(app.Images.watermark)
        return;
    end
    if ~app.PreviewOnly
        app.invalidateResult();
    end
    app.PreviewOnly = true;
    app.refreshControls();
    if ~isempty(app.PreviewClock) && toc(app.PreviewClock) < 0.25
        return;
    end
    app.PreviewClock = tic;
    [valid, ~, side, ~] = app.settings();
    if ~valid
        return;
    end
    cover = app.Images.cover;
    cropHeight = min(size(cover, 1), 640);
    cropWidth = min(size(cover, 2), 640);
    crop = cover(1:cropHeight, 1:cropWidth, :);
    if side * side > WatermarkEngine.capacityBytes( ...
            crop, app.selectedMode())
        app.setStatus( ...
            'This setting needs a larger cover image.');
        return;
    end
    try
        preview = WatermarkEngine.embed( ...
            crop, app.Images.watermark, strength, ...
            [side side], app.selectedMode());
        app.PreviewOnly = true;
        app.PreviewCover = crop;
        app.Images.watermarked = preview.image;
        recoveredPreview = WatermarkEngine.extract(preview.image);
        app.Images.extracted = recoveredPreview.watermark;
        app.LastQuality = preview.psnr;
        app.LastSavedPath = '';
        app.showImage('watermarked', preview.image);
        app.showImage('extracted', recoveredPreview.watermark);
        app.refreshComparison();
        app.PreviewDetails.watermarked.Text = sprintf( ...
            'Live crop preview • %d%%', percentage);
        app.StatusCards.verification.Text = 'Live preview';
        app.StatusCards.saved.Text = 'Not saved';
        app.setStatus(sprintf( ...
            'Live %d%% preview • %.2f dB PSNR. Release to create full image.', ...
            percentage, preview.psnr));
        app.refreshControls();
    catch exception
        app.setStatus(['Preview unavailable: ' exception.message]);
    end
end
