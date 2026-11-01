function runProjectChecks()
%RUNPROJECTCHECKS Exercise watermark recovery and analyze all MATLAB files.
    projectFolder = fileparts(mfilename('fullpath'));
    testWatermarkProject();

    sourceFiles = dir(fullfile(projectFolder, '*.m'));
    totalFindings = 0;

    for fileIndex = 1:numel(sourceFiles)
        filename = sourceFiles(fileIndex).name;
        findings = checkcode( ...
            fullfile(projectFolder, filename), '-struct');

        for findingIndex = 1:numel(findings)
            fprintf('%s:%d: %s\n', ...
                filename, findings(findingIndex).line, ...
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
