classdef APAT_v3_M8_4 < matlab.apps.AppBase %1931-lines %>> Error: "Unrecognized method, property, or field 'DataTipTemplate' for class 'matlab.graphics.primitive.Line'. (APAT_v3_M8_4.renderCut line 755)"
% APAT v3 M8 — Antenna Pattern Analyzer Tool (base MATLAB R2023b, no toolboxes).
%
% One grid-native pattern, one derivation function, one pattern registry shared by both tabs, one dispatcher,
% one retained-mode renderer per view, one declarative layout.  Same widgets, formats and features as M7.
%
% Dataflow — every arrow is one function; nothing below a line reads a widget, nothing above it writes one:
%
%   FILE ──io_read──► Source {Raw, Blocks{f}, Freqs, Meta}
%        ──pat_build──► Pattern {Theta, Phi, dTheta, dPhi, Eth, Eph | G.(col), Revision}   (uniform grid asserted once)
%        ──(pat_resample)──► ──geo_build──► Geometry {wTheta, dPhi, dOmega, Omega, PhiPeriodic, IsFullSphere}
%        Pattern + Geometry + Params ──pat_derive──► Derived {Cols, Peak, Pol, Boresight, Planes, Metrics}
%        app.Pats(k) = {Name, Path, Source, Pattern, Geometry, Derived, Params}     Main tab = Pats(app.Main); coverage nodes store k
%
%   widgets ──readConfig──► View ──geo_displayMap──► Map (column permutation + axis labels; no data copied)
%        ──► renderFull / renderCut / renderTables / renderMetadata / export / coverage
%
% Conventions live in apat_const() (file scope) and are shown in the Metadata tab.

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

    properties (GetAccess = public, SetAccess = private)
        isClosing logical = false      % lifecycle flag; set once by shutdown
        Perf struct = struct()         % last timed user action {AppVersion, Operation, Stages, TotalSeconds} (§7.5)
    end

    properties (Access = private)
        % ---- application state (no widget UserData anywhere)
        Pats = struct('Name', {}, 'Path', {}, 'Source', {}, 'Pattern', {}, 'Geometry', {}, 'Derived', {}, 'Params', {}, 'Native', {})  % pattern registry (I14)
        Main double = 0                % Pats index shown on the Main tab; 0 = nothing loaded
        View struct = struct()         % last readConfig() result
        Map struct = struct()          % geo_displayMap() result for View
        Range struct = struct('full', [-40 10], 'cut', [-40 10], 'cov', [-40 10], 'covX', [-40 10], ...
                              'Auto', struct('full', true, 'cut', true, 'cov', true, 'covX', true))
        Gfx struct = struct()          % retained graphics handles: Menu, Maps, Full(5), Cut, InKey, OutKey
        Status struct = struct('Main', '', 'Cov', '')   % persistent status text per bar (transient text restored from here)
        StatusTimer = []               % the one transient-status timer
        Dialog = []                    % cancellable progress dialog during long stages
        Busy logical = false           % re-entrancy guard for on()
        PerfRun = []                   % running perf record
        OutMask logical = logical([])  % Results-table column filter (true = shown)
        BasisAuto logical = true       % cut basis follows the detected polarisation until the user picks one
        CovRunID double = 0            % coverage job counter
        CovPresetKey string = ""       % pattern|component whose threshold window was last preset
        Defaults struct = struct()     % parameter widget defaults captured at startup (Reset Params)
        Single_paxCut matlab.graphics.axis.PolarAxes       % polar cut axes
        Single_paxPattern matlab.graphics.axis.PolarAxes   % circular-contour axes
    end

    methods (Access = private)   % ================= C. ORCHESTRATION =================

        function [V, prm] = readConfig(app)
            %READCONFIG The only place Main-tab widget values are read (§3.1).
            V.Component = string(app.Single_DropDown_Component.Value);
            V.Cut = struct('type', string(app.Single_DropDown_cutType.Value), 'value', app.Single_DropDown_cutValue.Value);
            V.SignedPhi = strcmp(app.Single_Switch_AngularSpan.Value, '-180° to 180°');
            V.Elevation = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°');
            V.Basis = string(app.CutFieldBasisDropDown.Value);
            V.Traces = logical([app.CheckBox_Et.Value, app.CheckBox_Er.Value, app.CheckBox_El.Value]);
            V.HPBW = app.Button_HPBW.Value; V.HPBWTips = app.Single_CheckBox_HPBWBounds.Value;
            V.POB = app.Single_CheckBox_POB.Value; V.Overlay = app.Singel_CheckBox_overlayCut.Value;
            V.Step1 = strcmp(app.Single_DropDown_step.Value, '1');
            V.FreqIndex = 1; if isnumeric(app.Single_DropDown_FFD.Value), V.FreqIndex = app.Single_DropDown_FFD.Value; end
            V.Camera = string(app.Single_DropDown_3DView.Value); V.CStep = app.Single_Plot_Cstep.Value;
            K = apat_const();
            prm = struct('L', app.Single_Spinner_Loss.Value, 'RxMode', string(app.Single_DropDown_RxPol.Value), 'RxAR_dB', app.Single_Spinner_Rw.Value);
            p = app.Single_Spinner_Pt.Value;
            switch app.Single_DropDown_Pt.Value, case 'dBm', prm.Pt_dBW = p - 30; case 'Watts', prm.Pt_dBW = 10*log10(max(p, eps)); otherwise, prm.Pt_dBW = p; end
            prm.R_m = max(app.Single_Spinner_R.Value, K.DistanceFloorM); if strcmp(app.Single_DropDown_R.Value, 'km'), prm.R_m = 1000*prm.R_m; end
        end

        function c = readCoverageConfig(app)
            %READCOVERAGECONFIG The only place Coverage-tab widget values are read; writes nothing (D48).
            c.Component = string(app.Cov_DropDown_Component.Value);
            c.T = cov_thresholds(app.Cov_Spinner_ThreshMin.Value, app.Cov_Spinner_ThreshMax.Value, max(app.Cov_Spinner_Step.Value, 0.1));
            c.Conical = logical(app.Cov_ButtonGroup_Btn_Conical.Value);
            c.Cone = [app.Cov_Spinner_ConeTH.Value, mod(app.Cov_Spinner_ConePH.Value, 360), app.Cov_Spinner_ConeAng.Value];
            c.Orientation = app.Cov_DropDown_Orientation.Value;
            c.QueryT = app.Cov_Spinner_queryCov.Value; c.QueryC = app.Cov_Spinner_queryThresh.Value;
        end

        function on(app, scope, arg)
            %ON Guard for every user action: re-entrancy, try/catch, cancellation, timing (§7.3).
            if app.Busy || app.isClosing, return; end
            if nargin < 3, arg = []; end
            app.Busy = true; guard = onCleanup(@() app.clearBusy()); app.perf("begin " + scope);
            try
                switch scope
                    case "load",      app.loadMain(arg);
                    case "process",   app.process();
                    case "range",     app.applyRange(arg{:}); app.renderCut(); app.renderFull(app.visibleView()); app.applyAnnot();
                    case "filter",    app.toggleFilter(); app.renderTables();
                    case "plane",     app.applyPlane(); app.update("view");
                    case "camera",    app.applyCamera();
                    case "reset",     app.resetParams();
                    case "export",    app.exportResults();
                    case "exportCut", app.exportCut();
                    case "exportUAN", app.exportUAN();
                    case "toCov",     app.covAddPattern(app.Main);
                    case "covLoad",   app.covLoad(arg);
                    case "covFormat", app.covReformat();
                    case "covRun",    app.covCompute();
                    case "covSelect", app.covSelect();
                    case "covCheck",  app.covRefresh();
                    case "covView",   app.covOrientation(); app.applyVisibility();
                    case "covQuery",  app.covQuery(arg);
                    case "covClear",  app.covClear();
                    case "covReset",  app.covReset();
                    case "covExport", app.exportCoverage();
                    otherwise,        app.update(scope);
                end
                drawnow limitrate
            catch err
                if strcmp(err.identifier, 'APAT:Cancelled'), app.setStatus(app.Single_StatusBar, 'Operation cancelled by user.', true);
                else, app.showError(err, char(scope)); end
            end
            app.perf("end");
        end

        function clearBusy(app), if ~app.isClosing, app.Busy = false; end, end

        function update(app, scope)
            %UPDATE Ladder: freq ⊃ step ⊃ params ⊃ view.  Numeric stages commit Pats(Main) in one step (I13);
            % renderers are key-guarded, so a view change costs only what actually changed.
            if app.Main == 0, app.applyVisibility(); return; end
            if any(scope == ["source", "freq", "step"]), app.applyChoices(scope == "source"); end
            [app.View, prm] = app.readConfig(); e = app.Pats(app.Main);
            if any(scope == ["freq", "step"])
                e.Pattern = pat_build(e.Source, app.View.FreqIndex); e.Native = max(e.Pattern.dTheta, e.Pattern.dPhi);
                if app.View.Step1, e.Pattern = pat_resample(e.Pattern, 1); end
                e.Geometry = geo_build(e.Pattern); app.perf("Build pattern"); app.checkCancelled();
            end
            if any(scope == ["freq", "step", "params"]), e.Derived = pat_derive(e.Pattern, e.Geometry, prm); e.Params = prm; app.perf("Derive"); end
            app.Pats(app.Main) = e;                                                       % commit
            app.Map = geo_displayMap(e.Pattern, e.Geometry, app.View);
            app.applyCutDomain();
            if any(scope == ["source", "freq", "step"]) && app.Range.Auto.full
                app.applyRange("full", util_presetRange(e.Derived.Peak.value), "set"); app.applyRange("cut", app.Range.full, "set");
            end
            app.renderCut(); app.renderFull(app.visibleView()); app.applyTheme(app.visibleView()); app.perf("Render");
            app.renderTables(); app.renderMetadata(); app.perf("Tables");
            app.applyVisibility(); drawnow limitrate; app.applyAnnot();
            p = e.Derived.Peak; [i, j] = ind2sub(size(e.Geometry.dOmega), p.index);
            txt = sprintf('Pattern: <b>%s</b> | POB <b>%s %s</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)', e.Name, util_fmt(p.value, 2), ...
                e.Pattern.Meta.UnitLabel, util_fmt(e.Pattern.Theta(i)), util_fmt(e.Pattern.Phi(j)));
            if ~e.Pattern.IsGainOnly, txt = sprintf('%s | Polarization <b>%s</b>', txt, e.Derived.Pol.label); end
            app.setStatus(app.Single_StatusBar, txt, false);
        end

        function e = buildEntry(app, S, fp, step1, prm)
            %BUILDENTRY Source → registry entry through the one numerical chain (both tabs use it).
            P = pat_build(S, 1); native = max(P.dTheta, P.dPhi); if step1, P = pat_resample(P, 1); end
            G = geo_build(P); app.checkCancelled();
            [~, name, ext] = fileparts(fp);
            e = struct('Name', [name ext], 'Path', fp, 'Source', S, 'Pattern', P, 'Geometry', G, 'Derived', pat_derive(P, G, prm), 'Params', prm, 'Native', native);
        end

        function loadMain(app, fp)
            %LOADMAIN Load button.  Browse when the field is empty, invalid or already loaded; re-selecting the same file reloads (D42).
            fp = strtrim(fp); loadedPath = ''; if app.Main > 0, loadedPath = app.Pats(app.Main).Path; end
            if isempty(fp) || ~isfile(fp) || strcmp(fp, loadedPath)
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.csv;*.dat;*.txt', 'Pattern/Gain Files'}, 'Select an antenna pattern file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            dlg = app.progress('Loading Data', 'Reading file...');  %#ok<NASGU>
            S = io_read(fp, "gain"); app.perf("Read file"); app.checkCancelled();
            if S.Meta.IsCoverage
                app.TabGroup.SelectedTab = app.Tab2_Coverage; app.Cov_EditField_filePath.Value = fp; app.covLoadResults(fp, S.Raw); return
            end
            [V, prm] = app.readConfig();
            e = app.buildEntry(S, fp, V.Step1, prm); app.perf("Build pattern");
            k = find(strcmp({app.Pats.Path}, fp), 1); if isempty(k), k = numel(app.Pats) + 1; end
            app.Pats(k) = e; app.Main = k;                                                % commit
            app.Single_EditField_Path.Value = fp; app.BasisAuto = true; app.OutMask = logical([]);
            app.Range.Auto = struct('full', true, 'cut', true, 'cov', app.Range.Auto.cov, 'covX', app.Range.Auto.covX);
            app.update("source");
        end

        function process(app)
            %PROCESS Process button: re-read a generic text source when its format selector changed, otherwise re-derive only (D55).
            if app.Main == 0, uialert(app.UIFigure, sprintf('No file!\nLoad a pattern first.'), 'Warning', 'Icon', 'warning'); return; end
            e = app.Pats(app.Main); fmt = string(app.Single_DropDown_TextFormat.Value);
            if isfield(e.Source.Meta, 'TextFormat') && fmt ~= e.Source.Meta.TextFormat
                dlg = app.progress('Processing', 'Re-reading with the selected text format...');  %#ok<NASGU>
                S = io_read(e.Path, fmt); assert(~S.Meta.IsCoverage, 'The selected generic format identifies a coverage-results file.');
                [V, prm] = app.readConfig(); app.Pats(app.Main) = app.buildEntry(S, e.Path, V.Step1, prm); app.BasisAuto = true;
                app.update("source");
            else
                app.update("params");
            end
            app.setStatus(app.Single_StatusBar, ['Re-processed <b>' e.Name '</b> with current parameters ' char(9989)], true);
        end

        function resetParams(app)
            d = app.Defaults;
            [app.Single_Spinner_Loss.Value, app.Single_DropDown_RxPol.Value, app.Single_Spinner_Rw.Value, app.Single_Spinner_Pt.Value, ...
                app.Single_DropDown_Pt.Value, app.Single_Spinner_R.Value, app.Single_DropDown_R.Value] = deal(d.Loss, d.RxMode, d.RxAR, d.Pt, d.PtUnit, d.R, d.RUnit);
            app.update("params");
        end

        function dlg = progress(app, ttl, msg)
            dlg = uiprogressdlg(app.UIFigure, 'Title', ttl, 'Message', msg, 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            app.Dialog = dlg; dlg = onCleanup(@() delete(dlg)); drawnow
        end

        % ---------------- apply*: the only writers of Items / Limits / Visible / Enable ----------------

        function applyChoices(app, newSource)
            %APPLYCHOICES Data-derived Items/ItemsData/Text of the Main tab (component, step, frequency, basis, traces, filter).
            e = app.Pats(app.Main); P = e.Pattern; D = e.Derived; S = e.Source;
            [names, labels] = app.componentItems(D.Cols, P.IsGainOnly);
            app.setItems(app.Single_DropDown_Component, labels, names, 'E_Total_dB');
            items = {sprintf('STEP: %g°', e.Native)}; data = {'native'};
            if abs(e.Native - 1) > 1e-9, items{end+1} = 'STEP: 1°'; data{end+1} = '1'; end                   % one item when native is 1° (D52)
            app.setItems(app.Single_DropDown_step, items, data, 'native');
            n = numel(S.Blocks); items = compose('Pattern %d: %.4g GHz', (1:n).', S.Freqs(:)/1e9); miss = isnan(S.Freqs(:));
            items(miss) = compose('Pattern %d', find(miss)); app.setItems(app.Single_DropDown_FFD, cellstr(items), num2cell(1:n), 1);
            if newSource, app.Single_DropDown_FFD.Value = 1; end
            if isfield(S.Meta, 'TextFormat'), app.Single_DropDown_TextFormat.Value = char(S.Meta.TextFormat); end
            if ~P.IsGainOnly
                if app.BasisAuto, if startsWith(D.Pol.label, 'Linear'), app.CutFieldBasisDropDown.Value = 'Linear'; else, app.CutFieldBasisDropDown.Value = 'Circular'; end, end
                pair = D.Pol.pairs.(app.CutFieldBasisDropDown.Value); app.CheckBox_Er.Text = char(pair(1)); app.CheckBox_El.Text = char(pair(2));
            end
            cols = fieldnames(D.Cols);
            if numel(app.OutMask) ~= numel(cols), app.OutMask = ~cellfun(@(c) util_colHidden(c), cols).'; end
            app.applyFilterItems();
        end

        function setItems(~, dd, items, data, preferred)
            %SETITEMS Replace Items/ItemsData; keep the current value when still present, else the preferred one, else the first.
            old = dd.Value; dd.Items = cellstr(items); dd.ItemsData = data;
            if isempty(data), return; end
            hit = cellfun(@(d) isequal(d, old), data); pref = cellfun(@(d) isequal(d, preferred), data);
            if any(hit), dd.Value = data{find(hit, 1)}; elseif any(pref), dd.Value = data{find(pref, 1)}; else, dd.Value = data{1}; end
        end

        function [names, labels] = componentItems(~, Cols, gainOnly)
            %COMPONENTITEMS Selectable components = level/AR/PLF kinds present in Cols (one rule for Main and Coverage).
            K = apat_const(); names = string(fieldnames(Cols)).';
            if gainOnly, labels = names; return; end
            def = string(K.Cols(:, 1)).'; keep = ismember(def, names) & ismember(string(K.Cols(:, 3)).', ["gain", "ar", "plf"]);
            names = def(keep); labels = string(K.Cols(keep, 2)).';
        end

        function applyFilterItems(app)
            %APPLYFILTERITEMS Results-table column filter dropdown: ✓ marks shown columns; styles are rebuilt, never accumulated.
            dd = app.Single_DropDown_output; cols = fieldnames(app.Pats(app.Main).Derived.Cols).';
            items = cols; items(app.OutMask) = append('✓ ', items(app.OutMask));
            dd.Items = [{'--- column filter ---'}, items]; dd.ItemsData = 0:numel(cols); dd.Value = 0;
            removeStyle(dd);
            addStyle(dd, uistyle('FontWeight', 'bold', 'FontColor', 'black', 'BackgroundColor', [0.8 1 0.8]), 'Item', find(app.OutMask) + 1);
            addStyle(dd, uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9]), 'Item', find([true, ~app.OutMask]));
        end

        function toggleFilter(app)
            i = app.Single_DropDown_output.Value;
            if i > 0, app.OutMask(i) = ~app.OutMask(i); end
            app.applyFilterItems(); app.applyVisibility();
        end

        function applyCutDomain(app)
            %APPLYCUTDOMAIN Cut-value spinner limits/step/value in the display convention (D40, D46).
            sp = app.Single_DropDown_cutValue; M = app.Map; P = app.Pats(app.Main).Pattern;
            if app.View.Cut.type == "Phi", vals = sort(M.ThetaAxis(:)); else, vals = sort(M.PhiAxis(1:numel(P.Phi)).'); end
            [~, i] = min(abs(vals - sp.Value)); sp.Limits = [-360 360]; sp.Value = vals(i);
            if vals(end) > vals(1), sp.Limits = [vals(1), vals(end)]; end
            if numel(vals) > 1, sp.Step = min(diff(vals)); end
            app.View.Cut.value = vals(i);
        end

        function applyPlane(app)
            %APPLYPLANE E/H switch → cut type/value from Derived.Planes, expressed in the display convention.
            if app.Main == 0, return; end
            S = app.Pats(app.Main).Derived.Planes; s = S.H; if startsWith(app.Single_Switch_EHplane.Value, 'E'), s = S.E; end
            V = app.readConfig(); v = s.value;
            if s.type == "Phi" && V.Elevation, v = 90 - v; elseif s.type == "Theta" && V.SignedPhi && v >= 180, v = v - 360; end
            app.Single_DropDown_cutType.Value = char(s.type); app.Single_DropDown_cutValue.Limits = [-360 360]; app.Single_DropDown_cutValue.Value = v;
        end

        function applyVisibility(app)
            %APPLYVISIBILITY The only writer of Visible/Enable, computed from data and view state; called once per update (D53, D69).
            loaded = app.Main > 0; field = false; generic = false; blocks = 1; native1 = true; kind = "gain"; plfShown = false; linkShown = false; distShown = false;
            if loaded
                e = app.Pats(app.Main); field = ~e.Pattern.IsGainOnly; generic = isfield(e.Source.Meta, 'TextFormat'); blocks = numel(e.Source.Blocks);
                native1 = numel(app.Single_DropDown_step.Items) == 1; kind = util_colKind(app.View.Component);
                cols = fieldnames(e.Derived.Cols); shown = string(cols(app.OutMask)).';
                plfShown = any(ismember(shown, ["PLF_dB", "Gain_PolCorrected_dB"])); linkShown = any(ismember(shown, ["EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
                distShown = any(ismember(shown, ["PFD_Wm2", "E_RMS_Vm"]));
            end
            set([app.Single_Panel_Rect, app.Single_Export_Output, app.Single_Panel_fullPattern, app.Single_Panel_plotControl, app.Single_Button_Coverage, ...
                app.Single_tabData, app.Single_Table_DataOut, app.Single_Table_DataIn, app.Single_DropDown_output], 'Visible', loaded);
            set([app.Single_Export_UAN, app.Single_gridEcut, app.CheckBox_Et, app.CheckBox_Er, app.CheckBox_El], 'Visible', field);
            set([app.CheckBox_Er, app.CheckBox_El, app.CutFieldBasisDropDown], 'Enable', field);
            set([app.TextFormatLabel, app.Single_DropDown_TextFormat], 'Visible', loaded && generic);
            set([app.FFDFreqDropDownLabel, app.Single_DropDown_FFD], 'Visible', blocks > 1, 'Enable', blocks > 1);
            set(app.Single_DropDown_step, 'Visible', loaded && ~native1, 'Enable', loaded && ~native1);
            set([app.RxPolLabel, app.Single_DropDown_RxPol, app.IncidentWaveARRwPLFLabel, app.Single_Spinner_Rw], 'Visible', field && (kind == "plf" || plfShown));
            set([app.TransmitPowerLabel, app.Single_Spinner_Pt, app.Single_DropDown_Pt], 'Visible', field && linkShown);
            set([app.DistanceLabel, app.Single_Spinner_R, app.Single_DropDown_R], 'Visible', field && distShown);
            set([app.LossindBLabel, app.Single_Spinner_Loss], 'Visible', loaded);
            app.Single_CheckBox_HPBWBounds.Visible = app.Button_HPBW.Value;
            if ~app.Button_HPBW.Value, app.Single_CheckBox_HPBWBounds.Value = false; end
            % ---- coverage tab
            node = app.covTarget(); hasPat = ~isempty(node); jobs = app.covJobs(); anyJobs = ~isempty(jobs);
            checked = any(app.isChecked(jobs)); conical = logical(app.Cov_ButtonGroup_Btn_Conical.Value);
            query = [app.Cov_QueryCoverageLabel, app.Cov_Spinner_queryCov, app.Cov_Button_queryCov, app.Cov_QueryThresholdLabel, app.Cov_Spinner_queryThresh, app.Cov_Button_queryThresh];
            cone = [app.Cov_Spinner_ConeTH, app.Cov_Spinner_ConePH, app.Cov_Spinner_ConeAng, app.ConeSpinnerLabel, app.ConeLabel, app.ConeAngleLabel, app.Cov_DropDown_Orientation, app.Cov_DropDown_OrientationLabel];
            set(app.Cov_gridPanel_Parm.Children, 'Visible', hasPat, 'Enable', hasPat);
            set([app.AntennaPatternEditFieldLabel, app.Cov_EditField_filePath, app.Cov_Button_Load, app.Cov_Button_computeCov, app.Cov_Button_toMain], 'Visible', 'on', 'Enable', 'on');
            set([query, app.Cov_Button_Reset, app.Cov_Button_Export, app.Cov_Button_Clear], 'Visible', hasPat || anyJobs);
            set([query, app.Cov_Button_Export, app.Cov_Button_Clear], 'Enable', checked); set(app.Cov_Button_Reset, 'Enable', hasPat || anyJobs);
            set(app.Cov_Button_computeCov, 'Enable', hasPat); set(cone, 'Visible', hasPat && conical, 'Enable', hasPat && conical);
            covGeneric = hasPat && isfield(app.Pats(node.NodeData.k).Source.Meta, 'TextFormat');
            set([app.Cov_TextFormatLabel, app.Cov_DropDown_TextFormat], 'Visible', covGeneric, 'Enable', covGeneric);
            app.Cov_Panel_Results.Visible = hasPat || anyJobs;
        end

        function applyRange(app, group, lim, mode)
            %APPLYRANGE Only writer of the four range groups (§5.4).  mode: "set" (preset/Apply: slider travel = lim),
            % "spin" (spinner edit: travel widens to include lim), "slide" (slider drag: travel kept).  A user edit clears Auto.
            K = apat_const(); gap = 1; if any(group == ["cov", "covX", "all"]), gap = 0.1; end
            if group == "all", app.applyRange("full", lim, mode); app.applyRange("cut", lim, mode); return; end
            lim = sort(double(lim(:).')); lim = min(max(lim, K.Hard(1)), K.Hard(2));
            if diff(lim) < gap, lim(2) = min(K.Hard(2), lim(1) + gap); lim(1) = lim(2) - gap; end
            switch group
                case "full", sl = [app.Range_Ctr, app.Range_Cir, app.Range_3dSph, app.Range_3dPol, app.Range_3dRect];
                             mn = [app.Range_Ctr_Min, app.Range_Cir_Min, app.Range_3dSph_Min, app.Range_3dPol_Min, app.Range_3dRect_Min, app.Single_Plot_Cmin];
                             mx = [app.Range_Ctr_Max, app.Range_Cir_Max, app.Range_3dSph_Max, app.Range_3dPol_Max, app.Range_3dRect_Max, app.Single_Plot_Cmax];
                case "cut",  sl = app.Range_Cut; mn = app.Range_Cut_Min; mx = app.Range_Cut_Max;
                case "cov",  sl = []; mn = app.Cov_Spinner_ThreshMin; mx = app.Cov_Spinner_ThreshMax;
                case "covX", sl = app.Cov_Spinner_XRange; mn = app.Cov_Spinner_XMin; mx = app.Cov_Spinner_XMax;
            end
            if ~isempty(sl) && mode ~= "slide"
                travel = lim; if mode == "spin", travel = [min(sl(1).Limits(1), lim(1)), max(sl(1).Limits(2), lim(2))]; end
                set(sl, 'Limits', K.Hard, 'Value', lim); set(sl, 'Limits', travel);
            end
            set(mn, 'Limits', K.Hard, 'Value', lim(1)); set(mn, 'Limits', [K.Hard(1), lim(2) - gap]);
            set(mx, 'Limits', K.Hard, 'Value', lim(2)); set(mx, 'Limits', [lim(1) + gap, K.Hard(2)]);
            app.Range.(group) = lim; if mode ~= "set", app.Range.Auto.(group) = false; end
            switch group
                case "full", for k = 1:5, app.applyTheme(k); end
                case "cut",  set(app.Single_paxCut, 'RLim', lim, 'RTick', lim(1):5:lim(2)); set(app.Single_AxesRect, 'YLim', lim);
                case "covX", set(app.Cov_Axes, 'XLimMode', 'manual', 'XLim', lim);
            end
        end

        function applyTheme(app, k)
            %APPLYTHEME Colour scale of one full-pattern view: signed AR → fixed ±30 dB blue-white-red; else Range.full with jet (D41, D66).
            if app.Main == 0 || k == 0, return; end
            K = apat_const(); s = app.Gfx.Full(k); ax = app.viewAxes(k); isAR = util_colKind(app.View.Component) == "ar";
            if isAR, lim = K.ARLimits; map = app.Gfx.Maps.AR; else, lim = app.Range.full; map = app.Gfx.Maps.Gain; end
            clim(ax, lim); colormap(ax, map); t = util_ticks(lim, app.View.CStep);
            if ~isempty(t), s.Colorbar.Ticks = t; else, s.Colorbar.TicksMode = 'auto'; end
            s.Colorbar.Label.String = app.levelUnit(app.View.Component);
            if k == 5, zlim(ax, lim); if ~isempty(t), ax.ZTick = t; end, end
        end

        function applyCamera(app)
            V = app.readConfig(); up = [0 0 1];
            switch V.Camera
                case "top",    az = 0; el = 90; up = [0 1 0];
                case "bottom", az = 0; el = -90; up = [0 1 0];
                case "right",  az = 90; el = 0;
                case "left",   az = -90; el = 0;
                case "front",  az = 0; el = 0;
                case "back",   az = 180; el = 0;
                otherwise,     az = NaN; el = NaN;
            end
            K = apat_const();
            for k = 3:5
                ax = app.viewAxes(k); def = K.Views{k, 5};
                if isnan(az), view(ax, def(1), def(2)); else, view(ax, az, el); end
                camup(ax, up);
            end
        end

        function applyAnnot(app)
            %APPLYANNOT POB / HPBW annotation handles: create missing datatips (after the surfaces are drawn) and set Visible.
            if app.Main == 0, return; end
            V = app.View; vis = app.visibleView();
            for k = 1:5
                s = app.Gfx.Full(k); if ~s.HasPOB, continue; end
                if ~isgraphics(s.Tip) && V.POB && k == vis, s.Tip = datatip(s.Marker, 'DataIndex', 1, 'FontSize', 9, 'Tag', 'APAT'); app.Gfx.Full(k).Tip = s.Tip; end
                s.Marker.Visible = V.POB; if isgraphics(s.Tip), s.Tip.Visible = V.POB && k == vis; end
            end
            c = app.Gfx.Cut; tabs = [app.Single_tabPolarPlot, app.Single_tabRectPlot]; sel = app.Single_tabCut.SelectedTab;
            for m = 1:2
                mk = c.POB(m); if c.HasPOB && ~isgraphics(c.POBTip(m)) && V.POB, c.POBTip(m) = datatip(mk, 'DataIndex', 1, 'FontSize', 9, 'Tag', 'APAT'); end
                mk.Visible = V.POB && c.HasPOB; if isgraphics(c.POBTip(m)), c.POBTip(m).Visible = V.POB && sel == tabs(m); end
                for b = 1:2
                    h = c.HPBW(m, b); on = V.HPBW && V.HPBWTips && c.HasHPBW;
                    if on && ~isgraphics(c.HPBWTip(m, b)), c.HPBWTip(m, b) = datatip(h, 'DataIndex', 1, 'FontSize', 9, 'Tag', 'APAT'); end
                    h.Visible = on; if isgraphics(c.HPBWTip(m, b)), c.HPBWTip(m, b).Visible = on && sel == tabs(m); end
                end
            end
            app.Gfx.Cut = c;
        end

        % ---------------- small accessors ----------------

        function ax = viewAxes(app, k)
            axesList = {app.Single_Axes_Ctr, app.Single_paxPattern, app.Single_Axes_3dSph, app.Single_Axes_3dPol, app.Single_Axes_3dRect}; ax = axesList{k};
        end

        function k = visibleView(app)
            tabs = [app.Single_tabContour, app.Single_tabCircular, app.Single_tab3DSpherical, app.Single_tab3DPolar, app.Single_tab3DRect];
            k = find(tabs == app.Single_tabPlots.SelectedTab, 1); if isempty(k), k = 1; end
        end

        function u = levelUnit(app, col)
            %LEVELUNIT Unit label of a column: level columns carry Meta.UnitLabel (I9); AR/PLF are relative dB.
            u = 'dB'; if util_colKind(col) == "gain", u = char(app.Pats(app.Main).Pattern.Meta.UnitLabel); end
        end

        function lbl = compLabel(app)
            dd = app.Single_DropDown_Component; i = find(cellfun(@(d) isequal(d, dd.Value), dd.ItemsData), 1);
            if isempty(i), lbl = char(dd.Value); else, lbl = dd.Items{i}; end
        end

        % ---------------- perf, status, errors ----------------

        function perf(app, stage)
            %PERF perf("begin <op>") | perf("<stage>") | perf("end") → app.Perf and base variable Perf_<class> (same record shape as M7).
            if startsWith(stage, "begin"), app.PerfRun = struct('Op', strtrim(extractAfter(stage, 5)), 'T0', tic, 'T', tic, 'Rows', {cell(0, 2)}); return; end
            if isempty(app.PerfRun), return; end
            app.PerfRun.Rows(end+1, :) = {char(stage), toc(app.PerfRun.T)}; app.PerfRun.T = tic;
            if stage ~= "end", return; end
            app.Perf = struct('AppVersion', string(class(app)), 'Operation', string(app.PerfRun.Op), ...
                'Stages', cell2table(app.PerfRun.Rows, 'VariableNames', {'Stage', 'Seconds'}), 'TotalSeconds', toc(app.PerfRun.T0));
            assignin('base', matlab.lang.makeValidName("Perf_" + class(app)), app.Perf); app.PerfRun = [];
        end

        function setStatus(app, label, msg, transient)
            %SETSTATUS One timer for transient messages; the persistent text lives in app.Status.(label.Tag) (D63).
            if app.isClosing || ~isgraphics(label), return; end
            stop(app.StatusTimer); label.Text = char(msg);
            if ~transient, app.Status.(label.Tag) = char(msg); return; end
            app.StatusTimer.TimerFcn = @(~, ~) app.restoreStatus(label); start(app.StatusTimer);
        end

        function restoreStatus(app, label), if ~app.isClosing && isgraphics(label), label.Text = app.Status.(label.Tag); end, end

        function showError(app, err, ttl)
            if app.isClosing || ~isvalid(app.UIFigure), return; end
            where = ''; if ~isempty(err.stack), where = sprintf('\n(%s line %d)', err.stack(1).name, err.stack(1).line); end
            uialert(app.UIFigure, [err.message where], ['APAT — ' ttl], 'Icon', 'error');
        end

        function checkCancelled(app)
            if ~isempty(app.Dialog) && isvalid(app.Dialog) && app.Dialog.CancelRequested
                app.Dialog.Message = 'Aborting...'; drawnow limitrate; error('APAT:Cancelled', 'Operation cancelled by user.');
            end
        end
    end

    methods (Access = private)   % ================= D. RENDERERS (retained mode, key-guarded) =================

        function renderFull(app, k)
            %RENDERFULL One full-pattern view (row k of apat_const().Views).  Surface, POB marker and overlay are created once
            % and updated in place; the key makes a component change one CData assignment (I12, D57).
            if app.Main == 0 || k == 0, return; end
            K = apat_const(); kind = string(K.Views{k, 4}); s = app.Gfx.Full(k); ax = app.viewAxes(k);
            e = app.Pats(app.Main); P = e.Pattern; D = e.Derived; V = app.View; M = app.Map;
            lim = app.Range.full; if util_colKind(V.Component) == "ar", lim = K.ARLimits; end
            key = sprintf('%d|%s|%s|%s|%s|%d', P.Revision, jsonencode(e.Params), V.Component, M.Key, mat2str(lim*(kind == "polar")), V.Overlay);
            if strcmp(s.Key, key), return; end
            C = D.Cols.(V.Component); C = C(:, M.ColIdx); lbl = app.compLabel(); unit = app.levelUnit(V.Component);
            [X, Y, Z, rmax] = app.viewCoords(kind, P, M, C, lim);
            if isgraphics(s.Surface) && isequal(size(s.Surface.CData), size(C))
                set(s.Surface, 'XData', X, 'YData', Y, 'ZData', Z, 'CData', C);
            else
                delete(s.Surface); s.Surface = surface(ax, X, Y, Z, C, 'EdgeColor', 'none', 'Tag', 'APAT'); s.Surface.ContextMenu = app.Gfx.Menu;
                if any(kind == ["pcolor", "fisheye"]), s.Surface.FaceColor = 'interp'; end
            end
            [TH, PH] = app.displayGrids(P, M);
            app.setTipRows(s.Surface, [dataTipTextRow(M.ThetaLabel, TH, '%.3g°'); dataTipTextRow("Phi", PH, '%.3g°'); dataTipTextRow(lbl, C, ['%.3g ' unit])]);
            % POB marker: the total-gain peak direction, showing the selected component's value there (I4)
            [i, j] = ind2sub([numel(P.Theta), numel(P.Phi)], D.Peak.index); jd = find(M.ColIdx == j, 1);
            if isvector(X), px = X(jd); py = Y(i); else, px = X(i, jd); py = Y(i, jd); end                  % pcolor keeps vector axes
            if kind == "fisheye", set(s.Marker, 'ThetaData', px, 'RData', py); else, set(s.Marker, 'XData', px, 'YData', py, 'ZData', Z(i, jd)); end
            s.HasPOB = true;
            app.setTipRows(s.Marker, [dataTipTextRow(M.ThetaLabel, TH(i, jd), '%.3g°'); dataTipTextRow("Phi", PH(i, jd), '%.3g°'); dataTipTextRow(lbl, C(i, jd), ['%.3g ' unit])]);
            if isgraphics(s.Tip), delete(s.Tip); end
            % overlay of the current cut on the 3-D spatial views (D60, D72)
            if any(kind == ["sphere", "polar"]) && V.Overlay
                cut = app.currentCut(); r = 1.02; if kind == "polar", r = util_polarRadius(cut.y(:, 1), lim, rmax)*1.01; end
                set(s.Overlay, 'XData', r.*sind(cut.theta).*cosd(cut.phi), 'YData', r.*sind(cut.theta).*sind(cut.phi), 'ZData', r.*cosd(cut.theta), 'Visible', 'on');
            elseif isgraphics(s.Overlay), s.Overlay.Visible = 'off';
            end
            app.formatView(k, kind, lbl, unit); s.Key = key; app.Gfx.Full(k) = s;
        end

        function [X, Y, Z, rmax] = viewCoords(app, kind, P, M, C, lim)
            %VIEWCOORDS Coordinates of one view kind.  Spatial views use physical angles; angular views use the display axes.
            rmax = 1; [THp, PHp] = ndgrid(P.Theta, P.Phi(M.ColIdx));      % physical (closing column repeats φ₁, same direction)
            switch kind
                case "pcolor",  X = M.PhiAxis(:).'; Y = M.ThetaAxis(:); Z = zeros(size(C));
                case "fisheye", X = deg2rad(PHp); Y = THp; Z = zeros(size(C));
                case "rect",    [X, Y] = meshgrid(M.PhiAxis, M.ThetaAxis); Z = C;
                otherwise                                                    % sphere | polar
                    r = 1; if kind == "polar", [r, rmax] = util_polarRadius(C, lim); end
                    X = r.*sind(THp).*cosd(PHp); Y = r.*sind(THp).*sind(PHp); Z = r.*cosd(THp);
            end
        end

        function [TH, PH] = displayGrids(~, ~, M), [TH, PH] = ndgrid(M.ThetaAxis, M.PhiAxis); end

        function formatView(app, k, kind, lbl, unit)
            %FORMATVIEW Axes ticks, labels, title and camera of one view (geometry stays physical; labels follow the convention).
            ax = app.viewAxes(k); M = app.Map; V = app.View;
            phiLim = [0 360]; if V.SignedPhi, phiLim = [-180 180]; end
            thLim = [0 180]; if V.Elevation, thLim = [-90 90]; end
            switch kind
                case "pcolor"
                    set(ax, 'XLim', phiLim, 'YLim', thLim, 'YDir', M.ThetaDir, 'XTick', phiLim(1):30:phiLim(2), 'YTick', thLim(1):15:thLim(2), 'Box', 'on', 'Layer', 'top');
                    daspect(ax, [1 1 1]); xlabel(ax, 'Phi (degree)'); ylabel(ax, M.ThetaLabel + " (degree)"); title(ax, lbl, 'Interpreter', 'none');
                case "fisheye"
                    a = 0:30:330; if V.SignedPhi, a(a > 180) = a(a > 180) - 360; end
                    r = 0:30:180; if V.Elevation, r = 90 - r; end
                    set(ax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', a), 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', r));
                    title(ax, sprintf('%s  |  r=θ, angle=φ', lbl), 'Interpreter', 'none', 'FontSize', 9);
                case "rect"
                    set(ax, 'XLim', phiLim, 'YLim', thLim, 'YDir', M.ThetaDir, 'XTick', phiLim(1):60:phiLim(2), 'YTick', thLim(1):30:thLim(2), 'Box', 'on', 'Layer', 'top');
                    xlabel(ax, 'Phi (degree)'); ylabel(ax, M.ThetaLabel + " (degree)"); zlabel(ax, sprintf('%s (%s)', lbl, unit), 'Interpreter', 'none');
                    grid(ax, 'on'); title(ax, lbl, 'Interpreter', 'none');
                otherwise
                    title(ax, sprintf('%s  |  θ: %s  |  φ: %s', lbl, app.Single_Switch_ThetaSpan.Value, app.Single_Switch_AngularSpan.Value), 'Interpreter', 'none');
            end
            if k >= 3, app.applyCamera(); end
        end

        function setTipRows(~, h, rows)
            %SETTIPROWS DataTipTemplate rows; the template of a fresh surface may not exist until a tip has been created once.
            try, h.DataTipTemplate.DataTipRows = rows;
            catch, t = datatip(h, 'DataIndex', 1); delete(t); h.DataTipTemplate.DataTipRows = rows; end
        end

        function [cols, idx] = cutTraces(app)
            %CUTTRACES Columns plotted on the cut: Total + co/cross pair (E-field) or the selected column (gain-only, D15).
            e = app.Pats(app.Main); V = app.View;
            if e.Pattern.IsGainOnly, cols = V.Component; idx = 1; return; end
            pair = e.Derived.Pol.pairs.(V.Basis); all3 = ["E_Total_dB", pair + "_dB"];
            sel = V.Traces; if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = all3(idx);
        end

        function cut = currentCut(app)
            %CURRENTCUT geo_cut for the current controls: one extraction serves polar, rectangular, overlays and HPBW (D61).
            e = app.Pats(app.Main); V = app.View; cols = app.cutTraces();
            v = V.Cut.value; if V.Cut.type == "Phi" && V.Elevation, v = 90 - v; elseif V.Cut.type == "Theta", v = mod(v, 360); end
            cut = geo_cut(e.Pattern, cellfun(@(c) e.Derived.Cols.(c), cellstr(cols), 'UniformOutput', false), V.Cut.type, v, e.Geometry.PhiPeriodic);
            cut.cols = cols;
        end

        function renderCut(app)
            %RENDERCUT Polar + rectangular cut, cut POB marker, HPBW regions/bounds.  Three retained lines per axes.
            if app.Main == 0, return; end
            e = app.Pats(app.Main); V = app.View; c = app.Gfx.Cut; pax = app.Single_paxCut; rax = app.Single_AxesRect;
            [cols, idx] = app.cutTraces(); cut = app.currentCut();
            key = sprintf('%d|%s|%s|%s|%s|%s|%d|%s', e.Pattern.Revision, jsonencode(e.Params), V.Component, jsonencode(cols), jsonencode(V.Cut), app.Map.Key, V.HPBW, mat2str(app.Range.cut));
            if strcmp(c.Key, key), return; end
            [a, Y] = util_circle(cut.angle, cut.y, V.SignedPhi, cut.closed); lim = app.Range.cut; unit = app.levelUnit(cols(1));
            xl = [0 360]; if V.SignedPhi, xl = [-180 180]; end
            names = cellstr(cols); order = pax.ColorOrder;
            for m = 1:3
                on = m <= numel(idx); set([c.Polar(m), c.Rect(m)], 'Visible', on);
                if ~on, continue; end
                col = order(1 + mod(idx(m) - 1, size(order, 1)), :);
                set(c.Polar(m), 'ThetaData', deg2rad(a), 'RData', max(Y(:, m), lim(1)), 'Color', col);       % clamp keeps spikes off the inner rim
                set(c.Rect(m), 'XData', a, 'YData', Y(:, m), 'Color', col);
                rows = [dataTipTextRow("Angle", a, '%.3g°'); dataTipTextRow("Magnitude", Y(:, m), ['%.3g ' unit])];
                c.Polar(m).DataTipTemplate.DataTipRows = rows; c.Rect(m).DataTipTemplate.DataTipRows = rows;
            end
            tl = 0:30:330; if V.SignedPhi, tl(tl > 180) = tl(tl > 180) - 360; end
            set(pax, 'ThetaDir', 'clockwise', 'ThetaZeroLocation', 'top', 'RLim', lim, 'RTick', lim(1):5:lim(2), 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', tl));
            set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on'); xlabel(rax, V.Cut.type + " (degree)"); ylabel(rax, ['Magnitude (' unit ')']);
            if e.Pattern.IsGainOnly, ttl = app.compLabel(); else, ttl = sprintf('%s cut @ %s = %g°', V.Cut.type, cut.symbol, cut.fixed); end
            title(pax, ttl, 'Interpreter', 'none'); title(rax, ttl, 'Interpreter', 'none');
            legend(pax, c.Polar(1:numel(idx)), names, 'Location', 'southoutside', 'Orientation', 'horizontal', 'Interpreter', 'none');
            legend(rax, c.Rect(1:numel(idx)), names, 'Location', 'best', 'Interpreter', 'none');
            if cut.snapped, app.setStatus(app.Single_StatusBar, sprintf('Requested %s cut snapped to nearest %s = %g°', V.Cut.type, cut.symbol, cut.fixed), true); end
            % cut POB = peak of the first plotted trace
            [pk, ip] = max(Y(:, 1), [], 'omitnan'); delete(c.POBTip(isgraphics(c.POBTip))); c.HasPOB = isfinite(pk);
            set(c.POB(1), 'ThetaData', deg2rad(a(ip)), 'RData', max(pk, lim(1))); set(c.POB(2), 'XData', a(ip), 'YData', pk);
            rows = [dataTipTextRow("Angle", a(ip), '%.3g°'); dataTipTextRow(names{1}, pk, ['%.3g ' unit])]; c.POB(1).DataTipTemplate.DataTipRows = rows; c.POB(2).DataTipTemplate.DataTipRows = rows;
            % HPBW on the first trace, wrap-aware, bounds mapped into the display range
            app.Label_HPBW.Text = ''; cellfun(@(h) delete(h(isgraphics(h))), c.Regions); c.Regions = {}; delete(c.HPBWTip(isgraphics(c.HPBWTip))); c.HasHPBW = false;
            if V.HPBW
                [bw, lo, hi] = met_hpbw(cut.angle, cut.y(:, 1));
                if isfinite(bw)
                    b = mod([lo hi], 360); if V.SignedPhi, b = mod(b + 180, 360) - 180; end
                    app.Label_HPBW.Text = sprintf('HPBW (%s)\n%.1f°\n(%.1f° to %.1f°)', names{1}, bw, b(1), b(2));
                    if b(1) <= b(2), reg = b; else, reg = [xl(1) b(2); b(1) xl(2)]; end
                    c.Regions = {thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12), xregion(rax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12)};
                    bl = ["Lower HPBW", "Upper HPBW"]; c.HasHPBW = true;
                    for m = 1:2
                        set(c.HPBW(1, m), 'ThetaData', deg2rad(b(m)), 'RData', pk - 3); set(c.HPBW(2, m), 'XData', b(m), 'YData', pk - 3);
                        rows = [dataTipTextRow(bl(m), b(m), '%.2f°'); dataTipTextRow("Level", pk - 3, ['%.2f ' unit])];
                        c.HPBW(1, m).DataTipTemplate.DataTipRows = rows; c.HPBW(2, m).DataTipTemplate.DataTipRows = rows;
                    end
                end
            end
            c.Key = key; app.Gfx.Cut = c;
            for k = 3:4, app.Gfx.Full(k).Key = ''; end                                    % overlays follow the cut
        end

        function T = resultsTable(app)
            %RESULTSTABLE Results in the display convention from Derived.Cols and the column filter (table and export share it).
            e = app.Pats(app.Main); M = app.Map; P = e.Pattern; cols = fieldnames(e.Derived.Cols); cols = cols(app.OutMask);
            [TH, PH] = app.displayGrids(P, M);
            vals = cellfun(@(c) reshape(e.Derived.Cols.(c)(:, M.ColIdx), [], 1), cols, 'UniformOutput', false);
            T = array2table([TH(:), PH(:), vals{:}], 'VariableNames', [{'Theta', 'Phi'}, cols.']);
        end

        function renderTables(app)
            %RENDERTABLES Input table once per source/block; Results table only when its tab is visible and its key changed (D43).
            if app.Main == 0, return; end
            e = app.Pats(app.Main); V = app.View;
            inKey = sprintf('%s|%d', e.Path, V.FreqIndex);
            if ~strcmp(app.Gfx.InKey, inKey)
                raw = e.Source.Raw; if numel(e.Source.Blocks) > 1, raw = e.Source.Blocks{V.FreqIndex}; end
                set(app.Single_Table_DataIn, 'Data', raw, 'ColumnName', raw.Properties.VariableNames); app.Gfx.InKey = inKey;
            end
            outKey = sprintf('%d|%s|%s|%s', e.Pattern.Revision, jsonencode(e.Params), app.Map.Key, mat2str(app.OutMask));
            if app.Single_tabData.SelectedTab == app.Single_tabDataOut && ~strcmp(app.Gfx.OutKey, outKey)
                T = app.resultsTable(); set(app.Single_Table_DataOut, 'Data', T, 'ColumnName', T.Properties.VariableNames); app.Gfx.OutKey = outKey;
            end
        end

        function renderMetadata(app)
            %RENDERMETADATA Facts, metrics, parameters, conventions and reader notes in one table (I9, D67).
            e = app.Pats(app.Main); P = e.Pattern; G = e.Geometry; D = e.Derived; m = D.Metrics; K = apat_const(); f = @util_fmt; u = char(P.Meta.UnitLabel);
            sphere = 'partial sphere'; if G.IsFullSphere, sphere = 'full sphere'; end
            if G.PhiPeriodic, sphere = [sphere ', φ periodic']; end
            rows = {'Source format', char(P.Meta.Format); 'File', e.Name; 'Level unit', u
                'Samples', sprintf('%d  (θ: %d × φ: %d)', numel(G.dOmega), numel(P.Theta), numel(P.Phi))
                'θ range / step', sprintf('[%s°, %s°] / %s°', f(P.Theta(1)), f(P.Theta(end)), f(P.dTheta))
                'φ range / step', sprintf('[%s°, %s°] / %s°', f(P.Phi(1)), f(P.Phi(end)), f(P.dPhi))
                'Sphere', sprintf('%s, Σ ΔΩ = %s sr', sphere, f(G.Omega, 4))};
            if isfinite(P.Freq), rows(end+1, :) = {'Frequency', sprintf('%.4g GHz', P.Freq/1e9)}; end
            if ~P.IsGainOnly
                rows(end+1, :) = {'Polarization (main beam)', D.Pol.label};
                rows(end+1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(D.Pol.pairs.(app.View.Basis), ' / '))};
            end
            rows = [rows; {'Peak (POB)', sprintf('%s %s', f(m.PeakGain_dB), u); 'POB direction [θ, φ]', sprintf('[%s°, %s°]', f(m.PeakTheta_deg), f(m.PeakPhi_deg))
                'Peak policy', sprintf('isolated spike > %g dB above its 4 neighbours is ignored', K.PeakExcessDB)}];
            if D.Peak.wasAdjusted, rows(end+1, :) = {'Raw peak (spike)', sprintf('%s %s  (%d spike sample(s) excluded)', f(D.Peak.rawValue), u, D.Peak.spikeCount)}; end
            rows = [rows; {'Boresight axis', K.Axes.labels{D.Boresight}; 'HPBW E-plane', [f(m.HPBW_EPlane_deg) '°']; 'HPBW H-plane', [f(m.HPBW_HPlane_deg) '°']
                'Front-to-back', [f(m.FrontBack_dB) ' dB']; 'Peak directivity', [f(m.PeakDirectivity_dB) ' dB']}];
            if isfinite(m.Efficiency_pct), rows(end+1, :) = {'Radiation efficiency', [f(m.Efficiency_pct) '%']}; end
            if isfinite(m.AxialRatioAtPeak_dB), rows(end+1, :) = {'AR at peak (signed)', [f(m.AxialRatioAtPeak_dB) ' dB']}; end
            p = e.Params;
            rows = [rows; {'Parameters', sprintf('L = %s dB, Rx = %s, Rw = %s dB, Pt = %s dBW, R = %s m', f(p.L), p.RxMode, f(p.RxAR_dB), f(p.Pt_dBW), f(p.R_m))
                'Circular basis', 'E_R = (Eθ + jEφ)/√2, E_L = (Eθ − jEφ)/√2  (IEEE, e^{+jωt}); signed AR: + RHCP, − LHCP, −100 dB linear'
                'Coverage definition', 'Coverage(T) = 100·Ω_R(G > T)/Ω_R, ΔΩ = (cos θ₋ − cos θ₊)·Δφ'}];
            for n = 1:numel(P.Meta.Notes), rows(end+1, :) = {'Reader note', char(P.Meta.Notes(n))}; end %#ok<AGROW>
            app.Single_Table_metadata.Data = rows;
        end
    end

    methods (Access = private)   % ================= E. COVERAGE TAB (the tree is the job registry; a job is a curve) =================

        function node = covTarget(app)
            %COVTARGET Pattern node to work on: the selection's pattern ancestor, else the most recently added pattern node.
            node = []; n = app.Cov_Tree.SelectedNodes; if ~isempty(n), n = n(1); end
            while ~isempty(n) && isa(n, 'matlab.ui.container.TreeNode')
                if isstruct(n.NodeData) && n.NodeData.kind == "pattern", node = n; return; end
                n = n.Parent;
            end
            kids = app.Cov_TreeNode_Results.Children;
            for k = numel(kids):-1:1, if isstruct(kids(k).NodeData) && kids(k).NodeData.kind == "pattern", node = kids(k); return; end, end
        end

        function tf = isChecked(app, nodes)
            c = app.Cov_Tree.CheckedNodes; tf = false(size(nodes)); if isempty(nodes) || isempty(c), return; end
            tf = ismember(nodes, c);
        end

        function jobs = covJobs(app, roots)
            %COVJOBS Job nodes (children of pattern/results nodes), optionally restricted to a subtree, in creation order.
            if nargin < 2 || isempty(roots), roots = app.Cov_TreeNode_Results.Children; end
            jobs = matlab.ui.container.TreeNode.empty(0, 1);
            for r = roots(:).'
                if isstruct(r.NodeData) && r.NodeData.kind == "job", jobs(end+1, 1) = r; else, jobs = [jobs; r.Children(:)]; end %#ok<AGROW>
            end
            jobs = jobs(arrayfun(@(n) isstruct(n.NodeData) && n.NodeData.kind == "job", jobs));
            if numel(jobs) > 1, [~, o] = sort(arrayfun(@(n) n.NodeData.id, jobs)); jobs = jobs(o); end
        end

        function covAddPattern(app, k)
            %COVADDPATTERN Tree node for registry entry k (select the existing one when present).  Main→Coverage uses k = Main.
            if k == 0, uialert(app.UIFigure, 'Load and process a pattern first.', 'Coverage'); return; end
            app.TabGroup.SelectedTab = app.Tab2_Coverage; app.Cov_EditField_filePath.Value = app.Pats(k).Path;
            kids = app.Cov_TreeNode_Results.Children; node = [];
            for n = kids(:).', if isstruct(n.NodeData) && n.NodeData.kind == "pattern" && n.NodeData.k == k, node = n; break; end, end
            if isempty(node)
                [~, name] = fileparts(app.Pats(k).Path);
                node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📡 ' name], 'NodeData', struct('kind', "pattern", 'k', k));
                app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node]; expand(app.Cov_Tree);
            end
            app.Cov_Tree.SelectedNodes = node; app.covSelect();
            app.setStatus(app.Cov_StatusBar, sprintf('Pattern "<b>%s</b>" ready — compute coverage.', app.Pats(k).Name), false);
        end

        function covLoad(app, fp)
            %COVLOAD Coverage Load button: pattern file → registry entry + node; results file → curves.  Parsed inside the guard (D64).
            fp = strtrim(fp); known = app.covPathNode(fp);
            if isempty(fp) || ~isfile(fp) || ~isempty(known)
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.ffd;*.ffe;*.ffs;*.cut;*.xlsx;*.csv;*.dat;*.txt', 'Pattern / coverage data'; '*.*', 'All files'}, 'Select a pattern or coverage results file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f); known = app.covPathNode(fp);
            end
            if ~isempty(known)
                app.Cov_Tree.SelectedNodes = known; app.covSelect(); app.setStatus(app.Cov_StatusBar, 'File already loaded — node selected.', true); return
            end
            dlg = app.progress('Loading Data', 'Reading file...');  %#ok<NASGU>
            S = io_read(fp, "gain"); app.perf("Read file"); app.checkCancelled();
            if S.Meta.IsCoverage, app.Cov_EditField_filePath.Value = fp; app.covLoadResults(fp, S.Raw); return; end
            [~, prm] = app.readConfig(); e = app.buildEntry(S, fp, false, prm); app.perf("Build pattern");
            k = find(strcmp({app.Pats.Path}, fp), 1); if isempty(k), k = numel(app.Pats) + 1; end
            app.Pats(k) = e; app.covAddPattern(k);
        end

        function node = covPathNode(app, fp)
            node = [];
            for n = app.Cov_TreeNode_Results.Children(:).'
                d = n.NodeData; if ~isstruct(d), continue; end
                if (d.kind == "pattern" && strcmp(app.Pats(d.k).Path, fp)) || (d.kind == "results" && strcmp(d.path, fp)), node = n; return; end
            end
        end

        function covReformat(app)
            %COVREFORMAT Coverage text-format selector: re-read the target generic source with the new format (shared entry).
            node = app.covTarget(); if isempty(node), return; end
            k = node.NodeData.k; e = app.Pats(k); fmt = string(app.Cov_DropDown_TextFormat.Value);
            if ~isfield(e.Source.Meta, 'TextFormat') || fmt == e.Source.Meta.TextFormat, return; end
            S = io_read(e.Path, fmt);
            if S.Meta.IsCoverage, app.setStatus(app.Cov_StatusBar, 'Coverage-result files are detected automatically.', true); return; end
            app.Pats(k) = app.buildEntry(S, e.Path, false, e.Params);
            if k == app.Main, app.update("source"); end
            app.covSelect(); app.setStatus(app.Cov_StatusBar, sprintf('Pattern <b>"%s"</b> re-read with the selected format.', e.Name), true);
        end

        function covLoadResults(app, fp, T)
            [~, name] = fileparts(fp); thr = T{:, 1};
            node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📄 ' name], 'NodeData', struct('kind', "results", 'name', name, 'path', fp));
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node];
            for c = 2:width(T), app.covAddJob(node, thr, T{:, c}, T.Properties.VariableNames{c}, '📈'); end
            if app.Range.Auto.covX, app.applyRange("covX", [min(thr), max(thr)], "set"); end
            expand(app.Cov_TreeNode_Results); app.Cov_Tree.SelectedNodes = node; app.covRefresh(); app.covSelect();
            app.setStatus(app.Cov_StatusBar, sprintf('Coverage results file "%s" loaded (%d curves).', name, width(T) - 1), false);
        end

        function covCompute(app)
            %COVCOMPUTE Coverage(T) = 100·Ω_R(G > T)/Ω_R on the registry entry's current columns (I3, I7).
            node = app.covTarget(); if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            e = app.Pats(node.NodeData.k); c = app.readCoverageConfig(); C = e.Derived.Cols.(c.Component);
            if c.Conical
                mask = cov_coneMask(e.Pattern, c.Cone(1), c.Cone(2), c.Cone(3)); region = sprintf('Con(%s) α=%s°', app.coneLabel(c.Cone(1), c.Cone(2)), util_fmt(c.Cone(3)));
            else
                mask = true(size(C)); region = 'Sph';
            end
            cov = cov_curve(C, e.Geometry.dOmega, mask, c.T); app.perf("Coverage");
            id = app.covAddJob(node, c.T, cov, sprintf('%s · %s · L=%s dB', region, c.Component, util_fmt(e.Params.L)), '📉');
            if app.Range.Auto.covX, app.applyRange("covX", [c.T(1), c.T(end)], "set"); end
            app.covRefresh();
            txt = sprintf('Run <b>%d</b>: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds, step %s dB).', id, region, e.Name, c.Component, numel(c.T), util_fmt(c.T(2) - c.T(1)));
            if ~any(mask(:)), txt = [txt ' | <b>Empty region</b> — coverage is 0 %.']; end
            app.setStatus(app.Cov_StatusBar, txt, false);
        end

        function id = covAddJob(app, parent, T, cov, label, icon)
            %COVADDJOB One job = one curve {T, cov} + its line; computed and file-loaded jobs are identical from here on (§6.9).
            app.CovRunID = app.CovRunID + 1; id = app.CovRunID; label = sprintf('R%d %s', id, label);
            h = plot(app.Cov_Axes, T(:), cov(:), 'LineWidth', 1.6, 'DisplayName', label);
            h.DataTipTemplate.DataTipRows = [dataTipTextRow('Threshold', 'XData', '%.2f dB'); dataTipTextRow('Coverage', 'YData', '%.2f %%')];
            node = uitreenode(parent, 'Text', [icon ' ' label], 'NodeData', struct('kind', "job", 'id', id, 'label', label, 'T', T(:), 'cov', cov(:), 'Line', h, 'Query', gobjects(0)));
            expand(parent); app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node];
        end

        function covRefresh(app)
            %COVREFRESH Visibility of curves/queries, the union table, the legend and the enable state after any check/uncheck.
            jobs = app.covJobs(); on = app.isChecked(jobs); checked = jobs(on);
            for i = 1:numel(jobs), d = jobs(i).NodeData; set([d.Line; d.Query(isgraphics(d.Query))], 'Visible', on(i)); end
            if isempty(checked)
                app.Cov_Tabel.Data = table(); legend(app.Cov_Axes, 'off');
            else
                Tu = unique(cell2mat(arrayfun(@(n) n.NodeData.T, checked, 'UniformOutput', false)));
                vals = [Tu, cell2mat(arrayfun(@(n) cov_at(n.NodeData, Tu), checked.', 'UniformOutput', false))];
                names = [{'Threshold (dB)'}, arrayfun(@(n) [char(n.NodeData.label) ' %'], checked.', 'UniformOutput', false)];
                app.Cov_Tabel.Data = array2table(compose('%.2f', vals), 'VariableNames', names);
                hl = arrayfun(@(n) n.NodeData.Line, checked, 'UniformOutput', false);
                legend(app.Cov_Axes, [hl{:}], arrayfun(@(n) n.NodeData.label, checked, 'UniformOutput', false), 'Location', 'southwest', 'Interpreter', 'none');
            end
            app.applyVisibility();
        end

        function covSelect(app)
            %COVSELECT Tree selection: component items + threshold preset for the target pattern, line highlight, status.
            sel = app.Cov_Tree.SelectedNodes; jobs = app.covJobs();
            for n = jobs(:).', d = n.NodeData; d.Line.LineWidth = 1.6 + 1.0*(~isempty(sel) && n == sel(1)); end
            node = app.covTarget();
            if ~isempty(node)
                e = app.Pats(node.NodeData.k); [names, labels] = app.componentItems(e.Derived.Cols, e.Pattern.IsGainOnly);
                app.setItems(app.Cov_DropDown_Component, labels, names, 'E_Total_dB'); c = app.readCoverageConfig();
                key = sprintf('%d|%s|%d', node.NodeData.k, c.Component, e.Pattern.Revision);
                if app.CovPresetKey ~= key, app.CovPresetKey = key; app.Range.Auto.cov = true; end
                if app.Range.Auto.cov
                    K = apat_const(); pk = met_peak(e.Derived.Cols.(c.Component), e.Geometry.PhiPeriodic, K.PeakExcessDB);
                    app.applyRange("cov", util_presetRange(pk.value), "set");
                end
                if isfield(e.Source.Meta, 'TextFormat'), app.Cov_DropDown_TextFormat.Value = char(e.Source.Meta.TextFormat); end
                app.covOrientation();
            end
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(app.Cov_StatusBar, 'Ready.', false);
            else
                d = sel(1).NodeData;
                switch d.kind
                    case "job"
                        t50 = thr_at(d, 50); [mx, im] = max(d.cov); txt = sprintf('%s | max <b>%s%%</b> @ <b>%s dB</b>', d.label, util_fmt(mx), util_fmt(d.T(im)));
                        if isfinite(t50), txt = sprintf('%s | 50%%-coverage threshold <b>%s dB</b>', txt, util_fmt(t50)); end
                    case "results", txt = sprintf('Results <b>"%s"</b> — <b>%d</b> curve(s).', d.name, numel(sel(1).Children));
                    otherwise,      txt = sprintf('Pattern <b>"%s"</b> — <b>%d</b> coverage job(s).', app.Pats(d.k).Name, numel(sel(1).Children));
                end
                app.setStatus(app.Cov_StatusBar, txt, false);
            end
            app.applyVisibility();
        end

        function covOrientation(app)
            %COVORIENTATION Auto → cone centre from the target's boresight; an explicit axis sets the centre spinners.
            node = app.covTarget(); if isempty(node), return; end
            K = apat_const(); A = K.Axes; i = app.Cov_DropDown_Orientation.Value; if i == 0, i = app.Pats(node.NodeData.k).Derived.Boresight; end
            app.Cov_Spinner_ConeTH.Value = A.theta(i); app.Cov_Spinner_ConePH.Value = A.phi(i);
        end

        function lbl = coneLabel(~, th, ph)
            %CONELABEL Principal-axis name when the centre is one, otherwise the coordinates.
            K = apat_const(); A = K.Axes; v = [sind(th)*cosd(ph), sind(th)*sind(ph), cosd(th)];
            ax = [sind(A.theta(:)).*cosd(A.phi(:)), sind(A.theta(:)).*sind(A.phi(:)), cosd(A.theta(:))];
            i = find(ax*v.' >= 1 - 1e-9, 1);
            if isempty(i), lbl = sprintf('θ=%s°, φ=%s°', util_fmt(th), util_fmt(ph)); else, lbl = A.labels{i}; end
        end

        function covQuery(app, mode)
            %COVQUERY "Coverage at T" (cov_at) or "Threshold at c %" (thr_at) on the checked jobs under the selection; one datatip each (D74).
            c = app.readCoverageConfig(); sel = app.Cov_Tree.SelectedNodes; ax = app.Cov_Axes;
            if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to query.', true); return; end
            jobs = app.covJobs(sel); jobs = jobs(app.isChecked(jobs)); hit = false;
            for n = jobs(:).'
                d = n.NodeData; delete(d.Query(isgraphics(d.Query)));
                if mode == "cov", x = c.QueryT; y = cov_at(d, x); else, y = c.QueryC; x = thr_at(d, y); end
                if ~isfinite(x) || ~isfinite(y), continue; end
                q = gobjects(3, 1); col = d.Line.Color;
                q(1) = line(ax, [x x], [ax.YLim(1) y], 'Color', col, 'LineStyle', ':', 'HandleVisibility', 'off');
                q(2) = line(ax, [ax.XLim(1) x], [y y], 'Color', col, 'LineStyle', ':', 'HandleVisibility', 'off');
                q(3) = datatip(d.Line, x, y, 'SnapToDataVertex', 'off', 'FontSize', 9);
                d.Query = q; n.NodeData = d; hit = true;
            end
            if ~hit, app.setStatus(app.Cov_StatusBar, 'Query value is outside the checked curves.', true);
            elseif mode == "cov", app.setStatus(app.Cov_StatusBar, sprintf('Coverage queried at %s dB.', util_fmt(c.QueryT)), false);
            else, app.setStatus(app.Cov_StatusBar, sprintf('Threshold queried at %s%% coverage.', util_fmt(c.QueryC)), false);
            end
        end

        function covClear(app)
            %COVCLEAR Query artefacts and user datatips of the jobs under the selection (the one findobj in the app, I11).
            sel = app.Cov_Tree.SelectedNodes; if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to clear.', true); return; end
            jobs = app.covJobs(sel);
            for n = jobs(:).'
                d = n.NodeData; delete(d.Query(isgraphics(d.Query))); d.Query = gobjects(0); n.NodeData = d; delete(findobj(d.Line, 'Type', 'datatip'));
            end
            app.setStatus(app.Cov_StatusBar, 'Selected DataTips and query markers cleared.', true);
        end

        function covReset(app)
            jobs = app.covJobs();
            for n = jobs(:).', d = n.NodeData; delete(d.Query(isgraphics(d.Query))); delete(d.Line); end
            delete(app.Cov_TreeNode_Results.Children); legend(app.Cov_Axes, 'off'); app.Cov_Tabel.Data = table(); app.CovRunID = 0; app.CovPresetKey = "";
            if app.Main > 0, app.Pats = app.Pats(app.Main); app.Main = 1; else, app.Pats(:) = []; end       % keep only the Main entry
            app.Range.Auto.cov = true; app.Range.Auto.covX = true; app.applyRange("covX", [-40 10], "set"); app.Cov_Axes.XLimMode = 'auto';
            app.applyVisibility(); app.setStatus(app.Cov_StatusBar, 'Coverage workspace reset 🔄', true);
        end
    end

    methods (Access = private)   % ================= F. EXPORT =================

        function exportResults(app)
            if app.Main == 0, return; end
            e = app.Pats(app.Main); [~, base] = fileparts(e.Path);
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Results', fullfile(fileparts(e.Path), [base '_APAT_results.csv']));
            if isequal(f, 0), return; end
            app.writeTable(app.resultsTable(), fullfile(p, f)); app.setStatus(app.Single_StatusBar, ['Results exported to <b>' fullfile(p, f) '</b>'], true);
        end

        function exportCut(app)
            if app.Main == 0, return; end
            e = app.Pats(app.Main); [~, base] = fileparts(e.Path); cut = app.currentCut();
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, 'Export Cut', fullfile(fileparts(e.Path), [base '_cut.csv']));
            if isequal(f, 0), return; end
            [a, Y] = util_circle(cut.angle, cut.y, app.View.SignedPhi, cut.closed);
            app.writeTable(array2table([a, Y], 'VariableNames', [{'Angle_deg'}, cellstr(cut.cols)]), fullfile(p, f));
            app.setStatus(app.Single_StatusBar, sprintf('Cut (%s = %g°) exported to <b>%s</b>', cut.symbol, cut.fixed, fullfile(p, f)), true);
        end

        function exportUAN(app)
            %EXPORTUAN Canonical XGTD UAN: φ ∈ [0,360) plus closing column, fields at the current loss, maximum_gain = total-gain peak (D29).
            if app.Main == 0, return; end
            e = app.Pats(app.Main); P = e.Pattern; [~, base] = fileparts(e.Path);
            if P.IsGainOnly, uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            s = 10^(e.Params.L/20); ph = P.Phi(:); Eth = P.Eth*s; Eph = P.Eph*s;
            if e.Geometry.PhiPeriodic, ph(end+1) = ph(1) + 360; Eth(:, end+1) = Eth(:, 1); Eph(:, end+1) = Eph(:, 1); end
            [TH, PH] = ndgrid(P.Theta, ph); dB = @(E) round(20*log10(max(abs(E(:)), eps)), 5); dg = @(E) round(rad2deg(angle(E(:))), 5);
            T = sortrows(table(TH(:), PH(:), dB(Eth), dB(Eph), dg(Eth), dg(Eph), 'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'}), {'Phi', 'Theta'});
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, ...
                'Export UAN / E-field data', fullfile(fileparts(e.Path), sprintf('%s_%.5f_%gdeg.uan', base, e.Derived.Peak.value, P.dTheta)));
            if isequal(f, 0), return; end
            fp = fullfile(p, f);
            if endsWith(fp, '.uan', 'IgnoreCase', true)
                hdr = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\ncomplex\nmag_phase\n' ...
                    'pattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                    ph(1), ph(end), P.dPhi, P.Theta(1), P.Theta(end), P.dTheta, e.Derived.Peak.value);
                writelines(hdr, fp); writetable(T, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
            else
                app.writeTable(T, fp);
            end
            app.setStatus(app.Single_StatusBar, ['UAN exported to <b>' fp '</b>'], true);
        end

        function exportCoverage(app)
            if isempty(app.Cov_Tabel.Data), return; end
            folder = pwd; if app.Main > 0, folder = fileparts(app.Pats(app.Main).Path); end
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Coverage Results', fullfile(folder, 'coverage_results.csv'));
            if isequal(f, 0), return; end
            app.writeTable(app.Cov_Tabel.Data, fullfile(p, f)); app.setStatus(app.Cov_StatusBar, ['Coverage results exported to ' fullfile(p, f)], true);
        end

        function writeTable(~, T, fp)
            if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
        end
    end

    methods (Access = private)   % ================= G. LAYOUT (declarative; same widgets, names, parents, rows, columns, defaults as M7) =================

        function h = place(~, ctor, parent, row, col, varargin)
            h = ctor(parent, varargin{:}); h.Layout.Row = row; h.Layout.Column = col;
        end

        function [lbl, h] = labelled(app, parent, text, row, lcol, ccol, ctor, varargin)
            lbl = app.place(@uilabel, parent, row, lcol, 'Text', text, 'HorizontalAlignment', 'right');
            h = app.place(ctor, parent, row, ccol, varargin{:});
        end

        function [tab, g, ax, sl, mn, mx] = patternTab(app, group, ttl, axesTitle, needsAxes)
            tab = uitab(group, 'Title', ttl); g = uigridlayout(tab, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'}); ax = [];
            if needsAxes
                ax = app.place(@uiaxes, g, [1 3], 2, 'XLim', [0 360], 'YLim', [0 180], 'YDir', 'reverse', 'XTick', 0:30:360, 'YTick', 0:15:180, 'Box', 'on');
                title(ax, axesTitle); xlabel(ax, 'Phi (degree)'); ylabel(ax, 'Theta (degree)'); zlabel(ax, 'Z'); colormap(ax, 'jet');
            end
            sl = app.place(@(p, varargin) uislider(p, 'range', varargin{:}), g, 2, 1, 'Limits', [-250 100], 'Value', [-250 100], 'Orientation', 'vertical', 'Step', 1);
            mx = app.place(@uispinner, g, 1, 1, 'Limits', [-250 100], 'Value', 100, 'Step', 5);
            mn = app.place(@uispinner, g, 3, 1, 'Limits', [-250 100], 'Value', -250, 'Step', 5);
        end

        function dd = formatDropdown(~, parent, cb)
            dd = uidropdown(parent, 'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
                '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'}, 'Value', 'gain', ...
                'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'ValueChangedFcn', cb);
        end

        function createComponents(app)
            K = apat_const(); pl = @app.place; lb = @app.labelled; cb = @(scope, varargin) @(~, ~) app.on(scope, varargin{:});
            push = @uibutton; state = @(p, varargin) uibutton(p, 'state', varargin{:}); sw = @(p, varargin) uiswitch(p, 'slider', varargin{:});
            rslider = @(p, varargin) uislider(p, 'range', varargin{:}); pad = @(n) repmat(char(160), 1, n); bg = [0.9412 0.9412 0.9412];
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' K.ReleaseName], 'Visible', 'off', 'Position', [100 100 1136 739], 'WindowState', 'maximized', ...
                'CloseRequestFcn', @(~, ~) app.closeRequest());
            app.GridLayout = uigridlayout(app.UIFigure, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.TabGroup = pl(@uitabgroup, app.GridLayout, 1, 1);
            % ---------------- Tab 1: Process Pattern
            app.Tab1_Single = uitab(app.TabGroup, 'Title', 'Process Pattern 📡');
            app.Single_Grid = uigridlayout(app.Tab1_Single, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});
            app.Single_Panel_fullPattern = pl(@uipanel, app.Single_Grid, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'Visible', 'off', 'BackgroundColor', bg, 'FontWeight', 'bold');
            app.Single_gridPanel_full = uigridlayout(app.Single_Panel_fullPattern, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_tabPlots = pl(@uitabgroup, app.Single_gridPanel_full, 1, 1, 'SelectionChangedFcn', cb("view"));
            [app.Single_tabContour, app.Single_gridContour, app.Single_Axes_Ctr, app.Range_Ctr, app.Range_Ctr_Min, app.Range_Ctr_Max] = app.patternTab(app.Single_tabPlots, 'Contour Plot', 'Antenna Gain Pattern', true);
            [app.Single_tabCircular, app.Single_gridCircular, ~, app.Range_Cir, app.Range_Cir_Min, app.Range_Cir_Max] = app.patternTab(app.Single_tabPlots, 'Circular Contour Plot', '', false);
            [app.Single_tab3DSpherical, app.Single_grid3dSpherical, app.Single_Axes_3dSph, app.Range_3dSph, app.Range_3dSph_Min, app.Range_3dSph_Max] = app.patternTab(app.Single_tabPlots, '3D Spherical Plot', '3D Spherical Plot', true);
            [app.Single_tab3DPolar, app.Single_grid3dPolar, app.Single_Axes_3dPol, app.Range_3dPol, app.Range_3dPol_Min, app.Range_3dPol_Max] = app.patternTab(app.Single_tabPlots, '3D Polar Plot', '3D Polar Plot', true);
            [app.Single_tab3DRect, app.Single_grid3dRect, app.Single_Axes_3dRect, app.Range_3dRect, app.Range_3dRect_Min, app.Range_3dRect_Max] = app.patternTab(app.Single_tabPlots, '3D Surface Plot', '3D Surface (Rectangular) Plot', true);
            app.Single_Panel_Rect = pl(@uipanel, app.Single_Grid, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'Visible', 'off', 'BackgroundColor', bg, 'FontWeight', 'bold');
            app.Single_gridPanel_Cut = uigridlayout(app.Single_Panel_Rect, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_tabCut = pl(@uitabgroup, app.Single_gridPanel_Cut, 1, 1, 'SelectionChangedFcn', cb("view"));
            app.Single_tabPolarPlot = uitab(app.Single_tabCut, 'Title', 'Polar Cut Plot');
            app.Single_Grid_Polar = uigridlayout(app.Single_tabPolarPlot, 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            app.Range_Cut = pl(rslider, app.Single_Grid_Polar, [2 3], 1, 'Limits', [-250 100], 'Orientation', 'vertical', 'Step', 1, 'Value', [-250 100], 'ValueChangedFcn', @(s, ~) app.on("range", {"cut", s.Value, "slide"}));
            app.Button_HPBW = pl(state, app.Single_Grid_Polar, 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'IconAlignment', 'center', 'ValueChangedFcn', cb("view"));
            app.Label_HPBW = pl(@uilabel, app.Single_Grid_Polar, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            app.Range_Cut_Min = pl(@uispinner, app.Single_Grid_Polar, 4, 1, 'Step', 5, 'Limits', [-250 100], 'Value', -250, 'ValueChangedFcn', @(s, ~) app.on("range", {"cut", [s.Value app.Range.cut(2)], "spin"}));
            app.Range_Cut_Max = pl(@uispinner, app.Single_Grid_Polar, 1, 1, 'Step', 5, 'Limits', [-250 100], 'Value', 100, 'ValueChangedFcn', @(s, ~) app.on("range", {"cut", [app.Range.cut(1) s.Value], "spin"}));
            app.Button_ExportCut = pl(push, app.Single_Grid_Polar, 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', cb("exportCut"));
            app.Single_gridEcut = pl(@uigridlayout, app.Single_Grid_Polar, 3, 4, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x', '1x', '1x'});
            app.CheckBox_Et = pl(@uicheckbox, app.Single_gridEcut, 1, 1, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', cb("view"));
            app.CheckBox_Er = pl(@uicheckbox, app.Single_gridEcut, 2, 1, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', cb("view"));
            app.CheckBox_El = pl(@uicheckbox, app.Single_gridEcut, 3, 1, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', cb("view"));
            app.Single_tabRectPlot = uitab(app.Single_tabCut, 'Title', 'Rectangular Cut Plot');
            app.Single_gridRect = uigridlayout(app.Single_tabRectPlot);
            app.Single_AxesRect = pl(@uiaxes, app.Single_gridRect, [1 2], [1 2], 'XLim', [0 180], 'XTick', 0:15:180, 'Box', 'on');
            xlabel(app.Single_AxesRect, 'Theta (degree)'); ylabel(app.Single_AxesRect, 'Magnitude (dB)'); zlabel(app.Single_AxesRect, 'Z');
            app.Single_DropDown_output = pl(@uidropdown, app.Single_Grid, 3, [13 14], 'Items', {'Select Output:'}, 'Value', 'Select Output:', 'Visible', 'off', 'ValueChangedFcn', cb("filter"));
            app.Single_tabData = pl(@uitabgroup, app.Single_Grid, 4, [1 14], 'Visible', 'off', 'SelectionChangedFcn', cb("view"));
            app.Single_tabDataOut = uitab(app.Single_tabData, 'Title', 'Results 📤', 'ButtonDownFcn', @(~, ~) set(app.Single_DropDown_output, 'Visible', 'on'));
            app.Single_gridDataOut = uigridlayout(app.Single_tabDataOut, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_DataOut = pl(@uitable, app.Single_gridDataOut, 1, 1, 'BackgroundColor', [1 1 1], 'ColumnWidth', '1x', 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true, 'Visible', 'off');
            app.Single_tabDataIn = uitab(app.Single_tabData, 'Title', 'Input 📥');
            app.Single_gridDataIn = uigridlayout(app.Single_tabDataIn, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_DataIn = pl(@uitable, app.Single_gridDataIn, 1, 1, 'BackgroundColor', [1 1 1], 'ColumnName', {'Theta'; 'Phi'; 'E-TH-DB'; 'E-PH-DB'; 'E-TH-DG'; 'E-PH-DG'}, ...
                'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true, 'Visible', 'off');
            app.MetadataTab = uitab(app.Single_tabData, 'Title', 'Metadata 📋');
            app.Single_gridMetadata = uigridlayout(app.MetadataTab, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_metadata = pl(@uitable, app.Single_gridMetadata, 1, 1, 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            % ---- plot control panel
            app.Single_Panel_plotControl = pl(@uipanel, app.Single_Grid, 2, [13 14], 'Title', 'Plot Control 🎨', 'Visible', 'off');
            g = uigridlayout(app.Single_Panel_plotControl, 'RowHeight', repmat({'fit'}, 1, 15)); app.Single_gridPanel_Ctrl = g;
            [app.ComponentLabel, app.Single_DropDown_Component] = lb(g, 'Component', 1, 1, 2, @uidropdown, 'Items', {'Total Gain', 'Etheta Gain', 'Ephi  Gain', 'RHCP Gain', 'LHCP  Gain', 'Axial Ratio', 'Polarized Gain'}, ...
                'ItemsData', {'E_Total_dB', 'E_TH_dB', 'E_PH_dB', 'E_RCP_dB', 'E_LCP_dB', 'AR_dB', 'Gain_PolCorrected_dB'}, 'Value', 'E_Total_dB', 'ValueChangedFcn', cb("view"));
            [app.CuttypeDropDownLabel, app.Single_DropDown_cutType] = lb(g, 'Cut type', 2, 1, 2, @uidropdown, 'Items', {'Phi', 'Theta'}, 'Value', 'Phi', 'ValueChangedFcn', cb("view"));
            [app.CutvalueSpinnerLabel, app.Single_DropDown_cutValue] = lb(g, 'Cut value', 3, 1, 2, @uispinner, 'Limits', [0 360], 'Value', 0, 'ValueChangedFcn', cb("view"));
            [~, app.CutFieldBasisDropDown] = lb(g, 'Cut fields', 4, 1, 2, @uidropdown, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Value', 'Circular', 'Enable', 'off', ...
                'ValueChangedFcn', @(~, ~) app.basisPicked());
            [app.ColorbarmaxLabel, app.Single_Plot_Cmax] = lb(g, 'Colorbar max', 5, 1, 2, @uispinner, 'Limits', [-250 100], 'Value', 100, 'ValueChangedFcn', @(s, ~) app.on("range", {"all", [app.Single_Plot_Cmin.Value s.Value], "spin"}));
            [app.ColorbarminLabel, app.Single_Plot_Cmin] = lb(g, 'Colorbar min', 6, 1, 2, @uispinner, 'Limits', [-250 100], 'Value', -250, 'ValueChangedFcn', @(s, ~) app.on("range", {"all", [s.Value app.Single_Plot_Cmax.Value], "spin"}));
            [app.ColorbarstepLabel, app.Single_Plot_Cstep] = lb(g, 'Colorbar step', 7, 1, 2, @uispinner, 'Limits', [0.1 100], 'ValueChangedFcn', cb("view"));
            [app.Single_Label_Clim, app.Single_Button_Clim] = lb(g, 'Adjust Colorbar', 8, 1, 2, push, 'Text', 'Apply', 'Tooltip', 'Apply to full-pattern plots; gain-cut limits remain independent for AR.', ...
                'ButtonPushedFcn', @(~, ~) app.on("range", {"all", [app.Single_Plot_Cmin.Value app.Single_Plot_Cmax.Value], "set"}));
            [app.View3DLabel, app.Single_DropDown_3DView] = lb(g, '3D view', 9, 1, 2, @uidropdown, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Value', 'iso', 'Tooltip', 'Camera direction for the 3D pattern tabs.', 'ValueChangedFcn', cb("camera"));
            app.Single_Switch_AngularSpan = pl(sw, g, 10, [1 2], 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'Value', '0° to 360°', 'ValueChangedFcn', cb("view"));
            app.Single_Switch_ThetaSpan = pl(sw, g, 11, [1 2], 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'Value', '0° to 180°', 'ValueChangedFcn', cb("view"));
            app.Single_Switch_EHplane = pl(sw, g, 12, [1 2], 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'Value', 'E-Plane cut', 'ValueChangedFcn', cb("plane"));
            app.Singel_CheckBox_overlayCut = pl(@uicheckbox, g, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', cb("view"));
            app.Single_CheckBox_POB = pl(@uicheckbox, g, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', cb("view"));
            app.Single_CheckBox_HPBWBounds = pl(@uicheckbox, g, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', cb("view"));
            app.Single_StatusBar = pl(@uilabel, app.Single_Grid, 5, [1 14], 'Interpreter', 'html', 'Text', 'Ready 🚀', 'Tag', 'Main');
            % ---- inputs & parameters panel
            app.Single_panelParam = pl(@uipanel, app.Single_Grid, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️');
            g = uigridlayout(app.Single_panelParam, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'}); app.Single_gridPanel_Param = g;
            [app.InputPatternLabel, app.Single_EditField_Path] = lb(g, 'Input Pattern:', 1, 1, [2 8], @(p, varargin) uieditfield(p, 'text', varargin{:}));
            [app.FFDFreqDropDownLabel, app.Single_DropDown_FFD] = lb(g, 'FFD Freq:', 1, 9, 10, @uidropdown, 'Items', {'Frequencies'}, 'Value', 'Frequencies', 'Enable', 'off', 'ValueChangedFcn', cb("freq"));
            app.FFDFreqDropDownLabel.Enable = 'off';
            app.Single_Button_Load = pl(push, g, 1, [11 12], 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.on("load", app.Single_EditField_Path.Value));
            app.Single_Button_Process = pl(push, g, 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', cb("process"));
            app.Single_Button_ResetParams = pl(push, g, 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', cb("reset"));
            app.TextFormatLabel = pl(@uilabel, g, 2, [4 5], 'Text', 'Format:', 'HorizontalAlignment', 'right', 'Visible', 'off');
            app.Single_DropDown_TextFormat = pl(@(p, varargin) app.formatDropdown(p, varargin{:}), g, 2, [6 8], cb("process"));
            app.Single_DropDown_step = pl(@uidropdown, g, 2, [9 10], 'Items', {'STEP', 'STEP: 1'}, 'Value', 'STEP', 'Enable', 'off', 'Visible', 'off', 'Placeholder', 'STEP', 'ValueChangedFcn', cb("step"));
            app.Single_Export_Output = pl(push, g, 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb("export"));
            app.Single_Export_UAN = pl(push, g, 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb("exportUAN"));
            [app.RxPolLabel, app.Single_DropDown_RxPol] = lb(g, 'Rw Sense', 3, 1, 2, @uidropdown, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Editable', 'on', 'Value', 'Auto', 'Visible', 'off');
            [app.IncidentWaveARRwPLFLabel, app.Single_Spinner_Rw] = lb(g, 'Rw (dB)', 3, 3, 4, @uispinner, 'Value', 6, 'Visible', 'off');
            [app.LossindBLabel, app.Single_Spinner_Loss] = lb(g, 'Loss (−) / Gain (+) dB', 3, 5, 6, @uispinner, 'Step', 0.1, 'Visible', 'off');
            [app.TransmitPowerLabel, app.Single_Spinner_Pt] = lb(g, 'Tx Pwr (Pt)', 3, 7, 8, @uispinner, 'Visible', 'off');
            app.Single_DropDown_Pt = pl(@uidropdown, g, 3, 9, 'Items', {'dBW', 'dBm', 'Watts'}, 'Value', 'dBW', 'Visible', 'off');
            [app.DistanceLabel, app.Single_Spinner_R] = lb(g, 'Distance', 3, 10, 11, @uispinner, 'Value', 1, 'Visible', 'off');
            app.Single_DropDown_R = pl(@uidropdown, g, 3, 12, 'Items', {'m', 'km'}, 'Value', 'm', 'Visible', 'off');
            app.Single_Button_Coverage = pl(push, g, 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb("toCov"));
            set([app.RxPolLabel, app.IncidentWaveARRwPLFLabel, app.LossindBLabel, app.TransmitPowerLabel, app.DistanceLabel], 'Visible', 'off');
            % ---------------- Tab 2: Compute Coverage
            app.Tab2_Coverage = uitab(app.TabGroup, 'Title', 'Compute Coverage 📈');
            app.Cov_Grid = uigridlayout(app.Tab2_Coverage, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            app.Cov_Panel_Param = pl(@uipanel, app.Cov_Grid, 1, [1 5], 'Title', 'Inputs & Parameters 🎛️');
            g = uigridlayout(app.Cov_Panel_Param, 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'}); app.Cov_gridPanel_Parm = g;
            app.Cov_ButtonGroup_CovType = pl(@uibuttongroup, g, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', cb("covView"));
            app.Cov_ButtonGroup_Btn_Spherical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            app.Cov_ButtonGroup_Btn_Conical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            [app.AntennaPatternEditFieldLabel, app.Cov_EditField_filePath] = lb(g, 'Antenna Pattern:', 1, 3, [4 8], @(p, varargin) uieditfield(p, 'text', varargin{:}));
            app.Cov_Button_Load = pl(push, g, 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', @(~, ~) app.on("covLoad", app.Cov_EditField_filePath.Value));
            app.Cov_Button_computeCov = pl(push, g, 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', cb("covRun"));
            [app.ThresholdMindBSpinnerLabel, app.Cov_Spinner_ThreshMin] = lb(g, 'Threshold  Min (dB):', 2, 3, 4, @uispinner, 'Value', -40, 'ValueChangedFcn', @(s, ~) app.on("range", {"cov", [s.Value app.Cov_Spinner_ThreshMax.Value], "spin"}));
            [app.ThresholdMaxdBSpinnerLabel, app.Cov_Spinner_ThreshMax] = lb(g, 'Threshold  Max (dB):', 2, 5, 6, @uispinner, 'Value', 10, 'ValueChangedFcn', @(s, ~) app.on("range", {"cov", [app.Cov_Spinner_ThreshMin.Value s.Value], "spin"}));
            [app.StepdBSpinnerLabel, app.Cov_Spinner_Step] = lb(g, 'Step (dB):', 2, 7, 8, @uispinner, 'Value', 1);
            app.Cov_Button_Reset = pl(push, g, 2, 9, 'Text', '🔄 Reset', 'Enable', 'off', 'ButtonPushedFcn', cb("covReset"));
            app.Cov_Button_Export = pl(push, g, 2, 10, 'Text', '💾 Export Results', 'Enable', 'off', 'ButtonPushedFcn', cb("covExport"));
            [app.Cov_DropDown_OrientationLabel, app.Cov_DropDown_Orientation] = lb(g, 'Orientation 🧭:', 3, 1, 2, @uidropdown, 'Items', [{'Auto'}, K.Axes.labels], 'ItemsData', num2cell(0:6), 'Value', 0, 'Enable', 'off', 'ValueChangedFcn', cb("covView"));
            [app.ConeSpinnerLabel, app.Cov_Spinner_ConeTH] = lb(g, 'Cone θ₀ (°):', 3, 3, 4, @uispinner, 'Limits', [0 180], 'Enable', 'off');
            [app.ConeLabel, app.Cov_Spinner_ConePH] = lb(g, 'Cone φ₀ (°):', 3, 5, 6, @uispinner, 'Limits', [0 360], 'Enable', 'off');
            [app.ConeAngleLabel, app.Cov_Spinner_ConeAng] = lb(g, 'Cone Angle α (°):', 3, 7, 8, @uispinner, 'Limits', [0 180], 'Value', 45, 'Enable', 'off');
            app.Cov_Button_Clear = pl(push, g, 3, 9, 'Text', '🧹 Clear DataTips', 'Enable', 'off', 'ButtonPushedFcn', cb("covClear"));
            app.Cov_Button_toMain = pl(push, g, 3, 10, 'Text', '📊 To Main ◀ ', 'ButtonPushedFcn', @(~, ~) set(app.TabGroup, 'SelectedTab', app.Tab1_Single));
            [app.Cov_DropDown_ComponentLabel, app.Cov_DropDown_Component] = lb(g, 'Component:', 4, 1, 2, @uidropdown, 'Items', {'E_Total_dB'}, 'Value', 'E_Total_dB', 'Enable', 'off', 'ValueChangedFcn', cb("covSelect"));
            [app.Cov_QueryCoverageLabel, app.Cov_Spinner_queryCov] = lb(g, 'Coverage @ dB:', 4, 3, 4, @uispinner, 'ValueDisplayFormat', '%g dB', 'Visible', 'off');
            app.Cov_Button_queryCov = pl(push, g, 4, 5, 'Text', '⯐ Query Coverage', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', cb("covQuery", "cov"));
            [app.Cov_QueryThresholdLabel, app.Cov_Spinner_queryThresh] = lb(g, 'Threshold @ %:', 4, 6, 7, @uispinner, 'ValueDisplayFormat', '%g%%', 'Value', 50, 'Visible', 'off');
            app.Cov_Button_queryThresh = pl(push, g, 4, 8, 'Text', '🔍︎ Query Threshold', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', cb("covQuery", "thr"));
            app.Cov_TextFormatLabel = pl(@uilabel, g, 4, 9, 'Text', 'Format:', 'HorizontalAlignment', 'right');
            app.Cov_DropDown_TextFormat = pl(@(p, varargin) app.formatDropdown(p, varargin{:}), g, 4, 10, cb("covFormat"));
            set([app.Cov_DropDown_OrientationLabel, app.ConeSpinnerLabel, app.ConeLabel, app.ConeAngleLabel, app.Cov_DropDown_ComponentLabel], 'Enable', 'off');
            set([app.Cov_QueryCoverageLabel, app.Cov_QueryThresholdLabel], 'Visible', 'off');
            app.Cov_StatusBar = pl(@uilabel, app.Cov_Grid, 3, [1 5], 'Interpreter', 'html', 'Text', 'Ready 🚀', 'Tag', 'Cov');
            app.Cov_Panel_Results = pl(@uipanel, app.Cov_Grid, 2, [1 5], 'Title', 'Results', 'Visible', 'off');
            app.GridLayout2 = uigridlayout(app.Cov_Panel_Results, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            app.Cov_Axes = pl(@uiaxes, app.GridLayout2, 1, [2 4], 'XLimMode', 'auto', 'Interactions', dataTipInteraction);
            title(app.Cov_Axes, 'Coverage vs Threshold'); xlabel(app.Cov_Axes, 'Threshold (dB)'); ylabel(app.Cov_Axes, 'Coverage (%)'); zlabel(app.Cov_Axes, 'Z');
            app.Cov_Tree = pl(@(p, varargin) uitree(p, 'checkbox', varargin{:}), app.GridLayout2, [1 2], 1, 'SelectionChangedFcn', cb("covSelect"), 'CheckedNodesChangedFcn', cb("covCheck"));
            app.Cov_TreeNode_Results = uitreenode(app.Cov_Tree, 'Text', 'Coverage Results');
            app.Cov_Tabel = pl(@uitable, app.GridLayout2, [1 2], 5, 'ColumnWidth', '1x', 'RowName', {});
            app.Cov_Spinner_XRange = pl(rslider, app.GridLayout2, 2, 3, 'Limits', [-250 100], 'Value', [-40 10], 'ValueChangedFcn', @(s, ~) app.on("range", {"covX", s.Value, "slide"}), 'ValueChangingFcn', @(~, ev) app.on("range", {"covX", ev.Value, "slide"}));
            app.Cov_Spinner_XMax = pl(@uispinner, app.GridLayout2, 2, 4, 'Editable', 'on', 'Limits', [-250 100], 'Value', 10, 'ValueChangedFcn', @(s, ~) app.on("range", {"covX", [app.Cov_Spinner_XMin.Value s.Value], "spin"}));
            app.Cov_Spinner_XMin = pl(@uispinner, app.GridLayout2, 2, 2, 'Editable', 'on', 'Limits', [-250 100], 'Value', -40, 'ValueChangedFcn', @(s, ~) app.on("range", {"covX", [s.Value app.Cov_Spinner_XMax.Value], "spin"}));
            app.UIFigure.Visible = 'on';
        end

        function basisPicked(app), app.BasisAuto = false; app.on("view"); end
    end

    methods (Access = private)   % ================= H. LIFECYCLE =================

        function startupFcn(app)
            %STARTUPFCN Everything created once: polar axes, context menu, colorbars, triads, markers, cut lines, timer, defaults.
            app.Single_paxCut = polaraxes(app.Single_Grid_Polar); app.Single_paxCut.Layout.Row = [1 4]; app.Single_paxCut.Layout.Column = 3;
            app.Single_paxPattern = polaraxes(app.Single_gridCircular); app.Single_paxPattern.Layout.Row = [1 3]; app.Single_paxPattern.Layout.Column = 2;
            set([app.Single_paxCut, app.Single_paxPattern], 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'NextPlot', 'add');
            menu = uicontextmenu(app.UIFigure); app.Gfx.Menu = menu;
            uimenu(menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ev) app.deleteUserTips(ev));
            app.Gfx.Maps = struct('Gain', jet(256), 'AR', interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)));
            app.Gfx.InKey = ''; app.Gfx.OutKey = '';
            mk = {'Marker', 'o', 'MarkerSize', 5, 'MarkerEdgeColor', 'k', 'MarkerFaceColor', 'k', 'LineStyle', 'none', 'HandleVisibility', 'off', 'Visible', 'off', 'Clipping', 'off'};
            for k = 1:5
                ax = app.viewAxes(k); ax.ContextMenu = menu; enableDefaultInteractivity(ax);
                if k == 2, marker = polarplot(ax, NaN, NaN, mk{:}); else, marker = line(ax, NaN, NaN, NaN, mk{:}); end
                s = struct('Surface', gobjects(0), 'Marker', marker, 'Tip', gobjects(0), 'Overlay', gobjects(0), 'Colorbar', colorbar(ax), 'Key', '', 'HasPOB', false);
                if k >= 3
                    ax.Interactions = [rotateInteraction, dataTipInteraction];
                    s.Overlay = line(ax, NaN, NaN, NaN, 'Color', 'k', 'LineWidth', 1.6, 'HandleVisibility', 'off', 'Visible', 'off');
                elseif k == 1, ax.Interactions = [zoomInteraction, dataTipInteraction];
                end
                if k == 3 || k == 4
                    set(ax, 'XDir', 'normal', 'YDir', 'normal', 'ZDir', 'normal', 'Projection', 'orthographic', 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1]);
                    axis(ax, 'off'); app.drawTriad(ax);
                end
                app.Gfx.Full(k) = s;
            end
            app.Single_AxesRect.Interactions = [zoomInteraction, dataTipInteraction]; app.Single_AxesRect.ContextMenu = menu; app.Single_AxesRect.NextPlot = 'add';
            pax = app.Single_paxCut; rax = app.Single_AxesRect; c = struct('Key', '', 'HasPOB', false, 'HasHPBW', false, 'Regions', {{}});
            c.Polar = polarplot(pax, nan(2, 3), nan(2, 3), 'LineWidth', 1.4).'; c.Rect = plot(rax, nan(2, 3), nan(2, 3), 'LineWidth', 1.4).';
            c.POB = [polarplot(pax, NaN, NaN, mk{:}), line(rax, NaN, NaN, mk{:})]; c.POBTip = gobjects(1, 2);
            hb = {'Marker', 'o', 'Color', '#D95319', 'MarkerFaceColor', '#D95319', 'LineStyle', 'none', 'HandleVisibility', 'off', 'Visible', 'off'};
            c.HPBW = [polarplot(pax, NaN, NaN, hb{:}), polarplot(pax, NaN, NaN, hb{:}); line(rax, NaN, NaN, hb{:}), line(rax, NaN, NaN, hb{:})]; c.HPBWTip = gobjects(2, 2);
            app.Gfx.Cut = c;
            app.StatusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3);
            [app.Single_Plot_Cmax.Value, app.Single_Plot_Cmin.Value, app.Single_Plot_Cstep.Value, app.Single_Spinner_Pt.Value, app.Single_Spinner_R.Value, app.Single_Spinner_Rw.Value] = deal(10, -40, 5, 0, 1, 6);
            hold(app.Cov_Axes, 'on'); grid(app.Cov_Axes, 'on'); ylim(app.Cov_Axes, [0 100]); set(app.Cov_Axes, 'Box', 'on', 'Layer', 'top');
            app.Defaults = struct('Loss', app.Single_Spinner_Loss.Value, 'RxMode', app.Single_DropDown_RxPol.Value, 'RxAR', app.Single_Spinner_Rw.Value, 'Pt', app.Single_Spinner_Pt.Value, ...
                'PtUnit', app.Single_DropDown_Pt.Value, 'R', app.Single_Spinner_R.Value, 'RUnit', app.Single_DropDown_R.Value);
            app.Status = struct('Main', 'Ready -- load an antenna pattern file to begin 🚀', 'Cov', 'Ready -- load an antenna pattern file to begin 🚀');
            app.Single_StatusBar.Text = app.Status.Main; app.Cov_StatusBar.Text = app.Status.Cov;
            app.applyVisibility();
        end

        function drawTriad(~, ax)
            cols = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; lbls = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'}; d = 1.35*eye(3);
            for i = 1:3
                quiver3(ax, 0, 0, 0, d(i, 1), d(i, 2), d(i, 3), 0, 'Color', cols{i}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25, 'HandleVisibility', 'off');
                text(ax, 1.12*d(i, 1), 1.12*d(i, 2), 1.12*d(i, 3), lbls{i}, 'Color', cols{i}, 'FontWeight', 'bold');
            end
        end

        function deleteUserTips(~, ev)
            t = findobj(ancestor(ev.ContextObject, {'axes', 'polaraxes'}), 'Type', 'datatip'); delete(t(arrayfun(@(h) ~strcmp(h.Tag, 'APAT'), t)));
        end

        function shutdown(app)
            if app.isClosing, return; end
            app.isClosing = true;
            if ~isempty(app.StatusTimer) && isvalid(app.StatusTimer), stop(app.StatusTimer); delete(app.StatusTimer); end
            if ~isempty(app.Dialog) && isvalid(app.Dialog), delete(app.Dialog); end
            if isvalid(app.UIFigure), delete(app.UIFigure); end
        end
    end

    methods (Access = public)

        function app = APAT_v3_M8_4
            createComponents(app); registerApp(app, app.UIFigure); runStartupFcn(app, @startupFcn);
            if nargout == 0, clear app; end
        end

        function closeRequest(app), app.shutdown(); end

        function delete(app), app.shutdown(); end
    end
end

% ======================================================================================================================
%  B. CONSTANTS — every convention in one place (§15)
% ======================================================================================================================
function K = apat_const()
K.ReleaseName = 'APAT v3 Milestone 8'; K.ReleaseVersion = '3.0-M8';
K.PeakExcessDB = 6;                    % a sample is a spike iff it exceeds its 4 grid neighbours by more than this (I5)
K.ARLimits = [-30 30];                 % signed axial-ratio colour scale
K.Hard = [-250 100];                   % hard limits of every level range control
K.DistanceFloorM = 1e-12;
K.Axes = struct('labels', {{'+Z', '-Z', '+X', '-X', '+Y', '-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270]);   % right-handed principal axes
%          name                    label             kind      hidden-by-default in Results
K.Cols = {'E_Total_dB'             'Total Gain'      'gain'    false
          'E_TH_dB'                'Etheta Gain'     'gain'    true
          'E_PH_dB'                'Ephi Gain'       'gain'    true
          'E_RCP_dB'               'RHCP Gain'       'gain'    false
          'E_LCP_dB'               'LHCP Gain'       'gain'    false
          'AR_dB'                  'Axial Ratio'     'ar'      false
          'PLF_dB'                 'PLF'             'plf'     false
          'Gain_PolCorrected_dB'   'Polarized Gain'  'gain'    false
          'E_TH_Phase'             'Etheta Phase'    'phase'   true
          'E_PH_Phase'             'Ephi Phase'      'phase'   true
          'E_RCP_Phase'            'RHCP Phase'      'phase'   true
          'E_LCP_Phase'            'LHCP Phase'      'phase'   true
          'EIRP_dBW'               'EIRP'            'link'    true
          'PFD_Wm2'                'PFD'             'link'    true
          'E_RMS_Vm'               'E_RMS'           'link'    true};
%          name        axesProp              rangeProp       kind       default camera
K.Views = {'contour'   'Single_Axes_Ctr'     'Range_Ctr'     'pcolor'   []
           'circular'  'Single_paxPattern'   'Range_Cir'     'fisheye'  []
           'sphere3D'  'Single_Axes_3dSph'   'Range_3dSph'   'sphere'   [135 25]
           'polar3D'   'Single_Axes_3dPol'   'Range_3dPol'   'polar'    [135 25]
           'rect3D'    'Single_Axes_3dRect'  'Range_3dRect'  'rect'     [-35 35]};
end

% ======================================================================================================================
%  I. READERS — every reader returns a Source {Raw, Blocks{f} (long tables), Freqs, Meta}; every heuristic writes a Note
% ======================================================================================================================
function S = io_read(fp, fmt)
%IO_READ Dispatch by extension.  Blocks are long tables {Theta, Phi, Re_Eth, Im_Eth, Re_Eph, Im_Eph} or {Theta, Phi, gain columns}.
[~, ~, ext] = fileparts(fp); ext = lower(erase(ext, '.'));
switch ext
    case {'xlsx', 'xls'},                        S = io_excel(fp);
    case {'csv', 'txt', 'dat'},                  S = io_text(fp, string(fmt));
    case 'cut',                                  S = io_cut(fp);
    case {'uan', 'fz', 'out', 'ffd', 'ffe', 'ffs'}, S = io_field(fp, ext);
    otherwise, error('APAT:Unsupported', 'Unsupported file format: .%s', ext);
end
end

function S = io_source(raw, blocks, freqs, format, unit, gainOnly, notes)
%IO_SOURCE Source factory.  Meta.Unit is a static property of the format (§15-4): dBi (calibrated) or dB (relative field/gain).
if unit == "dBi", ul = "dBi"; elseif gainOnly, ul = "dB"; else, ul = "dB (rel. field)"; end
S = struct('Raw', raw, 'Blocks', {blocks}, 'Freqs', freqs, 'Meta', struct('Format', string(format), 'Unit', string(unit), 'UnitLabel', ul, ...
    'IsGainOnly', logical(gainOnly), 'IsCoverage', false, 'Notes', string(notes(:))));
end

function T = io_fieldTable(th, ph, Eth, Eph)
T = table(th(:), ph(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function [Eth, Eph] = io_fields(M, order, domain, basis)
%IO_FIELDS One converter for every six-column field layout (A.10).  order maps [θ φ a b c d] to file columns;
%   domain 'magphase' (a,b = |c1| dB, ∠c1 deg; c,d likewise) or 'rect' (a,b = Re,Im c1; c,d = Re,Im c2); basis = component meaning.
A = M(:, order(3:6));
if domain == "magphase", c1 = 10.^(A(:, 1)/20).*exp(1i*deg2rad(A(:, 2))); c2 = 10.^(A(:, 3)/20).*exp(1i*deg2rad(A(:, 4)));
else,                    c1 = complex(A(:, 1), A(:, 2));                    c2 = complex(A(:, 3), A(:, 4)); end
switch basis
    case "thetaphi", Eth = c1; Eph = c2;
    case "rcplcp",   [Eth, Eph] = pol_fromCircular(c1, c2);
    case "lcprcp",   [Eth, Eph] = pol_fromCircular(c2, c1);
end
end

function [nHdr, hdr, ffd] = io_headerLines(fp, minFields)
%IO_HEADERLINES Count leading non-data lines (first line with ≥ minFields numbers starts the data) and parse an HFSS FFD header.
fid = fopen(fp, 'r'); if fid < 0, error('APAT:Open', 'Cannot open file: %s', fp); end
c = onCleanup(@() fclose(fid)); nHdr = 0; hdr = strings(0, 1);
num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?'; pat = sprintf('^\\s*%s(?:[\\s,;]+%s){%d,}\\s*$', num, num, minFields - 1);
while true
    line = fgetl(fid); if ~ischar(line) || ~isempty(regexp(line, pat, 'once')), break; end
    nHdr = nHdr + 1; hdr(end+1, 1) = string(line); %#ok<AGROW>
end
ffd = struct('ok', false, 'freq', []); triples = zeros(0, 3);
for k = 1:numel(hdr)
    v = sscanf(hdr(k), '%f').'; if numel(v) == 3 && size(triples, 1) < 2, triples(end+1, :) = v; end %#ok<AGROW>
    t = regexp(strtrim(hdr(k)), '^frequenc\w*\s+(.+)$', 'tokens', 'once', 'ignorecase');
    if ~isempty(t), f = sscanf(t{1}, '%f'); if numel(f) > 1, ffd.freq = f(:); end, end                 % "Frequencies N" alone is only a count
end
if size(triples, 1) == 2 && all(triples(:, 3) >= 1)
    ffd.ok = true; ffd.theta = linspace(triples(1, 1), triples(1, 2), round(triples(1, 3))).'; ffd.phi = linspace(triples(2, 1), triples(2, 2), round(triples(2, 3))).';
end
end

function S = io_field(fp, ext)
%IO_FIELD UAN/FZ (XGTD), OUT (GRASP), FFS (CST), FFE (FEKO), FFD (HFSS): six-column field tables through io_fields; FFD/FFE keep blocks.
minFields = 6; if ext == "ffd", minFields = 4; end
[nHdr, hdr, ffd] = io_headerLines(fp, minFields);
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
if ext == "ffe", opts.CommentStyle = '#'; end
opts = setvartype(opts, 'double'); M = readmatrix(fp, opts); notes = strings(0, 1); freqs = NaN;
if ext == "ffd"
    assert(ffd.ok, 'APAT:FFDHeader', 'FFD header (theta/phi start, stop, count) not found.');
    sep = isnan(M(:, 1)); f = M(sep, 2); freqs = [ffd.freq; f(isfinite(f))].'; F = M(~sep, 1:4); F = F(~all(isnan(F), 2), :);
    th = repelem(ffd.theta, numel(ffd.phi)); ph = repmat(ffd.phi, numel(ffd.theta), 1); n = numel(th);
    assert(mod(size(F, 1), n) == 0, 'APAT:FFDRows', 'FFD row count does not match the theta/phi grid.');
    nb = size(F, 1)/n; freqs(end+1:nb) = NaN; freqs = freqs(1:nb);
    blocks = arrayfun(@(b) io_fieldTable(th, ph, complex(F((b-1)*n+(1:n), 1), F((b-1)*n+(1:n), 2)), complex(F((b-1)*n+(1:n), 3), F((b-1)*n+(1:n), 4))), 1:nb, 'UniformOutput', false);
    S = io_source(blocks{1}, blocks, freqs, "HFSS FFD", "dB", false, notes); return
end
M = M(~any(isnan(M(:, 1:6)), 2), 1:6);
switch ext
    case {'uan', 'fz'}
        h = lower(strjoin(hdr, newline));
        if contains(h, 'magnitude') && ~contains(h, 'magnitude db'), error('APAT:UnsupportedUAN', 'UAN magnitude must be in dB.'); end
        if contains(h, 'polarization') && ~contains(h, 'theta_phi'), error('APAT:UnsupportedUAN', 'UAN polarization must be theta_phi.'); end
        order = [1 2 3 5 4 6]; dom = "magphase"; basis = "thetaphi"; unit = "dBi"; raw = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}; fmt = "XGTD " + upper(ext);
    case 'out', order = 1:6; dom = "rect"; basis = "rcplcp";  unit = "dBi"; raw = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; fmt = "TICRA/GRASP OUT";
    case 'ffs', order = [2 1 3 4 5 6]; dom = "rect"; basis = "thetaphi"; unit = "dB"; raw = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; fmt = "CST FFS";
    case 'ffe', order = 1:6; dom = "rect"; basis = "thetaphi"; unit = "dB"; raw = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; fmt = "FEKO FFE";
end
[Eth, Eph] = io_fields(M, order, dom, basis); th = M(:, order(1)); ph = M(:, order(2)); blocks = {io_fieldTable(th, ph, Eth, Eph)};
if ext == "ffe"                                                                                       % multi-frequency blocks (D22)
    tok = regexp(fileread(fp), '#Frequency:\s*([-+0-9.eEdD]+)', 'tokens'); f = cellfun(@(t) str2double(t{1}), tok);
    nb = max(1, numel(f)); n = size(M, 1)/nb;
    if nb > 1 && n == round(n), blocks = arrayfun(@(b) blocks{1}((b-1)*n+(1:n), :), 1:nb, 'UniformOutput', false); freqs = f(:).'; end
end
S = io_source(array2table(M, 'VariableNames', raw), blocks, freqs, fmt, unit, false, notes);
end

function S = io_text(fp, fmt)
%IO_TEXT CSV/TXT/DAT: coverage-results table, gain-only table, or six-column E-field table by the selected format.
opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvartype(opts, 'double'); opts = setvaropts(opts, 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
T = readtable(fp, opts); names = string(T.Properties.VariableNames); low = lower(names); hasHdr = ~all(startsWith(names, "Var"));
assert(width(T) >= 2, 'APAT:TextColumns', 'File needs at least two numeric columns.');
T = T(all(isfinite(T{:, 1:2}), 2), :); assert(height(T) > 0, 'APAT:TextEmpty', 'No numeric rows found.');       % drop rows only on θ/φ (D24)
c1 = T{:, 1}; rest = T{:, 2:end};
keyword = contains(low(1), "threshold") || any(contains(low(2:end), "coverage"));
strict = ~hasHdr && width(T) < 6 && issorted(c1, 'strictascend') && all(rest(:) >= 0 & rest(:) <= 100) && all(diff(rest, 1, 1) <= 1e-9, 'all');
if keyword || strict                                                                                   % coverage results (D27)
    if ~hasHdr, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:width(T) - 1))]; end
    S = io_source(T, {}, NaN, "Coverage results", "dB", true, strings(0, 1)); S.Meta.IsCoverage = true; return
end
if fmt == "gain"
    it = find(contains(low, ["theta", "elev"]) | low == "th", 1); ip = find(contains(low, ["phi", "azim"]) | low == "ph", 1);
    if hasHdr && ~isempty(it) && ~isempty(ip)
        order = [it, ip, setdiff(1:width(T), [it ip])]; note = "θ/φ columns taken from the header names.";
    else
        order = 1:width(T); if max(c1) - min(c1) > max(T{:, 2}) - min(T{:, 2}), order(1:2) = [2 1]; end   % smaller span = θ (D25)
        note = sprintf("Column %d read as θ and column %d as φ (θ has the smaller span).", order(1), order(2));
    end
    B = T(:, order); B.Properties.VariableNames = [{'Theta', 'Phi'}, cellstr(matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(names(order(3:end))), {'Theta', 'Phi'}))];
    unit = "dB"; if any(contains(low, "dbi")), unit = "dBi"; end
    S = io_source(T, {B}, NaN, "Generic gain table", unit, true, note); S.Meta.TextFormat = fmt; return
end
assert(width(T) >= 6, 'APAT:TextColumns', 'The selected generic E-field format needs six numeric columns.');
M = T{:, 1:6}; mp = endsWith(fmt, "magphase"); order = 1:6; note = strings(0, 1);
if mp                                                                                                  % magnitude/phase layout (D26)
    isPh = contains(low(3:6), ["deg", "phase", "ang"]); byRange = max(abs(M(:, 3:6)), [], 1, 'omitnan') > 100;
    if hasHdr && nnz(isPh) == 2, ph = isPh; note = "Phase columns identified from the header names.";
    elseif nnz(byRange) == 2, ph = byRange; note = "Phase columns identified by range (|x| > 100).";
    else, error('APAT:TextLayout', 'Cannot tell magnitude from phase columns; add header names.'); end
    mag = find(~ph); phs = find(ph); order(3:6) = 2 + [mag(1), phs(1), mag(2), phs(2)];
end
if startsWith(fmt, "rcp"), basis = "rcplcp"; comp = ["POL1", "POL2"]; elseif startsWith(fmt, "lcp"), basis = "lcprcp"; comp = ["POL1", "POL2"]; else, basis = "thetaphi"; comp = ["E_TH", "E_PH"]; end
dom = "rect"; if mp, dom = "magphase"; end
[Eth, Eph] = io_fields(M, order, dom, basis);
if ~hasHdr
    if mp, suffix = ["_dB", "_deg"]; else, suffix = ["_real", "_imag"]; end
    gen = strings(1, 6); gen(1:2) = ["Theta", "Phi"]; gen(order(3:6)) = [comp(1) + suffix, comp(2) + suffix];
    T.Properties.VariableNames = cellstr(gen);
end
S = io_source(T, {io_fieldTable(M(:, 1), M(:, 2), Eth, Eph)}, NaN, "Generic text (" + fmt + ")", "dB", false, note); S.Meta.TextFormat = fmt;
end

function S = io_cut(fp)
%IO_CUT TICRA/GRASP .cut: blocks of [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data].  ICOMP 1 = θ/φ, 2 = RHCP/LHCP (D19).
L = readlines(fp); L(strlength(strtrim(L)) == 0) = []; k = 1; th = {}; ph = {}; D = {}; notes = strings(0, 1);
while k < numel(L)
    p = sscanf(L(k+1), '%f'); assert(numel(p) >= 7, 'APAT:CutHeader', 'Could not parse the GRASP cut parameter line.');
    nA = p(3); icomp = p(5); icut = p(6);
    if ~any(icomp == [1 2]), error('APAT:UnsupportedICOMP', 'GRASP cut ICOMP=%g is not supported (1 = linear θ/φ, 2 = RHCP/LHCP).', icomp); end
    B = reshape(sscanf(strjoin(L(k+2:k+1+nA), ' '), '%f'), 2*p(7), []).';
    th{end+1} = p(1) + (0:nA-1).'*p(2); ph{end+1} = repmat(p(4), nA, 1); D{end+1} = B(:, 1:4); k = k + 2 + nA; %#ok<AGROW>
end
th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:});
if icut == 2, [th, ph] = deal(ph, th); notes(end+1) = "ICUT = 2: φ swept, θ fixed per block."; end
neg = th < 0; ph(neg) = ph(neg) + 180; th(neg) = -th(neg);
if isscalar(unique(ph))                                                                                 % single cut → body of revolution (§15-5)
    reps = (0:10:350).'; n = numel(th); th = repmat(th, numel(reps), 1); ph = repelem(reps, n); D = repmat(D, numel(reps), 1);
    notes(end+1) = "Single φ cut: pattern synthesised as a body of revolution at 10° φ steps.";
end
c1 = complex(D(:, 1), D(:, 2)); c2 = complex(D(:, 3), D(:, 4));
if icomp == 2, [Eth, Eph] = pol_fromCircular(c1, c2); raw = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'};
else, Eth = c1; Eph = c2; raw = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; end
S = io_source(array2table([th, ph, D], 'VariableNames', raw), {io_fieldTable(th, ph, Eth, Eph)}, NaN, "TICRA/GRASP CUT", "dB", false, notes);
end

function S = io_excel(fp)
%IO_EXCEL Matrix-template workbooks: first sheet = summary; fixed component sheets (C3-origin matrices) for Eθ/Eφ and/or RHCP/LHCP.
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"]; lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
if hasL && hasC, fmt = "Excel Matrix Format 3 (Ercp/Elcp + Eth/Eph)"; req = [circ lin]; elseif hasL, fmt = "Excel Matrix Format 1 (Eth/Eph)"; req = lin;
elseif hasC, fmt = "Excel Matrix Format 2 (Ercp/Elcp)"; req = circ;
else, error('APAT:ExcelFormat', 'Unsupported workbook: the component sheets must be the fixed Eth/Eph and/or RHCP/LHCP names.'); end
Mx = struct(); th = []; ph = [];
for s = req
    [t, p, X] = io_excelSheet(fp, sheets(find(strcmpi(sheets, s), 1)));
    if isempty(th), th = t; ph = p; elseif ~isequal(size(t), size(th)) || any(abs(t - th) > 1e-9) || ~isequal(size(p), size(ph)) || any(abs(p - ph) > 1e-9)
        error('APAT:ExcelGrid', 'All Excel Matrix component sheets must use the same theta/phi grid.'); end
    Mx.(s) = X;
end
fld = @(g, d) 10.^(g/20).*exp(1i*deg2rad(d));
if hasL, Eth = fld(Mx.Etheta_Gain_dBi, Mx.Etheta_Phase_degrees); Eph = fld(Mx.Ephi_Gain_dBi, Mx.Ephi_Phase_degrees);
else,    [Eth, Eph] = pol_fromCircular(fld(Mx.RHCP_Gain_dBi, Mx.RHCP_Phase_degrees), fld(Mx.LHCP_Gain_dBi, Mx.LHCP_Phase_degrees)); end
[PH, TH] = meshgrid(ph, th); B = io_fieldTable(TH, PH, Eth, Eph); raw = B;
for s = req, raw.(s) = reshape(Mx.(s), [], 1); end
fMHz = xl_lookup(fp, sheets(1), 'Pattern Simulation Freq (MHz):'); freqs = NaN; if isfinite(fMHz), freqs = fMHz*1e6; end
S = io_source(raw, {B}, freqs, fmt, "dBi", false, strings(0, 1));
end

function [th, ph, X] = io_excelSheet(fp, sheet)
%IO_EXCELSHEET One C3-origin matrix: row 2 (C→) = φ, column B (3↓) = θ.  readcell keeps worksheet coordinates.
C = readcell(fp, 'Sheet', char(sheet)); isnum = @(x) isnumeric(x) && isscalar(x) && isfinite(x);
if size(C, 1) < 3 || size(C, 2) < 3, error('APAT:ExcelSheet', 'Sheet "%s" does not contain a C3-origin matrix.', sheet); end
pm = cellfun(isnum, C(2, 3:end)); tm = cellfun(isnum, C(3:end, 2)); np = find(~pm, 1) - 1; nt = find(~tm, 1) - 1;
if isempty(np), np = numel(pm); end, if isempty(nt), nt = numel(tm); end
if any(pm(np+1:end)) || any(tm(nt+1:end)) || np == 0 || nt == 0, error('APAT:ExcelAxis', 'Sheet "%s" has a gap or no numeric θ/φ axis.', sheet); end
ph = cell2mat(C(2, 2+(1:np))).'; th = cell2mat(C(2+(1:nt), 2)); D = C(2+(1:nt), 2+(1:np));
if ~all(cellfun(isnum, D), 'all'), error('APAT:ExcelSheet', 'Sheet "%s" contains non-numeric/missing samples.', sheet); end
X = cell2mat(D);
if any(diff(th) <= 0) || any(diff(ph) <= 0) || th(1) < -1e-9 || th(end) > 180 + 1e-9 || ph(1) < -1e-9 || ph(end) >= 360 + 1e-9
    error('APAT:ExcelAxis', 'Sheet "%s" needs strictly increasing axes with θ in [0,180] and φ in [0,360).', sheet);
end
end

function v = xl_lookup(fp, sheet, label)
%XL_LOOKUP Numeric value to the right of a labelled summary cell; NaN when absent (replaces the 164-line summary parser, D30).
v = NaN; C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70');
[r, c] = find(cellfun(@(x) (ischar(x) || isstring(x)) && strcmpi(strtrim(string(x)), label), C), 1);
if isempty(r), return; end
for k = c+1:size(C, 2), if isnumeric(C{r, k}) && isscalar(C{r, k}) && isfinite(C{r, k}), v = C{r, k}; return; end, end
end

% ======================================================================================================================
%  J. NUMERICAL CORE
% ======================================================================================================================
function P = pat_build(S, f)
%PAT_BUILD Canonical grid-native pattern (I1): polar θ ascending in [0,180], φ ascending in [0,360), uniform steps asserted once,
%   no seam column, angles snapped to 5 decimals, field values untouched (D03).
T = S.Blocks{min(f, numel(S.Blocks))}; th = double(T.Theta); ph = double(T.Phi); notes = strings(0, 1);
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, th = 90 - th; notes(end+1) = "θ read as elevation (−90..90°) and folded to polar θ = 90° − el (D28).";
    else, m = th < 0; th(m) = -th(m); ph(m) = ph(m) + 180; notes(end+1) = "Negative θ folded onto φ + 180°."; end
end
th = mod(th, 360); over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;
th = round(th, 5); ph = round(mod(ph, 360), 5); ph(ph >= 360) = 0;
[~, keep] = unique([ph th], 'rows', 'first'); th = th(keep); ph = ph(keep); T = T(keep, :);       % φ = 360 duplicates of φ = 0 vanish here
P.Theta = unique(th); P.Phi = unique(ph); n = numel(P.Theta); m = numel(P.Phi);
P.dTheta = util_assertUniform(P.Theta, 'θ'); P.dPhi = util_assertUniform(P.Phi, 'φ');
if isnan(P.dTheta), P.dTheta = 180; end, if isnan(P.dPhi), P.dPhi = 360; end
if n*m ~= numel(th), error('APAT:NonUniformGrid', 'Pattern is not a complete θ×φ grid: %d samples for %d × %d axes.', numel(th), n, m); end
lin = sub2ind([n m], round((th - P.Theta(1))/P.dTheta) + 1, round((ph - P.Phi(1))/P.dPhi) + 1);
toGrid = @(v) reshape(accumarray(lin, double(v), [n*m 1], [], NaN), n, m);                       % scatter by index arithmetic
P.IsGainOnly = S.Meta.IsGainOnly; P.G = struct(); P.Eth = []; P.Eph = [];
if P.IsGainOnly, for c = string(T.Properties.VariableNames(3:end)), P.G.(c) = toGrid(T.(c)); end
else, P.Eth = complex(toGrid(T.Re_Eth), toGrid(T.Im_Eth)); P.Eph = complex(toGrid(T.Re_Eph), toGrid(T.Im_Eph)); end
P.Freq = S.Freqs(min(f, numel(S.Freqs))); P.Revision = 1; P.Meta = S.Meta; P.Meta.Notes = [S.Meta.Notes(:); notes(:)];
end

function step = util_assertUniform(axis, name)
%UTIL_ASSERTUNIFORM Median step; error with the offending axis and gaps when the axis is not uniform (§15-1, D18).
d = diff(axis); step = median(d);
if numel(axis) > 1 && any(abs(d - step) > 1e-6)
    error('APAT:NonUniformGrid', '%s axis is not uniform: steps range %.6g°..%.6g° (APAT requires uniform grids).', name, min(d), max(d));
end
end

function P = pat_resample(P, step)
%PAT_RESAMPLE Exact decimation when step/native ∈ ℕ (D06); otherwise bilinear on the φ-closed grid, never outside the source domain (D05):
%   E-field per component as linear power + unit phasor (B.5, D04); gain-kind columns as linear power (D16); others linear.
kt = step/P.dTheta; kp = step/P.dPhi; periodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
if abs(kt - 1) < 1e-9 && abs(kp - 1) < 1e-9, return; end                                          % already at the requested step
if abs(kt - round(kt)) < 1e-9 && abs(kp - round(kp)) < 1e-9 && kt >= 1 && kp >= 1
    it = 1:round(kt):numel(P.Theta); ip = 1:round(kp):numel(P.Phi); f = @(X, ~) X(it, ip); t2 = P.Theta(it); p2 = P.Phi(ip);
    P.Meta.Notes(end+1) = sprintf("Decimated from %g° to %g° (exact).", max(P.dTheta, P.dPhi), step);
else
    t2 = (P.Theta(1):step:P.Theta(end) + 1e-9).'; pEnd = P.Phi(end); if periodic, pEnd = P.Phi(1) + 360 - step; end
    p2 = (P.Phi(1):step:pEnd + 1e-9).'; f = @(X, kind) pat_interp(P.Theta, P.Phi, X, t2, p2, kind, periodic);
    P.Meta.Notes(end+1) = sprintf("Resampled from %g° to %g° (bilinear; power + phasor for fields, linear power for gain).", max(P.dTheta, P.dPhi), step);
end
if P.IsGainOnly, for c = string(fieldnames(P.G)).', P.G.(c) = f(P.G.(c), util_colKind(c)); end
else, P.Eth = f(P.Eth, "field"); P.Eph = f(P.Eph, "field"); end
P.Theta = t2(:); P.Phi = p2(:); P.dTheta = step; P.dPhi = step; P.Revision = P.Revision + 1;
end

function Y = pat_interp(th, ph, X, t2, p2, kind, periodic)
%PAT_INTERP Bilinear interpolation of one quantity by kind: "field" (power + unit phasor), "gain" (linear power), else linear.
if periodic, ph = [ph(:); ph(1) + 360]; X = [X, X(:, 1)]; end
[PP, TT] = meshgrid(ph, th); [Q, R] = meshgrid(p2, t2); I = @(V) interp2(PP, TT, V, Q, R, 'linear');
switch kind
    case "field", Pw = I(abs(X).^2); U = I(X./max(abs(X), realmin)); Y = sqrt(Pw).*U./max(abs(U), realmin);
    case "gain",  Y = 10*log10(max(I(10.^(X/10)), realmin));
    otherwise,    Y = I(X);
end
end

function G = geo_build(P)
%GEO_BUILD Separable cell solid angles on the uniform grid (I2):
%   wθ(i) = cos(θᵢ − Δθ/2) − cos(θᵢ + Δθ/2) with edges clipped to [0°, 180°];  ΔΩ(i,j) = wθ(i)·Δφ  (Δφ in rad)
%   Full sphere: Σ wθ = cos 0° − cos 180° = 2 (telescoping) and nφ·Δφ = 2π  ⇒  Σ ΔΩ = 4π exactly (B.1).
lo = max(P.Theta(:) - P.dTheta/2, 0); hi = min(P.Theta(:) + P.dTheta/2, 180);
G.wTheta = cosd(lo) - cosd(hi); G.dPhi = deg2rad(P.dPhi);
G.PhiPeriodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
G.IsFullSphere = G.PhiPeriodic && lo(1) == 0 && hi(end) == 180;
G.dOmega = G.wTheta*G.dPhi*ones(1, numel(P.Phi)); G.Omega = sum(G.dOmega, 'all');
end

function cg = geo_cosGamma(P, thC, phC)
%GEO_COSGAMMA cos of the great-circle angle from (θc, φc) to every grid direction (spherical law of cosines), nθ×nφ.
cg = cosd(P.Theta(:))*cosd(thC) + sind(P.Theta(:))*sind(thC).*cosd(P.Phi(:).' - phC);
end

function M = geo_displayMap(P, G, V)
%GEO_DISPLAYMAP Column permutation and axis relabelling for the display convention; no data is copied or changed (I8, A.8).
n = numel(P.Phi); j0 = find(P.Phi >= 180, 1); perm = 1:n;
if V.SignedPhi && ~isempty(j0), perm = [j0:n, 1:j0-1]; end
M.ColIdx = perm; if G.PhiPeriodic, M.ColIdx(end+1) = perm(1); end                                 % closing column, display only
M.PhiAxis = P.Phi(perm); if V.SignedPhi, M.PhiAxis(M.PhiAxis >= 180) = M.PhiAxis(M.PhiAxis >= 180) - 360; end
if G.PhiPeriodic, M.PhiAxis(end+1) = M.PhiAxis(1) + 360; end
if V.Elevation, M.ThetaAxis = 90 - P.Theta; M.ThetaDir = 'normal'; M.ThetaLabel = "Elevation";
else,           M.ThetaAxis = P.Theta;      M.ThetaDir = 'reverse'; M.ThetaLabel = "Theta"; end
M.Key = sprintf('%d|%d', V.SignedPhi, V.Elevation);
end

function cut = geo_cut(P, cols, type, value, periodic)
%GEO_CUT One great-circle cut as an open circle in physical degrees.  Phi cut (fixed θ): the nearest row, angle = φ.
%   Theta cut (fixed φ): the nearest column and its opposite, angle = [θ; 360 − θ] with the poles not repeated.
%   cols is a cell of nθ×nφ matrices → cut.y is nA × numel(cols); cut.closed says whether the circle is complete.
n = numel(P.Theta);
if type == "Phi"
    [snap, i] = min(abs(P.Theta - value)); cut.fixed = P.Theta(i); cut.symbol = 'θ';
    rows = repmat(i, numel(P.Phi), 1); cix = (1:numel(P.Phi)).'; cut.angle = P.Phi(:); cut.closed = periodic;
else
    [snap, j] = min(abs(mod(P.Phi - value + 180, 360) - 180)); cut.fixed = P.Phi(j); cut.symbol = 'φ';
    [dOpp, j2] = min(abs(mod(P.Phi - cut.fixed, 360) - 180)); hasOpp = dOpp < 1e-6;
    back = (n:-1:1).'; back(P.Theta(back) >= 180 - 1e-9 | P.Theta(back) <= 1e-9) = [];
    if ~hasOpp, back = zeros(0, 1); end
    rows = [(1:n).'; back]; cix = [repmat(j, n, 1); repmat(j2, numel(back), 1)];
    cut.angle = [P.Theta(:); 360 - P.Theta(back)]; cut.closed = hasOpp;
end
lin = sub2ind([n, numel(P.Phi)], rows, cix);
cut.y = cell2mat(cellfun(@(C) C(lin), cols(:).', 'UniformOutput', false));
cut.theta = P.Theta(rows); cut.phi = P.Phi(cix); cut.snapped = snap > 1e-9;
end

function D = pat_derive(P, G, prm)
%PAT_DERIVE Every column and every base fact of a pattern at the given parameters (I3); ≈ 40 ms at 1°×1°, so it is simply
%   re-run whenever Revision or Params change.  Physical quantities are defined on total gain (I4).
K = apat_const();
if P.IsGainOnly
    D.Cols = P.G; names = string(fieldnames(P.G)).';
    for c = names, if util_colKind(c) == "gain", D.Cols.(c) = P.G.(c) + prm.L; end, end                      % loss on levels only (D14)
    g = names(arrayfun(@(c) util_colKind(c) == "gain", names)); if isempty(g), g = names(1); end
    total = D.Cols.(g(1)); D.Pol = struct('pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]), 'label', 'n/a');
    D.Peak = met_peak(total, G.PhiPeriodic, K.PeakExcessDB);
else
    s = 10^(prm.L/20); Eth = P.Eth*s; Eph = P.Eph*s;                                                     % loss as an incident-field scale (B.3)
    Er = pol_circular(Eth, Eph, 1); El = pol_circular(Eth, Eph, 2);
    C.E_Total_dB = 10*log10(max(abs(Eth).^2 + abs(Eph).^2, eps));
    C.E_TH_dB = 20*log10(max(abs(Eth), eps));  C.E_PH_dB = 20*log10(max(abs(Eph), eps));
    C.E_RCP_dB = 20*log10(max(abs(Er), eps));  C.E_LCP_dB = 20*log10(max(abs(El), eps));
    [C.AR_dB, isLinear] = pol_signedAR(Er, El);
    D.Peak = met_peak(C.E_Total_dB, G.PhiPeriodic, K.PeakExcessDB);
    [i, j] = ind2sub(size(C.E_Total_dB), D.Peak.index);
    D.Pol = pol_classify(Eth, Eph, Er, El, G.dOmega.*(geo_cosGamma(P, P.Theta(i), P.Phi(j)) >= cosd(45)));  % main-beam weighted (D13)
    C.PLF_dB = pol_plf(C.AR_dB, isLinear, prm.RxMode, prm.RxAR_dB, D.Pol.pairs.Circular(1));
    C.Gain_PolCorrected_dB = C.E_Total_dB + C.PLF_dB;
    C.E_TH_Phase = rad2deg(angle(Eth)); C.E_PH_Phase = rad2deg(angle(Eph)); C.E_RCP_Phase = rad2deg(angle(Er)); C.E_LCP_Phase = rad2deg(angle(El));
    C.EIRP_dBW = prm.Pt_dBW + C.E_Total_dB;
    C.PFD_Wm2 = 10.^(C.EIRP_dBW/10)./(4*pi*prm.R_m^2);
    C.E_RMS_Vm = sqrt(30*10.^(C.EIRP_dBW/10))./prm.R_m;
    D.Cols = C; total = C.E_Total_dB;
end
D.Boresight = met_orientation(total, P, G, D.Peak);
D.Planes = met_planes(D.Boresight);
D.Metrics = met_metrics(total, P, G, D.Peak, D.Planes, D.Cols);
end

function K = met_peak(C, periodic, excessDB)
%MET_PEAK Effective peak = highest sample that is not an isolated spike (I5, replaces the percentile policy, D01):
%   spike(i,j) ⇔ C(i,j) − max(4 grid neighbours) > excessDB;  φ wraps when periodic.
[n, m] = size(C); nb = -inf(n, m);
nb(2:n, :) = max(nb(2:n, :), C(1:n-1, :)); nb(1:n-1, :) = max(nb(1:n-1, :), C(2:n, :));            % θ neighbours
if periodic && m > 1, L = circshift(C, 1, 2); R = circshift(C, -1, 2); else, L = [-inf(n, 1), C(:, 1:m-1)]; R = [C(:, 2:m), -inf(n, 1)]; end
nb = max(nb, max(L, R));                                                                            % φ neighbours
K.spike = isfinite(C) & (C - nb > excessDB);
[K.rawValue, K.rawIndex] = max(C(:), [], 'omitnan');
cand = C; cand(K.spike) = -Inf; [K.value, K.index] = max(cand(:), [], 'omitnan');
K.wasAdjusted = K.spike(K.rawIndex); K.spikeCount = nnz(K.spike);
end

function idx = met_orientation(total, P, G, peak)
%MET_ORIENTATION Principal axis whose 45° cone holds the most radiated power ∫10^{G/10} dΩ (spikes excluded).
K = apat_const(); A = K.Axes; w = 10.^(total/10).*G.dOmega; w(peak.spike | ~isfinite(w)) = 0;
e = arrayfun(@(k) sum(w(geo_cosGamma(P, A.theta(k), A.phi(k)) >= cosd(45)), 'all'), 1:numel(A.theta));
[~, idx] = max(e);
end

function S = met_planes(axisIndex)
%MET_PLANES E-plane: θ-cut through the boresight axis' φ.  H-plane: φ-cut at θ = 90° for a transverse axis (±X, ±Y), θ-cut at φ = 90° for ±Z.
K = apat_const(); A = K.Axes; S.E = struct('type', "Theta", 'value', A.phi(axisIndex));
if A.theta(axisIndex) == 90, S.H = struct('type', "Phi", 'value', 90); else, S.H = struct('type', "Theta", 'value', 90); end
end

function m = met_metrics(total, P, G, peak, planes, cols)
%MET_METRICS Directivity D = 4π·U_max / ∫U dΩ (spikes removed from the integral, D07); efficiency and F/B only on a full sphere (I9);
%   HPBW on the E and H principal cuts; AR at the peak.
keep = isfinite(total) & ~peak.spike; U = 10.^(total/10); I = sum(U(keep).*G.dOmega(keep));
[i, j] = ind2sub(size(total), peak.index); m.PeakGain_dB = peak.value; m.PeakTheta_deg = P.Theta(i); m.PeakPhi_deg = P.Phi(j);
m.PeakDirectivity_dB = 10*log10(max(4*pi*10^(peak.value/10)/max(I, eps), eps));
m.Efficiency_pct = NaN; m.FrontBack_dB = NaN;
if G.IsFullSphere
    if P.Meta.Unit == "dBi", m.Efficiency_pct = 100*I/(4*pi); if m.Efficiency_pct > 100, m.Efficiency_pct = NaN; end, end
    [~, b] = min(reshape(geo_cosGamma(P, P.Theta(i), P.Phi(j)), [], 1)); m.FrontBack_dB = peak.value - total(b);   % antipode of the peak
end
cE = geo_cut(P, {total}, planes.E.type, planes.E.value, G.PhiPeriodic); cH = geo_cut(P, {total}, planes.H.type, planes.H.value, G.PhiPeriodic);
m.HPBW_EPlane_deg = met_hpbw(cE.angle, cE.y); m.HPBW_HPlane_deg = met_hpbw(cH.angle, cH.y);
m.AxialRatioAtPeak_dB = NaN; if isfield(cols, 'AR_dB'), m.AxialRatioAtPeak_dB = cols.AR_dB(peak.index); end
end

function [bw, lo, hi] = met_hpbw(angleDeg, gainDB)
%MET_HPBW Half-power beamwidth of a circular cut: linear interpolation of the −3 dB crossings either side of the cut maximum.
[bw, lo, hi] = deal(NaN); v = isfinite(angleDeg) & isfinite(gainDB); angleDeg = angleDeg(v); gainDB = gainDB(v);
if numel(gainDB) < 3, return; end
[pk, ip] = max(gainDB); half = pk - 3;
[rel, o] = sort(mod(angleDeg - angleDeg(ip) + 180, 360) - 180); g = gainDB(o);
L = find(rel < 0 & g <= half, 1, 'last'); R = find(rel > 0 & g <= half, 1, 'first');
if isempty(L) || isempty(R) || L + 1 > numel(g) || R - 1 < 1, return; end
cross = @(a, b) rel(a) + (rel(b) - rel(a))*(half - g(a))/(g(b) - g(a));
if g(L+1) == g(L) || g(R-1) == g(R), return; end
lo = angleDeg(ip) + cross(L, L+1); hi = angleDeg(ip) + cross(R, R-1); bw = hi - lo;
end

function E = pol_circular(Eth, Eph, which)
%POL_CIRCULAR RHCP (which = 1) / LHCP (which = 2) components of E = Eθ θ̂ + Eφ φ̂ (I10, B.4).
%   Convention e^{+jωt}, (θ̂, φ̂, r̂) right-handed; IEEE right-hand unit vector ê_R = (θ̂ − jφ̂)/√2, so
%   E_R = E·ê_R* = (Eθ + jEφ)/√2 and E_L = (Eθ − jEφ)/√2.   Check: E = ê_R ⇒ Eθ = 1/√2, Eφ = −j/√2 ⇒ E_R = 1, E_L = 0.
if which == 1, E = (Eth + 1i*Eph)/sqrt(2); else, E = (Eth - 1i*Eph)/sqrt(2); end
end

function [Eth, Eph] = pol_fromCircular(Er, El)
%POL_FROMCIRCULAR Inverse of pol_circular (OUT, CUT ICOMP = 2, Excel format 2, generic rcp/lcp).
Eth = (Er + El)/sqrt(2); Eph = (Er - El)/(1i*sqrt(2));
end

function [AR, isLinear] = pol_signedAR(Er, El)
%POL_SIGNEDAR Signed axial ratio in dB: + RHCP sense, − LHCP sense; −100 dB at (numerically) linear samples (§15-2).
r = abs(Er); l = abs(El); d = r - l;
isLinear = isfinite(d) & abs(d) <= eps.*max(r + l, 1);
AR = min(20*log10((r + l)./max(abs(d), eps)), 250).*sign(d); AR(isLinear) = -100;
end

function pol = pol_classify(Eth, Eph, Er, El, w)
%POL_CLASSIFY Co/cross ordering of the linear and circular pairs and the polarisation label from the w-weighted mean powers
%   (w = ΔΩ inside the main beam, D13).  The leading circular member drives the Rx "Auto" sense.
p = @(E) sum(abs(E).^2.*w, 'all', 'omitnan');
pol.pairs = struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]);
if p(Eph) > p(Eth), pol.pairs.Linear = fliplr(pol.pairs.Linear); end
if p(El) > p(Er), pol.pairs.Circular = fliplr(pol.pairs.Circular); end
if max(p(Er), p(El)) > max(p(Eth), p(Eph)), pol.label = sprintf('Circular (%s)', replace(pol.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif p(Eth) >= p(Eph), pol.label = 'Linear (Vertical)'; else, pol.label = 'Linear (Horizontal)'; end
end

function plf = pol_plf(AR_dB, isLinear, rxMode, rxAR_dB, leadingCircular)
%POL_PLF Polarisation loss factor between the antenna ellipse (signed AR_dB) and the incident wave (rxMode, rxAR_dB) with
%   orthogonal major axes (cos 2Δτ = −1, the conservative M7 convention; Stutzman):
%   PLF = 1/2 + (4·ρa·ρw − (ρa² − 1)(ρw² − 1)) / (2(ρa² + 1)(ρw² + 1)),  ρ = signed linear axial ratio (|ρ| ≥ 1; +RHCP, −LHCP).
switch rxMode, case "RHCP", sw = 1; case "LHCP", sw = -1; otherwise, sw = 2*(leadingCircular == "E_RCP") - 1; end
ra = 10.^(abs(AR_dB)/20).*sign(AR_dB); ra(isLinear) = 1e12;                                        % linear antenna ⇒ |ρa| → ∞
rw = sw*10^(rxAR_dB/20);
plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1))./(2*(ra.^2 + 1)*(rw^2 + 1));
plf = 10*log10(min(max(plf, eps), 1)); plf(~isfinite(AR_dB)) = NaN;                                % NaN in ⇒ NaN out (D08)
end

function cov = cov_curve(C, dOmega, mask, T)
%COV_CURVE Coverage(T) = 100 · Ω_R(C > T) / Ω_R,   Ω_R(C > T) = Σ_{(i,j)∈R, C(i,j) > T} ΔΩ(i,j)   (I7, strict ">").
v = mask & isfinite(C); g = C(v); w = dOmega(v); Omega = sum(w);
cov = zeros(size(T)); if Omega <= 0, return; end                                                    % empty region → 0 %
cov = 100*arrayfun(@(t) sum(w(g > t)), T)/Omega;                                                    % the definition, O(N) memory (D10)
end

function m = cov_coneMask(P, thC, phC, alphaDeg)
%COV_CONEMASK (i,j) ∈ cone ⇔ cos γᵢⱼ ≥ cos α (spherical law of cosines), nθ×nφ.
m = geo_cosGamma(P, thC, phC) >= cosd(alphaDeg) - 1e-12;
end

function T = cov_thresholds(tMin, tMax, step)
%COV_THRESHOLDS T = tMin + (0:n)·step by counting, not accumulation (D11); tMax always included.
if tMax <= tMin, tMax = tMin + step; end
n = floor((tMax - tMin)/step + 1e-9); T = tMin + (0:n).'*step; if T(end) < tMax - 1e-9, T(end+1) = tMax; end
end

function y = cov_at(job, T)
%COV_AT Coverage at threshold(s) T read off the job's curve (linear between samples, NaN outside) — table union and queries.
y = interp1(job.T, job.cov, T, 'linear', NaN);
end

function T = thr_at(job, c)
%THR_AT Threshold at coverage c %: inverse read of the same curve; for each coverage level keep the highest threshold that
%   still reaches it ('last'), which makes the non-increasing curve strictly monotone (upper end of every plateau).
[cv, i] = unique(job.cov, 'last'); T = nan(size(c)); if numel(cv) < 2, return; end
T = interp1(cv, job.T(i), c, 'linear', NaN);
end

% ---------------------------------------------------------------- utilities
function kind = util_colKind(name)
%UTIL_COLKIND Column kind: from the column table when known, else by name — gain | ar | plf | phase | link | other.
K = apat_const(); i = find(strcmp(K.Cols(:, 1), char(name)), 1);
if ~isempty(i), kind = string(K.Cols{i, 3}); return; end
key = regexprep(lower(char(name)), '[^a-z0-9]', '');
if contains(key, 'plf'), kind = "plf";
elseif startsWith(key, 'ar') || contains(key, 'axial'), kind = "ar";
elseif contains(key, ["phase", "deg", "ang"]), kind = "phase";
elseif contains(key, ["gain", "directivity", "eirp"]) || endsWith(key, ["db", "dbi"]), kind = "gain";
else, kind = "other"; end
end

function tf = util_colHidden(name)
K = apat_const(); i = find(strcmp(K.Cols(:, 1), char(name)), 1); tf = ~isempty(i) && K.Cols{i, 4};
end

function s = util_fmt(v, prec)
%UTIL_FMT Compact number (≤ 2 decimals, no trailing zeros, never "-0") or fixed precision; 'n/a' when not finite (D67).
if ~(isscalar(v) && isnumeric(v) && isfinite(v)), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v + 0), '\.?0+$', ''); else, s = sprintf('%.*f', prec, v + 0); end
if strcmp(s, '-0'), s = '0'; end
end

function b = util_presetRange(peak)
%UTIL_PRESETRANGE 50-dB window under the next multiple of 5 above the peak (colour scale and coverage-threshold preset).
if ~isfinite(peak), b = [-40 10]; return; end
hi = 5*ceil(peak/5); b = min(max([hi - 50, hi], -250), 100);
end

function t = util_ticks(lim, step)
%UTIL_TICKS Tick positions at multiples of step inside lim, plus the limits themselves; empty when degenerate or too many.
t = [];
if numel(lim) ~= 2 || any(~isfinite(lim)) || ~isfinite(step) || step <= 0 || lim(1) >= lim(2), return; end
t = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)], 'stable'); if numel(t) > 60, t = []; end
end

function [r, rmax] = util_polarRadius(v, lim, rmax)
%UTIL_POLARRADIUS Radius of the polar-3D surface and its overlay from the same rule (D60): clipped level, normalised to the surface maximum.
r = max(v - lim(1), 0)/max(lim(2) - lim(1), eps);
if nargin < 3, rmax = max(max(r, [], 'all', 'omitnan'), eps); end
r = r/rmax;
end

function [a, Y] = util_circle(a, Y, signed, closed)
%UTIL_CIRCLE Display form of an open circular cut: rotate to −180..180 when signed; append the closing point when the circle is complete.
if signed
    j0 = find(a >= 180, 1);
    if ~isempty(j0), p = [j0:numel(a), 1:j0-1]; a = a(p); Y = Y(p, :); a(a >= 180) = a(a >= 180) - 360; end
end
if closed, a(end+1) = a(1) + 360; Y(end+1, :) = Y(1, :); end
end