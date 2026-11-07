function loadWithDialog(app, name)
    % Ask the user to choose an image file.
    suggestedName = '';
    suggestedFolder = '';
    dialogTitle = ['Choose ' name];
    if strcmp(name, 'watermarked')
        dialogTitle = 'Open saved watermarked PNG';
        recentPath = app.LastSavedPath;
        if ~isfile(recentPath)
            recentPath = app.ImagePaths.watermarked;
        end
        if isfile(recentPath)
            [suggestedFolder, baseName, extension] = ...
                fileparts(recentPath);
            suggestedName = [baseName extension];
        end
    end
    [filename, folder] = app.chooseFile('open', ...
        dialogTitle, suggestedName, ...
        suggestedFolder);
    if isequal(filename, 0)
        app.setStatus('Image selection canceled.');
        return;
    end
    app.readAndDisplay(name, fullfile(folder, filename));
end
