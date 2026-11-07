function saveWithDialog(app, name)
    % Save a PNG and check that it opens with the same pixels.
    if app.PreviewOnly
        error('Watermark:Preview', ...
            'Release the strength slider to create the full image.');
    end
    defaultName = [name '.png'];
    [filename, folder] = app.chooseFile( ...
        'save', ['Save ' name], defaultName);
    if isequal(filename, 0)
        app.setStatus('Save canceled. The result is still in memory.');
        return;
    end
    [~, ~, extension] = fileparts(filename);
    if isempty(extension)
        filename = [filename '.png'];
    end
    saved = ImageStore.savePng( ...
        fullfile(folder, filename), app.Images.(name));
    app.LastSavedPath = saved;
    if strcmp(name, 'watermarked')
        app.ImagePaths.watermarked = saved;
        reopened = ImageStore.read(saved, true);
        recovered = WatermarkEngine.extract(reopened);
        app.Images.extracted = recovered.watermark;
        app.LastRecoveryVerified = recovered.verified;
        app.LastRecoveryState = app.recoveryState( ...
            recovered, app.Images.prepared);
        app.showImage('extracted', recovered.watermark);
        app.refreshEvidence();
        app.StatusCards.verification.Text = app.LastRecoveryState;
        app.StatusCards.saved.Text = 'PNG verified';
    else
        app.StatusCards.saved.Text = 'Watermark PNG saved';
    end
    if ~app.LastRecoveryVerified
        app.setStatus([ ...
            'PNG saved; watermark recovery remains approximate: ' ...
            saved]);
    else
        app.setStatus(['Saved and verified: ' saved]);
    end
end
