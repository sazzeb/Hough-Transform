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
            evaluationTab = uitab(tabs, 'Title', 'Evaluate');

            app.buildCreateTab(createTab);
            app.buildExtractTab(extractTab);
            app.buildDetailsTab(detailsTab);
            app.buildEvaluationTab(evaluationTab);
            app.buildPreviewArea(workspace);
        end

        function buildCreateTab(app, tab)
            layout = uigridlayout(tab, [19 1]);
            layout.Scrollable = 'on';
            layout.RowHeight = {30, 37, 24, 37, 37, 57, 24, ...
                34, 34, 36, 22, 34, 34, 55, 42, 40, 35, 35, '1x'};
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
                ['The hidden image keeps its proportions and is converted ' ...
                 'to grayscale. Save the result as PNG to recover it.'], false);

            app.addLabel(layout, 7, '2  CHOOSE THE SETTINGS', true);
            app.PresetMenu = uidropdown(layout, ...
                'Items', {'Recommended', 'Subtle', 'Stronger', 'Custom'}, ...
                'Value', 'Recommended', ...
                'ValueChangedFcn', @(~, ~)app.applyPreset());
            app.PresetMenu.Layout.Row = 8;

            app.StrengthField = app.addTextSetting( ...
                layout, 9, 'Strength (8–32)', '16');
            app.StrengthSlider = uislider(layout, ...
                'Limits', [0 100], 'Value', 33, ...
                'MajorTicks', [0 25 50 75 100], ...
                'ValueChangingFcn', @(~, event)app.previewStrength( ...
                    event.Value), ...
                'ValueChangedFcn', @(~, event)app.finishStrengthChange( ...
                    event.Value));
            app.StrengthSlider.Layout.Row = 10;
            app.StrengthPercentLabel = app.addLabel(layout, 11, ...
                'Watermark strength: 33%  •  16/32', false);
            app.SizeField = app.addTextSetting( ...
                layout, 12, 'Hidden image side (8–64)', '32');
            app.ModeMenu = uidropdown(layout, ...
                'Items', {'Balanced', 'Durable', 'Classic'}, ...
                'Value', 'Balanced', ...
                'ValueChangedFcn', @(~, ~)app.settingsChanged());
            app.ModeMenu.Layout.Row = 13;
            app.StrengthField.ValueChangedFcn = ...
                @(~, ~)app.settingsChanged();
            app.SizeField.ValueChangedFcn = ...
                @(~, ~)app.settingsChanged();

            app.CapacityLabel = app.addLabel(layout, 14, ...
                'Capacity: choose an original image.', false);
            app.ValidationLabel = app.addLabel(layout, 15, ...
                'Choose both images to continue.', false);

            app.addButton(layout, 16, 'embed', ...
                'Create watermarked image', ...
                @()app.runAction(@()app.embedImage(), ...
                'Creating and verifying the image...'), true);
            app.addButton(layout, 17, 'saveImage', ...
                'Save watermarked PNG', ...
                @()app.runAction(@()app.saveWithDialog('watermarked'), ...
                'Opening save picker...'), false);
            app.addButton(layout, 18, 'saveMark', ...
                'Save recovered watermark', ...
                @()app.runAction(@()app.saveWithDialog('extracted'), ...
                'Opening save picker...'), false);
            app.addLabel(layout, 19, ...
                ['0–100% controls strength 8–32; it is not the ' ...
                 'percentage of pixels changed. Drag to preview; ' ...
                 'release for the full image. Durable adds redundancy ' ...
                 'against limited pixel damage. Keep the original PNG: ' ...
                 'JPEG, cropping and resizing may prevent recovery.'], false);
        end

        function buildExtractTab(app, tab)
            layout = uigridlayout(tab, [8 1]);
            layout.Scrollable = 'on';
            layout.RowHeight = {30, 88, 42, 42, 44, 76, 40, '1x'};
            layout.RowSpacing = 8;
            layout.Padding = [14 16 14 12];
            layout.BackgroundColor = [1 1 1];

            app.addLabel(layout, 1, 'RECOVER AN EXISTING WATERMARK', true);
            app.addLabel(layout, 2, ...
                ['For the image shown, select Recover current image. ' ...
                 'To recover later, first use Save watermarked PNG ' ...
                 'in Create, then open that same file below.'], false);
            app.addButton(layout, 3, 'extract', ...
                'Recover current image', ...
                @()app.runAction(@()app.extractImage(), ...
                'Checking and recovering the watermark...'), true);
            app.addButton(layout, 4, 'watermarked', ...
                'Open saved watermarked PNG', ...
                @()app.runAction(@()app.loadWithDialog('watermarked'), ...
                'Opening image picker...'), false);
            app.addButton(layout, 5, 'extractSave', ...
                'Save recovered watermark', ...
                @()app.runAction(@()app.saveWithDialog('extracted'), ...
                'Opening save picker...'), false);
            app.addLabel(layout, 6, ...
                ['Select the saved watermarked image, not the original ' ...
                 'photo, image to hide, or recovered watermark. ' ...
                 'Do not resize or recompress it.'], false);
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

        function buildEvaluationTab(app, tab)
            layout = uigridlayout(tab, [6 1]);
            layout.Scrollable = 'on';
            layout.RowHeight = {30, 145, 40, 170, 260, 110};
            layout.RowSpacing = 8;
            layout.Padding = [14 16 14 12];
            layout.BackgroundColor = [1 1 1];
            app.addLabel(layout, 1, 'ROBUSTNESS STUDY', true);
            app.addLabel(layout, 2, ...
                ['Uses the selected image pair, fitted to at most ' ...
                 '512 px. Tests Classic, Balanced and Durable; ' ...
                 'strengths 8, 16 and 32; watermark sides 16, 32 ' ...
                 'and 64. Changes: unchanged PNG, JPEG 95/75/50, ' ...
                 'crop 5%/10% from each edge and resize 75%/50%. ' ...
                 'Unavailable capacity settings are skipped.'], false);
            app.addButton(layout, 3, 'evaluate', ...
                'Run study on selected images', ...
                @()app.runAction(@()app.runEvaluation(), ...
                'Running robustness study...'), true);
            app.EvaluationSummary = uitable(layout, ...
                'ColumnName', {'Mode', 'Change', 'Exact', 'Total', ...
                'Rate', 'Header', 'Incomplete', 'Checksum', ...
                'Mean BER', 'Mean NCC'}, ...
                'ColumnEditable', false(1, 10));
            app.EvaluationSummary.Layout.Row = 4;
            app.EvaluationDetails = uitable(layout, ...
                'ColumnName', {'Mode', 'Strength', 'Side', 'Change', ...
                'Recovery', 'PSNR dB', 'Block SSIM', 'BER', 'NCC'}, ...
                'ColumnEditable', false(1, 9));
            app.EvaluationDetails.Layout.Row = 5;
            app.EvaluationNote = app.addLabel(layout, 6, ...
                ['No study yet. Exact rate counts only verified, ' ...
                 'pixel-identical prepared watermarks. BER and NCC ' ...
                 'are unavailable when recovery returns no pixels; ' ...
                 'their means use only recovered cases. ' ...
                 'PSNR and block SSIM compare the working cover with ' ...
                 'the image before each change.'], false);
        end

        function buildPreviewArea(app, workspace)
            right = uigridlayout(workspace, [7 1]);
            app.RightLayout = right;
            right.Layout.Column = 2;
            right.RowHeight = {78, 27, 1100, 270, 55, 27, 1280};
            right.RowSpacing = 9;
            right.Padding = [0 0 0 0];
            right.Scrollable = 'on';
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

            stageHeading = uilabel(right, ...
                'Text', '01  IMAGE → PREPARATION → HAAR DETAILS → RECOVERY', ...
                'FontSize', 12, 'FontWeight', 'bold', ...
                'FontColor', [38 100 53]/255);
            stageHeading.Layout.Row = 2;

            stages = uigridlayout(right, [3 2]);
            stages.Layout.Row = 3;
            stages.RowHeight = {360, 360, 360};
            stages.ColumnWidth = {'1x', '1x'};
            stages.RowSpacing = 10;
            stages.ColumnSpacing = 8;
            stages.Padding = [0 0 0 0];
            stages.BackgroundColor = [1 1 1];
            app.addStage(stages, 'source', '1  Original', ...
                'Cover image', 1);
            app.addStage(stages, 'input', '2  Image to hide', ...
                'Selected watermark', 2);
            app.addStage(stages, 'gray', '3  Prepared', ...
                'Grayscale + fit', 3);
            app.addStage(stages, 'haar', '4  Haar details', ...
                'First 512 × 512 pixels · magnitude ×2 for display', 4);
            app.addStage(stages, 'changed', '5  Embedded detail', ...
                'First 512 × 512 pixels · change ×4 for display', 5);
            app.addStage(stages, 'decoded', '6  Decoded', ...
                'Recovered bytes', 6);

            metrics = uigridlayout(right, [2 2]);
            metrics.Layout.Row = 4;
            metrics.RowHeight = {'1x', '1x'};
            metrics.ColumnWidth = {'1x', '1x'};
            metrics.RowSpacing = 8;
            metrics.ColumnSpacing = 8;
            metrics.Padding = [0 0 0 0];
            metrics.BackgroundColor = [1 1 1];
            app.addMetric(metrics, 1, 'psnr', 'COVER QUALITY · PSNR', ...
                'Original cover → watermarked | 10log10(255²/MSE)');
            app.addMetric(metrics, 2, 'ssim', 'COVER QUALITY · SSIM', ...
                'Original cover → watermarked | 8×8 block luminance variant');
            app.addMetric(metrics, 3, 'ber', 'RECOVERY · BER', ...
                'Prepared grayscale → recovered | wrong bits / all bits');
            app.addMetric(metrics, 4, 'ncc', 'RECOVERY · NCC', ...
                'Prepared grayscale → recovered | normalized dot product');

            evidenceNote = uilabel(right, ...
                'Text', ['Scores evaluate outputs; they do not create ' ...
                    'the watermark. No universal pass threshold applies. ' ...
                    'The Haar map shows only the first 512 × 512 ' ...
                    'pixels at 2× and coefficient changes at 4× ' ...
                    'for visualization. See Evaluate for measured ' ...
                    'recovery under specified changes.'], ...
                'FontSize', 10, 'WordWrap', 'on', ...
                'FontColor', [0 0 0]);
            evidenceNote.Layout.Row = 5;

            resultHeading = uilabel(right, ...
                'Text', '02  RESULT IMAGES  •  Compare the true pixels below', ...
                'FontSize', 12, 'FontWeight', 'bold', ...
                'FontColor', [38 100 53]/255);
            resultHeading.Layout.Row = 6;

            previews = uigridlayout(right, [3 2]);
            app.PreviewGrid = previews;
            previews.Layout.Row = 7;
            previews.RowHeight = {420, 420, 420};
            previews.ColumnWidth = {'1x', '1x'};
            previews.RowSpacing = 10;
            previews.ColumnSpacing = 10;
            previews.Padding = [0 0 0 0];
            previews.BackgroundColor = [1 1 1];

            app.addPreview(previews, 'cover', 'Original image', 1, 1);
            app.addPreview(previews, 'watermark', ...
                'Image to hide', 1, 2);
            app.addPreview(previews, 'prepared', ...
                'Prepared grayscale image', 2, 1);
            app.addPreview(previews, 'watermarked', ...
                'Watermarked image', 2, 2);
            app.addPreview(previews, 'extracted', ...
                'Recovered watermark', 3, 1);
            app.addPreview(previews, 'comparison', ...
                'Compare images', 3, 2);
            app.refreshEvidence();
        end

        function addStage(app, parent, name, title, detailText, index)
            card = uipanel(parent, 'BorderType', 'line', ...
                'BackgroundColor', [1 1 1]);
            card.Layout.Row = ceil(index/2);
            card.Layout.Column = mod(index-1, 2) + 1;
            layout = uigridlayout(card, [3 1]);
            layout.RowHeight = {28, '1x', 32};
            layout.Padding = [12 10 12 10];
            layout.RowSpacing = 2;
            titleLabel = uilabel(layout, 'Text', title, ...
                'FontSize', 12, 'FontWeight', 'bold', ...
                'FontColor', [38 100 53]/255);
            titleLabel.Layout.Row = 1;
            axesHandle = uiaxes(layout);
            axesHandle.Layout.Row = 2;
            axesHandle.Toolbar.Visible = 'off';
            app.StageAxes.(name) = axesHandle;
            detail = uilabel(layout, 'Text', detailText, ...
                'WordWrap', 'on', 'FontSize', 11, ...
                'FontColor', [0 0 0]);
            detail.Layout.Row = 3;
            app.StageDetails.(name) = detail;
        end

        function addMetric(app, parent, index, name, title, formula)
            card = uipanel(parent, 'BorderType', 'line', ...
                'BackgroundColor', [1 1 1]);
            card.Layout.Row = ceil(index/2);
            card.Layout.Column = mod(index-1, 2) + 1;
            layout = uigridlayout(card, [3 1]);
            layout.RowHeight = {23, 44, '1x'};
            layout.Padding = [10 7 10 7];
            heading = uilabel(layout, 'Text', title, ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', [38 100 53]/255);
            heading.Layout.Row = 1;
            value = uilabel(layout, 'Text', 'Waiting for images', ...
                'FontSize', 17, 'FontWeight', 'bold', ...
                'FontColor', [0 0 0], 'WordWrap', 'on');
            value.Layout.Row = 2;
            app.MetricValues.(name) = value;
            explanation = uilabel(layout, 'Text', formula, ...
                'FontSize', 9, 'WordWrap', 'on', ...
                'FontColor', [0 0 0]);
            explanation.Layout.Row = 3;
        end

        function refreshEvidence(app)
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

        function showStage(app, name, imageData)
            axesHandle = app.StageAxes.(name);
            cla(axesHandle);
            if isempty(imageData)
                text(axesHandle, 0.5, 0.5, 'Waiting', ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'middle', ...
                    'FontSize', 9, 'Color', [0 0 0]);
                xlim(axesHandle, [0 1]);
                ylim(axesHandle, [0 1]);
            elseif ismatrix(imageData)
                imagesc(axesHandle, imageData, [0 255]);
                colormap(axesHandle, gray(256));
                axis(axesHandle, 'image');
            else
                image(axesHandle, imageData);
                axis(axesHandle, 'image');
            end
            axis(axesHandle, 'off');
        end

        function [horizontal, vertical] = haarDetails(~, imageData)
            values = double(imageData);
            if ndims(values) == 3
                values = 0.299*values(:,:,1) + ...
                    0.587*values(:,:,2) + 0.114*values(:,:,3);
            end
            height = 2*floor(min(512, size(values, 1))/2);
            width = 2*floor(min(512, size(values, 2))/2);
            a = values(1:2:height, 1:2:width);
            b = values(1:2:height, 2:2:width);
            c = values(2:2:height, 1:2:width);
            d = values(2:2:height, 2:2:width);
            horizontal = (a-b+c-d)/2;
            vertical = (a+b-c-d)/2;
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
            layout.RowHeight = {32, '1x', 24, 34};
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
                    'FontSize', 13, 'FontWeight', 'bold', ...
                    'FontColor', [0 0 0]);
                heading.Layout.Row = 1;
            end

            axesHandle = uiaxes(layout);
            axesHandle.Layout.Row = 2;
            axesHandle.Toolbar.Visible = 'off';
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
            else
                app.WorkspaceLayout.ColumnWidth = {340, '1x'};
            end
            app.RightLayout.RowHeight = ...
                {78, 27, 1100, 270, 55, 27, 1280};
            app.PreviewGrid.RowHeight = {420, 420, 420};
            app.PreviewGrid.ColumnWidth = {'1x', '1x'};

            for index = 1:numel(names)
                card = app.PreviewCards.(names{index});
                card.Layout.Row = ceil(index/2);
                card.Layout.Column = mod(index-1, 2) + 1;
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

        function runEvaluation(app)
            if isempty(app.Images.cover) || isempty(app.Images.watermark)
                error('Watermark:Input', ...
                    'Choose an original image and an image to hide first.');
            end
            report = WatermarkEngine.evaluateRobustness( ...
                app.Images.cover, app.Images.watermark, ...
                @(step, total)app.updateEvaluationProgress(step, total));
            summary = report.summary;
            details = report.details;
            for row = 1:size(summary, 1)
                summary{row, 5} = sprintf('%.1f%%', ...
                    100*summary{row, 5});
                for column = [9 10]
                    if isnan(summary{row, column})
                        summary{row, column} = 'N/A';
                    else
                        summary{row, column} = sprintf('%.4f', ...
                            summary{row, column});
                    end
                end
            end
            for row = 1:size(details, 1)
                for column = 6:9
                    if isnan(details{row, column})
                        details{row, column} = 'N/A';
                    else
                        details{row, column} = sprintf('%.4f', ...
                            details{row, column});
                    end
                end
            end
            app.EvaluationSummary.Data = summary;
            app.EvaluationDetails.Data = details;
            working = report.workingSize;
            app.EvaluationNote.Text = sprintf( ...
                ['Study uses %d × %d working cover pixels; %d ' ...
                'configurations skipped for capacity. Exact rate = ' ...
                'verified, pixel-identical prepared marks / tested ' ...
                'cases. Header, Incomplete and Checksum count distinct ' ...
                'failure states. N/A means extraction returned no watermark. ' ...
                'Mean BER and NCC use only recovered cases. ' ...
                'PSNR and 8×8 block SSIM use the working cover and ' ...
                'watermarked image before the listed change.'], ...
                working(2), working(1), ...
                report.skippedConfigurations);
            app.setStatus(sprintf( ...
                'Study complete: %d tested cases; %d settings skipped.', ...
                size(details, 1), report.skippedConfigurations));
        end

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

        function refreshControls(app)
            [valid, ~, side, message] = app.settings();
            inputCount = double(~isempty(app.Images.cover)) + ...
                double(~isempty(app.Images.watermark));
            app.StatusCards.inputs.Text = sprintf('%d of 2 ready', inputCount);

            hasCapacity = false;
            if ~isempty(app.Images.cover)
                capacity = WatermarkEngine.capacityBytes( ...
                    app.Images.cover, app.selectedMode());
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
                'evaluate', inputCount == 2, ...
                'embed', valid && hasCapacity && inputCount == 2, ...
                'extract', ~isempty(app.Images.watermarked) && ...
                    ~app.PreviewOnly, ...
                'saveImage', ~isempty(app.Images.watermarked) && ...
                    ~app.PreviewOnly, ...
                'saveMark', ~isempty(app.Images.extracted) && ...
                    ~app.PreviewOnly, ...
                'extractSave', ~isempty(app.Images.extracted) && ...
                    ~app.PreviewOnly, ...
                'copySummary', ~isempty(app.LastSummary), ...
                'openFolder', ~isempty(app.LastSavedPath));
            names = fieldnames(app.Buttons);
            for index = 1:numel(names)
                enabled = available.(names{index}) && ~app.Busy;
                app.Buttons.(names{index}).Enable = app.onOff(enabled);
            end
            app.StrengthField.Enable = app.onOff(~app.Busy);
            app.StrengthSlider.Enable = app.onOff(~app.Busy);
            app.SizeField.Enable = app.onOff(~app.Busy);
            app.PresetMenu.Enable = app.onOff(~app.Busy);
            app.ModeMenu.Enable = app.onOff(~app.Busy);
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

        function runSample(app)
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

        function refreshComparison(app)
            compared = [];
            original = app.Images.cover;
            if app.PreviewOnly
                original = app.PreviewCover;
            end
            if ~isempty(app.Images.cover) && ...
                    ~isempty(app.Images.watermarked)
                switch app.ComparisonMenu.Value
                    case 'Original'
                        compared = original;
                    case 'Watermarked'
                        compared = app.Images.watermarked;
                    otherwise
                        difference = abs(double(original) - ...
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
            app.refreshEvidence();
        end

        function saveWithDialog(app, name)
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

        function refreshTechnicalSummary(app)
            [valid, strength, side, ~] = app.settings();
            lines = {'WAVELET WATERMARK SUMMARY', ''};
            if ~isempty(app.Images.cover)
                cover = app.Images.cover;
                lines{end+1} = sprintf('Original: %d × %d px', ...
                    size(cover, 2), size(cover, 1));
                lines{end+1} = sprintf('Capacity: %d bytes', ...
                    WatermarkEngine.capacityBytes( ...
                        cover, app.selectedMode()));
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
                lines{end+1} = sprintf( ...
                    'Strength slider: %d%%', ...
                    round(app.StrengthSlider.Value));
                lines{end+1} = ['Mode: ' app.ModeMenu.Value];
            end
            if ~isempty(app.Images.extracted)
                lines{end+1} = ['Recovery: ' app.LastRecoveryState];
                if isfinite(app.LastRecoveredStrength)
                    lines{end+1} = sprintf( ...
                        'Stored strength: %d', app.LastRecoveredStrength);
                end
            end
            if isfinite(app.LastQuality)
                if app.PreviewOnly
                    lines{end+1} = sprintf( ...
                        'Crop preview PSNR: %.2f dB', app.LastQuality);
                else
                    lines{end+1} = sprintf( ...
                        'Cover PSNR: %.2f dB', app.LastQuality);
                end
            end
            comparisonCover = app.Images.cover;
            if app.PreviewOnly
                comparisonCover = app.PreviewCover;
            end
            if ~isempty(comparisonCover) && ...
                    ~isempty(app.Images.watermarked) && ...
                    isequal(size(comparisonCover), ...
                        size(app.Images.watermarked))
                lines{end+1} = sprintf( ...
                        '8x8 block luminance SSIM variant: %.4f', ...
                    WatermarkEngine.ssim( ...
                        comparisonCover, app.Images.watermarked));
            end
            if ~isempty(app.Images.prepared) && ...
                    ~isempty(app.Images.extracted) && ...
                    isequal(size(app.Images.prepared), ...
                        size(app.Images.extracted))
                lines{end+1} = sprintf( ...
                    'Recovered bit error rate: %.3f%%', ...
                    100*WatermarkEngine.bitErrorRate( ...
                        app.Images.prepared, app.Images.extracted));
                lines{end+1} = sprintf( ...
                    'Watermark normalized correlation: %.5f', ...
                    WatermarkEngine.normalizedCorrelation( ...
                        app.Images.prepared, app.Images.extracted));
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
