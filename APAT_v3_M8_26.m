classdef APAT_v3_M8_26 < matlab.apps.AppBase %1873-lines
% APAT v3 M8 — Antenna Pattern Analyzer Tool (concise-architecture release).
%
% One file, four layers, strictly one-directional dataflow:
%
%   IO      readSource → src = struct(rawTbl, blocks, freqs, meta)          (local functions, UI-free)
%   MODEL   canonicalize → stdTbl (θ∈[0,180], φ∈[0,360] with one closing φ=360 seam)
%           computePattern / resampleCanonical → viewTbl (processed table at native or 1° step)
%           orientation / computeMetrics / coverageCCDF                    (local functions, UI-free)
%   VIEW    viewGrid / cutData / renderFull / plotCut / tables              (display conventions applied HERE only)
%   APP     callbacks, ranges, annotations, coverage workspace, lifecycle
%
% Design rules
%   • State tables always hold PHYSICAL angles; the φ-span / θ-span switches are pure presentation.
%   • All UI handles live in app.ui (built by buildUI); all state is an explicit named property.
%   • Every callback is wrapped by cb()/guard(): errors become dialogs, cancellation becomes a status line.
%   • Annotations (POB / HPBW) are tagged children of their axes: cla() releases them, syncTips() shows them.
%   • APAT_v3_M8.selfTest() exercises the model layer without a figure.

    properties (SetAccess = private)
        ui struct = struct()                       % every UI handle (see buildUI / buildMainTab / buildCoverageTab)
        isClosing logical = false
    end

    properties (Access = private)
        % ---- source & pipeline
        src struct = struct()                      % reader output: rawTbl, blocks, freqs, meta
        file struct = struct('path', '', 'folder', '', 'base', '', 'name', '')
        stdTbl table                               % canonical source of the selected block
        patTbl table                               % processed at native step (lazy cache, reset by refresh)
        viewTbl table                              % processed table currently displayed (physical angles)
        viewRev double = 0                         % increments whenever viewTbl changes
        info struct = struct()                     % computePattern summary: pol, pairs, peak
        peak struct = struct()                     % resolvePeak result of the selected component
        POB double = [NaN NaN NaN]                 % [gain_dB theta phi] of the selected component
        boresight double = 1                       % index into Axes6
        metrics struct = struct()                  % computeMetrics result (Total Gain)
        omega double = []                          % solid-angle weight per viewTbl row
        gridCache struct = struct()                % display grids per component (see viewGrid)
        rawShown logical = false
        % ---- explicit UI state (no hidden UserData flags)
        gainLim double = [-40 10]                  % shared colour scale of all non-AR components
        fullLim double = [-40 10]                  % colour scale currently applied to the full-pattern plots
        cutLim double = [-40 10]
        outMask logical = logical([])              % Results-table column filter
        autoCutBasis logical = true                % cut basis follows the detected polarization until edited
        keepOneDegree logical = false              % 1° step requested on the last (re)process
        defaults cell = {}                         % parameter control values captured at startup
        sticky string = ["" ""]                    % persistent status texts [main cov]
        % ---- coverage workspace
        covRunID double = 0
        covPreset string = ""                      % key (path|component|view) of the last automatic threshold preset
        covThrInit logical = false
        covXInit logical = false                   % coverage X-axis baseline established by the first result
        covSyncing logical = false
        % ---- lifecycle
        statusTimer = []
        opDialog = []
        perf = @(~) []                             % stage recorder (no-op when idle)
    end

    properties (Constant)
        Axes6 = struct('labels', {{'+Z','-Z','+X','-X','+Y','-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        HiddenOut = {'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'}
        PeakPct = 99.99                            % peak policy: percentile …
        PeakExcess = 6                             % … and maximum excess above it (dB)
        DbRange = [-250 100]                       % absolute dB domain of every range control
        Version = '3.0-M8'
        ProfileToBase = false                      % true → stage timings are exported to the base workspace
    end

    %% ------------------------------------------------------------------ lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_26
            app.buildUI();
            registerApp(app, app.ui.fig);
            runStartupFcn(app, @startup);
            if nargout == 0, clear app; end
        end

        function delete(app), app.shutdown(); end
    end

    methods (Access = private)
        function startup(app)
            u = app.ui;
            set([u.cutPax, u.full(2).ax], 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            for ax = [u.full(1).ax, u.cutAx], ax.Interactions = [zoomInteraction, dataTipInteraction]; end
            for ax = [u.full(3:5).ax],       ax.Interactions = [rotateInteraction, dataTipInteraction]; end
            hold(u.covAx, 'on'); grid(u.covAx, 'on'); ylim(u.covAx, [0 100]); set(u.covAx, 'Box', 'on', 'Layer', 'top');
            app.defaults = get(u.paramCtrls, 'Value');
            app.status("both", 'Ready -- load an antenna pattern file to begin 🚀', false);
            app.setCovUI();
        end

        function shutdown(app)
            % Single re-entrant close path: stop async resources, then release the figure.
            if app.isClosing, return; end
            app.isClosing = true; app.stopTimer();
            if ~isempty(app.opDialog) && isvalid(app.opDialog), delete(app.opDialog); end
            if isfield(app.ui, 'fig') && isvalid(app.ui.fig), delete(app.ui.fig); end
        end

        function f = cb(app, method, varargin)
            % Wrap an app method as a guarded UI callback (extra arguments are appended).
            extra = varargin;
            f = @(src, evt) app.guard(method, src, evt, extra{:});
        end

        function guard(app, method, src, evt, varargin)
            if app.isClosing, return; end
            try
                method(app, src, evt, varargin{:});
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.status("main", 'Operation cancelled by user.', true);
                else, app.showError(ME); end
            end
        end

        function showError(app, ME)
            if app.isClosing || ~isvalid(app.ui.fig), return; end
            where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.ui.fig, [ME.message where], 'APAT Error', 'Icon', 'error');
        end
    end

    %% ------------------------------------------------------------------ UI construction
    methods (Access = private)
        function h = add(~, ctor, parent, row, col, varargin)
            % Create one component inside a grid layout and place it in a single call.
            h = ctor(parent, varargin{:});
            if ~isempty(row), h.Layout.Row = row; end
            if ~isempty(col), h.Layout.Column = col; end
        end

        function h = lbl(app, g, text, row, col, varargin)
            h = app.add(@uilabel, g, row, col, 'Text', text, 'HorizontalAlignment', 'right', varargin{:});
        end

        function [slider, minSp, maxSp] = rangeControls(app, g, scope, rows)
            % Vertical range slider + max/min spinners in column 1 (rows = [max slider min]), wired to setRange(scope).
            maxSp  = app.add(@uispinner, g, rows(1), 1, 'Limits', app.DbRange, 'Value', app.DbRange(2), 'Step', 5, 'ValueChangedFcn', app.cb(@onRange, scope, 2));
            slider = app.add(@(p, varargin) uislider(p, 'range', varargin{:}), g, rows(2), 1, 'Limits', app.DbRange, 'Value', app.DbRange, 'Orientation', 'vertical', 'ValueChangedFcn', app.cb(@onRange, scope, 0));
            minSp  = app.add(@uispinner, g, rows(3), 1, 'Limits', app.DbRange, 'Value', app.DbRange(1), 'Step', 5, 'ValueChangedFcn', app.cb(@onRange, scope, 1));
        end

        function dd = formatDropdown(app, g, row, col, callback)
            dd = app.add(@uidropdown, g, row, col, 'Visible', 'off', 'ValueChangedFcn', callback, 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', ...
                'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
                '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
                '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'});
        end

        function buildUI(app)
            u = struct();
            u.fig = uifigure('Name', ['Antenna Pattern Analyzer Tool — APAT v' app.Version], 'Visible', 'off', ...
                'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) app.shutdown());
            u.plotMenu = uicontextmenu(u.fig);                    % one shared context menu for every plot
            uimenu(u.plotMenu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, e) delete(findall(ancestor(e.ContextObject, {'axes', 'polaraxes'}), 'Type', 'datatip')));
            u.tabs = uitabgroup(uigridlayout(u.fig, [1 1]));
            u.tabMain = uitab(u.tabs, 'Title', 'Process Pattern 📡');
            u.tabCov = uitab(u.tabs, 'Title', 'Compute Coverage 📈');
            app.ui = u;
            app.buildMainTab(); app.buildCoverageTab();
            app.ui.fig.Visible = 'on';
        end

        function buildMainTab(app)
            u = app.ui; add = @app.add; lbl = @app.lbl; cb = @app.cb;
            g = uigridlayout(u.tabMain, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});

            % ---- inputs & parameters
            gp = uigridlayout(add(@uipanel, g, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️'), 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            lbl(gp, 'Input Pattern:', 1, 1);
            u.path = add(@uieditfield, gp, 1, [2 8]);
            u.ffdLbl = lbl(gp, 'FFD Freq:', 1, 9, 'Visible', 'off');
            u.ffd = add(@uidropdown, gp, 1, 10, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', cb(@onFFD));
            u.load = add(@uibutton, gp, 1, [11 12], 'Text', '📂 Load File', 'FontWeight', 'bold', 'FontSize', 14, 'ButtonPushedFcn', cb(@onLoad));
            u.process = add(@uibutton, gp, 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', cb(@onProcess));
            u.resetParams = add(@uibutton, gp, 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', cb(@onResetParams));
            u.fmtLbl = lbl(gp, 'Format:', 2, [4 5], 'Visible', 'off');
            u.fmt = app.formatDropdown(gp, 2, [6 8], cb(@onTextFormat));
            u.step = add(@uidropdown, gp, 2, [9 10], 'Items', {'STEP'}, 'Visible', 'off', 'ValueChangedFcn', cb(@onStep));
            u.exportOut = add(@uibutton, gp, 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@onExportResults));
            u.exportUAN = add(@uibutton, gp, 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@onExportUAN));
            u.rxLbl = lbl(gp, 'Rw Sense', 3, 1);
            u.rxPol = add(@uidropdown, gp, 3, 2, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Editable', 'on');
            u.rwLbl = lbl(gp, 'Rw (dB)', 3, 3);
            u.rw = add(@uispinner, gp, 3, 4, 'Value', 6);
            u.lossLbl = lbl(gp, 'Loss (−) / Gain (+) dB', 3, 5);
            u.loss = add(@uispinner, gp, 3, 6, 'Step', 0.1);
            u.ptLbl = lbl(gp, 'Tx Pwr (Pt)', 3, 7);
            u.pt = add(@uispinner, gp, 3, 8);
            u.ptUnit = add(@uidropdown, gp, 3, 9, 'Items', {'dBW', 'dBm', 'Watts'});
            u.rLbl = lbl(gp, 'Distance', 3, 10);
            u.r = add(@uispinner, gp, 3, 11, 'Value', 1);
            u.rUnit = add(@uidropdown, gp, 3, 12, 'Items', {'m', 'km'});
            u.coverage = add(@uibutton, gp, 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@onToCoverage));
            u.paramCtrls = [u.loss, u.rxPol, u.rw, u.pt, u.ptUnit, u.r, u.rUnit];
            u.paramGroups = {[u.rxLbl, u.rxPol, u.rwLbl, u.rw], [u.ptLbl, u.pt, u.ptUnit], [u.rLbl, u.r, u.rUnit], [u.lossLbl, u.loss]};
            set([u.paramGroups{:}], 'Visible', 'off');

            % ---- full-pattern plots: five tabs sharing one record layout (kind, tab, ax, slider, minSp, maxSp)
            u.fullPanel = add(@uipanel, g, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off');
            u.fullTabs = add(@uitabgroup, uigridlayout(u.fullPanel, [1 1]), 1, 1, 'SelectionChangedFcn', cb(@onTabChanged));
            kinds = {'contour', 'fisheye', 'sphere', 'polar3d', 'rect3d'};
            titles = {'Contour Plot', 'Circular Contour Plot', '3D Spherical Plot', '3D Polar Plot', '3D Surface Plot'};
            for k = 1:5
                f = struct('kind', kinds{k}, 'tab', uitab(u.fullTabs, 'Title', titles{k}));
                gt = uigridlayout(f.tab, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
                [f.slider, f.minSp, f.maxSp] = app.rangeControls(gt, "full", [1 2 3]);
                if k == 2, f.ax = polaraxes(gt); else, f.ax = uiaxes(gt); end
                f.ax.Layout.Row = [1 3]; f.ax.Layout.Column = 2;
                u.full(k) = f;
            end

            % ---- cut plots
            u.cutPanel = add(@uipanel, g, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off');
            u.cutTabs = add(@uitabgroup, uigridlayout(u.cutPanel, [1 1]), 1, 1, 'SelectionChangedFcn', cb(@onTabChanged));
            u.tabPolar = uitab(u.cutTabs, 'Title', 'Polar Cut Plot');
            gc = uigridlayout(u.tabPolar, 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            [u.cutSlider, u.cutMin, u.cutMax] = app.rangeControls(gc, "cut", [1 2 4]);
            u.cutSlider.Layout.Row = [2 3];
            u.cutPax = polaraxes(gc); u.cutPax.Layout.Row = [1 4]; u.cutPax.Layout.Column = 3;
            u.hpbw = add(@(p, varargin) uibutton(p, 'state', varargin{:}), gc, 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', cb(@onCutChanged));
            u.hpbwLbl = add(@uilabel, gc, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            u.cutGrid = add(@uigridlayout, gc, 3, 4, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x', '1x', '1x'});
            names = {'E_Total', 'E_RCP', 'E_LCP'};
            for k = 1:3, u.cutBox(k) = add(@uicheckbox, u.cutGrid, k, 1, 'Text', names{k}, 'Value', true, 'ValueChangedFcn', cb(@onCutChanged)); end
            u.exportCut = add(@uibutton, gc, 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', cb(@onExportCut));
            u.tabRect = uitab(u.cutTabs, 'Title', 'Rectangular Cut Plot');
            u.cutAx = uiaxes(uigridlayout(u.tabRect, [1 1]));

            % ---- plot control
            u.ctrlPanel = add(@uipanel, g, 2, [13 14], 'Title', 'Plot Control 🎨', 'Visible', 'off');
            gk = uigridlayout(u.ctrlPanel, 'RowHeight', repmat({'fit'}, 1, 15));
            lbl(gk, 'Component', 1, 1);
            u.component = add(@uidropdown, gk, 1, 2, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', cb(@onComponent));
            lbl(gk, 'Cut type', 2, 1);
            u.cutType = add(@uidropdown, gk, 2, 2, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', cb(@onCutChanged));
            lbl(gk, 'Cut value', 3, 1);
            u.cutValue = add(@uispinner, gk, 3, 2, 'Limits', [0 360], 'ValueChangedFcn', cb(@onCutChanged));
            lbl(gk, 'Cut fields', 4, 1);
            u.cutBasis = add(@uidropdown, gk, 4, 2, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Enable', 'off', 'ValueChangedFcn', cb(@onCutChanged));
            lbl(gk, 'Colorbar max', 5, 1);  u.cmax = add(@uispinner, gk, 5, 2, 'Limits', app.DbRange, 'Value', 10);
            lbl(gk, 'Colorbar min', 6, 1);  u.cmin = add(@uispinner, gk, 6, 2, 'Limits', app.DbRange, 'Value', -40);
            lbl(gk, 'Colorbar step', 7, 1); u.cstep = add(@uispinner, gk, 7, 2, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', @(~, ~) app.applyFullRange());
            applyAll = @(~, ~) app.setRange("all", [u.cmin.Value, u.cmax.Value], true);
            set([u.cmin, u.cmax], 'ValueChangedFcn', applyAll);
            lbl(gk, 'Adjust Colorbar', 8, 1);
            add(@uibutton, gk, 8, 2, 'Text', 'Apply', 'Tooltip', 'Apply to full-pattern plots and cuts.', 'ButtonPushedFcn', applyAll);
            lbl(gk, '3D view', 9, 1);
            u.view3d = add(@uidropdown, gk, 9, 2, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'ValueChangedFcn', @(~, ~) app.apply3DViews(true));
            sw = @(p, varargin) uiswitch(p, 'slider', varargin{:}); pad = @(n) repmat(char(160), 1, n);
            u.phiSpan = add(sw, gk, 10, [1 2], 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0-360', 'signed'}, 'ValueChangedFcn', cb(@onSpan));
            u.thetaSpan = add(sw, gk, 11, [1 2], 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'polar', 'elevation'}, 'ValueChangedFcn', cb(@onSpan));
            u.plane = add(sw, gk, 12, [1 2], 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E', 'H'}, 'ValueChangedFcn', cb(@onPlane));
            u.overlay = add(@uicheckbox, gk, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', @(~, ~) app.overlayCuts());
            u.pob = add(@uicheckbox, gk, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', @(~, ~) app.syncTips());
            u.hpbwTips = add(@uicheckbox, gk, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', @(~, ~) app.syncTips());

            % ---- results / input / metadata tables and status bar
            u.outFilter = add(@uidropdown, g, 3, [13 14], 'Items', {'--- column filter ---'}, 'Visible', 'off', 'ValueChangedFcn', cb(@onOutFilter));
            u.dataTabs = add(@uitabgroup, g, 4, [1 14], 'Visible', 'off');
            t = uitab(u.dataTabs, 'Title', 'Results 📤'); t.ButtonDownFcn = @(~, ~) set(u.outFilter, 'Visible', 'on');
            u.tblOut = uitable(uigridlayout(t, [1 1]), 'ColumnWidth', '1x', 'RowName', 'numbered', 'ColumnSortable', true, 'ColumnRearrangeable', 'on');
            t = uitab(u.dataTabs, 'Title', 'Input 📥');
            u.tblIn = uitable(uigridlayout(t, [1 1]), 'RowName', 'numbered', 'ColumnSortable', true, 'ColumnRearrangeable', 'on');
            t = uitab(u.dataTabs, 'Title', 'Metadata 📋');
            u.tblMeta = uitable(uigridlayout(t, [1 1]), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            u.status = add(@uilabel, g, 5, [1 14], 'Interpreter', 'html', 'Text', 'Ready 🚀');
            app.ui = u;
        end

        function buildCoverageTab(app)
            u = app.ui; add = @app.add; lbl = @app.lbl; cb = @app.cb;
            g = uigridlayout(u.tabCov, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            gp = uigridlayout(add(@uipanel, g, 1, [1 5], 'Title', 'Inputs & Parameters 🎛️'), 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'});
            u.covParamGrid = gp;
            u.covType = add(@uibuttongroup, gp, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', cb(@onCovType));
            u.covSph = uiradiobutton(u.covType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            u.covCon = uiradiobutton(u.covType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            u.covOrientLbl = lbl(gp, 'Orientation 🧭:', 3, 1);
            u.covOrient = add(@uidropdown, gp, 3, 2, 'Items', [{'Auto'}, app.Axes6.labels], 'ItemsData', 0:6, 'ValueChangedFcn', cb(@onCovOrientation));
            lbl(gp, 'Component:', 4, 1);
            u.covComp = add(@uidropdown, gp, 4, 2, 'Items', {'E_Total_dB'}, 'ValueChangedFcn', cb(@onCovComponent));
            u.covPathLbl = lbl(gp, 'Antenna Pattern:', 1, 3);
            u.covPath = add(@uieditfield, gp, 1, [4 8]);
            u.covLoad = add(@uibutton, gp, 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', cb(@onCovLoad));
            u.covCompute = add(@uibutton, gp, 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'ButtonPushedFcn', cb(@onCovCompute));
            lbl(gp, 'Threshold  Min (dB):', 2, 3); u.thrMin = add(@uispinner, gp, 2, 4, 'Value', -40);
            lbl(gp, 'Threshold  Max (dB):', 2, 5); u.thrMax = add(@uispinner, gp, 2, 6, 'Value', 10);
            lbl(gp, 'Step (dB):', 2, 7);           u.thrStep = add(@uispinner, gp, 2, 8, 'Value', 1);
            u.covReset = add(@uibutton, gp, 2, 9, 'Text', '🔄 Reset', 'ButtonPushedFcn', cb(@onCovReset));
            u.covExport = add(@uibutton, gp, 2, 10, 'Text', '💾 Export Results', 'ButtonPushedFcn', cb(@onCovExport));
            coneLbls = [lbl(gp, 'Cone θ₀ (°):', 3, 3), lbl(gp, 'Cone φ₀ (°):', 3, 5), lbl(gp, 'Cone Angle α (°):', 3, 7)];
            u.coneTh = add(@uispinner, gp, 3, 4, 'Limits', [0 180]);
            u.conePh = add(@uispinner, gp, 3, 6, 'Limits', [0 360]);
            u.coneAng = add(@uispinner, gp, 3, 8, 'Limits', [0 180], 'Value', 45);
            u.covClear = add(@uibutton, gp, 3, 9, 'Text', '🧹 Clear DataTips', 'ButtonPushedFcn', cb(@onCovClear));
            u.covToMain = add(@uibutton, gp, 3, 10, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~, ~) set(u.tabs, 'SelectedTab', u.tabMain));
            qCovLbl = lbl(gp, 'Coverage @ dB:', 4, 3);
            u.qCov = add(@uispinner, gp, 4, 4, 'ValueDisplayFormat', '%g dB');
            u.qCovBtn = add(@uibutton, gp, 4, 5, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', cb(@onCovQuery, "cov"));
            qThrLbl = lbl(gp, 'Threshold @ %:', 4, 6);
            u.qThr = add(@uispinner, gp, 4, 7, 'Value', 50, 'ValueDisplayFormat', '%g%%');
            u.qThrBtn = add(@uibutton, gp, 4, 8, 'Text', '🔍 Query Threshold', 'ButtonPushedFcn', cb(@onCovQuery, "thr"));
            u.covFmtLbl = lbl(gp, 'Format:', 4, 9);
            u.covFmt = app.formatDropdown(gp, 4, 10, cb(@onCovTextFormat));
            u.queryCtrls = [qCovLbl, u.qCov, u.qCovBtn, qThrLbl, u.qThr, u.qThrBtn];
            u.coneCtrls = [coneLbls, u.coneTh, u.conePh, u.coneAng, u.covOrientLbl, u.covOrient];

            % ---- results: tree | plot + X range | table
            u.covResults = add(@uipanel, g, 2, [1 5], 'Title', 'Results', 'Visible', 'off');
            gr = uigridlayout(u.covResults, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            u.covTree = add(@(p, varargin) uitree(p, 'checkbox', varargin{:}), gr, [1 2], 1, 'SelectionChangedFcn', cb(@onCovSelect), 'CheckedNodesChangedFcn', cb(@onCovChecked));
            u.covRoot = uitreenode(u.covTree, 'Text', 'Coverage Results');
            u.covAx = add(@uiaxes, gr, 1, [2 4]);
            title(u.covAx, 'Coverage vs Threshold'); xlabel(u.covAx, 'Threshold (dB)'); ylabel(u.covAx, 'Coverage (%)');
            u.covAx.Interactions = dataTipInteraction;
            u.covTbl = add(@uitable, gr, [1 2], 5, 'ColumnWidth', '1x', 'RowName', {});
            u.xMin = add(@uispinner, gr, 2, 2, 'Limits', app.DbRange, 'Value', -40, 'ValueChangedFcn', cb(@onCovXRange));
            u.xRange = add(@(p, varargin) uislider(p, 'range', varargin{:}), gr, 2, 3, 'Limits', app.DbRange, 'Value', [-40 10], 'ValueChangedFcn', cb(@onCovXRange), 'ValueChangingFcn', cb(@onCovXRange));
            u.xMax = add(@uispinner, gr, 2, 4, 'Limits', app.DbRange, 'Value', 10, 'ValueChangedFcn', cb(@onCovXRange));
            u.covStatus = add(@uilabel, g, 3, [1 5], 'Interpreter', 'html', 'Text', 'Ready 🚀');
            app.ui = u;
        end
    end

    %% ------------------------------------------------------------------ pipeline (source → view)
    methods (Access = private)
        function prm = params(app)
            % Processing parameters, read from the UI once per pipeline run.
            u = app.ui;
            prm = struct('GainLoss_dB', u.loss.Value, 'RxMode', string(u.rxPol.Value), 'RxAR_dB', u.rw.Value);
            prm.FieldScale = 10^(prm.GainLoss_dB/20);
            switch u.ptUnit.Value
                case 'dBm',   prm.Pt_dBW = u.pt.Value - 30;
                case 'Watts', prm.Pt_dBW = 10*log10(max(u.pt.Value, eps));
                otherwise,    prm.Pt_dBW = u.pt.Value;
            end
            prm.R_m = max(u.r.Value, 1e-12) * (1 + 999*strcmp(u.rUnit.Value, 'km'));
        end

        function activate(app, src, fp)
            % Install a parsed source as the Main-tab pattern and select block 1.
            app.src = src; [folder, base, ext] = fileparts(fp);
            app.file = struct('path', fp, 'folder', folder, 'base', base, 'name', [base ext]);
            app.rawShown = false; app.selectBlock(1);
        end

        function selectBlock(app, k)
            T = canonicalize(app.src.blocks{k}); T.Properties.UserData = app.src.meta;
            app.stdTbl = T; app.patTbl = table();
            if app.src.meta.isDep, app.src.rawTbl = app.src.blocks{k}; app.rawShown = false; end
        end

        function refresh(app)
            % Full pipeline: process → step → view → tables → E/H cut → full plots → status.
            u = app.ui; meta = app.src.meta; app.patTbl = table();
            st = [gridStep(app.stdTbl.Theta), gridStep(app.stdTbl.Phi)]; st(~isfinite(st)) = 1;
            nonCanonical = any(abs(st - 1) > 1e-9);
            u.step.Items = [compose('STEP: %g°', max(st)), repmat({'STEP: 1°'}, 1, double(nonCanonical))];
            u.step.Value = u.step.Items{1 + (app.keepOneDegree && nonCanonical)};
            set(u.step, 'Visible', nonCanonical, 'Enable', nonCanonical);
            app.applyStep(); app.perf("Process pattern"); app.checkCancelled();
            if app.autoCutBasis && ~meta.isGainOnly, u.cutBasis.Value = regexp(app.info.pol, '^\w+', 'match', 'once'); end
            app.syncComponents(u.component, app.viewTbl);
            app.updateView(true, false, false); app.perf("Populate tables and ranges"); app.checkCancelled();
            app.onPlane(); drawnow limitrate                      % E/H-plane cut first: fast visual feedback
            app.renderFull(); app.perf("Build plots");
            hasE = ~meta.isGainOnly;
            set([u.cutPanel, u.exportOut, u.fullPanel, u.ctrlPanel, u.coverage], 'Visible', 'on');
            set([u.exportUAN, u.cutGrid], 'Visible', hasE); set(u.cutBox, 'Visible', hasE); u.cutBasis.Enable = hasE;
            app.updateParamVisibility();
            pol = ''; if hasE, pol = sprintf(' | Polarization %s', app.info.pol); end
            app.status("main", sprintf('Pattern: %s | POB %s dB ( &theta;=%s&deg;, &phi;=%s&deg; )%s', ...
                app.file.name, fmt(app.POB(1), 2), fmt(app.POB(2)), fmt(app.POB(3)), pol), false);
        end

        function applyStep(app)
            % Select native or 1° data.  Resampling acts on the canonical SOURCE (fields), never on nonlinear outputs.
            S = app.stdTbl; prm = app.params();
            if endsWith(app.ui.step.Value, '1°') && logical(app.ui.step.Visible)
                st = [gridStep(S.Theta), gridStep(S.Phi)];
                if all(isfinite(st) & st < 1)                     % sub-degree grid: exact decimation onto integer degrees
                    S = S(all(abs([S.Theta, S.Phi] - round([S.Theta, S.Phi])) < 1e-9, 2), :);
                else
                    S = resampleCanonical(S, 1);
                end
                [app.viewTbl, app.info] = computePattern(S, prm, app.PeakPct, app.PeakExcess);
            else
                if isempty(app.patTbl), [app.patTbl, app.info] = computePattern(S, prm, app.PeakPct, app.PeakExcess); end
                app.viewTbl = app.patTbl;
            end
            app.invalidateView();
        end

        function invalidateView(app)
            app.gridCache = struct(); app.omega = []; app.metrics = struct(); app.viewRev = app.viewRev + 1;
        end

        function updateView(app, resetGain, doCut, doFull)
            % Derive everything shown from viewTbl + selected component: peak, boresight, metrics, ranges, tables, plots.
            if nargin < 2, resetGain = false; end
            if nargin < 3, doCut = true; end
            if nargin < 4, doFull = true; end
            T = app.viewTbl; col = app.comp();
            if isempty(app.omega), app.omega = solidWeights(T.Theta, T.Phi); end
            [app.peak, app.boresight] = orientation(T, app.omega, col, app.Axes6, app.PeakPct, app.PeakExcess);
            app.POB = [app.peak.value, T.Theta(app.peak.index), mod(T.Phi(app.peak.index), 360)];
            app.metrics = computeMetrics(T, app.omega, app.Axes6, app.boresight, app.PeakPct, app.PeakExcess);
            if resetGain && ismember('E_Total_dB', T.Properties.VariableNames), app.gainLim = peakRange(T.E_Total_dB, app.PeakPct, app.PeakExcess); end
            r = app.gainLim; if isAR(col), r = [-30 30]; end
            app.setRange("all", r, false, resetGain);
            app.updateTables(); app.updateMetadata();
            if doCut, app.syncCutControl(); app.plotCut(); end
            if doFull, app.renderFull(); end
        end

        function syncComponents(~, dd, T, prefer)
            % Populate a component dropdown from T's canonical columns, keeping PREFER (default: current value) when present.
            [cols, labels] = componentMap(T); cols = cellstr(cols);
            if nargin < 4, prefer = dd.Value; end
            [dd.Items, dd.ItemsData] = deal(cellstr(labels), cols);
            if ~any(strcmp(cols, prefer)), prefer = 'E_Total_dB'; end
            if ~any(strcmp(cols, prefer)), prefer = cols{1}; end
            dd.Value = prefer;
        end

        function c = comp(app), c = app.ui.component.Value; end
        function tf = signed(app), tf = strcmp(app.ui.phiSpan.Value, 'signed'); end
        function tf = elevation(app), tf = strcmp(app.ui.thetaSpan.Value, 'elevation'); end
        function t = dispTheta(app, t), if app.elevation(), t = 90 - t; end, end

        function s = compLabel(app)
            dd = app.ui.component; i = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(i), s = string(strrep(dd.Value, '_', ' ')); else, s = string(dd.Items{i}); end
        end
    end

    %% ------------------------------------------------------------------ view model: display grid & cuts
    methods (Access = private)
        function [th, ph, G, geo] = viewGrid(app, col)
            % Regular grid of COL in the DISPLAY convention (rows θ, columns φ) with cached 3-D geometry.
            % Physical columns are permuted/relabelled here; the state table is never rewritten.
            c = app.gridCache; T = app.viewTbl; key = [app.ui.phiSpan.Value '|' app.ui.thetaSpan.Value];
            if ~isfield(c, 'key') || ~strcmp(c.key, key)
                thP = unique(T.Theta); phP = unique(T.Phi);
                [~, i] = ismember(T.Theta, thP); [~, j] = ismember(T.Phi, phP);
                cols = (1:numel(phP)).'; ph = phP;
                if app.signed()                                   % φ>180 → φ−360, drop the 360 copy, prepend −180 (= 180)
                    cols = find(phP < 360 - 1e-9); ph = phP(cols); ph(ph > 180) = ph(ph > 180) - 360;
                    [ph, o] = sort(ph); cols = cols(o);
                    j180 = find(abs(phP - 180) < 1e-9, 1);
                    if ~isempty(j180), ph = [-180; ph]; cols = [j180; cols]; end
                end
                th = app.dispTheta(thP);
                [PH, TH] = meshgrid(phP(cols), thP); s = sind(TH);
                geo = struct('TH', TH, 'PH', PH, 'x', s.*cosd(PH), 'y', s.*sind(PH), 'z', cosd(TH), ...
                    'thD', repmat(th, 1, numel(cols)), 'phD', repmat(ph.', numel(thP), 1));
                c = struct('key', key, 'th', th, 'ph', ph, 'phPhys', phP(cols), 'lin', sub2ind([numel(thP) numel(phP)], i, j), ...
                    'sz', [numel(thP) numel(phP)], 'cols', cols, 'geo', geo, 'data', struct());
            end
            k = matlab.lang.makeValidName(col);
            if ~isfield(c.data, k), Gf = nan(c.sz); Gf(c.lin) = T.(col); c.data.(k) = Gf(:, c.cols); end
            th = c.th; ph = c.ph; geo = c.geo; G = c.data.(k); app.gridCache = c;
        end

        function c = cutCols(app)
            % Selected cut columns: the displayed component (gain-only) or Total + co/cross pair in the chosen basis.
            u = app.ui;
            if app.src.meta.isGainOnly, c = struct('names', {{app.comp()}}, 'idx', 1); return; end
            if strcmp(u.cutBasis.Value, 'Linear'), all3 = {'E_Total_dB', 'E_TH_dB', 'E_PH_dB'}; else, all3 = {'E_Total_dB', 'E_RCP_dB', 'E_LCP_dB'}; end
            set(u.cutBox(2:3), {'Text'}, erase(all3(2:3), '_dB').');
            sel = [u.cutBox.Value]; if ~any(sel), sel(1) = true; end
            c = struct('names', {all3(sel)}, 'idx', find(sel));
        end

        function [a, V, names, ttl, geo] = cutData(app)
            % Active cut as one closed circle (0..360 or −180..180): angle, values, legend names, title, physical geometry.
            u = app.ui; T = app.viewTbl; c = app.cutCols(); type = u.cutType.Value;
            [a, rows, fixed, sym, snapped] = cutGeometry(T, type, u.cutValue.Value);
            if snapped, app.status("main", sprintf('Requested %s cut @ %s=%g° (snapped to nearest %s=%g°)', type, sym, u.cutValue.Value, sym, fixed), false); end
            M = [a, T.Theta(rows), T.Phi(rows), T{rows, c.names}];   % columns: angle, θ, φ, values…
            lim = [0 360];
            if app.signed(), lim = [-180 180]; w = M(:, 1) > 180; M(w, 1) = M(w, 1) - 360; M = sortrows(M, 1); end
            [~, i] = unique(M(:, 1), 'stable'); M = M(i, :);
            if strcmp(type, 'Phi')                                % close the seam explicitly at both display ends
                lo = find(abs(M(:, 1) - lim(1)) < 1e-9, 1); hi = find(abs(M(:, 1) - lim(2)) < 1e-9, 1);
                if isempty(lo) && ~isempty(hi), M = [M(hi, :); M]; M(1, 1) = lim(1);
                elseif ~isempty(lo) && isempty(hi), M = [M; M(lo, :)]; M(end, 1) = lim(2);
                elseif isempty(lo) && isempty(hi)                 % interpolate across the periodic gap
                    w = (lim(2) - M(end, 1)) / (M(1, 1) - lim(1) + lim(2) - M(end, 1));
                    s = (1 - w)*M(end, :) + w*M(1, :); s([1 3]) = lim(1); M = [s; M; s]; M(end, [1 3]) = lim(2);
                end
            end
            a = M(:, 1); V = M(:, 4:end); geo = struct('theta', M(:, 2), 'phi', M(:, 3), 'fixed', fixed, 'type', type);
            names = strrep(c.names, '_', '\_');
            if app.src.meta.isGainOnly, ttl = app.comp(); else, ttl = sprintf('%s cut @ %s = %g°', type, sym, fixed); end
        end

        function vals = syncCutControl(app)
            % Snap the cut-value spinner to the available fixed angles of the active cut type (physical degrees).
            u = app.ui; T = app.viewTbl;
            if strcmp(u.cutType.Value, 'Phi'), vals = unique(T.Theta); else, vals = unique(T.Phi); end
            u.cutValue.Limits = [min(vals), max(vals)];
            if numel(vals) > 1, u.cutValue.Step = min(diff(vals)); end
            [~, i] = min(abs(vals - u.cutValue.Value)); u.cutValue.Value = vals(i);
        end

        function D = displayTable(app)
            % viewTbl re-expressed in the display convention for the Results table and exports.
            D = app.viewTbl;
            if app.signed()
                D(abs(D.Phi - 360) < 1e-9, :) = []; D.Phi(D.Phi > 180) = D.Phi(D.Phi > 180) - 360;
                seam = D(abs(D.Phi - 180) < 1e-9, :); seam.Phi(:) = -180; D = [seam; D];
            end
            if app.elevation(), D.Theta = 90 - D.Theta; end
            if app.signed() || app.elevation(), D = sortrows(D, {'Phi', 'Theta'}); end
        end
    end

    %% ------------------------------------------------------------------ rendering
    methods (Access = private)
        function [lim, map] = theme(app)
            % Colour scale of the selected component: signed AR uses blue-white-red, everything else jet.
            persistent jetMap arMap
            if isempty(jetMap), jetMap = jet(256); arMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
            lim = app.fullLim; if isAR(app.comp()), map = arMap; else, map = jetMap; end
        end

        function renderFull(app)
            % Render all five full-pattern views eagerly (tab switching never re-plots).
            if isempty(app.viewTbl), return; end
            u = app.ui; col = app.comp(); [th, ph, G, geo] = app.viewGrid(col); [lim, map] = app.theme(); label = app.compLabel();
            [~, pr] = min(abs(th - app.dispTheta(app.POB(2)))); [~, pc] = min(abs(app.gridCache.phPhys - app.POB(3)));
            thLabel = "Theta"; if app.elevation(), thLabel = "Elevation"; end
            for k = 1:5
                f = u.full(k); ax = f.ax; app.checkCancelled(); if app.isClosing, return; end
                cla(ax); hold(ax, 'on');
                switch f.kind
                    case 'contour'
                        h = pcolor(ax, ph, th, G); set(h, 'FaceColor', 'interp', 'LineStyle', 'none');
                        app.angularAxes(ax, 30, 15); daspect(ax, [1 1 1]); title(ax, label, 'Interpreter', 'none');
                        P = [ph(pc), th(pr), 0];
                    case 'fisheye'
                        h = surface(ax, deg2rad(geo.PH), geo.TH, zeros(size(G)), G, 'EdgeColor', 'none');
                        set(ax, 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', app.dispTheta(0:30:180))); app.polarTicks(ax);
                        title(ax, sprintf('%s  |  r=θ, angle=φ', label), 'Interpreter', 'none', 'FontSize', 9);
                        P = [deg2rad(geo.PH(pr, pc)), geo.TH(pr, pc), 0];
                    case {'sphere', 'polar3d'}
                        R = 1;
                        if strcmp(f.kind, 'polar3d'), R = max(G - lim(1), 0) / max(diff(lim), eps); R = R / max(max(R, [], 'all', 'omitnan'), eps); end
                        h = surf(ax, R.*geo.x, R.*geo.y, R.*geo.z, G, 'EdgeColor', 'none');
                        app.format3D(ax); title(ax, sprintf('%s  |  θ: %s  |  φ: %s', label, u.thetaSpan.Value, u.phiSpan.Value), 'Interpreter', 'none');
                        P = R(min(pr, end), min(pc, end)) * [geo.x(pr, pc), geo.y(pr, pc), geo.z(pr, pc)];
                    case 'rect3d'
                        h = surf(ax, ph, th, G, 'EdgeColor', 'none');
                        zlim(ax, lim); ax.ZTick = tickVector(lim, u.cstep.Value); app.angularAxes(ax, 60, 30); grid(ax, 'on');
                        xlabel(ax, 'Phi (degree)'); ylabel(ax, thLabel + " (degree)"); zlabel(ax, label + " (dB)", 'Interpreter', 'none');
                        app.apply3DView(ax, [-35 35]); title(ax, label, 'Interpreter', 'none');
                        P = [ph(pc), th(pr), G(pr, pc)];
                end
                h.Tag = 'APAT_Surface';
                setTipRows(h, [dataTipTextRow(thLabel, geo.thD, '%.3g°'); dataTipTextRow("Phi", geo.phD, '%.3g°'); dataTipTextRow(label, G, '%.3g dB')]);
                clim(ax, lim); colormap(ax, map); app.ui.full(k).cbar = colorbar(ax); app.setTicks(app.ui.full(k).cbar, lim);
                app.markPeak(ax, P, [dataTipTextRow(thLabel, th(pr), '%.3g°'); dataTipTextRow("Phi", ph(pc), '%.3g°'); dataTipTextRow(label, G(pr, pc), '%.3g dB')]);
                hold(ax, 'off'); set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', u.plotMenu);
            end
            app.overlayCuts(); app.apply3DViews(false); app.syncTips();
        end

        function plotCut(app)
            if isempty(app.viewTbl), return; end
            u = app.ui; pax = u.cutPax; rax = u.cutAx; c = app.cutCols(); [a, V, names, ttl] = app.cutData();
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on');
            r = app.cutLim; xl = app.angularLimits(); colors = rax.ColorOrder(1 + mod(c.idx - 1, 7), :);
            hp = polarplot(pax, deg2rad(a), max(V, r(1)), 'LineWidth', 1.4);   % clamp: no reflection spikes inside RLim
            hr = plot(rax, a, V, 'LineWidth', 1.4);
            set([hp(:); hr(:)], {'Color'}, num2cell([colors; colors], 2));
            for k = 1:numel(hp)
                rows = [dataTipTextRow("Angle", a, '%.3g°'); dataTipTextRow("Magnitude", V(:, k), '%.3g dB')];
                setTipRows(hp(k), rows); setTipRows(hr(k), rows);
            end
            set(pax, 'ThetaDir', 'clockwise', 'ThetaZeroLocation', 'top', 'RLim', r, 'RTick', r(1):5:r(2)); app.polarTicks(pax);
            set(rax, 'YLim', r, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, [u.cutType.Value ' (degree)']); title(pax, ttl, 'Interpreter', 'none'); title(rax, ttl, 'Interpreter', 'none');
            % peak of the displayed cut (first column) and optional HPBW
            [pk, ip] = max(V(:, 1), [], 'omitnan');
            rows = [dataTipTextRow("Angle", a(ip), '%.3g°'); dataTipTextRow("Magnitude", pk, '%.3g dB')];
            app.markPeak(pax, [deg2rad(a(ip)), max(pk, r(1)), 0], rows); app.markPeak(rax, [a(ip), pk, 0], rows);
            u.hpbwLbl.Text = ''; u.hpbwTips.Visible = u.hpbw.Value; if ~u.hpbw.Value, u.hpbwTips.Value = false; end
            if u.hpbw.Value
                [bw, lo, hi] = calcHPBW(a, V(:, 1), pk, a(ip));
                if isfinite(bw)
                    b = mod([lo hi] - xl(1), 360) + xl(1);          % wrap the bounds into the displayed span
                    u.hpbwLbl.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                    reg = b; if b(1) > b(2), reg = [xl(1), b(2); b(1), xl(2)]; end
                    thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    xregion(rax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    lbls = ["Lower HPBW", "Upper HPBW"];
                    for j = 1:2
                        rows = [dataTipTextRow(lbls(j), b(j), '%.2f°'); dataTipTextRow("Gain", pk - 3, '%.2f dB')];
                        app.markPeak(pax, [deg2rad(b(j)), pk - 3, 0], rows, 'APAT_HPBW'); app.markPeak(rax, [b(j), pk - 3, 0], rows, 'APAT_HPBW');
                    end
                end
            end
            legend(pax, hp, names, 'Location', 'southoutside', 'Orientation', 'horizontal');
            legend(rax, hr, names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off'); app.syncTips();
            set(findall(rax, '-property', 'ContextMenu'), 'ContextMenu', u.plotMenu);
        end

        function overlayCuts(app)
            % Draw (or remove) the active cut as a black great-circle line on the two spatial 3-D plots.
            u = app.ui; if isempty(app.viewTbl), return; end
            on = u.overlay.Value; if on, [~, V, ~, ~, geo] = app.cutData(); end
            for k = 3:4
                ax = u.full(k).ax; delete(findall(ax, 'Tag', 'APAT_CutOverlay'));
                if ~on, continue; end
                R = 1.02; if k == 4, R = 1.01 * max(V(:, 1) - app.fullLim(1), 0) / max(diff(app.fullLim), eps); end
                hold(ax, 'on');
                plot3(ax, R.*sind(geo.theta).*cosd(geo.phi), R.*sind(geo.theta).*sind(geo.phi), R.*cosd(geo.theta), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay', 'HandleVisibility', 'off');
                hold(ax, 'off');
            end
        end

        function markPeak(app, ax, P, rows, tag)
            % Marker + DataTip at display point P ([x y z], polar: [θrad r]); visibility is governed by syncTips.
            if nargin < 5, tag = 'APAT_POB'; end
            if any(~isfinite(P)), return; end
            col = 'k'; if strcmp(tag, 'APAT_HPBW'), col = '#D95319'; end
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), m = polarplot(ax, P(1), P(2), 'o'); else, m = plot3(ax, P(1), P(2), P(3), 'o', 'Clipping', 'off'); end
            set(m, 'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 5, 'Tag', tag, 'HandleVisibility', 'off');
            try
                m.DataTipTemplate.DataTipRows = rows;
                t = datatip(m, 'DataIndex', 1, 'FontSize', 9, 'Tag', tag, 'HandleVisibility', 'off');
                if isequal(ax, app.ui.full(1).ax)                 % keep the tip inside the contour axes at its top edge
                    top = ax.YLim(1 + strcmp(ax.YDir, 'normal'));
                    if abs(P(2) - top) <= diff(ax.YLim)/1000, if P(1) <= mean(ax.XLim), t.Location = 'southeast'; else, t.Location = 'southwest'; end, end
                end
            catch ME
                if ~app.isClosing, warning('APAT:Annotation', 'Could not create annotation: %s', ME.message); end
            end
        end

        function syncTips(app)
            % One visibility rule for every annotation: its feature checkbox is on AND its tab is selected.
            u = app.ui;
            for f = u.full, setTagVisible(f.ax, 'APAT_POB', u.pob.Value && u.fullTabs.SelectedTab == f.tab); end
            sel = u.cutTabs.SelectedTab;
            setTagVisible(u.cutPax, 'APAT_POB', u.pob.Value && sel == u.tabPolar);  setTagVisible(u.cutAx, 'APAT_POB', u.pob.Value && sel == u.tabRect);
            setTagVisible(u.cutPax, 'APAT_HPBW', u.hpbwTips.Value && sel == u.tabPolar); setTagVisible(u.cutAx, 'APAT_HPBW', u.hpbwTips.Value && sel == u.tabRect);
        end

        function angularAxes(app, ax, phiStep, thetaStep)
            [xl, yl, dir] = app.angularLimits();
            set(ax, 'XLim', xl, 'YLim', yl, 'YDir', dir, 'Box', 'on', 'Layer', 'top', 'XTick', xl(1):phiStep:xl(2), 'YTick', yl(1):thetaStep:yl(2));
        end

        function [xl, yl, dir] = angularLimits(app)
            xl = [0 360]; if app.signed(), xl = [-180 180]; end
            yl = [0 180]; dir = 'reverse'; if app.elevation(), yl = [-90 90]; dir = 'normal'; end
        end

        function polarTicks(app, pax)
            a = 0:30:330; if app.signed(), a(a > 180) = a(a > 180) - 360; end
            set(pax, 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', a));
        end

        function format3D(app, ax)
            % Fixed orthographic camera box with labelled +X/+Y/+Z arrows.
            set(ax, 'XDir', 'normal', 'YDir', 'normal', 'ZDir', 'normal', 'Projection', 'orthographic', 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], ...
                'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1]);
            axis(ax, 'off');
            colors = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; names = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            for i = 1:3
                d = 1.35 * double((1:3) == i);
                quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors{i}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12*d(1), 1.12*d(2), 1.12*d(3), names{i}, 'Color', colors{i}, 'FontWeight', 'bold');
            end
            app.apply3DView(ax, [135 25]);
        end

        function apply3DView(app, ax, default)
            views = struct('top', {{0, 90, [0 1 0]}}, 'bottom', {{0, -90, [0 1 0]}}, 'right', {{90, 0, [0 0 1]}}, ...
                'left', {{-90, 0, [0 0 1]}}, 'front', {{0, 0, [0 0 1]}}, 'back', {{180, 0, [0 0 1]}});
            code = app.ui.view3d.Value;
            if isfield(views, code), v = views.(code); else, v = {default(1), default(2), [0 0 1]}; end
            view(ax, v{1}, v{2}); camup(ax, v{3});
        end

        function apply3DViews(app, redraw)
            if isempty(app.viewTbl), return; end
            u = app.ui; app.apply3DView(u.full(3).ax, [135 25]); app.apply3DView(u.full(4).ax, [135 25]); app.apply3DView(u.full(5).ax, [-35 35]);
            if redraw, drawnow limitrate; end
        end
    end

    %% ------------------------------------------------------------------ ranges, tables, metadata, status
    methods (Access = private)
        function setRange(app, scope, r, apply, reset)
            % Mirror one dB range to every control of SCOPE ("full" | "cut" | "all"), store it and optionally apply it.
            if nargin < 5, reset = false; end
            u = app.ui; r = clampRange(r, app.DbRange, 1);
            if scope == "all"
                set([u.cmin, u.cmax], {'Value'}, {r(1); r(2)});
                app.setRange("full", r, apply, reset); app.setRange("cut", r, apply, reset); return
            end
            if scope == "full"
                syncRange([u.full.slider], [u.full.minSp], [u.full.maxSp], r, 1, app.DbRange, reset);
                app.fullLim = r; if ~isAR(app.comp()), app.gainLim = r; end
                if apply && ~isempty(app.viewTbl), app.applyFullRange(); end
            else
                syncRange(u.cutSlider, u.cutMin, u.cutMax, r, 1, app.DbRange, reset); app.cutLim = r;
                if apply && ~isempty(app.viewTbl), set(u.cutPax, 'RLim', r); set(u.cutAx, 'YLim', r); end
            end
            if apply, drawnow limitrate; end
        end

        function onRange(app, src, ~, scope, part)
            % Slider (part 0) or min/max spinner (part 1/2) of one scope changed.
            r = app.fullLim; if scope == "cut", r = app.cutLim; end
            if part == 0, r = src.Value; else, r(part) = src.Value; end
            app.setRange(scope, r, true);
        end

        function applyFullRange(app)
            % Push fullLim and the colorbar tick step to every rendered full-pattern axes (no re-render).
            r = app.fullLim;
            for f = app.ui.full
                if isempty(findall(f.ax, 'Tag', 'APAT_Surface')), continue; end
                clim(f.ax, r);
                if strcmp(f.kind, 'rect3d'), zlim(f.ax, r); f.ax.ZTick = tickVector(r, app.ui.cstep.Value); end
                if isfield(f, 'cbar') && isgraphics(f.cbar), app.setTicks(f.cbar, r); end
            end
        end

        function setTicks(app, cbar, r)
            t = tickVector(r, app.ui.cstep.Value);
            if isempty(t), cbar.TicksMode = 'auto'; else, cbar.Ticks = t; end
        end

        function updateTables(app)
            u = app.ui; D = app.displayTable(); cols = D.Properties.VariableNames(3:end);
            if ~app.rawShown, set(u.tblIn, 'Data', app.src.rawTbl, 'ColumnName', app.src.rawTbl.Properties.VariableNames); app.rawShown = true; end
            if ~isequal(u.outFilter.ItemsData(2:end), cols), app.outMask = ~ismember(cols, app.HiddenOut); end
            app.applyOutFilter(D);
        end

        function applyOutFilter(app, D)
            % Results table = angles + checked columns; the dropdown doubles as the (styled) column checklist.
            u = app.ui; cols = D.Properties.VariableNames(3:end);
            marks = repmat({''}, size(cols)); marks(app.outMask) = {'✓ '};
            u.outFilter.Items = [{'--- column filter ---'}, append(marks, cols)]; u.outFilter.ItemsData = [{''}, cols]; u.outFilter.Value = '';
            removeStyle(u.outFilter);
            addStyle(u.outFilter, uistyle('FontWeight', 'bold', 'BackgroundColor', [0.8 1 0.8]), 'Item', find(app.outMask) + 1);
            addStyle(u.outFilter, uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9]), 'Item', [1, find(~app.outMask) + 1]);
            u.tblOut.Data = D(:, [true true app.outMask]);
            set([u.outFilter, u.tblOut, u.dataTabs], 'Visible', 'on'); app.updateParamVisibility();
        end

        function onOutFilter(app, ~, ~)
            u = app.ui; v = u.outFilter.Value;
            if ~isempty(v), k = strcmp(u.outFilter.ItemsData(2:end), v); app.outMask(k) = ~app.outMask(k); end
            app.applyOutFilter(app.displayTable());
        end

        function updateParamVisibility(app)
            % Show only the parameters that influence a currently displayed Results column.
            u = app.ui; sel = string(app.viewTbl.Properties.VariableNames(3:end)); sel = sel(app.outMask);
            need = {["PLF_dB" "Gain_PolCorrected_dB"], ["EIRP_dBW" "PFD_Wm2" "E_RMS_Vm"], ["PFD_Wm2" "E_RMS_Vm"], ...
                ["E_Total_dB" "E_TH_dB" "E_PH_dB" "E_RCP_dB" "E_LCP_dB" "Gain_PolCorrected_dB" "EIRP_dBW" "PFD_Wm2" "E_RMS_Vm"]};
            for k = 1:4, set(u.paramGroups{k}, 'Visible', any(ismember(sel, need{k})) || (k == 4 && app.src.meta.isGainOnly)); end
        end

        function updateMetadata(app)
            u = app.ui; T = app.viewTbl; m = app.src.meta; th = app.dispTheta(unique(T.Theta)); xl = app.angularLimits();
            rows = {'Source format', m.source; 'File', app.file.name; ...
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(T), numel(th), numel(unique(T.Phi))); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmt(min(th)), fmt(max(th)), fmt(gridStep(th))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmt(xl(1)), fmt(xl(2)), fmt(gridStep(T.Phi)))};
            f = app.src.freqs(isfinite(app.src.freqs));
            if ~isempty(f), rows(end+1, :) = {'Frequencies', strjoin(compose('%.4g GHz', f/1e9), ', ')}; end
            if ~m.isGainOnly
                rows(end+1, :) = {'Polarization', app.info.pol};
                rows(end+1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(app.info.pairs.(u.cutBasis.Value), ' / '))};
            end
            rows = [rows; {'Peak gain (POB)', sprintf('%s dB', fmt(app.POB(1))); 'POB direction [θ, φ]', sprintf('[%s°, %s°]', fmt(app.POB(2)), fmt(app.POB(3))); ...
                'Boresight axis', app.Axes6.labels{app.boresight}; 'Peak policy', sprintf('P%.4g, max excess %.4g dB', app.PeakPct, app.PeakExcess); ...
                'Peak adjusted', char(string(app.peak.wasAdjusted))}];
            x = app.metrics;
            if isfield(x, 'PeakGain_dB')
                rows = [rows; {'HPBW E-plane', [fmt(x.HPBW_EPlane_deg) '°']; 'HPBW H-plane', [fmt(x.HPBW_HPlane_deg) '°']; 'Front-to-back', [fmt(x.FrontBack_dB) ' dB']; ...
                    'Peak directivity', [fmt(x.PeakDirectivity_dB) ' dB']}];
                if isfinite(x.Efficiency_pct), rows(end+1, :) = {'Radiation efficiency', [fmt(x.Efficiency_pct) '%']}; end
                if isfinite(x.AxialRatioAtPeak_dB), rows(end+1, :) = {'AR at peak', [fmt(x.AxialRatioAtPeak_dB) ' dB']}; end
            end
            if isfield(m, 'summary') && ~isempty(m.summary), rows = [rows; [append('Excel: ', m.summary(:, 1)), m.summary(:, 2)]]; end
            u.tblMeta.Data = rows;
        end

        function status(app, which, msg, transient)
            % Update the Main and/or Coverage status bar; transient messages revert to the sticky text after 3 s.
            if app.isClosing, return; end
            app.stopTimer(); msg = char(msg); lbls = [app.ui.status, app.ui.covStatus];
            for k = find([any(which == ["main" "both"]), any(which == ["cov" "both"])])
                lbls(k).Text = msg; if ~transient, app.sticky(k) = msg; end
            end
            if transient
                app.statusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, 'TimerFcn', @(~, ~) app.restoreStatus(), 'StopFcn', @(t, ~) app.disposeTimer(t));
                start(app.statusTimer);
            end
        end

        function restoreStatus(app)
            if app.isClosing, return; end
            app.ui.status.Text = app.sticky(1); app.ui.covStatus.Text = app.sticky(2);
        end

        function disposeTimer(app, t)
            if isequal(app.statusTimer, t), app.statusTimer = []; end
            if isvalid(t), delete(t); end
        end

        function stopTimer(app)
            t = app.statusTimer; app.statusTimer = [];
            if ~isempty(t) && isvalid(t), stop(t); end
            if ~isempty(t) && isvalid(t), delete(t); end
        end

        function checkCancelled(app)
            % Stop at the next pipeline checkpoint after the user pressed Abort.
            if ~isempty(app.opDialog) && isvalid(app.opDialog) && app.opDialog.CancelRequested
                app.opDialog.Message = 'Aborting...'; drawnow limitrate
                error('APAT:Cancelled', 'Operation cancelled by user.');
            end
        end

        function done = startPerf(app, op)
            % Stage timer; timings are exported to the base workspace only when ProfileToBase is true.
            stages = cell(0, 2); t0 = tic; t1 = tic; app.perf = @track; done = @finish;
            function track(name), stages(end+1, :) = {string(name), toc(t1)}; t1 = tic; end
            function finish()
                app.perf = @(~) [];
                if app.ProfileToBase, assignin('base', 'Perf_APAT', struct('Operation', string(op), 'Stages', cell2table(stages, 'VariableNames', {'Stage', 'Seconds'}), 'TotalSeconds', toc(t0))); end
            end
        end
    end

    %% ------------------------------------------------------------------ Main-tab callbacks
    methods (Access = private)
        function onLoad(app, ~, ~)
            u = app.ui; prev = u.path.Value; fp = strtrim(prev);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.file.path)
                fp = app.browse('Select an antenna pattern file', app.file.path); if isempty(fp), return; end
                u.path.Value = fp;
            end
            done = app.startPerf("Load pattern"); dlg = app.openDialog('Loading Data', 'Reading file...', true);
            cleaner = onCleanup(@() app.closeDialog(dlg, done)); %#ok<NASGU>
            src = app.readWithFormat(fp, u.fmtLbl, u.fmt); app.perf("Read file"); app.checkCancelled();
            if src.meta.isCoverage                                % coverage results never replace the Main pattern
                u.path.Value = prev; u.tabs.SelectedTab = u.tabCov; u.covPath.Value = fp;
                app.covLoadResults(fp, src.rawTbl); return
            end
            app.activate(src, fp);
            if src.meta.isDep
                items = compose('Pattern %d: %.4g GHz', (1:numel(src.blocks)).', src.freqs(:)/1e9);
                items(isnan(src.freqs)) = compose('Pattern %d', find(isnan(src.freqs(:))));
                [u.ffd.Items, u.ffd.Value] = deal(items, items{1});
            end
            set([u.ffd, u.ffdLbl], 'Visible', src.meta.isDep);
            app.keepOneDegree = false; app.autoCutBasis = true;
            app.refresh();
        end

        function onProcess(app, ~, ~)
            if isempty(app.stdTbl), uialert(app.ui.fig, 'No file! Load a pattern first.', 'Warning', 'Icon', 'warning'); return; end
            u = app.ui; done = app.startPerf("Reprocess pattern"); dlg = app.openDialog('Processing', 'Re-processing pattern...', false);
            cleaner = onCleanup(@() app.closeDialog(dlg, done)); %#ok<NASGU>
            app.keepOneDegree = endsWith(u.step.Value, '1°') && logical(u.step.Visible);
            if isGenericText(app.file.path)                       % reinterpret the cached generic table with the selected format
                src = readSource(app.file.path, u.fmt.Value, app.src.rawTbl);
                assert(~src.meta.isCoverage, 'The selected generic format identifies a coverage-results file.');
                app.activate(src, app.file.path);
            end
            app.refresh();
            app.status("main", ['Re-processed <b>' app.file.name '</b> with current parameters ' char(9989)], true);
        end

        function onTextFormat(app, ~, ~)
            % Re-parse immediately when the selector belongs to the active generic source.
            if strcmp(strtrim(app.ui.path.Value), app.file.path) && isGenericText(app.file.path)
                app.autoCutBasis = true; app.status("main", 'Generic format changed — reprocessing...', true); app.onProcess();
            end
        end

        function onResetParams(app, ~, ~)
            set(app.ui.paramCtrls, {'Value'}, app.defaults);
            if ~isempty(app.stdTbl), app.refresh(); end
        end

        function onFFD(app, ~, ~)
            u = app.ui; done = app.startPerf("Switch FFD block"); k = find(strcmp(u.ffd.Items, u.ffd.Value), 1);
            app.autoCutBasis = true; app.selectBlock(k); app.refresh(); done();
            app.status("main", sprintf('Switched to FFD block %d (%s).', k, u.ffd.Value), true);
        end

        function onStep(app, ~, ~)
            done = app.startPerf("Change angular step");
            app.applyStep(); app.syncComponents(app.ui.component, app.viewTbl); app.updateView(true); done();
        end

        function onSpan(app, ~, ~)
            % φ/θ display convention changed: only presentation caches are stale.
            if isempty(app.viewTbl), return; end
            done = app.startPerf("Change angular span"); app.gridCache = struct(); app.updateView(false); done();
        end

        function onComponent(app, ~, ~), app.updateView(false); end

        function onCutChanged(app, src, ~)
            u = app.ui;
            if nargin > 1 && isequal(src, u.cutType), app.syncCutControl(); end
            if nargin > 1 && isequal(src, u.cutBasis), app.autoCutBasis = false; app.updateMetadata(); end
            app.plotCut(); app.overlayCuts();
        end

        function onPlane(app, ~, ~)
            % E-/H-plane presets relative to the detected boresight axis.
            u = app.ui; A = app.Axes6; k = app.boresight;
            if strcmp(u.plane.Value, 'E'),  u.cutType.Value = 'Theta'; target = A.phi(k);
            elseif A.theta(k) == 90,        u.cutType.Value = 'Phi';   target = 90;
            else,                           u.cutType.Value = 'Theta'; target = 90;
            end
            vals = app.syncCutControl(); [~, i] = min(abs(vals - target)); u.cutValue.Value = vals(i);
            app.onCutChanged();
        end

        function onTabChanged(app, ~, ~), app.syncTips(); end

        function onExportResults(app, ~, ~)
            if isempty(app.viewTbl), return; end
            fp = app.savePath({'*.csv', 'Comma-delimited (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Results', [app.file.base '_APAT_results.csv']);
            if isempty(fp), return; end
            writeTable(app.ui.tblOut.Data, fp); app.status("main", ['Results exported to <b>' fp '</b>'], true);
        end

        function onExportUAN(app, ~, ~)
            if app.src.meta.isGainOnly, uialert(app.ui.fig, 'No E-field data to export.', 'Export UAN'); return; end
            T = app.viewTbl;
            U = sortrows(table(T.Theta, T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'}), {'Phi', 'Theta'});
            step = gridStep(U.Theta); if ~isfinite(step), step = 1; end
            fp = app.savePath({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'Comma-delimited (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'}, ...
                'Export UAN / E-field data', sprintf('%s_%.5f_%gdeg.uan', app.file.base, max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan'), step));
            if isempty(fp), return; end
            dlg = app.openDialog('Saving Data', 'Writing file...', false); cleaner = onCleanup(@() app.closeDialog(dlg)); %#ok<NASGU>
            if endsWith(fp, '.uan', 'IgnoreCase', true), writeUAN(U, fp); else, writeTable(U, fp); end
            app.status("main", ['UAN exported to <b>' fp '</b>'], true);
        end

        function onExportCut(app, ~, ~)
            if isempty(app.viewTbl), return; end
            [a, V, ~, ttl] = app.cutData(); c = app.cutCols();
            fp = app.savePath({'*.csv', 'Comma-delimited (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'}, 'Export Cut', [app.file.base '_cut.csv']);
            if isempty(fp), return; end
            writeTable(array2table([a, V], 'VariableNames', [{'Angle_deg'}, c.names]), fp);
            app.status("main", ['Cut (' ttl ') exported to <b>' fp '</b>'], true);
        end
    end

    %% ------------------------------------------------------------------ dialogs & file helpers
    methods (Access = private)
        function fp = browse(app, ttl, current)
            % File chooser; re-selecting the already loaded file (CURRENT) asks for another one.
            filters = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage files'; '*.*', 'All files'};
            while true
                [f, p] = uigetfile(filters, ttl); fp = '';
                if isequal(f, 0), return; end
                fp = fullfile(p, f); if ~strcmp(fp, current), return; end
                c = uiconfirm(app.ui.fig, sprintf('"<b>%s</b>" is already loaded', f), 'File Already Loaded', 'Options', {'Select Another File', 'Cancel'}, ...
                    'DefaultOption', 1, 'CancelOption', 2, 'Interpreter', 'html');
                if strcmp(c, 'Cancel'), fp = ''; return; end
            end
        end

        function fp = savePath(app, filters, ttl, name)
            [f, p] = uiputfile(filters, ttl, fullfile(app.file.folder, name)); fp = '';
            if ~isequal(f, 0), fp = fullfile(p, f); end
        end

        function dlg = openDialog(app, ttl, msg, cancelable)
            dlg = uiprogressdlg(app.ui.fig, 'Title', ttl, 'Message', msg, 'Indeterminate', 'on', 'Cancelable', cancelable, 'CancelText', 'Abort');
            app.opDialog = dlg; drawnow;
        end

        function closeDialog(app, dlg, done)
            if nargin > 2, done(); end
            if isequal(app.opDialog, dlg), app.opDialog = []; end
            if isvalid(dlg), close(dlg); end
        end

        function src = readWithFormat(app, fp, lbl, dd)
            % Read FP.  Generic text files expose the format selector; every other format is self-describing.
            generic = isGenericText(fp); fmtSel = string(dd.Value); if generic, fmtSel = "gain"; end
            src = readSource(fp, fmtSel, table());
            if generic && ~src.meta.isCoverage, dd.Value = 'gain'; end
            set([lbl, dd], 'Visible', generic && ~src.meta.isCoverage);
            if ~isempty(app.opDialog), app.checkCancelled(); end
        end
    end

    %% ------------------------------------------------------------------ self-test (model layer, no UI)
    methods (Static)
        function r = selfTest()
            %SELFTEST Deterministic numerical checks of the IO/model layer.  r.pass is true when every check passes.
            A = APAT_v3_M8_26.Axes6; pct = APAT_v3_M8_26.PeakPct; ex = APAT_v3_M8_26.PeakExcess; r = struct();
            [P, T] = meshgrid(0:30:330, 0:30:180);
            G = table(T(:), P(:), 10*cosd(T(:)).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            w = solidWeights(G.Theta, G.Phi);                         r.solidAngle = abs(sum(w) - 4*pi) < 1e-9;
            [pk, ax] = orientation(G, w, 'E_Total_dB', A, pct, ex);   r.orientation = isfinite(pk.value) && ax == 1;
            c = coverageCCDF(G.E_Total_dB, true(height(G), 1), [-1; 20], w); r.coverage = abs(c(1) - 100) < 1e-9 && c(2) == 0;
            [P2, T2] = meshgrid(0:2:358, 0:2:180); f = @(t, p) 12*cosd(t).^2 - 0.5*sind(p).^2;
            R = resampleCanonical(table(T2(:), P2(:), f(T2(:), P2(:)), 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'}), 1);
            native = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0 & R.Phi < 360;
            r.resampleSize = height(R) == 181*361;
            r.resampleExact = max(abs(R.E_Total_dB(native) - f(R.Theta(native), R.Phi(native)))) < 1e-9;
            r.peakRange = isequal(peakRange([3.2; -250; -17], pct, ex), [-45 5]);
            spike = repmat(0.02, 1e5, 1); spike(1) = 10.02; pk = resolvePeak(spike, pct, ex);
            r.isolatedSpike = pk.wasAdjusted && abs(pk.value - 0.02) < 1e-12 && pk.rawIndex == 1 && isequal(peakRange(spike, pct, ex), [-45 5]);
            r.percentile = abs(percentile((1:10).', 50) - 5.5) < 1e-12 && percentile((1:10).', 100) == 10;
            r.arSemantics = all(arrayfun(@isAR, ["AR" "AR_dB" "AR dB" "Axial Ratio" "Axial_Ratio"])) && ~isAR("E_Total_dB");
            a = (0:359).'; d = abs(mod(a + 180, 360) - 180);       r.hpbw = abs(calcHPBW(a, 10 - 0.1*d) - 60) < 1e-9;
            [P3, T3] = meshgrid(0:10:350, 0:10:180); n = numel(T3);  % pure RHCP source: Eφ = −i·Eθ
            E = table(T3(:), P3(:), ones(n, 1), zeros(n, 1), zeros(n, 1), -ones(n, 1), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
            E.Properties.UserData = sourceMeta('test', false, false, false); S = canonicalize(E);
            [Q, info] = computePattern(S, struct('GainLoss_dB', 0, 'FieldScale', 1, 'RxMode', "Auto", 'RxAR_dB', 0, 'Pt_dBW', 0, 'R_m', 1), pct, ex);
            r.canonicalSeam = any(S.Phi == 360) && all(S.Theta >= 0 & S.Theta <= 180) && height(S) == n + 19;
            r.circular = strcmp(info.pol, 'Circular (RHCP)') && all(abs(Q.AR_dB) < 1e-9) && all(abs(Q.E_Total_dB - 10*log10(2)) < 1e-9) && all(abs(Q.PLF_dB) < 1e-9);
            ffdFile = [tempname '.ffd']; fid = fopen(ffdFile, 'w'); cleanup = onCleanup(@() delete(ffdFile)); %#ok<NASGU>
            fprintf(fid, '0 180 3\n-180 180 3\n'); fprintf(fid, '%d 0 0 1\n', 1:9); fclose(fid);
            src = readSource(ffdFile, "ffd"); r.ffdReader = strcmp(src.meta.source, 'HFSS FFD') && isscalar(src.blocks) && height(src.blocks{1}) == 9;
            ok = structfun(@(v) v, r); k = fieldnames(r); r.pass = all(ok);
            if ~r.pass, error('APAT:SelfTest', 'Self-test failed: %s', strjoin(k(~ok), ', ')); end
        end
    end

    %% ------------------------------------------------------------------ coverage workspace
    % Tree model: root → pattern nodes (kind 'pattern': pattern, omega, comp, boresight, cache)
    %                  → results-file nodes (kind 'results')
    %                  → job nodes (kind 'job': thr, cov, line, …).  The tree IS the registry.
    methods (Access = private)
        function onToCoverage(app, ~, ~)
            % Coverage is always fed from the CURRENT Main view table (loss, step and component derivation included).
            u = app.ui; if isempty(app.viewTbl), uialert(u.fig, 'Load and process a pattern first.', 'Coverage'); return; end
            u.tabs.SelectedTab = u.tabCov; u.covPath.Value = app.file.path;
            node = app.covFind(app.file.path);
            if isempty(node), app.covAddPattern(app.file.base, app.viewTbl, app.file.path, app.viewTbl);
            else, app.covSyncFromView(node); u.covTree.SelectedNodes = node; app.setCovUI(); end
            app.status("cov", 'Coverage source synchronized from the current Main-tab View Table.', false);
        end

        function covSyncFromView(app, node)
            d = node.NodeData; d.pattern = app.viewTbl; d.sourceTable = app.viewTbl; d.name = app.file.base;
            d.omega = solidWeights(d.pattern.Theta, d.pattern.Phi); d.rev = app.viewRev;
            node.NodeData = d; app.covSync(node);
        end

        function node = covFind(app, fp)
            node = []; kids = app.ui.covRoot.Children;
            for k = 1:numel(kids)
                if strcmp(nodeKind(kids(k)), 'pattern') && strcmp(kids(k).NodeData.path, fp), node = kids(k); return; end
            end
        end

        function node = covTarget(app)
            % Pattern node to operate on: the selection (or its pattern parent), else the newest pattern node.
            node = []; sel = app.ui.covTree.SelectedNodes;
            if ~isempty(sel)
                n = sel(1); if strcmp(nodeKind(n), 'job'), n = n.Parent; end
                if strcmp(nodeKind(n), 'pattern'), node = n; return; end
            end
            kids = app.ui.covRoot.Children;
            for k = numel(kids):-1:1, if strcmp(nodeKind(kids(k)), 'pattern'), node = kids(k); return; end, end
        end

        function jobs = covJobs(app, roots)
            % Job nodes below ROOTS (default: everything), sorted by run id.
            if nargin < 2, roots = app.ui.covRoot; end
            nodes = descendants(roots); jobs = nodes(arrayfun(@(n) strcmp(nodeKind(n), 'job'), nodes));
            if numel(jobs) > 1, [~, o] = sort(arrayfun(@(n) n.NodeData.id, jobs)); jobs = jobs(o); end
        end

        function covSync(app, node)
            % Align component / orientation controls and the automatic threshold preset with a pattern node.
            u = app.ui; d = node.NodeData; T = d.pattern;
            prefer = u.covComp.Value; if isfield(d, 'comp'), prefer = d.comp; end
            app.syncComponents(u.covComp, T, prefer); col = u.covComp.Value;
            if ~isfield(d, 'comp') || ~strcmp(d.comp, col)
                [~, d.boresight] = orientation(T, d.omega, col, app.Axes6, app.PeakPct, app.PeakExcess); d.comp = col; node.NodeData = d;
                if u.covOrient.Value == 0, app.onCovOrientation(); end   % Auto: seed the cone centre from the detected axis
            end
            key = string(sprintf('%s|%s|%d', d.path, col, d.rev));
            if app.covPreset ~= key, app.setCovRange(peakRange(T.(col), app.PeakPct, app.PeakExcess), "threshold"); app.covPreset = key; end
        end

        function covAddPattern(app, name, T, fp, sourceTable)
            u = app.ui; node = uitreenode(u.covRoot, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', 'pattern', 'name', name, 'path', fp, 'pattern', T, 'omega', solidWeights(T.Theta, T.Phi), ...
                'sourceTable', sourceTable, 'rev', app.viewRev, 'cache', struct());
            expand(u.covTree); u.covTree.CheckedNodes = [u.covTree.CheckedNodes; node]; u.covTree.SelectedNodes = node;
            app.covSync(node); app.setCovUI(); u.covResults.Visible = 'on';
            app.status("cov", sprintf('Pattern "<b>%s</b>" added %s ready to compute coverage.', name, char(8212)), false);
        end

        function P = buildPattern(app, src)
            % Auxiliary pattern (block 1) processed with the current parameters, without touching Main-tab state.
            S = canonicalize(src.blocks{1}); S.Properties.UserData = src.meta;
            P = computePattern(S, app.params(), app.PeakPct, app.PeakExcess);
        end

        function thr = covThresholds(app)
            % Threshold vector exactly as entered (the automatic preset only runs when pattern/component/view change).
            u = app.ui; lo = u.thrMin.Value; hi = u.thrMax.Value; st = max(u.thrStep.Value, 0.1);
            if hi <= lo, hi = min(100, lo + st); u.thrMax.Value = hi; end
            thr = (lo:st:hi).'; if thr(end) < hi, thr(end+1, 1) = hi; end
        end

        function setCovUI(app)
            % Parameter-panel mode: "pattern" (a pattern node exists) | "results" (only result files) | "empty".
            u = app.ui; mode = "empty"; hasJobs = ~isempty(app.covJobs());
            if ~isempty(app.covTarget()), mode = "pattern"; elseif hasJobs, mode = "results"; end
            ctrls = u.covParamGrid.Children;
            if mode == "pattern"
                set(ctrls, 'Visible', 'on', 'Enable', 'on');
                set([u.covExport, u.covClear, u.queryCtrls], 'Enable', hasJobs);
                set([u.covFmtLbl, u.covFmt], 'Visible', isGenericText(u.covPath.Value));
                app.onCovType();
            else
                set(ctrls, 'Visible', 'off');
                on = [u.covPathLbl, u.covPath, u.covLoad, u.covCompute];
                if mode == "results", on = [on, u.queryCtrls, u.covReset, u.covExport, u.covClear, u.covToMain]; end
                set(on, 'Visible', 'on', 'Enable', 'on');
            end
        end

        function setCovRange(app, r, mode)
            % "threshold": preset the threshold spinners (only widening after first use).  "plot": X axis + range controls.
            u = app.ui; r = clampRange(r, app.DbRange, 1);
            if mode == "threshold"
                if app.covThrInit, r = [min(u.thrMin.Value, r(1)), max(u.thrMax.Value, r(2))]; end
                u.thrMin.Limits = [app.DbRange(1), r(2) - 0.1]; u.thrMax.Limits = [r(1) + 0.1, app.DbRange(2)];
                u.thrMin.Value = r(1); u.thrMax.Value = r(2); app.covThrInit = true;
            else
                if app.covXInit, r = [min(u.covAx.XLim(1), r(1)), max(u.covAx.XLim(2), r(2))]; end
                app.covXInit = true; app.covSyncing = true; c = onCleanup(@() app.endCovSync()); %#ok<NASGU>
                set(u.covAx, 'XLimMode', 'manual', 'XLim', r); syncRange(u.xRange, u.xMin, u.xMax, r, 0.1, app.DbRange, true);
            end
        end

        function endCovSync(app), if ~app.isClosing, app.covSyncing = false; end, end

        function onCovXRange(app, src, evt)
            % The two spinners are the master (they define the slider travel); the slider only selects inside it.
            u = app.ui; if app.covSyncing, return; end
            if isequal(src, u.xRange)
                r = sort(evt.Value); if diff(r) <= 0, return; end
                u.xMin.Value = r(1); u.xMax.Value = r(2); set(u.covAx, 'XLimMode', 'manual', 'XLim', r); return
            end
            r = sort([u.xMin.Value, u.xMax.Value]);
            if diff(r) <= 0, if isequal(src, u.xMin), r(2) = min(app.DbRange(2), r(1) + 0.1); else, r(1) = max(app.DbRange(1), r(2) - 0.1); end, end
            app.covSyncing = true; c = onCleanup(@() app.endCovSync()); %#ok<NASGU>
            syncRange(u.xRange, u.xMin, u.xMax, r, 0.1, app.DbRange, true); set(u.covAx, 'XLimMode', 'manual', 'XLim', r);
        end

        function onCovLoad(app, ~, ~)
            u = app.ui; fp = strtrim(u.covPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFind(fp))
                fp = app.browse('Select a pattern or coverage results file', ''); if isempty(fp), return; end
            end
            existing = app.covFind(fp);
            if ~isempty(existing)
                u.covTree.SelectedNodes = existing; app.onCovSelect(); u.covPath.Value = fp; app.setCovUI();
                app.status("cov", 'File already loaded -- node selected. Add another job or load a different file.', true); return
            end
            u.covPath.Value = fp; src = app.readWithFormat(fp, u.covFmtLbl, u.covFmt);
            if src.meta.isCoverage
                t = app.covTarget(); if ~isempty(t), u.covPath.Value = t.NodeData.path; end
                app.covLoadResults(fp, src.rawTbl);
            else
                [~, name] = fileparts(fp); app.covAddPattern(name, app.buildPattern(src), fp, src.rawTbl);
            end
        end

        function onCovTextFormat(app, ~, ~)
            % Re-interpret an already loaded generic coverage pattern with the newly selected text format.
            u = app.ui; fp = strtrim(u.covPath.Value); old = app.covFind(fp);
            if isempty(old) || ~isGenericText(fp) || ~isfile(fp), return; end
            src = readSource(fp, u.covFmt.Value, old.NodeData.sourceTable);
            if src.meta.isCoverage, app.status("cov", 'Coverage-result format is detected automatically; no pattern reprocessing required.', true); return; end
            name = old.NodeData.name;
            for j = old.Children(:).', delete(j.NodeData.line); end
            delete(old); app.covAddPattern(name, app.buildPattern(src), fp, src.rawTbl); app.covFinalize();
            app.status("cov", sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
        end

        function covLoadResults(app, fp, R)
            u = app.ui; [~, name] = fileparts(fp);
            node = uitreenode(u.covRoot, 'Text', ['📄 ' name]); node.NodeData = struct('kind', 'results', 'name', name, 'path', fp);
            thr = R{:, 1}; app.setCovRange([min(thr), max(thr)], "plot");
            st = gridStep(thr); if isfinite(st) && st < u.thrStep.Value, u.thrStep.Value = st; end
            for k = 2:width(R), app.covAddJob(node, thr, R{:, k}, 'Res', R.Properties.VariableNames{k}, struct()); end
            u.covTree.CheckedNodes = [u.covTree.CheckedNodes; node; node.Children];
            app.covFinalize(); u.covResults.Visible = 'on';
            app.status("cov", sprintf('Coverage results file "%s" loaded (%d curves).', name, width(R) - 1), false);
        end

        function job = covAddJob(app, parent, thr, cov, tag, col, extra)
            % Plot one CCDF curve and register it as a job node under PARENT (EXTRA overrides node fields).
            u = app.ui; app.covRunID = app.covRunID + 1;
            icon = '📉'; if strcmp(tag, 'Res'), icon = '📈'; end
            label = sprintf('%s R%d %s · %s', icon, app.covRunID, tag, col);
            [icov, ii] = unique(cov, 'last');
            d = struct('kind', 'job', 'id', app.covRunID, 'tableTag', tag, 'label', label, 'thr', thr(:), 'cov', cov(:), 'invCov', icov, 'invThr', thr(ii), ...
                'line', plot(u.covAx, thr, cov, 'LineWidth', 1.6, 'DisplayName', label), 'isConical', false, 'orient', "n/a");
            for f = fieldnames(extra).', d.(f{1}) = extra.(f{1}); end
            job = uitreenode(parent, 'Text', label); job.NodeData = d;
        end

        function covFinalize(app)
            % Rebuild the results table (union of thresholds, curves interpolated) and the legend from checked jobs.
            u = app.ui; jobs = app.covJobs(); expand(u.covRoot);
            for j = jobs(:).', expand(j.Parent); end
            checked = jobs(isChecked(u.covTree, jobs));
            thr = app.covThresholds();
            if ~isempty(checked), c = arrayfun(@(j) j.NodeData.thr, checked, 'UniformOutput', false); thr = unique(vertcat(c{:})); end
            M = nan(numel(thr), numel(checked) + 1); M(:, 1) = thr; names = [{'Threshold (dB)'}, cell(1, numel(checked))];
            lines = gobjects(0); labels = {};
            for k = 1:numel(checked)
                d = checked(k).NodeData; M(:, k+1) = interp1(d.thr, d.cov, thr, 'linear', NaN); names{k+1} = sprintf('R%d %s %%', d.id, d.tableTag);
                if isgraphics(d.line), lines(end+1) = d.line; labels{end+1} = d.label; end %#ok<AGROW>
            end
            u.covTbl.Data = array2table(compose('%.2f', M), 'VariableNames', names);
            if isempty(lines), legend(u.covAx, 'off'); else, legend(u.covAx, lines, labels, 'Location', 'southwest', 'Interpreter', 'none'); end
            app.setCovUI();
        end

        function onCovCompute(app, ~, ~)
            u = app.ui; node = app.covTarget();
            if isempty(node), uialert(u.fig, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if ~isempty(app.viewTbl) && strcmp(node.NodeData.path, app.file.path), app.covSyncFromView(node); end   % Main pattern → current view
            done = app.startPerf("Compute coverage"); c = onCleanup(@() done()); %#ok<NASGU>
            d = node.NodeData; T = d.pattern; col = u.covComp.Value; thr = app.covThresholds();
            mask = true(height(T), 1); tag = 'Sph coverage'; key = 'Sph'; extra = struct('tableTag', 'Sph');
            if u.covCon.Value
                k = u.covOrient.Value; if k == 0, k = d.boresight; end
                th0 = u.coneTh.Value; ph0 = mod(u.conePh.Value, 360); alpha = u.coneAng.Value;
                mask = cosd(T.Theta)*cosd(th0) + sind(T.Theta)*sind(th0).*cosd(T.Phi - ph0) >= cosd(alpha);
                centre = app.coneLabel(th0, ph0); key = sprintf('Con_%.15g_%.15g_%.15g', th0, ph0, alpha);
                tag = sprintf('Conical coverage (%s) α=%s°', centre, fmt(alpha));
                extra = struct('tableTag', sprintf('Con %s α%s°', erase(centre, ["=" ","]), fmt(alpha)), 'isConical', true, 'orient', string(app.Axes6.labels{k}), 'cone', [th0 ph0 alpha]);
            end
            cacheKey = matlab.lang.makeValidName(sprintf('%s_%d_%s_%g_%g_%g_%d', col, d.rev, key, thr(1), thr(end), gridStep(thr), numel(thr)));
            hit = isfield(d.cache, cacheKey);
            if hit, cov = d.cache.(cacheKey); else, cov = coverageCCDF(T.(col), mask, thr, d.omega); d.cache.(cacheKey) = cov; node.NodeData = d; end
            job = app.covAddJob(node, thr, cov, tag, col, extra);
            u.covTree.CheckedNodes = [u.covTree.CheckedNodes; job];
            app.covFinalize(); app.setCovRange([thr(1), thr(end)], "plot"); u.covResults.Visible = 'on';
            act = 'computed'; if hit, act = 'reused cached CCDF'; end
            msg = sprintf('Run-<b>%d</b> %s: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', app.covRunID, act, tag, d.name, col, numel(thr));
            if u.covCon.Value, msg = sprintf('%s | Orientation <b>%s</b>', msg, extra.orient); end
            app.status("cov", msg, false);
        end

        function s = coneLabel(app, th, ph)
            % Principal-axis name when the cone centre matches ±X/±Y/±Z exactly, otherwise explicit θ/φ text.
            A = app.Axes6; U = [sind(A.theta).*cosd(A.phi); sind(A.theta).*sind(A.phi); cosd(A.theta)].';
            k = find(U * [sind(th)*cosd(ph); sind(th)*sind(ph); cosd(th)] >= 1 - 1e-9, 1);
            if isempty(k), s = sprintf('θ=%s°, φ=%s°', fmt(th), fmt(ph)); else, s = A.labels{k}; end
        end

        function onCovType(app, ~, ~)
            u = app.ui; on = u.covCon.Value; set(u.coneCtrls, 'Enable', on, 'Visible', on);
            if on, n = app.covTarget(); if ~isempty(n), app.covSync(n); end, app.covOrientStatus();
            else, app.status("cov", regexprep(app.sticky(2), '\s*\|\s*Orientation <b>.*?</b>', ''), false); end
        end

        function k = covAxis(app)
            % Resolved conical orientation index (Auto → detected boresight of the target pattern), [] when unavailable.
            u = app.ui; k = u.covOrient.Value;
            if k == 0, n = app.covTarget(); k = []; if ~isempty(n) && isfield(n.NodeData, 'boresight'), k = n.NodeData.boresight; end, end
        end

        function covOrientStatus(app)
            u = app.ui; k = app.covAxis(); if ~u.covCon.Value || isempty(k), return; end
            base = regexprep(char(u.covStatus.Text), '\s*\|\s*Orientation <b>.*?</b>$', '');
            app.status("cov", sprintf('%s | Orientation <b>%s</b>', base, app.Axes6.labels{k}), false);
        end

        function onCovOrientation(app, ~, ~)
            u = app.ui; k = app.covAxis(); if isempty(k), return; end
            u.coneTh.Value = app.Axes6.theta(k); u.conePh.Value = app.Axes6.phi(k); app.covOrientStatus();
        end

        function onCovComponent(app, ~, ~)
            % The user's component choice is authoritative: re-detect the orientation for it, do not re-sync.
            u = app.ui; n = app.covTarget(); if isempty(n), return; end
            d = n.NodeData; col = u.covComp.Value; if ~ismember(col, d.pattern.Properties.VariableNames), return; end
            d.comp = col; [~, d.boresight] = orientation(d.pattern, d.omega, col, app.Axes6, app.PeakPct, app.PeakExcess); n.NodeData = d;
            app.covOrientStatus();
        end

        function h = covArtifacts(app, d, mode)
            % Query projections + DataTips of one job (all modes, or only MODE = "cov" | "thr").
            if nargin < 3, h = [findall(app.ui.covAx, '-regexp', 'Tag', sprintf('^CovQ_\\w+_%d$', d.id)); findall(d.line, 'Type', 'datatip')];
            else, h = findall(app.ui.covAx, 'Tag', sprintf('CovQ_%s_%d', mode, d.id)); end
        end

        function onCovQuery(app, ~, ~, mode)
            % Project a threshold ("cov") or a coverage level ("thr") onto every checked curve under the selection.
            u = app.ui; ax = u.covAx; sel = u.covTree.SelectedNodes;
            if mode == "cov", q = u.qCov.Value; else, q = u.qThr.Value; end
            if isempty(sel), app.status("cov", 'Select a node to query.', true); return; end
            jobs = app.covJobs(sel); jobs = jobs(isChecked(u.covTree, jobs));
            if isempty(jobs), app.status("cov", 'No checked results under selected node.', true); return; end
            rows = [dataTipTextRow("Threshold", @(x, ~) arrayfun(@(v) [fmt(v) ' dB'], x, 'UniformOutput', false)); ...
                    dataTipTextRow("Coverage", @(~, y) arrayfun(@(v) [fmt(v) '%'], y, 'UniformOutput', false))];
            hit = false;
            for j = jobs(:).'
                d = j.NodeData; tag = sprintf('CovQ_%s_%d', mode, d.id); delete(app.covArtifacts(d, mode));
                if mode == "cov", x = q; y = interp1(d.thr, d.cov, q, 'linear', NaN); else, y = q; x = interp1(d.invCov, d.invThr, q, 'linear', NaN); end
                if ~isfinite(x) || ~isfinite(y), continue; end
                setTipRows(d.line, rows);
                line(ax, [x x], [ax.YLim(1) y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [app.DbRange(1) x], [y y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'HandleVisibility', 'off', 'FontSize', 9, 'Tag', tag);
                hit = true;
            end
            if ~hit, app.status("cov", 'Query value is outside selected checked range.', true);
            elseif mode == "cov", app.status("cov", sprintf('Coverage queried at %s dB.', fmt(q)), false);
            else, app.status("cov", sprintf('Threshold queried at %s%% coverage.', fmt(q)), false); end
        end

        function onCovChecked(app, ~, ~)
            u = app.ui; jobs = app.covJobs(); on = isChecked(u.covTree, jobs);
            for k = 1:numel(jobs), d = jobs(k).NodeData; set([d.line; app.covArtifacts(d)], 'Visible', on(k)); end
            app.covFinalize();
        end

        function onCovSelect(app, ~, ~)
            u = app.ui; sel = u.covTree.SelectedNodes;
            for j = app.covJobs().', d = j.NodeData; d.line.LineWidth = 1.6; end
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.status("cov", 'Ready.', false); return; end
            d = sel(1).NodeData; t = app.covTarget(); if ~isempty(t), app.covSync(t); end
            if ~strcmp(d.kind, 'job')
                n = numel(sel(1).Children); kindName = 'Pattern'; if strcmp(d.kind, 'results'), kindName = 'Results'; end
                app.status("cov", sprintf('%s <b>"%s"</b> -- <b>%d</b> coverage job%s.', kindName, d.name, n, repmat('s', 1, n ~= 1)), false);
                if strcmp(d.kind, 'pattern') && u.covCon.Value, app.covOrientStatus(); end
                return
            end
            d.line.LineWidth = 2.6;                                % selection = visual emphasis only
            parts = {char(d.label)};
            if d.isConical, parts{end+1} = sprintf('Orientation <b>%s</b>', d.orient); end
            parts{end+1} = sprintf('Threshold [%s, %s] dB | Step %s dB', fmt(d.thr(1)), fmt(d.thr(end)), fmt(gridStep(d.thr)));
            t50 = interp1(d.invCov, d.invThr, 50, 'linear', NaN);
            if isfinite(t50), parts{end+1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', fmt(t50)); else, parts{end+1} = '<b>50%-coverage unavailable</b>'; end
            ok = isfinite(d.cov) & isfinite(d.thr);
            if any(ok), shown = round(d.cov(ok), 2); thrOK = d.thr(ok); k = find(shown == max(shown), 1, 'last'); ...
                    parts{end+1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmt(shown(k)), fmt(thrOK(k)));
            else, parts{end+1} = 'max <b>n/a</b>'; end
            app.status("cov", strjoin(parts, ' | '), false);
        end

        function onCovReset(app, ~, ~)
            u = app.ui;
            delete(findall(u.covAx, 'Type', 'datatip')); delete(u.covRoot.Children);
            cla(u.covAx); legend(u.covAx, 'off'); hold(u.covAx, 'on'); grid(u.covAx, 'on'); ylim(u.covAx, [0 100]); set(u.covAx, 'Box', 'on', 'Layer', 'top', 'XLimMode', 'auto');
            u.covTbl.Data = table(); app.covRunID = 0; app.covPreset = ""; app.covXInit = false; app.covThrInit = false;
            syncRange(u.xRange, u.xMin, u.xMax, [-40 10], 0.1, app.DbRange, true);
            u.covResults.Visible = 'off'; app.setCovUI();
            app.status("cov", 'Coverage workspace reset 🔄', true);
        end

        function onCovClear(app, ~, ~)
            u = app.ui; sel = u.covTree.SelectedNodes;
            if isempty(sel), app.status("cov", 'Select a node to clear.', true); return; end
            jobs = app.covJobs(sel);
            if isempty(jobs), app.status("cov", 'No coverage results under selected node.', true); return; end
            for j = jobs(:).', delete(app.covArtifacts(j.NodeData)); end
            app.status("cov", 'Selected DataTips and query markers cleared.', true);
        end

        function onCovExport(app, ~, ~)
            if isempty(app.ui.covTbl.Data), return; end
            fp = app.savePath({'*.csv', 'Comma-delimited (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Coverage Results', 'coverage_results.csv');
            if isempty(fp), return; end
            writeTable(app.ui.covTbl.Data, fp); app.status("cov", ['Coverage results exported to ' fp], true);
        end
    end
end

%% ======================================================================= IO layer (UI-free local functions)
function src = readSource(fp, fmt, cached)
%READSOURCE Parse any supported file into src = struct(rawTbl, blocks, freqs, meta).
%   blocks{k} are canonical field tables {Theta,Phi,Re_Eth,Im_Eth,Re_Eph,Im_Eph} (or one gain table for
%   gain-only sources).  FMT selects the interpretation of generic text files; CACHED is an already parsed
%   generic table (skips re-reading the file on re-interpretation).
if nargin < 3, cached = table(); end
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
switch ext
    case {'XLSX', 'XLS'},                        src = readExcel(fp);
    case {'CSV', 'TXT', 'DAT'},                  src = readText(fp, string(fmt), cached);
    case 'CUT',                                  src = readCut(fp);
    case {'FZ', 'UAN', 'OUT', 'FFS', 'FFE', 'FFD'}, src = readFarField(fp, ext);
    otherwise, error('APAT:io:Unsupported', 'Unsupported format: %s', ext);
end
end

function meta = sourceMeta(source, isGainOnly, isCoverage, isDep)
meta = struct('source', char(source), 'isGainOnly', isGainOnly, 'isCoverage', isCoverage, 'isDep', isDep);
end

function src = packSource(raw, blocks, freqs, meta)
src = struct('rawTbl', raw, 'blocks', {blocks}, 'freqs', freqs, 'meta', meta);
end

function T = fieldTable(th, ph, Eth, Eph)
%FIELDTABLE Canonical complex-field block.
T = table(th(:), ph(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function E = fromMagPhase(dB, deg), E = 10.^(dB/20) .* exp(1i*deg2rad(deg)); end
function [Eth, Eph] = fromCircular(Er, El), Eth = (Er + El)/sqrt(2); Eph = (Er - El)/(1i*sqrt(2)); end
function tf = isGenericText(fp), [~, ~, e] = fileparts(fp); tf = any(strcmpi(e, {'.csv', '.txt', '.dat'})); end

function src = readFarField(fp, ext)
%READFARFIELD XGTD UAN/FZ, TICRA OUT, CST FFS, FEKO FFE and HFSS FFD (multi-block) files.
[nHdr, ffd] = scanHeader(fp);
o = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = readmatrix(fp, setvartype(o, o.VariableNames, 'double')); M = M(~all(isnan(M), 2), 1:min(end, 6));
if strcmp(ext, 'FFD')
    assert(ffd.isFFD, 'APAT:io:FFD', 'FFD header (theta/phi ranges) not found.');
    th = linspace(ffd.theta(1), ffd.theta(2), ffd.theta(3)).'; ph = linspace(ffd.phi(1), ffd.phi(2), ffd.phi(3)).';
    TH = repelem(th, numel(ph)); PH = repmat(ph, numel(th), 1); n = numel(TH);
    sep = isnan(M(:, 1)); freqs = [ffd.freq(:); M(sep & ~isnan(M(:, 2)), 2)].';    % "Frequency <f>" separator rows
    rows = M(~sep, 1:4);
    assert(mod(size(rows, 1), n) == 0, 'APAT:io:FFD', 'FFD mismatch: row count does not match the theta/phi grid.');
    nb = size(rows, 1)/n; freqs(end+1:nb) = NaN; freqs = freqs(1:nb); blocks = cell(1, nb);
    for b = 1:nb, r = rows((b-1)*n + (1:n), :); blocks{b} = fieldTable(TH, PH, complex(r(:, 1), r(:, 2)), complex(r(:, 3), r(:, 4))); end
    src = packSource(blocks{1}, blocks, freqs, sourceMeta('HFSS FFD', false, false, nb > 1 || any(isfinite(freqs)))); return
end
switch ext
    case {'FZ', 'UAN'}, names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}; Eth = fromMagPhase(M(:, 3), M(:, 5)); Eph = fromMagPhase(M(:, 4), M(:, 6)); source = ['XGTD ' ext];
    case 'OUT',         names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; [Eth, Eph] = fromCircular(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6))); source = 'TICRA/GRASP OUT';
    case 'FFS',         names = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6)); source = 'CST FFS';
    case 'FFE',         names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6)); source = 'FEKO FFE';
end
raw = array2table(M(:, 1:6), 'VariableNames', names);
src = packSource(raw, {fieldTable(raw.Theta, raw.Phi, Eth, Eph)}, NaN, sourceMeta(source, false, false, false));
end

function [nHdr, ffd] = scanHeader(fp)
%SCANHEADER Count leading non-data lines and parse the optional HFSS FFD header:
%   two numeric triples "start stop count" (theta, phi) followed by an optional "Frequencies …" line.
ffd = struct('theta', [], 'phi', [], 'freq', [], 'isFFD', false);
L = strtrim(readlines(fp)); ne = find(strlength(L) > 0, 3);
tri = cellfun(@(s) sscanf(s, '%f').', cellstr(L(ne(1:min(2, end)))), 'UniformOutput', false);
if numel(tri) == 2 && all(cellfun(@numel, tri) == 3)
    ffd.theta = tri{1}; ffd.phi = tri{2}; ffd.theta(3) = round(ffd.theta(3)); ffd.phi(3) = round(ffd.phi(3));
    ffd.isFFD = all(isfinite([ffd.theta, ffd.phi])) && all([ffd.theta(3), ffd.phi(3)] >= 1);
    nHdr = ne(2);
    if numel(ne) == 3
        tok = regexp(char(L(ne(3))), '^frequencies?\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok), nHdr = ne(3); f = sscanf(char(tok{1}), '%f'); if numel(f) > 1, ffd.freq = f(:); end, end   % a lone count is metadata only
    end
    if ffd.isFFD, return; end
end
num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?'; pat = ['^' num '(?:[\s,;]+' num '){3,}$'];   % first line with ≥4 numeric fields
nHdr = numel(L);
for k = 1:numel(L), if ~isempty(regexp(char(L(k)), pat, 'once')), nHdr = k - 1; break; end, end
end

function src = readText(fp, fmt, T)
%READTEXT Generic CSV/TXT/DAT: coverage results, gain-only pattern, or a 6-column E-field table (FMT = interpretation).
if isempty(T)
    o = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    o = setvaropts(setvartype(o, 'double'), 'TrimNonNumeric', true); o.VariableNamingRule = 'preserve';
    T = rmmissing(readtable(fp, o));
end
nc = width(T); assert(nc >= 2 && ~isempty(T), 'APAT:io:Text', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHeaders = ~all(startsWith(names, "Var")); c1 = T{:, 1}; c2 = T{:, 2}; raw = T;
covHeader = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
if (fmt == "gain" || nc < 6 || covHeader) && all(isfinite(c2)) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:nc-1))]; end
    src = packSource(T, {}, NaN, sourceMeta('Coverage results', false, true, false)); return
end
if fmt == "gain"                                                  % angles first; the wider span is φ
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    T = movevars(T, 'Theta', 'Before', 1); if ~hasHeaders, raw = T; end
    src = packSource(raw, {T}, NaN, sourceMeta('Generic text (gain)', true, false, false)); return
end
assert(nc >= 6, 'APAT:io:Text', 'The selected generic E-field format requires six numeric columns.');
F = T{:, 3:6}; layout = "not applicable";
if endsWith(fmt, "magphase")
    layout = "grouped"; big = max(abs(F), [], 1, 'omitnan') > 100;   % phase columns exceed ±100
    if big(2) && ~big(3), layout = "interleaved"; F = F(:, [1 3 2 4]); end
    C1 = fromMagPhase(F(:, 1), F(:, 3)); C2 = fromMagPhase(F(:, 2), F(:, 4));
else
    C1 = complex(F(:, 1), F(:, 2)); C2 = complex(F(:, 3), F(:, 4));
end
base = ["POL1" "POL2"]; rect = ["POL1_real" "POL1_imag" "POL2_real" "POL2_imag"];
if startsWith(fmt, "linear"), [Eth, Eph] = deal(C1, C2); base = ["E_TH" "E_PH"]; rect = ["Re_Eth" "Im_Eth" "Re_Eph" "Im_Eph"];
elseif startsWith(fmt, "rcp"), [Eth, Eph] = fromCircular(C1, C2);
else,                          [Eth, Eph] = fromCircular(C2, C1);
end
if ~hasHeaders
    gen = rect;
    if endsWith(fmt, "magphase"), gen = [base + "_dB", base + "_deg"]; if layout == "interleaved", gen = gen([1 3 2 4]); end, end
    raw.Properties.VariableNames(1:6) = cellstr(["Theta" "Phi" gen]);
end
src = packSource(raw, {fieldTable(c1, c2, Eth, Eph)}, NaN, sourceMeta(sprintf('Generic text (%s, %s)', fmt, layout), false, false, false));
end

function src = readCut(fp)
%READCUT TICRA/GRASP *.cut: repeated blocks [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data rows].
L = readlines(fp); L(strlength(strtrim(L)) == 0) = [];
TH = {}; PH = {}; D = {}; k = 1; icomp = 1; icut = 1;
while k < numel(L)
    p = sscanf(L(k+1), '%f'); assert(numel(p) >= 7, 'APAT:io:Cut', 'Could not parse the cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6);
    B = reshape(sscanf(strjoin(L(k+2:k+1+n), ' '), '%f'), 2*p(7), []).';
    TH{end+1} = p(1) + (0:n-1).'*p(2); PH{end+1} = repmat(p(4), n, 1); D{end+1} = B(:, 1:4); k = k + 2 + n; %#ok<AGROW>
end
th = vertcat(TH{:}); ph = vertcat(PH{:}); D = vertcat(D{:});
if icut == 2, [th, ph] = deal(ph, th); end                       % ICUT=2: φ swept, θ constant
neg = th < 0; ph(neg) = ph(neg) + 180; th(neg) = -th(neg);         % fold negative θ onto the opposite φ
if isscalar(unique(ph))                                            % single cut → body of revolution
    reps = (0:10:350).'; m = numel(th); th = repmat(th, numel(reps), 1); ph = repelem(reps, m); D = repmat(D, numel(reps), 1);
end
if icomp == 2, names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; [Eth, Eph] = fromCircular(complex(D(:, 1), D(:, 2)), complex(D(:, 3), D(:, 4)));
else,          names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'};    Eth = complex(D(:, 1), D(:, 2)); Eph = complex(D(:, 3), D(:, 4));
end
raw = array2table([th, ph, D], 'VariableNames', [{'Theta', 'Phi'}, names]);
src = packSource(raw, {fieldTable(th, ph, Eth, Eph)}, NaN, sourceMeta('TICRA/GRASP CUT', false, false, false));
end

function src = readExcel(fp)
%READEXCEL Excel matrix workbooks: sheet 1 = summary; fixed component sheets holding dBi / degree matrices (C3 origin).
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi" "RHCP_Phase_degrees" "LHCP_Gain_dBi" "LHCP_Phase_degrees"];
lin  = ["Etheta_Gain_dBi" "Etheta_Phase_degrees" "Ephi_Gain_dBi" "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'APAT:io:Excel', 'Unsupported Excel workbook: expected Etheta/Ephi and/or RHCP/LHCP component sheets after the summary sheet.');
need = [circ(1:4*hasC), lin(1:4*hasL)]; X = struct(); th = []; ph = [];
for s = need
    [t, p, Mx] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, s), 1)));
    if isempty(th), th = t; ph = p;
    else, assert(isequal(size(t), size(th)) && isequal(size(p), size(ph)) && max(abs(t - th)) < 1e-9 && max(abs(p - ph)) < 1e-9, 'APAT:io:Excel', 'All component sheets must share the same theta/phi grid.');
    end
    X.(char(s)) = Mx;
end
if hasL, Eth = fromMagPhase(X.Etheta_Gain_dBi, X.Etheta_Phase_degrees); Eph = fromMagPhase(X.Ephi_Gain_dBi, X.Ephi_Phase_degrees);
else,    [Eth, Eph] = fromCircular(fromMagPhase(X.RHCP_Gain_dBi, X.RHCP_Phase_degrees), fromMagPhase(X.LHCP_Gain_dBi, X.LHCP_Phase_degrees));
end
[PH, TH] = meshgrid(ph, th); block = fieldTable(TH, PH, Eth, Eph); raw = block;
for s = need, raw.(char(s)) = reshape(X.(char(s)), [], 1); end
formats = {'Excel Matrix Format 1 (Eth/Eph)', 'Excel Matrix Format 2 (Ercp/Elcp)', 'Excel Matrix Format 3 (Ercp/Elcp + Eth/Eph)'};
meta = sourceMeta(formats{hasL + 2*hasC}, false, false, false); meta.summary = readSummary(fp, sheets(1));
src = packSource(raw, {block}, NaN, meta);
end

function [th, ph, X] = readMatrixSheet(fp, sheet)
%READMATRIXSHEET One C3-origin matrix (row 2 = φ axis from C, column B = θ axis from row 3).  readcell keeps coordinates.
C = readcell(fp, 'Sheet', char(sheet));
assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'APAT:io:Excel', 'Sheet "%s" does not contain a C3-origin matrix.', sheet);
isnum = @(c) cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), c);
pm = isnum(C(2, 3:end)); tm = isnum(C(3:end, 2));
assert(any(pm) && any(tm) && ~any(diff(pm) > 0) && ~any(diff(tm) > 0), 'APAT:io:Excel', 'Sheet "%s" has an empty or non-contiguous theta/phi axis.', sheet);
ph = cellfun(@double, C(2, 2 + (1:nnz(pm)))).'; th = cellfun(@double, C(2 + (1:nnz(tm)), 2));
D = C(2 + (1:numel(th)), 2 + (1:numel(ph)));
assert(all(isnum(D), 'all'), 'APAT:io:Excel', 'Sheet "%s" contains non-numeric/missing matrix samples.', sheet);
X = cellfun(@double, D);
assert(all(diff(th) > 0) && all(diff(ph) > 0) && th(1) >= -1e-9 && th(end) <= 180 + 1e-9 && ph(1) >= -1e-9 && ph(end) < 360 + 1e-9, ...
    'APAT:io:Excel', 'Sheet "%s" axes must be increasing within theta 0..180 and phi 0..360.', sheet);
end

function S = readSummary(fp, sheet)
%READSUMMARY Summary-sheet label/value pairs (label in column B, first non-empty value in C..E) as an N×2 cell.
S = cell(0, 2);
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
for r = 1:size(C, 1)
    lab = C{r, 2}; if ~(ischar(lab) || isstring(lab)) || strlength(strtrim(string(lab))) == 0, continue; end
    v = C(r, 3:min(end, 5)); v = v(cellfun(@(x) ~isempty(x) && ~isa(x, 'missing'), v)); if isempty(v), continue; end
    val = v{1}; if isnumeric(val), val = num2str(val); else, val = char(string(val)); end
    S(end+1, :) = {char(regexprep(strtrim(string(lab)), '\s*:\s*$', '')), val}; %#ok<AGROW>
end
end

function writeTable(T, fp)
%WRITETABLE TXT is tab-delimited; CSV/XLSX use writetable defaults.
if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
end

function writeUAN(U, fp)
%WRITEUAN XGTD UAN: canonical free-format header followed by Theta Phi |Eθ|dB |Eφ|dB ∠Eθ ∠Eφ rows.
hdr = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
    min(U.Phi), max(U.Phi), gridStep(U.Phi), min(U.Theta), max(U.Theta), gridStep(U.Theta), max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan'));
writelines(hdr, fp); writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
end

%% ======================================================================= model layer (UI-free local functions)
function T = canonicalize(T)
%CANONICALIZE Map angles onto the canonical sphere: θ∈[0,180], φ∈[0,360) plus one closing φ=360 copy of φ=0.
%   Only the ANGLE columns are rounded (1e-6°) to remove floating-point seam artefacts; field values are untouched.
th = T.Theta; ph = T.Phi;
if any(th < 0)
    if min(th, [], 'omitnan') >= -90 && max(th, [], 'omitnan') <= 90, th = 90 - th;      % elevation source
    else, neg = th < 0; ph(neg) = ph(neg) + 180; th = abs(th);                        % negative polar angle → opposite φ
    end
end
th = mod(th, 360); over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;
T.Theta = round(th, 6); T.Phi = round(mod(ph, 360), 6);
[~, i] = unique([T.Phi, T.Theta], 'rows', 'first'); T = T(i, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function step = gridStep(v)
%GRIDSTEP Smallest positive spacing between distinct finite values (NaN when undefined).
d = diff(unique(v(isfinite(v)))); d = d(d > 1e-9);
if isempty(d), step = NaN; else, step = min(d); end
end

function w = solidWeights(th, ph)
%SOLIDWEIGHTS Exact solid angle of each uniform θ/φ cell; the closing φ=360 seam gets zero weight.
dt = gridStep(th); dp = gridStep(ph); if ~isfinite(dt), dt = 180; end, if ~isfinite(dp), dp = 360; end
w = (cosd(max(th - dt/2, 0)) - cosd(min(th + dt/2, 180))) * deg2rad(dp);
w(abs(ph - 360) < 1e-9) = 0;
end

function p = resolvePeak(v, pct, ex)
%RESOLVEPEAK Outlier-robust peak: the raw maximum is accepted unless it exceeds the PCT percentile by more
%   than EX dB, in which case the largest sample at/below the percentile becomes the effective peak.
v = double(v(:)); ok = isfinite(v);
p = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(v)), 'wasAdjusted', false);
if ~any(ok), return; end
[p.rawValue, p.rawIndex] = max(v, [], 'omitnan'); p.value = p.rawValue; p.index = p.rawIndex;
cut = percentile(v(ok), pct);
if p.rawValue > cut + ex
    p.outlierMask = ok & v > cut; c = v; c(~ok | p.outlierMask) = -Inf;
    if any(isfinite(c)), [p.value, p.index] = max(c); p.wasAdjusted = true; end
end
end

function q = percentile(x, pct)
%PERCENTILE prctile-compatible percentile (midpoint positions, end clamping) without toolbox dependency.
x = sort(x(:)); n = numel(x);
if n == 1, q = x; return; end
pos = 100*((1:n) - 0.5)/n; q = interp1(pos, x, min(max(pct, pos(1)), pos(end)), 'linear');
end

function r = peakRange(v, pct, ex)
%PEAKRANGE 50-dB display / threshold window whose top is the outlier-robust peak rounded up to 5 dB.
v = double(v(isfinite(v))); if isempty(v), r = [-50 0]; return; end
top = min(100, ceil(resolvePeak(v, pct, ex).value/5)*5); r = [max(-250, top - 50), top];
end

function r = clampRange(v, b, gap)
%CLAMPRANGE Sorted range inside bounds B with at least GAP between its ends.
v = sort(double(v(:).')); if numel(v) < 2 || any(~isfinite(v(1:2))), r = b; return; end
r = [max(b(1), v(1)), min(b(2), v(2))];
if diff(r) < gap, r(2) = min(b(2), r(1) + gap); r(1) = max(b(1), r(2) - gap); end
end

function [g, col] = chooseGain(T, col)
%CHOOSEGAIN Requested column, else Total Gain, else the first data column.
vars = T.Properties.VariableNames; c = [cellstr(col), {'E_Total_dB'}]; i = find(ismember(c, vars), 1);
if isempty(i), col = vars{3}; else, col = c{i}; end
g = T.(col);
end

function [pk, axisIndex] = orientation(T, w, col, A, pct, ex)
%ORIENTATION Peak of COL and the principal axis whose 45° cone captures the most peak-normalized power.
g = chooseGain(T, col); pk = resolvePeak(g, pct, ex); g(pk.outlierMask) = NaN;
sw = 10.^((g - pk.value)/10) .* w; sw(~isfinite(sw)) = 0;
V = [sind(T.Theta).*cosd(T.Phi), sind(T.Theta).*sind(T.Phi), cosd(T.Theta)];
U = [sind(A.theta(:)).*cosd(A.phi(:)), sind(A.theta(:)).*sind(A.phi(:)), cosd(A.theta(:))];
[~, axisIndex] = max(sw.' * double(V*U.' >= cosd(45)));
end

function m = computeMetrics(T, w, A, axisIndex, pct, ex)
%COMPUTEMETRICS Scalar antenna metrics on Total Gain: directivity, efficiency, front-to-back, E/H-plane HPBW, AR at peak.
g = chooseGain(T, 'E_Total_dB'); pk = resolvePeak(g, pct, ex); i = pk.index;
gm = g; gm(pk.outlierMask) = NaN; P = sum(10.^(gm/10) .* w, 'omitnan');
eff = 100*P/(4*pi); if eff < 0 || eff > 100, eff = NaN; end
[~, back] = min(cosd(T.Theta)*cosd(T.Theta(i)) + sind(T.Theta)*sind(T.Theta(i)).*cosd(T.Phi - T.Phi(i)));   % antipode of the peak
hType = 'Theta'; if A.theta(axisIndex) == 90, hType = 'Phi'; end
[ea, er] = cutGeometry(T, 'Theta', A.phi(axisIndex)); [ha, hr] = cutGeometry(T, hType, 90);
ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(i); end
m = struct('PeakGain_dB', pk.value, 'PeakTheta_deg', T.Theta(i), 'PeakPhi_deg', T.Phi(i), 'HPBW_EPlane_deg', calcHPBW(ea, g(er)), 'HPBW_HPlane_deg', calcHPBW(ha, g(hr)), ...
    'FrontBack_dB', pk.value - g(back), 'PeakDirectivity_dB', 10*log10(max(4*pi*10^(pk.value/10)/max(P, eps), eps)), 'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', ar);
end

function [a, rows, fixed, sym, snapped] = cutGeometry(T, type, req)
%CUTGEOMETRY Rows of one full-circle cut ordered along its sweep angle A ∈ [0,360].
%   'Phi'  : fixed θ (snapped to the grid), sweep φ.
%   'Theta': fixed φ (snapped) plus the opposite half-plane φ+180: A = θ on the primary side and 360−θ on the
%            opposite side (the θ=180 pole sample is not repeated).
if strcmp(type, 'Phi')
    u = unique(T.Theta); [d, k] = min(abs(u - req)); fixed = u(k); sym = 'θ';
    rows = find(abs(T.Theta - fixed) < 1e-9); [a, o] = sort(T.Phi(rows)); rows = rows(o);
else
    ph = mod(T.Phi, 360); u = unique(ph); [d, k] = min(abs(mod(u - req + 180, 360) - 180)); fixed = u(k); sym = 'φ';
    [~, k2] = min(abs(mod(u - fixed, 360) - 180));
    r1 = find(abs(ph - fixed) < 1e-9); [~, o] = sort(T.Theta(r1)); r1 = r1(o);
    r2 = find(abs(ph - u(k2)) < 1e-9 & abs(T.Theta - 180) > 1e-9); [~, o] = sort(T.Theta(r2), 'descend'); r2 = r2(o);
    rows = [r1; r2]; a = [T.Theta(r1); 360 - T.Theta(r2)];
end
snapped = d > 1e-9;
end

function [bw, lo, hi] = calcHPBW(a, g, pkGain, pkAngle)
%CALCHPBW Half-power beamwidth of a circular cut by linear interpolation of the −3 dB crossings around the peak.
[bw, lo, hi] = deal(NaN); ok = isfinite(a) & isfinite(g); a = a(ok); g = g(ok);
if numel(g) < 3, return; end
if nargin < 3 || isempty(pkGain), [pkGain, i] = max(g); pkAngle = a(i); end
half = pkGain - 3; [ra, o] = sort(mod(a - pkAngle + 180, 360) - 180); rg = g(o);
L = find(ra < 0 & rg <= half, 1, 'last'); R = find(ra > 0 & rg <= half, 1, 'first');
if isempty(L) || isempty(R) || L + 1 > numel(rg) || R < 2, return; end
gl = rg([L, L+1]); gr = rg([R, R-1]); if diff(gl) == 0 || diff(gr) == 0, return; end
xl = ra(L) + diff(ra([L, L+1]))*(half - gl(1))/diff(gl); xr = ra(R) + diff(ra([R, R-1]))*(half - gr(1))/diff(gr);
lo = pkAngle + xl; hi = pkAngle + xr; bw = xr - xl;
end

function [P, info] = computePattern(S, prm, pct, ex)
%COMPUTEPATTERN Canonical source → processed table (gains, signed AR, PLF, EIRP, PFD, E-field) + polarization summary.
meta = S.Properties.UserData;
info = struct('pol', 'n/a', 'pairs', struct('Linear', ["E_TH" "E_PH"], 'Circular', ["E_RCP" "E_LCP"]));
if meta.isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + prm.GainLoss_dB; end
    info.peak = resolvePeak(P{:, 3}, pct, ex); return
end
Eth = complex(S.Re_Eth, S.Im_Eth) * prm.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph) * prm.FieldScale;
Er = (Eth + 1i*Eph)/sqrt(2); El = (Eth - 1i*Eph)/sqrt(2);
[mt, mp, mr, ml] = deal(abs(Eth), abs(Eph), abs(Er), abs(El));
total = 10*log10(max(mt.^2 + mp.^2, eps)); info.peak = resolvePeak(total, pct, ex);
% dominant polarization from mean component power → co/cross ordering, label and Auto Rx sense
pw = [mean(mt.^2, 'omitnan'), mean(mp.^2, 'omitnan'), mean(mr.^2, 'omitnan'), mean(ml.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP" "E_LCP"], ["RHCP" "LHCP"]));
elseif pw(1) >= pw(2),          info.pol = 'Linear (Vertical)';
else,                           info.pol = 'Linear (Horizontal)';
end
% signed axial ratio: + RHCP sense, − LHCP sense; equal circular components (linear limit) → −100 dB floor
d = mr - ml; sense = sign(d); sense(~isfinite(d)) = 0; ar = (mr + ml) ./ max(abs(d), eps);
sAR = min(20*log10(ar), 250) .* sense; sAR(isfinite(d) & abs(d) <= eps*max(mr + ml, 1)) = -100;
% polarization loss factor against the incident wave (Rw), worst-case tilt alignment (cos 2Δτ = −1)
if prm.RxMode == "Auto", ws = 2*(info.pairs.Circular(1) == "E_RCP") - 1; elseif prm.RxMode == "RHCP", ws = 1; else, ws = -1; end
ra = ar .* sense; ra(sense == 0) = 1e12; rw = ws*10^(prm.RxAR_dB/20);
plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1)) ./ (2*(ra.^2 + 1)*(rw^2 + 1)); plfDB = 10*log10(min(max(plf, eps), 1));
eirp = prm.Pt_dBW + total; eirpW = 10.^(eirp/10);
dB20 = @(x) 20*log10(max(x, eps)); phs = @(z) rad2deg(angle(z));
P = table(S.Theta, S.Phi, total, sAR, dB20(mr), dB20(ml), plfDB, total + plfDB, dB20(mt), dB20(mp), phs(Eth), phs(Eph), phs(Er), phs(El), ...
    eirp, eirpW/(4*pi*prm.R_m^2), sqrt(30*eirpW)/prm.R_m, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', 'PLF_dB', ...
    'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
P.Properties.UserData = meta;
end

function R = resampleCanonical(S, step)
%RESAMPLECANONICAL Resample a canonical table onto a STEP-degree θ/φ grid (φ periodic, closing 360 seam included).
%   Field components are interpolated as-is; gain-like dB columns are interpolated in linear power (both paths).
%   Complete rectangular grids use interp2 (nearest fill outside the hull); irregular samples use scatteredInterpolant.
names = S.Properties.VariableNames(3:end); th = S.Theta; ph = mod(S.Phi, 360);
keep = find(abs(S.Phi - 360) > 1e-9 & isfinite(th) & isfinite(ph));
[~, i] = unique([th(keep), ph(keep)], 'rows', 'stable'); k = keep(i); th = th(k); ph = ph(k); S = S(k, :);
tT = (0:step:180).'; tP = unique([(0:step:360).'; 360]); [QP, QT] = meshgrid(tP, tT);
R = table(QT(:), QP(:), 'VariableNames', {'Theta', 'Phi'});
uT = unique(th); uP = unique(ph); [~, it] = ismember(th, uT); [~, ip] = ismember(ph, uP);
lin = sub2ind([numel(uT), numel(uP)], it, ip); regular = numel(uT)*numel(uP) == numel(th) && numel(unique(lin)) == numel(lin);
isField = all(ismember({'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}, names));
for n = names
    v = double(S.(n{1})); toLin = ~isField && isGainDB(n{1}); if toLin, v = 10.^(v/10); end
    if regular
        G = nan(numel(uT), numel(uP)); G(lin) = v; G = [G, G(:, 1)];                    % periodic φ closure column
        [GP, GT] = meshgrid([uP; uP(1) + 360], uT); q = interp2(GP, GT, G, QP, QT, 'linear', NaN);
        miss = ~isfinite(q); if any(miss, 'all'), qn = interp2(GP, GT, G, QP, QT, 'nearest', NaN); q(miss) = qn(miss); end
    else
        F = scatteredInterpolant(ph, th, v, 'linear', 'nearest'); q = F(QP, QT);
    end
    if toLin, q = 10*log10(max(q, realmin)); end
    R.(n{1}) = q(:);
end
R.Properties.UserData = S.Properties.UserData;
end

function cov = coverageCCDF(gain, mask, thr, w)
%COVERAGECCDF Coverage(T) [%] = 100 · Σ I(G_i > T)·Ω_i / Σ Ω_i over the masked region, for every threshold at once.
ok = mask(:) & isfinite(gain(:)) & isfinite(w(:)) & w(:) >= 0; g = double(gain(ok)); wr = double(w(ok));
cov = zeros(numel(thr), 1); if isempty(g) || sum(wr) <= 0, return; end
cov = 100 * (wr.' * (g > thr(:).')).' / sum(wr);
end

function [cols, labels] = componentMap(T)
%COMPONENTMAP Plottable components present in T with user-facing labels (gain-only sources: every data column).
cols = string(T.Properties.VariableNames(3:end)); labels = cols;
if T.Properties.UserData.isGainOnly, return; end
all7 = ["E_Total_dB" "E_TH_dB" "E_PH_dB" "E_RCP_dB" "E_LCP_dB" "AR_dB" "Gain_PolCorrected_dB"];
lab7 = ["Total Gain" "Etheta Gain" "Ephi Gain" "RHCP Gain" "LHCP Gain" "Axial Ratio" "Polarized Gain"];
keep = ismember(all7, cols); cols = all7(keep); labels = lab7(keep);
end

function tf = isAR(name)
%ISAR Axial-ratio semantics independent of column spelling (AR, AR_dB, Axial Ratio, …).
k = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', ''); tf = k == "ar" || startsWith(k, "ardb") || startsWith(k, "axialratio");
end

function tf = isGainDB(name)
%ISGAINDB Gain-like dB quantity → interpolate in linear power.
k = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', ''); tf = contains(k, 'gain') || contains(k, 'directivity') || contains(k, 'eirp') || endsWith(k, 'db');
end

%% ======================================================================= shared helpers
function s = fmt(v, prec)
%FMT Compact number text: up to 2 decimals without trailing zeros, or exactly PREC decimals; 'n/a' when not finite.
if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); else, s = sprintf('%.*f', prec, v); end
end

function t = tickVector(r, step)
%TICKVECTOR Multiples of STEP inside R plus both end points; empty when the request is unreasonable.
t = [];
if ~isfinite(step) || step <= 0 || diff(r) <= 0, return; end
t = unique([r(1), ceil(r(1)/step)*step:step:floor(r(2)/step)*step, r(2)]); if numel(t) > 60, t = []; end
end

function syncRange(sliders, lows, highs, r, gap, bounds, reset)
%SYNCRANGE Mirror range R to range slider(s) and their min/max spinners.  Slider travel widens monotonically
%   (RESET = true snaps it to R); spinners bound each other by GAP.
for s = sliders(:).'
    lim = r; if ~reset, lim = [min(s.Limits(1), r(1)), max(s.Limits(2), r(2))]; end
    s.Limits = bounds; s.Value = r; s.Limits = lim;
end
set(lows, 'Limits', [bounds(1), r(2) - gap], 'Value', r(1));
set(highs, 'Limits', [r(1) + gap, bounds(2)], 'Value', r(2));
end

function setTipRows(h, rows)
%SETTIPROWS Apply a DataTip template, tolerating objects that expose it lazily.
try, h.DataTipTemplate.DataTipRows = rows; catch, end
end

function setTagVisible(ax, tag, on), set(findall(ax, 'Tag', tag), 'Visible', on); end

function k = nodeKind(n)
%NODEKIND 'pattern' | 'results' | 'job' | '' for tree nodes.
k = ''; if isstruct(n.NodeData) && isfield(n.NodeData, 'kind'), k = n.NodeData.kind; end
end

function tf = isChecked(tree, nodes)
%ISCHECKED Logical mask of NODES that are currently checked in the checkbox TREE.
tf = false(size(nodes)); c = tree.CheckedNodes; if ~isempty(nodes) && ~isempty(c), tf = ismember(nodes, c); end
end

function nodes = descendants(roots)
%DESCENDANTS ROOTS and every node below them (column vector).
nodes = roots(:);
for n = roots(:).', nodes = [nodes; descendants(n.Children)]; end %#ok<AGROW>
end