classdef APAT_v3_M8_33 < matlab.apps.AppBase  %1836-lines %1. no Load check % Reset doesn't  delete DataTips & Projections %Adjusted Cone doesn't reflect
% APAT v3 M8 — Antenna Pattern Analyzer Tool (single-file App Designer-free implementation).
%
% DATA FLOW (one canonical pipeline, every stage is a pure function of the previous one)
%   file ──readPattern──▶ src{raw, blocks, freqs, meta}
%        ──normalizePattern──▶ stdTbl   canonical sphere: θ∈[0,180], φ∈[0,360] with one closing φ=360 copy
%        ──calcPattern──────▶ patTbl   every derived quantity at native resolution
%        ──applyStep────────▶ baseTbl  optional 1° resample of the *canonical* source, then calcPattern again
%        ──applySpan────────▶ viewTbl  φ display convention (0..360 | −180..180) + cached grid/geometry/dΩ
%        ──updateView───────▶ peak · boresight · metrics · tables · cut · full-pattern plots
%
% CONVENTIONS
%   • θ is ALWAYS stored physically (0° = +Z).  The "θ span" switch is a display transform (dispTheta).
%   • All UI handles live in app.ui (struct).  Annotations are managed purely through graphics Tags:
%       APAT_Surface  rendered pattern surfaces        APAT_POB      peak markers + their DataTips
%       APAT_HPBW     half-power boundary markers      APAT_CutOverlay 3-D cut overlays   CovQ_<mode>_<id> coverage queries
%   • Numerical services are local functions at the end of the file and never touch the app.

    properties (GetAccess = public, SetAccess = private)
        isClosing logical = false
    end

    properties (Access = public)
        ui struct = struct()                       % every UI handle (see createComponents)
        paxCut matlab.graphics.axis.PolarAxes
        paxPattern matlab.graphics.axis.PolarAxes
    end

    properties (Access = private)
        filePath char = ''
        fileName char = ''
        baseName char = ''
        folderPath char = ''
        src struct = struct()                      % readPattern result of the active file
        stdTbl table                               % canonical source (fields or gain)
        patTbl table                               % processed, native resolution
        baseTbl table                              % processed, selected step
        viewTbl table                              % displayed/exported (φ convention applied)
        grid struct = struct()                     % theta, phi, sz, idx(row→grid), thG, phG, phR, x, y, z, dOmega
        peak struct = struct()                     % resolvePeak() of the displayed component
        POB double = NaN
        POBth double = NaN
        POBph double = NaN
        polLabel char = 'n/a'
        polPairs struct = struct('Linear', ["E_TH","E_PH"], 'Circular', ["E_RCP","E_LCP"])
        boresight double = 1                       % index into Axes
        metrics struct = struct()
        autoCutBasis logical = true                % pick the cut basis from the detected polarization
        viewStamp double = 0                       % bumps whenever viewTbl changes
        fullLim double = [-40 10]                  % active full-pattern color range
        gainLim double = [-40 10]                  % non-AR color range remembered across components
        cutLim double = [-40 10]
        covRunID double = 0
        covPresetKey string = ""
        covXInit logical = false
        covThrInit logical = false
        defaults cell = {}
        statusTimer = []
        opDialog = []
        filterStyles cell = {}
    end

    properties (Constant, Access = private)
        Axes = struct('labels', {{'+Z','-Z','+X','-X','+Y','-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        CompKeys = ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","AR_dB","Gain_PolCorrected_dB"]
        CompNames = ["Total Gain","Etheta Gain","Ephi Gain","RHCP Gain","LHCP Gain","Axial Ratio","Polarized Gain"]
        HiddenCols = ["E_TH_dB","E_PH_dB","E_TH_Phase","E_PH_Phase","E_RCP_Phase","E_LCP_Phase","EIRP_dBW","PFD_Wm2","E_RMS_Vm"]
        PeakPct = 99.99                            % peak policy: P99.99 + 6 dB maximum excess
        PeakExcess = 6
        Full = [-250 100]                          % absolute dB span of every range control
        ARLim = [-30 30]
        GainMap = jet(256)
        ARMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256))
        Release = 'APAT v3 M8'
    end

    %% ───────────────────────────── lifecycle ─────────────────────────────
    methods (Access = public)
        function app = APAT_v3_M8_33
            app.createComponents(); registerApp(app, app.ui.Fig); runStartupFcn(app, @startup);
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true; app.stopStatusTimer();
            if ~isempty(app.opDialog) && isvalid(app.opDialog), delete(app.opDialog); end
            if isfield(app.ui, 'Fig') && isgraphics(app.ui.Fig), delete(app.ui.Fig); end
        end

        function report = runSelfTest(app)
            %RUNSELFTEST Deterministic numerical/policy checks; errors when any check fails.
            [P, Tt] = meshgrid(0:30:330, (0:30:180).'); T = table(Tt(:), P(:), 10*cosd(Tt(:)).^2, 'VariableNames', {'Theta','Phi','E_Total_dB'});
            w = solidWeights(T.Theta, T.Phi); pk = resolvePeak(T.E_Total_dB, app.PeakPct, app.PeakExcess);
            [P2, T2] = meshgrid(0:2:358, (0:2:180).'); f = @(t, p) 12*cosd(t).^2 - 0.5*sind(p).^2;
            R = resampleCanonical(table(T2(:), P2(:), f(T2(:), P2(:)), 'VariableNames', {'Theta','Phi','E_Total_dB'}), 1);
            native = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0 & R.Phi < 360; numErr = max(abs(R.E_Total_dB(native) - f(R.Theta(native), R.Phi(native))));
            spike = repmat(0.02, 1e5, 1); spike(1) = 10.02; sp = resolvePeak(spike, app.PeakPct, app.PeakExcess);
            cov = coverageCCDF([0 1 2 3], true(1, 4), [0.5 1 2.5], [1 1 1 1]);
            ffdFile = [tempname '.ffd']; writelines(["0 180 3"; "-180 180 3"; compose("%d 0 0 1", (1:9).')], ffdFile); c = onCleanup(@() delete(ffdFile)); %#ok<NASGU>
            ffd = readPattern(ffdFile, 'ffd');
            checks = struct( ...
                'SolidAngle', abs(sum(w) - 4*pi) < 1e-9, ...
                'Orientation', calcOrientation(T, T.E_Total_dB, pk, w, app.Axes) == 1, ...
                'Resampling', height(R) == 181*361 && all(isfinite(R.E_Total_dB)), ...
                'NumericalEquivalence', numErr < 1e-10, ...
                'PeakWindow', isequal(peakWindow([3.2; -100], app.PeakPct, app.PeakExcess), [-45 5]) && isequal(peakWindow(spike, app.PeakPct, app.PeakExcess), [-45 5]), ...
                'IsolatedSpike', sp.wasAdjusted && abs(sp.value - 0.02) < 1e-12 && sp.rawIndex == 1, ...
                'CoverageCCDF', max(abs(cov(:) - [75; 50; 25])) < 1e-12, ...
                'FFDReader', strcmp(ffd.meta.source, 'HFSS FFD') && isscalar(ffd.blocks) && height(ffd.blocks{1}) == 9, ...
                'ARTheme', all(arrayfun(@isAR, ["AR","AR_dB","AR dB","Axial Ratio","Axial_Ratio"])), ...
                'FormatNumber', strcmp(fmtNum(100), '100') && strcmp(fmtNum(3.14159), '3.14') && strcmp(fmtNum(NaN), 'n/a'));
            names = fieldnames(checks); ok = cellfun(@(n) checks.(n), names);
            report = checks; report.numericalError = numErr; report.pass = all(ok);
            if ~report.pass, error('apat:test:SelfTestFailed', 'Self-test failed: %s', strjoin(names(~ok), ', ')); end
        end
    end

    methods (Access = private)
        function startup(app)
            u = app.ui;
            app.paxCut = polaraxes(u.GridPolar); app.paxCut.Layout.Row = [1 4]; app.paxCut.Layout.Column = 3;
            app.paxPattern = polaraxes(u.GridCircular); app.paxPattern.Layout.Row = [1 3]; app.paxPattern.Layout.Column = 2;
            set([app.paxCut app.paxPattern], 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            axes3D = [u.Axes3dSph u.Axes3dPol u.Axes3dRect];
            for ax = [u.AxesCtr u.AxesRect axes3D]                     % one context menu per axes, created once (no leak)
                enableDefaultInteractivity(ax);
                if any(ax == axes3D), ax.Interactions = [rotateInteraction dataTipInteraction]; else, ax.Interactions = [zoomInteraction dataTipInteraction]; end
                ax.ContextMenu = uicontextmenu(u.Fig); uimenu(ax.ContextMenu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ~) delete(findall(ax, 'Type', 'datatip')));
            end
            app.defaults = cellfun(@(h) h.Value, app.paramControls(), 'UniformOutput', false);
            app.setCoverageUI();
        end

        function c = paramControls(app), u = app.ui; c = {u.Loss, u.RxPol, u.Rw, u.Pt, u.PtUnit, u.R, u.RUnit}; end

        function resetParams(app)
            cellfun(@(h, v) set(h, 'Value', v), app.paramControls(), app.defaults);
            if ~isempty(app.stdTbl), app.onProcess(); end
        end

        function setStatus(app, label, msg, temporary)
            % Permanent messages are remembered in UserData; temporary ones revert after 3 s (one timer per app).
            if app.isClosing || ~isgraphics(label), return; end
            app.stopStatusTimer(); label.Text = char(msg);
            if nargin < 4 || ~temporary, label.UserData = char(msg); return; end
            app.statusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, 'StopFcn', @(t, ~) delete(t), ...
                'TimerFcn', @(~, ~) app.restoreStatus(label));
            start(app.statusTimer);
        end

        function restoreStatus(app, label), if ~app.isClosing && isgraphics(label), label.Text = label.UserData; end, end

        function stopStatusTimer(app)
            t = app.statusTimer; app.statusTimer = [];
            if ~isempty(t) && isvalid(t), stop(t); end
        end

        function showError(app, ME, titleText)
            if app.isClosing, return; end
            where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.ui.Fig, [ME.message where], titleText, 'Icon', 'error');
        end

        function cleaner = busy(app, titleText, msg, cancelable)
            dlg = uiprogressdlg(app.ui.Fig, 'Title', titleText, 'Message', msg, 'Indeterminate', 'on', 'Cancelable', cancelable, 'CancelText', 'Abort');
            app.opDialog = dlg; drawnow; cleaner = onCleanup(@() app.endBusy(dlg));
        end

        function endBusy(app, dlg), if isvalid(dlg), close(dlg); end, if isequal(app.opDialog, dlg), app.opDialog = []; end, end

        function checkCancelled(app)
            if ~isempty(app.opDialog) && isvalid(app.opDialog) && app.opDialog.CancelRequested
                app.opDialog.Message = 'Aborting...'; drawnow limitrate; error('APAT:Cancelled', 'Operation cancelled by user.');
            end
        end

        function failOperation(app, ME, titleText)
            if strcmp(ME.identifier, 'APAT:Cancelled'), app.setStatus(app.ui.Status, 'Operation cancelled by user.', true); else, app.showError(ME, titleText); end
        end

        %% ───────────────────────────── pipeline ─────────────────────────────
        function onLoad(app)
            u = app.ui; fp = strtrim(u.Path.Value);
            if isempty(fp) || ~isfile(fp)
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern/Gain Files'; '*.*', 'All files'}, 'Select an antenna pattern file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            cleaner = app.busy('Loading Data', 'Reading file...', true); %#ok<NASGU>
            try
                out = app.readSource(fp, u.FormatLabel, u.Format); app.checkCancelled();
                if out.meta.isCoverage                                    % coverage-results tables route to the Coverage tab
                    u.Path.Value = app.filePath; [u.Tabs.SelectedTab, u.CovPath.Value] = deal(u.TabCov, fp);
                    app.covLoadResults(fp, out.raw); return
                end
                app.filePath = fp; [app.folderPath, app.baseName, ext] = fileparts(fp); app.fileName = [app.baseName ext];
                u.Path.Value = fp; app.src = out; app.showInput(out.raw);
                if out.meta.isDep
                    items = compose("Pattern %d: %.4g GHz", [(1:numel(out.blocks)).', out.freqs(:)/1e9]);
                    items(isnan(out.freqs(:))) = compose("Pattern %d", find(isnan(out.freqs(:))));
                    u.FFD.Items = items; u.FFD.Value = items(1);
                end
                set([u.FFD u.FFDLabel], 'Visible', out.meta.isDep, 'Enable', out.meta.isDep);
                app.autoCutBasis = true; u.Step.Value = u.Step.Items{1}; app.selectBlock(1); app.process(false);
            catch ME
                app.failOperation(ME, 'Loading Error');
            end
        end

        function out = readSource(app, fp, label, dropdown, raw)
            % Generic CSV/TXT/DAT files expose the text-format selector; all other formats are self-describing.
            if nargin < 5, raw = table(); end
            generic = isGenericText(fp); if generic && isempty(raw), dropdown.Value = 'gain'; end
            out = readPattern(fp, dropdown.Value, raw); app.checkCancelled();
            set([label dropdown], 'Visible', generic && ~out.meta.isCoverage);
        end

        function showInput(app, raw), set(app.ui.TableIn, 'Data', raw, 'ColumnName', raw.Properties.VariableNames, 'Visible', 'on'); end

        function selectBlock(app, k)
            block = app.src.blocks{k}; if app.src.meta.isDep, app.showInput(block); end
            app.stdTbl = normalizePattern(block); app.stdTbl.Properties.UserData = app.src.meta;
        end

        function T = buildPattern(app, out)
            % Auxiliary pattern (block 1) for the Coverage tab; never touches Main state.
            S = normalizePattern(out.blocks{1}); S.Properties.UserData = out.meta;
            T = calcPattern(S, app.getParam(), app.PeakPct, app.PeakExcess);
        end

        function onProcess(app)
            if isempty(app.stdTbl), uialert(app.ui.Fig, 'No file loaded — load a pattern first.', 'Warning', 'Icon', 'warning'); return; end
            cleaner = app.busy('Processing', 'Re-processing pattern...', false); %#ok<NASGU>
            try
                app.process(true); app.setStatus(app.ui.Status, sprintf('Re-processed <b>%s</b> with the current parameters ✅', app.fileName), true);
            catch ME
                app.failOperation(ME, 'Processing Error');
            end
        end

        function process(app, reinterpret)
            % Canonical source → every view.  REINTERPRET re-reads a generic text file with the selected format.
            u = app.ui;
            if reinterpret && isGenericText(app.filePath)
                out = readPattern(app.filePath, u.Format.Value, app.src.raw);
                assert(~out.meta.isCoverage, 'The selected format identifies a coverage-results file.');
                app.src = out; app.selectBlock(1);
            end
            [app.patTbl, info] = calcPattern(app.stdTbl, app.getParam(), app.PeakPct, app.PeakExcess); app.checkCancelled();
            [app.polLabel, app.polPairs] = deal(info.pol, info.pairs);
            if app.autoCutBasis && ~app.isGainOnly()
                if startsWith(info.pol, 'Linear'), u.CutBasis.Value = 'Linear'; else, u.CutBasis.Value = 'Circular'; end
            end
            [ts, ps] = deal(gridStep(app.patTbl.Theta), gridStep(app.patTbl.Phi)); if ~isfinite(ts), ts = 1; end, if ~isfinite(ps), ps = ts; end
            nonCanonical = abs(ts - 1) > 1e-9 || abs(ps - 1) > 1e-9; wantOne = strcmp(u.Step.Value, 'STEP: 1°');
            u.Step.Items = {sprintf('STEP: %g°', max(ts, ps)), 'STEP: 1°'}; u.Step.Value = u.Step.Items{1 + (wantOne && nonCanonical)};
            set(u.Step, 'Visible', nonCanonical, 'Enable', nonCanonical);
            app.applyStep(); app.checkCancelled();
            app.pickComponent(u.Component, app.viewTbl, u.Component.Value);
            app.updateView(true, false, false); app.checkCancelled();
            app.onPlaneChanged();                                          % E/H-plane cut on the detected boresight
            drawnow limitrate; app.renderFull();
            set([u.PanelCut u.ExportOut u.PanelFull u.PanelCtrl u.CoverageBtn], 'Visible', 'on');
            hasE = ~app.isGainOnly(); set([u.ExportUAN u.GridEcut], 'Visible', hasE); u.CutBasis.Enable = hasE;
            app.updateInputVisibility();
            pol = ''; if hasE && ~strcmpi(app.polLabel, 'n/a'), pol = sprintf(' | Polarization <b>%s</b>', app.polLabel); end
            app.setStatus(u.Status, sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>θ=%s°, φ=%s°</b>)%s', app.fileName, fmtNum(app.POB, 2), fmtNum(app.POBth), fmtNum(app.POBph), pol));
        end

        function p = getParam(app)
            u = app.ui;
            p = struct('GainLoss_dB', u.Loss.Value, 'RxMode', string(u.RxPol.Value), 'RxAR_dB', u.Rw.Value, 'R_m', max(u.R.Value, 1e-12));
            p.FieldScale = 10^(p.GainLoss_dB/20);
            switch u.PtUnit.Value, case 'dBm', p.Pt_dBW = u.Pt.Value - 30; case 'Watts', p.Pt_dBW = 10*log10(max(u.Pt.Value, eps)); otherwise, p.Pt_dBW = u.Pt.Value; end
            if strcmp(u.RUnit.Value, 'km'), p.R_m = 1000*p.R_m; end
        end

        function applyStep(app)
            % Resample the CANONICAL source (never the nonlinear outputs), then recompute the processed table.
            S = app.stdTbl; [ts, ps] = deal(gridStep(S.Theta), gridStep(S.Phi));
            if strcmp(app.ui.Step.Value, 'STEP: 1°') && (abs(ts - 1) > 1e-9 || abs(ps - 1) > 1e-9)
                S = resampleCanonical(S, 1); S.Properties.UserData = app.stdTbl.Properties.UserData;
                app.baseTbl = calcPattern(S, app.getParam(), app.PeakPct, app.PeakExcess);
            else
                app.baseTbl = app.patTbl;
            end
            app.applySpan();
        end

        function applySpan(app)
            % Materialize the φ display convention (θ stays physical) and cache grid topology, geometry and dΩ once.
            T = app.baseTbl;
            if app.signedPhi()
                T(abs(T.Phi - 360) <= 1e-9, :) = []; T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
                seam = T(abs(T.Phi - 180) < 1e-9, :); seam.Phi(:) = -180; T = sortrows([seam; T], {'Phi', 'Theta'});
            end
            app.viewTbl = T; app.viewStamp = app.viewStamp + 1;
            th = unique(T.Theta); ph = unique(T.Phi); [~, it] = ismember(T.Theta, th); [~, ip] = ismember(T.Phi, ph);
            [phG, thG] = meshgrid(ph, th); phR = deg2rad(phG); s = sind(thG);
            app.grid = struct('theta', th, 'phi', ph, 'sz', [numel(th) numel(ph)], 'idx', sub2ind([numel(th) numel(ph)], it, ip), ...
                'thG', thG, 'phG', phG, 'phR', phR, 'x', s.*cos(phR), 'y', s.*sin(phR), 'z', cosd(thG), 'dOmega', solidWeights(T.Theta, T.Phi));
        end

        function updateView(app, refreshRanges, renderFull, updateCut)
            % peak → boresight → metrics → tables/metadata → (cut) → (full patterns)
            comp = app.comp(); g = chooseGain(app.viewTbl, comp);
            app.peak = resolvePeak(g, app.PeakPct, app.PeakExcess);
            app.boresight = calcOrientation(app.viewTbl, g, app.peak, app.grid.dOmega, app.Axes);
            [app.POB, app.POBth, app.POBph] = deal(app.peak.value, app.viewTbl.Theta(app.peak.index), mod(app.viewTbl.Phi(app.peak.index), 360));
            app.metrics = calcMetrics(app.viewTbl, app.grid.dOmega, app.Axes, app.boresight, app.PeakPct, app.PeakExcess);
            if refreshRanges
                if ~isAR(comp) && ismember('E_Total_dB', app.viewTbl.Properties.VariableNames), app.gainLim = peakWindow(app.viewTbl.E_Total_dB, app.PeakPct, app.PeakExcess); end
                app.onRangeChanged(app.themeLimits(), 0, "all", false);
            end
            app.updateTables(); app.updateMetadata();
            if updateCut, app.updateCutControl(); app.plotCut(); end
            if renderFull, app.renderFull(); end
        end

        % ---- small state accessors -------------------------------------------------------------
        function tf = isGainOnly(app), tf = isfield(app.src, 'meta') && app.src.meta.isGainOnly; end
        function tf = signedPhi(app), tf = strcmp(app.ui.PhiSpan.Value, '-180° to 180°'); end
        function tf = elevation(app), tf = strcmp(app.ui.ThetaSpan.Value, '-90° to 90°'); end
        function th = dispTheta(app, th), if app.elevation(), th = 90 - th; end, end   % physical ↔ displayed θ (involution)
        function s = thetaName(app), if app.elevation(), s = "Elevation"; else, s = "Theta"; end, end
        function s = comp(app), s = app.ui.Component.Value; end
        function G = compGrid(app, col), G = nan(app.grid.sz); G(app.grid.idx) = app.viewTbl.(col); end

        function s = compLabel(app)
            d = app.ui.Component; i = find(strcmp(d.ItemsData, d.Value), 1);
            if isempty(i), s = string(d.Value); else, s = string(d.Items{i}); end
        end

        function [keys, names] = componentMap(app, T)
            % Canonical component keys/labels present in T; gain-only tables expose every data column verbatim.
            avail = string(T.Properties.VariableNames(3:end));
            if ~any(avail == "E_Total_dB"), [keys, names] = deal(avail); return; end
            present = ismember(app.CompKeys, avail); keys = app.CompKeys(present); names = app.CompNames(present);
        end

        function key = pickComponent(app, d, T, previous)
            % Populate a component dropdown, keeping PREVIOUS when still available (else Total Gain, else first).
            [keys, names] = app.componentMap(T);
            if any(keys == string(previous)), key = string(previous); elseif any(keys == "E_Total_dB"), key = "E_Total_dB"; else, key = keys(1); end
            d.Items = cellstr(names); d.ItemsData = cellstr(keys); d.Value = char(key);
        end

        % ---- event handlers (Main tab) ---------------------------------------------------------
        function onFormatChanged(app)
            if strcmp(strtrim(app.ui.Path.Value), app.filePath) && isGenericText(app.filePath), app.autoCutBasis = true; app.onProcess(); end
        end

        function onFFDChanged(app)
            u = app.ui; k = find(strcmp(u.FFD.Items, u.FFD.Value), 1); cleaner = app.busy('Processing', 'Switching FFD block...', false); %#ok<NASGU>
            try
                app.autoCutBasis = true; app.selectBlock(k); app.process(false);
                app.setStatus(u.Status, sprintf('Switched to FFD block %d (%s).', k, u.FFD.Value), true);
            catch ME
                app.failOperation(ME, 'Processing Error');
            end
        end

        function onStepChanged(app), app.applyStep(); app.pickComponent(app.ui.Component, app.viewTbl, app.comp()); app.updateView(true, true, true); end
        function onSpanChanged(app), if ~isempty(app.baseTbl), app.applySpan(); app.updateView(false, true, true); end, end
        function onComponentChanged(app), app.updateView(true, true, true); end

        %% ───────────────────────────── ranges & theme ─────────────────────────────
        function lim = themeLimits(app), if isAR(app.comp()), lim = app.ARLim; else, lim = app.gainLim; end, end

        function applyTheme(app, ax, lim)
            if isAR(app.comp()), map = app.ARMap; else, map = app.GainMap; end
            clim(ax, lim); colormap(ax, map); app.setTicks(colorbar(ax), lim);
        end

        function setTicks(app, target, lim)
            % Colorbar Ticks (or axes ZTick) from the "Colorbar step" spinner; skipped when it would produce > 60 ticks.
            step = app.ui.Cstep.Value; if ~(step > 0) || diff(lim) <= 0 || diff(lim)/step > 60, return; end
            ticks = unique([lim(1), ceil(lim(1)/step)*step:step:lim(2), lim(2)]);
            if isa(target, 'matlab.graphics.illustration.ColorBar'), target.Ticks = ticks; else, target.ZTick = ticks; end
        end

        function applyColorbarSpinners(app), app.onRangeChanged([app.ui.Cmin.Value app.ui.Cmax.Value], 0, "all", true); end

        function onRangeChanged(app, value, which, scope, applyNow)
            % WHICH: 0 = [min max] pair, 1 = min spinner, 2 = max spinner.  SCOPE: "full" | "cut" | "all".
            % Sliders travel over the requested window; single-spinner edits may only widen that travel.
            u = app.ui;
            if scope == "all"
                lim = clampRange(value, app.Full); [u.Cmin.Value, u.Cmax.Value] = deal(lim(1), lim(2));
                app.onRangeChanged(lim, 0, "full", applyNow); app.onRangeChanged(lim, 0, "cut", applyNow); return
            end
            if scope == "full", sliders = u.FullSliders; mins = u.FullMins; maxs = u.FullMaxs; lim = app.fullLim;
            else,               sliders = u.CutSlider;  mins = u.CutMin;   maxs = u.CutMax;   lim = app.cutLim; end
            if which == 0, lim = value; else, lim(which) = value; end
            lim = clampRange(lim, app.Full); travel = lim;
            if which ~= 0, travel = [min(sliders(1).Limits(1), lim(1)), max(sliders(1).Limits(2), lim(2))]; end
            setRange(sliders, lim, travel); setRange(mins, lim(1), [app.Full(1), lim(2) - 1]); setRange(maxs, lim(2), [lim(1) + 1, app.Full(2)]);
            if scope == "full", app.fullLim = lim; if ~isAR(app.comp()), app.gainLim = lim; end, else, app.cutLim = lim; end
            if ~applyNow || isempty(app.viewTbl), return; end
            if scope == "full", app.applyFullRange(); else, set(app.paxCut, 'RLim', lim, 'RTick', lim(1):5:lim(2)); u.AxesRect.YLim = lim; end
            drawnow limitrate
        end

        function applyFullRange(app)
            u = app.ui; lim = app.fullLim;
            for c = {u.AxesCtr, app.paxPattern, u.Axes3dSph, u.Axes3dPol, u.Axes3dRect}
                clim(c{1}, lim); cb = findall(u.Fig, 'Type', 'ColorBar', 'Axes', c{1}); if ~isempty(cb), app.setTicks(cb(1), lim); end
            end
            zlim(u.Axes3dRect, lim); app.setTicks(u.Axes3dRect, lim);
        end

        %% ───────────────────────────── full-pattern renderers ─────────────────────────────
        function renderFull(app)
            if isempty(app.viewTbl), return; end
            app.drawContour(); app.checkCancelled(); app.drawFisheye(); app.checkCancelled();
            app.draw3D(app.ui.Axes3dSph, "sphere"); app.checkCancelled(); app.draw3D(app.ui.Axes3dPol, "polar"); app.checkCancelled();
            app.drawRect3(); drawnow limitrate; app.annotatePOB();
        end

        function rows = tipRows(app, th, ph, val)
            rows = [dataTipTextRow(app.thetaName(), app.dispTheta(th), '%.3g°'); dataTipTextRow("Phi", ph, '%.3g°'); dataTipTextRow(replace(app.compLabel(), "_", "\_"), val, '%.3g dB')];
        end

        function rows = pobRows(app, G), k = app.grid.idx(app.peak.index); rows = app.tipRows(app.grid.thG(k), app.grid.phG(k), G(k)); end

        function formatAngularAxes(app, ax, phiStep, thetaStep)
            if app.signedPhi(), xl = [-180 180]; else, xl = [0 360]; end
            if app.elevation(), yl = [-90 90]; ydir = 'normal'; else, yl = [0 180]; ydir = 'reverse'; end
            set(ax, 'XLim', xl, 'YLim', yl, 'YDir', ydir, 'Box', 'on', 'Layer', 'top', 'XTick', xl(1):phiStep:xl(2), 'YTick', yl(1):thetaStep:yl(2));
        end

        function setPolarTicks(app, pax)
            a = 0:30:330; if app.signedPhi(), a(a > 180) = a(a > 180) - 360; end
            set(pax, 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', a), 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
        end

        function setContextMenu(~, ax), set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', ax.ContextMenu); end

        function drawContour(app)
            ax = app.ui.AxesCtr; g = app.grid; G = app.compGrid(app.comp()); Y = app.dispTheta(g.thG); cla(ax);
            s = pcolor(ax, g.phi, app.dispTheta(g.theta), G, 'FaceColor', 'interp', 'LineStyle', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax, app.fullLim); app.formatAngularAxes(ax, 30, 15); daspect(ax, [1 1 1]);
            xlabel(ax, 'Phi (degree)'); ylabel(ax, app.thetaName() + " (degree)"); title(ax, app.compLabel(), 'Interpreter', 'none');
            setTip(s, app.tipRows(g.thG, g.phG, G)); app.markPOB(ax, g.idx(app.peak.index), g.phG, Y, zeros(g.sz), app.pobRows(G)); app.setContextMenu(ax);
        end

        function drawFisheye(app)
            pax = app.paxPattern; g = app.grid; G = app.compGrid(app.comp()); cla(pax);
            s = surface(pax, g.phR, g.thG, zeros(g.sz), G, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(pax, app.fullLim); app.setPolarTicks(pax);
            set(pax, 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', app.dispTheta(0:30:180)));
            title(pax, sprintf('%s  |  r=θ, angle=φ', app.compLabel()), 'Interpreter', 'none', 'FontSize', 9);
            setTip(s, app.tipRows(g.thG, g.phG, G)); app.markPOB(pax, g.idx(app.peak.index), g.phR, g.thG, [], app.pobRows(G));
        end

        function draw3D(app, ax, kind)
            % kind "sphere": unit sphere colored by the component.  kind "polar": radius = (value − min) / (peak − min).
            g = app.grid; G = app.compGrid(app.comp()); lim = app.fullLim; r = 1;
            if kind == "polar", r = max(G - lim(1), 0) / max(max(G, [], 'all') - lim(1), eps); end
            [X, Y, Z] = deal(r.*g.x, r.*g.y, r.*g.z); cla(ax); hold(ax, 'on');
            s = surf(ax, X, Y, Z, G, 'EdgeColor', 'none', 'Tag', 'APAT_Surface'); app.applyTheme(ax, lim);
            set(ax, 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1], 'Projection', 'orthographic'); axis(ax, 'off');
            app.drawXYZ(ax); app.applyView(ax, [135 25]); app.overlayCut(ax, kind);
            title(ax, sprintf('%s  |  θ: %s  |  φ: %s', app.compLabel(), app.ui.ThetaSpan.Value, app.ui.PhiSpan.Value), 'Interpreter', 'none');
            setTip(s, app.tipRows(g.thG, g.phG, G)); app.markPOB(ax, g.idx(app.peak.index), X, Y, Z, app.pobRows(G)); hold(ax, 'off'); app.setContextMenu(ax);
        end

        function drawRect3(app)
            ax = app.ui.Axes3dRect; g = app.grid; G = app.compGrid(app.comp()); lim = app.fullLim; Y = app.dispTheta(g.thG); cla(ax);
            s = surf(ax, g.phG, Y, G, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax, lim); zlim(ax, lim); app.setTicks(ax, lim); app.formatAngularAxes(ax, 60, 30); grid(ax, 'on');
            xlabel(ax, 'Phi (degree)'); ylabel(ax, app.thetaName() + " (degree)"); zlabel(ax, app.compLabel() + " (dB)", 'Interpreter', 'none');
            app.applyView(ax, [-35 35]); title(ax, app.compLabel(), 'Interpreter', 'none');
            setTip(s, app.tipRows(g.thG, g.phG, G)); app.markPOB(ax, g.idx(app.peak.index), g.phG, Y, G, app.pobRows(G)); app.setContextMenu(ax);
        end

        function drawXYZ(~, ax)
            colors = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'}; D = 1.35*eye(3);
            for k = 1:3
                quiver3(ax, 0, 0, 0, D(k, 1), D(k, 2), D(k, 3), 0, 'Color', colors{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12*D(k, 1), 1.12*D(k, 2), 1.12*D(k, 3), labels{k}, 'Color', colors{k}, 'FontWeight', 'bold');
            end
        end

        function applyView(app, ax, default)
            v = struct('iso', [default 0 0 1], 'top', [0 90 0 1 0], 'bottom', [0 -90 0 1 0], 'right', [90 0 0 0 1], 'left', [-90 0 0 0 1], 'front', [0 0 0 0 1], 'back', [180 0 0 0 1]);
            v = v.(app.ui.View3D.Value); view(ax, v(1), v(2)); camup(ax, v(3:5));
        end

        function on3DViewChanged(app)
            if isempty(app.viewTbl), return; end
            app.applyView(app.ui.Axes3dSph, [135 25]); app.applyView(app.ui.Axes3dPol, [135 25]); app.applyView(app.ui.Axes3dRect, [-35 35]); drawnow limitrate
        end

        function overlayCut(app, ax, kind)
            % Draw the active cut on a 3-D pattern (same radius law as draw3D so the curve lies on the surface).
            delete(findall(ax, 'Tag', 'APAT_CutOverlay')); if ~app.ui.Overlay.Value, return; end
            c = app.cutData(); v = c.data(:, 1); r = 1.02;
            if kind == "polar", lim = app.fullLim; r = 1.01*max(v - lim(1), 0) / max(max(app.viewTbl.(app.comp())) - lim(1), eps); end
            held = ishold(ax); hold(ax, 'on');
            plot3(ax, r.*sind(c.theta).*cosd(c.phi), r.*sind(c.theta).*sind(c.phi), r.*cosd(c.theta), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay', 'HandleVisibility', 'off');
            if ~held, hold(ax, 'off'); end
        end

        function updateOverlays(app), if ~isempty(app.viewTbl), app.overlayCut(app.ui.Axes3dSph, "sphere"); app.overlayCut(app.ui.Axes3dPol, "polar"); end, end

        %% ───────────────────────────── tag-managed annotations ─────────────────────────────
        function markPOB(app, ax, k, X, Y, Z, rows)
            % One tagged peak marker at grid/line index K.  Visibility follows the POB checkbox; the DataTip is attached by annotatePOB.
            if ~isfinite(app.peak.value) || ~isfinite(k), return; end
            held = ishold(ax); hold(ax, 'on');
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), m = polarplot(ax, X(k), Y(k), 'ko'); else, m = plot3(ax, X(k), Y(k), Z(k), 'ko', 'Clipping', 'off'); end
            set(m, 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'Tag', 'APAT_POB', 'HandleVisibility', 'off', 'Visible', app.ui.POB.Value); setTip(m, rows);
            if ~held, hold(ax, 'off'); end
        end

        function annotatePOB(app)
            % Attach a DataTip to every POB marker that has none (called after graphics are materialized).
            for m = findall(app.ui.Fig, 'Tag', 'APAT_POB', 'Type', 'line').'
                if ~isempty(findall(m, 'Type', 'datatip')), continue; end
                try, t = datatip(m, 'DataIndex', 1, 'FontSize', 9); set(t, 'Tag', 'APAT_POB', 'HandleVisibility', 'off', 'Visible', m.Visible); catch, end
            end
        end

        function onPOBToggled(app)
            set(findall(app.ui.Fig, 'Tag', 'APAT_POB'), 'Visible', app.ui.POB.Value);
            if app.ui.POB.Value, drawnow limitrate; app.annotatePOB(); end
        end

        function markHPBW(~, ax, x, y, rows)
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), m = polarplot(ax, x, y, 'o'); else, m = plot(ax, x, y, 'o'); end
            set(m, 'Color', '#D95319', 'MarkerFaceColor', '#D95319', 'Tag', 'APAT_HPBW', 'HandleVisibility', 'off', 'Visible', 'off'); setTip(m, rows);
        end

        function refreshHPBW(app)
            on = app.ui.HPBWBounds.Value;
            for m = findall(app.ui.Fig, 'Tag', 'APAT_HPBW', 'Type', 'line').'
                m.Visible = on; t = findall(m, 'Type', 'datatip');
                if on && isempty(t), try, t = datatip(m, 'DataIndex', 1, 'FontSize', 9); t.Tag = 'APAT_HPBW'; catch, t = []; end, end
                if ~isempty(t), set(t, 'Visible', on); end
            end
        end

        %% ───────────────────────────── cuts ─────────────────────────────
        function [cols, idx] = cutCols(app)
            % Total plus the co/cross pair of the selected basis; IDX keeps the color mapping stable.
            u = app.ui; if app.isGainOnly(), cols = string(app.comp()); idx = 1; return; end
            if strcmp(u.CutBasis.Value, 'Linear'), cols = ["E_Total_dB","E_TH_dB","E_PH_dB"]; pair = {'E_TH','E_PH'};
            else,                                 cols = ["E_Total_dB","E_RCP_dB","E_LCP_dB"]; pair = {'E_RCP','E_LCP'}; end
            [u.Er.Text, u.El.Text] = pair{:}; sel = [u.Et.Value, u.Er.Value, u.El.Value]; if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = cols(idx);
        end

        function updateCutControl(app, requested)
            % Cut value = fixed θ (displayed convention) for φ-cuts, fixed φ for θ-cuts; snapped onto sampled planes.
            u = app.ui; T = app.viewTbl; if nargin < 2, requested = u.CutValue.Value; end
            if strcmp(u.CutType.Value, 'Phi'), vals = sort(app.dispTheta(unique(T.Theta))); else, vals = unique(mod(T.Phi, 360)); end
            [~, k] = min(abs(vals - requested)); lim = [vals(1) vals(end)]; if diff(lim) <= 0, lim = lim + [-1 1]; end
            setRange(u.CutValue, vals(k), lim); if numel(vals) > 1, u.CutValue.Step = min(diff(vals)); end
        end

        function onPlaneChanged(app)
            % E-plane: θ-cut through the boresight φ.  H-plane: φ-cut at θ=90° for transverse axes, θ-cut at φ=90° for ±Z.
            u = app.ui; ax = app.Axes; k = app.boresight;
            if startsWith(u.Plane.Value, 'E'), type = 'Theta'; value = ax.phi(k);
            elseif ax.theta(k) == 90,           type = 'Phi';   value = app.dispTheta(90);
            else,                               type = 'Theta'; value = 90; end
            u.CutType.Value = type; app.updateCutControl(value); app.onCutChanged();
        end

        function onCutChanged(app, source)
            u = app.ui;
            if nargin > 1 && isequal(source, u.CutType), app.updateCutControl(); end
            if nargin > 1 && isequal(source, u.CutBasis), app.autoCutBasis = false; app.updateMetadata(); end
            u.HPBWBounds.Visible = u.HPBW.Value; if ~u.HPBW.Value, u.HPBWBounds.Value = false; end
            if ~isempty(app.viewTbl), app.plotCut(); app.updateOverlays(); end
        end

        function c = cutData(app)
            % The active cut as one closed circle (0..360° or −180..180°) with the physical direction of every sample.
            T = app.viewTbl; [cols, idx] = app.cutCols(); type = string(app.ui.CutType.Value);
            req = app.ui.CutValue.Value; if type == "Phi", req = app.dispTheta(req); end
            [ang, rows, fixed, sym, snapped] = cutGeometry(T, type, req);
            if snapped, app.setStatus(app.ui.Status, sprintf('Requested %s cut @ %s=%g° (snapped to nearest %s=%g°)', type, sym, req, sym, fixed), false); end
            data = T{rows, cols}; th = T.Theta(rows); ph = T.Phi(rows);
            if app.signedPhi(), ang(ang > 180) = ang(ang > 180) - 360; end
            [ang, o] = unique(ang); data = data(o, :); th = th(o); ph = ph(o);
            if type == "Phi"                                              % close the φ circle at the seam (periodic)
                lo = -180*app.signedPhi(); hi = lo + 360;
                if ang(1) > lo, ang = [lo; ang]; data = [data(end, :); data]; th = [th(end); th]; ph = [lo; ph]; end
                if ang(end) < hi, ang = [ang; hi]; data = [data; data(1, :)]; th = [th; th(1)]; ph = [ph; hi]; end
                fixed = app.dispTheta(fixed);
            end
            if app.isGainOnly(), ttl = char(app.comp()); else, ttl = sprintf('%s cut @ %s = %g°', type, sym, fixed); end
            c = struct('angle', ang, 'data', data, 'cols', cols, 'idx', idx, 'names', replace(cols, "_", "\_"), 'title', ttl, 'theta', th, 'phi', ph, 'type', type);
        end

        function plotCut(app)
            u = app.ui; c = app.cutData(); pax = app.paxCut; rax = u.AxesRect; lim = app.cutLim;
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on');
            pl = polarplot(pax, deg2rad(c.angle), max(c.data, lim(1)), 'LineWidth', 1.4);   % clamp: no reflection spikes below the inner RLim
            rl = plot(rax, c.angle, c.data, 'LineWidth', 1.4); colors = rax.ColorOrder(1 + mod(c.idx - 1, size(rax.ColorOrder, 1)), :);
            for k = 1:numel(pl)
                rows = [dataTipTextRow("Angle", c.angle, '%.3g°'); dataTipTextRow("Magnitude", c.data(:, k), '%.3g dB')];
                set([pl(k) rl(k)], 'Color', colors(k, :)); setTip(pl(k), rows); setTip(rl(k), rows);
            end
            set(pax, 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.setPolarTicks(pax);
            xl = [-180*app.signedPhi(), 360 - 180*app.signedPhi()];
            set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, sprintf('%s (degree)', c.type)); title(pax, c.title, 'Interpreter', 'none'); title(rax, c.title, 'Interpreter', 'none');
            [pk, ki] = max(c.data(:, 1)); u.HPBWLabel.Text = '';
            if isfinite(pk)
                rows = [dataTipTextRow("Angle", c.angle(ki), '%.3g°'); dataTipTextRow("Magnitude", pk, '%.3g dB')];
                app.markPOB(pax, ki, deg2rad(c.angle), max(c.data(:, 1), lim(1)), [], rows); app.markPOB(rax, ki, c.angle, c.data(:, 1), zeros(size(c.angle)), rows);
                if u.HPBW.Value
                    [bw, lo, hi] = calcHPBW(c.angle, c.data(:, 1), pk, c.angle(ki));
                    if isfinite(bw)
                        b = mod([lo hi] - xl(1), 360) + xl(1); u.HPBWLabel.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                        if b(1) <= b(2), reg = b; else, reg = [xl(1) b(2); b(1) xl(2)]; end
                        thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                        xregion(rax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                        names = ["Lower HPBW", "Upper HPBW"];
                        for k = 1:2
                            rows = [dataTipTextRow(names(k), b(k), '%.2f°'); dataTipTextRow("Gain", pk - 3, '%.2f dB')];
                            app.markHPBW(pax, deg2rad(b(k)), pk - 3, rows); app.markHPBW(rax, b(k), pk - 3, rows);
                        end
                    end
                end
            end
            legend(pax, pl, c.names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rl, c.names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off'); drawnow limitrate; app.annotatePOB(); app.refreshHPBW();
        end

        %% ───────────────────────────── tables, metadata, export ─────────────────────────────
        function updateTables(app)
            d = app.ui.Filter; cols = app.viewTbl.Properties.VariableNames(3:end);
            if ~isequal(regexprep(d.Items(2:end), '^✓ ?', ''), cols)         % schema changed → rebuild the column filter
                d.Items = [{'--- column filter ---'}, cols]; d.ItemsData = 0:numel(cols); d.UserData = ~ismember(cols, app.HiddenCols); d.Value = 0;
                set([d, app.ui.TableOut, app.ui.TabsData], 'Visible', 'on');
            end
            app.filterOutput();
        end

        function filterOutput(app)
            % Dropdown doubles as a multi-select column filter: selecting an item toggles it; UserData holds the mask.
            d = app.ui.Filter; if d.Value > 0, d.UserData(d.Value) = ~d.UserData(d.Value); d.Value = 0; end
            if isempty(app.filterStyles), app.filterStyles = {uistyle('FontWeight', 'bold', 'FontColor', 'black', 'BackgroundColor', [0.8 1 0.8]), uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9])}; end
            d.Items = regexprep(d.Items, '^✓ ?', ''); removeStyle(d); on = find(d.UserData) + 1; d.Items(on) = append('✓ ', d.Items(on));
            if ~isempty(on), addStyle(d, app.filterStyles{1}, 'Item', on); end, addStyle(d, app.filterStyles{2}, 'Item', find([true, ~d.UserData]));
            app.ui.TableOut.Data = app.viewTbl(:, [true true d.UserData]); app.updateInputVisibility();
        end

        function updateInputVisibility(app)
            % Parameter controls appear only when a visible output column depends on them.
            u = app.ui; cols = app.viewTbl.Properties.VariableNames(3:end); shown = string(cols(u.Filter.UserData));
            set([u.RxPolLabel u.RxPol u.RwLabel u.Rw], 'Visible', any(ismember(shown, ["PLF_dB","Gain_PolCorrected_dB"])));
            set([u.PtLabel u.Pt u.PtUnit], 'Visible', any(ismember(shown, ["EIRP_dBW","PFD_Wm2","E_RMS_Vm"])));
            set([u.RLabel u.R u.RUnit], 'Visible', any(ismember(shown, ["PFD_Wm2","E_RMS_Vm"])));
            set([u.LossLabel u.Loss], 'Visible', app.isGainOnly() || any(ismember(shown, [setdiff(app.CompKeys, "AR_dB"), "EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"])));
        end

        function updateMetadata(app)
            T = app.viewTbl; m = app.metrics; g = app.grid;
            rows = {'Source format', app.src.meta.source; 'File', app.fileName; 'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(T), numel(g.theta), numel(g.phi)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(min(g.theta)), fmtNum(max(g.theta)), fmtNum(gridStep(g.theta))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(min(g.phi)), fmtNum(max(g.phi)), fmtNum(gridStep(g.phi)))};
            f = app.src.freqs(isfinite(app.src.freqs)); if ~isempty(f), rows(end+1, :) = {'Frequencies', char(strjoin(compose('%.4g GHz', f(:)/1e9), ', '))}; end
            if ~app.isGainOnly()
                if ~strcmpi(app.polLabel, 'n/a'), rows(end+1, :) = {'Polarization', app.polLabel}; end
                rows(end+1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(app.polPairs.(app.ui.CutBasis.Value), ' / '))};
            end
            rows = [rows; {'Peak gain (POB)', sprintf('%s dB', fmtNum(m.PeakGain_dB)); 'POB direction [θ, φ]', sprintf('[%s°, %s°]', fmtNum(m.PeakTheta_deg), fmtNum(m.PeakPhi_deg)); ...
                'Boresight axis', app.Axes.labels{app.boresight}; 'Peak policy', sprintf('P%.4g, max excess %.4g dB', app.PeakPct, app.PeakExcess); 'Peak adjusted', char(string(app.peak.wasAdjusted)); ...
                'HPBW E-plane', sprintf('%s°', fmtNum(m.HPBW_EPlane_deg)); 'HPBW H-plane', sprintf('%s°', fmtNum(m.HPBW_HPlane_deg)); 'Front-to-back', sprintf('%s dB', fmtNum(m.FrontBack_dB)); ...
                'Peak directivity', sprintf('%s dB', fmtNum(m.PeakDirectivity_dB)); 'Radiation efficiency', sprintf('%s %%', fmtNum(m.Efficiency_pct)); 'AR at peak', sprintf('%s dB', fmtNum(m.AxialRatioAtPeak_dB))}];
            app.ui.TableMeta.Data = rows;
        end

        function saveTable(app, T, name, what, status)
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, ['Export ' what], fullfile(app.folderPath, name));
            if isequal(f, 0), return; end
            try, fp = fullfile(p, f); writeTable(T, fp); app.setStatus(status, sprintf('%s exported to <b>%s</b>', what, fp), true); catch ME, app.showError(ME, 'Export Error'); end
        end

        function exportResults(app), if ~isempty(app.viewTbl), app.saveTable(app.ui.TableOut.Data, [app.baseName '_APAT_results.csv'], 'Results', app.ui.Status); end, end

        function exportCut(app)
            if isempty(app.viewTbl), return; end
            c = app.cutData(); app.saveTable(array2table([c.angle c.data], 'VariableNames', [{'Angle_deg'}, cellstr(c.cols)]), [app.baseName '_cut.csv'], ['Cut (' c.title ')'], app.ui.Status);
        end

        function exportUAN(app)
            if app.isGainOnly(), uialert(app.ui.Fig, 'No E-field data to export.', 'Export UAN'); return; end
            T = sortrows(app.viewTbl, {'Phi', 'Theta'});
            U = table(T.Theta, T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), 'VariableNames', {'Theta','Phi','E_TH_DB','E_PH_DB','E_TH_DG','E_PH_DG'});
            step = gridStep(U.Theta); if ~isfinite(step), step = 1; end, peak = max([U.E_TH_DB; U.E_PH_DB]);
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, ...
                'Export UAN / E-field data', fullfile(app.folderPath, sprintf('%s_%.5f_%gdeg.uan', app.baseName, peak, step)));
            if isequal(f, 0), return; end
            cleaner = app.busy('Saving Data', 'Writing file...', false); %#ok<NASGU>
            try
                fp = fullfile(p, f); if endsWith(fp, '.uan', 'IgnoreCase', true), writeUAN(U, fp); else, writeTable(U, fp); end
                app.setStatus(app.ui.Status, ['UAN exported to <b>' fp '</b>'], true);
            catch ME
                app.showError(ME, 'Export UAN Error');
            end
        end

        %% ───────────────────────────── coverage ─────────────────────────────
        % The CheckBoxTree is the single registry: pattern/results nodes own their jobs, every job owns its plotted line.
        function nodes = covNodes(app, kind, roots)
            if nargin < 3, roots = app.ui.CovRoot; end
            objs = findobj(roots); nodes = objs(arrayfun(@(n) nodeIs(n, kind), objs));
            if strcmp(kind, 'job') && numel(nodes) > 1, D = [nodes.NodeData]; [~, o] = sort([D.id]); nodes = nodes(o); end
        end

        function node = covTarget(app)
            % Pattern node to operate on: the selection (or its pattern ancestor), else the most recently added pattern.
            node = []; n = app.ui.CovTree.SelectedNodes;
            while ~isempty(n) && isa(n(1), 'matlab.ui.container.TreeNode')
                if nodeIs(n(1), 'pattern'), node = n(1); return; end
                n = n(1).Parent;
            end
            pats = app.covNodes('pattern'); if ~isempty(pats), node = pats(end); end
        end

        function node = covFindByPath(app, fp)
            node = [];
            for n = app.ui.CovRoot.Children.'
                if isstruct(n.NodeData) && isfield(n.NodeData, 'path') && strcmp(n.NodeData.path, fp), node = n; return; end
            end
        end

        function thr = covThresholds(app)
            % Thresholds exactly as entered (the automatic window is only a preset).
            u = app.ui; lo = u.ThrMin.Value; hi = u.ThrMax.Value; step = max(u.ThrStep.Value, 0.1);
            if hi <= lo, hi = min(100, lo + step); u.ThrMax.Value = hi; end
            thr = (lo:step:hi).'; if thr(end) < hi, thr(end+1) = hi; end
        end

        function setCoverageUI(app)
            u = app.ui; hasPattern = ~isempty(app.covNodes('pattern')); hasJobs = ~isempty(app.covNodes('job')); anyNode = hasPattern || hasJobs;
            set(u.CovPanelGrid.Children, 'Visible', hasPattern, 'Enable', hasPattern);
            set([u.CovPathLabel u.CovPath u.CovLoad u.CovCompute], 'Visible', 'on', 'Enable', 'on'); u.CovCompute.Enable = hasPattern;
            set([u.QueryCtrls u.CovReset u.CovExport u.CovClear u.CovToMain], 'Visible', anyNode, 'Enable', anyNode);
            set([u.CovExport u.CovClear u.QueryCtrls], 'Enable', hasJobs);
            set([u.CovFormatLabel u.CovFormat], 'Visible', hasPattern && isGenericText(u.CovPath.Value), 'Enable', 'on');
            app.onCovType();
        end

        function onCovType(app)
            u = app.ui; on = u.Conical.Value && ~isempty(app.covNodes('pattern')); set(u.ConeCtrls, 'Visible', on, 'Enable', on);
            if on, app.covOrientationStatus(); else, u.CovStatus.Text = regexprep(char(u.CovStatus.Text), '\s*\|\s*Orientation <b>.*?</b>', ''); end
        end

        function k = covOrientationIndex(app)
            % Auto (0) resolves to the detected boresight of the target pattern; explicit selections are authoritative.
            k = app.ui.CovOrientation.Value; if k ~= 0, return; end
            node = app.covTarget(); k = NaN; if ~isempty(node) && isfield(node.NodeData, 'boresight'), k = node.NodeData.boresight; end
        end

        function covOrientationStatus(app)
            k = app.covOrientationIndex(); if ~app.ui.Conical.Value || ~isfinite(k), return; end
            base = regexprep(char(app.ui.CovStatus.Text), '\s*\|\s*Orientation <b>.*?</b>', '');
            app.setStatus(app.ui.CovStatus, sprintf('%s | Orientation <b>%s</b>', base, app.Axes.labels{k}), false);
        end

        function onCovOrientation(app)
            k = app.covOrientationIndex(); if ~isfinite(k), return; end
            [app.ui.ConeTh.Value, app.ui.ConePh.Value] = deal(app.Axes.theta(k), app.Axes.phi(k)); app.covOrientationStatus();
        end

        function covSyncPattern(app, node)
            % Align the Coverage controls with NODE: component list, detected boresight and the threshold preset.
            d = node.NodeData; u = app.ui; T = d.pattern;
            if isempty(d.component), prev = u.CovComponent.Value; else, prev = d.component; end
            comp = char(app.pickComponent(u.CovComponent, T, prev));
            if ~strcmp(d.component, comp)
                d.component = comp; g = chooseGain(T, comp);
                d.boresight = calcOrientation(T, g, resolvePeak(g, app.PeakPct, app.PeakExcess), d.dOmega, app.Axes); node.NodeData = d;
                if u.CovOrientation.Value == 0, app.onCovOrientation(); end
            end
            key = sprintf('%s|%s|%g', d.path, comp, d.stamp);          % preset only when pattern/component/view actually changed
            if ~strcmp(app.covPresetKey, key)
                app.covPresetKey = key; w = peakWindow(T.(comp), app.PeakPct, app.PeakExcess);
                if app.covThrInit, w = [min(u.ThrMin.Value, w(1)), max(u.ThrMax.Value, w(2))]; end
                setRange(u.ThrMin, w(1), [app.Full(1), w(2) - 0.1]); setRange(u.ThrMax, w(2), [w(1) + 0.1, app.Full(2)]); app.covThrInit = true;
            end
        end

        function covSyncFromView(app, node)
            % Main-tab patterns always feed Coverage from the CURRENT view table (loss, step, span already applied).
            d = node.NodeData; [d.pattern, d.dOmega, d.stamp, d.name, d.component] = deal(app.viewTbl, app.grid.dOmega, app.viewStamp, app.baseName, '');
            node.NodeData = d; app.covSyncPattern(node);
        end

        function node = covAddPattern(app, name, T, fp, raw)
            node = uitreenode(app.ui.CovRoot, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', 'pattern', 'pattern', T, 'dOmega', solidWeights(T.Theta, T.Phi), 'name', name, 'path', fp, 'raw', raw, 'stamp', app.viewStamp, 'component', '');
            expand(app.ui.CovTree); app.ui.CovTree.CheckedNodes = [app.ui.CovTree.CheckedNodes; node]; app.ui.CovTree.SelectedNodes = node;
            app.covSyncPattern(node); app.setCoverageUI(); app.ui.CovResults.Visible = 'on';
            app.setStatus(app.ui.CovStatus, sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name), false);
        end

        function job = covAddJob(app, parent, thr, cov, tag, comp, label, tableTag, conical, orient)
            app.covRunID = app.covRunID + 1; icon = '📉'; if strcmp(tag, 'Res'), icon = '📈'; end
            name = sprintf('%s R%d %s · %s', icon, app.covRunID, label, comp);
            ln = plot(app.ui.CovAxes, thr, cov, 'LineWidth', 1.6, 'DisplayName', name);
            job = uitreenode(parent, 'Text', name);
            job.NodeData = struct('kind', 'job', 'id', app.covRunID, 'tag', tag, 'thr', thr(:), 'cov', cov(:), 'line', ln, 'label', name, 'tableTag', tableTag, 'conical', conical, 'orientation', orient);
            app.ui.CovTree.CheckedNodes = [app.ui.CovTree.CheckedNodes; job];
        end

        function finalizeJobs(app)
            jobs = app.covNodes('job'); expand(app.ui.CovRoot); if ~isempty(jobs), expand(unique([jobs.Parent])); end
            checked = jobs(ismember(jobs, app.ui.CovTree.CheckedNodes)); app.covRebuildTable(checked); app.covLegend(checked); app.setCoverageUI();
        end

        function covRebuildTable(app, jobs)
            thr = app.covThresholds(); names = {'Threshold (dB)'}; n = numel(jobs);
            if n > 0, D = [jobs.NodeData]; thr = unique(vertcat(D.thr)); end
            V = nan(numel(thr), n + 1); V(:, 1) = thr;
            for k = 1:n
                if numel(D(k).thr) > 1, V(:, k+1) = interp1(D(k).thr, D(k).cov, thr, 'linear', NaN); end
                names{k+1} = sprintf('R%d %s %%', D(k).id, D(k).tableTag);
            end
            app.ui.CovTable.Data = array2table(compose('%.2f', V), 'VariableNames', names);
        end

        function covLegend(app, jobs)
            if isempty(jobs), legend(app.ui.CovAxes, 'off'); return; end
            D = [jobs.NodeData]; legend(app.ui.CovAxes, [D.line], string({D.label}), 'Location', 'southwest', 'Interpreter', 'none');
        end

        function covLoadResults(app, fp, R)
            [~, name] = fileparts(fp); node = uitreenode(app.ui.CovRoot, 'Text', ['📄 ' name]); node.NodeData = struct('kind', 'results', 'name', name, 'path', fp);
            thr = R{:, 1}; app.setCovXRange([min(thr) max(thr)], gridStep(thr));
            for k = 2:width(R), app.covAddJob(node, thr, R{:, k}, 'Res', R.Properties.VariableNames{k}, 'Res', 'Res', false, "n/a"); end
            app.ui.CovTree.CheckedNodes = [app.ui.CovTree.CheckedNodes; node]; app.finalizeJobs(); app.ui.CovResults.Visible = 'on';
            app.setStatus(app.ui.CovStatus, sprintf('Coverage results file "%s" loaded (%d curves).', name, width(R) - 1), false);
        end

        function setCovXRange(app, b, step)
            % Plot X-window: the first result establishes it, later results may only widen it.
            u = app.ui; b = clampRange(b, app.Full); if app.covXInit, b = [min(u.CovAxes.XLim(1), b(1)), max(u.CovAxes.XLim(2), b(2))]; end
            app.covXInit = true; app.covApplyX(b);
            if nargin > 2 && isfinite(step) && step < u.ThrStep.Value, u.ThrStep.Value = step; end
        end

        function covApplyX(app, b)
            u = app.ui; setRange(u.CovXSlider, b, b); setRange(u.CovXMin, b(1), [app.Full(1), b(2) - 0.1]); setRange(u.CovXMax, b(2), [b(1) + 0.1, app.Full(2)]);
            set(u.CovAxes, 'XLimMode', 'manual', 'XLim', b);
        end

        function onCovXChanged(app, source, value)
            % Spinners are the masters (they define the slider travel); the slider only narrows the visible window.
            u = app.ui;
            if isequal(source, u.CovXSlider)
                v = sort(value); if diff(v) <= 0, return; end
                [u.CovXMin.Value, u.CovXMax.Value] = deal(v(1), v(2)); set(u.CovAxes, 'XLimMode', 'manual', 'XLim', v); return
            end
            b = sort([u.CovXMin.Value, u.CovXMax.Value]);
            if diff(b) <= 0, if isequal(source, u.CovXMin), b(2) = b(1) + 0.1; else, b(1) = b(2) - 0.1; end, end
            app.covApplyX(clampRange(b, app.Full));
        end

        function s = coneLabel(app, th, ph)
            % Principal-axis name when the cone centre coincides with one, otherwise the explicit spherical coordinates.
            ax = app.Axes; A = [sind(ax.theta(:)).*cosd(ax.phi(:)), sind(ax.theta(:)).*sind(ax.phi(:)), cosd(ax.theta(:))];
            k = find(A*[sind(th)*cosd(ph); sind(th)*sind(ph); cosd(th)] >= 1 - 1e-9, 1);
            if isempty(k), s = sprintf('θ=%s°, φ=%s°', fmtNum(th), fmtNum(ph)); else, s = ax.labels{k}; end
        end

        % ---- coverage event handlers ------------------------------------------------------------
        function onToCoverage(app)
            if isempty(app.viewTbl), uialert(app.ui.Fig, 'Load and process a pattern first.', 'Coverage'); return; end
            u = app.ui; [u.Tabs.SelectedTab, u.CovPath.Value] = deal(u.TabCov, app.filePath); node = app.covFindByPath(app.filePath);
            if isempty(node), app.covAddPattern(app.baseName, app.viewTbl, app.filePath, app.src.raw);
            else, app.covSyncFromView(node); u.CovTree.SelectedNodes = node; app.setCoverageUI(); end
            app.setStatus(u.CovStatus, 'Coverage source synchronized from the current Main-tab View Table.', false);
        end

        function onCovLoad(app)
            u = app.ui; fp = strtrim(u.CovPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFindByPath(fp))
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.ffd;*.ffe;*.ffs;*.cut;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage data'; '*.*', 'All files'}, 'Select a pattern or coverage results file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            existing = app.covFindByPath(fp); u.CovPath.Value = fp;
            if ~isempty(existing)
                u.CovTree.SelectedNodes = existing; app.onCovSelection(); app.setCoverageUI(); app.setStatus(u.CovStatus, 'File already loaded — node selected.', true); return
            end
            try
                out = app.readSource(fp, u.CovFormatLabel, u.CovFormat);
                if out.meta.isCoverage, app.covLoadResults(fp, out.raw); else, [~, name] = fileparts(fp); app.covAddPattern(name, app.buildPattern(out), fp, out.raw); end
            catch ME
                app.showError(ME, 'Coverage Load Error');
            end
        end

        function onCovFormat(app)
            % Re-interpret an existing generic-text pattern node with the newly selected format.
            u = app.ui; fp = strtrim(u.CovPath.Value); old = app.covFindByPath(fp);
            if isempty(old) || ~isGenericText(fp) || ~nodeIs(old, 'pattern'), return; end
            try
                out = readPattern(fp, u.CovFormat.Value, old.NodeData.raw);
                if out.meta.isCoverage, app.setStatus(u.CovStatus, 'Coverage-result files are detected automatically; nothing to reprocess.', true); return; end
                for job = app.covNodes('job', old).', delete(job.NodeData.line); end
                name = old.NodeData.name; delete(old); app.covAddPattern(name, app.buildPattern(out), fp, out.raw); app.finalizeJobs();
                app.setStatus(u.CovStatus, sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
            catch ME
                app.showError(ME, 'Coverage Format Error');
            end
        end

        function onCovComponent(app)
            node = app.covTarget(); if isempty(node), return; end
            d = node.NodeData; d.component = ''; node.NodeData = d; app.covSyncPattern(node);   % adopt the user's selection, re-detect orientation
        end

        function onCovCompute(app)
            node = app.covTarget(); u = app.ui;
            if isempty(node), uialert(u.Fig, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if strcmp(node.NodeData.path, app.filePath) && ~isempty(app.viewTbl), app.covSyncFromView(node); end
            try
                d = node.NodeData; T = d.pattern; comp = u.CovComponent.Value; thr = app.covThresholds(); conical = u.Conical.Value;
                mask = true(height(T), 1); tag = 'Sph'; label = 'Sph coverage'; tableTag = 'Sph'; orient = "n/a";
                if conical
                    [th0, ph0, a] = deal(u.ConeTh.Value, mod(u.ConePh.Value, 360), u.ConeAng.Value);
                    mask = cosd(T.Theta)*cosd(th0) + sind(T.Theta)*sind(th0).*cosd(T.Phi - ph0) >= cosd(a);
                    centre = app.coneLabel(th0, ph0); k = app.covOrientationIndex(); if isfinite(k), orient = string(app.Axes.labels{k}); end
                    tag = sprintf('Con_%g_%g_%g', th0, ph0, a); label = sprintf('Conical coverage (%s) α=%s°', centre, fmtNum(a)); tableTag = sprintf('Con %s α%s°', erase(centre, ["=", ","]), fmtNum(a));
                end
                cov = coverageCCDF(T.(comp), mask, thr, d.dOmega);
                job = app.covAddJob(node, thr, cov, tag, comp, label, tableTag, conical, orient);
                app.finalizeJobs(); app.setCovXRange([thr(1) thr(end)]); u.CovResults.Visible = 'on';
                msg = sprintf('Run-<b>%d</b> computed: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', job.NodeData.id, label, d.name, comp, numel(thr));
                if conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, orient); end
                app.setStatus(u.CovStatus, msg, false);
            catch ME
                app.showError(ME, 'Coverage Error');
            end
        end

        function covQuery(app, mode)
            % "cov": coverage at a threshold (x → y).  "thr": threshold at a coverage level (y → x).  One marker+tip per checked job.
            u = app.ui; ax = u.CovAxes; sel = u.CovTree.SelectedNodes;
            if isempty(sel), app.setStatus(u.CovStatus, 'Select a node to query.', true); return; end
            jobs = app.covNodes('job', sel); jobs = jobs(ismember(jobs, u.CovTree.CheckedNodes));
            if isempty(jobs), app.setStatus(u.CovStatus, 'No checked results under the selected node.', true); return; end
            if mode == "cov", q = u.QueryCov.Value; else, q = u.QueryThr.Value; end
            hit = false;
            for job = jobs.'
                d = job.NodeData; tag = sprintf('CovQ_%s_%d', mode, d.id); delete(findall(ax, 'Tag', tag));
                if mode == "cov", x = q; y = interp1(d.thr, d.cov, q, 'linear', NaN); else, x = invCoverage(d.thr, d.cov, q); y = q; end
                if ~isfinite(x) || ~isfinite(y), continue; end
                col = d.line.Color; hit = true;
                line(ax, [x x], [ax.YLim(1) y], 'Color', col, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [ax.XLim(1) x], [y y], 'Color', col, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                m = plot(ax, x, y, 'o', 'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 5, 'HandleVisibility', 'off', 'Tag', tag);
                setTip(m, [dataTipTextRow("Threshold", x, '%.4g dB'); dataTipTextRow("Coverage", y, '%.4g%%')]);
                try, t = datatip(m, 'DataIndex', 1, 'FontSize', 9); t.Tag = tag; catch, end
            end
            if ~hit, app.setStatus(u.CovStatus, 'Query value is outside the selected checked range.', true);
            elseif mode == "cov", app.setStatus(u.CovStatus, sprintf('Coverage queried at %s dB.', fmtNum(q)), false);
            else, app.setStatus(u.CovStatus, sprintf('Threshold queried at %s%% coverage.', fmtNum(q)), false); end
        end

        function onCovChecked(app)
            checked = app.ui.CovTree.CheckedNodes;
            for job = app.covNodes('job').'
                d = job.NodeData; on = ismember(job, checked); d.line.Visible = on;
                set(findall(app.ui.CovAxes, '-regexp', 'Tag', sprintf('^CovQ_\\w+_%d$', d.id)), 'Visible', on); set(findall(d.line, 'Type', 'datatip'), 'Visible', on);
            end
            app.finalizeJobs();
        end

        function onCovSelection(app)
            u = app.ui; sel = u.CovTree.SelectedNodes;
            for job = app.covNodes('job').', job.NodeData.line.LineWidth = 1.6 + (~isempty(sel) && isequal(job, sel(1))); end   % emphasise the selected curve
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(u.CovStatus, 'Ready.', false); return; end
            d = sel(1).NodeData; node = app.covTarget(); if ~isempty(node), app.covSyncPattern(node); end
            if ~strcmp(d.kind, 'job')
                n = numel(sel(1).Children); kind = 'Pattern'; if strcmp(d.kind, 'results'), kind = 'Results'; end
                app.setStatus(u.CovStatus, sprintf('%s <b>"%s"</b> — <b>%d</b> coverage job%s.', kind, d.name, n, repmat('s', 1, +(n ~= 1))), false);
                if strcmp(d.kind, 'pattern'), app.covOrientationStatus(); end
                return
            end
            shown = round(d.cov, 2); mx = max(shown); mi = find(shown == mx, 1, 'last'); thr50 = invCoverage(d.thr, d.cov, 50);
            parts = {char(d.label)}; if d.conical, parts{end+1} = sprintf('Orientation <b>%s</b>', d.orientation); end
            parts{end+1} = sprintf('Threshold [%s, %s] dB | Step %s dB', fmtNum(d.thr(1)), fmtNum(d.thr(end)), fmtNum(gridStep(d.thr)));
            if isfinite(thr50), parts{end+1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', fmtNum(thr50)); else, parts{end+1} = '<b>50%-coverage unavailable</b>'; end
            parts{end+1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmtNum(mx), fmtNum(d.thr(mi)));
            app.setStatus(u.CovStatus, strjoin(parts, ' | '), false);
        end

        function onCovClear(app)
            u = app.ui; sel = u.CovTree.SelectedNodes;
            if isempty(sel), app.setStatus(u.CovStatus, 'Select a node to clear.', true); return; end
            for job = app.covNodes('job', sel).'
                d = job.NodeData; delete(findall(u.CovAxes, '-regexp', 'Tag', sprintf('^CovQ_\\w+_%d$', d.id))); delete(findall(d.line, 'Type', 'datatip'));
            end
            app.setStatus(u.CovStatus, 'Selected DataTips and query markers cleared.', true);
        end

        function onCovReset(app)
            u = app.ui; delete(u.CovRoot.Children); cla(u.CovAxes); legend(u.CovAxes, 'off'); hold(u.CovAxes, 'on'); grid(u.CovAxes, 'on');
            u.CovTable.Data = table(); [app.covRunID, app.covPresetKey, app.covXInit, app.covThrInit] = deal(0, "", false, false);
            set(u.CovAxes, 'XLimMode', 'auto'); setRange(u.CovXSlider, [-40 10], app.Full); setRange(u.CovXMin, -40, app.Full); setRange(u.CovXMax, 10, app.Full);
            u.CovResults.Visible = 'off'; app.setCoverageUI(); app.setStatus(u.CovStatus, 'Coverage workspace reset 🔄', true);
        end

        function onCovExport(app), if ~isempty(app.ui.CovTable.Data), app.saveTable(app.ui.CovTable.Data, 'coverage_results.csv', 'Coverage results', app.ui.CovStatus); end, end

        %% ───────────────────────────── UI construction ─────────────────────────────
        function h = add(~, ctor, parent, row, col, varargin)
            % Create a component in a grid cell: ADD(@uibutton, grid, row, col, 'Text', ...).
            h = ctor(parent, varargin{:}); if ~isempty(row), h.Layout.Row = row; end, if ~isempty(col), h.Layout.Column = col; end
        end

        function h = label(app, parent, row, col, txt, varargin), h = app.add(@uilabel, parent, row, col, 'Text', txt, 'HorizontalAlignment', 'right', varargin{:}); end

        function d = formatDropdown(app, parent, row, col, cb)
            d = app.add(@uidropdown, parent, row, col, 'Visible', 'off', 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'ValueChangedFcn', cb, ...
                'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', '4: POL1=RCP, POL2=LCP — dB magnitude, phase', ...
                '5: POL1=LCP, POL2=RCP — dB magnitude, phase', '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'});
        end

        function [g, ax, slider, mn, mx] = patternTab(app, group, titleText, hasAxes)
            % One full-pattern tab: [max spinner / vertical range slider / min spinner] beside an optional axes.
            g = uigridlayout(uitab(group, 'Title', titleText), 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
            ax = []; if hasAxes, ax = app.add(@uiaxes, g, [1 3], 2, 'Box', 'on'); end
            slider = app.add(@(o, varargin) uislider(o, 'range', varargin{:}), g, 2, 1, 'Limits', app.Full, 'Value', app.Full, 'Orientation', 'vertical', 'Step', 1);
            mx = app.add(@uispinner, g, 1, 1, 'Limits', app.Full, 'Value', app.Full(2), 'Step', 5);
            mn = app.add(@uispinner, g, 3, 1, 'Limits', app.Full, 'Value', app.Full(1), 'Step', 5);
        end

        function createComponents(app)
            u = struct(); pad = @(n) repmat(char(160), 1, n); edit = @(o, varargin) uieditfield(o, 'text', varargin{:}); rangeSlider = @(o, varargin) uislider(o, 'range', varargin{:});
            sw = @(o, varargin) uiswitch(o, 'slider', varargin{:}); cell1 = @(parent) uigridlayout(parent, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            u.Fig = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.Release], 'Visible', 'off', 'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) delete(app));
            u.Tabs = uitabgroup(cell1(u.Fig));
            % ── Main tab ─────────────────────────────────────────────────────────────────────
            u.TabMain = uitab(u.Tabs, 'Title', 'Process Pattern 📡');
            g = uigridlayout(u.TabMain, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});
            u.PanelParam = app.add(@uipanel, g, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️');
            p = uigridlayout(u.PanelParam, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            app.label(p, 1, 1, 'Input Pattern:'); u.Path = app.add(edit, p, 1, [2 8]);
            u.FFDLabel = app.label(p, 1, 9, 'FFD Freq:', 'Visible', 'off'); u.FFD = app.add(@uidropdown, p, 1, 10, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', @(~, ~) app.onFFDChanged());
            u.Load = app.add(@uibutton, p, 1, [11 12], 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.onLoad());
            u.Process = app.add(@uibutton, p, 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', @(~, ~) app.onProcess());
            u.ResetParams = app.add(@uibutton, p, 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', @(~, ~) app.resetParams());
            u.FormatLabel = app.label(p, 2, [4 5], 'Format:', 'Visible', 'off'); u.Format = app.formatDropdown(p, 2, [6 8], @(~, ~) app.onFormatChanged());
            u.Step = app.add(@uidropdown, p, 2, [9 10], 'Items', {'STEP'}, 'Visible', 'off', 'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.onStepChanged());
            u.ExportOut = app.add(@uibutton, p, 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.exportResults());
            u.ExportUAN = app.add(@uibutton, p, 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.exportUAN());
            u.RxPolLabel = app.label(p, 3, 1, 'Rw Sense', 'Visible', 'off'); u.RxPol = app.add(@uidropdown, p, 3, 2, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Visible', 'off');
            u.RwLabel = app.label(p, 3, 3, 'Rw (dB)', 'Visible', 'off'); u.Rw = app.add(@uispinner, p, 3, 4, 'Value', 6, 'Visible', 'off');
            u.LossLabel = app.label(p, 3, 5, 'Loss (−) / Gain (+) dB', 'Visible', 'off'); u.Loss = app.add(@uispinner, p, 3, 6, 'Step', 0.1, 'Visible', 'off');
            u.PtLabel = app.label(p, 3, 7, 'Tx Pwr (Pt)', 'Visible', 'off'); u.Pt = app.add(@uispinner, p, 3, 8, 'Visible', 'off'); u.PtUnit = app.add(@uidropdown, p, 3, 9, 'Items', {'dBW', 'dBm', 'Watts'}, 'Visible', 'off');
            u.RLabel = app.label(p, 3, 10, 'Distance', 'Visible', 'off'); u.R = app.add(@uispinner, p, 3, 11, 'Value', 1, 'Visible', 'off'); u.RUnit = app.add(@uidropdown, p, 3, 12, 'Items', {'m', 'km'}, 'Visible', 'off');
            u.CoverageBtn = app.add(@uibutton, p, 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.onToCoverage());
            % full-pattern panel: five tabs sharing one color range
            u.PanelFull = app.add(@uipanel, g, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off');
            u.TabsFull = uitabgroup(cell1(u.PanelFull));
            [~, u.AxesCtr, s1, n1, x1] = app.patternTab(u.TabsFull, 'Contour Plot', true);
            [u.GridCircular, ~, s2, n2, x2] = app.patternTab(u.TabsFull, 'Circular Contour Plot', false);
            [~, u.Axes3dSph, s3, n3, x3] = app.patternTab(u.TabsFull, '3D Spherical Plot', true);
            [~, u.Axes3dPol, s4, n4, x4] = app.patternTab(u.TabsFull, '3D Polar Plot', true);
            [~, u.Axes3dRect, s5, n5, x5] = app.patternTab(u.TabsFull, '3D Surface Plot', true);
            u.FullSliders = [s1 s2 s3 s4 s5]; u.FullMins = [n1 n2 n3 n4 n5]; u.FullMaxs = [x1 x2 x3 x4 x5];
            set(u.FullSliders, 'ValueChangedFcn', @(s, ~) app.onRangeChanged(s.Value, 0, "full", true));
            set(u.FullMins, 'ValueChangedFcn', @(s, ~) app.onRangeChanged(s.Value, 1, "full", true)); set(u.FullMaxs, 'ValueChangedFcn', @(s, ~) app.onRangeChanged(s.Value, 2, "full", true));
            % cut panel
            u.PanelCut = app.add(@uipanel, g, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off');
            u.TabsCut = uitabgroup(cell1(u.PanelCut)); u.TabPolar = uitab(u.TabsCut, 'Title', 'Polar Cut Plot');
            u.GridPolar = uigridlayout(u.TabPolar, 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            u.CutSlider = app.add(rangeSlider, u.GridPolar, [2 3], 1, 'Limits', app.Full, 'Value', app.Full, 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s, ~) app.onRangeChanged(s.Value, 0, "cut", true));
            u.CutMax = app.add(@uispinner, u.GridPolar, 1, 1, 'Limits', app.Full, 'Value', app.Full(2), 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRangeChanged(s.Value, 2, "cut", true));
            u.CutMin = app.add(@uispinner, u.GridPolar, 4, 1, 'Limits', app.Full, 'Value', app.Full(1), 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRangeChanged(s.Value, 1, "cut", true));
            u.HPBW = app.add(@(o, varargin) uibutton(o, 'state', varargin{:}), u.GridPolar, 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', @(~, ~) app.onCutChanged());
            u.HPBWLabel = app.add(@uilabel, u.GridPolar, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            u.GridEcut = app.add(@uigridlayout, u.GridPolar, 3, 4, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x', '1x', '1x'});
            u.Et = app.add(@uicheckbox, u.GridEcut, 1, 1, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', @(~, ~) app.onCutChanged());
            u.Er = app.add(@uicheckbox, u.GridEcut, 2, 1, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', @(~, ~) app.onCutChanged());
            u.El = app.add(@uicheckbox, u.GridEcut, 3, 1, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', @(~, ~) app.onCutChanged());
            u.ExportCut = app.add(@uibutton, u.GridPolar, 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.exportCut());
            u.TabRect = uitab(u.TabsCut, 'Title', 'Rectangular Cut Plot'); u.AxesRect = uiaxes(cell1(u.TabRect), 'Box', 'on'); ylabel(u.AxesRect, 'Magnitude (dB)');
            % plot control panel
            u.PanelCtrl = app.add(@uipanel, g, 2, [13 14], 'Title', 'Plot Control 🎨', 'Visible', 'off');
            c = uigridlayout(u.PanelCtrl, 'RowHeight', repmat({'fit'}, 1, 15));
            app.label(c, 1, 1, 'Component'); u.Component = app.add(@uidropdown, c, 1, 2, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', @(~, ~) app.onComponentChanged());
            app.label(c, 2, 1, 'Cut type'); u.CutType = app.add(@uidropdown, c, 2, 2, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', @(s, ~) app.onCutChanged(s));
            app.label(c, 3, 1, 'Cut value'); u.CutValue = app.add(@uispinner, c, 3, 2, 'Limits', [0 360], 'ValueChangedFcn', @(~, ~) app.onCutChanged());
            app.label(c, 4, 1, 'Cut fields'); u.CutBasis = app.add(@uidropdown, c, 4, 2, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Enable', 'off', 'ValueChangedFcn', @(s, ~) app.onCutChanged(s));
            app.label(c, 5, 1, 'Colorbar max'); u.Cmax = app.add(@uispinner, c, 5, 2, 'Limits', app.Full, 'Value', 10, 'ValueChangedFcn', @(~, ~) app.applyColorbarSpinners());
            app.label(c, 6, 1, 'Colorbar min'); u.Cmin = app.add(@uispinner, c, 6, 2, 'Limits', app.Full, 'Value', -40, 'ValueChangedFcn', @(~, ~) app.applyColorbarSpinners());
            app.label(c, 7, 1, 'Colorbar step'); u.Cstep = app.add(@uispinner, c, 7, 2, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', @(~, ~) app.applyFullRange());
            app.label(c, 8, 1, 'Adjust Colorbar'); app.add(@uibutton, c, 8, 2, 'Text', 'Apply', 'Tooltip', 'Apply the min/max to all full-pattern and cut plots.', 'ButtonPushedFcn', @(~, ~) app.applyColorbarSpinners());
            app.label(c, 9, 1, '3D view'); u.View3D = app.add(@uidropdown, c, 9, 2, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Tooltip', 'Camera direction for the 3D pattern tabs.', 'ValueChangedFcn', @(~, ~) app.on3DViewChanged());
            u.PhiSpan = app.add(sw, c, 10, [1 2], 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'ValueChangedFcn', @(~, ~) app.onSpanChanged());
            u.ThetaSpan = app.add(sw, c, 11, [1 2], 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'ValueChangedFcn', @(~, ~) app.onSpanChanged());
            u.Plane = app.add(sw, c, 12, [1 2], 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'ValueChangedFcn', @(~, ~) app.onPlaneChanged());
            u.Overlay = app.add(@uicheckbox, c, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', @(~, ~) app.updateOverlays());
            u.POB = app.add(@uicheckbox, c, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', @(~, ~) app.onPOBToggled());
            u.HPBWBounds = app.add(@uicheckbox, c, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', @(~, ~) app.refreshHPBW());
            % data tables + status
            u.Filter = app.add(@uidropdown, g, 3, [13 14], 'Items', {'Select Output:'}, 'Visible', 'off', 'ValueChangedFcn', @(~, ~) app.filterOutput());
            u.TabsData = app.add(@uitabgroup, g, 4, [1 14], 'Visible', 'off');
            t = uitab(u.TabsData, 'Title', 'Results 📤', 'ButtonDownFcn', @(~, ~) set(u.Filter, 'Visible', 'on'));
            u.TableOut = uitable(cell1(t), 'ColumnWidth', '1x', 'ColumnSortable', true, 'ColumnRearrangeable', 'on', 'RowName', 'numbered');
            u.TableIn = uitable(cell1(uitab(u.TabsData, 'Title', 'Input 📥')), 'ColumnSortable', true, 'ColumnRearrangeable', 'on', 'RowName', 'numbered');
            u.TableMeta = uitable(cell1(uitab(u.TabsData, 'Title', 'Metadata 📋')), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            u.Status = app.add(@uilabel, g, 5, [1 14], 'Interpreter', 'html', 'Text', 'Ready — load an antenna pattern file to begin 🚀');
            % ── Coverage tab ─────────────────────────────────────────────────────────────────
            u.TabCov = uitab(u.Tabs, 'Title', 'Compute Coverage 📈');
            g = uigridlayout(u.TabCov, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            u.CovPanel = app.add(@uipanel, g, 1, [1 5], 'Title', 'Inputs & Parameters 🎛️');
            q = uigridlayout(u.CovPanel, 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'}); u.CovPanelGrid = q;
            u.CovType = app.add(@uibuttongroup, q, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', @(~, ~) app.onCovType());
            u.Spherical = uiradiobutton(u.CovType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true); u.Conical = uiradiobutton(u.CovType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            u.CovOrientationLabel = app.label(q, 3, 1, 'Orientation 🧭:');
            u.CovOrientation = app.add(@uidropdown, q, 3, 2, 'Items', [{'Auto'}, app.Axes.labels], 'ItemsData', 0:6, 'ValueChangedFcn', @(~, ~) app.onCovOrientation());
            u.CovPathLabel = app.label(q, 1, 3, 'Antenna Pattern:'); u.CovPath = app.add(edit, q, 1, [4 8]);
            u.CovLoad = app.add(@uibutton, q, 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', @(~, ~) app.onCovLoad());
            u.CovCompute = app.add(@uibutton, q, 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.onCovCompute());
            app.label(q, 2, 3, 'Threshold  Min (dB):'); u.ThrMin = app.add(@uispinner, q, 2, 4, 'Value', -40);
            app.label(q, 2, 5, 'Threshold  Max (dB):'); u.ThrMax = app.add(@uispinner, q, 2, 6, 'Value', 10);
            app.label(q, 2, 7, 'Step (dB):'); u.ThrStep = app.add(@uispinner, q, 2, 8, 'Value', 1, 'Limits', [0.1 100]);
            u.CovReset = app.add(@uibutton, q, 2, 9, 'Text', '🔄 Reset', 'ButtonPushedFcn', @(~, ~) app.onCovReset());
            u.CovExport = app.add(@uibutton, q, 2, 10, 'Text', '💾 Export Results', 'ButtonPushedFcn', @(~, ~) app.onCovExport());
            l1 = app.label(q, 3, 3, 'Cone θ₀ (°):'); u.ConeTh = app.add(@uispinner, q, 3, 4, 'Limits', [0 180]);
            l2 = app.label(q, 3, 5, 'Cone φ₀ (°):'); u.ConePh = app.add(@uispinner, q, 3, 6, 'Limits', [0 360]);
            l3 = app.label(q, 3, 7, 'Cone Angle α (°):'); u.ConeAng = app.add(@uispinner, q, 3, 8, 'Limits', [0 180], 'Value', 45);
            u.ConeCtrls = [u.CovOrientationLabel u.CovOrientation l1 u.ConeTh l2 u.ConePh l3 u.ConeAng];
            u.CovClear = app.add(@uibutton, q, 3, 9, 'Text', '🧹 Clear DataTips', 'ButtonPushedFcn', @(~, ~) app.onCovClear());
            u.CovToMain = app.add(@uibutton, q, 3, 10, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~, ~) set(u.Tabs, 'SelectedTab', u.TabMain));
            app.label(q, 4, 1, 'Component:'); u.CovComponent = app.add(@uidropdown, q, 4, 2, 'Items', {'E_Total_dB'}, 'ValueChangedFcn', @(~, ~) app.onCovComponent());
            l4 = app.label(q, 4, 3, 'Coverage @ dB:'); u.QueryCov = app.add(@uispinner, q, 4, 4, 'ValueDisplayFormat', '%g dB');
            u.QueryCovBtn = app.add(@uibutton, q, 4, 5, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', @(~, ~) app.covQuery("cov"));
            l5 = app.label(q, 4, 6, 'Threshold @ %:'); u.QueryThr = app.add(@uispinner, q, 4, 7, 'Value', 50, 'ValueDisplayFormat', '%g%%');
            u.QueryThrBtn = app.add(@uibutton, q, 4, 8, 'Text', '🔍 Query Threshold', 'ButtonPushedFcn', @(~, ~) app.covQuery("thr"));
            u.QueryCtrls = [l4 u.QueryCov u.QueryCovBtn l5 u.QueryThr u.QueryThrBtn];
            u.CovFormatLabel = app.label(q, 4, 9, 'Format:'); u.CovFormat = app.formatDropdown(q, 4, 10, @(~, ~) app.onCovFormat());
            u.CovStatus = app.add(@uilabel, g, 3, [1 5], 'Interpreter', 'html', 'Text', 'Ready 🚀');
            u.CovResults = app.add(@uipanel, g, 2, [1 5], 'Title', 'Results', 'Visible', 'off');
            r = uigridlayout(u.CovResults, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            u.CovAxes = app.add(@uiaxes, r, 1, [2 4], 'Box', 'on', 'Layer', 'top', 'YLim', [0 100], 'Interactions', dataTipInteraction);
            title(u.CovAxes, 'Coverage vs Threshold'); xlabel(u.CovAxes, 'Threshold (dB)'); ylabel(u.CovAxes, 'Coverage (%)'); hold(u.CovAxes, 'on'); grid(u.CovAxes, 'on');
            u.CovTree = app.add(@(o, varargin) uitree(o, 'checkbox', varargin{:}), r, [1 2], 1, 'SelectionChangedFcn', @(~, ~) app.onCovSelection(), 'CheckedNodesChangedFcn', @(~, ~) app.onCovChecked());
            u.CovRoot = uitreenode(u.CovTree, 'Text', 'Coverage Results');
            u.CovTable = app.add(@uitable, r, [1 2], 5, 'ColumnWidth', '1x', 'RowName', {});
            u.CovXMin = app.add(@uispinner, r, 2, 2, 'Limits', app.Full, 'Value', -40, 'ValueChangedFcn', @(s, e) app.onCovXChanged(s, e.Value));
            u.CovXSlider = app.add(rangeSlider, r, 2, 3, 'Limits', app.Full, 'Value', [-40 10], 'ValueChangedFcn', @(s, e) app.onCovXChanged(s, e.Value), 'ValueChangingFcn', @(s, e) app.onCovXChanged(s, e.Value));
            u.CovXMax = app.add(@uispinner, r, 2, 4, 'Limits', app.Full, 'Value', 10, 'ValueChangedFcn', @(s, e) app.onCovXChanged(s, e.Value));
            app.ui = u; u.Fig.Visible = 'on';
        end
    end
end

%% ═════════════════════════════════ I/O (pure functions) ═════════════════════════════════
function out = readPattern(fp, fmt, raw)
%readPattern Universal source reader → struct(raw, blocks{canonical tables}, freqs, meta).
%   Every E-field source becomes {Theta, Phi, Re_Eth, Im_Eth, Re_Eph, Im_Eph}; gain-only and coverage tables pass through.
if nargin < 3, raw = table(); end
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.')); fmt = string(fmt);
out = struct('raw', table(), 'blocks', {{}}, 'freqs', NaN, 'meta', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false));
switch ext
    case {'XLSX', 'XLS'},        out = readExcelMatrix(fp); return
    case {'CSV', 'TXT', 'DAT'},  out = readGenericText(fp, fmt, raw, out); return
    case 'CUT',                  out = readGraspCut(fp, out); return
end
[nHdr, ffd] = findHeaderLines(fp);
o = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = readmatrix(fp, setvartype(o, o.VariableNames, 'double')); M = M(~all(isnan(M), 2), :);
switch ext
    case {'FZ', 'UAN'}   % XGTD: Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
        names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}; src = ['XGTD ' ext]; th = M(:, 1); ph = M(:, 2);
        E1 = magPhase(M(:, 3), M(:, 5)); E2 = magPhase(M(:, 4), M(:, 6)); circ = false;
    case 'OUT'           % TICRA/GRASP: Theta Phi Re(RHCP) Im(RHCP) Re(LHCP) Im(LHCP)
        names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; src = 'TICRA/GRASP OUT'; th = M(:, 1); ph = M(:, 2);
        E1 = complex(M(:, 3), M(:, 4)); E2 = complex(M(:, 5), M(:, 6)); circ = true;
    case 'FFS'           % CST: Phi Theta Re(Eth) Im(Eth) Re(Eph) Im(Eph)
        names = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; src = 'CST FFS'; th = M(:, 2); ph = M(:, 1);
        E1 = complex(M(:, 3), M(:, 4)); E2 = complex(M(:, 5), M(:, 6)); circ = false;
    case 'FFE'           % FEKO: Theta Phi Re(Eth) Im(Eth) Re(Eph) Im(Eph) (extra columns ignored)
        names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; src = 'FEKO FFE'; th = M(:, 1); ph = M(:, 2);
        E1 = complex(M(:, 3), M(:, 4)); E2 = complex(M(:, 5), M(:, 6)); circ = false;
    case 'FFD',          out = readFFD(M, ffd, out); return
    otherwise,           error('readFile:unsupported', 'Unsupported format: %s', ext);
end
out.raw = array2table(M(:, 1:6), 'VariableNames', names); out.meta.source = src; out.blocks = {stdTable(th, ph, E1, E2, circ)};
end

function E = magPhase(dB, deg), E = 10.^(dB/20) .* exp(1i*deg2rad(deg)); end

function T = stdTable(th, ph, E1, E2, circular)
%stdTable Canonical field table; circular pairs (RHCP, LHCP) are converted to (Eθ, Eφ).
if circular, [E1, E2] = deal((E1 + E2)/sqrt(2), (E1 - E2)/(1i*sqrt(2))); end
T = table(th(:), ph(:), real(E1(:)), imag(E1(:)), real(E2(:)), imag(E2(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function [nHdr, ffd] = findHeaderLines(fp)
%findHeaderLines Leading non-data line count; recognises the HFSS FFD header (two axis triples + optional Frequencies line).
ffd = struct('isFFD', false, 'theta', [], 'phi', [], 'freq', []);
fid = fopen(fp, 'r'); assert(fid > 0, 'apat:io:OpenFailed', 'Cannot open file: %s', fp); c = onCleanup(@() fclose(fid)); %#ok<NASGU>
triples = zeros(0, 3); nHdr = 0;
while size(triples, 1) < 2
    ln = fgetl(fid); if ~ischar(ln), break; end
    nHdr = nHdr + 1; if isempty(strtrim(ln)), continue; end
    v = sscanf(ln, '%f').'; if numel(v) == 3, triples(end+1, :) = v; else, break; end %#ok<AGROW>
end
if size(triples, 1) == 2
    ffd.theta = [triples(1, 1:2), round(triples(1, 3))]; ffd.phi = [triples(2, 1:2), round(triples(2, 3))];
    ffd.isFFD = all(isfinite(triples(:))) && all(triples(:, 3) >= 1);
    ln = fgetl(fid); while ischar(ln) && isempty(strtrim(ln)), nHdr = nHdr + 1; ln = fgetl(fid); end
    if ischar(ln)
        tok = regexp(ln, '^\s*frequenc(?:y|ies)\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok), nHdr = nHdr + 1; f = sscanf(tok{1}, '%f'); if numel(f) > 1, ffd.freq = f(:); end, end   % "Frequencies N" alone is only a count
    end
end
if ~ffd.isFFD                          % generic: the header ends at the first line holding ≥ 4 numeric fields
    frewind(fid); nHdr = 0; num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?';
    while true
        ln = fgetl(fid); if ~ischar(ln) || ~isempty(regexp(ln, ['^\s*' num '(?:[\s,;]+' num '){3,}\s*$'], 'once')), break; end
        nHdr = nHdr + 1;
    end
end
end

function out = readFFD(M, ffd, out)
%readFFD HFSS far-field: header grid axes + one Re/Im(Eθ,Eφ) block per frequency ("Frequency <f>" separator rows).
assert(ffd.isFFD, 'readFile:ffd', 'FFD header (theta/phi ranges) not found.');
thAxis = linspace(ffd.theta(1), ffd.theta(2), ffd.theta(3)).'; phAxis = linspace(ffd.phi(1), ffd.phi(2), ffd.phi(3)).';
th = repelem(thAxis, numel(phAxis)); ph = repmat(phAxis, numel(thAxis), 1); n = numel(th);
sep = isnan(M(:, 1)); freqs = [ffd.freq(:); M(sep, 2)].'; freqs = freqs(isfinite(freqs)); rows = M(~sep, 1:4);
assert(mod(size(rows, 1), n) == 0, 'readFile:ffd', 'FFD row count does not match the theta/phi grid.');
nb = size(rows, 1)/n; freqs(end+1:nb) = NaN; freqs = freqs(1:nb);
out.meta.source = 'HFSS FFD'; out.meta.isDep = nb > 1 || any(isfinite(freqs)); out.freqs = freqs;
out.blocks = cell(1, nb);
for b = 1:nb, B = rows((b-1)*n + (1:n), :); out.blocks{b} = stdTable(th, ph, complex(B(:, 1), B(:, 2)), complex(B(:, 3), B(:, 4)), false); end
out.raw = out.blocks{1};
end

function out = readGenericText(fp, fmt, T, out)
%readGenericText CSV/TXT/DAT: coverage-results table, gain-only pattern, or a 6-column E-field layout selected by FMT.
if isempty(T)
    o = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    o = setvaropts(setvartype(o, 'double'), 'TrimNonNumeric', true); o.VariableNamingRule = 'preserve'; T = rmmissing(readtable(fp, o));
end
nc = width(T); assert(nc >= 2 && ~isempty(T), 'readFile:InvalidFormat', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHeaders = ~all(startsWith(names, "Var")); c1 = T{:, 1}; c2 = T{:, 2};
covHeader = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
if (fmt == "gain" || nc < 6 || covHeader) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')   % coverage results
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:nc-1))]; end
    out.raw = T; out.meta.isCoverage = true; return
end
if fmt == "gain"                                                                 % gain-only: the wider-span column is φ
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    T = movevars(T, 'Theta', 'Before', 1); out.raw = T; out.blocks = {T}; out.meta.isGainOnly = true; return
end
assert(nc >= 6, 'readFile:TextEFieldColumns', 'The selected generic E-field format requires six numeric columns.');
V = T{:, 3:6}; magPh = endsWith(fmt, "magphase"); circ = ~startsWith(fmt, "linear"); layout = "not applicable";
if magPh                                   % (mag, phase, mag, phase) vs (mag, mag, phase, phase): phases exceed 100
    big = max(abs(V), [], 1, 'omitnan') > 100;
    if big(2) && ~big(3), k = [1 2 3 4]; layout = "interleaved"; else, k = [1 3 2 4]; layout = "grouped"; end
    E1 = magPhase(V(:, k(1)), V(:, k(2))); E2 = magPhase(V(:, k(3)), V(:, k(4)));
else
    E1 = complex(V(:, 1), V(:, 2)); E2 = complex(V(:, 3), V(:, 4));
end
if circ && startsWith(fmt, "lcp"), [E1, E2] = deal(E2, E1); end
if ~hasHeaders                              % descriptive raw-table names for the Input tab
    if circ, base = ["POL1", "POL2"]; else, base = ["E_TH", "E_PH"]; end
    if magPh, f = [base + "_dB", base + "_deg"]; if layout == "interleaved", f = f([1 3 2 4]); end, else, f = [base(1) + ["_re", "_im"], base(2) + ["_re", "_im"]]; end
    T.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", f]);
end
out.raw = T; out.meta.source = sprintf('Generic text (%s, %s)', fmt, layout); out.blocks = {stdTable(c1, c2, E1, E2, circ)};
end

function out = readGraspCut(fp, out)
%readGraspCut TICRA/GRASP *.cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks.
out.meta.source = 'TICRA/GRASP CUT'; L = readlines(fp); L(strlength(strtrim(L)) == 0) = [];
th = {}; ph = {}; D = {}; k = 1; icomp = 1; icut = 1;
while k < numel(L)
    p = sscanf(L(k+1), '%f'); assert(numel(p) >= 7, 'readFile:cut', 'Could not parse the cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6); B = reshape(sscanf(strjoin(L(k+2:k+1+n), ' '), '%f'), 2*p(7), []).';
    th{end+1} = p(1) + (0:n-1).'*p(2); ph{end+1} = repmat(p(4), n, 1); D{end+1} = B(:, 1:4); k = k + 2 + n; %#ok<AGROW>
end
th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:});
if icut == 2, [th, ph] = deal(ph, th); end                                  % ICUT=2: φ swept at constant θ
neg = th < 0; ph(neg) = ph(neg) + 180; th(neg) = -th(neg);                  % fold negative θ onto the opposite half-plane
if isscalar(unique(ph)), n = numel(th); th = repmat(th, 36, 1); ph = repelem((0:10:350).', n); D = repmat(D, 36, 1); end   % single cut → body of revolution
circ = icomp == 2; if circ, names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; else, names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; end
out.raw = array2table([th ph D], 'VariableNames', [{'Theta', 'Phi'}, names]);
out.blocks = {stdTable(th, ph, complex(D(:, 1), D(:, 2)), complex(D(:, 3), D(:, 4)), circ)};
end

function out = readExcelMatrix(fp)
%readExcelMatrix Antenna-pattern Excel matrix workbooks: summary sheet + fixed component sheets (C3-origin matrices).
sheets = string(sheetnames(fp)); low = lower(sheets);
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"]; lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), low)); hasL = all(ismember(lower(lin), low));
assert(hasC || hasL, 'readFile:ExcelMatrixFormat', 'Unsupported Excel workbook: expected the fixed Etheta/Ephi and/or RHCP/LHCP component sheets after the summary sheet.');
req = [lin(hasL & true(1, 4)), circ(hasC & true(1, 4))]; M = struct(); ref = {};
for s = req
    [th, ph, data] = readExcelSheet(fp, sheets(find(low == lower(s), 1)));
    if isempty(ref), ref = {th, ph}; else, assert(isequal(size(th), size(ref{1})) && isequal(size(ph), size(ref{2})) && max(abs(th - ref{1})) < 1e-9 && max(abs(ph - ref{2})) < 1e-9, ...
            'readFile:ExcelMatrixGrid', 'All Excel component sheets must share the same theta/phi grid.'); end
    M.(char(s)) = data;
end
[thG, phG] = ndgrid(ref{1}, ref{2});
if hasL, E1 = magPhase(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); E2 = magPhase(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees); fmtNo = 1 + 2*hasC; basis = 'Eth/Eph';
else,    E1 = magPhase(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees); E2 = magPhase(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees); fmtNo = 2; basis = 'Ercp/Elcp'; end
if hasL && hasC, basis = 'Ercp/Elcp + Eth/Eph'; end
block = stdTable(thG, phG, E1, E2, ~hasL); raw = block(:, 1:2);
for s = req, raw.(char(s)) = reshape(M.(char(s)), [], 1); end
meta = readExcelSummary(fp, sheets(1)); meta.source = sprintf('Excel Matrix Format %d (%s)', fmtNo, basis);
[meta.isGainOnly, meta.isCoverage, meta.isDep] = deal(false); freq = NaN; if isfield(meta, 'frequencyMHz'), freq = meta.frequencyMHz*1e6; end
out = struct('raw', raw, 'blocks', {{block}}, 'freqs', freq, 'meta', meta);
end

function [th, ph, data] = readExcelSheet(fp, sheet)
%readExcelSheet One C3-origin matrix: row 2 = φ axis, column B = θ axis (readcell keeps worksheet coordinates).
C = readcell(fp, 'Sheet', char(sheet)); assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'readFile:ExcelMatrixSheet', 'Sheet "%s" has no C3-origin matrix.', sheet);
isNum = @(x) isnumeric(x) && isscalar(x) && isfinite(x); pm = cellfun(isNum, C(2, 3:end)); tm = cellfun(isNum, C(3:end, 2));
np = find(~pm, 1) - 1; if isempty(np), np = numel(pm); end, nt = find(~tm, 1) - 1; if isempty(nt), nt = numel(tm); end
assert(np > 0 && nt > 0 && ~any(pm(np+1:end)) && ~any(tm(nt+1:end)), 'readFile:ExcelMatrixAxis', 'Sheet "%s" has a missing or non-contiguous theta/phi axis.', sheet);
ph = cell2mat(C(2, 3:2+np)).'; th = cell2mat(C(3:2+nt, 2)); cells = C(3:2+nt, 3:2+np);
assert(all(cellfun(isNum, cells), 'all'), 'readFile:ExcelMatrixSheet', 'Sheet "%s" contains nonnumeric/missing matrix samples.', sheet); data = cell2mat(cells);
assert(all(diff(th) > 0) && all(diff(ph) > 0) && th(1) >= -1e-9 && th(end) <= 180 + 1e-9 && ph(1) >= -1e-9 && ph(end) < 360 + 1e-9, ...
    'readFile:ExcelMatrixAxis', 'Sheet "%s" needs increasing axes within theta 0..180 and phi 0..360.', sheet);
end

function meta = readExcelSummary(fp, sheet)
%readExcelSummary Template summary sheet as a label→value dictionary (column B label, first non-empty C..E value).
meta = struct('summarySheet', char(sheet));
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
for r = 1:size(C, 1)
    lab = C{r, 2}; if ~(ischar(lab) || isstring(lab)) || strlength(strtrim(string(lab))) == 0, continue; end
    v = C(r, 3:min(5, size(C, 2))); v = v(~cellfun(@(x) isempty(x) || isa(x, 'missing'), v)); if isempty(v), continue; end
    meta.(matlab.lang.makeValidName(lower(regexprep(char(lab), '[^a-zA-Z0-9]+', '_')))) = v{1};
end
if isfield(meta, 'pattern_simulation_freq_mhz_'), meta.frequencyMHz = str2double(string(meta.pattern_simulation_freq_mhz_)); end
end

function writeTable(T, fp)
if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
end

function writeUAN(U, fp)
%writeUAN XGTD UAN: canonical header followed by tab-delimited magnitude/phase rows.
hdr = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\ncomplex\nmag_phase\n' ...
    'pattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
    min(U.Phi), max(U.Phi), gridStep(U.Phi), min(U.Theta), max(U.Theta), gridStep(U.Theta), max([U.E_TH_DB; U.E_PH_DB]));
writelines(hdr, fp); writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
end

%% ═════════════════════════════════ numerical services (pure functions) ═════════════════════════════════
function T = normalizePattern(T)
%normalizePattern Map any angular convention onto the canonical sphere: θ∈[0,180], φ∈[0,360) plus one closing φ=360 copy.
%   Only the ANGLES are snapped to a 5-decimal grid (removes seam round-off); field values keep full precision.
th = T.Theta; ph = T.Phi;
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, th = 90 - th;                       % elevation convention
    else, ph(th < 0) = ph(th < 0) + 180; th = abs(th); end                   % negative θ = opposite half-plane
end
th = mod(th, 360); over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;
T.Theta = round(th, 5); T.Phi = mod(round(ph, 5), 360);
[~, keep] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(keep, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function [P, info] = calcPattern(S, p, pct, exc)
%calcPattern Canonical source → processed table with every derived quantity (allocation-light hot path).
info = struct('POB', NaN, 'POBth', NaN, 'POBph', NaN, 'pol', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
meta = S.Properties.UserData;
if isstruct(meta) && isfield(meta, 'isGainOnly') && meta.isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + p.GainLoss_dB; end
    info.peak = resolvePeak(P{:, 3}, pct, exc); [info.POB, info.POBth, info.POBph] = deal(info.peak.value, P.Theta(info.peak.index), P.Phi(info.peak.index)); return
end
Et = complex(S.Re_Eth, S.Im_Eth)*p.FieldScale; Ep = complex(S.Re_Eph, S.Im_Eph)*p.FieldScale;
Er = (Et + 1i*Ep)/sqrt(2); El = (Et - 1i*Ep)/sqrt(2); [mt, mp, mr, ml] = deal(abs(Et), abs(Ep), abs(Er), abs(El));
total = 10*log10(max(mt.^2 + mp.^2, eps));
info.peak = resolvePeak(total, pct, exc); [info.POB, info.POBth, info.POBph] = deal(info.peak.value, S.Theta(info.peak.index), S.Phi(info.peak.index));
% Dominant polarization drives the co/cross ordering of the cut pairs and the Auto receive sense.
pw = [mean(mt.^2, 'omitnan'), mean(mp.^2, 'omitnan'), mean(mr.^2, 'omitnan'), mean(ml.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif pw(1) >= pw(2),          info.pol = 'Linear (Vertical)';
else,                           info.pol = 'Linear (Horizontal)'; end
% Signed axial ratio (+RHCP / −LHCP); exactly equal circular components are the linear limit → −100 dB floor.
delta = mr - ml; sense = sign(delta); sense(~isfinite(delta)) = 0; ar = (mr + ml) ./ max(abs(delta), eps);
signedAR = min(20*log10(ar), 250) .* sense; signedAR(isfinite(delta) & abs(delta) <= eps*max(mr + ml, 1)) = -100;
% Polarization loss factor against the incident wave (axial ratio Rw, sense Auto/RHCP/LHCP).
if p.RxMode == "Auto", ws = 2*(info.pairs.Circular(1) == "E_RCP") - 1; elseif p.RxMode == "RHCP", ws = 1; else, ws = -1; end
ra = ar .* sense; ra(sense == 0) = 1e12; rw = ws*10^(p.RxAR_dB/20);
plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1)) ./ (2*(ra.^2 + 1)*(rw^2 + 1)); plfDB = 10*log10(min(max(plf, eps), 1));
eirp = p.Pt_dBW + total; eirpW = 10.^(eirp/10);
P = table(S.Theta, S.Phi, total, signedAR, 20*log10(max(mr, eps)), 20*log10(max(ml, eps)), plfDB, total + plfDB, 20*log10(max(mt, eps)), 20*log10(max(mp, eps)), ...
    rad2deg(angle(Et)), rad2deg(angle(Ep)), rad2deg(angle(Er)), rad2deg(angle(El)), eirp, eirpW/(4*pi*p.R_m^2), sqrt(30*eirpW)/p.R_m, ...
    'VariableNames', {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', 'PLF_dB', 'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase', ...
    'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
P.Properties.UserData = meta;
end

function R = resampleCanonical(S, step)
%resampleCanonical Resample the canonical source (fields or gain) onto a STEP° θ/φ grid with a closed φ seam.
%   Regular grids: periodic interp2.  Irregular samples: one scatteredInterpolant per column; gain-like dB columns in linear power.
th = S.Theta; ph = mod(S.Phi, 360); keep = find(isfinite(th) & isfinite(ph) & abs(S.Phi - 360) > 1e-9);   % drop the closing seam copy
[~, u] = unique([th(keep) ph(keep)], 'rows', 'stable'); keep = keep(u); S = S(keep, :); th = th(keep); ph = ph(keep);
[qPh, qTh] = meshgrid(unique([0:step:360, 360]), 0:step:180); R = table(qTh(:), qPh(:), 'VariableNames', {'Theta', 'Phi'});
ut = unique(th); up = unique(ph); [~, it] = ismember(th, ut); [~, ip] = ismember(ph, up); lin = sub2ind([numel(ut) numel(up)], it, ip);
regular = numel(lin) == numel(ut)*numel(up) && numel(unique(lin)) == numel(lin);
names = S.Properties.VariableNames(3:end); isField = all(ismember({'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}, names));
for c = names
    v = double(S.(c{1}));
    if regular
        [PG, TG] = meshgrid([up; up(1) + 360], ut); G = nan(numel(ut), numel(up)); G(lin) = v; G = [G, G(:, 1)];   % periodic φ closure
        q = interp2(PG, TG, G, qPh, qTh, 'linear', NaN); miss = ~isfinite(q);
        if any(miss, 'all'), nn = interp2(PG, TG, G, qPh, qTh, 'nearest', NaN); q(miss) = nn(miss); end
    else
        key = lower(c{1}); toLin = ~isField && (contains(key, 'gain') || contains(key, 'directivity') || endsWith(regexprep(key, '[^a-z0-9]', ''), 'db'));
        if toLin, v = 10.^(v/10); end
        F = scatteredInterpolant(ph, th, v, 'linear', 'nearest'); q = F(qPh, qTh); if toLin, q = 10*log10(max(q, realmin)); end
    end
    R.(c{1}) = q(:);
end
end

function info = resolvePeak(v, pct, exc)
%resolvePeak Effective peak: the raw maximum unless it exceeds the PCT percentile by more than EXC dB (isolated spike);
%   then the highest sample at/below the percentile is the peak and the samples above it are flagged as outliers.
v = double(v(:)); finite = isfinite(v);
info = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(v)), 'wasAdjusted', false, 'percentile', pct, 'maximumExcessDB', exc);
if ~any(finite), return; end
[info.rawValue, info.rawIndex] = max(v); [info.value, info.index] = deal(info.rawValue, info.rawIndex);
p = prctile(v(finite), pct); if info.rawValue <= p + exc, return; end
outliers = finite & v > p; cand = v; cand(~(finite & ~outliers)) = -Inf;
if any(isfinite(cand)), [info.value, info.index] = max(cand); info.outlierMask = outliers; info.wasAdjusted = true; end
end

function w = peakWindow(v, pct, exc)
%peakWindow 50-dB display/threshold window ending at the effective peak rounded up to the next 5 dB.
v = v(isfinite(v)); if isempty(v), w = [-50 0]; return; end
pk = resolvePeak(v, pct, exc); top = min(100, ceil(pk.value/5)*5); w = [max(-250, top - 50), top];
end

function r = clampRange(v, b)
%clampRange Sorted, clamped [lo hi] pair with a one-unit minimum span.
v = sort(double(v(:).')); if numel(v) < 2 || any(~isfinite(v(1:2))), r = b; return; end
r = [max(b(1), v(1)), min(b(2), v(2))]; if diff(r) < 1, r(2) = min(b(2), r(1) + 1); r(1) = max(b(1), r(2) - 1); end
end

function dOmega = solidWeights(th, ph)
%solidWeights Exact solid angle of every uniform grid cell; the duplicated φ seam column carries zero weight.
ts = gridStep(th); ps = gridStep(mod(ph, 360)); if ~isfinite(ts), ts = 180; end, if ~isfinite(ps), ps = 360; end
dOmega = (cosd(max(th - ts/2, 0)) - cosd(min(th + ts/2, 180))) * deg2rad(ps);
seam = 360 - 180*any(ph < 0); dOmega(abs(ph - seam) < 1e-9) = 0;
end

function cov = coverageCCDF(gain, mask, thr, dOmega)
%coverageCCDF Solid-angle-weighted coverage  Coverage(T) = 100·Σ_{G_i > T} Ω_i / Σ Ω_i  for every threshold at once.
%   Weighted histogram with right-closed bins (T_{k-1}, T_k] ⇒ cumsum(k) = weight of {G ≤ T_k}: exact strict '>' semantics
%   in O(N log N) memory/time instead of an N×T indicator matrix.
thr = double(thr(:)); ok = mask(:) & isfinite(gain(:)) & isfinite(dOmega(:)) & dOmega(:) >= 0;
g = double(gain(ok)); w = double(dOmega(ok)); total = sum(w); cov = zeros(size(thr));
if total <= 0 || isempty(g), return; end
[t, ~, back] = unique(thr); bin = discretize(g, [-Inf; t; Inf], 'IncludedEdge', 'right');
below = cumsum(accumarray(bin, w, [numel(t) + 1, 1])); cov = min(max(100*(1 - below(back)/total), 0), 100);
end

function x = invCoverage(thr, cov, q)
%invCoverage Threshold at coverage level Q (CCDF is monotone non-increasing; ties resolved to the last sample).
[c, i] = unique(cov, 'last'); x = NaN; if numel(c) > 1, x = interp1(c, thr(i), q, 'linear', NaN); end
end

function m = calcMetrics(T, dOmega, axesDef, k, pct, exc)
%calcMetrics Scalar antenna metrics from the total-gain column (physical θ, boresight axis K).
m = struct(); if isempty(T), return; end
g = chooseGain(T, 'E_Total_dB'); p = resolvePeak(g, pct, exc); i = p.index; gm = g; if p.wasAdjusted, gm(p.outlierMask) = NaN; end
P = sum(10.^(gm/10) .* dOmega, 'omitnan'); eff = 100*P/(4*pi); if eff < 0 || eff > 100, eff = NaN; end
[~, back] = min(cosd(T.Theta)*cosd(T.Theta(i)) + sind(T.Theta)*sind(T.Theta(i)).*cosd(T.Phi - T.Phi(i)));
if axesDef.theta(k) == 90, hType = "Phi"; else, hType = "Theta"; end
[eA, eR] = cutGeometry(T, "Theta", axesDef.phi(k)); [hA, hR] = cutGeometry(T, hType, 90);
ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(i); end
m = struct('PeakGain_dB', p.value, 'PeakTheta_deg', T.Theta(i), 'PeakPhi_deg', mod(T.Phi(i), 360), 'HPBW_EPlane_deg', calcHPBW(eA, g(eR)), 'HPBW_HPlane_deg', calcHPBW(hA, g(hR)), ...
    'FrontBack_dB', p.value - g(back), 'PeakDirectivity_dB', 10*log10(max(4*pi*10^(p.value/10)/max(P, eps), eps)), 'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', ar);
end

function k = calcOrientation(T, g, peak, dOmega, axesDef)
%calcOrientation Principal axis whose 45° cone captures the most peak-normalised radiated energy.
if peak.wasAdjusted, g(peak.outlierMask) = NaN; end
w = 10.^((g - peak.value)/10) .* dOmega; w(~isfinite(w)) = 0;
A = [sind(axesDef.theta(:)).*cosd(axesDef.phi(:)), sind(axesDef.theta(:)).*sind(axesDef.phi(:)), cosd(axesDef.theta(:))];
V = [sind(T.Theta).*cosd(T.Phi), sind(T.Theta).*sind(T.Phi), cosd(T.Theta)];
[~, k] = max(w.' * double(V*A.' >= cosd(45)));
end

function [ang, rows, fixed, sym, snapped] = cutGeometry(T, type, req)
%cutGeometry Ordered rows of one full-circle cut, snapped to the nearest sampled plane (physical θ).
if type == "Phi"                                                            % fixed θ, sweep φ
    th = unique(T.Theta); [d, i] = min(abs(th - req)); fixed = th(i);
    rows = find(abs(T.Theta - fixed) < 1e-9); [ang, o] = sort(T.Phi(rows)); rows = rows(o); sym = 'θ';
else                                                                        % fixed φ, sweep θ through both half-planes
    wrapped = mod(T.Phi, 360); ph = unique(wrapped); [d, i] = min(abs(mod(ph - req + 180, 360) - 180)); fixed = ph(i);
    [~, j] = min(abs(mod(ph - fixed, 360) - 180));
    a = find(abs(wrapped - fixed) < 1e-9); b = find(abs(wrapped - ph(j)) < 1e-9 & abs(T.Theta - 180) > 1e-9);
    [~, oa] = sort(T.Theta(a)); [~, ob] = sort(T.Theta(b), 'descend'); a = a(oa); b = b(ob);
    rows = [a; b]; ang = [T.Theta(a); 360 - T.Theta(b)]; sym = 'φ';
end
snapped = d > 1e-9;
end

function [bw, lo, hi] = calcHPBW(ang, g, pk, pkAng)
%calcHPBW Half-power beamwidth of a circular cut with linear interpolation of both −3 dB crossings.
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(g); ang = ang(ok); g = g(ok); if numel(g) < 3, return; end
if nargin < 4 || isempty(pk) || isempty(pkAng), [pk, i] = max(g); pkAng = ang(i); end
[rel, o] = sort(mod(ang - pkAng + 180, 360) - 180); rg = g(o); half = pk - 3;
L = find(rel < 0 & rg <= half, 1, 'last'); U = find(rel > 0 & rg <= half, 1, 'first');
if isempty(L) || isempty(U) || L + 1 > numel(rg) || U < 2, return; end
gl = rg([L L+1]); gu = rg([U U-1]); if diff(gl) == 0 || diff(gu) == 0, return; end
xl = rel(L) + diff(rel([L L+1]))*(half - gl(1))/diff(gl); xu = rel(U) + diff(rel([U U-1]))*(half - gu(1))/diff(gu);
lo = pkAng + xl; hi = pkAng + xu; bw = xu - xl;
end

function [g, col] = chooseGain(T, requested)
%chooseGain Requested column, else E_Total_dB, else the first data column.
vars = T.Properties.VariableNames; cand = [string(requested), "E_Total_dB"]; hit = find(ismember(cand, string(vars)), 1);
if isempty(hit), col = vars{3}; else, col = char(cand(hit)); end, g = T.(col);
end

function step = gridStep(v)
%gridStep Smallest positive spacing between distinct finite values (NaN when undefined).
d = diff(unique(v(isfinite(v)))); d = d(d > 1e-9); if isempty(d), step = NaN; else, step = min(d); end
end

function s = fmtNum(v, p)
%fmtNum 'n/a' for non-finite values; compact 2-decimal formatting by default, or exactly P decimals.
if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; elseif nargin < 2, s = sprintf('%.10g', round(v, 2) + 0); else, s = sprintf('%.*f', p, v); end
end

function tf = isAR(name)
k = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', ''); tf = k == "ar" || startsWith(k, "ardb") || startsWith(k, "axialratio");
end

function tf = isGenericText(fp), [~, ~, e] = fileparts(fp); tf = any(strcmpi(e, {'.csv', '.txt', '.dat'})); end

function tf = nodeIs(n, kind), tf = isstruct(n.NodeData) && isfield(n.NodeData, 'kind') && strcmp(n.NodeData.kind, kind); end

function setRange(ctrls, value, limits)
%setRange Order-safe Value/Limits update for spinners and range sliders (widen → set value → tighten).
set(ctrls, 'Limits', [-1e9 1e9]); set(ctrls, 'Value', value); set(ctrls, 'Limits', limits);
end

function setTip(h, rows), try, h.DataTipTemplate.DataTipRows = rows; catch, end, end