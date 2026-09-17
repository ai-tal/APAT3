classdef APAT_v3_M8_17 < matlab.apps.AppBase %1688-lines % ERROR: "Unrecognized method, property, or field 'NodeData' for class 'matlab.graphics.GraphicsPlaceholder'." "Error in APAT_v3_M8_17/covTarget (line 799: if isstruct(k.NodeData) && strcmp(k.NodeData.kind, 'pattern'), n = k; return; end)" 
% APAT v3 M8 — Antenna Pattern Analyzer Tool (concise re-architecture of M7.110_5)
%
% DATA FLOW (one direction, one authoritative table per stage)
%   file ──readPattern──▶ src{rawTbl, blocks, freqs, meta}
%        ──normalizePattern──▶ stdTbl   canonical sphere: Theta∈[0,180], Phi∈[0,360] (closed seam), complex E or gain
%        ──[resampleTo1deg]──calcPattern──▶ patTbl   PHYSICAL coordinates + every derived column (gain, AR, PLF, EIRP…)
%        ──▶ presentation layer only: gridOf()/cutData()/displayTable() map to the selected DISPLAY convention
%             (θ→elevation, φ→signed) at render time.  Metrics, coverage, POB and solid angles never see display angles.
%
% ANNOTATIONS are plain graphics objects identified by Tag (APAT_Surface, APAT_POB, APAT_HPBW, APAT_Overlay):
%   redraw = delete-by-tag + recreate.  No handle registries, no per-tab bookkeeping.
%
% All widgets live in app.ui (struct) — see build().  Every callback is wrapped by cb() so errors surface in-app.

    properties (Access = public)
        UIFigure matlab.ui.Figure
        ui struct = struct()                    % every widget, created in build()
    end

    properties (Access = private)
        file struct = struct('path', '', 'name', '', 'base', '', 'folder', '')
        src struct = struct()                   % readPattern output of the active file
        stdTbl table                            % canonical source (block k)
        patTbl table                            % processed pattern, physical coordinates
        info struct = struct()                  % calcPattern summary: POB, POBth, POBph, pol, pairs, peak
        metrics struct = struct()               % calcMetrics output
        boresight double = 1                    % index into Axes6
        dOmega double = []                      % solid-angle weight of every patTbl row
        gridCache struct = struct()             % display grids per component (see gridOf())
        fullLim double = [-40 10]               % active full-pattern color range
        cutLim double = [-40 10]                % active cut range
        gainLim double = [-40 10]               % remembered gain range while AR is displayed
        defaults struct = struct()              % startup parameter values
        covRunID double = 0
        covPreset string = ""                   % key of the last automatic threshold preset
        covThrInit logical = false
        covXInit logical = false
        statusTimer = []
        opDialog = []
        isClosing logical = false
    end

    properties (Constant, Access = private)
        Axes6 = struct('labels', {{'+Z', '-Z', '+X', '-X', '+Y', '-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        Hidden = {'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'}
        PeakPct = 99.99                         % peak policy: percentile …
        PeakExcess = 6                          % … and maximum excess (dB) of the raw maximum above it
        Range = [-250 100]                      % global dB range of every slider/spinner
        Version = 'APAT v3 M8'
    end

    %% ───────────────────────────── lifecycle ─────────────────────────────
    methods (Access = public)
        function app = APAT_v3_M8_17()
            app.build();
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @(a) a.startup());
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true; app.stopTimer();
            if ~isempty(app.opDialog) && isvalid(app.opDialog), delete(app.opDialog); end
            if isgraphics(app.UIFigure), delete(app.UIFigure); end
        end

        function r = selfTest(app)
            %SELFTEST Deterministic checks of the numerical kernel (no files, no rendering). Errors on failure.
            [ph, th] = meshgrid(0:30:360, 0:30:180);
            T = table(th(:), ph(:), 10*cosd(th(:)).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            w = solidWeights(T.Theta, T.Phi);
            r.solidAngle = abs(sum(w) - 4*pi) < 1e-9;
            pk = resolvePeak(T.E_Total_dB, app.PeakPct, app.PeakExcess);
            r.orientation = calcOrientation(T, T.E_Total_dB, w, pk, app.Axes6) == 1;        % +Z
            [p2, t2] = meshgrid(0:2:358, 0:2:180);
            T2 = table(t2(:), p2(:), 12*cosd(t2(:)).^2 - 0.5*sind(p2(:)).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            T2.Properties.UserData = struct('isGainOnly', false);
            R = resampleTo1deg(T2); nat = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0 & R.Phi < 360;
            err = max(abs(R.E_Total_dB(nat) - (12*cosd(R.Theta(nat)).^2 - 0.5*sind(R.Phi(nat)).^2)));
            r.resample = height(R) == 181*361 && err < 1e-10;
            r.range = isequal(displayRange([3.2; -100], app.PeakPct, app.PeakExcess), [-45 5]);
            g = repmat(0.02, 1e5, 1); g(1) = 10.02; sp = resolvePeak(g, app.PeakPct, app.PeakExcess);
            r.spike = sp.adjusted && abs(sp.value - 0.02) < 1e-12 && sp.rawIndex == 1;
            c = cutRows(T, "Theta", 0);
            r.cut = numel(c.rows) == 12 && abs(c.angle(end) - 330) < 1e-9;
            a = (0:359).'; gdb = 20*log10(max(abs(cosd(a)), 1e-6)); gdb(a > 90 & a < 270) = -60;
            r.hpbw = abs(calcHPBW(a, gdb) - 90) < 0.5;
            r.pass = all(structfun(@(x) x, r));
            if ~r.pass
                f = fieldnames(r); error('APAT:SelfTest', 'Self-test failed: %s', strjoin(f(~structfun(@(x) x, r)), ', '));
            end
        end
    end

    %% ───────────────────────────── pipeline ─────────────────────────────
    methods (Access = private)
        function startup(app)
            u = app.ui;
            app.defaults = struct('loss', u.loss.Value, 'rx', u.rx.Value, 'rw', u.rw.Value, 'pt', u.pt.Value, ...
                'ptU', u.ptU.Value, 'r', u.r.Value, 'rU', u.rU.Value);
            for c = {u.axCtr, u.axCutR}, enableDefaultInteractivity(c{1}); c{1}.Interactions = [zoomInteraction dataTipInteraction]; end
            for c = {u.axSph, u.axPol, u.axRect}, enableDefaultInteractivity(c{1}); c{1}.Interactions = [rotateInteraction dataTipInteraction]; end
            for c = app.allAxes()
                ax = c{1}; m = uicontextmenu(app.UIFigure);
                uimenu(m, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ~) delete(findall(ax, 'Type', 'datatip')));
                ax.ContextMenu = m;
            end
            app.setRange("full", app.fullLim, false); app.setRange("cut", app.cutLim, false);
            app.covUI(); app.UIFigure.Visible = 'on';
        end

        function onLoad(app)
            fp = strtrim(app.ui.path.Value);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.file.path)
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / Coverage files'}, ...
                    'Select an antenna pattern file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            app.ui.path.Value = fp;
            c = app.busy('Loading Data', 'Reading file...', true); %#ok<NASGU>
            src_ = readPattern(fp, app.textFormatFor(fp, app.ui.fmtLabel, app.ui.fmt)); app.checkCancelled();
            if src_.meta.isCoverage                       % route coverage-result files without touching Main state
                app.ui.path.Value = app.file.path; set([app.ui.fmtLabel app.ui.fmt], 'Visible', 'off');
                app.ui.tabs.SelectedTab = app.ui.covTab; app.ui.covPath.Value = fp;
                app.covLoadResults(fp, src_.rawTbl); return
            end
            app.setSource(src_, fp); app.process(false);
        end

        function onProcess(app)
            if isempty(app.stdTbl), uialert(app.UIFigure, 'Load a pattern file first.', 'Process', 'Icon', 'warning'); return; end
            if app.isGeneric(app.file.path)               % re-interpret the cached generic table with the selected format
                src_ = readPattern(app.file.path, app.ui.fmt.Value, app.src.rawTbl);
                assert(~src_.meta.isCoverage, 'The selected format identifies a coverage-results file.');
                app.setSource(src_, app.file.path);
            end
            app.process(true);
            app.setStatus(app.ui.status, ['Re-processed <b>' app.file.name '</b> with the current parameters ✅'], true);
        end

        function setSource(app, src_, fp)
            %SETSOURCE Adopt a parsed file: file info, frequency-block selector, block 1.
            app.src = src_; [folder, base, ext] = fileparts(fp);
            app.file = struct('path', fp, 'name', [base ext], 'base', base, 'folder', folder);
            u = app.ui; n = numel(src_.blocks);
            if src_.meta.isDep
                items = compose('Pattern %d: %.4g GHz', [(1:n).', src_.freqs(:)/1e9]); bad = isnan(src_.freqs(:));
                items(bad) = compose('Pattern %d', find(bad));
                u.ffd.Items = items; u.ffd.ItemsData = 1:n; u.ffd.Value = 1;
            end
            set([u.ffdLabel u.ffd], 'Visible', src_.meta.isDep);
            u.basis.UserData = true;                      % cut basis follows the detected polarization until the user picks one
            app.useBlock(1);
        end

        function useBlock(app, k)
            S = normalizePattern(app.src.blocks{k}); S.Properties.UserData = app.src.meta; app.stdTbl = S;
            if app.src.meta.isDep, app.src.rawTbl = app.src.blocks{k}; end
        end

        function process(app, keepStep)
            %PROCESS The whole pipeline: [1° resample] → calcPattern → orientation/metrics → controls → tables → plots.
            if isempty(app.stdTbl), return; end
            c = app.busy('Processing', 'Computing pattern...', true); %#ok<NASGU>
            S = app.stdTbl; u = app.ui;
            dT = gridStep(S.Theta); dP = gridStep(S.Phi(S.Phi < 360));
            nat = max([dT dP], [], 'omitnan'); if isnan(nat), nat = 1; end
            one = ['STEP: 1' char(176)]; native = sprintf('STEP: %g%c', nat, char(176));
            wantOne = keepStep && strcmp(u.step.Value, one); nonCanon = abs(dT - 1) > 1e-9 || abs(dP - 1) > 1e-9;
            u.step.Items = {native, one}; u.step.Value = native; if wantOne && nonCanon, u.step.Value = one; end
            set(u.step, 'Visible', nonCanon, 'Enable', nonCanon);
            if wantOne && nonCanon
                if dT < 1 && dP < 1, S = S(mod(S.Theta, 1) == 0 & mod(S.Phi, 1) == 0, :);   % sub-degree grid: decimate exactly
                else, S = resampleTo1deg(S); end
            end
            [app.patTbl, app.info] = calcPattern(S, app.getParam(), app.PeakPct, app.PeakExcess); app.checkCancelled();
            T = app.patTbl; g = app.gainOf(T); app.dOmega = solidWeights(T.Theta, T.Phi); app.gridCache = struct();
            app.boresight = calcOrientation(T, g, app.dOmega, app.info.peak, app.Axes6);
            app.metrics = calcMetrics(T, g, app.dOmega, app.info.peak, app.boresight, app.Axes6);
            hasE = ~app.isGainOnly();
            if hasE && isequal(u.basis.UserData, true)
                if startsWith(app.info.pol, 'Linear'), u.basis.Value = 'Linear'; else, u.basis.Value = 'Circular'; end
            end
            prev = u.comp.Value; [cols, labels] = componentMap(T);
            u.comp.Items = labels; u.comp.ItemsData = cols; u.comp.Value = pickComponent(prev, cols);
            app.gainLim = displayRange(g, app.PeakPct, app.PeakExcess);
            lim = app.gainLim; if app.isAR(), lim = [-30 30]; end
            app.setRange("full", lim, false, false); app.setRange("cut", app.gainLim, false, false);
            app.applyPlane(); app.updateTables(); app.updateMetadata();
            app.plotCut(); drawnow limitrate; app.renderAll(); app.checkCancelled();
            set([u.fullPanel u.cutPanel u.ctrlPanel u.dataTabs u.outFilter u.export u.covBtn], 'Visible', 'on');
            u.exportUAN.Visible = hasE; u.eGrid.Visible = hasE; u.basis.Enable = hasE;
            s = sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>θ=%s°, φ=%s°</b>)', app.file.name, ...
                fmt(app.info.POB, 2), fmt(app.info.POBth), fmt(app.info.POBph));
            if hasE, s = sprintf('%s | Polarization <b>%s</b>', s, app.info.pol); end
            app.setStatus(u.status, s);
        end

        function p = getParam(app)
            u = app.ui; p = struct('Loss_dB', u.loss.Value, 'RxMode', string(u.rx.Value), 'RxAR_dB', u.rw.Value);
            switch u.ptU.Value
                case 'dBm',   p.Pt_dBW = u.pt.Value - 30;
                case 'Watts', p.Pt_dBW = 10*log10(max(u.pt.Value, eps));
                otherwise,    p.Pt_dBW = u.pt.Value;
            end
            p.R_m = max(u.r.Value, 1e-12); if strcmp(u.rU.Value, 'km'), p.R_m = 1000*p.R_m; end
        end

        %% ── small state queries
        function tf = isGainOnly(app), tf = isfield(app.src, 'meta') && app.src.meta.isGainOnly; end
        function tf = isElev(app),     tf = strcmp(app.ui.thSpan.Value, '-90° to 90°'); end
        function tf = isSigned(app),   tf = strcmp(app.ui.phiSpan.Value, '-180° to 180°'); end
        function s = comp(app),        s = app.ui.comp.Value; end
        function s = thetaLabel(app),  if app.isElev(), s = 'Elevation'; else, s = 'Theta'; end, end
        function tf = isGeneric(~, fp), [~, ~, e] = fileparts(fp); tf = any(strcmpi(e, {'.csv', '.txt', '.dat'})); end
        function tf = isAR(app)
            k = regexprep(lower(app.comp()), '[^a-z0-9]', '');
            tf = strcmp(k, 'ar') || startsWith(k, 'ardb') || startsWith(k, 'axialratio');
        end
        function s = compLabel(app)
            dd = app.ui.comp; i = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(i), s = strrep(dd.Value, '_', ' '); else, s = dd.Items{i}; end
        end
        function g = gainOf(~, T)
            if ismember('E_Total_dB', T.Properties.VariableNames), g = T.E_Total_dB; else, g = T{:, 3}; end
        end
        function c = allAxes(app)
            u = app.ui; c = {u.axCtr, u.axCir, u.axSph, u.axPol, u.axRect, u.axCutP, u.axCutR};
        end
        function f = textFormatFor(app, fp, label, dd)
            %TEXTFORMATFOR Generic text files expose the format selector (reset to gain); other types are self-describing.
            generic = app.isGeneric(fp); set([label dd], 'Visible', generic);
            if generic, dd.Value = 'gain'; f = "gain"; else, f = "auto"; end
        end

        %% ── view-state callbacks
        function onComponent(app)
            if app.isAR(), app.setRange("full", [-30 30], false, false); else, app.setRange("full", app.gainLim, false, false); end
            if app.isGainOnly(), app.plotCut(); end
            app.renderAll();
        end

        function onSpanChanged(app, which)
            if isempty(app.patTbl), return; end
            app.gridCache = struct();
            if which == "theta" && strcmp(app.ui.cutType.Value, 'Phi')
                app.ui.cutVal.Limits = [-360 360]; app.ui.cutVal.Value = 90 - app.ui.cutVal.Value;
            end
            app.updateCutControls(); app.updateTables(); app.plotCut(); app.renderAll();
        end

        function onCutChanged(app, typeChanged)
            if isempty(app.patTbl), return; end
            if nargin > 1 && typeChanged, app.updateCutControls(); end
            u = app.ui; u.hpbwBounds.Visible = u.hpbwBtn.Value; if ~u.hpbwBtn.Value, u.hpbwBounds.Value = false; end
            app.plotCut(); app.overlayCut();
        end

        function onBasis(app)
            app.ui.basis.UserData = false; if isempty(app.patTbl), return; end
            app.updateMetadata(); app.onCutChanged();
        end

        function onPlane(app)
            if isempty(app.patTbl), return; end
            app.applyPlane(); app.onCutChanged();
        end

        function onPOB(app)
            if isempty(app.patTbl), return; end
            app.annotatePOB(app.fullAxes()); app.plotCut();
        end

        function onView3D(app)
            for c = {app.ui.axSph, app.ui.axPol, app.ui.axRect}, app.applyView(c{1}); end
        end

        function onFFD(app)
            app.useBlock(app.ui.ffd.Value); app.ui.basis.UserData = true; app.process(true);
            it = string(app.ui.ffd.Items); app.setStatus(app.ui.status, sprintf('Switched to %s.', it(app.ui.ffd.Value)), true);
        end

        function onResetParams(app)
            d = app.defaults; u = app.ui;
            [u.loss.Value, u.rx.Value, u.rw.Value, u.pt.Value, u.ptU.Value, u.r.Value, u.rU.Value] = ...
                deal(d.loss, d.rx, d.rw, d.pt, d.ptU, d.r, d.rU);
            if ~isempty(app.stdTbl), app.process(true); end
        end

        function onFmtChanged(app)
            if strcmp(strtrim(app.ui.path.Value), app.file.path) && app.isGeneric(app.file.path)
                app.ui.basis.UserData = true; app.onProcess();
            end
        end

        function applyPlane(app)
            %APPLYPLANE E-plane = great circle through the boresight axis; H-plane = the orthogonal one
            % (for transverse ±X/±Y axes the H-plane is the θ = 90° ring).
            A = app.Axes6; k = app.boresight; u = app.ui;
            if startsWith(u.ehSwitch.Value, 'E'),  type = 'Theta'; val = A.phi(k);
            elseif A.theta(k) == 90,                type = 'Phi';   val = 90; if app.isElev(), val = 0; end
            else,                                   type = 'Theta'; val = mod(A.phi(k) + 90, 360);
            end
            u.cutType.Value = type; u.cutVal.Limits = [-360 360]; u.cutVal.Value = val; app.updateCutControls();
        end

        function updateCutControls(app)
            %UPDATECUTCONTROLS Spinner limits/step follow the available cut positions (display units), snapping to the nearest.
            T = app.patTbl; sp = app.ui.cutVal;
            if strcmp(app.ui.cutType.Value, 'Phi'), v = unique(T.Theta); if app.isElev(), v = 90 - v; end
            else, v = unique(T.Phi(T.Phi < 360)); end
            v = sort(v); if numel(v) > 1, sp.Limits = [min(v) max(v)]; sp.Step = min(diff(v)); else, sp.Limits = [-360 360]; end
            [~, k] = min(abs(v - sp.Value)); sp.Value = v(k);
        end

        %% ───────────────────────────── ranges & theme ─────────────────────────────
        function lim = clamp(app, lim)
            %CLAMP Sorted [min max] inside the global range with at least 1 dB of spread.
            lim = sort(double(lim(:).')); lim = [max(app.Range(1), lim(1)), min(app.Range(2), lim(2))];
            if diff(lim) < 1, lim(2) = min(app.Range(2), lim(1) + 1); lim(1) = lim(2) - 1; end
        end

        function setRange(app, scope, lim, fromSlider, apply)
            %SETRANGE Push one [min max] to every slider/spinner of a scope ("full" | "cut") and apply it to the plots.
            % Spinner edits re-centre the slider travel (±20 dB window); slider drags keep their travel.
            if nargin < 5, apply = true; end
            lim = app.clamp(lim); u = app.ui;
            if scope == "full"
                sl = u.fullSliders; lo = u.fullMin; hi = u.fullMax; app.fullLim = lim; if ~app.isAR(), app.gainLim = lim; end
                u.cmin.Value = lim(1); u.cmax.Value = lim(2);
            else
                sl = u.cutSlider; lo = u.cutMin; hi = u.cutMax; app.cutLim = lim;
            end
            if fromSlider, set(sl, 'Value', lim);
            else, set(sl, 'Limits', app.Range, 'Value', lim); set(sl, 'Limits', [max(app.Range(1), lim(1) - 20), min(app.Range(2), lim(2) + 20)]); end
            set(lo, 'Limits', [app.Range(1), lim(2) - 1], 'Value', lim(1)); set(hi, 'Limits', [lim(1) + 1, app.Range(2)], 'Value', lim(2));
            if ~apply || isempty(app.patTbl), return; end
            if scope == "full", app.applyFullRange();
            else, set(u.axCutP, 'RLim', lim); set(u.axCutR, 'YLim', lim); end
        end

        function onRangeUI(app, scope, mode, e)
            %ONRANGEUI Slider (mode 0) or min/max spinner (mode 1/2) edit of the full-pattern or cut range.
            if scope == "full", lim = app.fullLim; else, lim = app.cutLim; end
            if mode == 0, lim = e.Value; else, lim(mode) = e.Value; end
            app.setRange(scope, lim, mode == 0);
        end

        function applyColorbar(app)
            lim = [app.ui.cmin.Value, app.ui.cmax.Value]; app.setRange("full", lim, false); app.setRange("cut", lim, false);
        end

        function [lim, map] = theme(app)
            %THEME Active color scale; signed axial ratio uses a blue-white-red map centred on 0 dB, gain uses jet.
            lim = app.fullLim;
            if app.isAR(), map = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); else, map = jet(256); end
        end

        function paint(app, ax, lim, map)
            clim(ax, lim); colormap(ax, map); cbar = colorbar(ax);
            t = niceTicks(lim, app.ui.cstep.Value); if ~isempty(t), cbar.Ticks = t; end
        end

        function applyFullRange(app)
            %APPLYFULLRANGE Re-scale colour on every full-pattern plot; the 3D polar surface is re-drawn (its shape depends on the range).
            if isempty(app.patTbl), return; end
            [lim, map] = app.theme(); u = app.ui;
            for c = {u.axCtr, u.axCir, u.axSph, u.axRect}, app.paint(c{1}, lim, map); end
            app.zRange(u.axRect, lim); app.draw3D("polar"); drawnow limitrate; app.annotatePOB({u.axPol});
        end

        function zRange(app, ax, lim)
            zlim(ax, lim); t = niceTicks(lim, app.ui.cstep.Value); if ~isempty(t), ax.ZTick = t; end
        end

        %% ───────────────────────────── full-pattern rendering ─────────────────────────────
        function c = fullAxes(app), u = app.ui; c = {u.axCtr, u.axCir, u.axSph, u.axPol, u.axRect}; end

        function G = gridOf(app, col)
            %GRIDOF Display-ordered θ×φ matrices of one component plus the matching PHYSICAL angles (cached per component).
            key = matlab.lang.makeValidName(col);
            if isfield(app.gridCache, key), G = app.gridCache.(key); return; end
            T = app.patTbl; th = unique(T.Theta); ph = unique(T.Phi);
            [~, it] = ismember(T.Theta, th); [~, ip] = ismember(T.Phi, ph);
            Z = nan(numel(th), numel(ph)); Z(sub2ind(size(Z), it, ip)) = T.(col);
            [phP, thP] = meshgrid(ph, th); phD = ph; thD = th;
            if app.isSigned()                            % 0..360 → −180..180: drop the 360 seam, rotate, re-close at ±180
                keep = ph < 360; phD = ph(keep); Z = Z(:, keep); phP = phP(:, keep);
                phD(phD > 180) = phD(phD > 180) - 360; [phD, o] = sort(phD); Z = Z(:, o); phP = phP(:, o);
                if phD(end) == 180, phD = [-180; phD]; Z = [Z(:, end) Z]; phP = [phP(:, end) phP]; end
            end
            if app.isElev(), thD = flipud(90 - th); Z = flipud(Z); thP = flipud(thP); phP = flipud(phP); end
            [phM, thM] = meshgrid(phD, thD);
            G = struct('th', thM, 'ph', phM, 'Z', Z, 'thP', thP, 'phP', phP); app.gridCache.(key) = G;
        end

        function renderAll(app)
            if isempty(app.patTbl), return; end
            app.drawContour(); app.drawFisheye(); app.draw3D("sphere"); app.draw3D("polar"); app.drawRect3();
            drawnow limitrate; app.annotatePOB(app.fullAxes());
        end

        function tipTemplate(app, h, G)
            %TIPTEMPLATE Common θ/φ/value DataTip rows for a rendered surface (+ the axes context menu).
            lab = strrep(char(app.compLabel()), '_', '\_');
            try
                h.DataTipTemplate.DataTipRows = [dataTipTextRow(app.thetaLabel(), G.th, '%.3g°'); ...
                    dataTipTextRow('Phi', G.ph, '%.3g°'); dataTipTextRow(lab, G.Z, '%.3g dB')];
            catch
            end
            h.ContextMenu = h.Parent.ContextMenu;
        end

        function angularAxes(app, ax, dPhi, dTh)
            %ANGULARAXES Rectangular φ/θ axes in the active display convention.
            if app.isSigned(), xl = [-180 180]; else, xl = [0 360]; end
            if app.isElev(), yl = [-90 90]; yd = 'normal'; else, yl = [0 180]; yd = 'reverse'; end
            set(ax, 'XLim', xl, 'YLim', yl, 'YDir', yd, 'XTick', xl(1):dPhi:xl(2), 'YTick', yl(1):dTh:yl(2), 'Box', 'on', 'Layer', 'top');
            xlabel(ax, 'Phi (degree)'); ylabel(ax, [app.thetaLabel() ' (degree)']);
        end

        function polarTicks(app, ax)
            a = 0:30:330; lab = a; if app.isSigned(), lab(lab > 180) = lab(lab > 180) - 360; end
            set(ax, 'ThetaTick', a, 'ThetaTickLabel', compose('%d°', lab));
        end

        function drawContour(app)
            ax = app.ui.axCtr; G = app.gridOf(app.comp()); cla(ax);
            s = pcolor(ax, G.ph, G.th, G.Z); set(s, 'FaceColor', 'interp', 'LineStyle', 'none', 'Tag', 'APAT_Surface', 'UserData', G);
            [lim, map] = app.theme(); app.paint(ax, lim, map); app.angularAxes(ax, 30, 15); daspect(ax, [1 1 1]);
            title(ax, app.compLabel(), 'Interpreter', 'none'); app.tipTemplate(s, G);
        end

        function drawFisheye(app)
            %DRAWFISHEYE Polar map: radius = physical θ (0° at centre), angle = φ.
            ax = app.ui.axCir; G = app.gridOf(app.comp()); cla(ax);
            s = surface(ax, deg2rad(G.phP), G.thP, zeros(size(G.Z)), G.Z, 'EdgeColor', 'none', 'Tag', 'APAT_Surface', 'UserData', G);
            [lim, map] = app.theme(); app.paint(ax, lim, map);
            r = 0:30:180; if app.isElev(), r = 90 - r; end
            set(ax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', r));
            app.polarTicks(ax);
            title(ax, sprintf('%s  |  r = %s, angle = φ', app.compLabel(), lower(app.thetaLabel())), 'Interpreter', 'none', 'FontSize', 9);
            app.tipTemplate(s, G);
        end

        function r = polarRadius(~, v, lim, ref)
            %POLARRADIUS Value above the range floor, normalised so the reference (surface) maximum is 1.
            if nargin < 4, ref = v; end
            n = @(x) max(x - lim(1), 0) / max(lim(2) - lim(1), eps);
            r = n(v) / max([n(ref(:)); eps], [], 'omitnan');
        end

        function draw3D(app, kind)
            %DRAW3D "sphere": unit sphere coloured by value.  "polar": radius ∝ value above the range floor.
            if kind == "sphere", ax = app.ui.axSph; else, ax = app.ui.axPol; end
            G = app.gridOf(app.comp()); [lim, map] = app.theme();
            r = ones(size(G.Z)); if kind == "polar", r = app.polarRadius(G.Z, lim); end
            cla(ax); hold(ax, 'on');
            s = surf(ax, r.*sind(G.thP).*cosd(G.phP), r.*sind(G.thP).*sind(G.phP), r.*cosd(G.thP), G.Z, ...
                'EdgeColor', 'none', 'Tag', 'APAT_Surface', 'UserData', G);
            app.paint(ax, lim, map);
            set(ax, 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], ...
                'PlotBoxAspectRatio', [1 1 1], 'Projection', 'orthographic');
            axis(ax, 'off'); app.drawXYZ(ax); app.applyView(ax);
            title(ax, sprintf('%s  |  θ: %s  |  φ: %s', app.compLabel(), app.ui.thSpan.Value, app.ui.phiSpan.Value), 'Interpreter', 'none');
            app.tipTemplate(s, G); hold(ax, 'off'); app.overlayCut({ax});
        end

        function drawXYZ(~, ax)
            col = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; lab = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            for k = 1:3
                d = 1.35*double(1:3 == k);
                quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', col{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12*d(1), 1.12*d(2), 1.12*d(3), lab{k}, 'Color', col{k}, 'FontWeight', 'bold');
            end
        end

        function applyView(app, ax)
            v = struct('iso', [135 25], 'top', [0 90], 'bottom', [0 -90], 'right', [90 0], 'left', [-90 0], 'front', [0 0], 'back', [180 0]);
            key = app.ui.view3D.Value; a = v.(key); if strcmp(key, 'iso') && isequal(ax, app.ui.axRect), a = [-35 35]; end
            view(ax, a(1), a(2)); if any(strcmp(key, {'top', 'bottom'})), camup(ax, [0 1 0]); else, camup(ax, [0 0 1]); end
        end

        function drawRect3(app)
            ax = app.ui.axRect; G = app.gridOf(app.comp()); [lim, map] = app.theme(); cla(ax);
            s = surf(ax, G.ph, G.th, G.Z, 'EdgeColor', 'none', 'Tag', 'APAT_Surface', 'UserData', G);
            app.paint(ax, lim, map); app.angularAxes(ax, 60, 30); app.zRange(ax, lim);
            zlabel(ax, [char(app.compLabel()) ' (dB)'], 'Interpreter', 'none'); grid(ax, 'on'); app.applyView(ax);
            title(ax, app.compLabel(), 'Interpreter', 'none'); app.tipTemplate(s, G);
        end

        function overlayCut(app, axList)
            %OVERLAYCUT Draw the active cut on the 3D surfaces as a black curve.
            % Uses the LINE primitive (never resets axes) — the M7 plot3 call wiped the surface/view when toggled.
            % On the polar surface the curve uses the SAME radius normalisation as the surface, so it sits on it.
            if nargin < 2, axList = {app.ui.axSph, app.ui.axPol}; end
            for c = axList, delete(findall(c{1}, 'Tag', 'APAT_Overlay')); end
            if ~app.ui.overlay.Value || isempty(app.patTbl), return; end
            cut = app.cutData(); lim = app.theme();
            for c = axList
                ax = c{1}; r = 1.02;
                if isequal(ax, app.ui.axPol)
                    s = findobj(ax, 'Tag', 'APAT_Surface'); if isempty(s), continue; end
                    r = 1.01*app.polarRadius(cut.vals(:, 1), lim, s.UserData.Z);
                end
                line(ax, r.*sind(cut.thP).*cosd(cut.phP), r.*sind(cut.thP).*sind(cut.phP), r.*cosd(cut.thP), ...
                    'Color', 'k', 'LineWidth', 1.6, 'Tag', 'APAT_Overlay');
            end
        end

        function annotatePOB(app, axList)
            %ANNOTATEPOB Marker + pinned DataTip at the total-gain peak direction on each full-pattern axes.
            for c = axList, delete(findall(c{1}, 'Tag', 'APAT_POB')); end
            if ~app.ui.pob.Value || ~isfield(app.info, 'POBth') || ~isfinite(app.info.POBth), return; end
            for c = axList
                ax = c{1}; s = findobj(ax, 'Tag', 'APAT_Surface'); if isempty(s), continue; end
                G = s.UserData;
                [~, i] = min(abs(G.thP(:) - app.info.POBth) + abs(mod(G.phP(:) - app.info.POBph + 180, 360) - 180));
                rows = [dataTipTextRow(app.thetaLabel(), G.th(i), '%.3g°'); dataTipTextRow('Phi', G.ph(i), '%.3g°'); ...
                    dataTipTextRow(strrep(char(app.compLabel()), '_', '\_'), G.Z(i), '%.3g dB')];
                if isa(ax, 'matlab.graphics.axis.PolarAxes')
                    held = ishold(ax); hold(ax, 'on'); h = polarplot(ax, s.XData(i), s.YData(i), 'o'); if ~held, hold(ax, 'off'); end
                else
                    h = line(ax, s.XData(i), s.YData(i), s.ZData(i), 'LineStyle', 'none', 'Marker', 'o');
                end
                set(h, 'Color', 'k', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'Tag', 'APAT_POB', 'HandleVisibility', 'off');
                h.DataTipTemplate.DataTipRows = rows;
                try, datatip(h, 'DataIndex', 1, 'Tag', 'APAT_POB', 'FontSize', 9); catch, end
            end
        end

        %% ───────────────────────────── cuts ─────────────────────────────
        function [cols, idx] = cutCols(app)
            %CUTCOLS Selected cut columns: Total plus the co/cross pair of the active basis (gain-only: the displayed component).
            % idx keeps the colour role stable: 1 = Total, 2 = co-pol, 3 = cross-pol.
            if app.isGainOnly(), cols = {app.comp()}; idx = 1; return; end
            pair = string(app.info.pairs.(app.ui.basis.Value));
            set(app.ui.cbCo, 'Text', char(pair(1))); set(app.ui.cbCx, 'Text', char(pair(2)));
            sel = [app.ui.cbTot.Value, app.ui.cbCo.Value, app.ui.cbCx.Value]; if ~any(sel), sel(1) = true; end
            all_ = cellstr(["E_Total_dB", pair + "_dB"]); idx = find(sel); cols = all_(idx);
        end

        function c = cutData(app)
            %CUTDATA Active cut as a closed circle in the display window: angle, values (N×k) and physical θ/φ of every point.
            T = app.patTbl; [cols, idx] = app.cutCols(); type = string(app.ui.cutType.Value);
            req = app.ui.cutVal.Value; if type == "Phi" && app.isElev(), req = 90 - req; end
            c = cutRows(T, type, req);
            if c.snapped
                shown = c.fixed; if type == "Phi" && app.isElev(), shown = 90 - shown; end
                app.setStatus(app.ui.status, sprintf('%s cut snapped to the nearest sample: %s = %g°', type, c.symbol, shown), true);
            end
            lo = 0; if app.isSigned(), lo = -180; end
            [c.angle, c.vals] = closeCircle(c.angle, T{c.rows, cols}, lo);
            a = mod(c.angle, 360);
            if type == "Phi"
                c.thP = repmat(c.fixed, size(a)); c.phP = a;
            else                                          % great circle: θ = a on φ0, θ = 360−a on φ0+180
                back = a > 180; c.thP = a; c.thP(back) = 360 - a(back);
                c.phP = repmat(c.fixed, size(a)); c.phP(back) = mod(c.fixed + 180, 360);
            end
            c.cols = cols; c.idx = idx; c.names = strrep(cols, '_', '\_');
            if app.isGainOnly(), c.title = char(app.compLabel()); else, c.title = sprintf('%s cut @ %s = %g°', type, c.symbol, c.fixed); end
        end

        function plotCut(app)
            if isempty(app.patTbl), return; end
            c = app.cutData(); pax = app.ui.axCutP; rax = app.ui.axCutR; lim = app.cutLim;
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on');
            co = rax.ColorOrder; col = co(1 + mod(c.idx - 1, size(co, 1)), :);
            pl = polarplot(pax, deg2rad(c.angle), max(c.vals, lim(1)), 'LineWidth', 1.4);     % clamp: no reflection through the origin
            rl = plot(rax, c.angle, c.vals, 'LineWidth', 1.4);
            for k = 1:numel(pl)
                rows = [dataTipTextRow('Angle', c.angle, '%.3g°'); dataTipTextRow('Magnitude', c.vals(:, k), '%.3g dB')];
                set([pl(k) rl(k)], 'Color', col(k, :)); pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            if app.isSigned(), xl = [-180 180]; else, xl = [0 360]; end
            set(pax, 'ThetaDir', 'clockwise', 'ThetaZeroLocation', 'top', 'RLim', lim); app.polarTicks(pax);
            set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, [char(c.type) ' (degree)']); ylabel(rax, 'Magnitude (dB)');
            title(pax, c.title, 'Interpreter', 'none'); title(rax, c.title, 'Interpreter', 'none');
            % Peak of the displayed cut (APAT_POB) and HPBW shading / bound markers (APAT_HPBW).
            [pk, i] = max(c.vals(:, 1)); app.ui.hpbwLabel.Text = '';
            if app.ui.pob.Value && isfinite(pk)
                rows = [dataTipTextRow('Angle', c.angle(i), '%.3g°'); dataTipTextRow('Magnitude', pk, '%.3g dB')];
                app.mark(pax, deg2rad(c.angle(i)), max(pk, lim(1)), 'k', rows, 'APAT_POB'); app.mark(rax, c.angle(i), pk, 'k', rows, 'APAT_POB');
            end
            if app.ui.hpbwBtn.Value && isfinite(pk)
                [bw, a1, a2] = calcHPBW(c.angle, c.vals(:, 1), pk, c.angle(i));
                if isfinite(bw)
                    b = mod([a1 a2] - xl(1), 360) + xl(1);
                    app.ui.hpbwLabel.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                    if b(1) <= b(2), reg = b; else, reg = [xl(1) b(2); b(1) xl(2)]; end   % wrap-aware shading
                    thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    xregion(rax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    if app.ui.hpbwBounds.Value
                        lab = {'Lower HPBW', 'Upper HPBW'};
                        for k = 1:2
                            rows = [dataTipTextRow(lab{k}, b(k), '%.2f°'); dataTipTextRow('Gain', pk - 3, '%.2f dB')];
                            app.mark(pax, deg2rad(b(k)), pk - 3, '#D95319', rows, 'APAT_HPBW'); app.mark(rax, b(k), pk - 3, '#D95319', rows, 'APAT_HPBW');
                        end
                    end
                end
            end
            legend(pax, pl, c.names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rl, c.names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off');
        end

        function mark(~, ax, x, y, color, rows, tag)
            %MARK Filled marker with a pinned DataTip on a polar or rectangular axes.
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), h = polarplot(ax, x, y, 'o'); else, h = plot(ax, x, y, 'o'); end
            set(h, 'Color', color, 'MarkerFaceColor', color, 'MarkerSize', 5, 'HandleVisibility', 'off', 'Tag', tag);
            h.DataTipTemplate.DataTipRows = rows;
            try, datatip(h, 'DataIndex', 1, 'Tag', tag, 'FontSize', 9); catch, end
        end

        %% ───────────────────────────── tables, metadata, export ─────────────────────────────
        function T = displayTable(app)
            %DISPLAYTABLE patTbl in the selected display convention (θ→elevation and/or φ→signed), sorted by φ then θ.
            T = app.patTbl;
            if app.isSigned()
                T = T(T.Phi < 360, :); T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
                s = T(T.Phi == 180, :); s.Phi(:) = -180; T = [s; T];
            end
            if app.isElev(), T.Theta = 90 - T.Theta; end
            if app.isSigned() || app.isElev(), T = sortrows(T, {'Phi', 'Theta'}); end
        end

        function updateTables(app)
            %UPDATETABLES Input table (raw file data) and Results table (display convention + column filter).
            u = app.ui; u.tblIn.Data = app.src.rawTbl; u.tblIn.ColumnName = app.src.rawTbl.Properties.VariableNames;
            cols = app.patTbl.Properties.VariableNames(3:end); dd = u.outFilter;
            if ~isequal(regexprep(dd.Items(2:end), '^✓ ', ''), cols)         % schema changed → rebuild the filter
                dd.Items = [{'--- column filter ---'} cols]; dd.ItemsData = 0:numel(cols);
                dd.UserData = ~ismember(cols, app.Hidden); dd.Value = 0;
            end
            app.filterOutput();
        end

        function filterOutput(app)
            %FILTEROUTPUT Toggle one column (dropdown pick), restyle the list, refresh the Results table and parameter visibility.
            dd = app.ui.outFilter; on = dd.UserData;
            if dd.Value > 0, on(dd.Value) = ~on(dd.Value); dd.UserData = on; dd.Value = 0; end
            items = regexprep(dd.Items, '^✓ ', ''); k = find(on) + 1; items(k) = append('✓ ', items(k)); dd.Items = items;
            removeStyle(dd);
            if ~isempty(k), addStyle(dd, uistyle('FontWeight', 'bold', 'BackgroundColor', [0.8 1 0.8]), 'Item', k); end
            addStyle(dd, uistyle('FontColor', [0.5 0.5 0.5]), 'Item', find([true ~on]));
            T = app.displayTable(); app.ui.tblOut.Data = T(:, [true true on]);
            app.updateParamVisibility(on);
        end

        function updateParamVisibility(app, on)
            %UPDATEPARAMVISIBILITY Show only the input parameters that influence a visible Results column.
            sel = string(app.patTbl.Properties.VariableNames(3:end)); sel = sel(on); u = app.ui;
            rx = any(ismember(sel, ["PLF_dB", "Gain_PolCorrected_dB"])); tx = any(ismember(sel, ["EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
            dist = any(ismember(sel, ["PFD_Wm2", "E_RMS_Vm"]));
            loss = app.isGainOnly() || any(ismember(sel, ["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", ...
                "Gain_PolCorrected_dB", "EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
            set([u.rxL u.rx u.rwL u.rw], 'Visible', rx); set([u.ptL u.pt u.ptU], 'Visible', tx);
            set([u.rL u.r u.rU], 'Visible', dist); set([u.lossL u.loss], 'Visible', loss);
        end

        function updateMetadata(app)
            T = app.patTbl; m = app.metrics; meta = app.src.meta; th = unique(T.Theta); ph = unique(T.Phi);
            rows = {'Source format', meta.source; 'File', app.file.name; ...
                'Samples', sprintf('%d  (θ: %d × φ: %d)', height(T), numel(th), numel(ph)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmt(min(th)), fmt(max(th)), fmt(gridStep(th))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmt(min(ph)), fmt(max(ph)), fmt(gridStep(ph)))};
            f = app.src.freqs(isfinite(app.src.freqs));
            if ~isempty(f), rows(end + 1, :) = {'Frequencies', strjoin(compose('%.4g GHz', f/1e9), ', ')}; end
            xl = {'pattern_description', 'Pattern description'; 'element_model_name', 'Element model'; ...
                'element_polarization', 'Element polarization'; 'pattern_simulation_band_name', 'Band'};
            for k = 1:size(xl, 1)
                if isfield(meta, xl{k, 1}), rows(end + 1, :) = {xl{k, 2}, char(string(meta.(xl{k, 1})))}; end %#ok<AGROW>
            end
            if ~app.isGainOnly()
                rows = [rows; {'Polarization', app.info.pol; 'Cut co-pol / cross-pol', char(strjoin(app.info.pairs.(app.ui.basis.Value), ' / '))}];
            end
            rows = [rows; {'Peak gain (POB)', [fmt(app.info.POB) ' dB']; ...
                'POB direction [θ, φ]', sprintf('[%s°, %s°]', fmt(app.info.POBth), fmt(app.info.POBph)); ...
                'Boresight axis', app.Axes6.labels{app.boresight}; ...
                'Peak policy', sprintf('P%.4g + %g dB max excess; adjusted: %s', app.PeakPct, app.PeakExcess, string(app.info.peak.adjusted)); ...
                'HPBW E-plane', [fmt(m.HPBW_EPlane_deg) '°']; 'HPBW H-plane', [fmt(m.HPBW_HPlane_deg) '°']; ...
                'Front-to-back', [fmt(m.FrontBack_dB) ' dB']; 'Peak directivity', [fmt(m.PeakDirectivity_dB) ' dB']; ...
                'Radiation efficiency', [fmt(m.Efficiency_pct) ' %']; 'AR at peak', [fmt(m.AxialRatioAtPeak_dB) ' dB']}];
            app.ui.tblMeta.Data = rows;
        end

        function writeTable(~, T, fp)
            if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
        end

        function exportResults(app)
            if isempty(app.patTbl), return; end
            [f, p] = uiputfile({'*.csv', 'CSV (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, ...
                'Export Results', fullfile(app.file.folder, [app.file.base '_APAT_results.csv']));
            if isequal(f, 0), return; end
            app.writeTable(app.ui.tblOut.Data, fullfile(p, f));              % respects the active column filter
            app.setStatus(app.ui.status, ['Results exported to <b>' fullfile(p, f) '</b>'], true);
        end

        function exportCut(app)
            if isempty(app.patTbl), return; end
            c = app.cutData();
            [f, p] = uiputfile({'*.csv', 'CSV (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'}, 'Export Cut', fullfile(app.file.folder, [app.file.base '_cut.csv']));
            if isequal(f, 0), return; end
            app.writeTable(array2table([c.angle c.vals], 'VariableNames', [{'Angle_deg'} c.cols]), fullfile(p, f));
            app.setStatus(app.ui.status, ['Cut (' c.title ') exported to <b>' fullfile(p, f) '</b>'], true);
        end

        function exportUAN(app)
            %EXPORTUAN XGTD user-defined antenna file (physical θ/φ, dB magnitude + degree phase of Eθ/Eφ).
            if app.isGainOnly(), uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            T = app.patTbl;
            U = sortrows(table(T.Theta, T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'}), {'Phi', 'Theta'});
            gmax = max([U.E_TH_DB; U.E_PH_DB]); st = gridStep(U.Theta); if isnan(st), st = 1; end
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'CSV (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'}, ...
                'Export UAN / E-field data', fullfile(app.file.folder, sprintf('%s_%.5f_%gdeg.uan', app.file.base, gmax, st)));
            if isequal(f, 0), return; end
            fp = fullfile(p, f); c = app.busy('Saving Data', 'Writing file...', false); %#ok<NASGU>
            if endsWith(fp, '.uan', 'IgnoreCase', true)
                hdr = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\n' ...
                    'polarization theta_phi\nend_<parameters>'], min(U.Phi), max(U.Phi), gridStep(U.Phi), min(U.Theta), max(U.Theta), st, gmax);
                writelines(hdr, fp);
                writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
            else
                app.writeTable(U, fp);
            end
            app.setStatus(app.ui.status, ['UAN exported to <b>' fp '</b>'], true);
        end

        %% ───────────────────────────── coverage ─────────────────────────────
        function P = patternFrom(app, src_)
            %PATTERNFROM Auxiliary pattern (block 1) processed with the current parameters, without touching Main state.
            S = normalizePattern(src_.blocks{1}); S.Properties.UserData = src_.meta;
            P = calcPattern(S, app.getParam(), app.PeakPct, app.PeakExcess);
        end

        function toCoverage(app)
            if isempty(app.patTbl), uialert(app.UIFigure, 'Load and process a pattern first.', 'Coverage'); return; end
            u = app.ui; u.tabs.SelectedTab = u.covTab; u.covPath.Value = app.file.path;
            n = app.covFind(app.file.path);
            if isempty(n), app.covAddPattern(app.file.base, app.patTbl, app.file.path, app.src.rawTbl);
            else, app.covSyncMain(n); u.covTree.SelectedNodes = n; app.covUI(); end
            app.setStatus(u.covStatus, 'Coverage source synchronized with the current processed pattern.');
        end

        function covLoad(app)
            u = app.ui; fp = strtrim(u.covPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFind(fp))
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage data'; '*.*', 'All files'}, ...
                    'Select a pattern or coverage results file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            n = app.covFind(fp);
            if ~isempty(n)
                u.covTree.SelectedNodes = n; app.covSelChanged(); app.setStatus(u.covStatus, 'File already loaded — node selected.', true); return
            end
            u.covPath.Value = fp; src_ = readPattern(fp, app.textFormatFor(fp, u.covFmtL, u.covFmt));
            if src_.meta.isCoverage, set([u.covFmtL u.covFmt], 'Visible', 'off'); app.covLoadResults(fp, src_.rawTbl);
            else, [~, name] = fileparts(fp); app.covAddPattern(name, app.patternFrom(src_), fp, src_.rawTbl); end
        end

        function covFmtChanged(app)
            %COVFMTCHANGED Re-interpret a generic coverage-pattern node with the newly selected text format.
            fp = strtrim(app.ui.covPath.Value); n = app.covFind(fp);
            if isempty(n) || ~app.isGeneric(fp) || ~strcmp(n.NodeData.kind, 'pattern'), return; end
            src_ = readPattern(fp, app.ui.covFmt.Value, n.NodeData.raw);
            if src_.meta.isCoverage, app.setStatus(app.ui.covStatus, 'Coverage-result files are detected automatically.', true); return; end
            name = n.NodeData.name; jobs = app.covJobs(n);
            for j = jobs(:).', if isgraphics(j.NodeData.line), delete(j.NodeData.line); end, end
            delete(n); app.covAddPattern(name, app.patternFrom(src_), fp, src_.rawTbl); app.covFinalize();
        end

        function n = covFind(app, fp)
            n = [];
            for k = app.ui.covRoot.Children(:).'
                if isstruct(k.NodeData) && strcmp(k.NodeData.path, fp), n = k; return; end
            end
        end

        function n = covTarget(app)
            %COVTARGET Pattern node to operate on: the selection (or its pattern ancestor), else the most recent pattern node.
            n = []; s = app.ui.covTree.SelectedNodes;
            if ~isempty(s)
                s = s(1);
                while isa(s, 'matlab.ui.container.TreeNode')
                    if isstruct(s.NodeData) && strcmp(s.NodeData.kind, 'pattern'), n = s; return; end
                    s = s.Parent;
                end
            end
            kids = app.ui.covRoot.Children;
            for k = kids(end:-1:1).'
                if isstruct(k.NodeData) && strcmp(k.NodeData.kind, 'pattern'), n = k; return; end
            end
        end

        function jobs = covJobs(app, roots)
            %COVJOBS Job nodes (optionally only below the given nodes), ordered by run id.
            if nargin < 2, roots = app.ui.covRoot; end
            jobs = matlab.ui.container.TreeNode.empty(0, 1);
            for r = roots(:).'
                if isstruct(r.NodeData) && strcmp(r.NodeData.kind, 'job'), jobs(end + 1, 1) = r; %#ok<AGROW>
                else, for k = r.Children(:).', jobs = [jobs; app.covJobs(k)]; end %#ok<AGROW>
                end
            end
            if numel(jobs) > 1, [~, o] = sort(arrayfun(@(j) j.NodeData.id, jobs)); jobs = jobs(o); end
        end

        function n = covAddPattern(app, name, P, fp, raw)
            n = uitreenode(app.ui.covRoot, 'Text', ['📡 ' name]);
            n.NodeData = struct('kind', 'pattern', 'name', name, 'path', fp, 'pattern', P, 'raw', raw, ...
                'solid', solidWeights(P.Theta, P.Phi), 'component', '', 'boresight', 1, 'rev', 0, 'cache', struct());
            expand(app.ui.covTree); app.ui.covTree.CheckedNodes = [app.ui.covTree.CheckedNodes; n]; app.ui.covTree.SelectedNodes = n;
            app.covSync(n); app.covUI();
            app.setStatus(app.ui.covStatus, sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name));
        end

        function covSyncMain(app, n)
            %COVSYNCMAIN The Main-tab node always mirrors the CURRENT processed pattern (loss, step, parameters).
            d = n.NodeData; d.pattern = app.patTbl; d.solid = app.dOmega; d.raw = app.src.rawTbl; d.name = app.file.base;
            d.component = ''; d.cache = struct(); d.rev = d.rev + 1; n.NodeData = d; app.covSync(n);
        end

        function covSync(app, n)
            %COVSYNC Component list, boresight and automatic threshold preset follow the target pattern node.
            d = n.NodeData; P = d.pattern; [cols, labels] = componentMap(P); dd = app.ui.covComp;
            prev = dd.Value; if ~isempty(d.component), prev = d.component; end
            cmp = pickComponent(prev, cols); dd.Items = labels; dd.ItemsData = cols; dd.Value = cmp;
            if ~strcmp(d.component, cmp)
                g = P.(cmp); d.component = cmp;
                d.boresight = calcOrientation(P, g, d.solid, resolvePeak(g, app.PeakPct, app.PeakExcess), app.Axes6); n.NodeData = d;
                if app.ui.covOrient.Value == 0, app.covOrientChanged(); end
            end
            key = string(sprintf('%s|%s|%d', d.path, cmp, d.rev));
            if app.covPreset ~= key                          % preset only when pattern/component/revision changes
                app.covPreset = key; app.covSetThresholds(displayRange(P.(cmp), app.PeakPct, app.PeakExcess));
            end
        end

        function covSetThresholds(app, b)
            %COVSETTHRESHOLDS Automatic threshold window: set once, afterwards only widened (user edits are never shrunk).
            u = app.ui; if app.covThrInit, b = [min(u.thrMin.Value, b(1)), max(u.thrMax.Value, b(2))]; end
            app.covThrInit = true;
            u.thrMin.Limits = [app.Range(1), b(2) - 0.1]; u.thrMax.Limits = [b(1) + 0.1, app.Range(2)];
            u.thrMin.Value = b(1); u.thrMax.Value = b(2);
        end

        function t = covThresholds(app)
            u = app.ui; lo = u.thrMin.Value; hi = u.thrMax.Value; st = max(u.thrStep.Value, 0.1);
            if hi <= lo, hi = min(app.Range(2), lo + st); u.thrMax.Value = hi; end
            t = (lo:st:hi).'; if t(end) < hi, t(end + 1) = hi; end
        end

        function covCompute(app)
            n = app.covTarget();
            if isempty(n), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if strcmp(n.NodeData.path, app.file.path) && ~isempty(app.patTbl), app.covSyncMain(n); end
            d = n.NodeData; P = d.pattern; u = app.ui; cmp = u.covComp.Value; thr = app.covThresholds(); conical = u.covCon.Value;
            if conical
                th0 = u.coneTh.Value; ph0 = mod(u.conePh.Value, 360); a = u.coneA.Value;
                mask = cosd(P.Theta)*cosd(th0) + sind(P.Theta)*sind(th0).*cosd(P.Phi - ph0) >= cosd(a);
                center = app.coneLabel(th0, ph0); tag = sprintf('Con_%.15g_%.15g_%.15g', th0, ph0, a);
                full = sprintf('Conical coverage (%s) α=%s°', center, fmt(a)); short = sprintf('Con %s α%s°', erase(center, ["=", ","]), fmt(a));
                oi = u.covOrient.Value; if oi == 0, oi = d.boresight; end; orient = app.Axes6.labels{oi};
            else
                mask = true(height(P), 1); tag = 'Sph'; full = 'Spherical coverage'; short = 'Sph'; orient = 'n/a';
            end
            key = matlab.lang.makeValidName(sprintf('%s_%s_%g_%g_%g_%d', cmp, tag, thr(1), thr(end), gridStep(thr), numel(thr)));
            hit = isfield(d.cache, key);
            if hit, cov = d.cache.(key); else, cov = coverageCCDF(P.(cmp), mask, thr, d.solid); d.cache.(key) = cov; n.NodeData = d; end
            j = app.covAddJob(n, thr, cov, tag, cmp, full);
            jd = j.NodeData; jd.tableTag = short; jd.isConical = conical; jd.orient = orient; j.NodeData = jd;
            app.covFinalize(); app.covSetX([thr(1) thr(end)], "auto");
            act = 'computed'; if hit, act = 'reused cached CCDF'; end
            s = sprintf('Run <b>%d</b> %s: <b>%s</b> on "<b>%s</b>" (%s, %d thresholds)', app.covRunID, act, full, d.name, cmp, numel(thr));
            if conical, s = sprintf('%s | Orientation <b>%s</b>', s, orient); end
            app.setStatus(u.covStatus, s);
        end

        function j = covAddJob(app, parent, thr, cov, tag, cmp, shown)
            app.covRunID = app.covRunID + 1; icon = '📉'; if strcmp(tag, 'Res'), icon = '📈'; end
            label = sprintf('%s R%d %s · %s', icon, app.covRunID, shown, cmp);
            ln = plot(app.ui.axCov, thr, cov, 'LineWidth', 1.6, 'DisplayName', label); [icov, ir] = unique(cov, 'last');
            j = uitreenode(parent, 'Text', label);
            j.NodeData = struct('kind', 'job', 'id', app.covRunID, 'tag', tag, 'thr', thr(:), 'cov', cov(:), 'invCov', icov(:), 'invThr', thr(ir), ...
                'line', ln, 'label', label, 'tableTag', shown, 'isConical', false, 'orient', 'n/a');
            app.ui.covTree.CheckedNodes = [app.ui.covTree.CheckedNodes; j];
        end

        function covLoadResults(app, fp, T)
            [~, name] = fileparts(fp); n = uitreenode(app.ui.covRoot, 'Text', ['📄 ' name]);
            n.NodeData = struct('kind', 'results', 'name', name, 'path', fp);
            thr = T{:, 1}; app.covSetX([min(thr) max(thr)], "auto");
            if gridStep(thr) < app.ui.thrStep.Value, app.ui.thrStep.Value = max(gridStep(thr), 0.1); end
            for k = 2:width(T), app.covAddJob(n, thr, T{:, k}, 'Res', T.Properties.VariableNames{k}, 'Res'); end
            app.ui.covTree.CheckedNodes = [app.ui.covTree.CheckedNodes; n]; app.covFinalize();
            app.setStatus(app.ui.covStatus, sprintf('Coverage results "<b>%s</b>" loaded (%d curves).', name, width(T) - 1));
        end

        function covFinalize(app)
            %COVFINALIZE Expand the tree, rebuild the results table (union of checked thresholds) and the legend.
            u = app.ui; jobs = app.covJobs(); checked = jobs(ismember(jobs, u.covTree.CheckedNodes));
            expand(u.covRoot); if ~isempty(jobs), expand(unique([jobs.Parent])); end
            thr = app.covThresholds();
            if ~isempty(checked), c = arrayfun(@(j) j.NodeData.thr, checked, 'UniformOutput', false); thr = unique(vertcat(c{:})); end
            V = nan(numel(thr), numel(checked) + 1); V(:, 1) = thr; names = cell(1, numel(checked) + 1); names{1} = 'Threshold (dB)';
            for k = 1:numel(checked)
                jd = checked(k).NodeData; V(:, k + 1) = interp1(jd.thr, jd.cov, thr, 'linear', NaN); names{k + 1} = sprintf('R%d %s %%', jd.id, jd.tableTag);
            end
            u.covTable.Data = array2table(compose('%.2f', V), 'VariableNames', names);
            if isempty(checked), legend(u.axCov, 'off');
            else, nd = [checked.NodeData]; legend(u.axCov, [nd.line], {nd.label}, 'Location', 'southwest', 'Interpreter', 'none'); end
            app.covUI();
        end

        function covUI(app)
            u = app.ui; hasPat = ~isempty(app.covTarget()); hasJobs = ~isempty(app.covJobs());
            u.covCompute.Enable = hasPat; set([u.covComp u.covCompL], 'Enable', hasPat); u.covReset.Enable = hasPat || hasJobs;
            set([u.covExport u.covClear u.qCovBtn u.qThrBtn], 'Enable', hasJobs); u.covResults.Visible = hasPat || hasJobs;
            set([u.covFmtL u.covFmt], 'Visible', hasPat && app.isGeneric(u.covPath.Value));
            app.covTypeChanged();
        end

        function covTypeChanged(app)
            u = app.ui; on = u.covCon.Value;
            set([u.coneThL u.coneTh u.conePhL u.conePh u.coneAL u.coneA u.covOrientL u.covOrient], 'Enable', on);
            if on, n = app.covTarget(); if ~isempty(n), app.covSync(n); end; app.covReportOrient();
            else, u.covStatus.Text = regexprep(char(u.covStatus.Text), '\s*\|\s*Orientation <b>.*?</b>', ''); end
        end

        function covOrientChanged(app)
            %COVORIENTCHANGED Auto → detected boresight of the target node; explicit picks are authoritative.
            i = app.ui.covOrient.Value;
            if i == 0, n = app.covTarget(); if isempty(n), return; end; i = n.NodeData.boresight; end
            app.ui.coneTh.Value = app.Axes6.theta(i); app.ui.conePh.Value = app.Axes6.phi(i); app.covReportOrient();
        end

        function covReportOrient(app)
            if ~app.ui.covCon.Value, return; end
            i = app.ui.covOrient.Value;
            if i == 0, n = app.covTarget(); if isempty(n), return; end; i = n.NodeData.boresight; end
            s = regexprep(char(app.ui.covStatus.Text), '\s*\|\s*Orientation <b>.*?</b>$', '');
            app.setStatus(app.ui.covStatus, sprintf('%s | Orientation <b>%s</b>', s, app.Axes6.labels{i}));
        end

        function covCompChanged(app)
            n = app.covTarget(); if isempty(n), return; end
            d = n.NodeData; if ~ismember(app.ui.covComp.Value, d.pattern.Properties.VariableNames), return; end
            d.component = ''; n.NodeData = d; app.covSync(n);   % user choice becomes the node's component
        end

        function s = coneLabel(app, th, ph)
            %CONELABEL Principal-axis name when the cone centre coincides with ±X/±Y/±Z, else explicit θ/φ.
            A = app.Axes6; v = [sind(th)*cosd(ph), sind(th)*sind(ph), cosd(th)];
            V = [sind(A.theta(:)).*cosd(A.phi(:)), sind(A.theta(:)).*sind(A.phi(:)), cosd(A.theta(:))];
            k = find(V*v.' >= 1 - 1e-9, 1);
            if isempty(k), s = sprintf('θ=%s°, φ=%s°', fmt(th), fmt(ph)); else, s = A.labels{k}; end
        end

        function h = covArtifacts(app, ln, tag)
            h = [findall(app.ui.axCov, 'Tag', tag); findall(ln, 'Tag', tag)];
        end

        function covQuery(app, mode)
            %COVQUERY Project a threshold ("cov") or a coverage level ("thr") onto every checked curve under the selection.
            u = app.ui; ax = u.axCov; sel = u.covTree.SelectedNodes;
            if isempty(sel), app.setStatus(u.covStatus, 'Select a node to query.', true); return; end
            jobs = app.covJobs(sel); jobs = jobs(ismember(jobs, u.covTree.CheckedNodes));
            if isempty(jobs), app.setStatus(u.covStatus, 'No checked results under the selected node.', true); return; end
            if mode == "cov", q = u.qCov.Value; else, q = u.qThr.Value; end
            hit = false;
            for j = jobs(:).'
                d = j.NodeData; if ~isgraphics(d.line), continue; end
                tag = sprintf('CovQ_%s_%d', mode, d.id); delete(app.covArtifacts(d.line, tag));
                if mode == "cov", x = q; y = interp1(d.thr, d.cov, q, 'linear', NaN); else, y = q; x = interp1(d.invCov, d.invThr, q, 'linear', NaN); end
                if ~isfinite(x) || ~isfinite(y), continue; end
                line(ax, [x x], [ax.YLim(1) y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [app.Range(1) x], [y y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                try
                    d.line.DataTipTemplate.DataTipRows = [dataTipTextRow('Threshold', 'XData', '%.2f dB'); dataTipTextRow('Coverage', 'YData', '%.2f%%')];
                    datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'Tag', tag, 'FontSize', 9);
                catch
                end
                hit = true;
            end
            if ~hit, app.setStatus(u.covStatus, 'Query value is outside the range of the checked curves.', true);
            elseif mode == "cov", app.setStatus(u.covStatus, sprintf('Coverage queried at %s dB.', fmt(q)));
            else, app.setStatus(u.covStatus, sprintf('Threshold queried at %s%% coverage.', fmt(q)));
            end
        end

        function covCheckChanged(app)
            chk = app.ui.covTree.CheckedNodes; jobs = app.covJobs();
            for j = jobs(:).'
                d = j.NodeData; on = ismember(j, chk); if ~isgraphics(d.line), continue; end
                d.line.Visible = on; set(findall(d.line, 'Type', 'datatip'), 'Visible', on);
                for m = ["cov" "thr"], set(app.covArtifacts(d.line, sprintf('CovQ_%s_%d', m, d.id)), 'Visible', on); end
            end
            app.covFinalize();
        end

        function covSelChanged(app)
            u = app.ui; sel = u.covTree.SelectedNodes; jobs = app.covJobs();
            for j = jobs(:).'
                if isgraphics(j.NodeData.line), j.NodeData.line.LineWidth = 1.6 + (~isempty(sel) && isequal(j, sel(1))); end
            end
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(u.covStatus, 'Ready.'); return; end
            d = sel(1).NodeData; t = app.covTarget(); if ~isempty(t), app.covSync(t); end
            if ~strcmp(d.kind, 'job')
                kind = 'Pattern'; if strcmp(d.kind, 'results'), kind = 'Results'; end
                app.setStatus(u.covStatus, sprintf('%s "<b>%s</b>" — <b>%d</b> coverage job(s).', kind, d.name, numel(sel(1).Children)));
                if strcmp(d.kind, 'pattern'), app.covReportOrient(); end
                return
            end
            parts = {d.label}; if d.isConical, parts{end + 1} = sprintf('Orientation <b>%s</b>', d.orient); end
            parts{end + 1} = sprintf('Threshold [%s, %s] dB, step %s dB', fmt(d.thr(1)), fmt(d.thr(end)), fmt(gridStep(d.thr)));
            t50 = interp1(d.invCov, d.invThr, 50, 'linear', NaN);
            if isfinite(t50), parts{end + 1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', fmt(t50)); else, parts{end + 1} = '<b>50%-coverage unavailable</b>'; end
            shown = round(d.cov, 2); mx = max(shown); im = find(shown == mx, 1, 'last');
            if isfinite(mx), parts{end + 1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmt(mx), fmt(d.thr(im))); end
            app.setStatus(u.covStatus, strjoin(parts, ' | '));
        end

        function covClear(app)
            sel = app.ui.covTree.SelectedNodes;
            if isempty(sel), app.setStatus(app.ui.covStatus, 'Select a node to clear.', true); return; end
            jobs = app.covJobs(sel);
            for j = jobs(:).'
                d = j.NodeData; if ~isgraphics(d.line), continue; end
                for m = ["cov" "thr"], delete(app.covArtifacts(d.line, sprintf('CovQ_%s_%d', m, d.id))); end
                delete(findall(d.line, 'Type', 'datatip'));
            end
            app.setStatus(app.ui.covStatus, 'DataTips and query markers cleared.', true);
        end

        function covReset(app)
            u = app.ui; delete(u.covRoot.Children); delete(findall(u.axCov, 'Type', 'datatip')); cla(u.axCov); legend(u.axCov, 'off');
            hold(u.axCov, 'on'); grid(u.axCov, 'on'); set(u.axCov, 'YLim', [0 100], 'XLimMode', 'auto');
            u.covTable.Data = table(); app.covRunID = 0; app.covPreset = ""; app.covXInit = false; app.covThrInit = false;
            set(u.xRange, 'Limits', app.Range, 'Value', [-40 10]); set([u.xMin u.xMax], 'Limits', app.Range); u.xMin.Value = -40; u.xMax.Value = 10;
            app.covUI(); app.setStatus(u.covStatus, 'Coverage workspace reset 🔄', true);
        end

        function covExport(app)
            if isempty(app.ui.covTable.Data), return; end
            [f, p] = uiputfile({'*.csv', 'CSV (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, ...
                'Export Coverage Results', fullfile(app.file.folder, 'coverage_results.csv'));
            if isequal(f, 0), return; end
            app.writeTable(app.ui.covTable.Data, fullfile(p, f)); app.setStatus(app.ui.covStatus, ['Coverage results exported to ' fullfile(p, f)], true);
        end

        function covSetX(app, b, mode)
            %COVSETX Coverage X-range. "auto": results only widen the baseline; "spinner": exact (spinners define the slider
            % travel); "slider": picks within the travel.  Programmatic Value changes never re-fire callbacks.
            u = app.ui; b = app.clamp(b);
            if mode == "slider", u.xMin.Value = b(1); u.xMax.Value = b(2); set(u.axCov, 'XLimMode', 'manual', 'XLim', b); return; end
            if mode == "auto" && app.covXInit, b = [min(u.xMin.Value, b(1)), max(u.xMax.Value, b(2))]; end
            app.covXInit = true;
            set(u.xRange, 'Limits', app.Range, 'Value', b); u.xRange.Limits = b;
            u.xMin.Limits = [app.Range(1), b(2) - 0.1]; u.xMax.Limits = [b(1) + 0.1, app.Range(2)]; u.xMin.Value = b(1); u.xMax.Value = b(2);
            set(u.axCov, 'XLimMode', 'manual', 'XLim', b);
        end

        function covXFromSpinner(app, e)
            u = app.ui; b = [u.xMin.Value, u.xMax.Value];
            if diff(b) <= 0
                if isequal(e.Source, u.xMin), b(2) = min(app.Range(2), b(1) + 1); else, b(1) = max(app.Range(1), b(2) - 1); end
            end
            app.covSetX(b, "spinner");
        end

        %% ───────────────────────────── infrastructure ─────────────────────────────
        function f = cb(app, fn)
            %CB Wrap a callback: errors are shown in-app, cancellation is reported quietly.
            f = @(~, e) app.guard(fn, e);
        end

        function guard(app, fn, e)
            try
                if nargin(fn) == 0, fn(); else, fn(e); end
            catch ME
                if app.isClosing, return; end
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.setStatus(app.ui.status, 'Operation cancelled.', true);
                else
                    loc = ''; if ~isempty(ME.stack), loc = sprintf('\n(%s, line %d)', ME.stack(1).name, ME.stack(1).line); end
                    uialert(app.UIFigure, [ME.message loc], 'APAT Error', 'Icon', 'error');
                end
            end
        end

        function c = busy(app, ttl, msg, cancelable)
            %BUSY Indeterminate progress dialog that closes automatically when the returned cleanup object is destroyed.
            dlg = uiprogressdlg(app.UIFigure, 'Title', ttl, 'Message', msg, 'Indeterminate', 'on', 'Cancelable', cancelable, 'CancelText', 'Abort');
            app.opDialog = dlg; c = onCleanup(@() delete(dlg)); drawnow;
        end

        function checkCancelled(app)
            d = app.opDialog;
            if ~isempty(d) && isvalid(d) && d.CancelRequested, error('APAT:Cancelled', 'Cancelled by user.'); end
        end

        function setStatus(app, label, msg, transient)
            %SETSTATUS Persistent status text, or a 3-second transient message that restores the previous text.
            if app.isClosing || ~isgraphics(label), return; end
            app.stopTimer(); label.Text = char(msg);
            if nargin > 3 && transient
                app.statusTimer = timer('StartDelay', 3, 'TimerFcn', @(t, ~) app.restoreStatus(label), 'StopFcn', @(t, ~) delete(t));
                start(app.statusTimer);
            else
                label.UserData = char(msg);
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

        %% ───────────────────────────── UI construction ─────────────────────────────
        function h = add(~, parent, ctor, row, col, varargin)
            %ADD Create one widget inside a grid cell.  ctor: @uibutton or {@uibutton, 'state'} (style argument).
            if iscell(ctor), h = ctor{1}(parent, ctor{2:end}, varargin{:}); else, h = ctor(parent, varargin{:}); end
            h.Layout.Row = row; h.Layout.Column = col;
        end

        function dd = formatDropdown(~, parent, fcn)
            dd = uidropdown(parent, 'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
                '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
                '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'}, ...
                'Value', 'gain', 'Tooltip', 'Interpretation of CSV/TXT/DAT pattern files.', 'ValueChangedFcn', fcn);
        end

        function build(app)
            u = struct(); A = @(varargin) app.add(varargin{:}); C = @(fn) app.cb(fn);
            L = @(p, txt, r, c, varargin) A(p, @uilabel, r, c, 'Text', txt, 'HorizontalAlignment', 'right', varargin{:});
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.Version], 'Visible', 'off', ...
                'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) app.delete());
            root = uigridlayout(app.UIFigure, [1 1]); u.tabs = uitabgroup(root);
            u.mainTab = uitab(u.tabs, 'Title', 'Process Pattern 📡'); u.covTab = uitab(u.tabs, 'Title', 'Compute Coverage 📈');
            G = uigridlayout(u.mainTab, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});

            % ── Inputs & parameters
            P = uigridlayout(A(G, @uipanel, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️'), 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            L(P, 'Input Pattern:', 1, 1); u.path = A(P, @uieditfield, 1, [2 8]);
            u.ffdLabel = L(P, 'FFD Freq:', 1, 9, 'Visible', 'off');
            u.ffd = A(P, @uidropdown, 1, 10, 'Items', {'—'}, 'Visible', 'off', 'ValueChangedFcn', C(@() app.onFFD()));
            u.load = A(P, @uibutton, 1, [11 12], 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', C(@() app.onLoad()));
            u.process = A(P, @uibutton, 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', C(@() app.onProcess()));
            u.reset = A(P, @uibutton, 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', C(@() app.onResetParams()));
            u.fmtLabel = L(P, 'Format:', 2, [4 5], 'Visible', 'off');
            u.fmt = app.formatDropdown(P, C(@() app.onFmtChanged())); u.fmt.Layout.Row = 2; u.fmt.Layout.Column = [6 8]; u.fmt.Visible = 'off';
            u.step = A(P, @uidropdown, 2, [9 10], 'Items', {'STEP'}, 'Visible', 'off', 'Enable', 'off', 'ValueChangedFcn', C(@() app.process(true)));
            u.export = A(P, @uibutton, 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', C(@() app.exportResults()));
            u.exportUAN = A(P, @uibutton, 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', C(@() app.exportUAN()));
            u.rxL = L(P, 'Rw Sense', 3, 1); u.rx = A(P, @uidropdown, 3, 2, 'Items', {'Auto', 'RHCP', 'LHCP'});
            u.rwL = L(P, 'Rw (dB)', 3, 3); u.rw = A(P, @uispinner, 3, 4, 'Value', 6);
            u.lossL = L(P, 'Loss (−) / Gain (+) dB', 3, 5); u.loss = A(P, @uispinner, 3, 6, 'Step', 0.1);
            u.ptL = L(P, 'Tx Pwr (Pt)', 3, 7); u.pt = A(P, @uispinner, 3, 8); u.ptU = A(P, @uidropdown, 3, 9, 'Items', {'dBW', 'dBm', 'Watts'});
            u.rL = L(P, 'Distance', 3, 10); u.r = A(P, @uispinner, 3, 11, 'Value', 1); u.rU = A(P, @uidropdown, 3, 12, 'Items', {'m', 'km'});
            u.covBtn = A(P, @uibutton, 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', C(@() app.toCoverage()));
            set([u.rxL u.rx u.rwL u.rw u.lossL u.loss u.ptL u.pt u.ptU u.rL u.r u.rU], 'Visible', 'off');

            % ── Full antenna pattern (5 tabs, each with its own range slider + spinners)
            u.fullPanel = A(G, @uipanel, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off');
            u.fullTabs = uitabgroup(uigridlayout(u.fullPanel, [1 1]));
            names = {'Contour Plot', 'Circular Contour Plot', '3D Spherical Plot', '3D Polar Plot', '3D Surface Plot'}; axc = cell(1, 5);
            for k = 1:5
                g = uigridlayout(uitab(u.fullTabs, 'Title', names{k}), 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
                if k == 2, ax = polaraxes(g); else, ax = uiaxes(g); end
                ax.Layout.Row = [1 3]; ax.Layout.Column = 2; axc{k} = ax;
                u.fullMax(k) = A(g, @uispinner, 1, 1, 'Limits', app.Range, 'Value', 10, 'Step', 5, 'ValueChangedFcn', C(@(e) app.onRangeUI("full", 2, e)));
                u.fullSliders(k) = A(g, {@uislider, 'range'}, 2, 1, 'Limits', app.Range, 'Value', [-40 10], 'Orientation', 'vertical', 'ValueChangedFcn', C(@(e) app.onRangeUI("full", 0, e)));
                u.fullMin(k) = A(g, @uispinner, 3, 1, 'Limits', app.Range, 'Value', -40, 'Step', 5, 'ValueChangedFcn', C(@(e) app.onRangeUI("full", 1, e)));
            end
            [u.axCtr, u.axCir, u.axSph, u.axPol, u.axRect] = axc{:};

            % ── Antenna pattern cut
            u.cutPanel = A(G, @uipanel, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off');
            u.cutTabs = uitabgroup(uigridlayout(u.cutPanel, [1 1]));
            gp = uigridlayout(uitab(u.cutTabs, 'Title', 'Polar Cut Plot'), 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            u.axCutP = polaraxes(gp); u.axCutP.Layout.Row = [1 4]; u.axCutP.Layout.Column = 3;
            u.cutMax = A(gp, @uispinner, 1, 1, 'Limits', app.Range, 'Value', 10, 'Step', 5, 'ValueChangedFcn', C(@(e) app.onRangeUI("cut", 2, e)));
            u.cutSlider = A(gp, {@uislider, 'range'}, [2 3], 1, 'Limits', app.Range, 'Value', [-40 10], 'Orientation', 'vertical', 'ValueChangedFcn', C(@(e) app.onRangeUI("cut", 0, e)));
            u.cutMin = A(gp, @uispinner, 4, 1, 'Limits', app.Range, 'Value', -40, 'Step', 5, 'ValueChangedFcn', C(@(e) app.onRangeUI("cut", 1, e)));
            u.hpbwBtn = A(gp, {@uibutton, 'state'}, 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', C(@() app.onCutChanged()));
            u.hpbwLabel = A(gp, @uilabel, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            u.eGrid = uigridlayout(gp, [3 1]); u.eGrid.Layout.Row = 3; u.eGrid.Layout.Column = 4;
            u.cbTot = A(u.eGrid, @uicheckbox, 1, 1, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', C(@() app.onCutChanged()));
            u.cbCo = A(u.eGrid, @uicheckbox, 2, 1, 'Text', 'Co-pol', 'Value', true, 'ValueChangedFcn', C(@() app.onCutChanged()));
            u.cbCx = A(u.eGrid, @uicheckbox, 3, 1, 'Text', 'Cross-pol', 'Value', true, 'ValueChangedFcn', C(@() app.onCutChanged()));
            u.exportCut = A(gp, @uibutton, 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', C(@() app.exportCut()));
            u.axCutR = uiaxes(uigridlayout(uitab(u.cutTabs, 'Title', 'Rectangular Cut Plot'), [1 1]));

            % ── Plot control
            u.ctrlPanel = A(G, @uipanel, 2, [13 14], 'Title', 'Plot Control 🎨', 'Visible', 'off');
            K = uigridlayout(u.ctrlPanel, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', repmat({'fit'}, 1, 15));
            L(K, 'Component', 1, 1); u.comp = A(K, @uidropdown, 1, 2, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', C(@() app.onComponent()));
            L(K, 'Cut type', 2, 1); u.cutType = A(K, @uidropdown, 2, 2, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', C(@() app.onCutChanged(true)));
            L(K, 'Cut value', 3, 1); u.cutVal = A(K, @uispinner, 3, 2, 'Limits', [-360 360], 'ValueChangedFcn', C(@() app.onCutChanged()));
            L(K, 'Cut fields', 4, 1); u.basis = A(K, @uidropdown, 4, 2, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, ...
                'Enable', 'off', 'UserData', true, 'ValueChangedFcn', C(@() app.onBasis()));
            L(K, 'Colorbar max', 5, 1); u.cmax = A(K, @uispinner, 5, 2, 'Limits', app.Range, 'Value', 10, 'ValueChangedFcn', C(@() app.applyColorbar()));
            L(K, 'Colorbar min', 6, 1); u.cmin = A(K, @uispinner, 6, 2, 'Limits', app.Range, 'Value', -40, 'ValueChangedFcn', C(@() app.applyColorbar()));
            L(K, 'Colorbar step', 7, 1); u.cstep = A(K, @uispinner, 7, 2, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', C(@() app.applyFullRange()));
            L(K, 'Adjust Colorbar', 8, 1); u.applyC = A(K, @uibutton, 8, 2, 'Text', 'Apply', 'Tooltip', 'Apply min/max to the full-pattern and cut plots.', 'ButtonPushedFcn', C(@() app.applyColorbar()));
            L(K, '3D view', 9, 1); u.view3D = A(K, @uidropdown, 9, 2, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Value', 'iso', 'ValueChangedFcn', C(@() app.onView3D()));
            u.phiSpan = A(K, {@uiswitch, 'slider'}, 10, [1 2], 'Items', {'φ span: 0° to 360°', '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'ValueChangedFcn', C(@() app.onSpanChanged("phi")));
            u.thSpan = A(K, {@uiswitch, 'slider'}, 11, [1 2], 'Items', {'θ span: 0° to 180°', '−90° to 90°'}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'ValueChangedFcn', C(@() app.onSpanChanged("theta")));
            u.ehSwitch = A(K, {@uiswitch, 'slider'}, 12, [1 2], 'Items', {'E-Plane cut', 'H-Plane cut'}, 'ValueChangedFcn', C(@() app.onPlane()));
            u.overlay = A(K, @uicheckbox, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', C(@() app.overlayCut()));
            u.pob = A(K, @uicheckbox, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', C(@() app.onPOB()));
            u.hpbwBounds = A(K, @uicheckbox, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', C(@() app.plotCut()));

            % ── Data tables & status
            u.outFilter = A(G, @uidropdown, 3, [13 14], 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Visible', 'off', 'ValueChangedFcn', C(@() app.filterOutput()));
            u.dataTabs = A(G, @uitabgroup, 4, [1 14], 'Visible', 'off');
            u.tblOut = uitable(uigridlayout(uitab(u.dataTabs, 'Title', 'Results 📤'), [1 1]), 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnRearrangeable', 'on');
            u.tblIn = uitable(uigridlayout(uitab(u.dataTabs, 'Title', 'Input 📥'), [1 1]), 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnRearrangeable', 'on');
            u.tblMeta = uitable(uigridlayout(uitab(u.dataTabs, 'Title', 'Metadata 📋'), [1 1]), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            u.status = A(G, @uilabel, 5, [1 14], 'Interpreter', 'html', 'Text', 'Ready — load an antenna pattern file to begin 🚀');

            % ── Coverage tab
            CG = uigridlayout(u.covTab, 'ColumnWidth', {'1x'}, 'RowHeight', {'fit', '1x', 'fit'});
            Q = uigridlayout(A(CG, @uipanel, 1, 1, 'Title', 'Inputs & Parameters 🎛️'), 'ColumnWidth', [{'fit'} repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'});
            u.covType = A(Q, @uibuttongroup, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', C(@() app.covTypeChanged()));
            u.covSph = uiradiobutton(u.covType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            u.covCon = uiradiobutton(u.covType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            u.covOrientL = L(Q, 'Orientation 🧭:', 3, 1);
            u.covOrient = A(Q, @uidropdown, 3, 2, 'Items', [{'Auto'} app.Axes6.labels], 'ItemsData', 0:6, 'ValueChangedFcn', C(@() app.covOrientChanged()));
            u.covCompL = L(Q, 'Component:', 4, 1); u.covComp = A(Q, @uidropdown, 4, 2, 'Items', {'E_Total_dB'}, 'ValueChangedFcn', C(@() app.covCompChanged()));
            L(Q, 'Antenna Pattern:', 1, 3); u.covPath = A(Q, @uieditfield, 1, [4 8]);
            u.covLoad = A(Q, @uibutton, 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', C(@() app.covLoad()));
            u.covCompute = A(Q, @uibutton, 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'ButtonPushedFcn', C(@() app.covCompute()));
            L(Q, 'Threshold Min (dB):', 2, 3); u.thrMin = A(Q, @uispinner, 2, 4, 'Value', -40);
            L(Q, 'Threshold Max (dB):', 2, 5); u.thrMax = A(Q, @uispinner, 2, 6, 'Value', 10);
            L(Q, 'Step (dB):', 2, 7); u.thrStep = A(Q, @uispinner, 2, 8, 'Value', 1, 'Limits', [0.1 100]);
            u.covReset = A(Q, @uibutton, 2, 9, 'Text', '🔄 Reset', 'ButtonPushedFcn', C(@() app.covReset()));
            u.covExport = A(Q, @uibutton, 2, 10, 'Text', '💾 Export Results', 'ButtonPushedFcn', C(@() app.covExport()));
            u.coneThL = L(Q, 'Cone θ₀ (°):', 3, 3); u.coneTh = A(Q, @uispinner, 3, 4, 'Limits', [0 180]);
            u.conePhL = L(Q, 'Cone φ₀ (°):', 3, 5); u.conePh = A(Q, @uispinner, 3, 6, 'Limits', [0 360]);
            u.coneAL = L(Q, 'Cone Angle α (°):', 3, 7); u.coneA = A(Q, @uispinner, 3, 8, 'Limits', [0 180], 'Value', 45);
            u.covClear = A(Q, @uibutton, 3, 9, 'Text', '🧹 Clear DataTips', 'ButtonPushedFcn', C(@() app.covClear()));
            A(Q, @uibutton, 3, 10, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~, ~) set(u.tabs, 'SelectedTab', u.mainTab));
            L(Q, 'Coverage @ dB:', 4, 3); u.qCov = A(Q, @uispinner, 4, 4, 'ValueDisplayFormat', '%g dB');
            u.qCovBtn = A(Q, @uibutton, 4, 5, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', C(@() app.covQuery("cov")));
            L(Q, 'Threshold @ %:', 4, 6); u.qThr = A(Q, @uispinner, 4, 7, 'Value', 50, 'Limits', [0 100], 'ValueDisplayFormat', '%g%%');
            u.qThrBtn = A(Q, @uibutton, 4, 8, 'Text', '🔍 Query Threshold', 'ButtonPushedFcn', C(@() app.covQuery("thr")));
            u.covFmtL = L(Q, 'Format:', 4, 9, 'Visible', 'off');
            u.covFmt = app.formatDropdown(Q, C(@() app.covFmtChanged())); u.covFmt.Layout.Row = 4; u.covFmt.Layout.Column = 10; u.covFmt.Visible = 'off';
            u.covResults = A(CG, @uipanel, 2, 1, 'Title', 'Results', 'Visible', 'off');
            R = uigridlayout(u.covResults, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            u.axCov = A(R, @uiaxes, 1, [2 4]); title(u.axCov, 'Coverage vs Threshold'); xlabel(u.axCov, 'Threshold (dB)'); ylabel(u.axCov, 'Coverage (%)');
            u.axCov.Interactions = dataTipInteraction; hold(u.axCov, 'on'); grid(u.axCov, 'on'); set(u.axCov, 'YLim', [0 100], 'Box', 'on', 'Layer', 'top');
            u.covTree = A(R, {@uitree, 'checkbox'}, [1 2], 1, 'SelectionChangedFcn', C(@() app.covSelChanged()), 'CheckedNodesChangedFcn', C(@() app.covCheckChanged()));
            u.covRoot = uitreenode(u.covTree, 'Text', 'Coverage Results');
            u.covTable = A(R, @uitable, [1 2], 5, 'ColumnWidth', '1x', 'RowName', {});
            u.xMin = A(R, @uispinner, 2, 2, 'Limits', app.Range, 'Value', -40, 'ValueChangedFcn', C(@(e) app.covXFromSpinner(e)));
            u.xRange = A(R, {@uislider, 'range'}, 2, 3, 'Limits', app.Range, 'Value', [-40 10], ...
                'ValueChangedFcn', C(@(e) app.covSetX(e.Value, "slider")), 'ValueChangingFcn', C(@(e) app.covSetX(e.Value, "slider")));
            u.xMax = A(R, @uispinner, 2, 4, 'Limits', app.Range, 'Value', 10, 'ValueChangedFcn', C(@(e) app.covXFromSpinner(e)));
            u.covStatus = A(CG, @uilabel, 3, 1, 'Interpreter', 'html', 'Text', 'Ready 🚀');
            app.ui = u;
        end
    end
end

%% ═════════════════════════════════ I/O LAYER (UI-independent) ═════════════════════════════════
function out = readPattern(fp, textFormat, cached)
%READPATTERN Parse any supported source into out{rawTbl, blocks, freqs, meta}.
%   blocks{k}: table Theta, Phi + (Re_Eth, Im_Eth, Re_Eph, Im_Eph) or gain columns.  meta.isCoverage marks results files.
if nargin < 3, cached = table(); end
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, 'meta', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false));
switch ext
    case {'XLSX', 'XLS'},        out = readExcelMatrix(fp);
    case {'CSV', 'TXT', 'DAT'},  out = readGenericText(fp, string(textFormat), cached, out);
    case 'CUT',                  out = readGraspCut(fp, out);
    case 'FFD',                  out = readHfssFfd(fp, out);
    case {'UAN', 'FZ', 'OUT', 'FFS', 'FFE'}
        M = readNumeric(fp); M = M(:, 1:6); th = M(:, 1); ph = M(:, 2);
        switch ext
            case {'UAN', 'FZ'}   % Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
                names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}; out.meta.source = ['XGTD ' ext];
                Eth = magPhase(M(:, 3), M(:, 5)); Eph = magPhase(M(:, 4), M(:, 6));
            case 'OUT'           % Theta Phi Re/Im(RHCP) Re/Im(LHCP)
                names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; out.meta.source = 'TICRA/GRASP OUT';
                [Eth, Eph] = circ2lin(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)));
            case 'FFS'           % Phi Theta Re/Im(Eθ) Re/Im(Eφ)
                names = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; out.meta.source = 'CST FFS';
                ph = M(:, 1); th = M(:, 2); Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
            case 'FFE'           % Theta Phi Re/Im(Eθ) Re/Im(Eφ) [extra columns ignored]
                names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; out.meta.source = 'FEKO FFE';
                Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
        end
        out.rawTbl = array2table(M, 'VariableNames', names); out.blocks = {fieldTable(th, ph, Eth, Eph)};
    otherwise
        error('APAT:io:Unsupported', 'Unsupported file type: %s', ext);
end
end

function E = magPhase(dB, deg), E = 10.^(dB/20) .* exp(1i*deg2rad(deg)); end
function [Eth, Eph] = circ2lin(Ercp, Elcp), Eth = (Ercp + Elcp)/sqrt(2); Eph = (Ercp - Elcp)/(1i*sqrt(2)); end
function T = fieldTable(th, ph, Eth, Eph)
T = table(th(:), ph(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function M = readNumeric(fp, nHdr)
%READNUMERIC Delimited numeric block after nHdr header lines (auto-detected: first line with ≥ 4 numeric fields).
if nargin < 2
    num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?'; pat = ['^\s*' num '(?:[\s,;]+' num '){3,}\s*$'];
    fid = fopen(fp, 'r'); assert(fid > 0, 'APAT:io:Open', 'Cannot open file: %s', fp); c = onCleanup(@() fclose(fid)); nHdr = 0;
    while true
        ln = fgetl(fid); if ~ischar(ln) || ~isempty(regexp(ln, pat, 'once')), break; end
        nHdr = nHdr + 1;
    end
end
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, ...
    'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvartype(opts, opts.VariableNames, 'double');
M = readmatrix(fp, opts); M = M(~all(isnan(M), 2), :);
end

function out = readGenericText(fp, fmt, T, out)
%READGENERICTEXT CSV/TXT/DAT: coverage-results table, gain-only pattern, or 6-column E-field table (selected format).
if isempty(T)
    opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
    T = rmmissing(readtable(fp, opts));
end
nc = width(T); assert(nc >= 2 && height(T) > 0, 'APAT:io:Text', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHdr = ~all(startsWith(names, "Var")); c1 = T{:, 1}; c2 = T{:, 2};
covHdr = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
if (fmt == "gain" || nc < 6 || covHdr) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHdr, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:nc - 1))]; end
    out.rawTbl = T; out.meta.isCoverage = true; return
end
if fmt == "gain"                                  % the column with the wider span is φ
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; T = movevars(T, 'Theta', 'Before', 1);
    else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    out.rawTbl = T; out.blocks = {T}; out.meta.isGainOnly = true; out.meta.source = 'Generic text (gain)'; return
end
assert(nc >= 6, 'APAT:io:Text', 'The selected E-field text format requires six numeric columns.');
V = T{:, 3:6}; isMP = endsWith(fmt, "magphase"); layout = "";
if isMP                                           % grouped [m1 m2 p1 p2] vs interleaved [m1 p1 m2 p2]: phases exceed 100
    big = max(abs(V), [], 1, 'omitnan') > 100;
    if big(2) && ~big(3), V = V(:, [1 3 2 4]); layout = ", interleaved"; else, layout = ", grouped"; end
    c = {magPhase(V(:, 1), V(:, 3)), magPhase(V(:, 2), V(:, 4))};
else
    c = {complex(V(:, 1), V(:, 2)), complex(V(:, 3), V(:, 4))};
end
if startsWith(fmt, "linear"), [Eth, Eph] = deal(c{1}, c{2});
elseif startsWith(fmt, "rcp"), [Eth, Eph] = circ2lin(c{1}, c{2});
else, [Eth, Eph] = circ2lin(c{2}, c{1});
end
if ~hasHdr                                        % name the raw columns after the chosen interpretation
    lab = ["POL1", "POL2"]; if startsWith(fmt, "linear"), lab = ["E_TH", "E_PH"]; end
    if isMP, f = [lab + "_dB", lab + "_deg"]; if layout == ", interleaved", f = f([1 3 2 4]); end
    else, f = [lab(1) + ["_re", "_im"], lab(2) + ["_re", "_im"]]; end
    T.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", f]);
end
out.rawTbl = T; out.blocks = {fieldTable(c1, c2, Eth, Eph)}; out.meta.source = sprintf('Generic text (%s%s)', fmt, layout);
end

function out = readGraspCut(fp, out)
%READGRASPCUT TICRA cut: repeated blocks [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; V_NUM rows of 2·NCOMP values].
L = readlines(fp); L(strlength(strtrim(L)) == 0) = [];
th = {}; ph = {}; D = {}; i = 1; icomp = 1; icut = 1;
while i < numel(L)
    p = sscanf(L(i + 1), '%f'); assert(numel(p) >= 7, 'APAT:io:CUT', 'Could not parse the cut parameter line %d.', i + 1);
    n = p(3); icomp = p(5); icut = p(6);
    B = reshape(sscanf(strjoin(L(i + 2:i + 1 + n), ' '), '%f'), 2*p(7), []).';
    th{end + 1, 1} = p(1) + (0:n - 1).'*p(2); ph{end + 1, 1} = repmat(p(4), n, 1); D{end + 1, 1} = B(:, 1:4); i = i + 2 + n; %#ok<AGROW>
end
th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:});
if icut == 2, [th, ph] = deal(ph, th); end                              % ICUT = 2: φ swept at constant θ
neg = th < 0; th(neg) = -th(neg); ph(neg) = ph(neg) + 180;              % fold negative θ onto the opposite φ
if isscalar(unique(ph))                                                 % single cut → body of revolution (10° φ copies)
    k = numel(th); th = repmat(th, 36, 1); ph = repelem((0:10:350).', k); D = repmat(D, 36, 1);
end
c1 = complex(D(:, 1), D(:, 2)); c2 = complex(D(:, 3), D(:, 4));
if icomp == 2, [Eth, Eph] = circ2lin(c1, c2); names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'};
else, [Eth, Eph] = deal(c1, c2); names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; end
out.rawTbl = array2table([th ph D], 'VariableNames', [{'Theta', 'Phi'} names]);
out.blocks = {fieldTable(th, ph, Eth, Eph)}; out.meta.source = 'TICRA/GRASP CUT';
end

function out = readHfssFfd(fp, out)
%READHFSSFFD HFSS far field: "θ0 θ1 nθ / φ0 φ1 nφ / [Frequencies …]" header, then Re/Im(Eθ) Re/Im(Eφ) rows per block.
raw = readlines(fp); n = numel(raw); nHdr = 0; hdr = zeros(0, 3);
while size(hdr, 1) < 2 && nHdr < n                                      % two numeric triples, blank-line tolerant
    nHdr = nHdr + 1; v = sscanf(raw(nHdr), '%f').';
    if numel(v) == 3, hdr(end + 1, :) = v; elseif strlength(strtrim(raw(nHdr))) > 0, break; end %#ok<AGROW>
end
assert(size(hdr, 1) == 2, 'APAT:io:FFD', 'FFD header (theta/phi ranges) not found.');
freqs = [];
if nHdr < n                                                             % optional "Frequencies f1 f2 …" (a bare count is ignored)
    tok = regexp(char(strtrim(raw(nHdr + 1))), '^frequenc\w*\s+(.+)$', 'tokens', 'once', 'ignorecase');
    if ~isempty(tok), nHdr = nHdr + 1; f = sscanf(tok{1}, '%f'); if numel(f) > 1, freqs = f(:).'; end, end
end
M = readNumeric(fp, nHdr); sep = isnan(M(:, 1)); sf = M(sep, 2); freqs = [freqs, sf(~isnan(sf)).'];   % "Frequency f" separator rows
F = M(~sep, 1:4);
thA = linspace(hdr(1, 1), hdr(1, 2), round(hdr(1, 3))).'; phA = linspace(hdr(2, 1), hdr(2, 2), round(hdr(2, 3))).';
nPts = numel(thA)*numel(phA); nBlk = size(F, 1)/nPts;
assert(nBlk == round(nBlk) && nBlk >= 1, 'APAT:io:FFD', 'FFD row count does not match the theta/phi grid.');
freqs(end + 1:nBlk) = NaN; freqs = freqs(1:nBlk);
th = repelem(thA, numel(phA)); ph = repmat(phA, numel(thA), 1); out.blocks = cell(1, nBlk);
for k = 1:nBlk
    B = F((k - 1)*nPts + (1:nPts), :); out.blocks{k} = fieldTable(th, ph, complex(B(:, 1), B(:, 2)), complex(B(:, 3), B(:, 4)));
end
out.freqs = freqs; out.rawTbl = out.blocks{1}; out.meta.source = 'HFSS FFD'; out.meta.isDep = nBlk > 1 || any(isfinite(freqs));
end

function out = readExcelMatrix(fp)
%READEXCELMATRIX Matrix-template workbook: sheet 1 = summary; fixed component sheets hold C3-origin matrices
%   (row 2 = φ axis from column C, column B = θ axis from row 3) of dBi magnitude / degree phase.
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"];
lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'APAT:io:Excel', 'Workbook lacks the fixed Etheta/Ephi or RHCP/LHCP component sheets.');
need = strings(1, 0); if hasL, need = [need lin]; end; if hasC, need = [need circ]; end
M = struct(); axesRef = {};
for s = need
    [th, ph, D] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, s), 1)));
    if isempty(axesRef), axesRef = {th, ph}; else, assert(isequal(axesRef, {th, ph}), 'APAT:io:Excel', 'All component sheets must share one theta/phi grid.'); end
    M.(char(s)) = D;
end
if hasL, Eth = magPhase(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = magPhase(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees);
else, [Eth, Eph] = circ2lin(magPhase(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), magPhase(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees)); end
[thG, phG] = ndgrid(axesRef{1}, axesRef{2}); blk = fieldTable(thG, phG, Eth, Eph); raw = blk;
for s = need, raw.(char(s)) = reshape(M.(char(s)), [], 1); end
fmtName = {'Excel Matrix Format 1 (Eth/Eph)', 'Excel Matrix Format 2 (RHCP/LHCP)', 'Excel Matrix Format 3 (Eth/Eph + RHCP/LHCP)'};
meta = readExcelSummary(fp, sheets(1)); meta.source = fmtName{hasL + 2*hasC}; meta.isGainOnly = false; meta.isCoverage = false; meta.isDep = false;
freq = NaN; if isfield(meta, 'frequencyMHz'), freq = meta.frequencyMHz*1e6; end
out = struct('rawTbl', raw, 'blocks', {{blk}}, 'freqs', freq, 'meta', meta);
end

function [th, ph, D] = readMatrixSheet(fp, sheet)
C = readcell(fp, 'Sheet', char(sheet)); isNum = @(c) cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), c);
assert(all(size(C) >= 3), 'APAT:io:Excel', 'Sheet "%s" lacks a C3-origin matrix.', sheet);
pm = isNum(C(2, 3:end)); tm = isNum(C(3:end, 2));
nP = find(~pm, 1) - 1; if isempty(nP), nP = numel(pm); end            % contiguous numeric prefix of each axis
nT = find(~tm, 1) - 1; if isempty(nT), nT = numel(tm); end
assert(nP > 0 && nT > 0 && ~any(pm(nP + 1:end)) && ~any(tm(nT + 1:end)), 'APAT:io:Excel', 'Sheet "%s" has a gap in its theta/phi axis.', sheet);
ph = cell2mat(C(2, 3:2 + nP)); ph = ph(:); th = cell2mat(C(3:2 + nT, 2)); th = th(:); Dc = C(3:2 + nT, 3:2 + nP);
assert(all(isNum(Dc), 'all'), 'APAT:io:Excel', 'Sheet "%s" contains non-numeric matrix samples.', sheet);
D = cell2mat(Dc);
assert(all(diff(th) > 0) && all(diff(ph) > 0) && th(1) >= 0 && th(end) <= 180 && ph(1) >= 0 && ph(end) < 360, ...
    'APAT:io:Excel', 'Sheet "%s": axes must increase within theta 0..180 and phi 0..<360.', sheet);
end

function meta = readExcelSummary(fp, sheet)
%READEXCELSUMMARY Harvest "Label:" → value pairs (column B → first filled C..E) from the template summary sheet.
meta = struct();
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
for r = 1:size(C, 1)
    lab = C{r, 2}; if ~(ischar(lab) || isstring(lab)) || strlength(strtrim(string(lab))) == 0, continue; end
    v = C(r, 3:min(end, 5)); v = v(cellfun(@filled, v)); if isempty(v), continue; end
    key = regexprep(lower(regexprep(strtrim(char(lab)), '[^a-zA-Z0-9]+', '_')), '_+$', '');
    if ~isempty(key), meta.(matlab.lang.makeValidName(key)) = v{1}; end
end
keys = string(fieldnames(meta)); k = keys(contains(keys, "simulation_freq"));
if ~isempty(k), meta.frequencyMHz = str2double(string(meta.(k(1)))); end
end

function tf = filled(x)
%FILLED True for a readcell value that carries information (not empty, not <missing>/NaN).
tf = ~isempty(x); if tf, try, tf = ~all(ismissing(x), 'all'); catch, end, end
end

%% ═════════════════════════════════ MATH KERNEL (pure functions, physical coordinates) ═════════════════════════════════
function T = normalizePattern(T)
%NORMALIZEPATTERN Canonical sphere: Theta∈[0,180], Phi∈[0,360) + one closing Phi = 360 copy of Phi = 0.
%   Angles are rounded to 1e-5° to remove floating-point seam artefacts; FIELD VALUES ARE NEVER ROUNDED.
th = round(T.Theta, 5); ph = round(T.Phi, 5);
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, th = 90 - th;                              % elevation-style source
    else, neg = th < 0; th(neg) = -th(neg); ph(neg) = ph(neg) + 180; end           % signed polar source
end
th = mod(th, 360); over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;
T.Theta = th; T.Phi = mod(ph, 360);
[~, keep] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(keep, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function R = resampleTo1deg(T)
%RESAMPLETO1DEG Resample canonical primitives onto the 1° sphere.  E-field: Re/Im interpolated linearly;
%   gain-only: interpolated as linear power.  Regular grids use interp2 with periodic φ, irregular ones scatteredInterpolant.
gainOnly = isfield(T.Properties.UserData, 'isGainOnly') && T.Properties.UserData.isGainOnly;
S = T(T.Phi < 360, :); th = S.Theta; ph = S.Phi;
[qPh, qTh] = meshgrid(0:360, 0:180); R = table(qTh(:), qPh(:), 'VariableNames', {'Theta', 'Phi'});
uT = unique(th); uP = unique(ph); regular = numel(uT)*numel(uP) == numel(th);
if regular
    [~, it] = ismember(th, uT); [~, ip] = ismember(ph, uP); idx = sub2ind([numel(uT) numel(uP)], it, ip);
    regular = numel(unique(idx)) == numel(idx); P = [uP; uP(1) + 360];
end
for name = string(S.Properties.VariableNames(3:end))
    nm = char(name); v = double(S.(nm)); if gainOnly, v = 10.^(v/10); end
    if regular
        G = nan(numel(uT), numel(uP)); G(idx) = v; G = [G, G(:, 1)];                 %#ok<AGROW> periodic φ closure
        q = interp2(P, uT, G, qPh, qTh, 'linear');
        miss = isnan(q); if any(miss(:)), qn = interp2(P, uT, G, qPh, qTh, 'nearest'); q(miss) = qn(miss); end
    else
        Fi = scatteredInterpolant(ph, th, v, 'linear', 'nearest'); q = Fi(qPh, qTh);
    end
    if gainOnly, q = 10*log10(max(q, realmin)); end
    R.(nm) = q(:);
end
R.Properties.UserData = T.Properties.UserData;
end

function [P, info] = calcPattern(S, prm, pct, excess)
%CALCPATTERN Canonical source → processed table (physical coordinates) + peak / polarization summary.
meta = S.Properties.UserData;
info = struct('pol', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
if meta.isGainOnly
    P = S; P{:, 3:end} = P{:, 3:end} + prm.Loss_dB; g = P{:, 3};
else
    k = 10^(prm.Loss_dB/20); Eth = complex(S.Re_Eth, S.Im_Eth)*k; Eph = complex(S.Re_Eph, S.Im_Eph)*k;
    Er = (Eth + 1i*Eph)/sqrt(2); El = (Eth - 1i*Eph)/sqrt(2);
    [mT, mP, mR, mL] = deal(abs(Eth), abs(Eph), abs(Er), abs(El)); g = 10*log10(max(mT.^2 + mP.^2, eps));
    % Dominant polarization from mean component power → co/cross ordering, label and Auto Rx sense.
    pw = [mean(mT.^2, 'omitnan'), mean(mP.^2, 'omitnan'), mean(mR.^2, 'omitnan'), mean(mL.^2, 'omitnan')];
    if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
    if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
    if max(pw(3:4)) > max(pw(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
    elseif pw(1) >= pw(2), info.pol = 'Linear (Vertical)'; else, info.pol = 'Linear (Horizontal)'; end
    % Signed axial ratio: + right-hand, − left-hand; equal circular components = linear limit → −100 dB floor.
    d = mR - mL; sense = sign(d); ar = (mR + mL)./max(abs(d), eps);
    arDB = min(20*log10(ar), 250).*sense; arDB(abs(d) <= eps*max(mR + mL, 1)) = -100;
    % Polarization loss factor against an incident wave of axial ratio Rw (worst-case tilt: cos 2Δτ = −1).
    if prm.RxMode == "Auto", ws = 2*(info.pairs.Circular(1) == "E_RCP") - 1; elseif prm.RxMode == "RHCP", ws = 1; else, ws = -1; end
    ra = ar.*sense; ra(sense == 0) = 1e12; rw = ws*10^(prm.RxAR_dB/20);
    plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1))./(2*(ra.^2 + 1)*(rw^2 + 1)); plfDB = 10*log10(min(max(plf, eps), 1));
    eirp = prm.Pt_dBW + g; eirpW = 10.^(eirp/10); dB = @(m) 20*log10(max(m, eps)); phs = @(z) rad2deg(angle(z));
    P = table(S.Theta, S.Phi, g, arDB, dB(mR), dB(mL), plfDB, g + plfDB, dB(mT), dB(mP), phs(Eth), phs(Eph), phs(Er), phs(El), ...
        eirp, eirpW/(4*pi*prm.R_m^2), sqrt(30*eirpW)/prm.R_m, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', ...
        'PLF_dB', 'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
    P.Properties.UserData = meta;
end
info.peak = resolvePeak(g, pct, excess); info.POB = info.peak.value;
info.POBth = P.Theta(info.peak.index); info.POBph = P.Phi(info.peak.index);
end

function pk = resolvePeak(v, pct, excess)
%RESOLVEPEAK Outlier-robust peak: the raw maximum is accepted unless it exceeds the P(pct) level by more than
%   `excess` dB; then the highest sample at/below that level is the peak and everything above it is an outlier.
v = double(v(:)); pk = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlier', false(size(v)), 'adjusted', false);
if ~any(isfinite(v)), return; end
[pk.rawValue, pk.rawIndex] = max(v, [], 'omitnan'); pk.value = pk.rawValue; pk.index = pk.rawIndex;
lvl = percentile(v, pct);
if pk.rawValue > lvl + excess
    pk.outlier = v > lvl; c = v; c(pk.outlier | ~isfinite(v)) = -Inf; [pk.value, pk.index] = max(c); pk.adjusted = true;
end
end

function q = percentile(v, p)
%PERCENTILE Toolbox-free equivalent of prctile (sorted samples at (i−0.5)/n, linear in between, clamped at the ends).
v = sort(v(isfinite(v))); n = numel(v); if n == 0, q = NaN; return; end
q = interp1([0, 100*((1:n) - 0.5)/n, 100], [v(1); v(:); v(end)], p);
end

function w = solidWeights(th, ph)
%SOLIDWEIGHTS Exact solid angle of each uniform θ×φ cell; the closing φ = 360 seam column carries zero weight.
dT = gridStep(th); dP = gridStep(mod(ph, 360)); if isnan(dT), dT = 180; end; if isnan(dP), dP = 360; end
w = (cosd(max(th - dT/2, 0)) - cosd(min(th + dT/2, 180)))*deg2rad(dP); w(ph >= 360 - 1e-9) = 0;
end

function s = gridStep(v)
%GRIDSTEP Smallest positive spacing of the unique finite values (NaN when there is none).
d = diff(unique(v(isfinite(v)))); d = d(d > 1e-9); s = min([d(:); NaN]);
end

function c = cutRows(T, type, req)
%CUTROWS Rows and circular angle (0 ≤ a < 360) of one full-circle cut through the PHYSICAL (Theta, Phi) table.
%   "Phi": constant-θ ring (angle = φ).  "Theta": great circle through φ0 and φ0+180 (angle = θ, then 360−θ).
if type == "Phi"
    u = unique(T.Theta); [snap, k] = min(abs(u - req)); c.fixed = u(k);
    rows = find(T.Theta == c.fixed & T.Phi < 360); [ang, o] = sort(T.Phi(rows)); rows = rows(o); c.symbol = 'θ';
else
    u = unique(T.Phi(T.Phi < 360)); [snap, k] = min(abs(mod(u - mod(req, 360) + 180, 360) - 180)); c.fixed = u(k);
    [~, k2] = min(abs(mod(u - c.fixed, 360) - 180));
    r1 = find(T.Phi == c.fixed); r2 = find(T.Phi == u(k2) & T.Theta > 0 & T.Theta < 180);
    [t1, o1] = sort(T.Theta(r1)); [t2, o2] = sort(T.Theta(r2), 'descend');
    rows = [r1(o1); r2(o2)]; ang = [t1; 360 - t2]; c.symbol = 'φ';
end
c.rows = rows; c.angle = ang; c.snapped = snap > 1e-9; c.type = type;
end

function [a, V] = closeCircle(a, V, lo)
%CLOSECIRCLE Map a periodic sample sequence into [lo, lo+360], sort, de-duplicate and close it at both ends
%   (interpolating the wrap point when no sample falls exactly on the window edge).
a = mod(a - lo, 360) + lo; [a, o] = unique(a); V = V(o, :); hi = lo + 360;
if a(1) - lo > 1e-9
    w = (hi - a(end))/(a(1) + 360 - a(end)); v0 = V(end, :) + w*(V(1, :) - V(end, :));
    a = [lo; a; hi]; V = [v0; V; v0];
else
    a = [a; hi]; V = [V; V(1, :)];
end
end

function [bw, lo, hi] = calcHPBW(a, g, pk, pa)
%CALCHPBW Half-power beamwidth of a circular cut: first −3 dB crossings either side of the peak (linear interpolation).
[bw, lo, hi] = deal(NaN); ok = isfinite(a) & isfinite(g); a = a(ok); g = g(ok); if numel(g) < 3, return; end
if nargin < 3 || isempty(pk), [pk, i] = max(g); pa = a(i); end
[ra, o] = sort(mod(a - pa + 180, 360) - 180); rg = g(o) - (pk - 3);           % angle relative to the peak, gain relative to −3 dB
Lk = find(ra < 0 & rg <= 0, 1, 'last'); Rk = find(ra > 0 & rg <= 0, 1, 'first');
if isempty(Lk) || isempty(Rk) || Lk + 1 > numel(rg) || Rk - 1 < 1 || rg(Lk + 1) == rg(Lk) || rg(Rk - 1) == rg(Rk), return; end
x = @(i, j) ra(i) - rg(i)*(ra(j) - ra(i))/(rg(j) - rg(i));                    % zero crossing between outside i and inside j
lo = pa + x(Lk, Lk + 1); hi = pa + x(Rk, Rk - 1); bw = hi - lo;
end

function k = calcOrientation(T, g, w, pk, A)
%CALCORIENTATION Principal axis (±X/±Y/±Z) whose 45° cone captures the most peak-normalised radiated power.
if pk.adjusted, g(pk.outlier) = NaN; end
sw = 10.^((g - pk.value)/10).*w; sw(~isfinite(sw)) = 0;
V = [sind(A.theta(:)).*cosd(A.phi(:)), sind(A.theta(:)).*sind(A.phi(:)), cosd(A.theta(:))];
S = [sind(T.Theta).*cosd(T.Phi), sind(T.Theta).*sind(T.Phi), cosd(T.Theta)];
[~, k] = max(sw.'*double(S*V.' >= cosd(45)));
end

function m = calcMetrics(T, g, w, pk, ax, A)
%CALCMETRICS Directivity, efficiency, front-to-back, E/H-plane HPBW and AR at the peak (physical coordinates).
i = pk.index; gm = g; if pk.adjusted, gm(pk.outlier) = NaN; end
Pint = sum(10.^(gm/10).*w, 'omitnan');
m.PeakGain_dB = pk.value; m.PeakTheta_deg = T.Theta(i); m.PeakPhi_deg = T.Phi(i);
m.PeakDirectivity_dB = 10*log10(max(4*pi*10^(pk.value/10)/max(Pint, eps), eps));
m.Efficiency_pct = 100*Pint/(4*pi); if m.Efficiency_pct > 100, m.Efficiency_pct = NaN; end
sep = cosd(T.Theta)*cosd(T.Theta(i)) + sind(T.Theta)*sind(T.Theta(i)).*cosd(T.Phi - T.Phi(i));
[~, back] = min(sep); m.FrontBack_dB = pk.value - g(back);
e = cutRows(T, "Theta", A.phi(ax));                                          % E-plane: great circle through the boresight axis
if A.theta(ax) == 90, h = cutRows(T, "Phi", 90); else, h = cutRows(T, "Theta", mod(A.phi(ax) + 90, 360)); end
m.HPBW_EPlane_deg = calcHPBW(e.angle, g(e.rows)); m.HPBW_HPlane_deg = calcHPBW(h.angle, g(h.rows));
m.AxialRatioAtPeak_dB = NaN; if ismember('AR_dB', T.Properties.VariableNames), m.AxialRatioAtPeak_dB = T.AR_dB(i); end
end

function cov = coverageCCDF(g, mask, thr, w)
%COVERAGECCDF Coverage(T) [%] = 100 · Σ I(G_i > T)·Ω_i / Σ Ω_i over the region (vectorised over all thresholds).
ok = mask(:) & isfinite(g(:)) & isfinite(w(:)) & w(:) >= 0; g = g(ok); w = w(ok); thr = thr(:);
cov = zeros(size(thr)); if isempty(g) || sum(w) <= 0, return; end
cov = 100*(w.'*double(g > thr.')).'/sum(w);
end

function b = displayRange(v, pct, excess)
%DISPLAYRANGE 50-dB window whose top is the effective peak rounded up to 5 dB (shared by colour scale and coverage preset).
pk = resolvePeak(v(isfinite(v)), pct, excess);
if ~isfinite(pk.value), b = [-50 0]; return; end
top = min(100, max(-200, ceil(pk.value/5)*5)); b = [top - 50, top];
end

function [cols, labels] = componentMap(T)
%COMPONENTMAP Plottable columns and their labels (gain-only sources expose every data column).
cols = T.Properties.VariableNames(3:end); labels = cols;
if ~T.Properties.UserData.isGainOnly
    all_ = {'E_Total_dB', 'E_TH_dB', 'E_PH_dB', 'E_RCP_dB', 'E_LCP_dB', 'AR_dB', 'Gain_PolCorrected_dB'};
    lab = {'Total Gain', 'Etheta Gain', 'Ephi Gain', 'RHCP Gain', 'LHCP Gain', 'Axial Ratio', 'Polarized Gain'};
    keep = ismember(all_, cols); cols = all_(keep); labels = lab(keep);
end
end

function c = pickComponent(prev, cols)
if any(strcmp(cols, prev)), c = prev; elseif any(strcmp(cols, 'E_Total_dB')), c = 'E_Total_dB'; else, c = cols{1}; end
end

function t = niceTicks(lim, step)
%NICETICKS The limits plus every multiple of step inside them (empty when invalid or too dense).
t = []; if ~isfinite(step) || step <= 0 || diff(lim) <= 0, return; end
t = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)]); if numel(t) > 60, t = []; end
end

function s = fmt(v, n)
%FMT Compact number text: up to 2 decimals with trailing zeros trimmed, or exactly n decimals; 'n/a' when not finite.
if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return; end
if nargin < 2, s = regexprep(regexprep(sprintf('%.2f', v), '\.?0+$', ''), '^-0$', '0'); else, s = sprintf('%.*f', n, v); end
end