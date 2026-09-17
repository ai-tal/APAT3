classdef APAT_v3_M8_12 < matlab.apps.AppBase %1612-lines %Issues: %1. Rotation interaction not working on 3D plots %2. Interactive DatTip cursor not showing Custom DataTips on Contour Plot & Fisheye Plot %3. DatTip Context menu callback not working (MATLAB Workspace showing "Warning: You cannot set 'ContextMenu' property of DataTip") %4. Coverage Threshold Query snaps to nearest Data Point instead of returning requested point! %5. When user change Coverage Cone coordinate while Conical Coverage Orientation drop-down on Auto, it remains on Auto thus computing Auto Coverage instead of adjusted Cone value!
% APAT v3 M8 — Antenna Pattern Analyzer Tool (single-file App Designer class).
%
% One processed table drives everything:
%   file → readPattern → normalizePattern (canonical θ∈[0,180], φ∈[0,360] with one closing φ=360 seam)
%        → [resampleTo1deg] → calcPattern → app.pat
%        → lazy grid cache → renderers, cuts, metrics, exports, coverage.
% Display conventions (θ span, φ span) are applied only at draw/table time through
% dispTheta/dispPhi; the data model is never rewritten to express a view.
%
% Public surface: APAT_v3_M8() constructor, runSelfTest(), closeRequest(), delete().

    properties (Access = public)
        UIFigure matlab.ui.Figure
        ui struct = struct()   % Every widget handle (built once in buildUI)
    end

    properties (Access = private)
        file struct = struct('path','','folder','','base','','name','')
        src struct = struct()  % Reader output: raw, blocks, freqs, meta
        std table              % Canonical source table of the selected block
        pat table              % Processed pattern at the selected step (canonical angles)
        info struct = struct('POB',NaN,'POBth',NaN,'POBph',NaN,'pol','n/a','peak',struct(), ...
                             'pairs',struct('Linear',["E_TH","E_PH"],'Circular',["E_RCP","E_LCP"]))
        grid struct = struct() % Lazy cache: th, ph, sz, idx, geom, comps.<column>
        metrics struct = struct()
        omega double = []      % Solid-angle weight of every row of app.pat
        boresight double = 1   % Index into Axes
        rev double = 0         % Increments on every process(); tags coverage presets
        lim struct = struct('gain',[-40 10],'full',[-40 10],'cut',[-40 10]) % gain = non-AR memory, full = shown
        cov struct = struct('runID',0,'presetKey','','thrInit',false,'plotInit',false)
        paxCut                 % Polar cut axes
        paxPattern             % Circular (fisheye) contour axes
        statusTimer = []
        dlg = []               % Active cancelable progress dialog
        isClosing logical = false
        filterStyles cell = {}
        defaults struct = struct('loss',0,'rxPol','Auto','rw',6,'pt',0,'ptUnit','dBW','dist',1,'distUnit','m')
    end

    properties (Constant, Access = private)
        Axes = struct('labels',{{'+Z','-Z','+X','-X','+Y','-Y'}},'theta',[0 180 90 90 90 90],'phi',[0 0 0 180 90 270])
        Hidden = ["E_TH_dB","E_PH_dB","E_TH_Phase","E_PH_Phase","E_RCP_Phase","E_LCP_Phase","EIRP_dBW","PFD_Wm2","E_RMS_Vm"]
        TextFormats = {'1: Gain Pattern','2: Etheta/Ephi — dB magnitude, phase','3: Etheta/Ephi — real, imaginary', ...
            '4: POL1=RCP, POL2=LCP — dB magnitude, phase','5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
            '6: POL1=RCP, POL2=LCP — real, imaginary','7: POL1=LCP, POL2=RCP — real, imaginary'}
        TextFormatCodes = {'gain','linear_magphase','linear_reim','rcp_lcp_magphase','lcp_rcp_magphase','rcp_lcp_reim','lcp_rcp_reim'}
        FileFilter = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt','Pattern / coverage files'; '*.*','All files'}
        ExportFilter = {'*.csv','Comma-delimited (*.csv)'; '*.txt','Tab-delimited (*.txt)'; '*.xlsx','Excel (*.xlsx)'}
        PeakPct = 99.99        % Peak policy: percentile …
        PeakExcess = 6         % … and maximum excess (dB) above it before a sample is treated as a spike
        DBRange = [-250 100]   % Absolute limits of every dB range control
        Version = '3.0-M8'
    end

    %% ------------------------------------------------------------------ lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_12
            buildUI(app)
            registerApp(app, app.UIFigure)
            runStartupFcn(app, @startup)
            if nargout == 0, clear app, end
        end

        function closeRequest(app, ~)
            delete(app);
        end

        function delete(app)
            if app.isClosing, return, end
            app.isClosing = true; app.stopTimer();
            if ~isempty(app.dlg) && isvalid(app.dlg), delete(app.dlg); end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end
    end

    methods (Access = private)
        function startup(app)
            u = app.ui;
            app.paxCut = polaraxes(u.gridPolar); app.paxCut.Layout.Row = [1 4]; app.paxCut.Layout.Column = 3;
            app.paxPattern = polaraxes(u.gridCircular); app.paxPattern.Layout.Row = [1 3]; app.paxPattern.Layout.Column = 2;
            set([app.paxCut, app.paxPattern], 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            for ax = [u.axCtr, u.axRect], ax.Interactions = [zoomInteraction, dataTipInteraction]; end
            for ax = [u.axSph, u.axPol, u.axRect3], ax.Interactions = [rotateInteraction, dataTipInteraction]; end
            % One context menu per axes, created once (M7 created a new menu on every render).
            axesList = {u.axCtr, u.axRect, u.axSph, u.axPol, u.axRect3, app.paxCut, app.paxPattern};
            for k = 1:numel(axesList)
                ax = axesList{k}; menu = uicontextmenu(app.UIFigure);
                uimenu(menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~,~) delete(findall(ax, 'Type', 'datatip', 'Tag', '')));
                ax.ContextMenu = menu;
            end
            % Range groups: all full-pattern tabs mirror one scale; the cut owns a second one.
            set(u.gainSliders, 'ValueChangedFcn', @(s,~) app.setRange('gain', s.Value));
            set(u.gainMins, 'ValueChangedFcn', @(s,~) app.setRange('gain', [s.Value, app.lim.full(2)]));
            set(u.gainMaxs, 'ValueChangedFcn', @(s,~) app.setRange('gain', [app.lim.full(1), s.Value]));
            u.cutSlider.ValueChangedFcn = @(s,~) app.setRange('cut', s.Value);
            u.cutMin.ValueChangedFcn = @(s,~) app.setRange('cut', [s.Value, app.lim.cut(2)]);
            u.cutMax.ValueChangedFcn = @(s,~) app.setRange('cut', [app.lim.cut(1), s.Value]);
            set([u.cmin, u.cmax], 'ValueChangedFcn', @(~,~) app.setRange('all', [u.cmin.Value, u.cmax.Value]));
            app.status(u.status, 'Ready — load an antenna pattern file to begin 🚀', false);
            app.status(u.covStatus, 'Ready 🚀', false);
            app.covSetUI();
        end

        %% -------------------------------------------------------------- load & process
        function onLoad(app, ~)
            u = app.ui; fp = strtrim(u.path.Value);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.file.path)
                [f, p] = uigetfile(app.FileFilter, 'Select an antenna pattern file');
                if isequal(f, 0), return, end
                fp = fullfile(p, f);
                if strcmp(fp, app.file.path) && strcmp(uiconfirm(app.UIFigure, sprintf('"%s" is already loaded. Reload it?', f), ...
                        'File Already Loaded', 'Options', {'Reload','Cancel'}, 'DefaultOption', 1, 'CancelOption', 2), 'Cancel')
                    return
                end
            end
            app.runGuarded('Loading Data', 'Reading file...', 'Loading Error', @doLoad);

            function doLoad()
                out = app.readSource(fp, u.fmtLabel, u.fmt); app.checkCancelled();
                if out.meta.isCoverage   % Coverage results never replace the Main state.
                    u.tabs.SelectedTab = u.tabCov; u.covPath.Value = fp; app.covLoadResults(fp, out.raw); u.covResults.Visible = 'on'; return
                end
                u.path.Value = fp; [folder, base, ext] = fileparts(fp);
                app.file = struct('path', fp, 'folder', folder, 'base', base, 'name', [base ext]); app.src = out;
                items = compose('Pattern %d: %.4g GHz', (1:numel(out.blocks))', out.freqs(:)/1e9);
                items(isnan(out.freqs(:))) = compose('Pattern %d', find(isnan(out.freqs(:))));
                set(u.ffd, 'Items', items, 'Value', items{1}); set([u.ffd, u.ffdLabel], 'Visible', out.meta.isDep);
                u.basis.UserData = true;   % Re-derive the cut field basis from the new source polarization.
                app.selectBlock(1);
            end
        end

        function out = readSource(app, fp, label, dropdown)
            % Excel and native far-field formats are self-describing; generic text exposes the format selector.
            generic = isGeneric(fp);
            if generic, dropdown.Value = 'gain'; end
            out = readPattern(fp, dropdown.Value);
            set([label, dropdown], 'Visible', generic && ~out.meta.isCoverage);
            app.checkCancelled();
        end

        function selectBlock(app, k)
            block = app.src.blocks{k};
            if app.src.meta.isDep, app.src.raw = block; end
            app.std = normalizePattern(block); app.std.Properties.UserData = app.src.meta;
            app.ui.tableIn.UserData = false;   % Input tab must be repopulated.
            app.refresh();
        end

        function process(app)
            % app.std → app.pat. The primitive source (fields or gain) is optionally resampled to 1°;
            % derived dB quantities are never interpolated. One calcPattern pass produces every column.
            u = app.ui; S = app.std; ts = gridStep(S.Theta); ps = gridStep(S.Phi);
            native = max([ts ps], [], 'omitnan'); if isempty(native) || isnan(native), native = 1; end
            items = {sprintf('STEP: %g°', native), 'STEP: 1°'};
            if ~isequal(u.step.Items, items), set(u.step, 'Items', items, 'Value', items{1}); end
            canonical = abs(ts - 1) < 1e-9 && abs(ps - 1) < 1e-9; set(u.step, 'Visible', ~canonical, 'Enable', ~canonical);
            if ~canonical && strcmp(u.step.Value, items{2}), S = resampleTo1deg(S); end
            [app.pat, app.info] = calcPattern(S, app.params(), app.PeakPct, app.PeakExcess);
            app.omega = solidWeights(app.pat.Theta, app.pat.Phi);
            app.grid = struct(); app.metrics = struct(); app.rev = app.rev + 1;
        end

        function refresh(app)
            % Full pipeline after a source or parameter change: process → view state → tables → plots.
            u = app.ui; app.process(); app.checkCancelled(); eField = ~app.src.meta.isGainOnly;
            if isequal(u.basis.UserData, true) && eField
                if startsWith(app.info.pol, 'Linear'), u.basis.Value = 'Linear'; else, u.basis.Value = 'Circular'; end
            end
            app.updateComponents(); app.updateView(true, false, false); app.checkCancelled();
            app.onPlaneSwitch(); drawnow limitrate; app.renderAll();
            set([u.panelCut, u.panelFull, u.panelCtrl, u.exportBtn, u.covBtn], 'Visible', 'on');
            set([u.uanBtn, u.gridEcut, u.cutEt, u.cutEr, u.cutEl], 'Visible', eField); set([u.cutEr, u.cutEl, u.basis], 'Enable', eField);
            app.updateParamVisibility();
            pol = ''; if eField, pol = sprintf(' | Polarization <b>%s</b>', app.info.pol); end
            app.status(u.status, sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (θ=%s°, φ=%s°)%s', app.file.name, ...
                fmtNum(app.info.POB, 2), fmtNum(app.info.POBth), fmtNum(app.info.POBph), pol), false);
        end

        function p = params(app)
            u = app.ui;
            p = struct('GainLoss_dB', u.loss.Value, 'RxMode', string(u.rxPol.Value), 'RxAR_dB', u.rw.Value, 'FieldScale', 10^(u.loss.Value/20));
            switch u.ptUnit.Value
                case 'dBm',   p.Pt_dBW = u.pt.Value - 30;
                case 'Watts', p.Pt_dBW = 10*log10(max(u.pt.Value, eps));
                otherwise,    p.Pt_dBW = u.pt.Value;
            end
            p.R_m = max(u.dist.Value, 1e-12) * (1 + 999*strcmp(u.distUnit.Value, 'km'));
        end

        function onProcess(app, ~)
            if isempty(app.std), uialert(app.UIFigure, 'Load a pattern first.', 'Process', 'Icon', 'warning'); return, end
            if app.runGuarded('Processing', 'Re-processing pattern...', 'Processing Error', @reprocess)
                app.status(app.ui.status, ['Re-processed <b>' app.file.name '</b> with the current parameters ✅'], true);
            end
            function reprocess()
                % Generic text sources are re-interpreted with the selected format from the cached table.
                u = app.ui;
                if isGeneric(app.file.path) && u.fmt.Visible
                    out = readPattern(app.file.path, u.fmt.Value, app.src.raw);
                    assert(~out.meta.isCoverage, 'The selected format identifies a coverage-results file.');
                    app.src = out; app.selectBlock(1);
                else
                    app.refresh();
                end
            end
        end

        function onFormatChanged(app, ~)
            if isGeneric(app.file.path) && strcmp(strtrim(app.ui.path.Value), app.file.path), app.ui.basis.UserData = true; app.onProcess(); end
        end

        function onStepChanged(app, ~)
            app.runGuarded('Processing', 'Changing angular step...', 'Processing Error', @() app.refresh());
        end

        function onFFDChanged(app, ~)
            u = app.ui; k = find(strcmp(u.ffd.Items, u.ffd.Value), 1); u.basis.UserData = true;
            app.runGuarded('Processing', 'Switching frequency block...', 'Processing Error', @() app.selectBlock(k));
            app.status(u.status, sprintf('Switched to block %d (%s).', k, u.ffd.Value), true);
        end

        function resetParams(app, ~)
            u = app.ui; d = app.defaults;
            [u.loss.Value, u.rxPol.Value, u.rw.Value, u.pt.Value, u.ptUnit.Value, u.dist.Value, u.distUnit.Value] = ...
                deal(d.loss, d.rxPol, d.rw, d.pt, d.ptUnit, d.dist, d.distUnit);
            if ~isempty(app.std), app.runGuarded('Processing', 'Re-processing pattern...', 'Processing Error', @() app.refresh()); end
        end

        function ok = runGuarded(app, ttl, msg, errTitle, fcn)
            % Run FCN under one cancelable progress dialog with uniform error reporting.
            app.dlg = uiprogressdlg(app.UIFigure, 'Title', ttl, 'Message', msg, 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            cleaner = onCleanup(@() delete(app.dlg)); drawnow; ok = false; %#ok<NASGU>
            try
                fcn(); ok = true;
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.status(app.ui.status, 'Operation cancelled by user.', true);
                else, app.showError(ME, errTitle); end
            end
        end

        function checkCancelled(app)
            if ~isempty(app.dlg) && isvalid(app.dlg) && app.dlg.CancelRequested, error('APAT:Cancelled', 'Operation cancelled by user.'); end
        end

        %% -------------------------------------------------------------- display conventions
        function tf = isElev(app),   tf = strcmp(app.ui.thetaSpan.Value, '-90° to 90°'); end
        function tf = isSigned(app), tf = strcmp(app.ui.phiSpan.Value, '-180° to 180°'); end
        function th = dispTheta(app, th), if app.isElev(), th = 90 - th; end, end          % involution: also maps display → physical
        function ph = dispPhi(app, ph),   if app.isSigned(), ph(ph > 180) = ph(ph > 180) - 360; end, end
        function s = thetaLabel(app), if app.isElev(), s = "Elevation"; else, s = "Theta"; end, end

        function T = viewTable(app)
            % app.pat expressed in the selected display conventions (Results table and exports only).
            T = app.pat;
            if app.isSigned()
                T(T.Phi == 360, :) = []; T.Phi = app.dispPhi(T.Phi);
                seam = T(T.Phi == 180, :); seam.Phi(:) = -180; T = [seam; T];
            end
            T.Theta = app.dispTheta(T.Theta);
            if app.isSigned() || app.isElev(), T = sortrows(T, {'Phi','Theta'}); end
        end

        function [th, ph, M] = gridOf(app, col)
            % Canonical θ×φ matrix of one component plus unit-sphere geometry (built lazily, cached per component).
            if ~isfield(app.grid, 'th')
                th = unique(app.pat.Theta); ph = unique(app.pat.Phi); [~, it] = ismember(app.pat.Theta, th); [~, ip] = ismember(app.pat.Phi, ph);
                g = struct('th', th, 'ph', ph, 'sz', [numel(th) numel(ph)], 'comps', struct()); g.idx = sub2ind(g.sz, it, ip);
                [phG, thG] = meshgrid(ph, th); sinT = sind(thG);
                g.geom = struct('thG', thG, 'phG', phG, 'x', sinT.*cosd(phG), 'y', sinT.*sind(phG), 'z', cosd(thG));
                app.grid = g;
            end
            th = app.grid.th; ph = app.grid.ph; key = matlab.lang.makeValidName(col);
            if ~isfield(app.grid.comps, key), M = nan(app.grid.sz); M(app.grid.idx) = app.pat.(col); app.grid.comps.(key) = M; end
            M = app.grid.comps.(key);
        end

        function [th, ph, M] = dispGrid(app, col)
            % Grid re-expressed in the display conventions with the φ seam kept closed (rectangular plots).
            [th, ph, M] = app.gridOf(col);
            if app.isSigned()
                keep = ph < 360; [ph, order] = sort(app.dispPhi(ph(keep))); M = M(:, keep); M = M(:, order);
                if ph(end) == 180, ph = [-180; ph]; M = [M(:, end), M]; end
            end
            th = app.dispTheta(th);
            if app.isElev(), th = flipud(th); M = flipud(M); end
        end

        %% -------------------------------------------------------------- view state
        function updateComponents(app)
            u = app.ui; [cols, labels] = componentList(app.pat); prev = u.comp.Value;
            set(u.comp, 'Items', cellstr(labels), 'ItemsData', cellstr(cols)); u.comp.Value = char(preferredComponent(prev, cols));
        end

        function c = comp(app), c = app.ui.comp.Value; end

        function s = compLabel(app)
            u = app.ui; k = find(strcmp(u.comp.ItemsData, u.comp.Value), 1);
            if isempty(k), s = string(u.comp.Value); else, s = string(u.comp.Items{k}); end
        end

        function updateView(app, resetRanges, redrawFull, redrawCut)
            % Orientation → peak → metrics → ranges → tables → metadata → plots, all from app.pat.
            if nargin < 3, redrawFull = true; end
            if nargin < 4, redrawCut = true; end
            col = app.comp();
            [~, pk, app.boresight] = calcOrientation(app.pat, app.omega, col, app.Axes, app.PeakPct, app.PeakExcess);
            app.info.peak = pk; app.info.POB = pk.value; app.info.POBth = app.pat.Theta(pk.index); app.info.POBph = app.pat.Phi(pk.index);
            app.metrics = calcMetrics(app.pat, app.omega, app.Axes, app.boresight, app.PeakPct, app.PeakExcess);
            if resetRanges
                if ~isAR(col), app.lim.gain = displayRange(chooseGain(app.pat, 'E_Total_dB'), app.PeakPct, app.PeakExcess); end
                app.setRange('gain', app.themeLimits(), false); app.setRange('cut', app.lim.gain, false);
            end
            app.updateTables(); app.updateMetadata();
            if redrawCut, app.updateCutControl(); app.plotCut(); end
            if redrawFull, app.renderAll(); end
        end

        function onComponentChanged(app, ~), app.updateView(true); end
        function onAngularChanged(app),       if ~isempty(app.pat), app.updateView(false); end, end

        %% -------------------------------------------------------------- ranges & theme
        function setRange(app, scope, limits, apply)
            % One authoritative range per scope: 'gain' (all full-pattern tabs + colorbar spinners), 'cut', or 'all'.
            if nargin < 4, apply = true; end
            u = app.ui; limits = clampRange(limits, app.DBRange);
            if strcmp(scope, 'all'), app.setRange('gain', limits, apply); app.setRange('cut', limits, apply); return, end
            if strcmp(scope, 'gain'), sliders = u.gainSliders; mins = [u.gainMins, u.cmin]; maxs = [u.gainMaxs, u.cmax];
            else, sliders = u.cutSlider; mins = u.cutMin; maxs = u.cutMax; end
            set(sliders, 'Limits', app.DBRange, 'Value', limits); set(sliders, 'Limits', clampRange(limits + [-10 10], app.DBRange));
            set(mins, 'Limits', [app.DBRange(1), limits(2) - 1], 'Value', limits(1));
            set(maxs, 'Limits', [limits(1) + 1, app.DBRange(2)], 'Value', limits(2));
            if strcmp(scope, 'gain')
                app.lim.full = limits; if ~isAR(app.comp()), app.lim.gain = limits; end
                if apply && ~isempty(app.pat), app.applyFullRange(); end
            else
                app.lim.cut = limits;
                if apply && ~isempty(app.pat), app.plotCut(); end   % Re-plot so the polar clamp follows the new floor.
            end
        end

        function limits = themeLimits(app)
            if isAR(app.comp()), limits = [-30 30]; else, limits = app.lim.gain; end
        end

        function applyTheme(app, ax)
            % Signed AR: fixed blue-white-red ±30 dB scale. Gain-like data: shared window with jet.
            limits = app.lim.full; map = jet(256);
            if isAR(app.comp()), map = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
            clim(ax, limits); colormap(ax, map); cb = colorbar(ax); t = ticks(limits, app.ui.cstep.Value);
            if isempty(t), cb.TicksMode = 'auto'; else, cb.Ticks = t; end
        end

        function applyFullRange(app)
            u = app.ui;
            for ax = [u.axCtr, u.axSph, u.axPol, u.axRect3], app.applyTheme(ax); end
            app.applyTheme(app.paxPattern); zlim(u.axRect3, app.lim.full); t = ticks(app.lim.full, u.cstep.Value);
            if isempty(t), u.axRect3.ZTickMode = 'auto'; else, u.axRect3.ZTick = t; end
            drawnow limitrate
        end

        %% -------------------------------------------------------------- full-pattern renderers
        function renderAll(app)
            if isempty(app.pat), return, end
            app.drawContour(); app.checkCancelled(); app.drawFisheye(); app.checkCancelled();
            app.draw3D(app.ui.axSph, 'sphere'); app.checkCancelled(); app.draw3D(app.ui.axPol, 'polar'); app.checkCancelled();
            app.drawRect3(); drawnow limitrate
        end

        function drawContour(app)
            ax = app.ui.axCtr; [th, ph, M] = app.dispGrid(app.comp()); [phG, thG] = meshgrid(ph, th); cla(ax);
            s = pcolor(ax, ph, th, M); set(s, 'FaceColor', 'interp', 'LineStyle', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax); app.angularAxes(ax, 30, 15); daspect(ax, [1 1 1]);
            title(ax, app.compLabel(), 'Interpreter', 'none'); xlabel(ax, 'Phi (degree)'); ylabel(ax, app.thetaLabel() + " (degree)");
            app.setTips(s, thG, phG, M); app.markPOB(ax, app.dispPhi(app.info.POBph), app.dispTheta(app.info.POBth), []);
        end

        function drawFisheye(app)
            % Radius is always physical θ (0 at the centre); only the tick labels follow the display conventions.
            ax = app.paxPattern; [~, ~, M] = app.gridOf(app.comp()); g = app.grid.geom; cla(ax);
            s = surface(ax, deg2rad(g.phG), g.thG, zeros(size(M)), M, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax); app.polarTicks(ax);
            set(ax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', app.dispTheta(0:30:180)));
            title(ax, sprintf('%s  |  r=θ, angle=φ', app.compLabel()), 'Interpreter', 'none', 'FontSize', 9);
            app.setTips(s, app.dispTheta(g.thG), app.dispPhi(g.phG), M); app.markPOB(ax, deg2rad(app.info.POBph), app.info.POBth, []);
        end

        function draw3D(app, ax, kind)
            % 'sphere': colour on the unit sphere. 'polar': radius ∝ (value − floor), shared with the cut overlay via radial().
            [~, ~, M] = app.gridOf(app.comp()); g = app.grid.geom; r = ones(size(M)); rp = 1;
            if strcmp(kind, 'polar'), r = app.radial(M); rp = app.radial(app.info.POB); end
            cla(ax); hold(ax, 'on');
            s = surf(ax, r.*g.x, r.*g.y, r.*g.z, M, 'EdgeColor', 'none', 'Tag', 'APAT_Surface'); app.applyTheme(ax);
            set(ax, 'Projection', 'orthographic', 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1]);
            axis(ax, 'off'); drawXYZ(ax); app.apply3DView(ax, [135 25]);
            if app.ui.overlay.Value, app.overlayCut(ax, kind); end
            title(ax, sprintf('%s  |  θ: %s  |  φ: %s', app.compLabel(), app.ui.thetaSpan.Value, app.ui.phiSpan.Value), 'Interpreter', 'none');
            app.setTips(s, app.dispTheta(g.thG), app.dispPhi(g.phG), M);
            th = app.info.POBth; ph = app.info.POBph; app.markPOB(ax, 1.02*rp*sind(th)*cosd(ph), 1.02*rp*sind(th)*sind(ph), 1.02*rp*cosd(th));
            hold(ax, 'off');
        end

        function drawRect3(app)
            u = app.ui; ax = u.axRect3; [th, ph, M] = app.dispGrid(app.comp()); [phG, thG] = meshgrid(ph, th); cla(ax);
            s = surf(ax, phG, thG, M, 'EdgeColor', 'none', 'Tag', 'APAT_Surface'); app.applyTheme(ax);
            zlim(ax, app.lim.full); t = ticks(app.lim.full, u.cstep.Value); if isempty(t), ax.ZTickMode = 'auto'; else, ax.ZTick = t; end
            app.angularAxes(ax, 60, 30); grid(ax, 'on'); app.apply3DView(ax, [-35 35]);
            xlabel(ax, 'Phi (degree)'); ylabel(ax, app.thetaLabel() + " (degree)"); zlabel(ax, app.compLabel() + " (dB)", 'Interpreter', 'none');
            title(ax, app.compLabel(), 'Interpreter', 'none'); app.setTips(s, thG, phG, M);
            app.markPOB(ax, app.dispPhi(app.info.POBph), app.dispTheta(app.info.POBth), app.info.POB);
        end

        function r = radial(app, values)
            % Normalized 3-D polar radius: 0 at the colour floor, 1 at the component maximum.
            lim = app.lim.full; [~, ~, M] = app.gridOf(app.comp());
            r = max(values - lim(1), 0) / max(max(M, [], 'all', 'omitnan') - lim(1), eps);
        end

        function markPOB(app, ax, x, y, z)
            % Peak-of-beam marker + DataTip drawn in the axes' own coordinates; visibility is tag-driven.
            rows = [dataTipTextRow(app.thetaLabel(), app.dispTheta(app.info.POBth), '%.3g°'); dataTipTextRow("Phi", app.dispPhi(app.info.POBph), '%.3g°'); ...
                    dataTipTextRow(app.compLabel(), app.info.POB, '%.3g dB')];
            if ~all(isfinite([x y])), return, end
            held = ishold(ax); hold(ax, 'on');
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), h = polarplot(ax, x, y, 'ko');
            elseif isempty(z), h = plot(ax, x, y, 'ko');
            else, h = plot3(ax, x, y, z, 'ko', 'Clipping', 'off'); end
            set(h, 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off', 'Tag', 'APAT_POB'); h.DataTipTemplate.DataTipRows = rows;
            tip = datatip(h, 'DataIndex', 1, 'FontSize', 9, 'Tag', 'APAT_POB', 'HandleVisibility', 'off');
            h.Visible = app.ui.pob.Value; tip.Visible = app.ui.pob.Value;
            if ~held, hold(ax, 'off'); end
            set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', ax.ContextMenu);
        end

        function setTips(app, s, thG, phG, M)
            % Common angular/component DataTip template for pattern surfaces (values in display conventions).
            rows = [dataTipTextRow(app.thetaLabel(), thG, '%.3g°'); dataTipTextRow("Phi", phG, '%.3g°'); dataTipTextRow(app.compLabel(), M, '%.3g dB')];
            try, s.DataTipTemplate.DataTipRows = rows; catch, end   % Template may not exist before the first render.
        end

        function angularAxes(app, ax, phiStep, thetaStep)
            if app.isSigned(), xl = [-180 180]; else, xl = [0 360]; end
            if app.isElev(), yl = [-90 90]; ydir = 'normal'; else, yl = [0 180]; ydir = 'reverse'; end
            set(ax, 'XLim', xl, 'YLim', yl, 'YDir', ydir, 'Box', 'on', 'Layer', 'top', 'XTick', xl(1):phiStep:xl(2), 'YTick', yl(1):thetaStep:yl(2));
        end

        function polarTicks(app, pax)
            set(pax, 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', app.dispPhi(0:30:330)));
        end

        function apply3DView(app, ax, iso)
            v = struct('iso', [iso 0 0 1], 'top', [0 90 0 1 0], 'bottom', [0 -90 0 1 0], 'right', [90 0 0 0 1], 'left', [-90 0 0 0 1], 'front', [0 0 0 0 1], 'back', [180 0 0 0 1]);
            v = v.(app.ui.view3D.Value); view(ax, v(1), v(2)); camup(ax, v(3:5));
        end

        function on3DView(app)
            if isempty(app.pat), return, end
            u = app.ui; app.apply3DView(u.axSph, [135 25]); app.apply3DView(u.axPol, [135 25]); app.apply3DView(u.axRect3, [-35 35]); drawnow limitrate
        end

        function toggleTag(app, tag, on)
            set(findall(app.UIFigure, 'Tag', tag), 'Visible', on);
        end

        %% -------------------------------------------------------------- cuts
        function [cols, idx] = cutCols(app)
            % Selected Total plus the circular or linear field pair; IDX keeps line colours stable.
            u = app.ui;
            if app.src.meta.isGainOnly, cols = string(app.comp()); idx = 1; return, end
            if strcmp(u.basis.Value, 'Linear'), pair = ["E_TH","E_PH"]; else, pair = ["E_RCP","E_LCP"]; end
            u.cutEr.Text = char(pair(1)); u.cutEl.Text = char(pair(2));
            sel = [u.cutEt.Value, u.cutEr.Value, u.cutEl.Value]; if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = ["E_Total_dB", pair + "_dB"]; cols = cols(idx);
        end

        function c = cutData(app)
            % Active cut as one closed circle (0..360° or −180..180°), with the source geometry of every sample.
            u = app.ui; T = app.pat; kind = string(u.cutType.Value); [cols, idx] = app.cutCols(); req = u.cutValue.Value;
            if kind == "Phi", req = app.dispTheta(req); end
            [ang, rows, fixed, sym, snapped] = cutGeometry(T, kind, req); shown = fixed; if kind == "Phi", shown = app.dispTheta(fixed); end
            if snapped, app.status(u.status, sprintf('Requested %s cut snapped to the nearest sample %s=%g°', kind, sym, shown), true); end
            ang = app.dispPhi(ang); [ang, order] = sort(ang); [ang, uq] = unique(ang, 'stable'); order = order(uq); rows = rows(order);
            data = T{rows, cols}; theta = T.Theta(rows); phi = T.Phi(rows);
            if app.isSigned(), seam = [-180 180]; else, seam = [0 360]; end   % close the circle at the seam
            lo = ang(1) == seam(1); hi = ang(end) == seam(2);
            if hi && ~lo,      ang = [seam(1); ang]; data = [data(end, :); data]; theta = [theta(end); theta]; phi = [phi(end); phi];
            elseif lo && ~hi,  ang = [ang; seam(2)]; data = [data; data(1, :)]; theta = [theta; theta(1)]; phi = [phi; phi(1)];
            elseif ~lo && ~hi
                w = (seam(2) - ang(end)) / (ang(1) - seam(1) + seam(2) - ang(end)); d = (1 - w)*data(end, :) + w*data(1, :);
                ang = [seam(1); ang; seam(2)]; data = [d; data; d]; theta = [theta(end); theta; theta(1)]; phi = [phi(end); phi; phi(1)];
            end
            c = struct('angle', ang, 'data', data, 'theta', theta, 'phi', phi, 'cols', cols, 'idx', idx, 'kind', kind, ...
                'title', sprintf('%s cut @ %s = %g°', kind, sym, shown));
        end

        function plotCut(app)
            if isempty(app.pat), return, end
            u = app.ui; pax = app.paxCut; rax = u.axRect; c = app.cutData(); lim = app.lim.cut;
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on');
            pl = polarplot(pax, deg2rad(c.angle), max(c.data, lim(1)), 'LineWidth', 1.4);   % clamp: no reflection spikes below the floor
            rl = plot(rax, c.angle, c.data, 'LineWidth', 1.4); colors = rax.ColorOrder(1 + mod(c.idx - 1, 7), :);
            for k = 1:numel(pl)
                rows = [dataTipTextRow("Angle", c.angle, '%.3g°'); dataTipTextRow("Magnitude", c.data(:, k), '%.3g dB')];
                set([pl(k), rl(k)], 'Color', colors(k, :)); pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            if app.isSigned(), xl = [-180 180]; else, xl = [0 360]; end
            set(pax, 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.polarTicks(pax);
            set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on', 'Box', 'on');
            xlabel(rax, c.kind + " (degree)"); ylabel(rax, 'Magnitude (dB)'); title(pax, c.title, 'Interpreter', 'none'); title(rax, c.title, 'Interpreter', 'none');
            [pk, ip] = max(c.data(:, 1), [], 'omitnan');   % Peak of the displayed cut (first plotted column).
            if isfinite(pk)
                app.markCut(c.angle(ip), pk, [dataTipTextRow("Angle", c.angle(ip), '%.3g°'); dataTipTextRow("Magnitude", pk, '%.3g dB')], 'APAT_POB', 'k', u.pob.Value);
            end
            u.hpbwLabel.Text = '';
            if u.hpbw.Value && isfinite(pk)
                [bw, lo, hi] = calcHPBW(c.angle, c.data(:, 1), pk, c.angle(ip));
                if isfinite(bw)
                    b = [lo hi]; if xl(1) < 0, b = mod(b + 180, 360) - 180; else, b = mod(b, 360); end
                    u.hpbwLabel.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                    if b(1) <= b(2), reg = b; else, reg = [xl(1), b(2); b(1), xl(2)]; end   % wrap-aware shading
                    thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    xregion(rax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    names = ["Lower HPBW", "Upper HPBW"];
                    for k = 1:2, app.markCut(b(k), pk - 3, [dataTipTextRow(names(k), b(k), '%.2f°'); dataTipTextRow("Gain", pk - 3, '%.2f dB')], 'APAT_HPBW', '#D95319', u.hpbwTips.Value); end
                end
            end
            names = replace(c.cols, "_", "\_");
            legend(pax, pl, names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rl, names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off');
        end

        function markCut(app, angle, value, rows, tag, color, visible)
            % Marker + DataTip on both cut axes (polar and rectangular).
            h = [polarplot(app.paxCut, deg2rad(angle), value, 'o'), plot(app.ui.axRect, angle, value, 'o')];
            set(h, 'Color', color, 'MarkerFaceColor', color, 'MarkerSize', 5, 'HandleVisibility', 'off', 'Tag', tag);
            for m = h
                m.DataTipTemplate.DataTipRows = rows; t = datatip(m, 'DataIndex', 1, 'FontSize', 9, 'Tag', tag, 'HandleVisibility', 'off');
                m.Visible = visible; t.Visible = visible;
            end
        end

        function overlayCut(app, ax, kind)
            delete(findall(ax, 'Tag', 'APAT_Overlay')); c = app.cutData(); r = 1.02;
            if strcmp(kind, 'polar'), r = 1.01*app.radial(c.data(:, 1)); end
            plot3(ax, r.*sind(c.theta).*cosd(c.phi), r.*sind(c.theta).*sind(c.phi), r.*cosd(c.theta), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_Overlay');
        end

        function onOverlayToggled(app)
            u = app.ui; if isempty(app.pat), return, end
            for spec = {{u.axSph, 'sphere'}, {u.axPol, 'polar'}}
                ax = spec{1}{1}; delete(findall(ax, 'Tag', 'APAT_Overlay'));
                if u.overlay.Value, hold(ax, 'on'); app.overlayCut(ax, spec{1}{2}); hold(ax, 'off'); end
            end
        end

        function updateCutControl(app, target)
            % Cut value = fixed θ (Phi cut, shown in the display θ convention) or fixed φ (Theta cut); snapped to samples.
            u = app.ui; if nargin < 2, target = u.cutValue.Value; end
            if strcmp(u.cutType.Value, 'Phi'), v = sort(app.dispTheta(unique(app.pat.Theta))); else, v = unique(app.pat.Phi); end
            [~, k] = min(abs(v - target)); step = gridStep(v); if isnan(step), step = 1; end
            set(u.cutValue, 'Limits', [min(v), max(max(v), min(v) + step)], 'Step', step, 'Value', v(k));
        end

        function onPlaneSwitch(app, ~)
            % E-plane: θ sweep at the boresight φ.  H-plane: the orthogonal plane through the boresight axis.
            u = app.ui; A = app.Axes; k = app.boresight;
            if strcmp(u.plane.Value, 'E'), kind = 'Theta'; value = A.phi(k);
            elseif A.theta(k) == 90,       kind = 'Phi';   value = app.dispTheta(90);
            else,                          kind = 'Theta'; value = 90; end
            u.cutType.Value = kind; app.updateCutControl(value); app.onCutChanged();
        end

        function onCutChanged(app, event)
            u = app.ui;
            if nargin > 1 && ~isempty(event) && event.Source == u.cutType, app.updateCutControl(); end
            if nargin > 1 && ~isempty(event) && event.Source == u.basis, u.basis.UserData = false; app.updateMetadata(); end
            u.hpbwTips.Visible = u.hpbw.Value; if ~u.hpbw.Value, u.hpbwTips.Value = false; end
            app.plotCut(); if u.overlay.Value, app.onOverlayToggled(); end
        end

        %% -------------------------------------------------------------- tables, metadata, status, export
        function updateTables(app)
            u = app.ui; T = app.viewTable(); cols = T.Properties.VariableNames(3:end);
            if ~isequal(u.tableIn.UserData, true)
                set(u.tableIn, 'Data', app.src.raw, 'ColumnName', app.src.raw.Properties.VariableNames, 'Visible', 'on', 'UserData', true);
            end
            if ~isequal(regexprep(u.filter.Items(2:end), '^✓ ?', ''), cols)   % schema changed → rebuild the column filter
                set(u.filter, 'Items', [{'--- column filter ---'}, cols], 'ItemsData', 0:numel(cols), 'Value', 0, 'UserData', ~ismember(cols, app.Hidden), 'Visible', 'on');
                set([u.tableOut, u.tabData], 'Visible', 'on');
            end
            app.filterOutput(T);
        end

        function filterOutput(app, T, ~)
            % Toggle one column from the dropdown (callback) or refresh after a data change (T given); style the items.
            u = app.ui; dd = u.filter; if nargin < 2 || ~istable(T), T = app.viewTable(); end
            if dd.Value > 0, dd.UserData(dd.Value) = ~dd.UserData(dd.Value); dd.Value = 0; end
            if isempty(app.filterStyles)
                app.filterStyles = {uistyle('FontWeight', 'bold', 'FontColor', 'black', 'BackgroundColor', [0.8 1 0.8]), uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9])};
            end
            dd.Items = regexprep(dd.Items, '^✓ ?', ''); removeStyle(dd); on = find(dd.UserData) + 1; dd.Items(on) = append('✓ ', dd.Items(on));
            addStyle(dd, app.filterStyles{1}, 'Item', on); addStyle(dd, app.filterStyles{2}, 'Item', find([true, ~dd.UserData]));
            u.tableOut.Data = T(:, [true, true, dd.UserData]); app.updateParamVisibility();
        end

        function updateParamVisibility(app)
            % Only the parameters that feed a visible Results column are shown.
            u = app.ui; cols = string(app.pat.Properties.VariableNames(3:end)); shown = cols(u.filter.UserData); has = @(n) any(ismember(shown, n));
            set([u.rxPolLabel, u.rxPol, u.rwLabel, u.rw], 'Visible', has(["PLF_dB","Gain_PolCorrected_dB"]));
            set([u.ptLabel, u.pt, u.ptUnit], 'Visible', has(["EIRP_dBW","PFD_Wm2","E_RMS_Vm"]));
            set([u.distLabel, u.dist, u.distUnit], 'Visible', has(["PFD_Wm2","E_RMS_Vm"]));
            set([u.lossLabel, u.loss], 'Visible', app.src.meta.isGainOnly || has(["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","Gain_PolCorrected_dB","EIRP_dBW","PFD_Wm2","E_RMS_Vm"]));
        end

        function updateMetadata(app)
            u = app.ui; T = app.pat; m = app.metrics; meta = app.src.meta; f = @fmtNum; th = unique(T.Theta); ph = unique(T.Phi);
            rows = {'Source format', meta.source; 'File', app.file.name; 'Samples', sprintf('%d  (θ: %d × φ: %d)', height(T), numel(th), numel(ph)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', f(min(th)), f(max(th)), f(gridStep(th))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', f(min(ph)), f(max(ph)), f(gridStep(ph))); 'Angular step', u.step.Value; ...
                'Selected component', char(app.compLabel()); ...
                'Peak of beam (component)', sprintf('%s dB @ [θ=%s°, φ=%s°]', f(app.info.POB), f(app.info.POBth), f(app.info.POBph)); ...
                'Peak policy', sprintf('P%.4g + %g dB, adjusted: %s', app.PeakPct, app.PeakExcess, string(app.info.peak.wasAdjusted)); ...
                'Boresight axis', app.Axes.labels{app.boresight}};
            fr = app.src.freqs(isfinite(app.src.freqs));
            if ~isempty(fr), rows(end+1, :) = {'Frequencies', strjoin(compose('%.4g GHz', fr(:)'/1e9), ', ')}; end
            if ~meta.isGainOnly
                rows = [rows; {'Polarization', app.info.pol; 'Cut co-pol / cross-pol', char(strjoin(app.info.pairs.(u.basis.Value), ' / '))}];
            end
            if isfield(m, 'PeakGain_dB')
                rows = [rows; {'Peak gain (total)', sprintf('%s dB @ [θ=%s°, φ=%s°]', f(m.PeakGain_dB), f(m.PeakTheta_deg), f(m.PeakPhi_deg)); ...
                    'HPBW E-plane / H-plane', sprintf('%s° / %s°', f(m.HPBW_EPlane_deg), f(m.HPBW_HPlane_deg)); ...
                    'Front-to-back', sprintf('%s dB', f(m.FrontBack_dB)); 'Peak directivity', sprintf('%s dB', f(m.PeakDirectivity_dB)); ...
                    'Radiation efficiency', sprintf('%s %%', f(m.Efficiency_pct)); 'AR at peak', sprintf('%s dB', f(m.AxialRatioAtPeak_dB))}];
            end
            if isfield(meta, 'summary') && ~isempty(meta.summary), rows = [rows; meta.summary]; end   % Excel workbook summary sheet
            u.tableMeta.Data = rows;
        end

        function status(app, label, message, transient)
            % Set a status label; a transient message reverts to the last persistent one after 3 s.
            if app.isClosing || ~isgraphics(label), return, end
            app.stopTimer(); label.Text = char(message);
            if ~transient, label.UserData = char(message); return, end
            app.statusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, 'TimerFcn', @(~,~) app.restoreStatus(label));
            start(app.statusTimer);
        end

        function restoreStatus(app, label)
            if ~app.isClosing && isgraphics(label) && ~isempty(label.UserData), label.Text = label.UserData; end
        end

        function stopTimer(app)
            t = app.statusTimer; app.statusTimer = [];
            if ~isempty(t) && isvalid(t), stop(t); delete(t); end
        end

        function showError(app, ME, ttl)
            if app.isClosing || ~isvalid(app.UIFigure), return, end
            where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.UIFigure, [ME.message where], ttl, 'Icon', 'error');
        end

        function exportTable(app, T, name, what, label)
            [f, p] = uiputfile(app.ExportFilter, ['Export ' what], fullfile(app.file.folder, name)); if isequal(f, 0), return, end
            try, fp = fullfile(p, f); writeTable(T, fp); app.status(label, sprintf('%s exported to <b>%s</b>', what, fp), true);
            catch ME, app.showError(ME, 'Export Error'); end
        end

        function exportResults(app, ~)
            if ~isempty(app.pat), app.exportTable(app.ui.tableOut.Data, [app.file.base '_APAT_results.csv'], 'Results', app.ui.status); end
        end

        function exportCut(app, ~)
            if isempty(app.pat), return, end
            c = app.cutData(); T = array2table([c.angle, c.data], 'VariableNames', [{'Angle_deg'}, cellstr(c.cols)]);
            app.exportTable(T, [app.file.base '_cut.csv'], ['Cut (' c.title ')'], app.ui.status);
        end

        function exportUAN(app, ~)
            % XGTD UAN: canonical header + Theta Phi |Eθ|dB |Eφ|dB ∠Eθ ∠Eφ rows (or the same table as CSV/TXT).
            if app.src.meta.isGainOnly, uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return, end
            T = app.pat; U = sortrows(table(T.Theta, T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta','Phi','E_TH_DB','E_PH_DB','E_TH_DG','E_PH_DG'}), {'Phi','Theta'});
            peak = max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan'); step = gridStep(U.Theta); if isnan(step), step = 1; end
            [f, p] = uiputfile({'*.uan','XGTD user-defined antenna (*.uan)'; '*.csv','Comma-delimited (*.csv)'; '*.txt','Tab-delimited (*.txt)'}, ...
                'Export UAN', fullfile(app.file.folder, sprintf('%s_%.5f_%gdeg.uan', app.file.base, peak, step)));
            if isequal(f, 0), return, end
            try
                fp = fullfile(p, f);
                if endsWith(fp, '.uan', 'IgnoreCase', true)
                    hdr = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                        'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                        min(U.Phi), max(U.Phi), gridStep(U.Phi), min(U.Theta), max(U.Theta), step, peak);
                    writelines(hdr, fp); writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
                else
                    writeTable(U, fp);
                end
                app.status(app.ui.status, ['UAN exported to <b>' fp '</b>'], true);
            catch ME, app.showError(ME, 'Export UAN Error'); end
        end

        %% -------------------------------------------------------------- coverage: sources
        function toCoverage(app, ~)
            % Coverage is always fed from the CURRENT processed Main pattern (loss, step, parameters already applied).
            u = app.ui; if isempty(app.pat), return, end
            u.tabs.SelectedTab = u.tabCov; u.covPath.Value = app.file.path; node = app.covFind(app.file.path);
            if isempty(node), app.covAddPattern(app.file.base, app.pat, app.file.path);
            else, app.covSyncFromMain(node); u.tree.SelectedNodes = node; app.covSetUI(); end
            app.status(u.covStatus, 'Coverage source synchronized from the Main tab.', false);
        end

        function covLoad(app, ~)
            u = app.ui; fp = strtrim(u.covPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFind(fp))
                [f, p] = uigetfile(app.FileFilter, 'Select a pattern or coverage results file'); if isequal(f, 0), return, end
                fp = fullfile(p, f);
            end
            node = app.covFind(fp);
            if ~isempty(node)
                u.tree.SelectedNodes = node; app.covTreeSelected(); u.covPath.Value = fp; app.status(u.covStatus, 'File already loaded — node selected.', true); return
            end
            u.covPath.Value = fp;
            try
                out = app.readSource(fp, u.covFmtLabel, u.covFmt);
                if out.meta.isCoverage, app.covLoadResults(fp, out.raw); else, [~, name] = fileparts(fp); app.covAddPattern(name, app.buildPattern(out), fp); end
                u.covResults.Visible = 'on';
            catch ME, app.showError(ME, 'Coverage Load Error'); end
        end

        function covFmtChanged(app, ~)
            % Re-interpret a generic coverage pattern node with the newly selected text format.
            u = app.ui; fp = strtrim(u.covPath.Value); old = app.covFind(fp); if isempty(old) || ~isGeneric(fp), return, end
            try
                out = readPattern(fp, u.covFmt.Value);
                if out.meta.isCoverage, app.status(u.covStatus, 'The selected format identifies a coverage-results file; pattern unchanged.', true); return, end
                name = old.NodeData.name; for j = treeNodes(old, 'job').', delete(j.NodeData.line); end, delete(old);
                app.covAddPattern(name, app.buildPattern(out), fp); app.covFinalize();
                app.status(u.covStatus, sprintf('Pattern "<b>%s</b>" re-processed with the selected format.', name), true);
            catch ME, app.showError(ME, 'Coverage Format Error'); end
        end

        function P = buildPattern(app, out)
            % Auxiliary processed pattern (first block) without touching the Main state.
            S = normalizePattern(out.blocks{1}); S.Properties.UserData = out.meta; P = calcPattern(S, app.params(), app.PeakPct, app.PeakExcess);
        end

        function node = covAddPattern(app, name, T, fp)
            u = app.ui; node = uitreenode(u.treeRoot, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', 'pattern', 'name', name, 'path', fp, 'pat', T, 'omega', solidWeights(T.Theta, T.Phi), 'comp', "", 'boresight', 1, 'rev', app.rev);
            expand(u.tree); u.tree.CheckedNodes = [u.tree.CheckedNodes; node]; u.tree.SelectedNodes = node;
            app.covSync(node); app.covSetUI(); app.status(u.covStatus, sprintf('Pattern "<b>%s</b>" ready — compute coverage.', name), false);
        end

        function covSyncFromMain(app, node)
            d = node.NodeData; d.pat = app.pat; d.omega = app.omega; d.name = app.file.base; d.rev = app.rev; d.comp = ""; node.NodeData = d; app.covSync(node);
        end

        function covSync(app, node)
            % Make the Component dropdown, the detected boresight and the threshold preset follow NODE.
            u = app.ui; d = node.NodeData; [cols, labels] = componentList(d.pat);
            if ~isequal(string(u.covComp.ItemsData), cols), set(u.covComp, 'Items', cellstr(labels), 'ItemsData', cellstr(cols)); end
            prev = d.comp; if prev == "", prev = string(u.covComp.Value); end
            c = preferredComponent(prev, cols); u.covComp.Value = char(c);
            if c ~= d.comp
                [~, ~, d.boresight] = calcOrientation(d.pat, d.omega, c, app.Axes, app.PeakPct, app.PeakExcess); d.comp = c; node.NodeData = d;
                if u.covOrient.Value == 0, app.covOrientChanged(); end
            end
            key = sprintf('%s|%s|%d', d.path, c, d.rev);   % Threshold window is only a PRESET: re-applied when pattern/component/data change.
            if ~strcmp(app.cov.presetKey, key), app.covSetRange(displayRange(d.pat.(c), app.PeakPct, app.PeakExcess), 'threshold'); app.cov.presetKey = key; end
        end

        function node = covTarget(app)
            % Pattern node to operate on: the selection's pattern ancestor, else the most recently added pattern.
            n = app.ui.tree.SelectedNodes; node = [];
            if ~isempty(n), n = n(1); while isa(n, 'matlab.ui.container.TreeNode'), if isNodeKind(n, 'pattern'), node = n; return, end, n = n.Parent; end, end
            kids = app.ui.treeRoot.Children;
            for k = numel(kids):-1:1, if isNodeKind(kids(k), 'pattern'), node = kids(k); return, end, end
        end

        function node = covFind(app, fp)
            node = []; kids = app.ui.treeRoot.Children;
            for k = 1:numel(kids), if isstruct(kids(k).NodeData) && strcmp(kids(k).NodeData.path, fp), node = kids(k); return, end, end
        end

        function tf = isChecked(app, nodes)
            c = app.ui.tree.CheckedNodes; tf = false(size(nodes));
            if ~isempty(c), for k = 1:numel(nodes), tf(k) = any(nodes(k) == c); end, end
        end

        %% -------------------------------------------------------------- coverage: compute & jobs
        function t = covThresholds(app)
            u = app.ui; step = max(u.thrStep.Value, 0.1); lo = u.thrMin.Value; hi = max(u.thrMax.Value, lo + step);
            t = (lo:step:hi)'; if t(end) < hi, t(end+1) = hi; end
        end

        function covCompute(app, ~)
            u = app.ui; node = app.covTarget();
            if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return, end
            if strcmp(node.NodeData.path, app.file.path) && ~isempty(app.pat), app.covSyncFromMain(node); end
            try
                d = node.NodeData; T = d.pat; c = u.covComp.Value; thr = app.covThresholds(); conical = u.covConical.Value;
                j = struct('thr', thr, 'tag', 'Sph', 'comp', c, 'label', 'Spherical coverage', 'tableTag', 'Sph', 'conical', conical, 'orientation', ""); mask = true(height(T), 1);
                if conical
                    th0 = u.coneTh.Value; ph0 = mod(u.conePh.Value, 360); alpha = u.coneAng.Value;
                    mask = cosd(T.Theta)*cosd(th0) + sind(T.Theta)*sind(th0).*cosd(T.Phi - ph0) >= cosd(alpha);   % great-circle distance ≤ α
                    k = u.covOrient.Value; if k == 0, k = d.boresight; end, j.orientation = string(app.Axes.labels{k}); center = app.coneLabel(th0, ph0);
                    j.tag = sprintf('Con_%g_%g_%g', th0, ph0, alpha); j.label = sprintf('Conical coverage (%s) α=%s°', center, fmtNum(alpha));
                    j.tableTag = sprintf('Con %s α%s°', erase(center, ["=", ","]), fmtNum(alpha));
                end
                j.cov = coverageCCDF(T.(c), mask, thr, d.omega); app.covAddJob(node, j); app.covFinalize();
                app.covSetRange([thr(1), thr(end)], 'plot'); u.covResults.Visible = 'on';
                msg = sprintf('Run <b>%d</b>: <b>%s</b> on "<b>%s</b>" (%s, %d thresholds)', app.cov.runID, j.label, d.name, c, numel(thr));
                if conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, j.orientation); end
                app.status(u.covStatus, msg, false);
            catch ME, app.showError(ME, 'Coverage Error'); end
        end

        function node = covAddJob(app, parent, j)
            % Register one coverage curve: plot line + tree node whose NodeData is the single job record.
            u = app.ui; app.cov.runID = app.cov.runID + 1; j.id = app.cov.runID; j.kind = 'job';
            if ~isfield(j, 'conical'), j.conical = false; j.orientation = ""; end
            icon = '📉'; if strcmp(j.tag, 'Res'), icon = '📈'; end
            j.label = sprintf('%s R%d %s · %s', icon, j.id, j.label, j.comp);
            j.line = plot(u.covAxes, j.thr, j.cov, 'LineWidth', 1.6, 'DisplayName', j.label);
            [j.invCov, rows] = unique(j.cov, 'last'); j.invThr = j.thr(rows);   % monotone branch for threshold-at-coverage queries
            node = uitreenode(parent, 'Text', j.label); node.NodeData = j; u.tree.CheckedNodes = [u.tree.CheckedNodes; node];
        end

        function covLoadResults(app, fp, R)
            u = app.ui; [~, name] = fileparts(fp); node = uitreenode(u.treeRoot, 'Text', ['📄 ' name]);
            node.NodeData = struct('kind', 'results', 'name', name, 'path', fp); u.tree.CheckedNodes = [u.tree.CheckedNodes; node];
            thr = R{:, 1}; app.covSetRange([min(thr), max(thr)], 'plot');
            for k = 2:width(R)
                app.covAddJob(node, struct('thr', thr, 'cov', R{:, k}, 'tag', 'Res', 'comp', R.Properties.VariableNames{k}, 'label', 'Results', 'tableTag', 'Res'));
            end
            expand(node); app.covFinalize(); app.status(u.covStatus, sprintf('Coverage results "%s" loaded (%d curves).', name, width(R) - 1), false);
        end

        function covFinalize(app, ~)
            % Sync curve/marker visibility, the legend and the results table with the checked tree nodes.
            u = app.ui; jobs = treeNodes(u.treeRoot, 'job'); on = app.isChecked(jobs); checked = jobs(on);
            expand(u.treeRoot); for k = 1:numel(jobs), expand(jobs(k).Parent); end
            for k = 1:numel(jobs)
                d = jobs(k).NodeData; d.line.Visible = on(k);
                set(findall(u.covAxes, '-regexp', 'Tag', sprintf('^CovQ_%d_', d.id)), 'Visible', on(k)); set(findall(d.line, 'Type', 'datatip'), 'Visible', on(k));
            end
            thr = app.covThresholds();
            if ~isempty(checked), c = arrayfun(@(n) n.NodeData.thr(:), checked, 'UniformOutput', false); thr = unique(vertcat(c{:})); end
            vals = [thr, nan(numel(thr), numel(checked))]; names = [{'Threshold (dB)'}, cell(1, numel(checked))]; lines = gobjects(1, numel(checked)); labels = cell(1, numel(checked));
            for k = 1:numel(checked)
                d = checked(k).NodeData; vals(:, k+1) = interp1(d.thr, d.cov, thr, 'linear', NaN);
                names{k+1} = sprintf('R%d %s %%', d.id, d.tableTag); lines(k) = d.line; labels{k} = d.label;
            end
            u.covTable.Data = array2table(compose('%.2f', vals), 'VariableNames', names);
            if isempty(checked), legend(u.covAxes, 'off'); else, legend(u.covAxes, lines, labels, 'Location', 'southwest', 'Interpreter', 'none'); end
            app.covSetUI();
        end

        function covReset(app, ~)
            u = app.ui; delete(u.treeRoot.Children); delete(allchild(u.covAxes)); legend(u.covAxes, 'off'); u.covTable.Data = table();
            app.cov = struct('runID', 0, 'presetKey', '', 'thrInit', false, 'plotInit', false);
            set(u.covAxes, 'XLimMode', 'auto'); set(u.xSlider, 'Limits', app.DBRange, 'Value', [-40 10]); set([u.xMin, u.xMax], 'Limits', app.DBRange);
            u.xMin.Value = -40; u.xMax.Value = 10; u.covResults.Visible = 'off'; app.covSetUI(); app.status(u.covStatus, 'Coverage workspace reset 🔄', true);
        end

        function covClear(app, ~)
            % Remove DataTips and query projections of the selected node's subtree (checked or not).
            u = app.ui; sel = u.tree.SelectedNodes; if isempty(sel), app.status(u.covStatus, 'Select a node to clear.', true); return, end
            for j = treeNodes(sel, 'job').'
                d = j.NodeData; delete(findall(u.covAxes, '-regexp', 'Tag', sprintf('^CovQ_%d_', d.id))); delete(findall(d.line, 'Type', 'datatip'));
            end
            app.status(u.covStatus, 'Selected DataTips and query markers cleared.', true);
        end

        function covExport(app, ~)
            if ~isempty(app.ui.covTable.Data), app.exportTable(app.ui.covTable.Data, 'coverage_results.csv', 'Coverage results', app.ui.covStatus); end
        end

        function covQuery(app, mode)
            % Project one query (coverage at a threshold, or threshold at a coverage) onto every checked curve under the selection.
            u = app.ui; ax = u.covAxes; sel = u.tree.SelectedNodes; if isempty(sel), app.status(u.covStatus, 'Select a node to query.', true); return, end
            jobs = treeNodes(sel, 'job'); jobs = jobs(app.isChecked(jobs)); if strcmp(mode, 'cov'), q = u.qCov.Value; else, q = u.qThr.Value; end
            hits = 0;
            for j = jobs(:).'
                d = j.NodeData; tag = sprintf('CovQ_%d_%s', d.id, mode); delete(findall(ax, 'Tag', tag));
                [x, y] = covQueryPoint(d, mode, q); if ~isfinite(x) || ~isfinite(y), continue, end
                line(ax, [x x], [ax.YLim(1) y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [app.DBRange(1) x], [y y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                d.line.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", 'XData', '%.2f dB'); dataTipTextRow("Coverage", 'YData', '%.2f %%')];
                datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'FontSize', 9, 'Tag', tag, 'HandleVisibility', 'off'); hits = hits + 1;
            end
            if hits, app.status(u.covStatus, sprintf('Query %g applied to %d curve(s).', q, hits), false);
            else, app.status(u.covStatus, 'Query value is outside the range of the checked curves.', true); end
        end

        %% -------------------------------------------------------------- coverage: UI state
        function covSetUI(app)
            u = app.ui; hasPat = ~isempty(app.covTarget()); hasJobs = ~isempty(treeNodes(u.treeRoot, 'job'));
            set(u.covPatternControls, 'Visible', hasPat, 'Enable', hasPat); set(u.covQueryControls, 'Visible', hasJobs, 'Enable', hasJobs);
            set(u.covCompute, 'Enable', hasPat); set(u.covReset, 'Enable', hasPat || hasJobs); set([u.covExport, u.covClear], 'Enable', hasJobs);
            set([u.covFmtLabel, u.covFmt], 'Visible', hasPat && isGeneric(u.covPath.Value));
            if hasPat, app.covTypeChanged(); end
        end

        function covTypeChanged(app, ~)
            u = app.ui; on = u.covConical.Value; set(u.coneControls, 'Enable', on);
            if on, node = app.covTarget(); if ~isempty(node), app.covSync(node); end, app.covOrientStatus();
            else, u.covStatus.Text = regexprep(char(u.covStatus.Text), '\s*\|\s*Orientation <b>.*?</b>$', ''); end
        end

        function covOrientChanged(app, ~)
            % Auto follows the detected boresight; an explicit axis is authoritative. The cone-centre spinners follow either.
            u = app.ui; k = u.covOrient.Value; node = app.covTarget();
            if k == 0, if isempty(node), return, end, k = node.NodeData.boresight; end
            u.coneTh.Value = app.Axes.theta(k); u.conePh.Value = app.Axes.phi(k); app.covOrientStatus();
        end

        function covOrientStatus(app)
            u = app.ui; if ~u.covConical.Value, return, end
            k = u.covOrient.Value; node = app.covTarget(); if k == 0 && isempty(node), return, end
            if k == 0, k = node.NodeData.boresight; end
            base = regexprep(char(u.covStatus.Text), '\s*\|\s*Orientation <b>.*?</b>$', '');
            app.status(u.covStatus, sprintf('%s | Orientation <b>%s</b>', base, app.Axes.labels{k}), false);
        end

        function covComponentChanged(app, ~)
            node = app.covTarget(); if isempty(node), return, end
            d = node.NodeData; d.comp = ""; node.NodeData = d; app.covSync(node);   % re-detect boresight and re-preset thresholds
        end

        function covTreeSelected(app, ~)
            u = app.ui; sel = u.tree.SelectedNodes;
            for j = treeNodes(u.treeRoot, 'job').', d = j.NodeData; d.line.LineWidth = 1.6 + (~isempty(sel) && j == sel(1)); end   % emphasize the selected curve
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.status(u.covStatus, 'Ready.', false); return, end
            d = sel(1).NodeData; node = app.covTarget(); if ~isempty(node), app.covSync(node); end
            if ~strcmp(d.kind, 'job')
                kind = 'Pattern'; if strcmp(d.kind, 'results'), kind = 'Results'; end
                app.status(u.covStatus, sprintf('%s "<b>%s</b>" — <b>%d</b> coverage job(s).', kind, d.name, numel(sel(1).Children)), false);
                if strcmp(d.kind, 'pattern'), app.covOrientStatus(); end
                return
            end
            shown = round(d.cov, 2); mx = max(shown); im = find(shown == mx, 1, 'last'); if isempty(im), im = 1; end
            parts = {char(d.label)}; if d.conical, parts{end+1} = sprintf('Orientation <b>%s</b>', d.orientation); end
            parts{end+1} = sprintf('Thresholds [%s, %s] dB, step %s', fmtNum(d.thr(1)), fmtNum(d.thr(end)), fmtNum(gridStep(d.thr)));
            t50 = covQueryPoint(d, 'thr', 50);
            if isfinite(t50), parts{end+1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', fmtNum(t50)); else, parts{end+1} = '<b>50%-coverage unavailable</b>'; end
            parts{end+1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmtNum(mx), fmtNum(d.thr(im)));
            app.status(u.covStatus, strjoin(parts, ' | '), false);
        end

        function covSetRange(app, bounds, mode)
            % 'threshold': preset the threshold spinners (never shrinking a previous window). 'plot': X-axis + its spinners/slider.
            u = app.ui; bounds = clampRange(bounds, app.DBRange); R = app.DBRange;
            if strcmp(mode, 'threshold')
                if app.cov.thrInit, bounds = [min(u.thrMin.Value, bounds(1)), max(u.thrMax.Value, bounds(2))]; end
                set(u.thrMin, 'Limits', [R(1), bounds(2) - 0.1], 'Value', bounds(1)); set(u.thrMax, 'Limits', [bounds(1) + 0.1, R(2)], 'Value', bounds(2)); app.cov.thrInit = true;
            else
                if app.cov.plotInit, bounds = [min(u.covAxes.XLim(1), bounds(1)), max(u.covAxes.XLim(2), bounds(2))]; end
                app.cov.plotInit = true; set(u.covAxes, 'XLimMode', 'manual', 'XLim', bounds);
                set(u.xSlider, 'Limits', R, 'Value', bounds); u.xSlider.Limits = bounds;
                set(u.xMin, 'Limits', [R(1), bounds(2) - 0.1], 'Value', bounds(1)); set(u.xMax, 'Limits', [bounds(1) + 0.1, R(2)], 'Value', bounds(2));
            end
        end

        function covXRange(app, event)
            % Plot X-range: the spinners are the master (they define the slider travel); the slider only selects within it.
            u = app.ui; R = app.DBRange;
            if event.Source == u.xSlider
                v = sort(event.Value); if diff(v) <= 0, return, end
                u.xMin.Value = v(1); u.xMax.Value = v(2); set(u.covAxes, 'XLimMode', 'manual', 'XLim', v); return
            end
            b = sort([u.xMin.Value, u.xMax.Value]);
            if diff(b) <= 0, if event.Source == u.xMin, b(2) = min(R(2), b(1) + 0.1); else, b(1) = max(R(1), b(2) - 0.1); end, end
            set(u.xSlider, 'Limits', R, 'Value', b); u.xSlider.Limits = b;
            set(u.xMin, 'Limits', [R(1), b(2) - 0.1], 'Value', b(1)); set(u.xMax, 'Limits', [b(1) + 0.1, R(2)], 'Value', b(2));
            set(u.covAxes, 'XLimMode', 'manual', 'XLim', b);
        end

        function label = coneLabel(app, th, ph)
            % Principal-axis name when the cone centre coincides with ±X/±Y/±Z, else the spherical coordinates.
            A = app.Axes; v = [sind(th)*cosd(ph), sind(th)*sind(ph), cosd(th)];
            k = find([sind(A.theta(:)).*cosd(A.phi(:)), sind(A.theta(:)).*sind(A.phi(:)), cosd(A.theta(:))] * v(:) >= 1 - 1e-9, 1);
            if isempty(k), label = sprintf('θ=%s°, φ=%s°', fmtNum(th), fmtNum(ph)); else, label = A.labels{k}; end
        end

        %% -------------------------------------------------------------- UI construction
        function h = mk(app, kind, parent, row, col, varargin)
            % Create one widget, place it in the parent grid (empty row/col = no layout) and return it.
            switch kind
                case 'label',    h = uilabel(parent, 'HorizontalAlignment', 'right', varargin{:});
                case 'button',   h = uibutton(parent, 'push', varargin{:});
                case 'state',    h = uibutton(parent, 'state', varargin{:});
                case 'dropdown', h = uidropdown(parent, varargin{:});
                case 'spinner',  h = uispinner(parent, varargin{:});
                case 'edit',     h = uieditfield(parent, 'text', varargin{:});
                case 'check',    h = uicheckbox(parent, varargin{:});
                case 'switch',   h = uiswitch(parent, 'slider', varargin{:});
                case 'range',    h = uislider(parent, 'range', 'Limits', app.DBRange, 'Value', app.DBRange, 'Step', 1, varargin{:});
                case 'panel',    h = uipanel(parent, 'FontWeight', 'bold', varargin{:});
                case 'grid',     h = uigridlayout(parent, varargin{:});
                case 'tabgroup', h = uitabgroup(parent, varargin{:});
                case 'tab',      h = uitab(parent, varargin{:});
                case 'axes',     h = uiaxes(parent, varargin{:});
                case 'table',    h = uitable(parent, varargin{:});
                case 'tree',     h = uitree(parent, 'checkbox', varargin{:});
                case 'group',    h = uibuttongroup(parent, varargin{:});
                case 'radio',    h = uiradiobutton(parent, varargin{:});
            end
            if ~isempty(row), h.Layout.Row = row; end
            if ~isempty(col), h.Layout.Column = col; end
        end

        function [tab, g, ax, sl, mn, mx] = patternTab(app, group, name, needsAxes)
            % One full-pattern tab: axes (optional; polar axes are created at startup) + vertical range slider and min/max spinners.
            tab = app.mk('tab', group, [], [], 'Title', name); g = app.mk('grid', tab, [], [], 'ColumnWidth', {'fit','1x'}, 'RowHeight', {'fit','1x','fit'});
            ax = []; if needsAxes, ax = app.mk('axes', g, [1 3], 2, 'Box', 'on'); end
            mx = app.mk('spinner', g, 1, 1, 'Limits', app.DBRange, 'Value', 100, 'Step', 5);
            sl = app.mk('range', g, 2, 1, 'Orientation', 'vertical');
            mn = app.mk('spinner', g, 3, 1, 'Limits', app.DBRange, 'Value', -250, 'Step', 5);
        end

        function t = dataTab(app, group, name, rowName)
            g = app.mk('grid', app.mk('tab', group, [], [], 'Title', name), [], [], 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            t = app.mk('table', g, 1, 1, 'RowName', rowName, 'ColumnSortable', true, 'ColumnRearrangeable', 'on', 'ColumnWidth', '1x');
        end

        function buildUI(app)
            cb = @(f) createCallbackFcn(app, f, true); R = app.DBRange; U = struct();
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — APAT v' app.Version], 'Visible', 'off', 'Position', [100 100 1136 739], 'WindowState', 'maximized');
            app.UIFigure.CloseRequestFcn = cb(@closeRequest);
            U.tabs = app.mk('tabgroup', app.mk('grid', app.UIFigure, [], [], 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}), 1, 1);
            U.tabMain = app.mk('tab', U.tabs, [], [], 'Title', 'Process Pattern 📡');
            U.tabCov = app.mk('tab', U.tabs, [], [], 'Title', 'Compute Coverage 📈');

            % ---- Main tab: parameters ----------------------------------------------------------------
            G = app.mk('grid', U.tabMain, [], [], 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit','2x','fit','1x','fit'});
            P = app.mk('grid', app.mk('panel', G, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️'), [], [], 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x','1x','1x'});
            app.mk('label', P, 1, 1, 'Text', 'Input Pattern:');
            U.path = app.mk('edit', P, 1, [2 8]);
            U.ffdLabel = app.mk('label', P, 1, 9, 'Text', 'FFD Freq:', 'Visible', 'off');
            U.ffd = app.mk('dropdown', P, 1, 10, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', cb(@onFFDChanged));
            U.load = app.mk('button', P, 1, [11 12], 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', cb(@onLoad));
            U.processBtn = app.mk('button', P, 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', cb(@onProcess));
            U.resetBtn = app.mk('button', P, 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', cb(@resetParams));
            U.fmtLabel = app.mk('label', P, 2, [4 5], 'Text', 'Format:', 'Visible', 'off');
            U.fmt = app.mk('dropdown', P, 2, [6 8], 'Items', app.TextFormats, 'ItemsData', app.TextFormatCodes, 'Visible', 'off', 'Tooltip', 'Interpretation of CSV/TXT/DAT pattern files.', 'ValueChangedFcn', cb(@onFormatChanged));
            U.step = app.mk('dropdown', P, 2, [9 10], 'Items', {'STEP','STEP: 1°'}, 'Visible', 'off', 'Enable', 'off', 'ValueChangedFcn', cb(@onStepChanged));
            U.exportBtn = app.mk('button', P, 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@exportResults));
            U.uanBtn = app.mk('button', P, 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@exportUAN));
            U.rxPolLabel = app.mk('label', P, 3, 1, 'Text', 'Rw Sense', 'Visible', 'off');
            U.rxPol = app.mk('dropdown', P, 3, 2, 'Items', {'Auto','RHCP','LHCP'}, 'Visible', 'off');
            U.rwLabel = app.mk('label', P, 3, 3, 'Text', 'Rw (dB)', 'Visible', 'off');
            U.rw = app.mk('spinner', P, 3, 4, 'Value', 6, 'Visible', 'off');
            U.lossLabel = app.mk('label', P, 3, 5, 'Text', 'Loss (−) / Gain (+) dB', 'Visible', 'off');
            U.loss = app.mk('spinner', P, 3, 6, 'Step', 0.1, 'Visible', 'off');
            U.ptLabel = app.mk('label', P, 3, 7, 'Text', 'Tx Pwr (Pt)', 'Visible', 'off');
            U.pt = app.mk('spinner', P, 3, 8, 'Visible', 'off');
            U.ptUnit = app.mk('dropdown', P, 3, 9, 'Items', {'dBW','dBm','Watts'}, 'Visible', 'off');
            U.distLabel = app.mk('label', P, 3, 10, 'Text', 'Distance', 'Visible', 'off');
            U.dist = app.mk('spinner', P, 3, 11, 'Value', 1, 'Visible', 'off');
            U.distUnit = app.mk('dropdown', P, 3, 12, 'Items', {'m','km'}, 'Visible', 'off');
            U.covBtn = app.mk('button', P, 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@toCoverage));

            % ---- Main tab: full pattern & cut panels ---------------------------------------------------
            U.panelFull = app.mk('panel', G, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'Visible', 'off');
            U.plotTabs = app.mk('tabgroup', app.mk('grid', U.panelFull, [], [], 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}), 1, 1);
            [U.tabCtr, ~, U.axCtr, s1, n1, x1] = app.patternTab(U.plotTabs, 'Contour Plot', true);
            [U.tabCir, U.gridCircular, ~, s2, n2, x2] = app.patternTab(U.plotTabs, 'Circular Contour Plot', false);
            [U.tabSph, ~, U.axSph, s3, n3, x3] = app.patternTab(U.plotTabs, '3D Spherical Plot', true);
            [U.tabPol, ~, U.axPol, s4, n4, x4] = app.patternTab(U.plotTabs, '3D Polar Plot', true);
            [U.tabRect3, ~, U.axRect3, s5, n5, x5] = app.patternTab(U.plotTabs, '3D Surface Plot', true);
            U.gainSliders = [s1 s2 s3 s4 s5]; U.gainMins = [n1 n2 n3 n4 n5]; U.gainMaxs = [x1 x2 x3 x4 x5];
            U.panelCut = app.mk('panel', G, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'Visible', 'off');
            U.cutTabs = app.mk('tabgroup', app.mk('grid', U.panelCut, [], [], 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}), 1, 1);
            U.gridPolar = app.mk('grid', app.mk('tab', U.cutTabs, [], [], 'Title', 'Polar Cut Plot'), [], [], 'ColumnWidth', {'fit','0.26x','1x','0.23x'}, 'RowHeight', {'fit','0.25x','1x','fit'});
            U.cutMax = app.mk('spinner', U.gridPolar, 1, 1, 'Limits', R, 'Value', 100, 'Step', 5);
            U.cutSlider = app.mk('range', U.gridPolar, [2 3], 1, 'Orientation', 'vertical');
            U.cutMin = app.mk('spinner', U.gridPolar, 4, 1, 'Limits', R, 'Value', -250, 'Step', 5);
            U.hpbw = app.mk('state', U.gridPolar, 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', cb(@onCutChanged));
            U.hpbwLabel = app.mk('label', U.gridPolar, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            U.gridEcut = app.mk('grid', U.gridPolar, 3, 4, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x','1x','1x'});
            U.cutEt = app.mk('check', U.gridEcut, 1, 1, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', cb(@onCutChanged));
            U.cutEr = app.mk('check', U.gridEcut, 2, 1, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', cb(@onCutChanged));
            U.cutEl = app.mk('check', U.gridEcut, 3, 1, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', cb(@onCutChanged));
            U.exportCut = app.mk('button', U.gridPolar, 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', cb(@exportCut));
            U.axRect = app.mk('axes', app.mk('grid', app.mk('tab', U.cutTabs, [], [], 'Title', 'Rectangular Cut Plot'), [], [], 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}), 1, 1, 'Box', 'on');

            % ---- Main tab: plot control ----------------------------------------------------------------
            U.panelCtrl = app.mk('panel', G, 2, [13 14], 'Title', 'Plot Control 🎨', 'Visible', 'off');
            C = app.mk('grid', U.panelCtrl, [], [], 'RowHeight', repmat({'fit'}, 1, 15));
            app.mk('label', C, 1, 1, 'Text', 'Component');
            U.comp = app.mk('dropdown', C, 1, 2, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', cb(@onComponentChanged));
            app.mk('label', C, 2, 1, 'Text', 'Cut type');
            U.cutType = app.mk('dropdown', C, 2, 2, 'Items', {'Phi','Theta'}, 'ValueChangedFcn', cb(@onCutChanged));
            app.mk('label', C, 3, 1, 'Text', 'Cut value');
            U.cutValue = app.mk('spinner', C, 3, 2, 'Limits', [0 360], 'ValueChangedFcn', cb(@onCutChanged));
            app.mk('label', C, 4, 1, 'Text', 'Cut fields');
            U.basis = app.mk('dropdown', C, 4, 2, 'Items', {'Circular: RCP/LCP','Linear: Etheta/Ephi'}, 'ItemsData', {'Circular','Linear'}, 'Enable', 'off', 'UserData', true, 'ValueChangedFcn', cb(@onCutChanged));
            app.mk('label', C, 5, 1, 'Text', 'Colorbar max');
            U.cmax = app.mk('spinner', C, 5, 2, 'Limits', R, 'Value', 10);
            app.mk('label', C, 6, 1, 'Text', 'Colorbar min');
            U.cmin = app.mk('spinner', C, 6, 2, 'Limits', R, 'Value', -40);
            app.mk('label', C, 7, 1, 'Text', 'Colorbar step');
            U.cstep = app.mk('spinner', C, 7, 2, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', @(~,~) app.applyFullRange());
            app.mk('label', C, 8, 1, 'Text', 'Adjust Colorbar');
            U.applyClim = app.mk('button', C, 8, 2, 'Text', 'Apply', 'Tooltip', 'Apply the min/max window to the full-pattern plots and the cut.', ...
                'ButtonPushedFcn', @(~,~) app.setRange('all', [app.ui.cmin.Value, app.ui.cmax.Value]));
            app.mk('label', C, 9, 1, 'Text', '3D view');
            U.view3D = app.mk('dropdown', C, 9, 2, 'Items', {'Isometric','Top (+Z)','Bottom (-Z)','Right (+X)','Left (-X)','Front (-Y)','Back (+Y)'}, ...
                'ItemsData', {'iso','top','bottom','right','left','front','back'}, 'ValueChangedFcn', @(~,~) app.on3DView());
            pad = @(n) repmat(char(160), 1, n);   % non-breaking padding centres the switch captions
            U.phiSpan = app.mk('switch', C, 10, [1 2], 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°','-180° to 180°'}, 'ValueChangedFcn', @(~,~) app.onAngularChanged());
            U.thetaSpan = app.mk('switch', C, 11, [1 2], 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°','-90° to 90°'}, 'ValueChangedFcn', @(~,~) app.onAngularChanged());
            U.plane = app.mk('switch', C, 12, [1 2], 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E','H'}, 'ValueChangedFcn', cb(@onPlaneSwitch));
            U.overlay = app.mk('check', C, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', @(~,~) app.onOverlayToggled());
            U.pob = app.mk('check', C, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', @(s,~) app.toggleTag('APAT_POB', s.Value));
            U.hpbwTips = app.mk('check', C, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', @(s,~) app.toggleTag('APAT_HPBW', s.Value));

            % ---- Main tab: data tables & status ------------------------------------------------------
            U.filter = app.mk('dropdown', G, 3, [13 14], 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Visible', 'off', 'ValueChangedFcn', cb(@filterOutput));
            U.tabData = app.mk('tabgroup', G, 4, [1 14], 'Visible', 'off');
            U.tableOut = app.dataTab(U.tabData, 'Results 📤', 'numbered'); U.tableOut.Visible = 'off';
            U.tableIn = app.dataTab(U.tabData, 'Input 📥', 'numbered'); U.tableIn.Visible = 'off';
            U.tableMeta = app.dataTab(U.tabData, 'Metadata 📋', {}); set(U.tableMeta, 'ColumnName', {'Property','Value'}, 'ColumnWidth', {220, 'auto'});
            U.status = app.mk('label', G, 5, [1 14], 'Text', 'Ready 🚀', 'Interpreter', 'html', 'HorizontalAlignment', 'left');

            % ---- Coverage tab ----------------------------------------------------------------------
            G2 = app.mk('grid', U.tabCov, [], [], 'ColumnWidth', {'0.75x','fit','1x','fit','1x'}, 'RowHeight', {'0.25x','1x','fit'});
            Q = app.mk('grid', app.mk('panel', G2, 1, [1 5], 'Title', 'Inputs & Parameters 🎛️'), [], [], 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x','fit','fit','fit'});
            U.covType = app.mk('group', Q, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', cb(@covTypeChanged));
            U.covSpherical = app.mk('radio', U.covType, [], [], 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            U.covConical = app.mk('radio', U.covType, [], [], 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            U.covOrientLabel = app.mk('label', Q, 3, 1, 'Text', 'Orientation 🧭:');
            U.covOrient = app.mk('dropdown', Q, 3, 2, 'Items', [{'Auto'}, app.Axes.labels], 'ItemsData', 0:6, 'ValueChangedFcn', cb(@covOrientChanged));
            U.covCompLabel = app.mk('label', Q, 4, 1, 'Text', 'Component:');
            U.covComp = app.mk('dropdown', Q, 4, 2, 'Items', {'E_Total_dB'}, 'ValueChangedFcn', cb(@covComponentChanged));
            app.mk('label', Q, 1, 3, 'Text', 'Antenna Pattern:');
            U.covPath = app.mk('edit', Q, 1, [4 8]);
            U.covLoad = app.mk('button', Q, 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', cb(@covLoad));
            U.covCompute = app.mk('button', Q, 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', cb(@covCompute));
            U.thrMinLabel = app.mk('label', Q, 2, 3, 'Text', 'Threshold Min (dB):');
            U.thrMin = app.mk('spinner', Q, 2, 4, 'Limits', R, 'Value', -40);
            U.thrMaxLabel = app.mk('label', Q, 2, 5, 'Text', 'Threshold Max (dB):');
            U.thrMax = app.mk('spinner', Q, 2, 6, 'Limits', R, 'Value', 10);
            U.thrStepLabel = app.mk('label', Q, 2, 7, 'Text', 'Step (dB):');
            U.thrStep = app.mk('spinner', Q, 2, 8, 'Limits', [0.1 100], 'Value', 1);
            U.covReset = app.mk('button', Q, 2, 9, 'Text', '🔄 Reset', 'Enable', 'off', 'ButtonPushedFcn', cb(@covReset));
            U.covExport = app.mk('button', Q, 2, 10, 'Text', '💾 Export Results', 'Enable', 'off', 'ButtonPushedFcn', cb(@covExport));
            U.coneThLabel = app.mk('label', Q, 3, 3, 'Text', 'Cone θ₀ (°):');
            U.coneTh = app.mk('spinner', Q, 3, 4, 'Limits', [0 180]);
            U.conePhLabel = app.mk('label', Q, 3, 5, 'Text', 'Cone φ₀ (°):');
            U.conePh = app.mk('spinner', Q, 3, 6, 'Limits', [0 360]);
            U.coneAngLabel = app.mk('label', Q, 3, 7, 'Text', 'Cone Angle α (°):');
            U.coneAng = app.mk('spinner', Q, 3, 8, 'Limits', [0 180], 'Value', 45);
            U.covClear = app.mk('button', Q, 3, 9, 'Text', '🧹 Clear DataTips', 'Enable', 'off', 'ButtonPushedFcn', cb(@covClear));
            U.toMain = app.mk('button', Q, 3, 10, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~,~) set(app.ui.tabs, 'SelectedTab', app.ui.tabMain));
            U.qCovLabel = app.mk('label', Q, 4, 3, 'Text', 'Coverage @ dB:');
            U.qCov = app.mk('spinner', Q, 4, 4, 'ValueDisplayFormat', '%g dB');
            U.qCovBtn = app.mk('button', Q, 4, 5, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', @(~,~) app.covQuery('cov'));
            U.qThrLabel = app.mk('label', Q, 4, 6, 'Text', 'Threshold @ %:');
            U.qThr = app.mk('spinner', Q, 4, 7, 'Value', 50, 'Limits', [0 100], 'ValueDisplayFormat', '%g%%');
            U.qThrBtn = app.mk('button', Q, 4, 8, 'Text', '🔍 Query Threshold', 'ButtonPushedFcn', @(~,~) app.covQuery('thr'));
            U.covFmtLabel = app.mk('label', Q, 4, 9, 'Text', 'Format:', 'Visible', 'off');
            U.covFmt = app.mk('dropdown', Q, 4, 10, 'Items', app.TextFormats, 'ItemsData', app.TextFormatCodes, 'Visible', 'off', 'ValueChangedFcn', cb(@covFmtChanged));
            U.coneControls = [U.coneThLabel, U.coneTh, U.conePhLabel, U.conePh, U.coneAngLabel, U.coneAng, U.covOrientLabel, U.covOrient];
            U.covQueryControls = [U.qCovLabel, U.qCov, U.qCovBtn, U.qThrLabel, U.qThr, U.qThrBtn];
            U.covPatternControls = [U.covType, U.coneControls, U.covCompLabel, U.covComp, U.thrMinLabel, U.thrMin, U.thrMaxLabel, U.thrMax, U.thrStepLabel, U.thrStep];
            U.covResults = app.mk('panel', G2, 2, [1 5], 'Title', 'Results', 'Visible', 'off');
            W = app.mk('grid', U.covResults, [], [], 'ColumnWidth', {'1x','fit','1x','fit','1x'}, 'RowHeight', {'1x','fit'});
            U.tree = app.mk('tree', W, [1 2], 1, 'SelectionChangedFcn', cb(@covTreeSelected), 'CheckedNodesChangedFcn', cb(@covFinalize));
            U.treeRoot = uitreenode(U.tree, 'Text', 'Coverage Results');
            U.covAxes = app.mk('axes', W, 1, [2 4], 'Box', 'on', 'Layer', 'top', 'YLim', [0 100], 'NextPlot', 'add', 'XGrid', 'on', 'YGrid', 'on');
            title(U.covAxes, 'Coverage vs Threshold'); xlabel(U.covAxes, 'Threshold (dB)'); ylabel(U.covAxes, 'Coverage (%)'); U.covAxes.Interactions = dataTipInteraction;
            U.covTable = app.mk('table', W, [1 2], 5, 'RowName', {}, 'ColumnWidth', '1x');
            U.xMin = app.mk('spinner', W, 2, 2, 'Limits', R, 'Value', -40, 'ValueChangedFcn', cb(@covXRange));
            U.xSlider = app.mk('range', W, 2, 3, 'Value', [-40 10], 'ValueChangedFcn', cb(@covXRange), 'ValueChangingFcn', cb(@covXRange));
            U.xMax = app.mk('spinner', W, 2, 4, 'Limits', R, 'Value', 10, 'ValueChangedFcn', cb(@covXRange));
            U.covStatus = app.mk('label', G2, 3, [1 5], 'Text', 'Ready 🚀', 'Interpreter', 'html', 'HorizontalAlignment', 'left');
            app.ui = U; app.UIFigure.Visible = 'on';
        end
    end

    %% ------------------------------------------------------------------ self-test
    methods (Access = public)
        function r = runSelfTest(app)
            %RUNSELFTEST Deterministic checks of the numerical core (solid angle, peak policy, resampling, HPBW, CCDF, readers, pattern math).
            [ph, th] = meshgrid(0:30:330, 0:30:180); n = numel(th); T = table(th(:), ph(:), 10*cosd(th(:)).^2, 'VariableNames', {'Theta','Phi','E_Total_dB'});
            w = solidWeights(T.Theta, T.Phi); r.solidAngle = abs(sum(w) - 4*pi) < 1e-9;
            [~, pk, k] = calcOrientation(T, w, "E_Total_dB", app.Axes, app.PeakPct, app.PeakExcess); r.orientation = k == 1 && isfinite(pk.value);
            [p2, t2] = meshgrid(0:2:358, 0:2:180); T2 = table(t2(:), p2(:), 12*cosd(t2(:)).^2 - 0.5*sind(p2(:)).^2, 'VariableNames', {'Theta','Phi','E_Total_dB'});
            Q = resampleTo1deg(normalizePattern(T2)); native = mod(Q.Theta, 2) == 0 & mod(Q.Phi, 2) == 0;
            r.resampling = height(Q) == 181*361 && max(abs(Q.E_Total_dB(native) - (12*cosd(Q.Theta(native)).^2 - 0.5*sind(Q.Phi(native)).^2))) < 1e-9;
            r.displayRange = isequal(displayRange([3.2; -100], app.PeakPct, app.PeakExcess), [-45 5]);
            spike = repmat(0.02, 1e5, 1); spike(1) = 10.02; ps = resolvePeak(spike, app.PeakPct, app.PeakExcess);
            r.isolatedSpike = ps.wasAdjusted && abs(ps.value - 0.02) < 1e-12 && ps.rawIndex == 1 && isequal(displayRange(spike, app.PeakPct, app.PeakExcess), [-45 5]);
            r.arSemantics = all(arrayfun(@isAR, ["AR","AR_dB","AR dB","Axial Ratio","Axial_Ratio"])) && ~isAR("E_Total_dB");
            a = (0:359)'; r.hpbw = abs(calcHPBW(a, -3*((mod(a + 180, 360) - 180)/20).^2) - 40) < 1e-9;
            r.coverage = isequal(coverageCCDF([0; 10; 20; 30], true(4, 1), [5; 15; 25; 35], ones(4, 1)), [75; 50; 25; 0]);
            S = table(th(:), ph(:), ones(n, 1), zeros(n, 1), zeros(n, 1), -ones(n, 1), 'VariableNames', {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'});
            [P, i] = calcPattern(S, struct('GainLoss_dB', 0, 'RxMode', "Auto", 'RxAR_dB', 6, 'FieldScale', 1, 'Pt_dBW', 0, 'R_m', 1), app.PeakPct, app.PeakExcess);
            r.patternMath = strcmp(i.pol, 'Circular (RHCP)') && all(abs(P.AR_dB) < 1e-9) && all(abs(P.E_Total_dB - 10*log10(2)) < 1e-9) && all(P.E_LCP_dB < -250);
            f = [tempname '.ffd']; fid = fopen(f, 'w'); c = onCleanup(@() delete(f)); %#ok<NASGU>
            fprintf(fid, '0 180 3\n-180 180 3\n'); fprintf(fid, '%d 0 0 1\n', 1:9); fclose(fid); out = readPattern(f, 'ffd');
            r.ffdReader = strcmp(out.meta.source, 'HFSS FFD') && height(out.blocks{1}) == 9;
            names = fieldnames(r); failed = names(~structfun(@(v) v, r)); r.pass = isempty(failed);
            if ~r.pass, error('APAT:SelfTest', 'Self-test failed: %s', strjoin(failed, ', ')); end
        end
    end
end

%% ====================================================================== I/O (UI-independent)
function out = readPattern(fp, fmt, cached)
%readPattern Read any supported source into a source struct:
%   raw    : file content as read (Input tab)         blocks : {table Theta Phi Re_Eth Im_Eth Re_Eph Im_Eph} or {gain table}
%   freqs  : per-block frequency in Hz (NaN unknown)  meta   : source, isGainOnly, isCoverage, isDep [, summary]
if nargin < 3, cached = table(); end
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.')); fmt = string(fmt);
out = struct('raw', table(), 'blocks', {{}}, 'freqs', NaN, 'meta', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false));
names = {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'};
field = @(th, ph, Eth, Eph) table(th(:), ph(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', names);
switch ext
    case {'XLSX','XLS'}
        out = readExcelMatrix(fp); return
    case {'CSV','TXT','DAT'}   % generic text: coverage results, gain pattern, or six-column E-field
        T = cached;
        if isempty(T)
            opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ','\t',',',';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
            opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
            T = rmmissing(readtable(fp, opts));
        end
        n = width(T); assert(n >= 2 && ~isempty(T), 'readFile:InvalidFormat', 'The file needs at least two numeric columns.');
        vn = string(T.Properties.VariableNames); headed = ~all(startsWith(vn, "Var")); c1 = T{:, 1}; c2 = T{:, 2};
        covHeader = contains(lower(vn(1)), "threshold") || any(contains(lower(vn(2:end)), "coverage"));
        if (fmt == "gain" || n < 6 || covHeader) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
            if ~headed, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:n-1))]; end
            out.raw = T; out.meta.isCoverage = true; return
        end
        if fmt == "gain"   % the wider-spanning of the first two columns is φ
            if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi','Theta'}; else, T.Properties.VariableNames(1:2) = {'Theta','Phi'}; end
            T = movevars(T, 'Theta', 'Before', 1); out.raw = T; out.blocks = {T}; out.meta.isGainOnly = true; return
        end
        assert(n >= 6, 'readFile:TextEFieldColumns', 'The selected E-field format requires six numeric columns.');
        V = T{:, 3:6}; layout = "re/im";
        if endsWith(fmt, "magphase")   % grouped (mag mag phase phase) vs interleaved (mag phase mag phase)
            big = max(abs(V), [], 1, 'omitnan') > 100; layout = "grouped";
            if big(2) && ~big(3), V = V(:, [1 3 2 4]); layout = "interleaved"; end
            c = 10.^(V(:, 1:2)/20) .* exp(1i*deg2rad(V(:, 3:4)));
        else
            c = complex(V(:, [1 3]), V(:, [2 4]));
        end
        if startsWith(fmt, "linear"), Eth = c(:, 1); Eph = c(:, 2);
        elseif startsWith(fmt, "rcp"), [Eth, Eph] = circToLinear(c(:, 1), c(:, 2));
        else, [Eth, Eph] = circToLinear(c(:, 2), c(:, 1)); end
        if ~headed, T.Properties.VariableNames(1:2) = {'Theta','Phi'}; end
        out.meta.source = sprintf('Generic text (%s, %s)', fmt, layout); out.raw = T; out.blocks = {field(c1, c2, Eth, Eph)}; return
    case 'CUT'   % TICRA/GRASP: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks
        L = readlines(fp); L(strlength(strtrim(L)) == 0) = []; k = 1; th = {}; ph = {}; D = {}; icomp = 1; icut = 1;
        while k < numel(L)
            p = sscanf(L(k+1), '%f'); assert(numel(p) >= 7, 'readFile:cut', 'Could not parse a GRASP cut parameter line.'); m = p(3); icomp = p(5); icut = p(6);
            block = reshape(sscanf(strjoin(L(k+2:k+1+m), ' '), '%f'), 2*p(7), []).';
            th{end+1} = p(1) + (0:m-1)'*p(2); ph{end+1} = repmat(p(4), m, 1); D{end+1} = block(:, 1:4); k = k + 2 + m; %#ok<AGROW>
        end
        th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:});
        if icut == 2, [th, ph] = deal(ph, th); end                       % ICUT=2: φ swept, θ constant
        neg = th < 0; ph(neg) = ph(neg) + 180; th(neg) = -th(neg);         % fold negative θ onto the opposite φ
        if isscalar(unique(ph)), m = numel(th); th = repmat(th, 36, 1); D = repmat(D, 36, 1); ph = repelem((0:10:350)', m); end   % single cut → body of revolution
        c1 = complex(D(:, 1), D(:, 2)); c2 = complex(D(:, 3), D(:, 4)); rawNames = names(3:6);
        if icomp == 2, [Eth, Eph] = circToLinear(c1, c2); rawNames = {'Re_RHCP','Im_RHCP','Re_LHCP','Im_LHCP'}; else, Eth = c1; Eph = c2; end
        out.meta.source = 'TICRA/GRASP CUT'; out.raw = array2table([th, ph, D], 'VariableNames', [names(1:2), rawNames]); out.blocks = {field(th, ph, Eth, Eph)}; return
    otherwise   % far-field tables with a text header
        [nHdr, ffd] = findHeader(fp);
        opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ','\t',',',';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
        M = readmatrix(fp, setvartype(opts, opts.VariableNames, 'double')); M = M(~all(isnan(M), 2), 1:min(end, 6));
        switch ext
            case {'FZ','UAN'}    % XGTD: Theta Phi |Eθ|dB |Eφ|dB ∠Eθ° ∠Eφ°
                out.meta.source = ['XGTD ' ext]; out.raw = array2table(M, 'VariableNames', {'Theta','Phi','E_TH_dB','E_PH_dB','E_TH_deg','E_PH_deg'});
                th = M(:, 1); ph = M(:, 2); Eth = 10.^(M(:, 3)/20) .* exp(1i*deg2rad(M(:, 5))); Eph = 10.^(M(:, 4)/20) .* exp(1i*deg2rad(M(:, 6)));
            case 'OUT'           % TICRA/GRASP: Theta Phi Re/Im(POL1=RHCP) Re/Im(POL2=LHCP)
                out.meta.source = 'TICRA/GRASP OUT'; out.raw = array2table(M, 'VariableNames', {'Theta','Phi','Re_RHCP','Im_RHCP','Re_LHCP','Im_LHCP'});
                th = M(:, 1); ph = M(:, 2); [Eth, Eph] = circToLinear(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)));
            case {'FFS','FFE'}   % CST (Phi Theta …) / FEKO (Theta Phi …): Re/Im(Eθ) Re/Im(Eφ), extra columns ignored
                if strcmp(ext, 'FFS'), out.meta.source = 'CST FFS'; th = M(:, 2); ph = M(:, 1); rawNames = [names([2 1]), names(3:6)];
                else, out.meta.source = 'FEKO FFE'; th = M(:, 1); ph = M(:, 2); rawNames = names; end
                out.raw = array2table(M, 'VariableNames', rawNames); Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
            case 'FFD'           % HFSS: header θ/φ axes; Re/Im(Eθ) Re/Im(Eφ) rows, one block per frequency ("Frequency f" separator rows)
                assert(ffd.ok, 'readFile:ffd', 'FFD header (theta/phi ranges) not found.');
                thA = linspace(ffd.theta(1), ffd.theta(2), ffd.theta(3))'; phA = linspace(ffd.phi(1), ffd.phi(2), ffd.phi(3))';
                th = repelem(thA, numel(phA)); ph = repmat(phA, numel(thA), 1); per = numel(th);
                sep = isnan(M(:, 1)); freqs = [ffd.freq(:); M(sep & ~isnan(M(:, 2)), 2)].'; rows = M(~sep, 1:4); nb = size(rows, 1)/per;
                assert(mod(size(rows, 1), per) == 0, 'readFile:ffd', 'FFD row count does not match the theta/phi grid.');
                freqs(end+1:nb) = NaN; freqs = freqs(1:nb); out.freqs = freqs; out.meta.source = 'HFSS FFD'; out.meta.isDep = nb > 1 || any(isfinite(freqs));
                out.blocks = cell(1, nb);
                for b = 1:nb, r = rows((b-1)*per + (1:per), :); out.blocks{b} = field(th, ph, complex(r(:, 1), r(:, 2)), complex(r(:, 3), r(:, 4))); end
                out.raw = out.blocks{1}; return
            otherwise, error('readFile:unsupported', 'Unsupported format: %s', ext);
        end
        out.blocks = {field(th, ph, Eth, Eph)};
end
end

function [nHdr, ffd] = findHeader(fp)
%findHeader Number of leading non-data lines; parses the HFSS FFD header (two θ/φ triples + optional frequency list) when present.
L = readlines(fp); ffd = struct('ok', false, 'theta', [], 'phi', [], 'freq', []); ne = find(strlength(strtrim(L)) > 0, 3);
if numel(ne) >= 2
    t = sscanf(L(ne(1)), '%f'); p = sscanf(L(ne(2)), '%f');
    if numel(t) == 3 && numel(p) == 3
        nHdr = ne(2); ffd = struct('ok', all(isfinite([t; p])) && t(3) >= 1 && p(3) >= 1, 'theta', [t(1) t(2) round(t(3))], 'phi', [p(1) p(2) round(p(3))], 'freq', []);
        if numel(ne) > 2
            tok = regexp(char(strtrim(L(ne(3)))), '^frequenc(?:y|ies)\s+(.+)$', 'tokens', 'once', 'ignorecase');
            if ~isempty(tok), f = sscanf(tok{1}, '%f'); if ~isscalar(f), ffd.freq = f(:); end, nHdr = ne(3); end   % a bare count keeps the row as header
        end
        if ffd.ok, return, end
    end
end
num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?'; head = cellstr(L(1:min(500, end)));
isData = ~cellfun(@isempty, regexp(head, ['^\s*' num '(?:[\s,;]+' num '){3,}\s*$'], 'once'));
nHdr = find(isData, 1) - 1; if isempty(nHdr), nHdr = 0; end
end

function out = readExcelMatrix(fp)
%readExcelMatrix Excel matrix workbooks: sheet 1 = summary; fixed component sheets hold C3-origin θ×φ matrices (dBi / degrees).
sheets = string(sheetnames(fp)); has = @(list) all(ismember(lower(list), lower(sheets)));
circ = ["RHCP_Gain_dBi","RHCP_Phase_degrees","LHCP_Gain_dBi","LHCP_Phase_degrees"]; lin = ["Etheta_Gain_dBi","Etheta_Phase_degrees","Ephi_Gain_dBi","Ephi_Phase_degrees"];
assert(has(lin) || has(circ), 'readFile:ExcelMatrixFormat', 'Unsupported workbook: no Etheta/Ephi or RHCP/LHCP component sheets found.');
req = [lin(has(lin) & true(1, 4)), circ(has(circ) & true(1, 4))]; M = struct(); th = []; ph = [];
for s = req
    [t, p, D] = readExcelSheet(fp, sheets(find(strcmpi(sheets, s), 1)));
    if isempty(th), th = t; ph = p;
    else, assert(isequal(size(t), size(th)) && isequal(size(p), size(ph)) && max(abs(t - th)) < 1e-9 && max(abs(p - ph)) < 1e-9, 'readFile:ExcelMatrixGrid', 'All component sheets must share one theta/phi grid.'); end
    M.(char(s)) = D;
end
mp = @(g, d) 10.^(g/20) .* exp(1i*deg2rad(d));
if has(lin), Eth = mp(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = mp(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees); code = 1 + 2*has(circ);
else, [Eth, Eph] = circToLinear(mp(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), mp(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees)); code = 2; end
[phG, thG] = meshgrid(ph, th);
block = table(thG(:), phG(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'});
raw = block; for s = req, raw.(char(s)) = M.(char(s))(:); end
summary = readExcelSummary(fp, sheets(1)); freqs = NaN;
k = find(contains(lower(summary(:, 1)), 'simulation freq'), 1); if ~isempty(k), f = str2double(summary{k, 2}); if isfinite(f), freqs = f*1e6; end, end
meta = struct('source', sprintf('Excel Matrix Format %d', code), 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'summary', {summary});
out = struct('raw', raw, 'blocks', {{block}}, 'freqs', freqs, 'meta', meta);
end

function [th, ph, D] = readExcelSheet(fp, sheet)
%readExcelSheet One C3-origin matrix: row 2 = φ axis (C→), column B = θ axis (3↓). readcell keeps worksheet coordinates intact.
C = readcell(fp, 'Sheet', char(sheet)); assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'readFile:ExcelMatrixSheet', 'Sheet "%s" has no C3-origin matrix.', sheet);
isNum = @(x) isnumeric(x) && isscalar(x) && isfinite(x); pm = cellfun(isNum, C(2, 3:end)); tm = cellfun(isNum, C(3:end, 2));
np = find(~pm, 1) - 1; if isempty(np), np = numel(pm); end, nt = find(~tm, 1) - 1; if isempty(nt), nt = numel(tm); end
assert(nt > 0 && np > 0 && ~any(pm(np+1:end)) && ~any(tm(nt+1:end)), 'readFile:ExcelMatrixAxis', 'Sheet "%s" has a missing or gapped theta/phi axis.', sheet);
ph = cell2mat(C(2, 3:2+np)); th = cell2mat(C(3:2+nt, 2)); cells = C(3:2+nt, 3:2+np);
assert(all(cellfun(isNum, cells), 'all'), 'readFile:ExcelMatrixSheet', 'Sheet "%s" contains nonnumeric/missing samples.', sheet); D = cell2mat(cells);
assert(all(diff(th) > 0) && all(diff(ph) > 0) && th(1) >= -1e-9 && th(end) <= 180 + 1e-9 && ph(1) >= -1e-9 && ph(end) <= 360 + 1e-9, ...
    'readFile:ExcelMatrixAxis', 'Sheet "%s": axes must be increasing with θ∈[0,180] and φ∈[0,360].', sheet);
end

function rows = readExcelSummary(fp, sheet)
%readExcelSummary Label/value pairs of the template summary sheet (column-B labels; first non-empty of C:E as value) for the Metadata tab.
rows = cell(0, 2);
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return, end
txt = @(x) (ischar(x) || isstring(x)) && strlength(strtrim(string(x))) > 0;
for r = 1:size(C, 1)
    if size(C, 2) < 3 || ~txt(C{r, 2}), continue, end
    v = C(r, 3:min(5, end)); v = v(cellfun(@(x) txt(x) || (isnumeric(x) && ~isempty(x)), v)); if isempty(v), continue, end
    rows(end+1, :) = {char(strtrim(string(C{r, 2}))), char(strtrim(string(v{1})))}; %#ok<AGROW>
end
end

function [Eth, Eph] = circToLinear(Er, El)
%circToLinear RHCP/LHCP → θ/φ components (IEEE sense, unit power).
Eth = (Er + El)/sqrt(2); Eph = (Er - El)/(1i*sqrt(2));
end

function writeTable(T, fp)
%writeTable TXT is tab-delimited; CSV/XLSX use writetable defaults.
if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
end

function tf = isGeneric(fp)
%isGeneric Generic text sources need the user-selected format.
[~, ~, e] = fileparts(fp); tf = ismember(lower(e), {'.csv','.txt','.dat'});
end

%% ====================================================================== numerical core (UI-independent)
function T = normalizePattern(T)
%normalizePattern Canonical sphere: θ∈[0,180], φ∈[0,360) plus one closing φ=360 copy of φ=0; unique directions; 5-decimal rounding.
th = T.Theta;
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, T.Theta = 90 - th;                             % elevation convention
    else, m = th < 0; T.Theta(m) = -th(m); T.Phi(m) = T.Phi(m) + 180; end               % negative polar θ ⇒ opposite φ
end
T.Theta = mod(T.Theta, 360); over = T.Theta > 180; T.Theta(over) = 360 - T.Theta(over); T.Phi(over) = T.Phi(over) + 180;
num = varfun(@isnumeric, T, 'OutputFormat', 'uniform'); T{:, num} = round(T{:, num}, 5);   % removes 1e-15 seam artefacts once, at the boundary
T.Phi = mod(T.Phi, 360);
[~, u] = unique([T.Phi, T.Theta], 'rows', 'first'); T = T(u, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function R = resampleTo1deg(S)
%resampleTo1deg Canonical 1° θ×φ grid (181×361) from a canonical source. E-fields: Re/Im interpolated; gain-only: linear power.
%   Integer-degree samples that already form a complete grid are simply picked (no interpolation at all).
names = S.Properties.VariableNames(3:end); ud = S.Properties.UserData; gainOnly = isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly;
[thQ, phQ] = ndgrid((0:180)', (0:360)'); R = table(thQ(:), phQ(:), 'VariableNames', {'Theta','Phi'}); S = S(S.Phi < 360, :);
whole = abs(S.Theta - round(S.Theta)) < 1e-9 & abs(S.Phi - round(S.Phi)) < 1e-9;
if nnz(whole) == 181*360, S = S(whole, :); end
th = unique(S.Theta); ph = unique(S.Phi); regular = numel(th)*numel(ph) == height(S);
for k = 1:numel(names)
    v = double(S.(names{k})); if gainOnly, v = 10.^(v/10); end
    if regular
        [~, it] = ismember(S.Theta, th); [~, ip] = ismember(S.Phi, ph); G = nan(numel(th), numel(ph)); G(sub2ind(size(G), it, ip)) = v;
        q = interp2([ph; ph(1) + 360].', th, [G, G(:, 1)], phQ, thQ, 'linear');           % periodic φ closure; NaN outside the θ span
    else
        F = scatteredInterpolant(S.Phi, S.Theta, v, 'linear', 'none'); q = F(phQ, thQ);
    end
    if gainOnly, q = 10*log10(max(q, realmin)); end
    R.(names{k}) = q(:);
end
R.Properties.UserData = ud;
end

function [P, info] = calcPattern(S, prm, pct, excess)
%calcPattern Processed pattern table from a canonical source (E-field or gain-only). Every derived column is produced here, once.
%   E-field: total/component gains, signed AR, PLF and polarization-corrected gain, phases, EIRP / PFD / E-field at range R.
ud = S.Properties.UserData; info = struct('pol', 'n/a', 'pairs', struct('Linear', ["E_TH","E_PH"], 'Circular', ["E_RCP","E_LCP"]));
if isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly
    P = S; P{:, 3:end} = P{:, 3:end} + prm.GainLoss_dB; info.peak = resolvePeak(P{:, 3}, pct, excess); return
end
Eth = complex(S.Re_Eth, S.Im_Eth)*prm.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph)*prm.FieldScale;
Er = (Eth + 1i*Eph)/sqrt(2); El = (Eth - 1i*Eph)/sqrt(2); [aTh, aPh, aR, aL] = deal(abs(Eth), abs(Eph), abs(Er), abs(El));
total = 10*log10(max(aTh.^2 + aPh.^2, eps)); info.peak = resolvePeak(total, pct, excess);
% Dominant components (mean power) drive the co/cross ordering, the polarization label and the Auto Rx sense.
pw = [mean(aTh.^2, 'omitnan'), mean(aPh.^2, 'omitnan'), mean(aR.^2, 'omitnan'), mean(aL.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP","E_LCP"], ["RHCP","LHCP"]));
elseif pw(1) >= pw(2), info.pol = 'Linear (Vertical)'; else, info.pol = 'Linear (Horizontal)'; end
% Signed axial ratio: + right-hand, − left-hand; exactly equal circular components (linear limit) sit on the −100 dB floor.
delta = aR - aL; sense = sign(delta); sense(~isfinite(delta)) = 0; ar = (aR + aL) ./ max(abs(delta), eps);
arDB = min(20*log10(ar), 250) .* sense; arDB(isfinite(delta) & abs(delta) <= eps*max(aR + aL, 1)) = -100;
% Polarization loss factor against an elliptical wave (axial ratio Rw, sense from the UI or Auto = the antenna's own sense),
% with the conservative worst-case 90° tilt between the two polarization ellipses (cos 2Δτ = −1).
if prm.RxMode == "Auto", ws = 2*(info.pairs.Circular(1) == "E_RCP") - 1; elseif prm.RxMode == "RHCP", ws = 1; else, ws = -1; end
Ra = ar .* sense; Ra(sense == 0) = 1e12; Rw = ws*10^(prm.RxAR_dB/20);
plf = 0.5 + (4*Ra*Rw - (Ra.^2 - 1)*(Rw^2 - 1)) ./ (2*(Ra.^2 + 1)*(Rw^2 + 1)); plfDB = 10*log10(min(max(plf, eps), 1));
eirp = prm.Pt_dBW + total; eirpW = 10.^(eirp/10); dB = @(a) 20*log10(max(a, eps)); deg = @(z) rad2deg(angle(z));
P = table(S.Theta, S.Phi, total, arDB, dB(aR), dB(aL), plfDB, total + plfDB, dB(aTh), dB(aPh), deg(Eth), deg(Eph), deg(Er), deg(El), ...
    eirp, eirpW/(4*pi*prm.R_m^2), sqrt(30*eirpW)/prm.R_m, 'VariableNames', {'Theta','Phi','E_Total_dB','AR_dB','E_RCP_dB','E_LCP_dB','PLF_dB', ...
    'Gain_PolCorrected_dB','E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'});
P.Properties.UserData = ud;
end

function pk = resolvePeak(v, pct, excess)
%resolvePeak Effective peak: the raw maximum unless it exceeds the P(pct) percentile by more than EXCESS dB (an isolated
%   numerical spike); then the highest sample at or below the percentile is used and the spikes are masked out.
v = double(v(:)); pk = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(v)), 'wasAdjusted', false);
if ~any(isfinite(v)), return, end
[pk.rawValue, pk.rawIndex] = max(v); pk.value = pk.rawValue; pk.index = pk.rawIndex; p = percentile(v, pct);
if pk.rawValue > p + excess
    pk.outlierMask = v > p; c = v; c(pk.outlierMask | ~isfinite(v)) = -Inf;
    if any(isfinite(c)), [pk.value, pk.index] = max(c); pk.wasAdjusted = true; else, pk.outlierMask(:) = false; end
end
end

function v = percentile(x, p)
%percentile Percentile with linear interpolation between order statistics (same definition as prctile; no toolbox needed).
x = sort(x(isfinite(x))); n = numel(x); if n == 0, v = NaN; return, end
pos = min(max(p/100*n + 0.5, 1), n); k = floor(pos); v = x(k) + (pos - k)*(x(min(k + 1, n)) - x(k));
end

function [omega, pk, k] = calcOrientation(T, omega, col, A, pct, excess)
%calcOrientation Principal axis (±X/±Y/±Z) whose 45° cone captures the most solid-angle-weighted power of COL; also COL's peak.
if isempty(omega) || numel(omega) ~= height(T), omega = solidWeights(T.Theta, T.Phi); end
g = chooseGain(T, col); pk = resolvePeak(g, pct, excess); g(pk.outlierMask) = NaN;
w = 10.^((g - pk.value)/10) .* omega; w(~isfinite(w)) = 0;
ax = [sind(A.theta(:)).*cosd(A.phi(:)), sind(A.theta(:)).*sind(A.phi(:)), cosd(A.theta(:))];
s = [sind(T.Theta).*cosd(T.Phi), sind(T.Theta).*sind(T.Phi), cosd(T.Theta)];
[~, k] = max(w.' * double(s*ax.' >= cosd(45)));
end

function m = calcMetrics(T, omega, A, k, pct, excess)
%calcMetrics Scalar metrics from total gain: peak, HPBW in the E/H planes of the boresight axis, F/B, directivity, efficiency, AR at peak.
g = chooseGain(T, 'E_Total_dB'); pk = resolvePeak(g, pct, excess); i = pk.index; gm = g; gm(pk.outlierMask) = NaN;
U = sum(10.^(gm/10) .* omega, 'omitnan');                                                      % ∫G dΩ (sr)
m = struct('PeakGain_dB', pk.value, 'PeakTheta_deg', T.Theta(i), 'PeakPhi_deg', T.Phi(i));
[~, back] = min(cosd(T.Theta)*cosd(T.Theta(i)) + sind(T.Theta)*sind(T.Theta(i)).*cosd(T.Phi - T.Phi(i)));   % antipode of the peak
hKind = 'Theta'; if A.theta(k) == 90, hKind = 'Phi'; end                                        % H-plane: orthogonal plane through the axis
[eA, eR] = cutGeometry(T, 'Theta', A.phi(k)); [hA, hR] = cutGeometry(T, hKind, 90);
m.HPBW_EPlane_deg = calcHPBW(eA, g(eR)); m.HPBW_HPlane_deg = calcHPBW(hA, g(hR)); m.FrontBack_dB = pk.value - g(back);
m.PeakDirectivity_dB = 10*log10(max(4*pi*10^(pk.value/10)/max(U, eps), eps));
m.Efficiency_pct = 100*U/(4*pi); if m.Efficiency_pct > 100, m.Efficiency_pct = NaN; end        % only meaningful for calibrated gain
m.AxialRatioAtPeak_dB = NaN; if ismember('AR_dB', T.Properties.VariableNames), m.AxialRatioAtPeak_dB = T.AR_dB(i); end
end

function [ang, rows, fixed, sym, snapped] = cutGeometry(T, kind, req)
%cutGeometry Rows of one great-circle cut of a canonical table.
%   Phi cut  : fixed θ (nearest sample), angle = φ ∈ [0,360].
%   Theta cut: fixed φ (nearest sample) and its opposite φ+180, angle = θ on the near side and 360−θ on the far side.
if strcmp(kind, 'Phi')
    v = unique(T.Theta); [d, j] = min(abs(v - req)); fixed = v(j); rows = find(T.Theta == fixed); [ang, o] = sort(T.Phi(rows)); rows = rows(o); sym = 'θ';
else
    v = unique(T.Phi(T.Phi < 360)); [d, j] = min(abs(mod(v - req + 180, 360) - 180)); fixed = v(j); [~, jo] = min(abs(mod(v - fixed, 360) - 180));
    a = find(T.Phi == fixed); [~, o] = sort(T.Theta(a)); a = a(o);
    b = find(T.Phi == v(jo) & T.Theta ~= 180); [~, o] = sort(T.Theta(b), 'descend'); b = b(o);
    rows = [a; b]; ang = [T.Theta(a); 360 - T.Theta(b)]; sym = 'φ';
end
snapped = d > 1e-9;
end

function [bw, lo, hi] = calcHPBW(ang, g, pk, pkAng)
%calcHPBW −3 dB beamwidth of a circular cut: linear interpolation of the first crossing on each side of the peak.
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(g); ang = ang(ok); g = g(ok); if numel(g) < 3, return, end
if nargin < 4 || isempty(pk) || isempty(pkAng), [pk, j] = max(g); pkAng = ang(j); end
[rel, o] = sort(mod(ang - pkAng + 180, 360) - 180); gr = g(o); h = pk - 3;
L = find(rel < 0 & gr <= h, 1, 'last'); Rr = find(rel > 0 & gr <= h, 1, 'first');
if isempty(L) || isempty(Rr) || L == numel(gr) || Rr == 1 || gr(L+1) == gr(L) || gr(Rr-1) == gr(Rr), return, end
x = @(i, j) rel(i) + (rel(j) - rel(i))*(h - gr(i))/(gr(j) - gr(i));   % crossing between sample i (outside) and j (inside)
lo = pkAng + x(L, L+1); hi = pkAng + x(Rr, Rr-1); bw = hi - lo;
end

function dOmega = solidWeights(th, ph)
%solidWeights Exact solid angle of each uniform θ×φ cell (sr); the closing φ=360 copies get zero weight so Σ = 4π.
dt = gridStep(th); dp = gridStep(ph); if isnan(dt), dt = 180; end, if isnan(dp), dp = 360; end
dOmega = (cosd(max(th - dt/2, 0)) - cosd(min(th + dt/2, 180))) * deg2rad(dp); dOmega(ph >= 360) = 0;
end

function c = coverageCCDF(g, mask, thr, omega)
%coverageCCDF Coverage(T) [%] = 100 · Σ Ω_i·[G_i > T] / Σ Ω_i over the region MASK, for every threshold at once.
ok = mask(:) & isfinite(g(:)) & isfinite(omega(:)) & omega(:) >= 0; g = g(ok); w = omega(ok); c = zeros(size(thr));
if isempty(g) || sum(w) <= 0, return, end
c = reshape(100*(w.' * (g > thr(:).'))/sum(w), size(thr));
end

function [x, y] = covQueryPoint(d, mode, q)
%covQueryPoint Coverage at a threshold ('cov') or threshold at a coverage ('thr') on one CCDF job record.
[x, y] = deal(NaN);
if strcmp(mode, 'cov'), x = q; if numel(d.thr) > 1, y = interp1(d.thr, d.cov, q, 'linear', NaN); end
else, y = q; if numel(d.invCov) > 1, x = interp1(d.invCov, d.invThr, q, 'linear', NaN); end, end
end

function b = displayRange(v, pct, excess)
%displayRange 50-dB window whose top is the effective peak rounded up to 5 dB (shared by colour scales and coverage presets).
pk = resolvePeak(v, pct, excess); if ~isfinite(pk.value), b = [-50 0]; return, end
top = min(max(5*ceil(pk.value/5), -200), 100); b = [top - 50, top];
end

function r = clampRange(v, b)
%clampRange Sorted range clamped to B and at least 1 dB wide.
v = sort(double(v(:).')); if numel(v) < 2 || any(~isfinite(v(1:2))), r = b; return, end
r = [max(b(1), v(1)), min(b(2), v(2))]; if diff(r) < 1, r(2) = min(b(2), r(1) + 1); r(1) = max(b(1), r(2) - 1); end
end

function [g, col] = chooseGain(T, col)
%chooseGain Values of COL, else E_Total_dB, else the first data column.
vn = string(T.Properties.VariableNames); c = [string(col), "E_Total_dB", vn(3)]; col = char(c(find(ismember(c, vn), 1))); g = double(T.(col));
end

function [cols, labels] = componentList(T)
%componentList Plottable component columns of a processed table with their display labels.
cols = string(T.Properties.VariableNames(3:end)); ud = T.Properties.UserData;
if isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly, labels = cols; return, end
known = ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","AR_dB","Gain_PolCorrected_dB"];
names = ["Total Gain","Etheta Gain","Ephi Gain","RHCP Gain","LHCP Gain","Axial Ratio","Polarized Gain"];
present = ismember(known, cols); cols = known(present); labels = names(present);
end

function c = preferredComponent(prev, cols)
%preferredComponent Keep the previous component when available, else Total Gain, else the first column.
c = string(prev); if ~any(cols == c), c = cols(find(cols == "E_Total_dB", 1)); end, if isempty(c), c = cols(1); end
end

function s = gridStep(v)
%gridStep Smallest positive spacing between distinct finite values (NaN when fewer than two).
d = diff(unique(v(isfinite(v)))); d = d(d > 1e-9); s = min(d); if isempty(s), s = NaN; end
end

function tf = isAR(c)
%isAR Axial-ratio semantics independent of column spelling (AR, AR_dB, "AR dB", Axial Ratio, Axial_Ratio).
key = regexprep(lower(strtrim(string(c))), '[^a-z0-9]', ''); tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
end

function s = fmtNum(v, n)
%fmtNum Compact number text: up to 2 decimals with trailing zeros removed, or exactly N decimals; 'n/a' when not finite.
if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return, end
if nargin > 1, s = sprintf('%.*f', n, v); else, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); end
end

function t = ticks(lim, step)
%ticks Colorbar/axis ticks at multiples of STEP inside LIM, including both ends (empty → automatic ticks).
t = []; if ~isfinite(step) || step <= 0 || diff(lim) <= 0, return, end
t = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)]); if numel(t) > 60, t = []; end
end

function drawXYZ(ax)
%drawXYZ Principal axes: X red, Y green, Z blue, with their spherical coordinates.
col = [0.85 0.1 0.1; 0.1 0.6 0.1; 0.1 0.2 0.9]; lab = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
for k = 1:3
    d = 1.35*((1:3) == k); quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', col(k, :), 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
    text(ax, 1.12*d(1), 1.12*d(2), 1.12*d(3), lab{k}, 'Color', col(k, :), 'FontWeight', 'bold');
end
end

function tf = isNodeKind(n, kind)
%isNodeKind True when N is a tree node whose NodeData.kind equals KIND.
tf = isa(n, 'matlab.ui.container.TreeNode') && isstruct(n.NodeData) && isfield(n.NodeData, 'kind') && strcmp(n.NodeData.kind, kind);
end

function nodes = treeNodes(roots, kind)
%treeNodes Depth-first list of ROOTS and all their descendants, optionally filtered by NodeData.kind.
nodes = matlab.ui.container.TreeNode.empty(0, 1);
for r = roots(:).', nodes = [nodes; r; treeNodes(r.Children)]; end %#ok<AGROW>
if nargin > 1, nodes = nodes(arrayfun(@(n) isNodeKind(n, kind), nodes)); end
end