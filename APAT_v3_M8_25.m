classdef APAT_v3_M8_25 < matlab.apps.AppBase %1717-lines
% APAT v3 M8 — Antenna Pattern Analyzer Tool (single file, programmatic UI, no toolboxes required)
%
% LAYERS (top → bottom, no upward dependencies)
%   UI shell ........ createUI + callbacks (every callback is wrapped by cb() → one error/cancel policy)
%   View pipeline ... load → normalize → process → step → span → view → tables/cuts/plots/coverage
%   Numeric core .... pure local functions at the end of this file (never touch the UI or a table's convention)
%   I/O ............. readPattern / readExcelMatrix (return the same canonical source contract for every format)
%
% DATA FLOW (one table per stage; each stage is derived only from the previous one)
%   file ─readPattern─▶ blocks{k} ─normalizePattern─▶ stdTbl   physical sphere θ∈[0,180], φ∈[0,360] (closed seam)
%        ─calcPattern─▶ patTbl (native step) ─applyStep─▶ baseTbl (native or 1°) ─applyAngularSpan─▶ viewTbl
%        viewTbl is the single source for the Results table, exports, cuts, full-pattern plots and Coverage.
%
% CONVENTIONS 
%   viewTbl.Theta/Phi follow the DISPLAY convention chosen with the θ/φ span switches. physAngles() converts
%   them back to physical (θ polar, φ mod 360). Numeric services always receive explicit physical angle
%   vectors and solid-angle weights — they never read a table's display mode.
%   Tags: APAT_Surface (pattern surfaces), APAT_POB (peak marker+tip), APAT_HPBW, APAT_CutOverlay, CovQ_<mode>_<id>.

    properties (SetAccess = private)
        ui struct = struct()          % all widgets (see createUI); u.range.<group> = struct(slider,min,max)
        isClosing logical = false
    end

    properties (Access = private)
        % source
        filePath char = ''
        fileName char = ''
        baseName char = ''
        folderPath char = ''
        rawTbl table                  % source table as read (Input tab)
        ffdBlocks cell = {}           % one canonical block per FFD frequency
        freqs double = NaN
        src struct = struct('isGainOnly', false, 'isDep', false, 'source', '')   % source metadata (readPattern.userData)
        rawShown logical = false
        % pipeline tables (see DATA FLOW)
        stdTbl table
        patTbl table
        baseTbl table
        viewTbl table
        viewRev uint64 = 0            % bumps whenever viewTbl changes (invalidates grid cache, coverage presets)
        % derived state of the current view
        info struct = struct('pol', 'n/a', 'pairs', struct('Linear', ["E_TH","E_PH"], 'Circular', ["E_RCP","E_LCP"]))
        peak struct = struct('value', NaN, 'index', 1, 'theta', NaN, 'phi', NaN, 'wasAdjusted', false)
        dOmega double = []            % solid-angle weight of every viewTbl row
        boresight double = 1          % index into Axes6
        metrics struct = struct()
        cache struct = struct()       % grid topology / geometry / reshaped components (see topology)
        % dB display ranges
        fullLim double = [-40 10]     % current full-pattern colour scale
        cutLim double = [-40 10]      % current cut range
        gainLim double = [-40 10]     % non-AR scale owner, preserved across component changes
        % coverage
        covRunID double = 0
        covPreset char = ''           % key of the last automatic threshold preset (path|component|viewRev)
        covXInit logical = false      % first result establishes the X-axis baseline
        % misc
        defaults cell = {}            % parameter values at startup (Reset Params)
        statusTimer = []              % single transient-status timer
        opDialog = []                 % active cancelable progress dialog
        perf = @(~) []                % stage recorder (no-op when idle)
    end

    properties (Constant, Access = private)
        Axes6 = struct('labels', {{'+Z','-Z','+X','-X','+Y','-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        Comps = ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","AR_dB","Gain_PolCorrected_dB"]
        CompLabels = ["Total Gain","Etheta Gain","Ephi Gain","RHCP Gain","LHCP Gain","Axial Ratio","Polarized Gain"]
        HiddenCols = {'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'}
        TextFormats = {'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
            '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
            '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
            'ItemsData', {'gain','linear_magphase','linear_reim','rcp_lcp_magphase','lcp_rcp_magphase','rcp_lcp_reim','lcp_rcp_reim'}, ...
            'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.'}
        PeakPct = 99.99                       % peak policy: raw max accepted unless > P99.99 + PeakExcess
        PeakExcess = 6
        DBLim = [-250 100]                    % absolute dB bounds of every range control
        Release = 'APAT v3 M8'
    end

    %% ===================================================================== lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_25
            app.createUI(); registerApp(app, app.ui.fig); app.startup();
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true;
            t = app.statusTimer; if ~isempty(t) && isvalid(t), stop(t); delete(t); end
            d = app.opDialog;    if ~isempty(d) && isvalid(d), delete(d); end
            if isfield(app.ui, 'fig') && isgraphics(app.ui.fig), delete(app.ui.fig); end
        end

        function f = cb(app, method)
            % Wrap a (src,evt) callback: one place handles errors, user cancellation and the closing state.
            f = @(src, evt) app.guard(method, src, evt);
        end

        function guard(app, method, src, evt)
            if app.isClosing, return; end
            try
                method(src, evt);
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.setStatus(app.ui.status, 'Operation cancelled by user.', true);
                else, app.showError(ME); end
            end
        end

        function startup(app)
            u = app.ui;
            app.defaults = {u.loss.Value, u.rxPol.Value, u.rw.Value, u.pt.Value, u.ptUnit.Value, u.dist.Value, u.distUnit.Value};
            app.setRange("full", [-40 10], false); app.setRange("cut", [-40 10], false);
            app.covReset(); app.setStatus(u.covStatus, 'Ready — load a pattern or a coverage-results file 🚀', false);
            app.setStatus(u.status, 'Ready — load an antenna pattern file to begin 🚀', false);
            u.fig.Visible = 'on';
        end
    end

    %% ===================================================================== loading & processing
    methods (Access = private)
        function onLoad(app, ~, ~)
            fp = strtrim(app.ui.path.Value);
            if isempty(fp) || ~isfile(fp)
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / gain / coverage files'; ...
                    '*.*', 'All files'}, 'Select an antenna pattern file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            done = app.beginOperation('Loading Data', 'Reading file...', true); %#ok<NASGU>
            src = app.readSource(fp, "main"); app.perf("Read file"); app.checkCancelled();
            if src.userData.isCoverage                     % coverage results never replace the Main state
                app.ui.tabs.SelectedTab = app.ui.tabCov; app.ui.covPath.Value = fp;
                app.covLoadResults(fp, src.rawTbl); return
            end
            app.ui.path.Value = fp; app.filePath = fp;
            [app.folderPath, app.baseName, ext] = fileparts(fp); app.fileName = [app.baseName ext];
            app.activate(src);
            u = app.ui;
            if src.userData.isDep                          % multi-block / frequency-dependent FFD
                items = compose('Pattern %d: %.4g GHz', (1:numel(src.blocks))', src.freqs(:)/1e9);
                items(isnan(src.freqs(:))) = compose('Pattern %d', find(isnan(src.freqs(:))));
                u.ffd.Items = items; u.ffd.Value = items{1};
            end
            set([u.ffd u.ffdLabel], 'Visible', src.userData.isDep);
            u.basis.UserData = true; u.step.UserData = false;   % auto cut basis; native step
            app.refresh();
        end

        function src = readSource(app, fp, which)
            % Parse FP; generic text files (csv/txt/dat) expose the format selector of the calling tab.
            if which == "main", dd = app.ui.txtFmt; lbl = app.ui.txtFmtLabel; else, dd = app.ui.covFmt; lbl = app.ui.covFmtLabel; end
            generic = app.isGenericText(fp);
            if generic, dd.Value = 'gain'; end               % a fresh generic file is first read as a gain table
            src = readPattern(fp, dd.Value, table());
            set([lbl dd], 'Visible', generic && ~src.userData.isCoverage);
        end

        function activate(app, src)
            [app.rawTbl, app.ffdBlocks, app.freqs, app.src] = deal(src.rawTbl, src.blocks, src.freqs, src.userData);
            app.rawShown = false; app.selectBlock(1);
        end

        function selectBlock(app, k)
            blk = app.ffdBlocks{k};
            if app.src.isDep, app.rawTbl = blk; app.rawShown = false; end
            app.stdTbl = normalizePattern(blk); app.stdTbl.Properties.UserData = app.src;
        end

        function onProcess(app, ~, ~)
            if isempty(app.stdTbl), uialert(app.ui.fig, 'Load a pattern first.', 'Process', 'Icon', 'warning'); return; end
            done = app.beginOperation('Processing', 'Re-processing pattern...', false); %#ok<NASGU>
            app.ui.step.UserData = startsWith(app.ui.step.Value, 'STEP: 1°');
            if app.isGenericText(app.filePath)              % re-interpret the cached raw table with the selected format
                src = readPattern(app.filePath, app.ui.txtFmt.Value, app.rawTbl);
                assert(~src.userData.isCoverage, 'APAT:format', 'The selected generic format identifies a coverage-results file.');
                app.activate(src);
            end
            app.refresh(); app.setStatus(app.ui.status, ['Re-processed <b>' app.fileName '</b> ✅'], true);
        end

        function onFormatChanged(app, ~, ~)
            if strcmp(strtrim(app.ui.path.Value), app.filePath) && app.isGenericText(app.filePath)
                app.ui.basis.UserData = true; app.onProcess();
            end
        end

        function onFFDChanged(app, ~, ~)
            k = find(strcmp(app.ui.ffd.Items, app.ui.ffd.Value), 1);
            done = app.beginOperation('Processing', 'Switching FFD block...', false); %#ok<NASGU>
            app.ui.basis.UserData = true; app.selectBlock(k); app.refresh();
            app.setStatus(app.ui.status, sprintf('Switched to FFD block %d (%s).', k, app.ui.ffd.Value), true);
        end

        function resetParams(app, ~, ~)
            u = app.ui;
            [u.loss.Value, u.rxPol.Value, u.rw.Value, u.pt.Value, u.ptUnit.Value, u.dist.Value, u.distUnit.Value] = deal(app.defaults{:});
            if ~isempty(app.stdTbl), app.refresh(); end
        end

        function p = getParam(app)
            u = app.ui; p = struct('GainLoss_dB', u.loss.Value, 'RxMode', string(u.rxPol.Value), 'RxAR_dB', u.rw.Value);
            p.FieldScale = 10^(p.GainLoss_dB/20);
            switch u.ptUnit.Value
                case 'dBm',   p.Pt_dBW = u.pt.Value - 30;
                case 'Watts', p.Pt_dBW = 10*log10(max(u.pt.Value, eps));
                otherwise,    p.Pt_dBW = u.pt.Value;
            end
            p.R_m = max(u.dist.Value, 1e-12)*(1 + 999*strcmp(u.distUnit.Value, 'km'));
        end

        %% ------------------------------------------------------------------ view pipeline
        function refresh(app)
            % Full pipeline from stdTbl: process → step → span → derived state → cut → full-pattern plots.
            u = app.ui; efield = ~app.src.isGainOnly;
            [app.patTbl, app.info] = calcPattern(app.stdTbl, app.getParam(), app.PeakPct, app.PeakExcess);
            app.perf("Process pattern"); app.checkCancelled();
            if efield && isequal(u.basis.UserData, true)   % cut basis follows the detected polarization until edited
                if startsWith(app.info.pol, 'Linear'), u.basis.Value = 'Linear'; else, u.basis.Value = 'Circular'; end
            end
            [ts, ps] = deal(gridStep(app.stdTbl.Theta), gridStep(app.stdTbl.Phi));
            if ~isfinite(ts), ts = 1; end, if ~isfinite(ps), ps = ts; end
            nonCanonical = abs(ts - 1) > 1e-9 || abs(ps - 1) > 1e-9;
            native = sprintf('STEP: %g°', max(ts, ps)); one = 'STEP: 1°';
            if nonCanonical, u.step.Items = {native, one}; else, u.step.Items = {native}; end
            if nonCanonical && isequal(u.step.UserData, true), u.step.Value = one; else, u.step.Value = native; end
            u.step.UserData = false; set(u.step, 'Visible', nonCanonical, 'Enable', nonCanonical);
            app.applyStep(); app.updateComponentItems();
            app.perf("Prepare view"); app.checkCancelled();
            app.updateView("reset", false);
            app.onEHPlane();                                % E-plane cut first: fast initial feedback
            drawnow limitrate
            app.renderAll(); app.perf("Build plots");
            set([u.panelCut u.exportBtn u.panelFull u.panelCtrl u.covBtn], 'Visible', 'on');
            set([u.exportUAN u.gridEcut u.chkEt u.chkEr u.chkEl], 'Visible', efield);
            set([u.chkEr u.chkEl u.basis], 'Enable', efield);
            app.updateInputVisibility();
            pol = ''; if efield, pol = sprintf(' | Polarization <b>%s</b>', app.info.pol); end
            app.setStatus(u.status, sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)%s', ...
                app.fileName, app.fmt(app.peak.value, 2), app.fmt(app.peak.theta), app.fmt(app.peak.phi), pol), false);
        end

        function applyStep(app)
            % Resample the canonical SOURCE (fields / gain) — never derived quantities — then reprocess.
            S = app.stdTbl; one = startsWith(app.ui.step.Value, 'STEP: 1°');
            [ts, ps] = deal(gridStep(S.Theta), gridStep(S.Phi));
            if ~one || (abs(ts - 1) < 1e-9 && abs(ps - 1) < 1e-9)
                app.baseTbl = app.patTbl;
            else
                if ts < 1 && ps < 1                         % sub-degree regular source: exact decimation
                    S = S(abs(S.Theta - round(S.Theta)) < 1e-9 & abs(S.Phi - round(S.Phi)) < 1e-9, :);
                else
                    S = resampleCanonical(S, 1);
                end
                S.Properties.UserData = app.src;
                app.baseTbl = calcPattern(S, app.getParam(), app.PeakPct, app.PeakExcess);
            end
            app.applyAngularSpan();
        end

        function applyAngularSpan(app)
            % Materialize the display convention (φ span / θ span) from the canonical baseTbl.
            T = app.baseTbl;
            if app.isSigned()
                T(abs(T.Phi - 360) < 1e-9, :) = [];
                T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
                seam = T(abs(T.Phi - 180) < 1e-9, :); seam.Phi(:) = -180; T = [seam; T];
            end
            if app.isElevation(), T.Theta = 90 - T.Theta; end
            app.viewTbl = sortrows(T, {'Phi', 'Theta'}); app.viewRev = app.viewRev + 1; app.cache = struct();
            [th, ~] = app.physAngles(); app.dOmega = solidWeights(th, app.viewTbl.Phi);
        end

        function [th, ph] = physAngles(app)
            % Physical (polar θ, φ mod 360) angles of viewTbl, whatever the display convention.
            th = app.viewTbl.Theta; if app.isElevation(), th = 90 - th; end
            ph = mod(app.viewTbl.Phi, 360);
        end

        function updateView(app, rangeMode, render)
            % Everything derived from (viewTbl, component): orientation, POB, metrics, ranges, tables, plots.
            %   rangeMode: "reset" (new data → new 50-dB window), "apply" (component change), "keep" (span change).
            T = app.viewTbl; [th, ph] = app.physAngles(); c = app.comp(); efield = ~app.src.isGainOnly;
            [app.peak, app.boresight] = calcOrientation(th, ph, chooseGain(T, c), app.dOmega, app.Axes6, app.PeakPct, app.PeakExcess);
            app.peak.theta = th(app.peak.index); app.peak.phi = ph(app.peak.index);
            mcol = c; ar = nan(height(T), 1);
            if efield, mcol = 'E_Total_dB'; ar = T.AR_dB; end          % scalar metrics are total-power quantities
            mpk = app.peak; if ~strcmp(mcol, c), mpk = resolvePeak(T.(mcol), app.PeakPct, app.PeakExcess); end
            app.metrics = calcMetrics(th, ph, T.(mcol), app.dOmega, mpk, app.Axes6, app.boresight, ar);
            if rangeMode == "reset", app.gainLim = app.peakWindow(chooseGain(T, 'E_Total_dB')); end
            if rangeMode ~= "keep"
                lim = app.gainLim; if app.isAR(c), lim = [-30 30]; end
                app.setRange("full", lim, false); app.setRange("cut", lim, false);
            end
            app.updateTables(); app.updateMetadata();
            if render, app.updateCutControl(); app.plotCut(); app.renderAll(); end
        end

        function stepChanged(app, ~, ~)
            done = app.beginOperation('Processing', 'Changing angular step...', false); %#ok<NASGU>
            app.applyStep(); app.updateComponentItems(); app.updateView("reset", true);
        end

        function spanChanged(app, ~, ~)
            if isempty(app.baseTbl), return; end
            app.applyAngularSpan(); app.updateView("keep", true);
        end

        function onComponentChanged(app, ~, ~)
            app.updateView("apply", true);
        end

        function c = topology(app)
            % θ×φ grid topology + unit-sphere geometry of viewTbl (cached per view revision).
            c = app.cache; T = app.viewTbl;
            if isfield(c, 'rev') && c.rev == app.viewRev, return; end
            theta = unique(T.Theta); phi = unique(T.Phi); sz = [numel(theta) numel(phi)];
            [~, it] = ismember(T.Theta, theta); [~, ip] = ismember(T.Phi, phi);
            [phiG, thG] = meshgrid(phi, theta); thP = thG; if app.isElevation(), thP = 90 - thG; end
            phR = deg2rad(phiG); s = sind(thP);
            c = struct('rev', app.viewRev, 'theta', theta, 'phi', phi, 'sz', sz, 'idx', sub2ind(sz, it, ip), 'comps', struct(), ...
                'geom', struct('phi', phiG, 'theta', thG, 'thetaPolar', thP, 'phiRad', phR, 'x', s.*cos(phR), 'y', s.*sin(phR), 'z', cosd(thP)));
            app.cache = c;
        end

        function [G, g] = gridComp(app, col)
            % One view column reshaped onto the θ×φ grid, plus the grid geometry.
            c = app.topology(); key = matlab.lang.makeValidName(col);
            if ~isfield(c.comps, key), G = nan(c.sz); G(c.idx) = app.viewTbl.(col); c.comps.(key) = G; app.cache = c; end
            G = c.comps.(key); g = c.geom;
        end

        %% ------------------------------------------------------------------ components, tables, metadata
        function [cols, labels] = componentMap(app, T)
            avail = string(T.Properties.VariableNames(3:end));
            if T.Properties.UserData.isGainOnly, [cols, labels] = deal(avail); return; end
            keep = ismember(app.Comps, avail); cols = app.Comps(keep); labels = app.CompLabels(keep);
        end

        function updateComponentItems(app)
            [cols, labels] = app.componentMap(app.viewTbl); app.setItems(app.ui.comp, labels, cols, app.ui.comp.Value);
        end

        function setItems(~, dd, labels, data, preferred)
            % Replace dropdown items, keeping PREFERRED when still present (else Total Gain, else the first item).
            dd.ItemsData = {}; dd.Items = cellstr(labels); dd.ItemsData = cellstr(data);
            if isempty(data), return; end
            k = find(data == string(preferred), 1); if isempty(k), k = find(data == "E_Total_dB", 1); end
            if isempty(k), k = 1; end
            dd.Value = char(data(k));
        end

        function updateTables(app)
            T = app.viewTbl; u = app.ui; dd = u.outFilter; cols = T.Properties.VariableNames(3:end);
            if ~app.rawShown
                set(u.tableIn, 'Data', app.rawTbl, 'ColumnName', app.rawTbl.Properties.VariableNames, 'Visible', 'on'); app.rawShown = true;
            end
            schemaChanged = ~isequal(regexprep(dd.Items(2:end), '^✓ ?', ''), cols);
            if schemaChanged
                dd.ItemsData = {}; dd.Items = [{'--- column filter ---'}, cols]; dd.ItemsData = 0:numel(cols);
                dd.UserData = ~ismember(cols, app.HiddenCols); dd.Value = 0;
                set([dd u.tableOut u.tabData], 'Visible', 'on');
            end
            app.filterOutput(schemaChanged);
        end

        function filterOutput(app, restyle)
            % The output dropdown doubles as a multi-select column filter: choosing an item toggles it.
            dd = app.ui.outFilter; if nargin < 2, restyle = true; end
            if dd.Value > 0, dd.UserData(dd.Value) = ~dd.UserData(dd.Value); dd.Value = 0; end
            if restyle
                dd.Items = regexprep(dd.Items, '^✓ ?', ''); removeStyle(dd);
                on = find(dd.UserData) + 1; off = find([true, ~dd.UserData]);
                if ~isempty(on), dd.Items(on) = append('✓ ', dd.Items(on)); addStyle(dd, uistyle('FontWeight', 'bold', 'BackgroundColor', [0.8 1 0.8]), 'Item', on); end
                addStyle(dd, uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9]), 'Item', off);
            end
            app.ui.tableOut.Data = app.viewTbl(:, [true true dd.UserData]);
            app.updateInputVisibility();
        end

        function updateInputVisibility(app)
            % Show only the parameters that influence a currently displayed output column.
            u = app.ui; cols = string(app.viewTbl.Properties.VariableNames(3:end)); sel = cols(u.outFilter.UserData);
            has = @(names) any(ismember(sel, names));
            set([u.rxLabel u.rxPol u.rwLabel u.rw], 'Visible', has(["PLF_dB","Gain_PolCorrected_dB"]));
            set([u.ptLabel u.pt u.ptUnit], 'Visible', has(["EIRP_dBW","PFD_Wm2","E_RMS_Vm"]));
            set([u.rLabel u.dist u.distUnit], 'Visible', has(["PFD_Wm2","E_RMS_Vm"]));
            set([u.lossLabel u.loss], 'Visible', app.src.isGainOnly || has(["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","Gain_PolCorrected_dB","EIRP_dBW","PFD_Wm2","E_RMS_Vm"]));
        end

        function updateMetadata(app)
            T = app.viewTbl; f = @app.fmt; m = app.metrics; [th, ph] = deal(unique(T.Theta), unique(T.Phi));
            rows = {'Source format', app.src.source; 'File', app.fileName; ...
                'Samples', sprintf('%d  (θ: %d × φ: %d)', height(T), numel(th), numel(ph)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', f(min(th)), f(max(th)), f(gridStep(th))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', f(min(ph)), f(max(ph)), f(gridStep(ph)))};
            fq = app.freqs(isfinite(app.freqs));
            if ~isempty(fq), rows(end+1, :) = {'Frequencies', strjoin(compose('%.4g GHz', fq(:)'/1e9), ', ')}; end
            if isfield(app.src, 'summary') && isfield(app.src.summary, 'frequencyMHz')
                rows(end+1, :) = {'Workbook frequency', sprintf('%s MHz', f(app.src.summary.frequencyMHz))};
            end
            if ~app.src.isGainOnly
                rows(end+1, :) = {'Polarization', app.info.pol};
                rows(end+1, :) = {'Cut co-pol / cross-pol', char(strjoin(app.info.pairs.(app.ui.basis.Value), ' / '))};
            end
            rows = [rows; {sprintf('POB (%s)', app.compLabel()), sprintf('%s dB', f(app.peak.value)); ...
                'POB direction [θ, φ]', sprintf('[%s°, %s°]', f(app.peak.theta), f(app.peak.phi)); ...
                'Boresight axis', app.Axes6.labels{app.boresight}; ...
                'Peak policy', sprintf('P%.4g + %g dB, adjusted: %s', app.PeakPct, app.PeakExcess, string(app.peak.wasAdjusted))}];
            if isfield(m, 'PeakDirectivity_dB')
                rows = [rows; {'HPBW E-plane', [f(m.HPBW_EPlane_deg) '°']; 'HPBW H-plane', [f(m.HPBW_HPlane_deg) '°']; ...
                    'Front-to-back', [f(m.FrontBack_dB) ' dB']; 'Peak directivity', [f(m.PeakDirectivity_dB) ' dB']; ...
                    'Radiation efficiency', [f(m.Efficiency_pct) ' %']; 'AR at peak', [f(m.AxialRatioAtPeak_dB) ' dB']}];
            end
            app.ui.tableMeta.Data = rows;
        end

        %% ------------------------------------------------------------------ dB ranges & colour theme
        function setRange(app, group, lim, apply)
            % Single authority for every dB range group: "full" (5 linked full-pattern views), "cut", "covX".
            % Slider travel keeps ±25 dB of headroom around the selected range; spinners are mutually bounded.
            lim = app.clampRange(lim); r = app.ui.range.(group); travel = app.clampRange([lim(1) - 25, lim(2) + 25]);
            app.setWithin(r.slider, lim, travel);
            app.setWithin(r.min, lim(1), [app.DBLim(1), lim(2) - 1]); app.setWithin(r.max, lim(2), [lim(1) + 1, app.DBLim(2)]);
            switch group
                case "full"
                    app.fullLim = lim; if ~app.isAR(app.comp()), app.gainLim = lim; end
                    app.ui.cmin.Value = lim(1); app.ui.cmax.Value = lim(2);
                    if apply, app.applyFullRange(lim); end
                case "cut"
                    app.cutLim = lim;
                    if apply, set(app.ui.paxCut, 'RLim', lim); set(app.ui.axRect, 'YLim', lim); end
                otherwise
                    set(app.ui.axCov, 'XLimMode', 'manual', 'XLim', lim);
            end
        end

        function rangeEdited(app, group, which, value)
            % A slider (which = 0) or the min/max spinner (1/2) of GROUP was edited.
            switch group, case "full", lim = app.fullLim; case "cut", lim = app.cutLim; otherwise, lim = app.ui.axCov.XLim; end
            if which == 0, lim = value; else, lim(which) = value; end
            app.setRange(group, lim, true);
        end

        function setWithin(~, h, value, limits)
            % Set VALUE and LIMITS on spinners/sliders in a safe order (Value always inside Limits).
            set(h, 'Limits', [-1e9 1e9]); set(h, 'Value', value); set(h, 'Limits', limits);
        end

        function lim = clampRange(app, lim)
            lim = sort(double(lim(:)')); if numel(lim) < 2 || any(~isfinite(lim)), lim = app.DBLim; end
            lim = [max(app.DBLim(1), lim(1)), min(app.DBLim(2), lim(2))];
            if diff(lim) < 1, lim(2) = min(app.DBLim(2), lim(1) + 1); lim(1) = lim(2) - 1; end
        end

        function w = peakWindow(app, values)
            % 50-dB window whose top is the outlier-robust peak rounded up to 5 dB (main colour scale & coverage preset).
            v = double(values(isfinite(values))); if isempty(v), w = [-40 10]; return; end
            pk = resolvePeak(v, app.PeakPct, app.PeakExcess); top = 5*ceil(pk.value/5); w = app.clampRange([top - 50, top]);
        end

        function applyFullRange(app, lim)
            for s = app.fullSpecs()
                clim(s.axes, lim); if s.name == "rect3D", zlim(s.axes, lim); app.applyTicks(s.axes, lim); end
                cbh = findall(app.ui.fig, 'Type', 'ColorBar', 'Axes', s.axes); if ~isempty(cbh), app.applyTicks(cbh(1), lim); end
            end
            drawnow limitrate
        end

        function [lim, map] = plotTheme(app)
            % Axial ratio: fixed signed ±30 dB blue-white-red scale. Everything else: current gain range with jet.
            if app.isAR(app.comp()), lim = [-30 30]; map = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256));
            else, lim = app.fullLim; map = jet(256); end
        end

        function applyTheme(app, ax)
            [lim, map] = app.plotTheme(); clim(ax, lim); colormap(ax, map); app.applyTicks(colorbar(ax), lim);
        end

        function applyTicks(app, target, lim)
            % Ticks from the colorbar-step spinner, always including both limits (colorbars and the 3-D surface Z axis).
            step = app.ui.cstep.Value;
            if ~isfinite(step) || step <= 0 || diff(lim) <= 0 || diff(lim)/step > 60, return; end
            ticks = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)]);
            if isa(target, 'matlab.graphics.illustration.ColorBar'), target.Ticks = ticks; else, target.ZTick = ticks; end
        end

        function tf = isAR(~, name)
            key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', '');
            tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
        end

        %% ------------------------------------------------------------------ full-pattern rendering
        function specs = fullSpecs(app)
            u = app.ui;
            specs = struct('name', {"contour", "fisheye", "sphere", "polar3D", "rect3D"}, ...
                'axes', {u.axCtr, u.paxFish, u.axSph, u.axPol, u.axRect3}, ...
                'render', {@app.drawContour, @app.drawFisheye, @() app.draw3D(u.axSph, "sphere"), @() app.draw3D(u.axPol, "polar"), @app.drawRect3});
        end

        function renderAll(app)
            % Render the five full-pattern views eagerly (tab switches never re-render), then annotate the POB.
            if isempty(app.viewTbl), return; end
            for s = app.fullSpecs()
                if app.isClosing, return; end
                app.checkCancelled(); s.render();
            end
            drawnow limitrate                               % surfaces must exist before DataTips attach
            app.annotatePOB();
        end

        function drawContour(app)
            ax = app.ui.axCtr; [G, g] = app.gridComp(app.comp()); cla(ax);
            h = pcolor(ax, g.phi(1, :), g.theta(:, 1), G, 'FaceColor', 'interp', 'LineStyle', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax); app.formatAngularAxes(ax, 30, 15); daspect(ax, [1 1 1]);
            title(ax, app.compLabel(), 'Interpreter', 'none'); app.tipTemplate(h, g, G);
        end

        function drawFisheye(app)
            ax = app.ui.paxFish; [G, g] = app.gridComp(app.comp()); cla(ax);
            h = surface(ax, g.phiRad, g.thetaPolar, zeros(size(G)), G, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax); app.setPolarTicks(ax);
            rl = 0:30:180; if app.isElevation(), rl = 90 - rl; end
            set(ax, 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', rl));
            title(ax, sprintf('%s  |  r=θ, angle=φ', app.compLabel()), 'Interpreter', 'none', 'FontSize', 9); app.tipTemplate(h, g, G);
        end

        function draw3D(app, ax, kind)
            % "sphere": colour mapped on the unit sphere. "polar": radius = normalized (value − min)/(max − min).
            [G, g] = app.gridComp(app.comp()); [lim, ~] = app.plotTheme(); r = 1;
            if kind == "polar", r = max(G - lim(1), 0)/max(diff(lim), eps); r = r/max(max(r, [], 'all'), eps); end
            cla(ax); hold(ax, 'on');
            h = surf(ax, r.*g.x, r.*g.y, r.*g.z, G, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax);
            set(ax, 'XDir', 'normal', 'YDir', 'normal', 'ZDir', 'normal', 'Projection', 'orthographic', 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], ...
                'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1]); axis(ax, 'off');
            app.drawXYZ(ax); app.applyView3D(ax, [135 25]); app.drawOverlay(ax, kind);
            title(ax, sprintf('%s  |  θ: %s  |  φ: %s', app.compLabel(), app.ui.thetaSpan.Value, app.ui.phiSpan.Value), 'Interpreter', 'none');
            app.tipTemplate(h, g, G); hold(ax, 'off');
        end

        function drawRect3(app)
            ax = app.ui.axRect3; [G, g] = app.gridComp(app.comp()); cla(ax);
            h = surf(ax, g.phi, g.theta, G, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax); [lim, ~] = app.plotTheme(); zlim(ax, lim); app.applyTicks(ax, lim);
            app.formatAngularAxes(ax, 60, 30); grid(ax, 'on'); app.applyView3D(ax, [-35 35]);
            xlabel(ax, 'Phi (degree)'); ylabel(ax, app.thetaLabel() + " (degree)"); zlabel(ax, app.compLabel() + " (dB)", 'Interpreter', 'none');
            title(ax, app.compLabel(), 'Interpreter', 'none'); app.tipTemplate(h, g, G);
        end

        function drawXYZ(~, ax)
            % Principal axes (X red, Y green, Z blue) with their spherical coordinates.
            colors = [0.85 0.1 0.1; 0.1 0.6 0.1; 0.1 0.2 0.9]; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            for k = 1:3
                d = 1.35*((1:3) == k);
                quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors(k, :), 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12*d(1), 1.12*d(2), 1.12*d(3), labels{k}, 'Color', colors(k, :), 'FontWeight', 'bold');
            end
        end

        function applyView3D(app, ax, default)
            views = struct('iso', [default 0 0 1], 'top', [0 90 0 1 0], 'bottom', [0 -90 0 1 0], 'right', [90 0 0 0 1], ...
                'left', [-90 0 0 0 1], 'front', [0 0 0 0 1], 'back', [180 0 0 0 1]);
            v = views.(app.ui.view3D.Value); view(ax, v(1), v(2)); camup(ax, v(3:5));
        end

        function on3DView(app)
            if isempty(app.viewTbl), return; end
            app.applyView3D(app.ui.axSph, [135 25]); app.applyView3D(app.ui.axPol, [135 25]); app.applyView3D(app.ui.axRect3, [-35 35]);
        end

        function tipTemplate(app, h, g, G)
            % Common θ/φ/value DataTip rows for every pattern surface; children share the "Delete DataTips" menu.
            rows = [dataTipTextRow(app.thetaLabel(), g.theta, '%.3g°'); dataTipTextRow("Phi", g.phi, '%.3g°'); ...
                dataTipTextRow(replace(app.compLabel(), "_", "\_"), G, '%.3g dB')];
            try, h.DataTipTemplate.DataTipRows = rows; catch, end
            set(findall(ancestor(h, {'axes', 'polaraxes'}), '-property', 'ContextMenu'), 'ContextMenu', app.ui.plotMenu);
        end

        function formatAngularAxes(app, ax, phiStep, thetaStep)
            xl = [0 360] - 180*app.isSigned(); yl = [0 180]; dir = 'reverse'; if app.isElevation(), yl = [-90 90]; dir = 'normal'; end
            set(ax, 'XLim', xl, 'YLim', yl, 'YDir', dir, 'Box', 'on', 'Layer', 'top', 'XTick', xl(1):phiStep:xl(2), 'YTick', yl(1):thetaStep:yl(2));
        end

        function setPolarTicks(app, pax)
            % Polar geometry stays physical (0..360 clockwise from top); only the labels follow the φ span.
            a = 0:30:330; if app.isSigned(), a(a > 180) = a(a > 180) - 360; end
            set(pax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', a));
        end

        %% ------------------------------------------------------------------ POB / HPBW annotations
        function annotatePOB(app)
            % One marker + DataTip per full-pattern view at the POB grid cell; visibility follows the checkbox.
            if ~isfinite(app.peak.value), return; end
            c = app.topology(); th = app.peak.theta; ph = app.peak.phi;
            if app.isElevation(), th = 90 - th; end
            if app.isSigned() && ph > 180, ph = ph - 360; end
            [~, row] = min(abs(c.theta - th)); [~, col] = min(abs(c.phi - ph));
            rows = [dataTipTextRow(app.thetaLabel(), th, '%.3g°'); dataTipTextRow("Phi", ph, '%.3g°'); dataTipTextRow(app.compLabel(), app.peak.value, '%.3g dB')];
            for s = app.fullSpecs()
                h = findobj(s.axes, 'Tag', 'APAT_Surface'); if ~isempty(h), app.markPOB(h(1), row, col, rows); end
            end
        end

        function markPOB(app, h, i, j, rows)
            % POB marker + DataTip on graphics object H at sample (i,j): surfaces use grid row/col, lines use index i.
            ax = h.Parent; polar = isa(ax, 'matlab.graphics.axis.PolarAxes'); delete(findall(ax, 'Tag', 'APAT_POB'));
            if isprop(h, 'ThetaData'), X = h.ThetaData; Y = h.RData; else, X = h.XData; Y = h.YData; end
            if isa(h, 'matlab.graphics.chart.primitive.Line'), x = X(i); y = Y(i); z = 0;
            else, x = gridValue(X, i, j, "col"); y = gridValue(Y, i, j, "row"); z = gridValue(h.ZData, i, j, "col"); end
            if ~all(isfinite([x y z])), return; end
            held = ishold(ax); hold(ax, 'on');
            if polar, m = polarplot(ax, x, y, 'ko'); else, m = plot3(ax, x, y, z, 'ko', 'Clipping', 'off'); end
            if ~held, hold(ax, 'off'); end
            set(m, 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off', 'Tag', 'APAT_POB', 'ContextMenu', app.ui.plotMenu);
            m.DataTipTemplate.DataTipRows = rows;
            t = datatip(m, 'DataIndex', 1, 'FontSize', 9, 'HandleVisibility', 'off', 'Tag', 'APAT_POB');
            if isequal(ax, app.ui.axCtr), if x > mean(ax.XLim), t.Location = 'southwest'; else, t.Location = 'southeast'; end, end
            m.Visible = app.ui.chkPOB.Value; t.Visible = app.ui.chkPOB.Value;
        end

        function onPOBToggled(app)
            set(findall(app.ui.fig, 'Tag', 'APAT_POB'), 'Visible', app.ui.chkPOB.Value);
        end

        function refreshHPBWTips(app)
            % HPBW bound markers follow the checkbox; their DataTips are shown only on the visible cut tab.
            on = app.ui.chkHPBW.Value; sel = app.ui.tabCut.SelectedTab;
            for t = reshape(findall(app.ui.tabCut, 'Tag', 'APAT_HPBW'), 1, [])
                t.Visible = on && (~isa(t, 'matlab.graphics.datatip.DataTip') || isequal(ancestor(t, 'uitab'), sel));
            end
        end

        %% ------------------------------------------------------------------ cuts
        function [type, value] = planeSettings(app, ePlane)
            % E-plane: θ-cut through the boresight axis at its φ. H-plane: θ-cut at φ=90° for ±Z, else the φ-cut at θ=90°.
            A = app.Axes6; k = app.boresight; type = 'Theta';
            if ePlane, value = A.phi(k); return; end
            if A.theta(k) == 90, type = 'Phi'; value = 90 - 90*app.isElevation(); else, value = 90; end
        end

        function onEHPlane(app, ~, ~)
            [type, value] = app.planeSettings(startsWith(app.ui.ehSwitch.Value, 'E'));
            app.ui.cutType.Value = type; vals = app.updateCutControl();
            [~, k] = min(abs(vals - value)); app.ui.cutValue.Value = vals(k); app.onCutChanged();
        end

        function vals = updateCutControl(app)
            % Cut value = fixed θ for a φ-cut (sweep φ) and fixed φ for a θ-cut (sweep θ).
            if strcmp(app.ui.cutType.Value, 'Phi'), vals = unique(app.viewTbl.Theta); else, vals = unique(mod(app.viewTbl.Phi, 360)); end
            s = app.ui.cutValue; [~, k] = min(abs(vals - s.Value)); lim = [min(vals), max(vals)]; if diff(lim) <= 0, lim(2) = lim(1) + 1; end
            app.setWithin(s, vals(k), lim);
            if numel(vals) > 1, s.Step = min(diff(vals)); end
        end

        function onCutChanged(app, ~, evt)
            u = app.ui;
            if nargin > 2 && ~isempty(evt) && isprop(evt, 'Source')
                if evt.Source == u.cutType, app.updateCutControl();
                elseif evt.Source == u.basis, u.basis.UserData = false; app.updateMetadata(); end
            end
            u.chkHPBW.Visible = u.hpbwBtn.Value; if ~u.hpbwBtn.Value, u.chkHPBW.Value = false; end
            app.plotCut();
        end

        function [cols, idx] = cutCols(app)
            % Selected cut traces: Total plus the co/cross pair of the chosen basis; IDX keeps trace colours stable.
            if app.src.isGainOnly, cols = string(app.comp()); idx = 1; return; end
            u = app.ui;
            if strcmp(u.basis.Value, 'Linear'), all3 = ["E_Total_dB","E_TH_dB","E_PH_dB"]; else, all3 = ["E_Total_dB","E_RCP_dB","E_LCP_dB"]; end
            u.chkEr.Text = char(extractBefore(all3(2), "_dB")); u.chkEl.Text = char(extractBefore(all3(3), "_dB"));
            sel = [u.chkEt.Value, u.chkEr.Value, u.chkEl.Value]; if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = all3(idx);
        end

        function c = cutData(app)
            % The active cut as one closed circle: sweep angle (display convention), values, physical geometry, title.
            T = app.viewTbl; [cols, idx] = app.cutCols(); type = string(app.ui.cutType.Value); [th, ph] = app.physAngles();
            [ang, rows, fixed, sym, snapped] = calcCutGeometry(T.Theta, T.Phi, th, ph, type, app.ui.cutValue.Value);
            if snapped, app.setStatus(app.ui.status, sprintf('%s cut snapped to nearest %s = %g°', type, sym, fixed), true); end
            V = T{rows, cellstr(cols)}; th = th(rows); ph = ph(rows);
            if app.isSigned() && type == "Theta"
                ang(ang > 180) = ang(ang > 180) - 360; [ang, o] = sort(ang); V = V(o, :); th = th(o); ph = ph(o);
            end
            [ang, u] = unique(ang, 'stable'); V = V(u, :); th = th(u); ph = ph(u);
            if type == "Phi"                                % close the circle at the φ seam when one side is missing
                lo = -180*app.isSigned(); hi = lo + 360;
                if abs(ang(1) - lo) > 1e-9 && abs(ang(end) - hi) < 1e-9, ang = [lo; ang]; V = [V(end, :); V]; th = [th(end); th]; ph = [ph(end); ph];
                elseif abs(ang(1) - lo) < 1e-9 && abs(ang(end) - hi) > 1e-9, ang = [ang; hi]; V = [V; V(1, :)]; th = [th; th(1)]; ph = [ph; ph(1)]; end
            end
            c = struct('angle', ang, 'values', V, 'cols', cols, 'idx', idx, 'theta', th, 'phi', ph, 'type', type, ...
                'title', sprintf('%s cut @ %s = %g°', type, sym, fixed));
            if app.src.isGainOnly, c.title = sprintf('%s  |  %s', app.compLabel(), c.title); end
        end

        function plotCut(app)
            if isempty(app.viewTbl), return; end
            u = app.ui; pax = u.paxCut; rax = u.axRect; c = app.cutData(); lim = app.cutLim; names = replace(c.cols, "_", "\_");
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on'); u.hpbwLabel.Text = '';
            pl = polarplot(pax, deg2rad(c.angle), max(c.values, lim(1)), 'LineWidth', 1.4);   % clamp: no reflection below RLim
            rl = plot(rax, c.angle, c.values, 'LineWidth', 1.4);
            colors = rax.ColorOrder(1 + mod(c.idx - 1, size(rax.ColorOrder, 1)), :);
            for k = 1:numel(pl)
                set([pl(k) rl(k)], 'Color', colors(k, :));
                rows = [dataTipTextRow("Angle", c.angle, '%.3g°'); dataTipTextRow("Magnitude", c.values(:, k), '%.3g dB')];
                pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            xl = [0 360] - 180*app.isSigned();
            set(pax, 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.setPolarTicks(pax);
            set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, c.type + " (degree)"); title(pax, c.title, 'Interpreter', 'none'); title(rax, c.title, 'Interpreter', 'none');
            legend(pax, pl, names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rl, names, 'Location', 'best');
            [pk, ki] = max(c.values(:, 1), [], 'omitnan');   % POB of a cut = peak of its first plotted trace
            if isfinite(pk)
                rows = [dataTipTextRow("Angle", c.angle(ki), '%.3g°'); dataTipTextRow("Magnitude", pk, '%.3g dB')];
                app.markPOB(pl(1), ki, 1, rows); app.markPOB(rl(1), ki, 1, rows);
                if u.hpbwBtn.Value, app.drawHPBW(c, pk, ki, xl); end
            end
            hold(pax, 'off'); hold(rax, 'off'); app.drawOverlays();
        end

        function drawHPBW(app, c, pk, ki, xl)
            % Shade the half-power region (wrap-aware) and mark the interpolated −3 dB bounds with DataTips.
            [bw, lo, hi] = calcHPBW(c.angle, c.values(:, 1), pk, c.angle(ki)); if ~isfinite(bw), return; end
            b = mod([lo hi] - xl(1), 360) + xl(1); u = app.ui;
            u.hpbwLabel.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
            if b(1) <= b(2), reg = b; else, reg = [xl(1), b(2); b(1), xl(2)]; end
            thetaregion(u.paxCut, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
            xregion(u.axRect, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
            names = ["Lower HPBW", "Upper HPBW"];
            for k = 1:2
                rows = [dataTipTextRow(names(k), b(k), '%.2f°'); dataTipTextRow("Gain", pk - 3, '%.2f dB')];
                for m = [polarplot(u.paxCut, deg2rad(b(k)), pk - 3, 'o'), plot(u.axRect, b(k), pk - 3, 'o')]
                    set(m, 'Color', '#D95319', 'MarkerFaceColor', '#D95319', 'HandleVisibility', 'off', 'Tag', 'APAT_HPBW');
                    m.DataTipTemplate.DataTipRows = rows; datatip(m, 'DataIndex', 1, 'Tag', 'APAT_HPBW', 'HandleVisibility', 'off');
                end
            end
            app.refreshHPBWTips();
        end

        function drawOverlays(app, ~, ~)
            % Add/remove the cut overlay on both spatial 3-D views without re-rendering their surfaces.
            app.drawOverlay(app.ui.axSph, "sphere"); app.drawOverlay(app.ui.axPol, "polar");
        end

        function drawOverlay(app, ax, kind)
            delete(findall(ax, 'Tag', 'APAT_CutOverlay'));
            if ~app.ui.chkOverlay.Value || isempty(findall(ax, 'Tag', 'APAT_Surface')), return; end
            c = app.cutData(); v = c.values(:, 1); [lim, ~] = app.plotTheme(); r = 1.02;
            if kind == "polar"                              % same normalization as the polar-3D surface itself
                G = app.gridComp(app.comp()); rmax = max(max(G - lim(1), 0), [], 'all')/max(diff(lim), eps);
                r = 1.01*max(v - lim(1), 0)/max(diff(lim), eps)/max(rmax, eps);
            end
            held = ishold(ax); hold(ax, 'on');
            plot3(ax, r.*sind(c.theta).*cosd(c.phi), r.*sind(c.theta).*sind(c.phi), r.*cosd(c.theta), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay');
            if ~held, hold(ax, 'off'); end
        end

        %% ------------------------------------------------------------------ exports
        function exportResults(app, ~, ~)
            app.saveTable(app.ui.tableOut.Data, [app.baseName '_APAT_results.csv'], 'Export Results');   % honours the column filter
        end

        function exportCut(app, ~, ~)
            if isempty(app.viewTbl), return; end
            c = app.cutData(); app.saveTable(array2table([c.angle, c.values], 'VariableNames', [{'Angle_deg'}, cellstr(c.cols)]), [app.baseName '_cut.csv'], 'Export Cut');
        end

        function exportUAN(app, ~, ~)
            T = app.viewTbl; [th, ~] = app.physAngles();
            U = sortrows(table(th, T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta','Phi','E_TH_DB','E_PH_DB','E_TH_DG','E_PH_DG'}), {'Phi', 'Theta'});
            peak = max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan'); step = gridStep(U.Theta); if ~isfinite(step), step = 1; end
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'CSV (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'}, ...
                'Export UAN / E-field data', fullfile(app.folderPath, sprintf('%s_%.5f_%gdeg.uan', app.baseName, peak, step)));
            if isequal(f, 0), return; end
            fp = fullfile(p, f); done = app.beginOperation('Saving', 'Writing file...', false); %#ok<NASGU>
            if endsWith(fp, '.uan', 'IgnoreCase', true)
                header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                    min(U.Phi), max(U.Phi), gridStep(U.Phi), min(U.Theta), max(U.Theta), step, peak);
                writelines(header, fp); writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
            else
                app.writeTable(U, fp);
            end
            app.setStatus(app.ui.status, ['UAN exported to <b>' fp '</b>'], true);
        end

        function saveTable(app, T, defaultName, titleText)
            if isempty(T), return; end
            [f, p] = uiputfile({'*.csv', 'CSV (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, titleText, fullfile(app.folderPath, defaultName));
            if isequal(f, 0), return; end
            fp = fullfile(p, f); app.writeTable(T, fp);
            st = app.ui.status; if app.ui.tabs.SelectedTab == app.ui.tabCov, st = app.ui.covStatus; end
            app.setStatus(st, ['Exported to <b>' fp '</b>'], true);
        end

        function writeTable(~, T, fp)
            if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
        end

        %% ===================================================================== coverage
        function toCoverage(app, ~, ~)
            % Coverage always consumes the CURRENT Main view table (loss, step, span already applied).
            if isempty(app.viewTbl), uialert(app.ui.fig, 'Load and process a pattern first.', 'Coverage'); return; end
            app.ui.tabs.SelectedTab = app.ui.tabCov; app.ui.covPath.Value = app.filePath; node = app.covFindByPath(app.filePath);
            if isempty(node), [th, ph] = app.physAngles(); app.covAddPattern(app.baseName, app.filePath, app.viewTbl, th, ph, app.rawTbl);
            else, app.covSyncFromView(node); app.ui.covTree.SelectedNodes = node; app.covSelectPattern(node); end
            app.setStatus(app.ui.covStatus, 'Coverage source synchronized from the current Main view table.', false);
        end

        function covLoad(app, ~, ~)
            fp = strtrim(app.ui.covPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFindByPath(fp))
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.ffd;*.ffe;*.ffs;*.cut;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage data'; '*.*', 'All files'}, ...
                    'Select a pattern or coverage results file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            existing = app.covFindByPath(fp); app.ui.covPath.Value = fp;
            if ~isempty(existing)
                app.ui.covTree.SelectedNodes = existing; app.covSelected(); app.setStatus(app.ui.covStatus, 'File already loaded — node selected.', true); return
            end
            src = app.readSource(fp, "cov");
            if src.userData.isCoverage, app.covLoadResults(fp, src.rawTbl); else, [~, name] = fileparts(fp); app.covAddFile(name, fp, src); end
        end

        function node = covAddFile(app, name, fp, src)
            % Process a file for Coverage without touching the Main view (multi-frequency FFD uses block 1).
            S = normalizePattern(src.blocks{1}); S.Properties.UserData = src.userData;
            P = calcPattern(S, app.getParam(), app.PeakPct, app.PeakExcess);
            node = app.covAddPattern(name, fp, P, P.Theta, P.Phi, src.rawTbl);
        end

        function node = covAddPattern(app, name, path, pattern, theta, phi, raw)
            % Pattern node = processed table + PHYSICAL angles + solid-angle weights: the source of every job under it.
            node = uitreenode(app.ui.covRoot, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', "pattern", 'name', name, 'path', path, 'pattern', pattern, 'raw', raw, 'theta', theta, 'phi', phi, ...
                'dOmega', solidWeights(theta, pattern.Phi), 'rev', app.viewRev, 'component', "", 'boresight', 1);
            expand(app.ui.covTree); app.covCheck(node); app.ui.covTree.SelectedNodes = node;
            app.covSelectPattern(node); app.covUI(); app.ui.panelCovResults.Visible = 'on';
            app.setStatus(app.ui.covStatus, sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name), false);
        end

        function covSyncFromView(app, node)
            d = node.NodeData; [d.theta, d.phi] = app.physAngles(); d.pattern = app.viewTbl; d.raw = app.rawTbl;
            d.dOmega = app.dOmega; d.rev = app.viewRev; d.name = app.baseName; node.NodeData = d;
        end

        function covSelectPattern(app, node, chosen)
            % Make NODE the active source: component list, detected boresight, and a one-time threshold preset per
            % (pattern, component, view revision). User-edited thresholds are otherwise used verbatim.
            d = node.NodeData; dd = app.ui.covComp; [cols, labels] = app.componentMap(d.pattern);
            if nargin < 3, chosen = d.component; end, if chosen == "", chosen = string(dd.Value); end
            app.setItems(dd, labels, cols, chosen); comp = string(dd.Value);
            if comp ~= d.component
                [~, d.boresight] = calcOrientation(d.theta, d.phi, chooseGain(d.pattern, comp), d.dOmega, app.Axes6, app.PeakPct, app.PeakExcess);
                d.component = comp; node.NodeData = d;
                if app.ui.covOrient.Value == 0, app.covOrientationChanged(); end
            end
            key = sprintf('%s|%s|%d', d.path, comp, d.rev);
            if ~strcmp(app.covPreset, key), w = app.peakWindow(d.pattern.(comp)); app.ui.thrMin.Value = w(1); app.ui.thrMax.Value = w(2); app.covPreset = key; end
            app.covReportOrientation();
        end

        function node = covTarget(app)
            % Pattern node to compute on: the selection (or its pattern ancestor), else the most recently added pattern.
            node = []; sel = app.ui.covTree.SelectedNodes; n = []; if ~isempty(sel), n = sel(1); end
            while isa(n, 'matlab.ui.container.TreeNode')
                if isstruct(n.NodeData) && n.NodeData.kind == "pattern", node = n; return; end
                n = n.Parent;
            end
            kids = app.ui.covRoot.Children;
            for k = numel(kids):-1:1, if kids(k).NodeData.kind == "pattern", node = kids(k); return; end, end
        end

        function node = covFindByPath(app, fp)
            node = [];
            for n = reshape(app.ui.covRoot.Children, 1, [])
                if strcmp(n.NodeData.path, fp), node = n; return; end
            end
        end

        function jobs = covJobs(app, roots)
            % All job nodes (the tree is the only registry), sorted by run id; optionally within ROOTS' subtrees.
            if nargin < 2, roots = app.ui.covRoot; end
            found = findobj(roots); isJob = arrayfun(@(n) isprop(n, 'NodeData') && isstruct(n.NodeData) && n.NodeData.kind == "job", found);
            jobs = found(isJob); if isempty(jobs), return; end
            [~, o] = sort(arrayfun(@(n) n.NodeData.id, jobs)); jobs = jobs(o);
        end

        function on = isChecked(app, nodes)
            cn = app.ui.covTree.CheckedNodes; on = false(size(nodes));
            if ~isempty(nodes) && ~isempty(cn), on = ismember(nodes, cn); end
        end

        function covCheck(app, nodes)
            tree = app.ui.covTree; cn = tree.CheckedNodes;
            if isempty(cn), tree.CheckedNodes = nodes; else, tree.CheckedNodes = [cn; nodes(~ismember(nodes, cn))]; end
        end

        function thr = covThresholds(app)
            % Thresholds exactly as entered (min:step:max, max always included).
            u = app.ui; lo = u.thrMin.Value; step = max(u.thrStep.Value, 0.1); hi = u.thrMax.Value;
            if hi <= lo, hi = lo + step; u.thrMax.Value = hi; end
            thr = (lo:step:hi)'; if thr(end) < hi - 1e-9, thr(end+1) = hi; end
        end

        function covCompute(app, ~, ~)
            node = app.covTarget();
            if isempty(node), uialert(app.ui.fig, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if strcmp(node.NodeData.path, app.filePath) && ~isempty(app.viewTbl), app.covSyncFromView(node); end   % Main pattern → live view
            d = node.NodeData; u = app.ui; comp = char(u.covComp.Value); thr = app.covThresholds(); gain = d.pattern.(comp);
            conical = u.covConical.Value; orient = ""; mask = true(size(gain)); tag = 'Sph'; label = 'Spherical coverage';
            if conical
                k = u.covOrient.Value; if k == 0, k = d.boresight; end, orient = string(app.Axes6.labels{k});
                [t0, p0, a] = deal(u.coneTh.Value, mod(u.conePh.Value, 360), u.coneAng.Value);
                mask = cosd(d.theta).*cosd(t0) + sind(d.theta).*sind(t0).*cosd(d.phi - p0) >= cosd(a);
                centre = app.coneLabel(t0, p0); tag = sprintf('Con %s α%s°', centre, app.fmt(a)); label = sprintf('Conical coverage (%s) α=%s°', centre, app.fmt(a));
            end
            app.covAddJob(node, thr, coverageCCDF(gain, mask, thr, d.dOmega), tag, comp, label, orient);
            app.covFinish(node, [thr(1) thr(end)]);
            msg = sprintf('Run <b>%d</b>: <b>%s</b> on "<b>%s</b>" (%s, %d thresholds)', app.covRunID, label, d.name, comp, numel(thr));
            if conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, orient); end
            app.setStatus(u.covStatus, msg, false);
        end

        function job = covAddJob(app, parent, thr, cov, tag, component, label, orient)
            % One job = one curve + one tree node whose NodeData feeds table, legend, queries and status.
            app.covRunID = app.covRunID + 1; icon = '📉'; if strcmp(tag, 'Res'), icon = '📈'; end
            text = sprintf('%s R%d %s · %s', icon, app.covRunID, label, component);
            curve = plot(app.ui.axCov, thr, cov, 'LineWidth', 1.6, 'DisplayName', text);
            job = uitreenode(parent, 'Text', text);
            job.NodeData = struct('kind', "job", 'id', app.covRunID, 'tag', tag, 'thr', thr(:), 'cov', cov(:), 'line', curve, 'label', text, 'orientation', orient);
        end

        function covLoadResults(app, fp, R)
            [~, name] = fileparts(fp); node = uitreenode(app.ui.covRoot, 'Text', ['📄 ' name]);
            node.NodeData = struct('kind', "results", 'name', name, 'path', fp); thr = R{:, 1};
            for k = 2:width(R), app.covAddJob(node, thr, R{:, k}, 'Res', R.Properties.VariableNames{k}, 'Loaded results', ""); end
            app.covFinish(node, [min(thr) max(thr)]);
            app.setStatus(app.ui.covStatus, sprintf('Coverage results "%s" loaded (%d curves).', name, width(R) - 1), false);
        end

        function covFinish(app, node, xr)
            % Common tail of every job creation: check the new nodes, rebuild table/legend, extend the X axis baseline.
            expand(node); expand(app.ui.covRoot); app.covCheck([node; node.Children]); app.covRefresh();
            if app.covXInit, xr = [min(xr(1), app.ui.axCov.XLim(1)), max(xr(2), app.ui.axCov.XLim(2))]; end
            app.setRange("covX", xr, true); app.covXInit = true; app.ui.panelCovResults.Visible = 'on';
        end

        function covRefresh(app)
            % Results table (union threshold grid, one column per checked job) + legend + control state.
            jobs = app.covJobs(); checked = jobs(app.isChecked(jobs)); n = numel(checked);
            if n == 0, thr = app.covThresholds(); else, d = [checked.NodeData]; thr = unique(vertcat(d.thr)); end
            M = nan(numel(thr), n + 1); M(:, 1) = thr; names = [{'Threshold (dB)'}, cell(1, n)];
            for k = 1:n
                j = checked(k).NodeData; M(:, k+1) = interp1(j.thr, j.cov, thr, 'linear', NaN); names{k+1} = sprintf('R%d %s %%', j.id, j.tag);
            end
            app.ui.covTable.Data = array2table(compose('%.2f', M), 'VariableNames', names);
            live = arrayfun(@(nd) isgraphics(nd.NodeData.line), checked);
            if any(live), d = [checked(live).NodeData]; legend(app.ui.axCov, [d.line], {d.label}, 'Location', 'southwest', 'Interpreter', 'none');
            else, legend(app.ui.axCov, 'off'); end
            app.covUI();
        end

        function covUI(app)
            % Control policy: no nodes → load controls; results only → + query/export/reset; pattern → everything.
            u = app.ui; hasPattern = ~isempty(app.covTarget()); hasJobs = ~isempty(app.covJobs()); every = u.covPanelGrid.Children;
            base = [u.covPathLabel u.covPath u.covLoadBtn u.covComputeBtn]; results = [u.covQuery u.covResetBtn u.covExportBtn u.covClearBtn u.covToMainBtn];
            if hasPattern, show = every; elseif hasJobs, show = [base results]; else, show = base; end
            set(every, 'Visible', 'off', 'Enable', 'off'); set(show, 'Visible', 'on', 'Enable', 'on');
            set([u.covExportBtn u.covClearBtn u.covQuery], 'Enable', hasJobs); set(u.covComputeBtn, 'Enable', hasPattern);
            set([u.covFmtLabel u.covFmt], 'Visible', hasPattern && app.isGenericText(u.covPath.Value));
            app.covTypeChanged();
        end

        function covTypeChanged(app, ~, ~)
            u = app.ui; on = u.covConical.Value && ~isempty(app.covTarget());
            set([u.coneThLabel u.coneTh u.conePhLabel u.conePh u.coneAngLabel u.coneAng u.covOrientLabel u.covOrient], 'Visible', on, 'Enable', on);
            app.covReportOrientation();
        end

        function covOrientationChanged(app, ~, ~)
            % Auto → detected boresight of the active pattern; explicit → that axis. Seeds the cone-centre spinners.
            node = app.covTarget(); k = app.ui.covOrient.Value;
            if k == 0, if isempty(node), return; end, k = node.NodeData.boresight; end
            app.ui.coneTh.Value = app.Axes6.theta(k); app.ui.conePh.Value = app.Axes6.phi(k); app.covReportOrientation();
        end

        function covComponentChanged(app, ~, ~)
            node = app.covTarget(); if ~isempty(node), app.covSelectPattern(node, string(app.ui.covComp.Value)); end
        end

        function covReportOrientation(app)
            % Keep " | Orientation <axis>" appended to the persistent Coverage status while Conical mode is active.
            u = app.ui; base = regexprep(char(u.covStatus.UserData), '\s*\|\s*Orientation <b>.*?</b>$', '');
            node = app.covTarget(); k = u.covOrient.Value; if k == 0 && ~isempty(node), k = node.NodeData.boresight; end
            if u.covConical.Value && k >= 1, base = sprintf('%s | Orientation <b>%s</b>', base, app.Axes6.labels{k}); end
            app.setStatus(u.covStatus, base, false);
        end

        function s = coneLabel(app, t0, p0)
            % Principal-axis name when the cone centre coincides with ±X/±Y/±Z, else the explicit angles.
            A = app.Axes6; v = [sind(t0)*cosd(p0), sind(t0)*sind(p0), cosd(t0)];
            V = [sind(A.theta(:)).*cosd(A.phi(:)), sind(A.theta(:)).*sind(A.phi(:)), cosd(A.theta(:))]; k = find(V*v' >= 1 - 1e-9, 1);
            if isempty(k), s = sprintf('θ%s° φ%s°', app.fmt(t0), app.fmt(p0)); else, s = A.labels{k}; end
        end

        function covQuery(app, mode)
            % Project a threshold ("cov": x→y) or a coverage level ("thr": y→x) onto every checked job under the selection.
            u = app.ui; sel = u.covTree.SelectedNodes;
            if isempty(sel), app.setStatus(u.covStatus, 'Select a node to query.', true); return; end
            jobs = app.covJobs(sel); jobs = jobs(app.isChecked(jobs)); hit = false;
            if mode == "cov", q = u.qCov.Value; else, q = u.qThr.Value; end
            for job = reshape(jobs, 1, [])
                j = job.NodeData; if ~isgraphics(j.line), continue; end
                tag = sprintf('CovQ_%s_%d', mode, j.id); delete(findall(u.axCov, 'Tag', tag));
                [x, y] = app.covPoint(j, mode, q); if ~all(isfinite([x y])), continue; end
                line(u.axCov, [x x], [0 y], 'Color', j.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(u.axCov, [app.DBLim(1) x], [y y], 'Color', j.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                j.line.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", 'XData', '%.2f dB'); dataTipTextRow("Coverage", 'YData', '%.2f%%')];
                datatip(j.line, x, y, 'SnapToDataVertex', 'off', 'FontSize', 9, 'HandleVisibility', 'off', 'Tag', tag); hit = true;
            end
            if ~hit, app.setStatus(u.covStatus, 'Query value is outside the checked results.', true);
            elseif mode == "cov", app.setStatus(u.covStatus, sprintf('Coverage queried at %s dB.', app.fmt(q)), false);
            else, app.setStatus(u.covStatus, sprintf('Threshold queried at %s%% coverage.', app.fmt(q)), false); end
        end

        function [x, y] = covPoint(~, j, mode, q)
            % Linear interpolation on the CCDF: threshold → coverage, or coverage → threshold (last tied sample).
            if mode == "cov", x = q; y = interp1(j.thr, j.cov, q, 'linear', NaN); return; end
            [c, i] = unique(j.cov, 'last'); y = q; x = NaN; if numel(c) > 1, x = interp1(c, j.thr(i), q, 'linear', NaN); end
        end

        function covClear(app, ~, ~)
            % Remove query projections and DataTips under the selected subtree (checked or not).
            sel = app.ui.covTree.SelectedNodes; if isempty(sel), app.setStatus(app.ui.covStatus, 'Select a node to clear.', true); return; end
            for job = reshape(app.covJobs(sel), 1, [])
                j = job.NodeData; delete(findall(app.ui.axCov, '-regexp', 'Tag', sprintf('^CovQ_\\w+_%d$', j.id)));
                if isgraphics(j.line), delete(findall(j.line, 'Type', 'datatip')); end
            end
            app.setStatus(app.ui.covStatus, 'Selected DataTips and query markers cleared.', true);
        end

        function covChecked(app, ~, ~)
            for job = reshape(app.covJobs(), 1, [])
                j = job.NodeData; on = app.isChecked(job); if ~isgraphics(j.line), continue; end
                set([j.line; findall(app.ui.axCov, '-regexp', 'Tag', sprintf('^CovQ_\\w+_%d$', j.id))], 'Visible', on);
                set(findall(j.line, 'Type', 'datatip'), 'Visible', on);
            end
            app.covRefresh();
        end

        function covSelected(app, ~, ~)
            u = app.ui; sel = u.covTree.SelectedNodes; f = @app.fmt;
            for job = reshape(app.covJobs(), 1, [])          % emphasise the selected curve
                ln = job.NodeData.line; if isgraphics(ln), ln.LineWidth = 1.6 + isequal(job, sel); end
            end
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(u.covStatus, 'Ready.', false); return; end
            d = sel(1).NodeData; node = app.covTarget(); if ~isempty(node), app.covSelectPattern(node); end
            if d.kind ~= "job"
                kind = char(d.kind); app.setStatus(u.covStatus, sprintf('%s "<b>%s</b>" — <b>%d</b> coverage job(s).', [upper(kind(1)) kind(2:end)], d.name, numel(sel(1).Children)), false);
                app.covReportOrientation(); return
            end
            r = round(d.cov, 2); mx = max(r); k = find(r == mx, 1, 'last'); if isempty(k), k = 1; end
            [x50, ~] = app.covPoint(d, "thr", 50); parts = {char(d.label)};
            if d.orientation ~= "", parts{end+1} = sprintf('Orientation <b>%s</b>', d.orientation); end
            parts{end+1} = sprintf('Threshold [%s, %s] dB step %s', f(d.thr(1)), f(d.thr(end)), f(gridStep(d.thr)));
            if isfinite(x50), parts{end+1} = sprintf('50%%-coverage threshold <b>%s dB</b>', f(x50)); else, parts{end+1} = '50%-coverage unavailable'; end
            parts{end+1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', f(mx), f(d.thr(k)));
            app.setStatus(u.covStatus, strjoin(parts, ' | '), false);
        end

        function covExport(app, ~, ~)
            app.saveTable(app.ui.covTable.Data, 'coverage_results.csv', 'Export Coverage Results');
        end

        function onCovFormatChanged(app, ~, ~)
            % Re-interpret an already loaded generic coverage pattern with the newly selected text format.
            fp = strtrim(app.ui.covPath.Value); old = app.covFindByPath(fp); if isempty(old) || ~app.isGenericText(fp), return; end
            src = readPattern(fp, app.ui.covFmt.Value, old.NodeData.raw);
            if src.userData.isCoverage, app.setStatus(app.ui.covStatus, 'Coverage-result files are detected automatically.', true); return; end
            for job = reshape(old.Children, 1, []), if isgraphics(job.NodeData.line), delete(job.NodeData.line); end, end
            name = old.NodeData.name; delete(old); app.covAddFile(name, fp, src); app.covRefresh();
            app.setStatus(app.ui.covStatus, sprintf('Pattern "<b>%s</b>" reprocessed with the selected format.', name), true);
        end

        function covReset(app, ~, ~)
            % Return the Coverage workspace to its initial state (also used at startup).
            u = app.ui; delete(u.covRoot.Children); delete(findall(u.axCov, 'Type', 'datatip'));
            cla(u.axCov); legend(u.axCov, 'off'); hold(u.axCov, 'on'); grid(u.axCov, 'on'); set(u.axCov, 'YLim', [0 100], 'Box', 'on', 'Layer', 'top');
            u.covTable.Data = table(); app.covRunID = 0; app.covPreset = ''; app.covXInit = false;
            app.setRange("covX", [-40 10], false); u.panelCovResults.Visible = 'off'; app.covUI();
            app.setStatus(u.covStatus, 'Coverage workspace reset 🔄', true);
        end

        %% ===================================================================== status, dialogs, helpers
        function setStatus(app, label, msg, temporary)
            % Persistent messages are remembered in label.UserData; a temporary one is restored after 3 s.
            if app.isClosing || ~isgraphics(label), return; end
            t = app.statusTimer; if ~isempty(t) && isvalid(t) && strcmp(t.Running, 'on'), stop(t); end
            msg = char(msg); label.Text = msg;
            if ~temporary, label.UserData = msg; return; end
            if isempty(t) || ~isvalid(t)
                t = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, 'TimerFcn', @(tm, ~) app.restoreStatus(tm)); app.statusTimer = t;
            end
            t.UserData = label; start(t);
        end

        function restoreStatus(app, tm)
            if ~app.isClosing && isgraphics(tm.UserData), tm.UserData.Text = char(tm.UserData.UserData); end
        end

        function showError(app, ME)
            if app.isClosing || ~isgraphics(app.ui.fig), return; end
            where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.ui.fig, [ME.message where], 'APAT Error', 'Icon', 'error');
        end

        function done = beginOperation(app, titleText, message, cancelable)
            % Modal progress dialog + stage timer; the returned onCleanup closes both when the caller exits (even on error).
            dlg = uiprogressdlg(app.ui.fig, 'Title', titleText, 'Message', message, 'Indeterminate', 'on', 'Cancelable', cancelable, 'CancelText', 'Abort');
            app.opDialog = dlg; drawnow; stop = app.startPerf(titleText);
            done = onCleanup(@() app.endOperation(dlg, stop));
        end

        function endOperation(app, dlg, stop)
            stop(); if isvalid(dlg), close(dlg); end
            if isequal(app.opDialog, dlg), app.opDialog = []; end
        end

        function checkCancelled(app)
            d = app.opDialog;
            if ~isempty(d) && isvalid(d) && d.CancelRequested, d.Message = 'Aborting...'; drawnow limitrate; error('APAT:Cancelled', 'Operation cancelled by user.'); end
        end

        function stop = startPerf(app, operation)
            % Stage timer: app.perf("stage") records elapsed time; STOP() stores the report in the base workspace.
            stages = cell(0, 2); t0 = tic; t = tic; app.perf = @record; stop = @save;
            function record(stage), stages(end+1, :) = {string(stage), toc(t)}; t = tic; end
            function save()
                if isempty(stages), return; end
                assignin('base', 'Perf_APAT_M8', struct('Operation', string(operation), 'Stages', cell2table(stages, 'VariableNames', {'Stage', 'Seconds'}), 'TotalSeconds', toc(t0)));
                app.perf = @(~) []; stages = cell(0, 2);
            end
        end

        function s = fmt(~, v, digits)
            % Compact number text: up to 2 decimals without trailing zeros, or exactly DIGITS decimals.
            if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return; end
            if nargin < 3, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); if strcmp(s, '-0'), s = '0'; end, else, s = sprintf('%.*f', digits, v); end
        end

        function tf = isGenericText(~, fp), [~, ~, ext] = fileparts(fp); tf = any(strcmpi(ext, {'.csv', '.txt', '.dat'})); end
        function tf = isSigned(app), tf = strcmp(app.ui.phiSpan.Value, '-180° to 180°'); end
        function tf = isElevation(app), tf = strcmp(app.ui.thetaSpan.Value, '-90° to 90°'); end
        function s = thetaLabel(app), if app.isElevation(), s = "Elevation"; else, s = "Theta"; end, end
        function c = comp(app), c = app.ui.comp.Value; end
        function s = compLabel(app)
            dd = app.ui.comp; k = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(k), s = string(dd.Value); else, s = string(dd.Items{k}); end
        end

        %% ===================================================================== UI construction
        function h = add(~, ctor, parent, row, col, varargin)
            % Create a component in a grid cell; CTOR is a constructor handle such as @uibutton.
            h = ctor(parent, varargin{:}); h.Layout.Row = row; h.Layout.Column = col;
        end

        function h = label(app, parent, text, row, col, varargin)
            h = app.add(@uilabel, parent, row, col, 'Text', text, 'HorizontalAlignment', 'right', varargin{:});
        end

        function [ax, tab, r] = patternTab(app, group, name, cartesian)
            % One full-pattern tab: axes (uiaxes or polaraxes) beside a vertical range slider with min/max spinners.
            tab = uitab(group, 'Title', name); g = uigridlayout(tab, [3 2]); g.ColumnWidth = {'fit', '1x'}; g.RowHeight = {'fit', '1x', 'fit'};
            if cartesian, ax = uiaxes(g); else, ax = polaraxes(g); end
            ax.Layout.Row = [1 3]; ax.Layout.Column = 2;
            r.max = app.add(@uispinner, g, 1, 1, 'Limits', app.DBLim, 'Value', 100, 'Step', 5);
            r.slider = app.add(@(p, varargin) uislider(p, 'range', varargin{:}), g, 2, 1, 'Limits', app.DBLim, 'Value', app.DBLim, 'Orientation', 'vertical', 'Step', 1);
            r.min = app.add(@uispinner, g, 3, 1, 'Limits', app.DBLim, 'Value', -250, 'Step', 5);
        end

        function createUI(app)
            u = struct(); pad = @(n) repmat(char(160), 1, n); ready = 'Ready 🚀';
            stateBtn = @(p, varargin) uibutton(p, 'state', varargin{:}); rangeSlider = @(p, varargin) uislider(p, 'range', varargin{:});
            sw = @(p, varargin) uiswitch(p, 'slider', varargin{:}); textField = @(p, varargin) uieditfield(p, 'text', varargin{:});
            u.fig = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.Release], 'Visible', 'off', 'Position', [100 100 1136 739], ...
                'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) delete(app));
            u.tabs = uitabgroup(uigridlayout(u.fig, [1 1]));
            u.plotMenu = uicontextmenu(u.fig);                 % one shared menu: acts on the axes under the pointer
            uimenu(u.plotMenu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, e) delete(findall(ancestor(e.ContextObject, {'axes', 'polaraxes'}), 'Type', 'datatip')));

            %% ---- Tab 1: Process Pattern
            u.tabMain = uitab(u.tabs, 'Title', 'Process Pattern 📡');
            G = uigridlayout(u.tabMain, [5 14]); G.RowHeight = {'fit', '2x', 'fit', '1x', 'fit'};
            u.panelParam = app.add(@uipanel, G, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️'); P = uigridlayout(u.panelParam, [3 14]);
            app.label(P, 'Input Pattern:', 1, 1);
            u.path = app.add(textField, P, 1, [2 8]);
            u.ffdLabel = app.label(P, 'FFD Freq:', 1, 9, 'Visible', 'off');
            u.ffd = app.add(@uidropdown, P, 1, 10, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', app.cb(@app.onFFDChanged));
            u.loadBtn = app.add(@uibutton, P, 1, [11 12], 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', app.cb(@app.onLoad));
            u.processBtn = app.add(@uibutton, P, 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', app.cb(@app.onProcess));
            u.resetBtn = app.add(@uibutton, P, 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', app.cb(@app.resetParams));
            u.txtFmtLabel = app.label(P, 'Format:', 2, [4 5], 'Visible', 'off');
            u.txtFmt = app.add(@uidropdown, P, 2, [6 8], app.TextFormats{:}, 'Visible', 'off', 'ValueChangedFcn', app.cb(@app.onFormatChanged));
            u.step = app.add(@uidropdown, P, 2, [9 10], 'Items', {'STEP'}, 'Visible', 'off', 'Enable', 'off', 'ValueChangedFcn', app.cb(@app.stepChanged));
            u.exportBtn = app.add(@uibutton, P, 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@app.exportResults));
            u.exportUAN = app.add(@uibutton, P, 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@app.exportUAN));
            u.rxLabel = app.label(P, 'Rw Sense', 3, 1, 'Visible', 'off');
            u.rxPol = app.add(@uidropdown, P, 3, 2, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Visible', 'off');
            u.rwLabel = app.label(P, 'Rw (dB)', 3, 3, 'Visible', 'off');
            u.rw = app.add(@uispinner, P, 3, 4, 'Value', 6, 'Visible', 'off');
            u.lossLabel = app.label(P, 'Loss (−) / Gain (+) dB', 3, 5, 'Visible', 'off');
            u.loss = app.add(@uispinner, P, 3, 6, 'Step', 0.1, 'Visible', 'off');
            u.ptLabel = app.label(P, 'Tx Pwr (Pt)', 3, 7, 'Visible', 'off');
            u.pt = app.add(@uispinner, P, 3, 8, 'Visible', 'off');
            u.ptUnit = app.add(@uidropdown, P, 3, 9, 'Items', {'dBW', 'dBm', 'Watts'}, 'Visible', 'off');
            u.rLabel = app.label(P, 'Distance', 3, 10, 'Visible', 'off');
            u.dist = app.add(@uispinner, P, 3, 11, 'Value', 1, 'Visible', 'off');
            u.distUnit = app.add(@uidropdown, P, 3, 12, 'Items', {'m', 'km'}, 'Visible', 'off');
            u.covBtn = app.add(@uibutton, P, 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@app.toCoverage));

            u.panelFull = app.add(@uipanel, G, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off');
            u.tabFull = uitabgroup(uigridlayout(u.panelFull, [1 1]));
            [u.axCtr, ~, r(1)] = app.patternTab(u.tabFull, 'Contour Plot', true);
            [u.paxFish, ~, r(2)] = app.patternTab(u.tabFull, 'Circular Contour Plot', false);
            [u.axSph, ~, r(3)] = app.patternTab(u.tabFull, '3D Spherical Plot', true);
            [u.axPol, ~, r(4)] = app.patternTab(u.tabFull, '3D Polar Plot', true);
            [u.axRect3, ~, r(5)] = app.patternTab(u.tabFull, '3D Surface Plot', true);
            u.range.full = struct('slider', [r.slider], 'min', [r.min], 'max', [r.max]);

            u.panelCut = app.add(@uipanel, G, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off');
            u.tabCut = uitabgroup(uigridlayout(u.panelCut, [1 1]), 'SelectionChangedFcn', @(~, ~) app.refreshHPBWTips());
            tabPolar = uitab(u.tabCut, 'Title', 'Polar Cut Plot');
            gp = uigridlayout(tabPolar, [4 4]); gp.ColumnWidth = {'fit', '0.26x', '1x', '0.23x'}; gp.RowHeight = {'fit', '0.25x', '1x', 'fit'};
            u.paxCut = polaraxes(gp); u.paxCut.Layout.Row = [1 4]; u.paxCut.Layout.Column = 3;
            rc.max = app.add(@uispinner, gp, 1, 1, 'Limits', app.DBLim, 'Value', 100, 'Step', 5);
            rc.slider = app.add(rangeSlider, gp, [2 3], 1, 'Limits', app.DBLim, 'Value', app.DBLim, 'Orientation', 'vertical', 'Step', 1);
            rc.min = app.add(@uispinner, gp, 4, 1, 'Limits', app.DBLim, 'Value', -250, 'Step', 5); u.range.cut = rc;
            u.hpbwBtn = app.add(stateBtn, gp, 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', app.cb(@app.onCutChanged));
            u.hpbwLabel = app.add(@uilabel, gp, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            u.gridEcut = uigridlayout(gp, [3 1]); u.gridEcut.Layout.Row = 3; u.gridEcut.Layout.Column = 4;
            u.chkEt = app.add(@uicheckbox, u.gridEcut, 1, 1, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', app.cb(@app.onCutChanged));
            u.chkEr = app.add(@uicheckbox, u.gridEcut, 2, 1, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', app.cb(@app.onCutChanged));
            u.chkEl = app.add(@uicheckbox, u.gridEcut, 3, 1, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', app.cb(@app.onCutChanged));
            u.exportCutBtn = app.add(@uibutton, gp, 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', app.cb(@app.exportCut));
            tabRect = uitab(u.tabCut, 'Title', 'Rectangular Cut Plot');
            u.axRect = uiaxes(uigridlayout(tabRect, [1 1]), 'Box', 'on'); xlabel(u.axRect, 'Theta (degree)'); ylabel(u.axRect, 'Magnitude (dB)');

            u.panelCtrl = app.add(@uipanel, G, 2, [13 14], 'Title', 'Plot Control 🎨', 'Visible', 'off');
            C = uigridlayout(u.panelCtrl, [15 2]); C.RowHeight = repmat({'fit'}, 1, 15);
            app.label(C, 'Component', 1, 1);
            u.comp = app.add(@uidropdown, C, 1, 2, 'Items', cellstr(app.CompLabels), 'ItemsData', cellstr(app.Comps), 'ValueChangedFcn', app.cb(@app.onComponentChanged));
            app.label(C, 'Cut type', 2, 1);
            u.cutType = app.add(@uidropdown, C, 2, 2, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', app.cb(@app.onCutChanged));
            app.label(C, 'Cut value', 3, 1);
            u.cutValue = app.add(@uispinner, C, 3, 2, 'Limits', [0 360], 'ValueChangedFcn', app.cb(@app.onCutChanged));
            app.label(C, 'Cut fields', 4, 1);
            u.basis = app.add(@uidropdown, C, 4, 2, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Enable', 'off', 'UserData', true, 'ValueChangedFcn', app.cb(@app.onCutChanged));
            applyClim = app.cb(@(~, ~) app.setRange("full", [app.ui.cmin.Value, app.ui.cmax.Value], true));
            app.label(C, 'Colorbar max', 5, 1); u.cmax = app.add(@uispinner, C, 5, 2, 'Limits', app.DBLim, 'Value', 10, 'ValueChangedFcn', applyClim);
            app.label(C, 'Colorbar min', 6, 1); u.cmin = app.add(@uispinner, C, 6, 2, 'Limits', app.DBLim, 'Value', -40, 'ValueChangedFcn', applyClim);
            app.label(C, 'Colorbar step', 7, 1); u.cstep = app.add(@uispinner, C, 7, 2, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', app.cb(@(~, ~) app.applyFullRange(app.fullLim)));
            app.label(C, 'Adjust Colorbar', 8, 1); u.climBtn = app.add(@uibutton, C, 8, 2, 'Text', 'Apply', 'Tooltip', 'Apply to all full-pattern plots (AR keeps its fixed ±30 dB scale).', 'ButtonPushedFcn', applyClim);
            app.label(C, '3D view', 9, 1);
            u.view3D = app.add(@uidropdown, C, 9, 2, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Tooltip', 'Camera direction for the 3D pattern tabs.', 'ValueChangedFcn', app.cb(@(~, ~) app.on3DView()));
            u.phiSpan = app.add(sw, C, 10, [1 2], 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'ValueChangedFcn', app.cb(@app.spanChanged));
            u.thetaSpan = app.add(sw, C, 11, [1 2], 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'ValueChangedFcn', app.cb(@app.spanChanged));
            u.ehSwitch = app.add(sw, C, 12, [1 2], 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'ValueChangedFcn', app.cb(@app.onEHPlane));
            u.chkOverlay = app.add(@uicheckbox, C, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', app.cb(@app.drawOverlays));
            u.chkPOB = app.add(@uicheckbox, C, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', app.cb(@(~, ~) app.onPOBToggled()));
            u.chkHPBW = app.add(@uicheckbox, C, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', app.cb(@(~, ~) app.refreshHPBWTips()));

            u.outFilter = app.add(@uidropdown, G, 3, [13 14], 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Visible', 'off', 'ValueChangedFcn', app.cb(@(~, ~) app.filterOutput()));
            u.tabData = app.add(@uitabgroup, G, 4, [1 14], 'Visible', 'off');
            tOut = uitab(u.tabData, 'Title', 'Results 📤', 'ButtonDownFcn', @(~, ~) set(app.ui.outFilter, 'Visible', 'on'));
            u.tableOut = uitable(uigridlayout(tOut, [1 1]), 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnRearrangeable', 'on', 'ColumnWidth', '1x');
            u.tableIn = uitable(uigridlayout(uitab(u.tabData, 'Title', 'Input 📥'), [1 1]), 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnRearrangeable', 'on');
            u.tableMeta = uitable(uigridlayout(uitab(u.tabData, 'Title', 'Metadata 📋'), [1 1]), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            u.status = app.add(@uilabel, G, 5, [1 14], 'Interpreter', 'html', 'Text', ready, 'UserData', ready);

            %% ---- Tab 2: Compute Coverage
            u.tabCov = uitab(u.tabs, 'Title', 'Compute Coverage 📈');
            Gc = uigridlayout(u.tabCov, [3 5]); Gc.ColumnWidth = {'0.75x', 'fit', '1x', 'fit', '1x'}; Gc.RowHeight = {'0.25x', '1x', 'fit'};
            u.covPanel = app.add(@uipanel, Gc, 1, [1 5], 'Title', 'Inputs & Parameters 🎛️');
            Q = uigridlayout(u.covPanel, [4 10]); Q.ColumnWidth = [{'fit'}, repmat({'1x'}, 1, 9)]; Q.RowHeight = {'1x', 'fit', 'fit', 'fit'}; u.covPanelGrid = Q;
            u.covType = app.add(@uibuttongroup, Q, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', app.cb(@app.covTypeChanged));
            u.covSpherical = uiradiobutton(u.covType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            u.covConical = uiradiobutton(u.covType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            u.covOrientLabel = app.label(Q, 'Orientation 🧭:', 3, 1);
            u.covOrient = app.add(@uidropdown, Q, 3, 2, 'Items', [{'Auto'}, app.Axes6.labels], 'ItemsData', 0:6, 'ValueChangedFcn', app.cb(@app.covOrientationChanged));
            u.covPathLabel = app.label(Q, 'Antenna Pattern:', 1, 3);
            u.covPath = app.add(textField, Q, 1, [4 8]);
            u.covLoadBtn = app.add(@uibutton, Q, 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', app.cb(@app.covLoad));
            u.covComputeBtn = app.add(@uibutton, Q, 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'ButtonPushedFcn', app.cb(@app.covCompute));
            app.label(Q, 'Threshold Min (dB):', 2, 3); u.thrMin = app.add(@uispinner, Q, 2, 4, 'Value', -40);
            app.label(Q, 'Threshold Max (dB):', 2, 5); u.thrMax = app.add(@uispinner, Q, 2, 6, 'Value', 10);
            app.label(Q, 'Step (dB):', 2, 7); u.thrStep = app.add(@uispinner, Q, 2, 8, 'Value', 1, 'Limits', [0.1 100]);
            u.covResetBtn = app.add(@uibutton, Q, 2, 9, 'Text', '🔄 Reset', 'ButtonPushedFcn', app.cb(@app.covReset));
            u.covExportBtn = app.add(@uibutton, Q, 2, 10, 'Text', '💾 Export Results', 'ButtonPushedFcn', app.cb(@app.covExport));
            u.coneThLabel = app.label(Q, 'Cone θ₀ (°):', 3, 3); u.coneTh = app.add(@uispinner, Q, 3, 4, 'Limits', [0 180]);
            u.conePhLabel = app.label(Q, 'Cone φ₀ (°):', 3, 5); u.conePh = app.add(@uispinner, Q, 3, 6, 'Limits', [0 360]);
            u.coneAngLabel = app.label(Q, 'Cone Angle α (°):', 3, 7); u.coneAng = app.add(@uispinner, Q, 3, 8, 'Limits', [0 180], 'Value', 45);
            u.covClearBtn = app.add(@uibutton, Q, 3, 9, 'Text', '🧹 Clear DataTips', 'ButtonPushedFcn', app.cb(@app.covClear));
            u.covToMainBtn = app.add(@uibutton, Q, 3, 10, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~, ~) set(u.tabs, 'SelectedTab', u.tabMain));
            u.covCompLabel = app.label(Q, 'Component:', 4, 1);
            u.covComp = app.add(@uidropdown, Q, 4, 2, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', app.cb(@app.covComponentChanged));
            q1 = app.label(Q, 'Coverage @ dB:', 4, 3); u.qCov = app.add(@uispinner, Q, 4, 4, 'ValueDisplayFormat', '%g dB');
            q2 = app.add(@uibutton, Q, 4, 5, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', app.cb(@(~, ~) app.covQuery("cov")));
            q3 = app.label(Q, 'Threshold @ %:', 4, 6); u.qThr = app.add(@uispinner, Q, 4, 7, 'Value', 50, 'ValueDisplayFormat', '%g%%');
            q4 = app.add(@uibutton, Q, 4, 8, 'Text', '🔍 Query Threshold', 'ButtonPushedFcn', app.cb(@(~, ~) app.covQuery("thr")));
            u.covQuery = [q1 u.qCov q2 q3 u.qThr q4];
            u.covFmtLabel = app.label(Q, 'Format:', 4, 9);
            u.covFmt = app.add(@uidropdown, Q, 4, 10, app.TextFormats{:}, 'ValueChangedFcn', app.cb(@app.onCovFormatChanged));
            u.covStatus = app.add(@uilabel, Gc, 3, [1 5], 'Interpreter', 'html', 'Text', ready, 'UserData', ready);
            u.panelCovResults = app.add(@uipanel, Gc, 2, [1 5], 'Title', 'Results', 'Visible', 'off');
            R = uigridlayout(u.panelCovResults, [2 5]); R.ColumnWidth = {'1x', 'fit', '1x', 'fit', '1x'}; R.RowHeight = {'1x', 'fit'};
            u.covTree = app.add(@(p, varargin) uitree(p, 'checkbox', varargin{:}), R, [1 2], 1, 'SelectionChangedFcn', app.cb(@app.covSelected), 'CheckedNodesChangedFcn', app.cb(@app.covChecked));
            u.covRoot = uitreenode(u.covTree, 'Text', 'Coverage Results');
            u.axCov = app.add(@uiaxes, R, 1, [2 4]); title(u.axCov, 'Coverage vs Threshold'); xlabel(u.axCov, 'Threshold (dB)'); ylabel(u.axCov, 'Coverage (%)');
            u.axCov.Interactions = dataTipInteraction;         % display-only axes
            u.covTable = app.add(@uitable, R, [1 2], 5, 'ColumnWidth', '1x', 'RowName', {});
            rx.min = app.add(@uispinner, R, 2, 2, 'Limits', app.DBLim, 'Value', -40);
            rx.slider = app.add(rangeSlider, R, 2, 3, 'Limits', app.DBLim, 'Value', [-40 10]);
            rx.max = app.add(@uispinner, R, 2, 4, 'Limits', app.DBLim, 'Value', 10); u.range.covX = rx;
            app.ui = u;

            %% ---- shared wiring: range groups and axes interactions
            for g = ["full", "cut", "covX"]
                rg = u.range.(g);
                set(rg.slider, 'ValueChangedFcn', app.cb(@(~, e) app.rangeEdited(g, 0, e.Value)));
                set(rg.min, 'ValueChangedFcn', app.cb(@(~, e) app.rangeEdited(g, 1, e.Value)));
                set(rg.max, 'ValueChangedFcn', app.cb(@(~, e) app.rangeEdited(g, 2, e.Value)));
            end
            for ax = [u.axCtr u.axRect], enableDefaultInteractivity(ax); ax.Interactions = [zoomInteraction dataTipInteraction]; end
            for ax = [u.axSph u.axPol u.axRect3], enableDefaultInteractivity(ax); ax.Interactions = [rotateInteraction dataTipInteraction]; end
            set([u.axCtr u.axRect u.axSph u.axPol u.axRect3], 'ContextMenu', u.plotMenu); set([u.paxCut u.paxFish], 'ContextMenu', u.plotMenu);
        end
    end

    %% ===================================================================== self-test
    methods (Access = public)
        function r = runSelfTest(app)
            %RUNSELFTEST Deterministic checks of the numeric core (no files opened by the UI, no state changes).
            [ph, th] = meshgrid(0:30:330, 0:30:180); T = table(th(:), ph(:), 10*cosd(th(:)).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            w = solidWeights(T.Theta, T.Phi); r.passSolidAngle = abs(sum(w) - 4*pi) < 1e-9;
            [pk, k] = calcOrientation(T.Theta, T.Phi, T.E_Total_dB, w, app.Axes6, app.PeakPct, app.PeakExcess);
            r.passOrientation = isfinite(pk.value) && k >= 1 && k <= 6;
            [p2, t2] = meshgrid(0:2:358, 0:2:180); f = @(t, p) 12*cosd(t).^2 - 0.5*sind(p).^2;
            R2 = resampleCanonical(table(t2(:), p2(:), f(t2(:), p2(:)), 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'}), 1);
            native = mod(R2.Theta, 2) == 0 & mod(R2.Phi, 2) == 0 & R2.Phi < 360;
            r.passResampling = height(R2) == 181*361 && max(abs(R2.E_Total_dB(native) - f(R2.Theta(native), R2.Phi(native)))) < 1e-9;
            spike = repmat(0.02, 1e5, 1); spike(1) = 10.02; sp = resolvePeak(spike, app.PeakPct, app.PeakExcess);
            r.passIsolatedSpike = sp.wasAdjusted && abs(sp.value - 0.02) < 1e-12 && sp.rawIndex == 1;
            r.passPeakWindow = isequal(app.peakWindow([3.2; -100]), [-45 5]) && isequal(app.peakWindow(spike), [-45 5]);
            r.passARSemantic = all(arrayfun(@(s) app.isAR(s), ["AR", "AR_dB", "AR dB", "Axial Ratio", "Axial_Ratio"])) && ~app.isAR("E_Total_dB");
            ang = (0:0.5:359.5)'; bw = calcHPBW(ang, 20*log10(max(abs(cosd(ang)), 1e-6)), 0, 0); r.passHPBW = abs(bw - 89.87) < 0.3;
            r.passCCDF = isequal(coverageCCDF([0; 10; 20; 30], true(4, 1), [5; 15; 25; 35], ones(4, 1)), [75; 50; 25; 0]);
            ffd = [tempname '.ffd']; writelines(["0 180 3"; "-180 180 3"; string(compose('%d 0 0 1', (1:9)'))], ffd); c = onCleanup(@() delete(ffd)); %#ok<NASGU>
            d = readPattern(ffd, "ffd", table()); r.passFFDReader = strcmp(d.userData.source, 'HFSS FFD') && height(d.blocks{1}) == 9;
            names = fieldnames(r); failed = names(cellfun(@(n) ~r.(n), names)); r.pass = isempty(failed);
            if ~r.pass, error('APAT:SelfTest', 'Self-test failed: %s', strjoin(failed, ', ')); end
        end
    end
end

%% ========================================================================= I/O (UI-independent)
function out = readPattern(fp, fmt, cached)
%READPATTERN Parse any supported source into the canonical contract {rawTbl, blocks{}, freqs, userData}.
%   blocks{k}: {Theta,Phi,Re_Eth,Im_Eth,Re_Eph,Im_Eph} (E-field) or {Theta,Phi,<gain columns>} (gain-only).
%   userData : source (label), isGainOnly, isCoverage, isDep (multi-block / frequency dependent).
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.')); fmt = string(fmt);
assert(ismember(ext, {'XLSX', 'XLS', 'CSV', 'TXT', 'DAT', 'CUT', 'FZ', 'UAN', 'OUT', 'FFS', 'FFE', 'FFD'}), 'readPattern:unsupported', 'Unsupported format: %s', ext);
ud = struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false);
out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, 'userData', ud);
canon = @(th, ph, Eth, Eph) table(th(:), ph(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
fromCircular = @(Er, El) deal((Er + El)/sqrt(2), (Er - El)/(1i*sqrt(2)));
switch ext
    case {'XLSX', 'XLS'}
        out = readExcelMatrix(fp, canon, fromCircular);
    case {'CSV', 'TXT', 'DAT'}
        out = readGenericText(fp, fmt, cached, out, canon, fromCircular);
    case 'CUT'   % TICRA/GRASP: repeated blocks [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data]
        L = readlines(fp); L(strlength(strtrim(L)) == 0) = []; [th, ph, D] = deal({}); i = 1;
        while i < numel(L)
            p = sscanf(L(i+1), '%f'); assert(numel(p) >= 7, 'readPattern:cut', 'Could not parse a GRASP cut parameter line.'); n = p(3);
            D{end+1, 1} = reshape(sscanf(strjoin(L(i+2:i+1+n), ' '), '%f'), 2*p(7), []).'; %#ok<AGROW>
            th{end+1, 1} = p(1) + (0:n-1)'*p(2); ph{end+1, 1} = repmat(p(4), n, 1); i = i + 2 + n; %#ok<AGROW>
        end
        th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:}); D = D(:, 1:4);
        if p(6) == 2, [th, ph] = deal(ph, th); end                          % ICUT=2: φ swept at constant θ
        neg = th < 0; th(neg) = -th(neg); ph(neg) = ph(neg) + 180;           % fold negative θ onto the opposite half-plane
        if isscalar(unique(ph)), m = numel(th); th = repmat(th, 36, 1); ph = repelem((0:10:350)', m); D = repmat(D, 36, 1); end   % body of revolution
        A = complex(D(:, 1), D(:, 2)); B = complex(D(:, 3), D(:, 4));
        if p(5) == 2, names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; [Eth, Eph] = fromCircular(A, B); else, names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; Eth = A; Eph = B; end
        out.userData.source = 'TICRA/GRASP CUT'; out.rawTbl = array2table([th ph D], 'VariableNames', [{'Theta', 'Phi'} names]); out.blocks = {canon(th, ph, Eth, Eph)};
    otherwise    % numeric far-field tables (6 columns) with an optional HFSS FFD header
        [nHdr, ffd] = findHeader(fp);
        opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
        M = readmatrix(fp, setvartype(opts, opts.VariableNames, 'double')); M = M(~all(isnan(M), 2), 1:min(end, 6));
        th = M(:, 1); ph = M(:, 2);
        switch ext
            case {'FZ', 'UAN'}   % Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
                ud.source = ['XGTD ' ext]; names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'};
                Eth = 10.^(M(:, 3)/20).*exp(1i*deg2rad(M(:, 5))); Eph = 10.^(M(:, 4)/20).*exp(1i*deg2rad(M(:, 6)));
            case 'OUT'           % Theta Phi Re/Im POL1(RHCP) Re/Im POL2(LHCP)
                ud.source = 'TICRA/GRASP OUT'; names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'};
                [Eth, Eph] = fromCircular(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)));
            case 'FFS'           % Phi Theta Re/Im Eth Re/Im Eph
                ud.source = 'CST FFS'; names = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'};
                Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6)); th = M(:, 2); ph = M(:, 1);
            case 'FFE'           % Theta Phi Re/Im Eth Re/Im Eph (extra columns ignored)
                ud.source = 'FEKO FFE'; names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'};
                Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
            case 'FFD'           % HFSS: header θ/φ triples; rows Re/Im Eth Re/Im Eph; optional "Frequency f" separator rows
                assert(ffd.isFFD, 'readPattern:ffd', 'FFD header (theta/phi ranges) not found.'); ud.source = 'HFSS FFD';
                tA = linspace(ffd.theta(1), ffd.theta(2), ffd.theta(3))'; pA = linspace(ffd.phi(1), ffd.phi(2), ffd.phi(3))';
                th = repelem(tA, numel(pA)); ph = repmat(pA, numel(tA), 1); sep = isnan(M(:, 1)); F = M(~sep, 1:4);
                freqs = [ffd.freq(:); M(sep, 2)]; freqs = freqs(isfinite(freqs))'; n = numel(th);
                assert(mod(size(F, 1), n) == 0, 'readPattern:ffd', 'FFD row count does not match the theta/phi grid.');
                nb = size(F, 1)/n; ud.isDep = nb > 1 || ~isempty(freqs); freqs(end+1:nb) = NaN; freqs = freqs(1:nb);
                out.blocks = arrayfun(@(b) canon(th, ph, complex(F((b-1)*n + (1:n), 1), F((b-1)*n + (1:n), 2)), complex(F((b-1)*n + (1:n), 3), F((b-1)*n + (1:n), 4))), 1:nb, 'UniformOutput', false);
                out.rawTbl = out.blocks{1}; out.freqs = freqs; names = {};
            otherwise, error('readPattern:unsupported', 'Unsupported format: %s', ext);
        end
        if ~isempty(names), out.rawTbl = array2table(M(:, 1:6), 'VariableNames', names); out.blocks = {canon(th, ph, Eth, Eph)}; end
        out.userData = ud;
end
for f = fieldnames(ud)', if ~isfield(out.userData, f{1}), out.userData.(f{1}) = ud.(f{1}); end, end
end

function [nHdr, ffd] = findHeader(fp)
%FINDHEADER Number of leading non-data lines; detects the HFSS FFD header (two θ/φ triples [+ "Frequencies ..."]).
ffd = struct('isFFD', false, 'theta', [], 'phi', [], 'freq', []); nHdr = 0;
fid = fopen(fp, 'r'); assert(fid > 0, 'readPattern:open', 'Cannot open file: %s', fp); c = onCleanup(@() fclose(fid)); %#ok<NASGU>
lines = strings(0, 1);
for k = 1:64, s = fgetl(fid); if ~ischar(s), break; end, lines(end+1, 1) = strtrim(string(s)); end %#ok<AGROW>
nums = arrayfun(@(s) {sscanf(regexprep(char(s), '[,;\t]', ' '), '%f')}, lines); counts = cellfun(@numel, nums); nonEmpty = find(strlength(lines) > 0);
if numel(nonEmpty) >= 2 && all(counts(nonEmpty(1:2)) == 3)
    t = nums{nonEmpty(1)}; p = nums{nonEmpty(2)}; nHdr = nonEmpty(2);
    ffd = struct('isFFD', all(isfinite([t; p])) && t(3) >= 1 && p(3) >= 1, 'theta', [t(1) t(2) round(t(3))], 'phi', [p(1) p(2) round(p(3))], 'freq', []);
    if numel(nonEmpty) >= 3
        tok = regexp(char(lines(nonEmpty(3))), '^frequenc(y|ies)\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok), nHdr = nonEmpty(3); f = sscanf(char(tok{2}), '%f'); if numel(f) > 1, ffd.freq = f(:); end, end   % a lone count is only metadata
    end
    return
end
first = find(counts >= 4, 1); if ~isempty(first), nHdr = first - 1; end
end

function out = readGenericText(fp, fmt, cached, out, canon, fromCircular)
%READGENERICTEXT CSV/TXT/DAT: coverage-results table, gain-only pattern, or a 6-column E-field layout chosen by FMT.
if isempty(cached)
    opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
    cached = rmmissing(readtable(fp, opts));
end
T = cached; n = width(T); assert(n >= 2 && ~isempty(T), 'readPattern:generic', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHeaders = ~all(startsWith(names, "Var")); c1 = T{:, 1}; c2 = T{:, 2};
covHeader = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));   % detect coverage results first
if (fmt == "gain" || n < 6 || covHeader) && all(isfinite(c2)) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:n-1))]; end
    out.rawTbl = T; out.userData.isCoverage = true; return
end
if fmt == "gain"     % the wider-spanning of the first two columns is φ
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    T = movevars(T, 'Theta', 'Before', 1); out.blocks = {T}; out.userData.isGainOnly = true;
    if hasHeaders, out.rawTbl = cached; else, out.rawTbl = T; end, return
end
assert(n >= 6, 'readPattern:generic', 'The selected E-field format requires six numeric columns.');
V = T{:, 3:6}; magPhase = endsWith(fmt, "magphase"); layout = "n/a";
if magPhase          % (mag,phase,mag,phase) interleaved vs (mag,mag,phase,phase) grouped: phases exceed 100
    big = max(abs(V), [], 1, 'omitnan') > 100;
    if big(2) && ~big(3), m = [1 3]; p = [2 4]; layout = "interleaved"; else, m = [1 2]; p = [3 4]; layout = "grouped"; end
    A = 10.^(V(:, m(1))/20).*exp(1i*deg2rad(V(:, p(1)))); B = 10.^(V(:, m(2))/20).*exp(1i*deg2rad(V(:, p(2))));
else
    A = complex(V(:, 1), V(:, 2)); B = complex(V(:, 3), V(:, 4));
end
if startsWith(fmt, "linear"), Eth = A; Eph = B; tags = ["E_TH", "E_PH"];
elseif startsWith(fmt, "rcp"), [Eth, Eph] = fromCircular(A, B); tags = ["POL1", "POL2"];
else, [Eth, Eph] = fromCircular(B, A); tags = ["POL1", "POL2"]; end
if magPhase, cols = [tags + "_dB", tags + "_deg"]; if layout == "interleaved", cols = cols([1 3 2 4]); end
elseif startsWith(fmt, "linear"), cols = ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"];
else, cols = [tags(1) + ["_real", "_imag"], tags(2) + ["_real", "_imag"]]; end
if ~hasHeaders, T.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", cols]); end
out.userData.source = sprintf('Generic text (%s, %s)', fmt, layout); out.rawTbl = T; out.blocks = {canon(T{:, 1}, T{:, 2}, Eth, Eph)};
end

function out = readExcelMatrix(fp, canon, fromCircular)
%READEXCELMATRIX Matrix-template workbooks: sheet 1 = summary; fixed component sheets hold dBi magnitude / degree phase.
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"]; lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'readPattern:excel', 'Unsupported workbook: expected the fixed Etheta/Ephi and/or RHCP/LHCP component sheets.');
required = [circ(1:4*hasC), lin(1:4*hasL)]; M = struct(); ref = {};
for name = required
    [th, ph, D] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, name), 1)));
    if isempty(ref), ref = {th, ph};
    else, assert(isequal(size(th), size(ref{1})) && isequal(size(ph), size(ref{2})) && max(abs(th - ref{1})) < 1e-9 && max(abs(ph - ref{2})) < 1e-9, ...
            'readPattern:excel', 'All component sheets must share one theta/phi grid.'); end
    M.(name) = D;
end
field = @(g, p) 10.^(M.(g)/20).*exp(1i*deg2rad(M.(p)));
if hasL, Eth = field("Etheta_Gain_dBi", "Etheta_Phase_degrees"); Eph = field("Ephi_Gain_dBi", "Ephi_Phase_degrees");
else, [Eth, Eph] = fromCircular(field("RHCP_Gain_dBi", "RHCP_Phase_degrees"), field("LHCP_Gain_dBi", "LHCP_Phase_degrees")); end
[phG, thG] = meshgrid(ref{2}, ref{1}); raw = canon(thG, phG, Eth, Eph);
for name = required, raw.(name) = reshape(M.(name), [], 1); end
kind = ["Format 2 (Ercp/Elcp)", "Format 1 (Eth/Eph)", "Format 3 (Ercp/Elcp + Eth/Eph)"];
ud = struct('source', char("Excel Matrix " + kind(hasC + 2*hasL)), 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'summary', readSummary(fp, sheets(1)));
out = struct('rawTbl', raw, 'blocks', {{raw(:, 1:6)}}, 'freqs', NaN, 'userData', ud);
end

function [th, ph, D] = readMatrixSheet(fp, sheet)
%READMATRIXSHEET C3-origin matrix: row 2 = φ axis (C→), column B = θ axis (3↓). readcell preserves sheet coordinates.
C = readcell(fp, 'Sheet', char(sheet)); assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'readPattern:excel', 'Sheet "%s" has no C3-origin matrix.', sheet);
isNum = @(c) cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), c); pm = isNum(C(2, 3:end)); tm = isNum(C(3:end, 2));
assert(any(pm) && any(tm) && all(pm(1:find(pm, 1, 'last'))) && all(tm(1:find(tm, 1, 'last'))), 'readPattern:excel', 'Sheet "%s": theta/phi axes missing or not contiguous.', sheet);
ph = cell2mat(C(2, 2 + (1:nnz(pm)))); th = cell2mat(C(2 + (1:nnz(tm)), 2)); cells = C(2 + (1:nnz(tm)), 2 + (1:nnz(pm)));
assert(all(isNum(cells), 'all'), 'readPattern:excel', 'Sheet "%s" contains non-numeric matrix samples.', sheet); D = cell2mat(cells);
assert(all(diff(th) > 0) && all(diff(ph) > 0) && th(1) >= -1e-9 && th(end) <= 180 + 1e-9 && ph(1) >= -1e-9 && ph(end) < 360 + 1e-9, ...
    'readPattern:excel', 'Sheet "%s": axes must be strictly increasing within θ 0..180, φ 0..360.', sheet);
end

function s = readSummary(fp, sheet)
%READSUMMARY Summary sheet as a label→value struct (labels in column B, first value in C..E); frequency normalized.
s = struct(); try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
for r = 1:size(C, 1)
    lbl = C{r, 2}; if ~(ischar(lbl) || isstring(lbl)) || strlength(strtrim(string(lbl))) == 0, continue; end
    v = C(r, 3:min(end, 5)); v = v(~cellfun(@(x) isempty(x) || isa(x, 'missing'), v)); if isempty(v), continue; end
    s.(matlab.lang.makeValidName(lower(regexprep(char(lbl), '[^a-zA-Z0-9]+', '_')))) = v{1};
end
key = fieldnames(s); key = key(contains(key, 'simulation_freq'));
if ~isempty(key) && isnumeric(s.(key{1})), s.frequencyMHz = double(s.(key{1})); end
end

%% ========================================================================= numeric core (pure, physical angles)
function T = normalizePattern(T)
%NORMALIZEPATTERN Map any angular convention onto the canonical sphere: θ∈[0,180], φ∈[0,360) plus one closing φ=360 copy.
th = T.Theta; ph = T.Phi;
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, th = 90 - th;                          % elevation convention
    else, neg = th < 0; th(neg) = -th(neg); ph(neg) = ph(neg) + 180; end         % signed polar angle
end
th = mod(th, 360); over = th > 180; th(over) = 360 - th(over); ph(over) = ph(over) + 180;
T.Theta = round(th, 6); T.Phi = mod(round(mod(ph, 360), 6), 360);               % round ANGLES only; data columns are untouched
[~, keep] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(keep, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function R = resampleCanonical(S, step)
%RESAMPLECANONICAL Resample a canonical source onto a regular STEP° grid (closing φ=360 included once).
%   E-field Re/Im columns are interpolated linearly; gain-only columns in linear power (dB → W → dB).
%   Regular grids use φ-periodic interp2; irregular samples use scatteredInterpolant. Uncovered targets → nearest.
th = S.Theta; ph = mod(S.Phi, 360); keep = find(isfinite(th) & isfinite(ph) & abs(S.Phi - 360) > 1e-9);
[~, u] = unique([th(keep) ph(keep)], 'rows', 'stable'); idx = keep(u); th = th(idx); ph = ph(idx);
[qPh, qTh] = meshgrid(unique([0:step:360, 360]), 0:step:180); R = table(qTh(:), qPh(:), 'VariableNames', {'Theta', 'Phi'});
uT = unique(th); uP = unique(ph); regular = numel(uT)*numel(uP) == numel(th);
if regular, [~, it] = ismember(th, uT); [~, ip] = ismember(ph, uP); lin = sub2ind([numel(uT) numel(uP)], it, ip); regular = numel(unique(lin)) == numel(lin); end
asPower = ~all(ismember(["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"], S.Properties.VariableNames));   % gain-only sources are dB power
for name = string(S.Properties.VariableNames(3:end))
    v = double(S.(name)(idx)); if asPower, v = 10.^(v/10); end
    if regular
        [PG, TG] = meshgrid([uP; uP(1) + 360], uT); G = nan(numel(uT), numel(uP)); G(lin) = v; G = [G, G(:, 1)];   % periodic φ column
        q = interp2(PG, TG, G, qPh, qTh, 'linear', NaN); miss = ~isfinite(q);
        if any(miss, 'all'), nn = interp2(PG, TG, G, qPh, qTh, 'nearest', NaN); q(miss) = nn(miss); end
    else
        F = scatteredInterpolant(ph, th, v, 'linear', 'nearest'); q = F(qPh, qTh);
    end
    if asPower, q = 10*log10(max(q, realmin)); end
    R.(name) = q(:);
end
R.Properties.UserData = S.Properties.UserData;
end

function [P, info] = calcPattern(S, prm, pct, excess)
%CALCPATTERN Canonical source → processed table. Gain-only: add loss. E-field: every derived quantity in one pass.
%   Columns: E_Total_dB, AR_dB (signed: + RHCP sense, − LHCP sense), E_RCP_dB, E_LCP_dB, PLF_dB, Gain_PolCorrected_dB,
%            E_TH_dB, E_PH_dB, four phases, EIRP_dBW, PFD_Wm2, E_RMS_Vm.
ud = S.Properties.UserData; info = struct('pol', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
if ud.isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + prm.GainLoss_dB; end
    info.peak = resolvePeak(P{:, 3}, pct, excess); return
end
Eth = complex(S.Re_Eth, S.Im_Eth)*prm.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph)*prm.FieldScale;
Er = (Eth + 1i*Eph)/sqrt(2); El = (Eth - 1i*Eph)/sqrt(2); [mT, mP, mR, mL] = deal(abs(Eth), abs(Eph), abs(Er), abs(El));
total = 10*log10(max(mT.^2 + mP.^2, eps)); info.peak = resolvePeak(total, pct, excess);
% Dominant polarization from mean component power → co/cross ordering, label and Auto-Rx sense
pw = [mean(mT.^2, 'omitnan'), mean(mP.^2, 'omitnan'), mean(mR.^2, 'omitnan'), mean(mL.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif pw(1) >= pw(2), info.pol = 'Linear (Vertical)'; else, info.pol = 'Linear (Horizontal)'; end
% Signed axial ratio; equal circular components (the linear limit) are shown at the −100 dB floor
d = mR - mL; sense = sign(d); sense(~isfinite(d)) = 0; ar = (mR + mL)./max(abs(d), eps);
arDB = min(20*log10(ar), 250).*sense; arDB(isfinite(d) & abs(d) <= eps*max(mR + mL, 1)) = -100;
% Polarization loss factor against an incident wave of axial ratio RxAR_dB and sense RxMode (Auto = antenna sense)
switch prm.RxMode, case "RHCP", ws = 1; case "LHCP", ws = -1; otherwise, ws = 2*(info.pairs.Circular(1) == "E_RCP") - 1; end
ra = ar.*sense; ra(sense == 0) = 1e12; rw = ws*10^(prm.RxAR_dB/20);
plf = 10*log10(min(max(0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1))./(2*(ra.^2 + 1)*(rw^2 + 1)), eps), 1));
eirp = prm.Pt_dBW + total; eirpW = 10.^(eirp/10); dB = @(m) 20*log10(max(m, eps)); deg = @(z) rad2deg(angle(z));
P = table(S.Theta, S.Phi, total, arDB, dB(mR), dB(mL), plf, total + plf, dB(mT), dB(mP), deg(Eth), deg(Eph), deg(Er), deg(El), ...
    eirp, eirpW/(4*pi*prm.R_m^2), sqrt(30*eirpW)/prm.R_m, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', ...
    'PLF_dB', 'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
P.Properties.UserData = ud;
end

function info = resolvePeak(values, pct, maxExcess)
%RESOLVEPEAK Peak policy: accept the raw maximum unless it exceeds the P<pct> level by more than MAXEXCESS dB;
%   otherwise the highest sample at/below that level is the effective peak and the samples above it are outliers.
values = double(values(:)); finite = isfinite(values);
info = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(values)), 'wasAdjusted', false);
if ~any(finite), return; end
[info.rawValue, info.rawIndex] = max(values, [], 'omitnan'); info.value = info.rawValue; info.index = info.rawIndex;
level = percentileOf(values(finite), pct);
if info.rawValue > level + maxExcess
    outliers = finite & values > level;
    if any(finite & ~outliers)
        cand = values; cand(~finite | outliers) = -Inf; [info.value, info.index] = max(cand); info.outlierMask = outliers; info.wasAdjusted = true;
    end
end
end

function p = percentileOf(v, pct)
%PERCENTILEOF prctile-compatible percentile (midpoint plotting positions, linear interpolation) without any toolbox.
s = sort(v(:)); n = numel(s);
if n == 0, p = NaN; elseif n == 1, p = s; else, q = 100*((1:n)' - 0.5)/n; p = interp1(q, s, min(max(pct, q(1)), q(end)), 'linear'); end
end

function dW = solidWeights(theta, phi)
%SOLIDWEIGHTS Exact solid angle of each sample's grid cell; the duplicated closing φ seam (360, or 180 when signed) gets zero weight.
ts = gridStep(theta); ps = gridStep(mod(phi, 360)); if ~isfinite(ts), ts = 180; end, if ~isfinite(ps), ps = 360; end
dW = (cosd(max(theta - ts/2, 0)) - cosd(min(theta + ts/2, 180)))*deg2rad(ps);
seam = 360 - 180*any(phi < 0); dW(abs(phi - seam) < 1e-9) = 0;
end

function s = gridStep(v)
%GRIDSTEP Smallest positive spacing between distinct finite values (NaN when undefined).
d = diff(unique(v(isfinite(v)))); d = d(d > 1e-9); s = NaN; if ~isempty(d), s = min(d); end
end

function g = chooseGain(T, requested)
%CHOOSEGAIN Column REQUESTED when present, else E_Total_dB, else the first data column.
names = T.Properties.VariableNames; c = char(requested);
if ~ismember(c, names), c = 'E_Total_dB'; end, if ~ismember(c, names), c = names{3}; end
g = T.(c);
end

function [peak, axisIndex] = calcOrientation(theta, phi, gainDB, dOmega, axes6, pct, excess)
%CALCORIENTATION Peak of GAINDB (peak policy) and the principal axis whose 45° cone captures the most weighted power.
peak = resolvePeak(gainDB, pct, excess); g = double(gainDB(:)); if peak.wasAdjusted, g(peak.outlierMask) = NaN; end
w = 10.^((g - peak.value)/10).*dOmega(:); w(~isfinite(w)) = 0;
A = [sind(axes6.theta(:)).*cosd(axes6.phi(:)), sind(axes6.theta(:)).*sind(axes6.phi(:)), cosd(axes6.theta(:))];
V = [sind(theta(:)).*cosd(phi(:)), sind(theta(:)).*sind(phi(:)), cosd(theta(:))];
[~, axisIndex] = max(w.'*double(V*A.' >= cosd(45)));
end

function m = calcMetrics(theta, phi, gainDB, dOmega, peak, axes6, axisIndex, arDB)
%CALCMETRICS Directivity, efficiency, front-to-back, E/H-plane HPBW and AR at the peak — all from PHYSICAL angles.
g = double(gainDB(:)); if peak.wasAdjusted, g(peak.outlierMask) = NaN; end
integ = sum(10.^(g/10).*dOmega(:), 'omitnan'); k = peak.index;
[~, kb] = min(cosd(theta).*cosd(theta(k)) + sind(theta).*sind(theta(k)).*cosd(phi - phi(k)));   % antipode of the peak
if axes6.theta(axisIndex) == 90, hType = "Phi"; else, hType = "Theta"; end   % H-plane: φ-cut at θ=90° for transverse axes, else θ-cut at φ=90°
[eAng, eRows] = calcCutGeometry(theta, phi, theta, phi, "Theta", axes6.phi(axisIndex));
[hAng, hRows] = calcCutGeometry(theta, phi, theta, phi, hType, 90);
eff = 100*integ/(4*pi); if eff < 0 || eff > 100, eff = NaN; end
m = struct('PeakGain_dB', peak.value, 'PeakTheta_deg', theta(k), 'PeakPhi_deg', phi(k), ...
    'HPBW_EPlane_deg', calcHPBW(eAng, gainDB(eRows)), 'HPBW_HPlane_deg', calcHPBW(hAng, gainDB(hRows)), 'FrontBack_dB', peak.value - gainDB(kb), ...
    'PeakDirectivity_dB', 10*log10(max(4*pi*10^(peak.value/10)/max(integ, eps), eps)), 'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', arDB(k));
end

function [ang, rows, fixed, sym, snapped] = calcCutGeometry(dispTheta, dispPhi, theta, phi, type, request)
%CALCCUTGEOMETRY Rows and sweep angle of one closed cut.
%   "Phi"  : fixed θ (nearest DISPTHETA value), sweep DISPPHI as given.
%   "Theta": fixed φ (nearest physical φ), sweep physical θ 0→180 on that half-plane, then 180→360 on the opposite one.
if type == "Phi"
    vals = unique(dispTheta); [d, k] = min(abs(vals - request)); fixed = vals(k); sym = 'θ';
    rows = find(abs(dispTheta - fixed) < 1e-9); [ang, o] = sort(dispPhi(rows)); rows = rows(o);
else
    request = mod(request, 360); vals = unique(phi); sym = 'φ';
    [d, k] = min(abs(mod(vals - request + 180, 360) - 180)); fixed = vals(k);
    [~, k2] = min(abs(mod(vals - fixed, 360) - 180)); opposite = vals(k2);
    p = find(abs(phi - fixed) < 1e-9); q = find(abs(phi - opposite) < 1e-9 & abs(theta - 180) > 1e-9);
    [~, o1] = sort(theta(p)); [~, o2] = sort(theta(q), 'descend'); p = p(o1); q = q(o2);
    rows = [p; q]; ang = [theta(p); 360 - theta(q)];
end
snapped = d > 1e-9;
end

function [bw, lo, hi] = calcHPBW(ang, g, pk, pkAng)
%CALCHPBW Half-power beamwidth of one closed cut with linearly interpolated −3 dB crossings (wrap-aware).
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(g); ang = ang(ok); g = g(ok); if numel(g) < 3, return; end
if nargin < 3 || isempty(pk), [pk, i] = max(g); pkAng = ang(i); end
[rel, o] = sort(mod(ang - pkAng + 180, 360) - 180); g = g(o); hp = pk - 3;
L = find(rel < 0 & g <= hp, 1, 'last'); Rr = find(rel > 0 & g <= hp, 1, 'first');
if isempty(L) || isempty(Rr) || L + 1 > numel(g) || Rr < 2 || g(L+1) == g(L) || g(Rr-1) == g(Rr), return; end
cross = @(a, b) rel(a) + (rel(b) - rel(a))*(hp - g(a))/(g(b) - g(a));
lo = pkAng + cross(L, L+1); hi = pkAng + cross(Rr, Rr-1); bw = hi - lo;
end

function cov = coverageCCDF(gain, mask, thr, dOmega)
%COVERAGECCDF Coverage(T) [%] = 100·Σ I(G_i > T)·Ω_i / Σ Ω_i over the region MASK, evaluated for every threshold at once.
ok = mask(:) & isfinite(gain(:)) & isfinite(dOmega(:)) & dOmega(:) >= 0; g = double(gain(ok)); w = double(dOmega(ok)); thr = double(thr(:));
cov = zeros(size(thr)); if isempty(g) || sum(w) <= 0, return; end
cov = 100*(w.'*(g > thr.')).'/sum(w);
end

function v = gridValue(D, row, col, prefer)
%GRIDVALUE Value of surface data D at grid cell (row,col); D may be the full matrix or a single axis vector.
if isempty(D), v = 0;
elseif ~isvector(D), v = D(min(row, end), min(col, end));
elseif prefer == "col", v = D(min(col, end));
else, v = D(min(row, end)); end
end