classdef APAT_v3_M8_3 < matlab.apps.AppBase %1805-lines %ISSUES:  %1. Load Error: "Unrecognized method, property, or field 'DataTipTemplate' for class 'matlab.graphics.primitive.Surface'. (APAT_v3_M8_3.renderFull)" >> Added Temp DataTips as temporary fix  %2. HPBW region highlighting/overlay not working!  %3. 3D Plots (Spherical & Polar) not-working/not-showing!  %4. The DataTip right-click context menu not showing in 3D Surface Plot, thus not able to delete manually created/labeled DataTips after creating them  %5. The Range Sliders not rendered/shown properly (by-default/on-load thy show full/allowed range! It only should show 50dB dynamic range from ceiling (next rounded 5 to the Total Gain POB))  %6. For Conical Coverage, the Cone coordinates are not changing/syncing when switching the preset orientation from the Orientation drop-down! Also, it not showing the Orientation on the Coverage Tab Status Area (The Orientation should show on status bar as soon as the user enable/select Conical coverage (to show the Auto detected orientation), and keep syncing/updates if the user change the orientation drop-down)!  %7. On Coverage, When Clearing the DataTips or Resetting, it doesn't clear the projection lines!  %8. On Coverage Query, it doesn't return/place the DataTip at the exact requested/queried value (it snaps to nearest data-point! whereas the projection lines are traced properly at the requested location!)
% APAT v3 Milestone 8 — Antenna Pattern Analyzer Tool.
%
% M8 keeps every M7 widget, feature and input format, but rebuilds the program
% underneath the UI around a small number of single-owner objects:
%
%   FILE ─► io_read ─► Source ─► pat_build ─► Pattern ─► geo_build ─► Geometry
%                                   │ (optional pat_resample)              │
%                                   └────────────► pat_derive(Pattern,Geometry,Params) ─► Derived
%   app.Pats(k) = {Name, Path, Source, Pattern, Geometry, Derived, Params}   ◄── one entry per loaded file
%   Main tab reads Pats(app.Main); a coverage tree node stores k. Nothing is copied or synchronised.
%
%   View = readConfig()   the only place widget values are read
%   Map  = geo_displayMap the only place the display convention (elevation θ / signed φ) exists
%   on(scope) ─► update(level) ─► apply*/render*   the only places widgets/graphics are written
%
% Conventions (one constant each, shown in Metadata): uniform grids only, spatial-isolation
% peak policy, IEEE circular basis under e^{+jωt}, signed AR with a -100 dB linear floor,
% coverage = 100·Ω_R(G > T)/Ω_R, physical metrics on total gain only.

    properties (GetAccess = public, SetAccess = private)
        isClosing logical = false
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
        Pats = struct('Name', {}, 'Path', {}, 'Source', {}, 'Pattern', {}, 'Geometry', {}, 'Derived', {}, 'Params', {})
        Main double = 0                       % index into Pats shown on the Main tab (0 = none)
        View struct = struct()                % last readConfig() result
        Map struct = struct()                 % last geo_displayMap() result
        Gfx struct = struct()                 % retained graphics handles, one field per view
        Dirty struct = struct('Full', true(1, 5), 'Out', false, 'In', false)
        Range struct = struct('Auto', struct('full', true, 'cut', true, 'cov', true))
        OutMask logical = logical.empty       % Results-table column filter (one flag per derived column)
        Status struct = struct('main', 'Ready 🚀', 'cov', 'Ready 🚀')
        StatusTimer = []
        OpDialog = []
        Busy logical = false
        Perf struct = struct()
        PerfTimer = []
        CovRunID double = 0
        Defaults cell = {}                    % startup parameter values (Reset Params)
        Styles cell = {}
        Menu3D = []
    end

    properties (Constant, Access = private)
        Const = struct( ...
            'ReleaseName', 'APAT v3 Milestone 8', 'Version', '3.0-M8', ...
            'PeakExcessDB', 6, ...           % spatial-isolation spike policy (met_peak)
            'ARFloorDB', -100, 'ARCapDB', 250, ... % signed axial ratio display floor/cap (pol_signedAR)
            'ConeDeg', 45, ...               % boresight-detection cone half angle
            'DistanceFloorM', 1e-12, ...
            'LinkBudgetRequiresDBi', true, ... % EIRP/PFD/E_RMS/efficiency only for absolute (dBi) sources
            'Axes', struct('labels', {{'+Z', '-Z', '+X', '-X', '+Y', '-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270]), ...
            'FullKeys', ["Ctr", "Cir", "Sph", "Pol", "Rect"], ...
            'Cols', {{ ... % name, label, kind, shown-in-Results-by-default
                'E_Total_dB', 'Total Gain', 'gain', true; 'AR_dB', 'Axial Ratio', 'ar', true; ...
                'E_RCP_dB', 'RHCP Gain', 'gain', true; 'E_LCP_dB', 'LHCP Gain', 'gain', true; ...
                'PLF_dB', 'PLF', 'plf', true; 'Gain_PolCorrected_dB', 'Polarized Gain', 'gain', true; ...
                'E_TH_dB', 'Etheta Gain', 'gain', false; 'E_PH_dB', 'Ephi Gain', 'gain', false; ...
                'E_TH_Phase', 'Etheta Phase', 'phase', false; 'E_PH_Phase', 'Ephi Phase', 'phase', false; ...
                'E_RCP_Phase', 'RHCP Phase', 'phase', false; 'E_LCP_Phase', 'LHCP Phase', 'phase', false; ...
                'EIRP_dBW', 'EIRP', 'link', false; 'PFD_Wm2', 'PFD', 'link', false; 'E_RMS_Vm', 'E RMS', 'link', false}}, ...
            'Components', ["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "AR_dB", "Gain_PolCorrected_dB"])
    end

    %% ================================================================ orchestration
    % SOURCE ─► PATTERN ─► GEOMETRY ─► DERIVED   (stored in Pats(k); each level rebuilds the ones below)
    %                                     ├─► PLOTS / CUT / TABLES / METADATA (+Map)
    %                                     └─► COVERAGE job = curve {T, cov} (tree node)
    % VIEW ─► MAP ─► column permutation / axes / ticks / cut-value domain (touches nothing above)
    methods (Access = private)

        function on(app, scope, src)
            %ON Every callback is one call to ON. It owns the busy flag, try/catch, cancellation,
            % the performance record and the single drawnow. Callbacks never contain logic.
            if app.Busy || app.isClosing, return; end
            if nargin < 3, src = []; end
            app.Busy = true; guard = onCleanup(@() app.endAction()); %#ok<NASGU>
            app.Perf = struct('AppVersion', string(class(app)), 'Operation', string(scope), 'Stages', {cell(0, 2)}, 'TotalSeconds', 0);
            app.PerfTimer = tic; total = tic;
            try
                app.dispatch(string(scope), src);
                drawnow limitrate
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.setStatus(app.Single_StatusBar, 'Operation cancelled by user.', true);
                else, app.showError(ME, sprintf('%s error', scope)); end
            end
            app.Perf.TotalSeconds = toc(total);
            app.Perf.Stages = cell2table(app.Perf.Stages, 'VariableNames', {'Stage', 'Seconds'});
            assignin('base', matlab.lang.makeValidName("Perf_" + string(class(app))), app.Perf);
        end

        function endAction(app)
            app.Busy = false;
            if ~isempty(app.OpDialog) && isvalid(app.OpDialog), close(app.OpDialog); end
            app.OpDialog = [];
        end

        function perf(app, stage)
            app.Perf.Stages(end + 1, :) = {string(stage), toc(app.PerfTimer)}; app.PerfTimer = tic;
        end

        function checkCancelled(app)
            if ~isempty(app.OpDialog) && isvalid(app.OpDialog) && app.OpDialog.CancelRequested
                error('APAT:Cancelled', 'Operation cancelled by user.');
            end
        end

        function dispatch(app, scope, src)
            filters = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.csv;*.dat;*.txt', 'Pattern/Gain Files'};
            switch scope
                case "load",        app.loadMain(app.pickFile(app.Single_EditField_Path.Value, filters));
                case "format",      if app.Main > 0 && app.Pats(app.Main).Source.Meta.IsText, app.loadMain(app.Pats(app.Main).Path); end
                case {"freq", "step"}, app.update("pattern");
                case "params",      app.update("derived");
                case "resetParams", app.applyParams(app.Defaults); app.update("derived");
                case "plane",       app.applyPlane(); app.update("cut");
                case {"component", "span"}, app.update("view");
                case "cut",         app.update("cut");
                case "view3d",      app.applyView3D();
                case "overlay",     app.refreshView(); app.renderOverlay();
                case "pob",         app.refreshView(); app.renderCut(); app.Dirty.Full(:) = true; app.renderFull();
                case "hpbw",        app.refreshView(); app.renderCut();
                case "fullTab",     app.refreshView(); app.renderFull(); app.renderOverlay();
                case "range",       app.onRange(src);
                case "filter",      app.applyFilter();
                case "dataTab",     app.applyTables();
                case "exportResults", app.exportResults();
                case "exportUAN",   app.exportUAN();
                case "exportCut",   app.exportCut();
                case "toCoverage",  app.covEnsureNode(app.Main); app.TabGroup.SelectedTab = app.Tab2_Coverage; app.covSelect();
                case "cov:load",    app.covLoad(app.pickFile(app.Cov_EditField_filePath.Value, filters));
                case "cov:format",  k = app.covTargetIndex(); if k > 0 && app.Pats(k).Source.Meta.IsText, app.covLoad(app.Pats(k).Path); end
                case "cov:compute", app.covCompute();
                case "cov:reset",   app.covReset();
                case "cov:clear",   delete(findall(app.Cov_Axes, 'Type', 'datatip')); delete(findobj(app.Cov_Axes, '-regexp', 'Tag', '^APAT_Query'));
                case "cov:export",  app.covExport();
                case {"cov:type", "cov:orient", "cov:selected"}, app.covSelect();
                case "cov:component", app.covSelect();
                case "cov:checked", app.covRefresh();
                case "cov:thresh",  app.Range.Auto.cov = false;
                case "cov:queryCov", app.covQuery("cov");
                case "cov:queryThr", app.covQuery("thr");
            end
        end

        function refreshView(app)
            %REFRESHVIEW Light scopes (tab, checkbox) re-read the view without touching data or map.
            if app.Main > 0, cfg = app.readConfig(); cfg.CutValue = app.View.CutValue; app.View = cfg; end
        end

        function update(app, level)
            %UPDATE Build-then-commit. Levels: pattern → derived → view → cut. Every stage computes into
            % locals; the registry entry is assigned once. Cancel or error leaves the previous state intact.
            if app.Main == 0, return; end
            L = find(["pattern", "derived", "view", "cut"] == string(level), 1);
            prev = app.View; cfg = app.readConfig(); entry = app.Pats(app.Main);
            if L <= 2
                entry = app.buildEntry(entry, cfg, L); app.Pats(app.Main) = entry;   % commit
                app.applyChoices(entry, L == 1); app.checkCancelled();
                if app.Range.Auto.full, app.applyRange("full", util_presetRange(entry.Derived.Peak.value)); end
                if app.Range.Auto.cut,  app.applyRange("cut",  util_presetRange(entry.Derived.Peak.value)); end
                if L == 1, app.applyPlane(); end
                cfg = app.readConfig(); prev = cfg;                  % choices just written are authoritative
            end
            app.applyCutDomain(prev, cfg, entry); cfg.CutValue = app.Single_DropDown_cutValue.Value;
            app.View = cfg; app.Map = geo_displayMap(entry.Pattern, entry.Geometry, cfg);
            if L <= 3, app.Dirty.Full(:) = true; app.Dirty.Out = true; app.renderFull(); end
            app.renderCut(); app.renderOverlay(); app.perf("Render");
            if L <= 3, app.applyMetadata(); app.applyTables(); app.applyVisibility(); app.applyStatus(); app.perf("Tables"); end
        end

        function entry = buildEntry(app, entry, cfg, level)
            %BUILDENTRY Pattern/Geometry (level 1) and Derived (level ≤ 2) for one registry entry.
            if level <= 1
                P = pat_build(entry.Source, cfg.FreqIndex);
                if cfg.StepOne && any(abs([P.dTheta, P.dPhi] - 1) > 1e-9), P = pat_resample(P, 1); end
                entry.Pattern = P; entry.Geometry = geo_build(P); app.perf("Build pattern");
            end
            entry.Params = cfg.Params;
            entry.Derived = pat_derive(entry.Pattern, entry.Geometry, cfg.Params, app.Const); app.perf("Derive");
        end

        %% ------------------------------------------------------------ readers (the only widget readers)
        function cfg = readConfig(app)
            cfg = struct();
            cfg.Component = string(app.Single_DropDown_Component.Value);
            cfg.CutType   = string(app.Single_DropDown_cutType.Value);   % "Phi": φ varies at fixed θ. "Theta": θ varies at fixed φ.
            cfg.CutValue  = app.Single_DropDown_cutValue.Value;           % display convention (see applyCutDomain)
            cfg.SignedPhi = strcmp(app.Single_Switch_AngularSpan.Value, '-180° to 180°');
            cfg.Elevation = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°');
            cfg.Basis     = string(app.CutFieldBasisDropDown.Value);
            cfg.Traces    = [app.CheckBox_Et.Value, app.CheckBox_Er.Value, app.CheckBox_El.Value];
            cfg.View3D    = string(app.Single_DropDown_3DView.Value);
            cfg.Overlay   = app.Singel_CheckBox_overlayCut.Value;
            cfg.POB       = app.Single_CheckBox_POB.Value;
            cfg.HPBW      = app.Button_HPBW.Value;
            cfg.HPBWBounds = app.Single_CheckBox_HPBWBounds.Value;
            cfg.CStep     = app.Single_Plot_Cstep.Value;
            cfg.FreqIndex = max([1, find(strcmp(app.Single_DropDown_FFD.Items, app.Single_DropDown_FFD.Value), 1)]);
            cfg.StepOne   = strcmp(app.Single_DropDown_step.Value, 'STEP: 1°');
            cfg.FullKey   = app.Const.FullKeys(app.Single_tabPlots.SelectedTab == app.fullTabs());
            cfg.Params    = app.readParams();
        end

        function p = readParams(app)
            p = struct('GainLoss_dB', app.Single_Spinner_Loss.Value, 'RxMode', string(app.Single_DropDown_RxPol.Value), ...
                'RxAR_dB', app.Single_Spinner_Rw.Value, 'Pt_dBW', app.Single_Spinner_Pt.Value, ...
                'R_m', max(app.Single_Spinner_R.Value, app.Const.DistanceFloorM));
            switch app.Single_DropDown_Pt.Value
                case 'dBm',   p.Pt_dBW = p.Pt_dBW - 30;
                case 'Watts', p.Pt_dBW = 10 * log10(max(p.Pt_dBW, eps));
            end
            if strcmp(app.Single_DropDown_R.Value, 'km'), p.R_m = 1000 * p.R_m; end
        end

        function tabs = fullTabs(app)
            tabs = [app.Single_tabContour, app.Single_tabCircular, app.Single_tab3DSpherical, app.Single_tab3DPolar, app.Single_tab3DRect];
        end

        function [sliders, mins, maxs] = rangeWidgets(app, group)
            switch group
                case "full"
                    sliders = [app.Range_Ctr, app.Range_Cir, app.Range_3dSph, app.Range_3dPol, app.Range_3dRect];
                    mins = [app.Range_Ctr_Min, app.Range_Cir_Min, app.Range_3dSph_Min, app.Range_3dPol_Min, app.Range_3dRect_Min, app.Single_Plot_Cmin];
                    maxs = [app.Range_Ctr_Max, app.Range_Cir_Max, app.Range_3dSph_Max, app.Range_3dPol_Max, app.Range_3dRect_Max, app.Single_Plot_Cmax];
                case "cut",  sliders = app.Range_Cut; mins = app.Range_Cut_Min; maxs = app.Range_Cut_Max;
                otherwise,   sliders = app.Cov_Spinner_XRange; mins = app.Cov_Spinner_XMin; maxs = app.Cov_Spinner_XMax;
            end
        end

        %% ------------------------------------------------------------ apply* (the only widget writers)
        function applyParams(app, p)
            [app.Single_Spinner_Loss.Value, app.Single_DropDown_RxPol.Value, app.Single_Spinner_Rw.Value, app.Single_Spinner_Pt.Value, ...
                app.Single_DropDown_Pt.Value, app.Single_Spinner_R.Value, app.Single_DropDown_R.Value] = deal(p{:});
        end

        function applyChoices(app, entry, newPattern)
            %APPLYCHOICES Component / step / output-filter items for one derived entry.
            D = entry.Derived; P = entry.Pattern;
            dd = app.Single_DropDown_Component; prev = string(dd.Value);
            sel = D.Names; if ~P.IsGainOnly, sel = D.Names(ismember(D.Names, app.Const.Components)); end
            [dd.Items, dd.ItemsData] = deal(cellstr(D.Labels(ismember(D.Names, sel))), cellstr(sel));
            if ~any(sel == prev), dd.Value = char(sel(1)); end
            native = P.Native; nonCanonical = any(abs(native - 1) > 1e-9);
            items = {sprintf('STEP: %s°', util_fmtNumber(native(1)))}; if nonCanonical, items{end + 1} = 'STEP: 1°'; end
            sd = app.Single_DropDown_step; prevStep = sd.Value; sd.Items = items;
            if ~any(strcmp(items, prevStep)), sd.Value = items{1}; end
            set(sd, 'Visible', nonCanonical, 'Enable', nonCanonical);
            od = app.Single_DropDown_output;
            [od.Items, od.ItemsData] = deal([{'Select Output:'}, cellstr(D.Labels)], num2cell(0:numel(D.Names)));
            if newPattern || numel(app.OutMask) ~= numel(D.Names), app.OutMask = D.Shown; end
            od.Value = 0; app.applyFilterStyle();
        end

        function applyPlane(app)
            %APPLYPLANE Cut controls follow the E/H switch (principal planes from Derived).
            if app.Main == 0, return; end
            D = app.Pats(app.Main).Derived; cfg = app.readConfig();
            plane = D.Planes.H; if strcmp(app.Single_Switch_EHplane.Value, 'E-Plane cut'), plane = D.Planes.E; end
            app.Single_DropDown_cutType.Value = char(plane.type); cfg.CutType = plane.type;
            canon = plane.value;
            if plane.type == "Phi", shown = canon; if cfg.Elevation, shown = 90 - canon; end
            else, shown = canon; if cfg.SignedPhi && canon >= 180, shown = canon - 360; end
            end
            app.applyCutDomain(cfg, cfg, app.Pats(app.Main));
            app.Single_DropDown_cutValue.Value = shown;
            if isfield(app.View, 'CutType'), app.View.CutType = plane.type; app.View.CutValue = shown; end
        end

        function applyCutDomain(app, prev, cfg, entry)
            %APPLYCUTDOMAIN Cut-value spinner limits/step follow the display convention; the value is
            % carried across a convention change through its canonical angle. Trace labels follow the basis.
            sp = app.Single_DropDown_cutValue; P = entry.Pattern;
            canon = util_cutCanonical(prev, sp.Value);
            if isfield(prev, 'CutType') && prev.CutType ~= cfg.CutType, canon = 0; end
            if cfg.CutType == "Phi"
                lim = [0 180]; shown = canon; if cfg.Elevation, lim = [-90 90]; shown = 90 - canon; end
                step = P.dTheta;
            else
                lim = [0 360]; shown = canon; if cfg.SignedPhi, lim = [-180 180]; if shown >= 180, shown = shown - 360; end, end
                step = P.dPhi;
            end
            sp.Limits = lim; sp.Step = max(step, 0.001); sp.Value = min(max(shown, lim(1)), lim(2));
            pair = entry.Derived.Pol.Pairs.(cfg.Basis);
            [app.CheckBox_Et.Text, app.CheckBox_Er.Text, app.CheckBox_El.Text] = deal(char(app.compLabel(cfg.Component)), char(pair(1)), char(pair(2)));
        end

        function applyRange(app, group, limits)
            %APPLYRANGE One descriptor-driven writer for every slider/spinner group.
            limits = sort(double(limits(:).')); limits = min(max(limits, -250), 100);
            if diff(limits) <= 0, limits(2) = min(limits(1) + 1, 100); limits(1) = limits(2) - 1; end
            [sliders, mins, maxs] = app.rangeWidgets(group);
            set(sliders, 'Value', limits); set(mins, 'Value', limits(1)); set(maxs, 'Value', limits(2));
            app.Range.(group) = limits;
            if group == "cov", app.Cov_Axes.XLim = limits; end
        end

        function onRange(app, src)
            %ONRANGE A user edit of any range widget: read the edited pair, apply to its group, redraw.
            app.refreshView();
            for group = ["full", "cut", "cov"]
                [sliders, mins, maxs] = app.rangeWidgets(group);
                if any(src == [sliders, mins, maxs, app.Single_Button_Clim, app.Single_Plot_Cstep]), break; end
            end
            if any(src == sliders), limits = src.Value;
            elseif src == app.Single_Plot_Cstep, limits = app.Range.(group);
            else
                idx = mod(find(src == [mins, maxs], 1) - 1, numel(mins)) + 1; if src == app.Single_Button_Clim, idx = numel(mins); end
                limits = [mins(idx).Value, maxs(idx).Value];
            end
            app.Range.Auto.(group) = false; app.applyRange(group, limits);
            switch group
                case "full", app.Dirty.Full(:) = true; app.renderFull();
                case "cut",  app.renderCut();
            end
        end

        function applyFilter(app)
            od = app.Single_DropDown_output;
            if od.Value > 0, app.OutMask(od.Value) = ~app.OutMask(od.Value); od.Value = 0; end
            app.applyFilterStyle(); app.Dirty.Out = true; app.applyTables();
        end

        function applyFilterStyle(app)
            od = app.Single_DropDown_output; od.Items = regexprep(od.Items, '^✓ ?', ''); removeStyle(od);
            on = find(app.OutMask) + 1; od.Items(on) = append('✓ ', od.Items(on));
            addStyle(od, app.Styles{1}, 'Item', on); addStyle(od, app.Styles{2}, 'Item', find([true, ~app.OutMask]));
        end

        function applyVisibility(app)
            entry = app.Pats(app.Main); field = ~entry.Pattern.IsGainOnly; link = field && (~app.Const.LinkBudgetRequiresDBi || entry.Source.Meta.Unit == "dBi");
            set([app.Single_Panel_Rect, app.Single_Export_Output, app.Single_Panel_fullPattern, app.Single_Panel_plotControl, ...
                app.Single_Button_Coverage, app.Single_tabData, app.Single_DropDown_output, app.Single_Table_DataOut, app.Single_Table_DataIn, ...
                app.LossindBLabel, app.Single_Spinner_Loss], 'Visible', 'on');
            set([app.Single_Export_UAN, app.Single_gridEcut, app.CheckBox_Er, app.CheckBox_El, app.CutFieldBasisDropDown, ...
                app.RxPolLabel, app.Single_DropDown_RxPol, app.IncidentWaveARRwPLFLabel, app.Single_Spinner_Rw], 'Visible', field);
            set([app.TransmitPowerLabel, app.Single_Spinner_Pt, app.Single_DropDown_Pt, app.DistanceLabel, app.Single_Spinner_R, app.Single_DropDown_R], 'Visible', link);
            set([app.TextFormatLabel, app.Single_DropDown_TextFormat], 'Visible', entry.Source.Meta.IsText);
            multi = numel(entry.Source.Blocks) > 1;
            set([app.Single_DropDown_FFD, app.FFDFreqDropDownLabel], 'Visible', multi, 'Enable', multi);
        end

        function applyStatus(app)
            entry = app.Pats(app.Main); D = entry.Derived; K = D.Peak;
            txt = sprintf('Pattern: %s | POB %s %s ( &theta;=%s&deg;, &phi;=%s&deg; )', entry.Name, util_fmtNumber(K.value, 2), ...
                entry.Source.Meta.UnitLabel, util_fmtNumber(K.theta), util_fmtNumber(K.phi));
            if K.wasAdjusted, txt = sprintf('%s | raw max %s dB isolated at ( &theta;=%s&deg;, &phi;=%s&deg; )', txt, util_fmtNumber(K.rawValue, 2), util_fmtNumber(K.rawTheta), util_fmtNumber(K.rawPhi)); end
            if D.Pol.Label ~= "n/a", txt = sprintf('%s | Polarization %s', txt, D.Pol.Label); end
            app.setStatus(app.Single_StatusBar, txt, false);
        end

        function applyMetadata(app)
            entry = app.Pats(app.Main); P = entry.Pattern; G = entry.Geometry; D = entry.Derived; M = entry.Source.Meta; f = @util_fmtNumber;
            rows = {'Source format', char(M.Format); 'File', entry.Name; 'Unit', char(M.UnitLabel); ...
                'Samples', sprintf('%d samples (θ: %d × φ: %d)', numel(P.Theta) * numel(P.Phi), numel(P.Theta), numel(P.Phi)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', f(P.Theta(1)), f(P.Theta(end)), f(P.dTheta)); ...
                'φ range / step', sprintf('[%s°, %s°] / %s° (%s)', f(P.Phi(1)), f(P.Phi(end)), f(P.dPhi), util_pick(G.PhiPeriodic, 'periodic', 'open')); ...
                'Native step', sprintf('%s° × %s°', f(P.Native(1)), f(P.Native(2))); ...
                'Sphere coverage', sprintf('Ω = %s sr (%s)', f(G.Omega, 3), util_pick(G.IsFullSphere, 'full sphere', 'partial sphere'))};
            if isfinite(P.Freq), rows(end + 1, :) = {'Frequency', sprintf('%.4g GHz', P.Freq / 1e9)}; end
            if ~P.IsGainOnly
                rows = [rows; {'Polarization', char(D.Pol.Label); 'Cut Co-pol / Cross-pol', char(strjoin(D.Pol.Pairs.(app.CutFieldBasisDropDown.Value), ' / ')); ...
                    'Circular basis', 'E_R = (Eθ + jEφ)/√2, E_L = (Eθ − jEφ)/√2 (IEEE, e^{+jωt})'; ...
                    'Parameters', sprintf('Loss %s dB | Rx %s | Rw %s dB | Pt %s dBW | R %s m', f(entry.Params.GainLoss_dB), entry.Params.RxMode, f(entry.Params.RxAR_dB), f(entry.Params.Pt_dBW), f(entry.Params.R_m))}];
            end
            K = D.Peak; mt = D.Metrics;
            rows = [rows; {'Peak gain (POB)', sprintf('%s %s', f(K.value), M.UnitLabel); 'POB direction [θ, φ]', sprintf('[%s°, %s°]', f(K.theta), f(K.phi)); ...
                'Peak policy', sprintf('spatial isolation, excess > %g dB (%d spike sample(s))', app.Const.PeakExcessDB, K.spikeCount); ...
                'Peak adjusted', util_pick(K.wasAdjusted, sprintf('yes — raw max %s dB at [%s°, %s°]', f(K.rawValue), f(K.rawTheta), f(K.rawPhi)), 'no'); ...
                'Boresight axis', app.Const.Axes.labels{D.Boresight}; ...
                'HPBW E-plane', sprintf('%s°', f(mt.HPBW_EPlane_deg)); 'HPBW H-plane', sprintf('%s°', f(mt.HPBW_HPlane_deg)); ...
                'Front-to-back', sprintf('%s dB', f(mt.FrontBack_dB)); 'Peak directivity', sprintf('%s dBi', f(mt.PeakDirectivity_dB)); ...
                'Radiation efficiency', sprintf('%s%%', f(mt.Efficiency_pct)); 'AR at peak', sprintf('%s dB', f(mt.AxialRatioAtPeak_dB))}];
            for n = 1:numel(P.Notes), rows(end + 1, :) = {sprintf('Note %d', n), char(P.Notes(n))}; end %#ok<AGROW>
            app.Single_Table_metadata.Data = rows;
        end

        function applyTables(app)
            %APPLYTABLES Lazy: a 65k-row uitable is filled only when its tab is visible.
            if app.Main == 0, return; end
            entry = app.Pats(app.Main); selected = app.Single_tabData.SelectedTab;
            if app.Dirty.Out && selected == app.Single_tabDataOut
                app.Single_Table_DataOut.Data = app.resultsTable(app.OutMask); app.Dirty.Out = false;
            end
            if app.Dirty.In && selected == app.Single_tabDataIn
                app.Single_Table_DataIn.Data = entry.Source.Raw; app.Single_Table_DataIn.ColumnName = entry.Source.Raw.Properties.VariableNames; app.Dirty.In = false;
            end
        end

        function T = resultsTable(app, mask)
            %RESULTSTABLE Long table in the display convention (no duplicated seam column).
            entry = app.Pats(app.Main); D = entry.Derived; M = app.Map;
            cols = M.ColIdx(1:end - entry.Geometry.PhiPeriodic);
            [PH, TH] = meshgrid(M.PhiAxis(1:numel(cols)), M.ThetaAxis);
            T = table(TH(:), PH(:), 'VariableNames', {'Theta', 'Phi'});
            for n = find(mask(:).')
                C = D.Cols.(D.Names(n)); C = C(:, cols); T.(D.Names(n)) = C(:);
            end
        end

        function labels = compLabel(app, components)
            D = app.Pats(app.Main).Derived; labels = string(components);
            [tf, loc] = ismember(labels, D.Names); labels(tf) = D.Labels(loc(tf));
        end

        %% ------------------------------------------------------------ files
        function fp = pickFile(app, current, filters)
            fp = strtrim(char(current));
            if ~isempty(fp) && isfile(fp) && ~(app.Main > 0 && strcmp(fp, app.Pats(app.Main).Path)), return; end
            [f, p] = uigetfile(filters, 'Select an antenna pattern file');
            if isequal(f, 0), fp = ''; else, fp = fullfile(p, f); end
        end

        function loadMain(app, fp)
            if isempty(fp), return; end
            app.OpDialog = uiprogressdlg(app.UIFigure, 'Title', 'Loading Data', 'Message', 'Reading file...', 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            drawnow;
            S = io_read(fp, app.Single_DropDown_TextFormat.Value); app.perf("Read file"); app.checkCancelled();
            if S.Meta.IsCoverage
                app.TabGroup.SelectedTab = app.Tab2_Coverage; app.Cov_EditField_filePath.Value = fp; app.covLoadResults(fp, S.Raw); return
            end
            app.Single_EditField_Path.Value = fp;
            k = app.registerSource(S, fp); app.Main = k;
            items = compose('Pattern %d: %.4g GHz', (1:numel(S.Blocks)).', S.Freqs(:) / 1e9); items(isnan(S.Freqs(:))) = compose('Pattern %d', find(isnan(S.Freqs(:))));
            [app.Single_DropDown_FFD.Items, app.Single_DropDown_FFD.Value] = deal(cellstr(items), char(items(1)));
            app.Range.Auto = struct('full', true, 'cut', true, 'cov', app.Range.Auto.cov); app.Dirty.In = true;
            app.update("pattern");
            app.covSyncNode(k);
        end

        function k = registerSource(app, S, fp)
            %REGISTERSOURCE One registry entry per path; reloading the same path replaces it in place.
            [~, name, ext] = fileparts(fp);
            k = find(strcmp({app.Pats.Path}, fp), 1); if isempty(k), k = numel(app.Pats) + 1; end
            app.Pats(k).Name = [name, ext]; app.Pats(k).Path = fp; app.Pats(k).Source = S;
            app.Pats(k).Pattern = []; app.Pats(k).Geometry = []; app.Pats(k).Derived = []; app.Pats(k).Params = [];
        end

        %% ------------------------------------------------------------ status / errors / lifecycle
        function setStatus(app, label, msg, transient)
            if app.isClosing || ~isgraphics(label), return; end
            stop(app.StatusTimer); label.Text = char(msg);
            if ~transient, app.Status.(label.Tag) = char(msg); return; end
            app.StatusTimer.TimerFcn = @(~, ~) set(label, 'Text', app.Status.(label.Tag));
            start(app.StatusTimer);
        end

        function showError(app, ME, titleText)
            if app.isClosing, return; end
            uialert(app.UIFigure, sprintf('%s\n(%s line %d)', ME.message, ME.stack(1).name, ME.stack(1).line), titleText, 'Icon','error');
            app.setStatus(app.Single_StatusBar, sprintf('Error: %s', ME.message), true);
        end

        function closeRequest(app, ~)
            app.isClosing = true; delete(app);
        end
    end

    methods (Access = public)
        function app = APAT_v3_M8_3
            app.createComponents();
            registerApp(app, app.UIFigure);
            app.StatusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3);
            app.Styles = {uistyle('FontWeight', 'bold', 'FontColor', 'black', 'BackgroundColor', [0.8 1 0.8]), uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9])};
            app.Defaults = {app.Single_Spinner_Loss.Value, app.Single_DropDown_RxPol.Value, app.Single_Spinner_Rw.Value, app.Single_Spinner_Pt.Value, ...
                app.Single_DropDown_Pt.Value, app.Single_Spinner_R.Value, app.Single_DropDown_R.Value};
            app.Range.full = [-250 100]; app.Range.cut = [-250 100]; app.Range.cov = [-40 10];
            if nargout == 0, clear app; end
        end

        function delete(app)
            app.isClosing = true;
            if ~isempty(app.StatusTimer) && isvalid(app.StatusTimer), stop(app.StatusTimer); delete(app.StatusTimer); end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end
    end

    %% ================================================================ renderers
    % Every renderer reads Pats(Main), View and Map only, owns its handles in Gfx and updates
    % XData/YData/ZData/CData in place when the grid size is unchanged. Only the visible tab is drawn.
    methods (Access = private)

        function ax = axesFor(app, key)
            switch key
                case "Ctr",  ax = app.Single_Axes_Ctr;
                case "Cir",  ax = app.Single_paxPattern;
                case "Sph",  ax = app.Single_Axes_3dSph;
                case "Pol",  ax = app.Single_Axes_3dPol;
                otherwise,   ax = app.Single_Axes_3dRect;
            end
        end

        function renderFull(app)
            if app.Main == 0, return; end
            key = app.View.FullKey; slot = find(app.Const.FullKeys == key, 1);
            if ~app.Dirty.Full(slot), return; end
            entry = app.Pats(app.Main); P = entry.Pattern; D = entry.Derived; M = app.Map; V = app.View;
            C = D.Cols.(V.Component)(:, M.ColIdx); label = app.compLabel(V.Component);
            [lim, cmap] = util_theme(D.Kinds(D.Names == V.Component), app.Range.full);
            [PH, TH] = meshgrid(M.PhiAxis, M.ThetaAxis);                 % display axes
            [PHp, THp] = meshgrid(P.Phi(M.ColIdx), P.Theta);             % physical angles
            ax = app.axesFor(key); K = D.Peak; pob = [K.theta, K.phi];
            switch key
                case "Ctr"
                    h = app.surfaceOf(key, ax, PH, TH, zeros(size(C)), C);
                    set(ax, 'XLim', [M.PhiAxis(1), M.PhiAxis(end)], 'YLim', sort(M.ThetaAxis([1, end])), 'YDir', M.ThetaDir, ...
                        'XTick', util_span(M.PhiAxis, 30), 'YTick', util_span(M.ThetaAxis, 15));
                    ylabel(ax, M.ThetaLabel + " (degree)"); daspect(ax, [1 1 1]);
                    mark = [util_display(pob, M), 0];
                case "Cir"
                    h = app.surfaceOf(key, ax, deg2rad(PHp), THp, zeros(size(C)), C);
                    set(ax, 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', util_pick(V.Elevation, 90 - (0:30:180), 0:30:180)), ...
                        'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', util_pick(V.SignedPhi, mod((0:30:330) + 180, 360) - 180, 0:30:330)));
                    title(ax, sprintf('%s  |  r=θ, angle=φ', label), 'Interpreter', 'none', 'FontSize', 9);
                    mark = [deg2rad(pob(2)), pob(1), 0];
                case {"Sph", "Pol"}
                    r = ones(size(C));
                    if key == "Pol"
                        r = max(C - lim(1), 0) / max(diff(lim), eps); app.Gfx.PolNorm = max(max(r, [], 'all', 'omitnan'), eps); r = r / app.Gfx.PolNorm;
                    end
                    h = app.surfaceOf(key, ax, r .* sind(THp) .* cosd(PHp), r .* sind(THp) .* sind(PHp), r .* cosd(THp), C);
                    rp = 1; if key == "Pol", rp = max(K.value - lim(1), 0) / max(diff(lim), eps) / app.Gfx.PolNorm; end
                    mark = rp * 1.02 * [sind(pob(1)) * cosd(pob(2)), sind(pob(1)) * sind(pob(2)), cosd(pob(1))];
                    title(ax, sprintf('%s  |  θ: %s  |  φ: %s', label, app.Single_Switch_ThetaSpan.Value, app.Single_Switch_AngularSpan.Value), 'Interpreter', 'none');
                otherwise
                    h = app.surfaceOf(key, ax, PH, TH, C, C);
                    set(ax, 'XLim', [M.PhiAxis(1), M.PhiAxis(end)], 'YLim', sort(M.ThetaAxis([1, end])), 'YDir', M.ThetaDir, 'ZLim', lim, ...
                        'XTick', util_span(M.PhiAxis, 60), 'YTick', util_span(M.ThetaAxis, 30), 'ZTick', util_ticks(lim, V.CStep));
                    ylabel(ax, M.ThetaLabel + " (degree)"); zlabel(ax, label + " (dB)", 'Interpreter', 'none');
                    mark = [util_display(pob, M), K.value];
            end
            if key ~= "Cir" && key ~= "Sph" && key ~= "Pol", title(ax, label, 'Interpreter', 'none'); end
            clim(ax, lim); colormap(ax, cmap); app.Gfx.CB.(key).Ticks = util_ticks(lim, V.CStep);
            temporaryTip = datatip(h); delete(temporaryTip); % create dummy DataTip to avoid error!
            h.DataTipTemplate.DataTipRows = [dataTipTextRow('θ', THp, '%.4g°'), dataTipTextRow('φ', PHp, '%.4g°'), dataTipTextRow(char(label), C, '%.3f')];
            app.markPOB(key, ax, mark, K, label);
            app.Dirty.Full(slot) = false;
        end

        function h = surfaceOf(app, key, parent, X, Y, Z, C)
            %SURFACEOF Retained surface per view: in-place data update when the grid size is unchanged.
            if nargin < 7, C = Z; end
            h = []; if isfield(app.Gfx, key), h = app.Gfx.(key); end
            if ~isempty(h) && isgraphics(h) && isequal(size(h.CData), size(C))
                set(h, 'XData', X, 'YData', Y, 'ZData', Z, 'CData', C); return
            end
            if ~isempty(h) && isgraphics(h), delete(h); end
            h = surface(parent, X, Y, Z, C, 'EdgeColor', 'none', 'FaceColor', 'interp'); app.Gfx.(key) = h;
        end

        function markPOB(app, key, ax, xyz, K, label)
            %MARKPOB One retained POB marker + datatip per view; visibility follows the checkbox.
            name = "POB" + key; h = []; if isfield(app.Gfx, name), h = app.Gfx.(name); end
            if isempty(h) || ~isgraphics(h)
                if key == "Cir", h = polarplot(ax, xyz(1), xyz(2), 'o'); else, h = line(ax, xyz(1), xyz(2), xyz(3), 'LineStyle', 'none', 'Marker', 'o'); end
                set(h, 'MarkerSize', 6, 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'w', 'Clipping', 'off', 'HandleVisibility', 'off'); app.Gfx.(name) = h;
            elseif key == "Cir", set(h, 'ThetaData', xyz(1), 'RData', xyz(2));
            else, set(h, 'XData', xyz(1), 'YData', xyz(2), 'ZData', xyz(3));
            end
            temporaryTip = datatip(h); delete(temporaryTip); % create dummy DataTip to avoid error!
            h.DataTipTemplate.DataTipRows = [dataTipTextRow('POB', string(sprintf('%s dB', util_fmtNumber(K.value, 2)))); dataTipTextRow('θ', string(sprintf('%s°', util_fmtNumber(K.theta)))); ...
                dataTipTextRow('φ', string(sprintf('%s°', util_fmtNumber(K.phi)))); dataTipTextRow('Component', string(label))];
            delete(findall(h, 'Type', 'datatip')); h.Visible = app.View.POB;
            if app.View.POB, datatip(h, 'DataIndex', 1, 'FontSize', 9); end
        end

        function [names, slots] = cutTraces(app)
            %CUTTRACES Trace list: selected component (Et box), then co/cross pair of the chosen basis.
            D = app.Pats(app.Main).Derived; V = app.View; names = strings(1, 0); slots = [];
            if V.Traces(1) || app.Pats(app.Main).Pattern.IsGainOnly, names(end + 1) = V.Component; slots(end + 1) = 1; end
            if D.Kinds(D.Names == V.Component) == "gain" && ~app.Pats(app.Main).Pattern.IsGainOnly
                pair = D.Pol.Pairs.(V.Basis) + "_dB";
                for n = 1:2, if V.Traces(n + 1) && any(D.Names == pair(n)), names(end + 1) = pair(n); slots(end + 1) = n + 1; end, end %#ok<AGROW>
            end
            if isempty(names), names = V.Component; slots = 1; end
        end

        function renderCut(app)
            if app.Main == 0, return; end
            entry = app.Pats(app.Main); P = entry.Pattern; G = entry.Geometry; D = entry.Derived; V = app.View;
            if isfield(app.Gfx, 'Cut'), delete(app.Gfx.Cut(isgraphics(app.Gfx.Cut))); end
            [names, slots] = app.cutTraces();
            cut = geo_cut(P, G, V.CutType, util_cutCanonical(V, V.CutValue), V.SignedPhi);
            Y = zeros(numel(cut.angle), numel(names));
            for n = 1:numel(names), C = D.Cols.(names(n)); Y(:, n) = C(cut.idx); end
            lim = app.Range.cut; pax = app.Single_paxCut; rax = app.Single_AxesRect;
            hp = polarplot(pax, deg2rad(cut.angle), max(Y, lim(1)), 'LineWidth', 1.4);
            hr = plot(rax, cut.angle, Y, 'LineWidth', 1.4);
            colors = rax.ColorOrder(1 + mod(slots - 1, size(rax.ColorOrder, 1)), :);
            set(hp(:), {'Color'}, num2cell(colors, 2)); set(hr(:), {'Color'}, num2cell(colors, 2));
            for n = 1:numel(names)
                rows = [dataTipTextRow('Angle', cut.angle, '%.3g°'), dataTipTextRow(char(app.compLabel(names(n))), Y(:, n), '%.3g dB')];
                hp(n).DataTipTemplate.DataTipRows = rows; hr(n).DataTipTemplate.DataTipRows = rows;
            end
            fixedShown = cut.fixed; if V.CutType == "Phi" && V.Elevation, fixedShown = 90 - cut.fixed; elseif V.CutType == "Theta" && V.SignedPhi && cut.fixed >= 180, fixedShown = cut.fixed - 360; end
            titleText = sprintf('%s cut @ %s = %s°  |  %s', V.CutType, cut.symbol, util_fmtNumber(fixedShown), strjoin(app.compLabel(names), ', '));
            set(pax, 'ThetaDir', 'clockwise', 'ThetaZeroLocation', 'top', 'RLim', lim, 'RTick', lim(1):5:lim(2), 'ThetaTick', 0:30:330, ...
                'ThetaTickLabel', compose('%d°', util_pick(V.SignedPhi, mod((0:30:330) + 180, 360) - 180, 0:30:330)));
            set(rax, 'YLim', lim, 'XLim', cut.xlim, 'XTick', cut.xlim(1):30:cut.xlim(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, sprintf('%s (degree)', V.CutType)); title(pax, titleText, 'Interpreter', 'none'); title(rax, titleText, 'Interpreter', 'none');
            legend(rax, cellstr(app.compLabel(names)), 'Location', 'best', 'Interpreter', 'none');
            handles = [hp(:); hr(:)];
            [peak, at] = max(Y(:, 1), [], 'omitnan');
            if V.POB && isfinite(peak)
                m1 = polarplot(pax, deg2rad(cut.angle(at)), peak, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off');
                m2 = plot(rax, cut.angle(at), peak, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off');
                for m = [m1, m2]
                    temporaryTip = datatip(m); delete(temporaryTip); % create dummy DataTip to avoid error!
                    m.DataTipTemplate.DataTipRows = [dataTipTextRow('Cut max', string(sprintf('%s dB', util_fmtNumber(peak, 2)))); dataTipTextRow('Angle', string(sprintf('%s°', util_fmtNumber(cut.angle(at)))))];
                    datatip(m, 'DataIndex', 1, 'FontSize', 9);
                end
                handles = [handles; m1; m2];
            end
            app.Label_HPBW.Text = '';
            if V.HPBW
                [bw, lo, hi] = met_hpbw(cut.angle, Y(:, 1));
                if isfinite(bw)
                    bounds = util_wrap([lo, hi], V.SignedPhi);
                    app.Label_HPBW.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, bounds(1), bounds(2));
                    if V.HPBWBounds
                        for b = bounds
                            handles(end + 1) = polarplot(pax, deg2rad([b b]), lim, 'k--', 'LineWidth', 1, 'HandleVisibility', 'off'); %#ok<AGROW>
                            handles(end + 1) = xline(rax, b, 'k--', 'LineWidth', 1, 'HandleVisibility', 'off'); %#ok<AGROW>
                        end
                    end
                end
            end
            app.Gfx.Cut = handles;
        end

        function renderOverlay(app)
            %RENDEROVERLAY Cut trace drawn on the visible 3-D surface, sharing the surface's radius rule.
            if app.Main == 0, return; end
            entry = app.Pats(app.Main); P = entry.Pattern; V = app.View; D = entry.Derived;
            for key = ["Sph", "Pol"]
                name = "Overlay" + key; h = []; if isfield(app.Gfx, name), h = app.Gfx.(name); end
                show = V.Overlay && V.FullKey == key;
                if ~show, if ~isempty(h) && isgraphics(h), h.Visible = 'off'; end, continue, end
                cut = geo_cut(P, entry.Geometry, V.CutType, util_cutCanonical(V, V.CutValue), V.SignedPhi);
                [i, j] = ind2sub([numel(P.Theta), numel(P.Phi)], cut.idx); th = P.Theta(i); ph = P.Phi(j).';
                g = D.Cols.(V.Component)(cut.idx); lim = app.Range.full; r = 1.02 * ones(size(g));
                if key == "Pol" && isfield(app.Gfx, 'PolNorm'), r = 1.01 * max(g - lim(1), 0) / max(diff(lim), eps) / app.Gfx.PolNorm; end
                xyz = {r .* sind(th) .* cosd(ph), r .* sind(th) .* sind(ph), r .* cosd(th)};
                if isempty(h) || ~isgraphics(h), h = line(app.axesFor(key), xyz{:}, 'Color', 'k', 'LineWidth', 1.6, 'HandleVisibility', 'off'); app.Gfx.(name) = h;
                else, set(h, 'XData', xyz{1}, 'YData', xyz{2}, 'ZData', xyz{3}, 'Visible', 'on');
                end
            end
        end

        function applyView3D(app)
            views = struct('iso', [135 25], 'top', [0 90], 'bottom', [0 -90], 'right', [0 0], 'left', [180 0], 'front', [-90 0], 'back', [90 0]);
            v = views.(app.Single_DropDown_3DView.Value);
            for ax = [app.Single_Axes_3dSph, app.Single_Axes_3dPol], view(ax, v); end
            if strcmp(app.Single_DropDown_3DView.Value, 'iso'), v = [-35 35]; end
            view(app.Single_Axes_3dRect, v);
        end

        function initAxes(app)
            %INITAXES Created once: polar axes, colorbars, triads, context menu, 3-D formatting.
            app.Single_paxCut = polaraxes(app.Single_Grid_Polar); app.Single_paxCut.Layout.Row = [1 4]; app.Single_paxCut.Layout.Column = [2 3];
            app.Single_paxPattern = polaraxes(app.Single_gridCircular); app.Single_paxPattern.Layout.Row = [1 3]; app.Single_paxPattern.Layout.Column = 2;
            set([app.Single_paxCut, app.Single_paxPattern], 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'NextPlot', 'add');
            app.Menu3D = uicontextmenu(app.UIFigure); uimenu(app.Menu3D, 'Text', 'Reset 3D view', 'MenuSelectedFcn', @(~, ~) app.on("view3d"));
            colors = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            for ax = [app.Single_Axes_3dSph, app.Single_Axes_3dPol]
                hold(ax, 'on'); axis(ax, 'equal'); axis(ax, 'vis3d'); axis(ax, 'off'); ax.ContextMenu = app.Menu3D; ax.Clipping = 'off';
                for n = 1:3
                    d = 1.35 * double(1:3 == n);
                    quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors{n}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25, 'HandleVisibility', 'off');
                    text(ax, 1.12 * d(1), 1.12 * d(2), 1.12 * d(3), labels{n}, 'Color', colors{n}, 'FontWeight', 'bold');
                end
            end
            hold(app.Single_Axes_3dRect, 'on'); grid(app.Single_Axes_3dRect, 'on'); app.Single_Axes_3dRect.ContextMenu = app.Menu3D;
            hold(app.Single_Axes_Ctr, 'on'); hold(app.Single_AxesRect, 'on');
            for key = app.Const.FullKeys, app.Gfx.CB.(key) = colorbar(app.axesFor(key)); end
            app.applyView3D();
        end
    end

    %% ================================================================ coverage
    % The tree IS the registry: a pattern node stores k (index into Pats), a job node stores its
    % curve {T, cov} and its line. Nothing is copied from the Main tab and nothing is cached.
    methods (Access = private)

        function node = covNodeFor(app, k)
            node = [];
            for n = app.Cov_Tree.Children(:).'
                if isstruct(n.NodeData) && n.NodeData.kind == "pattern" && n.NodeData.k == k, node = n; return; end
            end
        end

        function node = covEnsureNode(app, k)
            node = app.covNodeFor(k);
            if isempty(node) && k > 0
                node = uitreenode(app.Cov_Tree, 'Text', ['📡 ' app.Pats(k).Name], 'NodeData', struct('kind', "pattern", 'k', k));
                app.Cov_Tree.SelectedNodes = node;
            end
        end

        function covSyncNode(app, k)
            node = app.covNodeFor(k);
            if ~isempty(node), node.Text = ['📡 ' app.Pats(k).Name]; app.covSelect(); end
        end

        function [k, node] = covTarget(app)
            %COVTARGET Pattern node owning the selection, else the Main pattern's node.
            node = []; sel = app.Cov_Tree.SelectedNodes;
            if ~isempty(sel), node = sel(1); end
            while isa(node, 'matlab.ui.container.TreeNode') && ~(isstruct(node.NodeData) && node.NodeData.kind == "pattern"), node = node.Parent; end
            if ~isa(node, 'matlab.ui.container.TreeNode'), node = app.covNodeFor(app.Main); end
            k = 0; if ~isempty(node), k = node.NodeData.k; end
        end

        function k = covTargetIndex(app), k = app.covTarget(); end

        function jobs = covJobs(app, roots)
            if nargin < 2, roots = app.Cov_Tree.Children; end
            jobs = matlab.ui.container.TreeNode.empty(0, 1);
            for n = roots(:).'
                if isstruct(n.NodeData) && n.NodeData.kind == "job", jobs(end + 1, 1) = n; %#ok<AGROW>
                else, jobs = [jobs; app.covJobs(n.Children)]; %#ok<AGROW>
                end
            end
        end

        function covLoad(app, fp)
            if isempty(fp), return; end
            S = io_read(fp, app.Cov_DropDown_TextFormat.Value); app.perf("Read file");
            app.Cov_EditField_filePath.Value = fp;
            if S.Meta.IsCoverage, app.covLoadResults(fp, S.Raw); return; end
            k = app.registerSource(S, fp);
            if k == app.Main
                app.update("pattern");
            else
                cfg = app.readConfig(); cfg.StepOne = false;
                app.Pats(k) = app.buildEntry(app.Pats(k), cfg, 1);
            end
            app.Cov_Tree.SelectedNodes = app.covEnsureNode(k); app.covSelect();
            app.setStatus(app.Cov_StatusBar, sprintf('Pattern <b>%s</b> added — ready to compute coverage.', app.Pats(k).Name), false);
        end

        function covLoadResults(app, fp, T)
            [~, name] = fileparts(fp);
            node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📄 ' name], 'NodeData', struct('kind', "results", 'name', name));
            thr = T{:, 1};
            for c = 2:width(T)
                col = T.Properties.VariableNames{c};
                app.covAddJob(node, thr, T{:, c}, sprintf('%s: %s', name, col), col);
            end
            app.applyRange("cov", [min(thr), max(thr)]); app.Cov_Panel_Results.Visible = 'on';
            expand(app.Cov_TreeNode_Results); expand(node); app.Cov_Tree.SelectedNodes = node;
            app.covRefresh();
            app.setStatus(app.Cov_StatusBar, sprintf('Coverage results file "%s" loaded (%d curves).', name, width(T) - 1), false);
        end

        function covApplyOrientation(app)
            k = app.covTarget(); o = app.Cov_DropDown_Orientation.Value;
            if o == 0 && k > 0, o = app.Pats(k).Derived.Boresight; end
            if o > 0, [app.Cov_Spinner_ConeTH.Value, app.Cov_Spinner_ConePH.Value] = deal(app.Const.Axes.theta(o), app.Const.Axes.phi(o)); end
        end

        function covSelect(app)
            %COVSELECT The one reaction to selection / coverage type / orientation / component changes:
            % enable states, component items, auto orientation, threshold preset, highlight, status.
            [k, pnode] = app.covTarget(); sel = app.Cov_Tree.SelectedNodes; jobs = app.covJobs();
            conical = app.Cov_ButtonGroup_Btn_Conical.Value; hasJobs = ~isempty(jobs);
            set([app.ConeSpinnerLabel, app.Cov_Spinner_ConeTH, app.ConeLabel, app.Cov_Spinner_ConePH, app.ConeAngleLabel, app.Cov_Spinner_ConeAng, ...
                app.Cov_DropDown_Orientation, app.Cov_DropDown_OrientationLabel], 'Enable', conical);
            set([app.Cov_Button_computeCov, app.Cov_DropDown_Component, app.Cov_DropDown_ComponentLabel], 'Enable', k > 0);
            set([app.Cov_Button_Reset, app.Cov_Button_Export, app.Cov_Button_Clear], 'Enable', hasJobs);
            set([app.Cov_QueryCoverageLabel, app.Cov_Spinner_queryCov, app.Cov_Button_queryCov, app.Cov_QueryThresholdLabel, app.Cov_Spinner_queryThresh, app.Cov_Button_queryThresh], 'Visible', hasJobs, 'Enable', hasJobs);
            if k > 0
                D = app.Pats(k).Derived; dd = app.Cov_DropDown_Component; prev = dd.Value;
                [dd.Items, dd.ItemsData] = deal(cellstr(D.Labels), cellstr(D.Names));
                if ~any(strcmp(dd.ItemsData, prev)), dd.Value = char(D.Names(1)); end
                if conical && app.Cov_DropDown_Orientation.Value == 0, app.covApplyOrientation(); end
                if app.Range.Auto.cov
                    pr = util_presetRange(D.Peak.value); [app.Cov_Spinner_ThreshMin.Value, app.Cov_Spinner_ThreshMax.Value] = deal(pr(1), pr(2));
                    app.applyRange("cov", pr);
                end
            end
            for j = jobs(:).', j.NodeData.Line.LineWidth = 1 + 1.5 * any(sel == j); end
            if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Ready.', false); return; end
            d = sel(1).NodeData;
            if isstruct(d) && d.kind == "job"
                [cmax, at] = max(d.cov); t50 = thr_at(d, 50);
                app.setStatus(app.Cov_StatusBar, sprintf('%s | max <b>%s%%</b> @ <b>%s dB</b> | 50%%-coverage threshold <b>%s dB</b>', d.label, ...
                    util_fmtNumber(cmax), util_fmtNumber(d.T(at)), util_fmtNumber(t50)), false);
            else
                name = 'Coverage Results';
                if isstruct(d) && d.kind == "pattern", name = pnode.Text; elseif isstruct(d), name = char(d.name); end
                txt = sprintf('<b>%s</b> — <b>%d</b> coverage job(s).', name, numel(app.covJobs(sel(1))));
                if k > 0 && conical
                    o = app.Cov_DropDown_Orientation.Value; if o == 0, o = app.Pats(k).Derived.Boresight; end
                    txt = sprintf('%s | Orientation <b>%s</b>', txt, app.Const.Axes.labels{o});
                end
                app.setStatus(app.Cov_StatusBar, txt, false);
            end
        end

        function covCompute(app)
            [k, pnode] = app.covTarget();
            if k == 0, uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            entry = app.Pats(k); D = entry.Derived; P = entry.Pattern; G = entry.Geometry; f = @util_fmtNumber;
            comp = string(app.Cov_DropDown_Component.Value); if ~any(D.Names == comp), comp = D.Names(1); end
            T = cov_thresholds(app.Cov_Spinner_ThreshMin.Value, app.Cov_Spinner_ThreshMax.Value, app.Cov_Spinner_Step.Value);
            if app.Cov_ButtonGroup_Btn_Conical.Value
                c = [app.Cov_Spinner_ConeTH.Value, mod(app.Cov_Spinner_ConePH.Value, 360), app.Cov_Spinner_ConeAng.Value];
                mask = cov_coneMask(P, c(1), c(2), c(3));
                region = sprintf('Conical θ₀=%s° φ₀=%s° α=%s°', f(c(1)), f(c(2)), f(c(3))); short = sprintf('Con[%s,%s,%s]', f(c(1)), f(c(2)), f(c(3)));
            else
                mask = true(size(G.dOmega)); region = 'Spherical'; short = 'Sph';
            end
            cov = cov_curve(D.Cols.(comp), G.dOmega, mask, T); app.perf("Coverage");
            label = sprintf('%s | %s | %s | L=%s dB | T=[%s:%s:%s] dB', entry.Name, region, app.Pats(k).Derived.Labels(D.Names == comp), ...
                f(entry.Params.GainLoss_dB), f(T(1)), f(T(2) - T(1)), f(T(end)));
            node = app.covAddJob(pnode, T, cov, label, sprintf('%s %s', short, comp));
            app.applyRange("cov", [T(1), T(end)]); app.Cov_Panel_Results.Visible = 'on';
            app.covRefresh();
            app.setStatus(app.Cov_StatusBar, sprintf('Run-<b>%d</b> computed: %s (%d thresholds).', node.NodeData.id, label, numel(T)), false);
        end

        function node = covAddJob(app, parent, T, cov, label, short)
            app.CovRunID = app.CovRunID + 1; id = app.CovRunID;
            h = plot(app.Cov_Axes, T(:), cov(:), 'LineWidth', 1, 'DisplayName', sprintf('R%d %s', id, short));
            h.DataTipTemplate.DataTipRows = [dataTipTextRow('Threshold', 'XData', '%.2f dB'); dataTipTextRow('Coverage', 'YData', '%.2f %%')];
            node = uitreenode(parent, 'Text', sprintf('R%d %s', id, short), ...
                'NodeData', struct('kind', "job", 'id', id, 'label', sprintf('R%d %s', id, label), 'short', short, 'T', T(:), 'cov', cov(:), 'Line', h));
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node]; expand(parent);
        end

        function shown = covShown(app)
            jobs = app.covJobs(); shown = jobs(ismember(jobs, app.Cov_Tree.CheckedNodes));
        end

        function covRefresh(app)
            %COVREFRESH Visibility follows the check state; legend and table follow visibility.
            jobs = app.covJobs(); shown = app.covShown();
            for j = jobs(:).', j.NodeData.Line.Visible = any(shown == j); end
            if isempty(shown), legend(app.Cov_Axes, 'off'); app.Cov_Tabel.Data = table();
            else
                lines = arrayfun(@(n) n.NodeData.Line, shown, 'UniformOutput', false);
                legend(app.Cov_Axes, [lines{:}], 'Location', 'best', 'Interpreter', 'none'); app.Cov_Tabel.Data = app.covTable(shown);
            end
            app.covSelect();
        end

        function T = covTable(~, jobs)
            %COVTABLE Union of thresholds; every column is one interp1 read of a curve.
            d = vertcat(jobs.NodeData); thr = unique(vertcat(d.T));
            T = table(thr, 'VariableNames', {'Threshold_dB'});
            for j = jobs(:).'
                T.(matlab.lang.makeValidName(sprintf('R%d_%s_pct', j.NodeData.id, j.NodeData.short))) = round(cov_at(j.NodeData, thr), 2);
            end
        end

        function covQuery(app, mode)
            sel = app.Cov_Tree.SelectedNodes;
            if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to query.', true); return; end
            jobs = app.covJobs(sel(1)); jobs = jobs(ismember(jobs, app.Cov_Tree.CheckedNodes));
            if isempty(jobs), app.setStatus(app.Cov_StatusBar, 'No checked results under the selected node.', true); return; end
            ax = app.Cov_Axes; tag = char("APAT_Query_" + mode); delete(findobj(ax, 'Tag', tag)); parts = {};
            for j = jobs(:).'
                d = j.NodeData;
                if mode == "cov", x = app.Cov_Spinner_queryCov.Value; y = cov_at(d, x); else, y = app.Cov_Spinner_queryThresh.Value; x = thr_at(d, y); end
                if ~isfinite(x) || ~isfinite(y), parts{end + 1} = sprintf('R%d: n/a', d.id); continue; end %#ok<AGROW>
                line(ax, [x x], [ax.YLim(1) y], 'Color', d.Line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [ax.XLim(1) x], [y y], 'Color', d.Line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                dt = datatip(d.Line, x, y, 'SnapToDataVertex', 'off'); dt.Tag = tag;
                parts{end + 1} = sprintf('R%d: <b>%s%%</b> @ <b>%s dB</b>', d.id, util_fmtNumber(y), util_fmtNumber(x)); %#ok<AGROW>
            end
            app.setStatus(app.Cov_StatusBar, ['Query — ' strjoin(parts, ' | ')], false);
        end

        function covReset(app)
            jobs = app.covJobs();
            for j = jobs(:).', delete(j.NodeData.Line); delete(j); end
            delete(app.Cov_TreeNode_Results.Children);
            delete(findobj(app.Cov_Axes, '-regexp', 'Tag', '^APAT_Query')); delete(findall(app.Cov_Axes, 'Type', 'datatip'));
            app.covRefresh(); app.setStatus(app.Cov_StatusBar, 'Coverage results cleared.', false);
        end

        function covExport(app)
            shown = app.covShown();
            if isempty(shown), uialert(app.UIFigure, 'No checked coverage results to export.', 'Export'); return; end
            [f, p] = uiputfile({'*.csv', 'CSV (*.csv)'; '*.xlsx', 'Excel (*.xlsx)'; '*.txt', 'Tab-delimited text (*.txt)'}, 'Export Coverage', 'APAT_coverage.csv');
            if isequal(f, 0), return; end
            util_writeTable(app.covTable(shown), fullfile(p, f));
            app.setStatus(app.Cov_StatusBar, ['Coverage exported to <b>' fullfile(p, f) '</b>'], true);
        end

        %% ------------------------------------------------------------ Main-tab exports
        function exportResults(app)
            if app.Main == 0, return; end
            entry = app.Pats(app.Main); [~, base] = fileparts(entry.Path);
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, ...
                'Export Results', fullfile(fileparts(entry.Path), [base '_APAT_results.csv']));
            if isequal(f, 0), return; end
            util_writeTable(app.resultsTable(app.OutMask), fullfile(p, f));
            app.setStatus(app.Single_StatusBar, ['Results exported to <b>' fullfile(p, f) '</b>'], true);
        end

        function exportUAN(app)
            if app.Main == 0 || app.Pats(app.Main).Pattern.IsGainOnly, uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            entry = app.Pats(app.Main); P = entry.Pattern; D = entry.Derived; [~, base] = fileparts(entry.Path);
            [PH, TH] = meshgrid(P.Phi, P.Theta);
            U = table(TH(:), PH(:), round(D.Cols.E_TH_dB(:), 5), round(D.Cols.E_PH_dB(:), 5), round(D.Cols.E_TH_Phase(:), 5), round(D.Cols.E_PH_Phase(:), 5), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'});
            U = sortrows(U, {'Phi', 'Theta'});
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'CSV (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, 'Export UAN / E-field data', ...
                fullfile(fileparts(entry.Path), sprintf('%s_%.5f_%sdeg.uan', base, D.Peak.value, util_fmtNumber(P.dTheta))));
            if isequal(f, 0), return; end
            fp = fullfile(p, f);
            if endsWith(fp, '.uan', 'IgnoreCase', true)
                header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                    P.Phi(1), P.Phi(end), P.dPhi, P.Theta(1), P.Theta(end), P.dTheta, D.Peak.value);
                writelines(header, fp);
                writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
            else
                util_writeTable(U, fp);
            end
            app.setStatus(app.Single_StatusBar, ['UAN exported to <b>' fp '</b>'], true);
        end

        function exportCut(app)
            if app.Main == 0, return; end
            entry = app.Pats(app.Main); V = app.View; [~, base] = fileparts(entry.Path);
            [names, ~] = app.cutTraces();
            cut = geo_cut(entry.Pattern, entry.Geometry, V.CutType, util_cutCanonical(V, V.CutValue), V.SignedPhi);
            T = table(cut.angle(:), 'VariableNames', {char(V.CutType + "_deg")});
            for n = names, C = entry.Derived.Cols.(n); T.(n) = C(cut.idx); end
            [f, p] = uiputfile({'*.csv', 'CSV (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Cut', ...
                fullfile(fileparts(entry.Path), sprintf('%s_cut_%s_%s.csv', base, V.CutType, util_fmtNumber(cut.fixed))));
            if isequal(f, 0), return; end
            util_writeTable(T, fullfile(p, f));
            app.setStatus(app.Single_StatusBar, ['Cut exported to <b>' fullfile(p, f) '</b>'], true);
        end
    end

    %% ================================================================ layout (declarative)
    % One line per widget: ui_place(handle, row, column). Every callback is one on(scope) call.
    methods (Access = private)

        function [tab, g, ax, slider, mn, mx] = patternTab(app, ttl, axesTitle, needsAxes)
            rcb = @(src, ~) app.on("range", src);
            tab = uitab(app.Single_tabPlots, 'Title', ttl);
            g = uigridlayout(tab, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'}); ax = [];
            if needsAxes
                ax = ui_place(uiaxes(g, 'Box', 'on', 'XLim', [0 360], 'YLim', [0 180], 'YDir', 'reverse', 'XTick', 0:30:360, 'YTick', 0:15:180), [1 3], 2);
                title(ax, axesTitle); xlabel(ax, 'Phi (degree)'); ylabel(ax, 'Theta (degree)');
            end
            mx = ui_place(uispinner(g, 'Limits', [-250 100], 'Value', 100, 'Step', 5, 'ValueChangedFcn', rcb), 1, 1);
            slider = ui_place(uislider(g, 'range', 'Limits', [-250 100], 'Value', [-250 100], 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', rcb), 2, 1);
            mn = ui_place(uispinner(g, 'Limits', [-250 100], 'Value', -250, 'Step', 5, 'ValueChangedFcn', rcb), 3, 1);
        end

        function createComponents(app)
            cb = @(scope) @(~, ~) app.on(scope); rcb = @(src, ~) app.on("range", src); grey = [0.9412 0.9412 0.9412];
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.Const.ReleaseName], 'Visible', 'off', 'Position', [100 100 1136 739], ...
                'WindowState', 'maximized', 'CloseRequestFcn', @(~, ev) app.closeRequest(ev));
            app.GridLayout = uigridlayout(app.UIFigure, [1 1]);
            app.TabGroup = ui_place(uitabgroup(app.GridLayout), 1, 1);
            app.Tab1_Single = uitab(app.TabGroup, 'Title', 'Process Pattern 📡');
            app.Single_Grid = uigridlayout(app.Tab1_Single, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});

            % ---- Inputs & Parameters
            app.Single_panelParam = ui_place(uipanel(app.Single_Grid, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 14]);
            g = uigridlayout(app.Single_panelParam, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'}); app.Single_gridPanel_Param = g;
            app.InputPatternLabel = ui_label(g, 'Input Pattern:', 1, 1);
            app.Single_EditField_Path = ui_place(uieditfield(g, 'text'), 1, [2 8]);
            app.FFDFreqDropDownLabel = ui_place(uilabel(g, 'Text', 'FFD Freq:', 'Enable', 'off', 'Visible', 'off'), 1, 9);
            app.Single_DropDown_FFD = ui_place(uidropdown(g, 'Items', {'Frequencies'}, 'Enable', 'off', 'Visible', 'off', 'ValueChangedFcn', cb("freq")), 1, 10);
            app.Single_Button_Load = ui_place(uibutton(g, 'push', 'Text', '📂 Load File', 'FontSize', 14, 'ButtonPushedFcn', cb("load")), 1, [11 12]);
            app.Single_Button_Process = ui_place(uibutton(g, 'push', 'Text', '⚙️ Process', 'ButtonPushedFcn', cb("params")), 1, [13 14]);
            app.Single_Button_ResetParams = ui_place(uibutton(g, 'push', 'Text', 'Reset Params', 'ButtonPushedFcn', cb("resetParams")), 2, [1 3]);
            app.TextFormatLabel = ui_label(g, 'Format:', 2, [4 5], 'Visible', 'off');
            app.Single_DropDown_TextFormat = ui_place(ui_textFormatDropdown(g, cb("format")), 2, [6 8]);
            app.Single_DropDown_step = ui_place(uidropdown(g, 'Items', {'STEP'}, 'Enable', 'off', 'Visible', 'off', 'Placeholder', 'STEP', 'ValueChangedFcn', cb("step")), 2, [9 10]);
            app.Single_Export_Output = ui_place(uibutton(g, 'push', 'Text', '💾 Export Results', 'Visible', 'off', 'ButtonPushedFcn', cb("exportResults")), 2, [11 12]);
            app.Single_Export_UAN = ui_place(uibutton(g, 'push', 'Text', '💾 Export UAN', 'Visible', 'off', 'ButtonPushedFcn', cb("exportUAN")), 2, [13 14]);
            app.RxPolLabel = ui_label(g, 'Rw Sense', 3, 1, 'Visible', 'off');
            app.Single_DropDown_RxPol = ui_place(uidropdown(g, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Editable', 'on', 'Visible', 'off'), 3, 2);
            app.IncidentWaveARRwPLFLabel = ui_label(g, 'Rw (dB)', 3, 3, 'Visible', 'off');
            app.Single_Spinner_Rw = ui_place(uispinner(g, 'Value', 6, 'Visible', 'off'), 3, 4);
            app.LossindBLabel = ui_label(g, 'Loss (−) / Gain (+) dB', 3, 5, 'Visible', 'off');
            app.Single_Spinner_Loss = ui_place(uispinner(g, 'Step', 0.1, 'Visible', 'off'), 3, 6);
            app.TransmitPowerLabel = ui_label(g, 'Tx Pwr (Pt)', 3, 7, 'Visible', 'off');
            app.Single_Spinner_Pt = ui_place(uispinner(g, 'Visible', 'off'), 3, 8);
            app.Single_DropDown_Pt = ui_place(uidropdown(g, 'Items', {'dBW', 'dBm', 'Watts'}, 'Visible', 'off'), 3, 9);
            app.DistanceLabel = ui_label(g, 'Distance', 3, 10, 'Visible', 'off');
            app.Single_Spinner_R = ui_place(uispinner(g, 'Value', 1, 'Visible', 'off'), 3, 11);
            app.Single_DropDown_R = ui_place(uidropdown(g, 'Items', {'m', 'km'}, 'Visible', 'off'), 3, 12);
            app.Single_Button_Coverage = ui_place(uibutton(g, 'push', 'Text', '📉 Coverage ▶', 'Visible', 'off', 'ButtonPushedFcn', cb("toCoverage")), 3, [13 14]);

            % ---- Full Antenna Pattern
            app.Single_Panel_fullPattern = ui_place(uipanel(app.Single_Grid, 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off', 'BackgroundColor', grey), [2 3], [1 6]);
            app.Single_gridPanel_full = uigridlayout(app.Single_Panel_fullPattern, [1 1]);
            app.Single_tabPlots = ui_place(uitabgroup(app.Single_gridPanel_full, 'SelectionChangedFcn', cb("fullTab")), 1, 1);
            [app.Single_tabContour, app.Single_gridContour, app.Single_Axes_Ctr, app.Range_Ctr, app.Range_Ctr_Min, app.Range_Ctr_Max] = app.patternTab('Contour Plot', 'Antenna Gain Pattern', true);
            [app.Single_tabCircular, app.Single_gridCircular, ~, app.Range_Cir, app.Range_Cir_Min, app.Range_Cir_Max] = app.patternTab('Circular Contour Plot', '', false);
            [app.Single_tab3DSpherical, app.Single_grid3dSpherical, app.Single_Axes_3dSph, app.Range_3dSph, app.Range_3dSph_Min, app.Range_3dSph_Max] = app.patternTab('3D Spherical Plot', '3D Spherical Plot', true);
            [app.Single_tab3DPolar, app.Single_grid3dPolar, app.Single_Axes_3dPol, app.Range_3dPol, app.Range_3dPol_Min, app.Range_3dPol_Max] = app.patternTab('3D Polar Plot', '3D Polar Plot', true);
            [app.Single_tab3DRect, app.Single_grid3dRect, app.Single_Axes_3dRect, app.Range_3dRect, app.Range_3dRect_Min, app.Range_3dRect_Max] = app.patternTab('3D Surface Plot', '3D Surface (Rectangular) Plot', true);

            % ---- Antenna Pattern Cut
            app.Single_Panel_Rect = ui_place(uipanel(app.Single_Grid, 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off', 'BackgroundColor', grey), [2 3], [7 12]);
            app.Single_gridPanel_Cut = uigridlayout(app.Single_Panel_Rect, [1 1]);
            app.Single_tabCut = ui_place(uitabgroup(app.Single_gridPanel_Cut), 1, 1);
            app.Single_tabPolarPlot = uitab(app.Single_tabCut, 'Title', 'Polar Cut Plot');
            gp = uigridlayout(app.Single_tabPolarPlot, 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'}); app.Single_Grid_Polar = gp;
            app.Range_Cut_Max = ui_place(uispinner(gp, 'Limits', [-250 100], 'Value', 100, 'Step', 5, 'ValueChangedFcn', rcb), 1, 1);
            app.Range_Cut = ui_place(uislider(gp, 'range', 'Limits', [-250 100], 'Value', [-250 100], 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', rcb), [2 3], 1);
            app.Range_Cut_Min = ui_place(uispinner(gp, 'Limits', [-250 100], 'Value', -250, 'Step', 5, 'ValueChangedFcn', rcb), 4, 1);
            app.Button_HPBW = ui_place(uibutton(gp, 'state', 'Text', 'HPBW', 'FontWeight', 'bold', 'IconAlignment', 'center', 'ValueChangedFcn', cb("hpbw")), 1, 4);
            app.Label_HPBW = ui_place(uilabel(gp, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold'), 2, 4);
            app.Single_gridEcut = ui_place(uigridlayout(gp, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x', '1x', '1x'}), 3, 4);
            app.CheckBox_Et = ui_place(uicheckbox(app.Single_gridEcut, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', cb("cut")), 1, 1);
            app.CheckBox_Er = ui_place(uicheckbox(app.Single_gridEcut, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', cb("cut")), 2, 1);
            app.CheckBox_El = ui_place(uicheckbox(app.Single_gridEcut, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', cb("cut")), 3, 1);
            app.Button_ExportCut = ui_place(uibutton(gp, 'push', 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', cb("exportCut")), 4, 4);
            app.Single_tabRectPlot = uitab(app.Single_tabCut, 'Title', 'Rectangular Cut Plot');
            app.Single_gridRect = uigridlayout(app.Single_tabRectPlot, [1 1]);
            app.Single_AxesRect = ui_place(uiaxes(app.Single_gridRect, 'Box', 'on', 'XLim', [0 360], 'XTick', 0:30:360), 1, 1);
            xlabel(app.Single_AxesRect, 'Phi (degree)'); ylabel(app.Single_AxesRect, 'Magnitude (dB)');

            % ---- Plot Control
            app.Single_Panel_plotControl = ui_place(uipanel(app.Single_Grid, 'Title', 'Plot Control 🎨', 'Visible', 'off'), 2, [13 14]);
            gc = uigridlayout(app.Single_Panel_plotControl, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', repmat({'fit'}, 1, 15)); app.Single_gridPanel_Ctrl = gc;
            app.ComponentLabel = ui_label(gc, 'Component', 1, 1);
            app.Single_DropDown_Component = ui_place(uidropdown(gc, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', cb("component")), 1, 2);
            app.CuttypeDropDownLabel = ui_label(gc, 'Cut type', 2, 1);
            app.Single_DropDown_cutType = ui_place(uidropdown(gc, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', cb("cut")), 2, 2);
            app.CutvalueSpinnerLabel = ui_label(gc, 'Cut value', 3, 1);
            app.Single_DropDown_cutValue = ui_place(uispinner(gc, 'Limits', [0 360], 'Value', 0, 'ValueChangedFcn', cb("cut")), 3, 2);
            ui_label(gc, 'Cut fields', 4, 1);
            app.CutFieldBasisDropDown = ui_place(uidropdown(gc, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'ValueChangedFcn', cb("span")), 4, 2);
            app.ColorbarmaxLabel = ui_label(gc, 'Colorbar max', 5, 1);
            app.Single_Plot_Cmax = ui_place(uispinner(gc, 'Limits', [-250 100], 'Value', 100, 'ValueChangedFcn', rcb), 5, 2);
            app.ColorbarminLabel = ui_label(gc, 'Colorbar min', 6, 1);
            app.Single_Plot_Cmin = ui_place(uispinner(gc, 'Limits', [-250 100], 'Value', -250, 'ValueChangedFcn', rcb), 6, 2);
            app.ColorbarstepLabel = ui_label(gc, 'Colorbar step', 7, 1);
            app.Single_Plot_Cstep = ui_place(uispinner(gc, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', rcb), 7, 2);
            app.Single_Label_Clim = ui_label(gc, 'Adjust Colorbar', 8, 1);
            app.Single_Button_Clim = ui_place(uibutton(gc, 'push', 'Text', 'Apply', 'ButtonPushedFcn', rcb), 8, 2);
            app.View3DLabel = ui_label(gc, '3D view', 9, 1);
            app.Single_DropDown_3DView = ui_place(uidropdown(gc, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Value', 'iso', 'ValueChangedFcn', cb("view3d")), 9, 2);
            pad = @(n) repmat(char(160), 1, n);
            app.Single_Switch_AngularSpan = ui_place(uiswitch(gc, 'slider', 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'Value', '0° to 360°', 'ValueChangedFcn', cb("span")), 10, [1 2]);
            app.Single_Switch_ThetaSpan = ui_place(uiswitch(gc, 'slider', 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'Value', '0° to 180°', 'ValueChangedFcn', cb("span")), 11, [1 2]);
            app.Single_Switch_EHplane = ui_place(uiswitch(gc, 'slider', 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'Value', 'E-Plane cut', 'ValueChangedFcn', cb("plane")), 12, [1 2]);
            app.Singel_CheckBox_overlayCut = ui_place(uicheckbox(gc, 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', cb("overlay")), 13, [1 2]);
            app.Single_CheckBox_POB = ui_place(uicheckbox(gc, 'Text', 'Annotate POB', 'ValueChangedFcn', cb("pob")), 14, [1 2]);
            app.Single_CheckBox_HPBWBounds = ui_place(uicheckbox(gc, 'Text', 'Annotate HPBW Bounds', 'ValueChangedFcn', cb("hpbw")), 15, [1 2]);

            % ---- Data tabs & status
            app.Single_DropDown_output = ui_place(uidropdown(app.Single_Grid, 'Items', {'Select Output:'}, 'ItemsData', {0}, 'Value', 0, 'Visible', 'off', 'ValueChangedFcn', cb("filter")), 3, [13 14]);
            app.Single_tabData = ui_place(uitabgroup(app.Single_Grid, 'Visible', 'off', 'SelectionChangedFcn', cb("dataTab")), 4, [1 14]);
            app.Single_tabDataOut = uitab(app.Single_tabData, 'Title', 'Results 📤');
            app.Single_gridDataOut = uigridlayout(app.Single_tabDataOut, [1 1]);
            app.Single_Table_DataOut = ui_place(uitable(app.Single_gridDataOut, 'ColumnWidth', '1x', 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true, 'Visible', 'off'), 1, 1);
            app.Single_tabDataIn = uitab(app.Single_tabData, 'Title', 'Input 📥');
            app.Single_gridDataIn = uigridlayout(app.Single_tabDataIn, [1 1]);
            app.Single_Table_DataIn = ui_place(uitable(app.Single_gridDataIn, 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true, 'Visible', 'off'), 1, 1);
            app.MetadataTab = uitab(app.Single_tabData, 'Title', 'Metadata 📋');
            app.Single_gridMetadata = uigridlayout(app.MetadataTab, [1 1]);
            app.Single_Table_metadata = ui_place(uitable(app.Single_gridMetadata, 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {}), 1, 1);
            app.Single_StatusBar = ui_place(uilabel(app.Single_Grid, 'Text', 'Ready 🚀', 'Interpreter', 'html', 'Tag', 'main'), 5, [1 14]);

            % ---- Coverage tab
            app.Tab2_Coverage = uitab(app.TabGroup, 'Title', 'Compute Coverage 📈');
            app.Cov_Grid = uigridlayout(app.Tab2_Coverage, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            app.Cov_Panel_Param = ui_place(uipanel(app.Cov_Grid, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 5]);
            gv = uigridlayout(app.Cov_Panel_Param, 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'}); app.Cov_gridPanel_Parm = gv;
            app.Cov_ButtonGroup_CovType = ui_place(uibuttongroup(gv, 'Title', 'Coverage Type', 'SelectionChangedFcn', cb("cov:type")), [1 2], [1 2]);
            app.Cov_ButtonGroup_Btn_Spherical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            app.Cov_ButtonGroup_Btn_Conical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            app.Cov_DropDown_OrientationLabel = ui_label(gv, 'Orientation 🧭:', 3, 1, 'Enable', 'off');
            app.Cov_DropDown_Orientation = ui_place(uidropdown(gv, 'Items', [{'Auto'}, app.Const.Axes.labels], 'ItemsData', 0:6, 'Value', 0, 'Enable', 'off', 'ValueChangedFcn', cb("cov:orient")), 3, 2);
            app.AntennaPatternEditFieldLabel = ui_label(gv, 'Antenna Pattern:', 1, 3);
            app.Cov_EditField_filePath = ui_place(uieditfield(gv, 'text'), 1, [4 8]);
            app.Cov_Button_Load = ui_place(uibutton(gv, 'push', 'Text', '📂 Load File', 'ButtonPushedFcn', cb("cov:load")), 1, 9);
            app.Cov_Button_computeCov = ui_place(uibutton(gv, 'push', 'Text', '⚙️ Compute Coverage', 'Enable', 'off', 'ButtonPushedFcn', cb("cov:compute")), 1, 10);
            app.ThresholdMindBSpinnerLabel = ui_label(gv, 'Threshold  Min (dB):', 2, 3);
            app.Cov_Spinner_ThreshMin = ui_place(uispinner(gv, 'Value', -40, 'ValueChangedFcn', cb("cov:thresh")), 2, 4);
            app.ThresholdMaxdBSpinnerLabel = ui_label(gv, 'Threshold  Max (dB):', 2, 5);
            app.Cov_Spinner_ThreshMax = ui_place(uispinner(gv, 'Value', 10, 'ValueChangedFcn', cb("cov:thresh")), 2, 6);
            app.StepdBSpinnerLabel = ui_label(gv, 'Step (dB):', 2, 7);
            app.Cov_Spinner_Step = ui_place(uispinner(gv, 'Value', 1, 'Limits', [0.001 100], 'ValueChangedFcn', cb("cov:thresh")), 2, 8);
            app.Cov_Button_Reset = ui_place(uibutton(gv, 'push', 'Text', '🔄 Reset', 'Enable', 'off', 'ButtonPushedFcn', cb("cov:reset")), 2, 9);
            app.Cov_Button_Export = ui_place(uibutton(gv, 'push', 'Text', '💾 Export Results', 'Enable', 'off', 'ButtonPushedFcn', cb("cov:export")), 2, 10);
            app.ConeSpinnerLabel = ui_label(gv, 'Cone θ₀ (°):', 3, 3, 'Enable', 'off');
            app.Cov_Spinner_ConeTH = ui_place(uispinner(gv, 'Limits', [0 180], 'Enable', 'off'), 3, 4);
            app.ConeLabel = ui_label(gv, 'Cone φ₀ (°):', 3, 5, 'Enable', 'off');
            app.Cov_Spinner_ConePH = ui_place(uispinner(gv, 'Limits', [0 360], 'Enable', 'off'), 3, 6);
            app.ConeAngleLabel = ui_label(gv, 'Cone Angle α (°):', 3, 7, 'Enable', 'off');
            app.Cov_Spinner_ConeAng = ui_place(uispinner(gv, 'Limits', [0 180], 'Value', 45, 'Enable', 'off'), 3, 8);
            app.Cov_Button_Clear = ui_place(uibutton(gv, 'push', 'Text', '🧹 Clear DataTips', 'Enable', 'off', 'ButtonPushedFcn', cb("cov:clear")), 3, 9);
            app.Cov_Button_toMain = ui_place(uibutton(gv, 'push', 'Text', '📊 To Main ◀ ', 'ButtonPushedFcn', @(~, ~) set(app.TabGroup, 'SelectedTab', app.Tab1_Single)), 3, 10);
            app.Cov_DropDown_ComponentLabel = ui_label(gv, 'Component:', 4, 1, 'Enable', 'off');
            app.Cov_DropDown_Component = ui_place(uidropdown(gv, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'Enable', 'off', 'ValueChangedFcn', cb("cov:component")), 4, 2);
            app.Cov_QueryCoverageLabel = ui_label(gv, 'Coverage @ dB:', 4, 3, 'Visible', 'off');
            app.Cov_Spinner_queryCov = ui_place(uispinner(gv, 'ValueDisplayFormat', '%g dB', 'Visible', 'off'), 4, 4);
            app.Cov_Button_queryCov = ui_place(uibutton(gv, 'push', 'Text', '⯐ Query Coverage', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', cb("cov:queryCov")), 4, 5);
            app.Cov_QueryThresholdLabel = ui_label(gv, 'Threshold @ %:', 4, 6, 'Visible', 'off');
            app.Cov_Spinner_queryThresh = ui_place(uispinner(gv, 'Limits', [0 100], 'Value', 50, 'ValueDisplayFormat', '%g%%', 'Visible', 'off'), 4, 7);
            app.Cov_Button_queryThresh = ui_place(uibutton(gv, 'push', 'Text', '🔍︎ Query Threshold', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', cb("cov:queryThr")), 4, 8);
            app.Cov_TextFormatLabel = ui_label(gv, 'Format:', 4, 9);
            app.Cov_DropDown_TextFormat = ui_place(ui_textFormatDropdown(gv, cb("cov:format")), 4, 10);
            app.Cov_StatusBar = ui_place(uilabel(app.Cov_Grid, 'Text', 'Ready 🚀', 'Interpreter', 'html', 'Tag', 'cov'), 3, [1 5]);
            app.Cov_Panel_Results = ui_place(uipanel(app.Cov_Grid, 'Title', 'Results', 'Visible', 'off'), 2, [1 5]);
            app.GridLayout2 = uigridlayout(app.Cov_Panel_Results, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            app.Cov_Axes = ui_place(uiaxes(app.GridLayout2, 'Interactions', dataTipInteraction, 'NextPlot', 'add', 'XGrid', 'on', 'YGrid', 'on', 'YLim', [0 100], 'XLim', [-40 10]), 1, [2 4]);
            title(app.Cov_Axes, 'Coverage vs Threshold'); xlabel(app.Cov_Axes, 'Threshold (dB)'); ylabel(app.Cov_Axes, 'Coverage (%)');
            app.Cov_Tree = ui_place(uitree(app.GridLayout2, 'checkbox', 'SelectionChangedFcn', cb("cov:selected"), 'CheckedNodesChangedFcn', cb("cov:checked")), [1 2], 1);
            app.Cov_TreeNode_Results = uitreenode(app.Cov_Tree, 'Text', 'Coverage Results');
            app.Cov_Tabel = ui_place(uitable(app.GridLayout2, 'ColumnWidth', '1x', 'RowName', {}), [1 2], 5);
            app.Cov_Spinner_XMin = ui_place(uispinner(app.GridLayout2, 'Limits', [-250 100], 'Value', -40, 'ValueChangedFcn', rcb), 2, 2);
            app.Cov_Spinner_XRange = ui_place(uislider(app.GridLayout2, 'range', 'Limits', [-250 100], 'Value', [-40 10], 'ValueChangedFcn', rcb, ...
                'ValueChangingFcn', @(~, ev) set(app.Cov_Axes, 'XLim', sort(ev.Value))), 2, 3);
            app.Cov_Spinner_XMax = ui_place(uispinner(app.GridLayout2, 'Limits', [-250 100], 'Value', 10, 'ValueChangedFcn', rcb), 2, 4);

            app.initAxes();
            app.UIFigure.Visible = 'on';
        end
    end
end

%% ======================================================================= I/O
% Every reader returns Source = {Raw (Input tab), Blocks{f} (long tables), Freqs, Meta}. A field block is
% [Theta Phi Re_Eth Im_Eth Re_Eph Im_Eph]; a gain-only block is [Theta Phi <gain columns>].
function S = io_read(fp, textFormat)
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
freqs = NaN; unit = "dB"; gainOnly = false; isText = false; notes = strings(1, 0); isCov = false;
switch ext
    case {'XLSX', 'XLS'},      [blocks, raw, fmt, freqs, unit] = io_excel(fp);
    case {'CSV', 'TXT', 'DAT'}, isText = true; [blocks, raw, fmt, gainOnly, isCov, unit, notes] = io_text(fp, string(textFormat));
    case 'CUT',                [blocks, raw, fmt, notes] = io_cut(fp);
    otherwise,                 [blocks, raw, fmt, freqs, unit, notes] = io_farfield(fp, ext);
end
freqs = [double(freqs(:).'), NaN(1, max(numel(blocks), 1))]; freqs = freqs(1:max(numel(blocks), 1));
S = struct('Raw', raw, 'Blocks', {blocks}, 'Freqs', freqs, 'Meta', struct('Format', string(fmt), 'Unit', string(unit), ...
    'UnitLabel', util_pick(unit == "dBi", "dBi", "dB (relative)"), 'IsGainOnly', gainOnly, 'IsCoverage', isCov, 'IsText', isText, 'Notes', notes));
end

function F = io_scan(fp)
%IO_SCAN Tokenise a text far-field file once: numeric data rows, block ids at frequency markers, header.
num = '[-+]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][-+]?\d+)?';
L = cellstr(regexprep(readlines(fp), '(\d)[dD]([-+]?\d)', '$1E$2'));
tok = regexp(L, num, 'match'); counts = cellfun(@numel, tok);
isMarker = ~cellfun(@isempty, regexp(L, '^\s*#?\s*Frequenc(y|ies)\b', 'once', 'ignorecase'));
first = find(counts >= 4 & ~isMarker, 1);
if isempty(first), error('APAT:io:NoData', 'No numeric data rows found in "%s".', fp); end
isData = counts == counts(first) & ~isMarker; before = (1:numel(L)).' < first;
F.rows = str2double(vertcat(tok{isData}));
F.blockId = cumsum(isMarker & ~before); F.blockId = F.blockId(isData);
F.markerFreqs = cellfun(@(t) str2double(t{1}), tok(isMarker & ~before & counts > 0));
F.declared = []; d = find(isMarker & before, 1); if ~isempty(d) && counts(d) > 1, F.declared = str2double(tok{d}); end
F.triples = zeros(0, 3); tri = tok(counts == 3 & before & ~isMarker); if ~isempty(tri), F.triples = str2double(vertcat(tri{:})); end
F.header = lower(strjoin(L(before), newline));
end

function [B, raw] = io_fields(M, spec)
%IO_FIELDS Six numeric columns → canonical field block. spec.cols reorders the file columns into
% [θ φ a b c d] with (a,b,c,d) = (mag1, mag2, ph1°, ph2°) for "magphase" or (re1, im1, re2, im2) for "reim".
raw = array2table(M(:, 1:6), 'VariableNames', spec.names); M = M(:, spec.cols);
if spec.kind == "magphase", c1 = 10.^(M(:, 3) / 20) .* exp(1i * deg2rad(M(:, 5))); c2 = 10.^(M(:, 4) / 20) .* exp(1i * deg2rad(M(:, 6)));
else, c1 = complex(M(:, 3), M(:, 4)); c2 = complex(M(:, 5), M(:, 6));
end
switch spec.basis
    case "lin", Eth = c1; Eph = c2;
    case "rcp", [Eth, Eph] = pol_fromCircular(c1, c2);
    otherwise,  [Eth, Eph] = pol_fromCircular(c2, c1);
end
B = util_block(M(:, 1), M(:, 2), Eth, Eph);
end

function [blocks, raw, fmt, freqs, unit, notes] = io_farfield(fp, ext)
F = io_scan(fp); R = F.rows; freqs = NaN; unit = "dB"; notes = strings(1, 0);
spec = struct('cols', 1:6, 'kind', "reim", 'basis', "lin", 'names', {{'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}});
switch ext
    case {'FZ', 'UAN'}   % XGTD: Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
        if contains(F.header, 'begin_<parameters>') && ~(contains(F.header, 'theta_phi') && contains(F.header, 'mag_phase'))
            error('APAT:UnsupportedUAN', 'UAN header must declare "polarization theta_phi" and "mag_phase".');
        end
        spec.kind = "magphase"; spec.names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}; fmt = "XGTD " + ext; unit = "dBi";
    case 'OUT'           % TICRA/GRASP: Theta Phi Re(RHCP) Im(RHCP) Re(LHCP) Im(LHCP)
        spec.basis = "rcp"; spec.names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; fmt = "TICRA/GRASP OUT";
    case 'FFS'           % CST: Phi Theta Re(Eth) Im(Eth) Re(Eph) Im(Eph)
        spec.cols = [2 1 3 4 5 6]; spec.names = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; fmt = "CST FFS";
    case 'FFE'           % FEKO: Theta Phi Re(Eth) Im(Eth) Re(Eph) Im(Eph) [...]; one "#Frequency:" block per frequency
        fmt = "FEKO FFE"; freqs = F.markerFreqs;
    case 'FFD'           % HFSS: two header triples (θ, φ: start stop count), rows Re(Eth) Im(Eth) Re(Eph) Im(Eph)
        if size(F.triples, 1) < 2, error('APAT:io:FFDHeader', 'FFD header (theta/phi ranges) not found.'); end
        th = linspace(F.triples(1, 1), F.triples(1, 2), round(F.triples(1, 3))).'; ph = linspace(F.triples(2, 1), F.triples(2, 2), round(F.triples(2, 3))).';
        n = numel(th) * numel(ph); nb = size(R, 1) / n;
        if nb ~= round(nb), error('APAT:io:FFDGrid', 'FFD row count (%d) is not a multiple of the θ×φ grid (%d).', size(R, 1), n); end
        R = [repmat(repelem(th, numel(ph)), nb, 1), repmat(repmat(ph, numel(th), 1), nb, 1), R(:, 1:4)];
        if numel(unique(F.blockId)) ~= nb, F.blockId = repelem((1:nb).', n); end
        freqs = util_pick(isempty(F.markerFreqs), F.declared, F.markerFreqs); fmt = "HFSS FFD";
    otherwise, error('APAT:io:Unsupported', 'Unsupported format: %s', ext);
end
ids = unique(F.blockId); blocks = cell(1, numel(ids));
for b = 1:numel(ids), [blocks{b}, rawB] = io_fields(R(F.blockId == ids(b), :), spec); if b == 1, raw = rawB; end, end
if numel(blocks) > 1, notes(end + 1) = sprintf('%d frequency blocks found; each is selectable in the frequency dropdown.', numel(blocks)); end
end

function [blocks, raw, fmt, notes] = io_cut(fp)
%IO_CUT TICRA/GRASP .cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks.
L = readlines(fp); L(strlength(strtrim(L)) == 0) = []; th = {}; ph = {}; D = {}; k = 1; notes = strings(1, 0);
while k < numel(L)
    p = sscanf(L(k + 1), '%f'); if numel(p) < 7, error('APAT:io:CUT', 'Could not parse .cut parameter line %d.', k + 1); end
    n = p(3); comp = p(5); cutType = p(6);
    if ~ismember(comp, [1 2]), error('APAT:UnsupportedICOMP', '.cut ICOMP=%g is not supported (1 = θ/φ, 2 = RHCP/LHCP).', comp); end
    blk = reshape(sscanf(strjoin(L(k + 2:k + 1 + n), ' '), '%f'), 2 * p(7), []).';
    th{end + 1} = p(1) + (0:n - 1).' * p(2); ph{end + 1} = repmat(p(4), n, 1); D{end + 1} = blk(:, 1:4); %#ok<AGROW>
    k = k + 2 + n;
end
th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:});
if cutType == 2, [th, ph] = deal(ph, th); end
if isscalar(unique(ph))      % single cut → body of revolution, disclosed
    m = 36; th = repmat(th, m, 1); ph = repelem((0:10:350).', numel(ph)); D = repmat(D, m, 1);
    notes(end + 1) = 'Single .cut block: pattern synthesised as a body of revolution (36 φ copies).';
end
if comp == 2, names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; basis = "rcp"; else, names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; basis = "lin"; end
[B, raw] = io_fields([th, ph, D], struct('cols', 1:6, 'kind', "reim", 'basis', basis, 'names', {names}));
blocks = {B}; fmt = "TICRA/GRASP CUT";
end

function [blocks, raw, fmt, gainOnly, isCov, unit, notes] = io_text(fp, textFormat)
%IO_TEXT CSV/TXT/DAT: coverage results, gain-only pattern, or six-column E-field per the format dropdown.
opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvartype(opts, 'double'); opts = setvaropts(opts, 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
T = readtable(fp, opts); T = T(all(isfinite(T{:, 1:2}), 2), :);              % drop rows only when θ/φ are missing
nc = width(T); assert(nc >= 2 && ~isempty(T), 'APAT:io:Text', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHeaders = ~all(startsWith(names, "Var")); notes = strings(1, 0);
c1 = T{:, 1}; c2 = T{:, 2}; blocks = {}; gainOnly = false; unit = "dBi"; raw = T;
covHeader = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
isCov = (textFormat == "gain" || nc < 6 || covHeader) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic') && (covHeader || ~hasHeaders);
if isCov
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:nc - 1))]; end
    raw = T; fmt = "Coverage results"; return
end
if textFormat == "gain"
    thetaFirst = (max(c1) - min(c1)) <= (max(c2) - min(c2)); if hasHeaders && any(startsWith(lower(names(1:2)), "phi")), thetaFirst = ~startsWith(lower(names(1)), "phi"); end
    if ~thetaFirst, T = T(:, [2 1 3:nc]); notes(end + 1) = 'Axis order: first column read as φ (larger span / header name).'; end
    T.Properties.VariableNames(1:2) = {'Theta', 'Phi'};
    blocks = {T}; if ~hasHeaders, raw = T; end; gainOnly = true; fmt = "Gain table (text)"; return
end
assert(nc >= 6, 'APAT:io:TextEField', 'The selected generic E-field format requires six numeric columns.');
M = T{:, 1:6}; magphase = endsWith(textFormat, "magphase"); spec = struct('cols', 1:6, 'kind', "reim", 'basis', "lin", 'names', {cellstr(names(1:6))});
if startsWith(textFormat, "rcp"), spec.basis = "rcp"; elseif startsWith(textFormat, "lcp"), spec.basis = "lcp"; end
comp = util_pick(spec.basis == "lin", ["E_TH", "E_PH"], ["POL1", "POL2"]); layout = "";
if magphase
    spec.kind = "magphase"; big = max(abs(M(:, 3:6)), [], 1, 'omitnan') > 100;   % phases exceed ±100, magnitudes in dB do not
    if big(2) && ~big(3), spec.cols = [1 2 3 5 4 6]; layout = "interleaved"; gen = [comp(1) + "_dB", comp(1) + "_deg", comp(2) + "_dB", comp(2) + "_deg"];
    else, layout = "grouped"; gen = [comp + "_dB", comp + "_deg"];
    end
    notes(end + 1) = "Magnitude/phase column layout detected as " + layout + " (phase columns exceed ±100).";
else
    unit = "dB"; gen = [comp(1) + "_real", comp(1) + "_imag", comp(2) + "_real", comp(2) + "_imag"];
end
if ~hasHeaders, spec.names = cellstr(["Theta", "Phi", gen]); end
[B, raw] = io_fields(M, spec); blocks = {B}; fmt = sprintf('Generic text (%s%s)', textFormat, util_pick(layout == "", "", ", " + layout));
end

function [blocks, raw, fmt, freq, unit] = io_excel(fp)
%IO_EXCEL Excel Matrix workbooks: first sheet = summary, then fixed component sheets (C3-origin matrices).
sheets = string(sheetnames(fp)); unit = "dBi";
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"]; lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
if ~hasC && ~hasL, error('APAT:io:ExcelFormat', 'Unsupported Excel workbook: expected Etheta/Ephi and/or RHCP/LHCP component sheets after the summary sheet.'); end
req = util_pick(hasL, lin, circ); fmt = util_pick(hasL && hasC, "Excel Matrix Format 3 (Ercp/Elcp + Eth/Eph)", util_pick(hasL, "Excel Matrix Format 1 (Eth/Eph)", "Excel Matrix Format 2 (Ercp/Elcp)"));
G = cell(1, 4);
for k = 1:4
    C = readcell(fp, 'Sheet', char(sheets(strcmpi(sheets, req(k)))));
    isNum = @(c) cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), c);
    ph = C(2, 3:end); th = C(3:end, 2); ph = cell2mat(ph(isNum(ph))); th = cell2mat(th(isNum(th)));
    if isempty(th) || isempty(ph), error('APAT:io:ExcelSheet', 'Sheet "%s" has no numeric θ/φ axes at C3 origin.', req(k)); end
    D = C(3:2 + numel(th), 3:2 + numel(ph));
    if ~all(isNum(D), 'all'), error('APAT:io:ExcelSheet', 'Sheet "%s" contains non-numeric matrix samples.', req(k)); end
    if k == 1, th0 = th(:); ph0 = ph(:).'; elseif ~isequal(numel(th), numel(th0)) || any(abs(th(:) - th0) > 1e-9) || any(abs(ph(:).' - ph0) > 1e-9)
        error('APAT:io:ExcelGrid', 'All Excel Matrix component sheets must share the same θ/φ grid.');
    end
    G{k} = cell2mat(D);
end
c1 = 10.^(G{1} / 20) .* exp(1i * deg2rad(G{2})); c2 = 10.^(G{3} / 20) .* exp(1i * deg2rad(G{4}));
if hasL, Eth = c1; Eph = c2; else, [Eth, Eph] = pol_fromCircular(c1, c2); end
[PH, TH] = meshgrid(ph0, th0); B = util_block(TH, PH, Eth, Eph); raw = B;
for k = 1:4, raw.(char(req(k))) = reshape(G{k}, [], 1); end
S = readcell(fp, 'Sheet', char(sheets(1)), 'Range', 'A1:H70'); freq = NaN;   % the only summary field APAT uses
[r, ~] = find(cellfun(@(x) (ischar(x) || isstring(x)) && contains(lower(string(x)), 'simulation freq'), S), 1);
if ~isempty(r), v = S(r, :); v = v(cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), v)); if ~isempty(v), freq = 1e6 * v{1}; end, end
blocks = {B};
end

%% ======================================================================= pattern / geometry
function P = pat_build(S, f)
%PAT_BUILD Long block → canonical grid-native pattern: θ ascending in [0,180], φ ascending in [0,360),
% uniform steps asserted once. Angles snapped to 5 decimals; field values never rounded.
f = min(f, numel(S.Blocks)); B = S.Blocks{f}; th = B{:, 1}; ph = B{:, 2}; V = B{:, 3:end};
names = string(matlab.lang.makeValidName(B.Properties.VariableNames(3:end)));
notes = S.Meta.Notes; keep = isfinite(th) & isfinite(ph); th = th(keep); ph = ph(keep); V = V(keep, :);
if min(th) < 0 && min(th) >= -90 && max(th) <= 90, th = 90 - th; notes(end + 1) = 'Source θ in [-90°, 90°] read as elevation and mapped to polar θ = 90° − el.'; end
neg = th < 0; th(neg) = -th(neg); ph(neg) = ph(neg) + 180;
over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;
th = round(th, 5); ph = round(mod(ph, 360), 5); ph(ph >= 360) = 0;
theta = unique(th); phi = unique(ph).';
dT = util_assertUniform(theta, 'Theta'); dP = util_assertUniform(phi, 'Phi');
if isnan(dT), dT = 180; end, if isnan(dP), dP = 360; end
[~, i] = ismember(th, theta); [~, j] = ismember(ph, phi); lin = sub2ind([numel(theta), numel(phi)], i, j);
grid = @(v) util_grid(v, lin, [numel(theta), numel(phi)]);
P = struct('Theta', theta(:), 'Phi', phi, 'dTheta', dT, 'dPhi', dP, 'Native', [dT dP], 'IsGainOnly', S.Meta.IsGainOnly, 'Unit', S.Meta.Unit, ...
    'Eth', [], 'Eph', [], 'G', struct(), 'Names', names, 'Freq', S.Freqs(f), 'Notes', notes);
if P.IsGainOnly, for c = 1:numel(names), P.G.(names(c)) = grid(V(:, c)); end
else, P.Eth = complex(grid(V(:, 1)), grid(V(:, 2))); P.Eph = complex(grid(V(:, 3)), grid(V(:, 4)));
end
missing = numel(theta) * numel(phi) - numel(unique(lin));
if missing > 0, P.Notes(end + 1) = sprintf('%d grid cell(s) have no sample (shown as NaN, excluded from integrals).', missing); end
end

function P = pat_resample(P, step)
%PAT_RESAMPLE Uniform grid → uniform grid at STEP. Exact decimation when the target angles exist in the
% source; otherwise bilinear on the φ-closed grid: fields as linear power + unit phasor, gain-kind
% columns as linear power, other kinds linear. Target axes never leave the source domain.
periodic = numel(P.Phi) > 1 && abs(numel(P.Phi) * P.dPhi - 360) < 1e-6;
th2 = round((ceil(P.Theta(1) / step) * step:step:floor(P.Theta(end) / step) * step).', 5);
ph2 = round(ceil(P.Phi(1) / step) * step:step:util_pick(periodic, P.Phi(1) + 360 - step, floor(P.Phi(end) / step) * step), 5);
[okT, iT] = ismembertol(th2, P.Theta, 1e-9, 'DataScale', 1); [okP, jP] = ismembertol(mod(ph2, 360), P.Phi, 1e-9, 'DataScale', 1);
if all(okT) && all(okP)
    rs = @(C, ~) C(iT, jP); how = 'exact decimation';
else
    phs = P.Phi; wrap = @(C) C; if periodic, phs(end + 1) = P.Phi(1) + 360; wrap = @(C) [C, C(:, 1)]; end
    lin = @(C) interp2(phs, P.Theta, wrap(C), ph2, th2, 'linear');
    rs = @(C, kind) pat_interp(C, kind, lin); how = 'bilinear interpolation (power + unit phasor)';
end
if P.IsGainOnly, for n = P.Names, P.G.(n) = rs(P.G.(n), util_colKind(n)); end
else, P.Eth = rs(P.Eth, "field"); P.Eph = rs(P.Eph, "field");
end
P.Notes(end + 1) = sprintf('Resampled %s° × %s° → %g° by %s.', util_fmtNumber(P.dTheta), util_fmtNumber(P.dPhi), step, how);
P.Theta = th2; P.Phi = ph2; P.dTheta = step; P.dPhi = step;
end

function C = pat_interp(C, kind, lin)
%PAT_INTERP Interpolate one column by kind: fields as linear power + unit phasor (B.5), gain-kind columns as
% linear power, everything else linearly. LIN is the bilinear operator on the φ-closed source grid.
switch kind
    case "field"
        u = C ./ max(abs(C), eps); u = complex(lin(real(u)), lin(imag(u)));
        C = sqrt(max(lin(abs(C).^2), 0)) .* u ./ max(abs(u), eps);
    case "gain", C = 10 * log10(max(lin(10.^(C / 10)), eps));
    otherwise,   C = lin(C);
end
end

function G = geo_build(P)
%GEO_BUILD Separable solid-angle weights: ΔΩ(i,j) = wθ(i)·Δφ, wθ = cos(lo) − cos(hi) with cells clipped to
% the poles; adjacent cells share boundaries so ΣΔΩ = 4π exactly on a full sphere. No seam column exists.
lo = max(P.Theta - P.dTheta / 2, 0); hi = min(P.Theta + P.dTheta / 2, 180);
G.wTheta = cosd(lo) - cosd(hi); G.dPhi = deg2rad(P.dPhi);
G.dOmega = G.wTheta * G.dPhi * ones(1, numel(P.Phi)); G.Omega = sum(G.dOmega(:));
G.PhiPeriodic = numel(P.Phi) > 1 && abs(numel(P.Phi) * P.dPhi - 360) < 1e-6;
G.IsFullSphere = G.PhiPeriodic && lo(1) <= 1e-9 && hi(end) >= 180 - 1e-9;
end

function M = geo_displayMap(P, G, view)
%GEO_DISPLAYMAP Display convention as a column permutation plus axis labels. Data are never rewritten.
n = numel(P.Phi); j0 = find(P.Phi >= 180, 1); perm = 1:n;
if view.SignedPhi && ~isempty(j0), perm = [j0:n, 1:j0 - 1]; end
M.ColIdx = perm; if G.PhiPeriodic, M.ColIdx(end + 1) = perm(1); end        % closing column for display only
M.PhiAxis = P.Phi(perm); if view.SignedPhi, M.PhiAxis(M.PhiAxis >= 180) = M.PhiAxis(M.PhiAxis >= 180) - 360; end
if G.PhiPeriodic, M.PhiAxis(end + 1) = M.PhiAxis(1) + 360; end
if view.Elevation, M.ThetaAxis = 90 - P.Theta; M.ThetaDir = 'normal'; M.ThetaLabel = "Elevation";
else, M.ThetaAxis = P.Theta; M.ThetaDir = 'reverse'; M.ThetaLabel = "Theta";
end
M.SignedPhi = view.SignedPhi; M.Elevation = view.Elevation;
end

function cut = geo_cut(P, G, type, value, signed)
%GEO_CUT One full-circle cut through the grid (no interpolation; the requested angle snaps to a sample).
% "Phi": φ varies at fixed θ. "Theta": θ varies at fixed φ, continued through the poles on φ+180°.
nT = numel(P.Theta); nP = numel(P.Phi);
if type == "Phi"
    [~, i] = min(abs(P.Theta - value)); j = 1:nP; ang = P.Phi(:);
    idx = sub2ind([nT nP], i * ones(nP, 1), j(:)); fixed = P.Theta(i); symbol = 'θ'; step = P.dPhi; full = G.PhiPeriodic;
else
    [~, j1] = min(abs(mod(P.Phi - value + 180, 360) - 180)); [d2, j2] = min(abs(mod(P.Phi - P.Phi(j1), 360) - 180));
    idx = sub2ind([nT nP], (1:nT).', j1 * ones(nT, 1)); ang = P.Theta(:); full = d2 <= P.dPhi / 2 + 1e-9 && j2 ~= j1;
    if full, idx = [idx; sub2ind([nT nP], (nT:-1:1).', j2 * ones(nT, 1))]; ang = [ang; 360 - flipud(P.Theta(:))]; end
    fixed = P.Phi(j1); symbol = 'φ'; step = P.dTheta;
end
[ang, u] = unique(mod(ang, 360)); idx = idx(u);
if signed, ang = mod(ang + 180, 360) - 180; [ang, o] = sort(ang); idx = idx(o); end
if full && numel(ang) * step >= 360 - 1e-6, ang(end + 1) = ang(1) + 360; idx(end + 1) = idx(1); end   % closed loop
cut = struct('angle', ang, 'idx', idx, 'fixed', fixed, 'symbol', symbol, 'xlim', util_pick(signed, [-180 180], [0 360]));
end

%% ======================================================================= derivation
function D = pat_derive(P, G, prm, K)
%PAT_DERIVE Pattern + parameters → every column and every base fact, eagerly (tens of milliseconds).
% This is the only function that reads loss, Rx mode/AR, Pt or R. Nothing downstream adds or scales.
spec = K.Cols; dB = @(x) 10 * log10(max(x, eps)); pw = @(E) abs(E).^2; Cols = struct();
if P.IsGainOnly
    names = P.Names; kinds = arrayfun(@util_colKind, names); labels = replace(names, '_', ' '); shown = true(size(names));
    for n = 1:numel(names), Cols.(names(n)) = P.G.(names(n)) + prm.GainLoss_dB * (kinds(n) == "gain"); end
    gainName = names(find(kinds == "gain", 1)); if isempty(gainName), gainName = names(1); end
    peak = met_peak(Cols.(gainName), G.PhiPeriodic, K.PeakExcessDB);
    Pol = struct('Label', "n/a", 'Pairs', struct('Circular', ["E_RCP", "E_LCP"], 'Linear', ["E_TH", "E_PH"]));
else
    s = 10^(prm.GainLoss_dB / 20); Eth = P.Eth * s; Eph = P.Eph * s; Er = pol_circular(Eth, Eph, 1); El = pol_circular(Eth, Eph, 2);
    Cols.E_Total_dB = dB(pw(Eth) + pw(Eph)); gainName = "E_Total_dB";
    peak = met_peak(Cols.E_Total_dB, G.PhiPeriodic, K.PeakExcessDB);
    % Polarisation: Ω-weighted component powers inside the main beam (≥ peak − 3 dB).
    w = G.dOmega .* (Cols.E_Total_dB >= peak.value - 3); w(~isfinite(w)) = 0;
    pwr = [sum(w .* pw(Eth), 'all'), sum(w .* pw(Eph), 'all'), sum(w .* pw(Er), 'all'), sum(w .* pw(El), 'all')];
    Pol.Pairs.Linear = ["E_TH", "E_PH"]; if pwr(2) > pwr(1), Pol.Pairs.Linear = fliplr(Pol.Pairs.Linear); end
    Pol.Pairs.Circular = ["E_RCP", "E_LCP"]; if pwr(4) > pwr(3), Pol.Pairs.Circular = fliplr(Pol.Pairs.Circular); end
    if max(pwr(3:4)) > max(pwr(1:2)), Pol.Label = "Circular (" + util_pick(pwr(3) >= pwr(4), "RHCP", "LHCP") + ")";
    else, Pol.Label = "Linear (" + util_pick(pwr(1) >= pwr(2), "Vertical", "Horizontal") + ")";
    end
    % Signed axial ratio and polarisation loss factor (wave tilt 90° from the antenna's major axis, as M7):
    % PLF = ½ + [4 rA rW + (rA²−1)(rW²−1) cos 2Δτ] / [2 (rA²+1)(rW²+1)],  rA, rW signed axial ratios (+RHCP, −LHCP)
    [Cols.AR_dB, isLin] = pol_signedAR(Er, El, K);
    sense = sign(abs(Er) - abs(El)); sense(isLin) = 0; rA = 10.^(abs(Cols.AR_dB) / 20) .* sense; rA(sense == 0) = 1e12;
    switch prm.RxMode, case "RHCP", ws = 1; case "LHCP", ws = -1; otherwise, ws = 2 * (Pol.Pairs.Circular(1) == "E_RCP") - 1; end
    rW = ws * 10^(prm.RxAR_dB / 20);
    plf = 0.5 + (4 * rA * rW + (rA.^2 - 1) * (rW^2 - 1) * cosd(180)) ./ (2 * (rA.^2 + 1) * (rW^2 + 1));
    Cols.PLF_dB = 10 * log10(min(max(plf, eps), 1));
    Cols.E_RCP_dB = dB(pw(Er)); Cols.E_LCP_dB = dB(pw(El)); Cols.Gain_PolCorrected_dB = Cols.E_Total_dB + Cols.PLF_dB;
    Cols.E_TH_dB = dB(pw(Eth)); Cols.E_PH_dB = dB(pw(Eph));
    Cols.E_TH_Phase = rad2deg(angle(Eth)); Cols.E_PH_Phase = rad2deg(angle(Eph)); Cols.E_RCP_Phase = rad2deg(angle(Er)); Cols.E_LCP_Phase = rad2deg(angle(El));
    if ~K.LinkBudgetRequiresDBi || P.Unit == "dBi"
        Cols.EIRP_dBW = prm.Pt_dBW + Cols.E_Total_dB; eirpW = 10.^(Cols.EIRP_dBW / 10);
        Cols.PFD_Wm2 = eirpW / (4 * pi * prm.R_m^2); Cols.E_RMS_Vm = sqrt(30 * eirpW) / prm.R_m;
    end
    present = ismember(string(spec(:, 1)), string(fieldnames(Cols)));
    names = string(spec(present, 1)).'; labels = string(spec(present, 2)).'; kinds = string(spec(present, 3)).'; shown = [spec{present, 4}];
end
D = struct('Names', names, 'Labels', labels, 'Kinds', kinds, 'Shown', logical(shown), 'Cols', Cols, 'Pol', Pol);
Gc = Cols.(gainName); D.Peak = peak;
[i, j] = ind2sub(size(Gc), [D.Peak.index, D.Peak.rawIndex]);
[D.Peak.theta, D.Peak.phi, D.Peak.rawTheta, D.Peak.rawPhi] = deal(P.Theta(i(1)), P.Phi(j(1)), P.Theta(i(2)), P.Phi(j(2)));
% Boresight: principal axis whose 45° cone holds the most Ω-weighted power.
Glin = 10.^(Gc / 10); Glin(~isfinite(Glin)) = 0; e = zeros(1, 6);
for a = 1:6, m = cov_coneMask(P, K.Axes.theta(a), K.Axes.phi(a), K.ConeDeg); e(a) = sum(Glin(m) .* G.dOmega(m)); end
[~, D.Boresight] = max(e); aT = K.Axes.theta(D.Boresight); aP = K.Axes.phi(D.Boresight);
D.Planes.E = struct('type', "Theta", 'value', aP);
D.Planes.H = util_pick(aT == 90, struct('type', "Phi", 'value', 90), struct('type', "Theta", 'value', 90));
% Metrics, on the gain column only. Efficiency and front-to-back need a full sphere and absolute gain.
cE = geo_cut(P, G, D.Planes.E.type, D.Planes.E.value, false); cH = geo_cut(P, G, D.Planes.H.type, D.Planes.H.value, false);
Ptot = sum(Glin .* G.dOmega, 'all'); dir = 10 * log10(4 * pi * 10^(D.Peak.value / 10) / max(Ptot, eps));
eff = NaN; if G.IsFullSphere && (P.Unit == "dBi" || ~K.LinkBudgetRequiresDBi), eff = 100 * Ptot / (4 * pi); end
fb = NaN;
if G.IsFullSphere
    [~, ib] = min(abs(P.Theta - (180 - D.Peak.theta))); [~, jb] = min(abs(mod(P.Phi - D.Peak.phi - 180 + 180, 360) - 180)); fb = D.Peak.value - Gc(ib, jb);
end
ar = NaN; if isfield(Cols, 'AR_dB'), ar = Cols.AR_dB(D.Peak.index); end
D.Metrics = struct('HPBW_EPlane_deg', met_hpbw(cE.angle, Gc(cE.idx)), 'HPBW_HPlane_deg', met_hpbw(cH.angle, Gc(cH.idx)), ...
    'FrontBack_dB', fb, 'PeakDirectivity_dB', dir, 'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', ar);
end

function Kp = met_peak(C, periodic, excessDB)
%MET_PEAK Spatial-isolation peak policy: a sample is a spike iff it exceeds every grid neighbour by more
% than EXCESSDB (4-neighbours, φ-wrap when periodic). Effective peak = highest non-spike sample.
[n, m] = size(C); nb = -inf(n, m);
if n > 1, nb(2:n, :) = max(nb(2:n, :), C(1:n - 1, :)); nb(1:n - 1, :) = max(nb(1:n - 1, :), C(2:n, :)); end
if m > 1
    if periodic, L = circshift(C, 1, 2); R = circshift(C, -1, 2); else, L = [-inf(n, 1), C(:, 1:m - 1)]; R = [C(:, 2:m), -inf(n, 1)]; end
    nb = max(nb, max(L, R));
end
Kp.spike = isfinite(C) & (C - nb > excessDB);
[Kp.rawValue, Kp.rawIndex] = max(C(:), [], 'omitnan');
cand = C; cand(Kp.spike) = -Inf; [Kp.value, Kp.index] = max(cand(:), [], 'omitnan');
Kp.wasAdjusted = Kp.spike(Kp.rawIndex); Kp.spikeCount = nnz(Kp.spike);
end

function [bw, lo, hi] = met_hpbw(ang, g)
%MET_HPBW Half-power beamwidth of a circular cut: first −3 dB crossings on each side of the cut maximum,
% linearly interpolated, wrap-aware.
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(g); ang = ang(ok); g = g(ok);
if numel(g) < 3, return; end
[pk, at] = max(g); [rel, o] = sort(mod(ang - ang(at) + 180, 360) - 180); g = g(o); half = pk - 3;
l = find(rel < 0 & g <= half, 1, 'last'); r = find(rel > 0 & g <= half, 1, 'first');
if isempty(l) || isempty(r) || l + 1 > numel(g) || r - 1 < 1, return; end
x = @(a, b) rel(a) + (rel(b) - rel(a)) * (half - g(a)) / (g(b) - g(a));
lc = x(l, l + 1); rc = x(r, r - 1); if ~isfinite(lc) || ~isfinite(rc), return; end
lo = ang(at) + lc; hi = ang(at) + rc; bw = rc - lc;
end

function E = pol_circular(Eth, Eph, which)
%POL_CIRCULAR RHCP (1) / LHCP (2) component of E = Eθ θ̂ + Eφ φ̂ under e^{+jωt}, (θ̂, φ̂, r̂) right-handed:
% ê_R = (θ̂ − jφ̂)/√2 ⇒ E_R = E·ê_R* = (Eθ + jEφ)/√2, E_L = (Eθ − jEφ)/√2. Check: E = ê_R ⇒ E_R = 1, E_L = 0.
if which == 1, E = (Eth + 1i * Eph) / sqrt(2); else, E = (Eth - 1i * Eph) / sqrt(2); end
end

function [Eth, Eph] = pol_fromCircular(Er, El)
Eth = (Er + El) / sqrt(2); Eph = (Er - El) / (1i * sqrt(2));
end

function [AR, isLinear] = pol_signedAR(Er, El, K)
%POL_SIGNEDAR Signed axial ratio in dB: + RHCP sense, − LHCP sense; numerically equal components are the
% linear limit and take the APAT floor (−100 dB) so the signed display stays continuous.
r = abs(Er); l = abs(El); d = r - l;
isLinear = isfinite(d) & abs(d) <= eps * max(r + l, 1);
AR = min(20 * log10((r + l) ./ max(abs(d), eps)), K.ARCapDB) .* sign(d);
AR(isLinear) = K.ARFloorDB;
end

%% ======================================================================= coverage kernels
function cov = cov_curve(C, dOmega, mask, T)
%COV_CURVE Coverage(T) = 100·Ω_R(C > T)/Ω_R,  Ω_R(C > T) = Σ_{(i,j)∈R, C(i,j) > T} ΔΩ(i,j)   (strict ">").
v = mask & isfinite(C); g = C(v); w = dOmega(v); Omega = sum(w); cov = zeros(size(T));
if Omega <= 0, return; end
for k = 1:numel(T), cov(k) = 100 * sum(w(g > T(k))) / Omega; end       % the definition, O(N) memory
end

function m = cov_coneMask(P, thC, phC, alphaDeg)
%COV_CONEMASK (i,j) ∈ cone ⇔ cos γ ≥ cos α,  cos γ = cos θᵢ cos θc + sin θᵢ sin θc cos(φⱼ − φc).
m = cosd(P.Theta(:)) * cosd(thC) + sind(P.Theta(:)) * sind(thC) .* cosd(P.Phi(:).' - phC) >= cosd(alphaDeg) - 1e-12;
end

function T = cov_thresholds(tMin, tMax, step)
n = max(round((tMax - tMin) / step), 0); T = tMin + (0:n).' * step;     % counting, not accumulation
end

function c = cov_at(job, t)
c = NaN(size(t)); if numel(job.T) > 1, c = interp1(job.T, job.cov, t, 'linear', NaN); end
end

function t = thr_at(job, c)
%THR_AT Inverse read of a coverage curve; plateaus resolve to their upper threshold.
[cu, iu] = unique(job.cov, 'last'); t = NaN(size(c));
if numel(cu) > 1, t = interp1(cu, job.T(iu), c, 'linear', NaN); end
end

%% ======================================================================= utilities
function s = util_fmtNumber(v, prec)
%UTIL_FMTNUMBER Compact (≤ 2 decimals, no trailing zeros, never "-0") or fixed precision.
if ~(isscalar(v) && isnumeric(v) && isfinite(v)), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v), {'0+$', '\.$'}, ''); else, s = sprintf('%.*f', prec, v); end
if strcmp(s, '-0'), s = '0'; end
end

function b = util_presetRange(peak)
if ~isfinite(peak), b = [-50 0]; return; end
top = ceil(peak / 5) * 5; b = min(max([top - 50, top], -250), 100);
end

function [lim, map] = util_theme(kind, limits)
persistent jetMap arMap
if isempty(jetMap), jetMap = jet(256); arMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
if isscalar(kind) && kind == "ar", lim = [-30 30]; map = arMap; else, lim = limits; map = jetMap; end
end

function t = util_ticks(lim, step)
t = ceil(lim(1) / step) * step:step:floor(lim(2) / step) * step;
t = unique([lim(1), t, lim(2)]); if numel(t) > 60, t = lim; end
end

function t = util_span(axisValues, step)
t = floor(min(axisValues) / step) * step:step:ceil(max(axisValues) / step) * step;
end

function out = util_pick(cond, a, b)
if cond, out = a; else, out = b; end
end

function xy = util_display(thetaPhi, M)
%UTIL_DISPLAY Canonical [θ φ] → display [x=φ, y=θ] under the map's convention.
x = thetaPhi(2); if M.SignedPhi && x >= 180, x = x - 360; end
y = thetaPhi(1); if M.Elevation, y = 90 - y; end
xy = [x, y];
end

function a = util_wrap(a, signed)
if signed, a = mod(a + 180, 360) - 180; else, a = mod(a, 360); end
end

function v = util_cutCanonical(cfg, shown)
%UTIL_CUTCANONICAL Cut-value spinner (display convention) → canonical fixed angle.
if ~isfield(cfg, 'CutType'), v = shown; return; end
if cfg.CutType == "Phi", v = shown; if cfg.Elevation, v = 90 - shown; end
else, v = mod(shown, 360);
end
end

function kind = util_colKind(name)
key = regexprep(lower(string(name)), '[^a-z0-9]', '');
if key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio"), kind = "ar";
elseif contains(key, "phase") || contains(key, "deg"), kind = "phase";
else, kind = "gain";
end
end

function step = util_assertUniform(axisValues, name)
%UTIL_ASSERTUNIFORM Uniform-grid contract (I1): errors once, naming the axis and the gap range.
d = diff(axisValues(:)); step = NaN; if isempty(d), return; end
step = median(d);
if any(abs(d - step) > 1e-6)
    error('APAT:NonUniformGrid', '%s axis is not uniform: steps range %.6g°..%.6g° (APAT requires uniform grids).', name, min(d), max(d));
end
end

function M = util_grid(v, lin, sz)
M = nan(sz); M(lin) = v;
end

function B = util_block(th, ph, Eth, Eph)
B = table(th(:), ph(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function util_writeTable(T, fp)
if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
end

function h = ui_place(h, row, col, varargin)
h.Layout.Row = row; h.Layout.Column = col; if ~isempty(varargin), set(h, varargin{:}); end
end

function h = ui_label(parent, text, row, col, varargin)
h = ui_place(uilabel(parent, 'Text', text, 'HorizontalAlignment', 'right', varargin{:}), row, col);
end

function h = ui_textFormatDropdown(parent, callback)
h = uidropdown(parent, 'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
    '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', '6: POL1=RCP, POL2=LCP — real, imaginary', ...
    '7: POL1=LCP, POL2=RCP — real, imaginary'}, 'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', ...
    'rcp_lcp_reim', 'lcp_rcp_reim'}, 'Value', 'gain', 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'ValueChangedFcn', callback);
end