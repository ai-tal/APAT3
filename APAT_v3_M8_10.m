classdef APAT_v3_M8_10 < matlab.apps.AppBase %1793-lines % ERROR: "Index exceeds array bounds. (@(c)sscanf(char(c{1}),'%f').' line 1292)"
% APAT v3 Milestone 8 — one grid-native pattern, one derivation, one dispatcher, one layout helper.
%
%   SOURCE ─► PATTERN(Rev) ─► GEOMETRY ─► DERIVED(Params)      all stored in Pats(k)   (I13 build-then-commit)
%                │
%                ├─► PLOTS / CUTS / TABLES / METADATA  (+ MAP = display permutation, never a data copy)
%                └─► COVERAGE job = curve {T, cov} stored on its tree node
%   VIEW (widgets, read only in readConfig) ─► MAP ─► ColIdx / axes / labels / cut-value domain

    properties (GetAccess = public, SetAccess = private)
        isClosing logical = false
        Perf struct = struct()          % last timed action: {AppVersion, Operation, Stages, TotalSeconds}
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
        Single_paxCut matlab.graphics.axis.PolarAxes
        Single_paxPattern matlab.graphics.axis.PolarAxes
    end

    properties (Access = private)
        Pats struct = struct([])        % pattern registry: {Name, File, Path, Source, Pattern, Geometry, Derived, Params, Stamp}
        Main double = 0                 % index into Pats shown on the Main tab (0 = nothing loaded)
        View struct = struct()          % widget snapshot of the last update (readConfig)
        Map struct = struct()           % display permutation / labels for the current View (geo_displayMap)
        Cut struct = struct()           % current cut geometry (geo_cut)
        Range struct = struct('full',[-40 10],'ar',[-30 30],'cut',[-40 10],'cov',[-40 10],'covX',[-40 10], ...
            'Auto',struct('full',true,'cut',true,'cov',true,'covX',true))
        Gfx struct = struct()           % retained graphics: Full(k), CutPolar, CutRect, Menu
        Status struct = struct()        % persistent status text per status label
        OutMask logical = logical([])   % Results-table column filter
        Stamp double = 0                % increments on every commit; keys every renderer
        Busy logical = false
        StatusTimer = []
        Dialog = []
        PerfRun = []
        CovRunID double = 0
    end

    properties (Constant)
        ReleaseName = 'APAT v3 Milestone 8'
        PeakExcessDB = 6                % a sample is a spike iff it exceeds every grid neighbour by more than this (I5)
        ARLimits = [-30 30]
        Hard = [-250 100]               % hard limits of every level control
        DistanceFloorM = 1e-12
        PrincipalAxes = struct('labels', {{'+Z','-Z','+X','-X','+Y','-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        %        name                    label             kind      hidden-by-default in Results
        Cols = {'E_Total_dB'            'Total Gain'      'gain'    false
                'E_TH_dB'               'Etheta Gain'     'gain'    true
                'E_PH_dB'               'Ephi Gain'       'gain'    true
                'E_RCP_dB'              'RHCP Gain'       'gain'    false
                'E_LCP_dB'              'LHCP Gain'       'gain'    false
                'AR_dB'                 'Axial Ratio'     'ar'      false
                'PLF_dB'                'PLF'             'plf'     false
                'Gain_PolCorrected_dB'  'Polarized Gain'  'gain'    false
                'E_TH_Phase'            'Etheta Phase'    'phase'   true
                'E_PH_Phase'            'Ephi Phase'      'phase'   true
                'E_RCP_Phase'           'RHCP Phase'      'phase'   true
                'E_LCP_Phase'           'LHCP Phase'      'phase'   true
                'EIRP_dBW'              'EIRP'            'link'    true
                'PFD_Wm2'               'PFD'             'link'    true
                'E_RMS_Vm'              'E_RMS'           'link'    true}
        %         name        axes                 range slider    kind       camera
        Views = {'contour'   'Single_Axes_Ctr'    'Range_Ctr'     'contour'  []
                 'circular'  'Single_paxPattern'  'Range_Cir'     'fisheye'  []
                 'sphere3D'  'Single_Axes_3dSph'  'Range_3dSph'   'sphere'   [135 25]
                 'polar3D'   'Single_Axes_3dPol'  'Range_3dPol'   'polar'    [135 25]
                 'rect3D'    'Single_Axes_3dRect' 'Range_3dRect'  'rect'     [-35 35]}
    end

    methods (Access = private)   % ================= ORCHESTRATION =================

        function [V, prm] = readConfig(app)
            % The ONLY place Main-tab widget values are read (I11). Returns a View and the derivation Params.
            V.Path = strtrim(app.Single_EditField_Path.Value);
            V.TextFormat = string(app.Single_DropDown_TextFormat.Value);
            V.Component = string(app.Single_DropDown_Component.Value);
            V.CutType = string(app.Single_DropDown_cutType.Value);
            V.CutValue = app.Single_DropDown_cutValue.Value;
            V.SignedPhi = strcmp(app.Single_Switch_AngularSpan.Value, '-180° to 180°');
            V.Elevation = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°');
            V.Basis = string(app.CutFieldBasisDropDown.Value);
            V.Traces = logical([app.CheckBox_Et.Value, app.CheckBox_Er.Value, app.CheckBox_El.Value]);
            V.HPBW = app.Button_HPBW.Value; V.HPBWTips = app.Single_CheckBox_HPBWBounds.Value;
            V.POB = app.Single_CheckBox_POB.Value; V.Overlay = app.Singel_CheckBox_overlayCut.Value;
            V.OneDeg = strcmp(app.Single_DropDown_step.Value, ['STEP: 1' char(176)]);
            V.FreqIndex = find(strcmp(app.Single_DropDown_FFD.Items, app.Single_DropDown_FFD.Value), 1); if isempty(V.FreqIndex), V.FreqIndex = 1; end
            V.Camera = string(app.Single_DropDown_3DView.Value);
            V.Cstep = app.Single_Plot_Cstep.Value;
            prm = struct('L', app.Single_Spinner_Loss.Value, 'RxMode', string(app.Single_DropDown_RxPol.Value), 'RxAR_dB', app.Single_Spinner_Rw.Value);
            pt = app.Single_Spinner_Pt.Value;
            switch app.Single_DropDown_Pt.Value, case 'dBm', prm.Pt_dBW = pt - 30; case 'Watts', prm.Pt_dBW = 10*log10(max(pt, eps)); otherwise, prm.Pt_dBW = pt; end
            prm.R_m = max(app.Single_Spinner_R.Value, app.DistanceFloorM) * (1 + 999*strcmp(app.Single_DropDown_R.Value, 'km'));
        end

        function c = readCoverageConfig(app)
            % The ONLY place Coverage-tab widget values are read. Never writes a widget (D48).
            c.Path = strtrim(app.Cov_EditField_filePath.Value); c.TextFormat = string(app.Cov_DropDown_TextFormat.Value);
            c.Component = string(app.Cov_DropDown_Component.Value);
            c.Conical = logical(app.Cov_ButtonGroup_Btn_Conical.Value);
            c.Cone = [app.Cov_Spinner_ConeTH.Value, mod(app.Cov_Spinner_ConePH.Value, 360), app.Cov_Spinner_ConeAng.Value];
            c.Orientation = double(app.Cov_DropDown_Orientation.Value);
            c.T = cov_thresholds(app.Cov_Spinner_ThreshMin.Value, app.Cov_Spinner_ThreshMax.Value, max(app.Cov_Spinner_Step.Value, 0.1));
            c.QueryT = app.Cov_Spinner_queryCov.Value; c.QueryC = app.Cov_Spinner_queryThresh.Value;
        end

        function on(app, scope, title, busyText)
            % Guard around every user action: re-entrancy, cancel, error, timing. State changes only inside update's commit.
            if app.Busy || app.isClosing, return; end
            app.Busy = true; cleanBusy = onCleanup(@() app.setBusy(false));
            if nargin > 3
                app.Dialog = uiprogressdlg(app.UIFigure, 'Title', title, 'Message', busyText, 'Indeterminate', 'on', 'Cancelable', true, 'CancelText', 'Abort');
                cleanDlg = onCleanup(@() delete(app.Dialog)); drawnow
            end
            app.perf("begin " + scope);
            try
                switch scope
                    case "covSource", app.covLoad();
                    case "covRun", app.covCompute();
                    otherwise, app.update(scope);
                end
                drawnow limitrate
            catch err
                if strcmp(err.identifier, 'APAT:Cancelled'), app.setStatus(app.Single_StatusBar, 'Cancelled by user.', true);
                else, app.showError(err, title); end
            end
            app.perf("end");
        end

        function setBusy(app, tf), if ~app.isClosing, app.Busy = tf; end, end

        function update(app, scope)
            % Ladder: source ⊃ build (freq / step) ⊃ params ⊃ view. Numeric stages build into a local E and commit once (I13).
            rung = find(scope == ["source" "build" "params" "view"], 1);
            [V, prm] = app.readConfig();
            if rung <= 3
                if rung == 1
                    E = struct('Name', '', 'File', '', 'Path', V.Path, 'Source', [], 'Pattern', [], 'Geometry', [], 'Derived', [], 'Params', [], 'NativeStep', [1 1], 'Stamp', 0);
                    [~, E.Name, ext] = fileparts(V.Path); E.File = [E.Name ext];
                    E.Source = io_read(V.Path, V.TextFormat); app.perf("Read file"); app.checkCancelled();
                    if E.Source.Meta.IsCoverage       % a coverage-results file routes to the Coverage tab and leaves Main untouched
                        if app.Main > 0, app.Single_EditField_Path.Value = app.Pats(app.Main).Path; end
                        app.covLoadResults(V.Path, E.Source.Raw); return
                    end
                elseif app.Main == 0, return
                else, E = app.Pats(app.Main);
                end
                if rung <= 2
                    E.Pattern = pat_build(E.Source, min(V.FreqIndex, numel(E.Source.Blocks))); app.perf("Build pattern"); app.checkCancelled();
                    E.NativeStep = [E.Pattern.dTheta, E.Pattern.dPhi];
                    if V.OneDeg && (abs(E.Pattern.dTheta - 1) > 1e-9 || abs(E.Pattern.dPhi - 1) > 1e-9)
                        E.Pattern = pat_resample(E.Pattern, 1); app.perf("Resample");
                    end
                    E.Geometry = geo_build(E.Pattern);
                end
                E.Params = prm; E.Derived = pat_derive(E.Pattern, E.Geometry, prm); app.perf("Derive"); app.checkCancelled();
                % ---- commit: nothing above touched application state
                app.Stamp = app.Stamp + 1; E.Stamp = app.Stamp;
                if rung == 1
                    k = find(strcmp({app.Pats.Path}, E.Path), 1); if isempty(k), k = numel(app.Pats) + 1; end
                    app.Main = k;
                end
                app.Pats(app.Main) = E;
                app.applyChoices(rung); [V, prm] = app.readConfig(); %#ok<ASGLU>
            end
            if app.Main == 0, return; end
            E = app.Pats(app.Main); app.View = V;
            app.Map = geo_displayMap(E.Pattern, E.Geometry, V);
            [type, value] = app.cutSpec(V);
            app.Cut = geo_cut(E.Pattern, type, value);
            app.renderFull(app.visibleView()); app.renderCut(); app.renderTables(); app.renderMetadata(); app.perf("Render");
            if rung <= 3, app.setStatus(app.Single_StatusBar, app.mainStatus(E), false); end
            app.applyVisibility();
        end

        function applyChoices(app, rung)
            % The ONLY writer of data-derived Items / ItemsData / Limits / Step / default values.
            E = app.Pats(app.Main); P = E.Pattern; D = E.Derived;
            [names, labels] = colChoices(D.Cols, P.IsGainOnly);
            dd = app.Single_DropDown_Component; previous = string(dd.Value);
            [dd.Items, dd.ItemsData] = deal(cellstr(labels), cellstr(names)); dd.Value = char(prefer(previous, names));
            if rung == 1
                items = compose('Pattern %d: %.4g GHz', (1:numel(E.Source.Blocks)).', E.Source.Freqs(:)/1e9);
                items(~isfinite(E.Source.Freqs(:))) = compose('Pattern %d', find(~isfinite(E.Source.Freqs(:))));
                [app.Single_DropDown_FFD.Items, app.Single_DropDown_FFD.Value] = deal(items, items{1});
                items = {sprintf('STEP: %g%c', max(E.NativeStep), char(176))};                    % one item when native = 1° (D52)
                if any(abs(E.NativeStep - 1) > 1e-9), items{end+1} = ['STEP: 1' char(176)]; end
                oneDeg = strcmp(app.Single_DropDown_step.Value, ['STEP: 1' char(176)]) && numel(items) > 1;
                app.Single_DropDown_step.Items = items; app.Single_DropDown_step.Value = items{1 + oneDeg};
                app.OutMask = ~cellfun(@isHidden, fieldnames(D.Cols)).'; app.applyOutputFilter();
            end
            if rung <= 2
                if ~P.IsGainOnly, app.CutFieldBasisDropDown.Value = char(D.Pol.basis); end
                [app.CheckBox_Er.Text, app.CheckBox_El.Text] = deal(D.Pol.pairs.(app.CutFieldBasisDropDown.Value){:});
                app.setPlane(startsWith(app.Single_Switch_EHplane.Value, 'E'));
                if app.Range.Auto.full, app.applyRange("full", util_presetRange(D.Peak.value), true); end
                if app.Range.Auto.cut, app.applyRange("cut", util_presetRange(D.Peak.value), true); end
            end
            app.applyCutDomain();
        end

        function setPlane(app, isE)
            % E/H plane from the boresight axis (A.7); writes the two cut controls in the display convention.
            S = app.Pats(app.Main).Derived.Planes; s = S.H; if isE, s = S.E; end
            app.Single_DropDown_cutType.Value = char(s.type);
            V = app.readConfig(); v = s.value;
            if s.type == "Phi" && V.Elevation, v = 90 - v; elseif s.type == "Theta" && V.SignedPhi && v >= 180, v = v - 360; end
            app.applyCutDomain(); app.Single_DropDown_cutValue.Value = v;
        end

        function applyCutDomain(app)
            % Cut-value spinner domain follows the display convention through Map (D46); one writer (D40).
            P = app.Pats(app.Main).Pattern; V = app.readConfig(); M = geo_displayMap(P, app.Pats(app.Main).Geometry, V);
            if V.CutType == "Phi", vals = M.ThetaAxis; step = P.dTheta; else, vals = M.PhiAxis(1:numel(P.Phi)); step = P.dPhi; end
            sp = app.Single_DropDown_cutValue; if max(vals) > min(vals), sp.Limits = [min(vals), max(vals)]; end, if isfinite(step), sp.Step = step; end
            [~, i] = min(abs(vals - sp.Value)); sp.Value = vals(i);
        end

        function [type, value] = cutSpec(~, V)
            % Display-convention cut controls → canonical (polar θ, φ ∈ [0,360)) cut request.
            type = V.CutType; value = V.CutValue;
            if type == "Phi" && V.Elevation, value = 90 - value; elseif type == "Theta", value = mod(value, 360); end
        end

        function applyVisibility(app)
            % The ONLY writer of Visible / Enable on the Main tab; computed from Meta, component kind and choices (D53, D69).
            has = app.Main > 0; set([app.Single_Panel_Rect, app.Single_Export_Output, app.Single_Panel_fullPattern, ...
                app.Single_Panel_plotControl, app.Single_Button_Coverage, app.Single_tabData, app.Single_DropDown_output], 'Visible', has);
            if ~has, return; end
            E = app.Pats(app.Main); field = ~E.Pattern.IsGainOnly; kind = util_colKind(app.View.Component);
            set([app.Single_Export_UAN, app.Single_gridEcut, app.CheckBox_Et, app.CheckBox_Er, app.CheckBox_El], 'Visible', field);
            set([app.CheckBox_Er, app.CheckBox_El, app.CutFieldBasisDropDown], 'Enable', field);
            multi = numel(E.Source.Blocks) > 1; set([app.Single_DropDown_FFD, app.FFDFreqDropDownLabel], 'Visible', multi, 'Enable', multi);
            step = numel(app.Single_DropDown_step.Items) > 1; set(app.Single_DropDown_step, 'Visible', step, 'Enable', step);
            generic = isGenericText(E.Path); set([app.TextFormatLabel, app.Single_DropDown_TextFormat], 'Visible', generic);
            set([app.RxPolLabel, app.Single_DropDown_RxPol, app.IncidentWaveARRwPLFLabel, app.Single_Spinner_Rw], 'Visible', field && any(app.View.Component == ["PLF_dB" "Gain_PolCorrected_dB"]));
            set([app.TransmitPowerLabel, app.Single_Spinner_Pt, app.Single_DropDown_Pt], 'Visible', field && kind == "link");
            set([app.DistanceLabel, app.Single_Spinner_R, app.Single_DropDown_R], 'Visible', field && any(app.View.Component == ["PFD_Wm2" "E_RMS_Vm"]));
            set([app.LossindBLabel, app.Single_Spinner_Loss], 'Visible', kind == "gain");
            app.Single_CheckBox_HPBWBounds.Visible = app.View.HPBW;
        end

        function g = fullGroup(app)
            g = "full"; if app.Main > 0 && isfield(app.View, 'Component') && util_colKind(app.View.Component) == "ar", g = "ar"; end
        end

        function applyRange(app, group, lim, reset)
            % One descriptor-driven range controller for {full, ar, cut, cov, covX}: widgets first, then the axes.
            H = app.Hard; gap = 1 - 0.9*any(group == ["cov" "covX"]);
            lim = sort(double(lim(:).')); lim = [max(H(1), lim(1)), min(H(2), lim(2))];
            if diff(lim) < gap, lim(2) = min(H(2), lim(1) + gap); lim(1) = lim(2) - gap; end
            app.Range.(group) = lim;
            switch group
                case {"full", "ar"}, sl = [app.Range_Ctr app.Range_Cir app.Range_3dSph app.Range_3dPol app.Range_3dRect];
                    mn = [app.Range_Ctr_Min app.Range_Cir_Min app.Range_3dSph_Min app.Range_3dPol_Min app.Range_3dRect_Min app.Single_Plot_Cmin];
                    mx = [app.Range_Ctr_Max app.Range_Cir_Max app.Range_3dSph_Max app.Range_3dPol_Max app.Range_3dRect_Max app.Single_Plot_Cmax];
                case "cut", sl = app.Range_Cut; mn = app.Range_Cut_Min; mx = app.Range_Cut_Max;
                case "cov", sl = []; mn = app.Cov_Spinner_ThreshMin; mx = app.Cov_Spinner_ThreshMax;
                case "covX", sl = app.Cov_Spinner_XRange; mn = app.Cov_Spinner_XMin; mx = app.Cov_Spinner_XMax;
            end
            if ~isempty(sl)
                bounds = lim; if ~reset, bounds = [min(sl(1).Limits(1), lim(1)), max(sl(1).Limits(2), lim(2))]; end
                set(sl, 'Limits', H, 'Value', lim); set(sl, 'Limits', bounds);
            end
            set(mn, 'Limits', [H(1), lim(2) - gap], 'Value', lim(1)); set(mx, 'Limits', [lim(1) + gap, H(2)], 'Value', lim(2));
            switch group
                case {"full", "ar"}, if group == app.fullGroup(), for k = 1:5, app.applyTheme(k); end, end
                case "cut", set(app.Single_paxCut, 'RLim', lim); set(app.Single_AxesRect, 'YLim', lim);
                case "covX", app.Cov_Axes.XLim = lim;
            end
        end

        function onRange(app, group, lim)
            % Every range slider / spinner lands here; a user edit switches the group off Auto (D39, D45).
            if app.Busy, return; end
            if group == "full", group = app.fullGroup(); end
            app.Range.Auto.(group) = false; app.applyRange(group, lim, false);
            if app.Main > 0 && any(group == ["full" "ar"]), app.renderFull(app.visibleView()); end   % polar-3D radius follows the range
            drawnow limitrate
        end

        function perf(app, stage)
            % perf("begin <op>") | perf("<stage>") | perf("end") — same record shape and destination as M7 (Perf_<class>).
            if startsWith(stage, "begin"), app.PerfRun = struct('Op', extractAfter(stage, 6), 'T0', tic, 'T', tic, 'Rows', {cell(0, 2)}); return; end
            if isempty(app.PerfRun), return; end
            app.PerfRun.Rows(end+1, :) = {char(stage), toc(app.PerfRun.T)}; app.PerfRun.T = tic;
            if stage ~= "end", return; end
            app.Perf = struct('AppVersion', class(app), 'Operation', app.PerfRun.Op, ...
                'Stages', cell2table(app.PerfRun.Rows, 'VariableNames', {'Stage', 'Seconds'}), 'TotalSeconds', toc(app.PerfRun.T0));
            assignin('base', matlab.lang.makeValidName("Perf_" + class(app)), app.Perf); app.PerfRun = [];
        end

        function setStatus(app, label, msg, transient)
            % One reusable timer for transient messages; the persistent text lives in app.Status (not in UserData).
            if app.isClosing || ~isgraphics(label), return; end
            stop(app.StatusTimer); label.Text = char(msg);
            if ~transient, app.Status.(label.Tag) = char(msg); return; end
            app.StatusTimer.TimerFcn = @(~, ~) set(label, 'Text', app.Status.(label.Tag)); start(app.StatusTimer);
        end

        function s = mainStatus(app, E)
            K = E.Derived.Peak; [th, ph] = ind2sub(size(E.Derived.Cols.(E.Derived.Total)), K.index);
            s = sprintf('Pattern: <b>%s</b> | POB <b>%s %s</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)', E.File, util_fmtNumber(K.value, 2), ...
                E.Source.Meta.UnitLabel, util_fmtNumber(E.Pattern.Theta(th)), util_fmtNumber(E.Pattern.Phi(ph)));
            if ~E.Pattern.IsGainOnly, s = sprintf('%s | Polarization <b>%s</b>', s, E.Derived.Pol.label); end
            if K.wasAdjusted, s = sprintf('%s | raw max %s %s ignored as isolated spike', s, util_fmtNumber(K.rawValue, 2), E.Source.Meta.UnitLabel); end
        end

        function k = visibleView(app), k = find(strcmp(app.Views(:, 1), app.Single_tabPlots.SelectedTab.Tag), 1); end

        function checkCancelled(app)
            if ~isempty(app.Dialog) && isvalid(app.Dialog) && app.Dialog.CancelRequested, error('APAT:Cancelled', 'Operation cancelled by user.'); end
        end

        function showError(app, err, title)
            if app.isClosing, return; end
            where = ''; if ~isempty(err.stack), where = sprintf('\n(%s line %d)', err.stack(1).name, err.stack(1).line); end
            uialert(app.UIFigure, [err.message where], title, 'Icon', 'error');
        end
    end

    methods (Access = private)   % ================= RENDERERS (retained graphics, keyed) =================

        function renderFull(app, k)
            % One renderer for the five full-pattern views; redraws only when its key changes, in place when the grid size is unchanged.
            if app.Main == 0 || isempty(k), return; end
            E = app.Pats(app.Main); s = app.Gfx.Full(k); V = app.View; M = app.Map; g = app.fullGroup();
            key = sprintf('%d|%s|%s|%d|%s|%s', E.Stamp, V.Component, M.Key, V.Overlay, mat2str(app.Range.(g)), V.Camera);
            if strcmp(s.Key, key), return; end
            C = E.Derived.Cols.(V.Component); C = C(:, M.ColIdx); P = E.Pattern;
            [X, Y, Z] = app.viewCoords(s.Kind, P, M, C, app.Range.(g));
            if isgraphics(s.Surf) && isequal(size(s.Surf.CData), size(C))
                set(s.Surf, 'XData', X, 'YData', Y, 'ZData', Z, 'CData', C);
            else
                delete(s.Surf); s.Surf = surface(s.Axes, X, Y, Z, C, 'FaceColor', 'interp', 'EdgeColor', 'none', 'ContextMenu', app.Gfx.Menu);
            end
            label = app.compLabel(); unit = util_unit(V.Component, E.Source.Meta); ax = s.Axes;
            [thetaGrid, phiGrid] = ndgrid(M.ThetaAxis, M.PhiAxis);
            try, s.Surf.DataTipTemplate.DataTipRows = [dataTipTextRow(M.ThetaLabel, thetaGrid, '%.3g°'); dataTipTextRow("Phi", phiGrid, '%.3g°'); dataTipTextRow(label, C, ['%.3g ' unit])];
            catch err, app.Status.DataTip = err.message; end
            switch s.Kind
                case "contour"
                    app.formatAngular(ax, M, 30, 15); daspect(ax, [1 1 1]); title(ax, label, 'Interpreter', 'none');
                case "fisheye"
                    app.polarTicks(ax); ax.RLim = [0 180]; ax.RTick = 0:30:180; r = 0:30:180; if V.Elevation, r = 90 - r; end
                    ax.RTickLabel = compose('%d°', r); title(ax, sprintf('%s  |  r=θ, angle=φ', label), 'Interpreter', 'none', 'FontSize', 9);
                case {"sphere", "polar"}
                    title(ax, sprintf('%s  |  θ: %s  |  φ: %s', label, app.Single_Switch_ThetaSpan.Value, app.Single_Switch_AngularSpan.Value), 'Interpreter', 'none');
                case "rect"
                    app.formatAngular(ax, M, 60, 30); grid(ax, 'on'); title(ax, label, 'Interpreter', 'none');
                    xlabel(ax, 'Phi (degree)'); ylabel(ax, M.ThetaLabel + " (degree)"); zlabel(ax, label + " (" + unit + ")", 'Interpreter', 'none');
            end
            if s.Kind ~= "contour" && s.Kind ~= "fisheye", app.applyCamera(k); end
            app.Gfx.Full(k) = s; app.applyTheme(k); app.placeMarker(k, X, Y, Z, C); app.renderOverlay(k);
            app.Gfx.Full(k).Key = key;
        end

        function [X, Y, Z] = viewCoords(~, kind, P, M, C, lim)
            % The only per-kind code: coordinates of the displayed grid (physical geometry, display labels).
            th = P.Theta(:); ph = P.Phi(M.ColIdx(:)).';
            switch kind
                case "contour", X = M.PhiAxis; Y = M.ThetaAxis; Z = zeros(size(C));
                case "fisheye", [X, Y] = meshgrid(deg2rad(ph), th); Z = zeros(size(C));
                case "rect",    X = M.PhiAxis; Y = M.ThetaAxis; Z = C;
                otherwise       % sphere | polar
                    r = 1; if kind == "polar", r = util_polarRadius(C, lim); end
                    X = r .* (sind(th) * cosd(ph)); Y = r .* (sind(th) * sind(ph)); Z = r .* (cosd(th) * ones(size(ph)));
            end
        end

        function applyTheme(app, k)
            % Colour scale of one view: signed AR uses the blue-white-red map on ARLimits; everything else jet on Range.full (D41, D66).
            s = app.Gfx.Full(k); if ~isgraphics(s.Axes), return; end
            if app.fullGroup() == "ar", lim = app.Range.ar; map = app.Gfx.ARMap; else, lim = app.Range.full; map = app.Gfx.JetMap; end
            clim(s.Axes, lim); colormap(s.Axes, map); ticks = util_ticks(lim, app.Single_Plot_Cstep.Value);
            if ~isempty(ticks), s.Bar.Ticks = ticks; end
            if s.Kind == "rect", zlim(s.Axes, lim); if ~isempty(ticks), s.Axes.ZTick = ticks; end, end
        end

        function applyCamera(app, k)
            s = app.Gfx.Full(k); up = [0 0 1]; cam = app.Views{k, 5};
            switch string(app.Single_DropDown_3DView.Value)
                case "top", cam = [0 90]; up = [0 1 0];  case "bottom", cam = [0 -90]; up = [0 1 0];
                case "right", cam = [90 0]; case "left", cam = [-90 0]; case "front", cam = [0 0]; case "back", cam = [180 0];
            end
            view(s.Axes, cam(1), cam(2)); camup(s.Axes, up);
        end

        function placeMarker(app, k, X, Y, Z, C)
            % POB marker + datatip per view, created once and re-indexed (D70). Index is the effective peak on total gain (I4).
            s = app.Gfx.Full(k); E = app.Pats(app.Main); M = app.Map;
            [i, j] = ind2sub(size(E.Derived.Cols.(E.Derived.Total)), E.Derived.Peak.index); jj = find(M.ColIdx == j, 1);
            if isvector(X), x = X(jj); y = Y(i); else, x = X(i, jj); y = Y(i, jj); end   % axis vectors (contour/rect) or grids
            z = Z(i, jj);
            if ~isgraphics(s.Mark)
                if isa(s.Axes, 'matlab.graphics.axis.PolarAxes'), s.Mark = polarplot(s.Axes, x, y, 'ko', 'MarkerSize', 5, 'MarkerFaceColor', 'k', 'HandleVisibility', 'off');
                else, s.Mark = plot3(s.Axes, x, y, z, 'ko', 'MarkerSize', 5, 'MarkerFaceColor', 'k', 'HandleVisibility', 'off', 'Clipping', 'off'); end
                s.Tip = datatip(s.Mark, 'DataIndex', 1, 'HandleVisibility', 'off', 'FontSize', 9);
            elseif isa(s.Axes, 'matlab.graphics.axis.PolarAxes'), set(s.Mark, 'ThetaData', x, 'RData', y);
            else, set(s.Mark, 'XData', x, 'YData', y, 'ZData', z);
            end
            s.Mark.DataTipTemplate.DataTipRows = [dataTipTextRow(M.ThetaLabel, M.ThetaAxis(i), '%.3g°'); dataTipTextRow("Phi", M.PhiAxis(jj), '%.3g°'); ...
                dataTipTextRow(app.compLabel(), C(i, jj), ['%.3g ' util_unit(app.View.Component, E.Source.Meta)])];
            set([s.Mark, s.Tip], 'Visible', app.View.POB); app.Gfx.Full(k) = s;
        end

        function renderOverlay(app, k)
            % Cut overlay on the two spatial 3-D views, from the same geo_cut result as the cut plots (D61, D72).
            s = app.Gfx.Full(k); if ~any(s.Kind == ["sphere" "polar"]), return; end
            S = app.Cut; y = app.traceValues(); y = y(:, 1); r = 1.02;
            if s.Kind == "polar", r = 1.01 * util_polarRadius(y, app.Range.(app.fullGroup())); end
            if ~isgraphics(s.Over), s.Over = plot3(s.Axes, nan, nan, nan, 'k', 'LineWidth', 1.6, 'HandleVisibility', 'off'); end
            set(s.Over, 'XData', r .* sind(S.theta) .* cosd(S.phi), 'YData', r .* sind(S.theta) .* sind(S.phi), 'ZData', r .* cosd(S.theta), 'Visible', app.View.Overlay);
            app.Gfx.Full(k) = s;
        end

        function [names, idx] = cutTraces(app)
            % Trace columns of the cut: Total + co/cross pair (E-field) or the selected column (gain-only, D15). idx keeps stable colours.
            E = app.Pats(app.Main); V = app.View;
            if E.Pattern.IsGainOnly, names = V.Component; idx = 1; return; end
            names = ["E_Total_dB", string(E.Derived.Pol.pairs.(V.Basis)) + "_dB"]; sel = V.Traces; if ~any(sel), sel(1) = true; end
            idx = find(sel); names = names(idx);
        end

        function Y = traceValues(app)
            names = app.cutTraces(); C = app.Pats(app.Main).Derived.Cols; Y = zeros(numel(app.Cut.idx), numel(names));
            for t = 1:numel(names), col = C.(names(t)); Y(:, t) = col(app.Cut.idx); end
        end

        function renderCut(app)
            % Polar + rectangular cut from one geo_cut; three retained lines per axes, HPBW regions / bounds and the cut POB re-positioned.
            E = app.Pats(app.Main); V = app.View; S = app.Cut; g = app.Gfx; [names, idx] = app.cutTraces();
            key = sprintf('%d|%s|%s|%g|%d|%s|%d%d%d|%d', E.Stamp, strjoin(names, ','), S.type, S.fixed, V.SignedPhi, mat2str(app.Range.cut), V.HPBW, V.HPBWTips, V.POB, S.snapped);
            if strcmp(g.CutKey, key), return; end
            Y = app.traceValues(); ang = S.angle; lim = app.Range.cut; unit = util_unit(names(1), E.Source.Meta);
            if V.SignedPhi, [ang, o] = sort(mod(ang + 180, 360) - 180); Y = Y(o, :); end
            colors = app.Single_AxesRect.ColorOrder;
            for t = 1:3
                on = t <= numel(names); set([g.CutPolar(t), g.CutRect(t)], 'Visible', on); if ~on, continue; end
                rows = [dataTipTextRow("Angle", ang, '%.3g°'); dataTipTextRow("Magnitude", Y(:, t), ['%.3g ' unit])];
                set(g.CutPolar(t), 'ThetaData', deg2rad(ang), 'RData', max(Y(:, t), lim(1)), 'Color', colors(idx(t), :), 'DisplayName', replace(names(t), "_", "\_"));
                set(g.CutRect(t), 'XData', ang, 'YData', Y(:, t), 'Color', colors(idx(t), :), 'DisplayName', replace(names(t), "_", "\_"));
                g.CutPolar(t).DataTipTemplate.DataTipRows = rows; g.CutRect(t).DataTipTemplate.DataTipRows = rows;
            end
            xl = [0 360] - 180*V.SignedPhi;
            set(app.Single_paxCut, 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.polarTicks(app.Single_paxCut);
            set(app.Single_AxesRect, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(app.Single_AxesRect, char(S.type + " (degree)")); ylabel(app.Single_AxesRect, ['Magnitude (' unit ')']);
            ttl = sprintf('%s cut @ %s = %g°', S.type, S.symbol, S.fixed); if E.Pattern.IsGainOnly, ttl = [char(app.compLabel()) '  |  ' ttl]; end
            title(app.Single_paxCut, ttl, 'Interpreter', 'none'); title(app.Single_AxesRect, ttl, 'Interpreter', 'none');
            legend(app.Single_paxCut, g.CutPolar(1:numel(names)), 'Location', 'southoutside', 'Orientation', 'horizontal');
            legend(app.Single_AxesRect, g.CutRect(1:numel(names)), 'Location', 'best');
            if S.snapped, app.setStatus(app.Single_StatusBar, sprintf('Requested %s cut @ %s=%g° snapped to nearest %s=%g°', S.type, S.symbol, V.CutValue, S.symbol, S.fixed), true); end
            % POB of the displayed cut (peak of the first trace, named in the tip, D62)
            [pk, ip] = max(Y(:, 1), [], 'omitnan'); rows = [dataTipTextRow("Angle", ang(ip), '%.3g°'); dataTipTextRow(names(1), pk, ['%.3g ' unit])];
            set(g.CutMark(1), 'ThetaData', deg2rad(ang(ip)), 'RData', max(pk, lim(1))); set(g.CutMark(2), 'XData', ang(ip), 'YData', pk);
            for h = g.CutMark, h.DataTipTemplate.DataTipRows = rows; end
            set([g.CutMark, g.CutMarkTip], 'Visible', V.POB && isfinite(pk));
            % HPBW: wrap-aware shaded region and optional interpolated boundary tips
            app.Label_HPBW.Text = ''; [bw, lo, hi] = deal(NaN); R = nan(2, 2); bound = ["Lower HPBW" "Upper HPBW"];
            if V.HPBW, [bw, lo, hi] = met_hpbw(ang, Y(:, 1), pk, ang(ip)); end
            if isfinite(bw)
                b = mod([lo hi] - xl(1), 360) + xl(1); app.Label_HPBW.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                if b(1) <= b(2), R(1, :) = b; else, R = [xl(1) b(2); b(1) xl(2)]; end     % wrap around the seam → two regions
                for r = 1:2
                    rows = [dataTipTextRow(bound(r), b(r), '%.2f°'); dataTipTextRow(names(1), pk - 3, ['%.2f ' unit])];
                    set(g.HPBWMark(1, r), 'ThetaData', deg2rad(b(r)), 'RData', pk - 3); set(g.HPBWMark(2, r), 'XData', b(r), 'YData', pk - 3);
                    for h = g.HPBWMark(:, r).', h.DataTipTemplate.DataTipRows = rows; end
                end
            end
            for r = 1:2
                on = isfinite(R(r, 1)); if on, set(g.HPBWPolar(r), 'Value', deg2rad(R(r, :))); set(g.HPBWRect(r), 'Value', R(r, :)); end
                set([g.HPBWPolar(r) g.HPBWRect(r)], 'Visible', on);
            end
            set([g.HPBWMark(:); g.HPBWTip(:)], 'Visible', isfinite(bw) && V.HPBWTips);
            g.CutKey = key; app.Gfx = g;
        end

        function T = resultsTable(app)
            % Long table of the displayed grid (display convention) from Derived.Cols; used by the Results tab and export.
            E = app.Pats(app.Main); M = app.Map; names = fieldnames(E.Derived.Cols); names = names(app.OutMask);
            n = numel(E.Pattern.Theta); m = numel(M.ColIdx);
            vals = cellfun(@(nm) reshape(E.Derived.Cols.(nm)(:, M.ColIdx), [], 1), names, 'UniformOutput', false);
            T = table(repmat(M.ThetaAxis(:), m, 1), repelem(M.PhiAxis(:), n), vals{:}, 'VariableNames', [{char(M.ThetaLabel)}, {'Phi'}, names.']);
        end

        function renderTables(app)
            E = app.Pats(app.Main);
            if ~isequal(app.Gfx.InputKey, E.Path)
                app.Single_Table_DataIn.Data = E.Source.Raw; app.Single_Table_DataIn.ColumnName = E.Source.Raw.Properties.VariableNames; app.Gfx.InputKey = E.Path;
            end
            key = sprintf('%d|%s|%s', E.Stamp, app.Map.Key, char('0' + app.OutMask));
            if app.Single_tabData.SelectedTab ~= app.Single_tabDataOut || strcmp(app.Gfx.TableKey, key), return; end
            app.Single_Table_DataOut.Data = app.resultsTable(); app.Gfx.TableKey = key;
        end

        function applyOutputFilter(app)
            % Results column filter dropdown: items from Derived.Cols, ✓ marks the visible columns, styles from Gfx.
            dd = app.Single_DropDown_output; names = fieldnames(app.Pats(app.Main).Derived.Cols).';
            [dd.Items, dd.ItemsData] = deal([{'--- column filter ---'}, names], 0:numel(names)); dd.Value = 0;
            on = find(app.OutMask) + 1; dd.Items(on) = append('✓ ', dd.Items(on)); removeStyle(dd);
            addStyle(dd, app.Gfx.Styles{1}, 'Item', on); addStyle(dd, app.Gfx.Styles{2}, 'Item', find([true, ~app.OutMask]));
        end

        function onOutputFilter(app)
            v = app.Single_DropDown_output.Value; if v > 0, app.OutMask(v) = ~app.OutMask(v); end
            app.applyOutputFilter(); app.Gfx.TableKey = ''; app.renderTables();
        end

        function renderMetadata(app)
            % {label, value} rows from Meta, Pattern, Geometry, Derived, Params and the pinned conventions (I9).
            E = app.Pats(app.Main); P = E.Pattern; G = E.Geometry; D = E.Derived; K = D.Peak; X = D.Metrics; f = @util_fmtNumber; u = E.Source.Meta.UnitLabel;
            [pt, pp] = ind2sub(size(D.Cols.(D.Total)), K.index); [rt, rp] = ind2sub(size(D.Cols.(D.Total)), K.rawIndex);
            rows = {'Source format', char(E.Source.Meta.Format); 'File', E.File; 'Level unit', char(u)
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', numel(P.Theta)*numel(P.Phi), numel(P.Theta), numel(P.Phi))
                'θ range / step', sprintf('[%s°, %s°] / %s°', f(P.Theta(1)), f(P.Theta(end)), f(P.dTheta))
                'φ range / step', sprintf('[%s°, %s°] / %s°  (%s)', f(P.Phi(1)), f(P.Phi(end)), f(P.dPhi), char(string(G.PhiPeriodic).replace(["true" "false"], ["periodic" "open"])))
                'Sphere coverage', sprintf('%s sr = %s%% of 4π%s', f(G.Omega, 3), f(100*G.Omega/(4*pi)), char(string(G.IsFullSphere).replace(["true" "false"], ["  (full sphere)" "  (partial sphere)"])))
                'Resolution', char(string(P.Revision > 1).replace(["true" "false"], ["resampled to 1°" "native"]))};
            if any(isfinite(E.Source.Freqs)), rows(end+1, :) = {'Frequencies', char(strjoin(compose('%.4g GHz', E.Source.Freqs(isfinite(E.Source.Freqs))/1e9), ', '))}; end
            if ~P.IsGainOnly
                rows = [rows; {'Polarization', char(D.Pol.label); 'Cut Co-pol / Cross-pol', strjoin(D.Pol.pairs.(app.View.Basis), ' / ')
                    'Circular basis', 'E_R = (Eθ + jEφ)/√2, E_L = (Eθ − jEφ)/√2  (e^{+jωt}, IEEE)'}];
            end
            rows = [rows; {'Peak (POB)', sprintf('%s %s at [θ %s°, φ %s°]', f(K.value), u, f(P.Theta(pt)), f(P.Phi(pp)))
                'Peak policy', sprintf('spatial isolation, excess %g dB, %d spike(s)', app.PeakExcessDB, K.spikeCount)
                'Raw maximum', sprintf('%s %s at [θ %s°, φ %s°]%s', f(K.rawValue), u, f(P.Theta(rt)), f(P.Phi(rp)), char(string(K.wasAdjusted).replace(["true" "false"], ["  (ignored)" ""])))
                'Boresight axis', app.PrincipalAxes.labels{D.Boresight}
                'HPBW E-plane', sprintf('%s°  (%s cut @ %g°)', f(X.HPBW_E), D.Planes.E.type, D.Planes.E.value)
                'HPBW H-plane', sprintf('%s°  (%s cut @ %g°)', f(X.HPBW_H), D.Planes.H.type, D.Planes.H.value)
                'Peak directivity', sprintf('%s dB  (over the sampled %s sr)', f(X.Directivity_dB), f(X.OmegaUsed, 3))
                'Front-to-back', [f(X.FrontBack_dB) ' dB']; 'Radiation efficiency', [f(X.Efficiency_pct) ' %']; 'AR at peak', [f(X.AR_at_peak_dB) ' dB']
                'Parameters', sprintf('L = %g dB, Rx %s (AR %g dB), Pt = %g dBW, R = %g m', E.Params.L, E.Params.RxMode, E.Params.RxAR_dB, E.Params.Pt_dBW, E.Params.R_m)}];
            for n = E.Pattern.Meta.Notes(:).', rows(end+1, :) = {'Note', char(n)}; end
            app.Single_Table_metadata.Data = rows;
        end

        function label = compLabel(app)
            dd = app.Single_DropDown_Component; i = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(i), label = replace(string(dd.Value), '_', ' '); else, label = string(dd.Items{i}); end
        end

        function formatAngular(~, ax, M, phiStep, thetaStep)
            xl = [M.PhiAxis(1), M.PhiAxis(end)]; yl = sort([M.ThetaAxis(1), M.ThetaAxis(end)]);
            set(ax, 'XLim', xl, 'YLim', yl, 'YDir', M.ThetaDir, 'Box', 'on', 'Layer', 'top', 'XTick', xl(1):phiStep:xl(2), 'YTick', yl(1):thetaStep:yl(2));
        end

        function polarTicks(app, pax)
            a = 0:30:330; if app.View.SignedPhi, a(a > 180) = a(a > 180) - 360; end
            pax.ThetaTick = 0:30:330; pax.ThetaTickLabel = compose('%d°', a);
        end
    end

    methods (Access = private)   % ================= MAIN-TAB CALLBACKS, EXPORT, LIFECYCLE =================

        function onLoad(app)
            fp = strtrim(app.Single_EditField_Path.Value);
            if isempty(fp) || ~isfile(fp) || (app.Main > 0 && strcmp(fp, app.Pats(app.Main).Path))   % same path typed again → browse
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern/Gain Files'}, 'Select an antenna pattern file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            app.Single_EditField_Path.Value = fp;
            app.on("source", 'Loading Error', 'Reading file...');
        end

        function onProcess(app)
            if app.Main == 0, uialert(app.UIFigure, 'No file! Load a pattern first.', 'Warning', 'Icon', 'warning'); return; end
            scope = "params"; E = app.Pats(app.Main);
            if isGenericText(E.Path) && ~strcmp(E.Source.Meta.TextFormat, app.Single_DropDown_TextFormat.Value), scope = "source"; end
            app.on(scope, 'Processing Error', 'Re-processing pattern...');
            app.setStatus(app.Single_StatusBar, ['Re-processed <b>' E.File '</b> with current parameters ' char(9989)], true);
        end

        function onPlane(app)
            if app.Main == 0, return; end
            app.setPlane(startsWith(app.Single_Switch_EHplane.Value, 'E')); app.on("view", 'Cut Error');
        end

        function onCutType(app)
            if app.Main > 0, app.applyCutDomain(); end
            app.on("view", 'Cut Error');
        end

        function onPOB(app)
            on = app.Single_CheckBox_POB.Value; if app.Main > 0, app.View.POB = on; end
            for k = 1:5, set([app.Gfx.Full(k).Mark, app.Gfx.Full(k).Tip], 'Visible', on); end
            set([app.Gfx.CutMark, app.Gfx.CutMarkTip], 'Visible', on && app.Main > 0);
        end

        function resetParams(app)
            d = app.Gfx.Defaults;
            [app.Single_Spinner_Loss.Value, app.Single_DropDown_RxPol.Value, app.Single_Spinner_Rw.Value, app.Single_Spinner_Pt.Value, ...
                app.Single_DropDown_Pt.Value, app.Single_Spinner_R.Value, app.Single_DropDown_R.Value] = deal(d{:});
            if app.Main > 0, app.on("params", 'Processing Error'); end
        end

        function toCoverage(app)
            % Main → Coverage: the Coverage tree node references Pats(Main); no copy, no sync (I14).
            if app.Main == 0, return; end
            app.TabGroup.SelectedTab = app.Tab2_Coverage; app.Cov_EditField_filePath.Value = app.Pats(app.Main).Path;
            app.covAddPattern(app.Main);
        end

        function exportResults(app)
            if app.Main == 0, return; end
            E = app.Pats(app.Main);
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Results', fullfile(fileparts(E.Path), [E.Name '_APAT_results.csv']));
            if isequal(f, 0), return; end
            try, writeTable(app.resultsTable(), fullfile(p, f)); app.setStatus(app.Single_StatusBar, ['Results exported to <b>' fullfile(p, f) '</b>'], true);
            catch err, app.showError(err, 'Export Error'); end
        end

        function exportCut(app)
            if app.Main == 0, return; end
            E = app.Pats(app.Main); names = app.cutTraces(); S = app.Cut;
            T = array2table([S.angle(:), S.theta(:), S.phi(:), app.traceValues()], 'VariableNames', [{'Angle_deg', 'Theta_deg', 'Phi_deg'}, cellstr(names)]);
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, 'Export Cut', fullfile(fileparts(E.Path), [E.Name '_cut.csv']));
            if isequal(f, 0), return; end
            try, writeTable(T, fullfile(p, f)); app.setStatus(app.Single_StatusBar, sprintf('Cut (%s @ %g°) exported to <b>%s</b>', S.type, S.fixed, fullfile(p, f)), true);
            catch err, app.showError(err, 'Export Cut Error'); end
        end

        function exportUAN(app)
            % XGTD UAN from the canonical pattern at the current loss; closing φ column added as XGTD expects; maximum_gain = total-gain peak (D29).
            if app.Main == 0 || app.Pats(app.Main).Pattern.IsGainOnly, uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            E = app.Pats(app.Main); P = E.Pattern; s = 10^(E.Params.L/20); Eth = P.Eth*s; Eph = P.Eph*s; ph = P.Phi(:);
            if E.Geometry.PhiPeriodic, Eth(:, end+1) = Eth(:, 1); Eph(:, end+1) = Eph(:, 1); ph(end+1) = ph(1) + 360; end
            dB = @(x) round(20*log10(max(abs(x), eps)), 5); dg = @(x) round(rad2deg(angle(x)), 5);
            T = table(repmat(P.Theta(:), numel(ph), 1), repelem(ph, numel(P.Theta)), dB(Eth(:)), dB(Eph(:)), dg(Eth(:)), dg(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'});
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, 'Export UAN / E-field data', ...
                fullfile(fileparts(E.Path), sprintf('%s_%.5f_%gdeg.uan', E.Name, E.Derived.Peak.value, P.dTheta)));
            if isequal(f, 0), return; end
            try
                if endsWith(f, '.uan', 'IgnoreCase', true), writeUAN(T, fullfile(p, f), P, E.Derived.Peak.value); else, writeTable(T, fullfile(p, f)); end
                app.setStatus(app.Single_StatusBar, ['UAN exported to <b>' fullfile(p, f) '</b>'], true);
            catch err, app.showError(err, 'Export UAN Error'); end
        end

        function startupFcn(app)
            % Every retained graphics object is created here, once: polar axes, colorbars, triads, markers, cut lines, regions, menu, timer.
            app.Single_paxCut = app.place(@polaraxes, app.Single_Grid_Polar, [1 4], 3, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            app.Single_paxPattern = app.place(@polaraxes, app.Single_gridCircular, [1 3], 2, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            g = struct('JetMap', jet(256), 'ARMap', interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)), 'InputKey', '', 'TableKey', '', 'CutKey', '');
            g.Menu = uicontextmenu(app.UIFigure); uimenu(g.Menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, e) delete(findobj(ancestor(e.ContextObject, {'axes', 'polaraxes'}), 'Type', 'datatip')));
            g.Styles = {uistyle('FontWeight', 'bold', 'FontColor', 'black', 'BackgroundColor', [0.8 1 0.8]), uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9])};
            g.Defaults = {app.Single_Spinner_Loss.Value, app.Single_DropDown_RxPol.Value, app.Single_Spinner_Rw.Value, app.Single_Spinner_Pt.Value, app.Single_DropDown_Pt.Value, app.Single_Spinner_R.Value, app.Single_DropDown_R.Value};
            for k = 1:5
                ax = app.(app.Views{k, 2}); app.Single_tabPlots.Children(k).Tag = app.Views{k, 1};   % tab tag ↔ Views row
                s = struct('Axes', ax, 'Kind', string(app.Views{k, 4}), 'Bar', colorbar(ax), 'Surf', gobjects(0), 'Mark', gobjects(0), 'Tip', gobjects(0), 'Over', gobjects(0), 'Key', '');
                ax.ContextMenu = g.Menu; hold(ax, 'on');
                if k >= 3, ax.Interactions = [rotateInteraction, dataTipInteraction]; elseif k == 1, ax.Interactions = [zoomInteraction, dataTipInteraction]; end
                if k == 3 || k == 4   % spatial views: fixed unit box, no axes, XYZ triad
                    axis(ax, 'off'); set(ax, 'Projection', 'orthographic', 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1]);
                    app.drawTriad(ax);
                end
                g.Full(k) = s;
            end
            app.Single_AxesRect.Interactions = [zoomInteraction, dataTipInteraction]; app.Single_AxesRect.ContextMenu = g.Menu;
            hold(app.Single_paxCut, 'on'); hold(app.Single_AxesRect, 'on');
            g.CutPolar = polarplot(app.Single_paxCut, zeros(2, 3), zeros(2, 3), 'LineWidth', 1.4).'; g.CutRect = plot(app.Single_AxesRect, zeros(2, 3), zeros(2, 3), 'LineWidth', 1.4).';
            g.CutMark = [polarplot(app.Single_paxCut, 0, 0, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off'), plot(app.Single_AxesRect, 0, 0, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off')];
            g.HPBWPolar = thetaregion(app.Single_paxCut, [0 0], [1e-3 1e-3], 'FaceColor', '#D95319', 'FaceAlpha', 0.12).'; g.HPBWRect = xregion(app.Single_AxesRect, [0 0], [1e-3 1e-3], 'FaceColor', '#D95319', 'FaceAlpha', 0.12).';
            g.HPBWMark = [polarplot(app.Single_paxCut, zeros(2), zeros(2), 'o', 'Color', '#D95319', 'MarkerFaceColor', '#D95319', 'HandleVisibility', 'off').'; plot(app.Single_AxesRect, zeros(2), zeros(2), 'o', 'Color', '#D95319', 'MarkerFaceColor', '#D95319', 'HandleVisibility', 'off').'];
            g.CutMarkTip = arrayfun(@(h) datatip(h, 'DataIndex', 1, 'HandleVisibility', 'off', 'FontSize', 9), g.CutMark);
            g.HPBWTip = arrayfun(@(h) datatip(h, 'DataIndex', 1, 'HandleVisibility', 'off', 'FontSize', 9), g.HPBWMark);
            set([g.CutPolar g.CutRect g.CutMark g.HPBWPolar g.HPBWRect g.HPBWMark(:).' g.CutMarkTip g.HPBWTip(:).'], 'Visible', 'off');
            app.Gfx = g;
            app.StatusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3);
            app.Status = struct('Main', 'Ready -- load an antenna pattern file to begin 🚀', 'Cov', 'Ready -- load an antenna pattern file to begin 🚀');
            [app.Single_StatusBar.Text, app.Cov_StatusBar.Text] = deal(app.Status.Main);
            hold(app.Cov_Axes, 'on'); grid(app.Cov_Axes, 'on'); set(app.Cov_Axes, 'YLim', [0 100], 'Box', 'on', 'Layer', 'top');
            for grp = ["full" "ar" "cut" "cov" "covX"], app.applyRange(grp, app.Range.(grp), true); end
            app.applyVisibility(); app.covRefresh();
        end

        function drawTriad(~, ax)
            c = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; t = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'}; d = 1.35*eye(3);
            for i = 1:3
                quiver3(ax, 0, 0, 0, d(i, 1), d(i, 2), d(i, 3), 0, 'Color', c{i}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25, 'HandleVisibility', 'off');
                text(ax, 1.12*d(i, 1), 1.12*d(i, 2), 1.12*d(i, 3), t{i}, 'Color', c{i}, 'FontWeight', 'bold');
            end
        end

        function shutdown(app)
            if ~isempty(app.StatusTimer) && isvalid(app.StatusTimer), stop(app.StatusTimer); delete(app.StatusTimer); end
            if ~isempty(app.Dialog) && isvalid(app.Dialog), delete(app.Dialog); end
        end
    end

    methods (Access = public)
        function app = APAT_v3_M8_10
            createComponents(app); registerApp(app, app.UIFigure); runStartupFcn(app, @startupFcn)
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true; app.shutdown();
            if ~isempty(app.UIFigure) && isgraphics(app.UIFigure), delete(app.UIFigure); end
        end
    end

    methods (Access = private)   % ================= COVERAGE TAB =================
        % Tree = job registry. Pattern node: {kind "pattern", k}. Results node: {kind "results", name}.
        % Job node: {kind "job", id, label, short, T, cov, Line, Query}. Nothing else is stored anywhere.

        function node = covTarget(app)
            % Pattern node to act on: the selection (or its pattern ancestor), else the most recently added pattern node.
            node = []; n = app.Cov_Tree.SelectedNodes;
            while ~isempty(n) && isa(n(1), 'matlab.ui.container.TreeNode')
                if isstruct(n(1).NodeData) && n(1).NodeData.kind == "pattern", node = n(1); return; end
                n = n(1).Parent;
            end
            kids = app.Cov_TreeNode_Results.Children;
            for i = numel(kids):-1:1, if isstruct(kids(i).NodeData) && kids(i).NodeData.kind == "pattern", node = kids(i); return; end, end
        end

        function jobs = covJobs(app, roots)
            if nargin < 2, roots = app.Cov_TreeNode_Results; end
            jobs = gobjects(1, 0);
            for n = roots(:).'
                if isstruct(n.NodeData) && n.NodeData.kind == "job", jobs(end+1) = n; else, jobs = [jobs, app.covJobs(n.Children)]; end %#ok<AGROW>
            end
        end

        function covLoad(app)
            % Load a pattern or a coverage-results file on the Coverage tab through the same io_read → pat_build → geo_build → pat_derive chain.
            c = app.readCoverageConfig(); [~, prm] = app.readConfig(); fp = c.Path;
            nodes = app.Cov_TreeNode_Results.Children; paths = arrayfun(@(n) string(app.nodePath(n)), nodes);
            if isempty(fp) || ~isfile(fp) || any(paths == fp)
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.ffd;*.ffe;*.ffs;*.cut;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage data'; '*.*', 'All files'}, 'Select a pattern or coverage results file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            app.Cov_EditField_filePath.Value = fp; hit = find(paths == fp, 1);
            if ~isempty(hit) && nodes(hit).NodeData.kind == "pattern" && isGenericText(fp) && ~strcmp(app.Pats(nodes(hit).NodeData.k).Source.Meta.TextFormat, c.TextFormat)
                for j = app.covJobs(nodes(hit)), delete(j.NodeData.Line); end, delete(nodes(hit)); hit = [];   % generic format changed → reload
            end
            if ~isempty(hit), app.Cov_Tree.SelectedNodes = nodes(hit); app.covSelect(); app.setStatus(app.Cov_StatusBar, 'File already loaded -- node selected.', true); return; end
            S = io_read(fp, c.TextFormat); app.perf("Read file"); app.checkCancelled();
            if S.Meta.IsCoverage, app.covLoadResults(fp, S.Raw); return; end
            E = struct('Name', '', 'File', '', 'Path', fp, 'Source', S, 'Pattern', [], 'Geometry', [], 'Derived', [], 'Params', prm, 'NativeStep', [1 1], 'Stamp', 0);
            [~, E.Name, ext] = fileparts(fp); E.File = [E.Name ext];
            E.Pattern = pat_build(S, 1); E.NativeStep = [E.Pattern.dTheta, E.Pattern.dPhi]; E.Geometry = geo_build(E.Pattern); E.Derived = pat_derive(E.Pattern, E.Geometry, prm); app.perf("Derive");
            app.Stamp = app.Stamp + 1; E.Stamp = app.Stamp;
            k = find(strcmp({app.Pats.Path}, fp), 1); if isempty(k), k = numel(app.Pats) + 1; end
            app.Pats(k) = E; app.covAddPattern(k);
        end

        function p = nodePath(app, n)
            p = ''; if ~isstruct(n.NodeData), return; end
            if n.NodeData.kind == "pattern", p = app.Pats(n.NodeData.k).Path; elseif n.NodeData.kind == "results", p = n.NodeData.path; end
        end

        function covAddPattern(app, k)
            kids = app.Cov_TreeNode_Results.Children;
            hit = kids(arrayfun(@(n) isstruct(n.NodeData) && n.NodeData.kind == "pattern" && n.NodeData.k == k, kids));
            if isempty(hit)
                hit = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📡 ' app.Pats(k).Name]); hit.NodeData = struct('kind', "pattern", 'k', k);
                app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; hit];
            end
            expand(app.Cov_Tree); app.Cov_Tree.SelectedNodes = hit; app.covSelect(); app.covRefresh();
            app.setStatus(app.Cov_StatusBar, sprintf('Pattern "<b>%s</b>" ready to compute coverage (L = %g dB).', app.Pats(k).Name, app.Pats(k).Params.L), false);
        end

        function covCompute(app)
            % Coverage(T) = 100·Ω_R(G > T)/Ω_R on Derived.Cols.(component) at the current parameters (I3, I7). A job is a curve.
            node = app.covTarget(); if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            c = app.readCoverageConfig(); [~, prm] = app.readConfig(); k = node.NodeData.k; E = app.Pats(k);
            if ~isequal(E.Params, prm)   % foreign entry derived at older parameters → re-derive once, commit
                E.Params = prm; E.Derived = pat_derive(E.Pattern, E.Geometry, prm); app.Stamp = app.Stamp + 1; E.Stamp = app.Stamp; app.Pats(k) = E;
            end
            comp = c.Component; if ~isfield(E.Derived.Cols, comp), comp = string(E.Derived.Total); end
            if c.Conical
                mask = util_cosGamma(E.Pattern, c.Cone(1), c.Cone(2)) >= cosd(c.Cone(3)) - 1e-12;
                region = sprintf('Con(%s, α=%s°)', app.coneLabel(c.Cone(1), c.Cone(2)), util_fmtNumber(c.Cone(3)));
            else
                mask = true(size(E.Geometry.dOmega)); region = 'Sph';
            end
            cov = cov_curve(E.Derived.Cols.(comp), E.Geometry.dOmega, mask, c.T); app.perf("Coverage");
            label = sprintf('%s · %s · L=%g dB', region, comp, prm.L);
            app.covAddJob(node, c.T, cov, label, '📉');
            if app.Range.Auto.covX, app.applyRange("covX", [c.T(1) c.T(end)], true); end
            s = sprintf('Run-<b>%d</b> computed: <b>%s</b> on <b>"%s"</b> (%d thresholds, Ω_R = %s sr).', app.CovRunID, region, E.Name, numel(c.T), util_fmtNumber(sum(E.Geometry.dOmega(mask)), 3));
            if ~any(mask, 'all'), s = [s ' <b>Empty region — coverage is 0 %.</b>']; end
            app.setStatus(app.Cov_StatusBar, s, false);
        end

        function covAddJob(app, parent, T, cov, label, icon)
            app.CovRunID = app.CovRunID + 1; label = sprintf('R%d %s', app.CovRunID, label);
            line = plot(app.Cov_Axes, T(:), cov(:), 'LineWidth', 1.6, 'DisplayName', label);
            line.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", 'XData', '%.2f dB'); dataTipTextRow("Coverage", 'YData', '%.2f %%')];
            node = uitreenode(parent, 'Text', [icon ' ' label]);
            node.NodeData = struct('kind', "job", 'id', app.CovRunID, 'label', label, 'short', char(extractBefore(label + " ·", " ·")), ...
                'T', T(:), 'cov', cov(:), 'Line', line, 'Query', gobjects(1, 0));
            expand(parent); app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node]; app.Cov_Panel_Results.Visible = 'on'; app.covRefresh();
        end

        function covLoadResults(app, fp, R)
            [~, name] = fileparts(fp); node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📄 ' name]);
            node.NodeData = struct('kind', "results", 'name', name, 'path', fp); app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node];
            T = R{:, 1}; for j = 2:width(R), app.covAddJob(node, T, R{:, j}, R.Properties.VariableNames{j}, '📈'); end
            if app.Range.Auto.covX, app.applyRange("covX", [min(T) max(T)], true); end
            app.Cov_EditField_filePath.Value = fp; app.TabGroup.SelectedTab = app.Tab2_Coverage;
            app.setStatus(app.Cov_StatusBar, sprintf('Coverage results file "%s" loaded (%d curves).', name, width(R) - 1), false);
        end

        function covRefresh(app)
            % Visibility of lines / query marks from the checked state, legend, table, and every Enable/Visible of the Coverage tab (D53).
            jobs = app.covJobs(); on = ismember(jobs, app.Cov_Tree.CheckedNodes);
            for i = 1:numel(jobs), d = jobs(i).NodeData; set([d.Line, d.Query(isgraphics(d.Query))], 'Visible', on(i)); end
            if any(on), legend(app.Cov_Axes, arrayfun(@(n) n.NodeData.Line, jobs(on)), 'Location', 'southwest', 'Interpreter', 'none'); else, legend(app.Cov_Axes, 'off'); end
            app.Cov_Tabel.Data = app.covTable(jobs(on));
            hasPattern = ~isempty(app.covTarget()); hasJobs = ~isempty(jobs); c = app.readCoverageConfig();
            ctl = app.Cov_gridPanel_Parm.Children; set(ctl, 'Visible', hasPattern, 'Enable', hasPattern);
            set([app.AntennaPatternEditFieldLabel, app.Cov_EditField_filePath, app.Cov_Button_Load], 'Visible', 'on', 'Enable', 'on');
            set([app.Cov_Button_computeCov, app.Cov_DropDown_Component, app.Cov_DropDown_ComponentLabel], 'Visible', 'on', 'Enable', hasPattern);
            q = [app.Cov_QueryCoverageLabel, app.Cov_Spinner_queryCov, app.Cov_Button_queryCov, app.Cov_QueryThresholdLabel, app.Cov_Spinner_queryThresh, app.Cov_Button_queryThresh];
            set([q, app.Cov_Button_Reset, app.Cov_Button_Export, app.Cov_Button_Clear, app.Cov_Button_toMain], 'Visible', 'on', 'Enable', hasJobs || hasPattern);
            set([q, app.Cov_Button_Export, app.Cov_Button_Clear], 'Enable', hasJobs);
            cone = hasPattern && c.Conical;
            set([app.Cov_Spinner_ConeTH, app.Cov_Spinner_ConePH, app.Cov_Spinner_ConeAng, app.ConeSpinnerLabel, app.ConeLabel, app.ConeAngleLabel, app.Cov_DropDown_Orientation, app.Cov_DropDown_OrientationLabel], 'Visible', cone, 'Enable', cone);
            generic = hasPattern && isGenericText(c.Path); set([app.Cov_TextFormatLabel, app.Cov_DropDown_TextFormat], 'Visible', generic, 'Enable', generic);
            app.Cov_Panel_Results.Visible = ~isempty(app.Cov_TreeNode_Results.Children);
        end

        function T = covTable(app, jobs)
            % Rows = union of the checked jobs' thresholds; every cell is cov_at(job, T) (blank outside a curve's range).
            if isempty(jobs), T = table(); return; end
            nd = [jobs.NodeData]; t = unique(vertcat(nd.T)); vals = nan(numel(t), numel(jobs)); names = cell(1, numel(jobs));
            for j = 1:numel(jobs), vals(:, j) = cov_at(jobs(j).NodeData, t); names{j} = [jobs(j).NodeData.short ' %']; end
            T = array2table(compose('%.2f', [t, vals]), 'VariableNames', [{'Threshold (dB)'}, names]); T{:, :} = replace(T{:, :}, 'NaN', '');
        end

        function covSelect(app)
            % Selection: highlight, status, and (for a pattern target) component items + Auto orientation + threshold preset from Derived.
            sel = app.Cov_Tree.SelectedNodes; jobs = app.covJobs();
            for j = jobs, j.NodeData.Line.LineWidth = 1.6 + (~isempty(sel) && isequal(j, sel(1))); end
            node = app.covTarget();
            if ~isempty(node)
                E = app.Pats(node.NodeData.k); [names, labels] = colChoices(E.Derived.Cols, E.Pattern.IsGainOnly); dd = app.Cov_DropDown_Component;
                previous = string(dd.Value); [dd.Items, dd.ItemsData] = deal(cellstr(labels), cellstr(names)); dd.Value = char(prefer(previous, names));
                app.covOrientation();
                if app.Range.Auto.cov, C = E.Derived.Cols.(dd.Value); app.applyRange("cov", util_presetRange(max(C(~E.Derived.Peak.spike), [], 'all')), true); end
            end
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(app.Cov_StatusBar, 'Ready.', false); return; end
            d = sel(1).NodeData;
            if d.kind ~= "job"
                name = ''; if d.kind == "pattern", name = sprintf('%s  (L = %g dB)', app.Pats(d.k).Name, app.Pats(d.k).Params.L); else, name = d.name; end
                app.setStatus(app.Cov_StatusBar, sprintf('%s <b>"%s"</b> -- <b>%d</b> coverage job(s).', char(d.kind), name, numel(sel(1).Children)), false); return
            end
            mx = max(round(d.cov, 2)); i = find(round(d.cov, 2) == mx, 1, 'last'); f = @util_fmtNumber;
            app.setStatus(app.Cov_StatusBar, sprintf('%s | Threshold [%s, %s] dB, step %s dB | <b>50%%</b>-coverage threshold <b>%s dB</b> | max <b>%s%%</b> @ <b>%s dB</b>', ...
                d.label, f(d.T(1)), f(d.T(end)), f(median(diff(d.T))), f(thr_at(d, 50)), f(mx), f(d.T(i))), false);
        end

        function covOrientation(app)
            % Auto → the pattern's boresight (Derived, total gain); an explicit axis sets the cone-centre spinners. Spinners stay authoritative.
            node = app.covTarget(); i = double(app.Cov_DropDown_Orientation.Value);
            if i == 0 && ~isempty(node), i = app.Pats(node.NodeData.k).Derived.Boresight; end
            if i >= 1, [app.Cov_Spinner_ConeTH.Value, app.Cov_Spinner_ConePH.Value] = deal(app.PrincipalAxes.theta(i), app.PrincipalAxes.phi(i)); end
        end

        function label = coneLabel(app, th, ph)
            A = app.PrincipalAxes; i = find(abs(A.theta - th) < 1e-9 & (abs(mod(A.phi - ph, 360)) < 1e-9 | th == 0 | th == 180), 1);
            if isempty(i), label = sprintf('θ=%s°, φ=%s°', util_fmtNumber(th), util_fmtNumber(ph)); else, label = A.labels{i}; end
        end

        function covQuery(app, mode)
            % "Coverage at T" = cov_at; "Threshold at c %" = thr_at; one datatip at the point plus two projection lines (D65, D74).
            sel = app.Cov_Tree.SelectedNodes; if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to query.', true); return; end
            c = app.readCoverageConfig(); jobs = app.covJobs(sel); jobs = jobs(ismember(jobs, app.Cov_Tree.CheckedNodes)); ax = app.Cov_Axes; hit = false;
            for j = jobs
                d = j.NodeData; delete(d.Query(isgraphics(d.Query))); d.Query = gobjects(1, 0);
                if mode == "cov", x = c.QueryT; y = cov_at(d, x); else, y = c.QueryC; x = thr_at(d, y); end
                if isfinite(x) && isfinite(y)
                    col = d.Line.Color;
                    d.Query = [line(ax, [x x], [ax.YLim(1) y], 'Color', col, 'LineStyle', ':', 'HandleVisibility', 'off'), ...
                        line(ax, [ax.XLim(1) x], [y y], 'Color', col, 'LineStyle', ':', 'HandleVisibility', 'off'), ...
                        datatip(d.Line, x, y, 'SnapToDataVertex', 'off', 'HandleVisibility', 'off', 'FontSize', 9)];
                    hit = true;
                end
                j.NodeData = d;
            end
            if hit && mode == "cov", app.setStatus(app.Cov_StatusBar, sprintf('Coverage queried at %s dB.', util_fmtNumber(c.QueryT)), false);
            elseif hit, app.setStatus(app.Cov_StatusBar, sprintf('Threshold queried at %s%% coverage.', util_fmtNumber(c.QueryC)), false);
            else, app.setStatus(app.Cov_StatusBar, 'Query value is outside the selected checked curves.', true); end
        end

        function covClear(app)
            sel = app.Cov_Tree.SelectedNodes; if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to clear.', true); return; end
            for j = app.covJobs(sel)
                d = j.NodeData; delete(d.Query(isgraphics(d.Query))); d.Query = gobjects(1, 0); j.NodeData = d;
                delete(findobj(d.Line, 'Type', 'datatip'));   % user-created tips on this curve (the one permitted findobj for foreign objects)
            end
            app.setStatus(app.Cov_StatusBar, 'Selected DataTips and query markers cleared.', true);
        end

        function covReset(app)
            for j = app.covJobs(), delete(j.NodeData.Query(isgraphics(j.NodeData.Query))); delete(j.NodeData.Line); end
            delete(app.Cov_TreeNode_Results.Children); delete(findobj(app.Cov_Axes, 'Type', 'datatip'));
            if app.Main > 0, app.Pats = app.Pats(app.Main); app.Main = 1; else, app.Pats = struct([]); end   % drop entries only Coverage referenced
            app.CovRunID = 0; app.Cov_Tabel.Data = table(); legend(app.Cov_Axes, 'off');
            app.Range.Auto.cov = true; app.Range.Auto.covX = true; app.applyRange("covX", [-40 10], true); app.applyRange("cov", [-40 10], true);
            app.covRefresh(); app.setStatus(app.Cov_StatusBar, 'Coverage workspace reset 🔄', true);
        end

        function covExport(app)
            if isempty(app.Cov_Tabel.Data), return; end
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Coverage Results', 'coverage_results.csv');
            if isequal(f, 0), return; end
            try, writeTable(app.Cov_Tabel.Data, fullfile(p, f)); app.setStatus(app.Cov_StatusBar, ['Coverage results exported to ' fullfile(p, f)], true);
            catch err, app.showError(err, 'Export Error'); end
        end
    end

    methods (Access = private)   % ================= LAYOUT (declarative; widget set frozen from M7) =================

        function h = place(~, ctor, parent, row, col, varargin)
            h = ctor(parent, varargin{:}); h.Layout.Row = row; h.Layout.Column = col;
        end

        function [lbl, h] = labelled(app, parent, text, row, col, ctor, varargin)
            lbl = app.place(@uilabel, parent, row, col, 'Text', text, 'HorizontalAlignment', 'right');
            h = app.place(ctor, parent, row, col(end) + 1, varargin{:});
        end

        function [tab, g, ax, sl, mn, mx] = patternTab(app, group, name, axesTitle, needsAxes)
            tab = uitab(group, 'Title', name); g = uigridlayout(tab, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'}); ax = [];
            if needsAxes
                ax = app.place(@uiaxes, g, [1 3], 2, 'XLim', [0 360], 'YLim', [0 180], 'YDir', 'reverse', 'XTick', 0:30:360, 'YTick', 0:15:180, 'Box', 'on');
                title(ax, axesTitle); xlabel(ax, 'Phi (degree)'); ylabel(ax, 'Theta (degree)'); colormap(ax, 'jet');
            end
            sl = app.place(@(p, varargin) uislider(p, 'range', varargin{:}), g, 2, 1, 'Limits', app.Hard, 'Value', app.Hard, 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s, ~) app.onRange("full", s.Value));
            mx = app.place(@uispinner, g, 1, 1, 'Limits', app.Hard, 'Value', 100, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRange("full", [app.Range.(app.fullGroup())(1), s.Value]));
            mn = app.place(@uispinner, g, 3, 1, 'Limits', app.Hard, 'Value', -250, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRange("full", [s.Value, app.Range.(app.fullGroup())(2)]));
        end

        function dd = textFormatDropdown(~, parent)
            dd = uidropdown(parent, 'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', '4: POL1=RCP, POL2=LCP — dB magnitude, phase', ...
                '5: POL1=LCP, POL2=RCP — dB magnitude, phase', '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'}, 'Value', 'gain', 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.');
        end

        function createComponents(app)
            redraw = @(~, ~) app.on("view", 'Display Error'); grey = [0.9412 0.9412 0.9412];
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.ReleaseName], 'Visible', 'off', 'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) delete(app));
            app.GridLayout = uigridlayout(app.UIFigure, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.TabGroup = app.place(@uitabgroup, app.GridLayout, 1, 1);
            % ---------------- Tab 1: Process Pattern ----------------
            app.Tab1_Single = uitab(app.TabGroup, 'Title', 'Process Pattern 📡');
            app.Single_Grid = uigridlayout(app.Tab1_Single, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});
            app.Single_Panel_fullPattern = app.place(@uipanel, app.Single_Grid, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'BackgroundColor', grey, 'Visible', 'off');
            app.Single_gridPanel_full = uigridlayout(app.Single_Panel_fullPattern, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_tabPlots = app.place(@uitabgroup, app.Single_gridPanel_full, 1, 1, 'SelectionChangedFcn', @(~, ~) app.onTab());
            [app.Single_tabContour, app.Single_gridContour, app.Single_Axes_Ctr, app.Range_Ctr, app.Range_Ctr_Min, app.Range_Ctr_Max] = app.patternTab(app.Single_tabPlots, 'Contour Plot', 'Antenna Gain Pattern', true);
            [app.Single_tabCircular, app.Single_gridCircular, ~, app.Range_Cir, app.Range_Cir_Min, app.Range_Cir_Max] = app.patternTab(app.Single_tabPlots, 'Circular Contour Plot', '', false);
            [app.Single_tab3DSpherical, app.Single_grid3dSpherical, app.Single_Axes_3dSph, app.Range_3dSph, app.Range_3dSph_Min, app.Range_3dSph_Max] = app.patternTab(app.Single_tabPlots, '3D Spherical Plot', '3D Spherical Plot', true);
            [app.Single_tab3DPolar, app.Single_grid3dPolar, app.Single_Axes_3dPol, app.Range_3dPol, app.Range_3dPol_Min, app.Range_3dPol_Max] = app.patternTab(app.Single_tabPlots, '3D Polar Plot', '3D Polar Plot', true);
            [app.Single_tab3DRect, app.Single_grid3dRect, app.Single_Axes_3dRect, app.Range_3dRect, app.Range_3dRect_Min, app.Range_3dRect_Max] = app.patternTab(app.Single_tabPlots, '3D Surface Plot', '3D Surface (Rectangular) Plot', true);
            app.Single_Panel_Rect = app.place(@uipanel, app.Single_Grid, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'BackgroundColor', grey, 'Visible', 'off');
            app.Single_gridPanel_Cut = uigridlayout(app.Single_Panel_Rect, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_tabCut = app.place(@uitabgroup, app.Single_gridPanel_Cut, 1, 1);
            app.Single_tabPolarPlot = uitab(app.Single_tabCut, 'Title', 'Polar Cut Plot');
            app.Single_Grid_Polar = uigridlayout(app.Single_tabPolarPlot, 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            app.Range_Cut = app.place(@(p, varargin) uislider(p, 'range', varargin{:}), app.Single_Grid_Polar, [2 3], 1, 'Limits', app.Hard, 'Value', app.Hard, 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s, ~) app.onRange("cut", s.Value));
            app.Button_HPBW = app.place(@(p, varargin) uibutton(p, 'state', varargin{:}), app.Single_Grid_Polar, 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'IconAlignment', 'center', 'ValueChangedFcn', redraw);
            app.Label_HPBW = app.place(@uilabel, app.Single_Grid_Polar, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            app.Range_Cut_Min = app.place(@uispinner, app.Single_Grid_Polar, 4, 1, 'Limits', app.Hard, 'Value', -250, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRange("cut", [s.Value, app.Range.cut(2)]));
            app.Range_Cut_Max = app.place(@uispinner, app.Single_Grid_Polar, 1, 1, 'Limits', app.Hard, 'Value', 100, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRange("cut", [app.Range.cut(1), s.Value]));
            app.Button_ExportCut = app.place(@uibutton, app.Single_Grid_Polar, 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.exportCut());
            app.Single_gridEcut = app.place(@uigridlayout, app.Single_Grid_Polar, 3, 4, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x', '1x', '1x'});
            app.CheckBox_Et = app.place(@uicheckbox, app.Single_gridEcut, 1, 1, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', redraw);
            app.CheckBox_Er = app.place(@uicheckbox, app.Single_gridEcut, 2, 1, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', redraw);
            app.CheckBox_El = app.place(@uicheckbox, app.Single_gridEcut, 3, 1, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', redraw);
            app.Single_tabRectPlot = uitab(app.Single_tabCut, 'Title', 'Rectangular Cut Plot');
            app.Single_gridRect = uigridlayout(app.Single_tabRectPlot);
            app.Single_AxesRect = app.place(@uiaxes, app.Single_gridRect, [1 2], [1 2], 'XLim', [0 180], 'XTick', 0:15:180, 'Box', 'on');
            xlabel(app.Single_AxesRect, 'Theta (degree)'); ylabel(app.Single_AxesRect, 'Magnitude (dB)');
            app.Single_DropDown_output = app.place(@uidropdown, app.Single_Grid, 3, [13 14], 'Items', {'Select Output:'}, 'Visible', 'off', 'ValueChangedFcn', @(~, ~) app.onOutputFilter());
            app.Single_tabData = app.place(@uitabgroup, app.Single_Grid, 4, [1 14], 'Visible', 'off', 'SelectionChangedFcn', @(~, ~) app.onTab());
            app.Single_tabDataOut = uitab(app.Single_tabData, 'Title', 'Results 📤', 'ButtonDownFcn', @(~, ~) set(app.Single_DropDown_output, 'Visible', 'on'));
            app.Single_gridDataOut = uigridlayout(app.Single_tabDataOut, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_DataOut = app.place(@uitable, app.Single_gridDataOut, 1, 1, 'BackgroundColor', [1 1 1], 'ColumnWidth', '1x', 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true);
            app.Single_tabDataIn = uitab(app.Single_tabData, 'Title', 'Input 📥');
            app.Single_gridDataIn = uigridlayout(app.Single_tabDataIn, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_DataIn = app.place(@uitable, app.Single_gridDataIn, 1, 1, 'BackgroundColor', [1 1 1], 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true);
            app.MetadataTab = uitab(app.Single_tabData, 'Title', 'Metadata 📋');
            app.Single_gridMetadata = uigridlayout(app.MetadataTab, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_metadata = app.place(@uitable, app.Single_gridMetadata, 1, 1, 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            % Plot control panel
            app.Single_Panel_plotControl = app.place(@uipanel, app.Single_Grid, 2, [13 14], 'Title', 'Plot Control 🎨', 'Visible', 'off');
            c = uigridlayout(app.Single_Panel_plotControl, 'RowHeight', repmat({'fit'}, 1, 15)); app.Single_gridPanel_Ctrl = c;
            [app.ComponentLabel, app.Single_DropDown_Component] = app.labelled(c, 'Component', 1, 1, @uidropdown, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', redraw);
            [app.CuttypeDropDownLabel, app.Single_DropDown_cutType] = app.labelled(c, 'Cut type', 2, 1, @uidropdown, 'Items', {'Phi', 'Theta'}, 'Value', 'Phi', 'ValueChangedFcn', @(~, ~) app.onCutType());
            [app.CutvalueSpinnerLabel, app.Single_DropDown_cutValue] = app.labelled(c, 'Cut value', 3, 1, @uispinner, 'Limits', [0 360], 'Value', 0, 'ValueChangedFcn', redraw);
            [app.CutFieldsLabel, app.CutFieldBasisDropDown] = app.labelled(c, 'Cut fields', 4, 1, @uidropdown, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Value', 'Circular', 'Enable', 'off', 'ValueChangedFcn', redraw);
            [app.ColorbarmaxLabel, app.Single_Plot_Cmax] = app.labelled(c, 'Colorbar max', 5, 1, @uispinner, 'Limits', app.Hard, 'Value', 10, 'ValueChangedFcn', @(~, ~) app.onRange("full", [app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value]));
            [app.ColorbarminLabel, app.Single_Plot_Cmin] = app.labelled(c, 'Colorbar min', 6, 1, @uispinner, 'Limits', app.Hard, 'Value', -40, 'ValueChangedFcn', @(~, ~) app.onRange("full", [app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value]));
            [app.ColorbarstepLabel, app.Single_Plot_Cstep] = app.labelled(c, 'Colorbar step', 7, 1, @uispinner, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', @(~, ~) arrayfun(@(k) app.applyTheme(k), 1:5));
            [app.Single_Label_Clim, app.Single_Button_Clim] = app.labelled(c, 'Adjust Colorbar', 8, 1, @uibutton, 'Text', 'Apply', 'Tooltip', 'Apply to full-pattern plots; cut limits remain independent.', 'ButtonPushedFcn', @(~, ~) app.onRange("full", [app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value]));
            [app.View3DLabel, app.Single_DropDown_3DView] = app.labelled(c, '3D view', 9, 1, @uidropdown, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Value', 'iso', 'Tooltip', 'Camera direction for the 3D pattern tabs.', 'ValueChangedFcn', redraw);
            app.Single_Switch_AngularSpan = app.place(@(p, varargin) uiswitch(p, 'slider', varargin{:}), c, 10, [1 2], 'Items', {['φ span: 0° to 360°' repmat(char(160), 1, 3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'Value', '0° to 360°', 'ValueChangedFcn', @(~, ~) app.onSpan());
            app.Single_Switch_ThetaSpan = app.place(@(p, varargin) uiswitch(p, 'slider', varargin{:}), c, 11, [1 2], 'Items', {'θ span: 0° to 180°', ['−90° to 90°' repmat(char(160), 1, 2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'Value', '0° to 180°', 'ValueChangedFcn', @(~, ~) app.onSpan());
            app.Single_Switch_EHplane = app.place(@(p, varargin) uiswitch(p, 'slider', varargin{:}), c, 12, [1 2], 'Items', {[repmat(char(160), 1, 8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'Value', 'E-Plane cut', 'ValueChangedFcn', @(~, ~) app.onPlane());
            app.Singel_CheckBox_overlayCut = app.place(@uicheckbox, c, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', redraw);
            app.Single_CheckBox_POB = app.place(@uicheckbox, c, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', @(~, ~) app.onPOB());
            app.Single_CheckBox_HPBWBounds = app.place(@uicheckbox, c, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', redraw);
            app.Single_StatusBar = app.place(@uilabel, app.Single_Grid, 5, [1 14], 'Interpreter', 'html', 'Text', 'Ready 🚀', 'Tag', 'Main');
            % Inputs & parameters panel
            app.Single_panelParam = app.place(@uipanel, app.Single_Grid, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️');
            g = uigridlayout(app.Single_panelParam, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'}); app.Single_gridPanel_Param = g;
            [app.InputPatternLabel, app.Single_EditField_Path] = app.labelled(g, 'Input Pattern:', 1, 1, @uieditfield); app.Single_EditField_Path.Layout.Column = [2 8];
            [app.RxPolLabel, app.Single_DropDown_RxPol] = app.labelled(g, 'Rw Sense', 3, 1, @uidropdown, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Value', 'Auto', 'Editable', 'on', 'Visible', 'off'); app.RxPolLabel.Visible = 'off';
            [app.IncidentWaveARRwPLFLabel, app.Single_Spinner_Rw] = app.labelled(g, 'Rw (dB)', 3, 3, @uispinner, 'Value', 6, 'Visible', 'off'); app.IncidentWaveARRwPLFLabel.Visible = 'off';
            [app.LossindBLabel, app.Single_Spinner_Loss] = app.labelled(g, 'Loss (−) / Gain (+) dB', 3, 5, @uispinner, 'Step', 0.1, 'Visible', 'off'); app.LossindBLabel.Visible = 'off';
            [app.TransmitPowerLabel, app.Single_Spinner_Pt] = app.labelled(g, 'Tx Pwr (Pt)', 3, 7, @uispinner, 'Value', 0, 'Visible', 'off'); app.TransmitPowerLabel.Visible = 'off';
            app.Single_DropDown_Pt = app.place(@uidropdown, g, 3, 9, 'Items', {'dBW', 'dBm', 'Watts'}, 'Value', 'dBW', 'Visible', 'off');
            [app.DistanceLabel, app.Single_Spinner_R] = app.labelled(g, 'Distance', 3, 10, @uispinner, 'Value', 1, 'Visible', 'off'); app.DistanceLabel.Visible = 'off';
            app.Single_DropDown_R = app.place(@uidropdown, g, 3, 12, 'Items', {'m', 'km'}, 'Value', 'm', 'Visible', 'off');
            app.Single_Button_Load = app.place(@uibutton, g, 1, [11 12], 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.onLoad());
            app.Single_Button_Process = app.place(@uibutton, g, 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', @(~, ~) app.onProcess());
            app.Single_Button_ResetParams = app.place(@uibutton, g, 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', @(~, ~) app.resetParams());
            [app.TextFormatLabel, app.Single_DropDown_TextFormat] = app.labelled(g, 'Format:', 2, [4 5], @app.textFormatDropdown); app.Single_DropDown_TextFormat.Layout.Column = [6 8];
            set([app.TextFormatLabel, app.Single_DropDown_TextFormat], 'Visible', 'off'); app.Single_DropDown_TextFormat.ValueChangedFcn = @(~, ~) app.onProcess();
            app.Single_DropDown_step = app.place(@uidropdown, g, 2, [9 10], 'Items', {'STEP'}, 'Placeholder', 'STEP', 'Enable', 'off', 'Visible', 'off', 'ValueChangedFcn', @(~, ~) app.on("build", 'Step Error', 'Resampling...'));
            app.Single_Export_Output = app.place(@uibutton, g, 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.exportResults());
            app.Single_Export_UAN = app.place(@uibutton, g, 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.exportUAN());
            [app.FFDFreqDropDownLabel, app.Single_DropDown_FFD] = app.labelled(g, 'FFD Freq:', 1, 9, @uidropdown, 'Items', {'Frequencies'}, 'Enable', 'off', 'Visible', 'off', 'ValueChangedFcn', @(~, ~) app.on("build", 'Frequency Error', 'Switching block...'));
            set([app.FFDFreqDropDownLabel], 'Enable', 'off', 'Visible', 'off');
            app.Single_Button_Coverage = app.place(@uibutton, g, 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.toCoverage());
            % ---------------- Tab 2: Compute Coverage ----------------
            app.Tab2_Coverage = uitab(app.TabGroup, 'Title', 'Compute Coverage 📈');
            app.Cov_Grid = uigridlayout(app.Tab2_Coverage, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            app.Cov_Panel_Param = app.place(@uipanel, app.Cov_Grid, 1, [1 5], 'Title', 'Inputs & Parameters 🎛️');
            p = uigridlayout(app.Cov_Panel_Param, 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'}); app.Cov_gridPanel_Parm = p;
            app.Cov_ButtonGroup_CovType = app.place(@uibuttongroup, p, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', @(~, ~) app.covRefresh());
            app.Cov_ButtonGroup_Btn_Spherical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            app.Cov_ButtonGroup_Btn_Conical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            [app.Cov_DropDown_OrientationLabel, app.Cov_DropDown_Orientation] = app.labelled(p, 'Orientation 🧭:', 3, 1, @uidropdown, 'Items', [{'Auto'}, app.PrincipalAxes.labels], 'ItemsData', 0:6, 'Value', 0, 'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.covOrientation());
            [app.AntennaPatternEditFieldLabel, app.Cov_EditField_filePath] = app.labelled(p, 'Antenna Pattern:', 1, 3, @uieditfield); app.Cov_EditField_filePath.Layout.Column = [4 8];
            app.Cov_Button_Load = app.place(@uibutton, p, 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', @(~, ~) app.on("covSource", 'Coverage Load Error', 'Reading file...'));
            app.Cov_Button_computeCov = app.place(@uibutton, p, 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.on("covRun", 'Coverage Error'));
            app.Cov_Button_Reset = app.place(@uibutton, p, 2, 9, 'Text', '🔄 Reset', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.covReset());
            app.Cov_Button_Export = app.place(@uibutton, p, 2, 10, 'Text', '💾 Export Results', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.covExport());
            [app.ThresholdMindBSpinnerLabel, app.Cov_Spinner_ThreshMin] = app.labelled(p, 'Threshold  Min (dB):', 2, 3, @uispinner, 'Value', -40, 'ValueChangedFcn', @(s, ~) app.onRange("cov", [s.Value, app.Cov_Spinner_ThreshMax.Value]));
            [app.ThresholdMaxdBSpinnerLabel, app.Cov_Spinner_ThreshMax] = app.labelled(p, 'Threshold  Max (dB):', 2, 5, @uispinner, 'Value', 10, 'ValueChangedFcn', @(s, ~) app.onRange("cov", [app.Cov_Spinner_ThreshMin.Value, s.Value]));
            [app.StepdBSpinnerLabel, app.Cov_Spinner_Step] = app.labelled(p, 'Step (dB):', 2, 7, @uispinner, 'Value', 1, 'Limits', [0.1 100]);
            [app.ConeSpinnerLabel, app.Cov_Spinner_ConeTH] = app.labelled(p, 'Cone θ₀ (°):', 3, 3, @uispinner, 'Limits', [0 180], 'Enable', 'off');
            [app.ConeLabel, app.Cov_Spinner_ConePH] = app.labelled(p, 'Cone φ₀ (°):', 3, 5, @uispinner, 'Limits', [0 360], 'Enable', 'off');
            [app.ConeAngleLabel, app.Cov_Spinner_ConeAng] = app.labelled(p, 'Cone Angle α (°):', 3, 7, @uispinner, 'Limits', [0 180], 'Value', 45, 'Enable', 'off');
            app.Cov_Button_Clear = app.place(@uibutton, p, 3, 9, 'Text', '🧹 Clear DataTips', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.covClear());
            app.Cov_Button_toMain = app.place(@uibutton, p, 3, 10, 'Text', '📊 To Main ◀ ', 'ButtonPushedFcn', @(~, ~) set(app.TabGroup, 'SelectedTab', app.Tab1_Single));
            [app.Cov_DropDown_ComponentLabel, app.Cov_DropDown_Component] = app.labelled(p, 'Component:', 4, 1, @uidropdown, 'Items', {'E_Total_dB'}, 'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.covSelect());
            [app.Cov_QueryCoverageLabel, app.Cov_Spinner_queryCov] = app.labelled(p, 'Coverage @ dB:', 4, 3, @uispinner, 'ValueDisplayFormat', '%g dB', 'Visible', 'off');
            app.Cov_Button_queryCov = app.place(@uibutton, p, 4, 5, 'Text', '⯐ Query Coverage', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.covQuery("cov"));
            [app.Cov_QueryThresholdLabel, app.Cov_Spinner_queryThresh] = app.labelled(p, 'Threshold @ %:', 4, 6, @uispinner, 'ValueDisplayFormat', '%g%%', 'Value', 50, 'Visible', 'off');
            app.Cov_Button_queryThresh = app.place(@uibutton, p, 4, 8, 'Text', '🔍︎ Query Threshold', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.covQuery("thr"));
            [app.Cov_TextFormatLabel, app.Cov_DropDown_TextFormat] = app.labelled(p, 'Format:', 4, 9, @app.textFormatDropdown); app.Cov_DropDown_TextFormat.ValueChangedFcn = @(~, ~) app.on("covSource", 'Coverage Format Error', 'Re-reading file...');
            app.Cov_StatusBar = app.place(@uilabel, app.Cov_Grid, 3, [1 5], 'Interpreter', 'html', 'Text', 'Ready 🚀', 'Tag', 'Cov');
            app.Cov_Panel_Results = app.place(@uipanel, app.Cov_Grid, 2, [1 5], 'Title', 'Results', 'Visible', 'off');
            r = uigridlayout(app.Cov_Panel_Results, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'}); app.GridLayout2 = r;
            app.Cov_Axes = app.place(@uiaxes, r, 1, [2 4], 'Interactions', dataTipInteraction);
            title(app.Cov_Axes, 'Coverage vs Threshold  —  Coverage(T) = 100·Ω_R(G > T)/Ω_R'); xlabel(app.Cov_Axes, 'Threshold (dB)'); ylabel(app.Cov_Axes, 'Coverage (%)');
            app.Cov_Tree = app.place(@(pp, varargin) uitree(pp, 'checkbox', varargin{:}), r, [1 2], 1, 'SelectionChangedFcn', @(~, ~) app.covSelect(), 'CheckedNodesChangedFcn', @(~, ~) app.covRefresh());
            app.Cov_TreeNode_Results = uitreenode(app.Cov_Tree, 'Text', 'Coverage Results');
            app.Cov_Tabel = app.place(@uitable, r, [1 2], 5, 'ColumnWidth', '1x', 'RowName', {});
            app.Cov_Spinner_XRange = app.place(@(pp, varargin) uislider(pp, 'range', varargin{:}), r, 2, 3, 'Limits', app.Hard, 'Value', [-40 10], 'ValueChangedFcn', @(~, e) app.onRange("covX", e.Value), 'ValueChangingFcn', @(~, e) app.onRange("covX", e.Value));
            app.Cov_Spinner_XMax = app.place(@uispinner, r, 2, 4, 'Limits', app.Hard, 'Value', 10, 'ValueChangedFcn', @(s, ~) app.onRange("covX", [app.Cov_Spinner_XMin.Value, s.Value]));
            app.Cov_Spinner_XMin = app.place(@uispinner, r, 2, 2, 'Limits', app.Hard, 'Value', -40, 'ValueChangedFcn', @(s, ~) app.onRange("covX", [s.Value, app.Cov_Spinner_XMax.Value]));
            app.UIFigure.Visible = 'on';
        end

        function onTab(app)
            if app.Main > 0, app.renderFull(app.visibleView()); app.renderTables(); end
        end

        function onSpan(app)
            % Keep the physical cut when the display convention changes: re-express the cut value through the new Map.
            if app.Main > 0
                [type, val] = app.cutSpec(app.View); V = app.readConfig(); app.applyCutDomain(); v = val;
                if type == "Phi" && V.Elevation, v = 90 - val; elseif type == "Theta" && V.SignedPhi && val >= 180, v = val - 360; end
                app.Single_DropDown_cutValue.Value = v;
            end
            app.on("view", 'Display Error');
        end
    end
end

%% ============================== FILE-SCOPE: READERS ==============================
% Every reader returns a Source: Raw (table shown on the Input tab), Blocks (cell of long tables: Theta, Phi, then
% Re_Eth Im_Eth Re_Eph Im_Eph or the gain columns), Freqs (Hz per block) and Meta {Format, Unit, UnitLabel, IsGainOnly,
% IsCoverage, TextFormat, Notes}. Every heuristic decision is one sentence in Meta.Notes, shown in Metadata.

function S = io_read(fp, textFormat)
[~, ~, ext] = fileparts(fp); ext = lower(erase(ext, '.'));
S = struct('Raw', table(), 'Blocks', {{}}, 'Freqs', NaN, 'Meta', struct('Format', "", 'Unit', "dB", 'UnitLabel', "dB", ...
    'IsGainOnly', false, 'IsCoverage', false, 'TextFormat', char(textFormat), 'Notes', strings(1, 0)));
switch ext
    case {'xlsx', 'xls'},        S = io_excel(fp, S);
    case {'csv', 'txt', 'dat'},  S = io_generic(fp, string(textFormat), S);
    case 'cut',                  S = io_cut(fp, S);
    case {'uan', 'fz', 'out', 'ffs', 'ffe', 'ffd'}, S = io_farfield(fp, ext, S);
    otherwise, error('APAT:Unsupported', 'Unsupported format: .%s', ext);
end
if S.Meta.Unit == "dBi", S.Meta.UnitLabel = "dBi"; elseif ~S.Meta.IsGainOnly && ~S.Meta.IsCoverage, S.Meta.UnitLabel = "dB (rel. field)"; end
end

function tf = isGenericText(fp), [~, ~, e] = fileparts(fp); tf = any(strcmpi(e, {'.csv', '.txt', '.dat'})); end

function [M, blk, freqs, text, other] = io_scan(fp)
%IO_SCAN One pass over a text far-field file: numeric rows with the modal column count (M), a block index per row (a line
%   declaring a frequency starts a new block), every declared frequency, the non-numeric header text, and the remaining
%   numeric lines (e.g. the two HFSS axis triples). Replaces per-format header sniffing.
L = strtrim(readlines(fp));
isNum = strlength(L) > 0 & ~cellfun('isempty', regexp(L, '^[-+.\d][-+\d.eEdD\s,;]*$', 'once'));
tok = regexp(L(isNum), '[-+]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][-+]?\d+)?', 'match');
n = cellfun(@numel, tok); nc = mode(n(n >= 4));
if isempty(nc) || isnan(nc), error('APAT:NoData', 'No numeric data rows (≥ 4 columns) found in %s.', fp); end
keep = n == nc; M = str2double(replace(vertcat(tok{keep}), ["d" "D"], "e"));
fl = regexp(L, '^[#/*\s]*frequenc(?:y|ies)\b[^-+\d]*(.*)$', 'tokens', 'once', 'ignorecase'); isF = ~cellfun('isempty', fl);
freqs = cellfun(@(c) sscanf(char(c{1}), '%f').', fl(isF), 'UniformOutput', false);
b = cumsum(isF); rows = find(isNum); [~, ~, blk] = unique(b(rows(keep)));
text = L(~isNum); other = cellfun(@(t) str2double(t), tok(~keep), 'UniformOutput', false);
end

function [Eth, Eph] = io_fields(A, domain, basis)
%IO_FIELDS Four field columns → complex Eθ, Eφ. domain: "magphase" (dB, deg; columns mag1 ph1 mag2 ph2) | "rect" (re1 im1 re2 im2).
if domain == "magphase", c1 = 10.^(A(:, 1)/20) .* exp(1i*deg2rad(A(:, 2))); c2 = 10.^(A(:, 3)/20) .* exp(1i*deg2rad(A(:, 4)));
else, c1 = complex(A(:, 1), A(:, 2)); c2 = complex(A(:, 3), A(:, 4)); end
switch basis
    case "thetaphi", Eth = c1; Eph = c2;
    case "rcplcp",   [Eth, Eph] = pol_fromCircular(c1, c2);
    case "lcprcp",   [Eth, Eph] = pol_fromCircular(c2, c1);
end
end

function S = io_farfield(fp, ext, S)
%IO_FARFIELD UAN/FZ, OUT, FFS, FFE, FFD through one scanner and one spec row: {format, column order → [θ φ a b c d], domain, basis, unit, raw names}.
spec = struct( ...
    'uan', {{'XGTD UAN',        [1 2 3 5 4 6], "magphase", "thetaphi", "dBi", {'Theta','Phi','E_TH_dB','E_PH_dB','E_TH_deg','E_PH_deg'}}}, ...
    'fz',  {{'XGTD FZ',         [1 2 3 5 4 6], "magphase", "thetaphi", "dBi", {'Theta','Phi','E_TH_dB','E_PH_dB','E_TH_deg','E_PH_deg'}}}, ...
    'out', {{'TICRA/GRASP OUT', [1 2 3 4 5 6], "rect",     "rcplcp",   "dBi", {'Theta','Phi','Re_RHCP','Im_RHCP','Re_LHCP','Im_LHCP'}}}, ...
    'ffs', {{'CST FFS',         [2 1 3 4 5 6], "rect",     "thetaphi", "dB",  {'Phi','Theta','Re_Eth','Im_Eth','Re_Eph','Im_Eph'}}}, ...
    'ffe', {{'FEKO FFE',        [1 2 3 4 5 6], "rect",     "thetaphi", "dB",  {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'}}}, ...
    'ffd', {{'HFSS FFD',        [1 2 3 4 5 6], "rect",     "thetaphi", "dB",  {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'}}});
[S.Meta.Format, order, domain, basis, S.Meta.Unit, rawNames] = spec.(ext){:};
[M, blk, freqs, text, other] = io_scan(fp); v = [];
switch ext
    case {'uan', 'fz'}   % header assertions (D21): the only supported declarations are dB magnitude, degree phase, theta/phi polarisation
        hdr = lower(strjoin(text, newline));
        bad = (contains(hdr, 'polarization') && ~contains(hdr, 'theta_phi')) || (contains(hdr, 'magnitude') && ~contains(hdr, 'db'));
        if bad, error('APAT:UnsupportedUAN', 'UAN header declares an unsupported convention (APAT reads theta_phi polarization and dB magnitude).'); end
    case 'ffe', v = cellfun(@(x) x(1), freqs);
    case 'ffd'           % header = two axis triples (start stop count); blocks are consecutive grids; frequencies from header list and/or separators
        tri = other(cellfun(@numel, other) == 3);
        if numel(tri) < 2, error('APAT:FFD', 'FFD header (theta/phi start stop count) not found.'); end
        th = linspace(tri{1}(1), tri{1}(2), round(tri{1}(3))).'; ph = linspace(tri{2}(1), tri{2}(2), round(tri{2}(3))).'; n = numel(th)*numel(ph);
        if mod(size(M, 1), n) ~= 0 || size(M, 2) < 4, error('APAT:FFD', 'FFD row count (%d) does not match the %d×%d θ/φ grid.', size(M, 1), numel(th), numel(ph)); end
        nb = size(M, 1)/n; blk = repelem((1:nb).', n); M = [repmat([repelem(th, numel(ph)), repmat(ph, numel(th), 1)], nb, 1), M(:, 1:4)];
        v = [freqs{:}]; if numel(v) == nb + 1 && v(1) == round(v(1)), v(1) = []; end   % leading "Frequencies N" is a count
end
if size(M, 2) < 6, error('APAT:Columns', '%s data rows have %d columns; six are required.', S.Meta.Format, size(M, 2)); end
nb = max(blk); S.Freqs = nan(1, nb); if numel(v) == nb, S.Freqs = v(:).'; end
for b = 1:nb
    R = M(blk == b, order); [Eth, Eph] = io_fields(R(:, 3:6), domain, basis);
    S.Blocks{b} = table(R(:, 1), R(:, 2), real(Eth), imag(Eth), real(Eph), imag(Eph), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end
S.Raw = array2table(M(blk == 1, 1:6), 'VariableNames', rawNames);
if nb > 1, S.Meta.Notes(end+1) = sprintf('%d frequency blocks found; each is selectable in the frequency dropdown.', nb); end
end

function S = io_generic(fp, fmt, S)
%IO_GENERIC CSV/TXT/DAT: coverage-results table, gain-only pattern, or six-column E-field table in the selected textFormat.
opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvartype(opts, 'double'); opts = setvaropts(opts, 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
T = readtable(fp, opts); nc = width(T);
if nc < 2 || isempty(T), error('APAT:InvalidFormat', 'File needs at least two numeric columns.'); end
names = string(T.Properties.VariableNames); low = lower(names); hasHdr = ~all(startsWith(names, "Var"));
if fmt == "gain", used = 1:nc; else, used = 1:min(nc, 6); end
T = rmmissing(T, 'DataVariables', used); c1 = T{:, 1}; c2 = T{:, 2};              % drop rows only for NaN in used columns (D24)
kw = contains(low(1), "threshold") || any(contains(low(2:end), "coverage"));
isCov = kw || (~hasHdr && fmt == "gain" && nc < 6 && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictascend') && issorted(c2, 'descend'));   % a CCDF is non-increasing (D27)
if isCov
    if ~hasHdr, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:nc - 1))]; end
    S.Raw = T; S.Meta.IsCoverage = true; S.Meta.Format = "Coverage results"; return
end
if fmt == "gain"
    S.Meta.IsGainOnly = true; S.Meta.Format = "Generic text (gain)";
    ith = find(contains(low(1:2), ["theta" "elev"]), 1); iph = find(contains(low(1:2), ["phi" "azim"]), 1);
    if isempty(ith) || isempty(iph) || ith == iph
        wide = 1 + (max(c1) - min(c1) < max(c2) - min(c2)); ith = 3 - wide; iph = wide;    % wider span = φ (D25, disclosed)
        S.Meta.Notes(end+1) = sprintf('Axis order inferred from span: column %d = φ (wider span), column %d = θ.', iph, ith);
    end
    if any(contains(low, "dbi")), S.Meta.Unit = "dBi"; S.Meta.Notes(end+1) = "Level unit dBi taken from the column header."; else, S.Meta.Notes(end+1) = "Gain-only text file without a unit header: levels are shown in dB."; end
    B = T(:, [ith, iph, setdiff(1:nc, [ith iph])]); B.Properties.VariableNames(1:2) = {'Theta', 'Phi'};
    B.Properties.VariableNames(3:end) = matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(B.Properties.VariableNames(3:end)), {'Theta', 'Phi'});
    S.Raw = T; S.Blocks = {B}; return
end
if nc < 6, error('APAT:TextEFieldColumns', 'The selected generic E-field format requires six numeric columns.'); end
domain = "rect"; if endsWith(fmt, "magphase"), domain = "magphase"; end
basis = "thetaphi"; if startsWith(fmt, "rcp"), basis = "rcplcp"; elseif startsWith(fmt, "lcp"), basis = "lcprcp"; end
A = T{:, 3:6}; layout = "interleaved";
if domain == "magphase"          % columns are mag1 ph1 mag2 ph2 (interleaved) or mag1 mag2 ph1 ph2 (grouped): header names first, then range rule (D26)
    ph = contains(low(3:6), ["deg" "phase"]);
    if isequal(ph, [false true false true]), layout = "interleaved"; elseif isequal(ph, [false false true true]), layout = "grouped";
    else
        big = max(abs(A), [], 1, 'omitnan') > 100; if big(2) && ~big(3), layout = "interleaved"; else, layout = "grouped"; end
        S.Meta.Notes(end+1) = sprintf('Magnitude/phase column layout "%s" inferred from value ranges (|phase| > 100).', layout);
    end
    if layout == "grouped", A = A(:, [1 3 2 4]); end
end
[Eth, Eph] = io_fields(A, domain, basis);
S.Meta.Format = sprintf('Generic text (%s, %s)', fmt, layout);
if ~hasHdr
    comp = ["E_TH" "E_PH"]; if basis ~= "thetaphi", comp = ["POL1" "POL2"]; end
    if domain == "magphase", fn = [comp + "_dB", comp + "_deg"]; if layout == "interleaved", fn = fn([1 3 2 4]); end, else, fn = [comp(1) + ["_real" "_imag"], comp(2) + ["_real" "_imag"]]; end
    T.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", fn]);
end
S.Raw = T; S.Blocks = {table(c1, c2, real(Eth), imag(Eth), real(Eph), imag(Eph), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'})};
end

function S = io_cut(fp, S)
%IO_CUT TICRA/GRASP .cut: repeated blocks [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data]. ICOMP 1 = θ/φ, 2 = RHCP/LHCP (D19).
S.Meta.Format = "TICRA/GRASP CUT"; L = readlines(fp); L(strlength(strtrim(L)) == 0) = [];
th = {}; ph = {}; D = {}; i = 1;
while i < numel(L)
    p = sscanf(L(i + 1), '%f'); if numel(p) < 7, error('APAT:CUT', 'Could not parse cut parameter line %d.', i + 1); end
    n = p(3); blockData = reshape(sscanf(strjoin(L(i + 2:i + 1 + n), ' '), '%f'), 2*p(7), []).';
    th{end+1, 1} = p(1) + (0:n - 1).'*p(2); ph{end+1, 1} = repmat(p(4), n, 1); D{end+1, 1} = blockData(:, 1:4); i = i + 2 + n; %#ok<AGROW>
end
icomp = p(5); theta = vertcat(th{:}); phi = vertcat(ph{:}); M = vertcat(D{:});
if ~any(icomp == [1 2]), error('APAT:UnsupportedICOMP', 'GRASP cut ICOMP = %d is not supported (1 = theta/phi, 2 = RHCP/LHCP).', icomp); end
if p(6) == 2, [theta, phi] = deal(phi, theta); S.Meta.Notes(end+1) = "ICUT = 2: φ swept, θ constant per block."; end
if isscalar(unique(phi))           % single cut → body of revolution at 10° φ steps (§15-5), disclosed
    theta = repmat(theta, 36, 1); M = repmat(M, 36, 1); phi = repelem((0:10:350).', numel(phi));
    S.Meta.Notes(end+1) = "Single cut in file: pattern synthesised as a body of revolution (φ = 0:10:350).";
end
if icomp == 2, [Eth, Eph] = pol_fromCircular(complex(M(:, 1), M(:, 2)), complex(M(:, 3), M(:, 4))); raw = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'};
else, Eth = complex(M(:, 1), M(:, 2)); Eph = complex(M(:, 3), M(:, 4)); raw = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; end
S.Raw = array2table([theta phi M], 'VariableNames', [{'Theta', 'Phi'}, raw]);
S.Blocks = {table(theta, phi, real(Eth), imag(Eth), real(Eph), imag(Eph), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'})};
end

function S = io_excel(fp, S)
%IO_EXCEL Matrix workbooks: sheet 1 = summary, fixed component sheets (dBi magnitude / degree phase), C3-origin matrices.
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi" "RHCP_Phase_degrees" "LHCP_Gain_dBi" "LHCP_Phase_degrees"]; lin = ["Etheta_Gain_dBi" "Etheta_Phase_degrees" "Ephi_Gain_dBi" "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
if ~(hasC || hasL), error('APAT:ExcelMatrixFormat', 'Unsupported workbook: no Etheta/Ephi or RHCP/LHCP component sheets found.'); end
req = [circ(1:4*hasC) lin(1:4*hasL)]; S.Meta.Format = sprintf('Excel Matrix Format %d', 1*(hasL && ~hasC) + 2*(hasC && ~hasL) + 3*(hasC && hasL)); S.Meta.Unit = "dBi";
X = struct(); th = []; ph = [];
for k = 1:numel(req)
    sheet = sheets(find(strcmpi(sheets, req(k)), 1)); [t, p, X.(req(k))] = xl_matrix(fp, sheet);
    if k == 1, th = t; ph = p; elseif ~isequal(size(t), size(th)) || any(abs(t - th) > 1e-9, 'all') || any(abs(p - ph) > 1e-9, 'all')
        error('APAT:ExcelMatrixGrid', 'All component sheets must share the same theta/phi grid.');
    end
end
mp = @(g, f) 10.^(X.(g)/20) .* exp(1i*deg2rad(X.(f)));
if hasL, Eth = mp("Etheta_Gain_dBi", "Etheta_Phase_degrees"); Eph = mp("Ephi_Gain_dBi", "Ephi_Phase_degrees");
else, [Eth, Eph] = pol_fromCircular(mp("RHCP_Gain_dBi", "RHCP_Phase_degrees"), mp("LHCP_Gain_dBi", "LHCP_Phase_degrees")); end
[P, T] = meshgrid(ph, th); vals = cellfun(@(f) X.(f)(:), cellstr(req), 'UniformOutput', false);
S.Raw = table(T(:), P(:), vals{:}, 'VariableNames', [{'Theta', 'Phi'}, cellstr(req)]);
S.Blocks = {table(T(:), P(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'})};
S.Freqs = 1e6 * xl_lookup(fp, sheets(1), 'Pattern Simulation Freq (MHz):');
end

function [theta, phi, data] = xl_matrix(fp, sheet)
% One C3-origin matrix: row 2 (C onward) = φ, column B (row 3 onward) = θ. readcell keeps worksheet coordinates.
C = readcell(fp, 'Sheet', char(sheet)); isnum = @(x) isnumeric(x) && isscalar(x) && isfinite(x);
if size(C, 1) < 3 || size(C, 2) < 3, error('APAT:ExcelMatrixSheet', 'Sheet "%s" has no C3-origin matrix.', sheet); end
pm = cellfun(isnum, C(2, 3:end)); tm = cellfun(isnum, C(3:end, 2)); nP = find(~pm, 1) - 1; nT = find(~tm, 1) - 1;
if isempty(nP), nP = numel(pm); end, if isempty(nT), nT = numel(tm); end
if any(pm(nP + 1:end)) || any(tm(nT + 1:end)), error('APAT:ExcelMatrixAxis', 'Sheet "%s" has a gap in its theta/phi axis.', sheet); end
phi = cell2mat(C(2, 3:2 + nP)); theta = cell2mat(C(3:2 + nT, 2)); block = C(3:2 + nT, 3:2 + nP);
if ~all(cellfun(isnum, block), 'all'), error('APAT:ExcelMatrixSheet', 'Sheet "%s" contains non-numeric matrix samples.', sheet); end
data = cell2mat(block);
if any(diff(theta) <= 0) || any(diff(phi) <= 0) || theta(1) < -1e-9 || theta(end) > 180 + 1e-9 || phi(1) < -1e-9 || phi(end) >= 360
    error('APAT:ExcelMatrixAxis', 'Sheet "%s": axes must be strictly increasing with θ ∈ [0,180], φ ∈ [0,360).', sheet);
end
end

function v = xl_lookup(fp, sheet, label)
% Numeric value to the right of a labelled summary cell; NaN when absent. Replaces the 164-line summary parser (D30).
v = NaN;
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
[r, c] = find(cellfun(@(x) (ischar(x) || isstring(x)) && strcmpi(strtrim(string(x)), label), C), 1);
if isempty(r), return; end
for k = c + 1:size(C, 2), if isnumeric(C{r, k}) && isscalar(C{r, k}) && isfinite(C{r, k}), v = C{r, k}; return; end, end
end

function writeTable(T, fp)
if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
end

function writeUAN(T, fp, P, maxGain)
% XGTD UAN header (free format, mag_phase, dB, theta_phi) followed by the six tab-delimited columns.
header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\ncomplex\nmag_phase\n' ...
    'pattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
    min(T.Phi), max(T.Phi), P.dPhi, min(T.Theta), max(T.Theta), P.dTheta, maxGain);
writelines(header, fp); writetable(T, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
end

%% ============================== FILE-SCOPE: NUMERICAL CORE ==============================

function P = pat_build(S, f)
%PAT_BUILD Canonical grid-native pattern from Source block f (I1): polar θ ascending in [0,180], φ ascending in [0,360),
%   uniform steps asserted once, matrices nθ×nφ filled by index arithmetic. Angles snap to 5 decimals; values are never rounded (D03).
T = S.Blocks{f}; th = T.Theta; ph = T.Phi; V = T{:, 3:end}; names = string(T.Properties.VariableNames(3:end)); notes = strings(1, 0);
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, th = 90 - th; notes(end+1) = "θ ∈ [−90°, 90°] read as elevation and folded to polar θ = 90° − el.";
    else, neg = th < 0; th(neg) = -th(neg); ph(neg) = ph(neg) + 180; notes(end+1) = "Negative θ samples folded onto φ + 180°."; end
end
th = mod(th, 360); over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;
th = round(th, 5); ph = round(mod(ph, 360), 5); ph(ph >= 360) = 0;
[~, u] = unique([ph th], 'rows', 'first'); th = th(u); ph = ph(u); V = V(u, :);        % φ = 360 duplicates of φ = 0 collapse here (D17)
P.Theta = unique(th); P.Phi = unique(ph); P.dTheta = util_axisStep(P.Theta, 'θ'); P.dPhi = util_axisStep(P.Phi, 'φ');
n = numel(P.Theta); m = numel(P.Phi);
if n*m ~= numel(th), error('APAT:NonUniformGrid', '%d samples do not fill the %d×%d θ/φ grid: APAT requires a complete rectangular grid.', numel(th), n, m); end
if isnan(P.dTheta), P.dTheta = 180; end, if isnan(P.dPhi), P.dPhi = 360; end
idx = sub2ind([n m], round((th - P.Theta(1))/P.dTheta) + 1, round((ph - P.Phi(1))/P.dPhi) + 1);
P.IsGainOnly = S.Meta.IsGainOnly; P.Freq = S.Freqs(min(f, end)); P.Revision = 1; P.Meta = S.Meta; P.Meta.Notes = [S.Meta.Notes notes];
P.Eth = []; P.Eph = []; P.G = struct();
if P.IsGainOnly
    for k = 1:numel(names), g = nan(n, m); g(idx) = V(:, k); P.G.(names(k)) = g; end
else
    P.Eth = complex(nan(n, m)); P.Eph = complex(nan(n, m)); P.Eth(idx) = complex(V(:, 1), V(:, 2)); P.Eph(idx) = complex(V(:, 3), V(:, 4));
end
end

function step = util_axisStep(ax, name)
% Uniformity assertion (§15-1): one step per axis or APAT:NonUniformGrid naming the axis and its gap range.
if numel(ax) < 2, step = NaN; return; end
d = diff(ax); step = median(d);
if any(abs(d - step) > 1e-4), error('APAT:NonUniformGrid', '%s axis is not uniform: steps range %.6g°..%.6g° (APAT requires uniform grids).', name, min(d), max(d)); end
end

function P = pat_resample(P, step)
%PAT_RESAMPLE Exact decimation when step/Δθ and step/Δφ are integers (D06); otherwise bilinear on the φ-closed grid per quantity:
%   E-field as power + unit phasor per component (B.5, D04), gain-kind columns as linear power (D16), others linear.
%   Target axes never leave the source domain (D05). Columns are derived afterwards (I6).
kt = step/P.dTheta; kp = step/P.dPhi; periodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
if abs(kt - round(kt)) < 1e-9 && abs(kp - round(kp)) < 1e-9
    it = 1:round(kt):numel(P.Theta); ip = 1:round(kp):numel(P.Phi); f = @(X) X(it, ip); t = P.Theta(it); p = P.Phi(ip); how = "decimated";
else
    t = (P.Theta(1):step:P.Theta(end) + 1e-9).'; last = P.Phi(end); if periodic, last = P.Phi(1) + 360 - step; end
    p = (P.Phi(1):step:last + 1e-9).'; sp = P.Phi(:).'; st = P.Theta(:);
    if periodic, sp(end+1) = sp(1) + 360; close = @(X) [X, X(:, 1)]; else, close = @(X) X; end   % φ-closed grid
    f = @(X) interp2(sp, st, close(X), p.', t, 'linear'); how = "bilinear";
end
if P.IsGainOnly
    for nm = string(fieldnames(P.G)).'
        if util_colKind(nm) == "gain", P.G.(nm) = 10*log10(max(f(10.^(P.G.(nm)/10)), realmin)); else, P.G.(nm) = f(P.G.(nm)); end
    end
else
    P.Eth = fieldInterp(P.Eth, f); P.Eph = fieldInterp(P.Eph, f);
end
P.Theta = t(:); P.Phi = p(:); P.dTheta = step; P.dPhi = step; P.Revision = P.Revision + 1;
P.Meta.Notes(end+1) = sprintf('Resampled to %g° (%s).', step, how);
end

function E = fieldInterp(E, f)
% |E|² and the unit phasor E/|E| are interpolated separately and recombined as sqrt(P)·u/|u| (B.5): the magnitude stays exact under a
% phase slope and the phase is the circular mean. Under decimation f is a pure index selection, so E is returned unchanged.
u = E ./ max(abs(E), realmin); pw = f(abs(E).^2); u = complex(f(real(u)), f(imag(u)));
E = sqrt(max(pw, 0)) .* u ./ max(abs(u), realmin);
end

function G = geo_build(P)
%GEO_BUILD Separable cell solid angles on the uniform grid (I2): wθ(i) = cos(θᵢ−Δθ/2) − cos(θᵢ+Δθ/2), edges clipped to [0°,180°],
%   ΔΩ(i,j) = wθ(i)·Δφ. On a full sphere Σwθ = 2 (telescoping) and nφ·Δφ = 2π, so ΣΔΩ = 4π exactly (B.1). No seam column exists.
lo = max(P.Theta(:) - P.dTheta/2, 0); hi = min(P.Theta(:) + P.dTheta/2, 180);
G.wTheta = cosd(lo) - cosd(hi); G.dPhi = deg2rad(P.dPhi);
G.PhiPeriodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
G.IsFullSphere = G.PhiPeriodic && lo(1) == 0 && hi(end) == 180;
G.dOmega = G.wTheta * G.dPhi * ones(1, numel(P.Phi)); G.Omega = sum(G.dOmega, 'all');
end

function M = geo_displayMap(P, G, V)
%GEO_DISPLAYMAP Column permutation and axis relabelling for the display convention; no data is copied or changed (I8).
n = numel(P.Phi); j0 = find(P.Phi >= 180, 1); perm = 1:n;
if V.SignedPhi && ~isempty(j0), perm = [j0:n, 1:j0 - 1]; end
M.ColIdx = perm; M.PhiAxis = P.Phi(perm).';
if V.SignedPhi, M.PhiAxis(M.PhiAxis >= 180) = M.PhiAxis(M.PhiAxis >= 180) - 360; end
if G.PhiPeriodic, M.ColIdx(end+1) = perm(1); M.PhiAxis(end+1) = M.PhiAxis(1) + 360; end   % closing column for display only
if V.Elevation, M.ThetaAxis = 90 - P.Theta(:); M.ThetaDir = 'normal'; M.ThetaLabel = "Elevation";
else, M.ThetaAxis = P.Theta(:); M.ThetaDir = 'reverse'; M.ThetaLabel = "Theta"; end
M.Key = sprintf('%d|%d', V.SignedPhi, V.Elevation);
end

function S = geo_cut(P, type, value)
%GEO_CUT One great-circle cut as linear indices into the nθ×nφ grid, so any column can be sliced with C(S.idx).
%   Phi cut: fixed θ row, angle = φ. Theta cut: fixed φ column (θ ascending) then the opposite column φ+180 (θ descending),
%   angle = θ and 360−θ. The closing point is appended when the circle is complete.
n = numel(P.Theta); m = numel(P.Phi); periodic = abs(m*P.dPhi - 360) < 1e-6; S.type = type; S.value = value;
if type == "Phi"
    [d, i] = min(abs(P.Theta - value)); S.fixed = P.Theta(i); S.symbol = 'θ';
    cols = 1:m; rows = i*ones(1, m); S.angle = P.Phi(:);
    if periodic, cols(end+1) = 1; rows(end+1) = i; S.angle(end+1) = P.Phi(1) + 360; end
else
    [d, j] = min(abs(mod(P.Phi - value + 180, 360) - 180)); S.fixed = P.Phi(j); S.symbol = 'φ';
    [dj, jo] = min(abs(mod(P.Phi - S.fixed, 360) - 180)); rows = 1:n; cols = j*ones(1, n); S.angle = P.Theta(:);
    if dj <= P.dPhi/2 + 1e-9                                   % the opposite half-plane exists on this grid
        back = flip(find(P.Theta > 1e-9 & P.Theta < 180 - 1e-9)).'; rows = [rows, back]; cols = [cols, jo*ones(size(back))]; S.angle = [S.angle; 360 - P.Theta(back)];
        if P.Theta(1) == 0, rows(end+1) = 1; cols(end+1) = j; S.angle(end+1) = 360; end
    end
end
S.idx = sub2ind([n m], rows(:), cols(:)); S.theta = P.Theta(rows(:)); S.phi = P.Phi(cols(:)); S.snapped = d > 1e-9;
end

function D = pat_derive(P, G, prm)
%PAT_DERIVE Every column and every base fact of a pattern at the given parameters (I3, I4). Called again whenever Revision or
%   Params change (≈ 40 ms at 1°×1°); nothing downstream adds, scales or memoises a value.
if P.IsGainOnly
    C = P.G; names = string(fieldnames(C)).';
    for nm = names, if util_colKind(nm) == "gain", C.(nm) = C.(nm) + prm.L; end, end        % loss on gain-kind columns only (D14, §15-10)
    total = names(find(arrayfun(@(nm) util_colKind(nm) == "gain", names), 1)); if isempty(total), total = names(1); end
    D.Pol = struct('label', "n/a", 'basis', "Linear", 'pairs', struct('Linear', {{'E_TH', 'E_PH'}}, 'Circular', {{'E_RCP', 'E_LCP'}}));
else
    s = 10^(prm.L/20); Eth = P.Eth*s; Eph = P.Eph*s;                                          % loss as an incident-field scale (B.3)
    Er = pol_circular(Eth, Eph, 1); El = pol_circular(Eth, Eph, 2);
    C.E_Total_dB = 10*log10(max(abs(Eth).^2 + abs(Eph).^2, eps));
    C.E_TH_dB = 20*log10(max(abs(Eth), eps));  C.E_PH_dB = 20*log10(max(abs(Eph), eps));
    C.E_RCP_dB = 20*log10(max(abs(Er), eps));  C.E_LCP_dB = 20*log10(max(abs(El), eps));
    [C.AR_dB, isLinear] = pol_signedAR(Er, El);
    K0 = met_peak(C.E_Total_dB, G.PhiPeriodic, APAT_v3_M8_10.PeakExcessDB); [pt, pp] = ind2sub(size(C.E_Total_dB), K0.index);
    D.Pol = pol_classify(Eth, Eph, Er, El, G.dOmega, util_cosGamma(P, P.Theta(pt), P.Phi(pp)) >= cosd(45));   % main beam = 45° cone about the peak (D13)
    C.PLF_dB = pol_plf(C.AR_dB, isLinear, prm.RxMode, prm.RxAR_dB, D.Pol.pairs.Circular{1});
    C.Gain_PolCorrected_dB = C.E_Total_dB + C.PLF_dB;
    C.E_TH_Phase = rad2deg(angle(Eth)); C.E_PH_Phase = rad2deg(angle(Eph)); C.E_RCP_Phase = rad2deg(angle(Er)); C.E_LCP_Phase = rad2deg(angle(El));
    C.EIRP_dBW = prm.Pt_dBW + C.E_Total_dB;
    C.PFD_Wm2 = 10.^(C.EIRP_dBW/10) ./ (4*pi*prm.R_m^2);
    C.E_RMS_Vm = sqrt(30*10.^(C.EIRP_dBW/10)) ./ prm.R_m;
    total = "E_Total_dB";
end
D.Cols = C; D.Total = char(total); T = C.(total);
D.Peak = met_peak(T, G.PhiPeriodic, APAT_v3_M8_10.PeakExcessDB);                                 % I5
D.Boresight = met_orientation(T, P, G, D.Peak);                                                 % principal axis, 45° cone
D.Planes = met_planes(D.Boresight);                                                             % A.7
D.Metrics = met_metrics(T, P, G, D.Peak, D.Planes, C, P.Meta.Unit == "dBi");                   % I9
end

function K = met_peak(C, periodic, excessDB)
%MET_PEAK Effective peak = highest sample that is not an isolated spike (I5, replaces the percentile policy, D01).
%   spike(i,j) ⇔ C(i,j) − max(4 grid neighbours) > excessDB; φ wraps when periodic; pole rows see the adjacent ring.
[n, m] = size(C); nb = -inf(n, m);
if n > 1, nb(2:n, :) = max(nb(2:n, :), C(1:n - 1, :)); nb(1:n - 1, :) = max(nb(1:n - 1, :), C(2:n, :)); end
if periodic, L = circshift(C, 1, 2); R = circshift(C, -1, 2); else, L = [-inf(n, 1), C(:, 1:m - 1)]; R = [C(:, 2:m), -inf(n, 1)]; end
nb = max(nb, max(L, R));
K.spike = isfinite(C) & (C - nb > excessDB);
[K.rawValue, K.rawIndex] = max(C(:), [], 'omitnan');
cand = C; cand(K.spike) = -Inf; [K.value, K.index] = max(cand(:), [], 'omitnan');
K.wasAdjusted = K.spike(K.rawIndex); K.spikeCount = nnz(K.spike);
end

function cg = util_cosGamma(P, thc, phc)
% cos of the great-circle distance from (θc, φc) to every grid direction (spherical law of cosines), nθ×nφ.
cg = cosd(P.Theta(:))*cosd(thc) + sind(P.Theta(:))*sind(thc) .* cosd(P.Phi(:).' - phc);
end

function axisIndex = met_orientation(T, P, G, K)
%MET_ORIENTATION Principal axis whose 45° cone holds the most 10^{(G−Gp)/10}·ΔΩ (spikes and non-finite samples excluded).
w = 10.^((T - K.value)/10) .* G.dOmega; w(~isfinite(w) | K.spike) = 0; A = APAT_v3_M8_10.PrincipalAxes; e = zeros(1, numel(A.theta));
for i = 1:numel(A.theta), e(i) = sum(w(util_cosGamma(P, A.theta(i), A.phi(i)) >= cosd(45))); end
[~, axisIndex] = max(e);
end

function S = met_planes(axisIndex)
%MET_PLANES E-plane: θ-cut through the boresight axis' φ. H-plane: the orthogonal cut — a φ-cut at θ = 90° for a transverse axis (±X, ±Y), a θ-cut at φ = 90° for ±Z.
A = APAT_v3_M8_10.PrincipalAxes; S.E = struct('type', "Theta", 'value', A.phi(axisIndex));
if A.theta(axisIndex) == 90, S.H = struct('type', "Phi", 'value', 90); else, S.H = struct('type', "Theta", 'value', 90); end
end

function X = met_metrics(T, P, G, K, S, C, isAbsolute)
%MET_METRICS Directivity over the sampled solid angle with spikes removed from numerator and Ω (D07); efficiency and F/B only on a
%   full sphere (efficiency only in dBi, I9); HPBW on the E/H cuts through geo_cut; AR at the peak.
keep = isfinite(T) & ~K.spike; lin = 10.^(T/10); I = sum(lin(keep) .* G.dOmega(keep)); X.OmegaUsed = sum(G.dOmega(keep));
X.Directivity_dB = 10*log10(max(X.OmegaUsed * 10^(K.value/10) / max(I, realmin), realmin));
X.Efficiency_pct = NaN; if G.IsFullSphere && isAbsolute, X.Efficiency_pct = 100*I/(4*pi); end
X.FrontBack_dB = NaN;
if G.IsFullSphere, [pt, pp] = ind2sub(size(T), K.index); [~, back] = min(util_cosGamma(P, P.Theta(pt), P.Phi(pp)), [], 'all'); X.FrontBack_dB = K.value - T(back); end
E = geo_cut(P, S.E.type, S.E.value); H = geo_cut(P, S.H.type, S.H.value);
X.HPBW_E = met_hpbw(E.angle, T(E.idx)); X.HPBW_H = met_hpbw(H.angle, T(H.idx));
X.AR_at_peak_dB = NaN; if isfield(C, 'AR_dB'), X.AR_at_peak_dB = C.AR_dB(K.index); end
end

function [bw, lower, upper] = met_hpbw(angleDeg, gainDB, peakGain, peakAngle)
%MET_HPBW Half-power beamwidth of a circular cut by linear interpolation of the −3 dB crossings either side of the peak.
[bw, lower, upper] = deal(NaN); ok = isfinite(angleDeg) & isfinite(gainDB); angleDeg = angleDeg(ok); gainDB = gainDB(ok);
if numel(gainDB) < 3, return; end
if nargin < 3 || isempty(peakGain) || ~isfinite(peakGain), [peakGain, i] = max(gainDB); peakAngle = angleDeg(i); end
half = peakGain - 3; [ra, o] = sort(mod(angleDeg - peakAngle + 180, 360) - 180); rg = gainDB(o);
l = find(ra < 0 & rg <= half, 1, 'last'); r = find(ra > 0 & rg <= half, 1, 'first');
if isempty(l) || isempty(r) || l + 1 > numel(rg) || r - 1 < 1, return; end
li = [l, l + 1]; ri = [r, r - 1]; if diff(rg(li)) == 0 || diff(rg(ri)) == 0, return; end
lc = ra(li(1)) + diff(ra(li))*(half - rg(li(1)))/diff(rg(li)); rc = ra(ri(1)) + diff(ra(ri))*(half - rg(ri(1)))/diff(rg(ri));
lower = peakAngle + lc; upper = peakAngle + rc; bw = rc - lc;
end

function E = pol_circular(Eth, Eph, which)
%POL_CIRCULAR RHCP (1) / LHCP (2) components of E = Eθ θ̂ + Eφ φ̂ under e^{+jωt} with (θ̂, φ̂, r̂) right-handed (I10, B.4):
%   ê_R = (θ̂ − jφ̂)/√2 ⇒ E_R = E·ê_R* = (Eθ + jEφ)/√2,  E_L = (Eθ − jEφ)/√2.   Check: E = ê_R ⇒ E_R = 1, E_L = 0.
if which == 1, E = (Eth + 1i*Eph)/sqrt(2); else, E = (Eth - 1i*Eph)/sqrt(2); end
end

function [Eth, Eph] = pol_fromCircular(Er, El)
% Inverse of pol_circular: OUT / CUT ICOMP = 2 / Excel format 2 / generic rcp-lcp sources.
Eth = (Er + El)/sqrt(2); Eph = (Er - El)/(1i*sqrt(2));
end

function [AR, isLinear] = pol_signedAR(Er, El)
%POL_SIGNEDAR Signed axial ratio in dB: + RHCP sense, − LHCP sense; −100 dB at numerically linear samples (§15-2).
r = abs(Er); l = abs(El); d = r - l; isLinear = isfinite(d) & abs(d) <= eps .* max(r + l, 1);
AR = min(20*log10((r + l) ./ max(abs(d), eps)), 250) .* sign(d); AR(isLinear) = -100;
end

function pol = pol_classify(Eth, Eph, Er, El, dOmega, beam)
%POL_CLASSIFY Co/cross ordering, cut basis and label from Ω-weighted mean powers inside the main beam (not the sphere mean, D13).
w = dOmega(beam); pw = @(E) sum(abs(E(beam)).^2 .* w) / max(sum(w), realmin);
[pth, pph, pr, pl] = deal(pw(Eth), pw(Eph), pw(Er), pw(El));
pol.pairs.Linear = {'E_TH', 'E_PH'}; if pph > pth, pol.pairs.Linear = fliplr(pol.pairs.Linear); end
pol.pairs.Circular = {'E_RCP', 'E_LCP'}; if pl > pr, pol.pairs.Circular = fliplr(pol.pairs.Circular); end
if max(pr, pl) > max(pth, pph), pol.basis = "Circular"; pol.label = "Circular (" + replace(string(pol.pairs.Circular{1}), ["E_RCP" "E_LCP"], ["RHCP" "LHCP"]) + ")";
elseif pth >= pph, pol.basis = "Linear"; pol.label = "Linear (Vertical)";
else, pol.basis = "Linear"; pol.label = "Linear (Horizontal)"; end
end

function plf = pol_plf(AR_dB, isLinear, rxMode, rxAR_dB, leadingCircular)
%POL_PLF Polarisation loss factor between the antenna ellipse (signed AR) and the incident wave (rxMode, rxAR_dB), major axes
%   orthogonal (M7 convention):  PLF = 1/2 + (4·ρa·ρw − (ρa² − 1)(ρw² − 1)) / (2(ρa² + 1)(ρw² + 1)),  ρ = signed linear AR.
switch rxMode, case "RHCP", sw = 1; case "LHCP", sw = -1; otherwise, sw = 2*strcmp(leadingCircular, 'E_RCP') - 1; end
ra = 10.^(abs(AR_dB)/20) .* sign(AR_dB); ra(isLinear) = 1e12; rw = sw * 10^(rxAR_dB/20);
plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1)) ./ (2*(ra.^2 + 1)*(rw^2 + 1));
plf = 10*log10(min(max(plf, eps), 1)); plf(~isfinite(AR_dB)) = NaN;                        % NaN in ⇒ NaN out (D08)
end

function cov = cov_curve(C, dOmega, mask, T)
%COV_CURVE Coverage(T) = 100 · Ω_R(C > T) / Ω_R,   Ω_R(C > T) = Σ_{(i,j)∈R, C(i,j) > T} ΔΩ(i,j)     (I7, strict ">").
%   Evaluated as the sampled CCDF: sort the region levels once, accumulate their solid angles from the top, read at every T.
%   O((N + nT)·log N) time and O(N) memory — no N×T indicator matrix (D10), no cache (D56).
v = mask & isfinite(C); g = C(v); w = dOmega(v); Omega = sum(w); cov = zeros(size(T)); if Omega <= 0, return; end
[g, o] = sort(g(:)); w = w(o); [gu, first] = unique(g, 'first');
above = cumsum(w, 'reverse'); above = [above(first); 0];                      % Ω of samples with level ≥ gu(k); 0 above the maximum
k = discretize(T(:), [-Inf; gu; Inf]);                                        % gu(k−1) ≤ T < gu(k): the first level strictly above T is gu(k)
cov = reshape(100 * above(k) / Omega, size(T));
end

function T = cov_thresholds(tMin, tMax, step)
% Threshold vector by counting, not accumulation (D11).
if tMax <= tMin, tMax = tMin + step; end
n = round((tMax - tMin)/step); T = tMin + (0:n).'*step; if T(end) < tMax - 1e-9, T(end+1) = tMax; end
end

function y = cov_at(job, T)
%COV_AT Coverage at threshold(s) T, read off the job's curve (linear between samples, NaN outside).
y = interp1(job.T, job.cov, T, 'linear', NaN);
end

function T = thr_at(job, c)
%THR_AT Threshold at coverage c %: inverse read of the same curve. For each coverage level keep the highest threshold that still
%   reaches it ('last'), which makes the non-increasing curve strictly monotone and returns the upper end of every plateau.
[cv, i] = unique(job.cov, 'last'); if numel(cv) < 2, T = nan(size(c)); return; end
T = interp1(cv, job.T(i), c, 'linear', NaN);
end

%% ============================== FILE-SCOPE: UTILITIES ==============================

function kind = util_colKind(name)
% "gain" | "ar" | "plf" | "phase" | "link" | "other" from the column table, else from the name (gain-only sources).
tbl = APAT_v3_M8_10.Cols; i = find(strcmp(tbl(:, 1), char(name)), 1); if ~isempty(i), kind = string(tbl{i, 3}); return; end
key = regexprep(lower(char(name)), '[^a-z0-9]', '');
if strcmp(key, 'ar') || startsWith(key, 'ardb') || contains(key, 'axial'), kind = "ar";
elseif contains(key, 'phase') || endsWith(key, 'deg'), kind = "phase";
elseif contains(key, 'plf'), kind = "plf";
elseif contains(key, {'gain', 'directivity', 'eirp', 'dbi'}) || endsWith(key, 'db'), kind = "gain";
else, kind = "other"; end
end

function [names, labels] = colChoices(Cols, isGainOnly)
% Component dropdown entries: every column for gain-only sources; gain / AR / PLF kinds (table order) for E-field sources.
names = string(fieldnames(Cols)).'; tbl = APAT_v3_M8_10.Cols;
if ~isGainOnly, names = string(tbl(ismember(tbl(:, 3), {'gain', 'ar', 'plf'}), 1)).'; names = names(ismember(names, fieldnames(Cols))); end
labels = names;
for k = 1:numel(names), i = find(strcmp(tbl(:, 1), names(k)), 1); if ~isempty(i), labels(k) = string(tbl{i, 2}); end, end
end

function c = prefer(previous, names)
if any(names == previous), c = previous; elseif any(names == "E_Total_dB"), c = "E_Total_dB"; else, c = names(1); end
end

function tf = isHidden(name)
tbl = APAT_v3_M8_10.Cols; i = find(strcmp(tbl(:, 1), name), 1); tf = ~isempty(i) && tbl{i, 4};
end

function u = util_unit(name, meta)
switch util_colKind(name)
    case "gain", u = char(meta.UnitLabel); case {"ar", "plf"}, u = 'dB'; case "phase", u = 'deg';
    case "link", u = char(replace(string(name), ["EIRP_dBW" "PFD_Wm2" "E_RMS_Vm"], ["dBW" "W/m^2" "V/m"])); otherwise, u = '';
end
end

function s = util_fmtNumber(v, prec)
% Compact (≤ 2 decimals, no trailing zeros, never "-0") or fixed precision; 'n/a' for non-finite input (D67).
if ~(isscalar(v) && isnumeric(v) && isfinite(v)), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); else, s = sprintf('%.*f', prec, v); end
if strcmp(s, '-0') || isempty(s), s = '0'; end
end

function b = util_presetRange(peak)
% 50-dB window under the next multiple of 5 above the peak; the default window when no peak exists.
if ~isfinite(peak), b = [-40 10]; return; end
hi = 5*ceil(peak/5); b = min(max([hi - 50, hi], -250), 100);
end

function t = util_ticks(lim, step)
if ~isfinite(step) || step <= 0 || diff(lim) <= 0, t = []; return; end
t = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)], 'stable'); if numel(t) > 60, t = []; end
end

function r = util_polarRadius(values, lim)
% Radius of the polar-3D surface and its overlay from the same colour limits (D60): 0 at lim(1), 1 at lim(2).
r = min(max((values - lim(1)) / max(diff(lim), eps), 0), 1);
end