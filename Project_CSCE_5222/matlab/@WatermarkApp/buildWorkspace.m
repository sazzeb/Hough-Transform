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
