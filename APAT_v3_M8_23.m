classdef APAT_v3_M8_23 < matlab.apps.AppBase %1474-lines %MX %ISSUES: %1. POB DataTips renders/refreshes each time a plot tab is highlighted/selected  %2. When Switching Phi Span, while POB DataTip is enabled, it adjust the POB Datatip location/coordinate to reflect the Phi span, but it also keep the previous POB's dot/marker (they also remain shows/plotted when loading a new file/pattern)  %3. When loading new pattern while the older/current POB DataTip is active/enabled, it shows the new one but also keeps the old POB DataTips on the Cut Plots  %4. DatTip Custom Context menu triggers warning (MATLAB Workspace showing "Warning: You cannot set 'ContextMenu' property of DataTip")  %5. On Coverage Results Plots, the Interactive DataTip cursor doesn't shows Customized DataTips (However, Query requests DataTips sows Customized DataTips!)  %6. On Coverage, Clicking Reset button, it doesn't properly clear the DataTips & their respective projection lines (However, clicking on 'Clear the DataTips' button, properly clears the DataTips and their respective projection dotted lines)!
%APAT_v3_M8  Antenna Pattern Analyzer Tool — v3 Milestone 8 (single-file App Designer class).
%
%   PIPELINE (one direction, one owner per stage, every stage is a plain table)
%     file ─read─▶ src{rawTbl,blocks,freqs,meta} ─normalizePattern─▶ std ─[resample]─calcPattern─▶ base ─applyView─▶ view
%     view ─▶ {dΩ, boresight, metrics, component peak} ─▶ tables · metadata · cut plots · five full-pattern plots · coverage
%
%   CONVENTIONS
%     * All physics (solid angle, boresight, HPBW, directivity, coverage) is evaluated on PHYSICAL polar θ∈[0,180]
%       and φ.  The θ/φ span switches only change how the VIEW table is materialised, labelled and exported.
%     * Every widget lives in app.ui under a short key.  Every annotation is a tagged graphics object
%       ('APAT_POB', 'APAT_HPBW', 'APAT_Overlay', 'CovQ_<mode>_<id>'), so visibility and cleanup are one findall away.
%     * Local functions after the classdef are pure (no UI): readers, math, formatting.

    properties (Access = public)
        UIFigure matlab.ui.Figure
        ui struct = struct()            % every widget handle, keyed by short name (see buildUI)
    end

    properties (Access = private)
        file struct = struct('path','', 'folder','', 'base','', 'name','')
        src struct = struct()           % reader output: rawTbl, blocks, freqs, meta
        std table                       % canonical physical table (θ 0..180, φ 0..360 with closing seam)
        base table                      % processed table on the selected angular step (physical angles)
        view table                      % display table: φ span / θ span applied (what tables, plots and exports show)
        elev logical = false            % view θ is elevation (−90..90) instead of polar (0..180)
        signed logical = false          % view φ is signed (−180..180) instead of 0..360
        oneDeg logical = false          % user asked for the 1° resampled representation
        rev double = 0                  % view revision (drives coverage threshold presets)
        rawShown logical = false
        grid struct = struct()          % cached θ/φ axes, geometry and per-component grids of the view
        dOmega double = []              % solid-angle weight of every view row
        bsIdx double = 1                % detected boresight (index into Axes)
        peak struct = struct()          % resolvePeak() of the displayed component on the view
        metrics struct = struct()       % calcMetrics() of the total gain on the view
        pol struct = struct('label','n/a', 'Linear',["E_TH","E_PH"], 'Circular',["E_RCP","E_LCP"])
        gainLim double = [-40 10]       % authoritative non-AR colour range (survives component changes)
        fullLim double = [-40 10]       % colour range currently applied to the full-pattern plots
        cutLim double = [-40 10]
        defaults cell = {}              % start-up values of the parameter controls (Reset Params)
        covId double = 0                % running coverage job id
        covKey string = ""              % pattern|component|revision key of the last threshold preset
        covInit logical = [false false] % [threshold preset, plot X range] initialised → later presets only widen
        closing logical = false
        statusTimer
        dlg = []                        % active cancelable progress dialog
    end

    properties (Constant, Access = private)
        Axes = struct('labels', {{'+Z','-Z','+X','-X','+Y','-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270], ...
            'vec', [0 0 1; 0 0 -1; 1 0 0; -1 0 0; 0 1 0; 0 -1 0])   % principal axes: [polar θ, φ] and unit vectors
        Hidden = {'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'}
        Pctl = 99.99                    % peak policy: percentile ...
        Excess = 6                      % ... and maximum excess (dB) a raw maximum may have above it
        Release = 'APAT v3 M8'
    end

    %% ── Lifecycle ────────────────────────────────────────────────────────────────────────────────────────────
    methods (Access = public)
        function app = APAT_v3_M8_23
            app.buildUI(); registerApp(app, app.UIFigure); runStartupFcn(app, @startup);
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.closing, return; end
            app.closing = true;
            t = app.statusTimer; if ~isempty(t) && isvalid(t), stop(t); delete(t); end
            if ~isempty(app.dlg) && isvalid(app.dlg), delete(app.dlg); end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end
    end

    methods (Access = private)
        function startup(app)
            u = app.ui;
            app.statusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, 'TimerFcn', @(~,~) app.restoreStatus());
            hold(u.CovAxes, 'on'); grid(u.CovAxes, 'on'); ylim(u.CovAxes, [0 100]); set(u.CovAxes, 'Box', 'on', 'Layer', 'top');
            app.defaults = cellfun(@(h) h.Value, app.paramCtl(), 'UniformOutput', false);
            app.setStatus(u.Status, 'Ready -- load an antenna pattern file to begin 🚀');
            app.setStatus(u.CovStatus, 'Ready -- load an antenna pattern file to begin 🚀');
            app.covUI();
        end

        function setStatus(app, label, msg, transient)
            % Sticky messages are remembered in label.UserData; transient ones revert to it after 3 s (one shared timer).
            if app.closing || ~isgraphics(label), return; end
            t = app.statusTimer; stop(t); label.Text = char(msg);
            if nargin > 3 && transient, t.UserData = label; start(t); else, label.UserData = char(msg); end
        end

        function restoreStatus(app)
            if app.closing, return; end
            L = app.statusTimer.UserData; if isgraphics(L), L.Text = L.UserData; end
        end

        function showError(app, ME, ttl)
            if app.closing, return; end
            loc = ''; if ~isempty(ME.stack), loc = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.UIFigure, [ME.message loc], ttl, 'Icon', 'error');
        end

        function cancelled(app)
            % Honour the progress dialog's Abort button at pipeline checkpoints.
            if ~isempty(app.dlg) && isvalid(app.dlg) && app.dlg.CancelRequested, error('APAT:Cancelled', 'Operation cancelled by user.'); end
        end

        function c = paramCtl(app), u = app.ui; c = {u.Loss, u.RxPol, u.Rw, u.Pt, u.PtUnit, u.R, u.RUnit}; end

        function p = params(app)
            % Processing parameters from the Inputs panel (field scale, Tx power in dBW, distance in metres).
            u = app.ui; p = struct('GainLoss_dB', u.Loss.Value, 'RxMode', string(u.RxPol.Value), 'RxAR_dB', u.Rw.Value);
            p.FieldScale = 10^(p.GainLoss_dB/20);
            switch u.PtUnit.Value
                case 'dBm',   p.Pt_dBW = u.Pt.Value - 30;
                case 'Watts', p.Pt_dBW = 10*log10(max(u.Pt.Value, eps));
                otherwise,    p.Pt_dBW = u.Pt.Value;
            end
            p.R_m = max(u.R.Value, 1e-12)*(1 + 999*strcmp(u.RUnit.Value, 'km'));
        end

        function fp = browse(~, prompt)
            [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage files'; '*.*', 'All files'}, prompt);
            fp = ''; if ~isequal(f, 0), fp = fullfile(p, f); end
        end

        function fp = savePath(app, filters, prompt, name)
            [f, p] = uiputfile(filters, prompt, fullfile(app.file.folder, name)); fp = ''; if ~isequal(f, 0), fp = fullfile(p, f); end
        end

        function out = readSource(~, fp, lbl, dd)
            % Generic text files expose the format selector (and always start as "gain"); other formats are self-describing.
            generic = isGenericText(fp); if generic, dd.Value = 'gain'; end
            out = readPattern(fp, dd.Value); set([lbl dd], 'Visible', generic && ~out.meta.isCoverage);
        end

        %% ── Main pipeline: load → std → base → view → render ─────────────────────────────────────────────────
        function onLoad(app, ~, ~)
            u = app.ui; fp = strtrim(u.Path.Value);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.file.path)
                fp = app.browse('Select an antenna pattern file'); if isempty(fp), return; end
                u.Path.Value = fp;
            end
            app.dlg = uiprogressdlg(app.UIFigure, 'Title', 'Loading Data', 'Message', 'Reading file...', 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            cleaner = onCleanup(@() delete(app.dlg)); drawnow
            try
                out = app.readSource(fp, u.FormatLbl, u.Format); app.cancelled();
                if out.meta.isCoverage                    % route coverage-result files without touching Main state
                    u.Path.Value = app.file.path; u.Tabs.SelectedTab = u.TabCov; u.CovPath.Value = fp;
                    app.covLoadResults(fp, out.rawTbl); return
                end
                [folder, base, ext] = fileparts(fp); app.file = struct('path', fp, 'folder', folder, 'base', base, 'name', [base ext]);
                app.src = out; app.oneDeg = false; u.Basis.UserData = true;      % new source: native step, auto cut basis
                if out.meta.isDep
                    items = compose('Pattern %d: %.4g GHz', (1:numel(out.blocks))', out.freqs(:)/1e9);
                    items(isnan(out.freqs)) = compose('Pattern %d', find(isnan(out.freqs(:))));
                    u.FFD.Items = items; u.FFD.Value = items{1};
                end
                set([u.FFD u.FFDLbl], 'Visible', out.meta.isDep);
                app.selectBlock(1); app.rebuild();
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.setStatus(u.Status, 'Loading cancelled by user.', true);
                else, app.showError(ME, 'Loading Error'); end
            end
        end

        function selectBlock(app, k)
            % Choose one source block (FFD frequency) and standardise it onto the canonical sphere.
            blk = app.src.blocks{k}; if app.src.meta.isDep, app.src.rawTbl = blk; end
            app.rawShown = false; app.std = normalizePattern(blk); app.std.Properties.UserData = app.src.meta;
        end

        function rebuild(app, resetPlane)
            % std ─▶ base (angular step + parameters) ─▶ view ─▶ everything derived.  RESETPLANE re-derives the E/H cut.
            u = app.ui; if nargin < 2, resetPlane = true; end
            [ts, ps] = deal(gridStep(app.std.Theta), gridStep(app.std.Phi)); if ~isfinite(ts), ts = 1; end, if ~isfinite(ps), ps = ts; end
            coarse = abs(ts - 1) > 1e-9 || abs(ps - 1) > 1e-9; app.oneDeg = app.oneDeg && coarse;
            native = sprintf('STEP: %g°', max(ts, ps)); u.Step.Items = {native, 'STEP: 1°'};
            u.Step.Value = native; if app.oneDeg, u.Step.Value = 'STEP: 1°'; end
            set(u.Step, 'Visible', coarse, 'Enable', coarse);
            S = app.std;
            if app.oneDeg
                if ts < 1 && ps < 1, S = S(abs(S.Theta - round(S.Theta)) < 1e-9 & abs(S.Phi - round(S.Phi)) < 1e-9, :);   % exact decimation
                else, S = resampleCanonical(S, 1); end
            end
            [app.base, app.pol] = calcPattern(S, app.params()); app.cancelled();
            ef = ~app.src.meta.isGainOnly;
            if ef && isequal(u.Basis.UserData, true), u.Basis.Value = 'Circular'; if startsWith(app.pol.label, 'Linear'), u.Basis.Value = 'Linear'; end, end
            app.applyView(); app.setCompItems(); app.update(true, resetPlane);
            set([u.PanelFull u.PanelCut u.PanelCtrl u.DataTabs u.Filter u.ExportOut u.CovBtn], 'Visible', 'on');
            set([u.ExportUAN u.Ecut u.Et u.Er u.El], 'Visible', ef); set([u.Er u.El u.Basis], 'Enable', ef);
            m = app.metrics; msg = sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>θ=%s°, φ=%s°</b>)', app.file.name, fmt(m.PeakGain_dB, 2), fmt(m.PeakTheta_deg), fmt(m.PeakPhi_deg));
            if ef, msg = sprintf('%s | Polarization <b>%s</b>', msg, app.pol.label); end
            app.setStatus(u.Status, msg);
        end

        function applyView(app)
            % base (physical) ─▶ view (display convention) and all view-level physics on PHYSICAL angles.
            u = app.ui; T = app.base;
            app.signed = strcmp(u.PhiSpan.Value, '-180° to 180°'); app.elev = strcmp(u.ThSpan.Value, '-90° to 90°');
            if app.signed
                T(abs(T.Phi - 360) < 1e-9, :) = []; T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
                seam = T(abs(T.Phi - 180) < 1e-9, :); seam.Phi(:) = -180; T = [seam; T];
            end
            if app.elev, T.Theta = 90 - T.Theta; end
            if app.signed || app.elev, T = sortrows(T, {'Phi', 'Theta'}); end
            app.view = T; app.grid = struct(); app.rev = app.rev + 1;
            [th, ph] = app.physAngles(); g = totalGain(T); app.dOmega = solidWeights(th, ph);
            [app.bsIdx, pk] = calcOrientation(th, ph, g, app.dOmega, app.Axes, app.Pctl, app.Excess);
            app.metrics = calcMetrics(T, th, ph, g, pk, app.dOmega, app.Axes, app.bsIdx);
        end

        function [th, ph] = physAngles(app)
            % Physical polar θ and the view's φ (seam duplicates intact for the solid-angle weights).
            th = app.view.Theta; if app.elev, th = 90 - th; end, ph = app.view.Phi;
        end

        function update(app, ranges, plane)
            % Component peak → (optional) colour ranges → tables/metadata → cut plane → all plots.
            u = app.ui; comp = u.Comp.Value; app.peak = resolvePeak(app.view.(comp), app.Pctl, app.Excess);
            if nargin > 1 && ranges
                if isAR(comp), app.setRange([-30 30], 0, "full", false);
                else, app.gainLim = peakRange(totalGain(app.view), app.Pctl, app.Excess); app.setRange(app.gainLim, 0, "all", false); end
            end
            app.updateTables(); app.updateMetadata();
            if nargin > 2 && plane, app.setPlane(); else, app.cutValues(); end
            app.drawCut(); app.drawFull();
        end

        function setCompItems(app)
            u = app.ui; [cols, labels] = compList(app.view); prev = string(u.Comp.Value);
            u.Comp.Items = cellstr(labels); u.Comp.ItemsData = cellstr(cols); u.Comp.Value = char(pickComp(prev, cols));
        end

        function s = compLabel(app)
            u = app.ui; s = string(u.Comp.Items{find(strcmp(u.Comp.ItemsData, u.Comp.Value), 1)});
        end

        %% ── Simple callbacks ─────────────────────────────────────────────────────────────────────────────────
        function onProcess(app, ~, ~)
            u = app.ui;
            if isempty(app.std), uialert(app.UIFigure, 'No file! Load a pattern first.', 'Warning', 'Icon', 'warning'); return; end
            d = uiprogressdlg(app.UIFigure, 'Title', 'Processing', 'Message', 'Re-processing pattern...', 'Indeterminate', 'on'); cleaner = onCleanup(@() delete(d));
            try
                if isGenericText(app.file.path)           % reinterpret the cached generic table with the selected format
                    out = readPattern(app.file.path, u.Format.Value, app.src.rawTbl);
                    assert(~out.meta.isCoverage, 'The selected generic format identifies a coverage-results file.');
                    app.src = out; app.selectBlock(1);
                end
                app.rebuild(); app.setStatus(u.Status, ['Re-processed <b>' app.file.name '</b> with the current parameters ✅'], true);
            catch ME, app.showError(ME, 'Processing Error'); end
        end

        function onFormat(app, ~, ~)
            if strcmp(strtrim(app.ui.Path.Value), app.file.path) && isGenericText(app.file.path), app.ui.Basis.UserData = true; app.onProcess(); end
        end

        function onFFD(app, ~, ~)
            u = app.ui; k = find(strcmp(u.FFD.Items, u.FFD.Value), 1); u.Basis.UserData = true;
            app.selectBlock(k); app.rebuild(); app.setStatus(u.Status, sprintf('Switched to FFD block %d (%s).', k, u.FFD.Value), true);
        end

        function resetParams(app, ~, ~)
            c = app.paramCtl(); for k = 1:numel(c), c{k}.Value = app.defaults{k}; end
            if ~isempty(app.std), app.rebuild(false); end
        end

        function onStep(app, ~, ~), app.oneDeg = strcmp(app.ui.Step.Value, 'STEP: 1°'); app.rebuild(false); end
        function onSpan(app, ~, ~), if ~isempty(app.base), app.applyView(); app.update(); end, end
        function onComponent(app, ~, ~), app.update(true); end
        function onEH(app, ~, ~), app.setPlane(); app.drawCut(); end
        function onView3D(app, ~, ~)
            if isempty(app.view), return; end, u = app.ui; app.setView(u.Full(3).ax, [135 25]); app.setView(u.Full(4).ax, [135 25]); app.setView(u.Full(5).ax, [-35 35]);
        end

        function onCut(app, ~, ev)
            u = app.ui;
            if nargin > 2 && isequal(ev.Source, u.Basis), u.Basis.UserData = false; app.updateMetadata(); end
            u.HPBWTips.Visible = u.HPBW.Value; if ~u.HPBW.Value, u.HPBWTips.Value = false; end
            app.cutValues(); app.drawCut();
        end

        %% ── Tables, metadata, parameter visibility ───────────────────────────────────────────────────────────
        function updateTables(app)
            u = app.ui; cols = app.view.Properties.VariableNames(3:end);
            if ~app.rawShown, u.TableIn.Data = app.src.rawTbl; app.rawShown = true; end
            dd = u.Filter; changed = ~isequal(regexprep(dd.Items(2:end), '^✓ ?', ''), cols);
            if changed, dd.Items = [{'--- column filter ---'}, cols]; dd.ItemsData = 0:numel(cols); dd.UserData = ~ismember(cols, app.Hidden); dd.Value = 0; end
            app.filterOutput(changed);
        end

        function filterOutput(app, restyle)
            % Toggle the clicked column, restyle the filter dropdown, refresh the Results table and parameter visibility.
            u = app.ui; dd = u.Filter;
            if dd.Value > 0, dd.UserData(dd.Value) = ~dd.UserData(dd.Value); dd.Value = 0; restyle = true; end
            if restyle
                dd.Items = regexprep(dd.Items, '^✓ ?', ''); removeStyle(dd); on = find(dd.UserData) + 1; dd.Items(on) = append('✓ ', dd.Items(on));
                addStyle(dd, uistyle('FontWeight', 'bold', 'BackgroundColor', [0.8 1 0.8]), 'Item', on);
                addStyle(dd, uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9]), 'Item', find([true, ~dd.UserData]));
            end
            u.TableOut.Data = app.view(:, [true true dd.UserData]);
            sel = string(app.view.Properties.VariableNames(find(dd.UserData) + 2)); show = @(names) any(ismember(sel, names));
            set([u.RxPolLbl u.RxPol u.RwLbl u.Rw], 'Visible', show(["PLF_dB", "Gain_PolCorrected_dB"]));
            set([u.PtLbl u.Pt u.PtUnit], 'Visible', show(["EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
            set([u.RLbl u.R u.RUnit], 'Visible', show(["PFD_Wm2", "E_RMS_Vm"]));
            set([u.LossLbl u.Loss], 'Visible', app.src.meta.isGainOnly || show(["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "Gain_PolCorrected_dB", "EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
        end

        function updateMetadata(app)
            T = app.view; m = app.metrics; meta = app.src.meta; [th, ph] = deal(unique(T.Theta), unique(T.Phi));
            rows = {'Source format', meta.source; 'File', app.file.name; 'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(T), numel(th), numel(ph));
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmt(min(th)), fmt(max(th)), fmt(gridStep(th)));
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmt(min(ph)), fmt(max(ph)), fmt(gridStep(ph)))};
            fq = app.src.freqs(isfinite(app.src.freqs)); if ~isempty(fq), rows(end+1, :) = {'Frequencies', strjoin(compose('%.4g GHz', fq(:)/1e9), ', ')}; end
            if ~meta.isGainOnly, rows = [rows; {'Polarization', app.pol.label; 'Cut Co-pol / Cross-pol', char(strjoin(app.pol.(app.ui.Basis.Value), ' / '))}]; end
            rows = [rows; {'Peak gain (POB)', [fmt(m.PeakGain_dB) ' dB']; 'POB direction [θ, φ]', sprintf('[%s°, %s°]', fmt(m.PeakTheta_deg), fmt(m.PeakPhi_deg));
                'Boresight axis', app.Axes.labels{app.bsIdx}; 'Peak policy', sprintf('P%.4g, max excess %.4g dB', app.Pctl, app.Excess); 'Peak adjusted', char(string(m.PeakAdjusted));
                'HPBW E-plane', [fmt(m.HPBW_EPlane_deg) '°']; 'HPBW H-plane', [fmt(m.HPBW_HPlane_deg) '°'];
                'Front-to-back', [fmt(m.FrontBack_dB) ' dB']; 'Peak directivity', [fmt(m.PeakDirectivity_dB) ' dB']}];
            if isfinite(m.Efficiency_pct), rows(end+1, :) = {'Radiation efficiency', [fmt(m.Efficiency_pct) '%']}; end
            if isfinite(m.AxialRatioAtPeak_dB), rows(end+1, :) = {'AR at peak', [fmt(m.AxialRatioAtPeak_dB) ' dB']}; end
            app.ui.TableMeta.Data = rows;
        end

        %% ── Colour ranges ────────────────────────────────────────────────────────────────────────────────────
        function setRange(app, v, which, scope, apply)
            % Synchronise range controls.  WHICH: 0 = exact pair (limits follow), −1 = slider pair, 1/2 = min/max spinner
            % (limits only widen).  "all" seeds Cmin/Cmax and both scopes; "full"/"cut" update sliders, spinners and axes.
            u = app.ui; if nargin < 5, apply = true; end
            if scope == "all"
                r = clampRange(v, [-250 100]); u.Cmin.Value = r(1); u.Cmax.Value = r(2);
                app.setRange(r, 0, "full", apply); app.setRange(r, 0, "cut", apply); return
            end
            if scope == "full", S = [u.Full.rng]; lo = [u.Full.lo]; hi = [u.Full.hi]; r = app.fullLim;
            else, S = u.CutRng; lo = u.CutLo; hi = u.CutHi; r = app.cutLim; end
            if which <= 0, r = v; else, r(which) = v; end, r = clampRange(r, [-250 100]);
            L = r; if which ~= 0, L = [min(S(1).Limits(1), r(1)), max(S(1).Limits(2), r(2))]; end
            set(S, 'Limits', [-250 100], 'Value', r); set(S, 'Limits', L);
            set(lo, 'Limits', [-250 r(2)-1], 'Value', r(1)); set(hi, 'Limits', [r(1)+1 100], 'Value', r(2));
            if scope == "full", app.fullLim = r; if ~isAR(u.Comp.Value), app.gainLim = r; end, else, app.cutLim = r; end
            if apply && ~isempty(app.view), app.applyLim(scope); end
        end

        function applyLim(app, scope)
            u = app.ui;
            if scope == "full"
                for k = 1:5
                    ax = u.Full(k).ax; clim(ax, app.fullLim); app.applyTicks(colorbar(ax), 'Ticks', app.fullLim);
                    if k == 5, zlim(ax, app.fullLim); app.applyTicks(ax, 'ZTick', app.fullLim); end
                end
            else, set(u.CutPolar, 'RLim', app.cutLim); set(u.CutRect, 'YLim', app.cutLim); end
            drawnow limitrate
        end

        function applyTicks(app, h, prop, lim)
            t = axisTicks(lim, app.ui.Cstep.Value); if ~isempty(t), h.(prop) = t; end
        end

        function [lim, cmap] = theme(app)
            % Signed axial ratio: fixed ±30 dB blue-white-red; everything else: the shared gain range with jet.
            if isAR(app.ui.Comp.Value), lim = [-30 30]; cmap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256));
            else, lim = app.fullLim; cmap = jet(256); end
        end

        %% ── Full-pattern plots (contour, circular, 3-D spherical, 3-D polar, 3-D rectangular) ────────────────
        function [th, ph, G] = gridOf(app, col)
            % Cached rectangular θ×φ grid (NaN where unsampled) of one view column, plus geometry shared by all renderers.
            g = app.grid;
            if ~isfield(g, 'th')
                g.th = unique(app.view.Theta); g.ph = unique(app.view.Phi);
                [~, i] = ismember(app.view.Theta, g.th); [~, j] = ismember(app.view.Phi, g.ph);
                g.idx = sub2ind([numel(g.th) numel(g.ph)], i, j); g.data = struct(); [g.PH, g.TH] = meshgrid(g.ph, g.th);
                g.thp = g.TH; if app.elev, g.thp = 90 - g.TH; end
                g.X = sind(g.thp).*cosd(g.PH); g.Y = sind(g.thp).*sind(g.PH); g.Z = cosd(g.thp);
            end
            key = matlab.lang.makeValidName(col);
            if ~isfield(g.data, key), G = nan(size(g.TH)); G(g.idx) = app.view.(col); g.data.(key) = G; end
            th = g.th; ph = g.ph; G = g.data.(key); app.grid = g;
        end

        function drawFull(app)
            if isempty(app.view), return; end
            u = app.ui; comp = u.Comp.Value; [th, ph, G] = app.gridOf(comp); g = app.grid; [lim, cmap] = app.theme(); lbl = app.compLabel();
            thLbl = "Theta"; if app.elev, thLbl = "Elevation"; end
            i = app.peak.index; [~, r] = min(abs(th - app.view.Theta(i))); [~, c] = min(abs(ph - app.view.Phi(i)));
            tip = [dataTipTextRow(thLbl, g.TH(r, c), '%.3g°'); dataTipTextRow("Phi", g.PH(r, c), '%.3g°'); dataTipTextRow(lbl, G(r, c), '%.3g dB')];
            for k = 1:5
                ax = u.Full(k).ax; cla(ax); hold(ax, 'on');
                switch k
                    case 1                                   % rectangular contour
                        s = pcolor(ax, ph, th, G); set(s, 'FaceColor', 'interp', 'LineStyle', 'none');
                        app.angularAxes(ax, 30, 15); daspect(ax, [1 1 1]); title(ax, lbl, 'Interpreter', 'none'); pob = {g.PH(r, c), g.TH(r, c), 0};
                    case 2                                   % circular contour: radius = θ, angle = φ
                        s = surface(ax, deg2rad(g.PH), g.thp, zeros(size(G)), G, 'EdgeColor', 'none');
                        rl = 0:30:180; if app.elev, rl = 90 - rl; end, app.polarTicks(ax);
                        set(ax, 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', rl)); title(ax, sprintf('%s  |  r=θ, angle=φ', lbl), 'Interpreter', 'none', 'FontSize', 9);
                        pob = {deg2rad(g.PH(r, c)), g.thp(r, c), 0};
                    case 3                                   % 3-D spherical (colour on the unit sphere)
                        s = surf(ax, g.X, g.Y, g.Z, G, 'EdgeColor', 'none'); app.axes3D(ax, [135 25]); pob = {g.X(r, c), g.Y(r, c), g.Z(r, c)};
                    case 4                                   % 3-D polar (radius ∝ level above the colour floor)
                        r0 = max(G - lim(1), 0)/max(diff(lim), eps); app.grid.rmax = max(max(r0, [], 'all', 'omitnan'), eps); R = r0/app.grid.rmax;
                        s = surf(ax, R.*g.X, R.*g.Y, R.*g.Z, G, 'EdgeColor', 'none'); app.axes3D(ax, [135 25]); pob = {R(r, c)*g.X(r, c), R(r, c)*g.Y(r, c), R(r, c)*g.Z(r, c)};
                    otherwise                                % 3-D rectangular surface
                        s = surf(ax, g.PH, g.TH, G, 'EdgeColor', 'none'); zlim(ax, lim); app.applyTicks(ax, 'ZTick', lim); app.angularAxes(ax, 60, 30); grid(ax, 'on');
                        xlabel(ax, 'Phi (degree)'); ylabel(ax, thLbl + " (degree)"); zlabel(ax, lbl + " (dB)", 'Interpreter', 'none'); app.setView(ax, [-35 35]);
                        pob = {g.PH(r, c), g.TH(r, c), G(r, c)};
                end
                if k > 2, title(ax, sprintf('%s  |  θ: %s  |  φ: %s', lbl, u.ThSpan.Value, u.PhiSpan.Value), 'Interpreter', 'none'); end
                s.Tag = 'APAT_Surface'; clim(ax, lim); colormap(ax, cmap); app.applyTicks(colorbar(ax), 'Ticks', lim);
                setTips(s, [dataTipTextRow(thLbl, g.TH, '%.3g°'); dataTipTextRow("Phi", g.PH, '%.3g°'); dataTipTextRow(lbl, G, '%.3g dB')]);
                if isfinite(app.peak.value), app.pin(ax, pob{:}, tip, 'APAT_POB', 'k'); end
                if k ~= 2, set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', ax.ContextMenu); end
                hold(ax, 'off');
            end
            app.overlayCut(); app.syncTips();
        end

        function axes3D(app, ax, defView)
            set(ax, 'Projection', 'orthographic', 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1]);
            axis(ax, 'off'); app.setView(ax, defView);
            col = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; txt = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'}; d = 1.35*eye(3);
            for k = 1:3
                quiver3(ax, 0, 0, 0, d(k, 1), d(k, 2), d(k, 3), 0, 'Color', col{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12*d(k, 1), 1.12*d(k, 2), 1.12*d(k, 3), txt{k}, 'Color', col{k}, 'FontWeight', 'bold');
            end
        end

        function setView(app, ax, defView)
            views = struct('top', [0 90], 'bottom', [0 -90], 'right', [90 0], 'left', [-90 0], 'front', [0 0], 'back', [180 0]);
            v = app.ui.View3D.Value; up = [0 0 1]; if isfield(views, v), defView = views.(v); if abs(defView(2)) == 90, up = [0 1 0]; end, end
            view(ax, defView); camup(ax, up);
        end

        function angularAxes(app, ax, phStep, thStep)
            [pl, tl] = app.limits(); dir = 'reverse'; if app.elev, dir = 'normal'; end
            set(ax, 'XLim', pl, 'YLim', tl, 'YDir', dir, 'Box', 'on', 'Layer', 'top', 'XTick', pl(1):phStep:pl(2), 'YTick', tl(1):thStep:tl(2));
        end

        function [pl, tl] = limits(app)
            pl = [0 360]; if app.signed, pl = [-180 180]; end, tl = [0 180]; if app.elev, tl = [-90 90]; end
        end

        function polarTicks(app, pax)
            a = 0:30:330; if app.signed, a(a > 180) = a(a > 180) - 360; end
            set(pax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', a));
        end

        %% ── Annotations: one tagged marker + pinned DataTip; visibility follows checkboxes and selected tabs ──
        function pin(~, ax, x, y, z, rows, tag, color)
            if ~all(isfinite([x y z])), return; end
            held = ishold(ax); hold(ax, 'on');
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), h = polarplot(ax, x, y, 'o'); else, h = plot3(ax, x, y, z, 'o', 'Clipping', 'off'); end
            set(h, 'Color', color, 'MarkerFaceColor', color, 'MarkerSize', 5, 'HandleVisibility', 'off', 'Tag', tag);
            try h.DataTipTemplate.DataTipRows = rows; datatip(h, 'DataIndex', 1, 'FontSize', 9, 'Tag', tag); catch, end
            if ~held, hold(ax, 'off'); end
        end

        function syncTips(app, ~, ~)
            % uifigure DataTips ignore tab clipping, so an annotation is visible only when its checkbox is on AND every
            % enclosing tab is the selected one.
            u = app.ui; spec = {'APAT_POB', u.POB.Value; 'APAT_HPBW', u.HPBWTips.Value};
            for k = 1:2
                for h = findall(app.UIFigure, 'Tag', spec{k, 1})'
                    on = spec{k, 2}; p = h;
                    while on && isprop(p, 'Parent') && ~isempty(p.Parent)          % walk up: every enclosing tab must be selected
                        p = p.Parent; if isa(p, 'matlab.ui.container.Tab'), on = isequal(p.Parent.SelectedTab, p); end
                    end
                    h.Visible = on;
                end
            end
        end

        %% ── Pattern cuts ─────────────────────────────────────────────────────────────────────────────────────
        function setPlane(app)
            % E-plane: θ-cut through the boresight axis' φ.  H-plane: the orthogonal plane (θ=90° ring for ±Z, θ-cut at φ=90° otherwise).
            u = app.ui; A = app.Axes; k = app.bsIdx; isE = startsWith(u.EH.Value, 'E');
            if isE || A.theta(k) ~= 90, u.CutType.Value = 'Theta'; val = 90; if isE, val = A.phi(k); end
            else, u.CutType.Value = 'Phi'; val = 90 - 90*app.elev; end
            vals = app.cutValues(); [~, i] = min(abs(vals - val)); u.CutVal.Value = vals(i);
        end

        function vals = cutValues(app)
            % Fixed-angle values available for the current cut type (display units); snap the spinner onto them.
            u = app.ui;
            if strcmp(u.CutType.Value, 'Phi'), vals = unique(app.view.Theta); else, vals = unique(mod(app.view.Phi, 360)); end
            u.CutVal.Limits = [min(vals) max(vals)]; if numel(vals) > 1, u.CutVal.Step = min(diff(vals)); end
            [~, i] = min(abs(vals - u.CutVal.Value)); u.CutVal.Value = vals(i);
        end

        function [cols, idx] = cutCols(app)
            % Selected traces: Total plus the circular or linear pair; IDX keeps a stable colour per trace.
            u = app.ui;
            if app.src.meta.isGainOnly, cols = string(u.Comp.Value); idx = 1; return; end
            if strcmp(u.Basis.Value, 'Linear'), pair = ["E_TH", "E_PH"]; else, pair = ["E_RCP", "E_LCP"]; end
            if ~strcmp(u.Er.Text, pair(1)), u.Er.Text = char(pair(1)); u.El.Text = char(pair(2)); end
            sel = [u.Et.Value, u.Er.Value, u.El.Value]; if ~any(sel), sel(1) = true; end
            idx = find(sel); cand = ["E_Total_dB", pair + "_dB"]; cols = cand(idx);
        end

        function C = cutData(app)
            % The active cut as one closed circle in the selected angular span: ang, Y (n×traces), physical th/ph, title.
            u = app.ui; T = app.view; [cols, idx] = app.cutCols(); type = string(u.CutType.Value); req = u.CutVal.Value;
            [thp, ~] = app.physAngles(); reqPhys = req; if type == "Phi" && app.elev, reqPhys = 90 - req; end
            c = cutRows(thp, T.Phi, type, reqPhys); fixed = c.fixed; if type == "Phi" && app.elev, fixed = 90 - fixed; end
            if c.snap, app.setStatus(u.Status, sprintf('Requested %s cut @ %s=%g° (snapped to nearest %s=%g°)', type, c.sym, req, c.sym, fixed)); end
            ang = c.ang; Y = T{c.rows, cols}; th = thp(c.rows); ph = T.Phi(c.rows);
            if app.signed, ang(ang > 180) = ang(ang > 180) - 360; [ang, o] = sort(ang); Y = Y(o, :); th = th(o); ph = ph(o); end
            if app.signed || type == "Phi", [ang, k] = unique(ang, 'stable'); Y = Y(k, :); th = th(k); ph = ph(k); end
            if type == "Phi"                                           % close the φ seam exactly once
                lo = -180*app.signed; hi = lo + 360; i0 = find(abs(ang - lo) < 1e-9, 1); i1 = find(abs(ang - hi) < 1e-9, 1);
                if isempty(i0) && ~isempty(i1), ang = [lo; ang]; Y = [Y(i1, :); Y]; th = [th(i1); th]; ph = [ph(i1); ph];
                elseif ~isempty(i0) && isempty(i1), ang = [ang; hi]; Y = [Y; Y(i0, :)]; th = [th; th(i0)]; ph = [ph; ph(i0)];
                elseif isempty(i0) && isempty(i1)
                    w = (hi - ang(end))/(ang(1) - lo + hi - ang(end)); Ys = (1 - w)*Y(end, :) + w*Y(1, :); ts = (1 - w)*th(end) + w*th(1);
                    ang = [lo; ang; hi]; Y = [Ys; Y; Ys]; th = [ts; th; ts]; ph = [lo; ph; hi];
                end
            end
            if app.src.meta.isGainOnly, ttl = char(cols(1)); else, ttl = sprintf('%s cut @ %s = %g°', type, c.sym, fixed); end
            C = struct('ang', ang, 'Y', Y, 'th', th, 'ph', ph, 'cols', cols, 'idx', idx, 'title', ttl, 'type', type);
        end

        function drawCut(app)
            if isempty(app.view), return; end
            u = app.ui; C = app.cutData(); pax = u.CutPolar; rax = u.CutRect; lim = app.cutLim; [xl, ~] = app.limits();
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on');
            hp = polarplot(pax, deg2rad(C.ang), max(C.Y, lim(1)), 'LineWidth', 1.4);     % clamp: no reflection spikes below RLim
            hr = plot(rax, C.ang, C.Y, 'LineWidth', 1.4); colors = rax.ColorOrder(1 + mod(C.idx - 1, 7), :);
            set([hp(:); hr(:)], {'Color'}, num2cell([colors; colors], 2));
            for k = 1:numel(hp)
                rows = [dataTipTextRow("Angle", C.ang, '%.3g°'); dataTipTextRow("Magnitude", C.Y(:, k), '%.3g dB')];
                hp(k).DataTipTemplate.DataTipRows = rows; hr(k).DataTipTemplate.DataTipRows = rows;
            end
            app.polarTicks(pax); set(pax, 'RLim', lim, 'RTick', lim(1):5:lim(2));
            set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on'); xlabel(rax, C.type + " (degree)");
            title(pax, C.title, 'Interpreter', 'none'); title(rax, C.title, 'Interpreter', 'none');
            [pk, i] = max(C.Y(:, 1), [], 'omitnan');                                  % POB of a cut = peak of its first trace
            rows = [dataTipTextRow("Angle", C.ang(i), '%.3g°'); dataTipTextRow("Magnitude", pk, '%.3g dB')];
            app.pin(pax, deg2rad(C.ang(i)), max(pk, lim(1)), 0, rows, 'APAT_POB', 'k'); app.pin(rax, C.ang(i), pk, 0, rows, 'APAT_POB', 'k');
            u.HPBWLbl.Text = '';
            if u.HPBW.Value
                [bw, lo, hi] = calcHPBW(C.ang, C.Y(:, 1), pk, C.ang(i));
                if isfinite(bw)
                    b = [lo hi]; if xl(1) < 0, b = mod(b + 180, 360) - 180; else, b = mod(b, 360); end
                    u.HPBWLbl.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                    reg = b; if b(1) > b(2), reg = [xl(1) b(2); b(1) xl(2)]; end        % wrap-aware shaded region
                    thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    xregion(rax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    names = ["Lower HPBW", "Upper HPBW"];
                    for k = 1:2
                        rows = [dataTipTextRow(names(k), b(k), '%.2f°'); dataTipTextRow("Gain", pk - 3, '%.2f dB')];
                        app.pin(pax, deg2rad(b(k)), pk - 3, 0, rows, 'APAT_HPBW', '#D95319'); app.pin(rax, b(k), pk - 3, 0, rows, 'APAT_HPBW', '#D95319');
                    end
                end
            end
            names = replace(C.cols, "_", "\_");
            legend(pax, hp, names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, hr, names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off'); app.overlayCut(); app.syncTips();
        end

        function overlayCut(app, ~, ~)
            % Draw (or remove) the active cut as a black trace on the 3-D spherical and 3-D polar plots.
            u = app.ui; axs = [u.Full(3).ax, u.Full(4).ax]; delete(findall(axs, 'Tag', 'APAT_Overlay'));
            if ~u.Overlay.Value || isempty(app.view) || ~isfield(app.grid, 'rmax'), return; end
            C = app.cutData(); lim = app.fullLim; r = {1.02, 1.01*max(C.Y(:, 1) - lim(1), 0)/max(diff(lim), eps)/app.grid.rmax};
            for k = 1:2
                hold(axs(k), 'on');
                plot3(axs(k), r{k}.*sind(C.th).*cosd(C.ph), r{k}.*sind(C.th).*sind(C.ph), r{k}.*cosd(C.th), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_Overlay');
                hold(axs(k), 'off');
            end
        end

        %% ── Exports ──────────────────────────────────────────────────────────────────────────────────────────
        function exportResults(app, ~, ~)
            if isempty(app.view), return; end
            fp = app.savePath({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Results', [app.file.base '_APAT_results.csv']);
            if isempty(fp), return; end
            try, writeTable(app.ui.TableOut.Data, fp); app.setStatus(app.ui.Status, ['Results exported to <b>' fp '</b>'], true);
            catch ME, app.showError(ME, 'Export Error'); end
        end

        function exportCut(app, ~, ~)
            if isempty(app.view), return; end
            C = app.cutData(); fp = app.savePath({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, 'Export Cut', [app.file.base '_cut.csv']);
            if isempty(fp), return; end
            try, writeTable(array2table([C.ang C.Y], 'VariableNames', [{'Angle_deg'}, cellstr(C.cols)]), fp); app.setStatus(app.ui.Status, ['Cut (' C.title ') exported to <b>' fp '</b>'], true);
            catch ME, app.showError(ME, 'Export Cut Error'); end
        end

        function exportUAN(app, ~, ~)
            % XGTD UAN: canonical header + tab-delimited Theta Phi |Eθ|dB |Eφ|dB ∠Eθ ∠Eφ rows (physical angles).
            u = app.ui; T = app.view;
            if app.src.meta.isGainOnly, uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            [th, ~] = app.physAngles();
            U = sortrows(table(th, T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'}), {'Phi', 'Theta'});
            st = gridStep(U.Theta); if ~isfinite(st), st = 1; end, gmax = max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan');
            fp = app.savePath({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, ...
                'Export UAN / E-field data', sprintf('%s_%.5f_%gdeg.uan', app.file.base, gmax, st));
            if isempty(fp), return; end
            d = uiprogressdlg(app.UIFigure, 'Title', 'Saving Data', 'Message', 'Writing file...', 'Indeterminate', 'on'); cleaner = onCleanup(@() delete(d));
            try
                if endsWith(fp, '.uan', 'IgnoreCase', true)
                    hdr = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                        'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                        min(U.Phi), max(U.Phi), gridStep(mod(U.Phi, 360)), min(U.Theta), max(U.Theta), st, gmax);
                    writelines(hdr, fp); writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
                else, writeTable(U, fp); end
                app.setStatus(u.Status, ['UAN exported to <b>' fp '</b>'], true);
            catch ME, app.showError(ME, 'Export UAN Error'); end
        end

        %% ── Coverage: node model ─────────────────────────────────────────────────────────────────────────────
        %   pattern node: kind,name,path,pattern,th,ph,dOmega,raw,rev,comp,bsIdx   results node: kind,name,path
        %   job node:     kind,id,tag,ttag,label,thr,cov,line,conical,orient,cone     — the tree itself is the registry.
        function n = covTarget(app)
            % Pattern node owning the current selection, else the most recently added pattern node.
            n = app.ui.CovTree.SelectedNodes; if ~isempty(n), n = n(1); end
            while ~isempty(n) && ~isKind(n, 'pattern'), n = n.Parent; if ~isa(n, 'matlab.ui.container.TreeNode'), n = []; end, end
            if isempty(n), kids = app.ui.CovRoot.Children; for k = numel(kids):-1:1, if isKind(kids(k), 'pattern'), n = kids(k); return; end, end, end
        end

        function n = covFind(app, fp)
            n = []; for k = app.ui.CovRoot.Children', if isstruct(k.NodeData) && strcmp(k.NodeData.path, fp), n = k; return; end, end
        end

        function jobs = covJobs(app, roots)
            % Job nodes under ROOTS (default: whole tree) sorted by run id.
            if nargin < 2, roots = app.ui.CovRoot; end
            nodes = findall(roots); jobs = nodes(arrayfun(@(n) isKind(n, 'job'), nodes)); jobs = jobs(:).';
            if numel(jobs) > 1, [~, o] = sort(arrayfun(@(n) n.NodeData.id, jobs)); jobs = jobs(o); end
        end

        function [T, th, ph] = processAux(app, out)
            % Process an auxiliary source (Coverage tab) with the current Main parameters; angles stay physical.
            S = normalizePattern(out.blocks{1}); S.Properties.UserData = out.meta;
            T = calcPattern(S, app.params()); th = T.Theta; ph = T.Phi;
        end

        function n = covAddPattern(app, name, T, th, ph, fp, raw)
            u = app.ui; n = uitreenode(u.CovRoot, 'Text', ['📡 ' name]);
            n.NodeData = struct('kind', 'pattern', 'name', name, 'path', fp, 'pattern', T, 'th', th, 'ph', ph, 'dOmega', solidWeights(th, ph), ...
                'raw', raw, 'rev', app.rev, 'comp', "", 'bsIdx', 1);
            expand(u.CovTree); u.CovTree.CheckedNodes = [u.CovTree.CheckedNodes; n]; u.CovTree.SelectedNodes = n;
            app.covSyncPattern(n); app.covUI(); app.setStatus(u.CovStatus, sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name));
        end

        function covSyncFromView(app, n)
            % Main-tab patterns always feed Coverage from the CURRENT view table (loss, step, span already applied).
            d = n.NodeData; [d.th, d.ph] = app.physAngles(); d.pattern = app.view; d.dOmega = app.dOmega; d.rev = app.rev; d.name = app.file.base;
            n.NodeData = d; app.covSyncPattern(n);
        end

        function covSyncPattern(app, n)
            % Align the component dropdown, boresight detection and the threshold PRESET with one pattern node.  The preset
            % is applied once per pattern|component|revision so user-edited thresholds survive until the data really changes.
            u = app.ui; d = n.NodeData; T = d.pattern; [cols, labels] = compList(T);
            prev = d.comp; if prev == "", prev = string(u.CovComp.Value); end, comp = pickComp(prev, cols);
            if ~isequal(string(u.CovComp.ItemsData), cols), u.CovComp.Items = cellstr(labels); u.CovComp.ItemsData = cellstr(cols); end
            u.CovComp.Value = char(comp); changed = d.comp ~= comp;
            if changed, d.comp = comp; d.bsIdx = calcOrientation(d.th, d.ph, T.(comp), d.dOmega, app.Axes, app.Pctl, app.Excess); n.NodeData = d; end
            key = string(sprintf('%s|%s|%d', d.path, comp, d.rev));
            if app.covKey ~= key, app.covRange(peakRange(T.(comp), app.Pctl, app.Excess), "threshold"); app.covKey = key; end
            if changed && u.Orient.Value == 0, app.covOrientChanged(); end
        end

        function job = covAddJob(app, parent, thr, cov, tag, comp, label, ttag)
            % Plot one CCDF curve and register it as a job node under PARENT (LABEL for the tree, TTAG for the table).
            u = app.ui; app.covId = app.covId + 1; icon = '📉'; if strcmp(tag, 'Res'), icon = '📈'; end
            name = sprintf('%s R%d %s · %s', icon, app.covId, label, comp);
            h = plot(u.CovAxes, thr, cov, 'LineWidth', 1.6, 'DisplayName', name); job = uitreenode(parent, 'Text', name);
            job.NodeData = struct('kind', 'job', 'id', app.covId, 'tag', tag, 'ttag', ttag, 'label', name, 'thr', thr(:), 'cov', cov(:), 'line', h, ...
                'conical', false, 'orient', "n/a", 'cone', [NaN NaN NaN]);
        end

        function covLoadResults(app, fp, R)
            % A coverage-results table (threshold column + one coverage column per curve) becomes a results node with jobs.
            u = app.ui; [~, name] = fileparts(fp); n = uitreenode(u.CovRoot, 'Text', ['📄 ' name]);
            n.NodeData = struct('kind', 'results', 'name', name, 'path', fp); thr = R{:, 1}; app.covRange([min(thr) max(thr)], "plot", gridStep(thr));
            jobs = cell(1, width(R) - 1);
            for c = 2:width(R), jobs{c-1} = app.covAddJob(n, thr, R{:, c}, 'Res', R.Properties.VariableNames{c}, 'Res', 'Res'); end
            u.CovTree.CheckedNodes = [u.CovTree.CheckedNodes; n; vertcat(jobs{:})]; expand(n); app.covRefresh(); u.CovResults.Visible = 'on';
            app.setStatus(u.CovStatus, sprintf('Coverage results file "%s" loaded (%d curves).', name, width(R) - 1));
        end

        function covRefresh(app)
            % Rebuild the results table and legend from the checked jobs, then refresh the panel state.
            u = app.ui; jobs = app.covJobs(); on = jobs(ismember(jobs, u.CovTree.CheckedNodes)); expand(u.CovRoot);
            if isempty(on)
                u.CovTable.Data = table(); legend(u.CovAxes, 'off');
            else
                D = [on.NodeData]; thr = unique(vertcat(D.thr)); V = nan(numel(thr), numel(on) + 1); V(:, 1) = thr; names = {'Threshold (dB)'};
                for k = 1:numel(on), V(:, k+1) = interp1(D(k).thr, D(k).cov, thr, 'linear', NaN); names{k+1} = sprintf('R%d %s %%', D(k).id, D(k).ttag); end
                u.CovTable.Data = array2table(compose('%.2f', V), 'VariableNames', names);
                legend(u.CovAxes, [D.line], {D.label}, 'Location', 'southwest', 'Interpreter', 'none');
            end
            app.covUI();
        end

        function covUI(app)
            % Reveal controls progressively: nothing loaded → results only → pattern loaded (all controls).
            u = app.ui; hasPat = ~isempty(app.covTarget()); hasJobs = ~isempty(app.covJobs()); some = hasPat || hasJobs;
            set(u.CovPanel.Children, 'Visible', hasPat, 'Enable', hasPat); set([u.CovPathLbl u.CovPath u.CovLoad u.CovCompute], 'Visible', 'on', 'Enable', 'on');
            set([u.CovQuery u.CovReset u.CovExport u.CovClear u.CovToMain], 'Visible', some, 'Enable', some); set([u.CovQuery u.CovExport u.CovClear], 'Enable', hasJobs);
            set([u.CovFmtLbl u.CovFmt], 'Visible', hasPat && isGenericText(u.CovPath.Value));
            if hasPat, app.covTypeChanged(); end
        end

        %% ── Coverage: thresholds and ranges ──────────────────────────────────────────────────────────────────
        function thr = covThresholds(app)
            % The user's CURRENT threshold controls, verbatim (presets happen only in covSyncPattern).
            u = app.ui; lo = u.ThrMin.Value; hi = u.ThrMax.Value; st = max(u.ThrStep.Value, 0.1);
            if hi <= lo, hi = min(100, lo + st); u.ThrMax.Value = hi; end
            thr = (lo:st:hi)'; if isempty(thr), thr = [lo; hi]; elseif thr(end) < hi, thr(end+1) = hi; end
        end

        function covRange(app, b, mode, step)
            % "threshold": preset the threshold spinners; "plot": set the Coverage X range.  After the first use each only widens.
            u = app.ui; b = clampRange(b, [-250 100]);
            if mode == "threshold"
                if app.covInit(1), b = [min(u.ThrMin.Value, b(1)), max(u.ThrMax.Value, b(2))]; end, app.covInit(1) = true;
                set([u.ThrMin u.ThrMax], 'Limits', [-250 100]); u.ThrMin.Value = b(1); u.ThrMax.Value = b(2);
                u.ThrMin.Limits = [-250 b(2)-0.1]; u.ThrMax.Limits = [b(1)+0.1 100];
            else
                if app.covInit(2), b = [min(u.CovAxes.XLim(1), b(1)), max(u.CovAxes.XLim(2), b(2))]; end, app.covInit(2) = true;
                app.covSetX(b);
            end
            if nargin > 3 && isfinite(step) && step < u.ThrStep.Value, u.ThrStep.Value = step; end
        end

        function covSetX(app, b)
            % Spinners are the masters of the X range; the slider travels inside their limits.
            u = app.ui; set(u.CovAxes, 'XLimMode', 'manual', 'XLim', b);
            u.XRange.Limits = [-250 100]; u.XRange.Value = b; u.XRange.Limits = b;
            set(u.XMin, 'Limits', [-250 b(2)-0.1], 'Value', b(1)); set(u.XMax, 'Limits', [b(1)+0.1 100], 'Value', b(2));
        end

        function covXRange(app, ~, ev)
            u = app.ui;
            if isequal(ev.Source, u.XRange)                              % subordinate slider: move XLim, keep its limits
                b = sort(ev.Value); if diff(b) <= 0, return; end
                u.XMin.Value = b(1); u.XMax.Value = b(2); set(u.CovAxes, 'XLimMode', 'manual', 'XLim', b);
            else                                                         % master spinners: keep the edited endpoint
                b = sort([u.XMin.Value u.XMax.Value]);
                if diff(b) < 1, if isequal(ev.Source, u.XMin), b(2) = min(100, b(1) + 1); else, b(1) = max(-250, b(2) - 1); end, end
                app.covSetX(b);
            end
        end

        %% ── Coverage: actions ────────────────────────────────────────────────────────────────────────────────
        function toCoverage(app, ~, ~)
            u = app.ui;
            if isempty(app.view), uialert(app.UIFigure, 'No processed View Table is available. Load and process a pattern first.', 'Coverage'); return; end
            u.Tabs.SelectedTab = u.TabCov; u.CovPath.Value = app.file.path; n = app.covFind(app.file.path);
            if isempty(n), [th, ph] = app.physAngles(); app.covAddPattern(app.file.base, app.view, th, ph, app.file.path, app.view);
            else, app.covSyncFromView(n); u.CovTree.SelectedNodes = n; app.covUI(); end
            app.setStatus(u.CovStatus, 'Coverage source synchronized from the current Main-tab View Table.');
        end

        function covLoad(app, ~, ~)
            u = app.ui; fp = strtrim(u.CovPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFind(fp)), fp = app.browse('Select a pattern or coverage results file'); if isempty(fp), return; end, end
            n = app.covFind(fp);
            if ~isempty(n)
                u.CovTree.SelectedNodes = n; app.covSelected(); p = app.covTarget(); if ~isempty(p), fp = p.NodeData.path; end
                u.CovPath.Value = fp; app.covUI(); app.setStatus(u.CovStatus, 'File already loaded -- node selected. Add another job or load a different file.', true); return
            end
            u.CovPath.Value = fp;
            try
                out = app.readSource(fp, u.CovFmtLbl, u.CovFmt);
                if out.meta.isCoverage
                    p = app.covTarget(); if ~isempty(p), u.CovPath.Value = p.NodeData.path; end, app.covLoadResults(fp, out.rawTbl);
                else
                    [~, name] = fileparts(fp); [T, th, ph] = app.processAux(out); app.covAddPattern(name, T, th, ph, fp, out.rawTbl);
                end
                u.CovResults.Visible = 'on';
            catch ME, app.showError(ME, 'Coverage Load Error'); end
        end

        function covFormatChanged(app, ~, ~)
            % Replace a generic coverage-pattern node after its text format selector changed.
            u = app.ui; fp = strtrim(u.CovPath.Value); old = app.covFind(fp);
            if isempty(old) || ~isKind(old, 'pattern') || ~isGenericText(fp), return; end
            try
                out = readPattern(fp, u.CovFmt.Value, old.NodeData.raw);
                if out.meta.isCoverage, app.setStatus(u.CovStatus, 'Coverage-result format is detected automatically; no pattern reprocessing required.', true); return; end
                for j = app.covJobs(old), delete(j.NodeData.line); end
                name = old.NodeData.name; delete(old); [T, th, ph] = app.processAux(out);
                app.covAddPattern(name, T, th, ph, fp, out.rawTbl); app.covRefresh();
                app.setStatus(u.CovStatus, sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
            catch ME, app.showError(ME, 'Coverage Format Error'); end
        end

        function covCompute(app, ~, ~)
            u = app.ui; n = app.covTarget();
            if isempty(n), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if ~isempty(app.view) && strcmp(n.NodeData.path, app.file.path), app.covSyncFromView(n); end
            try
                d = n.NodeData; T = d.pattern; comp = u.CovComp.Value; thr = app.covThresholds(); conical = u.Conical.Value;
                mask = true(height(T), 1); tag = 'Sph'; label = 'Sph coverage'; ttag = 'Sph'; orient = "n/a"; cone = [NaN NaN NaN];
                if conical
                    k = u.Orient.Value; if k == 0, k = d.bsIdx; end, orient = string(app.Axes.labels{k});
                    cone = [u.ConeTh.Value, mod(u.ConePh.Value, 360), u.ConeAng.Value];
                    mask = cosd(d.th)*cosd(cone(1)) + sind(d.th)*sind(cone(1)).*cosd(d.ph - cone(2)) >= cosd(cone(3));
                    c = app.coneLabel(cone(1), cone(2)); tag = sprintf('Con_%.15g_%.15g_%.15g', cone);
                    label = sprintf('Conical coverage (%s) α=%s°', c, fmt(cone(3))); ttag = sprintf('Con %s α%s°', erase(c, ["=", ","]), fmt(cone(3)));
                end
                cov = coverageCCDF(T.(comp), mask, thr, d.dOmega); job = app.covAddJob(n, thr, cov, tag, comp, label, ttag);
                jd = job.NodeData; jd.conical = conical; jd.orient = orient; jd.cone = cone; job.NodeData = jd;
                u.CovTree.CheckedNodes = [u.CovTree.CheckedNodes; job]; expand(n); app.covRefresh(); app.covRange(thr([1 end]), "plot"); u.CovResults.Visible = 'on';
                msg = sprintf('Run-<b>%d</b> computed: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', app.covId, label, d.name, comp, numel(thr));
                if conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, orient); end
                app.setStatus(u.CovStatus, msg);
            catch ME, app.showError(ME, 'Coverage Error'); end
        end

        function covQuery(app, mode)
            % Mark the coverage at a threshold ("cov") or the threshold at a coverage ("thr") on every checked job under the selection.
            u = app.ui; ax = u.CovAxes; isCov = mode == "cov"; if isCov, q = u.QCov.Value; else, q = u.QThr.Value; end
            sel = u.CovTree.SelectedNodes; if isempty(sel), app.setStatus(u.CovStatus, 'Select a node to query.', true); return; end
            jobs = app.covJobs(sel); jobs = jobs(ismember(jobs, u.CovTree.CheckedNodes));
            if isempty(jobs), app.setStatus(u.CovStatus, 'No checked results under selected node.', true); return; end
            hit = false;
            for j = jobs
                d = j.NodeData; tag = sprintf('CovQ_%s_%d', mode, d.id); delete(findall(ax, 'Tag', tag));
                if isCov, x = q; y = interp1(d.thr, d.cov, q, 'linear', NaN); else, x = thrAt(d.thr, d.cov, q); y = q; end
                if ~isfinite(x) || ~isfinite(y), continue; end
                line(ax, [x x], [ax.YLim(1) y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [-250 x], [y y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                app.pin(ax, x, y, 0, [dataTipTextRow("Threshold", x, '%.2f dB'); dataTipTextRow("Coverage", y, '%.2f %%')], tag, d.line.Color); hit = true;
            end
            if ~hit, app.setStatus(u.CovStatus, 'Query value is outside the selected checked range.', true);
            elseif isCov, app.setStatus(u.CovStatus, sprintf('Coverage queried at %s dB.', fmt(q)));
            else, app.setStatus(u.CovStatus, sprintf('Threshold queried at %s%% coverage.', fmt(q))); end
        end

        function covClear(app, ~, ~)
            u = app.ui; s = u.CovTree.SelectedNodes;
            if isempty(s), app.setStatus(u.CovStatus, 'Select a node to clear.', true); return; end
            for j = app.covJobs(s), d = j.NodeData; delete([findall(u.CovAxes, '-regexp', 'Tag', sprintf('^CovQ_(cov|thr)_%d$', d.id)); findall(d.line, 'Type', 'datatip')]); end
            app.setStatus(u.CovStatus, 'Selected DataTips and query markers cleared.', true);
        end

        function covReset(app, ~, ~)
            u = app.ui; delete(u.CovRoot.Children); cla(u.CovAxes); legend(u.CovAxes, 'off'); hold(u.CovAxes, 'on'); grid(u.CovAxes, 'on'); ylim(u.CovAxes, [0 100]);
            u.CovTable.Data = table(); app.covId = 0; app.covKey = ""; app.covInit(:) = false; set(u.CovAxes, 'XLimMode', 'auto');
            u.XRange.Limits = [-250 100]; u.XRange.Value = [-40 10]; set([u.XMin u.XMax], 'Limits', [-250 100]); u.XMin.Value = -40; u.XMax.Value = 10;
            u.CovResults.Visible = 'off'; app.covUI(); app.setStatus(u.CovStatus, 'Coverage workspace reset 🔄', true);
        end

        function covExport(app, ~, ~)
            if isempty(app.ui.CovTable.Data), return; end
            fp = app.savePath({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Coverage Results', 'coverage_results.csv');
            if isempty(fp), return; end
            try, writeTable(app.ui.CovTable.Data, fp); app.setStatus(app.ui.CovStatus, ['Coverage results exported to ' fp], true);
            catch ME, app.showError(ME, 'Export Error'); end
        end

        %% ── Coverage: tree and orientation callbacks ─────────────────────────────────────────────────────────
        function covChecked(app, ~, ~)
            u = app.ui; checked = u.CovTree.CheckedNodes;
            for j = app.covJobs()
                d = j.NodeData; on = ismember(j, checked);
                set([d.line; findall(u.CovAxes, '-regexp', 'Tag', sprintf('^CovQ_(cov|thr)_%d$', d.id)); findall(d.line, 'Type', 'datatip')], 'Visible', on);
            end
            app.covRefresh();
        end

        function covSelected(app, ~, ~)
            u = app.ui; s = u.CovTree.SelectedNodes;
            for j = app.covJobs(), set(j.NodeData.line, 'LineWidth', 1.6); end                       % selection = visual emphasis only
            if isempty(s) || ~isstruct(s(1).NodeData), app.setStatus(u.CovStatus, 'Ready.'); return; end
            d = s(1).NodeData; p = app.covTarget(); if ~isempty(p), app.covSyncPattern(p); end
            if ~strcmp(d.kind, 'job')
                kind = 'Pattern'; if strcmp(d.kind, 'results'), kind = 'Results'; end, nJ = numel(s(1).Children);
                app.setStatus(u.CovStatus, sprintf('%s <b>"%s"</b> -- <b>%d</b> coverage job%s.', kind, d.name, nJ, repmat('s', 1, double(nJ ~= 1))));
                if strcmp(d.kind, 'pattern') && u.Conical.Value, app.covStatusOrient(); end
                return
            end
            set(d.line, 'LineWidth', 2.6); t50 = thrAt(d.thr, d.cov, 50); shown = round(d.cov, 2); cmax = max(shown); i = find(shown == cmax, 1, 'last');
            parts = {d.label}; if d.conical, parts{end+1} = sprintf('Orientation <b>%s</b>', d.orient); end
            parts{end+1} = sprintf('Threshold [%s, %s] dB | Step %s dB', fmt(d.thr(1)), fmt(d.thr(end)), fmt(gridStep(d.thr)));
            if isfinite(t50), parts{end+1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', fmt(t50)); else, parts{end+1} = '<b>50%-coverage unavailable</b>'; end
            parts{end+1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmt(cmax), fmt(d.thr(i))); app.setStatus(u.CovStatus, strjoin(parts, ' | '));
        end

        function covTypeChanged(app, ~, ~)
            u = app.ui; on = u.Conical.Value; set(u.ConeCtl, 'Visible', on, 'Enable', on);
            if on, n = app.covTarget(); if ~isempty(n), app.covSyncPattern(n); end, app.covStatusOrient();
            else, u.CovStatus.Text = regexprep(u.CovStatus.Text, '\s*\|\s*Orientation <b>.*?</b>', ''); end
        end

        function covStatusOrient(app)
            % Append the resolved conical orientation (Auto → detected axis) to the sticky Coverage status.
            u = app.ui; if ~u.Conical.Value, return; end
            k = u.Orient.Value; if k == 0, n = app.covTarget(); if isempty(n), return; end, k = n.NodeData.bsIdx; end
            msg = regexprep(char(u.CovStatus.Text), '\s*\|\s*Orientation <b>.*?</b>$', '');
            app.setStatus(u.CovStatus, sprintf('%s | Orientation <b>%s</b>', msg, app.Axes.labels{k}));
        end

        function covOrientChanged(app, ~, ~)
            % Auto resolves the detected axis; an explicit choice is authoritative.  Either way the cone centre follows.
            u = app.ui; k = u.Orient.Value; if k == 0, n = app.covTarget(); if isempty(n), return; end, k = n.NodeData.bsIdx; end
            u.ConeTh.Value = app.Axes.theta(k); u.ConePh.Value = app.Axes.phi(k); app.covStatusOrient();
        end

        function covCompChanged(app, ~, ~)
            u = app.ui; n = app.covTarget(); if isempty(n), return; end
            d = n.NodeData; comp = string(u.CovComp.Value); if ~any(comp == string(d.pattern.Properties.VariableNames)), return; end
            d.comp = comp; d.bsIdx = calcOrientation(d.th, d.ph, d.pattern.(comp), d.dOmega, app.Axes, app.Pctl, app.Excess); n.NodeData = d; app.covStatusOrient();
        end

        function s = coneLabel(app, th, ph)
            % Principal-axis name when the cone centre coincides with ±X/±Y/±Z, else the explicit θ/φ pair.
            k = find(app.Axes.vec*[sind(th)*cosd(ph); sind(th)*sind(ph); cosd(th)] >= 1 - 1e-9, 1);
            if isempty(k), s = sprintf('θ=%s°, φ=%s°', fmt(th), fmt(ph)); else, s = app.Axes.labels{k}; end
        end
    end

    %% ── UI construction ──────────────────────────────────────────────────────────────────────────────────────
    methods (Access = private)
        function buildUI(app)
            A = @(fcn, p, r, c, varargin) place(fcn(p, varargin{:}), r, c);               % create + place in a grid cell
            L = @(p, txt, r, c, varargin) A(@uilabel, p, r, c, 'Text', txt, 'HorizontalAlignment', 'right', varargin{:});
            E = @(p, varargin) uieditfield(p, 'text', varargin{:}); RS = @(p, varargin) uislider(p, 'range', varargin{:});
            SW = @(p, varargin) uiswitch(p, 'slider', varargin{:}); SB = @(p, varargin) uibutton(p, 'state', varargin{:});
            fmtItems = {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', '4: POL1=RCP, POL2=LCP — dB magnitude, phase', ...
                '5: POL1=LCP, POL2=RCP — dB magnitude, phase', '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'};
            fmtData = {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'};
            FD = @(p, cb) uidropdown(p, 'Items', fmtItems, 'ItemsData', fmtData, 'Value', 'gain', 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'ValueChangedFcn', cb);
            nb = char(160); u = struct();

            fig = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.Release], 'Visible', 'off', 'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', @(~,~) delete(app));
            app.UIFigure = fig; u.Tabs = uitabgroup(uigridlayout(fig, [1 1]), 'SelectionChangedFcn', @app.syncTips);

            % ── Main tab ────────────────────────────────────────────────────────────────────────────────
            u.TabMain = uitab(u.Tabs, 'Title', 'Process Pattern 📡');
            G = uigridlayout(u.TabMain, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});
            P = uigridlayout(A(@uipanel, G, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️'), 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            L(P, 'Input Pattern:', 1, 1); u.Path = A(E, P, 1, [2 8]);
            u.FFDLbl = L(P, 'FFD Freq:', 1, 9, 'Visible', 'off'); u.FFD = A(@uidropdown, P, 1, 10, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', @app.onFFD);
            A(@uibutton, P, 1, [11 12], 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', @app.onLoad);
            A(@uibutton, P, 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', @app.onProcess);
            A(@uibutton, P, 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', @app.resetParams);
            u.FormatLbl = L(P, 'Format:', 2, [4 5], 'Visible', 'off'); u.Format = A(FD, P, 2, [6 8], @app.onFormat); u.Format.Visible = 'off';
            u.Step = A(@uidropdown, P, 2, [9 10], 'Items', {'STEP', 'STEP: 1°'}, 'Visible', 'off', 'Enable', 'off', 'ValueChangedFcn', @app.onStep);
            u.ExportOut = A(@uibutton, P, 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', @app.exportResults);
            u.ExportUAN = A(@uibutton, P, 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', @app.exportUAN);
            u.RxPolLbl = L(P, 'Rw Sense', 3, 1, 'Visible', 'off'); u.RxPol = A(@uidropdown, P, 3, 2, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Editable', 'on', 'Visible', 'off');
            u.RwLbl = L(P, 'Rw (dB)', 3, 3, 'Visible', 'off'); u.Rw = A(@uispinner, P, 3, 4, 'Value', 6, 'Visible', 'off');
            u.LossLbl = L(P, 'Loss (−) / Gain (+) dB', 3, 5, 'Visible', 'off'); u.Loss = A(@uispinner, P, 3, 6, 'Step', 0.1, 'Visible', 'off');
            u.PtLbl = L(P, 'Tx Pwr (Pt)', 3, 7, 'Visible', 'off'); u.Pt = A(@uispinner, P, 3, 8, 'Visible', 'off'); u.PtUnit = A(@uidropdown, P, 3, 9, 'Items', {'dBW', 'dBm', 'Watts'}, 'Visible', 'off');
            u.RLbl = L(P, 'Distance', 3, 10, 'Visible', 'off'); u.R = A(@uispinner, P, 3, 11, 'Value', 1, 'Visible', 'off'); u.RUnit = A(@uidropdown, P, 3, 12, 'Items', {'m', 'km'}, 'Visible', 'off');
            u.CovBtn = A(@uibutton, P, 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', @app.toCoverage);

            % Full-pattern plots: five tabs built from one spec (axes + vertical range slider + min/max spinners)
            u.PanelFull = A(@uipanel, G, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off', 'BackgroundColor', [0.94 0.94 0.94]);
            u.FullTabs = uitabgroup(uigridlayout(u.PanelFull, [1 1]), 'SelectionChangedFcn', @app.syncTips);
            titles = {'Contour Plot', 'Circular Contour Plot', '3D Spherical Plot', '3D Polar Plot', '3D Surface Plot'};
            for k = 1:5
                g = uigridlayout(uitab(u.FullTabs, 'Title', titles{k}), 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
                if k == 2, ax = polaraxes(g); else, ax = uiaxes(g); end, place(ax, [1 3], 2); app.setupAxes(ax, k > 2);
                u.Full(k) = struct('ax', ax, 'hi', A(@uispinner, g, 1, 1, 'Limits', [-250 100], 'Value', 100, 'Step', 5, 'ValueChangedFcn', @(s,~) app.setRange(s.Value, 2, "full")), ...
                    'rng', A(RS, g, 2, 1, 'Limits', [-250 100], 'Value', [-250 100], 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s,~) app.setRange(s.Value, -1, "full")), ...
                    'lo', A(@uispinner, g, 3, 1, 'Limits', [-250 100], 'Value', -250, 'Step', 5, 'ValueChangedFcn', @(s,~) app.setRange(s.Value, 1, "full")));
            end

            % Cut plots: polar tab (with cut controls) and rectangular tab
            u.PanelCut = A(@uipanel, G, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off', 'BackgroundColor', [0.94 0.94 0.94]);
            u.CutTabs = uitabgroup(uigridlayout(u.PanelCut, [1 1]), 'SelectionChangedFcn', @app.syncTips);
            g = uigridlayout(uitab(u.CutTabs, 'Title', 'Polar Cut Plot'), 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            u.CutPolar = place(polaraxes(g), [1 4], 3); app.setupAxes(u.CutPolar, false);
            u.CutHi = A(@uispinner, g, 1, 1, 'Limits', [-250 100], 'Value', 100, 'Step', 5, 'ValueChangedFcn', @(s,~) app.setRange(s.Value, 2, "cut"));
            u.CutRng = A(RS, g, [2 3], 1, 'Limits', [-250 100], 'Value', [-250 100], 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s,~) app.setRange(s.Value, -1, "cut"));
            u.CutLo = A(@uispinner, g, 4, 1, 'Limits', [-250 100], 'Value', -250, 'Step', 5, 'ValueChangedFcn', @(s,~) app.setRange(s.Value, 1, "cut"));
            u.HPBW = A(SB, g, 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', @app.onCut);
            u.HPBWLbl = A(@uilabel, g, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            u.Ecut = uigridlayout(g, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x', '1x', '1x'}); place(u.Ecut, 3, 4);
            u.Et = A(@uicheckbox, u.Ecut, 1, 1, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', @app.onCut);
            u.Er = A(@uicheckbox, u.Ecut, 2, 1, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', @app.onCut);
            u.El = A(@uicheckbox, u.Ecut, 3, 1, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', @app.onCut);
            A(@uibutton, g, 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', @app.exportCut);
            u.CutRect = place(uiaxes(uigridlayout(uitab(u.CutTabs, 'Title', 'Rectangular Cut Plot'), [1 1])), 1, 1); app.setupAxes(u.CutRect, false);

            % Plot control panel
            u.PanelCtrl = A(@uipanel, G, 2, [13 14], 'Title', 'Plot Control 🎨', 'Visible', 'off'); C = uigridlayout(u.PanelCtrl, 'RowHeight', repmat({'fit'}, 1, 15));
            L(C, 'Component', 1, 1); u.Comp = A(@uidropdown, C, 1, 2, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', @app.onComponent);
            L(C, 'Cut type', 2, 1); u.CutType = A(@uidropdown, C, 2, 2, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', @app.onCut);
            L(C, 'Cut value', 3, 1); u.CutVal = A(@uispinner, C, 3, 2, 'Limits', [0 360], 'ValueChangedFcn', @app.onCut);
            L(C, 'Cut fields', 4, 1); u.Basis = A(@uidropdown, C, 4, 2, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Enable', 'off', 'UserData', true, 'ValueChangedFcn', @app.onCut);
            applyAll = @(~,~) app.setRange([app.ui.Cmin.Value app.ui.Cmax.Value], 0, "all");
            L(C, 'Colorbar max', 5, 1); u.Cmax = A(@uispinner, C, 5, 2, 'Limits', [-250 100], 'Value', 10);
            L(C, 'Colorbar min', 6, 1); u.Cmin = A(@uispinner, C, 6, 2, 'Limits', [-250 100], 'Value', -40);
            L(C, 'Colorbar step', 7, 1); u.Cstep = A(@uispinner, C, 7, 2, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', @(~,~) app.applyLim("full"));
            L(C, 'Adjust Colorbar', 8, 1); A(@uibutton, C, 8, 2, 'Text', 'Apply', 'Tooltip', 'Apply to full-pattern and cut plots (axial ratio keeps its ±30 dB scale).', 'ButtonPushedFcn', applyAll);
            set([u.Cmin u.Cmax], 'ValueChangedFcn', applyAll);
            L(C, '3D view', 9, 1); u.View3D = A(@uidropdown, C, 9, 2, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Tooltip', 'Camera direction for the 3D pattern tabs.', 'ValueChangedFcn', @app.onView3D);
            u.PhiSpan = A(SW, C, 10, [1 2], 'Items', {['φ span: 0° to 360°' repmat(nb, 1, 3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'ValueChangedFcn', @app.onSpan);
            u.ThSpan = A(SW, C, 11, [1 2], 'Items', {'θ span: 0° to 180°', ['−90° to 90°' repmat(nb, 1, 2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'ValueChangedFcn', @app.onSpan);
            u.EH = A(SW, C, 12, [1 2], 'Items', {[repmat(nb, 1, 8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'ValueChangedFcn', @app.onEH);
            u.Overlay = A(@uicheckbox, C, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', @app.overlayCut);
            u.POB = A(@uicheckbox, C, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', @app.syncTips);
            u.HPBWTips = A(@uicheckbox, C, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', @app.syncTips);

            % Data tables and status
            u.Filter = A(@uidropdown, G, 3, [13 14], 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Value', 0, 'Visible', 'off', 'ValueChangedFcn', @(~,~) app.filterOutput(false));
            u.DataTabs = A(@uitabgroup, G, 4, [1 14], 'Visible', 'off');
            u.TableOut = place(uitable(uigridlayout(uitab(u.DataTabs, 'Title', 'Results 📤'), [1 1]), 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnWidth', '1x'), 1, 1);
            u.TableIn = place(uitable(uigridlayout(uitab(u.DataTabs, 'Title', 'Input 📥'), [1 1]), 'ColumnSortable', true, 'RowName', 'numbered'), 1, 1);
            u.TableMeta = place(uitable(uigridlayout(uitab(u.DataTabs, 'Title', 'Metadata 📋'), [1 1]), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {}), 1, 1);
            u.Status = A(@uilabel, G, 5, [1 14], 'Interpreter', 'html', 'Text', 'Ready 🚀');

            % ── Coverage tab ────────────────────────────────────────────────────────────────────────────
            u.TabCov = uitab(u.Tabs, 'Title', 'Compute Coverage 📈');
            G = uigridlayout(u.TabCov, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            P = uigridlayout(A(@uipanel, G, 1, [1 5], 'Title', 'Inputs & Parameters 🎛️'), 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'}); u.CovPanel = P;
            bg = A(@uibuttongroup, P, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', @app.covTypeChanged);
            uiradiobutton(bg, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true); u.Conical = uiradiobutton(bg, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            u.OrientLbl = L(P, 'Orientation 🧭:', 3, 1); u.Orient = A(@uidropdown, P, 3, 2, 'Items', [{'Auto'}, app.Axes.labels], 'ItemsData', 0:6, 'Value', 0, 'ValueChangedFcn', @app.covOrientChanged);
            u.CovCompLbl = L(P, 'Component:', 4, 1); u.CovComp = A(@uidropdown, P, 4, 2, 'Items', {'E_Total_dB'}, 'ValueChangedFcn', @app.covCompChanged);
            u.CovPathLbl = L(P, 'Antenna Pattern:', 1, 3); u.CovPath = A(E, P, 1, [4 8]);
            u.CovLoad = A(@uibutton, P, 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', @app.covLoad);
            u.CovCompute = A(@uibutton, P, 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'ButtonPushedFcn', @app.covCompute);
            L(P, 'Threshold  Min (dB):', 2, 3); u.ThrMin = A(@uispinner, P, 2, 4, 'Value', -40);
            L(P, 'Threshold  Max (dB):', 2, 5); u.ThrMax = A(@uispinner, P, 2, 6, 'Value', 10);
            L(P, 'Step (dB):', 2, 7); u.ThrStep = A(@uispinner, P, 2, 8, 'Value', 1, 'Limits', [0.1 100]);
            u.CovReset = A(@uibutton, P, 2, 9, 'Text', '🔄 Reset', 'ButtonPushedFcn', @app.covReset);
            u.CovExport = A(@uibutton, P, 2, 10, 'Text', '💾 Export Results', 'ButtonPushedFcn', @app.covExport);
            cl = {L(P, 'Cone θ₀ (°):', 3, 3), L(P, 'Cone φ₀ (°):', 3, 5), L(P, 'Cone Angle α (°):', 3, 7)};
            u.ConeTh = A(@uispinner, P, 3, 4, 'Limits', [0 180]); u.ConePh = A(@uispinner, P, 3, 6, 'Limits', [0 360]); u.ConeAng = A(@uispinner, P, 3, 8, 'Limits', [0 180], 'Value', 45);
            u.ConeCtl = [u.ConeTh, u.ConePh, u.ConeAng, cl{:}, u.Orient, u.OrientLbl];
            u.CovClear = A(@uibutton, P, 3, 9, 'Text', '🧹 Clear DataTips', 'ButtonPushedFcn', @app.covClear);
            u.CovToMain = A(@uibutton, P, 3, 10, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~,~) set(u.Tabs, 'SelectedTab', u.TabMain));
            ql = {L(P, 'Coverage @ dB:', 4, 3), L(P, 'Threshold @ %:', 4, 6)};
            u.QCov = A(@uispinner, P, 4, 4, 'ValueDisplayFormat', '%g dB'); u.QThr = A(@uispinner, P, 4, 7, 'ValueDisplayFormat', '%g%%', 'Value', 50, 'Limits', [0 100]);
            qc = A(@uibutton, P, 4, 5, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', @(~,~) app.covQuery("cov"));
            qt = A(@uibutton, P, 4, 8, 'Text', '🔍︎ Query Threshold', 'ButtonPushedFcn', @(~,~) app.covQuery("thr"));
            u.CovQuery = [ql{1}, u.QCov, qc, ql{2}, u.QThr, qt];
            u.CovFmtLbl = L(P, 'Format:', 4, 9); u.CovFmt = A(FD, P, 4, 10, @app.covFormatChanged);
            u.CovStatus = A(@uilabel, G, 3, [1 5], 'Interpreter', 'html', 'Text', 'Ready 🚀');
            u.CovResults = A(@uipanel, G, 2, [1 5], 'Title', 'Results', 'Visible', 'off');
            R = uigridlayout(u.CovResults, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            u.CovAxes = A(@uiaxes, R, 1, [2 4], 'Interactions', dataTipInteraction); title(u.CovAxes, 'Coverage vs Threshold'); xlabel(u.CovAxes, 'Threshold (dB)'); ylabel(u.CovAxes, 'Coverage (%)');
            u.CovTree = A(@(p, varargin) uitree(p, 'checkbox', varargin{:}), R, [1 2], 1, 'SelectionChangedFcn', @app.covSelected, 'CheckedNodesChangedFcn', @app.covChecked);
            u.CovRoot = uitreenode(u.CovTree, 'Text', 'Coverage Results');
            u.CovTable = A(@uitable, R, [1 2], 5, 'ColumnWidth', '1x', 'RowName', {});
            u.XMin = A(@uispinner, R, 2, 2, 'Limits', [-250 100], 'Value', -40, 'ValueChangedFcn', @app.covXRange);
            u.XRange = A(RS, R, 2, 3, 'Limits', [-250 100], 'Value', [-40 10], 'ValueChangedFcn', @app.covXRange, 'ValueChangingFcn', @app.covXRange);
            u.XMax = A(@uispinner, R, 2, 4, 'Limits', [-250 100], 'Value', 10, 'ValueChangedFcn', @app.covXRange);
            app.ui = u; fig.Visible = 'on';
        end

        function setupAxes(app, ax, is3D)
            % Local gestures only (no figure-level modes) plus a "Delete DataTips" context menu on every non-polar axes.
            enableDefaultInteractivity(ax); if isa(ax, 'matlab.graphics.axis.PolarAxes'), return; end
            if is3D, ax.Interactions = [rotateInteraction dataTipInteraction]; else, ax.Interactions = [zoomInteraction dataTipInteraction]; end
            m = uicontextmenu(app.UIFigure); uimenu(m, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~,~) delete(findall(ax, 'Type', 'datatip'))); ax.ContextMenu = m;
        end
    end

    %% ── Self-test ────────────────────────────────────────────────────────────────────────────────────────────
    methods (Access = public)
        function r = runSelfTest(app)
            %runSelfTest Deterministic checks of the numerical core (throws on failure, returns the per-check report).
            [P, T] = meshgrid(0:30:330, 0:30:180); G = table(T(:), P(:), 10*cosd(T(:)/2).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            w = solidWeights(G.Theta, G.Phi); r.solidAngle = abs(sum(w) - 4*pi) < 1e-9;
            [k, pk] = calcOrientation(G.Theta, G.Phi, G.E_Total_dB, w, app.Axes, app.Pctl, app.Excess); r.orientation = k == 1 && isfinite(pk.value);
            [P2, T2] = meshgrid(0:2:358, 0:2:180); f = @(t, p) 12*cosd(t).^2 - 0.5*sind(p).^2;
            R = resampleCanonical(table(T2(:), P2(:), f(T2(:), P2(:)), 'VariableNames', {'Theta', 'Phi', 'Val'}), 1);
            nat = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0 & R.Phi < 360;
            r.resample = height(R) == 181*361 && max(abs(R.Val(nat) - f(R.Theta(nat), R.Phi(nat)))) < 1e-10;
            r.range = isequal(peakRange([3.2; -250; -17], app.Pctl, app.Excess), [-45 5]);
            spike = repmat(0.02, 1e5, 1); spike(1) = 10.02; pk = resolvePeak(spike, app.Pctl, app.Excess);
            r.spike = pk.adjusted && abs(pk.value - 0.02) < 1e-12 && pk.rawIndex == 1 && isequal(peakRange(spike, app.Pctl, app.Excess), [-45 5]);
            r.percentile = abs(pctile((1:100)', 50) - 50.5) < 1e-12 && abs(pctile((1:100)', 99.99) - 100) < 1e-12;
            r.hpbw = abs(calcHPBW((0:359)', 20*log10(max(abs(cosd((0:359)')), 1e-9)), 0, 0) - 90) < 0.5;
            r.arSemantics = all(arrayfun(@isAR, ["AR", "AR_dB", "AR dB", "Axial Ratio", "Axial_Ratio"])) && ~isAR("E_Total_dB");
            fp = [tempname '.ffd']; writelines(["0 180 3"; "-180 180 3"; compose("%d 0 0 1", (1:9)')], fp); c = onCleanup(@() delete(fp));
            d = readPattern(fp, 'ffd'); r.ffd = strcmp(d.meta.source, 'HFSS FFD') && isscalar(d.blocks) && height(d.blocks{1}) == 9;
            ok = structfun(@(x) logical(x), r); r.pass = all(ok);
            if ~r.pass, names = fieldnames(r); error('apat:test:SelfTestFailed', 'Self-test failed: %s', strjoin(names(~ok), ', ')); end
        end
    end
end

%% ═══════════════════════════════════════════ Local functions (pure) ═══════════════════════════════════════════
function h = place(h, row, col), h.Layout.Row = row; h.Layout.Column = col; end

function tf = isGenericText(fp), [~, ~, e] = fileparts(fp); tf = any(strcmpi(e, {'.csv', '.txt', '.dat'})); end

function tf = isKind(node, kind)
%isKind True when NODE is one tree node whose NodeData.kind equals KIND.
tf = isscalar(node) && isa(node, 'matlab.ui.container.TreeNode') && isstruct(node.NodeData) && strcmp(node.NodeData.kind, kind);
end

function s = fmt(v, n)
%fmt Compact number text: up to two decimals without trailing zeros (or exactly N decimals); 'n/a' when not finite.
if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); else, s = sprintf('%.*f', n, v); end
end

function writeTable(T, fp)
%writeTable TXT is tab-delimited; CSV/XLSX use writetable's native format.
if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
end

function setTips(h, rows)
%setTips Attach DataTip rows, tolerating objects whose template is materialized lazily.
try h.DataTipTemplate.DataTipRows = rows; catch, try delete(datatip(h, 'DataIndex', 1)); h.DataTipTemplate.DataTipRows = rows; catch, end, end
end

function [cols, labels] = compList(T)
%compList Component columns offered for display, with user-facing labels.
cols = string(T.Properties.VariableNames(3:end)); labels = cols; if T.Properties.UserData.isGainOnly, return; end
known = ["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "AR_dB", "Gain_PolCorrected_dB"];
names = ["Total Gain", "Etheta Gain", "Ephi Gain", "RHCP Gain", "LHCP Gain", "Axial Ratio", "Polarized Gain"];
keep = ismember(known, cols); cols = known(keep); labels = names(keep);
end

function c = pickComp(prev, cols)
%pickComp Keep the previous selection when still available, else Total Gain, else the first column.
c = cols(1); if any(cols == "E_Total_dB"), c = "E_Total_dB"; end, if any(cols == string(prev)), c = string(prev); end
end

function tf = isAR(name)
%isAR Axial-ratio semantics independent of the column spelling (AR, AR_dB, "Axial Ratio", ...).
key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', ''); tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
end

function tf = isGainDB(name)
%isGainDB Gain-like dB quantities, which are resampled in linear power.
key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', ''); tf = any(contains(key, ["gain", "directivity", "eirp"])) || endsWith(key, "db");
end

function g = totalGain(T)
%totalGain Total-gain column of a processed table (the first value column for gain-only sources).
if any(strcmp('E_Total_dB', T.Properties.VariableNames)), g = T.E_Total_dB; else, g = T{:, 3}; end
end

function r = clampRange(v, b)
%clampRange Sorted range clamped into B with a minimum width of 1.
v = sort(double(v(:).')); if numel(v) < 2 || any(~isfinite(v(1:2))), r = b; return; end
r = [max(b(1), v(1)), min(b(2), v(2))]; if diff(r) < 1, r(2) = min(b(2), r(1) + 1); r(1) = max(b(1), r(2) - 1); end
end

function t = axisTicks(lim, step)
%axisTicks Multiples of STEP inside LIM plus both limits (empty when degenerate or more than 60 ticks).
t = []; if ~isfinite(step) || step <= 0 || diff(lim) <= 0, return; end
t = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)]); if numel(t) > 60, t = []; end
end

%% ── Readers ─────────────────────────────────────────────────────────────────────────────────────────────────
function out = readPattern(fp, fmt, cached)
%readPattern Any supported source → struct(rawTbl, blocks, freqs, meta).  blocks{k} are canonical tables
%   {Theta,Phi,Re_Eth,Im_Eth,Re_Eph,Im_Eph} (or a gain table).  CACHED lets generic text be reinterpreted without re-reading.
if nargin < 3, cached = table(); end
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, 'meta', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false));
switch ext
    case {'XLSX', 'XLS'},                 out = readExcelMatrix(fp, out);
    case {'CSV', 'TXT', 'DAT'},           out = readGenericText(fp, string(fmt), cached, out);
    case 'CUT',                           out = readGraspCut(fp, out);
    case 'FFD',                           out = readHfssFfd(fp, out);
    case {'FZ', 'UAN', 'OUT', 'FFS', 'FFE'}, out = readColumnar(fp, ext, out);
    otherwise, error('readFile:unsupported', 'Unsupported format: %s', ext);
end
end

function E = magPhase(dB, deg), E = 10.^(dB/20).*exp(1i*deg2rad(deg)); end
function [Eth, Eph] = circToLin(Er, El), Eth = (Er + El)/sqrt(2); Eph = (Er - El)/(1i*sqrt(2)); end
function T = fieldTable(th, ph, Eth, Eph)
T = table(th(:), ph(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function [nHdr, ffd] = scanHeader(fp)
%scanHeader Count leading non-data lines (data = ≥4 numeric fields) and parse an HFSS FFD header when present
%   (two "start stop count" triples for θ and φ, then an optional "Frequencies f1 f2 ..." line).
NUM = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?'; fid = fopen(fp, 'r'); assert(fid > 0, 'apat:io:OpenFailed', 'Cannot open file: %s', fp);
c = onCleanup(@() fclose(fid)); ffd = struct('ok', false, 'theta', [], 'phi', [], 'freq', []); head = {}; at = []; nHdr = 0;
while true                                                            % stop at the first data line; remember non-empty header lines
    s = fgetl(fid); if ~ischar(s), break; end, nHdr = nHdr + 1; s = strtrim(s);
    if ~isempty(regexp(s, ['^' NUM '(?:[\s,;]+' NUM '){3,}$'], 'once')), nHdr = nHdr - 1; break; end
    if ~isempty(s), head{end+1} = s; at(end+1) = nHdr; end %#ok<AGROW>
end
if numel(head) >= 2
    t1 = sscanf(head{1}, '%f'); t2 = sscanf(head{2}, '%f');
    if numel(t1) == 3 && numel(t2) == 3 && t1(3) >= 1 && t2(3) >= 1   % FFD: only the triples (+ "Frequencies" line) are header;
        ffd = struct('ok', true, 'theta', linspace(t1(1), t1(2), round(t1(3))).', 'phi', linspace(t2(1), t2(2), round(t2(3))).', 'freq', []); nHdr = at(2);
        if numel(head) >= 3                                          % later "Frequency f" separators stay in the data section
            tok = regexp(head{3}, '^frequenc(?:y|ies)\s+(.+)$', 'tokens', 'once', 'ignorecase');
            if ~isempty(tok), nHdr = at(3); fv = sscanf(tok{1}, '%f'); if numel(fv) > 1, ffd.freq = fv(:); end, end
        end
    end
end
end

function M = readNumeric(fp, nHdr)
%readNumeric Delimited numeric matrix after NHDR header lines; blank rows dropped.
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = readmatrix(fp, setvartype(opts, 'double')); M = M(~all(isnan(M), 2), :);
end

function out = readColumnar(fp, ext, out)
%readColumnar Six-column far-field text files: XGTD UAN/FZ (dB, deg), GRASP OUT (RHCP/LHCP re/im), CST FFS, FEKO FFE.
M = readNumeric(fp, scanHeader(fp)); assert(size(M, 2) >= 6, 'readFile:columns', '%s files need six numeric columns.', ext); M = M(:, 1:6);
switch ext
    case {'FZ', 'UAN'}, names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}; ij = [1 2]; src = ['XGTD ' ext]; Eth = magPhase(M(:, 3), M(:, 5)); Eph = magPhase(M(:, 4), M(:, 6));
    case 'OUT',         names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; ij = [1 2]; src = 'TICRA/GRASP OUT'; [Eth, Eph] = circToLin(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)));
    case 'FFS',         names = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; ij = [2 1]; src = 'CST FFS'; Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
    otherwise,          names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; ij = [1 2]; src = 'FEKO FFE'; Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
end
out.meta.source = src; out.rawTbl = array2table(M, 'VariableNames', names); out.blocks = {fieldTable(M(:, ij(1)), M(:, ij(2)), Eth, Eph)};
end

function out = readHfssFfd(fp, out)
%readHfssFfd HFSS far-field: header grid + [Re Eθ, Im Eθ, Re Eφ, Im Eφ] rows, one block per frequency ("Frequency f" separators).
[nHdr, ffd] = scanHeader(fp); assert(ffd.ok, 'readFile:ffd', 'FFD header (theta/phi ranges) not found.');
M = readNumeric(fp, nHdr); sep = isnan(M(:, 1)); fs = M(sep, min(2, end)); f = [ffd.freq(:); fs(~isnan(fs))].';
th = repelem(ffd.theta, numel(ffd.phi)); ph = repmat(ffd.phi, numel(ffd.theta), 1); n = numel(th); F = M(~sep, 1:4);
assert(mod(size(F, 1), n) == 0, 'readFile:ffd', 'FFD row count does not match the theta/phi grid.'); nb = size(F, 1)/n; f(end+1:nb) = NaN; f = f(1:nb);
blk = @(k) fieldTable(th, ph, complex(F((k-1)*n + (1:n), 1), F((k-1)*n + (1:n), 2)), complex(F((k-1)*n + (1:n), 3), F((k-1)*n + (1:n), 4)));
out.blocks = arrayfun(blk, 1:nb, 'UniformOutput', false); out.freqs = f; out.rawTbl = out.blocks{1};
out.meta.source = 'HFSS FFD'; out.meta.isDep = nb > 1 || any(isfinite(f));
end

function out = readGraspCut(fp, out)
%readGraspCut TICRA/GRASP .cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks, one φ per block.
L = readlines(fp); L(strlength(strtrim(L)) == 0) = []; th = {}; ph = {}; D = {}; i = 1; icomp = 1; icut = 1;
while i < numel(L)
    p = sscanf(L(i+1), '%f'); assert(numel(p) >= 7, 'readFile:cut', 'Could not parse cut parameter line.'); n = p(3); icomp = p(5); icut = p(6);
    D{end+1, 1} = reshape(sscanf(strjoin(L(i+2:i+1+n), ' '), '%f'), 2*p(7), []).'; %#ok<AGROW>
    th{end+1, 1} = p(1) + (0:n-1)'*p(2); ph{end+1, 1} = repmat(p(4), n, 1); i = i + 2 + n; %#ok<AGROW>
end
th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:}); D = D(:, 1:4);
if icut == 2, [th, ph] = deal(ph, th); end                                   % ICUT=2: φ swept, θ constant
neg = th < 0; ph(neg) = ph(neg) + 180; th(neg) = -th(neg);                   % fold negative θ onto the opposite φ
if isscalar(unique(ph)), m = numel(th); th = repmat(th, 36, 1); ph = repelem((0:10:350)', m); D = repmat(D, 36, 1); end   % single cut → body of revolution
if icomp == 2, names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; [Eth, Eph] = circToLin(complex(D(:, 1), D(:, 2)), complex(D(:, 3), D(:, 4)));
else, names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; Eth = complex(D(:, 1), D(:, 2)); Eph = complex(D(:, 3), D(:, 4)); end
out.meta.source = 'TICRA/GRASP CUT'; out.rawTbl = array2table([th ph D], 'VariableNames', [{'Theta', 'Phi'}, names]); out.blocks = {fieldTable(th, ph, Eth, Eph)};
end

function out = readGenericText(fp, fmt, T, out)
%readGenericText CSV/TXT/DAT: coverage-results table, gain-only pattern, or six-column E-field table according to FMT.
if isempty(T)
    opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve'; T = rmmissing(readtable(fp, opts));
end
nc = width(T); assert(nc >= 2 && ~isempty(T), 'readFile:InvalidFormat', 'File needs at least two numeric columns.');
names = lower(string(T.Properties.VariableNames)); hasHdr = ~all(startsWith(names, "var")); c1 = T{:, 1}; c2 = T{:, 2}; raw = T;
covHdr = contains(names(1), "threshold") || any(contains(names(2:end), "coverage"));
if (fmt == "gain" || nc < 6 || covHdr) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')     % coverage results
    if ~hasHdr, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:nc-1))]; end
    out.rawTbl = T; out.meta.isCoverage = true; return
end
if fmt == "gain"                                                              % gain-only: the wider-spanning column is φ
    assert(nc >= 3, 'readFile:GainColumns', 'A gain pattern needs theta, phi and at least one value column.');
    if range(c1) > range(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    T = movevars(T, 'Theta', 'Before', 1); if ~hasHdr, raw = T; end
    out.rawTbl = raw; out.blocks = {T}; out.meta.isGainOnly = true; return
end
assert(nc >= 6, 'readFile:TextEFieldColumns', 'The selected generic E-field format requires six numeric columns.');
V = T{:, 3:6}; mp = endsWith(fmt, "magphase"); layout = "n/a";
if mp                                                                         % interleaved (mag,phase,mag,phase) vs grouped
    big = max(abs(V), [], 1, 'omitnan') > 100;
    if big(2) && ~big(3), mc = [1 3]; pc = [2 4]; layout = "interleaved"; else, mc = [1 2]; pc = [3 4]; layout = "grouped"; end
    A = magPhase(V(:, mc(1)), V(:, pc(1))); B = magPhase(V(:, mc(2)), V(:, pc(2)));
else
    A = complex(V(:, 1), V(:, 2)); B = complex(V(:, 3), V(:, 4));
end
if startsWith(fmt, "linear"), [Eth, Eph] = deal(A, B); comp = ["E_TH", "E_PH"]; rect = ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"];
else, if startsWith(fmt, "lcp"), [A, B] = deal(B, A); end, [Eth, Eph] = circToLin(A, B); comp = ["POL1", "POL2"]; rect = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"]; end
if mp, gen = [comp + "_dB", comp + "_deg"]; if layout == "interleaved", gen = gen([1 3 2 4]); end, else, gen = rect; end
if ~hasHdr, T.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", gen]); end
out.meta.source = sprintf('Generic text (%s, %s)', fmt, layout); out.rawTbl = T; out.blocks = {fieldTable(c1, c2, Eth, Eph)};
end

function out = readExcelMatrix(fp, out)
%readExcelMatrix Excel matrix workbooks: sheet 1 = summary; fixed component sheets hold C3-origin dBi / degree matrices.
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"]; lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'readFile:ExcelMatrixFormat', 'Unsupported Excel workbook: expected Etheta/Ephi and/or RHCP/LHCP component sheets after the summary sheet.');
req = [circ(1:4*hasC), lin(1:4*hasL)]; M = struct();
for k = 1:numel(req)
    [th, ph, D] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, req(k)), 1)));
    if k == 1, [th0, ph0] = deal(th, ph); else, assert(isequal(size(D), [numel(th0) numel(ph0)]) && max(abs(th - th0)) < 1e-9 && max(abs(ph - ph0)) < 1e-9, 'readFile:ExcelMatrixGrid', 'All component sheets must share one theta/phi grid.'); end
    M.(char(req(k))) = D;
end
if hasL, Eth = magPhase(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = magPhase(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees); code = 1 + 2*hasC;
else, [Eth, Eph] = circToLin(magPhase(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), magPhase(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees)); code = 2; end
[TH, PH] = ndgrid(th0, ph0); raw = fieldTable(TH, PH, Eth, Eph); for k = 1:numel(req), raw.(char(req(k))) = reshape(M.(char(req(k))), [], 1); end
kinds = {'Eth/Eph', 'Ercp/Elcp', 'Ercp/Elcp + Eth/Eph'}; meta = readSummary(fp, sheets(1));
meta.source = sprintf('Excel Matrix Format %d (%s)', code, kinds{code}); meta.isGainOnly = false; meta.isCoverage = false; meta.isDep = false;
out.rawTbl = raw; out.blocks = {raw(:, 1:6)}; out.meta = meta;
end

function [th, ph, D] = readMatrixSheet(fp, sheet)
%readMatrixSheet One C3-origin matrix: row 2 (C→) = φ, column B (3↓) = θ.  readcell keeps the worksheet coordinates intact.
C = readcell(fp, 'Sheet', char(sheet)); assert(all(size(C) >= 3), 'readFile:ExcelMatrixSheet', 'Sheet "%s" has no C3-origin matrix.', sheet);
isnum = @(c) cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), c); pm = isnum(C(2, 3:end)); tm = isnum(C(3:end, 2));
np = find(~pm, 1) - 1; if isempty(np), np = numel(pm); end, nt = find(~tm, 1) - 1; if isempty(nt), nt = numel(tm); end
assert(nt > 0 && np > 0 && ~any(pm(np+1:end)) && ~any(tm(nt+1:end)), 'readFile:ExcelMatrixAxis', 'Sheet "%s" has a missing or gapped theta/phi axis.', sheet);
ph = cell2mat(C(2, 3:2+np)); ph = ph(:); th = cell2mat(C(3:2+nt, 2)); th = th(:); D = C(3:2+nt, 3:2+np);
assert(all(isnum(D), 'all'), 'readFile:ExcelMatrixSheet', 'Sheet "%s" contains non-numeric or missing samples.', sheet); D = cell2mat(D);
assert(all(diff(th) > 0) && all(diff(ph) > 0) && th(1) >= -1e-9 && th(end) <= 180 + 1e-9 && ph(1) >= -1e-9 && ph(end) < 360 + 1e-9, ...
    'readFile:ExcelMatrixAxis', 'Sheet "%s" axes must be strictly increasing with theta in [0,180] and phi in [0,360).', sheet);
end

function meta = readSummary(fp, sheet)
%readSummary Capture the template summary sheet as metadata: label in column B → first value in C..E, keyed by a valid name.
meta = struct(); try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
blank = @(x) isempty(x) || isa(x, 'missing') || (isnumeric(x) && all(isnan(x(:))));
for r = 1:size(C, 1)
    lbl = C{r, 2}; if ~(ischar(lbl) || isstring(lbl)) || strlength(strtrim(string(lbl))) == 0, continue; end
    v = C(r, 3:min(end, 5)); v = v(~cellfun(blank, v)); if isempty(v), continue; end
    meta.(matlab.lang.makeValidName(lower(regexprep(char(lbl), '[^a-zA-Z0-9]+', '_')))) = v{1};
end
end

%% ── Math ────────────────────────────────────────────────────────────────────────────────────────────────────
function T = normalizePattern(T)
%normalizePattern Canonical sphere: θ∈[0,180], φ∈[0,360) plus one closing φ=360 copy; 5-decimal rounding; duplicates removed.
th = T.Theta;
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, T.Theta = 90 - th;                                     % elevation source
    else, m = th < 0; T.Theta(m) = -th(m); T.Phi(m) = T.Phi(m) + 180; end                      % negative θ → opposite φ
end
num = varfun(@isnumeric, T, 'OutputFormat', 'uniform'); T{:, num} = round(T{:, num}, 5);
T.Theta = mod(T.Theta, 360); over = T.Theta > 180; T.Theta(over) = 360 - T.Theta(over); T.Phi(over) = T.Phi(over) + 180;
T.Phi = mod(T.Phi, 360); T.Theta(abs(T.Theta) < 1e-12) = 0; T.Phi(abs(T.Phi) < 1e-12) = 0;
[~, i] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(i, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function R = resampleCanonical(S, step)
%resampleCanonical Resample primitive columns (Re/Im fields, or gain in linear power) onto a STEP° canonical grid.
%   Complete rectangular sources use interp2 with periodic φ closure; irregular sources use scatteredInterpolant.
keep = isfinite(S.Theta) & isfinite(S.Phi) & S.Theta >= -1e-9 & S.Theta <= 180 + 1e-9 & abs(S.Phi - 360) > 1e-9; S = S(keep, :);
[~, u] = unique([S.Theta mod(S.Phi, 360)], 'rows', 'stable'); S = S(u, :); th = S.Theta; ph = mod(S.Phi, 360);
[PQ, TQ] = meshgrid(unique([(0:step:360)'; 360]), (0:step:180)'); R = table(TQ(:), PQ(:), 'VariableNames', {'Theta', 'Phi'}); R.Properties.UserData = S.Properties.UserData;
ts = unique(th); ps = unique(ph); regular = numel(ts)*numel(ps) == numel(th);
if regular, [~, i] = ismember(th, ts); [~, j] = ismember(ph, ps); idx = sub2ind([numel(ts) numel(ps)], i, j); regular = numel(unique(idx)) == numel(idx); end
names = S.Properties.VariableNames(3:end); primitive = all(ismember({'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}, names));
for k = 1:numel(names)
    v = double(S.(names{k})); lin = ~primitive && isGainDB(names{k}); if lin, v = 10.^(v/10); end
    if regular
        G = nan(numel(ts), numel(ps)); G(idx) = v; [P, T] = meshgrid(ps, ts);
        if ps(end) < ps(1) + 360 - 1e-9, P(:, end+1) = P(:, 1) + 360; T(:, end+1) = T(:, 1); G(:, end+1) = G(:, 1); end     % periodic φ closure
        q = interp2(P, T, G, PQ, TQ, 'linear', NaN); miss = ~isfinite(q);
        if any(miss(:)), n = interp2(P, T, G, PQ, TQ, 'nearest', NaN); q(miss) = n(miss); end
    else
        F = scatteredInterpolant(ph, th, v, 'linear', 'nearest'); q = F(PQ, TQ);
    end
    if lin, q = 10*log10(max(q, realmin)); end
    R.(names{k}) = q(:);
end
end

function [T, info] = calcPattern(S, p)
%calcPattern Canonical fields (or a gain table) → processed pattern table.  INFO carries the polarization summary.
info = struct('label', 'n/a', 'Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]); meta = S.Properties.UserData;
if meta.isGainOnly, T = S; if width(T) > 2, T{:, 3:end} = T{:, 3:end} + p.GainLoss_dB; end, return; end
Eth = complex(S.Re_Eth, S.Im_Eth)*p.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph)*p.FieldScale; Er = (Eth + 1i*Eph)/sqrt(2); El = (Eth - 1i*Eph)/sqrt(2);
[mt, mp, mr, ml] = deal(abs(Eth), abs(Eph), abs(Er), abs(El)); G = 10*log10(max(mt.^2 + mp.^2, eps));
% Dominant polarization from mean component power → co/cross ordering and label
Pw = [mean(mt.^2, 'omitnan'), mean(mp.^2, 'omitnan'), mean(mr.^2, 'omitnan'), mean(ml.^2, 'omitnan')];
if Pw(2) > Pw(1), info.Linear = fliplr(info.Linear); end, if Pw(4) > Pw(3), info.Circular = fliplr(info.Circular); end
if max(Pw(3:4)) > max(Pw(1:2)), info.label = sprintf('Circular (%s)', replace(info.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif Pw(1) >= Pw(2), info.label = 'Linear (Vertical)'; else, info.label = 'Linear (Horizontal)'; end
% Signed axial ratio (+ right-hand, − left-hand); equal circular components are the linear limit → −100 dB floor
d = mr - ml; sense = sign(d); sense(~isfinite(d)) = 0; AR = (mr + ml)./max(abs(d), eps);
ARdB = min(20*log10(AR), 250).*sense; ARdB(isfinite(d) & abs(d) <= eps*max(mr + ml, 1)) = -100;
% Polarization loss factor against the incident wave (Auto = the pattern's dominant hand)
switch char(p.RxMode), case 'RHCP', ws = 1; case 'LHCP', ws = -1; otherwise, ws = 2*(info.Circular(1) == "E_RCP") - 1; end
ra = AR.*sense; ra(sense == 0) = 1e12; rw = ws*10^(p.RxAR_dB/20);
PLF = 10*log10(min(max(0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1))./(2*(ra.^2 + 1)*(rw^2 + 1)), eps), 1));
eirp = p.Pt_dBW + G; W = 10.^(eirp/10); dB20 = @(m) 20*log10(max(m, eps)); ang = @(E) rad2deg(angle(E));
T = table(S.Theta, S.Phi, G, ARdB, dB20(mr), dB20(ml), PLF, G + PLF, dB20(mt), dB20(mp), ang(Eth), ang(Eph), ang(Er), ang(El), eirp, W/(4*pi*p.R_m^2), sqrt(30*W)/p.R_m, ...
    'VariableNames', {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', 'PLF_dB', 'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', ...
    'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
T.Properties.UserData = meta;
end

function q = pctile(x, p)
%pctile Percentile with MATLAB's prctile convention ((i−0.5)/n plotting positions) — no toolbox required.
x = sort(x(:)); n = numel(x); r = min(max(p/100*n + 0.5, 1), n); i = floor(r); q = x(i) + (r - i)*(x(min(i + 1, n)) - x(i));
end

function pk = resolvePeak(v, pctl, excess)
%resolvePeak Peak policy: accept the raw maximum unless it exceeds the P(pctl) level by more than EXCESS dB; then the
%   highest sample at or below that level is the effective peak and the samples above it are flagged as outliers.
pk = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlier', false(size(v)), 'adjusted', false);
f = isfinite(v); if ~any(f), return; end
[pk.rawValue, pk.rawIndex] = max(v, [], 'omitnan'); pk.value = pk.rawValue; pk.index = pk.rawIndex; lvl = pctile(v(f), pctl);
if pk.rawValue > lvl + excess
    out = f & v > lvl; c = v; c(~f | out) = -Inf;
    if any(f & ~out), [pk.value, pk.index] = max(c); pk.outlier = out; pk.adjusted = true; end
end
end

function b = peakRange(v, pctl, excess)
%peakRange 50-dB display window ending at the effective peak rounded up to 5 dB (kept inside [−250, 100]).
pk = resolvePeak(double(v(:)), pctl, excess); hi = 0;
if isfinite(pk.value), hi = min(max(ceil(pk.value/5)*5, -200), 100); end, b = [hi - 50, hi];
end

function w = solidWeights(th, ph)
%solidWeights Exact solid angle of each uniform θ×φ cell (sr); the duplicated closing-seam column gets zero weight.
dt = gridStep(th); dp = gridStep(mod(ph, 360)); if ~isfinite(dt), dt = 180; end, if ~isfinite(dp), dp = 360; end
w = (cosd(max(th - dt/2, 0)) - cosd(min(th + dt/2, 180)))*deg2rad(dp);
seam = 360; if any(ph < 0), seam = 180; end, w(abs(ph - seam) < 1e-9) = 0;
end

function s = gridStep(v)
%gridStep Smallest positive spacing between distinct finite values (NaN when undefined).
d = diff(unique(v(isfinite(v)))); d = d(d > 1e-9); s = NaN; if ~isempty(d), s = min(d); end
end

function [idx, pk] = calcOrientation(th, ph, g, w, A, pctl, excess)
%calcOrientation Principal axis whose 45° cone captures the most peak-normalised radiated energy (outlier spikes excluded).
pk = resolvePeak(g, pctl, excess); g(pk.outlier) = NaN; e = 10.^((g - pk.value)/10).*w; e(~isfinite(e)) = 0;
V = [sind(th).*cosd(ph), sind(th).*sind(ph), cosd(th)]; [~, idx] = max(e.'*double(V*A.vec.' >= cosd(45)));
end

function c = cutRows(th, ph, type, val)
%cutRows One great-circle cut on physical angles.  "Phi": fixed θ, sweep φ (0..360).  "Theta": fixed φ, sweep θ over the
%   pole and back down the opposite φ (0..360).  Returns rows, sweep angle, snapped fixed value, symbol and snap flag.
ph = mod(ph, 360);
if type == "Phi"
    tv = unique(th); [d, i] = min(abs(tv - val)); c.fixed = tv(i); rows = find(abs(th - c.fixed) < 1e-9);
    [c.ang, o] = sort(ph(rows)); c.rows = rows(o); c.sym = 'θ';
else
    pv = unique(ph); [d, i] = min(abs(mod(pv - val + 180, 360) - 180)); c.fixed = pv(i); [~, j] = min(abs(mod(pv - c.fixed, 360) - 180));
    a = find(abs(ph - c.fixed) < 1e-9); b = find(abs(ph - pv(j)) < 1e-9 & abs(th - 180) > 1e-9);
    [~, oa] = sort(th(a)); [~, ob] = sort(th(b), 'descend'); a = a(oa); b = b(ob); c.rows = [a; b]; c.ang = [th(a); 360 - th(b)]; c.sym = 'φ';
end
c.snap = d > 0;
end

function [bw, lo, hi] = calcHPBW(ang, g, pk, pkAng)
%calcHPBW −3 dB beamwidth around the peak of one circular cut (wrap-aware, linear interpolation of the crossings).
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(g); ang = ang(ok); g = g(ok); if numel(g) < 3, return; end
if nargin < 3, [pk, i] = max(g); pkAng = ang(i); end
[ra, o] = sort(mod(ang - pkAng + 180, 360) - 180); rg = g(o); h = pk - 3;
L = find(ra < 0 & rg <= h, 1, 'last'); Rr = find(ra > 0 & rg <= h, 1, 'first');
if isempty(L) || isempty(Rr) || L + 1 > numel(rg) || Rr < 2 || rg(L+1) == rg(L) || rg(Rr-1) == rg(Rr), return; end
x = @(i, j) ra(i) + (ra(j) - ra(i))*(h - rg(i))/(rg(j) - rg(i));                % crossing between outside sample i and inside sample j
lo = pkAng + x(L, L+1); hi = pkAng + x(Rr, Rr-1); bw = hi - lo;
end

function m = calcMetrics(T, th, ph, g, pk, w, A, k)
%calcMetrics Scalar figures of merit from the total gain on physical angles, for boresight axis K.
i = pk.index; g2 = g; g2(pk.outlier) = NaN; U = sum(10.^(g2/10).*w, 'omitnan');                       % ∫G dΩ (linear)
D = 10*log10(max(4*pi*10^(pk.value/10)/max(U, eps), eps)); eff = 100*U/(4*pi); if eff < 0 || eff > 100, eff = NaN; end
[~, back] = min(cosd(th)*cosd(th(i)) + sind(th)*sind(th(i)).*cosd(ph - ph(i)));
AR = NaN; if any(strcmp('AR_dB', T.Properties.VariableNames)), AR = T.AR_dB(i); end
ec = cutRows(th, ph, "Theta", A.phi(k));                                                             % E-plane through the axis' φ
if A.theta(k) == 90, hc = cutRows(th, ph, "Phi", 90); else, hc = cutRows(th, ph, "Theta", 90); end   % H-plane: orthogonal plane
m = struct('PeakGain_dB', pk.value, 'PeakTheta_deg', th(i), 'PeakPhi_deg', mod(ph(i), 360), 'PeakAdjusted', pk.adjusted, ...
    'HPBW_EPlane_deg', calcHPBW(ec.ang, g(ec.rows)), 'HPBW_HPlane_deg', calcHPBW(hc.ang, g(hc.rows)), 'FrontBack_dB', pk.value - g(back), ...
    'PeakDirectivity_dB', D, 'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', AR);
end

function c = coverageCCDF(g, mask, thr, w)
%coverageCCDF Coverage(T) [%] = 100·Σ I(G_i > T)·Ω_i / Σ Ω_i over the masked region, evaluated for every threshold at once.
ok = mask(:) & isfinite(g(:)) & isfinite(w(:)) & w(:) >= 0; g = g(ok); w = w(ok); c = zeros(numel(thr), 1);
if ~isempty(g) && sum(w) > 0, c = 100*(w.'*(g > thr(:).')).'/sum(w); end
end

function x = thrAt(thr, cov, q)
%thrAt Threshold at which a (non-increasing) coverage curve crosses Q percent (NaN when outside the curve).
[c, k] = unique(cov(:), 'last'); x = NaN; if numel(c) > 1, x = interp1(c, thr(k), q, 'linear', NaN); end
end