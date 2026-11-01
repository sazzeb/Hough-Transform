classdef WatermarkApp < handle
    %WATERMARKAPP Interactive image watermarking and recovery workspace.

    properties (Access = private)
        Window
        StatusLabel
        CapacityLabel
        ValidationLabel
        StrengthField
        SizeField
        PresetMenu
        ComparisonMenu
        TechnicalText
        RootPanel
        WorkspaceLayout
        PreviewGrid
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
        LastSummary = ''
        Busy = false
    end

    methods
        function app = WatermarkApp()
            app.Window = uifigure( ...
                'Name', 'Wavelet Watermark Studio', ...
                'WindowStyle', 'normal', ...
                'Position', [80 80 1180 760], ...
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
            app.setStatus('Choose two images, or select Try an example.');
        end

        function delete(app)
            if isgraphics(app.Window)
                delete(app.Window);
            end
        end
    end

    methods (Access = private)
        function buildHeader(~, page)
            header = uipanel(page, 'BorderType', 'none', ...
                'BackgroundColor', [38 100 53]/255);
            header.Layout.Row = 1;

            layout = uigridlayout(header, [2 1]);
            layout.RowHeight = {22, 40};
            layout.Padding = [28 12 28 12];
            layout.RowSpacing = 2;
            layout.BackgroundColor = [38 100 53]/255;

            eyebrow = uilabel(layout, ...
                'Text', 'IMAGE LAB  /  WAVELET WATERMARKING', ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', [1 1 1]);
            eyebrow.Layout.Row = 1;

            title = uilabel(layout, ...
                'Text', 'Hide an image. Recover it. See every step.', ...
                'FontSize', 23, 'FontWeight', 'bold', ...
                'FontColor', [1 1 1]);
            title.Layout.Row = 2;
        end

        function buildWorkspace(app, page)
            workspace = uigridlayout(page, [1 2]);
            app.WorkspaceLayout = workspace;
            workspace.Layout.Row = 2;
            workspace.ColumnWidth = {340, '1x'};
            workspace.ColumnSpacing = 14;
            workspace.Padding = [16 14 16 14];
            workspace.BackgroundColor = [1 1 1];

            tabs = uitabgroup(workspace);
            tabs.Layout.Column = 1;

            createTab = uitab(tabs, 'Title', 'Create');
            extractTab = uitab(tabs, 'Title', 'Extract');
            detailsTab = uitab(tabs, 'Title', 'Details');

            app.buildCreateTab(createTab);
            app.buildExtractTab(extractTab);
            app.buildDetailsTab(detailsTab);
            app.buildPreviewArea(workspace);
        end

        function buildCreateTab(app, tab)
            layout = uigridlayout(tab, [16 1]);
            layout.Scrollable = 'on';
            layout.RowHeight = {30, 37, 24, 37, 37, 57, 24, ...
                34, 34, 34, 55, 42, 40, 35, 35, '1x'};
            layout.RowSpacing = 5;
            layout.Padding = [14 15 14 12];
            layout.BackgroundColor = [1 1 1];

            app.addLabel(layout, 1, 'CREATE A WATERMARKED IMAGE', true);
            app.addButton(layout, 2, 'sample', 'Try an example', ...
                @()app.runAction(@()app.runSample(), ...
                'Preparing the example...'), false);
            app.addLabel(layout, 3, '1  CHOOSE TWO IMAGES', true);
            app.addButton(layout, 4, 'cover', ...
                'Choose original image', ...
                @()app.runAction(@()app.loadWithDialog('cover'), ...
                'Opening image picker...'), false);
            app.addButton(layout, 5, 'watermark', ...
                'Choose image to hide', ...
                @()app.runAction(@()app.loadWithDialog('watermark'), ...
                'Opening image picker...'), false);
            app.addLabel(layout, 6, ...
                ['The hidden image is resized to a square and converted ' ...
                 'to grayscale. Save the result as PNG to recover it.'], false);

            app.addLabel(layout, 7, '2  CHOOSE THE SETTINGS', true);
            app.PresetMenu = uidropdown(layout, ...
                'Items', {'Recommended', 'Subtle', 'Stronger', 'Custom'}, ...
                'Value', 'Recommended', ...
                'ValueChangedFcn', @(~, ~)app.applyPreset());
            app.PresetMenu.Layout.Row = 8;

            app.StrengthField = app.addTextSetting( ...
                layout, 9, 'Strength (8–32)', '16');
            app.SizeField = app.addTextSetting( ...
                layout, 10, 'Hidden image side (8–64)', '32');
            app.StrengthField.ValueChangedFcn = ...
                @(~, ~)app.settingsChanged();
            app.SizeField.ValueChangedFcn = ...
                @(~, ~)app.settingsChanged();

            app.CapacityLabel = app.addLabel(layout, 11, ...
                'Capacity: choose an original image.', false);
            app.ValidationLabel = app.addLabel(layout, 12, ...
                'Choose both images to continue.', false);

            app.addButton(layout, 13, 'embed', ...
                'Create watermarked image', ...
                @()app.runAction(@()app.embedImage(), ...
                'Creating and verifying the image...'), true);
            app.addButton(layout, 14, 'saveImage', ...
                'Save watermarked PNG', ...
                @()app.runAction(@()app.saveWithDialog('watermarked'), ...
                'Opening save picker...'), false);
            app.addButton(layout, 15, 'saveMark', ...
                'Save recovered watermark', ...
                @()app.runAction(@()app.saveWithDialog('extracted'), ...
                'Opening save picker...'), false);
            app.addLabel(layout, 16, ...
                ['Lower strength changes fewer pixels; higher strength ' ...
                 'changes more. The result stays in memory until saved.'], false);
        end

        function buildExtractTab(app, tab)
            layout = uigridlayout(tab, [8 1]);
            layout.Scrollable = 'on';
            layout.RowHeight = {30, 66, 42, 42, 44, 60, 40, '1x'};
            layout.RowSpacing = 8;
            layout.Padding = [14 16 14 12];
            layout.BackgroundColor = [1 1 1];

            app.addLabel(layout, 1, 'RECOVER AN EXISTING WATERMARK', true);
            app.addLabel(layout, 2, ...
                ['Select an unchanged PNG made by this app. ' ...
                 'The stored strength and watermark size are read ' ...
                 'from the image automatically.'], false);
            app.addButton(layout, 3, 'watermarked', ...
                'Choose watermarked PNG', ...
                @()app.runAction(@()app.loadWithDialog('watermarked'), ...
                'Opening image picker...'), true);
            app.addButton(layout, 4, 'extract', ...
                'Recover watermark again', ...
                @()app.runAction(@()app.extractImage(), ...
                'Checking and recovering the watermark...'), false);
            app.addButton(layout, 5, 'extractSave', ...
                'Save recovered watermark', ...
                @()app.runAction(@()app.saveWithDialog('extracted'), ...
                'Opening save picker...'), false);
            app.addLabel(layout, 6, ...
                ['A modified or JPEG-compressed image may fail ' ...
                 'verification. Keep the original saved PNG.'], false);
            app.addLabel(layout, 7, ...
                'Recovery checks the embedded header and image data.', false);
        end

        function buildDetailsTab(app, tab)
            layout = uigridlayout(tab, [6 1]);
            layout.RowHeight = {30, 55, '1x', 38, 38, 40};
            layout.RowSpacing = 8;
            layout.Padding = [14 16 14 12];
            layout.BackgroundColor = [1 1 1];

            app.addLabel(layout, 1, 'TECHNICAL DETAILS', true);
            app.addLabel(layout, 2, ...
                ['Capacity, strength, verification, quality, ' ...
                 'and saved paths appear here.'], false);
            app.TechnicalText = uitextarea(layout, ...
                'Editable', 'off', ...
                'FontName', 'Menlo', ...
                'FontSize', 11, ...
                'BackgroundColor', [1 1 1], ...
                'FontColor', [0 0 0]);
            app.TechnicalText.Layout.Row = 3;
            app.addButton(layout, 4, 'copySummary', ...
                'Copy technical summary', ...
                @()app.runAction(@()app.copySummary(), ...
                'Copying summary...'), false);
            app.addButton(layout, 5, 'openFolder', ...
                'Open saved file location', ...
                @()app.runAction(@()app.openSavedFolder(), ...
                'Opening saved location...'), false);
            app.addLabel(layout, 6, ...
                'PSNR measures image change; higher is closer.', false);
        end

        function buildPreviewArea(app, workspace)
            right = uigridlayout(workspace, [2 1]);
            right.Layout.Column = 2;
            right.RowHeight = {88, '1x'};
            right.RowSpacing = 12;
            right.Padding = [0 0 0 0];
            right.BackgroundColor = [1 1 1];

            statuses = uigridlayout(right, [1 3]);
            statuses.Layout.Row = 1;
            statuses.ColumnWidth = {'1x', '1x', '1x'};
            statuses.ColumnSpacing = 10;
            statuses.Padding = [0 0 0 0];
            app.addStatusCard(statuses, 1, 'INPUT IMAGES', '0 of 2 ready', ...
                'inputs');
            app.addStatusCard(statuses, 2, 'RECOVERY', 'Not checked', ...
                'verification');
            app.addStatusCard(statuses, 3, 'SAVED RESULT', 'Not saved', ...
                'saved');

            previews = uigridlayout(right, [2 3]);
            app.PreviewGrid = previews;
            previews.Layout.Row = 2;
            previews.RowHeight = {'1x', '1x'};
            previews.ColumnWidth = {'1x', '1x', '1x'};
            previews.RowSpacing = 10;
            previews.ColumnSpacing = 10;
            previews.Padding = [0 0 0 0];
            previews.Scrollable = 'on';
            previews.BackgroundColor = [1 1 1];

            app.addPreview(previews, 'cover', 'Original image', 1, 1);
            app.addPreview(previews, 'watermark', ...
                'Image to hide', 1, 2);
            app.addPreview(previews, 'prepared', ...
                'Prepared grayscale image', 1, 3);
            app.addPreview(previews, 'watermarked', ...
                'Watermarked image', 2, 1);
            app.addPreview(previews, 'extracted', ...
                'Recovered watermark', 2, 2);
            app.addPreview(previews, 'comparison', ...
                'Compare images', 2, 3);
        end

        function buildFooter(app, page)
            footer = uipanel(page, 'BorderType', 'none', ...
                'BackgroundColor', [0 0 0]);
            footer.Layout.Row = 3;
            layout = uigridlayout(footer, [1 1]);
            layout.Padding = [24 8 24 8];
            layout.BackgroundColor = [0 0 0];
            app.StatusLabel = uilabel(layout, ...
                'Text', '', 'WordWrap', 'on', ...
                'FontSize', 12, 'FontColor', [1 1 1]);
        end

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

        function addStatusCard(app, parent, column, title, value, name)
            card = uipanel(parent, 'BorderType', 'line', ...
                'BackgroundColor', [1 1 1]);
            card.Layout.Column = column;
            layout = uigridlayout(card, [2 1]);
            layout.RowHeight = {23, '1x'};
            layout.Padding = [12 7 12 7];
            layout.BackgroundColor = [1 1 1];
            heading = uilabel(layout, 'Text', title, ...
                'FontSize', 10, 'FontWeight', 'bold', ...
                'FontColor', [38 100 53]/255);
            heading.Layout.Row = 1;
            detail = uilabel(layout, 'Text', value, ...
                'FontSize', 12, 'FontWeight', 'bold', ...
                'FontColor', [0 0 0]);
            detail.Layout.Row = 2;
            app.StatusCards.(name) = detail;
        end

        function addPreview(app, parent, name, title, row, column)
            card = uipanel(parent, 'BorderType', 'line', ...
                'BackgroundColor', [1 1 1]);
            card.Layout.Row = row;
            card.Layout.Column = column;
            app.PreviewCards.(name) = card;
            layout = uigridlayout(card, [4 1]);
            layout.RowHeight = {28, '1x', 20, 29};
            layout.RowSpacing = 4;
            layout.Padding = [10 8 10 8];
            layout.BackgroundColor = [1 1 1];

            if strcmp(name, 'comparison')
                app.ComparisonMenu = uidropdown(layout, ...
                    'Items', {'Difference', 'Original', 'Watermarked'}, ...
                    'Value', 'Difference', ...
                    'ValueChangedFcn', @(~, ~)app.refreshComparison());
                app.ComparisonMenu.Layout.Row = 1;
            else
                heading = uilabel(layout, 'Text', title, ...
                    'FontSize', 12, 'FontWeight', 'bold', ...
                    'FontColor', [0 0 0]);
                heading.Layout.Row = 1;
            end

            axesHandle = uiaxes(layout);
            axesHandle.Layout.Row = 2;
            axesHandle.Toolbar.Visible = 'on';
            app.PreviewAxes.(name) = axesHandle;

            detail = uilabel(layout, ...
                'Text', 'No image yet', ...
                'FontSize', 10, 'FontColor', [0 0 0]);
            detail.Layout.Row = 3;
            app.PreviewDetails.(name) = detail;

            actions = uigridlayout(layout, [1 2]);
            actions.Layout.Row = 4;
            actions.ColumnWidth = {'1x', '1x'};
            actions.Padding = [0 0 0 0];
            actions.BackgroundColor = [1 1 1];
            uibutton(actions, 'push', 'Text', 'Fit', ...
                'ButtonPushedFcn', @(~, ~)app.setPreviewScale(name, false));
            uibutton(actions, 'push', 'Text', '100%', ...
                'ButtonPushedFcn', @(~, ~)app.setPreviewScale(name, true));
            app.showImage(name, []);
        end

        function adjustLayout(app)
            app.RootPanel.Position = [1 1 app.Window.Position(3:4)];
            if isempty(app.PreviewGrid) || ...
                    ~isgraphics(app.PreviewGrid)
                return;
            end

            names = {'cover', 'watermark', 'prepared', ...
                'watermarked', 'extracted', 'comparison'};
            if app.Window.Position(3) < 1080
                app.WorkspaceLayout.ColumnWidth = {300, '1x'};
                app.PreviewGrid.RowHeight = {220, 220, 220};
                app.PreviewGrid.ColumnWidth = {'1x', '1x'};
                columns = 2;
            else
                app.WorkspaceLayout.ColumnWidth = {340, '1x'};
                app.PreviewGrid.RowHeight = {'1x', '1x'};
                app.PreviewGrid.ColumnWidth = {'1x', '1x', '1x'};
                columns = 3;
            end

            for index = 1:numel(names)
                card = app.PreviewCards.(names{index});
                card.Layout.Row = ceil(index/columns);
                card.Layout.Column = mod(index-1, columns) + 1;
            end
        end

        function showImage(app, name, imageData)
            axesHandle = app.PreviewAxes.(name);
            cla(axesHandle);

            if isempty(imageData)
                text(axesHandle, 0.5, 0.5, 'No image yet', ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'middle', ...
                    'FontSize', 11, 'Color', [0 0 0]);
                xlim(axesHandle, [0 1]);
                ylim(axesHandle, [0 1]);
                app.PreviewDetails.(name).Text = 'No image yet';
            else
                if ismatrix(imageData)
                    imagesc(axesHandle, imageData, [0 255]);
                    colormap(axesHandle, gray(256));
                else
                    image(axesHandle, imageData);
                end
                axis(axesHandle, 'image');
                app.PreviewDetails.(name).Text = sprintf( ...
                    '%d × %d px', size(imageData, 2), size(imageData, 1));
            end
            axis(axesHandle, 'off');
        end

        function setPreviewScale(app, name, useActualPixels)
            imageData = app.Images.(name);
            if isempty(imageData)
                return;
            end

            axesHandle = app.PreviewAxes.(name);
            width = size(imageData, 2);
            height = size(imageData, 1);
            if useActualPixels
                visibleWidth = min(width, max(1, axesHandle.Position(3)));
                visibleHeight = min(height, max(1, axesHandle.Position(4)));
                xlim(axesHandle, ...
                    [(width-visibleWidth)/2, (width+visibleWidth)/2] + 0.5);
                ylim(axesHandle, ...
                    [(height-visibleHeight)/2, (height+visibleHeight)/2] + 0.5);
            else
                xlim(axesHandle, [0.5 width+0.5]);
                ylim(axesHandle, [0.5 height+0.5]);
            end
        end

        function settingsChanged(app)
            app.PresetMenu.Value = 'Custom';
            app.refreshPrepared();
            app.refreshControls();
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
            app.refreshPrepared();
            app.refreshControls();
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
        end

        function refreshControls(app)
            [valid, ~, side, message] = app.settings();
            inputCount = double(~isempty(app.Images.cover)) + ...
                double(~isempty(app.Images.watermark));
            app.StatusCards.inputs.Text = sprintf('%d of 2 ready', inputCount);

            hasCapacity = false;
            if ~isempty(app.Images.cover)
                capacity = WatermarkEngine.capacityBytes(app.Images.cover);
                if valid
                    required = side * side;
                    hasCapacity = required <= capacity;
                    app.CapacityLabel.Text = sprintf( ...
                        'Capacity: %d needed / %d available bytes', ...
                        required, capacity);
                    if ~hasCapacity
                        message = 'Use a smaller side or larger original image.';
                    end
                else
                    app.CapacityLabel.Text = sprintf( ...
                        'Available capacity: %d bytes', capacity);
                end
            else
                app.CapacityLabel.Text = ...
                    'Capacity: choose an original image.';
            end

            if isempty(message)
                if inputCount < 2
                    message = 'Choose both images to continue.';
                else
                    message = 'Ready to create. The result must be saved.';
                end
            end
            app.ValidationLabel.Text = message;

            available = struct( ...
                'sample', true, 'cover', true, 'watermark', true, ...
                'watermarked', true, ...
                'embed', valid && hasCapacity && inputCount == 2, ...
                'extract', ~isempty(app.Images.watermarked), ...
                'saveImage', ~isempty(app.Images.watermarked), ...
                'saveMark', ~isempty(app.Images.extracted), ...
                'extractSave', ~isempty(app.Images.extracted), ...
                'copySummary', ~isempty(app.LastSummary), ...
                'openFolder', ~isempty(app.LastSavedPath));
            names = fieldnames(app.Buttons);
            for index = 1:numel(names)
                enabled = available.(names{index}) && ~app.Busy;
                app.Buttons.(names{index}).Enable = app.onOff(enabled);
            end
            app.StrengthField.Enable = app.onOff(~app.Busy);
            app.SizeField.Enable = app.onOff(~app.Busy);
            app.PresetMenu.Enable = app.onOff(~app.Busy);
            app.refreshTechnicalSummary();
        end

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

        function loadWithDialog(app, name)
            [filename, folder] = app.chooseFile('open', ...
                ['Choose ' name]);
            if isequal(filename, 0)
                app.setStatus('Image selection canceled.');
                return;
            end
            app.readAndDisplay(name, fullfile(folder, filename));
        end

        function readAndDisplay(app, name, path)
            imageData = ImageStore.read(path, strcmp(name, 'watermarked'));
            sourceInfo = imfinfo(path);
            recovered = [];
            if strcmp(name, 'watermarked')
                recovered = WatermarkEngine.extract(imageData);
            end

            app.Images.(name) = imageData;
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
                app.LastQuality = NaN;
                app.LastSavedPath = '';
                app.StatusCards.verification.Text = 'Exact recovery';
                app.StatusCards.saved.Text = 'Source PNG loaded';
                app.setStatus(sprintf( ...
                    'Recovered a %d × %d watermark from the PNG.', ...
                    size(recovered.watermark, 2), ...
                    size(recovered.watermark, 1)));
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
                strength, [side side]);
            recovered = WatermarkEngine.extract(result.image);
            app.Images.prepared = result.preparedWatermark;
            app.Images.watermarked = result.image;
            app.Images.extracted = recovered.watermark;
            app.LastQuality = result.psnr;
            app.LastRecoveredStrength = recovered.strength;
            app.LastSavedPath = '';
            app.showImage('prepared', app.Images.prepared);
            app.showImage('watermarked', app.Images.watermarked);
            app.showImage('extracted', app.Images.extracted);
            app.refreshComparison();
            app.StatusCards.verification.Text = 'Exact recovery';
            app.StatusCards.saved.Text = 'Not saved';
            app.setStatus( ...
                'Created and verified. Save the watermarked PNG to keep it.');
        end

        function extractImage(app)
            if isempty(app.Images.watermarked)
                error('Watermark:Input', ...
                    'Choose a watermarked PNG first.');
            end
            recovered = WatermarkEngine.extract(app.Images.watermarked);
            app.Images.extracted = recovered.watermark;
            app.LastRecoveredStrength = recovered.strength;
            app.showImage('extracted', recovered.watermark);
            app.StatusCards.verification.Text = 'Exact recovery';
            app.setStatus(sprintf( ...
                'Recovered a %d × %d watermark. Strength: %d.', ...
                size(recovered.watermark, 2), ...
                size(recovered.watermark, 1), recovered.strength));
        end

        function runSample(app)
            projectFolder = fileparts(fileparts(mfilename('fullpath')));
            coverPath = fullfile( ...
                projectFolder, 'python', 'sample_cover.jpg');
            app.Images.cover = ImageStore.read(coverPath);
            app.Images.watermark = sampleWatermark();
            app.ImagePaths.cover = coverPath;
            app.ImagePaths.watermark = 'Built-in example';
            app.StrengthField.Value = '16';
            app.SizeField.Value = '32';
            app.PresetMenu.Value = 'Recommended';
            app.showImage('cover', app.Images.cover);
            app.showImage('watermark', app.Images.watermark);
            app.embedImage();
            app.setStatus( ...
                ['Example ready: compare the images, then save the ' ...
                 'watermarked PNG if you want to keep it.']);
        end

        function refreshComparison(app)
            compared = [];
            if ~isempty(app.Images.cover) && ...
                    ~isempty(app.Images.watermarked)
                switch app.ComparisonMenu.Value
                    case 'Original'
                        compared = app.Images.cover;
                    case 'Watermarked'
                        compared = app.Images.watermarked;
                    otherwise
                        difference = abs(double(app.Images.cover) - ...
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
        end

        function saveWithDialog(app, name)
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
                reopened = ImageStore.read(saved, true);
                recovered = WatermarkEngine.extract(reopened);
                app.Images.extracted = recovered.watermark;
                app.showImage('extracted', recovered.watermark);
                app.StatusCards.verification.Text = 'Exact recovery';
                app.StatusCards.saved.Text = 'PNG verified';
            else
                app.StatusCards.saved.Text = 'Watermark PNG saved';
            end
            app.setStatus(['Saved and verified: ' saved]);
        end

        function refreshTechnicalSummary(app)
            [valid, strength, side, ~] = app.settings();
            lines = {'WAVELET WATERMARK SUMMARY', ''};
            if ~isempty(app.Images.cover)
                cover = app.Images.cover;
                lines{end+1} = sprintf('Original: %d × %d px', ...
                    size(cover, 2), size(cover, 1));
                lines{end+1} = sprintf('Capacity: %d bytes', ...
                    WatermarkEngine.capacityBytes(cover));
                lines{end+1} = ['Original path: ' app.ImagePaths.cover];
            end
            if ~isempty(app.Images.watermark)
                mark = app.Images.watermark;
                lines{end+1} = sprintf('Input watermark: %d × %d px', ...
                    size(mark, 2), size(mark, 1));
                lines{end+1} = ['Watermark path: ' app.ImagePaths.watermark];
            end
            if valid
                lines{end+1} = sprintf( ...
                    'Prepared watermark: %d × %d grayscale', side, side);
                lines{end+1} = sprintf('Strength: %d', strength);
            end
            if ~isempty(app.Images.extracted)
                lines{end+1} = 'Recovery: exact, checksums passed';
                if isfinite(app.LastRecoveredStrength)
                    lines{end+1} = sprintf( ...
                        'Stored strength: %d', app.LastRecoveredStrength);
                end
            end
            if isfinite(app.LastQuality)
                lines{end+1} = sprintf( ...
                    'Image quality: %.2f dB PSNR', app.LastQuality);
            end
            if ~isempty(app.LastSavedPath)
                lines{end+1} = ['Saved: ' app.LastSavedPath];
            else
                lines{end+1} = 'Saved: no';
            end
            lines{end+1} = 'Output format: lossless PNG';
            app.TechnicalText.Value = lines;
            app.LastSummary = strjoin(lines, newline);
        end

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

        function [filename, folder] = chooseFile(~, mode, title, defaultName)
            % A movable native dialog stays above the visible app.
            if nargin < 4
                defaultName = '';
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
