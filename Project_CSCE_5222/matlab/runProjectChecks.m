function runProjectChecks()
% Run the recovery tests and check every MATLAB source file.
    projectFolder = fileparts(mfilename('fullpath'));
    testWatermarkProject();

    sourceFiles = dir(fullfile(projectFolder, '**', '*.m'));
    totalFindings = 0;

    for fileIndex = 1:numel(sourceFiles)
        filename = sourceFiles(fileIndex).name;
        sourcePath = fullfile(sourceFiles(fileIndex).folder, filename);
        findings = checkcode( ...
            sourcePath, '-struct');

        for findingIndex = 1:numel(findings)
            fprintf('%s:%d: %s\n', ...
                erase(sourcePath, [projectFolder filesep]), ...
                findings(findingIndex).line, ...
                findings(findingIndex).message);
        end

        totalFindings = totalFindings + numel(findings);
    end

    if totalFindings > 0
        error('Watermark:CodeIssues', ...
            'MATLAB Code Analyzer reported %d findings.', totalFindings);
    end

    fprintf('MATLAB Code Analyzer: no findings across %d files.\n', ...
        numel(sourceFiles));
end
