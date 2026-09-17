classdef APAT_v3_M8_22 < matlab.apps.AppBase  %1579-lines %ISSUES: %1. Interactive DataTip not working on 3D Plots (Spherical, Polar, and Surface) %2. When Switching Phi Span, while POB DataTip is enabled, it adjust the POB Datatip location/coordinate to reflect the Phi span, but it also keep the previous DataTip! %3. When loading new pattern while the older/current POB DataTip is active/enabled, it shows the new one but also keeps the old POB DataTips on the Cut Plots (the old POB DataTip shouldn't show after loading a new pattern)! %4. Coverage Threshold Query snaps to nearest Data Point instead of returning requested/query point! %5. Context menu shows warning: "Warning: You cannot set 'ContextMenu' property of DataTip." %6. POB DataTips don't use rounded (to the 4th or 5th decimal digits/precision) selected component!
% APAT v3 M8 — Antenna Pattern Analyzer Tool (single-file App Designer-free implementation).
%
%   Data flow (one direction, one canonical representation):
%     file ──readPattern──▶ source{rawTbl, blocks, freqs, meta}
%          ──canonicalize─▶ stdTbl   physical sphere: θ∈[0,180], φ∈[0,360] (closed seam)
%          ──toOneDegree?─▶          optional 1° grid (primitive quantities only)
%          ──calcPattern──▶ viewTbl  processed columns, still canonical/physical
%          ──analyzePattern▶ analysis{solidAngle, peak, boresight, metrics}
%          ──render────────▶ the φ/θ display convention is applied ONLY at the plot/table edge
%
%   Everything numerical lives in the local functions at the end of the file and never sees the app.

    properties (SetAccess = private)
        UIFigure matlab.ui.Figure
        ui struct = struct()                 % every control, created once in buildUI (see field names there)
        isClosing logical = false
    end

    properties (Access = private)
        filePath char = ''
        folderPath char = ''
        baseName char = ''
        fileName char = ''
        source struct = struct()             % readPattern output of the active file
        stdTbl table                         % canonical source block (physical angles)
        viewTbl table                        % processed pattern (canonical; never convention-transformed)
        info struct = struct()               % calcPattern info: polarization label and co/cross pairs
        analysis struct = struct()           % analyzePattern output for the current view/component
        viewRevision uint64 = 0
        gridCache struct = struct()          % display-convention grid topology/geometry + component matrices
        cutGeom struct = struct()            % last plotted cut (angles, data, physical θ/φ) for overlay/export
        gainLim double = [-40 10]            % authoritative non-AR colour scale
        fullLim double = [-40 10]            % scale currently shown on the full-pattern plots
        cutLim double = [-40 10]
        polarNorm double = 1                 % radius normalisation shared by the 3-D polar surface and its overlay
        defaults cell = {}
        rawShown logical = false
        covJobs = matlab.ui.container.TreeNode.empty
        covRunID double = 0
        covPresetKey string = ""
        covXInitialized logical = false
        statusTimer = []
        opDialog = []
        perf = @(~) []
    end

    properties (Constant, Access = private)
        Axes6 = struct('labels', {{'+Z','-Z','+X','-X','+Y','-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        ComponentNames = ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","AR_dB","Gain_PolCorrected_dB"]
        ComponentLabels = ["Total Gain","Etheta Gain","Ephi Gain","RHCP Gain","LHCP Gain","Axial Ratio","Polarized Gain"]
        HiddenColumns = ["E_TH_dB","E_PH_dB","E_TH_Phase","E_PH_Phase","E_RCP_Phase","E_LCP_Phase","EIRP_dBW","PFD_Wm2","E_RMS_Vm"]
        FileFilter = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage files'; '*.*', 'All files'}
        PeakPercentile = 99.99
        PeakMaxExcessDB = 6
        DBRange = [-250 100]
        ARRange = [-30 30]
        OneDegree = ['STEP: 1' char(176)]
        Release = 'APAT v3 M8'
    end

    %% ================================================================== lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_22
            app.buildUI();
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @startup);
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true;
            if ~isempty(app.statusTimer) && isvalid(app.statusTimer), stop(app.statusTimer); delete(app.statusTimer); end
            if ~isempty(app.opDialog) && isvalid(app.opDialog), delete(app.opDialog); end
            if isgraphics(app.UIFigure), delete(app.UIFigure); end
        end
    end

    methods (Access = private)
        function startup(app)
            u = app.ui;
            app.statusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, 'TimerFcn', @(t, ~) app.revertStatus(t));
            for ax = [u.axCtr, u.axRect], ax.Interactions = [zoomInteraction, dataTipInteraction]; end
            for ax = [u.axSph, u.axPol, u.ax3dRect], ax.Interactions = [rotateInteraction, dataTipInteraction]; end
            u.styleOn = uistyle('FontWeight', 'bold', 'FontColor', 'black', 'BackgroundColor', [0.8 1 0.8]);
            u.styleOff = uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9]);
            app.ui = u;
            app.defaults = cellfun(@(c) c.Value, {u.loss, u.rxPol, u.rw, u.pt, u.ptUnit, u.dist, u.distUnit}, 'UniformOutput', false);
            set([u.mainStatus, u.covStatus], 'UserData', 'Ready — load an antenna pattern file to begin 🚀');
            app.covAxesSetup(); app.setRange("all", app.gainLim, false); app.covUI();
        end

        function f = cb(app, method)
            % Wrap a method/anonymous function (app, src, evt) as a UI callback with uniform error handling.
            f = @(src, evt) app.guard(@() method(app, src, evt));
        end

        function guard(app, action)
            if app.isClosing, return; end
            try
                action();
            catch ME
                app.perf = @(~) [];
                if app.isClosing, return; end
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.status("main", 'Operation cancelled by user.', true); else, app.showError(ME); end
            end
        end

        function showError(app, ME)
            where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.UIFigure, [ME.message where], 'APAT Error', 'Icon', 'error');
        end

        function status(app, bar, message, transient)
            % bar = "main" | "cov". Transient messages revert to the last persistent message after 3 s.
            if app.isClosing, return; end
            label = app.ui.(char(bar + "Status")); t = app.statusTimer;
            if ~isempty(t) && isvalid(t), stop(t); end
            label.Text = char(message);
            if nargin < 4 || ~transient, label.UserData = char(message); return; end
            t.UserData = label; start(t);
        end

        function revertStatus(app, t)
            if ~app.isClosing && isgraphics(t.UserData), t.UserData.Text = t.UserData.UserData; end
        end

        function dlg = progress(app, title, message, cancelable)
            dlg = uiprogressdlg(app.UIFigure, 'Title', title, 'Message', message, 'Indeterminate', 'on', 'Cancelable', cancelable, 'CancelText', 'Abort');
            app.opDialog = dlg; drawnow;
        end

        function checkCancelled(app)
            d = app.opDialog;
            if ~isempty(d) && isvalid(d) && d.CancelRequested
                d.Message = 'Aborting...'; drawnow limitrate; error('APAT:Cancelled', 'Operation cancelled by user.');
            end
        end

        function done = startPerf(app, operation)
            % Stage timer for long operations; the report lands in the base workspace as Perf_APAT (developer aid).
            stages = cell(0, 2); t0 = tic; t = tic; app.perf = @record; done = @finish;
            function record(stage), stages(end+1, :) = {string(stage), toc(t)}; t = tic; end
            function finish()
                app.perf = @(~) [];
                assignin('base', 'Perf_APAT', struct('Operation', string(operation), 'TotalSeconds', toc(t0), ...
                    'Stages', cell2table(stages, 'VariableNames', {'Stage', 'Seconds'})));
            end
        end

        %% ============================================================== source → view pipeline
        function onLoad(app, ~, ~)
            u = app.ui; fp = strtrim(u.mainPath.Value);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.filePath)
                [f, p] = uigetfile(app.FileFilter, 'Select an antenna pattern file'); if isequal(f, 0), return; end
                fp = fullfile(p, f);
                if strcmp(fp, app.filePath) && strcmp(uiconfirm(app.UIFigure, sprintf('"%s" is already loaded.', f), 'File Already Loaded', ...
                        'Options', {'Reload', 'Cancel'}, 'CancelOption', 2), 'Cancel'), return; end
            end
            dlg = app.progress('Loading Data', 'Reading file...', true); cleaner = onCleanup(@() close(dlg)); done = app.startPerf("Load pattern"); %#ok<NASGU>
            src = app.readSource(fp, u.formatLabel, u.format); app.perf("Read file"); app.checkCancelled();
            if src.meta.isCoverage    % coverage-results files route to the Coverage tab without touching Main state
                u.tabs.SelectedTab = u.covTab; u.covPath.Value = fp; app.covLoadResults(fp, src.rawTbl); done(); return
            end
            u.mainPath.Value = fp; app.filePath = fp; [app.folderPath, app.baseName, ext] = fileparts(fp); app.fileName = [app.baseName ext];
            app.activate(src); done();
        end

        function src = readSource(app, fp, label, dropdown, cached)
            % I/O boundary. Generic text files expose the format selector (first read auto-detects with "gain"); others are self-describing.
            generic = app.isGenericText(fp);
            if nargin < 5 || isempty(cached), cached = table(); fmt = "gain"; else, fmt = string(dropdown.Value); end
            src = readPattern(fp, fmt, cached);
            show = generic && ~src.meta.isCoverage; set([label, dropdown], 'Visible', show);
            if show && isempty(cached), dropdown.Value = 'gain'; end
        end

        function activate(app, src)
            % Install a freshly read source: FFD block list, per-source UI defaults, then run the pipeline.
            u = app.ui; app.source = src; app.rawShown = false; dep = src.meta.isDep;
            set([u.ffd, u.ffdLabel], 'Visible', dep, 'Enable', dep);
            if dep
                items = compose('Pattern %d: %.4g GHz', (1:numel(src.blocks)).', src.freqs(:) / 1e9);
                missing = isnan(src.freqs(:)); items(missing) = compose('Pattern %d', find(missing));
                u.ffd.Items = items; u.ffd.Value = items{1};
            end
            u.step.Value = u.step.Items{1}; u.cutBasis.UserData = true;      % native step; auto-select the cut basis once
            app.selectBlock(1); app.refresh(true);
        end

        function selectBlock(app, k)
            T = canonicalize(app.source.blocks{k}); T.Properties.UserData = app.source.meta; app.stdTbl = T;
            if app.source.meta.isDep, app.source.rawTbl = app.source.blocks{k}; app.rawShown = false; end
        end

        function onFFD(app, ~, ~)
            u = app.ui; k = find(strcmp(u.ffd.Items, u.ffd.Value), 1); done = app.startPerf("Switch FFD block");
            u.cutBasis.UserData = true; app.selectBlock(k); app.refresh(true); done();
            app.status("main", sprintf('Switched to FFD block %d (%s).', k, u.ffd.Value), true);
        end

        function onProcess(app, ~, ~)
            if isempty(app.stdTbl), uialert(app.UIFigure, 'Load a pattern first.', 'Process', 'Icon', 'warning'); return; end
            dlg = app.progress('Processing', 'Re-processing pattern...', false); cleaner = onCleanup(@() close(dlg)); done = app.startPerf("Reprocess pattern"); %#ok<NASGU>
            if app.isGenericText(app.filePath)   % reinterpret the cached generic table with the selected text format
                src = app.readSource(app.filePath, app.ui.formatLabel, app.ui.format, app.source.rawTbl);
                assert(~src.meta.isCoverage, 'The selected generic format identifies a coverage-results file.');
                app.source = src; app.selectBlock(1); app.perf("Reinterpret source");
            end
            app.refresh(false); done();
            app.status("main", sprintf('Re-processed <b>%s</b> with the current parameters ✅', app.fileName), true);
        end

        function onFormat(app, ~, ~)
            if strcmp(strtrim(app.ui.mainPath.Value), app.filePath) && app.isGenericText(app.filePath), app.onProcess(); end
        end

        function onResetParams(app, ~, ~)
            u = app.ui; if isempty(app.defaults), return; end
            [u.loss.Value, u.rxPol.Value, u.rw.Value, u.pt.Value, u.ptUnit.Value, u.dist.Value, u.distUnit.Value] = app.defaults{:};
            if ~isempty(app.stdTbl), app.refresh(false); end
        end

        function p = getParam(app)
            u = app.ui; p = struct('GainLoss_dB', u.loss.Value, 'RxMode', string(u.rxPol.Value), 'RxAR_dB', u.rw.Value);
            p.FieldScale = 10^(p.GainLoss_dB / 20);
            if strcmp(u.ptUnit.Value, 'dBm'), p.Pt_dBW = u.pt.Value - 30;
            elseif strcmp(u.ptUnit.Value, 'Watts'), p.Pt_dBW = 10 * log10(max(u.pt.Value, eps));
            else, p.Pt_dBW = u.pt.Value; end
            p.R_m = max(u.dist.Value, 1e-12) * (1 + 999 * strcmp(u.distUnit.Value, 'km'));
        end

        function refresh(app, resetPlane)
            % stdTbl → [1° grid] → calcPattern → analysis → tables → cut → full-pattern plots.
            u = app.ui; T = app.stdTbl; steps = [gridStep(T.Theta), gridStep(T.Phi)]; steps(~isfinite(steps)) = 1;
            nonCanonical = any(abs(steps - 1) > 1e-9); wantOne = nonCanonical && strcmp(u.step.Value, app.OneDegree);
            native = sprintf('STEP: %g%c', max(steps), char(176)); u.step.Items = unique({native, app.OneDegree}, 'stable');
            set(u.step, 'Visible', nonCanonical, 'Enable', nonCanonical);
            if wantOne, u.step.Value = app.OneDegree; T = toOneDegree(T, steps); else, u.step.Value = native; end
            app.perf("Resample"); app.checkCancelled();
            [app.viewTbl, app.info] = calcPattern(T, app.getParam(), app.PeakPercentile, app.PeakMaxExcessDB);
            app.perf("Process pattern"); app.checkCancelled();
            hasE = ~app.isGainOnly();
            if u.cutBasis.UserData && hasE
                if startsWith(app.info.pol, 'Linear'), u.cutBasis.Value = 'Linear'; else, u.cutBasis.Value = 'Circular'; end
            end
            previous = u.component.Value; [cols, labels] = app.componentMap(app.viewTbl);
            app.setItems(u.component, cellstr(labels), cellstr(cols)); u.component.Value = preferredComponent(previous, cols);
            app.viewChanged("data", resetPlane);
            set([u.cutPanel, u.fullPanel, u.controlPanel, u.exportResults, u.toCoverage], 'Visible', 'on');
            set([u.exportUAN, u.cutFieldGrid], 'Visible', hasE); u.cutBasis.Enable = hasE; app.updateParamVisibility();
            pk = app.analysis.peak; pol = ''; if hasE && ~strcmpi(app.info.pol, 'n/a'), pol = [' | Polarization ' app.info.pol]; end
            app.status("main", sprintf('Pattern: %s | POB %s dB ( θ=%s°, φ=%s° )%s', app.fileName, fmtNum(pk.value, 2), ...
                fmtNum(app.viewTbl.Theta(pk.index)), fmtNum(app.viewTbl.Phi(pk.index)), pol), false);
        end

        function viewChanged(app, rangeMode, resetPlane)
            % Analysis + every view for the current viewTbl/component/convention. rangeMode: "data" | "component" | "keep".
            if nargin < 3, resetPlane = false; end
            app.viewRevision = app.viewRevision + 1; app.gridCache = struct();
            app.analysis = analyzePattern(app.viewTbl, app.comp(), app.Axes6, app.PeakPercentile, app.PeakMaxExcessDB);
            if rangeMode == "data", app.gainLim = peakWindow(chooseGain(app.viewTbl, "E_Total_dB"), [-50 0], app.PeakPercentile, app.PeakMaxExcessDB); end
            if rangeMode ~= "keep"
                if app.isAR(app.comp()), lim = app.ARRange; else, lim = app.gainLim; end
                app.setRange("full", lim, false); if rangeMode == "data", app.setRange("cut", app.gainLim, false); end
            end
            app.updateTables(); app.updateMetadata(); app.perf("Tables");
            if resetPlane, app.onPlane(); else, app.cutValues(); app.plotCut(); end
            app.renderAll(); app.perf("Plots");
        end

        function tf = isGainOnly(app), tf = isfield(app.source, 'meta') && app.source.meta.isGainOnly; end
        function tf = isGenericText(~, fp), [~, ~, e] = fileparts(fp); tf = any(strcmpi(e, {'.csv', '.txt', '.dat'})); end
        function c = comp(app), c = app.ui.component.Value; end
        function setItems(~, dd, items, data), dd.ItemsData = {}; dd.Items = items; dd.ItemsData = data; end   % never leaves Items/ItemsData mismatched
        function s = compLabel(app), u = app.ui; s = string(u.component.Items{find(strcmp(u.component.ItemsData, u.component.Value), 1)}); end

        function tf = isAR(~, name)
            key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', '');
            tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
        end

        function [cols, labels] = componentMap(app, T)
            available = string(T.Properties.VariableNames(3:end));
            if T.Properties.UserData.isGainOnly, cols = available; labels = available; return; end
            keep = ismember(app.ComponentNames, available); cols = app.ComponentNames(keep); labels = app.ComponentLabels(keep);
        end

        function v = convention(app)
            % Active display convention; the data itself stays canonical.
            u = app.ui; v.signedPhi = strcmp(u.phiSpan.Value, '-180° to 180°'); v.elevation = strcmp(u.thetaSpan.Value, '-90° to 90°');
            if v.signedPhi, v.phiLim = [-180 180]; else, v.phiLim = [0 360]; end
            if v.elevation, v.thetaLim = [-90 90]; v.thetaDir = 'normal'; v.thetaLabel = "Elevation";
            else, v.thetaLim = [0 180]; v.thetaDir = 'reverse'; v.thetaLabel = "Theta"; end
        end

        function onSpan(app, src, ~)
            u = app.ui;   % keep the same physical cut when the θ convention flips
            if isequal(src, u.thetaSpan) && strcmp(u.cutType.Value, 'Phi'), u.cutValue.Limits = [-Inf Inf]; u.cutValue.Value = 90 - u.cutValue.Value; end
            app.viewChanged("keep");
        end

        function T = displayTable(app)
            % viewTbl expressed in the selected φ/θ convention — used for the Results table and exports only.
            T = app.viewTbl; v = app.convention();
            if v.signedPhi
                T(abs(T.Phi - 360) < 1e-9, :) = []; T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
                seam = T(abs(T.Phi - 180) < 1e-9, :); seam.Phi(:) = -180; T = [T; seam];
            end
            if v.elevation, T.Theta = 90 - T.Theta; end
            if v.signedPhi || v.elevation, T = sortrows(T, {'Phi', 'Theta'}); end
        end

        %% ============================================================== tables & metadata
        function updateTables(app)
            u = app.ui; T = app.displayTable(); cols = T.Properties.VariableNames(3:end);
            if ~app.rawShown
                u.inTable.Data = app.source.rawTbl; u.inTable.ColumnName = app.source.rawTbl.Properties.VariableNames; app.rawShown = true;
            end
            if ~isequal(u.outFilter.UserData.cols, cols)          % schema changed → rebuild the column filter
                u.outFilter.UserData = struct('cols', {cols}, 'on', ~ismember(cols, app.HiddenColumns));
                app.setItems(u.outFilter, [{'--- column filter ---'}, cols], 0:numel(cols)); u.outFilter.Value = 0;
                set([u.outFilter, u.outTable, u.dataTabs], 'Visible', 'on');
            end
            app.applyFilter(T);
        end

        function onFilter(app, ~, ~)
            u = app.ui; k = u.outFilter.Value;
            if k > 0, f = u.outFilter.UserData; f.on(k) = ~f.on(k); u.outFilter.UserData = f; u.outFilter.Value = 0; end
            app.applyFilter(app.displayTable()); app.updateParamVisibility();
        end

        function applyFilter(app, T)
            u = app.ui; f = u.outFilter.UserData; items = f.cols; items(f.on) = append('✓ ', items(f.on));
            u.outFilter.Items = [{'--- column filter ---'}, items]; removeStyle(u.outFilter);
            addStyle(u.outFilter, u.styleOn, 'Item', find(f.on) + 1); addStyle(u.outFilter, u.styleOff, 'Item', find([true, ~f.on]));
            u.outTable.Data = T(:, [true, true, f.on]);
        end

        function updateParamVisibility(app)
            % Show only the parameters that feed a currently selected output column.
            u = app.ui; f = u.outFilter.UserData; sel = string(f.cols(f.on));
            set(u.rxCtls, 'Visible', any(ismember(sel, ["PLF_dB", "Gain_PolCorrected_dB"])));
            set(u.txCtls, 'Visible', any(ismember(sel, ["EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"])));
            set(u.distCtls, 'Visible', any(ismember(sel, ["PFD_Wm2", "E_RMS_Vm"])));
            set(u.lossCtls, 'Visible', app.isGainOnly() || any(ismember(sel, [app.ComponentNames, "EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"])));
        end

        function updateMetadata(app)
            u = app.ui; T = app.viewTbl; A = app.analysis; m = A.metrics; th = unique(T.Theta); ph = unique(T.Phi);
            rows = {'Source format', app.source.meta.source; 'File', app.fileName; ...
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(T), numel(th), numel(ph)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(th(1)), fmtNum(th(end)), fmtNum(gridStep(th))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(ph(1)), fmtNum(ph(end)), fmtNum(gridStep(ph)))};
            f = app.source.freqs(isfinite(app.source.freqs));
            if ~isempty(f), rows(end+1, :) = {'Frequencies', char(strjoin(compose('%.4g GHz', f(:) / 1e9), ', '))}; end
            if ~app.isGainOnly()
                rows(end+1, :) = {'Polarization', app.info.pol};
                rows(end+1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(app.info.pairs.(u.cutBasis.Value), ' / '))};
            end
            rows = [rows; {'Selected component', char(app.compLabel()); ...
                'Component peak (POB)', sprintf('%s dB @ [%s°, %s°]', fmtNum(A.peak.value), fmtNum(T.Theta(A.peak.index)), fmtNum(T.Phi(A.peak.index))); ...
                'Peak policy', sprintf('P%.4g, max excess %.4g dB (adjusted: %s)', app.PeakPercentile, app.PeakMaxExcessDB, string(A.peak.wasAdjusted)); ...
                'Boresight axis', app.Axes6.labels{A.boresight}; ...
                'Peak gain', sprintf('%s dB @ [%s°, %s°]', fmtNum(m.PeakGain_dB), fmtNum(m.PeakTheta_deg), fmtNum(m.PeakPhi_deg)); ...
                'HPBW E-plane / H-plane', sprintf('%s° / %s°', fmtNum(m.HPBW_EPlane_deg), fmtNum(m.HPBW_HPlane_deg)); ...
                'Front-to-back', sprintf('%s dB', fmtNum(m.FrontBack_dB)); 'Peak directivity', sprintf('%s dB', fmtNum(m.PeakDirectivity_dB)); ...
                'Radiation efficiency', sprintf('%s %%', fmtNum(m.Efficiency_pct)); 'AR at peak', sprintf('%s dB', fmtNum(m.AxialRatioAtPeak_dB))}];
            u.metaTable.Data = rows;
        end

        %% ============================================================== display grid (cached)
        function G = grid(app)
            % Rectangular topology + geometry of viewTbl in the DISPLAY convention, cached per view revision.
            G = app.gridCache; if isfield(G, 'rev') && G.rev == app.viewRevision, return; end
            T = app.viewTbl; v = app.convention(); th = T.Theta; ph = T.Phi; rows = (1:height(T)).';
            if v.signedPhi   % drop the physical 360° seam, map (180,360)→(−180,0) and mirror φ=180 onto −180 for closure
                mirror = find(abs(ph - 180) < 1e-9); rows = rows(ph < 360 - 1e-9); ph = ph(rows); ph(ph > 180) = ph(ph > 180) - 360;
                rows = [rows; mirror]; ph = [ph; -180 * ones(numel(mirror), 1)];
            end
            th = th(rows); if v.elevation, th = 90 - th; end
            G = struct('rev', app.viewRevision, 'rows', rows, 'theta', unique(th), 'phi', unique(ph), 'comp', struct());
            [~, it] = ismember(th, G.theta); [~, ip] = ismember(ph, G.phi); G.sz = [numel(G.theta), numel(G.phi)]; G.lin = sub2ind(G.sz, it, ip);
            [G.phiGrid, G.thetaGrid] = meshgrid(G.phi, G.theta); G.thetaPolar = G.thetaGrid; if v.elevation, G.thetaPolar = 90 - G.thetaGrid; end
            s = sind(G.thetaPolar); G.X = s .* cosd(G.phiGrid); G.Y = s .* sind(G.phiGrid); G.Z = cosd(G.thetaPolar);
            app.gridCache = G;
        end

        function C = gridOf(app, column)
            G = app.grid(); key = matlab.lang.makeValidName(column);
            if isfield(G.comp, key), C = G.comp.(key); return; end
            C = nan(G.sz); C(G.lin) = app.viewTbl.(column)(G.rows); app.gridCache.comp.(key) = C;
        end

        %% ============================================================== full-pattern plots
        function renderAll(app)
            for s = app.ui.full, app.checkCancelled(); app.render(s); end
            drawnow limitrate                      % surfaces must exist before data tips are pinned
            if app.ui.showPOB.Value, app.annotateFullPOB(); end
        end

        function render(app, s)
            G = app.grid(); C = app.gridOf(app.comp()); ax = s.axes; v = app.convention(); u = app.ui;
            [lim, cmap] = app.theme(); label = app.compLabel(); cla(ax); hold(ax, 'on');
            switch s.name
                case "contour"
                    h = pcolor(ax, G.phi, G.theta, C); set(h, 'FaceColor', 'interp', 'LineStyle', 'none');
                    app.angularAxes(ax, 30, 15); daspect(ax, [1 1 1]);
                case "circular"
                    h = surface(ax, deg2rad(G.phiGrid), G.thetaPolar, zeros(G.sz), C, 'EdgeColor', 'none');
                    app.polarTicks(ax); r = 0:30:180; if v.elevation, r = 90 - r; end
                    set(ax, 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', r)); label = label + "  |  r=θ, angle=φ";
                case {"sphere", "polar"}
                    R = 1;
                    if s.name == "polar"
                        R = max(C - lim(1), 0) / max(diff(lim), eps); app.polarNorm = max(max(R(:), [], 'omitnan'), eps); R = R / app.polarNorm;
                    end
                    h = surf(ax, R .* G.X, R .* G.Y, R .* G.Z, C, 'EdgeColor', 'none');
                    app.format3D(ax); if u.overlayCut.Value, app.overlayCut(ax, s.name, lim); end
                    label = sprintf('%s  |  θ: %s  |  φ: %s', label, u.thetaSpan.Value, u.phiSpan.Value);
                case "rect3D"
                    h = surf(ax, G.phiGrid, G.thetaGrid, C, 'EdgeColor', 'none'); app.angularAxes(ax, 60, 30); grid(ax, 'on');
                    xlabel(ax, 'Phi (degree)'); ylabel(ax, v.thetaLabel + " (degree)"); zlabel(ax, label + " (dB)", 'Interpreter', 'none'); app.applyView(ax);
            end
            h.Tag = 'APAT_Surface'; app.applyTheme(ax, lim, cmap); title(ax, label, 'Interpreter', 'none', 'FontSize', 9); hold(ax, 'off');
            app.setTips(h, [dataTipTextRow(v.thetaLabel, G.thetaGrid, '%.3g°'); dataTipTextRow("Phi", G.phiGrid, '%.3g°'); ...
                dataTipTextRow(replace(app.compLabel(), "_", "\_"), C, '%.3g dB')]);
            app.contextMenu(ax);
        end

        function [lim, cmap] = theme(app)
            % Signed axial ratio uses a blue-white-red map (default ±30 dB); gain-like components use jet. The range is fullLim.
            persistent jetMap arMap
            if isempty(jetMap), jetMap = jet(256); arMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
            lim = app.fullLim; if app.isAR(app.comp()), cmap = arMap; else, cmap = jetMap; end
        end

        function applyTheme(app, ax, lim, cmap)
            clim(ax, lim); if nargin > 3, colormap(ax, cmap); end
            bar = colorbar(ax); t = axisTicks(lim, app.ui.cStep.Value); if ~isempty(t), bar.Ticks = t; end
            if isequal(ax, app.ui.ax3dRect), zlim(ax, lim); if ~isempty(t), ax.ZTick = t; end, end
        end

        function setRange(app, scope, lim, widen)
            % Mirror a dB range to the sliders/spinners of SCOPE ("full" | "cut" | "all") and apply it to the axes.
            u = app.ui; lim = clampRange(lim, app.DBRange);
            if scope == "all", app.setRange("full", lim, widen); app.setRange("cut", lim, widen); return; end
            if scope == "full"
                sliders = [u.full.range]; pairs = [u.full.min; u.full.max]; app.fullLim = lim; u.cMin.Value = lim(1); u.cMax.Value = lim(2);
                if ~app.isAR(app.comp()), app.gainLim = lim; end
            else, sliders = u.cutRange; pairs = [u.cutMin; u.cutMax]; app.cutLim = lim;
            end
            for s = sliders   % slider travel = the range itself; spinner edits may only widen the travel
                b = lim; if widen, b = [min(s.Limits(1), lim(1)), max(s.Limits(2), lim(2))]; end
                set(s, 'Limits', app.DBRange, 'Value', lim); s.Limits = b;
            end
            for k = 1:size(pairs, 2), app.setPair(pairs(1, k), pairs(2, k), lim, 1); end
            if isempty(app.viewTbl), return; end
            if scope == "full", for s = u.full, app.applyTheme(s.axes, lim); end
            else, set(u.axPolarCut, 'RLim', lim, 'RTick', lim(1):5:lim(2)); u.axRect.YLim = lim; end
        end

        function setPair(app, minCtl, maxCtl, b, gap)
            % Set a min/max spinner pair without transient limit violations.
            set([minCtl, maxCtl], 'Limits', app.DBRange); minCtl.Value = b(1); maxCtl.Value = b(2);
            minCtl.Limits = [app.DBRange(1), b(2) - gap]; maxCtl.Limits = [b(1) + gap, app.DBRange(2)];
        end

        function angularAxes(app, ax, phiStep, thetaStep)
            v = app.convention();
            set(ax, 'XLim', v.phiLim, 'YLim', v.thetaLim, 'YDir', v.thetaDir, 'Box', 'on', 'Layer', 'top', ...
                'XTick', v.phiLim(1):phiStep:v.phiLim(2), 'YTick', v.thetaLim(1):thetaStep:v.thetaLim(2));
        end

        function polarTicks(app, pax)
            a = 0:30:330; if app.convention().signedPhi, a(a > 180) = a(a > 180) - 360; end
            set(pax, 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', a));
        end

        function format3D(app, ax)
            set(ax, 'XDir', 'normal', 'YDir', 'normal', 'ZDir', 'normal', 'Projection', 'orthographic', 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], ...
                'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1]); axis(ax, 'off');
            colors = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            for k = 1:3
                d = 1.35 * double((1:3) == k);
                quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12 * d(1), 1.12 * d(2), 1.12 * d(3), labels{k}, 'Color', colors{k}, 'FontWeight', 'bold');
            end
            app.applyView(ax);
        end

        function applyView(app, ax)
            d = [135 25]; if isequal(ax, app.ui.ax3dRect), d = [-35 35]; end
            views = struct('iso', d, 'top', [0 90], 'bottom', [0 -90], 'right', [90 0], 'left', [-90 0], 'front', [0 0], 'back', [180 0]);
            a = views.(app.ui.view3D.Value); view(ax, a(1), a(2)); up = [0 0 1]; if abs(a(2)) == 90, up = [0 1 0]; end; camup(ax, up);
        end

        function on3DView(app, ~, ~)
            if isempty(app.viewTbl), return; end
            for s = app.ui.full(3:5), app.applyView(s.axes); end; drawnow limitrate
        end

        function contextMenu(app, ax)
            % One reusable "Delete DataTips" menu per axes, shared with every child (rotation stays independent of tip mode).
            if isempty(ax.ContextMenu) || ~isvalid(ax.ContextMenu)
                m = uicontextmenu(app.UIFigure); uimenu(m, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ~) delete(findall(ax, 'Type', 'datatip')));
                ax.ContextMenu = m;
            end
            set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', ax.ContextMenu);
        end

        function setTips(~, h, rows)
            try
                h.DataTipTemplate.DataTipRows = rows;
            catch     % some surfaces only expose the template after a first tip has been created
                try, delete(datatip(h, 'DataIndex', 1)); h.DataTipTemplate.DataTipRows = rows; catch, end
            end
        end

        function refreshOverlay(app, ~, ~)
            u = app.ui; on = u.overlayCut.Value;
            for s = u.full(ismember([u.full.name], ["sphere", "polar"]))
                delete(findall(s.axes, 'Tag', 'APAT_CutOverlay')); if on, app.overlayCut(s.axes, s.name, app.fullLim); end
            end
        end

        function overlayCut(app, ax, kind, lim)
            g = app.cutGeom; if isempty(fieldnames(g)), return; end; r = 1.02;
            if kind == "polar", r = max(g.data(:, 1) - lim(1), 0) / max(diff(lim), eps) / app.polarNorm * 1.01; end
            hold(ax, 'on'); plot3(ax, r .* sind(g.theta) .* cosd(g.phi), r .* sind(g.theta) .* sind(g.phi), r .* cosd(g.theta), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay'); hold(ax, 'off');
        end

        %% ============================================================== annotations (tag-based: APAT_POB / APAT_HPBW)
        function pin(app, ax, x, y, z, rows, tag, visible)
            % Marker + pinned data tip. Objects are children of AX, so cla()/re-render disposes of them automatically.
            color = 'k'; if strcmp(tag, 'APAT_HPBW'), color = '#D95319'; end; held = ishold(ax); hold(ax, 'on');
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), m = polarplot(ax, x, y, 'o'); else, m = plot3(ax, x, y, z, 'o', 'Clipping', 'off'); end
            if ~held, hold(ax, 'off'); end
            set(m, 'MarkerSize', 5, 'Color', color, 'MarkerFaceColor', color, 'HandleVisibility', 'off', 'Tag', tag, 'Visible', visible);
            m.DataTipTemplate.DataTipRows = rows;
            t = datatip(m, 'DataIndex', 1, 'FontSize', 9, 'Tag', tag, 'Visible', visible);
            if isequal(ax, app.ui.axCtr)   % keep the tip inside the contour box at the top edge
                top = ax.YLim(2); if strcmp(ax.YDir, 'reverse'), top = ax.YLim(1); end
                if abs(y - top) < diff(ax.YLim) / 1000, if x <= mean(ax.XLim), t.Location = 'southeast'; else, t.Location = 'southwest'; end, end
            end
        end

        function annotateFullPOB(app)
            % POB marker + tip on every full-pattern surface at the display-grid cell of the component peak.
            u = app.ui; pk = app.analysis.peak; if ~isfinite(pk.value), return; end
            G = app.grid(); T = app.viewTbl; v = app.convention(); th = T.Theta(pk.index); ph = T.Phi(pk.index);
            if v.elevation, th = 90 - th; end; if v.signedPhi && ph > 180, ph = ph - 360; end
            [~, r] = min(abs(G.theta - th)); [~, c] = min(abs(G.phi - ph)); k = sub2ind(G.sz, r, c); C = app.gridOf(app.comp());
            rows = [dataTipTextRow(v.thetaLabel, G.thetaGrid(k), '%.3g°'); dataTipTextRow("Phi", G.phiGrid(k), '%.3g°'); ...
                dataTipTextRow(replace(app.compLabel(), "_", "\_"), C(k), '%.3g dB')];
            for s = u.full
                delete(findall(s.axes, 'Tag', 'APAT_POB')); h = findall(s.axes, 'Tag', 'APAT_Surface'); if isempty(h), continue; end
                if s.name == "contour", x = G.phi(c); y = G.theta(r); z = 0;
                elseif s.name == "circular", x = h.XData(k); y = h.YData(k); z = 0;
                else, x = h.XData(k); y = h.YData(k); z = h.ZData(k); end
                app.pin(s.axes, x, y, z, rows, 'APAT_POB', true);
            end
        end

        function onPOBToggled(app, ~, ~)
            on = app.ui.showPOB.Value; if on && ~isempty(app.viewTbl), app.annotateFullPOB(); end
            set(findall(app.UIFigure, 'Tag', 'APAT_POB'), 'Visible', on); drawnow limitrate nocallbacks
        end

        %% ============================================================== pattern cuts
        function values = cutValues(app)
            % Snap the cut-value spinner to the available fixed angles of the selected cut type (display convention).
            u = app.ui; T = app.viewTbl;
            if strcmp(u.cutType.Value, 'Phi'), values = unique(T.Theta); if app.convention().elevation, values = 90 - values; end
            else, values = unique(T.Phi(T.Phi < 360 - 1e-9)); end
            [~, k] = min(abs(values - u.cutValue.Value)); u.cutValue.Limits = [-Inf Inf]; u.cutValue.Value = values(k);
            u.cutValue.Limits = [min(values), max(values)]; if numel(values) > 1, u.cutValue.Step = min(diff(values)); end
        end

        function onPlane(app, ~, ~)
            % E-plane: θ-cut through the boresight-axis φ. H-plane: the orthogonal principal plane.
            u = app.ui; k = app.analysis.boresight;
            if startsWith(u.plane.Value, 'E'), u.cutType.Value = 'Theta'; want = app.Axes6.phi(k);
            elseif app.Axes6.theta(k) == 90, u.cutType.Value = 'Phi'; want = 90; if app.convention().elevation, want = 0; end
            else, u.cutType.Value = 'Theta'; want = 90; end
            values = app.cutValues(); [~, j] = min(abs(values - want)); u.cutValue.Value = values(j); app.onCut();
        end

        function onCut(app, src, ~)
            u = app.ui;
            if nargin > 1 && isequal(src, u.cutType), app.cutValues();
            elseif nargin > 1 && isequal(src, u.cutBasis), u.cutBasis.UserData = false; app.updateMetadata(); end
            u.showHPBW.Visible = u.hpbw.Value; if ~u.hpbw.Value, u.showHPBW.Value = false; end
            app.plotCut(); if u.overlayCut.Value, app.refreshOverlay(); end
        end

        function [cols, idx] = cutColumns(app)
            % Selected Total + co/cross pair columns; idx keeps line colours stable across selections.
            u = app.ui;
            if app.isGainOnly(), cols = {app.comp()}; idx = 1; return; end
            if strcmp(u.cutBasis.Value, 'Linear'), cols = {'E_Total_dB', 'E_TH_dB', 'E_PH_dB'}; else, cols = {'E_Total_dB', 'E_RCP_dB', 'E_LCP_dB'}; end
            u.cutCo.Text = cols{2}(1:end-3); u.cutCx.Text = cols{3}(1:end-3);
            sel = [u.cutTotal.Value, u.cutCo.Value, u.cutCx.Value]; if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = cols(idx);
        end

        function plotCut(app)
            if isempty(app.viewTbl), return; end
            u = app.ui; T = app.viewTbl; v = app.convention(); [cols, idx] = app.cutColumns(); cutType = u.cutType.Value;
            req = u.cutValue.Value; isPhiCut = strcmp(cutType, 'Phi'); if isPhiCut && v.elevation, req = 90 - req; end
            [ang, rows, fixed, sym, snapped] = cutRows(T, cutType, req);
            [ang, V] = displayCircle(ang, [T{rows, cols}, T.Theta(rows), T.Phi(rows)], v.signedPhi); Y = V(:, 1:numel(cols));
            app.cutGeom = struct('angle', ang, 'data', Y, 'cols', {cols}, 'theta', V(:, end-1), 'phi', V(:, end));
            shown = fixed; if isPhiCut && v.elevation, shown = 90 - fixed; end
            if snapped, app.status("main", sprintf('Requested %s cut @ %s=%g° (snapped to nearest %s=%g°)', cutType, sym, req, sym, fixed), false); end
            if app.isGainOnly(), ttl = app.comp(); else, ttl = sprintf('%s cut @ %s = %g°', cutType, sym, shown); end
            pax = u.axPolarCut; rax = u.axRect; cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on'); lim = app.cutLim;
            pl = polarplot(pax, deg2rad(ang), max(Y, lim(1)), 'LineWidth', 1.4);       % clamp: no reflection spikes below RLim
            rl = plot(rax, ang, Y, 'LineWidth', 1.4); colors = rax.ColorOrder(1 + mod(idx - 1, size(rax.ColorOrder, 1)), :);
            for k = 1:numel(cols)
                tip = [dataTipTextRow("Angle", ang, '%.3g°'), dataTipTextRow("Magnitude", Y(:, k), '%.3g dB')];
                set([pl(k), rl(k)], 'Color', colors(k, :)); pl(k).DataTipTemplate.DataTipRows = tip; rl(k).DataTipTemplate.DataTipRows = tip;
            end
            set(pax, 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.polarTicks(pax);
            set(rax, 'YLim', lim, 'XLim', v.phiLim, 'XTick', v.phiLim(1):30:v.phiLim(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, [cutType ' (degree)']); title(pax, ttl, 'Interpreter', 'none'); title(rax, ttl, 'Interpreter', 'none');
            % Peak of the displayed cut (POB) and HPBW of the first plotted column.
            [pk, ip] = max(Y(:, 1), [], 'omitnan'); u.hpbwLabel.Text = '';
            if isfinite(pk)
                tip = [dataTipTextRow("Angle", ang(ip), '%.3g°'); dataTipTextRow("Magnitude", pk, '%.3g dB')];
                app.pin(pax, deg2rad(ang(ip)), max(pk, lim(1)), 0, tip, 'APAT_POB', u.showPOB.Value); app.pin(rax, ang(ip), pk, 0, tip, 'APAT_POB', u.showPOB.Value);
                if u.hpbw.Value
                    [bw, lo, hi] = calcHPBW(ang, Y(:, 1), pk, ang(ip));
                    if isfinite(bw)
                        b = [lo, hi]; if v.signedPhi, b = mod(b + 180, 360) - 180; else, b = mod(b, 360); end
                        u.hpbwLabel.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                        if b(1) <= b(2), reg = b; else, reg = [v.phiLim(1), b(2); b(1), v.phiLim(2)]; end   % wrap-aware shading
                        thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                        xregion(rax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                        names = ["Lower HPBW", "Upper HPBW"];
                        for k = 1:2
                            tip = [dataTipTextRow(names(k), b(k), '%.2f°'); dataTipTextRow("Gain", pk - 3, '%.2f dB')];
                            app.pin(pax, deg2rad(b(k)), pk - 3, 0, tip, 'APAT_HPBW', u.showHPBW.Value); app.pin(rax, b(k), pk - 3, 0, tip, 'APAT_HPBW', u.showHPBW.Value);
                        end
                    end
                end
            end
            names = replace(string(cols), "_", "\_");
            legend(pax, pl, names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rl, names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off');
        end

        %% ============================================================== exports
        function onExportResults(app, ~, ~)
            [f, p] = uiputfile({'*.csv', 'CSV (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Results', fullfile(app.folderPath, [app.baseName '_APAT_results.csv']));
            if isequal(f, 0), return; end; fp = fullfile(p, f); writeTable(app.ui.outTable.Data, fp);   % respects the active column filter
            app.status("main", ['Results exported to <b>' fp '</b>'], true);
        end

        function onExportCut(app, ~, ~)
            g = app.cutGeom; if isempty(fieldnames(g)), return; end
            [f, p] = uiputfile({'*.csv', 'CSV (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'}, 'Export Cut', fullfile(app.folderPath, [app.baseName '_cut.csv']));
            if isequal(f, 0), return; end; fp = fullfile(p, f);
            writeTable(array2table([g.angle, g.data], 'VariableNames', [{'Angle_deg'}, g.cols]), fp);
            app.status("main", ['Cut exported to <b>' fp '</b>'], true);
        end

        function onExportUAN(app, ~, ~)
            T = app.viewTbl; U = sortrows(table(T.Theta, T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'}), {'Phi', 'Theta'});
            peak = max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan'); step = gridStep(U.Theta); if ~isfinite(step), step = 1; end
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'CSV (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'}, ...
                'Export UAN / E-field data', fullfile(app.folderPath, sprintf('%s_%.5f_%gdeg.uan', app.baseName, peak, step)));
            if isequal(f, 0), return; end; fp = fullfile(p, f);
            if endsWith(fp, '.uan', 'IgnoreCase', true)
                header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                    min(U.Phi), max(U.Phi), gridStep(U.Phi), min(U.Theta), max(U.Theta), step, peak);
                writelines(header, fp); writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
            else, writeTable(U, fp); end
            app.status("main", ['UAN exported to <b>' fp '</b>'], true);
        end

        %% ============================================================== coverage: sources & nodes
        function onToCoverage(app, ~, ~)
            % Coverage always receives the CURRENT processed view (loss, step and component set already applied).
            u = app.ui; if isempty(app.viewTbl), uialert(app.UIFigure, 'Load and process a pattern first.', 'Coverage'); return; end
            u.tabs.SelectedTab = u.covTab; u.covPath.Value = app.filePath; node = app.covFind(app.filePath);
            if isempty(node), app.covAddPattern(app.baseName, app.viewTbl, app.filePath, app.source.rawTbl);
            else, app.covSyncFromView(node); u.covTree.SelectedNodes = node; app.covUI(); end
            app.status("cov", 'Coverage source synchronized from the current Main-tab view.', false);
        end

        function onCovLoad(app, ~, ~)
            u = app.ui; fp = strtrim(u.covPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFind(fp))
                [f, p] = uigetfile(app.FileFilter, 'Select a pattern or coverage results file'); if isequal(f, 0), return; end; fp = fullfile(p, f);
            end
            existing = app.covFind(fp);
            if ~isempty(existing)
                u.covTree.SelectedNodes = existing; app.onCovSelected(); u.covPath.Value = fp; app.covUI();
                app.status("cov", 'File already loaded — node selected. Add another job or load a different file.', true); return
            end
            u.covPath.Value = fp; src = app.readSource(fp, u.covFormatLabel, u.covFormat);
            if src.meta.isCoverage, app.covLoadResults(fp, src.rawTbl);
            else, [~, name] = fileparts(fp); app.covAddPattern(name, app.buildPattern(src), fp, src.rawTbl); end
        end

        function onCovFormat(app, ~, ~)
            % Re-interpret a generic coverage-pattern node with the newly selected text format.
            u = app.ui; fp = strtrim(u.covPath.Value); old = app.covFind(fp);
            if isempty(old) || ~app.isGenericText(fp) || ~strcmp(old.NodeData.kind, 'pattern'), return; end
            src = app.readSource(fp, u.covFormatLabel, u.covFormat, old.NodeData.raw);
            if src.meta.isCoverage, app.status("cov", 'Coverage-result files are detected automatically; nothing to reprocess.', true); return; end
            name = old.NodeData.name; for j = app.covJobsUnder(old), delete(j.NodeData.line); end; delete(old);
            app.covAddPattern(name, app.buildPattern(src), fp, src.rawTbl); app.covFinalize();
            app.status("cov", sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
        end

        function P = buildPattern(app, src)
            T = canonicalize(src.blocks{1}); T.Properties.UserData = src.meta;   % multi-frequency sources use block 1
            P = calcPattern(T, app.getParam(), app.PeakPercentile, app.PeakMaxExcessDB);
        end

        function node = covAddPattern(app, name, P, path, raw)
            u = app.ui; node = uitreenode(u.covRoot, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', 'pattern', 'name', name, 'path', path, 'pattern', P, 'raw', raw, 'solidAngle', solidWeights(P.Theta, P.Phi), ...
                'revision', app.viewRevision, 'component', '', 'boresight', 1, 'cache', struct());
            expand(u.covTree); u.covTree.CheckedNodes = [u.covTree.CheckedNodes; node]; u.covTree.SelectedNodes = node;
            app.covSyncPattern(node); u.covResults.Visible = 'on'; app.covUI();
            app.status("cov", sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name), false);
        end

        function covSyncFromView(app, node)
            d = node.NodeData; d.pattern = app.viewTbl; d.solidAngle = solidWeights(app.viewTbl.Theta, app.viewTbl.Phi);
            d.revision = app.viewRevision; d.cache = struct(); node.NodeData = d; app.covSyncPattern(node);
        end

        function covSyncPattern(app, node)
            % Align the component list, detected orientation and threshold preset with the target pattern node.
            u = app.ui; d = node.NodeData; P = d.pattern; [cols, labels] = app.componentMap(P);
            previous = d.component; if isempty(previous), previous = u.covComponent.Value; end; comp = preferredComponent(previous, cols);
            if ~isequal(string(u.covComponent.ItemsData), cols), app.setItems(u.covComponent, cellstr(labels), cellstr(cols)); end
            u.covComponent.Value = comp;
            if ~strcmp(d.component, comp)
                d.component = comp; d.boresight = boresightAxis(P, comp, d.solidAngle, app.Axes6, app.PeakPercentile, app.PeakMaxExcessDB); node.NodeData = d;
                if u.covOrientation.Value == 0, app.onCovOrientation(); end       % Auto: seed the cone centre from the detected axis
            end
            key = string(sprintf('%s|%s|%d', d.path, comp, d.revision));         % threshold preset only when pattern/component/view changes
            if app.covPresetKey ~= key, app.covPresetKey = key; app.setCovThresholds(peakWindow(P.(comp), [-40 10], app.PeakPercentile, app.PeakMaxExcessDB)); end
        end

        function covLoadResults(app, fp, R)
            u = app.ui; [~, name] = fileparts(fp); node = uitreenode(u.covRoot, 'Text', ['📄 ' name]);
            node.NodeData = struct('kind', 'results', 'name', name, 'path', fp); u.covTree.CheckedNodes = [u.covTree.CheckedNodes; node];
            thr = R{:, 1}; meta = struct('conical', false, 'orientation', "n/a", 'theta', NaN, 'phi', NaN, 'angle', NaN);
            for c = 2:width(R), app.covAddJob(node, thr, R{:, c}, 'Res', R.Properties.VariableNames{c}, 'Res', 'Res', meta); end
            app.setCovX([min(thr), max(thr)], true); s = gridStep(thr); if isfinite(s) && s < u.covStep.Value, u.covStep.Value = s; end
            u.covResults.Visible = 'on'; app.covUI(); app.status("cov", sprintf('Coverage results "%s" loaded (%d curves).', name, width(R) - 1), false);
        end

        function node = covFind(app, fp)
            node = []; kids = app.ui.covRoot.Children;
            for k = 1:numel(kids), if isstruct(kids(k).NodeData) && strcmp(kids(k).NodeData.path, fp), node = kids(k); return; end, end
        end

        function node = covTarget(app)
            % Pattern node to operate on: the selection (or a job's parent pattern), else the most recent pattern node.
            u = app.ui; node = []; sel = u.covTree.SelectedNodes;
            if ~isempty(sel)
                n = sel(1); if isstruct(n.NodeData) && strcmp(n.NodeData.kind, 'job'), n = n.Parent; end
                if isstruct(n.NodeData) && strcmp(n.NodeData.kind, 'pattern'), node = n; return; end
            end
            kids = u.covRoot.Children;
            for k = numel(kids):-1:1, if isstruct(kids(k).NodeData) && strcmp(kids(k).NodeData.kind, 'pattern'), node = kids(k); return; end, end
        end

        function jobs = covJobsUnder(app, node)
            % Live job nodes (id order), optionally restricted to NODE itself or its direct children.
            app.covJobs = app.covJobs(isvalid(app.covJobs)); jobs = app.covJobs;
            if nargin > 1 && ~isempty(node) && isstruct(node.NodeData)
                if strcmp(node.NodeData.kind, 'job'), jobs = node; else, jobs = jobs(ismember(jobs, node.Children)); end
            end
        end

        %% ============================================================== coverage: compute & jobs
        function thr = covThresholds(app)
            % Current threshold controls, verbatim (presets are applied only when the pattern/component/view changes).
            u = app.ui; tMin = u.covThreshMin.Value; tMax = u.covThreshMax.Value; step = max(u.covStep.Value, 0.1);
            if tMax <= tMin, tMax = min(100, tMin + step); u.covThreshMax.Value = tMax; end
            thr = (tMin:step:tMax).'; if isempty(thr), thr = [tMin; tMax]; elseif thr(end) < tMax, thr(end+1) = tMax; end
        end

        function onCovCompute(app, ~, ~)
            u = app.ui; node = app.covTarget();
            if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if ~isempty(app.viewTbl) && strcmp(node.NodeData.path, app.filePath), app.covSyncFromView(node); end   % Main source: always the displayed view
            done = app.startPerf("Compute coverage"); d = node.NodeData; P = d.pattern; comp = u.covComponent.Value; thr = app.covThresholds();
            meta = struct('conical', u.covConical.Value, 'orientation', "n/a", 'theta', NaN, 'phi', NaN, 'angle', NaN);
            if meta.conical
                meta.theta = u.coneTheta.Value; meta.phi = mod(u.conePhi.Value, 360); meta.angle = u.coneAngle.Value;
                k = u.covOrientation.Value; if k == 0, k = d.boresight; end; meta.orientation = string(app.Axes6.labels{k});
                mask = cosd(P.Theta) * cosd(meta.theta) + sind(P.Theta) * sind(meta.theta) .* cosd(P.Phi - meta.phi) >= cosd(meta.angle);
                centre = app.coneLabel(meta.theta, meta.phi); tag = sprintf('Con_%.15g_%.15g_%.15g', meta.theta, meta.phi, meta.angle);
                label = sprintf('Conical coverage (%s) α=%s°', centre, fmtNum(meta.angle)); tableTag = sprintf('Con %s α%s°', erase(centre, ["=", ","]), fmtNum(meta.angle));
            else, mask = true(height(P), 1); tag = 'Sph'; label = 'Sph coverage'; tableTag = 'Sph';
            end
            key = matlab.lang.makeValidName(sprintf('%s_%s_%g_%g_%g_%d', comp, tag, thr(1), thr(end), gridStep(thr), numel(thr))); hit = isfield(d.cache, key);
            if hit, cov = d.cache.(key); else, cov = coverageCCDF(P.(comp), mask, thr, d.solidAngle); d.cache.(key) = cov; node.NodeData = d; end
            app.covAddJob(node, thr, cov, tag, comp, label, tableTag, meta); app.setCovX([thr(1), thr(end)], true); u.covResults.Visible = 'on'; done();
            action = 'computed'; if hit, action = 'reused cached CCDF'; end
            msg = sprintf('Run-<b>%d</b> %s: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', app.covRunID, action, label, d.name, comp, numel(thr));
            if meta.conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, meta.orientation); end
            app.status("cov", msg, false);
        end

        function label = coneLabel(app, theta, phi)
            % Principal-axis name when the cone centre coincides with ±X/±Y/±Z, otherwise the explicit θ/φ pair.
            a = app.Axes6; c = [sind(theta) * cosd(phi), sind(theta) * sind(phi), cosd(theta)];
            k = find([sind(a.theta(:)) .* cosd(a.phi(:)), sind(a.theta(:)) .* sind(a.phi(:)), cosd(a.theta(:))] * c(:) >= 1 - 1e-9, 1);
            if isempty(k), label = sprintf('θ=%s°, φ=%s°', fmtNum(theta), fmtNum(phi)); else, label = string(a.labels{k}); end
        end

        function node = covAddJob(app, parent, thr, cov, tag, comp, label, tableTag, meta)
            u = app.ui; app.covRunID = app.covRunID + 1; icon = '📉'; if strcmp(tag, 'Res'), icon = '📈'; end
            txt = sprintf('%s R%d %s · %s', icon, app.covRunID, label, comp);
            curve = plot(u.covAxes, thr, cov, 'LineWidth', 1.6, 'DisplayName', txt); node = uitreenode(parent, 'Text', txt);
            node.NodeData = struct('kind', 'job', 'id', app.covRunID, 'tag', tag, 'tableTag', tableTag, 'label', txt, 'thr', thr(:), 'cov', cov(:), 'line', curve, 'meta', meta);
            app.covJobs(end+1) = node; expand(parent); u.covTree.CheckedNodes = [u.covTree.CheckedNodes; node]; app.covFinalize();
        end

        function covFinalize(app)
            % Results table (union of checked thresholds), legend and control state.
            u = app.ui; jobs = app.covJobsUnder(); checked = jobs(ismember(jobs, u.covTree.CheckedNodes)); thr = app.covThresholds();
            if isempty(checked), legend(u.covAxes, 'off');
            else
                D = [checked.NodeData]; thr = unique(vertcat(D.thr)); legend(u.covAxes, [D.line], {D.label}, 'Location', 'southwest', 'Interpreter', 'none');
            end
            n = numel(checked); vals = nan(numel(thr), n + 1); vals(:, 1) = thr; names = cell(1, n + 1); names{1} = 'Threshold (dB)';
            for k = 1:n, d = checked(k).NodeData; vals(:, k+1) = interp1(d.thr, d.cov, thr, 'linear', NaN); names{k+1} = sprintf('R%d %s %%', d.id, d.tableTag); end
            u.covTable.Data = array2table(compose('%.2f', vals), 'VariableNames', names); app.covUI();
        end

        function covUI(app)
            u = app.ui; hasPattern = ~isempty(app.covTarget()); hasJobs = ~isempty(app.covJobsUnder());
            set(u.covPatternCtls, 'Visible', hasPattern, 'Enable', hasPattern); u.covCompute.Enable = hasPattern;
            set(u.covQueryCtls, 'Visible', hasPattern || hasJobs, 'Enable', hasJobs); set([u.covExport, u.covClear], 'Enable', hasJobs);
            u.covReset.Enable = hasPattern || hasJobs; fmt = hasPattern && app.isGenericText(u.covPath.Value);
            set([u.covFormatLabel, u.covFormat], 'Visible', fmt, 'Enable', fmt); app.onCovType();
        end

        %% ============================================================== coverage: tree, queries, ranges
        function onCovSelected(app, ~, ~)
            u = app.ui; sel = u.covTree.SelectedNodes;
            for j = app.covJobsUnder(), d = j.NodeData; d.line.LineWidth = 1.6; end
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.status("cov", 'Ready.', false); return; end
            d = sel(1).NodeData; target = app.covTarget(); if ~isempty(target), app.covSyncPattern(target); end
            if ~strcmp(d.kind, 'job')
                n = numel(sel(1).Children); kind = 'Pattern'; if strcmp(d.kind, 'results'), kind = 'Results'; end; plural = 's'; if n == 1, plural = ''; end
                app.status("cov", sprintf('%s <b>"%s"</b> — <b>%d</b> coverage job%s.', kind, d.name, n, plural), false);
                if strcmp(d.kind, 'pattern') && u.covConical.Value, app.covOrientationStatus(); end
                return
            end
            d.line.LineWidth = 2.6; t50 = app.covQueryPoint(d, "thr", 50);
            shown = round(d.cov, 2); mx = max(shown); im = find(shown == mx, 1, 'last'); if isempty(im), im = 1; end
            parts = {d.label}; if d.meta.conical, parts{end+1} = sprintf('Orientation <b>%s</b>', d.meta.orientation); end
            parts{end+1} = sprintf('Threshold [%s, %s] dB | Step %s dB', fmtNum(d.thr(1)), fmtNum(d.thr(end)), fmtNum(gridStep(d.thr)));
            if isfinite(t50), parts{end+1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', fmtNum(t50)); else, parts{end+1} = '<b>50%-coverage unavailable</b>'; end
            parts{end+1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmtNum(mx), fmtNum(d.thr(im)));
            app.status("cov", strjoin(parts, ' | '), false);
        end

        function onCovChecked(app, ~, ~)
            u = app.ui; checked = u.covTree.CheckedNodes;
            for j = app.covJobsUnder()
                on = ismember(j, checked); d = j.NodeData; d.line.Visible = on; set([app.covArtifacts(d); findall(d.line, 'Type', 'datatip')], 'Visible', on);
            end
            app.covFinalize();
        end

        function h = covArtifacts(app, d, mode)
            % Query projections live on the axes; query tips on the curve. Tags: CovQ_<mode>_<id>.
            if nargin < 3, pattern = sprintf('^CovQ_\\w+_%d$', d.id); else, pattern = sprintf('^CovQ_%s_%d$', mode, d.id); end
            h = [findall(app.ui.covAxes, '-regexp', 'Tag', pattern); findall(d.line, '-regexp', 'Tag', pattern)];
        end

        function [x, y] = covQueryPoint(~, d, mode, q)
            if mode == "cov", x = q; y = interp1(d.thr, d.cov, q, 'linear', NaN);
            else, [c, i] = unique(d.cov, 'last'); y = q; x = NaN; if numel(c) > 1, x = interp1(c, d.thr(i), q, 'linear', NaN); end; end
        end

        function onCovQuery(app, mode)
            u = app.ui; ax = u.covAxes; sel = u.covTree.SelectedNodes;
            if isempty(sel), app.status("cov", 'Select a node to query.', true); return; end
            jobs = app.covJobsUnder(sel(1)); jobs = jobs(ismember(jobs, u.covTree.CheckedNodes));
            if isempty(jobs), app.status("cov", 'No checked results under the selected node.', true); return; end
            if mode == "cov", q = u.covQueryCov.Value; else, q = u.covQueryThr.Value; end; hit = false;
            for j = jobs
                d = j.NodeData; tag = sprintf('CovQ_%s_%d', mode, d.id); delete(app.covArtifacts(d, mode));
                [x, y] = app.covQueryPoint(d, mode, q); if ~isfinite(x) || ~isfinite(y), continue; end
                app.setTips(d.line, [dataTipTextRow("Threshold", 'XData', '%.2f dB'); dataTipTextRow("Coverage", 'YData', '%.2f%%')]);
                line(ax, [x x], [ax.YLim(1) y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [app.DBRange(1) x], [y y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'HandleVisibility', 'off', 'FontSize', 9, 'Tag', tag); hit = true;
            end
            if ~hit, app.status("cov", 'Query value is outside the selected checked range.', true);
            elseif mode == "cov", app.status("cov", sprintf('Coverage queried at %s dB.', fmtNum(q)), false);
            else, app.status("cov", sprintf('Threshold queried at %s%% coverage.', fmtNum(q)), false); end
        end

        function onCovClear(app, ~, ~)
            u = app.ui; sel = u.covTree.SelectedNodes; if isempty(sel), app.status("cov", 'Select a node to clear.', true); return; end
            for j = app.covJobsUnder(sel(1)), d = j.NodeData; delete([app.covArtifacts(d); findall(d.line, 'Type', 'datatip')]); end
            app.status("cov", 'Selected data tips and query markers cleared.', true);
        end

        function onCovReset(app, ~, ~)
            u = app.ui; delete(u.covRoot.Children); app.covJobs = matlab.ui.container.TreeNode.empty; app.covRunID = 0; app.covPresetKey = "";
            cla(u.covAxes); legend(u.covAxes, 'off'); app.covAxesSetup(); u.covTable.Data = table(); u.covAxes.XLimMode = 'auto';
            app.covXInitialized = false; u.covThreshMin.UserData = false; app.setPair(u.covXMin, u.covXMax, [-40 10], 0.1);
            set(u.covXRange, 'Limits', app.DBRange, 'Value', [-40 10]); u.covResults.Visible = 'off'; app.covUI();
            app.status("cov", 'Coverage workspace reset 🔄', true);
        end

        function onCovExport(app, ~, ~)
            if isempty(app.ui.covTable.Data), return; end
            [f, p] = uiputfile({'*.csv', 'CSV (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Coverage Results', fullfile(app.folderPath, 'coverage_results.csv'));
            if isequal(f, 0), return; end; fp = fullfile(p, f); writeTable(app.ui.covTable.Data, fp);
            app.status("cov", ['Coverage results exported to ' fp], true);
        end

        function covAxesSetup(app)
            ax = app.ui.covAxes; hold(ax, 'on'); grid(ax, 'on'); ylim(ax, [0 100]); set(ax, 'Box', 'on', 'Layer', 'top');
        end

        function onCovType(app, ~, ~)
            u = app.ui; on = u.covConical.Value && ~isempty(app.covTarget()); set(u.coneCtls, 'Visible', on, 'Enable', on);
            if u.covConical.Value, n = app.covTarget(); if ~isempty(n), app.covSyncPattern(n); end; app.covOrientationStatus();
            else, u.covStatus.Text = regexprep(u.covStatus.Text, '\s*\|\s*Orientation <b>.*?</b>', ''); end
        end

        function onCovOrientation(app, ~, ~)
            % Auto seeds the cone centre from the detected axis; an explicit selection is authoritative afterwards.
            u = app.ui; k = u.covOrientation.Value;
            if k == 0, n = app.covTarget(); if isempty(n), return; end; k = n.NodeData.boresight; end
            u.coneTheta.Value = app.Axes6.theta(k); u.conePhi.Value = app.Axes6.phi(k); app.covOrientationStatus();
        end

        function covOrientationStatus(app)
            u = app.ui; if ~u.covConical.Value, return; end; k = u.covOrientation.Value;
            if k == 0, n = app.covTarget(); if isempty(n), return; end; k = n.NodeData.boresight; end
            base = regexprep(u.covStatus.Text, '\s*\|\s*Orientation <b>.*?</b>$', '');
            app.status("cov", sprintf('%s | Orientation <b>%s</b>', base, app.Axes6.labels{k}), false);
        end

        function onCovComponent(app, ~, ~)
            n = app.covTarget(); if isempty(n), return; end; d = n.NodeData; d.component = app.ui.covComponent.Value;
            d.boresight = boresightAxis(d.pattern, d.component, d.solidAngle, app.Axes6, app.PeakPercentile, app.PeakMaxExcessDB); n.NodeData = d;
            app.covOrientationStatus();
        end

        function setCovThresholds(app, b)
            % Threshold preset (50-dB peak window); after the first preset it may only widen the current user range.
            u = app.ui; b = clampRange(b, app.DBRange);
            if u.covThreshMin.UserData, b = [min(u.covThreshMin.Value, b(1)), max(u.covThreshMax.Value, b(2))]; end
            app.setPair(u.covThreshMin, u.covThreshMax, b, 0.1); u.covThreshMin.UserData = true;
        end

        function setCovX(app, b, widen)
            % Coverage X axis. Spinners are master (they define the slider travel); the slider only moves within it.
            u = app.ui; b = clampRange(b, app.DBRange);
            if widen && app.covXInitialized, b = [min(u.covAxes.XLim(1), b(1)), max(u.covAxes.XLim(2), b(2))]; end
            app.covXInitialized = true; set(u.covXRange, 'Limits', app.DBRange, 'Value', b); u.covXRange.Limits = b;
            app.setPair(u.covXMin, u.covXMax, b, 0.1); u.covAxes.XLimMode = 'manual'; u.covAxes.XLim = b;
        end

        function onCovX(app, src, evt)
            u = app.ui;
            if isequal(src, u.covXRange)
                b = sort(evt.Value); if diff(b) <= 0, return; end
                u.covXMin.Value = b(1); u.covXMax.Value = b(2); u.covAxes.XLimMode = 'manual'; u.covAxes.XLim = b;
            else
                b = [u.covXMin.Value, u.covXMax.Value];
                if diff(b) <= 0, if isequal(src, u.covXMin), b(2) = b(1) + 0.1; else, b(1) = b(2) - 0.1; end, end
                app.setCovX(b, false);
            end
        end

        %% ============================================================== UI construction (declarative)
        function h = add(~, kind, parent, row, col, varargin)
            % Create one component in a grid cell: add('button', grid, row, col, Name, Value, ...).
            switch kind
                case 'label',    h = uilabel(parent, 'HorizontalAlignment', 'right', varargin{:});
                case 'button',   h = uibutton(parent, 'push', varargin{:});
                case 'state',    h = uibutton(parent, 'state', varargin{:});
                case 'dropdown', h = uidropdown(parent, varargin{:});
                case 'spinner',  h = uispinner(parent, varargin{:});
                case 'checkbox', h = uicheckbox(parent, varargin{:});
                case 'switch',   h = uiswitch(parent, 'slider', varargin{:});
                case 'edit',     h = uieditfield(parent, 'text', varargin{:});
                case 'range',    h = uislider(parent, 'range', 'Limits', [-250 100], 'Value', [-250 100], 'Step', 1, varargin{:});
                case 'axes',     h = uiaxes(parent, varargin{:});
                case 'polar',    h = polaraxes(parent, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', varargin{:});
                case 'table',    h = uitable(parent, varargin{:});
                case 'tree',     h = uitree(parent, 'checkbox', varargin{:});
                case 'group',    h = uibuttongroup(parent, varargin{:});
                case 'panel',    h = uipanel(parent, 'FontWeight', 'bold', varargin{:});
                case 'grid',     h = uigridlayout(parent, varargin{:});
                case 'tabs',     h = uitabgroup(parent, varargin{:});
            end
            if ~isempty(row), h.Layout.Row = row; end
            if ~isempty(col), h.Layout.Column = col; end
        end

        function spec = patternTab(app, tabs, name, ttl)
            % One full-pattern tab: [max spinner; vertical range slider; min spinner] + axes.
            g = app.add('grid', uitab(tabs, 'Title', ttl), [], [], 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
            if name == "circular", ax = app.add('polar', g, [1 3], 2); else, ax = app.add('axes', g, [1 3], 2, 'Box', 'on'); end
            spec = struct('name', name, 'axes', ax, 'max', app.add('spinner', g, 1, 1, 'Limits', app.DBRange, 'Value', 10, 'Step', 5), ...
                'range', app.add('range', g, 2, 1, 'Orientation', 'vertical'), 'min', app.add('spinner', g, 3, 1, 'Limits', app.DBRange, 'Value', -40, 'Step', 5));
        end

        function dd = formatDropdown(app, parent, row, col, callback)
            dd = app.add('dropdown', parent, row, col, 'Visible', 'off', 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'ValueChangedFcn', callback, ...
                'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', '4: POL1=RCP, POL2=LCP — dB magnitude, phase', ...
                '5: POL1=LCP, POL2=RCP — dB magnitude, phase', '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'});
        end

        function buildUI(app)
            u = struct(); DB = app.DBRange; pad = @(n) repmat(char(160), 1, n);
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.Release], 'Visible', 'off', 'Position', [100 100 1136 739], ...
                'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) delete(app));
            root = app.add('grid', app.UIFigure, [], [], 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}); u.tabs = app.add('tabs', root, 1, 1);
            u.mainTab = uitab(u.tabs, 'Title', 'Process Pattern 📡'); u.covTab = uitab(u.tabs, 'Title', 'Compute Coverage 📈');
            % ---------------------------------------------------------- Main tab: inputs & parameters
            g = app.add('grid', u.mainTab, [], [], 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});
            pg = app.add('grid', app.add('panel', g, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️'), [], [], 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            app.add('label', pg, 1, 1, 'Text', 'Input Pattern:'); u.mainPath = app.add('edit', pg, 1, [2 8]);
            u.ffdLabel = app.add('label', pg, 1, 9, 'Text', 'FFD Freq:', 'Visible', 'off');
            u.ffd = app.add('dropdown', pg, 1, 10, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', app.cb(@onFFD));
            app.add('button', pg, 1, [11 12], 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', app.cb(@onLoad));
            app.add('button', pg, 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', app.cb(@onProcess));
            app.add('button', pg, 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', app.cb(@onResetParams));
            u.formatLabel = app.add('label', pg, 2, [4 5], 'Text', 'Format:', 'Visible', 'off'); u.format = app.formatDropdown(pg, 2, [6 8], app.cb(@onFormat));
            u.step = app.add('dropdown', pg, 2, [9 10], 'Items', {'STEP', app.OneDegree}, 'Visible', 'off', 'ValueChangedFcn', app.cb(@(a, ~, ~) a.refresh(false)));
            u.exportResults = app.add('button', pg, 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@onExportResults));
            u.exportUAN = app.add('button', pg, 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@onExportUAN));
            u.rxPol = app.add('dropdown', pg, 3, 2, 'Items', {'Auto', 'RHCP', 'LHCP'}); u.rw = app.add('spinner', pg, 3, 4, 'Value', 6);
            u.rxCtls = [app.add('label', pg, 3, 1, 'Text', 'Rw Sense'), u.rxPol, app.add('label', pg, 3, 3, 'Text', 'Rw (dB)'), u.rw];
            u.loss = app.add('spinner', pg, 3, 6, 'Step', 0.1); u.lossCtls = [app.add('label', pg, 3, 5, 'Text', 'Loss (−) / Gain (+) dB'), u.loss];
            u.pt = app.add('spinner', pg, 3, 8); u.ptUnit = app.add('dropdown', pg, 3, 9, 'Items', {'dBW', 'dBm', 'Watts'});
            u.txCtls = [app.add('label', pg, 3, 7, 'Text', 'Tx Pwr (Pt)'), u.pt, u.ptUnit];
            u.dist = app.add('spinner', pg, 3, 11, 'Value', 1); u.distUnit = app.add('dropdown', pg, 3, 12, 'Items', {'m', 'km'});
            u.distCtls = [app.add('label', pg, 3, 10, 'Text', 'Distance'), u.dist, u.distUnit]; set([u.rxCtls, u.lossCtls, u.txCtls, u.distCtls], 'Visible', 'off');
            u.toCoverage = app.add('button', pg, 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@onToCoverage));
            % ---------------------------------------------------------- Main tab: full-pattern plots
            u.fullPanel = app.add('panel', g, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'Visible', 'off');
            ft = app.add('tabs', app.add('grid', u.fullPanel, [], [], 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}), 1, 1);
            kinds = ["contour", "circular", "sphere", "polar", "rect3D"]; titles = {'Contour Plot', 'Circular Contour Plot', '3D Spherical Plot', '3D Polar Plot', '3D Surface Plot'};
            specs = cell(1, 5); for k = 1:5, specs{k} = app.patternTab(ft, kinds(k), titles{k}); end; u.full = [specs{:}];
            u.axCtr = u.full(1).axes; u.axSph = u.full(3).axes; u.axPol = u.full(4).axes; u.ax3dRect = u.full(5).axes;
            for k = 1:5
                u.full(k).range.ValueChangedFcn = app.cb(@(a, s, ~) a.setRange("full", s.Value, false));
                set([u.full(k).min, u.full(k).max], 'ValueChangedFcn', app.cb(@(a, ~, ~) a.setRange("full", [a.ui.full(k).min.Value, a.ui.full(k).max.Value], true)));
            end
            % ---------------------------------------------------------- Main tab: cuts
            u.cutPanel = app.add('panel', g, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'Visible', 'off');
            ct = app.add('tabs', app.add('grid', u.cutPanel, [], [], 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}), 1, 1);
            pc = app.add('grid', uitab(ct, 'Title', 'Polar Cut Plot'), [], [], 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            u.cutRange = app.add('range', pc, [2 3], 1, 'Orientation', 'vertical', 'ValueChangedFcn', app.cb(@(a, s, ~) a.setRange("cut", s.Value, false)));
            u.cutMax = app.add('spinner', pc, 1, 1, 'Limits', DB, 'Value', 10, 'Step', 5); u.cutMin = app.add('spinner', pc, 4, 1, 'Limits', DB, 'Value', -40, 'Step', 5);
            set([u.cutMin, u.cutMax], 'ValueChangedFcn', app.cb(@(a, ~, ~) a.setRange("cut", [a.ui.cutMin.Value, a.ui.cutMax.Value], true)));
            u.axPolarCut = app.add('polar', pc, [1 4], 3);
            u.hpbw = app.add('state', pc, 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', app.cb(@onCut));
            u.hpbwLabel = app.add('label', pc, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            u.cutFieldGrid = app.add('grid', pc, 3, 4, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x', '1x', '1x'});
            u.cutTotal = app.add('checkbox', u.cutFieldGrid, 1, 1, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', app.cb(@onCut));
            u.cutCo = app.add('checkbox', u.cutFieldGrid, 2, 1, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', app.cb(@onCut));
            u.cutCx = app.add('checkbox', u.cutFieldGrid, 3, 1, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', app.cb(@onCut));
            app.add('button', pc, 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', app.cb(@onExportCut));
            u.axRect = app.add('axes', app.add('grid', uitab(ct, 'Title', 'Rectangular Cut Plot'), [], [], 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}), 1, 1, 'Box', 'on');
            ylabel(u.axRect, 'Magnitude (dB)');
            % ---------------------------------------------------------- Main tab: plot control
            u.controlPanel = app.add('panel', g, 2, [13 14], 'Title', 'Plot Control 🎨', 'Visible', 'off', 'FontWeight', 'normal');
            cg = app.add('grid', u.controlPanel, [], [], 'RowHeight', repmat({'fit'}, 1, 15));
            app.add('label', cg, 1, 1, 'Text', 'Component');
            u.component = app.add('dropdown', cg, 1, 2, 'Items', cellstr(app.ComponentLabels), 'ItemsData', cellstr(app.ComponentNames), 'ValueChangedFcn', app.cb(@(a, ~, ~) a.viewChanged("component")));
            app.add('label', cg, 2, 1, 'Text', 'Cut type'); u.cutType = app.add('dropdown', cg, 2, 2, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', app.cb(@onCut));
            app.add('label', cg, 3, 1, 'Text', 'Cut value'); u.cutValue = app.add('spinner', cg, 3, 2, 'Limits', [0 360], 'ValueChangedFcn', app.cb(@onCut));
            app.add('label', cg, 4, 1, 'Text', 'Cut fields');
            u.cutBasis = app.add('dropdown', cg, 4, 2, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Enable', 'off', 'UserData', true, 'ValueChangedFcn', app.cb(@onCut));
            app.add('label', cg, 5, 1, 'Text', 'Colorbar max'); u.cMax = app.add('spinner', cg, 5, 2, 'Limits', DB, 'Value', 10);
            app.add('label', cg, 6, 1, 'Text', 'Colorbar min'); u.cMin = app.add('spinner', cg, 6, 2, 'Limits', DB, 'Value', -40);
            applyAll = app.cb(@(a, ~, ~) a.setRange("all", [a.ui.cMin.Value, a.ui.cMax.Value], true)); set([u.cMin, u.cMax], 'ValueChangedFcn', applyAll);
            app.add('label', cg, 7, 1, 'Text', 'Colorbar step'); u.cStep = app.add('spinner', cg, 7, 2, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', app.cb(@(a, ~, ~) a.setRange("full", a.fullLim, false)));
            app.add('label', cg, 8, 1, 'Text', 'Adjust Colorbar'); app.add('button', cg, 8, 2, 'Text', 'Apply', 'Tooltip', 'Apply the range to full-pattern and cut plots.', 'ButtonPushedFcn', applyAll);
            app.add('label', cg, 9, 1, 'Text', '3D view');
            u.view3D = app.add('dropdown', cg, 9, 2, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Tooltip', 'Camera direction for the 3D pattern tabs.', 'ValueChangedFcn', app.cb(@on3DView));
            u.phiSpan = app.add('switch', cg, 10, [1 2], 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'ValueChangedFcn', app.cb(@onSpan));
            u.thetaSpan = app.add('switch', cg, 11, [1 2], 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'ValueChangedFcn', app.cb(@onSpan));
            u.plane = app.add('switch', cg, 12, [1 2], 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'ValueChangedFcn', app.cb(@onPlane));
            u.overlayCut = app.add('checkbox', cg, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', app.cb(@refreshOverlay));
            u.showPOB = app.add('checkbox', cg, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', app.cb(@onPOBToggled));
            u.showHPBW = app.add('checkbox', cg, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', ...
                'ValueChangedFcn', app.cb(@(a, s, ~) set(findall(a.UIFigure, 'Tag', 'APAT_HPBW'), 'Visible', s.Value)));
            % ---------------------------------------------------------- Main tab: data tables & status
            u.outFilter = app.add('dropdown', g, 3, [13 14], 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Visible', 'off', ...
                'UserData', struct('cols', {{}}, 'on', false(1, 0)), 'ValueChangedFcn', app.cb(@onFilter));
            u.dataTabs = app.add('tabs', g, 4, [1 14], 'Visible', 'off'); one = {'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}};
            t = uitab(u.dataTabs, 'Title', 'Results 📤', 'ButtonDownFcn', @(~, ~) set(u.outFilter, 'Visible', 'on'));
            u.outTable = app.add('table', app.add('grid', t, [], [], one{:}), 1, 1, 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnRearrangeable', 'on');
            u.inTable = app.add('table', app.add('grid', uitab(u.dataTabs, 'Title', 'Input 📥'), [], [], one{:}), 1, 1, 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnRearrangeable', 'on');
            u.metaTable = app.add('table', app.add('grid', uitab(u.dataTabs, 'Title', 'Metadata 📋'), [], [], one{:}), 1, 1, 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            u.mainStatus = app.add('label', g, 5, [1 14], 'Text', 'Ready 🚀', 'Interpreter', 'html', 'HorizontalAlignment', 'left');
            % ---------------------------------------------------------- Coverage tab
            g = app.add('grid', u.covTab, [], [], 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            pg = app.add('grid', app.add('panel', g, 1, [1 5], 'Title', 'Inputs & Parameters 🎛️', 'FontWeight', 'normal'), [], [], 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'});
            u.covType = app.add('group', pg, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', app.cb(@onCovType));
            uiradiobutton(u.covType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            u.covConical = uiradiobutton(u.covType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            u.covOrientation = app.add('dropdown', pg, 3, 2, 'Items', [{'Auto'}, app.Axes6.labels], 'ItemsData', 0:6, 'ValueChangedFcn', app.cb(@onCovOrientation));
            app.add('label', pg, 1, 3, 'Text', 'Antenna Pattern:'); u.covPath = app.add('edit', pg, 1, [4 8]);
            app.add('button', pg, 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', app.cb(@onCovLoad));
            u.covCompute = app.add('button', pg, 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@onCovCompute));
            u.covThreshMin = app.add('spinner', pg, 2, 4, 'Value', -40, 'UserData', false); u.covThreshMax = app.add('spinner', pg, 2, 6, 'Value', 10); u.covStep = app.add('spinner', pg, 2, 8, 'Value', 1);
            thrLabels = [app.add('label', pg, 2, 3, 'Text', 'Threshold Min (dB):'), app.add('label', pg, 2, 5, 'Text', 'Threshold Max (dB):'), app.add('label', pg, 2, 7, 'Text', 'Step (dB):')];
            u.covReset = app.add('button', pg, 2, 9, 'Text', '🔄 Reset', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@onCovReset));
            u.covExport = app.add('button', pg, 2, 10, 'Text', '💾 Export Results', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@onCovExport));
            u.coneTheta = app.add('spinner', pg, 3, 4, 'Limits', [0 180]); u.conePhi = app.add('spinner', pg, 3, 6, 'Limits', [0 360]); u.coneAngle = app.add('spinner', pg, 3, 8, 'Limits', [0 180], 'Value', 45);
            u.coneCtls = [app.add('label', pg, 3, 1, 'Text', 'Orientation 🧭:'), u.covOrientation, app.add('label', pg, 3, 3, 'Text', 'Cone θ₀ (°):'), u.coneTheta, ...
                app.add('label', pg, 3, 5, 'Text', 'Cone φ₀ (°):'), u.conePhi, app.add('label', pg, 3, 7, 'Text', 'Cone Angle α (°):'), u.coneAngle];
            u.covClear = app.add('button', pg, 3, 9, 'Text', '🧹 Clear DataTips', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@onCovClear));
            app.add('button', pg, 3, 10, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~, ~) set(u.tabs, 'SelectedTab', u.mainTab));
            u.covComponent = app.add('dropdown', pg, 4, 2, 'Items', {'E_Total_dB'}, 'ValueChangedFcn', app.cb(@onCovComponent));
            u.covQueryCov = app.add('spinner', pg, 4, 4, 'ValueDisplayFormat', '%g dB'); u.covQueryThr = app.add('spinner', pg, 4, 7, 'Value', 50, 'ValueDisplayFormat', '%g%%');
            u.covQueryCtls = [app.add('label', pg, 4, 3, 'Text', 'Coverage @ dB:'), u.covQueryCov, app.add('button', pg, 4, 5, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', app.cb(@(a, ~, ~) a.onCovQuery("cov"))), ...
                app.add('label', pg, 4, 6, 'Text', 'Threshold @ %:'), u.covQueryThr, app.add('button', pg, 4, 8, 'Text', '🔍 Query Threshold', 'ButtonPushedFcn', app.cb(@(a, ~, ~) a.onCovQuery("thr")))];
            u.covFormatLabel = app.add('label', pg, 4, 9, 'Text', 'Format:', 'Visible', 'off'); u.covFormat = app.formatDropdown(pg, 4, 10, app.cb(@onCovFormat));
            u.covPatternCtls = [u.covType, thrLabels, u.covThreshMin, u.covThreshMax, u.covStep, u.coneCtls, app.add('label', pg, 4, 1, 'Text', 'Component:'), u.covComponent];
            u.covResults = app.add('panel', g, 2, [1 5], 'Title', 'Results', 'Visible', 'off', 'FontWeight', 'normal');
            rg = app.add('grid', u.covResults, [], [], 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            u.covTree = app.add('tree', rg, [1 2], 1, 'SelectionChangedFcn', app.cb(@onCovSelected), 'CheckedNodesChangedFcn', app.cb(@onCovChecked));
            u.covRoot = uitreenode(u.covTree, 'Text', 'Coverage Results');
            u.covAxes = app.add('axes', rg, 1, [2 4]); title(u.covAxes, 'Coverage vs Threshold'); xlabel(u.covAxes, 'Threshold (dB)'); ylabel(u.covAxes, 'Coverage (%)');
            u.covAxes.Interactions = dataTipInteraction;                     % display-only axes: no pan/zoom
            u.covTable = app.add('table', rg, [1 2], 5, 'RowName', {}, 'ColumnWidth', '1x');
            u.covXMin = app.add('spinner', rg, 2, 2, 'Limits', DB, 'Value', -40, 'ValueChangedFcn', app.cb(@onCovX));
            u.covXRange = app.add('range', rg, 2, 3, 'Value', [-40 10], 'ValueChangedFcn', app.cb(@onCovX), 'ValueChangingFcn', app.cb(@onCovX));
            u.covXMax = app.add('spinner', rg, 2, 4, 'Limits', DB, 'Value', 10, 'ValueChangedFcn', app.cb(@onCovX));
            u.covStatus = app.add('label', g, 3, [1 5], 'Text', 'Ready 🚀', 'Interpreter', 'html', 'HorizontalAlignment', 'left');
            app.ui = u; app.UIFigure.Visible = 'on';
        end
    end

    %% ================================================================== self-test
    methods (Access = public)
        function report = runSelfTest(app)
            %RUNSELFTEST Deterministic numerical smoke checks of the pure services (no UI interaction required).
            [P, T] = meshgrid(0:30:330, 0:30:180); G = table(T(:), P(:), 10 * cosd(T(:)).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            w = solidWeights(G.Theta, G.Phi); r.solidAngleError = abs(sum(w) - 4 * pi); r.passSolidAngle = r.solidAngleError < 1e-9;
            r.passOrientation = boresightAxis(G, "E_Total_dB", w, app.Axes6, app.PeakPercentile, app.PeakMaxExcessDB) == 1;
            [P2, T2] = meshgrid(0:2:358, 0:2:180); G2 = table(T2(:), P2(:), 12 * cosd(T2(:)).^2 - 0.5 * sind(P2(:)).^2, 'VariableNames', {'Theta', 'Phi', 'Gain_dB'});
            G2.Properties.UserData = struct('isGainOnly', true); R = resampleCanonical(G2, 1); native = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0 & R.Phi < 360;
            r.numericalError = max(abs(R.Gain_dB(native) - (12 * cosd(R.Theta(native)).^2 - 0.5 * sind(R.Phi(native)).^2)));
            r.passResampling = height(R) == 181 * 361 && r.numericalError < 1e-9;
            r.passPeakWindow = isequal(peakWindow([3.2; -250; -17], [-50 0], app.PeakPercentile, app.PeakMaxExcessDB), [-45 5]);
            spike = repmat(0.02, 1e5, 1); spike(1) = 10.02; pk = resolvePeak(spike, app.PeakPercentile, app.PeakMaxExcessDB);
            r.passIsolatedSpike = pk.wasAdjusted && abs(pk.value - 0.02) < 1e-12 && pk.rawIndex == 1;
            r.passCoverage = isequal(coverageCCDF([0; 10; 20; 30], true(4, 1), [-5; 5; 15; 25; 35], ones(4, 1)), [100; 75; 50; 25; 0]);
            r.passHPBW = abs(calcHPBW((0:359).', 10 * cosd(0:359).', 10, 0) - 90) < 1e-9;
            r.passARSemantic = all(arrayfun(@(s) app.isAR(s), ["AR", "AR_dB", "AR dB", "Axial Ratio", "Axial_Ratio"]));
            f = [tempname '.ffd']; writelines(["0 180 3"; "-180 180 3"; compose("%d 0 0 1", (1:9).')], f); cleaner = onCleanup(@() delete(f)); %#ok<NASGU>
            d = readPattern(f, "ffd", table()); r.passFFDReader = strcmp(d.meta.source, 'HFSS FFD') && isscalar(d.blocks) && height(d.blocks{1}) == 9;
            names = fieldnames(r); failed = names(cellfun(@(n) startsWith(n, 'pass') && ~r.(n), names)); report = r; report.pass = isempty(failed);
            if ~report.pass, error('APAT:SelfTestFailed', 'Self-test failed: %s', strjoin(failed, ', ')); end
        end
    end
end

%% ====================================================================== I/O services (pure)
function out = readPattern(fp, fmt, cached)
%readPattern Read any supported source into {rawTbl, blocks{}, freqs, meta}. Blocks are canonical-ready E-field or gain tables.
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, 'meta', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false));
switch ext
    case {'XLSX', 'XLS'}, out = readExcelMatrix(fp); return
    case {'CSV', 'TXT', 'DAT'}, out = readGenericText(fp, string(fmt), cached, out); return
    case 'CUT', out = readGraspCut(fp, out); return
end
[nHdr, ffd] = headerInfo(fp);
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = readmatrix(fp, setvartype(opts, 'double')); M = M(~all(isnan(M), 2), 1:min(end, 6));
switch ext
    case {'FZ', 'UAN'}   % XGTD: Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
        names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}; src = ['XGTD ' ext]; th = M(:, 1); ph = M(:, 2);
        Eth = polarField(M(:, 3), M(:, 5)); Eph = polarField(M(:, 4), M(:, 6));
    case 'OUT'           % TICRA/GRASP: Theta Phi Re(RHCP) Im(RHCP) Re(LHCP) Im(LHCP)
        names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; src = 'TICRA/GRASP OUT'; th = M(:, 1); ph = M(:, 2);
        [Eth, Eph] = circularToLinear(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)));
    case 'FFS'           % CST: Phi Theta Re(Eth) Im(Eth) Re(Eph) Im(Eph)
        names = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; src = 'CST FFS'; ph = M(:, 1); th = M(:, 2);
        Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
    case 'FFE'           % FEKO: Theta Phi Re(Eth) Im(Eth) Re(Eph) Im(Eph) [extra columns ignored]
        names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; src = 'FEKO FFE'; th = M(:, 1); ph = M(:, 2);
        Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
    case 'FFD'           % HFSS: header axes; Re(Eth) Im(Eth) Re(Eph) Im(Eph) per block; optional "Frequency f" separator rows
        assert(ffd.isFFD, 'readFile:ffd', 'FFD header (theta/phi ranges) not found.'); out.meta.source = 'HFSS FFD';
        thAxis = linspace(ffd.theta(1), ffd.theta(2), ffd.theta(3)).'; phAxis = linspace(ffd.phi(1), ffd.phi(2), ffd.phi(3)).';
        th = repelem(thAxis, numel(phAxis)); ph = repmat(phAxis, numel(thAxis), 1); n = numel(th);
        sep = isnan(M(:, 1)); f = M(sep, 2); freqs = [ffd.freq(:); f(~isnan(f))].'; rows = M(~sep, 1:4);
        assert(mod(size(rows, 1), n) == 0, 'readFile:ffd', 'FFD row count does not match the theta/phi grid.');
        nb = size(rows, 1) / n; freqs(end+1:nb) = NaN; out.freqs = freqs(1:nb); out.meta.isDep = nb > 1 || any(isfinite(out.freqs));
        out.blocks = cell(1, nb);
        for b = 1:nb, B = rows((b-1)*n + (1:n), :); out.blocks{b} = fieldTable(th, ph, complex(B(:, 1), B(:, 2)), complex(B(:, 3), B(:, 4))); end
        out.rawTbl = out.blocks{1}; return
    otherwise, error('readFile:unsupported', 'Unsupported format: %s', ext);
end
out.meta.source = src; out.rawTbl = array2table(M(:, 1:6), 'VariableNames', names); out.blocks = {fieldTable(th, ph, Eth, Eph)};
end

function [nHdr, ffd] = headerInfo(fp)
%headerInfo Leading non-data line count; recognises the HFSS FFD header (two θ/φ triples + optional "Frequencies" line).
lines = readlines(fp); nonEmpty = find(strlength(strtrim(lines)) > 0); ffd = struct('isFFD', false, 'theta', [], 'phi', [], 'freq', []);
triples = zeros(0, 3); last = 0;
for i = nonEmpty(1:min(2, end)).'
    v = sscanf(lines(i), '%f').'; if numel(v) ~= 3, break; end; triples(end+1, :) = v; last = i; %#ok<AGROW>
end
if size(triples, 1) == 2 && all(isfinite(triples(:))) && all(triples(:, 3) >= 1)
    ffd.isFFD = true; ffd.theta = triples(1, :); ffd.phi = triples(2, :); nHdr = last; j = nonEmpty(find(nonEmpty > last, 1));
    if ~isempty(j)
        tok = regexp(strtrim(lines(j)), '^frequencies?\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok), nHdr = j; f = sscanf(tok{1}, '%f'); if ~isscalar(f), ffd.freq = f(:); end, end   % "Frequencies N" alone is only a count
    end
    return
end
num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?';                                                  % first line with ≥4 numeric fields
first = find(~cellfun(@isempty, regexp(cellstr(lines), ['^\s*' num '(?:[\s,;]+' num '){3,}\s*$'], 'once')), 1);
if isempty(first), nHdr = 0; else, nHdr = first - 1; end
end

function out = readGenericText(fp, fmt, T, out)
%readGenericText CSV/TXT/DAT: coverage-results table, gain-only pattern, or a 6-column E-field table interpreted per FMT.
if isempty(T)
    opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve'; T = rmmissing(readtable(fp, opts));
end
nc = width(T); assert(nc >= 2 && height(T) > 0, 'readFile:InvalidFormat', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHeaders = ~all(startsWith(names, "Var")); c1 = T{:, 1}; c2 = T{:, 2};
coverageHeader = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
if (fmt == "gain" || nc < 6 || coverageHeader) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:nc-1))]; end
    out.rawTbl = T; out.meta.isCoverage = true; return
end
if fmt == "gain"          % gain-only: the wider-spanning of the first two columns is φ
    raw = T;
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; T = movevars(T, 'Theta', 'Before', 1);
    else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    if ~hasHeaders, raw = T; end; out.rawTbl = raw; out.blocks = {T}; out.meta.isGainOnly = true; return
end
assert(nc >= 6, 'readFile:TextEFieldColumns', 'The selected E-field format requires six numeric columns.');
V = T{:, 3:6}; magPhase = endsWith(fmt, "magphase"); interleaved = false;
if magPhase                % auto-detect [mag phase mag phase] vs [mag mag phase phase] from the phase magnitude
    interleaved = max(abs(V(:, 2)), [], 'omitnan') > 100 && max(abs(V(:, 3)), [], 'omitnan') <= 100;
    if interleaved, e1 = polarField(V(:, 1), V(:, 2)); e2 = polarField(V(:, 3), V(:, 4)); else, e1 = polarField(V(:, 1), V(:, 3)); e2 = polarField(V(:, 2), V(:, 4)); end
else, e1 = complex(V(:, 1), V(:, 2)); e2 = complex(V(:, 3), V(:, 4));
end
if startsWith(fmt, "linear"), Eth = e1; Eph = e2; comp = ["E_TH", "E_PH"]; reim = ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"];
elseif startsWith(fmt, "rcp"), [Eth, Eph] = circularToLinear(e1, e2); comp = ["POL1", "POL2"]; reim = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"];
else, [Eth, Eph] = circularToLinear(e2, e1); comp = ["POL1", "POL2"]; reim = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"]; end
if ~hasHeaders
    if magPhase, f = [comp + "_dB", comp + "_deg"]; if interleaved, f = f([1 3 2 4]); end, else, f = reim; end
    T.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", f]);
end
layout = "not applicable"; if magPhase, layout = "grouped"; if interleaved, layout = "interleaved"; end, end
out.meta.source = sprintf('Generic text (%s, %s)', fmt, layout); out.rawTbl = T; out.blocks = {fieldTable(T{:, 1}, T{:, 2}, Eth, Eph)};
end

function out = readGraspCut(fp, out)
%readGraspCut TICRA GRASP *.cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks.
out.meta.source = 'TICRA/GRASP CUT'; lines = readlines(fp); lines(strlength(strtrim(lines)) == 0) = [];
th = {}; ph = {}; D = {}; i = 1; icomp = 1; icut = 1;
while i < numel(lines)
    p = sscanf(lines(i + 1), '%f'); assert(numel(p) >= 7, 'readFile:cut', 'Could not parse a GRASP cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6); blk = reshape(sscanf(strjoin(lines(i + 2:i + 1 + n), ' '), '%f'), 2 * p(7), []).';
    th{end+1, 1} = p(1) + (0:n-1).' * p(2); ph{end+1, 1} = repmat(p(4), n, 1); D{end+1, 1} = blk(:, 1:4); i = i + 2 + n; %#ok<AGROW>
end
th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:});
if icut == 2, [th, ph] = deal(ph, th); end                                    % ICUT=2: φ swept, θ constant
neg = th < 0; th(neg) = -th(neg); ph(neg) = ph(neg) + 180;                     % fold negative θ onto the opposite φ
if isscalar(unique(ph)), ph = repelem((0:10:350).', numel(ph)); th = repmat(th, 36, 1); D = repmat(D, 36, 1); end   % single cut → body of revolution
c1 = complex(D(:, 1), D(:, 2)); c2 = complex(D(:, 3), D(:, 4));
if icomp == 2, names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; [Eth, Eph] = circularToLinear(c1, c2);
else, names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; Eth = c1; Eph = c2; end
out.rawTbl = array2table([th, ph, D], 'VariableNames', [{'Theta', 'Phi'}, names]); out.blocks = {fieldTable(th, ph, Eth, Eph)};
end

function out = readExcelMatrix(fp)
%readExcelMatrix Excel matrix workbooks: sheet 1 = summary; fixed component sheets (Format 1 Eth/Eph, 2 RHCP/LHCP, 3 both).
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"]; lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'readFile:ExcelMatrixFormat', 'Unsupported Excel workbook: expected Etheta/Ephi and/or RHCP/LHCP gain+phase component sheets after the summary sheet.');
required = [circ(1:4 * hasC), lin(1:4 * hasL)]; M = struct(); th = []; ph = [];
for name = required
    [t, p, data] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, name), 1)));
    if isempty(th), th = t; ph = p;
    else, assert(isequal(size(t), size(th)) && isequal(size(p), size(ph)) && max(abs(t - th)) < 1e-9 && max(abs(p - ph)) < 1e-9, 'readFile:ExcelMatrixGrid', 'All component sheets must share the same theta/phi grid.');
    end
    M.(char(name)) = data;
end
if hasL, Eth = polarField(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = polarField(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees);
else, [Eth, Eph] = circularToLinear(polarField(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), polarField(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees)); end
[P, T] = meshgrid(ph, th); block = fieldTable(T, P, Eth, Eph); raw = block;
for name = required, raw.(char(name)) = M.(char(name))(:); end               % keep the workbook quantities inspectable
meta = readExcelSummary(fp, sheets(1)); kinds = ["Format 1 (Eth/Eph)", "Format 2 (Ercp/Elcp)", "Format 3 (Ercp/Elcp + Eth/Eph)"];
meta.source = char("Excel Matrix " + kinds(hasL + 2 * hasC)); meta.isGainOnly = false; meta.isCoverage = false; meta.isDep = false;
out = struct('rawTbl', raw, 'blocks', {{block}}, 'freqs', NaN, 'meta', meta);
end

function [theta, phi, data] = readMatrixSheet(fp, sheet)
%readMatrixSheet One C3-origin matrix: row 2 = φ axis (C…), column B = θ axis (3…). readcell keeps worksheet coordinates.
C = readcell(fp, 'Sheet', char(sheet)); assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'readFile:ExcelMatrixSheet', 'Sheet "%s" does not contain a C3-origin matrix.', sheet);
isNum = @(cells) cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), cells); pm = isNum(C(2, 3:end)); tm = isNum(C(3:end, 2));
nP = find(~pm, 1) - 1; if isempty(nP), nP = numel(pm); end; nT = find(~tm, 1) - 1; if isempty(nT), nT = numel(tm); end
assert(nP > 0 && nT > 0 && ~any(pm(nP+1:end)) && ~any(tm(nT+1:end)), 'readFile:ExcelMatrixAxis', 'Sheet "%s" has a missing or non-contiguous theta/phi axis.', sheet);
phi = cell2mat(C(2, 3:2+nP)).'; theta = cell2mat(C(3:2+nT, 2)); cells = C(3:2+nT, 3:2+nP);
assert(all(isNum(cells), 'all'), 'readFile:ExcelMatrixSheet', 'Sheet "%s" contains non-numeric/missing matrix samples.', sheet); data = cell2mat(cells);
assert(all(diff(theta) > 0) && all(diff(phi) > 0) && theta(1) >= -1e-9 && theta(end) <= 180 + 1e-9 && phi(1) >= -1e-9 && phi(end) < 360 + 1e-9, ...
    'readFile:ExcelMatrixAxis', 'Sheet "%s" axes must be strictly increasing within θ∈[0,180], φ∈[0,360).', sheet);
end

function meta = readExcelSummary(fp, sheet)
%readExcelSummary Summary sheet → struct: every "Label:" in column B with its first value in C..E, plus frequency and frame fields.
C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); isText = cellfun(@(x) ischar(x) || isstring(x), C); labels = strings(size(C));
labels(isText) = regexprep(replace(lower(strtrim(string(C(isText)))), {char(160), char(8211), char(8212), char(8722)}, {' ', '-', '-', '-'}), '\s+', ' ');
meta = struct(); value = @(r) firstValue(C(r, 3:min(end, 5)));
for r = find(isText(:, 2)).'
    key = matlab.lang.makeValidName(regexprep(labels(r, 2), '[^a-z0-9]+', '_')); v = value(r); if ~isempty(v), meta.(char(key)) = v; end
end
meta.frequencyMHz = NaN; r = find(labels(:, 2) == "pattern simulation freq (mhz):", 1); if ~isempty(r), meta.frequencyMHz = toDouble(value(r)); end
meta.frameAzEl = NaN(3, 2); dirs = ["+x direction", "+y direction", "+z direction"];
for k = 1:3, [r, ~] = find(labels == dirs(k), 1); if ~isempty(r), meta.frameAzEl(k, :) = [toDouble(C{r, 7}), toDouble(C{r, 8})]; end, end
end

function v = firstValue(cells)
v = []; for c = cells, x = c{1}; if ~isempty(x) && ~isa(x, 'missing'), v = x; return; end, end
end

function v = toDouble(x)
if isnumeric(x) && ~isempty(x), v = double(x(1)); elseif ischar(x) || isstring(x), v = str2double(strtrim(string(x))); else, v = NaN; end
end

function E = polarField(dB, deg), E = 10.^(dB / 20) .* exp(1i * deg2rad(deg)); end
function [Eth, Eph] = circularToLinear(Ercp, Elcp), Eth = (Ercp + Elcp) / sqrt(2); Eph = (Ercp - Elcp) / (1i * sqrt(2)); end
function T = fieldTable(theta, phi, Eth, Eph)
T = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function writeTable(T, fp)
if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
end

%% ====================================================================== pattern model (pure)
function T = canonicalize(T)
%canonicalize Map angles onto the physical sphere: θ∈[0,180], φ∈[0,360) plus one closing φ=360 copy. Only ANGLES are rounded (1e-5°).
T = T(isfinite(T.Theta) & isfinite(T.Phi), :); th = T.Theta; ph = T.Phi;
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, th = 90 - th;                                   % elevation source
    else, ph(th < 0) = ph(th < 0) + 180; th = abs(th); end                                % signed polar source
end
th = mod(th, 360); over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;
T.Theta = round(th, 5); T.Phi = mod(round(ph, 5), 360);
[~, keep] = unique([T.Phi, T.Theta], 'rows', 'first'); T = T(keep, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function T = toOneDegree(T, steps)
%toOneDegree 1° canonical grid: decimate exact integer-degree samples when the source is a finer sub-multiple, otherwise resample.
meta = T.Properties.UserData;
if all(steps < 1) && all(abs(1 ./ steps - round(1 ./ steps)) < 1e-6)
    T = T(abs(T.Theta - round(T.Theta)) < 1e-9 & abs(T.Phi - round(T.Phi)) < 1e-9, :);
else, T = resampleCanonical(T, 1); end
T.Properties.UserData = meta;
end

function R = resampleCanonical(S, step)
%resampleCanonical Resample canonical primitives onto a STEP° grid (θ 0..180, φ 0..360 closed). E-field Re/Im are interpolated
%   independently; gain-like dB columns in linear power. Complete grids use φ-periodic interp2, irregular data scatteredInterpolant.
keep = find(abs(S.Phi - 360) > 1e-9); [~, u] = unique([S.Theta(keep), mod(S.Phi(keep), 360)], 'rows', 'stable'); rows = keep(u);
th = S.Theta(rows); ph = mod(S.Phi(rows), 360); ta = unique(th); pa = unique(ph);
[QP, QT] = meshgrid(0:step:360, 0:step:180); if QP(1, end) ~= 360, QP(:, end+1) = 360; QT(:, end+1) = QT(:, 1); end
R = table(QT(:), QP(:), 'VariableNames', {'Theta', 'Phi'}); regular = numel(ta) * numel(pa) == numel(th);
if regular, [~, it] = ismember(th, ta); [~, ip] = ismember(ph, pa); lin = sub2ind([numel(ta), numel(pa)], it, ip); regular = numel(unique(lin)) == numel(lin); end
isField = all(ismember(["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"], S.Properties.VariableNames));
for name = string(S.Properties.VariableNames(3:end))
    v = double(S.(char(name))(rows)); linearPower = ~isField && isGainDB(name); if linearPower, v = 10.^(v / 10); end
    if regular
        G = nan(numel(ta), numel(pa)); G(lin) = v; [PG, TG] = meshgrid(pa, ta);
        if pa(end) < pa(1) + 360 - 1e-9, PG(:, end+1) = pa(1) + 360; TG(:, end+1) = ta; G(:, end+1) = G(:, 1); end     % periodic closure in φ
        q = interp2(PG, TG, G, QP, QT, 'linear', NaN); miss = ~isfinite(q);
        if any(miss(:)), near = interp2(PG, TG, G, QP, QT, 'nearest', NaN); q(miss) = near(miss); end
    else
        F = scatteredInterpolant(ph, th, v, 'linear', 'nearest'); q = F(QP, QT);
    end
    if linearPower, q = 10 * log10(max(q, realmin)); end
    R.(char(name)) = q(:);
end
R.Properties.UserData = S.Properties.UserData;
end

function tf = isGainDB(name)
key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', ''); tf = contains(key, 'gain') || contains(key, 'directivity') || contains(key, 'eirp') || endsWith(key, 'db');
end

function [P, info] = calcPattern(S, prm, pct, excess)
%calcPattern Canonical source → processed pattern table + polarization info. Pure; never touches the UI.
meta = S.Properties.UserData; info = struct('pol', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
if meta.isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + prm.GainLoss_dB; end; return
end
Eth = complex(S.Re_Eth, S.Im_Eth) * prm.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph) * prm.FieldScale;
Ercp = (Eth + 1i * Eph) / sqrt(2); Elcp = (Eth - 1i * Eph) / sqrt(2);
mTh = abs(Eth); mPh = abs(Eph); mR = abs(Ercp); mL = abs(Elcp); total = 10 * log10(max(mTh.^2 + mPh.^2, eps));
% Dominant components (mean power) drive co/cross ordering, the polarization label and the Auto Rx sense.
pw = [mean(mTh.^2, 'omitnan'), mean(mPh.^2, 'omitnan'), mean(mR.^2, 'omitnan'), mean(mL.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif pw(1) >= pw(2), info.pol = 'Linear (Vertical)'; else, info.pol = 'Linear (Horizontal)'; end
% Signed axial ratio (+ right-hand, − left-hand); equal circular components are the linear limit → −100 dB floor.
d = mR - mL; sense = sign(d); sense(~isfinite(d)) = 0; AR = (mR + mL) ./ max(abs(d), eps);
ARdB = min(20 * log10(AR), 250) .* sense; ARdB(isfinite(d) & abs(d) <= eps * max(mR + mL, 1)) = -100;
% Polarization loss factor against an incident wave of axial ratio Rw (worst-case tilt alignment, cos 2Δτ = −1).
if prm.RxMode == "Auto", ws = 2 * (info.pairs.Circular(1) == "E_RCP") - 1; elseif prm.RxMode == "RHCP", ws = 1; else, ws = -1; end
Ra = AR .* sense; Ra(sense == 0) = 1e12; Rw = ws * 10^(prm.RxAR_dB / 20);
plf = 0.5 + (4 * Ra * Rw - (Ra.^2 - 1) * (Rw^2 - 1)) ./ (2 * (Ra.^2 + 1) * (Rw^2 + 1)); plfDB = 10 * log10(min(max(plf, eps), 1));
eirp = prm.Pt_dBW + total; eirpW = 10.^(eirp / 10); dB = @(m) 20 * log10(max(m, eps)); phase = @(E) rad2deg(angle(E));
P = table(S.Theta, S.Phi, total, ARdB, dB(mR), dB(mL), plfDB, total + plfDB, dB(mTh), dB(mPh), phase(Eth), phase(Eph), phase(Ercp), phase(Elcp), ...
    eirp, eirpW / (4 * pi * prm.R_m^2), sqrt(30 * eirpW) / prm.R_m, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', 'PLF_dB', ...
    'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
P.Properties.UserData = meta;
end

%% ====================================================================== analysis (pure, canonical tables only)
function A = analyzePattern(T, column, axes6, pct, excess)
%analyzePattern Solid-angle weights, selected-component peak, boresight axis and scalar metrics.
A.solidAngle = solidWeights(T.Theta, T.Phi); [g, A.column] = chooseGain(T, column); A.peak = resolvePeak(g, pct, excess);
A.boresight = boresightAxis(T, column, A.solidAngle, axes6, pct, excess); A.metrics = calcMetrics(T, A.solidAngle, axes6, A.boresight, pct, excess);
end

function k = boresightAxis(T, column, dOmega, axes6, pct, excess)
%boresightAxis Principal axis (±X/±Y/±Z) whose 45° cone captures the most peak-normalised radiated energy (outliers excluded).
g = chooseGain(T, column); pk = resolvePeak(g, pct, excess); if pk.wasAdjusted, g(pk.outlierMask) = NaN; end
w = 10.^((g - pk.value) / 10) .* dOmega; w(~isfinite(w)) = 0;
ax = [sind(axes6.theta(:)) .* cosd(axes6.phi(:)), sind(axes6.theta(:)) .* sind(axes6.phi(:)), cosd(axes6.theta(:))];
r = [sind(T.Theta) .* cosd(T.Phi), sind(T.Theta) .* sind(T.Phi), cosd(T.Theta)]; [~, k] = max(w.' * double(r * ax.' >= cosd(45)));
end

function m = calcMetrics(T, dOmega, axes6, axisIndex, pct, excess)
%calcMetrics Peak, principal-plane HPBW, front-to-back, directivity, efficiency and AR at peak — all from total gain.
g = chooseGain(T, "E_Total_dB"); pk = resolvePeak(g, pct, excess); i = pk.index; gm = g; if pk.wasAdjusted, gm(pk.outlierMask) = NaN; end
Prad = sum(10.^(gm / 10) .* dOmega, 'omitnan'); m = struct('PeakGain_dB', pk.value, 'PeakTheta_deg', T.Theta(i), 'PeakPhi_deg', T.Phi(i));
m.PeakDirectivity_dB = 10 * log10(max(4 * pi * 10^(pk.value / 10) / max(Prad, eps), eps));
m.Efficiency_pct = 100 * Prad / (4 * pi); if m.Efficiency_pct > 100, m.Efficiency_pct = NaN; end
[~, back] = min(cosd(T.Theta) * cosd(T.Theta(i)) + sind(T.Theta) * sind(T.Theta(i)) .* cosd(T.Phi - T.Phi(i))); m.FrontBack_dB = pk.value - g(back);
[eAng, eRows] = cutRows(T, 'Theta', axes6.phi(axisIndex));
if axes6.theta(axisIndex) == 90, [hAng, hRows] = cutRows(T, 'Phi', 90); else, [hAng, hRows] = cutRows(T, 'Theta', 90); end
m.HPBW_EPlane_deg = calcHPBW(eAng, g(eRows)); m.HPBW_HPlane_deg = calcHPBW(hAng, g(hRows));
m.AxialRatioAtPeak_dB = NaN; if ismember('AR_dB', T.Properties.VariableNames), m.AxialRatioAtPeak_dB = T.AR_dB(i); end
end

function [angleDeg, rows, fixed, symbol, snapped] = cutRows(T, cutType, requested)
%cutRows Rows of one full-circle cut through a canonical table, ordered by the running angle 0..360.
%   'Phi' cut: fixed θ (nearest sample), running φ.  'Theta' cut: fixed φ and its antipode, running θ then 360−θ.
if strcmp(cutType, 'Phi')
    tv = unique(T.Theta); [d, k] = min(abs(tv - requested)); fixed = tv(k); symbol = 'θ';
    rows = find(abs(T.Theta - fixed) < 1e-9); [angleDeg, o] = sort(T.Phi(rows)); rows = rows(o);
else
    pv = unique(T.Phi(T.Phi < 360 - 1e-9)); requested = mod(requested, 360); symbol = 'φ';
    [d, k] = min(abs(mod(pv - requested + 180, 360) - 180)); fixed = pv(k); [~, j] = min(abs(mod(pv - fixed, 360) - 180));
    a = find(abs(T.Phi - fixed) < 1e-9); [~, o] = sort(T.Theta(a)); a = a(o);
    b = find(abs(T.Phi - pv(j)) < 1e-9 & T.Theta < 180 - 1e-9); [~, o] = sort(T.Theta(b), 'descend'); b = b(o);
    rows = [a; b]; angleDeg = [T.Theta(a); 360 - T.Theta(b)];
end
snapped = d > 1e-9;
end

function [ang, V] = displayCircle(ang, V, signed)
%displayCircle Map a 0..360 running angle to the display span, sort, dedupe and close both seams (interpolating across a gap).
if signed, ang(ang > 180) = ang(ang > 180) - 360; end
[ang, i] = unique(ang); V = V(i, :); lo = -180 * signed; hi = lo + 360; hasLo = abs(ang(1) - lo) < 1e-9; hasHi = abs(ang(end) - hi) < 1e-9;
if hasLo && ~hasHi, ang(end+1) = hi; V(end+1, :) = V(1, :);
elseif hasHi && ~hasLo, ang = [lo; ang]; V = [V(end, :); V];
elseif ~hasLo && ~hasHi
    w = (hi - ang(end)) / (ang(1) - lo + hi - ang(end)); s = (1 - w) * V(end, :) + w * V(1, :); ang = [lo; ang; hi]; V = [s; V; s];
end
end

function [bw, lo, hi] = calcHPBW(ang, g, pk, pkAng)
%calcHPBW Half-power beamwidth of a circular cut from the interpolated −3 dB crossings on either side of the peak.
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(g); ang = ang(ok); g = g(ok); if numel(g) < 3, return; end
if nargin < 3 || isempty(pk), [pk, i] = max(g); pkAng = ang(i); end
[rel, o] = sort(mod(ang - pkAng + 180, 360) - 180); gr = g(o); half = pk - 3;
L = find(rel < 0 & gr <= half, 1, 'last'); R = find(rel > 0 & gr <= half, 1, 'first');
if isempty(L) || isempty(R) || L + 1 > numel(gr) || R < 2 || gr(L+1) == gr(L) || gr(R-1) == gr(R), return; end
cross = @(a, b) rel(a) + (rel(b) - rel(a)) * (half - gr(a)) / (gr(b) - gr(a));
l = cross(L, L + 1); r = cross(R, R - 1); lo = pkAng + l; hi = pkAng + r; bw = r - l;
end

function cov = coverageCCDF(gain, mask, thr, dOmega)
%coverageCCDF Solid-angle-weighted CCDF, Coverage(T) = 100·Σ Ω_i·[G_i > T] / Σ Ω_i over the region. Exact, O(N log K) via binning.
thr = double(thr(:)); ok = mask(:) & isfinite(gain(:)) & isfinite(dOmega(:)) & dOmega(:) >= 0; g = double(gain(ok)); w = double(dOmega(ok));
cov = zeros(size(thr)); if isempty(g) || sum(w) <= 0, return; end
bins = discretize(g, [-Inf; thr; Inf], 'IncludedEdge', 'right');                 % bin k+1 ⇔ thr(k) < g ≤ thr(k+1)
above = flipud(cumsum(flipud(accumarray(bins, w, [numel(thr) + 1, 1]))));      % above(k+1) = weight with g > thr(k)
cov = 100 * above(2:end) / sum(w);
end

function info = resolvePeak(values, percentile, maxExcessDB)
%resolvePeak Outlier-robust peak: the raw maximum is accepted unless it exceeds the P<percentile> level by more than
%   maxExcessDB; otherwise the highest sample at or below that level is the effective peak (nearest-rank percentile, no toolbox).
v = double(values(:)); finite = isfinite(v);
info = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(v)), 'wasAdjusted', false);
if ~any(finite), return; end
[info.rawValue, info.rawIndex] = max(v, [], 'omitnan'); info.value = info.rawValue; info.index = info.rawIndex;
s = sort(v(finite)); level = s(min(numel(s), max(1, ceil(percentile / 100 * numel(s)))));
if info.rawValue <= level + maxExcessDB, return; end
outliers = finite & v > level; candidates = finite & ~outliers; if ~any(candidates), return; end
c = v; c(~candidates) = -Inf; [info.value, info.index] = max(c); info.outlierMask = outliers; info.wasAdjusted = true;
end

function dOmega = solidWeights(theta, phi)
%solidWeights Exact solid angle of each uniform θ/φ cell of a canonical grid (the closing φ=360 seam weighs zero).
dt = gridStep(theta); dp = gridStep(phi); if ~isfinite(dt), dt = 180; end; if ~isfinite(dp), dp = 360; end
dOmega = (cosd(max(theta - dt / 2, 0)) - cosd(min(theta + dt / 2, 180))) * deg2rad(dp); dOmega(abs(phi - 360) < 1e-9) = 0;
end

function [g, column] = chooseGain(T, requested)
%chooseGain Requested column if present, else E_Total_dB, else the first data column.
vars = string(T.Properties.VariableNames); candidates = [string(requested), "E_Total_dB"]; k = find(ismember(candidates, vars), 1);
if isempty(k), column = char(vars(3)); else, column = char(candidates(k)); end; g = T.(column);
end

function b = peakWindow(values, fallback, pct, excess)
%peakWindow 50-dB display window whose top is the effective peak rounded up to the next 5 dB.
values = values(isfinite(values)); if isempty(values), b = fallback; return; end
top = 5 * ceil(resolvePeak(values, pct, excess).value / 5); b = min(max([top - 50, top], -250), 100); if diff(b) < 1, b(1) = max(-250, b(2) - 50); end
end

function r = clampRange(v, bounds)
%clampRange Sorted range clamped to BOUNDS with at least a one-unit span.
v = sort(double(v(:).')); if numel(v) < 2 || any(~isfinite(v(1:2))), r = bounds; return; end
r = [max(bounds(1), v(1)), min(bounds(2), v(2))]; if diff(r) < 1, r(2) = min(bounds(2), r(1) + 1); r(1) = max(bounds(1), r(2) - 1); end
end

function t = axisTicks(lim, step)
%axisTicks Colorbar/Z ticks at multiples of STEP inside LIM, always including both ends (empty when degenerate or too dense).
t = []; if ~isfinite(step) || step <= 0 || diff(lim) <= 0, return; end
first = ceil(lim(1) / step) * step; last = floor(lim(2) / step) * step; t = unique([lim(1), first:step:last, lim(2)], 'stable'); if numel(t) > 60, t = []; end
end

function s = gridStep(v)
%gridStep Smallest positive spacing between distinct finite samples (NaN if fewer than two).
d = diff(unique(v(isfinite(v)))); d = d(d > 1e-9); if isempty(d), s = NaN; else, s = min(d); end
end

function c = preferredComponent(previous, cols)
if any(cols == string(previous)), c = char(string(previous)); elseif any(cols == "E_Total_dB"), c = 'E_Total_dB'; else, c = char(cols(1)); end
end

function s = fmtNum(v, precision)
%fmtNum Compact number text: up to 2 decimals without trailing zeros (or exactly PRECISION decimals); 'n/a' when not finite.
if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return; end
if nargin > 1, s = sprintf('%.*f', precision, v); else, s = regexprep(sprintf('%.2f', round(v, 2) + 0), '\.?0+$', ''); end
end