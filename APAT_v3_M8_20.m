classdef APAT_v3_M8_20 < matlab.apps.AppBase %1981-lines %ISSUES: %1. Cut plots don't load/plot E-cut by-default-as-preset %2. POB annotation on Cut plots shows two DataTips instead of one! %3. Customized Interactive DataTip NOT-OK ON Contour Plot & Fisheye Plot (shows default X_Y_Z/Theta_R_Z, instead of Customized DataTips) %4. When loading new pattern while the older/current POB DataTip is active/enabled, it shows the old POB and the new one (the old POB DataTip shouldn't show after loading a new pattern)! %5. Table Outputs Filter not showing %6. Coverage Threshold Query snaps to nearest Data Point instead of returning requested/query point! %7. Context menu shows warning: "Warning: You cannot set 'ContextMenu' property of DataTip."
% APAT v3 M8 — Antenna Pattern Analyzer Tool (concise architecture release).
%
% Design in one paragraph: every loaded source is normalized once into a canonical,
% physical pattern table (theta 0..180°, phi 0..360° with a closed 360° seam). That
% single table feeds processing, cuts, metrics, orientation, coverage and export.
% The user-selectable display conventions (phi span, theta/elevation span) are
% applied only at the presentation edge (axes, tick labels, data tips, result table)
% and never rewrite the data. Numerical services are pure local functions at the end
% of this file and never touch the UI.

    properties (GetAccess = public, SetAccess = private)
        isClosing logical = false
    end

    properties (Access = public) % UI handles (kept public for tests / scripting)
        UIFigure matlab.ui.Figure
        TabGroup matlab.ui.container.TabGroup
        Tab1_Single matlab.ui.container.Tab
        Tab2_Coverage matlab.ui.container.Tab
        % --- Main tab: inputs & parameters
        Single_EditField_Path matlab.ui.control.EditField
        Single_Button_Load matlab.ui.control.Button
        Single_Button_Process matlab.ui.control.Button
        Single_Button_ResetParams matlab.ui.control.Button
        Single_Export_Output matlab.ui.control.Button
        Single_Export_UAN matlab.ui.control.Button
        Single_Button_Coverage matlab.ui.control.Button
        TextFormatLabel matlab.ui.control.Label
        Single_DropDown_TextFormat matlab.ui.control.DropDown
        FFDFreqDropDownLabel matlab.ui.control.Label
        Single_DropDown_FFD matlab.ui.control.DropDown
        Single_DropDown_step matlab.ui.control.DropDown
        Single_DropDown_RxPol matlab.ui.control.DropDown
        Single_Spinner_Rw matlab.ui.control.Spinner
        Single_Spinner_Loss matlab.ui.control.Spinner
        Single_Spinner_Pt matlab.ui.control.Spinner
        Single_DropDown_Pt matlab.ui.control.DropDown
        Single_Spinner_R matlab.ui.control.Spinner
        Single_DropDown_R matlab.ui.control.DropDown
        ParamGroups struct % label+control groups toggled together: rx, tx, dist, loss
        Single_StatusBar matlab.ui.control.Label
        % --- Main tab: plot control
        Single_Panel_plotControl matlab.ui.container.Panel
        Single_DropDown_Component matlab.ui.control.DropDown
        Single_DropDown_cutType matlab.ui.control.DropDown
        Single_DropDown_cutValue matlab.ui.control.Spinner
        CutFieldBasisDropDown matlab.ui.control.DropDown
        Single_Plot_Cmax matlab.ui.control.Spinner
        Single_Plot_Cmin matlab.ui.control.Spinner
        Single_Plot_Cstep matlab.ui.control.Spinner
        Single_Button_Clim matlab.ui.control.Button
        Single_DropDown_3DView matlab.ui.control.DropDown
        Single_Switch_AngularSpan matlab.ui.control.Switch
        Single_Switch_ThetaSpan matlab.ui.control.Switch
        Single_Switch_EHplane matlab.ui.control.Switch
        Single_CheckBox_overlayCut matlab.ui.control.CheckBox
        Single_CheckBox_POB matlab.ui.control.CheckBox
        Single_CheckBox_HPBWBounds matlab.ui.control.CheckBox
        % --- Main tab: data tables
        Single_tabData matlab.ui.container.TabGroup
        Single_DropDown_output matlab.ui.control.DropDown
        Single_Table_DataOut matlab.ui.control.Table
        Single_Table_DataIn matlab.ui.control.Table
        Single_Table_metadata matlab.ui.control.Table
        % --- Main tab: cut panel
        Single_Panel_Rect matlab.ui.container.Panel
        Single_tabCut matlab.ui.container.TabGroup
        Single_tabPolarPlot matlab.ui.container.Tab
        Single_tabRectPlot matlab.ui.container.Tab
        Single_paxCut matlab.graphics.axis.PolarAxes
        Single_AxesRect matlab.ui.control.UIAxes
        Range_Cut matlab.ui.control.RangeSlider
        Range_Cut_Min matlab.ui.control.Spinner
        Range_Cut_Max matlab.ui.control.Spinner
        Button_HPBW matlab.ui.control.StateButton
        Label_HPBW matlab.ui.control.Label
        Button_ExportCut matlab.ui.control.Button
        Single_gridEcut matlab.ui.container.GridLayout
        CheckBox_Et matlab.ui.control.CheckBox
        CheckBox_Er matlab.ui.control.CheckBox
        CheckBox_El matlab.ui.control.CheckBox
        % --- Main tab: full-pattern panel (five tabs share one spec array)
        Single_Panel_fullPattern matlab.ui.container.Panel
        Single_tabPlots matlab.ui.container.TabGroup
        Single_Axes_Ctr matlab.ui.control.UIAxes
        Single_paxPattern matlab.graphics.axis.PolarAxes
        Single_Axes_3dSph matlab.ui.control.UIAxes
        Single_Axes_3dPol matlab.ui.control.UIAxes
        Single_Axes_3dRect matlab.ui.control.UIAxes
        FullSpecs struct % name / axes / slider / min / max / render per full-pattern tab
        % --- Coverage tab
        Cov_EditField_filePath matlab.ui.control.EditField
        Cov_Button_Load matlab.ui.control.Button
        Cov_Button_computeCov matlab.ui.control.Button
        Cov_Button_Reset matlab.ui.control.Button
        Cov_Button_Export matlab.ui.control.Button
        Cov_Button_Clear matlab.ui.control.Button
        Cov_Button_toMain matlab.ui.control.Button
        Cov_TextFormatLabel matlab.ui.control.Label
        Cov_DropDown_TextFormat matlab.ui.control.DropDown
        Cov_ButtonGroup_CovType matlab.ui.container.ButtonGroup
        Cov_ButtonGroup_Btn_Conical matlab.ui.control.RadioButton
        Cov_ButtonGroup_Btn_Spherical matlab.ui.control.RadioButton
        Cov_DropDown_Orientation matlab.ui.control.DropDown
        Cov_Spinner_ConeTH matlab.ui.control.Spinner
        Cov_Spinner_ConePH matlab.ui.control.Spinner
        Cov_Spinner_ConeAng matlab.ui.control.Spinner
        Cov_Spinner_ThreshMin matlab.ui.control.Spinner
        Cov_Spinner_ThreshMax matlab.ui.control.Spinner
        Cov_Spinner_Step matlab.ui.control.Spinner
        Cov_DropDown_Component matlab.ui.control.DropDown
        Cov_Spinner_queryCov matlab.ui.control.Spinner
        Cov_Button_queryCov matlab.ui.control.Button
        Cov_Spinner_queryThresh matlab.ui.control.Spinner
        Cov_Button_queryThresh matlab.ui.control.Button
        CovGroups struct % control groups toggled together: pattern, cone, query, results
        Cov_Panel_Results matlab.ui.container.Panel
        Cov_Axes matlab.ui.control.UIAxes
        Cov_Tree matlab.ui.container.CheckBoxTree
        Cov_TreeNode_Results matlab.ui.container.TreeNode
        Cov_Table matlab.ui.control.Table
        Cov_Spinner_XMin matlab.ui.control.Spinner
        Cov_Spinner_XMax matlab.ui.control.Spinner
        Cov_Spinner_XRange matlab.ui.control.RangeSlider
        Cov_StatusBar matlab.ui.control.Label
    end

    properties (Access = private)
        % source & pipeline (all tables are canonical/physical, see header)
        src struct = struct()        % rawTbl, blocks, freqs, meta, filePath, fileName, baseName, folderPath
        stdTbl table                 % normalized standard table of the selected block
        patTbl table                 % processed pattern at native resolution
        viewTbl table                % processed pattern at the selected step (feeds every view)
        dOmega double = []           % solid-angle weights aligned with viewTbl rows
        grid struct = struct()       % lazily built grid topology, geometry and component matrices
        pol struct = struct('label','n/a','pairs',struct('Linear',["E_TH","E_PH"],'Circular',["E_RCP","E_LCP"]))
        peak struct = struct()       % resolved POB of the selected component (value/index/row/col/theta/phi)
        metrics struct = struct()    % scalar antenna metrics of the total-gain column
        boresight double = 1         % index into PrincipalAxes
        % UI state that must survive re-processing
        useOneDeg logical = false    % user asked for the 1° resampled view
        cutBasisAuto logical = true  % cut basis follows the detected polarization until edited
        outMask logical = []         % visible result columns (3:end)
        outStyles cell = {}          % dropdown styles for the column filter
        gainLim double = [-40 10]    % authoritative non-AR full-pattern color range
        cutLim double = [-40 10]     % cut plot range
        defaults struct = struct()   % startup parameter values (Reset Params)
        % infrastructure
        statusTimer = []             % single reusable one-shot timer for transient status text
        busyDlg = []                 % active cancelable progress dialog
        % coverage
        covRunID double = 0
        covPresetKey string = ""     % pattern|component whose threshold preset is active
        covPlotInit logical = false  % first result establishes the X baseline
        covSyncing logical = false   % re-entrancy guard for range widgets
    end

    properties (Constant, Access = private)
        PrincipalAxes = struct('labels', {{'+Z','-Z','+X','-X','+Y','-Y'}}, 'theta', [0,180,90,90,90,90], 'phi', [0,0,0,180,90,270])
        HiddenOutputColumns = {'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'}
        ComponentNames = ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","AR_dB","Gain_PolCorrected_dB"]
        ComponentLabels = ["Total Gain","Etheta Gain","Ephi Gain","RHCP Gain","LHCP Gain","Axial Ratio","Polarized Gain"]
        Views3D = struct('iso',[135 25 0 0 1],'top',[0 90 0 1 0],'bottom',[0 -90 0 1 0],'right',[90 0 0 0 1],'left',[-90 0 0 0 1],'front',[0 0 0 0 1],'back',[180 0 0 0 1])
        HardRange = [-250 100]
        PeakPercentile = 99.99
        PeakMaxExcessDB = 6
        DistanceFloorM = 1e-12
        ReleaseName = 'APAT v3 Milestone 8'
        ReleaseVersion = '3.0-M8'
    end

    %% ------------------------------------------------------------------ lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_20
            createComponents(app)
            registerApp(app, app.UIFigure)
            runStartupFcn(app, @startupFcn)
            if nargout == 0, clear app; end
        end

        function closeRequest(app, ~)
            if app.isClosing, return; end
            app.isClosing = true;
            t = app.statusTimer; app.statusTimer = [];
            if ~isempty(t) && isvalid(t), stop(t); delete(t); end
            if ~isempty(app.busyDlg) && isvalid(app.busyDlg), delete(app.busyDlg); end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end

        function delete(app)
            app.closeRequest();
        end
    end

    methods (Access = private)
        function startupFcn(app)
            app.statusTimer = timer('ExecutionMode','singleShot','StartDelay',3,'TimerFcn',@(~,~) app.restoreStatus());
            app.defaults = app.getParam();
            allAxes = {app.Single_Axes_Ctr, app.Single_AxesRect, app.Single_paxPattern, app.Single_paxCut, app.Single_Axes_3dSph, app.Single_Axes_3dPol, app.Single_Axes_3dRect};
            for k = 1:numel(allAxes)
                ax = allAxes{k}; enableDefaultInteractivity(ax);
                if ~isa(ax,'matlab.graphics.axis.PolarAxes')
                    if k > 4, ax.Interactions = [rotateInteraction, dataTipInteraction]; else, ax.Interactions = [zoomInteraction, dataTipInteraction]; end
                end
                menu = uicontextmenu(app.UIFigure); % one menu per axes for the whole session (no per-render churn)
                uimenu(menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~,~) delete(findall(ax,'Type','datatip')));
                ax.ContextMenu = menu;
            end
            app.setRanges(app.gainLim);
            app.setStatus(app.Single_StatusBar, 'Ready -- load an antenna pattern file to begin 🚀', false);
            app.setStatus(app.Cov_StatusBar, 'Ready 🚀', false);
            app.setCoverageUI();
        end
    end

    %% ------------------------------------------------------------------ loading & processing pipeline
    methods (Access = public)
        function out = readFile(~, fp, textFormat, tableData)
            % I/O boundary: file -> {rawTbl, blocks, freqs, meta}. UI independent.
            if nargin < 4, tableData = table(); end
            out = readPattern(fp, textFormat, tableData);
        end

        function [standard, pattern] = buildPatternData(app, sourceData)
            % Auxiliary (non-Main) pattern, e.g. for the Coverage tab.
            standard = normalizePattern(sourceData.blocks{1});
            standard.Properties.UserData = sourceData.meta;
            pattern = calcPattern(standard, app.getParam(), app.PeakPercentile, app.PeakMaxExcessDB);
        end

        function param = getParam(app)
            param = struct('GainLoss_dB', app.Single_Spinner_Loss.Value, 'RxMode', string(app.Single_DropDown_RxPol.Value), 'RxAR_dB', app.Single_Spinner_Rw.Value);
            param.FieldScale = 10 .^ (param.GainLoss_dB / 20);
            power = app.Single_Spinner_Pt.Value;
            switch app.Single_DropDown_Pt.Value
                case 'dBm',   param.Pt_dBW = power - 30;
                case 'Watts', param.Pt_dBW = 10 * log10(max(power, eps));
                otherwise,    param.Pt_dBW = power;
            end
            param.R_m = max(app.Single_Spinner_R.Value, app.DistanceFloorM) * (1 + 999 * strcmp(app.Single_DropDown_R.Value, 'km'));
            param.Power = power; param.PowerUnit = app.Single_DropDown_Pt.Value; param.Distance = app.Single_Spinner_R.Value; param.DistanceUnit = app.Single_DropDown_R.Value;
        end

        function refresh(app)
            % stdTbl -> patTbl -> viewTbl -> every view. Called after load / parameter / block changes.
            [app.patTbl, info] = calcPattern(app.stdTbl, app.getParam(), app.PeakPercentile, app.PeakMaxExcessDB);
            app.checkCancelled();
            app.pol = struct('label', info.pol, 'pairs', info.pairs);
            gainOnly = app.src.meta.isGainOnly;
            if app.cutBasisAuto && ~gainOnly
                if startsWith(info.pol, 'Linear'), app.CutFieldBasisDropDown.Value = 'Linear'; else, app.CutFieldBasisDropDown.Value = 'Circular'; end
            end
            thetaStep = gridStep(app.patTbl.Theta); phiStep = gridStep(app.patTbl.Phi);
            if ~isfinite(thetaStep), thetaStep = 1; end, if ~isfinite(phiStep), phiStep = thetaStep; end
            nonCanonical = abs(thetaStep - 1) > 1e-9 || abs(phiStep - 1) > 1e-9;
            items = {sprintf('STEP: %g°', max(thetaStep, phiStep)), 'STEP: 1°'};
            app.Single_DropDown_step.Items = items; app.Single_DropDown_step.Value = items{1 + (app.useOneDeg && nonCanonical)};
            set(app.Single_DropDown_step, 'Visible', nonCanonical, 'Enable', nonCanonical);
            app.buildView();
            app.updateView(true);
            set([app.Single_Panel_Rect, app.Single_Export_Output, app.Single_Panel_fullPattern, app.Single_Panel_plotControl, app.Single_Button_Coverage, app.Single_tabData], 'Visible', 'on');
            set([app.Single_Export_UAN, app.Single_gridEcut, app.CheckBox_Et, app.CheckBox_Er, app.CheckBox_El], 'Visible', ~gainOnly);
            app.CutFieldBasisDropDown.Enable = ~gainOnly;
            polText = ''; if ~gainOnly && ~strcmpi(strtrim(app.pol.label), 'n/a'), polText = sprintf(' | Polarization <b>%s</b>', app.pol.label); end
            app.setStatus(app.Single_StatusBar, sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)%s', ...
                app.src.fileName, app.fmtNumber(app.peak.value, 2), app.fmtNumber(app.peak.theta), app.fmtNumber(app.peak.phi), polText), false);
        end

        function buildView(app)
            % Materialize viewTbl at the selected angular step. Resampling is performed on the
            % primitive source quantities (fields / gain), never on derived outputs such as AR or PLF.
            source = app.stdTbl;
            useOne = strcmp(app.Single_DropDown_step.Value, 'STEP: 1°') && logical(app.Single_DropDown_step.Visible);
            if useOne
                thetaStep = gridStep(source.Theta); phiStep = gridStep(source.Phi);
                if isfinite(thetaStep) && isfinite(phiStep) && thetaStep < 1 && phiStep < 1
                    keep = abs(source.Theta - round(source.Theta)) < 1e-9 & abs(source.Phi - round(source.Phi)) < 1e-9;
                    source = source(keep, :); % exact integer sub-grid: decimate instead of interpolating
                else
                    source = resampleCanonical(source, 1);
                end
                source.Properties.UserData = app.stdTbl.Properties.UserData;
                app.viewTbl = calcPattern(source, app.getParam(), app.PeakPercentile, app.PeakMaxExcessDB);
            else
                app.viewTbl = app.patTbl;
            end
            app.dOmega = solidWeights(app.viewTbl.Theta, app.viewTbl.Phi);
            app.grid = struct();
            app.updateComponentItems();
        end

        function updateView(app, resetRanges)
            % Everything derived from viewTbl + selected component + display conventions.
            if isempty(app.viewTbl), return; end
            T = app.viewTbl; comp = app.comp(); pp = app.PeakPercentile; pm = app.PeakMaxExcessDB;
            [pk, app.boresight] = calcOrientation(T, app.dOmega, comp, app.PrincipalAxes, pp, pm);
            g = app.gridData();
            [~, ti] = ismember(T.Theta(pk.index), g.theta); [~, pi_] = ismember(T.Phi(pk.index), g.phi);
            app.peak = struct('value', pk.value, 'index', pk.index, 'row', ti, 'col', pi_, 'theta', T.Theta(pk.index), 'phi', mod(T.Phi(pk.index), 360), 'wasAdjusted', pk.wasAdjusted);
            app.metrics = calcMetrics(T, app.dOmega, app.PrincipalAxes, app.boresight, pp, pm);
            app.checkCancelled();
            if resetRanges
                if ~app.isAR() && ismember('E_Total_dB', T.Properties.VariableNames), app.gainLim = peakWindow(T.E_Total_dB, [-50 0], pp, pm); end
                if app.isAR(), app.setRanges([-30 30]); else, app.setRanges(app.gainLim); end
            end
            app.updateTables(); app.updateMetadata();
            app.updateCutControl(); app.plotCut();
            app.checkCancelled();
            app.renderAll();
        end

        function activateSource(app, out, fp)
            [folder, base, ext] = fileparts(fp);
            app.src = struct('rawTbl', out.rawTbl, 'blocks', {out.blocks}, 'freqs', out.freqs, 'meta', out.meta, ...
                'filePath', fp, 'fileName', [base ext], 'baseName', base, 'folderPath', folder);
            app.selectBlock(1);
        end

        function selectBlock(app, k)
            block = app.src.blocks{k};
            if app.src.meta.isDep, app.src.rawTbl = block; end
            app.stdTbl = normalizePattern(block);
            app.stdTbl.Properties.UserData = app.src.meta;
            app.Single_Table_DataIn.Data = app.src.rawTbl; app.Single_Table_DataIn.ColumnName = app.src.rawTbl.Properties.VariableNames;
        end
    end

    methods (Access = private)
        function onLoad(app, ~)
            previousPath = app.Single_EditField_Path.Value; fp = strtrim(previousPath);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.srcField('filePath'))
                fp = app.browse('Select an antenna pattern file', app.srcField('filePath'));
                if isempty(fp), return; end
                app.Single_EditField_Path.Value = fp;
            end
            done = app.busy('Loading Data', 'Reading file...', true); %#ok<NASGU>
            t0 = tic;
            try
                out = app.prepareTextFormat(fp, app.TextFormatLabel, app.Single_DropDown_TextFormat);
                app.checkCancelled();
                if out.meta.isCoverage % route coverage results without replacing Main state
                    app.Single_EditField_Path.Value = previousPath;
                    [app.TabGroup.SelectedTab, app.Cov_EditField_filePath.Value] = deal(app.Tab2_Coverage, fp);
                    app.covLoadResults(fp, out.rawTbl);
                    return
                end
                app.activateSource(out, fp);
                isDep = out.meta.isDep;
                if isDep
                    items = compose('Pattern %d: %.4g GHz', (1:numel(out.blocks))', (out.freqs(:) / 1e9));
                    items(isnan(out.freqs(:))) = compose('Pattern %d', find(isnan(out.freqs(:))));
                    [app.Single_DropDown_FFD.Items, app.Single_DropDown_FFD.Value] = deal(items, items{1});
                end
                set([app.Single_DropDown_FFD, app.FFDFreqDropDownLabel], 'Visible', isDep, 'Enable', isDep);
                [app.useOneDeg, app.cutBasisAuto] = deal(false, true);
                app.refresh();
                app.setStatus(app.Single_StatusBar, sprintf('%s | loaded in %.2f s', app.Single_StatusBar.UserData, toc(t0)), false);
            catch ME
                app.fail(ME, 'Loading Error', app.Single_StatusBar);
            end
        end

        function onProcess(app, ~)
            if isempty(app.stdTbl), uialert(app.UIFigure, 'No file! Load a pattern first.', 'Warning', 'Icon', 'warning'); return; end
            done = app.busy('Processing', 'Re-processing pattern...', false); %#ok<NASGU>
            app.useOneDeg = strcmp(app.Single_DropDown_step.Value, 'STEP: 1°');
            try
                if app.isGenericTextFile(app.src.filePath) % reinterpret the cached generic table with the selected format
                    out = app.readFile(app.src.filePath, app.Single_DropDown_TextFormat.Value, app.src.rawTbl);
                    assert(~out.meta.isCoverage, 'The selected generic format identifies a coverage-results file.');
                    app.activateSource(out, app.src.filePath);
                end
                app.refresh();
                app.setStatus(app.Single_StatusBar, ['Re-processed <b>' app.src.fileName '</b> with current parameters ' char(9989)], true);
            catch ME
                app.fail(ME, 'Processing Error', app.Single_StatusBar);
            end
        end

        function onTextFormatChanged(app, ~)
            if strcmp(strtrim(app.Single_EditField_Path.Value), app.srcField('filePath')) && app.isGenericTextFile(app.src.filePath)
                app.cutBasisAuto = true; app.onProcess();
            end
        end

        function onFFDChanged(app, ~)
            k = find(strcmp(app.Single_DropDown_FFD.Items, app.Single_DropDown_FFD.Value), 1);
            app.cutBasisAuto = true; app.selectBlock(k); app.refresh();
            app.setStatus(app.Single_StatusBar, sprintf('Switched to FFD block %d (%s).', k, app.Single_DropDown_FFD.Value), true);
        end

        function stepChanged(app, ~)
            app.useOneDeg = strcmp(app.Single_DropDown_step.Value, 'STEP: 1°');
            app.buildView(); app.updateView(true);
        end

        function resetParams(app, ~)
            d = app.defaults;
            [app.Single_Spinner_Loss.Value, app.Single_DropDown_RxPol.Value, app.Single_Spinner_Rw.Value, app.Single_Spinner_Pt.Value, ...
                app.Single_DropDown_Pt.Value, app.Single_Spinner_R.Value, app.Single_DropDown_R.Value] = ...
                deal(d.GainLoss_dB, char(d.RxMode), d.RxAR_dB, d.Power, d.PowerUnit, d.Distance, d.DistanceUnit);
            if ~isempty(app.stdTbl), app.refresh(); end
        end

        function sourceData = prepareTextFormat(app, fp, label, dropdown)
            % Generic text files expose the format selector; every other source is self-describing.
            generic = app.isGenericTextFile(fp);
            if generic, fmt = "gain"; else, fmt = string(dropdown.Value); end
            sourceData = app.readFile(fp, fmt);
            showSelector = generic && ~sourceData.meta.isCoverage;
            if showSelector, dropdown.Value = 'gain'; end
            set([label, dropdown], 'Visible', showSelector);
        end

        function tf = isGenericTextFile(~, fp)
            [~, ~, ext] = fileparts(fp); tf = ismember(lower(ext), {'.csv', '.txt', '.dat'});
        end

        function value = srcField(app, name)
            if isfield(app.src, name), value = app.src.(name); else, value = ''; end
        end

        function fp = browse(app, titleText, alreadyLoaded)
            % File browser that refuses to "re-load" the active file (offers to pick another one).
            filters = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage data'; '*.*', 'All files'};
            fp = '';
            while true
                [f, p] = uigetfile(filters, titleText);
                if isequal(f, 0), return; end
                candidate = fullfile(p, f);
                if ~strcmp(candidate, alreadyLoaded), fp = candidate; return; end
                choice = uiconfirm(app.UIFigure, sprintf('"<b>%s</b>" is already loaded', f), 'File Already Loaded', ...
                    'Options', {'Select Another File', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2, 'Interpreter', 'html');
                if strcmp(choice, 'Cancel'), return; end
            end
        end
    end

    %% ------------------------------------------------------------------ view model: conventions, grid, components
    methods (Access = private)
        function [signedPhi, elevation] = conv(app)
            signedPhi = strcmp(app.Single_Switch_AngularSpan.Value, '-180° to 180°');
            elevation = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°');
        end

        function [phiLimits, thetaLimits, thetaDir, thetaLabel] = axesConv(app)
            [sp, el] = app.conv();
            if sp, phiLimits = [-180 180]; else, phiLimits = [0 360]; end
            if el, thetaLimits = [-90 90]; thetaDir = 'normal'; thetaLabel = 'Elevation'; else, thetaLimits = [0 180]; thetaDir = 'reverse'; thetaLabel = 'Theta'; end
        end

        function g = gridData(app, column)
            % Canonical grid topology + geometry (built once per view) and per-component matrices (built on demand).
            g = app.grid;
            if ~isfield(g, 'theta')
                T = app.viewTbl; [sp, el] = app.conv();
                g.theta = unique(T.Theta); g.phi = unique(T.Phi); g.sz = [numel(g.theta), numel(g.phi)];
                [~, it] = ismember(T.Theta, g.theta); [~, ip] = ismember(T.Phi, g.phi); g.idx = sub2ind(g.sz, it, ip);
                [g.phiGrid, g.thetaGrid] = meshgrid(g.phi, g.theta);
                phiRad = deg2rad(g.phiGrid); sinTheta = sind(g.thetaGrid);
                g.x = sinTheta .* cos(phiRad); g.y = sinTheta .* sin(phiRad); g.z = cosd(g.thetaGrid); g.phiRad = phiRad;
                % display versions of the same grid (canonical column order)
                g.thetaDisp = g.theta; g.thetaGridDisp = g.thetaGrid; g.phiGridDisp = g.phiGrid;
                if el, g.thetaDisp = 90 - g.theta; g.thetaGridDisp = 90 - g.thetaGrid; end
                if sp, g.phiGridDisp(g.phiGrid > 180) = g.phiGrid(g.phiGrid > 180) - 360; end
                % rectangular plots need display column order: drop 360, wrap >180, prepend -180 copy of 180
                g.cols = (1:g.sz(2))'; g.phiDisp = g.phi;
                if sp
                    keep = find(g.phi < 360 - 1e-9); pd = g.phi(keep); pd(pd > 180) = pd(pd > 180) - 360;
                    [pd, order] = sort(pd); cols = keep(order);
                    c180 = find(abs(g.phi - 180) < 1e-9, 1);
                    if ~isempty(c180), pd = [-180; pd]; cols = [c180; cols]; end
                    g.phiDisp = pd; g.cols = cols;
                end
                g.data = struct();
            end
            if nargin > 1
                key = matlab.lang.makeValidName(column);
                if ~isfield(g.data, key), m = nan(g.sz); m(g.idx) = app.viewTbl.(column); g.data.(key) = m; end
                g.value = g.data.(key);
            end
            app.grid = g;
        end

        function c = dispCol(app, g)
            % Column of the peak in display order (the 360° seam column maps back to 0°).
            c = find(g.cols == app.peak.col, 1);
            if isempty(c), c = find(abs(g.phi(g.cols) - mod(g.phi(app.peak.col), 360)) < 1e-9, 1); end
        end

        function T = displayTable(app)
            % The only place where a table is rewritten into the display convention (results tab / export).
            T = app.viewTbl; [sp, el] = app.conv();
            if sp
                T(abs(T.Phi - 360) < 1e-9, :) = []; T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
                seam = T(abs(T.Phi - 180) < 1e-9, :); seam.Phi(:) = -180; T = [seam; T];
            end
            if el, T.Theta = 90 - T.Theta; end
            if sp || el, T = sortrows(T, {'Phi', 'Theta'}); end
        end

        function [columns, labels] = componentMap(app, T)
            available = string(T.Properties.VariableNames(3:end));
            if T.Properties.UserData.isGainOnly, [columns, labels] = deal(available); return; end
            present = ismember(app.ComponentNames, available);
            [columns, labels] = deal(app.ComponentNames(present), app.ComponentLabels(present));
        end

        function component = preferredComponent(~, previous, columns)
            if any(columns == string(previous)), component = string(previous);
            elseif any(columns == "E_Total_dB"), component = "E_Total_dB";
            else, component = columns(1); end
            component = char(component);
        end

        function updateComponentItems(app)
            [columns, labels] = app.componentMap(app.viewTbl); dd = app.Single_DropDown_Component;
            previous = dd.Value; [dd.Items, dd.ItemsData] = deal(cellstr(labels), cellstr(columns));
            if ~isempty(columns), dd.Value = app.preferredComponent(previous, columns); end
        end

        function component = comp(app), component = app.Single_DropDown_Component.Value; end

        function label = compLabel(app)
            dd = app.Single_DropDown_Component; k = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(k), label = strrep(string(dd.Value), '_', ' '); else, label = string(dd.Items{k}); end
        end

        function tf = isAR(app, component)
            % AR semantics independent of column spelling: AR, AR_dB, Axial Ratio, ...
            if nargin < 2, component = app.comp(); end
            key = regexprep(lower(strtrim(string(component))), '[^a-z0-9]', '');
            tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
        end

        function onComponentChanged(app, ~)
            if app.src.meta.isGainOnly, app.onEHPlaneChanged(); end
            app.updateView(true);
        end

        function onSpanChanged(app, ~)
            app.grid = struct(); app.updateView(false);
        end
    end

    %% ------------------------------------------------------------------ tables, metadata, parameter visibility
    methods (Access = private)
        function updateTables(app)
            T = app.displayTable(); columns = T.Properties.VariableNames(3:end); dd = app.Single_DropDown_output;
            schemaChanged = ~isequal(regexprep(dd.Items(2:end), '^✓ ?', ''), columns);
            if schemaChanged
                [dd.Items, dd.ItemsData, dd.Value] = deal([{'--- column filter ---'}, columns], 0:numel(columns), 0);
                app.outMask = ~ismember(columns, app.HiddenOutputColumns);
            end
            app.filterOutput([], schemaChanged, T);
        end

        function filterOutput(app, ~, restyle, T)
            % Column-filter dropdown: selecting an item toggles that column; ✓ marks visible columns.
            if nargin < 3, restyle = true; end, if nargin < 4, T = app.displayTable(); end
            dd = app.Single_DropDown_output;
            if dd.Value > 0, app.outMask(dd.Value) = ~app.outMask(dd.Value); dd.Value = 0; end
            if restyle
                if numel(app.outStyles) ~= 2
                    app.outStyles = {uistyle('FontWeight','bold','FontColor','black','BackgroundColor',[0.8 1 0.8]), uistyle('FontColor',[0.5 0.5 0.5],'BackgroundColor',[0.9 0.9 0.9])};
                end
                dd.Items = regexprep(dd.Items, '^✓ ?', ''); removeStyle(dd);
                on = find(app.outMask) + 1; dd.Items(on) = append('✓ ', dd.Items(on));
                addStyle(dd, app.outStyles{1}, 'Item', on); addStyle(dd, app.outStyles{2}, 'Item', find([true, ~app.outMask]));
            end
            app.Single_Table_DataOut.Data = T(:, [true, true, app.outMask]);
            app.updateInputVisibility();
        end

        function updateInputVisibility(app)
            % Show only the parameters that influence a currently visible result column.
            columns = string(app.viewTbl.Properties.VariableNames(3:end)); shown = columns(app.outMask); G = app.ParamGroups;
            set(G.rx,   'Visible', any(ismember(shown, ["PLF_dB","Gain_PolCorrected_dB"])));
            set(G.tx,   'Visible', any(ismember(shown, ["EIRP_dBW","PFD_Wm2","E_RMS_Vm"])));
            set(G.dist, 'Visible', any(ismember(shown, ["PFD_Wm2","E_RMS_Vm"])));
            set(G.loss, 'Visible', app.src.meta.isGainOnly || any(ismember(shown, ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","Gain_PolCorrected_dB","EIRP_dBW","PFD_Wm2","E_RMS_Vm"])));
        end

        function updateMetadata(app)
            g = app.gridData(); m = app.metrics; f = @(v) app.fmtNumber(v); [~, ~, ~, thetaLabel] = app.axesConv();
            rows = {
                'Source format', app.src.meta.source
                'File', app.src.fileName
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(app.viewTbl), g.sz(1), g.sz(2))
                [thetaLabel ' range / step'], sprintf('[%s°, %s°] / %s°', f(min(g.thetaDisp)), f(max(g.thetaDisp)), f(gridStep(g.theta)))
                'φ range / step', sprintf('[%s°, %s°] / %s°', f(min(g.phiDisp)), f(max(g.phiDisp)), f(gridStep(g.phi)))};
            validFreq = app.src.freqs(isfinite(app.src.freqs));
            if ~isempty(validFreq), rows(end+1, :) = {'Frequencies', strjoin(compose('%.4g GHz', validFreq / 1e9), ', ')}; end
            if ~app.src.meta.isGainOnly
                rows(end+1, :) = {'Polarization', app.pol.label};
                rows(end+1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(app.pol.pairs.(app.CutFieldBasisDropDown.Value), ' / '))};
            end
            rows = [rows; {
                sprintf('Peak (%s)', app.compLabel()), sprintf('%s dB  @ [θ=%s°, φ=%s°]', f(app.peak.value), f(app.peak.theta), f(app.peak.phi))
                'Peak policy', sprintf('P%.4g, max excess %.4g dB, adjusted: %s', app.PeakPercentile, app.PeakMaxExcessDB, string(app.peak.wasAdjusted))
                'Boresight axis', app.PrincipalAxes.labels{app.boresight}}];
            if isfield(m, 'PeakGain_dB')
                rows = [rows; {
                    'Peak gain (total)', sprintf('%s dB  @ [θ=%s°, φ=%s°]', f(m.PeakGain_dB), f(m.PeakTheta_deg), f(m.PeakPhi_deg))
                    'HPBW E-plane / H-plane', sprintf('%s° / %s°', f(m.HPBW_EPlane_deg), f(m.HPBW_HPlane_deg))
                    'Front-to-back', sprintf('%s dB', f(m.FrontBack_dB))
                    'Peak directivity', sprintf('%s dB', f(m.PeakDirectivity_dB))}];
                if isfinite(m.Efficiency_pct), rows(end+1, :) = {'Radiation efficiency', sprintf('%s%%', f(m.Efficiency_pct))}; end
                if isfinite(m.AxialRatioAtPeak_dB), rows(end+1, :) = {'AR at peak', sprintf('%s dB', f(m.AxialRatioAtPeak_dB))}; end
            end
            app.Single_Table_metadata.Data = rows;
        end

        function text = fmtNumber(~, value, precision)
            % Compact numeric text: up to 2 decimals without trailing zeros, or exactly N decimals when given.
            if ~isscalar(value) || ~isnumeric(value) || ~isfinite(value), text = 'n/a'; return; end
            if abs(value) < 5e-3, value = 0; end
            if nargin < 3, text = regexprep(sprintf('%.2f', value), '\.?0+$', '');
            else, text = sprintf('%.*f', max(0, min(5, round(precision))), value); end
        end
    end

    %% ------------------------------------------------------------------ ranges (full-pattern color scale & cut scale)
    methods (Access = private)
        function setRanges(app, r)
            % Apply one range to the full-pattern plots and the cut plots (component change / refresh / Apply).
            r = clampRange(r, app.HardRange);
            [app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value] = deal(r(1), r(2));
            app.onRange("full", r, 0, false); app.onRange("cut", r, 0, false);
        end

        function onRange(app, scope, value, part, applyNow)
            % Synchronize slider + min/max spinners of one scope. part: 0 = whole range, 1 = min, 2 = max.
            if nargin < 5, applyNow = true; end
            if scope == "full", S = app.FullSpecs; sliders = [S.slider]; mins = [S.min]; maxs = [S.max]; r = sliders(1).Value;
            else, sliders = app.Range_Cut; mins = app.Range_Cut_Min; maxs = app.Range_Cut_Max; r = app.cutLim; end
            if part == 0, r = value; else, r(part) = value; end
            r = clampRange(r, app.HardRange);
            lim = r; if part > 0, old = sliders(1).Limits; lim = [min(old(1), r(1)), max(old(2), r(2))]; end
            set(sliders, 'Limits', app.HardRange, 'Value', r); set(sliders, 'Limits', lim);
            set(mins, 'Limits', [app.HardRange(1), r(2) - 1], 'Value', r(1)); set(maxs, 'Limits', [r(1) + 1, app.HardRange(2)], 'Value', r(2));
            if scope == "full"
                if ~app.isAR(), app.gainLim = r; end
                if applyNow, app.applyFullRange(); end
            else
                app.cutLim = r;
                if applyNow, set(app.Single_paxCut, 'RLim', r); set(app.Single_AxesRect, 'YLim', r); end
            end
        end

        function applyFullRange(app)
            % Push the current full-pattern range (and colorbar tick step) onto every rendered full-pattern axes.
            r = app.FullSpecs(1).slider.Value;
            for k = 1:numel(app.FullSpecs)
                ax = app.FullSpecs(k).axes; clim(ax, r);
                if isequal(ax, app.Single_Axes_3dRect), zlim(ax, r); ax.ZTick = app.axisTicks(r); end
                cb = findall(ancestor(ax, 'figure'), 'Type', 'ColorBar', 'Axes', ax);
                if ~isempty(cb), ticks = app.axisTicks(r); if ~isempty(ticks), cb(1).Ticks = ticks; end, end
            end
        end

        function ticks = axisTicks(app, r)
            step = double(app.Single_Plot_Cstep.Value); ticks = [];
            if ~isfinite(step) || step <= 0 || diff(r) <= 0, return; end
            ticks = unique([r(1), ceil(r(1) / step) * step:step:floor(r(2) / step) * step, r(2)], 'stable');
            if numel(ticks) > 60, ticks = []; end
        end

        function applyTheme(app, ax)
            % Color scale + colormap: signed AR uses a fixed ±30 dB blue-white-red map; gain uses jet over the shared range.
            persistent arMap, if isempty(arMap), arMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
            if app.isAR(), r = [-30 30]; map = arMap; else, r = app.FullSpecs(1).slider.Value; map = jet(256); end
            clim(ax, r); colormap(ax, map); cb = colorbar(ax); ticks = app.axisTicks(r); if ~isempty(ticks), cb.Ticks = ticks; end
        end
    end

    %% ------------------------------------------------------------------ status, busy dialog, errors
    methods (Access = private)
        function setStatus(app, label, message, temporary)
            % Permanent messages become the label's baseline (UserData); temporary ones revert after 3 s.
            if app.isClosing || ~isgraphics(label), return; end
            t = app.statusTimer; if ~isempty(t) && isvalid(t) && strcmp(t.Running, 'on'), stop(t); end
            label.Text = char(message);
            if temporary, start(t); else, label.UserData = char(message); end
        end

        function restoreStatus(app)
            if app.isClosing, return; end
            for label = [app.Single_StatusBar, app.Cov_StatusBar], if ischar(label.UserData), label.Text = label.UserData; end, end
        end

        function cleaner = busy(app, titleText, message, cancelable)
            dlg = uiprogressdlg(app.UIFigure, 'Title', titleText, 'Message', message, 'Indeterminate', 'on', 'Cancelable', cancelable, 'CancelText', 'Abort');
            app.busyDlg = dlg; drawnow;
            cleaner = onCleanup(@() app.endBusy(dlg));
        end

        function endBusy(app, dlg)
            if isequal(app.busyDlg, dlg), app.busyDlg = []; end
            if isvalid(dlg), close(dlg); end
        end

        function checkCancelled(app)
            if ~isempty(app.busyDlg) && isvalid(app.busyDlg) && app.busyDlg.CancelRequested
                app.busyDlg.Message = 'Aborting...'; drawnow limitrate
                error('APAT:Cancelled', 'Operation cancelled by user.');
            end
        end

        function fail(app, ME, titleText, statusLabel)
            % Uniform error path: user cancellation is a status note, everything else is an alert with location.
            if app.isClosing, return; end
            if strcmp(ME.identifier, 'APAT:Cancelled'), app.setStatus(statusLabel, 'Operation cancelled by user.', true); return; end
            where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.UIFigure, [ME.message where], titleText, 'Icon', 'error');
        end
    end

    %% ------------------------------------------------------------------ full-pattern rendering
    methods (Access = private)
        function renderAll(app)
            S = app.FullSpecs;
            for k = 1:numel(S)
                if app.isClosing, return; end
                S(k).render(); app.checkCancelled();
            end
            drawnow limitrate % surfaces must exist before data tips are attached
            app.annotatePOB();
        end

        function drawContour(app)
            g = app.gridData(app.comp()); ax = app.Single_Axes_Ctr; cla(ax);
            C = g.value(:, g.cols);
            s = pcolor(ax, g.phiDisp, g.thetaDisp, C, 'FaceColor', 'interp', 'LineStyle', 'none', 'Tag', 'APAT_Surf');
            s.UserData = [g.phiDisp(app.dispCol(g)), g.thetaDisp(app.peak.row), 0]; % POB location in plotted coordinates
            app.applyTheme(ax); app.formatAngularAxes(ax, 30, 15); daspect(ax, [1 1 1]);
            title(ax, app.compLabel(), 'Interpreter', 'none');
            app.setSurfaceTips(s, g.thetaGridDisp(:, g.cols), g.phiGridDisp(:, g.cols), C);
            app.finishAxes(ax);
        end

        function drawFisheye(app)
            g = app.gridData(app.comp()); pax = app.Single_paxPattern; cla(pax); [~, el] = app.conv();
            s = surface(pax, g.phiRad, g.thetaGrid, zeros(g.sz), g.value, 'EdgeColor', 'none', 'Tag', 'APAT_Surf');
            s.UserData = [g.phiRad(app.peak.row, app.peak.col), g.theta(app.peak.row), 0];
            app.applyTheme(pax); app.setPolarTicks(pax);
            radial = 0:30:180; if el, radial = 90 - radial; end
            set(pax, 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', radial));
            title(pax, sprintf('%s  |  r=θ, angle=φ', app.compLabel()), 'Interpreter', 'none', 'FontSize', 9);
            app.setSurfaceTips(s, g.thetaGridDisp, g.phiGridDisp, g.value);
            app.finishAxes(pax);
        end

        function drawPattern3D(app, ax, kind)
            % kind "sphere": color on the unit sphere; kind "polar": radius scaled by the normalized value.
            g = app.gridData(app.comp()); cla(ax); hold(ax, 'on');
            X = g.x; Y = g.y; Z = g.z;
            if kind == "polar"
                r = app.FullSpecs(1).slider.Value; if app.isAR(), r = [-30 30]; end
                radius = max(g.value - r(1), 0) / max(diff(r), eps); radius = radius / max(max(radius, [], 'all', 'omitnan'), eps);
                X = radius .* X; Y = radius .* Y; Z = radius .* Z;
            end
            s = surf(ax, X, Y, Z, g.value, 'EdgeColor', 'none', 'Tag', 'APAT_Surf');
            s.UserData = [X(app.peak.row, app.peak.col), Y(app.peak.row, app.peak.col), Z(app.peak.row, app.peak.col)];
            app.applyTheme(ax);
            set(ax, 'XDir', 'normal', 'YDir', 'normal', 'ZDir', 'normal', 'Projection', 'orthographic', 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1]);
            axis(ax, 'off'); app.drawXYZ(ax); app.apply3DView(ax, [135 25]);
            if app.Single_CheckBox_overlayCut.Value, app.overlayCut3D(ax, kind); end
            title(ax, sprintf('%s  |  θ: %s  |  φ: %s', app.compLabel(), app.Single_Switch_ThetaSpan.Value, app.Single_Switch_AngularSpan.Value), 'Interpreter', 'none');
            app.setSurfaceTips(s, g.thetaGridDisp, g.phiGridDisp, g.value);
            hold(ax, 'off'); app.finishAxes(ax);
        end

        function drawRect3(app)
            g = app.gridData(app.comp()); ax = app.Single_Axes_3dRect; cla(ax); [~, ~, ~, thetaLabel] = app.axesConv();
            C = g.value(:, g.cols); [P, T] = meshgrid(g.phiDisp, g.thetaDisp);
            s = surf(ax, P, T, C, 'EdgeColor', 'none', 'Tag', 'APAT_Surf');
            c = app.dispCol(g); s.UserData = [g.phiDisp(c), g.thetaDisp(app.peak.row), C(app.peak.row, c)];
            app.applyTheme(ax); r = clim(ax); zlim(ax, r); ax.ZTick = app.axisTicks(r);
            app.formatAngularAxes(ax, 60, 30); grid(ax, 'on');
            xlabel(ax, 'Phi (degree)'); ylabel(ax, [thetaLabel ' (degree)']); zlabel(ax, app.compLabel() + " (dB)", 'Interpreter', 'none');
            app.apply3DView(ax, [-35 35]); title(ax, app.compLabel(), 'Interpreter', 'none');
            app.setSurfaceTips(s, T, P, C);
            app.finishAxes(ax);
        end

        function drawXYZ(~, ax)
            colors = {[0.85 0.1 0.1], [0.1 0.6 0.1], [0.1 0.2 0.9]}; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'}; E = 1.35 * eye(3);
            for k = 1:3
                quiver3(ax, 0, 0, 0, E(k,1), E(k,2), E(k,3), 0, 'Color', colors{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12 * E(k,1), 1.12 * E(k,2), 1.12 * E(k,3), labels{k}, 'Color', colors{k}, 'FontWeight', 'bold');
            end
        end

        function overlayCut3D(app, ax, kind)
            c = app.cutData(); v = c.vals(:, 1);
            if kind == "sphere", radius = 1.02;
            else, r = app.FullSpecs(1).slider.Value; radius = max(v - r(1), 0) / max(diff(r), eps) * 1.01; end
            plot3(ax, radius .* sind(c.theta) .* cosd(c.phi), radius .* sind(c.theta) .* sind(c.phi), radius .* cosd(c.theta), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay');
        end

        function onOverlayChanged(app, ~)
            if isempty(app.viewTbl), return; end
            for spec = [struct('ax', app.Single_Axes_3dSph, 'kind', "sphere"), struct('ax', app.Single_Axes_3dPol, 'kind', "polar")]
                delete(findall(spec.ax, 'Tag', 'APAT_CutOverlay'));
                if app.Single_CheckBox_overlayCut.Value, hold(spec.ax, 'on'); app.overlayCut3D(spec.ax, spec.kind); hold(spec.ax, 'off'); end
            end
        end

        function apply3DView(app, ax, defaultView)
            v = app.Views3D.(app.Single_DropDown_3DView.Value);
            if strcmp(app.Single_DropDown_3DView.Value, 'iso'), v(1:2) = defaultView; end
            view(ax, v(1), v(2)); camup(ax, v(3:5));
        end

        function on3DViewChanged(app, ~)
            if isempty(app.viewTbl), return; end
            app.apply3DView(app.Single_Axes_3dSph, [135 25]); app.apply3DView(app.Single_Axes_3dPol, [135 25]); app.apply3DView(app.Single_Axes_3dRect, [-35 35]);
        end

        function formatAngularAxes(app, ax, phiStep, thetaStep)
            [phiLimits, thetaLimits, thetaDir] = app.axesConv();
            set(ax, 'XLim', phiLimits, 'YLim', thetaLimits, 'YDir', thetaDir, 'Box', 'on', 'Layer', 'top', ...
                'XTick', phiLimits(1):phiStep:phiLimits(2), 'YTick', thetaLimits(1):thetaStep:thetaLimits(2));
        end

        function setPolarTicks(app, pax)
            angles = 0:30:330; [sp, ~] = app.conv(); if sp, angles(angles > 180) = angles(angles > 180) - 360; end
            set(pax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', angles));
        end

        function setSurfaceTips(app, s, thetaGrid, phiGrid, values)
            [~, ~, ~, thetaLabel] = app.axesConv();
            rows = [dataTipTextRow(thetaLabel, thetaGrid, '%.3g°'); dataTipTextRow("Phi", phiGrid, '%.3g°'); dataTipTextRow(replace(app.compLabel(), "_", "\_"), values, '%.3g dB')];
            try, s.DataTipTemplate.DataTipRows = rows; catch, end
        end

        function finishAxes(~, ax)
            % Newly created children inherit the session context menu of their axes.
            set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', ax.ContextMenu);
        end
    end

    %% ------------------------------------------------------------------ annotations (tag based: APAT_POB / APAT_HPBW)
    methods (Access = private)
        function annotatePOB(app)
            % One marker + data tip per full-pattern surface at the POB stored by the renderer (UserData).
            if isempty(app.peak) || ~isfinite(app.peak.value), return; end
            [~, ~, ~, thetaLabel] = app.axesConv(); [sp, el] = app.conv();
            theta = app.peak.theta; phi = app.peak.phi; if el, theta = 90 - theta; end, if sp && phi > 180, phi = phi - 360; end
            rows = [dataTipTextRow(thetaLabel, theta, '%.3g°'); dataTipTextRow("Phi", phi, '%.3g°'); dataTipTextRow(replace(app.compLabel(), "_", "\_"), app.peak.value, '%.3g dB')];
            for k = 1:numel(app.FullSpecs)
                ax = app.FullSpecs(k).axes; s = findobj(ax, 'Tag', 'APAT_Surf');
                if isempty(s) || numel(s(1).UserData) ~= 3, continue; end
                app.addTip(ax, 'APAT_POB', s(1).UserData, rows, app.Single_CheckBox_POB.Value, []);
            end
        end

        function addTip(app, ax, tag, p, rows, visible, tab)
            % Marker + pinned data tip. tab (optional) restricts visibility to one selected cut tab.
            if any(~isfinite(p)), return; end
            held = ishold(ax); hold(ax, 'on');
            try
                if isa(ax, 'matlab.graphics.axis.PolarAxes'), m = polarplot(ax, p(1), p(2), 'ko', 'MarkerSize', 5, 'MarkerFaceColor', 'k', 'HandleVisibility', 'off');
                else, m = plot3(ax, p(1), p(2), p(3), 'ko', 'MarkerSize', 5, 'MarkerFaceColor', 'k', 'HandleVisibility', 'off', 'Clipping', 'off'); end
                m.Tag = tag; m.UserData = tab; m.DataTipTemplate.DataTipRows = rows;
                t = datatip(m, 'DataIndex', 1, 'HandleVisibility', 'off', 'FontSize', 9, 'Tag', tag); t.UserData = tab;
                if isequal(ax, app.Single_Axes_Ctr) && abs(p(2) - ax.YLim(1 + strcmp(ax.YDir, 'normal'))) <= diff(ax.YLim) / 1000
                    if p(1) <= mean(ax.XLim), t.Location = 'southeast'; else, t.Location = 'southwest'; end
                end
                set([m, t], 'Visible', visible);
            catch ME
                if ~app.isClosing, warning('APAT:Annotation', 'Could not create %s annotation: %s', tag, ME.message); end
            end
            if ~held, hold(ax, 'off'); end
        end

        function syncAnnotations(app, ~)
            % Visibility only: POB follows its checkbox; HPBW bounds follow theirs and the selected cut tab.
            set(findall(app.UIFigure, 'Tag', 'APAT_POB'), 'Visible', app.Single_CheckBox_POB.Value);
            for h = findall(app.UIFigure, 'Tag', 'APAT_HPBW')'
                h.Visible = app.Single_CheckBox_HPBWBounds.Value && (isempty(h.UserData) || isequal(h.UserData, app.Single_tabCut.SelectedTab));
            end
        end
    end

    %% ------------------------------------------------------------------ cuts
    methods (Access = private)
        function [cols, idx] = cutCols(app)
            % Total plus the circular or linear pair; idx keeps stable colors per role.
            if app.src.meta.isGainOnly, [cols, idx] = deal(string(app.comp()), 1); return; end
            if strcmp(app.CutFieldBasisDropDown.Value, 'Linear'), all3 = ["E_Total_dB","E_TH_dB","E_PH_dB"]; pair = {'E_TH','E_PH'};
            else, all3 = ["E_Total_dB","E_RCP_dB","E_LCP_dB"]; pair = {'E_RCP','E_LCP'}; end
            [app.CheckBox_Er.Text, app.CheckBox_El.Text] = deal(pair{:});
            sel = logical([app.CheckBox_Et.Value, app.CheckBox_Er.Value, app.CheckBox_El.Value]); if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = all3(idx);
        end

        function [cutType, cutValue] = planeSettings(app, isEPlane)
            % E-plane: theta cut through the boresight azimuth. H-plane: the orthogonal great circle.
            A = app.PrincipalAxes; k = app.boresight; [~, el] = app.conv();
            if isEPlane, cutType = 'Theta'; cutValue = A.phi(k);
            elseif A.theta(k) == 90, cutType = 'Phi'; cutValue = 90 - 90 * el; % transverse boresight: equatorial cut (θ=90° / el=0°)
            else, cutType = 'Theta'; cutValue = 90; end
        end

        function values = updateCutControl(app)
            % Cut value = fixed theta (display convention) for Phi cuts, fixed phi (0..360) for Theta cuts.
            g = app.gridData();
            if strcmp(app.Single_DropDown_cutType.Value, 'Phi'), values = sort(g.thetaDisp); else, values = g.phi(g.phi < 360 - 1e-9); end
            sp = app.Single_DropDown_cutValue; sp.Limits = [min(values), max(values)];
            if numel(values) > 1, sp.Step = min(diff(values)); end
            [~, nearest] = min(abs(values - sp.Value)); sp.Value = values(nearest);
        end

        function c = cutData(app)
            % Active cut as one full circle (display angles) with physical theta/phi per sample.
            T = app.viewTbl; [cols, idx] = app.cutCols(); [sp, el] = app.conv();
            cutType = app.Single_DropDown_cutType.Value; requested = app.Single_DropDown_cutValue.Value;
            if strcmp(cutType, 'Phi') && el, requested = 90 - requested; end
            [ang, rows, fixed, symbol, snapped] = calcCutGeometry(T, cutType, requested);
            if snapped, app.setStatus(app.Single_StatusBar, sprintf('Requested %s cut @ %s=%g° (snapped to nearest %s=%g°)', cutType, symbol, requested, symbol, fixed), true); end
            if sp, ang(ang > 180) = ang(ang > 180) - 360; end
            [ang, order] = sort(ang); rows = rows(order);
            [ang, u] = unique(ang, 'stable'); rows = rows(u);
            if sp && ang(1) > -180 + 1e-9 % close the loop at -180° with the +180° sample
                k = find(abs(ang - 180) < 1e-9, 1); if ~isempty(k), ang = [-180; ang]; rows = [rows(k); rows]; end
            end
            c = struct('ang', ang, 'vals', T{rows, cols}, 'cols', cols, 'idx', idx, 'theta', T.Theta(rows), 'phi', T.Phi(rows), 'type', cutType);
            if app.src.meta.isGainOnly, c.title = char(string(app.comp())); else, c.title = sprintf('%s cut @ %s = %g°', cutType, symbol, fixed); end
        end

        function plotCut(app)
            if isempty(app.viewTbl), return; end
            c = app.cutData(); pax = app.Single_paxCut; rax = app.Single_AxesRect;
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on');
            r = app.cutLim; [xLimits, ~, ~] = app.axesConv();
            polarLines = polarplot(pax, deg2rad(c.ang), max(c.vals, r(1)), 'LineWidth', 1.4); % clamp only the polar display (no reflection spikes)
            rectLines = plot(rax, c.ang, c.vals, 'LineWidth', 1.4);
            colors = rax.ColorOrder(1 + mod(c.idx - 1, size(rax.ColorOrder, 1)), :);
            set(polarLines(:), {'Color'}, num2cell(colors, 2)); set(rectLines(:), {'Color'}, num2cell(colors, 2));
            for k = 1:numel(polarLines)
                rows = [dataTipTextRow("Angle", c.ang, '%.3g°'), dataTipTextRow("Magnitude", c.vals(:, k), '%.3g dB')];
                polarLines(k).DataTipTemplate.DataTipRows = rows; rectLines(k).DataTipTemplate.DataTipRows = rows;
            end
            set(pax, 'RLim', r, 'RTick', r(1):5:r(2)); app.setPolarTicks(pax);
            set(rax, 'YLim', r, 'XLim', xLimits, 'XTick', xLimits(1):30:xLimits(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, [c.type ' (degree)']); title(pax, c.title, 'Interpreter', 'none'); title(rax, c.title, 'Interpreter', 'none');
            % POB of the displayed cut (first curve)
            [cutPeak, kPeak] = max(c.vals(:, 1), [], 'omitnan');
            if isfinite(cutPeak)
                rows = [dataTipTextRow("Angle", c.ang(kPeak), '%.3g°'); dataTipTextRow("Magnitude", cutPeak, '%.3g dB')];
                app.addTip(pax, 'APAT_POB', [deg2rad(c.ang(kPeak)), max(cutPeak, r(1)), 0], rows, app.Single_CheckBox_POB.Value, []);
                app.addTip(rax, 'APAT_POB', [c.ang(kPeak), cutPeak, 0], rows, app.Single_CheckBox_POB.Value, []);
            end
            % HPBW (wrap aware) with optional interpolated boundary tips
            app.Label_HPBW.Text = '';
            if app.Button_HPBW.Value && isfinite(cutPeak)
                [bw, lo, hi] = calcHPBW(c.ang, c.vals(:, 1), cutPeak, c.ang(kPeak));
                if isfinite(bw)
                    if xLimits(1) < 0, b = mod([lo hi] + 180, 360) - 180; else, b = mod([lo hi], 360); end
                    app.Label_HPBW.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                    if b(1) <= b(2), regions = b; else, regions = [xLimits(1), b(2); b(1), xLimits(2)]; end
                    thetaregion(pax, deg2rad(regions(:, 1)), deg2rad(regions(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    xregion(rax, regions(:, 1), regions(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    half = cutPeak - 3; labels = ["Lower HPBW", "Upper HPBW"]; show = app.Single_CheckBox_HPBWBounds.Value;
                    for k = 1:2
                        rows = [dataTipTextRow(labels(k), b(k), '%.2f°'); dataTipTextRow("Gain", half, '%.2f dB')];
                        app.addTip(pax, 'APAT_HPBW', [deg2rad(b(k)), max(half, r(1)), 0], rows, show && app.Single_tabCut.SelectedTab == app.Single_tabPolarPlot, app.Single_tabPolarPlot);
                        app.addTip(rax, 'APAT_HPBW', [b(k), half, 0], rows, show && app.Single_tabCut.SelectedTab == app.Single_tabRectPlot, app.Single_tabRectPlot);
                    end
                end
            end
            names = replace(string(c.cols), "_", "\_"); % legends last so regions/markers never join them
            legend(pax, polarLines, names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rectLines, names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off');
        end

        function onCutChanged(app, event)
            if nargin > 1 && ~isempty(event)
                if event.Source == app.Single_DropDown_cutType, app.updateCutControl();
                elseif event.Source == app.CutFieldBasisDropDown, app.cutBasisAuto = false; app.updateMetadata(); end
            end
            show = app.Button_HPBW.Value; app.Single_CheckBox_HPBWBounds.Visible = show;
            if ~show, app.Single_CheckBox_HPBWBounds.Value = false; end
            app.plotCut();
            if app.Single_CheckBox_overlayCut.Value, app.onOverlayChanged(); end
        end

        function onEHPlaneChanged(app, ~)
            [cutType, cutValue] = app.planeSettings(startsWith(app.Single_Switch_EHplane.Value, 'E'));
            app.Single_DropDown_cutType.Value = cutType;
            values = app.updateCutControl(); [~, k] = min(abs(values - cutValue)); app.Single_DropDown_cutValue.Value = values(k);
            app.onCutChanged();
        end
    end

    %% ------------------------------------------------------------------ export
    methods (Access = private)
        function exportTable(app, T, filters, defaultName, label, statusLabel)
            [f, p] = uiputfile(filters, label, fullfile(app.srcField('folderPath'), defaultName));
            if isequal(f, 0), return; end
            try
                fp = fullfile(p, f);
                if endsWith(fp, '.uan', 'IgnoreCase', true), writeUAN(T, fp);
                elseif endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t');
                else, writetable(T, fp); end
                app.setStatus(statusLabel, [label ' written to <b>' fp '</b>'], true);
            catch ME
                app.fail(ME, 'Export Error', statusLabel);
            end
        end

        function exportResults(app, ~)
            if isempty(app.viewTbl), return; end
            app.exportTable(app.Single_Table_DataOut.Data, {'*.csv','CSV (*.csv)'; '*.txt','Tab-delimited (*.txt)'; '*.xlsx','Excel (*.xlsx)'}, ...
                [app.src.baseName '_APAT_results.csv'], 'Results', app.Single_StatusBar);
        end

        function exportCut(app, ~)
            if isempty(app.viewTbl), return; end
            c = app.cutData();
            app.exportTable(array2table([c.ang, c.vals], 'VariableNames', [{'Angle_deg'}, cellstr(c.cols)]), ...
                {'*.csv','CSV (*.csv)'; '*.txt','Tab-delimited (*.txt)'}, [app.src.baseName '_cut.csv'], ['Cut (' c.title ')'], app.Single_StatusBar);
        end

        function exportUAN(app, ~)
            % Canonical physical grid (theta 0..180, phi 0..360) in XGTD magnitude/phase form.
            if app.src.meta.isGainOnly, uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            T = app.viewTbl;
            U = sortrows(table(T.Theta, T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta','Phi','E_TH_DB','E_PH_DB','E_TH_DG','E_PH_DG'}), {'Phi', 'Theta'});
            step = gridStep(U.Theta); if ~isfinite(step), step = 1; end
            peakDB = max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan');
            app.exportTable(U, {'*.uan','XGTD user-defined antenna (*.uan)'; '*.csv','CSV (*.csv)'; '*.txt','Tab-delimited (*.txt)'}, ...
                sprintf('%s_%.5f_%gdeg.uan', app.src.baseName, peakDB, step), 'UAN', app.Single_StatusBar);
        end
    end

    %% ------------------------------------------------------------------ coverage: model (tree nodes are the single source of truth)
    methods (Access = private)
        function node = covPatternTarget(app)
            % Selected pattern node (or the pattern owning the selected job); otherwise the newest pattern.
            node = []; n = app.Cov_Tree.SelectedNodes;
            while ~isempty(n) && isa(n(1), 'matlab.ui.container.TreeNode')
                if app.nodeKind(n(1)) == "pattern", node = n(1); return; end
                n = n(1).Parent;
            end
            kids = app.Cov_TreeNode_Results.Children;
            for k = numel(kids):-1:1, if app.nodeKind(kids(k)) == "pattern", node = kids(k); return; end, end
        end

        function kind = nodeKind(~, node)
            kind = ""; if isstruct(node.NodeData) && isfield(node.NodeData, 'kind'), kind = string(node.NodeData.kind); end
        end

        function node = covFindByPath(app, fp)
            node = []; kids = app.Cov_TreeNode_Results.Children;
            for k = 1:numel(kids)
                if isstruct(kids(k).NodeData) && isfield(kids(k).NodeData, 'path') && strcmp(kids(k).NodeData.path, fp), node = kids(k); return; end
            end
        end

        function jobs = covJobs(app, roots, checkedOnly)
            % Job nodes (optionally below given roots / only checked ones), ordered by run id.
            if nargin < 2 || isempty(roots), roots = app.Cov_TreeNode_Results; end
            nodes = findobj(roots); nodes = nodes(arrayfun(@(n) isa(n, 'matlab.ui.container.TreeNode') && app.nodeKind(n) == "job", nodes));
            jobs = reshape(nodes, 1, []);
            if nargin > 2 && checkedOnly, jobs = jobs(ismember(jobs, app.Cov_Tree.CheckedNodes)); end
            if numel(jobs) > 1, [~, order] = sort(arrayfun(@(n) n.NodeData.id, jobs)); jobs = jobs(order); end
        end

        function node = covAddPattern(app, name, T, fp)
            % T is a canonical processed table; weights are derived here so every consumer shares them.
            node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', "pattern", 'name', name, 'path', fp, 'tbl', T, 'dOmega', solidWeights(T.Theta, T.Phi), 'component', "", 'boresight', 1);
            expand(app.Cov_Tree);
            [app.Cov_Tree.CheckedNodes, app.Cov_Tree.SelectedNodes] = deal([app.Cov_Tree.CheckedNodes; node], node);
            app.syncCoveragePattern(node); app.setCoverageUI();
            app.setStatus(app.Cov_StatusBar, sprintf('Pattern "<b>%s</b>" added %s ready to compute coverage.', name, char(8212)), false);
        end

        function syncCoveragePattern(app, node)
            % Align the component dropdown, boresight detection and the threshold preset with this pattern.
            d = node.NodeData; [columns, labels] = app.componentMap(d.tbl); dd = app.Cov_DropDown_Component;
            if strlength(d.component) > 0, previous = d.component; else, previous = string(dd.Value); end
            component = app.preferredComponent(previous, columns);
            if ~isequal(string(dd.ItemsData), columns), [dd.Items, dd.ItemsData] = deal(cellstr(labels), cellstr(columns)); end
            dd.Value = component;
            if d.component ~= string(component)
                [~, d.boresight] = calcOrientation(d.tbl, d.dOmega, component, app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
                d.component = string(component); node.NodeData = d;
                if app.Cov_DropDown_Orientation.Value == 0, app.onOrientationChanged(); end
            end
            key = string(d.path) + "|" + component;
            if app.covPresetKey ~= key % thresholds are preset once per pattern/component; user edits persist afterwards
                app.covPresetKey = key; w = peakWindow(d.tbl.(component), [-40 10], app.PeakPercentile, app.PeakMaxExcessDB);
                app.Cov_Spinner_ThreshMin.Limits = [app.HardRange(1), w(2) - 0.1]; app.Cov_Spinner_ThreshMax.Limits = [w(1) + 0.1, app.HardRange(2)];
                [app.Cov_Spinner_ThreshMin.Value, app.Cov_Spinner_ThreshMax.Value] = deal(w(1), w(2));
            end
        end

        function thresholds = covThresholds(app)
            tMin = app.Cov_Spinner_ThreshMin.Value; tMax = app.Cov_Spinner_ThreshMax.Value; step = max(app.Cov_Spinner_Step.Value, 0.1);
            if tMax <= tMin, tMax = min(app.HardRange(2), tMin + step); app.Cov_Spinner_ThreshMax.Value = tMax; end
            thresholds = (tMin:step:tMax)'; if thresholds(end) < tMax, thresholds(end+1) = tMax; end
        end

        function jobNode = covAddJob(app, parentNode, thresholds, coverage, tag, componentName, extra)
            % Register one coverage curve as a tree node; NodeData carries everything the UI needs.
            app.covRunID = app.covRunID + 1; icon = '📉'; if strcmp(tag, 'Sph') || strcmp(tag, 'Res'), icon = '📈'; end
            label = sprintf('%s R%d %s %s %s', icon, app.covRunID, extra.displayTag, char(183), componentName);
            curve = plot(app.Cov_Axes, thresholds, coverage, 'LineWidth', 1.6, 'DisplayName', label);
            jobNode = uitreenode(parentNode, 'Text', label);
            jobNode.NodeData = struct('kind', "job", 'id', app.covRunID, 'tag', tag, 'thr', thresholds(:), 'cov', coverage(:), 'line', curve, 'label', label, ...
                'tableTag', extra.tableTag, 'orientationLabel', extra.orientationLabel);
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; jobNode];
        end

        function finalizeCoverageJobs(app, ~)
            % Curve visibility, legend and results table all follow the tree's checked state.
            expand(app.Cov_TreeNode_Results); jobs = app.covJobs(); checked = app.covJobs([], true);
            if ~isempty(jobs), expand(unique([jobs.Parent])); end
            for j = jobs
                on = ismember(j, checked); set(j.NodeData.line, 'Visible', on);
                set([findall(app.Cov_Axes, 'Tag', app.queryTag(j.NodeData.id)); findall(j.NodeData.line, 'Type', 'datatip')], 'Visible', on);
            end
            thresholds = app.covThresholds(); n = numel(checked); lines = gobjects(1, n); labels = cell(1, n);
            if n > 0, cells = arrayfun(@(j) j.NodeData.thr, checked, 'UniformOutput', false); thresholds = unique(vertcat(cells{:})); end
            values = nan(numel(thresholds), n + 1); values(:, 1) = thresholds; names = [{'Threshold (dB)'}, cell(1, n)];
            for k = 1:n
                d = checked(k).NodeData; lines(k) = d.line; labels{k} = d.label;
                values(:, k + 1) = interp1(d.thr, d.cov, thresholds, 'linear', NaN); names{k + 1} = sprintf('R%d %s %%', d.id, d.tableTag);
            end
            if n > 0, legend(app.Cov_Axes, lines, labels, 'Location', 'southwest', 'Interpreter', 'none'); else, legend(app.Cov_Axes, 'off'); end
            app.Cov_Table.Data = array2table(compose('%.2f', values), 'VariableNames', names);
            app.setCoverageUI();
        end

        function tag = queryTag(~, id), tag = sprintf('CovQ_%d', id); end

        function setCoverageUI(app)
            % Enable state follows the model: a pattern node unlocks computation, jobs unlock results tooling.
            hasPattern = ~isempty(app.covPatternTarget()); hasJobs = ~isempty(app.covJobs()); conical = app.Cov_ButtonGroup_Btn_Conical.Value; G = app.CovGroups;
            set(G.pattern, 'Enable', hasPattern); set(G.cone, 'Enable', hasPattern && conical, 'Visible', conical);
            set(G.query, 'Enable', hasJobs); set(G.results, 'Enable', hasJobs);
            app.Cov_Button_Reset.Enable = hasPattern || hasJobs; app.Cov_Panel_Results.Visible = hasPattern || hasJobs;
            set([app.Cov_TextFormatLabel, app.Cov_DropDown_TextFormat], 'Visible', hasPattern && app.isGenericTextFile(app.Cov_EditField_filePath.Value));
        end

        function covXRange(app, r, fromSlider)
            % Plot X range: spinners are the master (they define slider travel); the slider only selects within it.
            if app.covSyncing || app.isClosing, return; end
            app.covSyncing = true; cleaner = onCleanup(@() app.clearCovSync()); %#ok<NASGU>
            r = clampRange(r, app.HardRange); sl = app.Cov_Spinner_XRange;
            if ~fromSlider, set(sl, 'Limits', app.HardRange, 'Value', r); sl.Limits = r; end
            set(app.Cov_Spinner_XMin, 'Limits', [app.HardRange(1), r(2) - 0.1], 'Value', r(1)); set(app.Cov_Spinner_XMax, 'Limits', [r(1) + 0.1, app.HardRange(2)], 'Value', r(2));
            app.Cov_Axes.XLimMode = 'manual'; app.Cov_Axes.XLim = r;
        end

        function clearCovSync(app), if ~app.isClosing, app.covSyncing = false; end, end

        function onCovXRange(app, event)
            if isequal(event.Source, app.Cov_Spinner_XRange), app.covXRange(sort(event.Value), true);
            else, app.covXRange([app.Cov_Spinner_XMin.Value, app.Cov_Spinner_XMax.Value], false); end
        end

        function covExtendPlotRange(app, thresholds)
            % First result establishes the X baseline; later results may only widen it automatically.
            r = [min(thresholds), max(thresholds)];
            if app.covPlotInit, r = [min(app.Cov_Axes.XLim(1), r(1)), max(app.Cov_Axes.XLim(2), r(2))]; end
            app.covPlotInit = true; app.covXRange(r, false);
            step = gridStep(thresholds); if isfinite(step) && step < app.Cov_Spinner_Step.Value, app.Cov_Spinner_Step.Value = step; end
        end
    end

    %% ------------------------------------------------------------------ coverage: actions
    methods (Access = private)
        function Single_Button_CoveragePushed(app, ~)
            % Coverage is always fed from the current Main view table (loss, step, component derivation included).
            if isempty(app.viewTbl), uialert(app.UIFigure, 'No processed view is available. Load and process a pattern first.', 'Coverage'); return; end
            [app.TabGroup.SelectedTab, app.Cov_EditField_filePath.Value] = deal(app.Tab2_Coverage, app.src.filePath);
            node = app.covFindByPath(app.src.filePath);
            if isempty(node), app.covAddPattern(app.src.baseName, app.viewTbl, app.src.filePath);
            else, app.Cov_Tree.SelectedNodes = node; app.covSyncFromView(node); app.setCoverageUI(); end
            app.setStatus(app.Cov_StatusBar, 'Coverage source synchronized from the current Main-tab view.', false);
        end

        function covSyncFromView(app, node)
            d = node.NodeData; d.tbl = app.viewTbl; d.dOmega = app.dOmega; d.component = ""; node.NodeData = d;
            app.syncCoveragePattern(node);
        end

        function Cov_Button_LoadPushed(app, ~)
            fp = strtrim(app.Cov_EditField_filePath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFindByPath(fp))
                fp = app.browse('Select a pattern or coverage results file', fp); if isempty(fp), return; end
            end
            existing = app.covFindByPath(fp);
            if ~isempty(existing)
                app.Cov_Tree.SelectedNodes = existing; app.Cov_TreeSelectionChanged(); app.setCoverageUI();
                app.setStatus(app.Cov_StatusBar, 'File already loaded -- node selected.', true); return
            end
            app.Cov_EditField_filePath.Value = fp;
            try
                out = app.prepareTextFormat(fp, app.Cov_TextFormatLabel, app.Cov_DropDown_TextFormat);
                if out.meta.isCoverage
                    patternNode = app.covPatternTarget(); if ~isempty(patternNode), app.Cov_EditField_filePath.Value = patternNode.NodeData.path; end
                    app.covLoadResults(fp, out.rawTbl);
                else
                    [~, pattern] = app.buildPatternData(out); [~, name] = fileparts(fp);
                    app.covAddPattern(name, pattern, fp);
                end
            catch ME
                app.fail(ME, 'Coverage Load Error', app.Cov_StatusBar);
            end
        end

        function onCovTextFormatChanged(app, ~)
            % Re-interpret an existing generic coverage-pattern node with the newly selected format.
            fp = strtrim(app.Cov_EditField_filePath.Value); old = app.covFindByPath(fp);
            if isempty(old) || ~app.isGenericTextFile(fp), return; end
            try
                out = app.readFile(fp, app.Cov_DropDown_TextFormat.Value);
                if out.meta.isCoverage, app.setStatus(app.Cov_StatusBar, 'Coverage-result files are detected automatically.', true); return; end
                [~, pattern] = app.buildPatternData(out); name = old.NodeData.name;
                for j = app.covJobs(old), delete(j.NodeData.line); end
                delete(old); app.covAddPattern(name, pattern, fp); app.finalizeCoverageJobs();
                app.setStatus(app.Cov_StatusBar, sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
            catch ME
                app.fail(ME, 'Coverage Format Error', app.Cov_StatusBar);
            end
        end

        function covLoadResults(app, fp, R)
            [~, name] = fileparts(fp);
            node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📄 ' name]); node.NodeData = struct('kind', "results", 'name', name, 'path', fp);
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node];
            thresholds = R{:, 1}; extra = struct('displayTag', 'Res', 'tableTag', 'Res', 'orientationLabel', "n/a");
            for k = 2:width(R), app.covAddJob(node, thresholds, R{:, k}, 'Res', R.Properties.VariableNames{k}, extra); end
            app.covExtendPlotRange(thresholds); app.finalizeCoverageJobs();
            app.setStatus(app.Cov_StatusBar, sprintf('Coverage results file "%s" loaded (%d curves).', name, width(R) - 1), false);
        end

        function Cov_Button_computeCovPushed(app, ~)
            node = app.covPatternTarget();
            if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if ~isempty(app.viewTbl) && strcmp(node.NodeData.path, app.srcField('filePath')), app.covSyncFromView(node); end % Main patterns track the live view
            try
                d = node.NodeData; T = d.tbl; comp = app.Cov_DropDown_Component.Value; thresholds = app.covThresholds();
                conical = app.Cov_ButtonGroup_Btn_Conical.Value; mask = true(height(T), 1);
                extra = struct('displayTag', 'Sph coverage', 'tableTag', 'Sph', 'orientationLabel', "n/a"); tag = 'Sph';
                if conical
                    k = app.Cov_DropDown_Orientation.Value; if k == 0, k = d.boresight; end
                    extra.orientationLabel = string(app.PrincipalAxes.labels{k});
                    th0 = app.Cov_Spinner_ConeTH.Value; ph0 = mod(app.Cov_Spinner_ConePH.Value, 360); alpha = app.Cov_Spinner_ConeAng.Value;
                    mask = cosd(T.Theta) * cosd(th0) + sind(T.Theta) * sind(th0) .* cosd(T.Phi - ph0) >= cosd(alpha);
                    center = app.coneCenterLabel(th0, ph0); tag = sprintf('Con_%.15g_%.15g_%.15g', th0, ph0, alpha);
                    extra.displayTag = sprintf('Conical coverage (%s) α=%s°', center, app.fmtNumber(alpha));
                    extra.tableTag = sprintf('Con %s α%s°', erase(center, ["=", ","]), app.fmtNumber(alpha));
                end
                coverage = coverageCCDF(T.(comp), mask, thresholds, d.dOmega);
                app.covAddJob(node, thresholds, coverage, tag, comp, extra);
                app.covExtendPlotRange(thresholds); app.finalizeCoverageJobs();
                statusText = sprintf('Run-<b>%d</b> computed: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', app.covRunID, extra.displayTag, d.name, comp, numel(thresholds));
                if conical, statusText = sprintf('%s | Orientation <b>%s</b>', statusText, extra.orientationLabel); end
                app.setStatus(app.Cov_StatusBar, statusText, false);
            catch ME
                app.fail(ME, 'Coverage Error', app.Cov_StatusBar);
            end
        end

        function label = coneCenterLabel(app, theta, phi)
            % Principal-axis name when the cone center coincides with ±X/±Y/±Z, otherwise the coordinates.
            A = app.PrincipalAxes; c = [sind(theta) * cosd(phi), sind(theta) * sind(phi), cosd(theta)];
            axesXYZ = [sind(A.theta(:)) .* cosd(A.phi(:)), sind(A.theta(:)) .* sind(A.phi(:)), cosd(A.theta(:))];
            k = find(axesXYZ * c(:) >= 1 - 1e-9, 1);
            if isempty(k), label = sprintf('θ=%s°, φ=%s°', app.fmtNumber(theta), app.fmtNumber(phi)); else, label = string(A.labels{k}); end
        end

        function Cov_Button_ResetPushed(app, ~)
            delete(app.Cov_TreeNode_Results.Children);
            cla(app.Cov_Axes); legend(app.Cov_Axes, 'off'); hold(app.Cov_Axes, 'on'); grid(app.Cov_Axes, 'on'); ylim(app.Cov_Axes, [0 100]);
            app.Cov_Table.Data = table(); app.covRunID = 0; app.covPresetKey = ""; app.covPlotInit = false;
            app.Cov_Axes.XLimMode = 'auto'; app.covXRange([-40 10], false); app.Cov_Axes.XLimMode = 'auto';
            app.setCoverageUI(); app.setStatus(app.Cov_StatusBar, 'Coverage workspace reset 🔄', true);
        end

        function Cov_Button_ClearPushed(app, ~)
            % Remove query markers and data tips of the selected subtree (checked state is ignored on purpose).
            sel = app.Cov_Tree.SelectedNodes;
            if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to clear.', true); return; end
            jobs = app.covJobs(sel);
            for j = jobs, delete([findall(app.Cov_Axes, 'Tag', app.queryTag(j.NodeData.id)); findall(j.NodeData.line, 'Type', 'datatip')]); end
            app.setStatus(app.Cov_StatusBar, 'Selected DataTips and query markers cleared.', true);
        end

        function Cov_Button_ExportPushed(app, ~)
            if isempty(app.Cov_Table.Data), return; end
            app.exportTable(app.Cov_Table.Data, {'*.csv','CSV (*.csv)'; '*.txt','Tab-delimited (*.txt)'; '*.xlsx','Excel (*.xlsx)'}, 'coverage_results.csv', 'Coverage results', app.Cov_StatusBar);
        end

        function onCovTypeChanged(app, ~)
            app.setCoverageUI();
            if app.Cov_ButtonGroup_Btn_Conical.Value
                node = app.covPatternTarget(); if ~isempty(node), app.syncCoveragePattern(node); end
                app.reportOrientation();
            else
                app.Cov_StatusBar.Text = regexprep(app.Cov_StatusBar.Text, '\s*\|\s*Orientation <b>.*?</b>', '');
            end
        end

        function reportOrientation(app)
            % Append the resolved conical orientation (Auto -> detected boresight) to the current status.
            if ~app.Cov_ButtonGroup_Btn_Conical.Value, return; end
            k = app.Cov_DropDown_Orientation.Value; node = app.covPatternTarget();
            if k == 0, if isempty(node), return; end, k = node.NodeData.boresight; end
            base = regexprep(app.Cov_StatusBar.Text, '\s*\|\s*Orientation <b>.*?</b>$', '');
            app.setStatus(app.Cov_StatusBar, sprintf('%s | Orientation <b>%s</b>', base, app.PrincipalAxes.labels{k}), false);
        end

        function onOrientationChanged(app, ~)
            % Auto resolves the detected boresight; an explicit axis is authoritative and pre-fills the cone center.
            k = app.Cov_DropDown_Orientation.Value; node = app.covPatternTarget();
            if k == 0, if isempty(node), return; end, k = node.NodeData.boresight; end
            [app.Cov_Spinner_ConeTH.Value, app.Cov_Spinner_ConePH.Value] = deal(app.PrincipalAxes.theta(k), app.PrincipalAxes.phi(k));
            app.reportOrientation();
        end

        function onCovComponentChanged(app, ~)
            node = app.covPatternTarget(); if isempty(node), return; end
            d = node.NodeData; component = string(app.Cov_DropDown_Component.Value);
            if ~ismember(component, string(d.tbl.Properties.VariableNames)), return; end
            [~, d.boresight] = calcOrientation(d.tbl, d.dOmega, component, app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
            d.component = component; node.NodeData = d;
            app.syncCoveragePattern(node); app.reportOrientation();
        end

        function covRunQuery(app, mode)
            % mode "cov": coverage at a threshold (x -> y). mode "thr": threshold reaching a coverage (y -> x).
            ax = app.Cov_Axes; sel = app.Cov_Tree.SelectedNodes;
            if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to query.', true); return; end
            jobs = app.covJobs(sel, true);
            if isempty(jobs), app.setStatus(app.Cov_StatusBar, 'No checked results under the selected node.', true); return; end
            if mode == "cov", q = app.Cov_Spinner_queryCov.Value; else, q = app.Cov_Spinner_queryThresh.Value; end
            rows = [dataTipTextRow("Threshold", @(x, ~) reshape(compose('%.2f dB', x(:)), size(x))); dataTipTextRow("Coverage", @(~, y) reshape(compose('%.2f%%', y(:)), size(y)))];
            hit = false;
            for j = jobs
                d = j.NodeData; tag = app.queryTag(d.id); [x, y] = coverageQuery(d.thr, d.cov, mode, q);
                if ~isfinite(x) || ~isfinite(y), continue; end
                delete(findall(ax, 'Tag', tag)); delete(findall(d.line, 'Tag', tag));
                try, d.line.DataTipTemplate.DataTipRows = rows; catch, end
                line(ax, [x x], [ax.YLim(1) y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [app.HardRange(1) x], [y y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'HandleVisibility', 'off', 'FontSize', 9, 'Tag', tag);
                hit = true;
            end
            if ~hit, app.setStatus(app.Cov_StatusBar, 'Query value is outside the selected checked range.', true);
            elseif mode == "cov", app.setStatus(app.Cov_StatusBar, sprintf('Coverage queried at %s dB.', app.fmtNumber(q)), false);
            else, app.setStatus(app.Cov_StatusBar, sprintf('Threshold queried at %s%% coverage.', app.fmtNumber(q)), false); end
        end

        function Cov_TreeSelectionChanged(app, ~)
            sel = app.Cov_Tree.SelectedNodes; jobs = app.covJobs();
            for j = jobs, set(j.NodeData.line, 'LineWidth', 1.6 + isequal(j, sel)); end % visual emphasis only
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(app.Cov_StatusBar, 'Ready.', false); return; end
            d = sel(1).NodeData; patternNode = app.covPatternTarget();
            if ~isempty(patternNode), app.syncCoveragePattern(patternNode); end
            if d.kind ~= "job"
                n = numel(sel(1).Children); kind = "Pattern"; if d.kind == "results", kind = "Results"; end
                app.setStatus(app.Cov_StatusBar, sprintf('%s <b>"%s"</b> -- <b>%d</b> coverage job%s.', kind, d.name, n, repmat('s', 1, n ~= 1)), false);
                if d.kind == "pattern", app.reportOrientation(); end
                return
            end
            [t50, ~] = coverageQuery(d.thr, d.cov, "thr", 50); f = @(v) app.fmtNumber(v);
            shown = round(d.cov, 2); [cMax, kMax] = max(shown); kMax = find(shown == cMax, 1, 'last');
            parts = {char(d.label)};
            if d.orientationLabel ~= "n/a", parts{end+1} = sprintf('Orientation <b>%s</b>', d.orientationLabel); end
            parts{end+1} = sprintf('Threshold [%s, %s] dB, step %s dB', f(d.thr(1)), f(d.thr(end)), f(gridStep(d.thr)));
            if isfinite(t50), parts{end+1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', f(t50)); else, parts{end+1} = '<b>50%-coverage unavailable</b>'; end
            parts{end+1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', f(cMax), f(d.thr(kMax)));
            app.setStatus(app.Cov_StatusBar, strjoin(parts, ' | '), false);
        end
    end

    %% ------------------------------------------------------------------ UI construction
    methods (Access = private)
        function h = at(~, h, row, col)
            % Place a component in its grid cell and return it (keeps construction one line per control).
            h.Layout.Row = row; h.Layout.Column = col;
        end

        function lbl = label(app, parent, text, row, col, varargin)
            lbl = app.at(uilabel(parent, 'Text', text, 'HorizontalAlignment', 'right', varargin{:}), row, col);
        end

        function dd = textFormatDropdown(~, parent)
            dd = uidropdown(parent, 'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
                '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'}, ...
                'Value', 'gain', 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'Visible', 'off');
        end

        function [ax, slider, mn, mx] = patternTab(app, tabGroup, tabTitle, kind)
            % One full-pattern tab: vertical range slider + min/max spinners on the left, axes on the right.
            g = uigridlayout(uitab(tabGroup, 'Title', tabTitle), 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
            switch kind
                case "polar", ax = polaraxes(g); set(ax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
                otherwise,    ax = uiaxes(g); ax.Box = 'on';
            end
            app.at(ax, [1 3], 2);
            slider = app.at(uislider(g, 'range', 'Limits', app.HardRange, 'Value', app.HardRange, 'Orientation', 'vertical', 'Step', 1), 2, 1);
            mx = app.at(uispinner(g, 'Limits', app.HardRange, 'Value', app.HardRange(2), 'Step', 5), 1, 1);
            mn = app.at(uispinner(g, 'Limits', app.HardRange, 'Value', app.HardRange(1), 'Step', 5), 3, 1);
        end

        function createComponents(app)
            cb = @(fcn) createCallbackFcn(app, fcn, true);
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.ReleaseName], 'Visible', 'off', 'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', cb(@closeRequest));
            app.TabGroup = uitabgroup(uigridlayout(app.UIFigure, [1 1]));
            app.Tab1_Single = uitab(app.TabGroup, 'Title', 'Process Pattern 📡');
            app.Tab2_Coverage = uitab(app.TabGroup, 'Title', 'Compute Coverage 📈');

            % ---------------- Main tab layout: params (row 1) | full pattern + cut + plot control (rows 2-3) | tables (row 4) | status (row 5)
            G = uigridlayout(app.Tab1_Single, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});
            P = uigridlayout(app.at(uipanel(G, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 14]), 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            app.label(P, 'Input Pattern:', 1, 1);
            app.Single_EditField_Path = app.at(uieditfield(P, 'text'), 1, [2 8]);
            app.FFDFreqDropDownLabel = app.label(P, 'FFD Freq:', 1, 9, 'Visible', 'off');
            app.Single_DropDown_FFD = app.at(uidropdown(P, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', cb(@onFFDChanged)), 1, 10);
            app.Single_Button_Load = app.at(uibutton(P, 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', cb(@onLoad)), 1, [11 12]);
            app.Single_Button_Process = app.at(uibutton(P, 'Text', '⚙️ Process', 'ButtonPushedFcn', cb(@onProcess)), 1, [13 14]);
            app.Single_Button_ResetParams = app.at(uibutton(P, 'Text', 'Reset Params', 'ButtonPushedFcn', cb(@resetParams)), 2, [1 3]);
            app.TextFormatLabel = app.label(P, 'Format:', 2, [4 5], 'Visible', 'off');
            app.Single_DropDown_TextFormat = app.at(app.textFormatDropdown(P), 2, [6 8]); app.Single_DropDown_TextFormat.ValueChangedFcn = cb(@onTextFormatChanged);
            app.Single_DropDown_step = app.at(uidropdown(P, 'Items', {'STEP', 'STEP: 1°'}, 'Visible', 'off', 'Enable', 'off', 'ValueChangedFcn', cb(@stepChanged)), 2, [9 10]);
            app.Single_Export_Output = app.at(uibutton(P, 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@exportResults)), 2, [11 12]);
            app.Single_Export_UAN = app.at(uibutton(P, 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@exportUAN)), 2, [13 14]);
            rxL = app.label(P, 'Rw Sense', 3, 1);   app.Single_DropDown_RxPol = app.at(uidropdown(P, 'Items', {'Auto', 'RHCP', 'LHCP'}), 3, 2);
            rwL = app.label(P, 'Rw (dB)', 3, 3);    app.Single_Spinner_Rw = app.at(uispinner(P, 'Value', 6), 3, 4);
            lossL = app.label(P, 'Loss (−) / Gain (+) dB', 3, 5); app.Single_Spinner_Loss = app.at(uispinner(P, 'Step', 0.1), 3, 6);
            ptL = app.label(P, 'Tx Pwr (Pt)', 3, 7); app.Single_Spinner_Pt = app.at(uispinner(P), 3, 8); app.Single_DropDown_Pt = app.at(uidropdown(P, 'Items', {'dBW', 'dBm', 'Watts'}), 3, 9);
            rL = app.label(P, 'Distance', 3, 10);   app.Single_Spinner_R = app.at(uispinner(P, 'Value', 1), 3, 11); app.Single_DropDown_R = app.at(uidropdown(P, 'Items', {'m', 'km'}), 3, 12);
            app.Single_Button_Coverage = app.at(uibutton(P, 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@Single_Button_CoveragePushed)), 3, [13 14]);
            app.ParamGroups = struct('rx', [rxL, app.Single_DropDown_RxPol, rwL, app.Single_Spinner_Rw], 'tx', [ptL, app.Single_Spinner_Pt, app.Single_DropDown_Pt], ...
                'dist', [rL, app.Single_Spinner_R, app.Single_DropDown_R], 'loss', [lossL, app.Single_Spinner_Loss]);
            set([app.ParamGroups.rx, app.ParamGroups.tx, app.ParamGroups.dist, app.ParamGroups.loss], 'Visible', 'off');

            % full-pattern panel
            app.Single_Panel_fullPattern = app.at(uipanel(G, 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [1 6]);
            app.Single_tabPlots = uitabgroup(uigridlayout(app.Single_Panel_fullPattern, [1 1]));
            [app.Single_Axes_Ctr, s1, n1, x1] = app.patternTab(app.Single_tabPlots, 'Contour Plot', "rect");
            [app.Single_paxPattern, s2, n2, x2] = app.patternTab(app.Single_tabPlots, 'Circular Contour Plot', "polar");
            [app.Single_Axes_3dSph, s3, n3, x3] = app.patternTab(app.Single_tabPlots, '3D Spherical Plot', "rect");
            [app.Single_Axes_3dPol, s4, n4, x4] = app.patternTab(app.Single_tabPlots, '3D Polar Plot', "rect");
            [app.Single_Axes_3dRect, s5, n5, x5] = app.patternTab(app.Single_tabPlots, '3D Surface Plot', "rect");
            app.FullSpecs = struct('name', {'contour', 'circular', 'sphere3D', 'polar3D', 'rect3D'}, ...
                'axes', {app.Single_Axes_Ctr, app.Single_paxPattern, app.Single_Axes_3dSph, app.Single_Axes_3dPol, app.Single_Axes_3dRect}, ...
                'slider', {s1, s2, s3, s4, s5}, 'min', {n1, n2, n3, n4, n5}, 'max', {x1, x2, x3, x4, x5}, ...
                'render', {@() app.drawContour(), @() app.drawFisheye(), @() app.drawPattern3D(app.Single_Axes_3dSph, "sphere"), @() app.drawPattern3D(app.Single_Axes_3dPol, "polar"), @() app.drawRect3()});
            set([app.FullSpecs.slider], 'ValueChangedFcn', @(s, ~) app.onRange("full", s.Value, 0));
            set([app.FullSpecs.min], 'ValueChangedFcn', @(s, ~) app.onRange("full", s.Value, 1));
            set([app.FullSpecs.max], 'ValueChangedFcn', @(s, ~) app.onRange("full", s.Value, 2));

            % cut panel
            app.Single_Panel_Rect = app.at(uipanel(G, 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [7 12]);
            app.Single_tabCut = uitabgroup(uigridlayout(app.Single_Panel_Rect, [1 1]), 'SelectionChangedFcn', @(~, ~) app.syncAnnotations());
            app.Single_tabPolarPlot = uitab(app.Single_tabCut, 'Title', 'Polar Cut Plot');
            C = uigridlayout(app.Single_tabPolarPlot, 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            app.Single_paxCut = app.at(polaraxes(C), [1 4], 3); set(app.Single_paxCut, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            app.Range_Cut = app.at(uislider(C, 'range', 'Limits', app.HardRange, 'Value', app.HardRange, 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s, ~) app.onRange("cut", s.Value, 0)), [2 3], 1);
            app.Range_Cut_Max = app.at(uispinner(C, 'Limits', app.HardRange, 'Value', app.HardRange(2), 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRange("cut", s.Value, 2)), 1, 1);
            app.Range_Cut_Min = app.at(uispinner(C, 'Limits', app.HardRange, 'Value', app.HardRange(1), 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRange("cut", s.Value, 1)), 4, 1);
            app.Button_HPBW = app.at(uibutton(C, 'state', 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', cb(@onCutChanged)), 1, 4);
            app.Label_HPBW = app.at(uilabel(C, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold'), 2, 4);
            app.Single_gridEcut = app.at(uigridlayout(C, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x', '1x', '1x'}), 3, 4);
            app.CheckBox_Et = app.at(uicheckbox(app.Single_gridEcut, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', cb(@onCutChanged)), 1, 1);
            app.CheckBox_Er = app.at(uicheckbox(app.Single_gridEcut, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', cb(@onCutChanged)), 2, 1);
            app.CheckBox_El = app.at(uicheckbox(app.Single_gridEcut, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', cb(@onCutChanged)), 3, 1);
            app.Button_ExportCut = app.at(uibutton(C, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', cb(@exportCut)), 4, 4);
            app.Single_tabRectPlot = uitab(app.Single_tabCut, 'Title', 'Rectangular Cut Plot');
            app.Single_AxesRect = uiaxes(uigridlayout(app.Single_tabRectPlot, [1 1])); app.Single_AxesRect.Box = 'on';
            xlabel(app.Single_AxesRect, 'Theta (degree)'); ylabel(app.Single_AxesRect, 'Magnitude (dB)');

            % plot control panel
            app.Single_Panel_plotControl = app.at(uipanel(G, 'Title', 'Plot Control 🎨', 'Visible', 'off'), 2, [13 14]);
            K = uigridlayout(app.Single_Panel_plotControl, 'RowHeight', repmat({'fit'}, 1, 15));
            app.label(K, 'Component', 1, 1);
            app.Single_DropDown_Component = app.at(uidropdown(K, 'Items', cellstr(app.ComponentLabels), 'ItemsData', cellstr(app.ComponentNames), 'Value', 'E_Total_dB', 'ValueChangedFcn', cb(@onComponentChanged)), 1, 2);
            app.label(K, 'Cut type', 2, 1);
            app.Single_DropDown_cutType = app.at(uidropdown(K, 'Items', {'Phi', 'Theta'}, 'Value', 'Phi', 'ValueChangedFcn', cb(@onCutChanged)), 2, 2);
            app.label(K, 'Cut value', 3, 1);
            app.Single_DropDown_cutValue = app.at(uispinner(K, 'Limits', [0 360], 'Value', 0, 'ValueChangedFcn', cb(@onCutChanged)), 3, 2);
            app.label(K, 'Cut fields', 4, 1);
            app.CutFieldBasisDropDown = app.at(uidropdown(K, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Value', 'Circular', 'Enable', 'off', 'ValueChangedFcn', cb(@onCutChanged)), 4, 2);
            app.label(K, 'Colorbar max', 5, 1);  app.Single_Plot_Cmax = app.at(uispinner(K, 'Limits', app.HardRange, 'Value', 10), 5, 2);
            app.label(K, 'Colorbar min', 6, 1);  app.Single_Plot_Cmin = app.at(uispinner(K, 'Limits', app.HardRange, 'Value', -40), 6, 2);
            app.label(K, 'Colorbar step', 7, 1); app.Single_Plot_Cstep = app.at(uispinner(K, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', @(~, ~) app.applyFullRange()), 7, 2);
            app.label(K, 'Adjust Colorbar', 8, 1);
            app.Single_Button_Clim = app.at(uibutton(K, 'Text', 'Apply', 'Tooltip', 'Apply to full-pattern and cut plots.', 'ButtonPushedFcn', @(~, ~) app.setRanges([app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value])), 8, 2);
            set([app.Single_Plot_Cmin, app.Single_Plot_Cmax], 'ValueChangedFcn', @(~, ~) app.setRanges([app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value]));
            app.label(K, '3D view', 9, 1);
            app.Single_DropDown_3DView = app.at(uidropdown(K, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Value', 'iso', 'ValueChangedFcn', cb(@on3DViewChanged)), 9, 2);
            pad = @(n) repmat(char(160), 1, n); % non-breaking padding centers the switch bodies
            app.Single_Switch_AngularSpan = app.at(uiswitch(K, 'slider', 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'Value', '0° to 360°', 'ValueChangedFcn', cb(@onSpanChanged)), 10, [1 2]);
            app.Single_Switch_ThetaSpan = app.at(uiswitch(K, 'slider', 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'Value', '0° to 180°', 'ValueChangedFcn', cb(@onSpanChanged)), 11, [1 2]);
            app.Single_Switch_EHplane = app.at(uiswitch(K, 'slider', 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'Value', 'E-Plane cut', 'ValueChangedFcn', cb(@onEHPlaneChanged)), 12, [1 2]);
            app.Single_CheckBox_overlayCut = app.at(uicheckbox(K, 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', cb(@onOverlayChanged)), 13, [1 2]);
            app.Single_CheckBox_POB = app.at(uicheckbox(K, 'Text', 'Annotate POB', 'ValueChangedFcn', cb(@syncAnnotations)), 14, [1 2]);
            app.Single_CheckBox_HPBWBounds = app.at(uicheckbox(K, 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', cb(@syncAnnotations)), 15, [1 2]);

            % data tables + status
            app.Single_DropDown_output = app.at(uidropdown(G, 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Value', 0, 'Visible', 'off', 'ValueChangedFcn', cb(@filterOutput)), 3, [13 14]);
            app.Single_tabData = app.at(uitabgroup(G, 'Visible', 'off'), 4, [1 14]);
            tOut = uitab(app.Single_tabData, 'Title', 'Results 📤', 'ButtonDownFcn', @(~, ~) set(app.Single_DropDown_output, 'Visible', 'on'));
            app.Single_Table_DataOut = uitable(uigridlayout(tOut, [1 1]), 'ColumnWidth', '1x', 'RowName', 'numbered', 'ColumnSortable', true, 'ColumnRearrangeable', 'on');
            app.Single_Table_DataIn = uitable(uigridlayout(uitab(app.Single_tabData, 'Title', 'Input 📥'), [1 1]), 'ColumnWidth', '1x', 'RowName', 'numbered', 'ColumnSortable', true, 'ColumnRearrangeable', 'on');
            app.Single_Table_metadata = uitable(uigridlayout(uitab(app.Single_tabData, 'Title', 'Metadata 📋'), [1 1]), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {220, 'auto'}, 'RowName', {});
            app.Single_StatusBar = app.at(uilabel(G, 'Text', 'Ready 🚀', 'Interpreter', 'html'), 5, [1 14]);

            % ---------------- Coverage tab
            V = uigridlayout(app.Tab2_Coverage, 'ColumnWidth', {'1x'}, 'RowHeight', {'fit', '1x', 'fit'});
            Q = uigridlayout(app.at(uipanel(V, 'Title', 'Inputs & Parameters 🎛️'), 1, 1), 'ColumnWidth', {'fit', '1x', '1x', '1x', '1x', '1x', '1x', '1x', '1x', '1x'}, 'RowHeight', {'1x', 'fit', 'fit', 'fit'});
            app.Cov_ButtonGroup_CovType = app.at(uibuttongroup(Q, 'Title', 'Coverage Type', 'SelectionChangedFcn', cb(@onCovTypeChanged)), [1 2], [1 2]);
            app.Cov_ButtonGroup_Btn_Spherical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            app.Cov_ButtonGroup_Btn_Conical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            orL = app.label(Q, 'Orientation 🧭:', 3, 1);
            app.Cov_DropDown_Orientation = app.at(uidropdown(Q, 'Items', [{'Auto'}, app.PrincipalAxes.labels], 'ItemsData', 0:numel(app.PrincipalAxes.labels), 'Value', 0, 'ValueChangedFcn', cb(@onOrientationChanged)), 3, 2);
            compL = app.label(Q, 'Component:', 4, 1);
            app.Cov_DropDown_Component = app.at(uidropdown(Q, 'Items', {'E_Total_dB'}, 'Value', 'E_Total_dB', 'ValueChangedFcn', cb(@onCovComponentChanged)), 4, 2);
            app.label(Q, 'Antenna Pattern:', 1, 3);
            app.Cov_EditField_filePath = app.at(uieditfield(Q, 'text'), 1, [4 8]);
            app.Cov_Button_Load = app.at(uibutton(Q, 'Text', '📂 Load File', 'ButtonPushedFcn', cb(@Cov_Button_LoadPushed)), 1, 9);
            app.Cov_Button_computeCov = app.at(uibutton(Q, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'ButtonPushedFcn', cb(@Cov_Button_computeCovPushed)), 1, 10);
            tminL = app.label(Q, 'Threshold Min (dB):', 2, 3); app.Cov_Spinner_ThreshMin = app.at(uispinner(Q, 'Value', -40), 2, 4);
            tmaxL = app.label(Q, 'Threshold Max (dB):', 2, 5); app.Cov_Spinner_ThreshMax = app.at(uispinner(Q, 'Value', 10), 2, 6);
            stepL = app.label(Q, 'Step (dB):', 2, 7);          app.Cov_Spinner_Step = app.at(uispinner(Q, 'Value', 1, 'Limits', [0.1 100]), 2, 8);
            app.Cov_Button_Reset = app.at(uibutton(Q, 'Text', '🔄 Reset', 'ButtonPushedFcn', cb(@Cov_Button_ResetPushed)), 2, 9);
            app.Cov_Button_Export = app.at(uibutton(Q, 'Text', '💾 Export Results', 'ButtonPushedFcn', cb(@Cov_Button_ExportPushed)), 2, 10);
            thL = app.label(Q, 'Cone θ₀ (°):', 3, 3);  app.Cov_Spinner_ConeTH = app.at(uispinner(Q, 'Limits', [0 180]), 3, 4);
            phL = app.label(Q, 'Cone φ₀ (°):', 3, 5);  app.Cov_Spinner_ConePH = app.at(uispinner(Q, 'Limits', [0 360]), 3, 6);
            alL = app.label(Q, 'Cone Angle α (°):', 3, 7); app.Cov_Spinner_ConeAng = app.at(uispinner(Q, 'Limits', [0 180], 'Value', 45), 3, 8);
            app.Cov_Button_Clear = app.at(uibutton(Q, 'Text', '🧹 Clear DataTips', 'ButtonPushedFcn', cb(@Cov_Button_ClearPushed)), 3, 9);
            app.Cov_Button_toMain = app.at(uibutton(Q, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~, ~) set(app.TabGroup, 'SelectedTab', app.Tab1_Single)), 3, 10);
            qcL = app.label(Q, 'Coverage @ dB:', 4, 3);  app.Cov_Spinner_queryCov = app.at(uispinner(Q, 'ValueDisplayFormat', '%g dB'), 4, 4);
            app.Cov_Button_queryCov = app.at(uibutton(Q, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', @(~, ~) app.covRunQuery("cov")), 4, 5);
            qtL = app.label(Q, 'Threshold @ %:', 4, 6);  app.Cov_Spinner_queryThresh = app.at(uispinner(Q, 'ValueDisplayFormat', '%g%%', 'Value', 50, 'Limits', [0 100]), 4, 7);
            app.Cov_Button_queryThresh = app.at(uibutton(Q, 'Text', '🔍 Query Threshold', 'ButtonPushedFcn', @(~, ~) app.covRunQuery("thr")), 4, 8);
            app.Cov_TextFormatLabel = app.label(Q, 'Format:', 4, 9, 'Visible', 'off');
            app.Cov_DropDown_TextFormat = app.at(app.textFormatDropdown(Q), 4, 10); app.Cov_DropDown_TextFormat.ValueChangedFcn = cb(@onCovTextFormatChanged);
            app.CovGroups = struct( ...
                'pattern', [app.Cov_Button_computeCov, compL, app.Cov_DropDown_Component, orL, app.Cov_DropDown_Orientation, tminL, app.Cov_Spinner_ThreshMin, tmaxL, app.Cov_Spinner_ThreshMax, stepL, app.Cov_Spinner_Step], ...
                'cone', [thL, app.Cov_Spinner_ConeTH, phL, app.Cov_Spinner_ConePH, alL, app.Cov_Spinner_ConeAng], ...
                'query', [qcL, app.Cov_Spinner_queryCov, app.Cov_Button_queryCov, qtL, app.Cov_Spinner_queryThresh, app.Cov_Button_queryThresh], ...
                'results', [app.Cov_Button_Export, app.Cov_Button_Clear]);
            app.Cov_Panel_Results = app.at(uipanel(V, 'Title', 'Results', 'Visible', 'off'), 2, 1);
            R = uigridlayout(app.Cov_Panel_Results, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            app.Cov_Tree = app.at(uitree(R, 'checkbox', 'SelectionChangedFcn', cb(@Cov_TreeSelectionChanged), 'CheckedNodesChangedFcn', @(~, ~) app.finalizeCoverageJobs()), [1 2], 1);
            app.Cov_TreeNode_Results = uitreenode(app.Cov_Tree, 'Text', 'Coverage Results');
            app.Cov_Axes = app.at(uiaxes(R), 1, [2 4]);
            title(app.Cov_Axes, 'Coverage vs Threshold'); xlabel(app.Cov_Axes, 'Threshold (dB)'); ylabel(app.Cov_Axes, 'Coverage (%)');
            app.Cov_Axes.Interactions = dataTipInteraction; hold(app.Cov_Axes, 'on'); grid(app.Cov_Axes, 'on'); ylim(app.Cov_Axes, [0 100]); set(app.Cov_Axes, 'Box', 'on', 'Layer', 'top');
            app.Cov_Spinner_XMin = app.at(uispinner(R, 'Limits', app.HardRange, 'Value', -40, 'ValueChangedFcn', cb(@onCovXRange)), 2, 2);
            app.Cov_Spinner_XRange = app.at(uislider(R, 'range', 'Limits', app.HardRange, 'Value', [-40 10], 'ValueChangedFcn', cb(@onCovXRange), 'ValueChangingFcn', cb(@onCovXRange)), 2, 3);
            app.Cov_Spinner_XMax = app.at(uispinner(R, 'Limits', app.HardRange, 'Value', 10, 'ValueChangedFcn', cb(@onCovXRange)), 2, 4);
            app.Cov_Table = app.at(uitable(R, 'ColumnWidth', '1x', 'RowName', {}), [1 2], 5);
            app.Cov_StatusBar = app.at(uilabel(V, 'Text', 'Ready 🚀', 'Interpreter', 'html'), 3, 1);
            app.UIFigure.Visible = 'on';
        end
    end

    %% ------------------------------------------------------------------ self-test (pure numerics; no file dialogs)
    methods (Access = public)
        function report = runSelfTest(app)
            pp = app.PeakPercentile; pm = app.PeakMaxExcessDB; r = struct();
            [P, T] = meshgrid((0:2:358)', (0:2:180)'); G = table(T(:), P(:), 10 * log10(max(cosd(T(:)).^2, 1e-12)), 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            N = normalizePattern(G); w = solidWeights(N.Theta, N.Phi);
            r.solidAngle = abs(sum(w) - 4 * pi) < 1e-9;
            [~, axisIndex] = calcOrientation(N, w, "E_Total_dB", app.PrincipalAxes, pp, pm); r.orientation = axisIndex == 1;
            R = resampleCanonical(N, 1); r.resampling = height(R) == 181 * 361 && all(isfinite(R.E_Total_dB));
            native = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0 & R.Theta > 0 & R.Theta < 90;
            r.numericalEquivalence = max(abs(R.E_Total_dB(native) - 10 * log10(cosd(R.Theta(native)).^2))) < 1e-9;
            [ang, rows] = calcCutGeometry(N, 'Theta', 0); r.hpbw = abs(calcHPBW(ang, N.E_Total_dB(rows)) - 90) < 1e-9; % cos² pattern: -3 dB at ±45°
            c = coverageCCDF(N.E_Total_dB, true(height(N), 1), [-400; 400], w); r.ccdf = abs(c(1) - 100) < 1e-9 && c(2) == 0;
            r.peakWindow = isequal(peakWindow([3.2; -250; -17], [-50 0], pp, pm), [-45 5]);
            spike = repmat(0.02, 1e5, 1); spike(1) = 10.02; pk = resolvePeak(spike, pp, pm); r.isolatedSpike = pk.wasAdjusted && abs(pk.value - 0.02) < 1e-12;
            r.arSemantics = all(arrayfun(@(s) app.isAR(s), ["AR", "AR_dB", "AR dB", "Axial Ratio", "Axial_Ratio"]));
            ffd = [tempname '.ffd']; writelines(["0 180 3"; "-180 180 3"; string(compose('%d 0 0 1', (1:9)'))], ffd); cleaner = onCleanup(@() delete(ffd)); %#ok<NASGU>
            out = readPattern(ffd, "ffd", table()); r.ffdReader = out.meta.source == "HFSS FFD" && height(out.blocks{1}) == 9;
            names = fieldnames(r); failed = names(~cellfun(@(f) r.(f), names));
            report = r; report.pass = isempty(failed);
            if ~report.pass, error('apat:test:SelfTestFailed', 'Self-test failed: %s', strjoin(failed, ', ')); end
        end
    end
end

%% ====================================================================== I/O services (pure, UI independent)
function out = readPattern(fp, textFormat, tableData)
%READPATTERN Any supported source -> struct(rawTbl, blocks, freqs, meta).
%   blocks{k} are standard tables {Theta,Phi,Re_Eth,Im_Eth,Re_Eph,Im_Eph} (or gain tables).
if nargin < 3, tableData = table(); end
textFormat = string(textFormat); [~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
std6 = {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'};
meta = struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'isMultiBlock', false, 'hasFrequency', false);
out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, 'meta', meta);
fieldTable = @(th, ph, Eth, Eph) table(th(:), ph(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', std6);
circToLin = @(Ercp, Elcp) deal((Ercp + Elcp) / sqrt(2), (Ercp - Elcp) / (1i * sqrt(2)));

if ismember(ext, {'XLSX', 'XLS'}), out = readExcelMatrix(fp); return; end

if ismember(ext, {'CSV', 'TXT', 'DAT'}) % ---- generic text: gain pattern, generic E-field, or coverage results
    if isempty(tableData)
        opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
        opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
        tableData = rmmissing(readtable(fp, opts));
    end
    n = width(tableData); assert(n >= 2 && ~isempty(tableData), 'readFile:InvalidFormat', 'File needs at least two numeric columns.');
    names = string(tableData.Properties.VariableNames); hasHeaders = ~all(startsWith(names, "Var"));
    c1 = tableData{:, 1}; c2 = tableData{:, 2};
    coverageHeader = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
    if (textFormat == "gain" || n < 6 || coverageHeader) && all(isfinite(c2)) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
        if ~hasHeaders, tableData.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', (1:n - 1)'))']; end
        out.rawTbl = tableData; out.meta.isCoverage = true; return
    end
    if textFormat == "gain" % which of the first two columns spans phi?
        if max(c1) - min(c1) > max(c2) - min(c2), tableData.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; else, tableData.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
        tableData = movevars(tableData, 'Theta', 'Before', 1);
        out.rawTbl = tableData; out.blocks = {tableData}; out.meta.isGainOnly = true; return
    end
    assert(n >= 6, 'readFile:TextEFieldColumns', 'The selected generic E-field format requires six numeric columns.');
    F = tableData{:, 3:6}; magPhase = endsWith(textFormat, "magphase"); layout = "not applicable";
    if magPhase
        bigCols = max(abs(F), [], 1, 'omitnan') > 100; % phase columns exceed 100 (degrees)
        if bigCols(2) && ~bigCols(3), magCols = [1 3]; phCols = [2 4]; layout = "interleaved"; else, magCols = [1 2]; phCols = [3 4]; layout = "grouped"; end
        comp = 10.^(F(:, magCols) / 20) .* exp(1i * deg2rad(F(:, phCols)));
    else
        comp = [complex(F(:, 1), F(:, 2)), complex(F(:, 3), F(:, 4))];
    end
    if startsWith(textFormat, "linear"), Eth = comp(:, 1); Eph = comp(:, 2); tagNames = ["E_TH", "E_PH"]; reim = ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"];
    else
        if startsWith(textFormat, "rcp"), [Eth, Eph] = circToLin(comp(:, 1), comp(:, 2)); else, [Eth, Eph] = circToLin(comp(:, 2), comp(:, 1)); end
        tagNames = ["POL1", "POL2"]; reim = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"];
    end
    if magPhase, fieldNames = [tagNames + "_dB", tagNames + "_deg"]; if layout == "interleaved", fieldNames = fieldNames([1 3 2 4]); end, else, fieldNames = reim; end
    if ~hasHeaders, tableData.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", fieldNames]); end
    out.meta.source = sprintf('Generic text (%s, %s)', textFormat, layout); out.rawTbl = tableData;
    out.blocks = {fieldTable(c1, c2, Eth, Eph)}; return
end

if strcmp(ext, 'CUT') % ---- TICRA/GRASP cut: repeated blocks [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data]
    out.meta.source = 'TICRA/GRASP CUT';
    L = readlines(fp); L(strlength(strtrim(L)) == 0) = []; th = {}; ph = {}; D = {}; k = 1; icomp = 1; icut = 1;
    while k < numel(L)
        p = sscanf(L(k + 1), '%f'); assert(numel(p) >= 7, 'parseCutFile:bad', 'Could not parse cut parameter line.');
        n = p(3); icomp = p(5); icut = p(6);
        block = reshape(sscanf(strjoin(L(k + 2:k + 1 + n), ' '), '%f'), 2 * p(7), []).';
        th{end+1, 1} = p(1) + (0:n - 1)' * p(2); ph{end+1, 1} = repmat(p(4), n, 1); D{end+1, 1} = block(:, 1:4); k = k + 2 + n; %#ok<AGROW>
    end
    th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:});
    if icut == 2, [th, ph] = deal(ph, th); end % ICUT=2: phi swept, theta constant
    neg = th < 0; ph(neg) = ph(neg) + 180; th(neg) = -th(neg);
    if isscalar(unique(ph)) % single cut -> body of revolution
        copies = (0:10:350)'; m = numel(th); th = repmat(th, numel(copies), 1); ph = repelem(copies, m); D = repmat(D, numel(copies), 1);
    end
    A = complex(D(:, 1), D(:, 2)); B = complex(D(:, 3), D(:, 4));
    if icomp == 2, out.rawTbl = table(th, ph, D(:, 1), D(:, 2), D(:, 3), D(:, 4), 'VariableNames', {'Theta','Phi','Re_RHCP','Im_RHCP','Re_LHCP','Im_LHCP'}); [Eth, Eph] = circToLin(A, B);
    else, out.rawTbl = table(th, ph, D(:, 1), D(:, 2), D(:, 3), D(:, 4), 'VariableNames', std6); Eth = A; Eph = B; end
    out.blocks = {fieldTable(th, ph, Eth, Eph)}; return
end

% ---- E-field far-field text files (UAN/FZ, OUT, FFS, FFE, FFD)
[nHdr, ffd] = scanHeader(fp);
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = readmatrix(fp, setvartype(opts, opts.VariableNames, 'double'));
M = M(~all(isnan(M), 2), 1:min(size(M, 2), 6));
switch ext
    case {'FZ', 'UAN'} % Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
        out.meta.source = sprintf('XGTD %s', ext); out.rawTbl = array2table(M, 'VariableNames', {'Theta','Phi','E_TH_dB','E_PH_dB','E_TH_deg','E_PH_deg'});
        th = M(:, 1); ph = M(:, 2); Eth = 10.^(M(:, 3) / 20) .* exp(1i * deg2rad(M(:, 5))); Eph = 10.^(M(:, 4) / 20) .* exp(1i * deg2rad(M(:, 6)));
    case 'OUT' % Theta Phi Re(RHCP) Im(RHCP) Re(LHCP) Im(LHCP)
        out.meta.source = 'TICRA/GRASP OUT'; out.rawTbl = array2table(M, 'VariableNames', {'Theta','Phi','Re_RHCP','Im_RHCP','Re_LHCP','Im_LHCP'});
        th = M(:, 1); ph = M(:, 2); [Eth, Eph] = circToLin(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)));
    case 'FFS' % Phi Theta Re(Eth) Im(Eth) Re(Eph) Im(Eph)
        out.meta.source = 'CST FFS'; out.rawTbl = array2table(M, 'VariableNames', {'Phi','Theta','Re_Eth','Im_Eth','Re_Eph','Im_Eph'});
        ph = M(:, 1); th = M(:, 2); Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
    case 'FFE' % Theta Phi Re(Eth) Im(Eth) Re(Eph) Im(Eph) [extra columns ignored]
        out.meta.source = 'FEKO FFE'; out.rawTbl = array2table(M, 'VariableNames', std6);
        th = M(:, 1); ph = M(:, 2); Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
    case 'FFD' % header defines the grid; rows are Re(Eth) Im(Eth) Re(Eph) Im(Eph); "Frequency f" rows separate blocks
        out.meta.source = 'HFSS FFD'; assert(ffd.isFFD, 'readFile:ffd', 'FFD header (theta/phi ranges) not found.');
        thetaAxis = linspace(ffd.theta(1), ffd.theta(2), ffd.theta(3))'; phiAxis = linspace(ffd.phi(1), ffd.phi(2), ffd.phi(3))';
        th = repelem(thetaAxis, numel(phiAxis)); ph = repmat(phiAxis, numel(thetaAxis), 1);
        sep = isnan(M(:, 1)); sepFreqs = M(sep, 2); freqs = [ffd.freq(:); sepFreqs(~isnan(sepFreqs))]';
        rows = M(~sep, 1:4); perBlock = numel(th);
        assert(mod(size(rows, 1), perBlock) == 0, 'readFile:ffd', 'FFD mismatch: row count does not match the theta/phi grid.');
        nBlocks = size(rows, 1) / perBlock; freqs(end+1:nBlocks) = NaN; freqs = freqs(1:nBlocks);
        out.meta.isMultiBlock = nBlocks > 1; out.meta.hasFrequency = any(isfinite(freqs)); out.meta.isDep = out.meta.isMultiBlock || out.meta.hasFrequency;
        blocks = mat2cell(rows, repmat(perBlock, nBlocks, 1), 4);
        out.blocks = cellfun(@(B) fieldTable(th, ph, complex(B(:, 1), B(:, 2)), complex(B(:, 3), B(:, 4))), blocks, 'UniformOutput', false);
        out.freqs = freqs; out.rawTbl = out.blocks{1}; return
    otherwise, error('readFile:unsupported', 'Unsupported format: %s', ext);
end
out.blocks = {fieldTable(th, ph, Eth, Eph)};
end

function [nHdr, ffd] = scanHeader(fp)
%SCANHEADER Count leading non-data lines; recognize the HFSS FFD header (two axis triples + optional Frequencies line).
L = readlines(fp); nonEmpty = find(strlength(strtrim(L)) > 0, 3);
ffd = struct('isFFD', false, 'theta', [], 'phi', [], 'freq', []); nHdr = 0;
tri = arrayfun(@(k) sscanf(char(L(k)), '%f')', nonEmpty, 'UniformOutput', false);
if numel(tri) >= 2 && numel(tri{1}) == 3 && numel(tri{2}) == 3 && all(isfinite([tri{1} tri{2}])) && tri{1}(3) >= 1 && tri{2}(3) >= 1
    ffd.theta = tri{1}; ffd.phi = tri{2}; ffd.isFFD = true; nHdr = nonEmpty(2);
    if numel(tri) == 3
        tok = regexp(strtrim(char(L(nonEmpty(3)))), '^frequenc(?:y|ies)\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok), nHdr = nonEmpty(3); f = sscanf(tok{1}, '%f'); if numel(f) > 1, ffd.freq = f(:); end, end % a scalar is only a count
    end
    return
end
num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?';
firstData = find(~cellfun('isempty', regexp(cellstr(L), ['^\s*' num '(?:[\s,;]+' num '){3,}\s*$'], 'once')), 1);
if ~isempty(firstData), nHdr = firstData - 1; end
end

function out = readExcelMatrix(fp)
%READEXCELMATRIX Antenna-pattern Excel matrix workbooks (Eth/Eph and/or RHCP/LHCP gain+phase sheets, C3-origin matrices).
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"]; lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasCirc = all(ismember(lower(circ), lower(sheets))); hasLin = all(ismember(lower(lin), lower(sheets)));
assert(hasCirc || hasLin, 'readFile:ExcelMatrixFormat', 'Unsupported Excel workbook: expected the fixed Etheta/Ephi and/or RHCP/LHCP component sheets after the summary sheet.');
required = [circ(1:4 * hasCirc), lin(1:4 * hasLin)]; formats = {'Excel Matrix Format 2 (Ercp/Elcp)', 'Excel Matrix Format 1 (Eth/Eph)', 'Excel Matrix Format 3 (Ercp/Elcp + Eth/Eph)'};
Mx = struct(); theta = []; phi = [];
for name = required
    [t, p, data] = readExcelSheet(fp, sheets(find(strcmpi(sheets, name), 1)));
    if isempty(theta), theta = t; phi = p;
    else, assert(isequal(size(t), size(theta)) && isequal(size(p), size(phi)) && max(abs(t - theta)) < 1e-9 && max(abs(p - phi)) < 1e-9, 'readFile:ExcelMatrixGrid', 'All component sheets must share one theta/phi grid.'); end
    Mx.(char(matlab.lang.makeValidName(name))) = data;
end
toC = @(g, ph) 10.^(g / 20) .* exp(1i * deg2rad(ph));
if hasLin, Eth = toC(Mx.Etheta_Gain_dBi, Mx.Etheta_Phase_degrees); Eph = toC(Mx.Ephi_Gain_dBi, Mx.Ephi_Phase_degrees);
else, Er = toC(Mx.RHCP_Gain_dBi, Mx.RHCP_Phase_degrees); El = toC(Mx.LHCP_Gain_dBi, Mx.LHCP_Phase_degrees); Eth = (Er + El) / sqrt(2); Eph = (Er - El) / (1i * sqrt(2)); end
[P, T] = meshgrid(phi, theta);
block = table(T(:), P(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'});
raw = block; for name = required, key = char(matlab.lang.makeValidName(name)); raw.(key) = Mx.(key)(:); end
meta = readExcelSummary(fp, sheets(1));
meta.source = formats{1 + hasLin + (hasLin && hasCirc)}; meta.file = fp; meta.isGainOnly = false; meta.isCoverage = false; meta.isDep = false; meta.isMultiBlock = false;
meta.hasFrequency = isfield(meta, 'frequencyMHz') && isfinite(meta.frequencyMHz); meta.componentSheets = cellstr(required);
out = struct('rawTbl', raw, 'blocks', {{block}}, 'freqs', NaN, 'meta', meta);
end

function [theta, phi, data] = readExcelSheet(fp, sheet)
% One C3-origin matrix: row 2 (C..) = phi, column B (3..) = theta. readcell keeps worksheet coordinates intact.
C = readcell(fp, 'Sheet', char(sheet)); isNum = @(x) isnumeric(x) && isscalar(x) && isfinite(x);
assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'readFile:ExcelMatrixSheet', 'Sheet "%s" does not contain a C3-origin matrix.', sheet);
pm = cellfun(isNum, C(2, 3:end)); tm = cellfun(isNum, C(3:end, 2));
nPhi = find(~pm, 1) - 1; if isempty(nPhi), nPhi = numel(pm); end, nTheta = find(~tm, 1) - 1; if isempty(nTheta), nTheta = numel(tm); end
assert(nPhi > 0 && nTheta > 0 && ~any(pm(nPhi + 1:end)) && ~any(tm(nTheta + 1:end)), 'readFile:ExcelMatrixAxis', 'Sheet "%s" has a missing or non-contiguous theta/phi axis.', sheet);
phi = cellfun(@double, C(2, 3:2 + nPhi))'; theta = cellfun(@double, C(3:2 + nTheta, 2)); cells = C(3:2 + nTheta, 3:2 + nPhi);
assert(all(cellfun(isNum, cells(:))), 'readFile:ExcelMatrixSheet', 'Sheet "%s" contains non-numeric/missing samples.', sheet);
data = cellfun(@double, cells);
assert(all(diff(theta) > 0) && all(diff(phi) > 0) && theta(1) >= -1e-9 && theta(end) <= 180 + 1e-9 && phi(1) >= -1e-9 && phi(end) < 360 + 1e-9, ...
    'readFile:ExcelMatrixAxis', 'Sheet "%s" needs strictly increasing axes within theta 0..180 and phi 0..360.', sheet);
end

function meta = readExcelSummary(fp, sheet)
% Harvest every "label | value" pair of the summary sheet into normalized keys; expose the frequency explicitly.
meta = struct('frequencyMHz', NaN);
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
blank = @(v) isempty(v) || isa(v, 'missing') || (isnumeric(v) && all(isnan(v(:)))) || ((ischar(v) || isstring(v)) && strlength(strtrim(string(v))) == 0);
for r = 1:size(C, 1)
    for c = 1:size(C, 2) - 1
        lbl = C{r, c}; if ~(ischar(lbl) || isstring(lbl)) || blank(lbl), continue; end
        vals = C(r, c + 1:min(size(C, 2), c + 3)); k = find(~cellfun(blank, vals), 1); if isempty(k), continue; end
        key = char(matlab.lang.makeValidName(lower(regexprep(strtrim(string(lbl)), '[^a-zA-Z0-9]+', '_'))));
        if ~isfield(meta, key), meta.(key) = vals{k}; end
        break
    end
end
if isfield(meta, 'pattern_simulation_freq_mhz_'), f = str2double(string(meta.pattern_simulation_freq_mhz_)); if isscalar(f), meta.frequencyMHz = f; end, end
end

function writeUAN(U, fp)
% Canonical XGTD UAN header followed by tab-delimited magnitude/phase rows.
header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\ncomplex\nmag_phase\n' ...
    'pattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
    min(U.Phi), max(U.Phi), gridStep(U.Phi), min(U.Theta), max(U.Theta), gridStep(U.Theta), max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan'));
writelines(header, fp);
writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
end

%% ====================================================================== numerical services (pure)
function T = normalizePattern(T)
%NORMALIZEPATTERN Map any angular convention onto the canonical sphere: theta 0..180, phi 0..360 with a closed seam.
theta = T.Theta;
if any(theta < 0)
    if min(theta, [], 'omitnan') >= -90 && max(theta, [], 'omitnan') <= 90, T.Theta = 90 - theta; % elevation source
    else, m = theta < 0; T.Theta(m) = -theta(m); T.Phi(m) = T.Phi(m) + 180; end                   % negative theta folds through the pole
end
T.Theta = mod(T.Theta, 360); over = T.Theta > 180; T.Theta(over) = 360 - T.Theta(over); T.Phi(over) = T.Phi(over) + 180;
T.Theta = round(T.Theta, 5); T.Phi = round(mod(T.Phi, 360), 5); % angles only: field values keep full precision
T.Phi(abs(T.Phi - 360) < 1e-9) = 0;
[~, keep] = unique([T.Phi, T.Theta], 'rows', 'first'); T = T(keep, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function R = resampleCanonical(S, stepDeg)
%RESAMPLECANONICAL Resample primitive source quantities onto a canonical stepDeg grid.
%   Complete rectangular grids use interp2 with a periodic phi seam; irregular sets use scatteredInterpolant.
%   Gain-like dB columns of gain-only sources are interpolated in linear power.
names = string(S.Properties.VariableNames); cols = names(3:end);
theta = S.Theta; phi = mod(S.Phi, 360); keep = isfinite(theta) & isfinite(phi) & abs(S.Phi - 360) > 1e-9; % phi=0 is authoritative
[~, u] = unique([theta(keep), phi(keep)], 'rows', 'stable'); idx = find(keep); idx = idx(u); theta = theta(idx); phi = phi(idx); S = S(idx, :);
[Q, TQ] = meshgrid(unique([0:stepDeg:360, 360]), 0:stepDeg:180); R = table(TQ(:), Q(:), 'VariableNames', {'Theta', 'Phi'});
sT = unique(theta); sP = unique(phi); [~, it] = ismember(theta, sT); [~, ip] = ismember(phi, sP); lin = sub2ind([numel(sT), numel(sP)], it, ip);
regular = numel(sT) * numel(sP) == numel(theta) && numel(unique(lin)) == numel(lin);
isField = all(ismember(["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"], cols));
for name = cols
    v = double(S.(char(name))); asPower = ~isField && endsWith(lower(name), "db");
    if asPower, v = 10.^(v / 10); end
    if regular
        [PG, TG] = meshgrid([sP; sP(1) + 360], sT); G = nan(numel(sT), numel(sP)); G(lin) = v; G = [G, G(:, 1)]; %#ok<AGROW>
        q = interp2(PG, TG, G, Q, TQ, 'linear', NaN); miss = ~isfinite(q);
        if any(miss(:)), qn = interp2(PG, TG, G, Q, TQ, 'nearest', NaN); q(miss) = qn(miss); end
    else
        F = scatteredInterpolant(phi, theta, v, 'linear', 'nearest'); q = F(Q, TQ);
    end
    if asPower, q = 10 * log10(max(q, realmin)); end
    R.(char(name)) = q(:);
end
R.Properties.UserData = S.Properties.UserData;
end

function [P, info] = calcPattern(S, prm, pp, pm)
%CALCPATTERN Standard fields -> processed pattern table (gain, AR, PLF, EIRP, PFD, field strength) + polarization info.
info = struct('POB', NaN, 'POBth', NaN, 'POBph', NaN, 'pol', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
ud = S.Properties.UserData;
if isfield(ud, 'isGainOnly') && ud.isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + prm.GainLoss_dB; end
    pk = resolvePeak(P{:, 3}, pp, pm); [info.POB, info.POBth, info.POBph] = deal(pk.value, P.Theta(pk.index), P.Phi(pk.index)); return
end
Eth = complex(S.Re_Eth, S.Im_Eth) * prm.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph) * prm.FieldScale;
Er = (Eth + 1i * Eph) / sqrt(2); El = (Eth - 1i * Eph) / sqrt(2);
mTh = abs(Eth); mPh = abs(Eph); mR = abs(Er); mL = abs(El);
total = 10 * log10(max(mTh.^2 + mPh.^2, eps));
pk = resolvePeak(total, pp, pm); [info.POB, info.POBth, info.POBph] = deal(pk.value, S.Theta(pk.index), S.Phi(pk.index));
% dominant polarization from mean component power (drives co/cross ordering, label and Auto Rx sense)
pw = [mean(mTh.^2, 'omitnan'), mean(mPh.^2, 'omitnan'), mean(mR.^2, 'omitnan'), mean(mL.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif pw(1) >= pw(2), info.pol = 'Linear (Vertical)'; else, info.pol = 'Linear (Horizontal)'; end
% signed axial ratio: + right-hand, - left-hand; equal circular components are the linear limit (-100 dB floor)
delta = mR - mL; sense = sign(delta); sense(~isfinite(delta)) = 0;
AR = (mR + mL) ./ max(abs(delta), eps); equal = isfinite(delta) & abs(delta) <= eps * max(mR + mL, 1);
signedAR = min(20 * log10(AR), 250) .* sense; signedAR(equal) = -100;
% polarization loss factor against an incident wave of axial ratio Rw (worst-case tilt: cos(2Δτ) = -1)
if prm.RxMode == "Auto", waveSense = 2 * (info.pairs.Circular(1) == "E_RCP") - 1; elseif prm.RxMode == "RHCP", waveSense = 1; else, waveSense = -1; end
Ra = AR .* sense; Ra(sense == 0) = 1e12; Rw = waveSense * 10^(prm.RxAR_dB / 20);
plf = 0.5 + (4 * Ra * Rw - (Ra.^2 - 1) * (Rw^2 - 1)) ./ (2 * (Ra.^2 + 1) * (Rw^2 + 1));
plfDB = 10 * log10(min(max(plf, eps), 1));
eirpDB = prm.Pt_dBW + total; eirpW = 10.^(eirpDB / 10);
dB = @(m) 20 * log10(max(m, eps)); ph = @(E) rad2deg(angle(E));
P = table(S.Theta, S.Phi, total, signedAR, dB(mR), dB(mL), plfDB, total + plfDB, dB(mTh), dB(mPh), ph(Eth), ph(Eph), ph(Er), ph(El), ...
    eirpDB, eirpW / (4 * pi * prm.R_m^2), sqrt(30 * eirpW) / prm.R_m, 'VariableNames', ...
    {'Theta','Phi','E_Total_dB','AR_dB','E_RCP_dB','E_LCP_dB','PLF_dB','Gain_PolCorrected_dB','E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'});
P.Properties.UserData = ud;
end

function info = resolvePeak(values, percentile, maxExcessDB)
%RESOLVEPEAK APAT peak policy: the raw maximum is accepted unless it exceeds the P-percentile by more than maxExcessDB;
%   then the highest sample at or below the percentile is the effective peak and the outliers are masked.
info = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(values)), 'wasAdjusted', false);
finite = isfinite(values); if ~any(finite), return; end
[info.rawValue, info.rawIndex] = max(values, [], 'omitnan'); [info.value, info.index] = deal(info.rawValue, info.rawIndex);
p = prctile(values(finite), percentile);
if info.rawValue > p + maxExcessDB
    outliers = finite & values > p; candidates = values; candidates(~finite | outliers) = -Inf;
    if any(finite & ~outliers), [info.value, info.index] = max(candidates); info.outlierMask = outliers; info.wasAdjusted = true; end
end
end

function bounds = peakWindow(values, fallback, pp, pm)
%PEAKWINDOW 50-dB display/threshold window whose top is the effective peak rounded up to 5 dB.
values = double(values(isfinite(values))); if isempty(values), bounds = fallback; return; end
pk = resolvePeak(values, pp, pm); if ~isfinite(pk.value), bounds = fallback; return; end
top = min(100, ceil(pk.value / 5) * 5); bounds = [max(-250, top - 50), top];
end

function r = clampRange(r, hard)
%CLAMPRANGE Sort, clamp to the hard limits and enforce a one-unit minimum span.
r = sort(double(r(:)')); if numel(r) < 2 || any(~isfinite(r)), r = hard; return; end
r = [max(hard(1), r(1)), min(hard(2), r(2))];
if diff(r) < 1, r(2) = min(hard(2), r(1) + 1); r(1) = max(hard(1), r(2) - 1); end
end

function step = gridStep(values)
%GRIDSTEP Smallest positive spacing of a sample axis (NaN when undefined).
d = diff(unique(values(isfinite(values)))); d = d(d > 1e-9); if isempty(d), step = NaN; else, step = min(d); end
end

function dOmega = solidWeights(theta, phi)
%SOLIDWEIGHTS Exact uniform-cell solid angle per sample; the duplicated 360° seam column carries zero weight.
ts = gridStep(theta); ps = gridStep(mod(phi, 360)); if ~isfinite(ts), ts = 180; end, if ~isfinite(ps), ps = 360; end
dOmega = (cosd(max(theta - ts / 2, 0)) - cosd(min(theta + ts / 2, 180))) * deg2rad(ps);
dOmega(abs(phi - 360) < 1e-9) = 0;
end

function [gain, column] = chooseGain(T, requested)
%CHOOSEGAIN Requested column, else total gain, else the first data column.
vars = string(T.Properties.VariableNames); c = [string(requested), "E_Total_dB"]; k = find(ismember(c, vars), 1);
if isempty(k), column = char(vars(3)); else, column = char(c(k)); end
gain = T.(column);
end

function [pk, axisIndex] = calcOrientation(T, dOmega, column, PA, pp, pm)
%CALCORIENTATION Peak of the requested column and the principal axis whose 45° cone carries the most weighted energy.
g = chooseGain(T, column); pk = resolvePeak(g, pp, pm);
if pk.wasAdjusted, g(pk.outlierMask) = NaN; end
w = 10.^((g - pk.value) / 10) .* dOmega(:); w(~isfinite(w)) = 0;
A = [sind(PA.theta(:)) .* cosd(PA.phi(:)), sind(PA.theta(:)) .* sind(PA.phi(:)), cosd(PA.theta(:))];
V = [sind(T.Theta) .* cosd(T.Phi), sind(T.Theta) .* sind(T.Phi), cosd(T.Theta)];
[~, axisIndex] = max(w' * double(V * A' >= cosd(45)));
end

function [ang, rows, fixed, symbol, snapped] = calcCutGeometry(T, cutType, requested)
%CALCCUTGEOMETRY One full-circle cut of a canonical table: Phi cut at fixed theta, or Theta cut at fixed phi + opposite phi.
if strcmp(cutType, 'Phi')
    tv = unique(T.Theta); [dist, k] = min(abs(tv - requested)); fixed = tv(k); symbol = 'θ';
    rows = find(abs(T.Theta - fixed) < 1e-9); [ang, o] = sort(T.Phi(rows)); rows = rows(o);
else
    pv = unique(T.Phi(T.Phi < 360 - 1e-9)); requested = mod(requested, 360);
    [dist, k] = min(abs(mod(pv - requested + 180, 360) - 180)); fixed = pv(k); symbol = 'φ';
    [~, ko] = min(abs(mod(pv - fixed, 360) - 180)); wrapped = mod(T.Phi, 360);
    primary = find(abs(wrapped - fixed) < 1e-9); opposite = find(abs(wrapped - pv(ko)) < 1e-9 & abs(T.Theta - 180) > 1e-9);
    [~, o1] = sort(T.Theta(primary)); [~, o2] = sort(T.Theta(opposite), 'descend'); primary = primary(o1); opposite = opposite(o2);
    rows = [primary; opposite]; ang = [T.Theta(primary); 360 - T.Theta(opposite)];
end
snapped = dist > 1e-9;
end

function [bw, lo, hi] = calcHPBW(ang, gainDB, peakGain, peakAngle)
%CALCHPBW Half-power beamwidth of one circular cut with linear interpolation of both -3 dB crossings.
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(gainDB); ang = ang(ok); gainDB = gainDB(ok);
if numel(gainDB) < 3, return; end
if nargin < 3 || isempty(peakGain), [peakGain, k] = max(gainDB); peakAngle = ang(k); end
half = peakGain - 3; [rel, o] = sort(mod(ang - peakAngle + 180, 360) - 180); g = gainDB(o);
L = find(rel < 0 & g <= half, 1, 'last'); R = find(rel > 0 & g <= half, 1, 'first');
if isempty(L) || isempty(R) || L + 1 > numel(g) || R - 1 < 1, return; end
cross = @(i, j) rel(i) + (rel(j) - rel(i)) * (half - g(i)) / (g(j) - g(i));
if g(L + 1) == g(L) || g(R - 1) == g(R), return; end
lo = peakAngle + cross(L, L + 1); hi = peakAngle + cross(R, R - 1); bw = cross(R, R - 1) - cross(L, L + 1);
end

function m = calcMetrics(T, dOmega, PA, axisIndex, pp, pm)
%CALCMETRICS Scalar antenna metrics of the total-gain column on a canonical table.
[g, ~] = chooseGain(T, 'E_Total_dB'); pk = resolvePeak(g, pp, pm); gm = g; if pk.wasAdjusted, gm(pk.outlierMask) = NaN; end
integ = sum(10.^(gm / 10) .* dOmega(:), 'omitnan'); eff = 100 * integ / (4 * pi); if eff < 0 || eff > 100, eff = NaN; end
th0 = T.Theta(pk.index); ph0 = T.Phi(pk.index);
[~, back] = min(cosd(T.Theta) * cosd(th0) + sind(T.Theta) * sind(th0) .* cosd(T.Phi - ph0));
if PA.theta(axisIndex) == 90, hType = 'Phi'; else, hType = 'Theta'; end % transverse boresight: equatorial H-plane
[eAng, eRows] = calcCutGeometry(T, 'Theta', PA.phi(axisIndex)); [hAng, hRows] = calcCutGeometry(T, hType, 90);
ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(pk.index); end
m = struct('PeakGain_dB', pk.value, 'PeakTheta_deg', th0, 'PeakPhi_deg', mod(ph0, 360), 'HPBW_EPlane_deg', calcHPBW(eAng, g(eRows)), 'HPBW_HPlane_deg', calcHPBW(hAng, g(hRows)), ...
    'FrontBack_dB', pk.value - g(back), 'PeakDirectivity_dB', 10 * log10(max(4 * pi * 10^(pk.value / 10) / max(integ, eps), eps)), 'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', ar);
end

function coverage = coverageCCDF(gain, mask, thresholds, dOmega)
%COVERAGECCDF Coverage(T) [%] = 100 · Σ I(G_i > T)·Ω_i / Σ Ω_i over the masked region, for all thresholds at once.
ok = mask(:) & isfinite(gain(:)) & isfinite(dOmega(:)) & dOmega(:) >= 0; g = gain(ok); w = dOmega(ok);
coverage = zeros(size(thresholds(:))); if isempty(g) || sum(w) <= 0, return; end
coverage = 100 * (w' * (g > thresholds(:)'))' / sum(w);
end

function [x, y] = coverageQuery(thr, cov, mode, q)
%COVERAGEQUERY "cov": coverage at threshold q. "thr": threshold at which coverage q is reached (descending CCDF).
[x, y] = deal(NaN);
if mode == "cov", x = q; if numel(thr) > 1, y = interp1(thr, cov, q, 'linear', NaN); end
else, y = q; [c, k] = unique(cov, 'last'); if numel(c) > 1, x = interp1(c, thr(k), q, 'linear', NaN); end
end
end