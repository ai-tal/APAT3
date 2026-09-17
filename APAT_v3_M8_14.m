classdef APAT_v3_M8_14 < matlab.apps.AppBase %1714-lines %Issues %1.POB DataTip issue (if POB DataTip enabled, then user right Click and Delete Tips using custom context menu, it delete all DatTips as expected, but if user disable then re-enable the POB DatTip, the POB DatTip doesn't show anymore!) %2. Coverage Threshold Query snaps to nearest Data Point instead of returning requested point! %3. When user change Coverage Cone coordinate while Conical Coverage Orientation drop-down on Auto, it computes Auto Coverage instead of the adjusted Cone values/coordinates
% APAT v3 M8 — Antenna Pattern Analyzer Tool (consolidated architecture).
%
%   Pipeline (one direction, one owner per stage):
%     file ──readPattern──▶ blocks ──normalizePattern──▶ stdTbl ──calcPattern──▶ patTbl
%           ──applyStep (optional 1° resample of the *canonical* source)──▶ viewBaseTbl
%           ──applyAngularSpan (display convention only)──▶ viewTbl ──▶ tables / plots / coverage
%
%   Layout of this file:  properties · lifecycle · pipeline · view state · renderers · annotations ·
%   tables/metadata/export · coverage tab · UI construction · local I/O functions · local math functions.
%   Everything numerical lives in pure local functions that never receive the app object.

    properties (Access = public)
        UIFigure matlab.ui.Figure
        ui struct = struct()   % Every UI control handle, keyed by a short name (built in createUI)
        full struct            % Full-pattern tab registry: tab / axes / slider / min / max / render / view
    end

    properties (Access = private)
        % Source & pipeline tables
        file struct = struct('path', '', 'folder', '', 'base', '', 'name', '')
        rawTbl table                        % Data as found in the file (Input tab)
        stdTbl table                        % Canonical E-field / gain table (normalizePattern)
        patTbl table                        % Processed pattern at native resolution (calcPattern)
        viewBaseTbl table                   % Processed pattern at the selected step (native or 1°)
        viewTbl table                       % viewBaseTbl in the selected display convention (span / elevation)
        uanTbl table                        % Lazily built UAN export table
        blocks cell = {}                    % One canonical block per FFD frequency
        freqs double = NaN                  % Block frequencies (Hz)
        srcUD struct = struct()             % Source metadata from the reader
        viewRev double = 0                  % Increments whenever viewTbl is rebuilt
        % Derived view state
        grid struct = struct()              % Cached (theta x phi) topology, geometry and component matrices of viewTbl
        peak struct = struct()              % Peak policy result for the selected component
        POB = NaN; POBth = NaN; POBph = NaN % Peak-of-beam value / physical theta / phi
        polLabel char = 'n/a'
        polPairs struct = struct('Linear', ["E_TH","E_PH"], 'Circular', ["E_RCP","E_LCP"])   % Co/cross ordering
        boresight double = 1                % Index into Axes (detected principal axis)
        metrics struct = struct()
        solidAngle double = []              % dOmega per viewTbl row
        gainLim double = [-40 10]           % Authoritative non-AR colour scale (survives AR excursions)
        fullLim double = [-40 10]           % Current full-pattern colour scale
        cutLim double = [-40 10]            % Current cut-plot range
        defaults cell = {}                  % Startup values of the parameter controls
        rawShown logical = false
        filterStyles cell = {}
        % Coverage tab
        covRunID double = 0
        covJobs = matlab.ui.container.TreeNode.empty   % Job-node registry (the tree is the view)
        covPreset string = ""               % pattern|component|view key of the last threshold preset
        covPresetDone logical = false
        covXInit logical = false            % Coverage X-axis baseline established
        % Lifecycle
        isClosing logical = false
        statusTimer = []
        opDialog = []
        perfMark = @(~) []                  % Stage recorder (no-op when idle)
    end

    properties (Constant, Access = private)
        Axes = struct('labels', {{'+Z','-Z','+X','-X','+Y','-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        Comps = ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","AR_dB","Gain_PolCorrected_dB"]
        CompLabels = ["Total Gain","Etheta Gain","Ephi Gain","RHCP Gain","LHCP Gain","Axial Ratio","Polarized Gain"]
        Hidden = {'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'}
        PeakPct = 99.99; PeakExcess = 6; DBRange = [-250 100]
        OneDeg = ['STEP: 1' char(176)]
        FileFilter = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern/Gain Files'}
        CsvFilters = {'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}
    end

    %% ------------------------------------------------------------------ lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_14
            app.createUI(); registerApp(app, app.UIFigure); runStartupFcn(app, @(a) a.startup());
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true;
            t = app.statusTimer; if ~isempty(t) && isvalid(t), stop(t); delete(t); end
            d = app.opDialog;    if ~isempty(d) && isvalid(d), delete(d); end
            if isgraphics(app.UIFigure), delete(app.UIFigure); end
        end

        function report = runSelfTest(app)
            %RUNSELFTEST Deterministic numerical / policy checks (errors when any check fails).
            [P, T] = meshgrid(0:30:330, (0:30:180)'); th = T(:); ph = P(:); w = solidWeights(th, ph);
            r.passSolidAngle = abs(sum(w) - 4*pi) < 1e-9;
            [pk, ax] = calcOrientation(th, ph, 10*cosd(th).^2, w, app.Axes, app.PeakPct, app.PeakExcess);
            r.passOrientation = isfinite(pk.value) && ax >= 1 && ax <= 6;
            [P2, T2] = meshgrid(0:2:358, (0:2:180)'); f = @(t, p) 12*cosd(t).^2 - 0.5*sind(p).^2;
            R = resampleCanonical(table(T2(:), P2(:), f(T2(:), P2(:)), 'VariableNames', {'Theta','Phi','E_Total_dB'}), 1);
            native = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0 & R.Phi < 360;
            r.passResampling = height(R) == 181*361 && all(isfinite(R.E_Total_dB));
            r.passNumericalEquivalence = max(abs(R.E_Total_dB(native) - f(R.Theta(native), R.Phi(native)))) < 1e-9;
            r.passVisualRange = isequal(peakWindow([3.2; -250; -17], app.PeakPct, app.PeakExcess), [-45 5]);
            spike = repmat(0.02, 100000, 1); spike(1) = 10.02; sp = resolvePeak(spike, app.PeakPct, app.PeakExcess);
            r.passIsolatedSpike = sp.wasAdjusted && abs(sp.value - 0.02) < 1e-12 && sp.rawIndex == 1 && ...
                isequal(peakWindow(spike, app.PeakPct, app.PeakExcess), [-45 5]);
            r.passARSemantic = all(arrayfun(@(s) app.isAR(s), ["AR", "AR_dB", "AR dB", "Axial Ratio", "Axial_Ratio"]));
            r.passCCDF = max(abs(coverageCCDF([0; 10; 20], true(3, 1), [5; 15; 25], [1; 1; 1]) - [200/3; 100/3; 0])) < 1e-12;
            ffd = [tempname '.ffd']; writelines(["0 180 3"; "-180 180 3"; compose('%d 0 0 1', (1:9)')], ffd); c = onCleanup(@() delete(ffd));
            d = readPattern(ffd, 'ffd', table());
            r.passFFDReader = strcmp(d.userData.source, 'HFSS FFD') && isscalar(d.blocks) && height(d.blocks{1}) == 9;
            names = fieldnames(r); failed = names(~cellfun(@(k) r.(k), names)); report = r; report.pass = isempty(failed);
            if ~report.pass, error('apat:test:SelfTestFailed', 'Self-test failed: %s', strjoin(failed, ', ')); end
        end
    end

    methods (Access = private)
        function startup(app)
            u = app.ui;
            set([u.PolarCut, app.full(2).axes], 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            axesList = [app.full.axes, u.PolarCut, u.RectAxes];
            for k = 1:numel(axesList)   % Local gestures + one persistent "Delete DataTips" menu per axes (no per-render leaks)
                ax = axesList(k); enableDefaultInteractivity(ax);
                m = uicontextmenu(app.UIFigure); uimenu(m, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ~) delete(findall(ax, 'Type', 'datatip')));
                ax.ContextMenu = m;
                if isa(ax, 'matlab.graphics.axis.PolarAxes'), continue; end
                if any(k == 3:5), ax.Interactions = [rotateInteraction, dataTipInteraction]; else, ax.Interactions = [zoomInteraction, dataTipInteraction]; end
            end
            hold(u.CovAxes, 'on'); grid(u.CovAxes, 'on'); set(u.CovAxes, 'YLim', [0 100], 'Box', 'on', 'Layer', 'top');
            app.defaults = get(app.paramControls(), 'Value');
            app.covUI(); app.UIFigure.Visible = 'on';
        end

        function safe(app, fn, varargin)
            % Uniform callback guard: cancellation → status message, anything else → error dialog.
            try
                fn(varargin{:});
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.setStatus(app.ui.Status, 'Operation cancelled by user.', true);
                else, app.showError(ME); end
            end
        end

        function showError(app, ME)
            if app.isClosing || ~isvalid(app.UIFigure), return; end
            where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.UIFigure, [ME.message where], 'APAT Error', 'Icon', 'error');
        end

        function runOp(app, ttl, msg, fn)
            % Cancelable busy dialog + stage timing around a pipeline operation.
            dlg = uiprogressdlg(app.UIFigure, 'Title', ttl, 'Message', msg, 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            app.opDialog = dlg; cleaner = onCleanup(@() delete(dlg)); drawnow %#ok<NASGU>
            done = app.startPerf(ttl); fn(); done();
        end

        function checkCancelled(app)
            if ~isempty(app.opDialog) && isvalid(app.opDialog) && app.opDialog.CancelRequested
                app.opDialog.Message = 'Aborting...'; drawnow limitrate; error('APAT:Cancelled', 'Operation cancelled by user.');
            end
        end

        function done = startPerf(app, op)
            % Stage recorder; the report is written to the base workspace as Perf_<class>.
            stages = cell(0, 2); t0 = tic; t = tic; app.perfMark = @track; done = @finish;
            function track(s), stages(end+1, :) = {string(s), toc(t)}; t = tic; end
            function finish()
                app.perfMark = @(~) [];
                assignin('base', matlab.lang.makeValidName("Perf_" + class(app)), struct('Operation', string(op), ...
                    'Stages', cell2table(stages, 'VariableNames', {'Stage', 'Seconds'}), 'TotalSeconds', toc(t0)));
            end
        end

        function setStatus(app, label, msg, temporary)
            % Permanent messages become the label's restore point; temporary ones revert after 3 s (one shared timer).
            if app.isClosing || ~isgraphics(label), return; end
            label.Text = char(msg);
            if ~temporary, label.UserData = char(msg); return; end
            t = app.statusTimer;
            if isempty(t) || ~isvalid(t)
                t = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, 'TimerFcn', @(t, ~) app.restoreStatus(t)); app.statusTimer = t;
            end
            stop(t); t.UserData = label; start(t);
        end

        function restoreStatus(app, t)
            if app.isClosing, return; end
            label = t.UserData; if isgraphics(label) && ischar(label.UserData), label.Text = label.UserData; end
        end
    end

    %% ------------------------------------------------------------------ pipeline
    methods (Access = private)
        function onLoad(app)
            fp = strtrim(app.ui.Path.Value);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.file.path)
                [f, p] = uigetfile(app.FileFilter, 'Select an antenna pattern file'); if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            app.runOp('Loading Data', 'Reading file...', @() app.loadMain(fp));
        end

        function loadMain(app, fp)
            out = app.readSource(fp, app.ui.FormatLabel, app.ui.Format); app.perfMark("Read file"); app.checkCancelled();
            if out.userData.isCoverage   % Coverage-results files route to the Coverage tab without touching Main state.
                app.ui.Tabs.SelectedTab = app.ui.CovTab; app.ui.CovPath.Value = fp; app.covLoadResults(fp, out.rawTbl); return
            end
            app.ui.Path.Value = fp; [folder, base, ext] = fileparts(fp);
            app.file = struct('path', fp, 'folder', folder, 'base', base, 'name', [base ext]);
            app.activateSource(out);
            isDep = out.userData.isDep;
            if isDep
                items = compose('Pattern %d: %.4g GHz', (1:numel(out.blocks))', out.freqs(:)/1e9);
                items(isnan(out.freqs)) = compose('Pattern %d', find(isnan(out.freqs(:))));
                set(app.ui.FFD, 'Items', items, 'ItemsData', 1:numel(items), 'Value', 1);
            end
            set([app.ui.FFD, app.ui.FFDLabel], 'Visible', isDep, 'Enable', isDep);
            app.ui.Step.UserData = false; app.ui.CutBasis.UserData = true;   % New source: native step, auto cut basis
            app.refresh();
        end

        function out = readSource(app, fp, label, dropdown)
            % Generic text files expose the format selector (re-armed to 'gain'); every other format is self-describing.
            generic = isGenericText(fp); kind = string(dropdown.Value);
            if generic, kind = "gain"; dropdown.Value = 'gain'; end
            out = readPattern(fp, kind, table());
            set([label, dropdown], 'Visible', generic && ~out.userData.isCoverage);
        end

        function activateSource(app, out)
            [app.rawTbl, app.blocks, app.freqs, app.srcUD] = deal(out.rawTbl, out.blocks, out.freqs, out.userData);
            app.rawShown = false; app.selectBlock(1);
        end

        function selectBlock(app, k)
            B = app.blocks{k}; if app.srcUD.isDep, app.rawTbl = B; app.rawShown = false; end
            S = normalizePattern(B); S.Properties.UserData = app.srcUD; app.stdTbl = S;
        end

        function P = buildPattern(app, out)
            % Auxiliary pattern (Coverage tab) processed with the current parameters; never mutates Main state.
            S = normalizePattern(out.blocks{1}); S.Properties.UserData = out.userData;
            P = calcPattern(S, app.getParam());
        end

        function onProcess(app)
            if isempty(app.stdTbl), uialert(app.UIFigure, 'No file! Load a pattern first.', 'Warning', 'Icon', 'warning'); return; end
            app.ui.Step.UserData = strcmp(app.ui.Step.Value, app.OneDeg);   % Remember the 1° choice across reprocessing
            app.runOp('Processing', 'Re-processing pattern...', @() app.reprocess());
        end

        function reprocess(app)
            if isGenericText(app.file.path)   % Re-interpret the cached generic table with the selected format
                out = readPattern(app.file.path, app.ui.Format.Value, app.rawTbl);
                assert(~out.userData.isCoverage, 'The selected generic format identifies a coverage-results file.');
                app.activateSource(out);
            end
            app.refresh();
            app.setStatus(app.ui.Status, sprintf('Re-processed <b>%s</b> with current parameters ✅', app.file.name), true);
        end

        function onFormatChanged(app)
            if strcmp(strtrim(app.ui.Path.Value), app.file.path) && isGenericText(app.file.path)
                app.ui.CutBasis.UserData = true; app.onProcess();
            end
        end

        function onFFDChanged(app)
            k = app.ui.FFD.Value; app.ui.CutBasis.UserData = true; app.selectBlock(k); app.refresh();
            app.setStatus(app.ui.Status, sprintf('Switched to FFD block %d (%s).', k, app.ui.FFD.Items{k}), true);
        end

        function refresh(app)
            % Full recompute from stdTbl: pattern → step → span → view → plots. Called after load/process/block switch.
            [app.patTbl, info] = calcPattern(app.stdTbl, app.getParam());
            app.perfMark("Process pattern"); app.checkCancelled();
            [app.polLabel, app.polPairs] = deal(info.pol, info.pairs);
            hasE = ~app.srcUD.isGainOnly;
            if isequal(app.ui.CutBasis.UserData, true) && hasE, app.ui.CutBasis.Value = strtok(info.pol); end   % 'Linear' | 'Circular'

            steps = [gridStep(app.patTbl.Theta), gridStep(mod(app.patTbl.Phi, 360))]; steps(~isfinite(steps)) = 1;
            nonCanonical = any(abs(steps - 1) > 1e-9); keepOne = isequal(app.ui.Step.UserData, true) && nonCanonical;
            native = sprintf('STEP: %g%c', max(steps), char(176));
            set(app.ui.Step, 'Items', {native, app.OneDeg}, 'Visible', nonCanonical, 'Enable', nonCanonical, 'UserData', false);
            if keepOne, app.ui.Step.Value = app.OneDeg; else, app.ui.Step.Value = native; end
            app.ui.CutValue.Step = max(steps(1), 1);

            app.applyStep(); app.updateComponentItems(); app.perfMark("Prepare view"); app.checkCancelled();
            app.updateView(true, false, false); app.onEHPlane();   % tables, ranges, default E-plane cut
            drawnow limitrate; app.renderFull(); app.perfMark("Build plots");

            set([app.ui.PanelCut, app.ui.PanelFull, app.ui.PanelCtrl, app.ui.ExportOut, app.ui.ToCoverage], 'Visible', 'on');
            set([app.ui.ExportUAN, app.ui.EGrid, app.ui.ChkTotal, app.ui.ChkA, app.ui.ChkB], 'Visible', hasE);
            set([app.ui.ChkA, app.ui.ChkB, app.ui.CutBasis], 'Enable', hasE);
            app.updateInputVisibility();
            pol = ''; if hasE && ~strcmpi(app.polLabel, 'n/a'), pol = sprintf(' | Polarization <b>%s</b>', app.polLabel); end
            app.setStatus(app.ui.Status, sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)%s', ...
                app.file.name, fmt(app.POB, 2), fmt(app.POBth), fmt(app.POBph), pol), false);
        end

        function prm = getParam(app)
            u = app.ui; prm = struct('GainLoss_dB', u.Loss.Value, 'RxMode', string(u.RxPol.Value), 'RxAR_dB', u.Rw.Value);
            prm.FieldScale = 10^(prm.GainLoss_dB/20);
            switch u.PtUnit.Value
                case 'dBm',   prm.Pt_dBW = u.Pt.Value - 30;
                case 'Watts', prm.Pt_dBW = 10*log10(max(u.Pt.Value, eps));
                otherwise,    prm.Pt_dBW = u.Pt.Value;
            end
            prm.R_m = max(u.R.Value, 1e-12); if strcmp(u.RUnit.Value, 'km'), prm.R_m = 1000*prm.R_m; end
        end

        function h = paramControls(app), u = app.ui; h = [u.Loss, u.RxPol, u.Rw, u.Pt, u.PtUnit, u.R, u.RUnit]; end

        function resetParams(app)
            set(app.paramControls(), {'Value'}, app.defaults); if ~isempty(app.stdTbl), app.refresh(); end
        end

        function applyStep(app)
            % Optional 1° resampling of the CANONICAL source (never of derived dB quantities), then recompute.
            src = app.stdTbl; steps = [gridStep(src.Theta), gridStep(mod(src.Phi, 360))];
            if strcmp(app.ui.Step.Value, app.OneDeg) && any(~isfinite(steps) | abs(steps - 1) > 1e-9)
                if all(isfinite(steps) & steps < 1)   % Finer than 1°: decimate exactly onto integer degrees
                    src = src(all(abs([src.Theta, src.Phi] - round([src.Theta, src.Phi])) < 1e-9, 2), :);
                else
                    src = resampleCanonical(src, 1);
                end
                src.Properties.UserData = app.stdTbl.Properties.UserData;
                app.viewBaseTbl = calcPattern(src, app.getParam());
            else
                app.viewBaseTbl = app.patTbl;
            end
            app.applyAngularSpan();
        end

        function applyAngularSpan(app)
            % Materialize only the display convention (phi span / theta-vs-elevation); the canonical table is untouched.
            T = app.viewBaseTbl; signed = app.isSignedPhi(); elev = app.isElev();
            if signed
                T(abs(T.Phi - 360) <= 1e-9, :) = [];
                T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
                seam = T(abs(T.Phi - 180) < 1e-9, :); seam.Phi(:) = -180; T = [seam; T];
            end
            if elev, T.Theta = 90 - T.Theta; end
            ud = T.Properties.UserData; ud.elevation = elev; T.Properties.UserData = ud;
            if signed || elev, T = sortrows(T, {'Phi', 'Theta'}); end
            app.viewTbl = T; app.uanTbl = table(); app.grid = struct(); app.solidAngle = []; app.viewRev = app.viewRev + 1;
        end

        function onStepChanged(app), app.applyStep(); app.updateComponentItems(); app.updateView(true); end

        function onSpanChanged(app)
            if isempty(app.viewBaseTbl), return; end
            app.applyAngularSpan(); app.updateView();
        end

        function updateView(app, refreshRanges, renderFull, updateCut)
            % Derive everything that depends on (viewTbl, component): peak, boresight, metrics, ranges, tables, plots.
            if nargin < 2, refreshRanges = false; end; if nargin < 3, renderFull = true; end; if nargin < 4, updateCut = true; end
            T = app.viewTbl; comp = app.comp(); vars = T.Properties.VariableNames; th = app.physTheta(T); ph = T.Phi;
            if isempty(app.solidAngle), app.solidAngle = solidWeights(th, ph); end
            [app.peak, app.boresight] = calcOrientation(th, ph, T.(comp), app.solidAngle, app.Axes, app.PeakPct, app.PeakExcess);
            app.POB = app.peak.value; app.POBth = th(app.peak.index); app.POBph = mod(ph(app.peak.index), 360);
            total = comp; if ismember('E_Total_dB', vars), total = 'E_Total_dB'; end
            ar = []; if ismember('AR_dB', vars), ar = T.AR_dB; end
            app.metrics = calcMetrics(th, ph, T.(total), ar, app.solidAngle, app.Axes, app.boresight, app.PeakPct, app.PeakExcess);
            if refreshRanges
                if app.isAR(comp), lim = [-30 30]; else, app.gainLim = peakWindow(T.(total), app.PeakPct, app.PeakExcess); lim = app.gainLim; end
                app.setRange("all", lim, 0, false);
            end
            app.updateTables(); app.updateMetadata();
            if updateCut, app.updateCutControl(); app.plotCut(); end
            if renderFull, app.renderFull(); end
        end
    end

    %% ------------------------------------------------------------------ view state helpers
    methods (Access = private)
        function c = comp(app), c = app.ui.Component.Value; end
        function tf = isElev(app), tf = strcmp(app.ui.ThetaSpan.Value, '-90° to 90°'); end
        function tf = isSignedPhi(app), tf = strcmp(app.ui.PhiSpan.Value, '-180° to 180°'); end
        function xl = phiLimits(app), xl = [0 360] - 180*app.isSignedPhi(); end
        function s = thetaName(app), if app.isElev(), s = "Elevation"; else, s = "Theta"; end, end

        function tf = isAR(~, name)
            % AR semantics independent of column spelling: AR, AR_dB, AR dB, Axial Ratio, Axial_Ratio.
            key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', '');
            tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
        end

        function th = physTheta(~, T)
            % Physical polar theta regardless of the active display convention.
            th = T.Theta; ud = T.Properties.UserData;
            if isstruct(ud) && isfield(ud, 'elevation') && ud.elevation, th = 90 - th; end
        end

        function s = compLabel(app)
            dd = app.ui.Component; i = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(i), s = string(dd.Value); else, s = string(dd.Items{i}); end
        end

        function [cols, labels] = componentMap(app, T)
            cols = string(T.Properties.VariableNames(3:end)); labels = cols;
            if ~T.Properties.UserData.isGainOnly, keep = ismember(app.Comps, cols); cols = app.Comps(keep); labels = app.CompLabels(keep); end
        end

        function setComponentItems(app, dd, T, prefer)
            % Populate a component dropdown, keeping PREFER when available, else Total Gain, else the first column.
            [cols, labels] = app.componentMap(T); if isempty(cols), return; end
            [dd.Items, dd.ItemsData] = deal(cellstr(labels), cellstr(cols));
            pick = find(cols == string(prefer), 1); if isempty(pick), pick = find(cols == "E_Total_dB", 1); end; if isempty(pick), pick = 1; end
            dd.Value = char(cols(pick));
        end

        function updateComponentItems(app), app.setComponentItems(app.ui.Component, app.viewTbl, app.ui.Component.Value); end

        function [g, Z] = gridOf(app, col)
            % Rectangular (theta x phi) topology, geometry and per-component matrices of viewTbl; cached until the view changes.
            T = app.viewTbl; g = app.grid;
            if ~isfield(g, 'sz')
                g.theta = unique(T.Theta); g.phi = unique(T.Phi); g.sz = [numel(g.theta), numel(g.phi)];
                [~, it] = ismember(T.Theta, g.theta); [~, ip] = ismember(T.Phi, g.phi); g.index = sub2ind(g.sz, it, ip);
                [g.phiGrid, g.thetaGrid] = meshgrid(g.phi, g.theta);
                g.polar = g.thetaGrid; if app.isElev(), g.polar = 90 - g.polar; end
                g.phiRad = deg2rad(g.phiGrid); s = sind(g.polar);
                g.x = s.*cos(g.phiRad); g.y = s.*sin(g.phiRad); g.z = cosd(g.polar); g.data = struct();
            end
            key = matlab.lang.makeValidName(col);
            if ~isfield(g.data, key), Z = nan(g.sz); Z(g.index) = T.(col); g.data.(key) = Z; end
            Z = g.data.(key); app.grid = g;
        end

        function [R, scale] = polarRadius(~, Z, lim)
            % 3-D polar radius: linear in dB above the lower colour limit, normalized so the pattern maximum reaches 1.
            R = max(Z - lim(1), 0) / max(diff(lim), eps); scale = max(max(R, [], 'all', 'omitnan'), eps); R = R / scale;
        end

        function setRange(app, scope, value, part, apply)
            % One synchronizer for every slider/spinner range group. scope: "full" | "cut" | "all".
            % part: 0 = whole range (slider travel collapses to it), 1 = min, 2 = max, 3 = slider drag (travel kept).
            if nargin < 4, part = 0; end; if nargin < 5, apply = true; end
            if scope == "all"
                lim = clampRange(value, app.DBRange); [app.ui.Cmin.Value, app.ui.Cmax.Value] = deal(lim(1), lim(2));
                app.setRange("full", lim, 0, apply); app.setRange("cut", lim, 0, apply); return
            end
            if scope == "full", sliders = [app.full.slider]; mins = [app.full.min]; maxs = [app.full.max]; lim = app.fullLim;
            else, sliders = app.ui.CutSlider; mins = app.ui.CutMin; maxs = app.ui.CutMax; lim = app.cutLim; end
            if part == 1 || part == 2, lim(part) = double(value); else, lim = value; end
            lim = clampRange(lim, app.DBRange);
            travel = lim; if part ~= 0, travel = [min(sliders(1).Limits(1), lim(1)), max(sliders(1).Limits(2), lim(2))]; end
            set(sliders, 'Limits', app.DBRange, 'Value', lim); set(sliders, 'Limits', travel);
            set(mins, 'Limits', [app.DBRange(1), lim(2) - 1], 'Value', lim(1));
            set(maxs, 'Limits', [lim(1) + 1, app.DBRange(2)], 'Value', lim(2));
            if scope == "full", app.fullLim = lim; if ~app.isAR(app.comp()), app.gainLim = lim; end, else, app.cutLim = lim; end
            if ~apply || isempty(app.viewTbl), return; end
            if scope == "full", app.applyFullRange(); else, set(app.ui.PolarCut, 'RLim', lim); set(app.ui.RectAxes, 'YLim', lim); end
            drawnow limitrate
        end

        function applyFullRange(app)
            for k = 1:numel(app.full)
                ax = app.full(k).axes; clim(ax, app.fullLim); if k == 5, zlim(ax, app.fullLim); end
                cb = findall(ancestor(ax, 'figure'), 'Type', 'ColorBar', 'Axes', ax); if ~isempty(cb), app.tickColorbar(cb(1)); end
            end
        end
    end

    %% ------------------------------------------------------------------ renderers
    methods (Access = private)
        function [lim, map] = theme(app)
            % Colour scale + map: signed AR uses a blue-white-red thermometer map; gain-like data use jet.
            persistent jetMap arMap
            if isempty(jetMap), jetMap = jet(256); arMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
            lim = app.fullLim; if app.isAR(app.comp()), map = arMap; else, map = jetMap; end
        end

        function applyTheme(app, ax)
            [lim, map] = app.theme(); clim(ax, lim); colormap(ax, map); app.tickColorbar(colorbar(ax));
        end

        function tickColorbar(app, cb)
            t = axisTicks(cb.Limits, app.ui.Cstep.Value); if ~isempty(t), cb.Ticks = t; end
        end

        function angularAxes(app, ax, phiStep, thetaStep)
            xl = app.phiLimits(); if app.isElev(), yl = [-90 90]; dir = 'normal'; else, yl = [0 180]; dir = 'reverse'; end
            set(ax, 'XLim', xl, 'YLim', yl, 'YDir', dir, 'Box', 'on', 'Layer', 'top', 'XTick', xl(1):phiStep:xl(2), 'YTick', yl(1):thetaStep:yl(2));
        end

        function polarTicks(app, pax)
            % Polar geometry stays physical; only the labels follow the selected phi span.
            a = 0:30:330; if app.isSignedPhi(), a(a > 180) = a(a > 180) - 360; end
            set(pax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', a));
        end

        function tipTemplate(app, h, g, Z)
            rows = [dataTipTextRow(app.thetaName(), g.thetaGrid, '%.3g°'); dataTipTextRow("Phi", g.phiGrid, '%.3g°'); ...
                dataTipTextRow(replace(app.compLabel(), "_", "\_"), Z, '%.3g dB')];
            try, h.DataTipTemplate.DataTipRows = rows;
            catch, try, delete(datatip(h, 'DataIndex', 1)); h.DataTipTemplate.DataTipRows = rows; catch, end   % Surface templates may need one materialized tip
            end
        end

        function attachMenu(~, ax), set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', ax.ContextMenu); end

        function applyView(app, ax, default)
            switch string(app.ui.View3D.Value)
                case "top",    v = [0 90];  up = [0 1 0];
                case "bottom", v = [0 -90]; up = [0 1 0];
                case "right",  v = [90 0];  up = [0 0 1];
                case "left",   v = [-90 0]; up = [0 0 1];
                case "front",  v = [0 0];   up = [0 0 1];
                case "back",   v = [180 0]; up = [0 0 1];
                otherwise,     v = default; up = [0 0 1];
            end
            view(ax, v); camup(ax, up);
        end

        function onViewChanged(app)
            if isempty(app.viewTbl), return; end
            for k = 3:5, app.applyView(app.full(k).axes, app.full(k).view); end
            drawnow limitrate
        end

        function renderFull(app)
            % All five full-pattern plots are rendered eagerly; tab changes only touch annotation visibility.
            for k = 1:numel(app.full)
                if app.isClosing, return; end
                app.checkCancelled(); app.full(k).render();
            end
            drawnow limitrate; app.annotatePOB();
        end

        function drawContour(app)
            [g, Z] = app.gridOf(app.comp()); ax = app.full(1).axes; cla(ax);
            h = pcolor(ax, g.phi, g.theta, Z, 'FaceColor', 'interp', 'LineStyle', 'none');
            app.applyTheme(ax); app.angularAxes(ax, 30, 15); daspect(ax, [1 1 1]);
            title(ax, app.compLabel(), 'Interpreter', 'none'); app.tipTemplate(h, g, Z); app.attachMenu(ax);
        end

        function drawFisheye(app)
            [g, Z] = app.gridOf(app.comp()); pax = app.full(2).axes; cla(pax);
            h = surface(pax, g.phiRad, g.polar, zeros(g.sz), Z, 'EdgeColor', 'none');
            app.applyTheme(pax); app.polarTicks(pax);
            rl = 0:30:180; if app.isElev(), rl = 90 - rl; end
            set(pax, 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', rl));
            title(pax, sprintf('%s  |  r=θ, angle=φ', app.compLabel()), 'Interpreter', 'none', 'FontSize', 9); app.tipTemplate(h, g, Z);
        end

        function draw3D(app, k, kind)
            % kind "sphere": colour on the unit sphere; kind "polar": radius proportional to dB above the lower limit.
            [g, Z] = app.gridOf(app.comp()); ax = app.full(k).axes; lim = app.theme();
            X = g.x; Y = g.y; W = g.z;
            if kind == "polar", R = app.polarRadius(Z, lim); X = R.*X; Y = R.*Y; W = R.*W; end
            cla(ax); hold(ax, 'on');
            h = surf(ax, X, Y, W, Z, 'EdgeColor', 'none');
            app.applyTheme(ax);
            set(ax, 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1], 'Projection', 'orthographic');
            axis(ax, 'off'); app.drawXYZ(ax); app.applyView(ax, app.full(k).view); app.overlayCut(ax, kind);
            title(ax, sprintf('%s  |  θ: %s  |  φ: %s', app.compLabel(), app.ui.ThetaSpan.Value, app.ui.PhiSpan.Value), 'Interpreter', 'none');
            app.tipTemplate(h, g, Z); hold(ax, 'off'); app.attachMenu(ax);
        end

        function drawRect3(app)
            [g, Z] = app.gridOf(app.comp()); ax = app.full(5).axes; lim = app.theme(); cla(ax);
            h = surf(ax, g.phiGrid, g.thetaGrid, Z, 'EdgeColor', 'none');
            app.applyTheme(ax); zlim(ax, lim); t = axisTicks(lim, app.ui.Cstep.Value); if ~isempty(t), ax.ZTick = t; end
            app.angularAxes(ax, 60, 30); grid(ax, 'on'); app.applyView(ax, app.full(5).view);
            xlabel(ax, 'Phi (degree)'); ylabel(ax, app.thetaName() + " (degree)"); zlabel(ax, app.compLabel() + " (dB)", 'Interpreter', 'none');
            title(ax, app.compLabel(), 'Interpreter', 'none'); app.tipTemplate(h, g, Z); app.attachMenu(ax);
        end

        function drawXYZ(~, ax)
            colors = [0.85 0.10 0.10; 0.10 0.60 0.10; 0.10 0.20 0.90]; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            for k = 1:3
                d = 1.35 * ((1:3) == k);
                quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors(k, :), 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12*d(1), 1.12*d(2), 1.12*d(3), labels{k}, 'Color', colors(k, :), 'FontWeight', 'bold');
            end
        end

        function overlayCut(app, ax, kind)
            % Draw the active cut as a black trace on a spatial 3-D plot (same radius law as the surface).
            delete(findall(ax, 'Tag', 'APAT_CutOverlay')); if ~app.ui.Overlay.Value, return; end
            c = app.cutData(); v = c.data(:, 1); lim = app.theme(); r = 1.02;
            if kind == "polar", [~, Z] = app.gridOf(app.comp()); [~, scale] = app.polarRadius(Z, lim); r = 1.01 * max(v - lim(1), 0) / max(diff(lim), eps) / scale; end
            held = ishold(ax); hold(ax, 'on');
            plot3(ax, r.*sind(c.theta).*cosd(c.phi), r.*sind(c.theta).*sind(c.phi), r.*cosd(c.theta), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay');
            if ~held, hold(ax, 'off'); end
        end

        function refreshOverlay(app)
            if isempty(app.viewTbl), return; end
            app.overlayCut(app.full(3).axes, "sphere"); app.overlayCut(app.full(4).axes, "polar");
        end

        %% ---- cuts
        function onEHPlane(app)
            % E-plane: theta cut through the boresight axis; H-plane: the orthogonal principal cut.
            a = app.Axes; i = app.boresight; type = 'Theta'; value = 90;
            if startsWith(app.ui.EHPlane.Value, 'E'), value = a.phi(i);
            elseif a.theta(i) == 90, type = 'Phi'; if app.isElev(), value = 0; end
            end
            app.ui.CutType.Value = type; vals = app.updateCutControl();
            [~, k] = min(abs(vals - value)); app.ui.CutValue.Value = vals(k); app.onCutChanged();
        end

        function onCutChanged(app, src)
            if nargin > 1 && isequal(src, app.ui.CutType), app.updateCutControl(); end
            if nargin > 1 && isequal(src, app.ui.CutBasis), app.ui.CutBasis.UserData = false; app.updateMetadata(); end
            show = app.ui.HPBW.Value; app.ui.HPBWBounds.Visible = show; if ~show, app.ui.HPBWBounds.Value = false; end
            app.plotCut(); app.refreshOverlay();
        end

        function vals = updateCutControl(app)
            % Cut value = fixed theta (display convention) for Phi cuts, fixed phi for Theta cuts; snapped to the grid.
            if strcmp(app.ui.CutType.Value, 'Phi'), vals = unique(app.viewTbl.Theta); else, vals = unique(mod(app.viewTbl.Phi, 360)); end
            sp = app.ui.CutValue; sp.Limits = [-Inf Inf]; [~, k] = min(abs(vals - sp.Value)); sp.Value = vals(k);
            sp.Limits = [min(vals), max(vals)]; if numel(vals) > 1, sp.Step = min(diff(vals)); end
        end

        function [cols, idx] = cutCols(app)
            % Selected traces: Total plus the circular or linear pair; idx keeps colours stable per trace slot.
            if app.srcUD.isGainOnly, cols = string(app.comp()); idx = 1; return; end
            if strcmp(app.ui.CutBasis.Value, 'Linear'), pair = ["E_TH", "E_PH"]; else, pair = ["E_RCP", "E_LCP"]; end
            if ~strcmp(app.ui.ChkA.Text, pair(1)), [app.ui.ChkA.Text, app.ui.ChkB.Text] = deal(char(pair(1)), char(pair(2))); end
            sel = logical([app.ui.ChkTotal.Value, app.ui.ChkA.Value, app.ui.ChkB.Value]); if ~any(sel), sel(1) = true; end
            idx = find(sel); all3 = ["E_Total_dB", pair + "_dB"]; cols = all3(idx);
        end

        function c = cutData(app)
            % The active cut as one closed circle: 0..360° (or −180..180° when the phi span is signed).
            T = app.viewTbl; [cols, idx] = app.cutCols(); type = string(app.ui.CutType.Value); req = app.ui.CutValue.Value;
            elev = app.isElev() && type == "Phi"; th = app.physTheta(T);
            if elev, req = 90 - req; end
            [ang, rows, fixed, sym, snapped] = cutRows(th, T.Phi, type, req);
            if elev, fixed = 90 - fixed; end
            if snapped, app.setStatus(app.ui.Status, sprintf('%s cut snapped to nearest sampled %s = %g°', type, sym, fixed), true); end
            Y = T{rows, cols}; th = th(rows); ph = T.Phi(rows);
            if app.isSignedPhi(), ang(ang > 180) = ang(ang > 180) - 360; end
            [ang, o] = unique(ang); Y = Y(o, :); th = th(o); ph = ph(o);
            if type == "Phi"   % Close the circle at the seam when a source lacks the duplicate sample.
                lo = -180*app.isSignedPhi(); hi = lo + 360; hasLo = abs(ang(1) - lo) < 1e-9; hasHi = abs(ang(end) - hi) < 1e-9;
                if ~hasLo && hasHi,     ang = [lo; ang]; Y = [Y(end, :); Y]; th = [th(end); th]; ph = [ph(end); ph];
                elseif hasLo && ~hasHi, ang = [ang; hi]; Y = [Y; Y(1, :)]; th = [th; th(1)]; ph = [ph; ph(1)];
                elseif ~hasLo && ~hasHi
                    w = (hi - ang(end)) / (ang(1) - lo + hi - ang(end)); Ys = (1 - w)*Y(end, :) + w*Y(1, :); ts = (1 - w)*th(end) + w*th(1);
                    ang = [lo; ang; hi]; Y = [Ys; Y; Ys]; th = [ts; th; ts]; ph = [lo; ph; hi];
                end
            end
            if app.srcUD.isGainOnly, ttl = char(app.compLabel()); else, ttl = sprintf('%s cut @ %s = %g°', type, sym, fixed); end
            c = struct('angle', ang, 'data', Y, 'cols', cols, 'idx', idx, 'names', replace(cols, "_", "\_"), 'title', ttl, 'theta', th, 'phi', ph, 'type', type);
        end

        function plotCut(app)
            if isempty(app.viewTbl), return; end
            c = app.cutData(); pax = app.ui.PolarCut; rax = app.ui.RectAxes; lim = app.cutLim; xl = app.phiLimits();
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on');
            pl = polarplot(pax, deg2rad(c.angle), max(c.data, lim(1)), 'LineWidth', 1.4);   % Clamp prevents reflection spikes below RLim
            rl = plot(rax, c.angle, c.data, 'LineWidth', 1.4);
            colors = rax.ColorOrder(1 + mod(c.idx - 1, size(rax.ColorOrder, 1)), :);
            set([pl(:); rl(:)], {'Color'}, num2cell([colors; colors], 2));
            for k = 1:numel(pl)
                rows = [dataTipTextRow("Angle", c.angle, '%.3g°'), dataTipTextRow("Magnitude", c.data(:, k), '%.3g dB')];   % True (unclamped) values
                pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            set(pax, 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.polarTicks(pax);
            set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, c.type + " (degree)"); title(pax, c.title, 'Interpreter', 'none'); title(rax, c.title, 'Interpreter', 'none');
            legend(pax, pl, c.names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rl, c.names, 'Location', 'best');

            [pk, i] = max(c.data(:, 1), [], 'omitnan');   % Cut POB = peak of the displayed primary trace
            app.ui.HPBWLabel.Text = '';
            if isfinite(pk)
                rows = [dataTipTextRow("Angle", c.angle(i), '%.3g°'); dataTipTextRow("Magnitude", pk, '%.3g dB')];
                app.markPoint(pax, deg2rad(c.angle(i)), max(pk, lim(1)), [], rows, "APAT_POB"); app.markPoint(rax, c.angle(i), pk, 0, rows, "APAT_POB");
            end
            if app.ui.HPBW.Value && isfinite(pk)
                [bw, lo, hi] = calcHPBW(c.angle, c.data(:, 1), pk, c.angle(i));
                if isfinite(bw)
                    b = mod([lo, hi] - xl(1), 360) + xl(1);   % Wrap the bounds into the displayed span
                    app.ui.HPBWLabel.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                    if b(1) <= b(2), reg = b; else, reg = [xl(1), b(2); b(1), xl(2)]; end
                    thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), FaceColor = '#D95319', FaceAlpha = 0.12);
                    xregion(rax, reg(:, 1), reg(:, 2), FaceColor = '#D95319', FaceAlpha = 0.12);
                    names = ["Lower HPBW", "Upper HPBW"];
                    for k = 1:2
                        rows = [dataTipTextRow(names(k), b(k), '%.2f°'); dataTipTextRow("Gain", pk - 3, '%.2f dB')];
                        app.markPoint(pax, deg2rad(b(k)), pk - 3, [], rows, "APAT_HPBW"); app.markPoint(rax, b(k), pk - 3, 0, rows, "APAT_HPBW");
                    end
                end
            end
            hold(pax, 'off'); hold(rax, 'off'); app.syncTips();
        end

        function exportCut(app)
            c = app.cutData();
            app.saveTable(array2table([c.angle, c.data], 'VariableNames', [{'Angle_deg'}, cellstr(c.cols)]), app.CsvFilters(1:2, :), [app.file.base '_cut.csv'], app.ui.Status);
        end
    end

    %% ------------------------------------------------------------------ annotations (POB / HPBW)
    methods (Access = private)
        function markPoint(app, ax, x, y, z, rows, tag)
            % Marker + pinned DataTip. All annotations share two tags; syncTips() is the only visibility authority.
            if ~all(isfinite([x, y, z])), return; end
            color = 'k'; on = app.ui.POB.Value; if tag == "APAT_HPBW", color = '#D95319'; on = app.ui.HPBWBounds.Value; end
            held = ishold(ax); hold(ax, 'on');
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), h = polarplot(ax, x, y, 'o'); else, h = plot3(ax, x, y, z, 'o', 'Clipping', 'off'); end
            if ~held, hold(ax, 'off'); end
            set(h, 'MarkerSize', 5, 'Color', color, 'MarkerFaceColor', color, 'HandleVisibility', 'off', 'Tag', tag, 'Visible', on);
            h.DataTipTemplate.DataTipRows = rows;
            datatip(h, 'DataIndex', 1, 'FontSize', 9, 'Tag', tag, 'HandleVisibility', 'off', 'Visible', on);
        end

        function annotatePOB(app)
            % Mark the resolved peak-of-beam on every full-pattern plot using each plot's own coordinate law.
            if ~isfinite(app.POBth) || isempty(app.viewTbl), return; end
            [g, Z] = app.gridOf(app.comp()); lim = app.theme(); R = app.polarRadius(Z, lim);
            th = app.POBth; if app.isElev(), th = 90 - th; end
            ph = app.POBph; if app.isSignedPhi() && ph > 180, ph = ph - 360; end
            [~, r] = min(abs(g.theta - th)); [~, c] = min(abs(g.phi - ph)); v = Z(r, c);
            rows = [dataTipTextRow(app.thetaName(), g.theta(r), '%.3g°'); dataTipTextRow("Phi", g.phi(c), '%.3g°'); dataTipTextRow(app.compLabel(), v, '%.3g dB')];
            pts = {g.phi(c), g.theta(r), 0; g.phiRad(r, c), g.polar(r, c), []; 1.02*g.x(r, c), 1.02*g.y(r, c), 1.02*g.z(r, c); ...
                R(r, c)*g.x(r, c), R(r, c)*g.y(r, c), R(r, c)*g.z(r, c); g.phi(c), g.theta(r), v};
            for k = 1:5, app.markPoint(app.full(k).axes, pts{k, :}, rows, "APAT_POB"); end
            app.syncTips();
        end

        function syncTips(app)
            % Visibility policy: checkbox state, and pinned tips additionally require their owning tab to be selected
            % (DataTips on hidden tabs would otherwise float over the visible one).
            if app.isClosing, return; end
            on = struct('APAT_POB', app.ui.POB.Value, 'APAT_HPBW', app.ui.HPBWBounds.Value);
            for tag = ["APAT_POB", "APAT_HPBW"]
                for h = findall(app.UIFigure, 'Tag', tag)'
                    vis = on.(char(tag)); tab = ancestor(h, 'uitab');
                    if isa(h, 'matlab.graphics.datatip.DataTip') && ~isempty(tab), vis = vis && isequal(tab.Parent.SelectedTab, tab); end
                    h.Visible = vis;
                end
            end
        end
    end

    %% ------------------------------------------------------------------ tables · metadata · export
    methods (Access = private)
        function updateTables(app)
            T = app.viewTbl; dd = app.ui.OutFilter; cols = T.Properties.VariableNames(3:end);
            if ~app.rawShown, set(app.ui.InTable, 'Data', app.rawTbl, 'ColumnName', app.rawTbl.Properties.VariableNames, 'Visible', 'on'); app.rawShown = true; end
            schemaChanged = ~isequal(regexprep(dd.Items(2:end), '^✓ ?', ''), cols);
            if schemaChanged
                set(dd, 'Items', [{'--- column filter ---'}, cols], 'ItemsData', 0:numel(cols), 'UserData', ~ismember(cols, app.Hidden), 'Value', 0);
                set([dd, app.ui.OutTable, app.ui.DataTabs], 'Visible', 'on');
            end
            app.filterOutput(schemaChanged);
        end

        function filterOutput(app, restyle)
            % Toggle the picked column (UserData = visibility mask), then rebuild the ✓ styling and the Results table.
            if nargin < 2, restyle = true; end
            dd = app.ui.OutFilter;
            if dd.Value > 0, dd.UserData(dd.Value) = ~dd.UserData(dd.Value); dd.Value = 0; end
            if restyle
                if isempty(app.filterStyles)
                    app.filterStyles = {uistyle('FontWeight', 'bold', 'FontColor', 'black', 'BackgroundColor', [0.8 1 0.8]), uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9])};
                end
                dd.Items = regexprep(dd.Items, '^✓ ?', ''); removeStyle(dd);
                on = find(dd.UserData) + 1; dd.Items(on) = append('✓ ', dd.Items(on));
                addStyle(dd, app.filterStyles{1}, 'Item', on); addStyle(dd, app.filterStyles{2}, 'Item', find([true, ~dd.UserData]));
            end
            app.ui.OutTable.Data = app.viewTbl(:, [true, true, dd.UserData]); app.updateInputVisibility();
        end

        function updateInputVisibility(app)
            % Show only the parameter controls that influence a currently displayed output column.
            u = app.ui; cols = app.viewTbl.Properties.VariableNames(3:end); shown = string(cols(u.OutFilter.UserData));
            has = @(names) any(ismember(shown, names));
            set([u.RxPolLabel, u.RxPol, u.RwLabel, u.Rw], 'Visible', has(["PLF_dB", "Gain_PolCorrected_dB"]));
            set([u.PtLabel, u.Pt, u.PtUnit], 'Visible', has(["EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
            set([u.RLabel, u.R, u.RUnit], 'Visible', has(["PFD_Wm2", "E_RMS_Vm"]));
            set([u.LossLabel, u.Loss], 'Visible', app.srcUD.isGainOnly || has([app.Comps(1:5), "Gain_PolCorrected_dB", "EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
        end

        function updateMetadata(app)
            T = app.viewTbl; m = app.metrics; th = unique(T.Theta); ph = unique(T.Phi);
            rows = {'Source format', app.srcUD.source; 'File', app.file.name; ...
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(T), numel(th), numel(ph)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmt(min(th)), fmt(max(th)), fmt(gridStep(th))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmt(min(ph)), fmt(max(ph)), fmt(gridStep(ph)))};
            f = app.freqs(isfinite(app.freqs)); if ~isempty(f), rows(end+1, :) = {'Frequencies', strjoin(compose('%.4g GHz', f/1e9), ', ')}; end
            if ~app.srcUD.isGainOnly
                rows(end+1, :) = {'Polarization', app.polLabel};
                rows(end+1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(app.polPairs.(app.ui.CutBasis.Value), ' / '))};
            end
            rows = [rows; {'Peak gain (POB)', sprintf('%s dB', fmt(m.PeakGain_dB)); 'POB direction [θ, φ]', sprintf('[%s°, %s°]', fmt(m.PeakTheta_deg), fmt(m.PeakPhi_deg)); ...
                'Boresight axis', app.Axes.labels{app.boresight}; 'Peak policy', sprintf('P%.4g, max excess %.4g dB', app.PeakPct, app.PeakExcess); ...
                'Peak adjusted', char(string(app.peak.wasAdjusted)); 'HPBW E-plane', sprintf('%s°', fmt(m.HPBW_EPlane_deg)); ...
                'HPBW H-plane', sprintf('%s°', fmt(m.HPBW_HPlane_deg)); 'Front-to-back', sprintf('%s dB', fmt(m.FrontBack_dB)); ...
                'Peak directivity', sprintf('%s dB', fmt(m.PeakDirectivity_dB))}];
            if isfinite(m.Efficiency_pct), rows(end+1, :) = {'Radiation efficiency', sprintf('%s%%', fmt(m.Efficiency_pct))}; end
            if isfinite(m.AxialRatioAtPeak_dB), rows(end+1, :) = {'AR at peak', sprintf('%s dB', fmt(m.AxialRatioAtPeak_dB))}; end
            app.ui.MetaTable.Data = rows;
        end

        function saveTable(app, T, filters, defaultName, statusLabel)
            % One export path: UAN gets its header, TXT is tab-delimited, CSV/XLSX use writetable defaults.
            [f, p] = uiputfile(filters, 'Export', fullfile(app.file.folder, defaultName)); if isequal(f, 0), return; end
            fp = fullfile(p, f);
            if endsWith(fp, '.uan', 'IgnoreCase', true), writeUAN(T, fp);
            elseif endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t');
            else, writetable(T, fp); end
            app.setStatus(statusLabel, sprintf('Exported to <b>%s</b>', fp), true);
        end

        function exportResults(app)
            app.saveTable(app.ui.OutTable.Data, app.CsvFilters, [app.file.base '_APAT_results.csv'], app.ui.Status);   % Honours the column filter
        end

        function exportUAN(app)
            if app.srcUD.isGainOnly, uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            if isempty(app.uanTbl)
                V = app.viewTbl;
                app.uanTbl = sortrows(table(app.physTheta(V), V.Phi, round(V.E_TH_dB, 5), round(V.E_PH_dB, 5), round(V.E_TH_Phase, 5), round(V.E_PH_Phase, 5), ...
                    'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'}), {'Phi', 'Theta'});
            end
            U = app.uanTbl; st = gridStep(U.Theta); if ~isfinite(st), st = 1; end
            name = sprintf('%s_%.5f_%gdeg.uan', app.file.base, max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan'), st);
            app.saveTable(U, [{'*.uan', 'XGTD user-defined antenna (*.uan)'}; app.CsvFilters(1:2, :)], name, app.ui.Status);
        end
    end

    %% ------------------------------------------------------------------ coverage tab
    methods (Access = private)
        function toCoverage(app)
            % Coverage is fed from the CURRENT View Table so loss/step/span/component state is exactly what the user sees.
            app.ui.Tabs.SelectedTab = app.ui.CovTab; app.ui.CovPath.Value = app.file.path;
            node = app.covFind(app.file.path);
            if isempty(node), app.covAddPattern(app.file.base, app.viewTbl, app.file.path, app.rawTbl);
            else, app.covSyncFromView(node); app.ui.CovTree.SelectedNodes = node; app.covUI(); end
            app.ui.CovPanelResults.Visible = 'on';
            app.setStatus(app.ui.CovStatus, 'Coverage source synchronized from the current Main-tab View Table.', false);
        end

        function covLoad(app)
            fp = strtrim(app.ui.CovPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFind(fp))
                [f, p] = uigetfile([app.FileFilter; {'*.*', 'All files'}], 'Select a pattern or coverage results file'); if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            existing = app.covFind(fp);
            if ~isempty(existing)
                app.ui.CovTree.SelectedNodes = existing; app.covSelected(); app.ui.CovPath.Value = fp; app.covUI();
                app.setStatus(app.ui.CovStatus, 'File already loaded -- node selected.', true); return
            end
            app.ui.CovPath.Value = fp; out = app.readSource(fp, app.ui.CovFormatLabel, app.ui.CovFormat);
            if out.userData.isCoverage
                node = app.covPattern(); if ~isempty(node), app.ui.CovPath.Value = node.NodeData.path; end
                app.covLoadResults(fp, out.rawTbl);
            else
                [~, name] = fileparts(fp); app.covAddPattern(name, app.buildPattern(out), fp, out.rawTbl);
            end
            app.ui.CovPanelResults.Visible = 'on';
        end

        function covFormatChanged(app)
            % Re-interpret a generic text pattern node with the newly selected format (jobs of the old node are dropped).
            fp = strtrim(app.ui.CovPath.Value); old = app.covFind(fp);
            if isempty(old) || ~isGenericText(fp) || ~strcmp(old.NodeData.kind, 'pattern'), return; end
            out = readPattern(fp, app.ui.CovFormat.Value, old.NodeData.raw);
            if out.userData.isCoverage, app.setStatus(app.ui.CovStatus, 'Coverage-result format is detected automatically.', true); return; end
            name = old.NodeData.name; for j = old.Children', delete(j.NodeData.line); end; delete(old);
            app.covAddPattern(name, app.buildPattern(out), fp, out.rawTbl); app.covRefresh();
            app.setStatus(app.ui.CovStatus, sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
        end

        function node = covAddPattern(app, name, T, fp, raw)
            th = app.physTheta(T); node = uitreenode(app.ui.CovRoot, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', 'pattern', 'name', name, 'path', fp, 'pattern', T, 'raw', raw, 'theta', th, ...
                'w', solidWeights(th, T.Phi), 'rev', app.viewRev, 'orientComp', "", 'boresight', 1);
            expand(app.ui.CovTree, 'all');
            app.ui.CovTree.CheckedNodes = [app.ui.CovTree.CheckedNodes; node]; app.ui.CovTree.SelectedNodes = node;
            app.covSync(node); app.covUI();
            app.setStatus(app.ui.CovStatus, sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name), false);
        end

        function covSyncFromView(app, node)
            d = node.NodeData; T = app.viewTbl; d.pattern = T; d.theta = app.physTheta(T); d.w = solidWeights(d.theta, T.Phi);
            d.name = app.file.base; d.rev = app.viewRev; d.orientComp = ""; node.NodeData = d; app.covSync(node);
        end

        function covSync(app, node)
            % Align the component dropdown, the detected boresight and the threshold preset with a pattern node.
            d = node.NodeData; T = d.pattern;
            prefer = d.orientComp; if prefer == "", prefer = string(app.ui.CovComp.Value); end
            app.setComponentItems(app.ui.CovComp, T, prefer); comp = string(app.ui.CovComp.Value);
            if comp ~= d.orientComp
                [~, d.boresight] = calcOrientation(d.theta, T.Phi, T.(comp), d.w, app.Axes, app.PeakPct, app.PeakExcess);
                d.orientComp = comp; node.NodeData = d;
                if app.ui.CovOrient.Value == 0, app.covOrientChanged(); end   % Auto: seed the cone centre from the detected axis
            end
            key = string(sprintf('%s|%s|%d', d.path, comp, d.rev));   % Preset once per pattern/component/view; user edits survive recomputes
            if app.covPreset ~= key, app.covPresetThresholds(peakWindow(T.(comp), app.PeakPct, app.PeakExcess)); app.covPreset = key; end
        end

        function covPresetThresholds(app, bounds)
            % Automatic 50-dB peak window; after the first preset it may only widen the user's current range.
            u = app.ui; if app.covPresetDone, bounds = [min(u.ThrMin.Value, bounds(1)), max(u.ThrMax.Value, bounds(2))]; end
            set([u.ThrMin, u.ThrMax], 'Limits', app.DBRange); [u.ThrMin.Value, u.ThrMax.Value] = deal(bounds(1), bounds(2));
            u.ThrMin.Limits = [-250, bounds(2) - 0.1]; u.ThrMax.Limits = [bounds(1) + 0.1, 100]; app.covPresetDone = true;
        end

        function thr = covThresholds(app)
            lo = app.ui.ThrMin.Value; hi = app.ui.ThrMax.Value; st = max(app.ui.ThrStep.Value, 0.1);
            if hi <= lo, hi = min(100, lo + st); app.ui.ThrMax.Value = hi; end
            thr = (lo:st:hi)'; if thr(end) < hi, thr(end+1, 1) = hi; end
        end

        function covCompute(app)
            node = app.covPattern();
            if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if strcmp(node.NodeData.path, app.file.path) && ~isempty(app.viewTbl), app.covSyncFromView(node); end
            d = node.NodeData; comp = app.ui.CovComp.Value; thr = app.covThresholds(); conical = app.ui.CovCon.Value;
            mask = true(height(d.pattern), 1); label = 'Sph coverage'; tableTag = 'Sph'; orient = "n/a";
            if conical
                sel = app.ui.CovOrient.Value; if sel == 0, sel = d.boresight; end; orient = string(app.Axes.labels{sel});
                th0 = app.ui.ConeTh.Value; ph0 = mod(app.ui.ConePh.Value, 360); a = app.ui.ConeAng.Value;
                mask = cosd(d.theta)*cosd(th0) + sind(d.theta)*sind(th0).*cosd(d.pattern.Phi - ph0) >= cosd(a);
                centre = app.coneLabel(th0, ph0);
                label = sprintf('Conical coverage (%s) α=%s°', centre, fmt(a)); tableTag = sprintf('Con %s α%s°', erase(centre, ["=", ","]), fmt(a));
            end
            done = app.startPerf("Compute coverage");
            cov = coverageCCDF(d.pattern.(comp), mask, thr, d.w);
            job = app.covAddJob(node, thr, cov, label, comp, struct('tableTag', tableTag, 'conical', conical, 'orient', orient));
            app.covRefresh(); app.covSetX([thr(1), thr(end)]); app.ui.CovPanelResults.Visible = 'on'; done();
            msg = sprintf('Run-<b>%d</b> computed: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', job.NodeData.id, label, d.name, comp, numel(thr));
            if conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, orient); end
            app.setStatus(app.ui.CovStatus, msg, false);
        end

        function label = coneLabel(app, theta, phi)
            % Principal-axis name when the cone centre coincides with ±X/±Y/±Z, otherwise the spherical coordinates.
            a = app.Axes; v = [sind(theta)*cosd(phi), sind(theta)*sind(phi), cosd(theta)];
            A = [sind(a.theta(:)).*cosd(a.phi(:)), sind(a.theta(:)).*sind(a.phi(:)), cosd(a.theta(:))];
            k = find(A * v(:) >= 1 - 1e-9, 1);
            if isempty(k), label = sprintf('θ=%s°, φ=%s°', fmt(theta), fmt(phi)); else, label = string(a.labels{k}); end
        end

        function node = covAddJob(app, parent, thr, cov, label, comp, extra)
            app.covRunID = app.covRunID + 1; icon = '📉'; if strcmp(parent.NodeData.kind, 'results'), icon = '📈'; end
            text = sprintf('%s R%d %s · %s', icon, app.covRunID, label, comp);
            line = plot(app.ui.CovAxes, thr, cov, 'LineWidth', 1.6, 'DisplayName', text);
            line.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", 'XData', '%.2f dB'); dataTipTextRow("Coverage", 'YData', '%.2f%%')];
            node = uitreenode(parent, 'Text', text);
            d = struct('kind', 'job', 'id', app.covRunID, 'thr', thr(:), 'cov', cov(:), 'line', line, 'label', text, 'tableTag', label, 'conical', false, 'orient', "n/a");
            for f = fieldnames(extra)', d.(f{1}) = extra.(f{1}); end
            node.NodeData = d; app.covJobs(end+1) = node;
            app.ui.CovTree.CheckedNodes = [app.ui.CovTree.CheckedNodes; node];
        end

        function covLoadResults(app, fp, T)
            [~, name] = fileparts(fp); node = uitreenode(app.ui.CovRoot, 'Text', ['📄 ' name]);
            node.NodeData = struct('kind', 'results', 'name', name, 'path', fp);
            app.ui.CovTree.CheckedNodes = [app.ui.CovTree.CheckedNodes; node]; thr = T{:, 1};
            for k = 2:width(T), app.covAddJob(node, thr, T{:, k}, 'Res', T.Properties.VariableNames{k}, struct()); end
            app.covSetX([min(thr), max(thr)], gridStep(thr)); app.covRefresh(); app.ui.CovPanelResults.Visible = 'on';
            app.setStatus(app.ui.CovStatus, sprintf('Coverage results file "%s" loaded (%d curves).', name, width(T) - 1), false);
        end

        function jobs = covJobsUnder(app, roots)
            % Live job nodes in run order, optionally restricted to a subtree.
            app.covJobs = app.covJobs(isvalid(app.covJobs)); jobs = app.covJobs;
            if nargin > 1 && ~isempty(roots), jobs = jobs(ismember(jobs, findobj(roots))); end
        end

        function node = covPattern(app)
            % Pattern node to operate on: the selection's pattern ancestor, else the most recently added pattern node.
            node = []; n = app.ui.CovTree.SelectedNodes;
            if ~isempty(n), n = n(1); end
            while isscalar(n) && isa(n, 'matlab.ui.container.TreeNode')
                if isstruct(n.NodeData) && strcmp(n.NodeData.kind, 'pattern'), node = n; return; end
                n = n.Parent;
            end
            kids = app.ui.CovRoot.Children;
            for k = numel(kids):-1:1, if isstruct(kids(k).NodeData) && strcmp(kids(k).NodeData.kind, 'pattern'), node = kids(k); return; end; end
        end

        function node = covFind(app, fp)
            node = [];
            for n = app.ui.CovRoot.Children'
                if isstruct(n.NodeData) && isfield(n.NodeData, 'path') && strcmp(n.NodeData.path, fp), node = n; return; end
            end
        end

        function covRefresh(app)
            % Rebuild the results table (union of checked thresholds) and the legend, then the panel state.
            jobs = app.covJobsUnder(); checked = jobs(ismember(jobs, app.ui.CovTree.CheckedNodes)); expand(app.ui.CovTree, 'all');
            thr = app.covThresholds();
            if ~isempty(checked), c = arrayfun(@(n) n.NodeData.thr, checked, 'UniformOutput', false); thr = unique(vertcat(c{:})); end
            vals = nan(numel(thr), numel(checked) + 1); vals(:, 1) = thr; names = cell(1, numel(checked) + 1); names{1} = 'Threshold (dB)';
            lines = gobjects(1, numel(checked)); labels = cell(1, numel(checked));
            for k = 1:numel(checked)
                d = checked(k).NodeData; vals(:, k+1) = interp1(d.thr, d.cov, thr, 'linear', NaN);
                names{k+1} = sprintf('R%d %s %%', d.id, d.tableTag); lines(k) = d.line; labels{k} = d.label;
            end
            app.ui.CovTable.Data = array2table(compose('%.2f', vals), 'VariableNames', names);
            if isempty(checked), legend(app.ui.CovAxes, 'off'); else, legend(app.ui.CovAxes, lines, labels, 'Location', 'southwest', 'Interpreter', 'none'); end
            app.covUI();
        end

        function covUI(app)
            % Parameter-panel state machine: empty → results-only → pattern loaded.
            u = app.ui; hasPattern = ~isempty(app.covPattern()); hasJobs = ~isempty(app.covJobsUnder()); kids = u.CovParamGrid.Children;
            query = [u.QCovLabel, u.QCov, u.QCovBtn, u.QThrLabel, u.QThr, u.QThrBtn];
            if hasPattern
                set(kids, 'Visible', 'on', 'Enable', 'on'); set([u.CovExport, u.CovClear, query], 'Enable', hasJobs);
                generic = isGenericText(u.CovPath.Value); set([u.CovFormatLabel, u.CovFormat], 'Visible', generic, 'Enable', generic);
                app.covTypeChanged();
            else
                set(kids, 'Visible', 'off', 'Enable', 'off'); set([u.CovPathLabel, u.CovPath, u.CovLoad, u.CovCompute], 'Visible', 'on');
                set([u.CovPathLabel, u.CovPath, u.CovLoad], 'Enable', 'on');
                set([query, u.CovReset, u.CovExport, u.CovClear, u.CovToMain], 'Visible', hasJobs, 'Enable', hasJobs);
            end
        end

        function covTypeChanged(app)
            u = app.ui; conical = u.CovCon.Value;
            set([u.ConeTh, u.ConePh, u.ConeAng, u.ConeThLabel, u.ConePhLabel, u.ConeAngLabel, u.CovOrient, u.CovOrientLabel], 'Enable', conical, 'Visible', conical);
            if conical, node = app.covPattern(); if ~isempty(node), app.covSync(node); end; app.covOrientStatus();
            else, u.CovStatus.Text = regexprep(char(u.CovStatus.Text), '\s*\|\s*Orientation <b>.*?</b>', ''); end
        end

        function i = covOrientIndex(app)
            % Resolved conical orientation: explicit dropdown choice, or the detected boresight when set to Auto.
            i = app.ui.CovOrient.Value; node = app.covPattern();
            if i == 0 && ~isempty(node), i = node.NodeData.boresight; end
        end

        function covOrientChanged(app)
            i = app.covOrientIndex(); if i == 0, return; end
            [app.ui.ConeTh.Value, app.ui.ConePh.Value] = deal(app.Axes.theta(i), app.Axes.phi(i)); app.covOrientStatus();
        end

        function covOrientStatus(app)
            i = app.covOrientIndex(); if ~app.ui.CovCon.Value || i == 0, return; end
            base = regexprep(char(app.ui.CovStatus.Text), '\s*\|\s*Orientation <b>.*?</b>$', '');
            app.setStatus(app.ui.CovStatus, sprintf('%s | Orientation <b>%s</b>', base, app.Axes.labels{i}), false);
        end

        function covCompChanged(app)
            % The user's component choice is authoritative: re-detect the boresight for it and keep it on the node.
            node = app.covPattern(); if isempty(node), return; end
            d = node.NodeData; comp = string(app.ui.CovComp.Value);
            [~, d.boresight] = calcOrientation(d.theta, d.pattern.Phi, d.pattern.(comp), d.w, app.Axes, app.PeakPct, app.PeakExcess);
            d.orientComp = comp; node.NodeData = d; app.covOrientStatus();
        end

        function h = covArtifacts(app, d, mode)
            % Query projections (axes children) and query tips (curve children). mode omitted = every query + every tip.
            if nargin < 3, pat = sprintf('^CovQ_\\w+_%d$', d.id); else, pat = sprintf('^CovQ_%s_%d$', mode, d.id); end
            h = findall(app.ui.CovAxes, '-regexp', 'Tag', pat);
            if nargin < 3, h = [h; findall(d.line, 'Type', 'datatip')]; end
        end

        function covQuery(app, mode)
            % "cov": coverage at a threshold · "thr": threshold at a coverage level → dotted projections + pinned tip.
            ax = app.ui.CovAxes; sel = app.ui.CovTree.SelectedNodes;
            if isempty(sel), app.setStatus(app.ui.CovStatus, 'Select a node to query.', true); return; end
            jobs = app.covJobsUnder(sel); jobs = jobs(ismember(jobs, app.ui.CovTree.CheckedNodes));
            if isempty(jobs), app.setStatus(app.ui.CovStatus, 'No checked results under selected node.', true); return; end
            if mode == "cov", q = app.ui.QCov.Value; else, q = app.ui.QThr.Value; end
            hit = false;
            for k = 1:numel(jobs)
                d = jobs(k).NodeData; tag = sprintf('CovQ_%s_%d', mode, d.id); delete(app.covArtifacts(d, mode));
                if mode == "cov", x = q; y = interp1(d.thr, d.cov, q, 'linear', NaN); else, x = thresholdAt(d.thr, d.cov, q); y = q; end
                if ~isfinite(x) || ~isfinite(y), continue; end
                line(ax, [x x], [ax.YLim(1) y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [-250 x], [y y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'FontSize', 9, 'Tag', tag, 'HandleVisibility', 'off'); hit = true;
            end
            if ~hit, app.setStatus(app.ui.CovStatus, 'Query value is outside selected checked range.', true);
            elseif mode == "cov", app.setStatus(app.ui.CovStatus, sprintf('Coverage queried at %s dB.', fmt(q)), false);
            else, app.setStatus(app.ui.CovStatus, sprintf('Threshold queried at %s%% coverage.', fmt(q)), false); end
        end

        function covChecked(app)
            checked = app.ui.CovTree.CheckedNodes; jobs = app.covJobsUnder();
            for k = 1:numel(jobs)
                d = jobs(k).NodeData; vis = ismember(jobs(k), checked); d.line.Visible = vis; set(app.covArtifacts(d), 'Visible', vis);
            end
            app.covRefresh();
        end

        function covSelected(app)
            sel = app.ui.CovTree.SelectedNodes; jobs = app.covJobsUnder();
            for k = 1:numel(jobs), d = jobs(k).NodeData; d.line.LineWidth = 1.6 + (~isempty(sel) && jobs(k) == sel(1)); end   % Selection = emphasis only
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(app.ui.CovStatus, 'Ready.', false); return; end
            d = sel(1).NodeData; node = app.covPattern(); if ~isempty(node), app.covSync(node); end
            if ~strcmp(d.kind, 'job')
                kind = 'Pattern'; if strcmp(d.kind, 'results'), kind = 'Results'; end
                app.setStatus(app.ui.CovStatus, sprintf('%s <b>"%s"</b> -- <b>%d</b> coverage job(s).', kind, d.name, numel(sel(1).Children)), false);
                if strcmp(d.kind, 'pattern'), app.covOrientStatus(); end
                return
            end
            parts = {char(d.label)};
            if d.conical, parts{end+1} = sprintf('Orientation <b>%s</b>', d.orient); end
            parts{end+1} = sprintf('Threshold [%s, %s] dB, step %s dB', fmt(d.thr(1)), fmt(d.thr(end)), fmt(gridStep(d.thr)));
            t50 = thresholdAt(d.thr, d.cov, 50);
            if isfinite(t50), parts{end+1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', fmt(t50)); else, parts{end+1} = '<b>50%-coverage unavailable</b>'; end
            shown = round(d.cov, 2); mx = max(shown); i = find(shown == mx, 1, 'last');
            if isfinite(mx), parts{end+1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmt(mx), fmt(d.thr(i))); end
            app.setStatus(app.ui.CovStatus, strjoin(parts, ' | '), false);
        end

        function covSetX(app, bounds, step)
            % Coverage X-axis baseline: the first result establishes it, later results may only widen it.
            bounds = clampRange(bounds, app.DBRange);
            if app.covXInit, bounds = [min(app.ui.CovAxes.XLim(1), bounds(1)), max(app.ui.CovAxes.XLim(2), bounds(2))]; end
            app.covXInit = true; app.covApplyX(bounds, true);
            if nargin > 2 && isfinite(step) && step < app.ui.ThrStep.Value, app.ui.ThrStep.Value = step; end
        end

        function covApplyX(app, bounds, master)
            % master = spinners define the slider travel; a slider drag only moves the selection inside that travel.
            u = app.ui; set(u.CovAxes, 'XLimMode', 'manual', 'XLim', bounds);
            set([u.CovXMin, u.CovXMax], 'Limits', app.DBRange); [u.CovXMin.Value, u.CovXMax.Value] = deal(bounds(1), bounds(2));
            if master, u.CovXSlider.Limits = app.DBRange; u.CovXSlider.Value = bounds; u.CovXSlider.Limits = bounds; end
            u.CovXMin.Limits = [-250, bounds(2) - 0.1]; u.CovXMax.Limits = [bounds(1) + 0.1, 100];
        end

        function covXChanged(app, src, value)
            u = app.ui;
            if isequal(src, u.CovXSlider), b = sort(double(value)); if diff(b) > 0, app.covApplyX(b, false); end; return; end
            b = sort([u.CovXMin.Value, u.CovXMax.Value]);
            if diff(b) <= 0, if isequal(src, u.CovXMin), b(2) = min(100, b(1) + 1); else, b(1) = max(-250, b(2) - 1); end, end
            app.covApplyX(b, true);
        end

        function covClear(app)
            sel = app.ui.CovTree.SelectedNodes;
            if isempty(sel), app.setStatus(app.ui.CovStatus, 'Select a node to clear.', true); return; end
            jobs = app.covJobsUnder(sel); for k = 1:numel(jobs), delete(app.covArtifacts(jobs(k).NodeData)); end
            app.setStatus(app.ui.CovStatus, 'Selected DataTips and query markers cleared.', true);
        end

        function covReset(app)
            delete(app.ui.CovRoot.Children); app.covJobs = matlab.ui.container.TreeNode.empty;
            cla(app.ui.CovAxes); legend(app.ui.CovAxes, 'off'); app.ui.CovTable.Data = table();
            [app.covRunID, app.covPreset, app.covPresetDone, app.covXInit] = deal(0, "", false, false);
            app.ui.CovPanelResults.Visible = 'off'; app.covApplyX([-40 10], true); app.ui.CovAxes.XLimMode = 'auto'; app.covUI();
            app.setStatus(app.ui.CovStatus, 'Coverage workspace reset 🔄', true);
        end

        function covExport(app)
            if isempty(app.ui.CovTable.Data), return; end
            app.saveTable(app.ui.CovTable.Data, app.CsvFilters, 'coverage_results.csv', app.ui.CovStatus);
        end
    end

    %% ------------------------------------------------------------------ UI construction
    methods (Access = private)
        function h = add(~, ctor, parent, row, col, varargin)
            % Create a component inside a grid cell: add(@uibutton, grid, row, col, 'Text', ...).
            h = ctor(parent, varargin{:}); h.Layout.Row = row; h.Layout.Column = col;
        end

        function h = lbl(app, parent, text, row, col, varargin)
            h = app.add(@uilabel, parent, row, col, 'Text', text, 'HorizontalAlignment', 'right', varargin{:});
        end

        function dd = formatDropdown(app, parent, row, col, fcn)
            items = {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
                '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
                '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'};
            data = {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'};
            dd = app.add(@uidropdown, parent, row, col, 'Items', items, 'ItemsData', data, 'Visible', 'off', ...
                'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'ValueChangedFcn', fcn);
        end

        function createUI(app)
            u = struct(); cb = @(fn) @(s, e) app.safe(fn, s, e); pad = @(n) repmat(char(160), 1, n);
            app.UIFigure = uifigure('Name', 'Antenna Pattern Analyzer Tool — APAT v3 M8', 'Visible', 'off', 'Position', [100 100 1136 739], ...
                'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) app.delete());
            u.Tabs = uitabgroup(uigridlayout(app.UIFigure, [1 1]));
            u.MainTab = uitab(u.Tabs, 'Title', 'Process Pattern 📡'); u.CovTab = uitab(u.Tabs, 'Title', 'Compute Coverage 📈');

            % ---- Main tab: parameters --------------------------------------------------------------------------
            g = uigridlayout(u.MainTab, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});
            pg = uigridlayout(app.add(@uipanel, g, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️'), 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            app.lbl(pg, 'Input Pattern:', 1, 1); u.Path = app.add(@uieditfield, pg, 1, [2 8], 'text');
            u.FFDLabel = app.lbl(pg, 'FFD Freq:', 1, 9, 'Visible', 'off');
            u.FFD = app.add(@uidropdown, pg, 1, 10, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', cb(@(~, ~) app.onFFDChanged()));
            u.Load = app.add(@uibutton, pg, 1, [11 12], 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', cb(@(~, ~) app.onLoad()));
            u.Process = app.add(@uibutton, pg, 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', cb(@(~, ~) app.onProcess()));
            u.ResetParams = app.add(@uibutton, pg, 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', cb(@(~, ~) app.resetParams()));
            u.FormatLabel = app.lbl(pg, 'Format:', 2, [4 5], 'Visible', 'off'); u.Format = app.formatDropdown(pg, 2, [6 8], cb(@(~, ~) app.onFormatChanged()));
            u.Step = app.add(@uidropdown, pg, 2, [9 10], 'Items', {'STEP'}, 'Visible', 'off', 'Enable', 'off', 'ValueChangedFcn', cb(@(~, ~) app.onStepChanged()));
            u.ExportOut = app.add(@uibutton, pg, 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@(~, ~) app.exportResults()));
            u.ExportUAN = app.add(@uibutton, pg, 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@(~, ~) app.exportUAN()));
            u.RxPolLabel = app.lbl(pg, 'Rw Sense', 3, 1, 'Visible', 'off'); u.RxPol = app.add(@uidropdown, pg, 3, 2, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Editable', 'on', 'Visible', 'off');
            u.RwLabel = app.lbl(pg, 'Rw (dB)', 3, 3, 'Visible', 'off'); u.Rw = app.add(@uispinner, pg, 3, 4, 'Value', 6, 'Visible', 'off');
            u.LossLabel = app.lbl(pg, 'Loss (−) / Gain (+) dB', 3, 5, 'Visible', 'off'); u.Loss = app.add(@uispinner, pg, 3, 6, 'Step', 0.1, 'Visible', 'off');
            u.PtLabel = app.lbl(pg, 'Tx Pwr (Pt)', 3, 7, 'Visible', 'off'); u.Pt = app.add(@uispinner, pg, 3, 8, 'Visible', 'off');
            u.PtUnit = app.add(@uidropdown, pg, 3, 9, 'Items', {'dBW', 'dBm', 'Watts'}, 'Visible', 'off');
            u.RLabel = app.lbl(pg, 'Distance', 3, 10, 'Visible', 'off'); u.R = app.add(@uispinner, pg, 3, 11, 'Value', 1, 'Visible', 'off');
            u.RUnit = app.add(@uidropdown, pg, 3, 12, 'Items', {'m', 'km'}, 'Visible', 'off');
            u.ToCoverage = app.add(@uibutton, pg, 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@(~, ~) app.toCoverage()));

            % ---- Main tab: full-pattern plots (registry drives rendering, ranges and annotations) ------------
            u.PanelFull = app.add(@uipanel, g, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off');
            u.FullTabs = uitabgroup(uigridlayout(u.PanelFull, [1 1]), 'SelectionChangedFcn', @(~, ~) app.syncTips());
            names = {'Contour Plot', 'Circular Contour Plot', '3D Spherical Plot', '3D Polar Plot', '3D Surface Plot'};
            renders = {@() app.drawContour(), @() app.drawFisheye(), @() app.draw3D(3, "sphere"), @() app.draw3D(4, "polar"), @() app.drawRect3()};
            views = {[], [], [135 25], [135 25], [-35 35]};
            for k = 1:5
                t = uitab(u.FullTabs, 'Title', names{k}); tg = uigridlayout(t, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
                if k == 2, ax = polaraxes(tg); else, ax = uiaxes(tg); end
                ax.Layout.Row = [1 3]; ax.Layout.Column = 2;
                f = struct('tab', t, 'axes', ax, 'render', renders{k}, 'view', views{k}, ...
                    'max', app.add(@uispinner, tg, 1, 1, 'Limits', app.DBRange, 'Value', 100, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.setRange("full", s.Value, 2)), ...
                    'slider', app.add(@uislider, tg, 2, 1, 'range', 'Limits', app.DBRange, 'Value', app.DBRange, 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s, ~) app.setRange("full", s.Value, 3)), ...
                    'min', app.add(@uispinner, tg, 3, 1, 'Limits', app.DBRange, 'Value', -250, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.setRange("full", s.Value, 1)));
                if k == 1, specs = f; else, specs(k) = f; end
            end
            app.full = specs;

            % ---- Main tab: cut plots -------------------------------------------------------------------------
            u.PanelCut = app.add(@uipanel, g, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off');
            u.CutTabs = uitabgroup(uigridlayout(u.PanelCut, [1 1]), 'SelectionChangedFcn', @(~, ~) app.syncTips());
            u.PolarTab = uitab(u.CutTabs, 'Title', 'Polar Cut Plot');
            pr = uigridlayout(u.PolarTab, 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            u.CutMax = app.add(@uispinner, pr, 1, 1, 'Limits', app.DBRange, 'Value', 100, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.setRange("cut", s.Value, 2));
            u.CutSlider = app.add(@uislider, pr, [2 3], 1, 'range', 'Limits', app.DBRange, 'Value', app.DBRange, 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s, ~) app.setRange("cut", s.Value, 3));
            u.CutMin = app.add(@uispinner, pr, 4, 1, 'Limits', app.DBRange, 'Value', -250, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.setRange("cut", s.Value, 1));
            u.PolarCut = polaraxes(pr); u.PolarCut.Layout.Row = [1 4]; u.PolarCut.Layout.Column = 3;
            u.HPBW = app.add(@uibutton, pr, 1, 4, 'state', 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', cb(@(~, ~) app.onCutChanged()));
            u.HPBWLabel = app.add(@uilabel, pr, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            u.EGrid = uigridlayout(pr, [3 1]); u.EGrid.Layout.Row = 3; u.EGrid.Layout.Column = 4;
            u.ChkTotal = app.add(@uicheckbox, u.EGrid, 1, 1, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', cb(@(~, ~) app.onCutChanged()));
            u.ChkA = app.add(@uicheckbox, u.EGrid, 2, 1, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', cb(@(~, ~) app.onCutChanged()));
            u.ChkB = app.add(@uicheckbox, u.EGrid, 3, 1, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', cb(@(~, ~) app.onCutChanged()));
            u.ExportCut = app.add(@uibutton, pr, 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', cb(@(~, ~) app.exportCut()));
            u.RectTab = uitab(u.CutTabs, 'Title', 'Rectangular Cut Plot'); u.RectAxes = uiaxes(uigridlayout(u.RectTab, [1 1]));
            xlabel(u.RectAxes, 'Theta (degree)'); ylabel(u.RectAxes, 'Magnitude (dB)'); u.RectAxes.Box = 'on';

            % ---- Main tab: plot control -----------------------------------------------------------------------
            u.PanelCtrl = app.add(@uipanel, g, 2, [13 14], 'Title', 'Plot Control 🎨', 'Visible', 'off');
            kg = uigridlayout(u.PanelCtrl, [15 2], 'RowHeight', repmat({'fit'}, 1, 15));
            app.lbl(kg, 'Component', 1, 1);
            u.Component = app.add(@uidropdown, kg, 1, 2, 'Items', cellstr(app.CompLabels), 'ItemsData', cellstr(app.Comps), 'ValueChangedFcn', cb(@(~, ~) app.updateView(true)));
            app.lbl(kg, 'Cut type', 2, 1); u.CutType = app.add(@uidropdown, kg, 2, 2, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', cb(@(s, ~) app.onCutChanged(s)));
            app.lbl(kg, 'Cut value', 3, 1); u.CutValue = app.add(@uispinner, kg, 3, 2, 'Limits', [0 360], 'ValueChangedFcn', cb(@(~, ~) app.onCutChanged()));
            app.lbl(kg, 'Cut fields', 4, 1);
            u.CutBasis = app.add(@uidropdown, kg, 4, 2, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Enable', 'off', 'UserData', true, 'ValueChangedFcn', cb(@(s, ~) app.onCutChanged(s)));
            app.lbl(kg, 'Colorbar max', 5, 1); u.Cmax = app.add(@uispinner, kg, 5, 2, 'Limits', app.DBRange, 'Value', 10);
            app.lbl(kg, 'Colorbar min', 6, 1); u.Cmin = app.add(@uispinner, kg, 6, 2, 'Limits', app.DBRange, 'Value', -40);
            set([u.Cmin, u.Cmax], 'ValueChangedFcn', @(~, ~) app.setRange("all", [app.ui.Cmin.Value, app.ui.Cmax.Value]));
            app.lbl(kg, 'Colorbar step', 7, 1); u.Cstep = app.add(@uispinner, kg, 7, 2, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', @(~, ~) app.applyFullRange());
            app.lbl(kg, 'Adjust Colorbar', 8, 1);
            u.ApplyClim = app.add(@uibutton, kg, 8, 2, 'Text', 'Apply', 'Tooltip', 'Apply to full-pattern plots; the cut range follows.', 'ButtonPushedFcn', @(~, ~) app.setRange("all", [app.ui.Cmin.Value, app.ui.Cmax.Value]));
            app.lbl(kg, '3D view', 9, 1);
            u.View3D = app.add(@uidropdown, kg, 9, 2, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Tooltip', 'Camera direction for the 3D pattern tabs.', 'ValueChangedFcn', @(~, ~) app.onViewChanged());
            u.PhiSpan = app.add(@uiswitch, kg, 10, [1 2], 'slider', 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'ValueChangedFcn', cb(@(~, ~) app.onSpanChanged()));
            u.ThetaSpan = app.add(@uiswitch, kg, 11, [1 2], 'slider', 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'ValueChangedFcn', cb(@(~, ~) app.onSpanChanged()));
            u.EHPlane = app.add(@uiswitch, kg, 12, [1 2], 'slider', 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'ValueChangedFcn', cb(@(~, ~) app.onEHPlane()));
            u.Overlay = app.add(@uicheckbox, kg, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', cb(@(~, ~) app.refreshOverlay()));
            u.POB = app.add(@uicheckbox, kg, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', @(~, ~) app.syncTips());
            u.HPBWBounds = app.add(@uicheckbox, kg, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', @(~, ~) app.syncTips());

            % ---- Main tab: data tables + status ---------------------------------------------------------------
            u.OutFilter = app.add(@uidropdown, g, 3, [13 14], 'Items', {'Select Output:'}, 'Visible', 'off', 'ValueChangedFcn', cb(@(~, ~) app.filterOutput()));
            u.DataTabs = app.add(@uitabgroup, g, 4, [1 14], 'Visible', 'off');
            t = uitab(u.DataTabs, 'Title', 'Results 📤', 'ButtonDownFcn', @(~, ~) set(app.ui.OutFilter, 'Visible', 'on'));
            u.OutTable = uitable(uigridlayout(t, [1 1]), 'ColumnWidth', '1x', 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true, 'Visible', 'off');
            u.InTable = uitable(uigridlayout(uitab(u.DataTabs, 'Title', 'Input 📥'), [1 1]), 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true, 'Visible', 'off');
            u.MetaTable = uitable(uigridlayout(uitab(u.DataTabs, 'Title', 'Metadata 📋'), [1 1]), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            u.Status = app.add(@uilabel, g, 5, [1 14], 'Interpreter', 'html', 'Text', 'Ready -- load an antenna pattern file to begin 🚀', 'UserData', 'Ready 🚀');

            % ---- Coverage tab ---------------------------------------------------------------------------------
            cg = uigridlayout(u.CovTab, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            u.CovParamGrid = uigridlayout(app.add(@uipanel, cg, 1, [1 5], 'Title', 'Inputs & Parameters 🎛️'), 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'});
            q = u.CovParamGrid;
            u.CovType = app.add(@uibuttongroup, q, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', cb(@(~, ~) app.covTypeChanged()));
            u.CovSph = uiradiobutton(u.CovType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            u.CovCon = uiradiobutton(u.CovType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            u.CovOrientLabel = app.lbl(q, 'Orientation 🧭:', 3, 1, 'Enable', 'off');
            u.CovOrient = app.add(@uidropdown, q, 3, 2, 'Items', [{'Auto'}, app.Axes.labels], 'ItemsData', 0:6, 'Enable', 'off', 'ValueChangedFcn', cb(@(~, ~) app.covOrientChanged()));
            u.CovCompLabel = app.lbl(q, 'Component:', 4, 1, 'Enable', 'off');
            u.CovComp = app.add(@uidropdown, q, 4, 2, 'Items', {'E_Total_dB'}, 'Enable', 'off', 'ValueChangedFcn', cb(@(~, ~) app.covCompChanged()));
            u.CovPathLabel = app.lbl(q, 'Antenna Pattern:', 1, 3); u.CovPath = app.add(@uieditfield, q, 1, [4 8], 'text');
            u.CovLoad = app.add(@uibutton, q, 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', cb(@(~, ~) app.covLoad()));
            u.CovCompute = app.add(@uibutton, q, 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', cb(@(~, ~) app.covCompute()));
            u.ThrMinLabel = app.lbl(q, 'Threshold  Min (dB):', 2, 3); u.ThrMin = app.add(@uispinner, q, 2, 4, 'Value', -40);
            u.ThrMaxLabel = app.lbl(q, 'Threshold  Max (dB):', 2, 5); u.ThrMax = app.add(@uispinner, q, 2, 6, 'Value', 10);
            u.ThrStepLabel = app.lbl(q, 'Step (dB):', 2, 7); u.ThrStep = app.add(@uispinner, q, 2, 8, 'Value', 1);
            u.CovReset = app.add(@uibutton, q, 2, 9, 'Text', '🔄 Reset', 'Enable', 'off', 'ButtonPushedFcn', cb(@(~, ~) app.covReset()));
            u.CovExport = app.add(@uibutton, q, 2, 10, 'Text', '💾 Export Results', 'Enable', 'off', 'ButtonPushedFcn', cb(@(~, ~) app.covExport()));
            u.ConeThLabel = app.lbl(q, 'Cone θ₀ (°):', 3, 3, 'Enable', 'off'); u.ConeTh = app.add(@uispinner, q, 3, 4, 'Limits', [0 180], 'Enable', 'off');
            u.ConePhLabel = app.lbl(q, 'Cone φ₀ (°):', 3, 5, 'Enable', 'off'); u.ConePh = app.add(@uispinner, q, 3, 6, 'Limits', [0 360], 'Enable', 'off');
            u.ConeAngLabel = app.lbl(q, 'Cone Angle α (°):', 3, 7, 'Enable', 'off'); u.ConeAng = app.add(@uispinner, q, 3, 8, 'Limits', [0 180], 'Value', 45, 'Enable', 'off');
            u.CovClear = app.add(@uibutton, q, 3, 9, 'Text', '🧹 Clear DataTips', 'Enable', 'off', 'ButtonPushedFcn', cb(@(~, ~) app.covClear()));
            u.CovToMain = app.add(@uibutton, q, 3, 10, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~, ~) set(app.ui.Tabs, 'SelectedTab', app.ui.MainTab));
            u.QCovLabel = app.lbl(q, 'Coverage @ dB:', 4, 3, 'Visible', 'off'); u.QCov = app.add(@uispinner, q, 4, 4, 'ValueDisplayFormat', '%g dB', 'Visible', 'off');
            u.QCovBtn = app.add(@uibutton, q, 4, 5, 'Text', '⯐ Query Coverage', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', cb(@(~, ~) app.covQuery("cov")));
            u.QThrLabel = app.lbl(q, 'Threshold @ %:', 4, 6, 'Visible', 'off'); u.QThr = app.add(@uispinner, q, 4, 7, 'Value', 50, 'ValueDisplayFormat', '%g%%', 'Visible', 'off');
            u.QThrBtn = app.add(@uibutton, q, 4, 8, 'Text', '🔍 Query Threshold', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', cb(@(~, ~) app.covQuery("thr")));
            u.CovFormatLabel = app.lbl(q, 'Format:', 4, 9, 'Visible', 'off'); u.CovFormat = app.formatDropdown(q, 4, 10, cb(@(~, ~) app.covFormatChanged()));
            u.CovPanelResults = app.add(@uipanel, cg, 2, [1 5], 'Title', 'Results', 'Visible', 'off');
            rg = uigridlayout(u.CovPanelResults, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            u.CovTree = app.add(@uitree, rg, [1 2], 1, 'checkbox', 'SelectionChangedFcn', cb(@(~, ~) app.covSelected()), 'CheckedNodesChangedFcn', cb(@(~, ~) app.covChecked()));
            u.CovRoot = uitreenode(u.CovTree, 'Text', 'Coverage Results');
            u.CovAxes = app.add(@uiaxes, rg, 1, [2 4]); title(u.CovAxes, 'Coverage vs Threshold'); xlabel(u.CovAxes, 'Threshold (dB)'); ylabel(u.CovAxes, 'Coverage (%)');
            u.CovAxes.Interactions = dataTipInteraction;   % Display-only axes
            u.CovXMin = app.add(@uispinner, rg, 2, 2, 'Limits', app.DBRange, 'Value', -40, 'ValueChangedFcn', cb(@(s, ~) app.covXChanged(s, [])));
            u.CovXSlider = app.add(@uislider, rg, 2, 3, 'range', 'Limits', app.DBRange, 'Value', [-40 10], 'ValueChangedFcn', cb(@(s, e) app.covXChanged(s, e.Value)), 'ValueChangingFcn', cb(@(s, e) app.covXChanged(s, e.Value)));
            u.CovXMax = app.add(@uispinner, rg, 2, 4, 'Limits', app.DBRange, 'Value', 10, 'ValueChangedFcn', cb(@(s, ~) app.covXChanged(s, [])));
            u.CovTable = app.add(@uitable, rg, [1 2], 5, 'ColumnWidth', '1x', 'RowName', {});
            u.CovStatus = app.add(@uilabel, cg, 3, [1 5], 'Interpreter', 'html', 'Text', 'Ready -- load an antenna pattern file to begin 🚀', 'UserData', 'Ready 🚀');
            app.ui = u;
        end
    end
end

%% ====================================================================== local functions: I/O
function tf = isGenericText(fp)
[~, ~, e] = fileparts(fp); tf = ismember(lower(e), {'.csv', '.txt', '.dat'});
end

function T = fieldTable(theta, phi, Eth, Eph)
%fieldTable Canonical complex-field table {Theta, Phi, Re_Eth, Im_Eth, Re_Eph, Im_Eph}.
T = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function [Eth, Eph] = circToLinear(Ercp, Elcp)
Eth = (Ercp + Elcp) / sqrt(2); Eph = (Ercp - Elcp) / (1i*sqrt(2));
end

function E = magPhase(dB, deg)
E = 10.^(dB/20) .* exp(1i*deg2rad(deg));
end

function out = readPattern(fp, kind, cached)
%readPattern Universal source reader → struct(rawTbl, blocks{}, freqs, userData). UI-independent.
%   kind   : interpretation of generic text files ('gain', 'linear_magphase', ... ); ignored for self-describing formats.
%   cached : previously imported generic table, so format changes do not re-read the file.
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, 'userData', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false));
switch ext
    case {'XLSX', 'XLS'},        out = readExcelMatrix(fp);
    case {'CSV', 'TXT', 'DAT'},  out = readGenericText(fp, string(kind), cached, out);
    case 'CUT',                  out = readGraspCut(fp, out);
    otherwise,                   out = readFarField(fp, ext, out);
end
end

function out = readGenericText(fp, kind, T, out)
% Generic numeric table: coverage results (auto-detected) or a pattern interpreted per KIND.
if isempty(T)
    o = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    o = setvartype(o, 'double'); o = setvaropts(o, 'TrimNonNumeric', true); o.VariableNamingRule = 'preserve';
    T = rmmissing(readtable(fp, o));
end
n = width(T); assert(n >= 2 && ~isempty(T), 'readFile:InvalidFormat', 'File needs at least two numeric columns.');
names = lower(string(T.Properties.VariableNames)); hasHeaders = ~all(startsWith(names, "var")); c1 = T{:, 1}; c2 = T{:, 2};
covHeader = contains(names(1), "threshold") || any(contains(names(2:end), "coverage"));
if (kind == "gain" || n < 6 || covHeader) && all(isfinite(c2) & c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:n-1))]; end
    out.rawTbl = T; out.userData.isCoverage = true; return
end
raw = T;
if kind == "gain"   % Gain-only pattern: the wider-spanning of the first two columns is phi.
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    T = movevars(T, 'Theta', 'Before', 1); if ~hasHeaders, raw = T; end
    out.rawTbl = raw; out.blocks = {T}; out.userData.isGainOnly = true; return
end
assert(n >= 6, 'readFile:TextEFieldColumns', 'The selected generic E-field format requires six numeric columns.');
V = T{:, 3:6}; magPh = endsWith(kind, "magphase"); layout = "not applicable";
if magPh
    isPhase = max(abs(V), [], 1, 'omitnan') > 100;   % Phase columns exceed 100°; detects grouped vs interleaved layouts
    if isPhase(2) && ~isPhase(3), m = [1 3]; p = [2 4]; layout = "interleaved"; else, m = [1 2]; p = [3 4]; layout = "grouped"; end
    A = magPhase(V(:, m(1)), V(:, p(1))); B = magPhase(V(:, m(2)), V(:, p(2)));
else
    A = complex(V(:, 1), V(:, 2)); B = complex(V(:, 3), V(:, 4));
end
if startsWith(kind, "linear"), Eth = A; Eph = B; comp = ["E_TH", "E_PH"]; rect = ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"];
else
    if startsWith(kind, "rcp"), [Eth, Eph] = circToLinear(A, B); else, [Eth, Eph] = circToLinear(B, A); end
    comp = ["POL1", "POL2"]; rect = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"];
end
if magPh, gen = [comp + "_dB", comp + "_deg"]; if layout == "interleaved", gen = gen([1 3 2 4]); end, else, gen = rect; end
if ~hasHeaders, raw.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", gen]); end
out.userData.source = sprintf('Generic text (%s, %s)', kind, layout); out.rawTbl = raw; out.blocks = {fieldTable(c1, c2, Eth, Eph)};
end

function out = readGraspCut(fp, out)
% TICRA/GRASP .cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks, one per phi (theta when ICUT = 2).
out.userData.source = 'TICRA/GRASP CUT';
L = readlines(fp); L(strlength(strtrim(L)) == 0) = []; i = 1; th = {}; ph = {}; D = {}; icomp = 1; icut = 1;
while i < numel(L)
    p = sscanf(L(i+1), '%f'); assert(numel(p) >= 7, 'parseCutFile:bad', 'Could not parse cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6);
    B = reshape(sscanf(strjoin(L(i+2:i+1+n), ' '), '%f'), 2*p(7), []).';
    th{end+1, 1} = p(1) + (0:n-1)'*p(2); ph{end+1, 1} = repmat(p(4), n, 1); D{end+1, 1} = B(:, 1:4); i = i + 2 + n; %#ok<AGROW>
end
th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:});
if icut == 2, [th, ph] = deal(ph, th); end
neg = th < 0; ph(neg) = ph(neg) + 180; th(neg) = -th(neg);   % Fold negative theta onto the opposite half-plane
if isscalar(unique(ph)), n = numel(th); th = repmat(th, 36, 1); ph = repelem((0:10:350)', n); D = repmat(D, 36, 1); end   % Single cut → body of revolution
A = complex(D(:, 1), D(:, 2)); B = complex(D(:, 3), D(:, 4));
if icomp == 2, names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; [Eth, Eph] = circToLinear(A, B);
else, names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; Eth = A; Eph = B; end
out.rawTbl = array2table([th, ph, D], 'VariableNames', [{'Theta', 'Phi'}, names]); out.blocks = {fieldTable(th, ph, Eth, Eph)};
end

function out = readFarField(fp, ext, out)
% Far-field text exports: XGTD UAN/FZ, GRASP OUT, CST FFS, FEKO FFE and HFSS FFD (multi-frequency blocks).
[nHdr, ffd] = findHeader(fp);
o = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = readmatrix(fp, setvartype(o, o.VariableNames, 'double')); M = M(~all(isnan(M), 2), 1:min(end, 6));
switch ext
    case {'FZ', 'UAN'}   % Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
        out.userData.source = ['XGTD ' ext]; names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'};
        th = M(:, 1); ph = M(:, 2); Eth = magPhase(M(:, 3), M(:, 5)); Eph = magPhase(M(:, 4), M(:, 6));
    case 'OUT'           % Theta Phi Re(RHCP) Im(RHCP) Re(LHCP) Im(LHCP)
        out.userData.source = 'TICRA/GRASP OUT'; names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'};
        th = M(:, 1); ph = M(:, 2); [Eth, Eph] = circToLinear(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)));
    case 'FFS'           % Phi Theta Re(Eth) Im(Eth) Re(Eph) Im(Eph)
        out.userData.source = 'CST FFS'; names = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'};
        ph = M(:, 1); th = M(:, 2); Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
    case 'FFE'           % Theta Phi Re(Eth) Im(Eth) Re(Eph) Im(Eph) [extra columns ignored]
        out.userData.source = 'FEKO FFE'; names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'};
        th = M(:, 1); ph = M(:, 2); Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
    case 'FFD'           % Header-defined grid; Re(Eth) Im(Eth) Re(Eph) Im(Eph) rows, "Frequency f" separator rows between blocks
        out.userData.source = 'HFSS FFD'; assert(ffd.isFFD, 'readFile:ffd', 'FFD header (theta/phi ranges) not found.');
        thAxis = linspace(ffd.theta(1), ffd.theta(2), ffd.theta(3)).'; phAxis = linspace(ffd.phi(1), ffd.phi(2), ffd.phi(3)).';
        th = repelem(thAxis, numel(phAxis)); ph = repmat(phAxis, numel(thAxis), 1); per = numel(th);
        sep = isnan(M(:, 1)); freqs = [ffd.freq(:); M(sep & isfinite(M(:, 2)), 2)].'; rows = M(~sep, 1:4);
        assert(mod(size(rows, 1), per) == 0, 'readFile:ffd', 'FFD mismatch: row count does not match the theta/phi grid.');
        nb = size(rows, 1) / per; freqs(end+1:nb) = NaN; freqs = freqs(1:nb);
        out.userData.isDep = nb > 1 || any(isfinite(freqs)); out.freqs = freqs;
        out.blocks = cellfun(@(B) fieldTable(th, ph, complex(B(:, 1), B(:, 2)), complex(B(:, 3), B(:, 4))), mat2cell(rows, repmat(per, nb, 1), 4), 'UniformOutput', false);
        out.rawTbl = out.blocks{1}; return
    otherwise, error('readFile:unsupported', 'Unsupported format: %s', ext);
end
out.rawTbl = array2table(M(:, 1:6), 'VariableNames', names); out.blocks = {fieldTable(th, ph, Eth, Eph)};
end

function [nHdr, ffd] = findHeader(fp)
%findHeader Number of leading non-data lines; recognises the HFSS FFD header (two numeric triples [+ Frequencies line]).
lines = readlines(fp); ffd = struct('isFFD', false, 'theta', [], 'phi', [], 'freq', []);
idx = find(strlength(strtrim(lines)) > 0, 3);   % First three non-empty lines
trip = cellfun(@(s) sscanf(s, '%f').', cellstr(lines(idx(1:min(2, end)))), 'UniformOutput', false);
if numel(trip) == 2 && all(cellfun(@numel, trip) == 3)
    ffd.theta = trip{1}; ffd.phi = trip{2}; ffd.theta(3) = round(ffd.theta(3)); ffd.phi(3) = round(ffd.phi(3)); nHdr = idx(2);
    ffd.isFFD = all(isfinite([ffd.theta, ffd.phi])) && ffd.theta(3) >= 1 && ffd.phi(3) >= 1;
    if numel(idx) > 2
        tok = regexp(char(strtrim(lines(idx(3)))), '^frequencies?\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok), f = sscanf(tok{1}, '%f'); if ~isscalar(f), ffd.freq = f(:); end; nHdr = idx(3); end   % A bare count is metadata only
    end
    if ffd.isFFD, return; end
end
num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?';
isData = ~cellfun(@isempty, regexp(cellstr(lines), ['^\s*' num '(?:[\s,;]+' num '){3,}\s*$'], 'once'));   % ≥ 4 numeric fields
nHdr = find(isData, 1) - 1; if isempty(nHdr), nHdr = 0; end
end

function out = readExcelMatrix(fp)
%readExcelMatrix Excel matrix workbooks: sheet 1 = summary, fixed Eth/Eph and/or RHCP/LHCP gain+phase sheets (C3-origin).
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"];
lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'readFile:ExcelMatrixFormat', 'Unsupported Excel workbook: no Eth/Eph or RHCP/LHCP component sheets found.');
req = [circ(1:4*hasC), lin(1:4*hasL)]; M = struct(); th = []; ph = [];
for k = 1:numel(req)
    [t, p, D] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, req(k)), 1)));
    if k == 1, th = t; ph = p;
    else, assert(isequal(size(t), size(th)) && isequal(size(p), size(ph)) && max(abs(t - th)) < 1e-9 && max(abs(p - ph)) < 1e-9, ...
            'readFile:ExcelMatrixGrid', 'All Excel Matrix component sheets must use the same theta/phi grid.'); end
    M.(char(req(k))) = D;
end
if hasL, Eth = magPhase(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = magPhase(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees);
else, [Eth, Eph] = circToLinear(magPhase(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), magPhase(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees)); end
[P, T] = meshgrid(ph, th); block = fieldTable(T, P, Eth, Eph); raw = block;
for k = 1:numel(req), raw.(char(req(k))) = reshape(M.(char(req(k))), [], 1); end   % Keep the workbook quantities inspectable
formats = ["Excel Matrix Format 1 (Eth/Eph)", "Excel Matrix Format 2 (Ercp/Elcp)", "Excel Matrix Format 3 (Ercp/Elcp + Eth/Eph)"];
ud = readExcelSummary(fp, sheets(1)); ud.source = char(formats(hasL + 2*hasC)); [ud.isGainOnly, ud.isCoverage, ud.isDep] = deal(false);
freqs = NaN; if isfinite(ud.frequencyMHz), freqs = ud.frequencyMHz * 1e6; end
out = struct('rawTbl', raw, 'blocks', {{block}}, 'freqs', freqs, 'userData', ud);
end

function [th, ph, D] = readMatrixSheet(fp, sheet)
% One C3-origin matrix: row 2 (C→) = phi, column B (3→) = theta. readcell keeps worksheet coordinates intact.
C = readcell(fp, 'Sheet', char(sheet));
assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'readFile:ExcelMatrixSheet', 'Sheet "%s" does not contain a C3-origin matrix.', sheet);
isNum = @(x) isnumeric(x) && isscalar(x) && isfinite(x);
pm = cellfun(isNum, C(2, 3:end)); tm = cellfun(isNum, C(3:end, 2));
np = find(~pm, 1) - 1; if isempty(np), np = numel(pm); end; nt = find(~tm, 1) - 1; if isempty(nt), nt = numel(tm); end
assert(nt > 0 && np > 0 && ~any(pm(np+1:end)) && ~any(tm(nt+1:end)), 'readFile:ExcelMatrixAxis', 'Sheet "%s" has missing or non-contiguous theta/phi axes.', sheet);
ph = cell2mat(C(2, 2 + (1:np))); th = cell2mat(C(2 + (1:nt), 2)); Dc = C(2 + (1:nt), 2 + (1:np));
assert(all(cellfun(isNum, Dc), 'all'), 'readFile:ExcelMatrixSheet', 'Sheet "%s" contains nonnumeric/missing matrix samples.', sheet);
D = cell2mat(Dc);
assert(all(diff(th) > 0) && all(diff(ph) > 0) && th(1) >= -1e-9 && th(end) <= 180 + 1e-9 && ph(1) >= -1e-9 && ph(end) < 360 + 1e-9, ...
    'readFile:ExcelMatrixAxis', 'Sheet "%s" must have strictly increasing axes within theta 0..180 and phi 0..360.', sheet);
end

function ud = readExcelSummary(fp, sheet)
% Summary sheet → label/value pairs (labels in column B, first non-empty value in C..E); the simulation frequency is normalized.
ud = struct('summarySheet', char(sheet), 'frequencyMHz', NaN);
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
for r = 1:size(C, 1)
    lab = C{r, 2}; if ~(ischar(lab) || isstring(lab)) || strlength(strtrim(string(lab))) == 0, continue; end
    vals = C(r, 3:min(end, 5)); vals = vals(~cellfun(@(v) isempty(v) || isa(v, 'missing'), vals)); if isempty(vals), continue; end
    ud.(matlab.lang.makeValidName(lower(regexprep(strtrim(string(lab)), '[^a-zA-Z0-9]+', '_')))) = vals{1};
end
keys = fieldnames(ud); k = find(contains(keys, 'simulation_freq'), 1);
if ~isempty(k) && isnumeric(ud.(keys{k})), ud.frequencyMHz = double(ud.(keys{k})); end
end

function writeUAN(U, fp)
%writeUAN Canonical XGTD UAN header followed by tab-delimited magnitude/phase rows.
hdr = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
    min(U.Phi), max(U.Phi), gridStep(mod(U.Phi, 360)), min(U.Theta), max(U.Theta), gridStep(U.Theta), max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan'));
writelines(hdr, fp); writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
end

%% ====================================================================== local functions: math (pure; never see the app)
function T = normalizePattern(T)
%normalizePattern Canonical sphere: Theta [0,180], Phi [0,360] with the 0° seam duplicated at 360°, unique directions.
th = T.Theta; ph = T.Phi;
if any(th < 0) && min(th) >= -90 && max(th) <= 90, th = 90 - th; end     % Elevation convention
neg = th < 0; th(neg) = -th(neg); ph(neg) = ph(neg) + 180;               % Negative theta → opposite half-plane
th = mod(th, 360); over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;
T.Theta = th; T.Phi = mod(ph, 360);
num = varfun(@isnumeric, T, 'OutputFormat', 'uniform'); T{:, num} = round(T{:, num}, 5);   % Remove 1e-15 seam artefacts once, here
T.Phi = mod(T.Phi, 360);
[~, u] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(u, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function R = resampleCanonical(T, step)
%resampleCanonical Resample primitive columns onto a regular STEP° grid (theta 0..180, phi 0..360 incl. the seam).
%   E-field Re/Im columns interpolate directly; gain-like dB columns always interpolate in linear power.
keep = isfinite(T.Theta) & isfinite(T.Phi) & abs(T.Phi - 360) > 1e-9; T = T(keep, :);
[~, u] = unique([T.Theta, mod(T.Phi, 360)], 'rows', 'stable'); T = T(u, :); th = T.Theta; ph = mod(T.Phi, 360);
tp = 0:step:360; if tp(end) < 360, tp(end+1) = 360; end
[qPhi, qTh] = meshgrid(tp, 0:step:180); R = table(qTh(:), qPhi(:), 'VariableNames', {'Theta', 'Phi'});
sTh = unique(th); sPh = unique(ph); regular = numel(sTh)*numel(sPh) == numel(th);
isField = all(ismember(["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"], T.Properties.VariableNames));
if regular
    [G_phi, G_th] = meshgrid([sPh; sPh(1) + 360], sTh);   % Periodic closure column
    [~, it] = ismember(th, sTh); [~, ip] = ismember(ph, sPh); idx = sub2ind([numel(sTh), numel(sPh)], it, ip);
end
for c = T.Properties.VariableNames(3:end)
    name = c{1}; v = double(T.(name)); power = ~isField && isGainDB(name);
    if power, v = 10.^(v/10); end
    if regular
        Z = nan(numel(sTh), numel(sPh)); Z(idx) = v; Z = [Z, Z(:, 1)]; %#ok<AGROW>
        q = interp2(G_phi, G_th, Z, qPhi, qTh, 'linear', NaN); miss = ~isfinite(q);
        if any(miss(:)), qn = interp2(G_phi, G_th, Z, qPhi, qTh, 'nearest', NaN); q(miss) = qn(miss); end
    else
        F = scatteredInterpolant(ph, th, v, 'linear', 'nearest'); q = F(qPhi, qTh);
    end
    if power, q = 10*log10(max(q, realmin)); end
    R.(name) = q(:);
end
R.Properties.UserData = T.Properties.UserData;
end

function tf = isGainDB(name)
k = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', ''); tf = contains(k, ["gain", "directivity", "eirp"]) || endsWith(k, "db");
end

function [P, info] = calcPattern(S, prm)
%calcPattern Canonical source → processed pattern table + polarization summary (allocation-light hot path).
ud = S.Properties.UserData; info = struct('pol', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
if ud.isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + prm.GainLoss_dB; end; return
end
Eth = complex(S.Re_Eth, S.Im_Eth) * prm.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph) * prm.FieldScale;
Er = (Eth + 1i*Eph) / sqrt(2); El = (Eth - 1i*Eph) / sqrt(2);
mTh = abs(Eth); mPh = abs(Eph); mR = abs(Er); mL = abs(El); total = 10*log10(max(mTh.^2 + mPh.^2, eps));
% Dominant polarization from mean component power: drives co/cross ordering, the label and the Auto Rx sense.
pw = [mean(mTh.^2, 'omitnan'), mean(mPh.^2, 'omitnan'), mean(mR.^2, 'omitnan'), mean(mL.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif pw(1) >= pw(2), info.pol = 'Linear (Vertical)'; else, info.pol = 'Linear (Horizontal)'; end
% Signed axial ratio (+ = RHCP sense, − = LHCP sense); equal circular components are the linear limit → −100 dB floor.
d = mR - mL; sense = sign(d); sense(~isfinite(d)) = 0; ar = (mR + mL) ./ max(abs(d), eps);
arDB = min(20*log10(ar), 250) .* sense; arDB(isfinite(d) & abs(d) <= eps*max(mR + mL, 1)) = -100;
% Polarization loss factor against an incident wave of axial ratio Rw and the selected (or Auto) sense.
switch prm.RxMode, case "RHCP", ws = 1; case "LHCP", ws = -1; otherwise, ws = 2*(info.pairs.Circular(1) == "E_RCP") - 1; end
ra = ar .* sense; ra(sense == 0) = 1e12; rw = ws * 10^(prm.RxAR_dB/20);
plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1)) ./ (2*(ra.^2 + 1)*(rw^2 + 1)); plfDB = 10*log10(min(max(plf, eps), 1));
eirp = prm.Pt_dBW + total; eirpW = 10.^(eirp/10); dB = @(m) 20*log10(max(m, eps)); phs = @(E) rad2deg(angle(E));
P = table(S.Theta, S.Phi, total, arDB, dB(mR), dB(mL), plfDB, total + plfDB, dB(mTh), dB(mPh), phs(Eth), phs(Eph), phs(Er), phs(El), ...
    eirp, eirpW / (4*pi*prm.R_m^2), sqrt(30*eirpW) / prm.R_m, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', ...
    'PLF_dB', 'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
P.Properties.UserData = ud;
end

function info = resolvePeak(v, pct, excess)
%resolvePeak Outlier-robust peak: the raw maximum is accepted unless it exceeds the P<pct> level by more than EXCESS dB;
%   then the highest sample at or below that level becomes the effective peak and everything above it is flagged.
v = double(v(:)); ok = isfinite(v);
info = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(v)), 'wasAdjusted', false);
if ~any(ok), return; end
[info.rawValue, info.rawIndex] = max(v, [], 'omitnan'); info.value = info.rawValue; info.index = info.rawIndex;
level = percentile(v(ok), pct);
if info.rawValue > level + excess && any(ok & v <= level)
    info.outlierMask = ok & v > level; c = v; c(info.outlierMask | ~ok) = -Inf;
    [info.value, info.index] = max(c); info.wasAdjusted = true;
end
end

function q = percentile(v, p)
%percentile Toolbox-free equivalent of prctile: linear interpolation between order statistics placed at 100·(k−0.5)/n.
s = sort(v(:)); n = numel(s); if n == 1, q = s; return; end
q = interp1(100*((1:n) - 0.5)/n, s, min(max(p, 50/n), 100 - 50/n));
end

function b = peakWindow(values, pct, excess)
%peakWindow 50-dB display / threshold window whose top is the effective peak rounded up to 5 dB (clamped to [−250, 100]).
v = double(values(isfinite(values))); b = [-40 10]; if isempty(v), return; end
pk = resolvePeak(v, pct, excess); if ~isfinite(pk.value), return; end
hi = min(max(ceil(pk.value/5)*5, -249), 100); b = [max(hi - 50, -250), hi];
end

function r = clampRange(v, b)
%clampRange Sorted, clamped [lo hi] with a one-unit minimum width.
v = sort(double(v(:).')); if numel(v) < 2 || any(~isfinite(v(1:2))), r = b; return; end
r = [max(b(1), v(1)), min(b(2), v(2))];
if diff(r) < 1, r(2) = min(b(2), r(1) + 1); r(1) = max(b(1), r(2) - 1); end
end

function t = axisTicks(lim, step)
%axisTicks Regular ticks inside LIM including both end points (empty when degenerate or more than 60 ticks).
t = []; if numel(lim) ~= 2 || ~all(isfinite([lim(:); step])) || step <= 0 || lim(1) >= lim(2), return; end
t = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)]); if numel(t) > 60, t = []; end
end

function s = fmt(v, p)
%fmt Compact number text: up to 2 decimals with trailing zeros trimmed, or exactly P decimals; 'n/a' when not finite.
if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return; end
if nargin > 1, s = sprintf('%.*f', p, v); else, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); end
end

function step = gridStep(v)
%gridStep Smallest positive spacing between distinct finite values (NaN when undefined).
d = diff(unique(v(isfinite(v)))); d = d(d > 1e-9); step = NaN; if ~isempty(d), step = min(d); end
end

function w = solidWeights(theta, phi)
%solidWeights Exact solid angle of each uniform (θ, φ) cell; the duplicated seam column (360° or 180° when signed) gets zero weight.
dt = gridStep(theta); dp = gridStep(mod(phi, 360)); if ~isfinite(dt), dt = 180; end; if ~isfinite(dp), dp = 360; end
w = (cosd(max(theta - dt/2, 0)) - cosd(min(theta + dt/2, 180))) * deg2rad(dp);
seam = 360 - 180*any(phi < 0); w(abs(phi - seam) < 1e-9) = 0;
end

function [peak, axisIndex] = calcOrientation(theta, phi, gainDB, w, axes, pct, excess)
%calcOrientation Peak policy + the principal axis whose 45° cone captures the most solid-angle-weighted power (physical theta).
peak = resolvePeak(gainDB, pct, excess); g = gainDB; if peak.wasAdjusted, g(peak.outlierMask) = NaN; end
sw = 10.^((g - peak.value)/10) .* w; sw(~isfinite(sw)) = 0;
A = [sind(axes.theta(:)).*cosd(axes.phi(:)), sind(axes.theta(:)).*sind(axes.phi(:)), cosd(axes.theta(:))];
S = [sind(theta).*cosd(phi), sind(theta).*sind(phi), cosd(theta)];
[~, axisIndex] = max(sw.' * double(S * A.' >= cosd(45)));
end

function m = calcMetrics(theta, phi, gain, ar, w, axes, axisIndex, pct, excess)
%calcMetrics Scalar figures of merit from the total-gain pattern (physical theta): peak, HPBWs, F/B, directivity, efficiency.
pk = resolvePeak(gain, pct, excess); i = pk.index; g = gain; if pk.wasAdjusted, g(pk.outlierMask) = NaN; end
integrated = sum(10.^(g/10) .* w, 'omitnan'); eff = 100*integrated/(4*pi); if eff < 0 || eff > 100, eff = NaN; end
[~, back] = min(cosd(theta)*cosd(theta(i)) + sind(theta)*sind(theta(i)).*cosd(phi - phi(i)));
hType = 'Theta'; if axes.theta(axisIndex) == 90, hType = 'Phi'; end   % H-plane: phi cut at θ = 90° for transverse boresights
[eAng, eRows] = cutRows(theta, phi, 'Theta', axes.phi(axisIndex)); [hAng, hRows] = cutRows(theta, phi, hType, 90);
arPk = NaN; if ~isempty(ar), arPk = ar(i); end
m = struct('PeakGain_dB', pk.value, 'PeakTheta_deg', theta(i), 'PeakPhi_deg', phi(i), ...
    'HPBW_EPlane_deg', calcHPBW(eAng, gain(eRows)), 'HPBW_HPlane_deg', calcHPBW(hAng, gain(hRows)), 'FrontBack_dB', pk.value - gain(back), ...
    'PeakDirectivity_dB', 10*log10(max(4*pi*10^(pk.value/10) / max(integrated, eps), eps)), 'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', arPk);
end

function [ang, rows, fixed, sym, snapped] = cutRows(theta, phi, type, req)
%cutRows Rows and running angle of one full-circle cut, snapped to the nearest sampled plane (physical theta in, physical out).
if strcmp(type, 'Phi')   % Fixed theta, running phi
    v = unique(theta); [dist, k] = min(abs(v - req)); fixed = v(k); sym = 'θ';
    rows = find(abs(theta - fixed) < 1e-9); [ang, o] = sort(phi(rows)); rows = rows(o);
else                     % Fixed phi + its opposite half-plane, running theta 0..360
    p = mod(phi, 360); v = unique(p); [dist, k] = min(abs(mod(v - mod(req, 360) + 180, 360) - 180)); fixed = v(k); sym = 'φ';
    [~, ko] = min(abs(mod(v - fixed, 360) - 180));
    r1 = find(abs(p - fixed) < 1e-9); [~, o] = sort(theta(r1)); r1 = r1(o);
    r2 = find(abs(p - v(ko)) < 1e-9 & abs(theta - 180) > 1e-9); [~, o] = sort(theta(r2), 'descend'); r2 = r2(o);
    rows = [r1; r2]; ang = [theta(r1); 360 - theta(r2)];
end
snapped = dist > 0;
end

function [bw, lo, hi] = calcHPBW(ang, g, pk, pkAng)
%calcHPBW Half-power beamwidth of a circular cut from the linearly interpolated −3 dB crossings either side of the peak.
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(g); ang = ang(ok); g = g(ok);
if numel(g) < 3, return; end
if nargin < 3 || isempty(pk), [pk, i] = max(g); pkAng = ang(i); end
[rel, o] = sort(mod(ang - pkAng + 180, 360) - 180); g = g(o); half = pk - 3;
L = find(rel < 0 & g <= half, 1, 'last'); Rr = find(rel > 0 & g <= half, 1, 'first');
if isempty(L) || isempty(Rr) || L + 1 > numel(g) || g(L+1) == g(L) || g(Rr-1) == g(Rr), return; end
cross = @(a, b) rel(a) + (rel(b) - rel(a)) * (half - g(a)) / (g(b) - g(a));
lo = pkAng + cross(L, L+1); hi = pkAng + cross(Rr, Rr-1); bw = hi - lo;
end

function cov = coverageCCDF(gain, mask, thr, w)
%coverageCCDF Coverage(T) [%] = 100 · Σ I(G_i > T)·Ω_i / Σ_region Ω_i, evaluated for every threshold at once.
ok = mask(:) & isfinite(gain(:)) & isfinite(w(:)) & w(:) >= 0; g = gain(ok); ww = w(ok); tot = sum(ww);
cov = zeros(size(thr)); if tot > 0, cov = 100 * (ww.' * double(g > thr(:).')).' / tot; end
end

function t = thresholdAt(thr, cov, level)
%thresholdAt Invert a (non-increasing) coverage curve: the threshold at which LEVEL % coverage is reached.
ok = isfinite(thr) & isfinite(cov); thr = thr(ok); [c, i] = unique(cov(ok), 'last'); t = NaN;
if numel(c) > 1, t = interp1(c, thr(i), level, 'linear', NaN); end
end