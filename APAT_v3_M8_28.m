classdef APAT_v3_M8_28 < matlab.apps.AppBase %1416-lines
% APAT v3 M8 — Antenna Pattern Analyzer Tool (single-file App Designer class).
%
% Architecture (M8):
%   readSource  -> normalizePattern -> calcPattern -> [resampleCanonical] -> viewTbl  (canonical, physical θ/φ)
%   viewTbl     -> gridData / cutData / calcMetrics / coverageCCDF                       (all physics on canonical data)
%   display     -> displayAngles (θ-span / φ-span switches) applied only at render/table time
%
% Design rules: one authoritative table, one grid cache, one annotation mechanism (tags), one range
% policy, tiny declarative UI builder, no hidden toolbox dependencies, no duplicate helpers.

    properties (Constant, Access = private)
        Version    = 'APAT v3 M8'
        Axes6      = struct('labels', {{'+Z','-Z','+X','-X','+Y','-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        CompNames  = ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","AR_dB","Gain_PolCorrected_dB"]
        CompLabels = ["Total Gain","Etheta Gain","Ephi Gain","RHCP Gain","LHCP Gain","Axial Ratio","Polarized Gain"]
        HiddenCols = {'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'}
        PeakPct    = 99.99      % peak policy: percentile level
        PeakExcess = 6          % peak policy: allowed excess above the percentile (dB)
        RangeLim   = [-250 100] % absolute dB bounds of every range control
        OneDeg     = 'STEP: 1°'
    end

    properties (Access = private)
        ui struct = struct()            % every UI handle (built by buildUI)
        full                            % full-pattern tab specs: name, tab, axes, slider, minSp, maxSp, cbar
        styles cell = {}                % dropdown filter styles {on, off}
        cmapAR double                   % signed axial-ratio colormap
        % source & pipeline
        src struct = struct()           % source adapter: rawTbl, blocks, freqs, userData
        filePath char = ''
        fileName char = ''
        baseName char = ''
        folderPath char = ''
        stdTbl table                    % canonical source (normalized fields / gain)
        patTbl table                    % processed at native step
        viewTbl table                   % processed at the selected step (canonical θ 0..180, φ 0..360 closed seam)
        dispTbl table                   % viewTbl with display angle conventions (Results table / export)
        solidAngle double = []          % dΩ per viewTbl row
        gridCache struct = struct()     % geometry + per-component grids for the current view/display
        lastCut = []                    % last extracted cut (plot, overlay, export)
        % derived state
        peak struct = struct('wasAdjusted', false)   % resolved peak of the selected component
        POB double = NaN                % peak value (dB)
        POBth double = NaN              % peak physical theta (deg)
        POBph double = NaN              % peak phi 0..360 (deg)
        boresight double = 1            % index into Axes6
        metrics struct = struct()       % total-gain figures of merit
        polLabel char = 'n/a'
        polPairs struct = struct('Linear', ["E_TH","E_PH"], 'Circular', ["E_RCP","E_LCP"])   % co/cross ordering
        gainLim double = [-40 10]       % authoritative non-AR colour scale
        fullLim double = [-40 10]       % currently applied full-pattern scale (gainLim or the fixed AR scale)
        cutLim double = [-40 10]        % cut-plot scale
        polarNorm double = 1            % 3D-polar radius normalization shared with the cut overlay
        outCols logical = logical([])   % Results-table column filter
        defaults struct = struct()      % startup parameter values
        statusTimer = []                % one shared transient-status timer
        covRunID double = 0             % coverage job counter
        covPresetKey char = ''          % last automatic threshold-preset key
        covXInit logical = false        % coverage X-axis baseline established
        isClosing logical = false
    end

    %% ------------------------------------------------------------------ lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_28
            app.buildUI(); registerApp(app, app.ui.fig); runStartupFcn(app, @startup);
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true;
            t = app.statusTimer; if ~isempty(t) && isvalid(t), stop(t); delete(t); end
            if isfield(app.ui, 'fig') && isvalid(app.ui.fig), delete(app.ui.fig); end
        end

        function report = runSelfTest(app)
            %RUNSELFTEST Deterministic numerical checks of the math kernel (no files, no UI state).
            [P, T] = meshgrid((0:30:330).', (0:30:180).');
            tbl = table(T(:), P(:), 10*cosd(T(:)).^2, 'VariableNames', {'Theta','Phi','E_Total_dB'});
            w = solidWeights(tbl.Theta, tbl.Phi); r.solidAngleError = abs(sum(w) - 4*pi);
            [pk, ax] = calcOrientation(tbl, w, 'E_Total_dB', app.Axes6, app.PeakPct, app.PeakExcess);
            r.passOrientation = isfinite(pk.value) && ax == 1;
            r.passDisplayRange = isequal(displayRange([3.2; -100], app.PeakPct, app.PeakExcess), [-45 5]);
            spike = repmat(0.02, 100000, 1); spike(7) = 10.02; sp = resolvePeak(spike, app.PeakPct, app.PeakExcess);
            r.passIsolatedSpike = sp.wasAdjusted && abs(sp.value - 0.02) < 1e-12 && sp.rawIndex == 7;
            [P2, T2] = meshgrid((0:2:358).', (0:2:180).'); f = @(t, p) 12*cosd(t).^2 - 0.5*sind(p).^2;
            R = resampleCanonical(table(T2(:), P2(:), f(T2(:), P2(:)), 'VariableNames', {'Theta','Phi','X'}), 1);
            native = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0 & R.Phi < 360;
            r.resampleError = max(abs(R.X(native) - f(R.Theta(native), R.Phi(native))));
            r.passResampling = height(R) == 181*361 && r.resampleError < 1e-9;
            ang = (-180:180).'; g = 20*log10(max(cosd(ang), 1e-6)); bw = calcHPBW(ang, g);
            r.passHPBW = abs(bw - 90) < 0.2;
            r.passCoverage = abs(coverageCCDF(tbl.E_Total_dB, true(height(tbl), 1), -100, w) - 100) < 1e-9;
            N = normalizePattern(table([-90; 0; 90], [10; 20; 30], [1; 2; 3], 'VariableNames', {'Theta','Phi','G'}));
            r.passNormalize = isequal(sort(N.Theta), [0; 90; 180]);
            r.passARSemantics = all(arrayfun(@(s) app.isAR(s), ["AR","AR_dB","AR dB","Axial Ratio","Axial_Ratio"]));
            names = fieldnames(r); passes = names(startsWith(names, 'pass'));
            r.pass = r.solidAngleError < 1e-9 && all(cellfun(@(n) r.(n), passes));
            report = r;
            if ~r.pass, error('APAT:selfTest', 'Self-test failed: %s', strjoin(passes(~cellfun(@(n) r.(n), passes)), ', ')); end
        end
    end

    %% ------------------------------------------------------------------ UI construction
    methods (Access = private)
        function h = add(~, ctor, parent, row, col, varargin)
            % Declarative widget factory: construct, set name/value pairs (in order), place in the grid.
            h = ctor(parent); if ~isempty(varargin), set(h, varargin{:}); end
            h.Layout.Row = row; h.Layout.Column = col;
        end
        function h = lbl(app, parent, text, row, col, varargin)
            h = app.add(@uilabel, parent, row, col, 'Text', text, 'HorizontalAlignment', 'right', varargin{:});
        end
        function h = btn(app, parent, text, row, col, fcn, varargin)
            h = app.add(@uibutton, parent, row, col, 'Text', text, 'ButtonPushedFcn', fcn, varargin{:});
        end
        function h = spin(app, parent, row, col, value, varargin)
            h = app.add(@uispinner, parent, row, col, 'Value', value, varargin{:});
        end
        function cb = guard(app, f, title)
            % Wrap a callback so that any error is reported in a dialog instead of the command window.
            cb = @(~, ~) app.run(f, title);
        end
        function run(app, f, title)
            try, f(); catch ME, if ~app.isClosing, app.fail(ME, title); end, end
        end
        function fail(app, ME, title)
            loc = ''; if ~isempty(ME.stack), loc = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.ui.fig, [ME.message loc], title, 'Icon', 'error');
        end
        function dd = formatDropdown(app, parent, row, col, fcn)
            dd = app.add(@uidropdown, parent, row, col, 'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', ...
                '3: Etheta/Ephi — real, imaginary', '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
                '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                'ItemsData', {'gain','linear_magphase','linear_reim','rcp_lcp_magphase','lcp_rcp_magphase','rcp_lcp_reim','lcp_rcp_reim'}, ...
                'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'Visible', 'off', 'ValueChangedFcn', fcn);
        end
        function setupAxes(~, ax, is3D, fig)
            if is3D, ax.Interactions = [rotateInteraction, dataTipInteraction]; else, ax.Interactions = [zoomInteraction, dataTipInteraction]; end
            cm = uicontextmenu(fig); uimenu(cm, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ~) delete(findall(ax, 'Type', 'datatip')));
            ax.ContextMenu = cm; ax.Box = 'on';
        end
        function initCovAxes(~, ax)
            cla(ax); legend(ax, 'off'); hold(ax, 'on'); grid(ax, 'on'); ylim(ax, [0 100]); set(ax, 'Box', 'on', 'Layer', 'top');
            title(ax, 'Coverage vs Threshold'); xlabel(ax, 'Threshold (dB)'); ylabel(ax, 'Coverage (%)');
        end

        function buildUI(app)
            RL = app.RangeLim; cutCb = app.guard(@() app.onCutChanged(), 'Cut Error');
            u.fig = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.Version], 'Visible', 'off', 'Position', [100 100 1136 739], 'WindowState', 'maximized');
            u.fig.CloseRequestFcn = @(~, ~) delete(app);
            root = uigridlayout(u.fig, [1 1]); u.tabs = uitabgroup(root); u.tabs.Layout.Row = 1; u.tabs.Layout.Column = 1;
            u.tabMain = uitab(u.tabs, 'Title', 'Process Pattern 📡'); u.tabCov = uitab(u.tabs, 'Title', 'Compute Coverage 📈');
            G = uigridlayout(u.tabMain, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});

            % ---- Inputs & parameters -------------------------------------------------------------
            pg = uigridlayout(app.add(@uipanel, G, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️'), 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            app.lbl(pg, 'Input Pattern:', 1, 1);
            u.path   = app.add(@(p) uieditfield(p, 'text'), pg, 1, [2 8]);
            u.ffdLbl = app.lbl(pg, 'FFD Freq:', 1, 9, 'Visible', 'off');
            u.ffd    = app.add(@uidropdown, pg, 1, 10, 'Items', {'-'}, 'Visible', 'off', 'ValueChangedFcn', app.guard(@() app.onBlockChanged(), 'FFD Block Error'));
            app.btn(pg, '📂 Load File', 1, [11 12], app.guard(@() app.onLoad(), 'Loading Error'), 'FontSize', 14, 'FontWeight', 'bold');
            app.btn(pg, '⚙️ Process', 1, [13 14], app.guard(@() app.onProcess(), 'Processing Error'));
            app.btn(pg, 'Reset Params', 2, [1 3], app.guard(@() app.resetParams(), 'Reset Error'));
            u.fmtLbl = app.lbl(pg, 'Format:', 2, [4 5], 'Visible', 'off');
            u.fmt    = app.formatDropdown(pg, 2, [6 8], app.guard(@() app.onProcess(), 'Format Error'));
            u.step   = app.add(@uidropdown, pg, 2, [9 10], 'Items', {'STEP'}, 'Visible', 'off', 'ValueChangedFcn', app.guard(@() app.onStepChanged(), 'Step Error'));
            u.export = app.btn(pg, '💾 Export Results', 2, [11 12], app.guard(@() app.exportResults(), 'Export Error'), 'FontWeight', 'bold', 'Visible', 'off');
            u.uan    = app.btn(pg, '💾 Export UAN', 2, [13 14], app.guard(@() app.exportUAN(), 'Export UAN Error'), 'FontWeight', 'bold', 'Visible', 'off');
            u.rxLbl  = app.lbl(pg, 'Rw Sense', 3, 1, 'Visible', 'off');
            u.rx     = app.add(@uidropdown, pg, 3, 2, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Visible', 'off');
            u.rwLbl  = app.lbl(pg, 'Rw (dB)', 3, 3, 'Visible', 'off');
            u.rw     = app.spin(pg, 3, 4, 6, 'Visible', 'off');
            u.lossLbl = app.lbl(pg, 'Loss (−) / Gain (+) dB', 3, 5, 'Visible', 'off');
            u.loss   = app.spin(pg, 3, 6, 0, 'Step', 0.1, 'Visible', 'off');
            u.ptLbl  = app.lbl(pg, 'Tx Pwr (Pt)', 3, 7, 'Visible', 'off');
            u.pt     = app.spin(pg, 3, 8, 0, 'Visible', 'off');
            u.ptUnit = app.add(@uidropdown, pg, 3, 9, 'Items', {'dBW', 'dBm', 'Watts'}, 'Visible', 'off');
            u.distLbl = app.lbl(pg, 'Distance', 3, 10, 'Visible', 'off');
            u.dist   = app.spin(pg, 3, 11, 1, 'Visible', 'off');
            u.distUnit = app.add(@uidropdown, pg, 3, 12, 'Items', {'m', 'km'}, 'Visible', 'off');
            u.toCov  = app.btn(pg, '📉 Coverage ▶', 3, [13 14], app.guard(@() app.sendToCoverage(), 'Coverage Error'), 'FontWeight', 'bold', 'Visible', 'off');

            % ---- Full-pattern tabs (one factory, five tabs) --------------------------------------
            u.fullPanel = app.add(@uipanel, G, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off');
            fg = uigridlayout(u.fullPanel, [1 1]); u.fullTabs = uitabgroup(fg); u.fullTabs.Layout.Row = 1; u.fullTabs.Layout.Column = 1;
            names = {'contour', 'circular', 'sphere', 'polar3D', 'rect3D'};
            titles = {'Contour Plot', 'Circular Contour Plot', '3D Spherical Plot', '3D Polar Plot', '3D Surface Plot'};
            for k = 1:5
                t = uitab(u.fullTabs, 'Title', titles{k});
                g = uigridlayout(t, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
                if k == 2, ax = polaraxes(g); set(ax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise'); else, ax = uiaxes(g); app.setupAxes(ax, k >= 3, u.fig); end
                ax.Layout.Row = [1 3]; ax.Layout.Column = 2;
                s = struct('name', names{k}, 'tab', t, 'axes', ax, 'cbar', [], ...
                    'slider', app.add(@(p) uislider(p, 'range'), g, 2, 1, 'Limits', RL, 'Value', RL, 'Orientation', 'vertical', 'Step', 1), ...
                    'maxSp', app.spin(g, 1, 1, RL(2), 'Limits', RL, 'Step', 5), 'minSp', app.spin(g, 3, 1, RL(1), 'Limits', RL, 'Step', 5));
                s.slider.ValueChangedFcn = @(h, ~) app.setFullRange(h.Value, true);
                s.minSp.ValueChangedFcn  = @(h, ~) app.setFullRange([h.Value, app.fullLim(2)], false);
                s.maxSp.ValueChangedFcn  = @(h, ~) app.setFullRange([app.fullLim(1), h.Value], false);
                app.full = [app.full, s];
            end

            % ---- Cut panel -------------------------------------------------------------------------
            u.cutPanel = app.add(@uipanel, G, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off');
            cg = uigridlayout(u.cutPanel, [1 1]); u.cutTabs = uitabgroup(cg); u.cutTabs.Layout.Row = 1; u.cutTabs.Layout.Column = 1;
            pc = uigridlayout(uitab(u.cutTabs, 'Title', 'Polar Cut Plot'), 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            u.cutMax = app.spin(pc, 1, 1, RL(2), 'Limits', RL, 'Step', 5, 'ValueChangedFcn', @(h, ~) app.setCutRange([app.cutLim(1), h.Value], false));
            u.cutSlider = app.add(@(p) uislider(p, 'range'), pc, [2 3], 1, 'Limits', RL, 'Value', RL, 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(h, ~) app.setCutRange(h.Value, true));
            u.cutMin = app.spin(pc, 4, 1, RL(1), 'Limits', RL, 'Step', 5, 'ValueChangedFcn', @(h, ~) app.setCutRange([h.Value, app.cutLim(2)], false));
            u.paxCut = polaraxes(pc); u.paxCut.Layout.Row = [1 4]; u.paxCut.Layout.Column = 3; set(u.paxCut, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            u.hpbw = app.add(@(p) uibutton(p, 'state'), pc, 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', cutCb);
            u.hpbwLbl = app.add(@uilabel, pc, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            u.eGrid = uigridlayout(pc, [3 1]); u.eGrid.Layout.Row = 3; u.eGrid.Layout.Column = 4;
            u.cbTotal = app.add(@uicheckbox, u.eGrid, 1, 1, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', cutCb);
            u.cbCo    = app.add(@uicheckbox, u.eGrid, 2, 1, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', cutCb);
            u.cbCx    = app.add(@uicheckbox, u.eGrid, 3, 1, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', cutCb);
            app.btn(pc, 'Export Cut', 4, 4, app.guard(@() app.exportCut(), 'Export Cut Error'), 'FontWeight', 'bold');
            rg = uigridlayout(uitab(u.cutTabs, 'Title', 'Rectangular Cut Plot'), [1 1]);
            u.axRect = uiaxes(rg); u.axRect.Layout.Row = 1; u.axRect.Layout.Column = 1; app.setupAxes(u.axRect, false, u.fig);
            xlabel(u.axRect, 'Theta (degree)'); ylabel(u.axRect, 'Magnitude (dB)');

            % ---- Plot control ----------------------------------------------------------------------
            u.ctrl = app.add(@uipanel, G, 2, [13 14], 'Title', 'Plot Control 🎨', 'Visible', 'off');
            kg = uigridlayout(u.ctrl, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', repmat({'fit'}, 1, 15));
            app.lbl(kg, 'Component', 1, 1);
            u.comp = app.add(@uidropdown, kg, 1, 2, 'Items', cellstr(app.CompLabels), 'ItemsData', cellstr(app.CompNames), 'ValueChangedFcn', app.guard(@() app.updateView(true, true), 'Component Error'));
            app.lbl(kg, 'Cut type', 2, 1);
            u.cutType = app.add(@uidropdown, kg, 2, 2, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', app.guard(@() app.onCutTypeChanged(), 'Cut Error'));
            app.lbl(kg, 'Cut value', 3, 1);
            u.cutVal = app.spin(kg, 3, 2, 0, 'Limits', [0 360], 'ValueChangedFcn', cutCb);
            app.lbl(kg, 'Cut fields', 4, 1);
            u.basis = app.add(@uidropdown, kg, 4, 2, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Enable', 'off', 'UserData', true, ...
                'ValueChangedFcn', app.guard(@() app.onBasisChanged(), 'Cut Error'));
            app.lbl(kg, 'Colorbar max', 5, 1);  u.cmax  = app.spin(kg, 5, 2, 10, 'Limits', RL, 'ValueChangedFcn', @(~, ~) app.applyBoth());
            app.lbl(kg, 'Colorbar min', 6, 1);  u.cmin  = app.spin(kg, 6, 2, -40, 'Limits', RL, 'ValueChangedFcn', @(~, ~) app.applyBoth());
            app.lbl(kg, 'Colorbar step', 7, 1); u.cstep = app.spin(kg, 7, 2, 5, 'Limits', [0.1 100], 'ValueChangedFcn', @(~, ~) app.applyFullRange());
            app.lbl(kg, 'Adjust Colorbar', 8, 1);
            app.btn(kg, 'Apply', 8, 2, @(~, ~) app.applyBoth(), 'Tooltip', 'Apply min/max to the full-pattern and cut plots.');
            app.lbl(kg, '3D view', 9, 1);
            u.view3D = app.add(@uidropdown, kg, 9, 2, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'ValueChangedFcn', @(~, ~) app.applyViews());
            u.phiSpan = app.add(@(p) uiswitch(p, 'slider'), kg, 10, [1 2], 'Items', {'φ: 0° to 360°', '−180° to 180°'}, 'ItemsData', {'0-360', 'signed'}, 'ValueChangedFcn', app.guard(@() app.refreshDisplay(), 'View Error'));
            u.thetaSpan = app.add(@(p) uiswitch(p, 'slider'), kg, 11, [1 2], 'Items', {'θ: 0° to 180°', '−90° to 90°'}, 'ItemsData', {'0-180', 'elevation'}, 'ValueChangedFcn', app.guard(@() app.refreshDisplay(), 'View Error'));
            u.plane = app.add(@(p) uiswitch(p, 'slider'), kg, 12, [1 2], 'Items', {'E-Plane cut', 'H-Plane cut'}, 'ValueChangedFcn', app.guard(@() app.selectPlane(), 'Cut Error'));
            u.overlay = app.add(@uicheckbox, kg, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', @(~, ~) app.drawOverlay());
            u.pob = app.add(@uicheckbox, kg, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', @(h, ~) app.setTagVisible('APAT_POB', h.Value));
            u.hpbwTips = app.add(@uicheckbox, kg, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', @(h, ~) app.setTagVisible('APAT_HPBW', h.Value));

            % ---- Data tables & status --------------------------------------------------------------
            u.filter = app.add(@uidropdown, G, 3, [13 14], 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Visible', 'off', 'ValueChangedFcn', @(h, ~) app.onFilterChanged(h));
            u.dataTabs = app.add(@uitabgroup, G, 4, [1 14], 'Visible', 'off');
            u.tblOut  = app.dataTable(u.dataTabs, 'Results 📤'); u.tblIn = app.dataTable(u.dataTabs, 'Input 📥');
            u.tblMeta = app.dataTable(u.dataTabs, 'Metadata 📋'); set(u.tblMeta, 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            u.status = app.add(@uilabel, G, 5, [1 14], 'Interpreter', 'html', 'Text', 'Ready 🚀');

            % ---- Coverage tab ----------------------------------------------------------------------
            C = uigridlayout(u.tabCov, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            q = uigridlayout(app.add(@uipanel, C, 1, [1 5], 'Title', 'Inputs & Parameters 🎛️'), 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'});
            u.covType = app.add(@uibuttongroup, q, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', app.guard(@() app.onCovTypeChanged(), 'Coverage Error'));
            u.btnSph = uiradiobutton(u.covType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            u.btnCon = uiradiobutton(u.covType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            u.orientLbl = app.lbl(q, 'Orientation 🧭:', 3, 1);
            u.orient = app.add(@uidropdown, q, 3, 2, 'Items', [{'Auto'}, app.Axes6.labels], 'ItemsData', 0:6, 'ValueChangedFcn', app.guard(@() app.onOrientationChanged(), 'Coverage Error'));
            u.covCompLbl = app.lbl(q, 'Component:', 4, 1);
            u.covComp = app.add(@uidropdown, q, 4, 2, 'Items', {'E_Total_dB'}, 'Enable', 'off', 'ValueChangedFcn', app.guard(@() app.onCovComponentChanged(), 'Coverage Error'));
            app.lbl(q, 'Antenna Pattern:', 1, 3);
            u.covPath = app.add(@(p) uieditfield(p, 'text'), q, 1, [4 8]);
            app.btn(q, '📂 Load File', 1, 9, app.guard(@() app.onCovLoad(), 'Coverage Load Error'));
            u.covCompute = app.btn(q, '⚙️ Compute Coverage', 1, 10, app.guard(@() app.computeCoverage(), 'Coverage Error'), 'FontWeight', 'bold', 'Enable', 'off');
            app.lbl(q, 'Threshold Min (dB):', 2, 3); u.thrMin = app.spin(q, 2, 4, -40, 'Limits', RL);
            app.lbl(q, 'Threshold Max (dB):', 2, 5); u.thrMax = app.spin(q, 2, 6, 10, 'Limits', RL);
            app.lbl(q, 'Step (dB):', 2, 7);          u.thrStep = app.spin(q, 2, 8, 1, 'Limits', [0.1 100]);
            u.covReset  = app.btn(q, '🔄 Reset', 2, 9, app.guard(@() app.resetCoverage(), 'Coverage Error'), 'Enable', 'off');
            u.covExport = app.btn(q, '💾 Export Results', 2, 10, app.guard(@() app.exportCoverage(), 'Export Error'), 'Enable', 'off');
            u.coneLbls = [app.lbl(q, 'Cone θ₀ (°):', 3, 3), app.lbl(q, 'Cone φ₀ (°):', 3, 5), app.lbl(q, 'Cone Angle α (°):', 3, 7)];
            u.coneTh = app.spin(q, 3, 4, 0, 'Limits', [0 180]); u.conePh = app.spin(q, 3, 6, 0, 'Limits', [0 360]); u.coneAng = app.spin(q, 3, 8, 45, 'Limits', [0 180]);
            u.covClear = app.btn(q, '🧹 Clear DataTips', 3, 9, app.guard(@() app.clearCoverageTips(), 'Coverage Error'), 'Enable', 'off');
            app.btn(q, '📊 To Main ◀', 3, 10, @(~, ~) set(u.tabs, 'SelectedTab', u.tabMain));
            u.qCovLbl = app.lbl(q, 'Coverage @ dB:', 4, 3); u.qCov = app.spin(q, 4, 4, 0, 'ValueDisplayFormat', '%g dB');
            u.qCovBtn = app.btn(q, '⯐ Query Coverage', 4, 5, app.guard(@() app.queryCoverage("cov"), 'Query Error'));
            u.qThrLbl = app.lbl(q, 'Threshold @ %:', 4, 6); u.qThr = app.spin(q, 4, 7, 50, 'Limits', [0 100], 'ValueDisplayFormat', '%g%%');
            u.qThrBtn = app.btn(q, '🔍 Query Threshold', 4, 8, app.guard(@() app.queryCoverage("thr"), 'Query Error'));
            u.covFmtLbl = app.lbl(q, 'Format:', 4, 9, 'Visible', 'off');
            u.covFmt = app.formatDropdown(q, 4, 10, app.guard(@() app.onCovFormatChanged(), 'Coverage Format Error'));
            u.covStatus = app.add(@uilabel, C, 3, [1 5], 'Interpreter', 'html', 'Text', 'Ready 🚀');
            u.covResults = app.add(@uipanel, C, 2, [1 5], 'Title', 'Results', 'Visible', 'off');
            r = uigridlayout(u.covResults, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            u.covAxes = app.add(@uiaxes, r, 1, [2 4], 'Interactions', dataTipInteraction); app.initCovAxes(u.covAxes);
            u.covTree = app.add(@(p) uitree(p, 'checkbox'), r, [1 2], 1, 'SelectionChangedFcn', app.guard(@() app.onCovSelection(), 'Coverage Error'), ...
                'CheckedNodesChangedFcn', app.guard(@() app.refreshCoverage(), 'Coverage Error'));
            u.covRoot = uitreenode(u.covTree, 'Text', 'Coverage Results');
            u.covTable = app.add(@uitable, r, [1 2], 5, 'ColumnWidth', '1x', 'RowName', {});
            u.xMin = app.spin(r, 2, 2, -40, 'Limits', RL, 'ValueChangedFcn', @(h, ~) app.setCovX([h.Value, app.ui.xMax.Value], false));
            u.xSlider = app.add(@(p) uislider(p, 'range'), r, 2, 3, 'Limits', RL, 'Value', [-40 10], 'ValueChangedFcn', @(h, ~) app.setCovX(h.Value, true), 'ValueChangingFcn', @(~, e) app.setCovX(e.Value, true));
            u.xMax = app.spin(r, 2, 4, 10, 'Limits', RL, 'ValueChangedFcn', @(h, ~) app.setCovX([app.ui.xMin.Value, h.Value], false));
            app.ui = u; u.fig.Visible = 'on';
        end

        function tbl = dataTable(~, tabs, title)
            g = uigridlayout(uitab(tabs, 'Title', title), [1 1]);
            tbl = uitable(g, 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnRearrangeable', 'on'); tbl.Layout.Row = 1; tbl.Layout.Column = 1;
        end

        function startup(app)
            app.statusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3);
            app.cmapAR = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256));
            app.styles = {uistyle('FontWeight', 'bold', 'FontColor', 'black', 'BackgroundColor', [0.8 1 0.8]), uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9])};
            app.defaults = app.paramUI(); set([app.ui.status, app.ui.covStatus], 'UserData', 'Ready -- load an antenna pattern file to begin 🚀');
            app.updateCoverageUI();
        end

        function p = paramUI(app, p)
            % Get (nargin==1) or set (nargin==2) the raw link-budget parameter controls.
            u = app.ui; h = {u.loss, u.rx, u.rw, u.pt, u.ptUnit, u.dist, u.distUnit}; f = {'loss', 'rx', 'rw', 'pt', 'ptUnit', 'dist', 'distUnit'};
            if nargin < 2, p = struct(); for k = 1:numel(h), p.(f{k}) = h{k}.Value; end
            else, for k = 1:numel(h), h{k}.Value = p.(f{k}); end
            end
        end
    end

    %% ------------------------------------------------------------------ pipeline: load / process / view
    methods (Access = private)
        function onLoad(app)
            u = app.ui; fp = strtrim(u.path.Value);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.filePath)
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern/Gain Files'; '*.*', 'All files'}, 'Select an antenna pattern file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            dlg = uiprogressdlg(u.fig, 'Title', 'Loading Data', 'Message', 'Reading file...', 'Indeterminate', 'on'); c = onCleanup(@() close(dlg)); %#ok<NASGU>
            t0 = tic; s = app.readAny(fp, u.fmt, u.fmtLbl);
            if s.userData.isCoverage                                   % coverage-results file: route to the Coverage tab
                u.tabs.SelectedTab = u.tabCov; u.covPath.Value = fp; app.addResultsNode(fp, s.rawTbl); return
            end
            u.path.Value = fp; app.filePath = fp; [app.folderPath, app.baseName, ext] = fileparts(fp); app.fileName = [app.baseName ext];
            app.src = s;
            if s.userData.isDep
                items = cellstr(compose('Pattern %d: %.4g GHz', (1:numel(s.blocks)).', s.freqs(:)/1e9));
                nof = isnan(s.freqs(:)); items(nof) = cellstr(compose('Pattern %d', find(nof)));
                u.ffd.Items = items; u.ffd.Value = items{1};
            end
            set([u.ffd, u.ffdLbl], 'Visible', s.userData.isDep);
            u.basis.UserData = true; app.selectBlock(1); app.process();
            app.say('main', sprintf('Loaded <b>%s</b> in %.2f s', app.fileName, toc(t0)), true);
        end

        function s = readAny(~, fp, dd, lb, fmt, cached)
            % Read any source. Generic text files expose the format selector; other formats are self-describing.
            generic = isGenericText(fp);
            if nargin < 5 || isempty(fmt), fmt = "gain"; if generic, dd.Value = 'gain'; end, end
            if nargin < 6, cached = table(); end
            s = readSource(fp, fmt, cached);
            set([dd, lb], 'Visible', generic && ~s.userData.isCoverage);
        end

        function selectBlock(app, k)
            T = normalizePattern(app.src.blocks{k}); T.Properties.UserData = app.src.userData; app.stdTbl = T;
            raw = app.src.rawTbl; if app.src.userData.isDep, raw = app.src.blocks{k}; end
            app.ui.tblIn.Data = raw; app.ui.tblIn.ColumnName = raw.Properties.VariableNames;
        end

        function onProcess(app)
            if isempty(app.stdTbl), uialert(app.ui.fig, 'Load a pattern first.', 'Process', 'Icon', 'warning'); return; end
            dlg = uiprogressdlg(app.ui.fig, 'Title', 'Processing', 'Message', 'Re-processing pattern...', 'Indeterminate', 'on'); c = onCleanup(@() close(dlg)); %#ok<NASGU>
            if isGenericText(app.filePath)                             % reinterpret the cached generic table with the selected format
                s = readSource(app.filePath, app.ui.fmt.Value, app.src.rawTbl);
                assert(~s.userData.isCoverage, 'The selected format identifies a coverage-results file.');
                app.src = s; app.ui.basis.UserData = true; app.selectBlock(1);
            end
            app.process(); app.say('main', 'Re-processed with the current parameters ✅', true);
        end

        function onBlockChanged(app)
            k = find(strcmp(app.ui.ffd.Items, app.ui.ffd.Value), 1); app.ui.basis.UserData = true; app.selectBlock(k); app.process();
        end

        function resetParams(app)
            app.paramUI(app.defaults); if ~isempty(app.stdTbl), app.process(); end
        end

        function process(app)
            % Full recompute: native pattern -> step selection -> view -> tables -> plots.
            u = app.ui; t0 = tic; gainOnly = app.src.userData.isGainOnly;
            [app.patTbl, info] = calcPattern(app.stdTbl, app.getParam()); app.polLabel = info.pol; app.polPairs = info.pairs;
            if isequal(u.basis.UserData, true) && ~gainOnly           % auto-select the cut field basis once per source
                if startsWith(info.pol, 'Linear'), u.basis.Value = 'Linear'; else, u.basis.Value = 'Circular'; end
                u.basis.UserData = false;
            end
            ts = gridStep(app.patTbl.Theta); ps = gridStep(app.patTbl.Phi); if ~isfinite(ts), ts = 1; end, if ~isfinite(ps), ps = ts; end
            native = sprintf('STEP: %g°', max(ts, ps)); nonCanonical = abs(ts - 1) > 1e-9 || abs(ps - 1) > 1e-9;
            wantOne = strcmp(u.step.Value, app.OneDeg); u.step.Items = {native, app.OneDeg};
            if wantOne && nonCanonical, u.step.Value = app.OneDeg; end
            set(u.step, 'Visible', nonCanonical, 'Enable', nonCanonical); u.cutVal.Step = max(min(ts, ps), 1);
            app.buildView(); app.updateComponentItems(); app.updateView(true, false); app.selectPlane(); app.renderFull();
            set([u.cutPanel, u.fullPanel, u.ctrl, u.export, u.toCov, u.dataTabs, u.filter], 'Visible', 'on');
            set([u.uan, u.eGrid], 'Visible', ~gainOnly); u.basis.Enable = ~gainOnly; app.updateParamVisibility();
            pol = ''; if ~gainOnly, pol = sprintf(' | Polarization <b>%s</b>', app.polLabel); end
            app.say('main', sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>θ=%s°, φ=%s°</b>)%s | %.2f s', app.fileName, fmtNum(app.POB, 2), fmtNum(app.POBth), fmtNum(app.POBph), pol, toc(t0)), false);
        end

        function buildView(app)
            % viewTbl = processed pattern at the selected step. Resampling acts on canonical source fields
            % (Re/Im or gain), never on derived quantities such as AR or PLF.
            S = app.stdTbl; ts = gridStep(S.Theta); ps = gridStep(S.Phi);
            if strcmp(app.ui.step.Value, app.OneDeg) && (abs(ts - 1) > 1e-9 || abs(ps - 1) > 1e-9)
                if ts < 1 && ps < 1, S = S(abs(S.Theta - round(S.Theta)) < 1e-9 & abs(S.Phi - round(S.Phi)) < 1e-9, :);   % exact decimation
                else, S = resampleCanonical(S, 1); end
                S.Properties.UserData = app.stdTbl.Properties.UserData; app.viewTbl = calcPattern(S, app.getParam());
            else
                app.viewTbl = app.patTbl;
            end
            app.gridCache = struct(); app.solidAngle = solidWeights(app.viewTbl.Theta, app.viewTbl.Phi);
        end

        function updateView(app, resetRanges, render)
            % Recompute peak / boresight / metrics for the selected component, then refresh tables and (optionally) plots.
            T = app.viewTbl; col = app.comp();
            [app.peak, app.boresight] = calcOrientation(T, app.solidAngle, col, app.Axes6, app.PeakPct, app.PeakExcess);
            app.POB = app.peak.value; app.POBth = T.Theta(app.peak.index); app.POBph = mod(T.Phi(app.peak.index), 360);
            app.metrics = calcMetrics(T, app.solidAngle, app.Axes6, app.boresight, app.PeakPct, app.PeakExcess);
            if resetRanges
                if ~app.isAR(col), app.gainLim = displayRange(chooseGain(T, col), app.PeakPct, app.PeakExcess); end
                app.setFullRange(app.themeLimits(), false); app.setCutRange(app.gainLim, false);
            end
            app.updateTables(); app.updateMetadata();
            if render, app.redraw(); end
        end

        function redraw(app), app.updateCutControl(); app.plotCut(); app.renderFull(); end

        function refreshDisplay(app)
            % Display-convention switches only remap coordinates; no physics is recomputed.
            if isempty(app.viewTbl), return; end
            app.gridCache = struct(); app.updateTables(); app.updateMetadata(); app.redraw();
        end

        function onStepChanged(app), app.buildView(); app.updateComponentItems(); app.updateView(true, true); end

        function p = getParam(app)
            u = app.ui; p = struct('GainLoss_dB', u.loss.Value, 'RxMode', string(u.rx.Value), 'RxAR_dB', u.rw.Value);
            p.FieldScale = 10^(p.GainLoss_dB/20);
            switch u.ptUnit.Value, case 'dBm', p.Pt_dBW = u.pt.Value - 30; case 'Watts', p.Pt_dBW = 10*log10(max(u.pt.Value, eps)); otherwise, p.Pt_dBW = u.pt.Value; end
            p.R_m = max(u.dist.Value, 1e-12); if strcmp(u.distUnit.Value, 'km'), p.R_m = 1000*p.R_m; end
        end

        % ---- small view helpers ----------------------------------------------------------------
        function c = comp(app), c = app.ui.comp.Value; end
        function tf = isSigned(app), tf = strcmp(app.ui.phiSpan.Value, 'signed'); end
        function tf = isElevation(app), tf = strcmp(app.ui.thetaSpan.Value, 'elevation'); end
        function s = thetaName(app), if app.isElevation(), s = "Elevation"; else, s = "Theta"; end, end
        function tf = isAR(~, col)
            key = regexprep(lower(strtrim(string(col))), '[^a-z0-9]', ''); tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
        end
        function s = compLabel(app)
            dd = app.ui.comp; k = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(k), s = string(dd.Value); else, s = string(dd.Items{k}); end
        end
        function lim = themeLimits(app), if app.isAR(app.comp()), lim = [-30 30]; else, lim = app.gainLim; end, end
        function m = themeMap(app), if app.isAR(app.comp()), m = app.cmapAR; else, m = jet(256); end, end
        function [theta, phi] = displayAngles(app, theta, phi)
            if app.isElevation(), theta = 90 - theta; end
            if app.isSigned(), phi(phi > 180 + 1e-9) = phi(phi > 180 + 1e-9) - 360; end
        end
        function [xl, yl, ydir] = displayLimits(app)
            xl = [0 360]; if app.isSigned(), xl = [-180 180]; end
            yl = [0 180]; ydir = 'reverse'; if app.isElevation(), yl = [-90 90]; ydir = 'normal'; end
        end

        function updateComponentItems(app)
            dd = app.ui.comp; [cols, labels] = componentList(app.viewTbl); prev = dd.Value;
            dd.Items = cellstr(labels); dd.ItemsData = cellstr(cols); dd.Value = pickComponent(prev, cols);
        end

        function [G, g] = gridData(app, column)
            % Component matrix + geometry for the current view in the current display convention.
            % Canonical grid (θ rows, φ columns) is built once; display mapping is a row/column permutation.
            c = app.gridCache;
            if ~isfield(c, 'geo')
                T = app.viewTbl; th = unique(T.Theta); ph = unique(T.Phi); [~, it] = ismember(T.Theta, th); [~, ip] = ismember(T.Phi, ph);
                rows = (1:numel(th)).'; thAxis = th; if app.isElevation(), rows = flip(rows); thAxis = 90 - th(rows); end
                cols = (1:numel(ph)).'; phAxis = ph;
                if app.isSigned()
                    cols = find(ph < 360 - 1e-9); phAxis = ph(cols); phAxis(phAxis > 180) = phAxis(phAxis > 180) - 360;
                    [phAxis, o] = sort(phAxis); cols = cols(o);
                    k = find(abs(phAxis - 180) < 1e-9, 1); if ~isempty(k), cols = [cols(k); cols]; phAxis = [-180; phAxis]; end   % close the seam
                end
                [phiGrid, thetaGrid] = meshgrid(phAxis, thAxis); thPhys = thetaGrid; if app.isElevation(), thPhys = 90 - thetaGrid; end
                s = sind(thPhys); pr = deg2rad(phiGrid);
                g = struct('theta', thAxis, 'phi', phAxis, 'thetaGrid', thetaGrid, 'phiGrid', phiGrid, 'thetaPhys', thPhys, ...
                    'x', s.*cos(pr), 'y', s.*sin(pr), 'z', cosd(thPhys), 'rows', rows, 'cols', cols, 'index', sub2ind([numel(th) numel(ph)], it, ip), 'size', [numel(th) numel(ph)]);
                c = struct('geo', g, 'data', struct());
            end
            g = c.geo; key = matlab.lang.makeValidName(column);
            if isfield(c.data, key), G = c.data.(key);
            else, F = nan(g.size); F(g.index) = app.viewTbl.(column); G = F(g.rows, g.cols); c.data.(key) = G;
            end
            app.gridCache = c;
        end

        %% ---------------------------------------------------------------- tables & metadata
        function updateTables(app)
            T = app.viewTbl; if app.isSigned(), T(abs(T.Phi - 360) < 1e-9, :) = []; end
            [T.Theta, T.Phi] = app.displayAngles(T.Theta, T.Phi);
            if app.isSigned() || app.isElevation(), T = sortrows(T, {'Phi', 'Theta'}); end
            app.dispTbl = T; names = T.Properties.VariableNames(3:end);
            if numel(app.outCols) ~= numel(names), app.outCols = ~ismember(names, app.HiddenCols); end
            app.refreshFilter(); app.ui.tblOut.Data = T(:, [true true app.outCols]);
        end

        function refreshFilter(app)
            dd = app.ui.filter; names = app.dispTbl.Properties.VariableNames(3:end); items = names; items(app.outCols) = append('✓ ', names(app.outCols));
            dd.Items = [{'--- column filter ---'}, items]; dd.ItemsData = 0:numel(names); dd.Value = 0;
            removeStyle(dd); on = find(app.outCols) + 1; if ~isempty(on), addStyle(dd, app.styles{1}, 'Item', on); end
            addStyle(dd, app.styles{2}, 'Item', [1, find(~app.outCols) + 1]);
        end

        function onFilterChanged(app, dd)
            k = dd.Value; if k > 0, app.outCols(k) = ~app.outCols(k); end
            app.refreshFilter(); app.ui.tblOut.Data = app.dispTbl(:, [true true app.outCols]); app.updateParamVisibility();
        end

        function updateParamVisibility(app)
            % Only show link-budget controls that influence a visible Results column.
            u = app.ui; sel = string(app.viewTbl.Properties.VariableNames(3:end)); sel = sel(app.outCols);
            rx = any(ismember(["PLF_dB", "Gain_PolCorrected_dB"], sel)); tx = any(ismember(["EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"], sel)); dist = any(ismember(["PFD_Wm2", "E_RMS_Vm"], sel));
            loss = app.src.userData.isGainOnly || any(ismember(["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "Gain_PolCorrected_dB", "EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"], sel));
            set([u.rxLbl, u.rx, u.rwLbl, u.rw], 'Visible', rx); set([u.ptLbl, u.pt, u.ptUnit], 'Visible', tx);
            set([u.distLbl, u.dist, u.distUnit], 'Visible', dist); set([u.lossLbl, u.loss], 'Visible', loss);
        end

        function updateMetadata(app)
            T = app.viewTbl; ud = app.src.userData; th = unique(T.Theta); ph = unique(T.Phi); m = app.metrics; deg = @(v) [fmtNum(v) '°']; dB = @(v) [fmtNum(v) ' dB'];
            rows = {'Source format', ud.source; 'File', app.fileName; 'Samples', sprintf('%d  (θ: %d × φ: %d)', height(T), numel(th), numel(ph)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(min(th)), fmtNum(max(th)), fmtNum(gridStep(th))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(min(ph)), fmtNum(max(ph)), fmtNum(gridStep(ph)))};
            f = app.src.freqs(isfinite(app.src.freqs)); if ~isempty(f), rows(end+1, :) = {'Frequencies', char(strjoin(compose('%.4g GHz', f(:)/1e9), ', '))}; end
            if isfield(ud, 'frequencyMHz') && isfinite(ud.frequencyMHz), rows(end+1, :) = {'Frequency', sprintf('%g MHz', ud.frequencyMHz)}; end
            if ~ud.isGainOnly, rows = [rows; {'Polarization', app.polLabel; 'Cut co-pol / cross-pol', char(strjoin(app.polPairs.(app.ui.basis.Value), ' / '))}]; end
            rows = [rows; {'Selected component', char(app.compLabel()); 'Peak (POB)', sprintf('%s @ [θ=%s°, φ=%s°]', dB(app.POB), fmtNum(app.POBth), fmtNum(app.POBph)); ...
                'Peak policy', sprintf('P%.4g + %g dB max excess (adjusted: %s)', app.PeakPct, app.PeakExcess, string(app.peak.wasAdjusted)); 'Boresight axis', app.Axes6.labels{app.boresight}; ...
                'Peak total gain', sprintf('%s @ [θ=%s°, φ=%s°]', dB(m.PeakGain_dB), fmtNum(m.PeakTheta_deg), fmtNum(m.PeakPhi_deg)); ...
                'HPBW E-plane', deg(m.HPBW_EPlane_deg); 'HPBW H-plane', deg(m.HPBW_HPlane_deg); 'Front-to-back', dB(m.FrontBack_dB); ...
                'Peak directivity', dB(m.PeakDirectivity_dB); 'Radiation efficiency', [fmtNum(m.Efficiency_pct) ' %']; 'AR at peak', dB(m.AxialRatioAtPeak_dB)}];
            if isfield(ud, 'summary') && ~isempty(ud.summary), rows = [rows; ud.summary]; end
            app.ui.tblMeta.Data = rows;
        end

        %% ---------------------------------------------------------------- ranges & theme
        function setFullRange(app, lim, fromSlider)
            lim = clampRange(lim, app.RangeLim); app.fullLim = lim; if ~app.isAR(app.comp()), app.gainLim = lim; end
            app.syncRange([app.full.slider], [app.full.minSp], [app.full.maxSp], lim, fromSlider);
            app.ui.cmin.Value = lim(1); app.ui.cmax.Value = lim(2); app.applyFullRange();
        end
        function setCutRange(app, lim, fromSlider)
            lim = clampRange(lim, app.RangeLim); app.cutLim = lim; u = app.ui;
            app.syncRange(u.cutSlider, u.cutMin, u.cutMax, lim, fromSlider);
            if ~isempty(app.viewTbl), app.plotCut(); end
        end
        function syncRange(app, sliders, mins, maxs, lim, fromSlider)
            % Sliders travel inside the selected range; spinners widen it. Programmatic changes never re-trigger callbacks.
            if fromSlider, set(sliders, 'Value', lim); else, setBounded(sliders, lim, lim, app.RangeLim); end
            setBounded(mins, lim(1), [app.RangeLim(1), lim(2) - 1], app.RangeLim); setBounded(maxs, lim(2), [lim(1) + 1, app.RangeLim(2)], app.RangeLim);
        end
        function applyBoth(app)
            lim = [app.ui.cmin.Value, app.ui.cmax.Value]; app.setFullRange(lim, false); app.setCutRange(lim, false);
        end
        function applyFullRange(app)
            lim = app.fullLim; ticks = axisTicks(lim, app.ui.cstep.Value);
            for k = 1:numel(app.full)
                f = app.full(k); clim(f.axes, lim);
                if strcmp(f.name, 'rect3D'), zlim(f.axes, lim); if ~isempty(ticks), f.axes.ZTick = ticks; end, end
                if ~isempty(f.cbar) && isgraphics(f.cbar) && ~isempty(ticks), f.cbar.Ticks = ticks; end
            end
        end
        function setTagVisible(app, tag, on), set(findall(app.ui.fig, 'Tag', tag), 'Visible', on); end

        %% ---------------------------------------------------------------- full-pattern rendering
        function renderFull(app)
            if isempty(app.viewTbl), return; end
            u = app.ui; [G, g] = app.gridData(app.comp()); lim = app.themeLimits(); label = app.compLabel();
            [thD, phD] = app.displayAngles(app.POBth, app.POBph); [~, ri] = min(abs(g.theta - thD)); [~, ci] = min(abs(g.phi - phD));
            tip = @(TH, PH, V) [dataTipTextRow(app.thetaName(), TH, '%.3g°'); dataTipTextRow("Phi", PH, '%.3g°'); dataTipTextRow(label, V, '%.3g dB')];
            app.polarNorm = max(max(max(G - lim(1), 0), [], 'all'), eps) / max(diff(lim), eps);
            for k = 1:numel(app.full)
                f = app.full(k); ax = f.axes; cla(ax); hold(ax, 'on'); Z = [];
                switch f.name
                    case 'contour'
                        h = pcolor(ax, g.phi, g.theta, G); set(h, 'FaceColor', 'interp', 'LineStyle', 'none');
                        app.angularAxes(ax, 30, 15); daspect(ax, [1 1 1]); title(ax, label, 'Interpreter', 'none'); X = g.phiGrid; Y = g.thetaGrid;
                    case 'circular'
                        X = deg2rad(g.phiGrid); Y = g.thetaPhys; h = surface(ax, X, Y, zeros(size(G)), G, 'EdgeColor', 'none');
                        rt = 0:30:180; set(ax, 'RLim', [0 180], 'RTick', rt); if app.isElevation(), rt = 90 - rt; end
                        ax.RTickLabel = compose('%d°', rt); app.polarTicks(ax); title(ax, sprintf('%s  |  r=θ, angle=φ', label), 'Interpreter', 'none', 'FontSize', 9);
                    case {'sphere', 'polar3D'}
                        r = 1; if strcmp(f.name, 'polar3D'), r = max(G - lim(1), 0) / max(diff(lim), eps) / app.polarNorm; end
                        X = r.*g.x; Y = r.*g.y; Z = r.*g.z; h = surf(ax, X, Y, Z, G, 'EdgeColor', 'none');
                        app.format3D(ax); title(ax, label, 'Interpreter', 'none');
                    case 'rect3D'
                        X = g.phiGrid; Y = g.thetaGrid; Z = G; h = surf(ax, X, Y, Z, 'EdgeColor', 'none');
                        app.angularAxes(ax, 60, 30); grid(ax, 'on'); zlabel(ax, label + " (dB)", 'Interpreter', 'none'); title(ax, label, 'Interpreter', 'none');
                end
                h.Tag = 'APAT_Surface'; clim(ax, lim); colormap(ax, app.themeMap()); app.full(k).cbar = colorbar(ax);
                try, h.DataTipTemplate.DataTipRows = tip(g.thetaGrid, g.phiGrid, G); catch, end
                if isempty(Z), z = []; else, z = Z(ri, ci); end
                app.mark(ax, X(ri, ci), Y(ri, ci), z, tip(g.thetaGrid(ri, ci), g.phiGrid(ri, ci), G(ri, ci)), 'APAT_POB', u.pob.Value, 'k');
                if ~isempty(ax.ContextMenu), set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', ax.ContextMenu); end
                hold(ax, 'off');
            end
            app.applyFullRange(); app.applyViews(); app.drawOverlay(); drawnow limitrate
        end

        function mark(~, ax, x, y, z, rows, tag, visible, color)
            % One annotation mechanism for POB / HPBW markers: a tagged marker line carrying a pinned DataTip.
            if ~all(isfinite([x y])), return; end
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), h = polarplot(ax, x, y, 'o');
            elseif isempty(z), h = plot(ax, x, y, 'o');
            else, h = plot3(ax, x, y, z, 'o', 'Clipping', 'off'); end
            set(h, 'MarkerSize', 5, 'MarkerFaceColor', color, 'MarkerEdgeColor', color, 'HandleVisibility', 'off', 'Tag', tag, 'Visible', visible);
            if ~isempty(rows), h.DataTipTemplate.DataTipRows = rows; end
            try, t = datatip(h, 'DataIndex', 1, 'FontSize', 9, 'Tag', tag, 'HandleVisibility', 'off'); t.Visible = visible; catch, end
        end

        function angularAxes(app, ax, phiStep, thetaStep)
            [xl, yl, ydir] = app.displayLimits();
            set(ax, 'XLim', xl, 'YLim', yl, 'YDir', ydir, 'Box', 'on', 'Layer', 'top', 'XTick', xl(1):phiStep:xl(2), 'YTick', yl(1):thetaStep:yl(2));
            xlabel(ax, 'Phi (degree)'); ylabel(ax, app.thetaName() + " (degree)");
        end
        function polarTicks(app, pax)
            a = 0:30:330; if app.isSigned(), a(a > 180) = a(a > 180) - 360; end
            pax.ThetaTick = 0:30:330; pax.ThetaTickLabel = compose('%d°', a); pax.ThetaZeroLocation = 'top'; pax.ThetaDir = 'clockwise';
        end
        function format3D(~, ax)
            set(ax, 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1], 'Projection', 'orthographic'); axis(ax, 'off');
            col = {[0.85 0.1 0.1], [0.1 0.6 0.1], [0.1 0.2 0.9]}; txt = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'}; D = 1.35*eye(3);
            for k = 1:3
                quiver3(ax, 0, 0, 0, D(k, 1), D(k, 2), D(k, 3), 0, 'Color', col{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12*D(k, 1), 1.12*D(k, 2), 1.12*D(k, 3), txt{k}, 'Color', col{k}, 'FontWeight', 'bold');
            end
        end
        function applyViews(app)
            v = struct('iso', [135 25 0 0 1], 'top', [0 90 0 1 0], 'bottom', [0 -90 0 1 0], 'right', [90 0 0 0 1], 'left', [-90 0 0 0 1], 'front', [0 0 0 0 1], 'back', [180 0 0 0 1]);
            d = v.(app.ui.view3D.Value);
            for k = 3:5
                e = d; if k == 5 && strcmp(app.ui.view3D.Value, 'iso'), e(1:2) = [-35 35]; end
                view(app.full(k).axes, e(1), e(2)); try, camup(app.full(k).axes, e(3:5)); catch, end
            end
        end
        function drawOverlay(app)
            delete(findall(app.ui.fig, 'Tag', 'APAT_Overlay')); c = app.lastCut;
            if ~app.ui.overlay.Value || isempty(c), return; end
            lim = app.themeLimits(); v = c.data(:, 1);
            for k = 3:4
                ax = app.full(k).axes; r = 1.02; if k == 4, r = 1.01 * max(v - lim(1), 0) / max(diff(lim), eps) / app.polarNorm; end
                hold(ax, 'on'); plot3(ax, r.*sind(c.theta).*cosd(c.phi), r.*sind(c.theta).*sind(c.phi), r.*cosd(c.theta), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_Overlay'); hold(ax, 'off');
            end
        end

        %% ---------------------------------------------------------------- cuts
        function selectPlane(app)
            % E-plane: θ-cut through the boresight axis; H-plane: orthogonal principal cut.
            u = app.ui; A = app.Axes6; k = app.boresight;
            if startsWith(u.plane.Value, 'E'), type = 'Theta'; val = A.phi(k);
            elseif A.theta(k) == 90, type = 'Phi'; val = app.displayAngles(90, 0);
            else, type = 'Theta'; val = 90; end
            u.cutType.Value = type; vals = app.updateCutControl(); [~, i] = min(abs(vals - val)); u.cutVal.Value = vals(i);
            app.onCutChanged();
        end
        function onCutTypeChanged(app), app.updateCutControl(); app.onCutChanged(); end
        function onBasisChanged(app), app.ui.basis.UserData = false; app.updateMetadata(); app.onCutChanged(); end
        function onCutChanged(app)
            u = app.ui; u.hpbwTips.Visible = u.hpbw.Value; if ~u.hpbw.Value, u.hpbwTips.Value = false; end
            app.plotCut(); app.drawOverlay();
        end

        function vals = updateCutControl(app)
            % Cut value = fixed θ (display convention) for a Phi cut, fixed φ (0..360) for a Theta cut.
            T = app.viewTbl; s = app.ui.cutVal;
            if strcmp(app.ui.cutType.Value, 'Phi'), vals = unique(app.displayAngles(T.Theta, 0)); else, vals = unique(mod(T.Phi, 360)); end
            [~, k] = min(abs(vals - s.Value)); setBounded(s, vals(k), [min(vals), max(vals)], [-360 360]);
            if numel(vals) > 1, s.Step = min(diff(vals)); end
        end

        function [cols, idx] = cutColumns(app)
            % Total plus the selected field pair, co-pol first. idx keeps line colours stable.
            u = app.ui;
            if app.src.userData.isGainOnly, cols = string(app.comp()); idx = 1; return; end
            pair = app.polPairs.(u.basis.Value); u.cbCo.Text = char(pair(1)); u.cbCx.Text = char(pair(2));
            sel = [u.cbTotal.Value, u.cbCo.Value, u.cbCx.Value]; if ~any(sel), sel(1) = true; end
            idx = find(sel); all3 = ["E_Total_dB", pair + "_dB"]; cols = all3(idx);
        end

        function c = cutData(app)
            % Extract the active cut as one full 0..360° circle (θ-cuts pass through the opposite φ).
            T = app.viewTbl; u = app.ui; type = string(u.cutType.Value); req = u.cutVal.Value; signed = app.isSigned();
            [cols, idx] = app.cutColumns();
            if type == "Phi"
                if app.isElevation(), req = 90 - req; end
                [ang, rows, fixed, snapped] = cutRows(T, 'Phi', req); shown = fixed; if app.isElevation(), shown = 90 - fixed; end; sym = 'θ';
            else
                [ang, rows, fixed, snapped] = cutRows(T, 'Theta', req); shown = fixed; sym = 'φ';
            end
            if snapped, app.say('main', sprintf('%s cut snapped to nearest %s = %g°', type, sym, shown), true); end
            data = T{rows, cellstr(cols)}; th = T.Theta(rows); ph = T.Phi(rows);
            if signed, ang(ang > 180) = ang(ang > 180) - 360; end
            [ang, o] = sort(ang); data = data(o, :); th = th(o); ph = ph(o);
            [ang, k] = unique(ang, 'stable'); data = data(k, :); th = th(k); ph = ph(k);
            k = find(abs(ang - 180) < 1e-9, 1);
            if signed && ~isempty(k) && ~any(abs(ang + 180) < 1e-9), ang = [-180; ang]; data = [data(k, :); data]; th = [th(k); th]; ph = [ph(k); ph]; end   % close the seam
            if app.src.userData.isGainOnly, ttl = char(app.compLabel()); else, ttl = sprintf('%s cut @ %s = %g°', type, sym, shown); end
            c = struct('ang', ang, 'data', data, 'cols', cols, 'idx', idx, 'theta', th, 'phi', ph, 'type', type, 'title', ttl);
        end

        function plotCut(app)
            if isempty(app.viewTbl), return; end
            u = app.ui; c = app.cutData(); app.lastCut = c; pax = u.paxCut; rax = u.axRect; lim = app.cutLim;
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on');
            xl = [0 360]; if app.isSigned(), xl = [-180 180]; end
            names = replace(c.cols, "_", "\_"); colors = rax.ColorOrder; colors = colors(1 + mod(c.idx - 1, size(colors, 1)), :);
            pl = polarplot(pax, deg2rad(c.ang), max(c.data, lim(1)), 'LineWidth', 1.4);      % clamp so the polar trace never folds through the origin
            rl = plot(rax, c.ang, c.data, 'LineWidth', 1.4);
            for k = 1:numel(pl)
                rows = [dataTipTextRow("Angle", c.ang, '%.3g°'); dataTipTextRow("Magnitude", c.data(:, k), '%.3g dB')];
                set([pl(k), rl(k)], 'Color', colors(k, :)); pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            set(pax, 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.polarTicks(pax);
            set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on'); xlabel(rax, c.type + " (degree)");
            title(pax, c.title, 'Interpreter', 'none'); title(rax, c.title, 'Interpreter', 'none');
            [pk, i] = max(c.data(:, 1), [], 'omitnan'); u.hpbwLbl.Text = '';
            if isfinite(pk)
                rows = [dataTipTextRow("Angle", c.ang(i), '%.3g°'); dataTipTextRow("Magnitude", pk, '%.3g dB')];
                app.mark(pax, deg2rad(c.ang(i)), max(pk, lim(1)), [], rows, 'APAT_POB', u.pob.Value, 'k'); app.mark(rax, c.ang(i), pk, [], rows, 'APAT_POB', u.pob.Value, 'k');
                [bw, lo, hi] = calcHPBW(c.ang, c.data(:, 1), pk, c.ang(i));
                if u.hpbw.Value && isfinite(bw)
                    b = [lo, hi]; if xl(1) < 0, b = mod(b + 180, 360) - 180; else, b = mod(b, 360); end
                    u.hpbwLbl.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                    if b(1) <= b(2), reg = b; else, reg = [xl(1), b(2); b(1), xl(2)]; end                    % wrap-aware shading
                    thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    xregion(rax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    lbls = ["Lower HPBW", "Upper HPBW"];
                    for j = 1:2
                        rows = [dataTipTextRow(lbls(j), b(j), '%.2f°'); dataTipTextRow("Gain", pk - 3, '%.2f dB')];
                        app.mark(pax, deg2rad(b(j)), pk - 3, [], rows, 'APAT_HPBW', u.hpbwTips.Value, '#D95319'); app.mark(rax, b(j), pk - 3, [], rows, 'APAT_HPBW', u.hpbwTips.Value, '#D95319');
                    end
                end
            end
            legend(pax, pl, names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rl, names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off');
        end

        %% ---------------------------------------------------------------- export & status
        function exportResults(app)
            [f, p] = uiputfile({'*.csv', 'Comma-delimited (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Results', fullfile(app.folderPath, [app.baseName '_APAT_results.csv']));
            if isequal(f, 0), return; end
            writeTable(app.ui.tblOut.Data, fullfile(p, f)); app.say('main', ['Results exported to <b>' fullfile(p, f) '</b>'], true);
        end
        function exportCut(app)
            c = app.lastCut; if isempty(c), return; end
            [f, p] = uiputfile({'*.csv', 'Comma-delimited (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'}, 'Export Cut', fullfile(app.folderPath, [app.baseName '_cut.csv']));
            if isequal(f, 0), return; end
            writeTable(array2table([c.ang, c.data], 'VariableNames', [{'Angle_deg'}, cellstr(c.cols)]), fullfile(p, f));
            app.say('main', ['Cut (' c.title ') exported to <b>' fullfile(p, f) '</b>'], true);
        end
        function exportUAN(app)
            T = app.viewTbl; assert(all(ismember({'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase'}, T.Properties.VariableNames)), 'UAN export requires processed E-field columns.');
            U = sortrows(table(T.Theta, T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'}), {'Phi', 'Theta'});
            gmax = max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan'); ts = gridStep(U.Theta); if ~isfinite(ts), ts = 1; end
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'Comma-delimited (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'}, 'Export UAN', ...
                fullfile(app.folderPath, sprintf('%s_%.5f_%gdeg.uan', app.baseName, gmax, ts)));
            if isequal(f, 0), return; end
            fp = fullfile(p, f);
            if endsWith(fp, '.uan', 'IgnoreCase', true)
                hdr = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\ncomplex\nmag_phase\n' ...
                    'pattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                    min(U.Phi), max(U.Phi), gridStep(U.Phi), min(U.Theta), max(U.Theta), ts, gmax);
                writelines(hdr, fp); writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
            else
                writeTable(U, fp);
            end
            app.say('main', ['UAN exported to <b>' fp '</b>'], true);
        end

        function say(app, which, msg, transient)
            % Status text; transient messages restore the last persistent text after 3 s via one shared timer.
            if app.isClosing, return; end
            if strcmp(which, 'cov'), lbl = app.ui.covStatus; else, lbl = app.ui.status; end
            t = app.statusTimer; if isvalid(t), stop(t); end
            lbl.Text = char(msg);
            if transient, t.TimerFcn = @(~, ~) app.restoreStatus(lbl); start(t); else, lbl.UserData = lbl.Text; end
        end
        function restoreStatus(app, lbl)
            if ~app.isClosing && isvalid(lbl) && ~isempty(lbl.UserData), lbl.Text = lbl.UserData; end
        end
    end

    %% ------------------------------------------------------------------ coverage tab
    methods (Access = private)
        function sendToCoverage(app)
            % Coverage always receives the canonical view table (loss / step already applied; convention independent).
            if isempty(app.viewTbl), uialert(app.ui.fig, 'Load and process a pattern first.', 'Coverage'); return; end
            u = app.ui; u.tabs.SelectedTab = u.tabCov; u.covPath.Value = app.filePath; node = app.covFind(app.filePath);
            if isempty(node), app.addPatternNode(app.baseName, app.filePath, app.viewTbl, app.src.rawTbl);
            else, d = node.NodeData; d.pattern = app.viewTbl; d.solidAngle = app.solidAngle; d.component = ''; node.NodeData = d; u.covTree.SelectedNodes = node; app.syncPatternNode(node); end
            app.say('cov', 'Coverage source synchronized from the current Main-tab view.', false);
        end

        function node = addPatternNode(app, name, fp, T, raw)
            node = uitreenode(app.ui.covRoot, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', 'pattern', 'name', name, 'path', fp, 'pattern', T, 'solidAngle', solidWeights(T.Theta, T.Phi), 'raw', raw, 'component', '', 'boresight', 1);
            expand(app.ui.covRoot); app.ui.covTree.CheckedNodes = [app.ui.covTree.CheckedNodes; node]; app.ui.covTree.SelectedNodes = node;
            app.syncPatternNode(node); app.updateCoverageUI();
            app.say('cov', sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name), false);
        end

        function addResultsNode(app, fp, R)
            [~, name] = fileparts(fp); node = uitreenode(app.ui.covRoot, 'Text', ['📄 ' name]); node.NodeData = struct('kind', 'results', 'name', name, 'path', fp);
            app.ui.covTree.CheckedNodes = [app.ui.covTree.CheckedNodes; node]; thr = R{:, 1};
            for k = 2:width(R), app.addJob(node, thr, R{:, k}, 'Res', R.Properties.VariableNames{k}, "n/a"); end
            expand(node); app.setCovX([min(thr), max(thr)], false, true);
            st = gridStep(thr); if isfinite(st) && st < app.ui.thrStep.Value, app.ui.thrStep.Value = st; end
            app.say('cov', sprintf('Coverage results "<b>%s</b>" loaded (%d curves).', name, width(R) - 1), false);
        end

        function syncPatternNode(app, node)
            % Component list, boresight detection and threshold preset for the active pattern node.
            d = node.NodeData; T = d.pattern; dd = app.ui.covComp; [cols, labels] = componentList(T);
            prev = d.component; if isempty(prev), prev = dd.Value; end
            comp = pickComponent(prev, cols); dd.Items = cellstr(labels); dd.ItemsData = cellstr(cols); dd.Value = comp;
            if ~strcmp(d.component, comp)
                [~, d.boresight] = calcOrientation(T, d.solidAngle, comp, app.Axes6, app.PeakPct, app.PeakExcess); d.component = comp; node.NodeData = d;
                if app.ui.orient.Value == 0, app.onOrientationChanged(); end
            end
            key = sprintf('%s|%s|%d|%.6g', d.path, comp, height(T), mean(T.(comp), 'omitnan'));
            if ~strcmp(app.covPresetKey, key)                          % automatic preset only when pattern/component/view changed
                b = displayRange(T.(comp), app.PeakPct, app.PeakExcess); app.ui.thrMin.Value = b(1); app.ui.thrMax.Value = b(2); app.covPresetKey = key;
            end
        end

        function onCovTypeChanged(app), app.updateCoverageUI(); if app.ui.btnCon.Value, app.onOrientationChanged(); end, end
        function onOrientationChanged(app)
            k = app.ui.orient.Value; node = app.covTarget();
            if k == 0, if isempty(node), return; end, k = node.NodeData.boresight; end
            app.ui.coneTh.Value = app.Axes6.theta(k); app.ui.conePh.Value = app.Axes6.phi(k);
            if app.ui.btnCon.Value, app.say('cov', sprintf('Conical orientation: <b>%s</b> (θ₀=%g°, φ₀=%g°)', app.Axes6.labels{k}, app.Axes6.theta(k), app.Axes6.phi(k)), true); end
        end
        function onCovComponentChanged(app)
            node = app.covTarget(); if isempty(node), return; end
            d = node.NodeData; d.component = ''; node.NodeData = d; app.syncPatternNode(node);
        end

        function node = covTarget(app)
            % Pattern node to operate on: the selection (or its pattern ancestor), else the most recent pattern node.
            node = []; n = app.ui.covTree.SelectedNodes;
            if ~isempty(n), n = n(1); while isa(n, 'matlab.ui.container.TreeNode'), if isstruct(n.NodeData) && strcmp(n.NodeData.kind, 'pattern'), node = n; return; end, n = n.Parent; end, end
            kids = app.ui.covRoot.Children;
            for k = numel(kids):-1:1, if isstruct(kids(k).NodeData) && strcmp(kids(k).NodeData.kind, 'pattern'), node = kids(k); return; end, end
        end
        function node = covFind(app, fp)
            node = []; kids = app.ui.covRoot.Children;
            for k = 1:numel(kids), if isstruct(kids(k).NodeData) && strcmp(kids(k).NodeData.path, fp), node = kids(k); return; end, end
        end
        function jobs = covJobs(app, roots)
            % All job nodes below ROOTS (default: the whole tree), in creation order. The tree is the only registry.
            if nargin < 2, roots = app.ui.covRoot; end
            jobs = matlab.ui.container.TreeNode.empty(0, 1);
            for n = roots(:).'
                if isstruct(n.NodeData) && strcmp(n.NodeData.kind, 'job'), jobs(end+1, 1) = n; end %#ok<AGROW>
                if ~isempty(n.Children), jobs = [jobs; app.covJobs(n.Children)]; end %#ok<AGROW>
            end
        end

        function updateCoverageUI(app)
            u = app.ui; hasPattern = ~isempty(app.covTarget()); hasJobs = ~isempty(app.covJobs()); con = u.btnCon.Value;
            set([u.covCompute, u.covComp, u.covCompLbl], 'Enable', hasPattern);
            set([u.covExport, u.covClear, u.qCov, u.qCovBtn, u.qThr, u.qThrBtn, u.qCovLbl, u.qThrLbl], 'Enable', hasJobs); u.covReset.Enable = hasJobs || hasPattern;
            set([u.coneLbls, u.coneTh, u.conePh, u.coneAng, u.orient, u.orientLbl], 'Visible', con, 'Enable', con);
            u.covResults.Visible = hasJobs || hasPattern; set([u.covFmt, u.covFmtLbl], 'Visible', hasPattern && isGenericText(u.covPath.Value));
        end

        function onCovLoad(app)
            u = app.ui; fp = strtrim(u.covPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFind(fp))
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.ffd;*.ffe;*.ffs;*.cut;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage data'; '*.*', 'All files'}, 'Select a pattern or coverage results file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            existing = app.covFind(fp);
            if ~isempty(existing), u.covTree.SelectedNodes = existing; app.onCovSelection(); u.covPath.Value = fp; app.say('cov', 'File already loaded — node selected.', true); return; end
            u.covPath.Value = fp; s = app.readAny(fp, u.covFmt, u.covFmtLbl);
            if s.userData.isCoverage, app.addResultsNode(fp, s.rawTbl); else, [~, name] = fileparts(fp); app.addPatternNode(name, fp, app.auxPattern(s), s.rawTbl); end
        end
        function T = auxPattern(app, s)
            S = normalizePattern(s.blocks{1}); S.Properties.UserData = s.userData; T = calcPattern(S, app.getParam());
        end
        function onCovFormatChanged(app)
            fp = strtrim(app.ui.covPath.Value); node = app.covFind(fp); if isempty(node) || ~isGenericText(fp), return; end
            s = readSource(fp, app.ui.covFmt.Value, node.NodeData.raw);
            if s.userData.isCoverage, app.say('cov', 'Coverage-result files are detected automatically; nothing to reprocess.', true); return; end
            name = node.NodeData.name; for j = app.covJobs(node).', delete(j.NodeData.line); end
            delete(node); app.addPatternNode(name, fp, app.auxPattern(s), s.rawTbl); app.refreshCoverage();
            app.say('cov', sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
        end

        function thr = thresholds(app)
            u = app.ui; a = u.thrMin.Value; b = u.thrMax.Value; s = max(u.thrStep.Value, 0.1);
            if b <= a, b = min(app.RangeLim(2), a + s); u.thrMax.Value = b; end
            thr = (a:s:b).'; if thr(end) < b - 1e-9, thr(end+1) = b; end
        end

        function computeCoverage(app)
            u = app.ui; node = app.covTarget();
            if isempty(node), uialert(u.fig, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if strcmp(node.NodeData.path, app.filePath) && ~isempty(app.viewTbl)   % Main-sourced nodes track the live view
                d = node.NodeData; d.pattern = app.viewTbl; d.solidAngle = app.solidAngle; node.NodeData = d;
            end
            d = node.NodeData; T = d.pattern; comp = u.covComp.Value; thr = app.thresholds();
            if u.btnCon.Value
                th0 = u.coneTh.Value; ph0 = mod(u.conePh.Value, 360); a = u.coneAng.Value; k = u.orient.Value; if k == 0, k = d.boresight; end
                mask = cosd(T.Theta)*cosd(th0) + sind(T.Theta)*sind(th0).*cosd(T.Phi - ph0) >= cosd(a);
                center = app.coneLabel(th0, ph0); tag = sprintf('Con %s α%s°', erase(center, ["=", ","]), fmtNum(a));
                label = sprintf('Conical (%s) α=%s°', center, fmtNum(a)); orient = string(app.Axes6.labels{k});
            else
                mask = true(height(T), 1); tag = 'Sph'; label = 'Spherical'; orient = "n/a";
            end
            cov = coverageCCDF(T.(comp), mask, thr, d.solidAngle);
            app.addJob(node, thr, cov, tag, sprintf('%s · %s', label, comp), orient); app.setCovX([thr(1), thr(end)], false, true);
            msg = sprintf('Run-<b>%d</b>: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', app.covRunID, label, d.name, comp, numel(thr));
            if u.btnCon.Value, msg = sprintf('%s | Orientation <b>%s</b>', msg, orient); end
            app.say('cov', msg, false);
        end

        function node = addJob(app, parent, thr, cov, tag, text, orient)
            app.covRunID = app.covRunID + 1; id = app.covRunID; icon = '📉'; if strcmp(tag, 'Res'), icon = '📈'; end
            name = sprintf('%s R%d %s', icon, id, text);
            ln = plot(app.ui.covAxes, thr, cov, 'LineWidth', 1.6, 'DisplayName', name);
            ln.DataTipTemplate.DataTipRows = [dataTipTextRow('Threshold', 'XData', '%.2f dB'); dataTipTextRow('Coverage', 'YData', '%.2f%%')];
            node = uitreenode(parent, 'Text', name);
            node.NodeData = struct('kind', 'job', 'id', id, 'tag', tag, 'label', name, 'thr', thr(:), 'cov', cov(:), 'line', ln, 'orientation', orient);
            expand(parent); app.ui.covTree.CheckedNodes = [app.ui.covTree.CheckedNodes; node]; app.refreshCoverage();
        end

        function refreshCoverage(app)
            % Checked state drives curve/query visibility, the legend and the results table.
            u = app.ui; jobs = app.covJobs(); on = ismember(jobs, u.covTree.CheckedNodes); lines = gobjects(0, 1);
            for k = 1:numel(jobs)
                d = jobs(k).NodeData; set(d.line, 'Visible', on(k));
                set(findall(u.covAxes, '-regexp', 'Tag', sprintf('^CovQ_\\w+_%d$', d.id)), 'Visible', on(k));
                if on(k), lines(end+1, 1) = d.line; end %#ok<AGROW>
            end
            if isempty(lines), legend(u.covAxes, 'off'); u.covTable.Data = table();
            else
                legend(u.covAxes, lines, 'Location', 'southwest', 'Interpreter', 'none');
                D = [jobs(on).NodeData]; thr = unique(vertcat(D.thr)); M = nan(numel(thr), numel(D) + 1); M(:, 1) = thr; names = cell(1, numel(D) + 1); names{1} = 'Threshold (dB)';
                for k = 1:numel(D), [x, i] = unique(D(k).thr); M(:, k+1) = interp1(x, D(k).cov(i), thr, 'linear', NaN); names{k+1} = sprintf('R%d %s %%', D(k).id, D(k).tag); end
                u.covTable.Data = array2table(compose('%.2f', M), 'VariableNames', names);
            end
            app.updateCoverageUI();
        end

        function onCovSelection(app)
            u = app.ui; sel = u.covTree.SelectedNodes; jobs = app.covJobs();
            for k = 1:numel(jobs), ln = jobs(k).NodeData.line; ln.LineWidth = 1.6; if ~isempty(sel) && jobs(k) == sel(1), ln.LineWidth = 2.6; end, end
            if isempty(sel) || ~isstruct(sel(1).NodeData), return; end
            d = sel(1).NodeData;
            if strcmp(d.kind, 'job')
                shown = round(d.cov, 2); [cmax, j] = max(shown); j = find(shown == cmax, 1, 'last'); msg = sprintf('%s | max <b>%s%%</b> @ <b>%s dB</b>', d.label, fmtNum(cmax), fmtNum(d.thr(j)));
                [c, i] = unique(d.cov, 'last'); if numel(c) > 1, t50 = interp1(c, d.thr(i), 50, 'linear', NaN); else, t50 = NaN; end
                if isfinite(t50), msg = sprintf('%s | 50%%-coverage threshold <b>%s dB</b>', msg, fmtNum(t50)); end
                if d.orientation ~= "n/a", msg = sprintf('%s | Orientation <b>%s</b>', msg, d.orientation); end
                msg = sprintf('%s | Threshold [%s, %s] dB step %s', msg, fmtNum(d.thr(1)), fmtNum(d.thr(end)), fmtNum(gridStep(d.thr)));
            else
                node = app.covTarget(); if ~isempty(node), app.syncPatternNode(node); end
                msg = sprintf('%s <b>"%s"</b> — <b>%d</b> coverage job(s).', regexprep(d.kind, '^.', '${upper($0)}'), d.name, numel(sel(1).Children));
            end
            app.say('cov', msg, false); app.updateCoverageUI();
        end

        function queryCoverage(app, mode)
            % Mark coverage@threshold ("cov") or threshold@coverage ("thr") on every checked curve under the selection.
            u = app.ui; ax = u.covAxes; sel = u.covTree.SelectedNodes;
            if isempty(sel), app.say('cov', 'Select a node to query.', true); return; end
            jobs = app.covJobs(sel); jobs = jobs(ismember(jobs, u.covTree.CheckedNodes)); hit = false;
            if isempty(jobs), app.say('cov', 'No checked results under the selected node.', true); return; end
            for k = 1:numel(jobs)
                d = jobs(k).NodeData; tag = sprintf('CovQ_%s_%d', mode, d.id); delete(findall(ax, 'Tag', tag)); [x, i] = unique(d.thr);
                if mode == "cov", x0 = u.qCov.Value; y0 = interp1(x, d.cov(i), x0, 'linear', NaN);
                else, y0 = u.qThr.Value; [c, i] = unique(d.cov, 'last'); x0 = NaN; if numel(c) > 1, x0 = interp1(c, d.thr(i), y0, 'linear', NaN); end
                end
                if ~isfinite(x0) || ~isfinite(y0), continue; end
                line(ax, [x0 x0], [0 y0], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [app.RangeLim(1) x0], [y0 y0], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                try, t = datatip(d.line, x0, y0, 'SnapToDataVertex', 'off', 'FontSize', 9, 'HandleVisibility', 'off'); t.Tag = tag; catch, end
                hit = true;
            end
            if ~hit, app.say('cov', 'Query value is outside the selected results range.', true);
            elseif mode == "cov", app.say('cov', sprintf('Coverage queried at %s dB.', fmtNum(u.qCov.Value)), false);
            else, app.say('cov', sprintf('Threshold queried at %s%% coverage.', fmtNum(u.qThr.Value)), false); end
        end

        function clearCoverageTips(app)
            sel = app.ui.covTree.SelectedNodes; if isempty(sel), app.say('cov', 'Select a node to clear.', true); return; end
            for j = app.covJobs(sel).', d = j.NodeData; delete(findall(app.ui.covAxes, '-regexp', 'Tag', sprintf('^CovQ_\\w+_%d$', d.id))); delete(findall(d.line, 'Type', 'datatip')); end
            app.say('cov', 'Selected DataTips and query markers cleared.', true);
        end

        function resetCoverage(app)
            u = app.ui; delete(u.covRoot.Children); app.initCovAxes(u.covAxes); u.covTable.Data = table();
            app.covRunID = 0; app.covPresetKey = ''; app.covXInit = false; set(u.covAxes, 'XLimMode', 'auto');
            setBounded(u.xSlider, [-40 10], app.RangeLim, app.RangeLim); setBounded(u.xMin, -40, app.RangeLim, app.RangeLim); setBounded(u.xMax, 10, app.RangeLim, app.RangeLim);
            u.covResults.Visible = 'off'; app.updateCoverageUI(); app.say('cov', 'Coverage workspace reset 🔄', true);
        end

        function exportCoverage(app)
            if isempty(app.ui.covTable.Data), return; end
            [f, p] = uiputfile({'*.csv', 'Comma-delimited (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Coverage Results', fullfile(app.folderPath, 'coverage_results.csv'));
            if isequal(f, 0), return; end
            writeTable(app.ui.covTable.Data, fullfile(p, f)); app.say('cov', ['Coverage results exported to ' fullfile(p, f)], true);
        end

        function setCovX(app, lim, fromSlider, expand)
            % Spinners are the master X-range controls (they define the slider travel); the slider only narrows the view.
            u = app.ui; lim = clampRange(lim, app.RangeLim);
            if nargin > 3 && expand && app.covXInit, lim = [min(lim(1), u.covAxes.XLim(1)), max(lim(2), u.covAxes.XLim(2))]; end
            app.covXInit = true; app.syncRange(u.xSlider, u.xMin, u.xMax, lim, fromSlider); set(u.covAxes, 'XLimMode', 'manual', 'XLim', lim);
        end

        function label = coneLabel(app, theta, phi)
            % Principal-axis name when the cone centre coincides with ±X/±Y/±Z, otherwise the explicit angles.
            A = app.Axes6; c = [sind(theta)*cosd(phi), sind(theta)*sind(phi), cosd(theta)];
            V = [sind(A.theta(:)).*cosd(A.phi(:)), sind(A.theta(:)).*sind(A.phi(:)), cosd(A.theta(:))]; k = find(V*c.' >= 1 - 1e-9, 1);
            if isempty(k), label = sprintf('θ=%s°, φ=%s°', fmtNum(theta), fmtNum(phi)); else, label = A.labels{k}; end
        end
    end
end

%% ====================================================================== I/O (UI independent)
function tf = isGenericText(fp)
[~, ~, e] = fileparts(char(fp)); tf = any(strcmpi(e, {'.csv', '.txt', '.dat'}));
end

function src = readSource(fp, fmt, cached)
%READSOURCE Parse any supported file into {rawTbl, blocks{}, freqs, userData}. Blocks are canonical
% E-field tables {Theta,Phi,Re_Eth,Im_Eth,Re_Eph,Im_Eph} or gain tables {Theta,Phi,<gain columns>}.
if nargin < 2 || isempty(fmt), fmt = "gain"; end
if nargin < 3, cached = table(); end
[~, ~, e] = fileparts(fp); ext = upper(erase(e, '.'));
src = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, 'userData', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false));
switch ext
    case {'XLSX', 'XLS'},      src = readExcelMatrix(fp, src);
    case {'CSV', 'TXT', 'DAT'}, src = readGenericText(fp, string(fmt), cached, src);
    case 'CUT',                src = readGraspCut(fp, src);
    case {'UAN', 'FZ', 'OUT', 'FFS', 'FFE', 'FFD'}, src = readFarField(fp, ext, src);
    otherwise, error('APAT:unsupported', 'Unsupported file format: %s', ext);
end
end

function T = fieldTable(theta, phi, Eth, Eph)
T = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end
function E = magPhase(dB, deg), E = 10.^(dB/20) .* exp(1i*deg2rad(deg)); end
function [Eth, Eph] = circToLinear(Er, El), Eth = (Er + El)/sqrt(2); Eph = (Er - El)/(1i*sqrt(2)); end

function [nHdr, ffd] = scanHeader(fp)
%SCANHEADER Count leading non-data lines; recognise the HFSS FFD header (two axis triples + optional frequency list).
fid = fopen(fp, 'r'); assert(fid > 0, 'APAT:open', 'Cannot open file: %s', fp); c = onCleanup(@() fclose(fid)); %#ok<NASGU>
nHdr = 0; triples = zeros(0, 3); ffd = struct('isFFD', false, 'freq', zeros(0, 1));
num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?'; dataLine = ['^\s*' num '(?:[\s,;]+' num '){3,}\s*$'];
while true
    line = fgetl(fid); if ~ischar(line), return; end
    t = strtrim(line); if isempty(t), nHdr = nHdr + 1; continue; end
    v = sscanf(t, '%f').';
    if size(triples, 1) < 2 && numel(v) == 3, triples(end+1, :) = v; nHdr = nHdr + 1; continue; end %#ok<AGROW>
    if size(triples, 1) == 2 && all(isfinite(triples(:))) && all(triples(:, 3) >= 1)
        tok = regexp(t, '^frequenc(?:y|ies)\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok), f = sscanf(tok{1}, '%f'); if ~isscalar(f), ffd.freq = f(:); end, nHdr = nHdr + 1; end
        ffd.isFFD = true; ffd.theta = triples(1, :); ffd.phi = triples(2, :); return
    end
    if ~isempty(regexp(t, dataLine, 'once')), return; end
    nHdr = nHdr + 1;
end
end

function src = readFarField(fp, ext, src)
%READFARFIELD Column-oriented far-field exports: XGTD UAN/FZ, GRASP OUT, CST FFS, FEKO FFE, HFSS FFD.
[nHdr, ffd] = scanHeader(fp);
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = readmatrix(fp, setvartype(opts, 'double')); M = M(~all(isnan(M), 2), :);
if strcmp(ext, 'FFD')
    assert(ffd.isFFD, 'APAT:ffd', 'FFD header (theta/phi ranges) not found.');
    th = linspace(ffd.theta(1), ffd.theta(2), ffd.theta(3)).'; ph = linspace(ffd.phi(1), ffd.phi(2), ffd.phi(3)).';
    theta = repelem(th, numel(ph)); phi = repmat(ph, numel(th), 1); n = numel(theta);
    sep = isnan(M(:, 1)); freqs = [ffd.freq(:); M(sep & ~isnan(M(:, 2)), 2)].'; F = M(~sep, 1:4);   % "Frequency <f>" separator rows
    assert(mod(size(F, 1), n) == 0, 'APAT:ffd', 'FFD row count does not match the theta/phi grid.');
    nb = size(F, 1)/n; freqs(end+1:nb) = NaN; freqs = freqs(1:nb);
    src.blocks = arrayfun(@(b) fieldTable(theta, phi, complex(F((b-1)*n+(1:n), 1), F((b-1)*n+(1:n), 2)), complex(F((b-1)*n+(1:n), 3), F((b-1)*n+(1:n), 4))), 1:nb, 'UniformOutput', false);
    src.freqs = freqs; src.rawTbl = src.blocks{1}; src.userData.source = 'HFSS FFD'; src.userData.isDep = nb > 1 || any(isfinite(freqs));
    return
end
M = M(:, 1:6);
switch ext
    case {'UAN', 'FZ'}, names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}; Eth = magPhase(M(:, 3), M(:, 5)); Eph = magPhase(M(:, 4), M(:, 6)); src.userData.source = ['XGTD ' ext];
    case 'OUT', names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; [Eth, Eph] = circToLinear(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6))); src.userData.source = 'TICRA/GRASP OUT';
    case 'FFS', names = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6)); src.userData.source = 'CST FFS';
    case 'FFE', names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6)); src.userData.source = 'FEKO FFE';
end
src.rawTbl = array2table(M, 'VariableNames', names); if strcmp(ext, 'FFS'), M = M(:, [2 1]); end
src.blocks = {fieldTable(M(:, 1), M(:, 2), Eth, Eph)};
end

function src = readGenericText(fp, fmt, T, src)
%READGENERICTEXT CSV/TXT/DAT: coverage-results table, gain-only pattern, or one of the six generic E-field layouts.
if isempty(T)
    opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve'; T = rmmissing(readtable(fp, opts));
end
nc = width(T); assert(nc >= 2 && ~isempty(T), 'APAT:generic', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHdr = ~all(startsWith(names, "Var")); c1 = T{:, 1}; c2 = T{:, 2};
covHdr = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
if (fmt == "gain" || nc < 6 || covHdr) && all(isfinite(c2)) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHdr, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:nc-1))]; end
    src.rawTbl = T; src.userData.isCoverage = true; return
end
if fmt == "gain"                                                     % the wider-span angle column is phi
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; T = movevars(T, 'Theta', 'Before', 1); else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    src.rawTbl = T; src.blocks = {T}; src.userData.isGainOnly = true; src.userData.source = 'Generic gain table'; return
end
assert(nc >= 6, 'APAT:generic', 'The selected E-field format requires six numeric columns.');
V = T{:, 3:6}; magPh = endsWith(fmt, "magphase"); layout = "n/a";
if magPh
    big = max(abs(V), [], 1, 'omitnan') > 100;                          % phase columns exceed ±100
    if big(2) && ~big(3), mc = [1 3]; pc = [2 4]; layout = "interleaved"; else, mc = [1 2]; pc = [3 4]; layout = "grouped"; end
    A = magPhase(V(:, mc(1)), V(:, pc(1))); B = magPhase(V(:, mc(2)), V(:, pc(2)));
else
    A = complex(V(:, 1), V(:, 2)); B = complex(V(:, 3), V(:, 4));
end
if startsWith(fmt, "linear"), Eth = A; Eph = B; tags = ["E_TH", "E_PH"]; reim = ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"];
elseif startsWith(fmt, "rcp"), [Eth, Eph] = circToLinear(A, B); tags = ["POL1", "POL2"]; reim = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"];
else, [Eth, Eph] = circToLinear(B, A); tags = ["POL1", "POL2"]; reim = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"]; end
if ~hasHdr
    if magPh, cols = [tags + "_dB", tags + "_deg"]; if layout == "interleaved", cols = cols([1 3 2 4]); end, else, cols = reim; end
    T.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", cols]);
end
src.userData.source = sprintf('Generic text (%s, %s)', fmt, layout); src.rawTbl = T; src.blocks = {fieldTable(c1, c2, Eth, Eph)};
end

function src = readGraspCut(fp, src)
%READGRASPCUT TICRA/GRASP *.cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks.
L = readlines(fp); L(strlength(strtrim(L)) == 0) = []; i = 1; th = {}; ph = {}; D = {}; icomp = 1; icut = 1;
while i < numel(L)
    p = sscanf(L(i+1), '%f'); assert(numel(p) >= 7, 'APAT:cut', 'Could not parse the GRASP cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6); B = reshape(sscanf(strjoin(L(i+2:i+1+n), ' '), '%f'), 2*p(7), []).';
    th{end+1, 1} = p(1) + (0:n-1).'*p(2); ph{end+1, 1} = repmat(p(4), n, 1); D{end+1, 1} = B(:, 1:4); i = i + 2 + n; %#ok<AGROW>
end
theta = vertcat(th{:}); phi = vertcat(ph{:}); D = vertcat(D{:});
if icut == 2, [theta, phi] = deal(phi, theta); end                     % ICUT=2: phi swept, theta constant
neg = theta < 0; phi(neg) = phi(neg) + 180; theta(neg) = -theta(neg);   % fold negative theta onto the opposite phi
if isscalar(unique(phi)), m = numel(theta); phi = repelem((0:10:350).', m); theta = repmat(theta, 36, 1); D = repmat(D, 36, 1); end   % single cut: body of revolution
A = complex(D(:, 1), D(:, 2)); B = complex(D(:, 3), D(:, 4));
if icomp == 2, [Eth, Eph] = circToLinear(A, B); names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; else, Eth = A; Eph = B; names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; end
src.rawTbl = array2table([theta phi D], 'VariableNames', [{'Theta', 'Phi'}, names]); src.blocks = {fieldTable(theta, phi, Eth, Eph)}; src.userData.source = 'TICRA/GRASP CUT';
end

function src = readExcelMatrix(fp, src)
%READEXCELMATRIX Matrix-template workbooks: summary sheet + fixed Etheta/Ephi and/or RHCP/LHCP gain+phase sheets (C3 origin).
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"]; lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'APAT:excel', 'Unsupported workbook: expected Etheta/Ephi and/or RHCP/LHCP gain+phase matrix sheets after the summary sheet.');
req = [circ(repmat(hasC, 1, 4)), lin(repmat(hasL, 1, 4))]; M = struct(); th = []; ph = [];
for s = req
    [t, p, X] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, s), 1)));
    if isempty(th), th = t; ph = p; else, assert(isequal(size(X), [numel(th) numel(ph)]) && max(abs(t - th)) < 1e-9 && max(abs(p - ph)) < 1e-9, 'APAT:excel', 'All matrix sheets must share one theta/phi grid.'); end
    M.(char(s)) = X;
end
if hasL, Eth = magPhase(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = magPhase(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees);
else, [Eth, Eph] = circToLinear(magPhase(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), magPhase(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees)); end
[P, T] = meshgrid(ph, th); src.blocks = {fieldTable(T, P, Eth, Eph)}; raw = src.blocks{1};
for s = req, raw.(char(s)) = M.(char(s))(:); end
src.rawTbl = raw; [src.userData.summary, src.userData.frequencyMHz] = readSummary(fp, sheets(1));
kinds = ["Format 1 (Eth/Eph)", "Format 2 (RHCP/LHCP)", "Format 3 (Eth/Eph + RHCP/LHCP)"]; src.userData.source = char("Excel Matrix " + kinds(hasL + 2*hasC));
end

function [theta, phi, X] = readMatrixSheet(fp, sheet)
% readcell keeps worksheet coordinates (readmatrix would auto-trim and break the C3-origin convention).
C = readcell(fp, 'Sheet', char(sheet)); assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'APAT:excel', 'Sheet "%s" has no C3-origin matrix.', sheet);
isnum = @(x) isnumeric(x) && isscalar(x) && isfinite(x); pm = cellfun(isnum, C(2, 3:end)); tm = cellfun(isnum, C(3:end, 2));
np = find(~pm, 1) - 1; if isempty(np), np = numel(pm); end, nt = find(~tm, 1) - 1; if isempty(nt), nt = numel(tm); end
assert(np > 0 && nt > 0 && ~any(pm(np+1:end)) && ~any(tm(nt+1:end)), 'APAT:excel', 'Sheet "%s": theta/phi axes must be contiguous numeric ranges.', sheet);
phi = cell2mat(C(2, 3:2+np)).'; theta = cell2mat(C(3:2+nt, 2)); D = C(3:2+nt, 3:2+np);
assert(all(cellfun(isnum, D), 'all'), 'APAT:excel', 'Sheet "%s" contains non-numeric or missing matrix samples.', sheet); X = cell2mat(D);
assert(all(diff(theta) > 0) && all(diff(phi) > 0) && theta(1) >= -1e-9 && theta(end) <= 180 + 1e-9 && phi(1) >= -1e-9 && phi(end) < 360 + 1e-9, ...
    'APAT:excel', 'Sheet "%s": axes must be strictly increasing within theta 0..180 and phi 0..360.', sheet);
end

function [rows, fMHz] = readSummary(fp, sheet)
%READSUMMARY Generic label/value scan of the template summary sheet (column B labels, first value in C:E).
rows = cell(0, 2); fMHz = NaN;
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
for r = 1:size(C, 1)
    lab = C{r, 2}; if ~(ischar(lab) || isstring(lab)) || strlength(strtrim(string(lab))) == 0, continue; end
    val = '';
    for c = 3:min(5, size(C, 2))
        x = C{r, c}; if isempty(x) || (~ischar(x) && any(ismissing(x))), continue; end
        if isnumeric(x), val = num2str(x); else, val = char(string(x)); end, break
    end
    if isempty(val), continue; end
    lab = strtrim(regexprep(char(string(lab)), ':\s*$', '')); rows(end+1, :) = {['Excel: ' lab], val}; %#ok<AGROW>
    if isnan(fMHz) && contains(lower(lab), 'simulation freq'), fMHz = str2double(val); end
end
end

function writeTable(T, fp)
if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
end

%% ====================================================================== math kernel (UI independent)
function T = normalizePattern(T)
%NORMALIZEPATTERN Map angles to the canonical sphere: theta [0,180], phi [0,360] with the phi seam closed (0 duplicated at 360).
th = T.Theta;
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, T.Theta = 90 - th;                                   % elevation convention
    else, m = th < 0; T.Theta(m) = -th(m); T.Phi(m) = T.Phi(m) + 180; end                   % negative polar angle
end
T.Theta = mod(T.Theta, 360); over = T.Theta > 180; T.Theta(over) = 360 - T.Theta(over); T.Phi(over) = T.Phi(over) + 180;
num = varfun(@isnumeric, T, 'OutputFormat', 'uniform'); T{:, num} = round(T{:, num}, 5);   % deterministic 5-decimal grid (kills seam round-off)
T.Phi = mod(T.Phi, 360);
[~, k] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(k, :);
seam = T(abs(T.Phi) < 1e-9, :); seam.Phi(:) = 360; T = [T; seam];
end

function [P, info] = calcPattern(S, prm)
%CALCPATTERN Canonical fields -> processed table (gain, signed AR, polarization, PLF, EIRP/PFD/E-field).
ud = S.Properties.UserData; info = struct('pol', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
if isfield(ud, 'isGainOnly') && ud.isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + prm.GainLoss_dB; end, return
end
Eth = complex(S.Re_Eth, S.Im_Eth)*prm.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph)*prm.FieldScale;
Er = (Eth + 1i*Eph)/sqrt(2); El = (Eth - 1i*Eph)/sqrt(2); [mT, mP, mR, mL] = deal(abs(Eth), abs(Eph), abs(Er), abs(El));
total = 10*log10(max(mT.^2 + mP.^2, eps));
% Dominant polarization from mean component power: drives co/cross ordering, the label and the Auto Rx sense.
pw = [mean(mT.^2, 'omitnan'), mean(mP.^2, 'omitnan'), mean(mR.^2, 'omitnan'), mean(mL.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = char("Circular (" + replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]) + ")");
elseif pw(1) >= pw(2), info.pol = 'Linear (Vertical)'; else, info.pol = 'Linear (Horizontal)'; end
% Signed axial ratio (+ RHCP sense, − LHCP sense); equal circular components are the linear limit → −100 dB floor.
d = mR - mL; sense = sign(d); sense(~isfinite(d)) = 0; ar = (mR + mL) ./ max(abs(d), eps);
arDB = min(20*log10(ar), 250) .* sense; arDB(isfinite(d) & abs(d) <= eps*max(mR + mL, 1)) = -100;
% Polarization loss factor vs. an incident wave of axial ratio Rw (worst-case tilt, cos 2Δτ = −1).
switch prm.RxMode, case "RHCP", ws = 1; case "LHCP", ws = -1; otherwise, ws = 2*(info.pairs.Circular(1) == "E_RCP") - 1; end
ra = ar .* sense; ra(sense == 0) = 1e12; rw = ws*10^(prm.RxAR_dB/20);
plfDB = 10*log10(min(max(0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1)) ./ (2*(ra.^2 + 1)*(rw^2 + 1)), eps), 1));
eirp = prm.Pt_dBW + total; W = 10.^(eirp/10); dB = @(m) 20*log10(max(m, eps)); ph = @(E) rad2deg(angle(E));
P = table(S.Theta, S.Phi, total, arDB, dB(mR), dB(mL), plfDB, total + plfDB, dB(mT), dB(mP), ph(Eth), ph(Eph), ph(Er), ph(El), eirp, W/(4*pi*prm.R_m^2), sqrt(30*W)/prm.R_m, ...
    'VariableNames', {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', 'PLF_dB', 'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
P.Properties.UserData = ud;
end

function R = resampleCanonical(S, step)
%RESAMPLECANONICAL Resample canonical source data onto a uniform STEP° grid with a closed phi seam.
% Field columns (Re/Im) are interpolated directly; gain-like dB columns through linear power.
th = S.Theta; keep = abs(S.Phi - 360) > 1e-9; idx = find(keep);                              % the phi=0 sample is authoritative
[~, k] = unique([th(keep) mod(S.Phi(keep), 360)], 'rows', 'stable'); idx = idx(k); th = th(idx); ph = mod(S.Phi(idx), 360);
tq = (0:step:180).'; pq = unique([(0:step:360).'; 360]); [PQ, TQ] = meshgrid(pq, tq); R = table(TQ(:), PQ(:), 'VariableNames', {'Theta', 'Phi'});
ut = unique(th); up = unique(ph); [~, it] = ismember(th, ut); [~, ip] = ismember(ph, up); lin = sub2ind([numel(ut) numel(up)], it, ip);
regular = numel(lin) == numel(ut)*numel(up) && numel(unique(lin)) == numel(lin);
names = S.Properties.VariableNames(3:end); isField = all(ismember({'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}, names));
for n = names
    v = double(S.(n{1})(idx)); gainLike = ~isField;                                                  % gain-only tables: every data column is a dB gain
    if gainLike, v = 10.^(v/10); end
    if regular
        G = nan(numel(ut), numel(up)); G(lin) = v; [PG, TG] = meshgrid(up, ut);
        if up(end) < 360 - 1e-9, PG(:, end+1) = 360; TG(:, end+1) = ut; G(:, end+1) = G(:, 1); end        % periodic closure
        q = interp2(PG, TG, G, PQ, TQ, 'linear', NaN); miss = isnan(q);
        if any(miss, 'all'), nn = interp2(PG, TG, G, PQ, TQ, 'nearest', NaN); q(miss) = nn(miss); end
    else
        F = scatteredInterpolant(ph, th, v, 'linear', 'nearest'); q = F(PQ, TQ);
    end
    if gainLike, q = 10*log10(max(q, realmin)); end
    R.(n{1}) = q(:);
end
R.Properties.UserData = S.Properties.UserData;
end

function w = solidWeights(theta, phi)
%SOLIDWEIGHTS Exact solid angle of each uniform sample cell; the duplicated phi=360 seam gets zero weight.
ts = gridStep(theta); ps = gridStep(mod(phi, 360)); if ~isfinite(ts), ts = 180; end, if ~isfinite(ps), ps = 360; end
w = (cosd(max(theta - ts/2, 0)) - cosd(min(theta + ts/2, 180)))*deg2rad(ps); w(abs(phi - 360) < 1e-9) = 0;
end

function s = gridStep(v)
%GRIDSTEP Smallest positive spacing between distinct finite values (NaN if fewer than two).
d = diff(unique(v(isfinite(v)))); d = d(d > 1e-9); if isempty(d), s = NaN; else, s = min(d); end
end

function pk = resolvePeak(v, pct, excess)
%RESOLVEPEAK Peak policy: accept the raw maximum unless it exceeds the P<pct> level by more than EXCESS dB
% (isolated spike); then the highest sample at/below that level is the effective peak. Toolbox free.
pk = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(v)), 'wasAdjusted', false);
f = isfinite(v); if ~any(f), return; end
[pk.rawValue, pk.rawIndex] = max(v, [], 'omitnan'); pk.value = pk.rawValue; pk.index = pk.rawIndex;
s = sort(v(f)); n = numel(s); level = s(end); if n > 1, level = interp1(((1:n) - 0.5)/n, s, pct/100, 'linear', s(end)); end
if pk.rawValue > level + excess
    out = f & v > level; cand = v; cand(out | ~f) = -Inf;
    if any(f & ~out), [pk.value, pk.index] = max(cand); pk.outlierMask = out; pk.wasAdjusted = true; end
end
end

function [pk, axisIndex] = calcOrientation(T, w, col, axes6, pct, excess)
%CALCORIENTATION Peak of COL and the principal axis whose 45° cone captures the most solid-angle-weighted power.
g = chooseGain(T, col); pk = resolvePeak(g, pct, excess); if pk.wasAdjusted, g(pk.outlierMask) = NaN; end
sw = 10.^((g - pk.value)/10) .* w; sw(~isfinite(sw)) = 0;
A = [sind(axes6.theta(:)).*cosd(axes6.phi(:)), sind(axes6.theta(:)).*sind(axes6.phi(:)), cosd(axes6.theta(:))];
V = [sind(T.Theta).*cosd(T.Phi), sind(T.Theta).*sind(T.Phi), cosd(T.Theta)];
[~, axisIndex] = max(sw.' * double(V*A.' >= cosd(45)));
end

function m = calcMetrics(T, w, axes6, k, pct, excess)
%CALCMETRICS Scalar figures of merit from the total-gain column (physical angles).
g = chooseGain(T, 'E_Total_dB'); pk = resolvePeak(g, pct, excess); gm = g; if pk.wasAdjusted, gm(pk.outlierMask) = NaN; end
i = pk.index; pTh = T.Theta(i); pPh = T.Phi(i); integ = sum(10.^(gm/10) .* w, 'omitnan');
eff = 100*integ/(4*pi); if eff < 0 || eff > 100, eff = NaN; end
[~, back] = min(cosd(T.Theta)*cosd(pTh) + sind(T.Theta)*sind(pTh).*cosd(T.Phi - pPh));
ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(i); end
[eA, eR] = cutRows(T, 'Theta', axes6.phi(k));                                                  % E-plane contains the boresight axis
if axes6.theta(k) == 90, [hA, hR] = cutRows(T, 'Phi', 90); else, [hA, hR] = cutRows(T, 'Theta', 90); end
m = struct('PeakGain_dB', pk.value, 'PeakTheta_deg', pTh, 'PeakPhi_deg', pPh, 'HPBW_EPlane_deg', calcHPBW(eA, g(eR)), 'HPBW_HPlane_deg', calcHPBW(hA, g(hR)), ...
    'FrontBack_dB', pk.value - g(back), 'PeakDirectivity_dB', 10*log10(max(4*pi*10^(pk.value/10)/max(integ, eps), eps)), 'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', ar);
end

function [ang, rows, fixed, snapped] = cutRows(T, type, req)
%CUTROWS Rows of one full-circle cut (snapped to the nearest sampled plane) and their circle angles.
% Phi cut: fixed theta, angle = phi. Theta cut: fixed phi plus the opposite half-plane, angle = theta / 360−theta.
ok = T.Phi < 360 - 1e-9;                                                                        % skip the duplicated seam
if strcmp(type, 'Phi')
    th = unique(T.Theta); [d, k] = min(abs(th - req)); fixed = th(k); rows = find(abs(T.Theta - fixed) < 1e-9); [ang, o] = sort(T.Phi(rows)); rows = rows(o);
else
    ph = unique(mod(T.Phi(ok), 360)); req = mod(req, 360); [d, k] = min(abs(mod(ph - req + 180, 360) - 180)); fixed = ph(k);
    [~, j] = min(abs(mod(ph - fixed, 360) - 180)); opp = ph(j);
    r1 = find(ok & abs(T.Phi - fixed) < 1e-9); [~, o] = sort(T.Theta(r1)); r1 = r1(o);
    r2 = find(ok & abs(T.Phi - opp) < 1e-9 & abs(T.Theta - 180) > 1e-9); [~, o] = sort(T.Theta(r2), 'descend'); r2 = r2(o);
    rows = [r1; r2]; ang = [T.Theta(r1); 360 - T.Theta(r2)];
end
snapped = d > 1e-9;
end

function [bw, lo, hi] = calcHPBW(ang, g, pkGain, pkAng)
%CALCHPBW Half-power beamwidth of a circular cut with linear interpolation of the −3 dB crossings.
[bw, lo, hi] = deal(NaN); v = isfinite(ang) & isfinite(g); ang = ang(v); g = g(v); if numel(g) < 3, return; end
if nargin < 4 || isempty(pkGain) || isempty(pkAng), [pkGain, i] = max(g); pkAng = ang(i); end
half = pkGain - 3; [ra, o] = sort(mod(ang - pkAng + 180, 360) - 180); rg = g(o);
L = find(ra < 0 & rg <= half, 1, 'last'); Rr = find(ra > 0 & rg <= half, 1, 'first');
if isempty(L) || isempty(Rr) || L + 1 > numel(rg) || Rr - 1 < 1, return; end
cross = @(a, b) ra(a) + (ra(b) - ra(a))*(half - rg(a))/(rg(b) - rg(a));
if rg(L+1) == rg(L) || rg(Rr-1) == rg(Rr), return; end
lc = cross(L, L+1); rc = cross(Rr, Rr-1); lo = pkAng + lc; hi = pkAng + rc; bw = rc - lc;
end

function cov = coverageCCDF(gain, mask, thr, w)
%COVERAGECCDF Coverage(T) [%] = 100 · Σ I(G_i > T)·Ω_i / Σ Ω_i over the region MASK, for every threshold at once.
gain = double(gain(:)); w = double(w(:)); thr = double(thr(:)); ok = logical(mask(:)) & isfinite(gain) & isfinite(w) & w >= 0;
cov = zeros(size(thr)); total = sum(w(ok)); if total <= 0, return; end
cov = 100*(w(ok).' * double(gain(ok) > thr.')).' / total;
end

function b = displayRange(v, pct, excess)
%DISPLAYRANGE 50-dB window ending at the policy peak rounded up to a multiple of 5 dB.
pk = resolvePeak(double(v(:)), pct, excess); if ~isfinite(pk.value), b = [-50 0]; return; end
hi = min(100, ceil(pk.value/5)*5); b = [max(-250, hi - 50), hi];
end

function r = clampRange(v, bounds)
%CLAMPRANGE Sorted, clamped two-element range with at least one unit of span.
v = sort(double(v(:).')); if numel(v) < 2 || any(~isfinite(v(1:2))), r = bounds; return; end
r = [max(bounds(1), v(1)), min(bounds(2), v(2))];
if diff(r) < 1, r(2) = min(bounds(2), r(1) + 1); r(1) = max(bounds(1), r(2) - 1); end
end

function setBounded(h, value, limits, full)
%SETBOUNDED Set Value then narrow Limits of sliders/spinners without ever leaving Value outside Limits.
set(h, 'Limits', full); set(h, 'Value', value); set(h, 'Limits', limits);
end

function t = axisTicks(lim, step)
%AXISTICKS Ticks at multiples of STEP inside LIM, always including both ends (empty when too dense).
t = []; if ~isfinite(step) || step <= 0 || diff(lim) <= 0, return; end
t = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)], 'stable'); if numel(t) > 60, t = []; end
end

function g = chooseGain(T, col)
%CHOOSEGAIN Requested column, else E_Total_dB, else the first data column.
vars = string(T.Properties.VariableNames); c = string(col);
if ~any(vars == c), c = "E_Total_dB"; end, if ~any(vars == c), c = vars(3); end
g = T.(char(c));
end

function [cols, labels] = componentList(T)
%COMPONENTLIST Plottable component columns with user-facing labels.
avail = string(T.Properties.VariableNames(3:end)); ud = T.Properties.UserData;
if isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly, cols = avail; labels = avail; return; end
names = ["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "AR_dB", "Gain_PolCorrected_dB"];
labels = ["Total Gain", "Etheta Gain", "Ephi Gain", "RHCP Gain", "LHCP Gain", "Axial Ratio", "Polarized Gain"];
m = ismember(names, avail); cols = names(m); labels = labels(m);
end

function c = pickComponent(prev, cols)
c = string(prev); if ~any(cols == c), c = "E_Total_dB"; end, if ~any(cols == c), c = cols(1); end, c = char(c);
end

function s = fmtNum(v, prec)
%FMTNUM Compact number text: up to two decimals without trailing zeros, or exactly PREC decimals.
if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); else, s = sprintf('%.*f', prec, v); end
end