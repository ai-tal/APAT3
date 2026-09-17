classdef APAT_v3_M8_32 < matlab.apps.AppBase  %1836-lines 
% APAT v3 M8 — Antenna Pattern Analyzer Tool.
%
% M8 is a structural rewrite of M7.110_5 with identical numerical policies and
% file-format contracts.  Architecture:
%   source (readPattern) -> stdTbl (normalizePattern) -> patTbl (calcPattern)
%   -> viewBaseTbl (step)  -> viewTbl (angular conventions) -> derived view state
%   -> lazily rendered plots.
% One range controller (setRange), one annotation registry (annots), one
% callback error boundary (cb/guarded), one progress/perf wrapper (runOp) and a
% declarative UI builder (add/addLabel) replace the parallel mechanisms of M7.
% See APAT_M8_CHANGES.md for the full change log.

    properties (Access = public)
        UIFigure matlab.ui.Figure
        UI struct = struct()          % every widget handle, keyed by a short name (app.UI.loadBtn, ...)
    end

    properties (SetAccess = private)
        isClosing logical = false
    end

    properties (Access = private)
        % --- source and pipeline tables ------------------------------------------------
        src struct = struct('path','','name','','base','','folder','','rawTbl',table(),'blocks',{{}},'freqs',NaN,'meta',struct())
        stdTbl table                  % canonical block: {Theta,Phi,Re_Eth,Im_Eth,Re_Eph,Im_Eph} or {Theta,Phi,<gain cols>}
        patTbl table                  % processed pattern at native resolution
        viewBaseTbl table             % processed pattern at the selected step (θ 0..180, φ 0..360)
        viewTbl table                 % display/export table in the selected angular conventions
        uanTbl table                  % lazily built UAN export table
        % --- derived view state ----------------------------------------------------------
        view struct = struct('rev',0,'grid',[],'solidAngle',[],'peak',struct(),'POB',NaN,'POBth',NaN,'POBph',NaN, ...
            'boresight',1,'metrics',struct(),'pol','n/a','pairs',struct('Linear',["E_TH","E_PH"],'Circular',["E_RCP","E_LCP"]))
        lim struct = struct('gain',[-40 10],'full',[-40 10],'cut',[-40 10])   % gain = authoritative non-AR color scale
        dirty logical = true(1,5)     % lazy full-pattern render flags (one per tab)
        annots cell = {}              % annotation sources (lines/surfaces carrying POB or HPBW records in UserData)
        rawShown logical = false
        defaults struct = struct()
        cov struct = struct('runID',0,'presetKey',"",'thrInit',false,'plotInit',false)
        % --- lifecycle helpers -----------------------------------------------------------
        statusTimer = []
        opDialog = []
        perf struct = struct('stages',{cell(0,2)},'t',[],'t0',[])
        filterStyles cell = {}
    end

    properties (Constant, Access = private)
        Axes = struct('labels',{{'+Z','-Z','+X','-X','+Y','-Y'}},'theta',[0 180 90 90 90 90],'phi',[0 0 0 180 90 270])
        Peak = struct('percentile',99.99,'maxExcessDB',6)     % isolated-spike peak policy (P99.99 + 6 dB)
        RangeBounds = [-250 100]
        ARLimits = [-30 30]
        HiddenColumns = {'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'}
        ComponentNames = ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","AR_dB","Gain_PolCorrected_dB"]
        ComponentLabels = ["Total Gain","Etheta Gain","Ephi Gain","RHCP Gain","LHCP Gain","Axial Ratio","Polarized Gain"]
        FullNames = ["contour","circular","sphere","polar","rect3d"]
        Views3D = struct('top',{{0,90,[0 1 0]}},'bottom',{{0,-90,[0 1 0]}},'right',{{90,0,[0 0 1]}},'left',{{-90,0,[0 0 1]}},'front',{{0,0,[0 0 1]}},'back',{{180,0,[0 0 1]}})
        TableFilters = {'*.csv','Comma-delimited text (*.csv)';'*.txt','Tab-delimited text (*.txt)';'*.xlsx','Excel (*.xlsx)'}
        TextFormatArgs = {'Items', {'1: Gain Pattern','2: Etheta/Ephi — dB magnitude, phase','3: Etheta/Ephi — real, imaginary', ...
            '4: POL1=RCP, POL2=LCP — dB magnitude, phase','5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
            '6: POL1=RCP, POL2=LCP — real, imaginary','7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
            'ItemsData', {'gain','linear_magphase','linear_reim','rcp_lcp_magphase','lcp_rcp_magphase','rcp_lcp_reim','lcp_rcp_reim'}, ...
            'Value', 'gain', 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.'}
        Release = 'APAT v3 M8'
    end

    %% ================================================================ lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_32
            app.createComponents();
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @startup);
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true;
            app.stopStatusTimer();
            if ~isempty(app.opDialog) && isvalid(app.opDialog), delete(app.opDialog); end
            if ~isempty(app.UIFigure) && isgraphics(app.UIFigure), delete(app.UIFigure); end
        end
    end

    methods (Access = private)
        function startup(app)
            u = app.UI;
            % Polar axes have no layout-builder constructor; attach them to their grids here.
            app.UI.paxCut = polaraxes(u.polarGrid); place(app.UI.paxCut, [1 4], 3);
            app.UI.paxPattern = polaraxes(u.full(2).grid); place(app.UI.paxPattern, [1 3], 2);
            app.UI.full(2).axes = app.UI.paxPattern;
            set([app.UI.paxCut app.UI.paxPattern], 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            for k = [1 3 4 5], app.setInteraction(app.UI.full(k).axes, k >= 3); end
            app.setInteraction(u.axesRect, false);
            hold(u.covAxes, 'on'); grid(u.covAxes, 'on'); ylim(u.covAxes, [0 100]); set(u.covAxes, 'Box', 'on', 'Layer', 'top');
            for n = ["loss","rxPol","rw","pt","ptUnit","dist","distUnit"], app.defaults.(n) = u.(n).Value; end
            app.setCoverageUI();
            app.status("main", 'Ready -- load an antenna pattern file to begin 🚀');
            app.status("cov", 'Ready 🚀');
        end

        function f = cb(app, fn)
            % Wrap a UI callback so every entry point shares one error boundary.
            f = @(s, e) app.guarded(fn, s, e);
        end

        function guarded(app, fn, s, e)
            if app.isClosing, return; end
            try
                fn(s, e);
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.status("main", 'Operation cancelled by user.', true);
                else, app.showError(ME); end
            end
        end

        function showError(app, ME, titleText)
            if nargin < 3, titleText = 'APAT Error'; end
            if app.isClosing || ~isvalid(app.UIFigure), return; end
            where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.UIFigure, [ME.message where], titleText, 'Icon', 'error');
        end

        function runOp(app, title, message, fn, cancelable)
            % Run FN behind a progress dialog with optional cancel support; stage timings go to Perf_APAT_M8.
            if nargin < 5, cancelable = false; end
            dlg = uiprogressdlg(app.UIFigure, 'Title', title, 'Message', message, 'Indeterminate', 'on', 'Cancelable', cancelable, 'CancelText', 'Abort');
            app.opDialog = dlg; app.perf = struct('stages', {cell(0,2)}, 't', tic, 't0', tic); drawnow;
            cleaner = onCleanup(@() app.endOp(dlg, title)); %#ok<NASGU>
            fn();
        end

        function endOp(app, dlg, title)
            if isvalid(dlg), close(dlg); end
            app.opDialog = [];
            if app.isClosing || isempty(app.perf.t), return; end
            report = struct('Operation', string(title), 'Stages', cell2table(app.perf.stages, 'VariableNames', {'Stage','Seconds'}), 'TotalSeconds', toc(app.perf.t0));
            assignin('base', 'Perf_APAT_M8', report); app.perf.t = [];
        end

        function mark(app, stage)
            % Record one pipeline stage and honour a pending cancel request.
            if ~isempty(app.perf.t), app.perf.stages(end+1, :) = {string(stage), toc(app.perf.t)}; app.perf.t = tic; end
            d = app.opDialog;
            if ~isempty(d) && isvalid(d) && d.CancelRequested
                d.Message = 'Aborting...'; drawnow limitrate
                error('APAT:Cancelled', 'Operation cancelled by user.');
            end
        end

        function status(app, which, message, temporary)
            % which = "main" | "cov".  Temporary messages revert to the persistent one after 3 s.
            if app.isClosing, return; end
            if nargin < 4, temporary = false; end
            label = app.UI.status; if which == "cov", label = app.UI.covStatus; end
            app.stopStatusTimer(); label.Text = char(message);
            if ~temporary, label.UserData = label.Text; return; end
            app.statusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, 'TimerFcn', @(~,~) app.restoreStatus(label), 'StopFcn', @(t,~) delete(t));
            start(app.statusTimer);
        end

        function restoreStatus(app, label)
            if ~app.isClosing && isgraphics(label), label.Text = label.UserData; end
        end

        function stopStatusTimer(app)
            t = app.statusTimer; app.statusTimer = [];
            if ~isempty(t) && isvalid(t), stop(t); end
            if ~isempty(t) && isvalid(t), delete(t); end
        end

        function setInteraction(app, ax, is3D)
            enableDefaultInteractivity(ax);
            if is3D, ax.Interactions = [rotateInteraction dataTipInteraction]; else, ax.Interactions = [zoomInteraction dataTipInteraction]; end
            menu = uicontextmenu(app.UIFigure);
            uimenu(menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~,~) delete(findall(ax, 'Type', 'datatip')));
            ax.ContextMenu = menu;
        end

        function attachContextMenu(~, ax)
            % Re-attach the axes' own context menu to freshly rendered children (one menu per axes, never leaked).
            if isprop(ax, 'ContextMenu') && ~isempty(ax.ContextMenu), set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', ax.ContextMenu); end
        end

        %% ================================================================ pipeline
        function onLoad(app)
            fp = strtrim(app.UI.path.Value);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.src.path)
                fp = app.browse('Select an antenna pattern file'); if isempty(fp), return; end
                app.UI.path.Value = fp;
            end
            app.runOp('Loading Data', 'Reading file...', @() app.loadFile(fp), true);
        end

        function fp = browse(app, prompt)
            % File picker that refuses to re-select the currently loaded Main file.
            filters = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage files'; '*.*', 'All files'};
            fp = '';
            while true
                [f, p] = uigetfile(filters, prompt); if isequal(f, 0), return; end
                if ~strcmp(fullfile(p, f), app.src.path), fp = fullfile(p, f); return; end
                choice = uiconfirm(app.UIFigure, sprintf('"%s" is already loaded.', f), 'File Already Loaded', 'Options', {'Select Another File','Cancel'}, 'DefaultOption', 1, 'CancelOption', 2);
                if strcmp(choice, 'Cancel'), return; end
            end
        end

        function loadFile(app, fp)
            u = app.UI; out = app.readSource(fp, u.fmtLabel, u.fmt, false); app.mark("Read file");
            if out.meta.isCoverage            % coverage-results table: route to the Coverage tab, Main state untouched
                u.path.Value = app.src.path; u.tabs.SelectedTab = u.covTab; u.covPath.Value = fp;
                app.covLoadResults(fp, out.rawTbl); return
            end
            app.src = out; app.src.path = fp; [app.src.folder, app.src.base, ext] = fileparts(fp); app.src.name = [app.src.base ext];
            if out.meta.isDep
                items = compose('Pattern %d: %.4g GHz', (1:numel(out.blocks))', out.freqs(:)/1e9);
                items(isnan(out.freqs(:))) = compose('Pattern %d', find(isnan(out.freqs(:))));
                u.ffd.Items = items; u.ffd.Value = items{1};
            end
            set([u.ffd u.ffdLabel], 'Visible', out.meta.isDep);
            u.step.UserData = false; u.basis.UserData = true;      % new source: native step, auto cut basis
            app.activateBlock(1); app.process();
        end

        function out = readSource(app, fp, fmtLabel, fmtDropdown, useSelected)
            % I/O boundary.  Generic text files expose the format selector (first read is always "gain");
            % every other format is self-describing.
            generic = isGenericText(fp); textFormat = "gain";
            if ~generic || useSelected, textFormat = string(fmtDropdown.Value); end
            out = readPattern(fp, textFormat);
            showSelector = generic && ~out.meta.isCoverage;
            set([fmtLabel fmtDropdown], 'Visible', showSelector);
            if showSelector && ~useSelected, fmtDropdown.Value = 'gain'; end
            app.mark("Parse source");
        end

        function activateBlock(app, k)
            % Select one canonical block (FFD files may hold one block per frequency) and standardize it.
            block = app.src.blocks{k};
            if app.src.meta.isDep, app.src.rawTbl = block; end
            app.rawShown = false;
            app.stdTbl = normalizePattern(block); app.stdTbl.Properties.UserData = app.src.meta;
        end

        function process(app)
            % Native-resolution processing and step selector, then a fresh view rebuild.
            u = app.UI; hasE = ~app.src.meta.isGainOnly;
            [app.patTbl, info] = calcPattern(app.stdTbl, app.getParam()); app.mark("Process pattern");
            app.view.pol = info.pol; app.view.pairs = info.pairs;
            if isequal(u.basis.UserData, true) && hasE
                if startsWith(info.pol, 'Linear'), u.basis.Value = 'Linear'; else, u.basis.Value = 'Circular'; end
            end
            [tStep, pStep] = deal(gridStep(app.patTbl.Theta), gridStep(mod(app.patTbl.Phi, 360)));
            if ~isfinite(tStep), tStep = 1; end, if ~isfinite(pStep), pStep = tStep; end
            nonCanonical = abs(tStep - 1) > 1e-9 || abs(pStep - 1) > 1e-9;
            u.step.Items = {sprintf('STEP: %g°', max(tStep, pStep))}; if nonCanonical, u.step.Items{2} = 'STEP: 1°'; end
            u.step.Value = u.step.Items{1 + (isequal(u.step.UserData, true) && nonCanonical)}; u.step.UserData = false;
            set(u.step, 'Visible', nonCanonical, 'Enable', nonCanonical);
            app.rebuildView(true, true);
            set([u.cutPanel u.exportBtn u.fullPanel u.ctrlPanel u.covBtn], 'Visible', 'on');
            set([u.exportUAN u.cutFieldGrid u.cbTotal u.cbCo u.cbCx], 'Visible', hasE); set([u.cbCo u.cbCx u.basis], 'Enable', hasE);
            pol = ''; if hasE, pol = [' | Polarization ' app.view.pol]; end
            app.status("main", sprintf('Pattern: %s | POB %s dB ( &theta;=%s&deg;, &phi;=%s&deg; )%s', app.src.name, fmt(app.view.POB, 2), fmt(app.view.POBth), fmt(app.view.POBph), pol));
        end

        function rebuildView(app, fresh, resetRanges)
            % viewBaseTbl (step) -> viewTbl (φ/θ conventions) -> derived state -> tables, cut and plots.
            u = app.UI; S = app.stdTbl;
            if strcmp(u.step.Value, 'STEP: 1°') && u.step.Enable == "on"     % only non-canonical sources expose the 1° option
                [tStep, pStep] = deal(gridStep(S.Theta), gridStep(mod(S.Phi, 360)));
                if isfinite(tStep) && isfinite(pStep) && tStep < 1 && pStep < 1     % integer samples exist: exact decimation
                    S = S(abs(S.Theta - round(S.Theta)) < 1e-9 & abs(S.Phi - round(S.Phi)) < 1e-9, :);
                else                                                                % otherwise resample the primitive fields
                    S = resampleCanonical(S, 1);
                end
                S.Properties.UserData = app.stdTbl.Properties.UserData;
            end
            if isequal(S.Theta, app.stdTbl.Theta) && isequal(S.Phi, app.stdTbl.Phi), app.viewBaseTbl = app.patTbl;
            else, app.viewBaseTbl = calcPattern(S, app.getParam()); end
            T = app.viewBaseTbl; signedPhi = app.isSignedPhi(); elev = app.isElev();
            if signedPhi
                T(abs(T.Phi - 360) <= 1e-9, :) = [];
                T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
                seam = T(abs(T.Phi - 180) < 1e-9, :); seam.Phi(:) = -180; T = [seam; T];
            end
            if elev, T.Theta = 90 - T.Theta; end
            meta = T.Properties.UserData; meta.thetaMode = 'polar'; if elev, meta.thetaMode = 'elevation'; end, T.Properties.UserData = meta;
            if signedPhi || elev, T = sortrows(T, {'Phi','Theta'}); end
            app.viewTbl = T; app.uanTbl = table(); app.view.rev = app.view.rev + 1; app.view.grid = []; app.view.solidAngle = [];
            app.mark("Prepare view");
            app.setComponentItems(u.component, T, string(u.component.Value));
            app.updateModel();
            if resetRanges, app.lim.gain = displayRange(chooseGain(T, 'E_Total_dB'), [-50 0], app.Peak); end
            app.applyTheme(); app.updateTables(); app.updateMetadata(); app.mark("Populate tables");
            if fresh, app.planeChanged(); else, app.updateCutControl(); app.cutChanged(); end
            app.invalidateFull(); app.mark("Build plots");
        end

        function updateModel(app)
            % Derived scalars for the selected component: solid angles, boresight axis, POB and metrics.
            T = app.viewTbl; theta = app.physTheta(T);
            if isempty(app.view.solidAngle), app.view.solidAngle = solidWeights(theta, T.Phi); end
            [~, peak, app.view.boresight] = calcOrientation(theta, T.Phi, chooseGain(T, app.comp()), app.view.solidAngle, app.Axes, app.Peak);
            app.view.peak = peak; app.view.POB = peak.value; app.view.POBth = theta(peak.index); app.view.POBph = mod(T.Phi(peak.index), 360);
            axes = app.Axes; axes.index = app.view.boresight;
            app.view.metrics = calcMetrics(T, theta, app.view.solidAngle, axes, app.Peak);
        end

        function p = getParam(app)
            u = app.UI;
            p = struct('GainLoss_dB', u.loss.Value, 'RxMode', string(u.rxPol.Value), 'RxAR_dB', u.rw.Value);
            p.FieldScale = 10^(p.GainLoss_dB/20);
            switch u.ptUnit.Value
                case 'dBm',   p.Pt_dBW = u.pt.Value - 30;
                case 'Watts', p.Pt_dBW = 10*log10(max(u.pt.Value, eps));
                otherwise,    p.Pt_dBW = u.pt.Value;
            end
            p.R_m = max(u.dist.Value, 1e-12) * (1 + 999*strcmp(u.distUnit.Value, 'km'));
        end

        function onProcess(app)
            if isempty(app.stdTbl), uialert(app.UIFigure, sprintf('No file!\nLoad a pattern first.'), 'Warning', 'Icon', 'warning'); return; end
            app.UI.step.UserData = strcmp(app.UI.step.Value, 'STEP: 1°');
            app.runOp('Processing', 'Re-processing pattern...', @() app.reprocess());
        end

        function reprocess(app)
            if isGenericText(app.src.path)     % generic text: reinterpret with the selected format
                out = app.readSource(app.src.path, app.UI.fmtLabel, app.UI.fmt, true);
                assert(~out.meta.isCoverage, 'The selected generic format identifies a coverage-results file.');
                [app.src.rawTbl, app.src.blocks, app.src.freqs, app.src.meta] = deal(out.rawTbl, out.blocks, out.freqs, out.meta);
                app.activateBlock(1);
            end
            app.process();
            app.status("main", ['Re-processed <b>' app.src.name '</b> with current parameters ✅'], true);
        end

        function formatChanged(app)
            if strcmp(strtrim(app.UI.path.Value), app.src.path) && isGenericText(app.src.path)
                app.UI.basis.UserData = true; app.onProcess();
            end
        end

        function ffdChanged(app)
            k = find(strcmp(app.UI.ffd.Items, app.UI.ffd.Value), 1);
            app.UI.basis.UserData = true; app.UI.step.UserData = strcmp(app.UI.step.Value, 'STEP: 1°');
            app.runOp('Processing', 'Switching frequency block...', @() app.switchBlock(k));
        end

        function switchBlock(app, k)
            app.activateBlock(k); app.process();
            app.status("main", sprintf('Switched to FFD block %d (%s).', k, app.UI.ffd.Value), true);
        end

        function stepChanged(app)
            app.runOp('Processing', 'Changing angular step...', @() app.rebuildView(false, true));
        end

        function spanChanged(app, src)
            if isempty(app.viewBaseTbl), return; end
            if src == app.UI.thetaSpan && strcmp(app.UI.cutType.Value, 'Phi')   % keep the same physical plane
                app.UI.cutValue.Limits = [-Inf Inf]; app.UI.cutValue.Value = 90 - app.UI.cutValue.Value;
            end
            app.rebuildView(false, false);
        end

        function componentChanged(app)
            app.updateModel(); app.updateMetadata(); app.applyTheme();
            if app.src.meta.isGainOnly, app.planeChanged(); else, app.plotCut(); end   % gain-only cuts follow the component
            app.invalidateFull();
        end

        function resetParams(app)
            for n = string(fieldnames(app.defaults))', app.UI.(n).Value = app.defaults.(n); end
            if ~isempty(app.stdTbl), app.onProcess(); end
        end

        %% ================================================================ view helpers
        function th = physTheta(~, T)
            % Physical polar θ regardless of the display convention stored with the table.
            th = T.Theta; m = T.Properties.UserData;
            if isstruct(m) && isfield(m, 'thetaMode') && strcmp(m.thetaMode, 'elevation'), th = 90 - th; end
        end
        function tf = isElev(app), tf = strcmp(app.UI.thetaSpan.Value, '-90° to 90°'); end
        function tf = isSignedPhi(app), tf = strcmp(app.UI.phiSpan.Value, '-180° to 180°'); end
        function c = comp(app), c = app.UI.component.Value; end

        function [cols, labels] = componentMap(app, T)
            cols = string(T.Properties.VariableNames(3:end)); labels = cols;
            if ~T.Properties.UserData.isGainOnly
                present = ismember(app.ComponentNames, cols); cols = app.ComponentNames(present); labels = app.ComponentLabels(present);
            end
        end

        function setComponentItems(app, dd, T, preferred)
            [cols, labels] = app.componentMap(T); if isempty(cols), return; end
            if ~any(cols == preferred), preferred = cols(1); if any(cols == "E_Total_dB"), preferred = "E_Total_dB"; end, end
            dd.Items = cellstr(labels); dd.ItemsData = cellstr(cols); dd.Value = char(preferred);
        end

        function s = compLabel(app)
            dd = app.UI.component; k = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(k), s = strrep(string(dd.Value), '_', ' '); else, s = string(dd.Items{k}); end
        end

        function tf = isAR(~, name)
            % AR semantics independent of column spelling: AR, AR_dB, AR dB, Axial Ratio, Axial_Ratio.
            key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', '');
            tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
        end

        function g = viewGrid(app)
            % Rectangular topology + geometry of the view table, cached per view revision.
            g = app.view.grid; if ~isempty(g), return; end
            T = app.viewTbl; theta = unique(T.Theta); phi = unique(T.Phi);
            [~, it] = ismember(T.Theta, theta); [~, ip] = ismember(T.Phi, phi); sz = [numel(theta) numel(phi)];
            g = struct('theta', theta, 'phi', phi, 'sz', sz, 'idx', sub2ind(sz, it, ip), 'comp', struct());
            [g.phiGrid, g.thetaGrid] = meshgrid(phi, theta);
            g.thetaPolar = g.thetaGrid; if app.isElev(), g.thetaPolar = 90 - g.thetaGrid; end
            g.phiRad = deg2rad(g.phiGrid); s = sind(g.thetaPolar);
            g.x = s.*cos(g.phiRad); g.y = s.*sin(g.phiRad); g.z = cosd(g.thetaPolar);
            app.view.grid = g;
        end

        function [g, C] = compGrid(app, name)
            g = app.viewGrid(); key = matlab.lang.makeValidName(name);
            if isfield(g.comp, key), C = g.comp.(key); return; end
            C = nan(g.sz); C(g.idx) = app.viewTbl.(name); app.view.grid.comp.(key) = C;
        end

        function updateTables(app)
            u = app.UI; cols = app.viewTbl.Properties.VariableNames(3:end);
            if ~app.rawShown
                set(u.tableIn, 'Data', app.src.rawTbl, 'ColumnName', app.src.rawTbl.Properties.VariableNames, 'Visible', 'on'); app.rawShown = true;
            end
            dd = u.outFilter; schemaChanged = ~isequal(regexprep(dd.Items(2:end), '^✓ ?', ''), cols);
            if schemaChanged
                dd.Items = [{'--- column filter ---'}, cols]; dd.ItemsData = 0:numel(cols);
                dd.UserData = ~ismember(cols, app.HiddenColumns); dd.Value = 0;
                set([dd u.tableOut u.dataTabs], 'Visible', 'on');
            end
            app.filterOutput(schemaChanged);
        end

        function filterOutput(app, restyle)
            % The output dropdown doubles as a multi-select column filter (✓ marks visible columns).
            dd = app.UI.outFilter;
            if dd.Value > 0, dd.UserData(dd.Value) = ~dd.UserData(dd.Value); dd.Value = 0; restyle = true; end
            if restyle
                if isempty(app.filterStyles), app.filterStyles = {uistyle('FontWeight', 'bold', 'BackgroundColor', [0.8 1 0.8]), uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9])}; end
                dd.Items = regexprep(dd.Items, '^✓ ?', ''); removeStyle(dd);
                on = find(dd.UserData) + 1; dd.Items(on) = append('✓ ', dd.Items(on));
                addStyle(dd, app.filterStyles{1}, 'Item', on); addStyle(dd, app.filterStyles{2}, 'Item', find([true, ~dd.UserData]));
            end
            app.UI.tableOut.Data = app.viewTbl(:, [true true dd.UserData]);
            app.updateParamVisibility();
        end

        function updateParamVisibility(app)
            % Link-budget inputs appear only when a column that depends on them is shown.
            u = app.UI; cols = app.viewTbl.Properties.VariableNames(3:end); shown = string(cols(u.outFilter.UserData));
            has = @(names) any(ismember(shown, names));
            set([u.rxPolLabel u.rxPol u.rwLabel u.rw], 'Visible', has(["PLF_dB","Gain_PolCorrected_dB"]));
            set([u.ptLabel u.pt u.ptUnit], 'Visible', has(["EIRP_dBW","PFD_Wm2","E_RMS_Vm"]));
            set([u.distLabel u.dist u.distUnit], 'Visible', has(["PFD_Wm2","E_RMS_Vm"]));
            set([u.lossLabel u.loss], 'Visible', app.src.meta.isGainOnly || has(["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","Gain_PolCorrected_dB","EIRP_dBW","PFD_Wm2","E_RMS_Vm"]));
        end

        function updateMetadata(app)
            T = app.viewTbl; v = app.view; m = v.metrics; meta = app.src.meta; [th, ph] = deal(unique(T.Theta), unique(T.Phi));
            rows = {'Source format', meta.source; 'File', app.src.name; ...
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(T), numel(th), numel(ph)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmt(min(th)), fmt(max(th)), fmt(gridStep(th))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmt(min(ph)), fmt(max(ph)), fmt(gridStep(ph)))};
            f = app.src.freqs(isfinite(app.src.freqs));
            if ~isempty(f), rows(end+1, :) = {'Frequencies', strjoin(compose('%.4g GHz', f(:)/1e9), ', ')}; end
            if ~meta.isGainOnly
                rows(end+1, :) = {'Polarization', v.pol};
                rows(end+1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(v.pairs.(app.UI.basis.Value), ' / '))};
            end
            rows = [rows; {'Peak gain (POB)', [fmt(m.PeakGain_dB) ' dB']; 'POB direction [θ, φ]', sprintf('[%s°, %s°]', fmt(m.PeakTheta_deg), fmt(m.PeakPhi_deg)); ...
                'Boresight axis', app.Axes.labels{v.boresight}; 'Peak policy', sprintf('P%.4g, max excess %.4g dB', app.Peak.percentile, app.Peak.maxExcessDB); ...
                'Peak adjusted', char(string(v.peak.wasAdjusted)); 'HPBW E-plane', [fmt(m.HPBW_EPlane_deg) '°']; 'HPBW H-plane', [fmt(m.HPBW_HPlane_deg) '°']; ...
                'Front-to-back', [fmt(m.FrontBack_dB) ' dB']; 'Peak directivity', [fmt(m.PeakDirectivity_dB) ' dB']}];
            if isfinite(m.Efficiency_pct), rows(end+1, :) = {'Radiation efficiency', [fmt(m.Efficiency_pct) '%']}; end
            if isfinite(m.AxialRatioAtPeak_dB), rows(end+1, :) = {'AR at peak', [fmt(m.AxialRatioAtPeak_dB) ' dB']}; end
            app.UI.tableMeta.Data = rows;
        end

        %% ================================================================ ranges & theme
        function [limits, map] = theme(app)
            % Signed AR always uses ±30 dB with a blue-white-red map; gain-like data share app.lim.gain with jet.
            persistent jetMap arMap
            if isempty(jetMap), jetMap = jet(256); arMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
            if app.isAR(app.comp()), limits = app.ARLimits; map = arMap; else, limits = app.lim.gain; map = jetMap; end
        end

        function applyTheme(app)
            limits = app.theme(); app.setRange("full", limits, false); app.setRange("cut", limits, false);
        end

        function applyColorbar(app)
            b = [app.UI.cmin.Value, app.UI.cmax.Value]; app.setRange("full", b, true); app.setRange("cut", b, true);
        end

        function setRange(app, scope, bounds, widen)
            % One controller for every slider/min/max triplet: "full" (5 mirrored tabs), "cut", "covx" (coverage X axis).
            % Spinner edits (widen=true) extend the slider travel; slider drags select within the current travel.
            bounds = clampRange(bounds, app.RangeBounds, 1);
            switch scope, case "full", ctl = app.UI.full; case "cut", ctl = app.UI.cutRange; otherwise, ctl = app.UI.covRange; end
            sliders = [ctl.slider]; travel = bounds;
            if widen, travel = [min(sliders(1).Limits(1), bounds(1)), max(sliders(1).Limits(2), bounds(2))]; end
            set(sliders, 'Limits', app.RangeBounds, 'Value', bounds); set(sliders, 'Limits', travel);   % widen first: Value is never clamped mid-update
            set([ctl.min ctl.max], 'Limits', app.RangeBounds);
            set([ctl.min], 'Value', bounds(1), 'Limits', [app.RangeBounds(1), bounds(2) - 1]);
            set([ctl.max], 'Value', bounds(2), 'Limits', [bounds(1) + 1, app.RangeBounds(2)]);
            switch scope
                case "full"
                    app.lim.full = bounds; if ~app.isAR(app.comp()), app.lim.gain = bounds; end
                    app.UI.cmin.Value = bounds(1); app.UI.cmax.Value = bounds(2); app.applyFullRange();
                case "cut"
                    app.lim.cut = bounds;
                    if ~isempty(app.viewTbl), set(app.UI.paxCut, 'RLim', bounds); set(app.UI.axesRect, 'YLim', bounds); end
                otherwise
                    set(app.UI.covAxes, 'XLimMode', 'manual', 'XLim', bounds);
            end
        end

        function onRangeInput(app, scope, value, endIndex)
            % endIndex: 0 = slider (both ends), 1 = min spinner, 2 = max spinner.
            if endIndex == 0, app.setRange(scope, value, false); return; end
            switch scope, case "full", b = app.lim.full; case "cut", b = app.lim.cut; otherwise, b = app.UI.covAxes.XLim; end
            b(endIndex) = value; app.setRange(scope, b, true);
        end

        function applyFullRange(app)
            % Push app.lim.full to every rendered full-pattern axes (color limits, colorbar ticks, 3-D z-limits).
            limits = app.lim.full;
            for k = find(~app.dirty)
                spec = app.UI.full(k); clim(spec.axes, limits);
                if k == 5, zlim(spec.axes, limits); t = axisTicks(limits, app.UI.cstep.Value); if ~isempty(t), spec.axes.ZTick = t; end, end
                if isgraphics(spec.cbar), t = axisTicks(limits, app.UI.cstep.Value); if ~isempty(t), spec.cbar.Ticks = t; end, end
            end
        end

        %% ================================================================ full-pattern plots (lazy)
        function invalidateFull(app)
            app.dirty(:) = true; app.renderVisibleFull();
        end

        function renderVisibleFull(app)
            % Only the visible tab is drawn; hidden tabs are drawn on first view.  Also serves the tab-change callback.
            if isempty(app.viewTbl) || app.isClosing, return; end
            k = find([app.UI.full.tab] == app.UI.fullTabs.SelectedTab, 1);
            if app.dirty(k)
                switch k
                    case 1, app.drawContour();
                    case 2, app.drawFisheye();
                    case 3, app.drawPattern3D(3, "sphere");
                    case 4, app.drawPattern3D(4, "polar");
                    case 5, app.drawRect3D();
                end
                app.dirty(k) = false; drawnow limitrate            % surfaces must exist before DataTips attach
                app.registerSurfacePOB(k);
            end
            app.refreshAnnotations();
        end

        function limits = finishSurface(app, k, h, C)
            % Shared surface epilogue: theme, colorbar, DataTip template, context menu.
            [limits, map] = app.theme(); ax = app.UI.full(k).axes;
            clim(ax, limits); colormap(ax, map); cbar = colorbar(ax); app.UI.full(k).cbar = cbar;
            t = axisTicks(limits, app.UI.cstep.Value); if ~isempty(t), cbar.Ticks = t; end
            g = app.viewGrid(); thetaLabel = "Theta"; if app.isElev(), thetaLabel = "Elevation"; end
            try
                h.DataTipTemplate.DataTipRows = [dataTipTextRow(thetaLabel, g.thetaGrid, '%.3g°'); dataTipTextRow("Phi", g.phiGrid, '%.3g°'); ...
                    dataTipTextRow(replace(app.compLabel(), "_", "\_"), C, '%.3g dB')];
            catch
            end
            app.attachContextMenu(ax);
        end

        function drawContour(app)
            [g, C] = app.compGrid(app.comp()); ax = app.UI.full(1).axes; cla(ax);
            h = pcolor(ax, g.phi, g.theta, C, 'FaceColor', 'interp', 'LineStyle', 'none', 'Tag', 'APAT_Surface');
            app.finishSurface(1, h, C); app.formatAngularAxes(ax, 30, 15); daspect(ax, [1 1 1]);
            title(ax, app.compLabel(), 'Interpreter', 'none');
        end

        function drawFisheye(app)
            [g, C] = app.compGrid(app.comp()); pax = app.UI.full(2).axes; cla(pax);
            h = surface(pax, g.phiRad, g.thetaPolar, zeros(g.sz), C, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.finishSurface(2, h, C); app.setPolarTicks(pax);
            rLabels = 0:30:180; if app.isElev(), rLabels = 90 - rLabels; end
            set(pax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', rLabels));
            title(pax, sprintf('%s  |  r=θ, angle=φ', app.compLabel()), 'Interpreter', 'none', 'FontSize', 9);
        end

        function drawPattern3D(app, k, kind)
            % kind "sphere": unit sphere colored by the component; "polar": radius scaled by the component within the color range.
            [g, C] = app.compGrid(app.comp()); ax = app.UI.full(k).axes; limits = app.theme(); xyz = {g.x, g.y, g.z};
            if kind == "polar"
                r = max(C - limits(1), 0) / max(diff(limits), eps); r = r / max(max(r, [], 'all', 'omitnan'), eps);
                xyz = cellfun(@(c) r.*c, xyz, 'UniformOutput', false);
            end
            cla(ax); hold(ax, 'on');
            h = surf(ax, xyz{:}, C, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.finishSurface(k, h, C);
            set(ax, 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1], 'Projection', 'orthographic');
            axis(ax, 'off'); app.drawXYZ(ax); app.apply3DView(ax, [135 25]);
            if app.UI.overlay.Value, app.overlayCut(ax, kind); end
            title(ax, sprintf('%s  |  θ: %s  |  φ: %s', app.compLabel(), app.UI.thetaSpan.Value, app.UI.phiSpan.Value), 'Interpreter', 'none');
            hold(ax, 'off');
        end

        function drawRect3D(app)
            [g, C] = app.compGrid(app.comp()); ax = app.UI.full(5).axes; cla(ax);
            h = surf(ax, g.phiGrid, g.thetaGrid, C, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            limits = app.finishSurface(5, h, C);
            zlim(ax, limits); t = axisTicks(limits, app.UI.cstep.Value); if ~isempty(t), ax.ZTick = t; end
            app.formatAngularAxes(ax, 60, 30); grid(ax, 'on');
            thetaLabel = 'Theta (degree)'; if app.isElev(), thetaLabel = 'Elevation (degree)'; end
            xlabel(ax, 'Phi (degree)'); ylabel(ax, thetaLabel); zlabel(ax, app.compLabel() + " (dB)", 'Interpreter', 'none');
            app.apply3DView(ax, [-35 35]); title(ax, app.compLabel(), 'Interpreter', 'none');
        end

        function drawXYZ(~, ax)
            colors = {[0.85 0.1 0.1], [0.1 0.6 0.1], [0.1 0.2 0.9]}; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            for k = 1:3
                d = 1.35 * double((1:3) == k);
                quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12*d(1), 1.12*d(2), 1.12*d(3), labels{k}, 'Color', colors{k}, 'FontWeight', 'bold');
            end
        end

        function apply3DView(app, ax, defaultView)
            code = app.UI.view3D.Value;
            if isfield(app.Views3D, code), v = app.Views3D.(code); else, v = {defaultView(1), defaultView(2), [0 0 1]}; end
            view(ax, v{1}, v{2}); camup(ax, v{3});
        end

        function on3DViewChanged(app)
            if isempty(app.viewTbl), return; end
            app.apply3DView(app.UI.full(3).axes, [135 25]); app.apply3DView(app.UI.full(4).axes, [135 25]); app.apply3DView(app.UI.full(5).axes, [-35 35]);
        end

        function overlayCut(app, ax, kind)
            c = app.cutData(); v = c.data(:, 1); limits = app.theme();
            if kind == "sphere", r = 1.02; else, r = 1.01 * max(v - limits(1), 0) / max(diff(limits), eps); end
            plot3(ax, r.*sind(c.theta).*cosd(c.phi), r.*sind(c.theta).*sind(c.phi), r.*cosd(c.theta), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay');
        end

        function updateOverlays(app)
            % Overlay checkbox / cut changes redraw only the overlay lines on already-rendered 3-D tabs.
            for k = 3:4
                ax = app.UI.full(k).axes; delete(findall(ax, 'Tag', 'APAT_CutOverlay'));
                if app.UI.overlay.Value && ~app.dirty(k), hold(ax, 'on'); app.overlayCut(ax, app.FullNames(k)); hold(ax, 'off'); end
            end
        end

        function [phiLim, thetaLim, dir] = angularLimits(app)
            phiLim = [0 360]; if app.isSignedPhi(), phiLim = [-180 180]; end
            thetaLim = [0 180]; dir = 'reverse'; if app.isElev(), thetaLim = [-90 90]; dir = 'normal'; end
        end

        function formatAngularAxes(app, ax, phiStep, thetaStep)
            [p, t, dir] = app.angularLimits();
            set(ax, 'XLim', p, 'YLim', t, 'YDir', dir, 'Box', 'on', 'Layer', 'top', 'XTick', p(1):phiStep:p(2), 'YTick', t(1):thetaStep:t(2));
        end

        function setPolarTicks(app, pax)
            labels = 0:30:330; if app.isSignedPhi(), labels(labels > 180) = labels(labels > 180) - 360; end
            set(pax, 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', labels));
        end

        %% ================================================================ annotations (POB / HPBW)
        function addAnnotation(app, src, kind, index, rows, tab)
            % SRC (line or surface) owns its record; INDEX is a data/grid index or NaN when SRC itself is the marker.
            src.UserData = struct('kind', kind, 'index', index, 'rows', rows, 'tab', tab, 'tip', gobjects(0), 'marker', gobjects(0));
            app.annots{end+1} = src;
        end

        function registerSurfacePOB(app, k)
            h = findobj(app.UI.full(k).axes, 'Tag', 'APAT_Surface'); if isempty(h) || ~isfinite(app.view.POBth), return; end
            g = app.viewGrid(); theta = app.view.POBth; phi = mod(app.view.POBph, 360);
            if app.isElev(), theta = 90 - theta; end
            if app.isSignedPhi() && phi > 180, phi = phi - 360; end
            [~, r] = min(abs(g.theta - theta)); [~, c] = min(abs(g.phi - phi)); C = h(1).CData; index = sub2ind(size(C), r, c);
            thetaLabel = 'Theta'; if app.isElev(), thetaLabel = 'Elevation'; end
            rows = [dataTipTextRow(thetaLabel, g.thetaGrid(index), '%.3g°'); dataTipTextRow('Phi', g.phiGrid(index), '%.3g°'); dataTipTextRow(app.compLabel(), C(index), '%.3g dB')];
            app.addAnnotation(h(1), "pob", index, rows, app.UI.full(k).tab);
        end

        function refreshAnnotations(app)
            % One pass over all sources: create tips lazily when enabled and on the visible tab, then sync visibility.
            app.annots = app.annots(cellfun(@isgraphics, app.annots)); u = app.UI;
            for k = 1:numel(app.annots)
                src = app.annots{k}; a = src.UserData;
                if a.kind == "pob", enabled = u.showPOB.Value; else, enabled = u.showHPBW.Value; end
                onTab = isempty(a.tab) || a.tab.Parent.SelectedTab == a.tab;
                if enabled && onTab && isempty(a.tip), [a.tip, a.marker] = app.makeTip(src, a.index, a.rows); src.UserData = a; end
                if a.kind == "hpbw", src.Visible = enabled; end
                set([a.tip a.marker], 'Visible', enabled && onTab);
            end
        end

        function [tip, marker] = makeTip(app, src, index, rows)
            % Black marker + DataTip at sample INDEX of SRC (or on SRC itself when INDEX is NaN).
            tip = gobjects(0); marker = gobjects(0); [x, y] = deal(NaN);
            try
                ax = src.Parent; polar = isa(ax, 'matlab.graphics.axis.PolarAxes'); host = src;
                if ~isnan(index)
                    [x, y, z] = pointAt(src, index, polar); held = ishold(ax); hold(ax, 'on');
                    if polar, marker = polarplot(ax, x, y, 'ko', 'MarkerSize', 5, 'MarkerFaceColor', 'k', 'HandleVisibility', 'off');
                    else, marker = plot3(ax, x, y, z, 'ko', 'MarkerSize', 5, 'MarkerFaceColor', 'k', 'HandleVisibility', 'off', 'Clipping', 'off'); end
                    if ~held, hold(ax, 'off'); end
                    host = marker;
                end
                if ~isempty(rows), host.DataTipTemplate.DataTipRows = rows; end
                tip = datatip(host, 'DataIndex', 1, 'HandleVisibility', 'off', 'FontSize', 9);
                if isequal(ax, app.UI.full(1).axes) && abs(y - ax.YLim(1 + strcmp(ax.YDir, 'normal'))) <= diff(ax.YLim)/1000
                    if x <= mean(ax.XLim), tip.Location = 'southeast'; else, tip.Location = 'southwest'; end
                end
            catch ME
                delete([tip marker]); tip = gobjects(0); marker = gobjects(0);
                if ~app.isClosing, warning('APAT:Annotation', 'Could not create annotation: %s', ME.message); end
            end
        end

        %% ================================================================ cuts
        function planeChanged(app)
            % E-plane: Theta cut at the boresight φ.  H-plane: Phi cut at θ=90° for transverse axes, else Theta cut at φ=90°.
            if isempty(app.viewTbl), return; end
            u = app.UI; ax = app.Axes; k = app.view.boresight;
            if startsWith(u.plane.Value, 'E'), type = 'Theta'; value = ax.phi(k);
            elseif ax.theta(k) == 90, type = 'Phi'; value = 90; if app.isElev(), value = 0; end
            else, type = 'Theta'; value = 90; end
            u.cutType.Value = type; app.updateCutControl(value); app.cutChanged();
        end

        function updateCutControl(app, requested)
            % Spinner limits/step follow the sampled cut coordinates; the value snaps to the nearest sample.
            u = app.UI;
            if strcmp(u.cutType.Value, 'Phi'), values = unique(app.viewTbl.Theta); else, values = unique(mod(app.viewTbl.Phi, 360)); end
            if nargin < 2, requested = u.cutValue.Value; end
            [~, k] = min(abs(values - requested));
            u.cutValue.Limits = [-Inf Inf]; u.cutValue.Value = values(k);
            if numel(values) > 1, u.cutValue.Limits = [min(values) max(values)]; u.cutValue.Step = min(diff(values)); end
        end

        function cutChanged(app, src)
            u = app.UI; if isempty(app.viewTbl), return; end
            if nargin > 1
                if src == u.cutType, app.updateCutControl(); elseif src == u.basis, u.basis.UserData = false; app.updateMetadata(); end
            end
            u.showHPBW.Visible = u.hpbwBtn.Value; if ~u.hpbwBtn.Value, u.showHPBW.Value = false; end
            app.plotCut(); app.updateOverlays();
        end

        function [cols, idx] = cutCols(app)
            % Total plus the co/cross pair of the selected basis; IDX keeps line colors stable per component.
            u = app.UI;
            if app.src.meta.isGainOnly, cols = string(app.comp()); idx = 1; return; end
            if strcmp(u.basis.Value, 'Linear'), all3 = ["E_Total_dB","E_TH_dB","E_PH_dB"]; else, all3 = ["E_Total_dB","E_RCP_dB","E_LCP_dB"]; end
            pair = erase(all3(2:3), "_dB"); if ~strcmp(u.cbCo.Text, pair(1)), u.cbCo.Text = pair(1); u.cbCx.Text = pair(2); end
            sel = logical([u.cbTotal.Value u.cbCo.Value u.cbCx.Value]); if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = all3(idx);
        end

        function c = cutData(app)
            % The active cut as one closed circle: angle, component data, names, title and physical θ/φ per sample.
            u = app.UI; T = app.viewTbl; [cols, idx] = app.cutCols(); type = string(u.cutType.Value);
            req = u.cutValue.Value; if type == "Phi" && app.isElev(), req = 90 - req; end
            th = app.physTheta(T); [angle, rows, fixed, sym, snapped] = calcCutGeometry(th, T.Phi, type, req);
            shown = fixed; if type == "Phi" && app.isElev(), shown = 90 - fixed; end
            if snapped, app.status("main", sprintf('Requested %s cut @ %s=%g° (snapped to nearest %s=%g°)', type, sym, u.cutValue.Value, sym, shown)); end
            D = T{rows, cols}; th = th(rows); ph = T.Phi(rows);
            if app.isSignedPhi()
                angle(angle > 180) = angle(angle > 180) - 360;
                [angle, o] = sort(angle); D = D(o, :); th = th(o); ph = ph(o);
            end
            if app.isSignedPhi() || type == "Phi", [angle, o] = unique(angle, 'stable'); D = D(o, :); th = th(o); ph = ph(o); end
            if type == "Phi"                                             % close the φ circle at the seam
                seam = [0 360]; if app.isSignedPhi(), seam = [-180 180]; end
                lo = find(abs(angle - seam(1)) < 1e-9, 1); hi = find(abs(angle - seam(2)) < 1e-9, 1);
                if isempty(lo) && ~isempty(hi), angle = [seam(1); angle]; D = [D(hi, :); D]; th = [th(hi); th]; ph = [ph(hi); ph];
                elseif ~isempty(lo) && isempty(hi), angle = [angle; seam(2)]; D = [D; D(lo, :)]; th = [th; th(lo)]; ph = [ph; ph(lo)];
                elseif isempty(lo) && isempty(hi)
                    w = (seam(2) - angle(end)) / (angle(1) - seam(1) + seam(2) - angle(end));
                    Ds = (1 - w)*D(end, :) + w*D(1, :); ts = (1 - w)*th(end) + w*th(1);
                    angle = [seam(1); angle; seam(2)]; D = [Ds; D; Ds]; th = [ts; th; ts]; ph = [seam(1); ph; seam(2)];
                end
            end
            if app.src.meta.isGainOnly, ttl = char(app.comp()); else, ttl = sprintf('%s cut @ %s = %g°', type, sym, shown); end
            c = struct('angle', angle, 'data', D, 'cols', cols, 'idx', idx, 'names', replace(cols, "_", "\_"), 'title', ttl, 'theta', th, 'phi', ph, 'type', type);
        end

        function plotCut(app)
            if isempty(app.viewTbl), return; end
            u = app.UI; c = app.cutData(); pax = u.paxCut; rax = u.axesRect; lim = app.lim.cut;
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on');
            pl = polarplot(pax, deg2rad(c.angle), max(c.data, lim(1)), 'LineWidth', 1.4);   % clamp: no reflection spikes below RLim
            rl = plot(rax, c.angle, c.data, 'LineWidth', 1.4);
            colors = rax.ColorOrder(1 + mod(c.idx - 1, size(rax.ColorOrder, 1)), :);
            set(pl, {'Color'}, num2cell(colors, 2)); set(rl, {'Color'}, num2cell(colors, 2));
            for k = 1:numel(pl)
                rows = [dataTipTextRow("Angle", c.angle, '%.3g°'); dataTipTextRow("Magnitude", c.data(:, k), '%.3g dB')];
                pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            set(pax, 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.setPolarTicks(pax); xl = app.angularLimits();
            set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, c.type + " (degree)"); title(pax, c.title, 'Interpreter', 'none'); title(rax, c.title, 'Interpreter', 'none');
            % POB of the displayed cut (a 1-D view: indexed in the plotted line data, not the full-pattern POB).
            [pk, ip] = max(c.data(:, 1), [], 'omitnan'); u.hpbwLabel.Text = '';
            if isfinite(pk)
                rows = [dataTipTextRow("Angle", c.angle(ip), '%.3g°'); dataTipTextRow("Magnitude", pk, '%.3g dB')];
                app.addAnnotation(pl(1), "pob", ip, rows, u.polarTab); app.addAnnotation(rl(1), "pob", ip, rows, u.rectTab);
            end
            if u.hpbwBtn.Value && isfinite(pk)   % HPBW: wrap-aware shaded region and optional interpolated boundary tips
                [bw, lo, hi] = calcHPBW(c.angle, c.data(:, 1), pk, c.angle(ip));
                if isfinite(bw)
                    b = [lo hi]; if xl(1) < 0, b = mod(b + 180, 360) - 180; else, b = mod(b, 360); end
                    u.hpbwLabel.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                    if b(1) <= b(2), regions = b; else, regions = [xl(1) b(2); b(1) xl(2)]; end
                    thetaregion(pax, deg2rad(regions(:, 1)), deg2rad(regions(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    xregion(rax, regions(:, 1), regions(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    names = ["Lower HPBW", "Upper HPBW"];
                    for k = 1:2
                        rows = [dataTipTextRow(names(k), b(k), '%.2f°'); dataTipTextRow("Gain", pk - 3, '%.2f dB')];
                        m1 = polarplot(pax, deg2rad(b(k)), pk - 3, 'o', 'Color', '#D95319', 'MarkerFaceColor', '#D95319', 'HandleVisibility', 'off');
                        m2 = plot(rax, b(k), pk - 3, 'o', 'Color', '#D95319', 'MarkerFaceColor', '#D95319', 'HandleVisibility', 'off');
                        app.addAnnotation(m1, "hpbw", NaN, rows, u.polarTab); app.addAnnotation(m2, "hpbw", NaN, rows, u.rectTab);
                    end
                end
            end
            legend(pax, pl, c.names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rl, c.names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off');
            app.refreshAnnotations();
        end

        %% ================================================================ export
        function exportTable(app, T, prompt, defaultName, filters, which)
            % TXT is tab-delimited, UAN uses the XGTD header, everything else goes through writetable.
            if nargin < 6, which = "main"; end
            [f, p] = uiputfile(filters, prompt, fullfile(app.src.folder, defaultName)); if isequal(f, 0), return; end
            fp = fullfile(p, f);
            if endsWith(fp, '.uan', 'IgnoreCase', true), writeUAN(T, fp);
            elseif endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t');
            else, writetable(T, fp); end
            app.status(which, ['Exported to <b>' fp '</b>'], true);
        end

        function exportResults(app)
            if isempty(app.viewTbl), return; end
            app.exportTable(app.UI.tableOut.Data, 'Export Results', [app.src.base '_APAT_results.csv'], app.TableFilters);   % respects the column filter
        end

        function exportCut(app)
            if isempty(app.viewTbl), return; end
            c = app.cutData();
            app.exportTable(array2table([c.angle, c.data], 'VariableNames', [{'Angle_deg'}, cellstr(c.cols)]), 'Export Cut', [app.src.base '_cut.csv'], app.TableFilters(1:2, :));
        end

        function exportUAN(app)
            if app.src.meta.isGainOnly, uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            if isempty(app.uanTbl)
                T = app.viewTbl;
                app.uanTbl = sortrows(table(app.physTheta(T), T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                    'VariableNames', {'Theta','Phi','E_TH_DB','E_PH_DB','E_TH_DG','E_PH_DG'}), {'Phi','Theta'});
            end
            step = gridStep(app.uanTbl.Theta); if ~isfinite(step), step = 1; end
            peak = max([app.uanTbl.E_TH_DB; app.uanTbl.E_PH_DB], [], 'omitnan');
            app.exportTable(app.uanTbl, 'Export UAN / E-field data', sprintf('%s_%.5f_%gdeg.uan', app.src.base, peak, step), ...
                [{'*.uan', 'XGTD user-defined antenna (*.uan)'}; app.TableFilters(1:2, :)]);
        end

        %% ================================================================ coverage
        function toCoverage(app)
            % Coverage always receives the CURRENT Main view table (loss, step, span and components exactly as displayed).
            if isempty(app.viewTbl), uialert(app.UIFigure, 'Load and process a pattern first.', 'Coverage'); return; end
            u = app.UI; u.tabs.SelectedTab = u.covTab; u.covPath.Value = app.src.path;
            node = app.covFindNode(app.src.path);
            if isempty(node), app.covAddPattern(app.src.base, app.viewTbl, app.src.path);
            else, app.covSyncFromView(node); u.covTree.SelectedNodes = node; app.setCoverageUI(); end
            app.status("cov", 'Coverage source synchronized from the current Main-tab View Table.');
        end

        function covSyncFromView(app, node)
            d = node.NodeData; d.pattern = app.viewTbl; d.solidAngle = solidWeights(app.physTheta(app.viewTbl), app.viewTbl.Phi);
            d.rev = app.view.rev; d.name = app.src.base; node.NodeData = d; app.covSyncPattern(node);
        end

        function node = covAddPattern(app, name, pattern, path)
            u = app.UI; node = uitreenode(u.covRoot, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', "pattern", 'name', name, 'path', path, 'pattern', pattern, 'solidAngle', solidWeights(app.physTheta(pattern), pattern.Phi), ...
                'rev', app.view.rev, 'component', "", 'boresight', 1, 'cache', struct());
            expand(u.covTree); u.covTree.CheckedNodes = [u.covTree.CheckedNodes; node]; u.covTree.SelectedNodes = node;
            app.covSyncPattern(node); app.setCoverageUI(); u.covResults.Visible = 'on';
            app.status("cov", sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name));
        end

        function covSyncPattern(app, node)
            % Component list, detected orientation and the automatic threshold preset follow the target pattern node.
            u = app.UI; d = node.NodeData; T = d.pattern;
            previous = d.component; if previous == "", previous = string(u.covComponent.Value); end
            app.setComponentItems(u.covComponent, T, previous); comp = string(u.covComponent.Value);
            if comp ~= d.component
                d.component = comp; d.boresight = app.covOrientation(d); node.NodeData = d;
                if u.covOrient.Value == 0, app.covOrientationChanged(); end     % Auto: seed the cone center from the detected axis
            end
            key = sprintf('%s|%s|%g', d.path, comp, d.rev);
            if ~strcmp(app.cov.presetKey, key)   % preset only when pattern/component/view changes; user edits survive otherwise
                app.setThresholdPreset(displayRange(T.(char(comp)), [-40 10], app.Peak)); app.cov.presetKey = key;
            end
        end

        function k = covOrientation(app, d)
            [~, ~, k] = calcOrientation(app.physTheta(d.pattern), d.pattern.Phi, chooseGain(d.pattern, d.component), d.solidAngle, app.Axes, app.Peak);
        end

        function setThresholdPreset(app, bounds)
            u = app.UI; bounds = clampRange(bounds, app.RangeBounds, 1);
            if app.cov.thrInit, bounds = [min(u.thrMin.Value, bounds(1)), max(u.thrMax.Value, bounds(2))]; end
            set([u.thrMin u.thrMax], 'Limits', app.RangeBounds); u.thrMin.Value = bounds(1); u.thrMax.Value = bounds(2);
            u.thrMin.Limits = [app.RangeBounds(1), bounds(2) - 0.1]; u.thrMax.Limits = [bounds(1) + 0.1, app.RangeBounds(2)];
            app.cov.thrInit = true;
        end

        function thr = covThresholds(app)
            % The user's current threshold controls, verbatim.
            u = app.UI; tMin = u.thrMin.Value; tMax = u.thrMax.Value; step = max(u.thrStep.Value, 0.1);
            if tMax <= tMin, tMax = min(100, tMin + step); u.thrMax.Value = tMax; end
            thr = (tMin:step:tMax)'; if thr(end) < tMax - 1e-9, thr(end+1, 1) = tMax; end
        end

        function covSetPlotRange(app, bounds, step)
            % The first result establishes the X baseline; later results may only widen it.
            if app.cov.plotInit, bounds = [min(app.UI.covAxes.XLim(1), bounds(1)), max(app.UI.covAxes.XLim(2), bounds(2))]; end
            app.cov.plotInit = true; app.setRange("covx", bounds, false);
            if nargin > 2 && isfinite(step) && step < app.UI.thrStep.Value, app.UI.thrStep.Value = step; end
        end

        function covLoad(app)
            u = app.UI; fp = strtrim(u.covPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFindNode(fp))
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage data'; '*.*', 'All files'}, 'Select a pattern or coverage results file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            existing = app.covFindNode(fp);
            if ~isempty(existing)
                u.covTree.SelectedNodes = existing; app.covSelectionChanged(); u.covPath.Value = fp; app.setCoverageUI();
                app.status("cov", 'File already loaded -- node selected. Add another job or load a different file.', true); return
            end
            u.covPath.Value = fp; out = app.readSource(fp, u.covFmtLabel, u.covFmt, false);
            if out.meta.isCoverage
                target = app.covPatternTarget(); if ~isempty(target), u.covPath.Value = target.NodeData.path; end
                app.covLoadResults(fp, out.rawTbl);
            else
                [~, name] = fileparts(fp); app.covAddPattern(name, app.buildPattern(out), fp);
            end
        end

        function pattern = buildPattern(app, out)
            % Auxiliary pattern (block 1) processed with the current parameters, without touching Main state.
            T = normalizePattern(out.blocks{1}); T.Properties.UserData = out.meta; pattern = calcPattern(T, app.getParam());
        end

        function covFormatChanged(app)
            % Re-read a generic coverage-tab pattern with the newly selected text format.
            u = app.UI; fp = strtrim(u.covPath.Value); old = app.covFindNode(fp);
            if isempty(old) || ~isGenericText(fp), return; end
            out = app.readSource(fp, u.covFmtLabel, u.covFmt, true);
            if out.meta.isCoverage, app.status("cov", 'Coverage-result format is detected automatically; no pattern reprocessing required.', true); return; end
            name = old.NodeData.name; for j = old.Children(:).', delete(j.NodeData.line); end, delete(old);
            app.covAddPattern(name, app.buildPattern(out), fp); app.covFinalize();
            app.status("cov", sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
        end

        function covLoadResults(app, fp, R)
            u = app.UI; [~, name] = fileparts(fp);
            node = uitreenode(u.covRoot, 'Text', ['📄 ' name]); node.NodeData = struct('kind', "results", 'name', name, 'path', fp);
            thr = R{:, 1}; app.covSetPlotRange([min(thr) max(thr)], gridStep(thr)); jobs = cell(1, width(R) - 1);
            for c = 2:width(R), jobs{c-1} = app.covAddJob(node, thr, R{:, c}, 'Res', R.Properties.VariableNames{c}, 'Res'); end
            u.covTree.CheckedNodes = [u.covTree.CheckedNodes; node; vertcat(jobs{:})]; expand(node);
            app.covFinalize(); u.covResults.Visible = 'on';
            app.status("cov", sprintf('Coverage results file "%s" loaded (%d curves).', name, width(R) - 1));
        end

        function job = covAddJob(app, parent, thr, cov, tag, component, label)
            % One CCDF curve = one tree node + one line; NodeData carries everything later features need.
            u = app.UI; app.cov.runID = app.cov.runID + 1; id = app.cov.runID;
            icon = '📉'; if strcmp(tag, 'Res'), icon = '📈'; end
            name = sprintf('%s R%d %s · %s', icon, id, label, component);
            line = plot(u.covAxes, thr, cov, 'LineWidth', 1.6, 'DisplayName', name); [invCov, rows] = unique(cov, 'last');
            job = uitreenode(parent, 'Text', name);
            job.NodeData = struct('kind', "job", 'id', id, 'tag', tag, 'label', name, 'tableTag', tag, 'thr', thr(:), 'cov', cov(:), ...
                'invCov', invCov(:), 'invThr', reshape(thr(rows), [], 1), 'line', line, 'conical', false, 'orientation', "n/a");
        end

        function jobs = covJobs(app, roots)
            % The tree IS the job registry: jobs are the children of pattern/results nodes (sorted by run id).
            if nargin < 2, roots = app.UI.covRoot.Children; end
            list = {};
            for n = roots(:).'
                d = n.NodeData;
                if isstruct(d) && d.kind == "job", list{end+1} = n; else, list = [list, num2cell(n.Children(:).')]; end %#ok<AGROW>
            end
            jobs = [list{:}];
            if numel(jobs) > 1, [~, o] = sort(arrayfun(@(n) n.NodeData.id, jobs)); jobs = jobs(o); end
        end

        function node = covPatternTarget(app)
            % Selected pattern node (or the pattern above the selected job); otherwise the most recently added pattern.
            node = []; u = app.UI; sel = u.covTree.SelectedNodes;
            if ~isempty(sel)
                n = sel(1);
                while isa(n, 'matlab.ui.container.TreeNode')
                    if isstruct(n.NodeData) && n.NodeData.kind == "pattern", node = n; return; end
                    n = n.Parent;
                end
            end
            kids = u.covRoot.Children;
            for k = numel(kids):-1:1, if isstruct(kids(k).NodeData) && kids(k).NodeData.kind == "pattern", node = kids(k); return; end, end
        end

        function node = covFindNode(app, fp)
            node = [];
            for n = app.UI.covRoot.Children(:).', if isstruct(n.NodeData) && strcmp(n.NodeData.path, fp), node = n; return; end, end
        end

        function covCompute(app)
            u = app.UI; node = app.covPatternTarget();
            if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if ~isempty(app.viewTbl) && strcmp(node.NodeData.path, app.src.path), app.covSyncFromView(node); end   % Main pattern: always the displayed view
            d = node.NodeData; T = d.pattern; comp = char(u.covComponent.Value); thr = app.covThresholds();
            conical = u.covConical.Value; region = true(height(T), 1); tag = 'Sph'; label = 'Sph coverage'; tableTag = 'Sph'; orientation = "n/a";
            if conical
                [th0, ph0, alpha] = deal(u.coneTh.Value, mod(u.conePh.Value, 360), u.coneAng.Value); th = app.physTheta(T);
                region = cosd(th).*cosd(th0) + sind(th).*sind(th0).*cosd(T.Phi - ph0) >= cosd(alpha);
                center = app.coneCenterLabel(th0, ph0); orientation = string(app.Axes.labels{app.covResolvedOrientation()});
                tag = sprintf('Con_%.15g_%.15g_%.15g', th0, ph0, alpha);
                label = sprintf('Conical coverage (%s) α=%s°', center, fmt(alpha)); tableTag = sprintf('Con %s α%s°', erase(center, ["=", ","]), fmt(alpha));
            end
            key = matlab.lang.makeValidName(sprintf('%s_%g_%s_%g_%g_%g_%d', comp, d.rev, tag, thr(1), thr(end), gridStep(thr), numel(thr)));
            hit = isfield(d.cache, key);
            if hit, cov = d.cache.(key); else, cov = coverageCCDF(T.(comp), region, thr, d.solidAngle); d.cache.(key) = cov; node.NodeData = d; end
            job = app.covAddJob(node, thr, cov, tag, comp, label);
            jd = job.NodeData; jd.tableTag = tableTag; jd.conical = conical; jd.orientation = orientation; job.NodeData = jd;
            expand(node); u.covTree.CheckedNodes = [u.covTree.CheckedNodes; job];
            app.covFinalize(); app.covSetPlotRange([thr(1) thr(end)]); u.covResults.Visible = 'on';
            action = 'computed'; if hit, action = 'reused cached CCDF'; end
            msg = sprintf('Run-<b>%d</b> %s: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', jd.id, action, label, d.name, comp, numel(thr));
            if conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, orientation); end
            app.status("cov", msg);
        end

        function label = coneCenterLabel(app, theta, phi)
            % Principal-axis name when the center matches ±X/±Y/±Z exactly, otherwise the spherical coordinates.
            ax = app.Axes; c = [sind(theta)*cosd(phi); sind(theta)*sind(phi); cosd(theta)];
            A = [sind(ax.theta(:)).*cosd(ax.phi(:)), sind(ax.theta(:)).*sind(ax.phi(:)), cosd(ax.theta(:))];
            k = find(A*c >= 1 - 1e-9, 1);
            if isempty(k), label = sprintf('θ=%s°, φ=%s°', fmt(theta), fmt(phi)); else, label = ax.labels{k}; end
        end

        function covFinalize(app)
            % Rebuild the results table and legend from the checked jobs, then refresh the panel state.
            u = app.UI; jobs = app.covJobs(); expand(u.covRoot);
            checked = jobs(ismember(jobs, u.covTree.CheckedNodes)); n = numel(checked);
            if n == 0, thr = app.covThresholds(); else, c = arrayfun(@(j) j.NodeData.thr, checked, 'UniformOutput', false); thr = unique(vertcat(c{:})); end
            values = [thr, nan(numel(thr), n)]; names = [{'Threshold (dB)'}, cell(1, n)]; lines = gobjects(1, n); labels = cell(1, n);
            for k = 1:n
                d = checked(k).NodeData; values(:, k+1) = safeInterp(d.thr, d.cov, thr);
                names{k+1} = sprintf('R%d %s %%', d.id, d.tableTag); lines(k) = d.line; labels{k} = d.label;
            end
            u.covTable.Data = array2table(compose('%.2f', values), 'VariableNames', names);
            if n == 0, legend(u.covAxes, 'off'); else, legend(u.covAxes, lines, labels, 'Location', 'southwest', 'Interpreter', 'none'); end
            app.setCoverageUI();
        end

        function setCoverageUI(app)
            % Panel state follows the tree: nothing -> load only; results only -> query/export; pattern -> everything.
            u = app.UI; hasPattern = ~isempty(app.covPatternTarget()); hasJobs = ~isempty(app.covJobs()); anyNode = hasPattern || hasJobs;
            set([u.covType u.covComponentLabel u.covComponent u.thrMinLabel u.thrMin u.thrMaxLabel u.thrMax u.thrStepLabel u.thrStep], 'Visible', hasPattern, 'Enable', hasPattern);
            set([u.covQueryCtl u.covReset u.covExport u.covClear u.covToMain], 'Visible', anyNode, 'Enable', anyNode);
            set([u.covExport u.covClear u.covQueryCtl], 'Enable', hasJobs); u.covCompute.Enable = hasPattern;
            set([u.covFmtLabel u.covFmt], 'Visible', hasPattern && isGenericText(u.covPath.Value));
            app.setConeControls();
        end

        function setConeControls(app)
            u = app.UI; on = u.covConical.Value && ~isempty(app.covPatternTarget());
            set([u.coneThLabel u.coneTh u.conePhLabel u.conePh u.coneAngLabel u.coneAng u.covOrientLabel u.covOrient], 'Visible', on, 'Enable', on);
        end

        function covTypeChanged(app)
            app.setConeControls(); u = app.UI;
            if u.covConical.Value
                node = app.covPatternTarget(); if ~isempty(node), app.covSyncPattern(node); end
                app.covReportOrientation();
            else
                u.covStatus.Text = regexprep(u.covStatus.Text, '\s*\|\s*Orientation <b>.*?</b>', '');
            end
        end

        function k = covResolvedOrientation(app)
            % Auto (0) resolves to the target node's detected boresight; explicit selections are authoritative.
            k = app.UI.covOrient.Value; node = app.covPatternTarget();
            if k == 0, if isempty(node), k = NaN; else, k = node.NodeData.boresight; end, end
        end

        function covOrientationChanged(app)
            k = app.covResolvedOrientation(); if ~isfinite(k), return; end
            app.UI.coneTh.Value = app.Axes.theta(k); app.UI.conePh.Value = app.Axes.phi(k); app.covReportOrientation();
        end

        function covReportOrientation(app)
            u = app.UI; k = app.covResolvedOrientation(); if ~u.covConical.Value || ~isfinite(k), return; end
            base = regexprep(u.covStatus.Text, '\s*\|\s*Orientation <b>.*?</b>$', '');
            app.status("cov", sprintf('%s | Orientation <b>%s</b>', base, app.Axes.labels{k}));
        end

        function covComponentChanged(app)
            % User selection is authoritative; only the detected orientation is refreshed for the new component.
            node = app.covPatternTarget(); if isempty(node), return; end
            d = node.NodeData; d.component = string(app.UI.covComponent.Value); d.boresight = app.covOrientation(d); node.NodeData = d;
            app.covReportOrientation();
        end

        function covQuery(app, mode)
            % "cov": coverage at a threshold; "thr": threshold at a coverage level.  Projections + one DataTip per checked curve.
            u = app.UI; ax = u.covAxes; if mode == "cov", q = u.queryCov.Value; else, q = u.queryThr.Value; end
            sel = u.covTree.SelectedNodes; if isempty(sel), app.status("cov", 'Select a node to query.', true); return; end
            jobs = app.covJobs(sel); jobs = jobs(ismember(jobs, u.covTree.CheckedNodes));
            if isempty(jobs), app.status("cov", 'No checked results under selected node.', true); return; end
            rows = [dataTipTextRow("Threshold", @(x, ~) arrayfun(@(v) [fmt(v) ' dB'], x, 'UniformOutput', false)); ...
                    dataTipTextRow("Coverage", @(~, y) arrayfun(@(v) [fmt(v) '%'], y, 'UniformOutput', false))];
            hit = false;
            for j = jobs(:).'
                d = j.NodeData; tag = sprintf('CovQ_%s_%d', mode, d.id); delete(app.covArtifacts(d, tag));
                if mode == "cov", x = q; y = safeInterp(d.thr, d.cov, q); else, y = q; x = safeInterp(d.invCov, d.invThr, q); end
                if ~isfinite(x) || ~isfinite(y), continue; end
                try, d.line.DataTipTemplate.DataTipRows = rows; catch, end
                line(ax, [x x], [ax.YLim(1) y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [app.RangeBounds(1) x], [y y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                tip = datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'HandleVisibility', 'off', 'FontSize', 9); tip.Tag = tag; hit = true;
            end
            if ~hit, app.status("cov", 'Query value is outside the selected checked range.', true);
            elseif mode == "cov", app.status("cov", sprintf('Coverage queried at %s dB.', fmt(q)));
            else, app.status("cov", sprintf('Threshold queried at %s%% coverage.', fmt(q))); end
        end

        function h = covArtifacts(app, d, tag)
            h = [findall(app.UI.covAxes, 'Tag', tag); findall(d.line, 'Tag', tag)];
        end

        function covCheckedChanged(app)
            u = app.UI;
            for j = app.covJobs()
                d = j.NodeData; on = ismember(j, u.covTree.CheckedNodes); d.line.Visible = on;
                set([app.covArtifacts(d, sprintf('CovQ_cov_%d', d.id)); app.covArtifacts(d, sprintf('CovQ_thr_%d', d.id)); findall(d.line, 'Type', 'datatip')], 'Visible', on);
            end
            app.covFinalize();
        end

        function covSelectionChanged(app)
            u = app.UI; sel = u.covTree.SelectedNodes;
            for j = app.covJobs(), j.NodeData.line.LineWidth = 1.6 + (~isempty(sel) && j == sel(1)); end   % emphasize the selected curve
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.status("cov", 'Ready.'); return; end
            d = sel(1).NodeData; target = app.covPatternTarget(); if ~isempty(target), app.covSyncPattern(target); end
            if d.kind ~= "job"
                kind = 'Pattern'; if d.kind == "results", kind = 'Results'; end, n = numel(sel(1).Children);
                app.status("cov", sprintf('%s <b>"%s"</b> -- <b>%d</b> coverage job%s.', kind, d.name, n, repmat('s', 1, n ~= 1)));
                if d.kind == "pattern", app.covReportOrientation(); end
                return
            end
            parts = {char(d.label)};
            if d.conical, parts{end+1} = sprintf('Orientation <b>%s</b>', d.orientation); end
            parts{end+1} = sprintf('Threshold [%s, %s] dB | Step %s dB', fmt(d.thr(1)), fmt(d.thr(end)), fmt(gridStep(d.thr)));
            t50 = safeInterp(d.invCov, d.invThr, 50);
            if isfinite(t50), parts{end+1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', fmt(t50)); else, parts{end+1} = '<b>50%-coverage unavailable</b>'; end
            shown = round(d.cov, 2); mx = max(shown); k = find(shown == mx, 1, 'last');   % same rounding as the table
            parts{end+1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmt(mx), fmt(d.thr(k)));
            app.status("cov", strjoin(parts, ' | '));
        end

        function covReset(app)
            u = app.UI;
            delete(u.covRoot.Children); delete(findall(u.covAxes, 'Type', 'datatip')); cla(u.covAxes); legend(u.covAxes, 'off');
            hold(u.covAxes, 'on'); grid(u.covAxes, 'on'); ylim(u.covAxes, [0 100]);
            u.covTable.Data = table(); app.cov = struct('runID', 0, 'presetKey', "", 'thrInit', false, 'plotInit', false);
            app.setRange("covx", [-40 10], false); u.covAxes.XLimMode = 'auto';   % the next result re-establishes the X baseline
            u.covResults.Visible = 'off'; app.setCoverageUI(); app.status("cov", 'Coverage workspace reset 🔄', true);
        end

        function covClear(app)
            % Remove DataTips and query markers below the selected node only (checked state is ignored on purpose).
            u = app.UI; sel = u.covTree.SelectedNodes;
            if isempty(sel), app.status("cov", 'Select a node to clear.', true); return; end
            jobs = app.covJobs(sel);
            if isempty(jobs), app.status("cov", 'No coverage results under selected node.', true); return; end
            for j = jobs(:).'
                d = j.NodeData;
                delete([app.covArtifacts(d, sprintf('CovQ_cov_%d', d.id)); app.covArtifacts(d, sprintf('CovQ_thr_%d', d.id)); findall(d.line, 'Type', 'datatip')]);
            end
            app.status("cov", 'Selected DataTips and query markers cleared.', true);
        end

        function covExport(app)
            if isempty(app.UI.covTable.Data), return; end
            app.exportTable(app.UI.covTable.Data, 'Export Coverage Results', 'coverage_results.csv', app.TableFilters, "cov");
        end

        %% ================================================================ UI construction
        function h = add(app, name, ctor, parent, row, col, varargin)
            % Declarative widget factory: create, place in the parent grid, register as app.UI.(name).
            h = ctor(parent, varargin{:});
            if ~isempty(row), place(h, row, col); end
            if ~isempty(name), app.UI.(name) = h; end
        end

        function h = addLabel(app, name, parent, row, col, text, varargin)
            h = app.add(name, @uilabel, parent, row, col, 'Text', text, 'HorizontalAlignment', 'right', varargin{:});
        end

        function createComponents(app)
            C = @(f) app.cb(f);                                    % guarded callback
            app.UIFigure = uifigure('Name', 'Antenna Pattern Analyzer Tool — APAT v3 M8', 'Visible', 'off', 'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', @(~,~) delete(app));
            root = uigridlayout(app.UIFigure, [1 1]);
            app.add('tabs', @uitabgroup, root, 1, 1);
            app.UI.mainTab = uitab(app.UI.tabs, 'Title', 'Process Pattern 📡');
            app.UI.covTab = uitab(app.UI.tabs, 'Title', 'Compute Coverage 📈');
            app.buildMainTab(C); app.buildCoverageTab(C);
            app.UIFigure.Visible = 'on';
        end

        function buildMainTab(app, C)
            sw = @(p, varargin) uiswitch(p, 'slider', varargin{:}); rs = @(p, varargin) uislider(p, 'range', varargin{:});
            G = uigridlayout(app.UI.mainTab, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});
            % --- Inputs & parameters -------------------------------------------------------------------------
            g = uigridlayout(app.add('paramPanel', @uipanel, G, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️'), 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            app.addLabel('', g, 1, 1, 'Input Pattern:');
            app.add('path', @uieditfield, g, 1, [2 8], 'text');
            app.addLabel('ffdLabel', g, 1, 9, 'FFD Freq:', 'Visible', 'off');
            app.add('ffd', @uidropdown, g, 1, 10, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', C(@(~,~) app.ffdChanged()));
            app.add('loadBtn', @uibutton, g, 1, [11 12], 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', C(@(~,~) app.onLoad()));
            app.add('processBtn', @uibutton, g, 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', C(@(~,~) app.onProcess()));
            app.add('resetBtn', @uibutton, g, 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', C(@(~,~) app.resetParams()));
            app.addLabel('fmtLabel', g, 2, [4 5], 'Format:', 'Visible', 'off');
            app.add('fmt', @uidropdown, g, 2, [6 8], app.TextFormatArgs{:}, 'Visible', 'off', 'ValueChangedFcn', C(@(~,~) app.formatChanged()));
            app.add('step', @uidropdown, g, 2, [9 10], 'Items', {'STEP', 'STEP: 1°'}, 'Visible', 'off', 'ValueChangedFcn', C(@(~,~) app.stepChanged()));
            app.add('exportBtn', @uibutton, g, 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', C(@(~,~) app.exportResults()));
            app.add('exportUAN', @uibutton, g, 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', C(@(~,~) app.exportUAN()));
            app.addLabel('rxPolLabel', g, 3, 1, 'Rw Sense', 'Visible', 'off');
            app.add('rxPol', @uidropdown, g, 3, 2, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Editable', 'on', 'Visible', 'off');
            app.addLabel('rwLabel', g, 3, 3, 'Rw (dB)', 'Visible', 'off');
            app.add('rw', @uispinner, g, 3, 4, 'Value', 6, 'Visible', 'off');
            app.addLabel('lossLabel', g, 3, 5, 'Loss (−) / Gain (+) dB', 'Visible', 'off');
            app.add('loss', @uispinner, g, 3, 6, 'Step', 0.1, 'Visible', 'off');
            app.addLabel('ptLabel', g, 3, 7, 'Tx Pwr (Pt)', 'Visible', 'off');
            app.add('pt', @uispinner, g, 3, 8, 'Visible', 'off');
            app.add('ptUnit', @uidropdown, g, 3, 9, 'Items', {'dBW', 'dBm', 'Watts'}, 'Visible', 'off');
            app.addLabel('distLabel', g, 3, 10, 'Distance', 'Visible', 'off');
            app.add('dist', @uispinner, g, 3, 11, 'Value', 1, 'Visible', 'off');
            app.add('distUnit', @uidropdown, g, 3, 12, 'Items', {'m', 'km'}, 'Visible', 'off');
            app.add('covBtn', @uibutton, g, 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', C(@(~,~) app.toCoverage()));
            % --- Full pattern: five tabs, each [max spinner; range slider; min spinner] + axes ----------------
            g = uigridlayout(app.add('fullPanel', @uipanel, G, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [1 1]);
            app.add('fullTabs', @uitabgroup, g, 1, 1, 'SelectionChangedFcn', C(@(~,~) app.renderVisibleFull()));
            titles = {'Contour Plot', 'Circular Contour Plot', '3D Spherical Plot', '3D Polar Plot', '3D Surface Plot'};
            for k = 1:5
                t = uitab(app.UI.fullTabs, 'Title', titles{k}); tg = uigridlayout(t, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
                spec = struct('tab', t, 'grid', tg, 'axes', [], 'cbar', [], 'slider', [], 'min', [], 'max', []);
                if k ~= 2, spec.axes = uiaxes(tg); place(spec.axes, [1 3], 2); end
                spec.max = uispinner(tg, 'Limits', app.RangeBounds, 'Value', 10, 'Step', 5, 'ValueChangedFcn', C(@(s,~) app.onRangeInput("full", s.Value, 2)));
                spec.slider = rs(tg, 'Limits', app.RangeBounds, 'Value', [-40 10], 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', C(@(s,~) app.onRangeInput("full", s.Value, 0)));
                spec.min = uispinner(tg, 'Limits', app.RangeBounds, 'Value', -40, 'Step', 5, 'ValueChangedFcn', C(@(s,~) app.onRangeInput("full", s.Value, 1)));
                place(spec.max, 1, 1); place(spec.slider, 2, 1); place(spec.min, 3, 1);
                if k == 1, app.UI.full = spec; else, app.UI.full(k) = spec; end
            end
            % --- Cut panel -----------------------------------------------------------------------------------
            g = uigridlayout(app.add('cutPanel', @uipanel, G, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [1 1]);
            app.add('cutTabs', @uitabgroup, g, 1, 1, 'SelectionChangedFcn', C(@(~,~) app.refreshAnnotations()));
            app.UI.polarTab = uitab(app.UI.cutTabs, 'Title', 'Polar Cut Plot');
            pg = app.add('polarGrid', @uigridlayout, app.UI.polarTab, [], [], 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            r = struct();
            r.max = app.add('', @uispinner, pg, 1, 1, 'Limits', app.RangeBounds, 'Value', 10, 'Step', 5, 'ValueChangedFcn', C(@(s,~) app.onRangeInput("cut", s.Value, 2)));
            r.slider = app.add('', rs, pg, [2 3], 1, 'Limits', app.RangeBounds, 'Value', [-40 10], 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', C(@(s,~) app.onRangeInput("cut", s.Value, 0)));
            r.min = app.add('', @uispinner, pg, 4, 1, 'Limits', app.RangeBounds, 'Value', -40, 'Step', 5, 'ValueChangedFcn', C(@(s,~) app.onRangeInput("cut", s.Value, 1)));
            app.UI.cutRange = r;
            app.add('hpbwBtn', @(p, varargin) uibutton(p, 'state', varargin{:}), pg, 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', C(@(~,~) app.cutChanged()));
            app.add('hpbwLabel', @uilabel, pg, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            fg = app.add('cutFieldGrid', @uigridlayout, pg, 3, 4, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x', '1x', '1x'});
            app.add('cbTotal', @uicheckbox, fg, 1, 1, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', C(@(~,~) app.cutChanged()));
            app.add('cbCo', @uicheckbox, fg, 2, 1, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', C(@(~,~) app.cutChanged()));
            app.add('cbCx', @uicheckbox, fg, 3, 1, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', C(@(~,~) app.cutChanged()));
            app.add('', @uibutton, pg, 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', C(@(~,~) app.exportCut()));
            app.UI.rectTab = uitab(app.UI.cutTabs, 'Title', 'Rectangular Cut Plot');
            ax = app.add('axesRect', @uiaxes, uigridlayout(app.UI.rectTab, [1 1]), 1, 1); xlabel(ax, 'Theta (degree)'); ylabel(ax, 'Magnitude (dB)'); ax.Box = 'on';
            % --- Plot control --------------------------------------------------------------------------------
            g = uigridlayout(app.add('ctrlPanel', @uipanel, G, 2, [13 14], 'Title', 'Plot Control 🎨', 'Visible', 'off'), 'RowHeight', repmat({'fit'}, 1, 15));
            app.addLabel('', g, 1, 1, 'Component');
            app.add('component', @uidropdown, g, 1, 2, 'Items', cellstr(app.ComponentLabels), 'ItemsData', cellstr(app.ComponentNames), 'Value', 'E_Total_dB', 'ValueChangedFcn', C(@(~,~) app.componentChanged()));
            app.addLabel('', g, 2, 1, 'Cut type');
            app.add('cutType', @uidropdown, g, 2, 2, 'Items', {'Phi', 'Theta'}, 'Value', 'Phi', 'ValueChangedFcn', C(@(s,~) app.cutChanged(s)));
            app.addLabel('', g, 3, 1, 'Cut value');
            app.add('cutValue', @uispinner, g, 3, 2, 'Limits', [0 360], 'Value', 0, 'ValueChangedFcn', C(@(s,~) app.cutChanged(s)));
            app.addLabel('', g, 4, 1, 'Cut fields');
            app.add('basis', @uidropdown, g, 4, 2, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Value', 'Circular', 'Enable', 'off', 'UserData', true, 'ValueChangedFcn', C(@(s,~) app.cutChanged(s)));
            app.addLabel('', g, 5, 1, 'Colorbar max');
            app.add('cmax', @uispinner, g, 5, 2, 'Limits', app.RangeBounds, 'Value', 10, 'ValueChangedFcn', C(@(~,~) app.applyColorbar()));
            app.addLabel('', g, 6, 1, 'Colorbar min');
            app.add('cmin', @uispinner, g, 6, 2, 'Limits', app.RangeBounds, 'Value', -40, 'ValueChangedFcn', C(@(~,~) app.applyColorbar()));
            app.addLabel('', g, 7, 1, 'Colorbar step');
            app.add('cstep', @uispinner, g, 7, 2, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', C(@(~,~) app.applyFullRange()));
            app.addLabel('', g, 8, 1, 'Adjust Colorbar');
            app.add('', @uibutton, g, 8, 2, 'Text', 'Apply', 'Tooltip', 'Apply the colorbar min/max to the full-pattern and cut plots.', 'ButtonPushedFcn', C(@(~,~) app.applyColorbar()));
            app.addLabel('', g, 9, 1, '3D view');
            app.add('view3D', @uidropdown, g, 9, 2, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Value', 'iso', 'Tooltip', 'Camera direction for the 3D pattern tabs.', 'ValueChangedFcn', C(@(~,~) app.on3DViewChanged()));
            pad = @(n) repmat(char(160), 1, n);   % non-breaking padding centers the switch captions
            app.add('phiSpan', sw, g, 10, [1 2], 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'Value', '0° to 360°', 'ValueChangedFcn', C(@(s,~) app.spanChanged(s)));
            app.add('thetaSpan', sw, g, 11, [1 2], 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'Value', '0° to 180°', 'ValueChangedFcn', C(@(s,~) app.spanChanged(s)));
            app.add('plane', sw, g, 12, [1 2], 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'Value', 'E-Plane cut', 'ValueChangedFcn', C(@(~,~) app.planeChanged()));
            app.add('overlay', @uicheckbox, g, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', C(@(~,~) app.updateOverlays()));
            app.add('showPOB', @uicheckbox, g, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', C(@(~,~) app.refreshAnnotations()));
            app.add('showHPBW', @uicheckbox, g, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', C(@(~,~) app.refreshAnnotations()));
            % --- Data tables & status ------------------------------------------------------------------------
            app.add('outFilter', @uidropdown, G, 3, [13 14], 'Items', {'--- column filter ---'}, 'Visible', 'off', 'ValueChangedFcn', C(@(~,~) app.filterOutput(false)));
            D = app.add('dataTabs', @uitabgroup, G, 4, [1 14], 'Visible', 'off');
            app.add('tableOut', @uitable, uigridlayout(uitab(D, 'Title', 'Results 📤'), [1 1]), 1, 1, 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnRearrangeable', 'on', 'Visible', 'off');
            app.add('tableIn', @uitable, uigridlayout(uitab(D, 'Title', 'Input 📥'), [1 1]), 1, 1, 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnRearrangeable', 'on', 'Visible', 'off');
            app.add('tableMeta', @uitable, uigridlayout(uitab(D, 'Title', 'Metadata 📋'), [1 1]), 1, 1, 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            app.add('status', @uilabel, G, 5, [1 14], 'Text', 'Ready 🚀', 'Interpreter', 'html');
        end

        function buildCoverageTab(app, C)
            G = uigridlayout(app.UI.covTab, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            g = uigridlayout(app.add('covParamPanel', @uipanel, G, 1, [1 5], 'Title', 'Inputs & Parameters 🎛️'), 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'});
            bg = app.add('covType', @uibuttongroup, g, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', C(@(~,~) app.covTypeChanged()));
            app.add('covSpherical', @uiradiobutton, bg, [], [], 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            app.add('covConical', @uiradiobutton, bg, [], [], 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            app.addLabel('covOrientLabel', g, 3, 1, 'Orientation 🧭:', 'Enable', 'off');
            app.add('covOrient', @uidropdown, g, 3, 2, 'Items', [{'Auto'}, app.Axes.labels], 'ItemsData', 0:numel(app.Axes.labels), 'Value', 0, 'Enable', 'off', 'ValueChangedFcn', C(@(~,~) app.covOrientationChanged()));
            app.addLabel('covComponentLabel', g, 4, 1, 'Component:', 'Enable', 'off');
            app.add('covComponent', @uidropdown, g, 4, 2, 'Items', {'E_Total_dB'}, 'Enable', 'off', 'ValueChangedFcn', C(@(~,~) app.covComponentChanged()));
            app.addLabel('covPathLabel', g, 1, 3, 'Antenna Pattern:');
            app.add('covPath', @uieditfield, g, 1, [4 8], 'text');
            app.add('covLoad', @uibutton, g, 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', C(@(~,~) app.covLoad()));
            app.add('covCompute', @uibutton, g, 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', C(@(~,~) app.covCompute()));
            app.addLabel('thrMinLabel', g, 2, 3, 'Threshold  Min (dB):'); app.add('thrMin', @uispinner, g, 2, 4, 'Value', -40);
            app.addLabel('thrMaxLabel', g, 2, 5, 'Threshold  Max (dB):'); app.add('thrMax', @uispinner, g, 2, 6, 'Value', 10);
            app.addLabel('thrStepLabel', g, 2, 7, 'Step (dB):');           app.add('thrStep', @uispinner, g, 2, 8, 'Value', 1);
            app.add('covReset', @uibutton, g, 2, 9, 'Text', '🔄 Reset', 'Enable', 'off', 'ButtonPushedFcn', C(@(~,~) app.covReset()));
            app.add('covExport', @uibutton, g, 2, 10, 'Text', '💾 Export Results', 'Enable', 'off', 'ButtonPushedFcn', C(@(~,~) app.covExport()));
            app.addLabel('coneThLabel', g, 3, 3, 'Cone θ₀ (°):', 'Enable', 'off');      app.add('coneTh', @uispinner, g, 3, 4, 'Limits', [0 180], 'Enable', 'off');
            app.addLabel('conePhLabel', g, 3, 5, 'Cone φ₀ (°):', 'Enable', 'off');      app.add('conePh', @uispinner, g, 3, 6, 'Limits', [0 360], 'Enable', 'off');
            app.addLabel('coneAngLabel', g, 3, 7, 'Cone Angle α (°):', 'Enable', 'off'); app.add('coneAng', @uispinner, g, 3, 8, 'Limits', [0 180], 'Value', 45, 'Enable', 'off');
            app.add('covClear', @uibutton, g, 3, 9, 'Text', '🧹 Clear DataTips', 'Enable', 'off', 'ButtonPushedFcn', C(@(~,~) app.covClear()));
            app.add('covToMain', @uibutton, g, 3, 10, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~,~) set(app.UI.tabs, 'SelectedTab', app.UI.mainTab));
            app.UI.covQueryCtl = [ ...   % heterogeneous handle array: build by concatenation
                app.addLabel('', g, 4, 3, 'Coverage @ dB:', 'Visible', 'off'), ...
                app.add('queryCov', @uispinner, g, 4, 4, 'ValueDisplayFormat', '%g dB', 'Visible', 'off'), ...
                app.add('', @uibutton, g, 4, 5, 'Text', '⯐ Query Coverage', 'Visible', 'off', 'ButtonPushedFcn', C(@(~,~) app.covQuery("cov"))), ...
                app.addLabel('', g, 4, 6, 'Threshold @ %:', 'Visible', 'off'), ...
                app.add('queryThr', @uispinner, g, 4, 7, 'ValueDisplayFormat', '%g%%', 'Value', 50, 'Visible', 'off'), ...
                app.add('', @uibutton, g, 4, 8, 'Text', '🔍 Query Threshold', 'Visible', 'off', 'ButtonPushedFcn', C(@(~,~) app.covQuery("thr")))];
            app.addLabel('covFmtLabel', g, 4, 9, 'Format:', 'Visible', 'off');
            app.add('covFmt', @uidropdown, g, 4, 10, app.TextFormatArgs{:}, 'Visible', 'off', 'ValueChangedFcn', C(@(~,~) app.covFormatChanged()));
            app.add('covStatus', @uilabel, G, 3, [1 5], 'Text', 'Ready 🚀', 'Interpreter', 'html');
            % --- Results -------------------------------------------------------------------------------------
            g = uigridlayout(app.add('covResults', @uipanel, G, 2, [1 5], 'Title', 'Results', 'Visible', 'off'), 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            ax = app.add('covAxes', @uiaxes, g, 1, [2 4]); title(ax, 'Coverage vs Threshold'); xlabel(ax, 'Threshold (dB)'); ylabel(ax, 'Coverage (%)'); ax.Interactions = dataTipInteraction;
            tree = app.add('covTree', @(p, varargin) uitree(p, 'checkbox', varargin{:}), g, [1 2], 1, 'SelectionChangedFcn', C(@(~,~) app.covSelectionChanged()), 'CheckedNodesChangedFcn', C(@(~,~) app.covCheckedChanged()));
            app.UI.covRoot = uitreenode(tree, 'Text', 'Coverage Results');
            app.add('covTable', @uitable, g, [1 2], 5, 'RowName', {});
            r = struct();
            r.min = app.add('', @uispinner, g, 2, 2, 'Limits', app.RangeBounds, 'Value', -40, 'ValueChangedFcn', C(@(s,~) app.onRangeInput("covx", s.Value, 1)));
            r.slider = app.add('', @(p, varargin) uislider(p, 'range', varargin{:}), g, 2, 3, 'Limits', app.RangeBounds, 'Value', [-40 10], 'ValueChangingFcn', C(@(~,e) app.onRangeInput("covx", e.Value, 0)));
            r.max = app.add('', @uispinner, g, 2, 4, 'Limits', app.RangeBounds, 'Value', 10, 'ValueChangedFcn', C(@(s,~) app.onRangeInput("covx", s.Value, 2)));
            app.UI.covRange = r;
        end
    end

    %% ==================================================================== self-test
    methods (Access = public)
        function report = runSelfTest(app)
            %RUNSELFTEST Deterministic numerical/policy checks (no UI interaction). Errors when any check fails.
            [P, T] = meshgrid(0:30:330, 0:30:180); G = table(T(:), P(:), 10*cosd(T(:)).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            w = solidWeights(G.Theta, G.Phi); omegaErr = abs(sum(w) - 4*pi);
            [~, pk, axisIndex] = calcOrientation(G.Theta, G.Phi, G.E_Total_dB, w, app.Axes, app.Peak);
            [P2, T2] = meshgrid(0:2:358, 0:2:180); S = table(T2(:), P2(:), 12*cosd(T2(:)).^2 - 0.5*sind(P2(:)).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            R = resampleCanonical(S, 1); native = mod(round(R.Theta), 2) == 0 & mod(round(R.Phi), 2) == 0 & R.Phi < 360;
            numErr = max(abs(R.E_Total_dB(native) - (12*cosd(R.Theta(native)).^2 - 0.5*sind(R.Phi(native)).^2)));
            spike = repmat(0.02, 100000, 1); spike(1) = 10.02; sp = resolvePeak(spike, app.Peak);
            ffd = [tempname '.ffd']; writelines(["0 180 3"; "-180 180 3"; compose("%d 0 0 1", (1:9)')], ffd); cleanup = onCleanup(@() delete(ffd)); %#ok<NASGU>
            ffdOut = readPattern(ffd, "ffd");
            checks = struct( ...
                'SolidAngle',           omegaErr < 1e-9, ...
                'Orientation',          isfinite(pk.value) && axisIndex >= 1 && axisIndex <= 6, ...
                'Resampling',           height(R) == 181*361 && all(isfinite(R.Theta)) && all(isfinite(R.Phi)), ...
                'NumericalEquivalence', isfinite(numErr) && numErr < 1e-10, ...
                'DisplayRange',         isequal(displayRange([3.2; -250; -17], [-50 0], app.Peak), [-45 5]), ...
                'PeakAwareRange',       isequal(displayRange(spike, [-50 0], app.Peak), [-45 5]), ...
                'IsolatedSpike',        sp.wasAdjusted && abs(sp.value - 0.02) < 1e-12 && sp.rawIndex == 1, ...
                'Percentile',           abs(percentile([1 2 3 4], 50) - 2.5) < 1e-12 && percentile([5 1 3], 100) == 5, ...
                'FFDReader',            strcmp(ffdOut.meta.source, 'HFSS FFD') && isscalar(ffdOut.blocks) && height(ffdOut.blocks{1}) == 9, ...
                'ARSemantic',           all(arrayfun(@(s) app.isAR(s), ["AR", "AR_dB", "AR dB", "Axial Ratio", "Axial_Ratio"])));
            names = fieldnames(checks); failed = names(~cellfun(@(f) checks.(f), names));
            report = checks; report.numericalError = numErr; report.solidAngleError = omegaErr; report.orientationIndex = axisIndex; report.pass = isempty(failed);
            if ~report.pass, error('apat:test:SelfTestFailed', 'Self-test failed: %s', strjoin(failed, ', ')); end
        end
    end
end

%% ======================================================================== file readers
function out = readPattern(fp, textFormat)
%READPATTERN Universal loader -> struct(rawTbl, blocks, freqs, meta).  blocks{k} is a canonical table
%   {Theta,Phi,Re_Eth,Im_Eth,Re_Eph,Im_Eph} (E-field sources) or {Theta,Phi,<gain columns>} (gain-only).
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, 'meta', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false));
switch ext
    case {'XLSX', 'XLS'},        out = readExcelMatrix(fp);
    case {'CSV', 'TXT', 'DAT'},  out = readGenericText(fp, string(textFormat), out);
    case 'CUT',                  out = readGraspCut(fp, out);
    case 'FFD',                  out = readFFD(fp, out);
    case {'FZ', 'UAN', 'OUT', 'FFS', 'FFE'}, out = readFarFieldTable(fp, ext, out);
    otherwise, error('readFile:unsupported', 'Unsupported format: %s', ext);
end
if out.meta.isGainOnly, out.meta.quantityType = "gain-like"; else, out.meta.quantityType = "complex-electric-field"; end
end

function out = readFarFieldTable(fp, ext, out)
% Six-column far-field exports: XGTD UAN/FZ (dB + phase), GRASP OUT (RHCP/LHCP re/im), CST FFS and FEKO FFE (re/im).
M = readNumeric(fp, countHeaderLines(fp));
assert(size(M, 2) >= 6, 'readFile:columns', '%s files need six numeric columns.', ext);
switch ext
    case {'FZ', 'UAN'}, src = ['XGTD ' ext];    names = {'Theta','Phi','E_TH_dB','E_PH_dB','E_TH_deg','E_PH_deg'}; tp = M(:, 1:2);   Eth = dbPhase(M(:, 3), M(:, 5)); Eph = dbPhase(M(:, 4), M(:, 6));
    case 'OUT',         src = 'TICRA/GRASP OUT'; names = {'Theta','Phi','Re_RHCP','Im_RHCP','Re_LHCP','Im_LHCP'}; tp = M(:, 1:2);   [Eth, Eph] = circularToLinear(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)));
    case 'FFS',         src = 'CST FFS';         names = {'Phi','Theta','Re_Eth','Im_Eth','Re_Eph','Im_Eph'};     tp = M(:, [2 1]); Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
    case 'FFE',         src = 'FEKO FFE';        names = {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'};     tp = M(:, 1:2);   Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
end
out.meta.source = src; out.rawTbl = array2table(M(:, 1:6), 'VariableNames', names); out.blocks = {fieldTable(tp(:, 1), tp(:, 2), Eth, Eph)};
end

function out = readFFD(fp, out)
% HFSS FFD: "θstart θstop Nθ" / "φstart φstop Nφ" [/ "Frequencies ..."], then Re/Im(Eθ) Re/Im(Eφ) rows, one block per
% frequency; "Frequency <f>" separator rows may precede blocks.  θ is the outer loop, φ the inner one.
out.meta.source = 'HFSS FFD';
lines = readlines(fp); lines = lines(strlength(strtrim(lines)) > 0);
t = sscanf(lines(1), '%f'); p = sscanf(lines(2), '%f');
assert(numel(lines) >= 3 && numel(t) == 3 && numel(p) == 3, 'readFile:ffd', 'FFD header (theta/phi ranges) not found.');
theta = linspace(t(1), t(2), round(t(3))).'; phi = linspace(p(1), p(2), round(p(3))).'; nHdr = 2; freqs = [];
tok = regexp(strtrim(lines(3)), '^frequencies?\s+(.+)$', 'tokens', 'once', 'ignorecase');
if ~isempty(tok), nHdr = 3; f = sscanf(tok{1}, '%f'); if ~isscalar(f), freqs = f(:).'; end, end   % a scalar is only a count
rest = cellstr(lines(nHdr+1:end)); isSep = ~cellfun(@isempty, regexp(rest, '^\s*[A-Za-z]', 'once'));
sepFreqs = str2double(regexp(rest(isSep), '[-+\d.eE]+', 'match', 'once')); sepFreqs = sepFreqs(isfinite(sepFreqs));
F = sscanf(strjoin(rest(~isSep), ' '), '%f'); assert(mod(numel(F), 4) == 0, 'readFile:ffd', 'FFD data rows must hold four values.');
F = reshape(F, 4, []).'; n = numel(theta)*numel(phi);
assert(mod(size(F, 1), n) == 0, 'readFile:ffd', 'FFD mismatch: row count does not match the theta/phi grid.');
nb = size(F, 1)/n; freqs = [freqs(:); sepFreqs(:)].'; out.meta.isDep = nb > 1 || ~isempty(freqs);
freqs(end+1:nb) = NaN; freqs = freqs(1:nb);
th = repelem(theta, numel(phi)); ph = repmat(phi, numel(theta), 1); out.blocks = cell(1, nb);
for b = 1:nb, rows = (b-1)*n + (1:n); out.blocks{b} = fieldTable(th, ph, complex(F(rows, 1), F(rows, 2)), complex(F(rows, 3), F(rows, 4))); end
out.freqs = freqs; out.rawTbl = out.blocks{1};
end

function out = readGenericText(fp, textFormat, out)
% CSV/TXT/DAT: a coverage-results table, a gain-only pattern, or one of the six-column E-field layouts.
opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvartype(opts, 'double'); opts = setvaropts(opts, 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
T = rmmissing(readtable(fp, opts)); nCol = width(T);
assert(nCol >= 2 && ~isempty(T), 'readFile:InvalidFormat', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHeaders = ~all(startsWith(names, "Var")); raw = T; c1 = T{:, 1}; c2 = T{:, 2};
coverageHeader = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
if (textFormat == "gain" || nCol < 6 || coverageHeader) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:nCol-1))]; end
    out.rawTbl = T; out.meta.isCoverage = true; return
end
if textFormat == "gain"     % the two angle columns come first; the wider span is φ
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    T = movevars(T, 'Theta', 'Before', 1); if ~hasHeaders, raw = T; end
    out.rawTbl = raw; out.blocks = {T}; out.meta.isGainOnly = true; return
end
assert(nCol >= 6, 'readFile:TextEFieldColumns', 'The selected generic E-field format requires six numeric columns.');
V = T{:, 3:6}; magPhase = endsWith(textFormat, "magphase"); layout = "not applicable";
if magPhase     % grouped [m1 m2 p1 p2] unless column 2 looks like a phase and column 3 does not (interleaved [m1 p1 m2 p2])
    big = max(abs(V), [], 1, 'omitnan') > 100;
    if big(2) && ~big(3), [m1, p1, m2, p2] = deal(1, 2, 3, 4); layout = "interleaved"; else, [m1, p1, m2, p2] = deal(1, 3, 2, 4); layout = "grouped"; end
    A = dbPhase(V(:, m1), V(:, p1)); B = dbPhase(V(:, m2), V(:, p2));
else
    A = complex(V(:, 1), V(:, 2)); B = complex(V(:, 3), V(:, 4));
end
if startsWith(textFormat, "linear"), Eth = A; Eph = B; comps = ["E_TH", "E_PH"]; reim = ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"];
else
    if startsWith(textFormat, "rcp"), [Eth, Eph] = circularToLinear(A, B); else, [Eth, Eph] = circularToLinear(B, A); end
    comps = ["POL1", "POL2"]; reim = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"];
end
if magPhase, gen = [comps + "_dB", comps + "_deg"]; if layout == "interleaved", gen = gen([1 3 2 4]); end, else, gen = reim; end
if ~hasHeaders, raw.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", gen]); end
out.meta.source = sprintf('Generic text (%s, %s)', textFormat, layout); out.rawTbl = raw; out.blocks = {fieldTable(c1, c2, Eth, Eph)};
end

function out = readGraspCut(fp, out)
% TICRA GRASP .cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks (one φ per block).
out.meta.source = 'TICRA/GRASP CUT';
lines = readlines(fp); lines(strlength(strtrim(lines)) == 0) = [];
th = {}; ph = {}; D = {}; k = 1; icomp = 1; icut = 1;
while k < numel(lines)
    p = sscanf(lines(k+1), '%f'); assert(numel(p) >= 7, 'parseCutFile:bad', 'Could not parse cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6);
    block = reshape(sscanf(strjoin(lines(k+2:k+1+n), ' '), '%f'), 2*p(7), []).';
    th{end+1, 1} = p(1) + (0:n-1)'*p(2); ph{end+1, 1} = repmat(p(4), n, 1); D{end+1, 1} = block(:, 1:4); k = k + 2 + n; %#ok<AGROW>
end
th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:});
if icut == 2, [th, ph] = deal(ph, th); end                       % ICUT=2: φ swept, θ constant
neg = th < 0; ph(neg) = ph(neg) + 180; th(neg) = -th(neg);         % fold negative θ onto the opposite φ
if isscalar(unique(ph))                                             % single cut -> body of revolution
    copies = (0:10:350)'; m = numel(th); th = repmat(th, numel(copies), 1); ph = repelem(copies, m); D = repmat(D, numel(copies), 1);
end
A = complex(D(:, 1), D(:, 2)); B = complex(D(:, 3), D(:, 4));
if icomp == 2, names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; [Eth, Eph] = circularToLinear(A, B);
else, names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; Eth = A; Eph = B; end
out.rawTbl = array2table([th ph D], 'VariableNames', [{'Theta', 'Phi'}, names]); out.blocks = {fieldTable(th, ph, Eth, Eph)};
end

function out = readExcelMatrix(fp)
% Excel matrix templates: sheet 1 = summary; fixed component sheets hold C3-origin dBi/phase matrices
% (row 2 = φ axis from column C, column B = θ axis from row 3).
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"];
lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'readFile:ExcelMatrixFormat', 'Unsupported Excel workbook: expected the fixed Eth/Eph and/or RHCP/LHCP component sheets after the summary sheet.');
required = [circ(1:4*hasC), lin(1:4*hasL)]; M = struct(); theta = []; phi = [];
for name = required
    [t, p, data] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, name), 1)));
    if isempty(theta), theta = t; phi = p;
    else, assert(isequal(size(t), size(theta)) && isequal(size(p), size(phi)) && max(abs(t - theta)) < 1e-9 && max(abs(p - phi)) < 1e-9, ...
            'readFile:ExcelMatrixGrid', 'All Excel Matrix component sheets must use the same theta/phi grid.'); end
    M.(name) = data;
end
if hasL, Eth = dbPhase(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = dbPhase(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees); basis = "theta-phi";
else, [Eth, Eph] = circularToLinear(dbPhase(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), dbPhase(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees)); basis = "RHCP/LHCP"; end
if hasL && hasC, basis = "theta-phi + RHCP/LHCP"; end
[P, T] = meshgrid(phi, theta); block = fieldTable(T(:), P(:), Eth(:), Eph(:)); raw = block;
for name = required, raw.(name) = M.(name)(:); end
formats = {'Excel Matrix Format 2 (Ercp/Elcp)', 'Excel Matrix Format 1 (Eth/Eph)', 'Excel Matrix Format 3 (Ercp/Elcp + Eth/Eph)'};
meta = readExcelSummary(fp, sheets(1));
meta.source = formats{hasC + 2*hasL}; meta.isGainOnly = false; meta.isCoverage = false; meta.isDep = false; meta.polarizationBasis = basis; meta.componentSheets = cellstr(required);
freq = NaN; if isfield(meta, 'frequencyMHz') && isfinite(meta.frequencyMHz), freq = meta.frequencyMHz*1e6; end
out = struct('rawTbl', raw, 'blocks', {{block}}, 'freqs', freq, 'meta', meta);
end

function [theta, phi, data] = readMatrixSheet(fp, sheet)
% readcell keeps worksheet coordinates (readmatrix would auto-trim the C3 origin).  Axes must be contiguous and increasing.
C = readcell(fp, 'Sheet', char(sheet));
assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'readFile:ExcelMatrixSheet', 'Sheet "%s" does not contain a C3-origin matrix.', sheet);
isNum = @(cells) cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), cells);
pm = isNum(C(2, 3:end)); tm = isNum(C(3:end, 2));
assert(any(pm) && any(tm) && all(pm(1:find(pm, 1, 'last'))) && all(tm(1:find(tm, 1, 'last'))), 'readFile:ExcelMatrixAxis', 'Sheet "%s" has missing or gapped theta/phi axes.', sheet);
phi = cell2mat(C(2, 2 + (1:nnz(pm)))); theta = cell2mat(C(2 + (1:nnz(tm)), 2)); cells = C(2 + (1:numel(theta)), 2 + (1:numel(phi)));
assert(all(isNum(cells), 'all'), 'readFile:ExcelMatrixSheet', 'Sheet "%s" contains nonnumeric/missing matrix samples.', sheet);
data = cell2mat(cells); theta = theta(:); phi = phi(:);
assert(all(diff(theta) > 0) && all(diff(phi) > 0) && theta(1) >= -1e-9 && theta(end) <= 180 + 1e-9 && phi(1) >= -1e-9 && phi(end) < 360 + 1e-9, ...
    'readFile:ExcelMatrixAxis', 'Sheet "%s" axes must be increasing within theta 0..180 and phi 0..360.', sheet);
end

function meta = readExcelSummary(fp, sheet)
% Summary sheet: every "Label:" in column B with its first value in C..E becomes meta.(key); the simulation frequency is normalized.
meta = struct();
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
isBlank = @(v) isempty(v) || isa(v, 'missing') || (isnumeric(v) && all(isnan(v), 'all'));
for r = 1:size(C, 1)
    lab = C{r, 2}; if ~(ischar(lab) || isstring(lab)) || strlength(strtrim(string(lab))) == 0, continue; end
    vals = C(r, 3:min(5, size(C, 2))); vals = vals(~cellfun(isBlank, vals)); if isempty(vals), continue; end
    key = regexprep(lower(replace(strtrim(string(lab)), char(160), ' ')), '\s+', ' ');
    meta.(matlab.lang.makeValidName(char(key))) = vals{1};
    if startsWith(key, "pattern simulation freq"), meta.frequencyMHz = toDouble(vals{1}); end
end
end

function v = toDouble(v)
if isnumeric(v) && ~isempty(v), v = double(v(1)); elseif ischar(v) || isstring(v), v = str2double(strtrim(string(v))); else, v = NaN; end
end

function n = countHeaderLines(fp)
% Leading non-data lines: data starts at the first line holding at least four numeric fields.
lines = readlines(fp); n = numel(lines);
for k = 1:numel(lines)
    if numel(sscanf(char(regexprep(lines(k), '[,;]', ' ')), '%f')) >= 4, n = k - 1; return; end
end
end

function M = readNumeric(fp, nHdr)
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvartype(opts, 'double'); M = readmatrix(fp, opts); M = M(~all(isnan(M), 2), :);
end

function E = dbPhase(dB, deg), E = 10.^(dB/20) .* exp(1i*deg2rad(deg)); end
function [Eth, Eph] = circularToLinear(Ercp, Elcp), Eth = (Ercp + Elcp)/sqrt(2); Eph = (Ercp - Elcp)/(1i*sqrt(2)); end
function tf = isGenericText(fp), [~, ~, e] = fileparts(fp); tf = any(strcmpi(e, {'.csv', '.txt', '.dat'})); end

function T = fieldTable(theta, phi, Eth, Eph)
T = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function writeUAN(T, fp)
% XGTD UAN: canonical parameter header followed by tab-separated magnitude/phase rows.
header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
    min(T.Phi), max(T.Phi), gridStep(mod(T.Phi, 360)), min(T.Theta), max(T.Theta), gridStep(T.Theta), max([T.E_TH_DB; T.E_PH_DB], [], 'omitnan'));
writelines(header, fp); writetable(T, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
end

%% ======================================================================== numerical core
function T = normalizePattern(T)
%NORMALIZEPATTERN Map angles onto the canonical sphere: θ in [0,180], φ in [0,360] with the φ=360 seam duplicated once.
theta = T.Theta;
if any(theta < 0)
    if min(theta, [], 'omitnan') >= -90 && max(theta, [], 'omitnan') <= 90, T.Theta = 90 - theta;   % elevation source
    else, m = theta < 0; T.Theta(m) = -theta(m); T.Phi(m) = T.Phi(m) + 180; end                      % negative θ = opposite φ
end
T.Theta = mod(T.Theta, 360); over = T.Theta > 180; T.Theta(over) = 360 - T.Theta(over); T.Phi(over) = T.Phi(over) + 180;
num = varfun(@isnumeric, T, 'OutputFormat', 'uniform'); T{:, num} = round(T{:, num}, 5);   % deterministic 5-decimal grid removes seam round-off
T.Theta = mod(T.Theta, 360); over = T.Theta > 180; T.Theta(over) = 360 - T.Theta(over); T.Phi = mod(T.Phi, 360);
T.Theta(abs(T.Theta) < 1e-12) = 0; T.Phi(abs(T.Phi) < 1e-12) = 0;
[~, u] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(u, :);
seam = T(abs(T.Phi) < 1e-10, :); seam.Phi(:) = 360; T = [T; seam];
end

function [P, info] = calcPattern(S, param)
%CALCPATTERN Canonical source -> processed table (gains, signed AR, PLF, link quantities) + polarization summary.
meta = S.Properties.UserData; info = struct('pol', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
if meta.isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + param.GainLoss_dB; end
    return
end
Eth = complex(S.Re_Eth, S.Im_Eth)*param.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph)*param.FieldScale;
Ercp = (Eth + 1i*Eph)/sqrt(2); Elcp = (Eth - 1i*Eph)/sqrt(2);
[mTh, mPh, mR, mL] = deal(abs(Eth), abs(Eph), abs(Ercp), abs(Elcp)); total = 10*log10(max(mTh.^2 + mPh.^2, eps));
% Mean component powers decide co/cross ordering, the polarization label and the Auto Rx sense.
pw = [mean(mTh.^2, 'omitnan'), mean(mPh.^2, 'omitnan'), mean(mR.^2, 'omitnan'), mean(mL.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif pw(1) >= pw(2), info.pol = 'Linear (Vertical)'; else, info.pol = 'Linear (Horizontal)'; end
% Signed axial ratio (+ right-hand, - left-hand); equal circular components are the linear limit (-100 dB floor).
delta = mR - mL; sense = sign(delta); sense(~isfinite(delta)) = 0; ar = (mR + mL)./max(abs(delta), eps);
signedAR = min(20*log10(ar), 250).*sense; signedAR(isfinite(delta) & abs(delta) <= eps*max(mR + mL, 1)) = -100;
% Polarization loss factor against an incident wave of axial ratio RxAR_dB with the selected (or dominant) sense.
switch param.RxMode
    case "RHCP", ws = 1;
    case "Auto", ws = 2*(info.pairs.Circular(1) == "E_RCP") - 1;
    otherwise,   ws = -1;
end
ra = ar.*sense; ra(sense == 0) = 1e12; rw = ws*10^(param.RxAR_dB/20);
plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1))./(2*(ra.^2 + 1)*(rw^2 + 1)); plfDB = 10*log10(min(max(plf, eps), 1));
eirp = param.Pt_dBW + total; eirpW = 10.^(eirp/10);
P = table(S.Theta, S.Phi, total, signedAR, 20*log10(max(mR, eps)), 20*log10(max(mL, eps)), plfDB, total + plfDB, 20*log10(max(mTh, eps)), 20*log10(max(mPh, eps)), ...
    rad2deg(angle(Eth)), rad2deg(angle(Eph)), rad2deg(angle(Ercp)), rad2deg(angle(Elcp)), eirp, eirpW/(4*pi*param.R_m^2), sqrt(30*eirpW)/param.R_m, ...
    'VariableNames', {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', 'PLF_dB', 'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', ...
    'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
P.Properties.UserData = meta;
end

function R = resampleCanonical(S, step)
%RESAMPLECANONICAL Resample a canonical source onto a STEP° grid (θ 0..180, φ 0..360 including the seam).
%   E-field sources interpolate Re/Im; gain-only sources interpolate linear power.  Regular grids use
%   periodic interp2, irregular samples fall back to scatteredInterpolant.
names = string(S.Properties.VariableNames(3:end)); theta = S.Theta; phi = mod(S.Phi, 360);
keep = find(isfinite(theta) & isfinite(phi) & theta >= -1e-9 & theta <= 180 + 1e-9 & abs(S.Phi - 360) > 1e-9);
[~, u] = unique([theta(keep) phi(keep)], 'rows', 'stable'); idx = keep(u); theta = theta(idx); phi = phi(idx);
[qPhi, qTheta] = meshgrid(unique([0:step:360, 360]), 0:step:180); R = table(qTheta(:), qPhi(:), 'VariableNames', {'Theta', 'Phi'});
isGain = ~all(ismember(["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"], names));
[st, ~, it] = unique(theta); [sp, ~, ip] = unique(phi); regular = numel(st)*numel(sp) == numel(theta);
for name = names
    v = double(S.(name)(idx)); if isGain, v = 10.^(v/10); end
    if regular
        G = nan(numel(st), numel(sp)); G(sub2ind(size(G), it, ip)) = v; G(:, end+1) = G(:, 1);      %#ok<AGROW> periodic φ closure
        [PG, TG] = meshgrid([sp; sp(1) + 360], st); q = interp2(PG, TG, G, qPhi, qTheta, 'linear', NaN);
        miss = ~isfinite(q); if any(miss, 'all'), nn = interp2(PG, TG, G, qPhi, qTheta, 'nearest', NaN); q(miss) = nn(miss); end
    else
        F = scatteredInterpolant(phi, theta, v, 'linear', 'nearest'); q = F(qPhi, qTheta);
    end
    if isGain, q = 10*log10(max(q, realmin)); end
    R.(name) = q(:);
end
R.Properties.UserData = S.Properties.UserData;
end

function [w, peak, k] = calcOrientation(theta, phi, gain, w, axes, policy)
%CALCORIENTATION Outlier-aware peak and the principal axis whose 45° cone holds the most weighted energy.
if isempty(w) || numel(w) ~= numel(theta), w = solidWeights(theta, phi); end
peak = resolvePeak(gain, policy); if peak.wasAdjusted, gain(peak.outlierMask) = NaN; end
sw = 10.^((gain - peak.value)/10).*w; sw(~isfinite(sw)) = 0;
A = [sind(axes.theta(:)).*cosd(axes.phi(:)), sind(axes.theta(:)).*sind(axes.phi(:)), cosd(axes.theta(:))];
V = [sind(theta).*cosd(phi), sind(theta).*sind(phi), cosd(theta)];
[~, k] = max(sw.' * double(V*A.' >= cosd(45)));
end

function m = calcMetrics(T, theta, w, axes, policy)
%CALCMETRICS Scalar metrics from total gain: peak, HPBW in the E/H planes of the boresight axis, F/B, directivity, efficiency.
gain = chooseGain(T, 'E_Total_dB'); peak = resolvePeak(gain, policy); i = peak.index;
g = gain; if peak.wasAdjusted, g(peak.outlierMask) = NaN; end
integrated = sum(10.^(g/10).*w, 'omitnan'); directivity = 10*log10(max(4*pi*10^(peak.value/10)/max(integrated, eps), eps));
eff = 100*integrated/(4*pi); if eff < 0 || eff > 100, eff = NaN; end
[~, back] = min(cosd(theta)*cosd(theta(i)) + sind(theta)*sind(theta(i)).*cosd(T.Phi - T.Phi(i)));
k = axes.index; hType = "Theta"; if axes.theta(k) == 90, hType = "Phi"; end
[eAng, eRows] = calcCutGeometry(theta, T.Phi, "Theta", axes.phi(k)); [hAng, hRows] = calcCutGeometry(theta, T.Phi, hType, 90);
ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(i); end
m = struct('PeakGain_dB', peak.value, 'PeakTheta_deg', theta(i), 'PeakPhi_deg', mod(T.Phi(i), 360), 'HPBW_EPlane_deg', calcHPBW(eAng, gain(eRows)), ...
    'HPBW_HPlane_deg', calcHPBW(hAng, gain(hRows)), 'FrontBack_dB', peak.value - gain(back), 'PeakDirectivity_dB', directivity, 'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', ar);
end

function [angle, rows, fixed, sym, snapped] = calcCutGeometry(theta, phi, type, req)
%CALCCUTGEOMETRY Rows of one full-circle cut snapped to the nearest sampled plane, ordered by cut angle.
%   "Phi" cut: fixed θ, angle = φ.  "Theta" cut: fixed φ, angle = θ on φ (0..180) continuing on φ+180 (180..360).
if type == "Phi"
    values = unique(theta); [dist, k] = min(abs(values - req)); fixed = values(k);
    rows = find(abs(theta - fixed) < 1e-9); [angle, o] = sort(phi(rows)); rows = rows(o); sym = 'θ';
else
    values = unique(mod(phi, 360)); wrapped = mod(phi, 360);
    [dist, k] = min(abs(mod(values - mod(req, 360) + 180, 360) - 180)); fixed = values(k); [~, ko] = min(abs(mod(values - fixed, 360) - 180));
    primary = find(abs(wrapped - fixed) < 1e-9); opposite = find(abs(wrapped - values(ko)) < 1e-9 & abs(theta - 180) > 1e-9);
    [~, o1] = sort(theta(primary)); [~, o2] = sort(theta(opposite), 'descend'); primary = primary(o1); opposite = opposite(o2);
    rows = [primary; opposite]; angle = [theta(primary); 360 - theta(opposite)]; sym = 'φ';
end
snapped = dist > 0;
end

function [bw, lower, upper] = calcHPBW(angle, gain, peakGain, peakAngle)
%CALCHPBW Half-power beamwidth of a circular cut with linear interpolation of the -3 dB crossings.
[bw, lower, upper] = deal(NaN); valid = isfinite(angle) & isfinite(gain); angle = angle(valid); gain = gain(valid);
if numel(gain) < 3, return; end
if nargin < 3 || isempty(peakGain), [peakGain, i] = max(gain); peakAngle = angle(i); end
half = peakGain - 3; [rel, o] = sort(mod(angle - peakAngle + 180, 360) - 180); g = gain(o);
L = find(rel < 0 & g <= half, 1, 'last'); Rr = find(rel > 0 & g <= half, 1, 'first');
if isempty(L) || isempty(Rr) || L + 1 > numel(g) || Rr - 1 < 1, return; end
gl = g([L L+1]); gr = g([Rr Rr-1]); if diff(gl) == 0 || diff(gr) == 0, return; end
left = rel(L) + diff(rel([L L+1]))*(half - gl(1))/diff(gl); right = rel(Rr) + diff(rel([Rr Rr-1]))*(half - gr(1))/diff(gr);
lower = peakAngle + left; upper = peakAngle + right; bw = right - left;
end

function info = resolvePeak(values, policy)
%RESOLVEPEAK Authoritative peak: the raw maximum unless it exceeds the P-th percentile by more than
%   policy.maxExcessDB, in which case the highest sample at/below the percentile is used (isolated spikes).
info = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(values)), 'wasAdjusted', false);
finite = isfinite(values); if ~any(finite), return; end
[info.rawValue, info.rawIndex] = max(values, [], 'omitnan'); info.value = info.rawValue; info.index = info.rawIndex;
p = percentile(values(finite), policy.percentile);
if info.rawValue > p + policy.maxExcessDB
    info.outlierMask = finite & values > p; candidates = values; candidates(~finite | info.outlierMask) = -Inf;
    if any(candidates > -Inf), [info.value, info.index] = max(candidates); info.wasAdjusted = true; else, info.outlierMask(:) = false; end
end
end

function v = percentile(x, p)
%PERCENTILE Same definition as prctile (linear interpolation between order statistics at 100*(k-0.5)/n) without a toolbox.
x = sort(x(:)); n = numel(x); if n == 0, v = NaN; return; end
pos = p/100*n + 0.5; lo = min(max(floor(pos), 1), n); hi = min(max(ceil(pos), 1), n);
v = x(lo) + (pos - floor(pos))*(x(hi) - x(lo));
end

function b = displayRange(values, default, policy)
%DISPLAYRANGE 50-dB window ending at the effective (outlier-aware) peak rounded up to 5 dB, clamped to [-250,100].
values = double(values(isfinite(values))); if isempty(values), b = default; return; end
peak = resolvePeak(values, policy).value; if ~isfinite(peak), b = default; return; end
top = min(100, ceil(peak/5)*5); b = [max(-250, top - 50), top]; if diff(b) < 1, b(2) = b(1) + 1; end
end

function coverage = coverageCCDF(gain, region, thresholds, w)
%COVERAGECCDF Coverage(T) [%] = 100 * sum(I(G_i > T) * Omega_i) / Omega_region, for every threshold at once.
gain = double(gain(:)); w = double(w(:)); thresholds = double(thresholds(:));
valid = logical(region(:)) & isfinite(gain) & isfinite(w) & w >= 0; total = sum(w(valid));
coverage = zeros(size(thresholds)); if total <= 0, return; end
coverage = 100 * (w(valid).' * double(gain(valid) > thresholds.')).' / total;
end

function w = solidWeights(theta, phi)
%SOLIDWEIGHTS Exact solid angle of each uniform θ/φ cell; the duplicated closing φ seam gets zero weight.
dt = gridStep(theta); if ~isfinite(dt), dt = 180; end
dp = gridStep(mod(phi, 360)); if ~isfinite(dp), dp = 360; end
w = (cosd(max(theta - dt/2, 0)) - cosd(min(theta + dt/2, 180)))*deg2rad(dp);
seam = 360; if any(phi < 0), seam = 180; end
w(abs(phi - seam) < 1e-9) = 0;
end

function [g, col] = chooseGain(T, requested)
%CHOOSEGAIN Requested column if present, else E_Total_dB, else the first data column.
vars = T.Properties.VariableNames; c = [string(requested), "E_Total_dB"]; k = find(ismember(c, vars), 1);
if isempty(k), col = vars{3}; else, col = char(c(k)); end
g = T.(col);
end

function step = gridStep(values)
%GRIDSTEP Smallest positive spacing between distinct finite values (NaN when undefined).
d = diff(unique(values(isfinite(values)))); d = d(d > 1e-9);
if isempty(d), step = NaN; else, step = min(d); end
end

function r = clampRange(values, bounds, minGap)
%CLAMPRANGE Sorted [lo hi] inside BOUNDS with at least MINGAP between the ends.
r = sort(double(values(:).')); if numel(r) < 2 || any(~isfinite(r(1:2))), r = bounds; return; end
r = [max(bounds(1), r(1)), min(bounds(2), r(2))];
if diff(r) < minGap, r(2) = min(bounds(2), r(1) + minGap); r(1) = max(bounds(1), r(2) - minGap); end
end

function t = axisTicks(limits, step)
%AXISTICKS Ticks at multiples of STEP inside LIMITS plus both ends; empty when STEP is unusable or too dense.
t = []; if ~isfinite(step) || step <= 0 || diff(limits) <= 0, return; end
t = unique([limits(1), ceil(limits(1)/step)*step:step:floor(limits(2)/step)*step, limits(2)]);
if numel(t) > 60, t = []; end
end

function y = safeInterp(x, v, q)
%SAFEINTERP Linear interpolation that returns NaN instead of erroring on degenerate (<2 point) curves.
if numel(x) < 2, y = nan(size(q)); else, y = interp1(x, v, q, 'linear', NaN); end
end

function [x, y, z] = pointAt(h, index, polar)
%POINTAT Coordinates of sample/grid INDEX on a line or surface (INDEX addresses CData for surfaces).
if polar && isprop(h, 'ThetaData'), X = h.ThetaData; Y = h.RData; Z = [];
else, X = h.XData; Y = h.YData; Z = h.ZData; end
if isvector(X) && isvector(Y) && ~isempty(Z) && ~isvector(Z), [X, Y] = meshgrid(X, Y); end   % pcolor keeps vector axes
index = min(max(1, round(index)), numel(X)); x = X(index); y = Y(index);
if isempty(Z), z = 0; elseif isequal(size(Z), size(X)), z = Z(index); else, z = Z(min(index, numel(Z))); end
end

function s = fmt(v, precision)
%FMT Compact number text: up to two decimals without trailing zeros, or exactly PRECISION decimals; non-finite -> 'n/a'.
if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); else, s = sprintf('%.*f', precision, v); end
end

function place(h, row, col)
h.Layout.Row = row; h.Layout.Column = col;
end