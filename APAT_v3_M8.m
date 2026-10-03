classdef APAT_v3_M8 < matlab.apps.AppBase
%APAT_V3_M8  Antenna Pattern Analysis Tool — release M8 (single-truth rebuild of APAT_v3_M7_110_5): one file,
%   base MATLAB (R2023b+), no toolboxes, App Designer-style handles. Same tabs, features and input formats as M7:
%   Pattern (five full-pattern views, cuts, metrics, exports), Input, Results, Coverage tabs.
%
%   DATAFLOW (one direction; nothing is copied, nothing is synchronised)
%     FILE ─► io_read ─► Source ─► pat_build (+pat_resample) ─► Pattern ─► geo_build ─► Geometry ─► pat_derive(P, G, Params) ─► Derived
%     app.Pats(k) = {Key, Name, Path, Source, Pattern, Geometry, Derived, Params}; coverage nodes store k, Main reads Pats(app.Main).
%     VIEW = readConfig() ─► MAP = geo_displayMap(View) ─► renderers (index permutation + labels only).
%
%   RULES  * Widgets are READ only in readConfig/readCoverageConfig, WRITTEN only in apply*/render* methods.
%     * File-scope functions are app-free and widget-free; update(scope) commits one assignment (an error leaves state intact).
%     * Peak, boresight, planes and metrics live on total gain; the component changes plots, cuts, tables and the POB marker only.
%     * Conventions live in Const / Meta and are listed in the Metadata table.
%
%   Run:  app = APAT_v3_M8;        Self-test (no UI):  APAT_v3_M8.selfTest

    %% ============================================================ UI handles (App Designer style)
    properties (Access = public)
        UIFigure                    matlab.ui.Figure
        MainTabGroup                matlab.ui.container.TabGroup
        Tab_Main                    matlab.ui.container.Tab
        Tab_Input                   matlab.ui.container.Tab
        Tab_Results                 matlab.ui.container.Tab
        Tab_Coverage                matlab.ui.container.Tab
        % Pattern tab — file bar
        Single_Button_Browse        matlab.ui.control.Button
        Single_EditField_File       matlab.ui.control.EditField
        Single_DropDown_TextFormat  matlab.ui.control.DropDown
        Single_DropDown_Freq        matlab.ui.control.DropDown
        Single_Button_Process       matlab.ui.control.Button
        Single_Button_Coverage      matlab.ui.control.Button
        Single_Export_Output        matlab.ui.control.Button
        Single_Export_UAN           matlab.ui.control.Button
        % Pattern tab — parameters
        Single_Panel_Params         matlab.ui.container.Panel
        Single_Spinner_Loss         matlab.ui.control.Spinner
        Single_DropDown_RxPol       matlab.ui.control.DropDown
        Single_Spinner_Rw           matlab.ui.control.Spinner
        Single_Spinner_Pt           matlab.ui.control.Spinner
        Single_DropDown_Pt          matlab.ui.control.DropDown
        Single_Spinner_R            matlab.ui.control.Spinner
        Single_DropDown_R           matlab.ui.control.DropDown
        Single_Button_Reset         matlab.ui.control.Button
        % Pattern tab — plot control
        Single_Panel_plotControl    matlab.ui.container.Panel
        Single_DropDown_Component   matlab.ui.control.DropDown
        Single_DropDown_step        matlab.ui.control.DropDown
        Single_DropDown_3DView      matlab.ui.control.DropDown
        Single_Switch_ThetaSpan     matlab.ui.control.Switch
        Single_Switch_PhiSpan       matlab.ui.control.Switch
        Single_Spinner_Cmin         matlab.ui.control.Spinner
        Single_Spinner_Cmax         matlab.ui.control.Spinner
        Single_Plot_Cstep           matlab.ui.control.Spinner
        Single_Button_AutoRange     matlab.ui.control.Button
        Single_CheckBox_POB         matlab.ui.control.CheckBox
        Single_CheckBox_Overlay     matlab.ui.control.CheckBox
        Single_Table_metadata       matlab.ui.control.Table
        % Pattern tab — full-pattern views (M7 tab set: contour, fisheye, sphere, polar, surface)
        Single_Panel_fullPattern    matlab.ui.container.Panel
        Single_TabGroup_Full        matlab.ui.container.TabGroup
        Single_tabContour           matlab.ui.container.Tab
        Single_tabCircular          matlab.ui.container.Tab
        Single_tab3DSpherical       matlab.ui.container.Tab
        Single_tab3DPolar           matlab.ui.container.Tab
        Single_tab3DRect            matlab.ui.container.Tab
        Single_Axes_Ctr             matlab.ui.control.UIAxes
        Single_paxPattern           matlab.graphics.axis.PolarAxes
        Single_Axes_3dSph           matlab.ui.control.UIAxes
        Single_Axes_3dPol           matlab.ui.control.UIAxes
        Single_Axes_3dRect          matlab.ui.control.UIAxes
        % Pattern tab — cuts
        Single_Panel_Rect           matlab.ui.container.Panel
        Single_Switch_EHplane       matlab.ui.control.Switch
        Single_DropDown_cutType     matlab.ui.control.DropDown
        Single_DropDown_cutValue    matlab.ui.control.Spinner
        CutFieldBasisDropDown       matlab.ui.control.DropDown
        Single_gridEcut             matlab.ui.container.GridLayout
        CheckBox_Et                 matlab.ui.control.CheckBox
        CheckBox_Er                 matlab.ui.control.CheckBox
        CheckBox_El                 matlab.ui.control.CheckBox
        Button_HPBW                 matlab.ui.control.StateButton
        Label_HPBW                  matlab.ui.control.Label
        Single_Spinner_CutMin       matlab.ui.control.Spinner
        Single_Spinner_CutMax       matlab.ui.control.Spinner
        Button_ExportCut            matlab.ui.control.Button
        Single_paxCut               matlab.graphics.axis.PolarAxes
        Single_AxesRect             matlab.ui.control.UIAxes
        Single_StatusBar            matlab.ui.control.Label
        % Input / Results tabs
        Input_Label                 matlab.ui.control.Label
        Input_Table                 matlab.ui.control.Table
        Single_DropDown_output      matlab.ui.control.DropDown
        Single_Table_DataOut        matlab.ui.control.Table
        % Coverage tab
        Cov_Tree                    matlab.ui.container.CheckBoxTree
        Cov_TreeNode_Patterns       matlab.ui.container.TreeNode
        Cov_TreeNode_Results        matlab.ui.container.TreeNode
        Cov_Button_AddPattern       matlab.ui.control.Button
        Cov_Button_LoadResults      matlab.ui.control.Button
        Cov_Button_Remove           matlab.ui.control.Button
        Cov_DropDown_Component      matlab.ui.control.DropDown
        Cov_ButtonGroup_CovType     matlab.ui.container.ButtonGroup
        Cov_Radio_Spherical         matlab.ui.control.RadioButton
        Cov_Radio_Conical           matlab.ui.control.RadioButton
        Cov_DropDown_Orientation    matlab.ui.control.DropDown
        Cov_Spinner_ConeTheta       matlab.ui.control.Spinner
        Cov_Spinner_ConePhi         matlab.ui.control.Spinner
        Cov_Spinner_ConeAngle       matlab.ui.control.Spinner
        Cov_Spinner_ThreshMin       matlab.ui.control.Spinner
        Cov_Spinner_ThreshMax       matlab.ui.control.Spinner
        Cov_Spinner_ThreshStep      matlab.ui.control.Spinner
        Cov_Button_Compute          matlab.ui.control.Button
        Cov_Axes                    matlab.ui.control.UIAxes
        Cov_Spinner_Xmin            matlab.ui.control.Spinner
        Cov_Spinner_Xmax            matlab.ui.control.Spinner
        Cov_Spinner_Ymin            matlab.ui.control.Spinner
        Cov_Spinner_Ymax            matlab.ui.control.Spinner
        Cov_Button_AutoRange        matlab.ui.control.Button
        Cov_Spinner_QueryThr        matlab.ui.control.Spinner
        Cov_Spinner_QueryCov        matlab.ui.control.Spinner
        Cov_Button_QueryThr         matlab.ui.control.Button
        Cov_Button_QueryCov         matlab.ui.control.Button
        Cov_Button_ClearTips        matlab.ui.control.Button
        Cov_Button_Export           matlab.ui.control.Button
        Cov_Tabel                   matlab.ui.control.Table
        Cov_StatusBar               matlab.ui.control.Label
    end

    %% ============================================================ State
    properties (Access = private)
        Pats = []                   % registry: struct array {Key, Name, Path, Source, Pattern, Geometry, Derived, Params}
        Main = 0                    % index of the Pattern-tab entry in Pats (0 = nothing loaded)
        View = struct()             % last readConfig()
        Map = struct()              % last geo_displayMap()
        Range                       % display ranges {full, cut, cov, covX} + Auto flags
        Gfx = struct()              % retained graphics handles (created once, updated in place)
        Perf = struct()             % seconds per action scope (developer channel: app.Perf / APAT_PROFILE=1)
        Status = struct('Main', '', 'Cov', '')   % persistent text of each status bar
        StatusTimer                 % the single transient-status timer
        Dialog                      % active cancellable progress dialog (if any)
        Busy = false
        IsClosing = false
        JobCounter = 0              % coverage job ids
        Stamp = 0                   % increments on every Derived commit (render-key ingredient)
        InputStamp = ''             % key of the rows last pushed to the Input tab
        OutKey = ''                 % key of the rows last pushed to the Results tab
        OutMask = false             % Results column selection, aligned with fieldnames(Derived.Cols)
        DefaultParams               % parameter widget values at startup (Reset button)
        Tips = gobjects(0)          % coverage query datatips
    end

    %% ============================================================ Conventions (one place each; shown in Metadata)
    properties (Constant)
        Const = struct( ...
            'ReleaseName',        'APAT v3 M8', ...
            'PeakExcessDB',       6, ...       % spike = exceeds every grid neighbour by more than this
            'LinearAR_dB',        -100, ...    % signed AR displayed at numerically linear samples
            'FloorDB',            -100, ...    % dB floor for zero power / zero PLF
            'AngleDecimals',      5, ...       % angles are snapped; field values are never rounded
            'UniformTolDeg',      1e-4, ...    % uniform-axis assertion (> snapping error of 5-decimal angles)
            'RevolutionPhiStep',  10, ...      % single-cut body-of-revolution synthesis (disclosed)
            'ConeHalfAngleDeg',   45, ...      % boresight-axis selection cone
            'DistanceFloorM',     1e-3, ...
            'StatusSeconds',      3, ...
            'ViewCamera',         {{'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}})  % 3-D camera presets
        Axes6 = struct('labels', {{'+X', '-X', '+Y', '-Y', '+Z', '-Z'}}, 'theta', [90 90 90 90 0 180], 'phi', [0 180 90 270 0 0])
        FileFilter = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.txt;*.dat', 'Antenna patterns'; '*.*', 'All files'}
        TextFormats = {{'Auto (detect)', '1: Gain pattern', '2: Etheta/Ephi — dB magnitude, phase', ...
                        '3: Etheta/Ephi — real, imaginary', '4: POL1=RCP, POL2=LCP — dB magnitude, phase', ...
                        '5: POL1=LCP, POL2=RCP — dB magnitude, phase', '6: POL1=RCP, POL2=LCP — real, imaginary', ...
                        '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                       {'auto', 'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', ...
                        'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'}}
    end

    %% ============================================================ Lifecycle
    methods (Access = public)
        function app = APAT_v3_M8()
            app.createComponents();
            registerApp(app, app.UIFigure);
            app.initState();
            if nargout == 0, clear app; end
        end
        function delete(app)
            app.IsClosing = true;
            if ~isempty(app.StatusTimer) && isvalid(app.StatusTimer), stop(app.StatusTimer); delete(app.StatusTimer); end
            app.closeDialog();
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end
    end

    %% ============================================================ Orchestration
    methods (Access = private)
        function initState(app)
            app.Range = struct('full', [-50 0], 'cut', [-50 0], 'cov', [0 100], 'covX', [-40 10], 'Auto', struct('full', true, 'cut', true, 'cov', true, 'covX', true));
            app.DefaultParams = app.readConfig().Params;
            app.StatusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', app.Const.StatusSeconds, 'TimerFcn', @(~, ~) app.restoreStatus());
            app.initGraphics();
            app.applyVisibility(false);
            app.setStatus(app.Single_StatusBar, 'Select a pattern file to begin.', false);
            app.setStatus(app.Cov_StatusBar, 'Add a pattern or load a results file.', false);
            app.UIFigure.Visible = 'on';
        end
        function on(app, scope)
        % ON Every callback lands here: busy guard, cancellable progress, error boundary, one drawnow.
            if app.Busy || app.IsClosing, return; end
            app.Busy = true; t0 = tic;
            busyGuard = onCleanup(@() app.setBusy(false));
            app.UIFigure.Pointer = 'watch';
            if any(scope == ["source", "rebuild", "fmt", "covAdd", "covCompute"])
                app.Dialog = uiprogressdlg(app.UIFigure, 'Title', app.Const.ReleaseName, 'Message', 'Working…', 'Indeterminate', 'on', 'Cancelable', 'on');
                dlgGuard = onCleanup(@() app.closeDialog());
            end
            try
                app.update(string(scope));
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled')
                    app.setStatus(app.statusBarOf(scope), 'Cancelled.', true);
                else
                    app.setStatus(app.statusBarOf(scope), ['Error: ' ME.message], true);
                    if ~app.IsClosing && isvalid(app.UIFigure), uialert(app.UIFigure, ME.message, app.Const.ReleaseName, 'Icon', 'error'); end
                end
            end
            name = matlab.lang.makeValidName(char(scope));
            app.Perf.(name) = toc(t0);
            if getenv("APAT_PROFILE"), fprintf('%-14s %6.1f ms\n', name, 1000*app.Perf.(name)); end
            app.setBusy(false);
            if isvalid(app.UIFigure), app.UIFigure.Pointer = 'arrow'; end
            drawnow limitrate
        end
        function setBusy(app, tf), if ~app.IsClosing, app.Busy = tf; end, end
        function bar = statusBarOf(app, scope), if startsWith(string(scope), "cov"), bar = app.Cov_StatusBar; else, bar = app.Single_StatusBar; end, end
        function closeDialog(app)
            if ~isempty(app.Dialog)
                try if isvalid(app.Dialog), delete(app.Dialog); end, catch, end
                app.Dialog = [];
            end
        end
        function checkCancelled(app)
            if ~isempty(app.Dialog) && isvalid(app.Dialog) && app.Dialog.Cancelled, error('APAT:Cancelled', 'Cancelled by the user.'); end
        end
        function update(app, scope, arg)
        % UPDATE Recompute exactly the invalidation radius of SCOPE, then let renderers reconcile keys.  SOURCE ─► PATTERN(Rev) ─► GEOMETRY ─► DERIVED(Rev, Params)   committed into Pats(Main) in one step VIEW ─► MAP ─► ColIdx / axes / labels / cut-value domain      touches nothing above
            if startsWith(scope, "cov"), app.updateCoverage(scope, arg); return; end
            if strcmp(scope, "browse")
                [f, p] = uigetfile(app.FileFilter, 'Select an antenna pattern file', app.startDir());
                if isequal(f, 0), return; end
                arg = fullfile(p, f); scope = "source";
            elseif strcmp(scope, "fmt")                    % text-format change: re-read the file from scratch
                if app.Main == 0, return; end
                arg = char(app.Pats(app.Main).Path); scope = "source";
            elseif strcmp(scope, "reset")
                app.applyParams(app.DefaultParams); scope = "params";
            end
            is = @(varargin) any(scope == string(varargin));   % created AFTER re-targeting: anonymous fns capture by value
            if is("export"),   app.exportMain(arg); return; end
            if is("exportcut"), app.exportCut(); return; end
            if is("filter"),   app.onOutputFilter(); return; end
            if is("source", "rebuild")
                if scope == "source"
                    path = string(arg); source = [];
                    if app.Main == 0 || string(app.Pats(app.Main).Path) ~= path
                        app.Single_DropDown_TextFormat.Value = 'auto';         % a fresh file starts on auto-detect
                    end
                    cfg = app.readConfig(); cfg.FreqIndex = 1; cfg.StepChoice = "native";   % fresh file: first block, native step
                else
                    if app.Main == 0, return; end
                    path = app.Pats(app.Main).Path; source = app.Pats(app.Main).Source; cfg = app.readConfig();
                end
                try
                    E = app.buildEntry(path, cfg, source);            % may throw: nothing committed yet (I13)
                catch ME
                    if ~strcmp(ME.identifier, 'APAT:CoverageFile'), rethrow(ME); end
                    app.covLoadResults(char(path));                   % a coverage-results file routes to Coverage
                    app.MainTabGroup.SelectedTab = app.Tab_Coverage; app.covRefresh();
                    return
                end
                if app.Main == 0, app.Pats = [app.Pats, E]; app.Main = numel(app.Pats); else, app.Pats(app.Main) = E; end
                app.Stamp = app.Stamp + 1;
                app.Single_EditField_File.Value = char(path);
                app.Range.Auto.full = true; app.Range.Auto.cut = true;
                app.applyChoices(E);
                app.covRefreshPatternNodes();
            elseif is("params")
                if app.Main == 0, return; end
                cfg = app.readConfig(); E = app.Pats(app.Main);
                D = pat_derive(E.Pattern, E.Geometry, cfg.Params, app.Const, app.Axes6);
                app.Pats(app.Main).Derived = D; app.Pats(app.Main).Params = cfg.Params;   % one assignment per entry
                app.Stamp = app.Stamp + 1;
            end
            if app.Main == 0, return; end
            if is("plane"), app.applyPlane(); end
            if is("range"), app.Range.(arg) = app.readRange(arg); app.Range.Auto.(arg) = false; end
            if is("autorange"), app.Range.Auto.full = true; app.Range.Auto.cut = true; end
            canon = [];                                                       % keep the cut through a span toggle
            if is("span") && isfield(app.View, 'CutType'), canon = util_cutCanonical(app.View.CutType, app.View.CutValue, app.View.Elevation); end
            app.View = app.readConfig();
            E = app.Pats(app.Main);
            app.Map = geo_displayMap(E.Pattern, E.Geometry, app.View);
            if ~isempty(canon), app.setSpinner(app.Single_DropDown_cutValue, util_cutDisplay(app.View.CutType, canon, app.View.Elevation, app.View.SignedPhi)); end
            if is("source", "rebuild", "span", "cuttype", "plane"), app.applyCutDomain(); app.View = app.readConfig(); end
            if is("source", "rebuild", "params", "component", "autorange"), app.applyAutoRanges(); end
            app.renderFull();
            app.renderCut();
            if is("source", "rebuild", "params", "component", "span", "plane"), app.applyMetadata(); app.applyStatus(); end
            app.applyInputTable();
            app.applyResults();
        end
        function E = buildEntry(app, path, cfg, source)
        % BUILDENTRY Source → Pattern → Geometry → Derived for one file, into locals only (I13).
            if isempty(source), source = io_read(char(path), cfg.TextFormat); end
            if source.Meta.IsCoverage, error('APAT:CoverageFile', 'This file holds coverage results; it belongs on the Coverage tab.'); end
            P = pat_build(source, min(max(cfg.FreqIndex, 1), numel(source.Blocks)), app.Const);
            if cfg.StepChoice == "1deg", P = pat_resample(P, 1); end
            G = geo_build(P);
            D = pat_derive(P, G, cfg.Params, app.Const, app.Axes6);
            [~, name, ext] = fileparts(char(path));
            E = struct('Key', string(path), 'Name', string([name ext]), 'Path', string(path), 'Source', source, ...
                       'Pattern', P, 'Geometry', G, 'Derived', D, 'Params', cfg.Params);
        end
        function d = startDir(app)
            d = pwd;
            if app.Main > 0, d = fileparts(char(app.Pats(app.Main).Path)); end
        end

        %% ------------------------------------------------ readConfig: the ONLY place Pattern-tab widgets are read
        function cfg = readConfig(app)
            cfg.Component  = string(app.Single_DropDown_Component.Value);
            cfg.CutType    = string(app.Single_DropDown_cutType.Value);          % "Theta": θ-cut at fixed φ | "Phi": φ-cut at fixed θ
            cfg.CutValue   = app.Single_DropDown_cutValue.Value;
            cfg.Basis      = string(app.CutFieldBasisDropDown.Value);            % "Auto" | "Linear" | "Circular"
            cfg.Traces     = logical([app.CheckBox_Et.Value, app.CheckBox_Er.Value, app.CheckBox_El.Value]);
            cfg.HPBW       = logical(app.Button_HPBW.Value);
            cfg.POB        = logical(app.Single_CheckBox_POB.Value);
            cfg.Overlay    = logical(app.Single_CheckBox_Overlay.Value);
            cfg.Elevation  = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°');
            cfg.SignedPhi  = strcmp(app.Single_Switch_PhiSpan.Value, '-180° to 180°');
            cfg.CStep      = app.Single_Plot_Cstep.Value;
            cfg.Camera     = string(app.Single_DropDown_3DView.Value);
            cfg.TextFormat = string(app.Single_DropDown_TextFormat.Value);
            cfg.FreqIndex  = app.Single_DropDown_Freq.Value;
            cfg.StepChoice = string(app.Single_DropDown_step.Value);             % "native" | "1deg"
            cfg.FullView   = str2double(app.Single_TabGroup_Full.SelectedTab.Tag);
            cfg.InputTab   = app.MainTabGroup.SelectedTab == app.Tab_Input;
            cfg.ResultsTab = app.MainTabGroup.SelectedTab == app.Tab_Results;
            power = app.Single_Spinner_Pt.Value;
            switch app.Single_DropDown_Pt.Value
                case 'dBm',   ptdBW = power - 30;
                case 'Watts', ptdBW = 10*log10(max(power, eps));
                otherwise,    ptdBW = power;
            end
            rm = max(app.Single_Spinner_R.Value, app.Const.DistanceFloorM);
            if strcmp(app.Single_DropDown_R.Value, 'km'), rm = 1000*rm; end
            cfg.Params = struct('L', app.Single_Spinner_Loss.Value, 'RxMode', string(app.Single_DropDown_RxPol.Value), ...
                                'RxAR_dB', app.Single_Spinner_Rw.Value, 'Pt_dBW', ptdBW, 'R_m', rm);
        end
        function r = readRange(app, group)
            if group == "full", r = [app.Single_Spinner_Cmin.Value, app.Single_Spinner_Cmax.Value];
            else,               r = [app.Single_Spinner_CutMin.Value, app.Single_Spinner_CutMax.Value]; end
            if ~(r(2) > r(1)), r = app.Range.(group); end
        end

        %% ------------------------------------------------ apply*: the ONLY places Pattern-tab widgets are written
        function applyChoices(app, E)
        % APPLYCHOICES Item lists, enables and default masks that depend on the loaded pattern.
            if isempty(E)                                                     % nothing loaded: defaults only
                set(app.Single_DropDown_Freq, 'Items', {'—'}, 'ItemsData', {1}, 'Value', 1);
                set(app.Single_DropDown_step, 'Items', {'STEP: native'}, 'ItemsData', {'native'}, 'Value', 'native');
                return
            end
            S = E.Source; P = E.Pattern; D = E.Derived;
            f = S.Freqs(:).'; items = cellstr(compose('%.6g GHz', f/1e9));
            for k = find(~isfinite(f)), items{k} = sprintf('Block %d', k); end
            dd = app.Single_DropDown_Freq; v = dd.Value;
            set(dd, 'Items', items, 'ItemsData', num2cell(1:numel(items)));
            dd.Value = min(max(v, 1), numel(items)); dd.Visible = numel(items) > 1;
            nat = P.NativeStep;
            if all(abs(nat - 1) < 1e-9)
                items = {'STEP: 1°'}; data = {'native'};
            else
                items = {sprintf('STEP: native (%s° × %s°)', util_fmtNumber(nat(1)), util_fmtNumber(nat(2))), 'STEP: 1°'};
                data = {'native', '1deg'};
            end
            dd = app.Single_DropDown_step; v = dd.Value;
            set(dd, 'Items', items, 'ItemsData', data);
            if any(strcmp(data, v)), dd.Value = v; end
            dd.Visible = numel(items) > 1;
            names = fieldnames(D.Cols).'; names = names(~startsWith(names, 'Phase_'));
            dd = app.Single_DropDown_Component; v = dd.Value;
            set(dd, 'Items', cellfun(@util_colLabel, names, 'UniformOutput', false), 'ItemsData', names);
            if any(strcmp(names, v)), dd.Value = v; elseif isfield(D.Cols, 'E_Total_dB'), dd.Value = 'E_Total_dB'; else, dd.Value = names{1}; end
            hasField = ~P.IsGainOnly; link = P.Meta.Unit == "dBi";
            set([app.Single_DropDown_RxPol, app.Single_Spinner_Rw, app.CutFieldBasisDropDown, app.CheckBox_Er, app.CheckBox_El], 'Enable', hasField);
            set([app.Single_Spinner_Pt, app.Single_DropDown_Pt, app.Single_Spinner_R, app.Single_DropDown_R], 'Enable', hasField && link);
            app.Single_Export_UAN.Enable = hasField;
            generic = isGenericText(E.Path);                                   % the format selector exists for generic text only
            set(app.Single_DropDown_TextFormat, 'Visible', generic);
            allNames = fieldnames(D.Cols).';
            app.OutMask = ~startsWith(allNames, 'Phase_');                     % Results columns: phase hidden by default
            app.applyOutputFilter();
            app.applyVisibility(true);
        end
        function applyVisibility(app, loaded)
            set([app.Single_Panel_Rect, app.Single_Panel_fullPattern, app.Single_Panel_plotControl, ...
                 app.Single_Export_Output, app.Single_Export_UAN, app.Single_Button_Coverage, ...
                 app.Single_Button_Process, app.Single_Table_metadata, app.Single_DropDown_output], 'Visible', loaded);
        end
        function applyParams(app, prm)
            app.Single_Spinner_Loss.Value = prm.L; app.Single_DropDown_RxPol.Value = char(prm.RxMode);
            app.Single_Spinner_Rw.Value = prm.RxAR_dB; app.Single_Spinner_Pt.Value = prm.Pt_dBW;
            app.Single_DropDown_Pt.Value = 'dBW'; app.Single_Spinner_R.Value = prm.R_m; app.Single_DropDown_R.Value = 'm';
        end
        function applyPlane(app)
        % APPLYPLANE E/H switch → cut controls from the principal-axis planes of the loaded pattern.
            D = app.Pats(app.Main).Derived; V = app.readConfig();
            plane = D.Planes.H; if startsWith(app.Single_Switch_EHplane.Value, 'E'), plane = D.Planes.E; end
            app.Single_DropDown_cutType.Value = char(plane.CutType);
            app.setSpinner(app.Single_DropDown_cutValue, util_cutDisplay(plane.CutType, plane.Fixed, V.Elevation, V.SignedPhi));
        end
        function applyCutDomain(app)
        % APPLYCUTDOMAIN Cut-value spinner domain follows the display convention of the fixed angle.
            V = app.View; P = app.Pats(app.Main).Pattern; M = app.Map;
            if V.CutType == "Theta", axisVals = M.PhiAxis(1:numel(P.Phi)); step = P.dPhi;
            else,                    axisVals = M.ThetaAxis;                step = P.dTheta; end
            canon = util_cutCanonical(V.CutType, V.CutValue, V.Elevation);
            shown = util_cutDisplay(V.CutType, canon, V.Elevation, V.SignedPhi);
            [~, i] = min(abs(axisVals - shown));
            app.setSpinner(app.Single_DropDown_cutValue, axisVals(i), [min(axisVals), max(axisVals)], step);
        end
        function setSpinner(~, sp, value, limits, step)
        % SETSPINNER Value first inside open limits, then the real limits (a value outside Limits is an error).
            sp.Limits = [-Inf Inf]; sp.Value = value;
            if nargin >= 4, sp.Limits = limits; end
            if nargin >= 5 && isfinite(step) && step > 0, sp.Step = step; end
        end
        function applyAutoRanges(app)
            D = app.Pats(app.Main).Derived; V = app.View;
            comp = V.Component; if ~isfield(D.Cols, comp), comp = D.GainName; end
            if app.Range.Auto.full, app.Range.full = app.presetRange(comp); end
            traces = app.cutTraceNames();
            if app.Range.Auto.cut, app.Range.cut = app.presetRange(traces{1}); end
            app.setSpinner(app.Single_Spinner_Cmin, app.Range.full(1)); app.setSpinner(app.Single_Spinner_Cmax, app.Range.full(2));
            app.setSpinner(app.Single_Spinner_CutMin, app.Range.cut(1)); app.setSpinner(app.Single_Spinner_CutMax, app.Range.cut(2));
        end
        function r = presetRange(app, name)
        % PRESETRANGE Display range per column kind; gain-like columns use the non-spike peak rounded up to 5 dB.
            D = app.Pats(app.Main).Derived;
            switch util_colKind(name)
                case "ar",     r = [-30 30];
                case "phase",  r = [-180 180];
                case "plf",    r = [-30 0];
                otherwise
                    C = D.Cols.(name); v = C(~D.Peak.spike & isfinite(C));
                    r = util_presetRange(max(v, [], 'all'));
            end
        end
        function [lims, cmap] = theme(app, name)
        % THEME Colour scale per column kind: signed AR is a fixed blue-white-red thermometer, phase is cyclic.
            switch util_colKind(name)
                case "ar",     lims = [-30 30];   cmap = app.Gfx.Maps.ar;
                case "phase",  lims = [-180 180]; cmap = app.Gfx.Maps.phase;
                otherwise,     lims = app.Range.full; cmap = app.Gfx.Maps.gain;
            end
        end
        function [names, labels, show] = cutTraceNames(app)
        % CUTTRACENAMES Total/co/cross for field sources, the selected column for gain-only sources.
            E = app.Pats(app.Main); D = E.Derived; V = app.View;
            if E.Pattern.IsGainOnly
                comp = V.Component; if ~isfield(D.Cols, comp), comp = D.GainName; end
                names = {comp}; labels = {util_colLabel(comp)}; show = true;
                return
            end
            basis = V.Basis;
            if basis == "Auto", basis = "Linear"; if startsWith(D.Pol.Label, "Circular"), basis = "Circular"; end, end
            pair = D.Pol.Pairs.(basis) + "_dB";
            names = {'E_Total_dB', char(pair(1)), char(pair(2))};
            labels = {'Total', [util_colLabel(names{2}) ' (co-pol)'], [util_colLabel(names{3}) ' (cross-pol)']};
            show = V.Traces;
        end
        function applyInputTable(app)
        % APPLYINPUTTABLE The raw source table is pushed to the Input tab lazily (only when visible and stale).
            E = app.Pats(app.Main);
            key = char(E.Path);
            if ~app.View.InputTab || strcmp(app.InputStamp, key), return; end
            app.Input_Table.Data = E.Source.Raw;
            app.Input_Label.Text = sprintf('%s — %s — %d rows as parsed (%s)', E.Name, E.Source.Meta.Format, ...
                                           height(E.Source.Raw), strjoin(cellstr(E.Source.Meta.Notes), '; '));
            app.InputStamp = key;
        end
        function applyResults(app)
        % APPLYRESULTS The displayed long table is pushed to the Results tab lazily (visible + key).
            if ~app.View.ResultsTab, return; end
            E = app.Pats(app.Main); M = app.Map;
            key = sprintf('%d|%s|%s', app.Stamp, M.Key, char('0' + app.OutMask));
            if strcmp(app.OutKey, key), return; end
            names = fieldnames(E.Derived.Cols).'; names = names(app.OutMask);
            n = numel(E.Pattern.Theta); m = numel(M.ColIdx);
            vals = cellfun(@(nm) reshape(E.Derived.Cols.(nm)(:, M.ColIdx), [], 1), names, 'UniformOutput', false);
            T = table(repmat(M.ThetaAxis(:), m, 1), repelem(M.PhiAxis(:), n), vals{:}, ...
                      'VariableNames', [{char(M.ThetaLabel)}, {'Phi'}, names.']);
            app.Single_Table_DataOut.Data = T;
            app.OutKey = key;
        end
        function applyOutputFilter(app)
        % APPLYOUTPUTFILTER Results column filter: items are all columns; a check mark marks the visible ones.
            dd = app.Single_DropDown_output;
            names = fieldnames(app.Pats(app.Main).Derived.Cols).';
            items = [{'--- column filter ---'}, names];
            on = find(app.OutMask) + 1; items(on) = append('✓ ', items(on));
            set(dd, 'Items', items, 'ItemsData', num2cell(0:numel(names)), 'Value', 0);
        end
        function onOutputFilter(app)
            v = app.Single_DropDown_output.Value;
            if v > 0, app.OutMask(v) = ~app.OutMask(v); app.OutKey = ''; app.applyOutputFilter(); app.applyResults(); end
        end
        function applyStatus(app)
            E = app.Pats(app.Main); D = E.Derived; M = D.Metrics;
            txt = sprintf('Pattern: %s | POB %s %s ( θ=%s°, φ=%s° )', E.Name, util_fmtNumber(D.Peak.value, 2), ...
                          E.Pattern.Meta.UnitLabel, util_fmtNumber(M.PeakTheta_deg), util_fmtNumber(M.PeakPhi_deg));
            if ~E.Pattern.IsGainOnly, txt = sprintf('%s | Polarization %s', txt, D.Pol.Label); end
            if D.Peak.wasAdjusted, txt = sprintf('%s | %d isolated spike(s) excluded', txt, D.Peak.spikeCount); end
            app.setStatus(app.Single_StatusBar, txt, false);
        end
        function applyMetadata(app)
        % APPLYMETADATA Facts, metrics, parameters and conventions — every convention APAT applies is listed here.
            E = app.Pats(app.Main); P = E.Pattern; G = E.Geometry; D = E.Derived; M = D.Metrics; K = app.Const;
            f = @util_fmtNumber;
            rows = {
                'Source format',        char(P.Meta.Format)
                'File',                 char(E.Name)
                'Level unit',           char(P.Meta.UnitLabel)
                'Samples',              sprintf('%d (θ: %d × φ: %d)', numel(P.Theta)*numel(P.Phi), numel(P.Theta), numel(P.Phi))
                'θ range / step',       sprintf('[%s°, %s°] / %s°', f(P.Theta(1)), f(P.Theta(end)), f(P.dTheta))
                'φ range / step',       sprintf('[%s°, %s°] / %s° (%s)', f(P.Phi(1)), f(P.Phi(end)), f(P.dPhi), util_iif(G.PhiPeriodic, 'periodic', 'open'))
                'Sphere coverage',      sprintf('%s sr (%s)', f(G.Omega, 3), util_iif(G.IsFullSphere, 'full sphere', 'partial'))};
            if isfinite(P.Freq), rows(end+1, :) = {'Frequency', sprintf('%.6g GHz', P.Freq/1e9)}; end
            if ~P.IsGainOnly
                rows(end+1, :) = {'Polarization', char(D.Pol.Label)};
                [~, labels] = app.cutTraceNames(); rows(end+1, :) = {'Cut co-pol / cross-pol', [labels{2} ' / ' labels{3}]};
            end
            rows = [rows; {
                'Peak (POB)',           sprintf('%s %s at [θ %s°, φ %s°]; raw max %s (policy: spatial isolation > %g dB, %d spike(s) excluded)', ...
                    f(D.Peak.value, 2), P.Meta.UnitLabel, f(M.PeakTheta_deg), f(M.PeakPhi_deg), f(D.Peak.rawValue, 2), K.PeakExcessDB, D.Peak.spikeCount)
                'Boresight axis',       app.Axes6.labels{D.Boresight}
                'E-plane / H-plane',    sprintf('%s / %s', util_planeText(D.Planes.E), util_planeText(D.Planes.H))
                'HPBW (E / H)',         sprintf('%s° / %s°', f(M.HPBW_EPlane_deg), f(M.HPBW_HPlane_deg))
                'Peak directivity',     sprintf('%s dB (relative to the region mean intensity)', f(M.PeakDirectivity_dB))
                'Radiation efficiency', util_iif(isfinite(M.Efficiency_pct), sprintf('%s %%', f(M.Efficiency_pct)), 'n/a (needs dBi on a full sphere)')
                'Front-to-back',        util_iif(isfinite(M.FrontBack_dB), sprintf('%s dB', f(M.FrontBack_dB)), 'n/a (partial sphere)')
                'AR at peak',           util_iif(isfinite(M.AxialRatioAtPeak_dB), sprintf('%s dB', f(M.AxialRatioAtPeak_dB)), 'n/a')
                'Parameters',           sprintf('Loss %s dB | Rx %s (AR %s dB) | Pt %s dBW | R %s m', f(E.Params.L), E.Params.RxMode, f(E.Params.RxAR_dB), f(E.Params.Pt_dBW), f(E.Params.R_m))
                'Conventions',          sprintf('E_R=(Eθ+jEφ)/√2 (IEEE RHCP, e^{+jωt}); PLF with aligned major axes; linear AR shown as %g dB; angles snapped to %d decimals', K.LinearAR_dB, K.AngleDecimals)}];
            for n = cellstr(P.Meta.Notes(:).'), rows(end+1, :) = {'Note', n{1}}; end %#ok<AGROW>
            app.Single_Table_metadata.Data = rows;
        end

        %% ------------------------------------------------ status (one timer for both bars)
        function setStatus(app, label, msg, transient)
            if app.IsClosing || isempty(label) || ~isgraphics(label), return; end
            stop(app.StatusTimer);
            label.Text = char(msg);
            if transient, start(app.StatusTimer); else, app.Status.(label.Tag) = char(msg); end
        end
        function restoreStatus(app)
            if app.IsClosing, return; end
            if isgraphics(app.Single_StatusBar), app.Single_StatusBar.Text = app.Status.Main; end
            if isgraphics(app.Cov_StatusBar), app.Cov_StatusBar.Text = app.Status.Cov; end
        end

        %% ------------------------------------------------ retained graphics
        function initGraphics(app)
        % INITGRAPHICS Colormaps, one context menu, colorbars, cut lines and markers — created exactly once.
            app.Gfx.Maps = struct('gain', jet(256), 'phase', hsv(256), 'ar', interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)));
            menu = uicontextmenu(app.UIFigure);
            uimenu(menu, 'Text', 'Auto colour range', 'MenuSelectedFcn', @(~, ~) app.on("autorange"));
            uimenu(menu, 'Text', 'Export this view as PNG…', 'MenuSelectedFcn', @(~, ~) app.on("export", "png"));
            uimenu(menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ~) app.deleteTips());
            axesList = [app.Single_Axes_Ctr, app.Single_paxPattern, app.Single_Axes_3dSph, app.Single_Axes_3dPol, app.Single_Axes_3dRect];
            F = repmat(struct('Axes', [], 'Colorbar', [], 'Surface', gobjects(0), 'Overlay', gobjects(0), ...
                              'Marker', gobjects(0), 'Label', gobjects(0), 'Topo', '', 'Key', ''), 1, 5);
            for v = 1:5, F(v).Axes = axesList(v); F(v).Colorbar = colorbar(axesList(v)); axesList(v).ContextMenu = menu; end
            app.Gfx.Full = F;
            pa = app.Single_paxCut; ra = app.Single_AxesRect; colors = lines(3);
            hold(pa, 'on'); hold(ra, 'on'); grid(ra, 'on');
            ra.ContextMenu = menu;
            pa.ThetaZeroLocation = 'top'; pa.ThetaDir = 'clockwise';
            for t = 1:3
                C.Polar(t) = polarplot(pa, NaN, NaN, 'LineWidth', 1.4, 'Color', colors(t, :));
                C.Rect(t)   = plot(ra, NaN, NaN, 'LineWidth', 1.4, 'Color', colors(t, :));
            end
            C.HPBWPatch = patch(ra, 'XData', NaN(4, 1), 'YData', NaN(4, 1), 'FaceColor', [0.9 0.6 0.1], 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
            C.HPBWPolar = polarplot(pa, NaN(2, 2), NaN(2, 2), '--', 'Color', [0.9 0.6 0.1], 'HandleVisibility', 'off');
            C.MarkerRect  = plot(ra, NaN, NaN, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off');
            C.MarkerPolar = polarplot(pa, NaN, NaN, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off');
            C.Text = text(ra, 0, 0, '', 'FontSize', 9, 'VerticalAlignment', 'bottom', 'Clipping', 'off');
            C.Key = '';
            app.Gfx.Cut = C;
            hold(app.Cov_Axes, 'on'); grid(app.Cov_Axes, 'on'); app.Cov_Axes.ContextMenu = menu;
            xlabel(app.Cov_Axes, 'Threshold (dB)'); ylabel(app.Cov_Axes, 'Coverage (%)');
            title(app.Cov_Axes, 'Coverage(T) = 100 · Ω_R(G > T) / Ω_R');
        end
        function deleteTips(app)
        % DELETETIPS Remove every data tip on the axes APAT owns (the one permitted findall: foreign objects).
            axesList = [app.Gfx.Full.Axes, app.Single_paxCut, app.Single_AxesRect, app.Cov_Axes];
            for ax = axesList
                if isgraphics(ax), t = findall(ax, 'Type', 'datatip'); delete(t(isgraphics(t))); end
            end
            delete(app.Tips(isgraphics(app.Tips))); app.Tips = gobjects(0);
        end
        function applyCamera(app, v)
        % APPLYCAMERA Camera preset of one 3-D view (2-D views are fixed; manual rotation survives until the next key change).
            if ~any(v == [3 4 5]), return; end
            ax = app.Gfx.Full(v).Axes;
            switch string(app.View.Camera)
                case "top",     view(ax, 0, 90);   camup(ax, [0 1 0]);
                case "bottom",  view(ax, 0, -90);  camup(ax, [0 1 0]);
                case "right",   view(ax, 90, 0);
                case "left",    view(ax, -90, 0);
                case "front",   view(ax, 0, 0);
                case "back",    view(ax, 180, 0);
                otherwise,      if v == 5, view(ax, -35, 35); else, view(ax, 135, 25); end; camup(ax, [0 0 1]);
            end
        end
        function k = cutKey(app)
            V = app.View;
            k = sprintf('%s|%g|%s|%s', V.CutType, V.CutValue, V.Basis, mat2str(V.Traces));
        end
        function [cut, labels, show] = currentCut(app)
        % CURRENTCUT One geo_cut of the current trace stack (the only cut extraction per change).
            E = app.Pats(app.Main); D = E.Derived; V = app.View;
            [names, labels, show] = app.cutTraceNames();
            C = zeros([size(D.Cols.(names{1})), numel(names)]);
            for t = 1:numel(names), C(:, :, t) = D.Cols.(names{t}); end
            cut = geo_cut(E.Pattern, C, V.CutType, util_cutCanonical(V.CutType, V.CutValue, V.Elevation));
        end
        function renderFull(app)
        % RENDERFULL The visible full-pattern tab only: objects are recreated on a topology change and updated in place otherwise; an unchanged key returns immediately. Five views, one renderer: 1 contour (φ-θ plane) · 2 fisheye (polar, r=θ) · 3 sphere · 4 polar-radius · 5 3-D surface.
            v = app.View.FullView; F = app.Gfx.Full(v); ax = F.Axes;
            E = app.Pats(app.Main); P = E.Pattern; G = E.Geometry; D = E.Derived; V = app.View; M = app.Map;
            comp = V.Component; if ~isfield(D.Cols, comp), comp = D.GainName; end
            [lims, cmap] = app.theme(comp);
            key = sprintf('%d|%s|%s|%g|%g|%g|%d|%d|%s|%s', app.Stamp, M.Key, comp, lims, V.CStep, V.POB, V.Overlay, ...
                          util_iif(V.Overlay, app.cutKey(), ''), V.Camera, char(P.Meta.UnitLabel));
            if strcmp(F.Key, key), return; end
            C = D.Cols.(comp); Cd = C(:, M.ColIdx);
            [PHd, THd] = meshgrid(M.PhiAxis, M.ThetaAxis);                     % display grids (rows = θ/elevation)
            yMap = M.ThetaAxis; Cmap = Cd;
            if numel(yMap) > 1 && yMap(1) > yMap(end), yMap = flipud(yMap); Cmap = flipud(Cd); end   % image rows ascend
            [PHg, THg] = meshgrid(P.Phi(M.ColIdx), P.Theta);                   % physical grids for the 3-D views
            X = sind(THg).*cosd(PHg); Y = sind(THg).*sind(PHg); Z = cosd(THg);
            r = util_polarRadius(Cd, lims);
            ticks = util_ticks(lims, V.CStep);
            lv = ticks; if numel(lv) < 2, lv = linspace(lims(1), lims(2), 11); end
            if v == 1, topo = sprintf('%s|%dx%d', char(M.Key), size(Cd));       % contour: recreate on any key change
            else,      topo = sprintf('%dx%d', size(Cd)); end                   % 3-D views: topology is size only
            if ~strcmp(F.Topo, topo) || ~isgraphics(F.Surface) || v == 1
                cla(ax); hold(ax, 'on');
                switch v
                    case 1, F.Surface = contourf(ax, M.PhiAxis, yMap, Cmap, lv, 'LineColor', 'none');
                    case 2, F.Surface = surface(ax, deg2rad(PHg), THg, zeros(size(Cd)), Cd, 'FaceColor', 'interp', 'EdgeColor', 'none');
                    case 3, F.Surface = surf(ax, X, Y, Z, Cd, 'EdgeColor', 'none', 'FaceColor', 'interp');
                    case 4, F.Surface = surf(ax, r.*X, r.*Y, r.*Z, Cd, 'EdgeColor', 'none', 'FaceColor', 'interp');
                    case 5, F.Surface = surf(ax, PHd, THd, Cd, 'EdgeColor', 'none', 'FaceColor', 'interp');
                end
                F.Surface.ContextMenu = app.Gfx.Full(v).Axes.ContextMenu;
                if any(v == [3 4])
                    F.Overlay = plot3(ax, NaN, NaN, NaN, 'k-', 'LineWidth', 1.5);
                    F.Marker  = plot3(ax, NaN, NaN, NaN, 'o', 'MarkerSize', 6, 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'w');
                    F.Label   = text(ax, 0, 0, 0, '', 'FontSize', 9, 'BackgroundColor', [1 1 0.85], 'Margin', 2, 'Clipping', 'off');
                    axis(ax, 'equal', 'vis3d', 'off');
                elseif v == 5
                    F.Marker = plot3(ax, NaN, NaN, NaN, 'o', 'MarkerSize', 6, 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'w', 'Clipping', 'off');
                    F.Label  = text(ax, 0, 0, 0, '', 'FontSize', 9, 'BackgroundColor', [1 1 0.85], 'Margin', 2, 'Clipping', 'off');
                    grid(ax, 'on');
                elseif v == 2
                    F.Marker = polarplot(ax, NaN, NaN, 'o', 'MarkerSize', 6, 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'w');
                    F.Label  = text(ax, 0, 0, '', 'FontSize', 9, 'BackgroundColor', [1 1 0.85], 'Margin', 2, 'Clipping', 'off');
                    ax.ThetaZeroLocation = 'top'; ax.ThetaDir = 'clockwise';
                    ax.RLim = [0 180]; ax.RTick = 0:30:180;
                else
                    F.Marker = plot3(ax, NaN, NaN, NaN, 'o', 'MarkerSize', 6, 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'w');
                    F.Label  = text(ax, 0, 0, 0, '', 'FontSize', 9, 'BackgroundColor', [1 1 0.85], 'Margin', 2, 'Clipping', 'off');
                    daspect(ax, [1 1 1]); grid(ax, 'on');
                end
                F.Topo = topo;
            else
                switch v
                    case 2, set(F.Surface, 'XData', deg2rad(PHg), 'YData', THg, 'CData', Cd);
                    case 3, set(F.Surface, 'XData', X, 'YData', Y, 'ZData', Z, 'CData', Cd);
                    case 4, set(F.Surface, 'XData', r.*X, 'YData', r.*Y, 'ZData', r.*Z, 'CData', Cd);
                    case 5, set(F.Surface, 'XData', PHd, 'YData', THd, 'ZData', Cd, 'CData', Cd);
                end
            end
            % ---- per-view labels, camera and conventions
            switch v
                case 1
                    ax.YDir = M.ThetaDir; daspect(ax, [1 1 1]);
                    xlabel(ax, 'φ (°)'); ylabel(ax, M.ThetaLabel);
                case 2
                    ax.ThetaTick = 0:30:330;
                    tt = 0:30:330; if V.SignedPhi, tt(tt > 180) = tt(tt > 180) - 360; end
                    ax.ThetaTickLabel = compose('%d°', tt);
                    rl = 0:30:180; if V.Elevation, rl = 90 - rl; end
                    ax.RTickLabel = compose('%d°', rl);
                case 5
                    zlim(ax, lims); if numel(ticks) > 1, ax.ZTick = ticks; end
                    xlabel(ax, 'φ (°)'); ylabel(ax, M.ThetaLabel);
            end
            if any(v == [3 4 5]), app.applyCamera(v); end
            % ---- POB marker of the displayed component (display only; physics stays on total gain)
            pk = met_peak(C, G.PhiPeriodic, app.Const.PeakExcessDB);
            [pr, pc] = ind2sub(size(C), pk.index); pcd = find(M.ColIdx == pc, 1);
            switch v
                case 1,  pos = [M.PhiAxis(pcd), M.ThetaAxis(pr), 1];
                case 2,  pos = [deg2rad(P.Phi(pc)), P.Theta(pr)];
                case {3, 4}, u = [X(pr, pcd), Y(pr, pcd), Z(pr, pcd)]; pos = util_iif(v == 3, 1.02*u, (r(pr, pcd) + 0.02)*u);
                case 5,  pos = [M.PhiAxis(pcd), M.ThetaAxis(pr), Cd(pr, pcd)];
            end
            if v == 2, set(F.Marker, 'XData', pos(1), 'YData', pos(2), 'Visible', V.POB);
            else,       set(F.Marker, 'XData', pos(1), 'YData', pos(2), 'ZData', pos(3), 'Visible', V.POB); end
            postr = sprintf(' POB %s %s\n θ %s°, φ %s°', util_fmtNumber(pk.value, 2), P.Meta.UnitLabel, util_fmtNumber(P.Theta(pr)), util_fmtNumber(P.Phi(pc)));
            set(F.Label, 'Position', pos, 'Visible', V.POB, 'String', postr);
            % ---- optional cut overlay on the two spherical views
            ov = NaN(1, 3);
            if V.Overlay && any(v == [3 4])
                cut = app.currentCut();
                ov = [sind(cut.theta).*cosd(cut.phi), sind(cut.theta).*sind(cut.phi), cosd(cut.theta)];
                if v == 3, ov = 1.01*ov; else, ov = (util_polarRadius(cut.values(:, 1), lims) + 0.005).*ov; end
            end
            set(F.Overlay, 'XData', ov(:, 1), 'YData', ov(:, 2), 'ZData', ov(:, 3));
            % ---- theme, title, colourbar, interactive DataTip rows
            clim(ax, lims); colormap(ax, cmap);
            F.Colorbar.Ticks = ticks; F.Colorbar.Label.String = char(P.Meta.UnitLabel);
            if v == 1 || v == 5, ttl = sprintf('%s [%s]', util_colLabel(comp), P.Meta.UnitLabel);
            elseif v == 2,       ttl = sprintf('%s [%s]  |  r=θ, angle=φ', util_colLabel(comp), P.Meta.UnitLabel);
            else,                ttl = sprintf('%s [%s]', util_colLabel(comp), P.Meta.UnitLabel);
            end
            title(ax, ttl, 'Interpreter', 'none');
            app.setSurfaceTips(F.Surface, M.ThetaLabel, PHd, THd, Cd, util_colLabel(comp), P.Meta.UnitLabel);
            F.Key = key; app.Gfx.Full(v) = F;
        end
        function setSurfaceTips(~, h, thetaLabel, PHd, THd, Cd, compLabel, unit)
        % SETSURFACETIPS θ/φ/level rows on one chart; the lazy branch materialises DataTipTemplate first (M7 recipe).
            if ~isgraphics(h), return; end
            rows = [dataTipTextRow(thetaLabel, THd, '%.3g°'); dataTipTextRow('Phi', PHd, '%.3g°'); dataTipTextRow(compLabel, Cd, ['%.3g ' char(unit)])];
            try
                h.DataTipTemplate.DataTipRows = rows;
            catch
                try t = datatip(h, 'DataIndex', 1); delete(t); h.DataTipTemplate.DataTipRows = rows; catch, end
            end
        end
        function renderCut(app)
        % RENDERCUT Polar + rectangular cut of the trace stack with POB, HPBW and interactive DataTip rows.
            V = app.View; C = app.Gfx.Cut; E = app.Pats(app.Main); P = E.Pattern; G = E.Geometry;
            key = sprintf('%d|%s|%s|%s|%d|%d|%g|%g', app.Stamp, app.Map.Key, app.cutKey(), V.Component, V.HPBW, V.POB, app.Range.cut);
            if strcmp(C.Key, key), return; end
            [cut, labels, show] = app.currentCut();
            a = cut.angle; Y = cut.values;
            if V.CutType == "Theta" && V.Elevation, a = 90 - a; end           % full-circle θ → elevation-like angle
            signed = (V.CutType == "Phi" && V.SignedPhi) || (V.CutType == "Theta" && V.Elevation);
            if signed, a = util_wrap180(a); end
            [a, ord] = sort(a); Y = Y(ord, :);
            closed = (V.CutType == "Phi" && G.PhiPeriodic) || cut.closed;
            ap = a; Yp = Y;
            if closed, ap(end+1) = a(1) + 360; Yp(end+1, :) = Y(1, :); end
            nT = numel(labels);
            for t = 1:3
                if t <= nT
                    set(C.Polar(t), 'ThetaData', deg2rad(ap), 'RData', Yp(:, t), 'DisplayName', labels{t});
                    set(C.Rect(t),   'XData', a,             'YData', Y(:, t),  'DisplayName', labels{t});
                    app.setLineTips(C.Rect(t), cut.axis, a, labels{t}, Y(:, t), P.Meta.UnitLabel);
                    app.setLineTips(C.Polar(t), cut.axis, ap, labels{t}, Yp(:, t), P.Meta.UnitLabel);
                end
                set([C.Polar(t), C.Rect(t)], 'Visible', t <= nT && show(min(t, numel(show))));
            end
            pa = app.Single_paxCut; ra = app.Single_AxesRect;
            rlim(pa, app.Range.cut); ylim(ra, app.Range.cut);
            if closed, xl = [util_iif(signed, -180, 0), util_iif(signed, 180, 360)]; else, xl = [min(a), max(a)]; end
            if xl(2) > xl(1), xlim(ra, xl); end
            shown = find(show(1:min(nT, numel(show))));
            if isempty(shown), legend(ra, 'off'); else, legend(ra, C.Rect(shown), 'Location', 'best'); end
            fixedShown = util_cutDisplay(V.CutType, cut.fixed, V.Elevation, V.SignedPhi);
            ttl = sprintf('%s-cut at %s = %s°%s', cut.axis, cut.symbol, util_fmtNumber(fixedShown), util_iif(cut.snapped, ' (snapped)', ''));
            title(ra, ttl); title(pa, ttl);
            xlabel(ra, sprintf('%s (°)', cut.axis)); ylabel(ra, sprintf('Level (%s)', P.Meta.UnitLabel));
            set([C.MarkerRect, C.MarkerPolar, C.HPBWPatch, C.HPBWPolar(:).'], 'Visible', 'off');
            C.Text.String = ''; app.Label_HPBW.Text = '';
            if ~isempty(shown)
                t0 = shown(1); [pv, ip] = max(Y(:, t0));
                if V.POB && isfinite(pv)
                    set(C.MarkerRect,  'XData', a(ip), 'YData', pv, 'Visible', 'on');
                    set(C.MarkerPolar, 'ThetaData', deg2rad(a(ip)), 'RData', pv, 'Visible', 'on');
                    set(C.Text, 'Position', [a(ip), pv, 0], 'String', sprintf(' %s %s @ %s° (%s)', util_fmtNumber(pv, 2), ...
                        P.Meta.UnitLabel, util_fmtNumber(a(ip)), labels{t0}));
                end
                if V.HPBW
                    [bw, lo, hi] = met_hpbw(a, Y(:, t0));
                    if isfinite(bw)
                        yl = app.Range.cut;
                        set(C.HPBWPatch, 'XData', [lo hi hi lo], 'YData', [yl(1) yl(1) yl(2) yl(2)], 'Visible', 'on');
                        set(C.HPBWPolar(1), 'ThetaData', deg2rad([lo lo]), 'RData', yl, 'Visible', 'on');
                        set(C.HPBWPolar(2), 'ThetaData', deg2rad([hi hi]), 'RData', yl, 'Visible', 'on');
                        app.Label_HPBW.Text = sprintf('HPBW %s° [%s°, %s°] on %s', util_fmtNumber(bw, 2), util_fmtNumber(lo, 1), util_fmtNumber(hi, 1), labels{t0});
                    else
                        app.Label_HPBW.Text = 'HPBW n/a (no −3 dB crossing on this cut)';
                    end
                end
            end
            C.Key = key; app.Gfx.Cut = C;
        end
        function setLineTips(~, h, axisName, ang, label, vals, unit)
        % SETLINETIPS Angle + level rows on one cut line (values must match the line's data length).
            if ~isgraphics(h), return; end
            rows = [dataTipTextRow([axisName ' (°)'], ang, '%.3g°'); dataTipTextRow(label, vals, ['%.3g ' char(unit)])];
            try
                h.DataTipTemplate.DataTipRows = rows;
            catch
                try t = datatip(h, 'DataIndex', 1); delete(t); h.DataTipTemplate.DataTipRows = rows; catch, end
            end
        end

        %% ------------------------------------------------ exports (Pattern tab)
        function exportMain(app, kind)
            if app.Main == 0, return; end
            E = app.Pats(app.Main); [~, base] = fileparts(char(E.Path)); d = app.startDir();
            switch string(kind)
                case "output"
                    [f, p] = uiputfile({'*.csv', 'CSV table'}, 'Export processed pattern', fullfile(d, [base '_APAT.csv']));
                    if isequal(f, 0), return; end
                    writetable(util_longTable(E.Pattern, E.Derived), fullfile(p, f));
                case "uan"
                    [f, p] = uiputfile({'*.uan', 'UAN pattern'}, 'Export UAN', fullfile(d, [base '_APAT.uan']));
                    if isequal(f, 0), return; end
                    io_writeUAN(fullfile(p, f), E.Pattern, E.Derived);
                case "png"
                    [f, p] = uiputfile({'*.png', 'PNG image'}, 'Export view', fullfile(d, [base '_view.png']));
                    if isequal(f, 0), return; end
                    exportgraphics(app.Gfx.Full(app.View.FullView).Axes, fullfile(p, f), 'Resolution', 200);
            end
            app.setStatus(app.Single_StatusBar, sprintf('Exported %s', fullfile(p, f)), true);
        end
        function exportCut(app)
        % EXPORTCUT The current cut (canonical angles, all traces) to CSV.
            if app.Main == 0, return; end
            [cut, labels, ~] = app.currentCut();
            E = app.Pats(app.Main); [~, base] = fileparts(char(E.Path));
            vn = [{'Angle_deg'}, matlab.lang.makeValidName(strrep(labels, ' ', '_'))];
            T = array2table([cut.angle, cut.values], 'VariableNames', vn);
            [f, p] = uiputfile({'*.csv', 'CSV table'}, 'Export cut', fullfile(app.startDir(), [base '_cut.csv']));
            if isequal(f, 0), return; end
            writetable(T, fullfile(p, f));
            app.setStatus(app.Single_StatusBar, sprintf('Exported %s', fullfile(p, f)), true);
        end

        %% ============================================================ Coverage tab
        %  The tree IS the job registry: a pattern node stores k (index into Pats), a job node stores its curve
        %  {id, label, T, cov, dist, Line}. Nothing is copied from the Pattern tab and nothing is synchronised.
        %  The cone spinners are the single source of truth for the region; the orientation dropdown only writes them.
        function c = readCoverageConfig(app)
            c.Component = string(app.Cov_DropDown_Component.Value);
            c.Conical   = logical(app.Cov_Radio_Conical.Value);
            c.Orient    = double(app.Cov_DropDown_Orientation.Value);
            c.Cone      = [app.Cov_Spinner_ConeTheta.Value, app.Cov_Spinner_ConePhi.Value, app.Cov_Spinner_ConeAngle.Value];
            c.T         = cov_thresholds(app.Cov_Spinner_ThreshMin.Value, app.Cov_Spinner_ThreshMax.Value, app.Cov_Spinner_ThreshStep.Value);
            c.QueryThr  = app.Cov_Spinner_QueryThr.Value;
            c.QueryCov  = app.Cov_Spinner_QueryCov.Value;
            c.X         = [app.Cov_Spinner_Xmin.Value, app.Cov_Spinner_Xmax.Value];
            c.Y         = [app.Cov_Spinner_Ymin.Value, app.Cov_Spinner_Ymax.Value];
        end
        function updateCoverage(app, scope, arg)
            c = app.readCoverageConfig();
            switch scope
                case "covAdd"
                    [f, p] = uigetfile(app.FileFilter, 'Add a pattern to Coverage', app.startDir());
                    if isequal(f, 0), return; end
                    app.covAddPattern(fullfile(p, f));
                case "covAddMain"
                    if app.Main == 0, return; end
                    app.covAddPattern(app.Pats(app.Main).Path);
                    app.MainTabGroup.SelectedTab = app.Tab_Coverage;
                case "covLoad"
                    [f, p] = uigetfile({'*.csv;*.txt', 'Coverage results'}, 'Load coverage results', app.startDir());
                    if isequal(f, 0), return; end
                    app.covLoadResults(fullfile(p, f));
                case "covRemove"
                    for n = app.Cov_Tree.SelectedNodes(:).'
                        if ~any(n == [app.Cov_TreeNode_Patterns, app.Cov_TreeNode_Results]), app.covDeleteNode(n); end
                    end
                case "covCompute",   app.covCompute(c);
                case "covRange",     app.Range.(arg) = util_iif(string(arg) == "cov", c.Y, c.X); app.Range.Auto.(arg) = false;
                case "covAutoRange", app.Range.Auto.cov = true; app.Range.Auto.covX = true;
                case "covQueryThr",  app.covQuery(c, "thr");
                case "covQueryCov",  app.covQuery(c, "cov");
                case "covClearTips", app.deleteTips(); app.setStatus(app.Cov_StatusBar, 'Data tips cleared.', true);
                case "covExport",    app.covExport();
                case "covType",      app.covApplyType(c);
                case "covOrient",    app.covApplyOrient(c);
                case "covSelect",    if c.Conical, app.covApplyOrient(c); end
            end
            app.covRefresh();
        end
        function covAddPattern(app, path)
            k = [];
            if ~isempty(app.Pats), k = find([app.Pats.Key] == string(path), 1); end
            if isempty(k), E = app.buildEntry(path, app.readConfig(), []); app.Pats = [app.Pats, E]; k = numel(app.Pats); end
            for n = app.Cov_TreeNode_Patterns.Children(:).'
                if n.NodeData.k == k, app.Cov_Tree.SelectedNodes = n; app.covAfterSelect(); return; end
            end
            node = uitreenode(app.Cov_TreeNode_Patterns, 'Text', char(app.Pats(k).Name));
            node.NodeData = struct('kind', "pattern", 'k', k);
            expand(app.Cov_TreeNode_Patterns); app.Cov_Tree.SelectedNodes = node;
            app.covAfterSelect();
            app.setStatus(app.Cov_StatusBar, sprintf('Pattern "%s" added — set thresholds and compute coverage.', app.Pats(k).Name), false);
        end
        function covAfterSelect(app)
            if app.Cov_Radio_Conical.Value, app.covApplyOrient(app.readCoverageConfig()); end
        end
        function covApplyType(app, c)
        % COVAPPLYTYPE Cone controls are only meaningful for a conical region; Auto follows the selected pattern.
            set([app.Cov_DropDown_Orientation, app.Cov_Spinner_ConeTheta, app.Cov_Spinner_ConePhi, app.Cov_Spinner_ConeAngle], 'Enable', c.Conical);
            if c.Conical, app.covApplyOrient(c); end
        end
        function covApplyOrient(app, c)
        % COVAPPLYORIENT Orientation dropdown → cone spinners (Auto resolves the pattern's boresight axis). Compute only ever reads the spinners, so the region can never disagree with what is shown.
            idx = c.Orient; pn = app.covPatternNode();
            if idx == 0
                if isempty(pn), app.setStatus(app.Cov_StatusBar, 'Add/select a pattern to resolve the Auto orientation.', true); return; end
                idx = app.Pats(pn.NodeData.k).Derived.Boresight;
                who = sprintf('Auto → %s', app.Axes6.labels{idx});
            else
                who = app.Axes6.labels{idx};
            end
            app.setSpinner(app.Cov_Spinner_ConeTheta, app.Axes6.theta(idx), [0 180]);
            app.setSpinner(app.Cov_Spinner_ConePhi,   app.Axes6.phi(idx),   [0 360]);
            app.setStatus(app.Cov_StatusBar, sprintf('Cone orientation: %s (half-angle %g°)', who, app.Cov_Spinner_ConeAngle.Value), false);
        end
        function covRefreshPatternNodes(app)
        % COVREFRESHPATTERNNODES The Pattern-tab entry was rebuilt: its node follows, its old curves are stale.
            for n = app.Cov_TreeNode_Patterns.Children(:).'
                if n.NodeData.k ~= app.Main, continue; end
                n.Text = char(app.Pats(app.Main).Name);
                for j = app.covJobs(n).', app.covDeleteNode(j); end
            end
            app.covRefresh();
        end
        function node = covPatternNode(app)
        % COVPATTERNNODE The pattern node owning the selection (or the first pattern node).
            node = [];
            sel = app.Cov_Tree.SelectedNodes;
            if ~isempty(sel)
                n = sel(1);
                while ~isempty(n) && isa(n, 'matlab.ui.container.TreeNode')
                    if isstruct(n.NodeData) && isfield(n.NodeData, 'kind') && n.NodeData.kind == "pattern", node = n; return; end
                    n = n.Parent;
                end
            end
            if ~isempty(app.Cov_TreeNode_Patterns.Children), node = app.Cov_TreeNode_Patterns.Children(1); end
        end
        function jobs = covJobs(app, roots, checkedOnly)
        % COVJOBS Job nodes below ROOTS (default: whole tree), in id order; optionally checked ones only.
            if nargin < 2 || isempty(roots), roots = [app.Cov_TreeNode_Patterns, app.Cov_TreeNode_Results]; end
            if nargin < 3, checkedOnly = false; end
            checked = app.Cov_Tree.CheckedNodes;
            jobs = []; ids = []; stack = roots(:);
            while ~isempty(stack)
                n = stack(1); stack(1) = [];
                d = n.NodeData;
                if isstruct(d) && isfield(d, 'kind') && d.kind == "job" && (~checkedOnly || any(n == checked)), jobs = [jobs; n]; ids(end+1) = d.id; end %#ok<AGROW>
                stack = [stack; n.Children(:)]; %#ok<AGROW>
            end
            if ~isempty(jobs), [~, o] = sort(ids); jobs = jobs(o); end
        end
        function covCompute(app, c)
            pn = app.covPatternNode();
            if isempty(pn), error('APAT:Coverage', 'Add a pattern to the Coverage tree first.'); end
            E = app.Pats(pn.NodeData.k); D = E.Derived;
            if ~isfield(D.Cols, c.Component), error('APAT:Coverage', 'Component "%s" is not available in "%s".', c.Component, E.Name); end
            C = D.Cols.(c.Component);
            if c.Conical
                mask = cov_coneMask(E.Pattern, c.Cone(1), c.Cone(2), c.Cone(3));
                region = sprintf('cone θ%s° φ%s° ±%s°', util_fmtNumber(c.Cone(1)), util_fmtNumber(c.Cone(2)), util_fmtNumber(c.Cone(3)));
            else
                mask = true(size(C)); region = util_iif(E.Geometry.IsFullSphere, 'full sphere', 'measured region');
            end
            d = cov_dist(C, E.Geometry.dOmega, mask);
            app.checkCancelled();
            cov = cov_eval(d, c.T);
            app.JobCounter = app.JobCounter + 1;
            label = sprintf('%s | %s | %s | L=%s dB | step %s dB', E.Name, util_colLabel(c.Component), region, ...
                            util_fmtNumber(E.Params.L), util_fmtNumber(c.T(min(2, end)) - c.T(1)));
            app.covAddJob(pn, app.JobCounter, label, c.T, cov, d);
            app.setStatus(app.Cov_StatusBar, sprintf('R%d computed: %d thresholds, Ω_R = %s sr.', app.JobCounter, numel(c.T), util_fmtNumber(d.Omega, 3)), false);
        end
        function covAddJob(app, parent, id, label, T, cov, d)
            line = plot(app.Cov_Axes, T, cov, 'LineWidth', 1.4, 'DisplayName', sprintf('R%d', id));
            node = uitreenode(parent, 'Text', sprintf('R%d: %s', id, label));
            node.NodeData = struct('kind', "job", 'id', id, 'label', label, 'T', T(:), 'cov', cov(:), 'dist', d, 'Line', line);
            expand(parent);
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes(:); node];
        end
        function covLoadResults(app, path)
            [T, curves, names] = io_coverageCSV(path);
            [~, name] = fileparts(path);
            node = uitreenode(app.Cov_TreeNode_Results, 'Text', name);
            node.NodeData = struct('kind', "results", 'path', string(path));
            for q = 1:numel(names)
                app.JobCounter = app.JobCounter + 1;
                app.covAddJob(node, app.JobCounter, sprintf('%s | %s (file)', name, names{q}), T, curves(:, q), []);
            end
            expand(app.Cov_TreeNode_Results);
            app.setStatus(app.Cov_StatusBar, sprintf('Loaded %d curve(s) from "%s".', numel(names), name), false);
        end
        function covDeleteNode(app, n)
            for j = app.covJobs(n).', if isgraphics(j.NodeData.Line), delete(j.NodeData.Line); end, end
            delete(n);
        end
        function covQuery(app, c, mode)
        % COVQUERY Exact threshold/coverage query from the stored Ω-distribution; the tip is placed at (x, y).
            jobs = app.covJobs([], true);
            if isempty(jobs), app.setStatus(app.Cov_StatusBar, 'Check at least one curve to query.', true); return; end
            msg = {};
            for n = jobs.'
                j = n.NodeData;
                if mode == "thr", x = c.QueryThr; y = cov_at(j, x); else, y = c.QueryCov; x = cov_thrAt(j, y); end
                if ~(isfinite(x) && isfinite(y)), msg{end+1} = sprintf('R%d: n/a', j.id); continue; end %#ok<AGROW>
                app.Tips(end+1) = datatip(j.Line, x, y, 'SnapToDataVertex', 'off', 'HandleVisibility', 'off');
                msg{end+1} = sprintf('R%d: %s %% at %s dB', j.id, util_fmtNumber(y, 2), util_fmtNumber(x, 2)); %#ok<AGROW>
            end
            app.setStatus(app.Cov_StatusBar, strjoin(msg, ' | '), false);
        end
        function covExport(app)
            tbl = app.Cov_Tabel.Data;
            if isempty(tbl), app.setStatus(app.Cov_StatusBar, 'Nothing to export — check at least one curve.', true); return; end
            [f, p] = uiputfile({'*.csv', 'CSV'}, 'Export coverage results', fullfile(app.startDir(), 'APAT_coverage.csv'));
            if isequal(f, 0), return; end
            writetable(tbl, fullfile(p, f));
            app.setStatus(app.Cov_StatusBar, sprintf('Exported %s', fullfile(p, f)), true);
        end
        function covRefresh(app)
        % COVREFRESH Visibility, legend, ranges, component list and the threshold-union table — from the tree only.
            allJobs = app.covJobs(); jobs = app.covJobs([], true);
            for n = allJobs.', n.NodeData.Line.Visible = any(n == jobs); end
            pn = app.covPatternNode();
            dd = app.Cov_DropDown_Component;
            if ~isempty(pn)
                names = fieldnames(app.Pats(pn.NodeData.k).Derived.Cols).'; names = names(~startsWith(names, 'Phase_'));
                v = dd.Value; set(dd, 'Items', cellfun(@util_colLabel, names, 'UniformOutput', false), 'ItemsData', names);
                if any(strcmp(names, v)), dd.Value = v; elseif any(strcmp(names, 'E_Total_dB')), dd.Value = 'E_Total_dB'; else, dd.Value = names{1}; end
            end
            app.Cov_Button_Compute.Enable = ~isempty(pn);
            app.Cov_Button_Export.Enable = ~isempty(jobs);
            ax = app.Cov_Axes;
            if isempty(jobs)
                legend(ax, 'off'); app.Cov_Tabel.Data = table();
            else
                Ts = cell(numel(jobs), 1); lines = gobjects(numel(jobs), 1);
                for q = 1:numel(jobs), Ts{q} = jobs(q).NodeData.T; lines(q) = jobs(q).NodeData.Line; end
                Tu = unique(vertcat(Ts{:}));
                vals = zeros(numel(Tu), numel(jobs)); names = cell(1, numel(jobs));
                for q = 1:numel(jobs), vals(:, q) = cov_at(jobs(q).NodeData, Tu); names{q} = sprintf('R%d_pct', jobs(q).NodeData.id); end
                app.Cov_Tabel.Data = array2table(round([Tu, vals], 3), 'VariableNames', [{'Threshold_dB'}, names]);
                legend(ax, lines, 'Location', 'southwest');
                if app.Range.Auto.covX, app.Range.covX = [min(Tu), max(Tu)]; end
                if app.Range.Auto.cov,  app.Range.cov = [0 100]; end
            end
            if app.Range.covX(2) > app.Range.covX(1), xlim(ax, app.Range.covX); end
            if app.Range.cov(2)  > app.Range.cov(1),  ylim(ax, app.Range.cov);  end
            app.setSpinner(app.Cov_Spinner_Xmin, app.Range.covX(1), [-250 100]);
            app.setSpinner(app.Cov_Spinner_Xmax, app.Range.covX(2), [-250 100]);
            app.setSpinner(app.Cov_Spinner_Ymin, app.Range.cov(1),  [0 100]);
            app.setSpinner(app.Cov_Spinner_Ymax, app.Range.cov(2),  [0 100]);
        end

        %% ============================================================ Layout (declarative: one line per widget)
        function h = place(~, h, row, col, varargin)
        % PLACE Grid cell + name/value defaults for one already-constructed widget.
            if ~isempty(varargin), set(h, varargin{:}); end
            h.Layout.Row = row; h.Layout.Column = col;
        end
        function lab(app, parent, row, col, text)
            app.place(uilabel(parent, 'Text', text, 'HorizontalAlignment', 'right'), row, col);
        end
        function g = mkgrid(~, parent, rows, cols)
            g = uigridlayout(parent, [numel(rows), numel(cols)], 'RowHeight', rows, 'ColumnWidth', cols, 'Padding', [4 4 4 4], 'RowSpacing', 4, 'ColumnSpacing', 6);
        end
        function createComponents(app)
            cb = @(scope, varargin) @(~, ~) app.on(scope, varargin{:});
            tf = app.TextFormats;
            app.UIFigure = uifigure('Visible', 'off', 'Name', app.Const.ReleaseName, 'Position', [60 60 1500 900], 'CloseRequestFcn', @(~, ~) delete(app));
            root = uigridlayout(app.UIFigure, [1 1], 'Padding', [0 0 0 0]);
            app.MainTabGroup = uitabgroup(root, 'SelectionChangedFcn', cb("view"));
            app.Tab_Main     = uitab(app.MainTabGroup, 'Title', 'Pattern');
            app.Tab_Input    = uitab(app.MainTabGroup, 'Title', 'Input');
            app.Tab_Results  = uitab(app.MainTabGroup, 'Title', 'Results');
            app.Tab_Coverage = uitab(app.MainTabGroup, 'Title', 'Coverage');
            % ---------------- Pattern tab
            g  = app.mkgrid(app.Tab_Main, {'fit', '1x', 22}, {340, '1x'});
            fb = app.place(app.mkgrid(g, {24}, {84, '1x', 170, 150, 84, 124, 124, 84}), 1, [1 2], 'Padding', [0 0 0 0]);
            app.Single_Button_Browse   = app.place(uibutton(fb, 'Text', 'Browse…', 'ButtonPushedFcn', cb("browse")), 1, 1);
            app.Single_EditField_File  = app.place(uieditfield(fb, 'Editable', 'off', 'Placeholder', 'No pattern loaded'), 1, 2);
            app.Single_DropDown_TextFormat = app.place(uidropdown(fb, 'Items', tf{1}, 'ItemsData', tf{2}, 'Value', 'auto', ...
                                   'Visible', 'off', 'Tooltip', 'Interpretation used for generic CSV/TXT/DAT files.', ...
                                   'ValueChangedFcn', cb("fmt")), 1, 3);
            app.Single_DropDown_Freq   = app.place(uidropdown(fb, 'Items', {'—'}, 'ItemsData', {1}, 'Visible', 'off', 'ValueChangedFcn', cb("rebuild")), 1, 4);
            app.Single_Button_Process  = app.place(uibutton(fb, 'Text', 'Process', 'Tooltip', 'Rebuild with the current frequency / step choice', 'ButtonPushedFcn', cb("rebuild")), 1, 5);
            app.Single_Button_Coverage = app.place(uibutton(fb, 'Text', 'Add to Coverage', 'ButtonPushedFcn', cb("covAddMain")), 1, 6);
            app.Single_Export_Output   = app.place(uibutton(fb, 'Text', 'Export table…', 'ButtonPushedFcn', cb("export", "output")), 1, 7);
            app.Single_Export_UAN      = app.place(uibutton(fb, 'Text', 'Export UAN…', 'ButtonPushedFcn', cb("export", "uan")), 1, 8);
            lc = app.place(app.mkgrid(g, {'fit', 'fit', '1x'}, {'1x'}), 2, 1, 'Padding', [0 0 0 0]);
            app.Single_Panel_Params = app.place(uipanel(lc, 'Title', 'Link & polarisation parameters'), 1, 1);
            pg = app.mkgrid(app.Single_Panel_Params, {22, 22, 22, 22}, {'fit', '1x', 'fit', 78});
            app.lab(pg, 1, 1, 'Loss (dB)'); app.Single_Spinner_Loss   = app.place(uispinner(pg, 'Limits', [-100 100], 'Value', 0, 'Step', 0.5, 'ValueChangedFcn', cb("params")), 1, 2);
            app.lab(pg, 1, 3, 'Rx pol.'); app.Single_DropDown_RxPol = app.place(uidropdown(pg, 'Items', {'Auto', 'RHCP', 'LHCP', 'Linear'}, 'ValueChangedFcn', cb("params")), 1, 4);
            app.lab(pg, 2, 1, 'Rx wave AR (dB)'); app.Single_Spinner_Rw     = app.place(uispinner(pg, 'Limits', [0 60], 'Value', 6, 'Step', 0.5, 'ValueChangedFcn', cb("params")), 2, 2);
            app.Single_Button_Reset   = app.place(uibutton(pg, 'Text', 'Reset', 'ButtonPushedFcn', cb("reset")), 2, [3 4]);
            app.lab(pg, 3, 1, 'Tx power'); app.Single_Spinner_Pt     = app.place(uispinner(pg, 'Limits', [-1e6 1e6], 'Value', 0, 'ValueChangedFcn', cb("params")), 3, 2);
            app.Single_DropDown_Pt    = app.place(uidropdown(pg, 'Items', {'dBW', 'dBm', 'Watts'}, 'ValueChangedFcn', cb("params")), 3, [3 4]);
            app.lab(pg, 4, 1, 'Distance'); app.Single_Spinner_R      = app.place(uispinner(pg, 'Limits', [0 1e6], 'Value', 1, 'ValueChangedFcn', cb("params")), 4, 2);
            app.Single_DropDown_R     = app.place(uidropdown(pg, 'Items', {'m', 'km'}, 'ValueChangedFcn', cb("params")), 4, [3 4]);
            app.Single_Panel_plotControl = app.place(uipanel(lc, 'Title', 'Display'), 2, 1);
            cg = app.mkgrid(app.Single_Panel_plotControl, {22, 26, 22, 22, 22, 22}, {'fit', '1x', 'fit', '1x'});
            app.lab(cg, 1, 1, 'Component'); app.Single_DropDown_Component = app.place(uidropdown(cg, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', cb("component")), 1, [2 3]);
            app.Single_DropDown_step      = app.place(uidropdown(cg, 'Items', {'STEP: native'}, 'ItemsData', {'native'}, 'ValueChangedFcn', cb("rebuild")), 1, 4);
            app.lab(cg, 2, 1, 'θ axis'); app.Single_Switch_ThetaSpan   = app.place(uiswitch(cg, 'slider', 'Items', {'0° to 180°', '-90° to 90°'}, 'ValueChangedFcn', cb("span")), 2, 2);
            app.lab(cg, 2, 3, 'φ axis'); app.Single_Switch_PhiSpan     = app.place(uiswitch(cg, 'slider', 'Items', {'0° to 360°', '-180° to 180°'}, 'ValueChangedFcn', cb("span")), 2, 4);
            app.lab(cg, 3, 1, 'Colour min / max'); app.Single_Spinner_Cmin       = app.place(uispinner(cg, 'Limits', [-250 100], 'Value', -50, 'Step', 5, 'ValueChangedFcn', cb("range", "full")), 3, 2);
            app.Single_Spinner_Cmax       = app.place(uispinner(cg, 'Limits', [-250 100], 'Value', 0, 'Step', 5, 'ValueChangedFcn', cb("range", "full")), 3, 3);
            app.Single_Button_AutoRange   = app.place(uibutton(cg, 'Text', 'Auto', 'ButtonPushedFcn', cb("autorange")), 3, 4);
            app.lab(cg, 4, 1, 'Colour tick step'); app.Single_Plot_Cstep         = app.place(uispinner(cg, 'Limits', [0.1 100], 'Value', 5, 'Step', 1, 'ValueChangedFcn', cb("cstep")), 4, 2);
            app.Single_CheckBox_POB       = app.place(uicheckbox(cg, 'Text', 'POB marker', 'Value', true, 'ValueChangedFcn', cb("pob")), 4, [3 4]);
            app.lab(cg, 5, 1, '3-D view'); app.Single_DropDown_3DView    = app.place(uidropdown(cg, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                                   'ItemsData', app.Const.ViewCamera, 'Value', 'iso', 'ValueChangedFcn', cb("camera")), 5, [2 4]);
            app.Single_CheckBox_Overlay   = app.place(uicheckbox(cg, 'Text', 'Overlay the cut on the 3-D views', 'Value', false, 'ValueChangedFcn', cb("overlay")), 6, [1 4]);
            app.Single_Table_metadata     = app.place(uitable(lc, 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {140, 'auto'}, 'RowName', {}), 3, 1);
            rc = app.place(app.mkgrid(g, {'1x', '1x'}, {'1x'}), 2, 2, 'Padding', [0 0 0 0]);
            app.Single_Panel_fullPattern = app.place(uipanel(rc, 'Title', 'Full pattern'), 1, 1);
            fg = app.mkgrid(app.Single_Panel_fullPattern, {'1x'}, {'1x'});
            app.Single_TabGroup_Full = uitabgroup(fg, 'SelectionChangedFcn', cb("view"));
            titles = {'Contour', 'Circular (fisheye)', '3-D spherical', '3-D polar', '3-D surface'};
            tabs = cell(1, 5); axs = cell(1, 5);
            for v = 1:5
                tabs{v} = uitab(app.Single_TabGroup_Full, 'Title', titles{v}, 'Tag', num2str(v));
                tg = app.mkgrid(tabs{v}, {'1x'}, {'1x'});
                if v == 2, axs{v} = polaraxes(tg); else, axs{v} = uiaxes(tg); end
                app.place(axs{v}, 1, 1);
            end
            [app.Single_tabContour, app.Single_tabCircular, app.Single_tab3DSpherical, app.Single_tab3DPolar, app.Single_tab3DRect] = tabs{:};
            [app.Single_Axes_Ctr, app.Single_paxPattern, app.Single_Axes_3dSph, app.Single_Axes_3dPol, app.Single_Axes_3dRect] = axs{:};
            app.Single_paxPattern.ThetaZeroLocation = 'top'; app.Single_paxPattern.ThetaDir = 'clockwise';
            app.Single_Panel_Rect = app.place(uipanel(rc, 'Title', 'Cuts'), 2, 1);
            kg = app.mkgrid(app.Single_Panel_Rect, {'fit', '1x', 18}, {'1x', '1x'});
            hb = app.place(app.mkgrid(kg, {24}, {150, 'fit', 130, 'fit', 90, 'fit', 90, '1x', 'fit', 80, 80, 80}), 1, [1 2], 'Padding', [0 0 0 0]);
            app.Single_Switch_EHplane    = app.place(uiswitch(hb, 'slider', 'Items', {'E-plane', 'H-plane'}, 'ValueChangedFcn', cb("plane")), 1, 1);
            app.lab(hb, 1, 2, 'Cut'); app.Single_DropDown_cutType  = app.place(uidropdown(hb, 'Items', {'θ-cut (φ fixed)', 'φ-cut (θ fixed)'}, 'ItemsData', {'Theta', 'Phi'}, 'ValueChangedFcn', cb("cuttype")), 1, 3);
            app.lab(hb, 1, 4, 'at'); app.Single_DropDown_cutValue = app.place(uispinner(hb, 'Limits', [0 360], 'Value', 0, 'ValueChangedFcn', cb("cut")), 1, 5);
            app.lab(hb, 1, 6, 'Basis'); app.CutFieldBasisDropDown    = app.place(uidropdown(hb, 'Items', {'Auto', 'Linear', 'Circular'}, 'ValueChangedFcn', cb("basis")), 1, 7);
            app.Single_gridEcut = app.place(app.mkgrid(hb, {24}, {'fit', 'fit', 'fit'}), 1, 8, 'Padding', [0 0 0 0]);
            app.CheckBox_Et = app.place(uicheckbox(app.Single_gridEcut, 'Text', 'Total', 'Value', true, 'ValueChangedFcn', cb("traces")), 1, 1);
            app.CheckBox_Er = app.place(uicheckbox(app.Single_gridEcut, 'Text', 'Co-pol', 'Value', true, 'ValueChangedFcn', cb("traces")), 1, 2);
            app.CheckBox_El = app.place(uicheckbox(app.Single_gridEcut, 'Text', 'Cross-pol', 'Value', true, 'ValueChangedFcn', cb("traces")), 1, 3);
            app.Button_HPBW           = app.place(uibutton(hb, 'state', 'Text', 'HPBW', 'ValueChangedFcn', cb("hpbw")), 1, 9);
            app.Single_Spinner_CutMin = app.place(uispinner(hb, 'Limits', [-250 100], 'Value', -50, 'Step', 5, 'Tooltip', 'Cut range minimum', 'ValueChangedFcn', cb("range", "cut")), 1, 10);
            app.Single_Spinner_CutMax = app.place(uispinner(hb, 'Limits', [-250 100], 'Value', 0, 'Step', 5, 'Tooltip', 'Cut range maximum', 'ValueChangedFcn', cb("range", "cut")), 1, 11);
            app.Button_ExportCut      = app.place(uibutton(hb, 'Text', 'Cut CSV', 'Tooltip', 'Export the current cut as CSV', 'ButtonPushedFcn', cb("exportcut")), 1, 12);
            app.Single_paxCut   = app.place(polaraxes(kg), 2, 1);
            app.Single_AxesRect = app.place(uiaxes(kg), 2, 2);
            app.Label_HPBW      = app.place(uilabel(kg, 'Text', '', 'FontColor', [0.6 0.35 0]), 3, [1 2]);
            app.Single_StatusBar = app.place(uilabel(g, 'Text', '', 'Tag', 'Main', 'FontColor', [0.2 0.2 0.2]), 3, [1 2]);
            % ---------------- Input tab
            ig = app.mkgrid(app.Tab_Input, {'fit', '1x'}, {'1x'});
            app.Input_Label = app.place(uilabel(ig, 'Text', 'The rows of the source file, as parsed, appear here after a pattern is loaded.'), 1, 1);
            app.Input_Table = app.place(uitable(ig), 2, 1);
            % ---------------- Results tab
            rg2 = app.mkgrid(app.Tab_Results, {'fit', '1x'}, {'fit', '1x'});
            app.Single_DropDown_output = app.place(uidropdown(rg2, 'Items', {'--- column filter ---'}, 'ItemsData', {0}, 'Value', 0, ...
                                     'Visible', 'off', 'Tooltip', 'Toggle columns of the processed table.', 'ValueChangedFcn', cb("filter")), 1, 1);
            app.Single_Table_DataOut = app.place(uitable(rg2, 'RowName', {}), 2, [1 2]);
            % ---------------- Coverage tab
            vg = app.mkgrid(app.Tab_Coverage, {'1x', 22}, {360, '1x'});
            lg = app.place(app.mkgrid(vg, {'1x', 'fit', 'fit'}, {'1x'}), 1, 1, 'Padding', [0 0 0 0]);
            app.Cov_Tree = app.place(uitree(lg, 'checkbox', 'CheckedNodesChangedFcn', cb("covCheck"), 'SelectionChangedFcn', cb("covSelect")), 1, 1);
            app.Cov_TreeNode_Patterns = uitreenode(app.Cov_Tree, 'Text', 'Patterns');
            app.Cov_TreeNode_Results  = uitreenode(app.Cov_Tree, 'Text', 'Results files');
            bg = app.place(app.mkgrid(lg, {24}, {'1x', '1x', '1x'}), 2, 1, 'Padding', [0 0 0 0]);
            app.Cov_Button_AddPattern  = app.place(uibutton(bg, 'Text', 'Add pattern…', 'ButtonPushedFcn', cb("covAdd")), 1, 1);
            app.Cov_Button_LoadResults = app.place(uibutton(bg, 'Text', 'Load results…', 'ButtonPushedFcn', cb("covLoad")), 1, 2);
            app.Cov_Button_Remove      = app.place(uibutton(bg, 'Text', 'Remove', 'ButtonPushedFcn', cb("covRemove")), 1, 3);
            sp = app.place(uipanel(lg, 'Title', 'Coverage settings'), 3, 1);
            sg = app.mkgrid(sp, {22, 46, 22, 22, 22, 26}, {'fit', '1x', '1x', '1x'});
            app.lab(sg, 1, 1, 'Component'); app.Cov_DropDown_Component  = app.place(uidropdown(sg, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}), 1, [2 4]);
            app.Cov_ButtonGroup_CovType = app.place(uibuttongroup(sg, 'BorderType', 'none', 'SelectionChangedFcn', cb("covType")), 2, [1 4]);
            app.Cov_Radio_Spherical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Whole pattern (sphere / measured region)', 'Position', [4 24 330 20], 'Value', true);
            app.Cov_Radio_Conical   = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Cone around (θ, φ) with half-angle ±', 'Position', [4 2 330 20]);
            app.lab(sg, 3, 1, 'Orientation'); app.Cov_DropDown_Orientation = app.place(uidropdown(sg, 'Items', [{'Auto'}, app.Axes6.labels], 'ItemsData', 0:6, ...
                                         'Value', 0, 'Enable', 'off', 'Tooltip', 'Auto follows the selected pattern''s boresight axis.', ...
                                         'ValueChangedFcn', cb("covOrient")), 3, [2 4]);
            app.lab(sg, 4, 1, 'Cone θ₀ / φ₀ / α'); app.Cov_Spinner_ConeTheta = app.place(uispinner(sg, 'Limits', [0 180], 'Value', 0, 'Enable', 'off'), 4, 2);
            app.Cov_Spinner_ConePhi   = app.place(uispinner(sg, 'Limits', [0 360], 'Value', 0, 'Enable', 'off'), 4, 3);
            app.Cov_Spinner_ConeAngle = app.place(uispinner(sg, 'Limits', [0 180], 'Value', 60, 'Enable', 'off'), 4, 4);
            app.lab(sg, 5, 1, 'Thresholds min / max / step'); app.Cov_Spinner_ThreshMin  = app.place(uispinner(sg, 'Limits', [-250 100], 'Value', -40), 5, 2);
            app.Cov_Spinner_ThreshMax  = app.place(uispinner(sg, 'Limits', [-250 100], 'Value', 10), 5, 3);
            app.Cov_Spinner_ThreshStep = app.place(uispinner(sg, 'Limits', [1e-3 100], 'Value', 0.5), 5, 4);
            app.Cov_Button_Compute = app.place(uibutton(sg, 'Text', 'Compute coverage', 'Enable', 'off', 'ButtonPushedFcn', cb("covCompute")), 6, [1 4]);
            rr = app.place(app.mkgrid(vg, {'1x', 'fit', 'fit', 200}, {'1x'}), 1, 2, 'Padding', [0 0 0 0]);
            app.Cov_Axes = app.place(uiaxes(rr), 1, 1);
            qg = app.place(app.mkgrid(rr, {24}, {'fit', 70, 90, 'fit', 70, 90, '1x', 80, 90}), 2, 1, 'Padding', [0 0 0 0]);
            app.lab(qg, 1, 1, 'Query at threshold (dB)'); app.Cov_Spinner_QueryThr = app.place(uispinner(qg, 'Limits', [-250 100], 'Value', 0), 1, 2);
            app.Cov_Button_QueryThr  = app.place(uibutton(qg, 'Text', 'Coverage?', 'ButtonPushedFcn', cb("covQueryThr")), 1, 3);
            app.lab(qg, 1, 4, 'Query at coverage (%)'); app.Cov_Spinner_QueryCov = app.place(uispinner(qg, 'Limits', [0 100], 'Value', 90), 1, 5);
            app.Cov_Button_QueryCov  = app.place(uibutton(qg, 'Text', 'Threshold?', 'ButtonPushedFcn', cb("covQueryCov")), 1, 6);
            app.Cov_Button_ClearTips = app.place(uibutton(qg, 'Text', 'Clear tips', 'ButtonPushedFcn', cb("covClearTips")), 1, 8);
            app.Cov_Button_Export    = app.place(uibutton(qg, 'Text', 'Export…', 'Enable', 'off', 'ButtonPushedFcn', cb("covExport")), 1, 9);
            xg = app.place(app.mkgrid(rr, {24}, {'fit', 70, 70, 'fit', 70, 70, 60, '1x'}), 3, 1, 'Padding', [0 0 0 0]);
            app.lab(xg, 1, 1, 'Threshold axis'); app.Cov_Spinner_Xmin = app.place(uispinner(xg, 'Limits', [-250 100], 'Value', -40, 'ValueChangedFcn', cb("covRange", "covX")), 1, 2);
            app.Cov_Spinner_Xmax = app.place(uispinner(xg, 'Limits', [-250 100], 'Value', 10, 'ValueChangedFcn', cb("covRange", "covX")), 1, 3);
            app.lab(xg, 1, 4, 'Coverage axis'); app.Cov_Spinner_Ymin = app.place(uispinner(xg, 'Limits', [0 100], 'Value', 0, 'ValueChangedFcn', cb("covRange", "cov")), 1, 5);
            app.Cov_Spinner_Ymax = app.place(uispinner(xg, 'Limits', [0 100], 'Value', 100, 'ValueChangedFcn', cb("covRange", "cov")), 1, 6);
            app.Cov_Button_AutoRange = app.place(uibutton(xg, 'Text', 'Auto', 'ButtonPushedFcn', cb("covAutoRange")), 1, 7);
            app.Cov_Tabel     = app.place(uitable(rr, 'RowName', {}), 4, 1);
            app.Cov_StatusBar = app.place(uilabel(vg, 'Text', '', 'Tag', 'Cov', 'FontColor', [0.2 0.2 0.2]), 2, [1 2]);
        end
    end

    %% ============================================================ Self-test (headless: no figure, no widgets)
    methods (Static)
        function rows = selfTest()
            %SELFTEST Re-derive every kernel against closed-form results:  APAT_v3_M8.selfTest. Rows = {name, got, want, pass}; exceptions fail.
            T = strings(0, 4); K = APAT_v3_M8.Const; A6 = APAT_v3_M8.Axes6;
            TH = 0:5:180; PH = 0:5:355; [p, t] = ndgrid(TH, PH);
            P = struct('Theta', TH(:), 'Phi', PH(:), 'dTheta', 5, 'dPhi', 5, 'IsGainOnly', true, 'G', struct('dummy', zeros(37, 72)), ...
                       'Revision', 1, 'NativeStep', [5 5], 'Freq', NaN, 'Meta', struct('Notes', strings(1, 0), 'Unit', "dB"));
            G = geo_build(P);
            % Gaussian beam: E = 10.^(−3·(θ/10)²/20) field ⇒ 0 dB at the pole, −3 dB at θ = 10°.
            E = 10.^(-3 .* (p ./ 10).^2 ./ 20);
            [mv, mi] = max(E(:)); [r0, ~] = ind2sub(size(E), mi);
            T = stRow(T, 'Gaussian peak', @() {sprintf('%.1f dB @ θ=%d°', 20*log10(mv), TH(r0)), 20*log10(mv) == 0 && TH(r0) == 0}, '0.0 dB @ θ=0°');
            % −3 dB crossings of a full circle across the φ wrap: exactly ±10° ⇒ HPBW 20°.
            g = -3 .* ((mod(PH + 180, 360) - 180) ./ 10).^2;
            [bw, lo, hi] = met_hpbw(PH(:), g(:));
            T = stRow(T, 'HPBW wrap', @() {sprintf('%.1f / %.1f / %.1f', bw, lo, hi), abs(bw - 20) < 1e-9 && abs(lo + 10) < 1e-9 && abs(hi - 10) < 1e-9}, '20.0 / -10.0 / 10.0');
            bw0 = met_hpbw(TH(:), ones(37, 1));
            T = stRow(T, 'HPBW flat cut', @() {sprintf('%g', bw0), isnan(bw0)}, 'NaN');
            % Polarisation identities: E_R=(Eθ+jEφ)/√2; pure LHCP input ⇒ E_R = 0, E_L = √2.
            [Er, El] = pol_circular(1, 1i, 1); [ErL, ElL] = pol_circular(1, 1i, 2);
            T = stRow(T, 'pol_circular', @() {sprintf('%.3f / %.3f', abs(Er), abs(El)), abs(Er) < 1e-12 && abs(El - sqrt(2)) < 1e-12}, '0.000 / 1.414');
            [arP, linP] = pol_signedAR(ErL, ElL);
            T = stRow(T, 'signedAR pure LHCP', @() {sprintf('%.0f / %d', arP, linP), abs(arP) < 1e-12 && ~linP}, '0 / 0');
            [arL, linL] = pol_signedAR(1, 1);
            T = stRow(T, 'signedAR linear', @() {sprintf('%.0f / %d', arL, linL), arL == K.LinearAR_dB && linL}, '-100 / 1');
            % PLF: matched near-circular pair ≈ 0 dB; opposite pure senses deep down; NaN in, NaN out.
            plfM = pol_plf(0.4, false, "RHCP", 0.1, 'E_RCP', 1);
            T = stRow(T, 'PLF match', @() {sprintf('%.3f', plfM), abs(plfM) < 0.01}, '|PLF| < 0.01 dB');
            plfX = pol_plf(0, false, "LHCP", 0.1, 'E_RCP', 1);
            T = stRow(T, 'PLF mismatch', @() {sprintf('%.0f', plfX), plfX < -40}, '< -40 dB');
            plfN = pol_plf(NaN, false, "RHCP", 6, 'E_RCP', NaN);
            T = stRow(T, 'PLF NaN', @() {sprintf('%g', plfN), isnan(plfN)}, 'NaN');
            % Peak policy: NaN ignored, an isolated +30 dB spike excluded, zero plateau picked.
            Cp = zeros(7, 12); Cp(2, 3) = NaN; Cp(4, 5) = 30;
            Kp = met_peak(Cp, true, K.PeakExcessDB);
            T = stRow(T, 'met_peak spike', @() {sprintf('raw %g | val %g | n %d | adj %d', Kp.rawValue, Kp.value, Kp.spikeCount, Kp.wasAdjusted), Kp.rawValue == 30 && Kp.value == 0 && Kp.spikeCount == 1 && Kp.wasAdjusted}, 'raw 30 | val 0 | n 1 | adj 1');
            % Boresight of a +Z beam (Axes6 index 5) and its E/H planes: θ-cut φ=0 and θ-cut φ=90.
            Tb = 10 .* log10(max(cosd(p).^9, realmin));
            Kt = met_peak(Tb, true, K.PeakExcessDB);
            ax = met_orientation(Tb, P, G, Kt, A6);
            T = stRow(T, 'Boresight +Z', @() {sprintf('%d', ax), ax == 5}, '5');
            Pl = met_planes(ax, A6);
            T = stRow(T, 'E/H planes', @() {sprintf('%s:%g | %s:%g', Pl.E.CutType, Pl.E.Fixed, Pl.H.CutType, Pl.H.Fixed), Pl.E.CutType == "Theta" && Pl.E.Fixed == 0 && Pl.H.CutType == "Theta" && Pl.H.Fixed == 90}, 'Theta:0 | Theta:90');
            % Exact integer decimation: 1° → 3° keeps 61 θ rows and every third φ column bit-for-bit.
            Pr = struct('Theta', (0:1:180).', 'Phi', (0:1:359).', 'dTheta', 1, 'dPhi', 1, 'IsGainOnly', true, 'G', struct('gain', reshape(1:181*360, 181, 360)), ...
                        'Revision', 1, 'NativeStep', [1 1], 'Meta', struct('Notes', strings(1, 0), 'Unit', "dB"));
            Q = pat_resample(Pr, 3);
            T = stRow(T, 'resample 1°→3°', @() {sprintf('%d × %d', numel(Q.Theta), numel(Q.Phi)), numel(Q.Theta) == 61 && numel(Q.Phi) == 120 && isequal(Q.G.gain, Pr.G.gain(1:3:end, 1:3:end))}, '61 × 120, exact');
            % Display conventions: signed φ starts at −180, plain φ at 0, both append the closing column.
            M1 = geo_displayMap(P, G, struct('SignedPhi', true,  'Elevation', false));
            M0 = geo_displayMap(P, G, struct('SignedPhi', false, 'Elevation', false));
            T = stRow(T, 'displayMap signed', @() {sprintf('%d | %g | %d', numel(M1.PhiAxis), M1.PhiAxis(1), M1.ColIdx(end)), numel(M1.PhiAxis) == 73 && M1.PhiAxis(1) == -180 && M1.ColIdx(end) == 37}, '73 | -180 | 37');
            T = stRow(T, 'displayMap plain', @() {sprintf('%g | %g | %d', M0.PhiAxis(1), M0.PhiAxis(end), M0.ColIdx(end)), M0.PhiAxis(1) == 0 && M0.PhiAxis(end) == 360 && M0.ColIdx(end) == 1}, '0 | 360 | 1');
            % Cuts: both great circles come back as one closed 0:5:360 circle (73 points).
            S = cat(3, p, t);
            s1 = geo_cut(P, S, "Theta", 0);
            T = stRow(T, 'geo_cut θ=0', @() {sprintf('%d | %g | %g', numel(s1.angle), s1.angle(1), s1.angle(end)), numel(s1.angle) == 73 && s1.angle(1) == 0 && s1.angle(end) == 360 && s1.fixed == 0}, '73 | 0 | 360');
            s2 = geo_cut(P, S, "Phi", 90);
            T = stRow(T, 'geo_cut fixed θ=90', @() {sprintf('%d | %g | %g', numel(s2.angle), s2.angle(1), s2.angle(end)), numel(s2.angle) == 73 && s2.angle(1) == 0 && s2.angle(end) == 360 && s2.fixed == 90}, '73 | 0 | 360');
            % Geometry and coverage: cos γ poles, threshold vector, hand-counted region, query round-trip.
            cg = util_cosGamma(P, 90, 0);
            T = stRow(T, 'cos γ poles', @() {sprintf('%.3f / %.3f', cg(19, 1), cg(19, 37)), cg(19, 1) == 1 && abs(cg(19, 37) + 1) < 1e-12}, '1.000 / -1.000');
            Tv = cov_thresholds(-40, 10, 0.5);
            T = stRow(T, 'threshold vector', @() {sprintf('%d | %g | %g', numel(Tv), Tv(1), Tv(end)), numel(Tv) == 101 && Tv(1) == -40 && Tv(end) == 10}, '101 | -40 | 10');
            % Region {dist < 15°} ∩ {θ ≥ 40°}: 5 φ columns always inside + 2 columns losing θ=90° ⇒ 5·29 + 2·28 = 201.
            dist = acosd(cg); mask = dist < 15 & p >= 40;
            d = cov_dist(-dist, ones(size(dist)), mask);
            c15 = cov_eval(d, -15);
            T = stRow(T, 'coverage count', @() {sprintf('%g | %.0f', d.Omega, c15), d.Omega == 201 && abs(c15 - 100) < 1e-9}, '201 | 100');
            j = struct('T', Tv, 'cov', cov_eval(d, Tv), 'dist', d, 'id', 1);
            xq = cov_thrAt(j, 50); yq = cov_at(j, xq); nTie = nnz(dist == -xq);
            T = stRow(T, 'coverage query', @() {sprintf('%.2f → %.2f', xq, yq), isfinite(xq) && abs(yq - 50) <= (nTie + 1) * 100/201}, 'inverse within (ties+1)·100/201 %');
            rows = T;
            if any(T{:, 4} == "false")
                for i = find(T{:, 4} == "false").', fprintf('  FAIL  %-22s got %-34s want %s\n', T{i, 1}, T{i, 2}, T{i, 3}); end
                error('APAT:SelfTest', '%d self-test row(s) failed.', nnz(T{:, 4} == "false"));
            end
            fprintf('APAT_v3_M8.selfTest: %d/%d passed.\n', size(T, 1), size(T, 1));
        end
    end
end

%% ================= FILE-SCOPE FUNCTIONS =================  app-free, widget-free; loaded with the class.
%  Canonical data path: io_read → pat_build (+pat_resample) → geo_build → pat_derive.
%  Every function below reads plain structs only; conventions arrive as explicit arguments.
function P = pat_build(S, f, K)
% PAT_BUILD Grid-native pattern from Source block f: θ ascending in [0,180], φ ascending in [0,360), uniform steps asserted once, matrices nθ×nφ filled by index arithmetic. Angles snap to K.AngleDecimals decimals; field values are never rounded.
T = S.Blocks{f}; th = T.Theta; ph = T.Phi; V = T{:, 3:end}; names = string(T.Properties.VariableNames(3:end)).';
notes = strings(1, 0);
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90
        th = 90 - th; notes(end+1) = "θ ∈ [−90°, 90°] read as elevation and folded to polar θ = 90° − el.";
    else
        neg = th < 0; th(neg) = -th(neg); ph(neg) = ph(neg) + 180; notes(end+1) = "Negative θ samples folded onto φ + 180°.";
    end
end
th = mod(th, 360); over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;
th = round(th, K.AngleDecimals); ph = round(mod(ph, 360), K.AngleDecimals); ph(ph >= 360) = 0;
[~, u] = unique([ph th], 'rows', 'first'); th = th(u); ph = ph(u); V = V(u, :);   % a φ = 360 twin of φ = 0 collapses here
P.Theta = unique(th); P.Phi = unique(ph);
P.dTheta = util_axisStep(P.Theta, 'θ', K); P.dPhi = util_axisStep(P.Phi, 'φ', K);
n = numel(P.Theta); m = numel(P.Phi);
if n*m ~= numel(th), error('APAT:NonUniformGrid', '%d samples do not fill the %d×%d θ/φ grid: APAT requires a complete rectangular grid.', numel(th), n, m); end
if isnan(P.dTheta), P.dTheta = 180; end
if isnan(P.dPhi),   P.dPhi = 360;   end
idx = sub2ind([n m], round((th - P.Theta(1))/P.dTheta) + 1, round((ph - P.Phi(1))/P.dPhi) + 1);
P.IsGainOnly = S.Meta.IsGainOnly; P.Freq = S.Freqs(min(f, end)); P.Revision = 1;
P.Meta = S.Meta; P.Meta.Notes = [S.Meta.Notes notes];
P.NativeStep = [P.dTheta P.dPhi];
P.Eth = []; P.Eph = []; P.G = struct();
if P.IsGainOnly
    for k = 1:numel(names), g = nan(n, m); g(idx) = V(:, k); P.G.(names(k)) = g; end
else
    P.Eth = complex(nan(n, m)); P.Eph = complex(nan(n, m));
    P.Eth(idx) = complex(V(:, 1), V(:, 2)); P.Eph(idx) = complex(V(:, 3), V(:, 4));
end
end
function step = util_axisStep(ax, name, K)
% UTIL_AXISSTEP One step per axis or APAT:NonUniformGrid naming the axis and its gap range.
if numel(ax) < 2, step = NaN; return; end
d = diff(ax); step = median(d);
if any(abs(d - step) > K.UniformTolDeg)
    error('APAT:NonUniformGrid', '%s axis is not uniform: steps range %.6g°..%.6g° (APAT requires uniform grids).', name, min(d), max(d));
end
end
function P = pat_resample(P, step)
% PAT_RESAMPLE Exact index decimation when step/Δθ and step/Δφ are integers (values bit-for-bit); otherwise bilinear on the φ-closed grid: E-field as power + unit phasor, gain-kind as linear power, everything else linear. Target axes never leave the source domain.
kt = step/P.dTheta; kp = step/P.dPhi;
periodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
decimate = abs(kt - round(kt)) < 1e-9 && abs(kp - round(kp)) < 1e-9;
if decimate
    it = 1:round(kt):numel(P.Theta); ip = 1:round(kp):numel(P.Phi);
    t = P.Theta(it); p = P.Phi(ip); how = "decimated";
    pick = @(X) X(it, ip);
else
    t = (P.Theta(1):step:P.Theta(end) + 1e-9).'; last = P.Phi(end);
    if periodic, last = P.Phi(1) + 360 - step; end
    p = (P.Phi(1):step:last + 1e-9).'; sp = P.Phi(:).'; st = P.Theta(:);
    if periodic, sp(end+1) = sp(1) + 360; seam = @(X) [X, X(:, 1)]; else, seam = @(X) X; end
    pick = @(X) interp2(sp, st, seam(X), p.', t, 'linear'); how = "bilinear";
end
if P.IsGainOnly
    for nm = string(fieldnames(P.G)).'
        if decimate
            P.G.(nm) = pick(P.G.(nm));
        elseif util_colKind(nm) == "gain"
            P.G.(nm) = 10*log10(max(pick(10.^(P.G.(nm)/10)), realmin));
        else
            P.G.(nm) = pick(P.G.(nm));
        end
    end
elseif decimate
    P.Eth = pick(P.Eth); P.Eph = pick(P.Eph);
else
    P.Eth = fieldInterp(P.Eth, pick); P.Eph = fieldInterp(P.Eph, pick);
end
P.Theta = t(:); P.Phi = p(:); P.dTheta = step; P.dPhi = step; P.Revision = P.Revision + 1;
P.Meta.Notes(end+1) = sprintf('Resampled to %g° (%s).', step, how);
end
function E = fieldInterp(E, f)
% FIELDINTERP |E|² and the unit phasor E/|E| are interpolated separately and recombined as sqrt(P)·u/|u|: magnitudes stay exact under a phase slope and phases average circularly.
u = E ./ max(abs(E), realmin); pw = f(abs(E).^2); u = complex(f(real(u)), f(imag(u)));
E = sqrt(max(pw, 0)) .* u ./ max(abs(u), realmin);
end
function G = geo_build(P)
% GEO_BUILD Separable cell solid angles on the uniform grid: wθ(i) = cos(θᵢ−Δθ/2) − cos(θᵢ+Δθ/2) with edges clipped to [0°,180°], ΔΩ(i,j) = wθ(i)·Δφ. On a full sphere ΣΔΩ = 4π exactly.
lo = max(P.Theta(:) - P.dTheta/2, 0); hi = min(P.Theta(:) + P.dTheta/2, 180);
G.wTheta = cosd(lo) - cosd(hi); G.dPhi = deg2rad(P.dPhi);
G.PhiPeriodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
G.IsFullSphere = G.PhiPeriodic && lo(1) == 0 && hi(end) == 180;
G.dOmega = G.wTheta * G.dPhi * ones(1, numel(P.Phi));
G.Omega = sum(G.dOmega, 'all');
end
function M = geo_displayMap(P, G, V)
% GEO_DISPLAYMAP Column permutation and axis relabelling for the display convention: signed φ starts at −180°, elevation relabels θ, and the periodic grid gains one closing column. No data is copied or changed — indices and labels only.
n = numel(P.Phi); j0 = find(P.Phi >= 180, 1); perm = 1:n;
if V.SignedPhi && ~isempty(j0), perm = [j0:n, 1:j0 - 1]; end
M.ColIdx = perm; M.PhiAxis = P.Phi(perm).';
if V.SignedPhi, M.PhiAxis(M.PhiAxis >= 180) = M.PhiAxis(M.PhiAxis >= 180) - 360; end
if G.PhiPeriodic, M.ColIdx(end+1) = perm(1); M.PhiAxis(end+1) = M.PhiAxis(1) + 360; end
if V.Elevation
    M.ThetaAxis = 90 - P.Theta(:); M.ThetaDir = 'normal'; M.ThetaLabel = "Elevation";
else
    M.ThetaAxis = P.Theta(:); M.ThetaDir = 'reverse'; M.ThetaLabel = "Theta";
end
M.Key = sprintf('%d|%d', V.SignedPhi, V.Elevation);
end
function S = geo_cut(P, C, type, value)
% GEO_CUT One great-circle cut through the nθ×nφ value stack C. Phi cut: fixed θ row, angle = φ (closing point appended when periodic). Theta cut: fixed φ column (θ ascending) then the opposite column φ+180° (θ descending), angle = θ then 360−θ, closed at 360° when the pole is in the grid.
n = numel(P.Theta); m = numel(P.Phi); periodic = abs(m*P.dPhi - 360) < 1e-6;
S.type = type; S.value = value;
if type == "Phi"
    [d, i] = min(abs(P.Theta - value)); S.fixed = P.Theta(i); S.symbol = 'θ'; S.axis = 'θ';
    cols = 1:m; rows = i*ones(1, m); S.angle = P.Phi(:);
    S.closed = periodic;
    if periodic, cols(end+1) = 1; rows(end+1) = i; S.angle(end+1) = P.Phi(1) + 360; end
else
    [d, j] = min(abs(mod(P.Phi - value + 180, 360) - 180)); S.fixed = P.Phi(j); S.symbol = 'φ'; S.axis = 'φ';
    [dj, jo] = min(abs(mod(P.Phi - S.fixed, 360) - 180));
    rows = 1:n; cols = j*ones(1, n); S.angle = P.Theta(:); S.closed = false;
    if dj <= P.dPhi/2 + 1e-9                                   % opposite half-plane exists on this grid
        back = flip(find(P.Theta > 1e-9 & P.Theta < 180 - 1e-9)).';
        rows = [rows, back]; cols = [cols, jo*ones(size(back))]; S.angle = [S.angle; 360 - P.Theta(back)];
        if P.Theta(1) == 0, rows(end+1) = 1; cols(end+1) = j; S.angle(end+1) = 360; S.closed = true; end
    end
end
S.idx = sub2ind([n m], rows(:), cols(:));
S.theta = P.Theta(rows(:)); S.phi = P.Phi(cols(:)); S.snapped = d > 1e-9;
tiers = (0:size(C, 3) - 1) * n * m;                                 % one linear-index block per trace
S.values = reshape(C(S.idx(:) + tiers), [], size(C, 3));
end
function D = pat_derive(P, G, prm, K, A6)
% PAT_DERIVE Every column and every base fact of a pattern at the given parameters. Called again whenever the file, the parameters or the frequency block change; nothing downstream adds, scales or memoises a value.
if P.IsGainOnly
    C = P.G; names = string(fieldnames(C)).';
    for nm = names
        if util_colKind(nm) == "gain", C.(nm) = C.(nm) + prm.L; end     % loss touches gain-kind columns only
    end
    tot = names(find(arrayfun(@(nm) util_colKind(nm) == "gain", names), 1));
    if isempty(tot), tot = names(1); end
    D.Pol = struct('Label', "n/a", 'Basis', "Linear", 'Pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
else
    s = 10^(prm.L/20); Eth = P.Eth*s; Eph = P.Eph*s;                    % loss as an incident-field scale
    Er = pol_circular(Eth, Eph, 1); El = pol_circular(Eth, Eph, 2);
    C.E_Total_dB = 10*log10(max(abs(Eth).^2 + abs(Eph).^2, eps));
    C.E_TH_dB = 20*log10(max(abs(Eth), eps)); C.E_PH_dB = 20*log10(max(abs(Eph), eps));
    C.E_RCP_dB = 20*log10(max(abs(Er), eps)); C.E_LCP_dB = 20*log10(max(abs(El), eps));
    [C.AR_dB, isLin, sense] = pol_signedAR(Er, El);
    K0 = met_peak(C.E_Total_dB, G.PhiPeriodic, K.PeakExcessDB);
    [r0, c0] = ind2sub(size(C.E_Total_dB), K0.index);
    D.Pol = pol_classify(Eth, Eph, Er, El, G.dOmega, util_cosGamma(P, P.Theta(r0), P.Phi(c0)) >= cosd(K.ConeHalfAngleDeg));  % main beam = 45° cone
    C.PLF_dB = pol_plf(C.AR_dB, isLin, prm.RxMode, prm.RxAR_dB, D.Pol.Pairs.Circular(1), sense);
    C.Gain_PolCorrected_dB = C.E_Total_dB + C.PLF_dB;
    C.E_TH_Phase = rad2deg(angle(Eth)); C.E_PH_Phase = rad2deg(angle(Eph));
    C.E_RCP_Phase = rad2deg(angle(Er)); C.E_LCP_Phase = rad2deg(angle(El));
    C.EIRP_dBW = prm.Pt_dBW + C.E_Total_dB;
    C.PFD_Wm2 = 10.^(C.EIRP_dBW/10) ./ (4*pi*prm.R_m^2);
    C.E_RMS_Vm = sqrt(30*10.^(C.EIRP_dBW/10)) ./ prm.R_m;
    tot = "E_Total_dB";
end
D.Cols = C; D.GainName = char(tot);
Tt = C.(char(tot));
D.Peak = met_peak(Tt, G.PhiPeriodic, K.PeakExcessDB);
D.Boresight = met_orientation(Tt, P, G, D.Peak, A6);
D.Planes = met_planes(D.Boresight, A6);
D.Metrics = met_metrics(Tt, P, G, D.Peak, D.Planes, C, P.Meta.Unit == "dBi");
end

%% ---------------- metrics ----------------
function K = met_peak(C, periodic, excessDB)
% MET_PEAK Effective peak = highest sample that is not an isolated spike. spike(i,j) ⇔ C(i,j) − max(4 grid neighbours) > excessDB; φ wraps when periodic; NaNs are ignored.
[n, m] = size(C); nb = -inf(n, m);
if n > 1, nb(2:n, :) = max(nb(2:n, :), C(1:n - 1, :)); nb(1:n - 1, :) = max(nb(1:n - 1, :), C(2:n, :)); end
if periodic, L = circshift(C, 1, 2); R = circshift(C, -1, 2);
else,        L = [-inf(n, 1), C(:, 1:m - 1)]; R = [C(:, 2:m), -inf(n, 1)];
end
nb = max(nb, max(L, R));
K.spike = isfinite(C) & (C - nb > excessDB);
[K.rawValue, K.rawIndex] = max(C(:), [], 'omitnan');
cand = C; cand(K.spike) = -Inf;
[K.value, K.index] = max(cand(:), [], 'omitnan');
K.wasAdjusted = K.spike(K.rawIndex); K.spikeCount = nnz(K.spike);
end
function cg = util_cosGamma(P, thc, phc)
% UTIL_COSGAMMA Cosine of the great-circle distance from (θc, φc) to every grid direction.
cg = cosd(P.Theta(:))*cosd(thc) + sind(P.Theta(:))*sind(thc) .* cosd(P.Phi(:).' - phc);
end
function axisIndex = met_orientation(T, P, G, K, A6)
% MET_ORIENTATION Principal axis whose 45° cone holds the most 10^{(G−Gp)/10}·ΔΩ energy (spikes and non-finite samples excluded).
w = 10.^((T - K.value)/10) .* G.dOmega; w(~isfinite(w) | K.spike) = 0;
e = zeros(1, numel(A6.theta));
for i = 1:numel(A6.theta), e(i) = sum(w(util_cosGamma(P, A6.theta(i), A6.phi(i)) >= cosd(45))); end
[~, axisIndex] = max(e);
end
function S = met_planes(axisIndex, A6)
% MET_PLANES E-plane: θ-cut through the axis' φ. H-plane: the orthogonal cut — a φ-cut at θ = 90° for a transverse axis (±X, ±Y), a θ-cut at φ = 90° for ±Z.
S.E = struct('CutType', "Theta", 'Fixed', A6.phi(axisIndex));
if A6.theta(axisIndex) == 90, S.H = struct('CutType', "Phi", 'Fixed', 90);
else,                          S.H = struct('CutType', "Theta", 'Fixed', 90); end
end
function X = met_metrics(T, P, G, K, Pl, C, isAbsolute)
% MET_METRICS Directivity over the sampled solid angle with spikes removed from numerator and Ω; efficiency and front-to-back only on a full sphere; HPBW on the E/H cuts; AR at the peak.
keep = isfinite(T) & ~K.spike; lin = 10.^(T/10);
I = sum(lin(keep) .* G.dOmega(keep)); X.OmegaUsed = sum(G.dOmega(keep));
X.PeakDirectivity_dB = 10*log10(max(X.OmegaUsed * 10^(K.value/10) / max(I, realmin), realmin));
X.Efficiency_pct = NaN;
if G.IsFullSphere && isAbsolute, X.Efficiency_pct = 100*I/(4*pi); end
X.FrontBack_dB = NaN;
[pr, pc] = ind2sub(size(T), K.index);
X.PeakTheta_deg = P.Theta(pr); X.PeakPhi_deg = P.Phi(pc);
if G.IsFullSphere, [~, back] = min(util_cosGamma(P, P.Theta(pr), P.Phi(pc)), [], 'all'); X.FrontBack_dB = K.value - T(back); end
E = geo_cut(P, T, Pl.E.CutType, Pl.E.Fixed); H = geo_cut(P, T, Pl.H.CutType, Pl.H.Fixed);
X.HPBW_EPlane_deg = met_hpbw(E.angle, T(E.idx));
X.HPBW_HPlane_deg = met_hpbw(H.angle, T(H.idx));
X.AxialRatioAtPeak_dB = NaN;
if isfield(C, 'AR_dB'), X.AxialRatioAtPeak_dB = C.AR_dB(K.index); end
end
function [bw, lower, upper] = met_hpbw(angleDeg, gainDB, peakGain, peakAngle)
% MET_HPBW Half-power beamwidth of a circular cut: linear interpolation of the −3 dB crossings either side of the peak, angles measured as the signed wrap around the peak.
[bw, lower, upper] = deal(NaN);
ok = isfinite(angleDeg) & isfinite(gainDB); angleDeg = angleDeg(ok); gainDB = gainDB(ok);
if numel(gainDB) < 3, return; end
if nargin < 3 || isempty(peakGain) || ~isfinite(peakGain), [peakGain, i] = max(gainDB); peakAngle = angleDeg(i); end
half = peakGain - 3;
[ra, o] = sort(mod(angleDeg - peakAngle + 180, 360) - 180); rg = gainDB(o);
l = find(ra < 0 & rg <= half, 1, 'last'); r = find(ra > 0 & rg <= half, 1, 'first');
if isempty(l) || isempty(r) || l + 1 > numel(rg) || r - 1 < 1, return; end
li = [l, l + 1]; ri = [r, r - 1];
if diff(rg(li)) == 0 || diff(rg(ri)) == 0, return; end
lc = ra(li(1)) + diff(ra(li))*(half - rg(li(1)))/diff(rg(li));
rc = ra(ri(1)) + diff(ra(ri))*(half - rg(ri(1)))/diff(rg(ri));
lower = peakAngle + lc; upper = peakAngle + rc; bw = rc - lc;
end

%% ---------------- polarisation ----------------
function E = pol_circular(Eth, Eph, which), if which == 1, E = (Eth + 1i*Eph)/sqrt(2); else, E = (Eth - 1i*Eph)/sqrt(2); end   % RHCP/LHCP: E_R=(Eθ+jEφ)/√2, E_L=(Eθ−jEφ)/√2
end
function [Eth, Eph] = pol_fromCircular(Er, El), Eth = (Er + El)/sqrt(2); Eph = (Er - El)/(1i*sqrt(2)); end   % inverse of pol_circular
function [AR, isLinear, sense] = pol_signedAR(Er, El)
% POL_SIGNEDAR Signed axial ratio in dB: + RHCP sense, − LHCP sense; −100 dB at numerically linear samples. SENSE is ±1 (the sign that AR = 0 dB alone cannot carry).
r = abs(Er); l = abs(El); d = r - l;
isLinear = isfinite(d) & abs(d) <= eps .* max(r + l, 1);
AR = min(20*log10((r + l) ./ max(abs(d), eps)), 250) .* sign(d);
AR(isLinear) = -100;
sense = sign(d); sense(~isfinite(d)) = NaN;
end
function pol = pol_classify(Eth, Eph, Er, El, dOmega, beam)
% POL_CLASSIFY Co/cross ordering, cut basis and label from Ω-weighted mean powers inside the main beam (the 45° cone about the peak), not over the whole sphere.
w = dOmega(beam); pw = @(E) sum(abs(E(beam)).^2 .* w) / max(sum(w), realmin);
[pth, pph, pr, pl] = deal(pw(Eth), pw(Eph), pw(Er), pw(El));
pol.Pairs.Linear = ["E_TH", "E_PH"]; if pph > pth, pol.Pairs.Linear = flip(pol.Pairs.Linear); end
pol.Pairs.Circular = ["E_RCP", "E_LCP"]; if pl > pr, pol.Pairs.Circular = flip(pol.Pairs.Circular); end
if max(pr, pl) > max(pth, pph)
    pol.Basis = "Circular";
    pol.Label = "Circular (" + replace(string(pol.Pairs.Circular(1)), ["E_RCP" "E_LCP"], ["RHCP" "LHCP"]) + ")";
elseif pth >= pph
    pol.Basis = "Linear"; pol.Label = "Linear (Vertical)";
else
    pol.Basis = "Linear"; pol.Label = "Linear (Horizontal)";
end
end
function plf = pol_plf(AR_dB, isLinear, rxMode, rxAR_dB, leadingCircular, sense)
% POL_PLF Polarisation loss between the antenna ellipse (signed AR with SENSE ±1) and the incident wave (rxMode, rxAR_dB), major axes orthogonal — the M7 identity: PLF = ½ + (4ρaρw − (ρa²−1)(ρw²−1)) / (2(ρa²+1)(ρw²+1)),  ρa = 10^(|AR|/20)·sense, ρw = ±10^(ARw/20).
switch rxMode
    case "RHCP", sw = 1;
    case "LHCP", sw = -1;
    otherwise,   sw = 2*strcmp(leadingCircular, 'E_RCP') - 1;             % Auto follows the pattern's own sense
end
ra = 10.^(abs(AR_dB)/20) .* sense; ra(isLinear) = 1e12;
rw = sw * 10^(rxAR_dB/20);
plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1)) ./ (2*(ra.^2 + 1)*(rw^2 + 1));
plf = 10*log10(min(max(plf, eps), 1));
plf(~isfinite(AR_dB)) = NaN;                                               % NaN in ⇒ NaN out
end

%% ---------------- coverage ----------------
function T = cov_thresholds(tMin, tMax, step)
% COV_THRESHOLDS Threshold vector by counting, not accumulation (always includes tMax).
if tMax <= tMin, tMax = tMin + step; end
n = round((tMax - tMin)/step); T = tMin + (0:n).'*step;
if T(end) < tMax - 1e-9, T(end+1) = tMax; end
end
function mask = cov_coneMask(P, thc, phc, alpha), mask = util_cosGamma(P, thc, phc) >= cosd(alpha); end   % cone around (thc, phc)
function d = cov_dist(gain, dOmega, mask)
% COV_DIST Store the region's level distribution once: distances from the region peak with their solid angles, cumulative from the bottom. All coverage reads are O(N) off this.
v = mask & isfinite(gain); g = gain(v); w = dOmega(v);
if isempty(g), [d.peak, d.x, d.w, d.cumw, d.Omega] = deal(NaN, [], [], [], 0); return; end
d.peak = max(g);
[d.x, o] = sort(d.peak - g); d.w = w(o);
d.cumw = [0; cumsum(d.w)]; d.Omega = d.cumw(end);
end
function cov = cov_eval(d, T)
% COV_EVAL Coverage(T) = 100 · Ω_R(G > T) / Ω_R from the stored distances (strict >).
cov = zeros(size(T));
if ~(d.Omega > 0), return; end
k = sum(d.x < (d.peak - T(:)).', 1);                      % samples strictly above each threshold
cov = reshape(100 * d.cumw(k + 1) / d.Omega, size(T));
end
function y = cov_at(j, T)
% COV_AT Coverage at threshold(s) T: exact from the stored Ω-distribution, else interpolated from a loaded curve (NaN outside its span).
if ~isempty(j.dist), y = cov_eval(j.dist, T);
else,                y = interp1(j.T, j.cov, T, 'linear', NaN); end
end
function x = cov_thrAt(j, y)
% COV_THRAT Threshold at coverage y %: inverse read — the highest threshold that still reaches y ('last' plateau), from the distribution when stored, else from the loaded curve.
if ~isempty(j.dist)
    d = j.dist; x = nan(size(y));
    if ~(d.Omega > 0), return; end
    k = find(d.cumw(2:end) >= y * d.Omega / 100, 1, 'first');
    if ~isempty(k), x = d.peak - d.x(k); end
else
    [cv, i] = unique(j.cov, 'last'); if numel(cv) < 2, x = nan(size(y)); return; end
    x = interp1(cv, j.T(i), y, 'linear', NaN);
end
end

%% ---------------- utilities ----------------
function v = util_iif(cond, a, b), if cond, v = a; else, v = b; end   % eager scalar choice: both arguments must be safe to evaluate
end
function a = util_wrap180(a), a = mod(a + 180, 360) - 180; end
function canon = util_cutCanonical(type, shown, elevation)
% UTIL_CUTCANONICAL Displayed cut value → physical θ/φ (θ ∈ [0,180], φ ∈ [0,360)).
if type == "Phi", canon = util_iif(elevation, 90 - shown, shown);
else,             canon = mod(shown, 360); end
end
function shown = util_cutDisplay(type, canon, elevation, signedPhi)
% UTIL_CUTDISPLAY Physical cut value → the current display convention.
if type == "Phi", shown = util_iif(elevation, 90 - canon, canon);
else
    shown = mod(canon, 360);
    if signedPhi && shown >= 180, shown = shown - 360; end
end
end
function s = util_planeText(p)   % 'θ-cut at φ = 0°' description of a plane struct (CutType / Fixed)
fixed = util_iif(p.CutType == "Theta", 'φ', 'θ'); s = sprintf('%s-cut at %s = %g°', char(p.CutType), fixed, p.Fixed);
end
function t = colDefs()
% COLDEFS name | label | kind | hidden — the single column table behind kind and label lookups.
t = {'E_Total_dB',           'Total Gain',   'gain',  false
     'E_TH_dB',              'Etheta Gain',  'gain',  true
     'E_PH_dB',              'Ephi Gain',    'gain',  true
     'E_RCP_dB',             'RHCP Gain',    'gain',  false
     'E_LCP_dB',             'LHCP Gain',    'gain',  false
     'AR_dB',                'Axial Ratio',  'ar',    false
     'PLF_dB',               'PLF',          'plf',   false
     'Gain_PolCorrected_dB', 'Polarized Gain', 'gain', false
     'E_TH_Phase',           'Etheta Phase', 'phase', true
     'E_PH_Phase',           'Ephi Phase',   'phase', true
     'E_RCP_Phase',          'RHCP Phase',   'phase', true
     'E_LCP_Phase',          'LHCP Phase',   'phase', true
     'EIRP_dBW',             'EIRP',         'link',  true
     'PFD_Wm2',              'PFD',          'link',  true
     'E_RMS_Vm',             'E_RMS',        'link',  true};
end
function kind = util_colKind(name)
% UTIL_COLKIND "gain" | "ar" | "plf" | "phase" | "link" | "other" from the column table, else from the name itself (gain-only sources carry arbitrary column names).
t = colDefs(); i = find(strcmp(t(:, 1), char(name)), 1);
if ~isempty(i), kind = string(t{i, 3}); return; end
key = regexprep(lower(char(name)), '[^a-z0-9]', '');
if strcmp(key, 'ar') || startsWith(key, 'ardb') || contains(key, 'axial'),          kind = "ar";
elseif contains(key, 'phase') || endsWith(key, 'deg'),                              kind = "phase";
elseif contains(key, 'plf'),                                                        kind = "plf";
elseif contains(key, {'gain', 'directivity', 'eirp', 'dbi'}) || endsWith(key, 'db'), kind = "gain";
else,                                                                               kind = "other";
end
end
function s = util_colLabel(name)
% UTIL_COLLABEL Human label for a column (falls back to the name itself).
t = colDefs(); i = find(strcmp(t(:, 1), char(name)), 1);
if isempty(i), s = char(name); else, s = t{i, 2}; end
end
function s = util_fmtNumber(v, prec)
% UTIL_FMTNUMBER Compact (≤ 2 decimals, no trailing zeros, never "-0") or fixed precision; 'n/a' for non-finite input.
if ~(isscalar(v) && isnumeric(v) && isfinite(v)), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); else, s = sprintf('%.*f', prec, v); end
if strcmp(s, '-0') || isempty(s), s = '0'; end
end
function b = util_presetRange(peak)
% UTIL_PRESETRANGE 50-dB window ending at the next multiple of 5 above the peak (default window when no peak exists).
if ~isfinite(peak), b = [-40 10]; return; end
hi = 5*ceil(peak/5); b = min(max([hi - 50, hi], -250), 100);
end
function t = util_ticks(lim, step)
% UTIL_TICKS Tick list for a range and step; empty when the list would overflow.
if ~isfinite(step) || step <= 0 || diff(lim) <= 0, t = []; return; end
t = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)], 'stable');
if numel(t) > 60, t = []; end
end
function r = util_polarRadius(values, lim), r = min(max((values - lim(1)) / max(diff(lim), eps), 0), 1); end   % colour limits -> 0..1 radius

%% ---------------- input formats ----------------
function S = io_read(fp, textFormat)
% IO_READ Dispatch by extension into S = {Raw, Blocks{f}, Freqs, Meta}; "auto" text resolves first.
[~, ~, ext] = fileparts(fp); ext = lower(erase(ext, '.'));
if textFormat == "auto", textFormat = io_auto(fp); end
S = struct('Raw', table(), 'Blocks', {{}}, 'Freqs', NaN, ...
           'Meta', struct('Format', "", 'Unit', "dB", 'UnitLabel', "dB", 'IsGainOnly', false, ...
                          'IsCoverage', false, 'TextFormat', char(textFormat), 'Notes', strings(1, 0)));
switch ext
    case {'xlsx', 'xls'},                    S = io_excel(fp, S);
    case {'csv', 'txt', 'dat'},              S = io_generic(fp, string(textFormat), S);
    case 'cut',                              S = io_cut(fp, S);
    case {'uan', 'fz', 'out', 'ffs', 'ffe', 'ffd'}, S = io_farfield(fp, ext, S);
    otherwise, error('APAT:Unsupported', 'Unsupported format: .%s', ext);
end
if S.Meta.Unit == "dBi"
    S.Meta.UnitLabel = "dBi";
elseif ~S.Meta.IsGainOnly && ~S.Meta.IsCoverage
    S.Meta.UnitLabel = "dB (rel. field)";
end
end
function tf = isGenericText(fp), [~, ~, e] = fileparts(fp); tf = any(strcmpi(e, {'.csv', '.txt', '.dat'})); end
function fmt = io_auto(fp)
% IO_AUTO One disclosed rule for "auto": header names decide the text format, else gain.
fid = fopen(fp, 'r'); if fid == -1, fmt = "gain"; return; end
hl = fgetl(fid); fclose(fid);
if ~ischar(hl), fmt = "gain"; return; end
names = lower(string(regexp(hl, '[A-Za-z_][A-Za-z0-9_]*', 'match')));
if numel(names) < 6 || ~any(contains(names, ["theta", "etheta", "e_th", "rcp", "lcp", "pol1"]))
    fmt = "gain"; return                                                                % headerless or angle-only tables are gain/coverage
end
if any(contains(names, ["real", "imag", "re_", "im_"])), dom = "reim"; else, dom = "magphase"; end
il = find(contains(names, "lcp"), 1); ir = find(contains(names, "rcp"), 1);
if ~isempty(il) && (isempty(ir) || il < ir), pol = "lcp_rcp"; else, pol = "rcp_lcp"; end
fmt = pol + "_" + dom;
end
function [M, blk, freqs, text, other] = io_scan(fp)
% IO_SCAN One pass over a text far-field file: numeric rows with the modal column count (M), a block index per row (a frequency line starts a new block), every declared frequency, the non-numeric header text, and the remaining numeric lines (e.g. HFSS axis triples).
L = strtrim(readlines(fp));
isNum = strlength(L) > 0 & ~cellfun('isempty', regexp(L, '^[-+.\d][-+\d.eEdD\s,;]*$', 'once'));
tok = regexp(L(isNum), '[-+]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][-+]?\d+)?', 'match');
n = cellfun(@numel, tok); nc = mode(n(n >= 4));
if isempty(nc) || isnan(nc), error('APAT:NoData', 'No numeric data rows (≥ 4 columns) found in %s.', fp); end
keep = n == nc; M = str2double(replace(vertcat(tok{keep}), ["d" "D"], "e"));
fl = regexp(L, '^[#/*\s]*frequenc(?:y|ies)\b[^-+\d]*(.*)$', 'tokens', 'once', 'ignorecase');
isF = ~cellfun('isempty', fl);
freqs = cellfun(@(c) sscanf(char(c{1}), '%f').', fl(isF), 'UniformOutput', false);
b = cumsum(isF); rows = find(isNum); [~, ~, blk] = unique(b(rows(keep)));
text = L(~isNum); other = cellfun(@(t) str2double(t), tok(~keep), 'UniformOutput', false);
end
function [Eth, Eph] = io_fields(A, domain, basis)
% IO_FIELDS Four field columns → complex Eθ, Eφ. domain: "magphase" | "rect"; basis: "thetaphi" | "rcplcp" (R first) | "lcprcp" (L first).
if domain == "magphase"
    c1 = 10.^(A(:, 1)/20) .* exp(1i*deg2rad(A(:, 2)));
    c2 = 10.^(A(:, 3)/20) .* exp(1i*deg2rad(A(:, 4)));
else
    c1 = complex(A(:, 1), A(:, 2)); c2 = complex(A(:, 3), A(:, 4));
end
switch basis
    case "thetaphi", Eth = c1; Eph = c2;
    case "rcplcp",   [Eth, Eph] = pol_fromCircular(c1, c2);
    case "lcprcp",   [Eth, Eph] = pol_fromCircular(c2, c1);
end
end
function S = io_farfield(fp, ext, S)
% IO_FARFIELD UAN/FZ, OUT, FFS, FFE, FFD through one scanner and one spec row: {format, column order → [θ φ a b c d], domain, basis, unit, raw names}.
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
    case {'uan', 'fz'}                       % header assertions: only dB magnitude / degree phase / theta_phi
        hdr = lower(strjoin(text, newline));
        bad = (contains(hdr, 'polarization') && ~contains(hdr, 'theta_phi')) || (contains(hdr, 'magnitude') && ~contains(hdr, 'db'));
        if bad, error('APAT:UnsupportedUAN', 'UAN header declares an unsupported convention (APAT reads theta_phi polarization and dB magnitude).'); end
    case 'ffe', v = cellfun(@(x) x(1), freqs);
    case 'ffd'                               % header = two axis triples (start stop count); blocks = consecutive grids
        tri = other(cellfun(@numel, other) == 3);
        if numel(tri) < 2, error('APAT:FFD', 'FFD header (theta/phi start stop count) not found.'); end
        th = linspace(tri{1}(1), tri{1}(2), round(tri{1}(3))).';
        ph = linspace(tri{2}(1), tri{2}(2), round(tri{2}(3))).';
        n = numel(th)*numel(ph);
        if mod(size(M, 1), n) ~= 0 || size(M, 2) < 4, error('APAT:FFD', 'FFD row count (%d) does not match the %d×%d θ/φ grid.', size(M, 1), numel(th), numel(ph)); end
        nb = size(M, 1)/n; blk = repelem((1:nb).', n);
        M = [repmat([repelem(th, numel(ph)), repmat(ph, numel(th), 1)], nb, 1), M(:, 1:4)];
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
% IO_GENERIC CSV/TXT/DAT: coverage-results table, gain-only pattern, or six-column E-field table.
opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvartype(opts, 'double'); opts = setvaropts(opts, 'TrimNonNumeric', true);
opts.VariableNamingRule = 'preserve';
T = readtable(fp, opts); nc = width(T);
if nc < 2 || isempty(T), error('APAT:InvalidFormat', 'File needs at least two numeric columns.'); end
names = string(T.Properties.VariableNames); low = lower(names); hasHdr = ~all(startsWith(names, "Var"));
if fmt == "gain", used = 1:nc; else, used = 1:min(nc, 6); end
T = rmmissing(T, 'DataVariables', used); c1 = T{:, 1}; c2 = T{:, 2};     % drop rows only for NaN in used columns
kw = contains(low(1), "threshold") || any(contains(low(2:end), "coverage"));
isCov = kw || (~hasHdr && fmt == "gain" && nc < 6 && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictascend') && issorted(c2, 'descend'));   % a CCDF is non-increasing
if isCov
    if ~hasHdr, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:nc - 1))]; end
    S.Raw = T; S.Meta.IsCoverage = true; S.Meta.Format = "Coverage results"; return
end
if fmt == "gain"
    S.Meta.IsGainOnly = true; S.Meta.Format = "Generic text (gain)";
    ith = find(contains(low(1:2), ["theta" "elev"]), 1); iph = find(contains(low(1:2), ["phi" "azim"]), 1);
    if isempty(ith) || isempty(iph) || ith == iph
        wide = 1 + (max(c1) - min(c1) < max(c2) - min(c2)); ith = 3 - wide; iph = wide;   % wider span = φ (disclosed)
        S.Meta.Notes(end+1) = sprintf('Axis order inferred from span: column %d = φ (wider span), column %d = θ.', iph, ith);
    end
    if any(contains(low, "dBi"))
        S.Meta.Unit = "dBi"; S.Meta.Notes(end+1) = "Level unit dBi taken from the column header.";
    else
        S.Meta.Notes(end+1) = "Gain-only text file without a unit header: levels are shown in dB.";
    end
    B = T(:, [ith, iph, setdiff(1:nc, [ith iph])]); B.Properties.VariableNames(1:2) = {'Theta', 'Phi'};
    B.Properties.VariableNames(3:end) = matlab.lang.makeUniqueStrings( matlab.lang.makeValidName(B.Properties.VariableNames(3:end)), {'Theta', 'Phi'});
    S.Raw = T; S.Blocks = {B}; return
end
if nc < 6, error('APAT:TextEFieldColumns', 'The selected generic E-field format requires six numeric columns.'); end
domain = "rect"; if endsWith(fmt, "magphase"), domain = "magphase"; end
basis = "thetaphi"; if startsWith(fmt, "rcp"), basis = "rcplcp"; elseif startsWith(fmt, "lcp"), basis = "lcprcp"; end
A = T{:, 3:6}; layout = "interleaved";
if domain == "magphase"                        % interleaved mag ph mag ph vs grouped mag mag ph ph: header, then ranges
    ph = contains(low(3:6), ["deg" "phase"]);
    if isequal(ph, [false true false true]), layout = "interleaved";
    elseif isequal(ph, [false false true true]), layout = "grouped";
    else
        big = max(abs(A), [], 1, 'omitnan') > 100;
        if big(2) && ~big(3), layout = "interleaved"; else, layout = "grouped"; end
        S.Meta.Notes(end+1) = sprintf('Magnitude/phase column layout "%s" inferred from value ranges (|phase| > 100).', layout);
    end
    if layout == "grouped", A = A(:, [1 3 2 4]); end
end
[Eth, Eph] = io_fields(A, domain, basis);
S.Meta.Format = sprintf('Generic text (%s, %s)', fmt, layout);
if ~hasHdr
    comp = ["E_TH" "E_PH"]; if basis ~= "thetaphi", comp = ["POL1" "POL2"]; end
    if domain == "magphase"
        fn = [comp + "_dB", comp + "_deg"]; if layout == "interleaved", fn = fn([1 3 2 4]); end
    else
        fn = [comp(1) + ["_real" "_imag"], comp(2) + ["_real" "_imag"]];
    end
    T.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", fn]);
end
S.Raw = T;
S.Blocks = {table(c1, c2, real(Eth), imag(Eth), real(Eph), imag(Eph), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'})};
end
function S = io_cut(fp, S)
% IO_CUT TICRA/GRASP .cut: blocks [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data]. ICOMP 1 = θ/φ, 2 = RHCP/LHCP. A single cut becomes a body of revolution at 10° φ steps.
S.Meta.Format = "TICRA/GRASP CUT"; L = readlines(fp); L(strlength(strtrim(L)) == 0) = [];
th = {}; ph = {}; D = {}; i = 1;
while i < numel(L)
    p = sscanf(L(i + 1), '%f'); if numel(p) < 7, error('APAT:CUT', 'Could not parse cut parameter line %d.', i + 1); end
    n = p(3);
    blockData = reshape(sscanf(strjoin(L(i + 2:i + 1 + n), ' '), '%f'), 2*p(7), []).';
    th{end+1, 1} = p(1) + (0:n - 1).'*p(2); ph{end+1, 1} = repmat(p(4), n, 1); D{end+1, 1} = blockData(:, 1:4);   %#ok<AGROW>
    i = i + 2 + n;
end
icomp = p(5); theta = vertcat(th{:}); phi = vertcat(ph{:}); M = vertcat(D{:});
if ~any(icomp == [1 2]), error('APAT:UnsupportedICOMP', 'GRASP cut ICOMP = %d is not supported (1 = theta/phi, 2 = RHCP/LHCP).', icomp); end
if p(6) == 2, [theta, phi] = deal(phi, theta); S.Meta.Notes(end+1) = "ICUT = 2: φ swept, θ constant per block."; end
if isscalar(unique(phi))
    theta = repmat(theta, 36, 1); M = repmat(M, 36, 1); phi = repelem((0:10:350).', numel(phi));
    S.Meta.Notes(end+1) = "Single cut in file: pattern synthesised as a body of revolution (φ = 0:10:350).";
end
if icomp == 2
    [Eth, Eph] = pol_fromCircular(complex(M(:, 1), M(:, 2)), complex(M(:, 3), M(:, 4)));
    raw = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'};
else
    Eth = complex(M(:, 1), M(:, 2)); Eph = complex(M(:, 3), M(:, 4));
    raw = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'};
end
S.Raw = array2table([theta phi M], 'VariableNames', [{'Theta', 'Phi'}, raw]);
S.Blocks = {table(theta, phi, real(Eth), imag(Eth), real(Eph), imag(Eph), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'})};
end
function S = io_excel(fp, S)
% IO_EXCEL Matrix workbooks: fixed component sheets (dBi magnitude / degree phase), C3-origin matrices.
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi" "RHCP_Phase_degrees" "LHCP_Gain_dBi" "LHCP_Phase_degrees"];
lin  = ["Etheta_Gain_dBi" "Etheta_Phase_degrees" "Ephi_Gain_dBi" "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
if ~(hasC || hasL), error('APAT:ExcelMatrixFormat', 'Unsupported workbook: no Etheta/Ephi or RHCP/LHCP component sheets found.'); end
req = [circ(1:4*hasC) lin(1:4*hasL)];
S.Meta.Format = sprintf('Excel Matrix Format %d', 1*(hasL && ~hasC) + 2*(hasC && ~hasL) + 3*(hasC && hasL));
S.Meta.Unit = "dBi";
X = struct(); th = []; ph = [];
for k = 1:numel(req)
    sheet = sheets(find(strcmpi(sheets, req(k)), 1)); [t, p, X.(req(k))] = xl_matrix(fp, sheet);
    if k == 1, th = t; ph = p;
    elseif ~isequal(size(t), size(th)) || any(abs(t - th) > 1e-9, 'all') || any(abs(p - ph) > 1e-9, 'all')
        error('APAT:ExcelMatrixGrid', 'All component sheets must share the same theta/phi grid.');
    end
end
mp = @(g, f) 10.^(X.(g)/20) .* exp(1i*deg2rad(X.(f)));
if hasL
    Eth = mp("Etheta_Gain_dBi", "Etheta_Phase_degrees"); Eph = mp("Ephi_Gain_dBi", "Ephi_Phase_degrees");
else
    [Eth, Eph] = pol_fromCircular(mp("RHCP_Gain_dBi", "RHCP_Phase_degrees"), mp("LHCP_Gain_dBi", "LHCP_Phase_degrees"));
end
[Pr, Tr] = meshgrid(ph, th); vals = cellfun(@(f) X.(f)(:), cellstr(req), 'UniformOutput', false);
S.Raw = table(Tr(:), Pr(:), vals{:}, 'VariableNames', [{'Theta', 'Phi'}, cellstr(req)]);
S.Blocks = {table(Tr(:), Pr(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'})};
S.Freqs = 1e6 * xl_lookup(fp, sheets(1), 'Pattern Simulation Freq (MHz):');
end
function [theta, phi, data] = xl_matrix(fp, sheet)
% XL_MATRIX One C3-origin matrix: row 2 (C onward) = φ, column B (row 3 onward) = θ.
C = readcell(fp, 'Sheet', char(sheet)); isnum = @(x) isnumeric(x) && isscalar(x) && isfinite(x);
if size(C, 1) < 3 || size(C, 2) < 3, error('APAT:ExcelMatrixSheet', 'Sheet "%s" has no C3-origin matrix.', sheet); end
pm = cellfun(isnum, C(2, 3:end)); tm = cellfun(isnum, C(3:end, 2));
nP = find(~pm, 1) - 1; nT = find(~tm, 1) - 1;
if isempty(nP), nP = numel(pm); end
if isempty(nT), nT = numel(tm); end
if any(pm(nP + 1:end)) || any(tm(nT + 1:end)), error('APAT:ExcelMatrixAxis', 'Sheet "%s" has a gap in its theta/phi axis.', sheet); end
phi = cell2mat(C(2, 3:2 + nP)); theta = cell2mat(C(3:2 + nT, 2)); block = C(3:2 + nT, 3:2 + nP);
if ~all(cellfun(isnum, block), 'all'), error('APAT:ExcelMatrixSheet', 'Sheet "%s" contains non-numeric matrix samples.', sheet); end
data = cell2mat(block);
if any(diff(theta) <= 0) || any(diff(phi) <= 0) || theta(1) < -1e-9 || theta(end) > 180 + 1e-9 ...
        || phi(1) < -1e-9 || phi(end) >= 360
    error('APAT:ExcelMatrixAxis', 'Sheet "%s": axes must be strictly increasing with θ ∈ [0,180], φ ∈ [0,360).', sheet);
end
end
function v = xl_lookup(fp, sheet, label)
% XL_LOOKUP Numeric value to the right of a labelled summary cell; NaN when absent.
v = NaN;
try C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
[r, c] = find(cellfun(@(x) (ischar(x) || isstring(x)) && strcmpi(strtrim(string(x)), label), C), 1);
if isempty(r), return; end
for k = c + 1:size(C, 2)
    if isnumeric(C{r, k}) && isscalar(C{r, k}) && isfinite(C{r, k}), v = C{r, k}; return; end
end
end
function [T, curves, names] = io_coverageCSV(fp)
% IO_COVERAGECSV Coverage-results file: column 1 = thresholds, remaining columns = curves.
opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvartype(opts, 'double'); opts.VariableNamingRule = 'preserve';
R = readtable(fp, opts);
if width(R) < 2, error('APAT:CoverageFile', 'A coverage file needs at least two columns (threshold, curve…).'); end
T = R{:, 1}; curves = R{:, 2:end};
names = cellstr(matlab.lang.makeValidName(string(R.Properties.VariableNames(2:end))));
end

%% ---------------- output formats ----------------
function T = util_longTable(P, D)
% UTIL_LONGTABLE Canonical long-format table: one row per (θ, φ) sample, every derived column.
n = numel(P.Theta); m = numel(P.Phi);
names = fieldnames(D.Cols).';
vals = cellfun(@(nm) reshape(D.Cols.(nm), [], 1), names, 'UniformOutput', false);
T = table(repmat(P.Theta(:), m, 1), repelem(P.Phi(:), n), vals{:}, 'VariableNames', [{'Theta', 'Phi'}, names]);
end
function io_writeUAN(fp, P, D)
% IO_WRITEUAN XGTD UAN: free-format header (mag_phase, dB, theta_phi) + six tab-delimited columns. Levels and phases come from Derived, so loss and parameters are already applied; the periodic grid gains the closing φ column XGTD expects.
need = {'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase'};
if ~all(isfield(D.Cols, need)), error('APAT:UAN', 'UAN export needs E-field columns (gain-only patterns cannot be exported).'); end
header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\n' ...
    'theta_min %g\ntheta_max %g\ntheta_inc %g\ncomplex\nmag_phase\npattern gain\nmagnitude dB\n'
    'maximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
    min(P.Phi), max(P.Phi), P.dPhi, min(P.Theta), max(P.Theta), P.dTheta, D.Peak.value);
writelines(header, fp);
cols = {D.Cols.E_TH_dB, D.Cols.E_PH_dB, D.Cols.E_TH_Phase, D.Cols.E_PH_Phase}; ph = P.Phi(:);
if abs(numel(ph)*P.dPhi - 360) < 1e-6
    for q = 1:4, cols{q}(:, end+1) = cols{q}(:, 1); end
    ph(end+1) = ph(1) + 360;
end
r = @(x) round(x(:), 5);
T = table(repmat(P.Theta(:), numel(ph), 1), repelem(ph, numel(P.Theta)), ...
          r(cols{1}), r(cols{2}), r(cols{3}), r(cols{4}), ...
          'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'});
writetable(T, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
end

%% ---------------- self-test plumbing ----------------
function T = stRow(T, name, fun, want)
% STROW One self-test row: {name, got, want, pass}; an exception is a failed row.
try
    out = fun(); got = string(out{1}); ok = all(logical(out{2}), 'all');
catch ME
    got = "ERROR: " + string(ME.message); ok = false;
end
T(end+1, :) = [name, got, string(want), string(ok)];
end
