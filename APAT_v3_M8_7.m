classdef APAT_v3_M8_7 < matlab.apps.AppBase  %1690-lines % ISSUE: error "Unrecognized method, property, or field 'DataTipTemplate' for class 'matlab.graphics.primitive.Line'. (APAT_v3_M8_7.placeMarker line 532)"
% APAT v3 Milestone 7 — grid-native pattern, one derivation function, one pattern registry, one dispatcher.
%
%   SOURCE ─► PATTERN(Rev) ─► GEOMETRY ─► DERIVED(Rev, Params)      all stored in Pats(k); Main tab = Pats(Main)
%      │                                        ├─► PLOTS / CUTS / TABLES / METADATA (+Map)
%      │                                        └─► COVERAGE job = curve {T, cov} (tree node stores k)
%   VIEW (readConfig) ─► MAP (geo_displayMap) ─► column permutation / axes / labels — touches nothing above.
%
%   Rule: widgets are read only in readConfig/readCoverageConfig; numerics never see a widget; widgets are written
%   only by apply*/render* functions. Every callback is one expression: @(~,~) app.on("scope").
%
%   Retained-graphics invariant (M8.8): every "maybe-not-yet-created" handle slot (Gfx.Full(k).Surface/Marker/Tip) holds a
%   gobjects(1) placeholder, never gobjects(0), so isgraphics(slot) is always a logical SCALAR and can guard && / if directly.
%   Cache identity: every built registry entry carries a unique Stamp; render/table cache keys are derived from app.dataKey(e).

    properties (GetAccess = public, SetAccess = private)
        isClosing logical = false
        Perf struct = struct()        % last timed action {AppVersion, Operation, Stages, TotalSeconds} (also in base workspace)
    end

    properties (Access = public)
        UIFigure; GridLayout; TabGroup; Tab1_Single; Single_Grid
        Single_panelParam; Single_gridPanel_Param; Single_DropDown_FFD; FFDFreqDropDownLabel
        Single_DropDown_TextFormat; TextFormatLabel; Single_Export_UAN; Single_Button_ResetParams
        Single_Export_Output; Single_Button_Coverage; Single_Button_Process; Single_DropDown_step
        Single_DropDown_R; Single_Spinner_R; DistanceLabel; Single_Button_Load
        Single_DropDown_Pt; Single_Spinner_Pt; TransmitPowerLabel; Single_Spinner_Loss; LossindBLabel
        Single_Spinner_Rw; IncidentWaveARRwPLFLabel; Single_DropDown_RxPol; RxPolLabel
        Single_EditField_Path; InputPatternLabel; Single_StatusBar
        Single_Panel_plotControl; Single_gridPanel_Ctrl; View3DLabel; Single_DropDown_3DView
        Singel_CheckBox_overlayCut; Single_CheckBox_POB; Single_CheckBox_HPBWBounds
        Single_Switch_EHplane; Single_Switch_AngularSpan; Single_Switch_ThetaSpan
        CutvalueSpinnerLabel; Single_Label_Clim; Single_Button_Clim; Single_Plot_Cstep; ColorbarstepLabel
        Single_Plot_Cmin; ColorbarminLabel; Single_Plot_Cmax; ColorbarmaxLabel
        Single_DropDown_cutValue; Single_DropDown_cutType; CutFieldBasisDropDown; CutfieldsLabel; CuttypeDropDownLabel
        Single_DropDown_Component; ComponentLabel
        Single_tabData; Single_tabDataOut; Single_gridDataOut; Single_Table_DataOut
        Single_tabDataIn; Single_gridDataIn; Single_Table_DataIn; MetadataTab; Single_gridMetadata; Single_Table_metadata
        Single_DropDown_output
        Single_Panel_Rect; Single_gridPanel_Cut; Single_tabCut; Single_tabPolarPlot; Single_Grid_Polar; Single_gridEcut
        CheckBox_Et; CheckBox_Er; CheckBox_El; Button_ExportCut; Range_Cut_Max; Range_Cut_Min; Label_HPBW; Button_HPBW; Range_Cut
        Single_tabRectPlot; Single_gridRect; Single_AxesRect
        Single_Panel_fullPattern; Single_gridPanel_full; Single_tabPlots
        Single_tabContour; Single_gridContour; Range_Ctr_Min; Range_Ctr_Max; Range_Ctr; Single_Axes_Ctr
        Single_tabCircular; Single_gridCircular; Range_Cir_Min; Range_Cir_Max; Range_Cir
        Single_tab3DSpherical; Single_grid3dSpherical; Range_3dSph_Min; Range_3dSph_Max; Range_3dSph; Single_Axes_3dSph
        Single_tab3DPolar; Single_grid3dPolar; Range_3dPol_Min; Range_3dPol_Max; Range_3dPol; Single_Axes_3dPol
        Single_tab3DRect; Single_grid3dRect; Range_3dRect_Min; Range_3dRect_Max; Range_3dRect; Single_Axes_3dRect
        Tab2_Coverage; Cov_Grid; Cov_Panel_Results; GridLayout2; Cov_Spinner_XMin; Cov_Spinner_XMax; Cov_Spinner_XRange
        Cov_Tabel; Cov_Tree; Cov_TreeNode_Results; Cov_Axes; Cov_StatusBar; Cov_Panel_Param; Cov_gridPanel_Parm
        Cov_DropDown_OrientationLabel; Cov_DropDown_TextFormat; Cov_TextFormatLabel; Cov_Button_queryThresh; Cov_Button_queryCov
        Cov_DropDown_Component; Cov_DropDown_ComponentLabel; Cov_Spinner_queryThresh; Cov_QueryThresholdLabel
        Cov_Spinner_queryCov; Cov_QueryCoverageLabel; Cov_Button_toMain; Cov_Button_Clear
        Cov_Spinner_ConeAng; ConeAngleLabel; Cov_Spinner_ConePH; ConeLabel; Cov_Spinner_ConeTH; ConeSpinnerLabel
        Cov_Spinner_Step; StepdBSpinnerLabel; Cov_Spinner_ThreshMax; ThresholdMaxdBSpinnerLabel
        Cov_Spinner_ThreshMin; ThresholdMindBSpinnerLabel; Cov_Button_Export; Cov_Button_Reset; Cov_Button_computeCov
        Cov_Button_Load; Cov_EditField_filePath; AntennaPatternEditFieldLabel; Cov_DropDown_Orientation
        Cov_ButtonGroup_CovType; Cov_ButtonGroup_Btn_Conical; Cov_ButtonGroup_Btn_Spherical
        Single_paxCut; Single_paxPattern
    end

    properties (Access = private)
        Pats = struct('Name', {}, 'Path', {}, 'Source', {}, 'Pattern', {}, 'Geometry', {}, 'Derived', {}, 'Params', {}, 'Native', {}, 'Stamp', {})
        Main double = 0                % index into Pats shown on the Main tab (0 = nothing loaded)
        View struct = struct()         % last readConfig() result (display choices + Params)
        Map struct = struct()          % geo_displayMap(): column permutation + axis vectors for the display convention
        CompPeak struct = struct()     % met_peak of the displayed component (== Derived.Peak for total gain)
        Range struct = struct('full', [-40 10], 'cut', [-40 10], 'cov', [-40 10], 'covX', [-40 10], ...
            'Auto', struct('full', true, 'cut', true, 'cov', true, 'covX', true))
        OutMask logical = logical([])  % Results-table column filter (one flag per Derived column)
        BasisAuto logical = true       % cut basis follows the detected polarisation until the user picks one
        RawShown logical = false
        Gfx struct = struct()          % retained graphics: Full(k), Cut, Menu, Maps, TableKey
        Status struct = struct('main', '', 'cov', '')
        StatusTimer = []
        Dlg = []
        Busy logical = false
        PerfRun = []
        CovId double = 0
        CovQuery = []                  % query controls handled together
        Defaults struct = struct()
    end

    properties (Constant)
        ReleaseName = 'APAT v3 Milestone 8'
        PrincipalAxes = struct('labels', {{'+Z', '-Z', '+X', '-X', '+Y', '-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        PeakExcessDB = 6               % a sample is a spike iff it exceeds every grid neighbour by more than this (I5)
        ARLimits = [-30 30]            % signed axial-ratio colour scale
        HardRange = [-250 100]         % absolute limits of every dB range control
        DistanceFloorM = 1e-12
        %        name                    label             kind      hidden-by-default
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
    end

    % ======================================================= LIFECYCLE =======================================================
    methods (Access = public)
        function app = APAT_v3_M8_7
            createComponents(app); registerApp(app, app.UIFigure); runStartupFcn(app, @startupFcn)
            if nargout == 0, clear app; end
        end

        function closeRequest(app, ~), app.delete(); end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true;
            if ~isempty(app.StatusTimer) && isvalid(app.StatusTimer), stop(app.StatusTimer); delete(app.StatusTimer); end
            if ~isempty(app.Dlg) && isvalid(app.Dlg), delete(app.Dlg); end
            if ~isempty(app.UIFigure) && isgraphics(app.UIFigure), delete(app.UIFigure); end
        end
    end

    methods (Access = private)
        function startupFcn(app)
            app.StatusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3);
            % One shared context menu; the opening event records the right-clicked axes so "Delete DataTips" acts on that axes only.
            app.Gfx.Menu = uicontextmenu(app.UIFigure, 'ContextMenuOpeningFcn', @(c, ev) set(c, 'UserData', ancestor(ev.ContextObject, {'axes', 'polaraxes'})));
            uimenu(app.Gfx.Menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(m, ~) delete(findall(m.Parent.UserData, 'Type', 'datatip')));
            app.Gfx.Maps = struct('gain', jet(256), 'ar', interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)));
            app.Gfx.TableKey = '';
            % Five full-pattern views behind one renderer: axes, range controls, kind and camera per row.
            % Surface/Marker/Tip start as gobjects(1) placeholders (isgraphics == scalar false), never gobjects(0) (isgraphics == []).
            axesList = {app.Single_Axes_Ctr, app.Single_paxPattern, app.Single_Axes_3dSph, app.Single_Axes_3dPol, app.Single_Axes_3dRect};
            app.Gfx.Full = struct('Tab', {app.Single_tabContour, app.Single_tabCircular, app.Single_tab3DSpherical, app.Single_tab3DPolar, app.Single_tab3DRect}, ...
                'Axes', axesList, 'Kind', {"contour", "fisheye", "sphere", "polar", "rect"}, 'Camera', {[], [], [135 25], [135 25], [-35 35]}, ...
                'Surface', gobjects(1), 'Marker', gobjects(1), 'Tip', gobjects(1), 'Colorbar', gobjects(1), 'Key', '');
            for k = 1:5
                ax = axesList{k}; ax.ContextMenu = app.Gfx.Menu; app.Gfx.Full(k).Colorbar = colorbar(ax);
                if k == 2, hold(ax, 'on'); continue; end
                enableDefaultInteractivity(ax);
                if k >= 3, ax.Interactions = [rotateInteraction, dataTipInteraction]; else, ax.Interactions = [zoomInteraction, dataTipInteraction]; end
                if k == 3 || k == 4     % fixed camera box and the XYZ triad, once
                    set(ax, 'Projection', 'orthographic', 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1], 'Visible', 'off');
                    hold(ax, 'on'); c = {[0.85 0.1 0.1], [0.1 0.6 0.1], [0.1 0.2 0.9]}; t = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'}; e = 1.35*eye(3);
                    for a = 1:3, quiver3(ax, 0, 0, 0, e(a, 1), e(a, 2), e(a, 3), 0, 'Color', c{a}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25); text(ax, 1.12*e(a, 1), 1.12*e(a, 2), 1.12*e(a, 3), t{a}, 'Color', c{a}, 'FontWeight', 'bold'); end
                end
            end
            set([app.Single_AxesRect, app.Cov_Axes, app.Single_paxCut], 'ContextMenu', app.Gfx.Menu); hold(app.Single_paxCut, 'on'); hold(app.Single_AxesRect, 'on');
            enableDefaultInteractivity(app.Single_AxesRect); app.Single_AxesRect.Interactions = [zoomInteraction, dataTipInteraction];
            % Cut graphics created once: three traces + peak marker per axes, two overlays, HPBW bound markers.
            co = app.Single_AxesRect.ColorOrder; g = struct('Polar', gobjects(1, 3), 'Rect', gobjects(1, 3), 'Overlay', gobjects(1, 2), 'PolarReg', gobjects(0), 'RectReg', gobjects(0));
            for t = 1:3
                g.Polar(t) = polarplot(app.Single_paxCut, NaN, NaN, 'LineWidth', 1.4, 'Color', co(t, :), 'Visible', 'off');
                g.Rect(t) = plot(app.Single_AxesRect, NaN, NaN, 'LineWidth', 1.4, 'Color', co(t, :), 'Visible', 'off');
            end
            g.PolarPk = polarplot(app.Single_paxCut, NaN, NaN, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off', 'Visible', 'off');
            g.RectPk = plot(app.Single_AxesRect, NaN, NaN, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off', 'Visible', 'off');
            g.PolarBd = polarplot(app.Single_paxCut, [NaN NaN], [NaN NaN], 'o', 'Color', '#D95319', 'MarkerFaceColor', '#D95319', 'HandleVisibility', 'off', 'Visible', 'off');
            g.RectBd = plot(app.Single_AxesRect, [NaN NaN], [NaN NaN], 'o', 'Color', '#D95319', 'MarkerFaceColor', '#D95319', 'HandleVisibility', 'off', 'Visible', 'off');
            for a = 1:2, g.Overlay(a) = plot3(axesList{2 + a}, NaN, NaN, NaN, 'k', 'LineWidth', 1.6, 'Visible', 'off'); end
            app.Gfx.Cut = g;
            app.CovQuery = [app.Cov_QueryCoverageLabel, app.Cov_Spinner_queryCov, app.Cov_Button_queryCov, app.Cov_QueryThresholdLabel, app.Cov_Spinner_queryThresh, app.Cov_Button_queryThresh];
            hold(app.Cov_Axes, 'on'); grid(app.Cov_Axes, 'on'); ylim(app.Cov_Axes, [0 100]); set(app.Cov_Axes, 'Box', 'on', 'Layer', 'top');
            V0 = app.readConfig(); app.Defaults = V0.Params;
            for grp = ["full" "cut" "cov" "covX"], app.applyRange(grp, app.Range.(grp)); end
            app.setStatus(app.Single_StatusBar, 'Ready -- load an antenna pattern file to begin 🚀', false);
            app.setStatus(app.Cov_StatusBar, 'Ready 🚀', false);
            app.applyVisibility();
        end

        function setBusy(app, tf), if ~app.isClosing, app.Busy = tf; end, end

        function checkCancelled(app)
            if ~isempty(app.Dlg) && isvalid(app.Dlg) && app.Dlg.CancelRequested, error('APAT:Cancelled', 'Operation cancelled by user.'); end
        end

        function showError(app, err, titleText)
            if app.isClosing, return; end
            where = ''; if ~isempty(err.stack), where = sprintf('\n(%s line %d)', err.stack(1).name, err.stack(1).line); end
            uialert(app.UIFigure, [err.message where], char(titleText), 'Icon', 'error');
        end

        function setStatus(app, label, msg, transient)
            %SETSTATUS One reusable timer; the persistent message lives in app.Status.(label.Tag), not in the widget.
            if app.isClosing, return; end
            stop(app.StatusTimer); label.Text = char(msg);
            if ~transient, app.Status.(label.Tag) = char(msg); return; end
            app.StatusTimer.TimerFcn = @(~, ~) set(label, 'Text', app.Status.(label.Tag)); start(app.StatusTimer);
        end

        function perf(app, stage)
            %PERF perf("begin <op>") | perf("<stage>") | perf("end") — same record shape and destination as M7 for side-by-side timing.
            if startsWith(stage, "begin"), app.PerfRun = struct('Op', extractAfter(stage, 6), 'T0', tic, 'T', tic, 'Rows', {cell(0, 2)}); return; end
            if isempty(app.PerfRun), return; end
            app.PerfRun.Rows(end + 1, :) = {char(stage), toc(app.PerfRun.T)}; app.PerfRun.T = tic;
            if stage ~= "end", return; end
            app.Perf = struct('AppVersion', class(app), 'Operation', app.PerfRun.Op, 'Stages', cell2table(app.PerfRun.Rows, 'VariableNames', {'Stage', 'Seconds'}), 'TotalSeconds', toc(app.PerfRun.T0));
            assignin('base', matlab.lang.makeValidName("Perf_" + class(app)), app.Perf); app.PerfRun = [];
        end

        % ================================================ ORCHESTRATION ================================================
        function e = pat(app), e = app.Pats(app.Main); end

        function C = col(app, name)
            %COL Matrix of the selected (or named) column of the Main pattern.
            if nargin < 2, name = app.View.Component; end
            e = app.pat(); C = e.Derived.Cols.(name);
        end

        function V = readConfig(app)
            %READCONFIG The only reader of Main-tab widget values (I11): display choices (View) and physics inputs (Params).
            V.Component = string(app.Single_DropDown_Component.Value);
            V.SignedPhi = strcmp(app.Single_Switch_AngularSpan.Value, '-180° to 180°');
            V.Elevation = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°');
            V.CutType = string(app.Single_DropDown_cutType.Value); v = app.Single_DropDown_cutValue.Value;
            if V.CutType == "Phi" && V.Elevation, v = 90 - v; elseif V.CutType == "Theta", v = mod(v, 360); end
            V.CutValue = v;                                                   % display convention → canonical angle (I8)
            V.Basis = string(app.CutFieldBasisDropDown.Value);
            V.Traces = logical([app.CheckBox_Et.Value, app.CheckBox_Er.Value, app.CheckBox_El.Value]);
            V.HPBW = app.Button_HPBW.Value; V.HPBWBounds = app.Single_CheckBox_HPBWBounds.Value;
            V.POB = app.Single_CheckBox_POB.Value; V.Overlay = app.Singel_CheckBox_overlayCut.Value;
            V.OneDegree = numel(app.Single_DropDown_step.Items) == 2 && strcmp(app.Single_DropDown_step.Value, app.Single_DropDown_step.Items{2});
            V.FreqIndex = max([1, find(strcmp(app.Single_DropDown_FFD.Items, app.Single_DropDown_FFD.Value), 1)]);
            V.TextFormat = string(app.Single_DropDown_TextFormat.Value); V.Camera = string(app.Single_DropDown_3DView.Value);
            V.CStep = app.Single_Plot_Cstep.Value;
            p.L = app.Single_Spinner_Loss.Value; p.RxMode = string(app.Single_DropDown_RxPol.Value); p.RxAR_dB = app.Single_Spinner_Rw.Value;
            pt = app.Single_Spinner_Pt.Value;
            switch app.Single_DropDown_Pt.Value, case 'dBm', pt = pt - 30; case 'Watts', pt = 10*log10(max(pt, eps)); end
            p.Pt_dBW = pt; p.R_m = max(app.Single_Spinner_R.Value, app.DistanceFloorM) * (1 + 999*strcmp(app.Single_DropDown_R.Value, 'km'));
            V.Params = p;
        end

        function on(app, scope, dlgTitle)
            %ON Guard for every user action: busy flag, try/catch, cancellation, timing. UPDATE commits state only when complete (I13).
            if app.Busy || app.isClosing, return; end
            app.Busy = true; cleanBusy = onCleanup(@() app.setBusy(false)); app.perf("begin " + scope);
            if nargin > 2
                app.Dlg = uiprogressdlg(app.UIFigure, 'Title', dlgTitle, 'Message', 'Working...', 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
                cleanDlg = onCleanup(@() delete(app.Dlg)); drawnow
            end
            try
                app.update(scope); drawnow limitrate
            catch err
                if strcmp(err.identifier, 'APAT:Cancelled'), app.setStatus(app.Single_StatusBar, 'Operation cancelled.', true);
                else, app.showError(err, "Error (" + scope + ")"); end
            end
            app.perf("end");
        end

        function e = buildEntry(app, S, name, path, oneDegree, freqIndex, prm)
            %BUILDENTRY Source → Pattern → (Resample) → Geometry → Derived, returned as one registry entry (build-then-commit).
            P = pat_build(S, freqIndex); native = [P.dTheta, P.dPhi]; app.perf("Build pattern"); app.checkCancelled();
            if oneDegree && any(abs(native - 1) > 1e-9), P = pat_resample(P, 1); app.perf("Resample"); app.checkCancelled(); end
            G = geo_build(P); D = pat_derive(P, G, prm); app.perf("Derive");
            e = struct('Name', name, 'Path', path, 'Source', S, 'Pattern', P, 'Geometry', G, 'Derived', D, 'Params', prm, 'Native', native, 'Stamp', tic);   % Stamp: unique per build
        end

        function k = dataKey(~, e)
            %DATAKEY Identity of the data behind every cached render: the build (file, block, step) and the derivation parameters.
            k = {e.Stamp, e.Params};
        end

        function update(app, scope)
            %UPDATE The dispatcher. Ladder: source ⊃ freq ⊃ step ⊃ params ⊃ {component, span, cut, range, annot, camera}.
            %   Recompute only the invalidation radius, then render the visible full-pattern tab, the cut, tables and metadata.
            if app.Main == 0, app.applyVisibility(); return; end
            V = app.readConfig(); k = app.Main; e = app.Pats(k);
            if ismember(scope, ["source" "freq" "step"])                       % "source": entry already built and committed by loadMain
                if scope ~= "source", app.Pats(k) = app.buildEntry(e.Source, e.Name, e.Path, V.OneDegree, V.FreqIndex, V.Params); end   % one commit
                app.applyChoices(scope == "source"); V = app.readConfig(); e = app.Pats(k);
                for grp = ["full" "cut"], if app.Range.Auto.(grp), app.applyRange(grp, util_presetRange(e.Derived.Peak.value)); end, end
            elseif scope == "params" && ~isequal(e.Params, V.Params)
                e.Derived = pat_derive(e.Pattern, e.Geometry, V.Params); e.Params = V.Params; app.Pats(k) = e; app.perf("Derive");
            end
            if scope == "eh" || scope == "source", app.applyPlane(e.Derived.Planes); V = app.readConfig(); end   % E/H switch, or a fresh load
            if ismember(scope, ["source" "freq" "step" "span" "eh" "cut"])
                canon = V.CutValue; if scope == "span" && isfield(app.View, 'CutValue'), canon = app.View.CutValue; end
                app.applyCutDomain(e.Pattern, V, canon); V = app.readConfig();
            end
            app.View = V; app.Map = geo_displayMap(e.Pattern, e.Geometry, V);
            app.CompPeak = e.Derived.Peak;
            if V.Component ~= e.Derived.TotalName, app.CompPeak = met_peak(app.col(), e.Geometry.PhiPeriodic, app.PeakExcessDB); end
            app.renderFull(); app.renderCut(); app.renderTables(); app.renderMetadata(); app.perf("Render");
            if ismember(scope, ["source" "freq" "step" "params" "component"])
                pk = app.CompPeak; [r, c] = ind2sub(size(app.col()), pk.index); what = 'POB';
                if V.Component ~= e.Derived.TotalName, what = ['Peak of ' char(app.compLabel())]; end
                msg = sprintf('Pattern: <b>%s</b> | %s <b>%s %s</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)', e.Name, what, util_fmtNumber(pk.value, 2), ...
                    e.Pattern.Meta.UnitLabel, util_fmtNumber(e.Pattern.Theta(r)), util_fmtNumber(e.Pattern.Phi(c)));
                if ~e.Pattern.IsGainOnly, msg = sprintf('%s | Polarization <b>%s</b>', msg, e.Derived.Pol.label); end
                app.setStatus(app.Single_StatusBar, msg, false);
            end
            app.applyVisibility();
        end

        function applyChoices(app, newSource)
            %APPLYCHOICES The only writer of data-derived Items/ItemsData (I11): component lists, step choice, block list, filter.
            e = app.pat(); P = e.Pattern; [names, labels] = app.componentList(e.Derived);
            dd = app.Single_DropDown_Component; prev = string(dd.Value); [dd.Items, dd.ItemsData] = deal(cellstr(labels), cellstr(names));
            if ~any(names == prev), prev = e.Derived.TotalName; end
            dd.Value = char(prev);
            one = ['STEP: 1' char(176)]; nat = sprintf('STEP: %g%c', max(e.Native), char(176)); canon = all(abs(e.Native - 1) < 1e-9);
            sd = app.Single_DropDown_step; keepOne = ~newSource && numel(sd.Items) == 2 && strcmp(sd.Value, one);
            if canon, sd.Items = {one}; else, sd.Items = {nat, one}; end
            sd.Value = sd.Items{1 + (keepOne && ~canon)};
            fd = app.Single_DropDown_FFD; nb = numel(e.Source.Blocks); f = e.Source.Freqs(1:nb);
            items = compose('Pattern %d: %.4g GHz', [(1:nb).', f(:)/1e9]); items(~isfinite(f)) = compose('Pattern %d', find(~isfinite(f(:))));
            fd.Items = cellstr(items); if ~ismember(fd.Value, fd.Items), fd.Value = fd.Items{1}; end
            if newSource && app.BasisAuto && ~P.IsGainOnly
                if startsWith(e.Derived.Pol.label, 'Linear'), app.CutFieldBasisDropDown.Value = 'Linear'; else, app.CutFieldBasisDropDown.Value = 'Circular'; end
            end
            colNames = fieldnames(e.Derived.Cols); od = app.Single_DropDown_output;
            if ~isequal(regexprep(od.Items(2:end), '^✓ ?', ''), colNames.')        % compare bare names: applyFilterStyles adds ✓ marks
                [od.Items, od.ItemsData] = deal([{'--- column filter ---'}, colNames.'], 0:numel(colNames)); od.Value = 0;
                app.OutMask = ~cellfun(@(n) app.hiddenOf(n), colNames.');
            end
            app.applyFilterStyles();
        end

        function applyPlane(app, planes)
            %APPLYPLANE E/H switch → cut-type dropdown; the value is applied by applyCutDomain from the canonical plane angle.
            pl = planes.E; if startsWith(app.Single_Switch_EHplane.Value, 'H'), pl = planes.H; end
            app.Single_DropDown_cutType.Value = char(pl.type); app.Single_DropDown_cutValue.Limits = [-360 720]; app.Single_DropDown_cutValue.Value = pl.value;
            if pl.type == "Phi" && strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°'), app.Single_DropDown_cutValue.Value = 90 - pl.value; end
        end

        function applyCutDomain(app, P, V, canon)
            %APPLYCUTDOMAIN Cut-value spinner limits/step/value in the display convention (D40, D46); CANON = canonical angle to show.
            if V.CutType == "Phi", dom = P.Theta; step = P.dTheta; if V.Elevation, dom = 90 - dom; canon = 90 - canon; end
            else, dom = P.Phi; step = P.dPhi; if V.SignedPhi, dom(dom >= 180) = dom(dom >= 180) - 360; canon = mod(canon + 180, 360) - 180; end
            end
            dom = sort(dom); [~, i] = min(abs(dom - canon)); lim = [dom(1), dom(end)]; if diff(lim) <= 0, lim = lim + [-1 1]; end
            sp = app.Single_DropDown_cutValue; sp.Limits = [-360 720]; set(sp, 'Value', dom(i), 'Limits', lim, 'Step', max(step, 1e-3));
        end

        function applyRange(app, group, lim, store, fromSlider)
            %APPLYRANGE One descriptor-driven range controller for the four groups; the only writer of range widgets and axes limits.
            %   A slider drag never rewrites its own travel limits (spinners are the master controls, the slider moves inside them).
            if nargin < 4, store = true; end
            if nargin < 5, fromSlider = false; end
            lim = sort(double(lim(:).')); gap = 1; if ismember(group, ["cov" "covX"]), gap = 0.1; end
            lim = [max(app.HardRange(1), lim(1)), min(app.HardRange(2), lim(2))];
            if diff(lim) < gap, lim(2) = min(app.HardRange(2), lim(1) + gap); lim(1) = min(lim(1), lim(2) - gap); end
            switch group
                case "full", sl = [app.Range_Ctr, app.Range_Cir, app.Range_3dSph, app.Range_3dPol, app.Range_3dRect];
                    mn = [app.Range_Ctr_Min, app.Range_Cir_Min, app.Range_3dSph_Min, app.Range_3dPol_Min, app.Range_3dRect_Min, app.Single_Plot_Cmin];
                    mx = [app.Range_Ctr_Max, app.Range_Cir_Max, app.Range_3dSph_Max, app.Range_3dPol_Max, app.Range_3dRect_Max, app.Single_Plot_Cmax];
                case "cut", sl = app.Range_Cut; mn = app.Range_Cut_Min; mx = app.Range_Cut_Max;
                case "cov", sl = gobjects(0); mn = app.Cov_Spinner_ThreshMin; mx = app.Cov_Spinner_ThreshMax;
                case "covX", sl = app.Cov_Spinner_XRange; mn = app.Cov_Spinner_XMin; mx = app.Cov_Spinner_XMax;
            end
            if fromSlider, set(sl, 'Value', lim);                                                          % siblings follow the dragged slider
            else, set(sl, 'Limits', app.HardRange, 'Value', lim); set(sl, 'Limits', lim); end              % widen, set, then tighten the travel
            set(mn, 'Limits', [app.HardRange(1), lim(2) - gap], 'Value', lim(1)); set(mx, 'Limits', [lim(1) + gap, app.HardRange(2)], 'Value', lim(2));
            if store, app.Range.(group) = lim; end
            if group == "covX", set(app.Cov_Axes, 'XLimMode', 'manual', 'XLim', lim); end
            if group == "cut" && app.Main > 0, set(app.Single_paxCut, 'RLim', lim, 'RTick', lim(1):5:lim(2)); set(app.Single_AxesRect, 'YLim', lim); end
        end

        function onRange(app, group, which, value)
            %ONRANGE Slider (which = 0) or min/max spinner (1/2) edit of one group; a user edit switches the group's Auto preset off.
            if app.Busy, return; end
            lim = app.Range.(group); if group == "full" && app.isAR(), lim = app.ARLimits; end
            if which == 0, lim = value; else, lim(which) = value; end
            app.Range.Auto.(group) = false; isAR = group == "full" && app.isAR();
            app.applyRange(group, lim, ~isAR, which == 0);
            if ismember(group, ["full" "cut"]), app.on("range"); end
        end

        function applyVisibility(app)
            %APPLYVISIBILITY The only writer of Visible/Enable (I11), computed from state; it never calls numerics (D53).
            has = app.Main > 0; on = @(h, tf) set(h, 'Visible', tf, 'Enable', tf);
            params = [app.RxPolLabel, app.Single_DropDown_RxPol, app.IncidentWaveARRwPLFLabel, app.Single_Spinner_Rw, app.LossindBLabel, app.Single_Spinner_Loss, ...
                app.TransmitPowerLabel, app.Single_Spinner_Pt, app.Single_DropDown_Pt, app.DistanceLabel, app.Single_Spinner_R, app.Single_DropDown_R];
            set([app.Single_Panel_Rect, app.Single_Panel_fullPattern, app.Single_Panel_plotControl, app.Single_Export_Output, app.Single_Button_Coverage, ...
                app.Single_tabData, app.Single_DropDown_output, app.Single_Table_DataOut], 'Visible', has);
            if has
                e = app.pat(); field = ~e.Pattern.IsGainOnly; kinds = app.kindsInUse();
                set([app.Single_Export_UAN, app.Single_gridEcut, app.CheckBox_Et, app.CheckBox_Er, app.CheckBox_El], 'Visible', field);
                set([app.CheckBox_Er, app.CheckBox_El, app.CutFieldBasisDropDown], 'Enable', field);
                set(params(1:4), 'Visible', any(kinds == "plf")); set(params(5:6), 'Visible', any(kinds == "gain") || ~field); set(params(7:12), 'Visible', any(kinds == "link"));
                on(app.Single_DropDown_step, numel(app.Single_DropDown_step.Items) == 2);
                on([app.FFDFreqDropDownLabel, app.Single_DropDown_FFD], numel(e.Source.Blocks) > 1);
                on([app.TextFormatLabel, app.Single_DropDown_TextFormat], app.isTextFile(e.Path));
                app.Single_CheckBox_HPBWBounds.Visible = app.Button_HPBW.Value;
            else
                set([params, app.Single_Export_UAN, app.Single_DropDown_step, app.FFDFreqDropDownLabel, app.Single_DropDown_FFD, app.TextFormatLabel, ...
                    app.Single_DropDown_TextFormat, app.Single_CheckBox_HPBWBounds], 'Visible', false);
            end
            pn = app.covTarget(); hasPat = ~isempty(pn); hasJobs = ~isempty(app.covJobs()); con = app.Cov_ButtonGroup_Btn_Conical.Value;
            on(app.Cov_gridPanel_Parm.Children, hasPat);
            on([app.AntennaPatternEditFieldLabel, app.Cov_EditField_filePath, app.Cov_Button_Load, app.Cov_Button_computeCov], true);
            if hasPat, set([app.Cov_Button_Export, app.Cov_Button_Clear, app.CovQuery], 'Enable', hasJobs);
            else, on([app.CovQuery, app.Cov_Button_Reset, app.Cov_Button_Export, app.Cov_Button_Clear, app.Cov_Button_toMain], hasJobs); end
            app.Cov_Button_computeCov.Enable = hasPat; app.Cov_Button_Reset.Enable = hasPat || hasJobs;
            on([app.Cov_Spinner_ConeTH, app.Cov_Spinner_ConePH, app.Cov_Spinner_ConeAng, app.ConeSpinnerLabel, app.ConeLabel, app.ConeAngleLabel, ...
                app.Cov_DropDown_Orientation, app.Cov_DropDown_OrientationLabel], hasPat && con);
            on([app.Cov_TextFormatLabel, app.Cov_DropDown_TextFormat], hasPat && app.isTextFile(app.Cov_EditField_filePath.Value));
            app.Cov_Panel_Results.Visible = hasPat || hasJobs;
        end

        % ------------------------------------------------ small shared helpers ------------------------------------------------
        function tf = isTextFile(~, p), [~, ~, x] = fileparts(char(p)); tf = ismember(lower(x), {'.csv', '.txt', '.dat'}); end

        function [label, kind, hidden] = colMeta(app, name)
            %COLMETA Label, kind and default-hidden flag of a column: from Const.Cols, or synthesised for gain-only source columns.
            i = find(strcmp(app.Cols(:, 1), char(name)), 1);
            if ~isempty(i), label = string(app.Cols{i, 2}); kind = string(app.Cols{i, 3}); hidden = app.Cols{i, 4};
            else, label = replace(string(name), '_', ' '); kind = util_colKind(name); hidden = false; end
        end

        function k = kindOf(app, name), [~, k] = app.colMeta(name); end
        function h = hiddenOf(app, name), [~, ~, h] = app.colMeta(name); end

        function [names, labels] = componentList(app, D)
            names = string(fieldnames(D.Cols)).'; keep = false(size(names)); labels = names;
            for i = 1:numel(names), [labels(i), kind] = app.colMeta(names(i)); keep(i) = ismember(kind, ["gain" "ar" "plf" "other"]); end
            names = names(keep); labels = labels(keep);
        end

        function s = compLabel(app), s = app.colMeta(app.View.Component); end
        function tf = isAR(app), tf = app.Main > 0 && isfield(app.View, 'Component') && app.kindOf(app.View.Component) == "ar"; end

        function k = kindsInUse(app)
            %KINDSINUSE Column kinds of the selected component and of every column checked in the Results filter (drives parameter visibility).
            e = app.pat(); names = string(fieldnames(e.Derived.Cols)).'; sel = [app.View.Component, names(app.OutMask)];
            k = arrayfun(@(n) app.kindOf(n), sel);
        end

        function lim = themeLimits(app), if app.isAR(), lim = app.ARLimits; else, lim = app.Range.full; end, end

        function [names, idx] = cutColumns(app, V, e)
            %CUTCOLUMNS Trace columns of the cut in stable colour order: Total, first pair member, second pair member.
            if e.Pattern.IsGainOnly, names = V.Component; idx = 1; return; end
            if V.Basis == "Linear", pair = ["E_TH_dB" "E_PH_dB"]; else, pair = ["E_RCP_dB" "E_LCP_dB"]; end
            sel = V.Traces; if ~any(sel), sel(1) = true; end
            idx = find(sel); all3 = [e.Derived.TotalName, pair]; names = all3(idx);
        end
    end

    % ========================================================= RENDERING =========================================================
    methods (Access = private)
        function renderFull(app, k)
            %RENDERFULL Retained-mode render of full-pattern view k (default: the visible tab). Component change = one CData set.
            if nargin < 2, k = find(arrayfun(@(s) isequal(s.Tab, app.Single_tabPlots.SelectedTab), app.Gfx.Full), 1); end
            s = app.Gfx.Full(k); e = app.pat(); V = app.View; M = app.Map; lim = app.themeLimits(); C = app.col(); C = C(:, M.ColIdx);
            key = jsonencode([app.dataKey(e), {V.Component, M.Key, lim, V.CStep, V.Camera}]);
            if ~strcmp(s.Key, key)
                [X, Y, Z] = app.viewCoords(s.Kind, C, lim); unit = e.Pattern.Meta.UnitLabel; label = app.compLabel(); ax = s.Axes;
                if isgraphics(s.Surface) && isequal(size(s.Surface.CData), size(C)), set(s.Surface, 'XData', X, 'YData', Y, 'ZData', Z, 'CData', C);
                else                                            % grid changed: rebuild the surface and let placeMarker recreate the marker on top of it
                    delete([s.Surface, s.Marker, s.Tip]); [s.Marker, s.Tip] = deal(gobjects(1));
                    s.Surface = surface(ax, X, Y, Z, C, 'EdgeColor', 'none', 'FaceColor', 'interp', 'ContextMenu', app.Gfx.Menu);
                end
                map = app.Gfx.Maps.gain; if app.isAR(), map = app.Gfx.Maps.ar; end
                clim(ax, lim); colormap(ax, map); ticks = util_ticks(lim, V.CStep);
                if isempty(ticks), s.Colorbar.TicksMode = 'auto'; else, s.Colorbar.Ticks = ticks; end
                s.Colorbar.Label.String = sprintf('%s (%s)', label, unit);
                switch s.Kind
                    case {"contour", "rect"}
                        set(ax, 'XLim', [M.PhiAxis(1), M.PhiAxis(end)], 'YLim', sort([M.ThetaAxis(1), M.ThetaAxis(end)]), 'YDir', M.ThetaDir, 'Box', 'on', 'Layer', 'top');
                        if s.Kind == "contour", set(ax, 'XTick', M.PhiAxis(1):30:M.PhiAxis(end), 'YTick', min(M.ThetaAxis):15:max(M.ThetaAxis), 'DataAspectRatio', [1 1 1]); title(ax, label, 'Interpreter', 'none');
                        else, set(ax, 'XTick', M.PhiAxis(1):60:M.PhiAxis(end), 'YTick', min(M.ThetaAxis):30:max(M.ThetaAxis), 'ZLim', lim); grid(ax, 'on'); if isempty(ticks), ax.ZTickMode = 'auto'; else, ax.ZTick = ticks; end
                            zlabel(ax, sprintf('%s (%s)', label, unit), 'Interpreter', 'none'); title(ax, label, 'Interpreter', 'none'); app.applyCamera(k);
                        end
                        xlabel(ax, 'Phi (degree)'); ylabel(ax, M.ThetaLabel + " (degree)");
                    case "fisheye"
                        lbl = 0:30:330; if V.SignedPhi, lbl(lbl > 180) = lbl(lbl > 180) - 360; end
                        rl = 0:30:180; if V.Elevation, rl = 90 - rl; end
                        set(ax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', lbl), 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', rl));
                        title(ax, sprintf('%s  |  r=θ, angle=φ', label), 'Interpreter', 'none', 'FontSize', 9);
                    otherwise
                        title(ax, sprintf('%s  |  θ: %s  |  φ: %s', label, app.Single_Switch_ThetaSpan.Value, app.Single_Switch_AngularSpan.Value), 'Interpreter', 'none'); app.applyCamera(k);
                end
                [PH, TH] = meshgrid(M.PhiAxis, M.ThetaAxis);
                try
                    s.Surface.DataTipTemplate.DataTipRows = [dataTipTextRow(M.ThetaLabel, TH, '%.3g°'), dataTipTextRow("Phi", PH, '%.3g°'), dataTipTextRow(label, C, ['%.3g ' char(unit)])];
                catch err
                    app.Status.Note = err.message;              % datatip template unsupported on this graphics object; plot is unaffected
                end
                s.Key = key; app.Gfx.Full(k) = s;
            end
            app.placeMarker(k);
        end

        function [X, Y, Z] = viewCoords(app, kind, C, lim)
            %VIEWCOORDS Surface coordinates of one view kind. Fisheye/3-D stay physical (polar θ, φ); contour/rect use the display axes.
            e = app.pat(); P = e.Pattern; M = app.Map; ph = P.Phi(M.ColIdx);
            switch kind
                case "contour", X = M.PhiAxis; Y = M.ThetaAxis; Z = zeros(size(C));
                case "rect",    X = M.PhiAxis; Y = M.ThetaAxis; Z = C;
                case "fisheye", [X, Y] = meshgrid(deg2rad(ph), P.Theta); Z = zeros(size(C));
                otherwise
                    [PH, TH] = meshgrid(ph, P.Theta); r = 1; if kind == "polar", r = util_polarRadius(C, lim); end
                    X = r .* sind(TH) .* cosd(PH); Y = r .* sind(TH) .* sind(PH); Z = r .* cosd(TH);
            end
        end

        function applyCamera(app, k)
            %APPLYCAMERA 3-D view from the dropdown (or the view's default camera) for one or all 3-D axes.
            if nargin < 2, ks = 3:5; else, ks = k; end
            up = [0 0 1]; switch app.Single_DropDown_3DView.Value
                case 'top', v = [0 90]; up = [0 1 0]; case 'bottom', v = [0 -90]; up = [0 1 0]; case 'right', v = [90 0]; case 'left', v = [-90 0];
                case 'front', v = [0 0]; case 'back', v = [180 0]; otherwise, v = []; end
            for k = ks(ks >= 3)
                ax = app.Gfx.Full(k).Axes; if isempty(v), view(ax, app.Gfx.Full(k).Camera); else, view(ax, v); end
                camup(ax, up);
            end
        end

        function placeMarker(app, k)
            %PLACEMARKER Peak-of-beam marker + datatip of view k (created once, re-indexed on every render; Visible follows the checkbox).
            s = app.Gfx.Full(k); e = app.pat(); P = e.Pattern; M = app.Map; V = app.View; pk = app.CompPeak;
            [r, c] = ind2sub([numel(P.Theta), numel(P.Phi)], pk.index); cc = find(M.ColIdx == c, 1);
            val = app.col(); val = val(r, c); thD = M.ThetaAxis(r); phD = M.PhiAxis(cc); z = 0;
            switch s.Kind
                case "contour", x = phD; y = thD;
                case "rect", x = phD; y = thD; z = val;
                case "fisheye", x = deg2rad(P.Phi(c)); y = P.Theta(r);
                otherwise, rad = 1.02; if s.Kind == "polar", rad = 1.02*util_polarRadius(val, app.themeLimits()); end
                    x = rad*sind(P.Theta(r))*cosd(P.Phi(c)); y = rad*sind(P.Theta(r))*sind(P.Phi(c)); z = rad*cosd(P.Theta(r));
            end
            if ~isgraphics(s.Marker)
                if s.Kind == "fisheye", s.Marker = polarplot(s.Axes, x, y, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off');
                else, s.Marker = line(s.Axes, x, y, z, 'LineStyle', 'none', 'Marker', 'o', 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off', 'Clipping', 'off'); end
            elseif s.Kind == "fisheye", set(s.Marker, 'ThetaData', x, 'RData', y);
            else, set(s.Marker, 'XData', x, 'YData', y, 'ZData', z);
            end
            s.Marker.DataTipTemplate.DataTipRows = [dataTipTextRow(M.ThetaLabel, thD, '%.3g°'), dataTipTextRow("Phi", phD, '%.3g°'), dataTipTextRow(app.compLabel(), val, ['%.3g ' char(P.Meta.UnitLabel)])];
            if ~isgraphics(s.Tip) && V.POB, s.Tip = datatip(s.Marker, 'DataIndex', 1, 'FontSize', 9); end
            set([s.Marker, s.Tip(isgraphics(s.Tip))], 'Visible', V.POB); app.Gfx.Full(k) = s;
        end

        function renderCut(app)
            %RENDERCUT Polar + rectangular cut from ONE geo_cut extraction; the same extract feeds both 3-D overlays and the HPBW readout.
            e = app.pat(); P = e.Pattern; D = e.Derived; V = app.View; g = app.Gfx.Cut; lim = app.Range.cut;
            [names, idx] = app.cutColumns(V, e);
            cut = geo_cut(P, cellfun(@(n) D.Cols.(n), cellstr(names), 'UniformOutput', false), V.CutType, V.CutValue);
            if V.Basis == "Linear", set([app.CheckBox_Er, app.CheckBox_El], {'Text'}, {'E_TH'; 'E_PH'}); else, set([app.CheckBox_Er, app.CheckBox_El], {'Text'}, {'E_RCP'; 'E_LCP'}); end
            % 3-D overlays use the physical cut geometry before any display re-ordering.
            fl = app.themeLimits(); rad = [1.02*ones(size(cut.y, 1), 1), 1.01*util_polarRadius(cut.y(:, 1), fl)];
            for a = 1:2, set(g.Overlay(a), 'XData', rad(:, a).*sind(cut.theta).*cosd(cut.phi), 'YData', rad(:, a).*sind(cut.theta).*sind(cut.phi), 'ZData', rad(:, a).*cosd(cut.theta), 'Visible', V.Overlay); end
            a = cut.angle; y = cut.y; xl = [0 360];
            if V.SignedPhi
                xl = [-180 180]; a = mod(a + 180, 360) - 180; [a, o] = sort(a); y = y(o, :); [a, u] = unique(a); y = y(u, :);
                if a(1) == -180, a(end + 1) = 180; y(end + 1, :) = y(1, :); end
            end
            set([g.Polar, g.Rect], 'Visible', 'off'); pd = max(y, lim(1));
            for j = 1:numel(idx)
                t = idx(j); rows = [dataTipTextRow("Angle", a, '%.3g°'), dataTipTextRow("Magnitude", y(:, j), '%.3g dB')];
                set(g.Polar(t), 'ThetaData', deg2rad(a), 'RData', pd(:, j), 'Visible', 'on', 'DisplayName', char(names(j))); g.Polar(t).DataTipTemplate.DataTipRows = rows;
                set(g.Rect(t), 'XData', a, 'YData', y(:, j), 'Visible', 'on', 'DisplayName', char(names(j))); g.Rect(t).DataTipTemplate.DataTipRows = rows;
            end
            lbl = 0:30:330; if V.SignedPhi, lbl(lbl > 180) = lbl(lbl > 180) - 360; end
            set(app.Single_paxCut, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'RLim', lim, 'RTick', lim(1):5:lim(2), 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', lbl));
            set(app.Single_AxesRect, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            if V.CutType == "Phi", xlabel(app.Single_AxesRect, 'Phi (degree)'); else, xlabel(app.Single_AxesRect, 'Theta (degree)'); end
            if P.IsGainOnly, ttl = char(app.compLabel()); else, ttl = sprintf('%s cut @ %s = %g°', V.CutType, cut.symbol, cut.fixed); end
            title(app.Single_paxCut, ttl, 'Interpreter', 'none'); title(app.Single_AxesRect, ttl, 'Interpreter', 'none');
            legend(app.Single_paxCut, g.Polar(idx), 'Location', 'southoutside', 'Orientation', 'horizontal', 'Interpreter', 'none');
            legend(app.Single_AxesRect, g.Rect(idx), 'Location', 'best', 'Interpreter', 'none');
            if cut.snapped, app.setStatus(app.Single_StatusBar, sprintf('Requested %s cut snapped to nearest %s = %g°', V.CutType, cut.symbol, cut.fixed), true); end
            % Peak of the displayed cut (first trace) and HPBW with wrap-aware shading.
            [pk, ip] = max(y(:, 1), [], 'omitnan'); tipRows = [dataTipTextRow("Angle", a(ip), '%.3g°'), dataTipTextRow("Magnitude", pk, '%.3g dB')];
            set(g.PolarPk, 'ThetaData', deg2rad(a(ip)), 'RData', max(pk, lim(1)), 'Visible', V.POB); set(g.RectPk, 'XData', a(ip), 'YData', pk, 'Visible', V.POB);
            g.PolarPk.DataTipTemplate.DataTipRows = tipRows; g.RectPk.DataTipTemplate.DataTipRows = tipRows;
            delete(g.PolarReg); delete(g.RectReg); g.PolarReg = gobjects(0); g.RectReg = gobjects(0); app.Label_HPBW.Text = ''; set([g.PolarBd, g.RectBd], 'Visible', 'off');
            if V.HPBW
                [bw, lo, hi] = met_hpbw(a, y(:, 1), pk, a(ip));
                if isfinite(bw)
                    b = [lo hi]; if V.SignedPhi, b = mod(b + 180, 360) - 180; else, b = mod(b, 360); end
                    app.Label_HPBW.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                    if b(1) <= b(2), R = b; else, R = [xl(1) b(2); b(1) xl(2)]; end
                    g.PolarReg = thetaregion(app.Single_paxCut, deg2rad(R(:, 1)), deg2rad(R(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    g.RectReg = xregion(app.Single_AxesRect, R(:, 1), R(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    bdRows = [dataTipTextRow("HPBW bound", b, '%.2f°'), dataTipTextRow("Gain", [pk pk] - 3, '%.2f dB')];
                    set(g.PolarBd, 'ThetaData', deg2rad(b), 'RData', [pk pk] - 3, 'Visible', V.HPBWBounds); set(g.RectBd, 'XData', b, 'YData', [pk pk] - 3, 'Visible', V.HPBWBounds);
                    g.PolarBd.DataTipTemplate.DataTipRows = bdRows; g.RectBd.DataTipTemplate.DataTipRows = bdRows;
                end
            end
            app.Gfx.Cut = g;
        end

        function T = resultsTable(app)
            %RESULTSTABLE Long table of the checked columns in the display convention (built from Derived on demand, never cached).
            e = app.pat(); M = app.Map; names = string(fieldnames(e.Derived.Cols)).'; names = names(app.OutMask);
            [PH, TH] = meshgrid(M.PhiAxis, M.ThetaAxis); T = table(TH(:), PH(:), 'VariableNames', {'Theta', 'Phi'});
            for n = names, X = e.Derived.Cols.(n); X = X(:, M.ColIdx); T.(n) = X(:); end
            T = sortrows(T, {'Phi', 'Theta'});
        end

        function renderTables(app)
            %RENDERTABLES Input table once per source; Results table only when its tab is visible and its key changed (D43).
            e = app.pat();
            if ~app.RawShown, set(app.Single_Table_DataIn, 'Data', e.Source.Raw, 'ColumnName', e.Source.Raw.Properties.VariableNames, 'Visible', 'on'); app.RawShown = true; end
            key = jsonencode([app.dataKey(e), {app.Map.Key, app.OutMask}]);
            if strcmp(app.Gfx.TableKey, key) || ~isequal(app.Single_tabData.SelectedTab, app.Single_tabDataOut), return; end
            T = app.resultsTable(); set(app.Single_Table_DataOut, 'Data', T, 'ColumnName', T.Properties.VariableNames); app.Gfx.TableKey = key;
        end

        function applyFilterStyles(app)
            %APPLYFILTERSTYLES ✓ marks and colours of the Results column filter from OutMask.
            dd = app.Single_DropDown_output; if numel(dd.Items) < 2, return; end
            dd.Items = regexprep(dd.Items, '^✓ ?', ''); removeStyle(dd); on = find(app.OutMask) + 1; dd.Items(on) = append('✓ ', dd.Items(on));
            addStyle(dd, uistyle('FontWeight', 'bold', 'FontColor', 'black', 'BackgroundColor', [0.8 1 0.8]), 'Item', on);
            addStyle(dd, uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9]), 'Item', find([true, ~app.OutMask]));
        end

        function onFilter(app)
            dd = app.Single_DropDown_output;
            if dd.Value > 0, app.OutMask(dd.Value) = ~app.OutMask(dd.Value); dd.Value = 0; app.applyFilterStyles(); end
            app.on("annot");
        end

        function renderMetadata(app)
            %RENDERMETADATA {property, value} rows from Meta, Geometry, Derived, Params and the pinned conventions.
            e = app.pat(); P = e.Pattern; G = e.Geometry; D = e.Derived; m = D.Metrics; f = @util_fmtNumber; u = char(P.Meta.UnitLabel);
            per = 'open'; if G.PhiPeriodic, per = 'periodic'; end
            rows = {'Source format', char(P.Meta.Format); 'File', e.Name; 'Level unit', u
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', numel(P.Theta)*numel(P.Phi), numel(P.Theta), numel(P.Phi))
                'θ range / step', sprintf('[%s°, %s°] / %s°', f(P.Theta(1)), f(P.Theta(end)), f(P.dTheta))
                'φ range / step', sprintf('[%s°, %s°] / %s° (φ %s)', f(P.Phi(1)), f(P.Phi(end)), f(P.dPhi), per)
                'Sampled solid angle', sprintf('%s sr (%s%% of 4π)', f(G.Omega, 4), f(100*G.Omega/(4*pi)))};
            if isfinite(P.Freq), rows(end + 1, :) = {'Frequency', sprintf('%.4g GHz', P.Freq/1e9)}; end
            if ~P.IsGainOnly
                rows = [rows; {'Polarization', D.Pol.label; 'Cut Co-pol / Cross-pol', char(strjoin(D.Pol.pairs.(app.View.Basis), ' / '))}];
                rows(end + 1, :) = {'Parameters', sprintf('L=%s dB | Rx %s, AR %s dB | Pt %s dBW | R %s m', f(e.Params.L), e.Params.RxMode, f(e.Params.RxAR_dB), f(e.Params.Pt_dBW), f(e.Params.R_m))};
            else, rows(end + 1, :) = {'Parameters', sprintf('L=%s dB on gain-kind columns', f(e.Params.L))};
            end
            rows = [rows; {sprintf('Peak gain (POB) [%s]', u), sprintf('%s %s', f(D.Peak.value), u); 'POB direction [θ, φ]', sprintf('[%s°, %s°]', f(m.PeakTheta_deg), f(m.PeakPhi_deg))
                'Peak policy', sprintf('spatial isolation > %g dB over 4 neighbours; %d spike(s), raw max %s %s, adjusted: %s', app.PeakExcessDB, D.Peak.spikeCount, f(D.Peak.rawValue), u, string(D.Peak.wasAdjusted))
                'Boresight axis', app.PrincipalAxes.labels{D.Boresight}; 'HPBW E-plane', [f(m.HPBW_EPlane_deg) '°']; 'HPBW H-plane', [f(m.HPBW_HPlane_deg) '°']
                'Front-to-back', [f(m.FrontBack_dB) ' dB']; 'Peak directivity', [f(m.PeakDirectivity_dB) ' dB']}];
            if ~G.IsFullSphere, rows{end, 2} = [rows{end, 2} ' (normalised to the sampled region; F/B and efficiency need a full sphere)']; end
            if isfinite(m.Efficiency_pct), rows(end + 1, :) = {'Radiation efficiency', [f(m.Efficiency_pct) '%']}; end
            if isfinite(m.AxialRatioAtPeak_dB), rows(end + 1, :) = {'AR at peak', [f(m.AxialRatioAtPeak_dB) ' dB (signed: + RHCP, − LHCP)']}; end
            rows = [rows; {'Conventions', 'e^{+jωt}; E_R = (Eθ + jEφ)/√2, E_L = (Eθ − jEφ)/√2 (IEEE); ΔΩ = [cos(θ−Δθ/2) − cos(θ+Δθ/2)]·Δφ; Coverage(T) = 100·Ω_R(G>T)/Ω_R'}];
            for n = P.Meta.Notes, rows(end + 1, :) = {'Reader note', char(n)}; end %#ok<AGROW>
            app.Single_Table_metadata.Data = rows;
        end
    end

    % ====================================================== MAIN-TAB ACTIONS ======================================================
    methods (Access = private)
        function onLoad(app)
            %ONLOAD Browse (or take the typed path), parse, build the entry, commit it as Main. Coverage-results files route to the Coverage tab.
            fp = strtrim(app.Single_EditField_Path.Value);
            if isempty(fp) || ~isfile(fp)
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.csv;*.dat;*.txt', 'Pattern/Gain Files'}, 'Select an antenna pattern file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            app.Single_EditField_Path.Value = fp; app.loadMain(fp, "Loading Data");
        end

        function loadMain(app, fp, dlgTitle)
            %LOADMAIN Same-file reselect and Process-with-format-change both come here: one read, one build, one commit (D42, D44).
            if app.Busy, return; end
            app.Busy = true; cleanBusy = onCleanup(@() app.setBusy(false)); app.perf("begin source");
            app.Dlg = uiprogressdlg(app.UIFigure, 'Title', dlgTitle, 'Message', 'Reading file...', 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            cleanDlg = onCleanup(@() delete(app.Dlg)); drawnow
            try
                fmt = "gain"; if ~app.isTextFile(fp), fmt = "auto"; elseif app.Main > 0 && strcmp(fp, app.Pats(app.Main).Path), fmt = string(app.Single_DropDown_TextFormat.Value); end
                S = io_read(fp, fmt, table()); app.perf("Read file"); app.checkCancelled();
                if S.Meta.IsCoverage
                    app.Single_EditField_Path.Value = ''; if app.Main > 0, app.Single_EditField_Path.Value = app.Pats(app.Main).Path; end
                    app.TabGroup.SelectedTab = app.Tab2_Coverage; app.Cov_EditField_filePath.Value = fp; app.covLoadResults(fp, S.Raw);
                else
                    [~, name, ext] = fileparts(fp); V = app.readConfig(); newFile = app.Main == 0 || ~strcmp(fp, app.Pats(app.Main).Path);
                    if newFile, set(app.Single_DropDown_step, 'Items', {'STEP'}, 'Value', 'STEP'); set(app.Single_DropDown_FFD, 'Items', {'Frequencies'}, 'Value', 'Frequencies'); app.BasisAuto = true; V = app.readConfig(); end
                    e = app.buildEntry(S, [name ext], fp, V.OneDegree, V.FreqIndex, V.Params);
                    k = find(strcmp({app.Pats.Path}, fp), 1); if isempty(k), k = numel(app.Pats) + 1; end
                    app.Pats(k) = e; app.Main = k; app.RawShown = false; app.Gfx.TableKey = ''; app.Range.Auto.full = true; app.Range.Auto.cut = true;
                    app.update("source");                              % entry already built and committed: choices, presets and every view
                    if app.isTextFile(fp), app.Single_DropDown_TextFormat.Value = char(fmt); end
                end
                drawnow limitrate
            catch err
                if strcmp(err.identifier, 'APAT:Cancelled'), app.setStatus(app.Single_StatusBar, 'Loading cancelled by user.', true); else, app.showError(err, 'Loading Error'); end
            end
            app.perf("end");
        end

        function onProcess(app)
            %ONPROCESS Loss/Rx/Pt/R → one derivation and a redraw; a changed generic text format → a reload (D55).
            if app.Main == 0, uialert(app.UIFigure, 'No file! Load a pattern first.', 'Warning', 'Icon', 'warning'); return; end
            e = app.pat();
            if app.isTextFile(e.Path) && ~isequal(string(app.Single_DropDown_TextFormat.Value), extractBetween(e.Pattern.Meta.Format + ")", "(", ")"))
                app.loadMain(e.Path, "Processing"); return
            end
            app.on("params"); app.setStatus(app.Single_StatusBar, ['Re-processed <b>' e.Name '</b> with current parameters ' char(9989)], true);
        end

        function resetParams(app)
            d = app.Defaults;
            set(app.Single_Spinner_Loss, 'Value', d.L); set(app.Single_DropDown_RxPol, 'Value', char(d.RxMode)); set(app.Single_Spinner_Rw, 'Value', d.RxAR_dB);
            set(app.Single_Spinner_Pt, 'Value', 0); set(app.Single_DropDown_Pt, 'Value', 'dBW'); set(app.Single_Spinner_R, 'Value', 1); set(app.Single_DropDown_R, 'Value', 'm');
            app.on("params");
        end

        function writeTable(~, T, fp)
            if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
        end

        function exportAny(app, kind)
            %EXPORTANY results | cut | uan | coverage — built from data on demand, never from a uitable.
            if app.Main == 0 && kind ~= "coverage", return; end
            e = []; if app.Main > 0, e = app.pat(); end
            try
                switch kind
                    case "results", [f, p] = uiputfile({'*.csv'; '*.txt'; '*.xlsx'}, 'Export Results', [regexprep(e.Path, '\.[^.]*$', '') '_APAT_results.csv']); if isequal(f, 0), return; end
                        app.writeTable(app.resultsTable(), fullfile(p, f)); what = 'Results';
                    case "cut", [names, ~] = app.cutColumns(app.View, e); cut = geo_cut(e.Pattern, cellfun(@(n) e.Derived.Cols.(n), cellstr(names), 'UniformOutput', false), app.View.CutType, app.View.CutValue);
                        [f, p] = uiputfile({'*.csv'; '*.txt'}, 'Export Cut', [regexprep(e.Path, '\.[^.]*$', '') '_cut.csv']); if isequal(f, 0), return; end
                        app.writeTable(array2table([cut.angle, cut.y], 'VariableNames', [{'Angle_deg'}, cellstr(names)]), fullfile(p, f)); what = 'Cut';
                    case "coverage", if isempty(app.Cov_Tabel.Data), return; end
                        [f, p] = uiputfile({'*.csv'; '*.txt'; '*.xlsx'}, 'Export Coverage Results', 'coverage_results.csv'); if isequal(f, 0), return; end
                        app.writeTable(app.Cov_Tabel.Data, fullfile(p, f)); what = 'Coverage results';
                    case "uan"
                        if e.Pattern.IsGainOnly, uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
                        [U, hdr] = app.uanTable(e); [f, p] = uiputfile({'*.uan'; '*.csv'; '*.txt'}, 'Export UAN / E-field data', sprintf('%s_%.5f_%gdeg.uan', regexprep(e.Path, '\.[^.]*$', ''), e.Derived.Peak.value, e.Pattern.dTheta));
                        if isequal(f, 0), return; end
                        fp = fullfile(p, f);
                        if endsWith(fp, '.uan', 'IgnoreCase', true), writelines(hdr, fp); writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
                        else, app.writeTable(U, fp); end
                        what = 'UAN';
                end
                app.setStatus(app.Single_StatusBar, [what ' exported to <b>' fullfile(p, f) '</b>'], true);
            catch err
                app.showError(err, 'Export Error');
            end
        end

        function [U, hdr] = uanTable(~, e)
            %UANTABLE Canonical φ ∈ [0,360] (closing column added as XGTD expects), fields at the current loss, maximum_gain = total-gain peak (D29).
            P = e.Pattern; s = 10^(e.Params.L/20); idx = 1:numel(P.Phi); ph = P.Phi; if e.Geometry.PhiPeriodic, idx(end + 1) = 1; ph(end + 1) = ph(1) + 360; end
            Eth = P.Eth(:, idx)*s; Eph = P.Eph(:, idx)*s; [PH, TH] = meshgrid(ph, P.Theta);
            U = table(TH(:), PH(:), round(20*log10(max(abs(Eth(:)), eps)), 5), round(20*log10(max(abs(Eph(:)), eps)), 5), round(rad2deg(angle(Eth(:))), 5), round(rad2deg(angle(Eph(:))), 5), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'});
            U = sortrows(U, {'Phi', 'Theta'});
            hdr = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\ncomplex\nmag_phase\n' ...
                'pattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                ph(1), ph(end), P.dPhi, P.Theta(1), P.Theta(end), P.dTheta, e.Derived.Peak.value);
        end
    end

    % ========================================================= COVERAGE TAB =========================================================
    methods (Access = private)
        function node = covTarget(app)
            %COVTARGET Pattern node to act on: the selection (or its ancestor), otherwise the most recently added pattern node.
            node = []; sel = app.Cov_Tree.SelectedNodes;
            if ~isempty(sel), n = sel(1); while isa(n, 'matlab.ui.container.TreeNode'), if app.nodeIs(n, 'pattern'), node = n; return; end, n = n.Parent; end, end
            kids = app.Cov_TreeNode_Results.Children;
            for k = numel(kids):-1:1, if app.nodeIs(kids(k), 'pattern'), node = kids(k); return; end, end
        end

        function tf = nodeIs(~, n, kind), tf = isstruct(n.NodeData) && strcmp(n.NodeData.kind, kind); end

        function jobs = covJobs(app, roots)
            %COVJOBS The tree IS the job registry: jobs are the grandchildren of the Results root (optionally under ROOTS only).
            if nargin < 2, roots = app.Cov_TreeNode_Results.Children; end
            jobs = gobjects(1, 0);
            for r = roots(:).', kids = r.Children(:).'; jobs = [jobs, r, kids, vertcat(kids.Children).']; end %#ok<AGROW>  (root, its children, grandchildren)
            jobs = jobs(arrayfun(@(n) app.nodeIs(n, 'job'), jobs));
        end

        function Q = readCoverageConfig(app)
            %READCOVERAGECONFIG The only reader of Coverage-tab widget values; it never writes one (D48).
            Q.Component = string(app.Cov_DropDown_Component.Value);
            Q.T = cov_thresholds(app.Cov_Spinner_ThreshMin.Value, app.Cov_Spinner_ThreshMax.Value, max(app.Cov_Spinner_Step.Value, 0.1));
            Q.Conical = logical(app.Cov_ButtonGroup_Btn_Conical.Value); Q.Orientation = double(app.Cov_DropDown_Orientation.Value);
            Q.Cone = [app.Cov_Spinner_ConeTH.Value, mod(app.Cov_Spinner_ConePH.Value, 360), app.Cov_Spinner_ConeAng.Value];
            Q.QueryT = app.Cov_Spinner_queryCov.Value; Q.QueryC = app.Cov_Spinner_queryThresh.Value; Q.TextFormat = string(app.Cov_DropDown_TextFormat.Value);
        end

        function covLoad(app)
            %COVLOAD Load a pattern (new registry entry through the same build chain as Main) or a coverage-results file.
            fp = strtrim(app.Cov_EditField_filePath.Value);
            if isempty(fp) || ~isfile(fp)
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.ffd;*.ffe;*.ffs;*.cut;*.xlsx;*.csv;*.dat;*.txt', 'Pattern / coverage data'; '*.*', 'All files'}, 'Select a pattern or coverage results file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            app.Cov_EditField_filePath.Value = fp;
            existing = app.Cov_TreeNode_Results.Children(arrayfun(@(n) isstruct(n.NodeData) && isfield(n.NodeData, 'path') && strcmp(n.NodeData.path, fp), app.Cov_TreeNode_Results.Children));
            if ~isempty(existing), app.Cov_Tree.SelectedNodes = existing(1); app.covSelect(); app.setStatus(app.Cov_StatusBar, 'File already loaded -- node selected.', true); return; end
            app.covAddPattern(fp, "gain");
        end

        function covAddPattern(app, fp, fmt)
            %COVADDPATTERN Parse FP on the Coverage tab (guarded, D64) into a registry entry and a pattern node holding only k.
            if app.Busy, return; end
            app.Busy = true; cleanBusy = onCleanup(@() app.setBusy(false)); app.perf("begin covSource");
            try
                if ~app.isTextFile(fp), fmt = "auto"; end
                S = io_read(fp, fmt, table()); app.perf("Read file");
                if S.Meta.IsCoverage, app.covLoadResults(fp, S.Raw); app.perf("end"); return; end
                [~, name] = fileparts(fp); V = app.readConfig();
                k = find(strcmp({app.Pats.Path}, fp), 1); if isempty(k), k = numel(app.Pats) + 1; end
                if k ~= app.Main, app.Pats(k) = app.buildEntry(S, name, fp, false, 1, V.Params); end
                old = app.Cov_TreeNode_Results.Children(arrayfun(@(n) isstruct(n.NodeData) && isfield(n.NodeData, 'k') && n.NodeData.k == k, app.Cov_TreeNode_Results.Children));
                for j = app.covJobs(old), delete(j.NodeData.Line); delete(j.NodeData.Query(isgraphics(j.NodeData.Query))); end
                delete(old);
                node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📡 ' name]); node.NodeData = struct('kind', 'pattern', 'k', k, 'path', fp, 'name', name);
                expand(app.Cov_Tree); app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node]; app.Cov_Tree.SelectedNodes = node;
                app.Range.Auto.cov = true; app.covSelect();                                     % covSelect already refreshes lines, legend and table
                app.setStatus(app.Cov_StatusBar, sprintf('Pattern "<b>%s</b>" added %s ready to compute coverage.', name, char(8212)), false);
            catch err
                app.showError(err, 'Coverage Load Error');
            end
            app.perf("end");
        end

        function covFromMain(app)
            if app.Main == 0, uialert(app.UIFigure, 'Load and process a pattern first.', 'Coverage'); return; end
            e = app.pat(); app.TabGroup.SelectedTab = app.Tab2_Coverage; app.Cov_EditField_filePath.Value = e.Path;
            nodes = app.Cov_TreeNode_Results.Children; hit = nodes(arrayfun(@(n) isstruct(n.NodeData) && isfield(n.NodeData, 'k') && n.NodeData.k == app.Main, nodes));
            if isempty(hit), app.covAddPattern(e.Path, app.View.TextFormat); else, app.Cov_Tree.SelectedNodes = hit(1); app.covSelect(); end
            app.setStatus(app.Cov_StatusBar, 'Coverage source is the Main-tab pattern (shared registry entry; loss and step follow the Main tab).', false);
        end

        function covLoadResults(app, fp, R)
            %COVLOADRESULTS Every column of a results file becomes a job {T, cov} indistinguishable from a computed one.
            [~, name] = fileparts(fp); node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📄 ' name]); node.NodeData = struct('kind', 'results', 'path', fp, 'name', name);
            T = R{:, 1}; jobs = gobjects(1, width(R) - 1);
            for c = 2:width(R), jobs(c - 1) = app.covAddJob(node, T, R{:, c}, sprintf('%s · %s', name, R.Properties.VariableNames{c}), '📈'); end
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node; jobs(:)]; expand(node);
            if app.Range.Auto.covX, app.applyRange("covX", [min(T), max(T)]); end
            app.covFinish(app.covJobs()); app.setStatus(app.Cov_StatusBar, sprintf('Coverage results file "%s" loaded (%d curves).', name, numel(jobs)), false);
        end

        function job = covAddJob(app, parent, T, cov, label, icon)
            app.CovId = app.CovId + 1; label = sprintf('%s R%d %s', icon, app.CovId, label);
            h = plot(app.Cov_Axes, T, cov, 'LineWidth', 1.6, 'DisplayName', label);
            h.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", T, '%.2f dB'), dataTipTextRow("Coverage", cov, '%.2f%%')];
            job = uitreenode(parent, 'Text', label); job.NodeData = struct('kind', 'job', 'id', app.CovId, 'label', label, 'T', T(:), 'cov', cov(:), 'Line', h, 'Query', gobjects(0));
        end

        function covCompute(app)
            %COVCOMPUTE One cov_curve on Pats(k).Derived.Cols.(component) (already at the current loss) for the current thresholds and region.
            node = app.covTarget(); if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            app.perf("begin covRun");
            try
                e = app.Pats(node.NodeData.k); Q = app.readCoverageConfig(); P = e.Pattern; C = e.Derived.Cols.(Q.Component); region = 'Sph'; mask = true(size(C));
                if Q.Conical
                    mask = cov_coneMask(P, Q.Cone(1), Q.Cone(2), Q.Cone(3)); region = sprintf('Con %s α=%s°', app.coneLabel(Q.Cone(1), Q.Cone(2)), util_fmtNumber(Q.Cone(3)));
                end
                cov = cov_curve(C, e.Geometry.dOmega, mask, Q.T); app.perf("Coverage");
                job = app.covAddJob(node, Q.T, cov, sprintf('%s · %s · L=%s dB', region, Q.Component, util_fmtNumber(e.Params.L)), '📉');
                app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; job]; expand(node);
                if app.Range.Auto.covX, app.applyRange("covX", [Q.T(1), Q.T(end)]); end
                app.covFinish(app.covJobs());
                msg = sprintf('Run-<b>%d</b> computed: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds, Ω_R = %s sr).', app.CovId, region, node.NodeData.name, Q.Component, numel(Q.T), util_fmtNumber(sum(e.Geometry.dOmega(mask & isfinite(C))), 3));
                if ~any(mask, 'all'), msg = [msg ' <b>Empty region: coverage is 0 %.</b>']; end
                app.setStatus(app.Cov_StatusBar, msg, false);
            catch err
                app.showError(err, 'Coverage Error');
            end
            app.perf("end");
        end

        function s = coneLabel(app, th, ph)
            %CONELABEL Principal-axis name when the centre coincides with ±X/±Y/±Z, else the explicit (θ, φ).
            A = app.PrincipalAxes; v = [sind(th)*cosd(ph), sind(th)*sind(ph), cosd(th)]; ax = [sind(A.theta(:)).*cosd(A.phi(:)), sind(A.theta(:)).*sind(A.phi(:)), cosd(A.theta(:))];
            i = find(ax*v(:) >= 1 - 1e-9, 1); if isempty(i), s = sprintf('θ=%s°, φ=%s°', util_fmtNumber(th), util_fmtNumber(ph)); else, s = A.labels{i}; end
        end

        function covFinish(app, jobs)
            %COVFINISH Line visibility, legend and the union table for the checked jobs — pure reads of the curves (cov_at).
            checked = jobs(ismember(jobs, app.Cov_Tree.CheckedNodes)); sel = app.Cov_Tree.SelectedNodes;
            for j = jobs(:).', d = j.NodeData; vis = ismember(j, checked); set([d.Line, d.Query(isgraphics(d.Query))], 'Visible', vis); set(findobj(d.Line, 'Type', 'datatip'), 'Visible', vis); d.Line.LineWidth = 1.6 + 1.0*(~isempty(sel) && isequal(j, sel(1))); end
            if isempty(checked), legend(app.Cov_Axes, 'off'); app.Cov_Tabel.Data = table(); else
                legend(app.Cov_Axes, arrayfun(@(j) j.NodeData.Line, checked), 'Location', 'southwest', 'Interpreter', 'none');
                Ts = arrayfun(@(j) j.NodeData.T, checked, 'UniformOutput', false); T = unique(vertcat(Ts{:}));      % union of the checked thresholds
                M = [T, cell2mat(arrayfun(@(j) cov_at(j.NodeData, T), checked, 'UniformOutput', false))];
                names = [{'Threshold (dB)'}, arrayfun(@(j) sprintf('R%d %%', j.NodeData.id), checked, 'UniformOutput', false)];
                app.Cov_Tabel.Data = array2table(compose('%.2f', M), 'VariableNames', names);
            end
            app.applyVisibility();
        end

        function covSelect(app)
            %COVSELECT Tree selection: component list and threshold preset for the pattern (numerics already in Derived, D37), status for a job.
            sel = app.Cov_Tree.SelectedNodes; node = app.covTarget();
            if ~isempty(node)
                e = app.Pats(node.NodeData.k); [names, labels] = app.componentList(e.Derived); dd = app.Cov_DropDown_Component; prev = string(dd.Value);
                if ~isequal(string(dd.ItemsData), names), [dd.Items, dd.ItemsData] = deal(cellstr(labels), cellstr(names)); end
                if ~any(names == prev), prev = e.Derived.TotalName; end
                dd.Value = char(prev);
                app.covPreset(); if app.Cov_ButtonGroup_Btn_Conical.Value && app.Cov_DropDown_Orientation.Value == 0, app.covOrientation(); end
            end
            app.covFinish(app.covJobs());
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(app.Cov_StatusBar, 'Ready.', false); return; end
            d = sel(1).NodeData;
            if ~strcmp(d.kind, 'job')
                extra = ''; if strcmp(d.kind, 'pattern'), e = app.Pats(d.k); extra = sprintf(' | L=%s dB | boresight <b>%s</b>', util_fmtNumber(e.Params.L), app.PrincipalAxes.labels{e.Derived.Boresight}); end
                app.setStatus(app.Cov_StatusBar, sprintf('%s <b>"%s"</b> -- <b>%d</b> coverage job(s)%s.', [upper(d.kind(1)) d.kind(2:end)], d.name, numel(sel(1).Children), extra), false); return
            end
            mx = max(round(d.cov, 2)); i = find(round(d.cov, 2) == mx, 1, 'last'); t50 = thr_at(d, 50); f = @util_fmtNumber;
            app.setStatus(app.Cov_StatusBar, sprintf('%s | Threshold [%s, %s] dB step %s | 50%%-coverage threshold <b>%s dB</b> | max <b>%s%%</b> @ <b>%s dB</b>', ...
                d.label, f(d.T(1)), f(d.T(end)), f(median(diff(d.T))), f(t50), f(mx), f(d.T(i))), false);
        end

        function covPreset(app)
            %COVPRESET 50-dB threshold window under the selected column's peak while the group is still automatic (D39, D45).
            node = app.covTarget(); if isempty(node) || ~app.Range.Auto.cov, return; end
            e = app.Pats(node.NodeData.k); name = string(app.Cov_DropDown_Component.Value); if ~isfield(e.Derived.Cols, name), return; end
            if app.kindOf(name) == "ar", lim = app.ARLimits; else, C = e.Derived.Cols.(name); lim = util_presetRange(max(C(~e.Derived.Peak.spike), [], 'all')); end
            app.applyRange("cov", lim);
        end

        function covOrientation(app)
            %COVORIENTATION Auto → the pattern's boresight axis; explicit → that axis. Sets the cone-centre spinners (the region's definition).
            i = double(app.Cov_DropDown_Orientation.Value); node = app.covTarget();
            if i == 0, if isempty(node), return; end, i = app.Pats(node.NodeData.k).Derived.Boresight; end
            app.Cov_Spinner_ConeTH.Value = app.PrincipalAxes.theta(i); app.Cov_Spinner_ConePH.Value = app.PrincipalAxes.phi(i);
            app.setStatus(app.Cov_StatusBar, sprintf('Conical region centred on <b>%s</b> (θ₀=%g°, φ₀=%g°).', app.PrincipalAxes.labels{i}, app.PrincipalAxes.theta(i), app.PrincipalAxes.phi(i)), false);
        end

        function covQuery(app, mode)
            %COVQUERY "cov": Coverage at T (cov_at); "thr": Threshold at c % (thr_at). One datatip per checked job under the selection.
            sel = app.Cov_Tree.SelectedNodes; if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to query.', true); return; end
            jobs = app.covJobs(sel); jobs = jobs(ismember(jobs, app.Cov_Tree.CheckedNodes)); Q = app.readCoverageConfig(); ax = app.Cov_Axes; hit = false;
            for j = jobs(:).'
                d = j.NodeData; delete(d.Query(isgraphics(d.Query))); d.Query = gobjects(0);
                if mode == "cov", x = Q.QueryT; y = cov_at(d, x); else, y = Q.QueryC; x = thr_at(d, y); end
                if all(isfinite([x y]))
                    d.Query = [line(ax, [x x], [ax.YLim(1) y], 'Color', d.Line.Color, 'LineStyle', ':', 'HandleVisibility', 'off'), ...
                        line(ax, [ax.XLim(1) x], [y y], 'Color', d.Line.Color, 'LineStyle', ':', 'HandleVisibility', 'off'), ...
                        datatip(d.Line, x, y, 'SnapToDataVertex', 'off', 'FontSize', 9)];
                    hit = true;
                end
                j.NodeData = d;
            end
            if ~hit, app.setStatus(app.Cov_StatusBar, 'No checked result under the selection covers the query value.', true);
            elseif mode == "cov", app.setStatus(app.Cov_StatusBar, sprintf('Coverage queried at %s dB.', util_fmtNumber(Q.QueryT)), false);
            else, app.setStatus(app.Cov_StatusBar, sprintf('Threshold queried at %s%% coverage.', util_fmtNumber(Q.QueryC)), false); end
            app.applyVisibility();
        end

        function covClear(app)
            sel = app.Cov_Tree.SelectedNodes; if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to clear.', true); return; end
            for j = app.covJobs(sel), d = j.NodeData; delete(d.Query(isgraphics(d.Query))); d.Query = gobjects(0); delete(findobj(d.Line, 'Type', 'datatip')); j.NodeData = d; end
            app.setStatus(app.Cov_StatusBar, 'Selected DataTips and query markers cleared.', true);
        end

        function covReset(app)
            %COVRESET Delete every node and job; drop registry entries the Main tab does not use; restore automatic presets.
            for j = app.covJobs(), delete(j.NodeData.Line); delete(j.NodeData.Query(isgraphics(j.NodeData.Query))); end
            delete(app.Cov_TreeNode_Results.Children); delete(findobj(app.Cov_Axes, 'Type', 'datatip')); legend(app.Cov_Axes, 'off');
            if app.Main > 0, app.Pats = app.Pats(app.Main); app.Main = 1; else, app.Pats(:) = []; end
            app.Cov_Tabel.Data = table(); app.CovId = 0; app.Range.Auto.cov = true; app.Range.Auto.covX = true;
            app.applyRange("cov", [-40 10]); app.applyRange("covX", [-40 10]); app.applyVisibility();
            app.setStatus(app.Cov_StatusBar, 'Coverage workspace reset 🔄', true);
        end

        function covTypeChanged(app)
            if app.Cov_ButtonGroup_Btn_Conical.Value && app.Cov_DropDown_Orientation.Value == 0, app.covOrientation(); end
            app.applyVisibility();
        end

        function covFormatChanged(app)
            %COVFORMATCHANGED Re-read a generic text pattern node with the newly selected interpretation.
            node = app.covTarget(); fp = strtrim(app.Cov_EditField_filePath.Value);
            if isempty(node) || ~app.isTextFile(fp) || ~strcmp(node.NodeData.path, fp), return; end
            Q = app.readCoverageConfig(); app.covAddPattern(fp, Q.TextFormat);
        end
    end

    % =========================================================== LAYOUT ===========================================================
    methods (Access = private)
        function h = place(~, ctor, parent, row, col, varargin)
            %PLACE One widget, one line: constructor, parent, grid cell, properties.
            h = ctor(parent, varargin{:}); h.Layout.Row = row; h.Layout.Column = col;
        end

        function [lbl, h] = labelled(app, parent, text, row, col, ctor, varargin)
            %LABELLED Right-aligned label in (row, col) and its control in (row, col+1).
            lbl = app.place(@uilabel, parent, row, col, 'Text', text, 'HorizontalAlignment', 'right');
            h = app.place(ctor, parent, row, col + 1, varargin{:});
        end

        function [tab, g, ax, sl, mn, mx] = patternTab(app, group, tabTitle, axesTitle, needsAxes)
            %PATTERNTAB One full-pattern tab: axes (optional), vertical range slider, max/min spinners.
            tab = uitab(group, 'Title', tabTitle); g = uigridlayout(tab, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'}); ax = [];
            if needsAxes
                ax = app.place(@uiaxes, g, [1 3], 2, 'XLim', [0 360], 'YLim', [0 180], 'YDir', 'reverse', 'XTick', 0:30:360, 'YTick', 0:15:180, 'Box', 'on');
                title(ax, axesTitle); xlabel(ax, 'Phi (degree)'); ylabel(ax, 'Theta (degree)'); colormap(ax, 'jet');
            end
            sl = app.place(@(p, varargin) uislider(p, 'range', varargin{:}), g, 2, 1, 'Limits', app.HardRange, 'Value', app.HardRange, 'Orientation', 'vertical', 'Step', 1);
            mx = app.place(@uispinner, g, 1, 1, 'Limits', app.HardRange, 'Value', 100, 'Step', 5);
            mn = app.place(@uispinner, g, 3, 1, 'Limits', app.HardRange, 'Value', -250, 'Step', 5);
        end

        function dd = textFormatDropdown(app, parent, row, col, cb)
            dd = app.place(@uidropdown, parent, row, col, 'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
                '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'}, 'Value', 'gain', ...
                'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'ValueChangedFcn', cb);
        end

        function createComponents(app)
            on = @(scope) @(~, ~) app.on(scope); grid = @(parent, cols, rows) uigridlayout(parent, 'ColumnWidth', cols, 'RowHeight', rows);
            state = @(p, varargin) uibutton(p, 'state', varargin{:}); sw = @(p, varargin) uiswitch(p, 'slider', varargin{:}); rng = @(p, varargin) uislider(p, 'range', varargin{:});
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.ReleaseName], 'Visible', 'off', 'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) app.closeRequest());
            app.GridLayout = grid(app.UIFigure, {'1x'}, {'1x'}); app.TabGroup = app.place(@uitabgroup, app.GridLayout, 1, 1);
            % ------------------------------------------------------------ Tab 1: Process Pattern ------------------------------------------------------------
            app.Tab1_Single = uitab(app.TabGroup, 'Title', 'Process Pattern 📡'); app.Single_Grid = grid(app.Tab1_Single, repmat({'1x'}, 1, 14), {'fit', '2x', 'fit', '1x', 'fit'});
            app.Single_Panel_fullPattern = app.place(@uipanel, app.Single_Grid, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'BackgroundColor', [0.9412 0.9412 0.9412]);
            app.Single_gridPanel_full = grid(app.Single_Panel_fullPattern, {'1x'}, {'1x'});
            app.Single_tabPlots = app.place(@uitabgroup, app.Single_gridPanel_full, 1, 1, 'SelectionChangedFcn', on("annot"));
            [app.Single_tabContour, app.Single_gridContour, app.Single_Axes_Ctr, app.Range_Ctr, app.Range_Ctr_Min, app.Range_Ctr_Max] = app.patternTab(app.Single_tabPlots, 'Contour Plot', 'Antenna Gain Pattern', true);
            [app.Single_tabCircular, app.Single_gridCircular, ~, app.Range_Cir, app.Range_Cir_Min, app.Range_Cir_Max] = app.patternTab(app.Single_tabPlots, 'Circular Contour Plot', '', false);
            [app.Single_tab3DSpherical, app.Single_grid3dSpherical, app.Single_Axes_3dSph, app.Range_3dSph, app.Range_3dSph_Min, app.Range_3dSph_Max] = app.patternTab(app.Single_tabPlots, '3D Spherical Plot', '3D Spherical Plot', true);
            [app.Single_tab3DPolar, app.Single_grid3dPolar, app.Single_Axes_3dPol, app.Range_3dPol, app.Range_3dPol_Min, app.Range_3dPol_Max] = app.patternTab(app.Single_tabPlots, '3D Polar Plot', '3D Polar Plot', true);
            [app.Single_tab3DRect, app.Single_grid3dRect, app.Single_Axes_3dRect, app.Range_3dRect, app.Range_3dRect_Min, app.Range_3dRect_Max] = app.patternTab(app.Single_tabPlots, '3D Surface Plot', '3D Surface (Rectangular) Plot', true);
            app.Single_paxPattern = app.place(@polaraxes, app.Single_gridCircular, [1 3], 2, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            full = [app.Range_Ctr, app.Range_Cir, app.Range_3dSph, app.Range_3dPol, app.Range_3dRect];
            set(full, 'ValueChangedFcn', @(s, ~) app.onRange("full", 0, s.Value));
            set([app.Range_Ctr_Min, app.Range_Cir_Min, app.Range_3dSph_Min, app.Range_3dPol_Min, app.Range_3dRect_Min], 'ValueChangedFcn', @(s, ~) app.onRange("full", 1, s.Value));
            set([app.Range_Ctr_Max, app.Range_Cir_Max, app.Range_3dSph_Max, app.Range_3dPol_Max, app.Range_3dRect_Max], 'ValueChangedFcn', @(s, ~) app.onRange("full", 2, s.Value));
            % Cut panel
            app.Single_Panel_Rect = app.place(@uipanel, app.Single_Grid, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'BackgroundColor', [0.9412 0.9412 0.9412]);
            app.Single_gridPanel_Cut = grid(app.Single_Panel_Rect, {'1x'}, {'1x'}); app.Single_tabCut = app.place(@uitabgroup, app.Single_gridPanel_Cut, 1, 1);
            app.Single_tabPolarPlot = uitab(app.Single_tabCut, 'Title', 'Polar Cut Plot'); app.Single_Grid_Polar = grid(app.Single_tabPolarPlot, {'fit', '0.26x', '1x', '0.23x'}, {'fit', '0.25x', '1x', 'fit'});
            app.Range_Cut = app.place(rng, app.Single_Grid_Polar, [2 3], 1, 'Limits', app.HardRange, 'Value', app.HardRange, 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s, ~) app.onRange("cut", 0, s.Value));
            app.Range_Cut_Max = app.place(@uispinner, app.Single_Grid_Polar, 1, 1, 'Limits', app.HardRange, 'Value', 100, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRange("cut", 2, s.Value));
            app.Range_Cut_Min = app.place(@uispinner, app.Single_Grid_Polar, 4, 1, 'Limits', app.HardRange, 'Value', -250, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRange("cut", 1, s.Value));
            app.Single_paxCut = app.place(@polaraxes, app.Single_Grid_Polar, [1 4], 3, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            app.Button_HPBW = app.place(state, app.Single_Grid_Polar, 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', on("cut"));
            app.Label_HPBW = app.place(@uilabel, app.Single_Grid_Polar, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            app.Single_gridEcut = grid(app.Single_Grid_Polar, {'1x'}, {'1x', '1x', '1x'}); app.Single_gridEcut.Layout.Row = 3; app.Single_gridEcut.Layout.Column = 4;
            app.CheckBox_Et = app.place(@uicheckbox, app.Single_gridEcut, 1, 1, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', on("cut"));
            app.CheckBox_Er = app.place(@uicheckbox, app.Single_gridEcut, 2, 1, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', on("cut"));
            app.CheckBox_El = app.place(@uicheckbox, app.Single_gridEcut, 3, 1, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', on("cut"));
            app.Button_ExportCut = app.place(@uibutton, app.Single_Grid_Polar, 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.exportAny("cut"));
            app.Single_tabRectPlot = uitab(app.Single_tabCut, 'Title', 'Rectangular Cut Plot'); app.Single_gridRect = uigridlayout(app.Single_tabRectPlot);
            app.Single_AxesRect = app.place(@uiaxes, app.Single_gridRect, [1 2], [1 2], 'XLim', [0 180], 'XTick', 0:15:180, 'Box', 'on');
            xlabel(app.Single_AxesRect, 'Theta (degree)'); ylabel(app.Single_AxesRect, 'Magnitude (dB)');
            % Data tabs
            app.Single_DropDown_output = app.place(@uidropdown, app.Single_Grid, 3, [13 14], 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Value', 0, 'ValueChangedFcn', @(~, ~) app.onFilter());
            app.Single_tabData = app.place(@uitabgroup, app.Single_Grid, 4, [1 14], 'SelectionChangedFcn', on("annot"));
            app.Single_tabDataOut = uitab(app.Single_tabData, 'Title', 'Results 📤'); app.Single_gridDataOut = grid(app.Single_tabDataOut, {'1x'}, {'1x'});
            app.Single_Table_DataOut = app.place(@uitable, app.Single_gridDataOut, 1, 1, 'ColumnWidth', '1x', 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true);
            app.Single_tabDataIn = uitab(app.Single_tabData, 'Title', 'Input 📥'); app.Single_gridDataIn = grid(app.Single_tabDataIn, {'1x'}, {'1x'});
            app.Single_Table_DataIn = app.place(@uitable, app.Single_gridDataIn, 1, 1, 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true, 'Visible', 'off');
            app.MetadataTab = uitab(app.Single_tabData, 'Title', 'Metadata 📋'); app.Single_gridMetadata = grid(app.MetadataTab, {'1x'}, {'1x'});
            app.Single_Table_metadata = app.place(@uitable, app.Single_gridMetadata, 1, 1, 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            % Plot control panel
            app.Single_Panel_plotControl = app.place(@uipanel, app.Single_Grid, 2, [13 14], 'Title', 'Plot Control 🎨'); c = grid(app.Single_Panel_plotControl, {'1x', '1x'}, repmat({'fit'}, 1, 15)); app.Single_gridPanel_Ctrl = c;
            [app.ComponentLabel, app.Single_DropDown_Component] = app.labelled(c, 'Component', 1, 1, @uidropdown, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'Value', 'E_Total_dB', 'ValueChangedFcn', on("component"));
            [app.CuttypeDropDownLabel, app.Single_DropDown_cutType] = app.labelled(c, 'Cut type', 2, 1, @uidropdown, 'Items', {'Phi', 'Theta'}, 'Value', 'Phi', 'ValueChangedFcn', on("cut"));
            [app.CutvalueSpinnerLabel, app.Single_DropDown_cutValue] = app.labelled(c, 'Cut value', 3, 1, @uispinner, 'Limits', [0 360], 'Value', 0, 'ValueChangedFcn', on("cut"));
            [app.CutfieldsLabel, app.CutFieldBasisDropDown] = app.labelled(c, 'Cut fields', 4, 1, @uidropdown, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Value', 'Circular', 'Enable', 'off', ...
                'ValueChangedFcn', @(~, ~) app.onBasis());
            [app.ColorbarmaxLabel, app.Single_Plot_Cmax] = app.labelled(c, 'Colorbar max', 5, 1, @uispinner, 'Limits', app.HardRange, 'Value', 100, 'ValueChangedFcn', @(s, ~) app.onRange("full", 2, s.Value));
            [app.ColorbarminLabel, app.Single_Plot_Cmin] = app.labelled(c, 'Colorbar min', 6, 1, @uispinner, 'Limits', app.HardRange, 'Value', -250, 'ValueChangedFcn', @(s, ~) app.onRange("full", 1, s.Value));
            [app.ColorbarstepLabel, app.Single_Plot_Cstep] = app.labelled(c, 'Colorbar step', 7, 1, @uispinner, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', on("range"));
            [app.Single_Label_Clim, app.Single_Button_Clim] = app.labelled(c, 'Adjust Colorbar', 8, 1, @uibutton, 'Text', 'Apply', 'Tooltip', 'Apply the colorbar min/max to the full-pattern plots and the cut plots.', ...
                'ButtonPushedFcn', @(~, ~) app.onApplyClim());
            [app.View3DLabel, app.Single_DropDown_3DView] = app.labelled(c, '3D view', 9, 1, @uidropdown, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Value', 'iso', 'Tooltip', 'Camera direction for the 3D pattern tabs.', 'ValueChangedFcn', on("camera"));
            pad = @(n) repmat(char(160), 1, n);
            app.Single_Switch_AngularSpan = app.place(sw, c, 10, [1 2], 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'Value', '0° to 360°', 'ValueChangedFcn', on("span"));
            app.Single_Switch_ThetaSpan = app.place(sw, c, 11, [1 2], 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'Value', '0° to 180°', 'ValueChangedFcn', on("span"));
            app.Single_Switch_EHplane = app.place(sw, c, 12, [1 2], 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'Value', 'E-Plane cut', 'ValueChangedFcn', on("eh"));
            app.Singel_CheckBox_overlayCut = app.place(@uicheckbox, c, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', on("cut"));
            app.Single_CheckBox_POB = app.place(@uicheckbox, c, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', on("annot"));
            app.Single_CheckBox_HPBWBounds = app.place(@uicheckbox, c, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'ValueChangedFcn', on("cut"));
            app.Single_StatusBar = app.place(@uilabel, app.Single_Grid, 5, [1 14], 'Interpreter', 'html', 'Text', 'Ready 🚀', 'Tag', 'main');
            % Inputs & parameters panel
            app.Single_panelParam = app.place(@uipanel, app.Single_Grid, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️'); p = grid(app.Single_panelParam, repmat({'1x'}, 1, 14), {'1x', '1x', '1x'}); app.Single_gridPanel_Param = p;
            [app.InputPatternLabel, app.Single_EditField_Path] = app.labelled(p, 'Input Pattern:', 1, 1, @uieditfield); app.Single_EditField_Path.Layout.Column = [2 8];
            app.FFDFreqDropDownLabel = app.place(@uilabel, p, 1, 9, 'Text', 'FFD Freq:', 'HorizontalAlignment', 'right');
            app.Single_DropDown_FFD = app.place(@uidropdown, p, 1, 10, 'Items', {'Frequencies'}, 'Value', 'Frequencies', 'ValueChangedFcn', @(~, ~) app.on("freq", "Switching block"));
            app.Single_Button_Load = app.place(@uibutton, p, 1, [11 12], 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.onLoad());
            app.Single_Button_Process = app.place(@uibutton, p, 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', @(~, ~) app.onProcess());
            app.Single_Button_ResetParams = app.place(@uibutton, p, 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', @(~, ~) app.resetParams());
            app.TextFormatLabel = app.place(@uilabel, p, 2, [4 5], 'Text', 'Format:', 'HorizontalAlignment', 'right');
            app.Single_DropDown_TextFormat = app.textFormatDropdown(p, 2, [6 8], @(~, ~) app.onProcess());
            app.Single_DropDown_step = app.place(@uidropdown, p, 2, [9 10], 'Items', {'STEP'}, 'Value', 'STEP', 'Placeholder', 'STEP', 'ValueChangedFcn', @(~, ~) app.on("step", "Resampling"));
            app.Single_Export_Output = app.place(@uibutton, p, 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.exportAny("results"));
            app.Single_Export_UAN = app.place(@uibutton, p, 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.exportAny("uan"));
            [app.RxPolLabel, app.Single_DropDown_RxPol] = app.labelled(p, 'Rw Sense', 3, 1, @uidropdown, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Value', 'Auto', 'Editable', 'on');
            [app.IncidentWaveARRwPLFLabel, app.Single_Spinner_Rw] = app.labelled(p, 'Rw (dB)', 3, 3, @uispinner, 'Value', 6);
            [app.LossindBLabel, app.Single_Spinner_Loss] = app.labelled(p, 'Loss (−) / Gain (+) dB', 3, 5, @uispinner, 'Step', 0.1);
            [app.TransmitPowerLabel, app.Single_Spinner_Pt] = app.labelled(p, 'Tx Pwr (Pt)', 3, 7, @uispinner, 'Value', 0);
            app.Single_DropDown_Pt = app.place(@uidropdown, p, 3, 9, 'Items', {'dBW', 'dBm', 'Watts'}, 'Value', 'dBW');
            [app.DistanceLabel, app.Single_Spinner_R] = app.labelled(p, 'Distance', 3, 10, @uispinner, 'Value', 1);
            app.Single_DropDown_R = app.place(@uidropdown, p, 3, 12, 'Items', {'m', 'km'}, 'Value', 'm');
            app.Single_Button_Coverage = app.place(@uibutton, p, 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.covFromMain());
            % ------------------------------------------------------------ Tab 2: Compute Coverage ------------------------------------------------------------
            app.Tab2_Coverage = uitab(app.TabGroup, 'Title', 'Compute Coverage 📈'); app.Cov_Grid = grid(app.Tab2_Coverage, {'0.75x', 'fit', '1x', 'fit', '1x'}, {'0.25x', '1x', 'fit'});
            app.Cov_Panel_Param = app.place(@uipanel, app.Cov_Grid, 1, [1 5], 'Title', 'Inputs & Parameters 🎛️'); q = grid(app.Cov_Panel_Param, [{'fit'}, repmat({'1x'}, 1, 9)], {'1x', 'fit', 'fit', 'fit'}); app.Cov_gridPanel_Parm = q;
            app.Cov_ButtonGroup_CovType = app.place(@uibuttongroup, q, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', @(~, ~) app.covTypeChanged());
            app.Cov_ButtonGroup_Btn_Spherical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            app.Cov_ButtonGroup_Btn_Conical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            [app.Cov_DropDown_OrientationLabel, app.Cov_DropDown_Orientation] = app.labelled(q, 'Orientation 🧭:', 3, 1, @uidropdown, 'Items', [{'Auto'}, app.PrincipalAxes.labels], 'ItemsData', 0:6, 'Value', 0, 'ValueChangedFcn', @(~, ~) app.covOrientation());
            [app.AntennaPatternEditFieldLabel, app.Cov_EditField_filePath] = app.labelled(q, 'Antenna Pattern:', 1, 3, @uieditfield); app.Cov_EditField_filePath.Layout.Column = [4 8];
            app.Cov_Button_Load = app.place(@uibutton, q, 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', @(~, ~) app.covLoad());
            app.Cov_Button_computeCov = app.place(@uibutton, q, 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.covCompute());
            app.Cov_Button_Reset = app.place(@uibutton, q, 2, 9, 'Text', '🔄 Reset', 'ButtonPushedFcn', @(~, ~) app.covReset());
            app.Cov_Button_Export = app.place(@uibutton, q, 2, 10, 'Text', '💾 Export Results', 'ButtonPushedFcn', @(~, ~) app.exportAny("coverage"));
            covEdit = @(s, ~) app.onRange("cov", 2 - strcmp(s.Tag, 'min'), s.Value);
            [app.ThresholdMindBSpinnerLabel, app.Cov_Spinner_ThreshMin] = app.labelled(q, 'Threshold  Min (dB):', 2, 3, @uispinner, 'Value', -40, 'Tag', 'min', 'ValueChangedFcn', covEdit);
            [app.ThresholdMaxdBSpinnerLabel, app.Cov_Spinner_ThreshMax] = app.labelled(q, 'Threshold  Max (dB):', 2, 5, @uispinner, 'Value', 10, 'Tag', 'max', 'ValueChangedFcn', covEdit);
            [app.StepdBSpinnerLabel, app.Cov_Spinner_Step] = app.labelled(q, 'Step (dB):', 2, 7, @uispinner, 'Value', 1, 'Limits', [0.01 100]);
            [app.ConeSpinnerLabel, app.Cov_Spinner_ConeTH] = app.labelled(q, 'Cone θ₀ (°):', 3, 3, @uispinner, 'Limits', [0 180]);
            [app.ConeLabel, app.Cov_Spinner_ConePH] = app.labelled(q, 'Cone φ₀ (°):', 3, 5, @uispinner, 'Limits', [0 360]);
            [app.ConeAngleLabel, app.Cov_Spinner_ConeAng] = app.labelled(q, 'Cone Angle α (°):', 3, 7, @uispinner, 'Limits', [0 180], 'Value', 45);
            app.Cov_Button_Clear = app.place(@uibutton, q, 3, 9, 'Text', '🧹 Clear DataTips', 'ButtonPushedFcn', @(~, ~) app.covClear());
            app.Cov_Button_toMain = app.place(@uibutton, q, 3, 10, 'Text', '📊 To Main ◀ ', 'ButtonPushedFcn', @(~, ~) set(app.TabGroup, 'SelectedTab', app.Tab1_Single));
            [app.Cov_DropDown_ComponentLabel, app.Cov_DropDown_Component] = app.labelled(q, 'Component:', 4, 1, @uidropdown, 'Items', {'E_Total_dB'}, 'ValueChangedFcn', @(~, ~) app.covPreset());
            [app.Cov_QueryCoverageLabel, app.Cov_Spinner_queryCov] = app.labelled(q, 'Coverage @ dB:', 4, 3, @uispinner, 'ValueDisplayFormat', '%g dB');
            app.Cov_Button_queryCov = app.place(@uibutton, q, 4, 5, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', @(~, ~) app.covQuery("cov"));
            [app.Cov_QueryThresholdLabel, app.Cov_Spinner_queryThresh] = app.labelled(q, 'Threshold @ %:', 4, 6, @uispinner, 'ValueDisplayFormat', '%g%%', 'Value', 50);
            app.Cov_Button_queryThresh = app.place(@uibutton, q, 4, 8, 'Text', '🔍︎ Query Threshold', 'ButtonPushedFcn', @(~, ~) app.covQuery("thr"));
            app.Cov_TextFormatLabel = app.place(@uilabel, q, 4, 9, 'Text', 'Format:', 'HorizontalAlignment', 'right');
            app.Cov_DropDown_TextFormat = app.textFormatDropdown(q, 4, 10, @(~, ~) app.covFormatChanged());
            app.Cov_StatusBar = app.place(@uilabel, app.Cov_Grid, 3, [1 5], 'Interpreter', 'html', 'Text', 'Ready 🚀', 'Tag', 'cov');
            app.Cov_Panel_Results = app.place(@uipanel, app.Cov_Grid, 2, [1 5], 'Title', 'Results'); r = grid(app.Cov_Panel_Results, {'1x', 'fit', '1x', 'fit', '1x'}, {'1x', 'fit'}); app.GridLayout2 = r;
            app.Cov_Axes = app.place(@uiaxes, r, 1, [2 4], 'XLimMode', 'auto'); app.Cov_Axes.Interactions = dataTipInteraction;
            title(app.Cov_Axes, 'Coverage vs Threshold   —   Coverage(T) = 100·Ω_R(G > T)/Ω_R'); xlabel(app.Cov_Axes, 'Threshold (dB)'); ylabel(app.Cov_Axes, 'Coverage (%)');
            app.Cov_Tree = app.place(@(p, varargin) uitree(p, 'checkbox', varargin{:}), r, [1 2], 1, 'SelectionChangedFcn', @(~, ~) app.covSelect(), 'CheckedNodesChangedFcn', @(~, ~) app.covFinish(app.covJobs()));
            app.Cov_TreeNode_Results = uitreenode(app.Cov_Tree, 'Text', 'Coverage Results');
            app.Cov_Tabel = app.place(@uitable, r, [1 2], 5, 'ColumnWidth', '1x', 'RowName', {});
            app.Cov_Spinner_XRange = app.place(rng, r, 2, 3, 'Limits', app.HardRange, 'Value', [-40 10], 'ValueChangedFcn', @(s, ~) app.onRange("covX", 0, s.Value), 'ValueChangingFcn', @(s, e) app.onRange("covX", 0, e.Value));
            app.Cov_Spinner_XMin = app.place(@uispinner, r, 2, 2, 'Limits', app.HardRange, 'Value', -40, 'ValueChangedFcn', @(s, ~) app.onRange("covX", 1, s.Value));
            app.Cov_Spinner_XMax = app.place(@uispinner, r, 2, 4, 'Limits', app.HardRange, 'Value', 10, 'ValueChangedFcn', @(s, ~) app.onRange("covX", 2, s.Value));
            app.UIFigure.Visible = 'on';
        end

        function onBasis(app), app.BasisAuto = false; app.on("cut"); end

        function onApplyClim(app)
            lim = [app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value]; app.Range.Auto.full = false; app.Range.Auto.cut = false;
            app.applyRange("full", lim, ~app.isAR()); app.applyRange("cut", lim); app.on("range");
        end
    end
end

% =============================================================== READERS ===============================================================
function S = io_read(fp, fmt, raw)
%IO_READ Dispatch by extension → Source {Raw, Blocks (tables Theta, Phi, +columns), Freqs, Meta{Format, Unit, UnitLabel, IsGainOnly, IsCoverage, ColNames, Notes}}.
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
S = struct('Raw', table(), 'Blocks', {{}}, 'Freqs', NaN, 'Meta', struct('Format', string(ext), 'Unit', "dB", 'UnitLabel', "dB (rel. field)", ...
    'IsGainOnly', false, 'IsCoverage', false, 'ColNames', strings(1, 0), 'Notes', strings(1, 0)));
switch ext
    case {'XLSX', 'XLS'}, S = io_excel(fp, S);
    case {'CSV', 'TXT', 'DAT'}, S = io_text(fp, fmt, raw, S);
    case 'CUT', S = io_cut(fp, S);
    case {'UAN', 'FZ', 'OUT', 'FFS', 'FFE', 'FFD'}, S = io_farfield(fp, ext, S);
    otherwise, error('APAT:Unsupported', 'Unsupported format: %s', ext);
end
end

function s = io_spec(key)
%IO_SPEC Layout of every six-column field table: logical column order (θ φ a b c d), magnitude domain, polarisation basis, unit, raw names.
%   magphase: a b c d = |E1| ∠E1 |E2| ∠E2 (dB, deg);   rect: Re E1, Im E1, Re E2, Im E2.   Grouped files (m m p p) use order [1 2 3 5 4 6].
s = struct('format', "", 'order', 1:6, 'domain', "rect", 'basis', "thetaphi", 'unit', "dB", 'names', {{'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}});
switch key
    case {'UAN', 'FZ'}, s.format = "XGTD " + key; s.order = [1 2 3 5 4 6]; s.domain = "magphase"; s.unit = "dBi"; s.names = {'Theta', 'Phi', 'E_TH_dB', 'E_TH_deg', 'E_PH_dB', 'E_PH_deg'};
    case 'OUT', s.format = "TICRA/GRASP OUT"; s.basis = "rcplcp"; s.unit = "dBi"; s.names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'};
    case 'FFS', s.format = "CST FFS"; s.order = [2 1 3 4 5 6];
    case 'FFE', s.format = "FEKO FFE";
    case 'FFD', s.format = "HFSS FFD";
    otherwise                                                    % generic text: <linear|rcp_lcp|lcp_rcp>_<magphase|reim>
        parts = split(string(key), '_'); s.format = "Generic text (" + key + ")"; s.domain = replace(parts(end), "reim", "rect");
        if parts(1) == "linear", comp = ["E_TH" "E_PH"]; else, comp = ["POL1" "POL2"]; s.basis = parts(1) + parts(2); end
        if s.domain == "magphase", suf = ["_dB" "_deg"]; s.order = [1 2 3 5 4 6]; else, suf = ["_real" "_imag"]; end
        s.names = cellstr(["Theta" "Phi" comp(1) + suf comp(2) + suf]);
end
end

function nm = io_rawNames(s)
%IO_RAWNAMES Column names in FILE order: raw column order(k) carries logical name k.
nm = s.names; nm(s.order) = s.names;
end

function [Eth, Eph] = io_fields(M, s)
%IO_FIELDS Six numeric columns → complex Eθ, Eφ through the spec: pick, un-log, rotate the basis (one converter for nine layouts).
A = M(:, s.order(3:6));
if s.domain == "magphase", c1 = 10.^(A(:, 1)/20) .* exp(1i*deg2rad(A(:, 2))); c2 = 10.^(A(:, 3)/20) .* exp(1i*deg2rad(A(:, 4)));
else, c1 = complex(A(:, 1), A(:, 2)); c2 = complex(A(:, 3), A(:, 4)); end
switch s.basis
    case "thetaphi", Eth = c1; Eph = c2;
    case "rcplcp", [Eth, Eph] = pol_fromCircular(c1, c2);
    case "lcprcp", [Eth, Eph] = pol_fromCircular(c2, c1);
end
end

function B = io_block(th, ph, Eth, Eph)
B = table(th(:), ph(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function S = io_farfield(fp, ext, S)
%IO_FARFIELD UAN/FZ, OUT, FFS (one block), FFE (blocks split on "#Frequency:"), FFD (header grid, blocks split on "Frequency" rows).
s = io_spec(ext); S.Meta.Format = s.format; S.Meta.Unit = s.unit; if s.unit == "dBi", S.Meta.UnitLabel = "dBi"; end
if ext == "FFE"
    L = readlines(fp); t = strtrim(L); mark = find(startsWith(t, "#Frequency", 'IgnoreCase', true)); if isempty(mark), mark = 0; end
    ends = [mark(2:end) - 1; numel(t)]; S.Freqs = nan(1, numel(mark));
    for b = 1:numel(mark)
        if mark(b) > 0, v = sscanf(char(extractAfter(t(mark(b)), ':')), '%f'); if ~isempty(v), S.Freqs(b) = v(1); end, end
        rows = t(mark(b) + 1:ends(b)); rows = rows(strlength(rows) > 0 & ~startsWith(rows, ["#", "*", "/"]));
        n = numel(sscanf(char(rows(1)), '%f')); M = reshape(sscanf(char(strjoin(rows, newline)), '%f'), n, []).';
        [Eth, Eph] = io_fields(M, s); S.Blocks{b} = io_block(M(:, 1), M(:, 2), Eth, Eph);
    end
    S.Raw = S.Blocks{1}; if numel(mark) > 1, S.Meta.Notes(end + 1) = sprintf("%d frequency blocks; block 1 shown in the Input tab.", numel(mark)); end   % FFE raw == block layout
    return
end
[nHdr, ffd, t] = io_headerLines(fp);
o = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = readmatrix(fp, setvartype(o, 'double')); M = M(~all(isnan(M), 2), :);
if ext == "FFD"
    assert(ffd.isFFD, 'APAT:FFD', 'FFD header (theta/phi ranges) not found.');
    th = linspace(ffd.theta(1), ffd.theta(2), round(ffd.theta(3))).'; ph = linspace(ffd.phi(1), ffd.phi(2), round(ffd.phi(3))).';
    sep = isnan(M(:, 1)); fr = [ffd.freq(:); M(sep, min(2, end))]; fr = fr(isfinite(fr)); F = M(~sep, 1:4); per = numel(th)*numel(ph);
    assert(mod(size(F, 1), per) == 0, 'APAT:FFD', 'FFD row count does not match the θ/φ grid.');
    nb = size(F, 1)/per; ang = [repelem(th, numel(ph)), repmat(ph, numel(th), 1)]; S.Freqs = nan(1, nb); S.Freqs(1:min(nb, numel(fr))) = fr(1:min(nb, numel(fr)));
    for b = 1:nb, Fb = F((b - 1)*per + (1:per), :); S.Blocks{b} = io_block(ang(:, 1), ang(:, 2), complex(Fb(:, 1), Fb(:, 2)), complex(Fb(:, 3), Fb(:, 4))); end
    S.Raw = S.Blocks{1}; if nb > 1, S.Meta.Notes(end + 1) = sprintf("%d frequency blocks; block 1 shown in the Input tab.", nb); end
    return
end
assert(size(M, 2) >= 6, 'APAT:Columns', '%s needs six numeric columns; found %d.', ext, size(M, 2));
if ext == "UAN" || ext == "FZ"
    hdr = lower(strjoin(t(1:min(nHdr + 1, end)), ' '));
    if contains(hdr, 'begin_<parameters>') && ~(contains(hdr, 'mag_phase') && contains(hdr, 'theta_phi'))
        error('APAT:UnsupportedUAN', 'UAN header declares a layout other than mag_phase / theta_phi; APAT reads only that layout.');
    end
end
M = M(:, 1:6); [Eth, Eph] = io_fields(M, s); S.Raw = array2table(M, 'VariableNames', io_rawNames(s));
S.Blocks = {io_block(M(:, s.order(1)), M(:, s.order(2)), Eth, Eph)};
end

function [nHdr, ffd, t] = io_headerLines(fp)
%IO_HEADERLINES Leading non-data line count; HFSS FFD header = two numeric triples (θ, φ: start stop count) + optional "Frequencies ...".
t = strtrim(readlines(fp)); ffd = struct('isFFD', false, 'theta', [], 'phi', [], 'freq', []);
isNum = @(s) ~isempty(regexp(s, '^[-+]?(\d+\.?\d*|\.\d+)([eEdD][-+]?\d+)?([\s,;]+[-+]?(\d+\.?\d*|\.\d+)([eEdD][-+]?\d+)?)*$', 'once'));
ne = find(strlength(t) > 0, 3);
if numel(ne) >= 2 && isNum(t(ne(1))) && isNum(t(ne(2))) && numel(sscanf(char(t(ne(1))), '%f')) == 3 && numel(sscanf(char(t(ne(2))), '%f')) == 3
    ffd = struct('isFFD', true, 'theta', sscanf(char(t(ne(1))), '%f').', 'phi', sscanf(char(t(ne(2))), '%f').', 'freq', []); nHdr = ne(2);
    if numel(ne) == 3
        tok = regexp(t(ne(3)), '^frequencies?\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok), v = sscanf(char(tok{1}), '%f'); if numel(v) > 1 || startsWith(t(ne(3)), "frequencies", 'IgnoreCase', true), nHdr = ne(3); end, if numel(v) > 1, ffd.freq = v(:); end, end
    end
    return
end
nHdr = 0;
for i = 1:numel(t)
    if isNum(t(i)) && numel(sscanf(char(t(i)), '%f')) >= 4, break; end
    nHdr = i;
end
end

function S = io_text(fp, fmt, raw, S)
%IO_TEXT CSV/TXT/DAT: coverage results, a gain-only pattern (fmt "gain"/"auto") or a six-column field table interpreted by FMT.
if isempty(raw)
    o = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    o = setvaropts(setvartype(o, 'double'), 'TrimNonNumeric', true); o.VariableNamingRule = 'preserve'; raw = readtable(fp, o);
end
if fmt == "auto", fmt = "gain"; end
names = string(raw.Properties.VariableNames); low = lower(names); hasHdr = ~all(startsWith(names, "Var")); nc = width(raw);
assert(nc >= 2 && height(raw) > 0, 'APAT:Text', 'File needs at least two numeric columns.');
raw = raw(all(isfinite(raw{:, 1:2}), 2), :); c1 = raw{:, 1}; V = raw{:, 2:end};   % drop only rows without a direction (D24)
covKey = contains(low(1), "threshold") || any(contains(low(2:end), "coverage"));
covShape = ~hasHdr && (fmt == "gain" || nc < 6) && all(V >= 0 & V <= 100, 'all') && issorted(c1, 'strictmonotonic') && all(diff(V) <= 1e-9, 'all');
if covKey || covShape                                                              % a CCDF: [0,100] %, non-increasing, monotone thresholds (D27)
    if ~hasHdr, raw.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:nc - 1))]; end
    S.Raw = raw; S.Meta.IsCoverage = true; S.Meta.Format = "Coverage results"; return
end
if fmt == "gain"
    ti = find(contains(low(1:2), ["theta" "el"]), 1); pj = find(contains(low(1:2), ["phi" "az"]), 1); order = [1 2];
    if hasHdr && ~isempty(ti) && ~isempty(pj) && ti ~= pj, order = [ti pj]; S.Meta.Notes(end + 1) = "θ/φ columns identified by their header names.";
    else, if max(c1) - min(c1) > max(V(:, 1)) - min(V(:, 1)), order = [2 1]; end, S.Meta.Notes(end + 1) = "θ/φ columns assigned by span (the wider span is φ); no usable header."; end
    vn = matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(cellstr(names(3:end))), {'Theta', 'Phi'}); if ~hasHdr, vn = cellstr(compose('Gain%d_dB', 1:nc - 2)); if nc == 3, vn = {'Gain_dB'}; end, end
    B = [table(raw{:, order(1)}, raw{:, order(2)}, 'VariableNames', {'Theta', 'Phi'}), raw(:, 3:end)]; B.Properties.VariableNames(3:end) = vn;
    if ~hasHdr, raw.Properties.VariableNames(order) = {'Theta', 'Phi'}; raw.Properties.VariableNames(3:end) = vn; end
    S.Meta.IsGainOnly = true; S.Meta.ColNames = string(vn); S.Meta.Format = "Generic text (gain)"; S.Meta.Unit = "dB"; S.Meta.UnitLabel = "dB";
    if any(contains(low, "dbi")), S.Meta.Unit = "dBi"; S.Meta.UnitLabel = "dBi"; end
    S.Raw = raw; S.Blocks = {B}; return
end
assert(nc >= 6, 'APAT:Text', 'The selected generic E-field format requires six numeric columns.');
M = raw{:, 1:6}; s = io_spec(char(fmt));
if s.domain == "magphase"                                                          % grouped (m m p p, default) or interleaved (m p m p)
    if hasHdr, inter = contains(low(4), ["phase" "deg"]) && ~contains(low(5), ["phase" "deg"]); else, big = max(abs(M(:, 3:6)), [], 1, 'omitnan') > 100; inter = big(2) && ~big(3); end
    if inter, s.order = 1:6; S.Meta.Notes(end + 1) = "Magnitude/phase columns read as interleaved (m p m p)."; else, S.Meta.Notes(end + 1) = "Magnitude/phase columns read as grouped (m m p p)."; end
end
[Eth, Eph] = io_fields(M, s); if ~hasHdr, raw.Properties.VariableNames(1:6) = io_rawNames(s); end
S.Meta.Format = s.format; S.Raw = raw; S.Blocks = {io_block(M(:, 1), M(:, 2), Eth, Eph)};
end

function S = io_cut(fp, S)
%IO_CUT TICRA/GRASP .cut: blocks of [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data]. ICOMP 1 = Eθ/Eφ, 2 = RHCP/LHCP (else unsupported, D19).
S.Meta.Format = "TICRA/GRASP CUT"; L = readlines(fp); L(strlength(strtrim(L)) == 0) = []; i = 1; th = []; ph = []; D = zeros(0, 4); icomp = 1; icut = 1;
while i < numel(L)
    p = sscanf(char(L(i + 1)), '%f'); assert(numel(p) >= 7, 'APAT:CUT', 'Could not parse cut parameter line %d.', i + 1);
    n = p(3); icomp = p(5); icut = p(6); blk = reshape(sscanf(char(strjoin(L(i + 2:i + 1 + n), ' ')), '%f'), 2*p(7), []).';
    th = [th; p(1) + (0:n - 1).'*p(2)]; ph = [ph; repmat(p(4), n, 1)]; D = [D; blk(:, 1:4)]; i = i + 2 + n; %#ok<AGROW>
end
assert(icomp == 1 || icomp == 2, 'APAT:UnsupportedICOMP', 'GRASP cut ICOMP = %d is not supported (1 = theta/phi, 2 = RHCP/LHCP).', icomp);
if icut == 2, [th, ph] = deal(ph, th); S.Meta.Notes(end + 1) = "ICUT = 2: φ swept at constant θ."; end
if isscalar(unique(ph)), k = numel(th); th = repmat(th, 36, 1); ph = repelem((0:10:350).', k); D = repmat(D, 36, 1); S.Meta.Notes(end + 1) = "Single cut replicated every 10° in φ (body of revolution)."; end
if icomp == 2, [Eth, Eph] = pol_fromCircular(complex(D(:, 1), D(:, 2)), complex(D(:, 3), D(:, 4))); nm = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'};
else, Eth = complex(D(:, 1), D(:, 2)); Eph = complex(D(:, 3), D(:, 4)); nm = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; end
S.Raw = array2table([th ph D], 'VariableNames', [{'Theta', 'Phi'}, nm]); S.Blocks = {io_block(th, ph, Eth, Eph)};
end

function S = io_excel(fp, S)
%IO_EXCEL Matrix workbooks: sheet 1 = summary; fixed component sheets (Etheta/Ephi and/or RHCP/LHCP gain dBi + phase deg) with a C3-origin matrix.
sheets = string(sheetnames(fp)); circ = ["RHCP_Gain_dBi" "RHCP_Phase_degrees" "LHCP_Gain_dBi" "LHCP_Phase_degrees"]; lin = ["Etheta_Gain_dBi" "Etheta_Phase_degrees" "Ephi_Gain_dBi" "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'APAT:Excel', 'Unsupported workbook: sheet 1 must be the summary and the other sheets the fixed Eth/Eph and/or RHCP/LHCP component sheets.');
req = strings(1, 0); if hasC, req = [req circ]; end, if hasL, req = [req lin]; end, m = struct(); ref = [];
for k = 1:numel(req)
    C = readcell(fp, 'Sheet', char(sheets(strcmpi(sheets, req(k)))));
    isn = @(c) cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), c);
    pm = isn(C(2, 3:end)); tm = isn(C(3:end, 2)); np = find(~pm, 1) - 1; nt = find(~tm, 1) - 1; if isempty(np), np = numel(pm); end, if isempty(nt), nt = numel(tm); end
    assert(np > 0 && nt > 0 && all(pm(1:np)) && all(tm(1:nt)), 'APAT:Excel', 'Sheet "%s" has no contiguous numeric θ/φ axes at B3↓ / C2→.', req(k));
    ax = struct('theta', cell2mat(C(3:2 + nt, 2)), 'phi', cell2mat(C(2, 3:2 + np))); data = C(3:2 + nt, 3:2 + np);
    assert(all(isn(data), 'all'), 'APAT:Excel', 'Sheet "%s" contains non-numeric matrix samples.', req(k));
    if isempty(ref), ref = ax; else, assert(isequal(size(ax.theta), size(ref.theta)) && isequal(size(ax.phi), size(ref.phi)) && max(abs(ax.theta - ref.theta)) < 1e-9 && max(abs(ax.phi - ref.phi)) < 1e-9, 'APAT:Excel', 'All component sheets must share one θ/φ grid.'); end
    m.(char(req(k))) = cell2mat(data);
end
E = @(g, p) 10.^(g/20) .* exp(1i*deg2rad(p));
if hasL, Eth = E(m.Etheta_Gain_dBi, m.Etheta_Phase_degrees); Eph = E(m.Ephi_Gain_dBi, m.Ephi_Phase_degrees); S.Meta.Format = "Excel Matrix Format 1 (Eth/Eph)";
else, [Eth, Eph] = pol_fromCircular(E(m.RHCP_Gain_dBi, m.RHCP_Phase_degrees), E(m.LHCP_Gain_dBi, m.LHCP_Phase_degrees)); S.Meta.Format = "Excel Matrix Format 2 (Ercp/Elcp)"; end
if hasL && hasC, S.Meta.Format = "Excel Matrix Format 3 (Ercp/Elcp + Eth/Eph)"; end
[PH, TH] = meshgrid(ref.phi, ref.theta); S.Blocks = {io_block(TH, PH, Eth, Eph)}; S.Raw = S.Blocks{1};
for k = 1:numel(req), v = m.(char(req(k))); S.Raw.(char(req(k))) = v(:); end
S.Meta.Unit = "dBi"; S.Meta.UnitLabel = "dBi"; fMHz = xl_lookup(fp, sheets(1), 'Pattern Simulation Freq (MHz):');
if isfinite(fMHz), S.Freqs = fMHz*1e6; end
end

function v = xl_lookup(fp, sheet, label)
%XL_LOOKUP Numeric value to the right of a labelled summary cell; NaN when absent.
v = NaN; C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); n = @(x) regexprep(lower(strtrim(x)), '[^a-z0-9]', '');
[r, c] = find(cellfun(@(x) (ischar(x) || isstring(x)) && strcmp(n(char(x)), n(label)), C), 1);
if isempty(r), return; end
for k = c + 1:size(C, 2), if isnumeric(C{r, k}) && isscalar(C{r, k}) && isfinite(C{r, k}), v = C{r, k}; return; end, end
end

% ============================================================ NUMERICAL CORE ============================================================
function P = pat_build(S, f)
%PAT_BUILD Canonical grid-native pattern from source block f: polar θ↑ in [0,180], φ↑ in [0,360), uniform axes asserted once (I1).
%   Angles are snapped to 5 decimals; field values are never rounded (D03). Duplicate directions (e.g. φ = 0 and 360) keep the first sample.
T = S.Blocks{min(f, numel(S.Blocks))}; th = double(T.Theta); ph = double(T.Phi); notes = S.Meta.Notes;
ok = isfinite(th) & isfinite(ph); T = T(ok, :); th = th(ok); ph = ph(ok);
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, th = 90 - th; notes(end + 1) = "θ read as elevation (−90..90°) and folded to polar θ = 90° − el.";
    else, neg = th < 0; th(neg) = -th(neg); ph(neg) = ph(neg) + 180; notes(end + 1) = "Negative θ folded onto φ + 180°."; end
end
th = mod(th, 360); over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;
th = round(th, 5); ph = mod(round(ph, 5), 360);
[~, keep] = unique([ph th], 'rows'); th = th(keep); ph = ph(keep); T = T(keep, :);
P.Theta = unique(th); P.Phi = unique(ph); n = numel(P.Theta); m = numel(P.Phi);
P.dTheta = util_assertUniform(P.Theta, 'θ', 180); P.dPhi = util_assertUniform(P.Phi, 'φ', 360);
if numel(th) ~= n*m, error('APAT:NonUniformGrid', 'Irregular grid: %d directions on a %d × %d θ×φ axis set (APAT requires a complete rectangular grid).', numel(th), n, m); end
idx = sub2ind([n m], round((th - P.Theta(1))/P.dTheta) + 1, round((ph - P.Phi(1))/P.dPhi) + 1);
P.IsGainOnly = S.Meta.IsGainOnly; P.Meta = S.Meta; P.Meta.Notes = notes; P.Freq = S.Freqs(min(f, numel(S.Freqs))); P.Revision = 1; P.G = struct(); P.Eth = []; P.Eph = [];
if P.IsGainOnly, for c = string(S.Meta.ColNames), P.G.(c) = util_grid(T.(c), idx, n, m); end
else, P.Eth = util_grid(complex(T.Re_Eth, T.Im_Eth), idx, n, m); P.Eph = util_grid(complex(T.Re_Eph, T.Im_Eph), idx, n, m); end
end

function step = util_assertUniform(axis, name, fallback)
%UTIL_ASSERTUNIFORM Median step of a sorted axis; every gap must agree to 1e-6° (§15-1), else APAT:NonUniformGrid.
d = diff(axis); if isempty(d), step = fallback; return; end
step = median(d);
if any(abs(d - step) > 1e-6), error('APAT:NonUniformGrid', '%s axis is not uniform: steps range %.6g°..%.6g° (APAT requires uniform grids).', name, min(d), max(d)); end
end

function G = util_grid(v, idx, n, m), G = nan(n, m); G(idx) = v; end

function P = pat_resample(P, step)
%PAT_RESAMPLE Exact decimation when target/native is an integer on both axes; otherwise bilinear on power + unit phasor (I6, B.5).
%   Target axes never leave the source domain (D05). Columns are derived afterwards, never interpolated.
if numel(P.Theta) < 2 || numel(P.Phi) < 2, return; end
kt = step/P.dTheta; kp = step/P.dPhi; periodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
if abs(kt - round(kt)) < 1e-9 && abs(kp - round(kp)) < 1e-9 && kt >= 1 && kp >= 1
    r = 1:round(kt):numel(P.Theta); c = 1:round(kp):numel(P.Phi); f = @(X, ~) X(r, c); P.Theta = P.Theta(r); P.Phi = P.Phi(c);
    note = sprintf('Decimated %g°/%g° → %g° (every %d/%d sample, exact).', P.dTheta, P.dPhi, step, round(kt), round(kp));
else
    th = P.Theta; ph = P.Phi; th2 = (th(1):step:th(end)).';
    if periodic, ph2 = (ph(1):step:ph(1) + 360 - step/2).'; else, ph2 = (ph(1):step:ph(end)).'; end
    f = @(X, kind) pat_interp(X, th, ph, th2, ph2, periodic, kind); P.Theta = th2; P.Phi = ph2;
    note = sprintf('Resampled %g°/%g° → %g° by bilinear interpolation (power + unit phasor for fields, linear power for gain).', P.dTheta, P.dPhi, step);
end
if P.IsGainOnly, for nm = string(fieldnames(P.G)).', P.G.(nm) = f(P.G.(nm), util_colKind(nm)); end
else, P.Eth = f(P.Eth, "field"); P.Eph = f(P.Eph, "field"); end
P.dTheta = step; P.dPhi = step; P.Revision = P.Revision + 1; P.Meta.Notes(end + 1) = note;
end

function Y = pat_interp(X, th, ph, th2, ph2, periodic, kind)
%PAT_INTERP Bilinear resampling of one quantity on the (φ-closed) grid: "field" → |E|² and E/|E| separately (B.5); "gain" → linear power; else linear.
if periodic, X(:, end + 1) = X(:, 1); ph(end + 1) = ph(1) + 360; end
[PH, TH] = meshgrid(ph, th); [PH2, TH2] = meshgrid(ph2, th2); I = @(Z) interp2(PH, TH, Z, PH2, TH2, 'linear');
switch kind
    case "field", u = I(X ./ max(abs(X), realmin)); Y = sqrt(I(abs(X).^2)) .* u ./ max(abs(u), realmin);
    case "gain", Y = 10*log10(max(I(10.^(X/10)), realmin));
    otherwise, Y = I(X);
end
end

function G = geo_build(P)
%GEO_BUILD Separable cell solid angles on the uniform grid (I2):  wθ(i) = cos(θᵢ − Δθ/2) − cos(θᵢ + Δθ/2) (edges clipped to [0°,180°]),
%   ΔΩ(i,j) = wθ(i)·Δφ.  Full sphere: Σ wθ = 2 (telescoping) and nφ·Δφ = 2π ⇒ Σ ΔΩ = 4π exactly (B.1).
lo = max(P.Theta(:) - P.dTheta/2, 0); hi = min(P.Theta(:) + P.dTheta/2, 180);
G.wTheta = cosd(lo) - cosd(hi); G.dPhi = deg2rad(P.dPhi);
G.PhiPeriodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6; G.IsFullSphere = G.PhiPeriodic && lo(1) == 0 && hi(end) == 180;
G.dOmega = G.wTheta * G.dPhi * ones(1, numel(P.Phi)); G.Omega = sum(G.dOmega, 'all');
end

function M = geo_displayMap(P, G, view)
%GEO_DISPLAYMAP Column permutation and axis relabelling for the display convention; no data is copied or changed (I8).
n = numel(P.Phi); j0 = find(P.Phi >= 180, 1); perm = 1:n;
if view.SignedPhi && ~isempty(j0), perm = [j0:n, 1:j0 - 1]; end
M.ColIdx = perm; M.PhiAxis = P.Phi(perm);
if view.SignedPhi, M.PhiAxis(M.PhiAxis >= 180) = M.PhiAxis(M.PhiAxis >= 180) - 360; end
if G.PhiPeriodic, M.ColIdx(end + 1) = perm(1); M.PhiAxis(end + 1) = M.PhiAxis(1) + 360; end   % closing column for display only
if view.Elevation, M.ThetaAxis = 90 - P.Theta; M.ThetaDir = 'normal'; M.ThetaLabel = "Elevation";
else, M.ThetaAxis = P.Theta; M.ThetaDir = 'reverse'; M.ThetaLabel = "Theta"; end
M.Key = sprintf('%d|%d', view.SignedPhi, view.Elevation);
end

function c = geo_cut(P, cols, type, value)
%GEO_CUT One full-circle cut through the canonical grid; COLS is a cell of nθ×nφ matrices → c.y (N × numel(cols)).
%   "Phi": fixed θ, sweep φ (closing point appended when φ is periodic).  "Theta": fixed φ, sweep θ over the pole and down the
%   opposite meridian, where angle = 360° − θ.  The snapped fixed angle and the physical (θ, φ) of every point are returned.
if type == "Phi"
    [~, i] = min(abs(P.Theta - value)); c.fixed = P.Theta(i); c.symbol = 'θ'; m = numel(P.Phi);
    rows = repmat(i, m, 1); cidx = (1:m).'; c.angle = P.Phi(:);
    if abs(m*P.dPhi - 360) < 1e-6, rows(end + 1) = i; cidx(end + 1) = 1; c.angle(end + 1) = P.Phi(1) + 360; end
else
    d = @(a, b) abs(mod(a - b + 180, 360) - 180); n = numel(P.Theta);
    [~, j] = min(d(P.Phi, value)); c.fixed = P.Phi(j); c.symbol = 'φ'; [gap, j2] = min(d(P.Phi, c.fixed + 180));
    rows = (1:n).'; cidx = repmat(j, n, 1); c.angle = P.Theta(:);
    if gap <= P.dPhi/2 + 1e-9 && j2 ~= j                       % opposite meridian present: θ < 180 in reverse → angles 180 … 360
        back = flipud(find(P.Theta < 180 - 1e-9)); rows = [rows; back]; cidx = [cidx; repmat(j2, numel(back), 1)]; c.angle = [c.angle; 360 - P.Theta(back)];
    end
end
c.type = type; c.snapped = abs(c.fixed - value) > 1e-9; c.theta = P.Theta(rows); c.phi = P.Phi(cidx);
lin = sub2ind([numel(P.Theta), numel(P.Phi)], rows, cidx); c.y = zeros(numel(lin), numel(cols));
for k = 1:numel(cols), c.y(:, k) = cols{k}(lin); end
end

function D = pat_derive(P, G, prm)
%PAT_DERIVE Every column and every base fact of a pattern at the given parameters, in one pass (I3, B.3). ≈ 40 ms at 1°×1°.
if P.IsGainOnly
    C = P.G; names = string(fieldnames(C)).'; kinds = arrayfun(@util_colKind, names);
    for c = names(kinds == "gain"), C.(c) = C.(c) + prm.L; end                      % loss on gain-kind columns only (§15-10)
    D.TotalName = names(find(kinds == "gain", 1)); if isempty(D.TotalName), D.TotalName = names(1); end
    D.Pol = struct('pairs', struct('Linear', ["E_TH" "E_PH"], 'Circular', ["E_RCP" "E_LCP"]), 'label', 'n/a');
else
    s = 10^(prm.L/20); Eth = P.Eth*s; Eph = P.Eph*s;                               % loss / gain as an incident-field scale
    Er = pol_circular(Eth, Eph, 1); El = pol_circular(Eth, Eph, 2);
    C.E_Total_dB = 10*log10(max(abs(Eth).^2 + abs(Eph).^2, eps));
    C.E_TH_dB = 20*log10(max(abs(Eth), eps)); C.E_PH_dB = 20*log10(max(abs(Eph), eps));
    C.E_RCP_dB = 20*log10(max(abs(Er), eps)); C.E_LCP_dB = 20*log10(max(abs(El), eps));
    [C.AR_dB, isLinear] = pol_signedAR(Er, El);
    D.Pol = pol_classify(Eth, Eph, Er, El, G);
    C.PLF_dB = pol_plf(C.AR_dB, isLinear, prm.RxMode, prm.RxAR_dB, D.Pol.pairs.Circular(1));
    C.Gain_PolCorrected_dB = C.E_Total_dB + C.PLF_dB;
    C.E_TH_Phase = rad2deg(angle(Eth)); C.E_PH_Phase = rad2deg(angle(Eph)); C.E_RCP_Phase = rad2deg(angle(Er)); C.E_LCP_Phase = rad2deg(angle(El));
    C.EIRP_dBW = prm.Pt_dBW + C.E_Total_dB;
    C.PFD_Wm2 = 10.^(C.EIRP_dBW/10) ./ (4*pi*prm.R_m^2);
    C.E_RMS_Vm = sqrt(30*10.^(C.EIRP_dBW/10)) ./ prm.R_m;
    D.TotalName = "E_Total_dB";
end
D.Cols = C; total = C.(D.TotalName);
D.Peak = met_peak(total, G.PhiPeriodic, APAT_v3_M8_7.PeakExcessDB);                    % I5
D.Boresight = met_orientation(total, P, G, D.Peak);                                    % principal axis with the most power in its 45° cone
D.Planes = met_planes(D.Boresight);
D.Metrics = met_metrics(total, P, G, D.Peak, D.Planes, C, P.Meta.Unit);
end

function K = met_peak(C, periodic, excessDB)
%MET_PEAK Effective peak = highest sample that is not an isolated spike (I5). spike(i,j) ⇔ C(i,j) − max(4 grid neighbours) > excessDB;
%   φ wraps when periodic. Raw and effective peaks are both reported. Base MATLAB only (no percentile, no toolbox).
[n, m] = size(C); nb = -inf(n, m);
nb(2:n, :) = max(nb(2:n, :), C(1:n - 1, :)); nb(1:n - 1, :) = max(nb(1:n - 1, :), C(2:n, :));
if periodic, L = circshift(C, 1, 2); R = circshift(C, -1, 2); else, L = [-inf(n, 1), C(:, 1:m - 1)]; R = [C(:, 2:m), -inf(n, 1)]; end
nb = max(nb, max(L, R));
K.spike = isfinite(C) & (C - nb > excessDB);
[K.rawValue, K.rawIndex] = max(C(:), [], 'omitnan');
cand = C; cand(K.spike) = -Inf; [K.value, K.index] = max(cand(:));
K.wasAdjusted = K.spike(K.rawIndex); K.spikeCount = nnz(K.spike);
end

function k = met_orientation(total, P, G, peak)
%MET_ORIENTATION Principal axis whose 45° cone carries the most radiated power  Σ 10^((G−Gp)/10)·ΔΩ  (spikes excluded).
A = APAT_v3_M8_7.PrincipalAxes; w = 10.^((total - peak.value)/10) .* G.dOmega; w(~isfinite(w) | peak.spike) = 0; e = zeros(1, 6);
for a = 1:6, e(a) = sum(w(cov_coneMask(P, A.theta(a), A.phi(a), 45)), 'all'); end
[~, k] = max(e);
end

function S = met_planes(axisIndex)
%MET_PLANES E-plane: θ-cut through the boresight axis' φ. H-plane: the orthogonal cut — a φ-cut at θ = 90° for a transverse axis
%   (±X, ±Y), a θ-cut at φ = 90° for ±Z (§15-6). Values are canonical; the display convention is applied by the UI layer.
A = APAT_v3_M8_7.PrincipalAxes; S.E = struct('type', "Theta", 'value', A.phi(axisIndex));
if A.theta(axisIndex) == 90, S.H = struct('type', "Phi", 'value', 90); else, S.H = struct('type', "Theta", 'value', 90); end
end

function M = met_metrics(total, P, G, peak, planes, C, unit)
%MET_METRICS Directivity, efficiency, front-to-back, HPBW (E/H) and AR at the peak — all on total gain (I4), spikes removed from
%   numerator AND solid angle (D07); efficiency and F/B only on a full sphere, efficiency only for dBi sources (I9).
keep = isfinite(total) & ~peak.spike; prad = sum(10.^(total(keep)/10) .* G.dOmega(keep)); om = sum(G.dOmega(keep));
[r, c] = ind2sub(size(total), peak.index);
M.PeakGain_dB = peak.value; M.PeakTheta_deg = P.Theta(r); M.PeakPhi_deg = P.Phi(c);
M.PeakDirectivity_dB = 10*log10(max(om*10^(peak.value/10)/max(prad, realmin), realmin));     % Ω·U_max / ∫U dΩ over the kept region
M.Efficiency_pct = NaN; M.FrontBack_dB = NaN;
if G.IsFullSphere && unit == "dBi", M.Efficiency_pct = 100*prad/om; if M.Efficiency_pct > 100, M.Efficiency_pct = NaN; end, end
if G.IsFullSphere, [~, rb] = min(abs(P.Theta - (180 - P.Theta(r)))); [~, cb] = min(abs(mod(P.Phi - P.Phi(c), 360) - 180)); M.FrontBack_dB = peak.value - total(rb, cb); end
for pl = ["E" "H"], cut = geo_cut(P, {total}, planes.(pl).type, planes.(pl).value); M.("HPBW_" + pl + "Plane_deg") = met_hpbw(cut.angle, cut.y); end
M.AxialRatioAtPeak_dB = NaN; if isfield(C, 'AR_dB'), M.AxialRatioAtPeak_dB = C.AR_dB(peak.index); end
end

function [bw, lo, hi] = met_hpbw(a, g, gp, ap)
%MET_HPBW Half-power beamwidth of one circular cut: the first −3 dB crossings either side of the peak, linearly interpolated.
[bw, lo, hi] = deal(NaN); v = isfinite(a) & isfinite(g); a = a(v); g = g(v); if numel(g) < 3, return; end
if nargin < 3, [gp, i] = max(g); ap = a(i); end
[ra, o] = sort(mod(a - ap + 180, 360) - 180); rg = g(o); h = gp - 3;
L = find(ra < 0 & rg <= h, 1, 'last'); R = find(ra > 0 & rg <= h, 1, 'first');
if isempty(L) || isempty(R) || L + 1 > numel(rg) || R < 2 || rg(L + 1) == rg(L) || rg(R - 1) == rg(R), return; end
x = @(i, j) ra(i) + (ra(j) - ra(i)) * (h - rg(i)) / (rg(j) - rg(i));               % crossing between outside sample i and inside sample j
lo = ap + x(L, L + 1); hi = ap + x(R, R - 1); bw = hi - lo;
end

function E = pol_circular(Eth, Eph, which)
%POL_CIRCULAR RHCP (which = 1) / LHCP (which = 2) component of E = Eθ θ̂ + Eφ φ̂ under e^{+jωt} with (θ̂, φ̂, r̂) right-handed (I10, B.4):
%   ê_R = (θ̂ − jφ̂)/√2 (IEEE right-hand),  E_R = E·ê_R* = (Eθ + jEφ)/√2,  E_L = (Eθ − jEφ)/√2.   Check: E = ê_R ⇒ E_R = 1, E_L = 0.
if which == 1, E = (Eth + 1i*Eph)/sqrt(2); else, E = (Eth - 1i*Eph)/sqrt(2); end
end

function [Eth, Eph] = pol_fromCircular(Er, El)
%POL_FROMCIRCULAR Inverse of pol_circular (OUT, CUT ICOMP = 2, Excel format 2, generic rcp/lcp layouts).
Eth = (Er + El)/sqrt(2); Eph = (Er - El)/(1i*sqrt(2));
end

function [AR, isLinear] = pol_signedAR(Er, El)
%POL_SIGNEDAR Signed axial ratio in dB: + RHCP sense, − LHCP sense; −100 dB at (numerically) linear samples (§15-2).
r = abs(Er); l = abs(El); d = r - l; isLinear = isfinite(d) & abs(d) <= eps .* max(r + l, 1);
AR = min(20*log10((r + l) ./ max(abs(d), eps)), 250) .* sign(d); AR(isLinear) = -100;
end

function pol = pol_classify(Eth, Eph, Er, El, G)
%POL_CLASSIFY Co/cross ordering and dominant polarisation from the Ω-weighted radiated power of each component (D13).
p = @(E) sum(abs(E).^2 .* G.dOmega, 'all', 'omitnan'); pTH = p(Eth); pPH = p(Eph); pR = p(Er); pL = p(El);
pol.pairs.Linear = ["E_TH" "E_PH"]; if pPH > pTH, pol.pairs.Linear = fliplr(pol.pairs.Linear); end
pol.pairs.Circular = ["E_RCP" "E_LCP"]; if pL > pR, pol.pairs.Circular = fliplr(pol.pairs.Circular); end
if max(pR, pL) > max(pTH, pPH), pol.label = sprintf('Circular (%s)', replace(pol.pairs.Circular(1), ["E_RCP" "E_LCP"], ["RHCP" "LHCP"]));
elseif pTH >= pPH, pol.label = 'Linear (Vertical)'; else, pol.label = 'Linear (Horizontal)'; end
end

function plf = pol_plf(AR_dB, isLinear, rxMode, rxAR_dB, leadingCircular)
%POL_PLF Polarisation loss factor between the antenna ellipse (signed AR) and the incident wave (rxMode, rxAR_dB), major axes orthogonal:
%   PLF = 1/2 + (4·ρa·ρw − (ρa² − 1)(ρw² − 1)) / (2(ρa² + 1)(ρw² + 1)),  ρ = signed linear axial ratio (+RHCP, −LHCP). NaN in ⇒ NaN out (D08).
switch rxMode, case "RHCP", sw = 1; case "LHCP", sw = -1; otherwise, sw = 2*(leadingCircular == "E_RCP") - 1; end
ra = 10.^(abs(AR_dB)/20) .* sign(AR_dB); ra(isLinear) = 1e12; rw = sw * 10^(rxAR_dB/20);
plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1)) ./ (2*(ra.^2 + 1)*(rw^2 + 1));
plf = 10*log10(min(max(plf, eps), 1)); plf(~isfinite(AR_dB)) = NaN;
end

function cov = cov_curve(C, dOmega, mask, T)
%COV_CURVE Coverage(T) = 100 · Ω_R(C > T) / Ω_R,   Ω_R(C > T) = Σ_{(i,j)∈R, C(i,j) > T} ΔΩ(i,j)   (I7, strict ">", O(N) memory).
v = mask & isfinite(C); g = C(v); w = dOmega(v); Omega = sum(w);
cov = zeros(size(T)); if Omega <= 0, return; end
cov = 100 * arrayfun(@(t) sum(w(g > t)), T) / Omega;
end

function m = cov_coneMask(P, thC, phC, alphaDeg)
%COV_CONEMASK (i,j) ∈ cone ⇔ cos γ ≥ cos α,  cos γ = cos θᵢ cos θc + sin θᵢ sin θc cos(φⱼ − φc)  (spherical law of cosines).
m = cosd(P.Theta(:))*cosd(thC) + sind(P.Theta(:))*sind(thC).*cosd(P.Phi(:).' - phC) >= cosd(alphaDeg) - 1e-12;
end

function T = cov_thresholds(tMin, tMax, step)
%COV_THRESHOLDS T = tMin + (0:n)·step by counting (D11); tMax is always included.
if tMax <= tMin, tMax = tMin + step; end
n = floor((tMax - tMin)/step + 1e-9); T = tMin + (0:n).'*step; if T(end) < tMax - 1e-9, T(end + 1) = tMax; end
end

function y = cov_at(job, T)
%COV_AT Coverage at threshold(s) T read off the job's curve (linear between samples, NaN outside).
y = interp1(job.T, job.cov, T, 'linear', NaN);
end

function T = thr_at(job, c)
%THR_AT Threshold at coverage c %: inverse read of the same curve; per coverage level the highest threshold reaching it ('last').
[cv, i] = unique(job.cov, 'last'); if numel(cv) < 2, T = nan(size(c)); return; end
T = interp1(cv, job.T(i), c, 'linear', NaN);
end

function k = util_colKind(name)
%UTIL_COLKIND gain | ar | plf | phase | link | other, from a column name (drives loss, theme, cuts, visibility, resampling domain).
s = regexprep(lower(string(name)), '[^a-z0-9]', '');
if s == "ar" || startsWith(s, "ardb") || contains(s, "axialratio"), k = "ar";        % not every "ar…" column (e.g. Array_Gain_dBi) is an axial ratio
elseif startsWith(s, "plf"), k = "plf";
elseif contains(s, "phase") || endsWith(s, "deg") || endsWith(s, "dg"), k = "phase";
elseif contains(s, ["eirp" "pfd" "erms"]), k = "link";
elseif contains(s, ["gain" "directivity"]) || endsWith(s, ["db" "dbi"]), k = "gain";
else, k = "other"; end
end

function s = util_fmtNumber(v, prec)
%UTIL_FMTNUMBER Compact (≤ 2 dp, no trailing zeros, never "-0") or fixed-precision text; 'n/a' for non-finite input.
if ~(isscalar(v) && isnumeric(v) && isfinite(v)), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); else, s = sprintf('%.*f', prec, v); end
if strcmp(s, '-0') || isempty(s), s = '0'; end
end

function b = util_presetRange(peak)
%UTIL_PRESETRANGE 50-dB window under the next multiple of 5 above the peak (colour scale, cut range and coverage thresholds).
if ~isfinite(peak), b = [-40 10]; return; end
hi = 5*ceil(peak/5); b = min(max([hi - 50, hi], -250), 100);
end

function r = util_polarRadius(values, lim)
%UTIL_POLARRADIUS Radius of the polar-3D surface and its overlay: clamp to the colour scale, normalise to [0, 1].
r = max(values - lim(1), 0) / max(lim(2) - lim(1), eps);
end

function t = util_ticks(lim, step)
%UTIL_TICKS Colorbar / z-axis ticks at multiples of STEP inside LIM, with both limits included (≤ 60 ticks).
t = []; if ~(isfinite(step) && step > 0 && diff(lim) > 0), return; end
t = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)]); if numel(t) > 60, t = []; end
end