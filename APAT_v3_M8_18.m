classdef APAT_v3_M8_18 < matlab.apps.AppBase %1913-lines %ISSUE: %1. Loaded file check not working (if a pattern is already loaded, when pressing Load again it goes ahead and load the same file again instead of throwing a message!) %2. POB DataTip redraw/re-renders every-time a tab is highlighted/switched-to! %3. Edge POB DataTip positioning NOT OK (Hidden) %4. POB DataTip deletion issue (if POB DataTip is enabled, then user right Click and Delete Tips using the Custom Context Menu, it delete all DatTips as expected, but if user disable then re-enable the POB DatTip, it fails (the POB DatTip doesn't show anymore)!)  %5. When loading new pattern while the older/current POB DataTip is active/enabled, it shows the old POB instead of the new one (the old POB DataTip shouldn't show after loading a new pattern)! %6. Coverage Threshold Query snaps to nearest Data Point instead of returning requested/query point! %7. Context menu shows warning: "Warning: You cannot set 'ContextMenu' property of DataTip."
% APAT v3 M8 — Antenna Pattern Analyzer Tool (single-file programmatic App Designer class).
%
% ARCHITECTURE
%   I/O layer        readSource()  file -> {rawTbl, blocks, freqs, meta}      (pure local functions)
%   Model layer      normalizePattern, resample1deg, calcPattern, resolvePeak,
%                    calcOrientation, calcMetrics, calcCutGeometry, calcHPBW,
%                    solidWeights, coverageCCDF                               (pure local functions)
%   View state       stdTbl -> patTbl -> viewBaseTbl -> viewTbl (+ lazily built grid cache)
%   Presentation     renderFull / plotCut / tables / metadata / status         (app methods)
%   Coverage         the uitree IS the job registry (NodeData holds curve data + line handle)
%
% PIPELINE  loadPattern -> useBlock -> refresh -> applyStep -> applyView -> updateView
%   refresh     recompute processed pattern from the canonical source and the parameters
%   applyStep   native grid or 1° resampling of the *source* (never of derived quantities)
%   applyView   phi/theta display convention (0..360 / ±180, polar / elevation)
%   updateView  orientation, peaks, metrics, ranges, tables, cut, full-pattern plots
%
% Requires MATLAB R2023b or later (range slider, thetaregion/xregion, clim). No toolboxes.

    properties (Access = public)
        UIFigure matlab.ui.Figure
        h struct = struct()                 % UI handle registry (built once by createComponents)
    end

    properties (Access = private)
        src struct = struct('path', '', 'folder', '', 'base', '', 'name', '')  % active source
        stdTbl table                        % canonical E-field / gain table of the selected block
        patTbl table                        % processed pattern at native resolution
        viewBaseTbl table                   % canonical 0..360 view (native or 1° resampled)
        viewTbl table                       % display/export view in the selected angular convention
        grid struct = struct()              % grid topology / geometry / component cache of viewTbl
        solidAngle double = []              % dOmega per viewTbl row
        peak struct = struct()              % resolved peak of the displayed component
        pob double = [NaN NaN NaN]          % [gain, physical theta, phi] of the displayed peak
        pol struct = struct('label', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]))
        boresight double = 1                % index into Axes6
        metrics struct = struct()           % scalar antenna metrics (reference gain column)
        gainLim double = [-40 10]           % non-AR colour range, remembered across components
        fullLim double = [-40 10]           % currently applied full-pattern range
        cutLim double = [-40 10]            % cut magnitude range
        defaults struct = struct()          % start-up parameter values (Reset Params)
        keepOneDeg logical = false          % remember the user's 1° choice across reprocessing
        autoBasis logical = true            % choose the cut co/cross basis from the detected polarization
        covRunID double = 0
        covPresetKey string = ""            % pattern|component|size of the last threshold preset
        covXInit logical = false            % first coverage curve establishes the X baseline
        statusTimer = []
        opDialog = []
        isClosing logical = false
        filterStyles cell = {}
    end

    properties (Constant, Access = private)
        Axes6 = struct('labels', {{'+Z', '-Z', '+X', '-X', '+Y', '-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        Hidden = {'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'}
        PeakPct = 99.99                     % peak policy: P99.99 + max excess
        PeakExcess = 6
        DbLimits = [-250 100]
        Version = 'APAT v3 M8'
    end

    %% ======================================================================================
    %  Lifecycle
    %  ======================================================================================
    methods (Access = public)
        function app = APAT_v3_M8_18
            createComponents(app)
            registerApp(app, app.UIFigure)
            runStartupFcn(app, @startupFcn)
            if nargout == 0, clear app; end
        end

        function delete(app)
            app.shutdown();
        end

        function shutdown(app)
            if app.isClosing, return; end
            app.isClosing = true;
            app.stopTimer();
            if ~isempty(app.opDialog) && isvalid(app.opDialog), close(app.opDialog); end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end
    end

    %% ======================================================================================
    %  UI construction
    %  ======================================================================================
    methods (Access = private)
        function createComponents(app)
            V = app.DbLimits;
            fig = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.Version], 'Visible', 'off', ...
                'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) app.shutdown());
            app.UIFigure = fig;
            H = struct();
            H.Tabs = uitabgroup(uigridlayout(fig, [1 1]));
            H.TabMain = uitab(H.Tabs, 'Title', 'Process Pattern 📡');
            H.TabCov = uitab(H.Tabs, 'Title', 'Compute Coverage 📈');

            % ---- Main tab: inputs & parameters ------------------------------------------------
            G = uigridlayout(H.TabMain, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});
            P = uigridlayout(place(uipanel(G, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 14]), ...
                'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            lbl(P, 'Input Pattern:', 1, 1);
            H.Path = place(uieditfield(P, 'text'), 1, [2 8]);
            H.FFDLabel = lbl(P, 'FFD Freq:', 1, 9, 'Visible', 'off');
            H.FFD = place(uidropdown(P, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', app.cb(@app.onFFDChanged)), 1, 10);
            H.Load = place(uibutton(P, 'Text', '📂 Load File', 'ButtonPushedFcn', app.cb(@app.onLoad)), 1, [11 12]);
            H.Process = place(uibutton(P, 'Text', '⚙️ Process', 'ButtonPushedFcn', app.cb(@app.onProcess)), 1, [13 14]);
            H.ResetParams = place(uibutton(P, 'Text', 'Reset Params', 'ButtonPushedFcn', app.cb(@app.resetParams)), 2, [1 3]);
            H.FormatLabel = lbl(P, 'Format:', 2, [4 5], 'Visible', 'off');
            H.Format = place(formatDropdown(P, app.cb(@app.onFormatChanged), 'Visible', 'off'), 2, [6 8]);
            H.Step = place(uidropdown(P, 'Items', {'STEP'}, 'Visible', 'off', 'ValueChangedFcn', app.cb(@app.onStepChanged)), 2, [9 10]);
            H.ExportResults = place(uibutton(P, 'Text', '💾 Export Results', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@app.exportResults)), 2, [11 12]);
            H.ExportUAN = place(uibutton(P, 'Text', '💾 Export UAN', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@app.exportUAN)), 2, [13 14]);
            H.RxPolLabel = lbl(P, 'Rw Sense', 3, 1, 'Visible', 'off');
            H.RxPol = place(uidropdown(P, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Visible', 'off'), 3, 2);
            H.RwLabel = lbl(P, 'Rw (dB)', 3, 3, 'Visible', 'off');
            H.Rw = place(uispinner(P, 'Value', 6, 'Visible', 'off'), 3, 4);
            H.LossLabel = lbl(P, 'Loss (−) / Gain (+) dB', 3, 5, 'Visible', 'off');
            H.Loss = place(uispinner(P, 'Step', 0.1, 'Visible', 'off'), 3, 6);
            H.PtLabel = lbl(P, 'Tx Pwr (Pt)', 3, 7, 'Visible', 'off');
            H.Pt = place(uispinner(P, 'Visible', 'off'), 3, 8);
            H.PtUnit = place(uidropdown(P, 'Items', {'dBW', 'dBm', 'Watts'}, 'Visible', 'off'), 3, 9);
            H.RLabel = lbl(P, 'Distance', 3, 10, 'Visible', 'off');
            H.R = place(uispinner(P, 'Value', 1, 'Visible', 'off'), 3, 11);
            H.RUnit = place(uidropdown(P, 'Items', {'m', 'km'}, 'Visible', 'off'), 3, 12);
            H.ToCoverage = place(uibutton(P, 'Text', '📉 Coverage ▶', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@app.onToCoverage)), 3, [13 14]);

            % ---- Main tab: full-pattern plots (five views, one range control each) -------------
            H.PanelFull = place(uipanel(G, 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [1 6]);
            H.TabPlots = uitabgroup(uigridlayout(H.PanelFull, [1 1]), 'SelectionChangedFcn', @(~, ~) app.syncAnnotations());
            names = {'contour', 'circular', 'sphere3D', 'polar3D', 'rect3D'};
            titles = {'Contour Plot', 'Circular Contour Plot', '3D Spherical Plot', '3D Polar Plot', '3D Surface Plot'};
            for k = 1:5
                S.name = names{k};
                S.tab = uitab(H.TabPlots, 'Title', titles{k});
                g = uigridlayout(S.tab, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
                S.hi = place(uispinner(g, 'Limits', V, 'Value', 10, 'Step', 5, 'ValueChangedFcn', app.cb(@(s, ~) app.onRange("full", 2, s.Value))), 1, 1);
                S.slider = place(uislider(g, 'range', 'Limits', V, 'Value', [-40 10], 'Orientation', 'vertical', 'ValueChangedFcn', app.cb(@(s, ~) app.onRange("full", 0, s.Value))), 2, 1);
                S.lo = place(uispinner(g, 'Limits', V, 'Value', -40, 'Step', 5, 'ValueChangedFcn', app.cb(@(s, ~) app.onRange("full", 1, s.Value))), 3, 1);
                if k == 2, S.ax = place(polaraxes(g), [1 3], 2); else, S.ax = place(uiaxes(g), [1 3], 2); end
                H.full(k) = S;
            end

            % ---- Main tab: cut plots ----------------------------------------------------------
            H.PanelCut = place(uipanel(G, 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [7 12]);
            H.TabCut = uitabgroup(uigridlayout(H.PanelCut, [1 1]), 'SelectionChangedFcn', @(~, ~) app.syncAnnotations());
            H.TabPolar = uitab(H.TabCut, 'Title', 'Polar Cut Plot');
            g = uigridlayout(H.TabPolar, 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            H.CutHi = place(uispinner(g, 'Limits', V, 'Value', 10, 'Step', 5, 'ValueChangedFcn', app.cb(@(s, ~) app.onRange("cut", 2, s.Value))), 1, 1);
            H.CutSlider = place(uislider(g, 'range', 'Limits', V, 'Value', [-40 10], 'Orientation', 'vertical', 'ValueChangedFcn', app.cb(@(s, ~) app.onRange("cut", 0, s.Value))), [2 3], 1);
            H.CutLo = place(uispinner(g, 'Limits', V, 'Value', -40, 'Step', 5, 'ValueChangedFcn', app.cb(@(s, ~) app.onRange("cut", 1, s.Value))), 4, 1);
            H.PolarCut = place(polaraxes(g), [1 4], 3);
            H.HPBW = place(uibutton(g, 'state', 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', app.cb(@app.onCutChanged)), 1, 4);
            H.HPBWLabel = place(uilabel(g, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold'), 2, 4);
            H.EcutGrid = place(uigridlayout(g, [3 1]), 3, 4);
            H.Et = uicheckbox(H.EcutGrid, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', app.cb(@app.onCutChanged));
            H.Er = uicheckbox(H.EcutGrid, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', app.cb(@app.onCutChanged));
            H.El = uicheckbox(H.EcutGrid, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', app.cb(@app.onCutChanged));
            H.ExportCut = place(uibutton(g, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', app.cb(@app.exportCut)), 4, 4);
            H.TabRect = uitab(H.TabCut, 'Title', 'Rectangular Cut Plot');
            H.RectCut = uiaxes(uigridlayout(H.TabRect, [1 1]), 'Box', 'on');

            % ---- Main tab: plot control ------------------------------------------------------
            H.PanelCtrl = place(uipanel(G, 'Title', 'Plot Control 🎨', 'Visible', 'off'), 2, [13 14]);
            C = uigridlayout(H.PanelCtrl, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', repmat({'fit'}, 1, 15));
            lbl(C, 'Component', 1, 1);
            H.Component = place(uidropdown(C, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', app.cb(@app.onComponentChanged)), 1, 2);
            lbl(C, 'Cut type', 2, 1);
            H.CutType = place(uidropdown(C, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', app.cb(@app.onCutChanged)), 2, 2);
            lbl(C, 'Cut value', 3, 1);
            H.CutValue = place(uispinner(C, 'Limits', [-90 360], 'ValueChangedFcn', app.cb(@app.onCutChanged)), 3, 2);
            lbl(C, 'Cut basis', 4, 1);
            H.Basis = place(uidropdown(C, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'ValueChangedFcn', app.cb(@app.onCutChanged)), 4, 2);
            applyAll = app.cb(@(~, ~) app.setRange("all", [app.h.Cmin.Value, app.h.Cmax.Value], true));
            lbl(C, 'Colorbar max', 5, 1);
            H.Cmax = place(uispinner(C, 'Limits', V, 'Value', 10, 'ValueChangedFcn', applyAll), 5, 2);
            lbl(C, 'Colorbar min', 6, 1);
            H.Cmin = place(uispinner(C, 'Limits', V, 'Value', -40, 'ValueChangedFcn', applyAll), 6, 2);
            lbl(C, 'Colorbar step', 7, 1);
            H.Cstep = place(uispinner(C, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', app.cb(@(~, ~) app.applyRange("full"))), 7, 2);
            H.Apply = place(uibutton(C, 'Text', 'Apply', 'Tooltip', 'Apply to full-pattern and cut plots.', 'ButtonPushedFcn', applyAll), 8, 2);
            lbl(C, '3D view', 9, 1);
            H.View3D = place(uidropdown(C, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Tooltip', 'Camera direction for the 3D pattern tabs.', ...
                'ValueChangedFcn', app.cb(@(~, ~) app.applyView3D())), 9, 2);
            pad = @(n) repmat(char(160), 1, n);   % non-breaking padding centres the switch captions
            H.PhiSpan = place(uiswitch(C, 'slider', 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'ValueChangedFcn', app.cb(@app.onSpanChanged)), 10, [1 2]);
            H.ThetaSpan = place(uiswitch(C, 'slider', 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'ValueChangedFcn', app.cb(@app.onSpanChanged)), 11, [1 2]);
            H.Plane = place(uiswitch(C, 'slider', 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E', 'H'}, 'ValueChangedFcn', app.cb(@app.onPlaneChanged)), 12, [1 2]);
            H.Overlay = place(uicheckbox(C, 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', app.cb(@(~, ~) app.drawOverlays())), 13, [1 2]);
            H.POB = place(uicheckbox(C, 'Text', 'Annotate POB', 'ValueChangedFcn', app.cb(@(~, ~) app.syncAnnotations())), 14, [1 2]);
            H.HPBWBounds = place(uicheckbox(C, 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', app.cb(@(~, ~) app.syncAnnotations())), 15, [1 2]);

            % ---- Main tab: tables & status ---------------------------------------------------
            H.OutFilter = place(uidropdown(G, 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Value', 0, 'Visible', 'off', 'ValueChangedFcn', app.cb(@(~, ~) app.filterOutput(true))), 3, [13 14]);
            H.TabData = place(uitabgroup(G, 'Visible', 'off'), 4, [1 14]);
            H.TableOut = uitable(uigridlayout(uitab(H.TabData, 'Title', 'Results 📤'), [1 1]), 'ColumnWidth', '1x');
            H.TableIn = uitable(uigridlayout(uitab(H.TabData, 'Title', 'Input 📥'), [1 1]));
            H.TableMeta = uitable(uigridlayout(uitab(H.TabData, 'Title', 'Metadata 📋'), [1 1]), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            H.Status = place(uilabel(G, 'Text', 'Ready 🚀', 'Interpreter', 'html'), 5, [1 14]);

            % ---- Coverage tab ----------------------------------------------------------------
            G2 = uigridlayout(H.TabCov, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            Q = uigridlayout(place(uipanel(G2, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 5]), 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'});
            H.CovType = place(uibuttongroup(Q, 'Title', 'Coverage Type', 'SelectionChangedFcn', app.cb(@app.onCovTypeChanged)), [1 2], [1 2]);
            H.Spherical = uiradiobutton(H.CovType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            H.Conical = uiradiobutton(H.CovType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            H.OrientLabel = lbl(Q, 'Orientation 🧭:', 3, 1, 'Enable', 'off');
            H.Orient = place(uidropdown(Q, 'Items', [{'Auto'}, app.Axes6.labels], 'ItemsData', 0:6, 'Value', 0, 'Enable', 'off', 'ValueChangedFcn', app.cb(@app.onOrientChanged)), 3, 2);
            lbl(Q, 'Antenna Pattern:', 1, 3);
            H.CovPath = place(uieditfield(Q, 'text'), 1, [4 8]);
            H.CovLoad = place(uibutton(Q, 'Text', '📂 Load File', 'ButtonPushedFcn', app.cb(@app.onCovLoad)), 1, 9);
            H.CovCompute = place(uibutton(Q, 'Text', '⚙️ Compute Coverage', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@app.onCovCompute)), 1, 10);
            lbl(Q, 'Threshold  Min (dB):', 2, 3);
            H.ThrMin = place(uispinner(Q, 'Limits', V, 'Value', -40), 2, 4);
            lbl(Q, 'Threshold  Max (dB):', 2, 5);
            H.ThrMax = place(uispinner(Q, 'Limits', V, 'Value', 10), 2, 6);
            lbl(Q, 'Step (dB):', 2, 7);
            H.ThrStep = place(uispinner(Q, 'Limits', [0.1 50], 'Value', 1), 2, 8);
            H.CovReset = place(uibutton(Q, 'Text', '🔄 Reset', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@app.onCovReset)), 2, 9);
            H.CovExport = place(uibutton(Q, 'Text', '💾 Export Results', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@app.onCovExport)), 2, 10);
            H.ConeLabels = [lbl(Q, 'Cone θ₀ (°):', 3, 3, 'Enable', 'off'), lbl(Q, 'Cone φ₀ (°):', 3, 5, 'Enable', 'off'), lbl(Q, 'Cone Angle α (°):', 3, 7, 'Enable', 'off')];
            H.ConeTh = place(uispinner(Q, 'Limits', [0 180], 'Enable', 'off'), 3, 4);
            H.ConePh = place(uispinner(Q, 'Limits', [0 360], 'Enable', 'off'), 3, 6);
            H.ConeAng = place(uispinner(Q, 'Limits', [0 180], 'Value', 45, 'Enable', 'off'), 3, 8);
            H.CovClear = place(uibutton(Q, 'Text', '🧹 Clear DataTips', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@app.onCovClear)), 3, 9);
            H.ToMain = place(uibutton(Q, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~, ~) set(H.Tabs, 'SelectedTab', H.TabMain)), 3, 10);
            H.CovCompLabel = lbl(Q, 'Component:', 4, 1, 'Enable', 'off');
            H.CovComp = place(uidropdown(Q, 'Items', {'E_Total_dB'}, 'Enable', 'off', 'ValueChangedFcn', app.cb(@app.onCovComponentChanged)), 4, 2);
            lbl(Q, 'Coverage @ dB:', 4, 3);
            H.QueryCov = place(uispinner(Q, 'Limits', V, 'Value', 0, 'ValueDisplayFormat', '%g dB'), 4, 4);
            H.QueryCovBtn = place(uibutton(Q, 'Text', '⯐ Query Coverage', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@(~, ~) app.covQuery("cov"))), 4, 5);
            lbl(Q, 'Threshold @ %:', 4, 6);
            H.QueryThr = place(uispinner(Q, 'Limits', [0 100], 'Value', 50, 'ValueDisplayFormat', '%g%%'), 4, 7);
            H.QueryThrBtn = place(uibutton(Q, 'Text', '🔍 Query Threshold', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@(~, ~) app.covQuery("thr"))), 4, 8);
            H.CovFormatLabel = lbl(Q, 'Format:', 4, 9, 'Visible', 'off');
            H.CovFormat = place(formatDropdown(Q, app.cb(@app.onCovFormatChanged), 'Visible', 'off'), 4, 10);
            H.CovStatus = place(uilabel(G2, 'Text', 'Ready 🚀', 'Interpreter', 'html'), 3, [1 5]);
            H.PanelResults = place(uipanel(G2, 'Title', 'Results', 'Visible', 'off'), 2, [1 5]);
            R = uigridlayout(H.PanelResults, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            H.CovAxes = place(uiaxes(R, 'Box', 'on', 'Layer', 'top', 'XGrid', 'on', 'YGrid', 'on', 'YLim', [0 100], 'NextPlot', 'add'), 1, [2 4]);
            H.CovAxes.Interactions = dataTipInteraction;                    % display-only axes
            title(H.CovAxes, 'Coverage vs Threshold'); xlabel(H.CovAxes, 'Threshold (dB)'); ylabel(H.CovAxes, 'Coverage (%)');
            H.Tree = place(uitree(R, 'checkbox', 'SelectionChangedFcn', app.cb(@app.onTreeSelection), 'CheckedNodesChangedFcn', app.cb(@(~, ~) app.covRefresh())), [1 2], 1);
            H.TreeRoot = uitreenode(H.Tree, 'Text', 'Coverage Results');
            H.CovTable = place(uitable(R, 'ColumnWidth', '1x', 'RowName', {}), [1 2], 5);
            H.XMin = place(uispinner(R, 'Limits', V, 'Value', -40, 'ValueChangedFcn', app.cb(@app.onCovXRange)), 2, 2);
            H.XRange = place(uislider(R, 'range', 'Limits', V, 'Value', [-40 10], 'ValueChangedFcn', app.cb(@app.onCovXRange), 'ValueChangingFcn', app.cb(@app.onCovXRange)), 2, 3);
            H.XMax = place(uispinner(R, 'Limits', V, 'Value', 10, 'ValueChangedFcn', app.cb(@app.onCovXRange)), 2, 4);
            app.h = H;

            % Fixed local gestures: rotate on 3-D axes, zoom elsewhere, DataTips everywhere.
            for k = 1:5, app.setInteraction(H.full(k).ax, k > 2); end
            app.setInteraction(H.RectCut, false); app.setInteraction(H.PolarCut, false);
            fig.Visible = 'on';
        end

        function startupFcn(app)
            H = app.h;
            app.defaults = struct('Loss', H.Loss.Value, 'RxPol', H.RxPol.Value, 'Rw', H.Rw.Value, 'Pt', H.Pt.Value, ...
                'PtUnit', H.PtUnit.Value, 'R', H.R.Value, 'RUnit', H.RUnit.Value);
            set([H.PolarCut, H.full(2).ax], 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            app.setStatus(H.Status, 'Ready -- load an antenna pattern file to begin 🚀', false);
            app.setCoverageUI();
        end
    end

    methods (Access = public)
        %% ==================================================================================
        %  Callback plumbing, status, errors
        %  ==================================================================================
        function f = cb(app, fn)
            % Uniform callback wrapper: one error/cancel path for every UI action.
            f = @(s, e) app.guard(fn, s, e);
        end

        function guard(app, fn, s, e)
            if app.isClosing, return; end
            try
                fn(s, e);
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled')
                    app.setStatus(app.h.Status, 'Operation cancelled by user.', true);
                else
                    app.showError(ME);
                end
            end
        end

        function setInteraction(app, ax, is3D)
            enableDefaultInteractivity(ax);
            if ~isa(ax, 'matlab.graphics.axis.PolarAxes')
                if is3D, ax.Interactions = [rotateInteraction, dataTipInteraction]; else, ax.Interactions = [zoomInteraction, dataTipInteraction]; end
            end
            menu = uicontextmenu(app.UIFigure);
            uimenu(menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ~) delete(findall(ax, 'Type', 'datatip')));
            ax.ContextMenu = menu;
        end

        function setStatus(app, label, msg, transient)
            % Persistent messages are remembered in UserData; transient ones revert after 3 s.
            if app.isClosing || ~isgraphics(label), return; end
            app.stopTimer();
            label.Text = char(msg);
            if ~transient, label.UserData = char(msg); return; end
            app.statusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, ...
                'TimerFcn', @(~, ~) app.restoreStatus(label), 'StopFcn', @(t, ~) delete(t));
            start(app.statusTimer);
        end

        function restoreStatus(app, label)
            if ~app.isClosing && isgraphics(label) && ischar(label.UserData), label.Text = label.UserData; end
        end

        function stopTimer(app)
            t = app.statusTimer; app.statusTimer = [];
            if ~isempty(t) && isvalid(t), stop(t); end
            if ~isempty(t) && isvalid(t), delete(t); end
        end

        function showError(app, ME)
            if app.isClosing || ~isvalid(app.UIFigure), return; end
            loc = '';
            if ~isempty(ME.stack), loc = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.UIFigure, [ME.message loc], 'APAT Error', 'Icon', 'error');
        end

        function checkCancelled(app)
            d = app.opDialog;
            if ~isempty(d) && isvalid(d) && d.CancelRequested, error('APAT:Cancelled', 'Operation cancelled by user.'); end
        end

        %% ==================================================================================
        %  Source loading and the processing pipeline
        %  ==================================================================================
        function onLoad(app, ~, ~)
            fp = strtrim(app.h.Path.Value);
            if isempty(fp) || ~isfile(fp)
                fp = pickFile(); if isempty(fp), return; end
                app.h.Path.Value = fp;
            end
            app.loadPattern(fp);
        end

        function loadPattern(app, fp)
            H = app.h;
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Loading Data', 'Message', 'Reading file...', 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            app.opDialog = dlg; cleaner = onCleanup(@() close(dlg)); %#ok<NASGU>
            drawnow
            out = app.readSourceUI(fp, H.FormatLabel, H.Format);
            app.checkCancelled();
            if out.meta.isCoverage                       % route coverage results without touching Main state
                H.Path.Value = app.src.path; H.Tabs.SelectedTab = H.TabCov; H.CovPath.Value = fp;
                app.covLoadResults(fp, out.rawTbl);
                return
            end
            [out.folder, out.base, ext] = fileparts(fp); out.path = fp; out.name = [out.base ext];
            app.src = out;
            if out.meta.isDep                            % multi-frequency FFD: one block per frequency
                items = compose('Pattern %d: %.4g GHz', [(1:numel(out.blocks))', out.freqs(:) / 1e9]);
                items(isnan(out.freqs(:))) = compose('Pattern %d', find(isnan(out.freqs(:))));
                H.FFD.Items = cellstr(items); H.FFD.Value = H.FFD.Items{1};
            end
            set([H.FFD, H.FFDLabel], 'Visible', out.meta.isDep);
            app.keepOneDeg = false; app.autoBasis = true;
            app.useBlock(1);
            app.refresh();
        end

        function out = readSourceUI(~, fp, label, dropdown)
            % Generic text files expose the format selector; every other format is self-describing.
            generic = isGenericText(fp);
            if generic, dropdown.Value = 'gain'; end
            out = readSource(fp, dropdown.Value, table());
            set([label, dropdown], 'Visible', generic && ~out.meta.isCoverage);
        end

        function useBlock(app, k)
            T = normalizePattern(app.src.blocks{k}); T.Properties.UserData = app.src.meta;
            app.stdTbl = T;
            if app.src.meta.isDep, app.src.rawTbl = app.src.blocks{k}; end
            app.h.TableIn.Data = app.src.rawTbl; app.h.TableIn.ColumnName = app.src.rawTbl.Properties.VariableNames;
        end

        function refresh(app)
            % Full recompute: processed pattern -> step -> view convention -> everything derived.
            t0 = tic; H = app.h; isField = ~app.src.meta.isGainOnly;
            [app.patTbl, info] = calcPattern(app.stdTbl, app.getParam());
            app.pol = info;
            if app.autoBasis && isField
                if startsWith(info.label, 'Linear'), H.Basis.Value = 'Linear'; else, H.Basis.Value = 'Circular'; end
            end
            app.checkCancelled();
            [thetaStep, phiStep] = tableSteps(app.patTbl);        % native step + optional 1° resampling
            native = sprintf('STEP: %g°', max(thetaStep, phiStep)); oneDeg = 'STEP: 1°';
            nonCanonical = abs(thetaStep - 1) > 1e-9 || abs(phiStep - 1) > 1e-9;
            H.Step.Items = {native, oneDeg};
            if app.keepOneDeg && nonCanonical, H.Step.Value = oneDeg; else, H.Step.Value = native; end
            set(H.Step, 'Visible', nonCanonical, 'Enable', nonCanonical);
            app.applyStep();
            app.updateComponentItems();
            app.checkCancelled();
            app.updateView(true, true);
            set([H.PanelCut, H.PanelFull, H.PanelCtrl, H.ExportResults, H.ToCoverage, H.TabData, H.OutFilter], 'Visible', 'on');
            set([H.ExportUAN, H.EcutGrid, H.Et, H.Er, H.El], 'Visible', isField);
            set([H.Er, H.El, H.Basis], 'Enable', isField);
            app.updateInputVisibility();
            polText = '';
            if isField && ~strcmpi(strtrim(app.pol.label), 'n/a'), polText = sprintf(' | Polarization <b>%s</b>', app.pol.label); end
            app.setStatus(H.Status, sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)%s | ⏱ %.2f s', ...
                app.src.name, fmtNum(app.pob(1), 2), fmtNum(app.pob(2)), fmtNum(app.pob(3)), polText, toc(t0)), false);
        end

        function p = getParam(app)
            H = app.h;
            p = struct('GainLoss_dB', H.Loss.Value, 'RxMode', string(H.RxPol.Value), 'RxAR_dB', H.Rw.Value);
            p.FieldScale = 10 .^ (p.GainLoss_dB / 20);
            switch H.PtUnit.Value
                case 'dBm',   p.Pt_dBW = H.Pt.Value - 30;
                case 'Watts', p.Pt_dBW = 10 * log10(max(H.Pt.Value, eps));
                otherwise,    p.Pt_dBW = H.Pt.Value;
            end
            p.R_m = max(H.R.Value, 1e-12) * (1 + 999 * strcmp(H.RUnit.Value, 'km'));
        end

        function applyStep(app)
            % Resample the canonical *source* (fields / raw gain), never the derived quantities.
            [thetaStep, phiStep] = tableSteps(app.stdTbl);
            if strcmp(app.h.Step.Value, 'STEP: 1°') && (abs(thetaStep - 1) > 1e-9 || abs(phiStep - 1) > 1e-9)
                app.viewBaseTbl = calcPattern(resample1deg(app.stdTbl), app.getParam());
            else
                app.viewBaseTbl = app.patTbl;
            end
            app.applyView();
        end

        function applyView(app)
            % Materialize the selected phi/theta display convention from the canonical table.
            T = app.viewBaseTbl; signed = app.isSigned(); elev = app.isElev();
            if signed
                T(abs(T.Phi - 360) <= 1e-9, :) = [];
                T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
                seam = T(abs(T.Phi - 180) < 1e-9, :); seam.Phi(:) = -180;
                T = [seam; T];
            end
            if elev, T.Theta = 90 - T.Theta; end
            ud = T.Properties.UserData; ud.elevation = elev; T.Properties.UserData = ud;
            if signed || elev, T = sortrows(T, {'Phi', 'Theta'}); end
            app.viewTbl = T;
            app.grid = struct(); app.solidAngle = []; app.metrics = struct();
        end

        function tf = isSigned(app), tf = strcmp(app.h.PhiSpan.Value, '-180° to 180°'); end
        function tf = isElev(app),   tf = strcmp(app.h.ThetaSpan.Value, '-90° to 90°'); end
        function xl = phiLimits(app), if app.isSigned(), xl = [-180 180]; else, xl = [0 360]; end, end
        function c = comp(app), c = app.h.Component.Value; end

        function s = compLabel(app)
            dd = app.h.Component; k = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(k), s = strrep(dd.Value, '_', ' '); else, s = dd.Items{k}; end
        end

        function updateComponentItems(app)
            [cols, labels] = componentMap(app.viewTbl);
            dd = app.h.Component; prev = dd.Value;
            dd.Items = cellstr(labels); dd.ItemsData = cellstr(cols);
            dd.Value = preferredComponent(prev, cols);
        end

        function updateView(app, resetRange, syncPlane)
            % Everything derived from viewTbl and the selected component.
            % Orientation and metrics always use the reference gain (Total); the POB follows the component.
            T = app.viewTbl; c = app.comp(); ref = chooseGain(T, 'E_Total_dB');
            [app.solidAngle, refPeak, app.boresight] = calcOrientation(T, ref, [], app.Axes6, app.PeakPct, app.PeakExcess);
            app.metrics = calcMetrics(T, ref, refPeak, app.solidAngle, app.Axes6, app.boresight, app.isElev());
            app.peak = resolvePeak(T.(c), app.PeakPct, app.PeakExcess);
            pt = physTheta(T); app.pob = [app.peak.value, pt(app.peak.index), mod(T.Phi(app.peak.index), 360)];
            if resetRange
                if ~isAR(c), app.gainLim = peakWindow(ref, app.PeakPct, app.PeakExcess); end
                app.setRange("full", app.themeLimits(), false); app.setRange("cut", app.gainLim, false);
            end
            app.updateTables(); app.updateMetadata();
            if syncPlane, app.syncPlaneCut(); end
            app.updateCutControl(); app.plotCut();
            app.renderFull();
        end

        function T = buildPattern(app, out)
            % Process an auxiliary source (block 1) without touching the Main view.
            S = normalizePattern(out.blocks{1}); S.Properties.UserData = out.meta;
            T = calcPattern(S, app.getParam());
        end

        function onProcess(app, ~, ~)
            if isempty(app.stdTbl), uialert(app.UIFigure, 'Load a pattern first.', 'Process', 'Icon', 'warning'); return; end
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Processing', 'Message', 'Re-processing pattern...', 'Indeterminate', 'on');
            cleaner = onCleanup(@() close(dlg)); %#ok<NASGU>
            if isGenericText(app.src.path)          % re-interpret the cached generic table with the selected format
                out = readSource(app.src.path, app.h.Format.Value, app.src.rawTbl);
                assert(~out.meta.isCoverage, 'The selected generic format identifies a coverage-results file.');
                app.src.rawTbl = out.rawTbl; app.src.blocks = out.blocks; app.src.freqs = out.freqs; app.src.meta = out.meta;
                app.useBlock(1);
            end
            app.refresh();
        end

        function onFormatChanged(app, ~, ~)
            if strcmp(strtrim(app.h.Path.Value), app.src.path) && isGenericText(app.src.path)
                app.autoBasis = true; app.onProcess();
            end
        end

        function onFFDChanged(app, ~, ~)
            k = find(strcmp(app.h.FFD.Items, app.h.FFD.Value), 1);
            app.autoBasis = true; app.useBlock(k); app.refresh();
        end

        function onStepChanged(app, ~, ~)
            app.keepOneDeg = strcmp(app.h.Step.Value, 'STEP: 1°');
            app.applyStep(); app.updateComponentItems(); app.updateView(true, false);
        end

        function onSpanChanged(app, src, ~)
            H = app.h;
            if isequal(src, H.ThetaSpan) && strcmp(H.CutType.Value, 'Phi')   % keep the same physical cut
                H.CutValue.Limits = [-90 360]; H.CutValue.Value = 90 - H.CutValue.Value;
            end
            app.applyView(); app.updateView(false, false);
        end

        function onComponentChanged(app, ~, ~)
            app.updateView(true, false);
        end

        function resetParams(app, ~, ~)
            H = app.h; d = app.defaults;
            if ~isfield(d, 'Loss'), return; end
            H.Loss.Value = d.Loss; H.RxPol.Value = d.RxPol; H.Rw.Value = d.Rw; H.Pt.Value = d.Pt;
            H.PtUnit.Value = d.PtUnit; H.R.Value = d.R; H.RUnit.Value = d.RUnit;
            if ~isempty(app.stdTbl), app.refresh(); end
        end

        %% ==================================================================================
        %  Tables and metadata
        %  ==================================================================================
        function updateTables(app)
            dd = app.h.OutFilter; cols = app.viewTbl.Properties.VariableNames(3:end);
            if ~isequal(regexprep(dd.Items(2:end), '^✓ ?', ''), cols)   % schema changed -> rebuild the filter
                dd.Items = [{'--- column filter ---'}, cols]; dd.ItemsData = 0:numel(cols);
                dd.UserData = ~ismember(cols, app.Hidden); dd.Value = 0;
            end
            app.filterOutput(false);
        end

        function filterOutput(app, fromUser)
            % Toggle one column from the dropdown, restyle the items, refresh the results table.
            dd = app.h.OutFilter;
            if fromUser && dd.Value > 0, dd.UserData(dd.Value) = ~dd.UserData(dd.Value); end
            if isempty(app.filterStyles)
                app.filterStyles = {uistyle('FontWeight', 'bold', 'FontColor', 'black', 'BackgroundColor', [0.8 1 0.8]), ...
                    uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9])};
            end
            on = find(dd.UserData) + 1;
            dd.Items = regexprep(dd.Items, '^✓ ?', ''); dd.Items(on) = append('✓ ', dd.Items(on)); dd.Value = 0;
            removeStyle(dd); addStyle(dd, app.filterStyles{2}, 'Item', find([true, ~dd.UserData]));
            if ~isempty(on), addStyle(dd, app.filterStyles{1}, 'Item', on); end
            app.h.TableOut.Data = app.viewTbl(:, [true, true, dd.UserData]);
            app.updateInputVisibility();
        end

        function updateInputVisibility(app)
            % Show only the parameters that influence a visible results column.
            H = app.h; cols = app.viewTbl.Properties.VariableNames(3:end); sel = string(cols(H.OutFilter.UserData));
            showRx = any(ismember(sel, ["PLF_dB", "Gain_PolCorrected_dB"]));
            showTx = any(ismember(sel, ["EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
            showR = any(ismember(sel, ["PFD_Wm2", "E_RMS_Vm"]));
            showLoss = app.src.meta.isGainOnly || any(ismember(sel, ["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "Gain_PolCorrected_dB", "EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
            set([H.RxPolLabel, H.RxPol, H.RwLabel, H.Rw], 'Visible', showRx);
            set([H.PtLabel, H.Pt, H.PtUnit], 'Visible', showTx);
            set([H.RLabel, H.R, H.RUnit], 'Visible', showR);
            set([H.LossLabel, H.Loss], 'Visible', showLoss);
        end

        function updateMetadata(app)
            T = app.viewTbl; M = app.metrics; meta = app.src.meta; H = app.h;
            theta = unique(T.Theta); phi = unique(T.Phi);
            rows = {'Source format', meta.source; 'File', app.src.name; ...
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(T), numel(theta), numel(phi)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(min(theta)), fmtNum(max(theta)), fmtNum(gridStep(theta))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(min(phi)), fmtNum(max(phi)), fmtNum(gridStep(phi)))};
            f = app.src.freqs(isfinite(app.src.freqs));
            if ~isempty(f), rows(end + 1, :) = {'Frequencies', strjoin(compose('%.4g GHz', f(:) / 1e9), ', ')}; end
            if ~meta.isGainOnly
                rows(end + 1, :) = {'Polarization', app.pol.label};
                rows(end + 1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(app.pol.pairs.(H.Basis.Value), ' / '))};
            end
            rows = [rows; {'Peak gain (POB)', [fmtNum(M.PeakGain_dB) ' dB']; ...
                'POB direction [θ, φ]', sprintf('[%s°, %s°]', fmtNum(M.PeakTheta_deg), fmtNum(M.PeakPhi_deg)); ...
                'Boresight axis', app.Axes6.labels{app.boresight}; ...
                'Peak policy', sprintf('P%.4g, max excess %g dB', app.PeakPct, app.PeakExcess); ...
                'Peak adjusted', char(string(app.peak.wasAdjusted)); ...
                'HPBW E-plane', [fmtNum(M.HPBW_EPlane_deg) '°']; 'HPBW H-plane', [fmtNum(M.HPBW_HPlane_deg) '°']; ...
                'Front-to-back', [fmtNum(M.FrontBack_dB) ' dB']; 'Peak directivity', [fmtNum(M.PeakDirectivity_dB) ' dB']}];
            if isfinite(M.Efficiency_pct), rows(end + 1, :) = {'Radiation efficiency', [fmtNum(M.Efficiency_pct) '%']}; end
            if isfinite(M.AxialRatioAtPeak_dB), rows(end + 1, :) = {'AR at peak', [fmtNum(M.AxialRatioAtPeak_dB) ' dB']}; end
            H.TableMeta.Data = rows;
        end

        %% ==================================================================================
        %  Ranges and colour theme
        %  ==================================================================================
        function lim = themeLimits(app)
            if isAR(app.comp()), lim = [-30 30]; else, lim = app.gainLim; end
        end

        function onRange(app, scope, which, value)
            % Slider (which = 0, value = [lo hi]) or one spinner (which = 1|2, scalar) changed.
            if scope == "full", cur = app.fullLim; else, cur = app.cutLim; end
            if which > 0, cur(which) = value; else, cur = value; end
            app.setRange(scope, cur, true);
        end

        function setRange(app, scope, lim, apply)
            % One range setter for the full-pattern colour scale ("full"), the cut scale ("cut") or both ("all").
            H = app.h; L = app.DbLimits; lim = clampRange(lim, L);
            if scope == "all", app.setRange("full", lim, apply); app.setRange("cut", lim, apply); return; end
            if scope == "full"
                sliders = [H.full.slider]; los = [H.full.lo]; his = [H.full.hi];
                app.fullLim = lim; if ~isAR(app.comp()), app.gainLim = lim; end
                H.Cmin.Value = lim(1); H.Cmax.Value = lim(2);
            else
                sliders = H.CutSlider; los = H.CutLo; his = H.CutHi; app.cutLim = lim;
            end
            travel = clampRange(lim + [-20 20], L);                   % slider travel: selection ± 20 dB
            set(sliders, 'Limits', L); set(sliders, 'Value', lim); set(sliders, 'Limits', travel);
            set([los, his], 'Limits', L); set(los, 'Value', lim(1)); set(his, 'Value', lim(2));
            set(los, 'Limits', [L(1), lim(2) - 1]); set(his, 'Limits', [lim(1) + 1, L(2)]);
            if apply && ~isempty(app.viewTbl), app.applyRange(scope); end
        end

        function applyRange(app, scope)
            H = app.h;
            if scope == "cut"
                set(H.PolarCut, 'RLim', app.cutLim, 'RTick', app.cutLim(1):5:app.cutLim(2)); H.RectCut.YLim = app.cutLim;
            else
                for S = H.full
                    clim(S.ax, app.fullLim);
                    if strcmp(S.name, 'rect3D'), zlim(S.ax, app.fullLim); applyTicks(S.ax, 'ZTick', app.fullLim, H.Cstep.Value); end
                    cbar = findall(app.UIFigure, 'Type', 'ColorBar', 'Axes', S.ax);
                    if ~isempty(cbar), applyTicks(cbar(1), 'Ticks', app.fullLim, H.Cstep.Value); end
                end
            end
            drawnow limitrate
        end

        function applyTheme(app, ax)
            % Colour scale, colormap (jet, or blue-white-red for signed AR) and colorbar ticks.
            persistent arMap
            if isempty(arMap), arMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
            if isAR(app.comp()), colormap(ax, arMap); else, colormap(ax, jet(256)); end
            clim(ax, app.fullLim);
            applyTicks(colorbar(ax), 'Ticks', app.fullLim, app.h.Cstep.Value);
        end

        %% ==================================================================================
        %  Full-pattern rendering
        %  ==================================================================================
        function [G, c] = gridOf(app, col)
            % Rectangular grid of one viewTbl column plus the cached geometry (built once per view).
            T = app.viewTbl; c = app.grid;
            if ~isfield(c, 'sz')
                c = struct('theta', unique(T.Theta), 'phi', unique(T.Phi), 'data', struct());
                [~, it] = ismember(T.Theta, c.theta); [~, ip] = ismember(T.Phi, c.phi);
                c.sz = [numel(c.theta), numel(c.phi)]; c.idx = sub2ind(c.sz, it, ip);
                [c.phiGrid, c.thetaGrid] = meshgrid(c.phi, c.theta);
                c.thetaPolar = c.thetaGrid; if app.isElev(), c.thetaPolar = 90 - c.thetaGrid; end
                c.phiRad = deg2rad(c.phiGrid); s = sind(c.thetaPolar);
                c.x = s .* cos(c.phiRad); c.y = s .* sin(c.phiRad); c.z = cosd(c.thetaPolar);
            end
            key = matlab.lang.makeValidName(col);
            if ~isfield(c.data, key), G = nan(c.sz); G(c.idx) = T.(col); c.data.(key) = G; end
            G = c.data.(key); app.grid = c;
        end

        function renderFull(app)
            % Render the five full-pattern views from one grid. Each axes stores its POB spec in UserData.
            if isempty(app.viewTbl), return; end
            H = app.h; label = app.compLabel(); lim = app.fullLim;
            [G, g] = app.gridOf(app.comp());
            pobTheta = app.pob(2); if app.isElev(), pobTheta = 90 - pobTheta; end
            pobPhi = app.pob(3); if app.isSigned() && pobPhi > 180, pobPhi = pobPhi - 360; end
            [~, r] = min(abs(g.theta - pobTheta)); [~, q] = min(abs(g.phi - pobPhi));
            if app.isElev(), thetaName = 'Elevation'; else, thetaName = 'Theta'; end
            tex = strrep(label, '_', '\_');
            tipRows = [dataTipTextRow(thetaName, g.thetaGrid, '%.3g°'); dataTipTextRow('Phi', g.phiGrid, '%.3g°'); dataTipTextRow(tex, G, '%.3g dB')];
            pobTip = [dataTipTextRow(thetaName, g.thetaGrid(r, q), '%.3g°'); dataTipTextRow('Phi', g.phiGrid(r, q), '%.3g°'); dataTipTextRow(tex, G(r, q), '%.3g dB')];
            for S = H.full
                app.checkCancelled();
                ax = S.ax; cla(ax); hold(ax, 'on'); scale = 1;
                switch S.name
                    case 'contour'
                        sh = pcolor(ax, g.phi, g.theta, G, 'FaceColor', 'interp', 'LineStyle', 'none');
                        app.formatAngularAxes(ax, 30, 15); daspect(ax, [1 1 1]); title(ax, label, 'Interpreter', 'none');
                        pob = [g.phiGrid(r, q), g.thetaGrid(r, q), 1];
                    case 'circular'
                        sh = surface(ax, g.phiRad, g.thetaPolar, zeros(g.sz), G, 'EdgeColor', 'none');
                        rl = 0:30:180; if app.isElev(), rl = 90 - rl; end
                        app.formatPolarAxes(ax); set(ax, 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', rl));
                        title(ax, sprintf('%s  |  r=θ, angle=φ', label), 'Interpreter', 'none', 'FontSize', 9);
                        pob = [g.phiRad(r, q), g.thetaPolar(r, q), 0];
                    case 'rect3D'
                        sh = surf(ax, g.phiGrid, g.thetaGrid, G, 'EdgeColor', 'none');
                        app.formatAngularAxes(ax, 60, 30); grid(ax, 'on'); zlim(ax, lim); applyTicks(ax, 'ZTick', lim, H.Cstep.Value);
                        xlabel(ax, 'Phi (degree)'); ylabel(ax, [thetaName ' (degree)']); zlabel(ax, [label ' (dB)'], 'Interpreter', 'none');
                        title(ax, label, 'Interpreter', 'none');
                        pob = [g.phiGrid(r, q), g.thetaGrid(r, q), G(r, q)];
                    otherwise                                         % sphere3D | polar3D
                        rad = ones(g.sz);
                        if strcmp(S.name, 'polar3D')
                            rad = max(G - lim(1), 0) / max(diff(lim), eps); scale = max(max(rad, [], 'all', 'omitnan'), eps); rad = rad / scale;
                        end
                        sh = surf(ax, rad .* g.x, rad .* g.y, rad .* g.z, G, 'EdgeColor', 'none');
                        app.format3DAxes(ax);
                        title(ax, sprintf('%s  |  θ: %s  |  φ: %s', label, H.ThetaSpan.Value, H.PhiSpan.Value), 'Interpreter', 'none');
                        pob = rad(r, q) * [g.x(r, q), g.y(r, q), g.z(r, q)];
                end
                sh.Tag = 'APAT_Surface';
                app.applyTheme(ax); setTipRows(sh, tipRows);
                ax.UserData = struct('pob', pob, 'tip', pobTip, 'scale', scale);
                hold(ax, 'off'); propagateMenu(ax);
            end
            app.applyView3D(); app.drawOverlays(); app.syncAnnotations();
        end

        function formatAngularAxes(app, ax, phiStep, thetaStep)
            xl = app.phiLimits();
            if app.isElev(), yl = [-90 90]; ydir = 'normal'; else, yl = [0 180]; ydir = 'reverse'; end
            set(ax, 'XLim', xl, 'YLim', yl, 'YDir', ydir, 'Box', 'on', 'Layer', 'top', 'XTick', xl(1):phiStep:xl(2), 'YTick', yl(1):thetaStep:yl(2));
        end

        function formatPolarAxes(app, pax)
            % Keep the polar geometry physical while labelling phi in the selected span.
            angles = 0:30:330; if app.isSigned(), angles(angles > 180) = angles(angles > 180) - 360; end
            set(pax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', angles));
        end

        function format3DAxes(~, ax)
            set(ax, 'XDir', 'normal', 'YDir', 'normal', 'ZDir', 'normal', 'Projection', 'orthographic', 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], ...
                'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1]);
            axis(ax, 'off');
            colors = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            for k = 1:3
                d = 1.35 * double((1:3) == k);
                quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25, 'HandleVisibility', 'off');
                text(ax, 1.12 * d(1), 1.12 * d(2), 1.12 * d(3), labels{k}, 'Color', colors{k}, 'FontWeight', 'bold');
            end
        end

        function applyView3D(app)
            H = app.h; up = [0 0 1];
            switch H.View3D.Value
                case 'top',    v = [0 90];  up = [0 1 0];
                case 'bottom', v = [0 -90]; up = [0 1 0];
                case 'right',  v = [90 0];
                case 'left',   v = [-90 0];
                case 'front',  v = [0 0];
                case 'back',   v = [180 0];
                otherwise,     v = [];
            end
            for k = 3:5
                ax = H.full(k).ax; d = [135 25]; if k == 5, d = [-35 35]; end
                if isempty(v), view(ax, d); else, view(ax, v); end
                camup(ax, up);
            end
        end

        function drawOverlays(app)
            % Trace of the active cut on the two spatial 3-D plots (uses the same radius law as the surface).
            H = app.h;
            for k = 3:4
                ax = H.full(k).ax; delete(findall(ax, 'Tag', 'APAT_CutOverlay'));
                if ~H.Overlay.Value || isempty(app.viewTbl) || ~isstruct(ax.UserData), continue; end
                cut = app.cutData(); v = cut.data(:, 1); lim = app.fullLim;
                if k == 3, rad = 1.02; else, rad = 1.01 * max(v - lim(1), 0) / max(diff(lim), eps) / ax.UserData.scale; end
                held = ishold(ax); hold(ax, 'on');
                plot3(ax, rad .* sind(cut.theta) .* cosd(cut.phi), rad .* sind(cut.theta) .* sind(cut.phi), rad .* cosd(cut.theta), ...
                    'k', 'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay', 'HandleVisibility', 'off');
                if ~held, hold(ax, 'off'); end
            end
        end

        function syncAnnotations(app)
            % Single owner of POB / HPBW annotation visibility. Markers are created lazily from the
            % spec stored in each axes' UserData and only shown on the currently selected tab.
            if app.isClosing, return; end
            H = app.h; showPOB = H.POB.Value; showHPBW = H.HPBWBounds.Value && H.HPBW.Value;
            for S = H.full, app.showPOB(S.ax, showPOB && H.TabPlots.SelectedTab == S.tab); end
            polarOn = H.TabCut.SelectedTab == H.TabPolar;
            app.showPOB(H.PolarCut, showPOB && polarOn); app.showPOB(H.RectCut, showPOB && ~polarOn);
            set(findall(H.PolarCut, 'Tag', 'APAT_HPBW'), 'Visible', showHPBW && polarOn);
            set(findall(H.RectCut, 'Tag', 'APAT_HPBW'), 'Visible', showHPBW && ~polarOn);
        end

        function showPOB(~, ax, visible)
            marks = findall(ax, 'Tag', 'APAT_POB'); spec = ax.UserData;
            if isempty(marks) && visible && isstruct(spec) && isfield(spec, 'pob') && all(isfinite(spec.pob))
                try
                    held = ishold(ax); hold(ax, 'on');
                    if isa(ax, 'matlab.graphics.axis.PolarAxes'), m = polarplot(ax, spec.pob(1), spec.pob(2), 'ko');
                    else, m = plot3(ax, spec.pob(1), spec.pob(2), spec.pob(3), 'ko', 'Clipping', 'off'); end
                    set(m, 'MarkerSize', 5, 'MarkerFaceColor', 'k', 'Tag', 'APAT_POB', 'HandleVisibility', 'off');
                    m.DataTipTemplate.DataTipRows = spec.tip;
                    datatip(m, 'DataIndex', 1, 'Tag', 'APAT_POB', 'FontSize', 9, 'HandleVisibility', 'off');
                    if ~held, hold(ax, 'off'); end
                catch
                end
                marks = findall(ax, 'Tag', 'APAT_POB');
            end
            if ~isempty(marks), set(marks, 'Visible', visible); end
        end

        %% ==================================================================================
        %  Pattern cuts
        %  ==================================================================================
        function [cols, idx] = cutCols(app)
            % Total plus the selected co/cross pair; idx keeps stable line colours.
            H = app.h;
            if app.src.meta.isGainOnly, cols = {app.comp()}; idx = 1; return; end
            if strcmp(H.Basis.Value, 'Linear'), all3 = {'E_Total_dB', 'E_TH_dB', 'E_PH_dB'}; else, all3 = {'E_Total_dB', 'E_RCP_dB', 'E_LCP_dB'}; end
            H.Er.Text = strrep(all3{2}, '_dB', ''); H.El.Text = strrep(all3{3}, '_dB', '');
            sel = logical([H.Et.Value, H.Er.Value, H.El.Value]); if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = all3(idx);
        end

        function cut = cutData(app)
            % The active cut as one closed circle: angles, component columns and physical geometry.
            H = app.h; T = app.viewTbl; [cols, idx] = app.cutCols(); type = string(H.CutType.Value);
            [ang, rows, fixed, sym, snapped] = calcCutGeometry(T, type, H.CutValue.Value, physTheta(T));
            if snapped, app.setStatus(H.Status, sprintf('Requested %s cut snapped to nearest %s = %g°', type, sym, fixed), true); end
            data = T{rows, cols}; pt = physTheta(T); theta = pt(rows); phi = T.Phi(rows);
            if app.isSigned()
                ang(ang > 180) = ang(ang > 180) - 360;
                [ang, o] = sort(ang); data = data(o, :); theta = theta(o); phi = phi(o);
            end
            if app.isSigned() || type == "Phi"
                [ang, u] = unique(ang, 'stable'); data = data(u, :); theta = theta(u); phi = phi(u);
            end
            if type == "Phi"                                                % close the circle at the phi seam
                seam = [0 360]; if app.isSigned(), seam = [-180 180]; end
                lo = any(abs(ang - seam(1)) < 1e-9); hi = any(abs(ang - seam(2)) < 1e-9);
                if lo && ~hi
                    ang(end + 1) = seam(2); data(end + 1, :) = data(1, :); theta(end + 1) = theta(1); phi(end + 1) = phi(1);
                elseif hi && ~lo
                    ang = [seam(1); ang]; data = [data(end, :); data]; theta = [theta(end); theta]; phi = [phi(end); phi];
                elseif ~lo && ~hi
                    w = (seam(2) - ang(end)) / (ang(1) - seam(1) + seam(2) - ang(end)); d = (1 - w) * data(end, :) + w * data(1, :);
                    ang = [seam(1); ang; seam(2)]; data = [d; data; d]; theta = [theta(1); theta; theta(1)]; phi = [seam(1); phi; seam(2)];
                end
            end
            if app.src.meta.isGainOnly, ttl = app.comp(); else, ttl = sprintf('%s cut @ %s = %g°', type, sym, fixed); end
            cut = struct('angle', ang, 'data', data, 'cols', {cols}, 'names', {strrep(cols, '_', '\_')}, 'idx', idx, ...
                'title', ttl, 'theta', theta, 'phi', phi, 'type', type);
        end

        function plotCut(app)
            if isempty(app.viewTbl), return; end
            H = app.h; pax = H.PolarCut; rax = H.RectCut; lim = app.cutLim; xl = app.phiLimits();
            cut = app.cutData(); ang = cut.angle; data = cut.data;
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on');
            pl = polarplot(pax, deg2rad(ang), max(data, lim(1)), 'LineWidth', 1.4);   % clamp: no reflection spikes below RLim
            rl = plot(rax, ang, data, 'LineWidth', 1.4);
            order = rax.ColorOrder; colors = order(1 + mod(cut.idx - 1, size(order, 1)), :);
            for k = 1:numel(pl)
                rows = [dataTipTextRow('Angle', ang, '%.3g°'), dataTipTextRow('Magnitude', data(:, k), '%.3g dB')];
                set([pl(k), rl(k)], 'Color', colors(k, :)); pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            app.formatPolarAxes(pax); set(pax, 'RLim', lim, 'RTick', lim(1):5:lim(2));
            set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, [char(cut.type) ' (degree)']); ylabel(rax, 'Magnitude (dB)');
            title(pax, cut.title, 'Interpreter', 'none'); title(rax, cut.title, 'Interpreter', 'none');
            % POB of the displayed cut = peak of the first plotted trace.
            [pk, ki] = max(data(:, 1), [], 'omitnan');
            tip = [dataTipTextRow('Angle', ang(ki), '%.3g°'); dataTipTextRow('Magnitude', pk, '%.3g dB')];
            pax.UserData = struct('pob', [deg2rad(ang(ki)), max(pk, lim(1)), 0], 'tip', tip);
            rax.UserData = struct('pob', [ang(ki), pk, 0], 'tip', tip);
            % HPBW: wrap-aware shaded region, label and interpolated -3 dB boundary markers.
            H.HPBWLabel.Text = ''; H.HPBWBounds.Visible = H.HPBW.Value;
            if ~H.HPBW.Value, H.HPBWBounds.Value = false; end
            if H.HPBW.Value && isfinite(pk)
                [bw, lo, hi] = calcHPBW(ang, data(:, 1), pk, ang(ki));
                if isfinite(bw)
                    b = [lo hi]; if xl(1) < 0, b = mod(b + 180, 360) - 180; else, b = mod(b, 360); end
                    H.HPBWLabel.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                    if b(1) <= b(2), reg = b; else, reg = [xl(1), b(2); b(1), xl(2)]; end
                    thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    xregion(rax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    names = {'Lower HPBW', 'Upper HPBW'};
                    for k = 1:2
                        rows = [dataTipTextRow(names{k}, b(k), '%.2f°'); dataTipTextRow('Gain', pk - 3, '%.2f dB')];
                        m = [polarplot(pax, deg2rad(b(k)), pk - 3, 'o'), plot(rax, b(k), pk - 3, 'o')];
                        set(m, 'Color', '#D95319', 'MarkerFaceColor', '#D95319', 'Tag', 'APAT_HPBW', 'HandleVisibility', 'off');
                        for mk = m, setTipRows(mk, rows); try, datatip(mk, 'DataIndex', 1, 'Tag', 'APAT_HPBW', 'HandleVisibility', 'off'); catch, end, end
                    end
                end
            end
            legend(pax, pl, cut.names, 'Location', 'southoutside', 'Orientation', 'horizontal');
            legend(rax, rl, cut.names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off');
            app.syncAnnotations();
        end

        function values = updateCutControl(app)
            % The spinner holds the fixed theta for Phi cuts and the fixed phi for Theta cuts.
            H = app.h; T = app.viewTbl;
            if strcmp(H.CutType.Value, 'Phi'), values = unique(T.Theta); else, values = unique(mod(T.Phi, 360)); end
            H.CutValue.Limits = [-90 360];                             % widen first so snapping can never violate Limits
            [~, k] = min(abs(values - H.CutValue.Value)); H.CutValue.Value = values(k);
            H.CutValue.Limits = [min(values), max(values)];
            if numel(values) > 1, H.CutValue.Step = min(diff(values)); end
        end

        function syncPlaneCut(app)
            % E-plane: theta cut through the boresight axis; H-plane: the orthogonal principal cut.
            H = app.h; A = app.Axes6; k = app.boresight;
            if strcmp(H.Plane.Value, 'E'), type = 'Theta'; value = A.phi(k);
            elseif A.theta(k) == 90,       type = 'Phi';   value = 90 * ~app.isElev();   % polar 90° == elevation 0°
            else,                          type = 'Theta'; value = 90;
            end
            H.CutType.Value = type; values = app.updateCutControl();
            [~, i] = min(abs(values - value)); H.CutValue.Value = values(i);
        end

        function onPlaneChanged(app, ~, ~)
            if isempty(app.viewTbl), return; end
            app.syncPlaneCut(); app.onCutChanged();
        end

        function onCutChanged(app, src, ~)
            if isempty(app.viewTbl), return; end
            H = app.h;
            if nargin > 1 && isequal(src, H.CutType), app.updateCutControl(); end
            if nargin > 1 && isequal(src, H.Basis), app.autoBasis = false; app.updateMetadata(); end
            app.plotCut(); app.drawOverlays();
        end

        %% ==================================================================================
        %  Export
        %  ==================================================================================
        function fp = saveTable(app, T, defaultName, filters, dialogTitle)
            fp = '';
            [f, p] = uiputfile(filters, dialogTitle, fullfile(app.src.folder, defaultName));
            if isequal(f, 0), return; end
            fp = fullfile(p, f); writeAny(T, fp);
        end

        function exportResults(app, ~, ~)
            fp = app.saveTable(app.h.TableOut.Data, [app.src.base '_APAT_results.csv'], tableFilters(true), 'Export Results');
            if ~isempty(fp), app.setStatus(app.h.Status, ['Results exported to <b>' fp '</b>'], true); end
        end

        function exportCut(app, ~, ~)
            cut = app.cutData();
            T = array2table([cut.angle, cut.data], 'VariableNames', [{'Angle_deg'}, cut.cols]);
            fp = app.saveTable(T, [app.src.base '_cut.csv'], tableFilters(false), 'Export Cut');
            if ~isempty(fp), app.setStatus(app.h.Status, ['Cut (' cut.title ') exported to <b>' fp '</b>'], true); end
        end

        function exportUAN(app, ~, ~)
            T = app.viewTbl;
            assert(all(ismember({'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase'}, T.Properties.VariableNames)), 'UAN export requires processed E-field columns.');
            U = table(physTheta(T), T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'});
            U = sortrows(U, {'Phi', 'Theta'});
            step = gridStep(U.Theta); if ~isfinite(step), step = 1; end
            gmax = max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan');
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, ...
                'Export UAN / E-field data', fullfile(app.src.folder, sprintf('%s_%.5f_%gdeg.uan', app.src.base, gmax, step)));
            if isequal(f, 0), return; end
            fp = fullfile(p, f);
            if endsWith(fp, '.uan', 'IgnoreCase', true)
                hdr = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                    min(U.Phi), max(U.Phi), gridStep(mod(U.Phi, 360)), min(U.Theta), max(U.Theta), step, gmax);
                writelines(hdr, fp);
                writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
            else
                writeAny(U, fp);
            end
            app.setStatus(app.h.Status, ['UAN exported to <b>' fp '</b>'], true);
        end

        %% ==================================================================================
        %  Coverage
        %  ==================================================================================
        function nodes = covNodes(app, kind, roots)
            % All tree nodes of one kind (optionally within a subtree); jobs in run order.
            if nargin < 3, roots = app.h.TreeRoot; end
            nodes = findobj(roots);
            nodes = nodes(arrayfun(@(n) isstruct(n.NodeData) && strcmp(n.NodeData.kind, kind), nodes));
            if strcmp(kind, 'job') && numel(nodes) > 1, [~, o] = sort(arrayfun(@(n) n.NodeData.id, nodes)); nodes = nodes(o); end
        end

        function node = covTarget(app)
            % Pattern node to compute on: the selection's owning pattern, else the most recent pattern.
            node = []; n = app.h.Tree.SelectedNodes;
            while ~isempty(n) && isa(n(1), 'matlab.ui.container.TreeNode')
                if isstruct(n(1).NodeData) && strcmp(n(1).NodeData.kind, 'pattern'), node = n(1); return; end
                n = n(1).Parent;
            end
            pats = app.covNodes('pattern'); if ~isempty(pats), node = pats(end); end
        end

        function node = covFind(app, fp)
            node = [];
            for n = app.h.TreeRoot.Children(:).'
                if isstruct(n.NodeData) && isfield(n.NodeData, 'path') && strcmp(n.NodeData.path, fp), node = n; return; end
            end
        end

        function setCoverageUI(app)
            % Enable state follows content: a pattern enables compute, any job enables the result actions.
            H = app.h; hasPattern = ~isempty(app.covNodes('pattern')); hasJobs = ~isempty(app.covNodes('job'));
            set([H.CovCompute, H.CovComp, H.CovCompLabel], 'Enable', hasPattern);
            H.CovReset.Enable = hasPattern || hasJobs;
            set([H.CovExport, H.CovClear, H.QueryCovBtn, H.QueryThrBtn], 'Enable', hasJobs);
            set([H.ConeLabels, H.ConeTh, H.ConePh, H.ConeAng, H.Orient, H.OrientLabel], 'Enable', H.Conical.Value);
        end

        function onToCoverage(app, ~, ~)
            % Coverage always receives the CURRENT Main view table (loss, step and span already applied).
            H = app.h; H.Tabs.SelectedTab = H.TabCov; H.CovPath.Value = app.src.path;
            node = app.covFind(app.src.path);
            if isempty(node), app.covAddPattern(app.src.base, app.viewTbl, app.src.path, app.src.rawTbl);
            else, app.covSyncFromView(node); H.Tree.SelectedNodes = node; app.setCoverageUI(); end
            H.PanelResults.Visible = 'on';
            app.setStatus(H.CovStatus, 'Coverage source synchronized from the current Main-tab View Table.', false);
        end

        function onCovLoad(app, ~, ~)
            H = app.h; fp = strtrim(H.CovPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFind(fp)), fp = pickFile(); if isempty(fp), return; end, end
            existing = app.covFind(fp);
            if ~isempty(existing)
                H.Tree.SelectedNodes = existing; app.onTreeSelection(); H.CovPath.Value = fp;
                app.setStatus(H.CovStatus, 'File already loaded -- node selected.', true); return
            end
            H.CovPath.Value = fp;
            out = app.readSourceUI(fp, H.CovFormatLabel, H.CovFormat);
            if out.meta.isCoverage, app.covLoadResults(fp, out.rawTbl);
            else, [~, name] = fileparts(fp); app.covAddPattern(name, app.buildPattern(out), fp, out.rawTbl); end
            H.PanelResults.Visible = 'on';
        end

        function onCovFormatChanged(app, ~, ~)
            H = app.h; fp = strtrim(H.CovPath.Value); node = app.covFind(fp);
            if isempty(node) || ~isGenericText(fp) || ~strcmp(node.NodeData.kind, 'pattern'), return; end
            out = readSource(fp, H.CovFormat.Value, node.NodeData.raw);
            if out.meta.isCoverage, app.setStatus(H.CovStatus, 'Coverage-result files are detected automatically.', true); return; end
            name = node.NodeData.name;
            for j = app.covNodes('job', node).', delete(j.NodeData.line); end
            delete(node);
            app.covAddPattern(name, app.buildPattern(out), fp, out.rawTbl); app.covRefresh();
            app.setStatus(H.CovStatus, sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
        end

        function node = covAddPattern(app, name, T, fp, raw)
            if nargin < 5, raw = table(); end
            H = app.h; node = uitreenode(H.TreeRoot, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', 'pattern', 'name', name, 'path', fp, 'pattern', T, 'raw', raw, ...
                'dOmega', solidWeights(physTheta(T), T.Phi), 'component', '', 'boresight', 1);
            expand(H.Tree); H.Tree.CheckedNodes = [H.Tree.CheckedNodes; node]; H.Tree.SelectedNodes = node;
            app.covSyncPattern(node); app.setCoverageUI();
            app.setStatus(H.CovStatus, sprintf('Pattern <b>%s</b> added — ready to compute coverage.', name), false);
        end

        function covSyncFromView(app, node)
            d = node.NodeData; T = app.viewTbl;
            d.pattern = T; d.dOmega = solidWeights(physTheta(T), T.Phi); d.name = app.src.base; d.component = '';
            node.NodeData = d; app.covSyncPattern(node);
        end

        function covSyncPattern(app, node)
            % Component list, detected boresight and the automatic threshold preset for one pattern node.
            H = app.h; d = node.NodeData; T = d.pattern; [cols, labels] = componentMap(T);
            if ~isequal(string(H.CovComp.ItemsData), cols), H.CovComp.Items = cellstr(labels); H.CovComp.ItemsData = cellstr(cols); end
            prev = d.component; if isempty(prev), prev = H.CovComp.Value; end
            c = preferredComponent(prev, cols); H.CovComp.Value = c;
            if ~strcmp(d.component, c)
                g = T.(c); if isAR(c), g = chooseGain(T, 'E_Total_dB'); end
                [~, ~, d.boresight] = calcOrientation(T, g, d.dOmega, app.Axes6, app.PeakPct, app.PeakExcess);
                d.component = c; node.NodeData = d;
                if H.Orient.Value == 0, app.onOrientChanged(); end   % Auto orientation follows the detected axis
            end
            key = string(sprintf('%s|%s|%d', d.path, c, height(T)));
            if app.covPresetKey ~= key                                 % preset only when pattern/component/view changes
                app.covPresetKey = key; b = peakWindow(T.(c), app.PeakPct, app.PeakExcess);
                set([H.ThrMin, H.ThrMax], 'Limits', app.DbLimits); H.ThrMin.Value = b(1); H.ThrMax.Value = b(2);
            end
        end

        function thr = covThresholds(app)
            H = app.h; lo = H.ThrMin.Value; hi = H.ThrMax.Value; st = max(H.ThrStep.Value, 0.1);
            if hi <= lo, hi = min(app.DbLimits(2), lo + st); H.ThrMax.Value = hi; end
            thr = (lo:st:hi).'; if thr(end) < hi, thr(end + 1) = hi; end
        end

        function onCovCompute(app, ~, ~)
            H = app.h; node = app.covTarget();
            if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if strcmp(node.NodeData.path, app.src.path) && ~isempty(app.viewTbl), app.covSyncFromView(node); end
            d = node.NodeData; T = d.pattern; c = H.CovComp.Value; thr = app.covThresholds();
            conical = H.Conical.Value; orient = "n/a";
            if conical
                k = H.Orient.Value; if k == 0, k = d.boresight; end
                orient = string(app.Axes6.labels{k});
                th0 = H.ConeTh.Value; ph0 = mod(H.ConePh.Value, 360); alpha = H.ConeAng.Value; pt = physTheta(T);
                mask = cosd(pt) * cosd(th0) + sind(pt) * sind(th0) .* cosd(T.Phi - ph0) >= cosd(alpha);
                center = app.coneLabel(th0, ph0);
                label = sprintf('Conical coverage (%s) α=%s°', center, fmtNum(alpha));
                tag = sprintf('Con %s α%s°', erase(center, ["=", ","]), fmtNum(alpha));
            else
                mask = true(height(T), 1); label = 'Sph coverage'; tag = 'Sph';
            end
            cov = coverageCCDF(T.(c), mask, thr, d.dOmega);
            job = app.covAddJob(node, thr, cov, label, tag, c, conical, orient);
            app.covRefresh(); app.setCovXRange([thr(1), thr(end)]); H.PanelResults.Visible = 'on';
            msg = sprintf('Run-<b>%d</b> computed: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', job.NodeData.id, label, d.name, c, numel(thr));
            if conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, orient); end
            app.setStatus(H.CovStatus, msg, false);
        end

        function label = coneLabel(app, theta, phi)
            % Principal-axis name when the cone centre matches ±X/±Y/±Z exactly, else the coordinates.
            A = app.Axes6; c = [sind(theta) * cosd(phi), sind(theta) * sind(phi), cosd(theta)];
            av = [sind(A.theta(:)) .* cosd(A.phi(:)), sind(A.theta(:)) .* sind(A.phi(:)), cosd(A.theta(:))];
            k = find(av * c(:) >= 1 - 1e-9, 1);
            if isempty(k), label = sprintf('θ=%s°, φ=%s°', fmtNum(theta), fmtNum(phi)); else, label = A.labels{k}; end
        end

        function node = covAddJob(app, parent, thr, cov, label, tag, comp, conical, orient)
            H = app.h; app.covRunID = app.covRunID + 1;
            icon = '📉'; if strcmp(tag, 'Res'), icon = '📈'; end
            txt = sprintf('%s R%d %s · %s', icon, app.covRunID, label, comp);
            ln = plot(H.CovAxes, thr, cov, 'LineWidth', 1.6, 'DisplayName', txt);
            node = uitreenode(parent, 'Text', txt);
            node.NodeData = struct('kind', 'job', 'id', app.covRunID, 'thr', thr(:), 'cov', cov(:), 'line', ln, 'tag', tag, 'conical', conical, 'orient', orient);
            expand(parent); H.Tree.CheckedNodes = [H.Tree.CheckedNodes; node];
        end

        function covLoadResults(app, fp, R)
            H = app.h; [~, name] = fileparts(fp);
            node = uitreenode(H.TreeRoot, 'Text', ['📄 ' name]);
            node.NodeData = struct('kind', 'results', 'name', name, 'path', fp);
            H.Tree.CheckedNodes = [H.Tree.CheckedNodes; node];
            thr = R{:, 1};
            for k = 2:width(R), app.covAddJob(node, thr, R{:, k}, 'Res', 'Res', R.Properties.VariableNames{k}, false, "n/a"); end
            expand(H.TreeRoot); app.covRefresh(); app.setCovXRange([min(thr), max(thr)]);
            if gridStep(thr) < H.ThrStep.Value, H.ThrStep.Value = max(gridStep(thr), 0.1); end
            H.PanelResults.Visible = 'on';
            app.setStatus(H.CovStatus, sprintf('Coverage results file "%s" loaded (%d curves).', name, width(R) - 1), false);
        end

        function a = covArtifacts(app, d)
            % Query projections live in the axes, DataTips on the curve; both are tagged by job id.
            a = [findall(app.h.CovAxes, 'Tag', sprintf('CovQ_%d', d.id)); findall(d.line, 'Type', 'datatip')];
        end

        function covRefresh(app)
            % The tree's checked state is the single source of truth: line visibility, legend and table follow it.
            H = app.h; jobs = app.covNodes('job'); checked = H.Tree.CheckedNodes;
            on = false(size(jobs));
            for k = 1:numel(jobs)
                d = jobs(k).NodeData; on(k) = hasNode(checked, jobs(k));
                d.line.Visible = on(k); set(app.covArtifacts(d), 'Visible', on(k));
            end
            shown = jobs(on);
            lines = gobjects(1, numel(shown)); for k = 1:numel(shown), lines(k) = shown(k).NodeData.line; end
            if isempty(shown), legend(H.CovAxes, 'off'); else, legend(H.CovAxes, lines, {shown.Text}, 'Location', 'southwest', 'Interpreter', 'none'); end
            thr = app.covThresholds();
            if ~isempty(shown), c = arrayfun(@(n) n.NodeData.thr, shown, 'UniformOutput', false); thr = unique(vertcat(c{:})); end
            M = nan(numel(thr), numel(shown) + 1); M(:, 1) = thr; names = cell(1, numel(shown) + 1); names{1} = 'Threshold (dB)';
            for k = 1:numel(shown)
                d = shown(k).NodeData; M(:, k + 1) = interp1(d.thr, d.cov, thr, 'linear', NaN); names{k + 1} = sprintf('R%d %s %%', d.id, d.tag);
            end
            H.CovTable.Data = array2table(compose('%.2f', M), 'VariableNames', names);
            app.setCoverageUI();
        end

        function covQuery(app, mode)
            % Project a threshold ("cov") or a coverage level ("thr") onto every checked job under the selection.
            H = app.h; ax = H.CovAxes; sel = H.Tree.SelectedNodes;
            if isempty(sel), app.setStatus(H.CovStatus, 'Select a node to query.', true); return; end
            jobs = app.covNodes('job', sel(1)); jobs = jobs(arrayfun(@(n) hasNode(H.Tree.CheckedNodes, n), jobs));
            if isempty(jobs), app.setStatus(H.CovStatus, 'No checked results under the selected node.', true); return; end
            hit = false;
            for n = jobs(:).'
                d = n.NodeData; tag = sprintf('CovQ_%d', d.id); delete(app.covArtifacts(d));
                if mode == "cov", x = H.QueryCov.Value; y = interp1(d.thr, d.cov, x, 'linear', NaN);
                else, y = H.QueryThr.Value; x = inverseCoverage(d, y); end
                if ~isfinite(x) || ~isfinite(y), continue; end
                line(ax, [x x], [ax.YLim(1) y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [app.DbLimits(1) x], [y y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                d.line.DataTipTemplate.DataTipRows = [dataTipTextRow('Threshold', 'XData', '%.2f dB'); dataTipTextRow('Coverage', 'YData', '%.2f%%')];
                datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'FontSize', 9, 'Tag', tag, 'HandleVisibility', 'off');
                hit = true;
            end
            if ~hit,              app.setStatus(H.CovStatus, 'Query value is outside the selected checked range.', true);
            elseif mode == "cov", app.setStatus(H.CovStatus, sprintf('Coverage queried at %s dB.', fmtNum(H.QueryCov.Value)), false);
            else,                 app.setStatus(H.CovStatus, sprintf('Threshold queried at %s%% coverage.', fmtNum(H.QueryThr.Value)), false);
            end
        end

        function onTreeSelection(app, ~, ~)
            H = app.h; sel = H.Tree.SelectedNodes;
            for n = app.covNodes('job').', d = n.NodeData; d.line.LineWidth = 1.6; end
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(H.CovStatus, 'Ready.', false); return; end
            d = sel(1).NodeData; pat = app.covTarget();
            if ~isempty(pat), app.covSyncPattern(pat); end
            if ~strcmp(d.kind, 'job')
                kindName = 'Pattern'; if strcmp(d.kind, 'results'), kindName = 'Results'; end
                app.setStatus(H.CovStatus, sprintf('%s <b>"%s"</b> -- <b>%d</b> coverage job(s).', kindName, d.name, numel(sel(1).Children)), false);
                if strcmp(d.kind, 'pattern') && H.Conical.Value, app.reportOrientation(); end
                return
            end
            d.line.LineWidth = 2.6;                                                  % visual emphasis only
            t50 = inverseCoverage(d, 50); shown = round(d.cov, 2); mi = find(shown == max(shown), 1, 'last');
            parts = {sel(1).Text};
            if d.conical, parts{end + 1} = sprintf('Orientation <b>%s</b>', d.orient); end
            parts{end + 1} = sprintf('Threshold [%s, %s] dB, step %s dB', fmtNum(d.thr(1)), fmtNum(d.thr(end)), fmtNum(gridStep(d.thr)));
            if isfinite(t50), parts{end + 1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', fmtNum(t50)); else, parts{end + 1} = '<b>50%-coverage unavailable</b>'; end
            if isempty(mi), parts{end + 1} = 'max <b>n/a</b>'; else, parts{end + 1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmtNum(shown(mi)), fmtNum(d.thr(mi))); end
            app.setStatus(H.CovStatus, strjoin(parts, ' | '), false);
        end

        function onCovTypeChanged(app, ~, ~)
            H = app.h; app.setCoverageUI();
            if H.Conical.Value
                node = app.covTarget(); if ~isempty(node), app.covSyncPattern(node); end
                app.reportOrientation();
            else
                H.CovStatus.Text = regexprep(H.CovStatus.Text, '\s*\|\s*Orientation <b>.*?</b>', '');
            end
        end

        function onOrientChanged(app, ~, ~)
            % Auto (0) resolves the detected boresight; explicit choices are authoritative.
            H = app.h; k = H.Orient.Value;
            if k == 0, node = app.covTarget(); if isempty(node), return; end, k = node.NodeData.boresight; end
            H.ConeTh.Value = app.Axes6.theta(k); H.ConePh.Value = app.Axes6.phi(k);
            app.reportOrientation();
        end

        function reportOrientation(app)
            H = app.h; if ~H.Conical.Value, return; end
            k = H.Orient.Value;
            if k == 0, node = app.covTarget(); if isempty(node), return; end, k = node.NodeData.boresight; end
            msg = regexprep(H.CovStatus.Text, '\s*\|\s*Orientation <b>.*?</b>$', '');
            app.setStatus(H.CovStatus, sprintf('%s | Orientation <b>%s</b>', msg, app.Axes6.labels{k}), false);
        end

        function onCovComponentChanged(app, ~, ~)
            node = app.covTarget(); if isempty(node), return; end
            d = node.NodeData; d.component = ''; node.NodeData = d;      % force re-detection for the new component
            app.covSyncPattern(node);
        end

        function onCovXRange(app, src, evt)
            % Spinners are the master (they define the slider travel); the slider only moves within it.
            H = app.h; L = app.DbLimits; fromSlider = isequal(src, H.XRange);
            if fromSlider
                b = sort(evt.Value); if diff(b) <= 0, return; end
            else
                b = sort([H.XMin.Value, H.XMax.Value]);
                if diff(b) <= 0, if isequal(src, H.XMin), b(2) = min(L(2), b(1) + 1); else, b(1) = max(L(1), b(2) - 1); end, end
            end
            app.applyCovX(b, fromSlider);
        end

        function setCovXRange(app, b)
            % The first curve sets the X baseline; later curves may only widen it.
            if app.covXInit, b = [min(app.h.CovAxes.XLim(1), b(1)), max(app.h.CovAxes.XLim(2), b(2))]; end
            app.covXInit = true; app.applyCovX(clampRange(b, app.DbLimits), false);
        end

        function applyCovX(app, b, fromSlider)
            H = app.h; L = app.DbLimits;
            set([H.XMin, H.XMax], 'Limits', L); H.XMin.Value = b(1); H.XMax.Value = b(2);
            H.XMin.Limits = [L(1), b(2) - 0.1]; H.XMax.Limits = [b(1) + 0.1, L(2)];
            if ~fromSlider, H.XRange.Limits = L; H.XRange.Value = b; H.XRange.Limits = b; end
            set(H.CovAxes, 'XLimMode', 'manual', 'XLim', b);
        end

        function onCovReset(app, ~, ~)
            H = app.h;
            delete(findall(H.CovAxes, 'Type', 'datatip')); delete(H.TreeRoot.Children);
            cla(H.CovAxes); legend(H.CovAxes, 'off'); hold(H.CovAxes, 'on'); ylim(H.CovAxes, [0 100]); H.CovTable.Data = table();
            app.covRunID = 0; app.covPresetKey = ""; app.covXInit = false;
            app.applyCovX([-40 10], false); H.CovAxes.XLimMode = 'auto';
            H.PanelResults.Visible = 'off'; app.setCoverageUI();
            app.setStatus(H.CovStatus, 'Coverage workspace reset 🔄', true);
        end

        function onCovClear(app, ~, ~)
            H = app.h; sel = H.Tree.SelectedNodes;
            if isempty(sel), app.setStatus(H.CovStatus, 'Select a node to clear.', true); return; end
            for n = app.covNodes('job', sel(1)).', delete(app.covArtifacts(n.NodeData)); end
            app.setStatus(H.CovStatus, 'Selected DataTips and query markers cleared.', true);
        end

        function onCovExport(app, ~, ~)
            if isempty(app.h.CovTable.Data), return; end
            fp = app.saveTable(app.h.CovTable.Data, 'coverage_results.csv', tableFilters(true), 'Export Coverage Results');
            if ~isempty(fp), app.setStatus(app.h.CovStatus, ['Coverage results exported to ' fp], true); end
        end

        %% ==================================================================================
        %  Self-test (model layer only; no UI interaction)
        %  ==================================================================================
        function report = runSelfTest(app)
            %RUNSELFTEST Deterministic numerical checks; errors if any check fails.
            [P, T] = meshgrid(0:30:330, (0:30:180).');
            G = table(T(:), P(:), 10 * cosd(T(:) / 2).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            w = solidWeights(G.Theta, G.Phi);
            [~, pk, k] = calcOrientation(G, G.E_Total_dB, w, app.Axes6, app.PeakPct, app.PeakExcess);
            r.passSolidAngle = abs(sum(w) - 4 * pi) < 1e-9;
            r.passOrientation = isfinite(pk.value) && k == 1;
            % A 2° E-field grid resampled to 1° reproduces the analytic field exactly on native nodes.
            [P2, T2] = meshgrid(0:2:358, (0:2:180).'); f = @(t, p) 12 * cosd(t).^2 - 0.5 * sind(p).^2; z = zeros(numel(T2), 1);
            S = table(T2(:), P2(:), f(T2(:), P2(:)), z, z, z, 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
            R = resample1deg(S); native = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0;
            r.passResampling = height(R) == 181 * 361 && max(abs(R.Re_Eth(native) - f(R.Theta(native), R.Phi(native)))) < 1e-9;
            r.passPeakWindow = isequal(peakWindow([3.2; -100], app.PeakPct, app.PeakExcess), [-45 5]);
            spike = repmat(0.02, 100000, 1); spike(1) = 10.02; sp = resolvePeak(spike, app.PeakPct, app.PeakExcess);
            r.passIsolatedSpike = sp.wasAdjusted && abs(sp.value - 0.02) < 1e-12 && sp.rawIndex == 1 && isequal(peakWindow(spike, app.PeakPct, app.PeakExcess), [-45 5]);
            % HPBW of a cos^2 power pattern is 90° (E-plane through phi = 0/180).
            theta = repmat((0:180).', 2, 1); phi = [zeros(181, 1); 180 * ones(181, 1)];
            cut = table(theta, phi, 20 * log10(max(abs(cosd(theta)), 1e-6)), 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            [ang, rows] = calcCutGeometry(cut, "Theta", 0, cut.Theta);
            r.passHPBW = abs(calcHPBW(ang, cut.E_Total_dB(rows)) - 90) < 0.2;
            r.passCoverage = isequal(round(coverageCCDF(G.E_Total_dB, true(height(G), 1), [-1; 11], w), 6), [100; 0]);
            r.passARSemantic = all(cellfun(@isAR, {'AR', 'AR_dB', 'AR dB', 'Axial Ratio', 'Axial_Ratio'})) && ~isAR('E_Total_dB');
            % FFD reader: two axis triples, a frequency count line and one "Frequency" separator.
            ffd = [tempname '.ffd']; c = onCleanup(@() delete(ffd)); %#ok<NASGU>
            writelines(["0 180 3"; "-180 180 3"; "Frequencies 1"; "Frequency 1e9"; compose("%d 0 0 1", (1:9).')], ffd);
            d = readSource(ffd, "gain", table());
            r.passFFDReader = strcmp(d.meta.source, 'HFSS FFD') && isscalar(d.blocks) && height(d.blocks{1}) == 9 && d.freqs(1) == 1e9;
            ok = structfun(@(x) x, r); report = r; report.pass = all(ok);
            if ~all(ok)
                names = fieldnames(r);
                error('apat:test:SelfTestFailed', 'Self-test failed: %s', strjoin(names(~ok), ', '));
            end
        end
    end
end

%% ==========================================================================================
%  UI helpers
%  ==========================================================================================
function c = place(c, row, col)
c.Layout.Row = row; c.Layout.Column = col;
end

function c = lbl(parent, text, row, col, varargin)
c = place(uilabel(parent, 'Text', text, 'HorizontalAlignment', 'right', varargin{:}), row, col);
end

function dd = formatDropdown(parent, callback, varargin)
dd = uidropdown(parent, 'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
    '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
    '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
    'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'}, ...
    'Value', 'gain', 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'ValueChangedFcn', callback, varargin{:});
end

function propagateMenu(ax)
% Children created after the axes' context menu need the same menu for right-click DataTip actions.
kids = findall(ax, '-property', 'ContextMenu');
set(kids(kids ~= ax), 'ContextMenu', ax.ContextMenu);
end

function setTipRows(obj, rows)
try
    obj.DataTipTemplate.DataTipRows = rows;
catch
    try, delete(datatip(obj, 'DataIndex', 1)); obj.DataTipTemplate.DataTipRows = rows; catch, end
end
end

function applyTicks(obj, prop, lim, step)
% Ticks at multiples of step inside lim, always including both ends (auto mode when unusable).
t = [];
if isfinite(step) && step > 0 && diff(lim) > 0
    t = unique([lim(1), ceil(lim(1) / step) * step:step:floor(lim(2) / step) * step, lim(2)], 'stable');
    if numel(t) > 60, t = []; end
end
if isempty(t), obj.([prop 'Mode']) = 'auto'; else, obj.(prop) = t; end
end

function fp = pickFile()
fp = '';
[f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage files'; '*.*', 'All files'}, ...
    'Select an antenna pattern or coverage results file');
if ~isequal(f, 0), fp = fullfile(p, f); end
end

function filters = tableFilters(withExcel)
filters = {'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'};
if withExcel, filters(end + 1, :) = {'*.xlsx', 'Excel (*.xlsx)'}; end
end

function writeAny(T, fp)
if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
end

function s = fmtNum(v, prec)
%fmtNum 'n/a' for non-finite; compact (<= 2 decimals, no trailing zeros) or a fixed precision.
if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); else, s = sprintf('%.*f', prec, v); end
end

%% ==========================================================================================
%  Model helpers
%  ==========================================================================================
function tf = isAR(name)
k = regexprep(lower(strtrim(char(name))), '[^a-z0-9]', '');
tf = strcmp(k, 'ar') || startsWith(k, 'ardb') || startsWith(k, 'axialratio');
end

function tf = isGenericText(fp)
[~, ~, e] = fileparts(char(fp)); tf = any(strcmpi(e, {'.csv', '.txt', '.dat'}));
end

function theta = physTheta(T)
% Physical polar theta of a table regardless of the display convention it carries.
theta = T.Theta; ud = T.Properties.UserData;
if isstruct(ud) && isfield(ud, 'elevation') && ud.elevation, theta = 90 - theta; end
end

function [thetaStep, phiStep] = tableSteps(T)
thetaStep = gridStep(T.Theta); phiStep = gridStep(mod(T.Phi, 360));
if ~isfinite(thetaStep), thetaStep = 1; end
if ~isfinite(phiStep), phiStep = thetaStep; end
end

function s = gridStep(v)
%gridStep Smallest positive sample spacing (NaN for a single value).
v = unique(v(isfinite(v))); d = diff(v); d = d(d > 1e-9);
if isempty(d), s = NaN; else, s = min(d); end
end

function r = clampRange(v, b)
%clampRange Sorted, clamped to b, at least one unit wide.
v = sort(double(v(:).'));
if numel(v) < 2 || any(~isfinite(v(1:2))), r = b; return; end
r = [max(b(1), v(1)), min(b(2), v(2))];
if diff(r) < 1, r(2) = min(b(2), r(1) + 1); r(1) = max(b(1), r(2) - 1); end
end

function v = percentile(x, p)
%percentile Same definition as MATLAB's prctile (order statistics at (i-0.5)/n) without a toolbox.
x = sort(x(:)); n = numel(x); q = 100 * ((1:n).' - 0.5) / n;
if n == 1 || p <= q(1), v = x(1); elseif p >= q(end), v = x(end); else, v = interp1(q, x, p); end
end

function g = chooseGain(T, want)
%chooseGain Requested column, else E_Total_dB, else the first data column.
v = T.Properties.VariableNames; c = find(ismember({char(want), 'E_Total_dB'}, v), 1);
if isempty(c), g = T.(v{3}); elseif c == 1, g = T.(char(want)); else, g = T.E_Total_dB; end
end

function [cols, labels] = componentMap(T)
%componentMap Plottable component columns with their user-facing labels.
avail = string(T.Properties.VariableNames(3:end)); ud = T.Properties.UserData;
if isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly, cols = avail; labels = avail; return; end
cols = ["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "AR_dB", "Gain_PolCorrected_dB"];
labels = ["Total Gain", "Etheta Gain", "Ephi Gain", "RHCP Gain", "LHCP Gain", "Axial Ratio", "Polarized Gain"];
keep = ismember(cols, avail); cols = cols(keep); labels = labels(keep);
end

function c = preferredComponent(prev, cols)
c = string(prev);
if ~any(cols == c), c = cols(1); if any(cols == "E_Total_dB"), c = "E_Total_dB"; end, end
c = char(c);
end

function tf = hasNode(list, n)
tf = any(arrayfun(@(x) isequal(x, n), list));
end

function x = inverseCoverage(d, y)
%inverseCoverage Threshold at which a (monotonic) coverage curve reaches y percent.
[cu, iu] = unique(d.cov, 'last');
if numel(cu) < 2, x = NaN; else, x = interp1(cu, d.thr(iu), y, 'linear', NaN); end
end

%% ==========================================================================================
%  Numerical model (pure functions)
%  ==========================================================================================
function T = normalizePattern(T)
%normalizePattern Canonical sphere: Theta in [0,180], Phi in [0,360], unique directions, closed phi seam.
theta = T.Theta;
if any(theta < 0)
    if min(theta) >= -90 && max(theta) <= 90, T.Theta = 90 - theta;                     % elevation convention
    else, neg = theta < 0; T.Theta(neg) = -theta(neg); T.Phi(neg) = T.Phi(neg) + 180; end
end
T.Theta = mod(T.Theta, 360); over = T.Theta > 180;
T.Theta(over) = 360 - T.Theta(over); T.Phi(over) = T.Phi(over) + 180;
T.Phi = mod(T.Phi, 360);
num = varfun(@isnumeric, T, 'OutputFormat', 'uniform');
T{:, num} = round(T{:, num}, 5);                                                        % remove float seam artefacts once
[~, u] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(u, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function R = resample1deg(S)
%resample1deg Canonical 1° grid (theta 0..180 x phi 0..360) from the primitive source columns.
% Sub-degree grids that already contain every integer-degree sample are decimated exactly; otherwise
% fields (Re/Im) are interpolated linearly and gain-only columns in linear power (regular grids use
% interp2 with periodic phi closure, irregular samples a scattered interpolant).
ud = S.Properties.UserData; gainMode = isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly;
theta = S.Theta; phi = mod(S.Phi, 360); keep = abs(S.Phi - 360) > 1e-9;
onGrid = abs(theta - round(theta)) < 1e-9 & abs(phi - round(phi)) < 1e-9;
if gridStep(theta) < 1 && gridStep(phi) < 1 && nnz(onGrid & keep) == 181 * 360
    R = S(onGrid, :); R.Properties.UserData = ud; return
end
S = S(keep, :); theta = theta(keep); phi = phi(keep);
[~, u] = unique([theta, phi], 'rows', 'stable'); S = S(u, :); theta = theta(u); phi = phi(u);
[QP, QT] = meshgrid(0:360, 0:180);
R = table(QT(:), QP(:), 'VariableNames', {'Theta', 'Phi'});
st = unique(theta); sp = unique(phi); regular = numel(st) * numel(sp) == numel(theta);
if regular
    [~, it] = ismember(theta, st); [~, ip] = ismember(phi, sp); li = sub2ind([numel(st), numel(sp)], it, ip);
    regular = numel(unique(li)) == numel(li);
end
for name = string(S.Properties.VariableNames(3:end))
    v = double(S.(char(name))); if gainMode, v = 10 .^ (v / 10); end
    if regular
        G = nan(numel(st), numel(sp)); G(li) = v;
        [PG, TG] = meshgrid([sp; sp(1) + 360], st); G = [G, G(:, 1)];                     % periodic phi closure
        q = interp2(PG, TG, G, QP, QT, 'linear');
        miss = ~isfinite(q); if any(miss, 'all'), nn = interp2(PG, TG, G, QP, QT, 'nearest'); q(miss) = nn(miss); end
    else
        F = scatteredInterpolant(phi, theta, v, 'linear', 'nearest'); q = F(QP, QT);
    end
    if gainMode, q = 10 * log10(max(q, realmin)); end
    R.(char(name)) = q(:);
end
R.Properties.UserData = ud;
end

function [P, info] = calcPattern(S, prm)
%calcPattern Canonical source -> processed pattern table (+ polarization info).
ud = S.Properties.UserData;
info = struct('label', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
if isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + prm.GainLoss_dB; end
    return
end
Eth = complex(S.Re_Eth, S.Im_Eth) * prm.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph) * prm.FieldScale;
Er = (Eth + 1i * Eph) / sqrt(2); El = (Eth - 1i * Eph) / sqrt(2);
mTh = abs(Eth); mPh = abs(Eph); mR = abs(Er); mL = abs(El);
total = 10 * log10(max(mTh.^2 + mPh.^2, eps));
% Dominant components decide the co/cross ordering, the displayed polarization and the Auto Rx sense.
pw = [mean(mTh.^2, 'omitnan'), mean(mPh.^2, 'omitnan'), mean(mR.^2, 'omitnan'), mean(mL.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.label = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif pw(1) >= pw(2),           info.label = 'Linear (Vertical)';
else,                            info.label = 'Linear (Horizontal)';
end
% Signed axial ratio (+RHCP / -LHCP); equal circular components are the linear limit (-100 dB floor).
d = mR - mL; sense = sign(d); sense(~isfinite(d)) = 0;
arLin = (mR + mL) ./ max(abs(d), eps);
ar = min(20 * log10(arLin), 250) .* sense;
ar(isfinite(d) & abs(d) <= eps * max(mR + mL, 1)) = -100;
% Polarization loss factor against the incident wave (Rw = wave axial ratio with its sense).
switch prm.RxMode
    case "RHCP", ws = 1;
    case "LHCP", ws = -1;
    otherwise,   ws = 2 * (info.pairs.Circular(1) == "E_RCP") - 1;
end
Ra = arLin .* sense; Ra(sense == 0) = 1e12; Rw = ws * 10 ^ (prm.RxAR_dB / 20);
plf = 0.5 + (4 * Ra * Rw - (Ra.^2 - 1) * (Rw^2 - 1)) ./ (2 * (Ra.^2 + 1) * (Rw^2 + 1));
plfDB = 10 * log10(min(max(plf, eps), 1));
eirp = prm.Pt_dBW + total; eirpW = 10 .^ (eirp / 10);
dB20 = @(m) 20 * log10(max(m, eps)); ph = @(E) rad2deg(angle(E));
P = table(S.Theta, S.Phi, total, ar, dB20(mR), dB20(mL), plfDB, total + plfDB, dB20(mTh), dB20(mPh), ph(Eth), ph(Eph), ph(Er), ph(El), ...
    eirp, eirpW / (4 * pi * prm.R_m^2), sqrt(30 * eirpW) / prm.R_m, 'VariableNames', ...
    {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', 'PLF_dB', 'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', ...
    'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
P.Properties.UserData = ud;
end

function pk = resolvePeak(v, pct, excess)
%resolvePeak Raw maximum, unless it exceeds the P<pct> level by more than <excess> dB (isolated spike);
% then the highest sample at or below that percentile becomes the effective peak.
v = double(v(:)); ok = isfinite(v);
pk = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(v)), 'wasAdjusted', false);
if ~any(ok), return; end
[pk.rawValue, pk.rawIndex] = max(v, [], 'omitnan'); pk.value = pk.rawValue; pk.index = pk.rawIndex;
p = percentile(v(ok), pct);
if pk.rawValue > p + excess
    out = ok & v > p; cand = v; cand(~ok | out) = -Inf;
    if any(isfinite(cand)), [pk.value, pk.index] = max(cand); pk.outlierMask = out; pk.wasAdjusted = true; end
end
end

function b = peakWindow(v, pct, excess)
%peakWindow 50 dB display / threshold window ending at the effective peak rounded up to 5 dB.
v = double(v(isfinite(v)));
if isempty(v), b = [-40 10]; return; end
top = ceil(resolvePeak(v, pct, excess).value / 5) * 5;
b = min(max([top - 50, top], -250), 100);
if diff(b) < 1, b(1) = max(-250, b(2) - 50); end
end

function w = solidWeights(theta, phi)
%solidWeights Exact solid angle of each uniform grid cell; the duplicated closing phi seam gets zero weight.
dt = gridStep(theta); if ~isfinite(dt), dt = 180; end
dp = gridStep(mod(phi, 360)); if ~isfinite(dp), dp = 360; end
w = (cosd(max(theta - dt / 2, 0)) - cosd(min(theta + dt / 2, 180))) * deg2rad(dp);
seam = 360; if any(phi < 0), seam = 180; end
w(abs(phi - seam) < 1e-9) = 0;
end

function [w, pk, k] = calcOrientation(T, gain, w, A, pct, excess)
%calcOrientation Principal axis (±X/±Y/±Z) whose 45° cone holds the most peak-normalized energy.
pt = physTheta(T);
if isempty(w) || numel(w) ~= height(T), w = solidWeights(pt, T.Phi); end
pk = resolvePeak(gain, pct, excess);
g = double(gain(:)); if pk.wasAdjusted, g(pk.outlierMask) = NaN; end
e = 10 .^ ((g - pk.value) / 10) .* w(:); e(~isfinite(e)) = 0;
av = [sind(A.theta(:)) .* cosd(A.phi(:)), sind(A.theta(:)) .* sind(A.phi(:)), cosd(A.theta(:))];
dirs = [sind(pt) .* cosd(T.Phi), sind(pt) .* sind(T.Phi), cosd(pt)];
[~, k] = max(e.' * double(dirs * av.' >= cosd(45)));
end

function M = calcMetrics(T, gain, pk, w, A, k, elev)
%calcMetrics Scalar antenna metrics from the reference gain column and its resolved peak.
g = double(gain(:)); if pk.wasAdjusted, g(pk.outlierMask) = NaN; end
integ = sum(10 .^ (g / 10) .* w(:), 'omitnan');
pt = physTheta(T); t0 = pt(pk.index); p0 = T.Phi(pk.index);
[~, back] = min(cosd(pt) * cosd(t0) + sind(pt) * sind(t0) .* cosd(T.Phi - p0));      % antipode of the peak
eff = 100 * integ / (4 * pi); if eff < 0 || eff > 100, eff = NaN; end
ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(pk.index); end
[eAng, eRows] = calcCutGeometry(T, "Theta", A.phi(k), pt);                              % E-plane through the axis
if A.theta(k) == 90, [hAng, hRows] = calcCutGeometry(T, "Phi", 90 * ~elev, pt);        % H-plane: orthogonal cut
else,                [hAng, hRows] = calcCutGeometry(T, "Theta", 90, pt); end
M = struct('PeakGain_dB', pk.value, 'PeakTheta_deg', t0, 'PeakPhi_deg', p0, ...
    'HPBW_EPlane_deg', calcHPBW(eAng, gain(eRows)), 'HPBW_HPlane_deg', calcHPBW(hAng, gain(hRows)), ...
    'FrontBack_dB', pk.value - gain(back), 'PeakDirectivity_dB', 10 * log10(max(4 * pi * 10 ^ (pk.value / 10) / max(integ, eps), eps)), ...
    'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', ar);
end

function [ang, rows, fixed, sym, snapped] = calcCutGeometry(T, type, req, pt)
%calcCutGeometry Snap a requested cut to the grid and return its full-circle rows in plotting order.
if type == "Phi"                                   % fixed theta, phi sweeps 0..360
    tv = unique(T.Theta); [dist, i] = min(abs(tv - req)); fixed = tv(i);
    rows = find(abs(T.Theta - fixed) < 1e-9); [ang, o] = sort(T.Phi(rows)); rows = rows(o); sym = 'θ';
else                                               % fixed phi: theta 0..180, then the opposite half-plane as 180..360
    req = mod(req, 360); wp = mod(T.Phi, 360); pv = unique(wp);
    [dist, i] = min(abs(mod(pv - req + 180, 360) - 180)); fixed = pv(i);
    [~, j] = min(abs(mod(pv - fixed, 360) - 180));
    a = find(abs(wp - fixed) < 1e-9); b = find(abs(wp - pv(j)) < 1e-9 & abs(pt - 180) > 1e-9);
    [~, oa] = sort(pt(a)); [~, ob] = sort(pt(b), 'descend'); a = a(oa); b = b(ob);
    rows = [a; b]; ang = [pt(a); 360 - pt(b)]; sym = 'φ';
end
snapped = dist > 1e-9;
end

function [bw, lo, hi] = calcHPBW(ang, g, pk, pa)
%calcHPBW Half-power beamwidth of a circular cut with linear interpolation of the -3 dB crossings.
[bw, lo, hi] = deal(NaN);
ok = isfinite(ang) & isfinite(g); ang = ang(ok); g = g(ok);
if numel(g) < 3, return; end
if nargin < 3 || isempty(pk) || isempty(pa), [pk, i] = max(g); pa = ang(i); end
half = pk - 3;
[ra, o] = sort(mod(ang - pa + 180, 360) - 180); rg = g(o);                % angles relative to the peak
L = find(ra < 0 & rg <= half, 1, 'last'); Rr = find(ra > 0 & rg <= half, 1, 'first');
if isempty(L) || isempty(Rr) || L + 1 > numel(rg) || Rr < 2, return; end
li = [L, L + 1]; ri = [Rr, Rr - 1];
if diff(rg(li)) == 0 || diff(rg(ri)) == 0, return; end
lc = ra(li(1)) + diff(ra(li)) * (half - rg(li(1))) / diff(rg(li));
rc = ra(ri(1)) + diff(ra(ri)) * (half - rg(ri(1))) / diff(rg(ri));
lo = pa + lc; hi = pa + rc; bw = rc - lc;
end

function cov = coverageCCDF(gain, mask, thr, w)
%coverageCCDF Coverage(T) [%] = 100 * sum(Omega_i * I(G_i > T)) / sum(Omega_i) over the region.
ok = mask(:) & isfinite(gain(:)) & isfinite(w(:)) & w(:) >= 0;
g = gain(ok); ww = w(ok); cov = zeros(numel(thr), 1);
if isempty(g) || sum(ww) <= 0, return; end
cov = 100 * (ww.' * (g > thr(:).')).' / sum(ww);
end

%% ==========================================================================================
%  Source readers
%  ==========================================================================================
function T = fieldTable(theta, phi, Eth, Eph)
T = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), ...
    'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function E = magPhase(dB, deg), E = 10 .^ (dB / 20) .* exp(1i * deg2rad(deg)); end

function [Eth, Eph] = circToLin(Ercp, Elcp), Eth = (Ercp + Elcp) / sqrt(2); Eph = (Ercp - Elcp) / (1i * sqrt(2)); end

function out = readSource(fp, fmt, cached)
%readSource Parse any supported pattern / coverage file into {rawTbl, blocks, freqs, meta}.
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, 'meta', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false));
switch ext
    case {'XLSX', 'XLS'},        out = readExcelMatrix(fp, out);
    case {'CSV', 'TXT', 'DAT'},  out = readGenericText(fp, string(fmt), cached, out);
    case 'CUT',                  out = readGraspCut(fp, out);
    case 'FFD',                  out = readHfssFfd(fp, out);
    case {'FZ', 'UAN', 'OUT', 'FFS', 'FFE'}
        M = readNumericFile(fp);
        assert(size(M, 2) >= 6, 'readFile:columns', 'Expected six numeric columns in %s.', fp);
        M = M(:, 1:6); theta = M(:, 1); phi = M(:, 2);
        switch ext
            case {'FZ', 'UAN'}   % XGTD: Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
                names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}; src = ['XGTD ' ext];
                Eth = magPhase(M(:, 3), M(:, 5)); Eph = magPhase(M(:, 4), M(:, 6));
            case 'OUT'           % TICRA/GRASP: Theta Phi Re/Im(RHCP) Re/Im(LHCP)
                names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; src = 'TICRA/GRASP OUT';
                [Eth, Eph] = circToLin(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)));
            case 'FFS'           % CST: Phi Theta Re/Im(Eth) Re/Im(Eph)
                names = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; src = 'CST FFS';
                Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6)); theta = M(:, 2); phi = M(:, 1);
            otherwise            % FEKO FFE: Theta Phi Re/Im(Eth) Re/Im(Eph) [extra columns ignored]
                names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; src = 'FEKO FFE';
                Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
        end
        out.meta.source = src; out.rawTbl = array2table(M, 'VariableNames', names);
        out.blocks = {fieldTable(theta, phi, Eth, Eph)};
    otherwise
        error('readFile:unsupported', 'Unsupported format: %s', ext);
end
end

function M = readNumericFile(fp)
%readNumericFile Numeric body of a text file. The data section starts at the first line with >= 4
% numeric fields that is followed by another such line (skips header lines that merely contain numbers).
fid = fopen(fp, 'r'); assert(fid > 0, 'apat:io:OpenFailed', 'Cannot open file: %s', fp); c = onCleanup(@() fclose(fid)); %#ok<NASGU>
isData = @(s) ischar(s) && numel(sscanf(s, '%f')) >= 4;
nHdr = 0; prev = fgetl(fid);
while ischar(prev)
    next = fgetl(fid);
    if isData(prev) && (isData(next) || ~ischar(next)), break; end
    nHdr = nHdr + 1; prev = next;
end
M = readmatrix(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, ...
    'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = M(~all(isnan(M), 2), :);
end

function out = readGenericText(fp, fmt, cached, out)
%readGenericText CSV/TXT/DAT: coverage results, gain-only pattern, or a user-selected E-field layout.
if isempty(cached)
    opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
    cached = rmmissing(readtable(fp, opts));
end
T = cached; n = width(T);
assert(n >= 2 && ~isempty(T), 'readFile:InvalidFormat', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHeaders = ~all(startsWith(names, "Var"));
c1 = T{:, 1}; c2 = T{:, 2};
% Coverage results: strictly monotonic thresholds followed by 0..100 % columns.
covHeader = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
if (fmt == "gain" || n < 6 || covHeader) && all(isfinite(c2)) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:n - 1))]; end
    out.rawTbl = T; out.meta.isCoverage = true; return
end
if fmt == "gain"                                  % gain-only: the wider-spanning angle column is phi
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    T = movevars(T, 'Theta', 'Before', 1);
    if hasHeaders, out.rawTbl = cached; else, out.rawTbl = T; end
    out.blocks = {T}; out.meta.isGainOnly = true; out.meta.source = 'Generic text (gain)'; return
end
assert(n >= 6, 'readFile:TextEFieldColumns', 'The selected generic E-field format requires six numeric columns.');
V = T{:, 3:6}; magPh = endsWith(fmt, "magphase"); layout = "not applicable";
if magPh                                          % phase columns exceed 100 -> detect interleaved mag/phase pairs
    layout = "grouped"; big = max(abs(V), [], 1, 'omitnan') > 100;
    if big(2) && ~big(3), V = V(:, [1 3 2 4]); layout = "interleaved"; end
    A = magPhase(V(:, 1), V(:, 3)); B = magPhase(V(:, 2), V(:, 4));
else
    A = complex(V(:, 1), V(:, 2)); B = complex(V(:, 3), V(:, 4));
end
if startsWith(fmt, "linear"), Eth = A; Eph = B; pol = ["E_TH", "E_PH"]; gen = ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"];
else
    pol = ["POL1", "POL2"]; gen = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"];
    if startsWith(fmt, "rcp"), [Eth, Eph] = circToLin(A, B); else, [Eth, Eph] = circToLin(B, A); end
end
if magPh, gen = [pol + "_dB", pol + "_deg"]; if layout == "interleaved", gen = gen([1 3 2 4]); end, end
if ~hasHeaders, cached.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", gen]); end
out.meta.source = sprintf('Generic text (%s, %s)', fmt, layout);
out.rawTbl = cached; out.blocks = {fieldTable(c1, c2, Eth, Eph)};
end

function out = readGraspCut(fp, out)
%readGraspCut TICRA/GRASP *.cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks.
out.meta.source = 'TICRA/GRASP CUT';
L = readlines(fp); L(strlength(strtrim(L)) == 0) = [];
theta = []; phi = []; D = zeros(0, 4); i = 1; icomp = 1; icut = 1;
while i < numel(L)
    p = sscanf(char(L(i + 1)), '%f'); assert(numel(p) >= 7, 'readFile:cut', 'Could not parse a GRASP cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6);
    blk = reshape(sscanf(char(strjoin(L(i + 2:i + 1 + n), ' ')), '%f'), 2 * p(7), []).';
    theta = [theta; p(1) + (0:n - 1).' * p(2)]; phi = [phi; repmat(p(4), n, 1)]; D = [D; blk(:, 1:4)]; %#ok<AGROW>
    i = i + 2 + n;
end
if icut == 2, [theta, phi] = deal(phi, theta); end                     % ICUT=2: phi swept, theta constant
neg = theta < 0; phi(neg) = phi(neg) + 180; theta(neg) = -theta(neg);  % fold negative theta onto the opposite phi
if isscalar(unique(phi))                                               % a single cut -> body of revolution
    cuts = (0:10:350).'; m = numel(theta);
    theta = repmat(theta, numel(cuts), 1); phi = repelem(cuts, m); D = repmat(D, numel(cuts), 1);
end
A = complex(D(:, 1), D(:, 2)); B = complex(D(:, 3), D(:, 4));
if icomp == 2, names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; [Eth, Eph] = circToLin(A, B);
else,          names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'};     Eth = A; Eph = B; end
out.rawTbl = array2table([theta, phi, D], 'VariableNames', [{'Theta', 'Phi'}, names]);
out.blocks = {fieldTable(theta, phi, Eth, Eph)};
end

function out = readHfssFfd(fp, out)
%readHfssFfd HFSS *.ffd: two axis triples, optional "Frequencies ..." line, then 4-column blocks
% optionally separated by "Frequency <f>" rows (one block per frequency).
out.meta.source = 'HFSS FFD';
L = cellstr(strtrim(readlines(fp))); L(cellfun(@isempty, L)) = [];
isTxt = ~cellfun(@isempty, regexp(L, '^[A-Za-z]', 'once'));
v = sscanf(strjoin(L(~isTxt), ' '), '%f');
assert(numel(v) >= 6 && mod(numel(v) - 6, 4) == 0, 'readFile:ffd', 'FFD header (theta/phi ranges) or 4-column data not found.');
thetaAxis = linspace(v(1), v(2), round(v(3))).'; phiAxis = linspace(v(4), v(5), round(v(6))).';
theta = repelem(thetaAxis, numel(phiAxis)); phi = repmat(phiAxis, numel(thetaAxis), 1);
F = reshape(v(7:end), 4, []).'; n = numel(theta);
assert(mod(size(F, 1), n) == 0, 'readFile:ffd', 'FFD row count does not match the theta/phi grid.');
freqs = [];
for s = L(isTxt).'
    tok = regexpi(s{1}, '^frequenc(y|ies)\s+(.+)$', 'tokens', 'once');
    if isempty(tok), continue; end
    f = sscanf(tok{2}, '%f').';
    if numel(f) > 1 || strcmpi(tok{1}, 'y'), freqs = [freqs, f]; end %#ok<AGROW>   ("Frequencies N" is only a count)
end
nb = size(F, 1) / n; freqs(end + 1:nb) = NaN; freqs = freqs(1:nb);
out.meta.isDep = nb > 1 || any(isfinite(freqs));
out.blocks = arrayfun(@(b) fieldTable(theta, phi, complex(F((b - 1) * n + 1:b * n, 1), F((b - 1) * n + 1:b * n, 2)), ...
    complex(F((b - 1) * n + 1:b * n, 3), F((b - 1) * n + 1:b * n, 4))), 1:nb, 'UniformOutput', false);
out.freqs = freqs; out.rawTbl = out.blocks{1};
end

function out = readExcelMatrix(fp, out)
%readExcelMatrix Excel matrix templates: first sheet = summary, fixed component sheets with C3-origin matrices
% (row 2 = phi axis, column B = theta axis) in dBi magnitude / degrees phase.
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"];
lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'readFile:ExcelMatrixFormat', 'Unsupported Excel workbook: expected Etheta/Ephi and/or RHCP/LHCP component sheets.');
need = string.empty; if hasC, need = [need, circ]; end, if hasL, need = [need, lin]; end
S = struct(); theta = []; phi = [];
for k = 1:numel(need)
    [t, p, D] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, need(k)), 1)));
    if isempty(theta), theta = t; phi = p;
    else, assert(isequal(size(t), size(theta)) && isequal(size(p), size(phi)) && max(abs(t - theta)) < 1e-9 && max(abs(p - phi)) < 1e-9, ...
            'readFile:ExcelMatrixGrid', 'All component sheets must share one theta/phi grid.');
    end
    S.(char(need(k))) = D;
end
if hasL, Eth = magPhase(S.Etheta_Gain_dBi, S.Etheta_Phase_degrees); Eph = magPhase(S.Ephi_Gain_dBi, S.Ephi_Phase_degrees);
else, [Eth, Eph] = circToLin(magPhase(S.RHCP_Gain_dBi, S.RHCP_Phase_degrees), magPhase(S.LHCP_Gain_dBi, S.LHCP_Phase_degrees)); end
[P, T] = meshgrid(phi, theta);
out.blocks = {fieldTable(T(:), P(:), Eth(:), Eph(:))};
raw = out.blocks{1}; for k = 1:numel(need), raw.(char(need(k))) = S.(char(need(k)))(:); end
out.rawTbl = raw;
out.meta.source = sprintf('Excel Matrix Format %d', 1 + hasC * (1 + hasL));   % 1: Eth/Eph, 2: RHCP/LHCP, 3: both
out.meta.summary = readSummary(fp, sheets(1));
end

function [theta, phi, D] = readMatrixSheet(fp, sheet)
%readMatrixSheet One C3-origin matrix; contiguous, strictly increasing axes are required.
C = readcell(fp, 'Sheet', char(sheet));
assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'readFile:ExcelMatrixSheet', 'Sheet "%s" has no C3-origin matrix.', sheet);
isNum = @(x) isnumeric(x) && isscalar(x) && isfinite(x);
pm = cellfun(isNum, C(2, 3:end)); tm = cellfun(isNum, C(3:end, 2));
np = find(~pm, 1) - 1; if isempty(np), np = numel(pm); end
nt = find(~tm, 1) - 1; if isempty(nt), nt = numel(tm); end
assert(nt > 0 && np > 0 && ~any(pm(np + 1:end)) && ~any(tm(nt + 1:end)), 'readFile:ExcelMatrixAxis', 'Sheet "%s" has a gap or no numeric theta/phi axis.', sheet);
phi = cell2mat(C(2, 3:2 + np)); theta = cell2mat(C(3:2 + nt, 2)); cells = C(3:2 + nt, 3:2 + np);
assert(all(cellfun(isNum, cells), 'all'), 'readFile:ExcelMatrixSheet', 'Sheet "%s" contains non-numeric matrix samples.', sheet);
D = cell2mat(cells);
assert(all(diff(theta) > 0) && all(diff(phi) > 0) && theta(1) >= -1e-9 && theta(end) <= 180 + 1e-9 && phi(1) >= -1e-9 && phi(end) < 360 + 1e-9, ...
    'readFile:ExcelMatrixAxis', 'Sheet "%s" needs strictly increasing axes within theta 0..180 and phi 0..360.', sheet);
end

function s = readSummary(fp, sheet)
%readSummary Label/value pairs of the template summary sheet (column B labels, first non-empty of C..E).
s = struct();
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
for r = 1:size(C, 1)
    lab = C{r, 2};
    if ~(ischar(lab) || isstring(lab)) || strlength(strtrim(string(lab))) == 0, continue; end
    for c = 3:min(size(C, 2), 5)
        v = C{r, c};
        if ~isempty(v) && ~isa(v, 'missing')
            s.(matlab.lang.makeValidName(lower(regexprep(char(lab), '[^a-zA-Z0-9]+', '_')))) = v; break
        end
    end
end
end