classdef APAT_v3_M8_9 < matlab.apps.AppBase %1681-lines %ISSUE: nothing happens after selecting a file (it doesn't load! It doesn't even show the selected file in the Path Input Field)
%APAT_V3_M8  Antenna Pattern Analysis Tool — release M8 (architecture rebuild of APAT_v3_M7_110_5).
%
%   Base MATLAB only (R2023b baseline, no toolboxes). One file, App Designer-style handles, the same widgets,
%   tabs, input formats and features as M7 — rebuilt around one grid-native pattern, one derivation function,
%   one pattern registry shared by the Pattern and Coverage tabs, one dispatcher and one declarative layout.
%
%   DATAFLOW  (every arrow is one function; nothing is copied, memoised or synchronised)
%
%     FILE ─► io_read ─────────────────► Source   {Raw, Blocks{f}, Freqs, Meta}
%          ─► pat_build (+pat_resample) ► Pattern  {Theta, Phi, dTheta, dPhi, Eth, Eph | G.(name), Freq, Meta}
%          ─► geo_build ────────────────► Geometry {wTheta, dPhiRad, dOmega, Omega, PhiPeriodic, IsFullSphere}
%          ─► pat_derive(P, G, Params) ─► Derived  {Cols.(name), Kind.(name), Total, Peak, Pol, Boresight, Planes, Metrics}
%          ─► app.Pats(k) = {Key, Name, Path, Source, Pattern, Geometry, Derived, Params}
%                Pattern tab reads Pats(app.Main); a coverage tree node stores its k. No second copy exists.
%     VIEW = readConfig() ─► MAP = geo_displayMap(View) ─► renderers (index permutation + labels only)
%
%   RULES
%     * Widgets are READ only in readConfig / readCoverageConfig / readRange and WRITTEN only in apply* / render*.
%     * Every function below the "File-scope functions" line is app-free, widget-free and alert-free.
%     * update(scope) builds into locals and commits with one assignment: an error leaves the old state intact.
%     * Physical quantities (peak, boresight, principal planes, metrics) are defined on total gain; the selected
%       component changes plots, cuts, tables and the POB marker only.
%     * Conventions live in Const (one place each) and are listed in the Metadata table.
%
%   Run:  app = APAT_v3_M8;        Seconds of the last action per scope:  app.Perf

    %% ================================================================ UI handles (App Designer style, M7 names)
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

    %% ================================================================ State: one registry, one view, one map
    properties (Access = private)
        Pats = struct('Key', {}, 'Name', {}, 'Path', {}, 'Source', {}, 'Pattern', {}, 'Geometry', {}, 'Derived', {}, 'Params', {}, 'NativeStep', {})
        Main = 0                          % index of the Pattern-tab entry in Pats (0 = nothing loaded)
        View = struct()                   % last readConfig()
        Map = struct()                    % last geo_displayMap()
        Range = struct()                  % display ranges {full, cut, covX} + Auto flags per group
        Gfx = struct()                    % retained graphics handles (created once, updated in place)
        Perf = struct()                   % seconds of the last action per scope (developer channel)
        Status = struct('Main', '', 'Cov', '')   % persistent text of each status bar (Tag = field name)
        StatusTimer = []                  % the single transient-status timer
        Busy = false
        IsClosing = false
        JobCounter = 0                    % coverage job ids
        Stamp = 0                         % increments on every Derived commit (render-key ingredient)
        Shown = struct('out', "", 'in', "")      % keys of the last filled Output / Input tables (lazy tables)
        DefaultParams = struct()          % parameter widget values at startup (Reset button)
        Single_paxCut matlab.graphics.axis.PolarAxes
        Single_paxPattern matlab.graphics.axis.PolarAxes
    end

    %% ================================================================ Conventions (one place each; shown in Metadata)
    properties (Constant)
        Const = struct('ReleaseName', 'APAT v3 M8', 'ReleaseVersion', '3.0-M8', ...
            'PeakExcessDB', 6, ...          % spike = exceeds every grid neighbour by more than this (spatial isolation)
            'LinearAR_dB', -100, ...        % signed AR shown at numerically linear samples (M7 floor kept)
            'FloorDB', -100, ...            % dB floor for zero PLF
            'AngleDecimals', 5, ...         % angles are snapped; field values are never rounded
            'UniformTolDeg', 1e-4, ...      % uniform-axis assertion tolerance
            'RevolutionPhiStep', 10, ...    % single-cut body-of-revolution synthesis (disclosed in Notes)
            'ConeHalfAngleDeg', 45, ...     % boresight-axis selection cone
            'DistanceFloorM', 1e-12, 'StatusSeconds', 3, 'ARLimits', [-30 30])
        Axes6 = struct('labels', {{'+Z', '-Z', '+X', '-X', '+Y', '-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        Columns = struct( ...               % derived-column catalogue: name, user label, in component lists, in the standard output table
            'name',  {'E_Total_dB', 'E_TH_dB', 'E_PH_dB', 'E_RCP_dB', 'E_LCP_dB', 'AR_dB', 'PLF_dB', 'Gain_PolCorrected_dB', ...
                      'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'}, ...
            'label', {'Total Gain', 'Etheta Gain', 'Ephi Gain', 'RHCP Gain', 'LHCP Gain', 'Axial Ratio', 'PLF', 'Polarized Gain', ...
                      'Etheta Phase', 'Ephi Phase', 'RHCP Phase', 'LHCP Phase', 'EIRP', 'PFD', 'E RMS'}, ...
            'plot',  {true, true, true, true, true, true, false, true, false, false, false, false, false, false, false}, ...
            'std',   {true, false, false, true, true, true, true, true, false, false, false, false, false, false, false})
        FileFilter = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.txt;*.dat', 'Antenna patterns & coverage results'; '*.*', 'All files'}
    end

    %% ================================================================ Lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_9()
            app.createComponents();
            registerApp(app, app.UIFigure);
            app.initState();
            if nargout == 0, clear app; end
        end

        function delete(app)
            app.IsClosing = true;
            if ~isempty(app.StatusTimer) && isvalid(app.StatusTimer), stop(app.StatusTimer); delete(app.StatusTimer); end
            if isvalid(app.UIFigure), delete(app.UIFigure); end
        end
    end

    %% ================================================================ Orchestration
    methods (Access = private)
        function initState(app)
            app.Range = struct('full', [-50 0], 'cut', [-50 0], 'covX', [-40 10], ...
                               'Auto', struct('full', true, 'cut', true, 'cov', true, 'covX', true));
            app.DefaultParams = app.readConfig().Params;
            app.StatusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', app.Const.StatusSeconds, 'TimerFcn', @(~, ~) app.restoreStatus());
            app.initGraphics();
            for g = ["full", "cut", "covX"], app.applyRange(g); end
            app.applyVisibility();
            app.setStatus(app.Single_StatusBar, 'Load a pattern file to begin.', false);
            app.setStatus(app.Cov_StatusBar, 'Load a pattern or a coverage results file, then compute coverage.', false);
            app.UIFigure.Visible = 'on';
        end

        function on(app, scope, arg)
            %ON Every callback lands here: busy guard, error boundary, performance record, one drawnow.
            if nargin < 3, arg = []; end
            if app.Busy || app.IsClosing, return; end
            app.Busy = true; t0 = tic; app.UIFigure.Pointer = 'watch';
            try
                app.update(string(scope), arg);
            catch ME
                bar = app.Single_StatusBar; if startsWith(string(scope), "cov"), bar = app.Cov_StatusBar; end
                app.setStatus(bar, ['Error: ' ME.message], true);
                uialert(app.UIFigure, ME.message, app.Const.ReleaseName, 'Icon', 'error');
            end
            app.Perf.(matlab.lang.makeValidName(char(scope))) = toc(t0);
            app.Busy = false; app.UIFigure.Pointer = 'arrow';
            drawnow limitrate
        end

        function update(app, scope, arg)
            %UPDATE Recompute exactly the invalidation radius of SCOPE; renderers then reconcile their keys.
            %
            %   SOURCE ─► PATTERN ─► GEOMETRY ─► DERIVED(Params)   committed into Pats(k) in one assignment
            %   VIEW ─► MAP ─► ColIdx / axes / labels / cut domain  touches nothing above
            is = @(varargin) any(scope == string(varargin));
            if startsWith(scope, "cov"), app.updateCoverage(scope, arg); return; end
            if is("load")
                [f, p] = uigetfile(app.FileFilter, 'Select an antenna pattern file', app.startDir());
                if isequal(f, 0), return; end
                arg = fullfile(p, f); scope = "source";
            elseif is("path"),   arg = app.Single_EditField_Path.Value; scope = "source"; if isempty(arg), return; end
            elseif is("export"), app.exportMain(string(arg)); return
            elseif is("reset"),  app.applyParams(app.DefaultParams); scope = "params";
            elseif is("switch"), app.Main = arg;                                       % coverage tree → Pattern tab
            end
            rebuilt = is("source", "freq", "step", "format", "switch");
            if is("freq", "step", "format") && app.Main == 0, return; end
            if is("source", "freq", "step", "format")
                cfg = app.readConfig();
                if is("source"), path = string(arg); source = [];
                else, path = app.Pats(app.Main).Path; source = app.Pats(app.Main).Source; if is("format"), source = []; end
                end
                try
                    E = app.buildEntry(path, cfg, source);                                % nothing committed before this line
                catch ME
                    if ~strcmp(ME.identifier, 'APAT:CoverageFile'), rethrow(ME); end
                    app.covLoadResults(path); app.TabGroup.SelectedTab = app.Tab2_Coverage; app.covRefresh(); return
                end
                k = find(arrayfun(@(e) e.Key == E.Key, app.Pats), 1); if isempty(k), k = numel(app.Pats) + 1; end
                app.Pats(k) = E; app.Main = k;                                            % the one commit
            end
            if app.Main == 0, return; end
            if rebuilt
                app.Stamp = app.Stamp + 1; app.Range.Auto.full = true; app.Range.Auto.cut = true;
                app.applyChoices(); app.applyVisibility();
            elseif is("params")
                cfg = app.readConfig(); E = app.Pats(app.Main);
                app.Pats(app.Main).Derived = pat_derive(E.Pattern, E.Geometry, cfg.Params, app.Const, app.Axes6);
                app.Pats(app.Main).Params = cfg.Params; app.Stamp = app.Stamp + 1;
            elseif is("range")
                g = string(arg.Tag); app.Range.(g) = app.readRange(g, arg); app.Range.Auto.(g) = false; app.applyRange(g);
                if g == "covX", app.covRefresh(); return; end
            elseif is("autorange"), app.Range.Auto.full = true; app.Range.Auto.cut = true;
            end
            V0 = app.View; app.View = app.readConfig();
            if rebuilt || is("plane"), app.applyPlane();
            elseif is("span") && isfield(V0, 'CutType')                                   % keep the same physical cut (I8)
                canon = util_cutCanonical(V0.CutType, V0.CutValue, V0.Elevation);
                app.setSpinner(app.Single_DropDown_cutValue, util_cutDisplay(app.View.CutType, canon, app.View.Elevation, app.View.SignedPhi));
            end
            if rebuilt || is("plane", "span", "cuttype"), app.applyCutDomain(); end
            app.View = app.readConfig(); E = app.Pats(app.Main);
            app.Map = geo_displayMap(E.Pattern, E.Geometry, app.View);
            if rebuilt || is("params", "component", "autorange"), app.applyAutoRanges(); end
            app.renderFull(); app.renderCut();
            app.applyMetadata(); app.applyStatus(); app.applyTables();
        end

        function E = buildEntry(app, path, cfg, source)
            %BUILDENTRY Source → Pattern → Geometry → Derived for one file, into locals only.
            if isempty(source), source = io_read(char(path), cfg.TextFormat); end
            P = pat_build(source, min(max(cfg.FreqIndex, 1), numel(source.Blocks)), app.Const);
            native = [P.dTheta, P.dPhi];
            if cfg.StepChoice == "1deg", P = pat_resample(P, 1); end
            G = geo_build(P);
            D = pat_derive(P, G, cfg.Params, app.Const, app.Axes6);
            [~, name, ext] = fileparts(char(path));
            E = struct('Key', string(path), 'Name', string([name ext]), 'Path', string(path), 'Source', source, ...
                       'Pattern', P, 'Geometry', G, 'Derived', D, 'Params', cfg.Params, 'NativeStep', native);
        end

        function d = startDir(app)
            d = pwd; if app.Main > 0, d = fileparts(char(app.Pats(app.Main).Path)); end
        end

        %% ------------------------------------------------------------ readConfig: the ONLY reader of Pattern-tab widgets
        function cfg = readConfig(app)
            cfg = struct();
            cfg.Component  = string(app.Single_DropDown_Component.Value);
            cfg.CutType    = string(app.Single_DropDown_cutType.Value);      % "Theta": fixed φ, θ sweeps | "Phi": fixed θ, φ sweeps
            cfg.CutValue   = app.Single_DropDown_cutValue.Value;             % in the DISPLAY convention
            cfg.Basis      = string(app.CutFieldBasisDropDown.Value);        % "Auto" | "Linear" | "Circular"
            cfg.Traces     = logical([app.CheckBox_Et.Value, app.CheckBox_Er.Value, app.CheckBox_El.Value]);
            cfg.HPBW       = logical(app.Button_HPBW.Value);
            cfg.HPBWBounds = logical(app.Single_CheckBox_HPBWBounds.Value);
            cfg.POB        = logical(app.Single_CheckBox_POB.Value);
            cfg.Overlay    = logical(app.Singel_CheckBox_overlayCut.Value);
            cfg.Plane      = string(app.Single_Switch_EHplane.Value);        % "E" | "H"
            cfg.Elevation  = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°');
            cfg.SignedPhi  = strcmp(app.Single_Switch_AngularSpan.Value, '-180° to 180°');
            cfg.View3D     = string(app.Single_DropDown_3DView.Value);
            cfg.CStep      = app.Single_Plot_Cstep.Value;
            cfg.FreqIndex  = app.Single_DropDown_FFD.Value;
            cfg.StepChoice = string(app.Single_DropDown_step.Value);         % "native" | "1deg"
            cfg.TextFormat = string(app.Single_DropDown_TextFormat.Value);   % "auto" | "gain" | "reim" | "magphase"
            cfg.OutFilter  = string(app.Single_DropDown_output.Value);       % "std" | "all"
            cfg.FullView   = str2double(app.Single_tabPlots.SelectedTab.Tag);
            cfg.DataTab    = string(app.Single_tabData.SelectedTab.Tag);
            pt = app.Single_Spinner_Pt.Value;
            switch app.Single_DropDown_Pt.Value
                case 'dBm',   pt = pt - 30;
                case 'Watts', pt = 10*log10(max(pt, eps));
            end
            R = max(app.Single_Spinner_R.Value, app.Const.DistanceFloorM); if strcmp(app.Single_DropDown_R.Value, 'km'), R = 1000*R; end
            cfg.Params = struct('Loss_dB', app.Single_Spinner_Loss.Value, 'RxMode', string(app.Single_DropDown_RxPol.Value), ...
                                'RxAR_dB', app.Single_Spinner_Rw.Value, 'Pt_dBW', pt, 'R_m', R);
        end

        function lim = readRange(app, group, src)
            %READRANGE Limits of GROUP from the widget SRC that fired; the partner spinner is pushed when min ≥ max.
            [sl, mn, mx] = app.rangeWidgets(group);
            if any(sl == src), lim = src.Value; return; end
            i = find(mn == src, 1);
            if ~isempty(i), lim = [src.Value, mx(i).Value]; if diff(lim) <= 0, lim(2) = lim(1) + 1; end
            else, i = find(mx == src, 1); lim = [mn(i).Value, src.Value]; if diff(lim) <= 0, lim(1) = lim(2) - 1; end
            end
        end

        %% ------------------------------------------------------------ apply*: the ONLY writers of widget state
        function applyParams(app, p)
            app.Single_Spinner_Loss.Value = p.Loss_dB; app.Single_DropDown_RxPol.Value = char(p.RxMode); app.Single_Spinner_Rw.Value = p.RxAR_dB;
            app.Single_Spinner_Pt.Value = p.Pt_dBW; app.Single_DropDown_Pt.Value = 'dBW';
            app.Single_Spinner_R.Value = p.R_m; app.Single_DropDown_R.Value = 'm';
        end

        function applyChoices(app)
            %APPLYCHOICES Items that depend on the loaded entry (frequency, step, component, traces); user values survive.
            E = app.Pats(app.Main); S = E.Source; P = E.Pattern;
            n = numel(S.Blocks); items = compose('Block %d', 1:n); ok = isfinite(S.Freqs);
            items(ok) = compose('%.4g GHz', S.Freqs(ok)/1e9);
            app.setDropdown(app.Single_DropDown_FFD, items, num2cell(1:n), 1);
            set([app.Single_DropDown_FFD, app.FFDFreqDropDownLabel], 'Visible', n > 1);
            native = max(E.NativeStep); nonCanonical = abs(native - 1) > 1e-9;
            app.setDropdown(app.Single_DropDown_step, {sprintf('STEP: %g°', native), 'STEP: 1°'}, {'native', '1deg'}, 'native');
            set(app.Single_DropDown_step, 'Visible', nonCanonical, 'Enable', nonCanonical);
            generic = S.Meta.Generic;
            set([app.Single_DropDown_TextFormat, app.TextFormatLabel], 'Visible', generic);
            [names, labels] = app.componentItems(E);
            app.setDropdown(app.Single_DropDown_Component, cellstr(labels), cellstr(names), char(E.Derived.Total));
            app.Single_EditField_Path.Value = char(E.Path);
            if ~P.IsGainOnly
                pr = E.Derived.Pol.Pairs; pretty = @(s) replace(s, ["E_TH", "E_PH", "E_RCP", "E_LCP"], ["Eθ", "Eφ", "RHCP", "LHCP"]);
                app.CheckBox_Et.Text = 'Total';
                app.CheckBox_Er.Text = sprintf('Co-pol (%s | %s)', pretty(pr.Linear(1)), pretty(pr.Circular(1)));
                app.CheckBox_El.Text = sprintf('Cross-pol (%s | %s)', pretty(pr.Linear(2)), pretty(pr.Circular(2)));
            end
        end

        function applyVisibility(app)
            loaded = app.Main > 0; field = loaded && ~app.Pats(app.Main).Pattern.IsGainOnly;
            set([app.Single_Panel_Rect, app.Single_Export_Output, app.Single_Panel_fullPattern, app.Single_Panel_plotControl, ...
                 app.Single_Button_Coverage, app.Single_Button_Process, app.Single_Button_ResetParams, app.Single_tabData], 'Visible', loaded);
            set([app.Single_Export_UAN, app.Single_gridEcut, app.CutFieldBasisDropDown], 'Visible', field);
            set([app.Single_Spinner_Rw, app.IncidentWaveARRwPLFLabel, app.Single_DropDown_RxPol, app.RxPolLabel], 'Enable', field);
            if ~loaded, set([app.Single_DropDown_FFD, app.FFDFreqDropDownLabel, app.Single_DropDown_step, app.Single_DropDown_TextFormat, app.TextFormatLabel], 'Visible', false); end
        end

        function applyPlane(app)
            %APPLYPLANE Cut type/value follow the E/H switch (principal planes come from Derived, on total gain).
            pl = app.Pats(app.Main).Derived.Planes.(app.View.Plane); V = app.View;
            app.Single_DropDown_cutType.Value = char(pl.CutType);
            app.setSpinner(app.Single_DropDown_cutValue, util_cutDisplay(pl.CutType, pl.Fixed, V.Elevation, V.SignedPhi));
        end

        function applyCutDomain(app)
            %APPLYCUTDOMAIN Fixed-angle spinner domain in the display convention; the value snaps to the nearest grid line.
            P = app.Pats(app.Main).Pattern; V = app.readConfig(); sp = app.Single_DropDown_cutValue;
            if V.CutType == "Theta"
                dom = P.Phi; if V.SignedPhi, dom = util_wrap180(dom); end; step = P.dPhi; app.CutvalueSpinnerLabel.Text = 'Fixed φ (°)';
            else
                dom = P.Theta; if V.Elevation, dom = 90 - dom; end; step = P.dTheta; app.CutvalueSpinnerLabel.Text = util_iif(V.Elevation, 'Fixed el (°)', 'Fixed θ (°)');
            end
            dom = sort(dom); [~, i] = min(abs(dom - V.CutValue));
            sp.Limits = [-Inf Inf]; sp.Value = dom(i); sp.Limits = dom([1 end]) + [-1 1]*1e-9; sp.Step = step;
        end

        function applyAutoRanges(app)
            E = app.Pats(app.Main); V = app.View; D = E.Derived;
            pk = met_peak(D.Cols.(V.Component), E.Geometry.PhiPeriodic, app.Const.PeakExcessDB);
            if app.Range.Auto.full && D.Kind.(V.Component) ~= "ar", app.Range.full = util_presetRange(pk.value); end
            if app.Range.Auto.cut, app.Range.cut = util_presetRange(util_iif(E.Pattern.IsGainOnly, pk.value, D.Peak.value)); end
            app.applyRange("full"); app.applyRange("cut");
        end

        function [sl, mn, mx] = rangeWidgets(app, group)
            switch group
                case "full"
                    sl = [app.Range_Ctr, app.Range_Cir, app.Range_3dSph, app.Range_3dPol, app.Range_3dRect];
                    mn = [app.Range_Ctr_Min, app.Range_Cir_Min, app.Range_3dSph_Min, app.Range_3dPol_Min, app.Range_3dRect_Min, app.Single_Plot_Cmin];
                    mx = [app.Range_Ctr_Max, app.Range_Cir_Max, app.Range_3dSph_Max, app.Range_3dPol_Max, app.Range_3dRect_Max, app.Single_Plot_Cmax];
                case "cut",  sl = app.Range_Cut; mn = app.Range_Cut_Min; mx = app.Range_Cut_Max;
                otherwise,   sl = app.Cov_Spinner_XRange; mn = app.Cov_Spinner_XMin; mx = app.Cov_Spinner_XMax;
            end
        end

        function applyRange(app, group)
            %APPLYRANGE One descriptor drives every slider/spinner of GROUP (sliders get ±20 dB of headroom).
            lim = app.Range.(group); [sl, mn, mx] = app.rangeWidgets(group);
            outer = [floor(lim(1)/10)*10 - 20, ceil(lim(2)/10)*10 + 20];
            set(sl, 'Limits', [-1e6 1e6]); set(sl, 'Value', lim); set(sl, 'Limits', outer);
            set(mn, 'Value', lim(1)); set(mx, 'Value', lim(2));
            if group == "full", app.Single_Label_Clim.Text = sprintf('Color scale [%g, %g]', lim); end
        end

        function setSpinner(~, sp, v)
            sp.Limits = [-Inf Inf]; sp.Value = v;
        end

        function setDropdown(~, dd, items, data, preferred)
            %SETDROPDOWN Replace Items/ItemsData; keep the user's value when it still exists, else PREFERRED, else the first.
            old = dd.Value; dd.Items = items; dd.ItemsData = data;
            if any(cellfun(@(x) isequal(x, old), data)), dd.Value = old;
            elseif any(cellfun(@(x) isequal(x, preferred), data)), dd.Value = preferred;
            end
        end

        function [names, labels] = componentItems(app, E)
            names = string(fieldnames(E.Derived.Cols)).'; labels = names;
            if ~E.Pattern.IsGainOnly
                cat = app.Columns([app.Columns.plot]); names = string({cat.name}); labels = string({cat.label});
                keep = ismember(names, string(fieldnames(E.Derived.Cols))); names = names(keep); labels = labels(keep);
            end
        end

        function [names, labels] = cutTraces(app, E)
            %CUTTRACES Columns drawn in the cut: total + co/cross of the chosen basis (fields) or the selected component (gain-only).
            V = app.View; D = E.Derived;
            if E.Pattern.IsGainOnly
                [all, lab] = app.componentItems(E); names = V.Component; labels = lab(all == V.Component);
                if isempty(labels), labels = names; end
                return
            end
            basis = V.Basis; if basis == "Auto", basis = D.Pol.Basis; end
            pair = D.Pol.Pairs.(basis); pretty = replace(pair, ["E_TH", "E_PH", "E_RCP", "E_LCP"], ["Eθ", "Eφ", "RHCP", "LHCP"]);
            names = ["E_Total_dB", pair + "_dB"]; labels = ["Total", pretty(1) + " (co)", pretty(2) + " (cross)"];
            keep = V.Traces; if ~any(keep), keep(1) = true; end
            names = names(keep); labels = labels(keep);
        end
        %% ------------------------------------------------------------ Graphics: created once, updated in place
        function ax = axesOf(app, v)
            h = {app.Single_Axes_Ctr, app.Single_paxPattern, app.Single_Axes_3dSph, app.Single_Axes_3dPol, app.Single_Axes_3dRect}; ax = h{v};
        end

        function initGraphics(app)
            %INITGRAPHICS Every retained graphics object is created here; the renderers only assign data.
            G = struct('key', strings(1, 5), 'cutKey', "", 'view3D', strings(1, 5), 'surf', gobjects(1, 5), 'cut3', gobjects(1, 5), 'pob3', gobjects(1, 5), 'cb', gobjects(1, 5));
            mk = {'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 6, 'HandleVisibility', 'off'};
            ax = app.Single_Axes_Ctr; hold(ax, 'on'); box(ax, 'on');
            G.ctr = surface(ax, [0 1], [0 1], zeros(2), 'EdgeColor', 'none');
            G.ctrCut = plot(ax, NaN, NaN, 'k.', 'MarkerSize', 5); G.ctrPOB = plot(ax, NaN, NaN, mk{:});
            pax = app.Single_paxPattern; hold(pax, 'on');
            G.cir = polarscatter(pax, 0, 0, 10, 0, 'filled', 'Marker', 's'); G.cirPOB = polarplot(pax, NaN, NaN, mk{:});
            style = {'k-', 'k-', 'k.'};
            for v = 3:5
                ax = app.axesOf(v); hold(ax, 'on'); box(ax, 'on'); set(ax, 'XGrid', 'on', 'YGrid', 'on', 'ZGrid', 'on');
                G.surf(v) = surf(ax, nan(2), nan(2), nan(2), 'EdgeColor', 'none');
                G.cut3(v) = plot3(ax, NaN, NaN, NaN, style{v-2}, 'LineWidth', 1.5, 'MarkerSize', 5);
                G.pob3(v) = plot3(ax, NaN, NaN, NaN, mk{:});
                if v < 5, axis(ax, 'equal'); axis(ax, 'vis3d'); xlabel(ax, 'x'); ylabel(ax, 'y'); zlabel(ax, 'z'); end
            end
            for v = 1:5, G.cb(v) = colorbar(app.axesOf(v)); end
            pax = app.Single_paxCut; hold(pax, 'on'); ax = app.Single_AxesRect; hold(ax, 'on'); box(ax, 'on'); set(ax, 'XGrid', 'on', 'YGrid', 'on');
            G.cutPolar = gobjects(1, 3); G.cutRect = gobjects(1, 3);
            for k = 1:3, G.cutPolar(k) = polarplot(pax, NaN, NaN, 'LineWidth', 1.5); G.cutRect(k) = plot(ax, NaN, NaN, 'LineWidth', 1.5); end
            G.cutPolarPOB = polarplot(pax, NaN, NaN, mk{:}); G.cutRectPOB = plot(ax, NaN, NaN, mk{:});
            G.cutPolarHPBW = polarplot(pax, nan(2), nan(2), 'k--', 'HandleVisibility', 'off');
            G.cutRectHPBW = plot(ax, nan(2), nan(2), 'k--', 'HandleVisibility', 'off');
            app.Gfx = G;
        end

        function renderFull(app)
            %RENDERFULL Draw only the visible full-pattern tab; skip when its key (stamp, component, map, theme, view) is unchanged.
            E = app.Pats(app.Main); V = app.View; M = app.Map; P = E.Pattern; D = E.Derived; v = V.FullView; G = app.Gfx;
            [lim, cmap] = util_theme(D.Kind.(V.Component), app.Range.full, app.Const);
            key = sprintf('%d|%s|%s|%g|%g|%g|%d|%s|%s|%g|%d', app.Stamp, V.Component, M.Key, lim, V.CStep, V.POB, V.View3D, V.CutType, V.CutValue, V.Overlay);
            if G.key(v) == key, return; end
            C = D.Cols.(V.Component); Cd = C(:, M.ColIdx); ax = app.axesOf(v);
            pk = met_peak(C, E.Geometry.PhiPeriodic, app.Const.PeakExcessDB);
            [pi_, pj] = ind2sub(size(C), pk.index); pjd = find(M.ColIdx == pj, 1);
            [PHc, THc] = meshgrid(P.Phi(M.ColIdx), P.Theta); [X, Y, Z] = util_sph2cart(THc, PHc);
            cut = struct('Idx', zeros(0, 1));
            if V.Overlay, cut = geo_cut(P, V.CutType, util_cutCanonical(V.CutType, V.CutValue, V.Elevation)); end
            [ci, cj] = ind2sub(size(C), cut.Idx); cth = P.Theta(ci); cph = P.Phi(cj); [cx, cy, cz] = util_sph2cart(cth, cph);
            dispPhi = @(ph) util_iif(V.SignedPhi, util_wrap180(ph), ph); dispTh = @(th) util_iif(V.Elevation, 90 - th, th);
            norm01 = @(c) min(max((c - lim(1))/diff(lim), 0), 1);
            switch v
                case 1
                    set(G.ctr, 'XData', M.PhiAxis, 'YData', M.ThetaAxis, 'ZData', zeros(size(Cd)), 'CData', Cd);
                    set(ax, 'YDir', M.ThetaDir, 'XLim', M.PhiAxis([1 end]), 'YLim', sort(M.ThetaAxis([1 end])));
                    xlabel(ax, 'φ (°)'); ylabel(ax, M.ThetaLabel);
                    set(G.ctrPOB, 'XData', M.PhiAxis(pjd), 'YData', M.ThetaAxis(pi_), 'Visible', V.POB);
                    set(G.ctrCut, 'XData', dispPhi(cph), 'YData', dispTh(cth));
                case 2
                    px = 0.5*min(ax.InnerPosition(3:4))/numel(P.Theta);
                    set(G.cir, 'ThetaData', deg2rad(PHc(:)), 'RData', THc(:), 'CData', Cd(:), 'SizeData', max(3, (1.6*px)^2));
                    rt = 0:30:180; tt = 0:30:330;
                    set(ax, 'RLim', [0 180], 'RTick', rt, 'RTickLabel', compose('%g°', dispTh(rt)), 'ThetaTick', tt, 'ThetaTickLabel', compose('%g°', dispPhi(tt)));
                    set(G.cirPOB, 'ThetaData', deg2rad(P.Phi(pj)), 'RData', P.Theta(pi_), 'Visible', V.POB);
                case 3
                    set(G.surf(3), 'XData', X, 'YData', Y, 'ZData', Z, 'CData', Cd);
                    set(G.pob3(3), 'XData', X(pi_, pjd), 'YData', Y(pi_, pjd), 'ZData', Z(pi_, pjd), 'Visible', V.POB);
                    set(G.cut3(3), 'XData', 1.01*cx, 'YData', 1.01*cy, 'ZData', 1.01*cz);
                case 4
                    r = norm01(Cd); rc = 1.01*norm01(C(cut.Idx)); rp = r(pi_, pjd);
                    set(G.surf(4), 'XData', X.*r, 'YData', Y.*r, 'ZData', Z.*r, 'CData', Cd);
                    set(G.pob3(4), 'XData', X(pi_, pjd)*rp, 'YData', Y(pi_, pjd)*rp, 'ZData', Z(pi_, pjd)*rp, 'Visible', V.POB);
                    set(G.cut3(4), 'XData', cx.*rc, 'YData', cy.*rc, 'ZData', cz.*rc);
                    set(ax, 'XLim', [-1 1], 'YLim', [-1 1], 'ZLim', [-1 1]);
                case 5
                    set(G.surf(5), 'XData', M.PhiAxis, 'YData', M.ThetaAxis, 'ZData', Cd, 'CData', Cd);
                    set(ax, 'YDir', M.ThetaDir, 'XLim', M.PhiAxis([1 end]), 'YLim', sort(M.ThetaAxis([1 end])), 'ZLim', lim);
                    xlabel(ax, 'φ (°)'); ylabel(ax, M.ThetaLabel); zlabel(ax, char(D.Unit));
                    set(G.pob3(5), 'XData', M.PhiAxis(pjd), 'YData', M.ThetaAxis(pi_), 'ZData', Cd(pi_, pjd), 'Visible', V.POB);
                    set(G.cut3(5), 'XData', dispPhi(cph), 'YData', dispTh(cth), 'ZData', C(cut.Idx));
            end
            set(ax, 'CLim', lim, 'Colormap', cmap); G.cb(v).Ticks = util_ticks(lim, V.CStep);
            title(ax, sprintf('%s — %s', app.columnLabel(E, V.Component), E.Name), 'Interpreter', 'none');
            if v >= 3 && G.view3D(v) ~= V.View3D
                views = struct('iso', [-37.5 30], 'top', [0 90], 'front', [0 0], 'side', [90 0]); view(ax, views.(V.View3D)); G.view3D(v) = V.View3D;
            end
            G.key(v) = key; app.Gfx = G;
        end

        function renderCut(app)
            %RENDERCUT One geo_cut per change feeds the polar and rectangular cut plots, the POB marker and the HPBW read-out.
            E = app.Pats(app.Main); V = app.View; D = E.Derived; P = E.Pattern; G = app.Gfx;
            cut = geo_cut(P, V.CutType, util_cutCanonical(V.CutType, V.CutValue, V.Elevation));
            [names, labels] = app.cutTraces(E);
            signed = util_iif(V.CutType == "Phi", V.SignedPhi, V.SignedPhi || V.Elevation);
            key = sprintf('%d|%s|%g|%s|%g|%g|%d|%d|%d|%d', app.Stamp, V.CutType, cut.Fixed, strjoin(names, ','), app.Range.cut, V.HPBW, V.HPBWBounds, V.POB, signed);
            if G.cutKey == key, return; end
            ang = cut.Angle; x = ang; if signed, x = util_wrap180(ang); end; [x, o] = sort(x);
            pax = app.Single_paxCut; ax = app.Single_AxesRect; n = numel(names);
            for k = 1:3
                if k <= n
                    y = D.Cols.(names(k))(cut.Idx);
                    set(G.cutPolar(k), 'ThetaData', deg2rad(ang), 'RData', y, 'DisplayName', labels(k), 'Visible', 'on');
                    set(G.cutRect(k), 'XData', x, 'YData', y(o), 'DisplayName', labels(k), 'Visible', 'on');
                else
                    set([G.cutPolar(k), G.cutRect(k)], 'Visible', 'off');
                end
            end
            tk = 0:30:330; wrap = @(a) util_iif(signed, util_wrap180(a), a);
            if V.CutType == "Theta", set(pax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise'); else, set(pax, 'ThetaZeroLocation', 'right', 'ThetaDir', 'counterclockwise'); end
            set(pax, 'ThetaTick', tk, 'ThetaTickLabel', compose('%g°', wrap(tk)), 'RLim', app.Range.cut);
            set(ax, 'YLim', app.Range.cut, 'XLim', [min(x) max(x)]);
            sweep = util_iif(V.CutType == "Theta", 'θ', 'φ');
            ttl = sprintf('%s-cut at %s = %g°%s', sweep, cut.Symbol, cut.Fixed, util_iif(cut.Snapped, ' (snapped)', ''));
            title(pax, ttl); title(ax, ttl); xlabel(ax, [sweep ' (°)']); ylabel(ax, char(D.Unit));
            legend(pax, G.cutPolar(1:n), 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(ax, G.cutRect(1:n), 'Location', 'best');
            y1 = D.Cols.(names(1))(cut.Idx); [pv, pi_] = max(y1);                       % POB and HPBW of the first drawn trace
            set(G.cutPolarPOB, 'ThetaData', deg2rad(ang(pi_)), 'RData', pv, 'Visible', V.POB);
            set(G.cutRectPOB, 'XData', wrap(ang(pi_)), 'YData', pv, 'Visible', V.POB);
            [bw, lo, hi] = met_hpbw(ang, y1); showB = V.HPBW && V.HPBWBounds && isfinite(bw); b = wrap([lo hi]);
            app.Label_HPBW.Text = util_iif(V.HPBW, sprintf('HPBW (%s): %s°  [%s°, %s°]', labels(1), util_fmt(bw), util_fmt(b(1)), util_fmt(b(2))), '');
            for k = 1:2
                set(G.cutPolarHPBW(k), 'ThetaData', deg2rad([b(k) b(k)]), 'RData', app.Range.cut, 'Visible', showB);
                set(G.cutRectHPBW(k), 'XData', [b(k) b(k)], 'YData', app.Range.cut, 'Visible', showB);
            end
            app.Gfx.cutKey = key;
        end

        function label = columnLabel(app, E, name)
            [n, l] = app.componentItems(E); label = char(name); if any(n == name), label = char(l(n == name)); end
        end

        %% ------------------------------------------------------------ Metadata, status, lazy tables, exports
        function applyMetadata(app)
            E = app.Pats(app.Main); P = E.Pattern; G = E.Geometry; D = E.Derived; m = D.Metrics; f = @util_fmt; C = app.Const; V = app.View;
            basis = V.Basis; if basis == "Auto", basis = D.Pol.Basis; end
            rows = {
                'Source format',        char(P.Meta.Format)
                'File',                 char(E.Name)
                'Samples',              sprintf('%d (θ: %d × φ: %d), %s', numel(P.Theta)*numel(P.Phi), numel(P.Theta), numel(P.Phi), util_iif(G.IsFullSphere, 'full sphere', sprintf('partial sphere, Ω = %s sr', f(G.Omega))))
                'θ range / step',       sprintf('[%s°, %s°] / %s° (native %s°)', f(P.Theta(1)), f(P.Theta(end)), f(P.dTheta), f(E.NativeStep(1)))
                'φ range / step',       sprintf('[%s°, %s°] / %s° (native %s°)%s', f(P.Phi(1)), f(P.Phi(end)), f(P.dPhi), f(E.NativeStep(2)), util_iif(G.PhiPeriodic, ', periodic', ''))
                'Level unit',           char(D.Unit)
                'Frequency',            util_iif(isfinite(P.Freq), sprintf('%.4g GHz', P.Freq/1e9), 'n/a')
                'Polarization',         char(D.Pol.Label)
                'Cut co-pol / cross-pol', char(strjoin(D.Pol.Pairs.(basis), ' / '))
                'Peak gain (POB)',      sprintf('%s %s', f(D.Peak.value), D.Unit)
                'POB direction [θ, φ]', sprintf('[%s°, %s°]', f(D.Peak.Theta), f(D.Peak.Phi))
                'Raw maximum',          sprintf('%s %s%s', f(D.Peak.rawValue), D.Unit, util_iif(D.Peak.wasAdjusted, sprintf(' — spike; %d isolated sample(s) excluded', D.Peak.spikeCount), ''))
                'Peak policy',          sprintf('spatial isolation: a sample exceeding every grid neighbour by > %g dB is a spike', C.PeakExcessDB)
                'Boresight axis',       app.Axes6.labels{D.Boresight}
                'E-plane / H-plane',    sprintf('%s / %s', util_planeText(D.Planes.E), util_planeText(D.Planes.H))
                'HPBW E-plane',         sprintf('%s°', f(m.HPBW_EPlane_deg))
                'HPBW H-plane',         sprintf('%s°', f(m.HPBW_HPlane_deg))
                'Peak directivity',     sprintf('%s dB', f(m.PeakDirectivity_dB))
                'Radiation efficiency', util_iif(isfinite(m.Efficiency_pct), sprintf('%s %%', f(m.Efficiency_pct)), 'n/a (needs a full sphere in dBi)')
                'Front-to-back',        util_iif(isfinite(m.FrontBack_dB), sprintf('%s dB', f(m.FrontBack_dB)), 'n/a (needs a full sphere)')
                'AR at peak',           util_iif(isfinite(m.AxialRatioAtPeak_dB), sprintf('%s dB', f(m.AxialRatioAtPeak_dB)), 'n/a')
                'Parameters',           sprintf('L = %g dB | Rx %s | wave AR %g dB | Pt %g dBW | R %g m', E.Params.Loss_dB, E.Params.RxMode, E.Params.RxAR_dB, E.Params.Pt_dBW, E.Params.R_m)
                'Circular convention',  'E_R = (Eθ + jEφ)/√2, E_L = (Eθ − jEφ)/√2 (IEEE, e^{+jωt}); AR signed +RHCP / −LHCP'
                'Table convention',     'Output/export tables use θ polar [0°,180°], φ [0°,360°); display toggles change plots only'
                'Reader notes',         char(strjoin(P.Meta.Notes, '; '))
                'Release',              sprintf('%s (%s)', C.ReleaseName, C.ReleaseVersion)};
            app.Single_Table_metadata.Data = rows;
        end

        function applyStatus(app)
            E = app.Pats(app.Main); D = E.Derived; f = @util_fmt;
            txt = sprintf('Pattern: <b>%s</b> | POB <b>%s %s</b> (<b>θ=%s°, φ=%s°</b>)', E.Name, f(D.Peak.value, 2), D.Unit, f(D.Peak.Theta), f(D.Peak.Phi));
            if D.Pol.Label ~= "n/a", txt = sprintf('%s | Polarization <b>%s</b>', txt, D.Pol.Label); end
            app.setStatus(app.Single_StatusBar, txt, false);
        end

        function applyTables(app)
            %APPLYTABLES Output/Input tables are filled only when their tab is visible and their key changed (65k-row pushes are costly).
            E = app.Pats(app.Main); V = app.View;
            if V.DataTab == "out"
                key = sprintf('%d|%s', app.Stamp, V.OutFilter);
                if app.Shown.out ~= key
                    app.Single_Table_DataOut.Data = util_longTable(E.Pattern, E.Derived, app.outputColumns(E, V.OutFilter)); app.Shown.out = key;
                end
            elseif V.DataTab == "in" && app.Shown.in ~= E.Key
                app.Single_Table_DataIn.Data = E.Source.Raw; app.Shown.in = E.Key;
            end
        end

        function names = outputColumns(app, E, filt)
            names = string(fieldnames(E.Derived.Cols)).';
            if filt == "std" && ~E.Pattern.IsGainOnly, cat = app.Columns([app.Columns.std]); names = names(ismember(names, string({cat.name}))); end
        end

        function exportMain(app, what)
            E = app.Pats(app.Main); base = fullfile(app.startDir(), regexprep(char(E.Name), '\.[^.]*$', ''));
            switch what
                case "output"
                    [f, p] = uiputfile({'*.csv', 'CSV'; '*.xlsx', 'Excel'}, 'Export processed pattern', [base '_APAT.csv']); if isequal(f, 0), return; end
                    writetable(util_longTable(E.Pattern, E.Derived, app.outputColumns(E, app.View.OutFilter)), fullfile(p, f));
                case "uan"
                    [f, p] = uiputfile({'*.uan', 'UAN'}, 'Export UAN', [base '_APAT.uan']); if isequal(f, 0), return; end
                    io_writeUAN(fullfile(p, f), E.Pattern, E.Derived);
                case "cut"
                    [f, p] = uiputfile({'*.csv', 'CSV'}, 'Export cut', [base '_cut.csv']); if isequal(f, 0), return; end
                    V = app.View; cut = geo_cut(E.Pattern, V.CutType, util_cutCanonical(V.CutType, V.CutValue, V.Elevation)); names = app.cutTraces(E);
                    T = table(cut.Angle, 'VariableNames', {'Angle_deg'});
                    for k = 1:numel(names), T.(char(names(k))) = E.Derived.Cols.(names(k))(cut.Idx); end
                    writetable(T, fullfile(p, f));
            end
            app.setStatus(app.Single_StatusBar, sprintf('Exported %s', fullfile(p, f)), true);
        end
        %% ------------------------------------------------------------ Coverage tab: the tree IS the job registry
        function updateCoverage(app, scope, arg) %#ok<INUSD>
            is = @(varargin) any(scope == string(varargin));
            if is("covLoad")
                [f, p] = uigetfile(app.FileFilter, 'Select a pattern or a coverage results file', app.startDir()); if isequal(f, 0), return; end
                app.covAddFile(string(fullfile(p, f)));
            elseif is("covPath"), if ~isempty(app.Cov_EditField_filePath.Value), app.covAddFile(string(app.Cov_EditField_filePath.Value)); end
            elseif is("covAdd")                                                          % Pattern-tab "Coverage" button
                if app.Main == 0, return; end
                app.Cov_Tree.SelectedNodes = app.covPatternNode(app.Main); app.TabGroup.SelectedTab = app.Tab2_Coverage;
            elseif is("covToMain")
                k = app.covTarget(); if k == 0, return; end
                app.TabGroup.SelectedTab = app.Tab1_Single; app.update("switch", k); return
            elseif is("covCompute"), app.covCompute();
            elseif is("covThresh"),  app.Range.Auto.cov = false;
            elseif is("covQueryThr", "covQueryCov"), app.covQuery(scope == "covQueryThr");
            elseif is("covClear"),   delete(findobj(app.Cov_Axes, '-isa', 'matlab.graphics.datatip.DataTip'));
            elseif is("covReset"),   app.covReset();
            elseif is("covExport"),  app.covExport(); return
            end
            app.applyCovChoices(); app.covRefresh();
        end

        function c = readCoverageConfig(app)
            c = struct('Component', string(app.Cov_DropDown_Component.Value), 'Conical', logical(app.Cov_ButtonGroup_Btn_Conical.Value), ...
                       'Orientation', string(app.Cov_DropDown_Orientation.Value), ...
                       'Cone', [app.Cov_Spinner_ConeTH.Value, app.Cov_Spinner_ConePH.Value, app.Cov_Spinner_ConeAng.Value], ...
                       'T', [app.Cov_Spinner_ThreshMin.Value, app.Cov_Spinner_ThreshMax.Value, app.Cov_Spinner_Step.Value], ...
                       'QueryThr', app.Cov_Spinner_queryThresh.Value, 'QueryCov', app.Cov_Spinner_queryCov.Value, ...
                       'TextFormat', string(app.Cov_DropDown_TextFormat.Value));
        end

        function covAddFile(app, path)
            cfg = app.readConfig(); cfg.TextFormat = app.readCoverageConfig().TextFormat;
            try
                E = app.buildEntry(path, cfg, []);
            catch ME
                if ~strcmp(ME.identifier, 'APAT:CoverageFile'), rethrow(ME); end
                app.covLoadResults(path); return
            end
            k = find(arrayfun(@(e) e.Key == E.Key, app.Pats), 1);
            if isempty(k), k = numel(app.Pats) + 1; app.Pats(k) = E; elseif k ~= app.Main, app.Pats(k) = E; end   % the Pattern tab's entry is never replaced from here
            app.Cov_EditField_filePath.Value = char(path); app.Cov_Tree.SelectedNodes = app.covPatternNode(k);
            app.setStatus(app.Cov_StatusBar, sprintf('Pattern <b>%s</b> ready (params: L = %g dB).', E.Name, E.Params.Loss_dB), false);
        end

        function node = covPatternNode(app, k)
            nodes = app.covNodes(); node = nodes(arrayfun(@(n) n.NodeData.kind == "pattern" && n.NodeData.k == k, nodes));
            if isempty(node), node = uitreenode(app.Cov_Tree, 'Text', ['📡 ' char(app.Pats(k).Name)], 'NodeData', struct('kind', "pattern", 'k', k)); end
        end

        function nodes = covNodes(app, parent)
            if nargin < 2, parent = app.Cov_Tree; end
            nodes = gobjects(0, 1);
            for c = parent.Children(:).', nodes = [nodes; c; app.covNodes(c)]; end %#ok<AGROW>
        end

        function [jobs, checked] = covJobs(app)
            nodes = app.covNodes(); jobs = nodes(arrayfun(@(n) n.NodeData.kind == "job", nodes));
            if ~isempty(jobs), [~, o] = sort(arrayfun(@(n) n.NodeData.id, jobs)); jobs = jobs(o); end
            cn = app.Cov_Tree.CheckedNodes; checked = false(size(jobs));
            if ~isempty(cn), checked = arrayfun(@(j) any(cn == j), jobs); end
        end

        function k = covTarget(app)
            %COVTARGET Registry index of the selected pattern node (or its ancestor); the Pattern-tab entry otherwise.
            k = 0; n = app.Cov_Tree.SelectedNodes;
            while ~isempty(n) && isa(n, 'matlab.ui.container.TreeNode')
                if n.NodeData.kind == "pattern", k = n.NodeData.k; break; end
                n = n.Parent;
            end
            if k == 0, k = app.Main; end
        end

        function [th, ph] = covConeAxis(app, E, c)
            switch c.Orientation
                case "auto",   i = E.Derived.Boresight; th = app.Axes6.theta(i); ph = app.Axes6.phi(i);
                case "custom", th = c.Cone(1); ph = c.Cone(2);
                otherwise,     i = find(strcmp(app.Axes6.labels, c.Orientation), 1); th = app.Axes6.theta(i); ph = app.Axes6.phi(i);
            end
        end

        function applyCovChoices(app)
            k = app.covTarget(); c = app.readCoverageConfig();
            if k > 0
                E = app.Pats(k); [names, labels] = app.componentItems(E);
                app.setDropdown(app.Cov_DropDown_Component, cellstr(labels), cellstr(names), char(E.Derived.Total));
                c.Component = string(app.Cov_DropDown_Component.Value);
                if app.Range.Auto.cov
                    pk = met_peak(E.Derived.Cols.(c.Component), E.Geometry.PhiPeriodic, app.Const.PeakExcessDB); r = util_presetRange(pk.value);
                    app.Cov_Spinner_ThreshMin.Value = r(1); app.Cov_Spinner_ThreshMax.Value = r(2);
                end
                if c.Orientation ~= "custom", [app.Cov_Spinner_ConeTH.Value, app.Cov_Spinner_ConePH.Value] = app.covConeAxis(E, c); end
            end
            set([app.Cov_Spinner_ConeTH, app.Cov_Spinner_ConePH], 'Enable', c.Conical && c.Orientation == "custom");
            set([app.Cov_Spinner_ConeAng, app.Cov_DropDown_Orientation], 'Enable', c.Conical);
            set([app.Cov_Button_computeCov, app.Cov_Button_toMain], 'Enable', k > 0);
        end

        function covCompute(app)
            k = app.covTarget(); if k == 0, error('APAT:NoPattern', 'Load a pattern before computing coverage.'); end
            E = app.Pats(k); c = app.readCoverageConfig(); C = E.Derived.Cols.(c.Component);
            T = cov_thresholds(c.T(1), c.T(2), c.T(3));
            if c.Conical
                [th, ph] = app.covConeAxis(E, c); mask = cov_coneMask(E.Pattern, th, ph, c.Cone(3));
                region = sprintf('cone %g° @ (θ %g°, φ %g°)', c.Cone(3), th, ph);
            else
                mask = true(size(C)); region = 'sphere';
            end
            cov = cov_curve(C, E.Geometry.dOmega, mask, T);
            app.JobCounter = app.JobCounter + 1;
            label = sprintf('R%d %s | %s | %s | L=%g dB | step %g dB', app.JobCounter, E.Name, app.columnLabel(E, c.Component), region, E.Params.Loss_dB, c.T(3));
            app.covAddJob(app.covPatternNode(k), app.JobCounter, label, T, cov);
            app.setStatus(app.Cov_StatusBar, sprintf('R%d computed over Ω_R = %s sr (%d thresholds).', app.JobCounter, util_fmt(sum(E.Geometry.dOmega(mask))), numel(T)), false);
        end

        function covAddJob(app, parent, id, label, T, cov)
            line = plot(app.Cov_Axes, T, cov, 'LineWidth', 1.5, 'DisplayName', label);
            node = uitreenode(parent, 'Text', label, 'NodeData', struct('kind', "job", 'id', id, 'label', label, 'T', T(:), 'cov', cov(:), 'Line', line));
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node]; expand(parent);
        end

        function covRefresh(app)
            %COVREFRESH Visible curves, the union table (one interp1 per curve), the x-range and the query buttons follow the checked jobs.
            [jobs, checked] = app.covJobs(); vis = jobs(checked);
            for j = jobs(:).', j.NodeData.Line.Visible = any(vis == j); end
            if isempty(vis)
                app.Cov_Tabel.Data = []; app.Cov_Tabel.ColumnName = {}; legend(app.Cov_Axes, 'off');
            else
                nd = [vis.NodeData]; T = unique(vertcat(nd.T)); data = nan(numel(T), numel(nd));
                for j = 1:numel(nd), data(:, j) = cov_at(nd(j).T, nd(j).cov, T); end
                app.Cov_Tabel.Data = [T data]; app.Cov_Tabel.ColumnName = [{'Threshold (dB)'}, arrayfun(@(n) sprintf('R%d (%%)', n.id), nd, 'UniformOutput', false)];
                legend(app.Cov_Axes, [nd.Line], 'Location', 'southwest', 'Interpreter', 'none');
                if app.Range.Auto.covX, app.Range.covX = [min(T), max(T) + (max(T) == min(T))]; app.applyRange("covX"); end
            end
            set(app.Cov_Axes, 'XLim', app.Range.covX, 'YLim', [0 100]);
            set([app.Cov_Button_queryThresh, app.Cov_Button_queryCov, app.Cov_Button_Export, app.Cov_Button_Clear], 'Enable', ~isempty(vis));
        end

        function covQuery(app, byThreshold)
            [jobs, checked] = app.covJobs(); c = app.readCoverageConfig(); msg = strings(1, 0);
            for j = jobs(checked).'
                d = j.NodeData;
                if byThreshold, x = c.QueryThr; y = cov_at(d.T, d.cov, x); else, y = c.QueryCov; x = thr_at(d.T, d.cov, y); end
                if isfinite(x) && isfinite(y)
                    datatip(d.Line, x, y, 'SnapToDataVertex', 'off'); msg(end+1) = sprintf('R%d: %.2f %% @ %.2f dB', d.id, y, x); %#ok<AGROW>
                else
                    msg(end+1) = sprintf('R%d: outside the curve', d.id); %#ok<AGROW>
                end
            end
            app.setStatus(app.Cov_StatusBar, char(strjoin(msg, ' | ')), false);
        end

        function covReset(app)
            jobs = app.covJobs(); for j = jobs(:).', delete(j.NodeData.Line); end
            delete(app.Cov_Tree.Children(app.Cov_Tree.Children ~= app.Cov_TreeNode_Results)); delete(app.Cov_TreeNode_Results.Children);
            delete(findobj(app.Cov_Axes, '-isa', 'matlab.graphics.datatip.DataTip'));
            app.JobCounter = 0; app.Range.Auto.cov = true; app.Range.Auto.covX = true;
            app.setStatus(app.Cov_StatusBar, 'Coverage tab reset.', true);
        end

        function covExport(app)
            if isempty(app.Cov_Tabel.Data), return; end
            [f, p] = uiputfile({'*.csv', 'CSV'; '*.xlsx', 'Excel'}, 'Export coverage table', fullfile(app.startDir(), 'coverage.csv')); if isequal(f, 0), return; end
            names = matlab.lang.makeValidName(regexprep(app.Cov_Tabel.ColumnName, '[()%]', ''));
            writetable(array2table(app.Cov_Tabel.Data, 'VariableNames', names), fullfile(p, f));
            app.setStatus(app.Cov_StatusBar, sprintf('Exported %s', fullfile(p, f)), true);
        end

        function covLoadResults(app, path)
            [T, curves, names] = io_coverageCSV(char(path)); [~, nm, ext] = fileparts(char(path));
            node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📄 ' nm ext], 'NodeData', struct('kind', "results"));
            for j = 1:size(curves, 2)
                app.JobCounter = app.JobCounter + 1;
                app.covAddJob(node, app.JobCounter, sprintf('R%d %s | %s', app.JobCounter, [nm ext], names{j}), T, curves(:, j));
            end
            expand(app.Cov_TreeNode_Results); app.Cov_Tree.SelectedNodes = node;
            app.setStatus(app.Cov_StatusBar, sprintf('Loaded %d curve(s) from <b>%s</b>.', size(curves, 2), [nm ext]), false);
        end

        %% ------------------------------------------------------------ Status bars: one timer for both
        function setStatus(app, label, msg, transient)
            if app.IsClosing, return; end
            stop(app.StatusTimer); label.Text = char(msg);
            if ~transient, app.Status.(label.Tag) = char(msg); return; end
            start(app.StatusTimer);
        end

        function restoreStatus(app)
            if app.IsClosing || ~isvalid(app.UIFigure), return; end
            app.Single_StatusBar.Text = app.Status.Main; app.Cov_StatusBar.Text = app.Status.Cov;
        end

        %% ------------------------------------------------------------ Layout: one declaration per widget (M7 names, M7 defaults)
        function h = place(app, name, ctor, parent, row, col, varargin)
            h = ctor(parent, varargin{:}); h.Layout.Row = row; h.Layout.Column = col; app.(name) = h;
        end

        function g = grid(~, parent, rows, cols)
            g = uigridlayout(parent, [numel(rows) numel(cols)], 'RowHeight', rows, 'ColumnWidth', cols, 'Padding', [4 4 4 4], 'RowSpacing', 4, 'ColumnSpacing', 6);
        end

        function h = labelled(app, labelName, text, ctlName, ctor, parent, row, col, varargin)
            app.place(labelName, @uilabel, parent, row, col, 'Text', text, 'HorizontalAlignment', 'right');
            h = app.place(ctlName, ctor, parent, row, col + 1, varargin{:});
        end

        function patternTab(app, tag, tabName, gridName, title, axesName, sliderName, minName, maxName)
            tab = uitab(app.Single_tabPlots, 'Title', title, 'Tag', tag); app.(tabName) = tab;
            g = app.grid(tab, {'1x', 24}, {70, '1x', 70}); app.(gridName) = g;
            if strcmp(axesName, 'Single_paxPattern'), ax = polaraxes(g); else, ax = uiaxes(g); end
            ax.Layout.Row = 1; ax.Layout.Column = [1 3]; app.(axesName) = ax;
            rng = @(s, ~) app.on("range", s);
            app.place(minName, @uispinner, g, 2, 1, 'Tag', 'full', 'ValueChangedFcn', rng);
            app.place(sliderName, @(p, varargin) uislider(p, 'range', varargin{:}), g, 2, 2, 'Tag', 'full', 'MajorTicks', [], 'MinorTicks', [], 'ValueChangedFcn', rng);
            app.place(maxName, @uispinner, g, 2, 3, 'Tag', 'full', 'ValueChangedFcn', rng);
        end

        function createComponents(app)
            C = app.Const; cb = @(s) @(~, ~) app.on(s); rng = @(s, ~) app.on("range", s);
            slider = @(p, varargin) uislider(p, 'range', 'MajorTicks', [], 'MinorTicks', [], varargin{:});
            app.UIFigure = uifigure('Visible', 'off', 'Position', [40 40 1560 900], 'Name', sprintf('%s (%s)', C.ReleaseName, C.ReleaseVersion), 'CloseRequestFcn', @(~, ~) delete(app));
            app.GridLayout = app.grid(app.UIFigure, {'1x'}, {'1x'});
            app.place('TabGroup', @uitabgroup, app.GridLayout, 1, 1);
            app.Tab1_Single = uitab(app.TabGroup, 'Title', 'Pattern'); app.Tab2_Coverage = uitab(app.TabGroup, 'Title', 'Coverage');
            % ---- Pattern tab: parameters (row 1, left)
            app.Single_Grid = app.grid(app.Tab1_Single, {'fit', '1x', '1x', 22}, {'1x', '1.4x'});
            app.place('Single_panelParam', @uipanel, app.Single_Grid, 1, 1, 'Title', 'Input & parameters');
            g = app.grid(app.Single_panelParam, repmat({22}, 1, 6), {95, '1x', 62, 100, '1x', 62, 100}); app.Single_gridPanel_Param = g;
            app.labelled('InputPatternLabel', 'Input pattern', 'Single_EditField_Path', @uieditfield, g, 1, 1, 'ValueChangedFcn', cb("path")); app.Single_EditField_Path.Layout.Column = [2 6];
            app.place('Single_Button_Load', @uibutton, g, 1, 7, 'Text', 'Load…', 'ButtonPushedFcn', cb("load"));
            app.labelled('FFDFreqDropDownLabel', 'Frequency', 'Single_DropDown_FFD', @uidropdown, g, 2, 1, 'Items', {'—'}, 'ItemsData', {1}, 'ValueChangedFcn', cb("freq")); app.Single_DropDown_FFD.Layout.Column = [2 3];
            app.labelled('TextFormatLabel', 'Text format', 'Single_DropDown_TextFormat', @uidropdown, g, 2, 4, 'Items', {'Auto (header / ranges)', 'Gain table (dBi)', 'Re/Im fields', 'Mag(dB)/phase fields'}, 'ItemsData', {'auto', 'gain', 'reim', 'magphase'}, 'ValueChangedFcn', cb("format")); app.Single_DropDown_TextFormat.Layout.Column = [5 6];
            app.place('Single_DropDown_step', @uidropdown, g, 2, 7, 'Items', {'STEP: native'}, 'ItemsData', {'native'}, 'ValueChangedFcn', cb("step"));
            app.labelled('LossindBLabel', 'Loss (dB)', 'Single_Spinner_Loss', @uispinner, g, 3, 1, 'Step', 0.5);
            app.labelled('RxPolLabel', 'Rx polarization', 'Single_DropDown_RxPol', @uidropdown, g, 3, 4, 'Items', {'Auto', 'RHCP', 'LHCP'}); app.Single_DropDown_RxPol.Layout.Column = [5 6];
            app.place('Single_Button_Process', @uibutton, g, 3, 7, 'Text', 'Process', 'ButtonPushedFcn', cb("params"));
            app.labelled('IncidentWaveARRwPLFLabel', 'Wave AR (dB)', 'Single_Spinner_Rw', @uispinner, g, 4, 1, 'Limits', [0 100], 'Step', 0.5);
            app.labelled('TransmitPowerLabel', 'Tx power', 'Single_Spinner_Pt', @uispinner, g, 4, 4);
            app.place('Single_DropDown_Pt', @uidropdown, g, 4, 6, 'Items', {'dBW', 'dBm', 'Watts'});
            app.place('Single_Button_ResetParams', @uibutton, g, 4, 7, 'Text', 'Reset params', 'ButtonPushedFcn', cb("reset"));
            app.labelled('DistanceLabel', 'Distance', 'Single_Spinner_R', @uispinner, g, 5, 1, 'Value', 1, 'Limits', [0 Inf]);
            app.place('Single_DropDown_R', @uidropdown, g, 5, 3, 'Items', {'m', 'km'});
            app.place('Single_Export_UAN', @uibutton, g, 5, [5 6], 'Text', 'Export UAN', 'ButtonPushedFcn', @(~, ~) app.on("export", "uan"));
            app.place('Single_Export_Output', @uibutton, g, 5, 7, 'Text', 'Export output', 'ButtonPushedFcn', @(~, ~) app.on("export", "output"));
            app.place('Single_Button_Coverage', @uibutton, g, 6, 7, 'Text', 'Coverage ▸', 'ButtonPushedFcn', cb("covAdd"));
            % ---- Pattern tab: plot control (row 1, right)
            app.place('Single_Panel_plotControl', @uipanel, app.Single_Grid, 1, 2, 'Title', 'Plot control');
            g = app.grid(app.Single_Panel_plotControl, repmat({24}, 1, 5), {80, '1x', 80, '1x', 90, '1x'}); app.Single_gridPanel_Ctrl = g;
            app.labelled('ComponentLabel', 'Component', 'Single_DropDown_Component', @uidropdown, g, 1, 1, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', cb("component"));
            app.labelled('CuttypeDropDownLabel', 'Cut type', 'Single_DropDown_cutType', @uidropdown, g, 1, 3, 'Items', {'θ-cut (fixed φ)', 'φ-cut (fixed θ)'}, 'ItemsData', {'Theta', 'Phi'}, 'ValueChangedFcn', cb("cuttype"));
            app.labelled('CutvalueSpinnerLabel', 'Fixed φ (°)', 'Single_DropDown_cutValue', @uispinner, g, 1, 5, 'ValueChangedFcn', cb("cut"));
            app.place('CutFieldBasisDropDown', @uidropdown, g, 2, [1 2], 'Items', {'Auto', 'Linear', 'Circular'}, 'ValueChangedFcn', cb("basis"));
            app.place('Single_Switch_EHplane', @uiswitch, g, 2, [3 4], 'Items', {'E', 'H'}, 'ValueChangedFcn', cb("plane"));
            app.labelled('View3DLabel', '3D view', 'Single_DropDown_3DView', @uidropdown, g, 2, 5, 'Items', {'Isometric', 'Top (+Z)', 'Front (+X)', 'Side (+Y)'}, 'ItemsData', {'iso', 'top', 'front', 'side'}, 'ValueChangedFcn', cb("view3d"));
            app.place('Single_Switch_AngularSpan', @uiswitch, g, 3, [1 2], 'Items', {'0° to 360°', '-180° to 180°'}, 'ValueChangedFcn', cb("span"));
            app.place('Single_Switch_ThetaSpan', @uiswitch, g, 3, [3 4], 'Items', {'0° to 180°', '-90° to 90°'}, 'ValueChangedFcn', cb("span"));
            app.place('Singel_CheckBox_overlayCut', @uicheckbox, g, 3, [5 6], 'Text', 'Overlay cut on full pattern', 'ValueChangedFcn', cb("overlay"));
            app.labelled('ColorbarminLabel', 'Color min', 'Single_Plot_Cmin', @uispinner, g, 4, 1, 'Tag', 'full', 'ValueChangedFcn', rng);
            app.labelled('ColorbarmaxLabel', 'Color max', 'Single_Plot_Cmax', @uispinner, g, 4, 3, 'Tag', 'full', 'ValueChangedFcn', rng);
            app.labelled('ColorbarstepLabel', 'Color step', 'Single_Plot_Cstep', @uispinner, g, 4, 5, 'Value', 5, 'Limits', [0.1 100], 'ValueChangedFcn', cb("cstep"));
            app.place('Single_CheckBox_POB', @uicheckbox, g, 5, [1 2], 'Text', 'POB marker', 'Value', true, 'ValueChangedFcn', cb("pob"));
            app.place('Single_CheckBox_HPBWBounds', @uicheckbox, g, 5, [3 4], 'Text', 'HPBW bounds', 'Value', true, 'ValueChangedFcn', cb("hpbw"));
            app.place('Single_Button_Clim', @uibutton, g, 5, 5, 'Text', 'Auto range', 'ButtonPushedFcn', cb("autorange"));
            app.place('Single_Label_Clim', @uilabel, g, 5, 6, 'Text', '');
            % ---- Pattern tab: cuts (row 2, left)
            app.place('Single_Panel_Rect', @uipanel, app.Single_Grid, 2, 1, 'Title', 'Cuts');
            app.Single_gridPanel_Cut = app.grid(app.Single_Panel_Rect, {'1x'}, {'1x'});
            app.place('Single_tabCut', @uitabgroup, app.Single_gridPanel_Cut, 1, 1);
            app.Single_tabPolarPlot = uitab(app.Single_tabCut, 'Title', 'Polar'); app.Single_tabRectPlot = uitab(app.Single_tabCut, 'Title', 'Rectangular');
            g = app.grid(app.Single_tabPolarPlot, {24, '1x', 24}, {70, '1x', 90, 70, '1x', 70}); app.Single_Grid_Polar = g;
            e = app.place('Single_gridEcut', @uigridlayout, g, 1, [1 6], [1 3], 'Padding', [0 0 0 0], 'RowHeight', {22});
            app.place('CheckBox_Et', @uicheckbox, e, 1, 1, 'Text', 'Total', 'Value', true, 'ValueChangedFcn', cb("traces"));
            app.place('CheckBox_Er', @uicheckbox, e, 1, 2, 'Text', 'Co-pol', 'Value', true, 'ValueChangedFcn', cb("traces"));
            app.place('CheckBox_El', @uicheckbox, e, 1, 3, 'Text', 'Cross-pol', 'Value', true, 'ValueChangedFcn', cb("traces"));
            app.Single_paxCut = polaraxes(g); app.Single_paxCut.Layout.Row = 2; app.Single_paxCut.Layout.Column = [1 6];
            app.place('Button_HPBW', @uibutton, g, 3, 1, 'state', 'Text', 'HPBW', 'Value', true, 'ValueChangedFcn', cb("hpbw"));
            app.place('Label_HPBW', @uilabel, g, 3, 2, 'Text', '');
            app.place('Button_ExportCut', @uibutton, g, 3, 3, 'Text', 'Export cut', 'ButtonPushedFcn', @(~, ~) app.on("export", "cut"));
            app.place('Range_Cut_Min', @uispinner, g, 3, 4, 'Tag', 'cut', 'ValueChangedFcn', rng);
            app.place('Range_Cut', slider, g, 3, 5, 'Tag', 'cut', 'ValueChangedFcn', rng);
            app.place('Range_Cut_Max', @uispinner, g, 3, 6, 'Tag', 'cut', 'ValueChangedFcn', rng);
            app.Single_gridRect = app.grid(app.Single_tabRectPlot, {'1x'}, {'1x'});
            app.place('Single_AxesRect', @uiaxes, app.Single_gridRect, 1, 1);
            % ---- Pattern tab: data tables (row 3, left)
            app.place('Single_tabData', @uitabgroup, app.Single_Grid, 3, 1, 'SelectionChangedFcn', cb("tab"));
            app.Single_tabDataOut = uitab(app.Single_tabData, 'Title', 'Output data', 'Tag', 'out');
            app.Single_tabDataIn = uitab(app.Single_tabData, 'Title', 'Input data', 'Tag', 'in');
            app.MetadataTab = uitab(app.Single_tabData, 'Title', 'Metadata', 'Tag', 'meta');
            app.Single_gridDataOut = app.grid(app.Single_tabDataOut, {22, '1x'}, {200, '1x'});
            app.place('Single_DropDown_output', @uidropdown, app.Single_gridDataOut, 1, 1, 'Items', {'Standard columns', 'All columns'}, 'ItemsData', {'std', 'all'}, 'ValueChangedFcn', cb("tab"));
            app.place('Single_Table_DataOut', @uitable, app.Single_gridDataOut, 2, [1 2]);
            app.Single_gridDataIn = app.grid(app.Single_tabDataIn, {'1x'}, {'1x'});
            app.place('Single_Table_DataIn', @uitable, app.Single_gridDataIn, 1, 1);
            app.Single_gridMetadata = app.grid(app.MetadataTab, {'1x'}, {'1x'});
            app.place('Single_Table_metadata', @uitable, app.Single_gridMetadata, 1, 1, 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {170, 'auto'});
            % ---- Pattern tab: full-pattern views (rows 2–3, right) and status bar
            app.place('Single_Panel_fullPattern', @uipanel, app.Single_Grid, [2 3], 2, 'Title', 'Full pattern');
            app.Single_gridPanel_full = app.grid(app.Single_Panel_fullPattern, {'1x'}, {'1x'});
            app.place('Single_tabPlots', @uitabgroup, app.Single_gridPanel_full, 1, 1, 'SelectionChangedFcn', cb("tab"));
            app.patternTab('1', 'Single_tabContour', 'Single_gridContour', 'Contour', 'Single_Axes_Ctr', 'Range_Ctr', 'Range_Ctr_Min', 'Range_Ctr_Max');
            app.patternTab('2', 'Single_tabCircular', 'Single_gridCircular', 'Circular', 'Single_paxPattern', 'Range_Cir', 'Range_Cir_Min', 'Range_Cir_Max');
            app.patternTab('3', 'Single_tab3DSpherical', 'Single_grid3dSpherical', '3D spherical', 'Single_Axes_3dSph', 'Range_3dSph', 'Range_3dSph_Min', 'Range_3dSph_Max');
            app.patternTab('4', 'Single_tab3DPolar', 'Single_grid3dPolar', '3D polar', 'Single_Axes_3dPol', 'Range_3dPol', 'Range_3dPol_Min', 'Range_3dPol_Max');
            app.patternTab('5', 'Single_tab3DRect', 'Single_grid3dRect', '3D rectangular', 'Single_Axes_3dRect', 'Range_3dRect', 'Range_3dRect_Min', 'Range_3dRect_Max');
            app.place('Single_StatusBar', @uilabel, app.Single_Grid, 4, [1 2], 'Text', '', 'Interpreter', 'html', 'Tag', 'Main');
            % ---- Coverage tab
            app.Cov_Grid = app.grid(app.Tab2_Coverage, {'1x', 22}, {340, '1x'});
            app.place('Cov_Panel_Param', @uipanel, app.Cov_Grid, 1, 1, 'Title', 'Coverage parameters');
            g = app.grid(app.Cov_Panel_Param, [repmat({24}, 1, 15), {'1x'}], {105, '1x', 80}); app.Cov_gridPanel_Parm = g;
            app.labelled('AntennaPatternEditFieldLabel', 'Antenna pattern', 'Cov_EditField_filePath', @uieditfield, g, 1, 1, 'ValueChangedFcn', cb("covPath"));
            app.place('Cov_Button_Load', @uibutton, g, 1, 3, 'Text', 'Load…', 'ButtonPushedFcn', cb("covLoad"));
            app.labelled('Cov_TextFormatLabel', 'Text format', 'Cov_DropDown_TextFormat', @uidropdown, g, 2, 1, 'Items', app.Single_DropDown_TextFormat.Items, 'ItemsData', app.Single_DropDown_TextFormat.ItemsData); app.Cov_DropDown_TextFormat.Layout.Column = [2 3];
            app.labelled('Cov_DropDown_ComponentLabel', 'Component', 'Cov_DropDown_Component', @uidropdown, g, 3, 1, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', cb("covComponent")); app.Cov_DropDown_Component.Layout.Column = [2 3];
            bg = app.place('Cov_ButtonGroup_CovType', @uibuttongroup, g, 4, [1 3], 'BorderType', 'none', 'SelectionChangedFcn', cb("covRegion"));
            app.Cov_ButtonGroup_Btn_Spherical = uiradiobutton(bg, 'Text', 'Spherical (whole grid)', 'Position', [6 2 150 22], 'Value', true);
            app.Cov_ButtonGroup_Btn_Conical = uiradiobutton(bg, 'Text', 'Conical region', 'Position', [170 2 140 22]);
            app.labelled('Cov_DropDown_OrientationLabel', 'Cone axis', 'Cov_DropDown_Orientation', @uidropdown, g, 5, 1, 'Items', [{'Boresight (auto)'}, app.Axes6.labels, {'Custom'}], 'ItemsData', [{'auto'}, app.Axes6.labels, {'custom'}], 'ValueChangedFcn', cb("covRegion")); app.Cov_DropDown_Orientation.Layout.Column = [2 3];
            app.labelled('ConeSpinnerLabel', 'Cone θ (°)', 'Cov_Spinner_ConeTH', @uispinner, g, 6, 1, 'Limits', [0 180], 'ValueChangedFcn', cb("covRegion")); app.Cov_Spinner_ConeTH.Layout.Column = [2 3];
            app.labelled('ConeLabel', 'Cone φ (°)', 'Cov_Spinner_ConePH', @uispinner, g, 7, 1, 'Limits', [0 360], 'ValueChangedFcn', cb("covRegion")); app.Cov_Spinner_ConePH.Layout.Column = [2 3];
            app.labelled('ConeAngleLabel', 'Half-angle (°)', 'Cov_Spinner_ConeAng', @uispinner, g, 8, 1, 'Value', 45, 'Limits', [0 180], 'ValueChangedFcn', cb("covRegion")); app.Cov_Spinner_ConeAng.Layout.Column = [2 3];
            app.labelled('ThresholdMindBSpinnerLabel', 'Threshold min', 'Cov_Spinner_ThreshMin', @uispinner, g, 9, 1, 'Value', -40, 'ValueChangedFcn', cb("covThresh")); app.Cov_Spinner_ThreshMin.Layout.Column = [2 3];
            app.labelled('ThresholdMaxdBSpinnerLabel', 'Threshold max', 'Cov_Spinner_ThreshMax', @uispinner, g, 10, 1, 'Value', 10, 'ValueChangedFcn', cb("covThresh")); app.Cov_Spinner_ThreshMax.Layout.Column = [2 3];
            app.labelled('StepdBSpinnerLabel', 'Step (dB)', 'Cov_Spinner_Step', @uispinner, g, 11, 1, 'Value', 1, 'Limits', [0.01 50], 'Step', 0.5); app.Cov_Spinner_Step.Layout.Column = [2 3];
            app.place('Cov_Button_computeCov', @uibutton, g, 12, [1 2], 'Text', 'Compute coverage', 'ButtonPushedFcn', cb("covCompute"));
            app.place('Cov_Button_Reset', @uibutton, g, 12, 3, 'Text', 'Reset', 'ButtonPushedFcn', cb("covReset"));
            app.labelled('Cov_QueryThresholdLabel', 'Query T (dB)', 'Cov_Spinner_queryThresh', @uispinner, g, 13, 1);
            app.place('Cov_Button_queryThresh', @uibutton, g, 13, 3, 'Text', '→ cov %', 'ButtonPushedFcn', cb("covQueryThr"));
            app.labelled('Cov_QueryCoverageLabel', 'Query cov (%)', 'Cov_Spinner_queryCov', @uispinner, g, 14, 1, 'Value', 90, 'Limits', [0 100]);
            app.place('Cov_Button_queryCov', @uibutton, g, 14, 3, 'Text', '→ T (dB)', 'ButtonPushedFcn', cb("covQueryCov"));
            app.place('Cov_Button_Clear', @uibutton, g, 15, 1, 'Text', 'Clear tips', 'ButtonPushedFcn', cb("covClear"));
            app.place('Cov_Button_Export', @uibutton, g, 15, 2, 'Text', 'Export table', 'ButtonPushedFcn', cb("covExport"));
            app.place('Cov_Button_toMain', @uibutton, g, 15, 3, 'Text', '◂ Pattern', 'ButtonPushedFcn', cb("covToMain"));
            app.place('Cov_Panel_Results', @uipanel, app.Cov_Grid, 1, 2, 'Title', 'Coverage results');
            g = app.grid(app.Cov_Panel_Results, {'1x', 24, 170}, {300, 70, '1x', 70}); app.GridLayout2 = g;
            app.place('Cov_Tree', @uitree, g, [1 3], 1, 'checkbox', 'CheckedNodesChangedFcn', cb("covTree"), 'SelectionChangedFcn', cb("covTree"));
            app.Cov_TreeNode_Results = uitreenode(app.Cov_Tree, 'Text', '📄 Loaded results', 'NodeData', struct('kind', "results"));
            ax = app.place('Cov_Axes', @uiaxes, g, 1, [2 4]); hold(ax, 'on'); box(ax, 'on'); set(ax, 'XGrid', 'on', 'YGrid', 'on');
            xlabel(ax, 'Threshold (dB)'); ylabel(ax, 'Coverage (%)'); title(ax, 'Coverage(T) = 100 · Ω_R(G > T) / Ω_R');
            app.place('Cov_Spinner_XMin', @uispinner, g, 2, 2, 'Tag', 'covX', 'ValueChangedFcn', rng);
            app.place('Cov_Spinner_XRange', slider, g, 2, 3, 'Tag', 'covX', 'ValueChangedFcn', rng);
            app.place('Cov_Spinner_XMax', @uispinner, g, 2, 4, 'Tag', 'covX', 'ValueChangedFcn', rng);
            app.place('Cov_Tabel', @uitable, g, 3, [2 4]);
            app.place('Cov_StatusBar', @uilabel, app.Cov_Grid, 2, [1 2], 'Text', '', 'Interpreter', 'html', 'Tag', 'Cov');
        end
    end
end

%% ==================================================================== File-scope functions (app-free, widget-free)
%% ---------------------------------------------------------------------- Pattern: canonical grid, resampling, geometry, map, cut
function P = pat_build(S, f, Const)
%PAT_BUILD Source block f → canonical grid-native pattern: θ polar ascending in [0,180], φ ascending in [0,360), uniform
%   steps asserted once, no seam column. Angles are snapped to Const.AngleDecimals; field values are never rounded.
    B = S.Blocks{f}; th = double(B.Theta(:)); ph = double(B.Phi(:)); notes = S.Meta.Notes;
    if S.Meta.ThetaConvention == "elevation", th = 90 - th; end
    th = mod(th, 360); over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;  % negative θ / θ > 180: mirror through the pole
    th = round(th, Const.AngleDecimals); ph = round(mod(ph, 360), Const.AngleDecimals); ph(ph >= 360) = 0;
    [~, keep] = unique([th, ph], 'rows', 'first'); keep = sort(keep); th = th(keep); ph = ph(keep);  % φ = 360 copies of φ = 0 vanish here
    if numel(unique(ph)) == 1                                                                       % one cut: body of revolution (disclosed)
        m = round(360/Const.RevolutionPhiStep); n = numel(th);
        ph = repelem((0:m-1).'*Const.RevolutionPhiStep, n); th = repmat(th, m, 1); keep = repmat(keep, m, 1);
        notes(end+1) = sprintf("single φ cut replicated every %g° (body of revolution)", Const.RevolutionPhiStep);
    end
    theta = unique(th); phi = unique(ph); sz = [numel(theta), numel(phi)];
    [~, it] = ismember(th, theta); [~, jp] = ismember(ph, phi);
    sampleOf = zeros(sz); sampleOf(sub2ind(sz, it, jp)) = 1:numel(th);
    for r = find(ismember(theta, [0 180])).'                                    % a pole is one direction: its sample serves every φ
        have = find(sampleOf(r, :), 1); if ~isempty(have), sampleOf(r, sampleOf(r, :) == 0) = sampleOf(r, have); end
    end
    if any(sampleOf(:) == 0)
        error('APAT:IrregularGrid', 'The pattern is not a complete θ×φ grid: %d of %d cells are filled.', nnz(sampleOf), prod(sz));
    end
    P = struct('Theta', theta, 'Phi', phi, 'dTheta', util_uniformStep(theta, 'θ', Const.UniformTolDeg), ...
               'dPhi', util_uniformStep(phi, 'φ', Const.UniformTolDeg), 'IsGainOnly', S.Meta.IsGainOnly, 'Freq', S.Freqs(f), 'Meta', S.Meta);
    if isnan(P.dTheta), P.dTheta = 180; end
    if isnan(P.dPhi), P.dPhi = 360; end
    P.Meta.Notes = notes;
    if P.IsGainOnly
        for nm = string(fieldnames(B.G)).', v = B.G.(nm)(keep); P.G.(nm) = v(sampleOf); end
    else
        v = B.Eth(keep); P.Eth = v(sampleOf); v = B.Eph(keep); P.Eph = v(sampleOf);
    end
end

function P = pat_resample(P, step)
%PAT_RESAMPLE Resample onto STEP degrees inside the source domain: exact decimation when the ratio is an integer, otherwise
%   bilinear in linear power + unit phasor (fields) or linear power (gain-kind columns); dB, AR and phases are never interpolated.
    if numel(P.Theta) < 2 || numel(P.Phi) < 2, return; end
    periodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6; rT = step/P.dTheta; rP = step/P.dPhi;
    decimate = abs(rT - round(rT)) < 1e-9 && abs(rP - round(rP)) < 1e-9;
    if decimate
        it = 1:round(rT):numel(P.Theta); jp = 1:round(rP):numel(P.Phi); th = P.Theta(it); ph = P.Phi(jp); pick = @(A, ~) A(it, jp);
    else
        th = (P.Theta(1):step:P.Theta(end) + 1e-9).'; last = util_iif(periodic, P.Phi(1) + 360 - step, P.Phi(end));
        ph = (P.Phi(1):step:last + 1e-9).'; phs = P.Phi; ext = @(A) A;
        if periodic, phs = [P.Phi; P.Phi(1) + 360]; ext = @(A) [A, A(:, 1)]; end                    % φ-closed grid for interpolation
        [PQ, TQ] = meshgrid(ph, th); lin = @(A, method) interp2(phs, P.Theta, ext(A), PQ, TQ, method);
        pick = @(A, kind) util_interpKind(A, kind, lin);
    end
    if P.IsGainOnly
        for nm = string(fieldnames(P.G)).', P.G.(nm) = pick(P.G.(nm), util_colKind(nm)); end
    else
        P.Eth = pick(P.Eth, "field"); P.Eph = pick(P.Eph, "field");
    end
    P.Theta = th; P.Phi = mod(ph, 360); P.dTheta = util_iif(numel(th) > 1, step, 180); P.dPhi = util_iif(numel(ph) > 1, step, 360);
    P.Meta.Notes(end+1) = sprintf("resampled to %g° by %s", step, util_iif(decimate, "exact decimation", "bilinear power + unit-phasor interpolation"));
end

function G = geo_build(P)
%GEO_BUILD Separable exact solid angle: ΔΩ(i,j) = wθ(i)·Δφ, wθ = cos(θ−Δθ/2) − cos(θ+Δθ/2) clipped to [0°,180°]; Σ ΔΩ = 4π on a full sphere.
    lo = max(P.Theta - P.dTheta/2, 0); hi = min(P.Theta + P.dTheta/2, 180);
    G.wTheta = cosd(lo) - cosd(hi); G.dPhiRad = deg2rad(P.dPhi);
    G.dOmega = repmat(G.wTheta*G.dPhiRad, 1, numel(P.Phi)); G.Omega = sum(G.dOmega(:));
    G.PhiPeriodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
    G.IsFullSphere = G.PhiPeriodic && lo(1) <= 1e-9 && hi(end) >= 180 - 1e-9;
end

function M = geo_displayMap(P, G, view)
%GEO_DISPLAYMAP Display convention as a column permutation plus axis labels: no number in Pattern/Geometry/Derived changes.
    n = numel(P.Phi); j0 = find(P.Phi >= 180, 1); perm = 1:n;
    if view.SignedPhi && ~isempty(j0), perm = [j0:n, 1:j0-1]; end
    M.ColIdx = perm; M.PhiAxis = P.Phi(perm);
    if view.SignedPhi, M.PhiAxis(M.PhiAxis >= 180) = M.PhiAxis(M.PhiAxis >= 180) - 360; end
    if G.PhiPeriodic, M.ColIdx(end+1) = perm(1); M.PhiAxis(end+1) = M.PhiAxis(1) + 360; end   % closing column, display only
    if view.Elevation, M.ThetaAxis = 90 - P.Theta; M.ThetaDir = 'normal'; M.ThetaLabel = 'Elevation (°)';
    else,              M.ThetaAxis = P.Theta;      M.ThetaDir = 'reverse'; M.ThetaLabel = 'θ (°)'; end
    M.Key = sprintf('%d|%d', view.SignedPhi, view.Elevation);
end

function cut = geo_cut(P, cutType, fixed)
%GEO_CUT One full-circle cut. "Phi": fixed θ, φ sweeps [0,360). "Theta": fixed φ, θ sweeps 0→180 on φ then 180→360 on φ+180.
    sz = [numel(P.Theta), numel(P.Phi)]; wrapd = @(a, b) abs(mod(a - b + 180, 360) - 180);
    if cutType == "Phi"
        [d, i] = min(abs(P.Theta - fixed)); cut.Fixed = P.Theta(i); cut.Symbol = 'θ';
        cut.Idx = sub2ind(sz, repmat(i, sz(2), 1), (1:sz(2)).'); cut.Angle = P.Phi;
    else
        [d, j] = min(wrapd(P.Phi, fixed)); [d2, j2] = min(wrapd(P.Phi, P.Phi(j) + 180)); cut.Fixed = P.Phi(j); cut.Symbol = 'φ';
        back = flipud(find(P.Theta < 180 - 1e-9)); if j2 == j || d2 > P.dPhi/2 + 1e-9, back = zeros(0, 1); end   % no opposite half-plane
        cut.Idx = [sub2ind(sz, (1:sz(1)).', repmat(j, sz(1), 1)); sub2ind(sz, back, repmat(j2, numel(back), 1))];
        cut.Angle = [P.Theta; 360 - P.Theta(back)];
    end
    cut.Snapped = d > 1e-9;
end

%% ---------------------------------------------------------------------- Derivation: every column and every base fact
function D = pat_derive(P, G, prm, Const, Axes6)
%PAT_DERIVE Pattern + parameters → every column and every base fact. The only function that reads loss / Rx / Pt / R.
%   Runs once per (pattern, params) in tens of milliseconds; nothing downstream adds, scales or shifts a value.
    pairs = struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]);
    D = struct('Cols', struct(), 'Kind', struct(), 'Unit', P.Meta.UnitLabel, 'Pol', struct('Label', "n/a", 'Basis', "Linear", 'Pairs', pairs));
    if P.IsGainOnly
        names = string(fieldnames(P.G)).'; kinds = arrayfun(@util_colKind, names);
        for k = 1:numel(names), D.Cols.(names(k)) = P.G.(names(k)) + prm.Loss_dB*(kinds(k) == "gain"); end   % loss on gain-kind columns only
        i = find(kinds == "gain", 1); if isempty(i), i = 1; end; D.Total = names(i);
    else
        s = 10^(prm.Loss_dB/20); Eth = P.Eth*s; Eph = P.Eph*s; Er = pol_circular(Eth, Eph, 1); El = pol_circular(Eth, Eph, 2);
        dB = @(E) 20*log10(max(abs(E), realmin)); ph = @(E) rad2deg(angle(E));
        total = 10*log10(max(abs(Eth).^2 + abs(Eph).^2, realmin));
        pk = met_peak(total, G.PhiPeriodic, Const.PeakExcessDB);
        w = G.dOmega .* (total >= pk.value - 3 & ~pk.spike); pw = @(E) sum(abs(E(:)).^2 .* w(:), 'omitnan');   % main-beam Ω-weighted powers
        if pw(Eph) > pw(Eth), pairs.Linear = fliplr(pairs.Linear); end
        if pw(El) > pw(Er), pairs.Circular = fliplr(pairs.Circular); end
        if max(pw(Er), pw(El)) > max(pw(Eth), pw(Eph))
            D.Pol = struct('Label', "Circular (" + replace(pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]) + ")", 'Basis', "Circular", 'Pairs', pairs);
        else
            D.Pol = struct('Label', util_iif(pairs.Linear(1) == "E_TH", "Linear (Vertical)", "Linear (Horizontal)"), 'Basis', "Linear", 'Pairs', pairs);
        end
        switch prm.RxMode
            case "RHCP", sense = 1;
            case "LHCP", sense = -1;
            otherwise,   sense = 2*(pairs.Circular(1) == "E_RCP") - 1;                   % Auto: the antenna's own circular sense
        end
        PLF = pol_plf(Er, El, sense*10^(prm.RxAR_dB/20), Const.FloorDB);
        D.Cols = struct('E_Total_dB', total, 'E_TH_dB', dB(Eth), 'E_PH_dB', dB(Eph), 'E_RCP_dB', dB(Er), 'E_LCP_dB', dB(El), ...
                        'AR_dB', pol_signedAR(Er, El, Const.LinearAR_dB), 'PLF_dB', PLF, 'Gain_PolCorrected_dB', total + PLF, ...
                        'E_TH_Phase', ph(Eth), 'E_PH_Phase', ph(Eph), 'E_RCP_Phase', ph(Er), 'E_LCP_Phase', ph(El));
        if P.Meta.Unit == "dBi"                                                          % link-budget columns need calibrated gain
            eirp = prm.Pt_dBW + total; W = 10.^(eirp/10);
            D.Cols.EIRP_dBW = eirp; D.Cols.PFD_Wm2 = W/(4*pi*prm.R_m^2); D.Cols.E_RMS_Vm = sqrt(30*W)/prm.R_m;
        end
        D.Total = "E_Total_dB";
    end
    for nm = string(fieldnames(D.Cols)).', D.Kind.(nm) = util_colKind(nm); end
    % ---- base facts on total gain: peak, boresight axis, principal planes, metrics
    Gt = D.Cols.(D.Total); D.Peak = met_peak(Gt, G.PhiPeriodic, Const.PeakExcessDB);
    [pi_, pj] = ind2sub(size(Gt), D.Peak.index); D.Peak.Theta = P.Theta(pi_); D.Peak.Phi = P.Phi(pj);
    [PH, TH] = meshgrid(P.Phi, P.Theta); [x, y, z] = util_sph2cart(TH, PH); [ax, ay, az] = util_sph2cart(Axes6.theta(:), Axes6.phi(:));
    w = 10.^((Gt(:) - D.Peak.value)/10) .* G.dOmega(:); w(~isfinite(w) | D.Peak.spike(:)) = 0;
    [~, D.Boresight] = max(w.' * double([x(:), y(:), z(:)]*[ax, ay, az].' >= cosd(Const.ConeHalfAngleDeg)));   % cone with most energy
    at = Axes6.theta(D.Boresight); ap = Axes6.phi(D.Boresight);
    D.Planes.E = struct('CutType', "Theta", 'Fixed', ap);
    if at == 90, D.Planes.H = struct('CutType', "Phi", 'Fixed', 90); else, D.Planes.H = struct('CutType', "Theta", 'Fixed', mod(ap + 90, 360)); end
    U = 10.^(Gt/10); U(~isfinite(U)) = 0; Prad = sum(U(:).*G.dOmega(:));
    m = struct('PeakGain_dB', D.Peak.value, 'PeakTheta_deg', D.Peak.Theta, 'PeakPhi_deg', D.Peak.Phi, ...
               'PeakDirectivity_dB', 10*log10(4*pi*10^(D.Peak.value/10)/max(Prad, realmin)), ...
               'Efficiency_pct', NaN, 'FrontBack_dB', NaN, 'AxialRatioAtPeak_dB', NaN);
    if G.IsFullSphere                                                                    % partial-sphere honesty
        cosg = cosd(TH)*cosd(D.Peak.Theta) + sind(TH)*sind(D.Peak.Theta).*cosd(PH - D.Peak.Phi); [~, b] = min(cosg(:));
        m.FrontBack_dB = D.Peak.value - Gt(b);
        if P.Meta.Unit == "dBi", m.Efficiency_pct = 100*Prad/(4*pi); if m.Efficiency_pct > 100 + 1e-6, m.Efficiency_pct = NaN; end; end
    end
    for pl = ["E", "H"]
        c = geo_cut(P, D.Planes.(pl).CutType, D.Planes.(pl).Fixed); m.(char("HPBW_" + pl + "Plane_deg")) = met_hpbw(c.Angle, Gt(c.Idx));
    end
    if isfield(D.Cols, 'AR_dB'), m.AxialRatioAtPeak_dB = D.Cols.AR_dB(D.Peak.index); end
    D.Metrics = m;
end

function K = met_peak(C, periodic, excessDB)
%MET_PEAK Spatial-isolation peak policy: a sample is a spike iff it exceeds every grid neighbour by more than EXCESSDB
%   (4-neighbours, φ wraps when periodic). Effective peak = highest non-spike sample; raw and effective peaks are both kept.
    [n, m] = size(C); nb = -inf(n, m);
    if n > 1, nb(2:n, :) = max(nb(2:n, :), C(1:n-1, :)); nb(1:n-1, :) = max(nb(1:n-1, :), C(2:n, :)); end
    if m > 1
        if periodic, L = circshift(C, 1, 2); R = circshift(C, -1, 2); else, L = [-inf(n, 1), C(:, 1:m-1)]; R = [C(:, 2:m), -inf(n, 1)]; end
        nb = max(nb, max(L, R));
    end
    nb(isinf(nb)) = C(isinf(nb));                                                        % a sample without neighbours is never a spike
    K.spike = isfinite(C) & (C - nb > excessDB);
    [K.rawValue, K.rawIndex] = max(C(:), [], 'omitnan');
    cand = C; cand(K.spike) = -Inf; [K.value, K.index] = max(cand(:), [], 'omitnan');
    K.wasAdjusted = K.spike(K.rawIndex); K.spikeCount = nnz(K.spike);
end

function [bw, lo, hi] = met_hpbw(angleDeg, gainDB)
%MET_HPBW Half-power beamwidth of a circular cut: linear interpolation of the two −3 dB crossings around the cut maximum.
    [bw, lo, hi] = deal(NaN); v = isfinite(angleDeg) & isfinite(gainDB); angleDeg = angleDeg(v); gainDB = gainDB(v);
    if numel(gainDB) < 3, return; end
    [pk, i] = max(gainDB); pa = angleDeg(i); half = pk - 3;
    [rel, o] = sort(util_wrap180(angleDeg - pa)); g = gainDB(o);
    l = find(rel < 0 & g <= half, 1, 'last'); r = find(rel > 0 & g <= half, 1, 'first');
    if isempty(l) || isempty(r) || g(l+1) == g(l) || g(r-1) == g(r), return; end
    cross = @(a, b) rel(a) + (rel(b) - rel(a))*(half - g(a))/(g(b) - g(a));
    lo = pa + cross(l, l+1); hi = pa + cross(r, r-1); bw = hi - lo;
end

%% ---------------------------------------------------------------------- Polarisation (one place each)
function E = pol_circular(Eth, Eph, which)
%POL_CIRCULAR RHCP (1) / LHCP (2) component of E = Eθ θ̂ + Eφ φ̂ under e^{+jωt}, (θ̂, φ̂, r̂) right-handed (IEEE):
%   E_R = (Eθ + jEφ)/√2, E_L = (Eθ − jEφ)/√2.  Check: E = ê_R = (θ̂ − jφ̂)/√2 gives E_R = 1, E_L = 0.
    if which == 1, E = (Eth + 1i*Eph)/sqrt(2); else, E = (Eth - 1i*Eph)/sqrt(2); end
end

function [Eth, Eph] = pol_fromCircular(Er, El)
    Eth = (Er + El)/sqrt(2); Eph = (Er - El)/(1i*sqrt(2));
end

function AR = pol_signedAR(Er, El, linearDB)
%POL_SIGNEDAR Signed axial ratio in dB: + RHCP sense, − LHCP sense, LINEARDB at numerically linear samples, capped at 250 dB.
    r = abs(Er); l = abs(El); d = r - l;
    AR = min(20*log10((r + l)./max(abs(d), realmin)), 250).*sign(d);
    AR(isfinite(d) & abs(d) <= eps*max(r + l, 1)) = linearDB; AR(~isfinite(d)) = NaN;
end

function PLF = pol_plf(Er, El, waveRatio, floorDB)
%POL_PLF Polarisation loss factor (dB) between the antenna's signed axial ratio r_a and an incident wave of signed ratio r_w,
%   worst-case tilt (cos 2Δτ = −1, as in M7):  PLF = 1/2 + [4 r_a r_w − (r_a² − 1)(r_w² − 1)] / [2 (r_a² + 1)(r_w² + 1)].
    r = abs(Er); l = abs(El); d = r - l; ra = (r + l)./max(abs(d), eps).*sign(d); ra(d == 0) = 1e12;   % linear limit
    rw = waveRatio; plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1))./(2*(ra.^2 + 1)*(rw^2 + 1));
    PLF = 10*log10(min(max(plf, 10^(floorDB/10)), 1)); PLF(~isfinite(d)) = NaN;                        % NaN fields stay NaN
end

%% ---------------------------------------------------------------------- Coverage: the definition, and curve reads
function cov = cov_curve(C, dOmega, mask, T)
%COV_CURVE Coverage(T) = 100 · Ω_R(C > T) / Ω_R,  Ω_R(C > T) = Σ_{(i,j)∈R, C(i,j) > T} ΔΩ(i,j)   (strict ">", O(N) memory).
    v = mask & isfinite(C); g = C(v); w = dOmega(v); Omega = sum(w);
    cov = zeros(size(T)); if Omega <= 0, return; end
    for k = 1:numel(T), cov(k) = 100*sum(w(g > T(k)))/Omega; end
end

function m = cov_coneMask(P, thC, phC, alphaDeg)
%COV_CONEMASK (i,j) ∈ cone ⇔ cos γ ≥ cos α, cos γ = cos θᵢ cos θc + sin θᵢ sin θc cos(φⱼ − φc)   (spherical law of cosines).
    m = cosd(P.Theta(:))*cosd(thC) + sind(P.Theta(:))*sind(thC).*cosd(P.Phi(:).' - phC) >= cosd(alphaDeg) - 1e-12;
end

function T = cov_thresholds(tMin, tMax, step)
    n = floor((tMax - tMin)/step + 1e-9); if n < 0, error('APAT:Thresholds', 'Threshold max must not be below threshold min.'); end
    T = tMin + (0:n).'*step; if T(end) < tMax - 1e-9, T(end+1) = tMax; end                % counting, not accumulation
end

function y = cov_at(T, cov, x)
%COV_AT Coverage read from a curve at threshold(s) x: linear between samples, NaN outside.
    if numel(T) < 2, y = nan(size(x)); y(x == T) = cov; return; end
    y = interp1(T, cov, x, 'linear', NaN);
end

function x = thr_at(T, cov, y)
%THR_AT Threshold at which the (non-increasing) curve reaches coverage y; one T per level (upper end of a plateau).
    [c, i] = unique(cov, 'last');
    if numel(c) < 2, x = NaN; if any(c == y), x = T(i(c == y)); end; return; end
    x = interp1(c, T(i), y, 'linear', NaN);
end

%% ---------------------------------------------------------------------- Utilities
function [x, y, z] = util_sph2cart(thDeg, phDeg)
    x = sind(thDeg).*cosd(phDeg); y = sind(thDeg).*sind(phDeg); z = cosd(thDeg);
end

function step = util_uniformStep(x, name, tol)
%UTIL_UNIFORMSTEP Median step of an ascending axis; errors when any gap deviates (APAT requires uniform grids). NaN for one sample.
    d = diff(x(:)); if isempty(d), step = NaN; return; end
    step = median(d);
    if any(abs(d - step) > tol), error('APAT:NonUniformGrid', '%s axis is not uniform: steps range %.6g°..%.6g°.', name, min(d), max(d)); end
end

function k = util_colKind(name)
%UTIL_COLKIND Column semantics from its name: "ar" | "phase" | "gain" (dB level: loss applies, power interpolation) | "other".
    key = lower(regexprep(char(name), '[^a-zA-Z0-9]', ''));
    if startsWith(key, 'ar') || contains(key, 'axialratio'), k = "ar";
    elseif contains(key, 'phase'), k = "phase";
    elseif contains(key, {'gain', 'directivity', 'eirp', 'total'}) || endsWith(key, {'db', 'dbi'}), k = "gain";
    else, k = "other";
    end
end

function X = util_interpKind(A, kind, lin)
    switch kind
        case "field", pw = lin(abs(A).^2, 'linear'); u = lin(A./max(abs(A), realmin), 'linear'); X = sqrt(max(pw, 0)).*u./max(abs(u), realmin);
        case "gain",  X = 10*log10(max(lin(10.^(A/10), 'linear'), realmin));
        otherwise,    X = lin(A, 'nearest');                                             % AR / phase / other: never invented
    end
end

function [lim, cmap] = util_theme(kind, lim, Const)
%UTIL_THEME Signed AR: fixed ±30 dB blue-white-red map; everything else: the requested range with jet.
    persistent jetMap arMap
    if isempty(jetMap), jetMap = jet(256); arMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
    if kind == "ar", lim = Const.ARLimits; cmap = arMap; else, cmap = jetMap; end
end

function lim = util_presetRange(peak)
%UTIL_PRESETRANGE 50 dB window under the next multiple of 5 above the peak (M7 policy), clamped to [−250, 100].
    if ~isfinite(peak), lim = [-50 0]; return; end
    hi = min(max(ceil(peak/5)*5, -200), 100); lim = [hi - 50, hi];
end

function t = util_ticks(lim, step)
    t = []; if ~isfinite(step) || step <= 0 || diff(lim) <= 0, return; end
    t = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)]); if numel(t) > 60, t = []; end
end

function s = util_fmt(v, prec)
%UTIL_FMT Compact number (≤ 2 decimals, no trailing zeros, never "-0") or fixed PREC decimals; 'n/a' when not finite.
    if ~(isscalar(v) && isnumeric(v) && isfinite(v)), s = 'n/a'; return; end
    if nargin >= 2, s = sprintf('%.*f', prec, v); return; end
    s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); if strcmp(s, '-0'), s = '0'; end
end

function a = util_wrap180(a)
    a = mod(a + 180, 360) - 180;
end

function v = util_iif(cond, a, b)
    if cond, v = a; else, v = b; end
end

function c = util_cutCanonical(cutType, value, elevation)
%UTIL_CUTCANONICAL Displayed fixed angle → canonical (fixed φ in [0,360); fixed θ polar).
    if cutType == "Theta", c = mod(value, 360); elseif elevation, c = 90 - value; else, c = value; end
end

function v = util_cutDisplay(cutType, canon, elevation, signedPhi)
    if cutType == "Theta", v = util_iif(signedPhi, util_wrap180(canon), mod(canon, 360)); else, v = util_iif(elevation, 90 - canon, canon); end
end

function s = util_planeText(pl)
    s = sprintf('%s-cut at %s = %g°', util_iif(pl.CutType == "Theta", 'θ', 'φ'), util_iif(pl.CutType == "Theta", 'φ', 'θ'), pl.Fixed);
end

function T = util_longTable(P, D, names)
%UTIL_LONGTABLE Canonical long table (Theta, Phi, the requested derived columns) — built only when a table or export needs it.
    [PH, TH] = meshgrid(P.Phi, P.Theta); T = table(TH(:), PH(:), 'VariableNames', {'Theta', 'Phi'});
    for nm = names, T.(char(nm)) = reshape(D.Cols.(nm), [], 1); end
end

%% ---------------------------------------------------------------------- I/O: every reader returns Source = {Raw, Blocks{f}, Freqs, Meta}
function S = io_read(path, textFormat)
%IO_READ Dispatch on extension. A block is {Theta, Phi, Eth, Eph} (complex fields) or {Theta, Phi, G.(name)} (gain-only, dB).
    [~, ~, ext] = fileparts(path); ext = lower(ext);
    switch ext
        case '.uan',            S = io_uan(path);
        case '.cut',            S = io_cut(path);
        case '.ffd',            S = io_ffd(path);
        case '.ffe',            S = io_ffe(path);
        case '.ffs',            S = io_ffs(path);
        case {'.xlsx', '.xls'}, S = io_xlsx(path);
        otherwise,              S = io_generic(path, ext, textFormat);
    end
end

function S = io_source(blocks, freqs, raw, meta)
    freqs = double(freqs(:).'); freqs(end+1:numel(blocks)) = NaN;
    S = struct('Raw', raw, 'Blocks', {blocks}, 'Freqs', freqs(1:numel(blocks)), 'Meta', meta);
end

function meta = io_meta(format, unit, varargin)
%IO_META Source disclosure. The unit class is a static property of the format; reader decisions go to Notes (shown in Metadata).
    meta = struct('Format', string(format), 'Unit', string(unit), 'UnitLabel', "dBi", 'ThetaConvention', "polar", ...
                  'IsGainOnly', false, 'Generic', false, 'Notes', strings(1, 0));
    if meta.Unit ~= "dBi", meta.UnitLabel = "dB (relative field)"; end
    for k = 1:2:numel(varargin), meta.(varargin{k}) = varargin{k+1}; end
end

function L = io_lines(path)
    L = strtrim(string(splitlines(fileread(path))));
end

function [M, isNum] = io_numeric(L)
%IO_NUMERIC Numeric rows of the text lines L: the modal column count wins, every other line is ignored.
    R = regexprep(regexprep(L(:), '[,;\t]+', ' '), '\s+', ' ');
    isNum = ~cellfun('isempty', regexp(R, '^[-+]?[\d.]', 'once')) & ~cellfun('isempty', regexp(R, '^[-+.\deE ]+$', 'once'));
    M = zeros(0, 0); if ~any(isNum), return; end
    cnt = count(R(isNum), ' ') + 1; nCol = mode(cnt); idx = find(isNum); isNum(idx(cnt ~= nCol)) = false;
    M = reshape(sscanf(char(join(R(isNum), newline)), '%f'), nCol, []).';
end

function v = io_headerValue(L, key)
%IO_HEADERVALUE First token following KEY at the start of any line ("" when absent), case-insensitive.
    t = regexp(L(:), ['^' key '\s+(\S+)'], 'tokens', 'once', 'ignorecase'); hit = find(~cellfun('isempty', t), 1);
    if isempty(hit), v = ""; else, v = string(t{hit}{1}); end
end

function [Eth, Eph] = io_fields(M, kind, basis, cols, phaseUnit)
%IO_FIELDS Four value columns → complex (Eθ, Eφ). kind: "reim" | "magphase" (dB, phase in PHASEUNIT); basis: "linear" | "circular".
    c = M(:, cols);
    if kind == "reim"
        A = complex(c(:, 1), c(:, 2)); B = complex(c(:, 3), c(:, 4));
    else
        p = c(:, [2 4]); if phaseUnit == "rad", p = rad2deg(p); end
        A = 10.^(c(:, 1)/20).*exp(1i*deg2rad(p(:, 1))); B = 10.^(c(:, 3)/20).*exp(1i*deg2rad(p(:, 2)));
    end
    if basis == "circular", [Eth, Eph] = pol_fromCircular(A, B); else, Eth = A; Eph = B; end
end

function S = io_uan(path)
%IO_UAN MVG/Satimo UAN: key/value header, rows "theta phi mag1 phase1 mag2 phase2" (magnitude in dB = dBi gain).
    L = io_lines(path);
    mag = lower(io_headerValue(L, 'magnitude')); if mag == "", mag = "db"; end
    if ~startsWith(mag, "db"), error('APAT:UnsupportedUAN', 'UAN magnitude "%s" is not supported (dB expected).', mag); end
    pol = lower(io_headerValue(L, 'polarization')); basis = util_iif(contains(pol, ["circ", "rhcp", "rcp"]), "circular", "linear");
    phaseUnit = util_iif(startsWith(lower(io_headerValue(L, 'phase')), "rad"), "rad", "deg");
    freq = str2double(io_headerValue(L, 'frequency'));
    if isfinite(freq) && freq < 1e4, freq = freq*1e9; elseif isfinite(freq) && freq < 1e7, freq = freq*1e6; end
    M = io_numeric(L);
    if size(M, 2) < 6, error('APAT:UnsupportedUAN', 'UAN data rows need six columns (theta phi mag phase mag phase).'); end
    [Eth, Eph] = io_fields(M, "magphase", basis, 3:6, phaseUnit);
    raw = array2table(M(:, 1:6), 'VariableNames', {'Theta', 'Phi', 'Mag1_dB', 'Phase1', 'Mag2_dB', 'Phase2'});
    meta = io_meta("UAN (MVG/Satimo)", "dBi");
    meta.Notes(end+1) = "UAN magnitudes read as dBi gain; polarization header: " + util_iif(pol == "", "theta_phi (default)", pol);
    S = io_source({struct('Theta', M(:, 1), 'Phi', M(:, 2), 'Eth', Eth, 'Eph', Eph)}, freq, raw, meta);
end

function S = io_cut(path)
%IO_CUT TICRA GRASP cut: per cut a text line, "V_INI V_INC V_NUM C ICOMP ICUT NCOMP", then V_NUM rows of Re/Im pairs.
    L = io_lines(path);
    hdr = find(~cellfun('isempty', regexp(L(:), '^[-+\d.eE]+(\s+[-+\d.eE]+){6}$', 'once')));
    if isempty(hdr), error('APAT:UnsupportedCUT', 'No GRASP cut header (V_INI V_INC V_NUM C ICOMP ICUT NCOMP) found.'); end
    th = []; ph = []; A = []; B = []; icomp = 1;
    for k = hdr(:).'
        h = sscanf(char(L(k)), '%f'); n = round(h(3)); icomp = h(5);
        if h(6) ~= 1, error('APAT:UnsupportedCUT', 'Only polar cuts (ICUT = 1) are supported.'); end
        if ~any(icomp == [1 2]), error('APAT:UnsupportedICOMP', 'GRASP ICOMP = %d is not supported (1 = θ/φ, 2 = RHCP/LHCP).', icomp); end
        M = reshape(sscanf(char(join(L(k+1:k+n), newline)), '%f'), [], n).';
        th = [th; h(1) + (0:n-1).'*h(2)]; ph = [ph; repmat(h(4), n, 1)]; %#ok<AGROW>
        A = [A; complex(M(:, 1), M(:, 2))]; B = [B; complex(M(:, 3), M(:, 4))]; %#ok<AGROW>
    end
    if icomp == 2, [Eth, Eph] = pol_fromCircular(A, B); else, Eth = A; Eph = B; end
    raw = table(th, ph, real(A), imag(A), real(B), imag(B), 'VariableNames', {'Theta', 'Phi', 'Re1', 'Im1', 'Re2', 'Im2'});
    meta = io_meta("TICRA GRASP cut", "dB");
    meta.Notes(end+1) = util_iif(icomp == 2, "components read as RHCP/LHCP (ICOMP = 2)", "components read as Eθ/Eφ (ICOMP = 1)");
    S = io_source({struct('Theta', th, 'Phi', ph, 'Eth', Eth, 'Eph', Eph)}, NaN, raw, meta);
end

function S = io_ffd(path)
%IO_FFD HFSS far-field data: "θs θe nθ", "φs φe nφ", "Frequencies N", per block "Frequency f" + nθ·nφ rows of Re/Im Eθ, Re/Im Eφ.
    L = io_lines(path); a1 = sscanf(char(L(1)), '%f'); a2 = sscanf(char(L(2)), '%f');
    if numel(a1) < 3 || numel(a2) < 3, error('APAT:UnsupportedFFD', 'FFD must start with "θ_start θ_stop nθ" and "φ_start φ_stop nφ".'); end
    th = linspace(a1(1), a1(2), a1(3)).'; ph = linspace(a2(1), a2(2), a2(3)).'; nT = numel(th); nP = numel(ph); N = nT*nP;
    t = regexp(L(:), '^Frequency\s+([-+\d.eE]+)', 'tokens', 'once', 'ignorecase'); fq = cellfun(@(x) str2double(x{1}), t(~cellfun('isempty', t)));
    M = io_numeric(L(3:end));
    if size(M, 2) < 4 || mod(size(M, 1), N) ~= 0, error('APAT:UnsupportedFFD', 'FFD rows (%d) do not match nθ×nφ = %d.', size(M, 1), N); end
    p = sum(M(1:nP, 1:4).^2, 2); phiInner = nP > 1 && nT > 1 && (max(p) - min(p)) <= 1e-6*max(max(p), realmin);   % θ = 0 pole test
    if phiInner, TH = repelem(th, nP); PH = repmat(ph, nT, 1); else, TH = repmat(th, nP, 1); PH = repelem(ph, nT); end
    nB = size(M, 1)/N; blocks = cell(1, nB);
    for b = 1:nB, r = (b-1)*N + (1:N); blocks{b} = struct('Theta', TH, 'Phi', PH, 'Eth', complex(M(r, 1), M(r, 2)), 'Eph', complex(M(r, 3), M(r, 4))); end
    raw = array2table([TH, PH, M(1:N, 1:4)], 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
    meta = io_meta("HFSS far-field data (.ffd)", "dB");
    meta.Notes(end+1) = "row order detected as " + util_iif(phiInner, "θ-outer / φ-inner", "φ-outer / θ-inner") + " (pole test); raw field levels";
    S = io_source(blocks, fq(max(1, numel(fq) - nB + 1):end), raw, meta);
end

function S = io_ffe(path)
%IO_FFE FEKO far field: one block per "#Frequency:"; rows θ φ Re(Eθ) Im(Eθ) Re(Eφ) Im(Eφ) [FEKO gain columns ignored].
    L = io_lines(path); fIdx = find(startsWith(L, "#Frequency", 'IgnoreCase', true));
    if isempty(fIdx), fIdx = 1; freqs = NaN; else, freqs = arrayfun(@(k) str2double(regexprep(L(k), '^[^:]*:', '')), fIdx); end
    bounds = [fIdx(:); numel(L) + 1]; blocks = {}; keep = []; raw = table();
    for b = 1:numel(fIdx)
        M = io_numeric(L(bounds(b):bounds(b+1)-1)); if size(M, 2) < 6, continue; end
        blocks{end+1} = struct('Theta', M(:, 1), 'Phi', M(:, 2), 'Eth', complex(M(:, 3), M(:, 4)), 'Eph', complex(M(:, 5), M(:, 6))); keep(end+1) = b; %#ok<AGROW>
        if isempty(raw), raw = array2table(M(:, 1:6), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}); end
    end
    if isempty(blocks), error('APAT:UnsupportedFFE', 'No six-column field block found in the FEKO file.'); end
    meta = io_meta("FEKO far field (.ffe)", "dB"); meta.Notes(end+1) = "Re/Im E columns used; FEKO gain columns ignored (raw field levels)";
    S = io_source(blocks, freqs(keep), raw, meta);
end

function S = io_ffs(path)
%IO_FFS CST far-field source: frequency is the 4th value after "// Radiated/Accepted/Stimulated Power"; rows φ θ Re/Im Eθ Re/Im Eφ.
    L = io_lines(path); pIdx = find(contains(L, "Radiated/Accepted/Stimulated Power", 'IgnoreCase', true));
    freqs = arrayfun(@(k) util_nth(sscanf(char(L(min(k+1, end))), '%f'), 4), pIdx);
    M = io_numeric(L);
    if size(M, 2) < 6, error('APAT:UnsupportedFFS', 'FFS data rows need six columns (phi theta Re/Im Eθ Re/Im Eφ).'); end
    nB = max(numel(freqs), 1); N = size(M, 1)/nB; if mod(N, 1) ~= 0, nB = 1; N = size(M, 1); end
    blocks = cell(1, nB);
    for b = 1:nB, r = (b-1)*N + (1:N); blocks{b} = struct('Theta', M(r, 2), 'Phi', M(r, 1), 'Eth', complex(M(r, 3), M(r, 4)), 'Eph', complex(M(r, 5), M(r, 6))); end
    raw = array2table(M(1:N, 1:6), 'VariableNames', {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
    meta = io_meta("CST far-field source (.ffs)", "dB"); meta.Notes(end+1) = "columns read as φ, θ, Re/Im Eθ, Re/Im Eφ (raw field levels)";
    S = io_source(blocks, freqs, raw, meta);
end

function S = io_xlsx(path)
%IO_XLSX Excel matrix templates: component sheets "<comp>_Gain_dBi" + "<comp>_Phase_degrees", each a C3-origin θ×φ matrix.
    sheets = string(sheetnames(path));
    circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"];
    lin  = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
    hasL = all(ismember(lower(lin), lower(sheets))); hasC = all(ismember(lower(circ), lower(sheets)));
    if ~(hasL || hasC), error('APAT:UnsupportedExcel', 'Workbook needs the Etheta/Ephi and/or RHCP/LHCP "Gain_dBi" + "Phase_degrees" sheets.'); end
    need = lin; basis = "linear"; fmt = "Excel matrix (Eθ/Eφ)";
    if ~hasL, need = circ; basis = "circular"; fmt = "Excel matrix (RHCP/LHCP)"; elseif hasC, fmt = "Excel matrix (Eθ/Eφ + RHCP/LHCP)"; end
    mats = cell(1, 4);
    for k = 1:4
        [th, ph, mats{k}] = io_xlsxSheet(path, sheets(find(strcmpi(sheets, need(k)), 1)));
        if k == 1, th0 = th; ph0 = ph;
        elseif ~isequal(size(mats{k}), size(mats{1})) || max(abs(th - th0)) > 1e-9 || max(abs(ph - ph0)) > 1e-9
            error('APAT:ExcelGrid', 'All component sheets must share the same θ/φ grid.');
        end
    end
    [PH, TH] = meshgrid(ph0, th0); M = [TH(:), PH(:), mats{1}(:), mats{2}(:), mats{3}(:), mats{4}(:)];
    [Eth, Eph] = io_fields(M, "magphase", basis, 3:6, "deg");
    raw = array2table(M, 'VariableNames', [{'Theta', 'Phi'}, cellstr(need)]);
    S = io_source({struct('Theta', M(:, 1), 'Phi', M(:, 2), 'Eth', Eth, 'Eph', Eph)}, io_xlsxFrequency(path, sheets(1)), raw, io_meta(fmt, "dBi"));
end

function [th, ph, data] = io_xlsxSheet(path, sheet)
%IO_XLSXSHEET One C3-origin matrix: column axis in row 2 (C2→), row axis in column 2 (B3↓). θ is the axis staying ≤ 180°.
    C = readcell(path, 'Sheet', char(sheet)); isnum = @(x) isnumeric(x) && isscalar(x);
    if size(C, 1) < 3 || size(C, 2) < 3, error('APAT:ExcelSheet', 'Sheet "%s" holds no C3-origin matrix.', sheet); end
    kc = find(cellfun(isnum, C(2, 3:end))); kr = find(cellfun(isnum, C(3:end, 2)));
    colAxis = cell2mat(C(2, 2 + kc)).'; rowAxis = cell2mat(C(2 + kr, 2));
    D = C(2 + kr, 2 + kc); D(~cellfun(isnum, D)) = {NaN}; data = cell2mat(D); th = rowAxis; ph = colAxis;
    if max(rowAxis) > 180 + 1e-9 && max(colAxis) <= 180 + 1e-9, th = colAxis; ph = rowAxis; data = data.'; end
end

function f = io_xlsxFrequency(path, sheet)
%IO_XLSXFREQUENCY The one summary-sheet fact APAT uses: the first numeric cell right of a "freq … MHz" label (NaN when absent).
    f = NaN; C = readcell(path, 'Sheet', char(sheet), 'Range', 'A1:H70');
    for r = 1:size(C, 1)
        for c = 1:size(C, 2)
            x = C{r, c};
            if (ischar(x) || isstring(x)) && contains(lower(string(x)), "freq") && contains(lower(string(x)), "mhz")
                for c2 = c+1:size(C, 2), y = C{r, c2}; if isnumeric(y) && isscalar(y) && isfinite(y), f = y*1e6; return; end; end
            end
        end
    end
end

function S = io_generic(path, ext, fmt)
%IO_GENERIC Delimited text (csv/txt/dat/fz/out): header names decide axis roles and value layout, FMT overrides the layout
%   ("auto" | "gain" | "reim" | "magphase"); every decision is written to Notes. A 2-column/coverage-labelled table is a results file.
    L = io_lines(path); [M, isNum] = io_numeric(L); generic = any(strcmp(ext, {'.csv', '.txt', '.dat'}));
    if isempty(M) || size(M, 2) < 2, error('APAT:UnsupportedFile', 'No numeric table found in "%s".', path); end
    first = find(isNum, 1); hdr = strings(1, 0);
    if first > 1, tok = regexp(char(L(first-1)), '[^,;\t ]+', 'match'); if numel(tok) == size(M, 2), hdr = string(tok); end; end
    names = lower(hdr); nCol = size(M, 2); notes = strings(1, 0);
    if fmt == "auto" && (any(contains(names, ["cov", "thresh", "ccdf"])) || (nCol == 2 && isempty(hdr)))
        error('APAT:CoverageFile', 'This file is a coverage-results table: it is loaded on the Coverage tab.');
    end
    iTh = find(startsWith(names, ["theta", "th", "el"]) & ~startsWith(names, "thr"), 1);
    iPh = find(startsWith(names, ["phi", "ph", "az"]) & ~startsWith(names, "pha"), 1); thetaConv = "polar";
    if isempty(iTh) || isempty(iPh)
        iTh = 1; iPh = 2; span = max(M(:, 1:2)) - min(M(:, 1:2));
        if span(1) > 180 + 1e-9 && span(2) <= 180 + 1e-9, iTh = 2; iPh = 1; notes(end+1) = "axis order φ,θ decided by column spans";
        else, notes(end+1) = "axis order θ,φ assumed (columns 1–2)"; end
    elseif startsWith(names(iTh), "el"), thetaConv = "elevation"; notes(end+1) = "θ column is elevation (header)";
    end
    if thetaConv == "polar" && min(M(:, iTh)) < -1e-9 && max(M(:, iTh)) <= 90 + 1e-9, thetaConv = "elevation"; notes(end+1) = "θ range [−90°, 90°] read as elevation"; end
    M = M(isfinite(M(:, iTh)) & isfinite(M(:, iPh)), :);                                % drop rows only on θ/φ NaN
    vals = setdiff(1:nCol, [iTh iPh], 'stable'); vn = strings(1, 0); if ~isempty(hdr), vn = names(vals); end
    kind = fmt;
    if fmt == "auto"
        kind = "gain";
        if numel(vals) == 4
            if isempty(hdr) || any(startsWith(vn, ["re", "im"])) || any(contains(vn, ["real", "imag"])), kind = "reim"; end
            if any(contains(vn, ["mag", "amp"])) && any(contains(vn, "pha")), kind = "magphase"; end
            if isempty(hdr) && all(abs(M(:, vals([2 4]))) <= 360, 'all') && any(M(:, vals([1 3])) < -20, 'all'), kind = "magphase"; end
        end
        notes(end+1) = "value layout '" + kind + "' decided from " + util_iif(isempty(hdr), "column count and value ranges", "header names");
    else
        notes(end+1) = "value layout '" + kind + "' selected by the user";
    end
    if kind ~= "gain"
        if numel(vals) < 4, error('APAT:UnsupportedFile', 'A field table needs four value columns (two components × Re/Im or mag/phase).'); end
        vals = vals(1:4); basis = util_iif(any(contains(vn, ["rhcp", "lhcp", "rcp", "lcp"])) || strcmp(ext, '.out'), "circular", "linear");
        unit = util_iif(kind == "magphase" && any(contains(vn, "dbi")), "dBi", "dB");
        [Eth, Eph] = io_fields(M, kind, basis, vals, "deg");
        block = struct('Theta', M(:, iTh), 'Phi', M(:, iPh), 'Eth', Eth, 'Eph', Eph);
        meta = io_meta("Field table (" + ext + ")", unit, 'ThetaConvention', thetaConv, 'Generic', generic);
        notes(end+1) = "components read as " + util_iif(basis == "circular", "RHCP/LHCP", "Eθ/Eφ");
    else
        G = struct();
        for k = 1:numel(vals)
            nm = "Col" + vals(k) + "_dB"; if ~isempty(hdr), nm = hdr(vals(k)); elseif k == 1, nm = "Gain_dB"; end
            G.(matlab.lang.makeValidName(char(nm))) = M(:, vals(k));
        end
        block = struct('Theta', M(:, iTh), 'Phi', M(:, iPh), 'G', G);
        meta = io_meta("Gain table (" + ext + ")", "dBi", 'ThetaConvention', thetaConv, 'IsGainOnly', true, 'Generic', generic);
        notes(end+1) = "gain-only columns are taken as dBi";
    end
    rawNames = cellstr(compose('Col%d', 1:nCol)); if ~isempty(hdr), rawNames = cellstr(hdr); end
    raw = array2table(M, 'VariableNames', matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(rawNames)));
    meta.Notes = [meta.Notes, notes];
    S = io_source({block}, NaN, raw, meta);
end

function [T, curves, names] = io_coverageCSV(path)
%IO_COVERAGECSV Results table: first numeric column = thresholds, remaining numeric columns = coverage curves (%).
    tbl = readtable(path, 'VariableNamingRule', 'preserve'); tbl = tbl(:, varfun(@isnumeric, tbl, 'OutputFormat', 'uniform'));
    if width(tbl) < 2, error('APAT:CoverageFile', 'A coverage results file needs a threshold column and at least one curve.'); end
    [T, o] = sort(tbl{:, 1}); curves = tbl{o, 2:end}; names = tbl.Properties.VariableNames(2:end);
end

function io_writeUAN(file, P, D)
%IO_WRITEUAN UAN export (dB magnitude / degree phase, θ-φ polarisation) of the derived Eθ/Eφ columns at the current loss.
    fid = fopen(file, 'w'); c = onCleanup(@() fclose(fid)); %#ok<NASGU>
    [PH, TH] = meshgrid(P.Phi, P.Theta);
    fprintf(fid, ['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                  'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.4f\nphase degrees\ndirection degrees\npolarization theta_phi\n'], ...
            P.Phi(1), P.Phi(end), P.dPhi, P.Theta(1), P.Theta(end), P.dTheta, D.Peak.value);
    if isfinite(P.Freq), fprintf(fid, 'frequency %.6g\n', P.Freq); end
    fprintf(fid, 'end_<parameters>\nbegin_<data>\n');
    fprintf(fid, '%g %g %.4f %.3f %.4f %.3f\n', [TH(:), PH(:), D.Cols.E_TH_dB(:), D.Cols.E_TH_Phase(:), D.Cols.E_PH_dB(:), D.Cols.E_PH_Phase(:)].');
    fprintf(fid, 'end_<data>\n');
end

function v = util_nth(x, k)
    if numel(x) >= k, v = x(k); else, v = NaN; end
end