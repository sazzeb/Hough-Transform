classdef WatermarkApp < handle
    %WATERMARKAPP Interactive image watermarking and recovery workspace.

    properties (Access = private)
        Window
        StatusLabel
        CapacityLabel
        ValidationLabel
        StrengthField
        StrengthSlider
        StrengthPercentLabel
        SizeField
        PresetMenu
        ModeMenu
        ComparisonMenu
        TechnicalText
        EvaluationSummary
        EvaluationDetails
        EvaluationNote
        RootPanel
        WorkspaceLayout
        RightLayout
        PreviewGrid
        StageAxes = struct()
        StageDetails = struct()
        MetricValues = struct()
        PreviewCards = struct()
        StatusCards = struct()
        Buttons = struct()
        PreviewAxes = struct()
        PreviewDetails = struct()
        Images = struct( ...
            'cover', [], 'watermark', [], 'prepared', [], ...
            'watermarked', [], 'extracted', [], 'comparison', [])
        ImagePaths = struct('cover', '', 'watermark', '', 'watermarked', '')
        LastSavedPath = ''
        LastQuality = NaN
        LastRecoveredStrength = NaN
        LastRecoveryVerified = false
        LastRecoveryState = 'Not checked'
        LastSummary = ''
        PreviewOnly = false
        PreviewCover = []
        PreviewClock = []
        Busy = false
        Gallery
    end

    methods
        function app = WatermarkApp()
            app.Gallery = ExampleGallery();
            app.Window = uifigure( ...
                'Name', 'Wavelet Watermark Studio', ...
                'WindowStyle', 'normal', ...
                'Position', [80 80 1360 860], ...
                'Color', [1 1 1], ...
                'CloseRequestFcn', @(~, ~)app.closeWindow(), ...
                'WindowKeyPressFcn', @(~, event)app.handleShortcut(event));

            app.RootPanel = uipanel(app.Window, ...
                'BorderType', 'none', ...
                'Position', [1 1 app.Window.Position(3:4)], ...
                'BackgroundColor', [1 1 1]);
            page = uigridlayout(app.RootPanel, [3 1]);
            page.RowHeight = {94, '1x', 64};
            page.ColumnWidth = {'1x'};
            page.RowSpacing = 0;
            page.Padding = [0 0 0 0];

            app.buildHeader(page);
            app.buildWorkspace(page);
            app.buildFooter(page);
            app.Window.AutoResizeChildren = 'off';
            app.Window.SizeChangedFcn = @(~, ~)app.adjustLayout();
            app.adjustLayout();
            app.refreshPrepared();
            app.refreshControls();
            app.PreviewClock = tic;
            app.setStatus('Choose two images, or select Try an example.');
        end

        function delete(app)
            if isgraphics(app.Window)
                delete(app.Window);
            end
        end
    end

    methods (Access = private)
        buildHeader(~, page)

        buildWorkspace(app, page)

        buildCreateTab(app, tab)

        buildExtractTab(app, tab)

        buildDetailsTab(app, tab)

        buildEvaluationTab(app, tab)

        buildPreviewArea(app, workspace)

        addStage(app, parent, name, title, detailText, index)

        addMetric(app, parent, index, name, title, formula)

        refreshEvidence(app)

        showStage(app, name, imageData)

        [horizontal, vertical] = haarDetails(~, imageData)

        buildFooter(app, page)

        function label = addLabel(~, parent, row, textValue, isHeading)
            label = uilabel(parent, ...
                'Text', textValue, ...
                'WordWrap', 'on', ...
                'FontSize', 11, ...
                'FontColor', [0 0 0]);
            if isHeading
                label.FontWeight = 'bold';
                label.FontColor = [38 100 53]/255;
            end
            label.Layout.Row = row;
        end

        function button = addButton(app, parent, row, name, caption, ...
                callback, isPrimary)
            button = uibutton(parent, 'push', ...
                'Text', caption, ...
                'ButtonPushedFcn', @(~, ~)callback(), ...
                'FontSize', 12, 'FontWeight', 'bold');
            button.Layout.Row = row;
            if isPrimary
                button.BackgroundColor = [38 100 53]/255;
                button.FontColor = [1 1 1];
            else
                button.BackgroundColor = [1 1 1];
                button.FontColor = [0 0 0];
            end
            app.Buttons.(name) = button;
        end

        function field = addTextSetting(app, parent, row, caption, value)
            setting = uigridlayout(parent, [1 2]);
            setting.Layout.Row = row;
            setting.ColumnWidth = {'1x', 66};
            setting.Padding = [0 0 0 0];
            setting.BackgroundColor = [1 1 1];
            app.addLabel(setting, 1, caption, false);
            field = uieditfield(setting, 'text', ...
                'Value', value, ...
                'HorizontalAlignment', 'center');
            field.Layout.Column = 2;
        end

        addStatusCard(app, parent, column, title, value, name)

        addPreview(app, parent, name, title, row, column)

        adjustLayout(app)

        showImage(app, name, imageData)

        setPreviewScale(app, name, useActualPixels)

        function settingsChanged(app)
            app.PresetMenu.Value = 'Custom';
            strength = str2double(app.StrengthField.Value);
            if isfinite(strength) && strength >= 8 && strength <= 32
                percentage = round(100 * (strength-8) / 24);
                app.StrengthSlider.Value = percentage;
                app.StrengthPercentLabel.Text = sprintf( ...
                    'Watermark strength: %d%%  •  %d/32', ...
                    percentage, round(strength));
            end
            app.invalidateResult();
            app.refreshPrepared();
            app.refreshControls();
            app.embedWhenReady();
        end

        function applyPreset(app)
            switch app.PresetMenu.Value
                case 'Subtle'
                    app.StrengthField.Value = '8';
                case 'Recommended'
                    app.StrengthField.Value = '16';
                case 'Stronger'
                    app.StrengthField.Value = '32';
            end
            app.StrengthSlider.Value = round(100 * ...
                (str2double(app.StrengthField.Value)-8) / 24);
            app.StrengthPercentLabel.Text = sprintf( ...
                'Watermark strength: %d%%  •  %s/32', ...
                round(app.StrengthSlider.Value), ...
                app.StrengthField.Value);
            app.invalidateResult();
            app.refreshPrepared();
            app.refreshControls();
            app.embedWhenReady();
        end

        function mode = selectedMode(app)
            mode = lower(app.ModeMenu.Value);
        end

        function state = recoveryState(~, recovered, prepared)
            if ~recovered.verified
                state = 'Checksum failed; approximate';
            elseif isempty(prepared)
                state = 'Verified payload CRC';
            elseif isequal(recovered.watermark, prepared)
                state = 'Verified exact';
            else
                state = 'Verified, pixels differ';
            end
        end

        function clearEvaluation(app)
            app.EvaluationSummary.Data = cell(0, 10);
            app.EvaluationDetails.Data = cell(0, 9);
            app.EvaluationNote.Text = [ ...
                'No study for this image pair yet. Exact rate counts ' ...
                'only checksum-verified, pixel-identical prepared marks.'];
        end

        runEvaluation(app)

        function updateEvaluationProgress(app, step, total)
            app.setStatus(sprintf( ...
                'Evaluating configuration %d of %d...', step, total));
            drawnow limitrate;
        end

        function invalidateResult(app)
            app.PreviewOnly = false;
            app.PreviewCover = [];
            app.Images.watermarked = [];
            app.Images.extracted = [];
            app.Images.comparison = [];
            app.LastSavedPath = '';
            app.LastQuality = NaN;
            app.LastRecoveredStrength = NaN;
            app.LastRecoveryVerified = false;
            app.LastRecoveryState = 'Not checked';
            app.showImage('watermarked', []);
            app.showImage('extracted', []);
            app.showImage('comparison', []);
            app.StatusCards.verification.Text = 'Not checked';
            app.StatusCards.saved.Text = 'Not saved';
            app.refreshEvidence();
        end

        function embedWhenReady(app)
            [valid, ~, side, ~] = app.settings();
            if valid && ~isempty(app.Images.cover) && ...
                    ~isempty(app.Images.watermark) && ...
                    side * side <= WatermarkEngine.capacityBytes( ...
                        app.Images.cover, app.selectedMode())
                app.runAction(@()app.embedImage(), ...
                    'Updating the full watermarked image...');
            end
        end

        previewStrength(app, percentage)

        function finishStrengthChange(app, percentage)
            app.StrengthSlider.Value = round(percentage);
            app.StrengthField.Value = num2str( ...
                8 + round(24 * percentage / 100));
            app.StrengthPercentLabel.Text = sprintf( ...
                'Watermark strength: %d%%  •  %s/32', ...
                round(percentage), app.StrengthField.Value);
            app.PresetMenu.Value = 'Custom';
            app.invalidateResult();
            app.refreshControls();
            app.embedWhenReady();
        end

        function [valid, strength, side, message] = settings(app)
            strength = str2double(app.StrengthField.Value);
            side = str2double(app.SizeField.Value);
            valid = isfinite(strength) && strength == floor(strength) && ...
                strength >= 8 && strength <= 32 && ...
                isfinite(side) && side == floor(side) && ...
                side >= 8 && side <= 64;
            message = '';
            if ~valid
                message = 'Enter whole numbers: strength 8–32; side 8–64.';
            end
        end

        function refreshPrepared(app)
            [valid, ~, side, ~] = app.settings();
            app.Images.prepared = [];
            if valid && ~isempty(app.Images.watermark)
                app.Images.prepared = WatermarkEngine.prepareWatermark( ...
                    app.Images.watermark, [side side]);
            end
            app.showImage('prepared', app.Images.prepared);
            app.refreshEvidence();
        end

        refreshControls(app)

        function state = onOff(~, enabled)
            state = 'off';
            if enabled
                state = 'on';
            end
        end

        function runAction(app, operation, message)
            if app.Busy
                return;
            end
            app.Busy = true;
            app.refreshControls();
            app.setStatus(message);
            app.Window.Pointer = 'watch';
            cleanup = onCleanup(@()app.finishAction());
            drawnow;
            try
                operation();
            catch exception
                app.setStatus(['Could not finish: ' exception.message]);
                uialert(app.Window, exception.message, ...
                    'Action needed', 'Icon', 'error');
            end
        end

        function finishAction(app)
            app.Busy = false;
            if isgraphics(app.Window)
                app.Window.Pointer = 'arrow';
                app.refreshControls();
            end
        end

        function setStatus(app, message)
            app.StatusLabel.Text = message;
        end

        loadWithDialog(app, name)

        readAndDisplay(app, name, path)

        embedImage(app)

        extractImage(app)

        runSample(app)

        refreshComparison(app)

        saveWithDialog(app, name)

        refreshTechnicalSummary(app)

        function copySummary(app)
            clipboard('copy', app.LastSummary);
            app.setStatus('Technical summary copied.');
        end

        function openSavedFolder(app)
            if isempty(app.LastSavedPath)
                return;
            end
            folder = fileparts(app.LastSavedPath);
            if ~javaMethod('isDesktopSupported', 'java.awt.Desktop')
                error('Watermark:Desktop', ...
                    'Opening folders is not supported on this desktop.');
            end
            desktop = javaMethod('getDesktop', 'java.awt.Desktop');
            desktop.open(javaObject('java.io.File', folder));
        end

        function [filename, folder] = chooseFile( ...
                ~, mode, title, defaultName, defaultFolder)
            % A movable native dialog stays above the visible app.
            if nargin < 4
                defaultName = '';
            end
            if nargin < 5
                defaultFolder = '';
            end
            if ~usejava('awt')
                error('Watermark:Dialog', ...
                    'The desktop file picker requires Java AWT.');
            end
            owner = javaObject('java.awt.Frame');
            ownerCleanup = onCleanup(@()owner.dispose());
            dialogMode = 0;
            if strcmp(mode, 'save')
                dialogMode = 1;
            end
            picker = javaObject( ...
                'java.awt.FileDialog', owner, title, int32(dialogMode));
            pickerCleanup = onCleanup(@()picker.dispose());
            picker.setAlwaysOnTop(true);
            if ~isempty(defaultFolder)
                picker.setDirectory(defaultFolder);
            end
            if ~isempty(defaultName)
                picker.setFile(defaultName);
            end
            picker.setVisible(true);
            selected = picker.getFile();
            if isempty(selected)
                filename = 0;
                folder = 0;
            else
                filename = char(selected);
                folder = char(picker.getDirectory());
            end
            clear pickerCleanup ownerCleanup
        end

        function handleShortcut(app, event)
            modifiers = event.Modifier;
            primaryKey = any(strcmp(modifiers, 'control')) || ...
                any(strcmp(modifiers, 'command'));
            if ~primaryKey || app.Busy
                return;
            end

            switch lower(event.Key)
                case 'o'
                    name = 'cover';
                    if any(strcmp(modifiers, 'shift'))
                        name = 'watermark';
                    end
                    app.runAction(@()app.loadWithDialog(name), ...
                        'Opening image picker...');
                case 'e'
                    app.runAction(@()app.loadWithDialog('watermarked'), ...
                        'Opening image picker...');
                case 's'
                    if ~isempty(app.Images.watermarked)
                        app.runAction( ...
                            @()app.saveWithDialog('watermarked'), ...
                            'Opening save picker...');
                    end
            end
        end

        function closeWindow(app)
            if app.Busy
                uialert(app.Window, ...
                    'Wait for the current action to finish.', ...
                    'Action in progress');
                return;
            end
            delete(app);
        end
    end
end
