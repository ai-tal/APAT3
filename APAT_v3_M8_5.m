classdef APAT_v3_M8_5 < matlab.apps.AppBase %1671-lines %>> Error: Unrecognized method, property, or field 'DataTipTemplate' for class 'matlab.graphics.primitive.Line'. (APAT_v3_M8_4.renderCut line 755)
% APAT v3 M8 — Antenna Pattern Analyzer Tool (single-file App Designer-style app, base MATLAB R2023b, no toolboxes).
%
% ARCHITECTURE (one concept, one place):
%   FILE ─► io_read ─► Source ─► pat_build ─► Pattern (grid-native nθ×nφ, polar θ, φ∈[0,360), uniform steps)
%        ─► [pat_resample] ─► geo_build ─► Geometry (separable ΔΩ, Σ = 4π exactly on a full sphere)
%        ─► pat_derive(Pattern, Geometry, Params) ─► Derived (every column + peak + polarisation + boresight + metrics)
%   app.Pats(k) = {Name, Path, Source, Pattern, Geometry, Derived, Params, NativeStep}  ◄── one entry per loaded file,
%   shared by the Main tab (app.Main) and every Coverage tree node (NodeData.k). Nothing is copied or synchronised.
%   View/Map: display conventions (elevation θ, signed φ) are a column permutation + axis relabelling (geo_displayMap);
%   they never touch data. Widgets are read only in readConfig/readCoverageConfig and written only in apply*/render*.
%   Every callback is app.on(scope) → update(scope) with a ladder: source ⊃ freq ⊃ step ⊃ params ⊃ pattern ⊃ {span,
%   component, cut, range, annot, camera}. Graphics are retained: renderers compare a key and touch only what changed.
%
% CONVENTIONS (apat_const): peak isolation excess 6 dB, signed AR floor −100 dB at linear samples, IEEE circular basis
%   under e^{+jωt} (pol_circular), E/H planes by principal axis, gain-kind columns take loss, coverage = 100·Ω_R(G>T)/Ω_R.

    properties (GetAccess = public, SetAccess = private)
        isClosing logical = false   % lifecycle flag
        Perf struct = struct()      % last timed operation {AppVersion, Operation, Stages, TotalSeconds}
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
        Pats struct = struct([])    % pattern registry: one entry per loaded file (see newEntry)
        Main double = 0             % index into Pats shown on the Main tab (0 = nothing loaded)
        View struct = struct()      % last readConfig() snapshot of the Main-tab widgets
        Map struct = struct()       % geo_displayMap of the Main pattern for the active display convention
        Cut struct = struct()       % last geo_cut result (indices + angles) for the Main pattern
        CutData struct = struct()   % last rendered cut traces {angle, Y, names, theta, phi, title}
        Range struct                % display ranges per group {full, cut, cov, covX} + Auto flags
        RangeCtl struct             % widget descriptors per range group (built in startupFcn)
        Gfx struct                  % retained graphics: Full(k) views, Cut items, Menu, keys
        State struct = struct('BasisAuto', true, 'OutMask', logical([]), 'CovRunID', 0, 'RawKey', '', 'TableKey', '', 'Defaults', struct())
        Status struct = struct('main', 'Ready 🚀', 'cov', 'Ready 🚀', 'Warn', '')
        StatusTimer                 % one reusable single-shot timer for transient status messages
        Dialog = []                 % active cancellable uiprogressdlg
        Busy logical = false
        PerfRun = []
    end

    methods (Access = private, Static)
        function e = newEntry(name, fp, S, P, prm)
            %NEWENTRY One registry entry; the single constructor keeps Pats a homogeneous struct array.
            e = struct('Name', name, 'Path', fp, 'Source', S, 'Pattern', P, 'Geometry', geo_build(P), ...
                'Derived', [], 'Params', prm, 'NativeStep', max(P.dTheta, P.dPhi));
            e.Derived = pat_derive(P, e.Geometry, prm);
        end
    end

    %% ================================================================== C. ORCHESTRATION
    methods (Access = private)

        function [V, prm] = readConfig(app)
            %READCONFIG The only reader of Main-tab widget values. Returns the display View and the physical Params.
            V.Component = string(app.Single_DropDown_Component.Value);
            V.SignedPhi = strcmp(app.Single_Switch_AngularSpan.Value, '-180° to 180°');
            V.Elevation = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°');
            V.CutType = string(app.Single_DropDown_cutType.Value);           % "Phi": fixed θ swept over φ; "Theta": fixed φ
            V.CutValue = app.toCanonical(V, V.CutType, app.Single_DropDown_cutValue.Value);
            V.Basis = string(app.CutFieldBasisDropDown.Value);
            V.Traces = logical([app.CheckBox_Et.Value, app.CheckBox_Er.Value, app.CheckBox_El.Value]);
            V.HPBW = app.Button_HPBW.Value; V.HPBWBounds = app.Single_CheckBox_HPBWBounds.Value;
            V.POB = app.Single_CheckBox_POB.Value; V.Overlay = app.Singel_CheckBox_overlayCut.Value;
            V.Camera = string(app.Single_DropDown_3DView.Value); V.Cstep = app.Single_Plot_Cstep.Value;
            V.OneDegree = strcmp(app.Single_DropDown_step.Value, 'STEP: 1°') && numel(app.Single_DropDown_step.Items) > 1;
            V.Block = find(strcmp(app.Single_DropDown_FFD.Items, app.Single_DropDown_FFD.Value), 1); if isempty(V.Block), V.Block = 1; end
            prm = struct('L', app.Single_Spinner_Loss.Value, 'RxMode', string(app.Single_DropDown_RxPol.Value), ...
                'RxAR_dB', app.Single_Spinner_Rw.Value, 'Pt_dBW', app.Single_Spinner_Pt.Value, 'R_m', app.Single_Spinner_R.Value);
            switch app.Single_DropDown_Pt.Value, case 'dBm', prm.Pt_dBW = prm.Pt_dBW - 30; case 'Watts', prm.Pt_dBW = 10*log10(max(prm.Pt_dBW, eps)); end
            prm.R_m = max(prm.R_m, apat_const().DistanceFloorM); if strcmp(app.Single_DropDown_R.Value, 'km'), prm.R_m = 1000*prm.R_m; end
        end

        function v = toCanonical(~, V, type, d)          % display cut value → physical (polar θ or φ∈[0,360))
            if type == "Phi", v = d; if V.Elevation, v = 90 - d; end, else, v = mod(d, 360); end
        end
        function d = toDisplay(~, V, type, v)            % physical cut value → display convention
            if type == "Phi", d = v; if V.Elevation, d = 90 - v; end
            else, d = mod(v, 360); if V.SignedPhi && d >= 180, d = d - 360; end, end
        end

        function on(app, scope, title)
            %ON Guard for every user action: re-entrancy, try/catch, cancellation, timing, one drawnow.
            if app.Busy || app.isClosing, return; end
            if nargin < 3, title = 'APAT'; end
            app.Busy = true; c = onCleanup(@() app.setBusy(false)); %#ok<NASGU>
            isFn = isa(scope, 'function_handle'); if isFn, name = func2str(scope); else, name = char(scope); end
            app.perf("begin " + string(name));
            try
                if isFn, scope(); app.applyVisibility(); else, app.update(scope); end
                drawnow limitrate
            catch err
                if strcmp(err.identifier, 'APAT:Cancelled'), app.setStatus(app.Single_StatusBar, 'Operation cancelled.', true);
                else, app.showError(err, title); end
            end
            app.perf("end");
        end
        function setBusy(app, tf), if ~app.isClosing, app.Busy = tf; end, end

        function update(app, scope)
            %UPDATE Dispatcher. Recomputes only the invalidation radius of SCOPE, commits Pats(k) at the end of a stage
            %   (build-then-commit), renders the visible full-pattern tab, and ends with one applyVisibility.
            s = string(scope); k = app.Main;
            if k == 0 || any(s == ["tab", "annot", "camera", "covUI"]), app.renderLight(s); return; end
            [V, prm] = app.readConfig(); e = app.Pats(k);
            switch s
                case {"source", "freq", "step"}                       % "source" arrives already built and derived by loadMain
                    if s ~= "source"
                        P = pat_build(e.Source, V.Block); if V.OneDegree, P = pat_resample(P, 1); end
                        e.Pattern = P; e.Geometry = geo_build(P); app.perf("Build pattern"); app.checkCancelled();
                        e.Derived = pat_derive(e.Pattern, e.Geometry, prm); e.Params = prm; app.Pats(k) = e; app.perf("Derive");
                    end
                    app.applyChoices(s ~= "source"); [V, ~] = app.readConfig();
                    if app.Range.Auto.full, lim = util_presetRange(e.Derived.Peak.value); app.applyRange("full", lim, -1); app.applyRange("cut", lim, -1); end
                    s = "pattern";
                case "params"
                    if ~isequal(e.Params, prm), e.Derived = pat_derive(e.Pattern, e.Geometry, prm); e.Params = prm; app.Pats(k) = e; app.perf("Derive"); end
                    s = "pattern";
            end
            app.View = V; app.Map = geo_displayMap(e.Pattern, e.Geometry, V);
            if s == "plane"                                             % E/H switch → principal-plane cut controls
                pl = e.Derived.Planes.(app.Single_Switch_EHplane.Value(1));
                app.Single_DropDown_cutType.Value = char(pl.type); app.applyCutDomain(pl.value); s = "cut";
            elseif any(s == ["pattern", "span", "cutType"]), app.applyCutDomain(); if s == "cutType", s = "cut"; end
            end
            app.View = app.readConfig();
            if any(s == ["pattern", "span", "cut", "component"])
                app.Cut = geo_cut(e.Pattern, e.Geometry, app.View.CutType, app.View.CutValue); app.renderCut(); app.perf("Cut");
            end
            app.renderVisible(); app.perf("Render");
            if any(s == ["pattern", "span", "component", "tables"]), app.renderTables(); app.renderMetadata(); app.perf("Tables"); end
            if s == "pattern", app.setStatus(app.Single_StatusBar, app.mainStatus(e), false); end
            app.applyVisibility();
        end

        function renderLight(app, s)
            %RENDERLIGHT Scopes that touch no data: tab change, annotation toggles, camera, coverage UI state.
            if app.Main > 0
                app.View = app.readConfig();
                if s == "tab", app.renderVisible(); end
                if s == "annot", app.renderCut(); for j = 1:5, app.setAnnotationVisible(j); end, end
                if s == "camera", for j = 3:5, app.applyCamera(j); end, end
            end
            app.applyVisibility();
        end

        function loadMain(app, fp, fmt)
            %LOADMAIN Read a file into the registry and show it on the Main tab (coverage-result files are routed away).
            app.Dialog = uiprogressdlg(app.UIFigure, 'Title', 'Loading Data', 'Message', 'Reading file...', 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            c = onCleanup(@() app.closeDialog()); %#ok<NASGU>
            S = io_read(fp, fmt); app.perf("Read file"); app.checkCancelled();
            if S.IsCoverage
                app.TabGroup.SelectedTab = app.Tab2_Coverage; app.Cov_EditField_filePath.Value = fp; app.covLoadResults(fp, S.Raw); return
            end
            [~, name, ext] = fileparts(fp); [~, prm] = app.readConfig();
            e = app.newEntry([name ext], fp, S, pat_build(S, 1), prm); app.perf("Build pattern"); app.checkCancelled();
            slot = app.Main; if slot == 0 || app.covRefs(slot), slot = numel(app.Pats) + 1; end   % never yank a coverage node's pattern
            if isempty(app.Pats), app.Pats = e; else, app.Pats(slot) = e; end
            app.Main = slot; app.State.BasisAuto = true; app.State.RawKey = '';
            app.Single_EditField_Path.Value = fp; app.Single_DropDown_FFD.Items = {'Frequencies'}; app.Single_DropDown_FFD.Value = 'Frequencies';
            app.State.OutMask = logical([]);
            app.update("source");
        end

        function closeDialog(app), d = app.Dialog; app.Dialog = []; if ~isempty(d) && isvalid(d), close(d); end, end

        function tf = covRefs(app, k)                       % is Pats(k) referenced by a coverage tree node?
            tf = false;
            for n = app.Cov_TreeNode_Results.Children(:).'
                d = n.NodeData; if isstruct(d) && d.kind == "pattern" && d.k == k, tf = true; return; end
            end
        end

        function applyChoices(app, keepStep)
            %APPLYCHOICES The only writer of data-derived Items/ItemsData on the Main tab (after source/freq/step).
            e = app.Pats(app.Main); P = e.Pattern; S = e.Source; V = app.readConfig();
            [names, labels] = app.componentItems(e); dd = app.Single_DropDown_Component; prev = string(dd.Value);
            dd.Items = cellstr(labels); dd.ItemsData = cellstr(names);
            if any(names == prev), dd.Value = char(prev); elseif any(names == "E_Total_dB"), dd.Value = 'E_Total_dB'; else, dd.Value = dd.ItemsData{1}; end
            items = {sprintf('STEP: %g°', e.NativeStep)}; one = keepStep && V.OneDegree;
            if abs(e.NativeStep - 1) > 1e-9, items{end+1} = 'STEP: 1°'; end
            app.Single_DropDown_step.Items = items; app.Single_DropDown_step.Value = items{1 + (one && numel(items) > 1)};
            if numel(S.Blocks) > 1 && numel(app.Single_DropDown_FFD.Items) ~= numel(S.Blocks)
                it = compose('Pattern %d: %.4g GHz', (1:numel(S.Blocks)).', S.Freqs(:)/1e9); it(isnan(S.Freqs(:))) = compose('Pattern %d', find(isnan(S.Freqs(:))));
                app.Single_DropDown_FFD.Items = it; app.Single_DropDown_FFD.Value = it{1};
            end
            if ~P.IsGainOnly && app.State.BasisAuto
                if startsWith(e.Derived.Pol.label, "Linear"), app.CutFieldBasisDropDown.Value = 'Linear'; else, app.CutFieldBasisDropDown.Value = 'Circular'; end
            end
            cols = app.colNames(e); K = apat_const();
            if numel(app.State.OutMask) ~= numel(cols)
                app.State.OutMask = true(size(cols));
                if ~P.IsGainOnly, [tf, loc] = ismember(cols, string({K.Cols.name})); app.State.OutMask(tf) = ~[K.Cols(loc(tf)).hidden]; end
            end
            dd = app.Single_DropDown_output; dd.Items = [{'--- column filter ---'}, cellstr(cols)]; dd.ItemsData = 0:numel(cols); dd.Value = 0; app.styleFilter();
        end

        function applyCutDomain(app, value)
            %APPLYCUTDOMAIN Cut-value spinner limits/step follow the display convention (Map); optional VALUE is physical.
            V = app.readConfig(); M = app.Map; sp = app.Single_DropDown_cutValue;
            if V.CutType == "Phi", vals = sort(M.ThetaAxis); else, vals = sort(M.PhiAxis(1:numel(M.Perm))); end
            if nargin < 2, value = V.CutValue; end
            d = app.toDisplay(V, V.CutType, value); [~, i] = min(abs(vals - d));
            st = min(diff(vals)); if isempty(st) || ~(st > 0), st = 1; end
            sp.Limits = [min(vals), max(vals) + (numel(vals) == 1)]; sp.Step = st; sp.Value = vals(i);
        end

        function applyVisibility(app)
            %APPLYVISIBILITY The only writer of Visible/Enable, computed from the registry, the view and the coverage tree.
            loaded = app.Main > 0; hasE = loaded && ~app.Pats(app.Main).Pattern.IsGainOnly;
            set([app.Single_Panel_Rect, app.Single_Panel_fullPattern, app.Single_Panel_plotControl, app.Single_Export_Output, ...
                app.Single_Button_Coverage, app.Single_tabData, app.Single_DropDown_output, app.Single_Table_DataOut, app.Single_Table_DataIn], 'Visible', loaded);
            set([app.Single_Export_UAN, app.Single_gridEcut, app.CheckBox_Et, app.CheckBox_Er, app.CheckBox_El], 'Visible', hasE);
            set([app.CheckBox_Er, app.CheckBox_El, app.CutFieldBasisDropDown], 'Enable', hasE);
            set([app.LossindBLabel, app.Single_Spinner_Loss], 'Visible', loaded);
            set([app.RxPolLabel, app.Single_DropDown_RxPol, app.IncidentWaveARRwPLFLabel, app.Single_Spinner_Rw, app.TransmitPowerLabel, ...
                app.Single_Spinner_Pt, app.Single_DropDown_Pt, app.DistanceLabel, app.Single_Spinner_R, app.Single_DropDown_R], 'Visible', hasE);
            multiStep = numel(app.Single_DropDown_step.Items) > 1; set(app.Single_DropDown_step, 'Visible', loaded && multiStep, 'Enable', multiStep);
            blocks = loaded && numel(app.Single_DropDown_FFD.Items) > 1; set([app.Single_DropDown_FFD, app.FFDFreqDropDownLabel], 'Visible', blocks, 'Enable', blocks);
            set([app.TextFormatLabel, app.Single_DropDown_TextFormat], 'Visible', loaded && io_isGeneric(app.Single_EditField_Path.Value));
            app.Single_CheckBox_HPBWBounds.Visible = app.Button_HPBW.Value;
            % Coverage tab
            pats = app.covPatternNodes(); hasP = ~isempty(pats); jobs = app.covJobs(); hasJ = ~isempty(jobs);
            base = [app.AntennaPatternEditFieldLabel, app.Cov_EditField_filePath, app.Cov_Button_Load, app.Cov_Button_computeCov];
            res = [app.covQueryControls(), app.Cov_Button_Reset, app.Cov_Button_Export, app.Cov_Button_Clear, app.Cov_Button_toMain];
            set(app.Cov_gridPanel_Parm.Children, 'Visible', hasP, 'Enable', 'on'); set(base, 'Visible', 'on'); if hasJ, set(res, 'Visible', 'on'); end
            conical = app.Cov_ButtonGroup_Btn_Conical.Value;
            set([app.Cov_Spinner_ConeTH, app.Cov_Spinner_ConePH, app.Cov_Spinner_ConeAng, app.ConeSpinnerLabel, app.ConeLabel, app.ConeAngleLabel, ...
                app.Cov_DropDown_Orientation, app.Cov_DropDown_OrientationLabel], 'Visible', hasP && conical, 'Enable', conical);
            set([app.Cov_Button_computeCov, app.Cov_DropDown_Component, app.Cov_DropDown_ComponentLabel], 'Enable', hasP);
            set([app.Cov_Button_Export, app.Cov_Button_Clear, app.covQueryControls()], 'Enable', hasJ); app.Cov_Button_Reset.Enable = hasP || hasJ;
            cp = app.Cov_EditField_filePath.Value; set([app.Cov_TextFormatLabel, app.Cov_DropDown_TextFormat], 'Visible', hasP && io_isGeneric(cp) && ~isempty(app.covFindByPath(cp)));
            app.Cov_Panel_Results.Visible = hasP || hasJ;
        end

        function h = covQueryControls(app)
            h = [app.Cov_QueryCoverageLabel, app.Cov_Spinner_queryCov, app.Cov_Button_queryCov, app.Cov_QueryThresholdLabel, app.Cov_Spinner_queryThresh, app.Cov_Button_queryThresh];
        end

        function onRange(app, group, src, which)
            %ONRANGE Slider/spinner callback for one range group. WHICH: 0 slider, 1 min spinner, 2 max spinner, 3 both spinners.
            if app.Busy, return; end
            g = string(group); if g == "all", lim = app.Range.full; else, lim = app.Range.(g); end
            switch which, case 0, lim = src.Value; case 3, lim = [app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value]; otherwise, lim(which) = src.Value; end
            if g == "all", app.Range.Auto.full = false; app.Range.Auto.cut = false; app.applyRange("full", lim, 3); app.applyRange("cut", lim, 3);
            else, app.Range.Auto.(g) = false; app.applyRange(g, lim, which); end
            if g == "covX" || g == "cov", return; end
            [app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value] = deal(app.Range.full(1), app.Range.full(2));
            app.on("range");
        end

        function applyRange(app, group, lim, which)
            %APPLYRANGE One descriptor-driven writer for the four range groups: clamp, widen-then-set sliders, spinner
            %   limits with the group's gap, then the owning axes. WHICH −1 = preset (slider limits := lim), 1/2/3 = spinner
            %   edits (slider limits widen only), 0 = slider drag (limits untouched, value only).
            g = string(group); R = app.RangeCtl.(g); K = apat_const(); hard = K.Hard;
            lim = sort(double(lim(:).')); if numel(lim) < 2 || any(~isfinite(lim)), lim = hard; end
            lim = [max(hard(1), lim(1)), min(hard(2), lim(2))]; if diff(lim) < R.gap, lim(2) = min(hard(2), lim(1) + R.gap); lim(1) = max(hard(1), lim(2) - R.gap); end
            app.Range.(g) = lim;
            for sl = R.sl(:).'
                if which == 0, set(sl, 'Value', lim); continue; end
                if which < 0, L = lim; else, L = [min(sl.Limits(1), lim(1)), max(sl.Limits(2), lim(2))]; end
                set(sl, 'Limits', hard); set(sl, 'Value', lim); set(sl, 'Limits', L);
            end
            set(R.mn, 'Limits', [hard(1), lim(2) - R.gap], 'Value', lim(1)); set(R.mx, 'Limits', [lim(1) + R.gap, hard(2)], 'Value', lim(2));
            switch g
                case "cut", set(app.Single_paxCut, 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.Single_AxesRect.YLim = lim;
                case "covX", app.Cov_Axes.XLimMode = 'manual'; app.Cov_Axes.XLim = lim;
            end
        end

        function setStatus(app, label, msg, transient)
            %SETSTATUS One reusable timer; the persistent text lives in app.Status.(label.Tag), not in the widget.
            if app.isClosing || ~isgraphics(label), return; end
            stop(app.StatusTimer); label.Text = char(msg);
            if ~transient, app.Status.(label.Tag) = char(msg); return; end
            app.StatusTimer.TimerFcn = @(~, ~) set(label, 'Text', app.Status.(label.Tag)); start(app.StatusTimer);
        end

        function perf(app, stage)
            %PERF perf("begin <op>") | perf("<stage>") | perf("end") → app.Perf and base-workspace Perf_<class> (M7 record shape).
            if startsWith(stage, "begin"), app.PerfRun = struct('Op', extractAfter(stage, 6), 'T0', tic, 'T', tic, 'Rows', {cell(0, 2)}); return; end
            if isempty(app.PerfRun), return; end
            app.PerfRun.Rows(end+1, :) = {char(stage), toc(app.PerfRun.T)}; app.PerfRun.T = tic;
            if stage ~= "end", return; end
            app.Perf = struct('AppVersion', class(app), 'Operation', app.PerfRun.Op, 'Stages', cell2table(app.PerfRun.Rows, 'VariableNames', {'Stage', 'Seconds'}), 'TotalSeconds', toc(app.PerfRun.T0));
            assignin('base', matlab.lang.makeValidName("Perf_" + class(app)), app.Perf); app.PerfRun = [];
        end

        function checkCancelled(app)
            if ~isempty(app.Dialog) && isvalid(app.Dialog) && app.Dialog.CancelRequested, error('APAT:Cancelled', 'Operation cancelled by user.'); end
        end

        function showError(app, err, title)
            if app.isClosing || ~isvalid(app.UIFigure), return; end
            where = ''; if ~isempty(err.stack), where = sprintf('\n(%s line %d)', err.stack(1).name, err.stack(1).line); end
            uialert(app.UIFigure, [err.message where], title, 'Icon', 'error');
        end

        function [names, labels] = componentItems(~, e)      % plottable columns: gain/ar/plf kinds (all columns for gain-only)
            K = apat_const();
            if e.Pattern.IsGainOnly, names = string(fieldnames(e.Pattern.G)).'; labels = names; return; end
            sel = ismember({K.Cols.kind}, {'gain', 'ar', 'plf'}); names = string({K.Cols(sel).name}); labels = string({K.Cols(sel).label});
        end
        function names = colNames(~, e), names = string(fieldnames(e.Derived.Cols)).'; end
        function C = col(app, name)                          % current (or named) component matrix of the Main pattern
            D = app.Pats(app.Main).Derived.Cols; if nargin < 2, name = app.View.Component; end
            if ~isfield(D, name), f = fieldnames(D); name = f{1}; end, C = D.(name);
        end
        function s = compLabel(app)
            dd = app.Single_DropDown_Component; i = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(i), s = string(dd.Value); else, s = string(dd.Items{i}); end
        end
        function txt = mainStatus(app, e)
            D = e.Derived; K = D.Peak; [ti, pj] = ind2sub(size(e.Geometry.dOmega), K.index); u = e.Source.Meta.UnitLabel;
            txt = sprintf('Pattern: <b>%s</b> | POB <b>%s %s</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)', e.Name, util_fmtNumber(K.value, 2), u, ...
                util_fmtNumber(e.Pattern.Theta(ti)), util_fmtNumber(e.Pattern.Phi(pj)));
            if ~e.Pattern.IsGainOnly, txt = sprintf('%s | Polarization <b>%s</b>', txt, D.Pol.label); end
            if K.wasAdjusted, txt = sprintf('%s | <i>%d isolated spike(s) excluded from the peak</i>', txt, K.spikeCount); end
        end
    end

    %% ================================================================== D. RENDERERS (retained mode)
    methods (Access = private)

        function renderVisible(app)
            k = find(app.Single_tabPlots.SelectedTab == [app.Gfx.Full.Tab], 1); if ~isempty(k), app.renderFull(k); end
        end

        function [lim, map] = theme(app)                     % colour scale for the selected component (AR: fixed signed map)
            K = apat_const();
            if util_colKind(app.View.Component) == "ar", lim = K.ARLimits; map = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256));
            else, lim = app.Range.full; map = jet(256); end
        end

        function renderFull(app, k)
            %RENDERFULL Draw/refresh full-pattern view k in place. Skips when nothing it depends on changed (key).
            s = app.Gfx.Full(k); e = app.Pats(app.Main); P = e.Pattern; M = app.Map; V = app.View; lim = app.theme();
            key = sprintf('%d|%s|%s|%s|%s|%g', P.Revision, jsonencode(e.Params), V.Component, M.Key, mat2str(lim), V.Cstep);
            if V.Overlay && any(s.Kind == ["sphere", "polar"]), key = [key '|' jsonencode(app.CutData.angle) jsonencode(app.CutData.Y(:, 1)) mat2str(app.Range.cut)]; end
            if strcmp(s.Key, key), return; end
            C = app.col(); Cd = C(:, M.ColIdx); [PH, TH] = meshgrid(P.Phi(M.ColIdx), P.Theta); [X, Y, Z] = deal([]);
            switch s.Kind
                case "pcolor",  X = M.PhiAxis; Y = M.ThetaAxis; Z = zeros(size(Cd));
                case "fisheye", X = deg2rad(PH); Y = TH; Z = zeros(size(Cd));
                case "rect",    X = M.PhiAxis; Y = M.ThetaAxis; Z = Cd;
                otherwise,      r = 1; if s.Kind == "polar", r = util_polarRadius(Cd, lim); end
                                X = r.*sind(TH).*cosd(PH); Y = r.*sind(TH).*sind(PH); Z = r.*cosd(TH);
            end
            ax = s.Axes; fresh = ~util_live(s.Surface) || ~isequal(size(s.Surface.CData), size(Cd));
            if fresh
                cla(ax); hold(ax, 'on');
                if s.Kind == "pcolor", s.Surface = pcolor(ax, X, Y, Cd); set(s.Surface, 'FaceColor', 'interp', 'LineStyle', 'none');
                elseif s.Kind == "fisheye", s.Surface = surface(ax, X, Y, Z, Cd, 'EdgeColor', 'none');
                else, s.Surface = surf(ax, X, Y, Z, Cd, 'EdgeColor', 'none'); end
                s.Surface.ContextMenu = app.Gfx.Menu; s.Marker = gobjects(0); s.Tip = gobjects(0); s.Overlay = gobjects(0); s.Colorbar = colorbar(ax);
                if any(s.Kind == ["sphere", "polar"])
                    set(ax, 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1], 'Projection', 'orthographic'); axis(ax, 'off');
                    col = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; lab = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'}; D = 1.35*eye(3);
                    for a = 1:3, quiver3(ax, 0, 0, 0, D(a,1), D(a,2), D(a,3), 0, 'Color', col{a}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25); text(ax, 1.12*D(a,1), 1.12*D(a,2), 1.12*D(a,3), lab{a}, 'Color', col{a}, 'FontWeight', 'bold'); end
                end
            else
                set(s.Surface, 'XData', X, 'YData', Y, 'ZData', Z, 'CData', Cd);
            end
            u = e.Source.Meta.UnitLabel; lbl = app.compLabel();
            switch s.Kind
                case "pcolor", app.formatAngularAxes(ax, 30, 15); daspect(ax, [1 1 1]); title(ax, lbl, 'Interpreter', 'none');
                case "fisheye"
                    set(ax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'RLim', [0 180], 'RTick', 0:30:180); app.polarTicks(ax);
                    rl = 0:30:180; if V.Elevation, rl = 90 - rl; end, ax.RTickLabel = compose('%d°', rl); title(ax, sprintf('%s  |  r=θ, angle=φ', lbl), 'Interpreter', 'none', 'FontSize', 9);
                case "rect"
                    zlim(ax, lim); zt = app.makeTicks(lim, V.Cstep); if ~isempty(zt), ax.ZTick = zt; end
                    app.formatAngularAxes(ax, 60, 30); grid(ax, 'on'); zlabel(ax, sprintf('%s (%s)', lbl, u), 'Interpreter', 'none'); title(ax, lbl, 'Interpreter', 'none'); app.applyCamera(k);
                otherwise, title(ax, sprintf('%s  |  θ: %s  |  φ: %s', lbl, app.Single_Switch_ThetaSpan.Value, app.Single_Switch_AngularSpan.Value), 'Interpreter', 'none'); app.applyCamera(k);
            end
            [~, map] = app.theme(); clim(ax, lim); colormap(ax, map);
            if util_live(s.Colorbar), s.Colorbar.Label.String = u; t = app.makeTicks(lim, V.Cstep); if ~isempty(t), s.Colorbar.Ticks = t; end, end
            try, s.Surface.DataTipTemplate.DataTipRows = [dataTipTextRow(M.ThetaLabel, TH*0 + M.ThetaAxis, '%.3g°'); dataTipTextRow("Phi", PH*0 + M.PhiAxis.', '%.3g°'); dataTipTextRow(replace(lbl, "_", "\_"), Cd, ['%.3g ' char(u)])];
            catch err, app.Status.Warn = err.message; end
            % POB marker + datatip (created once, re-indexed afterwards)
            [ti, pj] = ind2sub(size(C), e.Derived.Peak.index); cj = find(M.ColIdx == pj, 1);
            if s.Kind == "fisheye", mx = X(ti, cj); my = Y(ti, cj); mz = 0; elseif isvector(X), mx = X(cj); my = Y(ti); mz = Z(ti, cj); else, mx = X(ti, cj); my = Y(ti, cj); mz = Z(ti, cj); end
            rows = [dataTipTextRow(M.ThetaLabel, M.ThetaAxis(ti), '%.3g°'); dataTipTextRow("Phi", M.PhiAxis(cj), '%.3g°'); dataTipTextRow(replace(lbl, "_", "\_"), Cd(ti, cj), ['%.3g ' char(u)])];
            if ~util_live(s.Marker)
                if s.Kind == "fisheye", s.Marker = polarplot(ax, mx, my, 'ko', 'MarkerSize', 5, 'MarkerFaceColor', 'k', 'HandleVisibility', 'off');
                else, s.Marker = line(ax, mx, my, mz, 'LineStyle', 'none', 'Marker', 'o', 'MarkerSize', 5, 'MarkerEdgeColor', 'k', 'MarkerFaceColor', 'k', 'HandleVisibility', 'off', 'Clipping', 'off'); end
                s.Marker.DataTipTemplate.DataTipRows = rows; s.Tip = datatip(s.Marker, 'DataIndex', 1, 'HandleVisibility', 'off', 'FontSize', 9);
            else
                if s.Kind == "fisheye", set(s.Marker, 'ThetaData', mx, 'RData', my); else, set(s.Marker, 'XData', mx, 'YData', my, 'ZData', mz); end
                s.Marker.DataTipTemplate.DataTipRows = rows; if ~util_live(s.Tip), s.Tip = datatip(s.Marker, 'DataIndex', 1, 'HandleVisibility', 'off', 'FontSize', 9); end
            end
            % Cut overlay on the two spatial 3-D views (same geometry as the cut, same radius rule as the surface)
            if any(s.Kind == ["sphere", "polar"])
                if V.Overlay
                    cd = app.CutData; r = 1.02; if s.Kind == "polar", r = util_polarRadius(cd.Y(:, 1), lim)*1.01; end
                    ox = r.*sind(cd.theta).*cosd(cd.phi); oy = r.*sind(cd.theta).*sind(cd.phi); oz = r.*cosd(cd.theta);
                    if util_live(s.Overlay), set(s.Overlay, 'XData', ox, 'YData', oy, 'ZData', oz, 'Visible', 'on'); else, s.Overlay = plot3(ax, ox, oy, oz, 'k', 'LineWidth', 1.6, 'HandleVisibility', 'off'); end
                elseif util_live(s.Overlay), s.Overlay.Visible = 'off';
                end
            end
            s.Key = key; app.Gfx.Full(k) = s; app.setAnnotationVisible(k);
        end

        function setAnnotationVisible(app, k)
            s = app.Gfx.Full(k); h = [s.Marker, s.Tip]; if ~isempty(h), set(h(isgraphics(h)), 'Visible', app.View.POB); end
        end

        function applyCamera(app, k)
            s = app.Gfx.Full(k); up = [0 0 1]; ae = s.Camera;
            switch app.View.Camera
                case "top", ae = [0 90]; up = [0 1 0]; case "bottom", ae = [0 -90]; up = [0 1 0]; case "right", ae = [90 0]; case "left", ae = [-90 0]; case "front", ae = [0 0]; case "back", ae = [180 0];
            end
            view(s.Axes, ae(1), ae(2)); camup(s.Axes, up);
        end

        function formatAngularAxes(app, ax, phiStep, thetaStep)
            M = app.Map; set(ax, 'XLim', M.PhiLim, 'YLim', M.ThetaLim, 'YDir', M.ThetaDir, 'Box', 'on', 'Layer', 'top', 'XTick', M.PhiLim(1):phiStep:M.PhiLim(2), 'YTick', M.ThetaLim(1):thetaStep:M.ThetaLim(2));
            xlabel(ax, 'Phi (degree)'); ylabel(ax, sprintf('%s (degree)', M.ThetaLabel));
        end

        function polarTicks(app, pax)                         % physical polar geometry, labels follow the φ convention
            a = 0:30:330; if app.View.SignedPhi, a(a > 180) = a(a > 180) - 360; end
            pax.ThetaTick = 0:30:330; pax.ThetaTickLabel = compose('%d°', a);
        end

        function t = makeTicks(~, lim, step)
            t = []; if ~isfinite(step) || step <= 0 || diff(lim) <= 0, return; end
            t = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)], 'stable'); if numel(t) > 60, t = []; end
        end

        function [cols, idx] = cutColumns(app)               % traces: Total + co/cross pair of the selected basis; stable colours
            e = app.Pats(app.Main); V = app.View;
            if e.Pattern.IsGainOnly, cols = V.Component; idx = 1; return; end
            pair = e.Derived.Pol.pairs.(V.Basis); app.CheckBox_Er.Text = char(pair(1)); app.CheckBox_El.Text = char(pair(2));   % co-pol first
            allc = ["E_Total_dB", pair + "_dB"]; sel = V.Traces; if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = allc(idx);
        end

        function renderCut(app)
            %RENDERCUT Polar + rectangular cut from one geo_cut extract, plus POB and HPBW annotations.
            e = app.Pats(app.Main); G = e.Geometry; V = app.View; c = app.Cut; [cols, idx] = app.cutColumns();
            Y = zeros(numel(c.lin), numel(cols)); for j = 1:numel(cols), M = app.col(cols(j)); Y(:, j) = M(c.lin); end
            ang = c.angle; th = c.theta; ph = c.phi;
            if V.SignedPhi, ang = mod(ang + 180, 360) - 180; end
            [ang, o] = unique(ang); Y = Y(o, :); th = th(o); ph = ph(o);
            if (c.type == "Theta" || G.PhiPeriodic) && ang(end) - ang(1) < 360 - 1e-9, ang(end+1) = ang(1) + 360; Y(end+1, :) = Y(1, :); th(end+1) = th(1); ph(end+1) = ph(1); end
            ttl = sprintf('%s cut @ %s = %g°', c.type, c.symbol, c.fixed); if e.Pattern.IsGainOnly, ttl = sprintf('%s  |  %s', app.compLabel(), ttl); end
            names = replace(cols, "_", "\_"); u = char(e.Source.Meta.UnitLabel);
            app.CutData = struct('angle', ang, 'Y', Y, 'names', names, 'theta', th, 'phi', ph, 'title', ttl, 'cols', cols);
            pax = app.Single_paxCut; rax = app.Single_AxesRect; delete(app.Gfx.Cut(isgraphics(app.Gfx.Cut))); app.Gfx.Cut = gobjects(0);
            lim = app.Range.cut; pl = polarplot(pax, deg2rad(ang), max(Y, lim(1)), 'LineWidth', 1.4); hold(pax, 'on'); rl = plot(rax, ang, Y, 'LineWidth', 1.4); hold(rax, 'on');
            pal = rax.ColorOrder; colr = pal(1 + mod(idx - 1, size(pal, 1)), :); set(pl(:), {'Color'}, num2cell(colr, 2)); set(rl(:), {'Color'}, num2cell(colr, 2));
            for j = 1:numel(pl), rows = [dataTipTextRow("Angle", ang, '%.3g°'); dataTipTextRow("Magnitude", Y(:, j), ['%.3g ' u])]; pl(j).DataTipTemplate.DataTipRows = rows; rl(j).DataTipTemplate.DataTipRows = rows; end
            app.Gfx.Cut = [pl(:); rl(:)];
            set(pax, 'ThetaDir', 'clockwise', 'ThetaZeroLocation', 'top', 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.polarTicks(pax);
            xl = app.Map.PhiLim; set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, sprintf('%s (degree)', c.type)); ylabel(rax, sprintf('Magnitude (%s)', u)); title(pax, ttl, 'Interpreter', 'none'); title(rax, ttl, 'Interpreter', 'none');
            [pk, ip] = max(Y(:, 1), [], 'omitnan'); app.Label_HPBW.Text = '';
            if isfinite(pk)                                              % POB of the displayed cut (first trace)
                rows = [dataTipTextRow("Angle", ang(ip), '%.3g°'); dataTipTextRow(names(1), pk, ['%.3g ' u])];
                app.Gfx.Cut = [app.Gfx.Cut; app.cutMark(pax, ang(ip), pk, 'k', rows, V.POB); app.cutMark(rax, ang(ip), pk, 'k', rows, V.POB)];
                if V.HPBW
                    [bw, lo, hi] = met_hpbw(ang, Y(:, 1), pk, ang(ip));
                    if isfinite(bw)
                        b = [lo, hi]; if xl(1) < 0, b = mod(b + 180, 360) - 180; else, b = mod(b, 360); end
                        app.Label_HPBW.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                        if b(1) <= b(2), reg = b; else, reg = [xl(1), b(2); b(1), xl(2)]; end
                        app.Gfx.Cut(end+1) = thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                        app.Gfx.Cut(end+1) = xregion(rax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                        for q = 1:2
                            bl = ["Lower HPBW", "Upper HPBW"]; rows = [dataTipTextRow(bl(q), b(q), '%.2f°'); dataTipTextRow("Level", pk - 3, ['%.2f ' u])];
                            app.Gfx.Cut = [app.Gfx.Cut; app.cutMark(pax, b(q), pk - 3, '#D95319', rows, V.HPBWBounds); app.cutMark(rax, b(q), pk - 3, '#D95319', rows, V.HPBWBounds)];
                        end
                    end
                end
            end
            legend(pax, pl, names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rl, names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off');
        end

        function h = cutMark(~, ax, x, y, colr, rows, visible)  % marker + datatip on a cut axes; returns both handles
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), m = polarplot(ax, deg2rad(x), y, 'o', 'Color', colr, 'MarkerFaceColor', colr, 'HandleVisibility', 'off');
            else, m = plot(ax, x, y, 'o', 'Color', colr, 'MarkerFaceColor', colr, 'HandleVisibility', 'off'); end
            m.DataTipTemplate.DataTipRows = rows; t = datatip(m, 'DataIndex', 1, 'HandleVisibility', 'off', 'FontSize', 9); set([m t], 'Visible', visible); h = [m; t];
        end

        function renderTables(app)
            %RENDERTABLES Input table once per source; Results table only when its tab is showing and its key changed.
            e = app.Pats(app.Main); M = app.Map;
            if ~strcmp(app.State.RawKey, e.Path), app.Single_Table_DataIn.Data = e.Source.Raw; app.Single_Table_DataIn.ColumnName = e.Source.Raw.Properties.VariableNames; app.State.RawKey = e.Path; end
            if app.Single_tabData.SelectedTab ~= app.Single_tabDataOut, return; end
            key = sprintf('%d|%s|%s|%s', e.Pattern.Revision, jsonencode(e.Params), M.Key, mat2str(app.State.OutMask)); if strcmp(app.State.TableKey, key), return; end
            [X, names] = app.resultsTable(); app.Single_Table_DataOut.Data = X; app.Single_Table_DataOut.ColumnName = names; app.State.TableKey = key;
        end

        function filterToggle(app)                            % Results column filter dropdown: toggle one column, restyle
            dd = app.Single_DropDown_output; if dd.Value > 0, app.State.OutMask(dd.Value) = ~app.State.OutMask(dd.Value); dd.Value = 0; end
            app.styleFilter(); app.State.TableKey = ''; app.on("tables");
        end
        function styleFilter(app)
            dd = app.Single_DropDown_output; dd.Items = regexprep(dd.Items, '^✓ ?', ''); removeStyle(dd); on = find(app.State.OutMask) + 1; dd.Items(on) = append('✓ ', dd.Items(on));
            addStyle(dd, uistyle('FontWeight', 'bold', 'FontColor', 'black', 'BackgroundColor', [0.8 1 0.8]), 'Item', on);
            addStyle(dd, uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9]), 'Item', find([true, ~app.State.OutMask]));
        end

        function renderMetadata(app)
            %RENDERMETADATA One {label, value} list from Meta, Pattern, Geometry, Derived, Params and the pinned conventions.
            e = app.Pats(app.Main); P = e.Pattern; G = e.Geometry; D = e.Derived; K = D.Peak; Mt = D.Metrics; S = e.Source.Meta; f = @util_fmtNumber; u = char(S.UnitLabel);
            Ax = apat_const().Axes; [ti, pj] = ind2sub(size(G.dOmega), K.index); [ri, rj] = ind2sub(size(G.dOmega), K.rawIndex);
            rows = {'Source format', char(S.Format); 'File', e.Name; 'Level unit', u; ...
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', numel(G.dOmega), numel(P.Theta), numel(P.Phi)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', f(P.Theta(1)), f(P.Theta(end)), f(P.dTheta)); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°  (%s)', f(P.Phi(1)), f(P.Phi(end)), f(P.dPhi), char("periodic: " + string(G.PhiPeriodic))); ...
                'Solid angle', sprintf('%s sr  (full sphere: %s)', f(G.Omega, 4), char(string(G.IsFullSphere)))};
            fr = e.Source.Freqs(isfinite(e.Source.Freqs)); if ~isempty(fr), rows(end+1, :) = {'Frequencies', strjoin(compose('%.4g GHz', fr(:).'/1e9), ', ')}; end
            if ~P.IsGainOnly
                rows(end+1, :) = {'Polarization (main beam)', char(D.Pol.label)};
                rows(end+1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(D.Pol.pairs.(app.View.Basis), ' / '))};
                rows(end+1, :) = {'Parameters', sprintf('L = %s dB, Rx %s (AR %s dB), Pt = %s dBW, R = %s m', f(e.Params.L), e.Params.RxMode, f(e.Params.RxAR_dB), f(e.Params.Pt_dBW), f(e.Params.R_m))};
            else, rows(end+1, :) = {'Parameters', sprintf('L = %s dB (gain-kind columns only)', f(e.Params.L))};
            end
            rows = [rows; {'Peak gain (POB)', sprintf('%s %s', f(K.value), u); 'POB direction [θ, φ]', sprintf('[%s°, %s°]', f(P.Theta(ti)), f(P.Phi(pj))); ...
                'Peak policy', sprintf('spatial isolation > %g dB over 4 grid neighbours (%d spike(s))', apat_const().PeakExcessDB, K.spikeCount)}];
            if K.wasAdjusted, rows(end+1, :) = {'Raw maximum (excluded)', sprintf('%s %s at [%s°, %s°]', f(K.rawValue), u, f(P.Theta(ri)), f(P.Phi(rj)))}; end
            rows = [rows; {'Boresight axis', Ax.labels{D.Boresight}; 'E-plane / H-plane', sprintf('%s = %s° / %s = %s°', D.Planes.E.type, f(D.Planes.E.value), D.Planes.H.type, f(D.Planes.H.value)); ...
                'HPBW E-plane', sprintf('%s°', f(Mt.HPBW_EPlane_deg)); 'HPBW H-plane', sprintf('%s°', f(Mt.HPBW_HPlane_deg)); ...
                'Front-to-back', sprintf('%s dB', f(Mt.FrontBack_dB)); 'Peak directivity', sprintf('%s dB', f(Mt.PeakDirectivity_dB))}];
            if ~G.IsFullSphere, rows{end, 2} = [rows{end, 2} ' (upper bound: partial sphere)']; end
            if isfinite(Mt.Efficiency_pct), rows(end+1, :) = {'Radiation efficiency', sprintf('%s%%', f(Mt.Efficiency_pct))}; end
            if isfinite(Mt.AxialRatioAtPeak_dB), rows(end+1, :) = {'AR at peak', sprintf('%s dB', f(Mt.AxialRatioAtPeak_dB))}; end
            for n = P.Meta.Notes(:).', rows(end+1, :) = {'Reader note', char(n)}; end %#ok<AGROW>
            app.Single_Table_metadata.Data = rows;
        end
    end

    %% ================================================================== E. COVERAGE TAB (the tree IS the job registry)
    methods (Access = private)

        function cfg = readCoverageConfig(app)
            %READCOVERAGECONFIG The only reader of Coverage-tab widgets. Writes nothing.
            cfg.Component = string(app.Cov_DropDown_Component.Value);
            tMin = app.Cov_Spinner_ThreshMin.Value; tMax = app.Cov_Spinner_ThreshMax.Value; step = max(app.Cov_Spinner_Step.Value, 0.1);
            assert(tMax > tMin, 'APAT:Thresholds', 'Threshold max must exceed threshold min.');
            cfg.T = cov_thresholds(tMin, tMax, step); cfg.Step = step;
            cfg.Conical = logical(app.Cov_ButtonGroup_Btn_Conical.Value); cfg.Orientation = double(app.Cov_DropDown_Orientation.Value);
            cfg.ConeTheta = app.Cov_Spinner_ConeTH.Value; cfg.ConePhi = mod(app.Cov_Spinner_ConePH.Value, 360); cfg.ConeAngle = app.Cov_Spinner_ConeAng.Value;
            cfg.QueryT = app.Cov_Spinner_queryCov.Value; cfg.QueryC = app.Cov_Spinner_queryThresh.Value;
        end

        function nodes = covPatternNodes(app)
            kids = app.Cov_TreeNode_Results.Children; nodes = kids(arrayfun(@(n) isstruct(n.NodeData) && n.NodeData.kind == "pattern", kids));
        end
        function J = covJobs(app, nodes)                     % all job nodes under NODES (default: whole tree), in id order
            if nargin < 2, nodes = app.Cov_TreeNode_Results.Children; end
            J = matlab.ui.container.TreeNode.empty(0, 1);
            for n = nodes(:).'
                d = n.NodeData; if isstruct(d) && d.kind == "job", J(end+1, 1) = n; else, J = [J; app.covJobs(n.Children)]; end %#ok<AGROW>
            end
            if numel(J) > 1, [~, o] = sort(arrayfun(@(n) n.NodeData.id, J)); J = J(o); end
        end
        function node = covTarget(app)                       % selected pattern node (or ancestor), else the newest pattern node
            node = []; sel = app.Cov_Tree.SelectedNodes;
            if ~isempty(sel), n = sel(1); while isa(n, 'matlab.ui.container.TreeNode'), if isstruct(n.NodeData) && n.NodeData.kind == "pattern", node = n; return; end, n = n.Parent; end, end
            pats = app.covPatternNodes(); if ~isempty(pats), node = pats(end); end
        end
        function node = covFindByPath(app, fp)
            node = []; for n = app.Cov_TreeNode_Results.Children(:).', d = n.NodeData; if isstruct(d) && isfield(d, 'path') && strcmp(d.path, fp), node = n; return; end, end
        end

        function covAddPattern(app, k)
            %COVADDPATTERN Attach registry entry k to the coverage tree (or select its existing node).
            e = app.Pats(k); node = app.covFindByPath(e.Path);
            if isempty(node)
                node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📡 ' e.Name]); node.NodeData = struct('kind', "pattern", 'k', k, 'name', e.Name, 'path', e.Path);
                app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node]; expand(app.Cov_Tree);
            else, node.NodeData.k = k;
            end
            app.Cov_Tree.SelectedNodes = node; app.Cov_EditField_filePath.Value = e.Path; app.covSelectPattern(node);
            app.setStatus(app.Cov_StatusBar, sprintf('Pattern <b>"%s"</b> ready — choose a region and thresholds, then Compute Coverage.', e.Name), false);
        end

        function covLoad(app)
            %COVLOAD Load a pattern or a coverage-results file on the Coverage tab through the same reader/registry path.
            fp = strtrim(app.Cov_EditField_filePath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFindByPath(fp))
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.ffd;*.ffe;*.ffs;*.cut;*.xlsx;*.csv;*.dat;*.txt', 'Pattern / coverage data'; '*.*', 'All files'}, 'Select a pattern or coverage results file');
                if isequal(f, 0), return; end, fp = fullfile(p, f);
            end
            if ~isempty(app.covFindByPath(fp)), app.Cov_Tree.SelectedNodes = app.covFindByPath(fp); app.covSelect(); app.setStatus(app.Cov_StatusBar, 'File already loaded — node selected.', true); return; end
            app.Cov_EditField_filePath.Value = fp; app.covLoadInto(fp, app.Cov_DropDown_TextFormat.Value, []);
        end

        function covLoadInto(app, fp, fmt, node)
            %COVLOADINTO Read FP; results files become job curves, patterns become a registry entry (replacing NODE's if given).
            S = io_read(fp, fmt); app.perf("Read file");
            if S.IsCoverage, app.covLoadResults(fp, S.Raw); return; end
            [~, name, ext] = fileparts(fp); [~, prm] = app.readConfig(); e = app.newEntry([name ext], fp, S, pat_build(S, 1), prm); app.perf("Build pattern");
            if isempty(node), k = numel(app.Pats) + 1; else, k = node.NodeData.k; end
            if isempty(app.Pats), app.Pats = e; else, app.Pats(k) = e; end
            app.covAddPattern(k);
        end

        function covFormatChanged(app)                       % generic-text format changed for a loaded coverage pattern
            fp = strtrim(app.Cov_EditField_filePath.Value); node = app.covFindByPath(fp);
            if ~isempty(node) && io_isGeneric(fp) && node.NodeData.kind == "pattern", app.covLoadInto(fp, app.Cov_DropDown_TextFormat.Value, node); end
        end

        function covSelectPattern(app, node)
            %COVSELECTPATTERN Point the component list, threshold preset and Auto orientation at NODE's pattern.
            e = app.Pats(node.NodeData.k); [names, labels] = app.componentItems(e); dd = app.Cov_DropDown_Component; prev = string(dd.Value);
            dd.Items = cellstr(labels); dd.ItemsData = cellstr(names);
            if any(names == prev), dd.Value = char(prev); elseif any(names == "E_Total_dB"), dd.Value = 'E_Total_dB'; else, dd.Value = dd.ItemsData{1}; end
            app.covPreset(e);
            if app.Cov_DropDown_Orientation.Value == 0, app.covOrientationChanged(); end
        end

        function covPreset(app, e)                            % 50-dB threshold window under the selected column's effective peak
            if ~app.Range.Auto.cov, return; end
            K = met_peak(e.Derived.Cols.(string(app.Cov_DropDown_Component.Value)), e.Geometry.PhiPeriodic, apat_const().PeakExcessDB);
            app.applyRange("cov", util_presetRange(K.value), -1);
        end

        function covCompute(app)
            %COVCOMPUTE Coverage(T) = 100·Ω_R(G > T)/Ω_R on the selected pattern, region and thresholds → one job curve.
            node = app.covTarget(); if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            k = node.NodeData.k; e = app.Pats(k); [~, prm] = app.readConfig(); cfg = app.readCoverageConfig();
            if ~isequal(e.Params, prm), e.Derived = pat_derive(e.Pattern, e.Geometry, prm); e.Params = prm; app.Pats(k) = e; app.perf("Derive"); end
            C = e.Derived.Cols.(cfg.Component); mask = true(size(C)); region = 'Sph';
            if cfg.Conical
                mask = cov_coneMask(e.Pattern, cfg.ConeTheta, cfg.ConePhi, cfg.ConeAngle);
                region = sprintf('Con(%s) α=%s°', app.coneCenterLabel(cfg.ConeTheta, cfg.ConePhi), util_fmtNumber(cfg.ConeAngle));
            end
            cov = cov_curve(C, e.Geometry.dOmega, mask, cfg.T); app.perf("Coverage");
            label = sprintf('%s · %s · L=%s dB', region, cfg.Component, util_fmtNumber(prm.L));
            job = app.covAddJob(node, cfg.T, cov, label, '📉');
            msg = sprintf('Run <b>%d</b>: <b>%s</b> on <b>"%s"</b> (%d thresholds, step %s dB).', job.NodeData.id, label, e.Name, numel(cfg.T), util_fmtNumber(cfg.Step));
            if ~any(mask, 'all'), msg = [msg ' <b>Region contains no samples — coverage is 0 %.</b>']; end
            app.setStatus(app.Cov_StatusBar, msg, false);
        end

        function job = covAddJob(app, parent, T, cov, label, icon)
            %COVADDJOB A job is a curve {T, cov}: one line, one node. Computed and file-loaded jobs are indistinguishable.
            app.State.CovRunID = app.State.CovRunID + 1; id = app.State.CovRunID; label = sprintf('R%d %s', id, label);
            ln = plot(app.Cov_Axes, T(:), cov(:), 'LineWidth', 1.6, 'DisplayName', label);
            job = uitreenode(parent, 'Text', [icon ' ' label]); job.NodeData = struct('kind', "job", 'id', id, 'label', label, 'T', T(:), 'cov', cov(:), 'Line', ln, 'Query', gobjects(0));
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; job]; expand(parent); expand(app.Cov_TreeNode_Results);
            if app.Range.Auto.covX                                   % first curve sets the X window; later ones may only widen it
                x = [T(1) T(end)]; if numel(app.covJobs()) > 1, x = [min(app.Range.covX(1), x(1)), max(app.Range.covX(2), x(2))]; end
                app.applyRange("covX", x, -1);
            end
            app.covRefresh();
        end

        function covLoadResults(app, fp, R)
            %COVLOADRESULTS Results file: column 1 thresholds, every other column one curve (0..100 %).
            [~, name] = fileparts(fp); node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📄 ' name]); node.NodeData = struct('kind', "results", 'name', name, 'path', fp);
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node]; T = R{:, 1};
            for j = 2:width(R), app.covAddJob(node, T, R{:, j}, R.Properties.VariableNames{j}, '📈'); end
            app.setStatus(app.Cov_StatusBar, sprintf('Coverage results file "%s" loaded (%d curves).', name, width(R) - 1), false);
        end

        function covRefresh(app)
            %COVREFRESH Line visibility follows the check boxes; legend and table are rebuilt from the checked jobs.
            J = app.covJobs(); on = ismember(J, app.Cov_Tree.CheckedNodes); ax = app.Cov_Axes;
            for j = 1:numel(J), d = J(j).NodeData; set([d.Line; d.Query(isgraphics(d.Query))], 'Visible', on(j)); end
            if ~any(on), legend(ax, 'off'); app.Cov_Tabel.Data = []; app.Cov_Tabel.ColumnName = {}; return; end
            D = [J(on).NodeData]; legend(ax, [D.Line], {D.label}, 'Location', 'southwest', 'Interpreter', 'none');
            Tu = unique(vertcat(D.T)); X = Tu;                       % table rows = union of the checked thresholds
            for d = D, X(:, end+1) = cov_at(d, Tu); end %#ok<AGROW>  % every cell is one read of one curve
            app.Cov_Tabel.Data = X; app.Cov_Tabel.ColumnName = [{'Threshold (dB)'}, cellfun(@(l) [l ' %'], {D.label}, 'UniformOutput', false)];
        end

        function covSelect(app)
            %COVSELECT Tree selection: highlight the job line, follow the target pattern, and summarise the job in the status bar.
            sel = app.Cov_Tree.SelectedNodes; f = @util_fmtNumber;
            for n = app.covJobs().', n.NodeData.Line.LineWidth = 1.6 + (~isempty(sel) && isequal(n, sel(1))); end
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(app.Cov_StatusBar, 'Ready.', false); return; end
            d = sel(1).NodeData; t = app.covTarget(); if ~isempty(t), app.covSelectPattern(t); app.Cov_EditField_filePath.Value = t.NodeData.path; end
            if d.kind ~= "job"
                app.setStatus(app.Cov_StatusBar, sprintf('%s <b>"%s"</b> — <b>%d</b> coverage job(s).', char(d.kind), d.name, numel(sel(1).Children)), false); return
            end
            [mx, im] = max(round(d.cov, 2)); t50 = thr_at(d, 50);
            msg = sprintf('%s | Threshold [%s, %s] dB | Step %s dB | max <b>%s%%</b> @ <b>%s dB</b>', d.label, f(d.T(1)), f(d.T(end)), f(median(diff(d.T))), f(mx), f(d.T(im)));
            if isfinite(t50), msg = sprintf('%s | <b>50%%</b>-coverage threshold <b>%s dB</b>', msg, f(t50)); end
            app.setStatus(app.Cov_StatusBar, msg, false);
        end

        function covQuery(app, mode)
            %COVQUERY "cov": coverage at a threshold (cov_at); "thr": threshold at a coverage (thr_at). One datatip per checked job.
            sel = app.Cov_Tree.SelectedNodes; if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to query.', true); return; end
            J = app.covJobs(sel); J = J(ismember(J, app.Cov_Tree.CheckedNodes)); cfg = app.readCoverageConfig(); ax = app.Cov_Axes; hit = false; f = @util_fmtNumber;
            for n = J.'
                d = n.NodeData; delete(d.Query(isgraphics(d.Query))); d.Query = gobjects(0);
                if mode == "cov", x = cfg.QueryT; y = cov_at(d, x); else, y = cfg.QueryC; x = thr_at(d, y); end
                if isfinite(x) && isfinite(y)
                    c = d.Line.Color; d.Line.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", @(v, ~) compose('%.2f dB', v)); dataTipTextRow("Coverage", @(~, v) compose('%.2f %%', v))];
                    d.Query = [line(ax, [x x], [ax.YLim(1) y], 'Color', c, 'LineStyle', ':', 'HandleVisibility', 'off'); line(ax, [ax.XLim(1) x], [y y], 'Color', c, 'LineStyle', ':', 'HandleVisibility', 'off'); ...
                        datatip(d.Line, x, y, 'SnapToDataVertex', 'off', 'HandleVisibility', 'off', 'FontSize', 9)];
                    hit = true;
                end
                n.NodeData = d;
            end
            if ~hit, app.setStatus(app.Cov_StatusBar, 'Query value is outside the checked curves.', true);
            elseif mode == "cov", app.setStatus(app.Cov_StatusBar, sprintf('Coverage queried at %s dB.', f(cfg.QueryT)), false);
            else, app.setStatus(app.Cov_StatusBar, sprintf('Threshold queried at %s%% coverage.', f(cfg.QueryC)), false); end
        end

        function covClear(app)                                % delete query marks and datatips under the selected subtree
            sel = app.Cov_Tree.SelectedNodes; if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to clear.', true); return; end
            for n = app.covJobs(sel).', d = n.NodeData; delete(d.Query(isgraphics(d.Query))); d.Query = gobjects(0); delete(findall(d.Line, 'Type', 'datatip')); n.NodeData = d; end
            app.setStatus(app.Cov_StatusBar, 'Selected DataTips and query markers cleared.', true);
        end

        function covReset(app)
            for n = app.covJobs().', d = n.NodeData; delete(d.Query(isgraphics(d.Query))); delete(d.Line); end
            delete(app.Cov_TreeNode_Results.Children); cla(app.Cov_Axes); legend(app.Cov_Axes, 'off'); hold(app.Cov_Axes, 'on'); grid(app.Cov_Axes, 'on');
            app.Cov_Tabel.Data = []; app.Cov_Tabel.ColumnName = {}; app.State.CovRunID = 0;
            if app.Main > 0, app.Pats = app.Pats(app.Main); app.Main = 1; else, app.Pats = struct([]); end   % drop entries no node references
            app.Range.Auto.cov = true; app.Range.Auto.covX = true; app.applyRange("covX", [-40 10], -1); app.applyRange("cov", [-40 10], -1); app.Cov_Axes.XLimMode = 'auto';
            app.setStatus(app.Cov_StatusBar, 'Coverage workspace reset 🔄', true);
        end

        function covExport(app)
            if isempty(app.Cov_Tabel.Data), return; end
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Coverage Results', fullfile(app.folder(), 'coverage_results.csv'));
            if isequal(f, 0), return; end
            T = array2table(app.Cov_Tabel.Data, 'VariableNames', matlab.lang.makeValidName(app.Cov_Tabel.ColumnName)); app.writeTable(T, fullfile(p, f));
            app.setStatus(app.Cov_StatusBar, ['Coverage results exported to ' fullfile(p, f)], true);
        end

        function covOrientationChanged(app)                   % Auto → detected boresight of the target pattern; explicit → that axis
            i = double(app.Cov_DropDown_Orientation.Value); A = apat_const().Axes;
            if i == 0, t = app.covTarget(); if isempty(t), return; end, i = app.Pats(t.NodeData.k).Derived.Boresight; end
            app.Cov_Spinner_ConeTH.Value = A.theta(i); app.Cov_Spinner_ConePH.Value = A.phi(i);
            if app.Cov_ButtonGroup_Btn_Conical.Value, app.setStatus(app.Cov_StatusBar, sprintf('%s | Orientation <b>%s</b>', regexprep(app.Status.cov, '\s*\|\s*Orientation <b>.*?</b>$', ''), A.labels{i}), false); end
        end

        function label = coneCenterLabel(~, theta, phi)      % principal-axis name when the centre matches one, else θ/φ text
            A = apat_const().Axes; v = [sind(theta)*cosd(phi), sind(theta)*sind(phi), cosd(theta)];
            i = find([sind(A.theta(:)).*cosd(A.phi(:)), sind(A.theta(:)).*sind(A.phi(:)), cosd(A.theta(:))]*v(:) >= 1 - 1e-9, 1);
            if isempty(i), label = sprintf('θ=%s°, φ=%s°', util_fmtNumber(theta), util_fmtNumber(phi)); else, label = A.labels{i}; end
        end
    end

    %% ================================================================== F. TOP-LEVEL ACTIONS & EXPORT
    methods (Access = private)

        function onLoad(app)
            fp = strtrim(app.Single_EditField_Path.Value);
            if isempty(fp) || ~isfile(fp)
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.csv;*.dat;*.txt', 'Pattern/Gain Files'}, 'Select an antenna pattern file');
                if isequal(f, 0), return; end, fp = fullfile(p, f);
            end
            fmt = app.Single_DropDown_TextFormat.Value; if ~io_isGeneric(fp), fmt = 'gain'; end
            app.on(@() app.loadMain(fp, fmt), 'Loading Error');
        end
        function formatChanged(app)                           % generic-text interpretation changed → reload the active file
            fp = strtrim(app.Single_EditField_Path.Value);
            if app.Main > 0 && strcmp(fp, app.Pats(app.Main).Path) && io_isGeneric(fp), app.on(@() app.loadMain(fp, app.Single_DropDown_TextFormat.Value), 'Loading Error'); end
        end
        function basisChanged(app), app.State.BasisAuto = false; app.on("pattern"); end
        function resetParams(app)
            d = app.State.Defaults; [app.Single_Spinner_Loss.Value, app.Single_DropDown_RxPol.Value, app.Single_Spinner_Rw.Value, app.Single_Spinner_Pt.Value, ...
                app.Single_DropDown_Pt.Value, app.Single_Spinner_R.Value, app.Single_DropDown_R.Value] = deal(d.L, d.Rx, d.RxAR, d.Pt, d.PtUnit, d.R, d.RUnit);
            app.on("params", 'Processing Error');
        end
        function toCoverage(app)
            if app.Main == 0, return; end
            app.TabGroup.SelectedTab = app.Tab2_Coverage; app.on(@() app.covAddPattern(app.Main), 'Coverage');
        end

        function p = folder(app), p = pwd; if app.Main > 0, p = fileparts(app.Pats(app.Main).Path); end, end

        function [X, names] = resultsTable(app)               % processed grid in the display convention, filtered columns
            e = app.Pats(app.Main); M = app.Map; cols = app.colNames(e); keep = cols(app.State.OutMask); n = numel(M.Perm);
            [TH, PH] = ndgrid(M.ThetaAxis, M.PhiAxis(1:n)); X = [TH(:), PH(:), zeros(numel(TH), numel(keep))];
            for j = 1:numel(keep), C = e.Derived.Cols.(keep(j)); C = C(:, M.Perm); X(:, 2 + j) = C(:); end
            names = cellstr([M.ThetaLabel, "Phi", keep]);
        end

        function exportResults(app)
            if app.Main == 0, return; end
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Results', fullfile(app.folder(), [app.baseName() '_APAT_results.csv']));
            if isequal(f, 0), return; end
            app.on(@() app.doExport(f, p), 'Export Error');
        end
        function doExport(app, f, p)
            [X, names] = app.resultsTable(); app.doWrite(array2table(X, 'VariableNames', names), fullfile(p, f), ['Results exported to <b>' fullfile(p, f) '</b>']);
        end
        function doWrite(app, T, fp, msg), app.writeTable(T, fp); app.setStatus(app.Single_StatusBar, msg, true); end
        function exportCut(app)
            if app.Main == 0, return; end
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, 'Export Cut', fullfile(app.folder(), [app.baseName() '_cut.csv']));
            if isequal(f, 0), return; end
            cd = app.CutData; T = array2table([cd.angle, cd.Y], 'VariableNames', [{'Angle_deg'}, cellstr(cd.cols)]);
            app.on(@() app.doWrite(T, fullfile(p, f), ['Cut (' cd.title ') exported to <b>' fullfile(p, f) '</b>']), 'Export Cut Error');
        end
        function exportUAN(app)
            %EXPORTUAN XGTD UAN from the current pattern at the current loss: φ ∈ [0,360] closed, maximum_gain = total-gain peak.
            if app.Main == 0 || app.Pats(app.Main).Pattern.IsGainOnly, uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            e = app.Pats(app.Main); P = e.Pattern; C = e.Derived.Cols; j = 1:numel(P.Phi); ph = P.Phi; if e.Geometry.PhiPeriodic, j(end+1) = 1; ph(end+1) = P.Phi(1) + 360; end
            [TH, PH] = ndgrid(P.Theta, ph); g = @(M) reshape(M(:, j), [], 1);
            U = table(TH(:), PH(:), round(g(C.E_TH_dB), 5), round(g(C.E_PH_dB), 5), round(g(C.E_TH_Phase), 5), round(g(C.E_PH_Phase), 5), 'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'});
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, 'Export UAN / E-field data', ...
                fullfile(app.folder(), sprintf('%s_%.5f_%gdeg.uan', app.baseName(), e.Derived.Peak.value, P.dTheta)));
            if isequal(f, 0), return; end
            app.on(@() app.doExportUAN(U, fullfile(p, f), P, e.Derived.Peak.value), 'Export UAN Error');
        end
        function doExportUAN(app, U, fp, P, peak)
            if endsWith(fp, '.uan', 'IgnoreCase', true)
                hdr = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\ncomplex\nmag_phase\n' ...
                    'pattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], min(U.Phi), max(U.Phi), P.dPhi, min(U.Theta), max(U.Theta), P.dTheta, peak);
                writelines(hdr, fp); writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
            else, app.writeTable(U, fp); end
            app.setStatus(app.Single_StatusBar, ['UAN exported to <b>' fp '</b>'], true);
        end
        function writeTable(~, T, fp)                         % TXT tab-delimited; CSV/XLSX by writetable's native format
            if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
        end
        function b = baseName(app), [~, b] = fileparts(app.Pats(app.Main).Path); end
    end

    %% ================================================================== G. LAYOUT (declarative: place / labelled / patternTab)
    methods (Access = private)

        function h = place(~, ctor, parent, row, col, varargin)
            h = ctor(parent, varargin{:}); h.Layout.Row = row; h.Layout.Column = col;
        end
        function [lbl, h] = labelled(app, parent, text, row, col, ctor, varargin)
            lbl = app.place(@uilabel, parent, row, col, 'Text', text, 'HorizontalAlignment', 'right'); h = app.place(ctor, parent, row, col + 1, varargin{:});
        end
        function dd = textFormatDropdown(~, parent)
            dd = uidropdown(parent, 'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', '4: POL1=RCP, POL2=LCP — dB magnitude, phase', ...
                '5: POL1=LCP, POL2=RCP — dB magnitude, phase', '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'}, 'Value', 'gain', 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.');
        end
        function [tab, g, ax, sl, mn, mx] = patternTab(app, group, title, axesTitle, needsAxes, k)
            tab = uitab(group, 'Title', title); g = uigridlayout(tab, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'}); ax = [];
            if needsAxes
                ax = app.place(@uiaxes, g, [1 3], 2, 'XLim', [0 360], 'YLim', [0 180], 'YDir', 'reverse', 'XTick', 0:30:360, 'YTick', 0:15:180, 'Box', 'on');
                title(ax, axesTitle); xlabel(ax, 'Phi (degree)'); ylabel(ax, 'Theta (degree)'); zlabel(ax, 'Z'); colormap(ax, 'jet');
            end
            sl = app.place(@(p, varargin) uislider(p, 'range', varargin{:}), g, 2, 1, 'Limits', [-250 100], 'Value', [-250 100], 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s, ~) app.onRange("full", s, 0));
            mx = app.place(@uispinner, g, 1, 1, 'Limits', [-250 100], 'Value', 100, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRange("full", s, 2));
            mn = app.place(@uispinner, g, 3, 1, 'Limits', [-250 100], 'Value', -250, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRange("full", s, 1));
            app.Gfx.Full(k).Tab = tab; %#ok<*NASGU>
        end

        function createComponents(app)
            K = apat_const(); pad = @(n) repmat(char(160), 1, n); cb = @(scope) @(~, ~) app.on(scope);
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' K.ReleaseName], 'Visible', 'off', 'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) app.closeRequest());
            app.GridLayout = uigridlayout(app.UIFigure, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.TabGroup = app.place(@uitabgroup, app.GridLayout, 1, 1);
            % ---------------- Tab 1: Process Pattern
            app.Tab1_Single = uitab(app.TabGroup, 'Title', 'Process Pattern 📡');
            app.Single_Grid = uigridlayout(app.Tab1_Single, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});
            app.Single_Panel_fullPattern = app.place(@uipanel, app.Single_Grid, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off', 'BackgroundColor', [0.9412 0.9412 0.9412]);
            app.Single_gridPanel_full = uigridlayout(app.Single_Panel_fullPattern, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_tabPlots = app.place(@uitabgroup, app.Single_gridPanel_full, 1, 1, 'SelectionChangedFcn', cb("tab"));
            app.Gfx = struct('Full', struct('Tab', cell(1, 5)), 'Cut', gobjects(0), 'Menu', []);
            [app.Single_tabContour, app.Single_gridContour, app.Single_Axes_Ctr, app.Range_Ctr, app.Range_Ctr_Min, app.Range_Ctr_Max] = app.patternTab(app.Single_tabPlots, 'Contour Plot', 'Antenna Gain Pattern', true, 1);
            [app.Single_tabCircular, app.Single_gridCircular, ~, app.Range_Cir, app.Range_Cir_Min, app.Range_Cir_Max] = app.patternTab(app.Single_tabPlots, 'Circular Contour Plot', '', false, 2);
            [app.Single_tab3DSpherical, app.Single_grid3dSpherical, app.Single_Axes_3dSph, app.Range_3dSph, app.Range_3dSph_Min, app.Range_3dSph_Max] = app.patternTab(app.Single_tabPlots, '3D Spherical Plot', '3D Spherical Plot', true, 3);
            [app.Single_tab3DPolar, app.Single_grid3dPolar, app.Single_Axes_3dPol, app.Range_3dPol, app.Range_3dPol_Min, app.Range_3dPol_Max] = app.patternTab(app.Single_tabPlots, '3D Polar Plot', '3D Polar Plot', true, 4);
            [app.Single_tab3DRect, app.Single_grid3dRect, app.Single_Axes_3dRect, app.Range_3dRect, app.Range_3dRect_Min, app.Range_3dRect_Max] = app.patternTab(app.Single_tabPlots, '3D Surface Plot', '3D Surface (Rectangular) Plot', true, 5);
            app.Single_paxPattern = app.place(@polaraxes, app.Single_gridCircular, [1 3], 2, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            % Cut panel
            app.Single_Panel_Rect = app.place(@uipanel, app.Single_Grid, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off', 'BackgroundColor', [0.9412 0.9412 0.9412]);
            app.Single_gridPanel_Cut = uigridlayout(app.Single_Panel_Rect, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_tabCut = app.place(@uitabgroup, app.Single_gridPanel_Cut, 1, 1, 'SelectionChangedFcn', cb("annot"));
            app.Single_tabPolarPlot = uitab(app.Single_tabCut, 'Title', 'Polar Cut Plot');
            app.Single_Grid_Polar = uigridlayout(app.Single_tabPolarPlot, 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            app.Range_Cut = app.place(@(p, varargin) uislider(p, 'range', varargin{:}), app.Single_Grid_Polar, [2 3], 1, 'Limits', [-250 100], 'Value', [-250 100], 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s, ~) app.onRange("cut", s, 0));
            app.Button_HPBW = app.place(@(p, varargin) uibutton(p, 'state', varargin{:}), app.Single_Grid_Polar, 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'IconAlignment', 'center', 'ValueChangedFcn', cb("cut"));
            app.Label_HPBW = app.place(@uilabel, app.Single_Grid_Polar, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            app.Range_Cut_Min = app.place(@uispinner, app.Single_Grid_Polar, 4, 1, 'Limits', [-250 100], 'Value', -250, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRange("cut", s, 1));
            app.Range_Cut_Max = app.place(@uispinner, app.Single_Grid_Polar, 1, 1, 'Limits', [-250 100], 'Value', 100, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRange("cut", s, 2));
            app.Button_ExportCut = app.place(@uibutton, app.Single_Grid_Polar, 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.exportCut());
            app.Single_paxCut = app.place(@polaraxes, app.Single_Grid_Polar, [1 4], 3, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            app.Single_gridEcut = app.place(@uigridlayout, app.Single_Grid_Polar, 3, 4, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x', '1x', '1x'});
            app.CheckBox_Et = app.place(@uicheckbox, app.Single_gridEcut, 1, 1, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', cb("cut"));
            app.CheckBox_Er = app.place(@uicheckbox, app.Single_gridEcut, 2, 1, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', cb("cut"));
            app.CheckBox_El = app.place(@uicheckbox, app.Single_gridEcut, 3, 1, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', cb("cut"));
            app.Single_tabRectPlot = uitab(app.Single_tabCut, 'Title', 'Rectangular Cut Plot'); app.Single_gridRect = uigridlayout(app.Single_tabRectPlot);
            app.Single_AxesRect = app.place(@uiaxes, app.Single_gridRect, [1 2], [1 2], 'XLim', [0 180], 'XTick', 0:15:180, 'Box', 'on');
            xlabel(app.Single_AxesRect, 'Theta (degree)'); ylabel(app.Single_AxesRect, 'Magnitude (dB)'); zlabel(app.Single_AxesRect, 'Z');
            % Data tabs
            app.Single_DropDown_output = app.place(@uidropdown, app.Single_Grid, 3, [13 14], 'Items', {'Select Output:'}, 'Value', 'Select Output:', 'Visible', 'off', 'ValueChangedFcn', @(~, ~) app.filterToggle());
            app.Single_tabData = app.place(@uitabgroup, app.Single_Grid, 4, [1 14], 'Visible', 'off', 'SelectionChangedFcn', cb("tables"));
            app.Single_tabDataOut = uitab(app.Single_tabData, 'Title', 'Results 📤'); app.Single_gridDataOut = uigridlayout(app.Single_tabDataOut, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_DataOut = app.place(@uitable, app.Single_gridDataOut, 1, 1, 'BackgroundColor', [1 1 1], 'ColumnWidth', '1x', 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true, 'Visible', 'off');
            app.Single_tabDataIn = uitab(app.Single_tabData, 'Title', 'Input 📥'); app.Single_gridDataIn = uigridlayout(app.Single_tabDataIn, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_DataIn = app.place(@uitable, app.Single_gridDataIn, 1, 1, 'BackgroundColor', [1 1 1], 'ColumnName', {'Theta'; 'Phi'; 'E-TH-DB'; 'E-PH-DB'; 'E-TH-DG'; 'E-PH-DG'}, 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true, 'Visible', 'off');
            app.MetadataTab = uitab(app.Single_tabData, 'Title', 'Metadata 📋'); app.Single_gridMetadata = uigridlayout(app.MetadataTab, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_metadata = app.place(@uitable, app.Single_gridMetadata, 1, 1, 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            % Plot control panel
            app.Single_Panel_plotControl = app.place(@uipanel, app.Single_Grid, 2, [13 14], 'Title', 'Plot Control 🎨', 'Visible', 'off');
            g = uigridlayout(app.Single_Panel_plotControl, 'RowHeight', repmat({'fit'}, 1, 15)); app.Single_gridPanel_Ctrl = g;
            [app.ComponentLabel, app.Single_DropDown_Component] = app.labelled(g, 'Component', 1, 1, @uidropdown, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'Value', 'E_Total_dB', 'ValueChangedFcn', cb("component"));
            [app.CuttypeDropDownLabel, app.Single_DropDown_cutType] = app.labelled(g, 'Cut type', 2, 1, @uidropdown, 'Items', {'Phi', 'Theta'}, 'Value', 'Phi', 'ValueChangedFcn', cb("cutType"));
            [app.CutvalueSpinnerLabel, app.Single_DropDown_cutValue] = app.labelled(g, 'Cut value', 3, 1, @uispinner, 'Limits', [0 360], 'Value', 0, 'ValueChangedFcn', cb("cut"));
            [app.CutFieldsLabel, app.CutFieldBasisDropDown] = app.labelled(g, 'Cut fields', 4, 1, @uidropdown, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Value', 'Circular', 'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.basisChanged());
            [app.ColorbarmaxLabel, app.Single_Plot_Cmax] = app.labelled(g, 'Colorbar max', 5, 1, @uispinner, 'Limits', [-250 100], 'Value', 10, 'ValueChangedFcn', @(s, ~) app.onRange("all", s, 3));
            [app.ColorbarminLabel, app.Single_Plot_Cmin] = app.labelled(g, 'Colorbar min', 6, 1, @uispinner, 'Limits', [-250 100], 'Value', -40, 'ValueChangedFcn', @(s, ~) app.onRange("all", s, 3));
            [app.ColorbarstepLabel, app.Single_Plot_Cstep] = app.labelled(g, 'Colorbar step', 7, 1, @uispinner, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', cb("range"));
            [app.Single_Label_Clim, app.Single_Button_Clim] = app.labelled(g, 'Adjust Colorbar', 8, 1, @uibutton, 'Text', 'Apply', 'Tooltip', 'Apply to full-pattern plots and cut plots.', 'ButtonPushedFcn', @(s, ~) app.onRange("all", s, 3));
            [app.View3DLabel, app.Single_DropDown_3DView] = app.labelled(g, '3D view', 9, 1, @uidropdown, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Value', 'iso', 'Tooltip', 'Camera direction for the 3D pattern tabs.', 'ValueChangedFcn', cb("camera"));
            app.Single_Switch_AngularSpan = app.place(@(p, varargin) uiswitch(p, 'slider', varargin{:}), g, 10, [1 2], 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'Value', '0° to 360°', 'ValueChangedFcn', cb("span"));
            app.Single_Switch_ThetaSpan = app.place(@(p, varargin) uiswitch(p, 'slider', varargin{:}), g, 11, [1 2], 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'Value', '0° to 180°', 'ValueChangedFcn', cb("span"));
            app.Single_Switch_EHplane = app.place(@(p, varargin) uiswitch(p, 'slider', varargin{:}), g, 12, [1 2], 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'Value', 'E-Plane cut', 'ValueChangedFcn', cb("plane"));
            app.Singel_CheckBox_overlayCut = app.place(@uicheckbox, g, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', cb("cut"));
            app.Single_CheckBox_POB = app.place(@uicheckbox, g, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', cb("annot"));
            app.Single_CheckBox_HPBWBounds = app.place(@uicheckbox, g, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', cb("annot"));
            app.Single_StatusBar = app.place(@uilabel, app.Single_Grid, 5, [1 14], 'Interpreter', 'html', 'Text', 'Ready 🚀', 'Tag', 'main');
            % Inputs & parameters panel
            app.Single_panelParam = app.place(@uipanel, app.Single_Grid, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️');
            g = uigridlayout(app.Single_panelParam, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'}); app.Single_gridPanel_Param = g;
            app.InputPatternLabel = app.place(@uilabel, g, 1, 1, 'Text', 'Input Pattern:', 'HorizontalAlignment', 'right');
            app.Single_EditField_Path = app.place(@uieditfield, g, 1, [2 8]);
            [app.RxPolLabel, app.Single_DropDown_RxPol] = app.labelled(g, 'Rw Sense', 3, 1, @uidropdown, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Value', 'Auto', 'Editable', 'on', 'Visible', 'off');
            [app.IncidentWaveARRwPLFLabel, app.Single_Spinner_Rw] = app.labelled(g, 'Rw (dB)', 3, 3, @uispinner, 'Value', 6, 'Visible', 'off');
            [app.LossindBLabel, app.Single_Spinner_Loss] = app.labelled(g, 'Loss (−) / Gain (+) dB', 3, 5, @uispinner, 'Step', 0.1, 'Visible', 'off');
            [app.TransmitPowerLabel, app.Single_Spinner_Pt] = app.labelled(g, 'Tx Pwr (Pt)', 3, 7, @uispinner, 'Value', 0, 'Visible', 'off');
            app.Single_DropDown_Pt = app.place(@uidropdown, g, 3, 9, 'Items', {'dBW', 'dBm', 'Watts'}, 'Value', 'dBW', 'Visible', 'off');
            app.Single_Button_Load = app.place(@uibutton, g, 1, [11 12], 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.onLoad());
            [app.DistanceLabel, app.Single_Spinner_R] = app.labelled(g, 'Distance', 3, 10, @uispinner, 'Value', 1, 'Visible', 'off');
            app.Single_DropDown_R = app.place(@uidropdown, g, 3, 12, 'Items', {'m', 'km'}, 'Value', 'm', 'Visible', 'off');
            app.Single_DropDown_step = app.place(@uidropdown, g, 2, [9 10], 'Items', {'STEP'}, 'Value', 'STEP', 'Placeholder', 'STEP', 'Enable', 'off', 'Visible', 'off', 'ValueChangedFcn', cb("step"));
            app.Single_Button_Process = app.place(@uibutton, g, 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', @(~, ~) app.on("params", 'Processing Error'));
            app.Single_Button_Coverage = app.place(@uibutton, g, 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.toCoverage());
            app.Single_Export_Output = app.place(@uibutton, g, 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.exportResults());
            app.Single_Export_UAN = app.place(@uibutton, g, 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.exportUAN());
            app.Single_Button_ResetParams = app.place(@uibutton, g, 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', @(~, ~) app.resetParams());
            app.TextFormatLabel = app.place(@uilabel, g, 2, [4 5], 'Text', 'Format:', 'HorizontalAlignment', 'right', 'Visible', 'off');
            app.Single_DropDown_TextFormat = app.place(@(p, varargin) app.textFormatDropdown(p), g, 2, [6 8]); set(app.Single_DropDown_TextFormat, 'Visible', 'off', 'ValueChangedFcn', @(~, ~) app.formatChanged());
            app.FFDFreqDropDownLabel = app.place(@uilabel, g, 1, 9, 'Text', 'FFD Freq:', 'HorizontalAlignment', 'right', 'Enable', 'off', 'Visible', 'off');
            app.Single_DropDown_FFD = app.place(@uidropdown, g, 1, 10, 'Items', {'Frequencies'}, 'Value', 'Frequencies', 'Enable', 'off', 'Visible', 'off', 'ValueChangedFcn', cb("freq"));
            % ---------------- Tab 2: Coverage
            app.Tab2_Coverage = uitab(app.TabGroup, 'Title', 'Compute Coverage 📈');
            app.Cov_Grid = uigridlayout(app.Tab2_Coverage, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            app.Cov_Panel_Param = app.place(@uipanel, app.Cov_Grid, 1, [1 5], 'Title', 'Inputs & Parameters 🎛️');
            g = uigridlayout(app.Cov_Panel_Param, 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'}); app.Cov_gridPanel_Parm = g;
            app.Cov_ButtonGroup_CovType = app.place(@uibuttongroup, g, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', @(~, ~) app.covTypeChanged());
            app.Cov_ButtonGroup_Btn_Spherical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            app.Cov_ButtonGroup_Btn_Conical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            [app.Cov_DropDown_OrientationLabel, app.Cov_DropDown_Orientation] = app.labelled(g, 'Orientation 🧭:', 3, 1, @uidropdown, 'Items', [{'Auto'}, K.Axes.labels], 'ItemsData', 0:numel(K.Axes.labels), 'Value', 0, 'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.on(@() app.covOrientationChanged(), 'Coverage'));
            [app.AntennaPatternEditFieldLabel, app.Cov_EditField_filePath] = app.labelled(g, 'Antenna Pattern:', 1, 3, @uieditfield); app.Cov_EditField_filePath.Layout.Column = [4 8];
            app.Cov_Button_Load = app.place(@uibutton, g, 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', @(~, ~) app.on(@() app.covLoad(), 'Coverage Load Error'));
            app.Cov_Button_computeCov = app.place(@uibutton, g, 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.on(@() app.covCompute(), 'Coverage Error'));
            app.Cov_Button_Reset = app.place(@uibutton, g, 2, 9, 'Text', '🔄 Reset', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.on(@() app.covReset(), 'Coverage'));
            app.Cov_Button_Export = app.place(@uibutton, g, 2, 10, 'Text', '💾 Export Results', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.on(@() app.covExport(), 'Export Error'));
            [app.ThresholdMindBSpinnerLabel, app.Cov_Spinner_ThreshMin] = app.labelled(g, 'Threshold  Min (dB):', 2, 3, @uispinner, 'Value', -40, 'ValueChangedFcn', @(s, ~) app.onRange("cov", s, 1));
            [app.ThresholdMaxdBSpinnerLabel, app.Cov_Spinner_ThreshMax] = app.labelled(g, 'Threshold  Max (dB):', 2, 5, @uispinner, 'Value', 10, 'ValueChangedFcn', @(s, ~) app.onRange("cov", s, 2));
            [app.StepdBSpinnerLabel, app.Cov_Spinner_Step] = app.labelled(g, 'Step (dB):', 2, 7, @uispinner, 'Value', 1, 'Limits', [0.1 100]);
            [app.ConeSpinnerLabel, app.Cov_Spinner_ConeTH] = app.labelled(g, 'Cone θ₀ (°):', 3, 3, @uispinner, 'Limits', [0 180], 'Enable', 'off'); app.ConeSpinnerLabel.Enable = 'off';
            [app.ConeLabel, app.Cov_Spinner_ConePH] = app.labelled(g, 'Cone φ₀ (°):', 3, 5, @uispinner, 'Limits', [0 360], 'Enable', 'off'); app.ConeLabel.Enable = 'off';
            [app.ConeAngleLabel, app.Cov_Spinner_ConeAng] = app.labelled(g, 'Cone Angle α (°):', 3, 7, @uispinner, 'Limits', [0 180], 'Value', 45, 'Enable', 'off'); app.ConeAngleLabel.Enable = 'off';
            app.Cov_Button_Clear = app.place(@uibutton, g, 3, 9, 'Text', '🧹 Clear DataTips', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.on(@() app.covClear(), 'Coverage'));
            app.Cov_Button_toMain = app.place(@uibutton, g, 3, 10, 'Text', '📊 To Main ◀ ', 'ButtonPushedFcn', @(~, ~) set(app.TabGroup, 'SelectedTab', app.Tab1_Single));
            [app.Cov_QueryCoverageLabel, app.Cov_Spinner_queryCov] = app.labelled(g, 'Coverage @ dB:', 4, 3, @uispinner, 'ValueDisplayFormat', '%g dB', 'Visible', 'off');
            app.Cov_Button_queryCov = app.place(@uibutton, g, 4, 5, 'Text', '⯐ Query Coverage', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.on(@() app.covQuery("cov"), 'Coverage'));
            [app.Cov_QueryThresholdLabel, app.Cov_Spinner_queryThresh] = app.labelled(g, 'Threshold @ %:', 4, 6, @uispinner, 'ValueDisplayFormat', '%g%%', 'Value', 50, 'Visible', 'off');
            app.Cov_Button_queryThresh = app.place(@uibutton, g, 4, 8, 'Text', '🔍︎ Query Threshold', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.on(@() app.covQuery("thr"), 'Coverage'));
            [app.Cov_DropDown_ComponentLabel, app.Cov_DropDown_Component] = app.labelled(g, 'Component:', 4, 1, @uidropdown, 'Items', {'E_Total_dB'}, 'Value', 'E_Total_dB', 'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.on(@() app.covSelectPattern(app.covTarget()), 'Coverage'));
            app.Cov_TextFormatLabel = app.place(@uilabel, g, 4, 9, 'Text', 'Format:', 'HorizontalAlignment', 'right', 'Visible', 'off');
            app.Cov_DropDown_TextFormat = app.place(@(p, varargin) app.textFormatDropdown(p), g, 4, 10); set(app.Cov_DropDown_TextFormat, 'Visible', 'off', 'ValueChangedFcn', @(~, ~) app.on(@() app.covFormatChanged(), 'Coverage Format Error'));
            app.Cov_StatusBar = app.place(@uilabel, app.Cov_Grid, 3, [1 5], 'Interpreter', 'html', 'Text', 'Ready 🚀', 'Tag', 'cov');
            app.Cov_Panel_Results = app.place(@uipanel, app.Cov_Grid, 2, [1 5], 'Title', 'Results', 'Visible', 'off');
            app.GridLayout2 = uigridlayout(app.Cov_Panel_Results, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            app.Cov_Axes = app.place(@uiaxes, app.GridLayout2, 1, [2 4], 'Box', 'on', 'Layer', 'top', 'YLim', [0 100], 'Interactions', dataTipInteraction);
            title(app.Cov_Axes, 'Coverage vs Threshold   —   Coverage(T) = 100·Ω_R(G > T) / Ω_R'); xlabel(app.Cov_Axes, 'Threshold (dB)'); ylabel(app.Cov_Axes, 'Coverage (%)'); hold(app.Cov_Axes, 'on'); grid(app.Cov_Axes, 'on');
            app.Cov_Tree = app.place(@(p, varargin) uitree(p, 'checkbox', varargin{:}), app.GridLayout2, [1 2], 1, 'SelectionChangedFcn', @(~, ~) app.on(@() app.covSelect(), 'Coverage'), 'CheckedNodesChangedFcn', @(~, ~) app.on(@() app.covRefresh(), 'Coverage'));
            app.Cov_TreeNode_Results = uitreenode(app.Cov_Tree, 'Text', 'Coverage Results');
            app.Cov_Tabel = app.place(@uitable, app.GridLayout2, [1 2], 5, 'ColumnWidth', '1x', 'RowName', {});
            app.Cov_Spinner_XRange = app.place(@(p, varargin) uislider(p, 'range', varargin{:}), app.GridLayout2, 2, 3, 'Limits', [-250 100], 'Value', [-40 10], 'ValueChangedFcn', @(s, ~) app.onRange("covX", s, 0), 'ValueChangingFcn', @(s, ev) app.onRange("covX", struct('Value', ev.Value), 0));
            app.Cov_Spinner_XMax = app.place(@uispinner, app.GridLayout2, 2, 4, 'Limits', [-250 100], 'Value', 10, 'ValueChangedFcn', @(s, ~) app.onRange("covX", s, 2));
            app.Cov_Spinner_XMin = app.place(@uispinner, app.GridLayout2, 2, 2, 'Limits', [-250 100], 'Value', -40, 'ValueChangedFcn', @(s, ~) app.onRange("covX", s, 1));
            app.UIFigure.Visible = 'on';
        end

        function covTypeChanged(app)
            if app.Cov_ButtonGroup_Btn_Conical.Value, app.on(@() app.covOrientationChanged(), 'Coverage');
            else, app.setStatus(app.Cov_StatusBar, regexprep(app.Status.cov, '\s*\|\s*Orientation <b>.*?</b>$', ''), false); app.on("covUI"); end
        end
    end

    %% ================================================================== H. LIFECYCLE
    methods (Access = private)
        function startupFcn(app)
            %STARTUPFCN Retained-graphics registry, range descriptors, interactions, one context menu, one status timer.
            kinds = ["pcolor", "fisheye", "sphere", "polar", "rect"]; cams = {[], [], [135 25], [135 25], [-35 35]};
            axs = {app.Single_Axes_Ctr, app.Single_paxPattern, app.Single_Axes_3dSph, app.Single_Axes_3dPol, app.Single_Axes_3dRect};
            for k = 1:5
                app.Gfx.Full(k).Axes = axs{k}; app.Gfx.Full(k).Kind = kinds(k); app.Gfx.Full(k).Camera = cams{k}; app.Gfx.Full(k).Key = '';
                for fld = ["Surface", "Marker", "Tip", "Overlay", "Colorbar"], app.Gfx.Full(k).(fld) = gobjects(0); end
            end
            app.Gfx.Menu = uicontextmenu(app.UIFigure); uimenu(app.Gfx.Menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ~) delete(findall(app.UIFigure, 'Type', 'datatip')));
            for k = [1 3 4 5], ax = axs{k}; enableDefaultInteractivity(ax); ax.ContextMenu = app.Gfx.Menu; if k > 1, ax.Interactions = [rotateInteraction, dataTipInteraction]; else, ax.Interactions = [zoomInteraction, dataTipInteraction]; end, end
            enableDefaultInteractivity(app.Single_AxesRect); app.Single_AxesRect.Interactions = [zoomInteraction, dataTipInteraction]; app.Single_AxesRect.ContextMenu = app.Gfx.Menu;
            app.RangeCtl = struct( ...
                'full', struct('sl', [app.Range_Ctr, app.Range_Cir, app.Range_3dSph, app.Range_3dPol, app.Range_3dRect], 'mn', [app.Range_Ctr_Min, app.Range_Cir_Min, app.Range_3dSph_Min, app.Range_3dPol_Min, app.Range_3dRect_Min], ...
                        'mx', [app.Range_Ctr_Max, app.Range_Cir_Max, app.Range_3dSph_Max, app.Range_3dPol_Max, app.Range_3dRect_Max], 'gap', 1), ...
                'cut',  struct('sl', app.Range_Cut, 'mn', app.Range_Cut_Min, 'mx', app.Range_Cut_Max, 'gap', 1), ...
                'cov',  struct('sl', gobjects(0), 'mn', app.Cov_Spinner_ThreshMin, 'mx', app.Cov_Spinner_ThreshMax, 'gap', 0.1), ...
                'covX', struct('sl', app.Cov_Spinner_XRange, 'mn', app.Cov_Spinner_XMin, 'mx', app.Cov_Spinner_XMax, 'gap', 0.1));
            app.Range = struct('full', [-40 10], 'cut', [-40 10], 'cov', [-40 10], 'covX', [-40 10], 'Auto', struct('full', true, 'cut', true, 'cov', true, 'covX', true));
            for gname = ["full", "cut", "cov", "covX"], app.applyRange(gname, [-40 10], -1); end
            app.StatusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3);
            app.State.Defaults = struct('L', app.Single_Spinner_Loss.Value, 'Rx', app.Single_DropDown_RxPol.Value, 'RxAR', app.Single_Spinner_Rw.Value, 'Pt', app.Single_Spinner_Pt.Value, ...
                'PtUnit', app.Single_DropDown_Pt.Value, 'R', app.Single_Spinner_R.Value, 'RUnit', app.Single_DropDown_R.Value);
            app.setStatus(app.Single_StatusBar, 'Ready -- load an antenna pattern file to begin 🚀', false); app.setStatus(app.Cov_StatusBar, 'Ready -- load an antenna pattern file to begin 🚀', false);
            app.applyVisibility();
        end

        function shutdown(app)
            if app.isClosing, return; end, app.isClosing = true;
            t = app.StatusTimer; if ~isempty(t) && isvalid(t), stop(t); delete(t); end
            app.closeDialog(); if ~isempty(app.UIFigure) && isgraphics(app.UIFigure), delete(app.UIFigure); end
        end
    end

    methods (Access = public)
        function app = APAT_v3_M8_5
            createComponents(app); registerApp(app, app.UIFigure); runStartupFcn(app, @startupFcn);
            if nargout == 0, clear app; end
        end
        function closeRequest(app), app.shutdown(); end
        function delete(app), app.shutdown(); end
    end
end

%% ====================================================================== I. READERS (file-scope, UI-free)
%  Every reader returns a Source: Raw (table shown on the Input tab), Blocks{f} = {Theta, Phi, Data} with Data = [Eth Eph]
%  (complex N×2) or gain columns (real N×nC), Freqs, IsCoverage, Meta {Format, Unit, UnitLabel, IsGainOnly, ColNames, Notes}.
%  Meta.Unit is a static property of the format: UAN/FZ/OUT/Excel carry dBi; FFD/FFE/FFS/CUT/generic fields are relative.

function tf = io_isGeneric(fp)
[~, ~, ext] = fileparts(char(fp)); tf = any(strcmpi(ext, {'.csv', '.txt', '.dat'}));
end

function S = io_read(fp, fmt)
%IO_READ Dispatch by extension. FMT is the generic-text interpretation ('gain' | 'linear_*' | 'rcp_lcp_*' | 'lcp_rcp_*').
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
S = struct('Raw', table(), 'Blocks', {{}}, 'Freqs', NaN, 'IsCoverage', false, ...
    'Meta', struct('Format', string(ext), 'Unit', "dB", 'UnitLabel', "dB (rel. field)", 'IsGainOnly', false, 'ColNames', strings(0, 1), 'Notes', strings(0, 1)));
switch ext
    case {'XLSX', 'XLS'},        S = io_excel(fp, S);
    case {'CSV', 'TXT', 'DAT'},  S = io_text(fp, string(fmt), S);
    case 'CUT',                  S = io_cut(fp, S);
    case {'UAN', 'FZ', 'OUT', 'FFS', 'FFE', 'FFD'}, S = io_farfield(fp, ext, S);
    otherwise, error('APAT:Unsupported', 'Unsupported format: %s', ext);
end
end

function [Eth, Eph] = io_fields(A, domain, basis)
%IO_FIELDS Four field columns A = [a b c d] → complex Eθ, Eφ. DOMAIN 'magphase' (dB, deg) | 'rect'; BASIS 'thetaphi' | 'rcplcp' | 'lcprcp'.
if domain == "magphase", c1 = 10.^(A(:, 1)/20).*exp(1i*deg2rad(A(:, 2))); c2 = 10.^(A(:, 3)/20).*exp(1i*deg2rad(A(:, 4)));
else, c1 = complex(A(:, 1), A(:, 2)); c2 = complex(A(:, 3), A(:, 4)); end
switch basis
    case "thetaphi", Eth = c1; Eph = c2;
    case "rcplcp",   [Eth, Eph] = pol_fromCircular(c1, c2);
    case "lcprcp",   [Eth, Eph] = pol_fromCircular(c2, c1);
end
end

function B = io_block(th, ph, Data), B = struct('Theta', th(:), 'Phi', ph(:), 'Data', Data); end

function S = io_farfield(fp, ext, S)
%IO_FARFIELD Six-column far-field text files (UAN/FZ, OUT, FFS, FFE) and HFSS FFD (header + 4 columns, multi-block).
[nHdr, hdr, ffd] = io_header(fp);
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvartype(opts, opts.VariableNames, 'double'); M = readmatrix(fp, opts);
%      key    θφ order  field cols   domain       basis       unit    raw column names
spec = {'UAN', [1 2],   [3 5 4 6],   "magphase",  "thetaphi", "dBi",  {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}
        'FZ',  [1 2],   [3 5 4 6],   "magphase",  "thetaphi", "dBi",  {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}
        'OUT', [1 2],   [3 4 5 6],   "rect",      "rcplcp",   "dBi",  {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}
        'FFS', [2 1],   [3 4 5 6],   "rect",      "thetaphi", "dB",   {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}
        'FFE', [1 2],   [3 4 5 6],   "rect",      "thetaphi", "dB",   {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}
        'FFD', [],      [1 2 3 4],   "rect",      "thetaphi", "dB",   {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}};
r = spec(strcmp(spec(:, 1), ext), :); names = {'XGTD UAN', 'XGTD FZ', 'TICRA/GRASP OUT', 'CST FFS', 'FEKO FFE', 'HFSS FFD'};
S.Meta.Format = string(names{strcmp(spec(:, 1), ext)}); S.Meta.Unit = r{6}; if r{6} == "dBi", S.Meta.UnitLabel = "dBi"; end
if strcmp(ext, 'UAN') && contains(hdr, 'polarization', 'IgnoreCase', true) && ~contains(hdr, 'theta_phi', 'IgnoreCase', true)
    error('APAT:UnsupportedUAN', 'UAN header declares a polarization basis other than theta_phi; APAT reads theta/phi UAN files only.');
end
if strcmp(ext, 'FFD')                                       % θ/φ axes from the header; blocks separated by "Frequency <f>" rows
    assert(ffd.isFFD, 'APAT:FFD', 'FFD header (theta/phi ranges) not found.');
    th = linspace(ffd.th(1), ffd.th(2), ffd.th(3)).'; ph = linspace(ffd.ph(1), ffd.ph(2), ffd.ph(3)).';
    sep = isnan(M(:, 1)); fr = M(sep, min(2, end)); freqs = [ffd.freq(:); fr(isfinite(fr))].'; M = M(~sep, 1:4); M = M(~all(isnan(M), 2), :);
    n = numel(th)*numel(ph); assert(mod(size(M, 1), n) == 0, 'APAT:FFD', 'FFD row count does not match the theta/phi grid.');
    nb = size(M, 1)/n; freqs(end+1:nb) = NaN; S.Freqs = freqs(1:nb); TH = repelem(th, numel(ph)); PH = repmat(ph, numel(th), 1);
    for b = 1:nb, [Eth, Eph] = io_fields(M((b-1)*n + (1:n), :), "rect", "thetaphi"); S.Blocks{b} = io_block(TH, PH, [Eth, Eph]); end
    S.Raw = array2table([TH, PH, M(1:n, :)], 'VariableNames', r{7}); return
end
M = M(~all(isnan(M), 2), 1:min(6, end)); assert(size(M, 2) >= 6, 'APAT:Columns', '%s requires six numeric columns.', ext);
if strcmp(ext, 'FFE')                                       % FEKO: one block per "#Frequency:" line, first block if none declared
    tok = regexp(fileread(fp), '#\s*Frequency\s*:\s*([\d.eE+-]+)', 'tokens'); fr = cellfun(@(t) str2double(t{1}), tok);
    nb = max(1, numel(fr)); rows = size(M, 1);
    if nb > 1 && mod(rows, nb) == 0, S.Freqs = fr; n = rows/nb; else, nb = 1; n = rows; if ~isempty(fr), S.Freqs = fr(1); end, end
    for b = 1:nb, Mb = M((b-1)*n + (1:n), :); [Eth, Eph] = io_fields(Mb(:, r{3}), r{4}, r{5}); S.Blocks{b} = io_block(Mb(:, r{2}(1)), Mb(:, r{2}(2)), [Eth, Eph]); end
    S.Raw = array2table(M(1:n, :), 'VariableNames', r{7}); return
end
[Eth, Eph] = io_fields(M(:, r{3}), r{4}, r{5}); S.Blocks = {io_block(M(:, r{2}(1)), M(:, r{2}(2)), [Eth, Eph])}; S.Raw = array2table(M, 'VariableNames', r{7});
end

function [nHdr, hdr, ffd] = io_header(fp)
%IO_HEADER Count leading non-data lines; parse the HFSS FFD header (two numeric triples + optional "Frequencies ..." line).
lines = readlines(fp); ffd = struct('isFFD', false, 'th', [], 'ph', [], 'freq', []); nHdr = 0; hdr = '';
num = @(s) sscanf(char(s), '%f').'; trip = zeros(0, 3); i = 1;
while i <= numel(lines) && size(trip, 1) < 2                 % first two non-empty lines as triples ⇒ FFD header
    t = strtrim(lines(i)); i = i + 1; if t == "", continue; end
    v = num(t); if numel(v) == 3, trip(end+1, :) = v; else, break; end %#ok<AGROW>
end
if size(trip, 1) == 2
    ffd.th = [trip(1, 1:2), round(trip(1, 3))]; ffd.ph = [trip(2, 1:2), round(trip(2, 3))]; ffd.isFFD = all(isfinite([ffd.th ffd.ph])) && ffd.th(3) >= 1 && ffd.ph(3) >= 1;
    nHdr = i - 1; while i <= numel(lines) && strtrim(lines(i)) == "", i = i + 1; end
    tok = regexp(strtrim(lines(min(i, end))), '^frequencies?\s+(.+)$', 'tokens', 'once', 'ignorecase');
    if ~isempty(tok), v = num(tok{1}); nHdr = i; if ~isscalar(v), ffd.freq = v(:); end, end
    if ffd.isFFD, return; end
end
pat = '^\s*[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?(?:[\s,;]+[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?){3,}\s*$';
nHdr = find(~cellfun(@isempty, regexp(cellstr(lines), pat, 'once')), 1) - 1; if isempty(nHdr), nHdr = 0; end
hdr = char(strjoin(lines(1:nHdr), newline));
end

function S = io_text(fp, fmt, S)
%IO_TEXT Generic CSV/TXT/DAT: coverage-results table, gain-only pattern, or a six-column E-field table per FMT.
opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvartype(opts, 'double'); opts = setvaropts(opts, 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve'; T = readtable(fp, opts);
nc = width(T); assert(nc >= 2 && ~isempty(T), 'APAT:Text', 'File needs at least two numeric columns.');
vn = string(T.Properties.VariableNames); ln = lower(vn); hasHdr = ~all(startsWith(vn, "Var"));
used = nc; if fmt ~= "gain", used = min(nc, 6); end, T = T(all(isfinite(T{:, 1:used}), 2), :);   % drop rows only on the columns APAT uses
c1 = T{:, 1}; rest = T{:, 2:end};
kw = contains(ln(1), "threshold") || any(contains(ln(2:end), "coverage"));
strict = ~hasHdr && fmt == "gain" && nc < 6 && all(rest >= 0 & rest <= 100, 'all') && issorted(c1, 'strictascend') && all(diff(rest, 1, 1) <= 1e-9, 'all');
if kw || strict                                              % coverage curves: monotone non-increasing 0..100 % against a threshold
    if ~hasHdr, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:nc - 1))]; end
    S.Raw = T; S.IsCoverage = true; return
end
if fmt == "gain"
    isTh = contains(ln(1:2), ["theta", "elev"]); isPh = contains(ln(1:2), ["phi", "azim"]);
    if any(isTh) && any(isPh) && isTh(1) ~= isTh(2), phiFirst = isTh(2); S.Meta.Notes(end+1) = "Angle columns identified from the header names.";
    else, phiFirst = max(c1) - min(c1) > max(T{:, 2}) - min(T{:, 2}); S.Meta.Notes(end+1) = "Angle columns identified by span (the wider span is φ)."; end
    if phiFirst, T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; T = movevars(T, 'Theta', 'Before', 1); else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    assert(nc >= 3, 'APAT:Text', 'A gain pattern needs theta, phi and at least one gain column.');
    S.Meta.ColNames = string(matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(T.Properties.VariableNames(3:end)))).'; S.Meta.IsGainOnly = true; S.Meta.Format = "Generic text (gain)";
    if any(contains(ln, "dbi")), S.Meta.Unit = "dBi"; S.Meta.UnitLabel = "dBi"; else, S.Meta.UnitLabel = "dB"; end
    S.Raw = T; S.Blocks = {io_block(T.Theta, T.Phi, T{:, 3:end})}; return
end
assert(nc >= 6, 'APAT:Text', 'The selected generic E-field format requires six numeric columns.');
A = T{:, 3:6}; mp = endsWith(fmt, "magphase"); layout = "grouped";
if mp                                                        % magnitude/phase layout: header names, else the >100° range rule
    isPh = contains(ln(3:6), ["phase", "deg"]); big = max(abs(A), [], 1, 'omitnan') > 100;
    if hasHdr && nnz(isPh) == 2, inter = isequal(isPh, [false true false true]); S.Meta.Notes(end+1) = "Magnitude/phase columns identified from the header names.";
    else, inter = big(2) && ~big(3); S.Meta.Notes(end+1) = "Magnitude/phase layout inferred from value ranges (phase columns exceed 100)."; end
    if inter, A = A(:, [1 3 2 4]); layout = "interleaved"; end
end
if startsWith(fmt, "linear"), basis = "thetaphi"; nm = ["E_TH", "E_PH"]; rect = ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"];
elseif startsWith(fmt, "rcp"), basis = "rcplcp"; nm = ["POL1", "POL2"]; rect = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"];
else, basis = "lcprcp"; nm = ["POL1", "POL2"]; rect = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"]; end
dom = "rect"; if mp, dom = "magphase"; end, [Eth, Eph] = io_fields(A, dom, basis);
if ~hasHdr, if mp, fn = [nm + "_dB", nm + "_deg"]; if layout == "interleaved", fn = fn([1 3 2 4]); end, else, fn = rect; end, T.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", fn]); end
S.Meta.Format = sprintf("Generic text (%s, %s)", fmt, layout); S.Raw = T; S.Blocks = {io_block(T{:, 1}, T{:, 2}, [Eth, Eph])};
end

function S = io_cut(fp, S)
%IO_CUT TICRA/GRASP .cut: blocks of [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data]. ICOMP 1 = θ/φ, 2 = RHCP/LHCP.
S.Meta.Format = "TICRA/GRASP CUT"; L = readlines(fp); L(strlength(strtrim(L)) == 0) = []; th = {}; ph = {}; D = {}; i = 1; icomp = 1; icut = 1;
while i < numel(L)
    p = sscanf(L(i + 1), '%f'); assert(numel(p) >= 7, 'APAT:CUT', 'Could not parse cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6); blk = reshape(sscanf(strjoin(L(i + 2:i + 1 + n), ' '), '%f'), 2*p(7), []).';
    th{end+1, 1} = p(1) + (0:n - 1).'*p(2); ph{end+1, 1} = repmat(p(4), n, 1); D{end+1, 1} = blk(:, 1:4); i = i + 2 + n; %#ok<AGROW>
end
th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:});
if icut == 2, [th, ph] = deal(ph, th); S.Meta.Notes(end+1) = "ICUT = 2: φ swept at constant θ."; end
neg = th < 0; ph(neg) = ph(neg) + 180; th(neg) = -th(neg);
if isscalar(unique(ph))                                      % single cut → body of revolution at 10° φ steps (disclosed)
    k = numel(th); th = repmat(th, 36, 1); ph = repelem((0:10:350).', k); D = repmat(D, 36, 1); S.Meta.Notes(end+1) = "Single cut expanded to a body of revolution (10° φ steps).";
end
switch icomp
    case 1, names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; basis = "thetaphi";
    case 2, names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; basis = "rcplcp";
    otherwise, error('APAT:UnsupportedICOMP', 'GRASP cut ICOMP = %d is not supported (1 = theta/phi, 2 = RHCP/LHCP).', icomp);
end
[Eth, Eph] = io_fields(D, "rect", basis); S.Raw = array2table([th, ph, D], 'VariableNames', [{'Theta', 'Phi'}, names]); S.Blocks = {io_block(th, ph, [Eth, Eph])};
end

function S = io_excel(fp, S)
%IO_EXCEL Matrix workbooks: sheet 1 = summary, fixed component sheets (Gain dBi + Phase deg), C3-origin matrices.
sheets = string(sheetnames(fp)); circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"]; lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
if hasL && hasC, S.Meta.Format = "Excel Matrix Format 3 (Ercp/Elcp + Eth/Eph)"; req = [circ lin]; elseif hasL, S.Meta.Format = "Excel Matrix Format 1 (Eth/Eph)"; req = lin;
elseif hasC, S.Meta.Format = "Excel Matrix Format 2 (Ercp/Elcp)"; req = circ;
else, error('APAT:Excel', 'Unsupported Excel workbook: the worksheets after the summary must be the fixed Eth/Eph and/or RHCP/LHCP component sheets.'); end
Mx = struct(); th = []; ph = [];
for k = 1:numel(req)
    [t, p, X] = io_excelSheet(fp, sheets(find(strcmpi(sheets, req(k)), 1)));
    if isempty(th), th = t; ph = p; elseif ~isequal(numel(t), numel(th)) || ~isequal(numel(p), numel(ph)) || any(abs(t - th) > 1e-9) || any(abs(p - ph) > 1e-9)
        error('APAT:Excel', 'All Excel matrix component sheets must share the same theta/phi grid.'); end
    Mx.(req(k)) = X;
end
if hasL, [Eth, Eph] = io_fields([Mx.Etheta_Gain_dBi(:), Mx.Etheta_Phase_degrees(:), Mx.Ephi_Gain_dBi(:), Mx.Ephi_Phase_degrees(:)], "magphase", "thetaphi");
else, [Eth, Eph] = io_fields([Mx.RHCP_Gain_dBi(:), Mx.RHCP_Phase_degrees(:), Mx.LHCP_Gain_dBi(:), Mx.LHCP_Phase_degrees(:)], "magphase", "rcplcp"); end
[TH, PH] = ndgrid(th, ph); S.Raw = table(TH(:), PH(:), 'VariableNames', {'Theta', 'Phi'}); for k = 1:numel(req), S.Raw.(req(k)) = Mx.(req(k))(:); end
S.Blocks = {io_block(TH, PH, [Eth, Eph])}; S.Meta.Unit = "dBi"; S.Meta.UnitLabel = "dBi";
fMHz = xl_lookup(fp, sheets(1), 'Pattern Simulation Freq (MHz):'); if isfinite(fMHz), S.Freqs = fMHz*1e6; end
end

function [theta, phi, X] = io_excelSheet(fp, sheet)
%IO_EXCELSHEET One C3-origin matrix: row 2 (C onward) = φ, column B (row 3 onward) = θ. readcell keeps worksheet coordinates.
C = readcell(fp, 'Sheet', char(sheet)); assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'APAT:Excel', 'Sheet "%s" has no C3-origin matrix.', sheet);
isnum = @(c) cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), c); pm = isnum(C(2, 3:end)); tm = isnum(C(3:end, 2));
np = find(~pm, 1) - 1; if isempty(np), np = numel(pm); end, nt = find(~tm, 1) - 1; if isempty(nt), nt = numel(tm); end
assert(np > 0 && nt > 0 && ~any(pm(np + 1:end)) && ~any(tm(nt + 1:end)), 'APAT:Excel', 'Sheet "%s" has a gap or no numeric theta/phi axes.', sheet);
phi = cell2mat(C(2, 3:2 + np)).'; theta = cell2mat(C(3:2 + nt, 2)); D = C(3:2 + nt, 3:2 + np);
assert(all(isnum(D), 'all'), 'APAT:Excel', 'Sheet "%s" contains non-numeric or missing matrix samples.', sheet); X = cell2mat(D);
assert(all(diff(theta) > 0) && all(diff(phi) > 0) && theta(1) >= -1e-9 && theta(end) <= 180 + 1e-9 && phi(1) >= -1e-9 && phi(end) < 360 + 1e-9, 'APAT:Excel', 'Sheet "%s" axes must be increasing within θ 0..180, φ 0..360.', sheet);
end

function v = xl_lookup(fp, sheet, label)
%XL_LOOKUP Numeric value to the right of a labelled cell in the summary sheet (NaN when absent).
C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); v = NaN;
[r, c] = find(cellfun(@(x) (ischar(x) || isstring(x)) && strcmpi(strtrim(string(x)), label), C), 1);
if ~isempty(r), for k = c + 1:size(C, 2), if isnumeric(C{r, k}) && isscalar(C{r, k}) && isfinite(C{r, k}), v = C{r, k}; return; end, end, end
end

%% ====================================================================== J. NUMERICAL CORE (file-scope, app-free)

function K = apat_const()
%APAT_CONST Every pinned convention in one place.
persistent C
if isempty(C)
    C.ReleaseName = 'APAT v3 Milestone 8'; C.PeakExcessDB = 6; C.ARLimits = [-30 30]; C.Hard = [-250 100]; C.DistanceFloorM = 1e-12;
    C.Axes = struct('labels', {{'+Z', '-Z', '+X', '-X', '+Y', '-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270]);   % right-handed [polar θ, φ]
    %            name                    label             kind     hidden (Results filter default)
    C.Cols = cell2struct({ ...
        'E_Total_dB',           'Total Gain',     'gain',  false; 'E_TH_dB',      'Etheta Gain',  'gain',  true;  'E_PH_dB',      'Ephi Gain',    'gain',  true
        'E_RCP_dB',             'RHCP Gain',      'gain',  false; 'E_LCP_dB',     'LHCP Gain',    'gain',  false; 'AR_dB',        'Axial Ratio',  'ar',    false
        'PLF_dB',               'PLF',            'plf',   false; 'Gain_PolCorrected_dB', 'Polarized Gain', 'gain', false; 'E_TH_Phase', 'Etheta Phase', 'phase', true
        'E_PH_Phase',           'Ephi Phase',     'phase', true;  'E_RCP_Phase',  'RHCP Phase',   'phase', true;  'E_LCP_Phase',  'LHCP Phase',   'phase', true
        'EIRP_dBW',             'EIRP',           'link',  true;  'PFD_Wm2',      'PFD',          'link',  true;  'E_RMS_Vm',     'E_RMS',        'link',  true}, ...
        {'name', 'label', 'kind', 'hidden'}, 2);
end
K = C;
end

function kind = util_colKind(name)
%UTIL_COLKIND Column semantics from the name (E-field columns are looked up; gain-only names are classified).
K = apat_const(); i = find(strcmp({K.Cols.name}, char(name)), 1); if ~isempty(i), kind = string(K.Cols(i).kind); return; end
key = regexprep(lower(char(name)), '[^a-z0-9]', '');
if startsWith(key, 'ar') || contains(key, 'axial'), kind = "ar"; elseif contains(key, 'plf'), kind = "plf"; elseif contains(key, ["phase", "deg"]), kind = "phase";
elseif contains(key, ["gain", "directivity", "eirp"]) || endsWith(key, 'db'), kind = "gain"; else, kind = "other"; end
end

function step = util_assertUniform(axis, name)
%UTIL_ASSERTUNIFORM Uniform-step check (I1). NaN step for a single sample.
d = diff(axis(:)); step = median(d); if isempty(d), step = NaN; return; end
if any(abs(d - step) > 1e-4), error('APAT:NonUniformGrid', '%s axis is not uniform: steps range %.6g°..%.6g° (APAT requires uniform grids).', name, min(d), max(d)); end
end

function P = pat_build(S, f)
%PAT_BUILD Canonical grid-native pattern from Source block f: polar θ ascending in [0,180], φ ascending in [0,360),
%   uniform steps, no seam column. Angles snapped to 5 decimals; field values never rounded (I1).
B = S.Blocks{min(f, end)}; th = double(B.Theta); ph = double(B.Phi); X = B.Data; notes = S.Meta.Notes;
ok = isfinite(th) & isfinite(ph); th = th(ok); ph = ph(ok); X = X(ok, :);
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, th = 90 - th; notes(end+1) = "Theta read as elevation (−90°..90°) and mapped to polar θ = 90° − el.";
    else, m = th < 0; th(m) = -th(m); ph(m) = ph(m) + 180; notes(end+1) = "Negative theta folded through φ + 180°."; end
end
th = mod(th, 360); m = th > 180; th(m) = 360 - th(m); ph(m) = ph(m) + 180;
th = round(th, 5); ph = round(mod(ph, 360), 5); ph(ph >= 360) = 0;
Theta = unique(th); Phi = unique(ph); dTheta = util_assertUniform(Theta, 'Theta'); dPhi = util_assertUniform(Phi, 'Phi');
if isnan(dTheta), dTheta = 180; end, if isnan(dPhi), dPhi = 360; end
sz = [numel(Theta), numel(Phi)]; lin = sub2ind(sz, round((th - Theta(1))/dTheta) + 1, round((ph - Phi(1))/dPhi) + 1);
[lin, first] = unique(lin);                                   % duplicate directions (e.g. φ = 0 and 360): first sample wins
if numel(lin) ~= prod(sz), error('APAT:NonUniformGrid', 'Pattern is not a complete θ×φ grid: %d distinct directions for %d×%d axes.', numel(lin), sz(1), sz(2)); end
P = struct('Theta', Theta, 'Phi', Phi, 'dTheta', dTheta, 'dPhi', dPhi, 'Eth', [], 'Eph', [], 'G', struct(), 'IsGainOnly', S.Meta.IsGainOnly, 'Freq', S.Freqs(min(f, end)), 'Revision', 1, 'Meta', S.Meta);
P.Meta.Notes = notes;
if P.IsGainOnly, for c = 1:size(X, 2), P.G.(S.Meta.ColNames(c)) = util_grid(sz, lin, X(first, c)); end
else, P.Eth = util_grid(sz, lin, X(first, 1)); P.Eph = util_grid(sz, lin, X(first, 2)); end
end
function M = util_grid(sz, lin, v), M = nan(sz, 'like', v); M(lin) = v; end     % scatter one column onto the nθ×nφ grid

function P = pat_resample(P, step)
%PAT_RESAMPLE Exact decimation when both ratios are integers; otherwise bilinear on the φ-closed grid — E-fields as
%   power + unit phasor, gain-kind columns as linear power, others linear (I6). Target axes stay inside the source domain.
kt = step/P.dTheta; kp = step/P.dPhi; periodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
if abs(kt - round(kt)) < 1e-9 && abs(kp - round(kp)) < 1e-9 && kt >= 1 && kp >= 1
    it = 1:round(kt):numel(P.Theta); ip = 1:round(kp):numel(P.Phi); f = @(M, ~) M(it, ip); th2 = P.Theta(it); ph2 = P.Phi(ip);
else
    th2 = (P.Theta(1):step:P.Theta(end) + 1e-9).';
    if periodic, ph2 = P.Phi(1) + (0:ceil(360/step) - 1).'*step; ph2 = ph2(ph2 < P.Phi(1) + 360 - 1e-9); else, ph2 = (P.Phi(1):step:P.Phi(end) + 1e-9).'; end
    f = @(M, kind) pat_interp(P.Theta, P.Phi, M, th2, ph2, kind, periodic);
end
if P.IsGainOnly, for n = string(fieldnames(P.G)).', P.G.(n) = f(P.G.(n), util_colKind(n)); end, else, P.Eth = f(P.Eth, "field"); P.Eph = f(P.Eph, "field"); end
P.Theta = th2; P.Phi = ph2; P.dTheta = util_assertUniform(th2, 'Theta'); P.dPhi = util_assertUniform(ph2, 'Phi');
if isnan(P.dTheta), P.dTheta = 180; end, if isnan(P.dPhi), P.dPhi = 360; end, P.Revision = P.Revision + 1;
end

function Y = pat_interp(th, ph, M, th2, ph2, kind, periodic)
%PAT_INTERP Bilinear interpolation of one nθ×nφ quantity in the domain that is linear for its KIND (B.5).
if periodic, ph(end+1) = ph(1) + 360; M(:, end+1) = M(:, 1); end
if numel(th) < 2 || numel(ph) < 2, Y = M; return; end
[PH, TH] = meshgrid(ph, th); [PH2, TH2] = meshgrid(ph2, th2); I = @(V) interp2(PH, TH, V, PH2, TH2, 'linear');
switch kind
    case "field", A = abs(M); U = M./max(A, eps); P2 = I(A.^2); U2 = complex(I(real(U)), I(imag(U))); Y = sqrt(max(P2, 0)).*U2./max(abs(U2), eps);
    case "gain",  Y = 10*log10(max(I(10.^(M/10)), realmin));
    otherwise,    Y = I(M);
end
end

function G = geo_build(P)
%GEO_BUILD Separable cell solid angles (I2): wθ(i) = cos(θᵢ−Δθ/2) − cos(θᵢ+Δθ/2) with edges clipped to [0°,180°], ΔΩ = wθ·Δφ.
%   Full sphere: Σwθ = cos0° − cos180° = 2 (telescoping) and nφ·Δφ = 2π ⇒ ΣΔΩ = 4π exactly.
lo = max(P.Theta(:) - P.dTheta/2, 0); hi = min(P.Theta(:) + P.dTheta/2, 180);
G.wTheta = cosd(lo) - cosd(hi); G.dPhi = deg2rad(P.dPhi); G.PhiPeriodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
G.IsFullSphere = G.PhiPeriodic && lo(1) == 0 && hi(end) == 180;
G.dOmega = G.wTheta*G.dPhi*ones(1, numel(P.Phi)); G.Omega = sum(G.dOmega, 'all');
end

function M = geo_displayMap(P, G, V)
%GEO_DISPLAYMAP Display convention as a column permutation + axis relabelling; no data is copied or changed (I8).
n = numel(P.Phi); j0 = find(P.Phi >= 180, 1); perm = 1:n; if V.SignedPhi && ~isempty(j0), perm = [j0:n, 1:j0 - 1]; end
M.Perm = perm; M.ColIdx = perm; if G.PhiPeriodic, M.ColIdx(end+1) = perm(1); end          % closing column for display only
M.PhiAxis = P.Phi(perm); if V.SignedPhi, M.PhiAxis(M.PhiAxis >= 180) = M.PhiAxis(M.PhiAxis >= 180) - 360; end
if G.PhiPeriodic, M.PhiAxis(end+1) = M.PhiAxis(1) + 360; end
if V.Elevation, M.ThetaAxis = 90 - P.Theta; M.ThetaDir = 'normal'; M.ThetaLabel = "Elevation"; M.ThetaLim = [-90 90];
else, M.ThetaAxis = P.Theta; M.ThetaDir = 'reverse'; M.ThetaLabel = "Theta"; M.ThetaLim = [0 180]; end
if V.SignedPhi, M.PhiLim = [-180 180]; else, M.PhiLim = [0 360]; end
M.Key = sprintf('%d|%d', V.SignedPhi, V.Elevation);
end

function c = geo_cut(P, G, type, value)
%GEO_CUT One full-circle cut as linear indices into the nθ×nφ grid. "Phi": the θ row nearest VALUE swept over φ (closed
%   when periodic). "Theta": the φ column nearest VALUE (0..180) joined with the opposite column (180..360), pole once.
[n, m] = size(G.dOmega);
if type == "Phi"
    [d, i] = min(abs(P.Theta - value)); j = 1:m; if G.PhiPeriodic, j(end+1) = 1; end
    lin = sub2ind([n m], i + 0*j, j); ang = P.Phi(j); if G.PhiPeriodic, ang(end) = P.Phi(1) + 360; end
    c = struct('fixed', P.Theta(i), 'symbol', 'θ');
else
    dp = @(a, b) abs(mod(a - b + 180, 360) - 180); [d, j] = min(dp(P.Phi, value)); [~, j2] = min(dp(P.Phi, P.Phi(j) + 180));
    i2 = flip(find(abs(P.Theta - 180) > 1e-9));
    lin = [sub2ind([n m], (1:n).', j + zeros(n, 1)); sub2ind([n m], i2(:), j2 + zeros(numel(i2), 1))]; ang = [P.Theta; 360 - P.Theta(i2)];
    c = struct('fixed', P.Phi(j), 'symbol', 'φ');
end
c.type = type; c.snapped = d > 1e-9; c.lin = lin(:); c.angle = ang(:); [ti, pj] = ind2sub([n m], c.lin); c.theta = P.Theta(ti); c.phi = P.Phi(pj);
end

function D = pat_derive(P, G, prm)
%PAT_DERIVE Every column and every base fact of a pattern at the given parameters (I3, I4). ≈ 40 ms at 1°×1°.
K = apat_const();
if P.IsGainOnly
    D.Cols = P.G; names = string(fieldnames(P.G)).'; kinds = strings(size(names)); for q = 1:numel(names), kinds(q) = util_colKind(names(q)); end
    for n = names(kinds == "gain"), D.Cols.(n) = P.G.(n) + prm.L; end                  % loss on gain-kind columns only
    tn = names(find(kinds == "gain", 1)); if isempty(tn), tn = names(1); end, total = D.Cols.(tn); D.Pol = struct('pairs', struct(), 'label', "n/a");
    D.Peak = met_peak(total, G.PhiPeriodic, K.PeakExcessDB);
else
    s = 10^(prm.L/20); Eth = P.Eth*s; Eph = P.Eph*s; Er = pol_circular(Eth, Eph, 1); El = pol_circular(Eth, Eph, 2);
    C.E_Total_dB = 10*log10(max(abs(Eth).^2 + abs(Eph).^2, eps));
    C.E_TH_dB = 20*log10(max(abs(Eth), eps)); C.E_PH_dB = 20*log10(max(abs(Eph), eps));
    C.E_RCP_dB = 20*log10(max(abs(Er), eps)); C.E_LCP_dB = 20*log10(max(abs(El), eps));
    [C.AR_dB, isLinear] = pol_signedAR(Er, El);
    D.Peak = met_peak(C.E_Total_dB, G.PhiPeriodic, K.PeakExcessDB); [ti, pj] = ind2sub(size(C.E_Total_dB), D.Peak.index);
    D.Pol = pol_classify(Eth, Eph, Er, El, G.dOmega.*cov_coneMask(P, P.Theta(ti), P.Phi(pj), 45));   % main-beam, Ω-weighted
    C.PLF_dB = pol_plf(C.AR_dB, isLinear, prm.RxMode, prm.RxAR_dB, D.Pol.pairs.Circular(1));
    C.Gain_PolCorrected_dB = C.E_Total_dB + C.PLF_dB;
    C.E_TH_Phase = rad2deg(angle(Eth)); C.E_PH_Phase = rad2deg(angle(Eph)); C.E_RCP_Phase = rad2deg(angle(Er)); C.E_LCP_Phase = rad2deg(angle(El));
    C.EIRP_dBW = prm.Pt_dBW + C.E_Total_dB; C.PFD_Wm2 = 10.^(C.EIRP_dBW/10)./(4*pi*prm.R_m^2); C.E_RMS_Vm = sqrt(30*10.^(C.EIRP_dBW/10))./prm.R_m;
    D.Cols = C; total = C.E_Total_dB;
end
D.Boresight = met_orientation(total, P, G, D.Peak); D.Planes = met_planes(D.Boresight);
D.Metrics = met_metrics(total, P, G, D.Peak, D.Planes, D.Cols, P.Meta.Unit);
end

function K = met_peak(C, periodic, excessDB)
%MET_PEAK Effective peak = highest sample that is not an isolated spike (I5):
%   spike(i,j) ⇔ C(i,j) − max(4 grid neighbours) > excessDB;  φ wraps when periodic.
[n, m] = size(C); nb = -inf(n, m);
if n > 1, nb(2:n, :) = max(nb(2:n, :), C(1:n-1, :)); nb(1:n-1, :) = max(nb(1:n-1, :), C(2:n, :)); end            % θ neighbours
if periodic && m > 1, L = circshift(C, 1, 2); R = circshift(C, -1, 2); else, L = [-inf(n, 1), C(:, 1:m-1)]; R = [C(:, 2:m), -inf(n, 1)]; end
nb = max(nb, max(L, R));                                                                                             % φ neighbours
K.spike = isfinite(C) & (C - nb > excessDB); [K.rawValue, K.rawIndex] = max(C(:), [], 'omitnan');
cand = C; cand(K.spike) = -Inf; [K.value, K.index] = max(cand(:), [], 'omitnan');
K.wasAdjusted = K.spike(K.rawIndex); K.spikeCount = nnz(K.spike);
end

function idx = met_orientation(total, P, G, K)
%MET_ORIENTATION Principal axis whose 45° cone holds the most normalised radiated power 10^{(G−Gp)/10}·ΔΩ (spikes excluded).
A = apat_const().Axes; E = 10.^((total - K.value)/10).*G.dOmega; E(~isfinite(E) | K.spike) = 0; energy = zeros(1, numel(A.theta));
for a = 1:numel(A.theta), energy(a) = sum(E(cov_coneMask(P, A.theta(a), A.phi(a), 45)), 'all'); end
[~, idx] = max(energy);
end

function S = met_planes(axisIndex)
%MET_PLANES E-plane: θ-cut through the boresight axis' φ. H-plane: φ-cut at θ = 90° for a transverse axis (±X, ±Y), θ-cut at φ = 90° for ±Z.
A = apat_const().Axes; S.E = struct('type', "Theta", 'value', A.phi(axisIndex));
if A.theta(axisIndex) == 90, S.H = struct('type', "Phi", 'value', 90); else, S.H = struct('type', "Theta", 'value', 90); end
end

function [bw, lo, hi] = met_hpbw(ang, g, peak, peakAng)
%MET_HPBW Half-power beamwidth of a circular cut by linear interpolation of the −3 dB crossings either side of the peak.
[bw, lo, hi] = deal(NaN); v = isfinite(ang) & isfinite(g); ang = ang(v); g = g(v); if numel(g) < 3, return; end
if nargin < 3 || isempty(peak), [peak, i] = max(g); peakAng = ang(i); end
[ra, o] = sort(mod(ang - peakAng + 180, 360) - 180); rg = g(o); h = peak - 3;
l = find(ra < 0 & rg <= h, 1, 'last'); r = find(ra > 0 & rg <= h, 1, 'first'); if isempty(l) || isempty(r) || l + 1 > numel(rg) || r < 2, return; end
if rg(l+1) == rg(l) || rg(r-1) == rg(r), return; end
lc = ra(l) + (ra(l+1) - ra(l))*(h - rg(l))/(rg(l+1) - rg(l)); rc = ra(r) + (ra(r-1) - ra(r))*(h - rg(r))/(rg(r-1) - rg(r));
lo = peakAng + lc; hi = peakAng + rc; bw = rc - lc;
end

function M = met_metrics(total, P, G, K, planes, Cols, unit)
%MET_METRICS Directivity 10·log10(4π·Up/∫U dΩ) with spikes removed; efficiency and F/B only on a full sphere (I9); HPBW on the E/H cuts.
keep = isfinite(total) & ~K.spike; U = 10.^(total/10); I = sum(U(keep).*G.dOmega(keep));
M.PeakGain_dB = K.value; M.PeakDirectivity_dB = 10*log10(max(4*pi*10^(K.value/10)/max(I, eps), eps));
M.Efficiency_pct = NaN; if G.IsFullSphere && unit == "dBi", M.Efficiency_pct = 100*I/(4*pi); if M.Efficiency_pct > 100 + 1e-9, M.Efficiency_pct = NaN; end, end
[ti, pj] = ind2sub(size(total), K.index); M.PeakTheta_deg = P.Theta(ti); M.PeakPhi_deg = P.Phi(pj); M.FrontBack_dB = NaN;
if G.IsFullSphere, sim = cosd(P.Theta)*cosd(M.PeakTheta_deg) + sind(P.Theta)*sind(M.PeakTheta_deg).*cosd(P.Phi.' - M.PeakPhi_deg); [~, b] = min(sim(:)); M.FrontBack_dB = K.value - total(b); end
e = geo_cut(P, G, planes.E.type, planes.E.value); h = geo_cut(P, G, planes.H.type, planes.H.value);
M.HPBW_EPlane_deg = met_hpbw(e.angle, total(e.lin)); M.HPBW_HPlane_deg = met_hpbw(h.angle, total(h.lin));
M.AxialRatioAtPeak_dB = NaN; if isfield(Cols, 'AR_dB'), M.AxialRatioAtPeak_dB = Cols.AR_dB(K.index); end
end

function E = pol_circular(Eth, Eph, which)
%POL_CIRCULAR RHCP (1) / LHCP (2) component of E = Eθ θ̂ + Eφ φ̂ under e^{+jωt}, (θ̂, φ̂, r̂) right-handed (IEEE):
%   ê_R = (θ̂ − jφ̂)/√2  ⇒  E_R = E·ê_R* = (Eθ + jEφ)/√2,  E_L = (Eθ − jEφ)/√2.  Check: E = ê_R ⇒ E_R = 1, E_L = 0.
if which == 1, E = (Eth + 1i*Eph)/sqrt(2); else, E = (Eth - 1i*Eph)/sqrt(2); end
end
function [Eth, Eph] = pol_fromCircular(Er, El)               % inverse of pol_circular (OUT, CUT ICOMP=2, Excel format 2, generic rcp/lcp)
Eth = (Er + El)/sqrt(2); Eph = (Er - El)/(1i*sqrt(2));
end

function [AR, isLinear] = pol_signedAR(Er, El)
%POL_SIGNEDAR Signed axial ratio in dB: + RHCP sense, − LHCP sense; −100 dB at numerically linear samples (M7 floor kept).
r = abs(Er); l = abs(El); d = r - l; isLinear = isfinite(d) & abs(d) <= eps.*max(r + l, 1);
AR = min(20*log10((r + l)./max(abs(d), eps)), 250).*sign(d); AR(isLinear) = -100;
end

function pol = pol_classify(Eth, Eph, Er, El, w)
%POL_CLASSIFY Co/cross pair order and label from Ω-weighted main-beam powers (weights W = ΔΩ inside the peak cone).
p = @(E) sum(abs(E).^2.*w, 'all', 'omitnan'); Pt = p(Eth); Pp = p(Eph); Pr = p(Er); Pl = p(El);
pol.pairs = struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]);
if Pp > Pt, pol.pairs.Linear = flip(pol.pairs.Linear); end, if Pl > Pr, pol.pairs.Circular = flip(pol.pairs.Circular); end
if max(Pr, Pl) > max(Pt, Pp), pol.label = "Circular (" + replace(pol.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]) + ")";
elseif Pt >= Pp, pol.label = "Linear (Vertical)"; else, pol.label = "Linear (Horizontal)"; end
end

function plf = pol_plf(AR_dB, isLinear, rxMode, rxAR_dB, leadingCircular)
%POL_PLF Polarisation loss factor between the antenna ellipse (signed AR) and the incident wave, major axes orthogonal:
%   PLF = 1/2 + (4ρaρw − (ρa²−1)(ρw²−1)) / (2(ρa²+1)(ρw²+1)),  ρ = signed linear axial ratio (+RHCP, −LHCP). NaN in ⇒ NaN out.
switch rxMode, case "RHCP", sw = 1; case "LHCP", sw = -1; otherwise, sw = 2*(leadingCircular == "E_RCP") - 1; end
ra = 10.^(abs(AR_dB)/20).*sign(AR_dB); ra(isLinear) = 1e12; rw = sw*10^(rxAR_dB/20);
plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1))./(2*(ra.^2 + 1)*(rw^2 + 1));
plf = 10*log10(min(max(plf, eps), 1)); plf(~isfinite(AR_dB)) = NaN;
end

function cov = cov_curve(C, dOmega, mask, T)
%COV_CURVE Coverage(T) = 100·Ω_R(C > T)/Ω_R,  Ω_R(C > T) = Σ_{(i,j)∈R, C(i,j) > T} ΔΩ(i,j)   (strict ">", exact, O(N log N)).
%   Distinct levels g₁<…<g_K carry weights w_k; above(k) = Σ_{j≥k} w_j. With k(T) = #{g_k ≤ T}: Ω_R(C > T) = above(k(T)+1).
v = mask & isfinite(C); [g, ~, ic] = unique(C(v)); w = accumarray(ic, dOmega(v)); Omega = sum(w);
cov = zeros(size(T)); if Omega <= 0, return; end
above = [cumsum(w, 'reverse'); 0]; k = discretize(T, [g; Inf]); k(isnan(k)) = 0;
cov = 100*above(k + 1)/Omega;
end

function m = cov_coneMask(P, thC, phC, alphaDeg)
%COV_CONEMASK (i,j) ∈ cone ⇔ cos γ ≥ cos α,  cos γ = cos θᵢ cos θc + sin θᵢ sin θc cos(φⱼ − φc)   (spherical law of cosines).
m = cosd(P.Theta(:))*cosd(thC) + sind(P.Theta(:))*sind(thC).*cosd(P.Phi(:).' - phC) >= cosd(alphaDeg) - 1e-12;
end

function T = cov_thresholds(tMin, tMax, step)                 % by counting, never by accumulating a colon
n = round((tMax - tMin)/step); T = tMin + (0:n).'*step; if T(end) < tMax - 1e-9, T(end+1) = tMax; end
end

function y = cov_at(job, T)                                   % coverage at threshold(s) T: linear read of the curve, NaN outside
y = interp1(job.T, job.cov, T, 'linear', NaN);
end

function T = thr_at(job, c)
%THR_AT Threshold at coverage c %: inverse read of the same curve; for each level keep the highest threshold reaching it.
[cv, i] = unique(job.cov, 'last'); if numel(cv) < 2, T = nan(size(c)); return; end, T = interp1(cv, job.T(i), c, 'linear', NaN);
end

function tf = util_live(h), tf = ~isempty(h) && all(isgraphics(h(:))); end   % a stored handle that still exists

function r = util_polarRadius(values, lim)                    % shared by the polar-3D surface and its cut overlay
r = max(values - lim(1), 0)/max(lim(2) - lim(1), eps); r = r/max(max(r, [], 'all', 'omitnan'), eps);
end

function s = util_fmtNumber(v, prec)                          % compact (≤ 2 dp, no trailing zeros, never "-0") or fixed
if ~(isscalar(v) && isnumeric(v) && isfinite(v)), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v + 0), '\.?0+$', ''); else, s = sprintf(['%.' num2str(prec) 'f'], v + 0); end
if strcmp(s, '-0') || isempty(s), s = '0'; end
end

function b = util_presetRange(peak)                           % 50-dB window under the next multiple of 5 above the peak
if ~isfinite(peak), b = [-40 10]; return; end, hi = 5*ceil(peak/5); b = min(max([hi - 50, hi], -250), 100);
end