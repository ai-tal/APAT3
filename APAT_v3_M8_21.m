classdef APAT_v3_M8_21 < handle %1716-lines %ISSUES: %1. Customized Interactive DataTip NOT-OK ON Contour Plot & Fisheye Plot (shows default X_Y_Z/Theta_R_Z, instead of Customized DataTips) %2. When loading new pattern while the older/current POB DataTip is active/enabled, it shows the old POB and the new one (the old POB DataTip shouldn't show after loading a new pattern)! %3. Coverage Threshold Query snaps to nearest Data Point instead of returning requested/query point! %4. Context menu shows warning: "Warning: You cannot set 'ContextMenu' property of DataTip."
%APAT_V3_M8 Antenna Pattern Analyzer Tool — v3 Milestone 8.
%
%   app = APAT_v3_M8          launch the tool
%   app.loadFile(path)        load a pattern / coverage-results file programmatically
%   app.runSelfTest()         deterministic checks of the numerical layer
%
%   Architecture — one file, three layers, data flows strictly downward:
%     file ──readPattern──▶ src.blocks{k}          canonical E-field or gain table
%          ──normalizePattern──▶ stdTbl            Theta 0..180, Phi 0..360 (seam closed)
%          ──stepSource──▶ ──calcPattern──▶ baseTbl all derived quantities, canonical axes
%          ──applySpan──▶ viewTbl + view.*         display convention + PHYSICAL theta/phi/omega
%          ──analyzeView──▶ peak/boresight/metrics ──▶ tables, cut plots, full-pattern plots
%   All numerics live in pure local functions that receive physical coordinates;
%   the app object never enters the math layer, and the math layer never reads widgets.

    properties (SetAccess = private)
        ui struct = struct()                       % Widget handle registry: app.ui.<name>
        src struct = struct()                      % Reader output: raw, blocks, freqs, meta
        file struct = struct('path', '', 'folder', '', 'base', '', 'name', '')
        stdTbl table                               % Canonical source table of the active block
        baseTbl table                              % Processed canonical table (every output column)
        viewTbl table                              % baseTbl in the selected phi/theta display convention
        view struct = struct('rev', 0, 'grid', struct(), 'elev', false, 'signed', false) % physical coords of viewTbl rows
        pol struct = struct('label', 'n/a', 'pairs', struct('Linear', ["E_TH","E_PH"], 'Circular', ["E_RCP","E_LCP"]))
        peak struct = struct('value', NaN, 'index', 1, 'theta', NaN, 'phi', NaN, 'dispTheta', NaN, 'dispPhi', NaN, 'wasAdjusted', false)
        metrics struct = struct()                  % calcMetrics() of the Total gain on the current view
        boresight double = 1                       % Index into Axes: principal axis holding the most energy
        gainLim double = [-40 10]                  % Full-pattern color scale for gain-like components
        arLim double = [-30 30]                    % Full-pattern color scale for signed axial ratio
        cutLim double = [-40 10]                   % Cut plot magnitude range (independent of the color scale)
        useOneDegree logical = false               % STEP selector: resample non-canonical grids to 1°
        autoBasis logical = true                   % Cut co/cross basis follows the detected polarization until overridden
        defaults struct                            % Startup values of the link parameters
        cov struct                                 % Coverage state: runID, presetKey, syncing, xInit
        perf struct = struct()                     % Timing of the last long operation (app.perf)
        dialog = []                                % Active progress dialog
        statusTimer = []                           % One-shot timer restoring the sticky status after a transient one
        isClosing logical = false
    end

    properties (Constant)
        Axes = struct('labels', {{'+Z','-Z','+X','-X','+Y','-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        Hidden = {'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'}
        PeakPercentile = 99.99                     % Peak policy: an isolated spike above P99.99 + PeakMaxExcessDB is rejected
        PeakMaxExcessDB = 6
        DBRange = [-250 100]                       % Absolute limits of every dB range control
        FileFilter = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage files'; '*.*', 'All files'}
        Version = '3.0-M8'
    end

    %% ------------------------------------------------------------------ public API
    methods
        function app = APAT_v3_M8_21
            app.createComponents();
            app.cov = struct('runID', 0, 'presetKey', '', 'syncing', false, 'xInit', false);
            app.defaults = app.readParams();
            app.setRange("full", app.gainLim, false); app.setRange("cut", app.cutLim, false);
            app.setCoverageUI();
            app.ui.fig.Visible = 'on';
        end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true; app.stopTimer(); app.closeDialog();
            if isfield(app.ui, 'fig') && isgraphics(app.ui.fig), delete(app.ui.fig); end
        end

        function loadFile(app, fp)
            %LOADFILE Load a pattern (Main tab) or a coverage-results file (Coverage tab).
            guard = app.busy('Loading Data', 'Reading file...', true); %#ok<NASGU>
            t0 = tic; out = app.readSource(fp, 'main'); app.checkCancelled();
            if out.meta.isCoverage                                   % coverage results never replace the Main state
                app.ui.tabs.SelectedTab = app.ui.covTab; app.ui.covPath.Value = fp; app.covLoadResults(fp, out.raw); return
            end
            [folder, base, ext] = fileparts(fp);
            app.file = struct('path', fp, 'folder', folder, 'base', base, 'name', [base ext]); app.ui.path.Value = fp;
            app.src = out; isDep = out.meta.isDep;
            if isDep                                                 % one selector entry per frequency block
                items = compose('Pattern %d: %.4g GHz', (1:numel(out.blocks)).', out.freqs(:)/1e9);
                items(isnan(out.freqs)) = compose('Pattern %d', find(isnan(out.freqs(:))));
                [app.ui.ffd.Items, app.ui.ffd.Value] = deal(items, items{1});
            end
            set([app.ui.ffd app.ui.ffdLabel], 'Visible', isDep);
            app.autoBasis = true; app.useOneDegree = false;
            app.selectBlock(1); app.process(true); app.perfLog("Load pattern", t0);
        end

        function process(app, resetCut)
            %PROCESS Recompute everything below stdTbl (parameters, step, span) and redraw all views.
            if nargin < 2, resetCut = true; end
            t0 = tic; source = app.stepSource();
            [app.baseTbl, app.pol] = calcPattern(source, app.readParams(), app.PeakPercentile, app.PeakMaxExcessDB);
            app.checkCancelled();
            if app.autoBasis && ~app.src.meta.isGainOnly
                if startsWith(app.pol.label, 'Linear'), app.ui.basis.Value = 'Linear'; else, app.ui.basis.Value = 'Circular'; end
            end
            app.applySpan(); app.updateComponentItems(); app.analyzeView(true);
            if resetCut, app.onPlaneChanged(); else, app.cutValues(); app.plotCut(); end
            app.renderFull(); app.showLoadedUI(); app.perfLog("Process pattern", t0);
        end
    end

    %% ------------------------------------------------------------------ pipeline
    methods (Access = private)
        function out = readSource(app, fp, side)
            % Generic CSV/TXT/DAT files expose a format selector (main/cov); other formats are self-describing.
            label = app.ui.([side 'FmtLabel']); dd = app.ui.([side 'Fmt']);
            if isGenericText(fp)
                out = readPattern(fp, "gain"); show = ~out.meta.isCoverage;
                if show, dd.Value = 'gain'; end
            else
                out = readPattern(fp, dd.Value); show = false;
            end
            set([label dd], 'Visible', show);
        end

        function selectBlock(app, k)
            block = app.src.blocks{k};
            app.stdTbl = normalizePattern(block); app.stdTbl.Properties.UserData = app.src.meta;
            raw = app.src.raw; if app.src.meta.isDep, raw = block; end
            [app.ui.tableIn.Data, app.ui.tableIn.ColumnName] = deal(raw, raw.Properties.VariableNames);
        end

        function source = stepSource(app)
            % Canonical table at the selected step; keeps the STEP selector consistent with the native grid.
            S = app.stdTbl; ts = gridStep(S.Theta); ps = gridStep(S.Phi);
            if ~isfinite(ts), ts = 1; end, if ~isfinite(ps), ps = ts; end
            canonical = abs(ts - 1) < 1e-9 && abs(ps - 1) < 1e-9;
            app.useOneDegree = app.useOneDegree && ~canonical;
            items = {sprintf('STEP: %g°', max(ts, ps)), 'STEP: 1°'};
            set(app.ui.step, 'Items', items, 'Value', items{1 + app.useOneDegree}, 'Visible', ~canonical, 'Enable', ~canonical);
            source = S;
            if app.useOneDegree
                if ts < 1 && ps < 1                                  % finer than 1°: decimate on integer degrees
                    source = S(abs(S.Theta - round(S.Theta)) < 1e-9 & abs(S.Phi - round(S.Phi)) < 1e-9, :);
                else                                                 % coarser/irregular: interpolate primitives
                    source = resampleCanonical(S, 1);
                end
                source.Properties.UserData = S.Properties.UserData;
            end
        end

        function applySpan(app)
            % Materialize the display convention from baseTbl and cache the physical coordinates of every row.
            T = app.baseTbl; signed = app.signedPhi(); elev = app.elevation(); seam = 360;
            if signed                                                % close the circle at -180° instead of 360°
                T(abs(T.Phi - 360) < 1e-9, :) = [];
                T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
                dup = T(abs(T.Phi - 180) < 1e-9, :); dup.Phi(:) = -180; T = [dup; T]; seam = -180;
            end
            theta = T.Theta;
            if elev, T.Theta = 90 - T.Theta; end
            if signed || elev, [T, order] = sortrows(T, {'Phi','Theta'}); theta = theta(order); end
            T.Properties.UserData = app.src.meta; app.viewTbl = T;
            app.view = struct('theta', theta, 'phi', mod(T.Phi, 360), 'omega', solidWeights(theta, T.Phi, seam), ...
                'seam', seam, 'signed', signed, 'elev', elev, 'rev', app.view.rev + 1, 'grid', struct());
        end

        function analyzeView(app, autoRange)
            % Peak of the selected component (POB), boresight axis, Total-gain metrics, ranges, tables.
            T = app.viewTbl; v = app.view; c = app.comp();
            app.peak = app.locatePeak(T.(c));
            total = chooseGain(T, 'E_Total_dB'); tpeak = resolvePeak(total, app.PeakPercentile, app.PeakMaxExcessDB);
            if isARName(c), og = total; opk = tpeak; else, og = T.(c); opk = app.peak; end   % AR is not an energy quantity
            app.boresight = calcOrientation(og, v.theta, v.phi, v.omega, app.Axes, opk);
            app.metrics = calcMetrics(T, total, v.theta, v.phi, v.omega, tpeak, app.Axes, app.boresight);
            if autoRange                                             % data changed: re-derive both dB windows
                app.gainLim = autoRange50(total, app.PeakPercentile, app.PeakMaxExcessDB); app.cutLim = app.gainLim;
            end
            app.setRange("full", app.fullLim(), false); app.setRange("cut", app.cutLim, false);
            app.updateTables(); app.updateMetadata();
        end

        function pk = locatePeak(app, values)
            pk = resolvePeak(values, app.PeakPercentile, app.PeakMaxExcessDB); k = pk.index;
            [pk.theta, pk.phi] = deal(app.view.theta(k), app.view.phi(k));
            [pk.dispTheta, pk.dispPhi] = deal(app.viewTbl.Theta(k), app.viewTbl.Phi(k));
        end

        function p = readParams(app)
            u = app.ui;
            p = struct('GainLoss_dB', u.loss.Value, 'RxMode', string(u.rxPol.Value), 'RxAR_dB', u.rw.Value, 'Power', u.pt.Value, ...
                'PowerUnit', string(u.ptUnit.Value), 'Distance', u.dist.Value, 'DistanceUnit', string(u.distUnit.Value));
            p.FieldScale = 10^(p.GainLoss_dB/20);
            switch p.PowerUnit
                case "dBm",   p.Pt_dBW = p.Power - 30;
                case "Watts", p.Pt_dBW = 10*log10(max(p.Power, eps));
                otherwise,    p.Pt_dBW = p.Power;
            end
            p.R_m = max(p.Distance, 1e-12) * (1 + 999*(p.DistanceUnit == "km"));
        end

        %% ---- view helpers
        function c = comp(app), c = app.ui.component.Value; end
        function tf = signedPhi(app), tf = strcmp(app.ui.phiSpan.Value, '-180° to 180°'); end
        function tf = elevation(app), tf = strcmp(app.ui.thetaSpan.Value, '-90° to 90°'); end
        function s = thetaName(app), if app.elevation(), s = "Elevation"; else, s = "Theta"; end, end
        function lim = fullLim(app), if isARName(app.comp()), lim = app.arLim; else, lim = app.gainLim; end, end

        function s = compLabel(app)
            dd = app.ui.component; k = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(k), s = string(dd.Value); else, s = string(dd.Items{k}); end
        end

        function [theta, phi, G] = gridOf(app, column)
            % COLUMN as an [nTheta x nPhi] matrix on the display axes; topology and geometry cached per view.
            g = app.view.grid;
            if ~isfield(g, 'theta')
                T = app.viewTbl; theta = unique(T.Theta); phi = unique(T.Phi);
                [~, it] = ismember(T.Theta, theta); [~, ip] = ismember(T.Phi, phi);
                [PG, TG] = meshgrid(phi, theta); TP = TG; if app.view.elev, TP = 90 - TG; end
                g = struct('theta', theta, 'phi', phi, 'idx', sub2ind([numel(theta) numel(phi)], it, ip), 'data', struct(), ...
                    'geom', struct('phiGrid', PG, 'thetaGrid', TG, 'thetaPolar', TP, 'x', sind(TP).*cosd(PG), 'y', sind(TP).*sind(PG), 'z', cosd(TP)));
            end
            theta = g.theta; phi = g.phi; key = matlab.lang.makeValidName(column);
            if ~isfield(g.data, key), G = nan(numel(theta), numel(phi)); G(g.idx) = app.viewTbl.(column); g.data.(key) = G; end
            G = g.data.(key); app.view.grid = g;
        end

        function geom = geometry(app)
            if ~isfield(app.view.grid, 'geom'), app.gridOf(app.comp()); end
            geom = app.view.grid.geom;
        end

        %% ---- lifecycle / status
        function f = cb(app, fn)
            % Wrap a callback so errors surface in a dialog instead of the console.
            f = @(src, evt) app.guarded(fn, src, evt);
        end

        function guarded(app, fn, src, evt)
            try
                fn(src, evt);
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.status('main', 'Operation cancelled by user.', true); return; end
                if app.isClosing || ~isgraphics(app.ui.fig), return; end
                where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
                uialert(app.ui.fig, [ME.message where], 'APAT Error', 'Icon', 'error');
            end
        end

        function status(app, bar, message, transient)
            % BAR is 'main' or 'cov'. Transient messages restore the previous sticky text after 3 s.
            if app.isClosing, return; end
            label = app.ui.([bar 'Status']); app.stopTimer(); label.Text = char(message);
            if nargin >= 4 && transient
                app.statusTimer = timer('StartDelay', 3, 'TimerFcn', @(~,~) app.restoreStatus(label), 'StopFcn', @(t,~) delete(t));
                start(app.statusTimer);
            else
                label.UserData = char(message);
            end
        end

        function restoreStatus(app, label)
            if ~app.isClosing && isgraphics(label) && ischar(label.UserData), label.Text = label.UserData; end
        end

        function stopTimer(app)
            t = app.statusTimer; app.statusTimer = [];
            if ~isempty(t) && isvalid(t), stop(t); end
            if ~isempty(t) && isvalid(t), delete(t); end
        end

        function guard = busy(app, title, message, cancelable)
            app.dialog = uiprogressdlg(app.ui.fig, 'Title', title, 'Message', message, 'Indeterminate', 'on', 'Cancelable', cancelable, 'CancelText', 'Abort');
            drawnow; guard = onCleanup(@() app.closeDialog());
        end

        function closeDialog(app)
            if ~isempty(app.dialog) && isvalid(app.dialog), close(app.dialog); end
            app.dialog = [];
        end

        function checkCancelled(app)
            if ~isempty(app.dialog) && isvalid(app.dialog) && app.dialog.CancelRequested, error('APAT:Cancelled', 'Operation cancelled by user.'); end
        end

        function perfLog(app, operation, t0)
            app.perf = struct('operation', string(operation), 'seconds', toc(t0), 'when', datetime('now'));
        end

        %% ---- Main-tab callbacks
        function onLoad(app, ~, ~)
            fp = strtrim(app.ui.path.Value);
            while isempty(fp) || ~isfile(fp) || strcmp(fp, app.file.path)     % typed new path → use it; else browse
                [f, p] = uigetfile(app.FileFilter, 'Select an antenna pattern file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
                if strcmp(fp, app.file.path) && strcmp(uiconfirm(app.ui.fig, sprintf('"%s" is already loaded.', f), 'File Already Loaded', ...
                        'Options', {'Select Another File','Cancel'}, 'CancelOption', 2), 'Cancel'), return; end
            end
            app.loadFile(fp);
        end

        function onProcess(app, ~, ~)
            if isempty(app.stdTbl), uialert(app.ui.fig, 'Load a pattern first.', 'Process', 'Icon', 'warning'); return; end
            guard = app.busy('Processing', 'Re-processing pattern...', false); %#ok<NASGU>
            if isGenericText(app.file.path)                          % reinterpret the text file with the selected format
                out = readPattern(app.file.path, app.ui.mainFmt.Value);
                assert(~out.meta.isCoverage, 'The selected generic format identifies a coverage-results file.');
                app.src = out; app.selectBlock(1);
            end
            app.process(true);
            app.status('main', ['Re-processed <b>' app.file.name '</b> with the current parameters ✅'], true);
        end

        function onFormatChanged(app, ~, ~)
            if strcmp(strtrim(app.ui.path.Value), app.file.path) && isGenericText(app.file.path), app.autoBasis = true; app.onProcess(); end
        end

        function onFFDChanged(app, ~, ~)
            k = find(strcmp(app.ui.ffd.Items, app.ui.ffd.Value), 1); app.autoBasis = true;
            app.selectBlock(k); app.process(true);
            app.status('main', sprintf('Switched to FFD block %d (%s).', k, app.ui.ffd.Value), true);
        end

        function onStepChanged(app, ~, ~)
            app.useOneDegree = strcmp(app.ui.step.Value, 'STEP: 1°'); app.process(false);
        end

        function onResetParams(app, ~, ~)
            d = app.defaults; u = app.ui;
            [u.loss.Value, u.rxPol.Value, u.rw.Value, u.pt.Value, u.ptUnit.Value, u.dist.Value, u.distUnit.Value] = ...
                deal(d.GainLoss_dB, char(d.RxMode), d.RxAR_dB, d.Power, char(d.PowerUnit), d.Distance, char(d.DistanceUnit));
            if ~isempty(app.stdTbl), app.process(false); end
        end

        function onSpanChanged(app, ~, ~)
            if isempty(app.baseTbl), return; end
            t0 = tic; wasElev = app.view.elev; target = app.ui.cutValue.Value;
            app.applySpan();
            if wasElev ~= app.view.elev && strcmp(app.ui.cutType.Value, 'Phi'), target = 90 - target; end   % same physical cut
            app.analyzeView(false); app.cutValues(target); app.plotCut(); app.renderFull(); app.perfLog("Change angular span", t0);
        end

        function onComponentChanged(app, ~, ~)
            if isempty(app.viewTbl), return; end
            app.analyzeView(false); app.plotCut(); app.renderFull();
        end

        function onPlaneChanged(app, ~, ~)
            % E-plane: theta cut through the boresight meridian. H-plane: the orthogonal plane.
            A = app.Axes; k = app.boresight; type = 'Theta'; val = A.phi(k);
            if ~startsWith(app.ui.ehSwitch.Value, 'E')
                if A.theta(k) == 90, type = 'Phi'; val = 90 - 90*app.elevation(); else, val = 90; end
            end
            app.ui.cutType.Value = type; app.cutValues(val); app.onCutChanged();
        end

        function onCutChanged(app, src, ~)
            if nargin > 1 && isequal(src, app.ui.cutType), app.cutValues(); end
            if nargin > 1 && isequal(src, app.ui.basis), app.autoBasis = false; app.updateMetadata(); end
            show = app.ui.hpbwBtn.Value; app.ui.hpbwBox.Visible = show; if ~show, app.ui.hpbwBox.Value = false; end
            app.plotCut(); app.refreshOverlay();
        end

        function onView3DChanged(app, ~, ~)
            for ax = [app.ui.sphAx app.ui.polAx app.ui.rect3Ax], app.applyView3D(ax); end
            drawnow limitrate
        end

        function onColorbarSpinner(app, ~, ~)
            app.setRange("full", [app.ui.cmin.Value app.ui.cmax.Value], true);
        end

        function onRange(app, scope, part, src)
            % Slider (part 0) or min/max spinner (1/2) of the full-pattern or cut range group.
            if scope == "full", lim = app.fullLim(); else, lim = app.cutLim; end
            if part == 0, lim = src.Value; else, lim(part) = src.Value; end
            app.setRange(scope, lim, true);
        end

        function onFilter(app, ~, ~)
            dd = app.ui.outFilter;
            if dd.Value > 0, dd.UserData(dd.Value) = ~dd.UserData(dd.Value); dd.Value = 0; end
            app.filterOutput(true);
        end

        %% ---- dB ranges
        function setRange(app, scope, lim, apply)
            % Single writer for a range group ("full" = 5 color-scale slider/spinner sets, "cut" = cut plots).
            lim = clampRange(lim, app.DBRange); u = app.ui;
            if scope == "full"
                if isARName(app.comp()), app.arLim = lim; else, app.gainLim = lim; end
                sliders = u.fullSlider; lo = u.fullMin; hi = u.fullMax; [u.cmin.Value, u.cmax.Value] = deal(lim(1), lim(2));
            else
                app.cutLim = lim; sliders = u.cutSlider; lo = u.cutMin; hi = u.cutMax;
            end
            set(sliders, 'Limits', app.DBRange, 'Value', lim); set(sliders, 'Limits', clampRange(lim + [-20 20], app.DBRange)); % travel = range ± 20 dB
            app.setPair(lo, hi, lim, 1);
            if ~apply || isempty(app.viewTbl), return; end
            if scope == "full", app.applyFullRange(lim); else, set(u.cutPolar, 'RLim', lim); set(u.cutRect, 'YLim', lim); end
        end

        function setPair(app, lo, hi, b, gap)
            % Coupled min/max spinners: each one's limit is the other's value.
            set([lo hi], 'Limits', app.DBRange); set(lo, 'Value', b(1)); set(hi, 'Value', b(2));
            set(lo, 'Limits', [app.DBRange(1) b(2) - gap]); set(hi, 'Limits', [b(1) + gap app.DBRange(2)]);
        end

        function applyFullRange(app, lim)
            if isempty(app.viewTbl), return; end
            for k = 1:numel(app.ui.full)
                ax = app.ui.full(k).ax; clim(ax, lim); app.setTicks(colorbar(ax), 'Ticks', lim);
                if k == 5, zlim(ax, lim); app.setTicks(ax, 'ZTick', lim); end
            end
            drawnow limitrate
        end

        function setTicks(app, h, prop, lim)
            t = ticksFor(lim, app.ui.cstep.Value); if ~isempty(t), h.(prop) = t; end
        end

        %% ---- full-pattern renderers
        function renderFull(app)
            if isempty(app.viewTbl), return; end
            app.drawContour(); app.checkCancelled(); app.drawFisheye(); app.draw3D(false); app.draw3D(true); app.drawRect3();
            drawnow limitrate
        end

        function theme(app, ax)
            % Color scale of the selected component: jet for gain, blue-white-red centred at 0 for signed AR.
            persistent jetMap arMap
            if isempty(jetMap), jetMap = jet(256); arMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
            if isARName(app.comp()), map = arMap; else, map = jetMap; end
            clim(ax, app.fullLim()); colormap(ax, map); app.setTicks(colorbar(ax), 'Ticks', app.fullLim());
            set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', ax.UserData.menu);   % rebind to the new children
        end

        function tipTemplate(app, s, g, G)
            rows = [dataTipTextRow(app.thetaName(), g.thetaGrid, '%.3g°'); dataTipTextRow("Phi", g.phiGrid, '%.3g°'); ...
                dataTipTextRow(replace(app.compLabel(), "_", "\_"), G, '%.3g dB')];
            try, s.DataTipTemplate.DataTipRows = rows; catch, end
        end

        function markPOB(app, ax, x, y, z)
            % Peak-of-beam marker + datatip; tagged so the "Annotate POB" checkbox can toggle it.
            pk = app.peak; if ~isfinite(pk.value), return; end
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), m = polarplot(ax, x, y, 'ko'); else, m = plot3(ax, x, y, z, 'ko', 'Clipping', 'off'); end
            set(m, 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off', 'Tag', 'APAT_POB');
            m.DataTipTemplate.DataTipRows = [dataTipTextRow(app.thetaName(), pk.dispTheta, '%.3g°'); dataTipTextRow("Phi", pk.dispPhi, '%.3g°'); ...
                dataTipTextRow(replace(app.compLabel(), "_", "\_"), pk.value, '%.3g dB')];
            t = datatip(m, 'DataIndex', 1, 'FontSize', 9, 'Tag', 'APAT_POB');
            if isequal(ax, app.ui.ctrAx) && any(abs(y - ax.YLim) < 1e-9), t.Location = 'southeast'; end   % keep the tip inside at the theta edges
            set([m t], 'Visible', app.ui.pobBox.Value);
        end

        function angularAxes(app, ax, dp, dt)
            pl = [0 360] - 180*app.view.signed; tl = [0 180] - 90*app.view.elev;
            set(ax, 'XLim', pl, 'YLim', tl, 'XTick', pl(1):dp:pl(2), 'YTick', tl(1):dt:tl(2), 'Box', 'on', 'Layer', 'top');
            if app.view.elev, ax.YDir = 'normal'; else, ax.YDir = 'reverse'; end
        end

        function polarTicks(app, pax)
            % Physical polar geometry with labels in the selected phi convention.
            a = 0:30:330; if app.view.signed, a(a > 180) = a(a > 180) - 360; end
            set(pax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', a));
        end

        function drawContour(app)
            ax = app.ui.ctrAx; [theta, phi, G] = app.gridOf(app.comp()); g = app.geometry(); cla(ax);
            s = pcolor(ax, phi, theta, G); set(s, 'FaceColor', 'interp', 'LineStyle', 'none', 'Tag', 'APAT_Surface');
            app.theme(ax); app.angularAxes(ax, 30, 15); daspect(ax, [1 1 1]);
            xlabel(ax, 'Phi (degree)'); ylabel(ax, app.thetaName() + " (degree)"); title(ax, app.compLabel(), 'Interpreter', 'none');
            app.tipTemplate(s, g, G); app.markPOB(ax, app.peak.dispPhi, app.peak.dispTheta, 0);
        end

        function drawFisheye(app)
            pax = app.ui.cirAx; [~, ~, G] = app.gridOf(app.comp()); g = app.geometry(); cla(pax);
            s = surface(pax, deg2rad(g.phiGrid), g.thetaPolar, zeros(size(G)), G, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.theme(pax); app.polarTicks(pax);
            r = 0:30:180; if app.view.elev, r = 90 - r; end
            set(pax, 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', r));
            title(pax, sprintf('%s  |  r=θ, angle=φ', app.compLabel()), 'Interpreter', 'none', 'FontSize', 9);
            app.tipTemplate(s, g, G); app.markPOB(pax, deg2rad(app.peak.phi), app.peak.theta, 0);
        end

        function draw3D(app, isPolar)
            % Spatial 3-D plots: unit sphere colored by the component, or radius scaled by (value - min)/(max - min).
            if isPolar, ax = app.ui.polAx; else, ax = app.ui.sphAx; end
            [~, ~, G] = app.gridOf(app.comp()); g = app.geometry(); lim = app.fullLim(); cla(ax);
            r = 1; rmax = 1; rp = 1;
            if isPolar
                r0 = max(G - lim(1), 0); rmax = max(r0(:), [], 'omitnan'); if ~(rmax > 0), rmax = 1; end
                r = r0/rmax; rp = max(app.peak.value - lim(1), 0)/rmax;
            end
            ax.UserData.rmax = rmax;
            s = surf(ax, r.*g.x, r.*g.y, r.*g.z, G, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.theme(ax); app.drawXYZ(ax);
            set(ax, 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'Projection', 'orthographic'); axis(ax, 'off');
            app.applyView3D(ax);
            title(ax, sprintf('%s  |  θ: %s  |  φ: %s', app.compLabel(), app.ui.thetaSpan.Value, app.ui.phiSpan.Value), 'Interpreter', 'none');
            app.tipTemplate(s, g, G);
            [t, p] = deal(app.peak.theta, app.peak.phi);
            app.markPOB(ax, 1.02*rp*sind(t)*cosd(p), 1.02*rp*sind(t)*sind(p), 1.02*rp*cosd(t));
            if app.ui.overlayBox.Value, app.overlayCut(ax, isPolar, lim, rmax); end
        end

        function drawRect3(app)
            ax = app.ui.rect3Ax; [~, ~, G] = app.gridOf(app.comp()); g = app.geometry(); lim = app.fullLim(); cla(ax);
            s = surf(ax, g.phiGrid, g.thetaGrid, G, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.theme(ax); zlim(ax, lim); app.setTicks(ax, 'ZTick', lim); app.angularAxes(ax, 60, 30); grid(ax, 'on');
            xlabel(ax, 'Phi (degree)'); ylabel(ax, app.thetaName() + " (degree)"); zlabel(ax, app.compLabel() + " (dB)", 'Interpreter', 'none');
            app.applyView3D(ax); title(ax, app.compLabel(), 'Interpreter', 'none');
            app.tipTemplate(s, g, G); app.markPOB(ax, app.peak.dispPhi, app.peak.dispTheta, app.peak.value);
        end

        function drawXYZ(~, ax)
            colors = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            for k = 1:3
                d = 1.35*(1:3 == k);
                quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12*d(1), 1.12*d(2), 1.12*d(3), labels{k}, 'Color', colors{k}, 'FontWeight', 'bold');
            end
        end

        function applyView3D(app, ax)
            v = ax.UserData.view; up = [0 0 1];
            switch string(app.ui.view3D.Value)
                case "top",    v = [0 90];  up = [0 1 0];
                case "bottom", v = [0 -90]; up = [0 1 0];
                case "right",  v = [90 0];
                case "left",   v = [-90 0];
                case "front",  v = [0 0];
                case "back",   v = [180 0];
            end
            view(ax, v(1), v(2)); camup(ax, up);
        end

        function overlayCut(app, ax, isPolar, lim, rmax)
            c = app.cutData(); r = 1.02;
            if isPolar, r = 1.01*max(c.data(:, 1) - lim(1), 0)/rmax; end
            plot3(ax, r.*sind(c.theta).*cosd(c.phi), r.*sind(c.theta).*sind(c.phi), r.*cosd(c.theta), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_Overlay');
        end

        function refreshOverlay(app)
            % Add/remove the black cut line on both spatial plots without re-rendering the surfaces.
            if isempty(app.viewTbl), return; end
            for ax = [app.ui.sphAx app.ui.polAx]
                delete(findall(ax, 'Tag', 'APAT_Overlay'));
                if app.ui.overlayBox.Value, app.overlayCut(ax, isequal(ax, app.ui.polAx), app.fullLim(), ax.UserData.rmax); end
            end
        end

        function toggleTag(app, tag, visible)
            set(findall(app.ui.fig, 'Tag', tag), 'Visible', visible);
        end

        %% ---- cuts
        function vals = cutValues(app, target)
            % Domain of the cut-value spinner (display theta for Phi cuts, physical phi for Theta cuts); snap to TARGET.
            s = app.ui.cutValue; if nargin < 2, target = s.Value; end
            if strcmp(app.ui.cutType.Value, 'Phi'), vals = unique(app.viewTbl.Theta); else, vals = unique(app.view.phi); end
            [~, k] = min(abs(vals - target));
            s.Limits = [-Inf Inf]; s.Value = vals(k); s.Limits = [min(vals) max(vals)];
            if numel(vals) > 1, s.Step = min(diff(vals)); end
        end

        function [cols, idx] = cutCols(app)
            % Selected cut traces: Total plus the co/cross pair of the chosen basis (gain-only: the selected column).
            if app.src.meta.isGainOnly, cols = string(app.comp()); idx = 1; return; end
            if strcmp(app.ui.basis.Value, 'Linear'), pair = ["E_TH","E_PH"]; else, pair = ["E_RCP","E_LCP"]; end
            [app.ui.boxEr.Text, app.ui.boxEl.Text] = deal(char(pair(1)), char(pair(2)));
            sel = [app.ui.boxEt.Value app.ui.boxEr.Value app.ui.boxEl.Value]; if ~any(sel), sel(1) = true; end
            idx = find(sel); names = ["E_Total" pair] + "_dB"; cols = names(idx);
        end

        function c = cutData(app)
            % One closed great-circle cut of the selected columns in the active display convention.
            T = app.viewTbl; v = app.view; [cols, idx] = app.cutCols(); isPhiCut = strcmp(app.ui.cutType.Value, 'Phi');
            [ang, rows, fixed] = circleCut(v.theta, v.phi, isPhiCut, app.ui.cutValue.Value, T.Theta);
            lo = -180*v.signed; [ang, k] = unique(mod(ang - lo, 360) + lo); rows = rows(k);
            ang(end+1) = lo + 360; rows(end+1) = rows(1);                                    % close the circle
            if isPhiCut, sym = 'θ'; name = "Phi"; else, sym = 'φ'; name = "Theta"; end
            c = struct('angle', ang, 'data', T{rows, cellstr(cols)}, 'theta', v.theta(rows), 'phi', v.phi(rows), 'cols', cols, 'idx', idx, ...
                'angleName', name, 'title', sprintf('%s cut @ %s = %g°', name, sym, fixed));
            if app.src.meta.isGainOnly, c.title = char(app.compLabel()); end
            if abs(fixed - app.ui.cutValue.Value) > 1e-9
                app.status('main', sprintf('Requested %s cut @ %s=%g° snapped to nearest %s=%g°', name, sym, app.ui.cutValue.Value, sym, fixed), true);
            end
        end

        function plotCut(app)
            if isempty(app.viewTbl), return; end
            c = app.cutData(); pax = app.ui.cutPolar; rax = app.ui.cutRect; lim = app.cutLim; cla(pax); cla(rax);
            pl = polarplot(pax, deg2rad(c.angle), max(c.data, lim(1)), 'LineWidth', 1.4);   % clamp: no reflection below RLim
            rl = plot(rax, c.angle, c.data, 'LineWidth', 1.4);
            colors = rax.ColorOrder(1 + mod(c.idx - 1, size(rax.ColorOrder, 1)), :);        % stable color per trace kind
            for k = 1:numel(pl)
                rows = [dataTipTextRow("Angle", c.angle, '%.3g°'); dataTipTextRow("Magnitude", c.data(:, k), '%.3g dB')];
                set([pl(k) rl(k)], 'Color', colors(k, :)); pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            xl = [0 360] - 180*app.view.signed;
            set(pax, 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.polarTicks(pax);
            set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, c.angleName + " (degree)"); title(pax, c.title, 'Interpreter', 'none'); title(rax, c.title, 'Interpreter', 'none');
            names = cellstr(replace(c.cols, "_", "\_"));
            legend(pax, pl, names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rl, names, 'Location', 'best');
            % Peak of the displayed cut (first trace) and its half-power beamwidth.
            [pk, ki] = max(c.data(:, 1), [], 'omitnan'); app.ui.hpbwLabel.Text = '';
            if ~isfinite(pk), return; end
            app.cutMarker(c.angle(ki), pk, "Angle", 'APAT_POB', 'k', app.ui.pobBox.Value);
            if ~app.ui.hpbwBtn.Value, return; end
            [bw, a1, a2] = calcHPBW(c.angle, c.data(:, 1), pk, c.angle(ki)); if ~isfinite(bw), return; end
            b = mod([a1 a2] - xl(1), 360) + xl(1);
            app.ui.hpbwLabel.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
            if b(1) <= b(2), reg = b; else, reg = [xl(1) b(2); b(1) xl(2)]; end                 % wrap-aware shading
            thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
            xregion(rax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
            app.cutMarker(b(1), pk - 3, "Lower HPBW", 'APAT_HPBW', '#D95319', app.ui.hpbwBox.Value);
            app.cutMarker(b(2), pk - 3, "Upper HPBW", 'APAT_HPBW', '#D95319', app.ui.hpbwBox.Value);
        end

        function cutMarker(app, ang, val, label, tag, color, visible)
            % Marker + datatip on both cut axes, discoverable by TAG for the annotation checkboxes.
            m = [polarplot(app.ui.cutPolar, deg2rad(ang), val, 'o'), plot(app.ui.cutRect, ang, val, 'o')];
            set(m, 'Color', color, 'MarkerFaceColor', color, 'MarkerSize', 5, 'HandleVisibility', 'off', 'Tag', tag);
            for h = m
                h.DataTipTemplate.DataTipRows = [dataTipTextRow(label, ang, '%.2f°'); dataTipTextRow("Magnitude", val, '%.2f dB')];
                t = datatip(h, 'DataIndex', 1, 'FontSize', 9, 'Tag', tag); t.Visible = visible;
            end
            set(m, 'Visible', visible);
        end

        %% ---- tables, metadata, visibility
        function updateComponentItems(app)
            [cols, labels] = componentMap(app.viewTbl); dd = app.ui.component; prev = string(dd.Value);
            [dd.Items, dd.ItemsData] = deal(cellstr(labels), cellstr(cols)); dd.Value = char(preferredComponent(prev, cols));
        end

        function updateTables(app)
            % Results table + column filter; the filter mask lives in the dropdown's UserData.
            dd = app.ui.outFilter; cols = app.viewTbl.Properties.VariableNames(3:end);
            if isequal(regexprep(dd.Items(2:end), '^✓ ', ''), cols), app.filterOutput(false); return; end
            [dd.Items, dd.ItemsData, dd.UserData, dd.Value] = deal([{'--- column filter ---'}, cols], 0:numel(cols), ~ismember(cols, app.Hidden), 0);
            app.filterOutput(true);
        end

        function filterOutput(app, restyle)
            dd = app.ui.outFilter; on = dd.UserData;
            if restyle
                dd.Items = regexprep(dd.Items, '^✓ ', ''); removeStyle(dd);
                k = find(on) + 1; dd.Items(k) = append('✓ ', dd.Items(k));
                addStyle(dd, app.ui.styleOn, 'Item', k); addStyle(dd, app.ui.styleOff, 'Item', find([true, ~on]));
            end
            app.ui.tableOut.Data = app.viewTbl(:, [true true on]);
            app.updateInputVisibility();
        end

        function updateInputVisibility(app)
            % Show only the link parameters that influence a currently displayed result column.
            u = app.ui; cols = string(app.viewTbl.Properties.VariableNames(3:end)); sel = cols(u.outFilter.UserData);
            has = @(names) any(ismember(sel, names));
            set([u.rxLabel u.rxPol u.rwLabel u.rw], 'Visible', has(["PLF_dB","Gain_PolCorrected_dB"]));
            set([u.ptLabel u.pt u.ptUnit], 'Visible', has(["EIRP_dBW","PFD_Wm2","E_RMS_Vm"]));
            set([u.distLabel u.dist u.distUnit], 'Visible', has(["PFD_Wm2","E_RMS_Vm"]));
            set([u.lossLabel u.loss], 'Visible', app.src.meta.isGainOnly || has(["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","Gain_PolCorrected_dB","EIRP_dBW","PFD_Wm2","E_RMS_Vm"]));
        end

        function updateMetadata(app)
            T = app.viewTbl; m = app.metrics; th = unique(T.Theta); ph = unique(T.Phi); f = @fmtNum;
            rows = {'Source format', app.src.meta.source; 'File', app.file.name; ...
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(T), numel(th), numel(ph)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', f(min(th)), f(max(th)), f(gridStep(th))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', f(min(ph)), f(max(ph)), f(gridStep(ph)))};
            fq = app.src.freqs(isfinite(app.src.freqs));
            if ~isempty(fq), rows(end+1, :) = {'Frequencies', strjoin(compose('%.4g GHz', fq(:)/1e9), ', ')}; end
            if ~app.src.meta.isGainOnly
                rows(end+1, :) = {'Polarization', app.pol.label};
                rows(end+1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(app.pol.pairs.(app.ui.basis.Value), ' / '))};
            end
            rows = [rows; {'Peak gain (POB)', [f(m.PeakGain_dB) ' dB']; 'POB direction [θ, φ]', sprintf('[%s°, %s°]', f(m.PeakTheta_deg), f(m.PeakPhi_deg)); ...
                'Boresight axis', app.Axes.labels{app.boresight}; 'Peak policy', sprintf('P%.4g, max excess %.4g dB', app.PeakPercentile, app.PeakMaxExcessDB); ...
                'Peak adjusted', char(string(app.peak.wasAdjusted)); 'HPBW E-plane', [f(m.HPBW_EPlane_deg) '°']; 'HPBW H-plane', [f(m.HPBW_HPlane_deg) '°']; ...
                'Front-to-back', [f(m.FrontBack_dB) ' dB']; 'Peak directivity', [f(m.PeakDirectivity_dB) ' dB']}];
            if isfinite(m.Efficiency_pct), rows(end+1, :) = {'Radiation efficiency', [f(m.Efficiency_pct) '%']}; end
            if isfinite(m.AxialRatioAtPeak_dB), rows(end+1, :) = {'AR at peak', [f(m.AxialRatioAtPeak_dB) ' dB']}; end
            app.ui.tableMeta.Data = rows;
        end

        function showLoadedUI(app)
            u = app.ui; hasE = ~app.src.meta.isGainOnly;
            set([u.cutPanel u.fullPanel u.ctrlPanel u.exportOut u.covBtn u.dataTabs u.outFilter], 'Visible', 'on');
            set([u.exportUAN u.ecutGrid u.boxEt u.boxEr u.boxEl], 'Visible', hasE); set([u.boxEr u.boxEl u.basis], 'Enable', hasE);
            app.updateInputVisibility();
            polText = ''; if hasE, polText = sprintf(' | Polarization <b>%s</b>', app.pol.label); end
            app.status('main', sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>θ=%s°, φ=%s°</b>)%s', app.file.name, ...
                fmtNum(app.peak.value, 2), fmtNum(app.peak.theta), fmtNum(app.peak.phi), polText), false);
        end

        %% ---- exports
        function onExportResults(app, ~, ~)
            if isempty(app.viewTbl), return; end
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, ...
                'Export Results', fullfile(app.file.folder, [app.file.base '_APAT_results.csv']));
            if isequal(f, 0), return; end
            writeTable(app.ui.tableOut.Data, fullfile(p, f));                         % respects the active column filter
            app.status('main', ['Results exported to <b>' fullfile(p, f) '</b>'], true);
        end

        function onExportCut(app, ~, ~)
            if isempty(app.viewTbl), return; end
            c = app.cutData(); cut = array2table([c.angle c.data], 'VariableNames', [{'Angle_deg'}, cellstr(c.cols)]);
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, 'Export Cut', fullfile(app.file.folder, [app.file.base '_cut.csv']));
            if isequal(f, 0), return; end
            writeTable(cut, fullfile(p, f)); app.status('main', ['Cut (' c.title ') exported to <b>' fullfile(p, f) '</b>'], true);
        end

        function onExportUAN(app, ~, ~)
            if app.src.meta.isGainOnly, uialert(app.ui.fig, 'No E-field data to export.', 'Export UAN'); return; end
            T = app.viewTbl;
            U = sortrows(table(app.view.theta, T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta','Phi','E_TH_DB','E_PH_DB','E_TH_DG','E_PH_DG'}), {'Phi','Theta'});
            step = gridStep(U.Theta); if ~isfinite(step), step = 1; end
            gmax = max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan');
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, ...
                'Export UAN / E-field data', fullfile(app.file.folder, sprintf('%s_%.5f_%gdeg.uan', app.file.base, gmax, step)));
            if isequal(f, 0), return; end
            guard = app.busy('Saving Data', 'Writing file...', false); %#ok<NASGU>
            fp = fullfile(p, f);
            if endsWith(fp, '.uan', 'IgnoreCase', true), writeUAN(U, fp); else, writeTable(U, fp); end
            app.status('main', ['UAN exported to <b>' fp '</b>'], true);
        end

        %% ---- coverage: model
        function [T, v] = buildPattern(app, out)
            % Auxiliary pattern for the Coverage tab from reader output (block 1), on canonical axes.
            S = normalizePattern(out.blocks{1}); S.Properties.UserData = out.meta;
            T = calcPattern(S, app.readParams(), app.PeakPercentile, app.PeakMaxExcessDB);
            v = struct('theta', T.Theta, 'phi', T.Phi, 'omega', solidWeights(T.Theta, T.Phi, 360), 'rev', 0);
        end

        function node = covAddPattern(app, name, path, T, v)
            node = uitreenode(app.ui.covRoot, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', 'pattern', 'name', name, 'path', path, 'pattern', T, 'theta', v.theta, 'phi', v.phi, ...
                'omega', v.omega, 'rev', v.rev, 'component', "", 'boresight', 1);
            tree = app.ui.covTree; expand(tree); tree.CheckedNodes = [tree.CheckedNodes; node]; tree.SelectedNodes = node;
            app.covSync(node); app.setCoverageUI(); app.ui.covResults.Visible = 'on';
            app.status('cov', sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name), false);
        end

        function covSyncFromView(app, node)
            % Main-tab patterns are always evaluated on the CURRENT view table (step, span, loss already applied).
            d = node.NodeData; v = app.view;
            [d.pattern, d.theta, d.phi, d.omega, d.rev, d.name] = deal(app.viewTbl, v.theta, v.phi, v.omega, v.rev, app.file.base);
            node.NodeData = d; app.covSync(node);
        end

        function covSync(app, node, comp)
            % Component list, boresight and threshold preset consistent with the target node.
            d = node.NodeData; [cols, labels] = componentMap(d.pattern); dd = app.ui.covComponent;
            if nargin < 3, comp = d.component; if strlength(comp) == 0, comp = string(dd.Value); end, end
            comp = preferredComponent(comp, cols);
            if ~isequal(string(dd.ItemsData), cols), [dd.Items, dd.ItemsData] = deal(cellstr(labels), cellstr(cols)); end
            dd.Value = char(comp);
            if d.component ~= comp
                d.component = comp; gain = d.pattern.(char(comp));
                d.boresight = calcOrientation(gain, d.theta, d.phi, d.omega, app.Axes, resolvePeak(gain, app.PeakPercentile, app.PeakMaxExcessDB));
                node.NodeData = d;
                if app.ui.orientation.Value == 0, app.onCovOrientation(); end       % Auto: seed the cone centre
            end
            key = sprintf('%s|%s|%d', d.path, comp, d.rev);                          % threshold preset only when the target changes
            if ~strcmp(app.cov.presetKey, key)
                b = autoRange50(d.pattern.(char(comp)), app.PeakPercentile, app.PeakMaxExcessDB);
                if ~isempty(app.cov.presetKey), b = [min(b(1), app.ui.thrMin.Value) max(b(2), app.ui.thrMax.Value)]; end   % only widen
                app.setPair(app.ui.thrMin, app.ui.thrMax, b, 0.1); app.cov.presetKey = key;
            end
        end

        function node = covPatternTarget(app)
            % Pattern node to operate on: the selection's pattern ancestor, else the most recently added pattern.
            node = []; sel = app.ui.covTree.SelectedNodes; if ~isempty(sel), n = sel(1); else, n = []; end
            while isa(n, 'matlab.ui.container.TreeNode')
                if isstruct(n.NodeData) && strcmp(n.NodeData.kind, 'pattern'), node = n; return; end
                n = n.Parent;
            end
            kids = app.ui.covRoot.Children;
            for k = numel(kids):-1:1, if strcmp(kids(k).NodeData.kind, 'pattern'), node = kids(k); return; end, end
        end

        function node = covFind(app, fp)
            node = []; kids = app.ui.covRoot.Children;
            for k = 1:numel(kids), if strcmp(kids(k).NodeData.path, fp), node = kids(k); return; end, end
        end

        function jobs = covJobs(app, roots)
            % Job nodes (sorted by run id) under ROOTS (default: all).
            if nargin < 2, roots = app.ui.covRoot; end
            nodes = roots(:); frontier = nodes;
            for depth = 1:2                                                             % pattern/results → jobs
                if isempty(frontier), break; end
                frontier = vertcat(frontier.Children); nodes = [nodes; frontier(:)]; %#ok<AGROW>
            end
            jobs = nodes(arrayfun(@(n) isstruct(n.NodeData) && strcmp(n.NodeData.kind, 'job'), nodes));
            [~, order] = sort(arrayfun(@(n) n.NodeData.id, jobs)); jobs = jobs(order);
        end

        function on = covChecked(app, jobs)
            % Logical mask of JOBS that are checked in the tree (handle identity, safe for empty selections).
            checked = app.ui.covTree.CheckedNodes; on = false(size(jobs));
            for k = 1:numel(jobs), on(k) = ~isempty(checked) && any(jobs(k) == checked); end
        end

        function thr = covThresholds(app)
            % Thresholds exactly as entered (the preset never overrides user edits at compute time).
            lo = app.ui.thrMin.Value; hi = app.ui.thrMax.Value; step = max(app.ui.thrStep.Value, 0.01);
            if hi <= lo, hi = min(100, lo + step); app.ui.thrMax.Value = hi; end
            thr = (lo:step:hi).'; if isempty(thr) || thr(end) < hi, thr(end+1, 1) = hi; end
        end

        function node = covAddJob(app, parent, thr, cov, label, comp, tableTag, conical, orient)
            app.cov.runID = app.cov.runID + 1; id = app.cov.runID;
            icon = '📉'; if strcmp(parent.NodeData.kind, 'results'), icon = '📈'; end
            text = sprintf('%s R%d %s · %s', icon, id, label, comp);
            line = plot(app.ui.covAx, thr, cov, 'LineWidth', 1.6, 'DisplayName', text);
            [icov, ii] = unique(cov(:), 'last');                                       % monotone samples for coverage → threshold
            node = uitreenode(parent, 'Text', text);
            node.NodeData = struct('kind', 'job', 'id', id, 'thr', thr(:), 'cov', cov(:), 'invCov', icov, 'invThr', thr(ii), 'line', line, ...
                'label', text, 'tableTag', tableTag, 'isConical', conical, 'orient', orient, 'step', gridStep(thr));
            expand(parent); app.ui.covTree.CheckedNodes = [app.ui.covTree.CheckedNodes; node];
            app.covFinalize();
        end

        function covFinalize(app)
            % Results table on the union of checked thresholds (linear interpolation per curve), legend, UI state.
            jobs = app.covJobs(); checked = jobs(app.covChecked(jobs)); n = numel(checked);
            thr = app.covThresholds();
            if n > 0, c = arrayfun(@(j) j.NodeData.thr, checked, 'UniformOutput', false); thr = unique(vertcat(c{:})); end
            vals = nan(numel(thr), n + 1); vals(:, 1) = thr; names = [{'Threshold (dB)'}, cell(1, n)]; lines = gobjects(1, n); labels = cell(1, n);
            for k = 1:n
                d = checked(k).NodeData; vals(:, k+1) = interp1(d.thr, d.cov, thr, 'linear', NaN);
                names{k+1} = sprintf('R%d %s %%', d.id, d.tableTag); lines(k) = d.line; labels{k} = d.label;
            end
            app.ui.covTable.Data = array2table(compose('%.2f', vals), 'VariableNames', names);
            if n > 0, legend(app.ui.covAx, lines, labels, 'Location', 'southwest', 'Interpreter', 'none'); else, legend(app.ui.covAx, 'off'); end
            app.setCoverageUI();
        end

        function covLoadResults(app, fp, T)
            [~, name] = fileparts(fp); node = uitreenode(app.ui.covRoot, 'Text', ['📄 ' name]);
            node.NodeData = struct('kind', 'results', 'name', name, 'path', fp);
            app.ui.covTree.CheckedNodes = [app.ui.covTree.CheckedNodes; node];
            thr = T{:, 1}; app.covXRange([min(thr) max(thr)], true);
            step = gridStep(thr); if isfinite(step) && step < app.ui.thrStep.Value, app.ui.thrStep.Value = step; end
            for k = 2:width(T), app.covAddJob(node, thr, T{:, k}, 'Res', T.Properties.VariableNames{k}, 'Res', false, "n/a"); end
            expand(node); app.ui.covResults.Visible = 'on';
            app.status('cov', sprintf('Coverage results file "%s" loaded (%d curves).', name, width(T) - 1), false);
        end

        function [x, y] = covQueryPoint(~, d, mode, q)
            if mode == "cov", x = q; y = interp1(d.thr, d.cov, q, 'linear', NaN); else, y = q; x = interp1(d.invCov, d.invThr, q, 'linear', NaN); end
        end

        function label = coneLabel(app, theta, phi)
            % Principal-axis name when the cone centre coincides with ±X/±Y/±Z, otherwise the explicit angles.
            A = app.Axes; c = [sind(theta)*cosd(phi), sind(theta)*sind(phi), cosd(theta)];
            k = find([sind(A.theta(:)).*cosd(A.phi(:)), sind(A.theta(:)).*sind(A.phi(:)), cosd(A.theta(:))] * c(:) >= 1 - 1e-9, 1);
            if isempty(k), label = sprintf('θ=%s°, φ=%s°', fmtNum(theta), fmtNum(phi)); else, label = A.labels{k}; end
        end

        %% ---- coverage: UI state
        function setCoverageUI(app)
            u = app.ui; hasPattern = ~isempty(app.covPatternTarget()); hasJobs = ~isempty(app.covJobs());
            set(u.covParams.Children, 'Visible', hasPattern);
            set([u.covPathLabel u.covPath u.covLoad u.covCompute], 'Visible', 'on');
            set([u.covQuery u.covReset u.covExport u.covClear u.covToMain], 'Visible', hasPattern || hasJobs);
            set([u.covFmtLabel u.covFmt], 'Visible', hasPattern && isGenericText(u.covPath.Value));
            set([u.covCompute u.covComponent u.covComponentLabel], 'Enable', hasPattern);
            set([u.covExport u.covClear u.covQuery], 'Enable', hasJobs); u.covReset.Enable = hasPattern || hasJobs;
            app.applyCovType();
        end

        function applyCovType(app)
            u = app.ui; conical = u.conical.Value;
            set([u.coneThLabel u.coneTh u.conePhLabel u.conePh u.coneAngLabel u.coneAng u.orientationLabel u.orientation], ...
                'Visible', conical && ~isempty(app.covPatternTarget()), 'Enable', conical);
        end

        function covXRange(app, bounds, widenOnly)
            % Coverage plot X window: the first result establishes it, later results may only widen it.
            if app.cov.syncing, return; end
            bounds = clampRange(bounds, app.DBRange); ax = app.ui.covAx;
            if widenOnly && app.cov.xInit, bounds = [min(ax.XLim(1), bounds(1)) max(ax.XLim(2), bounds(2))]; end
            app.cov.xInit = true; app.cov.syncing = true; guard = onCleanup(@() app.covSyncDone()); %#ok<NASGU>
            set(ax, 'XLimMode', 'manual', 'XLim', bounds);
            set(app.ui.covXSlider, 'Limits', app.DBRange, 'Value', bounds); app.ui.covXSlider.Limits = bounds;   % spinners define the slider travel
            app.setPair(app.ui.covXMin, app.ui.covXMax, bounds, 0.1);
        end

        function covSyncDone(app), if ~app.isClosing, app.cov.syncing = false; end, end

        function onCovXRange(app, src, evt)
            % Spinners are the master window; the slider only zooms the plot inside that window.
            if app.cov.syncing, return; end
            u = app.ui;
            if isequal(src, u.covXSlider)
                sel = sort(double(evt.Value)); if diff(sel) <= 0, return; end
                [u.covXMin.Value, u.covXMax.Value] = deal(sel(1), sel(2)); set(u.covAx, 'XLimMode', 'manual', 'XLim', sel);
            else
                b = sort([u.covXMin.Value u.covXMax.Value]);
                if diff(b) <= 0, if isequal(src, u.covXMin), b(2) = b(1) + 1; else, b(1) = b(2) - 1; end, end
                app.covXRange(b, false);
            end
        end

        %% ---- coverage: callbacks
        function onToCoverage(app, ~, ~)
            if isempty(app.viewTbl), uialert(app.ui.fig, 'Load and process a pattern first.', 'Coverage'); return; end
            app.ui.tabs.SelectedTab = app.ui.covTab; app.ui.covPath.Value = app.file.path;
            node = app.covFind(app.file.path);
            if isempty(node), app.covAddPattern(app.file.base, app.file.path, app.viewTbl, app.view);
            else, app.covSyncFromView(node); app.ui.covTree.SelectedNodes = node; app.setCoverageUI(); end
            app.status('cov', 'Coverage source synchronized from the current Main-tab View Table.', false);
        end

        function onCovLoad(app, ~, ~)
            fp = strtrim(app.ui.covPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFind(fp))
                [f, p] = uigetfile(app.FileFilter, 'Select a pattern or coverage results file'); if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            node = app.covFind(fp);
            if ~isempty(node)
                app.ui.covTree.SelectedNodes = node; app.onCovSelect(); app.ui.covPath.Value = fp; app.setCoverageUI();
                app.status('cov', 'File already loaded — node selected. Add another job or load a different file.', true); return
            end
            app.ui.covPath.Value = fp; out = app.readSource(fp, 'cov');
            if out.meta.isCoverage, app.covLoadResults(fp, out.raw); else, [T, v] = app.buildPattern(out); [~, name] = fileparts(fp); app.covAddPattern(name, fp, T, v); end
        end

        function onCovFormatChanged(app, ~, ~)
            % Re-interpret an already loaded generic coverage pattern with the newly selected format.
            fp = strtrim(app.ui.covPath.Value); old = app.covFind(fp);
            if isempty(old) || ~isGenericText(fp), return; end
            out = readPattern(fp, app.ui.covFmt.Value);
            if out.meta.isCoverage, app.status('cov', 'Coverage-result files are detected automatically; nothing to reprocess.', true); return; end
            name = old.NodeData.name; for j = app.covJobs(old).', delete(j.NodeData.line); end
            delete(old); [T, v] = app.buildPattern(out); app.covAddPattern(name, fp, T, v); app.covFinalize();
            app.status('cov', sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
        end

        function onCovCompute(app, ~, ~)
            node = app.covPatternTarget();
            if isempty(node), uialert(app.ui.fig, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if strcmp(node.NodeData.path, app.file.path) && ~isempty(app.viewTbl), app.covSyncFromView(node); end
            t0 = tic; d = node.NodeData; comp = app.ui.covComponent.Value; thr = app.covThresholds(); conical = app.ui.conical.Value;
            if conical
                [t0c, p0, alpha] = deal(app.ui.coneTh.Value, mod(app.ui.conePh.Value, 360), app.ui.coneAng.Value);
                mask = cosd(d.theta)*cosd(t0c) + sind(d.theta)*sind(t0c).*cosd(d.phi - p0) >= cosd(alpha);
                centre = app.coneLabel(t0c, p0);
                label = sprintf('Conical coverage (%s) α=%s°', centre, fmtNum(alpha)); tableTag = sprintf('Con %s α%s°', erase(centre, {'=', ','}), fmtNum(alpha));
                k = app.ui.orientation.Value; if k == 0, k = d.boresight; end, orient = string(app.Axes.labels{k});
            else
                mask = true(height(d.pattern), 1); label = 'Sph coverage'; tableTag = 'Sph'; orient = "n/a";
            end
            cov = coverageCCDF(d.pattern.(comp), mask, thr, d.omega);
            app.covAddJob(node, thr, cov, label, comp, tableTag, conical, orient);
            app.covXRange([thr(1) thr(end)], true); app.ui.covResults.Visible = 'on';
            msg = sprintf('Run-<b>%d</b> computed: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', app.cov.runID, label, d.name, comp, numel(thr));
            if conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, orient); end
            app.status('cov', msg, false); app.perfLog("Compute coverage", t0);
        end

        function onCovReset(app, ~, ~)
            delete(app.ui.covRoot.Children); cla(app.ui.covAx); legend(app.ui.covAx, 'off');
            app.ui.covTable.Data = table(); app.cov = struct('runID', 0, 'presetKey', '', 'syncing', false, 'xInit', false);
            app.ui.covAx.XLimMode = 'auto'; app.ui.covResults.Visible = 'off'; app.setCoverageUI();
            app.status('cov', 'Coverage workspace reset 🔄', true);
        end

        function onCovClear(app, ~, ~)
            % Remove query markers and datatips of the selected subtree only (checked state is ignored).
            sel = app.ui.covTree.SelectedNodes;
            if isempty(sel), app.status('cov', 'Select a node to clear.', true); return; end
            jobs = app.covJobs(sel);
            if isempty(jobs), app.status('cov', 'No coverage results under the selected node.', true); return; end
            for j = jobs.'
                delete(findall(app.ui.covAx, '-regexp', 'Tag', sprintf('^CovQ_\\w+_%d$', j.NodeData.id))); delete(findall(j.NodeData.line, 'Type', 'datatip'));
            end
            app.status('cov', 'Selected DataTips and query markers cleared.', true);
        end

        function onCovExport(app, ~, ~)
            if isempty(app.ui.covTable.Data), return; end
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, ...
                'Export Coverage Results', fullfile(app.file.folder, 'coverage_results.csv'));
            if isequal(f, 0), return; end
            writeTable(app.ui.covTable.Data, fullfile(p, f)); app.status('cov', ['Coverage results exported to ' fullfile(p, f)], true);
        end

        function onCovType(app, ~, ~)
            app.applyCovType();
            if ~app.ui.conical.Value, return; end
            node = app.covPatternTarget(); if ~isempty(node), app.covSync(node); end
            app.covOrientationStatus();
        end

        function onCovOrientation(app, ~, ~)
            % Auto resolves the detected axis; an explicit selection is authoritative and never overwritten on compute.
            k = app.ui.orientation.Value; node = app.covPatternTarget();
            if k == 0, if isempty(node), return; end, k = node.NodeData.boresight; end
            [app.ui.coneTh.Value, app.ui.conePh.Value] = deal(app.Axes.theta(k), app.Axes.phi(k));
            app.covOrientationStatus();
        end

        function covOrientationStatus(app)
            if ~app.ui.conical.Value, return; end
            k = app.ui.orientation.Value; node = app.covPatternTarget();
            if k == 0, if isempty(node), return; end, k = node.NodeData.boresight; end
            app.status('cov', sprintf('Conical coverage — orientation <b>%s</b> (cone centre θ₀=%s°, φ₀=%s°).', app.Axes.labels{k}, ...
                fmtNum(app.ui.coneTh.Value), fmtNum(app.ui.conePh.Value)), false);
        end

        function onCovComponent(app, ~, ~)
            node = app.covPatternTarget(); if isempty(node), return; end
            app.covSync(node, string(app.ui.covComponent.Value)); app.covOrientationStatus();
        end

        function onCovChecked(app, ~, ~)
            jobs = app.covJobs(); vis = app.covChecked(jobs);
            for k = 1:numel(jobs)
                on = vis(k); d = jobs(k).NodeData; d.line.Visible = on;
                set(findall(app.ui.covAx, '-regexp', 'Tag', sprintf('^CovQ_\\w+_%d$', d.id)), 'Visible', on);
                set(findall(d.line, 'Type', 'datatip'), 'Visible', on);
            end
            app.covFinalize();
        end

        function onCovSelect(app, ~, ~)
            sel = app.ui.covTree.SelectedNodes; jobs = app.covJobs();
            for j = jobs.', ln = j.NodeData.line; ln.LineWidth = 1.6 + (~isempty(sel) && j == sel(1)); end   % emphasise the selected curve
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.status('cov', 'Ready.', false); return; end
            d = sel(1).NodeData; target = app.covPatternTarget(); if ~isempty(target), app.covSync(target); end
            if ~strcmp(d.kind, 'job')
                kind = 'Pattern'; if strcmp(d.kind, 'results'), kind = 'Results'; end
                app.status('cov', sprintf('%s <b>"%s"</b> — <b>%d</b> coverage job(s).', kind, d.name, numel(sel(1).Children)), false);
                if strcmp(d.kind, 'pattern'), app.covOrientationStatus(); end
                return
            end
            shown = round(d.cov, 2); cmax = max(shown); imax = find(shown == cmax, 1, 'last'); t50 = app.covQueryPoint(d, "thr", 50);
            parts = {char(d.label)};
            if d.isConical, parts{end+1} = sprintf('Orientation <b>%s</b>', d.orient); end
            parts{end+1} = sprintf('Threshold [%s, %s] dB, step %s dB', fmtNum(d.thr(1)), fmtNum(d.thr(end)), fmtNum(d.step));
            if isfinite(t50), parts{end+1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', fmtNum(t50)); else, parts{end+1} = '<b>50%-coverage unavailable</b>'; end
            parts{end+1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmtNum(cmax), fmtNum(d.thr(imax)));
            app.status('cov', strjoin(parts, ' | '), false);
        end

        function covQuery(app, mode)
            % mode "cov": coverage at a threshold; mode "thr": threshold reaching a coverage percentage.
            sel = app.ui.covTree.SelectedNodes;
            if isempty(sel), app.status('cov', 'Select a node to query.', true); return; end
            jobs = app.covJobs(sel); jobs = jobs(app.covChecked(jobs));
            if isempty(jobs), app.status('cov', 'No checked results under the selected node.', true); return; end
            if mode == "cov", q = app.ui.qCov.Value; else, q = app.ui.qThr.Value; end
            ax = app.ui.covAx; hit = false;
            for j = jobs.'
                d = j.NodeData; tag = sprintf('CovQ_%s_%d', mode, d.id); delete(findall(ax, 'Tag', tag));
                [x, y] = app.covQueryPoint(d, mode, q); if ~isfinite(x) || ~isfinite(y), continue; end
                line(ax, [x x], [ax.YLim(1) y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [app.DBRange(1) x], [y y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                d.line.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", 'XData', '%.2f dB'); dataTipTextRow("Coverage", 'YData', '%.2f%%')];
                datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'FontSize', 9, 'Tag', tag); hit = true;   % exact interpolated point
            end
            if ~hit, app.status('cov', 'Query value is outside the selected checked range.', true);
            elseif mode == "cov", app.status('cov', sprintf('Coverage queried at %s dB.', fmtNum(q)), false);
            else, app.status('cov', sprintf('Threshold queried at %s%% coverage.', fmtNum(q)), false);
            end
        end

        %% ---- UI construction
        function h = place(~, h, row, col), h.Layout.Row = row; h.Layout.Column = col; end

        function h = label(app, parent, text, row, col, varargin)
            h = app.place(uilabel(parent, 'Text', text, 'HorizontalAlignment', 'right', varargin{:}), row, col);
        end

        function dd = formatDropdown(~, parent, callback)
            dd = uidropdown(parent, 'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
                '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
                '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'}, ...
                'Value', 'gain', 'Visible', 'off', 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'ValueChangedFcn', callback);
        end

        function [tab, ax, s] = rangeTab(app, parent, name, polar)
            % One plot tab: axes on the right, vertical range slider with max/min spinners on the left.
            tab = uitab(parent, 'Title', name); g = uigridlayout(tab, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
            if polar, ax = polaraxes(g); else, ax = uiaxes(g); end
            app.place(ax, [1 3], 2);
            s.max = app.place(uispinner(g, 'Step', 5), 1, 1);
            s.slider = app.place(uislider(g, 'range', 'Orientation', 'vertical'), 2, 1);
            s.min = app.place(uispinner(g, 'Step', 5), 3, 1);
        end

        function initAxes(app, ax, is3D, view0)
            % One-time axes setup: persistent hold, interactions, one "Delete DataTips" context menu, default camera.
            m = uicontextmenu(app.ui.fig); uimenu(m, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~,~) delete(findall(ax, 'Type', 'datatip')));
            ax.UserData = struct('menu', m, 'view', view0, 'rmax', 1); ax.ContextMenu = m; hold(ax, 'on');
            enableDefaultInteractivity(ax);
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), return; end
            if is3D, ax.Interactions = [rotateInteraction dataTipInteraction]; else, ax.Interactions = [zoomInteraction dataTipInteraction]; end
        end

        function createComponents(app)
            u = struct();
            u.fig = uifigure('Name', ['Antenna Pattern Analyzer Tool — APAT v' app.Version], 'Visible', 'off', 'Position', [100 100 1136 739], ...
                'WindowState', 'maximized', 'CloseRequestFcn', @(~,~) delete(app));
            app.ui = u;                                                                  % initAxes needs the figure early
            u.tabs = uitabgroup(uigridlayout(u.fig, [1 1]));
            u.mainTab = uitab(u.tabs, 'Title', 'Process Pattern 📡'); u.covTab = uitab(u.tabs, 'Title', 'Compute Coverage 📈');
            % ------------------------------------------------------------ Main tab: inputs & parameters
            G = uigridlayout(u.mainTab, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});
            P = uigridlayout(app.place(uipanel(G, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 14]), 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            app.label(P, 'Input Pattern:', 1, 1);
            u.path = app.place(uieditfield(P, 'text'), 1, [2 8]);
            u.ffdLabel = app.label(P, 'FFD Freq:', 1, 9, 'Visible', 'off');
            u.ffd = app.place(uidropdown(P, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', app.cb(@app.onFFDChanged)), 1, 10);
            u.load = app.place(uibutton(P, 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', app.cb(@app.onLoad)), 1, [11 12]);
            u.processBtn = app.place(uibutton(P, 'Text', '⚙️ Process', 'ButtonPushedFcn', app.cb(@app.onProcess)), 1, [13 14]);
            u.resetBtn = app.place(uibutton(P, 'Text', 'Reset Params', 'ButtonPushedFcn', app.cb(@app.onResetParams)), 2, [1 3]);
            u.mainFmtLabel = app.label(P, 'Format:', 2, [4 5], 'Visible', 'off');
            u.mainFmt = app.place(app.formatDropdown(P, app.cb(@app.onFormatChanged)), 2, [6 8]);
            u.step = app.place(uidropdown(P, 'Items', {'STEP', 'STEP: 1°'}, 'Visible', 'off', 'Enable', 'off', 'ValueChangedFcn', app.cb(@app.onStepChanged)), 2, [9 10]);
            u.exportOut = app.place(uibutton(P, 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@app.onExportResults)), 2, [11 12]);
            u.exportUAN = app.place(uibutton(P, 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@app.onExportUAN)), 2, [13 14]);
            u.rxLabel = app.label(P, 'Rw Sense', 3, 1, 'Visible', 'off');
            u.rxPol = app.place(uidropdown(P, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Editable', 'on', 'Visible', 'off'), 3, 2);
            u.rwLabel = app.label(P, 'Rw (dB)', 3, 3, 'Visible', 'off');
            u.rw = app.place(uispinner(P, 'Value', 6, 'Visible', 'off'), 3, 4);
            u.lossLabel = app.label(P, 'Loss (−) / Gain (+) dB', 3, 5, 'Visible', 'off');
            u.loss = app.place(uispinner(P, 'Step', 0.1, 'Visible', 'off'), 3, 6);
            u.ptLabel = app.label(P, 'Tx Pwr (Pt)', 3, 7, 'Visible', 'off');
            u.pt = app.place(uispinner(P, 'Visible', 'off'), 3, 8);
            u.ptUnit = app.place(uidropdown(P, 'Items', {'dBW', 'dBm', 'Watts'}, 'Visible', 'off'), 3, 9);
            u.distLabel = app.label(P, 'Distance', 3, 10, 'Visible', 'off');
            u.dist = app.place(uispinner(P, 'Value', 1, 'Visible', 'off'), 3, 11);
            u.distUnit = app.place(uidropdown(P, 'Items', {'m', 'km'}, 'Visible', 'off'), 3, 12);
            u.covBtn = app.place(uibutton(P, 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@app.onToCoverage)), 3, [13 14]);
            % ------------------------------------------------------------ Main tab: full-pattern plots
            u.fullPanel = app.place(uipanel(G, 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [1 6]);
            u.fullTabs = uitabgroup(uigridlayout(u.fullPanel, [1 1]));
            titles = {'Contour Plot', 'Circular Contour Plot', '3D Spherical Plot', '3D Polar Plot', '3D Surface Plot'}; views = {[0 90], [0 90], [135 25], [135 25], [-35 35]};
            for k = 1:5
                [tab, ax, s] = app.rangeTab(u.fullTabs, titles{k}, k == 2); app.initAxes(ax, k >= 3, views{k});
                F(k) = struct('tab', tab, 'ax', ax, 'slider', s.slider, 'min', s.min, 'max', s.max); %#ok<AGROW>
            end
            u.full = F; u.fullSlider = [F.slider]; u.fullMin = [F.min]; u.fullMax = [F.max];
            [u.ctrAx, u.cirAx, u.sphAx, u.polAx, u.rect3Ax] = F.ax;
            set(u.fullSlider, 'ValueChangedFcn', app.cb(@(s,~) app.onRange("full", 0, s)));
            set(u.fullMin, 'ValueChangedFcn', app.cb(@(s,~) app.onRange("full", 1, s))); set(u.fullMax, 'ValueChangedFcn', app.cb(@(s,~) app.onRange("full", 2, s)));
            % ------------------------------------------------------------ Main tab: cut plots
            u.cutPanel = app.place(uipanel(G, 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [7 12]);
            u.cutTabs = uitabgroup(uigridlayout(u.cutPanel, [1 1]));
            C = uigridlayout(uitab(u.cutTabs, 'Title', 'Polar Cut Plot'), 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            u.cutMax = app.place(uispinner(C, 'Step', 5, 'ValueChangedFcn', app.cb(@(s,~) app.onRange("cut", 2, s))), 1, 1);
            u.cutSlider = app.place(uislider(C, 'range', 'Orientation', 'vertical', 'ValueChangedFcn', app.cb(@(s,~) app.onRange("cut", 0, s))), [2 3], 1);
            u.cutMin = app.place(uispinner(C, 'Step', 5, 'ValueChangedFcn', app.cb(@(s,~) app.onRange("cut", 1, s))), 4, 1);
            u.cutPolar = app.place(polaraxes(C), [1 4], 3);
            u.hpbwBtn = app.place(uibutton(C, 'state', 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', app.cb(@app.onCutChanged)), 1, 4);
            u.hpbwLabel = app.place(uilabel(C, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold'), 2, 4);
            u.ecutGrid = app.place(uigridlayout(C, [3 1]), 3, 4);
            u.boxEt = uicheckbox(u.ecutGrid, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', app.cb(@app.onCutChanged));
            u.boxEr = uicheckbox(u.ecutGrid, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', app.cb(@app.onCutChanged));
            u.boxEl = uicheckbox(u.ecutGrid, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', app.cb(@app.onCutChanged));
            u.exportCut = app.place(uibutton(C, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', app.cb(@app.onExportCut)), 4, 4);
            u.cutRect = uiaxes(uigridlayout(uitab(u.cutTabs, 'Title', 'Rectangular Cut Plot'), [1 1]));
            xlabel(u.cutRect, 'Theta (degree)'); ylabel(u.cutRect, 'Magnitude (dB)'); u.cutRect.Box = 'on';
            app.initAxes(u.cutPolar, false, [0 90]); app.initAxes(u.cutRect, false, [0 90]);
            % ------------------------------------------------------------ Main tab: plot control
            u.ctrlPanel = app.place(uipanel(G, 'Title', 'Plot Control 🎨', 'Visible', 'off'), 2, [13 14]);
            K = uigridlayout(u.ctrlPanel, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', repmat({'fit'}, 1, 15));
            app.label(K, 'Component', 1, 1);
            u.component = app.place(uidropdown(K, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', app.cb(@app.onComponentChanged)), 1, 2);
            app.label(K, 'Cut type', 2, 1);
            u.cutType = app.place(uidropdown(K, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', app.cb(@app.onCutChanged)), 2, 2);
            app.label(K, 'Cut value', 3, 1);
            u.cutValue = app.place(uispinner(K, 'Limits', [0 360], 'ValueChangedFcn', app.cb(@app.onCutChanged)), 3, 2);
            app.label(K, 'Cut fields', 4, 1);
            u.basis = app.place(uidropdown(K, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Enable', 'off', 'ValueChangedFcn', app.cb(@app.onCutChanged)), 4, 2);
            app.label(K, 'Colorbar max', 5, 1); u.cmax = app.place(uispinner(K, 'Value', 10, 'ValueChangedFcn', app.cb(@app.onColorbarSpinner)), 5, 2);
            app.label(K, 'Colorbar min', 6, 1); u.cmin = app.place(uispinner(K, 'Value', -40, 'ValueChangedFcn', app.cb(@app.onColorbarSpinner)), 6, 2);
            app.label(K, 'Colorbar step', 7, 1); u.cstep = app.place(uispinner(K, 'Value', 5, 'Limits', [0.1 100], 'ValueChangedFcn', app.cb(@(~,~) app.applyFullRange(app.fullLim()))), 7, 2);
            app.label(K, 'Adjust Colorbar', 8, 1);
            u.climApply = app.place(uibutton(K, 'Text', 'Apply', 'Tooltip', 'Apply min/max to every full-pattern plot.', 'ButtonPushedFcn', app.cb(@app.onColorbarSpinner)), 8, 2);
            app.label(K, '3D view', 9, 1);
            u.view3D = app.place(uidropdown(K, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'ValueChangedFcn', app.cb(@app.onView3DChanged)), 9, 2);
            u.phiSpan = app.place(uiswitch(K, 'slider', 'Items', {'φ: 0° to 360°', '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'ValueChangedFcn', app.cb(@app.onSpanChanged)), 10, [1 2]);
            u.thetaSpan = app.place(uiswitch(K, 'slider', 'Items', {'θ: 0° to 180°', '−90° to 90°'}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'ValueChangedFcn', app.cb(@app.onSpanChanged)), 11, [1 2]);
            u.ehSwitch = app.place(uiswitch(K, 'slider', 'Items', {'E-Plane cut', 'H-Plane cut'}, 'ValueChangedFcn', app.cb(@app.onPlaneChanged)), 12, [1 2]);
            u.overlayBox = app.place(uicheckbox(K, 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', app.cb(@(~,~) app.refreshOverlay())), 13, [1 2]);
            u.pobBox = app.place(uicheckbox(K, 'Text', 'Annotate POB', 'ValueChangedFcn', app.cb(@(s,~) app.toggleTag('APAT_POB', s.Value))), 14, [1 2]);
            u.hpbwBox = app.place(uicheckbox(K, 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', app.cb(@(s,~) app.toggleTag('APAT_HPBW', s.Value))), 15, [1 2]);
            % ------------------------------------------------------------ Main tab: data tables & status
            u.outFilter = app.place(uidropdown(G, 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Visible', 'off', 'ValueChangedFcn', app.cb(@app.onFilter)), 3, [13 14]);
            u.dataTabs = app.place(uitabgroup(G, 'Visible', 'off'), 4, [1 14]);
            u.tableOut = uitable(uigridlayout(uitab(u.dataTabs, 'Title', 'Results 📤'), [1 1]), 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnWidth', '1x', 'ColumnRearrangeable', 'on');
            u.tableIn = uitable(uigridlayout(uitab(u.dataTabs, 'Title', 'Input 📥'), [1 1]), 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnRearrangeable', 'on');
            u.tableMeta = uitable(uigridlayout(uitab(u.dataTabs, 'Title', 'Metadata 📋'), [1 1]), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            u.styleOn = uistyle('FontWeight', 'bold', 'BackgroundColor', [0.8 1 0.8]); u.styleOff = uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9]);
            ready = 'Ready — load an antenna pattern file to begin 🚀';
            u.mainStatus = app.place(uilabel(G, 'Text', ready, 'UserData', ready, 'Interpreter', 'html'), 5, [1 14]);
            % ------------------------------------------------------------ Coverage tab
            V = uigridlayout(u.covTab, 'ColumnWidth', {'1x'}, 'RowHeight', {'fit', '1x', 'fit'});
            Q = uigridlayout(app.place(uipanel(V, 'Title', 'Inputs & Parameters 🎛️'), 1, 1), 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'});
            u.covParams = Q;
            u.covType = app.place(uibuttongroup(Q, 'Title', 'Coverage Type', 'SelectionChangedFcn', app.cb(@app.onCovType)), [1 2], [1 2]);
            u.spherical = uiradiobutton(u.covType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            u.conical = uiradiobutton(u.covType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            u.orientationLabel = app.label(Q, 'Orientation 🧭:', 3, 1);
            u.orientation = app.place(uidropdown(Q, 'Items', [{'Auto'}, app.Axes.labels], 'ItemsData', 0:6, 'ValueChangedFcn', app.cb(@app.onCovOrientation)), 3, 2);
            u.covComponentLabel = app.label(Q, 'Component:', 4, 1);
            u.covComponent = app.place(uidropdown(Q, 'Items', {'E_Total_dB'}, 'ValueChangedFcn', app.cb(@app.onCovComponent)), 4, 2);
            u.covPathLabel = app.label(Q, 'Antenna Pattern:', 1, 3);
            u.covPath = app.place(uieditfield(Q, 'text'), 1, [4 8]);
            u.covLoad = app.place(uibutton(Q, 'Text', '📂 Load File', 'ButtonPushedFcn', app.cb(@app.onCovLoad)), 1, 9);
            u.covCompute = app.place(uibutton(Q, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'ButtonPushedFcn', app.cb(@app.onCovCompute)), 1, 10);
            u.thrMinLabel = app.label(Q, 'Threshold Min (dB):', 2, 3); u.thrMin = app.place(uispinner(Q, 'Value', -40), 2, 4);
            u.thrMaxLabel = app.label(Q, 'Threshold Max (dB):', 2, 5); u.thrMax = app.place(uispinner(Q, 'Value', 10), 2, 6);
            u.thrStepLabel = app.label(Q, 'Step (dB):', 2, 7); u.thrStep = app.place(uispinner(Q, 'Value', 1, 'Limits', [0.01 100]), 2, 8);
            u.covReset = app.place(uibutton(Q, 'Text', '🔄 Reset', 'ButtonPushedFcn', app.cb(@app.onCovReset)), 2, 9);
            u.covExport = app.place(uibutton(Q, 'Text', '💾 Export Results', 'ButtonPushedFcn', app.cb(@app.onCovExport)), 2, 10);
            u.coneThLabel = app.label(Q, 'Cone θ₀ (°):', 3, 3); u.coneTh = app.place(uispinner(Q, 'Limits', [0 180]), 3, 4);
            u.conePhLabel = app.label(Q, 'Cone φ₀ (°):', 3, 5); u.conePh = app.place(uispinner(Q, 'Limits', [0 360]), 3, 6);
            u.coneAngLabel = app.label(Q, 'Cone Angle α (°):', 3, 7); u.coneAng = app.place(uispinner(Q, 'Value', 45, 'Limits', [0 180]), 3, 8);
            u.covClear = app.place(uibutton(Q, 'Text', '🧹 Clear DataTips', 'ButtonPushedFcn', app.cb(@app.onCovClear)), 3, 9);
            u.covToMain = app.place(uibutton(Q, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~,~) set(u.tabs, 'SelectedTab', u.mainTab)), 3, 10);
            u.qCovLabel = app.label(Q, 'Coverage @ dB:', 4, 3); u.qCov = app.place(uispinner(Q, 'ValueDisplayFormat', '%g dB'), 4, 4);
            u.qCovBtn = app.place(uibutton(Q, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', app.cb(@(~,~) app.covQuery("cov"))), 4, 5);
            u.qThrLabel = app.label(Q, 'Threshold @ %:', 4, 6); u.qThr = app.place(uispinner(Q, 'Value', 50, 'ValueDisplayFormat', '%g%%'), 4, 7);
            u.qThrBtn = app.place(uibutton(Q, 'Text', '🔍 Query Threshold', 'ButtonPushedFcn', app.cb(@(~,~) app.covQuery("thr"))), 4, 8);
            u.covFmtLabel = app.label(Q, 'Format:', 4, 9);
            u.covFmt = app.place(app.formatDropdown(Q, app.cb(@app.onCovFormatChanged)), 4, 10);
            u.covQuery = [u.qCovLabel u.qCov u.qCovBtn u.qThrLabel u.qThr u.qThrBtn];
            u.covResults = app.place(uipanel(V, 'Title', 'Results', 'Visible', 'off'), 2, 1);
            R = uigridlayout(u.covResults, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            u.covTree = app.place(uitree(R, 'checkbox', 'SelectionChangedFcn', app.cb(@app.onCovSelect), 'CheckedNodesChangedFcn', app.cb(@app.onCovChecked)), [1 2], 1);
            u.covRoot = uitreenode(u.covTree, 'Text', 'Coverage Results');
            u.covAx = app.place(uiaxes(R), 1, [2 4]); title(u.covAx, 'Coverage vs Threshold'); xlabel(u.covAx, 'Threshold (dB)'); ylabel(u.covAx, 'Coverage (%)');
            set(u.covAx, 'Box', 'on', 'Layer', 'top', 'YLim', [0 100], 'Interactions', dataTipInteraction); hold(u.covAx, 'on'); grid(u.covAx, 'on');
            u.covTable = app.place(uitable(R, 'ColumnWidth', '1x', 'RowName', {}), [1 2], 5);
            u.covXMin = app.place(uispinner(R, 'Value', -40, 'ValueChangedFcn', app.cb(@app.onCovXRange)), 2, 2);
            u.covXSlider = app.place(uislider(R, 'range', 'Limits', app.DBRange, 'Value', [-40 10], 'ValueChangedFcn', app.cb(@app.onCovXRange), 'ValueChangingFcn', app.cb(@app.onCovXRange)), 2, 3);
            u.covXMax = app.place(uispinner(R, 'Value', 10, 'ValueChangedFcn', app.cb(@app.onCovXRange)), 2, 4);
            u.covStatus = app.place(uilabel(V, 'Text', 'Ready 🚀', 'UserData', 'Ready 🚀', 'Interpreter', 'html'), 3, 1);
            app.ui = u;
        end
    end

    %% ------------------------------------------------------------------ self-test
    methods
        function report = runSelfTest(app)
            %RUNSELFTEST Deterministic checks of the numerical layer (no UI interaction).
            [PG, TG] = meshgrid(0:30:330, 0:30:180);
            T = table(TG(:), PG(:), 10*cosd(TG(:)).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            w = solidWeights(T.Theta, T.Phi); pk = resolvePeak(T.E_Total_dB, app.PeakPercentile, app.PeakMaxExcessDB);
            r.solidAngle = abs(sum(w) - 4*pi) < 1e-9;
            r.orientation = calcOrientation(T.E_Total_dB, T.Theta, T.Phi, w, app.Axes, pk) == 1;
            [P2, T2] = meshgrid(0:2:358, 0:2:180); A = 12*cosd(T2).^2 - 0.5*sind(P2).^2;
            R = resampleCanonical(table(T2(:), P2(:), A(:), 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'}), 1);
            native = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0 & R.Phi < 360;
            err = max(abs(R.E_Total_dB(native) - (12*cosd(R.Theta(native)).^2 - 0.5*sind(R.Phi(native)).^2)));
            r.resampling = height(R) == 181*361 && err < 1e-9;
            r.autoRange = isequal(autoRange50([3.2; -250; -17], app.PeakPercentile, app.PeakMaxExcessDB), [-45 5]);
            g = repmat(0.02, 1e5, 1); g(1) = 10.02; sp = resolvePeak(g, app.PeakPercentile, app.PeakMaxExcessDB);
            r.isolatedSpike = sp.wasAdjusted && abs(sp.value - 0.02) < 1e-12 && sp.rawIndex == 1;
            r.peakAwareRange = isequal(autoRange50(g, app.PeakPercentile, app.PeakMaxExcessDB), [-45 5]);
            r.percentile = abs(pct((1:100).', 99.99) - 100) < 1e-12 && abs(pct((1:100).', 50) - 50.5) < 1e-12;
            r.arSemantics = all(arrayfun(@isARName, ["AR", "AR_dB", "AR dB", "Axial Ratio", "Axial_Ratio"]));
            r.coverage = isequal(coverageCCDF([0; 10; 20], true(3, 1), [5; 15; 25], [1; 1; 1]), [200/3; 100/3; 0]);
            [~, hpbwRows] = circleCut(T.Theta, T.Phi, false, 0); r.cutRows = numel(hpbwRows) == 12;   % 7 primary + 5 opposite
            ffdFile = [tempname '.ffd']; cleanup = onCleanup(@() delete(ffdFile)); %#ok<NASGU>
            writelines(["0 180 3"; "-180 180 3"; string(compose('%d 0 0 1', (1:9).'))], ffdFile);
            d = readPattern(ffdFile, "ffd"); r.ffdReader = strcmp(d.meta.source, 'HFSS FFD') && isscalar(d.blocks) && height(d.blocks{1}) == 9;
            report = r; report.pass = all(structfun(@(x) x, r));
            if ~report.pass
                names = fieldnames(r); error('apat:test:SelfTestFailed', 'Self-test failed: %s', strjoin(names(~structfun(@(x) x, r)), ', '));
            end
        end
    end
end

%% ====================================================================== I/O layer (pure)
function out = readPattern(fp, fmt)
%READPATTERN Parse any supported source into struct(raw, blocks, freqs, meta). Every block is a
% canonical table {Theta,Phi,Re_Eth,Im_Eth,Re_Eph,Im_Eph} or a gain-only table {Theta,Phi,<gain columns>}.
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
out = struct('raw', table(), 'blocks', {{}}, 'freqs', NaN, 'meta', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'hasFrequency', false));
switch ext
    case {'XLSX', 'XLS'},        out = readExcelMatrix(fp, out);
    case {'CSV', 'TXT', 'DAT'},  out = readGenericText(fp, string(fmt), out);
    case 'CUT',                  out = readGraspCut(fp, out);
    otherwise,                   out = readFarField(fp, ext, out);
end
end

function tf = isGenericText(fp)
[~, ~, ext] = fileparts(fp); tf = ismember(lower(ext), {'.csv', '.txt', '.dat'});
end

function T = efieldTable(theta, phi, Eth, Eph)
T = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function [Eth, Eph] = circToLinear(Ercp, Elcp)
Eth = (Ercp + Elcp)/sqrt(2); Eph = (Ercp - Elcp)/(1i*sqrt(2));
end

function E = magPhase(dB, deg), E = 10.^(dB/20) .* exp(1i*deg2rad(deg)); end

function out = readGenericText(fp, fmt, out)
%READGENERICTEXT CSV/TXT/DAT: coverage-results table, gain-only pattern, or a 6-column E-field layout (FMT).
opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
T = rmmissing(readtable(fp, opts)); raw = T; n = width(T);
assert(n >= 2 && ~isempty(T), 'readFile:InvalidFormat', 'File needs at least two numeric columns.');
names = lower(string(T.Properties.VariableNames)); hasHeaders = ~all(startsWith(names, "var")); c1 = T{:, 1}; c2 = T{:, 2};
% Coverage results (threshold + percentage columns) are detected before any pattern interpretation.
coverageHeader = contains(names(1), "threshold") || any(contains(names(2:end), "coverage"));
if (fmt == "gain" || n < 6 || coverageHeader) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:n-1))]; end
    out.raw = T; out.meta.isCoverage = true; return
end
if fmt == "gain"                                                   % the wider-span angle column is phi
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; T = movevars(T, 'Theta', 'Before', 1);
    else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    if ~hasHeaders, raw = T; end
    out.raw = raw; out.blocks = {T}; out.meta.isGainOnly = true; return
end
assert(n >= 6, 'readFile:TextEFieldColumns', 'The selected E-field format requires six numeric columns.');
V = T{:, 3:6}; magPhaseFmt = endsWith(fmt, "magphase"); linear = startsWith(fmt, "linear"); layout = "not applicable";
if magPhaseFmt                                                     % phase columns exceed ±100 → grouped or interleaved layout
    isPhase = max(abs(V), [], 1, 'omitnan') > 100;
    if isPhase(2) && ~isPhase(3), m = [1 3]; p = [2 4]; layout = "interleaved"; else, m = [1 2]; p = [3 4]; layout = "grouped"; end
    E1 = magPhase(V(:, m(1)), V(:, p(1))); E2 = magPhase(V(:, m(2)), V(:, p(2)));
else
    E1 = complex(V(:, 1), V(:, 2)); E2 = complex(V(:, 3), V(:, 4));
end
if linear, [Eth, Eph] = deal(E1, E2); elseif startsWith(fmt, "rcp"), [Eth, Eph] = circToLinear(E1, E2); else, [Eth, Eph] = circToLinear(E2, E1); end
if ~hasHeaders                                                     % name the raw columns after the interpretation
    if linear, c = ["E_TH", "E_PH"]; rect = ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"]; else, c = ["POL1", "POL2"]; rect = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"]; end
    if magPhaseFmt, f = [c + "_dB", c + "_deg"]; if layout == "interleaved", f = f([1 3 2 4]); end, else, f = rect; end
    raw.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", f]);
end
out.meta.source = sprintf('Generic text (%s, %s)', fmt, layout); out.raw = raw; out.blocks = {efieldTable(c1, c2, Eth, Eph)};
end

function [nHdr, ffd] = scanHeader(fp)
%SCANHEADER Number of leading non-data lines; detects the HFSS FFD header (two numeric triples [+ frequencies]).
fid = fopen(fp, 'r'); assert(fid > 0, 'apat:io:OpenFailed', 'Cannot open file: %s', fp); cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
head = strings(0, 1);
while numel(head) < 200, ln = fgetl(fid); if ~ischar(ln), break; end, head(end+1, 1) = string(ln); end %#ok<AGROW>
nums = arrayfun(@(s) numel(sscanf(s, '%f')), head); nonEmpty = find(strlength(strtrim(head)) > 0);
ffd = struct('isFFD', false, 'theta', [], 'phi', [], 'freq', []);
if numel(nonEmpty) >= 2 && all(nums(nonEmpty(1:2)) == 3)
    t = sscanf(head(nonEmpty(1)), '%f'); p = sscanf(head(nonEmpty(2)), '%f'); nHdr = nonEmpty(2);
    ffd = struct('isFFD', true, 'theta', linspace(t(1), t(2), round(t(3))).', 'phi', linspace(p(1), p(2), round(p(3))).', 'freq', []);
    if numel(nonEmpty) >= 3                                        % optional "Frequencies f1 f2 ..." line (a bare count is ignored)
        tok = regexp(char(head(nonEmpty(3))), '^\s*frequenc(?:y|ies)\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok), f = sscanf(tok{1}, '%f'); if ~isscalar(f), ffd.freq = f(:); end, nHdr = nonEmpty(3); end
    end
else
    nHdr = find(nums >= 4, 1) - 1; if isempty(nHdr), nHdr = 0; end  % first line with ≥ 4 numeric fields starts the data
end
end

function out = readFarField(fp, ext, out)
%READFARFIELD Column-oriented far-field exports: XGTD UAN/FZ, GRASP OUT, CST FFS, FEKO FFE, HFSS FFD.
[nHdr, ffd] = scanHeader(fp);
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = readmatrix(fp, setvartype(opts, 'double')); M = M(~all(isnan(M), 2), 1:min(end, 6));
switch ext
    case {'FZ', 'UAN'}                                             % Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
        names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}; th = M(:, 1); ph = M(:, 2);
        Eth = magPhase(M(:, 3), M(:, 5)); Eph = magPhase(M(:, 4), M(:, 6)); out.meta.source = ['XGTD ' ext];
    case 'OUT'                                                     % Theta Phi Re/Im(RHCP) Re/Im(LHCP)
        names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; th = M(:, 1); ph = M(:, 2);
        [Eth, Eph] = circToLinear(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6))); out.meta.source = 'TICRA/GRASP OUT';
    case 'FFS'                                                     % Phi Theta Re/Im(Eth) Re/Im(Eph)
        names = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; ph = M(:, 1); th = M(:, 2);
        Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6)); out.meta.source = 'CST FFS';
    case 'FFE'                                                     % Theta Phi Re/Im(Eth) Re/Im(Eph) [extra columns ignored]
        names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; th = M(:, 1); ph = M(:, 2);
        Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6)); out.meta.source = 'FEKO FFE';
    case 'FFD'                                                     % header grid + [Re/Im(Eth) Re/Im(Eph)] per frequency block
        assert(ffd.isFFD, 'readFile:ffd', 'FFD header (theta/phi ranges) not found.');
        th = repelem(ffd.theta, numel(ffd.phi)); ph = repmat(ffd.phi, numel(ffd.theta), 1); n = numel(th);
        sep = isnan(M(:, 1)); freqs = [ffd.freq; M(sep & ~isnan(M(:, 2)), 2)].'; F = M(~sep, 1:4);   % "Frequency f" separator rows
        assert(mod(size(F, 1), n) == 0, 'readFile:ffd', 'FFD row count does not match the theta/phi grid.');
        nb = size(F, 1)/n; freqs(end+1:nb) = NaN; freqs = freqs(1:nb);
        out.blocks = arrayfun(@(b) efieldTable(th, ph, complex(F((b-1)*n + (1:n), 1), F((b-1)*n + (1:n), 2)), complex(F((b-1)*n + (1:n), 3), F((b-1)*n + (1:n), 4))), 1:nb, 'UniformOutput', false);
        out.freqs = freqs; out.raw = out.blocks{1}; out.meta.source = 'HFSS FFD';
        out.meta.hasFrequency = any(isfinite(freqs)); out.meta.isDep = nb > 1 || out.meta.hasFrequency;
        return
    otherwise, error('readFile:unsupported', 'Unsupported format: %s', ext);
end
out.raw = array2table(M(:, 1:6), 'VariableNames', names); out.blocks = {efieldTable(th, ph, Eth, Eph)};
end

function out = readGraspCut(fp, out)
%READGRASPCUT TICRA/GRASP .cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks.
out.meta.source = 'TICRA/GRASP CUT'; L = readlines(fp); L(strlength(strtrim(L)) == 0) = [];
th = {}; ph = {}; D = {}; i = 1; icomp = 1; icut = 1;
while i < numel(L)
    p = sscanf(L(i+1), '%f'); assert(numel(p) >= 7, 'parseCutFile:bad', 'Could not parse cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6); B = reshape(sscanf(strjoin(L(i+2:i+1+n), ' '), '%f'), 2*p(7), []).';
    th{end+1} = p(1) + (0:n-1).'*p(2); ph{end+1} = repmat(p(4), n, 1); D{end+1} = B(:, 1:4); i = i + 2 + n; %#ok<AGROW>
end
th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:});
if icut == 2, [th, ph] = deal(ph, th); end                          % ICUT=2: phi swept at constant theta
neg = th < 0; ph(neg) = ph(neg) + 180; th(neg) = -th(neg);           % negative theta = opposite meridian
if isscalar(unique(ph)), k = numel(th); th = repmat(th, 36, 1); ph = repelem((0:10:350).', k); D = repmat(D, 36, 1); end   % single cut → body of revolution
E1 = complex(D(:, 1), D(:, 2)); E2 = complex(D(:, 3), D(:, 4));
if icomp == 2, names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; [Eth, Eph] = circToLinear(E1, E2);
else, names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; [Eth, Eph] = deal(E1, E2); end
out.raw = array2table([th ph D], 'VariableNames', [{'Theta', 'Phi'} names]); out.blocks = {efieldTable(th, ph, Eth, Eph)};
end

function out = readExcelMatrix(fp, out)
%READEXCELMATRIX Template workbooks: sheet 1 = summary; component sheets are C3-origin matrices (row 2 = phi,
% column B = theta) holding dBi magnitude / degree phase for Etheta/Ephi and/or RHCP/LHCP.
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"];
lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'readFile:ExcelMatrixFormat', 'Unsupported workbook: no Etheta/Ephi or RHCP/LHCP component sheets found.');
req = [circ(1:4*hasC) lin(1:4*hasL)]; M = struct(); th = []; ph = [];
for s = req
    [t, p, D] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, s), 1)));
    if isempty(th), th = t; ph = p;
    else, assert(isequal(size(t), size(th)) && isequal(size(p), size(ph)) && max(abs(t - th)) < 1e-9 && max(abs(p - ph)) < 1e-9, ...
            'readFile:ExcelMatrixGrid', 'All component sheets must share one theta/phi grid.'); end
    M.(s) = D;
end
if hasL, Eth = magPhase(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = magPhase(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees);
else, [Eth, Eph] = circToLinear(magPhase(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), magPhase(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees)); end
[PG, TG] = meshgrid(ph, th); block = efieldTable(TG, PG, Eth, Eph); raw = block;
for s = req, raw.(s) = reshape(M.(s), [], 1); end
meta = readExcelSummary(fp, sheets(1)); names = ["Excel Matrix Format 1 (Eth/Eph)", "Excel Matrix Format 2 (Ercp/Elcp)", "Excel Matrix Format 3 (Ercp/Elcp + Eth/Eph)"];
meta.source = char(names(1 + hasC*(1 + hasL))); [meta.isGainOnly, meta.isCoverage, meta.isDep] = deal(false);
meta.hasFrequency = isfield(meta, 'frequencyMHz') && isfinite(meta.frequencyMHz);
out.freqs = NaN; if meta.hasFrequency, out.freqs = meta.frequencyMHz*1e6; end
out.raw = raw; out.blocks = {block}; out.meta = meta;
end

function [th, ph, D] = readMatrixSheet(fp, sheet)
C = readcell(fp, 'Sheet', char(sheet));                            % readcell keeps worksheet coordinates (readmatrix would trim)
assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'readFile:ExcelMatrixSheet', 'Sheet "%s" has no C3-origin matrix.', sheet);
isNum = @(x) isnumeric(x) && isscalar(x) && isfinite(x);
pm = cellfun(isNum, C(2, 3:end)); tm = cellfun(isNum, C(3:end, 2));
np = find(~pm, 1) - 1; if isempty(np), np = numel(pm); end, nt = find(~tm, 1) - 1; if isempty(nt), nt = numel(tm); end
assert(np > 0 && nt > 0 && ~any(pm(np+1:end)) && ~any(tm(nt+1:end)), 'readFile:ExcelMatrixAxis', 'Sheet "%s": theta/phi axes must be contiguous.', sheet);
ph = cell2mat(C(2, 3:2+np)).'; th = cell2mat(C(3:2+nt, 2)); cells = C(3:2+nt, 3:2+np);
assert(all(cellfun(isNum, cells), 'all'), 'readFile:ExcelMatrixSheet', 'Sheet "%s" contains non-numeric/missing samples.', sheet);
D = cell2mat(cells);
assert(all(diff(th) > 0) && all(diff(ph) > 0) && th(1) >= -1e-9 && th(end) <= 180 + 1e-9 && ph(1) >= -1e-9 && ph(end) < 360, ...
    'readFile:ExcelMatrixAxis', 'Sheet "%s": axes must be increasing within theta 0..180 and phi 0..360).', sheet);
end

function meta = readExcelSummary(fp, sheet)
%READEXCELSUMMARY Harvest "Label:" → value pairs (column B → first non-empty of C..E) from the summary sheet.
meta = struct();
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
for r = 1:size(C, 1)
    label = C{r, 2}; if ~(ischar(label) || isstring(label)) || strlength(strtrim(string(label))) == 0, continue; end
    vals = C(r, 3:min(end, 5)); vals = vals(~cellfun(@(x) isempty(x) || isa(x, 'missing'), vals)); if isempty(vals), continue; end
    key = lower(regexprep(char(label), '[^a-zA-Z0-9]+', '_')); meta.(matlab.lang.makeValidName(key)) = vals{1};
    if startsWith(regexprep(lower(strtrim(string(label))), '\s+', ' '), "pattern simulation freq"), meta.frequencyMHz = toDouble(vals{1}); end
end
end

function v = toDouble(x)
if isnumeric(x) && ~isempty(x), v = double(x(1)); elseif ischar(x) || isstring(x), v = str2double(x); else, v = NaN; end
end

function writeTable(T, fp)
if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
end

function writeUAN(U, fp)
%WRITEUAN Canonical XGTD UAN header followed by tab-delimited magnitude/phase rows.
header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
    min(U.Phi), max(U.Phi), gridStep(U.Phi), min(U.Theta), max(U.Theta), gridStep(U.Theta), max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan'));
writelines(header, fp);
writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
end

%% ====================================================================== math layer (pure)
function T = normalizePattern(T)
%NORMALIZEPATTERN Canonical sphere: Theta 0..180, Phi 0..360 with the seam duplicated at 360°, unique directions.
th = T.Theta; ph = T.Phi;
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, th = 90 - th;                              % elevation convention
    else, ph(th < 0) = ph(th < 0) + 180; th = abs(th); end                           % negative theta = opposite meridian
end
th = mod(th, 360); over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;
T.Theta = th; T.Phi = mod(ph, 360);
num = varfun(@isnumeric, T, 'OutputFormat', 'uniform'); T{:, num} = round(T{:, num}, 5);  % remove floating-point seam noise
T.Phi = mod(T.Phi, 360);
[~, k] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(k, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function [P, info] = calcPattern(S, prm, percentile, maxExcessDB)
%CALCPATTERN Canonical fields → processed table (gains, signed AR, PLF, link budget) + polarization summary.
info = struct('label', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
meta = S.Properties.UserData;
if isstruct(meta) && isfield(meta, 'isGainOnly') && meta.isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + prm.GainLoss_dB; end
    return
end
Eth = complex(S.Re_Eth, S.Im_Eth)*prm.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph)*prm.FieldScale;
Er = (Eth + 1i*Eph)/sqrt(2); El = (Eth - 1i*Eph)/sqrt(2);
[mT, mP, mR, mL] = deal(abs(Eth), abs(Eph), abs(Er), abs(El)); total = 10*log10(max(mT.^2 + mP.^2, eps));
% Dominant polarization from mean component power: orders co/cross pairs and drives the Auto Rx sense.
pw = [mean(mT.^2, 'omitnan') mean(mP.^2, 'omitnan') mean(mR.^2, 'omitnan') mean(mL.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.label = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif pw(1) >= pw(2), info.label = 'Linear (Vertical)'; else, info.label = 'Linear (Horizontal)'; end
% Signed axial ratio: + right-hand, − left-hand; equal circular components are the linear limit (−100 dB floor).
delta = mR - mL; sense = sign(delta); sense(~isfinite(delta)) = 0; ar = (mR + mL) ./ max(abs(delta), eps);
signedAR = min(20*log10(ar), 250) .* sense; signedAR(isfinite(delta) & abs(delta) <= eps*max(mR + mL, 1)) = -100;
% Polarization loss factor vs. an incident wave of axial ratio RxAR_dB (worst-case tilt, cos 2Δτ = −1).
switch prm.RxMode
    case "Auto", ws = 2*(info.pairs.Circular(1) == "E_RCP") - 1;
    case "RHCP", ws = 1;
    otherwise,   ws = -1;
end
ra = ar .* sense; ra(sense == 0) = 1e12; rw = ws*10^(prm.RxAR_dB/20);
plf = 10*log10(min(max(0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1)) ./ (2*(ra.^2 + 1)*(rw^2 + 1)), eps), 1));
eirp = prm.Pt_dBW + total; eirpW = 10.^(eirp/10);
P = table(S.Theta, S.Phi, total, signedAR, dB20(mR), dB20(mL), plf, total + plf, dB20(mT), dB20(mP), ...
    rad2deg(angle(Eth)), rad2deg(angle(Eph)), rad2deg(angle(Er)), rad2deg(angle(El)), eirp, eirpW/(4*pi*prm.R_m^2), sqrt(30*eirpW)/prm.R_m, ...
    'VariableNames', {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', 'PLF_dB', 'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', ...
    'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
P.Properties.UserData = meta;
end

function d = dB20(m), d = 20*log10(max(m, eps)); end

function R = resampleCanonical(S, step)
%RESAMPLECANONICAL Resample a canonical table onto a STEP° grid (Theta 0..180, Phi 0..360 incl. the seam).
% Primitive Re/Im fields are interpolated linearly; gain-only columns are interpolated in linear power.
names = string(S.Properties.VariableNames); cols = names(3:end); isField = all(ismember(["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"], cols));
th = S.Theta; ph = mod(S.Phi, 360); keep = find(isfinite(th) & isfinite(ph) & abs(S.Phi - 360) > 1e-9);   % drop the 360° copy
[~, u] = unique([th(keep) ph(keep)], 'rows', 'stable'); idx = keep(u); th = th(idx); ph = ph(idx);
tT = (0:step:180).'; tP = unique([(0:step:360).'; 360]); [QP, QT] = meshgrid(tP, tT);
R = table(QT(:), QP(:), 'VariableNames', {'Theta', 'Phi'});
uT = unique(th); uP = unique(ph); regular = numel(uT)*numel(uP) == numel(th);
if regular
    [PG, TG] = meshgrid(uP, uT); [~, it] = ismember(th, uT); [~, ip] = ismember(ph, uP); lin = sub2ind(size(PG), it, ip);
    PGx = [PG, PG(:, 1) + 360]; TGx = [TG, TG(:, 1)];                                         % periodic phi seam
end
for c = cols
    v = double(S.(c)(idx)); if ~isField, v = 10.^(v/10); end
    if regular
        G = nan(size(PG)); G(lin) = v; G(:, end+1) = G(:, 1); %#ok<AGROW>
        q = interp2(PGx, TGx, G, QP, QT, 'linear', NaN);
        miss = ~isfinite(q); if any(miss(:)), nn = interp2(PGx, TGx, G, QP, QT, 'nearest', NaN); q(miss) = nn(miss); end
    else
        F = scatteredInterpolant(ph, th, v, 'linear', 'nearest'); q = F(QP, QT);
    end
    if ~isField, q = 10*log10(max(q, realmin)); end
    R.(c) = q(:);
end
R.Properties.UserData = S.Properties.UserData;
end

function [ang, rows, fixed] = circleCut(thetaPhys, phi, isPhiCut, req, thetaSel)
%CIRCLECUT Rows and 0..360 angles of one great-circle cut. Phi cut: fixed theta (matched on THETASEL, default
% physical) sweeping phi. Theta cut: fixed phi sweeping theta, continued through the opposite meridian.
if nargin < 5, thetaSel = thetaPhys; end
if isPhiCut
    vals = unique(thetaSel); [~, k] = min(abs(vals - req)); fixed = vals(k);
    rows = find(abs(thetaSel - fixed) < 1e-9); ang = phi(rows);
else
    vals = unique(phi); [~, k] = min(abs(mod(vals - req + 180, 360) - 180)); fixed = vals(k);
    [~, j] = min(abs(mod(vals - fixed, 360) - 180));
    r1 = find(abs(phi - fixed) < 1e-9); r2 = find(abs(phi - vals(j)) < 1e-9 & thetaPhys > 1e-9 & thetaPhys < 180 - 1e-9);
    rows = [r1; r2]; ang = [thetaPhys(r1); 360 - thetaPhys(r2)];
end
[ang, k] = unique(mod(ang, 360)); rows = rows(k);
end

function [bw, lo, hi] = calcHPBW(ang, gainDB, peakGain, peakAngle)
%CALCHPBW Half-power beamwidth of a circular cut by linear interpolation of the -3 dB crossings (wrap-aware).
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(gainDB); ang = ang(ok); gainDB = gainDB(ok);
if numel(gainDB) < 3, return; end
if nargin < 3 || isempty(peakGain), [peakGain, k] = max(gainDB); peakAngle = ang(k); end
half = peakGain - 3; [rel, order] = sort(mod(ang - peakAngle + 180, 360) - 180); g = gainDB(order);
L = find(rel < 0 & g <= half, 1, 'last'); Rr = find(rel > 0 & g <= half, 1, 'first');
if isempty(L) || isempty(Rr) || L + 1 > numel(g) || Rr < 2, return; end
gl = g([L L+1]); gr = g([Rr Rr-1]); if diff(gl) == 0 || diff(gr) == 0, return; end
lc = rel(L) + diff(rel([L L+1]))*(half - gl(1))/diff(gl); rc = rel(Rr) + diff(rel([Rr Rr-1]))*(half - gr(1))/diff(gr);
lo = peakAngle + lc; hi = peakAngle + rc; bw = rc - lc;
end

function k = calcOrientation(gain, theta, phi, omega, axesDef, peak)
%CALCORIENTATION Index of the principal axis whose 45° cone collects the most peak-normalized energy.
if peak.wasAdjusted, gain(peak.outlierMask) = NaN; end
w = 10.^((gain - peak.value)/10) .* omega; w(~isfinite(w)) = 0;
A = [sind(axesDef.theta(:)).*cosd(axesDef.phi(:)), sind(axesDef.theta(:)).*sind(axesDef.phi(:)), cosd(axesDef.theta(:))];
S = [sind(theta).*cosd(phi), sind(theta).*sind(phi), cosd(theta)];
[~, k] = max(w.' * double(S*A.' >= cosd(45)));
end

function m = calcMetrics(T, gain, theta, phi, omega, peak, axesDef, k)
%CALCMETRICS Scalar figures of merit of the Total gain on physical (polar theta, 0..360 phi) coordinates.
i = peak.index; g = gain; if peak.wasAdjusted, g(peak.outlierMask) = NaN; end
Pint = sum(10.^(g/10) .* omega, 'omitnan');                                             % ∫ G dΩ
eff = 100*Pint/(4*pi); if eff < 0 || eff > 100, eff = NaN; end
[~, back] = min(cosd(theta)*cosd(theta(i)) + sind(theta)*sind(theta(i)).*cosd(phi - phi(i)));
ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(i); end
[eAng, eRows] = circleCut(theta, phi, false, axesDef.phi(k));                           % E-plane: boresight meridian
if axesDef.theta(k) == 90, [hAng, hRows] = circleCut(theta, phi, true, 90); else, [hAng, hRows] = circleCut(theta, phi, false, 90); end
m = struct('PeakGain_dB', peak.value, 'PeakTheta_deg', theta(i), 'PeakPhi_deg', phi(i), ...
    'HPBW_EPlane_deg', calcHPBW(eAng, gain(eRows)), 'HPBW_HPlane_deg', calcHPBW(hAng, gain(hRows)), ...
    'FrontBack_dB', peak.value - gain(back), 'PeakDirectivity_dB', 10*log10(max(4*pi*10^(peak.value/10)/max(Pint, eps), eps)), ...
    'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', ar);
end

function info = resolvePeak(values, percentile, maxExcessDB)
%RESOLVEPEAK Peak policy: accept the raw maximum unless it exceeds the P<percentile> level by more than
% MAXEXCESSDB; then the highest sample at/below that level is the effective peak (isolated spikes rejected).
values = double(values(:)); finite = isfinite(values);
info = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(values)), 'wasAdjusted', false);
if ~any(finite), return; end
[info.rawValue, info.rawIndex] = max(values, [], 'omitnan'); [info.value, info.index] = deal(info.rawValue, info.rawIndex);
level = pct(values(finite), percentile);
if info.rawValue > level + maxExcessDB
    outliers = finite & values > level; cand = values; cand(~finite | outliers) = -Inf;
    if any(finite & ~outliers), [info.value, info.index] = max(cand); info.outlierMask = outliers; info.wasAdjusted = true; end
end
end

function q = pct(v, p)
%PCT Percentile with the prctile convention (linear between sorted mid-points, clamped) — no toolbox needed.
v = sort(v(:)); n = numel(v); if n == 1, q = v; return; end
q = interp1(100*((1:n) - 0.5)/n, v, min(max(p, 50/n), 100 - 50/n));
end

function b = autoRange50(values, percentile, maxExcessDB)
%AUTORANGE50 50-dB window ending at the effective peak rounded up to the next 5 dB (display and threshold preset).
pk = resolvePeak(values, percentile, maxExcessDB);
if ~isfinite(pk.value), b = [-40 10]; return; end
b = clampRange(ceil(pk.value/5)*5 + [-50 0], [-250 100]);
end

function r = clampRange(v, bounds)
%CLAMPRANGE Sorted [lo hi] inside BOUNDS with at least 1 dB of span.
v = sort(double(v(:).')); if numel(v) < 2 || any(~isfinite(v)), r = bounds; return; end
r = [max(bounds(1), v(1)), min(bounds(2), v(2))];
if diff(r) < 1, r(2) = min(bounds(2), r(1) + 1); r(1) = max(bounds(1), r(2) - 1); end
end

function t = ticksFor(lim, step)
%TICKSFOR Ticks at multiples of STEP inside LIM, always including both limits (empty when unusable).
t = []; if ~isfinite(step) || step <= 0 || diff(lim) <= 0, return; end
t = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)]); if numel(t) > 60, t = []; end
end

function w = solidWeights(theta, phi, seamPhi)
%SOLIDWEIGHTS Exact solid angle (sr) of each sample's grid cell; the duplicated seam meridian SEAMPHI weighs 0.
dt = gridStep(theta); dp = gridStep(mod(phi, 360)); if ~isfinite(dt), dt = 180; end, if ~isfinite(dp), dp = 360; end
w = (cosd(max(theta - dt/2, 0)) - cosd(min(theta + dt/2, 180))) * deg2rad(dp);
if nargin < 3, seamPhi = 360; end
w(abs(phi - seamPhi) < 1e-9) = 0;
end

function coverage = coverageCCDF(gain, regionMask, thresholds, omega)
%COVERAGECCDF Coverage(T) [%] = 100 · Σ I(G_i > T)·Ω_i / Σ Ω_i over the region (all thresholds at once).
ok = regionMask(:) & isfinite(gain(:)) & isfinite(omega(:)) & omega(:) >= 0; g = gain(ok); w = omega(ok);
coverage = zeros(size(thresholds(:)));
if isempty(g) || sum(w) <= 0, return; end
coverage = 100*(w.' * double(g > thresholds(:).')).' / sum(w);
end

function step = gridStep(values)
%GRIDSTEP Smallest positive spacing between distinct finite values (NaN when undefined).
d = diff(unique(values(isfinite(values)))); d = d(d > 1e-9); if isempty(d), step = NaN; else, step = min(d); end
end

function [g, col] = chooseGain(T, col)
%CHOOSEGAIN Requested column, else E_Total_dB, else the first data column.
vars = T.Properties.VariableNames; c = [string(col) "E_Total_dB"]; k = find(ismember(c, vars), 1);
if isempty(k), col = vars{3}; else, col = char(c(k)); end, g = T.(col);
end

function [cols, labels] = componentMap(T)
%COMPONENTMAP Displayable component columns with labels (gain-only tables expose every column verbatim).
cols = string(T.Properties.VariableNames(3:end)); labels = cols; ud = T.Properties.UserData;
if isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly, return; end
known = ["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "AR_dB", "Gain_PolCorrected_dB"];
names = ["Total Gain", "Etheta Gain", "Ephi Gain", "RHCP Gain", "LHCP Gain", "Axial Ratio", "Polarized Gain"];
keep = ismember(known, cols); cols = known(keep); labels = names(keep);
end

function c = preferredComponent(prev, cols)
c = string(prev);
if ~any(cols == c), if any(cols == "E_Total_dB"), c = "E_Total_dB"; else, c = cols(1); end, end
end

function tf = isARName(name)
%ISARNAME Axial-ratio semantics independent of spelling: AR, AR_dB, "AR dB", Axial Ratio, Axial_Ratio.
key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', ''); tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
end

function s = fmtNum(v, precision)
%FMTNUM 'n/a' for non-finite values; fixed decimals when PRECISION is given, otherwise up to two trimmed decimals.
if ~isscalar(v) || ~isfinite(v), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); if strcmp(s, '-0'), s = '0'; end, else, s = sprintf('%.*f', precision, v); end
end