classdef APAT_v3_M8_1 < matlab.apps.AppBase
%APAT_V3_M8  Antenna Pattern Analysis Tool — release M8 (architecture rebuild of APAT_v3_M7_110_5).
%
%   Base MATLAB only (R2025a baseline (which support ), no toolboxes). One file, App Designer-style handles, same tabs and
%   features as M7: Pattern tab (full-pattern views, cuts, metrics, exports), Input tab, Coverage tab.
%
%   DATAFLOW (every arrow is one function; nothing is copied, nothing is memoised, nothing is synchronised)
%
%     FILE ─► io_read ────────────────► Source   {Raw, Blocks{f}, Freqs, Meta}
%          ─► pat_build (+pat_resample) ► Pattern  {Theta, Phi, dTheta, dPhi, Eth, Eph | G.(name), Revision}
%          ─► geo_build ───────────────► Geometry {wTheta, dPhi, dOmega, Omega, PhiPeriodic, IsFullSphere}
%          ─► pat_derive(P, G, Params) ► Derived  {Cols.(name), Peak, Pol, Boresight, Planes, Metrics}
%          ─► app.Pats(k) = {Key, Name, Path, Source, Pattern, Geometry, Derived, Params}
%                 Main tab reads Pats(app.Main); every coverage tree node stores its k.
%     VIEW = readConfig() ─► MAP = geo_displayMap(View) ─► renderers (index permutation + labels only).
%
%   RULES
%     * Widgets are READ only in readConfig/readCoverageConfig and WRITTEN only in apply*/render* methods.
%     * Every numerical function below the "File-scope functions" line is app-free and widget-free.
%     * update(scope) builds into locals and commits with one assignment (an error leaves the old state intact).
%     * Physical quantities (peak, boresight, planes, metrics) are defined on total gain; the selected component
%       changes plots, cuts, tables and the POB marker only.
%     * Conventions live in Const / Meta and are listed in the Metadata table.
%
%   Run:  app = APAT_v3_M8;        Self-test (no UI):  APAT_v3_M8.selfTest

% Loading Error: Nothing happens

    %% ============================================================ UI handles (App Designer style)
    properties (Access = public)
        UIFigure                    matlab.ui.Figure
        MainTabGroup                matlab.ui.container.TabGroup
        Tab_Main                    matlab.ui.container.Tab
        Tab_Input                   matlab.ui.container.Tab
        Tab_Coverage                matlab.ui.container.Tab
        % Pattern tab — file bar
        Single_Button_Browse        matlab.ui.control.Button
        Single_EditField_File       matlab.ui.control.EditField
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
        Single_Switch_ThetaSpan     matlab.ui.control.Switch
        Single_Switch_PhiSpan       matlab.ui.control.Switch
        Single_Spinner_Cmin         matlab.ui.control.Spinner
        Single_Spinner_Cmax         matlab.ui.control.Spinner
        Single_Plot_Cstep           matlab.ui.control.Spinner
        Single_Button_AutoRange     matlab.ui.control.Button
        Single_CheckBox_POB         matlab.ui.control.CheckBox
        Single_CheckBox_Overlay     matlab.ui.control.CheckBox
        Single_Table_metadata       matlab.ui.control.Table
        % Pattern tab — full-pattern views
        Single_Panel_fullPattern    matlab.ui.container.Panel
        Single_TabGroup_Full        matlab.ui.container.TabGroup
        Single_Tab_Map              matlab.ui.container.Tab
        Single_Tab_Sphere           matlab.ui.container.Tab
        Single_Tab_Polar3D          matlab.ui.container.Tab
        Single_Tab_UV               matlab.ui.container.Tab
        Single_Tab_Contour          matlab.ui.container.Tab
        Single_Axes_Map             matlab.ui.control.UIAxes
        Single_Axes_Sphere          matlab.ui.control.UIAxes
        Single_Axes_Polar3D         matlab.ui.control.UIAxes
        Single_Axes_UV              matlab.ui.control.UIAxes
        Single_Axes_Contour         matlab.ui.control.UIAxes
        % Pattern tab — cuts
        Single_Panel_Rect           matlab.ui.container.Panel
        Single_Switch_EHplane       matlab.ui.control.Switch
        Single_DropDown_cutType     matlab.ui.control.DropDown
        Single_DropDown_cutValue    matlab.ui.control.Spinner
        Single_gridEcut             matlab.ui.container.GridLayout
        CutFieldBasisDropDown       matlab.ui.control.DropDown
        CheckBox_Et                 matlab.ui.control.CheckBox
        CheckBox_Er                 matlab.ui.control.CheckBox
        CheckBox_El                 matlab.ui.control.CheckBox
        Button_HPBW                 matlab.ui.control.StateButton
        Label_HPBW                  matlab.ui.control.Label
        Single_Spinner_CutMin       matlab.ui.control.Spinner
        Single_Spinner_CutMax       matlab.ui.control.Spinner
        Single_Axes_Polar           matlab.graphics.axis.PolarAxes
        Single_Axes_Ctr             matlab.ui.control.UIAxes
        Single_StatusBar            matlab.ui.control.Label
        % Input tab
        Input_Label                 matlab.ui.control.Label
        Input_Table                 matlab.ui.control.Table
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
        Perf = struct()             % seconds per action scope (developer channel: app.Perf)
        Status = struct('Main', '', 'Cov', '')   % persistent text of each status bar
        StatusTimer                 % the single transient-status timer
        Busy = false
        IsClosing = false
        JobCounter = 0              % coverage job ids
        Stamp = 0                   % increments on every Derived commit (render-key ingredient)
        InputStamp = -1             % Stamp at which the Input table was last filled
        DefaultParams               % parameter widget values at startup (Reset button)
        Tips = gobjects(0)          % coverage query datatips
    end

    %% ============================================================ Conventions (one place each; shown in Metadata)
    properties (Constant)
        Const = struct( ...
            'ReleaseName',        'APAT v3 M8', ...
            'PeakExcessDB',       6, ...       % spike = exceeds every grid neighbour by more than this (I5)
            'LinearAR_dB',        -100, ...    % signed AR displayed at numerically linear samples
            'FloorDB',            -100, ...    % dB floor for zero power / zero PLF
            'AngleDecimals',      5, ...       % angles are snapped; field values are never rounded (I1)
            'UniformTolDeg',      1e-4, ...    % uniform-axis assertion (> snapping error of 5-decimal angles)
            'RevolutionPhiStep',  10, ...      % single-cut body-of-revolution synthesis (disclosed)
            'ConeHalfAngleDeg',   45, ...      % boresight-axis selection cone
            'DistanceFloorM',     1e-3, ...
            'StatusSeconds',      3)
        Axes6 = struct('labels', {{'+X', '-X', '+Y', '-Y', '+Z', '-Z'}}, ...
                       'theta', [90 90 90 90 0 180], 'phi', [0 180 90 270 0 0])
        FileFilter = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.txt;*.dat', 'Antenna patterns'; ...
                      '*.*', 'All files'}
    end

    %% ============================================================ Lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_1()
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

    %% ============================================================ Orchestration
    methods (Access = private)
        function initState(app)
            app.Range = struct('full', [-50 0], 'cut', [-50 0], 'cov', [-40 10], 'covX', [-40 10], ...
                               'Auto', struct('full', true, 'cut', true, 'cov', true, 'covX', true));
            app.DefaultParams = app.readConfig().Params;
            app.StatusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', app.Const.StatusSeconds, ...
                                    'TimerFcn', @(~, ~) app.restoreStatus());
            app.initGraphics();
            app.applyVisibility(false);
            app.setStatus(app.Single_StatusBar, 'Select a pattern file to begin.', false);
            app.setStatus(app.Cov_StatusBar, 'Add a pattern or load a results file.', false);
            app.UIFigure.Visible = 'on';
        end

        function on(app, scope, arg)
            %ON Every callback lands here: busy guard, error boundary, performance record, one drawnow.
            if nargin < 3, arg = []; end
            if app.Busy || app.IsClosing, return; end
            app.Busy = true; t0 = tic;
            app.UIFigure.Pointer = 'watch';
            try
                app.update(string(scope), arg);
            catch ME
                bar = app.Single_StatusBar; if startsWith(string(scope), "cov"), bar = app.Cov_StatusBar; end
                app.setStatus(bar, ['Error: ' ME.message], true);
                if ~app.IsClosing, uialert(app.UIFigure, ME.message, app.Const.ReleaseName, 'Icon', 'error'); end
            end
            app.Perf.(matlab.lang.makeValidName(char(scope))) = toc(t0);
            app.Busy = false;
            if isvalid(app.UIFigure), app.UIFigure.Pointer = 'arrow'; end
            drawnow limitrate
        end

        function update(app, scope, arg)
            %UPDATE Recompute exactly the invalidation radius of SCOPE, then let the renderers reconcile their keys.
            %
            %   SOURCE ─► PATTERN(Rev) ─► GEOMETRY ─► DERIVED(Rev, Params)   committed into Pats(Main) in one step
            %   VIEW ─► MAP ─► ColIdx / axes / labels / cut-value domain      touches nothing above
            %
            is = @(varargin) any(scope == string(varargin));
            if startsWith(scope, "cov"), app.updateCoverage(scope, arg); return; end
            if is("browse")
                [f, p] = uigetfile(app.FileFilter, 'Select an antenna pattern file', app.startDir());
                if isequal(f, 0), return; end
                arg = fullfile(p, f); scope = "source";
            end
            if is("export"), app.exportMain(arg); return; end
            if is("reset")
                app.applyParams(app.DefaultParams); scope = "params";
            end
            if is("source", "rebuild")
                if scope == "source"
                    path = string(arg); source = []; app.applyChoices([]);
                else
                    if app.Main == 0, return; end
                    path = app.Pats(app.Main).Path; source = app.Pats(app.Main).Source;
                end
                try
                    E = app.buildEntry(path, app.readConfig(), source);     % may throw: nothing committed yet (I13)
                catch ME
                    if ~strcmp(ME.identifier, 'APAT:CoverageFile'), rethrow(ME); end
                    app.covLoadResults(char(path)); app.MainTabGroup.SelectedTab = app.Tab_Coverage; app.covRefresh();
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
                D = pat_derive(E.Pattern, E.Geometry, cfg.Params, app.Const, app.Axes6);   % tens of ms; nothing memoised
                app.Pats(app.Main).Derived = D; app.Pats(app.Main).Params = cfg.Params;
                app.Stamp = app.Stamp + 1;
            end
            if app.Main == 0, return; end
            if is("plane"), app.applyPlane(); end
            if is("range"), app.Range.(arg) = app.readRange(arg); app.Range.Auto.(arg) = false; end
            if is("autorange"), app.Range.Auto.full = true; app.Range.Auto.cut = true; end
            canon = [];                                                       % keep the cut through a span toggle (I8)
            if is("span") && isfield(app.View, 'CutType')
                canon = util_cutCanonical(app.View.CutType, app.View.CutValue, app.View.Elevation);
            end
            app.View = app.readConfig();
            E = app.Pats(app.Main);
            app.Map = geo_displayMap(E.Pattern, E.Geometry, app.View);
            if ~isempty(canon)
                app.setSpinner(app.Single_DropDown_cutValue, util_cutDisplay(app.View.CutType, canon, app.View.Elevation, app.View.SignedPhi));
            end
            if is("source", "rebuild", "span", "cuttype", "plane"), app.applyCutDomain(); app.View = app.readConfig(); end
            if is("source", "rebuild", "params", "component", "autorange"), app.applyAutoRanges(); end
            app.renderFull();
            app.renderCut();
            if is("source", "rebuild", "params", "component", "span", "plane"), app.applyMetadata(); app.applyStatus(); end
            app.applyInputTable();
        end

        function E = buildEntry(app, path, cfg, source)
            %BUILDENTRY Source → Pattern → Geometry → Derived for one file, into locals only (I13).
            if isempty(source), source = io_read(char(path)); end
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
            cfg.CutType    = string(app.Single_DropDown_cutType.Value);          % "Theta": fixed φ | "Phi": fixed θ
            cfg.CutValue   = app.Single_DropDown_cutValue.Value;
            cfg.Basis      = string(app.CutFieldBasisDropDown.Value);            % "Auto" | "Linear" | "Circular"
            cfg.Traces     = logical([app.CheckBox_Et.Value, app.CheckBox_Er.Value, app.CheckBox_El.Value]);
            cfg.HPBW       = logical(app.Button_HPBW.Value);
            cfg.POB        = logical(app.Single_CheckBox_POB.Value);
            cfg.Overlay    = logical(app.Single_CheckBox_Overlay.Value);
            cfg.Elevation  = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°');
            cfg.SignedPhi  = strcmp(app.Single_Switch_PhiSpan.Value, '-180° to 180°');
            cfg.CStep      = app.Single_Plot_Cstep.Value;
            cfg.FreqIndex  = app.Single_DropDown_Freq.Value;
            cfg.StepChoice = string(app.Single_DropDown_step.Value);             % "native" | "1deg"
            cfg.FullView   = str2double(app.Single_TabGroup_Full.SelectedTab.Tag);
            cfg.InputTab   = app.MainTabGroup.SelectedTab == app.Tab_Input;
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
            %APPLYCHOICES Item lists and enable states that depend on the loaded pattern.
            if isempty(E)                                                     % new file: choices start from defaults
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
            app.applyVisibility(true);
        end

        function applyVisibility(app, loaded)
            set([app.Single_Panel_Rect, app.Single_Panel_fullPattern, app.Single_Panel_plotControl, ...
                 app.Single_Export_Output, app.Single_Export_UAN, app.Single_Button_Coverage, ...
                 app.Single_Button_Process, app.Single_Table_metadata], 'Visible', loaded);
        end

        function applyParams(app, prm)
            app.Single_Spinner_Loss.Value = prm.L; app.Single_DropDown_RxPol.Value = char(prm.RxMode);
            app.Single_Spinner_Rw.Value = prm.RxAR_dB; app.Single_Spinner_Pt.Value = prm.Pt_dBW;
            app.Single_DropDown_Pt.Value = 'dBW'; app.Single_Spinner_R.Value = prm.R_m; app.Single_DropDown_R.Value = 'm';
        end

        function applyPlane(app)
            %APPLYPLANE E/H switch → cut controls from the principal-axis planes of the loaded pattern.
            D = app.Pats(app.Main).Derived; V = app.readConfig();
            plane = D.Planes.H; if startsWith(app.Single_Switch_EHplane.Value, 'E'), plane = D.Planes.E; end
            app.Single_DropDown_cutType.Value = char(plane.CutType);
            app.setSpinner(app.Single_DropDown_cutValue, util_cutDisplay(plane.CutType, plane.Fixed, V.Elevation, V.SignedPhi));
        end

        function applyCutDomain(app)
            %APPLYCUTDOMAIN Cut-value spinner domain follows the display convention of the fixed angle (I8).
            V = app.View; P = app.Pats(app.Main).Pattern; M = app.Map;
            if V.CutType == "Theta", axisVals = M.PhiAxis(1:numel(P.Phi)); step = P.dPhi;
            else,                    axisVals = M.ThetaAxis;                step = P.dTheta; end
            canon = util_cutCanonical(V.CutType, V.CutValue, V.Elevation);
            shown = util_cutDisplay(V.CutType, canon, V.Elevation, V.SignedPhi);
            [~, i] = min(abs(axisVals - shown));
            app.setSpinner(app.Single_DropDown_cutValue, axisVals(i), [min(axisVals), max(axisVals)], step);
        end

        function setSpinner(~, sp, value, limits, step)
            %SETSPINNER Value first inside open limits, then the real limits (a value outside Limits is an error).
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
            %PRESETRANGE Display range per column kind; gain-like columns use the non-spike peak rounded up to 5 dB.
            D = app.Pats(app.Main).Derived;
            switch util_colKind(name)
                case "ar",    r = [-30 30];
                case "phase", r = [-180 180];
                case "plf",   r = [-30 0];
                otherwise
                    C = D.Cols.(name); v = C(~D.Peak.spike & isfinite(C));
                    r = util_presetRange(max(v, [], 'all'));
            end
        end

        function [lims, cmap] = theme(app, name)
            %THEME Colour scale per column kind: signed AR is a fixed blue-white-red thermometer, phase is cyclic.
            switch util_colKind(name)
                case "ar",    lims = [-30 30];   cmap = app.Gfx.Maps.ar;
                case "phase", lims = [-180 180]; cmap = app.Gfx.Maps.phase;
                otherwise,    lims = app.Range.full; cmap = app.Gfx.Maps.gain;
            end
        end

        function [names, labels, show] = cutTraceNames(app)
            %CUTTRACENAMES Trace columns of the cut: total/co/cross for fields, the selected column for gain-only (I4, §16-8).
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
            %APPLYINPUTTABLE The raw source table is pushed to the Input tab lazily (only when visible and stale).
            if ~app.View.InputTab || app.InputStamp == app.Stamp, return; end
            E = app.Pats(app.Main);
            app.Input_Table.Data = E.Source.Raw;
            app.Input_Label.Text = sprintf('%s — %s — %d rows as parsed (%s)', E.Name, E.Source.Meta.Format, ...
                                           height(E.Source.Raw), strjoin(cellstr(E.Source.Meta.Notes), '; '));
            app.InputStamp = app.Stamp;
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
            %APPLYMETADATA Facts, metrics, parameters and conventions — every convention APAT applies is listed here.
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
                'Peak (POB)',           sprintf('%s %s at [θ %s°, φ %s°]', f(D.Peak.value, 2), P.Meta.UnitLabel, f(M.PeakTheta_deg), f(M.PeakPhi_deg))
                'Peak policy',          sprintf('spatial isolation > %g dB; %d spike(s) excluded', K.PeakExcessDB, D.Peak.spikeCount)
                'Raw maximum',          sprintf('%s %s', f(D.Peak.rawValue, 2), P.Meta.UnitLabel)
                'Boresight axis',       app.Axes6.labels{D.Boresight}
                'E-plane / H-plane',    sprintf('%s / %s', util_planeText(D.Planes.E), util_planeText(D.Planes.H))
                'HPBW E-plane',         sprintf('%s°', f(M.HPBW_EPlane_deg))
                'HPBW H-plane',         sprintf('%s°', f(M.HPBW_HPlane_deg))
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
            app.Single_StatusBar.Text = app.Status.Main;
            app.Cov_StatusBar.Text = app.Status.Cov;
        end
        %% ------------------------------------------------ retained graphics
        function initGraphics(app)
            %INITGRAPHICS Colormaps, context menu, colorbars, cut lines and markers are created exactly once (I12).
            app.Gfx.Maps = struct('gain', jet(256), 'phase', hsv(256), ...
                                  'ar', interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)));
            menu = uicontextmenu(app.UIFigure);
            uimenu(menu, 'Text', 'Auto colour range', 'MenuSelectedFcn', @(~, ~) app.on("autorange"));
            uimenu(menu, 'Text', 'Export this view as PNG…', 'MenuSelectedFcn', @(~, ~) app.on("export", "png"));
            axesList = [app.Single_Axes_Map, app.Single_Axes_Sphere, app.Single_Axes_Polar3D, app.Single_Axes_UV, app.Single_Axes_Contour];
            F = repmat(struct('Axes', [], 'Colorbar', [], 'Surface', gobjects(0), 'Overlay', gobjects(0), ...
                              'Marker', gobjects(0), 'Label', gobjects(0), 'Topo', '', 'Key', ''), 1, 5);
            for v = 1:5
                F(v).Axes = axesList(v); F(v).Colorbar = colorbar(axesList(v)); axesList(v).ContextMenu = menu;
            end
            app.Gfx.Full = F;
            pa = app.Single_Axes_Polar; ra = app.Single_Axes_Ctr; colors = lines(3);
            hold(pa, 'on'); hold(ra, 'on'); grid(ra, 'on'); ra.ContextMenu = menu;
            pa.ThetaZeroLocation = 'top'; pa.ThetaDir = 'clockwise';
            for t = 1:3
                C.Polar(t) = polarplot(pa, NaN, NaN, 'LineWidth', 1.4, 'Color', colors(t, :));
                C.Rect(t) = plot(ra, NaN, NaN, 'LineWidth', 1.4, 'Color', colors(t, :));
            end
            C.HPBWPatch = patch(ra, 'XData', NaN(4, 1), 'YData', NaN(4, 1), 'FaceColor', [0.9 0.6 0.1], ...
                                'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
            C.HPBWPolar = polarplot(pa, NaN(2, 2), NaN(2, 2), '--', 'Color', [0.9 0.6 0.1], 'HandleVisibility', 'off');
            C.MarkerRect = plot(ra, NaN, NaN, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off');
            C.MarkerPolar = polarplot(pa, NaN, NaN, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off');
            C.Text = text(ra, 0, 0, '', 'FontSize', 9, 'VerticalAlignment', 'bottom', 'Clipping', 'off');
            C.Key = '';
            app.Gfx.Cut = C;
        end

        function k = cutKey(app)
            V = app.View;
            k = sprintf('%s|%g|%s|%s', V.CutType, V.CutValue, V.Basis, mat2str(V.Traces));
        end

        function [cut, labels, show] = currentCut(app)
            %CURRENTCUT One geo_cut of the current trace stack (the only cut extraction per change).
            E = app.Pats(app.Main); D = E.Derived; V = app.View;
            [names, labels, show] = app.cutTraceNames();
            C = zeros([size(D.Cols.(names{1})), numel(names)]);
            for t = 1:numel(names), C(:, :, t) = D.Cols.(names{t}); end
            cut = geo_cut(E.Pattern, C, V.CutType, util_cutCanonical(V.CutType, V.CutValue, V.Elevation));
        end

        function renderFull(app)
            %RENDERFULL Render the visible full-pattern tab only: objects are recreated on a topology change and
            %   updated in place otherwise; an unchanged key returns immediately.
            v = app.View.FullView; F = app.Gfx.Full(v); ax = F.Axes;
            E = app.Pats(app.Main); P = E.Pattern; G = E.Geometry; D = E.Derived; V = app.View; M = app.Map;
            comp = V.Component; if ~isfield(D.Cols, comp), comp = D.GainName; end
            [lims, cmap] = app.theme(comp);
            key = sprintf('%d|%s|%s|%g|%g|%g|%d|%d|%s', app.Stamp, M.Key, comp, lims, V.CStep, V.POB, V.Overlay, ...
                          util_iif(V.Overlay, app.cutKey(), ''));
            if strcmp(F.Key, key), return; end
            C = D.Cols.(comp); Cd = C(:, M.ColIdx);
            yMap = M.ThetaAxis; Cmap = Cd;
            if numel(yMap) > 1 && yMap(1) > yMap(end), yMap = flipud(yMap); Cmap = flipud(Cd); end   % image rows ascend
            [PH, TH] = meshgrid(P.Phi(M.ColIdx), P.Theta);
            X = sind(TH).*cosd(PH); Y = sind(TH).*sind(PH); Z = cosd(TH); up = P.Theta <= 90;
            ticks = util_ticks(lims, V.CStep);
            lv = ticks; if numel(lv) < 2, lv = linspace(lims(1), lims(2), 11); end   % contour levels
            r = util_polarRadius(Cd, lims);
            topo = sprintf('%s|%dx%d', M.Key, size(Cd));
            if ~strcmp(F.Topo, topo) || ~isgraphics(F.Surface)
                cla(ax); hold(ax, 'on');
                switch v
                    case 1, F.Surface = imagesc(ax, M.PhiAxis([1 end]), yMap([1 end]), Cmap);
                    case 2, F.Surface = surf(ax, X, Y, Z, Cd, 'EdgeColor', 'none');
                    case 3, F.Surface = surf(ax, r.*X, r.*Y, r.*Z, Cd, 'EdgeColor', 'none');
                    case 4, F.Surface = surf(ax, X(up, :), Y(up, :), zeros(nnz(up), size(X, 2)), Cd(up, :), 'EdgeColor', 'none');
                    case 5, [~, F.Surface] = contourf(ax, M.PhiAxis, yMap, Cmap, lv, 'LineColor', 'none');
                end
                F.Overlay = plot3(ax, NaN, NaN, NaN, 'k-', 'LineWidth', 1.5);
                F.Marker = plot3(ax, NaN, NaN, NaN, 'o', 'MarkerSize', 6, 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'w');
                F.Label = text(ax, 0, 0, 0, '', 'FontSize', 9, 'BackgroundColor', [1 1 0.85], 'Margin', 2, 'Clipping', 'off');
                if any(v == [2 3]), axis(ax, 'equal', 'vis3d', 'off'); view(ax, 135, 25); end
                if v == 4, view(ax, 2); axis(ax, 'equal'); xlim(ax, [-1 1]); ylim(ax, [-1 1]); xlabel(ax, 'u = sinθ cosφ'); ylabel(ax, 'v = sinθ sinφ'); end
                if any(v == [1 5]), axis(ax, 'tight'); xlabel(ax, 'φ (°)'); ylabel(ax, M.ThetaLabel); end
                F.Topo = topo;
            else
                switch v
                    case 1, set(F.Surface, 'XData', M.PhiAxis([1 end]), 'YData', yMap([1 end]), 'CData', Cmap);
                    case 2, F.Surface.CData = Cd;
                    case 3, set(F.Surface, 'XData', r.*X, 'YData', r.*Y, 'ZData', r.*Z, 'CData', Cd);
                    case 4, F.Surface.CData = Cd(up, :);
                    case 5, set(F.Surface, 'ZData', Cmap, 'LevelList', lv);
                end
            end
            if any(v == [1 5]), ax.YDir = M.ThetaDir; end
            % POB marker of the displayed component (display only; physics stays on total gain)
            pk = met_peak(C, G.PhiPeriodic, app.Const.PeakExcessDB, P.Theta);
            [pr, pc] = ind2sub(size(C), pk.index); pcd = find(M.ColIdx == pc, 1);
            u = [X(pr, pcd), Y(pr, pcd), Z(pr, pcd)];
            switch v
                case {1, 5}, pos = [M.PhiAxis(pcd), M.ThetaAxis(pr), 1];
                case 2,      pos = 1.02*u;
                case 3,      pos = (r(pr, pcd) + 0.02)*u;
                case 4,      pos = [u(1:2), 0.1]; if ~up(pr), pos = NaN(1, 3); end
            end
            set(F.Marker, 'XData', pos(1), 'YData', pos(2), 'ZData', pos(3), 'Visible', V.POB);
            set(F.Label, 'Position', pos, 'Visible', V.POB, 'String', sprintf(' POB %s %s\n θ %s°, φ %s°', ...
                util_fmtNumber(pk.value, 2), P.Meta.UnitLabel, util_fmtNumber(P.Theta(pr)), util_fmtNumber(P.Phi(pc))));
            % optional cut overlay on the two spherical views
            ov = NaN(1, 3);
            if V.Overlay && any(v == [2 3])
                cut = app.currentCut();
                ov = [sind(cut.theta).*cosd(cut.phi), sind(cut.theta).*sind(cut.phi), cosd(cut.theta)];
                if v == 2, ov = 1.01*ov; else, ov = (util_polarRadius(cut.values(:, 1), lims) + 0.005).*ov; end
            end
            set(F.Overlay, 'XData', ov(:, 1), 'YData', ov(:, 2), 'ZData', ov(:, 3));
            clim(ax, lims); colormap(ax, cmap);
            F.Colorbar.Ticks = ticks; F.Colorbar.Label.String = char(P.Meta.UnitLabel);
            title(ax, sprintf('%s [%s]', util_colLabel(comp), P.Meta.UnitLabel));
            F.Key = key; app.Gfx.Full(v) = F;
        end

        function renderCut(app)
            %RENDERCUT Polar + rectangular cut of the trace stack with POB and HPBW on the first shown trace.
            V = app.View; C = app.Gfx.Cut; E = app.Pats(app.Main); P = E.Pattern; G = E.Geometry;
            key = sprintf('%d|%s|%s|%d|%d|%g|%g', app.Stamp, app.Map.Key, app.cutKey(), V.HPBW, V.POB, app.Range.cut);
            if strcmp(C.Key, key), return; end
            [cut, labels, show] = app.currentCut();
            a = cut.angle; Y = cut.values;
            if V.CutType == "Theta" && V.Elevation, a = 90 - a; end       % full-circle θ → elevation-like angle
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
                    set(C.Rect(t), 'XData', a, 'YData', Y(:, t), 'DisplayName', labels{t});
                end
                set([C.Polar(t), C.Rect(t)], 'Visible', t <= nT && show(min(t, numel(show))));
            end
            pa = app.Single_Axes_Polar; ra = app.Single_Axes_Ctr;
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
                    set(C.MarkerRect, 'XData', a(ip), 'YData', pv, 'Visible', 'on');
                    set(C.MarkerPolar, 'ThetaData', deg2rad(a(ip)), 'RData', pv, 'Visible', 'on');
                    set(C.Text, 'Position', [a(ip), pv, 0], 'String', sprintf(' %s %s @ %s°', util_fmtNumber(pv, 2), P.Meta.UnitLabel, util_fmtNumber(a(ip))));
                end
                if V.HPBW
                    [bw, lo, hi] = met_hpbw(a, Y(:, t0));
                    if isfinite(bw)
                        yl = app.Range.cut;
                        set(C.HPBWPatch, 'XData', [lo hi hi lo], 'YData', [yl(1) yl(1) yl(2) yl(2)], 'Visible', 'on');
                        set(C.HPBWPolar(1), 'ThetaData', deg2rad([lo lo]), 'RData', yl, 'Visible', 'on');
                        set(C.HPBWPolar(2), 'ThetaData', deg2rad([hi hi]), 'RData', yl, 'Visible', 'on');
                        app.Label_HPBW.Text = sprintf('HPBW %s° [%s°, %s°] on %s', util_fmtNumber(bw, 2), ...
                                                      util_fmtNumber(lo, 1), util_fmtNumber(hi, 1), labels{t0});
                    else
                        app.Label_HPBW.Text = 'HPBW n/a (no −3 dB crossing on this cut)';
                    end
                end
            end
            C.Key = key; app.Gfx.Cut = C;
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
        %% ============================================================ Coverage tab
        %  The tree IS the job registry: a pattern node stores k (index into Pats), a job node stores its curve
        %  {id, label, T, cov, dist, Line}. Nothing is copied from the Pattern tab and nothing is synchronised.
        function c = readCoverageConfig(app)
            c.Component = string(app.Cov_DropDown_Component.Value);
            c.Conical   = logical(app.Cov_Radio_Conical.Value);
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
                case "covClearTips", delete(app.Tips(isgraphics(app.Tips))); app.Tips = gobjects(0);
                case "covExport",    app.covExport();
            end
            app.covRefresh();
        end

        function covAddPattern(app, path)
            k = [];
            if ~isempty(app.Pats), k = find([app.Pats.Key] == string(path), 1); end
            if isempty(k)
                E = app.buildEntry(path, app.readConfig(), []);
                app.Pats = [app.Pats, E]; k = numel(app.Pats);
            end
            for n = app.Cov_TreeNode_Patterns.Children(:).'
                if n.NodeData.k == k, app.Cov_Tree.SelectedNodes = n; return; end
            end
            node = uitreenode(app.Cov_TreeNode_Patterns, 'Text', char(app.Pats(k).Name));
            node.NodeData = struct('kind', "pattern", 'k', k);
            expand(app.Cov_TreeNode_Patterns); app.Cov_Tree.SelectedNodes = node;
            app.setStatus(app.Cov_StatusBar, sprintf('Pattern "%s" added — set thresholds and compute coverage.', app.Pats(k).Name), false);
        end

        function covRefreshPatternNodes(app)
            %COVREFRESHPATTERNNODES The Pattern-tab entry was rebuilt: its node follows, its old curves are stale.
            for n = app.Cov_TreeNode_Patterns.Children(:).'
                if n.NodeData.k ~= app.Main, continue; end
                n.Text = char(app.Pats(app.Main).Name);
                for j = app.covJobs(n).', app.covDeleteNode(j); end
            end
            app.covRefresh();
        end

        function node = covPatternNode(app)
            %COVPATTERNNODE The pattern node owning the selection (or the first pattern node).
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
            %COVJOBS Job nodes below ROOTS (default: whole tree), in id order; optionally checked ones only.
            if nargin < 2 || isempty(roots), roots = [app.Cov_TreeNode_Patterns, app.Cov_TreeNode_Results]; end
            if nargin < 3, checkedOnly = false; end
            checked = app.Cov_Tree.CheckedNodes;
            jobs = []; ids = []; stack = roots(:);
            while ~isempty(stack)
                n = stack(1); stack(1) = [];
                d = n.NodeData;
                if isstruct(d) && isfield(d, 'kind') && d.kind == "job" && (~checkedOnly || any(n == checked))
                    jobs = [jobs; n]; ids(end+1) = d.id; %#ok<AGROW>
                end
                stack = [stack; n.Children(:)]; %#ok<AGROW>
            end
            if ~isempty(jobs), [~, o] = sort(ids); jobs = jobs(o); end
        end

        function covCompute(app, c)
            pn = app.covPatternNode();
            if isempty(pn), error('APAT:Coverage', 'Add a pattern to the Coverage tree first.'); end
            E = app.Pats(pn.NodeData.k); D = E.Derived;
            if ~isfield(D.Cols, c.Component)
                error('APAT:Coverage', 'Component "%s" is not available in "%s".', c.Component, E.Name);
            end
            C = D.Cols.(c.Component);
            if c.Conical
                mask = cov_coneMask(E.Pattern, c.Cone(1), c.Cone(2), c.Cone(3));
                region = sprintf('cone θ%s° φ%s° ±%s°', util_fmtNumber(c.Cone(1)), util_fmtNumber(c.Cone(2)), util_fmtNumber(c.Cone(3)));
            else
                mask = true(size(C)); region = util_iif(E.Geometry.IsFullSphere, 'full sphere', 'measured region');
            end
            d = cov_dist(C, E.Geometry.dOmega, mask);
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
            jobs = app.covJobs([], true);
            if isempty(jobs), app.setStatus(app.Cov_StatusBar, 'Check at least one curve to query.', true); return; end
            msg = {};
            for n = jobs.'
                j = n.NodeData;
                if mode == "thr", x = c.QueryThr; y = cov_at(j, x); else, y = c.QueryCov; x = cov_thrAt(j, y); end
                if ~(isfinite(x) && isfinite(y)), msg{end+1} = sprintf('R%d: n/a', j.id); continue; end %#ok<AGROW>
                app.Tips(end+1) = datatip(j.Line, x, y, 'SnapToDataVertex', 'off');
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
            %COVREFRESH Visibility, legend, ranges, component list and the threshold-union table — from the tree only.
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
                if app.Range.Auto.cov, app.Range.cov = [0 100]; end
            end
            if app.Range.covX(2) > app.Range.covX(1), xlim(ax, app.Range.covX); end
            if app.Range.cov(2) > app.Range.cov(1), ylim(ax, app.Range.cov); end
            app.setSpinner(app.Cov_Spinner_Xmin, app.Range.covX(1)); app.setSpinner(app.Cov_Spinner_Xmax, app.Range.covX(2));
            app.setSpinner(app.Cov_Spinner_Ymin, app.Range.cov(1));  app.setSpinner(app.Cov_Spinner_Ymax, app.Range.cov(2));
        end
        %% ============================================================ Layout (declarative: one line per widget)
        function h = place(~, h, row, col, varargin)
            %PLACE Grid cell + name/value defaults for one already-constructed widget.
            if ~isempty(varargin), set(h, varargin{:}); end
            h.Layout.Row = row; h.Layout.Column = col;
        end

        function lab(app, parent, row, col, text)
            app.place(uilabel(parent, 'Text', text), row, col);
        end

        function g = mkgrid(~, parent, rows, cols)
            g = uigridlayout(parent, [numel(rows), numel(cols)], 'RowHeight', rows, 'ColumnWidth', cols, ...
                             'Padding', [4 4 4 4], 'RowSpacing', 4, 'ColumnSpacing', 6);
        end

        function createComponents(app)
            cb = @(scope, varargin) @(~, ~) app.on(scope, varargin{:});
            app.UIFigure = uifigure('Visible', 'off', 'Name', app.Const.ReleaseName, 'Position', [60 60 1500 900], ...
                                    'CloseRequestFcn', @(~, ~) delete(app));
            root = uigridlayout(app.UIFigure, [1 1], 'Padding', [0 0 0 0]);
            app.MainTabGroup = uitabgroup(root, 'SelectionChangedFcn', cb("view"));
            app.Tab_Main     = uitab(app.MainTabGroup, 'Title', 'Pattern');
            app.Tab_Input    = uitab(app.MainTabGroup, 'Title', 'Input');
            app.Tab_Coverage = uitab(app.MainTabGroup, 'Title', 'Coverage');

            % ---------------- Pattern tab
            g  = app.mkgrid(app.Tab_Main, {'fit', '1x', 22}, {340, '1x'});
            fb = app.place(app.mkgrid(g, {24}, {90, '1x', 150, 80, 130, 120, 110}), 1, [1 2], 'Padding', [0 0 0 0]);
            app.Single_Button_Browse   = app.place(uibutton(fb, 'Text', 'Browse…', 'ButtonPushedFcn', cb("browse")), 1, 1);
            app.Single_EditField_File  = app.place(uieditfield(fb, 'Editable', 'off', 'Placeholder', 'No pattern loaded'), 1, 2);
            app.Single_DropDown_Freq   = app.place(uidropdown(fb, 'Items', {'—'}, 'ItemsData', {1}, 'Visible', 'off', 'ValueChangedFcn', cb("rebuild")), 1, 3);
            app.Single_Button_Process  = app.place(uibutton(fb, 'Text', 'Reload', 'Tooltip', 'Re-read the file with the current frequency / step choice', 'ButtonPushedFcn', cb("rebuild")), 1, 4);
            app.Single_Button_Coverage = app.place(uibutton(fb, 'Text', 'Add to Coverage', 'ButtonPushedFcn', cb("covAddMain")), 1, 5);
            app.Single_Export_Output   = app.place(uibutton(fb, 'Text', 'Export table…', 'ButtonPushedFcn', cb("export", "output")), 1, 6);
            app.Single_Export_UAN      = app.place(uibutton(fb, 'Text', 'Export UAN…', 'ButtonPushedFcn', cb("export", "uan")), 1, 7);

            lc = app.place(app.mkgrid(g, {'fit', 'fit', '1x'}, {'1x'}), 2, 1, 'Padding', [0 0 0 0]);
            app.Single_Panel_Params = app.place(uipanel(lc, 'Title', 'Link & polarisation parameters'), 1, 1);
            pg = app.mkgrid(app.Single_Panel_Params, {22, 22, 22, 22}, {'fit', '1x', 'fit', 78});
            app.lab(pg, 1, 1, 'Loss (dB)');
            app.Single_Spinner_Loss   = app.place(uispinner(pg, 'Value', 0, 'Step', 0.5, 'ValueChangedFcn', cb("params")), 1, 2);
            app.lab(pg, 1, 3, 'Rx pol.');
            app.Single_DropDown_RxPol = app.place(uidropdown(pg, 'Items', {'Auto', 'RHCP', 'LHCP', 'Linear'}, 'ValueChangedFcn', cb("params")), 1, 4);
            app.lab(pg, 2, 1, 'Rx wave AR (dB)');
            app.Single_Spinner_Rw     = app.place(uispinner(pg, 'Value', 0, 'Limits', [0 60], 'Step', 0.5, 'ValueChangedFcn', cb("params")), 2, 2);
            app.Single_Button_Reset   = app.place(uibutton(pg, 'Text', 'Reset', 'ButtonPushedFcn', cb("reset")), 2, [3 4]);
            app.lab(pg, 3, 1, 'Tx power');
            app.Single_Spinner_Pt     = app.place(uispinner(pg, 'Value', 0, 'ValueChangedFcn', cb("params")), 3, 2);
            app.Single_DropDown_Pt    = app.place(uidropdown(pg, 'Items', {'dBW', 'dBm', 'Watts'}, 'ValueChangedFcn', cb("params")), 3, [3 4]);
            app.lab(pg, 4, 1, 'Distance');
            app.Single_Spinner_R      = app.place(uispinner(pg, 'Value', 1, 'Limits', [0 Inf], 'ValueChangedFcn', cb("params")), 4, 2);
            app.Single_DropDown_R     = app.place(uidropdown(pg, 'Items', {'m', 'km'}, 'ValueChangedFcn', cb("params")), 4, [3 4]);

            app.Single_Panel_plotControl = app.place(uipanel(lc, 'Title', 'Display'), 2, 1);
            cg = app.mkgrid(app.Single_Panel_plotControl, {22, 26, 22, 22, 22}, {'fit', '1x', 'fit', '1x'});
            app.lab(cg, 1, 1, 'Component');
            app.Single_DropDown_Component = app.place(uidropdown(cg, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', cb("component")), 1, [2 3]);
            app.Single_DropDown_step      = app.place(uidropdown(cg, 'Items', {'STEP: native'}, 'ItemsData', {'native'}, 'ValueChangedFcn', cb("rebuild")), 1, 4);
            app.lab(cg, 2, 1, 'θ axis');
            app.Single_Switch_ThetaSpan   = app.place(uiswitch(cg, 'slider', 'Items', {'0° to 180°', '-90° to 90°'}, 'ValueChangedFcn', cb("span")), 2, 2);
            app.lab(cg, 2, 3, 'φ axis');
            app.Single_Switch_PhiSpan     = app.place(uiswitch(cg, 'slider', 'Items', {'0° to 360°', '-180° to 180°'}, 'ValueChangedFcn', cb("span")), 2, 4);
            app.lab(cg, 3, 1, 'Colour min / max');
            app.Single_Spinner_Cmin       = app.place(uispinner(cg, 'Value', -50, 'Step', 5, 'ValueChangedFcn', cb("range", "full")), 3, 2);
            app.Single_Spinner_Cmax       = app.place(uispinner(cg, 'Value', 0, 'Step', 5, 'ValueChangedFcn', cb("range", "full")), 3, 3);
            app.Single_Button_AutoRange   = app.place(uibutton(cg, 'Text', 'Auto', 'ButtonPushedFcn', cb("autorange")), 3, 4);
            app.lab(cg, 4, 1, 'Colour tick step');
            app.Single_Plot_Cstep         = app.place(uispinner(cg, 'Value', 5, 'Limits', [0.1 100], 'Step', 1, 'ValueChangedFcn', cb("cstep")), 4, 2);
            app.Single_CheckBox_POB       = app.place(uicheckbox(cg, 'Text', 'POB marker', 'Value', true, 'ValueChangedFcn', cb("pob")), 4, [3 4]);
            app.Single_CheckBox_Overlay   = app.place(uicheckbox(cg, 'Text', 'Overlay the cut on the 3-D views', 'Value', false, 'ValueChangedFcn', cb("overlay")), 5, [1 4]);
            app.Single_Table_metadata     = app.place(uitable(lc, 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {140, 'auto'}, 'RowName', {}), 3, 1);

            rc = app.place(app.mkgrid(g, {'1x', '1x'}, {'1x'}), 2, 2, 'Padding', [0 0 0 0]);
            app.Single_Panel_fullPattern = app.place(uipanel(rc, 'Title', 'Full pattern'), 1, 1);
            fg = app.mkgrid(app.Single_Panel_fullPattern, {'1x'}, {'1x'});
            app.Single_TabGroup_Full = uitabgroup(fg, 'SelectionChangedFcn', cb("view"));
            titles = {'2-D map', '3-D sphere', '3-D polar', 'UV (upper hemisphere)', 'Contour'};
            tabs = cell(1, 5); axs = cell(1, 5);
            for v = 1:5
                tabs{v} = uitab(app.Single_TabGroup_Full, 'Title', titles{v}, 'Tag', num2str(v));
                axs{v} = uiaxes(app.mkgrid(tabs{v}, {'1x'}, {'1x'}));
            end
            [app.Single_Tab_Map, app.Single_Tab_Sphere, app.Single_Tab_Polar3D, app.Single_Tab_UV, app.Single_Tab_Contour] = tabs{:};
            [app.Single_Axes_Map, app.Single_Axes_Sphere, app.Single_Axes_Polar3D, app.Single_Axes_UV, app.Single_Axes_Contour] = axs{:};

            app.Single_Panel_Rect = app.place(uipanel(rc, 'Title', 'Cuts'), 2, 1);
            kg = app.mkgrid(app.Single_Panel_Rect, {'fit', '1x', 18}, {'1x', '1x'});
            hb = app.place(app.mkgrid(kg, {24}, {150, 'fit', 130, 'fit', 90, 'fit', 90, '1x', 'fit', 80, 80}), 1, [1 2], 'Padding', [0 0 0 0]);
            app.Single_Switch_EHplane    = app.place(uiswitch(hb, 'slider', 'Items', {'E-plane', 'H-plane'}, 'ValueChangedFcn', cb("plane")), 1, 1);
            app.lab(hb, 1, 2, 'Cut');
            app.Single_DropDown_cutType  = app.place(uidropdown(hb, 'Items', {'θ-cut (φ fixed)', 'φ-cut (θ fixed)'}, 'ItemsData', {'Theta', 'Phi'}, 'ValueChangedFcn', cb("cuttype")), 1, 3);
            app.lab(hb, 1, 4, 'at');
            app.Single_DropDown_cutValue = app.place(uispinner(hb, 'Value', 0, 'ValueChangedFcn', cb("cut")), 1, 5);
            app.lab(hb, 1, 6, 'Basis');
            app.CutFieldBasisDropDown    = app.place(uidropdown(hb, 'Items', {'Auto', 'Linear', 'Circular'}, 'ValueChangedFcn', cb("basis")), 1, 7);
            app.Single_gridEcut = app.place(app.mkgrid(hb, {24}, {'fit', 'fit', 'fit'}), 1, 8, 'Padding', [0 0 0 0]);
            app.CheckBox_Et = app.place(uicheckbox(app.Single_gridEcut, 'Text', 'Total', 'Value', true, 'ValueChangedFcn', cb("traces")), 1, 1);
            app.CheckBox_Er = app.place(uicheckbox(app.Single_gridEcut, 'Text', 'Co-pol', 'Value', true, 'ValueChangedFcn', cb("traces")), 1, 2);
            app.CheckBox_El = app.place(uicheckbox(app.Single_gridEcut, 'Text', 'Cross-pol', 'Value', true, 'ValueChangedFcn', cb("traces")), 1, 3);
            app.Button_HPBW           = app.place(uibutton(hb, 'state', 'Text', 'HPBW', 'ValueChangedFcn', cb("hpbw")), 1, 9);
            app.Single_Spinner_CutMin = app.place(uispinner(hb, 'Value', -50, 'Step', 5, 'Tooltip', 'Cut range minimum', 'ValueChangedFcn', cb("range", "cut")), 1, 10);
            app.Single_Spinner_CutMax = app.place(uispinner(hb, 'Value', 0, 'Step', 5, 'Tooltip', 'Cut range maximum', 'ValueChangedFcn', cb("range", "cut")), 1, 11);
            app.Single_Axes_Polar = app.place(polaraxes(kg), 2, 1);
            app.Single_Axes_Ctr   = app.place(uiaxes(kg), 2, 2);
            app.Label_HPBW        = app.place(uilabel(kg, 'Text', '', 'FontColor', [0.6 0.35 0]), 3, [1 2]);
            app.Single_StatusBar  = app.place(uilabel(g, 'Text', '', 'Tag', 'Main', 'FontColor', [0.2 0.2 0.2]), 3, [1 2]);

            % ---------------- Input tab
            ig = app.mkgrid(app.Tab_Input, {'fit', '1x'}, {'1x'});
            app.Input_Label = app.place(uilabel(ig, 'Text', 'The rows of the source file, as parsed, appear here after a pattern is loaded.'), 1, 1);
            app.Input_Table = app.place(uitable(ig), 2, 1);

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
            sg = app.mkgrid(sp, {22, 46, 22, 22, 26}, {'fit', '1x', '1x', '1x'});
            app.lab(sg, 1, 1, 'Component');
            app.Cov_DropDown_Component  = app.place(uidropdown(sg, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}), 1, [2 4]);
            app.Cov_ButtonGroup_CovType = app.place(uibuttongroup(sg, 'BorderType', 'none', 'SelectionChangedFcn', cb("covType")), 2, [1 4]);
            app.Cov_Radio_Spherical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Whole pattern (sphere / measured region)', 'Position', [4 24 330 20], 'Value', true);
            app.Cov_Radio_Conical   = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Cone around (θ, φ) with half-angle ±', 'Position', [4 2 330 20]);
            app.lab(sg, 3, 1, 'Cone θ / φ / ±');
            app.Cov_Spinner_ConeTheta = app.place(uispinner(sg, 'Value', 0, 'Limits', [0 180]), 3, 2);
            app.Cov_Spinner_ConePhi   = app.place(uispinner(sg, 'Value', 0, 'Limits', [0 360]), 3, 3);
            app.Cov_Spinner_ConeAngle = app.place(uispinner(sg, 'Value', 60, 'Limits', [0 180]), 3, 4);
            app.lab(sg, 4, 1, 'Thresholds min / max / step');
            app.Cov_Spinner_ThreshMin  = app.place(uispinner(sg, 'Value', -40), 4, 2);
            app.Cov_Spinner_ThreshMax  = app.place(uispinner(sg, 'Value', 10), 4, 3);
            app.Cov_Spinner_ThreshStep = app.place(uispinner(sg, 'Value', 0.5, 'Limits', [1e-3 100]), 4, 4);
            app.Cov_Button_Compute = app.place(uibutton(sg, 'Text', 'Compute coverage', 'Enable', 'off', 'ButtonPushedFcn', cb("covCompute")), 5, [1 4]);
            rg = app.place(app.mkgrid(vg, {'1x', 'fit', 'fit', 200}, {'1x'}), 1, 2, 'Padding', [0 0 0 0]);
            app.Cov_Axes = app.place(uiaxes(rg), 1, 1);
            qg = app.place(app.mkgrid(rg, {24}, {'fit', 70, 90, 'fit', 70, 90, '1x', 80, 90}), 2, 1, 'Padding', [0 0 0 0]);
            app.lab(qg, 1, 1, 'Query at threshold (dB)');
            app.Cov_Spinner_QueryThr = app.place(uispinner(qg, 'Value', 0), 1, 2);
            app.Cov_Button_QueryThr  = app.place(uibutton(qg, 'Text', 'Coverage?', 'ButtonPushedFcn', cb("covQueryThr")), 1, 3);
            app.lab(qg, 1, 4, 'Query at coverage (%)');
            app.Cov_Spinner_QueryCov = app.place(uispinner(qg, 'Value', 90, 'Limits', [0 100]), 1, 5);
            app.Cov_Button_QueryCov  = app.place(uibutton(qg, 'Text', 'Threshold?', 'ButtonPushedFcn', cb("covQueryCov")), 1, 6);
            app.Cov_Button_ClearTips = app.place(uibutton(qg, 'Text', 'Clear tips', 'ButtonPushedFcn', cb("covClearTips")), 1, 8);
            app.Cov_Button_Export    = app.place(uibutton(qg, 'Text', 'Export…', 'Enable', 'off', 'ButtonPushedFcn', cb("covExport")), 1, 9);
            xg = app.place(app.mkgrid(rg, {24}, {'fit', 70, 70, 'fit', 70, 70, 60, '1x'}), 3, 1, 'Padding', [0 0 0 0]);
            app.lab(xg, 1, 1, 'Threshold axis');
            app.Cov_Spinner_Xmin = app.place(uispinner(xg, 'Value', -40, 'ValueChangedFcn', cb("covRange", "covX")), 1, 2);
            app.Cov_Spinner_Xmax = app.place(uispinner(xg, 'Value', 10, 'ValueChangedFcn', cb("covRange", "covX")), 1, 3);
            app.lab(xg, 1, 4, 'Coverage axis');
            app.Cov_Spinner_Ymin = app.place(uispinner(xg, 'Value', 0, 'ValueChangedFcn', cb("covRange", "cov")), 1, 5);
            app.Cov_Spinner_Ymax = app.place(uispinner(xg, 'Value', 100, 'ValueChangedFcn', cb("covRange", "cov")), 1, 6);
            app.Cov_Button_AutoRange = app.place(uibutton(xg, 'Text', 'Auto', 'ButtonPushedFcn', cb("covAutoRange")), 1, 7);
            app.Cov_Tabel     = app.place(uitable(rg, 'RowName', {}), 4, 1);
            app.Cov_StatusBar = app.place(uilabel(vg, 'Text', '', 'Tag', 'Cov', 'FontColor', [0.2 0.2 0.2]), 2, [1 2]);
            hold(app.Cov_Axes, 'on'); grid(app.Cov_Axes, 'on');
            xlabel(app.Cov_Axes, 'Threshold (dB)'); ylabel(app.Cov_Axes, 'Coverage (%)');
            title(app.Cov_Axes, 'Coverage(T) = 100 · Ω_R(G > T) / Ω_R');
        end
    end

    %% ============================================================ Self-test (release gate, no UI)
    methods (Static)
        function ok = selfTest()
            %SELFTEST Kernel checks on a synthetic RHCP Gaussian beam (20° HPBW on +Z) at 1°×1°. Prints one line per check.
            K = APAT_v3_M8_1.Const; A6 = APAT_v3_M8_1.Axes6;
            prm = struct('L', 0, 'RxMode', "Auto", 'RxAR_dB', 0, 'Pt_dBW', 0, 'R_m', 1);
            [PH, TH] = meshgrid((0:359).', (0:180).');
            E = 10.^(-3*(TH/10).^2/20); Eth = E/sqrt(2); Eph = -1i*E/sqrt(2);             % Eφ = −jEθ ⇒ RHCP (B.5)
            S = io_source({struct('Theta', TH(:), 'Phi', PH(:), 'Eth', Eth(:), 'Eph', Eph(:))}, 2.4e9, table(), io_meta('Synthetic', "dBi"));
            P = pat_build(S, 1, K); G = geo_build(P); D = pat_derive(P, G, prm, K, A6);
            C = D.Cols.E_Total_dB; T = cov_thresholds(-40, 0, 0.5);
            d = cov_dist(C, G.dOmega, true(size(C))); cov = cov_eval(d, T);
            ref = arrayfun(@(t) 100*sum(G.dOmega(C > t))/sum(G.dOmega(:)), T);
            D2 = pat_derive(P, G, setfield(prm, 'L', -3), K, A6); %#ok<SFLD>
            Cs = C; Cs(60, 100) = Cs(60, 100) + 30; pk = met_peak(Cs, true, K.PeakExcessDB, P.Theta);
            P2 = pat_resample(P, 2); P3 = pat_resample(P, 3);
            M = geo_displayMap(P, G, struct('SignedPhi', true, 'Elevation', true));
            cut = geo_cut(P, C, "Theta", 0);
            try, util_assertUniform([0 1 2 3.5], 'θ', K.UniformTolDeg); uniformErr = false; catch ME, uniformErr = strcmp(ME.identifier, 'APAT:NonUniformGrid'); end
            checks = {
                'geometry: Σ ΔΩ = 4π exactly',              abs(G.Omega - 4*pi) < 1e-9 && G.IsFullSphere
                'circular sense: RHCP ≫ LHCP',              all(D.Cols.E_RCP_dB(:) - D.Cols.E_LCP_dB(:) > 60)
                'peak on +Z, boresight +Z',                 D.Peak.row == 1 && D.Boresight == 5
                'HPBW ≈ 20° on E and H planes',             abs(D.Metrics.HPBW_EPlane_deg - 20) < 0.2 && abs(D.Metrics.HPBW_HPlane_deg - 20) < 0.2
                'polarisation label Circular (RHCP)',       startsWith(D.Pol.Label, "Circular (RHCP)")
                'PLF: RHCP wave on RHCP antenna = 0 dB',    abs(D.Cols.PLF_dB(1, 1)) < 1e-6
                'loss is a pure offset',                    max(abs(D2.Cols.E_Total_dB(:) - C(:) + 3)) < 1e-9 && D2.Peak.index == D.Peak.index
                'coverage kernel ≡ definition',             max(abs(cov - ref)) < 1e-9
                'coverage inverse consistent',              all(cov_eval(d, cov_inverse(d, [10 50 90]) - 1e-9) >= [10 50 90] - 1e-9)
                'thresholds counted exactly',               numel(cov_thresholds(-40, 10, 0.1)) == 501
                'isolated spike excluded from the peak',    pk.wasAdjusted && pk.spikeCount == 1 && pk.index == D.Peak.index
                'decimation is exact / 3° grid by interp',  isequal(P2.Eth, P.Eth(1:2:end, 1:2:end)) && numel(P3.Theta) == 61
                'display map = permutation + closing col',  isequal(sort(M.ColIdx(1:end-1)), 1:360) && M.PhiAxis(1) == -180 && M.ColIdx(end) == M.ColIdx(1)
                'θ-cut closes through both poles',          numel(cut.angle) == 360 && cut.closed
                'non-uniform axis is rejected',             uniformErr
                'number formatting',                        strcmp(util_fmtNumber(-0.001), '0') && strcmp(util_fmtNumber(12.5), '12.5') && strcmp(util_fmtNumber(100), '100')};
            ok = all([checks{:, 2}]);
            for k = 1:size(checks, 1), fprintf('  [%s] %s\n', util_iif(checks{k, 2}, 'PASS', 'FAIL'), checks{k, 1}); end
            fprintf('%s self-test: %s (%d checks)\n', K.ReleaseName, util_iif(ok, 'PASS', 'FAIL'), size(checks, 1));
        end
    end
end
%% ====================================================================== File-scope functions (app-free)
%% ---------------------------------------------------------------------- Pattern, geometry, display map, cuts

function P = pat_build(S, f, K)
%PAT_BUILD Canonical grid-native pattern from source block f (I1): polar θ ∈ [0,180] ascending, φ ∈ [0,360)
%   ascending, uniform steps asserted once, no seam column, angles snapped, field values untouched.
    B = S.Blocks{f}; Meta = S.Meta; notes = Meta.Notes;
    th = double(B.Theta(:)); ph = double(B.Phi(:));
    if Meta.ThetaConvention == "elevation", th = 90 - th; end
    neg = th < 0; th(neg) = -th(neg); ph(neg) = ph(neg) + 180;            % θ < 0 lies in the opposite half-plane
    th = mod(th, 360); over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;
    th = round(th, K.AngleDecimals); ph = round(mod(ph, 360), K.AngleDecimals); ph(ph >= 360) = ph(ph >= 360) - 360;
    Theta = unique(th); Phi = unique(ph);
    util_assertUniform(Theta, 'θ', K.UniformTolDeg); util_assertUniform(Phi, 'φ', K.UniformTolDeg);
    n = numel(Theta); m = numel(Phi);
    [~, i] = ismember(th, Theta); [~, j] = ismember(ph, Phi);
    [cells, first] = unique(sub2ind([n m], i, j), 'first');               % duplicates (closed seam, pole repeats): first wins
    if numel(cells) ~= n*m
        error('APAT:NonUniformGrid', 'The θ×φ grid is irregular: %d of %d cells have no sample.', n*m - numel(cells), n*m);
    end
    if numel(first) < numel(th)
        notes(end+1) = sprintf("%d duplicate direction(s) folded (closed φ seam / over-the-pole samples)", numel(th) - numel(first));
    end
    put = @(v) util_place(cells, v(first), n, m);
    P = struct('Theta', Theta(:), 'Phi', Phi(:), 'dTheta', util_step(Theta, 180), 'dPhi', util_step(Phi, 360), ...
               'Eth', [], 'Eph', [], 'G', struct(), 'IsGainOnly', Meta.IsGainOnly, ...
               'Freq', S.Freqs(min(f, numel(S.Freqs))), 'Revision', uint64(1), 'Meta', Meta, 'NativeStep', [NaN NaN]);
    if Meta.IsGainOnly
        for nm = string(fieldnames(B.G)).', P.G.(nm) = put(B.G.(nm)); end
    else
        P.Eth = put(B.Eth); P.Eph = put(B.Eph);
    end
    if m == 1                                                             % single cut → body of revolution (disclosed)
        P.Phi = (0:K.RevolutionPhiStep:360 - K.RevolutionPhiStep).'; m = numel(P.Phi); P.dPhi = K.RevolutionPhiStep;
        if Meta.IsGainOnly
            for nm = string(fieldnames(P.G)).', P.G.(nm) = repmat(P.G.(nm), 1, m); end
        else
            P.Eth = repmat(P.Eth, 1, m); P.Eph = repmat(P.Eph, 1, m);
        end
        notes(end+1) = sprintf("single cut replicated as a body of revolution every %g° in φ", K.RevolutionPhiStep);
    end
    P.NativeStep = [P.dTheta, P.dPhi];
    P.Meta.Notes = notes;
end

function P = pat_resample(P, step)
%PAT_RESAMPLE Exact decimation when step/native ∈ ℕ on both axes; otherwise bilinear on the φ-closed grid in linear
%   power (+ unit phasor for fields) — never in dB, AR or PLF (I6, B.4). Target axes never leave the source domain.
    rT = step/P.dTheta; rP = step/P.dPhi;
    periodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
    if abs(rT - round(rT)) < 1e-9 && abs(rP - round(rP)) < 1e-9 && rT >= 1 && rP >= 1
        it = 1:round(rT):numel(P.Theta); jp = 1:round(rP):numel(P.Phi);
        thetaT = P.Theta(it); phiT = P.Phi(jp);
        lin = @(M) M(it, jp);
    else
        thetaT = (P.Theta(1):step:P.Theta(end) + 1e-9).';
        phiEnd = P.Phi(end) + P.dPhi*periodic;
        phiT = (P.Phi(1):step:phiEnd + 1e-9).';
        if periodic && abs(phiT(end) - phiEnd) < 1e-9, phiT(end) = []; end
        srcPhi = P.Phi; if periodic, srcPhi(end+1) = phiEnd; end
        [PS, TS] = meshgrid(srcPhi, P.Theta); [PT, TT] = meshgrid(phiT, thetaT);
        lin = @(M) interp2(PS, TS, util_iif(periodic, [M, M(:, 1)], M), PT, TT, 'linear');
    end
    if P.IsGainOnly
        for nm = string(fieldnames(P.G)).'
            if any(util_colKind(nm) == ["gain", "link"]), P.G.(nm) = 10*log10(max(lin(10.^(P.G.(nm)/10)), realmin));
            else,                                          P.G.(nm) = lin(P.G.(nm)); end
        end
    else
        P.Eth = field(P.Eth); P.Eph = field(P.Eph);
    end
    P.Theta = thetaT(:); P.Phi = phiT(:);
    P.dTheta = util_step(P.Theta, 180); P.dPhi = util_step(P.Phi, 360);
    P.Revision = P.Revision + 1;
    function E = field(E)                                                 % power + unit phasor (B.4)
        a = abs(E); u = E./max(a, realmin); u(a == 0) = 0;
        pw = lin(a.^2); ph = complex(lin(real(u)), lin(imag(u)));
        E = sqrt(max(pw, 0)).*ph./max(abs(ph), realmin);
    end
end

function G = geo_build(P)
%GEO_BUILD Separable solid-angle weights (I2): ΔΩ(i,j) = wθ(i)·Δφ, wθ(i) = cos θᵢ⁻ − cos θᵢ⁺ with cells clamped to the
%   poles. Σ wθ telescopes to cos θ₁⁻ − cos θₙ⁺ (= 2 on a full θ axis); Σ Δφ = 2π when periodic ⇒ Σ ΔΩ = 4π exactly.
    lo = max(P.Theta - P.dTheta/2, 0); hi = min(P.Theta + P.dTheta/2, 180);
    G.wTheta = cosd(lo) - cosd(hi);
    G.dPhi = deg2rad(P.dPhi);
    G.PhiPeriodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
    G.dOmega = G.wTheta*(G.dPhi*ones(1, numel(P.Phi)));
    G.Omega = sum(G.dOmega, 'all');
    G.IsFullSphere = G.PhiPeriodic && abs(sum(G.wTheta) - 2) < 1e-6;
end

function M = geo_displayMap(P, G, view)
%GEO_DISPLAYMAP Display convention as a column permutation plus axis labels — the data never move (I8).
    n = numel(P.Phi); j0 = find(P.Phi >= 180, 1); perm = 1:n;
    if view.SignedPhi && ~isempty(j0), perm = [j0:n, 1:j0-1]; end
    M.ColIdx = perm; if G.PhiPeriodic, M.ColIdx(end+1) = perm(1); end     % closing column for display only
    M.PhiAxis = P.Phi(perm);
    if view.SignedPhi, M.PhiAxis(M.PhiAxis >= 180) = M.PhiAxis(M.PhiAxis >= 180) - 360; end
    if G.PhiPeriodic, M.PhiAxis(end+1) = M.PhiAxis(1) + 360; end
    if view.Elevation, M.ThetaAxis = 90 - P.Theta; M.ThetaDir = 'normal';  M.ThetaLabel = 'Elevation (°)';
    else,              M.ThetaAxis = P.Theta;      M.ThetaDir = 'reverse'; M.ThetaLabel = 'θ (°)'; end
    M.Key = sprintf('%d|%d|%d|%d', view.SignedPhi, view.Elevation, numel(P.Theta), n);
end

function cut = geo_cut(P, C, cutType, fixed)
%GEO_CUT One full-circle cut through the level stack C (nθ×nφ×nTraces) by slicing — no copy of the pattern.
%   "Phi" cut: fixed θ, angle = φ.  "Theta" cut: fixed φ, angle = θ on the primary half-plane and 360−θ on the
%   opposite half-plane (φ+180°), so the cut closes through both poles whenever the source holds that half-plane.
    nT = size(C, 3);
    if cutType == "Phi"
        [~, i] = min(abs(P.Theta - fixed));
        cut = struct('angle', P.Phi(:), 'values', reshape(C(i, :, :), [], nT), 'theta', repmat(P.Theta(i), numel(P.Phi), 1), ...
                     'phi', P.Phi(:), 'fixed', P.Theta(i), 'symbol', 'θ', 'axis', 'φ', 'closed', false);
        cut.snapped = abs(cut.fixed - fixed) > 1e-9;
    else
        [~, j] = min(abs(util_wrap180(P.Phi - fixed)));
        [dOpp, jo] = min(abs(util_wrap180(P.Phi - (P.Phi(j) + 180))));
        angle = P.Theta(:); V = reshape(C(:, j, :), [], nT); th = P.Theta(:); ph = repmat(P.Phi(j), numel(th), 1);
        closed = dOpp < 1e-9 && jo ~= j;
        if closed
            keep = flipud(find(P.Theta > 0 & P.Theta < 180));            % pole samples already sit on the primary half
            angle = [angle; 360 - P.Theta(keep)]; V = [V; reshape(C(keep, jo, :), [], nT)];
            th = [th; P.Theta(keep)]; ph = [ph; repmat(P.Phi(jo), numel(keep), 1)];
        end
        cut = struct('angle', angle, 'values', V, 'theta', th, 'phi', ph, 'fixed', P.Phi(j), 'symbol', 'φ', 'axis', 'θ', 'closed', closed);
        cut.snapped = abs(util_wrap180(cut.fixed - fixed)) > 1e-9;
    end
end

%% ---------------------------------------------------------------------- Derivation, metrics, polarisation

function D = pat_derive(P, G, prm, K, A6)
%PAT_DERIVE Every level column and every base fact of one pattern at the given parameters (I3, I4).
%   Loss L scales the incident field by 10^(L/20): every level column shifts by L; peak index, boresight, planes,
%   HPBW, directivity and F/B are shift-invariant; efficiency scales by 10^(L/10). Nothing downstream adds L.
    pairs = struct('Linear', ["E_TH" "E_PH"], 'Circular', ["E_RCP" "E_LCP"]);
    if P.IsGainOnly
        Cols = struct(); names = fieldnames(P.G);
        for k = 1:numel(names)
            C = P.G.(names{k});
            if any(util_colKind(names{k}) == ["gain", "link"]), C = C + prm.L; end
            Cols.(names{k}) = C;
        end
        isGain = cellfun(@(nm) util_colKind(nm) == "gain", names);
        gainName = names{max([find(isGain, 1), 1])};
        Peak = met_peak(Cols.(gainName), G.PhiPeriodic, K.PeakExcessDB, P.Theta);
        Pol = struct('Label', "n/a", 'Pairs', pairs);
    else
        s = 10^(prm.L/20); Eth = P.Eth*s; Eph = P.Eph*s;
        Er = pol_circular(Eth, Eph, 1); El = pol_circular(Eth, Eph, 2);
        Cols.E_Total_dB = util_dB(abs(Eth).^2 + abs(Eph).^2, K.FloorDB);
        Cols.E_TH_dB  = util_dB(abs(Eth).^2, K.FloorDB); Cols.E_PH_dB  = util_dB(abs(Eph).^2, K.FloorDB);
        Cols.E_RCP_dB = util_dB(abs(Er).^2, K.FloorDB);  Cols.E_LCP_dB = util_dB(abs(El).^2, K.FloorDB);
        [Cols.AR_dB, ra, isLinear] = pol_signedAR(Er, El, K.LinearAR_dB);
        gainName = 'E_Total_dB';
        Peak = met_peak(Cols.E_Total_dB, G.PhiPeriodic, K.PeakExcessDB, P.Theta);
        % polarisation pairs and label from Ω-weighted main-beam power (samples within 3 dB of the total-gain peak)
        beam = isfinite(Cols.E_Total_dB) & Cols.E_Total_dB >= Peak.value - 3;
        mp = @(E) sum(abs(E(beam)).^2.*G.dOmega(beam));
        pw = [mp(Eth), mp(Eph), mp(Er), mp(El)];
        if pw(2) > pw(1), pairs.Linear = fliplr(pairs.Linear); end
        if pw(4) > pw(3), pairs.Circular = fliplr(pairs.Circular); end
        if max(pw(3:4)) > max(pw(1:2)), label = "Circular (" + replace(pairs.Circular(1), ["E_RCP" "E_LCP"], ["RHCP" "LHCP"]) + ")";
        elseif pw(1) >= pw(2),           label = "Linear (Vertical)";
        else,                            label = "Linear (Horizontal)"; end
        Pol = struct('Label', label, 'Pairs', pairs);
        rw = pol_rxRatio(prm.RxMode, prm.RxAR_dB, pairs.Circular(1) == "E_RCP");
        Cols.PLF_dB = util_dB(pol_plf(ra, isLinear, rw), K.FloorDB);
        Cols.Gain_PolCorrected_dB = Cols.E_Total_dB + Cols.PLF_dB;
        if P.Meta.Unit == "dBi"                                           % link columns exist only for calibrated gain (I9)
            Cols.EIRP_dBW   = Cols.E_Total_dB + prm.Pt_dBW;
            Cols.PFD_dBWm2  = Cols.EIRP_dBW - 10*log10(4*pi*prm.R_m^2);
            Cols.E_RMS_dBVm = Cols.PFD_dBWm2 + 10*log10(120*pi);
        end
        Cols.Phase_TH_deg = rad2deg(angle(Eth)); Cols.Phase_PH_deg = rad2deg(angle(Eph));
    end
    D = struct('Cols', Cols, 'GainName', gainName, 'Peak', Peak, 'Pol', Pol);
    D.Boresight = met_boresight(P, G, Cols.(gainName), K.ConeHalfAngleDeg, A6);
    D.Planes = met_planes(D.Boresight, A6);
    D.Metrics = met_metrics(P, G, Cols, gainName, Peak, D.Planes);
end

function K = met_peak(C, periodic, excessDB, thetaAxis)
%MET_PEAK Spatial-isolation peak policy (I5): a sample is a spike iff it exceeds every grid neighbour by more than
%   excessDB (4-neighbours; φ wraps when periodic; pole rows see the adjacent ring). Effective peak = highest non-spike.
    [n, m] = size(C); nb = -inf(n, m);
    if n > 1, nb(2:n, :) = max(nb(2:n, :), C(1:n-1, :)); nb(1:n-1, :) = max(nb(1:n-1, :), C(2:n, :)); end
    if m > 1
        if periodic, L = circshift(C, 1, 2); R = circshift(C, -1, 2);
        else,        L = [-inf(n, 1), C(:, 1:m-1)]; R = [C(:, 2:m), -inf(n, 1)]; end
        nb = max(nb, max(L, R));
    end
    if n > 1 && nargin >= 4
        if thetaAxis(1) == 0,     nb(1, :) = max(C(2, :), [], 'all'); end
        if thetaAxis(end) == 180, nb(n, :) = max(C(n-1, :), [], 'all'); end
    end
    K.spike = isfinite(C) & (C - nb > excessDB);
    [K.rawValue, K.rawIndex] = max(C(:));
    cand = C; cand(K.spike) = -Inf;
    [K.value, K.index] = max(cand(:));
    K.wasAdjusted = K.index ~= K.rawIndex; K.spikeCount = nnz(K.spike);
    [K.row, K.col] = ind2sub([n m], K.index);
end

function idx = met_boresight(P, G, Gt, halfAngle, A6)
%MET_BORESIGHT Principal axis whose ±halfAngle cone holds the most Ω-weighted radiated power (total gain).
    lin = 10.^(Gt/10).*G.dOmega; lin(~isfinite(lin)) = 0; e = zeros(1, 6);
    for k = 1:6, e(k) = sum(lin(cov_coneMask(P, A6.theta(k), A6.phi(k), halfAngle)), 'all'); end
    [~, idx] = max(e);
end

function Pl = met_planes(idx, A6)
%MET_PLANES Principal-axis rule (§16-6): E = θ-cut at the axis φ; H = φ-cut at θ = 90 for equatorial axes, else
%   θ-cut at φ_axis + 90°.
    thA = A6.theta(idx); phA = A6.phi(idx);
    Pl.E = struct('CutType', "Theta", 'Fixed', phA);
    if thA == 90, Pl.H = struct('CutType', "Phi", 'Fixed', 90);
    else,         Pl.H = struct('CutType', "Theta", 'Fixed', mod(phA + 90, 360)); end
end

function M = met_metrics(P, G, Cols, gainName, Peak, Pl)
%MET_METRICS Scalar metrics on total gain (I4); efficiency and F/B only when honest (I9).
    Gt = Cols.(gainName); lin = 10.^(Gt/10); lin(~isfinite(lin)) = 0;
    Prad = sum(lin.*G.dOmega, 'all');
    M.PeakGain_dB = Peak.value; M.PeakTheta_deg = P.Theta(Peak.row); M.PeakPhi_deg = P.Phi(Peak.col);
    M.PeakDirectivity_dB = Peak.value - 10*log10(Prad/G.Omega);
    M.Efficiency_pct = NaN; M.FrontBack_dB = NaN;
    if G.IsFullSphere
        if P.Meta.Unit == "dBi", M.Efficiency_pct = 100*Prad/(4*pi); end
        [~, ib] = min(abs(P.Theta - (180 - M.PeakTheta_deg)));
        [~, jb] = min(abs(util_wrap180(P.Phi - (M.PeakPhi_deg + 180))));
        M.FrontBack_dB = Peak.value - Gt(ib, jb);
    end
    ce = geo_cut(P, Gt, Pl.E.CutType, Pl.E.Fixed); M.HPBW_EPlane_deg = met_hpbw(ce.angle, ce.values);
    ch = geo_cut(P, Gt, Pl.H.CutType, Pl.H.Fixed); M.HPBW_HPlane_deg = met_hpbw(ch.angle, ch.values);
    M.AxialRatioAtPeak_dB = NaN;
    if isfield(Cols, 'AR_dB'), M.AxialRatioAtPeak_dB = Cols.AR_dB(Peak.index); end
end

function [bw, lo, hi] = met_hpbw(angleDeg, gainDB)
%MET_HPBW Half-power beamwidth of one circular cut: walk from the cut peak both ways until the level drops below
%   −3 dB, then interpolate the two crossings linearly. NaN when the cut never drops (omni) or is too short.
    [bw, lo, hi] = deal(NaN);
    ok = isfinite(angleDeg) & isfinite(gainDB); a = angleDeg(ok); g = gainDB(ok); n = numel(g);
    if n < 3, return; end
    [gp, ip] = max(g); rel = g - gp;
    nxt = @(i, d) mod(i - 1 + d, n) + 1;
    il = ip; while rel(nxt(il, -1)) >= -3 && nxt(il, -1) ~= ip, il = nxt(il, -1); end
    ir = ip; while rel(nxt(ir, +1)) >= -3 && nxt(ir, +1) ~= ip, ir = nxt(ir, +1); end
    if rel(nxt(il, -1)) >= -3 || rel(nxt(ir, +1)) >= -3, return; end
    rel2 = @(x) util_wrap180(x - a(ip));                                  % angles relative to the peak, in (−180, 180]
    aL = rel2(a(il)); aL0 = rel2(a(nxt(il, -1))); if aL0 > aL, aL0 = aL0 - 360; end
    aR = rel2(a(ir)); aR0 = rel2(a(nxt(ir, +1))); if aR0 < aR, aR0 = aR0 + 360; end
    xl = aL + (aL0 - aL)*(-3 - rel(il))/(rel(nxt(il, -1)) - rel(il));
    xr = aR + (aR0 - aR)*(-3 - rel(ir))/(rel(nxt(ir, +1)) - rel(ir));
    bw = xr - xl; lo = a(ip) + xl; hi = a(ip) + xr;
end

function E = pol_circular(Eth, Eph, which)
%POL_CIRCULAR RHCP (which = 1) / LHCP (which = 2) component of E = Eθ θ̂ + Eφ φ̂ (I10, B.5).
%   Convention e^{+jωt}, (θ̂, φ̂, r̂) right-handed: ê_R = (θ̂ − jφ̂)/√2, E_R = E·ê_R* = (Eθ + jEφ)/√2, E_L = (Eθ − jEφ)/√2.
    if which == 1, E = (Eth + 1i*Eph)/sqrt(2); else, E = (Eth - 1i*Eph)/sqrt(2); end
end

function [Eth, Eph] = pol_fromCircular(Er, El)
%POL_FROMCIRCULAR Inverse of pol_circular (OUT / CUT ICOMP = 2 / Excel RHCP-LHCP / generic rcp-lcp sources).
    Eth = (Er + El)/sqrt(2); Eph = (Er - El)/(1i*sqrt(2));
end

function [AR, ra, isLinear] = pol_signedAR(Er, El, linearFloor)
%POL_SIGNEDAR Signed axial ratio in dB (+ RHCP sense, − LHCP sense) and the signed linear ratio for the PLF.
%   Numerically equal circular components are the linear limit: AR shown at linearFloor, ra flagged (§16-2).
    r = abs(Er); l = abs(El); d = r - l;
    isLinear = isfinite(d) & abs(d) <= 4*eps(r + l);
    arLin = (r + l)./max(abs(d), realmin);
    ra = sign(d).*arLin;
    AR = sign(d).*20.*log10(arLin);
    AR(isLinear) = linearFloor; AR(~isfinite(d)) = NaN;
end

function rw = pol_rxRatio(mode, ar_dB, antennaLeadsRHCP)
%POL_RXRATIO Signed axial ratio of the incident wave (+RHCP / −LHCP sense; Inf = linear). Auto follows the antenna.
    switch string(mode)
        case "RHCP",  rw = 10^(ar_dB/20);
        case "LHCP",  rw = -10^(ar_dB/20);
        case "Auto",  rw = (2*antennaLeadsRHCP - 1)*10^(ar_dB/20);
        otherwise,    rw = Inf;
    end
end

function plf = pol_plf(ra, isLinear, rw)
%POL_PLF Polarisation loss factor (linear, 0..1) between antenna (signed AR ra) and wave (rw), major axes aligned:
%   PLF = ½ + [4·ra·rw + (ra² − 1)(rw² − 1)] / [2(ra² + 1)(rw² + 1)]
%   linear wave (rw → ∞):    PLF = ½ + (ra² − 1)/(2(ra² + 1));   linear antenna (ra → ∞): PLF = ½ + (rw² − 1)/(2(rw² + 1)) (B.6)
    ra2 = ra.^2;
    if isinf(rw)
        plf = 0.5 + (ra2 - 1)./(2*(ra2 + 1)); plf(isLinear) = 1;
    else
        rw2 = rw^2;
        plf = 0.5 + (4*ra*rw + (ra2 - 1)*(rw2 - 1))./(2*(ra2 + 1)*(rw2 + 1));
        plf(isLinear) = 0.5 + (rw2 - 1)/(2*(rw2 + 1));
    end
    plf(~isfinite(ra) & ~isLinear) = NaN;
    plf = min(max(plf, 0), 1);
end

%% ---------------------------------------------------------------------- Coverage kernels (I7)

function d = cov_dist(C, dOmega, mask)
%COV_DIST Ω-weighted level distribution of C over a region: Coverage(T) = 100·Ω{C > T}/Ω_R, strict ">".
%   Sorted distinct levels g₁ < … < gₙ with weights ωₖ and tail sums S(k) = Σ_{m≥k} ωₘ ⇒ Ω{C > T} = S(k_T),
%   k_T = first k with gₖ > T. O(N log N) once; every evaluation is a bin search (threshold-count independent).
    v = mask & isfinite(C);
    d = struct('g', zeros(0, 1), 'w', zeros(0, 1), 'S', zeros(0, 1), 'Omega', 0);
    if ~any(v(:)), return; end
    [d.g, ~, bin] = unique(C(v));
    d.w = accumarray(bin, dOmega(v)); d.S = flipud(cumsum(flipud(d.w))); d.Omega = sum(d.w);
end

function cov = cov_eval(d, T)
%COV_EVAL Coverage(T) in % for finite thresholds T (exact at ties, no interpolation).
    cov = zeros(size(T)); ok = isfinite(T); cov(~ok) = NaN;
    if isempty(d.g) || d.Omega <= 0, return; end
    k = discretize(T(ok), [-inf; d.g; inf]);                              % bin k ⇔ g(k−1) ≤ T < g(k): first level above T
    S = [d.S; 0];
    cov(ok) = 100*S(k)/d.Omega;
end

function T = cov_inverse(d, c)
%COV_INVERSE sup{T : Coverage(T) ≥ c %} = level g_k* with k* the last level whose tail sum S ≥ c·Ω/100 (NaN if none).
    T = nan(size(c));
    if isempty(d.g), return; end
    for q = 1:numel(c)
        k = nnz(d.S >= c(q)*d.Omega/100);
        if k >= 1, T(q) = d.g(k); end
    end
end

function m = cov_coneMask(P, thC, phC, alphaDeg)
%COV_CONEMASK (i,j) ∈ cone ⇔ cos γ ≥ cos α with cos γ = cos θᵢ cos θc + sin θᵢ sin θc cos(φⱼ − φc) (law of cosines).
    m = cosd(P.Theta(:))*cosd(thC) + sind(P.Theta(:))*sind(thC).*cosd(P.Phi(:).' - phC) >= cosd(alphaDeg) - 1e-12;
end

function T = cov_thresholds(tMin, tMax, step)
%COV_THRESHOLDS Threshold vector by counting (never by accumulation) so 501 requested values are 501 values.
    if ~(step > 0) || tMax < tMin, T = tMin; return; end
    n = round((tMax - tMin)/step);
    T = tMin + (0:n).'*step;
    if T(end) > tMax + 1e-9, T(end) = []; end
end

function y = cov_at(job, T)
%COV_AT Coverage of one job at thresholds T: exact from its distribution, linear on the curve for loaded files.
    if ~isempty(job.dist) && ~isempty(job.dist.g), y = cov_eval(job.dist, T);
    elseif numel(job.T) >= 2,                     y = interp1(job.T, job.cov, T, 'linear');
    else,                                         y = nan(size(T)); end
end

function x = cov_thrAt(job, c)
%COV_THRAT Threshold of one job at coverage c %: exact inverse, or the plateau-upper inverse of the loaded curve.
    if ~isempty(job.dist) && ~isempty(job.dist.g), x = cov_inverse(job.dist, c); return; end
    [cu, iu] = unique(job.cov, 'last'); x = NaN;
    if numel(cu) >= 2, x = interp1(cu, job.T(iu), c, 'linear'); end
end

%% ---------------------------------------------------------------------- Utilities

function k = util_colKind(name)
%UTIL_COLKIND Column semantics from its name: "ar" | "phase" | "plf" | "link" | "gain".
    s = regexprep(lower(string(name)), '[^a-z0-9]', '');
    if s == "ar" || startsWith(s, "ardb") || startsWith(s, "axialratio"), k = "ar";
    elseif contains(s, "phase"),                                           k = "phase";
    elseif startsWith(s, "plf") || contains(s, "polloss"),                 k = "plf";
    elseif contains(s, "eirp") || contains(s, "pfd") || contains(s, "erms"), k = "link";
    else,                                                                  k = "gain"; end
end

function s = util_colLabel(name)
    map = {'E_Total_dB', 'Total Gain'; 'E_TH_dB', 'Eθ Gain'; 'E_PH_dB', 'Eφ Gain'; 'E_RCP_dB', 'RHCP Gain'; 'E_LCP_dB', 'LHCP Gain'; ...
           'AR_dB', 'Axial Ratio (signed)'; 'PLF_dB', 'Polarization Loss Factor'; 'Gain_PolCorrected_dB', 'Polarized Gain'; ...
           'EIRP_dBW', 'EIRP (dBW)'; 'PFD_dBWm2', 'Power Flux Density (dBW/m²)'; 'E_RMS_dBVm', 'E-field RMS (dBV/m)'; ...
           'Phase_TH_deg', 'Eθ Phase (°)'; 'Phase_PH_deg', 'Eφ Phase (°)'};
    i = find(strcmp(map(:, 1), char(name)), 1);
    if isempty(i), s = strrep(char(name), '_', ' '); else, s = map{i, 2}; end
end

function s = util_fmtNumber(v, prec)
%UTIL_FMTNUMBER Compact (≤ 2 decimals, no trailing zeros, never "-0") or fixed-precision text; 'n/a' when not finite.
    if ~(isscalar(v) && isnumeric(v) && isfinite(v)), s = 'n/a'; return; end
    if nargin < 2, s = regexprep(regexprep(sprintf('%.2f', v), '(\.\d*?)0+$', '$1'), '\.$', '');
    else,          s = sprintf('%.*f', prec, v); end
    if str2double(s) == 0, s = regexprep(s, '^-', ''); end
end

function r = util_presetRange(peak)
    if ~isfinite(peak), r = [-50 0]; return; end
    hi = 5*ceil(peak/5); r = [hi - 50, hi];
end

function t = util_ticks(lims, step)
    if ~(isfinite(step) && step > 0 && lims(2) > lims(1)), t = []; return; end
    t = unique([lims(1), ceil(lims(1)/step)*step:step:floor(lims(2)/step)*step, lims(2)]);
    if numel(t) > 60, t = linspace(lims(1), lims(2), 11); end
end

function r = util_polarRadius(C, lims)
    r = (C - lims(1))/max(lims(2) - lims(1), eps); r = min(max(r, 0), 1); r(~isfinite(r)) = 0;
end

function x = util_dB(power, floorDB)
    x = 10*log10(max(power, realmin)); x(power <= 0) = floorDB;
end

function x = util_iif(cond, a, b)
    if cond, x = a; else, x = b; end
end

function y = util_wrap180(x)
    y = mod(x + 180, 360) - 180;
end

function s = util_step(x, fallback)
    if numel(x) < 2, s = fallback; else, s = median(diff(x(:))); end
end

function util_assertUniform(x, name, tol)
    d = diff(x(:));
    if numel(d) >= 2 && (max(d) - min(d)) > tol
        error('APAT:NonUniformGrid', 'The %s axis is not uniform: steps range %.6g°..%.6g° (APAT requires uniform grids).', name, min(d), max(d));
    end
end

function M = util_place(cells, vals, n, m)
    M = nan(n*m, 1); M(cells) = vals; M = reshape(M, n, m);
end

function c = util_cutCanonical(cutType, value, elevation)
%UTIL_CUTCANONICAL Displayed fixed angle → canonical (fixed φ in [0,360); fixed θ polar).
    if cutType == "Theta", c = mod(value, 360); elseif elevation, c = 90 - value; else, c = value; end
end

function v = util_cutDisplay(cutType, canon, elevation, signedPhi)
    if cutType == "Theta", v = util_iif(signedPhi, util_wrap180(canon), mod(canon, 360));
    else,                  v = util_iif(elevation, 90 - canon, canon); end
end

function s = util_planeText(pl)
    s = sprintf('%s-cut at %s = %g°', util_iif(pl.CutType == "Theta", 'θ', 'φ'), util_iif(pl.CutType == "Theta", 'φ', 'θ'), pl.Fixed);
end

function T = util_longTable(P, D)
%UTIL_LONGTABLE Canonical long table (Theta, Phi, every derived column) — built only when exported.
    [PH, TH] = meshgrid(P.Phi, P.Theta);
    T = table(TH(:), PH(:), 'VariableNames', {'Theta', 'Phi'});
    for nm = string(fieldnames(D.Cols)).', C = D.Cols.(nm); T.(nm) = C(:); end
end
%% ---------------------------------------------------------------------- I/O: readers return io_source(...)

function S = io_read(path)
%IO_READ Dispatch on extension. Every reader returns Source = {Raw, Blocks{f}, Freqs, Meta}; nothing else is parsed.
    [~, ~, ext] = fileparts(path); ext = lower(ext);
    switch ext
        case '.uan',            S = io_uan(path);
        case '.cut',            S = io_cut(path);
        case '.ffd',            S = io_ffd(path);
        case '.ffe',            S = io_ffe(path);
        case '.ffs',            S = io_ffs(path);
        case {'.xlsx', '.xls'}, S = io_xlsx(path);
        otherwise,              S = io_generic(path, ext);
    end
    S.Meta.File = string(path);
end

function S = io_source(blocks, freqs, raw, meta)
    if isempty(freqs) || all(~isfinite(freqs)), freqs = NaN(1, numel(blocks)); end
    S = struct('Raw', raw, 'Blocks', {blocks}, 'Freqs', freqs(:).', 'Meta', meta);
end

function meta = io_meta(format, unit, varargin)
%IO_META Source disclosure. The unit class is a static property of the format (§16-4); decisions go to Notes.
    meta = struct('Format', string(format), 'Unit', string(unit), 'UnitLabel', "dBi", 'ThetaConvention', "polar", ...
                  'IsGainOnly', false, 'Notes', strings(1, 0), 'File', "");
    if meta.Unit ~= "dBi", meta.UnitLabel = "dB (rel. field)"; end
    for k = 1:2:numel(varargin), meta.(varargin{k}) = varargin{k+1}; end
end

function L = io_lines(path)
    L = strtrim(string(splitlines(fileread(path))));
end

function [M, isNum] = io_numeric(L)
%IO_NUMERIC Numeric rows of the text lines L: the modal column count wins, everything else is ignored.
    R = regexprep(regexprep(L(:), '[,;\t]+', ' '), '\s+', ' ');
    isNum = ~cellfun('isempty', regexp(R, '^[-+]?[\d.]', 'once')) & ~cellfun('isempty', regexp(R, '^[-+.\deE ]+$', 'once'));
    M = zeros(0, 0);
    if ~any(isNum), return; end
    cnt = count(R(isNum), ' ') + 1; nCol = mode(cnt);
    idx = find(isNum); isNum(idx(cnt ~= nCol)) = false;
    M = reshape(sscanf(char(join(R(isNum), newline)), '%f'), nCol, []).';
end

function v = io_headerValue(L, key)
%IO_HEADERVALUE First token following KEY on any line ("" when absent), case-insensitive.
    t = regexp(L(:), ['^' key '\s+(\S+)'], 'tokens', 'once', 'ignorecase');
    hit = find(~cellfun('isempty', t), 1);
    if isempty(hit), v = ""; else, v = string(t{hit}{1}); end
end

function spec = io_spec(kind, basis, cols, phaseUnit, magUnit)
    spec = struct('kind', string(kind), 'basis', string(basis), 'cols', cols, 'phaseUnit', string(phaseUnit), 'magUnit', string(magUnit));
end

function [Eth, Eph] = io_fields(M, spec)
%IO_FIELDS Four value columns → complex (Eθ, Eφ). kind: reim | magphase; basis: linear | circular.
    c = M(:, spec.cols);
    if spec.kind == "reim"
        A = complex(c(:, 1), c(:, 2)); B = complex(c(:, 3), c(:, 4));
    else
        ph = c(:, [2 4]); if spec.phaseUnit == "rad", ph = rad2deg(ph); end
        mag = c(:, [1 3]); if spec.magUnit == "dB", mag = 10.^(mag/20); end
        A = mag(:, 1).*exp(1i*deg2rad(ph(:, 1))); B = mag(:, 2).*exp(1i*deg2rad(ph(:, 2)));
    end
    if spec.basis == "circular", [Eth, Eph] = pol_fromCircular(A, B); else, Eth = A; Eph = B; end
end

function S = io_uan(path)
%IO_UAN MVG/Satimo UAN: key/value header, rows "theta phi mag1 phase1 mag2 phase2" (magnitude dB = dBi gain).
    L = io_lines(path);
    mag = lower(io_headerValue(L, 'magnitude')); if mag == "", mag = "db"; end
    if ~startsWith(mag, "db"), error('APAT:UnsupportedUAN', 'UAN magnitude "%s" is not supported (dB expected).', mag); end
    pol = lower(io_headerValue(L, 'polarization'));
    basis = "linear"; if contains(pol, ["circ", "rhcp", "rcp"]), basis = "circular"; end
    phaseUnit = "deg"; if startsWith(lower(io_headerValue(L, 'phase')), "rad"), phaseUnit = "rad"; end
    freq = str2double(io_headerValue(L, 'frequency'));
    if isfinite(freq) && freq < 1e4, freq = freq*1e9; elseif isfinite(freq) && freq < 1e7, freq = freq*1e6; end
    M = io_numeric(L);
    if size(M, 2) < 6, error('APAT:UnsupportedUAN', 'UAN data rows need six columns (theta phi mag phase mag phase).'); end
    [Eth, Eph] = io_fields(M, io_spec("magphase", basis, 3:6, phaseUnit, "dB"));
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
%IO_FFD HFSS far-field data: "θs θe nθ", "φs φe nφ", "Frequency N" + N values, then blocks of Re/Im Eθ, Re/Im Eφ.
    L = io_lines(path);
    a1 = sscanf(char(L(1)), '%f'); a2 = sscanf(char(L(2)), '%f');
    if numel(a1) < 3 || numel(a2) < 3, error('APAT:UnsupportedFFD', 'FFD must start with "θ_start θ_stop nθ" and "φ_start φ_stop nφ".'); end
    th = linspace(a1(1), a1(2), a1(3)).'; ph = linspace(a2(1), a2(2), a2(3)).'; N = numel(th)*numel(ph);
    t = regexp(L(:), '^Frequency\s+([-+\d.eE]+)', 'tokens', 'once', 'ignorecase');
    fq = cellfun(@(x) str2double(x{1}), t(~cellfun('isempty', t)));
    if numel(fq) >= 2, fq = fq(2:end); end                                % the first "Frequency N" line is the count
    M = io_numeric(L(3:end));
    if size(M, 2) < 4 || mod(size(M, 1), N) ~= 0, error('APAT:UnsupportedFFD', 'FFD rows (%d) do not match nθ×nφ = %d.', size(M, 1), N); end
    nB = size(M, 1)/N; blocks = cell(1, nB);
    TH = repelem(th, numel(ph)); PH = repmat(ph, numel(th), 1);           % θ outer, φ inner
    for b = 1:nB
        r = (b-1)*N + (1:N);
        blocks{b} = struct('Theta', TH, 'Phi', PH, 'Eth', complex(M(r, 1), M(r, 2)), 'Eph', complex(M(r, 3), M(r, 4)));
    end
    raw = array2table([TH, PH, M(1:N, 1:4)], 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
    meta = io_meta("HFSS far-field data (.ffd)", "dB");
    meta.Notes(end+1) = "row order assumed θ-outer / φ-inner; raw field values (not calibrated gain)";
    S = io_source(blocks, fq(1:min(nB, numel(fq))), raw, meta);
end

function S = io_ffe(path)
%IO_FFE FEKO far field: "#Frequency:" per block; rows θ φ Re(Eθ) Im(Eθ) Re(Eφ) Im(Eφ) [gain columns ignored, as in M7].
    L = io_lines(path);
    fIdx = find(startsWith(L, "#Frequency", 'IgnoreCase', true));
    if isempty(fIdx), fIdx = 1; freqs = NaN; else, freqs = arrayfun(@(k) str2double(regexprep(L(k), '^[^:]*:', '')), fIdx); end
    bounds = [fIdx(:); numel(L) + 1]; blocks = {}; keep = [];
    for b = 1:numel(fIdx)
        M = io_numeric(L(bounds(b):bounds(b+1)-1));
        if size(M, 2) < 6, continue; end
        blocks{end+1} = struct('Theta', M(:, 1), 'Phi', M(:, 2), 'Eth', complex(M(:, 3), M(:, 4)), 'Eph', complex(M(:, 5), M(:, 6))); %#ok<AGROW>
        keep(end+1) = b; %#ok<AGROW>
        if numel(keep) == 1, raw = array2table(M(:, 1:6), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}); end
    end
    if isempty(blocks), error('APAT:UnsupportedFFE', 'No six-column field block found in the FEKO file.'); end
    meta = io_meta("FEKO far field (.ffe)", "dB");
    meta.Notes(end+1) = "Re/Im E columns used; FEKO gain columns ignored (raw field levels)";
    S = io_source(blocks, freqs(keep), raw, meta);
end

function S = io_ffs(path)
%IO_FFS CST far-field source: power/frequency quadruples after "// Radiated/Accepted/Stimulated Power", rows φ θ Re/Im Eθ Re/Im Eφ.
    L = io_lines(path);
    pIdx = find(contains(L, "Radiated/Accepted/Stimulated Power", 'IgnoreCase', true));
    freqs = arrayfun(@(k) util_nth(sscanf(char(L(min(k+1, end))), '%f'), 4), pIdx);
    M = io_numeric(L);
    if size(M, 2) < 6, error('APAT:UnsupportedFFS', 'FFS data rows need six columns (phi theta Re/Im Eθ Re/Im Eφ).'); end
    nB = max(numel(freqs), 1); N = size(M, 1)/nB;
    if mod(N, 1) ~= 0, nB = 1; N = size(M, 1); end
    blocks = cell(1, nB);
    for b = 1:nB
        r = (b-1)*N + (1:N);
        blocks{b} = struct('Theta', M(r, 2), 'Phi', M(r, 1), 'Eth', complex(M(r, 3), M(r, 4)), 'Eph', complex(M(r, 5), M(r, 6)));
    end
    raw = array2table(M(1:N, 1:6), 'VariableNames', {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
    meta = io_meta("CST far-field source (.ffs)", "dB");
    meta.Notes(end+1) = "columns read as φ, θ, Re/Im Eθ, Re/Im Eφ (raw field levels)";
    S = io_source(blocks, freqs, raw, meta);
end

function S = io_xlsx(path)
%IO_XLSX Excel matrix templates: component sheets (Gain_dBi + Phase_degrees) with a C3-origin θ×φ matrix each.
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
    [PH, TH] = meshgrid(ph0, th0);
    M = [TH(:), PH(:), mats{1}(:), mats{2}(:), mats{3}(:), mats{4}(:)];
    [Eth, Eph] = io_fields(M, io_spec("magphase", basis, 3:6, "deg", "dB"));
    raw = array2table(M, 'VariableNames', [{'Theta', 'Phi'}, cellstr(need)]);
    meta = io_meta(fmt, "dBi");
    S = io_source({struct('Theta', M(:, 1), 'Phi', M(:, 2), 'Eth', Eth, 'Eph', Eph)}, io_xlsxFrequency(path, sheets(1)), raw, meta);
end

function [th, ph, data] = io_xlsxSheet(path, sheet)
%IO_XLSXSHEET One C3-origin matrix: column axis in row 2 (C2→), row axis in column 2 (B3↓). θ is the axis reaching ≤ 180.
    C = readcell(path, 'Sheet', char(sheet));
    isnum = @(x) isnumeric(x) && isscalar(x);
    if size(C, 1) < 3 || size(C, 2) < 3, error('APAT:ExcelSheet', 'Sheet "%s" holds no C3-origin matrix.', sheet); end
    kc = find(cellfun(isnum, C(2, 3:end))); kr = find(cellfun(isnum, C(3:end, 2)));
    colAxis = cell2mat(C(2, 2 + kc)).'; rowAxis = cell2mat(C(2 + kr, 2));
    D = C(2 + kr, 2 + kc); D(~cellfun(isnum, D)) = {NaN}; data = cell2mat(D);
    th = rowAxis; ph = colAxis;
    if max(rowAxis) > 180 + 1e-9 && max(colAxis) <= 180 + 1e-9, th = colAxis; ph = rowAxis; data = data.'; end
end

function f = io_xlsxFrequency(path, sheet)
%IO_XLSXFREQUENCY The one summary-sheet fact APAT uses: the "Freq (MHz)" cell (NaN when absent).
    f = NaN;
    C = readcell(path, 'Sheet', char(sheet), 'Range', 'A1:H70');
    for r = 1:size(C, 1)
        for c = 1:size(C, 2)
            x = C{r, c};
            if (ischar(x) || isstring(x)) && contains(lower(string(x)), "freq") && contains(lower(string(x)), "mhz")
                for c2 = c+1:size(C, 2)
                    if isnumeric(C{r, c2}) && isscalar(C{r, c2}) && isfinite(C{r, c2}), f = C{r, c2}*1e6; return; end
                end
            end
        end
    end
end

function S = io_generic(path, ext)
%IO_GENERIC Delimited text (csv/txt/dat/fz/out): header names decide axis roles and value layout; decisions are noted.
    L = io_lines(path);
    [M, isNum] = io_numeric(L);
    if isempty(M) || size(M, 2) < 2, error('APAT:UnsupportedFile', 'No numeric table found in "%s".', path); end
    first = find(isNum, 1); hdr = strings(1, 0);
    if first > 1
        tok = strsplit(char(L(first-1)), {',', ';', sprintf('\t'), ' '}); tok = tok(~cellfun('isempty', tok));
        if numel(tok) == size(M, 2), hdr = string(tok); end
    end
    names = lower(hdr); nCol = size(M, 2); notes = strings(1, 0);
    if (nCol >= 2 && any(contains(names, ["cov", "thresh", "ccdf"]))) || (nCol == 2 && isempty(hdr))
        error('APAT:CoverageFile', 'This file is a coverage-results table: load it from the Coverage tab ("Load results…").');
    end
    iTh = find(startsWith(names, ["theta", "th", "el"]) & ~startsWith(names, "thr"), 1);
    iPh = find(startsWith(names, ["phi", "ph", "az"]) & ~startsWith(names, ["pha", "phase"]), 1);
    thetaConv = "polar";
    if isempty(iTh) || isempty(iPh)
        iTh = 1; iPh = 2; span = max(M(:, 1:2)) - min(M(:, 1:2));
        if span(1) > 180 + 1e-9 && span(2) <= 180 + 1e-9, iTh = 2; iPh = 1; notes(end+1) = "axis order φ,θ decided by column span";
        else, notes(end+1) = "axis order θ,φ assumed (columns 1–2)"; end
    elseif startsWith(names(iTh), "el")
        thetaConv = "elevation"; notes(end+1) = "θ column is elevation (header)";
    end
    if thetaConv == "polar" && min(M(:, iTh)) < -1e-9 && max(M(:, iTh)) <= 90 + 1e-9
        thetaConv = "elevation"; notes(end+1) = "θ range [-90°, 90°] read as elevation";
    end
    M = M(isfinite(M(:, iTh)) & isfinite(M(:, iPh)), :);
    vals = setdiff(1:nCol, [iTh iPh], 'stable'); vn = strings(1, 0); if ~isempty(hdr), vn = names(vals); end
    looksField = any(startsWith(vn, ["re", "im"])) || any(contains(vn, ["real", "imag"])) || ...
                 (any(contains(vn, ["mag", "amp"])) && any(contains(vn, "pha")));
    isField = numel(vals) == 4 && (isempty(hdr) || looksField);
    if isField
        kind = "reim"; if any(contains(vn, ["mag", "amp"])) && any(contains(vn, "pha")), kind = "magphase"; end
        if isempty(hdr)
            v = M(:, vals);
            if all(abs(v(:, [2 4])) <= 360, 'all') && any(v(:, [1 3]) < -20, 'all'), kind = "magphase"; notes(end+1) = "mag/phase layout decided by value ranges"; end
        end
        magUnit = "dB"; if kind == "magphase" && any(contains(vn, ["lin", "v/m"])), magUnit = "lin"; end
        basis = "linear"; if any(contains(vn, ["rhcp", "lhcp", "rcp", "lcp"])) || strcmp(ext, '.out'), basis = "circular"; end
        unit = "dB"; if kind == "magphase" && magUnit == "dB" && any(contains(vn, "dbi")), unit = "dBi"; end
        [Eth, Eph] = io_fields(M, io_spec(kind, basis, vals, "deg", magUnit));
        block = struct('Theta', M(:, iTh), 'Phi', M(:, iPh), 'Eth', Eth, 'Eph', Eph);
        meta = io_meta("Six-column field table (" + ext + ")", unit, 'ThetaConvention', thetaConv);
        notes(end+1) = sprintf("values read as %s, %s basis", kind, basis);
    else
        G = struct();
        for k = 1:numel(vals)
            nm = "Col" + vals(k) + "_dB"; if ~isempty(hdr), nm = hdr(vals(k)); elseif k == 1, nm = "Gain_dB"; end
            G.(matlab.lang.makeValidName(char(nm))) = M(:, vals(k));
        end
        block = struct('Theta', M(:, iTh), 'Phi', M(:, iPh), 'G', G);
        meta = io_meta("Gain table (" + ext + ")", "dBi", 'ThetaConvention', thetaConv, 'IsGainOnly', true);
        notes(end+1) = "gain-only columns are taken as dBi";
    end
    rawNames = cellstr(compose('Col%d', 1:nCol)); if ~isempty(hdr), rawNames = cellstr(hdr); end
    raw = array2table(M, 'VariableNames', matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(rawNames)));
    meta.Notes = [meta.Notes, notes];
    S = io_source({block}, NaN, raw, meta);
end

function [T, curves, names] = io_coverageCSV(path)
%IO_COVERAGECSV Results table: first numeric column = thresholds, remaining numeric columns = coverage curves (%).
    tbl = readtable(path, 'VariableNamingRule', 'preserve');
    num = varfun(@isnumeric, tbl, 'OutputFormat', 'uniform'); tbl = tbl(:, num);
    if width(tbl) < 2, error('APAT:CoverageFile', 'A coverage results file needs a threshold column and at least one curve.'); end
    [T, o] = sort(tbl{:, 1}); curves = tbl{o, 2:end}; names = tbl.Properties.VariableNames(2:end);
end

function io_writeUAN(file, P, D)
%IO_WRITEUAN UAN export (dB magnitude / degree phase, θ-φ polarisation) of the derived columns at the current loss.
    fid = fopen(file, 'w'); c = onCleanup(@() fclose(fid)); 
    [PH, TH] = meshgrid(P.Phi, P.Theta);
    fprintf(fid, ['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                  'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.4f\nphase degrees\ndirection degrees\npolarization theta_phi\n'], ...
            P.Phi(1), P.Phi(end), P.dPhi, P.Theta(1), P.Theta(end), P.dTheta, D.Peak.value);
    if isfinite(P.Freq), fprintf(fid, 'frequency %.6g\n', P.Freq); end
    fprintf(fid, 'end_<parameters>\nbegin_<data>\n');
    rows = [TH(:), PH(:), D.Cols.E_TH_dB(:), D.Cols.Phase_TH_deg(:), D.Cols.E_PH_dB(:), D.Cols.Phase_PH_deg(:)];
    fprintf(fid, '%g %g %.4f %.3f %.4f %.3f\n', rows.');
    fprintf(fid, 'end_<data>\n');
end

function v = util_nth(x, k)
    if numel(x) >= k, v = x(k); else, v = NaN; end
end