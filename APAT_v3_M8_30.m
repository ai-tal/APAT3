classdef APAT_v3_M8_30 < matlab.apps.AppBase %1995-lines
% APAT v3 M8 — Antenna Pattern Analyzer Tool (consolidated single-truth architecture).
%
% DATA FLOW (one direction, one canonical representation)
%   file ──readPattern──▶ rawTbl / stdTbl   canonical source: θ∈[0,180], φ∈[0,360] (closed seam),
%                                             complex Eθ/Eφ primitives or gain-only columns
%        ──calcPattern──▶ patTbl            native-resolution processed table
%        ──buildView────▶ viewTbl           = patTbl, or calcPattern(resample(stdTbl,1°))  [canonical, physical angles]
%        ──updateView───▶ grid cache · solid-angle weights · peak (POB) · boresight axis · antenna metrics
%        ──render───────▶ 5 full-pattern plots · polar/rectangular cut · results/metadata tables
%   Coverage tab consumes viewTbl (or any independently loaded pattern) → solid-angle weighted CCDF curves.
%
% DISPLAY CONVENTIONS (φ span 0..360 / −180..180, θ span 0..180 / elevation −90..90) are pure view
% transforms (toDisplay / displayTable / gridData). Canonical tables are never rewritten, so every
% physical computation (orientation, metrics, coverage, cuts) is exact in every display mode.
%
% Optional profiling: app.Verbose = true prints per-stage timings to the Command Window.

    properties (Access = public)  % ---------------------------------- UI handles
        UIFigure matlab.ui.Figure
        TabGroup matlab.ui.container.TabGroup
        Tab1_Single matlab.ui.container.Tab
        Tab2_Coverage matlab.ui.container.Tab
        Labels struct = struct()                 % named label handles toggled together with their controls
        % Main tab — inputs & parameters
        Single_EditField_Path matlab.ui.control.EditField
        Single_Button_Coverage matlab.ui.control.Button
        Single_Export_Output matlab.ui.control.Button
        Single_Export_UAN matlab.ui.control.Button
        Single_DropDown_FFD matlab.ui.control.DropDown
        Single_DropDown_TextFormat matlab.ui.control.DropDown
        Single_DropDown_step matlab.ui.control.DropDown
        Single_DropDown_RxPol matlab.ui.control.DropDown
        Single_Spinner_Rw matlab.ui.control.Spinner
        Single_Spinner_Loss matlab.ui.control.Spinner
        Single_Spinner_Pt matlab.ui.control.Spinner
        Single_DropDown_Pt matlab.ui.control.DropDown
        Single_Spinner_R matlab.ui.control.Spinner
        Single_DropDown_R matlab.ui.control.DropDown
        Single_StatusBar matlab.ui.control.Label
        % Main tab — plot control
        Single_Panel_plotControl matlab.ui.container.Panel
        Single_DropDown_Component matlab.ui.control.DropDown
        Single_DropDown_cutType matlab.ui.control.DropDown
        Single_Spinner_cutValue matlab.ui.control.Spinner
        CutFieldBasisDropDown matlab.ui.control.DropDown
        Single_Plot_Cmax matlab.ui.control.Spinner
        Single_Plot_Cmin matlab.ui.control.Spinner
        Single_Plot_Cstep matlab.ui.control.Spinner
        Single_DropDown_3DView matlab.ui.control.DropDown
        Single_Switch_AngularSpan matlab.ui.control.Switch
        Single_Switch_ThetaSpan matlab.ui.control.Switch
        Single_Switch_EHplane matlab.ui.control.Switch
        Single_CheckBox_overlayCut matlab.ui.control.CheckBox
        Single_CheckBox_POB matlab.ui.control.CheckBox
        Single_CheckBox_HPBWBounds matlab.ui.control.CheckBox
        % Main tab — full-pattern plots
        Single_Panel_fullPattern matlab.ui.container.Panel
        Single_Axes_Ctr matlab.ui.control.UIAxes
        Single_paxPattern matlab.graphics.axis.PolarAxes
        Single_Axes_3dSph matlab.ui.control.UIAxes
        Single_Axes_3dPol matlab.ui.control.UIAxes
        Single_Axes_3dRect matlab.ui.control.UIAxes
        Range_Ctr matlab.ui.control.RangeSlider
        Range_Ctr_Min matlab.ui.control.Spinner
        Range_Ctr_Max matlab.ui.control.Spinner
        Range_Cir matlab.ui.control.RangeSlider
        Range_Cir_Min matlab.ui.control.Spinner
        Range_Cir_Max matlab.ui.control.Spinner
        Range_3dSph matlab.ui.control.RangeSlider
        Range_3dSph_Min matlab.ui.control.Spinner
        Range_3dSph_Max matlab.ui.control.Spinner
        Range_3dPol matlab.ui.control.RangeSlider
        Range_3dPol_Min matlab.ui.control.Spinner
        Range_3dPol_Max matlab.ui.control.Spinner
        Range_3dRect matlab.ui.control.RangeSlider
        Range_3dRect_Min matlab.ui.control.Spinner
        Range_3dRect_Max matlab.ui.control.Spinner
        % Main tab — cut plots
        Single_Panel_Rect matlab.ui.container.Panel
        Single_paxCut matlab.graphics.axis.PolarAxes
        Single_AxesRect matlab.ui.control.UIAxes
        Range_Cut matlab.ui.control.RangeSlider
        Range_Cut_Min matlab.ui.control.Spinner
        Range_Cut_Max matlab.ui.control.Spinner
        Button_HPBW matlab.ui.control.StateButton
        Label_HPBW matlab.ui.control.Label
        Single_gridEcut matlab.ui.container.GridLayout
        CheckBox_Et matlab.ui.control.CheckBox
        CheckBox_Er matlab.ui.control.CheckBox
        CheckBox_El matlab.ui.control.CheckBox
        % Main tab — data tables
        Single_tabData matlab.ui.container.TabGroup
        Single_Table_DataOut matlab.ui.control.Table
        Single_Table_DataIn matlab.ui.control.Table
        Single_Table_metadata matlab.ui.control.Table
        Single_DropDown_output matlab.ui.control.DropDown
        % Coverage tab
        Cov_gridPanel_Parm matlab.ui.container.GridLayout
        Cov_Panel_Results matlab.ui.container.Panel
        Cov_EditField_filePath matlab.ui.control.EditField
        Cov_Button_Load matlab.ui.control.Button
        Cov_Button_computeCov matlab.ui.control.Button
        Cov_Button_Reset matlab.ui.control.Button
        Cov_Button_Export matlab.ui.control.Button
        Cov_Button_Clear matlab.ui.control.Button
        Cov_Button_toMain matlab.ui.control.Button
        Cov_Button_queryCov matlab.ui.control.Button
        Cov_Button_queryThresh matlab.ui.control.Button
        Cov_DropDown_TextFormat matlab.ui.control.DropDown
        Cov_DropDown_Component matlab.ui.control.DropDown
        Cov_DropDown_Orientation matlab.ui.control.DropDown
        Cov_Spinner_ThreshMin matlab.ui.control.Spinner
        Cov_Spinner_ThreshMax matlab.ui.control.Spinner
        Cov_Spinner_Step matlab.ui.control.Spinner
        Cov_Spinner_ConeTH matlab.ui.control.Spinner
        Cov_Spinner_ConePH matlab.ui.control.Spinner
        Cov_Spinner_ConeAng matlab.ui.control.Spinner
        Cov_Spinner_queryCov matlab.ui.control.Spinner
        Cov_Spinner_queryThresh matlab.ui.control.Spinner
        Cov_ButtonGroup_Btn_Conical matlab.ui.control.RadioButton
        Cov_Tree matlab.ui.container.CheckBoxTree
        Cov_TreeNode_Results matlab.ui.container.TreeNode
        Cov_Axes matlab.ui.control.UIAxes
        Cov_Table matlab.ui.control.Table
        Cov_Spinner_XMin matlab.ui.control.Spinner
        Cov_Spinner_XMax matlab.ui.control.Spinner
        Cov_Slider_XRange matlab.ui.control.RangeSlider
        Cov_StatusBar matlab.ui.control.Label
        Verbose logical = false                  % print stage timings
    end

    properties (Access = private)  % ---------------------------------- application state
        % source
        fileName char = ''
        filePath char = ''
        folderPath char = ''
        baseName char = ''
        rawTbl table                             % file content as parsed (Input tab)
        sourceCache table                        % generic text table exactly as read (for format reinterpretation)
        stdTbl table                             % canonical primitives of the active block
        ffdBlocks cell = {}
        freqs double = NaN
        srcUD struct = struct('source', 'n/a', 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'hasFrequency', false)
        % derived
        patTbl table                             % processed, native resolution
        viewTbl table                            % processed table shown/exported/analysed (canonical angles)
        viewRevision double = 0                  % bumps whenever viewTbl content changes
        grid struct = struct()                   % topology/geometry/component cache of viewTbl for the active display convention
        solidAngle double = []                   % dΩ per viewTbl row
        peakInfo struct = struct('wasAdjusted', false)
        POB double = NaN
        POBth double = NaN
        POBph double = NaN
        polLabel char = 'n/a'
        polPairs struct = struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"])
        boresightIndex double = 1
        metrics struct = struct()
        % user intent
        useOneDegree logical = false             % "STEP: 1°" selected
        autoCutBasis logical = true              % cut field basis follows detected polarization until the user picks one
        outputColumns cell = {}
        outputMask logical = logical.empty
        gainLim double = [-40, 10]               % persistent non-AR colour scale
        fullLim double = [-40, 10]               % active full-pattern scale (AR uses ±30 dB)
        cutLim double = [-40, 10]
        defaultParams struct = struct()
        % coverage
        covRunID double = 0
        covPresetKey char = ''
        covThreshInit logical = false
        covXInit logical = false
        CovQueryControls
        CovConeControls
        % lifecycle
        isClosing logical = false
        statusTimer = []
        operationDialog = []
        plotMenu matlab.ui.container.ContextMenu
        stageClock uint64 = uint64(0)
    end

    properties (Constant, Access = private)
        PrincipalAxes = struct('labels', {{'+Z', '-Z', '+X', '-X', '+Y', '-Y'}}, 'theta', [0, 180, 90, 90, 90, 90], 'phi', [0, 0, 0, 180, 90, 270])
        HiddenOutputColumns = {'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'}
        PeakPercentile = 99.99
        PeakMaxExcessDB = 6
        DistanceFloorM = 1e-12
        FileFilter = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage files'; '*.*', 'All files'}
        ReleaseName = 'APAT v3 Milestone 8'
    end

    % ====================================================================== PIPELINE
    methods (Access = private)
        function loadSource(app, out, fp)
            % Install a parsed source as the active Main-tab pattern and process block 1.
            app.filePath = fp; [app.folderPath, app.baseName, ext] = fileparts(fp); app.fileName = [app.baseName, ext];
            app.Single_EditField_Path.Value = fp;
            [app.rawTbl, app.sourceCache, app.ffdBlocks, app.freqs, app.srcUD] = deal(out.rawTbl, out.cache, out.blocks, out.freqs, out.userData);
            isDep = out.userData.isDep;
            if isDep
                items = compose('Pattern %d: %.4g GHz', [(1:numel(out.blocks))', out.freqs(:) / 1e9]);
                items(isnan(out.freqs(:))) = compose('Pattern %d', find(isnan(out.freqs(:))));
                [app.Single_DropDown_FFD.Items, app.Single_DropDown_FFD.Value] = deal(items, items{1});
            end
            set([app.Labels.FFD, app.Single_DropDown_FFD], 'Visible', isDep, 'Enable', isDep);
            set([app.Labels.Format, app.Single_DropDown_TextFormat], 'Visible', isGenericText(fp));
            app.useOneDegree = false; app.autoCutBasis = true;
            app.selectBlock(1);
        end

        function selectBlock(app, k)
            block = app.ffdBlocks{k};
            if app.srcUD.isDep, app.rawTbl = block; end
            app.stdTbl = normalizePattern(block); app.stdTbl.Properties.UserData = app.srcUD;
            app.process();
        end

        function process(app)
            % The single full refresh path: stdTbl → patTbl → viewTbl → derived state → every visual.
            [app.patTbl, info] = calcPattern(app.stdTbl, app.getParam(), app.PeakPercentile, app.PeakMaxExcessDB);
            app.tick("Process pattern"); app.checkCancelled();
            [app.polLabel, app.polPairs] = deal(info.pol, info.pairs);
            hasEField = ~app.srcUD.isGainOnly;
            if app.autoCutBasis && hasEField
                if startsWith(info.pol, 'Linear'), app.CutFieldBasisDropDown.Value = 'Linear'; else, app.CutFieldBasisDropDown.Value = 'Circular'; end
            end
            % Angular-step selector is offered only for non-1° sources.
            [thetaStep, phiStep] = app.nativeSteps(); nonCanonical = abs(thetaStep - 1) > 1e-9 || abs(phiStep - 1) > 1e-9;
            items = {sprintf('STEP: %g°', max(thetaStep, phiStep)), 'STEP: 1°'};
            app.Single_DropDown_step.Items = items; app.Single_DropDown_step.Value = items{1 + (app.useOneDegree && nonCanonical)};
            set(app.Single_DropDown_step, 'Visible', nonCanonical, 'Enable', nonCanonical);
            app.buildView(); app.setComponentItems(app.Single_DropDown_Component, app.viewTbl);
            app.tick("Prepare view"); app.checkCancelled();
            [app.Single_Table_DataIn.Data, app.Single_Table_DataIn.ColumnName] = deal(app.rawTbl, app.rawTbl.Properties.VariableNames);
            set([app.Single_Panel_Rect, app.Single_Export_Output, app.Single_Panel_fullPattern, app.Single_Panel_plotControl, ...
                app.Single_Button_Coverage, app.Single_tabData, app.Single_DropDown_output], 'Visible', 'on');
            set([app.Single_Export_UAN, app.Single_gridEcut, app.CheckBox_Et, app.CheckBox_Er, app.CheckBox_El], 'Visible', hasEField);
            app.CutFieldBasisDropDown.Enable = hasEField;
            app.updateView(true, true); app.tick("Build plots");
            pol = ''; if hasEField, pol = sprintf(' | Polarization <b>%s</b>', app.polLabel); end
            app.setStatus(app.Single_StatusBar, sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)%s', ...
                app.fileName, fmtNum(app.POB, 2), fmtNum(app.POBth), fmtNum(app.POBph), pol), false);
        end

        function [thetaStep, phiStep] = nativeSteps(app)
            thetaStep = gridStep(app.stdTbl.Theta); phiStep = gridStep(app.stdTbl.Phi);
            if ~isfinite(thetaStep), thetaStep = 1; end
            if ~isfinite(phiStep), phiStep = thetaStep; end
        end

        function buildView(app)
            % viewTbl is the native processed table, or the processed 1° resample of the canonical
            % PRIMITIVES (fields / gain) — nonlinear outputs (AR, PLF, …) are never interpolated.
            [thetaStep, phiStep] = app.nativeSteps(); source = app.stdTbl;
            resample = app.useOneDegree && (abs(thetaStep - 1) > 1e-9 || abs(phiStep - 1) > 1e-9);
            if resample
                if thetaStep < 1 && phiStep < 1   % integer-degree subset is exact: no interpolation needed
                    source = source(abs(source.Theta - round(source.Theta)) < 1e-9 & abs(source.Phi - round(source.Phi)) < 1e-9, :);
                else
                    source = resampleCanonical(source, 1);
                end
                source.Properties.UserData = app.srcUD;
                app.viewTbl = calcPattern(source, app.getParam(), app.PeakPercentile, app.PeakMaxExcessDB);
            else
                app.viewTbl = app.patTbl;
            end
            app.viewRevision = app.viewRevision + 1; app.grid = struct();
        end

        function param = getParam(app)
            param = struct('GainLoss_dB', app.Single_Spinner_Loss.Value, 'RxMode', string(app.Single_DropDown_RxPol.Value), 'RxAR_dB', app.Single_Spinner_Rw.Value);
            param.FieldScale = 10 .^ (param.GainLoss_dB / 20);
            power = app.Single_Spinner_Pt.Value;
            switch app.Single_DropDown_Pt.Value
                case 'dBm',   param.Pt_dBW = power - 30;
                case 'Watts', param.Pt_dBW = 10 * log10(max(power, eps));
                otherwise,    param.Pt_dBW = power;
            end
            param.R_m = max(app.Single_Spinner_R.Value, app.DistanceFloorM);
            if strcmp(app.Single_DropDown_R.Value, 'km'), param.R_m = 1000 * param.R_m; end
        end

        function updateView(app, refreshRanges, resetPlane)
            % Derive peak / boresight / metrics from the canonical view, then refresh every visual.
            % resetPlane re-selects the E/H cut plane from the (possibly new) boresight axis.
            T = app.viewTbl; principal = app.PrincipalAxes;
            app.solidAngle = solidWeights(T.Theta, T.Phi);
            [peak, app.boresightIndex] = calcOrientation(T, app.solidAngle, app.comp(), principal, app.PeakPercentile, app.PeakMaxExcessDB);
            app.peakInfo = peak; app.POB = peak.value;
            [app.POBth, app.POBph] = deal(T.Theta(peak.index), mod(T.Phi(peak.index), 360));
            principal.index = app.boresightIndex;
            app.metrics = calcMetrics(T, app.solidAngle, principal, app.PeakPercentile, app.PeakMaxExcessDB);
            if refreshRanges, app.initRanges(); end
            if nargin > 2 && resetPlane, app.selectPlane(); else, app.updateCutControl(); end
            app.updateTables(); app.updateMetadata(); app.renderAll(); app.plotCut();
        end

        function P = buildPattern(app, out)
            % Process an auxiliary source (Coverage tab) with the current parameters; Main state is untouched.
            standard = normalizePattern(out.blocks{1}); standard.Properties.UserData = out.userData;
            P = calcPattern(standard, app.getParam(), app.PeakPercentile, app.PeakMaxExcessDB);
        end

        function out = readSource(app, fp, formatDropdown, cached)
            % I/O boundary: generic text files use the selected interpretation, all other formats are self-describing.
            if nargin < 4, cached = table(); end
            if isGenericText(fp)
                if isempty(cached), formatDropdown.Value = 'gain'; end   % fresh load starts from the neutral interpretation
                out = readPattern(fp, formatDropdown.Value, cached);
            else
                out = readPattern(fp, "auto");
            end
            app.checkCancelled();
        end

        % ------------------------------------------------------------------ display conventions
        function tf = isSignedPhi(app), tf = strcmp(app.Single_Switch_AngularSpan.Value, '-180° to 180°'); end
        function tf = isElevation(app), tf = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°'); end
        function s = thetaLabel(app), if app.isElevation(), s = "Elevation"; else, s = "Theta"; end, end

        function [phi, theta] = toDisplay(app, phi, theta)
            % Canonical angles (θ∈[0,180], φ∈[0,360]) → active display convention.
            if app.isSignedPhi(), phi(phi > 180) = phi(phi > 180) - 360; end
            if nargin > 2 && app.isElevation(), theta = 90 - theta; end
        end

        function T = displayTable(app, T)
            % Canonical table → display convention rows (closed φ seam preserved, sorted by φ then θ).
            signed = app.isSignedPhi(); elevation = app.isElevation();
            if signed
                T(abs(T.Phi - 360) < 1e-9, :) = []; T.Phi = app.toDisplay(T.Phi);
                seam = T(abs(T.Phi - 180) < 1e-9, :); seam.Phi(:) = -180; T = [seam; T];
            end
            if elevation, T.Theta = 90 - T.Theta; end
            if signed || elevation, T = sortrows(T, {'Phi', 'Theta'}); end
        end

        function [G, C] = gridData(app, column)
            % Cached grid topology/geometry of viewTbl (display column order) plus one component matrix.
            G = app.grid; T = app.viewTbl;
            if ~isfield(G, 'sz')
                theta = unique(T.Theta); phi = unique(T.Phi); sz = [numel(theta), numel(phi)];
                [~, ti] = ismember(T.Theta, theta); [~, pj] = ismember(T.Phi, phi);
                cols = (1:sz(2))'; phiD = phi;
                if app.isSignedPhi()
                    cols = find(phi < 360 - 1e-9); [phiD, order] = sort(app.toDisplay(phi(cols))); cols = cols(order);
                    seam = find(abs(phiD - 180) < 1e-9, 1);
                    if ~isempty(seam), cols = [cols(seam); cols]; phiD = [-180; phiD]; end
                end
                thetaD = theta; if app.isElevation(), thetaD = 90 - theta; end
                [phiP, thetaP] = meshgrid(phi(cols), theta);   % physical angles per cell
                [phiG, thetaG] = meshgrid(phiD, thetaD);       % display angles per cell
                G = struct('theta', theta, 'phi', phi, 'sz', sz, 'lin', sub2ind(sz, ti, pj), 'cols', cols, ...
                    'thetaD', thetaD, 'phiD', phiD, 'thetaP', thetaP, 'phiP', phiP, 'thetaG', thetaG, 'phiG', phiG, ...
                    'x', sind(thetaP) .* cosd(phiP), 'y', sind(thetaP) .* sind(phiP), 'z', cosd(thetaP), 'comps', struct());
            end
            key = matlab.lang.makeValidName(column);
            if ~isfield(G.comps, key), C = nan(G.sz); C(G.lin) = T.(column); G.comps.(key) = C(:, G.cols); end
            C = G.comps.(key); app.grid = G;
        end

        % ------------------------------------------------------------------ components & tables
        function [columns, labels] = componentMap(~, T)
            available = string(T.Properties.VariableNames(3:end));
            if T.Properties.UserData.isGainOnly, [columns, labels] = deal(available); return; end
            columns = ["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "AR_dB", "Gain_PolCorrected_dB"];
            labels = ["Total Gain", "Etheta Gain", "Ephi Gain", "RHCP Gain", "LHCP Gain", "Axial Ratio", "Polarized Gain"];
            keep = ismember(columns, available); columns = columns(keep); labels = labels(keep);
        end

        function setComponentItems(app, dropdown, T)
            [columns, labels] = app.componentMap(T); previous = string(dropdown.Value);
            [dropdown.Items, dropdown.ItemsData] = deal(cellstr(labels), cellstr(columns));
            dropdown.Value = char(preferredComponent(previous, columns));
        end

        function c = comp(app), c = app.Single_DropDown_Component.Value; end

        function label = compLabel(app)
            dd = app.Single_DropDown_Component; k = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(k), label = replace(string(dd.Value), '_', ' '); else, label = string(dd.Items{k}); end
        end

        function updateTables(app)
            T = app.displayTable(app.viewTbl); columns = T.Properties.VariableNames(3:end);
            if ~isequal(columns, app.outputColumns)   % new schema → reset the column filter
                app.outputColumns = columns; app.outputMask = ~ismember(columns, app.HiddenOutputColumns);
                app.styleOutputFilter(); dd = app.Single_DropDown_output; [dd.ItemsData, dd.Value] = deal(0:numel(columns), 0);
            end
            app.Single_Table_DataOut.Data = T(:, [true, true, app.outputMask]);
            app.updateInputVisibility();
        end

        function filterOutput(app, ~)
            % Results-table column filter: selecting an entry toggles that column.
            dd = app.Single_DropDown_output;
            if dd.Value > 0, app.outputMask(dd.Value) = ~app.outputMask(dd.Value); dd.Value = 0; app.styleOutputFilter(); app.updateTables(); end
        end

        function styleOutputFilter(app)
            dd = app.Single_DropDown_output; on = find(app.outputMask) + 1;
            dd.Items = [{'--- column filter ---'}, app.outputColumns]; dd.Items(on) = append('✓ ', dd.Items(on));
            removeStyle(dd);
            if ~isempty(on), addStyle(dd, uistyle('FontWeight', 'bold', 'BackgroundColor', [0.8 1 0.8]), 'Item', on); end
            addStyle(dd, uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9]), 'Item', find([true, ~app.outputMask]));
        end

        function updateInputVisibility(app)
            % Parameter controls appear only while a visible result column depends on them.
            shown = string(app.outputColumns(app.outputMask)); L = app.Labels;
            showRx = any(ismember(shown, ["PLF_dB", "Gain_PolCorrected_dB"]));
            showTx = any(ismember(shown, ["EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
            showR = any(ismember(shown, ["PFD_Wm2", "E_RMS_Vm"]));
            showLoss = app.srcUD.isGainOnly || any(ismember(shown, ["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "Gain_PolCorrected_dB", "EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
            set([L.Rx, app.Single_DropDown_RxPol, L.Rw, app.Single_Spinner_Rw], 'Visible', showRx);
            set([L.Pt, app.Single_Spinner_Pt, app.Single_DropDown_Pt], 'Visible', showTx);
            set([L.R, app.Single_Spinner_R, app.Single_DropDown_R], 'Visible', showR);
            set([L.Loss, app.Single_Spinner_Loss], 'Visible', showLoss);
        end

        function updateMetadata(app)
            G = app.gridData(app.comp()); m = app.metrics; ud = app.srcUD;
            rows = {'Source format', ud.source; 'File', app.fileName; ...
                'Samples', sprintf('%d  (θ: %d × φ: %d)', height(app.viewTbl), G.sz(1), numel(G.phiD)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(min(G.thetaD)), fmtNum(max(G.thetaD)), fmtNum(gridStep(G.theta))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(min(G.phiD)), fmtNum(max(G.phiD)), fmtNum(gridStep(G.phi)))};
            f = app.freqs(isfinite(app.freqs));
            if ~isempty(f), rows(end + 1, :) = {'Frequencies', strjoin(compose('%.4g GHz', f(:) / 1e9), ', ')}; end
            if ~ud.isGainOnly
                rows(end + 1, :) = {'Polarization', app.polLabel};
                rows(end + 1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(app.polPairs.(app.CutFieldBasisDropDown.Value), ' / '))};
            end
            rows = [rows; {sprintf('Peak of %s (POB)', app.compLabel()), sprintf('%s dB @ [θ %s°, φ %s°]', fmtNum(app.POB), fmtNum(app.POBth), fmtNum(app.POBph)); ...
                'Peak policy', sprintf('P%.4g + %g dB max excess (adjusted: %s)', app.PeakPercentile, app.PeakMaxExcessDB, string(app.peakInfo.wasAdjusted)); ...
                'Boresight axis', app.PrincipalAxes.labels{app.boresightIndex}; ...
                'Peak total gain', sprintf('%s dB @ [θ %s°, φ %s°]', fmtNum(m.PeakGain_dB), fmtNum(m.PeakTheta_deg), fmtNum(m.PeakPhi_deg)); ...
                'HPBW E-plane / H-plane', sprintf('%s° / %s°', fmtNum(m.HPBW_EPlane_deg), fmtNum(m.HPBW_HPlane_deg)); ...
                'Front-to-back', sprintf('%s dB', fmtNum(m.FrontBack_dB)); ...
                'Peak directivity', sprintf('%s dB', fmtNum(m.PeakDirectivity_dB)); ...
                'Radiation efficiency', sprintf('%s%%', fmtNum(m.Efficiency_pct)); ...
                'AR at peak', sprintf('%s dB', fmtNum(m.AxialRatioAtPeak_dB))}];
            app.Single_Table_metadata.Data = rows;
        end
    end

    % ====================================================================== RENDERING
    methods (Access = private)
        function specs = fullSpecs(app)
            % The five full-pattern views: axes, range controls and renderer, in tab order.
            specs = struct( ...
                'axes',       {app.Single_Axes_Ctr, app.Single_paxPattern, app.Single_Axes_3dSph, app.Single_Axes_3dPol, app.Single_Axes_3dRect}, ...
                'range',      {app.Range_Ctr, app.Range_Cir, app.Range_3dSph, app.Range_3dPol, app.Range_3dRect}, ...
                'minSpinner', {app.Range_Ctr_Min, app.Range_Cir_Min, app.Range_3dSph_Min, app.Range_3dPol_Min, app.Range_3dRect_Min}, ...
                'maxSpinner', {app.Range_Ctr_Max, app.Range_Cir_Max, app.Range_3dSph_Max, app.Range_3dPol_Max, app.Range_3dRect_Max}, ...
                'render',     {@app.drawContour, @app.drawFisheye, @() app.draw3D(app.Single_Axes_3dSph, "sphere"), ...
                               @() app.draw3D(app.Single_Axes_3dPol, "polar"), @app.drawRect3});
        end

        function renderAll(app)
            if isempty(app.viewTbl), return; end
            specs = app.fullSpecs();
            for k = 1:numel(specs), app.checkCancelled(); specs(k).render(); end
            app.drawOverlay(); drawnow limitrate   % surfaces must exist before pinned tips are attached
            if app.Single_CheckBox_POB.Value, app.annotatePOB(); end
        end

        function [limits, map] = plotTheme(app)
            % Signed axial ratio: fixed ±30 dB blue-white-red scale. Everything else: shared gain scale, jet.
            persistent arMap
            if isempty(arMap), arMap = interp1([-1, 0, 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
            limits = app.fullLim; if isAR(app.comp()), map = arMap; else, map = jet(256); end
        end

        function applyTheme(app, ax)
            [limits, map] = app.plotTheme(); clim(ax, limits); colormap(ax, map);
            cb = colorbar(ax); ticks = makeTicks(limits, app.Single_Plot_Cstep.Value);
            if ~isempty(ticks), cb.Ticks = ticks; end
        end

        function applyFullRange(app)
            % Re-apply the full-pattern colour scale without re-rendering the surfaces.
            for spec = app.fullSpecs()
                ax = spec.axes; clim(ax, app.fullLim);
                cb = findall(app.UIFigure, 'Type', 'ColorBar', 'Axes', ax); ticks = makeTicks(app.fullLim, app.Single_Plot_Cstep.Value);
                if ~isempty(cb) && ~isempty(ticks), cb(1).Ticks = ticks; end
            end
            zlim(app.Single_Axes_3dRect, app.fullLim);
        end

        function formatAngularAxes(app, ax, phiStep, thetaStep)
            xl = [0, 360] - 180 * app.isSignedPhi();
            if app.isElevation(), yl = [-90, 90]; dir = 'normal'; else, yl = [0, 180]; dir = 'reverse'; end
            set(ax, 'XLim', xl, 'YLim', yl, 'YDir', dir, 'Box', 'on', 'Layer', 'top', 'XTick', xl(1):phiStep:xl(2), 'YTick', yl(1):thetaStep:yl(2));
        end

        function setPolarTicks(app, pax)
            % Polar geometry stays physical; only the φ labels follow the selected span.
            angles = 0:30:330; if app.isSignedPhi(), angles(angles > 180) = angles(angles > 180) - 360; end
            set(pax, 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', angles), 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
        end

        function setTipTemplate(app, h, G, C)
            % Common DataTip rows (display angles + component value) for every rendered surface.
            rows = [dataTipTextRow(app.thetaLabel(), G.thetaG, '%.3g°'); dataTipTextRow("Phi", G.phiG, '%.3g°'); ...
                dataTipTextRow(replace(app.compLabel(), "_", "\_"), C, '%.3g dB')];
            try, h.DataTipTemplate.DataTipRows = rows; catch, end
            set(findall(h.Parent, '-property', 'ContextMenu'), 'ContextMenu', app.plotMenu);
        end

        function drawContour(app)
            ax = app.Single_Axes_Ctr; [G, C] = app.gridData(app.comp()); delete(allchild(ax));
            s = pcolor(ax, G.phiD, G.thetaD, C); set(s, 'FaceColor', 'interp', 'LineStyle', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(ax); app.formatAngularAxes(ax, 30, 15); daspect(ax, [1 1 1]);
            xlabel(ax, 'Phi (degree)'); ylabel(ax, app.thetaLabel() + " (degree)"); title(ax, app.compLabel(), 'Interpreter', 'none');
            app.setTipTemplate(s, G, C);
        end

        function drawFisheye(app)
            pax = app.Single_paxPattern; [G, C] = app.gridData(app.comp()); delete(allchild(pax));
            s = surface(pax, deg2rad(G.phiP), G.thetaP, zeros(size(C)), C, 'EdgeColor', 'none', 'Tag', 'APAT_Surface');
            app.applyTheme(pax); app.setPolarTicks(pax);
            rt = 0:30:180; if app.isElevation(), rl = 90 - rt; else, rl = rt; end
            set(pax, 'RLim', [0, 180], 'RTick', rt, 'RTickLabel', compose('%d°', rl));
            title(pax, sprintf('%s  |  r=θ, angle=φ', app.compLabel()), 'Interpreter', 'none', 'FontSize', 9);
            app.setTipTemplate(s, G, C);
        end

        function r = polarRadius(app, values)
            % 3-D polar radius: colour-scale-normalised, clipped at the lower limit, peak at 1.
            lim = app.fullLim; r = max(values - lim(1), 0) / max(lim(2) - lim(1), eps);
        end

        function draw3D(app, ax, kind)
            [G, C] = app.gridData(app.comp()); [X, Y, Z] = deal(G.x, G.y, G.z);
            if kind == "polar"
                R = app.polarRadius(C); R = R / max(max(R, [], 'all', 'omitnan'), eps); [X, Y, Z] = deal(R .* X, R .* Y, R .* Z);
            end
            delete(allchild(ax)); hold(ax, 'on');
            s = surf(ax, X, Y, Z, C, 'EdgeColor', 'none', 'Tag', 'APAT_Surface'); app.applyTheme(ax);
            set(ax, 'XLim', [-1.5, 1.5], 'YLim', [-1.5, 1.5], 'ZLim', [-1.5, 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1], 'Projection', 'orthographic', 'Visible', 'off');
            colors = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; names = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            for k = 1:3   % principal axes
                d = 1.35 * (1:3 == k);
                quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12 * d(1), 1.12 * d(2), 1.12 * d(3), names{k}, 'Color', colors{k}, 'FontWeight', 'bold');
            end
            app.apply3DView(ax, [135, 25]);
            title(ax, sprintf('%s  |  θ: %s  |  φ: %s', app.compLabel(), app.Single_Switch_ThetaSpan.Value, app.Single_Switch_AngularSpan.Value), 'Interpreter', 'none');
            app.setTipTemplate(s, G, C); hold(ax, 'off');
        end

        function drawRect3(app)
            ax = app.Single_Axes_3dRect; [G, C] = app.gridData(app.comp()); delete(allchild(ax));
            s = surf(ax, G.phiG, G.thetaG, C, 'EdgeColor', 'none', 'Tag', 'APAT_Surface'); app.applyTheme(ax);
            zlim(ax, app.fullLim); ticks = makeTicks(app.fullLim, app.Single_Plot_Cstep.Value); if ~isempty(ticks), ax.ZTick = ticks; end
            app.formatAngularAxes(ax, 60, 30); grid(ax, 'on'); app.apply3DView(ax, [-35, 35]);
            xlabel(ax, 'Phi (degree)'); ylabel(ax, app.thetaLabel() + " (degree)"); zlabel(ax, app.compLabel() + " (dB)", 'Interpreter', 'none');
            title(ax, app.compLabel(), 'Interpreter', 'none'); app.setTipTemplate(s, G, C);
        end

        function apply3DView(app, ax, iso)
            views = struct('top', [0, 90], 'bottom', [0, -90], 'right', [90, 0], 'left', [-90, 0], 'front', [0, 0], 'back', [180, 0]);
            code = app.Single_DropDown_3DView.Value; up = [0, 0, 1];
            if isfield(views, code), v = views.(code); if abs(v(2)) == 90, up = [0, 1, 0]; end, else, v = iso; end
            view(ax, v(1), v(2)); camup(ax, up);
        end

        function drawOverlay(app)
            % Black cut trace on the 3-D spherical/polar plots (surfaces are never re-rendered for this).
            cut = [];
            for ax = [app.Single_Axes_3dSph, app.Single_Axes_3dPol]
                delete(findall(ax, 'Tag', 'APAT_CutOverlay'));
                if ~app.Single_CheckBox_overlayCut.Value || isempty(app.viewTbl), continue; end
                if isempty(cut), cut = app.cutData(); [~, C] = app.gridData(app.comp()); scale = max(max(app.polarRadius(C), [], 'all', 'omitnan'), eps); end
                if isequal(ax, app.Single_Axes_3dSph), r = 1.02; else, r = 1.01 * app.polarRadius(cut.data(:, 1)) / scale; end
                hold(ax, 'on');
                plot3(ax, r .* sind(cut.theta) .* cosd(cut.phi), r .* sind(cut.theta) .* sind(cut.phi), r .* cosd(cut.theta), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay');
                hold(ax, 'off');
            end
        end

        % ------------------------------------------------------------------ annotations (POB / HPBW)
        function addAnnotation(app, ax, x, y, z, tag, rows, color)
            % One marker plus one pinned DataTip; both carry TAG so syncAnnotations can drive visibility.
            held = ishold(ax); hold(ax, 'on');
            if isa(ax, 'matlab.graphics.axis.PolarAxes'), h = polarplot(ax, x, y, 'o'); else, h = plot3(ax, x, y, z, 'o', 'Clipping', 'off'); end
            set(h, 'MarkerSize', 5, 'Color', color, 'MarkerFaceColor', color, 'HandleVisibility', 'off', 'Tag', tag, 'Visible', 'off');
            h.DataTipTemplate.DataTipRows = rows;
            tip = datatip(h, 'DataIndex', 1, 'FontSize', 9, 'HandleVisibility', 'off', 'Tag', tag, 'Visible', 'off');
            if isequal(ax, app.Single_Axes_Ctr) && abs(y - ax.YLim(1 + strcmp(ax.YDir, 'normal'))) < diff(ax.YLim) / 100, tip.Location = 'southeast'; end
            if ~held, hold(ax, 'off'); end
        end

        function syncAnnotations(app)
            % Markers follow their checkbox; pinned tips additionally hide while their tab is not selected.
            for spec = {'APAT_POB', app.Single_CheckBox_POB.Value; 'APAT_HPBW', app.Single_CheckBox_HPBWBounds.Value}'
                [tag, on] = spec{:};
                for h = findall(app.UIFigure, 'Tag', tag).'
                    tab = ancestor(h, 'uitab'); onTab = isempty(tab) || isequal(tab.Parent.SelectedTab, tab);
                    h.Visible = on && (~strcmp(h.Type, 'datatip') || onTab);
                end
            end
        end

        function annotatePOB(app)
            % Peak marker on every full-pattern plot, placed from the canonical POB direction.
            delete(findall(app.Single_Panel_fullPattern, 'Tag', 'APAT_POB'));
            if ~isfinite(app.POBth), return; end
            [G, C] = app.gridData(app.comp());
            [~, r] = min(abs(G.theta - app.POBth)); [~, c] = min(abs(G.phiP(1, :) - app.POBph));
            [phiD, thetaD] = app.toDisplay(app.POBph, app.POBth); value = C(r, c);
            rows = [dataTipTextRow(app.thetaLabel(), thetaD, '%.3g°'); dataTipTextRow("Phi", phiD, '%.3g°'); dataTipTextRow(app.compLabel(), value, '%.3g dB')];
            R = app.polarRadius(C); radial = R(r, c) / max(max(R, [], 'all', 'omitnan'), eps);
            app.addAnnotation(app.Single_Axes_Ctr, phiD, thetaD, 0, 'APAT_POB', rows, 'k');
            app.addAnnotation(app.Single_paxPattern, deg2rad(app.POBph), app.POBth, 0, 'APAT_POB', rows, 'k');
            app.addAnnotation(app.Single_Axes_3dSph, G.x(r, c), G.y(r, c), G.z(r, c), 'APAT_POB', rows, 'k');
            app.addAnnotation(app.Single_Axes_3dPol, radial * G.x(r, c), radial * G.y(r, c), radial * G.z(r, c), 'APAT_POB', rows, 'k');
            app.addAnnotation(app.Single_Axes_3dRect, phiD, thetaD, value, 'APAT_POB', rows, 'k');
            app.syncAnnotations();
        end

        % ------------------------------------------------------------------ cuts
        function selectPlane(app)
            % E-plane: θ-cut through the boresight φ. H-plane: the orthogonal cut (φ-cut at θ=90° for transverse axes).
            ax = app.PrincipalAxes; k = app.boresightIndex;
            if startsWith(app.Single_Switch_EHplane.Value, 'E'), cutType = 'Theta'; value = ax.phi(k);
            elseif ax.theta(k) == 90, cutType = 'Phi'; value = 90;
            else, cutType = 'Theta'; value = 90;
            end
            app.Single_DropDown_cutType.Value = cutType; app.updateCutControl(value);
        end

        function updateCutControl(app, physicalRequest)
            % The cut-value spinner works in display units and snaps to the nearest available sample.
            isPhiCut = strcmp(app.Single_DropDown_cutType.Value, 'Phi'); spinner = app.Single_Spinner_cutValue;
            if isPhiCut, values = unique(app.viewTbl.Theta); if app.isElevation(), values = sort(90 - values); end
            else, values = unique(mod(app.viewTbl.Phi, 360));
            end
            if nargin < 2, requested = spinner.Value;
            else, requested = physicalRequest; if isPhiCut && app.isElevation(), requested = 90 - requested; end
            end
            [~, k] = min(abs(values - requested));
            spinner.Limits = [-inf, inf]; spinner.Value = values(k); spinner.Limits = [min(values), max(values)];
            if numel(values) > 1, spinner.Step = min(diff(values)); end
        end

        function [cols, idx] = cutCols(app)
            % Selected cut components: Total plus the circular or linear pair; IDX keeps line colours stable.
            if app.srcUD.isGainOnly, [cols, idx] = deal(string(app.viewTbl.Properties.VariableNames(3)), 1); return; end
            if strcmp(app.CutFieldBasisDropDown.Value, 'Linear'), all_ = ["E_Total_dB", "E_TH_dB", "E_PH_dB"]; else, all_ = ["E_Total_dB", "E_RCP_dB", "E_LCP_dB"]; end
            [app.CheckBox_Er.Text, app.CheckBox_El.Text] = deal(char(erase(all_(2), "_dB")), char(erase(all_(3), "_dB")));
            sel = logical([app.CheckBox_Et.Value, app.CheckBox_Er.Value, app.CheckBox_El.Value]); if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = all_(idx);
        end

        function cut = cutData(app)
            % The active cut as one closed 0..360° circle (canonical geometry) mapped to the display φ convention.
            T = app.viewTbl; cutType = string(app.Single_DropDown_cutType.Value); requested = app.Single_Spinner_cutValue.Value;
            if cutType == "Phi" && app.isElevation(), requested = 90 - requested; end
            [angleDeg, rows, fixedAngle, symbol, snapped] = calcCutGeometry(T, cutType, requested);
            [cols, idx] = app.cutCols();
            M = [angleDeg, T.Theta(rows), T.Phi(rows), T{rows, cellstr(cols)}];   % angle | θ | φ | components
            if app.isSignedPhi(), M(M(:, 1) > 180, 1) = M(M(:, 1) > 180, 1) - 360; M = sortrows(M, 1); end
            [~, u] = unique(M(:, 1), 'stable'); M = M(sort(u), :);
            if cutType == "Phi"   % close the circle at the display seam
                lo = -180 * app.isSignedPhi(); hi = lo + 360; hasLo = abs(M(1, 1) - lo) < 1e-9; hasHi = abs(M(end, 1) - hi) < 1e-9;
                if hasLo && ~hasHi, M(end + 1, :) = M(1, :); M(end, 1) = hi;
                elseif hasHi && ~hasLo, M = [M(end, :); M]; M(1, 1) = lo;
                elseif ~hasLo && ~hasHi
                    w = (hi - M(end, 1)) / (M(1, 1) - lo + hi - M(end, 1)); seam = (1 - w) * M(end, :) + w * M(1, :);
                    seam(1) = lo; seam(3) = mod(lo, 360); M = [seam; M; seam]; M(end, 1) = hi;
                end
            end
            shownFixed = fixedAngle; if cutType == "Phi" && app.isElevation(), shownFixed = 90 - fixedAngle; end
            if snapped, app.setStatus(app.Single_StatusBar, sprintf('Requested %s cut @ %s=%g° snapped to nearest sample %s=%g°', cutType, symbol, app.Single_Spinner_cutValue.Value, symbol, shownFixed), true); end
            if app.srcUD.isGainOnly, titleText = char(app.compLabel()); else, titleText = sprintf('%s cut @ %s = %g°', cutType, symbol, shownFixed); end
            cut = struct('type', cutType, 'angle', M(:, 1), 'theta', M(:, 2), 'phi', M(:, 3), 'data', M(:, 4:end), 'cols', cols, 'colorIndex', idx, 'title', titleText);
        end

        function plotCut(app)
            if isempty(app.viewTbl), return; end
            cut = app.cutData(); pax = app.Single_paxCut; rax = app.Single_AxesRect; lim = app.cutLim;
            delete(allchild(pax)); delete(allchild(rax)); hold(pax, 'on'); hold(rax, 'on');
            pl = polarplot(pax, deg2rad(cut.angle), max(cut.data, lim(1)), 'LineWidth', 1.4);   % clamp: no reflection spikes below RLim
            rl = plot(rax, cut.angle, cut.data, 'LineWidth', 1.4);
            colors = rax.ColorOrder(1 + mod(cut.colorIndex - 1, size(rax.ColorOrder, 1)), :); names = replace(cut.cols, "_", "\_");
            for k = 1:numel(pl)
                rows = [dataTipTextRow("Angle", cut.angle, '%.3g°'), dataTipTextRow("Magnitude", cut.data(:, k), '%.3g dB')];
                set([pl(k), rl(k)], 'Color', colors(k, :)); pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            xl = [0, 360] - 180 * app.isSignedPhi();
            set(pax, 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.setPolarTicks(pax);
            set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, cut.type + " (degree)"); ylabel(rax, 'Magnitude (dB)'); title(pax, cut.title, 'Interpreter', 'none'); title(rax, cut.title, 'Interpreter', 'none');
            legend(pax, pl, names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rl, names, 'Location', 'best');
            % Cut peak (POB of the displayed line) and HPBW of the first component.
            [peak, k] = max(cut.data(:, 1), [], 'omitnan'); app.Label_HPBW.Text = '';
            if isfinite(peak)
                rows = [dataTipTextRow("Angle", cut.angle(k), '%.3g°'); dataTipTextRow("Magnitude", peak, '%.3g dB')];
                app.addAnnotation(pax, deg2rad(cut.angle(k)), max(peak, lim(1)), 0, 'APAT_POB', rows, 'k');
                app.addAnnotation(rax, cut.angle(k), peak, 0, 'APAT_POB', rows, 'k');
                if app.Button_HPBW.Value
                    [bw, lower, upper] = calcHPBW(cut.angle, cut.data(:, 1), peak, cut.angle(k));
                    if isfinite(bw)
                        bounds = mod([lower, upper] - xl(1), 360) + xl(1);
                        app.Label_HPBW.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, bounds);
                        if bounds(1) <= bounds(2), regions = bounds; else, regions = [xl(1), bounds(2); bounds(1), xl(2)]; end
                        thetaregion(pax, deg2rad(regions(:, 1)), deg2rad(regions(:, 2)), FaceColor = '#D95319', FaceAlpha = 0.12);
                        xregion(rax, regions(:, 1), regions(:, 2), FaceColor = '#D95319', FaceAlpha = 0.12);
                        if app.Single_CheckBox_HPBWBounds.Value
                            labels = ["Lower HPBW", "Upper HPBW"];
                            for b = 1:2
                                rows = [dataTipTextRow(labels(b), bounds(b), '%.2f°'); dataTipTextRow("Gain", peak - 3, '%.2f dB')];
                                app.addAnnotation(pax, deg2rad(bounds(b)), peak - 3, 0, 'APAT_HPBW', rows, '#D95319');
                                app.addAnnotation(rax, bounds(b), peak - 3, 0, 'APAT_HPBW', rows, '#D95319');
                            end
                        end
                    end
                end
            end
            hold(pax, 'off'); hold(rax, 'off'); app.syncAnnotations();
        end

        % ------------------------------------------------------------------ ranges (colour scale / cut scale)
        function initRanges(app)
            % Auto scale: 50-dB window under the effective total-gain peak. AR always uses the signed ±30 dB scale.
            app.gainLim = displayRange(chooseGain(app.viewTbl, 'E_Total_dB'), app.PeakPercentile, app.PeakMaxExcessDB);
            app.setRange("cut", app.gainLim, false);
            if isAR(app.comp()), app.setRange("full", [-30, 30], false); else, app.setRange("full", app.gainLim, false); end
        end

        function setRange(app, scope, requested, applyNow)
            % Single range authority. Sliders travel over the union of previous limits and the request
            % (a fresh auto-scale resets the travel); spinners always bracket the current selection.
            requested = clampRange(requested, [-250, 100]);
            if scope == "all", app.setRange("full", requested, applyNow); app.setRange("cut", requested, applyNow); return; end
            if scope == "full"
                specs = app.fullSpecs(); sliders = [specs.range]; mins = [specs.minSpinner]; maxs = [specs.maxSpinner];
                app.fullLim = requested; if ~isAR(app.comp()), app.gainLim = requested; end
                [app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value] = deal(requested(1), requested(2));
            else
                sliders = app.Range_Cut; mins = app.Range_Cut_Min; maxs = app.Range_Cut_Max; app.cutLim = requested;
            end
            travel = requested; if applyNow, travel = [min(sliders(1).Limits(1), requested(1)), max(sliders(1).Limits(2), requested(2))]; end
            set(sliders, 'Limits', [-250, 100], 'Value', requested); set(sliders, 'Limits', travel);
            set(mins, 'Limits', [-250, 100], 'Value', requested(1)); set(mins, 'Limits', [-250, requested(2) - 1]);
            set(maxs, 'Limits', [-250, 100], 'Value', requested(2)); set(maxs, 'Limits', [requested(1) + 1, 100]);
            if applyNow && ~isempty(app.viewTbl)
                if scope == "full", app.applyFullRange(); else, set(app.Single_paxCut, 'RLim', requested); set(app.Single_AxesRect, 'YLim', requested); end
                drawnow limitrate
            end
        end

        function onRangeControl(app, src, scope, which)
            % Slider (which = 0) or min/max spinner (which = 1/2) edits of the full-pattern or cut range.
            if scope == "full", current = app.fullLim; else, current = app.cutLim; end
            if which == 0, requested = src.Value; else, requested = current; requested(which) = src.Value; end
            app.setRange(scope, requested, true);
        end
    end

    % ====================================================================== COVERAGE
    methods (Access = private)
        function node = covPatternNode(app)
            % Selected pattern node (or the pattern ancestor of the selection), else the newest pattern node.
            node = []; n = app.Cov_Tree.SelectedNodes;
            while ~isempty(n) && isa(n(1), 'matlab.ui.container.TreeNode') && isvalid(n(1))
                if isstruct(n(1).NodeData) && strcmp(n(1).NodeData.kind, 'pattern'), node = n(1); return; end
                n = n(1).Parent;
            end
            kids = app.Cov_TreeNode_Results.Children;
            for k = numel(kids):-1:1
                if strcmp(kids(k).NodeData.kind, 'pattern'), node = kids(k); return; end
            end
        end

        function node = covFindByPath(app, fp)
            node = []; kids = app.Cov_TreeNode_Results.Children;
            for k = 1:numel(kids), if strcmp(kids(k).NodeData.path, fp), node = kids(k); return; end, end
        end

        function jobs = covJobs(app, roots)
            % Job nodes ordered by run id, optionally restricted to the subtree(s) of ROOTS. The tree is the only registry.
            if nargin < 2, roots = app.Cov_TreeNode_Results; end
            jobs = matlab.ui.container.TreeNode.empty(1, 0); if isempty(roots), return; end
            nodes = findobj(roots); nodes = nodes(arrayfun(@(n) isa(n, 'matlab.ui.container.TreeNode') && isstruct(n.NodeData) && strcmp(n.NodeData.kind, 'job'), nodes));
            if isempty(nodes), return; end
            [~, order] = sort(arrayfun(@(n) n.NodeData.id, nodes)); jobs = reshape(nodes(order), 1, []);
        end

        function jobs = checkedJobs(app, roots)
            if nargin < 2, jobs = app.covJobs(); else, jobs = app.covJobs(roots); end
            jobs = jobs(ismember(jobs, app.Cov_Tree.CheckedNodes));
        end

        function addPatternNode(app, name, pattern, fp, sourceTable)
            node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', 'pattern', 'name', name, 'path', fp, 'pattern', pattern, 'sourceTable', sourceTable, ...
                'solidAngle', solidWeights(pattern.Theta, pattern.Phi), 'component', "", 'boresightIndex', 1, 'revision', app.viewRevision, 'cache', struct());
            expand(app.Cov_Tree);
            [app.Cov_Tree.CheckedNodes, app.Cov_Tree.SelectedNodes] = deal([app.Cov_Tree.CheckedNodes; node], node);
            app.syncPatternNode(node); app.Cov_Panel_Results.Visible = 'on'; app.setCoverageUI();
            app.setStatus(app.Cov_StatusBar, sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name), false);
        end

        function syncFromView(app, node)
            % Main-tab patterns are always analysed from the CURRENT view table (loss, step, parameters already applied).
            d = node.NodeData; if d.revision == app.viewRevision, return; end
            [d.pattern, d.solidAngle, d.name, d.revision, d.cache, d.component] = deal(app.viewTbl, app.solidAngle, app.baseName, app.viewRevision, struct(), "");
            node.NodeData = d; app.syncPatternNode(node);
        end

        function syncPatternNode(app, node)
            % Align component dropdown, boresight axis and threshold preset with a pattern node.
            d = node.NodeData; [columns, labels] = app.componentMap(d.pattern); dd = app.Cov_DropDown_Component;
            previous = d.component; if strlength(previous) == 0, previous = string(dd.Value); end
            component = preferredComponent(previous, columns);
            if ~isequal(string(dd.ItemsData), columns), [dd.Items, dd.ItemsData] = deal(cellstr(labels), cellstr(columns)); end
            dd.Value = char(component);
            changed = d.component ~= component;
            if changed
                [~, d.boresightIndex] = calcOrientation(d.pattern, d.solidAngle, component, app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
                d.component = component;
            end
            node.NodeData = d;
            if changed && app.Cov_DropDown_Orientation.Value == 0, app.orientationChanged(); end   % Auto: seed the cone centre
            key = sprintf('%s|%s|%d', d.path, component, d.revision);
            if ~strcmp(app.covPresetKey, key)   % threshold PRESET only when pattern / component / view changes
                app.covPresetKey = key; app.setCoverageRange(displayRange(d.pattern.(char(component)), app.PeakPercentile, app.PeakMaxExcessDB), "threshold");
            end
        end

        function thresholds = covThresholds(app)
            % Threshold vector exactly as entered (the preset never overrides user edits at compute time).
            tMin = app.Cov_Spinner_ThreshMin.Value; tMax = app.Cov_Spinner_ThreshMax.Value; step = max(app.Cov_Spinner_Step.Value, 0.1);
            if tMax <= tMin, tMax = min(100, tMin + step); app.Cov_Spinner_ThreshMax.Value = tMax; end
            thresholds = (tMin:step:tMax)'; if thresholds(end) < tMax, thresholds(end + 1) = tMax; end
        end

        function computeCoverage(app, ~)
            node = app.covPatternNode();
            if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if strcmp(node.NodeData.path, app.filePath) && ~isempty(app.viewTbl), app.syncFromView(node); end
            try
                d = node.NodeData; P = d.pattern; component = app.Cov_DropDown_Component.Value; thresholds = app.covThresholds();
                conical = app.Cov_ButtonGroup_Btn_Conical.Value; meta = struct('isConical', conical, 'orientationLabel', "n/a");
                if conical
                    [t0, p0, alpha] = deal(app.Cov_Spinner_ConeTH.Value, mod(app.Cov_Spinner_ConePH.Value, 360), app.Cov_Spinner_ConeAng.Value);
                    mask = cosd(P.Theta) * cosd(t0) + sind(P.Theta) * sind(t0) .* cosd(P.Phi - p0) >= cosd(alpha);
                    centre = app.coneCentreLabel(t0, p0);
                    tag = sprintf('Con_%.15g_%.15g_%.15g', t0, p0, alpha); tagFull = sprintf('Conical coverage (%s) α=%s°', centre, fmtNum(alpha));
                    tableTag = sprintf('Con %s α%s°', erase(centre, ["=", ","]), fmtNum(alpha));
                    k = app.Cov_DropDown_Orientation.Value; if k == 0, k = d.boresightIndex; end
                    meta.orientationLabel = string(app.PrincipalAxes.labels{k}); [meta.coneTheta, meta.conePhi, meta.coneAngle] = deal(t0, p0, alpha);
                else
                    mask = true(height(P), 1); [tag, tagFull, tableTag] = deal('Sph', 'Sph coverage', 'Sph');
                end
                key = matlab.lang.makeValidName(sprintf('%s_%s_%g_%g_%g_%d', component, tag, thresholds(1), thresholds(end), gridStep(thresholds), numel(thresholds)));
                cached = isfield(d.cache, key);
                if cached, coverage = d.cache.(key);
                else, coverage = coverageCCDF(P.(component), mask, thresholds, d.solidAngle); d.cache.(key) = coverage; node.NodeData = d;
                end
                app.addJob(node, thresholds, coverage, tag, component, tagFull, tableTag, meta);
                app.finalizeJobs(); app.setCoverageRange(thresholds([1, end])', "plot");
                action = 'computed'; if cached, action = 'reused cached CCDF'; end
                msg = sprintf('Run-<b>%d</b> %s: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', app.covRunID, action, tagFull, d.name, component, numel(thresholds));
                if conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, meta.orientationLabel); end
                app.setStatus(app.Cov_StatusBar, msg, false);
            catch ME
                app.showError(ME, 'Coverage Error');
            end
        end

        function addJob(app, parent, thresholds, coverage, tag, component, tagFull, tableTag, meta)
            if nargin < 9, meta = struct('isConical', false, 'orientationLabel', "n/a"); end
            app.covRunID = app.covRunID + 1; icon = '📉'; if strcmp(tag, 'Res'), icon = '📈'; end
            label = sprintf('%s R%d %s · %s', icon, app.covRunID, tagFull, component);
            h = plot(app.Cov_Axes, thresholds, coverage, 'LineWidth', 1.6, 'DisplayName', label);
            h.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", 'XData', '%.2f dB'); dataTipTextRow("Coverage", 'YData', '%.2f%%')];
            [invCov, invRows] = unique(coverage, 'last');
            node = uitreenode(parent, 'Text', label);
            node.NodeData = struct('kind', 'job', 'id', app.covRunID, 'tag', tag, 'tableTag', tableTag, 'label', label, 'line', h, ...
                'thr', thresholds(:), 'cov', coverage(:), 'invCov', invCov, 'invThr', thresholds(invRows), 'meta', meta);
            expand(parent); app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node];
        end

        function finalizeJobs(app)
            % Rebuild the shared table and legend from the checked jobs, then refresh control state.
            jobs = app.checkedJobs();
            if isempty(jobs), thresholds = app.covThresholds();
            else, cells = arrayfun(@(n) n.NodeData.thr, jobs, 'UniformOutput', false); thresholds = unique(vertcat(cells{:}));
            end
            values = [thresholds, nan(numel(thresholds), numel(jobs))]; names = [{'Threshold (dB)'}, cell(1, numel(jobs))];
            lines = gobjects(1, numel(jobs)); labels = cell(1, numel(jobs));
            for k = 1:numel(jobs)
                d = jobs(k).NodeData; if numel(d.thr) > 1, values(:, k + 1) = interp1(d.thr, d.cov, thresholds, 'linear', NaN); end
                names{k + 1} = sprintf('R%d %s %%', d.id, d.tableTag); lines(k) = d.line; labels{k} = d.label;
            end
            app.Cov_Table.Data = array2table(compose('%.2f', values), 'VariableNames', names);
            if isempty(jobs), legend(app.Cov_Axes, 'off'); else, legend(app.Cov_Axes, lines, labels, 'Location', 'southwest', 'Interpreter', 'none'); end
            app.setCoverageUI();
        end

        function setCoverageUI(app)
            % Control availability derives from tree content: a pattern node enables analysis, jobs enable results tools.
            hasPattern = ~isempty(app.covPatternNode()); hasJobs = ~isempty(app.covJobs()); conical = app.Cov_ButtonGroup_Btn_Conical.Value;
            set(app.Cov_gridPanel_Parm.Children, 'Visible', hasPattern, 'Enable', hasPattern);
            set([app.Labels.CovPath, app.Cov_EditField_filePath, app.Cov_Button_Load, app.Cov_Button_computeCov, app.Cov_Button_toMain], 'Visible', 'on', 'Enable', 'on');
            app.Cov_Button_computeCov.Enable = hasPattern;
            set([app.CovQueryControls, app.Cov_Button_Reset, app.Cov_Button_Export, app.Cov_Button_Clear], 'Visible', hasPattern || hasJobs, 'Enable', hasJobs);
            app.Cov_Button_Reset.Enable = hasPattern || hasJobs;
            set(app.CovConeControls, 'Visible', hasPattern && conical, 'Enable', hasPattern && conical);
            set([app.Labels.CovFormat, app.Cov_DropDown_TextFormat], 'Visible', hasPattern && isGenericText(app.Cov_EditField_filePath.Value));
        end

        function setCoverageRange(app, bounds, mode)
            % "threshold": preset the threshold spinners (only widened after the first preset).
            % "plot": X-axis baseline established by the first result and only widened afterwards.
            bounds = clampRange(bounds, [-250, 100]);
            if mode == "threshold"
                if app.covThreshInit, bounds = [min(bounds(1), app.Cov_Spinner_ThreshMin.Value), max(bounds(2), app.Cov_Spinner_ThreshMax.Value)]; end
                app.covThreshInit = true;
                set(app.Cov_Spinner_ThreshMin, 'Limits', [-250, 100], 'Value', bounds(1)); set(app.Cov_Spinner_ThreshMax, 'Limits', [-250, 100], 'Value', bounds(2));
                app.Cov_Spinner_ThreshMin.Limits = [-250, bounds(2) - 0.1]; app.Cov_Spinner_ThreshMax.Limits = [bounds(1) + 0.1, 100];
            else
                if app.covXInit, bounds = [min(app.Cov_Axes.XLim(1), bounds(1)), max(app.Cov_Axes.XLim(2), bounds(2))]; end
                app.covXInit = true; app.setXRange(bounds);
            end
        end

        function setXRange(app, b)
            % Plot-range spinners are the master: they define slider travel and the plotted X limits.
            s = app.Cov_Slider_XRange; s.Limits = [-250, 100]; s.Value = b; s.Limits = b;
            set(app.Cov_Spinner_XMin, 'Limits', [-250, 100], 'Value', b(1)); set(app.Cov_Spinner_XMax, 'Limits', [-250, 100], 'Value', b(2));
            app.Cov_Spinner_XMin.Limits = [-250, b(2) - 0.1]; app.Cov_Spinner_XMax.Limits = [b(1) + 0.1, 100];
            app.Cov_Axes.XLimMode = 'manual'; app.Cov_Axes.XLim = b;
        end

        function syncXRange(app, event)
            if isequal(event.Source, app.Cov_Slider_XRange)   % subordinate slider: select within the fixed travel
                v = sort(event.Value); if diff(v) <= 0, return; end
                [app.Cov_Spinner_XMin.Value, app.Cov_Spinner_XMax.Value] = deal(v(1), v(2)); app.Cov_Axes.XLim = v; return
            end
            b = sort([app.Cov_Spinner_XMin.Value, app.Cov_Spinner_XMax.Value]);
            if diff(b) <= 0   % keep the edited endpoint, move the other one
                if isequal(event.Source, app.Cov_Spinner_XMin), b(2) = min(100, b(1) + 1); else, b(1) = max(-250, b(2) - 1); end
            end
            app.setXRange(b);
        end

        function label = coneCentreLabel(app, theta, phi)
            % A cone centre that coincides with a principal axis is named after it; otherwise its coordinates are shown.
            ax = app.PrincipalAxes; c = [sind(theta) * cosd(phi), sind(theta) * sind(phi), cosd(theta)];
            A = [sind(ax.theta(:)) .* cosd(ax.phi(:)), sind(ax.theta(:)) .* sind(ax.phi(:)), cosd(ax.theta(:))];
            k = find(A * c(:) >= 1 - 1e-9, 1);
            if isempty(k), label = sprintf('θ=%s°, φ=%s°', fmtNum(theta), fmtNum(phi)); else, label = string(ax.labels{k}); end
        end

        function reportOrientation(app)
            % Append the resolved conical orientation to the Coverage status line (idempotent).
            if ~app.Cov_ButtonGroup_Btn_Conical.Value, return; end
            k = app.Cov_DropDown_Orientation.Value; node = app.covPatternNode();
            if k == 0, if isempty(node), return; end, k = node.NodeData.boresightIndex; end
            base = regexprep(char(app.Cov_StatusBar.Text), '\s*\|\s*Orientation <b>.*?</b>$', '');
            app.setStatus(app.Cov_StatusBar, sprintf('%s | Orientation <b>%s</b>', base, app.PrincipalAxes.labels{k}), false);
        end

        function orientationChanged(app, ~)
            % Auto resolves the detected axis; an explicit choice is authoritative and never overwritten.
            k = app.Cov_DropDown_Orientation.Value; node = app.covPatternNode();
            if k == 0, if isempty(node), return; end, k = node.NodeData.boresightIndex; end
            [app.Cov_Spinner_ConeTH.Value, app.Cov_Spinner_ConePH.Value] = deal(app.PrincipalAxes.theta(k), app.PrincipalAxes.phi(k));
            app.reportOrientation();
        end

        function covComponentChanged(app, ~)
            node = app.covPatternNode(); if isempty(node), return; end
            d = node.NodeData; d.component = string(app.Cov_DropDown_Component.Value);
            [~, d.boresightIndex] = calcOrientation(d.pattern, d.solidAngle, d.component, app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
            node.NodeData = d; app.reportOrientation();
        end

        function covTypeChanged(app, ~)
            app.setCoverageUI();
            if app.Cov_ButtonGroup_Btn_Conical.Value
                node = app.covPatternNode(); if ~isempty(node), app.syncPatternNode(node); end
                app.reportOrientation();
            else
                app.Cov_StatusBar.Text = regexprep(char(app.Cov_StatusBar.Text), '\s*\|\s*Orientation <b>.*?</b>', '');
            end
        end

        function treeSelectionChanged(app, ~)
            sel = app.Cov_Tree.SelectedNodes;
            for job = app.covJobs(), h = job.NodeData.line; h.LineWidth = 1.6 + isequal(job, sel); end   % highlight the selected job
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(app.Cov_StatusBar, 'Ready.', false); return; end
            d = sel(1).NodeData; pattern = app.covPatternNode(); if ~isempty(pattern), app.syncPatternNode(pattern); end
            if ~strcmp(d.kind, 'job')
                kind = 'Pattern'; if strcmp(d.kind, 'results'), kind = 'Results'; end
                app.setStatus(app.Cov_StatusBar, sprintf('%s <b>"%s"</b> — <b>%d</b> coverage job(s).', kind, d.name, numel(sel(1).Children)), false);
                if strcmp(d.kind, 'pattern'), app.reportOrientation(); end
                return
            end
            [t50, c50] = queryPoint(d, "thr", 50); shown = round(d.cov, 2); mx = max(shown); k = max([1, find(shown == mx, 1, 'last')]);
            parts = {char(d.label)};
            if d.meta.isConical, parts{end + 1} = sprintf('Orientation <b>%s</b>', d.meta.orientationLabel); end
            parts{end + 1} = sprintf('Threshold [%s, %s] dB, step %s dB', fmtNum(d.thr(1)), fmtNum(d.thr(end)), fmtNum(gridStep(d.thr)));
            if isfinite(t50), parts{end + 1} = sprintf('<b>%s%%</b>-coverage threshold <b>%s dB</b>', fmtNum(c50), fmtNum(t50)); else, parts{end + 1} = '<b>50%-coverage unavailable</b>'; end
            parts{end + 1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmtNum(mx), fmtNum(d.thr(k)));
            app.setStatus(app.Cov_StatusBar, strjoin(parts, ' | '), false);
        end

        function treeCheckedChanged(app, ~)
            checked = app.Cov_Tree.CheckedNodes;
            for job = app.covJobs()
                d = job.NodeData; on = ismember(job, checked);
                set([d.line; findall(d.line, 'Type', 'datatip'); app.queryArtifacts(d.id)], 'Visible', on);
            end
            app.finalizeJobs();
        end

        function objects = queryArtifacts(app, id)
            objects = findall(app.Cov_Axes, '-regexp', 'Tag', sprintf('^CovQ_\\w+_%d$', id));
        end

        function runQuery(app, mode)
            % "cov": coverage at a threshold (x → y). "thr": threshold at a coverage (y → x).
            isCov = mode == "cov"; ax = app.Cov_Axes;
            if isCov, q = app.Cov_Spinner_queryCov.Value; else, q = app.Cov_Spinner_queryThresh.Value; end
            jobs = app.checkedJobs(app.Cov_Tree.SelectedNodes);
            if isempty(jobs), app.setStatus(app.Cov_StatusBar, 'Select a node with checked results to query.', true); return; end
            hit = false;
            for job = jobs
                d = job.NodeData; tag = sprintf('CovQ_%s_%d', mode, d.id); delete(findall(ax, 'Tag', tag));
                [x, y] = queryPoint(d, mode, q); if ~isfinite(x) || ~isfinite(y), continue; end
                line(ax, [x, x; -250, x]', [ax.YLim(1), y; y, y]', 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'FontSize', 9, 'HandleVisibility', 'off', 'Tag', tag);
                hit = true;
            end
            if ~hit, app.setStatus(app.Cov_StatusBar, 'Query value is outside the selected checked range.', true);
            elseif isCov, app.setStatus(app.Cov_StatusBar, sprintf('Coverage queried at %s dB.', fmtNum(q)), false);
            else, app.setStatus(app.Cov_StatusBar, sprintf('Threshold queried at %s%% coverage.', fmtNum(q)), false);
            end
        end

        function clearQueries(app, ~)
            jobs = app.covJobs(app.Cov_Tree.SelectedNodes);
            if isempty(jobs), app.setStatus(app.Cov_StatusBar, 'Select a node with coverage results to clear.', true); return; end
            for job = jobs, d = job.NodeData; delete([app.queryArtifacts(d.id); findall(d.line, 'Type', 'datatip')]); end
            app.setStatus(app.Cov_StatusBar, 'Selected DataTips and query markers cleared.', true);
        end

        function resetCoverage(app, ~)
            delete(app.Cov_TreeNode_Results.Children); delete(allchild(app.Cov_Axes)); legend(app.Cov_Axes, 'off');
            app.Cov_Table.Data = table(); [app.covRunID, app.covPresetKey, app.covThreshInit, app.covXInit] = deal(0, '', false, false);
            app.Cov_Axes.XLimMode = 'auto'; app.Cov_Panel_Results.Visible = 'off'; app.setXRange([-40, 10]); app.setCoverageUI();
            app.setStatus(app.Cov_StatusBar, 'Coverage workspace reset 🔄', true);
        end

        function loadResults(app, fp, data)
            % A coverage-results table (threshold column + one coverage column per curve) becomes a results node with one job per curve.
            [~, name] = fileparts(fp); node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📄 ' name]);
            node.NodeData = struct('kind', 'results', 'name', name, 'path', fp);
            thresholds = data{:, 1}; step = gridStep(thresholds);
            if isfinite(step) && step < app.Cov_Spinner_Step.Value, app.Cov_Spinner_Step.Value = step; end
            for k = 2:width(data), app.addJob(node, thresholds, data{:, k}, 'Res', data.Properties.VariableNames{k}, 'Res', data.Properties.VariableNames{k}); end
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node]; app.setCoverageRange(thresholds([1, end])', "plot");
            app.Cov_Panel_Results.Visible = 'on'; app.finalizeJobs();
            app.setStatus(app.Cov_StatusBar, sprintf('Coverage results file "%s" loaded (%d curves).', name, width(data) - 1), false);
        end

        function covLoad(app, ~)
            fp = strtrim(app.Cov_EditField_filePath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFindByPath(fp))
                [f, p] = uigetfile(app.FileFilter, 'Select a pattern or coverage results file'); if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            existing = app.covFindByPath(fp);
            if ~isempty(existing)
                app.Cov_Tree.SelectedNodes = existing; app.treeSelectionChanged(); app.setCoverageUI();
                app.setStatus(app.Cov_StatusBar, 'File already loaded — node selected.', true); return
            end
            app.Cov_EditField_filePath.Value = fp;
            try
                out = app.readSource(fp, app.Cov_DropDown_TextFormat);
                if out.userData.isCoverage
                    node = app.covPatternNode(); if ~isempty(node), app.Cov_EditField_filePath.Value = node.NodeData.path; end
                    app.loadResults(fp, out.rawTbl);
                else
                    [~, name] = fileparts(fp); app.addPatternNode(name, app.buildPattern(out), fp, out.cache);   % multi-block FFD uses block 1
                end
            catch ME
                app.showError(ME, 'Coverage Load Error');
            end
        end

        function covFormatChanged(app, ~)
            % Reinterpret an already-loaded generic coverage pattern with the newly selected text format.
            fp = strtrim(app.Cov_EditField_filePath.Value); old = app.covFindByPath(fp);
            if isempty(old) || ~isGenericText(fp), return; end
            try
                out = readPattern(fp, app.Cov_DropDown_TextFormat.Value, old.NodeData.sourceTable);
                if out.userData.isCoverage, app.setStatus(app.Cov_StatusBar, 'Coverage-result files are detected automatically.', true); return; end
                name = old.NodeData.name;
                for job = app.covJobs(old), delete(job.NodeData.line); end
                delete(old); app.addPatternNode(name, app.buildPattern(out), fp, out.cache); app.finalizeJobs();
                app.setStatus(app.Cov_StatusBar, sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
            catch ME
                app.showError(ME, 'Coverage Format Error');
            end
        end

        function toCoverage(app, ~)
            % Push the current Main view table to the Coverage tab (creating or refreshing its pattern node).
            if isempty(app.viewTbl), uialert(app.UIFigure, 'Load and process a pattern first.', 'Coverage'); return; end
            [app.TabGroup.SelectedTab, app.Cov_EditField_filePath.Value] = deal(app.Tab2_Coverage, app.filePath);
            node = app.covFindByPath(app.filePath);
            if isempty(node), app.addPatternNode(app.baseName, app.viewTbl, app.filePath, app.sourceCache);
            else, app.syncFromView(node); app.Cov_Tree.SelectedNodes = node; app.setCoverageUI();
            end
            app.setStatus(app.Cov_StatusBar, 'Coverage source synchronized from the current Main-tab view table.', false);
        end
    end

    % ====================================================================== MAIN-TAB CALLBACKS, EXPORT, LIFECYCLE
    methods (Access = private)
        function onLoad(app, ~)
            fp = strtrim(app.Single_EditField_Path.Value);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.filePath)
                [f, p] = uigetfile(app.FileFilter, 'Select an antenna pattern file'); if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Loading Data', 'Message', 'Reading file...', 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            app.operationDialog = dlg; cleaner = onCleanup(@() close(dlg)); drawnow; app.tick("start");
            try
                out = app.readSource(fp, app.Single_DropDown_TextFormat); app.tick("Read file");
                if out.userData.isCoverage   % coverage results never replace the Main pattern
                    [app.TabGroup.SelectedTab, app.Cov_EditField_filePath.Value] = deal(app.Tab2_Coverage, fp); app.loadResults(fp, out.rawTbl);
                else
                    app.loadSource(out, fp);
                end
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.setStatus(app.Single_StatusBar, 'Loading cancelled by user.', true); else, app.showError(ME, 'Loading Error'); end
            end
            app.operationDialog = [];
        end

        function onProcess(app, ~)
            if isempty(app.stdTbl), uialert(app.UIFigure, 'Load a pattern first.', 'Warning', 'Icon', 'warning'); return; end
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Processing', 'Message', 'Re-processing pattern...', 'Indeterminate', 'on'); cleaner = onCleanup(@() close(dlg));
            app.useOneDegree = strcmp(app.Single_DropDown_step.Value, 'STEP: 1°'); app.tick("start");
            try
                if isGenericText(app.filePath)   % reinterpret the cached as-read text table with the selected format
                    out = readPattern(app.filePath, app.Single_DropDown_TextFormat.Value, app.sourceCache);
                    assert(~out.userData.isCoverage, 'The selected format identifies a coverage-results file.');
                    [app.rawTbl, app.ffdBlocks, app.freqs, app.srcUD] = deal(out.rawTbl, out.blocks, out.freqs, out.userData);
                    app.stdTbl = normalizePattern(out.blocks{1}); app.stdTbl.Properties.UserData = app.srcUD;
                end
                app.process();
                app.setStatus(app.Single_StatusBar, ['Re-processed <b>' app.fileName '</b> with the current parameters ✅'], true);
            catch ME
                app.showError(ME, 'Processing Error');
            end
        end

        function onTextFormatChanged(app, ~)
            if strcmp(strtrim(app.Single_EditField_Path.Value), app.filePath) && isGenericText(app.filePath), app.autoCutBasis = true; app.onProcess(); end
        end

        function onFFDChanged(app, ~)
            k = find(strcmp(app.Single_DropDown_FFD.Items, app.Single_DropDown_FFD.Value), 1); app.autoCutBasis = true; app.tick("start");
            app.selectBlock(k); app.setStatus(app.Single_StatusBar, sprintf('Switched to FFD block %d (%s).', k, app.Single_DropDown_FFD.Value), true);
        end

        function stepChanged(app, ~)
            app.useOneDegree = strcmp(app.Single_DropDown_step.Value, 'STEP: 1°'); app.tick("start");
            app.buildView(); app.setComponentItems(app.Single_DropDown_Component, app.viewTbl); app.updateView(true); app.tick("Change angular step");
        end

        function spanChanged(app, ~)
            % Display convention changed: the canonical data (and therefore peak/metrics) is unchanged — re-render only.
            if isempty(app.viewTbl), return; end
            app.grid = struct(); app.tick("start"); app.updateTables(); app.updateMetadata(); app.renderAll(); app.updateCutControl(); app.plotCut(); app.tick("Change angular span");
        end

        function onComponentChanged(app, ~)
            if ~isempty(app.viewTbl), app.updateView(true, app.srcUD.isGainOnly); end   % gain-only: boresight may move with the column
        end

        function onCutChanged(app, event)
            if nargin > 1 && ~isempty(event)
                if isequal(event.Source, app.Single_DropDown_cutType), app.updateCutControl();
                elseif isequal(event.Source, app.CutFieldBasisDropDown), app.autoCutBasis = false; app.updateMetadata();
                end
            end
            app.Single_CheckBox_HPBWBounds.Visible = app.Button_HPBW.Value;
            if ~app.Button_HPBW.Value, app.Single_CheckBox_HPBWBounds.Value = false; end
            app.plotCut(); app.drawOverlay();
        end

        function onPlaneChanged(app, ~)
            app.selectPlane(); app.onCutChanged();
        end

        function onPOBToggled(app, ~)
            if app.Single_CheckBox_POB.Value && isempty(findall(app.Single_Panel_fullPattern, 'Tag', 'APAT_POB')), app.annotatePOB(); end
            app.syncAnnotations();
        end

        function on3DViewChanged(app, ~)
            app.apply3DView(app.Single_Axes_3dSph, [135, 25]); app.apply3DView(app.Single_Axes_3dPol, [135, 25]); app.apply3DView(app.Single_Axes_3dRect, [-35, 35]);
        end

        function resetParams(app, ~)
            p = app.defaultParams;
            [app.Single_Spinner_Loss.Value, app.Single_DropDown_RxPol.Value, app.Single_Spinner_Rw.Value, app.Single_Spinner_Pt.Value, ...
                app.Single_DropDown_Pt.Value, app.Single_Spinner_R.Value, app.Single_DropDown_R.Value] = ...
                deal(p.Loss, p.RxMode, p.Rw, p.Pt, p.PtUnit, p.R, p.RUnit);
            if ~isempty(app.stdTbl), app.process(); end
        end

        function exportTable(app, T, defaultName, titleText, statusLabel)
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, titleText, fullfile(app.folderPath, defaultName));
            if isequal(f, 0), return; end
            try
                fp = fullfile(p, f); writeTable(T, fp); app.setStatus(statusLabel, sprintf('%s exported to <b>%s</b>', titleText, fp), true);
            catch ME
                app.showError(ME, [titleText ' Error']);
            end
        end

        function exportCut(app, ~)
            if isempty(app.viewTbl), return; end
            cut = app.cutData(); T = array2table([cut.angle, cut.data], 'VariableNames', [{'Angle_deg'}, cellstr(cut.cols)]);
            app.exportTable(T, [app.baseName '_cut.csv'], ['Export Cut (' cut.title ')'], app.Single_StatusBar);
        end

        function exportUAN(app, ~)
            % XGTD UAN export from the canonical view (physical θ 0..180, φ 0..360, dB magnitude + degree phase).
            T = app.viewTbl;
            if isempty(T) || app.srcUD.isGainOnly, uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            U = sortrows(table(T.Theta, T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'}), {'Phi', 'Theta'});
            peak = max([U.E_TH_DB; U.E_PH_DB]); step = gridStep(U.Theta); if ~isfinite(step), step = 1; end
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, ...
                'Export UAN / E-field data', fullfile(app.folderPath, sprintf('%s_%.5f_%gdeg.uan', app.baseName, peak, step)));
            if isequal(f, 0), return; end
            try
                fp = fullfile(p, f);
                if endsWith(fp, '.uan', 'IgnoreCase', true), writeUAN(U, fp); else, writeTable(U, fp); end
                app.setStatus(app.Single_StatusBar, ['UAN exported to <b>' fp '</b>'], true);
            catch ME
                app.showError(ME, 'Export UAN Error');
            end
        end

        function setStatus(app, label, message, temporary)
            % Persistent messages replace the label baseline; temporary ones revert to it after 3 s (one shared timer).
            if app.isClosing || ~isgraphics(label), return; end
            stop(app.statusTimer); label.Text = char(message);
            if temporary, app.statusTimer.UserData = label; start(app.statusTimer); else, label.UserData = label.Text; end
        end

        function restoreStatus(app)
            label = app.statusTimer.UserData;
            if ~app.isClosing && isgraphics(label), label.Text = label.UserData; end
        end

        function showError(app, ME, titleText)
            if app.isClosing, return; end
            where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.UIFigure, [ME.message where], titleText, 'Icon', 'error');
        end

        function checkCancelled(app)
            % Abort at the next pipeline checkpoint once the user pressed the dialog's cancel button.
            if ~isempty(app.operationDialog) && isvalid(app.operationDialog) && app.operationDialog.CancelRequested
                app.operationDialog.Message = 'Aborting...'; drawnow limitrate; error('APAT:Cancelled', 'Operation cancelled by user.');
            end
        end

        function tick(app, stage)
            % Stage profiler: tick("start") resets the clock; later ticks print the elapsed time when Verbose.
            if app.Verbose && stage ~= "start", fprintf('[APAT] %-24s %7.3f s\n', stage, toc(app.stageClock)); end
            app.stageClock = tic;
        end

        function closeRequest(app, ~), delete(app); end
    end

    % ====================================================================== UI CONSTRUCTION
    methods (Access = private)
        function h = at(~, h, row, col), h.Layout.Row = row; h.Layout.Column = col; end

        function h = rlabel(app, parent, text, row, col, varargin), h = app.at(uilabel(parent, 'Text', text, 'HorizontalAlignment', 'right', varargin{:}), row, col); end

        function cb = callback(app, method), cb = createCallbackFcn(app, method, true); end

        function dd = formatDropdown(app, parent, method)
            dd = uidropdown(parent, 'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
                '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
                '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'}, ...
                'Value', 'gain', 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'ValueChangedFcn', app.callback(method));
        end

        function [ax, slider, minSpinner, maxSpinner] = patternTab(app, tabGroup, titleText, scope, makeAxes)
            % One full-pattern tab: axes (or a polar-axes slot) with a vertical range slider bracketed by min/max spinners.
            g = uigridlayout(uitab(tabGroup, 'Title', titleText), 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
            ax = g; if makeAxes, ax = app.at(uiaxes(g), [1, 3], 2); end
            slider = app.at(uislider(g, 'range', 'Limits', [-250, 100], 'Value', [-40, 10], 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s, ~) app.onRangeControl(s, scope, 0)), 2, 1);
            maxSpinner = app.at(uispinner(g, 'Limits', [-250, 100], 'Value', 10, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRangeControl(s, scope, 2)), 1, 1);
            minSpinner = app.at(uispinner(g, 'Limits', [-250, 100], 'Value', -40, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRangeControl(s, scope, 1)), 3, 1);
        end

        function createComponents(app)
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.ReleaseName], 'Visible', 'off', 'Position', [100, 100, 1136, 739], 'WindowState', 'maximized');
            app.UIFigure.CloseRequestFcn = app.callback(@closeRequest);
            app.plotMenu = uicontextmenu(app.UIFigure, 'ContextMenuOpeningFcn', @(m, e) set(m, 'UserData', ancestor(e.ContextObject, {'axes', 'polaraxes'})));
            uimenu(app.plotMenu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(m, ~) delete(findall(m.Parent.UserData, 'Type', 'datatip')));
            app.TabGroup = uitabgroup(uigridlayout(app.UIFigure, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}));
            L = struct();

            % ------------------------------------------------------------ Main tab
            app.Tab1_Single = uitab(app.TabGroup, 'Title', 'Process Pattern 📡');
            main = uigridlayout(app.Tab1_Single, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});

            % Inputs & parameters
            P = uigridlayout(app.at(uipanel(main, 'Title', 'Inputs & Parameters 🎛️'), 1, [1, 14]), 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            app.rlabel(P, 'Input Pattern:', 1, 1);
            app.Single_EditField_Path = app.at(uieditfield(P, 'text'), 1, [2, 8]);
            L.FFD = app.rlabel(P, 'FFD Freq:', 1, 9, 'Visible', 'off');
            app.Single_DropDown_FFD = app.at(uidropdown(P, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', app.callback(@onFFDChanged)), 1, 10);
            app.at(uibutton(P, 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', app.callback(@onLoad)), 1, [11, 12]);
            app.at(uibutton(P, 'Text', '⚙️ Process', 'ButtonPushedFcn', app.callback(@onProcess)), 1, [13, 14]);
            app.at(uibutton(P, 'Text', 'Reset Params', 'ButtonPushedFcn', app.callback(@resetParams)), 2, [1, 3]);
            L.Format = app.rlabel(P, 'Format:', 2, [4, 5], 'Visible', 'off');
            app.Single_DropDown_TextFormat = app.at(app.formatDropdown(P, @onTextFormatChanged), 2, [6, 8]); app.Single_DropDown_TextFormat.Visible = 'off';
            app.Single_DropDown_step = app.at(uidropdown(P, 'Items', {'STEP', 'STEP: 1°'}, 'Visible', 'off', 'Enable', 'off', 'ValueChangedFcn', app.callback(@stepChanged)), 2, [9, 10]);
            app.Single_Export_Output = app.at(uibutton(P, 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.exportTable(app.Single_Table_DataOut.Data, [app.baseName '_APAT_results.csv'], 'Export Results', app.Single_StatusBar)), 2, [11, 12]);
            app.Single_Export_UAN = app.at(uibutton(P, 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.callback(@exportUAN)), 2, [13, 14]);
            L.Rx = app.rlabel(P, 'Rw Sense', 3, 1, 'Visible', 'off');
            app.Single_DropDown_RxPol = app.at(uidropdown(P, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Visible', 'off'), 3, 2);
            L.Rw = app.rlabel(P, 'Rw (dB)', 3, 3, 'Visible', 'off');
            app.Single_Spinner_Rw = app.at(uispinner(P, 'Value', 6, 'Visible', 'off'), 3, 4);
            L.Loss = app.rlabel(P, 'Loss (−) / Gain (+) dB', 3, 5, 'Visible', 'off');
            app.Single_Spinner_Loss = app.at(uispinner(P, 'Step', 0.1, 'Visible', 'off'), 3, 6);
            L.Pt = app.rlabel(P, 'Tx Pwr (Pt)', 3, 7, 'Visible', 'off');
            app.Single_Spinner_Pt = app.at(uispinner(P, 'Visible', 'off'), 3, 8);
            app.Single_DropDown_Pt = app.at(uidropdown(P, 'Items', {'dBW', 'dBm', 'Watts'}, 'Visible', 'off'), 3, 9);
            L.R = app.rlabel(P, 'Distance', 3, 10, 'Visible', 'off');
            app.Single_Spinner_R = app.at(uispinner(P, 'Value', 1, 'Visible', 'off'), 3, 11);
            app.Single_DropDown_R = app.at(uidropdown(P, 'Items', {'m', 'km'}, 'Visible', 'off'), 3, 12);
            app.Single_Button_Coverage = app.at(uibutton(P, 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.callback(@toCoverage)), 3, [13, 14]);

            % Full-pattern plots
            app.Single_Panel_fullPattern = app.at(uipanel(main, 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2, 3], [1, 6]);
            tabPlots = uitabgroup(uigridlayout(app.Single_Panel_fullPattern, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}), 'SelectionChangedFcn', @(~, ~) app.syncAnnotations());
            [app.Single_Axes_Ctr, app.Range_Ctr, app.Range_Ctr_Min, app.Range_Ctr_Max] = app.patternTab(tabPlots, 'Contour Plot', "full", true);
            [gCir, app.Range_Cir, app.Range_Cir_Min, app.Range_Cir_Max] = app.patternTab(tabPlots, 'Circular Contour Plot', "full", false);
            app.Single_paxPattern = app.at(polaraxes(gCir), [1, 3], 2);
            [app.Single_Axes_3dSph, app.Range_3dSph, app.Range_3dSph_Min, app.Range_3dSph_Max] = app.patternTab(tabPlots, '3D Spherical Plot', "full", true);
            [app.Single_Axes_3dPol, app.Range_3dPol, app.Range_3dPol_Min, app.Range_3dPol_Max] = app.patternTab(tabPlots, '3D Polar Plot', "full", true);
            [app.Single_Axes_3dRect, app.Range_3dRect, app.Range_3dRect_Min, app.Range_3dRect_Max] = app.patternTab(tabPlots, '3D Surface Plot', "full", true);

            % Cut plots
            app.Single_Panel_Rect = app.at(uipanel(main, 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2, 3], [7, 12]);
            tabCut = uitabgroup(uigridlayout(app.Single_Panel_Rect, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}), 'SelectionChangedFcn', @(~, ~) app.syncAnnotations());
            gPol = uigridlayout(uitab(tabCut, 'Title', 'Polar Cut Plot'), 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            app.Single_paxCut = app.at(polaraxes(gPol), [1, 4], 3);
            app.Range_Cut = app.at(uislider(gPol, 'range', 'Limits', [-250, 100], 'Value', [-40, 10], 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s, ~) app.onRangeControl(s, "cut", 0)), [2, 3], 1);
            app.Range_Cut_Max = app.at(uispinner(gPol, 'Limits', [-250, 100], 'Value', 10, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRangeControl(s, "cut", 2)), 1, 1);
            app.Range_Cut_Min = app.at(uispinner(gPol, 'Limits', [-250, 100], 'Value', -40, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.onRangeControl(s, "cut", 1)), 4, 1);
            app.Button_HPBW = app.at(uibutton(gPol, 'state', 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', app.callback(@onCutChanged)), 1, 4);
            app.Label_HPBW = app.at(uilabel(gPol, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold'), 2, 4);
            app.Single_gridEcut = app.at(uigridlayout(gPol, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x', '1x', '1x'}), 3, 4);
            app.CheckBox_Et = app.at(uicheckbox(app.Single_gridEcut, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', app.callback(@onCutChanged)), 1, 1);
            app.CheckBox_Er = app.at(uicheckbox(app.Single_gridEcut, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', app.callback(@onCutChanged)), 2, 1);
            app.CheckBox_El = app.at(uicheckbox(app.Single_gridEcut, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', app.callback(@onCutChanged)), 3, 1);
            app.at(uibutton(gPol, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', app.callback(@exportCut)), 4, 4);
            app.Single_AxesRect = uiaxes(uigridlayout(uitab(tabCut, 'Title', 'Rectangular Cut Plot'), 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}));
            set(app.Single_AxesRect, 'Box', 'on');

            % Plot control
            app.Single_Panel_plotControl = app.at(uipanel(main, 'Title', 'Plot Control 🎨', 'Visible', 'off'), 2, [13, 14]);
            C = uigridlayout(app.Single_Panel_plotControl, 'RowHeight', repmat({'fit'}, 1, 15));
            app.rlabel(C, 'Component', 1, 1);
            app.Single_DropDown_Component = app.at(uidropdown(C, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', app.callback(@onComponentChanged)), 1, 2);
            app.rlabel(C, 'Cut type', 2, 1);
            app.Single_DropDown_cutType = app.at(uidropdown(C, 'Items', {'Phi', 'Theta'}, 'ValueChangedFcn', app.callback(@onCutChanged)), 2, 2);
            app.rlabel(C, 'Cut value', 3, 1);
            app.Single_Spinner_cutValue = app.at(uispinner(C, 'Limits', [0, 360], 'ValueChangedFcn', app.callback(@onCutChanged)), 3, 2);
            app.rlabel(C, 'Cut fields', 4, 1);
            app.CutFieldBasisDropDown = app.at(uidropdown(C, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Enable', 'off', 'ValueChangedFcn', app.callback(@onCutChanged)), 4, 2);
            app.rlabel(C, 'Colorbar max', 5, 1);
            app.Single_Plot_Cmax = app.at(uispinner(C, 'Limits', [-250, 100], 'Value', 10), 5, 2);
            app.rlabel(C, 'Colorbar min', 6, 1);
            app.Single_Plot_Cmin = app.at(uispinner(C, 'Limits', [-250, 100], 'Value', -40), 6, 2);
            set([app.Single_Plot_Cmin, app.Single_Plot_Cmax], 'ValueChangedFcn', @(~, ~) app.setRange("all", [app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value], true));
            app.rlabel(C, 'Colorbar step', 7, 1);
            app.Single_Plot_Cstep = app.at(uispinner(C, 'Limits', [0.1, 100], 'Value', 5, 'ValueChangedFcn', @(~, ~) app.applyFullRange()), 7, 2);
            app.rlabel(C, 'Adjust Colorbar', 8, 1);
            app.at(uibutton(C, 'Text', 'Apply', 'Tooltip', 'Apply the colour-bar min/max to full-pattern and cut plots.', ...
                'ButtonPushedFcn', @(~, ~) app.setRange("all", [app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value], true)), 8, 2);
            app.rlabel(C, '3D view', 9, 1);
            app.Single_DropDown_3DView = app.at(uidropdown(C, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Tooltip', 'Camera direction for the 3D pattern tabs.', 'ValueChangedFcn', app.callback(@on3DViewChanged)), 9, 2);
            pad = @(n) repmat(char(160), 1, n);   % non-breaking padding keeps the switch bodies centred
            app.Single_Switch_AngularSpan = app.at(uiswitch(C, 'slider', 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'ValueChangedFcn', app.callback(@spanChanged)), 10, [1, 2]);
            app.Single_Switch_ThetaSpan = app.at(uiswitch(C, 'slider', 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'ValueChangedFcn', app.callback(@spanChanged)), 11, [1, 2]);
            app.Single_Switch_EHplane = app.at(uiswitch(C, 'slider', 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'ValueChangedFcn', app.callback(@onPlaneChanged)), 12, [1, 2]);
            app.Single_CheckBox_overlayCut = app.at(uicheckbox(C, 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', @(~, ~) app.drawOverlay()), 13, [1, 2]);
            app.Single_CheckBox_POB = app.at(uicheckbox(C, 'Text', 'Annotate POB', 'ValueChangedFcn', app.callback(@onPOBToggled)), 14, [1, 2]);
            app.Single_CheckBox_HPBWBounds = app.at(uicheckbox(C, 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', app.callback(@onCutChanged)), 15, [1, 2]);

            % Data tables
            app.Single_DropDown_output = app.at(uidropdown(main, 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Visible', 'off', 'ValueChangedFcn', app.callback(@filterOutput)), 3, [13, 14]);
            app.Single_tabData = app.at(uitabgroup(main, 'Visible', 'off'), 4, [1, 14]);
            app.Single_Table_DataOut = uitable(uigridlayout(uitab(app.Single_tabData, 'Title', 'Results 📤'), 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}), 'ColumnWidth', '1x', 'RowName', 'numbered', 'ColumnSortable', true, 'ColumnRearrangeable', 'on');
            app.Single_Table_DataIn = uitable(uigridlayout(uitab(app.Single_tabData, 'Title', 'Input 📥'), 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}), 'RowName', 'numbered', 'ColumnSortable', true, 'ColumnRearrangeable', 'on');
            app.Single_Table_metadata = uitable(uigridlayout(uitab(app.Single_tabData, 'Title', 'Metadata 📋'), 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {220, 'auto'}, 'RowName', {});
            app.Single_StatusBar = app.at(uilabel(main, 'Interpreter', 'html', 'Text', 'Ready 🚀'), 5, [1, 14]);

            % ------------------------------------------------------------ Coverage tab
            app.Tab2_Coverage = uitab(app.TabGroup, 'Title', 'Compute Coverage 📈');
            cov = uigridlayout(app.Tab2_Coverage, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            app.Cov_gridPanel_Parm = uigridlayout(app.at(uipanel(cov, 'Title', 'Inputs & Parameters 🎛️'), 1, [1, 5]), 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'});
            Q = app.Cov_gridPanel_Parm;
            covType = app.at(uibuttongroup(Q, 'Title', 'Coverage Type', 'SelectionChangedFcn', app.callback(@covTypeChanged)), [1, 2], [1, 2]);
            uiradiobutton(covType, 'Text', 'Spherical 🌐', 'Position', [11, 63, 91, 22], 'Value', true);
            app.Cov_ButtonGroup_Btn_Conical = uiradiobutton(covType, 'Text', 'Conical 🔻', 'Position', [11, 41, 82, 22]);
            L.CovPath = app.rlabel(Q, 'Antenna Pattern:', 1, 3);
            app.Cov_EditField_filePath = app.at(uieditfield(Q, 'text'), 1, [4, 8]);
            app.Cov_Button_Load = app.at(uibutton(Q, 'Text', '📂 Load File', 'ButtonPushedFcn', app.callback(@covLoad)), 1, 9);
            app.Cov_Button_computeCov = app.at(uibutton(Q, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'ButtonPushedFcn', app.callback(@computeCoverage)), 1, 10);
            app.rlabel(Q, 'Threshold  Min (dB):', 2, 3); app.Cov_Spinner_ThreshMin = app.at(uispinner(Q, 'Value', -40), 2, 4);
            app.rlabel(Q, 'Threshold  Max (dB):', 2, 5); app.Cov_Spinner_ThreshMax = app.at(uispinner(Q, 'Value', 10), 2, 6);
            app.rlabel(Q, 'Step (dB):', 2, 7); app.Cov_Spinner_Step = app.at(uispinner(Q, 'Value', 1, 'Limits', [0.1, 100]), 2, 8);
            app.Cov_Button_Reset = app.at(uibutton(Q, 'Text', '🔄 Reset', 'ButtonPushedFcn', app.callback(@resetCoverage)), 2, 9);
            app.Cov_Button_Export = app.at(uibutton(Q, 'Text', '💾 Export Results', 'ButtonPushedFcn', @(~, ~) app.exportTable(app.Cov_Table.Data, 'coverage_results.csv', 'Export Coverage Results', app.Cov_StatusBar)), 2, 10);
            L.CovOrientation = app.rlabel(Q, 'Orientation 🧭:', 3, 1);
            app.Cov_DropDown_Orientation = app.at(uidropdown(Q, 'Items', [{'Auto'}, app.PrincipalAxes.labels], 'ItemsData', 0:numel(app.PrincipalAxes.labels), 'ValueChangedFcn', app.callback(@orientationChanged)), 3, 2);
            L.ConeTH = app.rlabel(Q, 'Cone θ₀ (°):', 3, 3); app.Cov_Spinner_ConeTH = app.at(uispinner(Q, 'Limits', [0, 180]), 3, 4);
            L.ConePH = app.rlabel(Q, 'Cone φ₀ (°):', 3, 5); app.Cov_Spinner_ConePH = app.at(uispinner(Q, 'Limits', [0, 360]), 3, 6);
            L.ConeAng = app.rlabel(Q, 'Cone Angle α (°):', 3, 7); app.Cov_Spinner_ConeAng = app.at(uispinner(Q, 'Limits', [0, 180], 'Value', 45), 3, 8);
            app.Cov_Button_Clear = app.at(uibutton(Q, 'Text', '🧹 Clear DataTips', 'ButtonPushedFcn', app.callback(@clearQueries)), 3, 9);
            app.Cov_Button_toMain = app.at(uibutton(Q, 'Text', '📊 To Main ◀', 'ButtonPushedFcn', @(~, ~) set(app.TabGroup, 'SelectedTab', app.Tab1_Single)), 3, 10);
            L.CovComponent = app.rlabel(Q, 'Component:', 4, 1);
            app.Cov_DropDown_Component = app.at(uidropdown(Q, 'Items', {'E_Total_dB'}, 'ValueChangedFcn', app.callback(@covComponentChanged)), 4, 2);
            L.QueryCov = app.rlabel(Q, 'Coverage @ dB:', 4, 3);
            app.Cov_Spinner_queryCov = app.at(uispinner(Q, 'ValueDisplayFormat', '%g dB'), 4, 4);
            app.Cov_Button_queryCov = app.at(uibutton(Q, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', @(~, ~) app.runQuery("cov")), 4, 5);
            L.QueryThr = app.rlabel(Q, 'Threshold @ %:', 4, 6);
            app.Cov_Spinner_queryThresh = app.at(uispinner(Q, 'Value', 50, 'ValueDisplayFormat', '%g%%'), 4, 7);
            app.Cov_Button_queryThresh = app.at(uibutton(Q, 'Text', '🔍 Query Threshold', 'ButtonPushedFcn', @(~, ~) app.runQuery("thr")), 4, 8);
            L.CovFormat = app.rlabel(Q, 'Format:', 4, 9);
            app.Cov_DropDown_TextFormat = app.at(app.formatDropdown(Q, @covFormatChanged), 4, 10);
            app.Cov_Panel_Results = app.at(uipanel(cov, 'Title', 'Results', 'Visible', 'off'), 2, [1, 5]);
            R = uigridlayout(app.Cov_Panel_Results, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            app.Cov_Tree = app.at(uitree(R, 'checkbox', 'SelectionChangedFcn', app.callback(@treeSelectionChanged), 'CheckedNodesChangedFcn', app.callback(@treeCheckedChanged)), [1, 2], 1);
            app.Cov_TreeNode_Results = uitreenode(app.Cov_Tree, 'Text', 'Coverage Results');
            app.Cov_Axes = app.at(uiaxes(R), 1, [2, 4]);
            title(app.Cov_Axes, 'Coverage vs Threshold'); xlabel(app.Cov_Axes, 'Threshold (dB)'); ylabel(app.Cov_Axes, 'Coverage (%)');
            app.Cov_Axes.Interactions = dataTipInteraction;   % display-only axes
            app.Cov_Spinner_XMin = app.at(uispinner(R, 'Limits', [-250, 100], 'Value', -40, 'ValueChangedFcn', app.callback(@syncXRange)), 2, 2);
            app.Cov_Slider_XRange = app.at(uislider(R, 'range', 'Limits', [-250, 100], 'Value', [-40, 10], 'ValueChangedFcn', app.callback(@syncXRange), 'ValueChangingFcn', app.callback(@syncXRange)), 2, 3);
            app.Cov_Spinner_XMax = app.at(uispinner(R, 'Limits', [-250, 100], 'Value', 10, 'ValueChangedFcn', app.callback(@syncXRange)), 2, 4);
            app.Cov_Table = app.at(uitable(R, 'ColumnWidth', '1x', 'RowName', {}), [1, 2], 5);
            app.Cov_StatusBar = app.at(uilabel(cov, 'Interpreter', 'html', 'Text', 'Ready 🚀'), 3, [1, 5]);
            app.Labels = L;
            app.UIFigure.Visible = 'on';
        end

        function startupFcn(app)
            app.statusTimer = timer('Name', 'APAT_status', 'ExecutionMode', 'singleShot', 'StartDelay', 3, 'TimerFcn', @(~, ~) app.restoreStatus());
            app.CovQueryControls = [app.Labels.QueryCov, app.Cov_Spinner_queryCov, app.Cov_Button_queryCov, app.Labels.QueryThr, app.Cov_Spinner_queryThresh, app.Cov_Button_queryThresh];
            app.CovConeControls = [app.Labels.CovOrientation, app.Cov_DropDown_Orientation, app.Labels.ConeTH, app.Cov_Spinner_ConeTH, app.Labels.ConePH, app.Cov_Spinner_ConePH, app.Labels.ConeAng, app.Cov_Spinner_ConeAng];
            for ax = [app.Single_Axes_Ctr, app.Single_AxesRect], enableDefaultInteractivity(ax); ax.Interactions = [zoomInteraction, dataTipInteraction]; end
            for ax = [app.Single_Axes_3dSph, app.Single_Axes_3dPol, app.Single_Axes_3dRect], enableDefaultInteractivity(ax); ax.Interactions = [rotateInteraction, dataTipInteraction]; end
            enableDefaultInteractivity(app.Single_paxPattern); enableDefaultInteractivity(app.Single_paxCut);
            set([app.Single_paxPattern, app.Single_paxCut], 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            hold(app.Cov_Axes, 'on'); grid(app.Cov_Axes, 'on'); ylim(app.Cov_Axes, [0, 100]); set(app.Cov_Axes, 'Box', 'on', 'Layer', 'top');
            [app.Single_StatusBar.UserData, app.Cov_StatusBar.UserData] = deal('Ready -- load an antenna pattern file to begin 🚀');
            app.setStatus(app.Single_StatusBar, app.Single_StatusBar.UserData, false); app.setStatus(app.Cov_StatusBar, app.Cov_StatusBar.UserData, false);
            app.defaultParams = struct('Loss', app.Single_Spinner_Loss.Value, 'RxMode', app.Single_DropDown_RxPol.Value, 'Rw', app.Single_Spinner_Rw.Value, ...
                'Pt', app.Single_Spinner_Pt.Value, 'PtUnit', app.Single_DropDown_Pt.Value, 'R', app.Single_Spinner_R.Value, 'RUnit', app.Single_DropDown_R.Value);
            app.setCoverageUI();
        end
    end

    % ====================================================================== PUBLIC API
    methods (Access = public)
        function app = APAT_v3_M8_30
            createComponents(app); registerApp(app, app.UIFigure); runStartupFcn(app, @startupFcn);
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true;
            if ~isempty(app.statusTimer) && isvalid(app.statusTimer), stop(app.statusTimer); delete(app.statusTimer); end
            if ~isempty(app.operationDialog) && isvalid(app.operationDialog), delete(app.operationDialog); end
            if isgraphics(app.UIFigure), delete(app.UIFigure); end
        end

        function report = runSelfTest(app)
            %RUNSELFTEST Deterministic numerical / policy smoke checks (throws when any check fails).
            [P, T] = meshgrid(0:30:330, (0:30:180)'); G = table(T(:), P(:), 10 * cosd(T(:)).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            w = solidWeights(G.Theta, G.Phi); r.solidAngleError = abs(sum(w) - 4 * pi); r.passSolidAngle = r.solidAngleError < 1e-9;
            [peak, axisIndex] = calcOrientation(G, w, 'E_Total_dB', app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
            r.passOrientation = isfinite(peak.value) && axisIndex >= 1 && axisIndex <= 6;
            % Regular-grid resampling reproduces native samples exactly.
            [P2, T2] = meshgrid(0:2:358, (0:2:180)'); A = 12 * cosd(T2).^2 - 0.5 * sind(P2).^2;
            R = resampleCanonical(table(T2(:), P2(:), A(:), 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'}), 1);
            native = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0 & R.Phi < 360;
            r.numericalError = max(abs(R.E_Total_dB(native) - (12 * cosd(R.Theta(native)).^2 - 0.5 * sind(R.Phi(native)).^2)));
            r.passResampling = height(R) == 181 * 361 && r.numericalError < 1e-9;
            % Display-range and isolated-spike peak policy.
            r.passDisplayRange = isequal(displayRange([3.2; -250; -17], app.PeakPercentile, app.PeakMaxExcessDB), [-45, 5]);
            spike = repmat(0.02, 100000, 1); spike(1) = 10.02; sp = resolvePeak(spike, app.PeakPercentile, app.PeakMaxExcessDB);
            r.passIsolatedSpike = sp.wasAdjusted && abs(sp.value - 0.02) < 1e-12 && sp.rawIndex == 1 && isequal(displayRange(spike, app.PeakPercentile, app.PeakMaxExcessDB), [-45, 5]);
            r.passARSemantic = all(arrayfun(@isAR, ["AR", "AR_dB", "AR dB", "Axial Ratio", "Axial_Ratio"]));
            r.passCCDF = isequal(coverageCCDF([0; 10; 20], true(3, 1), [5; 15; 25], [1; 1; 2]), [75; 50; 0]);
            % FFD reader contract: two axis triples, no frequency line, nine field rows.
            f = [tempname, '.ffd']; writelines(["0 180 3"; "-180 180 3"; compose("%d 0 0 1", (1:9)')], f); cleaner = onCleanup(@() delete(f));
            d = readPattern(f, "auto"); r.passFFDReader = strcmp(d.userData.source, 'HFSS FFD') && isscalar(d.blocks) && height(d.blocks{1}) == 9;
            names = fieldnames(r); checks = names(startsWith(names, 'pass')); ok = cellfun(@(n) r.(n), checks); r.pass = all(ok);
            report = r;
            if ~r.pass, error('apat:test:SelfTestFailed', 'Self-test failed: %s', strjoin(checks(~ok), ', ')); end
        end
    end
end

% ========================================================================== LOCAL FUNCTIONS (UI-independent)
% -------------------------------------------------------------------------- small utilities
function tf = isGenericText(fp), [~, ~, ext] = fileparts(char(fp)); tf = ismember(lower(ext), {'.csv', '.txt', '.dat'}); end

function tf = isAR(name)
% Axial-ratio semantics independent of column spelling (AR, AR_dB, "Axial Ratio", ...).
key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', ''); tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
end

function s = fmtNum(v, precision)
%FMTNUM Compact number text: up to 2 decimals with trailing zeros dropped, or exactly PRECISION decimals.
if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return; end
if nargin < 2, if abs(v) < 5e-3, v = 0; end, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); else, s = sprintf('%.*f', precision, v); end
end

function component = preferredComponent(previous, columns)
% Keep the previous selection when available, otherwise Total Gain, otherwise the first column.
if any(columns == string(previous)), component = string(previous); elseif any(columns == "E_Total_dB"), component = "E_Total_dB"; else, component = columns(1); end
end

function r = clampRange(values, bounds)
% Sorted, clamped two-element range at least one unit wide.
values = sort(double(values(:)')); if numel(values) < 2 || any(~isfinite(values(1:2))), r = bounds; return; end
r = [max(bounds(1), values(1)), min(bounds(2), values(2))];
if diff(r) < 1, r(2) = min(bounds(2), r(1) + 1); r(1) = max(bounds(1), r(2) - 1); end
end

function ticks = makeTicks(limits, step)
% Tick vector at multiples of STEP that also includes both limits (empty when unusable or too dense).
ticks = [];
if ~isfinite(step) || step <= 0 || diff(limits) <= 0, return; end
ticks = unique([limits(1), ceil(limits(1) / step) * step:step:floor(limits(2) / step) * step, limits(2)], 'stable');
if numel(ticks) > 60, ticks = []; end
end

function [x, y] = queryPoint(d, mode, request)
% Coverage-curve lookup: "cov" → coverage at threshold x; "thr" → threshold at coverage y (via the inverse CCDF).
[x, y] = deal(NaN);
if mode == "cov", x = request; if numel(d.thr) > 1, y = interp1(d.thr, d.cov, request, 'linear', NaN); end
else, y = request; if numel(d.invCov) > 1, x = interp1(d.invCov, d.invThr, request, 'linear', NaN); end
end
end

function writeTable(T, fp)
if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
end

function writeUAN(U, fp)
% XGTD UAN: canonical parameter header followed by magnitude/phase rows.
header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
    min(U.Phi), max(U.Phi), gridStep(U.Phi), min(U.Theta), max(U.Theta), gridStep(U.Theta), max([U.E_TH_DB; U.E_PH_DB]));
writelines(header, fp);
writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
end

% -------------------------------------------------------------------------- numerical core
function step = gridStep(values)
% Smallest positive spacing of the unique finite values (NaN for a single value).
d = diff(unique(values(isfinite(values)))); d = d(d > 1e-9);
if isempty(d), step = NaN; else, step = min(d); end
end

function dOmega = solidWeights(theta, phi)
% Exact solid angle of each sample's uniform cell; the duplicated closing φ seam gets zero weight.
thetaStep = gridStep(theta); phiStep = gridStep(mod(phi, 360));
if ~isfinite(thetaStep), thetaStep = 180; end
if ~isfinite(phiStep), phiStep = 360; end
dOmega = (cosd(max(theta - thetaStep / 2, 0)) - cosd(min(theta + thetaStep / 2, 180))) * deg2rad(phiStep);
dOmega(abs(phi - 360) < 1e-9) = 0;
end

function [gain, column] = chooseGain(T, requested)
% Requested column if present, else E_Total_dB, else the first data column.
vars = string(T.Properties.VariableNames); k = find(ismember([string(requested), "E_Total_dB"], vars), 1);
if isempty(k), column = char(vars(3)); elseif k == 1, column = char(requested); else, column = 'E_Total_dB'; end
gain = T.(column);
end

function info = resolvePeak(values, percentile, maxExcessDB)
%RESOLVEPEAK APAT peak policy: the raw maximum is accepted unless it exceeds the P<percentile> level by more than
% maxExcessDB; then the highest sample at or below that level is the effective peak and the samples above it are outliers.
finiteMask = isfinite(values);
info = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(values)), 'wasAdjusted', false);
if ~any(finiteMask), return; end
[info.rawValue, info.rawIndex] = max(values, [], 'omitnan'); [info.value, info.index] = deal(info.rawValue, info.rawIndex);
sorted = sort(values(finiteMask)); n = numel(sorted); if n < 2, return; end
level = interp1(1:n, sorted, 1 + (n - 1) * percentile / 100);   % linear-interpolated percentile (no toolbox dependency)
if info.rawValue <= level + maxExcessDB, return; end
info.outlierMask = finiteMask & values > level; candidates = values; candidates(~finiteMask | info.outlierMask) = -Inf;
if any(isfinite(candidates)), [info.value, info.index] = max(candidates); info.wasAdjusted = true; end
end

function bounds = displayRange(values, percentile, maxExcessDB)
% 50-dB window whose upper edge is the effective peak rounded up to 5 dB (shared by colour scales and coverage presets).
values = values(isfinite(values));
if isempty(values), bounds = [-40, 10]; return; end
peak = resolvePeak(values, percentile, maxExcessDB); upper = ceil(peak.value / 5) * 5;
bounds = clampRange([upper - 50, upper], [-250, 100]);
end

function T = normalizePattern(T)
%NORMALIZEPATTERN Map any angular convention onto the canonical sphere: θ∈[0,180], φ∈[0,360), plus a closing φ=360 copy.
theta = T.Theta;
if any(theta < 0)
    if min(theta) >= -90 && max(theta) <= 90, T.Theta = 90 - theta;                 % elevation convention
    else, m = theta < 0; T.Theta(m) = -theta(m); T.Phi(m) = T.Phi(m) + 180;         % negative θ folds onto the opposite φ
    end
end
T.Theta = mod(T.Theta, 360); over = T.Theta > 180; T.Theta(over) = 360 - T.Theta(over); T.Phi(over) = T.Phi(over) + 180;
numeric = varfun(@isnumeric, T, 'OutputFormat', 'uniform'); T{:, numeric} = round(T{:, numeric}, 5);   % kill seam round-off once
T.Phi = mod(T.Phi, 360);
[~, keep] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(sort(keep), :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function [P, info] = calcPattern(S, param, percentile, maxExcessDB)
%CALCPATTERN Canonical primitives → processed pattern table (gain, polarization, PLF, link quantities).
info = struct('POB', NaN, 'POBth', NaN, 'POBph', NaN, 'pol', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
ud = S.Properties.UserData;
if ud.isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + param.GainLoss_dB; end
    peak = resolvePeak(P{:, 3}, percentile, maxExcessDB); info.peak = peak;
    [info.POB, info.POBth, info.POBph] = deal(peak.value, P.Theta(peak.index), P.Phi(peak.index)); return
end
Eth = complex(S.Re_Eth, S.Im_Eth) * param.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph) * param.FieldScale;
Ercp = (Eth + 1i * Eph) / sqrt(2); Elcp = (Eth - 1i * Eph) / sqrt(2);
[mTh, mPh, mR, mL] = deal(abs(Eth), abs(Eph), abs(Ercp), abs(Elcp));
totalGain = 10 * log10(max(mTh.^2 + mPh.^2, eps));
peak = resolvePeak(totalGain, percentile, maxExcessDB); info.peak = peak;
[info.POB, info.POBth, info.POBph] = deal(peak.value, S.Theta(peak.index), S.Phi(peak.index));
% Dominant components drive co/cross ordering, the polarization label and the Auto receive sense.
pw = [mean(mTh.^2, 'omitnan'), mean(mPh.^2, 'omitnan'), mean(mR.^2, 'omitnan'), mean(mL.^2, 'omitnan')];   % TH PH RCP LCP
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif pw(1) >= pw(2), info.pol = 'Linear (Vertical)';
else, info.pol = 'Linear (Horizontal)';
end
% Signed axial ratio (+ right-hand, − left-hand); equal circular components are the linear limit (−100 dB floor).
delta = mR - mL; sense = sign(delta); sense(~isfinite(delta)) = 0;
axialRatio = (mR + mL) ./ max(abs(delta), eps);
signedAR = min(20 * log10(axialRatio), 250) .* sense; signedAR(isfinite(delta) & abs(delta) <= eps * max(mR + mL, 1)) = -100;
% Polarization loss factor against the incident wave (axial ratio Rw, sense from the UI or the dominant hand).
switch param.RxMode
    case "Auto", waveSense = 2 * (info.pairs.Circular(1) == "E_RCP") - 1;
    case "RHCP", waveSense = 1;
    otherwise,   waveSense = -1;
end
ra = axialRatio .* sense; ra(sense == 0) = 1e12; rw = waveSense * 10^(param.RxAR_dB / 20);
plf = 0.5 + (4 * ra * rw - (ra.^2 - 1) * (rw^2 - 1)) ./ (2 * (ra.^2 + 1) * (rw^2 + 1));   % tilt term cos(2Δτ) = −1
plfDB = 10 * log10(min(max(plf, eps), 1));
eirpW = 10.^((param.Pt_dBW + totalGain) / 10);
P = table(S.Theta, S.Phi, totalGain, signedAR, 20 * log10(max(mR, eps)), 20 * log10(max(mL, eps)), plfDB, totalGain + plfDB, ...
    20 * log10(max(mTh, eps)), 20 * log10(max(mPh, eps)), rad2deg(angle(Eth)), rad2deg(angle(Eph)), rad2deg(angle(Ercp)), rad2deg(angle(Elcp)), ...
    param.Pt_dBW + totalGain, eirpW / (4 * pi * param.R_m^2), sqrt(30 * eirpW) / param.R_m, ...
    'VariableNames', {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', 'PLF_dB', 'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', ...
    'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
P.Properties.UserData = ud;
end

function [peak, axisIndex] = calcOrientation(T, dOmega, column, axes_, percentile, maxExcessDB)
%CALCORIENTATION Effective peak of COLUMN and the principal axis whose 45° cone captures the most weighted power.
gain = chooseGain(T, column); peak = resolvePeak(gain, percentile, maxExcessDB);
if peak.wasAdjusted, gain(peak.outlierMask) = NaN; end
w = 10.^((gain - peak.value) / 10) .* dOmega; w(~isfinite(w)) = 0;
A = [sind(axes_.theta(:)) .* cosd(axes_.phi(:)), sind(axes_.theta(:)) .* sind(axes_.phi(:)), cosd(axes_.theta(:))];
S = [sind(T.Theta) .* cosd(T.Phi), sind(T.Theta) .* sind(T.Phi), cosd(T.Theta)];
[~, axisIndex] = max(w' * double(S * A' >= cosd(45)));
end

function m = calcMetrics(T, dOmega, axes_, percentile, maxExcessDB)
%CALCMETRICS Scalar antenna metrics of the total gain: peak, HPBW (E/H planes of the boresight axis), F/B, directivity, efficiency.
gain = chooseGain(T, 'E_Total_dB'); peak = resolvePeak(gain, percentile, maxExcessDB); k = peak.index;
g = gain; if peak.wasAdjusted, g(peak.outlierMask) = NaN; end
integrated = sum(10.^(g / 10) .* dOmega, 'omitnan');
directivity = 10 * log10(max(4 * pi * 10^(peak.value / 10) / max(integrated, eps), eps));
efficiency = 100 * integrated / (4 * pi); if efficiency > 100, efficiency = NaN; end
[~, back] = min(cosd(T.Theta) * cosd(T.Theta(k)) + sind(T.Theta) * sind(T.Theta(k)) .* cosd(T.Phi - T.Phi(k)));
ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(k); end
i = axes_.index; [eAngle, eRows] = calcCutGeometry(T, "Theta", axes_.phi(i));
if axes_.theta(i) == 90, [hAngle, hRows] = calcCutGeometry(T, "Phi", 90); else, [hAngle, hRows] = calcCutGeometry(T, "Theta", 90); end
m = struct('PeakGain_dB', peak.value, 'PeakTheta_deg', T.Theta(k), 'PeakPhi_deg', T.Phi(k), 'HPBW_EPlane_deg', calcHPBW(eAngle, gain(eRows)), ...
    'HPBW_HPlane_deg', calcHPBW(hAngle, gain(hRows)), 'FrontBack_dB', peak.value - gain(back), 'PeakDirectivity_dB', directivity, ...
    'Efficiency_pct', efficiency, 'AxialRatioAtPeak_dB', ar);
end

function [angleDeg, rows, fixedAngle, symbol, snapped] = calcCutGeometry(T, cutType, requested)
%CALCCUTGEOMETRY Rows of one full-circle cut through canonical data, snapped to the nearest sampled plane.
% "Phi" cut: fixed θ, angle = φ. "Theta" cut: fixed φ, angle = θ on the primary half and 360−θ on the opposite half.
if cutType == "Phi"
    thetas = unique(T.Theta); [dist, k] = min(abs(thetas - requested)); fixedAngle = thetas(k);
    rows = find(abs(T.Theta - fixedAngle) < 1e-9); [angleDeg, order] = sort(T.Phi(rows)); rows = rows(order); symbol = 'θ';
else
    phis = unique(mod(T.Phi, 360)); wrapped = mod(T.Phi, 360);
    [dist, k] = min(abs(mod(phis - requested + 180, 360) - 180)); fixedAngle = phis(k);
    [~, opp] = min(abs(mod(phis - fixedAngle, 360) - 180));
    primary = find(abs(wrapped - fixedAngle) < 1e-9); opposite = find(abs(wrapped - phis(opp)) < 1e-9 & abs(T.Theta - 180) > 1e-9);
    [~, o1] = sort(T.Theta(primary)); [~, o2] = sort(T.Theta(opposite), 'descend'); primary = primary(o1); opposite = opposite(o2);
    rows = [primary; opposite]; angleDeg = [T.Theta(primary); 360 - T.Theta(opposite)]; symbol = 'φ';
end
snapped = dist > 1e-9;
end

function [bw, lower, upper] = calcHPBW(angleDeg, gainDB, peakGain, peakAngle)
%CALCHPBW Half-power beamwidth of a circular cut by linear interpolation of the −3 dB crossings around the peak.
[bw, lower, upper] = deal(NaN); valid = isfinite(angleDeg) & isfinite(gainDB); angleDeg = angleDeg(valid); gainDB = gainDB(valid);
if numel(gainDB) < 3, return; end
if nargin < 3, [peakGain, k] = max(gainDB); peakAngle = angleDeg(k); end
[rel, order] = sort(mod(angleDeg - peakAngle + 180, 360) - 180); g = gainDB(order); half = peakGain - 3;
L = find(rel < 0 & g <= half, 1, 'last'); R = find(rel > 0 & g <= half, 1, 'first');
if isempty(L) || isempty(R) || L + 1 > numel(g) || R - 1 < 1 || g(L + 1) == g(L) || g(R - 1) == g(R), return; end
left = rel(L) + (rel(L + 1) - rel(L)) * (half - g(L)) / (g(L + 1) - g(L));
right = rel(R) + (rel(R - 1) - rel(R)) * (half - g(R)) / (g(R - 1) - g(R));
[bw, lower, upper] = deal(right - left, peakAngle + left, peakAngle + right);
end

function coverage = coverageCCDF(gain, regionMask, thresholds, dOmega)
%COVERAGECCDF Coverage(T) [%] = 100 · Σ I(G_i > T)·Ω_i / Σ Ω_i over the region (vectorised over all thresholds).
valid = regionMask(:) & isfinite(gain(:)) & isfinite(dOmega(:)) & dOmega(:) >= 0;
g = gain(valid); w = dOmega(valid); total = sum(w); coverage = zeros(numel(thresholds), 1);
if total > 0, coverage = 100 * (w' * (g > thresholds(:)'))' / total; end
end

function R = resampleCanonical(S, step)
%RESAMPLECANONICAL Resample canonical primitives onto a STEP° grid (θ 0..180, φ 0..360 closed).
% Complete rectangular grids use periodic interp2; irregular sources use one scattered interpolant per column.
% Gain-like dB columns of gain-only sources are interpolated in linear power.
theta = double(S.Theta); phi = mod(double(S.Phi), 360);
keep = find(isfinite(theta) & isfinite(phi) & abs(double(S.Phi) - 360) > 1e-9);   % the φ=0 sample is authoritative
[~, u] = unique([theta(keep), phi(keep)], 'rows', 'stable'); keep = keep(u); S = S(keep, :); theta = theta(keep); phi = phi(keep);
tPhi = 0:step:360; if tPhi(end) ~= 360, tPhi(end + 1) = 360; end
[qPhi, qTheta] = meshgrid(tPhi, 0:step:180); R = table(qTheta(:), qPhi(:), 'VariableNames', {'Theta', 'Phi'});
names = S.Properties.VariableNames(3:end); ud = S.Properties.UserData;
gainOnly = isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly;
[sT, ~, it] = unique(theta); [sP, ~, ip] = unique(phi); lin = sub2ind([numel(sT), numel(sP)], it, ip);
regular = numel(sT) * numel(sP) == numel(theta) && numel(unique(lin)) == numel(lin);
if regular, [gP, gT] = meshgrid([sP; sP(1) + 360], sT); end
for k = 1:numel(names)
    v = double(S.(names{k})); toLinear = gainOnly && endsWith(lower(names{k}), 'db');
    if toLinear, v = 10.^(v / 10); end
    if regular
        V = nan(numel(sT), numel(sP)); V(lin) = v; V(:, end + 1) = V(:, 1);   %#ok<AGROW> periodic closing column
        Q = interp2(gP, gT, V, qPhi, qTheta, 'linear', NaN); miss = ~isfinite(Q);
        if any(miss(:)), N = interp2(gP, gT, V, qPhi, qTheta, 'nearest', NaN); Q(miss) = N(miss); end
    else
        F = scatteredInterpolant(phi, theta, v, 'linear', 'nearest'); Q = F(qPhi, qTheta);
    end
    if toLinear, Q = 10 * log10(max(Q, realmin)); end
    R.(names{k}) = Q(:);
end
R.Properties.UserData = ud;
end

% -------------------------------------------------------------------------- readers
function out = readPattern(fp, textFormat, cached)
%READPATTERN Parse any supported source into {rawTbl, blocks{canonical}, freqs, userData, cache}.
% Canonical block columns: Theta Phi Re_Eth Im_Eth Re_Eph Im_Eph — or Theta Phi <gain columns> for gain-only sources.
if nargin < 3, cached = table(); end
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, 'cache', table(), ...
    'userData', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'hasFrequency', false));
switch ext
    case {'XLSX', 'XLS'},        out = readExcelMatrix(fp, out);
    case {'CSV', 'TXT', 'DAT'},  out = readGenericText(fp, string(textFormat), cached, out);
    case 'CUT',                  out = readGraspCut(fp, out);
    otherwise,                   out = readFarField(fp, ext, out);
end
end

function T = fieldTable(theta, phi, Eth, Eph)
T = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function [Eth, Eph] = circularToLinear(Ercp, Elcp), Eth = (Ercp + Elcp) / sqrt(2); Eph = (Ercp - Elcp) / (1i * sqrt(2)); end

function E = fromMagPhase(dB, deg), E = 10.^(dB / 20) .* exp(1i * deg2rad(deg)); end

function out = readGenericText(fp, fmt, T, out)
% CSV/TXT/DAT: coverage-results table, gain-only pattern, or a six-column E-field layout selected by FMT.
if isempty(T)
    opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
    T = rmmissing(readtable(fp, opts));
end
out.cache = T; n = width(T); assert(n >= 2 && ~isempty(T), 'readFile:InvalidFormat', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHeaders = ~all(startsWith(names, "Var")); c1 = T{:, 1}; c2 = T{:, 2};
coverageHeader = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
if (fmt == "gain" || n < 6 || coverageHeader) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:n - 1))]; end
    out.rawTbl = T; out.userData.isCoverage = true; return
end
if fmt == "gain"   % the wider-spanning of the first two columns is φ
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; T = movevars(T, 'Theta', 'Before', 1);
    else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'};
    end
    out.rawTbl = T; out.blocks = {T}; out.userData.isGainOnly = true; out.userData.source = 'Generic text (gain)'; return
end
assert(n >= 6, 'readFile:TextEFieldColumns', 'The selected E-field format requires six numeric columns.');
V = T{:, 3:6}; magPhase = endsWith(fmt, "magphase"); layout = "n/a";
if magPhase   % phase columns exceed 100 (degrees): detect grouped [m1 m2 p1 p2] vs interleaved [m1 p1 m2 p2]
    big = max(abs(V), [], 1, 'omitnan') > 100;
    if big(2) && ~big(3), mc = [1, 3]; pc = [2, 4]; layout = "interleaved"; else, mc = [1, 2]; pc = [3, 4]; layout = "grouped"; end
    E1 = fromMagPhase(V(:, mc(1)), V(:, pc(1))); E2 = fromMagPhase(V(:, mc(2)), V(:, pc(2)));
else
    E1 = complex(V(:, 1), V(:, 2)); E2 = complex(V(:, 3), V(:, 4));
end
if startsWith(fmt, "linear"), [Eth, Eph] = deal(E1, E2); comp = ["E_TH", "E_PH"];
elseif startsWith(fmt, "rcp"), [Eth, Eph] = circularToLinear(E1, E2); comp = ["POL1", "POL2"];
else, [Eth, Eph] = circularToLinear(E2, E1); comp = ["POL1", "POL2"];
end
if ~hasHeaders
    if magPhase, gen = [comp + "_dB", comp + "_deg"]; if layout == "interleaved", gen = gen([1, 3, 2, 4]); end
    else, gen = [comp(1) + ["_re", "_im"], comp(2) + ["_re", "_im"]];
    end
    T.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", gen]);
end
out.userData.source = sprintf('Generic text (%s, %s)', fmt, layout); out.rawTbl = T; out.blocks = {fieldTable(c1, c2, Eth, Eph)};
end

function out = readGraspCut(fp, out)
% TICRA/GRASP *.cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks, one per φ (or θ when ICUT=2).
lines = readlines(fp); lines(strlength(strtrim(lines)) == 0) = []; i = 1; th = {}; ph = {}; D = {}; icomp = 1; icut = 1;
while i < numel(lines)
    p = sscanf(lines(i + 1), '%f'); assert(numel(p) >= 7, 'readFile:cut', 'Could not parse the GRASP cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6);
    block = reshape(sscanf(strjoin(lines(i + 2:i + 1 + n), ' '), '%f'), 2 * p(7), []).';
    th{end + 1} = p(1) + (0:n - 1)' * p(2); ph{end + 1} = repmat(p(4), n, 1); D{end + 1} = block(:, 1:4); %#ok<AGROW>
    i = i + 2 + n;
end
th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:});
if icut == 2, [th, ph] = deal(ph, th); end
neg = th < 0; ph(neg) = ph(neg) + 180; th(neg) = -th(neg);   % fold negative θ onto the opposite φ
if isscalar(unique(ph))                                      % single cut → body of revolution
    copies = (0:10:350)'; m = numel(th); th = repmat(th, numel(copies), 1); ph = repelem(copies, m); D = repmat(D, numel(copies), 1);
end
E1 = complex(D(:, 1), D(:, 2)); E2 = complex(D(:, 3), D(:, 4));
if icomp == 2, [Eth, Eph] = circularToLinear(E1, E2); names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; else, [Eth, Eph] = deal(E1, E2); names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; end
out.userData.source = 'TICRA/GRASP CUT'; out.rawTbl = array2table([th, ph, D], 'VariableNames', [{'Theta', 'Phi'}, names]); out.blocks = {fieldTable(th, ph, Eth, Eph)};
end

function out = readFarField(fp, ext, out)
% Column-oriented far-field exports: XGTD UAN/FZ, GRASP OUT, CST FFS, FEKO FFE and HFSS FFD (header-defined grid, multi-block).
[nHdr, ffd] = findHeaderLines(fp);
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
D = readmatrix(fp, setvartype(opts, opts.VariableNames, 'double')); D = D(~all(isnan(D), 2), 1:min(end, 6));
switch ext
    case {'FZ', 'UAN'}   % Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
        names = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}; th = D(:, 1); ph = D(:, 2);
        Eth = fromMagPhase(D(:, 3), D(:, 5)); Eph = fromMagPhase(D(:, 4), D(:, 6)); src = ['XGTD ' ext];
    case 'OUT'           % Theta Phi Re/Im POL1 (RHCP) Re/Im POL2 (LHCP)
        names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; th = D(:, 1); ph = D(:, 2);
        [Eth, Eph] = circularToLinear(complex(D(:, 3), D(:, 4)), complex(D(:, 5), D(:, 6))); src = 'TICRA/GRASP OUT';
    case 'FFS'           % Phi Theta Re/Im Eth Re/Im Eph
        names = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; ph = D(:, 1); th = D(:, 2);
        Eth = complex(D(:, 3), D(:, 4)); Eph = complex(D(:, 5), D(:, 6)); src = 'CST FFS';
    case 'FFE'           % Theta Phi Re/Im Eth Re/Im Eph (extra columns ignored)
        names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; th = D(:, 1); ph = D(:, 2);
        Eth = complex(D(:, 3), D(:, 4)); Eph = complex(D(:, 5), D(:, 6)); src = 'FEKO FFE';
    case 'FFD'
        assert(ffd.isFFD, 'readFile:ffd', 'FFD header (theta/phi ranges) not found.');
        tAxis = linspace(ffd.theta(1), ffd.theta(2), round(ffd.theta(3)))'; pAxis = linspace(ffd.phi(1), ffd.phi(2), round(ffd.phi(3)))';
        th = repelem(tAxis, numel(pAxis)); ph = repmat(pAxis, numel(tAxis), 1); n = numel(th);
        sep = isnan(D(:, 1)); freqs = [ffd.freq(:); D(sep & ~isnan(D(:, 2)), 2)]';   % "Frequency <f>" separator rows
        rows = D(~sep, 1:4); assert(mod(size(rows, 1), n) == 0, 'readFile:ffd', 'FFD row count does not match the theta/phi grid.');
        nb = size(rows, 1) / n; freqs(end + 1:nb) = NaN; freqs = freqs(1:nb);
        out.blocks = arrayfun(@(b) fieldTable(th, ph, complex(rows((b - 1) * n + (1:n), 1), rows((b - 1) * n + (1:n), 2)), ...
            complex(rows((b - 1) * n + (1:n), 3), rows((b - 1) * n + (1:n), 4))), 1:nb, 'UniformOutput', false);
        out.freqs = freqs; out.rawTbl = out.blocks{1}; out.userData.source = 'HFSS FFD';
        out.userData.hasFrequency = any(isfinite(freqs)); out.userData.isDep = nb > 1 || out.userData.hasFrequency; return
    otherwise
        error('readFile:unsupported', 'Unsupported format: %s', ext);
end
out.rawTbl = array2table(D(:, 1:6), 'VariableNames', names); out.userData.source = src; out.blocks = {fieldTable(th, ph, Eth, Eph)};
end

function [nHdr, ffd] = findHeaderLines(fp)
%FINDHEADERLINES Leading non-data line count; recognises the HFSS FFD header (two axis triples + optional "Frequencies" line).
lines = strtrim(readlines(fp)); nonEmpty = find(strlength(lines) > 0); ffd = struct('isFFD', false, 'theta', [], 'phi', [], 'freq', []);
triples = zeros(0, 3); last = 0;
for i = nonEmpty(1:min(2, end))'
    v = sscanf(char(lines(i)), '%f'); if numel(v) ~= 3, break; end
    triples(end + 1, :) = v'; last = i; %#ok<AGROW>
end
if size(triples, 1) == 2 && all(isfinite(triples(:))) && all(triples(:, 3) >= 1)
    ffd = struct('isFFD', true, 'theta', triples(1, :), 'phi', triples(2, :), 'freq', []); nHdr = last;
    next = nonEmpty(find(nonEmpty > last, 1));
    if ~isempty(next)
        tok = regexp(lines(next), '^frequencies?\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok), nHdr = next; f = sscanf(char(tok{1}), '%f'); if ~isscalar(f), ffd.freq = f(:); end, end
    end
    return
end
num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?';   % header ends before the first line with ≥4 numeric fields
isData = ~cellfun('isempty', regexp(cellstr(lines), ['^' num '(?:[\s,;]+' num '){3,}$'], 'once'));
nHdr = find(isData, 1) - 1; if isempty(nHdr), nHdr = 0; end
end

function out = readExcelMatrix(fp, out)
%READEXCELMATRIX Matrix-template workbooks: sheet 1 = summary; fixed component sheets holding C3-origin matrices.
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"]; lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'readFile:ExcelMatrixFormat', 'Unsupported workbook: expected the fixed Etheta/Ephi and/or RHCP/LHCP component sheets after the summary sheet.');
required = string.empty; if hasC, required = [required, circ]; end, if hasL, required = [required, lin]; end
M = struct();
for name = required
    [theta, phi, data] = readExcelSheet(fp, sheets(find(strcmpi(sheets, name), 1)));
    if isfield(M, 'theta')
        assert(numel(theta) == numel(M.theta) && numel(phi) == numel(M.phi) && max(abs(theta - M.theta)) < 1e-9 && max(abs(phi - M.phi)) < 1e-9, ...
            'readFile:ExcelMatrixGrid', 'All component sheets must share one theta/phi grid.');
    else
        M.theta = theta; M.phi = phi;
    end
    M.(char(name)) = data;
end
if hasL
    Eth = fromMagPhase(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = fromMagPhase(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees);
    if hasC, desc = 'Format 3 (Ercp/Elcp + Eth/Eph)'; else, desc = 'Format 1 (Eth/Eph)'; end
else
    [Eth, Eph] = circularToLinear(fromMagPhase(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), fromMagPhase(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees)); desc = 'Format 2 (Ercp/Elcp)';
end
[phiG, thetaG] = meshgrid(M.phi, M.theta); block = fieldTable(thetaG, phiG, Eth, Eph); raw = block;
for name = required, raw.(char(name)) = reshape(M.(char(name)), [], 1); end
ud = out.userData; summary = readExcelSummary(fp, sheets(1));
for f = fieldnames(summary)', ud.(f{1}) = summary.(f{1}); end
ud.source = ['Excel Matrix ' desc]; ud.componentSheets = cellstr(required); ud.hasFrequency = isfinite(ud.frequencyMHz);
out.rawTbl = raw; out.blocks = {block}; out.userData = ud;
end

function [theta, phi, data] = readExcelSheet(fp, sheet)
% C3-origin matrix: row 2 = φ axis from column C, column B = θ axis from row 3. readcell keeps worksheet coordinates.
C = readcell(fp, 'Sheet', char(sheet)); assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'readFile:ExcelMatrixSheet', 'Sheet "%s" has no C3-origin matrix.', sheet);
isNum = @(cells) cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), cells);
pm = isNum(C(2, 3:end)); tm = isNum(C(3:end, 2));
nP = find(~pm, 1) - 1; if isempty(nP), nP = numel(pm); end
nT = find(~tm, 1) - 1; if isempty(nT), nT = numel(tm); end
assert(nP > 0 && nT > 0 && ~any(pm(nP + 1:end)) && ~any(tm(nT + 1:end)), 'readFile:ExcelMatrixAxis', 'Sheet "%s" has a missing or gapped theta/phi axis.', sheet);
phi = cell2mat(C(2, 3:2 + nP))'; theta = cell2mat(C(3:2 + nT, 2)); D = C(3:2 + nT, 3:2 + nP);
assert(all(isNum(D), 'all'), 'readFile:ExcelMatrixSheet', 'Sheet "%s" contains nonnumeric/missing matrix samples.', sheet);
data = cell2mat(D);
assert(all(diff(theta) > 0) && all(diff(phi) > 0) && theta(1) >= -1e-9 && theta(end) <= 180 + 1e-9 && phi(1) >= -1e-9 && phi(end) < 360 + 1e-9, ...
    'readFile:ExcelMatrixAxis', 'Sheet "%s" axes must be strictly increasing within θ 0..180 and φ 0..360.', sheet);
end

function ud = readExcelSummary(fp, sheet)
% Summary sheet (columns A:H): every "Label:" cell becomes a metadata field holding the first non-empty cell to its right.
ud = struct('frequencyMHz', NaN);
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
isBlank = @(x) isa(x, 'missing') || isempty(x) || (isnumeric(x) && all(isnan(x(:))));
for r = 1:size(C, 1)
    for c = 1:size(C, 2) - 1
        v = C{r, c}; if ~(ischar(v) || isstring(v)) || ~endsWith(strtrim(string(v)), ":"), continue; end
        rest = C(r, c + 1:end); rest = rest(~cellfun(isBlank, rest)); if isempty(rest), continue; end
        ud.(matlab.lang.makeValidName(lower(regexprep(strtrim(string(v)), '[^a-zA-Z0-9]+', '_')))) = rest{1};
    end
end
names = fieldnames(ud); k = find(contains(names, 'simulation_freq'), 1);
if ~isempty(k), v = ud.(names{k}); if isnumeric(v), ud.frequencyMHz = double(v(1)); else, ud.frequencyMHz = str2double(string(v)); end, end
end