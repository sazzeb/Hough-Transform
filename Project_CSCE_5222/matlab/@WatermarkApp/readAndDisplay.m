function readAndDisplay(app, name, path)
    imageData = ImageStore.read(path, strcmp(name, 'watermarked'));
    sourceInfo = imfinfo(path);
    app.PreviewOnly = false;
    app.PreviewCover = [];
    recovered = [];
    if strcmp(name, 'watermarked')
        try
            recovered = WatermarkEngine.extract(imageData);
        catch exception
            error('Watermark:InvalidSavedPng', ...
                ['This PNG has no recoverable watermark. ' ...
                 'Select the unchanged file created by ' ...
                 'Save watermarked PNG, not the original photo ' ...
                 'or the recovered watermark. Details: %s'], ...
                exception.message);
        end
    end

    app.Images.(name) = imageData;
    app.clearEvaluation();
    app.ImagePaths.(name) = path;
    app.showImage(name, imageData);

    if strcmp(name, 'watermarked')
        app.Images.cover = [];
        app.Images.watermark = [];
        app.Images.prepared = [];
        app.ImagePaths.cover = '';
        app.ImagePaths.watermark = '';
        app.showImage('cover', []);
        app.showImage('watermark', []);
        app.showImage('prepared', []);
        app.Images.extracted = recovered.watermark;
        app.showImage('extracted', recovered.watermark);
        app.LastRecoveredStrength = recovered.strength;
        app.LastRecoveryVerified = recovered.verified;
        app.LastRecoveryState = app.recoveryState(recovered, []);
        app.LastQuality = NaN;
        app.LastSavedPath = '';
        app.StatusCards.verification.Text = app.LastRecoveryState;
        app.StatusCards.saved.Text = 'Source PNG loaded';
        if recovered.verified
            app.setStatus(sprintf( ...
                ['Recovered a %d × %d watermark from the PNG. ' ...
                'Payload checksum verified; original reference ' ...
                'is unavailable.'], ...
                size(recovered.watermark, 2), ...
                size(recovered.watermark, 1)));
        else
            app.setStatus( ...
                ['Approximate recovery: payload checksum failed. ' ...
                 'Inspect the recovered watermark before using it.']);
        end
    else
        app.Images.watermarked = [];
        app.Images.extracted = [];
        app.showImage('watermarked', []);
        app.showImage('extracted', []);
        app.StatusCards.verification.Text = 'Not checked';
        app.StatusCards.saved.Text = 'Not saved';
        app.LastSavedPath = '';
        app.LastQuality = NaN;
        app.LastRecoveredStrength = NaN;
        app.LastRecoveryVerified = false;
        app.LastRecoveryState = 'Not checked';
        if sourceInfo.Width ~= size(imageData, 2) || ...
                sourceInfo.Height ~= size(imageData, 1)
            app.setStatus(sprintf( ...
                ['Loaded %s. Resized %d × %d to %d × %d ' ...
                 'for safe processing; original file unchanged.'], ...
                name, sourceInfo.Width, sourceInfo.Height, ...
                size(imageData, 2), size(imageData, 1)));
        else
            app.setStatus(sprintf( ...
                'Loaded %s (%d × %d pixels).', ...
                name, size(imageData, 2), size(imageData, 1)));
        end
        app.refreshPrepared();
    end
    app.refreshComparison();
end
