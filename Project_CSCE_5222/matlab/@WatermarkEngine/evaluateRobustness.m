function report = evaluateRobustness(cover, watermark, progress)
    % Try PNG, JPEG, crop, and resize changes across several settings.
    % Use a smaller cover so the study finishes in a reasonable time.
    if nargin < 3
        progress = [];
    end
    WatermarkEngine.validateImage(cover);
    WatermarkEngine.validateImage(watermark);
    scale = min(1, 512/max(size(cover, 1), size(cover, 2)));
    if scale < 1
        workingCover = imresize(cover, scale, 'bilinear');
    else
        workingCover = cover;
    end

    modes = {'classic', 'balanced', 'durable'};
    strengths = [8 16 32];
    sides = [16 32 64];
    changes = {'Unchanged PNG', 'JPEG 95', 'JPEG 75', ...
        'JPEG 50', 'Crop 5% each edge', ...
        'Crop 10% each edge', 'Resize 75%', 'Resize 50%'};
    skipped = 0;
    configuration = 0;
    totalConfigurations = numel(modes)*numel(strengths)*numel(sides);
    details = cell(totalConfigurations*numel(changes), 9);
    detailCount = 0;

    for modeIndex = 1:numel(modes)
        mode = modes{modeIndex};
        capacity = WatermarkEngine.capacityBytes( ...
            workingCover, mode);
        for strength = strengths
            for side = sides
                configuration = configuration + 1;
                if ~isempty(progress)
                    progress(configuration, totalConfigurations);
                end
                if side^2 > capacity
                    skipped = skipped + 1;
                    continue;
                end
                embedded = WatermarkEngine.embed( ...
                    workingCover, watermark, strength, ...
                    [side side], mode);
                quality = WatermarkEngine.psnr( ...
                    workingCover, embedded.image);
                structure = WatermarkEngine.ssim( ...
                    workingCover, embedded.image);
                for changeIndex = 1:numel(changes)
                    changed = WatermarkEngine.applyStudyChange( ...
                        embedded.image, changeIndex);
                    bitRate = NaN;
                    correlation = NaN;
                    try
                        recovered = WatermarkEngine.extract(changed);
                        if isequal(size(recovered.watermark), ...
                                size(embedded.preparedWatermark))
                            bitRate = WatermarkEngine.bitErrorRate( ...
                                embedded.preparedWatermark, ...
                                recovered.watermark);
                            correlation = ...
                                WatermarkEngine.normalizedCorrelation( ...
                                embedded.preparedWatermark, ...
                                recovered.watermark);
                        end
                        if recovered.verified && bitRate == 0
                            state = 'Verified exact';
                        elseif recovered.verified
                            state = 'Verified, pixels differ';
                        else
                            state = 'Checksum failed; approximate';
                        end
                    catch exception
                        if strcmp(exception.identifier, ...
                                'Watermark:Checksum')
                            state = 'Payload checksum failed';
                        elseif any(strcmp(exception.identifier, ...
                                {'Watermark:Header', ...
                                'Watermark:Format'}))
                            state = 'Header unreadable';
                        elseif strcmp(exception.identifier, ...
                                'Watermark:Incomplete')
                            state = 'Incomplete payload';
                        else
                            rethrow(exception);
                        end
                    end
                    detailCount = detailCount + 1;
                    details(detailCount, :) = {mode, strength, side, ...
                        changes{changeIndex}, state, ...
                        quality, structure, bitRate, correlation};
                end
            end
        end
    end

    details = details(1:detailCount, :);
    summary = cell(numel(modes)*numel(changes), 10);
    summaryCount = 0;
    for modeIndex = 1:numel(modes)
        for changeIndex = 1:numel(changes)
            selected = strcmp(details(:, 1), modes{modeIndex}) & ...
                strcmp(details(:, 4), changes{changeIndex});
            rows = details(selected, :);
            if isempty(rows)
                continue;
            end
            states = rows(:, 5);
            exactCount = sum(strcmp(states, 'Verified exact'));
            unreadableCount = sum(strcmp( ...
                states, 'Header unreadable'));
            incompleteCount = sum(strcmp( ...
                states, 'Incomplete payload'));
            failedCount = sum(contains(states, 'checksum failed', ...
                'IgnoreCase', true));
            bitRates = cell2mat(rows(:, 8));
            correlations = cell2mat(rows(:, 9));
            validBits = bitRates(isfinite(bitRates));
            validCorrelations = correlations( ...
                isfinite(correlations));
            meanBitRate = NaN;
            meanCorrelation = NaN;
            if ~isempty(validBits)
                meanBitRate = mean(validBits);
            end
            if ~isempty(validCorrelations)
                meanCorrelation = mean(validCorrelations);
            end
            summaryCount = summaryCount + 1;
            summary(summaryCount, :) = {modes{modeIndex}, ...
                changes{changeIndex}, exactCount, size(rows, 1), ...
                exactCount/size(rows, 1), unreadableCount, ...
                incompleteCount, failedCount, ...
                meanBitRate, meanCorrelation};
        end
    end
    summary = summary(1:summaryCount, :);
    report = struct('details', {details}, 'summary', {summary}, ...
        'workingSize', size(workingCover), ...
        'skippedConfigurations', skipped);
end
