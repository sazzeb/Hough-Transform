function extractImage(app)
    if isempty(app.Images.watermarked)
        error('Watermark:Input', ...
            'Choose a watermarked PNG first.');
    end
    recovered = WatermarkEngine.extract(app.Images.watermarked);
    app.Images.extracted = recovered.watermark;
    app.LastRecoveredStrength = recovered.strength;
    app.LastRecoveryVerified = recovered.verified;
    app.LastRecoveryState = app.recoveryState( ...
        recovered, app.Images.prepared);
    app.showImage('extracted', recovered.watermark);
    app.refreshEvidence();
    if recovered.verified
        app.StatusCards.verification.Text = app.LastRecoveryState;
        app.setStatus(sprintf( ...
            'Recovered a %d × %d watermark. Strength: %d.', ...
            size(recovered.watermark, 2), ...
            size(recovered.watermark, 1), recovered.strength));
    else
        app.StatusCards.verification.Text = app.LastRecoveryState;
        app.setStatus( ...
            ['Approximate recovery: payload checksum failed. ' ...
             'Inspect the recovered watermark before using it.']);
    end
end
