function refreshEvidence(app)
    % Update process images and scores for the current result.
    if isempty(fieldnames(app.StageAxes))
        return;
    end
    original = app.Images.cover;
    if app.PreviewOnly
        original = app.PreviewCover;
    end
    app.showStage('source', app.Images.cover);
    app.showStage('input', app.Images.watermark);
    app.showStage('gray', app.Images.prepared);
    app.showStage('decoded', app.Images.extracted);
    app.showStage('haar', []);
    app.showStage('changed', []);

    if ~isempty(original)
        [horizontal, vertical] = app.haarDetails(original);
        magnitude = sqrt(horizontal.^2 + vertical.^2);
        app.showStage('haar', uint8(min(255, 2*magnitude)));
        if ~isempty(app.Images.watermarked) && ...
                isequal(size(original), size(app.Images.watermarked))
            [markedHorizontal, markedVertical] = ...
                app.haarDetails(app.Images.watermarked);
            coefficientChange = sqrt( ...
                (horizontal-markedHorizontal).^2 + ...
                (vertical-markedVertical).^2);
            app.showStage('changed', ...
                uint8(min(255, 4*coefficientChange)));
        end
    end

    app.MetricValues.psnr.Text = 'Need both images';
    app.MetricValues.ssim.Text = 'Need both images';
    app.MetricValues.ber.Text = 'Need both marks';
    app.MetricValues.ncc.Text = 'Need both marks';
    if isempty(original) && ~isempty(app.Images.watermarked)
        app.MetricValues.psnr.Text = 'Reference unavailable';
        app.MetricValues.ssim.Text = 'Reference unavailable';
    end
    if isempty(app.Images.prepared) && ...
            ~isempty(app.Images.extracted)
        app.MetricValues.ber.Text = 'Reference unavailable';
        app.MetricValues.ncc.Text = 'Reference unavailable';
    end
    if ~isempty(original) && ...
            ~isempty(app.Images.watermarked) && ...
            isequal(size(original), size(app.Images.watermarked))
        quality = WatermarkEngine.psnr( ...
            original, app.Images.watermarked);
        structure = WatermarkEngine.ssim( ...
            original, app.Images.watermarked);
        app.MetricValues.psnr.Text = sprintf('%.2f dB', quality);
        app.MetricValues.ssim.Text = sprintf('%.4f', structure);
    end
    if ~isempty(app.Images.prepared) && ...
            ~isempty(app.Images.extracted) && ...
            isequal(size(app.Images.prepared), ...
                size(app.Images.extracted))
        bitRate = WatermarkEngine.bitErrorRate( ...
            app.Images.prepared, app.Images.extracted);
        correlation = WatermarkEngine.normalizedCorrelation( ...
            app.Images.prepared, app.Images.extracted);
        app.MetricValues.ber.Text = sprintf('%.3f%%', 100*bitRate);
        if isfinite(correlation)
            app.MetricValues.ncc.Text = ...
                sprintf('%.5f', correlation);
        else
            app.MetricValues.ncc.Text = 'Undefined';
        end
    end
end
