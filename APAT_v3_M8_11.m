classdef APAT_v3_M8_11 < matlab.apps.AppBase %1811-lines %Issues: %1. Lazy plots rendering %2. Interactive DatTip cursor not showing Custom DataTips  on Contour Plot & Fisheye Plot %3. DatTip Context menu callback not working (nothing happens when clicking on "Delete DataTips" context menu! Also, MATLAB Workspace showing "Warning: You cannot set 'ContextMenu' property of DataTip") %4. Table Outputs Filter not showing  %5. When loading new pattern (or new cut), while the POB DatTips anotation is enabled, it keeps the old DataTip annotation!  %6. On Coverage Threshold Query, it doesn't return/place the DataTip at the exact requested/queried value (it snaps to nearest data-point! whereas the projection line is properly traced properly at the requested/queries Threshold/Coverage location/position!)  %7. On Coverage, when Resetting, it doesn't clear the projection lines!
%APAT_v3_M8  Antenna Pattern Analyzer Tool — v3 Milestone 8 (concise architecture).
%
%   One App Designer class organised in five layers (top to bottom of this file):
%     1. Lifecycle & public API     constructor, delete, loadFile, runSelfTest
%     2. Main-tab pipeline          read -> canonical -> process -> analysis basis -> view
%     3. Rendering                  full-pattern tabs (lazy), cuts, annotations, colour ranges
%     4. Coverage tab               tree of pattern/result nodes and CCDF jobs
%     5. UI construction            createComponents / startupFcn
%   Pure I/O readers and numerical services are local functions after the class;
%   they never touch the UI and are unit-testable through runSelfTest.
%
%   Data flow (ALL mathematics runs in the canonical frame θ∈[0,180], φ∈[0,360]):
%     src.blocks{k} --normalizePattern--> stdTbl --calcPattern--> patTbl   (native step)
%     stdTbl --[optional 1° resample]--calcPattern--> baseTbl             (analysis basis)
%     baseTbl --displayTable--> viewTbl   (θ/φ display convention: tables, exports, plot grids only)
%
%   Requires MATLAB R2023b or later (range slider, thetaregion/xregion, ContextObject event data).

    properties (Access = public)
        UIFigure matlab.ui.Figure
        ui struct = struct()       % Every widget, addressed as app.ui.<name> (see createComponents)
        full struct = struct([])   % Full-pattern tabs: name, tab, ax, slider, spMin, spMax, render, dirty
    end

    properties (SetAccess = private)
        isClosing logical = false
        file struct = struct('path', '', 'folder', '', 'base', '', 'name', '')
        src struct = struct()      % Source adapter from readPattern: raw, blocks, freqs, ud
        stdTbl table               % Canonical primitive block (Theta, Phi, Re/Im Eth/Eph | gain columns)
        patTbl table               % Processed pattern at the native angular step
        baseTbl table              % Processed analysis basis (native or 1° step); input of every analysis
        viewTbl table              % Display-convention copy of baseTbl (Results table, exports, plot grids)
        baseRev double = 0         % Increments whenever baseTbl changes (coverage preset key)
        info struct = struct()     % calcPattern summary: pol (label) and pairs (co/cross ordering)
        peak struct = struct()     % Outlier-aware peak of the selected component (canonical θ/φ)
        metrics struct = struct()  % Scalar metrics of the total-gain column
        omega double = []          % Solid-angle weights aligned with baseTbl rows
        boresight double = 1       % Index into PrincipalAxes (detected 45° cone with most power)
        gainLim double = [-40 10]  % Shared colour scale of the full-pattern tabs (gain-like components)
        arLim double = [-30 30]    % Colour scale used while the signed axial ratio is displayed
        cutLim double = [-40 10]   % Cut-plot range
        gridCache struct = struct()
        defaults cell = {}         % Startup values of the parameter controls (Reset Params)
        covJobs cell = {}          % Authoritative registry of coverage job nodes (the tree is the view)
        covRunID double = 0
        covPresetKey string = ""
        statusTimer = []
        dialog = []
    end

    properties (Constant)
        Release = 'APAT v3 M8'
        PrincipalAxes = struct('labels', {{'+Z', '-Z', '+X', '-X', '+Y', '-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        ComponentLabels = ["E_Total_dB", "Total Gain"; "E_TH_dB", "Etheta Gain"; "E_PH_dB", "Ephi Gain"; "E_RCP_dB", "RHCP Gain"; ...
            "E_LCP_dB", "LHCP Gain"; "AR_dB", "Axial Ratio"; "Gain_PolCorrected_dB", "Polarized Gain"]
        HiddenOutputColumns = {'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'}
        TextFormats = {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
            '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
            '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'; ...
            'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'}
        PeakPercentile = 99.99     % Peak policy: a raw maximum more than PeakMaxExcessDB above P99.99 is an outlier
        PeakMaxExcessDB = 6
        RangeBounds = [-250 100]   % Absolute dB bounds of every range control
    end

    %% ================================================================ 1. Lifecycle & public API
    methods (Access = public)
        function app = APAT_v3_M8_11
            createComponents(app);
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @startupFcn);
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true;
            app.stopStatusTimer();
            if ~isempty(app.dialog) && isvalid(app.dialog), delete(app.dialog); end
            if ~isempty(app.UIFigure) && isgraphics(app.UIFigure), delete(app.UIFigure); end
        end

        function loadFile(app, fp, textFormat)
            %LOADFILE Programmatic equivalent of the Load File button; TEXTFORMAT (see TextFormats) applies to generic text files.
            app.ui.path.Value = fp;
            app.onLoad();
            if nargin > 2 && isGenericText(fp) && ~strcmp(textFormat, 'gain')
                app.ui.ddFormat.Value = char(textFormat); app.onTextFormatChanged();
            end
        end

        function report = runSelfTest(app)
            %RUNSELFTEST Deterministic checks of the numerical services and readers (no UI interaction).
            pct = app.PeakPercentile; ex = app.PeakMaxExcessDB; axes6 = app.PrincipalAxes;
            [P, T] = meshgrid(0:30:330, 0:30:180);
            G = table(T(:), P(:), 10 * cosd(T(:)).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            w = solidWeights(G.Theta, G.Phi);                         r.solidAngle = abs(sum(w) - 4 * pi) < 1e-9;
            [pk, ai] = calcOrientation(G, w, 'E_Total_dB', axes6, pct, ex); r.orientation = isfinite(pk.value) && ai == 1;
            [P2, T2] = meshgrid(0:2:358, 0:2:180); A = 12 * cosd(T2).^2 - 0.5 * sind(P2).^2;
            R = resampleCanonical(table(T2(:), P2(:), A(:), 'VariableNames', {'Theta', 'Phi', 'Val'}), 1);
            native = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0 & R.Phi < 360;
            err = max(abs(R.Val(native) - (12 * cosd(R.Theta(native)).^2 - 0.5 * sind(R.Phi(native)).^2)));
            r.resampling = height(R) == 181 * 361 && err < 1e-9;
            r.peakWindow = isequal(peakWindow([3.2; -250; -17], pct, ex), [-45 5]);
            spike = repmat(0.02, 1e5, 1); spike(1) = 10.02; sp = resolvePeak(spike, pct, ex);
            r.isolatedSpike = sp.wasAdjusted && abs(sp.value - 0.02) < 1e-12 && sp.rawIndex == 1 && isequal(peakWindow(spike, pct, ex), [-45 5]);
            r.arSemantics = all(arrayfun(@isAR, ["AR", "AR_dB", "AR dB", "Axial Ratio", "Axial_Ratio"])) && ~isAR("E_Total_dB");
            c = coverageCCDF(G.E_Total_dB, true(height(G), 1), (-10:5:20).', w); r.coverage = all(diff(c) <= 0) && c(1) == 100 && c(end) == 0;
            S = normalizePattern(table([-90; 0; 90], [0; 0; 0], [1; 2; 3], 'VariableNames', {'Theta', 'Phi', 'G'}));
            r.normalize = isequal(sort(S.Theta), [0; 0; 90; 90; 180; 180]) && all(ismember(S.Phi, [0 360]));
            f = [tempname '.ffd']; fid = fopen(f, 'w'); fprintf(fid, '0 180 3\n-180 180 3\n%s', sprintf('%d 0 0 1\n', 1:9)); fclose(fid);
            cleanup = onCleanup(@() delete(f)); d = readPattern(f, "auto"); %#ok<NASGU>
            r.ffdReader = strcmp(d.ud.source, 'HFSS FFD') && isscalar(d.blocks) && height(d.blocks{1}) == 9;
            names = fieldnames(r); flags = cellfun(@(n) r.(n), names);
            report = r; report.pass = all(flags); report.resampleError = err;
            if ~report.pass, error('APAT:SelfTest', 'Self-test failed: %s', strjoin(names(~flags), ', ')); end
        end
    end

    %% ================================================================ Shared services (callbacks, status, dialogs)
    methods (Access = private)
        function f = cb(app, fn)
            % Wrap a callback so every uncaught error is reported once (cancellation is reported quietly).
            f = @(src, evt) app.guard(fn, src, evt);
        end

        function guard(app, fn, src, evt)
            try
                fn(src, evt);
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.status('Operation cancelled by user.', true);
                else, app.showError(ME); end
            end
        end

        function showError(app, ME, titleText)
            if nargin < 3, titleText = 'Error'; end
            if app.isClosing || ~isgraphics(app.UIFigure), return; end
            where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.UIFigure, [ME.message where], titleText, 'Icon', 'error');
        end

        function status(app, msg, transient, bar)
            % Set the Main (default) or Coverage status bar. Transient messages revert to the last persistent one after 3 s.
            if nargin < 3, transient = false; end
            if nargin < 4, bar = app.ui.bar; end
            if app.isClosing || ~isgraphics(bar), return; end
            app.stopStatusTimer();
            bar.Text = char(msg);
            if ~transient, bar.UserData = char(msg); return; end
            app.statusTimer = timer('StartDelay', 3, 'TimerFcn', @(~, ~) app.restoreStatus(bar), 'StopFcn', @(t, ~) delete(t));
            start(app.statusTimer);
        end

        function covStatus(app, msg, transient)
            if nargin < 3, transient = false; end
            app.status(msg, transient, app.ui.covBar);
        end

        function restoreStatus(app, bar)
            if ~app.isClosing && isgraphics(bar), bar.Text = bar.UserData; end
        end

        function stopStatusTimer(app)
            t = app.statusTimer; app.statusTimer = [];
            if ~isempty(t) && isvalid(t), stop(t); end
            if ~isempty(t) && isvalid(t), delete(t); end
        end

        function done = busy(app, titleText, msg, cancelable)
            % Indeterminate progress dialog; the returned onCleanup closes it when the caller exits (normally or by error).
            d = uiprogressdlg(app.UIFigure, 'Title', titleText, 'Message', msg, 'Indeterminate', 'on', 'Cancelable', cancelable, 'CancelText', 'Abort');
            app.dialog = d; drawnow;
            done = onCleanup(@() app.endBusy(d));
        end

        function endBusy(app, d)
            if isvalid(d), close(d); end
            if isequal(app.dialog, d), app.dialog = []; end
        end

        function checkCancelled(app)
            d = app.dialog;
            if ~isempty(d) && isvalid(d) && d.CancelRequested, error('APAT:Cancelled', 'Operation cancelled by user.'); end
        end
    end

    %% ================================================================ 2. Main-tab pipeline
    methods (Access = private)
        function out = readForUI(app, fp, dropdown, lbl)
            % Read a source for one tab. Generic text files expose that tab's format selector (reset to "gain" on first read).
            generic = isGenericText(fp); kind = "auto";
            if generic, kind = "gain"; dropdown.Value = 'gain'; end
            out = readPattern(fp, kind, table());
            set([dropdown lbl], 'Visible', generic && ~out.ud.isCoverage);
        end

        function onLoad(app, ~, ~)
            fp = strtrim(app.ui.path.Value);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.file.path)
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / gain / coverage files'; ...
                    '*.*', 'All files'}, 'Select an antenna pattern file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            keep = app.busy('Loading Data', 'Reading file...', true); %#ok<NASGU>
            out = app.readForUI(fp, app.ui.ddFormat, app.ui.lblFormat);
            app.checkCancelled();
            if out.ud.isCoverage   % Coverage-results tables go to the Coverage tab without touching Main state.
                app.ui.path.Value = app.file.path; app.ui.tabs.SelectedTab = app.ui.tabCov; app.ui.covPath.Value = fp;
                app.covLoadResults(fp, out.raw); return
            end
            app.ui.path.Value = fp;
            [app.file.folder, app.file.base, ext] = fileparts(fp);
            app.file.path = fp; app.file.name = [app.file.base ext]; app.src = out;
            if out.ud.isDep
                items = compose('Pattern %d: %.4g GHz', (1:numel(out.blocks)).', out.freqs(:) / 1e9);
                items(isnan(out.freqs)) = compose('Pattern %d', find(isnan(out.freqs(:))));
                items = cellstr(items); app.ui.ddFFD.Items = items; app.ui.ddFFD.Value = items{1};
            end
            set([app.ui.ddFFD app.ui.lblFFD], 'Visible', out.ud.isDep);
            app.ui.ddStep.Value = 'native';
            app.ui.ddCutBasis.UserData = true;   % Derive the cut basis from the new pattern's polarization.
            app.selectBlock(1);
        end

        function onProcess(app, ~, ~)
            if isempty(app.stdTbl), uialert(app.UIFigure, 'Load a pattern first.', 'Process', 'Icon', 'warning'); return; end
            keep = app.busy('Processing', 'Re-processing pattern...', false); %#ok<NASGU>
            if isGenericText(app.file.path)   % Re-interpret the cached generic source with the selected text format.
                out = readPattern(app.file.path, app.ui.ddFormat.Value, app.src.raw);
                assert(~out.ud.isCoverage, 'APAT:io:Format', 'The selected generic format identifies a coverage-results file.');
                app.src = out; app.selectBlock(1);
            else
                app.process();
            end
            app.status(['Re-processed <b>' app.file.name '</b> with the current parameters ✅'], true);
        end

        function onTextFormatChanged(app, ~, ~)
            if strcmp(strtrim(app.ui.path.Value), app.file.path) && isGenericText(app.file.path)
                app.ui.ddCutBasis.UserData = true; app.onProcess();
            end
        end

        function onFFDChanged(app, ~, ~)
            k = find(strcmp(app.ui.ddFFD.Items, app.ui.ddFFD.Value), 1);
            app.ui.ddCutBasis.UserData = true; app.selectBlock(k);
            app.status(sprintf('Switched to FFD block %d (%s).', k, app.ui.ddFFD.Value), true);
        end

        function onResetParams(app, ~, ~)
            set(app.ui.paramCtl, {'Value'}, app.defaults);
            if ~isempty(app.stdTbl), app.process(); end
        end

        function onStepChanged(app, ~, ~)
            app.applyStep();
        end

        function selectBlock(app, k)
            % Canonicalise one source block (FFD files may carry several frequency blocks) and run the pipeline.
            app.stdTbl = normalizePattern(app.src.blocks{k});
            app.stdTbl.Properties.UserData = app.src.ud;
            if app.src.ud.isDep, app.src.raw = app.src.blocks{k}; end
            app.ui.tblIn.UserData = false;   % Input table must be refreshed.
            app.process();
        end

        function process(app)
            % Canonical -> processed pattern -> analysis basis -> view/plots, plus source-dependent UI state.
            [app.patTbl, app.info] = calcPattern(app.stdTbl, app.getParam());
            app.checkCancelled();
            hasE = ~app.src.ud.isGainOnly;
            if hasE && isequal(app.ui.ddCutBasis.UserData, true)
                app.ui.ddCutBasis.Value = char(extractBefore(string(app.info.pol) + " ", " "));   % 'Linear' | 'Circular'
            end
            dt = gridStep(app.patTbl.Theta); dp = gridStep(app.patTbl.Phi);
            nonCanonical = (isfinite(dt) && abs(dt - 1) > 1e-9) || (isfinite(dp) && abs(dp - 1) > 1e-9);
            native = max([dt dp], [], 'omitnan'); if isnan(native), native = 1; end
            app.ui.ddStep.Items = {sprintf('STEP: %g°', native), 'STEP: 1°'};
            if ~nonCanonical, app.ui.ddStep.Value = 'native'; end
            set(app.ui.ddStep, 'Visible', nonCanonical, 'Enable', nonCanonical);
            set([app.ui.pnlCut app.ui.pnlFull app.ui.pnlCtrl app.ui.btnExport app.ui.btnCoverage app.ui.tabData], 'Visible', 'on');
            set([app.ui.btnUAN app.ui.gridEcut app.ui.cbEt app.ui.cbEr app.ui.cbEl], 'Visible', hasE);
            set([app.ui.cbEr app.ui.cbEl app.ui.ddCutBasis], 'Enable', hasE);
            app.applyStep();
            pol = ''; if hasE, pol = sprintf(' | Polarization <b>%s</b>', app.info.pol); end
            app.status(sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>θ=%s°, φ=%s°</b>)%s', app.file.name, ...
                fmt(app.peak.value, 2), fmt(app.peak.theta), fmt(app.peak.phi), pol));
        end

        function applyStep(app)
            % Analysis basis = native processed pattern, or the canonical source resampled to 1° and re-processed
            % (primitive fields are resampled, never the nonlinear outputs such as gain, AR or PLF).
            S = app.stdTbl; dt = gridStep(S.Theta); dp = gridStep(S.Phi);
            wantOne = strcmp(app.ui.ddStep.Value, 'one') && (abs(dt - 1) > 1e-9 || abs(dp - 1) > 1e-9);
            if ~wantOne
                app.baseTbl = app.patTbl;
            else
                onGrid = abs(S.Theta - round(S.Theta)) < 1e-9 & abs(S.Phi - round(S.Phi)) < 1e-9;
                if dt < 1 && dp < 1, S = S(onGrid, :); else, S = resampleCanonical(S, 1); end   % exact decimation when possible
                S.Properties.UserData = app.stdTbl.Properties.UserData;
                app.baseTbl = calcPattern(S, app.getParam());
            end
            app.baseRev = app.baseRev + 1;
            app.refreshAll(true);
        end

        function param = getParam(app)
            u = app.ui;
            param = struct('GainLoss_dB', u.spLoss.Value, 'RxMode', string(u.ddRxPol.Value), 'RxAR_dB', u.spRw.Value);
            param.FieldScale = 10 .^ (param.GainLoss_dB / 20);
            switch u.ddPt.Value
                case 'dBm',   param.Pt_dBW = u.spPt.Value - 30;
                case 'Watts', param.Pt_dBW = 10 * log10(max(u.spPt.Value, eps));
                otherwise,    param.Pt_dBW = u.spPt.Value;
            end
            param.R_m = max(u.spR.Value, 1e-12) * (1 + 999 * strcmp(u.ddR.Value, 'km'));
        end

        function refreshAll(app, resetRanges)
            % Everything downstream of the analysis basis: component list, analysis, default ranges, E-plane cut, display.
            app.updateComponentItems(); app.analyze();
            if resetRanges
                if ~isAR(app.comp()), app.gainLim = peakWindow(chooseGain(app.baseTbl, 'E_Total_dB'), app.PeakPercentile, app.PeakMaxExcessDB); end
                app.setPlaneControls();
            end
            app.refreshDisplay();
        end

        function refreshDisplay(app)
            % Everything downstream of the display convention (φ/θ spans) and the selected component.
            [signed, elev] = app.spans();
            app.viewTbl = displayTable(app.baseTbl, signed, elev); app.gridCache = struct();
            app.setRange("full", app.colorLimits(), false); app.setRange("cut", app.cutLim, false);
            app.updateTables(); app.updateMetadata(); app.updateCutControl();
            app.plotCut(); app.renderFull();
        end

        function analyze(app)
            % Peak, boresight axis, solid-angle weights and scalar metrics — canonical frame, selected component.
            T = app.baseTbl; app.omega = solidWeights(T.Theta, T.Phi);
            [app.peak, app.boresight] = calcOrientation(T, app.omega, app.comp(), app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
            app.metrics = calcMetrics(T, app.omega, app.PrincipalAxes, app.boresight, app.PeakPercentile, app.PeakMaxExcessDB);
        end

        function onComponentChanged(app, ~, ~)
            if isempty(app.baseTbl), return; end
            app.analyze(); app.refreshDisplay();
        end

        function onSpanChanged(app, ~, ~)
            if isempty(app.baseTbl), return; end
            app.refreshDisplay();
        end

        function [signed, elev] = spans(app)
            signed = strcmp(app.ui.swPhi.Value, '-180° to 180°');
            elev = strcmp(app.ui.swTheta.Value, '-90° to 90°');
        end

        function c = comp(app)
            c = app.ui.ddComp.Value;
        end

        function s = compLabel(app)
            dd = app.ui.ddComp; i = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(i), s = string(dd.Value); else, s = string(dd.Items{i}); end
        end

        function lim = colorLimits(app)
            if isAR(app.comp()), lim = app.arLim; else, lim = app.gainLim; end
        end

        function updateComponentItems(app)
            [cols, labels] = componentMap(app.baseTbl); dd = app.ui.ddComp;
            set(dd, 'Items', cellstr(labels), 'ItemsData', cellstr(cols), 'Value', pickComponent(dd.Value, cols));
        end

        function updateTables(app)
            u = app.ui; V = app.viewTbl;
            if ~isequal(u.tblIn.UserData, true)
                u.tblIn.Data = app.src.raw; u.tblIn.ColumnName = app.src.raw.Properties.VariableNames; u.tblIn.UserData = true;
            end
            cols = V.Properties.VariableNames(3:end);
            if ~isequal(u.ddOutput.UserData.cols, cols)   % schema changed -> rebuild the column filter
                u.ddOutput.UserData = struct('cols', {cols}, 'on', ~ismember(cols, app.HiddenOutputColumns));
            end
            app.filterOutput();
        end

        function filterOutput(app, ~, ~)
            % Output-column filter: the dropdown is a multi-select toggle list ("✓" marks visible columns).
            dd = app.ui.ddOutput; st = dd.UserData;
            if dd.Value > 0, st.on(dd.Value) = ~st.on(dd.Value); dd.UserData = st; end
            names = st.cols; names(st.on) = strcat('✓ ', names(st.on));
            set(dd, 'Items', [{'--- column filter ---'}, names], 'ItemsData', 0:numel(names), 'Value', 0);
            removeStyle(dd);
            if any(st.on), addStyle(dd, uistyle('FontWeight', 'bold', 'BackgroundColor', [0.8 1 0.8]), 'Item', find(st.on) + 1); end
            addStyle(dd, uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9]), 'Item', [1, find(~st.on) + 1]);
            app.ui.tblOut.Data = app.viewTbl(:, [true true st.on]);
            app.updateInputVisibility();
        end

        function updateInputVisibility(app)
            % Show only the parameters that influence a currently visible output column.
            u = app.ui; st = u.ddOutput.UserData; on = string(st.cols(st.on));
            set([u.lblRx u.ddRxPol u.lblRw u.spRw], 'Visible', any(ismember(["PLF_dB", "Gain_PolCorrected_dB"], on)));
            set([u.lblPt u.spPt u.ddPt], 'Visible', any(ismember(["EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"], on)));
            set([u.lblR u.spR u.ddR], 'Visible', any(ismember(["PFD_Wm2", "E_RMS_Vm"], on)));
            set([u.lblLoss u.spLoss], 'Visible', app.src.ud.isGainOnly || any(ismember(["E_Total_dB", "E_TH_dB", "E_PH_dB", ...
                "E_RCP_dB", "E_LCP_dB", "Gain_PolCorrected_dB", "EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"], on)));
        end

        function updateMetadata(app)
            T = app.baseTbl; m = app.metrics; ud = app.src.ud; th = unique(T.Theta); ph = unique(T.Phi);
            rows = {'Source format', ud.source; 'File', app.file.name; ...
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(T), numel(th), numel(ph)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmt(th(1)), fmt(th(end)), fmt(gridStep(th))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmt(ph(1)), fmt(ph(end)), fmt(gridStep(ph)))};
            f = app.src.freqs(isfinite(app.src.freqs));
            if ~isempty(f), rows(end + 1, :) = {'Frequencies', char(strjoin(compose('%.4g GHz', f(:).' / 1e9), ', '))}; end
            if ~ud.isGainOnly
                rows(end + 1, :) = {'Polarization', app.info.pol};
                rows(end + 1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(app.info.pairs.(app.ui.ddCutBasis.Value), ' / '))};
            end
            rows = [rows; {'Component', char(app.compLabel()); 'Peak (POB)', [fmt(app.peak.value) ' dB']; ...
                'POB direction [θ, φ]', sprintf('[%s°, %s°]', fmt(app.peak.theta), fmt(app.peak.phi)); ...
                'Boresight axis', app.PrincipalAxes.labels{app.boresight}; ...
                'Peak policy', sprintf('P%.4g, max excess %.4g dB', app.PeakPercentile, app.PeakMaxExcessDB); ...
                'Peak adjusted', char(string(app.peak.wasAdjusted))}];
            if isfield(m, 'PeakGain')
                rows = [rows; {'Peak total gain', [fmt(m.PeakGain) ' dB']; 'HPBW E-plane', [fmt(m.HPBW_E) '°']; 'HPBW H-plane', [fmt(m.HPBW_H) '°']; ...
                    'Front-to-back', [fmt(m.FrontBack) ' dB']; 'Peak directivity', [fmt(m.Directivity) ' dB']}];
                if isfinite(m.Efficiency), rows(end + 1, :) = {'Radiation efficiency', [fmt(m.Efficiency) '%']}; end
                if isfinite(m.ARatPeak), rows(end + 1, :) = {'AR at peak', [fmt(m.ARatPeak) ' dB']}; end
            end
            app.ui.tblMeta.Data = rows;
        end

        % ---- exports -------------------------------------------------------------------------------------
        function onExport(app, ~, ~)
            if isempty(app.viewTbl), return; end
            app.saveTable(app.ui.tblOut.Data, 'Results', [app.file.base '_APAT_results.csv'], ...
                {'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'});
        end

        function onExportCut(app, ~, ~)
            if isempty(app.baseTbl), return; end
            C = app.cutData();
            app.saveTable(array2table([C.angle C.data], 'VariableNames', [{'Angle_deg'} C.names]), ['Cut (' C.title ')'], ...
                [app.file.base '_cut.csv'], {'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'});
        end

        function onExportUAN(app, ~, ~)
            % XGTD UAN export of the analysis basis (canonical θ/φ, dB magnitude and degree phase of Eθ/Eφ).
            T = app.baseTbl; req = {'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase'};
            if isempty(T) || ~all(ismember(req, T.Properties.VariableNames)), uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            U = sortrows(table(T.Theta, T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'}), {'Phi', 'Theta'});
            top = max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan'); st = gridStep(U.Theta); if ~isfinite(st), st = 1; end
            app.saveTable(U, 'UAN', sprintf('%s_%.5f_%gdeg.uan', app.file.base, top, st), ...
                {'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'});
        end

        function saveTable(app, T, what, defaultName, filters, bar)
            % Common export path: file dialog, format by extension (.uan header, tab-delimited .txt, native otherwise).
            if nargin < 6, bar = app.ui.bar; end
            [f, p] = uiputfile(filters, ['Export ' what], fullfile(app.file.folder, defaultName));
            if isequal(f, 0), return; end
            fp = fullfile(p, f); keep = app.busy('Saving Data', 'Writing file...', false); %#ok<NASGU>
            if endsWith(fp, '.uan', 'IgnoreCase', true), writeUAN(T, fp);
            elseif endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t');
            else, writetable(T, fp); end
            app.status(sprintf('%s exported to <b>%s</b>', what, fp), true, bar);
        end
    end

    %% ================================================================ 3. Rendering
    methods (Access = private)
        % ---- cuts ----------------------------------------------------------------------------------------
        function setPlaneControls(app)
            % E-plane: θ-cut through the boresight φ. H-plane: the orthogonal plane
            % (φ-cut at θ=90° for ±Z boresight, θ-cut at φ=90° for transverse axes).
            ax = app.PrincipalAxes; i = app.boresight; [~, elev] = app.spans();
            if strcmp(app.ui.swEH.Value, 'E'), type = 'Theta'; val = ax.phi(i);
            elseif ax.theta(i) == 90, type = 'Phi'; val = 90 * ~elev;
            else, type = 'Theta'; val = 90; end
            app.ui.ddCutType.Value = type; app.updateCutControl();
            s = app.ui.spCutValue; s.Value = min(max(val, s.Limits(1)), s.Limits(2)); app.updateCutControl();   % snap to grid
        end

        function onEHPlane(app, ~, ~)
            if isempty(app.baseTbl), return; end
            app.setPlaneControls(); app.onCutChanged();
        end

        function onCutChanged(app, src, ~)
            if isempty(app.baseTbl), return; end
            if nargin > 1 && isequal(src, app.ui.ddCutType), app.updateCutControl(); end
            if nargin > 1 && isequal(src, app.ui.ddCutBasis), app.ui.ddCutBasis.UserData = false; app.updateMetadata(); end
            show = app.ui.btnHPBW.Value; app.ui.cbHPBWBounds.Visible = show;
            if ~show, app.ui.cbHPBWBounds.Value = false; end
            app.plotCut(); app.refreshOverlays();
        end

        function updateCutControl(app)
            % Cut value = fixed θ (Phi cut) or fixed φ (Theta cut), expressed in display units.
            [~, elev] = app.spans(); s = app.ui.spCutValue;
            if strcmp(app.ui.ddCutType.Value, 'Phi'), v = unique(app.baseTbl.Theta); if elev, v = sort(90 - v); end
            else, v = unique(mod(app.baseTbl.Phi, 360)); end
            s.Limits = [-Inf Inf]; [~, i] = min(abs(v - s.Value)); s.Value = v(i); s.Limits = [min(v) max(v)];   % widen, snap, narrow
            if numel(v) > 1, s.Step = min(diff(v)); end
        end

        function [cols, idx] = cutCols(app)
            % Selected cut traces: Total plus the circular or linear pair (idx keeps trace colours stable).
            if app.src.ud.isGainOnly, cols = {app.comp()}; idx = 1; return; end
            if strcmp(app.ui.ddCutBasis.Value, 'Linear'), pair = {'E_TH', 'E_PH'}; else, pair = {'E_RCP', 'E_LCP'}; end
            app.ui.cbEr.Text = pair{1}; app.ui.cbEl.Text = pair{2};
            on = [app.ui.cbEt.Value, app.ui.cbEr.Value, app.ui.cbEl.Value]; if ~any(on), on(1) = true; end
            idx = find(on); all3 = [{'E_Total_dB'}, strcat(pair, '_dB')]; cols = all3(idx);
        end

        function C = cutData(app)
            % The active cut as one closed circle: canonical geometry, angle axis in the display convention.
            [signed, elev] = app.spans(); type = string(app.ui.ddCutType.Value); req = app.ui.spCutValue.Value;
            if type == "Phi" && elev, req = 90 - req; end
            [ang, rows, fixed, sym, snapped] = calcCut(app.baseTbl, type, req);
            if snapped, app.status(sprintf('%s cut snapped to nearest %s = %g°', type, sym, fixed)); end
            [cols, idx] = app.cutCols();
            Y = app.baseTbl{rows, cols}; th = app.baseTbl.Theta(rows); ph = app.baseTbl.Phi(rows);
            if signed, ang(ang > 180) = ang(ang > 180) - 360; end
            [ang, order] = unique(ang); Y = Y(order, :); th = th(order); ph = ph(order);
            lim = [0 360]; if signed, lim = [-180 180]; end
            if ang(1) > lim(1) + 1e-9 && abs(ang(end) - lim(2)) < 1e-9        % close the circle at the display seam
                ang = [lim(1); ang]; Y = [Y(end, :); Y]; th = [th(end); th]; ph = [ph(end); ph];
            elseif abs(ang(1) - lim(1)) < 1e-9 && ang(end) < lim(2) - 1e-9
                ang = [ang; lim(2)]; Y = [Y; Y(1, :)]; th = [th; th(1)]; ph = [ph; ph(1)];
            end
            if app.src.ud.isGainOnly, titleText = char(app.compLabel());
            else, shown = fixed; if type == "Phi" && elev, shown = 90 - fixed; end
                titleText = sprintf('%s cut @ %s = %g°', type, sym, shown); end
            C = struct('angle', ang, 'data', Y, 'theta', th, 'phi', ph, 'names', {cols}, 'labels', replace(string(cols), "_", "\_"), ...
                'idx', idx, 'type', type, 'title', titleText, 'xlim', lim);
        end

        function plotCut(app)
            if isempty(app.baseTbl), return; end
            C = app.cutData(); pax = app.ui.paxCut; ax = app.ui.axRect; lim = app.cutLim;
            cla(pax); cla(ax); hold(pax, 'on'); hold(ax, 'on');
            pl = polarplot(pax, deg2rad(C.angle), max(C.data, lim(1)), 'LineWidth', 1.4);   % clamp: no reflection below RLim(1)
            rl = plot(ax, C.angle, C.data, 'LineWidth', 1.4);
            colors = ax.ColorOrder(1 + mod(C.idx - 1, size(ax.ColorOrder, 1)), :);
            for k = 1:numel(pl)
                rows = [dataTipTextRow("Angle", C.angle, '%.3g°'), dataTipTextRow("Magnitude", C.data(:, k), '%.3g dB')];
                set([pl(k) rl(k)], 'Color', colors(k, :)); pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            set(pax, 'ThetaDir', 'clockwise', 'ThetaZeroLocation', 'top', 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.polarTicks(pax);
            set(ax, 'YLim', lim, 'XLim', C.xlim, 'XTick', C.xlim(1):30:C.xlim(2), 'XGrid', 'on', 'YGrid', 'on', 'Box', 'on');
            xlabel(ax, sprintf('%s (degree)', C.type)); title(pax, C.title, 'Interpreter', 'none'); title(ax, C.title, 'Interpreter', 'none');
            % Peak of the displayed cut (first trace) and optional HPBW of that trace.
            [pk, i] = max(C.data(:, 1), [], 'omitnan'); app.ui.lblHPBW.Text = '';
            if isfinite(pk)
                rows = [dataTipTextRow("Angle", C.angle(i), '%.3g°'); dataTipTextRow("Magnitude", pk, '%.3g dB')];
                app.mark(pax, deg2rad(C.angle(i)), pk, [], rows, 'APAT_POB', 'k'); app.mark(ax, C.angle(i), pk, 0, rows, 'APAT_POB', 'k');
                if app.ui.btnHPBW.Value
                    [bw, lo, hi] = calcHPBW(C.angle, C.data(:, 1), pk, C.angle(i));
                    if isfinite(bw)
                        b = mod([lo hi] - C.xlim(1), 360) + C.xlim(1);   % wrap the bounds into the displayed span
                        app.ui.lblHPBW.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                        if b(1) <= b(2), reg = b; else, reg = [C.xlim(1) b(2); b(1) C.xlim(2)]; end
                        thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                        xregion(ax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                        tags = ["Lower HPBW", "Upper HPBW"];
                        for k = 1:2
                            rows = [dataTipTextRow(tags(k), b(k), '%.2f°'); dataTipTextRow("Gain", pk - 3, '%.2f dB')];
                            app.mark(pax, deg2rad(b(k)), pk - 3, [], rows, 'APAT_HPBW', '#D95319'); app.mark(ax, b(k), pk - 3, 0, rows, 'APAT_HPBW', '#D95319');
                        end
                    end
                end
            end
            legend(pax, pl, C.labels, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(ax, rl, C.labels, 'Location', 'best');
            hold(pax, 'off'); hold(ax, 'off'); app.applyAnnotationVisibility();
        end

        % ---- annotations ---------------------------------------------------------------------------------
        function mark(app, ax, x, y, z, rows, tag, color)
            % One annotated marker (marker + pinned DataTip). Visibility is driven by TAG in applyAnnotationVisibility.
            if any(~isfinite([x y])), return; end
            held = ishold(ax); hold(ax, 'on');
            try
                if isa(ax, 'matlab.graphics.axis.PolarAxes'), h = polarplot(ax, x, y, 'o'); else, h = plot3(ax, x, y, z, 'o', 'Clipping', 'off'); end
                set(h, 'MarkerSize', 5, 'MarkerEdgeColor', color, 'MarkerFaceColor', color, 'HandleVisibility', 'off', 'Tag', tag);
                h.DataTipTemplate.DataTipRows = rows;
                datatip(h, 'DataIndex', 1, 'FontSize', 9, 'Tag', tag);
            catch ME
                if ~app.isClosing, warning('APAT:Annotation', 'Could not create annotation: %s', ME.message); end
            end
            if ~held, hold(ax, 'off'); end
        end

        function markPOB(app, ax, x, y, z, G)
            if ~isfinite(app.peak.value), return; end
            [~, elev] = app.spans(); tl = "Theta"; if elev, tl = "Elevation"; end
            rows = [dataTipTextRow(tl, G.TH(G.pob), '%.3g°'); dataTipTextRow("Phi", G.PH(G.pob), '%.3g°'); dataTipTextRow(G.label, G.C(G.pob), '%.3g dB')];
            app.mark(ax, x, y, z, rows, 'APAT_POB', 'k');
        end

        function applyAnnotationVisibility(app, ~, ~)
            set(findall(app.UIFigure, 'Tag', 'APAT_POB'), 'Visible', app.ui.cbPOB.Value);
            set(findall(app.UIFigure, 'Tag', 'APAT_HPBW'), 'Visible', app.ui.cbHPBWBounds.Value);
        end

        function deleteDataTips(app, evt)
            % Shared context-menu action: remove user-pinned DataTips of the right-clicked plot (keeps APAT annotations).
            target = app.UIFigure;
            if isprop(evt, 'ContextObject') && ~isempty(evt.ContextObject), target = ancestor(evt.ContextObject, {'axes', 'polaraxes'}); end
            delete(findall(target, 'Type', 'datatip', 'Tag', ''));
        end

        % ---- full-pattern tabs (lazy) ---------------------------------------------------------------------
        function renderFull(app)
            % Mark every full-pattern tab stale and draw the visible one; hidden tabs are drawn when first shown.
            for k = 1:numel(app.full), app.full(k).dirty = true; end
            app.renderTab(app.selectedFullTab());
        end

        function k = selectedFullTab(app)
            k = find([app.full.tab] == app.ui.tabFull.SelectedTab, 1);
        end

        function renderTab(app, k)
            if isempty(k) || isempty(app.baseTbl) || ~app.full(k).dirty, return; end
            app.checkCancelled();
            app.full(k).render(); app.full(k).dirty = false;
            app.applyAnnotationVisibility();
        end

        function onFullTabChanged(app, ~, ~)
            app.renderTab(app.selectedFullTab());
        end

        function G = dispGrid(app)
            % Display-convention grid of the selected component (cached per view; components cached individually).
            c = app.comp(); [signed, elev] = app.spans(); g = app.gridCache;
            if ~isfield(g, 'TH')
                V = app.viewTbl; th = unique(V.Theta); ph = unique(V.Phi);
                [~, it] = ismember(V.Theta, th); [~, ip] = ismember(V.Phi, ph);
                [g.PH, g.TH] = meshgrid(ph, th); g.theta = th; g.phi = ph; g.index = sub2ind(size(g.TH), it, ip); g.comps = struct();
                g.TP = g.TH; if elev, g.TP = 90 - g.TH; end                     % physical polar angle
                g.PR = deg2rad(g.PH); g.X = sind(g.TP) .* cos(g.PR); g.Y = sind(g.TP) .* sin(g.PR); g.Z = cosd(g.TP);
            end
            key = matlab.lang.makeValidName(c);
            if ~isfield(g.comps, key), Zc = nan(size(g.TH)); Zc(g.index) = app.viewTbl.(c); g.comps.(key) = Zc; end
            app.gridCache = g;
            G = g; G.C = g.comps.(key); G.label = app.compLabel();
            pt = app.peak.theta; pp = app.peak.phi; if elev, pt = 90 - pt; end, if signed && pp > 180, pp = pp - 360; end
            [~, r] = min(abs(G.theta - pt)); [~, cc] = min(abs(G.phi - pp)); G.pob = sub2ind(size(G.C), r, cc);
        end

        function drawContour(app)
            G = app.dispGrid(); ax = app.ui.axContour; cla(ax); hold(ax, 'on');
            s = pcolor(ax, G.phi, G.theta, G.C); set(s, 'FaceColor', 'interp', 'LineStyle', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax); app.angularAxes(ax, 30, 15); daspect(ax, [1 1 1]);
            title(ax, G.label, 'Interpreter', 'none'); app.tipTemplate(s, G);
            app.markPOB(ax, G.PH(G.pob), G.TH(G.pob), 0, G); app.finishAxes(ax, false); hold(ax, 'off');
        end

        function drawCircular(app)
            G = app.dispGrid(); pax = app.ui.paxFull; [~, elev] = app.spans(); cla(pax);
            s = surface(pax, G.PR, G.TP, zeros(size(G.TP)), G.C, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(pax); app.polarTicks(pax);
            rl = 0:30:180; if elev, rl = 90 - rl; end
            set(pax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', rl));
            title(pax, sprintf('%s  |  r=θ, angle=φ', G.label), 'Interpreter', 'none', 'FontSize', 9); app.tipTemplate(s, G);
            app.markPOB(pax, G.PR(G.pob), G.TP(G.pob), [], G);
        end

        function draw3D(app, ax, kind)
            % kind: "sphere" (colour on the unit sphere) | "polar" (radius ∝ normalised level) | "rect" (φ, θ, level surface)
            G = app.dispGrid(); lim = app.colorLimits(); [~, elev] = app.spans(); cla(ax); hold(ax, 'on');
            if kind == "rect", X = G.PH; Y = G.TH; Z = G.C;
            else, r = 1; if kind == "polar", r = app.polarRadius(G.C); end, X = r .* G.X; Y = r .* G.Y; Z = r .* G.Z; end
            s = surf(ax, X, Y, Z, G.C, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax); app.tipTemplate(s, G);
            if kind == "rect"
                zlim(ax, lim); zt = axisTicks(lim, app.ui.spCstep.Value); if ~isempty(zt), ax.ZTick = zt; end
                app.angularAxes(ax, 60, 30); grid(ax, 'on');
                tl = 'Theta (degree)'; if elev, tl = 'Elevation (degree)'; end
                xlabel(ax, 'Phi (degree)'); ylabel(ax, tl); zlabel(ax, G.label + " (dB)", 'Interpreter', 'none');
                title(ax, G.label, 'Interpreter', 'none'); app.apply3DView(ax, [-35 35]);
            else
                set(ax, 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1], 'Projection', 'orthographic');
                axis(ax, 'off'); app.drawXYZ(ax); app.apply3DView(ax, [135 25]);
                title(ax, sprintf('%s  |  θ: %s  |  φ: %s', G.label, app.ui.swTheta.Value, app.ui.swPhi.Value), 'Interpreter', 'none');
                app.overlayCut(ax, kind);
            end
            app.markPOB(ax, X(G.pob), Y(G.pob), Z(G.pob), G); app.finishAxes(ax, true); hold(ax, 'off');
        end

        function r = polarRadius(app, v)
            % Radius used by the 3-D polar plot and its cut overlay: the displayed peak maps to r = 1, values ≤ range min to 0.
            lim = app.colorLimits(); top = max(app.baseTbl.(app.comp()), [], 'omitnan');
            r = max(v - lim(1), 0) / max(top - lim(1), eps);
        end

        function overlayCut(app, ax, kind)
            % Draw (or remove) the active cut on a 3-D spherical/polar surface.
            delete(findall(ax, 'Tag', 'APAT_CutOverlay'));
            if ~app.ui.cbOverlay.Value, return; end
            C = app.cutData(); r = 1.02; if kind == "polar", r = 1.01 * app.polarRadius(C.data(:, 1)); end
            held = ishold(ax); hold(ax, 'on');
            plot3(ax, r .* sind(C.theta) .* cosd(C.phi), r .* sind(C.theta) .* sind(C.phi), r .* cosd(C.theta), 'k', ...
                'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay', 'HandleVisibility', 'off');
            if ~held, hold(ax, 'off'); end
        end

        function refreshOverlays(app, ~, ~)
            if isempty(app.baseTbl), return; end
            if ~app.full(3).dirty, app.overlayCut(app.full(3).ax, "sphere"); end
            if ~app.full(4).dirty, app.overlayCut(app.full(4).ax, "polar"); end
        end

        function drawXYZ(~, ax)
            % Principal axes (X red, Y green, Z blue) with their spherical coordinates.
            colors = [0.85 0.10 0.10; 0.10 0.60 0.10; 0.10 0.20 0.90]; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            for k = 1:3
                d = 1.35 * (1:3 == k);
                quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors(k, :), 'LineWidth', 1.6, 'MaxHeadSize', 0.25, 'HandleVisibility', 'off');
                text(ax, 1.12 * d(1), 1.12 * d(2), 1.12 * d(3), labels{k}, 'Color', colors(k, :), 'FontWeight', 'bold');
            end
        end

        function apply3DView(app, ax, defaultView)
            views = struct('iso', [defaultView 0 0 1], 'top', [0 90 0 1 0], 'bottom', [0 -90 0 1 0], 'right', [90 0 0 0 1], ...
                'left', [-90 0 0 0 1], 'front', [0 0 0 0 1], 'back', [180 0 0 0 1]);
            v = views.(app.ui.dd3DView.Value); view(ax, v(1), v(2)); camup(ax, v(3:5));
        end

        function on3DViewChanged(app, ~, ~)
            if isempty(app.baseTbl), return; end
            app.apply3DView(app.full(3).ax, [135 25]); app.apply3DView(app.full(4).ax, [135 25]); app.apply3DView(app.full(5).ax, [-35 35]);
        end

        function tipTemplate(app, s, G)
            [~, elev] = app.spans(); tl = "Theta"; if elev, tl = "Elevation"; end
            try
                s.DataTipTemplate.DataTipRows = [dataTipTextRow(tl, G.TH, '%.3g°'); dataTipTextRow("Phi", G.PH, '%.3g°'); ...
                    dataTipTextRow(replace(G.label, "_", "\_"), G.C, '%.3g dB')];
            catch
            end
        end

        function finishAxes(app, ax, is3D)
            % Re-apply per-render state: shared context menu on every plot object and the gesture set (rotate for 3-D, zoom otherwise).
            set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', app.ui.plotMenu);
            if is3D, ax.Interactions = [rotateInteraction dataTipInteraction]; else, ax.Interactions = [zoomInteraction dataTipInteraction]; end
        end

        function angularAxes(app, ax, dp, dt)
            [signed, elev] = app.spans(); xl = [0 360]; yl = [0 180]; dir = 'reverse';
            if signed, xl = [-180 180]; end
            if elev, yl = [-90 90]; dir = 'normal'; end
            set(ax, 'XLim', xl, 'YLim', yl, 'YDir', dir, 'Box', 'on', 'Layer', 'top', 'XTick', xl(1):dp:xl(2), 'YTick', yl(1):dt:yl(2));
        end

        function polarTicks(app, pax)
            % Polar geometry stays physical; only the φ labels follow the selected span.
            signed = app.spans(); a = 0:30:330; if signed, a(a > 180) = a(a > 180) - 360; end
            pax.ThetaTick = 0:30:330; pax.ThetaTickLabel = compose('%d°', a);
        end

        % ---- colour scale / ranges -----------------------------------------------------------------------
        function applyTheme(app, ax)
            % Signed AR: fixed blue-white-red map centred at 0 dB. Gain-like data: shared jet scale.
            lim = app.colorLimits();
            if isAR(app.comp()), map = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); else, map = jet(256); end
            clim(ax, lim); colormap(ax, map); app.colorbarTicks(colorbar(ax), lim);
        end

        function colorbarTicks(app, cbHandle, lim)
            t = axisTicks(lim, app.ui.spCstep.Value); if ~isempty(t), cbHandle.Ticks = t; end
        end

        function applyColorbar(app, ~, ~)
            lim = [app.ui.spCmin.Value, app.ui.spCmax.Value]; app.setRange("full", lim); app.setRange("cut", lim);
        end

        function onRangeEdit(app, scope, side, value)
            if scope == "full", lim = app.colorLimits(); else, lim = app.cutLim; end
            lim(side) = value; app.setRange(scope, lim);
        end

        function setRange(app, scope, lim, apply)
            % Authoritative range setter: "full" = colour scale of every full-pattern tab, "cut" = cut-plot range.
            % Clamps to RangeBounds, enforces a 1 dB minimum span and mirrors slider/spinner controls.
            if nargin < 4, apply = true; end
            RB = app.RangeBounds; lim = sort(double(lim(:).')); lim = [max(RB(1), lim(1)), min(RB(2), lim(2))];
            if diff(lim) < 1, lim(2) = min(RB(2), lim(1) + 1); lim(1) = lim(2) - 1; end
            if scope == "full"
                sliders = [app.full.slider]; mins = [app.full.spMin]; maxs = [app.full.spMax];
                if isAR(app.comp()), app.arLim = lim; else, app.gainLim = lim; end
                app.ui.spCmin.Value = lim(1); app.ui.spCmax.Value = lim(2);
            else
                sliders = app.ui.sliderCut; mins = app.ui.spCutMin; maxs = app.ui.spCutMax; app.cutLim = lim;
            end
            set(sliders, 'Limits', RB, 'Value', lim); set(sliders, 'Limits', [max(RB(1), lim(1) - 10), min(RB(2), lim(2) + 10)]);
            set([mins maxs], 'Limits', RB); set(mins, 'Value', lim(1), 'Limits', [RB(1), lim(2) - 1]); set(maxs, 'Value', lim(2), 'Limits', [lim(1) + 1, RB(2)]);
            if ~apply || isempty(app.baseTbl), return; end
            if scope == "cut", set(app.ui.paxCut, 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.ui.axRect.YLim = lim; return; end
            for k = 1:numel(app.full)
                ax = app.full(k).ax; if app.full(k).dirty, continue; end
                clim(ax, lim); cbh = findall(app.UIFigure, 'Type', 'ColorBar', 'Axes', ax); if ~isempty(cbh), app.colorbarTicks(cbh(1), lim); end
                if app.full(k).name == "rect3D", zlim(ax, lim); zt = axisTicks(lim, app.ui.spCstep.Value); if ~isempty(zt), ax.ZTick = zt; end, end
            end
            app.full(4).dirty = true;   % the 3-D polar radius depends on the range
            if isequal(app.selectedFullTab(), 4), app.renderTab(4); end
        end
    end

    %% ================================================================ 4. Coverage tab
    methods (Access = private)
        function onCovLoad(app, ~, ~)
            fp = strtrim(app.ui.covPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covNodeByPath(fp))
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.ffd;*.ffe;*.ffs;*.cut;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage data'; ...
                    '*.*', 'All files'}, 'Select a pattern or coverage results file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            node = app.covNodeByPath(fp);
            if ~isempty(node)
                app.ui.covTree.SelectedNodes = node; app.onCovSelection(); app.ui.covPath.Value = fp;
                app.covStatus('File already loaded — node selected. Add another job or load a different file.', true); return
            end
            app.ui.covPath.Value = fp;
            out = app.readForUI(fp, app.ui.covFormat, app.ui.covFormatLabel);
            if out.ud.isCoverage, app.covLoadResults(fp, out.raw);
            else, [~, name] = fileparts(fp); app.covAddPattern(name, app.processAux(out), fp, out.raw); end
        end

        function T = processAux(app, out)
            % Process an auxiliary source with the current Main parameters, without touching Main state (FFD: block 1).
            S = normalizePattern(out.blocks{1}); S.Properties.UserData = out.ud;
            T = calcPattern(S, app.getParam());
        end

        function onCovFormatChanged(app, ~, ~)
            % Re-interpret a generic text pattern already in the tree with the newly selected format.
            fp = strtrim(app.ui.covPath.Value); old = app.covNodeByPath(fp);
            if isempty(old) || ~isGenericText(fp) || ~strcmp(old.NodeData.kind, 'pattern'), return; end
            out = readPattern(fp, app.ui.covFormat.Value, old.NodeData.raw);
            if out.ud.isCoverage, app.covStatus('The selected format identifies a coverage-results file; nothing to reprocess.', true); return; end
            name = old.NodeData.name; jobs = app.covJobNodes(old);
            for k = 1:numel(jobs), delete(jobs(k).NodeData.line); end
            delete(old); app.covAddPattern(name, app.processAux(out), fp, out.raw);
            app.covStatus(sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
        end

        function onCoverageFromMain(app, ~, ~)
            % Coverage always receives the current Main analysis basis (loss, step and component derivation included).
            if isempty(app.baseTbl), uialert(app.UIFigure, 'Load and process a pattern first.', 'Coverage'); return; end
            app.ui.tabs.SelectedTab = app.ui.tabCov; app.ui.covPath.Value = app.file.path;
            node = app.covNodeByPath(app.file.path);
            if isempty(node), app.covAddPattern(app.file.base, app.baseTbl, app.file.path, app.src.raw); return; end
            app.covSyncMain(node); app.ui.covTree.SelectedNodes = node; app.covSync(node); app.covRefresh();
            app.covStatus('Coverage source synchronized from the current Main analysis basis.');
        end

        function covSyncMain(app, node)
            % The node that mirrors the Main file always follows the Main analysis basis.
            d = node.NodeData;
            if ~strcmp(d.path, app.file.path) || isempty(app.baseTbl) || d.rev == app.baseRev, return; end
            d.T = app.baseTbl; d.omega = app.omega; d.rev = app.baseRev; d.comp = ''; node.NodeData = d;
        end

        function covAddPattern(app, name, T, fp, raw)
            node = uitreenode(app.ui.covRoot, 'Text', ['📡 ' name]);
            rev = 0; if strcmp(fp, app.file.path), rev = app.baseRev; end
            node.NodeData = struct('kind', 'pattern', 'name', name, 'path', fp, 'T', T, 'raw', raw, 'omega', solidWeights(T.Theta, T.Phi), ...
                'comp', '', 'boresight', 1, 'rev', rev);
            expand(app.ui.covTree); app.ui.covTree.CheckedNodes = [app.ui.covTree.CheckedNodes; node]; app.ui.covTree.SelectedNodes = node;
            app.covSync(node); app.covRefresh();
            app.covStatus(sprintf('Pattern <b>"%s"</b> added — ready to compute coverage.', name));
        end

        function covSync(app, node)
            % Align the component list, detected boresight and threshold preset with a pattern node.
            d = node.NodeData; [cols, labels] = componentMap(d.T); dd = app.ui.covComp;
            prev = d.comp; if isempty(prev), prev = dd.Value; end
            c = pickComponent(prev, cols);
            set(dd, 'Items', cellstr(labels), 'ItemsData', cellstr(cols), 'Value', c);
            if ~strcmp(d.comp, c)
                [~, d.boresight] = calcOrientation(d.T, d.omega, c, app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
                d.comp = c; node.NodeData = d;
                if app.ui.covOrientation.Value == 0, app.onCovOrientation(); end   % Auto follows the detected axis
            end
            key = sprintf('%s|%s|%d', d.path, c, d.rev);
            if ~strcmp(app.covPresetKey, key)   % automatic preset only when pattern/component/basis actually changed
                app.covPresetKey = key; app.covSetThresholds(peakWindow(d.T.(c), app.PeakPercentile, app.PeakMaxExcessDB));
            end
        end

        function covSetThresholds(app, b)
            % Peak-referenced 50 dB preset. After the first preset it only widens the range; user edits persist otherwise.
            u = app.ui; RB = app.RangeBounds;
            if isequal(u.covThrMin.UserData, true), b = [min(b(1), u.covThrMin.Value), max(b(2), u.covThrMax.Value)]; end
            set([u.covThrMin u.covThrMax], 'Limits', RB); u.covThrMin.Value = b(1); u.covThrMax.Value = b(2);
            u.covThrMin.Limits = [RB(1), b(2) - 0.1]; u.covThrMax.Limits = [b(1) + 0.1, RB(2)]; u.covThrMin.UserData = true;
        end

        function thr = covThresholds(app)
            % The threshold controls exactly as entered (presets never override user edits at compute time).
            u = app.ui; lo = u.covThrMin.Value; hi = u.covThrMax.Value; st = max(u.covStep.Value, 0.01);
            thr = (lo:st:hi).'; if thr(end) < hi - 1e-9, thr(end + 1, 1) = hi; end
        end

        function onCovCompute(app, ~, ~)
            node = app.covTarget();
            if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            app.covSyncMain(node); app.covSync(node); d = node.NodeData; T = d.T;
            c = app.ui.covComp.Value; thr = app.covThresholds(); conical = app.ui.covConical.Value;
            mask = true(height(T), 1); tag = 'Sph'; label = 'Sph coverage'; orientation = "n/a";
            if conical
                sel = app.ui.covOrientation.Value; if sel == 0, sel = d.boresight; end
                orientation = string(app.PrincipalAxes.labels{sel});
                t0 = app.ui.covConeTh.Value; p0 = mod(app.ui.covConePh.Value, 360); a = app.ui.covConeAng.Value;
                mask = cosd(T.Theta) * cosd(t0) + sind(T.Theta) * sind(t0) .* cosd(T.Phi - p0) >= cosd(a);
                center = app.coneLabel(t0, p0);
                tag = sprintf('Con %s α%s°', erase(center, ["=", ","]), fmt(a)); label = sprintf('Conical coverage (%s) α=%s°', center, fmt(a));
            end
            cov = coverageCCDF(T.(c), mask, thr, d.omega);
            job = app.covAddJob(node, thr, cov, label, tag, c, '📉');
            job.NodeData.conical = conical; job.NodeData.orientation = orientation;
            app.covRefresh(); app.covSetXLim([thr(1) thr(end)], true);
            msg = sprintf('Run-<b>%d</b> computed: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', app.covRunID, label, d.name, c, numel(thr));
            if conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, orientation); end
            app.covStatus(msg);
        end

        function job = covAddJob(app, parent, thr, cov, label, tag, c, icon)
            app.covRunID = app.covRunID + 1;
            text = sprintf('%s R%d %s · %s', icon, app.covRunID, label, c);
            h = plot(app.ui.covAxes, thr, cov, 'LineWidth', 1.6, 'DisplayName', text);
            h.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", 'XData', '%.2f dB'); dataTipTextRow("Coverage", 'YData', '%.2f%%')];
            job = uitreenode(parent, 'Text', text);
            job.NodeData = struct('kind', 'job', 'id', app.covRunID, 'thr', thr(:), 'cov', cov(:), 'line', h, 'label', text, ...
                'tableTag', tag, 'conical', false, 'orientation', "n/a");
            app.covJobs{end + 1} = job; expand(parent);
            app.ui.covTree.CheckedNodes = [app.ui.covTree.CheckedNodes; job];
        end

        function covLoadResults(app, fp, R)
            [~, name] = fileparts(fp);
            node = uitreenode(app.ui.covRoot, 'Text', ['📄 ' name]); node.NodeData = struct('kind', 'results', 'name', name, 'path', fp);
            app.ui.covTree.CheckedNodes = [app.ui.covTree.CheckedNodes; node]; thr = R{:, 1};
            for k = 2:width(R), app.covAddJob(node, thr, R{:, k}, 'Res', 'Res', R.Properties.VariableNames{k}, '📈'); end
            step = gridStep(thr); if isfinite(step) && step < app.ui.covStep.Value, app.ui.covStep.Value = step; end
            app.covRefresh(); app.covSetXLim([min(thr) max(thr)], true);
            app.covStatus(sprintf('Coverage results file "%s" loaded (%d curves).', name, width(R) - 1));
        end

        function jobs = covJobNodes(app, roots)
            % Live job nodes in creation order, optionally restricted to the subtree(s) under ROOTS.
            app.covJobs = app.covJobs(cellfun(@isvalid, app.covJobs)); jobs = [app.covJobs{:}];
            if nargin > 1 && ~isempty(roots) && ~isempty(jobs), jobs = jobs(ismember(jobs, findobj(roots))); end
        end

        function node = covTarget(app)
            % Pattern node to operate on: the selection (or its pattern ancestor), else the most recently added pattern.
            node = []; sel = app.ui.covTree.SelectedNodes; kids = app.ui.covRoot.Children;
            if ~isempty(sel)
                n = sel(1);
                while isa(n, 'matlab.ui.container.TreeNode')
                    if isstruct(n.NodeData) && strcmp(n.NodeData.kind, 'pattern'), node = n; return; end
                    n = n.Parent;
                end
            end
            for k = numel(kids):-1:1
                if isstruct(kids(k).NodeData) && strcmp(kids(k).NodeData.kind, 'pattern'), node = kids(k); return; end
            end
        end

        function node = covNodeByPath(app, fp)
            node = []; kids = app.ui.covRoot.Children;
            for k = 1:numel(kids)
                if isstruct(kids(k).NodeData) && strcmp(kids(k).NodeData.path, fp), node = kids(k); return; end
            end
        end

        function covRefresh(app)
            % Rebuild the results table, legend and control states from the tree.
            u = app.ui; jobs = app.covJobNodes(); on = jobs;
            if ~isempty(jobs), on = jobs(ismember(jobs, u.covTree.CheckedNodes)); end
            thr = app.covThresholds(); lines = gobjects(1, numel(on)); labels = cell(1, numel(on));
            if ~isempty(on), cells = arrayfun(@(n) n.NodeData.thr, on, 'UniformOutput', false); thr = unique(vertcat(cells{:})); end
            M = nan(numel(thr), numel(on) + 1); M(:, 1) = thr; names = [{'Threshold (dB)'}, cell(1, numel(on))];
            for k = 1:numel(on)
                d = on(k).NodeData; M(:, k + 1) = interp1(d.thr, d.cov, thr, 'linear', NaN);
                names{k + 1} = sprintf('R%d %s %%', d.id, d.tableTag); lines(k) = d.line; labels{k} = d.label;
            end
            u.covTable.Data = array2table(compose('%.2f', M), 'VariableNames', names);
            if isempty(on), legend(u.covAxes, 'off'); else, legend(u.covAxes, lines, labels, 'Location', 'southwest', 'Interpreter', 'none'); end
            hasPattern = ~isempty(app.covTarget()); hasJobs = ~isempty(jobs); resultsOnly = ~hasPattern && hasJobs;
            u.covResultsPanel.Visible = hasPattern || hasJobs;
            set(u.covParamGrid.Children, 'Visible', hasPattern);
            set([u.covPathLabel u.covPath u.covLoad u.covCompute], 'Visible', 'on');
            if resultsOnly, set([u.covQueryCtl u.covReset u.covExport u.covClear u.covToMain], 'Visible', 'on'); end
            set([u.covCompute u.covComp u.covCompLabel], 'Enable', hasPattern); u.covReset.Enable = hasPattern || hasJobs;
            set([u.covExport u.covClear u.covQueryCtl], 'Enable', hasJobs);
            set([u.covFormatLabel u.covFormat], 'Visible', hasPattern && isGenericText(u.covPath.Value));
            app.onCovType();
        end

        function onCovChecked(app, ~, ~)
            jobs = app.covJobNodes(); checked = app.ui.covTree.CheckedNodes;
            for k = 1:numel(jobs)
                d = jobs(k).NodeData; set([d.line; app.covArtifacts(d)], 'Visible', ismember(jobs(k), checked));
            end
            app.covRefresh();
        end

        function onCovSelection(app, ~, ~)
            sel = app.ui.covTree.SelectedNodes; jobs = app.covJobNodes();
            for k = 1:numel(jobs), d = jobs(k).NodeData; d.line.LineWidth = 1.6 + (~isempty(sel) && jobs(k) == sel(1)); end
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.covStatus('Ready.'); return; end
            d = sel(1).NodeData; target = app.covTarget(); if ~isempty(target), app.covSync(target); end
            if ~strcmp(d.kind, 'job')
                n = numel(sel(1).Children); kind = 'Pattern'; if strcmp(d.kind, 'results'), kind = 'Results'; end
                app.covStatus(sprintf('%s <b>"%s"</b> — <b>%d</b> coverage job%s.', kind, d.name, n, repmat('s', 1, n ~= 1)));
                if strcmp(d.kind, 'pattern'), app.covReportOrientation(); end
                return
            end
            t50 = app.covQueryPoint(d, "thr", 50); shown = round(d.cov, 2); best = find(shown == max(shown), 1, 'last');
            parts = {d.label};
            if d.conical, parts{end + 1} = sprintf('Orientation <b>%s</b>', d.orientation); end
            parts{end + 1} = sprintf('Threshold [%s, %s] dB, step %s dB', fmt(d.thr(1)), fmt(d.thr(end)), fmt(gridStep(d.thr)));
            if isfinite(t50), parts{end + 1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', fmt(t50)); else, parts{end + 1} = '<b>50%-coverage unavailable</b>'; end
            if ~isempty(best), parts{end + 1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmt(shown(best)), fmt(d.thr(best))); end
            app.covStatus(strjoin(parts, ' | '));
        end

        function [x, y] = covQueryPoint(~, d, mode, q)
            % "cov": coverage at threshold q.  "thr": threshold at coverage q (inverse of the non-increasing CCDF).
            if mode == "cov", x = q; y = interp1(d.thr, d.cov, q, 'linear', NaN);
            else, [c, i] = unique(d.cov, 'last'); y = q; x = NaN; if numel(c) > 1, x = interp1(c, d.thr(i), q, 'linear', NaN); end, end
        end

        function objs = covArtifacts(app, d)
            objs = [findall(app.ui.covAxes, '-regexp', 'Tag', sprintf('^CovQ_%d_', d.id)); findall(d.line, 'Type', 'datatip')];
        end

        function onCovQuery(app, mode)
            % Project the query point of every checked job under the selection onto the axes and pin an interpolated DataTip.
            ax = app.ui.covAxes; sel = app.ui.covTree.SelectedNodes;
            if mode == "cov", q = app.ui.covQueryCov.Value; else, q = app.ui.covQueryThr.Value; end
            if isempty(sel), app.covStatus('Select a node to query.', true); return; end
            jobs = app.covJobNodes(sel); if ~isempty(jobs), jobs = jobs(ismember(jobs, app.ui.covTree.CheckedNodes)); end
            hit = false;
            for k = 1:numel(jobs)
                d = jobs(k).NodeData; tag = sprintf('CovQ_%d_%s', d.id, mode);
                delete([findall(ax, 'Tag', tag); findall(d.line, 'Type', 'datatip', 'Tag', tag)]);
                [x, y] = app.covQueryPoint(d, mode, q); if ~isfinite(x) || ~isfinite(y), continue; end
                line(ax, [x x], [ax.YLim(1) y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [app.RangeBounds(1) x], [y y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'FontSize', 9, 'Tag', tag); hit = true;
            end
            if ~hit, app.covStatus('Query value is outside the range of the selected checked results.', true);
            elseif mode == "cov", app.covStatus(sprintf('Coverage queried at %s dB.', fmt(q)));
            else, app.covStatus(sprintf('Threshold queried at %s%% coverage.', fmt(q))); end
        end

        function onCovClear(app, ~, ~)
            sel = app.ui.covTree.SelectedNodes; jobs = app.covJobNodes(sel);
            if isempty(sel) || isempty(jobs), app.covStatus('Select a node with coverage results to clear.', true); return; end
            for k = 1:numel(jobs), delete(app.covArtifacts(jobs(k).NodeData)); end
            app.covStatus('Selected DataTips and query markers cleared.', true);
        end

        function onCovReset(app, ~, ~)
            u = app.ui; delete(u.covRoot.Children); app.covJobs = {}; app.covRunID = 0; app.covPresetKey = "";
            cla(u.covAxes); legend(u.covAxes, 'off'); u.covTable.Data = table(); u.covThrMin.UserData = false; u.covAxes.UserData = false;
            app.covSetXLim([-40 10], false); app.covRefresh(); app.covStatus('Coverage workspace reset 🔄', true);
        end

        function onCovExport(app, ~, ~)
            if isempty(app.ui.covTable.Data), return; end
            app.saveTable(app.ui.covTable.Data, 'Coverage results', 'coverage_results.csv', ...
                {'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, app.ui.covBar);
        end

        function onCovType(app, ~, ~)
            conical = app.ui.covConical.Value; hasPattern = ~isempty(app.covTarget());
            set(app.ui.covConeCtl, 'Visible', conical && hasPattern, 'Enable', conical);
            if conical, app.covReportOrientation();
            else, app.covStatus(regexprep(app.ui.covBar.UserData, '\s*\|\s*Orientation <b>.*?</b>', '')); end
        end

        function covReportOrientation(app)
            % Append the resolved conical orientation (Auto → detected axis) to the persistent Coverage status.
            if ~app.ui.covConical.Value, return; end
            i = app.ui.covOrientation.Value; node = app.covTarget();
            if i == 0, if isempty(node), return; end, i = node.NodeData.boresight; end
            current = regexprep(app.ui.covBar.UserData, '\s*\|\s*Orientation <b>.*?</b>$', '');
            app.covStatus(sprintf('%s | Orientation <b>%s</b>', current, app.PrincipalAxes.labels{i}));
        end

        function onCovOrientation(app, ~, ~)
            % Auto resolves the detected axis; an explicit selection is authoritative and never replaced on compute.
            i = app.ui.covOrientation.Value; node = app.covTarget();
            if i == 0, if isempty(node), return; end, i = node.NodeData.boresight; end
            app.ui.covConeTh.Value = app.PrincipalAxes.theta(i); app.ui.covConePh.Value = app.PrincipalAxes.phi(i);
            app.covReportOrientation();
        end

        function onCovComponent(app, ~, ~)
            node = app.covTarget(); if isempty(node), return; end
            d = node.NodeData; d.comp = app.ui.covComp.Value;
            [~, d.boresight] = calcOrientation(d.T, d.omega, d.comp, app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
            node.NodeData = d;
            if app.ui.covOrientation.Value == 0, app.onCovOrientation(); else, app.covReportOrientation(); end
        end

        function label = coneLabel(app, t, p)
            % Principal-axis name when the cone centre coincides with ±X/±Y/±Z, otherwise the spherical coordinates.
            ax = app.PrincipalAxes; c = [sind(t) * cosd(p), sind(t) * sind(p), cosd(t)];
            A = [sind(ax.theta(:)) .* cosd(ax.phi(:)), sind(ax.theta(:)) .* sind(ax.phi(:)), cosd(ax.theta(:))];
            hit = find(A * c(:) >= 1 - 1e-9, 1);
            if isempty(hit), label = sprintf('θ=%s°, φ=%s°', fmt(t), fmt(p)); else, label = ax.labels{hit}; end
        end

        function covSetXLim(app, b, widenOnly)
            % Coverage X-limits. The first result establishes the baseline; later results only widen it automatically.
            u = app.ui; RB = app.RangeBounds; ax = u.covAxes; b = sort(b);
            if widenOnly && isequal(ax.UserData, true), b = [min(ax.XLim(1), b(1)), max(ax.XLim(2), b(2))]; end
            if widenOnly, ax.UserData = true; end
            if diff(b) < 0.2, b(2) = b(1) + 0.2; end
            set(ax, 'XLimMode', 'manual', 'XLim', b);
            set(u.covXRange, 'Limits', RB, 'Value', b); u.covXRange.Limits = b;
            set([u.covXMin u.covXMax], 'Limits', RB); u.covXMin.Value = b(1); u.covXMax.Value = b(2);
            u.covXMin.Limits = [RB(1), b(2) - 0.1]; u.covXMax.Limits = [b(1) + 0.1, RB(2)];
        end

        function onCovXRange(app, src, evt)
            % Spinners are the master controls (they define the slider travel); the slider only narrows the visible XLim.
            u = app.ui;
            if src == u.covXRange
                v = sort(evt.Value); if diff(v) <= 0, return; end
                u.covXMin.Value = v(1); u.covXMax.Value = v(2); set(u.covAxes, 'XLimMode', 'manual', 'XLim', v);
            else
                app.covSetXLim([u.covXMin.Value u.covXMax.Value], false);
            end
        end
    end

    %% ================================================================ 5. UI construction
    methods (Access = private)
        function h = add(~, h, row, col)
            h.Layout.Row = row; h.Layout.Column = col;
        end

        function h = label(app, g, txt, row, col, varargin)
            h = app.add(uilabel(g, 'Text', txt, 'HorizontalAlignment', 'right', varargin{:}), row, col);
        end

        function dd = formatDropdown(app, g, callback)
            dd = uidropdown(g, 'Items', app.TextFormats(1, :), 'ItemsData', app.TextFormats(2, :), 'Value', 'gain', 'Visible', 'off', ...
                'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'ValueChangedFcn', callback);
        end

        function [sl, mn, mx] = rangeControls(app, g, scope, rows)
            % Vertical range slider with max (top) / min (bottom) spinners wired to setRange(SCOPE). rows = {max, slider, min}.
            RB = app.RangeBounds;
            sl = app.add(uislider(g, 'range', 'Limits', RB, 'Value', [-40 10], 'Orientation', 'vertical', ...
                'ValueChangedFcn', app.cb(@(s, ~) app.setRange(scope, s.Value))), rows{2}, 1);
            mx = app.add(uispinner(g, 'Limits', RB, 'Value', 10, 'Step', 5, 'ValueChangedFcn', app.cb(@(s, ~) app.onRangeEdit(scope, 2, s.Value))), rows{1}, 1);
            mn = app.add(uispinner(g, 'Limits', RB, 'Value', -40, 'Step', 5, 'ValueChangedFcn', app.cb(@(s, ~) app.onRangeEdit(scope, 1, s.Value))), rows{3}, 1);
        end

        function createComponents(app)
            u = struct(); RB = app.RangeBounds; pad = @(n) repmat(char(160), 1, n);   % non-breaking padding centres switch captions
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.Release], 'Visible', 'off', 'Position', [100 100 1136 739], ...
                'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) delete(app));
            u.plotMenu = uicontextmenu(app.UIFigure);
            uimenu(u.plotMenu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, e) app.deleteDataTips(e));
            u.tabs = uitabgroup(uigridlayout(app.UIFigure, [1 1]));
            u.tabMain = uitab(u.tabs, 'Title', 'Process Pattern 📡'); u.tabCov = uitab(u.tabs, 'Title', 'Compute Coverage 📈');
            G = uigridlayout(u.tabMain, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});

            % ---- Inputs & parameters --------------------------------------------------------------------
            P = uigridlayout(app.add(uipanel(G, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 14]), 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            app.label(P, 'Input Pattern:', 1, 1);
            u.path = app.add(uieditfield(P, 'text'), 1, [2 8]);
            u.lblFFD = app.label(P, 'FFD Freq:', 1, 9, 'Visible', 'off');
            u.ddFFD = app.add(uidropdown(P, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', app.cb(@app.onFFDChanged)), 1, 10);
            u.btnLoad = app.add(uibutton(P, 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', app.cb(@app.onLoad)), 1, [11 12]);
            u.btnProcess = app.add(uibutton(P, 'Text', '⚙️ Process', 'ButtonPushedFcn', app.cb(@app.onProcess)), 1, [13 14]);
            u.btnReset = app.add(uibutton(P, 'Text', 'Reset Params', 'ButtonPushedFcn', app.cb(@app.onResetParams)), 2, [1 3]);
            u.lblFormat = app.label(P, 'Format:', 2, [4 5], 'Visible', 'off');
            u.ddFormat = app.add(app.formatDropdown(P, app.cb(@app.onTextFormatChanged)), 2, [6 8]);
            u.ddStep = app.add(uidropdown(P, 'Items', {'STEP', 'STEP: 1°'}, 'ItemsData', {'native', 'one'}, 'Visible', 'off', 'Enable', 'off', ...
                'ValueChangedFcn', app.cb(@app.onStepChanged)), 2, [9 10]);
            u.btnExport = app.add(uibutton(P, 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@app.onExport)), 2, [11 12]);
            u.btnUAN = app.add(uibutton(P, 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@app.onExportUAN)), 2, [13 14]);
            u.lblRx = app.label(P, 'Rw Sense', 3, 1, 'Visible', 'off');       u.ddRxPol = app.add(uidropdown(P, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Visible', 'off'), 3, 2);
            u.lblRw = app.label(P, 'Rw (dB)', 3, 3, 'Visible', 'off');        u.spRw = app.add(uispinner(P, 'Value', 6, 'Visible', 'off'), 3, 4);
            u.lblLoss = app.label(P, 'Loss (−) / Gain (+) dB', 3, 5, 'Visible', 'off'); u.spLoss = app.add(uispinner(P, 'Step', 0.1, 'Visible', 'off'), 3, 6);
            u.lblPt = app.label(P, 'Tx Pwr (Pt)', 3, 7, 'Visible', 'off');    u.spPt = app.add(uispinner(P, 'Visible', 'off'), 3, 8);
            u.ddPt = app.add(uidropdown(P, 'Items', {'dBW', 'dBm', 'Watts'}, 'Visible', 'off'), 3, 9);
            u.lblR = app.label(P, 'Distance', 3, 10, 'Visible', 'off');      u.spR = app.add(uispinner(P, 'Value', 1, 'Visible', 'off'), 3, 11);
            u.ddR = app.add(uidropdown(P, 'Items', {'m', 'km'}, 'Visible', 'off'), 3, 12);
            u.btnCoverage = app.add(uibutton(P, 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@app.onCoverageFromMain)), 3, [13 14]);
            u.paramCtl = [u.spLoss u.ddRxPol u.spRw u.spPt u.ddPt u.spR u.ddR];

            % ---- Full antenna pattern (five lazily rendered tabs) -----------------------------------------
            u.pnlFull = app.add(uipanel(G, 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [1 6]);
            u.tabFull = uitabgroup(uigridlayout(u.pnlFull, [1 1]), 'SelectionChangedFcn', app.cb(@app.onFullTabChanged));
            names = ["contour", "circular", "sphere3D", "polar3D", "rect3D"];
            titles = {'Contour Plot', 'Circular Contour Plot', '3D Spherical Plot', '3D Polar Plot', '3D Surface Plot'};
            F = struct('name', {}, 'tab', {}, 'ax', {}, 'slider', {}, 'spMin', {}, 'spMax', {}, 'render', {}, 'dirty', {});
            for k = 1:5
                t = uitab(u.tabFull, 'Title', titles{k}); g = uigridlayout(t, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
                if k == 2, ax = polaraxes(g); else, ax = uiaxes(g); end
                ax.Layout.Row = [1 3]; ax.Layout.Column = 2;
                [sl, mn, mx] = app.rangeControls(g, "full", {1, 2, 3});
                F(k) = struct('name', names(k), 'tab', t, 'ax', ax, 'slider', sl, 'spMin', mn, 'spMax', mx, 'render', [], 'dirty', true);
            end
            F(1).render = @() app.drawContour(); F(2).render = @() app.drawCircular();
            F(3).render = @() app.draw3D(F(3).ax, "sphere"); F(4).render = @() app.draw3D(F(4).ax, "polar"); F(5).render = @() app.draw3D(F(5).ax, "rect");
            app.full = F; u.axContour = F(1).ax; u.paxFull = F(2).ax;

            % ---- Antenna pattern cut ---------------------------------------------------------------------
            u.pnlCut = app.add(uipanel(G, 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [7 12]);
            u.tabCut = uitabgroup(uigridlayout(u.pnlCut, [1 1]));
            u.tabPolar = uitab(u.tabCut, 'Title', 'Polar Cut Plot'); u.tabRect = uitab(u.tabCut, 'Title', 'Rectangular Cut Plot');
            gp = uigridlayout(u.tabPolar, 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            u.paxCut = polaraxes(gp); u.paxCut.Layout.Row = [1 4]; u.paxCut.Layout.Column = 3;
            [u.sliderCut, u.spCutMin, u.spCutMax] = app.rangeControls(gp, "cut", {1, [2 3], 4});
            u.btnHPBW = app.add(uibutton(gp, 'state', 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', app.cb(@app.onCutChanged)), 1, 4);
            u.lblHPBW = app.add(uilabel(gp, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold'), 2, 4);
            u.gridEcut = app.add(uigridlayout(gp, [3 1]), 3, 4);
            u.cbEt = app.add(uicheckbox(u.gridEcut, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', app.cb(@app.onCutChanged)), 1, 1);
            u.cbEr = app.add(uicheckbox(u.gridEcut, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', app.cb(@app.onCutChanged)), 2, 1);
            u.cbEl = app.add(uicheckbox(u.gridEcut, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', app.cb(@app.onCutChanged)), 3, 1);
            u.btnExportCut = app.add(uibutton(gp, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', app.cb(@app.onExportCut)), 4, 4);
            u.axRect = uiaxes(uigridlayout(u.tabRect, [1 1])); ylabel(u.axRect, 'Magnitude (dB)');

            % ---- Plot control ----------------------------------------------------------------------------
            u.pnlCtrl = app.add(uipanel(G, 'Title', 'Plot Control 🎨', 'Visible', 'off'), 2, [13 14]);
            C = uigridlayout(u.pnlCtrl, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', repmat({'fit'}, 1, 15));
            app.label(C, 'Component', 1, 1);
            u.ddComp = app.add(uidropdown(C, 'Items', cellstr(app.ComponentLabels(:, 2)), 'ItemsData', cellstr(app.ComponentLabels(:, 1)), ...
                'ValueChangedFcn', app.cb(@app.onComponentChanged)), 1, 2);
            app.label(C, 'Cut type', 2, 1);  u.ddCutType = app.add(uidropdown(C, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', app.cb(@app.onCutChanged)), 2, 2);
            app.label(C, 'Cut value', 3, 1); u.spCutValue = app.add(uispinner(C, 'Limits', [0 360], 'ValueChangedFcn', app.cb(@app.onCutChanged)), 3, 2);
            app.label(C, 'Cut fields', 4, 1);
            u.ddCutBasis = app.add(uidropdown(C, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Enable', 'off', ...
                'UserData', true, 'ValueChangedFcn', app.cb(@app.onCutChanged)), 4, 2);
            app.label(C, 'Colorbar max', 5, 1);  u.spCmax = app.add(uispinner(C, 'Limits', RB, 'Value', 10, 'ValueChangedFcn', app.cb(@app.applyColorbar)), 5, 2);
            app.label(C, 'Colorbar min', 6, 1);  u.spCmin = app.add(uispinner(C, 'Limits', RB, 'Value', -40, 'ValueChangedFcn', app.cb(@app.applyColorbar)), 6, 2);
            app.label(C, 'Colorbar step', 7, 1); u.spCstep = app.add(uispinner(C, 'Limits', [0.1 100], 'Value', 5, ...
                'ValueChangedFcn', app.cb(@(~, ~) app.setRange("full", app.colorLimits()))), 7, 2);
            app.label(C, 'Adjust Colorbar', 8, 1); u.btnClim = app.add(uibutton(C, 'Text', 'Apply', 'ButtonPushedFcn', app.cb(@app.applyColorbar)), 8, 2);
            app.label(C, '3D view', 9, 1);
            u.dd3DView = app.add(uidropdown(C, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'ValueChangedFcn', app.cb(@app.on3DViewChanged)), 9, 2);
            u.swPhi = app.add(uiswitch(C, 'slider', 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, ...
                'ValueChangedFcn', app.cb(@app.onSpanChanged)), 10, [1 2]);
            u.swTheta = app.add(uiswitch(C, 'slider', 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, ...
                'ValueChangedFcn', app.cb(@app.onSpanChanged)), 11, [1 2]);
            u.swEH = app.add(uiswitch(C, 'slider', 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E', 'H'}, 'ValueChangedFcn', app.cb(@app.onEHPlane)), 12, [1 2]);
            u.cbOverlay = app.add(uicheckbox(C, 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', app.cb(@app.refreshOverlays)), 13, [1 2]);
            u.cbPOB = app.add(uicheckbox(C, 'Text', 'Annotate POB', 'ValueChangedFcn', app.cb(@app.applyAnnotationVisibility)), 14, [1 2]);
            u.cbHPBWBounds = app.add(uicheckbox(C, 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', app.cb(@app.applyAnnotationVisibility)), 15, [1 2]);

            % ---- Data tables & status --------------------------------------------------------------------
            u.ddOutput = app.add(uidropdown(G, 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Visible', 'off', ...
                'UserData', struct('cols', {{}}, 'on', false(1, 0)), 'ValueChangedFcn', app.cb(@app.filterOutput)), 3, [13 14]);
            u.tabData = app.add(uitabgroup(G, 'Visible', 'off'), 4, [1 14]);
            tOut = uitab(u.tabData, 'Title', 'Results 📤', 'ButtonDownFcn', @(~, ~) set(u.ddOutput, 'Visible', 'on'));
            u.tblOut = uitable(uigridlayout(tOut, [1 1]), 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnRearrangeable', 'on');
            u.tblIn = uitable(uigridlayout(uitab(u.tabData, 'Title', 'Input 📥'), [1 1]), 'ColumnSortable', true, 'RowName', 'numbered', 'UserData', false);
            u.tblMeta = uitable(uigridlayout(uitab(u.tabData, 'Title', 'Metadata 📋'), [1 1]), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            u.bar = app.add(uilabel(G, 'Text', 'Ready 🚀', 'Interpreter', 'html'), 5, [1 14]);

            % ---- Coverage tab ----------------------------------------------------------------------------
            K = uigridlayout(u.tabCov, 'ColumnWidth', {'1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            Q = uigridlayout(app.add(uipanel(K, 'Title', 'Inputs & Parameters 🎛️'), 1, 1), 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'});
            u.covParamGrid = Q;
            bg = app.add(uibuttongroup(Q, 'Title', 'Coverage Type', 'SelectionChangedFcn', app.cb(@app.onCovType)), [1 2], [1 2]);
            u.covSpherical = uiradiobutton(bg, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            u.covConical = uiradiobutton(bg, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            u.covOrientationLabel = app.label(Q, 'Orientation 🧭:', 3, 1);
            u.covOrientation = app.add(uidropdown(Q, 'Items', [{'Auto'}, app.PrincipalAxes.labels], 'ItemsData', 0:6, 'Value', 0, 'ValueChangedFcn', app.cb(@app.onCovOrientation)), 3, 2);
            u.covCompLabel = app.label(Q, 'Component:', 4, 1, 'Enable', 'off');
            u.covComp = app.add(uidropdown(Q, 'Items', {'E_Total_dB'}, 'Enable', 'off', 'ValueChangedFcn', app.cb(@app.onCovComponent)), 4, 2);
            u.covPathLabel = app.label(Q, 'Antenna Pattern:', 1, 3);
            u.covPath = app.add(uieditfield(Q, 'text'), 1, [4 8]);
            u.covLoad = app.add(uibutton(Q, 'Text', '📂 Load File', 'ButtonPushedFcn', app.cb(@app.onCovLoad)), 1, 9);
            u.covCompute = app.add(uibutton(Q, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@app.onCovCompute)), 1, 10);
            app.label(Q, 'Threshold  Min (dB):', 2, 3); u.covThrMin = app.add(uispinner(Q, 'Value', -40, 'Limits', RB, 'UserData', false), 2, 4);
            app.label(Q, 'Threshold  Max (dB):', 2, 5); u.covThrMax = app.add(uispinner(Q, 'Value', 10, 'Limits', RB), 2, 6);
            app.label(Q, 'Step (dB):', 2, 7);           u.covStep = app.add(uispinner(Q, 'Value', 1, 'Limits', [0.01 100]), 2, 8);
            u.covReset = app.add(uibutton(Q, 'Text', '🔄 Reset', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@app.onCovReset)), 2, 9);
            u.covExport = app.add(uibutton(Q, 'Text', '💾 Export Results', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@app.onCovExport)), 2, 10);
            l1 = app.label(Q, 'Cone θ₀ (°):', 3, 3);       u.covConeTh = app.add(uispinner(Q, 'Limits', [0 180]), 3, 4);
            l2 = app.label(Q, 'Cone φ₀ (°):', 3, 5);       u.covConePh = app.add(uispinner(Q, 'Limits', [0 360]), 3, 6);
            l3 = app.label(Q, 'Cone Angle α (°):', 3, 7);  u.covConeAng = app.add(uispinner(Q, 'Limits', [0 180], 'Value', 45), 3, 8);
            u.covConeCtl = [l1 u.covConeTh l2 u.covConePh l3 u.covConeAng u.covOrientationLabel u.covOrientation];
            u.covClear = app.add(uibutton(Q, 'Text', '🧹 Clear DataTips', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@app.onCovClear)), 3, 9);
            u.covToMain = app.add(uibutton(Q, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~, ~) set(u.tabs, 'SelectedTab', u.tabMain)), 3, 10);
            q1 = app.label(Q, 'Coverage @ dB:', 4, 3);  u.covQueryCov = app.add(uispinner(Q, 'ValueDisplayFormat', '%g dB'), 4, 4);
            b1 = app.add(uibutton(Q, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', app.cb(@(~, ~) app.onCovQuery("cov"))), 4, 5);
            q2 = app.label(Q, 'Threshold @ %:', 4, 6);  u.covQueryThr = app.add(uispinner(Q, 'ValueDisplayFormat', '%g%%', 'Value', 50, 'Limits', [0 100]), 4, 7);
            b2 = app.add(uibutton(Q, 'Text', '🔍 Query Threshold', 'ButtonPushedFcn', app.cb(@(~, ~) app.onCovQuery("thr"))), 4, 8);
            u.covQueryCtl = [q1 u.covQueryCov b1 q2 u.covQueryThr b2];
            u.covFormatLabel = app.label(Q, 'Format:', 4, 9);
            u.covFormat = app.add(app.formatDropdown(Q, app.cb(@app.onCovFormatChanged)), 4, 10);
            u.covResultsPanel = app.add(uipanel(K, 'Title', 'Results', 'Visible', 'off'), 2, 1);
            R = uigridlayout(u.covResultsPanel, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            u.covTree = app.add(uitree(R, 'checkbox', 'SelectionChangedFcn', app.cb(@app.onCovSelection), 'CheckedNodesChangedFcn', app.cb(@app.onCovChecked)), [1 2], 1);
            u.covRoot = uitreenode(u.covTree, 'Text', 'Coverage Results');
            u.covAxes = app.add(uiaxes(R), 1, [2 4]);
            title(u.covAxes, 'Coverage vs Threshold'); xlabel(u.covAxes, 'Threshold (dB)'); ylabel(u.covAxes, 'Coverage (%)');
            u.covTable = app.add(uitable(R, 'ColumnWidth', '1x', 'RowName', {}), [1 2], 5);
            u.covXMin = app.add(uispinner(R, 'Limits', RB, 'Value', -40, 'ValueChangedFcn', app.cb(@app.onCovXRange)), 2, 2);
            u.covXRange = app.add(uislider(R, 'range', 'Limits', RB, 'Value', [-40 10], 'ValueChangedFcn', app.cb(@app.onCovXRange), ...
                'ValueChangingFcn', app.cb(@app.onCovXRange)), 2, 3);
            u.covXMax = app.add(uispinner(R, 'Limits', RB, 'Value', 10, 'ValueChangedFcn', app.cb(@app.onCovXRange)), 2, 4);
            u.covBar = app.add(uilabel(K, 'Text', 'Ready 🚀', 'Interpreter', 'html'), 3, 1);
            app.ui = u;
            app.UIFigure.Visible = 'on';
        end

        function startupFcn(app)
            u = app.ui;
            for k = 1:numel(app.full)
                ax = app.full(k).ax; if isa(ax, 'matlab.graphics.axis.PolarAxes'), continue; end
                enableDefaultInteractivity(ax);
                if k >= 3, ax.Interactions = [rotateInteraction dataTipInteraction]; else, ax.Interactions = [zoomInteraction dataTipInteraction]; end
            end
            enableDefaultInteractivity(u.axRect); u.axRect.Interactions = [zoomInteraction dataTipInteraction];
            hold(u.covAxes, 'on'); grid(u.covAxes, 'on'); ylim(u.covAxes, [0 100]);
            set(u.covAxes, 'Box', 'on', 'Layer', 'top', 'Interactions', dataTipInteraction);
            app.defaults = get(u.paramCtl, 'Value');
            [u.bar.Text, u.covBar.Text, u.bar.UserData, u.covBar.UserData] = deal('Ready — load an antenna pattern file to begin 🚀');
            app.covRefresh();
        end
    end
end

%% ==================================================================== I/O readers (pure functions)
function tf = isGenericText(fp)
[~, ~, e] = fileparts(fp); tf = ismember(lower(e), {'.csv', '.txt', '.dat'});
end

function out = readPattern(fp, kind, cached)
%readPattern Universal source reader -> struct(raw, blocks, freqs, ud).
%   blocks{k}: primitive table {Theta, Phi, Re_Eth, Im_Eth, Re_Eph, Im_Eph} (E-field) or {Theta, Phi, gain columns}.
%   KIND is the generic text interpretation (see TextFormats); CACHED lets generic files be re-interpreted without re-reading.
if nargin < 3, cached = table(); end
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
ud = struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'isMultiBlock', false, 'hasFrequency', false);
out = struct('raw', table(), 'blocks', {{}}, 'freqs', NaN, 'ud', ud);
switch ext
    case {'XLSX', 'XLS'},                        out = readExcelMatrix(fp, out);
    case {'CSV', 'TXT', 'DAT'},                  out = readGenericText(fp, string(kind), cached, out);
    case 'CUT',                                  out = readGraspCut(fp, out);
    case {'UAN', 'FZ', 'OUT', 'FFS', 'FFE', 'FFD'}, out = readFarField(fp, ext, out);
    otherwise, error('APAT:io:Unsupported', 'Unsupported format: %s', ext);
end
end

function out = readGenericText(fp, kind, T, out)
% Generic numeric tables: coverage results, gain-only patterns, or six-column E-field data interpreted per KIND.
if isempty(T)
    opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
    T = rmmissing(readtable(fp, opts));
end
n = width(T); assert(n >= 2 && ~isempty(T), 'APAT:io:Format', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHeaders = ~all(startsWith(names, "Var")); c1 = T{:, 1}; c2 = T{:, 2};
coverageHeader = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
if (kind == "gain" || n < 6 || coverageHeader) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:n - 1))]; end
    out.raw = T; out.ud.isCoverage = true; return
end
if kind == "gain"   % gain-only pattern: the column with the larger span is φ
    assert(n >= 3, 'APAT:io:Format', 'A gain pattern needs theta, phi and at least one gain column.');
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    T = movevars(T, 'Theta', 'Before', 1);
    out.raw = T; out.blocks = {T}; out.ud.isGainOnly = true; out.ud.source = 'Generic text (gain)'; return
end
assert(n >= 6, 'APAT:io:Format', 'The selected generic E-field format requires six numeric columns.');
V = T{:, 3:6}; magphase = endsWith(kind, "magphase"); layout = "n/a";
if magphase   % phase columns exceed 100 in magnitude: grouped [m1 m2 p1 p2] versus interleaved [m1 p1 m2 p2]
    big = max(abs(V), [], 1, 'omitnan') > 100;
    if big(2) && ~big(3), mc = [1 3]; pc = [2 4]; layout = "interleaved"; else, mc = [1 2]; pc = [3 4]; layout = "grouped"; end
    A = mp2c(V(:, mc(1)), V(:, pc(1))); B = mp2c(V(:, mc(2)), V(:, pc(2)));
else
    A = complex(V(:, 1), V(:, 2)); B = complex(V(:, 3), V(:, 4));
end
if startsWith(kind, "linear"), Eth = A; Eph = B; tags = ["E_TH", "E_PH"]; rect = ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"];
else, tags = ["POL1", "POL2"]; rect = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"];
    if startsWith(kind, "rcp"), [Eth, Eph] = circ2lin(A, B); else, [Eth, Eph] = circ2lin(B, A); end
end
if ~hasHeaders
    if magphase, f = [tags + "_dB", tags + "_deg"]; if layout == "interleaved", f = f([1 3 2 4]); end, else, f = rect; end
    T.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", f]);
end
out.ud.source = sprintf('Generic text (%s, %s)', kind, layout); out.raw = T; out.blocks = {efield(c1, c2, Eth, Eph)};
end

function out = readFarField(fp, ext, out)
% Column-oriented far-field exports: XGTD UAN/FZ, GRASP OUT, CST FFS, FEKO FFE, HFSS FFD (grid + blocks from header).
[nHdr, ffd] = scanHeader(fp, strcmp(ext, 'FFD'));
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = readmatrix(fp, setvartype(opts, opts.VariableNames, 'double'));
M = M(~all(isnan(M), 2), 1:min(size(M, 2), 6));
if strcmp(ext, 'FFD')
    out.ud.source = 'HFSS FFD'; assert(ffd.isFFD, 'APAT:io:FFD', 'FFD header (theta/phi ranges) not found.');
    th = linspace(ffd.theta(1), ffd.theta(2), ffd.theta(3)).'; ph = linspace(ffd.phi(1), ffd.phi(2), ffd.phi(3)).';
    theta = repelem(th, numel(ph)); phi = repmat(ph, numel(th), 1); n = numel(theta);
    sep = isnan(M(:, 1)); freqs = [ffd.freq(:); M(sep & isfinite(M(:, 2)), 2)].'; F = M(~sep, 1:4);   % "Frequency <f>" separator rows
    assert(mod(size(F, 1), n) == 0, 'APAT:io:FFD', 'FFD row count does not match the theta/phi grid.');
    nb = size(F, 1) / n; freqs(end + 1:nb) = NaN; freqs = freqs(1:nb);
    out.ud.isMultiBlock = nb > 1; out.ud.hasFrequency = any(isfinite(freqs)); out.ud.isDep = out.ud.isMultiBlock || out.ud.hasFrequency;
    out.blocks = cell(1, nb);
    for b = 1:nb, R = F((b - 1) * n + (1:n), :); out.blocks{b} = efield(theta, phi, complex(R(:, 1), R(:, 2)), complex(R(:, 3), R(:, 4))); end
    out.freqs = freqs; out.raw = out.blocks{1}; return
end
theta = M(:, 1); phi = M(:, 2);
switch ext
    case {'UAN', 'FZ'}   % Theta Phi |Eθ|dB |Eφ|dB ∠Eθ ∠Eφ
        out.ud.source = ['XGTD ' ext]; names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'};
        Eth = mp2c(M(:, 3), M(:, 5)); Eph = mp2c(M(:, 4), M(:, 6));
    case 'OUT'           % Theta Phi Re/Im(POL1=RHCP) Re/Im(POL2=LHCP)
        out.ud.source = 'TICRA/GRASP OUT'; names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'};
        [Eth, Eph] = circ2lin(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)));
    case 'FFS'           % Phi Theta Re/Im(Eθ) Re/Im(Eφ)
        out.ud.source = 'CST FFS'; names = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; [theta, phi] = deal(phi, theta);
        Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
    otherwise            % FFE: Theta Phi Re/Im(Eθ) Re/Im(Eφ); extra columns ignored
        out.ud.source = 'FEKO FFE'; names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'};
        Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
end
out.raw = array2table(M(:, 1:6), 'VariableNames', names); out.blocks = {efield(theta, phi, Eth, Eph)};
end

function [nHdr, ffd] = scanHeader(fp, expectFFD)
% Number of leading non-data lines. For FFD files: two "start stop count" triples + optional "Frequencies ..." line.
ffd = struct('theta', [], 'phi', [], 'freq', [], 'isFFD', false);
fid = fopen(fp, 'r'); assert(fid > 0, 'APAT:io:Open', 'Cannot open file: %s', fp); cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
L = cell(0, 1);
for k = 1:200, s = fgetl(fid); if ~ischar(s), break; end, L{end + 1, 1} = s; end %#ok<AGROW>
tok = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?';
triple = sprintf('^\\s*%s(?:\\s+%s){2}\\s*$', tok, tok);            % exactly three numbers
dataRow = sprintf('^\\s*%s(?:[\\s,;]+%s){3,}\\s*$', tok, tok);      % at least four numeric fields
ne = find(~cellfun(@(s) isempty(strtrim(s)), L));
if expectFFD && numel(ne) >= 2 && ~isempty(regexp(L{ne(1)}, triple, 'once')) && ~isempty(regexp(L{ne(2)}, triple, 'once'))
    t = sscanf(L{ne(1)}, '%f').'; p = sscanf(L{ne(2)}, '%f').';
    ffd.theta = [t(1) t(2) round(t(3))]; ffd.phi = [p(1) p(2) round(p(3))]; ffd.isFFD = all(isfinite([t p])) && t(3) >= 1 && p(3) >= 1;
    nHdr = ne(2);
    if numel(ne) >= 3
        tk = regexp(strtrim(L{ne(3)}), '^frequenc(?:y|ies)\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tk), f = sscanf(tk{1}, '%f'); if ~isscalar(f), ffd.freq = f(:); end, nHdr = ne(3); end   % scalar = count only
    end
    return
end
nHdr = 0;
for k = 1:numel(L), if ~isempty(regexp(L{k}, dataRow, 'once')), break; end, nHdr = k; end
end

function out = readGraspCut(fp, out)
% TICRA/GRASP .cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks, one φ (or θ) cut each.
out.ud.source = 'TICRA/GRASP CUT';
L = readlines(fp); L(strlength(strtrim(L)) == 0) = [];
th = {}; ph = {}; D = {}; i = 1; icomp = 1; icut = 1;
while i < numel(L)
    p = sscanf(L(i + 1), '%f'); assert(numel(p) >= 7, 'APAT:io:Cut', 'Could not parse the cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6);
    B = reshape(sscanf(strjoin(L(i + 2:i + 1 + n), ' '), '%f'), 2 * p(7), []).';
    th{end + 1} = p(1) + (0:n - 1).' * p(2); ph{end + 1} = repmat(p(4), n, 1); D{end + 1} = B(:, 1:4); i = i + 2 + n; %#ok<AGROW>
end
theta = vertcat(th{:}); phi = vertcat(ph{:}); D = vertcat(D{:});
if icut == 2, [theta, phi] = deal(phi, theta); end                       % ICUT=2: φ swept, θ constant
neg = theta < 0; phi(neg) = phi(neg) + 180; theta(neg) = -theta(neg);      % fold negative θ onto the opposite φ
if isscalar(unique(phi))                                                   % single cut -> body of revolution every 10°
    m = numel(theta); theta = repmat(theta, 36, 1); phi = repelem((0:10:350).', m); D = repmat(D, 36, 1);
end
A = complex(D(:, 1), D(:, 2)); B = complex(D(:, 3), D(:, 4));
if icomp == 2, names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; [Eth, Eph] = circ2lin(A, B);
else, names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; Eth = A; Eph = B; end
out.raw = array2table([theta phi D], 'VariableNames', [{'Theta', 'Phi'} names]); out.blocks = {efield(theta, phi, Eth, Eph)};
end

function out = readExcelMatrix(fp, out)
% Excel matrix templates: summary sheet first, then fixed component sheets (C3-origin matrices: row 2 = φ, column B = θ).
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"];
lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'APAT:io:Excel', 'Unsupported workbook: expected the fixed Etheta/Ephi and/or RHCP/LHCP component sheets after the summary sheet.');
req = [circ(1:4 * hasC) lin(1:4 * hasL)]; M = struct(); ref = {};
for s = req
    [th, ph, D] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, s), 1)));
    if isempty(ref), ref = {th, ph};
    else, assert(isequal(size(th), size(ref{1})) && isequal(size(ph), size(ref{2})) && max(abs(th - ref{1})) < 1e-9 && max(abs(ph - ref{2})) < 1e-9, ...
            'APAT:io:Excel', 'All component sheets must share the same theta/phi grid.'); end
    M.(s) = D;
end
[PH, TH] = meshgrid(ref{2}, ref{1});
if hasL, Eth = mp2c(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = mp2c(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees); code = 1 + 2 * hasC;
else, [Eth, Eph] = circ2lin(mp2c(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), mp2c(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees)); code = 2; end
blk = efield(TH(:), PH(:), Eth(:), Eph(:)); raw = blk;
for s = req, raw.(s) = M.(s)(:); end
ud = readExcelSummary(fp, sheets(1)); ud.source = sprintf('Excel Matrix Format %d', code); ud.hasFrequency = isfinite(ud.frequencyMHz);
[ud.isGainOnly, ud.isCoverage, ud.isDep, ud.isMultiBlock] = deal(false);
out.raw = raw; out.blocks = {blk}; out.ud = ud;
end

function [th, ph, D] = readMatrixSheet(fp, sheet)
% readcell keeps worksheet coordinates (readmatrix would auto-trim and break the C3-origin convention).
C = readcell(fp, 'Sheet', char(sheet));
assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'APAT:io:Excel', 'Sheet "%s" does not contain a C3-origin matrix.', sheet);
isNum = @(c) cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), c);
pm = isNum(C(2, 3:end)); tm = isNum(C(3:end, 2));
np = find([~pm true], 1) - 1; nt = find([~tm; true], 1) - 1;   % contiguous leading numeric runs define the axes
assert(np > 0 && nt > 0 && ~any(pm(np + 1:end)) && ~any(tm(nt + 1:end)), 'APAT:io:Excel', 'Sheet "%s" has a gap in, or no numeric, theta/phi axes.', sheet);
ph = cell2mat(C(2, 3:2 + np)).'; th = cell2mat(C(3:2 + nt, 2)); cells = C(3:2 + nt, 3:2 + np);
assert(all(isNum(cells), 'all'), 'APAT:io:Excel', 'Sheet "%s" contains non-numeric/missing matrix samples.', sheet);
D = cell2mat(cells);
assert(all(diff(th) > 0) && all(diff(ph) > 0) && th(1) >= -1e-9 && th(end) <= 180 + 1e-9 && ph(1) >= -1e-9 && ph(end) < 360 + 1e-9, ...
    'APAT:io:Excel', 'Sheet "%s" axes must be strictly increasing within theta 0..180 and phi 0..360.', sheet);
end

function ud = readExcelSummary(fp, sheet)
% Summary sheet -> metadata: every "Label:" in column B becomes a key (first value in C..E); frequency is parsed explicitly.
ud = struct('frequencyMHz', NaN, 'summarySheet', char(sheet));
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
for r = 1:size(C, 1)
    lab = C{r, 2}; if ~(ischar(lab) || isstring(lab)) || strlength(strtrim(string(lab))) == 0, continue; end
    vals = C(r, 3:min(end, 5)); vals = vals(~cellfun(@(v) isempty(v) || isa(v, 'missing'), vals));
    if isempty(vals), continue; end
    key = matlab.lang.makeValidName(lower(regexprep(strtrim(string(lab)), '[^a-zA-Z0-9]+', '_')));
    ud.(key) = vals{1};
end
f = fieldnames(ud); k = f(contains(f, 'simulation_freq')); if ~isempty(k), ud.frequencyMHz = toDouble(ud.(k{1})); end
end

function T = efield(theta, phi, Eth, Eph)
T = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function E = mp2c(dB, deg)
E = 10 .^ (dB / 20) .* exp(1i * deg2rad(deg));
end

function [Eth, Eph] = circ2lin(Er, El)
Eth = (Er + El) / sqrt(2); Eph = (Er - El) / (1i * sqrt(2));
end

function v = toDouble(v)
if isnumeric(v), if isempty(v), v = NaN; else, v = double(v(1)); end
elseif ischar(v) || isstring(v), v = str2double(strtrim(string(v)));
else, v = NaN; end
end

function writeUAN(U, fp)
% XGTD user-defined antenna file: canonical parameter header, then tab-separated θ φ |Eθ|dB |Eφ|dB ∠Eθ ∠Eφ rows.
hdr = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
    min(U.Phi), max(U.Phi), gridStep(U.Phi), min(U.Theta), max(U.Theta), gridStep(U.Theta), max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan'));
writelines(hdr, fp); writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
end

%% ==================================================================== Numerical services (pure functions)
function T = normalizePattern(T)
%normalizePattern Map any angular convention onto the canonical sphere: θ∈[0,180], φ∈[0,360] with the φ=360 seam duplicated.
th = T.Theta; ph = T.Phi;
if any(th < 0)
    if min(th, [], 'omitnan') >= -90 && max(th, [], 'omitnan') <= 90, th = 90 - th;   % elevation convention
    else, ph(th < 0) = ph(th < 0) + 180; th = abs(th); end                             % negative θ = opposite φ
end
th = mod(th, 360); over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;
T.Theta = th; T.Phi = ph;
num = varfun(@isnumeric, T, 'OutputFormat', 'uniform'); T{:, num} = round(T{:, num}, 5);   % deterministic seam/duplicate handling
T.Phi = mod(T.Phi, 360);
[~, i] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(i, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function [P, info] = calcPattern(S, param)
%calcPattern Canonical primitive fields -> processed pattern table (+ polarization summary).
info = struct('pol', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
ud = S.Properties.UserData;
if isfield(ud, 'isGainOnly') && ud.isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + param.GainLoss_dB; end
    return
end
Eth = complex(S.Re_Eth, S.Im_Eth) * param.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph) * param.FieldScale;
Er = (Eth + 1i * Eph) / sqrt(2); El = (Eth - 1i * Eph) / sqrt(2);
mt = abs(Eth); mp = abs(Eph); mr = abs(Er); ml = abs(El);
total = 10 * log10(max(mt.^2 + mp.^2, eps));
% Dominant polarization drives cut co/cross ordering, the displayed label and the Auto receive sense.
pw = [mean(mt.^2, 'omitnan'), mean(mp.^2, 'omitnan'), mean(mr.^2, 'omitnan'), mean(ml.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif pw(1) >= pw(2), info.pol = 'Linear (Vertical)'; else, info.pol = 'Linear (Horizontal)'; end
% Signed axial ratio (+ right-hand, − left-hand); equal circular components (linear limit) use the −100 dB floor.
delta = mr - ml; sense = sign(delta); sense(~isfinite(delta)) = 0;
ar = (mr + ml) ./ max(abs(delta), eps);
signedAR = min(20 * log10(ar), 250) .* sense; signedAR(isfinite(delta) & abs(delta) <= eps * max(mr + ml, 1)) = -100;
% Polarization loss factor against an incident wave of axial ratio RxAR_dB and sense RxMode (Auto = antenna sense).
if param.RxMode == "Auto", ws = 2 * (info.pairs.Circular(1) == "E_RCP") - 1; elseif param.RxMode == "RHCP", ws = 1; else, ws = -1; end
ra = ar .* sense; ra(sense == 0) = 1e12; rw = ws * 10 .^ (param.RxAR_dB / 20);
plf = 0.5 + (4 * ra * rw - (ra.^2 - 1) * (rw^2 - 1)) ./ (2 * (ra.^2 + 1) * (rw^2 + 1));
plfDB = 10 * log10(min(max(plf, eps), 1));
eirp = param.Pt_dBW + total; eirpW = 10 .^ (eirp / 10);
P = table(S.Theta, S.Phi, total, signedAR, 20 * log10(max(mr, eps)), 20 * log10(max(ml, eps)), plfDB, total + plfDB, ...
    20 * log10(max(mt, eps)), 20 * log10(max(mp, eps)), rad2deg(angle(Eth)), rad2deg(angle(Eph)), rad2deg(angle(Er)), rad2deg(angle(El)), ...
    eirp, eirpW / (4 * pi * param.R_m^2), sqrt(30 * eirpW) / param.R_m, 'VariableNames', ...
    {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', 'PLF_dB', 'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', ...
    'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
P.Properties.UserData = ud;
end

function info = resolvePeak(v, pct, ex)
%resolvePeak Outlier-aware peak: a raw maximum more than EX dB above the PCT percentile is rejected in favour of the
%   largest sample at or below that percentile. Returns value/index (NaN when nothing is finite) and the outlier mask.
v = double(v(:)); fin = isfinite(v);
info = struct('value', NaN, 'index', NaN, 'rawValue', NaN, 'rawIndex', NaN, 'outlierMask', false(size(v)), 'wasAdjusted', false, 'percentile', pct, 'maxExcessDB', ex);
if ~any(fin), return; end
[info.rawValue, info.rawIndex] = max(v, [], 'omitnan'); info.value = info.rawValue; info.index = info.rawIndex;
p = percentile(v(fin), pct);
if info.rawValue <= p + ex, return; end
outliers = fin & v > p; keep = fin & ~outliers;
if ~any(keep), return; end
w = v; w(~keep) = -Inf; [info.value, info.index] = max(w); info.outlierMask = outliers; info.wasAdjusted = true;
end

function q = percentile(v, p)
% prctile-compatible percentile without the Statistics Toolbox: sorted samples at (k-0.5)/n, linear interpolation, clamped ends.
v = sort(v(:)); n = numel(v);
if n == 0, q = NaN; return; elseif n == 1, q = v; return; end
pos = 100 * ((1:n) - 0.5) / n; q = interp1(pos, v, min(max(p, pos(1)), pos(end)));
end

function b = peakWindow(v, pct, ex)
%peakWindow 50 dB display/threshold window whose top is the outlier-aware peak rounded up to the next 5 dB.
v = double(v(isfinite(v))); if isempty(v), b = [-50 0]; return; end
pk = resolvePeak(v, pct, ex); top = ceil(pk.value / 5) * 5;
b = min(max([top - 50, top], -250), 100); if diff(b) < 1, b(1) = max(-250, b(2) - 50); end
end

function w = solidWeights(theta, phi)
%solidWeights Exact solid angle of each uniform θ/φ cell; the duplicated φ=360 seam column gets zero weight.
dt = gridStep(theta); dp = gridStep(phi); if ~isfinite(dt), dt = 180; end, if ~isfinite(dp), dp = 360; end
w = (cosd(max(theta - dt / 2, 0)) - cosd(min(theta + dt / 2, 180))) * deg2rad(dp);
w(abs(phi - 360) < 1e-9) = 0;
end

function step = gridStep(v)
%gridStep Smallest positive spacing between distinct finite values (NaN when there is none).
d = diff(unique(v(isfinite(v)))); d = d(d > 1e-9);
if isempty(d), step = NaN; else, step = min(d); end
end

function g = chooseGain(T, requested)
%chooseGain Requested column if present, else E_Total_dB, else the first data column.
vars = string(T.Properties.VariableNames); c = find(ismember([string(requested), "E_Total_dB"], vars), 1);
if isempty(c), g = T{:, 3}; elseif c == 1, g = T.(char(requested)); else, g = T.E_Total_dB; end
end

function [peak, axisIndex] = calcOrientation(T, omega, c, axes6, pct, ex)
%calcOrientation Peak of component C and the principal axis whose 45° cone captures the most weighted power.
g = chooseGain(T, c); peak = resolvePeak(g, pct, ex); peak.theta = NaN; peak.phi = NaN;
if ~isnan(peak.index), peak.theta = T.Theta(peak.index); peak.phi = mod(T.Phi(peak.index), 360); end
if peak.wasAdjusted, g(peak.outlierMask) = NaN; end
w = 10 .^ ((g - peak.value) / 10) .* omega; w(~isfinite(w)) = 0;
A = [sind(axes6.theta(:)) .* cosd(axes6.phi(:)), sind(axes6.theta(:)) .* sind(axes6.phi(:)), cosd(axes6.theta(:))];
S = [sind(T.Theta) .* cosd(T.Phi), sind(T.Theta) .* sind(T.Phi), cosd(T.Theta)];
[~, axisIndex] = max(w.' * double(S * A.' >= cosd(45)));
end

function m = calcMetrics(T, omega, axes6, ai, pct, ex)
%calcMetrics Scalar metrics of the total-gain column: peak, HPBW (E/H planes of the boresight axis), F/B, directivity, efficiency.
m = struct(); g0 = chooseGain(T, 'E_Total_dB'); pk = resolvePeak(g0, pct, ex); if isnan(pk.index), return; end
g = g0; if pk.wasAdjusted, g(pk.outlierMask) = NaN; end
t0 = T.Theta(pk.index); p0 = T.Phi(pk.index);
U = sum(10 .^ (g / 10) .* omega, 'omitnan');                         % integrated linear gain over the sphere
eff = 100 * U / (4 * pi); if eff < 0 || eff > 100, eff = NaN; end
[~, back] = min(cosd(T.Theta) * cosd(t0) + sind(T.Theta) * sind(t0) .* cosd(T.Phi - p0));
ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(pk.index); end
if axes6.theta(ai) == 90, hType = "Phi"; hVal = 90; else, hType = "Theta"; hVal = 90; end   % H-plane orthogonal to the E-plane
[ea, er] = calcCut(T, "Theta", axes6.phi(ai)); [ha, hr] = calcCut(T, hType, hVal);
m = struct('PeakGain', pk.value, 'PeakTheta', t0, 'PeakPhi', p0, 'HPBW_E', calcHPBW(ea, g(er)), 'HPBW_H', calcHPBW(ha, g(hr)), ...
    'FrontBack', pk.value - g0(back), 'Directivity', 10 * log10(max(4 * pi * 10^(pk.value / 10) / max(U, eps), eps)), 'Efficiency', eff, 'ARatPeak', ar);
end

function [ang, rows, fixed, sym, snapped] = calcCut(T, type, req)
%calcCut One full-circle cut of a canonical table. "Phi": φ sweeps at the nearest fixed θ. "Theta": θ sweeps through both
%   poles at the nearest fixed φ and its antipode (angles 0..360, the far side mapped to 360−θ). Rows are in angle order.
if type == "Phi"
    tv = unique(T.Theta); [dist, i] = min(abs(tv - req)); fixed = tv(i); sym = 'θ';
    rows = find(abs(T.Theta - fixed) < 1e-9); [ang, o] = sort(T.Phi(rows)); rows = rows(o);
else
    pv = unique(mod(T.Phi, 360)); wrapped = mod(T.Phi, 360);
    [dist, i] = min(abs(mod(pv - mod(req, 360) + 180, 360) - 180)); [~, j] = min(abs(mod(pv - pv(i), 360) - 180));
    fixed = pv(i); sym = 'φ';
    near = find(abs(wrapped - fixed) < 1e-9); far = find(abs(wrapped - pv(j)) < 1e-9 & abs(T.Theta - 180) > 1e-9);
    [~, o1] = sort(T.Theta(near)); [~, o2] = sort(T.Theta(far), 'descend'); near = near(o1); far = far(o2);
    rows = [near; far]; ang = [T.Theta(near); 360 - T.Theta(far)];
end
snapped = dist > 0;
end

function [bw, lo, hi] = calcHPBW(ang, g, pk, pkAng)
%calcHPBW Half-power beamwidth of a circular cut by linear interpolation of the −3 dB crossings around the peak.
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(g); ang = ang(ok); g = g(ok);
if numel(g) < 3, return; end
if nargin < 3 || isempty(pk), [pk, i] = max(g); pkAng = ang(i); end
[rel, o] = sort(mod(ang - pkAng + 180, 360) - 180); g = g(o); half = pk - 3;
L = find(rel < 0 & g <= half, 1, 'last'); R = find(rel > 0 & g <= half, 1, 'first');
if isempty(L) || isempty(R) || L + 1 > numel(g) || R - 1 < 1 || g(L + 1) == g(L) || g(R - 1) == g(R), return; end
lc = rel(L) + (rel(L + 1) - rel(L)) * (half - g(L)) / (g(L + 1) - g(L));
rc = rel(R) + (rel(R - 1) - rel(R)) * (half - g(R)) / (g(R - 1) - g(R));
lo = pkAng + lc; hi = pkAng + rc; bw = rc - lc;
end

function cov = coverageCCDF(gain, mask, thr, omega)
%coverageCCDF Coverage(T) [%] = 100 · Σ I(G_i > T)·Ω_i / Σ Ω_i over the region MASK, evaluated for every threshold at once.
ok = mask(:) & isfinite(gain(:)) & isfinite(omega(:)) & omega(:) >= 0; g = gain(ok); w = omega(ok); total = sum(w);
cov = zeros(numel(thr), 1); if total <= 0, return; end
cov = 100 * (w.' * double(g > thr(:).')).' / total;
end

function R = resampleCanonical(T, step)
%resampleCanonical Resample primitive canonical data onto a regular STEP° grid with a closed φ seam.
%   E-field sources: Re/Im columns are interpolated directly. Gain-only: dB columns are interpolated in linear power.
%   Complete rectangular grids use interp2 with a periodic φ column; irregular data use one scattered interpolant per column.
th = T.Theta; ph = mod(T.Phi, 360); keep = find(abs(T.Phi - 360) >= 1e-9);               % the φ=0 sample is authoritative at the seam
[~, u] = unique([th(keep) ph(keep)], 'rows', 'stable'); idx = keep(u); th = th(idx); ph = ph(idx);
[QP, QT] = meshgrid(0:step:360, 0:step:180); if QP(1, end) ~= 360, QP(:, end + 1) = 360; QT(:, end + 1) = QT(:, 1); end
R = table(QT(:), QP(:), 'VariableNames', {'Theta', 'Phi'});
names = T.Properties.VariableNames(3:end); gainMode = ~all(ismember({'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}, names));
ut = unique(th); up = unique(ph); regular = numel(ut) * numel(up) == numel(th);
if regular, [~, it] = ismember(th, ut); [~, ip] = ismember(ph, up); li = sub2ind([numel(ut) numel(up)], it, ip); regular = numel(unique(li)) == numel(li); end
for k = 1:numel(names)
    v = double(T.(names{k})(idx)); toLinear = gainMode && isGainDB(names{k}); if toLinear, v = 10 .^ (v / 10); end
    if regular
        [SP, ST] = meshgrid(up, ut); G = nan(size(SP)); G(li) = v;
        if up(end) < 360 - 1e-9, SP(:, end + 1) = SP(:, 1) + 360; ST(:, end + 1) = ST(:, 1); G(:, end + 1) = G(:, 1); end   % periodic φ
        q = interp2(SP, ST, G, QP, QT, 'linear', NaN); miss = ~isfinite(q);
        if any(miss(:)), nn = interp2(SP, ST, G, QP, QT, 'nearest', NaN); q(miss) = nn(miss); end
    else
        F = scatteredInterpolant(ph, th, v, 'linear', 'nearest'); q = F(QP, QT);
    end
    if toLinear, q = 10 * log10(max(q, realmin)); end
    R.(names{k}) = q(:);
end
R.Properties.UserData = T.Properties.UserData;
end

function tf = isGainDB(name)
key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', '');
tf = contains(key, 'gain') || contains(key, 'directivity') || contains(key, 'eirp') || endsWith(key, 'db');
end

function tf = isAR(c)
%isAR Axial-ratio semantics independent of the column spelling (AR, AR_dB, "AR dB", Axial Ratio, Axial_Ratio).
key = regexprep(lower(strtrim(string(c))), '[^a-z0-9]', ''); tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
end

function V = displayTable(T, signed, elev)
%displayTable Apply the φ/θ display convention to a canonical table (tables, exports and plot grids only).
if signed
    T(abs(T.Phi - 360) < 1e-9, :) = []; T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
    seam = T(abs(T.Phi - 180) < 1e-9, :); seam.Phi(:) = -180; T = [seam; T];
end
if elev, T.Theta = 90 - T.Theta; end
V = sortrows(T, {'Phi', 'Theta'});
end

function [cols, labels] = componentMap(T)
%componentMap Canonical component columns present in T with their user-facing labels (gain-only: every data column).
avail = string(T.Properties.VariableNames(3:end));
if T.Properties.UserData.isGainOnly, cols = avail; labels = avail; return; end
map = APAT_v3_M8_11.ComponentLabels; present = ismember(map(:, 1), avail); cols = map(present, 1).'; labels = map(present, 2).';
end

function c = pickComponent(prev, cols)
if ismember(string(prev), cols), c = char(prev); elseif ismember("E_Total_dB", cols), c = 'E_Total_dB'; else, c = char(cols(1)); end
end

function t = axisTicks(lim, step)
%axisTicks Tick vector for LIM at STEP including both limits (empty when degenerate or more than 60 ticks).
t = [];
if numel(lim) ~= 2 || any(~isfinite(lim)) || ~isfinite(step) || step <= 0 || lim(1) >= lim(2), return; end
t = unique([lim(1), ceil(lim(1) / step) * step:step:floor(lim(2) / step) * step, lim(2)], 'stable'); if numel(t) > 60, t = []; end
end

function s = fmt(v, precision)
%fmt Compact number formatting: up to 2 decimals with trailing zeros removed, or exactly PRECISION decimals; 'n/a' if not finite.
if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); else, s = sprintf('%.*f', max(0, min(5, round(precision))), v); end
end