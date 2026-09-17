classdef APAT_v3_M8_24 < matlab.apps.AppBase %1784-lines %MX %ISSUES: %1. POB DataTips renders/refreshes each time a plot tab is highlighted/selected  %2. When Switching Phi Span, while POB DataTip is enabled, it plots the adjusted POB Datatip to reflect the Phi span, but it also keep the previous POB DataTip (they also remain shown/plotted when reverting back to original Phi span, or when loading a new file/pattern)   %3. DataTip labeling not working on 3d surface Plot (it shows the interactive DatTip box, but it doesn't get labeled/fixed upon clicking)  %4. DataTip Custom Menu not working (nothing happens when clicking on the Context Menu! It doesn't delete the created/labeled DataTips)  %5. DatTip Custom Context menu triggers warning (MATLAB Workspace showing "Warning: You cannot set 'ContextMenu' property of DataTip")  %6. On Coverage Results Plots, the Interactive DataTip cursor doesn't shows Customized DataTips (However, Query requests DataTips sows Customized DataTips!)  %7. Coverage Threshold Query snaps to nearest Data Point instead of returning requested/query point!  %8. When user change Coverage Cone coordinate while Conical Coverage Orientation drop-down is on Auto, it computes Auto Coverage instead of the adjusted Cone values/coordinates!
    %APAT_V3_M8  Antenna Pattern Analyzer Tool — v3 Milestone 8 (concise canonical-pipeline rewrite of M7.110_5).
    %
    %   One data path:   readPattern (I/O) → normalizePattern → [resampleCanonical] → calcPattern → app.pat
    %   app.pat is ONE canonical table (Theta 0..180°, Phi 0..360° incl. the closing seam) holding every derived
    %   quantity.  Display conventions (signed φ, elevation θ) are applied only at the presentation boundary
    %   (axes ticks, data tips, Results table, exports); every physical computation uses canonical angles.
    %
    %   Sections:  properties · lifecycle · load/process pipeline · view model · full-pattern renderers ·
    %              cut plots · colour ranges & annotations · tables/metadata/exports · coverage tab ·
    %              UI construction · local I/O readers · local numerical core · self-test.
    %
    %   Requires MATLAB R2023a or later (thetaregion/xregion, dropdown styles). No toolboxes.

    properties (Access = public)
        UIFigure matlab.ui.Figure
        TabGroup matlab.ui.container.TabGroup
        MainTab  matlab.ui.container.Tab
        CovTab   matlab.ui.container.Tab
        ui  struct = struct()   % Main-tab widgets (fields documented in buildMainTab)
        cov struct = struct()   % Coverage-tab widgets (fields documented in buildCoverageTab)
        plots                   % 1×5 struct: full-pattern tabs (kind, view, tab, axes, slider, minSpin, maxSpin)
    end

    properties (Access = private)
        % Source & canonical data
        src struct = struct()          % reader output: raw, blocks, freqs, meta
        filePath char = ''             % active Main-tab file
        std table                      % canonical primitive block (fields or gain columns) after normalizePattern
        pat table                      % processed canonical pattern (all derived columns) at the displayed step
        autoBasis logical = true       % cut co/cross basis follows the detected polarization until the user overrides it
        useOneDeg logical = false      % 1° resampling requested through the STEP dropdown
        % Derived view state
        grid struct = struct()         % memoized grid topology, component matrices and unit-sphere geometry
        omega double = []              % solid-angle weight per canonical row
        peak struct = struct()         % peak of the selected component (resolvePeak)
        axisIndex double = 1           % boresight principal axis (index into Axes)
        metrics struct = struct()      % calcMetrics result (total gain)
        pol struct = struct()          % polarization summary from calcPattern (label, basis, pairs)
        cutFixed double = 0            % physical fixed angle of the active cut (θ for phi cuts, φ for theta cuts)
        gainLim double = [-40 10]      % non-AR colour range, preserved across component switches
        ctrLim double = [-40 10]       % active full-pattern colour range
        cutLim double = [-40 10]       % cut-plot magnitude range
        % Coverage
        covRunID double = 0
        covPresetKey string = ""       % pattern|component key of the last automatic threshold preset
        covXInit logical = false       % first plotted result establishes the X baseline
        % Infrastructure
        statusTimer                    % one reusable single-shot timer for transient status messages
        busyDlg = []                   % active (cancelable) progress dialog
        defaults cell = {}             % startup parameter values (Reset Params)
        isClosing logical = false
    end

    properties (Constant)
        Release = 'APAT v3 M8'
        Axes = struct('labels', {{'+Z', '-Z', '+X', '-X', '+Y', '-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        PeakPercentile = 99.99         % isolated-spike policy: P99.99 + PeakExcessDB
        PeakExcessDB = 6
        Components = ["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "AR_dB", "Gain_PolCorrected_dB"]
        ComponentLabels = ["Total Gain", "Etheta Gain", "Ephi Gain", "RHCP Gain", "LHCP Gain", "Axial Ratio", "Polarized Gain"]
        HiddenColumns = {'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'}
        TextFormats = {'1: Gain Pattern', 'gain'; '2: Etheta/Ephi — dB magnitude, phase', 'linear_magphase'; ...
            '3: Etheta/Ephi — real, imaginary', 'linear_reim'; '4: POL1=RCP, POL2=LCP — dB magnitude, phase', 'rcp_lcp_magphase'; ...
            '5: POL1=LCP, POL2=RCP — dB magnitude, phase', 'lcp_rcp_magphase'; '6: POL1=RCP, POL2=LCP — real, imaginary', 'rcp_lcp_reim'; ...
            '7: POL1=LCP, POL2=RCP — real, imaginary', 'lcp_rcp_reim'}
    end

    %% ------------------------------------------------------------------------------------------------ lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_24
            app.buildUI();
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @startup);
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true;
            if ~isempty(app.statusTimer) && isvalid(app.statusTimer), stop(app.statusTimer); delete(app.statusTimer); end
            if ~isempty(app.busyDlg) && isvalid(app.busyDlg), delete(app.busyDlg); end
            if isvalid(app.UIFigure), delete(app.UIFigure); end
        end
    end

    methods (Access = private)
        function startup(app)
            app.statusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, 'TimerFcn', @(~, ~) app.restoreStatus());
            u = app.ui;
            app.defaults = {u.loss.Value, u.rxPol.Value, u.rw.Value, u.pt.Value, u.ptUnit.Value, u.dist.Value, u.distUnit.Value};
            app.setCoverageUI();
        end

        function setStatus(app, label, message, transient)
            % Transient messages revert to the last persistent message after 3 s (one shared timer).
            if app.isClosing || ~isvalid(label), return; end
            if nargin < 4, transient = false; end
            stop(app.statusTimer);
            label.Text = char(message);
            if transient, start(app.statusTimer); else, label.UserData = char(message); end
        end

        function restoreStatus(app)
            if app.isClosing, return; end
            for lbl = [app.ui.status, app.cov.status]
                if ischar(lbl.UserData), lbl.Text = lbl.UserData; end
            end
        end

        function f = guard(app, fn)
            % Wrap a callback so errors become a dialog (and user cancellation a status line) instead of a console trace.
            f = @(src, event) app.protect(fn, src, event);
        end

        function protect(app, fn, src, event)
            try
                fn(src, event);
            catch ME
                if app.isClosing, return; end
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.setStatus(app.ui.status, 'Operation cancelled.', true); return; end
                where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
                uialert(app.UIFigure, [ME.message where], 'APAT Error', 'Icon', 'error');
            end
        end

        function dlg = busy(app, title, message, cancelable)
            dlg = uiprogressdlg(app.UIFigure, 'Title', title, 'Message', message, 'Indeterminate', 'on', 'Cancelable', cancelable);
            app.busyDlg = dlg; drawnow;
        end

        function checkCancelled(app)
            d = app.busyDlg;
            if ~isempty(d) && isvalid(d) && d.CancelRequested, error('APAT:Cancelled', 'Cancelled by user.'); end
        end

        function fp = browse(~, prompt)
            fp = '';
            [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage files'; '*.*', 'All files'}, prompt);
            if ~isequal(f, 0), fp = fullfile(p, f); end
        end

        function n = fileName(app), [~, b, e] = fileparts(app.filePath); n = [b e]; end
        function b = baseName(app), [~, b] = fileparts(app.filePath); end
        function d = folder(app), d = fileparts(app.filePath); if isempty(d), d = pwd; end, end
    end

    %% ------------------------------------------------------------------------------------- load / process pipeline
    methods (Access = private)
        function onLoad(app)
            fp = strtrim(app.ui.pathField.Value);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.filePath)
                fp = app.browse('Select an antenna pattern file');
                if isempty(fp), return; end
            end
            dlg = app.busy('Loading Data', 'Reading file...', true); cleaner = onCleanup(@() close(dlg)); %#ok<NASGU>
            source = app.readSource(fp, app.ui.fmtDrop, app.ui.fmtGroup);
            app.checkCancelled();
            if source.meta.isCoverage      % coverage results go to the Coverage tab without touching Main state
                app.TabGroup.SelectedTab = app.CovTab; app.cov.pathField.Value = fp;
                app.addResultsNode(fp, source.raw);
                return
            end
            app.ui.pathField.Value = fp; app.filePath = fp; app.src = source;
            [app.autoBasis, app.useOneDeg] = deal(true, false);
            app.showInput(source.raw);
            n = numel(source.blocks); f = source.freqs(:);
            items = compose('Pattern %d: %.4g GHz', (1:n)', f / 1e9); items(isnan(f)) = compose('Pattern %d', find(isnan(f)));
            [app.ui.ffdDrop.Items, app.ui.ffdDrop.Value] = deal(items, items{1});
            set(app.ui.ffdGroup, 'Visible', source.meta.isDep);
            app.selectBlock(1);
        end

        function source = readSource(~, fp, fmtDrop, fmtGroup)
            % Generic text files start as "gain" and expose the format selector; other formats are self-describing.
            source = readPattern(fp, 'gain');
            isText = isGenericText(fp) && ~source.meta.isCoverage;
            if isText, fmtDrop.Value = 'gain'; end
            set(fmtGroup, 'Visible', isText);
        end

        function showInput(app, raw)
            app.ui.tableIn.Data = raw; app.ui.tableIn.ColumnName = raw.Properties.VariableNames;
        end

        function selectBlock(app, k)
            app.std = normalizePattern(app.src.blocks{k});
            if app.src.meta.isDep, app.showInput(app.src.blocks{k}); end
            app.process(true);
        end

        function process(app, fresh)
            % Canonical pipeline: optional 1° resampling of PRIMITIVE data → derive all quantities → refresh the view.
            S = app.std; meta = app.src.meta;
            steps = [gridStep(S.Theta), gridStep(S.Phi)]; steps(isnan(steps)) = 1;
            nonCanonical = any(abs(steps - 1) > 1e-9);
            app.ui.stepDrop.Items = {sprintf('STEP: %g°', max(steps)), 'STEP: 1°'};
            app.ui.stepDrop.Value = app.ui.stepDrop.Items{1 + (app.useOneDeg && nonCanonical)};
            set(app.ui.stepDrop, 'Visible', nonCanonical, 'Enable', nonCanonical);
            if app.useOneDeg && nonCanonical
                if all(steps < 1)      % sub-degree grids: keep the exact integer-degree samples instead of interpolating
                    S = S(abs(S.Theta - round(S.Theta)) < 1e-9 & abs(S.Phi - round(S.Phi)) < 1e-9, :);
                else
                    S = resampleCanonical(S, 1);
                end
            end
            app.checkCancelled();
            [app.pat, app.pol] = calcPattern(S, app.getParams(), meta.isGainOnly);
            if app.autoBasis && ~meta.isGainOnly, app.ui.cutBasis.Value = app.pol.basis; end
            app.grid = struct(); app.omega = [];
            app.fillComponents(app.ui.component, app.pat, meta.isGainOnly, app.ui.component.Value);
            app.updateView(fresh);
            app.showLoadedState();
        end

        function updateView(app, fresh)
            % Derived quantities: selected-component peak (POB) plus total-gain orientation & metrics; then redraw all.
            T = app.pat; comp = app.comp(); gcol = gainColumn(T);
            if isempty(app.omega), app.omega = solidWeights(T.Theta, T.Phi); end
            app.peak = resolvePeak(T.(comp), app.PeakPercentile, app.PeakExcessDB);
            gpk = app.peak; if ~strcmp(comp, gcol), gpk = resolvePeak(T.(gcol), app.PeakPercentile, app.PeakExcessDB); end
            app.axisIndex = boresightAxis(T, app.omega, T.(gcol), gpk, app.Axes);
            app.metrics = calcMetrics(T, app.omega, T.(gcol), gpk, app.axisIndex, app.Axes);
            if fresh, app.gainLim = peakWindow(T.(gcol), app.PeakPercentile, app.PeakExcessDB); end
            app.applyColorRange(app.themeLimits(), fresh);
            app.checkCancelled();
            app.updateTables(); app.updateMetadata();
            if fresh, app.applyPlaneCut(); else, app.updateCutControl(); end
            app.plotCut(); app.checkCancelled();
            app.renderAll();
        end

        function showLoadedState(app)
            u = app.ui; hasE = ~app.src.meta.isGainOnly;
            set([u.panelPlots, u.panelCut, u.panelCtrl, u.dataTabs, u.outFilter, u.exportBtn, u.covBtn], 'Visible', 'on');
            set([u.uanBtn, u.cutBoxGrid], 'Visible', hasE); u.cutBasis.Enable = hasE;
            polText = ''; if hasE, polText = sprintf(' | Polarization <b>%s</b>', app.pol.label); end
            app.setStatus(u.status, sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>θ=%s°, φ=%s°</b>)%s', app.fileName(), ...
                fmtNum(app.peak.value, 2), fmtNum(app.peakTheta()), fmtNum(app.peakPhi()), polText), false);
        end

        function onProcess(app)
            assert(~isempty(app.std), 'No file loaded. Load a pattern first.');
            dlg = app.busy('Processing', 'Re-processing pattern...', false); cleaner = onCleanup(@() close(dlg)); %#ok<NASGU>
            if isGenericText(app.filePath)   % generic text: re-read with the selected column interpretation
                source = readPattern(app.filePath, app.ui.fmtDrop.Value);
                assert(~source.meta.isCoverage, 'The selected format identifies a coverage-results file.');
                app.src = source; app.std = normalizePattern(source.blocks{1}); app.showInput(source.raw);
            end
            app.process(true);
            app.setStatus(app.ui.status, ['Re-processed <b>' app.fileName() '</b> with the current parameters ✅'], true);
        end

        function onFormatChanged(app)
            if isGenericText(app.filePath) && strcmp(strtrim(app.ui.pathField.Value), app.filePath), app.autoBasis = true; app.onProcess(); end
        end

        function onBlockChanged(app)
            k = find(strcmp(app.ui.ffdDrop.Items, app.ui.ffdDrop.Value), 1);
            app.autoBasis = true; app.selectBlock(k);
            app.setStatus(app.ui.status, sprintf('Switched to FFD block %d (%s).', k, app.ui.ffdDrop.Value), true);
        end

        function onStepChanged(app, src)
            app.useOneDeg = strcmp(src.Value, 'STEP: 1°');
            dlg = app.busy('Processing', 'Resampling pattern...', false); cleaner = onCleanup(@() close(dlg)); %#ok<NASGU>
            app.process(false);
        end

        function onComponentChanged(app)
            if ~isempty(app.pat), app.updateView(false); end
        end

        function onSpanChanged(app)
            % Display convention only: no physics changes, so just re-present tables, cut and plots.
            if isempty(app.pat), return; end
            if strcmp(app.ui.cutType.Value, 'Phi'), v = app.dispTheta(app.cutFixed); else, v = app.dispPhi(app.cutFixed); end
            app.updateCutControl(v); app.updateTables(); app.plotCut(); app.renderAll();
        end

        function p = getParams(app)
            u = app.ui;
            p = struct('lossDB', u.loss.Value, 'rxMode', string(u.rxPol.Value), 'rxArDB', u.rw.Value, 'ptDBW', u.pt.Value, 'rM', max(u.dist.Value, 1e-12));
            switch u.ptUnit.Value, case 'dBm', p.ptDBW = p.ptDBW - 30; case 'Watts', p.ptDBW = 10 * log10(max(p.ptDBW, eps)); end
            if strcmp(u.distUnit.Value, 'km'), p.rM = 1000 * p.rM; end
        end

        function resetParams(app)
            d = app.defaults; u = app.ui;
            [u.loss.Value, u.rxPol.Value, u.rw.Value, u.pt.Value, u.ptUnit.Value, u.dist.Value, u.distUnit.Value] = deal(d{:});
            if ~isempty(app.std), app.onProcess(); end
        end
    end

    %% --------------------------------------------------------------------------------------------------- view model
    methods (Access = private)
        function c = comp(app), c = app.ui.component.Value; end

        function s = compLabel(app)
            i = strcmp(app.ui.component.ItemsData, app.comp()); s = string(app.comp());
            if any(i), s = string(app.ui.component.Items{i}); end
        end

        function fillComponents(app, dd, T, isGainOnly, prev)
            % Component dropdown from the columns actually present; keep PREV (else Total Gain) when available.
            names = string(T.Properties.VariableNames(3:end));
            if isGainOnly, [cols, labels] = deal(names);
            else, has = ismember(app.Components, names); cols = app.Components(has); labels = app.ComponentLabels(has); end
            [dd.Items, dd.ItemsData] = deal(cellstr(labels), cellstr(cols));
            dd.Value = char(preferred(string(prev), cols));
        end

        function t = peakTheta(app), t = app.pat.Theta(app.peak.index); end
        function p = peakPhi(app), p = app.pat.Phi(app.peak.index); end
        function tf = signedPhi(app), tf = strcmp(app.ui.phiSpan.Value, '-180° to 180°'); end
        function tf = elevation(app), tf = strcmp(app.ui.thetaSpan.Value, '-90° to 90°'); end
        function t = dispTheta(app, theta), t = theta; if app.elevation(), t = 90 - theta; end, end
        function p = dispPhi(app, phi), p = phi; if app.signedPhi(), p(p > 180) = p(p > 180) - 360; end, end
        function a = wrapAngle(app, a), if app.signedPhi(), a = mod(a + 180, 360) - 180; else, a = mod(a, 360); end, end

        function [phiLim, thetaLim, yDir] = displayLimits(app)
            phiLim = [0 360]; thetaLim = [0 180]; yDir = 'reverse';
            if app.signedPhi(), phiLim = [-180 180]; end
            if app.elevation(), thetaLim = [-90 90]; yDir = 'normal'; end
        end

        function [thetaName, phiName] = angleNames(app)
            thetaName = "Theta"; if app.elevation(), thetaName = "Elevation"; end; phiName = "Phi";
        end

        function [theta, phi, C] = gridOf(app, column)
            % Canonical theta × phi matrix of one column (NaN where a direction is missing); memoized per column.
            g = app.grid; T = app.pat;
            if ~isfield(g, 'theta')
                [g.theta, ~, it] = unique(T.Theta); [g.phi, ~, ip] = unique(T.Phi);
                g.index = sub2ind([numel(g.theta), numel(g.phi)], it, ip); g.data = struct();
            end
            key = matlab.lang.makeValidName(column);
            if ~isfield(g.data, key), C = nan(numel(g.theta), numel(g.phi)); C(g.index) = T.(column); g.data.(key) = C; end
            [theta, phi, C] = deal(g.theta, g.phi, g.data.(key)); app.grid = g;
        end

        function G = geometry(app)
            % Canonical angle grids and unit-sphere coordinates (memoized with the grid topology).
            if ~isfield(app.grid, 'x')
                [theta, phi] = app.gridOf(app.comp()); g = app.grid;
                [g.P, g.Th] = meshgrid(phi, theta);
                g.x = sind(g.Th) .* cosd(g.P); g.y = sind(g.Th) .* sind(g.P); g.z = cosd(g.Th); app.grid = g;
            end
            G = app.grid;
        end

        function [theta, phi, C] = displayGrid(app, theta, phi, C)
            % Reorder the canonical grid into the display convention (monotonic axes, closed φ seam).
            if app.signedPhi()
                keep = phi < 360; [phi, order] = sort(app.dispPhi(phi(keep))); C = C(:, keep); C = C(:, order);
                if phi(end) == 180, phi = [-180; phi]; C = [C(:, end), C]; end
            end
            if app.elevation(), theta = flipud(90 - theta); C = flipud(C); end
        end

        function D = displayTable(app, T)
            % Canonical → display-convention copy for the Results table (sorted for readability).
            D = T;
            if app.signedPhi(), D(D.Phi == 360, :) = []; D.Phi(D.Phi > 180) = D.Phi(D.Phi > 180) - 360; end
            if app.elevation(), D.Theta = 90 - D.Theta; end
            D = sortrows(D, {'Phi', 'Theta'});
        end

        function lim = themeLimits(app)
            if isAR(app.comp()), lim = [-30 30]; else, lim = app.gainLim; end
        end
    end

    %% --------------------------------------------------------------------------------------- full-pattern renderers
    methods (Access = private)
        function renderAll(app)
            for p = app.plots, app.checkCancelled(); app.render(p); end
            app.syncTips(); drawnow limitrate
        end

        function render(app, p)
            switch p.kind
                case "contour",  app.drawContour(p.axes);
                case "circular", app.drawFisheye(p.axes);
                case "rect3D",   app.drawRect3D(p.axes);
                otherwise,       app.drawSphere(p.axes, p.kind);
            end
        end

        function applyTheme(app, ax)
            % Colour scale + map for the selected component; colorbar ticks follow the step spinner.
            lim = app.themeLimits();
            if isAR(app.comp()), map = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); else, map = jet(256); end
            set(ax, 'CLim', lim); colormap(ax, map);
            app.setColorbarTicks(colorbar(ax), lim);
            set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', ax.ContextMenu);
        end

        function setTips(app, s, Th, P, C)
            % Common DataTip template (display-convention angles + component value) for a surface.
            [tn, pn] = app.angleNames();
            rows = [dataTipTextRow(tn, Th, '%.3g°'); dataTipTextRow(pn, P, '%.3g°'); dataTipTextRow(replace(app.compLabel(), "_", "\_"), C, '%.3g dB')];
            try
                s.DataTipTemplate.DataTipRows = rows;
            catch
                try, delete(datatip(s, 'DataIndex', 1)); s.DataTipTemplate.DataTipRows = rows; catch, end   % template materializes lazily
            end
        end

        function markPeak(app, ax, x, y, z)
            % Peak-of-beam marker + pinned tip; tagged so the checkbox toggles visibility without redrawing.
            if ~isfinite(app.peak.value), return; end
            [tn, pn] = app.angleNames();
            rows = [dataTipTextRow(tn, app.dispTheta(app.peakTheta()), '%.4g°'); dataTipTextRow(pn, app.dispPhi(app.peakPhi()), '%.4g°'); ...
                dataTipTextRow(replace(app.compLabel(), "_", "\_"), app.peak.value, '%.4g dB')];
            try
                held = ishold(ax); hold(ax, 'on');
                if isempty(z), m = polarplot(ax, x, y, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5);
                else, m = plot3(ax, x, y, z, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'Clipping', 'off'); end
                if ~held, hold(ax, 'off'); end
                set(m, 'HandleVisibility', 'off', 'Tag', 'APAT_POB'); m.DataTipTemplate.DataTipRows = rows;
                tip = datatip(m, 'DataIndex', 1, 'Tag', 'APAT_POB', 'FontSize', 9);
                set([m, tip], 'Visible', app.ui.pobBox.Value);
            catch
            end
        end

        function drawContour(app, ax)
            [theta, phi, C] = app.gridOf(app.comp()); [tD, pD, CD] = app.displayGrid(theta, phi, C);
            cla(ax);
            s = pcolor(ax, pD, tD, CD); set(s, 'FaceColor', 'interp', 'LineStyle', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax);
            [phiLim, thetaLim, yDir] = app.displayLimits(); [tn, pn] = app.angleNames();
            set(ax, 'XLim', phiLim, 'YLim', thetaLim, 'YDir', yDir, 'XTick', phiLim(1):30:phiLim(2), 'YTick', thetaLim(1):15:thetaLim(2), ...
                'Box', 'on', 'Layer', 'top', 'DataAspectRatio', [1 1 1]);
            xlabel(ax, pn + " (degree)"); ylabel(ax, tn + " (degree)"); title(ax, app.compLabel(), 'Interpreter', 'none');
            [P, Th] = meshgrid(pD, tD); app.setTips(s, Th, P, CD);
            app.markPeak(ax, app.dispPhi(app.peakPhi()), app.dispTheta(app.peakTheta()), 0);
        end

        function drawFisheye(app, ax)
            % Circular contour: radius = physical θ, angle = φ (ticks relabelled for the display convention).
            [~, ~, C] = app.gridOf(app.comp()); G = app.geometry();
            cla(ax);
            s = surface(ax, deg2rad(G.P), G.Th, zeros(size(C)), C, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax);
            set(ax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', app.dispPhi(0:30:330)), ...
                'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', app.dispTheta(0:30:180)));
            title(ax, sprintf('%s  |  r = θ, angle = φ', app.compLabel()), 'Interpreter', 'none', 'FontSize', 9);
            app.setTips(s, app.dispTheta(G.Th), app.dispPhi(G.P), C);
            app.markPeak(ax, deg2rad(app.peakPhi()), app.peakTheta(), []);
        end

        function drawSphere(app, ax, kind)
            % 3-D spherical (unit sphere coloured by value) or 3-D polar (radius = normalized value) surface.
            [~, ~, C] = app.gridOf(app.comp()); G = app.geometry(); lim = app.themeLimits();
            r = ones(size(C)); if kind == "polar3D", r = min(max(C - lim(1), 0) / diff(lim), 1); r(~isfinite(r)) = 0; end
            cla(ax); hold(ax, 'on');
            s = surf(ax, r .* G.x, r .* G.y, r .* G.z, C, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax);
            set(ax, 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'Projection', 'orthographic');
            axis(ax, 'off'); app.drawAxesTriad(ax); app.applyView(ax, [135 25]);
            title(ax, sprintf('%s  |  θ: %s  |  φ: %s', app.compLabel(), app.ui.thetaSpan.Value, app.ui.phiSpan.Value), 'Interpreter', 'none');
            app.setTips(s, app.dispTheta(G.Th), app.dispPhi(G.P), C);
            [~, k] = min(abs(G.Th(:) - app.peakTheta()) + abs(G.P(:) - app.peakPhi()));
            app.markPeak(ax, r(k) * G.x(k), r(k) * G.y(k), r(k) * G.z(k));
            if app.ui.overlay.Value, app.overlayCut(ax, kind); end
            hold(ax, 'off');
        end

        function drawRect3D(app, ax)
            [theta, phi, C] = app.gridOf(app.comp()); [tD, pD, CD] = app.displayGrid(theta, phi, C);
            [P, Th] = meshgrid(pD, tD); lim = app.themeLimits();
            cla(ax);
            s = surf(ax, P, Th, CD, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax);
            [phiLim, thetaLim, yDir] = app.displayLimits(); [tn, pn] = app.angleNames();
            set(ax, 'XLim', phiLim, 'YLim', thetaLim, 'YDir', yDir, 'ZLim', lim, 'XTick', phiLim(1):60:phiLim(2), 'YTick', thetaLim(1):30:thetaLim(2), 'Box', 'on');
            ticks = app.tickVector(lim); if ~isempty(ticks), ax.ZTick = ticks; end
            xlabel(ax, pn + " (degree)"); ylabel(ax, tn + " (degree)"); zlabel(ax, app.compLabel() + " (dB)", 'Interpreter', 'none');
            grid(ax, 'on'); app.applyView(ax, [-35 35]); title(ax, app.compLabel(), 'Interpreter', 'none');
            app.setTips(s, Th, P, CD);
            app.markPeak(ax, app.dispPhi(app.peakPhi()), app.dispTheta(app.peakTheta()), app.peak.value);
        end

        function drawAxesTriad(~, ax)
            % Principal axes (X red, Y green, Z blue) with their spherical coordinates.
            colors = [0.85 0.1 0.1; 0.1 0.6 0.1; 0.1 0.2 0.9]; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            for k = 1:3
                d = 1.35 * ((1:3) == k);
                quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors(k, :), 'LineWidth', 1.6, 'MaxHeadSize', 0.25, 'HandleVisibility', 'off');
                text(ax, 1.12 * d(1), 1.12 * d(2), 1.12 * d(3), labels{k}, 'Color', colors(k, :), 'FontWeight', 'bold');
            end
        end

        function applyView(app, ax, default)
            switch app.ui.view3D.Value
                case 'top',    v = [0 90];  up = [0 1 0];
                case 'bottom', v = [0 -90]; up = [0 1 0];
                case 'right',  v = [90 0];  up = [0 0 1];
                case 'left',   v = [-90 0]; up = [0 0 1];
                case 'front',  v = [0 0];   up = [0 0 1];
                case 'back',   v = [180 0]; up = [0 0 1];
                otherwise,     v = default; up = [0 0 1];
            end
            view(ax, v); camup(ax, up);
        end

        function onViewChanged(app)
            if isempty(app.pat), return; end
            for p = app.plots(3:5), app.applyView(p.axes, p.view); end
            drawnow limitrate
        end

        function overlayCut(app, ax, kind)
            % Black great-circle trace of the active cut on the sphere / polar surface (same radius law as the surface).
            delete(findall(ax, 'Tag', 'APAT_CutOverlay'));
            [~, Y, ~, ~, theta, phi] = app.cutData();
            r = 1.02 * ones(size(theta));
            if kind == "polar3D", lim = app.themeLimits(); r = 1.01 * min(max(Y(:, 1) - lim(1), 0) / diff(lim), 1); end
            plot3(ax, r .* sind(theta) .* cosd(phi), r .* sind(theta) .* sind(phi), r .* cosd(theta), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay', 'HandleVisibility', 'off');
        end

        function onOverlayChanged(app)
            if isempty(app.pat), return; end
            for p = app.plots(3:4)
                if app.ui.overlay.Value, hold(p.axes, 'on'); app.overlayCut(p.axes, p.kind); hold(p.axes, 'off');
                else, delete(findall(p.axes, 'Tag', 'APAT_CutOverlay')); end
            end
        end
    end

    %% ---------------------------------------------------------------------------------------------------- cut plots
    methods (Access = private)
        function [type, value] = planeCut(app, isE)
            % E-plane: θ cut through the boresight axis' φ.  H-plane: the orthogonal principal cut.
            a = app.Axes; k = app.axisIndex; type = 'Theta'; value = a.phi(k);
            if ~isE, value = 90; if a.theta(k) == 90, type = 'Phi'; end, end
        end

        function applyPlaneCut(app)
            [type, value] = app.planeCut(startsWith(app.ui.ehSwitch.Value, 'E'));
            app.ui.cutType.Value = type;
            if strcmp(type, 'Phi'), value = app.dispTheta(value); else, value = app.dispPhi(value); end
            app.updateCutControl(value);
        end

        function onPlaneSwitch(app)
            if isempty(app.pat), return; end
            app.applyPlaneCut(); app.onCutChanged();
        end

        function updateCutControl(app, requested)
            % Cut-value spinner in display units (fixed θ for phi cuts, fixed φ for theta cuts), snapped to the grid.
            s = app.ui.cutValue; if nargin < 2, requested = s.Value; end
            if strcmp(app.ui.cutType.Value, 'Phi'), v = unique(app.dispTheta(app.pat.Theta)); else, v = unique(app.dispPhi(app.pat.Phi(app.pat.Phi < 360))); end
            [~, k] = min(abs(v - requested)); lim = [min(v), max(v)]; if diff(lim) == 0, lim(2) = lim(1) + 1; end
            s.Limits = [-1e4 1e4]; s.Value = v(k); s.Limits = lim; s.Step = max(gridStep(v), 0.1);
        end

        function onCutChanged(app, src)
            if nargin > 1 && src == app.ui.cutType, app.updateCutControl(); end
            if nargin > 1 && src == app.ui.cutBasis, app.autoBasis = false; if ~isempty(app.pat), app.updateMetadata(); end, end
            app.ui.hpbwBoundsBox.Visible = app.ui.hpbwBtn.Value;
            if ~app.ui.hpbwBtn.Value, app.ui.hpbwBoundsBox.Value = false; end
            app.plotCut(); app.onOverlayChanged();
        end

        function [cols, idx] = cutColumns(app)
            % Total plus the selected field pair; IDX gives stable colours (1 = Total, 2/3 = pair).
            if app.src.meta.isGainOnly, cols = {app.comp()}; idx = 1; return; end
            if strcmp(app.ui.cutBasis.Value, 'Linear'), pair = ["E_TH", "E_PH"]; else, pair = ["E_RCP", "E_LCP"]; end
            set(app.ui.cutBoxes(2:3), {'Text'}, cellstr(pair(:)));
            sel = [app.ui.cutBoxes.Value]; if ~any(sel), sel(1) = true; end
            idx = find(sel); all3 = cellstr(["E_Total_dB", pair + "_dB"]); cols = all3(idx);
        end

        function [ang, Y, names, ttl, theta, phi, idx] = cutData(app)
            % Active cut as one closed great circle in display angles (rows come from the canonical table).
            T = app.pat; [cols, idx] = app.cutColumns(); type = app.ui.cutType.Value; req = app.ui.cutValue.Value;
            if strcmp(type, 'Phi') && app.elevation(), req = 90 - req; end
            if strcmp(type, 'Theta'), req = mod(req, 360); end
            [rows, ang, fixed] = cutRows(T, type, req); app.cutFixed = fixed;
            Y = T{rows, cols}; theta = T.Theta(rows); phi = T.Phi(rows);
            if app.signedPhi()
                keep = ang < 360; [ang, Y, theta, phi] = deal(ang(keep), Y(keep, :), theta(keep), phi(keep));
                ang(ang > 180) = ang(ang > 180) - 360; [ang, o] = sort(ang); [Y, theta, phi] = deal(Y(o, :), theta(o), phi(o));
                if ang(end) == 180, ang = [-180; ang]; Y = [Y(end, :); Y]; theta = [theta(end); theta]; phi = [phi(end); phi]; end
            elseif ang(end) < 360
                ang(end + 1) = 360; Y(end + 1, :) = Y(1, :); theta(end + 1) = theta(1); phi(end + 1) = phi(1);
            end
            names = replace(string(cols), "_", "\_");
            sym = 'θ'; if strcmp(type, 'Theta'), sym = 'φ'; end
            ttl = sprintf('%s cut @ %s = %g°', type, sym, fixed);
            if app.src.meta.isGainOnly, ttl = sprintf('%s  |  %s', app.compLabel(), ttl); end
        end

        function plotCut(app)
            if isempty(app.pat), return; end
            [ang, Y, names, ttl, ~, ~, idx] = app.cutData(); u = app.ui; pax = u.polarCut; rax = u.rectCut; lim = app.cutLim;
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on');
            pl = polarplot(pax, deg2rad(ang), max(Y, lim(1)), 'LineWidth', 1.4);   % clamp: no reflection below the inner RLim
            rl = plot(rax, ang, Y, 'LineWidth', 1.4);
            colors = rax.ColorOrder(idx, :); set(pl, {'Color'}, num2cell(colors, 2)); set(rl, {'Color'}, num2cell(colors, 2));
            for k = 1:numel(pl)
                rows = [dataTipTextRow("Angle", ang, '%.3g°'); dataTipTextRow("Magnitude", Y(:, k), '%.3g dB')];
                pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            xLim = app.displayLimits();
            set(pax, 'ThetaDir', 'clockwise', 'ThetaZeroLocation', 'top', 'RLim', lim, 'RTick', lim(1):5:lim(2), 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', app.dispPhi(0:30:330)));
            set(rax, 'YLim', lim, 'XLim', xLim, 'XTick', xLim(1):30:xLim(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, [u.cutType.Value ' (degree)']); ylabel(rax, 'Magnitude (dB)');
            title(pax, ttl, 'Interpreter', 'none'); title(rax, ttl, 'Interpreter', 'none');
            % Peak of the plotted cut (first line) and optional HPBW shading / interpolated −3 dB bounds.
            [pk, ki] = max(Y(:, 1), [], 'omitnan'); u.hpbwLabel.Text = '';
            if isfinite(pk)
                app.markCutPoint(pax, rax, ang(ki), pk, 'APAT_POB', {"Angle", "Magnitude"});
                if u.hpbwBtn.Value
                    [bw, lo, hi] = calcHPBW(ang, Y(:, 1));
                    if isfinite(bw)
                        lo = app.wrapAngle(lo); hi = app.wrapAngle(hi);
                        u.hpbwLabel.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, lo, hi);
                        if lo <= hi, reg = [lo hi]; else, reg = [xLim(1) hi; lo xLim(2)]; end
                        thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                        xregion(rax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                        for b = [lo hi], app.markCutPoint(pax, rax, b, pk - 3, 'APAT_HPBW', {"HPBW bound", "Gain"}); end
                    end
                end
            end
            legend(pax, pl, names, 'Location', 'southoutside', 'Orientation', 'horizontal');
            legend(rax, rl, names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off');
            app.syncTips();
        end

        function markCutPoint(app, pax, rax, angle, value, tag, labels)
            % Marker + pinned tip on both cut axes; visibility is driven by the matching checkbox through syncTips.
            rows = [dataTipTextRow(labels{1}, angle, '%.2f°'); dataTipTextRow(labels{2}, value, '%.2f dB')];
            color = 'k'; if strcmp(tag, 'APAT_HPBW'), color = '#D95319'; end
            hs = [polarplot(pax, deg2rad(angle), max(value, app.cutLim(1)), 'o', 'Color', color, 'MarkerFaceColor', color), ...
                plot(rax, angle, value, 'o', 'Color', color, 'MarkerFaceColor', color)];
            for h = hs
                set(h, 'HandleVisibility', 'off', 'Tag', tag); h.DataTipTemplate.DataTipRows = rows;
                try, datatip(h, 'DataIndex', 1, 'Tag', tag, 'FontSize', 9); catch, end
            end
        end

        function exportCut(app)
            if isempty(app.pat), return; end
            [ang, Y, ~, ttl] = app.cutData(); cols = app.cutColumns();
            app.saveTable(array2table([ang, Y], 'VariableNames', [{'Angle_deg'}, cols]), [app.baseName() '_cut.csv'], ['Export Cut (' ttl ')'], {'*.csv'; '*.txt'}, app.ui.status);
        end
    end

    %% ------------------------------------------------------------------------------- colour ranges & annotations
    methods (Access = private)
        function linkRange(~, slider, minSpin, maxSpin, apply)
            % Range slider ⇄ min/max spinners; APPLY(lim) receives every user change.
            slider.ValueChangedFcn = @(s, ~) apply(s.Value);
            minSpin.ValueChangedFcn = @(s, ~) apply([s.Value, maxSpin.Value]);
            maxSpin.ValueChangedFcn = @(s, ~) apply([minSpin.Value, s.Value]);
        end

        function syncRange(~, slider, minSpin, maxSpin, lim)
            % Mirror one [min max] range into a slider (limits padded ±20 dB) and its spinners without firing callbacks.
            slider.Limits = [-250 100]; slider.Value = lim; slider.Limits = [max(-250, lim(1) - 20), min(100, lim(2) + 20)];
            set(minSpin, 'Limits', [-250, lim(2) - 1], 'Value', lim(1));
            set(maxSpin, 'Limits', [lim(1) + 1, 100], 'Value', lim(2));
        end

        function applyColorRange(app, lim, includeCut)
            % One colour scale shared by the five full-pattern plots (AR keeps its fixed ±30 dB scale).
            lim = clampRange(lim); app.ctrLim = lim;
            if ~isAR(app.comp()), app.gainLim = lim; end
            [app.ui.cmin.Value, app.ui.cmax.Value] = deal(lim(1), lim(2));
            for p = app.plots
                app.syncRange(p.slider, p.minSpin, p.maxSpin, lim);
                set(p.axes, 'CLim', lim);
                if p.kind == "rect3D", set(p.axes, 'ZLim', lim); ticks = app.tickVector(lim); if ~isempty(ticks), p.axes.ZTick = ticks; end, end
                app.setColorbarTicks(findall(app.UIFigure, 'Type', 'ColorBar', 'Axes', p.axes), lim);
            end
            if includeCut, app.cutLim = lim; app.syncRange(app.ui.cutSlider, app.ui.cutMin, app.ui.cutMax, lim); end
        end

        function onColorRange(app, lim, includeCut)
            % Slider / spinner / Apply callback: apply the scale and redraw what depends on it.
            app.applyColorRange(lim, includeCut);
            if isempty(app.pat), return; end
            app.render(app.plots(4));                       % 3-D polar radius follows the scale
            if includeCut, app.plotCut(); end
            app.syncTips(); drawnow limitrate
        end

        function onCutRange(app, lim)
            app.cutLim = clampRange(lim); app.syncRange(app.ui.cutSlider, app.ui.cutMin, app.ui.cutMax, app.cutLim);
            if ~isempty(app.pat), app.plotCut(); end
        end

        function ticks = tickVector(app, lim)
            step = app.ui.cstep.Value; ticks = [];
            if ~(step > 0) || diff(lim) <= 0, return; end
            ticks = unique([lim(1), ceil(lim(1) / step) * step:step:lim(2), lim(2)]);
            if numel(ticks) > 60, ticks = []; end
        end

        function setColorbarTicks(app, cb, lim)
            ticks = app.tickVector(lim);
            if ~isempty(cb) && ~isempty(ticks), cb(1).Ticks = ticks; end
        end

        function syncTips(app)
            % Pinned tips live in a figure overlay: show them only when their checkbox is on and their tab is selected.
            for h = findall(app.UIFigure, '-regexp', 'Tag', '^APAT_(POB|HPBW)$')'
                on = app.ui.pobBox.Value; if strcmp(h.Tag, 'APAT_HPBW'), on = app.ui.hpbwBoundsBox.Value; end
                tab = ancestor(h, 'uitab');
                if ~isempty(tab), on = on && isequal(tab.Parent.SelectedTab, tab); end
                h.Visible = on;
            end
        end
    end

    %% ------------------------------------------------------------------------------ tables / metadata / exports
    methods (Access = private)
        function updateTables(app)
            % Results table = display-convention copy of the canonical table, filtered by the column selector.
            T = app.pat; dd = app.ui.outFilter; cols = T.Properties.VariableNames(3:end);
            if ~isequal(regexprep(dd.Items(2:end), '^✓ ', ''), cols)          % schema changed → rebuild the filter
                [dd.Items, dd.ItemsData, dd.Value] = deal([{'--- column filter ---'}, cols], 0:numel(cols), 0);
                dd.UserData = ~ismember(cols, app.HiddenColumns);
                app.styleFilter();
            end
            app.ui.tableOut.Data = app.displayTable(T(:, [true, true, dd.UserData]));
            app.updateParamVisibility();
        end

        function onFilterChanged(app)
            dd = app.ui.outFilter;
            if dd.Value > 0, dd.UserData(dd.Value) = ~dd.UserData(dd.Value); dd.Value = 0; app.styleFilter(); app.updateTables(); end
        end

        function styleFilter(app)
            % Shown columns get a ✓ (bold, green); hidden ones are greyed in the filter dropdown.
            dd = app.ui.outFilter; on = find(dd.UserData) + 1;
            dd.Items = regexprep(dd.Items, '^✓ ', ''); dd.Items(on) = append('✓ ', dd.Items(on));
            removeStyle(dd);
            if ~isempty(on), addStyle(dd, uistyle('FontWeight', 'bold', 'BackgroundColor', [0.8 1 0.8]), 'Item', on); end
            addStyle(dd, uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9]), 'Item', find([true, ~dd.UserData]));
        end

        function updateParamVisibility(app)
            % Show only the parameters that influence a currently displayed Results column.
            cols = string(app.pat.Properties.VariableNames(3:end)); shown = cols(app.ui.outFilter.UserData);
            has = @(names) any(ismember(shown, names));
            set(app.ui.rxGroup, 'Visible', has(["PLF_dB", "Gain_PolCorrected_dB"]));
            set(app.ui.txGroup, 'Visible', has(["EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
            set(app.ui.distGroup, 'Visible', has(["PFD_Wm2", "E_RMS_Vm"]));
            set(app.ui.lossGroup, 'Visible', app.src.meta.isGainOnly || has(["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "Gain_PolCorrected_dB", "EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
        end

        function updateMetadata(app)
            T = app.pat; m = app.metrics; meta = app.src.meta;
            [theta, phi] = deal(unique(T.Theta), unique(T.Phi));
            rows = {'Source format', meta.source; 'File', app.fileName();
                'Samples', sprintf('%d  (θ: %d × φ: %d)', height(T), numel(theta), numel(phi));
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(min(theta)), fmtNum(max(theta)), fmtNum(gridStep(theta)));
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(min(phi)), fmtNum(max(phi)), fmtNum(gridStep(phi)))};
            f = app.src.freqs(isfinite(app.src.freqs));
            if ~isempty(f), rows(end + 1, :) = {'Frequencies', strjoin(compose('%.4g GHz', f(:) / 1e9), ', ')}; end
            if ~meta.isGainOnly
                rows = [rows; {'Polarization', app.pol.label; 'Cut co-pol / cross-pol', char(strjoin(app.pol.pairs.(app.ui.cutBasis.Value), ' / '))}];
            end
            rows = [rows; {
                'Peak gain (POB)', [fmtNum(m.PeakGain_dB) ' dB']; 'POB direction [θ, φ]', sprintf('[%s°, %s°]', fmtNum(m.PeakTheta_deg), fmtNum(m.PeakPhi_deg));
                'Peak policy', sprintf('P%.4g + %g dB max excess (adjusted: %s)', app.PeakPercentile, app.PeakExcessDB, string(app.peak.wasAdjusted));
                'Boresight axis', app.Axes.labels{app.axisIndex};
                'HPBW E-plane / H-plane', sprintf('%s° / %s°', fmtNum(m.HPBW_EPlane_deg), fmtNum(m.HPBW_HPlane_deg));
                'Front-to-back', [fmtNum(m.FrontBack_dB) ' dB']; 'Peak directivity', [fmtNum(m.PeakDirectivity_dB) ' dB'];
                'Radiation efficiency', [fmtNum(m.Efficiency_pct) ' %']; 'AR at peak', [fmtNum(m.AxialRatioAtPeak_dB) ' dB']}];
            app.ui.tableMeta.Data = [rows; meta.summary];      % workbook summary key/values (Excel sources only)
        end

        function saveTable(app, T, defaultName, prompt, filters, statusLabel)
            % Write a table as CSV / tab-delimited TXT / XLSX (chosen by extension).
            [f, p] = uiputfile(filters, prompt, fullfile(app.folder(), defaultName));
            if isequal(f, 0), return; end
            fp = fullfile(p, f);
            if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
            app.setStatus(statusLabel, ['Exported to <b>' fp '</b>'], true);
        end

        function exportResults(app)
            if isempty(app.pat), return; end
            app.saveTable(app.ui.tableOut.Data, [app.baseName() '_APAT_results.csv'], 'Export Results', {'*.csv'; '*.txt'; '*.xlsx'}, app.ui.status);
        end

        function exportUAN(app)
            % XGTD UAN export (canonical φ 0..360°, physical θ) or the same E-field table as CSV/TXT.
            assert(~isempty(app.pat) && ~app.src.meta.isGainOnly, 'No E-field data to export.');
            T = app.pat;
            U = sortrows(table(T.Theta, T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'}), {'Phi', 'Theta'});
            gmax = max([U.E_TH_DB; U.E_PH_DB]); dt = gridStep(U.Theta); dp = gridStep(U.Phi);
            [f, p] = uiputfile({'*.uan'; '*.csv'; '*.txt'}, 'Export UAN / E-field data', fullfile(app.folder(), sprintf('%s_%.5f_%gdeg.uan', app.baseName(), gmax, dt)));
            if isequal(f, 0), return; end
            fp = fullfile(p, f);
            if endsWith(fp, '.uan', 'IgnoreCase', true)
                header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                    min(U.Phi), max(U.Phi), dp, min(U.Theta), max(U.Theta), dt, gmax);
                writelines(header, fp);
                writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
            elseif endsWith(fp, '.txt', 'IgnoreCase', true), writetable(U, fp, 'Delimiter', '\t');
            else, writetable(U, fp);
            end
            app.setStatus(app.ui.status, ['UAN exported to <b>' fp '</b>'], true);
        end
    end

    %% ------------------------------------------------------------------------------------------------- coverage tab
    methods (Access = private)
        function toCoverage(app)
            % Coverage always receives the current processed Main pattern (loss / step / parameters already applied).
            assert(~isempty(app.pat), 'Load and process a pattern first.');
            app.TabGroup.SelectedTab = app.CovTab; app.cov.pathField.Value = app.filePath;
            node = app.covNodeByPath(app.filePath);
            if isempty(node), app.addPatternNode(app.baseName(), app.pat, app.filePath, app.src.meta.isGainOnly);
            else, app.syncMainNode(node); app.cov.tree.SelectedNodes = node; app.syncCovTarget(); app.setCoverageUI(); end
            app.setStatus(app.cov.status, 'Coverage source synchronized from the Main tab.', false);
        end

        function syncMainNode(app, node)
            d = node.NodeData; d.pattern = app.pat; d.omega = app.omega; d.component = ''; node.NodeData = d;
        end

        function T = patternFrom(app, source)
            % Standalone processing for Coverage-tab sources (block 1, current Main parameters, native step).
            T = calcPattern(normalizePattern(source.blocks{1}), app.getParams(), source.meta.isGainOnly);
        end

        function onCovLoad(app)
            fp = strtrim(app.cov.pathField.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covNodeByPath(fp)), fp = app.browse('Select a pattern or coverage results file'); end
            if isempty(fp), return; end
            existing = app.covNodeByPath(fp);
            if ~isempty(existing)
                app.cov.tree.SelectedNodes = existing; app.onCovSelected(); app.cov.pathField.Value = fp;
                app.setStatus(app.cov.status, 'File already loaded — node selected.', true); return
            end
            app.cov.pathField.Value = fp;
            source = app.readSource(fp, app.cov.fmtDrop, app.cov.fmtGroup);
            if source.meta.isCoverage, app.addResultsNode(fp, source.raw);
            else, [~, name] = fileparts(fp); app.addPatternNode(name, app.patternFrom(source), fp, source.meta.isGainOnly); end
        end

        function onCovFormat(app)
            % Re-interpret a generic text pattern with the selected column format and replace its node.
            fp = strtrim(app.cov.pathField.Value); old = app.covNodeByPath(fp);
            if isempty(old) || ~isGenericText(fp) || ~strcmp(old.NodeData.kind, 'pattern'), return; end
            source = readPattern(fp, app.cov.fmtDrop.Value);
            assert(~source.meta.isCoverage, 'The selected format identifies a coverage-results file.');
            name = old.NodeData.name; app.deleteJobs(app.covJobs(old)); delete(old);
            app.addPatternNode(name, app.patternFrom(source), fp, source.meta.isGainOnly); app.finalizeCov();
            app.setStatus(app.cov.status, sprintf('Pattern "<b>%s</b>" reprocessed with the selected format.', name), true);
        end

        function node = addPatternNode(app, name, T, fp, isGainOnly)
            node = uitreenode(app.cov.root, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', 'pattern', 'name', name, 'path', fp, 'pattern', T, 'omega', solidWeights(T.Theta, T.Phi), ...
                'isGainOnly', isGainOnly, 'component', '', 'axisIndex', 1);
            expand(app.cov.tree);
            app.cov.tree.CheckedNodes = [app.cov.tree.CheckedNodes; node]; app.cov.tree.SelectedNodes = node;
            app.syncCovTarget(); app.setCoverageUI(); app.cov.panelResults.Visible = 'on';
            app.setStatus(app.cov.status, sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name), false);
        end

        function addResultsNode(app, fp, R)
            % Previously exported coverage table: one job curve per coverage column.
            [~, name] = fileparts(fp);
            node = uitreenode(app.cov.root, 'Text', ['📄 ' name]); node.NodeData = struct('kind', 'results', 'name', name, 'path', fp);
            app.cov.tree.CheckedNodes = [app.cov.tree.CheckedNodes; node];
            thr = R{:, 1};
            for k = 2:width(R), app.addJob(node, thr, R{:, k}, 'Res', R.Properties.VariableNames{k}, 'Res'); end
            app.applyCovXRange([min(thr), max(thr)], true);
            if gridStep(thr) < app.cov.thrStep.Value, app.cov.thrStep.Value = max(gridStep(thr), 0.1); end
            expand(app.cov.root);
            app.setStatus(app.cov.status, sprintf('Coverage results "%s" loaded (%d curves).', name, width(R) - 1), false);
        end

        function job = addJob(app, parent, thr, cov, label, comp, tableTag)
            app.covRunID = app.covRunID + 1; id = app.covRunID;
            icon = '📉'; if strcmp(label, 'Res'), icon = '📈'; end
            text = sprintf('%s R%d %s · %s', icon, id, label, comp);
            line = plot(app.cov.axes, thr, cov, 'LineWidth', 1.6, 'DisplayName', text);
            job = uitreenode(parent, 'Text', text);
            job.NodeData = struct('kind', 'job', 'id', id, 'thr', thr(:), 'cov', cov(:), 'line', line, 'label', text, 'tableTag', tableTag, ...
                'isConical', false, 'orientation', "n/a", 'step', gridStep(thr));
            expand(parent); app.cov.tree.CheckedNodes = [app.cov.tree.CheckedNodes; job];
            app.finalizeCov();
        end

        function finalizeCov(app)
            app.rebuildCovTable(); app.updateCovLegend(); app.setCoverageUI(); app.cov.panelResults.Visible = 'on';
        end

        function jobs = covJobs(app, roots)
            % Job nodes below ROOTS (default: everything), sorted by run id.
            if nargin < 2, roots = app.cov.root; end
            jobs = matlab.ui.container.TreeNode.empty(1, 0);
            for r = reshape(roots, 1, [])
                if isstruct(r.NodeData) && strcmp(r.NodeData.kind, 'job'), jobs(end + 1) = r; else, jobs = [jobs, app.covJobs(r.Children)]; end %#ok<AGROW>
            end
            [~, o] = sort(arrayfun(@(j) j.NodeData.id, jobs)); jobs = jobs(o);
        end

        function node = covTarget(app)
            % Pattern node to operate on: the selection's pattern ancestor, else the most recently added pattern.
            node = []; n = app.cov.tree.SelectedNodes;
            while ~isempty(n) && isa(n(1), 'matlab.ui.container.TreeNode')
                if isstruct(n(1).NodeData) && strcmp(n(1).NodeData.kind, 'pattern'), node = n(1); return; end
                n = n(1).Parent;
            end
            kids = app.cov.root.Children;
            for k = numel(kids):-1:1
                if isstruct(kids(k).NodeData) && strcmp(kids(k).NodeData.kind, 'pattern'), node = kids(k); return; end
            end
        end

        function node = covNodeByPath(app, fp)
            node = [];
            for k = reshape(app.cov.root.Children, 1, [])
                if isstruct(k.NodeData) && isfield(k.NodeData, 'path') && strcmp(k.NodeData.path, fp), node = k; return; end
            end
        end

        function deleteJobs(app, jobs)
            for j = jobs
                delete(findall(app.cov.axes, '-regexp', 'Tag', sprintf('^CovQ_\\w+_%d$', j.NodeData.id)));
                if isgraphics(j.NodeData.line), delete(j.NodeData.line); end
            end
        end

        function syncCovTarget(app)
            % Prepare the controls for the target pattern node: component list, orientation, automatic threshold preset.
            node = app.covTarget(); if isempty(node), return; end
            d = node.NodeData; T = d.pattern; dd = app.cov.component;
            prev = d.component; if isempty(prev), prev = dd.Value; end
            app.fillComponents(dd, T, d.isGainOnly, prev); comp = dd.Value;
            if ~strcmp(d.component, comp)
                g = T.(comp); d.axisIndex = boresightAxis(T, d.omega, g, resolvePeak(g, app.PeakPercentile, app.PeakExcessDB), app.Axes);
                d.component = comp; node.NodeData = d;
                if app.cov.orient.Value == 0, app.onCovOrientation(); end       % Auto: follow the detected axis
            end
            key = string(sprintf('%s|%s|%d', d.path, comp, height(T)));
            if app.covPresetKey ~= key   % preset (widen-only) when the pattern / component actually changes
                lim = peakWindow(T.(comp), app.PeakPercentile, app.PeakExcessDB);
                if strlength(app.covPresetKey) > 0, lim = [min(lim(1), app.cov.thrMin.Value), max(lim(2), app.cov.thrMax.Value)]; end
                app.covPresetKey = key; app.cov.thrMin.Value = lim(1); app.cov.thrMax.Value = lim(2);
            end
        end

        function thr = covThresholds(app)
            c = app.cov; step = max(c.thrStep.Value, 0.1); lo = c.thrMin.Value; hi = max(c.thrMax.Value, lo + step);
            thr = unique([(lo:step:hi)'; hi]);
        end

        function onCovCompute(app)
            node = app.covTarget(); assert(~isempty(node), 'Load (or select) an antenna pattern node first.');
            if strcmp(node.NodeData.path, app.filePath) && ~isempty(app.pat), app.syncMainNode(node); end
            app.syncCovTarget(); d = node.NodeData; T = d.pattern; comp = app.cov.component.Value; thr = app.covThresholds();
            mask = true(height(T), 1); label = 'Sph coverage'; tableTag = 'Sph'; orientation = "n/a"; conical = app.cov.conBtn.Value;
            if conical
                th0 = app.cov.coneTh.Value; ph0 = mod(app.cov.conePh.Value, 360); alpha = app.cov.coneAng.Value;
                mask = cosd(T.Theta) * cosd(th0) + sind(T.Theta) * sind(th0) .* cosd(T.Phi - ph0) >= cosd(alpha);
                center = app.coneLabel(th0, ph0);
                label = sprintf('Conical coverage (%s) α=%s°', center, fmtNum(alpha)); tableTag = sprintf('Con %s α%s°', erase(center, ["=", ","]), fmtNum(alpha));
                k = app.cov.orient.Value; if k == 0, k = d.axisIndex; end; orientation = string(app.Axes.labels{k});
            end
            cov = coverageCCDF(T.(comp), mask, thr, d.omega);
            job = app.addJob(node, thr, cov, label, comp, tableTag);
            job.NodeData.isConical = conical; job.NodeData.orientation = orientation;
            app.applyCovXRange([thr(1), thr(end)], true);
            msg = sprintf('Run <b>%d</b>: <b>%s</b> on "<b>%s</b>" (%s, %d thresholds).', job.NodeData.id, label, d.name, comp, numel(thr));
            if conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, orientation); end
            app.setStatus(app.cov.status, msg, false);
        end

        function label = coneLabel(app, theta, phi)
            % Principal-axis name when the cone centre coincides with ±X/±Y/±Z, otherwise the explicit θ/φ.
            a = app.Axes; c = [sind(theta) * cosd(phi); sind(theta) * sind(phi); cosd(theta)];
            k = find([sind(a.theta) .* cosd(a.phi); sind(a.theta) .* sind(a.phi); cosd(a.theta)]' * c >= 1 - 1e-9, 1);
            if isempty(k), label = sprintf('θ=%s°, φ=%s°', fmtNum(theta), fmtNum(phi)); else, label = a.labels{k}; end
        end

        function rebuildCovTable(app)
            jobs = app.covJobs(); jobs = jobs(ismember(jobs, app.cov.tree.CheckedNodes));
            if isempty(jobs), app.cov.table.Data = table(); return; end
            d = [jobs.NodeData]; thr = unique(vertcat(d.thr));
            V = nan(numel(thr), numel(d)); names = cell(1, numel(d));
            for k = 1:numel(d), V(:, k) = interp1(d(k).thr, d(k).cov, thr, 'linear', NaN); names{k} = sprintf('R%d %s %%', d(k).id, d(k).tableTag); end
            app.cov.table.Data = array2table(compose('%.2f', [thr, V]), 'VariableNames', [{'Threshold (dB)'}, names]);
        end

        function updateCovLegend(app)
            jobs = app.covJobs(); jobs = jobs(ismember(jobs, app.cov.tree.CheckedNodes));
            if isempty(jobs), legend(app.cov.axes, 'off'); return; end
            d = [jobs.NodeData]; legend(app.cov.axes, [d.line], {d.label}, 'Location', 'southwest', 'Interpreter', 'none');
        end

        function onCovChecked(app)
            checked = app.cov.tree.CheckedNodes;
            for j = app.covJobs()
                d = j.NodeData; on = ismember(j, checked);
                set([d.line; findall(d.line, 'Type', 'datatip'); findall(app.cov.axes, '-regexp', 'Tag', sprintf('^CovQ_\\w+_%d$', d.id))], 'Visible', on);
            end
            app.rebuildCovTable(); app.updateCovLegend(); app.setCoverageUI();
        end

        function onCovSelected(app)
            sel = app.cov.tree.SelectedNodes;
            for j = app.covJobs(), j.NodeData.line.LineWidth = 1.6 + (~isempty(sel) && isequal(j, sel(1))); end   % highlight selection
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(app.cov.status, 'Ready.', false); return; end
            app.syncCovTarget(); app.setCoverageUI(); d = sel(1).NodeData;
            if ~strcmp(d.kind, 'job')
                n = numel(sel(1).Children); kind = 'Pattern'; if strcmp(d.kind, 'results'), kind = 'Results'; end
                msg = sprintf('%s "<b>%s</b>" — <b>%d</b> coverage job%s.', kind, d.name, n, repmat('s', 1, n ~= 1));
                if strcmp(d.kind, 'pattern') && app.cov.conBtn.Value, msg = [msg ' | ' app.orientationText()]; end
                app.setStatus(app.cov.status, msg, false); return
            end
            shown = round(d.cov, 2); k = find(shown == max(shown), 1, 'last'); t50 = app.covQueryPoint(d, "thr", 50);
            parts = {d.label};
            if d.isConical, parts{end + 1} = sprintf('Orientation <b>%s</b>', d.orientation); end
            parts{end + 1} = sprintf('Threshold [%s, %s] dB, step %s dB', fmtNum(d.thr(1)), fmtNum(d.thr(end)), fmtNum(d.step));
            if isfinite(t50), parts{end + 1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', fmtNum(t50)); else, parts{end + 1} = '<b>50%-coverage unavailable</b>'; end
            parts{end + 1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmtNum(shown(k)), fmtNum(d.thr(k)));
            app.setStatus(app.cov.status, strjoin(parts, ' | '), false);
        end

        function [x, y] = covQueryPoint(~, d, mode, q)
            % Coverage at a threshold ("cov") or threshold at a coverage level ("thr"), linearly interpolated.
            if mode == "cov", x = q; y = interp1(d.thr, d.cov, q, 'linear', NaN); return; end
            [c, i] = unique(d.cov, 'last'); y = q; x = NaN;
            if numel(c) > 1, x = interp1(c, d.thr(i), q, 'linear', NaN); end
        end

        function onCovQuery(app, mode)
            % Mark the query point on every checked job under the selection with dotted projections to both axes.
            ax = app.cov.axes; sel = app.cov.tree.SelectedNodes;
            if isempty(sel), app.setStatus(app.cov.status, 'Select a node to query.', true); return; end
            jobs = app.covJobs(sel); jobs = jobs(ismember(jobs, app.cov.tree.CheckedNodes));
            if isempty(jobs), app.setStatus(app.cov.status, 'No checked results under the selected node.', true); return; end
            if mode == "cov", q = app.cov.qCov.Value; else, q = app.cov.qThr.Value; end
            hit = false;
            for j = jobs
                d = j.NodeData; tag = sprintf('CovQ_%s_%d', mode, d.id);
                delete(findall(ax, 'Tag', tag));
                [x, y] = app.covQueryPoint(d, mode, q);
                if ~isfinite(x) || ~isfinite(y), continue; end
                line(ax, [x x], [ax.YLim(1) y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [-250 x], [y y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                d.line.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", 'XData', '%.2f dB'); dataTipTextRow("Coverage", 'YData', '%.2f %%')];
                datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'Tag', tag, 'FontSize', 9);
                hit = true;
            end
            if ~hit, app.setStatus(app.cov.status, 'Query value is outside the range of the selected results.', true);
            elseif mode == "cov", app.setStatus(app.cov.status, sprintf('Coverage queried at %s dB.', fmtNum(q)), false);
            else, app.setStatus(app.cov.status, sprintf('Threshold queried at %s%% coverage.', fmtNum(q)), false);
            end
        end

        function onCovClear(app)
            jobs = app.covJobs(app.cov.tree.SelectedNodes);
            if isempty(jobs), app.setStatus(app.cov.status, 'Select a node with coverage results to clear.', true); return; end
            for j = jobs
                delete(findall(app.cov.axes, '-regexp', 'Tag', sprintf('^CovQ_\\w+_%d$', j.NodeData.id))); delete(findall(j.NodeData.line, 'Type', 'datatip'));
            end
            app.setStatus(app.cov.status, 'Selected DataTips and query markers cleared.', true);
        end

        function onCovReset(app)
            app.deleteJobs(app.covJobs()); delete(app.cov.root.Children);
            cla(app.cov.axes); legend(app.cov.axes, 'off'); set(app.cov.axes, 'NextPlot', 'add', 'XLimMode', 'auto');
            app.cov.table.Data = table(); app.covRunID = 0; app.covPresetKey = ""; app.covXInit = false;
            app.cov.panelResults.Visible = 'off'; app.setCoverageUI();
            app.setStatus(app.cov.status, 'Coverage workspace reset 🔄', true);
        end

        function onCovExport(app)
            if isempty(app.cov.table.Data), return; end
            app.saveTable(app.cov.table.Data, 'coverage_results.csv', 'Export Coverage Results', {'*.csv'; '*.txt'; '*.xlsx'}, app.cov.status);
        end

        function onCovType(app)
            app.setCoverageUI();
            if app.cov.conBtn.Value, app.syncCovTarget(); app.reportOrientation();
            else, app.cov.status.Text = regexprep(app.cov.status.Text, '\s*\|\s*Orientation <b>.*?</b>', ''); end
        end

        function txt = orientationText(app)
            k = app.cov.orient.Value; node = app.covTarget(); txt = '';
            if k == 0 && ~isempty(node), k = node.NodeData.axisIndex; end
            if k >= 1, txt = sprintf('Orientation <b>%s</b>', app.Axes.labels{k}); end
        end

        function reportOrientation(app)
            if ~app.cov.conBtn.Value, return; end
            base = regexprep(app.cov.status.Text, '\s*\|\s*Orientation <b>.*?</b>$', ''); txt = app.orientationText();
            if ~isempty(txt), app.setStatus(app.cov.status, [base ' | ' txt], false); end
        end

        function onCovOrientation(app)
            % Auto follows the detected axis; an explicit choice is authoritative until changed again.
            k = app.cov.orient.Value; node = app.covTarget();
            if k == 0, if isempty(node), return; end, k = node.NodeData.axisIndex; end
            [app.cov.coneTh.Value, app.cov.conePh.Value] = deal(app.Axes.theta(k), app.Axes.phi(k));
            app.reportOrientation();
        end

        function onCovComponent(app)
            node = app.covTarget(); if isempty(node), return; end
            node.NodeData.component = '';          % force orientation re-detection for the new component
            app.syncCovTarget(); app.reportOrientation();
        end

        function applyCovXRange(app, lim, autoExpand)
            % Coverage X axis: the first result sets the baseline; later results may only widen it automatically.
            if nargin > 2 && autoExpand
                if app.covXInit, lim = [min(lim(1), app.cov.axes.XLim(1)), max(lim(2), app.cov.axes.XLim(2))]; end
                app.covXInit = true;
            end
            lim = clampRange(lim); app.syncRange(app.cov.xSlider, app.cov.xMin, app.cov.xMax, lim);
            set(app.cov.axes, 'XLimMode', 'manual', 'XLim', lim);
        end

        function setCoverageUI(app)
            % Control availability is a pure function of the tree state (no mode memory).
            c = app.cov; hasPattern = ~isempty(app.covTarget()); hasJobs = ~isempty(app.covJobs()); any_ = hasPattern || hasJobs;
            set(c.patternCtrls, 'Visible', hasPattern, 'Enable', hasPattern);
            set(c.coneCtrls, 'Visible', hasPattern && c.conBtn.Value, 'Enable', hasPattern && c.conBtn.Value);
            set([c.exportBtn, c.clearBtn, c.queryCtrls], 'Visible', any_, 'Enable', hasJobs);
            set(c.resetBtn, 'Visible', any_, 'Enable', any_); c.computeBtn.Enable = hasPattern;
            set(c.fmtGroup, 'Visible', hasPattern && isGenericText(c.pathField.Value));
        end
    end

    %% ---------------------------------------------------------------------------------------------- UI construction
    methods (Access = private)
        function h = at(~, h, row, col)
            % Place a component in its parent grid (row/col may be spans) and return it for chaining.
            h.Layout.Row = row; h.Layout.Column = col;
        end

        function h = label(app, parent, text, row, col, varargin)
            h = app.at(uilabel(parent, 'Text', text, 'HorizontalAlignment', 'right', varargin{:}), row, col);
        end

        function dd = formatDropdown(app, parent, callback)
            dd = uidropdown(parent, 'Items', app.TextFormats(:, 1), 'ItemsData', app.TextFormats(:, 2), 'Value', 'gain', ...
                'Tooltip', 'Interpretation of CSV/TXT/DAT pattern files.', 'ValueChangedFcn', callback);
        end

        function prepareAxes(app, ax, is3D)
            % Interactions plus one persistent context menu per axes (re-assigned to new children after each render).
            menu = uicontextmenu(app.UIFigure);
            uimenu(menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ~) delete(findall(ax, 'Type', 'datatip', 'Tag', '')));
            ax.ContextMenu = menu;
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), return; end
            enableDefaultInteractivity(ax);
            if is3D, ax.Interactions = [rotateInteraction, dataTipInteraction]; else, ax.Interactions = [zoomInteraction, dataTipInteraction]; end
        end

        function p = patternTab(app, group, title, isPolar, is3D)
            % One full-pattern tab: [max spinner; range slider; min spinner] beside the plot axes.
            p.tab = uitab(group, 'Title', title);
            g = uigridlayout(p.tab, [3 2], 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
            if isPolar, p.axes = polaraxes(g); else, p.axes = uiaxes(g); end
            app.at(p.axes, [1 3], 2);
            p.maxSpin = app.at(uispinner(g, 'Limits', [-250 100], 'Value', 10, 'Step', 5), 1, 1);
            p.slider = app.at(uislider(g, 'range', 'Limits', [-250 100], 'Value', [-40 10], 'Orientation', 'vertical', 'Step', 1), 2, 1);
            p.minSpin = app.at(uispinner(g, 'Limits', [-250 100], 'Value', -40, 'Step', 5), 3, 1);
            app.prepareAxes(p.axes, is3D);
        end

        function buildUI(app)
            app.UIFigure = uifigure('Name', [app.Release ' — Antenna Pattern Analyzer Tool'], 'Position', [100 100 1200 760], ...
                'WindowState', 'maximized', 'Visible', 'off', 'CloseRequestFcn', @(~, ~) delete(app));
            app.TabGroup = uitabgroup(uigridlayout(app.UIFigure, [1 1]));
            app.MainTab = uitab(app.TabGroup, 'Title', 'Process Pattern 📡');
            app.CovTab = uitab(app.TabGroup, 'Title', 'Compute Coverage 📈');
            app.buildMainTab(); app.buildCoverageTab();
            app.UIFigure.Visible = 'on';
        end

        function buildMainTab(app)
            cb = @(f) app.guard(@(~, ~) f());
            G = uigridlayout(app.MainTab, [5 14], 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});
            u = struct();
            % --- Inputs & parameters --------------------------------------------------------------------------
            P = uigridlayout(app.at(uipanel(G, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 14]), [3 14], 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            app.label(P, 'Input Pattern:', 1, 1);
            u.pathField = app.at(uieditfield(P, 'text'), 1, [2 8]);
            u.ffdDrop = app.at(uidropdown(P, 'Items', {'Frequencies'}, 'ValueChangedFcn', cb(@() app.onBlockChanged())), 1, 10);
            u.ffdGroup = [app.label(P, 'FFD Freq:', 1, 9), u.ffdDrop];
            u.loadBtn = app.at(uibutton(P, 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', cb(@() app.onLoad())), 1, [11 12]);
            u.processBtn = app.at(uibutton(P, 'Text', '⚙️ Process', 'ButtonPushedFcn', cb(@() app.onProcess())), 1, [13 14]);
            u.resetBtn = app.at(uibutton(P, 'Text', 'Reset Params', 'ButtonPushedFcn', cb(@() app.resetParams())), 2, [1 3]);
            u.fmtDrop = app.at(app.formatDropdown(P, cb(@() app.onFormatChanged())), 2, [6 8]);
            u.fmtGroup = [app.label(P, 'Format:', 2, [4 5]), u.fmtDrop];
            u.stepDrop = app.at(uidropdown(P, 'Items', {'STEP', 'STEP: 1°'}, 'Visible', 'off', 'ValueChangedFcn', app.guard(@(s, ~) app.onStepChanged(s))), 2, [9 10]);
            u.exportBtn = app.at(uibutton(P, 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@() app.exportResults())), 2, [11 12]);
            u.uanBtn = app.at(uibutton(P, 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@() app.exportUAN())), 2, [13 14]);
            u.rxPol = app.at(uidropdown(P, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Editable', 'on'), 3, 2);
            u.rw = app.at(uispinner(P, 'Value', 6), 3, 4);
            u.rxGroup = [app.label(P, 'Rw Sense', 3, 1), u.rxPol, app.label(P, 'Rw (dB)', 3, 3), u.rw];
            u.loss = app.at(uispinner(P, 'Step', 0.1), 3, 6);
            u.lossGroup = [app.label(P, 'Loss (−) / Gain (+) dB', 3, 5), u.loss];
            u.pt = app.at(uispinner(P), 3, 8); u.ptUnit = app.at(uidropdown(P, 'Items', {'dBW', 'dBm', 'Watts'}), 3, 9);
            u.txGroup = [app.label(P, 'Tx Pwr (Pt)', 3, 7), u.pt, u.ptUnit];
            u.dist = app.at(uispinner(P, 'Value', 1), 3, 11); u.distUnit = app.at(uidropdown(P, 'Items', {'m', 'km'}), 3, 12);
            u.distGroup = [app.label(P, 'Distance', 3, 10), u.dist, u.distUnit];
            u.covBtn = app.at(uibutton(P, 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@() app.toCoverage())), 3, [13 14]);
            set([u.rxGroup, u.lossGroup, u.txGroup, u.distGroup, u.fmtGroup, u.ffdGroup], 'Visible', 'off');
            % --- Full-pattern plots (five tabs sharing one colour scale) ----------------------------------------
            u.panelPlots = app.at(uipanel(G, 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [1 6]);
            tg = uitabgroup(uigridlayout(u.panelPlots, [1 1]), 'SelectionChangedFcn', @(~, ~) app.syncTips());
            specs = {'contour', 'Contour Plot', [0 0]; 'circular', 'Circular Contour Plot', [0 0]; 'sphere3D', '3D Spherical Plot', [135 25]; ...
                'polar3D', '3D Polar Plot', [135 25]; 'rect3D', '3D Surface Plot', [-35 35]};
            tabs = cell(1, 5);
            for k = 1:5
                p = app.patternTab(tg, specs{k, 2}, k == 2, k >= 3); p.kind = string(specs{k, 1}); p.view = specs{k, 3}; tabs{k} = p;
                app.linkRange(p.slider, p.minSpin, p.maxSpin, @(lim) app.onColorRange(lim, false));
            end
            app.plots = [tabs{:}];
            % --- Cut panel --------------------------------------------------------------------------------------
            u.panelCut = app.at(uipanel(G, 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [7 12]);
            u.cutTabs = uitabgroup(uigridlayout(u.panelCut, [1 1]), 'SelectionChangedFcn', @(~, ~) app.syncTips());
            u.polarTab = uitab(u.cutTabs, 'Title', 'Polar Cut Plot');
            g = uigridlayout(u.polarTab, [4 4], 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            u.polarCut = app.at(polaraxes(g), [1 4], 3);
            u.cutMax = app.at(uispinner(g, 'Limits', [-250 100], 'Value', 10, 'Step', 5), 1, 1);
            u.cutSlider = app.at(uislider(g, 'range', 'Limits', [-250 100], 'Value', [-40 10], 'Orientation', 'vertical', 'Step', 1), [2 3], 1);
            u.cutMin = app.at(uispinner(g, 'Limits', [-250 100], 'Value', -40, 'Step', 5), 4, 1);
            u.hpbwBtn = app.at(uibutton(g, 'state', 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', cb(@() app.onCutChanged())), 1, 4);
            u.hpbwLabel = app.at(uilabel(g, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold'), 2, 4);
            u.cutBoxGrid = app.at(uigridlayout(g, [3 1]), 3, 4); boxes = cell(1, 3); names = {'E_Total', 'E_RCP', 'E_LCP'};
            for k = 1:3, boxes{k} = app.at(uicheckbox(u.cutBoxGrid, 'Text', names{k}, 'Value', true, 'ValueChangedFcn', cb(@() app.onCutChanged())), k, 1); end
            u.cutBoxes = [boxes{:}];
            u.exportCutBtn = app.at(uibutton(g, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', cb(@() app.exportCut())), 4, 4);
            u.rectTab = uitab(u.cutTabs, 'Title', 'Rectangular Cut Plot');
            u.rectCut = uiaxes(uigridlayout(u.rectTab, [1 1])); u.rectCut.Box = 'on';
            app.prepareAxes(u.polarCut, false); app.prepareAxes(u.rectCut, false);
            app.linkRange(u.cutSlider, u.cutMin, u.cutMax, @(lim) app.onCutRange(lim));
            % --- Results / Input / Metadata tables --------------------------------------------------------------
            u.outFilter = app.at(uidropdown(G, 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Visible', 'off', 'ValueChangedFcn', cb(@() app.onFilterChanged())), 3, [13 14]);
            u.dataTabs = app.at(uitabgroup(G, 'Visible', 'off'), 4, [1 14]);
            u.tableOut = uitable(uigridlayout(uitab(u.dataTabs, 'Title', 'Results 📤'), [1 1]), 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnWidth', '1x');
            u.tableIn = uitable(uigridlayout(uitab(u.dataTabs, 'Title', 'Input 📥'), [1 1]), 'ColumnSortable', true, 'RowName', 'numbered');
            u.tableMeta = uitable(uigridlayout(uitab(u.dataTabs, 'Title', 'Metadata 📋'), [1 1]), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {220, 'auto'}, 'RowName', {});
            % --- Plot control -----------------------------------------------------------------------------------
            u.panelCtrl = app.at(uipanel(G, 'Title', 'Plot Control 🎨', 'Visible', 'off'), 2, [13 14]);
            C = uigridlayout(u.panelCtrl, [15 2], 'RowHeight', repmat({'fit'}, 1, 15));
            app.label(C, 'Component', 1, 1);
            u.component = app.at(uidropdown(C, 'Items', cellstr(app.ComponentLabels), 'ItemsData', cellstr(app.Components), 'ValueChangedFcn', cb(@() app.onComponentChanged())), 1, 2);
            app.label(C, 'Cut type', 2, 1);
            u.cutType = app.at(uidropdown(C, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', app.guard(@(s, ~) app.onCutChanged(s))), 2, 2);
            app.label(C, 'Cut value', 3, 1);
            u.cutValue = app.at(uispinner(C, 'Limits', [0 360], 'ValueChangedFcn', app.guard(@(s, ~) app.onCutChanged(s))), 3, 2);
            app.label(C, 'Cut fields', 4, 1);
            u.cutBasis = app.at(uidropdown(C, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Enable', 'off', ...
                'ValueChangedFcn', app.guard(@(s, ~) app.onCutChanged(s))), 4, 2);
            app.label(C, 'Colorbar max', 5, 1); u.cmax = app.at(uispinner(C, 'Limits', [-250 100], 'Value', 10), 5, 2);
            app.label(C, 'Colorbar min', 6, 1); u.cmin = app.at(uispinner(C, 'Limits', [-250 100], 'Value', -40), 6, 2);
            app.label(C, 'Colorbar step', 7, 1);
            u.cstep = app.at(uispinner(C, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', @(~, ~) app.applyColorRange(app.ctrLim, false)), 7, 2);
            app.label(C, 'Adjust Colorbar', 8, 1);
            u.applyBtn = app.at(uibutton(C, 'Text', 'Apply', 'Tooltip', 'Apply min/max to the full-pattern plots and the cut plots.', ...
                'ButtonPushedFcn', cb(@() app.onColorRange([app.ui.cmin.Value, app.ui.cmax.Value], true))), 8, 2);
            app.label(C, '3D view', 9, 1);
            u.view3D = app.at(uidropdown(C, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'ValueChangedFcn', @(~, ~) app.onViewChanged()), 9, 2);
            pad = @(n) repmat(char(160), 1, n);    % non-breaking padding centres the switch captions
            u.phiSpan = app.at(uiswitch(C, 'slider', 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, ...
                'ValueChangedFcn', cb(@() app.onSpanChanged())), 10, [1 2]);
            u.thetaSpan = app.at(uiswitch(C, 'slider', 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, ...
                'ValueChangedFcn', cb(@() app.onSpanChanged())), 11, [1 2]);
            u.ehSwitch = app.at(uiswitch(C, 'slider', 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, ...
                'ValueChangedFcn', cb(@() app.onPlaneSwitch())), 12, [1 2]);
            u.overlay = app.at(uicheckbox(C, 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', cb(@() app.onOverlayChanged())), 13, [1 2]);
            u.pobBox = app.at(uicheckbox(C, 'Text', 'Annotate POB', 'ValueChangedFcn', @(~, ~) app.syncTips()), 14, [1 2]);
            u.hpbwBoundsBox = app.at(uicheckbox(C, 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', @(~, ~) app.syncTips()), 15, [1 2]);
            u.status = app.at(uilabel(G, 'Text', 'Ready — load an antenna pattern file to begin 🚀', 'Interpreter', 'html'), 5, [1 14]);
            u.status.UserData = u.status.Text;
            app.ui = u;
        end

        function buildCoverageTab(app)
            cb = @(f) app.guard(@(~, ~) f());
            G = uigridlayout(app.CovTab, [3 5], 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            c = struct();
            % --- Inputs & parameters --------------------------------------------------------------------------
            P = uigridlayout(app.at(uipanel(G, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 5]), [4 10], 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'});
            c.typeGroup = app.at(uibuttongroup(P, 'Title', 'Coverage Type', 'SelectionChangedFcn', cb(@() app.onCovType())), [1 2], [1 2]);
            c.sphBtn = uiradiobutton(c.typeGroup, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            c.conBtn = uiradiobutton(c.typeGroup, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            c.orientLabel = app.label(P, 'Orientation 🧭:', 3, 1);
            c.orient = app.at(uidropdown(P, 'Items', [{'Auto'}, app.Axes.labels], 'ItemsData', 0:6, 'ValueChangedFcn', cb(@() app.onCovOrientation())), 3, 2);
            app.label(P, 'Antenna Pattern:', 1, 3);
            c.pathField = app.at(uieditfield(P, 'text'), 1, [4 8]);
            c.loadBtn = app.at(uibutton(P, 'Text', '📂 Load File', 'ButtonPushedFcn', cb(@() app.onCovLoad())), 1, 9);
            c.computeBtn = app.at(uibutton(P, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'ButtonPushedFcn', cb(@() app.onCovCompute())), 1, 10);
            l1 = app.label(P, 'Threshold Min (dB):', 2, 3); c.thrMin = app.at(uispinner(P, 'Limits', [-250 99], 'Value', -40), 2, 4);
            l2 = app.label(P, 'Threshold Max (dB):', 2, 5); c.thrMax = app.at(uispinner(P, 'Limits', [-249 100], 'Value', 10), 2, 6);
            l3 = app.label(P, 'Step (dB):', 2, 7);          c.thrStep = app.at(uispinner(P, 'Limits', [0.1 50], 'Value', 1), 2, 8);
            c.resetBtn = app.at(uibutton(P, 'Text', '🔄 Reset', 'ButtonPushedFcn', cb(@() app.onCovReset())), 2, 9);
            c.exportBtn = app.at(uibutton(P, 'Text', '💾 Export Results', 'ButtonPushedFcn', cb(@() app.onCovExport())), 2, 10);
            l4 = app.label(P, 'Cone θ₀ (°):', 3, 3);      c.coneTh = app.at(uispinner(P, 'Limits', [0 180]), 3, 4);
            l5 = app.label(P, 'Cone φ₀ (°):', 3, 5);      c.conePh = app.at(uispinner(P, 'Limits', [0 360]), 3, 6);
            l6 = app.label(P, 'Cone Angle α (°):', 3, 7); c.coneAng = app.at(uispinner(P, 'Limits', [0 180], 'Value', 45), 3, 8);
            c.clearBtn = app.at(uibutton(P, 'Text', '🧹 Clear DataTips', 'ButtonPushedFcn', cb(@() app.onCovClear())), 3, 9);
            c.toMainBtn = app.at(uibutton(P, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~, ~) set(app.TabGroup, 'SelectedTab', app.MainTab)), 3, 10);
            c.compLabel = app.label(P, 'Component:', 4, 1);
            c.component = app.at(uidropdown(P, 'Items', {'E_Total_dB'}, 'ValueChangedFcn', cb(@() app.onCovComponent())), 4, 2);
            l7 = app.label(P, 'Coverage @ dB:', 4, 3);   c.qCov = app.at(uispinner(P, 'ValueDisplayFormat', '%g dB'), 4, 4);
            c.qCovBtn = app.at(uibutton(P, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', cb(@() app.onCovQuery("cov"))), 4, 5);
            l8 = app.label(P, 'Threshold @ %:', 4, 6);   c.qThr = app.at(uispinner(P, 'ValueDisplayFormat', '%g%%', 'Limits', [0 100], 'Value', 50), 4, 7);
            c.qThrBtn = app.at(uibutton(P, 'Text', '🔍 Query Threshold', 'ButtonPushedFcn', cb(@() app.onCovQuery("thr"))), 4, 8);
            c.fmtDrop = app.at(app.formatDropdown(P, cb(@() app.onCovFormat())), 4, 10);
            c.fmtGroup = [app.label(P, 'Format:', 4, 9), c.fmtDrop];
            c.patternCtrls = [c.typeGroup, l1, c.thrMin, l2, c.thrMax, l3, c.thrStep, c.compLabel, c.component];
            c.coneCtrls = [l4, c.coneTh, l5, c.conePh, l6, c.coneAng, c.orientLabel, c.orient];
            c.queryCtrls = [l7, c.qCov, c.qCovBtn, l8, c.qThr, c.qThrBtn];
            % --- Results ----------------------------------------------------------------------------------------
            c.panelResults = app.at(uipanel(G, 'Title', 'Results', 'Visible', 'off'), 2, [1 5]);
            R = uigridlayout(c.panelResults, [2 5], 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            c.tree = app.at(uitree(R, 'checkbox', 'SelectionChangedFcn', cb(@() app.onCovSelected()), 'CheckedNodesChangedFcn', cb(@() app.onCovChecked())), [1 2], 1);
            c.root = uitreenode(c.tree, 'Text', 'Coverage Results');
            c.axes = app.at(uiaxes(R), 1, [2 4]);
            title(c.axes, 'Coverage vs Threshold'); xlabel(c.axes, 'Threshold (dB)'); ylabel(c.axes, 'Coverage (%)');
            set(c.axes, 'Box', 'on', 'Layer', 'top', 'YLim', [0 100], 'XGrid', 'on', 'YGrid', 'on', 'NextPlot', 'add', 'Interactions', dataTipInteraction);
            c.xMin = app.at(uispinner(R, 'Limits', [-250 100], 'Value', -40), 2, 2);
            c.xSlider = app.at(uislider(R, 'range', 'Limits', [-250 100], 'Value', [-40 10]), 2, 3);
            c.xMax = app.at(uispinner(R, 'Limits', [-250 100], 'Value', 10), 2, 4);
            c.table = app.at(uitable(R, 'ColumnWidth', '1x', 'RowName', {}), [1 2], 5);
            c.status = app.at(uilabel(G, 'Text', 'Ready 🚀', 'Interpreter', 'html'), 3, [1 5]); c.status.UserData = c.status.Text;
            app.linkRange(c.xSlider, c.xMin, c.xMax, @(lim) app.applyCovXRange(lim));
            app.cov = c;
        end
    end

    %% ------------------------------------------------------------------------------------------------------ self-test
    methods (Static)
        function report = runSelfTest()
            %RUNSELFTEST Deterministic checks of the numerical core (no UI); errors when any check fails.
            [P, T] = meshgrid(0:2:358, 0:2:180); g = 20 * log10(max(cosd(T(:)), 1e-6));     % cos θ pattern, 0 dB peak at +Z
            tbl = normalizePattern(table(T(:), P(:), g, 'VariableNames', {'Theta', 'Phi', 'Gain_dB'}));
            w = solidWeights(tbl.Theta, tbl.Phi); ax = APAT_v3_M8_24.Axes;
            r.solidAngle = abs(sum(w) - 4 * pi) < 1e-9;
            r.seam = nnz(tbl.Phi == 360) == nnz(tbl.Phi == 0) && nnz(tbl.Phi == 0) == 91;
            pk = resolvePeak(tbl.Gain_dB, 99.99, 6); r.peak = abs(pk.value) < 1e-9 && tbl.Theta(pk.index) == 0 && ~pk.wasAdjusted;
            spike = repmat(0.02, 100000, 1); spike(1) = 10.02; sp = resolvePeak(spike, 99.99, 6);
            r.isolatedSpike = sp.wasAdjusted && abs(sp.value - 0.02) < 1e-12 && isequal(peakWindow(spike, 99.99, 6), [-45 5]);
            r.window = isequal(peakWindow([3.2; -250; -17], 99.99, 6), [-45 5]);
            R = resampleCanonical(tbl, 1); native = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0;
            r.resample = height(R) == 181 * 361 && max(abs(R.Gain_dB(native) - 20 * log10(max(cosd(R.Theta(native)), 1e-6)))) < 1e-9;
            [rows, ang] = cutRows(tbl, 'Theta', 0); r.hpbw = abs(calcHPBW(ang, tbl.Gain_dB(rows)) - 90) < 0.5;   % cos θ: −3 dB at ±45°
            cov = coverageCCDF(tbl.Gain_dB, true(height(tbl), 1), [-3; 0; 10], w);   % front cap θ < 45°: (1 − cos 45°) / 2 of the sphere
            r.coverage = abs(cov(1) - 50 * (1 - cosd(45))) < 0.5 && cov(2) == 0 && cov(3) == 0 && all(diff(cov) <= 0);
            r.orientation = boresightAxis(tbl, w, tbl.Gain_dB, pk, ax) == 1;
            m = calcMetrics(tbl, w, tbl.Gain_dB, pk, 1, ax); r.directivity = abs(m.PeakDirectivity_dB - 10 * log10(6)) < 0.05;   % U = cos²θ (front) → D = 6
            f = [tempname '.ffd']; cleaner = onCleanup(@() delete(f)); %#ok<NASGU>
            writelines(["0 180 3"; "-180 180 3"; compose("%d 0 0 1", (1:9)')], f);
            s = readPattern(f); r.ffd = strcmp(s.meta.source, 'HFSS FFD') && isscalar(s.blocks) && height(s.blocks{1}) == 9;
            r.arNames = all(cellfun(@isAR, {'AR', 'AR_dB', 'AR dB', 'Axial Ratio', 'Axial_Ratio'})) && ~isAR('E_Total_dB');
            failed = fieldnames(r); failed = failed(~cellfun(@(k) r.(k), failed));
            report = r; report.pass = isempty(failed);
            if ~report.pass, error('APAT:SelfTest', 'Self-test failed: %s', strjoin(failed, ', ')); end
        end
    end
end

%% ======================================================================================================= I/O readers
function src = readPattern(fp, fmt)
%READPATTERN Read any supported pattern / coverage source into one adapter struct.
%   src.raw    table as found in the file (Input tab)
%   src.blocks cell of primitive tables {Theta, Phi, Re_Eth, Im_Eth, Re_Eph, Im_Eph} or {Theta, Phi, <gain columns>}
%   src.freqs  block frequencies in Hz (NaN when unknown)
%   src.meta   source, isGainOnly, isCoverage, isDep, summary (N×2 cell of workbook metadata)
if nargin < 2, fmt = 'gain'; end
[~, ~, ext] = fileparts(fp); ext = upper(ext(2:end));
src = struct('raw', table(), 'blocks', {{}}, 'freqs', NaN, 'meta', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'summary', {cell(0, 2)}));
switch ext
    case {'XLSX', 'XLS'},                    src = readExcelMatrix(fp, src);
    case {'CSV', 'TXT', 'DAT'},              src = readGenericText(fp, fmt, src);
    case 'CUT',                              src = readGraspCut(fp, src);
    case 'FFD',                              src = readHfssFfd(fp, src);
    case {'UAN', 'FZ', 'OUT', 'FFS', 'FFE'}, src = readColumnFile(fp, ext, src);
    otherwise, error('APAT:io:Unsupported', 'Unsupported file type: %s', ext);
end
end

function T = fieldTable(theta, phi, Eth, Eph)
T = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function [Eth, Eph] = circularToLinear(Ercp, Elcp)
Eth = (Ercp + Elcp) / sqrt(2); Eph = (Ercp - Elcp) / (1i * sqrt(2));
end

function E = magPhase(dB, deg)
E = 10 .^ (dB / 20) .* exp(1i * deg2rad(deg));
end

function tf = isGenericText(fp)
[~, ~, ext] = fileparts(char(fp)); tf = any(strcmpi(ext, {'.csv', '.txt', '.dat'}));
end

function M = numericBody(fp)
% Numeric matrix of a text file; the header is every line before the first row with ≥ 4 numeric fields.
num = '[-+]?(\d+\.?\d*|\.\d+)([eEdD][-+]?\d+)?';
lines = readlines(fp);
first = find(~cellfun(@isempty, regexp(cellstr(lines), ['^\s*' num '([\s,;]+' num '){3,}\s*$'], 'once')), 1);
assert(~isempty(first), 'APAT:io:NoData', 'No numeric data rows found in %s.', fp);
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', first - 1, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = readmatrix(fp, setvartype(opts, 'double')); M = M(~all(isnan(M), 2), :);
end

function src = readColumnFile(fp, ext, src)
% Column-oriented far-field exports: XGTD UAN/FZ, GRASP OUT, CST FFS, FEKO FFE (extra FFE columns are ignored).
M = numericBody(fp); assert(size(M, 2) >= 6, 'APAT:io:Columns', '%s files need six numeric columns.', ext);
switch ext
    case {'UAN', 'FZ'}      % Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
        names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}; src.meta.source = ['XGTD ' ext];
        Eth = magPhase(M(:, 3), M(:, 5)); Eph = magPhase(M(:, 4), M(:, 6));
    case 'OUT'              % Theta Phi Re(RHCP) Im(RHCP) Re(LHCP) Im(LHCP)
        names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; src.meta.source = 'TICRA/GRASP OUT';
        [Eth, Eph] = circularToLinear(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)));
    otherwise               % FFS: Phi Theta Re/Im(Eθ) Re/Im(Eφ);  FFE: Theta Phi Re/Im(Eθ) Re/Im(Eφ)
        names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; src.meta.source = 'FEKO FFE';
        if strcmp(ext, 'FFS'), M(:, [1 2]) = M(:, [2 1]); src.meta.source = 'CST FFS'; end
        Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
end
src.raw = array2table(M(:, 1:6), 'VariableNames', names);
src.blocks = {fieldTable(M(:, 1), M(:, 2), Eth, Eph)};
end

function src = readGenericText(fp, fmt, src)
% CSV/TXT/DAT: coverage results, gain-only pattern, or one of six E-field column conventions.
opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore', 'VariableNamingRule', 'preserve');
opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true);
T = rmmissing(readtable(fp, opts));
n = width(T); assert(n >= 2 && height(T) > 0, 'APAT:io:Columns', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHeader = ~all(startsWith(names, "Var"));
c1 = T{:, 1}; c2 = T{:, 2};
% Coverage results: strictly monotonic thresholds with percentages next to them.
coverageHint = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
if (strcmp(fmt, 'gain') || n < 6 || coverageHint) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHeader, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:n - 1))]; end
    src.raw = T; src.meta.isCoverage = true; return
end
if ~hasHeader, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
if strcmp(fmt, 'gain')       % gain-only: the angle column with the larger span is phi
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; T = movevars(T, 'Theta', 'Before', 1);
    else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    src.raw = T; src.blocks = {T}; src.meta.isGainOnly = true; src.meta.source = 'Generic text (gain)'; return
end
assert(n >= 6, 'APAT:io:Columns', 'The selected E-field format requires six numeric columns.');
V = T{:, 3:6};
if endsWith(fmt, 'magphase')
    interleaved = max(abs(V(:, 2))) > 100 && max(abs(V(:, 3))) <= 100;    % |phase| exceeds 100 while |dB| does not
    mag = [1 2]; ph = [3 4]; if interleaved, mag = [1 3]; ph = [2 4]; end
    E1 = magPhase(V(:, mag(1)), V(:, ph(1))); E2 = magPhase(V(:, mag(2)), V(:, ph(2)));
else
    E1 = complex(V(:, 1), V(:, 2)); E2 = complex(V(:, 3), V(:, 4));
end
if startsWith(fmt, 'linear'), [Eth, Eph] = deal(E1, E2);
elseif startsWith(fmt, 'rcp'), [Eth, Eph] = circularToLinear(E1, E2);
else, [Eth, Eph] = circularToLinear(E2, E1);
end
src.meta.source = sprintf('Generic text (%s)', fmt); src.raw = T;
src.blocks = {fieldTable(T{:, 1}, T{:, 2}, Eth, Eph)};
end

function src = readGraspCut(fp, src)
% TICRA/GRASP .cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks (one constant angle per block).
src.meta.source = 'TICRA/GRASP CUT';
lines = readlines(fp); lines(strlength(strtrim(lines)) == 0) = [];
[theta, phi, data] = deal({}); k = 1;
while k < numel(lines)
    p = sscanf(lines(k + 1), '%f'); assert(numel(p) >= 7, 'APAT:io:Cut', 'Could not parse the GRASP cut parameter line.');
    n = p(3); block = reshape(sscanf(strjoin(lines(k + 2:k + 1 + n), ' '), '%f'), 2 * p(7), []).';
    theta{end + 1} = p(1) + (0:n - 1)' * p(2); phi{end + 1} = repmat(p(4), n, 1); data{end + 1} = block(:, 1:4); %#ok<AGROW>
    icomp = p(5); icut = p(6); k = k + 2 + n;
end
theta = vertcat(theta{:}); phi = vertcat(phi{:}); D = vertcat(data{:});
if icut == 2, [theta, phi] = deal(phi, theta); end                            % ICUT=2: phi swept, theta constant
neg = theta < 0; phi(neg) = phi(neg) + 180; theta(neg) = -theta(neg);           % fold negative theta onto the opposite phi
if isscalar(unique(phi))                                                        % single cut → body of revolution
    copies = (0:10:350)'; m = numel(theta);
    theta = repmat(theta, numel(copies), 1); phi = repelem(copies, m); D = repmat(D, numel(copies), 1);
end
E1 = complex(D(:, 1), D(:, 2)); E2 = complex(D(:, 3), D(:, 4));
if icomp == 2, [Eth, Eph] = circularToLinear(E1, E2); names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'};
else, [Eth, Eph] = deal(E1, E2); names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; end
src.raw = array2table([theta, phi, D], 'VariableNames', [{'Theta', 'Phi'}, names]);
src.blocks = {fieldTable(theta, phi, Eth, Eph)};
end

function src = readHfssFfd(fp, src)
% HFSS .ffd: "θ0 θ1 Nθ" / "φ0 φ1 Nφ" header, optional "Frequencies ..." line, then Re/Im(Eθ) Re/Im(Eφ) rows;
% multi-frequency files repeat the grid behind "Frequency <Hz>" separator rows.
src.meta.source = 'HFSS FFD';
numbers = @(s) str2double(regexp(s, '[-+]?\d*\.?\d+([eE][-+]?\d+)?', 'match'));
lines = strtrim(readlines(fp)); lines(strlength(lines) == 0) = [];
th = numbers(lines(1)); ph = numbers(lines(2));
assert(numel(th) == 3 && numel(ph) == 3, 'APAT:io:FFD', 'FFD header (theta/phi ranges) not found.');
freqs = []; k = 3;
if startsWith(lines(3), 'freq', 'IgnoreCase', true), v = numbers(lines(3)); if numel(v) > 1, freqs = v; end, k = 4; end   % one value is only a count
body = lines(k:end); sep = startsWith(body, 'freq', 'IgnoreCase', true);
if any(sep) && isempty(freqs), freqs = cellfun(@(v) v(1), arrayfun(@(s) [numbers(s), NaN], body(sep), 'UniformOutput', false)).'; end
vals = sscanf(strjoin(body(~sep), ' '), '%f'); assert(mod(numel(vals), 4) == 0, 'APAT:io:FFD', 'FFD data rows must hold four values.');
M = reshape(vals, 4, []).';
thetaAxis = linspace(th(1), th(2), th(3)).'; phiAxis = linspace(ph(1), ph(2), ph(3)).';
theta = repelem(thetaAxis, numel(phiAxis)); phi = repmat(phiAxis, numel(thetaAxis), 1);
perBlock = numel(theta); nBlocks = size(M, 1) / perBlock;
assert(nBlocks == round(nBlocks) && nBlocks >= 1, 'APAT:io:FFD', 'FFD row count does not match the theta/phi grid.');
freqs(end + 1:nBlocks) = NaN; freqs = freqs(1:nBlocks);
src.blocks = cell(1, nBlocks);
for b = 1:nBlocks
    B = M((b - 1) * perBlock + (1:perBlock), :);
    src.blocks{b} = fieldTable(theta, phi, complex(B(:, 1), B(:, 2)), complex(B(:, 3), B(:, 4)));
end
src.freqs = freqs; src.raw = src.blocks{1}; src.meta.isDep = nBlocks > 1 || any(isfinite(freqs));
end

function src = readExcelMatrix(fp, src)
% Excel matrix workbooks: summary sheet first, then fixed component sheets (θ down column B, φ across row 2, C3 origin).
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"];
lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'APAT:io:Excel', 'Unsupported workbook: expected Etheta/Ephi and/or RHCP/LHCP gain+phase sheets after the summary sheet.');
required = strings(1, 0); if hasL, required = [required, lin]; end; if hasC, required = [required, circ]; end
M = struct(); ref = {};
for name = required
    [theta, phi, data] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, name), 1)));
    if isempty(ref), ref = {theta, phi};
    else, assert(isequal(size(theta), size(ref{1})) && isequal(size(phi), size(ref{2})) && max(abs(theta - ref{1})) < 1e-9 && max(abs(phi - ref{2})) < 1e-9, ...
            'APAT:io:Excel', 'All component sheets must share one theta/phi grid.'); end
    M.(name) = data;
end
[P, Th] = meshgrid(ref{2}, ref{1});
if hasL, Eth = magPhase(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = magPhase(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees);
else, [Eth, Eph] = circularToLinear(magPhase(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), magPhase(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees)); end
src.blocks = {fieldTable(Th, P, Eth, Eph)};
src.raw = table(Th(:), P(:), 'VariableNames', {'Theta', 'Phi'}); for name = required, src.raw.(name) = M.(name)(:); end
code = 3; if ~hasC, code = 1; elseif ~hasL, code = 2; end
src.meta.source = sprintf('Excel Matrix Format %d', code);
[src.meta.summary, fMHz] = readExcelSummary(fp, sheets(1));
if isfinite(fMHz), src.freqs = fMHz * 1e6; end
end

function [theta, phi, data] = readMatrixSheet(fp, sheet)
% One C3-origin matrix: a B2-anchored read keeps the template coordinates; text cells become NaN.
M = readmatrix(fp, 'Sheet', sheet, 'Range', 'B2', 'OutputType', 'double');
phi = M(1, 2:end); theta = M(2:end, 1);
nP = find(~isfinite(phi), 1) - 1; if isempty(nP), nP = numel(phi); end
nT = find(~isfinite(theta), 1) - 1; if isempty(nT), nT = numel(theta); end
phi = phi(1:nP).'; theta = theta(1:nT); data = M(1 + (1:nT), 1 + (1:nP));
assert(nT > 0 && nP > 0 && all(isfinite(data(:))), 'APAT:io:Excel', 'Sheet "%s" has missing axis or matrix values.', sheet);
assert(all(diff(theta) > 0) && all(diff(phi) > 0) && theta(1) >= 0 && theta(end) <= 180 && phi(1) >= 0 && phi(end) < 360, ...
    'APAT:io:Excel', 'Sheet "%s": axes must increase within theta 0..180 / phi 0..<360.', sheet);
end

function [summary, freqMHz] = readExcelSummary(fp, sheet)
% Key/value pairs of the free-form summary sheet: a text cell followed (within three cells) by a non-empty value.
C = readcell(fp, 'Sheet', sheet, 'Range', 'A1:H80'); summary = cell(0, 2); freqMHz = NaN;
blank = @(v) isempty(v) || isa(v, 'missing') || ((ischar(v) || isstring(v)) && strlength(strtrim(string(v))) == 0);
for r = 1:size(C, 1)
    c = 1;
    while c < size(C, 2)
        key = C{r, c}; nxt = find(~cellfun(blank, C(r, c + 1:min(end, c + 3))), 1);
        if ~(ischar(key) || isstring(key)) || blank(key) || isempty(nxt), c = c + 1; continue; end
        val = C{r, c + nxt}; key = char(strtrim(string(key)));
        if isnumeric(val), val = num2str(val); else, val = char(strtrim(string(val))); end
        summary(end + 1, :) = {key, val}; %#ok<AGROW>
        if isnan(freqMHz) && contains(lower(key), 'simulation freq'), freqMHz = str2double(val); end
        c = c + nxt + 1;
    end
end
end

%% =================================================================================================== numerical core
function T = normalizePattern(T)
% Canonical sphere: Theta in [0,180], Phi in [0,360) plus a closing Phi = 360 copy; only ANGLES are rounded (1e-5°).
theta = T.Theta; phi = T.Phi;
if any(theta < 0)
    if min(theta) >= -90 && max(theta) <= 90, theta = 90 - theta;                    % elevation convention
    else, neg = theta < 0; theta(neg) = -theta(neg); phi(neg) = phi(neg) + 180; end   % negative polar angle → opposite phi
end
theta = mod(theta, 360); over = theta > 180; theta(over) = 360 - theta(over); phi(over) = phi(over) + 180;
T.Theta = round(theta, 5); T.Phi = mod(round(phi, 5), 360);
[~, keep] = unique([T.Phi, T.Theta], 'rows', 'first'); T = T(keep, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360;
T = [T; seam];
end

function [P, pol] = calcPattern(S, prm, isGainOnly)
% Derive every displayed/exported quantity from the canonical primitive table (fields scaled by the loss/gain term).
pol = struct('label', 'n/a', 'basis', 'Circular', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
if isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + prm.lossDB; end
    return
end
scale = 10 ^ (prm.lossDB / 20);
Eth = complex(S.Re_Eth, S.Im_Eth) * scale; Eph = complex(S.Re_Eph, S.Im_Eph) * scale;
Er = (Eth + 1i * Eph) / sqrt(2); El = (Eth - 1i * Eph) / sqrt(2);
[aTh, aPh, aR, aL] = deal(abs(Eth), abs(Eph), abs(Er), abs(El));
total = 10 * log10(max(aTh .^ 2 + aPh .^ 2, eps));
% Dominant polarization from mean component power: drives co/cross ordering, the label and the Auto Rx sense.
p = [mean(aTh .^ 2, 'omitnan'), mean(aPh .^ 2, 'omitnan'), mean(aR .^ 2, 'omitnan'), mean(aL .^ 2, 'omitnan')];
if p(2) > p(1), pol.pairs.Linear = fliplr(pol.pairs.Linear); end
if p(4) > p(3), pol.pairs.Circular = fliplr(pol.pairs.Circular); end
if max(p(3:4)) > max(p(1:2)), pol.label = sprintf('Circular (%s)', replace(pol.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif p(1) >= p(2), pol.label = 'Linear (Vertical)'; pol.basis = 'Linear';
else, pol.label = 'Linear (Horizontal)'; pol.basis = 'Linear';
end
% Signed axial ratio: +RHCP / −LHCP sense; equal circular components are the linear limit (−100 dB floor).
delta = aR - aL; sense = sign(delta); sense(~isfinite(delta)) = 0;
ar = (aR + aL) ./ max(abs(delta), eps);
arDB = min(20 * log10(ar), 250) .* sense; arDB(abs(delta) <= eps * max(aR + aL, 1)) = -100;
% Polarization loss factor against an incident wave of axial ratio Rw (worst-case tilt: cos 2Δτ = −1).
if prm.rxMode == "Auto", wSense = 2 * (pol.pairs.Circular(1) == "E_RCP") - 1; elseif prm.rxMode == "RHCP", wSense = 1; else, wSense = -1; end
ra = ar .* sense; ra(sense == 0) = 1e12; rw = wSense * 10 ^ (prm.rxArDB / 20);
plf = 0.5 + (4 * ra * rw - (ra .^ 2 - 1) * (rw ^ 2 - 1)) ./ (2 * (ra .^ 2 + 1) * (rw ^ 2 + 1));
plfDB = 10 * log10(min(max(plf, eps), 1));
% Link quantities.
eirpDB = prm.ptDBW + total; eirpW = 10 .^ (eirpDB / 10);
dB20 = @(a) 20 * log10(max(a, eps)); ph = @(E) rad2deg(angle(E));
P = table(S.Theta, S.Phi, total, arDB, dB20(aR), dB20(aL), plfDB, total + plfDB, dB20(aTh), dB20(aPh), ph(Eth), ph(Eph), ph(Er), ph(El), ...
    eirpDB, eirpW / (4 * pi * prm.rM ^ 2), sqrt(30 * eirpW) / prm.rM, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', ...
    'PLF_dB', 'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
end

function R = resampleCanonical(S, step)
% Resample the canonical PRIMITIVE table onto a STEP° grid.  E-field sources interpolate Re/Im linearly; gain-only
% sources interpolate linear power.  Regular grids use phi-periodic interp2, irregular ones scattered interpolation.
names = S.Properties.VariableNames(3:end);
S = S(S.Phi < 360, :); theta = S.Theta; phi = S.Phi;                       % the closing seam is re-created by the target grid
tq = (0:step:180)'; pq = unique([(0:step:360)'; 360]); [PQ, TQ] = meshgrid(pq, tq);
R = table(TQ(:), PQ(:), 'VariableNames', {'Theta', 'Phi'});
[ut, ~, it] = unique(theta); [up, ~, ip] = unique(phi); regular = numel(ut) * numel(up) == numel(theta);
isGain = ~all(ismember({'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}, names));
for k = 1:numel(names)
    v = double(S.(names{k})); if isGain, v = 10 .^ (v / 10); end
    if regular
        G = nan(numel(ut), numel(up)); G(sub2ind(size(G), it, ip)) = v;
        [PG, TG] = meshgrid([up; up(1) + 360], ut); G(:, end + 1) = G(:, 1);                     % periodic phi closure
        q = interp2(PG, TG, G, PQ, TQ, 'linear');
        miss = isnan(q); if any(miss(:)), n = interp2(PG, TG, G, PQ, TQ, 'nearest'); q(miss) = n(miss); end
    else
        F = scatteredInterpolant(phi, theta, v, 'linear', 'nearest'); q = F(PQ, TQ);
    end
    if isGain, q = 10 * log10(max(q, realmin)); end
    R.(names{k}) = q(:);
end
end

function pk = resolvePeak(v, pct, excessDB)
% Authoritative peak: the raw maximum unless it exceeds the P<pct> level by more than EXCESSDB (isolated spike);
% then the highest sample at or below that level becomes the peak and the outliers are masked.
pk = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'wasAdjusted', false, 'outlierMask', false(numel(v), 1));
v = double(v(:)); finite = isfinite(v); if ~any(finite), return; end
[pk.rawValue, pk.index] = max(v); pk.value = pk.rawValue;
s = sort(v(finite)); level = s(max(1, ceil(pct / 100 * numel(s))));          % nearest-rank percentile (no toolbox)
if pk.rawValue > level + excessDB
    pk.outlierMask = finite & v > level; c = v; c(pk.outlierMask | ~finite) = -Inf;
    [pk.value, pk.index] = max(c); pk.wasAdjusted = true;
end
end

function lim = peakWindow(v, pct, excessDB)
% 50-dB display window ending at the effective peak rounded up to 5 dB.
pk = resolvePeak(v, pct, excessDB); lim = [-50 0];
if isfinite(pk.value), hi = min(100, ceil(pk.value / 5) * 5); lim = [max(-250, hi - 50), hi]; end
end

function lim = clampRange(lim)
% Sorted, clamped to [-250 100] and at least 1 dB wide.
lim = sort(double(lim(:).')); if numel(lim) ~= 2 || any(~isfinite(lim)), lim = [-40 10]; end
lim = [max(-250, lim(1)), min(100, lim(2))];
if diff(lim) < 1, lim(2) = min(100, lim(1) + 1); lim(1) = min(lim(1), lim(2) - 1); end
end

function w = solidWeights(theta, phi)
% Exact cell solid angles of a uniform θ/φ grid (half cells at the poles; the closing φ = 360 seam weighs zero).
dt = gridStep(theta); dp = gridStep(phi); if isnan(dt), dt = 180; end; if isnan(dp), dp = 360; end
w = (cosd(max(theta - dt / 2, 0)) - cosd(min(theta + dt / 2, 180))) * deg2rad(dp);
w(phi >= 360) = 0;
end

function s = gridStep(v)
d = diff(unique(v(isfinite(v)))); d = d(d > 1e-9); s = NaN; if ~isempty(d), s = min(d); end
end

function c = gainColumn(T)
if ismember('E_Total_dB', T.Properties.VariableNames), c = 'E_Total_dB'; else, c = T.Properties.VariableNames{3}; end
end

function c = preferred(prev, cols)
if any(cols == prev), c = prev; elseif any(cols == "E_Total_dB"), c = "E_Total_dB"; else, c = cols(1); end
end

function tf = isAR(name)
key = regexprep(lower(char(name)), '[^a-z0-9]', ''); tf = strcmp(key, 'ar') || startsWith(key, 'ardb') || startsWith(key, 'axialratio');
end

function s = fmtNum(v, digits)
% Compact number text: fixed decimals when DIGITS is given, otherwise up to two without trailing zeros; 'n/a' if not finite.
if ~isscalar(v) || ~isfinite(v), s = 'n/a'; return; end
if nargin > 1, s = sprintf('%.*f', digits, v); else, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); end
if strcmp(s, '-0'), s = '0'; end
end

function k = boresightAxis(T, w, gainDB, pk, axes)
% Principal axis (±X, ±Y, ±Z) whose 45° cone captures the most radiated power (peak outliers masked).
g = gainDB; if pk.wasAdjusted, g(pk.outlierMask) = NaN; end
power = 10 .^ ((g - pk.value) / 10) .* w; power(~isfinite(power)) = 0;
dirs = [sind(T.Theta) .* cosd(T.Phi), sind(T.Theta) .* sind(T.Phi), cosd(T.Theta)];
ax = [sind(axes.theta(:)) .* cosd(axes.phi(:)), sind(axes.theta(:)) .* sind(axes.phi(:)), cosd(axes.theta(:))];
[~, k] = max(power.' * double(dirs * ax.' >= cosd(45)));
end

function m = calcMetrics(T, w, gainDB, pk, axisIndex, axes)
% Scalar antenna metrics from total gain on the canonical sphere.
i = pk.index; g = gainDB; if pk.wasAdjusted, g(pk.outlierMask) = NaN; end
integrated = sum(10 .^ (g / 10) .* w, 'omitnan');
eff = 100 * integrated / (4 * pi); if eff > 100, eff = NaN; end                 % > 100 % ⇒ the source is not gain-calibrated
th0 = T.Theta(i); ph0 = T.Phi(i);
[~, back] = min(cosd(T.Theta) * cosd(th0) + sind(T.Theta) * sind(th0) .* cosd(T.Phi - ph0));
ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(i); end
if axes.theta(axisIndex) == 90, hType = 'Phi'; else, hType = 'Theta'; end     % H-plane: orthogonal principal cut
[eRows, eAng] = cutRows(T, 'Theta', axes.phi(axisIndex)); [hRows, hAng] = cutRows(T, hType, 90);
m = struct('PeakGain_dB', pk.value, 'PeakTheta_deg', th0, 'PeakPhi_deg', ph0, ...
    'HPBW_EPlane_deg', calcHPBW(eAng, gainDB(eRows)), 'HPBW_HPlane_deg', calcHPBW(hAng, gainDB(hRows)), ...
    'FrontBack_dB', pk.value - gainDB(back), 'PeakDirectivity_dB', 10 * log10(max(4 * pi * 10 ^ (pk.value / 10) / max(integrated, eps), eps)), ...
    'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', ar);
end

function [rows, ang, fixed] = cutRows(T, type, requested)
% Rows of one full great-circle cut through the canonical table with the 0..360° angle along the circle.
%   'Phi'   cut: fixed theta (nearest grid value), angle = phi.
%   'Theta' cut: fixed phi, angle = theta on that half-plane and 360 − theta on the opposite one (phi + 180).
if strcmp(type, 'Phi')
    tv = unique(T.Theta); [~, k] = min(abs(tv - requested)); fixed = tv(k);
    rows = find(T.Theta == fixed); ang = T.Phi(rows);
else
    pv = unique(T.Phi(T.Phi < 360)); wrap = @(a) abs(mod(a + 180, 360) - 180);
    [~, k] = min(wrap(pv - requested)); fixed = pv(k); [~, j] = min(wrap(pv - fixed - 180));
    r1 = find(T.Phi == fixed); r2 = find(T.Phi == pv(j) & T.Theta > 0 & T.Theta < 180); if j == k, r2 = zeros(0, 1); end
    rows = [r1; r2]; ang = [T.Theta(r1); 360 - T.Theta(r2)];
end
[ang, order] = sort(ang); rows = rows(order);
end

function [bw, lo, hi] = calcHPBW(ang, g)
% Half-power beamwidth of a closed circular cut with linear interpolation of the −3 dB crossings.
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(g); ang = ang(ok); g = g(ok);
if numel(g) < 3, return; end
[pk, i] = max(g); [rel, order] = sort(mod(ang - ang(i) + 180, 360) - 180); g = g(order); half = pk - 3;
l = find(rel < 0 & g <= half, 1, 'last'); r = find(rel > 0 & g <= half, 1, 'first');
if isempty(l) || isempty(r) || l + 1 > numel(g) || r < 2 || g(l + 1) == g(l) || g(r - 1) == g(r), return; end
cross = @(a, b) rel(a) + (rel(b) - rel(a)) * (half - g(a)) / (g(b) - g(a));
lo = ang(i) + cross(l, l + 1); hi = ang(i) + cross(r, r - 1); bw = hi - lo;
end

function cov = coverageCCDF(gainDB, mask, thr, w)
% Coverage(T) = 100 · Σ{Ω_i : G_i > T} / Σ{Ω_i} over the region, via sorted cumulative weights: O(N log N + M log N).
ok = mask(:) & isfinite(gainDB(:)) & isfinite(w(:)) & w(:) > 0;
cov = zeros(size(thr)); if ~any(ok), return; end
[g, ~, grp] = unique(gainDB(ok)); below = cumsum(accumarray(grp, w(ok))); total = below(end);
k = discretize(thr(:), [g; Inf]);                                % largest k with g(k) <= T (NaN when T < min G)
b = zeros(numel(thr), 1); b(~isnan(k)) = below(k(~isnan(k)));
cov(:) = 100 * (total - b) / total;
end