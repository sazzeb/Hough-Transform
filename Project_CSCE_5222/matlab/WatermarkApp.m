classdef WatermarkApp < handle
    properties (Access = private)
        Window
        StrengthControl
        SideControl
        StatusControl
        HeaderPanel
        HeaderGrid
        HeaderLabels
        SectionLabels
        SurfaceContainers = {}

        Buttons = struct()
        Previews = struct()
        PreviewDetails = struct()

        Images = struct( ...
            'cover', [], ...
            'watermark', [], ...
            'watermarked', [], ...
            'extracted', [])

        Busy = false
    end

    methods
        function app = WatermarkApp()
            app.Window = uifigure( ...
                'Name', 'Wavelet Watermarking', ...
                'WindowStyle', 'normal', ...
                'Position', [100 100 1180 820], ...
                'CloseRequestFcn', @(~, ~)app.closeWindow());
            app.Window.ThemeChangedFcn = @(~, ~)app.applyBrandTheme();

            page = uigridlayout(app.Window, [3 1]);
            page.RowHeight = {88, '1x', 60};
            page.ColumnWidth = {'1x'};
            page.RowSpacing = 0;
            page.Padding = [0 0 0 0];

            app.HeaderPanel = uipanel( ...
                page, 'BorderType', 'none');
            app.HeaderPanel.Layout.Row = 1;

            header = uigridlayout(app.HeaderPanel, [2 1]);
            app.HeaderGrid = header;
            header.RowHeight = {20, 32};
            header.RowSpacing = 2;
            header.Padding = [24 14 24 14];

            app.HeaderLabels = [ ...
                uilabel(header, ...
                    'Text', 'IMAGE LAB  /  WAVELET WATERMARKING', ...
                    'FontSize', 11, 'FontWeight', 'bold'); ...
                uilabel(header, ...
                    'Text', 'Embed, inspect, and recover an image watermark', ...
                    'FontSize', 20, 'FontWeight', 'bold')];

            app.HeaderLabels(1).Layout.Row = 1;
            app.HeaderLabels(2).Layout.Row = 2;

            body = uigridlayout(page, [1 2]);
            body.Layout.Row = 2;
            body.ColumnWidth = {264, '1x'};
            body.ColumnSpacing = 12;
            body.Padding = [16 12 16 12];

            sidebar = uipanel(body, 'BorderType', 'line');
            sidebar.Layout.Column = 1;

            controls = uigridlayout(sidebar, [20 1]);
            controls.Scrollable = 'on';
            app.SurfaceContainers = {sidebar, controls};
            controls.RowHeight = { ...
                18, 32, 6, 18, 30, 30, 30, 6, 18, 34, ...
                34, 6, 18, 32, 30, 6, 18, 30, 30, '1x'};
            controls.RowSpacing = 3;
            controls.Padding = [12 12 12 10];

            app.SectionLabels = [ ...
                app.addSection(controls, 1, 'QUICK START'); ...
                app.addSection(controls, 4, '01  INPUT IMAGES'); ...
                app.addSection(controls, 9, '02  EMBEDDING SETTINGS'); ...
                app.addSection(controls, 13, '03  PROCESS'); ...
                app.addSection(controls, 17, '04  SAVE RESULTS')];

            app.addButton(controls, 2, 'sample', 'Try example', ...
                @()app.runAction( ...
                    @()app.runSample(), ...
                    'Loading and testing the example...'));
            app.addButton(controls, 5, 'cover', ...
                'Load cover image', @()app.loadImage('cover'));
            app.addButton(controls, 6, 'watermark', ...
                'Load watermark image', @()app.loadImage('watermark'));
            app.addButton(controls, 7, 'watermarked', ...
                'Open saved PNG', @()app.loadImage('watermarked'));

            app.StrengthControl = app.addSetting( ...
                controls, 10, 'Strength  ·  8-32', '16');
            app.SideControl = app.addSetting( ...
                controls, 11, 'Watermark side  ·  8-64', '32');

            app.addButton(controls, 14, 'embed', ...
                'Embed and verify', ...
                @()app.runAction( ...
                    @()app.embedImage(), ...
                    'Embedding and checking recovery...'));
            app.addButton(controls, 15, 'extract', ...
                'Extract from PNG', ...
                @()app.runAction( ...
                    @()app.extractImage(), ...
                    'Extracting and verifying watermark...'));
            app.addButton(controls, 18, 'saveImage', ...
                'Save watermarked PNG', ...
                @()app.saveImage('watermarked'));
            app.addButton(controls, 19, 'saveMark', ...
                'Save extracted PNG', ...
                @()app.saveImage('extracted'));

            previews = uigridlayout(body, [2 2]);
            previews.Layout.Column = 2;
            previews.RowHeight = {'1x', '1x'};
            previews.ColumnWidth = {'1x', '1x'};
            previews.RowSpacing = 12;
            previews.ColumnSpacing = 12;
            previews.Padding = [0 0 0 0];

            app.addPreview(previews, 'cover', ...
                'Cover image', 1, 1);
            app.addPreview(previews, 'watermark', ...
                'Watermark input', 1, 2);
            app.addPreview(previews, 'watermarked', ...
                'Watermarked image', 2, 1);
            app.addPreview(previews, 'extracted', ...
                'Extracted watermark', 2, 2);

            footer = uigridlayout(page, [1 1]);
            footer.Layout.Row = 3;
            footer.Padding = [22 8 22 8];

            app.StatusControl = uilabel(footer, ...
                'WordWrap', 'on', 'FontSize', 11);

            app.applyBrandTheme();

            app.setStatus( ...
                ['Try the example or load a cover and watermark. ' ...
                 'Save as PNG; extraction reads its embedded header.']);

            app.updateControls();
        end

        function delete(app)
            if isgraphics(app.Window)
                delete(app.Window);
            end
        end
    end

    methods (Access = private)
        function label = addSection(~, parent, row, caption)
            label = uilabel(parent, ...
                'Text', caption, 'FontSize', 10, ...
                'FontWeight', 'bold');
            label.Layout.Row = row;
        end

        function addButton(app, parent, row, name, caption, callback)
            button = uibutton(parent, 'push', ...
                'Text', caption, ...
                'ButtonPushedFcn', @(~, ~)callback(), ...
                'FontSize', 11);
            button.Layout.Row = row;
            app.Buttons.(name) = button;
        end

        function control = addSetting(~, parent, row, caption, value)
            setting = uigridlayout(parent, [1 2]);
            setting.Layout.Row = row;
            setting.ColumnWidth = {'1x', 54};
            setting.Padding = [0 0 0 0];

            uilabel(setting, 'Text', caption, 'FontSize', 11);
            control = uieditfield(setting, 'text', ...
                'Value', value, 'HorizontalAlignment', 'center');
            control.Layout.Column = 2;
        end

        function addPreview(app, parent, name, caption, row, column)
            card = uipanel(parent, 'BorderType', 'line');
            card.Layout.Row = row;
            card.Layout.Column = column;

            contents = uigridlayout(card, [3 1]);
            app.SurfaceContainers(end+1:end+2) = {card, contents};
            contents.RowHeight = {24, '1x', 20};
            contents.Padding = [12 9 12 9];
            contents.RowSpacing = 4;

            heading = uilabel(contents, 'Text', caption, ...
                'FontSize', 12, 'FontWeight', 'bold');
            heading.Layout.Row = 1;

            displayAxes = uiaxes(contents);
            displayAxes.Layout.Row = 2;
            displayAxes.Toolbar.Visible = 'off';
            app.Previews.(name) = displayAxes;

            detail = uilabel(contents, ...
                'Text', 'No image loaded', 'FontSize', 10);
            detail.Layout.Row = 3;
            app.PreviewDetails.(name) = detail;

            app.showImage(name, []);
        end

        function applyBrandTheme(app)
            theme = app.brandTheme();

            app.HeaderPanel.BackgroundColor = theme.header;
            app.HeaderGrid.BackgroundColor = theme.header;

            for index = 1:numel(app.SurfaceContainers)
                app.SurfaceContainers{index}.BackgroundColor = ...
                    theme.surface;
            end

            for index = 1:numel(app.HeaderLabels)
                app.HeaderLabels(index).BackgroundColor = theme.header;
                app.HeaderLabels(index).FontColor = theme.onHeader;
            end

            for index = 1:numel(app.SectionLabels)
                app.SectionLabels(index).FontColor = theme.secondary;
            end

            primary = {'sample', 'embed'};

            for index = 1:numel(primary)
                button = app.Buttons.(primary{index});
                button.BackgroundColor = theme.primary;
                button.FontColor = theme.onPrimary;
                button.FontWeight = 'bold';
            end
        end

        function theme = brandTheme(app)
            theme.primary = [36 88 166] / 255;
            theme.onPrimary = [1 1 1];
            theme.secondary = [45 87 135] / 255;
            theme.header = [20 38 61] / 255;
            theme.onHeader = [1 1 1];
            theme.surface = [1 1 1];

            if strcmpi( ...
                    string(app.Window.Theme.BaseColorStyle), 'dark')
                theme.primary = fliplightness(theme.primary);
                theme.onPrimary = fliplightness(theme.onPrimary);
                theme.secondary = fliplightness(theme.secondary);
                theme.header = fliplightness(theme.header);
                theme.onHeader = fliplightness(theme.onHeader);
                theme.surface = fliplightness(theme.surface);
            end
        end

        function setStatus(app, message)
            app.StatusControl.Text = message;
        end

        function showImage(app, name, imageData)
            displayAxes = app.Previews.(name);
            cla(displayAxes);

            if ~isempty(imageData)
                if ismatrix(imageData)
                    imagesc(displayAxes, imageData, [0 255]);
                    colormap(displayAxes, gray(256));
                else
                    image(displayAxes, imageData);
                end

                axis(displayAxes, 'image');
            else
                placeholders = struct( ...
                    'cover', 'Load a cover image', ...
                    'watermark', 'Load a watermark image', ...
                    'watermarked', 'Embed to see the result', ...
                    'extracted', 'Recover a watermark');

                text(displayAxes, 0.5, 0.5, ...
                    placeholders.(name), ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'middle', ...
                    'FontSize', 12);
                xlim(displayAxes, [0 1]);
                ylim(displayAxes, [0 1]);
            end

            axis(displayAxes, 'off');

            details = 'No image loaded';

            if ~isempty(imageData)
                details = sprintf('%d x %d px', ...
                    size(imageData, 2), size(imageData, 1));
            end

            app.PreviewDetails.(name).Text = details;
        end

        function updateControls(app)
            available = struct( ...
                'sample', true, ...
                'cover', true, ...
                'watermark', true, ...
                'watermarked', true, ...
                'embed', ...
                    ~isempty(app.Images.cover) && ...
                    ~isempty(app.Images.watermark), ...
                'extract', ~isempty(app.Images.watermarked), ...
                'saveImage', ~isempty(app.Images.watermarked), ...
                'saveMark', ~isempty(app.Images.extracted));

            names = fieldnames(app.Buttons);

            for index = 1:numel(names)
                state = 'off';

                if available.(names{index}) && ~app.Busy
                    state = 'on';
                end

                set(app.Buttons.(names{index}), 'Enable', state);
            end

            state = 'on';

            if app.Busy
                state = 'off';
            end

            set( ...
                [app.StrengthControl app.SideControl], ...
                'Enable', state);
        end

        function runAction(app, operation, message)
            if app.Busy
                return;
            end

            app.Busy = true;
            app.updateControls();
            app.setStatus(message);

            set(app.Window, 'Pointer', 'watch');

            cleanup = onCleanup( ...
                @()app.finishAction());

            drawnow;

            try
                operation();
            catch exception
                app.setStatus(['Operation failed: ' exception.message]);

                uialert( ...
                    app.Window, exception.message, ...
                    'Operation failed', 'Icon', 'error');
            end
        end

        function finishAction(app)
            app.Busy = false;

            if isgraphics(app.Window)
                set(app.Window, 'Pointer', 'arrow');
                app.updateControls();
            end
        end

        function loadImage(app, name)
            if app.Busy
                return;
            end

            [filename, folder] = app.chooseFile( ...
                'open', ['Load ' name]);

            if isequal(filename, 0)
                return;
            end

            path = fullfile(folder, filename);

            app.runAction( ...
                @()app.readAndDisplay(name, path), ...
                'Loading image...');
        end

        function readAndDisplay(app, name, path)
            imageData = ImageStore.read( ...
                path, strcmp(name, 'watermarked'));

            recovered = [];

            if strcmp(name, 'watermarked')
                recovered = WatermarkEngine.extract(imageData);
            end

            app.Images.(name) = imageData;
            app.showImage(name, imageData);

            invalidated = {'extracted'};

            if ~strcmp(name, 'watermarked')
                invalidated = {'watermarked', 'extracted'};
            end

            for index = 1:numel(invalidated)
                app.Images.(invalidated{index}) = [];
                app.showImage(invalidated{index}, []);
            end

            if ~isempty(recovered)
                app.Images.extracted = recovered.watermark;
                app.showImage('extracted', recovered.watermark);
            end

            message = sprintf( ...
                'Loaded %d x %d image.', ...
                size(imageData, 2), size(imageData, 1));

            if strcmp(name, 'cover')
                message = sprintf( ...
                    '%s Payload capacity: %d bytes.', ...
                    message, ...
                    WatermarkEngine.capacityBytes(imageData));
            end

            if ~isempty(recovered)
                message = sprintf( ...
                    ['%s Watermark extracted and checked: ' ...
                     '%d x %d, strength %d.'], ...
                    message, ...
                    size(recovered.watermark, 2), ...
                    size(recovered.watermark, 1), ...
                    recovered.strength);
            end

            app.setStatus(message);
        end

        function embedImage(app)
            if isempty(app.Images.cover) || isempty(app.Images.watermark)
                error('Watermark:Input', ...
                    'Load both a cover and a watermark.');
            end

            strength = str2double(app.StrengthControl.Value);
            side = str2double(app.SideControl.Value);

            result = WatermarkEngine.embed( ...
                app.Images.cover, ...
                app.Images.watermark, ...
                strength, ...
                [side side]);

            recovered = WatermarkEngine.extract(result.image);
            app.displayEmbedding(result, recovered);
        end

        function runSample(app)
            appFile = mfilename('fullpath');
            projectFolder = fileparts(fileparts(appFile));
            samplePath = fullfile( ...
                projectFolder, 'python', 'sample_cover.jpg');

            cover = ImageStore.read(samplePath);
            watermark = sampleWatermark();
            result = WatermarkEngine.embed( ...
                cover, watermark, 16, [32 32]);
            recovered = WatermarkEngine.extract(result.image);

            app.Images.cover = cover;
            app.Images.watermark = watermark;
            app.showImage('cover', cover);
            app.showImage('watermark', watermark);
            app.StrengthControl.Value = '16';
            app.SideControl.Value = '32';
            app.displayEmbedding(result, recovered);
        end

        function displayEmbedding(app, result, recovered)
            app.Images.watermarked = result.image;
            app.Images.extracted = recovered.watermark;

            app.showImage('watermarked', result.image);
            app.showImage('extracted', recovered.watermark);

            app.setStatus(sprintf( ...
                ['Embedded and extracted a %d x %d grayscale watermark ' ...
                 'across all image channels. ' ...
                 'Strength %d. PSNR %.2f dB. Exact recovery passed. ' ...
                 'Save the watermarked PNG to keep it; JPEG output is not ' ...
                 'supported because it is lossy.'], ...
                size(recovered.watermark, 2), ...
                size(recovered.watermark, 1), ...
                result.strength, result.psnr));
        end

        function extractImage(app)
            if isempty(app.Images.watermarked)
                error('Watermark:Input', ...
                    'Embed or load a watermarked PNG first.');
            end

            result = WatermarkEngine.extract(app.Images.watermarked);

            app.Images.extracted = result.watermark;
            app.showImage('extracted', result.watermark);

            app.setStatus(sprintf( ...
                ['Extraction passed both checksums. ' ...
                 'Stored strength %d. Watermark %d x %d.'], ...
                result.strength, ...
                size(result.watermark, 2), ...
                size(result.watermark, 1)));
        end

        function saveImage(app, name)
            if app.Busy || isempty(app.Images.(name))
                return;
            end

            [filename, folder] = app.chooseFile( ...
                'save', ['Save ' name], [name '.png']);

            if isequal(filename, 0)
                return;
            end

            [~, ~, extension] = fileparts(filename);

            if isempty(extension)
                filename = [filename '.png'];
            end

            app.runAction( ...
                @()app.saveAndReport( ...
                    fullfile(folder, filename), name), ...
                'Saving and verifying PNG...');
        end

        function saveAndReport(app, filename, name)
            saved = ImageStore.savePng( ...
                filename, app.Images.(name));

            if strcmp(name, 'watermarked')
                reopened = ImageStore.read(saved, true);
                recovered = WatermarkEngine.extract(reopened);
                app.Images.extracted = recovered.watermark;
                app.showImage('extracted', recovered.watermark);
                app.setStatus([ ...
                    'Saved ' saved '. Reopened the PNG and recovered its watermark.']);
            else
                app.setStatus(['Verified and saved: ' saved]);
            end
        end

        function [filename, folder] = chooseFile(~, mode, title, defaultName)
            % A standalone native dialog remains movable and above the app.
            % The regular MATLAB file picker has no UIFigure parent option.
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

        function closeWindow(app)
            if app.Busy
                uialert(app.Window, ...
                    'Close the window after the current operation finishes.', ...
                    'Operation in progress');

                return;
            end

            delete(app);
        end
    end
end
