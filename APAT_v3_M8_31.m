classdef APAT_v3_M8_31 < matlab.apps.AppBase  %1732-lines 
% APAT v3 M8 — Antenna Pattern Analyzer Tool (concise-architecture release).
%
%   One-directional data pipeline; every stage rebuilds everything downstream:
%
%     file ──read──▶ src.blocks ──normalize──▶ stdTbl ──calcPattern──▶ patTbl
%          ──resample(step)──▶ baseTbl ──span──▶ viewTbl + phys ──▶ plots / tables / coverage
%
%   All physics (solid angle, boresight, metrics, cuts, coverage) is evaluated on
%   PHYSICAL angles (phys.theta ∈ [0,180], phys.phi ∈ [0,360]).  The θ/φ display
%   conventions (elevation / signed φ) only affect axes, tables and exports.
%
%   Widgets live in the `ui` struct (app.ui.loadBtn, app.ui.fullAx{k}, ...).
%   Every UI callback is wrapped by cb() — one error boundary for the whole app.

    properties (Access = public)
        UIFigure matlab.ui.Figure
        ui struct = struct()            % all widgets, addressed by short name
    end

    properties (Access = private)
        src struct = struct()           % rawTbl, blocks, freqs, meta, path, folder, base, name, shown
        stdTbl table                    % canonical source (θ 0..180, φ 0..360 + closing seam)
        patTbl table                    % processed pattern at native resolution
        baseTbl table                   % processed pattern at the selected step (canonical angles)
        viewTbl table                   % baseTbl materialized in the display convention
        phys struct = struct()          % theta, phi, omega (per viewTbl row) + grid topology/geometry
        viewRev double = 0              % incremented whenever viewTbl changes
        peak struct = struct()          % resolved peak of the displayed component
        metrics struct = struct()       % total-gain antenna metrics
        boresight double = 1            % index into Axes
        pol char = 'n/a'
        pairs struct = struct('Linear', ["E_TH","E_PH"], 'Circular', ["E_RCP","E_LCP"])
        lim struct = struct('full', [-40 10], 'cut', [-40 10], 'gain', [-40 10])
        cov struct = struct('runID', 0, 'presetKey', "", 'xInit', false)
        defaults struct = struct()
        statusTimer = []
        dlg = []
        closing logical = false
    end

    properties (Constant, Access = private)
        Release = 'APAT v3 M8'
        Range = [-250 100]              % absolute dB range of every range control
        PeakPct = 99.99                 % peak policy: raw peak accepted unless it exceeds
        PeakExcess = 6                  %   the P99.99 percentile by more than 6 dB
        Axes = struct('labels', {{'+Z','-Z','+X','-X','+Y','-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        Labels = struct('E_Total_dB', 'Total Gain', 'E_TH_dB', 'Etheta Gain', 'E_PH_dB', 'Ephi Gain', 'E_RCP_dB', 'RHCP Gain', ...
            'E_LCP_dB', 'LHCP Gain', 'AR_dB', 'Axial Ratio', 'Gain_PolCorrected_dB', 'Polarized Gain')
        Hidden = {'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'}
        TextFormats = {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
            '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
            '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}
        TextCodes = {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'}
    end

    %% ------------------------------------------------------------------ lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_31
            app.src = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, 'meta', defaultMeta(struct()), ...
                'path', '', 'folder', '', 'base', '', 'name', '', 'shown', false);
            app.build();
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @startup);
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.closing, return; end
            app.closing = true;
            app.stopTimer(); app.endBusy();
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end

        function report = runSelfTest(app)
            %RUNSELFTEST Deterministic numerical smoke checks (no UI interaction).
            [PH, TH] = meshgrid(0:30:330, 0:30:180);
            T = table(TH(:), PH(:), 10*cosd(TH(:)).^2, 'VariableNames', {'Theta','Phi','E_Total_dB'});
            w = solidWeights(T.Theta, T.Phi);
            pk = resolvePeak(T.E_Total_dB, app.PeakPct, app.PeakExcess);
            k = boresightOf(T.Theta, T.Phi, T.E_Total_dB, w, pk, app.Axes);
            [P2, T2] = meshgrid(0:2:358, 0:2:180); A = 12*cosd(T2).^2 - 0.5*sind(P2).^2;
            R = resampleCanonical(table(T2(:), P2(:), A(:), 'VariableNames', {'Theta','Phi','E_Total_dB'}), 1);
            native = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0 & R.Phi < 360;
            err = max(abs(R.E_Total_dB(native) - (12*cosd(R.Theta(native)).^2 - 0.5*sind(R.Phi(native)).^2)));
            spike = repmat(0.02, 1e5, 1); spike(1) = 10.02; sp = resolvePeak(spike, app.PeakPct, app.PeakExcess);
            ffdFile = [tempname '.ffd']; writelines(["0 180 3"; "-180 180 3"; compose("%d 0 0 1", (1:9).')], ffdFile);
            cleaner = onCleanup(@() delete(ffdFile)); ffd = readSource(ffdFile, "ffd");
            ang = (0:359).'; [bw, ~, ~] = calcHPBW(ang, -3*((ang - 90)/20).^2);
            checks = struct( ...
                'SolidAngle', abs(sum(w) - 4*pi) < 1e-9, ...
                'Orientation', k == 1, ...
                'Resampling', height(R) == 181*361 && all(isfinite(R.E_Total_dB)), ...
                'NumericalEquivalence', err < 1e-10, ...
                'PeakWindow', isequal(peakWindow([3.2; -250; -17], app.PeakPct, app.PeakExcess), [-45 5]), ...
                'IsolatedSpike', sp.wasAdjusted && abs(sp.value - 0.02) < 1e-12 && sp.rawIndex == 1, ...
                'FFDReader', strcmp(ffd.meta.source, 'HFSS FFD') && isscalar(ffd.blocks) && height(ffd.blocks{1}) == 9, ...
                'HPBW', abs(bw - 40) < 1e-6, ...
                'ARTheme', all(cellfun(@isARName, {'AR','AR_dB','AR dB','Axial Ratio','Axial_Ratio'})), ...
                'Coverage', abs(coverageCCDF([0;10;20;30], true(4,1), 15, ones(4,1)) - 50) < 1e-12);
            flags = cell2mat(struct2cell(checks)); report = checks; report.pass = all(flags);
            if ~report.pass
                names = fieldnames(checks);
                error('apat:test:SelfTestFailed', 'Self-test failed: %s', strjoin(names(~flags), ', '));
            end
        end
    end

    %% ------------------------------------------------------------------ UI construction
    methods (Access = private)
        function h = add(app, name, h, row, col)
            % Register a widget under a short name and place it in its grid.
            if nargin > 3, h.Layout.Row = row; h.Layout.Column = col; end
            if ~isempty(name), app.ui.(name) = h; end
        end

        function h = lbl(app, parent, text, row, col)
            h = app.add('', uilabel(parent, 'Text', text, 'HorizontalAlignment', 'right'), row, col);
        end

        function f = cb(app, fn)
            % Wrap a callback in the single application error boundary.
            f = @(src, evt) app.guarded(fn, src, evt);
        end

        function guarded(app, fn, src, evt)
            try
                fn(src, evt);
            catch ME
                if app.closing, return; end
                if strcmp(ME.identifier, 'APAT:Cancelled')
                    app.say(1, 'Operation cancelled by user.', true); return
                end
                where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
                uialert(app.UIFigure, [ME.message where], 'APAT Error', 'Icon', 'error');
            end
        end

        function dd = fmtDropdown(app, parent, fn)
            dd = uidropdown(parent, 'Items', app.TextFormats, 'ItemsData', app.TextCodes, 'Value', 'gain', 'Visible', 'off', ...
                'ValueChangedFcn', fn, 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.');
        end

        function build(app)
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.Release], 'Visible', 'off', ...
                'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) delete(app));
            root = uigridlayout(app.UIFigure, [1 1]);
            app.ui.tabs = app.add('', uitabgroup(root), 1, 1);
            app.ui.mainTab = uitab(app.ui.tabs, 'Title', 'Process Pattern 📡');
            app.ui.covTab = uitab(app.ui.tabs, 'Title', 'Compute Coverage 📈');
            app.buildMain(app.ui.mainTab);
            app.buildCoverage(app.ui.covTab);
            app.UIFigure.Visible = 'on';
        end

        function buildMain(app, tab)
            on = @(f) app.cb(f); R = app.Range; nb = @(n) repmat(char(160), 1, n);
            G = uigridlayout(tab, [5 14]); G.ColumnWidth = repmat({'1x'}, 1, 14); G.RowHeight = {'fit', '2x', 'fit', '1x', 'fit'};

            % --- Inputs & parameters --------------------------------------------------
            P = uigridlayout(app.add('paramPanel', uipanel(G, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 14]), [3 14]);
            P.ColumnWidth = repmat({'1x'}, 1, 14); P.RowHeight = {'1x', '1x', '1x'};
            app.lbl(P, 'Input Pattern:', 1, 1);
            app.add('path', uieditfield(P, 'text'), 1, [2 8]);
            app.add('ffdLbl', uilabel(P, 'Text', 'FFD Freq:', 'HorizontalAlignment', 'right', 'Visible', 'off'), 1, 9);
            app.add('ffd', uidropdown(P, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', on(@(~, ~) app.onFFD())), 1, 10);
            app.add('loadBtn', uibutton(P, 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', on(@(~, ~) app.onLoad())), 1, [11 12]);
            app.add('processBtn', uibutton(P, 'Text', '⚙️ Process', 'ButtonPushedFcn', on(@(~, ~) app.onProcess())), 1, [13 14]);
            app.add('resetBtn', uibutton(P, 'Text', 'Reset Params', 'ButtonPushedFcn', on(@(~, ~) app.onResetParams())), 2, [1 3]);
            app.ui.fmtLbl = app.lbl(P, 'Format:', 2, [4 5]); app.ui.fmtLbl.Visible = 'off';
            app.add('fmt', app.fmtDropdown(P, on(@(~, ~) app.onFormat())), 2, [6 8]);
            app.add('step', uidropdown(P, 'Items', {'STEP', 'STEP: 1°'}, 'Visible', 'off', 'Enable', 'off', 'ValueChangedFcn', on(@(~, ~) app.run("step"))), 2, [9 10]);
            app.add('exportBtn', uibutton(P, 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', on(@(~, ~) app.exportResults())), 2, [11 12]);
            app.add('uanBtn', uibutton(P, 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', on(@(~, ~) app.exportUAN())), 2, [13 14]);
            app.ui.rxLbl = app.lbl(P, 'Rw Sense', 3, 1);
            app.add('rx', uidropdown(P, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Editable', 'on'), 3, 2);
            app.ui.rwLbl = app.lbl(P, 'Rw (dB)', 3, 3);
            app.add('rw', uispinner(P, 'Value', 6), 3, 4);
            app.ui.lossLbl = app.lbl(P, 'Loss (−) / Gain (+) dB', 3, 5);
            app.add('loss', uispinner(P, 'Step', 0.1), 3, 6);
            app.ui.ptLbl = app.lbl(P, 'Tx Pwr (Pt)', 3, 7);
            app.add('pt', uispinner(P), 3, 8);
            app.add('ptUnit', uidropdown(P, 'Items', {'dBW', 'dBm', 'Watts'}), 3, 9);
            app.ui.rLbl = app.lbl(P, 'Distance', 3, 10);
            app.add('r', uispinner(P, 'Value', 1), 3, 11);
            app.add('rUnit', uidropdown(P, 'Items', {'m', 'km'}), 3, 12);
            app.add('coverageBtn', uibutton(P, 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', on(@(~, ~) app.toCoverage())), 3, [13 14]);

            % --- Full antenna pattern: five tabs built by one loop ---------------------
            pnl = app.add('fullPanel', uipanel(G, 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [1 6]);
            tg = app.add('fullTabs', uitabgroup(uigridlayout(pnl, [1 1]), 'SelectionChangedFcn', on(@(~, ~) app.syncTips())), 1, 1);
            titles = {'Contour Plot', 'Circular Contour Plot', '3D Spherical Plot', '3D Polar Plot', '3D Surface Plot'};
            [app.ui.fullTab, app.ui.fullMax, app.ui.fullSlider, app.ui.fullMin] = deal(gobjects(1, 5)); app.ui.fullAx = cell(1, 5);
            for k = 1:5
                t = uitab(tg, 'Title', titles{k}); g = uigridlayout(t, [3 2]); g.ColumnWidth = {'fit', '1x'}; g.RowHeight = {'fit', '1x', 'fit'};
                if k == 2, ax = polaraxes(g); else, ax = uiaxes(g); end
                ax.Layout.Row = [1 3]; ax.Layout.Column = 2;
                app.ui.fullTab(k) = t; app.ui.fullAx{k} = ax;
                app.ui.fullMax(k) = app.add('', uispinner(g, 'Limits', R, 'Value', 10, 'Step', 5, 'ValueChangedFcn', on(@(s, ~) app.setRange("full", [app.lim.full(1) s.Value]))), 1, 1);
                app.ui.fullSlider(k) = app.add('', uislider(g, 'range', 'Limits', R, 'Value', [-40 10], 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', on(@(s, ~) app.setRange("full", s.Value))), 2, 1);
                app.ui.fullMin(k) = app.add('', uispinner(g, 'Limits', R, 'Value', -40, 'Step', 5, 'ValueChangedFcn', on(@(s, ~) app.setRange("full", [s.Value app.lim.full(2)]))), 3, 1);
            end

            % --- Pattern cut ------------------------------------------------------------
            pnl = app.add('cutPanel', uipanel(G, 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [7 12]);
            tg = app.add('cutTabs', uitabgroup(uigridlayout(pnl, [1 1]), 'SelectionChangedFcn', on(@(~, ~) app.syncTips())), 1, 1);
            app.ui.cutTabPolar = uitab(tg, 'Title', 'Polar Cut Plot');
            g = uigridlayout(app.ui.cutTabPolar, [4 4]); g.ColumnWidth = {'fit', '0.26x', '1x', '0.23x'}; g.RowHeight = {'fit', '0.25x', '1x', 'fit'};
            app.add('cutMax', uispinner(g, 'Limits', R, 'Value', 10, 'Step', 5, 'ValueChangedFcn', on(@(s, ~) app.setRange("cut", [app.lim.cut(1) s.Value]))), 1, 1);
            app.add('cutSlider', uislider(g, 'range', 'Limits', R, 'Value', [-40 10], 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', on(@(s, ~) app.setRange("cut", s.Value))), [2 3], 1);
            app.add('cutMin', uispinner(g, 'Limits', R, 'Value', -40, 'Step', 5, 'ValueChangedFcn', on(@(s, ~) app.setRange("cut", [s.Value app.lim.cut(2)]))), 4, 1);
            app.add('pax', polaraxes(g, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise'), [1 4], 3);
            app.add('hpbwBtn', uibutton(g, 'state', 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', on(@(~, ~) app.onCut())), 1, 4);
            app.add('hpbwLbl', uilabel(g, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold'), 2, 4);
            e = app.add('ecut', uigridlayout(g, [3 1]), 3, 4);
            app.add('chkTot', uicheckbox(e, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', on(@(~, ~) app.onCut())), 1, 1);
            app.add('chkA', uicheckbox(e, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', on(@(~, ~) app.onCut())), 2, 1);
            app.add('chkB', uicheckbox(e, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', on(@(~, ~) app.onCut())), 3, 1);
            app.add('exportCutBtn', uibutton(g, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', on(@(~, ~) app.exportCut())), 4, 4);
            app.ui.cutTabRect = uitab(tg, 'Title', 'Rectangular Cut Plot');
            app.add('rax', uiaxes(uigridlayout(app.ui.cutTabRect, [1 1]), 'Box', 'on'), 1, 1);
            xlabel(app.ui.rax, 'Theta (degree)'); ylabel(app.ui.rax, 'Magnitude (dB)');

            % --- Data tables --------------------------------------------------------------
            app.add('outFilter', uidropdown(G, 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Visible', 'off', 'ValueChangedFcn', on(@(~, ~) app.filterOutput(true))), 3, [13 14]);
            dt = app.add('dataTabs', uitabgroup(G, 'Visible', 'off'), 4, [1 14]);
            t = uitab(dt, 'Title', 'Results 📤', 'ButtonDownFcn', @(~, ~) set(app.ui.outFilter, 'Visible', 'on'));
            app.add('tblOut', uitable(uigridlayout(t, [1 1]), 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnRearrangeable', 'on'), 1, 1);
            t = uitab(dt, 'Title', 'Input 📥');
            app.add('tblIn', uitable(uigridlayout(t, [1 1]), 'ColumnSortable', true, 'RowName', 'numbered'), 1, 1);
            t = uitab(dt, 'Title', 'Metadata 📋');
            app.add('tblMeta', uitable(uigridlayout(t, [1 1]), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {}), 1, 1);

            % --- Plot control ------------------------------------------------------------
            C = uigridlayout(app.add('ctrlPanel', uipanel(G, 'Title', 'Plot Control 🎨', 'Visible', 'off'), 2, [13 14]), [15 2]);
            C.RowHeight = repmat({'fit'}, 1, 15);
            app.lbl(C, 'Component', 1, 1);
            app.add('comp', uidropdown(C, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', on(@(~, ~) app.refreshView(true, false))), 1, 2);
            app.lbl(C, 'Cut type', 2, 1);
            app.add('cutType', uidropdown(C, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', on(@(~, ~) app.onCut(true))), 2, 2);
            app.lbl(C, 'Cut value', 3, 1);
            app.add('cutValue', uispinner(C, 'Limits', [-360 360], 'ValueChangedFcn', on(@(~, ~) app.onCut())), 3, 2);
            app.lbl(C, 'Cut fields', 4, 1);
            app.add('basis', uidropdown(C, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Enable', 'off', 'UserData', true, 'ValueChangedFcn', on(@(~, ~) app.onBasis())), 4, 2);
            app.lbl(C, 'Colorbar max', 5, 1); app.add('cmax', uispinner(C, 'Limits', R, 'Value', 10), 5, 2);
            app.lbl(C, 'Colorbar min', 6, 1); app.add('cmin', uispinner(C, 'Limits', R, 'Value', -40), 6, 2);
            app.lbl(C, 'Colorbar step', 7, 1);
            app.add('cstep', uispinner(C, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', on(@(~, ~) app.setRange("full", app.lim.full))), 7, 2);
            app.lbl(C, 'Adjust Colorbar', 8, 1);
            app.add('applyBtn', uibutton(C, 'Text', 'Apply', 'Tooltip', 'Apply to full-pattern and cut plots.', 'ButtonPushedFcn', on(@(~, ~) app.setRange("all", [app.ui.cmin.Value app.ui.cmax.Value]))), 8, 2);
            app.lbl(C, '3D view', 9, 1);
            app.add('view3d', uidropdown(C, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'ValueChangedFcn', on(@(~, ~) app.apply3DViews())), 9, 2);
            app.add('phiSpan', uiswitch(C, 'slider', 'Items', {['φ span: 0° to 360°' nb(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'ValueChangedFcn', on(@(~, ~) app.run("span"))), 10, [1 2]);
            app.add('thSpan', uiswitch(C, 'slider', 'Items', {'θ span: 0° to 180°', ['−90° to 90°' nb(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'ValueChangedFcn', on(@(~, ~) app.run("span"))), 11, [1 2]);
            app.add('eh', uiswitch(C, 'slider', 'Items', {[nb(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E', 'H'}, 'ValueChangedFcn', on(@(~, ~) app.onPlane())), 12, [1 2]);
            app.add('overlay', uicheckbox(C, 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', on(@(~, ~) app.refreshOverlay())), 13, [1 2]);
            app.add('pob', uicheckbox(C, 'Text', 'Annotate POB', 'ValueChangedFcn', on(@(~, ~) app.syncTips())), 14, [1 2]);
            app.add('hpbwTips', uicheckbox(C, 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', on(@(~, ~) app.syncTips())), 15, [1 2]);
            app.add('status', uilabel(G, 'Text', 'Ready -- load an antenna pattern file to begin 🚀', 'Interpreter', 'html'), 5, [1 14]);
        end

        function buildCoverage(app, tab)
            on = @(f) app.cb(f); R = app.Range;
            G = uigridlayout(tab, [3 5]); G.ColumnWidth = {'0.75x', 'fit', '1x', 'fit', '1x'}; G.RowHeight = {'0.25x', '1x', 'fit'};
            P = uigridlayout(app.add('covPanel', uipanel(G, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 5]), [4 10]);
            P.ColumnWidth = [{'fit'}, repmat({'1x'}, 1, 9)]; P.RowHeight = {'1x', 'fit', 'fit', 'fit'};
            bg = app.add('covType', uibuttongroup(P, 'Title', 'Coverage Type', 'SelectionChangedFcn', on(@(~, ~) app.onCovType())), [1 2], [1 2]);
            app.ui.sph = uiradiobutton(bg, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            app.ui.con = uiradiobutton(bg, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            app.ui.orientLbl = app.lbl(P, 'Orientation 🧭:', 3, 1);
            app.add('orient', uidropdown(P, 'Items', [{'Auto'}, app.Axes.labels], 'ItemsData', 0:6, 'ValueChangedFcn', on(@(~, ~) app.onOrient())), 3, 2);
            app.ui.covCompLbl = app.lbl(P, 'Component:', 4, 1);
            app.add('covComp', uidropdown(P, 'Items', {'E_Total_dB'}, 'ValueChangedFcn', on(@(~, ~) app.onCovComp())), 4, 2);
            app.lbl(P, 'Antenna Pattern:', 1, 3);
            app.add('covPath', uieditfield(P, 'text'), 1, [4 8]);
            app.add('covLoad', uibutton(P, 'Text', '📂 Load File', 'ButtonPushedFcn', on(@(~, ~) app.onCovLoad())), 1, 9);
            app.add('covCompute', uibutton(P, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'ButtonPushedFcn', on(@(~, ~) app.onCovCompute())), 1, 10);
            app.lbl(P, 'Threshold  Min (dB):', 2, 3); app.add('thrMin', uispinner(P, 'Value', -40, 'Limits', R), 2, 4);
            app.lbl(P, 'Threshold  Max (dB):', 2, 5); app.add('thrMax', uispinner(P, 'Value', 10, 'Limits', R), 2, 6);
            app.lbl(P, 'Step (dB):', 2, 7); app.add('thrStep', uispinner(P, 'Value', 1, 'Limits', [0.1 50]), 2, 8);
            app.add('covReset', uibutton(P, 'Text', '🔄 Reset', 'ButtonPushedFcn', on(@(~, ~) app.onCovReset())), 2, 9);
            app.add('covExport', uibutton(P, 'Text', '💾 Export Results', 'ButtonPushedFcn', on(@(~, ~) app.saveTable(app.ui.covTbl.Data, 'coverage_results.csv', 'Export Coverage Results', 3, 2))), 2, 10);
            app.ui.coneThLbl = app.lbl(P, 'Cone θ₀ (°):', 3, 3); app.add('coneTh', uispinner(P, 'Limits', [0 180]), 3, 4);
            app.ui.conePhLbl = app.lbl(P, 'Cone φ₀ (°):', 3, 5); app.add('conePh', uispinner(P, 'Limits', [0 360]), 3, 6);
            app.ui.coneAngLbl = app.lbl(P, 'Cone Angle α (°):', 3, 7); app.add('coneAng', uispinner(P, 'Limits', [0 180], 'Value', 45), 3, 8);
            app.add('covClear', uibutton(P, 'Text', '🧹 Clear DataTips', 'ButtonPushedFcn', on(@(~, ~) app.onCovClear())), 3, 9);
            app.add('toMain', uibutton(P, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~, ~) set(app.ui.tabs, 'SelectedTab', app.ui.mainTab)), 3, 10);
            app.ui.qCovLbl = app.lbl(P, 'Coverage @ dB:', 4, 3); app.add('qCov', uispinner(P, 'ValueDisplayFormat', '%g dB'), 4, 4);
            app.add('qCovBtn', uibutton(P, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', on(@(~, ~) app.covQuery("cov"))), 4, 5);
            app.ui.qThrLbl = app.lbl(P, 'Threshold @ %:', 4, 6); app.add('qThr', uispinner(P, 'Value', 50, 'Limits', [0 100], 'ValueDisplayFormat', '%g%%'), 4, 7);
            app.add('qThrBtn', uibutton(P, 'Text', '🔍 Query Threshold', 'ButtonPushedFcn', on(@(~, ~) app.covQuery("thr"))), 4, 8);
            app.ui.covFmtLbl = app.lbl(P, 'Format:', 4, 9);
            app.add('covFmt', app.fmtDropdown(P, on(@(~, ~) app.onCovFormat())), 4, 10);
            app.add('covStatus', uilabel(G, 'Text', 'Ready 🚀', 'Interpreter', 'html'), 3, [1 5]);

            Rg = uigridlayout(app.add('covResults', uipanel(G, 'Title', 'Results', 'Visible', 'off'), 2, [1 5]), [2 5]);
            Rg.ColumnWidth = {'1x', 'fit', '1x', 'fit', '1x'}; Rg.RowHeight = {'1x', 'fit'};
            ax = app.add('covAx', uiaxes(Rg, 'Box', 'on', 'Layer', 'top'), 1, [2 4]);
            title(ax, 'Coverage vs Threshold'); xlabel(ax, 'Threshold (dB)'); ylabel(ax, 'Coverage (%)');
            ax.Interactions = dataTipInteraction; hold(ax, 'on'); grid(ax, 'on'); ylim(ax, [0 100]);
            tree = app.add('tree', uitree(Rg, 'checkbox', 'SelectionChangedFcn', on(@(~, ~) app.onTreeSelect()), 'CheckedNodesChangedFcn', on(@(~, ~) app.onTreeCheck())), [1 2], 1);
            app.ui.treeRoot = uitreenode(tree, 'Text', 'Coverage Results');
            app.add('covTbl', uitable(Rg, 'ColumnWidth', '1x', 'RowName', {}), [1 2], 5);
            app.add('xMin', uispinner(Rg, 'Limits', R, 'Value', -40, 'ValueChangedFcn', on(@(~, ~) app.covXRange([app.ui.xMin.Value app.ui.xMax.Value], "spinner"))), 2, 2);
            app.add('xSlider', uislider(Rg, 'range', 'Limits', R, 'Value', [-40 10], 'ValueChangedFcn', on(@(~, e) app.covXRange(e.Value, "slider")), 'ValueChangingFcn', on(@(~, e) app.covXRange(e.Value, "slider"))), 2, 3);
            app.add('xMax', uispinner(Rg, 'Limits', R, 'Value', 10, 'ValueChangedFcn', on(@(~, ~) app.covXRange([app.ui.xMin.Value app.ui.xMax.Value], "spinner"))), 2, 4);
        end

        function startup(app)
            u = app.ui;
            app.ui.menu = uicontextmenu(app.UIFigure);
            uimenu(app.ui.menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, e) delete(findall(ancestor(e.ContextObject, {'axes', 'polaraxes'}), 'Type', 'datatip')));
            axs = [u.fullAx, {u.pax, u.rax}];
            for k = 1:numel(axs)
                ax = axs{k}; ax.ContextMenu = app.ui.menu; enableDefaultInteractivity(ax);
                if isa(ax, 'matlab.graphics.axis.PolarAxes'), continue; end
                if ismember(k, 3:5), ax.Interactions = [rotateInteraction dataTipInteraction]; else, ax.Interactions = [zoomInteraction dataTipInteraction]; end
            end
            app.defaults = struct('loss', u.loss.Value, 'rx', u.rx.Value, 'rw', u.rw.Value, 'pt', u.pt.Value, 'ptUnit', u.ptUnit.Value, 'r', u.r.Value, 'rUnit', u.rUnit.Value);
            set(app.paramControls(), 'Visible', 'off');
            app.covUI();
        end

        function h = paramControls(app)
            u = app.ui; h = [u.rxLbl u.rx u.rwLbl u.rw u.lossLbl u.loss u.ptLbl u.pt u.ptUnit u.rLbl u.r u.rUnit];
        end
    end

    %% ------------------------------------------------------------------ small state helpers
    methods (Access = private)
        function tf = gainOnly(app), tf = app.src.meta.isGainOnly; end
        function tf = elev(app), tf = strcmp(app.ui.thSpan.Value, '-90° to 90°'); end
        function tf = signed(app), tf = strcmp(app.ui.phiSpan.Value, '-180° to 180°'); end
        function c = comp(app), c = app.ui.comp.Value; end

        function xl = phiLimits(app)
            if app.signed(), xl = [-180 180]; else, xl = [0 360]; end
        end

        function c = totalCol(app)
            c = 'E_Total_dB';
            if ~ismember(c, app.viewTbl.Properties.VariableNames), c = app.viewTbl.Properties.VariableNames{3}; end
        end

        function s = compLabel(app)
            dd = app.ui.comp; i = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(i), s = replace(string(dd.Value), '_', ' '); else, s = string(dd.Items{i}); end
        end

        function G = gridOf(app, col)
            G = nan(app.phys.sz); G(app.phys.idx) = app.viewTbl.(col);
        end

        function p = params(app)
            u = app.ui;
            p = struct('GainLoss_dB', u.loss.Value, 'RxMode', string(u.rx.Value), 'RxAR_dB', u.rw.Value);
            p.FieldScale = 10^(p.GainLoss_dB/20);
            pt = u.pt.Value;
            switch u.ptUnit.Value, case 'dBm', pt = pt - 30; case 'Watts', pt = 10*log10(max(pt, eps)); end
            p.Pt_dBW = pt;
            p.R_m = max(u.r.Value, 1e-12) * (1 + 999*strcmp(u.rUnit.Value, 'km'));
        end

        function say(app, which, msg, transient)
            % Status text; transient messages revert to the last persistent one after 3 s.
            if app.closing, return; end
            L = app.ui.status; if which == 2, L = app.ui.covStatus; end
            app.stopTimer(); L.Text = char(msg);
            if nargin > 3 && transient
                app.statusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, 'StopFcn', @(t, ~) delete(t), ...
                    'TimerFcn', @(~, ~) app.restoreStatus(L));
                start(app.statusTimer);
            else
                L.UserData = char(msg);
            end
        end

        function restoreStatus(app, L)
            if ~app.closing && isgraphics(L) && ischar(L.UserData), L.Text = L.UserData; end
            app.statusTimer = [];
        end

        function stopTimer(app)
            t = app.statusTimer; app.statusTimer = [];
            if ~isempty(t) && isvalid(t), stop(t); end
        end

        function c = busy(app, titleText, msg)
            app.dlg = uiprogressdlg(app.UIFigure, 'Title', titleText, 'Message', msg, 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            drawnow; c = onCleanup(@() app.endBusy());
        end

        function endBusy(app)
            d = app.dlg; app.dlg = [];
            if ~isempty(d) && isvalid(d), close(d); end
        end

        function check(app)
            % Cooperative cancellation checkpoint for long pipeline stages.
            if ~isempty(app.dlg) && isvalid(app.dlg) && app.dlg.CancelRequested
                app.dlg.Message = 'Aborting...'; drawnow limitrate
                error('APAT:Cancelled', 'Operation cancelled by user.');
            end
        end
    end

    %% ------------------------------------------------------------------ source loading
    methods (Access = private)
        function out = readAny(app, fp, dd, lbl)
            % Generic text files expose the format selector; other formats are self-describing.
            generic = isGeneric(fp);
            if generic, dd.Value = 'gain'; end
            out = readSource(fp, dd.Value);
            set([lbl dd], 'Visible', generic && ~out.meta.isCoverage);
            app.check();
        end

        function onLoad(app)
            prev = app.ui.path.Value; fp = strtrim(prev);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.src.path)
                filters = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern/Gain Files'};
                while true % re-selecting the loaded file asks for another one
                    [n, p] = uigetfile(filters, 'Select an antenna pattern file');
                    if isequal(n, 0), return; end
                    fp = fullfile(p, n); if ~strcmp(fp, app.src.path), break; end
                    choice = uiconfirm(app.UIFigure, sprintf('"<b>%s</b>" is already loaded', n), 'File Already Loaded', ...
                        'Options', {'Select Another File', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2, 'Interpreter', 'html');
                    if strcmp(choice, 'Cancel'), return; end
                end
                app.ui.path.Value = fp;
            end
            c = app.busy('Loading Data', 'Reading file...');
            out = app.readAny(fp, app.ui.fmt, app.ui.fmtLbl);
            if out.meta.isCoverage % coverage-results files route to the Coverage tab without touching Main state
                app.ui.path.Value = prev; delete(c);
                app.ui.tabs.SelectedTab = app.ui.covTab; app.ui.covPath.Value = fp;
                app.covLoadResults(fp, out.rawTbl); return
            end
            [folder, base, ext] = fileparts(fp);
            app.src = out; [app.src.path, app.src.folder, app.src.base, app.src.name, app.src.shown] = deal(fp, folder, base, [base ext], false);
            u = app.ui; dep = out.meta.isDep;
            if dep
                items = compose('Pattern %d: %.4g GHz', (1:numel(out.blocks)).', out.freqs(:)/1e9);
                miss = isnan(out.freqs(:)); items(miss) = compose('Pattern %d', find(miss));
                u.ffd.Items = items; u.ffd.Value = items{1};
            end
            set([u.ffd u.ffdLbl], 'Visible', dep);
            u.step.UserData = false; u.basis.UserData = true; % auto-select native step and cut basis
            app.selectBlock(1); app.run("process");
        end

        function selectBlock(app, k)
            T = normalizePattern(app.src.blocks{k}); T.Properties.UserData = app.src.meta;
            app.stdTbl = T;
            if app.src.meta.isDep, app.src.rawTbl = app.src.blocks{k}; app.src.shown = false; end
        end

        function onProcess(app)
            if isempty(app.stdTbl), uialert(app.UIFigure, 'No file loaded. Load a pattern first.', 'Warning', 'Icon', 'warning'); return; end
            c = app.busy('Processing', 'Re-processing pattern...'); %#ok<NASGU>
            u = app.ui; u.step.UserData = strcmp(u.step.Value, 'STEP: 1°');
            if isGeneric(app.src.path) % reinterpret the cached generic table with the selected format
                out = readSource(app.src.path, u.fmt.Value, app.src.rawTbl);
                assert(~out.meta.isCoverage, 'The selected generic format identifies a coverage-results file.');
                keep = app.src; app.src = out;
                [app.src.path, app.src.folder, app.src.base, app.src.name, app.src.shown] = deal(keep.path, keep.folder, keep.base, keep.name, false);
                app.selectBlock(1);
            end
            app.run("process");
            app.say(1, ['Re-processed <b>' app.src.name '</b> with current parameters ✅'], true);
        end

        function onFormat(app)
            if strcmp(strtrim(app.ui.path.Value), app.src.path) && isGeneric(app.src.path)
                app.ui.basis.UserData = true; app.onProcess();
            end
        end

        function onFFD(app)
            k = find(strcmp(app.ui.ffd.Items, app.ui.ffd.Value), 1);
            app.ui.basis.UserData = true; app.selectBlock(k); app.run("process");
            app.say(1, sprintf('Switched to FFD block %d (%s).', k, app.ui.ffd.Value), true);
        end

        function onResetParams(app)
            d = app.defaults; u = app.ui;
            [u.loss.Value, u.rx.Value, u.rw.Value, u.pt.Value, u.ptUnit.Value, u.r.Value, u.rUnit.Value] = deal(d.loss, d.rx, d.rw, d.pt, d.ptUnit, d.r, d.rUnit);
            if ~isempty(app.stdTbl), app.run("process"); end
        end
    end

    %% ------------------------------------------------------------------ pipeline
    methods (Access = private)
        function run(app, stage)
            % Rebuild from STAGE downstream: "process" ⊃ "step" ⊃ "span" ⊃ "view".
            from = find(["process", "step", "span", "view"] == stage, 1); app.check();
            if from <= 1
                [app.patTbl, info] = calcPattern(app.stdTbl, app.params());
                app.pol = info.pol; app.pairs = info.pairs;
                if isequal(app.ui.basis.UserData, true) && ~app.gainOnly()
                    app.ui.basis.Value = 'Circular'; if startsWith(app.pol, 'Linear'), app.ui.basis.Value = 'Linear'; end
                end
                app.stepItems(); app.compItems();
            end
            if from <= 2, app.baseTbl = app.resampled(); app.check(); end
            if from <= 3
                app.applySpan();
                app.lim.gain = peakWindow(app.viewTbl.(app.totalCol()), app.PeakPct, app.PeakExcess);
            end
            app.refreshView(from <= 3, from <= 1);
        end

        function stepItems(app)
            ts = gridStep(app.patTbl.Theta); ps = gridStep(mod(app.patTbl.Phi, 360));
            if ~isfinite(ts), ts = 1; end; if ~isfinite(ps), ps = ts; end
            d = app.ui.step; native = sprintf('STEP: %g°', max(ts, ps)); one = 'STEP: 1°';
            nonCanonical = abs(ts - 1) > 1e-9 || abs(ps - 1) > 1e-9;
            d.Items = {native, one}; d.Value = native;
            if isequal(d.UserData, true) && nonCanonical, d.Value = one; end
            d.UserData = false; set(d, 'Visible', nonCanonical, 'Enable', nonCanonical);
            app.ui.cutValue.Step = max(ts, 1);
        end

        function compItems(app)
            [cols, labels] = compList(app.patTbl, app.Labels); dd = app.ui.comp; prev = string(dd.Value);
            dd.Items = cellstr(labels); dd.ItemsData = cellstr(cols); dd.Value = pickComp(prev, cols);
        end

        function T = resampled(app)
            % Resample the PRIMITIVE canonical source (fields / gain) and reprocess; never interpolate derived dB outputs.
            S = app.stdTbl; T = app.patTbl;
            if ~strcmp(app.ui.step.Value, 'STEP: 1°'), return; end
            ts = gridStep(S.Theta); ps = gridStep(mod(S.Phi, 360));
            if all(isfinite([ts ps])) && all(abs([ts ps] - 1) < 1e-9), return; end
            if all(isfinite([ts ps])) && ts < 1 && ps < 1 % finer than 1°: keep the integer-degree subset exactly
                S = S(abs(S.Theta - round(S.Theta)) < 1e-9 & abs(S.Phi - round(S.Phi)) < 1e-9, :);
            else
                S = resampleCanonical(S, 1);
            end
            S.Properties.UserData = app.stdTbl.Properties.UserData;
            T = calcPattern(S, app.params());
        end

        function applySpan(app)
            % Materialize the display convention and derive the physical companions + grid topology.
            T = app.baseTbl; th = T.Theta; ph = T.Phi; meta = T.Properties.UserData;
            if app.signed()
                keep = abs(ph - 360) > 1e-9; T = T(keep, :); th = th(keep); ph = ph(keep);
                seam = abs(ph - 180) < 1e-9; % duplicate +180° as −180° so plots close
                T = [T(seam, :); T]; th = [th(seam); th]; ph = [ph(seam); ph];
                T.Phi = ph; T.Phi(ph > 180) = ph(ph > 180) - 360; T.Phi(1:nnz(seam)) = -180; dupPhi = -180;
            else
                dupPhi = 360;
            end
            if app.elev(), T.Theta = 90 - th; end
            [T, o] = sortrows(T, {'Phi', 'Theta'}); th = th(o); ph = ph(o); T.Properties.UserData = meta;
            P = struct('theta', th, 'phi', ph, 'omega', solidWeights(th, ph));
            P.omega(abs(T.Phi - dupPhi) < 1e-9) = 0; % the closing duplicate never carries solid angle
            P.thAxis = unique(T.Theta); P.phAxis = unique(T.Phi); P.sz = [numel(P.thAxis) numel(P.phAxis)];
            [~, i] = ismember(T.Theta, P.thAxis); [~, j] = ismember(T.Phi, P.phAxis); P.idx = sub2ind(P.sz, i, j);
            [P.PH, P.TH] = meshgrid(P.phAxis, P.thAxis);
            P.THp = nan(P.sz); P.THp(P.idx) = th; P.PHp = nan(P.sz); P.PHp(P.idx) = ph; % physical grids
            P.X = sind(P.THp).*cosd(P.PHp); P.Y = sind(P.THp).*sind(P.PHp); P.Z = cosd(P.THp);
            app.viewTbl = T; app.phys = P; app.viewRev = app.viewRev + 1;
        end

        function refreshView(app, resetRanges, resetCut)
            % Stage 4: peak / boresight / metrics, tables, metadata, cut and full-pattern plots.
            if isempty(app.viewTbl), return; end
            T = app.viewTbl; P = app.phys; tot = app.totalCol(); col = app.comp();
            pkT = resolvePeak(T.(tot), app.PeakPct, app.PeakExcess);
            app.boresight = boresightOf(P.theta, P.phi, T.(tot), P.omega, pkT, app.Axes);
            ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(pkT.index); end
            app.metrics = calcMetrics(P.theta, P.phi, T.(tot), pkT, P.omega, app.boresight, app.Axes, ar);
            app.peak = resolvePeak(T.(col), app.PeakPct, app.PeakExcess); app.check();
            if resetRanges, L = app.theme(); app.setRange("all", L, false); end
            app.updateTables(); app.updateMeta();
            if resetCut, app.setPlane(); end
            app.cutControl(); app.plotCut(); app.check(); app.renderFull();
            u = app.ui; e = ~app.gainOnly();
            set([u.cutPanel u.exportBtn u.fullPanel u.ctrlPanel u.coverageBtn], 'Visible', 'on');
            set([u.uanBtn u.ecut u.chkTot u.chkA u.chkB], 'Visible', e); set([u.chkA u.chkB u.basis], 'Enable', e);
            s = sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>θ=%s°, φ=%s°</b>)', app.src.name, fmtNum(app.peak.value, 2), ...
                fmtNum(P.theta(app.peak.index)), fmtNum(P.phi(app.peak.index)));
            if e && ~any(strcmpi(strtrim(app.pol), {'', 'n/a'})), s = [s ' | Polarization <b>' app.pol '</b>']; end
            app.say(1, s, false);
        end
    end

    %% ------------------------------------------------------------------ ranges & theme
    methods (Access = private)
        function [L, map] = theme(app)
            % Signed AR always uses ±30 dB with a blue-white-red map; everything else shares lim.gain + jet.
            if isARName(app.comp())
                L = [-30 30]; map = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256));
            else
                L = app.lim.gain; map = jet(256);
            end
        end

        function setRange(app, scope, L, apply)
            % Single authority for full-pattern ("full"), cut ("cut") or both ("all") dB windows.
            % APPLY (default true) pushes the window into existing plots; the pipeline passes false and re-renders itself.
            if nargin < 4, apply = true; end
            R = app.Range; L = sort(double(L(:).')); L = [max(R(1), L(1)), min(R(2), L(2))];
            if diff(L) < 1, L(2) = min(R(2), L(1) + 1); L(1) = L(2) - 1; end
            if scope == "all", app.setRange("full", L, apply); app.setRange("cut", L, apply); return; end
            u = app.ui;
            if scope == "full", S = u.fullSlider; lo = u.fullMin; hi = u.fullMax; else, S = u.cutSlider; lo = u.cutMin; hi = u.cutMax; end
            set(S, 'Limits', R, 'Value', L); set(S, 'Limits', [max(R(1), L(1) - 25), min(R(2), L(2) + 25)]); % ±25 dB slider travel
            set(lo, 'Limits', [R(1), L(2) - 1], 'Value', L(1)); set(hi, 'Limits', [L(1) + 1, R(2)], 'Value', L(2));
            app.lim.(scope) = L;
            if scope == "full"
                if ~isARName(app.comp()), app.lim.gain = L; end
                u.cmin.Value = L(1); u.cmax.Value = L(2);
                if ~apply, return; end
                for k = 1:5
                    ax = u.fullAx{k}; if isempty(findall(ax, 'Tag', 'APAT_Surface')), continue; end
                    clim(ax, L); if k == 5, zlim(ax, L); end; app.colorbarTicks(colorbar(ax), L);
                end
            elseif apply && ~isempty(app.viewTbl)
                app.plotCut();
            end
        end

        function colorbarTicks(app, cbh, L)
            step = app.ui.cstep.Value; if ~isfinite(step) || step <= 0, return; end
            t = unique([L(1), ceil(L(1)/step)*step:step:floor(L(2)/step)*step, L(2)]);
            if numel(t) <= 60, cbh.Ticks = t; end
        end
    end

    %% ------------------------------------------------------------------ full-pattern rendering
    methods (Access = private)
        function renderFull(app)
            P = app.phys; G = app.gridOf(app.comp()); [L, map] = app.theme(); lab = app.compLabel();
            thLab = "Theta"; if app.elev(), thLab = "Elevation"; end
            [i, j] = ind2sub(P.sz, P.idx(app.peak.index)); pob = cell(1, 5); r = ones(P.sz);
            for k = 1:5
                app.check(); ax = app.ui.fullAx{k}; cla(ax); hold(ax, 'on');
                switch k
                    case 1 % rectangular contour
                        h = pcolor(ax, P.phAxis, P.thAxis, G); set(h, 'FaceColor', 'interp', 'LineStyle', 'none');
                        app.angularAxes(ax, 30, 15); daspect(ax, [1 1 1]); title(ax, lab, 'Interpreter', 'none');
                        pob{k} = {P.PH(i, j), P.TH(i, j), []};
                    case 2 % circular contour: r = physical θ, angle = physical φ
                        h = surface(ax, deg2rad(P.PHp), P.THp, zeros(P.sz), G, 'EdgeColor', 'none');
                        rl = 0:30:180; if app.elev(), rl = 90 - rl; end
                        set(ax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', rl));
                        app.polarTicks(ax); title(ax, lab + "  |  r=θ, angle=φ", 'Interpreter', 'none', 'FontSize', 9);
                        pob{k} = {deg2rad(P.PHp(i, j)), P.THp(i, j), []};
                    case {3, 4} % 3-D sphere / 3-D polar (radius ∝ value within the colour window)
                        if k == 4, r = max(G - L(1), 0)/max(diff(L), eps); r = r/max(max(r(:)), eps); end
                        h = surf(ax, r.*P.X, r.*P.Y, r.*P.Z, G, 'EdgeColor', 'none');
                        set(ax, 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1], 'Projection', 'orthographic');
                        axis(ax, 'off'); app.drawXYZ(ax); app.view3D(ax, [135 25]);
                        if app.ui.overlay.Value, app.overlayCut(ax, k == 3, L); end
                        title(ax, sprintf('%s  |  θ: %s  |  φ: %s', lab, app.ui.thSpan.Value, app.ui.phiSpan.Value), 'Interpreter', 'none');
                        pob{k} = {r(i, j)*P.X(i, j), r(i, j)*P.Y(i, j), r(i, j)*P.Z(i, j)};
                    case 5 % rectangular 3-D surface
                        h = surf(ax, P.PH, P.TH, G, 'EdgeColor', 'none'); zlim(ax, L); app.angularAxes(ax, 60, 30); grid(ax, 'on');
                        xlabel(ax, 'Phi (degree)'); ylabel(ax, thLab + " (degree)"); zlabel(ax, lab + " (dB)", 'Interpreter', 'none');
                        app.view3D(ax, [-35 35]); title(ax, lab, 'Interpreter', 'none');
                        pob{k} = {P.PH(i, j), P.TH(i, j), G(i, j)};
                end
                set(h, 'Tag', 'APAT_Surface', 'ContextMenu', app.ui.menu); clim(ax, L); colormap(ax, map); app.colorbarTicks(colorbar(ax), L);
                try, h.DataTipTemplate.DataTipRows = [dataTipTextRow(thLab, P.TH, '%.3g°'); dataTipTextRow("Phi", P.PH, '%.3g°'); dataTipTextRow(lab, G, '%.3g dB')]; catch, end
                hold(ax, 'off');
            end
            drawnow limitrate % surfaces must exist before DataTips attach
            rows = [dataTipTextRow(thLab, P.TH(i, j), '%.3g°'); dataTipTextRow("Phi", P.PH(i, j), '%.3g°'); dataTipTextRow(lab, G(i, j), '%.3g dB')];
            for k = 1:5, app.mark(app.ui.fullAx{k}, pob{k}{:}, rows, 'APAT_POB', 'k'); end
            app.syncTips();
        end

        function angularAxes(app, ax, phiStep, thStep)
            xl = app.phiLimits();
            if app.elev(), yl = [-90 90]; dir = 'normal'; else, yl = [0 180]; dir = 'reverse'; end
            set(ax, 'XLim', xl, 'YLim', yl, 'YDir', dir, 'Box', 'on', 'Layer', 'top', 'XTick', xl(1):phiStep:xl(2), 'YTick', yl(1):thStep:yl(2));
        end

        function polarTicks(app, pax)
            a = 0:30:330; if app.signed(), a(a > 180) = a(a > 180) - 360; end
            set(pax, 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', a));
        end

        function view3D(app, ax, default)
            up = [0 0 1];
            switch string(app.ui.view3d.Value)
                case "top", v = [0 90]; up = [0 1 0];
                case "bottom", v = [0 -90]; up = [0 1 0];
                case "right", v = [90 0];
                case "left", v = [-90 0];
                case "front", v = [0 0];
                case "back", v = [180 0];
                otherwise, v = default;
            end
            view(ax, v); try, camup(ax, up); catch, end
        end

        function apply3DViews(app)
            if isempty(app.viewTbl), return; end
            d = {[135 25], [135 25], [-35 35]};
            for k = 3:5, app.view3D(app.ui.fullAx{k}, d{k - 2}); end
            drawnow limitrate
        end

        function drawXYZ(~, ax)
            c = {[0.85 0.1 0.1], [0.1 0.6 0.1], [0.1 0.2 0.9]}; t = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'}; D = 1.35*eye(3);
            for k = 1:3
                quiver3(ax, 0, 0, 0, D(k, 1), D(k, 2), D(k, 3), 0, 'Color', c{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12*D(k, 1), 1.12*D(k, 2), 1.12*D(k, 3), t{k}, 'Color', c{k}, 'FontWeight', 'bold');
            end
        end

        function overlayCut(app, ax, isSphere, L)
            C = app.cutData(); v = C.Y(:, 1);
            if isSphere, r = 1.02; else, r = max(v - L(1), 0)/max(diff(L), eps)*1.01; end
            plot3(ax, r.*sind(C.th).*cosd(C.ph), r.*sind(C.th).*sind(C.ph), r.*cosd(C.th), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_Overlay');
        end

        function refreshOverlay(app)
            if isempty(app.viewTbl), return; end
            L = app.theme();
            for k = 3:4
                ax = app.ui.fullAx{k}; delete(findall(ax, 'Tag', 'APAT_Overlay'));
                if app.ui.overlay.Value && ~isempty(findall(ax, 'Tag', 'APAT_Surface')), hold(ax, 'on'); app.overlayCut(ax, k == 3, L); hold(ax, 'off'); end
            end
        end
    end

    %% ------------------------------------------------------------------ annotations (POB / HPBW)
    methods (Access = private)
        function mark(~, ax, x, y, z, rows, tag, color)
            % One tagged marker + DataTip.  Visibility is governed centrally by syncTips().
            if isempty(x) || ~isfinite(x) || ~isfinite(y), return; end
            held = ishold(ax); hold(ax, 'on');
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), h = polarplot(ax, x, y, 'o');
            elseif isempty(z), h = plot(ax, x, y, 'o');
            else, h = plot3(ax, x, y, z, 'o', 'Clipping', 'off');
            end
            set(h, 'MarkerSize', 5, 'MarkerEdgeColor', color, 'MarkerFaceColor', color, 'Tag', tag);
            if ~held, hold(ax, 'off'); end
            try, h.DataTipTemplate.DataTipRows = rows; datatip(h, 'DataIndex', 1, 'Tag', tag, 'FontSize', 9); catch, end
        end

        function syncTips(app)
            % Tagged markers/tips are visible only when their checkbox is on AND their tab is the selected one.
            if app.closing, return; end
            on = struct('APAT_POB', app.ui.pob.Value, 'APAT_HPBW', app.ui.hpbwTips.Value);
            for tag = ["APAT_POB", "APAT_HPBW"]
                for h = findall(app.UIFigure, 'Tag', tag).'
                    tab = ancestor(h, 'uitab');
                    h.Visible = on.(tag) && (isempty(tab) || tab.Parent.SelectedTab == tab);
                end
            end
        end
    end

    %% ------------------------------------------------------------------ cuts
    methods (Access = private)
        function [type, v] = planeCut(app, isE)
            % E/H principal-plane cut for the detected boresight, expressed in the DISPLAY convention.
            [type, v] = planeDef(app.boresight, app.Axes, isE);
            if type == "Phi" && app.elev(), v = 90 - v; end
        end

        function setPlane(app)
            [type, v] = app.planeCut(strcmp(app.ui.eh.Value, 'E'));
            app.ui.cutType.Value = char(type); vals = app.cutControl();
            [~, i] = min(abs(vals - v)); app.ui.cutValue.Value = vals(i);
        end

        function onPlane(app), app.setPlane(); app.onCut(); end

        function onBasis(app), app.ui.basis.UserData = false; app.updateMeta(); app.onCut(); end

        function onCut(app, typeChanged)
            if nargin > 1 && typeChanged, app.cutControl(); end
            showB = app.ui.hpbwBtn.Value; app.ui.hpbwTips.Visible = showB;
            if ~showB, app.ui.hpbwTips.Value = false; end
            app.plotCut();
            if app.ui.overlay.Value, app.refreshOverlay(); end
        end

        function v = cutControl(app)
            % The cut value is a fixed θ (display units) for Phi cuts and a fixed φ for Theta cuts.
            u = app.ui;
            if strcmp(u.cutType.Value, 'Phi'), v = unique(app.viewTbl.Theta); else, v = unique(mod(app.phys.phi, 360)); end
            u.cutValue.Limits = [-360 360]; [~, i] = min(abs(v - u.cutValue.Value)); u.cutValue.Value = v(i);
            if numel(v) > 1, u.cutValue.Limits = [min(v) max(v)]; u.cutValue.Step = min(diff(v)); end
        end

        function [cols, idx] = cutCols(app)
            % Total plus the selected circular or linear pair; idx keeps colours stable.
            if app.gainOnly(), cols = string(app.comp()); idx = 1; return; end
            if strcmp(app.ui.basis.Value, 'Linear'), all3 = ["E_Total_dB", "E_TH_dB", "E_PH_dB"]; pair = {'E_TH', 'E_PH'};
            else, all3 = ["E_Total_dB", "E_RCP_dB", "E_LCP_dB"]; pair = {'E_RCP', 'E_LCP'};
            end
            [app.ui.chkA.Text, app.ui.chkB.Text] = pair{:};
            sel = [app.ui.chkTot.Value app.ui.chkA.Value app.ui.chkB.Value]; if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = all3(idx);
        end

        function C = cutData(app)
            % The active cut as one closed circle: ang (deg, display convention), Y (n×m dB), physical th/ph.
            u = app.ui; [cols, idx] = app.cutCols(); type = string(u.cutType.Value); req = u.cutValue.Value;
            if type == "Phi" && app.elev(), req = 90 - req; end
            [ang, rows, fixed] = cutRows(app.phys.theta, app.phys.phi, type, req);
            if abs(fixed - req) > 1e-9
                sym = 'θ'; if type == "Theta", sym = 'φ'; end
                app.say(1, sprintf('Requested %s cut @ %s=%g° (snapped to nearest %s=%g°)', type, sym, req, sym, fixed), true);
            end
            if app.signed(), ang = mod(ang + 180, 360) - 180; [ang, o] = sort(ang); rows = rows(o); end
            ang(end + 1) = ang(1) + 360; rows(end + 1) = rows(1); % close the circle
            shown = fixed; if type == "Phi" && app.elev(), shown = 90 - fixed; end
            if app.gainOnly(), titleText = char(app.compLabel());
            elseif type == "Phi", titleText = sprintf('Phi cut @ θ = %g°', shown);
            else, titleText = sprintf('Theta cut @ φ = %g°', shown);
            end
            C = struct('ang', ang, 'Y', app.viewTbl{rows, cellstr(cols)}, 'cols', cols, 'idx', idx, 'type', type, 'title', titleText, ...
                'th', app.phys.theta(rows), 'ph', app.phys.phi(rows), 'names', replace(cols, "_", "\_"));
        end

        function plotCut(app)
            if isempty(app.viewTbl), return; end
            C = app.cutData(); pax = app.ui.pax; rax = app.ui.rax; L = app.lim.cut; xl = app.phiLimits();
            cla(pax); cla(rax);
            hp = polarplot(pax, deg2rad(C.ang), max(C.Y, L(1)), 'LineWidth', 1.4); % clamp so nothing reflects through the origin
            hr = plot(rax, C.ang, C.Y, 'LineWidth', 1.4); hold(pax, 'on'); hold(rax, 'on');
            co = rax.ColorOrder; colors = num2cell(co(1 + mod(C.idx - 1, size(co, 1)), :), 2);
            set(hp, {'Color'}, colors); set(hr, {'Color'}, colors);
            for k = 1:numel(hp)
                rows = [dataTipTextRow("Angle", C.ang, '%.3g°'), dataTipTextRow("Magnitude", C.Y(:, k), '%.3g dB')];
                hp(k).DataTipTemplate.DataTipRows = rows; hr(k).DataTipTemplate.DataTipRows = rows;
            end
            set(pax, 'ThetaDir', 'clockwise', 'ThetaZeroLocation', 'top', 'RLim', L, 'RTick', L(1):5:L(2)); app.polarTicks(pax);
            set(rax, 'YLim', L, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, C.type + " (degree)"); title(pax, C.title, 'Interpreter', 'none'); title(rax, C.title, 'Interpreter', 'none');

            % POB of the displayed cut (first plotted component).
            [pk, ip] = max(C.Y(:, 1), [], 'omitnan');
            if isfinite(pk)
                rows = [dataTipTextRow("Angle", C.ang(ip), '%.3g°'); dataTipTextRow("Magnitude", pk, '%.3g dB')];
                app.mark(pax, deg2rad(C.ang(ip)), max(pk, L(1)), [], rows, 'APAT_POB', 'k'); app.mark(rax, C.ang(ip), pk, [], rows, 'APAT_POB', 'k');
            end

            % HPBW (wrap-aware shading, optional interpolated boundary tips).
            app.ui.hpbwLbl.Text = '';
            if app.ui.hpbwBtn.Value && isfinite(pk)
                [bw, lo, hi] = calcHPBW(C.ang(1:end - 1), C.Y(1:end - 1, 1));
                if isfinite(bw)
                    b = [lo hi]; if xl(1) < 0, b = mod(b + 180, 360) - 180; else, b = mod(b, 360); end
                    app.ui.hpbwLbl.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b);
                    if b(1) <= b(2), Rg = b; else, Rg = [xl(1) b(2); b(1) xl(2)]; end
                    thetaregion(pax, deg2rad(Rg(:, 1)), deg2rad(Rg(:, 2)), FaceColor = '#D95319', FaceAlpha = 0.12);
                    xregion(rax, Rg(:, 1), Rg(:, 2), FaceColor = '#D95319', FaceAlpha = 0.12);
                    names = ["Lower HPBW", "Upper HPBW"];
                    for k = 1:2
                        rows = [dataTipTextRow(names(k), b(k), '%.2f°'); dataTipTextRow("Gain", pk - 3, '%.2f dB')];
                        app.mark(pax, deg2rad(b(k)), pk - 3, [], rows, 'APAT_HPBW', '#D95319'); app.mark(rax, b(k), pk - 3, [], rows, 'APAT_HPBW', '#D95319');
                    end
                end
            end
            legend(pax, hp, C.names, 'Location', 'southoutside', 'Orientation', 'horizontal');
            legend(rax, hr, C.names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off'); app.syncTips();
        end
    end

    %% ------------------------------------------------------------------ tables, metadata, exports
    methods (Access = private)
        function updateTables(app)
            T = app.viewTbl; dd = app.ui.outFilter; cols = T.Properties.VariableNames(3:end);
            if ~app.src.shown
                set(app.ui.tblIn, 'Data', app.src.rawTbl, 'ColumnName', app.src.rawTbl.Properties.VariableNames); app.src.shown = true;
            end
            if ~isequal(regexprep(dd.Items(2:end), '^✓ ?', ''), cols) % schema changed → rebuild the column filter
                dd.Items = [{'--- column filter ---'}, cols]; dd.ItemsData = 0:numel(cols);
                dd.UserData = ~ismember(cols, app.Hidden); dd.Value = 0;
                set([dd app.ui.dataTabs], 'Visible', 'on');
            end
            app.filterOutput(false);
        end

        function filterOutput(app, fromUser)
            dd = app.ui.outFilter;
            if fromUser && dd.Value > 0, dd.UserData(dd.Value) = ~dd.UserData(dd.Value); dd.Value = 0; end
            on = find(dd.UserData) + 1; items = regexprep(dd.Items, '^✓ ?', ''); items(on) = append('✓ ', items(on)); dd.Items = items;
            removeStyle(dd);
            addStyle(dd, uistyle('FontWeight', 'bold', 'BackgroundColor', [0.8 1 0.8]), 'Item', on);
            addStyle(dd, uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9]), 'Item', find([true, ~dd.UserData]));
            app.ui.tblOut.Data = app.viewTbl(:, [true true logical(dd.UserData)]);
            app.paramVisibility();
        end

        function paramVisibility(app)
            % Only parameters that influence a visible output column are shown.
            u = app.ui; cols = string(app.viewTbl.Properties.VariableNames(3:end)); sel = cols(logical(u.outFilter.UserData));
            has = @(list) any(ismember(sel, list));
            set([u.rxLbl u.rx u.rwLbl u.rw], 'Visible', has(["PLF_dB", "Gain_PolCorrected_dB"]));
            set([u.ptLbl u.pt u.ptUnit], 'Visible', has(["EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
            set([u.rLbl u.r u.rUnit], 'Visible', has(["PFD_Wm2", "E_RMS_Vm"]));
            set([u.lossLbl u.loss], 'Visible', app.gainOnly() || has(["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "Gain_PolCorrected_dB", "EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
        end

        function updateMeta(app)
            T = app.viewTbl; P = app.phys; M = app.metrics; pk = app.peak;
            rows = {'Source format', app.src.meta.source; 'File', app.src.name; ...
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(T), P.sz(1), P.sz(2)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(min(T.Theta)), fmtNum(max(T.Theta)), fmtNum(gridStep(T.Theta))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(min(T.Phi)), fmtNum(max(T.Phi)), fmtNum(gridStep(T.Phi)))};
            f = app.src.freqs(isfinite(app.src.freqs));
            if ~isempty(f), rows(end + 1, :) = {'Frequencies', strjoin(compose('%.4g GHz', f(:)/1e9), ', ')}; end
            if ~app.gainOnly()
                if ~any(strcmpi(strtrim(app.pol), {'', 'n/a'})), rows(end + 1, :) = {'Polarization', app.pol}; end
                rows(end + 1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(app.pairs.(app.ui.basis.Value), ' / '))};
            end
            rows = [rows; { ...
                'Peak gain (POB)', sprintf('%s dB', fmtNum(M.PeakGain_dB)); ...
                'POB direction [θ, φ]', sprintf('[%s°, %s°]', fmtNum(M.PeakTheta_deg), fmtNum(M.PeakPhi_deg)); ...
                'Boresight axis', app.Axes.labels{app.boresight}; ...
                'Peak policy', sprintf('P%.4g, max excess %.4g dB', app.PeakPct, app.PeakExcess); ...
                'Peak adjusted', char(string(pk.wasAdjusted)); ...
                'HPBW E-plane', sprintf('%s°', fmtNum(M.HPBW_EPlane_deg)); 'HPBW H-plane', sprintf('%s°', fmtNum(M.HPBW_HPlane_deg)); ...
                'Front-to-back', sprintf('%s dB', fmtNum(M.FrontBack_dB)); 'Peak directivity', sprintf('%s dB', fmtNum(M.PeakDirectivity_dB))}];
            if ~strcmp(app.comp(), app.totalCol())
                rows(end + 1, :) = {char(app.compLabel() + " peak"), sprintf('%s dB @ [%s°, %s°]', fmtNum(pk.value), fmtNum(P.theta(pk.index)), fmtNum(P.phi(pk.index)))};
            end
            if isfinite(M.Efficiency_pct), rows(end + 1, :) = {'Radiation efficiency', sprintf('%s%%', fmtNum(M.Efficiency_pct))}; end
            if isfinite(M.AxialRatioAtPeak_dB), rows(end + 1, :) = {'AR at peak', sprintf('%s dB', fmtNum(M.AxialRatioAtPeak_dB))}; end
            app.ui.tblMeta.Data = rows;
        end

        function saveTable(app, T, defaultName, titleText, nFilters, which)
            % Shared CSV / TXT (tab) / XLSX writer with a file dialog.
            if isempty(T), return; end
            filters = {'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'};
            [f, p] = uiputfile(filters(1:nFilters, :), titleText, fullfile(app.src.folder, defaultName));
            if isequal(f, 0), return; end
            fp = fullfile(p, f);
            if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
            app.say(which, ['Exported to <b>' fp '</b>'], true);
        end

        function exportResults(app)
            app.saveTable(app.ui.tblOut.Data, [app.src.base '_APAT_results.csv'], 'Export Results', 3, 1); % respects the column filter
        end

        function exportCut(app)
            C = app.cutData();
            app.saveTable(array2table([C.ang C.Y], 'VariableNames', [{'Angle_deg'}, cellstr(C.cols)]), [app.src.base '_cut.csv'], 'Export Cut', 2, 1);
        end

        function exportUAN(app)
            if app.gainOnly(), uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            T = app.viewTbl; P = app.phys;
            U = table(P.theta, P.phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'});
            [~, i] = unique(U(:, [2 1])); U = U(i, :); % physical angles, one row per direction, φ-major order
            st = gridStep(U.Theta); if ~isfinite(st), st = 1; end; sp = gridStep(mod(U.Phi, 360));
            pk = max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan');
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, ...
                'Export UAN / E-field data', fullfile(app.src.folder, sprintf('%s_%.5f_%gdeg.uan', app.src.base, pk, st)));
            if isequal(f, 0), return; end
            fp = fullfile(p, f); c = app.busy('Saving Data', 'Writing file...'); %#ok<NASGU>
            if endsWith(fp, '.uan', 'IgnoreCase', true)
                header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                    min(U.Phi), max(U.Phi), sp, min(U.Theta), max(U.Theta), st, pk);
                writelines(header, fp);
                writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
            elseif endsWith(fp, '.txt', 'IgnoreCase', true), writetable(U, fp, 'Delimiter', '\t');
            else, writetable(U, fp);
            end
            app.say(1, ['UAN exported to <b>' fp '</b>'], true);
        end
    end

    %% ------------------------------------------------------------------ coverage tab
    methods (Access = private)
        function toCoverage(app)
            if isempty(app.viewTbl), uialert(app.UIFigure, 'No processed View Table is available. Load and process a pattern first.', 'Coverage'); return; end
            app.ui.tabs.SelectedTab = app.ui.covTab; app.ui.covPath.Value = app.src.path;
            n = app.covFind(app.src.path);
            if isempty(n), n = app.covAddPattern(app.src.base, app.src.path, app.viewTbl, app.phys.theta, app.phys.phi, app.phys.omega);
            else, app.covSyncFromView(n);
            end
            app.ui.tree.SelectedNodes = n; app.covUI();
            app.say(2, 'Coverage source synchronized from the current Main-tab View Table.', false);
        end

        function [pat, th, ph, omega] = patternFrom(app, out)
            % Coverage pattern from a file (block 1): canonical physical angles.
            S = normalizePattern(out.blocks{1}); S.Properties.UserData = out.meta;
            pat = calcPattern(S, app.params()); th = pat.Theta; ph = pat.Phi; omega = solidWeights(th, ph);
        end

        function onCovLoad(app)
            u = app.ui; fp = strtrim(u.covPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFind(fp))
                [n, p] = uigetfile({'*.uan;*.fz;*.out;*.ffd;*.ffe;*.ffs;*.cut;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage data'; '*.*', 'All files'}, 'Select a pattern or coverage results file');
                if isequal(n, 0), return; end
                fp = fullfile(p, n);
            end
            existing = app.covFind(fp);
            if ~isempty(existing)
                u.tree.SelectedNodes = existing; app.onTreeSelect(); u.covPath.Value = fp; app.covUI();
                app.say(2, 'File already loaded -- node selected. Add another job or load a different file.', true); return
            end
            u.covPath.Value = fp; c = app.busy('Loading Data', 'Reading file...'); %#ok<NASGU>
            out = app.readAny(fp, u.covFmt, u.covFmtLbl);
            if out.meta.isCoverage
                app.covLoadResults(fp, out.rawTbl);
            else
                [~, name] = fileparts(fp); [pat, th, ph, omega] = app.patternFrom(out);
                app.covAddPattern(name, fp, pat, th, ph, omega);
            end
        end

        function onCovFormat(app)
            % Re-interpret a generic-text pattern node with the newly selected format.
            fp = strtrim(app.ui.covPath.Value); n = app.covFind(fp);
            if ~isfile(fp) || ~isGeneric(fp) || isempty(n) || ~strcmp(n.NodeData.kind, 'pattern'), return; end
            out = readSource(fp, app.ui.covFmt.Value);
            if out.meta.isCoverage, app.say(2, 'Coverage-result format is detected automatically; no pattern reprocessing required.', true); return; end
            [pat, th, ph, omega] = app.patternFrom(out); name = n.NodeData.name;
            for j = app.covJobs(n).', delete(j.NodeData.line); end
            delete(n); app.cov.presetKey = "";
            app.covAddPattern(name, fp, pat, th, ph, omega); app.covFinalize();
            app.say(2, sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
        end

        function n = covAddPattern(app, name, path, pat, th, ph, omega)
            n = uitreenode(app.ui.treeRoot, 'Text', ['📡 ' name]);
            n.NodeData = struct('kind', 'pattern', 'name', name, 'path', path, 'pat', pat, 'th', th, 'ph', ph, 'omega', omega, 'rev', app.viewRev);
            expand(app.ui.tree); app.ui.tree.CheckedNodes = [app.ui.tree.CheckedNodes; n]; app.ui.tree.SelectedNodes = n;
            app.covSync(n); app.ui.covResults.Visible = 'on'; app.covUI();
            app.say(2, sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name), false);
        end

        function covSyncFromView(app, n)
            % Main-tab patterns always follow the CURRENT view table (loss, step, span, component derivation).
            d = n.NodeData;
            [d.pat, d.th, d.ph, d.omega, d.rev, d.name] = deal(app.viewTbl, app.phys.theta, app.phys.phi, app.phys.omega, app.viewRev, app.src.base);
            n.NodeData = d; app.covSync(n);
        end

        function covSync(app, n)
            % Align the component dropdown, boresight and threshold preset with a pattern node.
            d = n.NodeData; dd = app.ui.covComp; [cols, labels] = compList(d.pat, app.Labels);
            prev = string(dd.Value); if isfield(d, 'comp'), prev = string(d.comp); end
            c = pickComp(prev, cols); dd.Items = cellstr(labels); dd.ItemsData = cellstr(cols); dd.Value = c;
            changed = ~isfield(d, 'comp') || ~strcmp(d.comp, c);
            if changed
                d.comp = c; pk = resolvePeak(d.pat.(c), app.PeakPct, app.PeakExcess);
                d.boresight = boresightOf(d.th, d.ph, d.pat.(c), d.omega, pk, app.Axes);
            end
            n.NodeData = d;
            key = sprintf('%s|%s|%d', d.path, c, d.rev); % threshold preset only when pattern/component/view changes
            if ~strcmp(app.cov.presetKey, key), app.cov.presetKey = key; app.setThresh(peakWindow(d.pat.(c), app.PeakPct, app.PeakExcess)); end
            if changed && app.ui.orient.Value == 0 && app.ui.con.Value, app.onOrient(); end
        end

        function setThresh(app, b)
            u = app.ui; R = app.Range; set([u.thrMin u.thrMax], 'Limits', R);
            u.thrMin.Value = b(1); u.thrMax.Value = b(2); u.thrMin.Limits = [R(1), b(2) - 0.1]; u.thrMax.Limits = [b(1) + 0.1, R(2)];
        end

        function t = thresholds(app)
            u = app.ui; lo = u.thrMin.Value; hi = u.thrMax.Value; st = max(u.thrStep.Value, 0.1);
            if hi <= lo, hi = min(100, lo + st); u.thrMax.Limits = app.Range; u.thrMax.Value = hi; end
            t = (lo:st:hi).'; if isempty(t) || t(end) < hi - 1e-9, t(end + 1) = hi; end
        end

        function n = covTarget(app)
            % Pattern node to operate on: the selection's pattern ancestor, else the most recent pattern.
            n = []; s = app.ui.tree.SelectedNodes;
            if ~isempty(s)
                n = s(1);
                while isa(n, 'matlab.ui.container.TreeNode') && ~(isstruct(n.NodeData) && strcmp(n.NodeData.kind, 'pattern')), n = n.Parent; end
                if ~isa(n, 'matlab.ui.container.TreeNode'), n = []; end
            end
            if isempty(n)
                kids = app.ui.treeRoot.Children;
                for k = numel(kids):-1:1, if strcmp(kids(k).NodeData.kind, 'pattern'), n = kids(k); return; end; end
            end
        end

        function n = covFind(app, fp)
            n = [];
            for k = app.ui.treeRoot.Children.'
                if isfield(k.NodeData, 'path') && strcmp(k.NodeData.path, fp), n = k; return; end
            end
        end

        function jobs = covJobs(app, roots)
            % All job nodes below ROOTS (default: whole tree), ordered by run id.  The tree IS the registry.
            if nargin < 2, roots = app.ui.treeRoot; end
            jobs = matlab.ui.container.TreeNode.empty(0, 1);
            for r = roots(:).'
                if isstruct(r.NodeData) && strcmp(r.NodeData.kind, 'job'), jobs(end + 1, 1) = r; end %#ok<AGROW>
                jobs = [jobs; app.covJobs(r.Children)]; %#ok<AGROW>
            end
            if numel(jobs) > 1, [~, o] = sort(arrayfun(@(n) n.NodeData.id, jobs)); jobs = jobs(o); end
        end

        function covAddJob(app, parent, thr, cov, comp, tagFull, tableTag, conical, orient)
            app.cov.runID = app.cov.runID + 1; id = app.cov.runID;
            icon = '📉'; if strcmp(parent.NodeData.kind, 'results'), icon = '📈'; end
            label = sprintf('%s R%d %s · %s', icon, id, tagFull, comp);
            h = plot(app.ui.covAx, thr, cov, 'LineWidth', 1.6, 'DisplayName', label);
            h.DataTipTemplate.DataTipRows = [dataTipTextRow('Threshold (dB)', 'XData', '%.2f'); dataTipTextRow('Coverage (%)', 'YData', '%.2f')];
            j = uitreenode(parent, 'Text', label);
            j.NodeData = struct('kind', 'job', 'id', id, 'thr', thr(:), 'cov', cov(:), 'line', h, 'label', label, 'tableTag', tableTag, ...
                'conical', conical, 'orient', string(orient), 'step', gridStep(thr));
            expand(parent); app.ui.tree.CheckedNodes = [app.ui.tree.CheckedNodes; j];
        end

        function covFinalize(app)
            % Rebuild the results table and legend from the CHECKED jobs, then refresh control states.
            jobs = app.covJobs(); on = jobs(ismember(jobs, app.ui.tree.CheckedNodes)); ax = app.ui.covAx;
            thr = app.thresholds();
            if ~isempty(on), c = arrayfun(@(n) n.NodeData.thr, on, 'UniformOutput', false); thr = unique(vertcat(c{:})); end
            V = nan(numel(thr), numel(on) + 1); V(:, 1) = thr; names = [{'Threshold (dB)'}, cell(1, numel(on))];
            L = gobjects(1, numel(on)); labels = cell(1, numel(on));
            for k = 1:numel(on)
                d = on(k).NodeData; V(:, k + 1) = interp1(d.thr, d.cov, thr, 'linear', NaN);
                names{k + 1} = sprintf('R%d %s %%', d.id, d.tableTag); L(k) = d.line; labels{k} = d.label;
            end
            app.ui.covTbl.Data = array2table(compose('%.2f', V), 'VariableNames', names);
            if isempty(on), legend(ax, 'off'); else, legend(ax, L, labels, 'Location', 'southwest', 'Interpreter', 'none'); end
            app.covUI();
        end

        function covUI(app)
            % Control enabling follows two facts: is there a pattern node, are there job nodes.
            u = app.ui; hasPat = ~isempty(app.covTarget()); hasJobs = ~isempty(app.covJobs()); conical = u.con.Value;
            set([u.covCompute u.covComp u.covCompLbl], 'Enable', hasPat);
            set([u.orient u.orientLbl u.coneTh u.coneThLbl u.conePh u.conePhLbl u.coneAng u.coneAngLbl], 'Enable', hasPat && conical, 'Visible', conical);
            set([u.covExport u.covClear u.qCov u.qCovBtn u.qCovLbl u.qThr u.qThrBtn u.qThrLbl], 'Enable', hasJobs);
            u.covReset.Enable = hasPat || hasJobs;
            set([u.covFmtLbl u.covFmt], 'Visible', hasPat && isGeneric(u.covPath.Value));
        end

        function onCovType(app)
            app.covUI();
            if app.ui.con.Value
                n = app.covTarget(); if ~isempty(n), app.covSync(n); end
                app.reportOrient();
            else
                app.ui.covStatus.Text = regexprep(char(app.ui.covStatus.Text), '\s*\|\s*Orientation <b>.*?</b>', '');
            end
        end

        function lab = orientLabel(app)
            % Auto resolves the node's detected boresight; an explicit selection is authoritative.
            i = app.ui.orient.Value; lab = "n/a";
            if i == 0
                n = app.covTarget(); if isempty(n) || ~isfield(n.NodeData, 'boresight'), return; end
                i = n.NodeData.boresight;
            end
            lab = string(app.Axes.labels{i});
        end

        function onOrient(app)
            i = find(strcmp(app.Axes.labels, app.orientLabel()), 1); if isempty(i), return; end
            app.ui.coneTh.Value = app.Axes.theta(i); app.ui.conePh.Value = app.Axes.phi(i); app.reportOrient();
        end

        function reportOrient(app)
            if ~app.ui.con.Value, return; end
            lab = app.orientLabel(); if lab == "n/a", return; end
            cur = regexprep(char(app.ui.covStatus.Text), '\s*\|\s*Orientation <b>.*?</b>', '');
            app.say(2, sprintf('%s | Orientation <b>%s</b>', cur, lab), false);
        end

        function onCovComp(app)
            n = app.covTarget(); if isempty(n), return; end
            d = n.NodeData; if isfield(d, 'comp'), d = rmfield(d, 'comp'); end % force re-detection for the new component
            n.NodeData = d; app.covSync(n); app.reportOrient();
        end

        function lab = coneLabel(app, th, ph)
            % Principal-axis name when the cone centre coincides with ±X/±Y/±Z, else the explicit angles.
            m = find(dirVec(app.Axes.theta(:), app.Axes.phi(:))*dirVec(th, ph).' >= 1 - 1e-9, 1);
            if isempty(m), lab = sprintf('θ=%s°, φ=%s°', fmtNum(th), fmtNum(ph)); else, lab = app.Axes.labels{m}; end
        end

        function onCovCompute(app)
            n = app.covTarget();
            if isempty(n), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if strcmp(n.NodeData.path, app.src.path) && ~isempty(app.viewTbl), app.covSyncFromView(n); end
            d = n.NodeData; u = app.ui; c = u.covComp.Value; thr = app.thresholds(); conical = u.con.Value;
            if conical
                th0 = u.coneTh.Value; ph0 = mod(u.conePh.Value, 360); a = u.coneAng.Value;
                mask = dirVec(d.th, d.ph)*dirVec(th0, ph0).' >= cosd(a);
                center = app.coneLabel(th0, ph0); orient = app.orientLabel();
                tagFull = sprintf('Conical coverage (%s) α=%s°', center, fmtNum(a)); tableTag = sprintf('Con %s α%s°', erase(center, ["=", ","]), fmtNum(a));
            else
                mask = true(height(d.pat), 1); tagFull = 'Sph coverage'; tableTag = 'Sph'; orient = "n/a";
            end
            cov = coverageCCDF(d.pat.(c), mask, thr, d.omega);
            app.covAddJob(n, thr, cov, c, tagFull, tableTag, conical, orient);
            app.covFinalize(); app.covXRange([thr(1) thr(end)], "auto"); u.covResults.Visible = 'on';
            s = sprintf('Run-<b>%d</b> computed: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', app.cov.runID, tagFull, d.name, c, numel(thr));
            if conical, s = sprintf('%s | Orientation <b>%s</b>', s, orient); end
            app.say(2, s, false);
        end

        function covLoadResults(app, fp, T)
            [~, name] = fileparts(fp); n = uitreenode(app.ui.treeRoot, 'Text', ['📄 ' name]);
            n.NodeData = struct('kind', 'results', 'name', name, 'path', fp);
            thr = T{:, 1}; vn = T.Properties.VariableNames;
            for k = 2:width(T), app.covAddJob(n, thr, T{:, k}, vn{k}, 'Res', vn{k}, false, "n/a"); end
            app.ui.tree.CheckedNodes = [app.ui.tree.CheckedNodes; n]; expand(app.ui.treeRoot);
            app.covXRange([min(thr) max(thr)], "auto", gridStep(thr)); app.covFinalize(); app.ui.covResults.Visible = 'on';
            app.say(2, sprintf('Coverage results file "%s" loaded (%d curves).', name, width(T) - 1), false);
        end

        function covXRange(app, b, src, step)
            % Coverage plot X window.  Spinners are the master (define slider travel); the slider only narrows XLim.
            u = app.ui; R = app.Range;
            if src == "auto" % first result sets the baseline, later ones may only widen it
                if app.cov.xInit, b = [min(u.xMin.Value, b(1)), max(u.xMax.Value, b(2))]; end
                app.cov.xInit = true;
                if nargin > 3 && isfinite(step) && step < u.thrStep.Value, u.thrStep.Value = step; end
            end
            b = sort(double(b)); b = max(R(1), min(R(2), b));
            if diff(b) <= 0, b(2) = min(R(2), b(1) + max(u.xSlider.Step, 0.1)); end
            if src ~= "slider", set(u.xSlider, 'Limits', R, 'Value', b); u.xSlider.Limits = b; end
            set([u.xMin u.xMax], 'Limits', R); u.xMin.Value = b(1); u.xMax.Value = b(2);
            u.xMin.Limits = [R(1), b(2) - 0.1]; u.xMax.Limits = [b(1) + 0.1, R(2)];
            set(u.covAx, 'XLimMode', 'manual', 'XLim', b);
        end

        function covQuery(app, mode)
            % Mark coverage at a threshold ("cov") or the threshold reaching a coverage ("thr") on checked curves.
            u = app.ui; ax = u.covAx; s = u.tree.SelectedNodes;
            if isempty(s), app.say(2, 'Select a node to query.', true); return; end
            jobs = app.covJobs(s); jobs = jobs(ismember(jobs, u.tree.CheckedNodes));
            if isempty(jobs), app.say(2, 'No checked results under selected node.', true); return; end
            if mode == "cov", q = u.qCov.Value; else, q = u.qThr.Value; end
            hit = false;
            for j = jobs.'
                d = j.NodeData; tag = sprintf('CovQ_%d', d.id); delete(findall(ax, 'Tag', tag));
                if numel(d.thr) < 2, continue; end
                if mode == "cov", x = q; y = interp1(d.thr, d.cov, q, 'linear', NaN);
                else, [cv, i] = unique(d.cov, 'last'); y = q; x = NaN; if numel(cv) > 1, x = interp1(cv, d.thr(i), q, 'linear', NaN); end
                end
                if ~isfinite(x) || ~isfinite(y), continue; end
                col = d.line.Color;
                line(ax, [x x], [0 y], 'Color', col, 'LineStyle', ':', 'Tag', tag); line(ax, [app.Range(1) x], [y y], 'Color', col, 'LineStyle', ':', 'Tag', tag);
                try, t = datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'FontSize', 9); t.Tag = tag; catch, end
                hit = true;
            end
            if ~hit, app.say(2, 'Query value is outside the selected checked range.', true);
            elseif mode == "cov", app.say(2, sprintf('Coverage queried at %s dB.', fmtNum(q)), false);
            else, app.say(2, sprintf('Threshold queried at %s%% coverage.', fmtNum(q)), false);
            end
        end

        function onTreeCheck(app)
            checked = app.ui.tree.CheckedNodes;
            for j = app.covJobs().'
                d = j.NodeData; vis = ismember(j, checked); d.line.Visible = vis;
                set(findall(app.ui.covAx, 'Tag', sprintf('CovQ_%d', d.id)), 'Visible', vis);
                set(findall(d.line, 'Type', 'datatip'), 'Visible', vis);
            end
            app.covFinalize();
        end

        function onTreeSelect(app)
            s = app.ui.tree.SelectedNodes;
            for j = app.covJobs().' % emphasise the selected curve
                h = j.NodeData.line; h.LineWidth = 1.6 + double(~isempty(s) && j == s(1));
            end
            if isempty(s) || ~isstruct(s(1).NodeData), app.say(2, 'Ready.', false); return; end
            d = s(1).NodeData; n = app.covTarget(); if ~isempty(n), app.covSync(n); end
            if ~strcmp(d.kind, 'job')
                kind = 'Pattern'; if strcmp(d.kind, 'results'), kind = 'Results'; end
                c = numel(s(1).Children);
                app.say(2, sprintf('%s <b>"%s"</b> -- <b>%d</b> coverage job%s.', kind, d.name, c, repmat('s', 1, double(c ~= 1))), false);
                if strcmp(d.kind, 'pattern'), app.reportOrient(); end
                return
            end
            parts = {char(d.label)};
            if d.conical && d.orient ~= "n/a", parts{end + 1} = sprintf('Orientation <b>%s</b>', d.orient); end
            parts{end + 1} = sprintf('Threshold [%s, %s] dB | Step %s dB', fmtNum(d.thr(1)), fmtNum(d.thr(end)), fmtNum(d.step));
            ok = isfinite(d.thr) & isfinite(d.cov);
            if any(ok)
                t = d.thr(ok); cv = d.cov(ok); [uc, i] = unique(cv, 'last'); thr50 = NaN;
                if numel(uc) > 1, thr50 = interp1(uc, t(i), 50, 'linear', NaN); end
                shown = round(cv, 2); mx = max(shown); k = find(shown == mx, 1, 'last');
                if isfinite(thr50), parts{end + 1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', fmtNum(thr50)); else, parts{end + 1} = '<b>50%-coverage unavailable</b>'; end
                parts{end + 1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmtNum(mx), fmtNum(t(k)));
            end
            app.say(2, strjoin(parts, ' | '), false);
        end

        function onCovReset(app)
            u = app.ui; delete(u.treeRoot.Children);
            cla(u.covAx); legend(u.covAx, 'off'); hold(u.covAx, 'on'); grid(u.covAx, 'on'); ylim(u.covAx, [0 100]); set(u.covAx, 'XLimMode', 'auto');
            u.covTbl.Data = table(); app.cov = struct('runID', 0, 'presetKey', "", 'xInit', false);
            set([u.xMin u.xMax u.xSlider], 'Limits', app.Range); u.xMin.Value = -40; u.xMax.Value = 10; u.xSlider.Value = [-40 10];
            u.covResults.Visible = 'off'; app.covUI(); app.say(2, 'Coverage workspace reset 🔄', true);
        end

        function onCovClear(app)
            s = app.ui.tree.SelectedNodes;
            if isempty(s), app.say(2, 'Select a node to clear.', true); return; end
            jobs = app.covJobs(s);
            if isempty(jobs), app.say(2, 'No coverage results under selected node.', true); return; end
            for j = jobs.'
                d = j.NodeData; delete(findall(app.ui.covAx, 'Tag', sprintf('CovQ_%d', d.id))); delete(findall(d.line, 'Type', 'datatip'));
            end
            app.say(2, 'Selected DataTips and query markers cleared.', true);
        end
    end
end

%% ====================================================================== local functions
% Pure, UI-independent services.  Everything below works on PHYSICAL angles.

%% ---------------------------------------------------------------------- source readers
function out = readSource(fp, fmt, cached)
%READSOURCE Read any supported pattern / coverage file → struct(rawTbl, blocks, freqs, meta).
if nargin < 3, cached = table(); end
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
switch ext
    case {'XLSX', 'XLS'}, out = readExcelMatrix(fp);
    case {'CSV', 'TXT', 'DAT'}, out = readGeneric(fp, string(fmt), cached);
    case 'CUT', out = readGraspCut(fp);
    case {'UAN', 'FZ', 'OUT', 'FFS', 'FFE', 'FFD'}, out = readFarField(fp, ext);
    otherwise, error('readFile:unsupported', 'Unsupported format: %s', ext);
end
out.meta = defaultMeta(out.meta);
end

function m = defaultMeta(m)
d = struct('source', 'unknown', 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'isMultiBlock', false, 'hasFrequency', false, 'polarizationBasis', "theta-phi");
for f = fieldnames(d).', if ~isfield(m, f{1}) || isempty(m.(f{1})), m.(f{1}) = d.(f{1}); end, end
end

function tf = isGeneric(fp)
[~, ~, e] = fileparts(fp); tf = ismember(lower(e), {'.csv', '.txt', '.dat'});
end

function out = packSource(raw, blocks, freqs, meta)
%PACKSOURCE Uniform reader result.
out = struct('rawTbl', raw, 'blocks', {blocks}, 'freqs', freqs, 'meta', meta);
end

function T = fieldTable(th, ph, Eth, Eph)
T = table(th(:), ph(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function E = magPhase(dB, deg)
E = 10.^(dB/20).*exp(1i*deg2rad(deg));
end

function [Eth, Eph] = circToLin(Er, El)
Eth = (Er + El)/sqrt(2); Eph = (Er - El)/(1i*sqrt(2));
end

function out = readGeneric(fp, fmt, T)
%READGENERIC CSV/TXT/DAT: coverage-results table, gain-only pattern, or 6-column E-field pattern.
if isempty(T)
    opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    opts = setvartype(opts, 'double'); opts = setvaropts(opts, 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
    T = rmmissing(readtable(fp, opts));
end
nc = width(T); assert(nc >= 2 && height(T) > 0, 'readFile:InvalidFormat', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHdr = ~all(startsWith(names, "Var")); c1 = T{:, 1}; c2 = T{:, 2}; raw = T;
covHdr = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
if (fmt == "gain" || nc < 6 || covHdr) && all(isfinite(c2)) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHdr, T.Properties.VariableNames = cellstr(["Threshold_dB", "Coverage_" + (1:nc - 1)]); end
    out = packSource(T, {}, NaN, struct('source', 'Coverage results', 'isCoverage', true)); return
end
if fmt == "gain" % the wider-spanning of the first two columns is φ
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    T = movevars(T, 'Theta', 'Before', 1); if ~hasHdr, raw = T; end
    out = packSource(raw, {T}, NaN, struct('source', 'Generic text (gain)', 'isGainOnly', true)); return
end
assert(nc >= 6, 'readFile:TextEFieldColumns', 'The selected generic E-field format requires six numeric columns.');
V = T{:, 3:6}; magphase = endsWith(fmt, "magphase"); lin = startsWith(fmt, "linear"); layout = "n/a";
if magphase % detect [mag mag ph ph] vs [mag ph mag ph] from the phase-like column range
    big = max(abs(V), [], 1, 'omitnan') > 100;
    if big(2) && ~big(3), mc = [1 3]; pc = [2 4]; layout = "interleaved"; else, mc = [1 2]; pc = [3 4]; layout = "grouped"; end
    a = magPhase(V(:, mc(1)), V(:, pc(1))); b = magPhase(V(:, mc(2)), V(:, pc(2)));
else
    a = complex(V(:, 1), V(:, 2)); b = complex(V(:, 3), V(:, 4));
end
if lin, Eth = a; Eph = b; comps = ["E_TH", "E_PH"]; rect = ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"];
else
    if startsWith(fmt, "lcp"), [a, b] = deal(b, a); end
    [Eth, Eph] = circToLin(a, b); comps = ["POL1", "POL2"]; rect = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"];
end
if ~hasHdr
    if magphase, fn = [comps + "_dB", comps + "_deg"]; if layout == "interleaved", fn = fn([1 3 2 4]); end, else, fn = rect; end
    raw.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", fn]);
end
out = packSource(raw, {fieldTable(c1, c2, Eth, Eph)}, NaN, struct('source', sprintf('Generic text (%s, %s)', fmt, layout)));
end

function out = readGraspCut(fp)
%READGRASPCUT TICRA/GRASP *.cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks.
L = readlines(fp); L(strlength(strtrim(L)) == 0) = []; th = {}; ph = {}; D = {}; i = 1; icomp = 1; icut = 1;
while i < numel(L)
    p = sscanf(L(i + 1), '%f'); assert(numel(p) >= 7, 'parseCutFile:bad', 'Could not parse cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6);
    D{end + 1, 1} = reshape(sscanf(strjoin(L(i + 2:i + 1 + n), ' '), '%f'), 2*p(7), []).'; %#ok<AGROW>
    th{end + 1, 1} = p(1) + (0:n - 1).'*p(2); ph{end + 1, 1} = repmat(p(4), n, 1); i = i + 2 + n; %#ok<AGROW>
end
th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:}); D = D(:, 1:4);
if icut == 2, [th, ph] = deal(ph, th); end % φ swept, θ constant
neg = th < 0; ph(neg) = ph(neg) + 180; th(neg) = -th(neg);
if isscalar(unique(ph)) % a single cut is treated as a body of revolution
    pc = (0:10:350).'; n = numel(th); th = repmat(th, numel(pc), 1); ph = repelem(pc, n); D = repmat(D, numel(pc), 1);
end
a = complex(D(:, 1), D(:, 2)); b = complex(D(:, 3), D(:, 4));
if icomp == 2, names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; [Eth, Eph] = circToLin(a, b);
else, names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; Eth = a; Eph = b;
end
out = packSource(array2table([th ph D], 'VariableNames', names), {fieldTable(th, ph, Eth, Eph)}, NaN, struct('source', 'TICRA/GRASP CUT'));
end

function [nHdr, ffd] = scanHeader(fp)
%SCANHEADER Count leading non-data lines; recognise the HFSS FFD header (two numeric triples [+ Frequencies]).
L = cellstr(readlines(fp)); ffd = struct('ok', false, 'theta', [], 'phi', [], 'freq', []);
ne = find(~cellfun(@(s) isempty(strtrim(s)), L), 3);
nums = cellfun(@(s) sscanf(s, '%f').', L(ne), 'UniformOutput', false);
if numel(ne) >= 2 && numel(nums{1}) == 3 && numel(nums{2}) == 3
    ffd = struct('ok', true, 'theta', nums{1}, 'phi', nums{2}, 'freq', []); nHdr = ne(2);
    if numel(ne) == 3
        tok = regexp(strtrim(L{ne(3)}), '^frequencies?\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok), nHdr = ne(3); f = sscanf(tok{1}, '%f'); if numel(f) > 1, ffd.freq = f(:); end, end
    end
    return
end
num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?';
first = find(~cellfun(@isempty, regexp(L, ['^\s*' num '(?:[\s,;]+' num '){3,}\s*$'], 'once')), 1);
nHdr = 0; if ~isempty(first), nHdr = first - 1; end
end

function out = readFarField(fp, ext)
%READFARFIELD XGTD UAN/FZ, GRASP OUT, CST FFS, FEKO FFE, HFSS FFD (single- or multi-frequency).
[nHdr, ffd] = scanHeader(fp);
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvartype(opts, opts.VariableNames, 'double'); D = readmatrix(fp, opts);
D = D(~all(isnan(D), 2), :); D = D(:, 1:min(end, 6));
if strcmp(ext, 'FFD')
    assert(ffd.ok, 'readFile:ffd', 'FFD header (theta/phi ranges) not found.');
    tA = linspace(ffd.theta(1), ffd.theta(2), round(ffd.theta(3))).'; pA = linspace(ffd.phi(1), ffd.phi(2), round(ffd.phi(3))).';
    th = repelem(tA, numel(pA)); ph = repmat(pA, numel(tA), 1); n = numel(th);
    sep = isnan(D(:, 1)); f = [ffd.freq(:); D(sep, 2)]; f = f(isfinite(f)).'; F = D(~sep, 1:4); % "Frequency <f>" separator rows
    assert(mod(size(F, 1), n) == 0, 'readFile:ffd', 'FFD row count does not match the theta/phi grid.'); nb = size(F, 1)/n;
    f(end + 1:nb) = NaN; f = f(1:nb);
    blocks = cellfun(@(B) fieldTable(th, ph, complex(B(:, 1), B(:, 2)), complex(B(:, 3), B(:, 4))), mat2cell(F, repmat(n, nb, 1), 4), 'UniformOutput', false);
    meta = struct('source', 'HFSS FFD', 'isMultiBlock', nb > 1, 'hasFrequency', any(isfinite(f))); meta.isDep = meta.isMultiBlock || meta.hasFrequency;
    out = packSource(blocks{1}, blocks, f, meta); return
end
assert(size(D, 2) >= 6, 'readFile:columns', '%s files need six numeric columns.', ext);
th = D(:, 1); ph = D(:, 2);
switch ext
    case {'UAN', 'FZ'}, src = ['XGTD ' ext]; names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}; Eth = magPhase(D(:, 3), D(:, 5)); Eph = magPhase(D(:, 4), D(:, 6));
    case 'OUT', src = 'TICRA/GRASP OUT'; names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; [Eth, Eph] = circToLin(complex(D(:, 3), D(:, 4)), complex(D(:, 5), D(:, 6)));
    case 'FFS', src = 'CST FFS'; names = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; ph = D(:, 1); th = D(:, 2); Eth = complex(D(:, 3), D(:, 4)); Eph = complex(D(:, 5), D(:, 6));
    case 'FFE', src = 'FEKO FFE'; names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; Eth = complex(D(:, 3), D(:, 4)); Eph = complex(D(:, 5), D(:, 6));
end
out = packSource(array2table(D(:, 1:6), 'VariableNames', names), {fieldTable(th, ph, Eth, Eph)}, NaN, struct('source', src));
end

function out = readExcelMatrix(fp)
%READEXCELMATRIX Matrix-template workbooks: summary sheet + fixed Eth/Eph and/or RHCP/LHCP gain+phase sheets (C3 origin).
sheets = string(sheetnames(fp));
lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
cir = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"];
hasL = all(ismember(lower(lin), lower(sheets))); hasC = all(ismember(lower(cir), lower(sheets)));
assert(hasL || hasC, 'readFile:ExcelMatrixFormat', 'Unsupported Excel workbook: the sheets after the summary must contain the fixed Eth/Eph and/or RHCP/LHCP component sheets.');
req = [cir(1:4*hasC), lin(1:4*hasL)]; M = struct();
for k = 1:numel(req)
    [th, ph, D] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, req(k)), 1)));
    if k == 1, th0 = th; ph0 = ph;
    else, assert(isequal(size(D), [numel(th0) numel(ph0)]) && max(abs(th - th0)) < 1e-9 && max(abs(ph - ph0)) < 1e-9, 'readFile:ExcelMatrixGrid', 'All Excel Matrix component sheets must use the same theta/phi grid.');
    end
    M.(req(k)) = D;
end
if hasL, Eth = magPhase(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = magPhase(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees); basis = "theta-phi"; code = 1 + 2*hasC;
else, [Eth, Eph] = circToLin(magPhase(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), magPhase(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees)); basis = "RHCP/LHCP"; code = 2;
end
[PH, TH] = meshgrid(ph0, th0); block = fieldTable(TH, PH, Eth, Eph); raw = block;
for k = 1:numel(req), raw.(req(k)) = reshape(M.(req(k)), [], 1); end
meta = struct('source', sprintf('Excel Matrix Format %d (%s)', code, basis), 'polarizationBasis', basis, 'summary', readSummary(fp, sheets(1)));
out = packSource(raw, {block}, NaN, meta);
end

function [th, ph, D] = readMatrixSheet(fp, sheet)
% readcell keeps worksheet coordinates (readmatrix would auto-trim and break the C3-origin contract).
C = readcell(fp, 'Sheet', char(sheet));
assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'readFile:ExcelMatrixSheet', 'Sheet "%s" does not contain a C3-origin matrix.', sheet);
isnum = @(x) isnumeric(x) && isscalar(x) && isfinite(x);
pm = cellfun(isnum, C(2, 3:end)); tm = cellfun(isnum, C(3:end, 2));
nP = find(~pm, 1) - 1; if isempty(nP), nP = numel(pm); end; nT = find(~tm, 1) - 1; if isempty(nT), nT = numel(tm); end
assert(nP > 0 && nT > 0 && ~any(pm(nP + 1:end)) && ~any(tm(nT + 1:end)), 'readFile:ExcelMatrixAxis', 'Sheet "%s" has a missing or gapped theta/phi axis.', sheet);
ph = cell2mat(C(2, 3:2 + nP)).'; th = cell2mat(C(3:2 + nT, 2)); D = C(3:2 + nT, 3:2 + nP);
assert(all(cellfun(isnum, D(:))), 'readFile:ExcelMatrixSheet', 'Sheet "%s" contains nonnumeric/missing matrix samples.', sheet);
D = cell2mat(D);
assert(all(diff(th) > 0) && all(diff(ph) > 0) && th(1) >= -1e-9 && th(end) <= 180 + 1e-9 && ph(1) >= -1e-9 && ph(end) < 360 + 1e-9, ...
    'readFile:ExcelMatrixAxis', 'Sheet "%s" must have strictly increasing axes inside θ 0..180, φ 0..360.', sheet);
end

function S = readSummary(fp, sheet)
% Harvest "label → value" pairs from the template summary sheet (label in column B, value in C..E).
S = struct();
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
has = @(v) ~isa(v, 'missing') && ~isempty(v);
for r = 1:size(C, 1)
    lab = C{r, 2}; if ~(ischar(lab) || isstring(lab)) || strlength(strtrim(string(lab))) == 0, continue; end
    v = []; for c = 3:min(5, size(C, 2)), if has(C{r, c}), v = C{r, c}; break; end, end
    if isempty(v), continue; end
    key = matlab.lang.makeValidName(lower(regexprep(strtrim(string(lab)), '[^a-zA-Z0-9]+', '_')));
    S.(char(key)) = v;
    if contains(lower(lab), 'freq') && contains(lower(lab), 'mhz') && ~isfield(S, 'frequencyMHz') && isnumeric(v), S.frequencyMHz = double(v); end
end
end

%% ---------------------------------------------------------------------- canonical model & processing
function T = normalizePattern(T)
%NORMALIZEPATTERN Map angles onto the canonical sphere: θ ∈ [0,180], φ ∈ [0,360) plus one closing φ=360 seam.
th = T.Theta;
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, T.Theta = 90 - th; % elevation convention
    else, m = th < 0; T.Theta(m) = -th(m); T.Phi(m) = T.Phi(m) + 180; % negative θ folds onto the opposite φ
    end
end
num = varfun(@isnumeric, T, 'OutputFormat', 'uniform'); T{:, num} = round(T{:, num}, 5); % deterministic 5-decimal grid
th = mod(T.Theta, 360); over = th > 180; T.Theta = th; T.Theta(over) = 360 - th(over); T.Phi(over) = T.Phi(over) + 180;
T.Phi = mod(T.Phi, 360); T.Theta(abs(T.Theta) < 1e-12) = 0; T.Phi(abs(T.Phi) < 1e-12) = 0;
[~, u] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(u, :);
seam = T(abs(T.Phi) < 1e-10, :); seam.Phi(:) = 360; T = [T; seam];
end

function [T, info] = calcPattern(S, p)
%CALCPATTERN Canonical source → processed pattern table (all derived quantities in one pass).
meta = S.Properties.UserData;
info = struct('pol', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
if meta.isGainOnly
    T = S; if width(T) > 2, T{:, 3:end} = T{:, 3:end} + p.GainLoss_dB; end
    return
end
Eth = complex(S.Re_Eth, S.Im_Eth)*p.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph)*p.FieldScale;
Er = (Eth + 1i*Eph)/sqrt(2); El = (Eth - 1i*Eph)/sqrt(2);
mt = abs(Eth); mp = abs(Eph); mr = abs(Er); ml = abs(El);
total = 10*log10(max(mt.^2 + mp.^2, eps));
% Dominant polarization drives co/cross ordering, the label and the Auto Rx sense.
pw = [mean(mt.^2, 'omitnan'), mean(mp.^2, 'omitnan'), mean(mr.^2, 'omitnan'), mean(ml.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif pw(1) >= pw(2), info.pol = 'Linear (Vertical)';
else, info.pol = 'Linear (Horizontal)';
end
% Signed axial ratio: + RHCP sense, − LHCP sense; equal circular components → −100 dB floor.
d = mr - ml; sense = sign(d); sense(~isfinite(d)) = 0; ar = (mr + ml)./max(abs(d), eps);
arDB = min(20*log10(ar), 250).*sense; arDB(isfinite(d) & abs(d) <= eps*max(mr + ml, 1)) = -100;
% Polarization loss factor against the incident wave (worst-case tilt alignment).
if p.RxMode == "Auto", ws = 2*(info.pairs.Circular(1) == "E_RCP") - 1; elseif p.RxMode == "RHCP", ws = 1; else, ws = -1; end
ra = ar.*sense; ra(sense == 0) = 1e12; rw = ws*10^(p.RxAR_dB/20);
plf = 10*log10(min(max(0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1))./(2*(ra.^2 + 1)*(rw^2 + 1)), eps), 1));
eirp = p.Pt_dBW + total; W = 10.^(eirp/10);
T = table(S.Theta, S.Phi, total, arDB, 20*log10(max(mr, eps)), 20*log10(max(ml, eps)), plf, total + plf, ...
    20*log10(max(mt, eps)), 20*log10(max(mp, eps)), rad2deg(angle(Eth)), rad2deg(angle(Eph)), rad2deg(angle(Er)), rad2deg(angle(El)), ...
    eirp, W/(4*pi*p.R_m^2), sqrt(30*W)/p.R_m, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', 'PLF_dB', ...
    'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
T.Properties.UserData = meta;
end

function R = resampleCanonical(S, step)
%RESAMPLECANONICAL Resample primitive canonical data onto a step° grid (φ periodic, closing seam included).
%   Regular grids use interp2; irregular samples use one scattered interpolant per column.
%   Gain-only sources are interpolated in linear power.
names = string(S.Properties.VariableNames); cols = names(3:end); meta = S.Properties.UserData;
th = double(S.Theta); ph = mod(double(S.Phi), 360);
keep = find(isfinite(th) & isfinite(ph) & th >= -1e-9 & th <= 180 + 1e-9 & abs(double(S.Phi) - 360) > 1e-9);
[~, u] = unique([th(keep) ph(keep)], 'rows', 'stable'); keep = keep(u); S = S(keep, :); th = th(keep); ph = ph(keep);
tT = (0:step:180).'; tP = (0:step:360).'; if tP(end) ~= 360, tP(end + 1) = 360; end
[QP, QT] = meshgrid(tP, tT); R = table(QT(:), QP(:), 'VariableNames', {'Theta', 'Phi'});
uT = unique(th); uP = unique(ph); regular = numel(uT)*numel(uP) == numel(th);
if regular
    [~, i] = ismember(th, uT); [~, j] = ismember(ph, uP); lin = sub2ind([numel(uT) numel(uP)], i, j);
    regular = numel(unique(lin)) == numel(lin); [PG, TG] = meshgrid(uP, uT);
    if uP(end) < uP(1) + 360 - 1e-9, PG(:, end + 1) = PG(:, 1) + 360; TG(:, end + 1) = TG(:, 1); end % periodic φ column
end
gainMode = isstruct(meta) && isfield(meta, 'isGainOnly') && meta.isGainOnly;
for c = cols
    v = double(S.(c)); if gainMode, v = 10.^(v/10); end
    if regular
        G = nan(numel(uT), numel(uP)); G(lin) = v; if size(PG, 2) > size(G, 2), G(:, end + 1) = G(:, 1); end
        q = interp2(PG, TG, G, QP, QT, 'linear', NaN); miss = ~isfinite(q);
        if any(miss(:)), n = interp2(PG, TG, G, QP, QT, 'nearest', NaN); q(miss) = n(miss); end
    else
        F = scatteredInterpolant(ph, th, v, 'linear', 'nearest'); q = F(QP, QT);
    end
    if gainMode, q = 10*log10(max(q, realmin)); end
    R.(c) = q(:);
end
R.Properties.UserData = meta;
end

%% ---------------------------------------------------------------------- peak policy & ranges
function info = resolvePeak(v, pct, excess)
%RESOLVEPEAK Raw maximum, unless it exceeds the PCT percentile by more than EXCESS dB (isolated spike);
%   then the highest sample at or below the percentile is the effective peak.
info = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(v)), 'wasAdjusted', false);
f = isfinite(v); if ~any(f), return; end
[info.rawValue, info.rawIndex] = max(v, [], 'omitnan'); info.value = info.rawValue; info.index = info.rawIndex;
q = percentile(v(f), pct);
if info.rawValue <= q + excess, return; end
out = f & v > q; cand = v; cand(~(f & ~out)) = -Inf;
if any(f & ~out), [info.value, info.index] = max(cand); info.outlierMask = out; info.wasAdjusted = true; end
end

function q = percentile(v, p)
% Toolbox-free percentile using MATLAB's prctile definition (sample k sits at 100(k−0.5)/n).
v = sort(v(:)); n = numel(v);
if n == 0, q = NaN; elseif n == 1, q = v; else, pos = 100*((1:n).' - 0.5)/n; q = interp1(pos, v, min(max(p, pos(1)), pos(end))); end
end

function b = peakWindow(v, pct, excess)
%PEAKWINDOW 50-dB display / threshold window whose top is the effective peak rounded up to 5 dB.
v = v(isfinite(v)); b = [-40 10]; if isempty(v), return; end
pk = resolvePeak(v, pct, excess); if ~isfinite(pk.value), return; end
hi = ceil(pk.value/5)*5; b = min(max([hi - 50, hi], -250), 100); if diff(b) < 1, b(1) = max(-250, b(2) - 50); end
end

%% ---------------------------------------------------------------------- geometry, metrics, cuts
function V = dirVec(th, ph)
V = [sind(th(:)).*cosd(ph(:)), sind(th(:)).*sind(ph(:)), cosd(th(:))];
end

function s = gridStep(v)
v = unique(v(isfinite(v))); d = diff(v); d = d(d > 1e-9); s = NaN; if ~isempty(d), s = min(d); end
end

function w = solidWeights(th, ph)
%SOLIDWEIGHTS Exact solid angle of each uniform θ/φ cell; the canonical φ=360 duplicate carries none.
ts = gridStep(th); ps = gridStep(mod(ph, 360)); if ~isfinite(ts), ts = 180; end; if ~isfinite(ps), ps = 360; end
w = (cosd(max(th - ts/2, 0)) - cosd(min(th + ts/2, 180)))*deg2rad(ps);
w(abs(ph - 360) < 1e-9) = 0;
end

function k = boresightOf(th, ph, g, omega, pk, A)
%BORESIGHTOF Principal axis whose 45° cone captures the most peak-normalised power (outliers excluded).
if pk.wasAdjusted, g(pk.outlierMask) = NaN; end
w = 10.^((g - pk.value)/10).*omega; w(~isfinite(w)) = 0;
[~, k] = max(w.'*double(dirVec(th, ph)*dirVec(A.theta(:), A.phi(:)).' >= cosd(45)));
end

function [type, v] = planeDef(k, A, isE)
%PLANEDEF E-plane: θ-cut through the axis φ.  H-plane: φ-cut at θ=90 for transverse axes, else θ-cut at φ=90.
if isE, type = "Theta"; v = A.phi(k); elseif A.theta(k) == 90, type = "Phi"; v = 90; else, type = "Theta"; v = 90; end
end

function [ang, rows, fixed] = cutRows(th, ph, type, v)
%CUTROWS Rows of one full-circle cut (physical angles), sorted by ang ∈ [0,360) with duplicates removed.
w = mod(ph, 360);
if type == "Phi" % fixed θ, sweep φ
    tv = unique(th); [~, i] = min(abs(tv - v)); fixed = tv(i);
    rows = find(abs(th - fixed) < 1e-9); ang = w(rows);
else % fixed φ great circle: θ on φ0, then 360−θ on φ0+180 (poles excluded on the far side)
    pv = unique(w); [~, i] = min(abs(mod(pv - v + 180, 360) - 180)); fixed = pv(i);
    [~, j] = min(abs(mod(pv - fixed, 360) - 180)); opp = pv(j);
    a = find(abs(w - fixed) < 1e-9); b = find(abs(w - opp) < 1e-9 & th > 1e-9 & th < 180 - 1e-9);
    rows = [a; b]; ang = [th(a); 360 - th(b)];
end
[ang, u] = unique(ang); rows = rows(u);
end

function [bw, lo, hi] = calcHPBW(ang, g)
%CALCHPBW Half-power beamwidth of a circular cut with linear interpolation of the −3 dB crossings.
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(g); ang = ang(ok); g = g(ok);
if numel(g) < 3, return; end
[pk, i] = max(g); half = pk - 3;
[ra, o] = sort(mod(ang - ang(i) + 180, 360) - 180); rg = g(o);
L = find(ra < 0 & rg <= half, 1, 'last'); Rr = find(ra > 0 & rg <= half, 1, 'first');
if isempty(L) || isempty(Rr) || L + 1 > numel(rg) || Rr < 2 || rg(L + 1) == rg(L) || rg(Rr - 1) == rg(Rr), return; end
x = @(i1, i2) ra(i1) + (ra(i2) - ra(i1))*(half - rg(i1))/(rg(i2) - rg(i1));
l = x(L, L + 1); r = x(Rr, Rr - 1); lo = ang(i) + l; hi = ang(i) + r; bw = r - l;
end

function M = calcMetrics(th, ph, g, pk, omega, k, A, ar)
%CALCMETRICS Directivity, efficiency, front-to-back and principal-plane HPBWs from total gain.
g2 = g; if pk.wasAdjusted, g2(pk.outlierMask) = NaN; end
U = sum(10.^(g2/10).*omega, 'omitnan'); eff = 100*U/(4*pi); if eff < 0 || eff > 100, eff = NaN; end
V = dirVec(th, ph); [~, back] = min(V*V(pk.index, :).');
[eT, eV] = planeDef(k, A, true); [hT, hV] = planeDef(k, A, false);
[a, r] = cutRows(th, ph, eT, eV); eH = calcHPBW(a, g(r)); [a, r] = cutRows(th, ph, hT, hV); hH = calcHPBW(a, g(r));
M = struct('PeakGain_dB', pk.value, 'PeakTheta_deg', th(pk.index), 'PeakPhi_deg', ph(pk.index), 'HPBW_EPlane_deg', eH, 'HPBW_HPlane_deg', hH, ...
    'FrontBack_dB', pk.value - g(back), 'PeakDirectivity_dB', 10*log10(max(4*pi*10^(pk.value/10)/max(U, eps), eps)), 'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', ar);
end

function cov = coverageCCDF(g, mask, thr, omega)
%COVERAGECCDF Coverage(T) [%] = 100 · Σ I(G_i > T)·Ω_i / Σ Ω_i over the region (all thresholds at once).
g = double(g(:)); mask = logical(mask(:)); omega = double(omega(:)); thr = double(thr(:));
ok = mask & isfinite(g) & isfinite(omega) & omega >= 0; g = g(ok); omega = omega(ok);
cov = zeros(size(thr)); if isempty(g) || sum(omega) <= 0, return; end
cov = 100*(omega.'*double(g > thr.')).'/sum(omega);
end

%% ---------------------------------------------------------------------- naming helpers
function [cols, labels] = compList(T, L)
avail = string(T.Properties.VariableNames(3:end)); meta = T.Properties.UserData;
if isstruct(meta) && isfield(meta, 'isGainOnly') && meta.isGainOnly, cols = avail; labels = avail; return; end
cols = string(fieldnames(L)).'; cols = cols(ismember(cols, avail)); labels = arrayfun(@(c) string(L.(c)), cols);
end

function c = pickComp(prev, cols)
if any(cols == string(prev)), c = string(prev); elseif any(cols == "E_Total_dB"), c = "E_Total_dB"; else, c = cols(1); end
c = char(c);
end

function tf = isARName(c)
k = regexprep(lower(strtrim(string(c))), '[^a-z0-9]', ''); tf = k == "ar" || startsWith(k, "ardb") || startsWith(k, "axialratio");
end

function s = fmtNum(v, p)
%FMTNUM 'n/a' for non-finite values; compact (≤2 decimals, no trailing zeros) unless a precision is given.
if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return; end
if nargin < 2, s = regexprep(regexprep(sprintf('%.2f', v), '(\.\d*?)0+$', '$1'), '\.$', ''); else, s = sprintf('%.*f', p, v); end
end