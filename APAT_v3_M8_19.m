classdef APAT_v3_M8_19 < matlab.apps.AppBase %1917-lines %ISSUES: %1. Edge POB DataTip positioning NOT OK (Hidden) %2. Customized Interactive DataTip NOT-OK ON Contour Plot & Fisheye Plot (shows default X_Y_Z/Theta_R_Z) %3. When loading new pattern while the older/current POB DataTip is active/enabled, it shows the old POB instead of the new one (the old POB DataTip shouldn't show after loading a new pattern)! %4. Coverage Threshold Query snaps to nearest Data Point instead of returning requested/query point! %Context menu shows warning: "Warning: You cannot set 'ContextMenu' property of DataTip."
% APAT v3 M8 — Antenna Pattern Analyzer Tool (single-file App Designer class).
%
% Data flow (one direction; every stage has exactly one authoritative table):
%
%   file ──readPattern──▶ src{raw, blocks, freqs, meta}
%        ──normalizePattern──▶ srcTbl        canonical θ∈[0,180], φ∈[0,360] (closing φ=360 copy)
%        ──[resampleTo1Deg]──calcPattern──▶ patTbl   PHYSICAL frame: all physics lives here
%        ──displayFrame──▶ dispTbl          selected φ/θ spans: tables, export, plot grids
%
%   • Peak of beam, boresight, metrics, cuts and coverage are evaluated on patTbl only.
%   • Display conventions (signed φ, elevation θ) are applied exactly once, in displayFrame(),
%     and converted back nowhere.  UI controls never carry hidden state in UserData.
%   • Annotations (POB / HPBW markers + pinned DataTips) are ordinary tagged graphics that are
%     re-created by the renderer that owns them; visibility is a one-pass tag sweep.

    properties (GetAccess = public, SetAccess = private)
        isClosing logical = false
    end

    properties (Access = public)   % ---- UI handles (App Designer style names kept from M7)
        UIFigure
        TabGroup
        Tab1_Single
        Tab2_Coverage
        Single_StatusBar
        Cov_StatusBar
        Single_EditField_Path
        Single_Button_Load
        Single_Button_Process
        Single_Button_Coverage
        Single_Export_Output
        Single_Export_UAN
        Single_Button_ResetParams
        TextFormatLabel
        Single_DropDown_TextFormat
        FFDFreqDropDownLabel
        Single_DropDown_FFD
        Single_DropDown_step
        RxPolLabel
        Single_DropDown_RxPol
        RwLabel
        Single_Spinner_Rw
        LossLabel
        Single_Spinner_Loss
        PtLabel
        Single_Spinner_Pt
        Single_DropDown_Pt
        DistanceLabel
        Single_Spinner_R
        Single_DropDown_R
        Single_Panel_plotControl
        Single_DropDown_Component
        Single_DropDown_cutType
        Single_DropDown_cutValue
        CutFieldBasisDropDown
        Single_Plot_Cmax
        Single_Plot_Cmin
        Single_Plot_Cstep
        Single_DropDown_3DView
        Single_Switch_AngularSpan
        Single_Switch_ThetaSpan
        Single_Switch_EHplane
        Single_CheckBox_overlayCut
        Single_CheckBox_POB
        Single_CheckBox_HPBWBounds
        Single_tabData
        Single_DropDown_output
        Single_Table_DataOut
        Single_Table_DataIn
        Single_Table_metadata
        Single_Panel_Rect
        Single_tabCut
        Single_tabPolarPlot
        Single_tabRectPlot
        Single_paxCut
        Single_AxesRect
        Range_Cut
        Range_Cut_Min
        Range_Cut_Max
        Button_HPBW
        Label_HPBW
        Button_ExportCut
        Single_gridEcut
        CheckBox_Et
        CheckBox_Er
        CheckBox_El
        Single_Panel_fullPattern
        Single_tabPlots
        Single_Axes_Ctr
        Single_paxPattern
        Single_Axes_3dSph
        Single_Axes_3dPol
        Single_Axes_3dRect
        Full                      % struct array: one record per full-pattern tab {name,tab,axes,range,minSp,maxSp,render}
        Cov_Panel_Param
        Cov_gridPanel_Parm
        Cov_ButtonGroup_CovType
        Cov_Btn_Spherical
        Cov_Btn_Conical
        Cov_DropDown_Orientation
        Cov_DropDown_OrientationLabel
        Cov_DropDown_Component
        Cov_DropDown_ComponentLabel
        AntennaPatternLabel
        Cov_EditField_filePath
        Cov_Button_Load
        Cov_Button_computeCov
        Cov_Spinner_ThreshMin
        Cov_Spinner_ThreshMax
        Cov_Spinner_Step
        Cov_Button_Reset
        Cov_Button_Export
        Cov_Spinner_ConeTH
        Cov_Spinner_ConePH
        Cov_Spinner_ConeAng
        Cov_ConeControls
        Cov_Button_Clear
        Cov_Button_toMain
        Cov_Spinner_queryCov
        Cov_Button_queryCov
        Cov_Spinner_queryThresh
        Cov_Button_queryThresh
        Cov_QueryControls
        Cov_TextFormatLabel
        Cov_DropDown_TextFormat
        Cov_Panel_Results
        Cov_Tree
        Cov_TreeNode_Results
        Cov_Axes
        Cov_Spinner_XMin
        Cov_Spinner_XRange
        Cov_Spinner_XMax
        Cov_Table
    end

    properties (Access = private)  % ---- application state
        fileName char = ''
        filePath char = ''
        folderPath char = ''
        baseName char = ''
        raw table                  % source table exactly as read (Input tab)
        blocks cell = {}           % one canonical source table per frequency block
        freqs double = NaN         % block frequencies (Hz)
        meta struct                % source metadata {source,isGainOnly,isCoverage,isDep,...}
        srcTbl table               % canonical source of the selected block
        patTbl table               % processed pattern, physical frame
        dispTbl table              % processed pattern, display frame
        solid double = []          % solid-angle weight of every patTbl row
        patRev double = 0          % increments whenever patTbl changes (coverage cache key)
        grid struct = struct()     % lazily built display grid + component matrices
        rawShown logical = false
        step double = 1
        POB double = NaN
        POBth double = NaN
        POBph double = NaN
        peakInfo struct = struct()
        polLabel char = 'n/a'
        polPairs struct = struct('Linear', ["E_TH","E_PH"], 'Circular', ["E_RCP","E_LCP"])
        boresightIndex double = 1
        metrics struct = struct()
        defaults struct = struct()
        autoCutBasis logical = true   % pick the co/cross basis from the detected polarisation on next process
        keepOneDegree logical = false % keep the 1° step selection across a re-process
        outMask logical = logical([]) % visible Results columns (columns 3..end)
        cutLim double = [-40 10]
        ctrLim double = [-40 10]
        gainLim double = [-40 10]     % authoritative non-AR colour scale, preserved across components
        covRunID double = 0
        covPresetKey char = ''
        covThreshInit logical = false
        covPlotInit logical = false
        opDialog = []
        statusTimer = []
        PlotMenu
        perf = @(~) []
    end

    properties (Constant, Access = private)
        PrincipalAxes = struct('labels', {{'+Z','-Z','+X','-X','+Y','-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        HiddenOutputColumns = {'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'}
        PeakPercentile = 99.99
        PeakMaxExcessDB = 6
        DistanceFloorM = 1e-12
        ReleaseName = 'APAT v3 Milestone 8'
        ReleaseVersion = '3.0-M8'
    end

    %% ================================================================ lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_19
            createComponents(app); registerApp(app, app.UIFigure); runStartupFcn(app, @startupFcn);
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true;
            t = app.statusTimer; if ~isempty(t) && isvalid(t), stop(t); delete(t); end
            d = app.opDialog; if ~isempty(d) && isvalid(d), delete(d); end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end
    end

    methods (Access = private)
        function startupFcn(app)
            app.statusTimer = timer('StartDelay', 3, 'ExecutionMode', 'singleShot', 'TimerFcn', @(t, ~) app.restoreStatus(t));
            app.PlotMenu = uicontextmenu(app.UIFigure);
            app.PlotMenu.ContextMenuOpeningFcn = @(src, ~) set(src, 'UserData', app.UIFigure.CurrentObject);
            uimenu(app.PlotMenu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ~) app.deleteUserTips(app.PlotMenu.UserData));

            for ax = [app.Single_Axes_Ctr, app.Single_AxesRect], enableDefaultInteractivity(ax); ax.Interactions = [zoomInteraction, dataTipInteraction]; end
            for ax = [app.Single_Axes_3dSph, app.Single_Axes_3dPol, app.Single_Axes_3dRect], enableDefaultInteractivity(ax); ax.Interactions = [rotateInteraction, dataTipInteraction]; end
            for ax = [app.Single_paxPattern, app.Single_paxCut], enableDefaultInteractivity(ax); end
            app.defaults = struct('Loss', app.Single_Spinner_Loss.Value, 'RxPol', app.Single_DropDown_RxPol.Value, 'Rw', app.Single_Spinner_Rw.Value, ...
                'Pt', app.Single_Spinner_Pt.Value, 'PtUnit', app.Single_DropDown_Pt.Value, 'R', app.Single_Spinner_R.Value, 'RUnit', app.Single_DropDown_R.Value);
            set([app.Single_StatusBar, app.Cov_StatusBar], 'UserData', 'Ready -- load an antenna pattern file to begin 🚀');
            app.setCoverageUI();
        end
    end

    %% ================================================================ source loading
    methods (Access = private)
        function onLoad(app)
            fp = strtrim(app.Single_EditField_Path.Value);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.filePath)
                fp = app.browse('Select an antenna pattern file'); if isempty(fp), return; end
            end
            app.Single_EditField_Path.Value = fp;
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Loading Data', 'Message', 'Reading file...', 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            app.opDialog = dlg; cleaner = onCleanup(@() delete(dlg)); drawnow
            done = app.startPerf("Load pattern");
            try
                src = app.readSource(fp, app.TextFormatLabel, app.Single_DropDown_TextFormat); app.perf("Read file"); app.checkCancelled();
                if src.meta.isCoverage                     % coverage-results files are routed to the Coverage tab; Main state is untouched
                    app.Single_EditField_Path.Value = app.filePath;
                    app.TabGroup.SelectedTab = app.Tab2_Coverage; app.Cov_EditField_filePath.Value = fp;
                    app.covLoadResults(fp, src.raw);
                else
                    [app.folderPath, app.baseName, ext] = fileparts(fp); app.filePath = fp; app.fileName = [app.baseName ext];
                    app.activateSource(src);
                    if src.meta.isDep
                        items = cellstr(compose('Pattern %d: %.4g GHz', [(1:numel(src.blocks))', src.freqs(:)/1e9]));
                        miss = isnan(src.freqs(:)); items(miss) = cellstr(compose('Pattern %d', find(miss)));
                        set(app.Single_DropDown_FFD, 'Items', items, 'Value', items{1});
                    end
                    set([app.Single_DropDown_FFD, app.FFDFreqDropDownLabel], 'Visible', src.meta.isDep, 'Enable', src.meta.isDep);
                    app.keepOneDegree = false; app.autoCutBasis = true;
                    app.refresh();
                end
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.setStatus(app.Single_StatusBar, 'Loading cancelled by user.', true);
                else, app.showError(ME, 'Loading Error'); end
            end
            done();
        end

        function src = readSource(app, fp, label, dropdown)
            % Generic text files expose the format selector (after an automatic coverage/gain probe); other formats are self-describing.
            generic = isGenericText(fp);
            if generic, fmt = "gain"; else, fmt = string(dropdown.Value); end
            src = readPattern(fp, fmt);
            show = generic && ~src.meta.isCoverage;
            if show, dropdown.Value = 'gain'; end
            set([label, dropdown], 'Visible', show);
            if ~isempty(app.opDialog) && isvalid(app.opDialog), app.opDialog.Message = 'Processing...'; end
        end

        function activateSource(app, src)
            [app.raw, app.blocks, app.freqs, app.meta] = deal(src.raw, src.blocks, src.freqs, src.meta);
            app.rawShown = false; app.selectBlock(1);
        end

        function selectBlock(app, k)
            if app.meta.isDep, app.raw = app.blocks{k}; app.rawShown = false; end
            app.srcTbl = normalizePattern(app.blocks{k}); app.srcTbl.Properties.UserData = app.meta;
        end

        function P = buildPattern(app, src)
            % Auxiliary pattern (Coverage tab) built with the current parameters, without touching Main state.
            S = normalizePattern(src.blocks{1}); S.Properties.UserData = src.meta;
            P = calcPattern(S, app.getParam());
        end

        function onProcess(app)
            if isempty(app.srcTbl), uialert(app.UIFigure, 'No file! Load a pattern first.', 'Warning', 'Icon', 'warning'); return; end
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Processing', 'Message', 'Re-processing pattern...', 'Indeterminate', 'on'); cleaner = onCleanup(@() delete(dlg));
            done = app.startPerf("Reprocess pattern"); app.keepOneDegree = strcmp(app.Single_DropDown_step.Value, 'STEP: 1°');
            try
                if isGenericText(app.filePath)                % reinterpret the cached generic table with the selected format
                    src = readPattern(app.filePath, app.Single_DropDown_TextFormat.Value, app.raw);
                    assert(~src.meta.isCoverage, 'The selected generic format identifies a coverage-results file.');
                    app.activateSource(src); app.perf("Reinterpret generic source");
                end
                app.refresh();
                app.setStatus(app.Single_StatusBar, ['Re-processed <b>' app.fileName '</b> with current parameters ✅'], true);
            catch ME
                app.showError(ME, 'Processing Error');
            end
            done();
        end

        function onTextFormatChanged(app)
            if strcmp(strtrim(app.Single_EditField_Path.Value), app.filePath) && isGenericText(app.filePath)
                app.autoCutBasis = true; app.onProcess();
            end
        end

        function onFFDChanged(app)
            k = find(strcmp(app.Single_DropDown_FFD.Items, app.Single_DropDown_FFD.Value), 1); app.autoCutBasis = true;
            done = app.startPerf("Switch FFD block");
            try, app.selectBlock(k); app.refresh(); catch ME, app.showError(ME, 'FFD Block Error'); end
            done(); app.setStatus(app.Single_StatusBar, sprintf('Switched to FFD block %d (%s).', k, app.Single_DropDown_FFD.Value), true);
        end

        function resetParams(app)
            d = app.defaults; if isempty(fieldnames(d)), return; end
            [app.Single_Spinner_Loss.Value, app.Single_DropDown_RxPol.Value, app.Single_Spinner_Rw.Value, app.Single_Spinner_Pt.Value, ...
                app.Single_DropDown_Pt.Value, app.Single_Spinner_R.Value, app.Single_DropDown_R.Value] = deal(d.Loss, d.RxPol, d.Rw, d.Pt, d.PtUnit, d.R, d.RUnit);
            if ~isempty(app.srcTbl), app.onProcess(); end
        end
    end

    %% ================================================================ processing pipeline
    methods (Access = private)
        function refresh(app)
            % Full pipeline after a source/parameter change: step selector → process → model → cut → full-pattern plots.
            [tStep, pStep] = deal(gridStep(app.srcTbl.Theta), gridStep(app.srcTbl.Phi));
            if ~isfinite(tStep), tStep = 1; end, if ~isfinite(pStep), pStep = tStep; end
            app.step = max(tStep, pStep); native = sprintf('STEP: %g°', app.step); nonCanonical = abs(tStep - 1) > 1e-9 || abs(pStep - 1) > 1e-9;
            app.Single_DropDown_step.Items = {native, 'STEP: 1°'};
            if app.keepOneDegree && nonCanonical, app.Single_DropDown_step.Value = 'STEP: 1°'; else, app.Single_DropDown_step.Value = native; end
            set(app.Single_DropDown_step, 'Visible', nonCanonical, 'Enable', nonCanonical);

            app.process(); app.perf("Process pattern"); app.checkCancelled();
            app.updateComponentItems(); app.updateModel(true); app.perf("Populate tables"); app.checkCancelled();
            app.Single_Switch_EHplaneValueChanged(); drawnow limitrate
            app.renderFull(); app.perf("Build plots");

            set([app.Single_Panel_Rect, app.Single_Export_Output, app.Single_Panel_fullPattern, app.Single_Panel_plotControl, app.Single_Button_Coverage], 'Visible', 'on');
            hasE = ~app.meta.isGainOnly;
            set([app.Single_Export_UAN, app.CheckBox_Et, app.CheckBox_Er, app.CheckBox_El], 'Visible', hasE); app.Single_gridEcut.Visible = hasE;
            set([app.CheckBox_Er, app.CheckBox_El, app.CutFieldBasisDropDown], 'Enable', hasE);
            app.updateInputVisibility();
            pol = ''; if hasE, pol = sprintf(' | Polarization <b>%s</b>', app.polLabel); end
            app.setStatus(app.Single_StatusBar, sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)%s', ...
                app.fileName, app.fmtNumber(app.POB, 2), app.fmtNumber(app.POBth), app.fmtNumber(app.POBph), pol), false);
        end

        function process(app)
            % srcTbl → patTbl.  Resampling (when 1° is selected) acts on primitive quantities before any nonlinear derivation.
            T = app.srcTbl;
            if strcmp(app.Single_DropDown_step.Value, 'STEP: 1°')
                keep = abs(T.Theta - round(T.Theta)) < 1e-9 & abs(T.Phi - round(T.Phi)) < 1e-9; D = T(keep, :);
                if gridStep(T.Theta) < 1 && gridStep(T.Phi) < 1 && gridStep(D.Theta) == 1 && gridStep(D.Phi) == 1
                    T = D;                                         % exact decimation of a finer integer-compatible grid
                else
                    T = resampleTo1Deg(T);
                end
                T.Properties.UserData = app.meta;
            end
            [app.patTbl, info] = calcPattern(T, app.getParam());
            app.solid = solidWeights(app.patTbl.Theta, app.patTbl.Phi); app.patRev = app.patRev + 1;
            [app.polLabel, app.polPairs] = deal(info.pol, info.pairs);
            if app.autoCutBasis && ~app.meta.isGainOnly
                if startsWith(info.pol, 'Linear'), app.CutFieldBasisDropDown.Value = 'Linear'; else, app.CutFieldBasisDropDown.Value = 'Circular'; end
            end
        end

        function p = getParam(app)
            p = struct('GainLoss_dB', app.Single_Spinner_Loss.Value, 'RxMode', string(app.Single_DropDown_RxPol.Value), 'RxAR_dB', app.Single_Spinner_Rw.Value);
            p.FieldScale = 10^(p.GainLoss_dB/20);
            pt = app.Single_Spinner_Pt.Value;
            switch app.Single_DropDown_Pt.Value
                case 'dBm',   p.Pt_dBW = pt - 30;
                case 'Watts', p.Pt_dBW = 10*log10(max(pt, eps));
                otherwise,    p.Pt_dBW = pt;
            end
            p.R_m = max(app.Single_Spinner_R.Value, app.DistanceFloorM); if strcmp(app.Single_DropDown_R.Value, 'km'), p.R_m = 1000*p.R_m; end
        end

        function updateModel(app, resetRanges)
            % Everything derived from patTbl + display conventions + selected component (no plotting).
            T = app.patTbl; c = app.comp();
            app.dispTbl = displayFrame(T, app.signedPhi(), app.elevation()); app.grid = struct();
            app.peakInfo = resolvePeak(T.(c), app.PeakPercentile, app.PeakMaxExcessDB);
            app.POB = app.peakInfo.value; app.POBth = T.Theta(app.peakInfo.index); app.POBph = mod(T.Phi(app.peakInfo.index), 360);
            app.boresightIndex = calcOrientation(T, app.solid, c, app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
            app.metrics = calcMetrics(T, app.solid, app.boresightIndex, app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
            if resetRanges
                if ~app.isAR(c), app.gainLim = peakWindow(chooseGain(T, 'E_Total_dB'), [-50 0], app.PeakPercentile, app.PeakMaxExcessDB); end
                [lim, ~] = app.theme(); app.onRange(lim, 0, "all", false);
            end
            app.updateTables(); app.updateMetadata();
        end

        function updateView(app, resetRanges)
            if isempty(app.patTbl), return; end
            app.updateModel(resetRanges); app.updateCutControl(); app.plotCut(); app.renderFull();
        end

        function onSpanChanged(app)
            done = app.startPerf("Change angular span"); app.updateView(false); done();
        end

        function onComponentChanged(app)
            done = app.startPerf("Change component"); app.updateView(true); done();
        end

        function stepChanged(app)
            done = app.startPerf("Change angular step");
            try, app.process(); app.updateComponentItems(); app.updateView(true); catch ME, app.showError(ME, 'Step Error'); end
            done();
        end

        function G = gridOf(app, col)
            % Display-frame rectangular grid (θ rows × φ columns) with cached geometry; component matrices are added lazily.
            G = app.grid;
            if ~isfield(G, 'theta')
                T = app.dispTbl; G.theta = unique(T.Theta); G.phi = unique(T.Phi);
                [~, it] = ismember(T.Theta, G.theta); [~, ip] = ismember(T.Phi, G.phi);
                G.idx = sub2ind([numel(G.theta), numel(G.phi)], it, ip); G.data = struct();
                [G.phiGrid, G.thetaGrid] = meshgrid(G.phi, G.theta);
                polar = G.thetaGrid; if app.elevation(), polar = 90 - polar; end
                G.thetaPolar = polar; G.phiRad = deg2rad(G.phiGrid);
                G.x = sind(polar).*cos(G.phiRad); G.y = sind(polar).*sin(G.phiRad); G.z = cosd(polar);
            end
            key = matlab.lang.makeValidName(col);
            if ~isfield(G.data, key), M = nan(size(G.phiGrid)); M(G.idx) = app.dispTbl.(col); G.data.(key) = M; end
            app.grid = G; G.C = G.data.(key);
        end

        function tf = elevation(app), tf = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°'); end
        function tf = signedPhi(app), tf = strcmp(app.Single_Switch_AngularSpan.Value, '-180° to 180°'); end
        function c = comp(app), c = app.Single_DropDown_Component.Value; end
        function s = thetaName(app), if app.elevation(), s = "Elevation"; else, s = "Theta"; end, end

        function s = compLabel(app)
            dd = app.Single_DropDown_Component; k = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(k), s = string(dd.Value); else, s = string(dd.Items{k}); end
        end

        function updateComponentItems(app)
            [cols, labels] = componentMap(app.patTbl); dd = app.Single_DropDown_Component; prev = dd.Value;
            set(dd, 'Items', cellstr(labels), 'ItemsData', cellstr(cols)); dd.Value = preferredComponent(prev, cols);
        end

        function [px, ty, dir] = spanLimits(app)
            if app.signedPhi(), px = [-180 180]; else, px = [0 360]; end
            if app.elevation(), ty = [-90 90]; dir = 'normal'; else, ty = [0 180]; dir = 'reverse'; end
        end
    end

    %% ================================================================ tables & metadata
    methods (Access = private)
        function updateTables(app)
            T = app.dispTbl; dd = app.Single_DropDown_output; cols = T.Properties.VariableNames(3:end);
            if ~app.rawShown
                set(app.Single_Table_DataIn, 'Data', app.raw, 'ColumnName', app.raw.Properties.VariableNames, 'Visible', 'on'); app.rawShown = true;
            end
            schemaChanged = ~isequal(erase(dd.Items(2:end), '✓ '), cols);
            if schemaChanged
                set(dd, 'Items', [{'--- column filter ---'}, cols], 'ItemsData', 0:numel(cols)); dd.Value = 0;
                app.outMask = ~ismember(cols, app.HiddenOutputColumns);
                set([dd, app.Single_Table_DataOut, app.Single_tabData], 'Visible', 'on');
            end
            app.filterOutput(schemaChanged);
        end

        function filterOutput(app, restyle)
            % Results column filter: the dropdown toggles one column per selection; ✓ marks and styles show the active set.
            persistent onStyle offStyle
            if isempty(onStyle), onStyle = uistyle('FontWeight', 'bold', 'BackgroundColor', [0.8 1 0.8]); offStyle = uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9]); end
            dd = app.Single_DropDown_output;
            if dd.Value > 0, app.outMask(dd.Value) = ~app.outMask(dd.Value); dd.Value = 0; end
            if nargin < 2 || restyle
                dd.Items = erase(dd.Items, '✓ '); on = find(app.outMask) + 1; off = find([true, ~app.outMask]); dd.Items(on) = append('✓ ', dd.Items(on));
                removeStyle(dd); if ~isempty(on), addStyle(dd, onStyle, 'Item', on); end, if ~isempty(off), addStyle(dd, offStyle, 'Item', off); end
            end
            app.Single_Table_DataOut.Data = app.dispTbl(:, [true, true, app.outMask]);
            app.updateInputVisibility();
        end

        function updateInputVisibility(app)
            % Parameter controls appear only when a visible Results column depends on them.
            on = string(app.dispTbl.Properties.VariableNames(3:end)); on = on(app.outMask);
            set([app.RxPolLabel, app.Single_DropDown_RxPol, app.RwLabel, app.Single_Spinner_Rw], 'Visible', any(ismember(on, ["PLF_dB","Gain_PolCorrected_dB"])));
            set([app.PtLabel, app.Single_Spinner_Pt, app.Single_DropDown_Pt], 'Visible', any(ismember(on, ["EIRP_dBW","PFD_Wm2","E_RMS_Vm"])));
            set([app.DistanceLabel, app.Single_Spinner_R, app.Single_DropDown_R], 'Visible', any(ismember(on, ["PFD_Wm2","E_RMS_Vm"])));
            set([app.LossLabel, app.Single_Spinner_Loss], 'Visible', app.meta.isGainOnly || ...
                any(ismember(on, ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","Gain_PolCorrected_dB","EIRP_dBW","PFD_Wm2","E_RMS_Vm"])));
        end

        function updateMetadata(app)
            T = app.dispTbl; th = unique(T.Theta); ph = unique(T.Phi); m = app.metrics; f = @(v) app.fmtNumber(v);
            rows = {'Source format', app.meta.source; 'File', app.fileName; ...
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(T), numel(th), numel(ph)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', f(min(th)), f(max(th)), f(gridStep(th))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', f(min(ph)), f(max(ph)), f(gridStep(ph)))};
            if any(isfinite(app.freqs)), rows(end+1, :) = {'Frequencies', strjoin(compose('%.4g GHz', app.freqs(isfinite(app.freqs))/1e9), ', ')}; end
            if ~app.meta.isGainOnly
                rows(end+1, :) = {'Polarization', app.polLabel};
                rows(end+1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(app.polPairs.(app.CutFieldBasisDropDown.Value), ' / '))};
            end
            rows = [rows; { ...
                'Peak of beam (POB)', sprintf('%s dB  [%s]', f(app.POB), app.compLabel()); ...
                'POB direction [θ, φ]', sprintf('[%s°, %s°]', f(app.POBth), f(app.POBph)); ...
                'Peak policy', sprintf('P%.4g, max excess %.4g dB (adjusted: %s)', app.PeakPercentile, app.PeakMaxExcessDB, string(app.peakInfo.wasAdjusted)); ...
                'Boresight axis', app.PrincipalAxes.labels{app.boresightIndex}; ...
                'Peak total gain', sprintf('%s dB @ [%s°, %s°]', f(m.PeakGain_dB), f(m.PeakTheta_deg), f(m.PeakPhi_deg)); ...
                'HPBW E-plane', [f(m.HPBW_EPlane_deg) '°']; 'HPBW H-plane', [f(m.HPBW_HPlane_deg) '°']; ...
                'Front-to-back', [f(m.FrontBack_dB) ' dB']; 'Peak directivity', [f(m.PeakDirectivity_dB) ' dB']; ...
                'Radiation efficiency', [f(m.Efficiency_pct) ' %']; 'AR at peak', [f(m.AxialRatioAtPeak_dB) ' dB']}];
            if isfield(app.meta, 'summary')
                for k = string(fieldnames(app.meta.summary)).', rows(end+1, :) = {char("Excel: " + k), char(string(app.meta.summary.(k)))}; end
            end
            app.Single_Table_metadata.Data = rows;
        end
    end

    %% ================================================================ colour scale & ranges
    methods (Access = private)
        function [lim, map] = theme(app)
            % Signed axial ratio: fixed ±30 dB blue-white-red map.  Everything else: shared gain scale with jet.
            persistent jetMap arMap
            if isempty(jetMap), jetMap = jet(256); arMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
            if app.isAR(app.comp()), lim = [-30 30]; map = arMap; else, lim = app.gainLim; map = jetMap; end
        end

        function tf = isAR(~, c)
            key = regexprep(lower(strtrim(string(c))), '[^a-z0-9]', '');
            tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
        end

        function applyTheme(app, ax, lim, map)
            clim(ax, lim); colormap(ax, map); cb = colorbar(ax);
            t = app.ticks(lim); if ~isempty(t), cb.Ticks = t; end
        end

        function t = ticks(app, lim)
            s = app.Single_Plot_Cstep.Value; t = [];
            if ~isfinite(s) || s <= 0 || diff(lim) <= 0, return; end
            t = unique([lim(1), ceil(lim(1)/s)*s:s:floor(lim(2)/s)*s, lim(2)]); if numel(t) > 60, t = []; end
        end

        function onRange(app, value, which, scope, apply)
            % Keep slider/spinner pairs consistent and apply the limits.  which: [] slider, 1 min, 2 max, 0 programmatic.
            if nargin < 5, apply = true; end
            if scope == "all"
                r = clampRange(value); app.Single_Plot_Cmin.Value = r(1); app.Single_Plot_Cmax.Value = r(2);
                app.onRange(r, 0, "full", apply); app.onRange(r, 0, "cut", apply); return
            end
            if scope == "full", sl = [app.Full.range]; lo = [app.Full.minSp]; hi = [app.Full.maxSp]; r = app.ctrLim;
            else, sl = app.Range_Cut; lo = app.Range_Cut_Min; hi = app.Range_Cut_Max; r = app.cutLim; end
            if isempty(which) || isequal(which, 0), r = value; else, r(which) = value; end
            r = clampRange(r); lim = r;
            if ~isequal(which, 0), lim = [min(sl(1).Limits(1), r(1)), max(sl(1).Limits(2), r(2))]; end   % user edits may only widen the travel
            set(sl, 'Limits', [-250 100], 'Value', r); set(sl, 'Limits', lim);
            set(lo, 'Limits', [-250, r(2) - 1], 'Value', r(1)); set(hi, 'Limits', [r(1) + 1, 100], 'Value', r(2));
            if scope == "full", app.ctrLim = r; if ~app.isAR(app.comp()), app.gainLim = r; end, else, app.cutLim = r; end
            if ~apply || isempty(app.patTbl), return; end
            if scope == "full", app.applyFullRange(r); else, set(app.Single_paxCut, 'RLim', r); set(app.Single_AxesRect, 'YLim', r); end
            drawnow limitrate
        end

        function applyFullRange(app, r)
            if isempty(app.patTbl), return; end
            for s = app.Full
                clim(s.axes, r); if s.name == "rect3D", zlim(s.axes, r); end
                cb = findall(app.UIFigure, 'Type', 'ColorBar', 'Axes', s.axes); t = app.ticks(r);
                if ~isempty(cb) && ~isempty(t), cb(1).Ticks = t; end
            end
        end
    end

    %% ================================================================ full-pattern renderers
    methods (Access = private)
        function renderFull(app)
            if isempty(app.patTbl), return; end
            for s = app.Full, app.checkCancelled(); s.render(); end
            app.syncAnnotations();
        end

        function drawContour(app)
            G = app.gridOf(app.comp()); ax = app.Single_Axes_Ctr; cla(ax);
            h = pcolor(ax, G.phi, G.theta, G.C, 'FaceColor', 'interp', 'LineStyle', 'none', 'Tag', 'APAT_Surface');
            [lim, map] = app.theme(); app.applyTheme(ax, lim, map);
            app.angularAxes(ax, 30, 15); daspect(ax, [1 1 1]); title(ax, app.compLabel(), 'Interpreter', 'none');
            app.tipTemplate(h, G); [r, c] = app.pobCell(G); app.addPOB(ax, G.phi(c), G.theta(r), 1, G, r, c); app.attachMenu(ax);
        end

        function drawFisheye(app)
            G = app.gridOf(app.comp()); pax = app.Single_paxPattern; cla(pax);
            h = surface(pax, G.phiRad, G.thetaPolar, zeros(size(G.C)), G.C, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            [lim, map] = app.theme(); app.applyTheme(pax, lim, map); app.polarTicks(pax);
            rl = 0:30:180; if app.elevation(), rl = 90 - rl; end
            set(pax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', rl));
            title(pax, sprintf('%s  |  r=θ, angle=φ', app.compLabel()), 'Interpreter', 'none', 'FontSize', 9);
            app.tipTemplate(h, G); [r, c] = app.pobCell(G); app.addPOB(pax, G.phiRad(r, c), G.thetaPolar(r, c), 0, G, r, c); app.attachMenu(pax);
        end

        function draw3D(app, ax, kind)
            % kind "sphere": colour on the unit sphere.  kind "polar": radius = normalised gain above the scale minimum.
            G = app.gridOf(app.comp()); [lim, map] = app.theme(); R = 1;
            if kind == "polar", R = app.polarRadius(G.C, lim); end
            cla(ax); hold(ax, 'on');
            h = surf(ax, R.*G.x, R.*G.y, R.*G.z, G.C, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax, lim, map);
            set(ax, 'Projection', 'orthographic', 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1]);
            axis(ax, 'off'); app.drawXYZ(ax); app.applyView(ax, [135 25]);
            title(ax, sprintf('%s  |  θ: %s  |  φ: %s', app.compLabel(), app.Single_Switch_ThetaSpan.Value, app.Single_Switch_AngularSpan.Value), 'Interpreter', 'none'); ax.Title.Visible = 'on';
            app.tipTemplate(h, G); [r, c] = app.pobCell(G); Rp = R; if ~isscalar(R), Rp = R(r, c); end
            app.addPOB(ax, Rp*G.x(r, c), Rp*G.y(r, c), Rp*G.z(r, c), G, r, c);
            hold(ax, 'off'); app.overlayCut3D(ax, kind, lim); app.attachMenu(ax);
        end

        function R = polarRadius(~, C, lim)
            R = max(C - lim(1), 0) / max(diff(lim), eps); R = R / max(max(R, [], 'all', 'omitnan'), eps);
        end

        function drawRect3(app)
            G = app.gridOf(app.comp()); ax = app.Single_Axes_3dRect; cla(ax);
            h = surf(ax, G.phiGrid, G.thetaGrid, G.C, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            [lim, map] = app.theme(); app.applyTheme(ax, lim, map); zlim(ax, lim); t = app.ticks(lim); if ~isempty(t), ax.ZTick = t; end
            app.angularAxes(ax, 60, 30); grid(ax, 'on');
            xlabel(ax, 'Phi (degree)'); ylabel(ax, app.thetaName() + " (degree)"); zlabel(ax, app.compLabel() + " (dB)", 'Interpreter', 'none');
            app.applyView(ax, [-35 35]); title(ax, app.compLabel(), 'Interpreter', 'none');
            app.tipTemplate(h, G); [r, c] = app.pobCell(G); app.addPOB(ax, G.phi(c), G.theta(r), G.C(r, c), G, r, c); app.attachMenu(ax);
        end

        function drawXYZ(~, ax)
            colors = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'}; D = 1.35*eye(3);
            for k = 1:3
                quiver3(ax, 0, 0, 0, D(k, 1), D(k, 2), D(k, 3), 0, 'Color', colors{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12*D(k, 1), 1.12*D(k, 2), 1.12*D(k, 3), labels{k}, 'Color', colors{k}, 'FontWeight', 'bold');
            end
        end

        function applyView(app, ax, default)
            up = [0 0 1]; v = default;
            switch string(app.Single_DropDown_3DView.Value)
                case "top",    v = [0 90];  up = [0 1 0];
                case "bottom", v = [0 -90]; up = [0 1 0];
                case "right",  v = [90 0];
                case "left",   v = [-90 0];
                case "front",  v = [0 0];
                case "back",   v = [180 0];
            end
            view(ax, v); camup(ax, up);
        end

        function on3DViewChanged(app)
            if isempty(app.patTbl), return; end
            app.applyView(app.Single_Axes_3dSph, [135 25]); app.applyView(app.Single_Axes_3dPol, [135 25]); app.applyView(app.Single_Axes_3dRect, [-35 35]); drawnow limitrate
        end

        function overlayCut3D(app, ax, kind, lim)
            delete(findall(ax, 'Tag', 'APAT_CutOverlay'));
            if ~app.Single_CheckBox_overlayCut.Value, return; end
            cut = app.cutData(); v = cut.data(:, 1);
            if kind == "sphere", R = 1.02; else, G = app.gridOf(app.comp()); R = 1.01*max(v - lim(1), 0)/max(diff(lim), eps)/max(max(max(G.C - lim(1), 0)/max(diff(lim), eps), [], 'all', 'omitnan'), eps); end
            hold(ax, 'on');
            plot3(ax, R.*sind(cut.theta).*cosd(cut.phi), R.*sind(cut.theta).*sind(cut.phi), R.*cosd(cut.theta), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay');
            hold(ax, 'off');
        end

        function drawOverlays(app)
            if isempty(app.patTbl), return; end
            [lim, ~] = app.theme(); app.overlayCut3D(app.Single_Axes_3dSph, "sphere", lim); app.overlayCut3D(app.Single_Axes_3dPol, "polar", lim);
        end

        function angularAxes(app, ax, phiStep, thetaStep)
            [px, ty, dir] = app.spanLimits();
            set(ax, 'XLim', px, 'YLim', ty, 'YDir', dir, 'Box', 'on', 'Layer', 'top', 'XTick', px(1):phiStep:px(2), 'YTick', ty(1):thetaStep:ty(2));
        end

        function polarTicks(app, pax)
            a = 0:30:330; if app.signedPhi(), a(a > 180) = a(a > 180) - 360; end
            set(pax, 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', a));
        end

        function tipTemplate(app, h, G)
            try
                h.DataTipTemplate.DataTipRows = [dataTipTextRow(app.thetaName(), G.thetaGrid, '%.4g°'); dataTipTextRow("Phi", G.phiGrid, '%.4g°'); ...
                    dataTipTextRow(replace(app.compLabel(), "_", "\_"), G.C, '%.4g dB')];
            catch
            end
        end

        function [r, c] = pobCell(app, G)
            % Row/column of the peak of beam inside the display grid.
            th = app.POBth; ph = app.POBph;
            if app.elevation(), th = 90 - th; end
            if app.signedPhi() && ph > 180, ph = ph - 360; end
            [~, r] = min(abs(G.theta - th)); [~, c] = min(abs(G.phi - ph));
        end

        function addPOB(app, ax, x, y, z, G, r, c)
            % Peak-of-beam marker with a pinned DataTip; both follow the 'Annotate POB' checkbox.
            if ~isfinite(app.POB), return; end
            rows = [dataTipTextRow(app.thetaName(), G.thetaGrid(r, c), '%.4g°'); dataTipTextRow("Phi", G.phiGrid(r, c), '%.4g°'); dataTipTextRow(app.compLabel(), G.C(r, c), '%.4g dB')];
            hold(ax, 'on');
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), m = polarplot(ax, x, y, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5);
            else, m = plot3(ax, x, y, z, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'Clipping', 'off'); end
            hold(ax, 'off'); app.pinTip(m, rows, 'APAT_POB', app.Single_CheckBox_POB.Value);
        end

        function pinTip(~, handles, rows, tag, on)
            for h = handles(:).'
                set(h, 'HandleVisibility', 'off', 'Tag', tag, 'Visible', on);
                try
                    h.DataTipTemplate.DataTipRows = rows;
                    t = datatip(h, 'DataIndex', 1, 'FontSize', 9, 'Tag', tag, 'HandleVisibility', 'off'); t.Visible = on;
                catch
                end
            end
        end

        function syncAnnotations(app)
            % Tagged markers/tips follow their checkbox; pinned tips are shown only on the tab that is currently selected.
            for kind = ["POB", "HPBW"]
                if kind == "POB", on = app.Single_CheckBox_POB.Value; else, on = app.Single_CheckBox_HPBWBounds.Value; end
                for h = findall(app.UIFigure, 'Tag', "APAT_" + kind).'
                    tab = ancestor(h, 'uitab'); visible = on;
                    if strcmp(h.Type, 'datatip') && ~isempty(tab), visible = on && isequal(tab.Parent.SelectedTab, tab); end
                    h.Visible = visible;
                end
            end
        end

        function attachMenu(app, ax)
            set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', app.PlotMenu);
        end

        function deleteUserTips(~, obj)
            ax = ancestor(obj, {'axes', 'polaraxes'}); if isempty(ax), return; end
            t = findall(ax, 'Type', 'datatip'); if isempty(t), return; end
            delete(t(~startsWith(string({t.Tag}), "APAT_")));
        end
    end

    %% ================================================================ pattern cuts
    methods (Access = private)
        function [cols, idx] = cutCols(app)
            % Selected cut columns (Total + co/cross pair); idx keeps the colour of each trace stable.
            if app.meta.isGainOnly, cols = app.patTbl.Properties.VariableNames(3); idx = 1; return; end
            if strcmp(app.CutFieldBasisDropDown.Value, 'Linear'), all3 = {'E_Total_dB','E_TH_dB','E_PH_dB'}; pair = {'E_TH','E_PH'};
            else, all3 = {'E_Total_dB','E_RCP_dB','E_LCP_dB'}; pair = {'E_RCP','E_LCP'}; end
            if ~strcmp(app.CheckBox_Er.Text, pair{1}), app.CheckBox_Er.Text = pair{1}; app.CheckBox_El.Text = pair{2}; end
            sel = logical([app.CheckBox_Et.Value, app.CheckBox_Er.Value, app.CheckBox_El.Value]); if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = all3(idx);
        end

        function cut = cutData(app)
            % The active cut as one closed circle in the selected φ display span [lo, lo+360].
            T = app.patTbl; [cols, idx] = app.cutCols();
            type = string(app.Single_DropDown_cutType.Value); req = app.Single_DropDown_cutValue.Value;
            if type == "Phi" && app.elevation(), req = 90 - req; end                      % spinner shows the display frame
            [ang, rows, fixed, sym, snapped] = cutCircle(T, type, req);
            if snapped, app.setStatus(app.Single_StatusBar, sprintf('Requested %s cut @ %s=%g° (snapped to nearest %s=%g°)', type, sym, req, sym, fixed), false); end
            data = T{rows, cols}; th = T.Theta(rows); ph = T.Phi(rows);
            lo = 0; if app.signedPhi(), lo = -180; end
            [ang, o] = unique(mod(ang - lo, 360) + lo); data = data(o, :); th = th(o); ph = ph(o);
            w = (lo + 360 - ang(end)) / (ang(1) + 360 - ang(end));                          % periodic seam sample (exact copy when the grid contains lo)
            seam = data(end, :) + w*(data(1, :) - data(end, :)); sth = th(end) + w*(th(1) - th(end)); sph = ph(end) + w*(ph(1) - ph(end));
            if ang(1) > lo, ang = [lo; ang]; data = [seam; data]; th = [sth; th]; ph = [sph; ph]; end
            ang(end+1, 1) = lo + 360; data(end+1, :) = seam; th(end+1, 1) = sth; ph(end+1, 1) = sph;
            if app.meta.isGainOnly, ttl = char(app.comp()); else, ttl = sprintf('%s cut @ %s = %g°', type, sym, fixed); end
            cut = struct('angle', ang, 'data', data, 'theta', th, 'phi', ph, 'idx', idx, 'title', ttl, 'cols', {cols}, 'names', replace(string(cols), "_", "\_"));
        end

        function plotCut(app)
            if isempty(app.patTbl), return; end
            cut = app.cutData(); pax = app.Single_paxCut; rax = app.Single_AxesRect;
            cla(pax); cla(rax); app.Label_HPBW.Text = ''; lim = clampRange(app.Range_Cut.Value); [px, ~] = app.spanLimits();
            hold(pax, 'on'); hold(rax, 'on');
            pl = polarplot(pax, deg2rad(cut.angle), max(cut.data, lim(1)), 'LineWidth', 1.4);    % clamp: no reflection below the inner ring
            rl = plot(rax, cut.angle, cut.data, 'LineWidth', 1.4); colors = rax.ColorOrder(1 + mod(cut.idx - 1, 7), :);
            for k = 1:numel(pl)
                rows = [dataTipTextRow("Angle", cut.angle, '%.4g°'), dataTipTextRow("Magnitude", cut.data(:, k), '%.4g dB')];
                set([pl(k), rl(k)], 'Color', colors(k, :)); pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            set(pax, 'ThetaDir', 'clockwise', 'ThetaZeroLocation', 'top', 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.polarTicks(pax);
            set(rax, 'YLim', lim, 'XLim', px, 'XTick', px(1):30:px(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, [app.Single_DropDown_cutType.Value ' (degree)']); title(pax, cut.title, 'Interpreter', 'none'); title(rax, cut.title, 'Interpreter', 'none');
            [pk, kpk] = max(cut.data(:, 1), [], 'omitnan');                                    % peak of the displayed cut
            if isfinite(pk)
                rows = [dataTipTextRow("Angle", cut.angle(kpk), '%.4g°'); dataTipTextRow("Magnitude", pk, '%.4g dB')];
                m1 = polarplot(pax, deg2rad(cut.angle(kpk)), max(pk, lim(1)), 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5);
                m2 = plot(rax, cut.angle(kpk), pk, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5);
                app.pinTip([m1, m2], rows, 'APAT_POB', app.Single_CheckBox_POB.Value);
                if app.Button_HPBW.Value
                    [bw, lo, hi] = calcHPBW(cut.angle, cut.data(:, 1), pk, cut.angle(kpk));
                    if isfinite(bw)
                        b = mod([lo, hi] - px(1), 360) + px(1);                                 % bounds inside the display span
                        app.Label_HPBW.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                        if b(1) <= b(2), reg = b; else, reg = [px(1), b(2); b(1), px(2)]; end   % wrap-aware shaded region
                        thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                        xregion(rax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                        lbl = ["Lower HPBW", "Upper HPBW"];
                        for j = 1:2
                            rows = [dataTipTextRow(lbl(j), b(j), '%.2f°'); dataTipTextRow("Gain", pk - 3, '%.2f dB')];
                            h1 = polarplot(pax, deg2rad(b(j)), max(pk - 3, lim(1)), 'o', 'Color', '#D95319', 'MarkerFaceColor', '#D95319');
                            h2 = plot(rax, b(j), pk - 3, 'o', 'Color', '#D95319', 'MarkerFaceColor', '#D95319');
                            app.pinTip([h1, h2], rows, 'APAT_HPBW', app.Single_CheckBox_HPBWBounds.Value);
                        end
                    end
                end
            end
            legend(pax, pl, cut.names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rl, cut.names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off'); app.attachMenu(pax); app.attachMenu(rax); app.syncAnnotations();
        end

        function onCutChanged(app, src)
            if nargin > 1 && isequal(src, app.Single_DropDown_cutType), app.updateCutControl(); end
            if nargin > 1 && isequal(src, app.CutFieldBasisDropDown), app.autoCutBasis = false; if ~isempty(app.patTbl), app.updateMetadata(); end, end
            show = app.Button_HPBW.Value; app.Single_CheckBox_HPBWBounds.Visible = show;
            if ~show, app.Single_CheckBox_HPBWBounds.Value = false; end
            app.plotCut(); if app.Single_CheckBox_overlayCut.Value, app.drawOverlays(); end
        end

        function v = updateCutControl(app)
            % Cut value = fixed θ (display frame) for Phi cuts, fixed φ∈[0,360) for Theta cuts.
            if strcmp(app.Single_DropDown_cutType.Value, 'Phi'), v = unique(app.dispTbl.Theta); else, v = unique(mod(app.patTbl.Phi, 360)); end
            sp = app.Single_DropDown_cutValue; [~, k] = min(abs(v - sp.Value));
            sp.Limits = [-Inf Inf]; sp.Value = v(k); sp.Limits = [min(v), max(v)]; if numel(v) > 1, sp.Step = min(diff(v)); end
        end

        function Single_Switch_EHplaneValueChanged(app)
            % E-plane: θ sweep at the boresight φ.  H-plane: the orthogonal principal plane of the detected boresight axis.
            A = app.PrincipalAxes; k = app.boresightIndex; type = 'Theta'; value = 90;
            if startsWith(app.Single_Switch_EHplane.Value, 'E'), value = A.phi(k);
            elseif A.theta(k) == 90, type = 'Phi'; if app.elevation(), value = 0; end, end
            app.Single_DropDown_cutType.Value = type; v = app.updateCutControl();
            [~, n] = min(abs(v - value)); app.Single_DropDown_cutValue.Value = v(n); app.onCutChanged();
        end

        function exportCut(app)
            if isempty(app.patTbl), return; end
            cut = app.cutData(); T = array2table([cut.angle, cut.data], 'VariableNames', [{'Angle_deg'}, cut.cols]);
            app.exportTable(T, fullfile(app.folderPath, [app.baseName '_cut.csv']), ['Cut (' cut.title ')'], app.Single_StatusBar);
        end
    end

    %% ================================================================ export
    methods (Access = private)
        function exportResults(app)
            if isempty(app.patTbl), return; end
            app.exportTable(app.Single_Table_DataOut.Data, fullfile(app.folderPath, [app.baseName '_APAT_results.csv']), 'Results', app.Single_StatusBar);
        end

        function exportTable(app, T, defaultPath, what, label)
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, ['Export ' what], defaultPath);
            if isequal(f, 0), return; end
            try
                fp = fullfile(p, f);
                if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
                app.setStatus(label, sprintf('%s exported to <b>%s</b>', what, fp), true);
            catch ME
                app.showError(ME, 'Export Error');
            end
        end

        function exportUAN(app)
            if app.meta.isGainOnly, uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            T = app.patTbl;
            U = sortrows(table(T.Theta, T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta','Phi','E_TH_DB','E_PH_DB','E_TH_DG','E_PH_DG'}), {'Phi', 'Theta'});
            gmax = max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan'); st = gridStep(U.Theta); if ~isfinite(st), st = 1; end
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, ...
                'Export UAN / E-field data', fullfile(app.folderPath, sprintf('%s_%.5f_%gdeg.uan', app.baseName, gmax, st)));
            if isequal(f, 0), return; end
            try
                fp = fullfile(p, f);
                if endsWith(fp, '.uan', 'IgnoreCase', true)
                    hdr = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\ncomplex\nmag_phase\n' ...
                        'pattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                        min(U.Phi), max(U.Phi), gridStep(U.Phi), min(U.Theta), max(U.Theta), st, gmax);
                    writelines(hdr, fp); writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
                elseif endsWith(fp, '.txt', 'IgnoreCase', true), writetable(U, fp, 'Delimiter', '\t');
                else, writetable(U, fp);
                end
                app.setStatus(app.Single_StatusBar, ['UAN exported to <b>' fp '</b>'], true);
            catch ME
                app.showError(ME, 'Export UAN Error');
            end
        end
    end

    %% ================================================================ coverage
    methods (Access = private)
        function Single_Button_CoveragePushed(app)
            % Coverage is fed from the processed Main pattern (loss, step, parameters already applied).
            if isempty(app.patTbl), uialert(app.UIFigure, 'Load and process a pattern first.', 'Coverage'); return; end
            app.TabGroup.SelectedTab = app.Tab2_Coverage; app.Cov_EditField_filePath.Value = app.filePath;
            node = app.covFindByPath(app.filePath);
            if isempty(node), app.covAddPattern(app.baseName, app.filePath, app.raw, app.patTbl);
            else, app.covSyncFromMain(node); app.Cov_Tree.SelectedNodes = node; app.covSync(node); app.setCoverageUI(); end
            app.setStatus(app.Cov_StatusBar, 'Coverage source synchronized from the processed Main-tab pattern.', false);
        end

        function Cov_Button_LoadPushed(app)
            fp = strtrim(app.Cov_EditField_filePath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFindByPath(fp))
                fp = app.browse('Select a pattern or coverage results file'); if isempty(fp), return; end
            end
            node = app.covFindByPath(fp);
            if ~isempty(node)
                app.Cov_Tree.SelectedNodes = node; app.Cov_TreeSelectionChanged(); app.Cov_EditField_filePath.Value = fp; app.setCoverageUI();
                app.setStatus(app.Cov_StatusBar, 'File already loaded -- node selected. Add another job or load a different file.', true); return
            end
            app.Cov_EditField_filePath.Value = fp;
            try
                src = app.readSource(fp, app.Cov_TextFormatLabel, app.Cov_DropDown_TextFormat);
                if src.meta.isCoverage
                    node = app.covPatternTarget(); if ~isempty(node), app.Cov_EditField_filePath.Value = node.NodeData.path; end
                    app.covLoadResults(fp, src.raw);
                else
                    [~, name] = fileparts(fp); app.covAddPattern(name, fp, src.raw, app.buildPattern(src));   % multi-frequency sources use block 1
                end
            catch ME
                app.showError(ME, 'Coverage Load Error');
            end
        end

        function onCovTextFormatChanged(app)
            % Re-interpret an already loaded generic pattern with the newly selected format.
            fp = strtrim(app.Cov_EditField_filePath.Value); old = app.covFindByPath(fp);
            if isempty(old) || ~isGenericText(fp) || ~strcmp(old.NodeData.kind, 'pattern'), return; end
            try
                src = readPattern(fp, app.Cov_DropDown_TextFormat.Value, old.NodeData.raw);
                if src.meta.isCoverage, app.setStatus(app.Cov_StatusBar, 'Coverage-result files are detected automatically; nothing to reprocess.', true); return; end
                name = old.NodeData.name;
                for j = app.covNodes('job', old).', delete(j.NodeData.line); end
                delete(old); app.covAddPattern(name, fp, src.raw, app.buildPattern(src)); app.covFinalize();
                app.setStatus(app.Cov_StatusBar, sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
            catch ME
                app.showError(ME, 'Coverage Format Error');
            end
        end

        function node = covAddPattern(app, name, path, raw, pattern)
            node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', 'pattern', 'name', name, 'path', path, 'raw', raw, 'pattern', pattern, ...
                'solid', solidWeights(pattern.Theta, pattern.Phi), 'rev', app.patRev, 'component', '', 'boresight', 1, 'cache', {cell(0, 2)});
            expand(app.Cov_Tree); app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node]; app.Cov_Tree.SelectedNodes = node;
            app.covSync(node); app.setCoverageUI(); app.Cov_Panel_Results.Visible = 'on';
            app.setStatus(app.Cov_StatusBar, sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name), false);
        end

        function covSyncFromMain(app, node)
            % The node that mirrors the Main pattern always follows the latest processed table.
            d = node.NodeData; if d.rev == app.patRev, return; end
            [d.pattern, d.solid, d.rev, d.name, d.component, d.cache] = deal(app.patTbl, app.solid, app.patRev, app.baseName, '', cell(0, 2));
            node.NodeData = d;
        end

        function covSync(app, node)
            % Align component list, detected boresight and threshold preset with a pattern node.
            d = node.NodeData; [cols, labels] = componentMap(d.pattern); dd = app.Cov_DropDown_Component;
            if isempty(d.component), prev = dd.Value; else, prev = d.component; end
            c = preferredComponent(prev, cols);
            if ~isequal(string(dd.ItemsData), cols), set(dd, 'Items', cellstr(labels), 'ItemsData', cellstr(cols)); end
            dd.Value = c;
            if ~strcmp(d.component, c)
                d.component = c; d.boresight = calcOrientation(d.pattern, d.solid, c, app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB); node.NodeData = d;
                if app.Cov_DropDown_Orientation.Value == 0, app.Cov_DropDown_OrientationValueChanged(); end
            end
            key = sprintf('%s|%s|%d', d.path, c, d.rev);        % preset thresholds once per pattern/component/revision; user edits stick
            if ~strcmp(app.covPresetKey, key)
                app.covPresetKey = key; app.setThresholdRange(peakWindow(d.pattern.(c), [-40 10], app.PeakPercentile, app.PeakMaxExcessDB));
            end
        end

        function setThresholdRange(app, b)
            % Only widen an already initialised threshold range so user adjustments survive.
            cur = [app.Cov_Spinner_ThreshMin.Value, app.Cov_Spinner_ThreshMax.Value];
            if app.covThreshInit, b = [min(cur(1), b(1)), max(cur(2), b(2))]; end
            app.covThreshInit = true;
            set([app.Cov_Spinner_ThreshMin, app.Cov_Spinner_ThreshMax], 'Limits', [-250 100]);
            app.Cov_Spinner_ThreshMin.Value = b(1); app.Cov_Spinner_ThreshMax.Value = b(2);
            app.Cov_Spinner_ThreshMin.Limits = [-250, b(2) - 0.1]; app.Cov_Spinner_ThreshMax.Limits = [b(1) + 0.1, 100];
        end

        function thr = covThresholds(app)
            % Thresholds exactly as entered (the automatic window is only a preset).
            tMin = app.Cov_Spinner_ThreshMin.Value; tMax = app.Cov_Spinner_ThreshMax.Value; st = max(app.Cov_Spinner_Step.Value, 0.1);
            if tMax <= tMin, tMax = min(100, tMin + st); app.Cov_Spinner_ThreshMax.Value = tMax; end
            thr = (tMin:st:tMax).'; if isempty(thr), thr = [tMin; tMax]; elseif thr(end) < tMax, thr(end+1, 1) = tMax; end
        end

        function Cov_Button_computeCovPushed(app)
            node = app.covPatternTarget();
            if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if strcmp(node.NodeData.path, app.filePath) && ~isempty(app.patTbl), app.covSyncFromMain(node); app.covSync(node); end
            done = app.startPerf("Compute coverage");
            try
                d = node.NodeData; T = d.pattern; c = app.Cov_DropDown_Component.Value; thr = app.covThresholds();
                conical = app.Cov_Btn_Conical.Value; mask = true(height(T), 1); orient = "n/a"; tag = 'Sph'; full = 'Sph coverage'; tableTag = 'Sph';
                if conical
                    [th0, ph0, alpha] = deal(app.Cov_Spinner_ConeTH.Value, mod(app.Cov_Spinner_ConePH.Value, 360), app.Cov_Spinner_ConeAng.Value);
                    mask = cosd(T.Theta)*cosd(th0) + sind(T.Theta)*sind(th0).*cosd(T.Phi - ph0) >= cosd(alpha);
                    orient = string(app.PrincipalAxes.labels{app.orientationIndex()}); center = app.coneLabel(th0, ph0);
                    tag = sprintf('Con_%.15g_%.15g_%.15g', th0, ph0, alpha);
                    full = sprintf('Conical coverage (%s) α=%s°', center, app.fmtNumber(alpha));
                    tableTag = sprintf('Con %s α%s°', erase(center, ["=", ","]), app.fmtNumber(alpha));
                end
                key = sprintf('%s|%d|%s|%.10g|%.10g|%.10g|%d', c, d.rev, tag, thr(1), thr(end), gridStep(thr), numel(thr));
                hit = find(strcmp(d.cache(:, 1), key), 1);
                if isempty(hit), cov = coverageCCDF(T.(c), mask, thr, d.solid); d.cache(end+1, :) = {key, cov}; node.NodeData = d; else, cov = d.cache{hit, 2}; end
                app.covAddJob(node, thr, cov, tag, c, full, struct('tableTag', tableTag, 'isConical', conical, 'orientationLabel', orient));
                app.covFinalize(); app.setPlotRange([thr(1), thr(end)], []); app.Cov_Panel_Results.Visible = 'on';
                if isempty(hit), act = 'computed'; else, act = 'reused cached CCDF'; end
                msg = sprintf('Run-<b>%d</b> %s: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', app.covRunID, act, full, d.name, c, numel(thr));
                if conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, orient); end
                app.setStatus(app.Cov_StatusBar, msg, false);
            catch ME
                app.showError(ME, 'Coverage Error');
            end
            done();
        end

        function covAddJob(app, parent, thr, cov, tag, c, label, meta)
            app.covRunID = app.covRunID + 1; icon = '📉'; if strcmp(tag, 'Res'), icon = '📈'; end
            text = sprintf('%s R%d %s · %s', icon, app.covRunID, label, c);
            line = plot(app.Cov_Axes, thr, cov, 'LineWidth', 1.6, 'DisplayName', text); [icov, ir] = unique(cov(:), 'last');
            node = uitreenode(parent, 'Text', text);
            node.NodeData = struct('kind', 'job', 'id', app.covRunID, 'tag', tag, 'thr', thr(:), 'cov', cov(:), 'icov', icov, 'ithr', thr(ir), 'line', line, ...
                'label', text, 'tableTag', meta.tableTag, 'isConical', meta.isConical, 'orientationLabel', meta.orientationLabel);
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node];
        end

        function covFinalize(app)
            % Results table (checked jobs on the union of their threshold grids), legend and UI state.
            jobs = app.covNodes('job'); expand(app.Cov_TreeNode_Results);
            for j = jobs(:).', expand(j.Parent); end
            checked = jobs(app.isChecked(jobs));
            thr = app.covThresholds(); if ~isempty(checked), ds = vertcat(checked.NodeData); thr = unique(vertcat(ds.thr)); end
            vals = thr; names = {'Threshold (dB)'}; lines = gobjects(0); labels = {};
            for j = checked(:).'
                d = j.NodeData; vals(:, end+1) = interp1(d.thr, d.cov, thr, 'linear', NaN); %#ok<AGROW>
                names{end+1} = sprintf('R%d %s %%', d.id, d.tableTag); lines(end+1) = d.line; labels{end+1} = d.label; %#ok<AGROW>
            end
            app.Cov_Table.Data = array2table(compose('%.2f', vals), 'VariableNames', names);
            if isempty(lines), legend(app.Cov_Axes, 'off'); else, legend(app.Cov_Axes, lines, labels, 'Location', 'southwest', 'Interpreter', 'none'); end
            app.setCoverageUI();
        end

        function covLoadResults(app, fp, T)
            [~, name] = fileparts(fp);
            node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📄 ' name]); node.NodeData = struct('kind', 'results', 'name', name, 'path', fp);
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node]; thr = T{:, 1};
            for k = 2:width(T), app.covAddJob(node, thr, T{:, k}, 'Res', T.Properties.VariableNames{k}, 'Res', struct('tableTag', 'Res', 'isConical', false, 'orientationLabel', "n/a")); end
            app.setPlotRange([min(thr), max(thr)], gridStep(thr)); app.covFinalize(); app.Cov_Panel_Results.Visible = 'on';
            app.setStatus(app.Cov_StatusBar, sprintf('Coverage results file "%s" loaded (%d curves).', name, width(T) - 1), false);
        end

        function nodes = covNodes(app, kind, under)
            % Nodes of one kind at/under a node.  The tree is two levels deep: source nodes (pattern/results) → job nodes.
            if nargin < 3, under = app.Cov_TreeNode_Results; end
            pool = under(:); lvl = under(:);
            for level = 1:2, lvl = vertcat(matlab.ui.container.TreeNode.empty(0, 1), lvl.Children); pool = [pool; lvl]; end %#ok<AGROW>
            keep = arrayfun(@(n) isstruct(n.NodeData) && strcmp(n.NodeData.kind, kind), pool); nodes = pool(keep);
            if numel(nodes) > 1 && strcmp(kind, 'job'), [~, o] = sort(arrayfun(@(n) n.NodeData.id, nodes)); nodes = nodes(o); end
        end

        function tf = isChecked(app, nodes)
            c = app.Cov_Tree.CheckedNodes; tf = false(size(nodes)); if isempty(c), return; end
            for k = 1:numel(nodes), tf(k) = any(c == nodes(k)); end
        end

        function node = covPatternTarget(app)
            % Pattern node to operate on: the selection (or its pattern ancestor), else the most recently added pattern.
            node = []; sel = app.Cov_Tree.SelectedNodes;
            if ~isempty(sel)
                n = sel(1);
                while isa(n, 'matlab.ui.container.TreeNode')
                    if isstruct(n.NodeData) && strcmp(n.NodeData.kind, 'pattern'), node = n; return; end
                    n = n.Parent;
                end
            end
            p = app.covNodes('pattern'); if ~isempty(p), node = p(end); end
        end

        function node = covFindByPath(app, fp)
            node = []; kids = app.Cov_TreeNode_Results.Children;
            for k = 1:numel(kids)
                if isstruct(kids(k).NodeData) && strcmp(kids(k).NodeData.path, fp), node = kids(k); return; end
            end
        end

        function jobs = covSelectedJobs(app)
            sel = app.Cov_Tree.SelectedNodes; jobs = matlab.ui.container.TreeNode.empty(0, 1);
            if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node first.', true); return; end
            jobs = app.covNodes('job', sel(1)); jobs = jobs(app.isChecked(jobs));
            if isempty(jobs), app.setStatus(app.Cov_StatusBar, 'No checked results under the selected node.', true); end
        end

        function h = covQueryLines(app, d, modes)
            % Dotted query projection lines of one job (axes children); query tips live on the curve itself.
            h = gobjects(0);
            for m = modes, h = [h; findall(app.Cov_Axes, 'Type', 'line', 'Tag', sprintf('CovQ_%s_%d', m, d.id))]; end %#ok<AGROW>
        end

        function covQuery(app, mode)
            % Project a threshold ("cov") or a coverage level ("thr") onto every checked job under the selection.
            if mode == "cov", q = app.Cov_Spinner_queryCov.Value; else, q = app.Cov_Spinner_queryThresh.Value; end
            jobs = app.covSelectedJobs(); if isempty(jobs), return; end
            ax = app.Cov_Axes; hit = false;
            for j = jobs(:).'
                d = j.NodeData; tag = sprintf('CovQ_%s_%d', mode, d.id);
                delete([app.covQueryLines(d, mode); findall(d.line, 'Type', 'datatip', 'Tag', tag)]);
                if mode == "cov", x = q; y = interp1(d.thr, d.cov, q, 'linear', NaN);
                elseif numel(d.icov) > 1, y = q; x = interp1(d.icov, d.ithr, q, 'linear', NaN); else, continue; end
                if ~isfinite(x) || ~isfinite(y), continue; end
                line(ax, [x, x], [ax.YLim(1), y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [-250, x], [y, y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                try
                    d.line.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", 'XData', '%.2f dB'); dataTipTextRow("Coverage", 'YData', '%.2f%%')];
                    datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'FontSize', 9, 'Tag', tag, 'HandleVisibility', 'off');   % exact interpolated position
                catch
                end
                hit = true;
            end
            if ~hit, msg = 'Query value is outside the checked results range.';
            elseif mode == "cov", msg = sprintf('Coverage queried at %s dB.', app.fmtNumber(q));
            else, msg = sprintf('Threshold queried at %s%% coverage.', app.fmtNumber(q)); end
            app.setStatus(app.Cov_StatusBar, msg, ~hit);
        end

        function Cov_Button_ClearPushed(app)
            sel = app.Cov_Tree.SelectedNodes; if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to clear.', true); return; end
            for j = app.covNodes('job', sel(1)).', d = j.NodeData; delete([app.covQueryLines(d, ["cov", "thr"]); findall(d.line, 'Type', 'datatip')]); end
            app.setStatus(app.Cov_StatusBar, 'Selected DataTips and query markers cleared.', true);
        end

        function Cov_Button_ResetPushed(app)
            delete(app.Cov_TreeNode_Results.Children); app.resetCoverageAxes(); app.Cov_Table.Data = table();
            [app.covRunID, app.covPresetKey, app.covThreshInit, app.covPlotInit] = deal(0, '', false, false);
            app.Cov_Panel_Results.Visible = 'off'; app.setCoverageUI(); app.setStatus(app.Cov_StatusBar, 'Coverage workspace reset 🔄', true);
        end

        function resetCoverageAxes(app)
            ax = app.Cov_Axes; cla(ax); legend(ax, 'off'); hold(ax, 'on'); grid(ax, 'on');
            set(ax, 'YLim', [0 100], 'Box', 'on', 'Layer', 'top', 'XLimMode', 'auto');
            set([app.Cov_Spinner_XRange, app.Cov_Spinner_XMin, app.Cov_Spinner_XMax], 'Limits', [-250 100]);
            app.Cov_Spinner_XRange.Value = [-40 10]; app.Cov_Spinner_XMin.Value = -40; app.Cov_Spinner_XMax.Value = 10;
        end

        function Cov_Button_ExportPushed(app)
            if isempty(app.Cov_Table.Data), return; end
            app.exportTable(app.Cov_Table.Data, fullfile(app.folderPath, 'coverage_results.csv'), 'Coverage Results', app.Cov_StatusBar);
        end

        function Cov_TreeCheckedNodesChanged(app)
            for j = app.covNodes('job').'
                d = j.NodeData; set([d.line; findall(d.line, 'Type', 'datatip'); app.covQueryLines(d, ["cov", "thr"])], 'Visible', app.isChecked(j));
            end
            app.covFinalize();
        end

        function Cov_TreeSelectionChanged(app)
            sel = app.Cov_Tree.SelectedNodes;
            for j = app.covNodes('job').', ln = j.NodeData.line; ln.LineWidth = 1.6; if ~isempty(sel) && j == sel(1), ln.LineWidth = 2.6; end, end   % highlight
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(app.Cov_StatusBar, 'Ready.', false); return; end
            d = sel(1).NodeData; node = app.covPatternTarget(); if ~isempty(node), app.covSync(node); end
            if ~strcmp(d.kind, 'job')
                n = numel(sel(1).Children); kind = 'Pattern'; if strcmp(d.kind, 'results'), kind = 'Results'; end
                app.setStatus(app.Cov_StatusBar, sprintf('%s <b>"%s"</b> -- <b>%d</b> coverage job%s.', kind, d.name, n, repmat('s', 1, n ~= 1)), false);
                if strcmp(d.kind, 'pattern'), app.reportOrientation(); end
                return
            end
            parts = {char(d.label)};
            if d.isConical, parts{end+1} = sprintf('Orientation <b>%s</b>', d.orientationLabel); end
            parts{end+1} = sprintf('Threshold [%s, %s] dB, step %s dB', app.fmtNumber(d.thr(1)), app.fmtNumber(d.thr(end)), app.fmtNumber(gridStep(d.thr)));
            t50 = NaN; if numel(d.icov) > 1, t50 = interp1(d.icov, d.ithr, 50, 'linear', NaN); end
            if isfinite(t50), parts{end+1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', app.fmtNumber(t50)); else, parts{end+1} = '<b>50%-coverage unavailable</b>'; end
            ok = isfinite(d.thr) & isfinite(d.cov);
            if any(ok)
                shown = round(d.cov(ok), 2); thrOk = d.thr(ok); k = find(shown == max(shown), 1, 'last');
                parts{end+1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', app.fmtNumber(max(shown)), app.fmtNumber(thrOk(k)));
            end
            app.setStatus(app.Cov_StatusBar, strjoin(parts, ' | '), false);
        end

        function setCoverageUI(app)
            hasPattern = ~isempty(app.covPatternTarget()); hasJobs = ~isempty(app.covNodes('job')); ctrls = app.Cov_gridPanel_Parm.Children;
            if hasPattern
                set(ctrls, 'Visible', 'on', 'Enable', 'on');
                set([app.Cov_Button_Export, app.Cov_Button_Clear, app.Cov_QueryControls], 'Enable', hasJobs);
                generic = isGenericText(app.Cov_EditField_filePath.Value);
                set([app.Cov_TextFormatLabel, app.Cov_DropDown_TextFormat], 'Visible', generic, 'Enable', generic);
                app.Cov_ButtonGroup_CovTypeSelectionChanged();
            else
                set(ctrls, 'Visible', 'off', 'Enable', 'off');
                set([app.AntennaPatternLabel, app.Cov_EditField_filePath, app.Cov_Button_Load, app.Cov_Button_computeCov], 'Visible', 'on', 'Enable', 'on');
                set([app.Cov_QueryControls, app.Cov_Button_Reset, app.Cov_Button_Export, app.Cov_Button_Clear, app.Cov_Button_toMain], 'Visible', hasJobs, 'Enable', hasJobs);
            end
        end

        function Cov_ButtonGroup_CovTypeSelectionChanged(app)
            conical = app.Cov_Btn_Conical.Value; set(app.Cov_ConeControls, 'Enable', conical, 'Visible', conical);
            if conical, node = app.covPatternTarget(); if ~isempty(node), app.covSync(node); end, app.reportOrientation();
            else, app.Cov_StatusBar.Text = regexprep(app.Cov_StatusBar.Text, '\s*\|\s*Orientation <b>.*?</b>', ''); end
        end

        function k = orientationIndex(app)
            % Selected principal axis, or the detected boresight of the target pattern for 'Auto'.
            k = app.Cov_DropDown_Orientation.Value;
            if k == 0, k = []; node = app.covPatternTarget(); if ~isempty(node), k = node.NodeData.boresight; end, end
        end

        function reportOrientation(app)
            if ~app.Cov_Btn_Conical.Value, return; end
            k = app.orientationIndex(); if isempty(k), return; end
            msg = regexprep(char(app.Cov_StatusBar.Text), '\s*\|\s*Orientation <b>.*?</b>$', '');
            app.setStatus(app.Cov_StatusBar, sprintf('%s | Orientation <b>%s</b>', msg, app.PrincipalAxes.labels{k}), false);
        end

        function Cov_DropDown_OrientationValueChanged(app)
            % Auto follows the detected boresight; an explicit axis is authoritative and never overwritten.
            k = app.orientationIndex(); if isempty(k), return; end
            app.Cov_Spinner_ConeTH.Value = app.PrincipalAxes.theta(k); app.Cov_Spinner_ConePH.Value = app.PrincipalAxes.phi(k); app.reportOrientation();
        end

        function Cov_DropDown_ComponentValueChanged(app)
            node = app.covPatternTarget(); if isempty(node), return; end
            d = node.NodeData; d.component = ''; node.NodeData = d; app.covSync(node); app.reportOrientation();
        end

        function s = coneLabel(app, th, ph)
            % Principal-axis name when the cone centre coincides with ±X/±Y/±Z, otherwise the spherical coordinates.
            A = app.PrincipalAxes; v = [sind(th)*cosd(ph); sind(th)*sind(ph); cosd(th)];
            k = find([sind(A.theta(:)).*cosd(A.phi(:)), sind(A.theta(:)).*sind(A.phi(:)), cosd(A.theta(:))]*v >= 1 - 1e-9, 1);
            if isempty(k), s = sprintf('θ=%s°, φ=%s°', app.fmtNumber(th), app.fmtNumber(ph)); else, s = A.labels{k}; end
        end

        function setPlotRange(app, b, step)
            % Coverage X-axis baseline: the first result sets it; later results may only widen it.
            b = clampRange(b); if app.covPlotInit, b = [min(app.Cov_Axes.XLim(1), b(1)), max(app.Cov_Axes.XLim(2), b(2))]; end
            app.covPlotInit = true; set(app.Cov_Axes, 'XLimMode', 'manual', 'XLim', b);
            set([app.Cov_Spinner_XMin, app.Cov_Spinner_XMax, app.Cov_Spinner_XRange], 'Limits', [-250 100]);
            app.Cov_Spinner_XMin.Value = b(1); app.Cov_Spinner_XMax.Value = b(2); app.Cov_Spinner_XRange.Value = b; app.Cov_Spinner_XRange.Limits = b;
            app.Cov_Spinner_XMin.Limits = [-250, b(2) - 0.1]; app.Cov_Spinner_XMax.Limits = [b(1) + 0.1, 100];
            if ~isempty(step) && isfinite(step) && step < app.Cov_Spinner_Step.Value, app.Cov_Spinner_Step.Value = step; end
        end

        function syncCoverageXRange(app, src, evt)
            % Spinners are the master (they define the slider travel); the slider only moves the selected XLim.
            sl = app.Cov_Spinner_XRange; lo = app.Cov_Spinner_XMin; hi = app.Cov_Spinner_XMax;
            if isequal(src, sl)
                b = sort(evt.Value); if diff(b) <= 0, return; end
                lo.Value = b(1); hi.Value = b(2);
            else
                b = [lo.Value, hi.Value];
                if diff(b) <= 0, if isequal(src, lo), b(2) = min(100, b(1) + 0.1); else, b(1) = max(-250, b(2) - 0.1); end, end
                sl.Limits = [-250 100]; sl.Value = b; sl.Limits = b;
                lo.Value = b(1); hi.Value = b(2); lo.Limits = [-250, b(2) - 0.1]; hi.Limits = [b(1) + 0.1, 100];
            end
            set(app.Cov_Axes, 'XLimMode', 'manual', 'XLim', b);
        end
    end

    %% ================================================================ utilities
    methods (Access = private)
        function setStatus(app, label, msg, transient)
            % Sticky messages are remembered in the label UserData; transient ones are restored after 3 s by one shared timer.
            if app.isClosing || ~isgraphics(label), return; end
            t = app.statusTimer; if strcmp(t.Running, 'on'), stop(t); end
            label.Text = char(msg);
            if nargin > 3 && transient, t.UserData = label; start(t); else, label.UserData = char(msg); end
        end

        function restoreStatus(app, t)
            lbl = t.UserData; if app.isClosing || isempty(lbl) || ~isgraphics(lbl), return; end
            lbl.Text = lbl.UserData;
        end

        function showError(app, ME, ttl)
            if app.isClosing || ~isvalid(app.UIFigure), return; end
            where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.UIFigure, [ME.message where], ttl, 'Icon', 'error');
        end

        function fp = browse(~, ttl)
            [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage files'; '*.*', 'All files'}, ttl);
            if isequal(f, 0), fp = ''; else, fp = fullfile(p, f); end
        end

        function checkCancelled(app)
            if ~isempty(app.opDialog) && isvalid(app.opDialog) && app.opDialog.CancelRequested
                app.opDialog.Message = 'Aborting...'; drawnow limitrate; error('APAT:Cancelled', 'Operation cancelled by user.');
            end
        end

        function s = fmtNumber(~, v, precision)
            % 'n/a' for non-finite; up to 2 decimals with trailing zeros trimmed, or exactly <precision> decimals.
            if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return; end
            if nargin < 3, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); else, s = sprintf('%.*f', precision, v); end
        end

        function done = startPerf(app, op)
            % Stage timer for profiling; the report lands in base-workspace variable Perf_<class>.
            stages = cell(0, 2); t0 = tic; t = tic; app.perf = @track; done = @save;
            function track(name), stages(end+1, :) = {string(name), toc(t)}; t = tic; end
            function save()
                assignin('base', matlab.lang.makeValidName("Perf_" + class(app)), struct('Operation', string(op), ...
                    'Stages', cell2table(stages, 'VariableNames', {'Stage', 'Seconds'}), 'TotalSeconds', toc(t0)));
                app.perf = @(~) [];
            end
        end
    end

    %% ================================================================ UI construction
    methods (Access = private)
        function h = at(~, h, row, col), h.Layout.Row = row; h.Layout.Column = col; end

        function h = lbl(app, parent, text, row, col, varargin)
            h = app.at(uilabel(parent, 'Text', text, 'HorizontalAlignment', 'right', varargin{:}), row, col);
        end

        function dd = formatDropdown(~, parent, cb)
            dd = uidropdown(parent, 'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
                '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'}, ...
                'Value', 'gain', 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'Visible', 'off', 'ValueChangedFcn', cb);
        end

        function createComponents(app)
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.ReleaseName], 'Visible', 'off', 'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) delete(app));
            app.TabGroup = uitabgroup(uigridlayout(app.UIFigure, [1 1]));

            % ---------------------------------------------------------------- Main tab
            app.Tab1_Single = uitab(app.TabGroup, 'Title', 'Process Pattern 📡');
            G = uigridlayout(app.Tab1_Single, [5 14]); G.RowHeight = {'fit', '2x', 'fit', '1x', 'fit'};
            PG = uigridlayout(app.at(uipanel(G, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 14]), [3 14]);
            app.lbl(PG, 'Input Pattern:', 1, 1);
            app.Single_EditField_Path = app.at(uieditfield(PG, 'text'), 1, [2 8]);
            app.FFDFreqDropDownLabel = app.lbl(PG, 'FFD Freq:', 1, 9, 'Visible', 'off');
            app.Single_DropDown_FFD = app.at(uidropdown(PG, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', @(~, ~) app.onFFDChanged()), 1, 10);
            app.Single_Button_Load = app.at(uibutton(PG, 'push', 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.onLoad()), 1, [11 12]);
            app.Single_Button_Process = app.at(uibutton(PG, 'push', 'Text', '⚙️ Process', 'ButtonPushedFcn', @(~, ~) app.onProcess()), 1, [13 14]);
            app.Single_Button_ResetParams = app.at(uibutton(PG, 'push', 'Text', 'Reset Params', 'ButtonPushedFcn', @(~, ~) app.resetParams()), 2, [1 3]);
            app.TextFormatLabel = app.lbl(PG, 'Format:', 2, [4 5], 'Visible', 'off');
            app.Single_DropDown_TextFormat = app.at(app.formatDropdown(PG, @(~, ~) app.onTextFormatChanged()), 2, [6 8]);
            app.Single_DropDown_step = app.at(uidropdown(PG, 'Items', {'STEP'}, 'Visible', 'off', 'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.stepChanged()), 2, [9 10]);
            app.Single_Export_Output = app.at(uibutton(PG, 'push', 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.exportResults()), 2, [11 12]);
            app.Single_Export_UAN = app.at(uibutton(PG, 'push', 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.exportUAN()), 2, [13 14]);
            app.RxPolLabel = app.lbl(PG, 'Rw Sense', 3, 1, 'Visible', 'off');
            app.Single_DropDown_RxPol = app.at(uidropdown(PG, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Editable', 'on', 'Visible', 'off'), 3, 2);
            app.RwLabel = app.lbl(PG, 'Rw (dB)', 3, 3, 'Visible', 'off');
            app.Single_Spinner_Rw = app.at(uispinner(PG, 'Value', 6, 'Visible', 'off'), 3, 4);
            app.LossLabel = app.lbl(PG, 'Loss (−) / Gain (+) dB', 3, 5, 'Visible', 'off');
            app.Single_Spinner_Loss = app.at(uispinner(PG, 'Step', 0.1, 'Visible', 'off'), 3, 6);
            app.PtLabel = app.lbl(PG, 'Tx Pwr (Pt)', 3, 7, 'Visible', 'off');
            app.Single_Spinner_Pt = app.at(uispinner(PG, 'Visible', 'off'), 3, 8);
            app.Single_DropDown_Pt = app.at(uidropdown(PG, 'Items', {'dBW', 'dBm', 'Watts'}, 'Visible', 'off'), 3, 9);
            app.DistanceLabel = app.lbl(PG, 'Distance', 3, 10, 'Visible', 'off');
            app.Single_Spinner_R = app.at(uispinner(PG, 'Value', 1, 'Visible', 'off'), 3, 11);
            app.Single_DropDown_R = app.at(uidropdown(PG, 'Items', {'m', 'km'}, 'Visible', 'off'), 3, 12);
            app.Single_Button_Coverage = app.at(uibutton(PG, 'push', 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.Single_Button_CoveragePushed()), 3, [13 14]);

            % Full-pattern panel: five tabs sharing one layout (max spinner / range slider / min spinner | axes).
            app.Single_Panel_fullPattern = app.at(uipanel(G, 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off', 'BackgroundColor', [0.94 0.94 0.94]), [2 3], [1 6]);
            app.Single_tabPlots = uitabgroup(uigridlayout(app.Single_Panel_fullPattern, [1 1]), 'SelectionChangedFcn', @(~, ~) app.syncAnnotations());
            names = ["contour", "circular", "sphere3D", "polar3D", "rect3D"]; titles = {'Contour Plot', 'Circular Contour Plot', '3D Spherical Plot', '3D Polar Plot', '3D Surface Plot'};
            for k = 1:5
                tab = uitab(app.Single_tabPlots, 'Title', titles{k}); TG = uigridlayout(tab, [3 2]); TG.ColumnWidth = {'fit', '1x'}; TG.RowHeight = {'fit', '1x', 'fit'};
                s = struct('name', names(k), 'tab', tab, 'axes', [], 'range', [], 'minSp', [], 'maxSp', [], 'render', []);
                s.maxSp = app.at(uispinner(TG, 'Limits', [-250 100], 'Value', 100, 'Step', 5, 'ValueChangedFcn', @(src, ~) app.onRange(src.Value, 2, "full")), 1, 1);
                s.range = app.at(uislider(TG, 'range', 'Limits', [-250 100], 'Value', [-250 100], 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(src, ~) app.onRange(src.Value, [], "full")), 2, 1);
                s.minSp = app.at(uispinner(TG, 'Limits', [-250 100], 'Value', -250, 'Step', 5, 'ValueChangedFcn', @(src, ~) app.onRange(src.Value, 1, "full")), 3, 1);
                if k == 2, s.axes = polaraxes(TG); set(s.axes, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise'); else, s.axes = uiaxes(TG, 'Box', 'on'); end
                app.at(s.axes, [1 3], 2);
                if k == 1, app.Full = s; else, app.Full(k) = s; end
            end
            [app.Single_Axes_Ctr, app.Single_paxPattern, app.Single_Axes_3dSph, app.Single_Axes_3dPol, app.Single_Axes_3dRect] = deal(app.Full(1).axes, app.Full(2).axes, app.Full(3).axes, app.Full(4).axes, app.Full(5).axes);
            R = {@() app.drawContour(), @() app.drawFisheye(), @() app.draw3D(app.Single_Axes_3dSph, "sphere"), @() app.draw3D(app.Single_Axes_3dPol, "polar"), @() app.drawRect3()};
            for k = 1:5, app.Full(k).render = R{k}; end

            % Cut panel.
            app.Single_Panel_Rect = app.at(uipanel(G, 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off', 'BackgroundColor', [0.94 0.94 0.94]), [2 3], [7 12]);
            app.Single_tabCut = uitabgroup(uigridlayout(app.Single_Panel_Rect, [1 1]), 'SelectionChangedFcn', @(~, ~) app.syncAnnotations());
            app.Single_tabPolarPlot = uitab(app.Single_tabCut, 'Title', 'Polar Cut Plot');
            CG = uigridlayout(app.Single_tabPolarPlot, [4 4]); CG.ColumnWidth = {'fit', '0.26x', '1x', '0.23x'}; CG.RowHeight = {'fit', '0.25x', '1x', 'fit'};
            app.Range_Cut_Max = app.at(uispinner(CG, 'Limits', [-250 100], 'Value', 100, 'Step', 5, 'ValueChangedFcn', @(src, ~) app.onRange(src.Value, 2, "cut")), 1, 1);
            app.Range_Cut = app.at(uislider(CG, 'range', 'Limits', [-250 100], 'Value', [-250 100], 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(src, ~) app.onRange(src.Value, [], "cut")), [2 3], 1);
            app.Range_Cut_Min = app.at(uispinner(CG, 'Limits', [-250 100], 'Value', -250, 'Step', 5, 'ValueChangedFcn', @(src, ~) app.onRange(src.Value, 1, "cut")), 4, 1);
            app.Single_paxCut = app.at(polaraxes(CG), [1 4], 3); set(app.Single_paxCut, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            app.Button_HPBW = app.at(uibutton(CG, 'state', 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', @(src, ~) app.onCutChanged(src)), 1, 4);
            app.Label_HPBW = app.at(uilabel(CG, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold'), 2, 4);
            app.Single_gridEcut = app.at(uigridlayout(CG, [3 1]), 3, 4);
            app.CheckBox_Et = uicheckbox(app.Single_gridEcut, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', @(src, ~) app.onCutChanged(src));
            app.CheckBox_Er = uicheckbox(app.Single_gridEcut, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', @(src, ~) app.onCutChanged(src));
            app.CheckBox_El = uicheckbox(app.Single_gridEcut, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', @(src, ~) app.onCutChanged(src));
            app.Button_ExportCut = app.at(uibutton(CG, 'push', 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.exportCut()), 4, 4);
            app.Single_tabRectPlot = uitab(app.Single_tabCut, 'Title', 'Rectangular Cut Plot');
            app.Single_AxesRect = uiaxes(uigridlayout(app.Single_tabRectPlot, [1 1]), 'Box', 'on'); ylabel(app.Single_AxesRect, 'Magnitude (dB)');

            % Data tabs (Results / Input / Metadata) and the Results column filter.
            app.Single_DropDown_output = app.at(uidropdown(G, 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Visible', 'off', 'ValueChangedFcn', @(~, ~) app.filterOutput()), 3, [13 14]);
            app.Single_tabData = app.at(uitabgroup(G, 'Visible', 'off'), 4, [1 14]);
            t = uitab(app.Single_tabData, 'Title', 'Results 📤', 'ButtonDownFcn', @(~, ~) set(app.Single_DropDown_output, 'Visible', 'on'));
            app.Single_Table_DataOut = uitable(uigridlayout(t, [1 1]), 'ColumnWidth', '1x', 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true, 'Visible', 'off');
            t = uitab(app.Single_tabData, 'Title', 'Input 📥');
            app.Single_Table_DataIn = uitable(uigridlayout(t, [1 1]), 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true, 'Visible', 'off');
            t = uitab(app.Single_tabData, 'Title', 'Metadata 📋');
            app.Single_Table_metadata = uitable(uigridlayout(t, [1 1]), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});

            % Plot control panel.
            app.Single_Panel_plotControl = app.at(uipanel(G, 'Title', 'Plot Control 🎨', 'Visible', 'off'), 2, [13 14]);
            K = uigridlayout(app.Single_Panel_plotControl, [15 2]); K.RowHeight = repmat({'fit'}, 1, 15);
            app.lbl(K, 'Component', 1, 1);
            app.Single_DropDown_Component = app.at(uidropdown(K, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', @(~, ~) app.onComponentChanged()), 1, 2);
            app.lbl(K, 'Cut type', 2, 1);
            app.Single_DropDown_cutType = app.at(uidropdown(K, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', @(src, ~) app.onCutChanged(src)), 2, 2);
            app.lbl(K, 'Cut value', 3, 1);
            app.Single_DropDown_cutValue = app.at(uispinner(K, 'Limits', [0 360], 'Value', 0, 'ValueChangedFcn', @(src, ~) app.onCutChanged(src)), 3, 2);
            app.lbl(K, 'Cut fields', 4, 1);
            app.CutFieldBasisDropDown = app.at(uidropdown(K, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Enable', 'off', 'ValueChangedFcn', @(src, ~) app.onCutChanged(src)), 4, 2);
            app.lbl(K, 'Colorbar max', 5, 1);
            app.Single_Plot_Cmax = app.at(uispinner(K, 'Limits', [-250 100], 'Value', 10), 5, 2);
            app.lbl(K, 'Colorbar min', 6, 1);
            app.Single_Plot_Cmin = app.at(uispinner(K, 'Limits', [-250 100], 'Value', -40), 6, 2);
            applyAll = @(~, ~) app.onRange([app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value], 0, "all");
            set([app.Single_Plot_Cmin, app.Single_Plot_Cmax], 'ValueChangedFcn', applyAll);
            app.lbl(K, 'Colorbar step', 7, 1);
            app.Single_Plot_Cstep = app.at(uispinner(K, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', @(~, ~) app.applyFullRange(app.ctrLim)), 7, 2);
            app.lbl(K, 'Adjust Colorbar', 8, 1);
            app.at(uibutton(K, 'push', 'Text', 'Apply', 'Tooltip', 'Apply to full-pattern plots and cuts.', 'ButtonPushedFcn', applyAll), 8, 2);
            app.lbl(K, '3D view', 9, 1);
            app.Single_DropDown_3DView = app.at(uidropdown(K, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Tooltip', 'Camera direction for the 3D pattern tabs.', 'ValueChangedFcn', @(~, ~) app.on3DViewChanged()), 9, 2);
            pad = @(n) repmat(char(160), 1, n);   % non-breaking padding balances the switch captions
            app.Single_Switch_AngularSpan = app.at(uiswitch(K, 'slider', 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'ValueChangedFcn', @(~, ~) app.onSpanChanged()), 10, [1 2]);
            app.Single_Switch_ThetaSpan = app.at(uiswitch(K, 'slider', 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'ValueChangedFcn', @(~, ~) app.onSpanChanged()), 11, [1 2]);
            app.Single_Switch_EHplane = app.at(uiswitch(K, 'slider', 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'ValueChangedFcn', @(~, ~) app.Single_Switch_EHplaneValueChanged()), 12, [1 2]);
            app.Single_CheckBox_overlayCut = app.at(uicheckbox(K, 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', @(~, ~) app.drawOverlays()), 13, [1 2]);
            app.Single_CheckBox_POB = app.at(uicheckbox(K, 'Text', 'Annotate POB', 'ValueChangedFcn', @(~, ~) app.syncAnnotations()), 14, [1 2]);
            app.Single_CheckBox_HPBWBounds = app.at(uicheckbox(K, 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', @(~, ~) app.syncAnnotations()), 15, [1 2]);
            app.Single_StatusBar = app.at(uilabel(G, 'Text', 'Ready 🚀', 'Interpreter', 'html'), 5, [1 14]);

            % ---------------------------------------------------------------- Coverage tab
            app.Tab2_Coverage = uitab(app.TabGroup, 'Title', 'Compute Coverage 📈');
            CV = uigridlayout(app.Tab2_Coverage, [3 5]); CV.ColumnWidth = {'0.75x', 'fit', '1x', 'fit', '1x'}; CV.RowHeight = {'0.25x', '1x', 'fit'};
            app.Cov_Panel_Param = app.at(uipanel(CV, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 5]);
            Q = uigridlayout(app.Cov_Panel_Param, [4 10]); Q.ColumnWidth = [{'fit'}, repmat({'1x'}, 1, 9)]; Q.RowHeight = {'1x', 'fit', 'fit', 'fit'}; app.Cov_gridPanel_Parm = Q;
            app.Cov_ButtonGroup_CovType = app.at(uibuttongroup(Q, 'Title', 'Coverage Type', 'SelectionChangedFcn', @(~, ~) app.Cov_ButtonGroup_CovTypeSelectionChanged()), [1 2], [1 2]);
            app.Cov_Btn_Spherical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            app.Cov_Btn_Conical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            app.Cov_DropDown_OrientationLabel = app.lbl(Q, 'Orientation 🧭:', 3, 1, 'Enable', 'off');
            app.Cov_DropDown_Orientation = app.at(uidropdown(Q, 'Items', [{'Auto'}, app.PrincipalAxes.labels], 'ItemsData', 0:6, 'Value', 0, 'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.Cov_DropDown_OrientationValueChanged()), 3, 2);
            app.Cov_DropDown_ComponentLabel = app.lbl(Q, 'Component:', 4, 1, 'Enable', 'off');
            app.Cov_DropDown_Component = app.at(uidropdown(Q, 'Items', {'E_Total_dB'}, 'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.Cov_DropDown_ComponentValueChanged()), 4, 2);
            app.AntennaPatternLabel = app.lbl(Q, 'Antenna Pattern:', 1, 3);
            app.Cov_EditField_filePath = app.at(uieditfield(Q, 'text'), 1, [4 8]);
            app.Cov_Button_Load = app.at(uibutton(Q, 'push', 'Text', '📂 Load File', 'ButtonPushedFcn', @(~, ~) app.Cov_Button_LoadPushed()), 1, 9);
            app.Cov_Button_computeCov = app.at(uibutton(Q, 'push', 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.Cov_Button_computeCovPushed()), 1, 10);
            app.lbl(Q, 'Threshold  Min (dB):', 2, 3); app.Cov_Spinner_ThreshMin = app.at(uispinner(Q, 'Value', -40), 2, 4);
            app.lbl(Q, 'Threshold  Max (dB):', 2, 5); app.Cov_Spinner_ThreshMax = app.at(uispinner(Q, 'Value', 10), 2, 6);
            app.lbl(Q, 'Step (dB):', 2, 7);           app.Cov_Spinner_Step = app.at(uispinner(Q, 'Value', 1), 2, 8);
            app.Cov_Button_Reset = app.at(uibutton(Q, 'push', 'Text', '🔄 Reset', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.Cov_Button_ResetPushed()), 2, 9);
            app.Cov_Button_Export = app.at(uibutton(Q, 'push', 'Text', '💾 Export Results', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.Cov_Button_ExportPushed()), 2, 10);
            l1 = app.lbl(Q, 'Cone θ₀ (°):', 3, 3, 'Enable', 'off');       app.Cov_Spinner_ConeTH = app.at(uispinner(Q, 'Limits', [0 180], 'Enable', 'off'), 3, 4);
            l2 = app.lbl(Q, 'Cone φ₀ (°):', 3, 5, 'Enable', 'off');       app.Cov_Spinner_ConePH = app.at(uispinner(Q, 'Limits', [0 360], 'Enable', 'off'), 3, 6);
            l3 = app.lbl(Q, 'Cone Angle α (°):', 3, 7, 'Enable', 'off');  app.Cov_Spinner_ConeAng = app.at(uispinner(Q, 'Limits', [0 180], 'Value', 45, 'Enable', 'off'), 3, 8);
            app.Cov_ConeControls = [l1, l2, l3, app.Cov_Spinner_ConeTH, app.Cov_Spinner_ConePH, app.Cov_Spinner_ConeAng, app.Cov_DropDown_Orientation, app.Cov_DropDown_OrientationLabel];
            app.Cov_Button_Clear = app.at(uibutton(Q, 'push', 'Text', '🧹 Clear DataTips', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.Cov_Button_ClearPushed()), 3, 9);
            app.Cov_Button_toMain = app.at(uibutton(Q, 'push', 'Text', '📊 To Main ◀ ', 'ButtonPushedFcn', @(~, ~) set(app.TabGroup, 'SelectedTab', app.Tab1_Single)), 3, 10);
            q1 = app.lbl(Q, 'Coverage @ dB:', 4, 3, 'Visible', 'off');
            app.Cov_Spinner_queryCov = app.at(uispinner(Q, 'ValueDisplayFormat', '%g dB', 'Visible', 'off'), 4, 4);
            app.Cov_Button_queryCov = app.at(uibutton(Q, 'push', 'Text', '⯐ Query Coverage', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.covQuery("cov")), 4, 5);
            q2 = app.lbl(Q, 'Threshold @ %:', 4, 6, 'Visible', 'off');
            app.Cov_Spinner_queryThresh = app.at(uispinner(Q, 'Value', 50, 'ValueDisplayFormat', '%g%%', 'Visible', 'off'), 4, 7);
            app.Cov_Button_queryThresh = app.at(uibutton(Q, 'push', 'Text', '🔍 Query Threshold', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.covQuery("thr")), 4, 8);
            app.Cov_QueryControls = [q1, app.Cov_Spinner_queryCov, app.Cov_Button_queryCov, q2, app.Cov_Spinner_queryThresh, app.Cov_Button_queryThresh];
            app.Cov_TextFormatLabel = app.lbl(Q, 'Format:', 4, 9, 'Visible', 'off');
            app.Cov_DropDown_TextFormat = app.at(app.formatDropdown(Q, @(~, ~) app.onCovTextFormatChanged()), 4, 10);
            app.Cov_StatusBar = app.at(uilabel(CV, 'Text', 'Ready 🚀', 'Interpreter', 'html'), 3, [1 5]);
            app.Cov_Panel_Results = app.at(uipanel(CV, 'Title', 'Results', 'Visible', 'off'), 2, [1 5]);
            RG = uigridlayout(app.Cov_Panel_Results, [2 5]); RG.ColumnWidth = {'1x', 'fit', '1x', 'fit', '1x'}; RG.RowHeight = {'1x', 'fit'};
            app.Cov_Tree = app.at(uitree(RG, 'checkbox', 'SelectionChangedFcn', @(~, ~) app.Cov_TreeSelectionChanged(), 'CheckedNodesChangedFcn', @(~, ~) app.Cov_TreeCheckedNodesChanged()), [1 2], 1);
            app.Cov_TreeNode_Results = uitreenode(app.Cov_Tree, 'Text', 'Coverage Results');
            app.Cov_Axes = app.at(uiaxes(RG, 'Box', 'on', 'Layer', 'top', 'YLim', [0 100], 'Interactions', dataTipInteraction), 1, [2 4]);   % display-only axes
            title(app.Cov_Axes, 'Coverage vs Threshold'); xlabel(app.Cov_Axes, 'Threshold (dB)'); ylabel(app.Cov_Axes, 'Coverage (%)'); hold(app.Cov_Axes, 'on'); grid(app.Cov_Axes, 'on');
            app.Cov_Spinner_XMin = app.at(uispinner(RG, 'Limits', [-250 100], 'Value', -40, 'ValueChangedFcn', @(s, e) app.syncCoverageXRange(s, e)), 2, 2);
            app.Cov_Spinner_XRange = app.at(uislider(RG, 'range', 'Limits', [-250 100], 'Value', [-40 10], 'ValueChangedFcn', @(s, e) app.syncCoverageXRange(s, e), 'ValueChangingFcn', @(s, e) app.syncCoverageXRange(s, e)), 2, 3);
            app.Cov_Spinner_XMax = app.at(uispinner(RG, 'Limits', [-250 100], 'Value', 10, 'ValueChangedFcn', @(s, e) app.syncCoverageXRange(s, e)), 2, 4);
            app.Cov_Table = app.at(uitable(RG, 'ColumnWidth', '1x', 'RowName', {}), [1 2], 5);
            app.UIFigure.Visible = 'on';
        end
    end

    %% ================================================================ self-test
    methods (Access = public)
        function report = runSelfTest(app)
            %RUNSELFTEST Deterministic numerical smoke checks of the pure services (throws on failure).
            [P, Th] = meshgrid(0:30:330, 0:30:180); T = table(Th(:), P(:), 10*cosd(Th(:)).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            w = solidWeights(T.Theta, T.Phi); r.passSolidAngle = abs(sum(w) - 4*pi) < 1e-9;
            r.passOrientation = calcOrientation(T, w, 'E_Total_dB', app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB) == 1;
            [P2, T2] = meshgrid(0:2:358, 0:2:180); A = 12*cosd(T2).^2 - 0.5*sind(P2).^2;
            R = resampleTo1Deg(table(T2(:), P2(:), A(:), 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'}));
            r.passResampling = height(R) == 181*361 && all(isfinite(R.Theta)) && all(isfinite(R.Phi));
            native = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0 & R.Phi < 360; expect = 12*cosd(R.Theta).^2 - 0.5*sind(R.Phi).^2;
            r.passNumericalEquivalence = max(abs(R.E_Total_dB(native) - expect(native))) < 1e-9;
            r.passPeakWindow = isequal(peakWindow([3.2; -250; -17], [-50 0], app.PeakPercentile, app.PeakMaxExcessDB), [-45 5]);
            spike = repmat(0.02, 100000, 1); spike(1) = 10.02; pk = resolvePeak(spike, app.PeakPercentile, app.PeakMaxExcessDB);
            r.passIsolatedSpike = pk.wasAdjusted && abs(pk.value - 0.02) < 1e-12 && pk.rawIndex == 1;
            r.passPeakAwareRange = isequal(peakWindow(spike, [-50 0], app.PeakPercentile, app.PeakMaxExcessDB), [-45 5]);
            r.passARTheme = all(cellfun(@(c) app.isAR(c), {'AR', 'AR_dB', 'AR dB', 'Axial Ratio', 'Axial_Ratio'}));
            N = normalizePattern(T); [ang, rows] = cutCircle(N, "Theta", 0);                    % E-plane circle through ±Z (φ=0 ∪ φ=180)
            r.passCutCircle = numel(rows) == 19 && numel(unique(ang)) == 12 && max(ang) == 330 && min(ang) == 0;
            a = (0:359).'; [bw, lo, hi] = calcHPBW(a, -abs(mod(a + 180, 360) - 180)/10);       % triangular beam: −3 dB exactly at ±30°
            r.passHPBW = abs(bw - 60) < 1e-9 && abs(lo + 30) < 1e-9 && abs(hi - 30) < 1e-9;
            f = [tempname '.ffd']; writelines(["0 180 3"; "-180 180 3"; compose('%d 0 0 1', (1:9).')], f); c = onCleanup(@() delete(f));
            d = readPattern(f, 'ffd'); r.passFFDReader = strcmp(d.meta.source, 'HFSS FFD') && isscalar(d.blocks) && height(d.blocks{1}) == 9;
            r.pass = all(structfun(@(v) v, r)); report = r;
            if ~report.pass
                fn = fieldnames(r); error('apat:test:SelfTestFailed', 'Self-test failed: %s', strjoin(fn(~structfun(@(v) v, r)), ', '));
            end
        end
    end
end

%% ==================================================================== I/O services (UI independent)
function src = readPattern(fp, fmt, cached)
%readPattern Read any supported pattern/coverage file into src{raw, blocks, freqs, meta}.
%   blocks{k} is a canonical table {Theta,Phi,Re_Eth,Im_Eth,Re_Eph,Im_Eph} (or a gain table for gain-only sources).
if nargin < 3, cached = table(); end
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
src = struct('raw', table(), 'blocks', {{}}, 'freqs', NaN, 'meta', sourceMeta(ext));
switch ext
    case {'XLSX', 'XLS'},       src = readExcelMatrix(fp);
    case {'CSV', 'TXT', 'DAT'}, src = readGenericText(fp, string(fmt), cached, src);
    case 'CUT',                 src = readGraspCut(fp, src);
    otherwise
        assert(ismember(ext, {'FZ', 'UAN', 'OUT', 'FFS', 'FFE', 'FFD'}), 'readFile:unsupported', 'Unsupported format: %s', ext);
        [nHdr, ffd] = scanHeader(fp);
        opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
        M = readmatrix(fp, setvartype(opts, opts.VariableNames, 'double')); M = M(~all(isnan(M), 2), 1:min(end, 6));
        ang = M(:, 1:2);
        switch ext
            case {'FZ', 'UAN'}   % XGTD: Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
                names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}; src.meta.source = ['XGTD ' ext];
                Eth = polarField(M(:, 3), M(:, 5)); Eph = polarField(M(:, 4), M(:, 6));
            case 'OUT'           % TICRA/GRASP: Theta Phi Re/Im POL1(RHCP) Re/Im POL2(LHCP)
                names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; src.meta.source = 'TICRA/GRASP OUT';
                [Eth, Eph] = circularToLinear(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)));
            case 'FFS'           % CST: Phi Theta Re/Im Eth Re/Im Eph
                names = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; src.meta.source = 'CST FFS'; ang = M(:, [2 1]);
                Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
            case 'FFE'           % FEKO: Theta Phi Re/Im Eth Re/Im Eph (further columns ignored)
                names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; src.meta.source = 'FEKO FFE';
                Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
            case 'FFD'           % HFSS: axis header + Re/Im Eth Re/Im Eph rows, optionally one block per frequency
                src = readFFD(M, ffd, src); return
        end
        src.raw = array2table(M(:, 1:6), 'VariableNames', names);
        src.blocks = {fieldTable(ang(:, 1), ang(:, 2), Eth, Eph)};
end
end

function src = readFFD(M, ffd, src)
assert(ffd.isFFD, 'readFile:ffd', 'FFD header (theta/phi ranges) not found.');
th = linspace(ffd.theta(1), ffd.theta(2), ffd.theta(3)).'; ph = linspace(ffd.phi(1), ffd.phi(2), ffd.phi(3)).';
theta = repelem(th, numel(ph)); phi = repmat(ph, numel(th), 1); n = numel(theta);
sep = isnan(M(:, 1)); freqs = [ffd.freq(:); M(sep, 2)]; freqs = freqs(isfinite(freqs)).';   % "Frequency <f>" separator rows
rows = M(~sep, 1:4); assert(mod(size(rows, 1), n) == 0, 'readFile:ffd', 'FFD row count does not match the theta/phi grid.');
nb = size(rows, 1)/n; freqs(end+1:nb) = NaN; freqs = freqs(1:nb);
src.meta.source = 'HFSS FFD'; src.meta.isMultiBlock = nb > 1; src.meta.hasFrequency = any(isfinite(freqs)); src.meta.isDep = src.meta.isMultiBlock || src.meta.hasFrequency;
src.blocks = arrayfun(@(k) fieldTable(theta, phi, complex(rows((k-1)*n + (1:n), 1), rows((k-1)*n + (1:n), 2)), complex(rows((k-1)*n + (1:n), 3), rows((k-1)*n + (1:n), 4))), 1:nb, 'UniformOutput', false);
src.freqs = freqs; src.raw = src.blocks{1};
end

function [nHdr, ffd] = scanHeader(fp)
%scanHeader Number of leading non-data lines; recognises the HFSS FFD header (two axis triples [+ Frequencies line]).
fid = fopen(fp, 'r'); assert(fid > 0, 'apat:io:OpenFailed', 'Cannot open file: %s', fp); c = onCleanup(@() fclose(fid));
lines = splitlines(string(fread(fid, 65536, '*char').')); lines = lines(1:min(end, 400));
ffd = struct('isFFD', false, 'theta', [], 'phi', [], 'freq', []); ne = find(strlength(strtrim(lines)) > 0);
tri = nan(2, 3);
for k = 1:min(2, numel(ne)), v = sscanf(char(lines(ne(k))), '%f').'; if numel(v) == 3, tri(k, :) = v; end, end
if all(isfinite(tri(:))) && all(tri(:, 3) >= 1)
    ffd.isFFD = true; ffd.theta = [tri(1, 1:2), round(tri(1, 3))]; ffd.phi = [tri(2, 1:2), round(tri(2, 3))]; nHdr = ne(2);
    if numel(ne) >= 3
        tok = regexp(char(strtrim(lines(ne(3)))), '^frequencies?\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok), nHdr = ne(3); f = sscanf(tok{1}, '%f'); if numel(f) > 1, ffd.freq = f(:); end, end   % a bare count carries no frequency values
    end
    return
end
num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?';   % generic: the header ends at the first line with ≥ 4 numeric fields
isData = ~cellfun(@isempty, regexp(cellstr(lines), ['^\s*' num '(?:[\s,;]+' num '){3,}\s*$'], 'once'));
nHdr = find(isData, 1) - 1; if isempty(nHdr), nHdr = 0; end
end

function src = readGenericText(fp, fmt, T, src)
%readGenericText CSV/TXT/DAT: coverage results, gain-only pattern, or a six-column E-field layout selected by fmt.
if isempty(T)
    opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
    T = rmmissing(readtable(fp, opts));
end
nc = width(T); assert(nc >= 2 && ~isempty(T), 'readFile:InvalidFormat', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHeaders = ~all(startsWith(names, "Var")); c1 = T{:, 1}; c2 = T{:, 2}; src.raw = T;
covHeader = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
if (fmt == "gain" || nc < 6 || covHeader) && all(isfinite(c2)) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')   % coverage results
    if ~hasHeaders, src.raw.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:nc-1))]; end
    src.meta.isCoverage = true; return
end
if fmt == "gain"                                                            % the wider-spanning of the first two columns is phi
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    T = movevars(T, 'Theta', 'Before', 1); if ~hasHeaders, src.raw = T; end
    src.blocks = {T}; src.meta.isGainOnly = true; return
end
assert(nc >= 6, 'readFile:TextEFieldColumns', 'The selected E-field format requires six numeric columns.');
F = T{:, 3:6}; magPhase = endsWith(fmt, "magphase"); layout = "n/a";
if magPhase
    big = max(abs(F), [], 1, 'omitnan') > 100;                              % phase columns exceed 100
    if big(2) && ~big(3), layout = "interleaved"; mc = [1 3]; pc = [2 4]; else, layout = "grouped"; mc = [1 2]; pc = [3 4]; end
    A = polarField(F(:, mc(1)), F(:, pc(1))); B = polarField(F(:, mc(2)), F(:, pc(2)));
else
    A = complex(F(:, 1), F(:, 2)); B = complex(F(:, 3), F(:, 4));
end
if startsWith(fmt, "linear"), Eth = A; Eph = B; comp = ["E_TH", "E_PH"]; rect = ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"];
else
    if startsWith(fmt, "rcp"), [Eth, Eph] = circularToLinear(A, B); else, [Eth, Eph] = circularToLinear(B, A); end
    comp = ["POL1", "POL2"]; rect = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"];
end
if ~hasHeaders
    if magPhase, gen = [comp + "_dB", comp + "_deg"]; if layout == "interleaved", gen = gen([1 3 2 4]); end, else, gen = rect; end
    src.raw.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", gen]);
end
src.meta.source = sprintf('Generic text (%s, %s)', fmt, layout);
src.blocks = {fieldTable(T{:, 1}, T{:, 2}, Eth, Eph)};
end

function src = readGraspCut(fp, src)
%readGraspCut TICRA/GRASP .cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks.
src.meta.source = 'TICRA/GRASP CUT'; L = readlines(fp); L(strlength(strtrim(L)) == 0) = [];
th = {}; ph = {}; D = {}; k = 1; icomp = 1; icut = 1;
while k < numel(L)
    p = sscanf(char(L(k+1)), '%f'); assert(numel(p) >= 7, 'readFile:cut', 'Could not parse a GRASP cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6);
    blk = reshape(sscanf(char(strjoin(L(k+2:k+1+n), ' ')), '%f'), 2*p(7), []).';
    th{end+1, 1} = p(1) + (0:n-1).'*p(2); ph{end+1, 1} = repmat(p(4), n, 1); D{end+1, 1} = blk(:, 1:4); k = k + 2 + n; %#ok<AGROW>
end
th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:});
if icut == 2, [th, ph] = deal(ph, th); end                                  % ICUT = 2: phi swept, theta constant
neg = th < 0; ph(neg) = ph(neg) + 180; th(neg) = -th(neg);                   % fold negative theta onto the opposite phi
if isscalar(unique(ph))                                                     % a single cut is treated as a body of revolution
    reps = (0:10:350).'; m = numel(th); th = repmat(th, numel(reps), 1); ph = repelem(reps, m); D = repmat(D, numel(reps), 1);
end
A = complex(D(:, 1), D(:, 2)); B = complex(D(:, 3), D(:, 4));
if icomp == 2, names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; [Eth, Eph] = circularToLinear(A, B);
else, names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; Eth = A; Eph = B; end
src.raw = array2table([th, ph, D], 'VariableNames', [{'Theta', 'Phi'}, names]); src.blocks = {fieldTable(th, ph, Eth, Eph)};
end

function src = readExcelMatrix(fp)
%readExcelMatrix Excel matrix workbooks: summary sheet + fixed component sheets holding C3-origin dBi/phase matrices.
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"];
lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'readFile:ExcelMatrixFormat', 'Unsupported workbook: expected Eth/Eph and/or RHCP/LHCP component sheets after the summary sheet.');
fmtName = ["Excel Matrix Format 2 (Ercp/Elcp)", "Excel Matrix Format 1 (Eth/Eph)", "Excel Matrix Format 3 (Ercp/Elcp + Eth/Eph)"];
req = [circ(1:4*hasC), lin(1:4*hasL)]; Mtx = struct(); thRef = []; phRef = [];
for s = req
    [th, ph, M] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, s), 1)));
    if isempty(thRef), thRef = th; phRef = ph; end
    assert(numel(th) == numel(thRef) && numel(ph) == numel(phRef) && all(abs(th - thRef) < 1e-9) && all(abs(ph - phRef) < 1e-9), ...
        'readFile:ExcelMatrixGrid', 'All component sheets must share one theta/phi grid.');
    Mtx.(s) = M(:);
end
if hasL, Eth = polarField(Mtx.Etheta_Gain_dBi, Mtx.Etheta_Phase_degrees); Eph = polarField(Mtx.Ephi_Gain_dBi, Mtx.Ephi_Phase_degrees);
else, [Eth, Eph] = circularToLinear(polarField(Mtx.RHCP_Gain_dBi, Mtx.RHCP_Phase_degrees), polarField(Mtx.LHCP_Gain_dBi, Mtx.LHCP_Phase_degrees)); end
[phG, thG] = meshgrid(phRef, thRef); block = fieldTable(thG(:), phG(:), Eth, Eph); raw = block;
for s = req, raw.(s) = Mtx.(s); end
meta = sourceMeta(fmtName(hasC + 2*hasL)); meta.summary = readSummary(fp, sheets(1));
src = struct('raw', raw, 'blocks', {{block}}, 'freqs', NaN, 'meta', meta);
end

function [th, ph, M] = readMatrixSheet(fp, sheet)
% One C3-origin matrix: row 2 = phi axis (C..), column B = theta axis (3..).  readcell keeps worksheet coordinates intact.
C = readcell(fp, 'Sheet', char(sheet)); isNum = @(x) isnumeric(x) && isscalar(x) && isfinite(x);
assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'readFile:ExcelMatrixSheet', 'Sheet "%s" has no C3-origin matrix.', sheet);
pm = cellfun(isNum, C(2, 3:end)); tm = cellfun(isNum, C(3:end, 2));
nPh = find(~pm, 1) - 1; if isempty(nPh), nPh = numel(pm); end
nTh = find(~tm, 1) - 1; if isempty(nTh), nTh = numel(tm); end
assert(nPh > 0 && nTh > 0 && ~any(pm(nPh+1:end)) && ~any(tm(nTh+1:end)), 'readFile:ExcelMatrixAxis', 'Sheet "%s" has a missing or gapped theta/phi axis.', sheet);
ph = cell2mat(C(2, 3:2+nPh)); ph = ph(:); th = cell2mat(C(3:2+nTh, 2)); th = th(:); D = C(3:2+nTh, 3:2+nPh);
assert(all(cellfun(isNum, D(:))), 'readFile:ExcelMatrixSheet', 'Sheet "%s" contains non-numeric matrix samples.', sheet); M = cell2mat(D);
assert(all(diff(th) > 0) && all(diff(ph) > 0) && th(1) >= -1e-9 && th(end) <= 180 + 1e-9 && ph(1) >= -1e-9 && ph(end) < 360 + 1e-9, ...
    'readFile:ExcelMatrixAxis', 'Sheet "%s" needs increasing axes within theta 0..180 and phi 0..360.', sheet);
end

function S = readSummary(fp, sheet)
% Harvest every "Label:" / value pair of the template summary sheet (label in column B, first value in C..E).
S = struct();
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
for r = 1:size(C, 1)
    lbl = C{r, 2}; if ~(ischar(lbl) || isstring(lbl)) || strlength(strtrim(string(lbl))) == 0, continue; end
    vals = C(r, 3:min(5, end)); vals = vals(~cellfun(@(v) isempty(v) || all(ismissing(v)), vals));
    if isempty(vals), continue; end
    S.(matlab.lang.makeValidName(lower(regexprep(char(strtrim(string(lbl))), '[^a-zA-Z0-9]+', '_')))) = vals{1};
end
end

function m = sourceMeta(name)
m = struct('source', char(name), 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'isMultiBlock', false, 'hasFrequency', false);
end

function tf = isGenericText(fp)
[~, ~, ext] = fileparts(fp); tf = ismember(lower(ext), {'.csv', '.txt', '.dat'});
end

function E = polarField(dB, deg), E = 10.^(dB/20).*exp(1i*deg2rad(deg)); end

function [Eth, Eph] = circularToLinear(Ercp, Elcp), Eth = (Ercp + Elcp)/sqrt(2); Eph = (Ercp - Elcp)/(1i*sqrt(2)); end

function T = fieldTable(theta, phi, Eth, Eph)
T = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

%% ==================================================================== math services (UI independent)
function T = normalizePattern(T)
%normalizePattern Map angles onto the canonical sphere: θ∈[0,180], φ∈[0,360) plus one closing φ=360 copy of φ=0.
th = T.Theta;
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, T.Theta = 90 - th;                              % elevation convention
    else, T.Theta(th < 0) = -th(th < 0); T.Phi(th < 0) = T.Phi(th < 0) + 180; end        % negative θ = opposite φ
end
T.Theta = mod(T.Theta, 360); over = T.Theta > 180; T.Theta(over) = 360 - T.Theta(over); T.Phi(over) = T.Phi(over) + 180;
num = varfun(@isnumeric, T, 'OutputFormat', 'uniform'); T{:, num} = round(T{:, num}, 5);   % remove 1e-15 seam artefacts once
T.Phi = mod(T.Phi, 360); [~, u] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(u, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function T = displayFrame(T, signedPhi, elevation)
%displayFrame Apply the selected φ/θ display conventions to a canonical table (display only; never fed back to physics).
if signedPhi
    T(abs(T.Phi - 360) < 1e-9, :) = []; T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
    seam = T(abs(T.Phi - 180) < 1e-9, :); seam.Phi(:) = -180; T = [seam; T];
end
if elevation, T.Theta = 90 - T.Theta; end
if signedPhi || elevation, T = sortrows(T, {'Phi', 'Theta'}); end
end

function R = resampleTo1Deg(T)
%resampleTo1Deg Resample a canonical source table onto the 1° θ×φ grid (φ periodic, closing seam included).
%   Primitive quantities only: Re/Im fields directly, gain-like columns as linear power.  Regular grids use interp2.
keep = ~(abs(T.Phi - 360) < 1e-9); [~, u] = unique([T.Theta(keep), mod(T.Phi(keep), 360)], 'rows', 'stable'); idx = find(keep); T = T(idx(u), :);
theta = T.Theta; phi = mod(T.Phi, 360); ut = unique(theta); up = unique(phi);
[qPhi, qTheta] = meshgrid(0:360, 0:180); R = table(qTheta(:), qPhi(:), 'VariableNames', {'Theta', 'Phi'});
regular = numel(ut)*numel(up) == numel(theta);
if regular, [~, it] = ismember(theta, ut); [~, ip] = ismember(phi, up); lin = sub2ind([numel(ut), numel(up)], it, ip); regular = numel(unique(lin)) == numel(lin); end
names = T.Properties.VariableNames(3:end); isField = all(ismember({'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}, names));
for k = 1:numel(names)
    v = double(T.(names{k})); asPower = ~isField && isGainDB(names{k}); if asPower, v = 10.^(v/10); end
    if regular
        G = nan(numel(ut), numel(up)); G(lin) = v;
        q = interp2([up(end) - 360; up; up(1) + 360], ut, [G(:, end), G, G(:, 1)], qPhi, qTheta, 'linear', NaN);   % periodic φ padding
    else
        F = scatteredInterpolant(phi, theta, v, 'linear', 'nearest'); q = F(qPhi, qTheta);
    end
    if asPower, q = 10*log10(max(q, realmin)); end
    R.(names{k}) = q(:);
end
R.Properties.UserData = T.Properties.UserData;
end

function tf = isGainDB(name)
key = lower(regexprep(char(name), '[^a-zA-Z0-9]', '')); tf = contains(key, {'gain', 'directivity', 'eirp'}) || endsWith(key, 'db');
end

function [P, info] = calcPattern(S, p)
%calcPattern Canonical source table → processed pattern table with every derived quantity (one vectorised pass).
meta = S.Properties.UserData; info = struct('pol', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
if meta.isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + p.GainLoss_dB; end
    return
end
Eth = complex(S.Re_Eth, S.Im_Eth)*p.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph)*p.FieldScale;
Ercp = (Eth + 1i*Eph)/sqrt(2); Elcp = (Eth - 1i*Eph)/sqrt(2);
mT = abs(Eth); mP = abs(Eph); mR = abs(Ercp); mL = abs(Elcp); total = 10*log10(max(mT.^2 + mP.^2, eps));
% Dominant polarisation from mean component power: orders the co/cross pairs, labels the pattern, drives the Auto Rx sense.
pw = [mean(mT.^2, 'omitnan'), mean(mP.^2, 'omitnan'), mean(mR.^2, 'omitnan'), mean(mL.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = char("Circular (" + replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]) + ")");
elseif pw(1) >= pw(2), info.pol = 'Linear (Vertical)'; else, info.pol = 'Linear (Horizontal)'; end
% Signed axial ratio: + RHCP sense, − LHCP sense; equal circular components (linear limit) use the −100 dB floor.
d = mR - mL; sense = sign(d); sense(~isfinite(d)) = 0; ar = (mR + mL)./max(abs(d), eps);
arDB = min(20*log10(ar), 250).*sense; arDB(isfinite(d) & abs(d) <= eps*max(mR + mL, 1)) = -100;
% Polarisation loss factor against an incident wave of axial ratio Rw (worst-case 90° tilt mismatch, cos 2Δτ = −1).
if p.RxMode == "Auto", ws = 2*(info.pairs.Circular(1) == "E_RCP") - 1; elseif p.RxMode == "RHCP", ws = 1; else, ws = -1; end
ra = ar.*sense; ra(sense == 0) = 1e12; rw = ws*10^(p.RxAR_dB/20);
plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1))./(2*(ra.^2 + 1)*(rw^2 + 1)); plfDB = 10*log10(min(max(plf, eps), 1));
eirp = p.Pt_dBW + total; eirpW = 10.^(eirp/10); dB = @(m) 20*log10(max(m, eps)); ph = @(z) rad2deg(angle(z));
P = table(S.Theta, S.Phi, total, arDB, dB(mR), dB(mL), plfDB, total + plfDB, dB(mT), dB(mP), ph(Eth), ph(Eph), ph(Ercp), ph(Elcp), eirp, eirpW/(4*pi*p.R_m^2), sqrt(30*eirpW)/p.R_m, ...
    'VariableNames', {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', 'PLF_dB', 'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', ...
    'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
P.Properties.UserData = meta;
end

function pk = resolvePeak(v, pct, excess)
%resolvePeak Effective peak: the raw maximum unless it exceeds the P<pct> level by more than <excess> dB, in which case
%   the highest sample at or below that level is used and the samples above it are flagged as outliers.
v = double(v(:)); ok = isfinite(v);
pk = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(v)), 'wasAdjusted', false);
if ~any(ok), return; end
[pk.rawValue, pk.rawIndex] = max(v, [], 'omitnan'); pk.value = pk.rawValue; pk.index = pk.rawIndex;
level = prctile(v(ok), pct);
if pk.rawValue > level + excess
    mask = ok & v > level; cand = v; cand(~ok | mask) = -Inf;
    if any(isfinite(cand)), [pk.value, pk.index] = max(cand); pk.outlierMask = mask; pk.wasAdjusted = true; end
end
end

function b = peakWindow(values, fallback, pct, excess)
%peakWindow 50-dB display window whose top is the effective peak rounded up to the next 5 dB (clamped to [-250, 100]).
b = fallback; v = values(isfinite(values)); if isempty(v), return; end
top = resolvePeak(v, pct, excess).value; if ~isfinite(top), return; end
top = min(100, ceil(top/5)*5); b = [max(-250, top - 50), top];
end

function r = clampRange(v)
%clampRange Sorted range clamped to [-250, 100] and at least 1 dB wide.
v = sort(double(v(:).')); if numel(v) < 2 || any(~isfinite(v(1:2))), r = [-250 100]; return; end
r = [max(-250, v(1)), min(100, v(2))];
if diff(r) < 1, r(2) = min(100, r(1) + 1); r(1) = max(-250, r(2) - 1); end
end

function w = solidWeights(theta, phi)
%solidWeights Exact solid angle of each uniform θ×φ cell; the closing φ=360 copy carries zero weight.
dt = gridStep(theta); dp = gridStep(mod(phi, 360)); if ~isfinite(dt), dt = 180; end, if ~isfinite(dp), dp = 360; end
w = (cosd(max(theta - dt/2, 0)) - cosd(min(theta + dt/2, 180)))*deg2rad(dp); w(abs(phi - 360) < 1e-9) = 0;
end

function step = gridStep(values)
%gridStep Smallest positive spacing between distinct finite values (NaN when undefined).
d = diff(unique(values(isfinite(values)))); d = d(d > 1e-9); if isempty(d), step = NaN; else, step = min(d); end
end

function [g, col] = chooseGain(T, requested)
%chooseGain Requested column, else E_Total_dB, else the first data column.
vars = T.Properties.VariableNames; cand = [string(requested), "E_Total_dB"]; k = find(ismember(cand, string(vars)), 1);
if isempty(k), col = vars{3}; else, col = char(cand(k)); end
g = T.(col);
end

function [cols, labels] = componentMap(T)
%componentMap Plot-selectable columns with their user-facing labels.
avail = string(T.Properties.VariableNames(3:end));
if T.Properties.UserData.isGainOnly, cols = avail; labels = avail; return; end
cols = ["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "AR_dB", "Gain_PolCorrected_dB"];
labels = ["Total Gain", "Etheta Gain", "Ephi Gain", "RHCP Gain", "LHCP Gain", "Axial Ratio", "Polarized Gain"];
keep = ismember(cols, avail); cols = cols(keep); labels = labels(keep);
end

function c = preferredComponent(prev, cols)
if any(cols == string(prev)), c = char(prev); elseif any(cols == "E_Total_dB"), c = 'E_Total_dB'; else, c = char(cols(1)); end
end

function k = calcOrientation(T, solid, comp, axes, pct, excess)
%calcOrientation Principal axis whose 45° cone captures the most peak-normalised radiated power (physical frame).
g = chooseGain(T, comp); pk = resolvePeak(g, pct, excess); if pk.wasAdjusted, g(pk.outlierMask) = NaN; end
w = 10.^((g - pk.value)/10).*solid; w(~isfinite(w)) = 0;
A = [sind(axes.theta(:)).*cosd(axes.phi(:)), sind(axes.theta(:)).*sind(axes.phi(:)), cosd(axes.theta(:))];
V = [sind(T.Theta).*cosd(T.Phi), sind(T.Theta).*sind(T.Phi), cosd(T.Theta)];
[~, k] = max(w.'*double(V*A.' >= cosd(45)));
end

function m = calcMetrics(T, solid, axisIdx, axes, pct, excess)
%calcMetrics Scalar antenna metrics of the total gain on the canonical (physical) grid.
g = chooseGain(T, 'E_Total_dB'); pk = resolvePeak(g, pct, excess); gi = g; if pk.wasAdjusted, gi(pk.outlierMask) = NaN; end
Prad = sum(10.^(gi/10).*solid, 'omitnan');                                     % ∫G dΩ (= 4π·η for absolute gain)
D = 10*log10(max(4*pi*10^(pk.value/10)/max(Prad, eps), eps)); eff = 100*Prad/(4*pi); if eff < 0 || eff > 100, eff = NaN; end
th0 = T.Theta(pk.index); ph0 = T.Phi(pk.index);
[~, back] = min(cosd(T.Theta)*cosd(th0) + sind(T.Theta)*sind(th0).*cosd(T.Phi - ph0));
ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(pk.index); end
[eAng, eRows] = cutCircle(T, "Theta", axes.phi(axisIdx));                       % E-plane: θ sweep at the boresight φ
if axes.theta(axisIdx) == 90, [hAng, hRows] = cutCircle(T, "Phi", 90); else, [hAng, hRows] = cutCircle(T, "Theta", 90); end
m = struct('PeakGain_dB', pk.value, 'PeakTheta_deg', th0, 'PeakPhi_deg', ph0, 'HPBW_EPlane_deg', calcHPBW(eAng, g(eRows)), ...
    'HPBW_HPlane_deg', calcHPBW(hAng, g(hRows)), 'FrontBack_dB', pk.value - g(back), 'PeakDirectivity_dB', D, 'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', ar);
end

function [ang, rows, fixed, sym, snapped] = cutCircle(T, type, req)
%cutCircle Rows of one full-circle cut through a canonical table and the circle angle of every row.
if type == "Phi"                                                                % fixed θ, sweep φ
    v = unique(T.Theta); [d, k] = min(abs(v - req)); fixed = v(k); sym = 'θ';
    rows = find(abs(T.Theta - fixed) < 1e-9); ang = T.Phi(rows);
else                                                                            % fixed φ, sweep θ through φ and φ+180
    v = unique(mod(T.Phi, 360)); [d, k] = min(abs(mod(v - req + 180, 360) - 180)); fixed = v(k); sym = 'φ';
    [~, ko] = min(abs(mod(v - fixed, 360) - 180)); p = mod(T.Phi, 360);
    main = find(abs(p - fixed) < 1e-9); opp = find(abs(p - v(ko)) < 1e-9 & T.Theta > 1e-9 & T.Theta < 180 - 1e-9);
    rows = [main; opp]; ang = [T.Theta(main); 360 - T.Theta(opp)];
end
snapped = d > 1e-9;
end

function [bw, lo, hi] = calcHPBW(ang, g, pk, pkAng)
%calcHPBW −3 dB beamwidth of a circular cut (wrap-aware, linear crossing interpolation); NaN when undefined.
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(g); ang = ang(ok); g = g(ok); if numel(g) < 3, return; end
if nargin < 3 || isempty(pk), [pk, i] = max(g); pkAng = ang(i); end
[ra, o] = sort(mod(ang - pkAng + 180, 360) - 180); rg = g(o); half = pk - 3;
L = find(ra < 0 & rg <= half, 1, 'last'); Rr = find(ra > 0 & rg <= half, 1, 'first');
if isempty(L) || isempty(Rr) || L + 1 > numel(rg) || Rr < 2 || rg(L+1) == rg(L) || rg(Rr-1) == rg(Rr), return; end
cross = @(i, j) ra(i) + (ra(j) - ra(i))*(half - rg(i))/(rg(j) - rg(i));
lo = pkAng + cross(L, L+1); hi = pkAng + cross(Rr, Rr-1); bw = hi - lo;
end

function cov = coverageCCDF(gain, mask, thr, solid)
%coverageCCDF Coverage(T) [%] = 100·Σ I(G_i > T)·Ω_i / Σ Ω_i over the region, for every threshold at once.
ok = mask(:) & isfinite(gain(:)) & isfinite(solid(:)) & solid(:) >= 0; g = gain(ok); w = solid(ok);
cov = zeros(numel(thr), 1); if isempty(g) || sum(w) <= 0, return; end
cov = 100*(w.'*(g > thr(:).')).'/sum(w);
end