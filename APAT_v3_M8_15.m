classdef APAT_v3_M8_15 < matlab.apps.AppBase %1752-lines %1709-lines %ISSUES: %1. Loaded file check not working (if a pattern is loaded,when pressing Load again it goes ahead and load the same file again instead of throwing a message!) %2. Edge POB DataTip positioning NOT-OK %3. Customized Interactive DataTip NOT-OK ON Contour Plot & Fisheye Plot (shows default X_Y_Z/Theta_R_Z) %3. When loading new pattern while POB is active/enabled, it shows new POB but doesn't delete old POB %4. POB DataTip issue (if POB DataTip enabled, then user right CLick and Delete Tips using custom context menu, it delete all DatTips as expected, but if user disable then re-enable the POB DatTip, the POB DatTip doesn't show anymore!)  %5.Context menu shows error: "Warning: You cannot set 'ContextMenu' property of DataTip."
% APAT v3 M8 — Antenna Pattern Analyzer Tool.
%
% Milestone 8 is a ground-up consolidation of M7.110_5:
%   * one linear data pipeline   : file -> canonical -> processed -> view -> plots
%   * one declarative UI builder : handles live in app.ui, wired with guarded callbacks
%   * pure numerical services    : every local function below the class is UI-free
%   * annotations are plain tagged graphics; no bookkeeping records
%
% Usage:  app = APAT_v3_M8;          % interactive
%         report = app.selfTest();   % deterministic numerical checks
%
% Data model (all tables share Theta/Phi in degrees):
%   src.rawTbl  file columns as read            src.blocks{k}  canonical E-field/gain blocks
%   stdTbl      normalized canonical block      patTbl         processed at native step
%   baseTbl     processed at selected step      viewTbl        display convention applied

    properties (Access = public)
        fig matlab.ui.Figure
        ui  struct = struct()       % every UI handle, by short name (see createUI)
    end

    properties (Access = private)
        src      struct = struct('path','','name','','base','','folder','','rawTbl',table(),'textTbl',table(),'blocks',{{}},'freqs',NaN,'meta',struct())
        stdTbl   table
        patTbl   table
        baseTbl  table
        viewTbl  table
        viewRev  double = 0         % increments whenever viewTbl is rebuilt
        info     struct = struct('POB',NaN,'POBth',NaN,'POBph',NaN,'pol','n/a','pairs',struct('Linear',["E_TH","E_PH"],'Circular',["E_RCP","E_LCP"]),'peak',struct())
        metrics  struct = struct()
        boresight double = 1        % index into Axes6
        gainLim  double = [-40 10]  % authoritative gain colour window (non-AR)
        fullLim  double = [-40 10]  % range currently applied to the full-pattern plots
        cutLim   double = [-40 10]  % range applied to the cut plots
        cache    struct = struct()  % lazily built grid of the current view
        cov      struct = struct('runID',0,'jobs',{{}},'presetKey',"",'plotInit',false,'syncing',false)
        defaults struct = struct()
        styles   cell = {}
        statusTimer = []
        dlg = []
        closing logical = false
    end

    properties (Constant, Access = private)
        Axes6 = struct('labels',{{'+Z','-Z','+X','-X','+Y','-Y'}},'theta',[0 180 90 90 90 90],'phi',[0 0 0 180 90 270])
        Components = ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","AR_dB","Gain_PolCorrected_dB"; ...
                      "Total Gain","Etheta Gain","Ephi Gain","RHCP Gain","LHCP Gain","Axial Ratio","Polarized Gain"]
        HiddenColumns = {'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'}
        TextFormats = {{'1: Gain Pattern','2: Etheta/Ephi — dB magnitude, phase','3: Etheta/Ephi — real, imaginary', ...
                        '4: POL1=RCP, POL2=LCP — dB magnitude, phase','5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
                        '6: POL1=RCP, POL2=LCP — real, imaginary','7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                       {'gain','linear_magphase','linear_reim','rcp_lcp_magphase','lcp_rcp_magphase','rcp_lcp_reim','lcp_rcp_reim'}}
        FileFilter = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt','Pattern / coverage files';'*.*','All files'}
        PeakPct = 99.99             % peak policy: percentile ...
        PeakExcess = 6              % ... and maximum excess (dB) above it
        DistFloor = 1e-12
        Release = 'APAT v3 M8'
    end

    %% ------------------------------------------------------------------ construction / lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_15
            app.createUI();
            registerApp(app, app.fig);
            app.fig.Visible = 'on';
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.closing, return; end
            app.closing = true;
            app.stopTimer();
            if ~isempty(app.dlg) && isvalid(app.dlg), delete(app.dlg); end
            if isgraphics(app.fig), delete(app.fig); end
        end
    end

    %% ------------------------------------------------------------------ UI construction
    methods (Access = private)
        function f = cb(app, fn)
            % Wrap a callback so any error surfaces as a dialog instead of a console dump.
            f = @(src, evt) app.guarded(fn, src, evt);
        end

        function guarded(app, fn, src, evt)
            try
                fn(src, evt);
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.status(1, 'Operation cancelled by user.', true);
                else, app.showError(ME); end
            end
        end

        function createUI(app)
            G  = @(p, cols, rows) uigridlayout(p, 'ColumnWidth', cols, 'RowHeight', rows);
            L  = @(p, txt, r, c, varargin) place(uilabel(p, 'Text', txt, 'HorizontalAlignment', 'right', varargin{:}), r, c);
            B  = @(p, txt, fn, r, c, varargin) place(uibutton(p, 'push', 'Text', txt, 'FontWeight', 'bold', 'ButtonPushedFcn', app.cb(fn), varargin{:}), r, c);
            SP = @(p, val, r, c, varargin) place(uispinner(p, 'Value', val, varargin{:}), r, c);
            DD = @(p, items, data, val, fn, r, c, varargin) place(uidropdown(p, 'Items', items, 'ItemsData', data, 'Value', val, 'ValueChangedFcn', app.cb(fn), varargin{:}), r, c);
            CK = @(p, txt, fn, r, c, varargin) place(uicheckbox(p, 'Text', txt, 'ValueChangedFcn', app.cb(fn), varargin{:}), r, c);
            SW = @(p, items, data, fn, r, c) place(uiswitch(p, 'slider', 'Items', items, 'ItemsData', data, 'Value', data{1}, 'ValueChangedFcn', app.cb(fn)), r, c);
            rangeTriplet = @(g) struct( ...
                'max',    place(uispinner(g, 'Limits', [-250 100], 'Value', 100, 'Step', 5), 1, 1), ...
                'slider', place(uislider(g, 'range', 'Limits', [-250 100], 'Value', [-250 100], 'Orientation', 'vertical'), 2, 1), ...
                'min',    place(uispinner(g, 'Limits', [-250 100], 'Value', -250, 'Step', 5), 3, 1));

            app.fig = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.Release], 'Visible', 'off', ...
                'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) delete(app));
            root = G(app.fig, {'1x'}, {'1x'});
            u.Tabs = uitabgroup(root);
            u.TabMain = uitab(u.Tabs, 'Title', 'Process Pattern 📡');
            u.TabCov  = uitab(u.Tabs, 'Title', 'Compute Coverage 📈');

            % ---------------------------------------------------------- Main tab: parameters
            main = G(u.TabMain, repmat({'1x'}, 1, 14), {'fit', '2x', 'fit', '1x', 'fit'});
            pnl = place(uipanel(main, 'Title', 'Inputs & Parameters 🎛️', 'FontWeight', 'bold'), 1, [1 14]);
            g = G(pnl, repmat({'1x'}, 1, 14), {'1x', '1x', '1x'});
            L(g, 'Input Pattern:', 1, 1);
            u.Path = place(uieditfield(g, 'text'), 1, [2 8]);
            u.FFDLabel = L(g, 'FFD Freq:', 1, 9, 'Visible', 'off');
            u.FFD = DD(g, {'Frequencies'}, {}, 'Frequencies', @(~, ~) app.onFFD(), 1, 10, 'Visible', 'off');
            B(g, '📂 Load File', @(~, ~) app.onLoad(), 1, [11 12]);
            B(g, '⚙️ Process', @(~, ~) app.onProcess(), 1, [13 14]);
            B(g, 'Reset Params', @(~, ~) app.resetParams(), 2, [1 3], 'Tooltip', 'Restore the start-up parameter values and reprocess.');
            u.TextFormatLabel = L(g, 'Format:', 2, [4 5], 'Visible', 'off');
            u.TextFormat = DD(g, app.TextFormats{1}, app.TextFormats{2}, 'gain', @(~, ~) app.onTextFormat(), 2, [6 8], 'Visible', 'off', 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.');
            u.Step = DD(g, {'STEP'}, {}, 'STEP', @(~, ~) app.onStep(), 2, [9 10], 'Visible', 'off', 'Tooltip', 'Native angular step or a 1° resampled canonical grid.');
            u.ExportOut = B(g, '💾 Export Results', @(~, ~) app.exportResults(), 2, [11 12], 'Visible', 'off');
            u.ExportUAN = B(g, '💾 Export UAN', @(~, ~) app.exportUAN(), 2, [13 14], 'Visible', 'off');
            u.RxPolLabel = L(g, 'Rw Sense', 3, 1, 'Visible', 'off');
            u.RxPol = DD(g, {'Auto', 'RHCP', 'LHCP'}, {}, 'Auto', @(~, ~) [], 3, 2, 'Visible', 'off');
            u.RwLabel = L(g, 'Rw (dB)', 3, 3, 'Visible', 'off');
            u.Rw = SP(g, 6, 3, 4, 'Visible', 'off', 'Limits', [0 100]);
            u.LossLabel = L(g, 'Loss (−) / Gain (+) dB', 3, 5, 'Visible', 'off');
            u.Loss = SP(g, 0, 3, 6, 'Visible', 'off', 'Step', 0.1);
            u.PtLabel = L(g, 'Tx Pwr (Pt)', 3, 7, 'Visible', 'off');
            u.Pt = SP(g, 0, 3, 8, 'Visible', 'off');
            u.PtUnit = DD(g, {'dBW', 'dBm', 'Watts'}, {}, 'dBW', @(~, ~) [], 3, 9, 'Visible', 'off');
            u.RLabel = L(g, 'Distance', 3, 10, 'Visible', 'off');
            u.R = SP(g, 1, 3, 11, 'Visible', 'off', 'Limits', [0 Inf]);
            u.RUnit = DD(g, {'m', 'km'}, {}, 'm', @(~, ~) [], 3, 12, 'Visible', 'off');
            u.Coverage = B(g, '📉 Coverage ▶', @(~, ~) app.covFromMain(), 3, [13 14], 'Visible', 'off');

            % ---------------------------------------------------------- Main tab: full-pattern plots
            u.PanelFull = place(uipanel(main, 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [1 6]);
            tg = uitabgroup(G(u.PanelFull, {'1x'}, {'1x'}));
            titles = {'Contour Plot', 'Circular Contour Plot', '3D Spherical Plot', '3D Polar Plot', '3D Surface Plot'};
            for k = 1:5
                g = G(uitab(tg, 'Title', titles{k}), {'fit', '1x'}, {'fit', '1x', 'fit'});
                F = rangeTriplet(g);
                if k == 2, F.axes = place(polaraxes(g), [1 3], 2); else, F.axes = place(uiaxes(g), [1 3], 2); end
                F.is3D = k >= 3;
                u.Full(k) = F;
            end

            % ---------------------------------------------------------- Main tab: cut plots
            u.PanelCut = place(uipanel(main, 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [7 12]);
            tgc = uitabgroup(G(u.PanelCut, {'1x'}, {'1x'}));
            g = G(uitab(tgc, 'Title', 'Polar Cut Plot'), {'fit', '0.26x', '1x', '0.23x'}, {'fit', '0.25x', '1x', 'fit'});
            u.CutMax = place(uispinner(g, 'Limits', [-250 100], 'Value', 100, 'Step', 5), 1, 1);
            u.CutRange = place(uislider(g, 'range', 'Limits', [-250 100], 'Value', [-250 100], 'Orientation', 'vertical'), [2 3], 1);
            u.CutMin = place(uispinner(g, 'Limits', [-250 100], 'Value', -250, 'Step', 5), 4, 1);
            u.PaxCut = place(polaraxes(g), [1 4], 3);
            u.HPBW = place(uibutton(g, 'state', 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', app.cb(@(~, ~) app.onCut())), 1, 4);
            u.HPBWLabel = place(uilabel(g, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold'), 2, 4);
            ge = place(G(g, {'1x'}, {'1x', '1x', '1x'}), 3, 4);
            u.Et = CK(ge, 'E_Total', @(~, ~) app.onCut(), 1, 1, 'Value', true);
            u.Er = CK(ge, 'E_RCP', @(~, ~) app.onCut(), 2, 1, 'Value', true);
            u.El = CK(ge, 'E_LCP', @(~, ~) app.onCut(), 3, 1, 'Value', true);
            B(g, 'Export Cut', @(~, ~) app.exportCut(), 4, 4);
            u.AxRect = uiaxes(G(uitab(tgc, 'Title', 'Rectangular Cut Plot'), {'1x'}, {'1x'}));
            ylabel(u.AxRect, 'Magnitude (dB)'); u.AxRect.Box = 'on';

            % ---------------------------------------------------------- Main tab: plot control
            u.PanelCtrl = place(uipanel(main, 'Title', 'Plot Control 🎨', 'FontWeight', 'bold', 'Visible', 'off'), 2, [13 14]);
            g = G(u.PanelCtrl, {'fit', '1x'}, repmat({'fit'}, 1, 15));
            L(g, 'Component', 1, 1);     u.Component = DD(g, cellstr(app.Components(2, :)), cellstr(app.Components(1, :)), 'E_Total_dB', @(~, ~) app.onComponent(), 1, 2);
            L(g, 'Cut type', 2, 1);      u.CutType = DD(g, {'Phi', 'Theta'}, {}, 'Phi', @(~, ~) app.onCut(), 2, 2, 'Tooltip', 'Phi cut: fixed theta, sweep phi.  Theta cut: fixed phi, full great circle.');
            L(g, 'Cut value', 3, 1);     u.CutValue = SP(g, 0, 3, 2, 'Limits', [-Inf Inf], 'ValueChangedFcn', app.cb(@(~, ~) app.onCut()));
            L(g, 'Cut fields', 4, 1);    u.Basis = DD(g, {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, {'Circular', 'Linear'}, 'Circular', @(~, ~) app.onBasis(), 4, 2);
            L(g, 'Colorbar max', 5, 1);  u.Cmax = SP(g, 10, 5, 2, 'Limits', [-250 100], 'Step', 5, 'ValueChangedFcn', app.cb(@(~, ~) app.applyColorbar()));
            L(g, 'Colorbar min', 6, 1);  u.Cmin = SP(g, -40, 6, 2, 'Limits', [-250 100], 'Step', 5, 'ValueChangedFcn', app.cb(@(~, ~) app.applyColorbar()));
            L(g, 'Colorbar step', 7, 1); u.Cstep = SP(g, 5, 7, 2, 'Limits', [0.1 100], 'ValueChangedFcn', app.cb(@(~, ~) app.setRange("full", app.fullLim, false)));
            L(g, 'Adjust Colorbar', 8, 1); B(g, 'Apply', @(~, ~) app.applyColorbar(), 8, 2, 'Tooltip', 'Apply min/max to the full-pattern and cut plots.');
            L(g, '3D view', 9, 1);       u.View3D = DD(g, {'Isometric', 'Top (+Z)', 'Bottom (−Z)', 'Right (+X)', 'Left (−X)', 'Front (−Y)', 'Back (+Y)'}, ...
                {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'iso', @(~, ~) app.applyViews(), 9, 2);
            u.PhiSpan   = SW(g, {'φ span: 0° to 360°', '−180° to 180°'}, {'0° to 360°', '-180° to 180°'}, @(~, ~) app.applySpan(false, false), 10, [1 2]);
            u.ThetaSpan = SW(g, {'θ span: 0° to 180°', '−90° to 90°'}, {'0° to 180°', '-90° to 90°'}, @(~, ~) app.onThetaSpan(), 11, [1 2]);
            u.Plane     = SW(g, {'E-Plane cut', 'H-Plane cut'}, {'E', 'H'}, @(~, ~) app.applyPlane(), 12, [1 2]);
            u.Overlay = CK(g, 'Overlay Cut on 3D Plot', @(~, ~) app.drawOverlays(), 13, [1 2]);
            u.POB = CK(g, 'Annotate POB', @(~, ~) set(findall(app.fig, 'Tag', 'APAT_POB'), 'Visible', app.ui.POB.Value), 14, [1 2]);
            u.HPBWBounds = CK(g, 'Annotate HPBW Bounds', @(~, ~) set(findall(app.fig, 'Tag', 'APAT_HPBW'), 'Visible', app.ui.HPBWBounds.Value), 15, [1 2], 'Visible', 'off');

            % ---------------------------------------------------------- Main tab: data tables & status
            u.Filter = DD(main, {'--- column filter ---'}, {0}, 0, @(~, ~) app.filterOutput(false), 3, [13 14], 'Visible', 'off', 'Tooltip', 'Toggle result columns (✓ = shown).');
            u.DataTabs = place(uitabgroup(main, 'Visible', 'off'), 4, [1 14]);
            u.TableOut  = uitable(G(uitab(u.DataTabs, 'Title', 'Results 📤'), {'1x'}, {'1x'}), 'ColumnWidth', '1x');
            u.TableIn   = uitable(G(uitab(u.DataTabs, 'Title', 'Input 📥'), {'1x'}, {'1x'}));
            u.TableMeta = uitable(G(uitab(u.DataTabs, 'Title', 'Metadata 📋'), {'1x'}, {'1x'}), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'});
            u.Status = place(uilabel(main, 'Text', 'Ready -- load an antenna pattern file to begin 🚀', 'Interpreter', 'html'), 5, [1 14]);

            % ---------------------------------------------------------- Coverage tab
            cg = G(u.TabCov, {'0.75x', 'fit', '1x', 'fit', '1x'}, {'0.25x', '1x', 'fit'});
            pnl = place(uipanel(cg, 'Title', 'Inputs & Parameters 🎛️', 'FontWeight', 'bold'), 1, [1 5]);
            g = G(pnl, [{'fit'}, repmat({'1x'}, 1, 9)], {'1x', 'fit', 'fit', 'fit'});
            u.CovType = place(uibuttongroup(g, 'Title', 'Coverage Type', 'SelectionChangedFcn', app.cb(@(~, ~) app.onCovType(true))), [1 2], [1 2]);
            uiradiobutton(u.CovType, 'Text', 'Spherical 🌐', 'Position', [10 30 120 22], 'Value', true);
            u.CovConical = uiradiobutton(u.CovType, 'Text', 'Conical 🔻', 'Position', [10 6 120 22]);
            L(g, 'Antenna Pattern:', 1, 3);
            u.CovPath = place(uieditfield(g, 'text'), 1, [4 8]);
            B(g, '📂 Load File', @(~, ~) app.onCovLoad(), 1, 9);
            u.CovCompute = B(g, '⚙️ Compute Coverage', @(~, ~) app.covCompute(), 1, 10);
            lb(1) = L(g, 'Threshold  Min (dB):', 2, 3); u.ThrMin = SP(g, -40, 2, 4, 'Limits', [-250 100]);
            lb(2) = L(g, 'Threshold  Max (dB):', 2, 5); u.ThrMax = SP(g, 10, 2, 6, 'Limits', [-250 100]);
            lb(3) = L(g, 'Step (dB):', 2, 7);           u.ThrStep = SP(g, 1, 2, 8, 'Limits', [0.1 50], 'Step', 0.5);
            u.CovReset  = B(g, '🔄 Reset', @(~, ~) app.covReset(), 2, 9);
            u.CovExport = B(g, '💾 Export Results', @(~, ~) app.covExport(), 2, 10);
            lb(4) = L(g, 'Orientation 🧭:', 3, 1);
            u.CovOrient = DD(g, [{'Auto'}, app.Axes6.labels], num2cell(0:6), 0, @(~, ~) app.onCovOrientation(), 3, 2);
            lb(5) = L(g, 'Cone θ₀ (°):', 3, 3);       u.ConeTh = SP(g, 0, 3, 4, 'Limits', [0 180]);
            lb(6) = L(g, 'Cone φ₀ (°):', 3, 5);       u.ConePh = SP(g, 0, 3, 6, 'Limits', [0 360]);
            lb(7) = L(g, 'Cone Angle α (°):', 3, 7);  u.ConeAng = SP(g, 45, 3, 8, 'Limits', [0 180]);
            u.CovClear = B(g, '🧹 Clear DataTips', @(~, ~) app.covClear(), 3, 9);
            B(g, '📊 To Main ◀', @(~, ~) set(u.Tabs, 'SelectedTab', u.TabMain), 3, 10);
            lb(8) = L(g, 'Component:', 4, 1);
            u.CovComponent = DD(g, {'Total Gain'}, {'E_Total_dB'}, 'E_Total_dB', @(~, ~) app.onCovComponent(), 4, 2);
            lb(9) = L(g, 'Coverage @ dB:', 4, 3);  u.QueryCov = SP(g, 0, 4, 4);  u.QueryCovBtn = B(g, '⯐ Query Coverage', @(~, ~) app.covQuery("cov"), 4, 5);
            lb(10) = L(g, 'Threshold @ %:', 4, 6); u.QueryThr = SP(g, 50, 4, 7, 'Limits', [0 100]); u.QueryThrBtn = B(g, '🔍 Query Threshold', @(~, ~) app.covQuery("thr"), 4, 8);
            u.CovTextFormatLabel = L(g, 'Format:', 4, 9, 'Visible', 'off');
            u.CovTextFormat = DD(g, app.TextFormats{1}, app.TextFormats{2}, 'gain', @(~, ~) app.onCovTextFormat(), 4, 10, 'Visible', 'off');
            u.CovPatternCtrls = [lb(1:8), u.ThrMin, u.ThrMax, u.ThrStep, u.CovOrient, u.CovComponent, u.CovCompute];
            u.ConeCtrls  = [lb(4:7), u.CovOrient, u.ConeTh, u.ConePh, u.ConeAng];
            u.QueryCtrls = [lb(9:10), u.QueryCov, u.QueryCovBtn, u.QueryThr, u.QueryThrBtn];

            u.CovResults = place(uipanel(cg, 'Title', 'Results', 'FontWeight', 'bold', 'Visible', 'off'), 2, [1 5]);
            g = G(u.CovResults, {'1x', 'fit', '1x', 'fit', '1x'}, {'1x', 'fit'});
            u.CovTree = place(uitree(g, 'checkbox', 'SelectionChangedFcn', app.cb(@(~, ~) app.onCovSelect()), 'CheckedNodesChangedFcn', app.cb(@(~, ~) app.covRefresh())), [1 2], 1);
            u.CovRoot = uitreenode(u.CovTree, 'Text', 'Coverage Results');
            u.CovAxes = place(uiaxes(g), 1, [2 4]);
            u.CovTable = place(uitable(g, 'ColumnWidth', '1x'), [1 2], 5);
            u.CovXMin = SP(g, -40, 2, 2, 'Limits', [-250 100], 'ValueChangedFcn', app.cb(@(s, ~) app.covXRange(s)));
            u.CovXRange = place(uislider(g, 'range', 'Limits', [-250 100], 'Value', [-40 10], 'ValueChangedFcn', app.cb(@(s, ~) app.covXRange(s))), 2, 3);
            u.CovXMax = SP(g, 10, 2, 4, 'Limits', [-250 100], 'ValueChangedFcn', app.cb(@(s, ~) app.covXRange(s)));
            u.Status(2) = place(uilabel(cg, 'Text', 'Ready -- load an antenna pattern file to begin 🚀', 'Interpreter', 'html'), 3, [1 5]);
            app.ui = u;

            % ---------------------------------------------------------- one-time wiring
            for k = 1:5
                F = u.Full(k);
                F.slider.ValueChangedFcn = app.cb(@(s, ~) app.setRange("full", s.Value, false));
                F.min.ValueChangedFcn = app.cb(@(s, ~) app.setRange("full", [s.Value, app.fullLim(2)], false));
                F.max.ValueChangedFcn = app.cb(@(s, ~) app.setRange("full", [app.fullLim(1), s.Value], false));
                app.setInteraction(F.axes, F.is3D);
            end
            u.CutRange.ValueChangedFcn = app.cb(@(s, ~) app.setRange("cut", s.Value, false));
            u.CutMin.ValueChangedFcn = app.cb(@(s, ~) app.setRange("cut", [s.Value, app.cutLim(2)], false));
            u.CutMax.ValueChangedFcn = app.cb(@(s, ~) app.setRange("cut", [app.cutLim(1), s.Value], false));
            app.setInteraction(u.PaxCut, false); app.setInteraction(u.AxRect, false);
            set([u.PaxCut, u.Full(2).axes], 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            app.initCovAxes();
            app.styles = {uistyle('FontWeight', 'bold', 'FontColor', 'black', 'BackgroundColor', [0.8 1 0.8]), ...
                          uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9])};
            app.defaults = struct('Loss', u.Loss.Value, 'RxPol', u.RxPol.Value, 'Rw', u.Rw.Value, 'Pt', u.Pt.Value, ...
                'PtUnit', u.PtUnit.Value, 'R', u.R.Value, 'RUnit', u.RUnit.Value);
            app.covUI();
        end

        function setInteraction(app, ax, is3D)
            % Fixed per-axes gestures plus a "Delete DataTips" context menu.
            menu = uicontextmenu(app.fig);
            uimenu(menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ~) delete(findall(ax, 'Type', 'datatip')));
            ax.ContextMenu = menu;
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), return; end
            enableDefaultInteractivity(ax);
            if is3D, ax.Interactions = [rotateInteraction, dataTipInteraction];
            else,    ax.Interactions = [zoomInteraction, dataTipInteraction]; end
        end

        function initCovAxes(app)
            ax = app.ui.CovAxes; cla(ax); legend(ax, 'off');
            hold(ax, 'on'); grid(ax, 'on'); ylim(ax, [0 100]); set(ax, 'Box', 'on', 'Layer', 'top', 'XLimMode', 'auto');
            xlabel(ax, 'Threshold (dB)'); ylabel(ax, 'Coverage (%)');
        end
    end

    %% ------------------------------------------------------------------ pipeline: file -> canonical -> processed
    methods (Access = private)
        function onLoad(app)
            u = app.ui; fp = strtrim(u.Path.Value);
            if isempty(fp) || ~isfile(fp)
                [f, p] = uigetfile(app.FileFilter, 'Select an antenna pattern file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            app.dlg = uiprogressdlg(app.fig, 'Title', 'Loading', 'Message', 'Reading file...', 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            cleaner = onCleanup(@() delete(app.dlg)); t0 = tic;
            out = app.readAny(fp, 1);
            if out.meta.isCoverage                          % coverage-results files route to the Coverage tab
                u.Tabs.SelectedTab = u.TabCov; u.CovPath.Value = fp;
                app.covLoadResults(fp, out.rawTbl); return
            end
            [out.folder, out.base, ext] = fileparts(fp); out.path = fp; out.name = [out.base ext];
            app.src = out; u.Path.Value = fp;
            if out.meta.isDep
                items = compose('Pattern %d: %.4g GHz', (1:numel(out.blocks))', out.freqs(:) / 1e9);
                items(isnan(out.freqs)) = compose('Pattern %d', find(isnan(out.freqs(:))));
                u.FFD.Items = items; u.FFD.Value = items{1};
            end
            set([u.FFDLabel, u.FFD], 'Visible', out.meta.isDep);
            u.Basis.UserData = true;                        % let the detected polarization pick the cut basis
            app.selectBlock(1);
            app.process(false, t0);
        end

        function out = readAny(app, fp, tab)
            % I/O boundary. Generic text files expose the format selector of the calling tab.
            u = app.ui;
            if tab == 1, dd = u.TextFormat; lbl = u.TextFormatLabel; else, dd = u.CovTextFormat; lbl = u.CovTextFormatLabel; end
            generic = isGenericText(fp);
            if generic, dd.Value = 'gain'; end
            out = readSource(fp, dd.Value);
            set([lbl, dd], 'Visible', generic && ~out.meta.isCoverage);
        end

        function selectBlock(app, k)
            T = normalizePattern(app.src.blocks{k});
            T.Properties.UserData = app.src.meta;
            app.stdTbl = T;
            if app.src.meta.isDep, app.src.rawTbl = app.src.blocks{k}; end
            app.ui.TableIn.Data = app.src.rawTbl; app.ui.TableIn.ColumnName = app.src.rawTbl.Properties.VariableNames;
        end

        function process(app, keepStep, t0)
            % Recompute everything derived from the canonical block with the current parameters.
            if nargin < 3, t0 = tic; end
            u = app.ui; T = app.stdTbl; gainOnly = app.src.meta.isGainOnly;
            [app.patTbl, app.info] = calcPattern(T, app.params(), app.PeakPct, app.PeakExcess);
            app.checkCancel();
            if isequal(u.Basis.UserData, true) && ~gainOnly
                if startsWith(app.info.pol, 'Linear'), u.Basis.Value = 'Linear'; else, u.Basis.Value = 'Circular'; end
            end
            ts = gridStep(T.Theta); ps = gridStep(mod(T.Phi, 360));
            if ~isfinite(ts), ts = 1; end, if ~isfinite(ps), ps = ts; end
            native = sprintf('STEP: %g°', max(ts, ps)); one = 'STEP: 1°';
            nonCanonical = abs(ts - 1) > 1e-9 || abs(ps - 1) > 1e-9;
            wasOne = keepStep && strcmp(u.Step.Value, one);
            u.Step.Items = {native, one}; u.Step.Value = native;
            if wasOne && nonCanonical, u.Step.Value = one; end
            set(u.Step, 'Visible', nonCanonical, 'Enable', nonCanonical);
            u.CutValue.Step = max(ts, 1);
            app.applyStep(~keepStep);

            set([u.PanelFull, u.PanelCut, u.PanelCtrl, u.ExportOut, u.Coverage, u.DataTabs, u.Filter], 'Visible', 'on');
            set([u.ExportUAN, u.Et, u.Er, u.El], 'Visible', ~gainOnly); set([u.Er, u.El, u.Basis], 'Enable', ~gainOnly);
            app.updateInputVisibility();
            pol = ''; if ~gainOnly, pol = sprintf(' | Polarization <b>%s</b>', app.info.pol); end
            app.status(1, sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)%s | %.2f s', ...
                app.src.name, fmt(app.info.POB, 2), fmt(app.info.POBth), fmt(app.info.POBph), pol, toc(t0)));
        end

        function applyStep(app, resetPlane)
            % Resample the canonical *source* (never the nonlinear outputs) when the 1° grid is selected.
            S = app.stdTbl;
            nonCanonical = abs(gridStep(S.Theta) - 1) > 1e-9 || abs(gridStep(mod(S.Phi, 360)) - 1) > 1e-9;
            if strcmp(app.ui.Step.Value, 'STEP: 1°') && nonCanonical
                app.baseTbl = calcPattern(resampleCanonical(S, 1), app.params(), app.PeakPct, app.PeakExcess);
            else
                app.baseTbl = app.patTbl;
            end
            app.checkCancel();
            app.setComponentItems();
            app.applySpan(true, resetPlane);
        end

        function applySpan(app, resetRanges, resetPlane)
            % Materialize the selected phi/theta display convention into the view table.
            if isempty(app.baseTbl), return; end
            T = app.baseTbl;
            if app.signedPhi()
                T(abs(T.Phi - 360) < 1e-9, :) = [];
                T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
                seam = T(abs(T.Phi - 180) < 1e-9, :); seam.Phi(:) = -180; T = [seam; T];
            end
            if app.elevation(), T.Theta = 90 - T.Theta; end
            app.viewTbl = sortrows(T, {'Phi', 'Theta'});
            app.viewRev = app.viewRev + 1; app.cache = struct();
            app.updateView(resetRanges, resetPlane);
        end

        function updateView(app, resetRanges, resetPlane)
            % Everything derived from the view table: orientation, peak, metrics, ranges, tables, plots.
            T = app.viewTbl; th = app.physTheta(); ph = T.Phi;
            omega = solidWeights(th, ph); gcol = gainColumn(T);
            app.boresight = calcOrientation(th, ph, T.(gcol), omega, app.Axes6, app.PeakPct, app.PeakExcess);
            pk = resolvePeak(T.(app.comp()), app.PeakPct, app.PeakExcess);
            app.info.peak = pk; app.info.POB = pk.value; app.info.POBth = th(pk.index); app.info.POBph = mod(ph(pk.index), 360);
            app.metrics = calcMetrics(T, th, omega, gcol, app.Axes6, app.boresight, app.PeakPct, app.PeakExcess);
            app.checkCancel();
            if resetRanges, app.gainLim = peakWindow(T.(gcol), app.PeakPct, app.PeakExcess); end
            if isAR(app.comp()), lim = [-30 30]; else, lim = app.gainLim; end
            app.setRange("full", lim, true);
            if resetRanges, app.setRange("cut", app.gainLim, true); set([app.ui.Cmin, app.ui.Cmax], {'Value'}, {app.gainLim(1); app.gainLim(2)}); end
            app.filterOutput(resetRanges); app.updateMetadata();
            if resetPlane, app.applyPlane(); else, app.updateCutControl(); app.plotCut(); end
            drawnow limitrate
            app.renderFull();
        end

        %% -------------------------------------------------------------- small state helpers
        function tf = signedPhi(app), tf = strcmp(app.ui.PhiSpan.Value, '-180° to 180°'); end
        function tf = elevation(app), tf = strcmp(app.ui.ThetaSpan.Value, '-90° to 90°'); end
        function c = comp(app), c = app.ui.Component.Value; end

        function th = physTheta(app, T)
            % Physical polar theta of a display table regardless of the theta convention.
            if nargin < 2, T = app.viewTbl; end
            th = T.Theta; if app.elevation(), th = 90 - th; end
        end

        function lbl = compLabel(app)
            dd = app.ui.Component; k = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(k), lbl = strrep(dd.Value, '_', ' '); else, lbl = dd.Items{k}; end
        end

        function [phiLim, thetaLim, thetaDir] = angularLimits(app)
            if app.signedPhi(), phiLim = [-180 180]; else, phiLim = [0 360]; end
            if app.elevation(), thetaLim = [-90 90]; thetaDir = 'normal'; else, thetaLim = [0 180]; thetaDir = 'reverse'; end
        end

        function p = params(app)
            u = app.ui;
            p = struct('GainLoss_dB', u.Loss.Value, 'RxMode', string(u.RxPol.Value), 'RxAR_dB', u.Rw.Value);
            p.FieldScale = 10 ^ (p.GainLoss_dB / 20);
            switch u.PtUnit.Value
                case 'dBm',   p.Pt_dBW = u.Pt.Value - 30;
                case 'Watts', p.Pt_dBW = 10 * log10(max(u.Pt.Value, eps));
                otherwise,    p.Pt_dBW = u.Pt.Value;
            end
            p.R_m = max(u.R.Value, app.DistFloor); if strcmp(u.RUnit.Value, 'km'), p.R_m = 1000 * p.R_m; end
        end

        function checkCancel(app)
            if ~isempty(app.dlg) && isvalid(app.dlg) && app.dlg.CancelRequested
                error('APAT:Cancelled', 'Operation cancelled by user.');
            end
        end

        function setComponentItems(app)
            dd = app.ui.Component; prev = string(dd.Value);
            [cols, labels] = componentMap(app.baseTbl, app.Components);
            dd.ItemsData = {}; dd.Items = cellstr(labels); dd.ItemsData = cellstr(cols);
            dd.Value = char(preferredComponent(prev, cols));
        end

        %% -------------------------------------------------------------- Main-tab callbacks
        function onProcess(app)
            if isempty(app.stdTbl), uialert(app.fig, 'Load a pattern first.', 'Process', 'Icon', 'warning'); return; end
            app.dlg = uiprogressdlg(app.fig, 'Title', 'Processing', 'Message', 'Re-processing pattern...', 'Indeterminate', 'on');
            cleaner = onCleanup(@() delete(app.dlg));
            if isGenericText(app.src.path)                  % reinterpret the cached generic table with the selected format
                out = readSource(app.src.path, app.ui.TextFormat.Value, app.src.textTbl);
                assert(~out.meta.isCoverage, 'The selected generic format identifies a coverage-results file.');
                [app.src.rawTbl, app.src.textTbl, app.src.blocks, app.src.freqs, app.src.meta] = deal(out.rawTbl, out.textTbl, out.blocks, out.freqs, out.meta);
                app.selectBlock(1);
            end
            app.process(true);
        end

        function onTextFormat(app)
            if strcmp(strtrim(app.ui.Path.Value), app.src.path) && isGenericText(app.src.path)
                app.ui.Basis.UserData = true; app.onProcess();
            end
        end

        function onFFD(app)
            k = find(strcmp(app.ui.FFD.Items, app.ui.FFD.Value), 1);
            app.ui.Basis.UserData = true; app.selectBlock(k); app.process(true);
            app.status(1, sprintf('Switched to FFD block %d (%s).', k, app.ui.FFD.Value), true);
        end

        function onStep(app)
            if ~isempty(app.stdTbl), app.applyStep(false); end
        end

        function onThetaSpan(app)
            % Keep the same physical Phi-cut plane when the theta convention flips.
            if isempty(app.baseTbl), return; end
            if strcmp(app.ui.CutType.Value, 'Phi'), app.ui.CutValue.Limits = [-Inf Inf]; app.ui.CutValue.Value = 90 - app.ui.CutValue.Value; end
            app.applySpan(false, false);
        end

        function onComponent(app)
            if ~isempty(app.viewTbl), app.updateView(false, false); end
        end

        function onBasis(app)
            app.ui.Basis.UserData = false;
            if ~isempty(app.viewTbl), app.updateMetadata(); app.onCut(); end
        end

        function onCut(app)
            if isempty(app.viewTbl), return; end
            u = app.ui; u.HPBWBounds.Visible = u.HPBW.Value;
            if ~u.HPBW.Value, u.HPBWBounds.Value = false; end
            app.updateCutControl(); app.plotCut();
            if u.Overlay.Value, app.drawOverlays(); end
        end

        function applyPlane(app)
            % E-plane contains the boresight axis; H-plane is orthogonal to it.
            A = app.Axes6; k = app.boresight; u = app.ui;
            if strcmp(u.Plane.Value, 'E'), type = 'Theta'; val = A.phi(k);
            elseif A.theta(k) == 90,       type = 'Phi';   val = 90; if app.elevation(), val = 0; end
            else,                          type = 'Theta'; val = 90;
            end
            u.CutType.Value = type; u.CutValue.Limits = [-Inf Inf]; u.CutValue.Value = val; app.onCut();
        end

        function updateCutControl(app)
            % The cut value is a fixed theta for Phi cuts and a fixed phi for Theta cuts.
            u = app.ui; T = app.viewTbl;
            if strcmp(u.CutType.Value, 'Phi'), v = unique(T.Theta); else, v = unique(mod(T.Phi, 360)); end
            [~, k] = min(abs(v - u.CutValue.Value));
            u.CutValue.Limits = [-Inf Inf]; u.CutValue.Value = v(k); u.CutValue.Limits = [min(v), max(v)];
            if numel(v) > 1, u.CutValue.Step = min(diff(v)); end
        end

        function resetParams(app)
            u = app.ui; d = app.defaults;
            [u.Loss.Value, u.RxPol.Value, u.Rw.Value, u.Pt.Value, u.PtUnit.Value, u.R.Value, u.RUnit.Value] = ...
                deal(d.Loss, d.RxPol, d.Rw, d.Pt, d.PtUnit, d.R, d.RUnit);
            if ~isempty(app.stdTbl), app.onProcess(); end
        end

        %% -------------------------------------------------------------- colour / range control
        function applyColorbar(app)
            lim = [app.ui.Cmin.Value, app.ui.Cmax.Value];
            app.setRange("full", lim, true); app.setRange("cut", lim, true);
        end

        function setRange(app, scope, lim, resetTravel)
            % Synchronize one range group (full-pattern or cut) from any of its sliders/spinners.
            lim = sort(double(lim(:).')); lim = [max(-250, lim(1)), min(100, lim(2))];
            if diff(lim) < 1, lim(2) = min(100, lim(1) + 1); lim(1) = lim(2) - 1; end
            u = app.ui;
            if scope == "full"
                F = u.Full; sl = [F.slider]; mn = [F.min]; mx = [F.max]; app.fullLim = lim;
                if ~isAR(app.comp()), app.gainLim = lim; end
            else
                sl = u.CutRange; mn = u.CutMin; mx = u.CutMax; app.cutLim = lim;
            end
            travel = lim; if ~resetTravel, travel = [min(sl(1).Limits(1), lim(1)), max(sl(1).Limits(2), lim(2))]; end
            set(sl, 'Limits', [-250 100], 'Value', lim); set(sl, 'Limits', travel);
            set([mn, mx], 'Limits', [-250 100]); set(mn, 'Value', lim(1)); set(mx, 'Value', lim(2));   % widen, move, then tighten
            set(mn, 'Limits', [-250, lim(2) - 1]); set(mx, 'Limits', [lim(1) + 1, 100]);
            if isempty(app.viewTbl), return; end
            if scope == "full"
                for k = 1:numel(F)
                    clim(F(k).axes, lim); app.setTicks(colorbar(F(k).axes), lim, 'Ticks');
                end
                zlim(F(5).axes, lim); app.setTicks(F(5).axes, lim, 'ZTick');
            else
                u.PaxCut.RLim = lim; u.PaxCut.RTick = lim(1):5:lim(2); u.AxRect.YLim = lim;
            end
        end

        function setTicks(app, target, lim, prop)
            s = app.ui.Cstep.Value;
            if ~(s > 0) || diff(lim) <= 0, return; end
            t = unique([lim(1), ceil(lim(1) / s) * s : s : floor(lim(2) / s) * s, lim(2)]);
            if numel(t) <= 60, target.(prop) = t; end
        end

        function theme(app, ax)
            % Colour scale of the selected component: signed AR uses a fixed blue-white-red map.
            lim = app.fullLim; clim(ax, lim);
            if isAR(app.comp()), colormap(ax, interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)));
            else, colormap(ax, jet(256)); end
            app.setTicks(colorbar(ax), lim, 'Ticks');
        end

        %% -------------------------------------------------------------- full-pattern rendering
        function G = viewGrid(app)
            % Rectangular theta x phi grid of the current view (cached per view revision and component).
            T = app.viewTbl; c = app.cache; key = matlab.lang.makeValidName(app.comp());
            if ~isfield(c, 'theta')
                c.theta = unique(T.Theta); c.phi = unique(T.Phi);
                [~, it] = ismember(T.Theta, c.theta); [~, ip] = ismember(T.Phi, c.phi);
                c.idx = sub2ind([numel(c.theta), numel(c.phi)], it, ip);
                [c.PH, c.TH] = meshgrid(c.phi, c.theta);
                c.thetaPolar = c.TH; if app.elevation(), c.thetaPolar = 90 - c.TH; end
                c.phiRad = deg2rad(c.PH); s = sind(c.thetaPolar);
                c.x = s .* cos(c.phiRad); c.y = s .* sin(c.phiRad); c.z = cosd(c.thetaPolar);
                c.Z = struct();
            end
            if ~isfield(c.Z, key), Z = nan(size(c.TH)); Z(c.idx) = T.(app.comp()); c.Z.(key) = Z; end
            app.cache = c; G = c; G.Z = c.Z.(key);
            G.label = app.compLabel(); G.thetaLabel = 'Theta'; if app.elevation(), G.thetaLabel = 'Elevation'; end
            th = app.info.POBth; ph = app.info.POBph;                       % POB in display coordinates
            if app.elevation(), th = 90 - th; end, if app.signedPhi() && ph > 180, ph = ph - 360; end
            [~, G.r] = min(abs(c.theta - th)); [~, G.c] = min(abs(c.phi - ph));
            G.tip = [dataTipTextRow(G.thetaLabel, G.TH(G.r, G.c), '%.3g°'); dataTipTextRow('Phi', G.PH(G.r, G.c), '%.3g°'); ...
                     dataTipTextRow(texLabel(G.label), G.Z(G.r, G.c), '%.3g dB')];
        end

        function renderFull(app)
            if isempty(app.viewTbl) || app.closing, return; end
            G = app.viewGrid(); F = app.ui.Full;
            app.drawContour(F(1).axes, G);  app.checkCancel();
            app.drawFisheye(F(2).axes, G);  app.checkCancel();
            app.draw3D(F(3).axes, G, "sphere"); app.checkCancel();
            app.draw3D(F(4).axes, G, "polar");  app.checkCancel();
            app.drawRect3(F(5).axes, G);
            drawnow limitrate
        end

        function finish(app, ax, h, G, ttl)
            % Shared epilogue for full-pattern surfaces: theme, title, DataTips, context menu.
            app.theme(ax); title(ax, ttl, 'Interpreter', 'none', 'FontSize', 9);
            try
                h.DataTipTemplate.DataTipRows = [dataTipTextRow(G.thetaLabel, G.TH, '%.3g°'); dataTipTextRow('Phi', G.PH, '%.3g°'); ...
                    dataTipTextRow(texLabel(G.label), G.Z, '%.3g dB')];
            catch
            end
            set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', ax.ContextMenu);
            hold(ax, 'off');
        end

        function markPOB(app, ax, x, y, z, rows)
            % Peak-of-beam marker + DataTip. Plain tagged graphics: the checkbox toggles them via findall.
            if ~(isfinite(x) && isfinite(y)), return; end
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), m = polarplot(ax, x, y, 'ko');
            else, m = plot3(ax, x, y, z, 'ko', 'Clipping', 'off'); end
            set(m, 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off', 'Tag', 'APAT_POB');
            m.DataTipTemplate.DataTipRows = rows;
            t = datatip(m, 'DataIndex', 1, 'FontSize', 9, 'Tag', 'APAT_POB');
            if isequal(ax, app.ui.Full(1).axes) && x > mean(ax.XLim), t.Location = 'southwest'; end
            set([m, t], 'Visible', app.ui.POB.Value);
        end

        function drawContour(app, ax, G)
            cla(ax); hold(ax, 'on');
            h = pcolor(ax, G.phi, G.theta, G.Z); set(h, 'FaceColor', 'interp', 'LineStyle', 'none');
            app.formatAngularAxes(ax, 30, 15); daspect(ax, [1 1 1]);
            app.markPOB(ax, G.phi(G.c), G.theta(G.r), 1, G.tip);
            app.finish(ax, h, G, G.label);
        end

        function drawFisheye(app, pax, G)
            cla(pax); hold(pax, 'on');
            h = surface(pax, G.phiRad, G.thetaPolar, zeros(size(G.Z)), G.Z, 'EdgeColor', 'none');
            app.polarTicks(pax); pax.RLim = [0 180]; pax.RTick = 0:30:180;
            r = 0:30:180; if app.elevation(), r = 90 - r; end
            pax.RTickLabel = compose('%d°', r);
            app.markPOB(pax, G.phiRad(G.r, G.c), G.thetaPolar(G.r, G.c), 0, G.tip);
            app.finish(pax, h, G, sprintf('%s  |  r=θ, angle=φ', G.label));
        end

        function draw3D(app, ax, G, kind)
            X = G.x; Y = G.y; Z = G.z; lim = app.fullLim;
            if kind == "polar"
                rad = max(G.Z - lim(1), 0) / max(diff(lim), eps); rad = rad / max(max(rad, [], 'all', 'omitnan'), eps);
                X = rad .* X; Y = rad .* Y; Z = rad .* Z;
            end
            cla(ax); hold(ax, 'on');
            h = surf(ax, X, Y, Z, G.Z, 'EdgeColor', 'none', 'Tag', ['APAT_' char(kind)]);
            set(ax, 'Projection', 'orthographic', 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1]);
            axis(ax, 'off'); app.drawXYZ(ax); app.view3D(ax, [135 25]);
            if app.ui.Overlay.Value, app.overlayCut(ax, kind); end
            app.markPOB(ax, X(G.r, G.c), Y(G.r, G.c), Z(G.r, G.c), G.tip);
            app.finish(ax, h, G, sprintf('%s  |  θ: %s  |  φ: %s', G.label, app.ui.ThetaSpan.Value, app.ui.PhiSpan.Value));
        end

        function drawRect3(app, ax, G)
            cla(ax); hold(ax, 'on');
            h = surf(ax, G.PH, G.TH, G.Z, 'EdgeColor', 'none');
            zlim(ax, app.fullLim); app.setTicks(ax, app.fullLim, 'ZTick');
            app.formatAngularAxes(ax, 60, 30); grid(ax, 'on');
            xlabel(ax, 'Phi (degree)'); ylabel(ax, [G.thetaLabel ' (degree)']); zlabel(ax, [G.label ' (dB)'], 'Interpreter', 'none');
            app.view3D(ax, [-35 35]);
            app.markPOB(ax, G.PH(G.r, G.c), G.TH(G.r, G.c), G.Z(G.r, G.c), G.tip);
            app.finish(ax, h, G, G.label);
        end

        function drawXYZ(~, ax)
            % Principal axes: X red, Y green, Z blue.
            colors = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]};
            labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            for k = 1:3
                d = 1.35 * double(1:3 == k);
                quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25, 'HandleVisibility', 'off');
                text(ax, 1.12 * d(1), 1.12 * d(2), 1.12 * d(3), labels{k}, 'Color', colors{k}, 'FontWeight', 'bold');
            end
        end

        function view3D(app, ax, defaultView)
            views = struct('top', {{0, 90, [0 1 0]}}, 'bottom', {{0, -90, [0 1 0]}}, 'right', {{90, 0, [0 0 1]}}, ...
                'left', {{-90, 0, [0 0 1]}}, 'front', {{0, 0, [0 0 1]}}, 'back', {{180, 0, [0 0 1]}});
            code = app.ui.View3D.Value;
            if isfield(views, code), v = views.(code); view(ax, v{1}, v{2}); camup(ax, v{3});
            else, view(ax, defaultView(1), defaultView(2)); camup(ax, [0 0 1]); end
        end

        function applyViews(app)
            if isempty(app.viewTbl), return; end
            F = app.ui.Full; app.view3D(F(3).axes, [135 25]); app.view3D(F(4).axes, [135 25]); app.view3D(F(5).axes, [-35 35]);
        end

        function overlayCut(app, ax, kind)
            [~, Y, ~, ~, th, ph] = app.cutData(); v = Y(:, 1); lim = app.fullLim;
            if kind == "sphere", r = 1.02; else, r = max(v - lim(1), 0) / max(diff(lim), eps) * 1.01; end
            plot3(ax, r .* sind(th) .* cosd(ph), r .* sind(th) .* sind(ph), r .* cosd(th), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay', 'HandleVisibility', 'off');
        end

        function drawOverlays(app)
            % Toggle the cut overlay on both spatial 3-D plots without re-rendering the surfaces.
            if isempty(app.viewTbl), return; end
            kinds = ["sphere", "polar"];
            for k = 1:2
                ax = app.ui.Full(2 + k).axes; delete(findall(ax, 'Tag', 'APAT_CutOverlay'));
                if app.ui.Overlay.Value, hold(ax, 'on'); app.overlayCut(ax, kinds(k)); hold(ax, 'off'); end
            end
        end

        function formatAngularAxes(app, ax, phiStep, thetaStep)
            [phiLim, thetaLim, thetaDir] = app.angularLimits();
            set(ax, 'XLim', phiLim, 'YLim', thetaLim, 'YDir', thetaDir, 'Box', 'on', 'Layer', 'top', ...
                'XTick', phiLim(1):phiStep:phiLim(2), 'YTick', thetaLim(1):thetaStep:thetaLim(2));
        end

        function polarTicks(app, pax)
            % Polar geometry stays physical; only the labels follow the selected phi convention.
            a = 0:30:330; if app.signedPhi(), a(a > 180) = a(a > 180) - 360; end
            pax.ThetaTick = 0:30:330; pax.ThetaTickLabel = compose('%d°', a);
        end

        %% -------------------------------------------------------------- cut plots
        function [cols, idx] = cutCols(app)
            % Selected Total plus the circular or linear pair; idx keeps line colours stable.
            u = app.ui;
            if app.src.meta.isGainOnly, cols = string(app.comp()); idx = 1; return; end
            if strcmp(u.Basis.Value, 'Linear'), cols = ["E_Total_dB", "E_TH_dB", "E_PH_dB"]; else, cols = ["E_Total_dB", "E_RCP_dB", "E_LCP_dB"]; end
            u.Er.Text = extractBefore(cols(2), "_dB"); u.El.Text = extractBefore(cols(3), "_dB");
            sel = [u.Et.Value, u.Er.Value, u.El.Value]; if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = cols(idx);
        end

        function [ang, Y, names, ttl, th, ph] = cutData(app)
            % The active cut as one closed circle in the selected angular convention.
            T = app.viewTbl; u = app.ui; cols = app.cutCols(); type = string(u.CutType.Value);
            thP = app.physTheta();
            [rows, ang, fixed, sym, snapped] = calcCutGeometry(T.Theta, thP, T.Phi, type, u.CutValue.Value);
            if snapped, app.status(1, sprintf('%s cut snapped to nearest %s = %g°', type, sym, fixed), true); end
            Y = T{rows, cols}; th = thP(rows); ph = T.Phi(rows);
            if app.signedPhi(), ang(ang > 180) = ang(ang > 180) - 360; end
            [ang, iu] = unique(ang); Y = Y(iu, :); th = th(iu); ph = ph(iu);
            lim = app.angularLimits();                     % close the circle at the seam (periodic)
            if abs(ang(1) - lim(1)) > 1e-9, ang = [lim(1); ang]; Y = [Y(end, :); Y]; th = [th(end); th]; ph = [ph(end); ph]; end
            if abs(ang(end) - lim(2)) > 1e-9, ang = [ang; lim(2)]; Y = [Y; Y(1, :)]; th = [th; th(1)]; ph = [ph; ph(1)]; end
            names = texLabel(cols);
            if app.src.meta.isGainOnly, ttl = app.compLabel(); else, ttl = sprintf('%s cut @ %s = %g°', type, sym, fixed); end
        end

        function plotCut(app)
            u = app.ui; pax = u.PaxCut; rax = u.AxRect;
            [ang, Y, names, ttl] = app.cutData(); [~, idx] = app.cutCols(); lim = app.cutLim;
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on');
            pl = polarplot(pax, deg2rad(ang), max(Y, lim(1)), 'LineWidth', 1.4);   % clamp: no reflection below RLim
            rl = plot(rax, ang, Y, 'LineWidth', 1.4);
            colors = rax.ColorOrder(1 + mod(idx - 1, size(rax.ColorOrder, 1)), :);
            for k = 1:numel(pl)
                rows = [dataTipTextRow('Angle', ang, '%.3g°'); dataTipTextRow('Magnitude', Y(:, k), '%.3g dB')];
                set([pl(k), rl(k)], 'Color', colors(k, :)); pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            [xl, ~, ~] = app.angularLimits();
            set(pax, 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.polarTicks(pax);
            set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, [u.CutType.Value ' (degree)']); title(pax, ttl, 'Interpreter', 'none'); title(rax, ttl, 'Interpreter', 'none');

            [pk, i] = max(Y(:, 1), [], 'omitnan');                            % POB of the displayed cut
            if isfinite(pk)
                rows = [dataTipTextRow('Angle', ang(i), '%.3g°'); dataTipTextRow('Magnitude', pk, '%.3g dB')];
                app.markPOB(pax, deg2rad(ang(i)), max(pk, lim(1)), 0, rows); app.markPOB(rax, ang(i), pk, 0, rows);
            end
            u.HPBWLabel.Text = '';
            if u.HPBW.Value && isfinite(pk)
                [bw, lo, hi] = calcHPBW(ang, Y(:, 1), pk, ang(i));
                if isfinite(bw)
                    b = [lo, hi]; if xl(1) < 0, b = mod(b + 180, 360) - 180; else, b = mod(b, 360); end
                    u.HPBWLabel.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                    if b(1) <= b(2), reg = b; else, reg = [xl(1), b(2); b(1), xl(2)]; end
                    thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    xregion(rax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    bound = ["Lower HPBW", "Upper HPBW"];
                    for k = 1:2
                        rows = [dataTipTextRow(bound(k), b(k), '%.2f°'); dataTipTextRow('Gain', pk - 3, '%.2f dB')];
                        m = [polarplot(pax, deg2rad(b(k)), pk - 3, 'o'), plot(rax, b(k), pk - 3, 'o')];
                        set(m, 'Color', '#D95319', 'MarkerFaceColor', '#D95319', 'HandleVisibility', 'off', 'Tag', 'APAT_HPBW');
                        for h = m
                            h.DataTipTemplate.DataTipRows = rows;
                            t = datatip(h, 'DataIndex', 1, 'FontSize', 9, 'Tag', 'APAT_HPBW'); t.Visible = u.HPBWBounds.Value;
                        end
                    end
                end
            end
            legend(pax, pl, names, 'Location', 'southoutside', 'Orientation', 'horizontal');
            legend(rax, rl, names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off');
        end

        %% -------------------------------------------------------------- tables & metadata
        function filterOutput(app, rebuild)
            % Result-column filter: the dropdown acts as a checklist (✓ = shown).
            u = app.ui; dd = u.Filter; T = app.viewTbl; cols = T.Properties.VariableNames(3:end);
            if rebuild || numel(dd.UserData) ~= numel(cols)
                dd.UserData = ~ismember(cols, app.HiddenColumns);
            elseif dd.Value > 0
                dd.UserData(dd.Value) = ~dd.UserData(dd.Value);
            end
            on = find(dd.UserData); items = cols; items(on) = append('✓ ', cols(on));
            dd.ItemsData = {}; dd.Items = [{'--- column filter ---'}, items]; dd.ItemsData = num2cell(0:numel(cols)); dd.Value = 0;
            removeStyle(dd); off = find(~dd.UserData);
            if ~isempty(on), addStyle(dd, app.styles{1}, 'Item', on + 1); end
            if ~isempty(off), addStyle(dd, app.styles{2}, 'Item', off + 1); end
            u.TableOut.Data = T(:, [true, true, dd.UserData]);
            app.updateInputVisibility();
        end

        function updateInputVisibility(app)
            u = app.ui; cols = app.viewTbl.Properties.VariableNames(3:end); shown = string(cols(u.Filter.UserData));
            has = @(names) any(ismember(shown, names));
            set([u.RxPolLabel, u.RxPol, u.RwLabel, u.Rw], 'Visible', has(["PLF_dB", "Gain_PolCorrected_dB"]));
            set([u.PtLabel, u.Pt, u.PtUnit], 'Visible', has(["EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
            set([u.RLabel, u.R, u.RUnit], 'Visible', has(["PFD_Wm2", "E_RMS_Vm"]));
            set([u.LossLabel, u.Loss], 'Visible', app.src.meta.isGainOnly || has(["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "Gain_PolCorrected_dB", "EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
        end

        function updateMetadata(app)
            T = app.viewTbl; m = app.metrics; meta = app.src.meta; th = unique(T.Theta); ph = unique(T.Phi);
            rows = {'Source format', meta.source; 'File', app.src.name; ...
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(T), numel(th), numel(ph)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmt(min(th)), fmt(max(th)), fmt(gridStep(th))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmt(min(ph)), fmt(max(ph)), fmt(gridStep(ph)))};
            f = app.src.freqs(isfinite(app.src.freqs));
            if ~isempty(f), rows(end + 1, :) = {'Frequencies', strjoin(compose('%.4g GHz', f(:).' / 1e9), ', ')}; end
            if ~meta.isGainOnly
                rows = [rows; {'Polarization', app.info.pol; 'Cut Co-pol / Cross-pol', char(strjoin(app.info.pairs.(app.ui.Basis.Value), ' / '))}];
            end
            rows = [rows; {
                sprintf('Peak of %s', app.compLabel()), sprintf('%s dB @ [θ=%s°, φ=%s°]', fmt(app.info.POB), fmt(app.info.POBth), fmt(app.info.POBph))
                'Peak policy', sprintf('P%.4g + %g dB max excess (adjusted: %s)', app.PeakPct, app.PeakExcess, string(app.info.peak.wasAdjusted))
                'Boresight axis', app.Axes6.labels{app.boresight}
                'Peak gain (POB)', sprintf('%s dB @ [θ=%s°, φ=%s°]', fmt(m.PeakGain_dB), fmt(m.PeakTheta_deg), fmt(m.PeakPhi_deg))
                'HPBW E-plane / H-plane', sprintf('%s° / %s°', fmt(m.HPBW_EPlane_deg), fmt(m.HPBW_HPlane_deg))
                'Front-to-back', sprintf('%s dB', fmt(m.FrontBack_dB))
                'Peak directivity', sprintf('%s dB', fmt(m.PeakDirectivity_dB))}];
            if isfinite(m.Efficiency_pct), rows(end + 1, :) = {'Radiation efficiency', sprintf('%s%%', fmt(m.Efficiency_pct))}; end
            if isfinite(m.AxialRatioAtPeak_dB), rows(end + 1, :) = {'AR at peak', sprintf('%s dB', fmt(m.AxialRatioAtPeak_dB))}; end
            app.ui.TableMeta.Data = rows;
        end
    end

    %% ------------------------------------------------------------------ coverage tab
    methods (Access = private)
        function covFromMain(app)
            % Coverage of the CURRENT Main view table (loss, step, span and component derivation included).
            if isempty(app.viewTbl), uialert(app.fig, 'Load and process a pattern first.', 'Coverage'); return; end
            u = app.ui; u.Tabs.SelectedTab = u.TabCov; u.CovPath.Value = app.src.path;
            node = app.covFind(app.src.path);
            if isempty(node), node = app.covAddPattern(app.src.base, app.viewTbl, app.physTheta(), app.src.path, app.boresight);
            else, app.covSyncFromView(node); end
            u.CovTree.SelectedNodes = node; app.covUI();
            app.status(2, 'Coverage source synchronized from the current Main-tab View Table.');
        end

        function onCovLoad(app)
            u = app.ui; fp = strtrim(u.CovPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFind(fp))
                [f, p] = uigetfile(app.FileFilter, 'Select a pattern or coverage results file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            existing = app.covFind(fp);
            if ~isempty(existing)
                u.CovTree.SelectedNodes = existing; app.onCovSelect();
                app.status(2, 'File already loaded -- node selected.', true); return
            end
            u.CovPath.Value = fp; out = app.readAny(fp, 2);
            if out.meta.isCoverage, app.covLoadResults(fp, out.rawTbl);
            else, [~, name] = fileparts(fp); app.covAddPattern(name, app.buildPattern(out), [], fp); end
        end

        function onCovTextFormat(app)
            % Re-interpret a generic coverage pattern node with the newly selected text format.
            fp = strtrim(app.ui.CovPath.Value); node = app.covFind(fp);
            if isempty(node) || ~isGenericText(fp), return; end
            out = readSource(fp, app.ui.CovTextFormat.Value);
            if out.meta.isCoverage, app.status(2, 'Coverage-result files are detected automatically.', true); return; end
            name = node.NodeData.name; app.covDeleteNodes(node);
            app.covAddPattern(name, app.buildPattern(out), [], fp);
            app.status(2, sprintf('Pattern "<b>%s</b>" reprocessed with the selected format.', name), true);
        end

        function T = buildPattern(app, out)
            % Auxiliary pattern for the Coverage tab (block 1, current parameters), Main state untouched.
            S = normalizePattern(out.blocks{1}); S.Properties.UserData = out.meta;
            T = calcPattern(S, app.params(), app.PeakPct, app.PeakExcess);
        end

        function node = covAddPattern(app, name, T, theta, path, boresight)
            u = app.ui; if isempty(theta), theta = T.Theta; end
            omega = solidWeights(theta, T.Phi);
            if nargin < 6, boresight = calcOrientation(theta, T.Phi, T.(gainColumn(T)), omega, app.Axes6, app.PeakPct, app.PeakExcess); end
            node = uitreenode(u.CovRoot, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', 'pattern', 'name', name, 'path', path, 'pattern', T, 'theta', theta, ...
                'omega', omega, 'boresight', boresight, 'component', "", 'rev', app.viewRev);
            expand(u.CovTree); u.CovTree.CheckedNodes = [u.CovTree.CheckedNodes; node]; u.CovTree.SelectedNodes = node;
            app.covSync(node); app.covUI();
            app.status(2, sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name));
        end

        function covSyncFromView(app, node)
            d = node.NodeData;
            [d.pattern, d.theta, d.name, d.boresight, d.rev] = deal(app.viewTbl, app.physTheta(), app.src.base, app.boresight, app.viewRev);
            d.omega = solidWeights(d.theta, d.pattern.Phi); node.NodeData = d;
            app.covSync(node);
        end

        function covSync(app, node)
            % Align the component list and the threshold preset with the target pattern node.
            if isempty(node), return; end
            u = app.ui; d = node.NodeData; T = d.pattern;
            [cols, labels] = componentMap(T, app.Components);
            if strlength(d.component) > 0, prev = d.component; else, prev = string(u.CovComponent.Value); end
            if ~isequal(string(u.CovComponent.ItemsData), cols)
                u.CovComponent.ItemsData = {}; u.CovComponent.Items = cellstr(labels); u.CovComponent.ItemsData = cellstr(cols);
            end
            comp = preferredComponent(prev, cols); u.CovComponent.Value = char(comp);
            d.component = comp; node.NodeData = d;
            key = sprintf('%s|%s|%d', d.path, comp, d.rev);     % new pattern/component/view -> new 50 dB preset
            if ~strcmp(app.cov.presetKey, key)
                app.cov.presetKey = key; b = peakWindow(T.(char(comp)), app.PeakPct, app.PeakExcess);
                u.ThrMin.Value = b(1); u.ThrMax.Value = b(2);
            end
            if u.CovOrient.Value == 0, app.onCovOrientation(); end
        end

        function node = covTarget(app)
            % Pattern node to operate on: the selection (or its pattern ancestor), else the newest pattern node.
            node = []; n = app.ui.CovTree.SelectedNodes;
            while ~isempty(n) && isa(n(1), 'matlab.ui.container.TreeNode')
                if isstruct(n(1).NodeData) && strcmp(n(1).NodeData.kind, 'pattern'), node = n(1); return; end
                n = n(1).Parent;
            end
            kids = app.ui.CovRoot.Children;
            for k = numel(kids):-1:1
                if strcmp(kids(k).NodeData.kind, 'pattern'), node = kids(k); return; end
            end
        end

        function node = covFind(app, fp)
            node = []; kids = app.ui.CovRoot.Children;
            for k = 1:numel(kids)
                if isfield(kids(k).NodeData, 'path') && strcmp(kids(k).NodeData.path, fp), node = kids(k); return; end
            end
        end

        function jobs = covJobs(app, roots)
            % Ordered job nodes (optionally restricted to the subtree of ROOTS).
            app.cov.jobs = app.cov.jobs(cellfun(@isvalid, app.cov.jobs)); jobs = [app.cov.jobs{:}];
            if nargin > 1 && ~isempty(roots) && ~isempty(jobs), jobs = jobs(isIn(jobs, findobj(roots))); end
            if isempty(jobs), jobs = matlab.ui.container.TreeNode.empty(1, 0); end
        end

        function thr = covThresholds(app)
            u = app.ui; lo = u.ThrMin.Value; hi = u.ThrMax.Value; st = max(u.ThrStep.Value, 0.1);
            if hi <= lo, hi = min(100, lo + st); u.ThrMax.Value = hi; end
            thr = (lo:st:hi)'; if thr(end) < hi - 1e-9, thr(end + 1) = hi; end
        end

        function covCompute(app)
            node = app.covTarget();
            if isempty(node), uialert(app.fig, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if strcmp(node.NodeData.path, app.src.path) && ~isempty(app.viewTbl), app.covSyncFromView(node); end
            u = app.ui; d = node.NodeData; T = d.pattern; comp = u.CovComponent.Value; thr = app.covThresholds();
            meta = struct('conical', u.CovConical.Value, 'orientation', "n/a", 'thr', thr);
            if meta.conical
                th0 = u.ConeTh.Value; ph0 = mod(u.ConePh.Value, 360); a = u.ConeAng.Value;
                mask = cosd(d.theta) .* cosd(th0) + sind(d.theta) .* sind(th0) .* cosd(T.Phi - ph0) >= cosd(a);
                center = app.coneLabel(th0, ph0);
                tag = sprintf('Con %s α%s°', erase(center, ["=", ","]), fmt(a));
                label = sprintf('Conical coverage (%s) α=%s°', center, fmt(a));
                k = u.CovOrient.Value; if k == 0, k = d.boresight; end
                meta.orientation = string(app.Axes6.labels{k});
            else
                mask = true(height(T), 1); tag = 'Sph'; label = 'Spherical coverage';
            end
            cov = coverageCCDF(T.(comp), mask, thr, d.omega);
            app.covAddJob(node, thr, cov, label, tag, comp, meta);
            app.covSetXRange([thr(1), thr(end)]);
            msg = sprintf('Run-<b>%d</b>: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', app.cov.runID, label, d.name, comp, numel(thr));
            if meta.conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, meta.orientation); end
            app.status(2, msg);
        end

        function node = covAddJob(app, parent, thr, cov, label, tag, comp, meta)
            app.cov.runID = app.cov.runID + 1; id = app.cov.runID;
            text = sprintf('📉 R%d %s · %s', id, label, comp);
            ln = plot(app.ui.CovAxes, thr, cov, 'LineWidth', 1.6, 'DisplayName', text);
            ln.DataTipTemplate.DataTipRows = [dataTipTextRow('Threshold', 'XData', '%.2f dB'); dataTipTextRow('Coverage', 'YData', '%.2f %%')];
            [icov, ii] = unique(cov, 'last');
            node = uitreenode(parent, 'Text', text);
            node.NodeData = struct('kind', 'job', 'id', id, 'label', text, 'tag', tag, 'thr', thr(:), 'cov', cov(:), ...
                'invCov', icov(:), 'invThr', thr(ii), 'line', ln, 'meta', meta);
            app.cov.jobs{end + 1} = node;
            app.ui.CovTree.CheckedNodes = [app.ui.CovTree.CheckedNodes; node]; expand(parent);
            app.covRefresh();
        end

        function covLoadResults(app, fp, R)
            [~, name] = fileparts(fp); u = app.ui;
            node = uitreenode(u.CovRoot, 'Text', ['📄 ' name]); node.NodeData = struct('kind', 'results', 'name', name, 'path', fp);
            u.CovTree.CheckedNodes = [u.CovTree.CheckedNodes; node]; thr = R{:, 1};
            for k = 2:width(R)
                app.covAddJob(node, thr, R{:, k}, 'Res', R.Properties.VariableNames{k}, R.Properties.VariableNames{k}, struct('conical', false, 'orientation', "n/a", 'thr', thr));
            end
            app.covSetXRange([min(thr), max(thr)]); if gridStep(thr) < u.ThrStep.Value, u.ThrStep.Value = gridStep(thr); end
            expand(u.CovRoot); app.covUI();
            app.status(2, sprintf('Coverage results file "<b>%s</b>" loaded (%d curves).', name, width(R) - 1));
        end

        function covRefresh(app)
            % Visibility, results table and legend all follow the checked job nodes.
            u = app.ui; jobs = app.covJobs(); checked = jobs(isIn(jobs, u.CovTree.CheckedNodes));
            for j = jobs
                d = j.NodeData; vis = isIn(j, checked);
                set([d.line; findall(d.line, 'Type', 'datatip'); findall(u.CovAxes, '-regexp', 'Tag', sprintf('^CovQ_[a-z]+_%d$', d.id))], 'Visible', vis);
            end
            if isempty(checked)
                u.CovTable.Data = table(); legend(u.CovAxes, 'off');
            else
                c = arrayfun(@(n) n.NodeData.thr, checked, 'UniformOutput', false); thr = unique(vertcat(c{:}));
                V = [thr, nan(numel(thr), numel(checked))]; names = [{'Threshold (dB)'}, cell(1, numel(checked))];
                for k = 1:numel(checked)
                    d = checked(k).NodeData; V(:, k + 1) = safeInterp(d.thr, d.cov, thr); names{k + 1} = sprintf('R%d %s %%', d.id, d.tag);
                end
                u.CovTable.Data = array2table(compose('%.2f', V), 'VariableNames', names);
                D = [checked.NodeData]; legend(u.CovAxes, [D.line], {D.label}, 'Location', 'southwest', 'Interpreter', 'none');
            end
            app.covUI();
        end

        function covUI(app)
            u = app.ui; hasPat = ~isempty(app.covTarget()); hasJobs = ~isempty(app.covJobs());
            set(u.CovPatternCtrls, 'Visible', hasPat, 'Enable', hasPat);
            set(u.QueryCtrls, 'Visible', hasJobs, 'Enable', hasJobs);
            set([u.CovExport, u.CovClear], 'Enable', hasJobs); u.CovReset.Enable = hasPat || hasJobs;
            u.CovResults.Visible = hasPat || hasJobs;
            set([u.CovTextFormatLabel, u.CovTextFormat], 'Visible', hasPat && isGenericText(u.CovPath.Value));
            app.onCovType();
        end

        function onCovComponent(app)
            % The user's component choice is remembered per pattern node.
            node = app.covTarget();
            if ~isempty(node), node.NodeData.component = string(app.ui.CovComponent.Value); app.covSync(node); end
        end

        function onCovType(app, userAction)
            u = app.ui; on = u.CovConical.Value && ~isempty(app.covTarget());
            set(u.ConeCtrls, 'Visible', on, 'Enable', on);
            if on && nargin > 1 && userAction, app.onCovOrientation(); end
        end

        function onCovOrientation(app)
            % Auto follows the detected boresight; an explicit axis sets the cone centre spinners.
            u = app.ui; k = u.CovOrient.Value; node = app.covTarget();
            if k == 0 && ~isempty(node), k = node.NodeData.boresight; end
            if k == 0 || ~u.CovConical.Value, return; end
            A = app.Axes6; u.ConeTh.Value = A.theta(k); u.ConePh.Value = A.phi(k);
            app.status(2, sprintf('Cone orientation <b>%s</b> (θ₀=%g°, φ₀=%g°)', A.labels{k}, A.theta(k), A.phi(k)));
        end

        function lbl = coneLabel(app, theta, phi)
            % Principal-axis name when the cone centre matches one exactly, else the spherical coordinates.
            A = app.Axes6; v = [sind(theta) * cosd(phi), sind(theta) * sind(phi), cosd(theta)];
            V = [sind(A.theta(:)) .* cosd(A.phi(:)), sind(A.theta(:)) .* sind(A.phi(:)), cosd(A.theta(:))];
            k = find(V * v(:) >= 1 - 1e-9, 1);
            if isempty(k), lbl = sprintf('θ=%s°, φ=%s°', fmt(theta), fmt(phi)); else, lbl = A.labels{k}; end
        end

        function covQuery(app, mode)
            % Project a threshold (mode "cov") or a coverage level (mode "thr") onto every checked job of the selection.
            u = app.ui; ax = u.CovAxes; jobs = app.covJobs(u.CovTree.SelectedNodes); jobs = jobs(isIn(jobs, u.CovTree.CheckedNodes));
            if isempty(u.CovTree.SelectedNodes), app.status(2, 'Select a node to query.', true); return; end
            if isempty(jobs), app.status(2, 'No checked results under the selected node.', true); return; end
            if mode == "cov", q = u.QueryCov.Value; else, q = u.QueryThr.Value; end
            hit = false;
            for j = jobs
                d = j.NodeData; tag = sprintf('CovQ_%s_%d', mode, d.id);
                delete([findall(ax, 'Tag', tag); findall(d.line, 'Tag', tag)]);
                if mode == "cov", x = q; y = safeInterp(d.thr, d.cov, q); else, y = q; x = safeInterp(d.invCov, d.invThr, q); end
                if ~(isfinite(x) && isfinite(y)), continue; end
                line(ax, [x x; -250 x]', [0 y; y y]', 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'FontSize', 9, 'Tag', tag); hit = true;
            end
            if ~hit, app.status(2, 'Query value is outside the range of the checked results.', true);
            elseif mode == "cov", app.status(2, sprintf('Coverage queried at %s dB.', fmt(q)));
            else, app.status(2, sprintf('Threshold queried at %s%% coverage.', fmt(q))); end
        end

        function onCovSelect(app)
            u = app.ui; sel = u.CovTree.SelectedNodes; jobs = app.covJobs();
            for j = jobs, j.NodeData.line.LineWidth = 1.6; end
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.status(2, 'Ready.'); return; end
            d = sel(1).NodeData; app.covSync(app.covTarget());
            if ~strcmp(d.kind, 'job')
                app.status(2, sprintf('%s <b>"%s"</b> -- <b>%d</b> coverage job(s).', d.kind, d.name, numel(sel(1).Children))); return
            end
            d.line.LineWidth = 2.6;
            [mx, k] = max(round(d.cov, 2)); t50 = safeInterp(d.invCov, d.invThr, 50);
            parts = {d.label, sprintf('Threshold [%s, %s] dB, step %s dB', fmt(d.thr(1)), fmt(d.thr(end)), fmt(gridStep(d.thr)))};
            if d.meta.conical, parts{end + 1} = sprintf('Orientation <b>%s</b>', d.meta.orientation); end
            if isfinite(t50), parts{end + 1} = sprintf('50%%-coverage threshold <b>%s dB</b>', fmt(t50)); end
            parts{end + 1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmt(mx), fmt(d.thr(k)));
            app.status(2, strjoin(parts, ' | '));
        end

        function covXRange(app, src)
            % Min/Max spinners are the master controls; the range slider is subordinate and never shrinks its travel.
            u = app.ui; if app.cov.syncing, return; end
            app.cov.syncing = true; cleaner = onCleanup(@() app.covSyncDone());
            if isequal(src, u.CovXRange)
                b = sort(src.Value); if diff(b) <= 0, return; end
                u.CovXMin.Value = b(1); u.CovXMax.Value = b(2);
            else
                b = [u.CovXMin.Value, u.CovXMax.Value];
                if diff(b) <= 0, if isequal(src, u.CovXMin), b(2) = min(100, b(1) + 1); else, b(1) = max(-250, b(2) - 1); end, end
                set(u.CovXRange, 'Limits', [-250 100], 'Value', b); u.CovXRange.Limits = b;
                u.CovXMin.Value = b(1); u.CovXMax.Value = b(2);
            end
            u.CovAxes.XLim = b;
        end

        function covSyncDone(app), if ~app.closing, app.cov.syncing = false; end, end

        function covSetXRange(app, b)
            % The first result establishes the X baseline; later results may only widen it.
            if app.cov.plotInit, b = [min(app.ui.CovAxes.XLim(1), b(1)), max(app.ui.CovAxes.XLim(2), b(2))]; end
            app.cov.plotInit = true; app.ui.CovXMin.Value = b(1); app.ui.CovXMax.Value = b(2);
            app.covXRange(app.ui.CovXMin);
        end

        function covDeleteNodes(~, nodes)
            for n = nodes(:).'
                for j = findobj(n)'
                    if isstruct(j.NodeData) && isfield(j.NodeData, 'line') && isgraphics(j.NodeData.line), delete(j.NodeData.line); end
                end
            end
            delete(nodes);
        end

        function covReset(app)
            u = app.ui; app.covDeleteNodes(u.CovRoot.Children);
            delete(findall(u.CovAxes, 'Type', 'datatip')); app.initCovAxes();
            u.CovTable.Data = table(); app.cov = struct('runID', 0, 'jobs', {{}}, 'presetKey', "", 'plotInit', false, 'syncing', false);
            set(u.CovXRange, 'Limits', [-250 100], 'Value', [-40 10]); u.CovXMin.Value = -40; u.CovXMax.Value = 10;
            app.covUI(); app.status(2, 'Coverage workspace reset 🔄', true);
        end

        function covClear(app)
            % Remove DataTips and query projections of the selected subtree only.
            jobs = app.covJobs(app.ui.CovTree.SelectedNodes);
            if isempty(jobs), app.status(2, 'Select a node with coverage results to clear.', true); return; end
            for j = jobs
                delete(findall(j.NodeData.line, 'Type', 'datatip'));
                delete(findall(app.ui.CovAxes, '-regexp', 'Tag', sprintf('^CovQ_[a-z]+_%d$', j.NodeData.id)));
            end
            app.status(2, 'Selected DataTips and query markers cleared.', true);
        end

        function covExport(app)
            if isempty(app.ui.CovTable.Data), return; end
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, ...
                'Export Coverage Results', fullfile(app.src.folder, 'coverage_results.csv'));
            if isequal(f, 0), return; end
            writeTable(app.ui.CovTable.Data, fullfile(p, f)); app.status(2, ['Coverage results exported to ' fullfile(p, f)], true);
        end
    end

    %% ------------------------------------------------------------------ status, errors, export
    methods (Access = private)
        function status(app, tab, msg, temporary)
            % Permanent messages are remembered; temporary ones revert after 3 s.
            if app.closing, return; end
            lbl = app.ui.Status(tab); app.stopTimer(); lbl.Text = char(msg);
            if nargin > 3 && temporary
                app.statusTimer = timer('StartDelay', 3, 'TimerFcn', @(~, ~) app.restoreStatus(lbl), 'StopFcn', @(t, ~) delete(t));
                start(app.statusTimer);
            else
                lbl.UserData = char(msg);
            end
        end

        function restoreStatus(app, lbl)
            if ~app.closing && isgraphics(lbl) && ischar(lbl.UserData), lbl.Text = lbl.UserData; end
        end

        function stopTimer(app)
            t = app.statusTimer; app.statusTimer = [];
            if ~isempty(t) && isvalid(t), stop(t); delete(t); end
        end

        function showError(app, ME)
            if app.closing || ~isgraphics(app.fig), return; end
            where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.fig, [ME.message where], 'APAT error', 'Icon', 'error');
        end

        function exportResults(app)
            if isempty(app.viewTbl), return; end
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, ...
                'Export Results', fullfile(app.src.folder, [app.src.base '_APAT_results.csv']));
            if isequal(f, 0), return; end
            writeTable(app.ui.TableOut.Data, fullfile(p, f));               % respects the active column filter
            app.status(1, ['Results exported to <b>' fullfile(p, f) '</b>'], true);
        end

        function exportCut(app)
            if isempty(app.viewTbl), return; end
            [ang, Y, ~, ttl] = app.cutData(); cols = app.cutCols();
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, 'Export Cut', fullfile(app.src.folder, [app.src.base '_cut.csv']));
            if isequal(f, 0), return; end
            writeTable(array2table([ang, Y], 'VariableNames', [{'Angle_deg'}, cellstr(cols)]), fullfile(p, f));
            app.status(1, ['Cut (' ttl ') exported to <b>' fullfile(p, f) '</b>'], true);
        end

        function exportUAN(app)
            if isempty(app.viewTbl) || app.src.meta.isGainOnly, uialert(app.fig, 'No E-field data to export.', 'Export UAN'); return; end
            V = app.viewTbl;
            U = sortrows(table(app.physTheta(), V.Phi, round(V.E_TH_dB, 5), round(V.E_PH_dB, 5), round(V.E_TH_Phase, 5), round(V.E_PH_Phase, 5), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'}), {'Phi', 'Theta'});
            peak = max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan'); step = gridStep(U.Theta); if ~isfinite(step), step = 1; end
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, ...
                'Export UAN / E-field data', fullfile(app.src.folder, sprintf('%s_%.5f_%gdeg.uan', app.src.base, peak, step)));
            if isequal(f, 0), return; end
            fp = fullfile(p, f);
            if endsWith(fp, '.uan', 'IgnoreCase', true)
                header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                    min(U.Phi), max(U.Phi), gridStep(mod(U.Phi, 360)), min(U.Theta), max(U.Theta), step, peak);
                writelines(header, fp);
                writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
            else
                writeTable(U, fp);
            end
            app.status(1, ['UAN exported to <b>' fp '</b>'], true);
        end
    end

    %% ------------------------------------------------------------------ self-test
    methods (Access = public)
        function report = selfTest(app)
            %SELFTEST Deterministic checks of the numerical services (no UI interaction required).
            [P, T] = meshgrid(0:30:330, 0:30:180); G = table(T(:), P(:), 10 * cosd(T(:) / 2).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            w = solidWeights(G.Theta, G.Phi);
            r.solidAngle = abs(sum(w) - 4 * pi) < 1e-9;
            r.orientation = calcOrientation(G.Theta, G.Phi, G.E_Total_dB, w, app.Axes6, app.PeakPct, app.PeakExcess) == 1;

            [P2, T2] = meshgrid(0:2:358, 0:2:180); f = @(t, p) 12 * cosd(t).^2 - 0.5 * sind(p).^2;
            R = resampleCanonical(table(T2(:), P2(:), f(T2(:), P2(:)), 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'}), 1);
            native = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0 & R.Phi < 360;
            r.resampleSize = height(R) == 181 * 361;
            r.resampleExact = max(abs(R.E_Total_dB(native) - f(R.Theta(native), R.Phi(native)))) < 1e-10;

            r.peakWindow = isequal(peakWindow([3.2; -250; -17], app.PeakPct, app.PeakExcess), [-45 5]);
            spike = repmat(0.02, 100000, 1); spike(1) = 10.02; pk = resolvePeak(spike, app.PeakPct, app.PeakExcess);
            r.isolatedSpike = pk.wasAdjusted && abs(pk.value - 0.02) < 1e-12 && pk.rawIndex == 1;
            r.arSemantics = all(arrayfun(@isAR, ["AR", "AR_dB", "AR dB", "Axial Ratio", "Axial_Ratio"])) && ~isAR("E_Total_dB");

            cut = (-180:179)'; r.hpbw = abs(calcHPBW(cut, -abs(cut) / 10) - 60) < 1e-9;   % triangular beam: exact 60° HPBW
            c = coverageCCDF([0; 10; 20], true(3, 1), [-1; 5; 15; 25], [1; 1; 2]);
            r.coverage = isequal(c, [100; 75; 50; 0]);

            fp = [tempname '.ffd']; fid = fopen(fp, 'w'); cleaner = onCleanup(@() delete(fp));
            fprintf(fid, '0 180 3\n-180 180 3\n'); fprintf(fid, '%d 0 0 1\n', 1:9); fclose(fid);
            d = readSource(fp, 'gain'); r.ffdReader = strcmp(d.meta.source, 'HFSS FFD') && isscalar(d.blocks) && height(d.blocks{1}) == 9;

            flags = cell2mat(struct2cell(r)); report = r; report.pass = all(flags);
            if ~report.pass
                names = fieldnames(r); error('APAT:SelfTestFailed', 'Failed checks: %s', strjoin(names(~flags), ', '));
            end
        end
    end
end

%% ========================================================================== local helpers
function h = place(h, row, col)
h.Layout.Row = row; h.Layout.Column = col;
end

function s = fmt(value, precision)
% Compact number formatting ('n/a' for non-finite). fmt(v) trims to <= 2 decimals; fmt(v, N) keeps N.
if ~isscalar(value) || ~isnumeric(value) || ~isfinite(value), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', value), '\.?0+$', ''); else, s = sprintf('%.*f', precision, value); end
end

function s = texLabel(s), s = replace(string(s), "_", "\_"); end

function tf = isIn(nodes, list)
% Handle membership that tolerates an empty LIST of any class.
tf = false(size(nodes));
for k = 1:numel(nodes), tf(k) = any(arrayfun(@(n) n == nodes(k), list)); end
end

function v = safeInterp(x, y, q)
% Linear interpolation that returns NaN instead of erroring on degenerate (constant) supports.
[xu, iu] = unique(x(:)); y = y(:);
if numel(xu) < 2, v = nan(size(q)); else, v = interp1(xu, y(iu), q, 'linear', NaN); end
end

function tf = isGenericText(fp)
[~, ~, ext] = fileparts(fp); tf = any(strcmpi(ext, {'.csv', '.txt', '.dat'}));
end

function tf = isAR(name)
key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', '');
tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
end

function col = gainColumn(T)
% The total-gain column, or the first data column of a gain-only table.
vars = T.Properties.VariableNames;
if ismember('E_Total_dB', vars), col = 'E_Total_dB'; else, col = vars{3}; end
end

function [cols, labels] = componentMap(T, catalog)
available = string(T.Properties.VariableNames(3:end)); ud = T.Properties.UserData;
if isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly, cols = available; labels = available; return; end
present = ismember(catalog(1, :), available); cols = catalog(1, present); labels = catalog(2, present);
end

function c = preferredComponent(previous, cols)
if any(cols == string(previous)), c = string(previous); elseif any(cols == "E_Total_dB"), c = "E_Total_dB"; else, c = cols(1); end
end

function step = gridStep(values)
% Smallest positive spacing of a sample axis (NaN when undefined).
d = diff(unique(values(isfinite(values)))); d = d(d > 1e-9);
if isempty(d), step = NaN; else, step = min(d); end
end

function writeTable(T, fp)
if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
end

%% ========================================================================== source readers
function out = readSource(fp, textFormat, textTbl)
%READSOURCE Read any supported pattern/coverage file into {rawTbl, blocks, freqs, meta}.
%   blocks{k} are canonical tables Theta/Phi/Re_Eth/Im_Eth/Re_Eph/Im_Eph (or Theta/Phi/gain columns).
if nargin < 3, textTbl = table(); end
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
switch ext
    case {'XLSX', 'XLS'},        out = readExcel(fp);
    case {'CSV', 'TXT', 'DAT'},  out = readText(fp, string(textFormat), textTbl);
    case 'CUT',                  out = readCut(fp);
    case {'UAN', 'FZ', 'OUT', 'FFS', 'FFE', 'FFD'}, out = readColumns(fp, ext);
    otherwise, error('APAT:io:Unsupported', 'Unsupported file format: %s', ext);
end
defaults = struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false);
for f = fieldnames(defaults)', if ~isfield(out.meta, f{1}), out.meta.(f{1}) = defaults.(f{1}); end, end
if ~isfield(out, 'textTbl'), out.textTbl = table(); end
end

function out = sourceStruct(raw, blocks, freqs, meta)
out = struct('rawTbl', raw, 'blocks', {blocks}, 'freqs', freqs, 'meta', meta);
end

function T = fieldTable(theta, phi, Eth, Eph)
T = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), ...
    'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function E = polar2c(magDB, phaseDeg), E = 10 .^ (magDB / 20) .* exp(1i * deg2rad(phaseDeg)); end

function [Eth, Eph] = circ2lin(Ercp, Elcp)
Eth = (Ercp + Elcp) / sqrt(2); Eph = (Ercp - Elcp) / (1i * sqrt(2));
end

function out = readText(fp, textFormat, T)
% Generic CSV/TXT/DAT: coverage results, gain-only pattern, or a six-column E-field layout.
if isempty(T)
    opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    opts = setvartype(opts, 'double'); opts = setvaropts(opts, 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
    T = rmmissing(readtable(fp, opts));
end
n = width(T); assert(n >= 2 && ~isempty(T), 'APAT:io:InvalidFormat', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHeaders = ~all(startsWith(names, "Var"));
c1 = T{:, 1}; c2 = T{:, 2};
coverageHeader = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
if (textFormat == "gain" || n < 6 || coverageHeader) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:n - 1))]; end
    out = sourceStruct(T, {}, NaN, struct('source', 'Coverage results', 'isCoverage', true)); out.textTbl = T; return
end
raw = T;
if textFormat == "gain"                                    % the column with the larger span is phi
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    T = movevars(T, 'Theta', 'Before', 1); if ~hasHeaders, raw = T; end
    out = sourceStruct(raw, {T}, NaN, struct('source', 'Generic text (gain)', 'isGainOnly', true)); out.textTbl = raw; return
end
assert(n >= 6, 'APAT:io:TextEFieldColumns', 'The selected generic E-field format requires six numeric columns.');
V = T{:, 3:6}; layout = "";
if endsWith(textFormat, "magphase")                        % detect grouped (m m p p) vs interleaved (m p m p) layout
    isPhase = max(abs(V), [], 1, 'omitnan') > 100;
    if isPhase(2) && ~isPhase(3), mag = V(:, [1 3]); ph = V(:, [2 4]); layout = ", interleaved"; else, mag = V(:, 1:2); ph = V(:, 3:4); layout = ", grouped"; end
    C1 = polar2c(mag(:, 1), ph(:, 1)); C2 = polar2c(mag(:, 2), ph(:, 2));
else
    C1 = complex(V(:, 1), V(:, 2)); C2 = complex(V(:, 3), V(:, 4));
end
if startsWith(textFormat, "linear"), Eth = C1; Eph = C2;
elseif startsWith(textFormat, "rcp"), [Eth, Eph] = circ2lin(C1, C2);
else, [Eth, Eph] = circ2lin(C2, C1);
end
out = sourceStruct(raw, {fieldTable(c1, c2, Eth, Eph)}, NaN, struct('source', sprintf('Generic text (%s%s)', textFormat, layout)));
out.textTbl = raw;
end

function out = readCut(fp)
% TICRA/GRASP *.cut: repeated blocks of [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data].
L = readlines(fp); L(strlength(strtrim(L)) == 0) = [];
th = {}; ph = {}; D = {}; k = 1; icomp = 1; icut = 1;
while k < numel(L)
    p = sscanf(L(k + 1), '%f'); assert(numel(p) >= 7, 'APAT:io:Cut', 'Could not parse a GRASP cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6);
    rows = reshape(sscanf(strjoin(L(k + 2:k + 1 + n), ' '), '%f'), 2 * p(7), []).';
    th{end + 1} = p(1) + (0:n - 1)' * p(2); ph{end + 1} = repmat(p(4), n, 1); D{end + 1} = rows(:, 1:4); %#ok<AGROW>
    k = k + 2 + n;
end
th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:});
if icut == 2, [th, ph] = deal(ph, th); end                 % ICUT=2: phi swept, theta constant
neg = th < 0; ph(neg) = ph(neg) + 180; th(neg) = -th(neg);
if isscalar(unique(ph))                                    % single cut -> body of revolution
    m = numel(th); ph = repelem((0:10:350)', m); th = repmat(th, 36, 1); D = repmat(D, 36, 1);
end
C1 = complex(D(:, 1), D(:, 2)); C2 = complex(D(:, 3), D(:, 4));
if icomp == 2, [Eth, Eph] = circ2lin(C1, C2); rawNames = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'};
else, Eth = C1; Eph = C2; rawNames = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; end
raw = array2table([th, ph, D], 'VariableNames', [{'Theta', 'Phi'}, rawNames]);
out = sourceStruct(raw, {fieldTable(th, ph, Eth, Eph)}, NaN, struct('source', 'TICRA/GRASP CUT'));
end

function out = readColumns(fp, ext)
% Column-oriented far-field exports (XGTD, GRASP, CST, FEKO, HFSS).
[nHdr, ffd] = findHeader(fp);
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = readmatrix(fp, setvartype(opts, 'double')); M = M(~all(isnan(M), 2), 1:min(end, 6));
switch ext
    case {'UAN', 'FZ'}   % Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
        raw = array2table(M, 'VariableNames', {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'});
        blk = fieldTable(M(:, 1), M(:, 2), polar2c(M(:, 3), M(:, 5)), polar2c(M(:, 4), M(:, 6))); src = ['XGTD ' ext];
    case 'OUT'           % Theta Phi Re/Im POL1(RHCP) Re/Im POL2(LHCP)
        raw = array2table(M, 'VariableNames', {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'});
        [Eth, Eph] = circ2lin(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)));
        blk = fieldTable(M(:, 1), M(:, 2), Eth, Eph); src = 'TICRA/GRASP OUT';
    case 'FFS'           % Phi Theta Re/Im E_TH Re/Im E_PH
        raw = array2table(M, 'VariableNames', {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
        blk = fieldTable(M(:, 2), M(:, 1), complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6))); src = 'CST FFS';
    case 'FFE'           % Theta Phi Re/Im E_TH Re/Im E_PH (extra columns ignored)
        raw = array2table(M, 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
        blk = fieldTable(M(:, 1), M(:, 2), complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6))); src = 'FEKO FFE';
    case 'FFD'           % header-defined grid; one Re/Im E_TH Re/Im E_PH block per frequency
        assert(ffd.isFFD, 'APAT:io:FFD', 'FFD header (theta/phi ranges) not found.');
        th = repelem(ffd.theta, numel(ffd.phi)); ph = repmat(ffd.phi, numel(ffd.theta), 1);
        sep = isnan(M(:, 1)); freqs = [ffd.freq, M(sep & ~isnan(M(:, 2)), 2).'];
        rows = M(~sep, 1:4); n = numel(th);
        assert(mod(size(rows, 1), n) == 0, 'APAT:io:FFD', 'FFD row count does not match the theta/phi grid.');
        nb = size(rows, 1) / n; freqs(end + 1:nb) = NaN; freqs = freqs(1:nb);
        blocks = arrayfun(@(b) fieldTable(th, ph, complex(rows((b-1)*n+1:b*n, 1), rows((b-1)*n+1:b*n, 2)), complex(rows((b-1)*n+1:b*n, 3), rows((b-1)*n+1:b*n, 4))), 1:nb, 'UniformOutput', false);
        out = sourceStruct(blocks{1}, blocks, freqs, struct('source', 'HFSS FFD', 'isDep', nb > 1 || any(isfinite(freqs)))); return
end
out = sourceStruct(raw, {blk}, NaN, struct('source', src));
end

function [nHdr, ffd] = findHeader(fp)
% Number of leading non-data lines; also parses the HFSS FFD header (two numeric triples + optional frequency line).
L = readlines(fp); nonEmpty = find(strlength(strtrim(L)) > 0, 3); ffd = struct('isFFD', false);
trip = arrayfun(@(k) sscanf(char(L(k)), '%f').', nonEmpty(1:min(2, end)), 'UniformOutput', false);
if numel(trip) == 2 && all(cellfun(@numel, trip) == 3)
    a = trip{1}; b = trip{2}; nHdr = nonEmpty(2);
    ffd = struct('isFFD', true, 'theta', linspace(a(1), a(2), round(a(3))).', 'phi', linspace(b(1), b(2), round(b(3))).', 'freq', []);
    if numel(nonEmpty) == 3
        tok = regexp(char(strtrim(L(nonEmpty(3)))), '^frequenc(?:y|ies)\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok)
            nHdr = nonEmpty(3); f = sscanf(char(tok{1}), '%f'); if numel(f) > 1, ffd.freq = f(:).'; end
        end
    end
    return
end
nHdr = 0;
for k = 1:min(numel(L), 1000)                              % first line with at least four numeric fields
    if numel(sscanf(char(L(k)), '%f')) >= 4, return; end
    nHdr = k;
end
end

function out = readExcel(fp)
% Excel matrix workbooks: fixed component sheets (Etheta/Ephi and/or RHCP/LHCP gain+phase matrices) + a summary sheet.
sheets = string(sheetnames(fp));
lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
cir = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"];
hasL = all(ismember(lower(lin), lower(sheets))); hasC = all(ismember(lower(cir), lower(sheets)));
assert(hasL || hasC, 'APAT:io:ExcelFormat', 'Unsupported workbook: expected Etheta/Ephi and/or RHCP/LHCP component sheets.');
req = [lin(repmat(hasL, 1, 4)), cir(repmat(hasC, 1, 4))]; M = struct(); grid = {};
for s = req
    [th, ph, D] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, s), 1)));
    if isempty(grid), grid = {th, ph}; else, assert(isequal(grid, {th, ph}), 'APAT:io:ExcelGrid', 'All component sheets must share the same theta/phi grid.'); end
    M.(char(s)) = D;
end
if hasL, Eth = polar2c(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = polar2c(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees); src = 'Excel Matrix (Eth/Eph)';
else, [Eth, Eph] = circ2lin(polar2c(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), polar2c(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees)); src = 'Excel Matrix (RHCP/LHCP)'; end
if hasL && hasC, src = 'Excel Matrix (Eth/Eph + RHCP/LHCP)'; end
[PH, TH] = meshgrid(grid{2}, grid{1}); blk = fieldTable(TH, PH, Eth, Eph);
raw = blk(:, 1:2); for s = req, raw.(char(s)) = reshape(M.(char(s)), [], 1); end
summary = readSummary(fp, sheets(1)); freq = NaN;
if isfield(summary, 'frequencyMHz') && isfinite(summary.frequencyMHz), freq = summary.frequencyMHz * 1e6; end
out = sourceStruct(raw, {blk}, freq, struct('source', src, 'summary', summary));
end

function [theta, phi, D] = readMatrixSheet(fp, sheet)
% C3-origin matrix: phi along row 2 (from column C), theta down column B (from row 3). readcell keeps worksheet coordinates.
C = readcell(fp, 'Sheet', char(sheet));
assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'APAT:io:ExcelSheet', 'Sheet "%s" does not contain a C3-origin matrix.', sheet);
num = @(cells) cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), cells);
phiMask = num(C(2, 3:end)); thetaMask = num(C(3:end, 2));
nPhi = find([~phiMask, true], 1) - 1; nTheta = find([~thetaMask; true], 1) - 1;   % contiguous prefix only
assert(nPhi > 0 && nTheta > 0 && ~any(phiMask(nPhi + 1:end)) && ~any(thetaMask(nTheta + 1:end)), 'APAT:io:ExcelAxis', 'Sheet "%s" has a gap in its theta/phi axis.', sheet);
phi = cellfun(@double, C(2, 3:2 + nPhi)); theta = cellfun(@double, C(3:2 + nTheta, 2)); phi = phi(:); theta = theta(:);
cells = C(3:2 + nTheta, 3:2 + nPhi);
assert(all(num(cells), 'all'), 'APAT:io:ExcelSheet', 'Sheet "%s" contains non-numeric or missing matrix samples.', sheet);
D = cellfun(@double, cells);
assert(all(diff(theta) > 0) && all(diff(phi) > 0) && theta(1) >= -1e-9 && theta(end) <= 180 + 1e-9 && phi(1) >= -1e-9 && phi(end) < 360, ...
    'APAT:io:ExcelAxis', 'Sheet "%s" must have increasing axes within theta 0..180 and phi 0..360.', sheet);
end

function meta = readSummary(fp, sheet)
% Label/value pairs of the summary sheet (label in column B, first non-empty value in C..E), keyed by a valid name.
meta = struct();
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
for r = 1:size(C, 1)
    label = C{r, 2}; if ~(ischar(label) || isstring(label)) || strlength(strtrim(label)) == 0, continue; end
    vals = C(r, 3:min(5, end)); vals = vals(~cellfun(@(v) isempty(v) || (isa(v, 'missing')), vals));
    if isempty(vals), continue; end
    meta.(matlab.lang.makeValidName(lower(char(label)))) = vals{1};
end
key = fieldnames(meta); k = find(contains(key, 'freq') & contains(key, 'mhz') & ~contains(key, 'lowest') & ~contains(key, 'highest'), 1);
if ~isempty(k) && isnumeric(meta.(key{k})), meta.frequencyMHz = double(meta.(key{k})); end
end

%% ========================================================================== numerical services (pure functions)
function T = normalizePattern(T)
%NORMALIZEPATTERN Canonical sphere: Theta in [0,180], Phi in [0,360] with a closed phi seam, unique directions.
th = T.Theta; ph = T.Phi;
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, th = 90 - th;                 % elevation convention
    else, neg = th < 0; th(neg) = -th(neg); ph(neg) = ph(neg) + 180; end
end
th = mod(th, 360); over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;
T.Theta = th; T.Phi = mod(ph, 360);
num = varfun(@isnumeric, T, 'OutputFormat', 'uniform'); T{:, num} = round(T{:, num}, 5);   % kill seam round-off once
T.Phi = mod(T.Phi, 360);
[~, iu] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(iu, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function R = resampleCanonical(S, step)
%RESAMPLECANONICAL Resample primitive source data onto a step° canonical grid (0..180 x 0..360).
%   Regular grids use periodic interp2; irregular samples use scatteredInterpolant. Gain-only columns are
%   interpolated as linear power. E-field Re/Im columns are interpolated directly (never gain/AR/PLF).
th = S.Theta; ph = mod(S.Phi, 360); keep = isfinite(th) & isfinite(ph) & abs(S.Phi - 360) > 1e-9;
S = S(keep, :); th = th(keep); ph = ph(keep);
[~, iu] = unique([th, ph], 'rows'); S = S(iu, :); th = th(iu); ph = ph(iu);
ud = S.Properties.UserData; gainOnly = isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly;
[QP, QT] = meshgrid(unique([0:step:360, 360]), 0:step:180);
R = table(QT(:), QP(:), 'VariableNames', {'Theta', 'Phi'});
uT = unique(th); uP = unique(ph); regular = numel(uT) * numel(uP) == numel(th);
if regular
    [~, it] = ismember(th, uT); [~, ip] = ismember(ph, uP); idx = sub2ind([numel(uT), numel(uP)], it, ip);
    [PG, TG] = meshgrid([uP; uP(1) + 360], uT);                          % periodic closure column
end
for name = string(S.Properties.VariableNames(3:end))
    v = double(S.(char(name))); lin = gainOnly && isGainDB(name); if lin, v = 10 .^ (v / 10); end
    if regular
        Z = nan(numel(uT), numel(uP) + 1); Z(idx) = v; Z(:, end) = Z(:, 1);
        q = interp2(PG, TG, Z, QP, QT, 'linear', NaN); miss = ~isfinite(q);
        if any(miss(:)), qn = interp2(PG, TG, Z, QP, QT, 'nearest', NaN); q(miss) = qn(miss); end
    else
        F = scatteredInterpolant(ph, th, v, 'linear', 'nearest'); q = F(QP, QT);
    end
    if lin, q = 10 * log10(max(q, realmin)); end
    R.(char(name)) = q(:);
end
R.Properties.UserData = ud;
end

function tf = isGainDB(name)
key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', '');
tf = contains(key, 'gain') || contains(key, 'directivity') || contains(key, 'eirp') || endsWith(key, 'db');
end

function [P, info] = calcPattern(S, prm, pct, excess)
%CALCPATTERN Processed quantities from a canonical block (gain-only: loss offset; E-field: full derivation).
info = struct('POB', NaN, 'POBth', NaN, 'POBph', NaN, 'pol', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]), 'peak', struct());
ud = S.Properties.UserData;
if isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + prm.GainLoss_dB; end
    info.peak = resolvePeak(P{:, 3}, pct, excess); [info.POB, k] = deal(info.peak.value, info.peak.index);
    info.POBth = P.Theta(k); info.POBph = P.Phi(k); return
end
Eth = complex(S.Re_Eth, S.Im_Eth) * prm.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph) * prm.FieldScale;
Ercp = (Eth + 1i * Eph) / sqrt(2); Elcp = (Eth - 1i * Eph) / sqrt(2);
mTh = abs(Eth); mPh = abs(Eph); mR = abs(Ercp); mL = abs(Elcp);
total = 10 * log10(max(mTh.^2 + mPh.^2, eps));
info.peak = resolvePeak(total, pct, excess); [info.POB, k] = deal(info.peak.value, info.peak.index);
info.POBth = S.Theta(k); info.POBph = S.Phi(k);

% Dominant polarization: mean power of the four components drives co/cross order, label and Auto-Rx sense.
pw = [mean(mTh.^2, 'omitnan'), mean(mPh.^2, 'omitnan'), mean(mR.^2, 'omitnan'), mean(mL.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif pw(1) >= pw(2), info.pol = 'Linear (Vertical)'; else, info.pol = 'Linear (Horizontal)'; end

% Signed axial ratio (+ right-hand, - left-hand); equal circular components are the linear limit (-100 dB floor).
delta = mR - mL; sense = sign(delta); sense(~isfinite(delta)) = 0;
ar = (mR + mL) ./ max(abs(delta), eps);
signedAR = min(20 * log10(ar), 250) .* sense; signedAR(isfinite(delta) & abs(delta) <= eps * max(mR + mL, 1)) = -100;

% Polarization loss factor against the incident wave (Auto follows the dominant circular sense).
if prm.RxMode == "Auto", ws = 2 * (info.pairs.Circular(1) == "E_RCP") - 1; elseif prm.RxMode == "RHCP", ws = 1; else, ws = -1; end
ra = ar .* sense; ra(sense == 0) = 1e12; rw = ws * 10 ^ (prm.RxAR_dB / 20);
plf = 0.5 + (4 * ra * rw - (ra.^2 - 1) * (rw^2 - 1)) ./ (2 * (ra.^2 + 1) * (rw^2 + 1));
plfDB = 10 * log10(min(max(plf, eps), 1));

eirpDB = prm.Pt_dBW + total; eirpW = 10 .^ (eirpDB / 10);
dB = @(m) 20 * log10(max(m, eps)); deg = @(E) rad2deg(angle(E));
P = table(S.Theta, S.Phi, total, signedAR, dB(mR), dB(mL), plfDB, total + plfDB, dB(mTh), dB(mPh), deg(Eth), deg(Eph), deg(Ercp), deg(Elcp), ...
    eirpDB, eirpW / (4 * pi * prm.R_m^2), sqrt(30 * eirpW) / prm.R_m, 'VariableNames', ...
    {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', 'PLF_dB', 'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', ...
     'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
P.Properties.UserData = ud;
end

function k = calcOrientation(theta, phi, gainDB, omega, ax6, pct, excess)
%CALCORIENTATION Principal axis whose 45° cone carries the most (outlier-free) radiated energy.
pk = resolvePeak(gainDB, pct, excess); g = gainDB; if pk.wasAdjusted, g(pk.outlierMask) = NaN; end
w = 10 .^ ((g - pk.value) / 10) .* omega; w(~isfinite(w)) = 0;
A = [sind(ax6.theta(:)) .* cosd(ax6.phi(:)), sind(ax6.theta(:)) .* sind(ax6.phi(:)), cosd(ax6.theta(:))];
V = [sind(theta) .* cosd(phi), sind(theta) .* sind(phi), cosd(theta)];
[~, k] = max(w.' * double(V * A.' >= cosd(45)));
end

function m = calcMetrics(T, theta, omega, gcol, ax6, k, pct, excess)
%CALCMETRICS Scalar antenna metrics of the gain column (THETA is physical polar theta of every row).
g = T.(gcol); ph = T.Phi; pk = resolvePeak(g, pct, excess); i = pk.index;
gm = g; if pk.wasAdjusted, gm(pk.outlierMask) = NaN; end
P = sum(10 .^ (gm / 10) .* omega, 'omitnan');
eff = 100 * P / (4 * pi); if eff < 0 || eff > 100, eff = NaN; end
[~, back] = min(cosd(theta) .* cosd(theta(i)) + sind(theta) .* sind(theta(i)) .* cosd(ph - ph(i)));
ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(i); end
if ax6.theta(k) == 90, hType = "Phi"; else, hType = "Theta"; end            % H-plane orthogonal to the E-plane
[eRows, eAng] = calcCutGeometry(theta, theta, ph, "Theta", ax6.phi(k));
[hRows, hAng] = calcCutGeometry(theta, theta, ph, hType, 90);
m = struct('PeakGain_dB', pk.value, 'PeakTheta_deg', theta(i), 'PeakPhi_deg', mod(ph(i), 360), ...
    'HPBW_EPlane_deg', calcHPBW(eAng, g(eRows)), 'HPBW_HPlane_deg', calcHPBW(hAng, g(hRows)), ...
    'FrontBack_dB', pk.value - g(back), 'PeakDirectivity_dB', 10 * log10(max(4 * pi * 10^(pk.value / 10) / max(P, eps), eps)), ...
    'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', ar);
end

function [rows, ang, fixed, sym, snapped] = calcCutGeometry(thetaDisp, thetaPhys, phi, type, req)
%CALCCUTGEOMETRY Rows of one full-circle cut, snapped to the nearest sampled plane, with unique angles.
%   Phi cut  : fixed display theta, angle = phi (0..360).
%   Theta cut: fixed phi, angle = physical theta on the primary half (0..180) and 360 - theta on the opposite half.
if type == "Phi"
    vals = unique(thetaDisp); [dist, k] = min(abs(vals - req)); fixed = vals(k);
    rows = find(abs(thetaDisp - fixed) < 1e-9); ang = phi(rows); sym = 'θ';
else
    w = mod(phi, 360); vals = unique(w);
    [dist, k] = min(abs(mod(vals - req + 180, 360) - 180)); fixed = vals(k);
    [~, ko] = min(abs(mod(vals - fixed, 360) - 180));
    r1 = find(abs(w - fixed) < 1e-9); r2 = find(abs(w - vals(ko)) < 1e-9 & abs(thetaPhys - 180) > 1e-9);
    rows = [r1; r2]; ang = [thetaPhys(r1); 360 - thetaPhys(r2)]; sym = 'φ';
end
[ang, iu] = unique(ang); rows = rows(iu); snapped = dist > 1e-9;
end

function [bw, lo, hi] = calcHPBW(ang, g, peak, peakAng)
%CALCHPBW Half-power beamwidth of a circular cut by linear interpolation around the peak.
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(g); ang = ang(ok); g = g(ok);
if numel(g) < 3, return; end
if nargin < 3 || isempty(peak), [peak, i] = max(g); peakAng = ang(i); end
[rel, o] = sort(mod(ang - peakAng + 180, 360) - 180); g = g(o); half = peak - 3;
L = find(rel < 0 & g <= half, 1, 'last'); Rr = find(rel > 0 & g <= half, 1, 'first');
if isempty(L) || isempty(Rr) || L + 1 > numel(g) || Rr < 2, return; end
xing = @(a, b) rel(a) + (rel(b) - rel(a)) * (half - g(a)) / (g(b) - g(a));
if g(L + 1) == g(L) || g(Rr - 1) == g(Rr), return; end
lo = peakAng + xing(L, L + 1); hi = peakAng + xing(Rr, Rr - 1); bw = hi - lo;
end

function cov = coverageCCDF(gain, mask, thr, omega)
%COVERAGECCDF Coverage(T) [%] = 100 * sum(Omega_i * [G_i > T]) / Omega_region, evaluated for all T at once.
%   Sorted cumulative weights make this O(N log N) instead of an N x K indicator matrix.
v = mask(:) & isfinite(gain(:)) & isfinite(omega(:)) & omega(:) > 0;
g = gain(v); w = omega(v); total = sum(w); cov = zeros(size(thr));
if total <= 0, return; end
[gu, ~, grp] = unique(g); cw = cumsum(accumarray(grp, w));                % cw(i) = weight with gain <= gu(i)
n = discretize(thr(:), [gu; Inf]); below = zeros(size(n)); below(~isnan(n)) = cw(n(~isnan(n)));
cov = reshape(100 * (total - below) / total, size(thr));
end

function info = resolvePeak(values, pct, excess)
%RESOLVEPEAK Authoritative peak: the raw maximum unless it exceeds the P(pct) percentile by more than EXCESS dB,
%   in which case the highest sample at or below the percentile is used (isolated-spike protection).
info = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(values)), 'wasAdjusted', false);
finite = isfinite(values); if ~any(finite), return; end
[info.rawValue, info.rawIndex] = max(values, [], 'omitnan'); p = percentile(values(finite), pct);
info.value = info.rawValue; info.index = info.rawIndex;
if info.rawValue <= p + excess, return; end
info.outlierMask = finite & values > p; candidates = values; candidates(~(finite & ~info.outlierMask)) = -Inf;
if any(isfinite(candidates)), [info.value, info.index] = max(candidates); info.wasAdjusted = true; end
end

function v = percentile(x, p)
% Toolbox-free equivalent of prctile(x, p): sorted samples at 100*(i-0.5)/n with linear interpolation.
x = sort(x(:)); n = numel(x); q = p / 100 * n + 0.5;
if q <= 1, v = x(1); elseif q >= n, v = x(n); else, i = floor(q); v = x(i) + (q - i) * (x(i + 1) - x(i)); end
end

function b = peakWindow(values, pct, excess)
%PEAKWINDOW 50 dB display/threshold window ending at the peak rounded up to 5 dB.
v = values(isfinite(values)); if isempty(v), b = [-40 10]; return; end
hi = min(100, max(-200, ceil(resolvePeak(v, pct, excess).value / 5) * 5)); b = [hi - 50, hi];
end

function dOmega = solidWeights(theta, phi)
%SOLIDWEIGHTS Exact solid angle of each uniform theta x phi cell; the duplicated phi seam gets zero weight.
ts = gridStep(theta); ps = gridStep(mod(phi, 360));
if ~isfinite(ts), ts = 180; end, if ~isfinite(ps), ps = 360; end
dOmega = (cosd(max(theta - ts / 2, 0)) - cosd(min(theta + ts / 2, 180))) * deg2rad(ps);
seam = 360; if any(phi < 0), seam = 180; end
dOmega(abs(phi - seam) < 1e-9) = 0;
end