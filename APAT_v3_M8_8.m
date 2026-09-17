classdef APAT_v3_M8_8 < matlab.apps.AppBase %1962-lines  %ISSUE:  %1. Lazy Full Antenna Patterns plots rendering %2. Interactive DataTip cursor not showing Custom DataTips on Fisheye/Circular Contour Plot, and Interactive DataTip not working on 3D Plots (Spherical, Polar and Surface)  %3. DatTip Context menu callback not working (throw error: "Unrecognized method, property, or field 'ContextObject' for class 'matlab.ui.container.ContextMenu'.")  %4. On Coverage Threshold Query, it doesn't return/place the DataTip at the exact requested/queried value (it snaps to nearest data-point! whereas the projection line is properly traced properly at the requested/queries Threshold/Coverage location/position!)  %5. On Coverage, When Resetting, it doesn't clear the projection lines!
% APAT v3 M8 — Antenna Pattern Analyzer Tool.
%
% One grid-native Pattern on uniform axes -> one separable Geometry -> one
% derivation (pat_derive) that yields every column and every base fact ->
% one registry (Pats) shared by the Main and Coverage tabs -> one dispatcher
% (update) with build-then-commit -> retained graphics that render only what
% is visible.  Widgets are read in readConfig/readCoverageConfig only and
% written in apply*/render* only.  Base MATLAB (R2023b), no toolboxes.
%
% Dependency graph (nothing reaches upward):
%   SOURCE -> PATTERN(Rev) -> GEOMETRY -> DERIVED(Rev, Params)   stored in Pats(k)
%     |-> PLOTS / CUTS / TABLES / METADATA (+Map)
%     '-> COVERAGE job = curve {T, cov} (tree node)
%   VIEW -> MAP -> ColIdx / axes / ticks / labels / cut-value domain

    properties (GetAccess = public, SetAccess = private)
        isClosing logical = false
        Perf struct = struct()          % last timed action {AppVersion, Operation, Stages, TotalSeconds}
    end

    properties (Access = public)
        UIFigure matlab.ui.Figure
        GridLayout matlab.ui.container.GridLayout
        TabGroup matlab.ui.container.TabGroup
        Tab1_Single matlab.ui.container.Tab
        Single_Grid matlab.ui.container.GridLayout
        Single_panelParam matlab.ui.container.Panel
        Single_gridPanel_Param matlab.ui.container.GridLayout
        Single_DropDown_FFD matlab.ui.control.DropDown
        FFDFreqDropDownLabel matlab.ui.control.Label
        Single_DropDown_TextFormat matlab.ui.control.DropDown
        TextFormatLabel matlab.ui.control.Label
        Single_Export_UAN matlab.ui.control.Button
        Single_Button_ResetParams matlab.ui.control.Button
        Single_Export_Output matlab.ui.control.Button
        Single_Button_Coverage matlab.ui.control.Button
        Single_Button_Process matlab.ui.control.Button
        Single_DropDown_step matlab.ui.control.DropDown
        Single_DropDown_R matlab.ui.control.DropDown
        Single_Spinner_R matlab.ui.control.Spinner
        DistanceLabel matlab.ui.control.Label
        Single_Button_Load matlab.ui.control.Button
        Single_DropDown_Pt matlab.ui.control.DropDown
        Single_Spinner_Pt matlab.ui.control.Spinner
        TransmitPowerLabel matlab.ui.control.Label
        Single_Spinner_Loss matlab.ui.control.Spinner
        LossindBLabel matlab.ui.control.Label
        Single_Spinner_Rw matlab.ui.control.Spinner
        IncidentWaveARRwPLFLabel matlab.ui.control.Label
        Single_DropDown_RxPol matlab.ui.control.DropDown
        RxPolLabel matlab.ui.control.Label
        Single_EditField_Path matlab.ui.control.EditField
        InputPatternLabel matlab.ui.control.Label
        Single_StatusBar matlab.ui.control.Label
        Single_Panel_plotControl matlab.ui.container.Panel
        Single_gridPanel_Ctrl matlab.ui.container.GridLayout
        View3DLabel matlab.ui.control.Label
        Single_DropDown_3DView matlab.ui.control.DropDown
        Singel_CheckBox_overlayCut matlab.ui.control.CheckBox
        Single_CheckBox_POB matlab.ui.control.CheckBox
        Single_CheckBox_HPBWBounds matlab.ui.control.CheckBox
        Single_Switch_EHplane matlab.ui.control.Switch
        Single_Switch_AngularSpan matlab.ui.control.Switch
        Single_Switch_ThetaSpan matlab.ui.control.Switch
        CutvalueSpinnerLabel matlab.ui.control.Label
        Single_Label_Clim matlab.ui.control.Label
        Single_Button_Clim matlab.ui.control.Button
        Single_Plot_Cstep matlab.ui.control.Spinner
        ColorbarstepLabel matlab.ui.control.Label
        Single_Plot_Cmin matlab.ui.control.Spinner
        ColorbarminLabel matlab.ui.control.Label
        Single_Plot_Cmax matlab.ui.control.Spinner
        ColorbarmaxLabel matlab.ui.control.Label
        Single_DropDown_cutValue matlab.ui.control.Spinner
        Single_DropDown_cutType matlab.ui.control.DropDown
        CutFieldBasisDropDown matlab.ui.control.DropDown
        CutFieldsLabel matlab.ui.control.Label
        CuttypeDropDownLabel matlab.ui.control.Label
        Single_DropDown_Component matlab.ui.control.DropDown
        ComponentLabel matlab.ui.control.Label
        Single_tabData matlab.ui.container.TabGroup
        Single_tabDataOut matlab.ui.container.Tab
        Single_gridDataOut matlab.ui.container.GridLayout
        Single_Table_DataOut matlab.ui.control.Table
        Single_tabDataIn matlab.ui.container.Tab
        Single_gridDataIn matlab.ui.container.GridLayout
        Single_Table_DataIn matlab.ui.control.Table
        MetadataTab matlab.ui.container.Tab
        Single_gridMetadata matlab.ui.container.GridLayout
        Single_Table_metadata matlab.ui.control.Table
        Single_DropDown_output matlab.ui.control.DropDown
        Single_Panel_Rect matlab.ui.container.Panel
        Single_gridPanel_Cut matlab.ui.container.GridLayout
        Single_tabCut matlab.ui.container.TabGroup
        Single_tabPolarPlot matlab.ui.container.Tab
        Single_Grid_Polar matlab.ui.container.GridLayout
        Single_gridEcut matlab.ui.container.GridLayout
        CheckBox_Et matlab.ui.control.CheckBox
        CheckBox_Er matlab.ui.control.CheckBox
        CheckBox_El matlab.ui.control.CheckBox
        Button_ExportCut matlab.ui.control.Button
        Range_Cut_Max matlab.ui.control.Spinner
        Range_Cut_Min matlab.ui.control.Spinner
        Label_HPBW matlab.ui.control.Label
        Button_HPBW matlab.ui.control.StateButton
        Range_Cut matlab.ui.control.RangeSlider
        Single_tabRectPlot matlab.ui.container.Tab
        Single_gridRect matlab.ui.container.GridLayout
        Single_AxesRect matlab.ui.control.UIAxes
        Single_Panel_fullPattern matlab.ui.container.Panel
        Single_gridPanel_full matlab.ui.container.GridLayout
        Single_tabPlots matlab.ui.container.TabGroup
        Single_tabContour matlab.ui.container.Tab
        Single_gridContour matlab.ui.container.GridLayout
        Range_Ctr_Min matlab.ui.control.Spinner
        Range_Ctr_Max matlab.ui.control.Spinner
        Range_Ctr matlab.ui.control.RangeSlider
        Single_Axes_Ctr matlab.ui.control.UIAxes
        Single_tabCircular matlab.ui.container.Tab
        Single_gridCircular matlab.ui.container.GridLayout
        Range_Cir_Min matlab.ui.control.Spinner
        Range_Cir_Max matlab.ui.control.Spinner
        Range_Cir matlab.ui.control.RangeSlider
        Single_tab3DSpherical matlab.ui.container.Tab
        Single_grid3dSpherical matlab.ui.container.GridLayout
        Range_3dSph_Min matlab.ui.control.Spinner
        Range_3dSph_Max matlab.ui.control.Spinner
        Range_3dSph matlab.ui.control.RangeSlider
        Single_Axes_3dSph matlab.ui.control.UIAxes
        Single_tab3DPolar matlab.ui.container.Tab
        Single_grid3dPolar matlab.ui.container.GridLayout
        Range_3dPol_Min matlab.ui.control.Spinner
        Range_3dPol_Max matlab.ui.control.Spinner
        Range_3dPol matlab.ui.control.RangeSlider
        Single_Axes_3dPol matlab.ui.control.UIAxes
        Single_tab3DRect matlab.ui.container.Tab
        Single_grid3dRect matlab.ui.container.GridLayout
        Range_3dRect_Min matlab.ui.control.Spinner
        Range_3dRect_Max matlab.ui.control.Spinner
        Range_3dRect matlab.ui.control.RangeSlider
        Single_Axes_3dRect matlab.ui.control.UIAxes
        Single_paxCut matlab.graphics.axis.PolarAxes
        Single_paxPattern matlab.graphics.axis.PolarAxes
        Tab2_Coverage matlab.ui.container.Tab
        Cov_Grid matlab.ui.container.GridLayout
        Cov_Panel_Results matlab.ui.container.Panel
        GridLayout2 matlab.ui.container.GridLayout
        Cov_Spinner_XMin matlab.ui.control.Spinner
        Cov_Spinner_XMax matlab.ui.control.Spinner
        Cov_Spinner_XRange matlab.ui.control.RangeSlider
        Cov_Tabel matlab.ui.control.Table
        Cov_Tree matlab.ui.container.CheckBoxTree
        Cov_TreeNode_Results matlab.ui.container.TreeNode
        Cov_Axes matlab.ui.control.UIAxes
        Cov_StatusBar matlab.ui.control.Label
        Cov_Panel_Param matlab.ui.container.Panel
        Cov_gridPanel_Parm matlab.ui.container.GridLayout
        Cov_DropDown_OrientationLabel matlab.ui.control.Label
        Cov_DropDown_TextFormat matlab.ui.control.DropDown
        Cov_TextFormatLabel matlab.ui.control.Label
        Cov_Button_queryThresh matlab.ui.control.Button
        Cov_Button_queryCov matlab.ui.control.Button
        Cov_DropDown_Component matlab.ui.control.DropDown
        Cov_DropDown_ComponentLabel matlab.ui.control.Label
        Cov_Spinner_queryThresh matlab.ui.control.Spinner
        Cov_QueryThresholdLabel matlab.ui.control.Label
        Cov_Spinner_queryCov matlab.ui.control.Spinner
        Cov_QueryCoverageLabel matlab.ui.control.Label
        Cov_Button_toMain matlab.ui.control.Button
        Cov_Button_Clear matlab.ui.control.Button
        Cov_Spinner_ConeAng matlab.ui.control.Spinner
        ConeAngleLabel matlab.ui.control.Label
        Cov_Spinner_ConePH matlab.ui.control.Spinner
        ConeLabel matlab.ui.control.Label
        Cov_Spinner_ConeTH matlab.ui.control.Spinner
        ConeSpinnerLabel matlab.ui.control.Label
        Cov_Spinner_Step matlab.ui.control.Spinner
        StepdBSpinnerLabel matlab.ui.control.Label
        Cov_Spinner_ThreshMax matlab.ui.control.Spinner
        ThresholdMaxdBSpinnerLabel matlab.ui.control.Label
        Cov_Spinner_ThreshMin matlab.ui.control.Spinner
        ThresholdMindBSpinnerLabel matlab.ui.control.Label
        Cov_Button_Export matlab.ui.control.Button
        Cov_Button_Reset matlab.ui.control.Button
        Cov_Button_computeCov matlab.ui.control.Button
        Cov_Button_Load matlab.ui.control.Button
        Cov_EditField_filePath matlab.ui.control.EditField
        AntennaPatternEditFieldLabel matlab.ui.control.Label
        Cov_DropDown_Orientation matlab.ui.control.DropDown
        Cov_ButtonGroup_CovType matlab.ui.container.ButtonGroup
        Cov_ButtonGroup_Btn_Conical matlab.ui.control.RadioButton
        Cov_ButtonGroup_Btn_Spherical matlab.ui.control.RadioButton
    end

    properties (Access = private)
        Pats struct = struct([])        % registry: Name, Path, Source, Native, Pattern, Geometry, Derived, Params
        Main double = 0                 % index into Pats shown on the Main tab (0 = none)
        View struct = struct()          % last readConfig() result (display choices only)
        Map struct = struct()           % geo_displayMap(): column permutation + axis labels
        Range struct = struct('full',[-40 10],'gain',[-40 10],'cut',[-40 10],'cov',[-40 10],'covX',[-40 10], ...
            'Auto',struct('full',true,'cut',true,'cov',true,'covX',true))
        Gfx struct = struct()           % retained graphics handles (Menu, Full(k), Cut, Colorbars)
        Status struct = struct()        % persistent status text per status label tag
        StatusTimer = []                % one reusable single-shot timer for transient messages
        Dialog = []                     % active cancellable progress dialog
        Busy logical = false
        PerfRun = []
        CovRunID double = 0
        OutMask logical = logical([])   % Results-table column filter (one flag per Derived column)
        OutStyles cell = {}
    end

    %% ------------------------------------------------------------------ orchestration
    methods (Access = private)

        function [V, prm] = readConfig(app)
            % The ONLY reader of Main-tab widget values.  Returns display choices (V)
            % and physical parameters (prm) in canonical units.
            K = apat_const();
            V.Component = string(app.Single_DropDown_Component.Value);
            V.CutType = string(app.Single_DropDown_cutType.Value);
            V.SignedPhi = strcmp(app.Single_Switch_AngularSpan.Value, '-180° to 180°');
            V.Elevation = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°');
            v = app.Single_DropDown_cutValue.Value;                       % spinner shows the display convention (I8)
            if V.CutType == "Phi" && V.Elevation, v = 90 - v; end
            V.CutValue = v;
            V.Basis = string(app.CutFieldBasisDropDown.Value);
            V.Traces = logical([app.CheckBox_Et.Value, app.CheckBox_Er.Value, app.CheckBox_El.Value]);
            V.HPBW = app.Button_HPBW.Value;      V.HPBWBounds = app.Single_CheckBox_HPBWBounds.Value;
            V.POB = app.Single_CheckBox_POB.Value; V.Overlay = app.Singel_CheckBox_overlayCut.Value;
            V.Camera = string(app.Single_DropDown_3DView.Value);
            V.StepOne = strcmp(app.Single_DropDown_step.Value, 'one');
            V.FreqIndex = app.Single_DropDown_FFD.Value;
            V.Cstep = app.Single_Plot_Cstep.Value;
            V.OutMask = app.OutMask;
            prm.L = app.Single_Spinner_Loss.Value;
            prm.RxMode = string(app.Single_DropDown_RxPol.Value);
            prm.RxAR_dB = app.Single_Spinner_Rw.Value;
            p = app.Single_Spinner_Pt.Value;
            switch app.Single_DropDown_Pt.Value
                case 'dBm',   prm.Pt_dBW = p - 30;
                case 'Watts', prm.Pt_dBW = 10*log10(max(p, eps));
                otherwise,    prm.Pt_dBW = p;
            end
            prm.R_m = max(app.Single_Spinner_R.Value, K.DistanceFloorM) * (1 + 999*strcmp(app.Single_DropDown_R.Value, 'km'));
        end

        function C = readCoverageConfig(app)
            % The ONLY reader of Coverage-tab widget values.  Writes nothing.
            C.Component = string(app.Cov_DropDown_Component.Value);
            C.T = cov_thresholds(app.Cov_Spinner_ThreshMin.Value, app.Cov_Spinner_ThreshMax.Value, max(app.Cov_Spinner_Step.Value, 0.1));
            C.Conical = logical(app.Cov_ButtonGroup_Btn_Conical.Value);
            C.Center = [app.Cov_Spinner_ConeTH.Value, mod(app.Cov_Spinner_ConePH.Value, 360)];
            C.Alpha = app.Cov_Spinner_ConeAng.Value;
            C.Orientation = app.Cov_DropDown_Orientation.Value;           % 0 = Auto (Derived.Boresight)
            C.QueryT = app.Cov_Spinner_queryCov.Value;  C.QueryC = app.Cov_Spinner_queryThresh.Value;
            C.Format = app.Cov_DropDown_TextFormat.Value;
        end

        function on(app, scope, varargin)
            % Guard around every user action: re-entrancy, try/catch, cancel, timing.
            if app.Busy || app.isClosing, return; end
            app.Busy = true; cleaner = onCleanup(@() app.endAction());
            app.perf("begin " + scope);
            try
                app.update(scope, varargin{:}); drawnow limitrate
            catch err
                if err.identifier == "APAT:Cancelled", app.setStatus(app.Single_StatusBar, 'Operation cancelled.', true);
                else, app.showError(err, "APAT — " + scope); end
            end
            app.perf("end");
        end

        function endAction(app)
            app.Busy = false;
            if ~isempty(app.Dialog) && isvalid(app.Dialog), close(app.Dialog); end
            app.Dialog = [];
        end

        function update(app, scope, arg)
            % Dispatcher.  Data ladder: source > freq > step > params; view scopes touch no numbers.
            switch scope
                case "source"
                    app.Dialog = uiprogressdlg(app.UIFigure, 'Title', 'Loading', 'Message', 'Reading file...', ...
                        'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort'); drawnow
                    src = io_read(arg, app.Single_DropDown_TextFormat.Value); app.perf("Read file"); app.checkCancelled();
                    if src.Meta.IsCoverage, app.covLoadResults(arg, src.Raw); return; end
                    E = apat_entry(arg, src); k = app.findPat(arg); if k == 0, k = numel(app.Pats) + 1; end
                    app.Single_EditField_Path.Value = arg;
                    app.buildEntry(E, k, 1);
                case "freq",   app.buildEntry(app.Pats(app.Main), app.Main, 2);
                case "step",   app.buildEntry(app.Pats(app.Main), app.Main, 3);
                case "params", app.buildEntry(app.Pats(app.Main), app.Main, 4);
                case "reset"
                    [app.Single_Spinner_Loss.Value, app.Single_DropDown_RxPol.Value, app.Single_Spinner_Rw.Value, app.Single_Spinner_Pt.Value, ...
                        app.Single_DropDown_Pt.Value, app.Single_Spinner_R.Value, app.Single_DropDown_R.Value] = deal(0, 'Auto', 6, 0, 'dBW', 1, 'm');
                    if app.Main > 0, app.buildEntry(app.Pats(app.Main), app.Main, 4); end
                case "component"
                    if app.Main == 0, return; end
                    app.View = app.readConfig(); app.applyRange("full", app.fullLimits(), true);
                    app.renderCut(); app.renderVisible(true); app.applyVisibility(); app.statusMain();
                case "span"
                    if app.Main == 0, return; end
                    canonical = app.View.CutValue; app.View = app.readConfig(); app.View.CutValue = canonical;
                    app.Map = geo_displayMap(app.Pats(app.Main).Pattern, app.Pats(app.Main).Geometry, app.View);
                    app.applyCutDomain(); app.View = app.readConfig();
                    app.renderCut(); app.renderVisible(true); app.renderTables(); app.renderMetadata();
                case {"cut", "plane", "overlay"}
                    if app.Main == 0, return; end
                    if scope == "plane", app.applyPlane(); end
                    previous = app.View.CutType; app.View = app.readConfig();
                    if previous ~= app.View.CutType, app.applyCutDomain(); app.View = app.readConfig(); end
                    app.renderCut(); app.renderOverlays(); app.applyVisibility();
                case "range",  app.onRange(arg{:});
                case "cstep",  app.View = app.readConfig(); app.applyTicks();
                case "annot",  app.View = app.readConfig(); app.renderAnnotations();
                case "tab",    if app.Main > 0, app.renderVisible(false); end
                case "camera", app.View = app.readConfig(); app.applyCamera();
                case "filter", app.toggleFilter(); app.renderTables(); app.applyVisibility();
                case "datatab", if app.Main > 0, app.renderTables(true); end
                case "export",  app.exportData(arg);
                case "covSource",  app.covLoad(arg);
                case "covMain",    app.covFromMain();
                case "covCompute", app.covCompute();
                case "covQuery",   app.covQuery(arg);
                case "covCheck",   app.covChecked();
                case "covSelect",  app.covSelected();
                case "covType",    app.covOrient(); app.applyVisibility();
                case "covOrient",  app.covOrient();
                case "covComp",    app.covPreset();
                case "covClear",   app.covClear();
                case "covReset",   app.covReset();
                case "covRange"    % threshold spinners: user edit ends the automatic preset
                    app.Range.Auto.cov = false;
                    app.applyRange("cov", [app.Cov_Spinner_ThreshMin.Value, app.Cov_Spinner_ThreshMax.Value], false);
                case "covXRange",  app.Range.Auto.covX = false; app.onRange("covX", arg);
            end
        end

        function buildEntry(app, E, k, rung)
            % Build every layer at or below RUNG into locals, then commit Pats(k) in one step (I13).
            [V, prm] = app.readConfig(); if rung <= 1, V.FreqIndex = 1; end
            if rung <= 2, E.Native = pat_build(E.Source, V.FreqIndex); app.perf("Build pattern"); app.checkCancelled(); end
            if rung <= 3
                E.Pattern = E.Native;
                if V.StepOne && ~E.Native.IsOneDegree, E.Pattern = pat_resample(E.Native, 1); app.perf("Resample"); end
                E.Geometry = geo_build(E.Pattern); app.perf("Geometry"); app.checkCancelled();
            end
            E.Derived = pat_derive(E.Pattern, E.Geometry, prm); E.Params = prm; app.perf("Derive");
            if isempty(app.Pats), app.Pats = E; else, app.Pats(k) = E; end
            app.Main = k;
            app.View = app.readConfig(); app.Map = geo_displayMap(E.Pattern, E.Geometry, app.View);
            app.applyChoices(rung); app.View = app.readConfig();
            if rung <= 3
                if app.Range.Auto.full, app.Range.gain = util_presetRange(E.Derived.Peak.value); end
                app.applyRange("full", app.fullLimits(), true);
                if app.Range.Auto.cut, app.applyRange("cut", app.Range.gain, true); end
            end
            app.renderCut(); app.renderVisible(true); app.renderTables(); app.renderMetadata(); app.perf("Render");
            app.applyVisibility(); app.statusMain();
        end

        function applyChoices(app, rung)
            % The only writer of data-derived Items/ItemsData/Limits/Step of Main-tab controls.
            E = app.pat(); D = E.Derived;
            if rung <= 1
                n = numel(E.Source.Blocks); f = E.Source.Freqs(:);
                items = compose('Pattern %d: %.4g GHz', (1:n)', f/1e9); items(~isfinite(f)) = compose('Pattern %d', find(~isfinite(f)));
                [app.Single_DropDown_FFD.Items, app.Single_DropDown_FFD.ItemsData, app.Single_DropDown_FFD.Value] = deal(items, num2cell(1:n), 1);
                app.Single_Table_DataIn.Data = E.Source.Raw; app.Single_Table_DataIn.ColumnName = E.Source.Raw.Properties.VariableNames;
            end
            if rung <= 2
                N = E.Native; previous = app.Single_DropDown_step.Value;
                if N.IsOneDegree, items = {'STEP: 1°'}; data = {'one'};
                else, items = {sprintf('STEP: %g°', max(N.dTheta, N.dPhi)), 'STEP: 1°'}; data = {'native', 'one'}; end
                [app.Single_DropDown_step.Items, app.Single_DropDown_step.ItemsData] = deal(items, data);
                if any(strcmp(data, previous)), app.Single_DropDown_step.Value = previous; end
                if ~E.Pattern.IsGainOnly, app.CutFieldBasisDropDown.Value = char(D.Pol.Basis); end
            end
            if rung <= 3
                sel = ismember(D.Kinds, ["gain", "ar", "plf"]); previous = string(app.Single_DropDown_Component.Value);
                [app.Single_DropDown_Component.Items, app.Single_DropDown_Component.ItemsData] = deal(cellstr(D.Labels(sel)), cellstr(D.Names(sel)));
                app.Single_DropDown_Component.Value = char(util_pick(previous, D.Names(sel)));
                [app.Single_DropDown_output.Items, app.Single_DropDown_output.ItemsData] = deal([{'--- column filter ---'}, cellstr(D.Names)], num2cell(0:numel(D.Names)));
                app.Single_DropDown_output.Value = 0; app.OutMask = ~D.Hidden; app.styleFilter();
                app.applyPlane();
            end
        end

        function applyPlane(app)
            % E/H switch -> cut type and cut value (principal-axis rule, Derived.Planes).
            D = app.Pats(app.Main).Derived; plane = D.Planes.H; if startsWith(app.Single_Switch_EHplane.Value, 'E'), plane = D.Planes.E; end
            app.Single_DropDown_cutType.Value = char(plane.type);
            app.View = app.readConfig(); app.View.CutValue = plane.value;
            app.applyCutDomain();
        end

        function applyCutDomain(app)
            % Cut-value spinner domain and value in the display convention (I8, D46).
            V = app.View; M = app.Map;
            if V.CutType == "Phi", axis = M.ThetaAxis; v = V.CutValue; if V.Elevation, v = 90 - v; end
            else, axis = M.PhiAxis(1:end-double(app.Pats(app.Main).Geometry.PhiPeriodic)); v = mod(V.CutValue, 360); if V.SignedPhi && v >= 180, v = v - 360; end
            end
            [~, i] = min(abs(axis - v)); spinner = app.Single_DropDown_cutValue;
            spinner.Limits = [-360 360]; spinner.Value = axis(i); spinner.Limits = [min(axis), max(axis)];   % widen, set, tighten
            if numel(axis) > 1, spinner.Step = abs(axis(2) - axis(1)); end
        end

        function applyVisibility(app)
            % The only writer of Visible/Enable, computed from data and choices (called once per update).
            has = app.Main > 0; E = []; if has, E = app.pat(); end
            hasE = has && ~E.Pattern.IsGainOnly;
            set([app.Single_Panel_Rect, app.Single_Export_Output, app.Single_Panel_fullPattern, app.Single_Panel_plotControl, ...
                app.Single_Button_Coverage, app.Single_tabData, app.Single_DropDown_output, app.Single_Table_DataOut, app.Single_Table_DataIn], 'Visible', has);
            set([app.Single_Export_UAN, app.Single_gridEcut, app.CheckBox_Et, app.CheckBox_Er, app.CheckBox_El], 'Visible', hasE);
            app.CutFieldBasisDropDown.Enable = hasE;
            app.Single_CheckBox_HPBWBounds.Visible = has && app.Button_HPBW.Value;
            if has
                D = E.Derived; V = app.View;
                showLink = any(D.Kinds == "link") && any(V.OutMask(D.Kinds == "link"));
                set([app.RxPolLabel, app.Single_DropDown_RxPol, app.IncidentWaveARRwPLFLabel, app.Single_Spinner_Rw], 'Visible', any(D.Names == "PLF_dB"));
                set([app.TransmitPowerLabel, app.Single_Spinner_Pt, app.Single_DropDown_Pt, app.DistanceLabel, app.Single_Spinner_R, app.Single_DropDown_R], 'Visible', showLink);
                set([app.LossindBLabel, app.Single_Spinner_Loss], 'Visible', any(D.Kinds == "gain"));
                many = numel(app.Single_DropDown_step.Items) > 1;
                set(app.Single_DropDown_step, 'Visible', many, 'Enable', many);
                blocks = numel(E.Source.Blocks) > 1;
                set([app.Single_DropDown_FFD, app.FFDFreqDropDownLabel], 'Visible', blocks, 'Enable', blocks);
                generic = E.Source.Meta.IsGeneric;
                set([app.TextFormatLabel, app.Single_DropDown_TextFormat], 'Visible', generic);
            end
            app.covVisibility();
        end

        function applyRange(app, group, lim, preset)
            % One descriptor-driven controller for the four range groups; the only writer of range widgets.
            K = apat_const(); g = K.RangeGroups.(group); H = K.Hard; gap = g.gap;
            lim = sort(double(lim(:).')); lim = [max(H(1), lim(1)), min(H(2), lim(2))];
            if diff(lim) < gap, lim(2) = min(H(2), lim(1) + gap); lim(1) = min(lim(1), lim(2) - gap); end
            for s = app.handles(g.sliders)
                L = s.Limits; if preset, L = lim; else, L = [min(L(1), lim(1)), max(L(2), lim(2))]; end
                s.Limits = H; s.Value = lim; s.Limits = L;                  % widen first so Value is never clamped
            end
            [mins, maxs] = deal(app.handles(g.mins), app.handles(g.maxs)); set([mins, maxs], 'Limits', H);
            set(mins, 'Value', lim(1)); set(mins, 'Limits', [H(1), lim(2) - gap]);
            set(maxs, 'Value', lim(2)); set(maxs, 'Limits', [lim(1) + gap, H(2)]);
            app.Range.(group) = lim;
            switch group
                case "full"
                    for F = app.Gfx.Full, clim(F.Axes, lim); end
                    zlim(app.Single_Axes_3dRect, lim); app.applyTicks();
                    if ~app.isAR(), app.Range.gain = lim; end
                case "cut",  set(app.Single_paxCut, 'RLim', lim, 'RTick', lim(1):5:lim(2)); set(app.Single_AxesRect, 'YLim', lim);
                case "covX", app.Cov_Axes.XLim = lim;
            end
        end

        function onRange(app, group, src)
            % Slider / min / max / colorbar spinner edits.  GROUP "all" = colorbar spinners (full + cut).
            if group == "all"
                lim = [app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value];
                app.Range.Auto.full = false; app.Range.Auto.cut = false;
                app.applyRange("full", lim, true); app.applyRange("cut", lim, true); return
            end
            cur = app.Range.(group);
            if isa(src, 'matlab.ui.control.RangeSlider'), lim = src.Value;
            elseif endsWith(src.Tag, 'Min'), lim = [src.Value, cur(2)];
            else, lim = [cur(1), src.Value]; end
            if isfield(app.Range.Auto, group), app.Range.Auto.(group) = false; end
            app.applyRange(group, lim, false);
        end

        function applyTicks(app)
            % Colorbar / Z ticks from the colorbar-step spinner on every full-pattern axes.
            lim = app.Range.full; ticks = util_ticks(lim, app.Single_Plot_Cstep.Value);
            for F = app.Gfx.Full
                if isgraphics(F.Colorbar) && ~isempty(ticks), F.Colorbar.Ticks = ticks; end
            end
            if ~isempty(ticks), app.Single_Axes_3dRect.ZTick = ticks; end
        end

        function applyCamera(app)
            [az, el, up] = util_camera(app.View.Camera, [135 25]);
            for ax = [app.Single_Axes_3dSph, app.Single_Axes_3dPol], view(ax, az, el); camup(ax, up); end
            [az, el, up] = util_camera(app.View.Camera, [-35 35]); view(app.Single_Axes_3dRect, az, el); camup(app.Single_Axes_3dRect, up);
        end

        function toggleFilter(app)
            dd = app.Single_DropDown_output; i = dd.Value;
            if i > 0, app.OutMask(i) = ~app.OutMask(i); dd.Value = 0; end
            app.styleFilter(); app.View = app.readConfig();
        end

        function styleFilter(app)
            dd = app.Single_DropDown_output; if numel(dd.Items) < 2, return; end
            if isempty(app.OutStyles)
                app.OutStyles = {uistyle('FontWeight', 'bold', 'FontColor', 'black', 'BackgroundColor', [0.8 1 0.8]), uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9])};
            end
            on = find(app.OutMask) + 1; items = regexprep(dd.Items, '^✓ ?', ''); items(on) = append('✓ ', items(on));
            dd.Items = items; removeStyle(dd);
            addStyle(dd, app.OutStyles{1}, 'Item', on); addStyle(dd, app.OutStyles{2}, 'Item', setdiff(1:numel(items), on));
        end

        function perf(app, stage)
            % perf("begin <op>") | perf("<stage>") | perf("end") -> app.Perf and base-workspace Perf_<class>.
            if startsWith(stage, "begin"), app.PerfRun = struct('Op', extractAfter(stage, 6), 'T0', tic, 'T', tic, 'Rows', {cell(0, 2)}); return; end
            if isempty(app.PerfRun), return; end
            app.PerfRun.Rows(end + 1, :) = {char(stage), toc(app.PerfRun.T)}; app.PerfRun.T = tic;
            if stage ~= "end", return; end
            app.Perf = struct('AppVersion', class(app), 'Operation', app.PerfRun.Op, ...
                'Stages', cell2table(app.PerfRun.Rows, 'VariableNames', {'Stage', 'Seconds'}), 'TotalSeconds', toc(app.PerfRun.T0));
            assignin('base', matlab.lang.makeValidName("Perf_" + class(app)), app.Perf); app.PerfRun = [];
        end

        function setStatus(app, label, msg, transient)
            % One reusable timer; persistent text lives in app.Status.(label.Tag), not in the widget.
            if app.isClosing || ~isgraphics(label), return; end
            stop(app.StatusTimer); label.Text = char(msg);
            if ~transient, app.Status.(label.Tag) = char(msg); return; end
            app.StatusTimer.TimerFcn = @(~, ~) app.restoreStatus(label); start(app.StatusTimer);
        end

        function restoreStatus(app, label)
            if ~app.isClosing && isgraphics(label) && isfield(app.Status, label.Tag), label.Text = app.Status.(label.Tag); end
        end

        function statusMain(app)
            E = app.pat(); D = E.Derived; pk = D.Peak; f = @util_fmtNumber;
            text = sprintf('Pattern: %s | POB %s %s ( θ=%s°, φ=%s° )', E.File, f(pk.value, 2), E.Pattern.Meta.UnitLabel, f(pk.theta), f(pk.phi));
            if app.View.Component ~= D.PeakCol
                cp = app.compPeak(); text = sprintf('%s | Peak of %s %s ( θ=%s°, φ=%s° )', text, app.compLabel(), f(cp.value, 2), f(cp.theta), f(cp.phi));
            end
            if ~E.Pattern.IsGainOnly, text = sprintf('%s | Polarization %s', text, D.Pol.Label); end
            app.setStatus(app.Single_StatusBar, text, false);
        end

        %% ------------------------------------------------------------------ small accessors
        function E = pat(app), E = app.Pats(app.Main); end

        function k = findPat(app, path)
            k = 0; for i = 1:numel(app.Pats), if strcmp(app.Pats(i).Path, path), k = i; return; end, end
        end

        function h = handles(app, names)
            h = gobjects(1, numel(names)); for i = 1:numel(names), h(i) = app.(names(i)); end
        end

        function tf = isAR(app), tf = app.Main > 0 && any(app.Pats(app.Main).Derived.Kinds(app.Pats(app.Main).Derived.Names == app.View.Component) == "ar"); end

        function lim = fullLimits(app)
            K = apat_const(); if app.isAR(), lim = K.ARLimits; else, lim = app.Range.gain; end
        end

        function label = compLabel(app)
            D = app.Pats(app.Main).Derived; label = D.Labels(D.Names == app.View.Component); if isempty(label), label = app.View.Component; end
        end

        function pk = compPeak(app)
            % Peak of the SELECTED component (marker only); physical facts stay on Derived.Peak (I4).
            E = app.pat(); D = E.Derived;
            if app.View.Component == D.PeakCol, pk = D.Peak; return; end
            K = apat_const(); pk = met_peak(D.Cols.(app.View.Component), E.Pattern, E.Geometry.PhiPeriodic, K.PeakExcessDB);
        end
    end

    %% ------------------------------------------------------------------ renderers (retained graphics)
    methods (Access = private)

        function initGraphics(app)
            % Create every retained handle once: context menu, surfaces' hosts, markers, tips, colorbars, triads, cut lines.
            K = apat_const();
            app.Gfx.Menu = uicontextmenu(app.UIFigure);
            uimenu(app.Gfx.Menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ~) app.deleteTips(app.Gfx.Menu.ContextObject));
            tabs = [app.Single_tabContour, app.Single_tabCircular, app.Single_tab3DSpherical, app.Single_tab3DPolar, app.Single_tab3DRect];
            axesList = {app.Single_Axes_Ctr, app.Single_paxPattern, app.Single_Axes_3dSph, app.Single_Axes_3dPol, app.Single_Axes_3dRect};
            for k = 1:5
                ax = axesList{k}; hold(ax, 'on'); ax.ContextMenu = app.Gfx.Menu;
                if K.Views.kind(k) == "fisheye", marker = polarplot(ax, NaN, NaN, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off');
                else, marker = plot3(ax, NaN, NaN, NaN, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off', 'Clipping', 'off'); end
                F(k) = struct('Tab', tabs(k), 'Axes', ax, 'Kind', K.Views.kind(k), 'Surface', gobjects(1), 'Marker', marker, ...
                    'Tip', gobjects(1), 'Overlay', gobjects(1), 'Colorbar', colorbar(ax), 'Dirty', true); %#ok<AGROW>
            end
            app.Gfx.Full = F;
            for ax = [app.Single_Axes_3dSph, app.Single_Axes_3dPol]
                set(ax, 'Projection', 'orthographic', 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1]);
                axis(ax, 'off'); ax.Interactions = [rotateInteraction, dataTipInteraction];
                colors = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
                for i = 1:3
                    d = 1.35 * double(1:3 == i);
                    quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors{i}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25, 'HandleVisibility', 'off');
                    text(ax, 1.12*d(1), 1.12*d(2), 1.12*d(3), labels{i}, 'Color', colors{i}, 'FontWeight', 'bold');
                end
            end
            app.Single_Axes_3dRect.Interactions = [rotateInteraction, dataTipInteraction]; grid(app.Single_Axes_3dRect, 'on');
            set([app.Single_Axes_Ctr, app.Single_AxesRect], 'Box', 'on', 'Layer', 'top'); daspect(app.Single_Axes_Ctr, [1 1 1]);
            for ax = [app.Single_Axes_Ctr, app.Single_AxesRect], ax.Interactions = [zoomInteraction, dataTipInteraction]; end
            hold(app.Single_paxCut, 'on'); hold(app.Single_AxesRect, 'on'); hold(app.Cov_Axes, 'on');
            set([app.Single_paxCut, app.Single_paxPattern], 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            set([app.Single_paxCut, app.Single_AxesRect, app.Cov_Axes], 'ContextMenu', app.Gfx.Menu);
            palette = app.Single_AxesRect.ColorOrder;
            for t = 1:3
                G.Polar(t) = polarplot(app.Single_paxCut, NaN, NaN, 'LineWidth', 1.4, 'Color', palette(t, :));
                G.Rect(t) = plot(app.Single_AxesRect, NaN, NaN, 'LineWidth', 1.4, 'Color', palette(t, :));
            end
            G.PolarPeak = polarplot(app.Single_paxCut, NaN, NaN, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off');
            G.RectPeak = plot(app.Single_AxesRect, NaN, NaN, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off');
            G.PolarBound = polarplot(app.Single_paxCut, [NaN NaN], [NaN NaN], 'o', 'Color', '#D95319', 'MarkerFaceColor', '#D95319', 'HandleVisibility', 'off');
            G.RectBound = plot(app.Single_AxesRect, [NaN NaN], [NaN NaN], 'o', 'Color', '#D95319', 'MarkerFaceColor', '#D95319', 'HandleVisibility', 'off');
            [G.PeakTips, G.BoundTips, G.Regions, G.S] = deal(gobjects(1, 2), gobjects(1, 4), gobjects(0), []);
            app.Gfx.Cut = G; app.Gfx.TablesDirty = true;
            grid(app.Cov_Axes, 'on'); ylim(app.Cov_Axes, [0 100]); set(app.Cov_Axes, 'Box', 'on', 'Layer', 'top', 'Interactions', dataTipInteraction);
        end

        function deleteTips(app, target)
            ax = ancestor(target, {'axes', 'polaraxes'}); if isempty(ax), ax = app.UIFigure; end
            delete(findobj(ax, 'Type', 'datatip'));                        % the single findobj: user-created tips are not app-owned
        end

        function renderVisible(app, dirtyAll)
            F = app.Gfx.Full; if dirtyAll, [F.Dirty] = deal(true); app.Gfx.Full = F; end
            app.renderFull(find([F.Tab] == app.Single_tabPlots.SelectedTab, 1));
        end

        function renderFull(app, k)
            % One renderer for the five full-pattern views; in-place CData update whenever the grid size is unchanged.
            K = apat_const(); F = app.Gfx.Full(k); if ~F.Dirty, return; end
            E = app.pat(); P = E.Pattern; M = app.Map; V = app.View; lim = app.fullLimits(); unit = char(P.Meta.UnitLabel); label = app.compLabel();
            C = E.Derived.Cols.(V.Component); C = C(:, M.ColIdx);
            [X, Y, Z] = viewCoords(F.Kind, P.Theta, M, C, lim);
            if isgraphics(F.Surface) && isequal(size(F.Surface.CData), size(C))
                set(F.Surface, 'XData', X, 'YData', Y, 'ZData', Z, 'CData', C);
            else
                delete(F.Surface(isgraphics(F.Surface)));
                F.Surface = surface(F.Axes, X, Y, Z, C, 'EdgeColor', 'none', 'FaceColor', K.Views.face(k), 'ContextMenu', app.Gfx.Menu, 'HandleVisibility', 'off');
            end
            [phiGrid, thetaGrid] = meshgrid(M.PhiAxis, M.ThetaAxis);
            try
                F.Surface.DataTipTemplate.DataTipRows = [dataTipTextRow(M.ThetaLabel, thetaGrid, '%.3g°'); dataTipTextRow("Phi", phiGrid, '%.3g°'); dataTipTextRow(label, C, ['%.3g ' unit])];
            catch err
                app.Status.Note = "DataTip template unavailable: " + err.message;
            end
            switch F.Kind
                case {"pcolor", "rect"}
                    step = 30 + 30*(F.Kind == "rect");
                    set(F.Axes, 'XLim', M.PhiLim, 'YLim', M.ThetaLim, 'YDir', M.ThetaDir, 'XTick', M.PhiLim(1):step:M.PhiLim(2), 'YTick', M.ThetaLim(1):step/2:M.ThetaLim(2));
                    xlabel(F.Axes, 'Phi (degree)'); ylabel(F.Axes, M.ThetaLabel + " (degree)"); title(F.Axes, label, 'Interpreter', 'none');
                    if F.Kind == "rect", zlabel(F.Axes, label + " (" + unit + ")", 'Interpreter', 'none'); end
                case "fisheye"
                    set(F.Axes, 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', M.PhiTicks), 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', M.RTicks));
                    title(F.Axes, label + "  |  r=θ, angle=φ", 'Interpreter', 'none', 'FontSize', 9);
                otherwise
                    title(F.Axes, label + "  |  " + M.SpanText, 'Interpreter', 'none');
            end
            F.Dirty = false; app.Gfx.Full(k) = F;
            app.applyTheme(k); app.placeMarker(k); app.renderOverlay(k); app.applyCamera();
        end

        function applyTheme(app, k)
            K = apat_const(); F = app.Gfx.Full(k); lim = app.fullLimits();
            if app.isAR(), map = K.ARMap; else, map = K.GainMap; end
            clim(F.Axes, lim); colormap(F.Axes, map); F.Colorbar.Label.String = char(app.Pats(app.Main).Pattern.Meta.UnitLabel);
            if app.isAR(), F.Colorbar.Label.String = 'dB (+RHCP / −LHCP)'; end
            if F.Kind == "rect", zlim(F.Axes, lim); end
            app.applyTicks();
        end

        function placeMarker(app, k)
            % POB marker of the selected component, re-indexed through the display map; datatip created once.
            F = app.Gfx.Full(k); M = app.Map; pk = app.compPeak(); unit = char(app.Pats(app.Main).Pattern.Meta.UnitLabel);
            [i, j] = ind2sub(size(app.Pats(app.Main).Derived.Cols.(app.View.Component)), pk.index); jd = find(M.ColIdx == j, 1);
            S = F.Surface; x = S.XData(i, jd); y = S.YData(i, jd); z = S.ZData(i, jd);
            if F.Kind == "fisheye", set(F.Marker, 'ThetaData', x, 'RData', y); else, set(F.Marker, 'XData', x, 'YData', y, 'ZData', z); end
            F.Marker.DataTipTemplate.DataTipRows = [dataTipTextRow(M.ThetaLabel, M.ThetaAxis(i), '%.3g°'); dataTipTextRow("Phi", M.PhiAxis(jd), '%.3g°'); ...
                dataTipTextRow(app.compLabel(), pk.value, ['%.3g ' unit])];
            F.Tip = app.ensureTips(F.Tip, F.Marker, 1);
            app.setVis([F.Marker, F.Tip], app.View.POB); app.Gfx.Full(k) = F;
        end

        function renderOverlay(app, k)
            % Cut overlay on the sphere / polar-3D surface, from the one cut extract in Gfx.Cut.S.
            F = app.Gfx.Full(k); S = app.Gfx.Cut.S;
            if ~ismember(F.Kind, ["sphere", "polar"]), return; end
            if isempty(S) || ~app.View.Overlay, app.setVis(F.Overlay, false); return; end
            r = 1.02;
            if F.Kind == "polar", r = 1.01 * util_polarRadius(S.y(:, 1), app.fullLimits(), app.Pats(app.Main).Derived.Cols.(app.View.Component)); end
            [x, y, z] = deal(r.*sind(S.theta).*cosd(S.phi), r.*sind(S.theta).*sind(S.phi), r.*cosd(S.theta));
            if isgraphics(F.Overlay), set(F.Overlay, 'XData', x, 'YData', y, 'ZData', z, 'Visible', 'on');
            else, F.Overlay = plot3(F.Axes, x, y, z, 'k', 'LineWidth', 1.6, 'HandleVisibility', 'off'); end
            app.Gfx.Full(k) = F;
        end

        function renderOverlays(app)
            F = app.Gfx.Full; visible = [F.Tab] == app.Single_tabPlots.SelectedTab;
            for k = find(ismember([F.Kind], ["sphere", "polar"]))
                if visible(k) && ~F(k).Dirty, app.renderOverlay(k); else, app.Gfx.Full(k).Dirty = true; end
            end
        end

        function renderCut(app)
            % One geo_cut extract serves polar + rectangular traces, the peak marker, HPBW and both 3-D overlays.
            E = app.pat(); P = E.Pattern; D = E.Derived; V = app.View; M = app.Map; G = app.Gfx.Cut; unit = char(P.Meta.UnitLabel);
            if P.IsGainOnly, cols = V.Component; names = string(app.compLabel());
            else
                pair = D.Pol.Pairs.(V.Basis); cols = ["E_Total_dB", pair + "_dB"]; names = ["E_Total", pair];
                [app.CheckBox_Er.Text, app.CheckBox_El.Text] = deal(char(pair(1)), char(pair(2)));
            end
            sel = false(1, 3); sel(1:numel(cols)) = V.Traces(1:numel(cols)); if ~any(sel), sel(1) = true; end
            stack = cellfun(@(n) D.Cols.(n), cellstr(cols), 'UniformOutput', false);
            S = geo_cut(P, E.Geometry, cat(3, stack{:}), V.CutType, V.CutValue); S.names = cols;
            if V.SignedPhi, S = util_signedWrap(S); end
            G.S = S; lim = app.Range.cut; a = deg2rad(S.angle);
            for t = 1:3
                if ~sel(t), set([G.Polar(t), G.Rect(t)], 'Visible', 'off'); continue; end
                set(G.Polar(t), 'ThetaData', a, 'RData', max(S.y(:, t), lim(1)), 'Visible', 'on', 'DisplayName', names(t));
                set(G.Rect(t), 'XData', S.angle, 'YData', S.y(:, t), 'Visible', 'on', 'DisplayName', names(t));
                rows = [dataTipTextRow("Angle", S.angle, '%.3g°'); dataTipTextRow("Magnitude", S.y(:, t), ['%.3g ' unit])];
                G.Polar(t).DataTipTemplate.DataTipRows = rows; G.Rect(t).DataTipTemplate.DataTipRows = rows;
            end
            set(app.Single_paxCut, 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', M.PhiTicks));
            set(app.Single_AxesRect, 'XLim', M.PhiLim, 'XTick', M.PhiLim(1):30:M.PhiLim(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(app.Single_AxesRect, V.CutType + " (degree)"); ylabel(app.Single_AxesRect, "Magnitude (" + string(unit) + ")");
            if P.IsGainOnly, ttl = char(names(1)); else, ttl = sprintf('%s cut @ %s = %g°', V.CutType, S.symbol, S.fixed); end
            title(app.Single_paxCut, ttl, 'Interpreter', 'none'); title(app.Single_AxesRect, ttl, 'Interpreter', 'none');
            legend(app.Single_paxCut, G.Polar(sel), 'Location', 'southoutside', 'Orientation', 'horizontal', 'Interpreter', 'none');
            legend(app.Single_AxesRect, G.Rect(sel), 'Location', 'best', 'Interpreter', 'none');
            t1 = find(sel, 1); [pv, ipk] = max(S.y(:, t1), [], 'omitnan');
            set(G.PolarPeak, 'ThetaData', a(ipk), 'RData', max(pv, lim(1))); set(G.RectPeak, 'XData', S.angle(ipk), 'YData', pv);
            rows = [dataTipTextRow("Angle", S.angle(ipk), '%.3g°'); dataTipTextRow("Peak " + names(t1), pv, ['%.3g ' unit])];
            G.PolarPeak.DataTipTemplate.DataTipRows = rows; G.RectPeak.DataTipTemplate.DataTipRows = rows;
            G.PeakTips = app.ensureTips(G.PeakTips, [G.PolarPeak, G.RectPeak], [1 1]);
            delete(G.Regions(isgraphics(G.Regions))); G.Regions = gobjects(0); app.Label_HPBW.Text = '';
            set([G.PolarBound, G.RectBound], 'Visible', 'off');
            if V.HPBW
                [bw, lo, hi] = met_hpbw(S.angle, S.y(:, t1), pv, S.angle(ipk));
                if isfinite(bw)
                    b = [lo, hi]; if M.PhiLim(1) < 0, b = mod(b + 180, 360) - 180; else, b = mod(b, 360); end
                    app.Label_HPBW.Text = sprintf('HPBW %s\n%.1f°\n(%.1f° to %.1f°)', names(t1), bw, b(1), b(2));
                    if b(1) <= b(2), reg = b; else, reg = [M.PhiLim(1), b(2); b(1), M.PhiLim(2)]; end
                    tr = thetaregion(app.Single_paxCut, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    xr = xregion(app.Single_AxesRect, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    G.Regions = [tr(:); xr(:)];
                    set(G.PolarBound, 'ThetaData', deg2rad(b), 'RData', [pv pv] - 3); set(G.RectBound, 'XData', b, 'YData', [pv pv] - 3);
                    rows = [dataTipTextRow("HPBW bound", b, '%.2f°'); dataTipTextRow("Level", [pv pv] - 3, ['%.2f ' unit])];
                    G.PolarBound.DataTipTemplate.DataTipRows = rows; G.RectBound.DataTipTemplate.DataTipRows = rows;
                    G.BoundTips = app.ensureTips(G.BoundTips, [G.PolarBound, G.PolarBound, G.RectBound, G.RectBound], [1 2 1 2]);
                end
            end
            app.Gfx.Cut = G; app.renderAnnotations();
        end

        function renderAnnotations(app)
            % Visibility of app-owned markers and tips only; no numerics, no re-render.
            V = app.View; G = app.Gfx.Cut;
            for F = app.Gfx.Full, app.setVis([F.Marker, F.Tip], V.POB); end
            app.setVis([G.PolarPeak, G.RectPeak, G.PeakTips], V.POB);
            bounds = V.HPBW && ~isempty(app.Label_HPBW.Text);
            app.setVis([G.PolarBound, G.RectBound], bounds); app.setVis(G.BoundTips, bounds && V.HPBWBounds);
        end

        function tips = ensureTips(app, tips, lines, idx)
            % App-owned datatips are created once per marker; a failure (e.g. axes not yet realised) is noted, not swallowed.
            for i = 1:numel(lines)
                if isgraphics(tips(i)), continue; end
                try, tips(i) = datatip(lines(i), 'DataIndex', idx(i), 'HandleVisibility', 'off', 'FontSize', 9);
                catch err, app.Status.Note = "DataTip not created: " + err.message; end
            end
        end

        function setVis(~, h, tf), h = h(isgraphics(h)); if ~isempty(h), set(h, 'Visible', tf); end, end

        function renderTables(app, onlyIfDirty)
            % Results table is pushed only while its tab is showing (65k×17 pushes are the dominant M7 cost).
            if app.Single_tabData.SelectedTab ~= app.Single_tabDataOut, app.Gfx.TablesDirty = true; return; end
            if nargin > 1 && onlyIfDirty && ~app.Gfx.TablesDirty, return; end
            app.Single_Table_DataOut.Data = app.resultsTable(); app.Gfx.TablesDirty = false;
        end

        function T = resultsTable(app)
            % Display-convention long table built from Derived.Cols through the map (also the export source).
            E = app.pat(); D = E.Derived; M = app.Map; nt = numel(M.ThetaAxis); np = numel(M.PhiAxis);
            names = D.Names(app.OutMask); vals = cell(1, numel(names));
            for i = 1:numel(names), X = D.Cols.(names(i)); X = X(:, M.ColIdx); vals{i} = X(:); end
            T = table(repmat(M.ThetaAxis(:), np, 1), repelem(M.PhiAxis(:), nt), vals{:}, 'VariableNames', cellstr(["Theta", "Phi", names]));
        end

        function renderMetadata(app)
            K = apat_const(); E = app.pat(); P = E.Pattern; G = E.Geometry; D = E.Derived; m = D.Metrics; pk = D.Peak; f = @util_fmtNumber; u = P.Meta.UnitLabel;
            sphere = "partial sphere"; if G.IsFullSphere, sphere = "full sphere"; end
            if G.PhiPeriodic, sphere = sphere + ", φ periodic"; end
            rows = {'Source format', P.Meta.Format; 'File', E.File; 'Quantity / unit', char(u)
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', numel(P.Theta)*numel(P.Phi), numel(P.Theta), numel(P.Phi))
                'θ range / step', sprintf('[%s°, %s°] / %s°', f(P.Theta(1)), f(P.Theta(end)), f(P.dTheta))
                'φ range / step', sprintf('[%s°, %s°] / %s°', f(P.Phi(1)), f(P.Phi(end)), f(P.dPhi))
                'Coverage of sphere', sprintf('%s  (Σ ΔΩ / 4π = %s)', sphere, f(G.Omega/(4*pi), 4))};
            if isfinite(P.Freq), rows(end+1, :) = {'Frequency', sprintf('%.4g GHz', P.Freq/1e9)}; end
            if ~P.IsGainOnly
                rows = [rows; {'Polarization', char(D.Pol.Label); 'Cut Co-pol / Cross-pol', char(strjoin(D.Pol.Pairs.(app.View.Basis), ' / '))}];
            end
            rows = [rows; {'Peak (POB)', sprintf('%s %s at [θ %s°, φ %s°]', f(pk.value), u, f(pk.theta), f(pk.phi))
                'Peak policy', sprintf('isolated spike if > %g %s above every grid neighbour (%d found)', K.PeakExcessDB, u, pk.spikeCount)}];
            if pk.wasAdjusted, rows(end+1, :) = {'Raw peak (rejected spike)', sprintf('%s %s', f(pk.rawValue), u)}; end
            rows = [rows; {'Boresight axis', K.PrincipalAxes.labels{D.Boresight}
                'E-plane / H-plane', sprintf('%s = %s° / %s = %s°', D.Planes.E.symbol, f(D.Planes.E.value), D.Planes.H.symbol, f(D.Planes.H.value))
                'HPBW E-plane', sprintf('%s°', f(m.HPBW_E)); 'HPBW H-plane', sprintf('%s°', f(m.HPBW_H))
                'Peak directivity', sprintf('%s dBi', f(m.Directivity)); 'Radiation efficiency', sprintf('%s %%', f(m.Efficiency))
                'Front-to-back', sprintf('%s dB', f(m.FrontBack)); 'AR at peak', sprintf('%s dB', f(m.ARatPeak))
                'Parameters', sprintf('L = %g dB, Rx = %s, Rw = %g dB, Pt = %g dBW, R = %g m', E.Params.L, E.Params.RxMode, E.Params.RxAR_dB, E.Params.Pt_dBW, E.Params.R_m)}];
            for note = P.Meta.Notes(:).', rows(end+1, :) = {'Reader note', char(note)}; end %#ok<AGROW>
            app.Single_Table_metadata.Data = rows;
        end
    end

    %% ------------------------------------------------------------------ coverage tab
    methods (Access = private)

        function covLoad(app, path)
            % "Load File" on the Coverage tab: pattern -> Pats entry + tree node; results file -> curves.
            if isempty(path) || ~isfile(path)
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.ffd;*.ffe;*.ffs;*.cut;*.xlsx;*.csv;*.dat;*.txt', 'Pattern / coverage data'; '*.*', 'All files'}, ...
                    'Select a pattern or coverage results file');
                if isequal(f, 0), return; end
                path = fullfile(p, f);
            end
            app.Cov_EditField_filePath.Value = path;
            k = app.findPat(path);
            if k == 0 || (k ~= app.Main && app.Pats(k).Source.Meta.IsGeneric)          % (re)read unless it is the Main entry
                src = io_read(path, app.Cov_DropDown_TextFormat.Value); app.perf("Read file");
                if src.Meta.IsCoverage, app.covLoadResults(path, src.Raw); return; end
                E = apat_entry(path, src); [~, prm] = app.readConfig();
                E.Native = pat_build(src, 1); E.Pattern = E.Native; E.Geometry = geo_build(E.Pattern);
                E.Derived = pat_derive(E.Pattern, E.Geometry, prm); E.Params = prm; app.perf("Derive");
                if k == 0, k = numel(app.Pats) + 1; end
                if isempty(app.Pats), app.Pats = E; else, app.Pats(k) = E; end
            end
            app.covAddPattern(k);
        end

        function covFromMain(app)
            if app.Main == 0, uialert(app.UIFigure, 'Load and process a pattern first.', 'Coverage'); return; end
            app.TabGroup.SelectedTab = app.Tab2_Coverage; app.Cov_EditField_filePath.Value = app.Pats(app.Main).Path;
            app.covAddPattern(app.Main);
        end

        function covAddPattern(app, k)
            node = [];
            for n = app.Cov_TreeNode_Results.Children(:).'
                if isstruct(n.NodeData) && n.NodeData.k == k, node = n; break; end
            end
            if isempty(node)
                node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📡 ' app.Pats(k).Name]);
                node.NodeData = struct('kind', "pattern", 'k', k);
                app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node];
            end
            expand(app.Cov_Tree); app.Cov_Tree.SelectedNodes = node;
            app.covPreset(); app.covOrient(); app.covRefresh();
            app.setStatus(app.Cov_StatusBar, sprintf('Pattern "<b>%s</b>" ready — L = %g dB, %s.', app.Pats(k).Name, app.Pats(k).Params.L, app.Pats(k).Pattern.Meta.UnitLabel), false);
        end

        function node = covTarget(app)
            % Pattern node to compute on: the selection (or its ancestor), else the most recent pattern node.
            node = []; n = app.Cov_Tree.SelectedNodes;
            while ~isempty(n) && isa(n(1), 'matlab.ui.container.TreeNode')
                if isstruct(n(1).NodeData) && n(1).NodeData.kind == "pattern", node = n(1); return; end
                n = n(1).Parent;
            end
            kids = app.Cov_TreeNode_Results.Children;
            for i = numel(kids):-1:1
                if kids(i).NodeData.kind == "pattern", node = kids(i); return; end
            end
        end

        function covPreset(app)
            % Coverage component items for the target entry; threshold window preset while Range.Auto.cov.
            K = apat_const(); node = app.covTarget(); if isempty(node), return; end
            E = app.Pats(node.NodeData.k); D = E.Derived; sel = ismember(D.Kinds, ["gain", "ar", "plf"]);
            dd = app.Cov_DropDown_Component; previous = string(dd.Value);
            [dd.Items, dd.ItemsData] = deal(cellstr(D.Labels(sel)), cellstr(D.Names(sel))); dd.Value = char(util_pick(previous, D.Names(sel)));
            if app.Range.Auto.cov
                pk = D.Peak; if string(dd.Value) ~= D.PeakCol, pk = met_peak(D.Cols.(dd.Value), E.Pattern, E.Geometry.PhiPeriodic, K.PeakExcessDB); end
                app.applyRange("cov", util_presetRange(pk.value), true);
            end
        end

        function covOrient(app)
            % Auto -> Derived.Boresight; explicit axis -> its (θ, φ).  Spinners stay authoritative afterwards.
            K = apat_const(); C = app.readCoverageConfig(); node = app.covTarget();
            if ~C.Conical || isempty(node), return; end
            idx = C.Orientation; if idx == 0, idx = app.Pats(node.NodeData.k).Derived.Boresight; end
            A = K.PrincipalAxes; [app.Cov_Spinner_ConeTH.Value, app.Cov_Spinner_ConePH.Value] = deal(A.theta(idx), A.phi(idx));
            app.setStatus(app.Cov_StatusBar, sprintf('Cone centre %s (θ=%g°, φ=%g°).', A.labels{idx}, A.theta(idx), A.phi(idx)), true);
        end

        function covCompute(app)
            node = app.covTarget();
            if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            C = app.readCoverageConfig(); E = app.Pats(node.NodeData.k); D = E.Derived;
            assert(isfield(D.Cols, C.Component), 'APAT:NoComponent', 'Component %s is not available for this pattern.', C.Component);
            mask = true(size(E.Geometry.dOmega)); region = "Sph";
            if C.Conical
                mask = cov_coneMask(E.Pattern, C.Center(1), C.Center(2), C.Alpha);
                region = sprintf('Con(%s) α=%s°', util_axisLabel(C.Center), util_fmtNumber(C.Alpha));
            end
            cov = cov_curve(D.Cols.(C.Component), E.Geometry.dOmega, mask, C.T); app.perf("Coverage");
            app.CovRunID = app.CovRunID + 1;
            label = sprintf('R%d %s · %s · L=%g dB', app.CovRunID, region, C.Component, E.Params.L);
            app.covAddJob(node, label, C.T, cov, '📉'); app.covRefresh();
            empty = ''; if ~any(mask, 'all'), empty = ' — <b>empty region</b>'; end
            app.setStatus(app.Cov_StatusBar, sprintf('Run <b>%d</b>: %s on "<b>%s</b>" (%d thresholds)%s.', app.CovRunID, label, E.Name, numel(C.T), empty), false);
        end

        function covAddJob(app, parent, label, T, cov, icon)
            curve = plot(app.Cov_Axes, T, cov, 'LineWidth', 1.6, 'DisplayName', label);
            job = uitreenode(parent, 'Text', [icon ' ' label]);
            job.NodeData = struct('kind', "job", 'id', app.CovRunID, 'label', label, 'T', double(T(:)), 'cov', double(cov(:)), 'Line', curve, 'Query', gobjects(0));
            expand(parent); app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; job];
        end

        function covLoadResults(app, path, R)
            [~, name] = fileparts(path);
            node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📄 ' name]); node.NodeData = struct('kind', "results", 'k', 0);
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node];
            for c = 2:width(R)
                app.CovRunID = app.CovRunID + 1;
                app.covAddJob(node, sprintf('R%d %s', app.CovRunID, R.Properties.VariableNames{c}), R{:, 1}, R{:, c}, '📈');
            end
            app.Cov_Tree.SelectedNodes = node; app.TabGroup.SelectedTab = app.Tab2_Coverage; app.covRefresh();
            app.setStatus(app.Cov_StatusBar, sprintf('Coverage results "%s" loaded (%d curves).', name, width(R) - 1), false);
        end

        function jobs = covJobs(app, nodes)
            % The tree is the registry: jobs are grandchildren of the Results root (optionally under NODES only).
            jobs = matlab.ui.container.TreeNode.empty(0, 1);
            if nargin < 2, nodes = app.Cov_TreeNode_Results.Children; end
            for n = nodes(:).'
                if ~isstruct(n.NodeData), jobs = app.covJobs(); return; end            % root selected -> everything
                if n.NodeData.kind == "job", jobs(end + 1, 1) = n; else, jobs = [jobs; n.Children(:)]; end %#ok<AGROW>
            end
            if numel(jobs) > 1, [~, order] = sort(arrayfun(@(j) j.NodeData.id, jobs)); jobs = jobs(order); end
        end

        function covRefresh(app)
            % Curve visibility, table (union of checked thresholds), legend, X-range preset, visibility.
            jobs = app.covJobs(); checked = app.isChecked(jobs); lines = gobjects(0);
            for i = 1:numel(jobs)
                d = jobs(i).NodeData; app.setVis([d.Line; d.Query(:)], checked(i));
                if checked(i), lines(end + 1) = d.Line; end %#ok<AGROW>
            end
            app.covTable(jobs(checked));
            if isempty(lines), legend(app.Cov_Axes, 'off'); else, legend(app.Cov_Axes, lines, 'Location', 'southwest', 'Interpreter', 'none'); end
            if app.Range.Auto.covX && ~isempty(jobs)
                allT = arrayfun(@(j) j.NodeData.T, jobs, 'UniformOutput', false); allT = vertcat(allT{:});
                app.applyRange("covX", [min(allT), max(allT)], true);
            end
            app.covVisibility();
        end

        function covTable(app, jobs)
            if isempty(jobs), app.Cov_Tabel.Data = table(); return; end
            c = arrayfun(@(j) j.NodeData.T, jobs, 'UniformOutput', false); T = unique(vertcat(c{:}));
            vals = nan(numel(T), numel(jobs)); names = strings(1, numel(jobs));
            for i = 1:numel(jobs), d = jobs(i).NodeData; vals(:, i) = cov_at(d, T); names(i) = extractBefore(d.label + " ·", " ·") + " %"; end
            app.Cov_Tabel.Data = array2table(compose('%.2f', [T, vals]), 'VariableNames', cellstr(["Threshold (dB)", names]));
        end

        function covQuery(app, mode)
            % "Coverage at T" (cov) or "Threshold at c %" (thr) on checked jobs under the selection; one datatip each.
            C = app.readCoverageConfig(); sel = app.Cov_Tree.SelectedNodes; ax = app.Cov_Axes;
            if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to query.', true); return; end
            jobs = app.covJobs(sel); jobs = jobs(app.isChecked(jobs)); hit = false;
            for j = jobs.'
                d = j.NodeData; delete(d.Query(isgraphics(d.Query))); d.Query = gobjects(0);
                if mode == "cov", x = C.QueryT; y = cov_at(d, x); else, y = C.QueryC; x = thr_at(d, y); end
                if isfinite(x) && isfinite(y)
                    d.Line.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", 'XData', '%.2f dB'); dataTipTextRow("Coverage", 'YData', '%.2f %%')];
                    d.Query = [line(ax, [x x], [ax.YLim(1) y], 'Color', d.Line.Color, 'LineStyle', ':', 'HandleVisibility', 'off'); ...
                        line(ax, [ax.XLim(1) x], [y y], 'Color', d.Line.Color, 'LineStyle', ':', 'HandleVisibility', 'off'); ...
                        datatip(d.Line, x, y, 'SnapToDataVertex', 'off', 'HandleVisibility', 'off', 'FontSize', 9)];
                    hit = true;
                end
                j.NodeData = d;
            end
            if ~hit, app.setStatus(app.Cov_StatusBar, 'Query value is outside the range of the checked curves.', true);
            elseif mode == "cov", app.setStatus(app.Cov_StatusBar, sprintf('Coverage queried at %s dB.', util_fmtNumber(C.QueryT)), false);
            else, app.setStatus(app.Cov_StatusBar, sprintf('Threshold queried at %s %% coverage.', util_fmtNumber(C.QueryC)), false); end
        end

        function covChecked(app), app.covRefresh(); end

        function tf = isChecked(app, jobs)
            tf = false(size(jobs)); cn = app.Cov_Tree.CheckedNodes; if ~isempty(cn) && ~isempty(jobs), tf = ismember(jobs, cn); end
        end

        function covSelected(app)
            sel = app.Cov_Tree.SelectedNodes; f = @util_fmtNumber;
            jobs = app.covJobs(); for j = jobs.', d = j.NodeData; d.Line.LineWidth = 1.6; end
            app.covPreset(); app.covVisibility();
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(app.Cov_StatusBar, 'Ready.', false); return; end
            d = sel(1).NodeData;
            if d.kind ~= "job"
                app.setStatus(app.Cov_StatusBar, sprintf('%s "<b>%s</b>" — <b>%d</b> coverage job(s).', d.kind, erase(sel(1).Text, ["📡 ", "📄 "]), numel(sel(1).Children)), false); return
            end
            d.Line.LineWidth = 2.6; [cmax, i] = max(d.cov); t50 = thr_at(d, 50);
            text = sprintf('%s | Threshold [%s, %s] dB step %s | 50%%-coverage threshold <b>%s dB</b> | max <b>%s%%</b> @ <b>%s dB</b>', ...
                d.label, f(d.T(1)), f(d.T(end)), f(util_step(d.T)), f(t50), f(cmax), f(d.T(i)));
            app.setStatus(app.Cov_StatusBar, text, false);
        end

        function covClear(app)
            sel = app.Cov_Tree.SelectedNodes;
            if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to clear.', true); return; end
            jobs = app.covJobs(sel);
            for j = jobs.'
                d = j.NodeData; delete(d.Query(isgraphics(d.Query))); d.Query = gobjects(0); j.NodeData = d; app.deleteTips(d.Line);
            end
            app.setStatus(app.Cov_StatusBar, 'DataTips and query markers cleared.', true);
        end

        function covReset(app)
            delete(app.Cov_TreeNode_Results.Children); cla(app.Cov_Axes); legend(app.Cov_Axes, 'off');
            app.Cov_Tabel.Data = table(); app.CovRunID = 0;
            if app.Main > 0, app.Pats = app.Pats(app.Main); app.Main = 1; else, app.Pats = struct([]); end   % drop unreferenced entries
            app.Range.Auto.cov = true; app.Range.Auto.covX = true;
            app.applyRange("cov", [-40 10], true); app.applyRange("covX", [-40 10], true);
            app.covVisibility(); app.setStatus(app.Cov_StatusBar, 'Coverage workspace reset 🔄', true);
        end

        function covVisibility(app)
            hasPattern = ~isempty(app.covTarget()); hasJobs = ~isempty(app.covJobs()); C = app.readCoverageConfig();
            set([app.Cov_ButtonGroup_CovType, app.ThresholdMindBSpinnerLabel, app.Cov_Spinner_ThreshMin, app.ThresholdMaxdBSpinnerLabel, app.Cov_Spinner_ThreshMax, ...
                app.StepdBSpinnerLabel, app.Cov_Spinner_Step, app.Cov_DropDown_ComponentLabel, app.Cov_DropDown_Component, app.Cov_Button_computeCov], ...
                'Visible', hasPattern, 'Enable', hasPattern);
            set([app.ConeSpinnerLabel, app.Cov_Spinner_ConeTH, app.ConeLabel, app.Cov_Spinner_ConePH, app.ConeAngleLabel, app.Cov_Spinner_ConeAng, ...
                app.Cov_DropDown_OrientationLabel, app.Cov_DropDown_Orientation], 'Visible', hasPattern && C.Conical, 'Enable', hasPattern && C.Conical);
            set([app.Cov_QueryCoverageLabel, app.Cov_Spinner_queryCov, app.Cov_Button_queryCov, app.Cov_QueryThresholdLabel, app.Cov_Spinner_queryThresh, ...
                app.Cov_Button_queryThresh, app.Cov_Button_Export, app.Cov_Button_Clear], 'Visible', hasJobs || hasPattern, 'Enable', hasJobs);
            app.Cov_Button_Reset.Enable = hasJobs || hasPattern; app.Cov_Panel_Results.Visible = hasJobs || hasPattern;
            generic = false; if hasPattern, node = app.covTarget(); generic = app.Pats(node.NodeData.k).Source.Meta.IsGeneric; end
            set([app.Cov_TextFormatLabel, app.Cov_DropDown_TextFormat], 'Visible', generic);
        end
    end

    %% ------------------------------------------------------------------ export
    methods (Access = private)

        function exportData(app, kind)
            % Results / cut / UAN / coverage: built lazily from data, never from a uitable (except the coverage table as displayed).
            types = {'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'};
            folder = pwd; name = 'coverage_results.csv'; label = app.Single_StatusBar;
            if app.Main > 0, E = app.pat(); folder = E.Folder; end
            switch kind
                case "results", T = app.resultsTable(); name = [E.Name '_APAT_results.csv'];
                case "cut"
                    S = app.Gfx.Cut.S; T = array2table([S.angle, S.y], 'VariableNames', cellstr(["Angle_deg", S.names])); name = [E.Name '_cut.csv']; types = types(1:2, :);
                case "uan"
                    assert(~E.Pattern.IsGainOnly, 'APAT:NoField', 'No E-field data to export.');
                    T = app.uanTable(); name = sprintf('%s_%.5f_%gdeg.uan', E.Name, E.Derived.Peak.value, E.Pattern.dTheta);
                    types = [{'*.uan', 'XGTD user-defined antenna (*.uan)'}; types(1:2, :)];
                case "coverage", T = app.Cov_Tabel.Data; label = app.Cov_StatusBar; if isempty(T), return; end
            end
            [f, p] = uiputfile(types, char("Export " + kind), fullfile(folder, name));
            if isequal(f, 0), return; end
            path = fullfile(p, f);
            if endsWith(path, '.uan', 'IgnoreCase', true), app.writeUAN(T, path, E.Pattern.dTheta, E.Pattern.dPhi, E.Derived.Peak.value);
            elseif endsWith(path, '.txt', 'IgnoreCase', true), writetable(T, path, 'Delimiter', '\t');
            else, writetable(T, path); end
            app.setStatus(label, sprintf('%s exported to <b>%s</b>', kind, path), true);
        end

        function T = uanTable(app)
            % Canonical UAN rows (φ-major, closing φ column when periodic) from the field scaled by the current loss.
            E = app.pat(); P = E.Pattern; s = 10^(E.Params.L/20); phi = P.Phi;
            [Eth, Eph] = deal(P.Eth * s, P.Eph * s);
            if E.Geometry.PhiPeriodic, phi(end + 1) = phi(1) + 360; Eth(:, end + 1) = Eth(:, 1); Eph(:, end + 1) = Eph(:, 1); end
            nt = numel(P.Theta); np = numel(phi); dB = @(x) round(20*log10(max(abs(x(:)), eps)), 5); dg = @(x) round(rad2deg(angle(x(:))), 5);
            T = table(repmat(P.Theta(:), np, 1), repelem(phi(:), nt), dB(Eth), dB(Eph), dg(Eth), dg(Eph), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'});
        end

        function writeUAN(~, T, path, dTheta, dPhi, maxGain)
            header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                min(T.Phi), max(T.Phi), dPhi, min(T.Theta), max(T.Theta), dTheta, maxGain);
            writelines(header, path);
            writetable(T, path, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
        end
    end

    %% ------------------------------------------------------------------ lifecycle
    methods (Access = private)

        function startupFcn(app)
            app.StatusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3);
            app.initGraphics();
            app.Status = struct('Main', 'Ready -- load an antenna pattern file to begin 🚀', 'Cov', 'Ready 🚀');
            app.Single_StatusBar.Text = app.Status.Main; app.Cov_StatusBar.Text = app.Status.Cov;
            for g = ["full", "cut", "cov", "covX"], app.applyRange(g, [-40 10], true); end
            app.applyVisibility();
        end

        function onLoad(app)
            path = strtrim(app.Single_EditField_Path.Value);
            if isempty(path) || ~isfile(path)
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.csv;*.dat;*.txt', 'Pattern/Gain Files'}, 'Select an antenna pattern file');
                if isequal(f, 0), return; end
                path = fullfile(p, f);
            end
            app.on("source", path);
        end

        function onFormat(app)
            if app.Main > 0 && app.Pats(app.Main).Source.Meta.IsGeneric, app.on("source", app.Pats(app.Main).Path); end
        end

        function checkCancelled(app)
            if ~isempty(app.Dialog) && isvalid(app.Dialog) && app.Dialog.CancelRequested
                error('APAT:Cancelled', 'Operation cancelled by user.');
            end
        end

        function showError(app, err, titleText)
            if app.isClosing || ~isvalid(app.UIFigure), return; end
            where = ''; if ~isempty(err.stack), where = sprintf('\n(%s line %d)', err.stack(1).name, err.stack(1).line); end
            uialert(app.UIFigure, [err.message where], char(titleText), 'Icon', 'error');
        end

        function shutdown(app)
            if ~isempty(app.StatusTimer) && isvalid(app.StatusTimer), stop(app.StatusTimer); delete(app.StatusTimer); end
            if ~isempty(app.Dialog) && isvalid(app.Dialog), delete(app.Dialog); end
        end
    end

    methods (Access = public)

        function app = APAT_v3_M8_8
            createComponents(app)
            registerApp(app, app.UIFigure)
            runStartupFcn(app, @startupFcn)
            if nargout == 0, clear app, end
        end

        function closeRequest(app, ~)
            if app.isClosing, return; end
            app.isClosing = true; app.shutdown(); delete(app.UIFigure);
        end

        function delete(app)
            if ~app.isClosing, app.isClosing = true; app.shutdown(); end
            if ~isempty(app.UIFigure) && isgraphics(app.UIFigure), delete(app.UIFigure); end
        end
    end

    %% ------------------------------------------------------------------ layout (declarative)
    methods (Access = private)

        function h = place(~, ctor, parent, row, col, varargin)
            h = ctor(parent, varargin{:}); h.Layout.Row = row; h.Layout.Column = col;
        end

        function [lbl, h] = labelled(app, parent, text, row, col, ctor, varargin)
            lbl = app.place(@uilabel, parent, row, col, 'Text', text, 'HorizontalAlignment', 'right');
            h = app.place(ctor, parent, row, col(end) + 1, varargin{:});
        end

        function [tab, g, ax, sl, mn, mx] = patternTab(app, group, title, hasAxes, tag)
            tab = uitab(group, 'Title', title); g = uigridlayout(tab, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
            ax = []; if hasAxes, ax = app.place(@uiaxes, g, [1 3], 2); end
            sl = app.place(@(p, varargin) uislider(p, 'range', varargin{:}), g, 2, 1, 'Limits', [-250 100], 'Value', [-250 100], ...
                'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s, ~) app.on("range", {"full", s}));
            mx = app.place(@uispinner, g, 1, 1, 'Limits', [-250 100], 'Value', 100, 'Step', 5, 'Tag', [tag 'Max'], 'ValueChangedFcn', @(s, ~) app.on("range", {"full", s}));
            mn = app.place(@uispinner, g, 3, 1, 'Limits', [-250 100], 'Value', -250, 'Step', 5, 'Tag', [tag 'Min'], 'ValueChangedFcn', @(s, ~) app.on("range", {"full", s}));
        end

        function dd = formatDropdown(~, parent, callback)
            dd = uidropdown(parent, 'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
                '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', '6: POL1=RCP, POL2=LCP — real, imaginary', ...
                '7: POL1=LCP, POL2=RCP — real, imaginary'}, 'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', ...
                'rcp_lcp_reim', 'lcp_rcp_reim'}, 'Value', 'gain', 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'ValueChangedFcn', callback);
        end

        function createComponents(app)
            K = apat_const(); pl = @(varargin) app.place(varargin{:}); lb = @(varargin) app.labelled(varargin{:}); sw = @(p, varargin) uiswitch(p, 'slider', varargin{:});
            fmtDD = @(parent, callback) app.formatDropdown(parent, callback);
            grey = [0.9412 0.9412 0.9412]; cb = @(scope, varargin) @(~, ~) app.on(scope, varargin{:});
            app.UIFigure = uifigure('Name', K.ReleaseName, 'Visible', 'off', 'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', @(~, e) app.closeRequest(e));
            app.GridLayout = uigridlayout(app.UIFigure, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.TabGroup = pl(@uitabgroup, app.GridLayout, 1, 1);
            % ---- Main tab
            app.Tab1_Single = uitab(app.TabGroup, 'Title', 'Process Pattern 📡');
            app.Single_Grid = uigridlayout(app.Tab1_Single, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});
            app.Single_Panel_fullPattern = pl(@uipanel, app.Single_Grid, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'BackgroundColor', grey, 'FontWeight', 'bold');
            app.Single_gridPanel_full = uigridlayout(app.Single_Panel_fullPattern, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_tabPlots = pl(@uitabgroup, app.Single_gridPanel_full, 1, 1, 'SelectionChangedFcn', cb("tab"));
            [app.Single_tabContour, app.Single_gridContour, app.Single_Axes_Ctr, app.Range_Ctr, app.Range_Ctr_Min, app.Range_Ctr_Max] = app.patternTab(app.Single_tabPlots, 'Contour Plot', true, 'Ctr');
            [app.Single_tabCircular, app.Single_gridCircular, ~, app.Range_Cir, app.Range_Cir_Min, app.Range_Cir_Max] = app.patternTab(app.Single_tabPlots, 'Circular Contour Plot', false, 'Cir');
            app.Single_paxPattern = pl(@polaraxes, app.Single_gridCircular, [1 3], 2);
            [app.Single_tab3DSpherical, app.Single_grid3dSpherical, app.Single_Axes_3dSph, app.Range_3dSph, app.Range_3dSph_Min, app.Range_3dSph_Max] = app.patternTab(app.Single_tabPlots, '3D Spherical Plot', true, 'Sph');
            [app.Single_tab3DPolar, app.Single_grid3dPolar, app.Single_Axes_3dPol, app.Range_3dPol, app.Range_3dPol_Min, app.Range_3dPol_Max] = app.patternTab(app.Single_tabPlots, '3D Polar Plot', true, 'Pol');
            [app.Single_tab3DRect, app.Single_grid3dRect, app.Single_Axes_3dRect, app.Range_3dRect, app.Range_3dRect_Min, app.Range_3dRect_Max] = app.patternTab(app.Single_tabPlots, '3D Surface Plot', true, 'Rect');
            app.Single_Panel_Rect = pl(@uipanel, app.Single_Grid, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'BackgroundColor', grey, 'FontWeight', 'bold');
            app.Single_gridPanel_Cut = uigridlayout(app.Single_Panel_Rect, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_tabCut = pl(@uitabgroup, app.Single_gridPanel_Cut, 1, 1, 'SelectionChangedFcn', cb("annot"));
            app.Single_tabPolarPlot = uitab(app.Single_tabCut, 'Title', 'Polar Cut Plot');
            app.Single_Grid_Polar = uigridlayout(app.Single_tabPolarPlot, 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            app.Range_Cut = pl(@(p, varargin) uislider(p, 'range', varargin{:}), app.Single_Grid_Polar, [2 3], 1, 'Limits', [-250 100], 'Value', [-250 100], 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s, ~) app.on("range", {"cut", s}));
            app.Range_Cut_Max = pl(@uispinner, app.Single_Grid_Polar, 1, 1, 'Limits', [-250 100], 'Value', 100, 'Step', 5, 'Tag', 'CutMax', 'ValueChangedFcn', @(s, ~) app.on("range", {"cut", s}));
            app.Range_Cut_Min = pl(@uispinner, app.Single_Grid_Polar, 4, 1, 'Limits', [-250 100], 'Value', -250, 'Step', 5, 'Tag', 'CutMin', 'ValueChangedFcn', @(s, ~) app.on("range", {"cut", s}));
            app.Button_HPBW = pl(@(p, varargin) uibutton(p, 'state', varargin{:}), app.Single_Grid_Polar, 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', cb("cut"));
            app.Label_HPBW = pl(@uilabel, app.Single_Grid_Polar, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            app.Button_ExportCut = pl(@uibutton, app.Single_Grid_Polar, 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', cb("export", "cut"));
            app.Single_gridEcut = pl(@uigridlayout, app.Single_Grid_Polar, 3, 4, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x', '1x', '1x'});
            app.CheckBox_Et = pl(@uicheckbox, app.Single_gridEcut, 1, 1, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', cb("cut"));
            app.CheckBox_Er = pl(@uicheckbox, app.Single_gridEcut, 2, 1, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', cb("cut"));
            app.CheckBox_El = pl(@uicheckbox, app.Single_gridEcut, 3, 1, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', cb("cut"));
            app.Single_paxCut = pl(@polaraxes, app.Single_Grid_Polar, [1 4], 3);
            app.Single_tabRectPlot = uitab(app.Single_tabCut, 'Title', 'Rectangular Cut Plot');
            app.Single_gridRect = uigridlayout(app.Single_tabRectPlot);
            app.Single_AxesRect = pl(@uiaxes, app.Single_gridRect, [1 2], [1 2], 'XLim', [0 180], 'Box', 'on');
            xlabel(app.Single_AxesRect, 'Theta (degree)'); ylabel(app.Single_AxesRect, 'Magnitude (dB)');
            app.Single_DropDown_output = pl(@uidropdown, app.Single_Grid, 3, [13 14], 'Items', {'--- column filter ---'}, 'ItemsData', {0}, 'Value', 0, 'ValueChangedFcn', cb("filter"));
            app.Single_tabData = pl(@uitabgroup, app.Single_Grid, 4, [1 14], 'SelectionChangedFcn', cb("datatab"));
            app.Single_tabDataOut = uitab(app.Single_tabData, 'Title', 'Results 📤');
            app.Single_gridDataOut = uigridlayout(app.Single_tabDataOut, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_DataOut = pl(@uitable, app.Single_gridDataOut, 1, 1, 'BackgroundColor', [1 1 1], 'ColumnWidth', '1x', 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true);
            app.Single_tabDataIn = uitab(app.Single_tabData, 'Title', 'Input 📥');
            app.Single_gridDataIn = uigridlayout(app.Single_tabDataIn, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_DataIn = pl(@uitable, app.Single_gridDataIn, 1, 1, 'BackgroundColor', [1 1 1], 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true);
            app.MetadataTab = uitab(app.Single_tabData, 'Title', 'Metadata 📋');
            app.Single_gridMetadata = uigridlayout(app.MetadataTab, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_metadata = pl(@uitable, app.Single_gridMetadata, 1, 1, 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            app.Single_Panel_plotControl = pl(@uipanel, app.Single_Grid, 2, [13 14], 'Title', 'Plot Control 🎨');
            g = uigridlayout(app.Single_Panel_plotControl, 'RowHeight', repmat({'fit'}, 1, 15)); app.Single_gridPanel_Ctrl = g;
            [app.ComponentLabel, app.Single_DropDown_Component] = lb(g, 'Component', 1, 1, @uidropdown, 'Items', cellstr(K.Cols.label(1:7)), 'ItemsData', cellstr(K.Cols.name(1:7)), 'Value', 'E_Total_dB', 'ValueChangedFcn', cb("component"));
            [app.CuttypeDropDownLabel, app.Single_DropDown_cutType] = lb(g, 'Cut type', 2, 1, @uidropdown, 'Items', {'Phi', 'Theta'}, 'Value', 'Phi', 'ValueChangedFcn', cb("cut"));
            [app.CutvalueSpinnerLabel, app.Single_DropDown_cutValue] = lb(g, 'Cut value', 3, 1, @uispinner, 'Limits', [0 360], 'Value', 0, 'ValueChangedFcn', cb("cut"));
            [app.CutFieldsLabel, app.CutFieldBasisDropDown] = lb(g, 'Cut fields', 4, 1, @uidropdown, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Value', 'Circular', 'Enable', 'off', 'ValueChangedFcn', cb("cut"));
            [app.ColorbarmaxLabel, app.Single_Plot_Cmax] = lb(g, 'Colorbar max', 5, 1, @uispinner, 'Limits', [-250 100], 'Value', 10, 'ValueChangedFcn', @(s, ~) app.on("range", {"all", s}));
            [app.ColorbarminLabel, app.Single_Plot_Cmin] = lb(g, 'Colorbar min', 6, 1, @uispinner, 'Limits', [-250 100], 'Value', -40, 'ValueChangedFcn', @(s, ~) app.on("range", {"all", s}));
            [app.ColorbarstepLabel, app.Single_Plot_Cstep] = lb(g, 'Colorbar step', 7, 1, @uispinner, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', cb("cstep"));
            [app.Single_Label_Clim, app.Single_Button_Clim] = lb(g, 'Adjust Colorbar', 8, 1, @uibutton, 'Text', 'Apply', 'Tooltip', 'Apply to full-pattern and cut plots.', 'ButtonPushedFcn', @(s, ~) app.on("range", {"all", s}));
            [app.View3DLabel, app.Single_DropDown_3DView] = lb(g, '3D view', 9, 1, @uidropdown, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Value', 'iso', 'Tooltip', 'Camera direction for the 3D pattern tabs.', 'ValueChangedFcn', cb("camera"));
            app.Single_Switch_AngularSpan = pl(sw, g, 10, [1 2], 'Items', {['φ span: 0° to 360°' repmat(char(160), 1, 3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'Value', '0° to 360°', 'ValueChangedFcn', cb("span"));
            app.Single_Switch_ThetaSpan = pl(sw, g, 11, [1 2], 'Items', {'θ span: 0° to 180°', ['−90° to 90°' repmat(char(160), 1, 2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'Value', '0° to 180°', 'ValueChangedFcn', cb("span"));
            app.Single_Switch_EHplane = pl(sw, g, 12, [1 2], 'Items', {[repmat(char(160), 1, 8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'Value', 'E-Plane cut', 'ValueChangedFcn', cb("plane"));
            app.Singel_CheckBox_overlayCut = pl(@uicheckbox, g, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', cb("overlay"));
            app.Single_CheckBox_POB = pl(@uicheckbox, g, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', cb("annot"));
            app.Single_CheckBox_HPBWBounds = pl(@uicheckbox, g, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'ValueChangedFcn', cb("annot"));
            app.Single_StatusBar = pl(@uilabel, app.Single_Grid, 5, [1 14], 'Interpreter', 'html', 'Text', 'Ready 🚀', 'Tag', 'Main');
            app.Single_panelParam = pl(@uipanel, app.Single_Grid, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️');
            g = uigridlayout(app.Single_panelParam, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'}); app.Single_gridPanel_Param = g;
            app.InputPatternLabel = pl(@uilabel, g, 1, 1, 'Text', 'Input Pattern:', 'HorizontalAlignment', 'right');
            app.Single_EditField_Path = pl(@uieditfield, g, 1, [2 8]);
            [app.RxPolLabel, app.Single_DropDown_RxPol] = lb(g, 'Rw Sense', 3, 1, @uidropdown, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Value', 'Auto', 'Editable', 'on');
            [app.IncidentWaveARRwPLFLabel, app.Single_Spinner_Rw] = lb(g, 'Rw (dB)', 3, 3, @uispinner, 'Value', 6);
            [app.LossindBLabel, app.Single_Spinner_Loss] = lb(g, 'Loss (−) / Gain (+) dB', 3, 5, @uispinner, 'Step', 0.1);
            [app.TransmitPowerLabel, app.Single_Spinner_Pt] = lb(g, 'Tx Pwr (Pt)', 3, 7, @uispinner, 'Value', 0);
            app.Single_DropDown_Pt = pl(@uidropdown, g, 3, 9, 'Items', {'dBW', 'dBm', 'Watts'}, 'Value', 'dBW');
            [app.DistanceLabel, app.Single_Spinner_R] = lb(g, 'Distance', 3, 10, @uispinner, 'Value', 1);
            app.Single_DropDown_R = pl(@uidropdown, g, 3, 12, 'Items', {'m', 'km'}, 'Value', 'm');
            app.Single_Button_Load = pl(@uibutton, g, 1, [11 12], 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.onLoad());
            app.Single_Button_Process = pl(@uibutton, g, 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', cb("params"));
            app.Single_Button_ResetParams = pl(@uibutton, g, 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', cb("reset"));
            app.TextFormatLabel = pl(@uilabel, g, 2, [4 5], 'Text', 'Format:', 'HorizontalAlignment', 'right');
            app.Single_DropDown_TextFormat = pl(fmtDD, g, 2, [6 8], @(~, ~) app.onFormat());
            app.Single_DropDown_step = pl(@uidropdown, g, 2, [9 10], 'Items', {'STEP'}, 'ItemsData', {'native'}, 'Placeholder', 'STEP', 'ValueChangedFcn', cb("step"));
            app.Single_Export_Output = pl(@uibutton, g, 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'ButtonPushedFcn', cb("export", "results"));
            app.Single_Export_UAN = pl(@uibutton, g, 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'ButtonPushedFcn', cb("export", "uan"));
            [app.FFDFreqDropDownLabel, app.Single_DropDown_FFD] = lb(g, 'FFD Freq:', 1, 9, @uidropdown, 'Items', {'Frequencies'}, 'ItemsData', {1}, 'Value', 1, 'ValueChangedFcn', cb("freq"));
            app.Single_Button_Coverage = pl(@uibutton, g, 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'ButtonPushedFcn', cb("covMain"));
            % ---- Coverage tab
            app.Tab2_Coverage = uitab(app.TabGroup, 'Title', 'Compute Coverage 📈');
            app.Cov_Grid = uigridlayout(app.Tab2_Coverage, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            app.Cov_Panel_Param = pl(@uipanel, app.Cov_Grid, 1, [1 5], 'Title', 'Inputs & Parameters 🎛️');
            g = uigridlayout(app.Cov_Panel_Param, 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'}); app.Cov_gridPanel_Parm = g;
            app.Cov_ButtonGroup_CovType = pl(@uibuttongroup, g, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', cb("covType"));
            app.Cov_ButtonGroup_Btn_Spherical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            app.Cov_ButtonGroup_Btn_Conical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            [app.Cov_DropDown_OrientationLabel, app.Cov_DropDown_Orientation] = lb(g, 'Orientation 🧭:', 3, 1, @uidropdown, 'Items', [{'Auto'}, K.PrincipalAxes.labels], ...
                'ItemsData', num2cell(0:numel(K.PrincipalAxes.labels)), 'Value', 0, 'ValueChangedFcn', cb("covOrient"));
            app.AntennaPatternEditFieldLabel = pl(@uilabel, g, 1, 3, 'Text', 'Antenna Pattern:', 'HorizontalAlignment', 'right');
            app.Cov_EditField_filePath = pl(@uieditfield, g, 1, [4 8]);
            app.Cov_Button_Load = pl(@uibutton, g, 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', @(~, ~) app.on("covSource", strtrim(app.Cov_EditField_filePath.Value)));
            app.Cov_Button_computeCov = pl(@uibutton, g, 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'ButtonPushedFcn', cb("covCompute"));
            [app.ThresholdMindBSpinnerLabel, app.Cov_Spinner_ThreshMin] = lb(g, 'Threshold  Min (dB):', 2, 3, @uispinner, 'Value', -40, 'ValueChangedFcn', cb("covRange"));
            [app.ThresholdMaxdBSpinnerLabel, app.Cov_Spinner_ThreshMax] = lb(g, 'Threshold  Max (dB):', 2, 5, @uispinner, 'Value', 10, 'ValueChangedFcn', cb("covRange"));
            [app.StepdBSpinnerLabel, app.Cov_Spinner_Step] = lb(g, 'Step (dB):', 2, 7, @uispinner, 'Value', 1, 'Limits', [0.1 100]);
            app.Cov_Button_Reset = pl(@uibutton, g, 2, 9, 'Text', '🔄 Reset', 'ButtonPushedFcn', cb("covReset"));
            app.Cov_Button_Export = pl(@uibutton, g, 2, 10, 'Text', '💾 Export Results', 'ButtonPushedFcn', cb("export", "coverage"));
            [app.ConeSpinnerLabel, app.Cov_Spinner_ConeTH] = lb(g, 'Cone θ₀ (°):', 3, 3, @uispinner, 'Limits', [0 180]);
            [app.ConeLabel, app.Cov_Spinner_ConePH] = lb(g, 'Cone φ₀ (°):', 3, 5, @uispinner, 'Limits', [0 360]);
            [app.ConeAngleLabel, app.Cov_Spinner_ConeAng] = lb(g, 'Cone Angle α (°):', 3, 7, @uispinner, 'Limits', [0 180], 'Value', 45);
            app.Cov_Button_Clear = pl(@uibutton, g, 3, 9, 'Text', '🧹 Clear DataTips', 'ButtonPushedFcn', cb("covClear"));
            app.Cov_Button_toMain = pl(@uibutton, g, 3, 10, 'Text', '📊 To Main ◀ ', 'ButtonPushedFcn', @(~, ~) set(app.TabGroup, 'SelectedTab', app.Tab1_Single));
            [app.Cov_DropDown_ComponentLabel, app.Cov_DropDown_Component] = lb(g, 'Component:', 4, 1, @uidropdown, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', cb("covComp"));
            [app.Cov_QueryCoverageLabel, app.Cov_Spinner_queryCov] = lb(g, 'Coverage @ dB:', 4, 3, @uispinner, 'ValueDisplayFormat', '%g dB');
            app.Cov_Button_queryCov = pl(@uibutton, g, 4, 5, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', cb("covQuery", "cov"));
            [app.Cov_QueryThresholdLabel, app.Cov_Spinner_queryThresh] = lb(g, 'Threshold @ %:', 4, 6, @uispinner, 'ValueDisplayFormat', '%g%%', 'Value', 50, 'Limits', [0 100]);
            app.Cov_Button_queryThresh = pl(@uibutton, g, 4, 8, 'Text', '🔍︎ Query Threshold', 'ButtonPushedFcn', cb("covQuery", "thr"));
            app.Cov_TextFormatLabel = pl(@uilabel, g, 4, 9, 'Text', 'Format:', 'HorizontalAlignment', 'right');
            app.Cov_DropDown_TextFormat = pl(fmtDD, g, 4, 10, @(~, ~) app.on("covSource", strtrim(app.Cov_EditField_filePath.Value)));
            app.Cov_StatusBar = pl(@uilabel, app.Cov_Grid, 3, [1 5], 'Interpreter', 'html', 'Text', 'Ready 🚀', 'Tag', 'Cov');
            app.Cov_Panel_Results = pl(@uipanel, app.Cov_Grid, 2, [1 5], 'Title', 'Results');
            g = uigridlayout(app.Cov_Panel_Results, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'}); app.GridLayout2 = g;
            app.Cov_Axes = pl(@uiaxes, g, 1, [2 4]);
            title(app.Cov_Axes, 'Coverage(T) = 100·Ω_R(G > T) / Ω_R', 'Interpreter', 'none'); xlabel(app.Cov_Axes, 'Threshold (dB)'); ylabel(app.Cov_Axes, 'Coverage (%)');
            app.Cov_Tree = pl(@(p, varargin) uitree(p, 'checkbox', varargin{:}), g, [1 2], 1, 'SelectionChangedFcn', cb("covSelect"), 'CheckedNodesChangedFcn', cb("covCheck"));
            app.Cov_TreeNode_Results = uitreenode(app.Cov_Tree, 'Text', 'Coverage Results');
            app.Cov_Tabel = pl(@uitable, g, [1 2], 5, 'ColumnWidth', '1x', 'RowName', {});
            app.Cov_Spinner_XMin = pl(@uispinner, g, 2, 2, 'Limits', [-250 100], 'Value', -40, 'Tag', 'XMin', 'ValueChangedFcn', @(s, ~) app.on("covXRange", s));
            app.Cov_Spinner_XRange = pl(@(p, varargin) uislider(p, 'range', varargin{:}), g, 2, 3, 'Limits', [-250 100], 'Value', [-40 10], 'ValueChangedFcn', @(s, ~) app.on("covXRange", s));
            app.Cov_Spinner_XMax = pl(@uispinner, g, 2, 4, 'Limits', [-250 100], 'Value', 10, 'Tag', 'XMax', 'ValueChangedFcn', @(s, ~) app.on("covXRange", s));
            app.UIFigure.Visible = 'on';
        end
    end
end

%% ====================================================================== file-scope: readers
% Every reader returns a Source:
%   Source.Raw    table shown on the Input tab (the file's own quantities)
%   Source.Blocks {struct('Theta',N×1,'Phi',N×1,'Data',N×4 [Re Eθ, Im Eθ, Re Eφ, Im Eφ] | N×nC gain columns)}
%   Source.Freqs  one frequency per block (Hz, NaN when unknown)
%   Source.Meta   Format, Unit ("dBi"|"dB"), UnitLabel, IsGainOnly, IsCoverage, IsGeneric, ColNames, Notes

function S = io_read(path, textFormat)
[~, ~, ext] = fileparts(path); ext = upper(erase(ext, '.'));
M = struct('Format', ext, 'Unit', "dB", 'UnitLabel', "dB (rel. field)", 'IsGainOnly', false, 'IsCoverage', false, 'IsGeneric', false, ...
    'ColNames', strings(1, 0), 'Notes', strings(1, 0));
switch ext
    case {'XLSX', 'XLS'},                          S = io_excel(path, M);
    case {'CSV', 'TXT', 'DAT'},                    S = io_text(path, string(textFormat), M);
    case 'CUT',                                    S = io_cut(path, M);
    case {'UAN', 'FZ', 'OUT', 'FFS', 'FFE', 'FFD'}, S = io_field(path, ext, M);
    otherwise, error('APAT:Unsupported', 'Unsupported format: %s', ext);
end
end

function S = io_source(Raw, blocks, freqs, M)
S = struct('Raw', Raw, 'Blocks', {blocks}, 'Freqs', freqs, 'Meta', M);
end

function [theta, phi, F] = io_fields(D, angleCols, domain, layout, basis)
%IO_FIELDS Six numeric columns -> canonical [Re Eθ, Im Eθ, Re Eφ, Im Eφ].
%   angleCols [θ col, φ col]; domain "reim"|"magphase" (dB, degrees); layout "grouped" [m1 m2 p1 p2] |
%   "interleaved" [m1 p1 m2 p2]; basis "linear" (Eθ,Eφ) | "rcp" (RHCP,LHCP) | "lcp" (LHCP,RHCP).
theta = D(:, angleCols(1)); phi = D(:, angleCols(2)); V = D(:, 3:6);
if domain == "magphase"
    if layout == "interleaved", m = V(:, [1 3]); p = V(:, [2 4]); else, m = V(:, [1 2]); p = V(:, [3 4]); end
    c1 = 10.^(m(:, 1)/20) .* exp(1i*deg2rad(p(:, 1))); c2 = 10.^(m(:, 2)/20) .* exp(1i*deg2rad(p(:, 2)));
else
    c1 = complex(V(:, 1), V(:, 2)); c2 = complex(V(:, 3), V(:, 4));
end
switch basis
    case "linear", [Eth, Eph] = deal(c1, c2);
    case "rcp",    [Eth, Eph] = pol_fromCircular(c1, c2);
    otherwise,     [Eth, Eph] = pol_fromCircular(c2, c1);
end
F = [real(Eth), imag(Eth), real(Eph), imag(Eph)];
end

function S = io_field(path, ext, M)
%IO_FIELD UAN/FZ, OUT, FFS, FFE, FFD through one converter and a per-format spec.
[nHdr, ffd, headerText] = io_header(path);
opts = detectImportOptions(path, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
D = readmatrix(path, setvartype(opts, 'double')); freqs = NaN;
if ext == "FFD"
    assert(ffd.isFFD, 'APAT:FFDHeader', 'FFD header (theta/phi ranges) not found.');
    th = linspace(ffd.theta(1), ffd.theta(2), ffd.theta(3)).'; ph = linspace(ffd.phi(1), ffd.phi(2), ffd.phi(3)).';
    theta = repelem(th, numel(ph)); phi = repmat(ph, numel(th), 1); n = numel(theta);
    sep = isnan(D(:, 1)); f = [ffd.freq(:); D(sep, 2)]; freqs = f(isfinite(f)).'; rows = D(~sep, 1:4);
    names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; M.Format = 'HFSS FFD';
else
    D = D(all(isfinite(D(:, 1:2)), 2), 1:min(6, size(D, 2)));
    assert(size(D, 2) >= 6, 'APAT:Columns', '%s files need six numeric columns.', ext);
    switch ext
        case {'UAN', 'FZ'}
            assert(~(contains(headerText, 'polarization', 'IgnoreCase', true) && ~contains(headerText, 'theta_phi', 'IgnoreCase', true)), ...
                'APAT:UnsupportedUAN', 'Only "polarization theta_phi" UAN files are supported.');
            [theta, phi, rows] = io_fields(D, [1 2], "magphase", "grouped", "linear");
            names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}; M.Format = ['XGTD ' ext]; M.Unit = "dBi"; M.UnitLabel = "dBi";
        case 'OUT'
            [theta, phi, rows] = io_fields(D, [1 2], "reim", "grouped", "rcp");
            names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; M.Format = 'TICRA/GRASP OUT'; M.Unit = "dBi"; M.UnitLabel = "dBi";
        case 'FFS'
            [theta, phi, rows] = io_fields(D, [2 1], "reim", "grouped", "linear");
            names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; M.Format = 'CST FFS';
        case 'FFE'
            [theta, phi, rows] = io_fields(D, [1 2], "reim", "grouped", "linear");
            names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; M.Format = 'FEKO FFE';
            L = readlines(path); fl = strtrim(L(startsWith(strtrim(L), "#Frequency")));
            if ~isempty(fl), freqs = str2double(extractAfter(fl, ":")).'; end
            n = size(rows, 1) / max(1, numel(freqs));
    end
    if ext ~= "FFE", n = size(rows, 1); end
end
assert(abs(n - round(n)) < 1e-9 && mod(size(rows, 1), n) == 0, 'APAT:BlockMismatch', 'Row count does not match the declared grid / frequency blocks.');
nb = size(rows, 1) / n; freqs(end + 1:nb) = NaN; freqs = freqs(1:nb); blocks = cell(1, nb);
for b = 1:nb
    r = (b - 1)*n + (1:n); blocks{b} = struct('Theta', theta(r), 'Phi', phi(r), 'Data', rows(r, :));
end
if nb > 1, M.Notes(end + 1) = sprintf('%d frequency blocks found; select one with the frequency dropdown.', nb); end
S = io_source(array2table([blocks{1}.Theta, blocks{1}.Phi, rows(1:n, :)], 'VariableNames', names), blocks, freqs, M);
if ext == "FFS", S.Raw = S.Raw(:, [2 1 3:6]); end
end

function [nHdr, ffd, text] = io_header(path)
%IO_HEADER Count header lines; parse the HFSS FFD header (two numeric triples + optional "Frequencies ...").
fid = fopen(path, 'r'); assert(fid > 0, 'APAT:Open', 'Cannot open file: %s', path); cleaner = onCleanup(@() fclose(fid));
ffd = struct('isFFD', false, 'theta', [], 'phi', [], 'freq', []); triples = zeros(0, 3); nHdr = 0; text = "";
while size(triples, 1) < 2
    l = fgetl(fid); if ~ischar(l), break; end
    nHdr = nHdr + 1; t = strtrim(l); if isempty(t), continue; end
    v = sscanf(t, '%f').';
    if numel(v) == 3, triples(end + 1, :) = v; elseif isempty(triples), break; end %#ok<AGROW>
end
if size(triples, 1) == 2
    l3 = fgetl(fid); while ischar(l3) && isempty(strtrim(l3)), nHdr = nHdr + 1; l3 = fgetl(fid); end
    if ischar(l3)
        nHdr = nHdr + 1; tok = regexp(strtrim(l3), '^frequencies?\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if isempty(tok), nHdr = nHdr - 1; else, f = sscanf(tok{1}, '%f'); if ~isscalar(f), ffd.freq = f(:); end, end
    end
    ffd.theta = triples(1, :); ffd.phi = triples(2, :); ffd.isFFD = all(isfinite(triples(:))) && all(triples(:, 3) >= 1);
end
if ~ffd.isFFD                                      % generic: first line with at least four numeric fields starts the data
    frewind(fid); nHdr = 0; number = "[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?";
    dataLine = "^\s*" + number + "(?:[\s,;]+" + number + "){3,}\s*$";
    while true
        l = fgetl(fid);
        if ~ischar(l) || ~isempty(regexp(l, dataLine, 'once')), break; end
        nHdr = nHdr + 1; text = text + newline + string(l);
    end
end
end

function S = io_text(path, fmt, M)
%IO_TEXT Generic CSV/TXT/DAT: coverage results, gain-only pattern, or a six-column E-field layout.
opts = detectImportOptions(path, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
T = readtable(path, opts); names = string(T.Properties.VariableNames); low = lower(names); n = width(T);
hasHeaders = ~all(startsWith(names, "Var")); M.IsGeneric = true;
assert(n >= 2 && height(T) > 0, 'APAT:TextColumns', 'File needs at least two numeric columns.');
c2 = T{:, 2}; keyword = contains(low(1), "threshold") || any(contains(low(2:end), "coverage"));
strict = ~hasHeaders && n < 6 && fmt == "gain" && all(isfinite(c2)) && all(c2 >= 0 & c2 <= 100) && issorted(T{:, 1}, 'strictmonotonic');
if keyword || (strict && ~any(contains(low, ["theta", "phi"])))
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:n - 1))]; end
    M.IsCoverage = true; M.Format = 'Coverage results'; S = io_source(T, {}, NaN, M); return
end
if fmt == "gain"
    T = T(all(isfinite(T{:, :}), 2), :);
    it = find(contains(low, "theta"), 1); ip = find(contains(low, "phi"), 1);
    if isempty(it) || isempty(ip)
        span = max(T{:, 1:2}) - min(T{:, 1:2}); [it, ip] = deal(1, 2); if span(1) > span(2), [it, ip] = deal(2, 1); end
        M.Notes(end + 1) = sprintf('Axis order inferred from angular span: column %d = θ, column %d = φ.', it, ip);
    end
    cols = setdiff(1:n, [it ip], 'stable'); colNames = names(cols);
    if ~hasHeaders, colNames = "Gain" + string(1:numel(cols)) + "_dB"; if isscalar(cols), colNames = "Gain_dB"; end; M.Notes(end + 1) = "Headerless gain file: value column(s) named Gain_dB."; end
    M.ColNames = string(matlab.lang.makeValidName(cellstr(colNames))); M.IsGainOnly = true; M.Format = 'Generic text (gain)';
    if any(contains(low(cols), "dbi")), M.Unit = "dBi"; M.UnitLabel = "dBi"; else, M.UnitLabel = "dB"; end
    S = io_source(T, {struct('Theta', T{:, it}, 'Phi', T{:, ip}, 'Data', T{:, cols})}, NaN, M); return
end
assert(n >= 6, 'APAT:TextColumns', 'The selected generic E-field format requires six numeric columns.');
T = T(all(isfinite(T{:, 1:6}), 2), :); D = T{:, 1:6};
magphase = endsWith(fmt, "magphase"); layout = "grouped";
if magphase
    isPhase = contains(low(3:6), ["deg", "phase"]);
    if hasHeaders && isequal(isPhase, [false true false true]), layout = "interleaved";
    elseif ~(hasHeaders && isequal(isPhase, [false false true true]))
        big = max(abs(D(:, 3:6)), [], 1, 'omitnan') > 100; if big(2) && ~big(3), layout = "interleaved"; end
        M.Notes(end + 1) = "Magnitude/phase column layout (" + layout + ") inferred from value ranges (|phase| > 100).";
    end
end
basis = "linear"; comps = ["E_TH", "E_PH"];
if startsWith(fmt, "rcp"), basis = "rcp"; comps = ["POL1", "POL2"]; elseif startsWith(fmt, "lcp"), basis = "lcp"; comps = ["POL1", "POL2"]; end
domain = "reim"; if magphase, domain = "magphase"; end
[theta, phi, F] = io_fields(D, [1 2], domain, layout, basis);
if ~hasHeaders
    if magphase, gen = [comps + "_dB", comps + "_deg"]; if layout == "interleaved", gen = gen([1 3 2 4]); end
    else, gen = [comps(1) + ["_real", "_imag"], comps(2) + ["_real", "_imag"]]; end
    T.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", gen]);
end
M.Format = sprintf('Generic text (%s, %s)', fmt, layout);
S = io_source(T, {struct('Theta', theta, 'Phi', phi, 'Data', F)}, NaN, M);
end

function S = io_cut(path, M)
%IO_CUT TICRA/GRASP .cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks.
L = readlines(path); L(strlength(strtrim(L)) == 0) = []; [th, ph, dat] = deal({}); i = 1; icomp = 1; icut = 1;
while i < numel(L)
    p = sscanf(L(i + 1), '%f'); assert(numel(p) >= 7, 'APAT:CutHeader', 'Could not parse the cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6);
    B = reshape(sscanf(strjoin(L(i + 2:i + 1 + n), ' '), '%f'), 2*p(7), []).';
    th{end + 1} = p(1) + (0:n - 1).'*p(2); ph{end + 1} = repmat(p(4), n, 1); dat{end + 1} = B(:, 1:4); i = i + 2 + n; %#ok<AGROW>
end
theta = vertcat(th{:}); phi = vertcat(ph{:}); D = vertcat(dat{:});
assert(ismember(icomp, [1 2]), 'APAT:UnsupportedICOMP', 'GRASP cut ICOMP = %d is not supported (1 = linear θ/φ, 2 = RHCP/LHCP).', icomp);
if icut == 2, [theta, phi] = deal(phi, theta); M.Notes(end + 1) = "ICUT = 2: φ swept at constant θ."; end
neg = theta < 0; phi(neg) = phi(neg) + 180; theta(neg) = -theta(neg);        % GRASP polar convention: negative θ is the opposite φ
if isscalar(unique(phi))
    copies = (0:10:350).'; n = numel(theta); theta = repmat(theta, 36, 1); phi = repelem(copies, n); D = repmat(D, 36, 1);
    M.Notes(end + 1) = "Single cut: body of revolution synthesised at 10° φ steps.";
end
c1 = complex(D(:, 1), D(:, 2)); c2 = complex(D(:, 3), D(:, 4)); names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'};
if icomp == 2, [Eth, Eph] = pol_fromCircular(c1, c2); names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; else, [Eth, Eph] = deal(c1, c2); end
M.Format = 'TICRA/GRASP CUT';
S = io_source(array2table([theta, phi, D], 'VariableNames', [{'Theta', 'Phi'}, names]), ...
    {struct('Theta', theta, 'Phi', phi, 'Data', [real(Eth), imag(Eth), real(Eph), imag(Eph)])}, NaN, M);
end

function S = io_excel(path, M)
%IO_EXCEL Matrix-template workbooks: fixed component sheets (C3-origin matrices), summary sheet first.
sheets = string(sheetnames(path));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"];
lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'APAT:ExcelFormat', 'Unsupported workbook: expected the fixed Etheta/Ephi and/or RHCP/LHCP component sheets after the summary sheet.');
req = [lin(1:4*hasL), circ(1:4*hasC)]; kind = ["Format 1 (Eth/Eph)", "Format 2 (RHCP/LHCP)", "Format 3 (Eth/Eph + RHCP/LHCP)"]; kind = kind(hasL + 2*hasC);
mats = struct();
for k = 1:numel(req)
    [th, ph, X] = io_excelSheet(path, sheets(find(strcmpi(sheets, req(k)), 1)));
    if k == 1, [thRef, phRef] = deal(th, ph); end
    assert(isequal(size(th), size(thRef)) && isequal(size(ph), size(phRef)) && max(abs(th - thRef)) < 1e-9 && max(abs(ph - phRef)) < 1e-9, ...
        'APAT:ExcelGrid', 'All component sheets must use the same theta/phi grid.');
    mats.(req(k)) = X;
end
if hasL
    Eth = 10.^(mats.Etheta_Gain_dBi/20) .* exp(1i*deg2rad(mats.Etheta_Phase_degrees)); Eph = 10.^(mats.Ephi_Gain_dBi/20) .* exp(1i*deg2rad(mats.Ephi_Phase_degrees));
else
    [Eth, Eph] = pol_fromCircular(10.^(mats.RHCP_Gain_dBi/20) .* exp(1i*deg2rad(mats.RHCP_Phase_degrees)), 10.^(mats.LHCP_Gain_dBi/20) .* exp(1i*deg2rad(mats.LHCP_Phase_degrees)));
end
[phG, thG] = meshgrid(phRef, thRef); Raw = table(thG(:), phG(:), 'VariableNames', {'Theta', 'Phi'});
for k = 1:numel(req), Raw.(req(k)) = reshape(mats.(req(k)), [], 1); end
freqMHz = xl_lookup(path, sheets(1), 'Pattern Simulation Freq (MHz):');
M.Format = char("Excel Matrix " + kind); M.Unit = "dBi"; M.UnitLabel = "dBi";
S = io_source(Raw, {struct('Theta', thG(:), 'Phi', phG(:), 'Data', [real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:))])}, freqMHz*1e6, M);
end

function [theta, phi, X] = io_excelSheet(path, sheet)
% readcell keeps worksheet coordinates (readmatrix would trim the C3-origin template area).
C = readcell(path, 'Sheet', char(sheet));
assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'APAT:ExcelSheet', 'Sheet "%s" does not contain a C3-origin matrix.', sheet);
isNum = @(c) cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), c);
pm = isNum(C(2, 3:end)); tm = isNum(C(3:end, 2));
assert(any(pm) && any(tm) && ~any(pm(find(~pm, 1):end)) && ~any(tm(find(~tm, 1):end)), 'APAT:ExcelAxis', 'Sheet "%s" has a missing or non-contiguous theta/phi axis.', sheet);
phi = cell2mat(C(2, 2 + (1:nnz(pm)))); theta = cell2mat(C(2 + (1:nnz(tm)), 2));
block = C(2 + (1:numel(theta)), 2 + (1:numel(phi)));
assert(all(isNum(block), 'all'), 'APAT:ExcelSheet', 'Sheet "%s" contains non-numeric or missing matrix samples.', sheet);
X = cell2mat(block);
assert(all(diff(theta) > 0) && all(diff(phi) > 0) && theta(1) >= -1e-9 && theta(end) <= 180 + 1e-9 && phi(1) >= -1e-9 && phi(end) < 360, ...
    'APAT:ExcelAxis', 'Sheet "%s" axes must be increasing with θ in [0,180] and φ in [0,360).', sheet);
end

function v = xl_lookup(path, sheet, label)
%XL_LOOKUP First numeric value to the right of a label cell (whitespace/case/punctuation tolerant).
v = NaN; key = regexprep(lower(label), '[^a-z0-9]', '');
try, C = readcell(path, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
for r = 1:size(C, 1)
    for c = 1:size(C, 2)
        x = C{r, c};
        if ~(ischar(x) || isstring(x)) || ~strcmp(regexprep(lower(char(x)), '[^a-z0-9]', ''), key), continue; end
        for cc = c + 1:size(C, 2)
            y = C{r, cc}; if isnumeric(y) && isscalar(y) && isfinite(y), v = double(y); return; end
            if (ischar(y) || isstring(y)) && isfinite(str2double(y)), v = str2double(y); return; end
        end
    end
end
end

%% ====================================================================== file-scope: constants and factories

function K = apat_const()
%APAT_CONST Every convention in one place (persistent; built once).
persistent C
if isempty(C)
    C.ReleaseName = 'Antenna Pattern Analyzer Tool — APAT v3 M8'; C.ReleaseVersion = '3.0-M8';
    C.PeakExcessDB = 6;                 % isolated-spike threshold above every grid neighbour (I5)
    C.ARLimits = [-30 30];              % signed axial-ratio colour scale
    C.Hard = [-250 100];                % hard limits of every level range control
    C.DistanceFloorM = 1e-12; C.ConeHalfAngle = 45;
    C.PrincipalAxes = struct('labels', {{'+Z', '-Z', '+X', '-X', '+Y', '-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270]);
    cols = {'E_Total_dB' 'Total Gain' 'gain' false; 'E_TH_dB' 'Etheta Gain' 'gain' true; 'E_PH_dB' 'Ephi Gain' 'gain' true
        'E_RCP_dB' 'RHCP Gain' 'gain' false; 'E_LCP_dB' 'LHCP Gain' 'gain' false; 'AR_dB' 'Axial Ratio' 'ar' false
        'Gain_PolCorrected_dB' 'Polarized Gain' 'gain' false; 'PLF_dB' 'PLF' 'plf' false
        'E_TH_Phase' 'Etheta Phase' 'phase' true; 'E_PH_Phase' 'Ephi Phase' 'phase' true; 'E_RCP_Phase' 'RHCP Phase' 'phase' true; 'E_LCP_Phase' 'LHCP Phase' 'phase' true
        'EIRP_dBW' 'EIRP' 'link' true; 'PFD_Wm2' 'PFD' 'link' true; 'E_RMS_Vm' 'E_RMS' 'link' true};
    C.Cols = struct('name', string(cols(:, 1)).', 'label', string(cols(:, 2)).', 'kind', string(cols(:, 3)).', 'hidden', [cols{:, 4}]);
    C.Views = struct('kind', ["pcolor", "fisheye", "sphere", "polar", "rect"], 'face', ["interp", "interp", "flat", "flat", "flat"]);
    C.RangeGroups = struct( ...
        'full', struct('sliders', ["Range_Ctr", "Range_Cir", "Range_3dSph", "Range_3dPol", "Range_3dRect"], 'mins', ["Range_Ctr_Min", "Range_Cir_Min", "Range_3dSph_Min", "Range_3dPol_Min", "Range_3dRect_Min", "Single_Plot_Cmin"], ...
            'maxs', ["Range_Ctr_Max", "Range_Cir_Max", "Range_3dSph_Max", "Range_3dPol_Max", "Range_3dRect_Max", "Single_Plot_Cmax"], 'gap', 1), ...
        'cut', struct('sliders', "Range_Cut", 'mins', "Range_Cut_Min", 'maxs', "Range_Cut_Max", 'gap', 1), ...
        'cov', struct('sliders', strings(1, 0), 'mins', "Cov_Spinner_ThreshMin", 'maxs', "Cov_Spinner_ThreshMax", 'gap', 0.1), ...
        'covX', struct('sliders', "Cov_Spinner_XRange", 'mins', "Cov_Spinner_XMin", 'maxs', "Cov_Spinner_XMax", 'gap', 0.1));
    C.GainMap = jet(256); C.ARMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256));
end
K = C;
end

function E = apat_entry(path, src)
[folder, name, ext] = fileparts(path);
E = struct('Name', name, 'File', [name ext], 'Path', path, 'Folder', folder, 'Source', src, 'Native', [], 'Pattern', [], 'Geometry', [], 'Derived', [], 'Params', []);
end

%% ====================================================================== file-scope: pattern, geometry, display map, cuts

function P = pat_build(S, f)
%PAT_BUILD Canonical grid-native pattern: polar θ ascending in [0,180], φ ascending in [0,360), uniform steps asserted once.
B = S.Blocks{min(f, numel(S.Blocks))}; M = S.Meta;
theta = double(B.Theta(:)); phi = double(B.Phi(:)); X = double(B.Data);
ok = isfinite(theta) & isfinite(phi) & ~(abs(phi - 360) <= 1e-9 & any(abs(phi) <= 1e-9));   % drop the closing φ = 360 copies
theta = theta(ok); phi = phi(ok); X = X(ok, :);
if any(theta < 0)
    if min(theta) >= -90 && max(theta) <= 90
        theta = 90 - theta; M.Notes(end + 1) = "Source θ ∈ [−90°, 90°] read as elevation (θ_polar = 90° − θ).";
    else
        neg = theta < 0; theta(neg) = -theta(neg); phi(neg) = phi(neg) + 180; M.Notes(end + 1) = "Negative θ folded onto φ + 180°.";
    end
end
theta = mod(theta, 360); over = theta > 180; theta(over) = 360 - theta(over); phi(over) = phi(over) + 180;
theta = round(theta, 5); phi = mod(round(phi, 5), 360);                     % angles snapped; field values never rounded (I1)
[thA, ~, it] = unique(theta); [phA, ~, ip] = unique(phi);
util_assertUniform(thA, "θ"); util_assertUniform(phA, "φ");
n = numel(thA); m = numel(phA); idx = sub2ind([n m], it, ip); [cells, first] = unique(idx, 'first');
assert(numel(cells) == n*m, 'APAT:IncompleteGrid', 'The θ×φ grid is incomplete: %d of %d cells have no sample (APAT requires a complete regular grid).', n*m - numel(cells), n*m);
if numel(first) < numel(idx), M.Notes(end + 1) = sprintf('%d duplicate direction(s) resolved by first occurrence.', numel(idx) - numel(first)); end
grid = @(v) reshape(accumarray(cells, v(first), [n*m 1]), n, m);
P = struct('Theta', thA(:), 'Phi', phA(:).', 'dTheta', util_step(thA), 'dPhi', util_step(phA), 'Eth', [], 'Eph', [], 'G', struct(), ...
    'IsGainOnly', M.IsGainOnly, 'Freq', S.Freqs(min(f, numel(S.Freqs))), 'Revision', 1, 'Meta', M);
if M.IsGainOnly
    for c = 1:numel(M.ColNames), P.G.(M.ColNames(c)) = grid(X(:, c)); end
else
    P.Eth = complex(grid(X(:, 1)), grid(X(:, 2))); P.Eph = complex(grid(X(:, 3)), grid(X(:, 4)));
end
P.IsOneDegree = abs(P.dTheta - 1) < 1e-9 && abs(P.dPhi - 1) < 1e-9;
end

function util_assertUniform(axis, name)
d = diff(axis);
if numel(d) > 1 && max(abs(d - median(d))) > 1e-6
    error('APAT:NonUniformGrid', '%s axis is not uniform: steps range %.6g°..%.6g° (APAT requires uniform grids).', name, min(d), max(d));
end
end

function Q = pat_resample(P, step)
%PAT_RESAMPLE Exact decimation when step/native ∈ ℕ; otherwise bilinear interpolation of power + unit phasor (fields)
% or linear power (gain-kind columns), never of dB/AR/PLF (I6).  Target axes never leave the source domain.
Q = P; Q.Revision = P.Revision + 1; kt = step/P.dTheta; kp = step/P.dPhi;
isInt = @(k) isnan(k) || abs(k - round(k)) < 1e-9;
if isInt(kt) && isInt(kp)
    it = 1:max(1, round(kt)):numel(P.Theta); ip = 1:max(1, round(kp)):numel(P.Phi); f = @(X, ~) X(it, ip);
    Q.Theta = P.Theta(it); Q.Phi = P.Phi(ip);
    Q.Meta.Notes(end + 1) = sprintf('Decimated to %g° (every %d-th θ and %d-th φ sample; exact).', step, max(1, round(kt)), max(1, round(kp)));
else
    periodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6; phS = P.Phi; if periodic, phS(end + 1) = phS(1) + 360; end
    Q.Theta = (P.Theta(1):step:P.Theta(end) + 1e-9).';
    if periodic, Q.Phi = P.Phi(1) + (0:floor(360/step + 1e-9) - 1)*step; else, Q.Phi = P.Phi(1):step:P.Phi(end) + 1e-9; end
    f = @(X, kind) pat_interp(X, P.Theta, phS, Q.Theta, Q.Phi, kind, periodic);
    Q.Meta.Notes(end + 1) = sprintf('Resampled to %g° by bilinear interpolation (power + unit phasor for fields, linear power for gain).', step);
end
if P.IsGainOnly
    for c = string(fieldnames(P.G)).', kind = "linear"; if util_colKind(c) == "gain", kind = "power"; end, Q.G.(c) = f(P.G.(c), kind); end
else
    Q.Eth = f(P.Eth, "field"); Q.Eph = f(P.Eph, "field");
end
Q.dTheta = util_step(Q.Theta); Q.dPhi = util_step(Q.Phi); Q.IsOneDegree = abs(Q.dTheta - 1) < 1e-9 && abs(Q.dPhi - 1) < 1e-9;
end

function Y = pat_interp(X, th, ph, th2, ph2, kind, periodic)
if periodic, X(:, end + 1) = X(:, 1); end                                   % φ-closed grid
[PH, TH] = meshgrid(ph, th); [PH2, TH2] = meshgrid(ph2, th2);
lin = @(V) interp2(PH, TH, V, PH2, TH2, 'linear');
switch kind
    case "power", Y = 10*log10(max(lin(10.^(X/10)), realmin));
    case "field"                                                            % B.5: |E|² linear, direction as unit phasor
        U = X ./ max(abs(X), realmin); u = complex(lin(real(U)), lin(imag(U)));
        Y = sqrt(max(lin(abs(X).^2), 0)) .* u ./ max(abs(u), realmin);
    otherwise,    Y = lin(X);
end
end

function G = geo_build(P)
%GEO_BUILD Separable geometry: ΔΩ(i,j) = wθ(i)·Δφ with wθ = cos(lo) − cos(hi); Σ ΔΩ = 4π exactly on a full sphere (B.1).
th = P.Theta(:); dT = P.dTheta; if isnan(dT), dT = 180; end; dP = P.dPhi; if isnan(dP), dP = 360; end
G.wTheta = cosd(max(th - dT/2, 0)) - cosd(min(th + dT/2, 180)); G.dPhi = deg2rad(dP);
G.dOmega = G.wTheta * G.dPhi * ones(1, numel(P.Phi)); G.Omega = sum(G.dOmega, 'all');
G.PhiPeriodic = abs(numel(P.Phi)*dP - 360) < 1e-6;
G.IsFullSphere = G.PhiPeriodic && th(1) <= 1e-9 && abs(th(end) - 180) <= 1e-9;
end

function M = geo_displayMap(P, G, V)
%GEO_DISPLAYMAP Display convention as a column permutation + relabelled axes; no data copy, no numbers change (I8).
n = numel(P.Phi); j0 = find(P.Phi >= 180, 1); perm = 1:n;
if V.SignedPhi && ~isempty(j0), perm = [j0:n, 1:j0 - 1]; end
M.ColIdx = perm; M.PhiAxis = P.Phi(perm);
if V.SignedPhi, M.PhiAxis(M.PhiAxis >= 180) = M.PhiAxis(M.PhiAxis >= 180) - 360; M.PhiLim = [-180 180]; else, M.PhiLim = [0 360]; end
if G.PhiPeriodic, M.ColIdx(end + 1) = perm(1); M.PhiAxis(end + 1) = M.PhiAxis(1) + 360; end   % closing column for display only
if V.Elevation, M.ThetaAxis = 90 - P.Theta(:); M.ThetaDir = 'normal'; M.ThetaLabel = "Elevation"; M.ThetaLim = [-90 90];
else, M.ThetaAxis = P.Theta(:); M.ThetaDir = 'reverse'; M.ThetaLabel = "Theta"; M.ThetaLim = [0 180]; end
M.RTicks = 0:30:180; if V.Elevation, M.RTicks = 90 - M.RTicks; end
M.PhiTicks = 0:30:330; if V.SignedPhi, M.PhiTicks(M.PhiTicks > 180) = M.PhiTicks(M.PhiTicks > 180) - 360; end
M.SpanText = sprintf('θ: %d° to %d°  |  φ: %d° to %d°', M.ThetaLim, M.PhiLim);
end

function S = geo_cut(P, G, C, type, value)
%GEO_CUT Full-circle cut (angle 0..360) of nθ×nφ×nc stack C: "Phi" = fixed θ (sweep φ), "Theta" = fixed φ through the pole (φ, then φ+180).
th = P.Theta(:); ph = P.Phi(:); nc = size(C, 3);
if type == "Phi"
    [d, i] = min(abs(th - value)); fixed = th(i); symbol = 'θ';
    a = ph; y = reshape(C(i, :, :), [], nc); t = repmat(th(i), numel(ph), 1); p = ph;
    if G.PhiPeriodic, a(end + 1) = ph(1) + 360; y(end + 1, :) = y(1, :); t(end + 1) = t(1); p(end + 1) = ph(1); end
else
    [d, j1] = min(abs(mod(ph - mod(value, 360) + 180, 360) - 180)); fixed = ph(j1); symbol = 'φ';
    [dOpp, j2] = min(abs(mod(ph - ph(j1), 360) - 180)); ii = flipud(find(abs(th - 180) > 1e-9));
    a = th; y = reshape(C(:, j1, :), [], nc); t = th; p = repmat(ph(j1), numel(th), 1);
    if j2 ~= j1 && dOpp <= max(P.dPhi/2, 1e-6)                             % opposite half-plane exists
        a = [a; 360 - th(ii)]; y = [y; reshape(C(ii, j2, :), [], nc)]; t = [t; th(ii)]; p = [p; repmat(ph(j2), numel(ii), 1)];
    end
end
S = struct('angle', a, 'y', y, 'theta', t, 'phi', p, 'type', type, 'fixed', fixed, 'symbol', symbol, 'snapped', d > 1e-9, 'names', strings(1, 0));
end

function S = util_signedWrap(S)
% 0..360 cut -> −180..180 (rotation of the sample order + closing point at +180).
idx = S.angle >= 180; if ~any(idx), return; end
o = [find(idx); find(~idx)]; c = find(idx, 1);
S.angle = [S.angle(idx) - 360; S.angle(~idx); 180]; S.y = [S.y(o, :); S.y(c, :)];
S.theta = [S.theta(o); S.theta(c)]; S.phi = [S.phi(o); S.phi(c)];
end

%% ====================================================================== file-scope: derivation (columns, peak, polarisation, boresight, metrics)

function D = pat_derive(P, G, prm)
%PAT_DERIVE The only function that consumes parameters.  Pattern + Geometry + Params -> every column and every base fact.
K = apat_const(); s = 10^(prm.L/20); Cols = struct();
if P.IsGainOnly
    names = string(fieldnames(P.G)).'; kinds = arrayfun(@util_colKind, names); labels = names; hidden = false(size(names));
    if ~any(kinds == "gain"), kinds(1) = "gain"; end                        % a gain file has at least one gain column
    for i = 1:numel(names), Cols.(names(i)) = P.G.(names(i)) + prm.L*(kinds(i) == "gain"); end   % loss on gain kinds only
    pol = struct('Pairs', struct('Circular', ["E_RCP", "E_LCP"], 'Linear', ["E_TH", "E_PH"]), 'Label', "n/a", 'Basis', "Circular", 'Sense', 1);
else
    Eth = P.Eth*s; Eph = P.Eph*s; Er = pol_circular(Eth, Eph, 1); El = pol_circular(Eth, Eph, 2);
    lvl = @(E) 20*log10(max(abs(E), eps)); phs = @(E) rad2deg(angle(E));
    Cols.E_Total_dB = 10*log10(max(abs(Eth).^2 + abs(Eph).^2, eps));
    [Cols.AR_dB, isLinear] = pol_signedAR(Er, El);
    Cols.E_RCP_dB = lvl(Er); Cols.E_LCP_dB = lvl(El);
    % Polarisation from radiated-power shares  P_c = ∫|E_c|² dΩ  (Ω-weighted, so the main beam dominates; D13)
    share = @(E) sum(abs(E).^2 .* G.dOmega, 'all', 'omitnan'); pw = [share(Eth), share(Eph), share(Er), share(El)];
    pairs = struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]);
    if pw(2) > pw(1), pairs.Linear = fliplr(pairs.Linear); end
    if pw(4) > pw(3), pairs.Circular = fliplr(pairs.Circular); end
    if max(pw(3:4)) > max(pw(1:2)), basis = "Circular"; label = "Circular (" + replace(pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]) + ")";
    elseif pw(1) >= pw(2), basis = "Linear"; label = "Linear (Vertical)"; else, basis = "Linear"; label = "Linear (Horizontal)"; end
    sense = 2*(pairs.Circular(1) == "E_RCP") - 1;
    if prm.RxMode == "RHCP", sense = 1; elseif prm.RxMode == "LHCP", sense = -1; end
    pol = struct('Pairs', pairs, 'Label', label, 'Basis', basis, 'Sense', sense);
    Cols.PLF_dB = pol_plf(Er, El, isLinear, sense, prm.RxAR_dB);
    Cols.Gain_PolCorrected_dB = Cols.E_Total_dB + Cols.PLF_dB;
    Cols.E_TH_dB = lvl(Eth); Cols.E_PH_dB = lvl(Eph);
    Cols.E_TH_Phase = phs(Eth); Cols.E_PH_Phase = phs(Eph); Cols.E_RCP_Phase = phs(Er); Cols.E_LCP_Phase = phs(El);
    if P.Meta.Unit == "dBi"                                                 % link quantities exist only for absolute gain (I9)
        Cols.EIRP_dBW = prm.Pt_dBW + Cols.E_Total_dB; W = 10.^(Cols.EIRP_dBW/10);
        Cols.PFD_Wm2 = W ./ (4*pi*prm.R_m^2); Cols.E_RMS_Vm = sqrt(30*W) ./ prm.R_m;
    end
    names = string(fieldnames(Cols)).'; [~, loc] = ismember(names, K.Cols.name);
    kinds = K.Cols.kind(loc); labels = K.Cols.label(loc); hidden = K.Cols.hidden(loc);
end
D = struct('Cols', Cols, 'Names', names, 'Kinds', kinds, 'Labels', labels, 'Hidden', hidden, 'Pol', pol);
D.PeakCol = names(find(kinds == "gain", 1)); C0 = Cols.(D.PeakCol);
D.Peak = met_peak(C0, P, G.PhiPeriodic, K.PeakExcessDB);
D.Boresight = met_orientation(C0, P, G, D.Peak, K);
D.Planes = met_planes(D.Boresight, K.PrincipalAxes);
D.Metrics = met_metrics(P, G, D, C0);
end

function pk = met_peak(C, P, periodic, excessDB)
%MET_PEAK Effective peak = highest sample that is not an isolated spike; spike ⇔ C exceeds every 4-neighbour by > excessDB (I5).
[n, m] = size(C); nb = -inf(n, m);
nb(2:n, :) = max(nb(2:n, :), C(1:n - 1, :)); nb(1:n - 1, :) = max(nb(1:n - 1, :), C(2:n, :));            % θ neighbours
if periodic, L = circshift(C, 1, 2); R = circshift(C, -1, 2); else, L = [-inf(n, 1), C(:, 1:m - 1)]; R = [C(:, 2:m), -inf(n, 1)]; end
nb = max(nb, max(L, R));                                                                                  % φ neighbours
pk.spike = isfinite(C) & (C - nb > excessDB); pk.spikeCount = nnz(pk.spike);
[pk.rawValue, pk.rawIndex] = max(C(:), [], 'omitnan');
cand = C; cand(pk.spike) = -Inf; [pk.value, pk.index] = max(cand(:), [], 'omitnan');
pk.wasAdjusted = pk.index ~= pk.rawIndex;
[i, j] = ind2sub([n m], pk.index); pk.theta = P.Theta(i); pk.phi = P.Phi(j);
end

function idx = met_orientation(C, P, G, pk, K)
%MET_ORIENTATION Principal axis whose 45° cone holds the most radiated power 10^(G/10)·ΔΩ (spikes excluded).
w = 10.^((C - pk.value)/10) .* G.dOmega; w(~isfinite(w) | pk.spike) = 0; A = K.PrincipalAxes; e = zeros(1, numel(A.theta));
for a = 1:numel(e), e(a) = sum(w(cov_coneMask(P, A.theta(a), A.phi(a), K.ConeHalfAngle)), 'all'); end
[~, idx] = max(e);
end

function planes = met_planes(idx, A)
%MET_PLANES E-plane: θ-cut in the boresight meridian; H-plane: the φ-cut at θ = 90° for transverse axes, else the θ-cut at φ = 90°.
planes.E = struct('type', "Theta", 'value', A.phi(idx), 'symbol', 'φ');
if A.theta(idx) == 90, planes.H = struct('type', "Phi", 'value', 90, 'symbol', 'θ'); else, planes.H = struct('type', "Theta", 'value', 90, 'symbol', 'φ'); end
end

function m = met_metrics(P, G, D, C)
%MET_METRICS Directivity, efficiency, F/B, HPBW (E/H), AR at peak — all on the total-gain column (I4); honest gating (I9).
pk = D.Peak; keep = isfinite(C) & ~pk.spike; Prad = sum(10.^(C(keep)/10) .* G.dOmega(keep));
m.Directivity = 10*log10(max(4*pi*10^(pk.value/10) / max(Prad, realmin), realmin));
m.Efficiency = NaN; m.FrontBack = NaN; m.ARatPeak = NaN;
if G.IsFullSphere && P.Meta.Unit == "dBi", m.Efficiency = 100*Prad/(4*pi); end
if G.IsFullSphere
    sim = cosd(P.Theta(:))*cosd(pk.theta) + sind(P.Theta(:))*sind(pk.theta).*cosd(P.Phi(:).' - pk.phi);   % cos γ to the peak
    [~, back] = min(sim(:)); m.FrontBack = pk.value - C(back);
end
for plane = ["E", "H"]
    S = geo_cut(P, G, C, D.Planes.(plane).type, D.Planes.(plane).value); m.("HPBW_" + plane) = met_hpbw(S.angle, S.y);
end
if isfield(D.Cols, 'AR_dB'), m.ARatPeak = D.Cols.AR_dB(pk.index); end
end

function [bw, lo, hi] = met_hpbw(angleDeg, gainDB, peakGain, peakAngle)
%MET_HPBW Half-power beamwidth of a circular cut by linear interpolation of the −3 dB crossings about the peak.
[bw, lo, hi] = deal(NaN); v = isfinite(angleDeg) & isfinite(gainDB); angleDeg = angleDeg(v); gainDB = gainDB(v);
if numel(gainDB) < 3, return; end
if nargin < 3 || isempty(peakGain), [peakGain, i] = max(gainDB); peakAngle = angleDeg(i); end
half = peakGain - 3; [rel, o] = sort(mod(angleDeg - peakAngle + 180, 360) - 180); g = gainDB(o);
iL = find(rel < 0 & g <= half, 1, 'last'); iR = find(rel > 0 & g <= half, 1, 'first');
if isempty(iL) || isempty(iR) || iL + 1 > numel(g) || iR - 1 < 1, return; end
if g(iL + 1) == g(iL) || g(iR - 1) == g(iR), return; end
xL = rel(iL) + (rel(iL + 1) - rel(iL))*(half - g(iL))/(g(iL + 1) - g(iL));
xR = rel(iR) + (rel(iR - 1) - rel(iR))*(half - g(iR))/(g(iR - 1) - g(iR));
lo = peakAngle + xL; hi = peakAngle + xR; bw = xR - xL;
end

%% ====================================================================== file-scope: polarisation (one place for each convention)

function E = pol_circular(Eth, Eph, which)
%POL_CIRCULAR Under e^{+jωt} with (θ̂, φ̂, r̂) right-handed the IEEE RHCP unit vector is ê_R = (θ̂ − jφ̂)/√2, so the RHCP
% component of E = Eθ θ̂ + Eφ φ̂ is E·ê_R* = (Eθ + jEφ)/√2 and LHCP is (Eθ − jEφ)/√2  (check: E = ê_R ⇒ E_R = 1, E_L = 0).
if which == 1, E = (Eth + 1i*Eph)/sqrt(2); else, E = (Eth - 1i*Eph)/sqrt(2); end
end

function [Eth, Eph] = pol_fromCircular(Er, El)
Eth = (Er + El)/sqrt(2); Eph = (Er - El)/(1i*sqrt(2));
end

function [AR, isLinear] = pol_signedAR(Er, El)
%POL_SIGNEDAR Signed axial ratio in dB: AR = 20·log10((|E_R|+|E_L|)/||E_R|−|E_L||), + RHCP sense, − LHCP sense; −100 dB at linear samples.
r = abs(Er); l = abs(El); d = r - l;
isLinear = isfinite(d) & abs(d) <= eps*max(r + l, 1);
AR = min(20*log10((r + l) ./ max(abs(d), eps)), 250) .* sign(d); AR(isLinear) = -100; AR(~isfinite(d)) = NaN;
end

function PLF = pol_plf(Er, El, isLinear, sense, RxAR_dB)
%POL_PLF Polarisation loss factor between the antenna (signed voltage axial ratio ra) and the incident wave (rw),
% worst-case tilt:  PLF = 1/2 + (4·ra·rw − (ra²−1)(rw²−1)) / (2(ra²+1)(rw²+1)).  Linear samples take ra → ∞; NaN stays NaN (D08).
r = abs(Er); l = abs(El); d = r - l;
ra = (r + l) ./ max(abs(d), eps) .* sign(d); ra(isLinear) = 1e12; rw = sense*10^(RxAR_dB/20);
plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1)) ./ (2*(ra.^2 + 1)*(rw^2 + 1));
PLF = 10*log10(min(max(plf, eps), 1)); PLF(~isfinite(d)) = NaN;
end

%% ====================================================================== file-scope: coverage (the definition, verbatim)

function cov = cov_curve(C, dOmega, mask, T)
%COV_CURVE Coverage(T) = 100 · Ω_R(C > T) / Ω_R,  Ω_R(C > T) = Σ_{(i,j)∈R, C(i,j) > T} ΔΩ(i,j)   (strict ">", O(N) memory)
v = mask & isfinite(C); g = C(v); w = dOmega(v); Omega = sum(w); cov = zeros(size(T));
if Omega <= 0, return; end
cov = 100 * arrayfun(@(t) sum(w(g > t)), T) / Omega;
end

function m = cov_coneMask(P, thC, phC, alphaDeg)
%COV_CONEMASK (i,j) ∈ cone ⇔ cos γ ≥ cos α,  cos γ = cos θᵢ cos θc + sin θᵢ sin θc cos(φⱼ − φc)   (spherical law of cosines)
m = cosd(P.Theta(:))*cosd(thC) + sind(P.Theta(:))*sind(thC).*cosd(P.Phi(:).' - phC) >= cosd(alphaDeg) - 1e-12;
end

function T = cov_thresholds(tMin, tMax, step)
n = max(0, round((tMax - tMin)/step)); T = tMin + (0:n).'*step;            % by counting, not accumulation
end

function c = cov_at(job, T)
if numel(job.T) < 2, c = nan(size(T)); c(T == job.T) = job.cov; return; end
c = interp1(job.T, job.cov, T, 'linear', NaN);
end

function t = thr_at(job, c)
[cv, i] = unique(job.cov, 'last');                                          % upper end of every plateau -> strictly monotone
if numel(cv) < 2, t = nan(size(c)); t(c == cv) = job.T(i(1)); return; end
t = interp1(cv, job.T(i), c, 'linear', NaN);
end

%% ====================================================================== file-scope: utilities

function [X, Y, Z] = viewCoords(kind, theta, M, C, lim)
%VIEWCOORDS Surface coordinates of one full-pattern view (physical θ rows, display φ columns through the map).
[ph, th] = meshgrid(M.PhiAxis, theta);
switch kind
    case "pcolor",  [X, Y] = meshgrid(M.PhiAxis, M.ThetaAxis); Z = zeros(size(C));
    case "rect",    [X, Y] = meshgrid(M.PhiAxis, M.ThetaAxis); Z = C;
    case "fisheye", X = deg2rad(ph); Y = th; Z = zeros(size(C));
    otherwise
        r = 1; if kind == "polar", r = util_polarRadius(C, lim, C); end
        X = r.*sind(th).*cosd(ph); Y = r.*sind(th).*sind(ph); Z = r.*cosd(th);
end
end

function r = util_polarRadius(values, lim, ref)
% Radius in [0,1]: level above the colour floor, normalised so the reference grid's maximum touches 1 (surface and overlay agree).
span = max(diff(lim), eps); r = max(values - lim(1), 0)/span;
r = r / max(max(max(ref - lim(1), 0), [], 'all')/span, eps);
end

function [az, el, up] = util_camera(code, default)
up = [0 0 1];
switch code
    case "top",    az = 0; el = 90; up = [0 1 0];
    case "bottom", az = 0; el = -90; up = [0 1 0];
    case "right",  az = 90; el = 0;
    case "left",   az = -90; el = 0;
    case "front",  az = 0; el = 0;
    case "back",   az = 180; el = 0;
    otherwise,     az = default(1); el = default(2);
end
end

function ticks = util_ticks(lim, step)
ticks = [];
if numel(lim) ~= 2 || any(~isfinite(lim)) || ~isfinite(step) || step <= 0 || lim(1) >= lim(2), return; end
ticks = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)], 'stable');
if numel(ticks) > 60, ticks = []; end
end

function b = util_presetRange(peak)
% 50-dB window whose top is the peak rounded up to 5 dB (colour scale, cut range, coverage thresholds).
if ~isfinite(peak), b = [-50 0]; return; end
top = min(100, ceil(peak/5)*5); b = [max(-250, top - 50), top];
end

function s = util_fmtNumber(v, prec)
% Compact (≤ 2 decimals, no trailing zeros, never "-0") or fixed precision.
if ~(isscalar(v) && isnumeric(v) && isfinite(v)), s = 'n/a'; return; end
if nargin < 2, s = sprintf('%.2f', v); s = regexprep(regexprep(s, '(\.\d*?)0+$', '$1'), '\.$', ''); else, s = sprintf('%.*f', prec, v); end
if str2double(s) == 0, s = regexprep(s, '^-', ''); end
end

function step = util_step(values)
d = diff(unique(values(isfinite(values)))); d = d(d > 1e-9); step = NaN; if ~isempty(d), step = min(d); end
end

function kind = util_colKind(name)
key = regexprep(lower(char(name)), '[^a-z0-9]', '');
if startsWith(key, 'ar') || contains(key, 'axial'), kind = "ar";
elseif contains(key, 'plf'), kind = "plf";
elseif contains(key, 'phase') || endsWith(key, 'deg'), kind = "phase";
elseif contains(key, 'gain') || contains(key, 'directivity') || contains(key, 'eirp') || endsWith(key, 'db') || endsWith(key, 'dbi'), kind = "gain";
else, kind = "other"; end
end

function choice = util_pick(previous, options)
if any(options == previous), choice = previous; elseif any(options == "E_Total_dB"), choice = "E_Total_dB"; else, choice = options(1); end
end

function label = util_axisLabel(center)
% Principal-axis name when the cone centre is one, else the explicit coordinates.
K = apat_const(); A = K.PrincipalAxes; v = [sind(center(1))*cosd(center(2)), sind(center(1))*sind(center(2)), cosd(center(1))];
axes = [sind(A.theta(:)).*cosd(A.phi(:)), sind(A.theta(:)).*sind(A.phi(:)), cosd(A.theta(:))]; hit = find(axes*v(:) >= 1 - 1e-9, 1);
if isempty(hit), label = sprintf('θ=%s°, φ=%s°', util_fmtNumber(center(1)), util_fmtNumber(center(2))); else, label = A.labels{hit}; end
end