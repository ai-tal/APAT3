classdef APAT_v3_M8_16 < matlab.apps.AppBase %1996-lines  %Edge POB DataTip positioning OK % Customized Interactive DataTip NOT-OK ON Contour Plot & Fisheye Plot (shows default X_Y_Z/Theta_R_Z) %Manual/Interactive DataTip labeling not working on 3D Surface Plot % When loading new pattern while POB is active/enabled, it doesn't sync/update to shows the new POB, it shows the old POB instead! % Coverage Threshold Query snaps to nearest Data Point instead of returning requested/query point! %Context menu shows error: "Warning: You cannot set 'ContextMenu' property of DataTip."
% APAT v3 M8 — Antenna Pattern Analyzer Tool. One canonical data flow:
%   file ─► readPattern ─► normalizePattern ─► [resampleCanonical] ─► calcPattern ─► viewBaseTbl
%   viewBaseTbl ─► applyAngularSpan ─► viewTbl (+ physTheta, solidAngle) ─┬► gridOf ─► full-pattern renderers
%                                                                          ├► cutData ─► polar / rectangular cuts
%                                                                          ├► calcOrientation / calcMetrics
%                                                                          └► Coverage tab (CCDF over solid angle)
% Design rules: numerical services are pure local functions on PHYSICAL polar coordinates; calcPattern runs once
% per view; annotations are tagged graphics toggled by tag; no toolbox dependencies (nearest-rank percentile).

    properties (GetAccess = public, SetAccess = private)
        isClosing logical = false
    end

    properties (Access = public) % ---------------------------------------------------------- UI handles
        UIFigure
        TabGroup
        Tab1_Single
        Tab2_Coverage
        % Main tab · inputs & parameters
        Single_EditField_Path
        Single_Button_Load
        Single_Button_Process
        Single_Button_Coverage
        Single_Button_ResetParams
        Single_Export_Output
        Single_Export_UAN
        Single_DropDown_step
        Single_DropDown_FFD
        Single_DropDown_TextFormat
        Single_DropDown_RxPol
        Single_Spinner_Rw
        Single_Spinner_Loss
        Single_Spinner_Pt
        Single_DropDown_Pt
        Single_Spinner_R
        Single_DropDown_R
        Single_StatusBar
        Single_Panel_fullPattern
        Full struct = struct([])
        % Main tab · cut panel
        Single_Panel_Rect
        Single_paxCut
        Single_AxesRect
        Range_Cut
        Range_Cut_Min
        Range_Cut_Max
        Button_HPBW
        Label_HPBW
        Single_gridEcut
        CheckBox_Et
        CheckBox_Er
        CheckBox_El
        % Main tab · data tabs
        Single_tabData
        Single_DropDown_output
        Single_Table_DataOut
        Single_Table_DataIn
        Single_Table_metadata
        % Main tab · plot control
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
        % Coverage tab
        Cov_gridPanel_Parm
        Cov_ButtonGroup_Btn_Conical
        Cov_DropDown_Orientation
        Cov_EditField_filePath
        Cov_Button_Load
        Cov_Button_computeCov
        Cov_Button_Reset
        Cov_Button_Export
        Cov_Button_Clear
        Cov_Button_toMain
        Cov_Spinner_ThreshMin
        Cov_Spinner_ThreshMax
        Cov_Spinner_Step
        Cov_Spinner_ConeTH
        Cov_Spinner_ConePH
        Cov_Spinner_ConeAng
        Cov_Spinner_queryCov
        Cov_Button_queryCov
        Cov_Spinner_queryThresh
        Cov_Button_queryThresh
        Cov_DropDown_Component
        Cov_DropDown_TextFormat
        Cov_StatusBar
        Cov_Panel_Results
        Cov_Axes
        Cov_Tree
        Cov_TreeNode_Results
        Cov_Tabel
        Cov_Spinner_XRange
        Cov_Spinner_XMin
        Cov_Spinner_XMax
        Groups struct = struct()   % control groups shown / enabled together (Rx, Tx, Distance, Loss, FFD, Format, CovFormat, File, Cone, Query, Component)
    end

    properties (Access = private) % ------------------------------------------------------- application state
        fileName char = ''
        filePath char = ''
        folderPath char = ''
        baseName char = ''
        rawTbl table                 % source data exactly as read
        stdTbl table                 % canonical E-field / gain table (theta 0..180, phi 0..360)
        viewBaseTbl table            % processed canonical table (one calcPattern per view)
        viewTbl table                % display convention applied (phi span, theta mode)
        uanTbl table                 % lazily built UAN export table
        physTheta double = []        % physical polar theta of every viewTbl row
        solidAngle double = []       % dOmega of every viewTbl row
        ffdBlocks cell = {}
        freqs double = NaN
        srcUD struct = struct()
        viewGrid struct = struct()   % view grid topology, geometry and per-component value grids
        POB double = NaN
        POBth double = NaN
        POBph double = NaN
        peakInfo struct = struct()
        polLabel char = 'n/a'
        polPairs struct = struct('Linear', ["E_TH","E_PH"], 'Circular', ["E_RCP","E_LCP"])
        boresightIndex double = 1
        antennaMetrics struct = struct()
        defaultParams struct = struct()
        gainLim double = [-55 25]    % authoritative non-AR colour scale
        ctrLim double = [-55 25]     % currently applied full-pattern range
        cutLim double = [-55 25]     % currently applied cut range
        keepOneDegree logical = false
        autoCutBasis logical = true
        outputMask logical = logical([])
        covRunID double = 0
        covPresetKey string = ""
        covXInit logical = false
        covSyncing logical = false
        statusTimer = []
        operationDialog = []
        perfTracker = @(~) []
        filterStyles = {}
    end

    properties (Constant, Access = private)
        PrincipalAxes = struct('labels', {{'+Z','-Z','+X','-X','+Y','-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        HiddenOutputColumns = {'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'}
        PeakPercentile = 99.99
        PeakMaxExcessDB = 6
        DistanceFloorM = 1e-12
        RangeLimits = [-250 100]
        OneDegreeItem = ['STEP: 1' char(176)]
        HPBWColor = '#D95319'
        FileFilter = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage files'; '*.*', 'All files'}
        ReleaseName = 'APAT v3 Milestone 8'
        ReleaseVersion = '3.0-M8'
    end

    %% ================================================================== source → view pipeline
    methods (Access = private)
        function out = readSource(app, fp, group)
            % Excel workbooks are self-describing; generic CSV/TXT/DAT expose the format selector.
            isText = isTextFile(fp);
            dropdown = group(end); if isText, fmt = "gain"; else, fmt = string(dropdown.Value); end
            out = readPattern(fp, fmt, table());
            showSelector = isText && ~out.userData.isCoverage;
            if showSelector, dropdown.Value = 'gain'; end
            set(group, 'Visible', showSelector);
            app.checkCancelled();
        end

        function activateSource(app, out)
            [app.rawTbl, app.ffdBlocks, app.freqs, app.srcUD] = deal(out.rawTbl, out.blocks, out.freqs, out.userData);
            app.selectBlock(1);
        end

        function selectBlock(app, k)
            block = app.ffdBlocks{k};
            if app.srcUD.isDep, app.rawTbl = block; end
            app.stdTbl = normalizePattern(block);
            app.stdTbl.Properties.UserData = app.srcUD;
            set(app.Single_Table_DataIn, 'Data', app.rawTbl, 'ColumnName', app.rawTbl.Properties.VariableNames, 'Visible', 'on');
        end

        function param = getParam(app)
            param = struct('GainLoss_dB', app.Single_Spinner_Loss.Value, 'RxMode', string(app.Single_DropDown_RxPol.Value), 'RxAR_dB', app.Single_Spinner_Rw.Value);
            param.FieldScale = 10^(param.GainLoss_dB/20);
            p = app.Single_Spinner_Pt.Value; unit = app.Single_DropDown_Pt.Value;
            if strcmp(unit, 'Watts'), param.Pt_dBW = 10*log10(max(p, eps)); else, param.Pt_dBW = p - 30*strcmp(unit, 'dBm'); end
            param.R_m = max(app.Single_Spinner_R.Value, app.DistanceFloorM) * (1 + 999*strcmp(app.Single_DropDown_R.Value, 'km'));
        end

        function refresh(app)
            % Full rebuild after load / reprocess / block change: source → processed view → tables → plots.
            std = app.stdTbl;
            thetaStep = gridStep(std.Theta); phiStep = gridStep(mod(std.Phi, 360));
            if ~isfinite(thetaStep), thetaStep = 1; end
            if ~isfinite(phiStep), phiStep = thetaStep; end
            nonCanonical = abs(thetaStep - 1) > 1e-9 || abs(phiStep - 1) > 1e-9;
            native = sprintf('STEP: %g%c', max(thetaStep, phiStep), char(176));
            dd = app.Single_DropDown_step;
            dd.Items = {native, app.OneDegreeItem}; dd.Value = native;
            if app.keepOneDegree && nonCanonical, dd.Value = app.OneDegreeItem; end
            set(dd, 'Visible', nonCanonical, 'Enable', nonCanonical); app.keepOneDegree = false;

            app.processView();
            app.perfTracker("Process pattern"); app.checkCancelled();
            app.updateComponentItems();
            app.updateView(true, false, false);
            app.perfTracker("Tables and ranges"); app.checkCancelled();
            app.onPlaneChanged();                       % fast default E/H cut before the heavy full-pattern pass
            drawnow limitrate
            app.renderFull();
            app.perfTracker("Build plots");

            hasE = ~app.srcUD.isGainOnly;
            set([app.Single_Panel_Rect, app.Single_Export_Output, app.Single_Panel_fullPattern, app.Single_Panel_plotControl, app.Single_Button_Coverage], 'Visible', 'on');
            set([app.Single_Export_UAN, app.Single_gridEcut, app.CheckBox_Et, app.CheckBox_Er, app.CheckBox_El], 'Visible', hasE);
            set([app.CheckBox_Er, app.CheckBox_El, app.CutFieldBasisDropDown], 'Enable', hasE);
            app.updateInputVisibility();
            pol = ''; if hasE && ~strcmpi(strtrim(app.polLabel), 'n/a'), pol = sprintf(' | Polarization <b>%s</b>', app.polLabel); end
            app.setStatus(app.Single_StatusBar, sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)%s', ...
                app.fileName, fmtNumber(app.POB, 2), fmtNumber(app.POBth), fmtNumber(app.POBph), pol), false);
        end

        function processView(app)
            % Optionally resample the CANONICAL source (never the nonlinear outputs), then derive everything once.
            src = app.stdTbl;
            if strcmp(app.Single_DropDown_step.Value, app.OneDegreeItem)
                ts = gridStep(src.Theta); ps = gridStep(mod(src.Phi, 360));
                if all(isfinite([ts ps])) && ts < 1 && ps < 1       % finer than 1°: keep the integer-degree samples
                    src = src(abs(src.Theta - round(src.Theta)) < 1e-9 & abs(src.Phi - round(src.Phi)) < 1e-9, :);
                else
                    src = resampleCanonical(src, 1);
                end
                src.Properties.UserData = app.stdTbl.Properties.UserData;
            end
            [app.viewBaseTbl, info] = calcPattern(src, app.getParam());
            [app.polLabel, app.polPairs] = deal(info.pol, info.pairs);
            if app.autoCutBasis && ~app.srcUD.isGainOnly
                if startsWith(info.pol, 'Linear'), app.CutFieldBasisDropDown.Value = 'Linear'; else, app.CutFieldBasisDropDown.Value = 'Circular'; end
            end
            app.applyAngularSpan();
        end

        function applyAngularSpan(app)
            % Materialize the display convention from the canonical table; keep physical theta alongside.
            T = app.viewBaseTbl; [signedPhi, elevation] = app.viewModes();
            if signedPhi
                T(abs(T.Phi - 360) <= 1e-9, :) = [];
                T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
                seam = T(abs(T.Phi - 180) < 1e-9, :); seam.Phi(:) = -180; T = [seam; T];
            end
            theta = T.Theta;
            if elevation, T.Theta = 90 - theta; end
            if signedPhi || elevation, [T, order] = sortrows(T, {'Phi', 'Theta'}); theta = theta(order); end
            T.Properties.UserData = app.srcUD;
            app.viewTbl = T; app.physTheta = theta; app.solidAngle = solidWeights(theta, T.Phi);
            app.uanTbl = table(); app.viewGrid = struct(); app.antennaMetrics = struct();
        end

        function [signedPhi, elevation] = viewModes(app)
            signedPhi = strcmp(app.Single_Switch_AngularSpan.Value, '-180° to 180°');
            elevation = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°');
        end

        function updateView(app, refreshRanges, renderFull, updateCut)
            % Recompute peak, boresight and metrics for the current view, then refresh tables / plots as requested.
            T = app.viewTbl; if isempty(T), return; end
            gain = T.(chooseColumn(T, app.comp()));
            [peak, app.boresightIndex] = calcOrientation(app.physTheta, T.Phi, gain, app.solidAngle, app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
            app.peakInfo = peak; app.POB = peak.value;
            app.POBth = app.physTheta(peak.index); app.POBph = mod(T.Phi(peak.index), 360);
            ax = app.PrincipalAxes; [~, elevation] = app.viewModes();
            app.antennaMetrics = calcMetrics(T, app.physTheta, app.solidAngle, ax.theta(app.boresightIndex), ax.phi(app.boresightIndex), elevation, app.PeakPercentile, app.PeakMaxExcessDB);
            app.initRanges(refreshRanges);
            app.updateTables(); app.updateMetadata();
            if updateCut, app.updateCutControl(); app.plotCut(); end
            if renderFull, app.renderFull(); end
        end

        function initRanges(app, recompute)
            % Total Gain owns the non-AR colour scale (recomputed only when the view data changes); AR is fixed ±30 dB.
            T = app.viewTbl;
            if recompute && ismember('E_Total_dB', T.Properties.VariableNames), app.gainLim = peakWindow(T.E_Total_dB, app.PeakPercentile, app.PeakMaxExcessDB); end
            if isAR(app.comp()), requested = [-30 30]; else, requested = app.gainLim; end
            app.setRange("all", requested, 0, false);
        end
        %% ---------------------------------------------------------------- component / table helpers
        function [cols, labels] = componentMap(~, T)
            available = string(T.Properties.VariableNames(3:end)); ud = T.Properties.UserData;
            if isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly, [cols, labels] = deal(available); return; end
            cols = ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","AR_dB","Gain_PolCorrected_dB"];
            labels = ["Total Gain","Etheta Gain","Ephi Gain","RHCP Gain","LHCP Gain","Axial Ratio","Polarized Gain"];
            keep = ismember(cols, available); cols = cols(keep); labels = labels(keep);
        end

        function setComponentItems(app, dd, T, preferred)
            [cols, labels] = app.componentMap(T); if isempty(cols), return; end
            if ~isequal(string(dd.ItemsData), cols), dd.Items = cellstr(labels); dd.ItemsData = cellstr(cols); end
            if any(cols == string(preferred)), dd.Value = char(preferred);
            elseif any(cols == "E_Total_dB"), dd.Value = 'E_Total_dB';
            else, dd.Value = char(cols(1)); end
        end
        function updateComponentItems(app)
            app.setComponentItems(app.Single_DropDown_Component, app.viewTbl, app.Single_DropDown_Component.Value);
        end
        function c = comp(app), c = app.Single_DropDown_Component.Value; end

        function s = compLabel(app)
            dd = app.Single_DropDown_Component; k = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(k), s = strrep(string(dd.Value), '_', ' '); else, s = string(dd.Items{k}); end
        end

        function updateTables(app)
            dd = app.Single_DropDown_output; cols = app.viewTbl.Properties.VariableNames(3:end);
            schemaChanged = ~isequal(regexprep(dd.Items(2:end), '^✓ ?', ''), cols);
            if schemaChanged
                dd.Items = [{'--- column filter ---'}, cols]; dd.ItemsData = 0:numel(cols); dd.Value = 0;
                app.outputMask = ~ismember(cols, app.HiddenOutputColumns);
                set([dd, app.Single_Table_DataOut, app.Single_tabData], 'Visible', 'on');
            end
            app.filterOutput([], schemaChanged);
        end

        function filterOutput(app, event, restyle)
            % Dropdown toggles one output column; ✓ items are the visible columns of the Results table.
            if nargin < 3, restyle = true; end
            dd = app.Single_DropDown_output;
            if ~isempty(event) && dd.Value > 0, app.outputMask(dd.Value) = ~app.outputMask(dd.Value); dd.Value = 0; end
            if restyle
                if isempty(app.filterStyles)
                    app.filterStyles = {uistyle('FontWeight', 'bold', 'FontColor', 'black', 'BackgroundColor', [0.8 1 0.8]), uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9])};
                end
                dd.Items = regexprep(dd.Items, '^✓ ?', ''); removeStyle(dd);
                on = find(app.outputMask) + 1; off = find([true, ~app.outputMask]);
                dd.Items(on) = append('✓ ', dd.Items(on));
                if ~isempty(on), addStyle(dd, app.filterStyles{1}, 'Item', on); end
                if ~isempty(off), addStyle(dd, app.filterStyles{2}, 'Item', off); end
            end
            app.Single_Table_DataOut.Data = app.viewTbl(:, [true true app.outputMask]);
            app.updateInputVisibility();
        end

        function updateInputVisibility(app)
            % Only parameters that influence a visible output column are shown.
            sel = string(app.viewTbl.Properties.VariableNames(3:end)); sel = sel(app.outputMask);
            set(app.Groups.Rx, 'Visible', any(ismember(sel, ["PLF_dB","Gain_PolCorrected_dB"])));
            set(app.Groups.Tx, 'Visible', any(ismember(sel, ["EIRP_dBW","PFD_Wm2","E_RMS_Vm"])));
            set(app.Groups.Distance, 'Visible', any(ismember(sel, ["PFD_Wm2","E_RMS_Vm"])));
            set(app.Groups.Loss, 'Visible', app.srcUD.isGainOnly || any(ismember(sel, ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","Gain_PolCorrected_dB","EIRP_dBW","PFD_Wm2","E_RMS_Vm"])));
        end

        function updateMetadata(app)
            T = app.viewTbl; m = app.antennaMetrics; th = unique(T.Theta); ph = unique(T.Phi);
            rows = {'Source format', app.srcUD.source; 'File', app.fileName; ...
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(T), numel(th), numel(ph)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmtNumber(min(th)), fmtNumber(max(th)), fmtNumber(gridStep(th))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmtNumber(min(ph)), fmtNumber(max(ph)), fmtNumber(gridStep(ph)))};
            f = app.freqs(isfinite(app.freqs));
            if ~isempty(f), rows(end+1, :) = {'Frequencies', strjoin(compose('%.4g GHz', f(:)/1e9), ', ')}; end
            if ~app.srcUD.isGainOnly
                if ~strcmpi(strtrim(app.polLabel), 'n/a'), rows(end+1, :) = {'Polarization', app.polLabel}; end
                rows(end+1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(app.polPairs.(app.CutFieldBasisDropDown.Value), ' / '))};
            end
            rows = [rows; {'Peak gain (POB)', sprintf('%s dB', fmtNumber(app.POB)); 'POB direction [θ, φ]', sprintf('[%s°, %s°]', fmtNumber(app.POBth), fmtNumber(app.POBph)); ...
                'Boresight axis', app.PrincipalAxes.labels{app.boresightIndex}; ...
                'Peak policy', sprintf('P%.4g, max excess %.4g dB', app.PeakPercentile, app.PeakMaxExcessDB); 'Peak adjusted', char(string(app.peakInfo.wasAdjusted))}];
            if isfield(m, 'PeakGain_dB')
                rows = [rows; {'HPBW E-plane', sprintf('%s°', fmtNumber(m.HPBW_EPlane_deg)); 'HPBW H-plane', sprintf('%s°', fmtNumber(m.HPBW_HPlane_deg)); ...
                    'Front-to-back', sprintf('%s dB', fmtNumber(m.FrontBack_dB)); 'Peak directivity', sprintf('%s dB', fmtNumber(m.PeakDirectivity_dB))}];
                if isfinite(m.Efficiency_pct), rows(end+1, :) = {'Radiation efficiency', sprintf('%s%%', fmtNumber(m.Efficiency_pct))}; end
                if isfinite(m.AxialRatioAtPeak_dB), rows(end+1, :) = {'AR at peak', sprintf('%s dB', fmtNumber(m.AxialRatioAtPeak_dB))}; end
            end
            app.Single_Table_metadata.Data = rows;
        end
        %% ---------------------------------------------------------------- range synchronisation
        function setRange(app, scope, value, mode, apply)
            % One synchroniser for all range sliders / spinners. scope: "all" | "full" | "cut"; mode: 0 = pair, 1 = min, 2 = max.
            lim = app.RangeLimits;
            if scope == "all"
                r = clampRange(value, lim);
                [app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value] = deal(r(1), r(2));
                app.setRange("full", r, 0, apply); app.setRange("cut", r, 0, apply); return
            end
            if scope == "full", sliders = [app.Full.slider]; lo = [app.Full.minSpinner]; hi = [app.Full.maxSpinner]; r = app.ctrLim;
            else, sliders = app.Range_Cut; lo = app.Range_Cut_Min; hi = app.Range_Cut_Max; r = app.cutLim; end
            if mode == 0, r = value; else, r(mode) = value; end
            r = clampRange(r, lim); bounds = r;
            if mode ~= 0, old = sliders(1).Limits; bounds = [min(old(1), r(1)), max(old(2), r(2))]; end
            set(sliders, 'Limits', lim, 'Value', r); set(sliders, 'Limits', bounds);      % widen first so Value is never clamped
            set(lo, 'Limits', [lim(1), r(2) - 1], 'Value', r(1)); set(hi, 'Limits', [r(1) + 1, lim(2)], 'Value', r(2));
            if scope == "full", app.ctrLim = r; if ~isAR(app.comp()), app.gainLim = r; end, else, app.cutLim = r; end
            if apply && ~isempty(app.viewTbl)
                if scope == "full", app.applyFullRange(r); else, set(app.Single_paxCut, 'RLim', r); set(app.Single_AxesRect, 'YLim', r); end
                drawnow limitrate
            end
        end

        function applyFullRange(app, r)
            for s = app.Full
                clim(s.axes, r); if s.name == "rect3D", zlim(s.axes, r); end
                cb = findall(ancestor(s.axes, 'figure'), 'Type', 'ColorBar', 'Axes', s.axes);
                if ~isempty(cb), app.colorbarTicks(cb(1), r); end
            end
        end
        function colorbarTicks(app, cb, r)
            t = axisTicks(r, app.Single_Plot_Cstep.Value); if ~isempty(t), cb.Ticks = t; end
        end

        function [limits, map] = colorTheme(app)
            % Signed AR uses a fixed blue-white-red ±30 dB map; everything else uses jet over the gain scale.
            persistent jetMap arMap
            if isempty(jetMap), jetMap = jet(256); arMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
            if isAR(app.comp()), limits = [-30 30]; map = arMap; else, limits = app.gainLim; map = jetMap; end
        end
        function applyTheme(app, ax, limits, map)
            clim(ax, limits); colormap(ax, map); app.colorbarTicks(colorbar(ax), limits);
        end
    end

    %% ================================================================== rendering
    methods (Access = private)
        function g = gridOf(app, col)
            % Cached view-grid topology + geometry; value grids are added per component on demand.
            g = app.viewGrid;
            if ~isfield(g, 'theta')
                T = app.viewTbl; [~, elevation] = app.viewModes();
                g = struct('theta', unique(T.Theta), 'phi', unique(T.Phi), 'values', struct());
                [~, it] = ismember(T.Theta, g.theta); [~, ip] = ismember(T.Phi, g.phi);
                g.sz = [numel(g.theta), numel(g.phi)]; g.index = sub2ind(g.sz, it, ip);
                [g.phiGrid, g.thetaGrid] = meshgrid(g.phi, g.theta);
                polar = g.thetaGrid; if elevation, polar = 90 - polar; end
                g.thetaPolar = polar; g.phiRad = deg2rad(g.phiGrid);
                g.x = sind(polar).*cos(g.phiRad); g.y = sind(polar).*sin(g.phiRad); g.z = cosd(polar);
            end
            key = matlab.lang.makeValidName(col);
            if ~isfield(g.values, key), v = nan(g.sz); v(g.index) = app.viewTbl.(col); g.values.(key) = v; end
            g.data = g.values.(key); app.viewGrid = g;
        end

        function renderFull(app)
            if isempty(app.viewTbl), return; end
            for s = app.Full
                if app.isClosing, return; end
                app.checkCancelled();
                switch s.name
                    case "contour",  app.drawContour(s);
                    case "circular", app.drawFisheye(s);
                    otherwise,       app.draw3D(s);
                end
                app.finishAxes(s.axes);
            end
            drawnow limitrate                          % surfaces must exist before DataTips are pinned
            app.annotatePOB({app.Full.axes});
        end

        function drawContour(app, s)
            g = app.gridOf(app.comp()); ax = s.axes; cla(ax);
            h = pcolor(ax, g.phi, g.theta, g.data, 'FaceColor', 'interp', 'LineStyle', 'none', 'Tag', 'APAT_PatternSurface');
            [lim, map] = app.colorTheme(); app.applyTheme(ax, lim, map);
            app.formatAngularAxes(ax, 30, 15); daspect(ax, [1 1 1]);
            title(ax, app.compLabel(), 'Interpreter', 'none'); app.tipTemplate(h, g);
            [r, c] = app.pobIndex(g); app.recordPOB(ax, [g.phi(c), g.theta(r), 0], g, r, c);
        end

        function drawFisheye(app, s)
            g = app.gridOf(app.comp()); pax = s.axes; cla(pax);
            h = surface(pax, g.phiRad, g.thetaPolar, zeros(g.sz), g.data, 'EdgeColor', 'none', 'Tag', 'APAT_PatternSurface');
            [lim, map] = app.colorTheme(); app.applyTheme(pax, lim, map);
            set(pax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'RLim', [0 180], 'RTick', 0:30:180);
            app.setPolarTicks(pax); [~, elevation] = app.viewModes();
            rl = 0:30:180; if elevation, rl = 90 - rl; end
            pax.RTickLabel = compose('%d°', rl);
            title(pax, sprintf('%s  |  r=θ, angle=φ', app.compLabel()), 'Interpreter', 'none', 'FontSize', 9); app.tipTemplate(h, g);
            [r, c] = app.pobIndex(g); app.recordPOB(pax, [g.phiRad(r, c), g.thetaPolar(r, c), 0], g, r, c);
        end

        function draw3D(app, s)
            % sphere3D: unit sphere coloured by value; polar3D: radius ∝ value above the range floor; rect3D: surf(phi, theta, value).
            g = app.gridOf(app.comp()); ax = s.axes; [lim, map] = app.colorTheme(); cla(ax); hold(ax, 'on');
            if s.name == "rect3D"
                xyz = {g.phiGrid, g.thetaGrid, g.data};
                h = surf(ax, xyz{:}, 'EdgeColor', 'none', 'Tag', 'APAT_PatternSurface');
                zlim(ax, lim); zt = axisTicks(lim, app.Single_Plot_Cstep.Value); if ~isempty(zt), ax.ZTick = zt; end
                app.formatAngularAxes(ax, 60, 30); grid(ax, 'on'); [~, elevation] = app.viewModes();
                yl = 'Theta (degree)'; if elevation, yl = 'Elevation (degree)'; end
                xlabel(ax, 'Phi (degree)'); ylabel(ax, yl); zlabel(ax, app.compLabel() + " (dB)", 'Interpreter', 'none');
                title(ax, app.compLabel(), 'Interpreter', 'none');
            else
                rad = ones(g.sz);
                if s.name == "polar3D", rad = max(g.data - lim(1), 0) / max(diff(lim), eps); rad = rad / max(max(rad, [], 'all', 'omitnan'), eps); end
                xyz = {rad.*g.x, rad.*g.y, rad.*g.z};
                h = surf(ax, xyz{:}, g.data, 'EdgeColor', 'none', 'Tag', 'APAT_PatternSurface');
                set(ax, 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1], 'Projection', 'orthographic');
                axis(ax, 'off'); app.drawXYZ(ax);
                if app.Single_CheckBox_overlayCut.Value, app.overlayCut(ax, s.name, lim); end
                title(ax, sprintf('%s  |  θ: %s  |  φ: %s', app.compLabel(), app.Single_Switch_ThetaSpan.Value, app.Single_Switch_AngularSpan.Value), 'Interpreter', 'none');
            end
            app.applyTheme(ax, lim, map); app.apply3DView(ax, s.view); app.tipTemplate(h, g);
            [r, c] = app.pobIndex(g); app.recordPOB(ax, cellfun(@(m) m(r, c), xyz), g, r, c);
            hold(ax, 'off');
        end

        function drawXYZ(~, ax)
            % Principal axes (X red, Y green, Z blue) with their spherical coordinates.
            colors = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            for k = 1:3
                d = 1.35 * double((1:3) == k);
                quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12*d(1), 1.12*d(2), 1.12*d(3), labels{k}, 'Color', colors{k}, 'FontWeight', 'bold');
            end
        end

        function apply3DView(app, ax, defaultView)
            % [azimuth elevation | camera-up] per named point of view; "iso" uses the plot's own default.
            pov = struct('iso', [defaultView, 0 0 1], 'top', [0 90, 0 1 0], 'bottom', [0 -90, 0 1 0], 'right', [90 0, 0 0 1], 'left', [-90 0, 0 0 1], 'front', [0 0, 0 0 1], 'back', [180 0, 0 0 1]);
            v = pov.(app.Single_DropDown_3DView.Value); view(ax, v(1:2)); camup(ax, v(3:5));
        end

        function on3DViewChanged(app)
            for s = app.Full(~cellfun(@isempty, {app.Full.view})), app.apply3DView(s.axes, s.view); end
            drawnow limitrate
        end

        function overlayCut(app, ax, kind, lim)
            % Draw the active cut as a black line on the sphere / polar surface using the surface's own radius law.
            c = app.cutData(); v = c.values(:, 1);
            if kind == "sphere3D"
                r = 1.02;
            else
                g = app.gridOf(app.comp()); scale = max(max(g.data - lim(1), 0) / max(diff(lim), eps), [], 'all', 'omitnan');
                r = max(v - lim(1), 0) / max(diff(lim), eps) / max(scale, eps) * 1.01;
            end
            plot3(ax, r.*sind(c.theta).*cosd(c.phi), r.*sind(c.theta).*sind(c.phi), r.*cosd(c.theta), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay');
        end

        function overlayCuts(app)
            % Checkbox / cut change: refresh only the overlay lines on the two spatial 3-D plots.
            if isempty(app.viewTbl), return; end
            for s = app.Full(ismember([app.Full.name], ["sphere3D", "polar3D"]))
                delete(findall(s.axes, 'Tag', 'APAT_CutOverlay'));
                if ~app.Single_CheckBox_overlayCut.Value, continue; end
                lim = app.colorTheme(); held = ishold(s.axes); hold(s.axes, 'on');
                app.overlayCut(s.axes, s.name, lim); if ~held, hold(s.axes, 'off'); end
            end
        end

        function [xl, yl, ydir] = angularLimits(app)
            [signedPhi, elevation] = app.viewModes(); xl = [0 360] - 180*signedPhi;
            if elevation, yl = [-90 90]; ydir = 'normal'; else, yl = [0 180]; ydir = 'reverse'; end
        end

        function formatAngularAxes(app, ax, phiStep, thetaStep)
            [xl, yl, ydir] = app.angularLimits();
            set(ax, 'XLim', xl, 'YLim', yl, 'YDir', ydir, 'Box', 'on', 'Layer', 'top', 'XTick', xl(1):phiStep:xl(2), 'YTick', yl(1):thetaStep:yl(2));
        end

        function setPolarTicks(app, pax)
            a = 0:30:330; if app.viewModes(), a(a > 180) = a(a > 180) - 360; end
            pax.ThetaTick = 0:30:330; pax.ThetaTickLabel = compose('%d°', a);
        end

        function tipTemplate(app, h, g)
            [~, elevation] = app.viewModes(); lbl = "Theta"; if elevation, lbl = "Elevation"; end
            rows = [dataTipTextRow(lbl, g.thetaGrid, '%.3g°'); dataTipTextRow("Phi", g.phiGrid, '%.3g°'); dataTipTextRow(replace(app.compLabel(), "_", "\_"), g.data, '%.3g dB')];
            try, h.DataTipTemplate.DataTipRows = rows; catch, end
        end

        function initAxes(app, ax, is3D)
            % Interaction set + one context menu per axes (created once; propagated to children after every render).
            enableDefaultInteractivity(ax);
            if ~isa(ax, 'matlab.graphics.axis.PolarAxes')
                if is3D, ax.Interactions = [rotateInteraction, dataTipInteraction]; else, ax.Interactions = [zoomInteraction, dataTipInteraction]; end
            end
            menu = uicontextmenu(app.UIFigure, 'Tag', 'APAT_PlotContextMenu');
            uimenu(menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ~) delete(findall(ax, 'Type', 'datatip')));
            ax.ContextMenu = menu;
        end
        function finishAxes(~, ax)
            set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', ax.ContextMenu);
        end
        %% ---------------------------------------------------------------- annotations (POB / HPBW)
        function [r, c] = pobIndex(app, g)
            [signedPhi, elevation] = app.viewModes();
            th = app.POBth; if elevation, th = 90 - th; end
            ph = app.POBph; if signedPhi && ph > 180, ph = ph - 360; end
            [~, r] = min(abs(g.theta - th)); [~, c] = min(abs(g.phi - ph));
        end

        function recordPOB(app, ax, p, g, r, c)
            % Every renderer stores where its POB lives; annotatePOB materialises the marker when requested.
            if ~isfinite(app.POBth), ax.UserData = []; return; end
            [~, elevation] = app.viewModes(); lbl = "Theta"; if elevation, lbl = "Elevation"; end
            rows = [dataTipTextRow(lbl, g.theta(r), '%.3g°'); dataTipTextRow("Phi", g.phi(c), '%.3g°'); dataTipTextRow(app.compLabel(), g.data(r, c), '%.3g dB')];
            ax.UserData = struct('pob', p, 'rows', rows);
        end

        function annotatePOB(app, axesList)
            % Create missing POB markers (when the checkbox is on) or toggle existing ones by tag.
            show = app.Single_CheckBox_POB.Value;
            if nargin < 2, axesList = [{app.Full.axes}, {app.Single_paxCut, app.Single_AxesRect}]; end
            for k = 1:numel(axesList)
                ax = axesList{k};
                if ~isgraphics(ax) || ~isstruct(ax.UserData) || ~isfield(ax.UserData, 'pob'), continue; end
                existing = findall(ax, 'Tag', 'APAT_POB');
                if isempty(existing)
                    if show, app.markPoint(ax, ax.UserData.pob, ax.UserData.rows, 'APAT_POB', 'k', true); end
                else
                    set(existing, 'Visible', show);
                end
            end
        end

        function markPoint(~, ax, p, rows, tag, color, visible)
            % One marker plus one pinned DataTip; both carry TAG so visibility can be toggled collectively.
            isPolar = isa(ax, 'matlab.graphics.axis.PolarAxes'); held = ishold(ax); hold(ax, 'on');
            try
                if isPolar, h = polarplot(ax, p(1), p(2), 'o'); else, h = plot3(ax, p(1), p(2), p(3), 'o', 'Clipping', 'off'); end
                set(h, 'MarkerSize', 5, 'MarkerFaceColor', color, 'MarkerEdgeColor', color, 'HandleVisibility', 'off', 'Tag', tag, 'Visible', visible);
                if ~isempty(rows), h.DataTipTemplate.DataTipRows = rows; end
                tip = datatip(h, 'DataIndex', 1, 'FontSize', 9, 'Tag', tag, 'Visible', visible, 'HandleVisibility', 'off');
                if ~isPolar && strcmp(ax.YDir, 'reverse') && abs(p(2) - ax.YLim(1)) <= diff(ax.YLim)/1000   % contour: tip near theta=0 opens downwards
                    if p(1) <= mean(ax.XLim), tip.Location = 'southeast'; else, tip.Location = 'southwest'; end
                end
            catch ME
                warning('APAT:Annotation', 'Could not create annotation: %s', ME.message);
            end
            if ~held, hold(ax, 'off'); end
        end
        %% ---------------------------------------------------------------- cuts
        function values = updateCutControl(app)
            % The cut value is a fixed display-theta for Phi cuts and a fixed phi for Theta cuts.
            if strcmp(app.Single_DropDown_cutType.Value, 'Phi'), values = unique(app.viewTbl.Theta); else, values = unique(mod(app.viewTbl.Phi, 360)); end
            sp = app.Single_DropDown_cutValue; sp.Limits = [min(values), max(values)];
            if numel(values) > 1, sp.Step = min(diff(values)); end
            [~, k] = min(abs(values - sp.Value)); sp.Value = values(k);
        end

        function onPlaneChanged(app, ~)
            % E-plane: Theta cut through the boresight-axis phi. H-plane: the orthogonal principal plane.
            ax = app.PrincipalAxes; k = app.boresightIndex; [~, elevation] = app.viewModes();
            if startsWith(app.Single_Switch_EHplane.Value, 'E'), type = 'Theta'; value = ax.phi(k);
            elseif ax.theta(k) == 90, type = 'Phi'; value = 90 * ~elevation;
            else, type = 'Theta'; value = 90; end
            app.Single_DropDown_cutType.Value = type;
            values = app.updateCutControl(); [~, n] = min(abs(values - value)); app.Single_DropDown_cutValue.Value = values(n);
            app.onCutChanged();
        end

        function onCutChanged(app, event)
            if nargin > 1 && ~isempty(event)
                if event.Source == app.Single_DropDown_cutType, app.updateCutControl();
                elseif event.Source == app.CutFieldBasisDropDown, app.autoCutBasis = false; app.updateMetadata(); end
            end
            show = app.Button_HPBW.Value; app.Single_CheckBox_HPBWBounds.Visible = show;
            if ~show, app.Single_CheckBox_HPBWBounds.Value = false; end
            app.plotCut();
            if app.Single_CheckBox_overlayCut.Value, app.overlayCuts(); end
        end

        function [cols, idx] = cutCols(app)
            % Selected component (gain-only) or Total plus the circular / linear field pair; idx keeps colours stable.
            if app.srcUD.isGainOnly, cols = string(app.comp()); idx = 1; return; end
            if strcmp(app.CutFieldBasisDropDown.Value, 'Linear'), all3 = ["E_Total_dB","E_TH_dB","E_PH_dB"]; else, all3 = ["E_Total_dB","E_RCP_dB","E_LCP_dB"]; end
            pair = extractBefore(all3(2:3), "_dB");
            if ~strcmp(app.CheckBox_Er.Text, pair(1)), [app.CheckBox_Er.Text, app.CheckBox_El.Text] = deal(char(pair(1)), char(pair(2))); end
            idx = find([app.CheckBox_Et.Value, app.CheckBox_Er.Value, app.CheckBox_El.Value]); if isempty(idx), idx = 1; end
            cols = all3(idx);
        end

        function c = cutData(app)
            % Extract the active cut as one closed circle (angle, values, physical geometry, labels).
            T = app.viewTbl; [cols, idx] = app.cutCols();
            type = string(app.Single_DropDown_cutType.Value); requested = app.Single_DropDown_cutValue.Value;
            [angle, rows, fixed, symbol, snapped] = cutGeometry(T.Theta, app.physTheta, T.Phi, type, requested);
            if snapped, app.setStatus(app.Single_StatusBar, sprintf('Requested %s cut @ %s=%g° (snapped to nearest %s=%g°)', type, symbol, requested, symbol, fixed), false); end
            values = T{rows, cellstr(cols)}; theta = app.physTheta(rows); phi = T.Phi(rows); signedPhi = app.viewModes();
            if signedPhi, angle(angle > 180) = angle(angle > 180) - 360; end
            [angle, order] = unique(angle, 'sorted'); values = values(order, :); theta = theta(order); phi = phi(order);
            if type == "Phi"                                     % close the circle at the seam exactly once
                seam = [0 360] - 180*signedPhi; openLow = abs(angle(1) - seam(1)) > 1e-9; openHigh = abs(angle(end) - seam(2)) > 1e-9;
                if openLow && openHigh
                    w = (seam(2) - angle(end)) / (angle(1) - seam(1) + seam(2) - angle(end));
                    sv = (1 - w)*values(end, :) + w*values(1, :); st = (1 - w)*theta(end) + w*theta(1);
                    angle = [seam(1); angle; seam(2)]; values = [sv; values; sv]; theta = [st; theta; st]; phi = [seam(1); phi; seam(2)];
                elseif openLow
                    angle = [seam(1); angle]; values = [values(end, :); values]; theta = [theta(end); theta]; phi = [phi(end); phi];
                elseif openHigh
                    angle = [angle; seam(2)]; values = [values; values(1, :)]; theta = [theta; theta(1)]; phi = [phi; phi(1)];
                end
            end
            if app.srcUD.isGainOnly, ttl = char(app.compLabel()); else, ttl = sprintf('%s cut @ %s = %g°', type, symbol, fixed); end
            c = struct('angle', angle, 'values', values, 'cols', cols, 'names', replace(cols, "_", "\_"), 'idx', idx, 'title', ttl, 'theta', theta, 'phi', phi, 'type', type);
        end

        function plotCut(app)
            if isempty(app.viewTbl), return; end
            c = app.cutData(); pax = app.Single_paxCut; rax = app.Single_AxesRect;
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on'); pax.UserData = []; rax.UserData = [];
            lim = clampRange(app.Range_Cut.Value, app.RangeLimits);
            pl = polarplot(pax, deg2rad(c.angle), max(c.values, lim(1)), 'LineWidth', 1.4);   % clamp: no reflection spikes inside RLim
            rl = plot(rax, c.angle, c.values, 'LineWidth', 1.4);
            palette = rax.ColorOrder; colors = num2cell(palette(1 + mod(c.idx - 1, size(palette, 1)), :), 2);
            set(pl(:), {'Color'}, colors); set(rl(:), {'Color'}, colors);
            for k = 1:numel(pl)
                rows = [dataTipTextRow("Angle", c.angle, '%.3g°'), dataTipTextRow("Magnitude", c.values(:, k), '%.3g dB')];
                pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            set(pax, 'ThetaDir', 'clockwise', 'ThetaZeroLocation', 'top', 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.setPolarTicks(pax);
            xl = app.angularLimits();
            set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, c.type + " (degree)"); title(pax, c.title, 'Interpreter', 'none'); title(rax, c.title, 'Interpreter', 'none');
            legend(pax, pl, c.names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rl, c.names, 'Location', 'best');

            % The peak of the first plotted component is the cut POB and the HPBW reference.
            [pk, ki] = max(c.values(:, 1), [], 'omitnan'); app.Label_HPBW.Text = '';
            if isfinite(pk)
                rows = [dataTipTextRow("Angle", c.angle(ki), '%.3g°'); dataTipTextRow("Magnitude", pk, '%.3g dB')];
                pax.UserData = struct('pob', [deg2rad(c.angle(ki)), max(pk, lim(1)), 0], 'rows', rows);
                rax.UserData = struct('pob', [c.angle(ki), pk, 0], 'rows', rows);
                if app.Button_HPBW.Value, app.drawHPBW(c, pk, ki, xl); end
            end
            hold(pax, 'off'); hold(rax, 'off');
            app.annotatePOB({pax, rax}); app.finishAxes(rax);
        end

        function drawHPBW(app, c, pk, ki, xl)
            [bw, lo, hi] = calcHPBW(c.angle, c.values(:, 1), pk, c.angle(ki)); if ~isfinite(bw), return; end
            b = [lo hi]; if xl(1) < 0, b = mod(b + 180, 360) - 180; else, b = mod(b, 360); end
            app.Label_HPBW.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
            if b(1) <= b(2), regions = b; else, regions = [xl(1), b(2); b(1), xl(2)]; end     % wrap-aware shading
            thetaregion(app.Single_paxCut, deg2rad(regions(:, 1)), deg2rad(regions(:, 2)), 'FaceColor', app.HPBWColor, 'FaceAlpha', 0.12);
            xregion(app.Single_AxesRect, regions(:, 1), regions(:, 2), 'FaceColor', app.HPBWColor, 'FaceAlpha', 0.12);
            names = ["Lower HPBW", "Upper HPBW"]; show = app.Single_CheckBox_HPBWBounds.Value;
            for k = 1:2
                rows = [dataTipTextRow(names(k), b(k), '%.2f°'); dataTipTextRow("Gain", pk - 3, '%.2f dB')];
                app.markPoint(app.Single_paxCut, [deg2rad(b(k)), pk - 3, 0], rows, 'APAT_HPBW', app.HPBWColor, show);
                app.markPoint(app.Single_AxesRect, [b(k), pk - 3, 0], rows, 'APAT_HPBW', app.HPBWColor, show);
            end
        end
    end

    %% ================================================================== coverage
    methods (Access = private)
        function onCoveragePushed(app, ~)
            % Coverage always consumes the CURRENT Main-tab View Table (loss, step and span already applied).
            if isempty(app.viewTbl), uialert(app.UIFigure, 'Load and process a pattern first.', 'Coverage'); return; end
            [app.TabGroup.SelectedTab, app.Cov_EditField_filePath.Value] = deal(app.Tab2_Coverage, app.filePath);
            node = app.covFindByPath(app.filePath);
            if isempty(node), app.covAddPattern(app.baseName, app.viewTbl, app.physTheta, app.filePath);
            else, app.covSyncFromView(node); app.Cov_Tree.SelectedNodes = node; app.setCoverageUI(); end
            app.setStatus(app.Cov_StatusBar, 'Coverage source synchronized from the current Main-tab View Table.', false);
        end

        function covSyncFromView(app, node)
            d = node.NodeData; d.pattern = app.viewTbl; d.theta = app.physTheta; d.solidAngle = app.solidAngle;
            d.name = app.baseName; d.revision = d.revision + 1; node.NodeData = d; app.covSyncPattern(node);
        end

        function node = covAddPattern(app, name, T, theta, fp)
            node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', "pattern", 'pattern', T, 'theta', theta, 'solidAngle', solidWeights(theta, T.Phi), 'name', name, 'path', fp, 'revision', 0, 'component', "");
            expand(app.Cov_Tree); app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node]; app.Cov_Tree.SelectedNodes = node;
            app.covSyncPattern(node);
            set([app.Cov_Button_computeCov, app.Cov_Button_Reset, app.Groups.Component], 'Enable', 'on');
            app.setCoverageUI(); app.Cov_Panel_Results.Visible = 'on';
            app.setStatus(app.Cov_StatusBar, sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name), false);
        end

        function covSyncPattern(app, node)
            % Align component list, boresight detection and the threshold preset with NODE (idempotent).
            d = node.NodeData; T = d.pattern;
            prev = d.component; if prev == "", prev = string(app.Cov_DropDown_Component.Value); end
            app.setComponentItems(app.Cov_DropDown_Component, T, prev); comp = string(app.Cov_DropDown_Component.Value);
            if d.component ~= comp
                [~, d.boresightIndex] = calcOrientation(d.theta, T.Phi, T.(char(comp)), d.solidAngle, app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
                d.component = comp; node.NodeData = d;
                if app.Cov_DropDown_Orientation.Value == 0, app.onOrientationChanged(); end       % Auto follows the detected axis
            end
            key = sprintf('%s|%s|%d', d.path, comp, d.revision);        % preset only when pattern / component / view changes
            if app.covPresetKey ~= key
                app.setCoverageRange(peakWindow(T.(char(comp)), app.PeakPercentile, app.PeakMaxExcessDB, [-40 10]), "threshold");
                app.covPresetKey = key;
            end
        end

        function node = covPatternTarget(app)
            % Pattern ancestor of the selection, otherwise the most recently added pattern node.
            node = []; n = app.Cov_Tree.SelectedNodes;
            while ~isempty(n) && isa(n(1), 'matlab.ui.container.TreeNode')
                if isstruct(n(1).NodeData) && n(1).NodeData.kind == "pattern", node = n(1); return; end
                n = n(1).Parent;
            end
            kids = app.Cov_TreeNode_Results.Children;
            for k = numel(kids):-1:1
                if isstruct(kids(k).NodeData) && kids(k).NodeData.kind == "pattern", node = kids(k); return; end
            end
        end

        function node = covFindByPath(app, fp)
            node = [];
            for k = app.Cov_TreeNode_Results.Children(:).'
                if isstruct(k.NodeData) && isfield(k.NodeData, 'path') && strcmp(k.NodeData.path, fp), node = k; return; end
            end
        end

        function jobs = covJobs(app, roots)
            % All job nodes below ROOTS (default: whole tree) in creation order. The tree is the single registry.
            if nargin < 2, roots = app.Cov_TreeNode_Results; end
            jobs = matlab.ui.container.TreeNode.empty(0, 1);
            for r = roots(:).'
                if isstruct(r.NodeData) && r.NodeData.kind == "job", jobs(end+1, 1) = r; end %#ok<AGROW>
                jobs = [jobs; app.covJobs(r.Children)]; %#ok<AGROW>
            end
        end

        function jobs = covChecked(app, jobs)
            checked = app.Cov_Tree.CheckedNodes;
            if isempty(checked), jobs = jobs([]); else, jobs = jobs(ismember(jobs, checked)); end
        end

        function thr = covThresholds(app)
            % The threshold spinners are used verbatim; the automatic preset is applied only by covSyncPattern.
            tMin = app.Cov_Spinner_ThreshMin.Value; tMax = app.Cov_Spinner_ThreshMax.Value; step = max(app.Cov_Spinner_Step.Value, 0.1);
            if tMax <= tMin, tMax = min(100, tMin + step); app.Cov_Spinner_ThreshMax.Value = tMax; end
            thr = (tMin:step:tMax).'; if isempty(thr) || thr(end) < tMax, thr(end+1, 1) = tMax; end
        end

        function job = covAddJob(app, parent, thr, cov, label, tableTag, extra)
            % Plot one CCDF curve and register it as a job node under PARENT (curve metadata lives in NodeData).
            app.covRunID = app.covRunID + 1; icon = '📉'; if isfield(extra, 'fromFile'), icon = '📈'; end
            name = sprintf('%s R%d %s', icon, app.covRunID, label);
            curve = plot(app.Cov_Axes, thr, cov, 'LineWidth', 1.6, 'DisplayName', name);
            job = uitreenode(parent, 'Text', name);
            d = struct('kind', "job", 'id', app.covRunID, 'thr', thr(:), 'cov', cov(:), 'line', curve, 'label', name, 'tableTag', tableTag, 'isConical', false, 'orientationLabel', "n/a");
            for f = string(fieldnames(extra)).', d.(char(f)) = extra.(char(f)); end
            job.NodeData = d;
        end

        function finalizeJobs(app)
            % Results table (union of thresholds × checked jobs), legend, tree expansion and panel state.
            jobs = app.covJobs(); checked = app.covChecked(jobs);
            expand(app.Cov_TreeNode_Results); if ~isempty(jobs), expand(unique([jobs.Parent])); end
            thr = app.covThresholds();
            if ~isempty(checked), c = arrayfun(@(n) n.NodeData.thr, checked, 'UniformOutput', false); thr = unique(vertcat(c{:})); end
            n = numel(checked); vals = nan(numel(thr), n + 1); vals(:, 1) = thr; names = [{'Threshold (dB)'}, cell(1, n)];
            lines = gobjects(1, n); labels = cell(1, n);
            for k = 1:n
                d = checked(k).NodeData; vals(:, k+1) = interp1(d.thr, d.cov, thr, 'linear', NaN);
                names{k+1} = sprintf('R%d %s %%', d.id, d.tableTag); lines(k) = d.line; labels{k} = d.label;
            end
            app.Cov_Tabel.Data = array2table(compose('%.2f', vals), 'VariableNames', names);
            if n == 0, legend(app.Cov_Axes, 'off'); else, legend(app.Cov_Axes, lines, labels, 'Location', 'southwest', 'Interpreter', 'none'); end
            app.setCoverageUI();
        end

        function onComputeCoverage(app, ~)
            node = app.covPatternTarget();
            if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if ~isempty(app.viewTbl) && strcmp(node.NodeData.path, app.filePath), app.covSyncFromView(node); end   % Main-tab pattern follows the live view
            d = node.NodeData; T = d.pattern; comp = app.Cov_DropDown_Component.Value; thr = app.covThresholds();
            endPerf = app.startPerf("Compute coverage");
            try
                conical = app.Cov_ButtonGroup_Btn_Conical.Value; mask = true(height(T), 1); extra = struct('isConical', conical);
                label = 'Sph coverage'; tableTag = 'Sph';
                if conical
                    [~, extra.orientationLabel] = app.covOrientation(node);
                    cone = [app.Cov_Spinner_ConeTH.Value, mod(app.Cov_Spinner_ConePH.Value, 360), app.Cov_Spinner_ConeAng.Value]; extra.cone = cone;
                    mask = cosd(d.theta)*cosd(cone(1)) + sind(d.theta)*sind(cone(1)).*cosd(T.Phi - cone(2)) >= cosd(cone(3));   % great-circle distance ≤ α
                    center = app.coneCenterLabel(cone(1), cone(2));
                    label = sprintf('Conical coverage (%s) α=%s°', center, fmtNumber(cone(3)));
                    tableTag = sprintf('Con %s α%s°', erase(center, ["=", ","]), fmtNumber(cone(3)));
                end
                cov = coverageCCDF(T.(comp), mask, thr, d.solidAngle);
                job = app.covAddJob(node, thr, cov, sprintf('%s %c %s', label, char(183), comp), tableTag, extra);
                app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; job];
                app.finalizeJobs(); app.setCoverageRange([thr(1) thr(end)], "plot"); app.Cov_Panel_Results.Visible = 'on';
                endPerf();
                msg = sprintf('Run-<b>%d</b> computed: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', app.covRunID, label, d.name, comp, numel(thr));
                if conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, extra.orientationLabel); end
                app.setStatus(app.Cov_StatusBar, msg, false);
            catch ME
                endPerf(); app.showError(ME, 'Coverage Error');
            end
        end

        function [index, label] = covOrientation(app, node)
            % Auto (0) resolves to the node's detected boresight; explicit selections are authoritative.
            index = app.Cov_DropDown_Orientation.Value;
            if index == 0 && ~isempty(node) && isfield(node.NodeData, 'boresightIndex'), index = node.NodeData.boresightIndex; end
            label = "n/a"; if index >= 1, label = string(app.PrincipalAxes.labels{index}); end
        end

        function label = coneCenterLabel(app, theta, phi)
            % A principal-axis name when the centre coincides with ±X/±Y/±Z, otherwise the spherical coordinates.
            ax = app.PrincipalAxes; v = [sind(theta)*cosd(phi), sind(theta)*sind(phi), cosd(theta)];
            A = [sind(ax.theta(:)).*cosd(ax.phi(:)), sind(ax.theta(:)).*sind(ax.phi(:)), cosd(ax.theta(:))];
            k = find(A * v(:) >= 1 - 1e-9, 1);
            if isempty(k), label = sprintf('θ=%s°, φ=%s°', fmtNumber(theta), fmtNumber(phi)); else, label = string(ax.labels{k}); end
        end

        function onOrientationChanged(app, ~)
            [k, label] = app.covOrientation(app.covPatternTarget());
            if k >= 1, [app.Cov_Spinner_ConeTH.Value, app.Cov_Spinner_ConePH.Value] = deal(app.PrincipalAxes.theta(k), app.PrincipalAxes.phi(k)); end
            app.reportOrientation(label);
        end

        function reportOrientation(app, label)
            % Keep exactly one "| Orientation" suffix on the persistent Coverage status (conical mode only).
            base = regexprep(char(app.Cov_StatusBar.UserData), '\s*\|\s*Orientation <b>.*?</b>$', '');
            if app.Cov_ButtonGroup_Btn_Conical.Value && label ~= "n/a", base = sprintf('%s | Orientation <b>%s</b>', base, label); end
            app.setStatus(app.Cov_StatusBar, base, false);
        end

        function onCovTypeChanged(app, ~)
            conical = app.Cov_ButtonGroup_Btn_Conical.Value; set(app.Groups.Cone, 'Enable', conical, 'Visible', conical);
            node = app.covPatternTarget(); if conical && ~isempty(node), app.covSyncPattern(node); end
            [~, label] = app.covOrientation(node); app.reportOrientation(label);
        end

        function onCovComponentChanged(app, ~)
            node = app.covPatternTarget(); if isempty(node), return; end
            d = node.NodeData; d.component = ""; node.NodeData = d;          % force re-detection for the new component
            app.covSyncPattern(node); [~, label] = app.covOrientation(node); app.reportOrientation(label);
        end
        function h = covArtifacts(app, d, tag)
            h = [findall(app.Cov_Axes, 'Tag', tag); findall(d.line, 'Tag', tag)];
        end

        function covRunQuery(app, mode)
            % "cov": coverage at a threshold; "thr": threshold reaching a coverage. Marks every checked job under the selection.
            sel = app.Cov_Tree.SelectedNodes;
            if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to query.', true); return; end
            jobs = app.covChecked(app.covJobs(sel));
            if isempty(jobs), app.setStatus(app.Cov_StatusBar, 'No checked results under the selected node.', true); return; end
            if mode == "cov", q = app.Cov_Spinner_queryCov.Value; else, q = app.Cov_Spinner_queryThresh.Value; end
            ax = app.Cov_Axes; hit = false;
            rows = [dataTipTextRow("Threshold", 'XData', '%.2f dB'); dataTipTextRow("Coverage", 'YData', '%.2f%%')];
            for j = jobs.'
                d = j.NodeData; tag = sprintf('CovQ_%s_%d', mode, d.id); delete(app.covArtifacts(d, tag));
                try, d.line.DataTipTemplate.DataTipRows = rows; catch, end
                [x, y] = covQueryPoint(d, mode, q); if ~isfinite(x) || ~isfinite(y), continue; end
                col = d.line.Color;
                line(ax, [x x], [ax.YLim(1) y], 'Color', col, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [app.RangeLimits(1) x], [y y], 'Color', col, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'HandleVisibility', 'off', 'FontSize', 9, 'Tag', tag); hit = true;
            end
            if ~hit, app.setStatus(app.Cov_StatusBar, 'Query value is outside the selected checked range.', true);
            elseif mode == "cov", app.setStatus(app.Cov_StatusBar, sprintf('Coverage queried at %s dB.', fmtNumber(q)), false);
            else, app.setStatus(app.Cov_StatusBar, sprintf('Threshold queried at %s%% coverage.', fmtNumber(q)), false); end
        end

        function onTreeChecked(app, ~)
            jobs = app.covJobs(); checked = app.covChecked(jobs);
            for j = jobs.'
                d = j.NodeData; on = any(checked == j);
                set([d.line; app.covArtifacts(d, sprintf('CovQ_cov_%d', d.id)); app.covArtifacts(d, sprintf('CovQ_thr_%d', d.id)); findall(d.line, 'Type', 'datatip')], 'Visible', on);
            end
            app.finalizeJobs();
        end

        function onTreeSelection(app, ~)
            sel = app.Cov_Tree.SelectedNodes;
            for j = app.covJobs().', d = j.NodeData; d.line.LineWidth = 1.6 + (~isempty(sel) && j == sel(1)); end   % emphasise the selected curve
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(app.Cov_StatusBar, 'Ready.', false); return; end
            d = sel(1).NodeData; p = app.covPatternTarget(); if ~isempty(p), app.covSyncPattern(p); end
            if d.kind ~= "job"
                n = numel(sel(1).Children); kind = 'Pattern'; if d.kind == "results", kind = 'Results'; end
                app.setStatus(app.Cov_StatusBar, sprintf('%s <b>"%s"</b> -- <b>%d</b> coverage job%s.', kind, d.name, n, repmat('s', 1, n ~= 1)), false);
                if d.kind == "pattern", [~, label] = app.covOrientation(p); app.reportOrientation(label); end
                return
            end
            parts = {char(d.label)};
            if d.isConical, parts{end+1} = sprintf('Orientation <b>%s</b>', d.orientationLabel); end
            parts{end+1} = sprintf('Threshold [%s, %s] dB | Step %s dB', fmtNumber(d.thr(1)), fmtNumber(d.thr(end)), fmtNumber(gridStep(d.thr)));
            t50 = covQueryPoint(d, "thr", 50);
            if isfinite(t50), parts{end+1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', fmtNumber(t50)); else, parts{end+1} = '<b>50%-coverage unavailable</b>'; end
            shown = round(d.cov, 2); mx = max(shown); mi = find(shown == mx, 1, 'last');       % table precision; last tied row of the CCDF
            parts{end+1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmtNumber(mx), fmtNumber(d.thr(mi)));
            app.setStatus(app.Cov_StatusBar, strjoin(parts, ' | '), false);
        end

        function onCovClear(app, ~)
            jobs = app.covJobs(app.Cov_Tree.SelectedNodes);
            if isempty(jobs), app.setStatus(app.Cov_StatusBar, 'Select a node with coverage results to clear.', true); return; end
            for j = jobs.'
                d = j.NodeData; delete([app.covArtifacts(d, sprintf('CovQ_cov_%d', d.id)); app.covArtifacts(d, sprintf('CovQ_thr_%d', d.id)); findall(d.line, 'Type', 'datatip')]);
            end
            app.setStatus(app.Cov_StatusBar, 'Selected DataTips and query markers cleared.', true);
        end

        function onCovReset(app, ~)
            delete(app.Cov_TreeNode_Results.Children); delete(findall(app.Cov_Axes, 'Type', 'datatip'));
            cla(app.Cov_Axes); legend(app.Cov_Axes, 'off'); app.covAxesDefaults(); app.Cov_Axes.XLimMode = 'auto';
            app.Cov_Tabel.Data = table(); app.covRunID = 0; app.covPresetKey = ""; app.covXInit = false;
            set([app.Cov_Button_computeCov, app.Cov_Button_Export, app.Cov_Button_Clear, app.Cov_Button_Reset, app.Groups.Query], 'Enable', 'off');
            set([app.Cov_Spinner_XRange, app.Cov_Spinner_XMin, app.Cov_Spinner_XMax], 'Limits', app.RangeLimits);
            app.Cov_Spinner_XRange.Value = [-40 10]; app.Cov_Spinner_XMin.Value = -40; app.Cov_Spinner_XMax.Value = 10;
            app.Cov_Panel_Results.Visible = 'off'; app.setCoverageUI();
            app.setStatus(app.Cov_StatusBar, 'Coverage workspace reset 🔄', true);
        end

        function onCovExport(app, ~)
            if isempty(app.Cov_Tabel.Data), return; end
            app.exportTable(app.Cov_Tabel.Data, 'coverage_results.csv', 'Export Coverage Results', app.Cov_StatusBar, 'Coverage results');
        end

        function onCovLoad(app, ~)
            fp = strtrim(app.Cov_EditField_filePath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFindByPath(fp))
                [f, p] = uigetfile(app.FileFilter, 'Select a pattern or coverage results file'); if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            existing = app.covFindByPath(fp);
            if ~isempty(existing)
                app.Cov_Tree.SelectedNodes = existing; app.onTreeSelection([]); app.setCoverageUI();
                app.setStatus(app.Cov_StatusBar, 'File already loaded -- node selected. Add another job or load a different file.', true); return
            end
            app.Cov_EditField_filePath.Value = fp;
            try
                out = app.readSource(fp, app.Groups.CovFormat);
                if out.userData.isCoverage
                    p = app.covPatternTarget(); if ~isempty(p), app.Cov_EditField_filePath.Value = p.NodeData.path; end
                    app.covLoadResults(fp, out.rawTbl);
                else
                    [~, name] = fileparts(fp); T = app.buildPattern(out); app.covAddPattern(name, T, T.Theta, fp);
                end
            catch ME
                app.showError(ME, 'Coverage Load Error');
            end
        end

        function T = buildPattern(app, out)
            % Process an auxiliary source (block 1) with the current parameters without touching the Main view.
            std = normalizePattern(out.blocks{1}); std.Properties.UserData = out.userData;
            T = calcPattern(std, app.getParam());
        end

        function covLoadResults(app, fp, data)
            [~, name] = fileparts(fp);
            node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📄 ' name]); node.NodeData = struct('kind', "results", 'name', name, 'path', fp);
            thr = data{:, 1}; n = width(data) - 1; jobs = cell(n, 1);
            for k = 1:n, jobs{k} = app.covAddJob(node, thr, data{:, k+1}, data.Properties.VariableNames{k+1}, data.Properties.VariableNames{k+1}, struct('fromFile', true)); end
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node; vertcat(jobs{:})];
            step = gridStep(thr); if isfinite(step), app.Cov_Spinner_Step.Value = min(app.Cov_Spinner_Step.Value, step); end
            app.setCoverageRange([min(thr) max(thr)], "plot"); expand(node); app.finalizeJobs(); app.Cov_Panel_Results.Visible = 'on';
            app.setStatus(app.Cov_StatusBar, sprintf('Coverage results file "%s" loaded (%d curves).', name, n), false);
        end

        function onCovTextFormatChanged(app, ~)
            % Re-interpret an already loaded generic coverage-pattern node with the newly selected text format.
            fp = strtrim(app.Cov_EditField_filePath.Value); old = app.covFindByPath(fp);
            if ~isfile(fp) || ~isTextFile(fp) || isempty(old), return; end
            try
                out = readPattern(fp, app.Cov_DropDown_TextFormat.Value, table());
                if out.userData.isCoverage, app.setStatus(app.Cov_StatusBar, 'Coverage-result files are detected automatically; no reprocessing required.', true); return; end
                T = app.buildPattern(out); name = old.NodeData.name;
                for j = app.covJobs(old).', delete(j.NodeData.line); end
                delete(old); app.covAddPattern(name, T, T.Theta, fp); app.finalizeJobs();
                app.setStatus(app.Cov_StatusBar, sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
            catch ME
                app.showError(ME, 'Coverage Format Error');
            end
        end

        function setCoverageUI(app)
            % Panel states: no pattern → load controls only (+ query tools when results exist); pattern → everything.
            hasPattern = ~isempty(app.covPatternTarget()); hasJobs = ~isempty(app.covJobs()); ctrls = app.Cov_gridPanel_Parm.Children;
            if hasPattern
                set(ctrls, 'Visible', 'on', 'Enable', 'on');
                set([app.Cov_Button_Export, app.Cov_Button_Clear, app.Groups.Query], 'Enable', hasJobs);
                isText = isTextFile(app.Cov_EditField_filePath.Value);
                set(app.Groups.CovFormat, 'Visible', isText, 'Enable', isText);
                app.onCovTypeChanged();
            else
                set(ctrls, 'Visible', 'off'); set(app.Groups.File, 'Visible', 'on', 'Enable', 'on');
                if hasJobs, set([app.Groups.Query, app.Cov_Button_Reset, app.Cov_Button_Export, app.Cov_Button_Clear, app.Cov_Button_toMain], 'Visible', 'on', 'Enable', 'on'); end
            end
        end

        function setCoverageRange(app, bounds, mode)
            % "threshold": preset the evaluation spinners (exact once, widen-only afterwards).
            % "plot": the first curve defines the X baseline; later curves may only expand it.
            lim = app.RangeLimits; b = clampRange(bounds, lim);
            if mode == "threshold"
                cur = [app.Cov_Spinner_ThreshMin.Value, app.Cov_Spinner_ThreshMax.Value];
                if app.covPresetKey ~= "", b = [min(cur(1), b(1)), max(cur(2), b(2))]; end
                set([app.Cov_Spinner_ThreshMin, app.Cov_Spinner_ThreshMax], 'Limits', lim);
                app.Cov_Spinner_ThreshMin.Value = b(1); app.Cov_Spinner_ThreshMax.Value = b(2);
                app.Cov_Spinner_ThreshMin.Limits = [lim(1), b(2) - 0.1]; app.Cov_Spinner_ThreshMax.Limits = [b(1) + 0.1, lim(2)];
                return
            end
            if app.covXInit, b = [min(app.Cov_Axes.XLim(1), b(1)), max(app.Cov_Axes.XLim(2), b(2))]; end
            app.covXInit = true; app.covSyncing = true; cleanup = onCleanup(@() app.clearSync()); %#ok<NASGU>
            set(app.Cov_Axes, 'XLimMode', 'manual', 'XLim', b);
            set([app.Cov_Spinner_XMin, app.Cov_Spinner_XMax, app.Cov_Spinner_XRange], 'Limits', lim);
            app.Cov_Spinner_XRange.Value = b; app.Cov_Spinner_XRange.Limits = b;
            app.Cov_Spinner_XMin.Value = b(1); app.Cov_Spinner_XMax.Value = b(2);
            app.Cov_Spinner_XMin.Limits = [lim(1), b(2) - 0.1]; app.Cov_Spinner_XMax.Limits = [b(1) + 0.1, lim(2)];
        end

        function syncCoverageXRange(app, event)
            % The Min/Max spinners are the master controls (they define the slider travel); the slider only selects within.
            if app.isClosing || app.covSyncing, return; end
            lim = app.RangeLimits; sl = app.Cov_Spinner_XRange; lo = app.Cov_Spinner_XMin; hi = app.Cov_Spinner_XMax;
            if event.Source == sl
                b = max(lim(1), min(lim(2), sort(event.Value))); if diff(b) <= 0, return; end
                lo.Value = b(1); hi.Value = b(2); set(app.Cov_Axes, 'XLimMode', 'manual', 'XLim', b); return
            end
            b = max(lim(1), min(lim(2), sort([lo.Value, hi.Value])));
            if diff(b) <= 0
                gap = max(sl.Step, eps); if event.Source == lo, b(2) = min(lim(2), b(1) + gap); else, b(1) = max(lim(1), b(2) - gap); end
            end
            app.covSyncing = true; cleanup = onCleanup(@() app.clearSync()); %#ok<NASGU>
            sl.Limits = lim; sl.Value = b; sl.Limits = b; lo.Value = b(1); hi.Value = b(2);
            lo.Limits = [lim(1), b(2) - 0.1]; hi.Limits = [b(1) + 0.1, lim(2)];
            set(app.Cov_Axes, 'XLimMode', 'manual', 'XLim', b);
        end
        function clearSync(app), if ~app.isClosing, app.covSyncing = false; end, end
        function covAxesDefaults(app)
            hold(app.Cov_Axes, 'on'); grid(app.Cov_Axes, 'on'); set(app.Cov_Axes, 'YLim', [0 100], 'Box', 'on', 'Layer', 'top');
        end
    end

    %% ================================================================== main-tab callbacks, export, lifecycle
    methods (Access = private)
        function onLoad(app, ~)
            fp = strtrim(app.Single_EditField_Path.Value);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.filePath)        % empty / invalid / already loaded → browse (re-selecting reloads)
                [f, p] = uigetfile(app.FileFilter, 'Select an antenna pattern file'); if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Loading Data', 'Message', 'Reading file...', 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            app.operationDialog = dlg; cleaner = onCleanup(@() close(dlg)); drawnow; %#ok<NASGU>
            endPerf = app.startPerf("Load pattern");
            try
                out = app.readSource(fp, app.Groups.Format); app.perfTracker("Read file");
                if out.userData.isCoverage                                % coverage results never replace the Main state
                    endPerf(); [app.TabGroup.SelectedTab, app.Cov_EditField_filePath.Value] = deal(app.Tab2_Coverage, fp);
                    app.covLoadResults(fp, out.rawTbl); return
                end
                app.Single_EditField_Path.Value = fp; app.filePath = fp;
                [app.folderPath, app.baseName, ext] = fileparts(fp); app.fileName = [app.baseName ext];
                app.activateSource(out);
                dd = app.Single_DropDown_FFD;
                if out.userData.isDep
                    items = compose('Pattern %d: %.4g GHz', (1:numel(out.blocks))', out.freqs(:)/1e9);
                    missing = isnan(out.freqs(:)); items(missing) = compose('Pattern %d', find(missing));
                    dd.Items = items; dd.Value = items{1};
                end
                set(app.Groups.FFD, 'Visible', out.userData.isDep, 'Enable', out.userData.isDep);
                [app.keepOneDegree, app.autoCutBasis] = deal(false, true);
                app.refresh(); endPerf();
            catch ME
                endPerf();
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.setStatus(app.Single_StatusBar, 'Loading cancelled by user.', true); else, app.showError(ME, 'Loading Error'); end
            end
        end

        function onProcess(app, ~)
            if isempty(app.stdTbl), uialert(app.UIFigure, 'No file! Load a pattern first.', 'Warning', 'Icon', 'warning'); return; end
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Processing', 'Message', 'Re-processing pattern...', 'Indeterminate', 'on'); cleaner = onCleanup(@() close(dlg)); %#ok<NASGU>
            endPerf = app.startPerf("Reprocess pattern"); app.keepOneDegree = strcmp(app.Single_DropDown_step.Value, app.OneDegreeItem);
            try
                if isTextFile(app.filePath)                               % reinterpret the cached generic table with the selected format
                    out = readPattern(app.filePath, app.Single_DropDown_TextFormat.Value, app.rawTbl);
                    assert(~out.userData.isCoverage, 'The selected generic format identifies a coverage-results file.');
                    app.activateSource(out);
                end
                app.refresh(); endPerf();
                app.setStatus(app.Single_StatusBar, ['Re-processed <b>' app.fileName '</b> with the current parameters ✅'], true);
            catch ME
                endPerf(); app.showError(ME, 'Processing Error');
            end
        end

        function onTextFormatChanged(app, ~)
            fp = strtrim(app.Single_EditField_Path.Value);
            if strcmp(fp, app.filePath) && isTextFile(fp), app.autoCutBasis = true; app.onProcess(); end
        end

        function onFFDChanged(app, ~)
            endPerf = app.startPerf("Switch FFD block"); dd = app.Single_DropDown_FFD; k = find(strcmp(dd.Items, dd.Value), 1);
            app.autoCutBasis = true; app.selectBlock(k); app.refresh(); endPerf();
            app.setStatus(app.Single_StatusBar, sprintf('Switched to FFD block %d (%s).', k, dd.Value), true);
        end

        function stepChanged(app, ~)
            endPerf = app.startPerf("Change angular step");
            app.processView(); app.updateComponentItems(); app.updateView(true, true, true); endPerf();
        end

        function refreshAngularView(app)
            if isempty(app.viewBaseTbl), return; end
            endPerf = app.startPerf("Change angular span"); app.applyAngularSpan(); app.updateView(false, true, true); endPerf();
        end

        function onComponentChanged(app, ~)
            if app.srcUD.isGainOnly, app.updateView(false, true, false); app.onPlaneChanged();   % gain-only cuts follow the selected column
            else, app.updateView(false, true, true); end
        end

        function resetParams(app, ~)
            p = app.defaultParams; if isempty(fieldnames(p)), return; end
            [app.Single_Spinner_Loss.Value, app.Single_DropDown_RxPol.Value, app.Single_Spinner_Rw.Value, app.Single_Spinner_Pt.Value, ...
                app.Single_DropDown_Pt.Value, app.Single_Spinner_R.Value, app.Single_DropDown_R.Value] = deal(p.Loss, p.RxMode, p.Rw, p.Pt, p.PtUnit, p.R, p.RUnit);
            if ~isempty(app.stdTbl), app.refresh(); end
        end

        function exportResults(app, ~)
            app.exportTable(app.Single_Table_DataOut.Data, [app.baseName '_APAT_results.csv'], 'Export Results', app.Single_StatusBar, 'Results');   % respects the column filter
        end

        function exportCut(app, ~)
            c = app.cutData(); T = array2table([c.angle, c.values], 'VariableNames', [{'Angle_deg'}, cellstr(c.cols)]);
            app.exportTable(T, [app.baseName '_cut.csv'], 'Export Cut', app.Single_StatusBar, ['Cut (' c.title ')']);
        end

        function exportTable(app, T, defaultName, ttl, statusLabel, what)
            [f, p] = uiputfile({'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, ttl, fullfile(app.folderPath, defaultName));
            if isequal(f, 0), return; end
            try, writeTable(T, fullfile(p, f)); app.setStatus(statusLabel, sprintf('%s exported to <b>%s</b>', what, fullfile(p, f)), true);
            catch ME, app.showError(ME, [ttl ' Error']); end
        end

        function exportUAN(app, ~)
            if app.srcUD.isGainOnly, uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            if isempty(app.uanTbl)
                V = app.viewTbl; assert(all(ismember({'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase'}, V.Properties.VariableNames)), 'UAN requires processed E-field columns.');
                app.uanTbl = sortrows(table(app.physTheta, V.Phi, round(V.E_TH_dB, 5), round(V.E_PH_dB, 5), round(V.E_TH_Phase, 5), round(V.E_PH_Phase, 5), ...
                    'VariableNames', {'Theta','Phi','E_TH_DB','E_PH_DB','E_TH_DG','E_PH_DG'}), {'Phi', 'Theta'});
            end
            U = app.uanTbl; step = gridStep(U.Theta); if ~isfinite(step), step = 1; end
            peak = max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan');
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'}, ...
                'Export UAN / E-field data', fullfile(app.folderPath, sprintf('%s_%.5f_%gdeg.uan', app.baseName, peak, step)));
            if isequal(f, 0), return; end
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Saving Data', 'Message', 'Writing file...', 'Indeterminate', 'on'); cleaner = onCleanup(@() close(dlg)); %#ok<NASGU>
            try
                fpOut = fullfile(p, f);
                if endsWith(fpOut, '.uan', 'IgnoreCase', true)
                    header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                        'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                        min(U.Phi), max(U.Phi), gridStep(mod(U.Phi, 360)), min(U.Theta), max(U.Theta), step, peak);
                    writelines(header, fpOut); writetable(U, fpOut, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
                else
                    writeTable(U, fpOut);
                end
                app.setStatus(app.Single_StatusBar, ['UAN exported to <b>' fpOut '</b>'], true);
            catch ME
                app.showError(ME, 'Export UAN Error');
            end
        end

        function setStatus(app, label, msg, temporary)
            % Persistent messages are remembered in label.UserData; temporary ones revert to it after 3 s.
            if app.isClosing || ~isgraphics(label), return; end
            t = app.statusTimer; if ~isempty(t) && isvalid(t), stop(t); end
            label.Text = char(msg);
            if temporary && ~isempty(t), t.UserData = label; start(t); elseif ~temporary, label.UserData = char(msg); end
        end
        function restoreStatus(app, t)
            if ~app.isClosing && isgraphics(t.UserData), t.UserData.Text = t.UserData.UserData; end
        end

        function showError(app, ME, ttl)
            if app.isClosing || ~isvalid(app.UIFigure), return; end
            loc = ''; if ~isempty(ME.stack), loc = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.UIFigure, [ME.message loc], ttl, 'Icon', 'error');
        end

        function checkCancelled(app)
            % Abort at the next pipeline checkpoint after the user pressed Abort on the progress dialog.
            d = app.operationDialog;
            if ~isempty(d) && isvalid(d) && d.CancelRequested, d.Message = 'Aborting...'; drawnow limitrate; error('APAT:Cancelled', 'Operation cancelled by user.'); end
        end

        function done = startPerf(app, op)
            % Stage timer for profiling sessions; results are published as Perf_<class> in the base workspace.
            stages = cell(0, 2); t0 = tic; t = tic; app.perfTracker = @track; done = @save;
            function track(stage), stages(end+1, :) = {string(stage), toc(t)}; t = tic; end
            function save()
                app.perfTracker = @(~) [];
                assignin('base', matlab.lang.makeValidName("Perf_" + class(app)), struct('Operation', string(op), 'Stages', cell2table(stages, 'VariableNames', {'Stage', 'Seconds'}), 'TotalSeconds', toc(t0)));
            end
        end

        function cleanupResources(app)
            t = app.statusTimer; app.statusTimer = []; if ~isempty(t) && isvalid(t), stop(t); delete(t); end
            d = app.operationDialog; app.operationDialog = []; if ~isempty(d) && isvalid(d), delete(d); end
        end

        function startupFcn(app)
            app.statusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, 'Name', 'APAT_StatusTimer', 'TimerFcn', @(t, ~) app.restoreStatus(t));
            for s = app.Full, app.initAxes(s.axes, ~isempty(s.view)); end
            app.initAxes(app.Single_AxesRect, false); app.initAxes(app.Single_paxCut, false); app.covAxesDefaults();
            set([app.Single_StatusBar, app.Cov_StatusBar], 'Text', 'Ready -- load an antenna pattern file to begin 🚀', 'UserData', 'Ready -- load an antenna pattern file to begin 🚀');
            app.defaultParams = struct('Loss', app.Single_Spinner_Loss.Value, 'RxMode', app.Single_DropDown_RxPol.Value, 'Rw', app.Single_Spinner_Rw.Value, ...
                'Pt', app.Single_Spinner_Pt.Value, 'PtUnit', app.Single_DropDown_Pt.Value, 'R', app.Single_Spinner_R.Value, 'RUnit', app.Single_DropDown_R.Value);
            app.setCoverageUI();
        end
    end

    %% ================================================================== UI construction
    methods (Access = private)
        function h = mkLabel(~, parent, text, row, col, varargin)
            h = at(uilabel(parent, 'Text', text, 'HorizontalAlignment', 'right', varargin{:}), row, col);
        end

        function dd = textFormatDropdown(app, parent, callback)
            dd = uidropdown(parent, 'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
                '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                'ItemsData', {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'}, 'Value', 'gain', 'Visible', 'off', ...
                'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'ValueChangedFcn', createCallbackFcn(app, callback, true));
        end

        function s = createPatternTab(app, tg, ttl, name, kind, view)
            % One full-pattern tab: axes + vertical range slider with max/min spinners; returns its spec record.
            g = uigridlayout(uitab(tg, 'Title', ttl), 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
            if kind == "polar", ax = polaraxes(g); set(ax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            else, ax = uiaxes(g); xlabel(ax, 'Phi (degree)'); ylabel(ax, 'Theta (degree)'); set(ax, 'XLim', [0 360], 'YLim', [0 180], 'YDir', 'reverse', 'Box', 'on'); end
            lim = app.RangeLimits;
            s = struct('name', name, 'tab', g.Parent, 'axes', at(ax, [1 3], 2), 'view', view, ...
                'slider', at(uislider(g, 'range', 'Limits', lim, 'Value', lim, 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(h, ~) app.setRange("full", h.Value, 0, true)), 2, 1), ...
                'maxSpinner', at(uispinner(g, 'Limits', lim, 'Value', 100, 'Step', 5, 'ValueChangedFcn', @(h, ~) app.setRange("full", h.Value, 2, true)), 1, 1), ...
                'minSpinner', at(uispinner(g, 'Limits', lim, 'Value', -250, 'Step', 5, 'ValueChangedFcn', @(h, ~) app.setRange("full", h.Value, 1, true)), 3, 1));
        end

        function createComponents(app)
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.ReleaseName], 'Visible', 'off', 'Position', [100 100 1136 739], 'WindowState', 'maximized', ...
                'CloseRequestFcn', createCallbackFcn(app, @closeRequest, true));
            app.TabGroup = at(uitabgroup(uigridlayout(app.UIFigure, [1 1])), 1, 1);
            app.Tab1_Single = uitab(app.TabGroup, 'Title', 'Process Pattern 📡');
            app.Tab2_Coverage = uitab(app.TabGroup, 'Title', 'Compute Coverage 📈');
            app.createMainTab(); app.createCoverageTab();
            app.UIFigure.Visible = 'on';
        end

        function createMainTab(app)
            lim = app.RangeLimits; cb = @(fcn) createCallbackFcn(app, fcn, true);
            G = uigridlayout(app.Tab1_Single, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});
            % ---- Inputs & parameters
            P = uigridlayout(at(uipanel(G, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 14]), 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            app.mkLabel(P, 'Input Pattern:', 1, 1);
            app.Single_EditField_Path = at(uieditfield(P, 'text'), 1, [2 8]);
            ffdLabel = app.mkLabel(P, 'FFD Freq:', 1, 9, 'Visible', 'off');
            app.Single_DropDown_FFD = at(uidropdown(P, 'Items', {'Frequencies'}, 'Visible', 'off', 'ValueChangedFcn', cb(@onFFDChanged)), 1, 10);
            app.Single_Button_Load = at(uibutton(P, 'push', 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', cb(@onLoad)), 1, [11 12]);
            app.Single_Button_Process = at(uibutton(P, 'push', 'Text', '⚙️ Process', 'ButtonPushedFcn', cb(@onProcess)), 1, [13 14]);
            app.Single_Button_ResetParams = at(uibutton(P, 'push', 'Text', 'Reset Params', 'ButtonPushedFcn', cb(@resetParams)), 2, [1 3]);
            fmtLabel = app.mkLabel(P, 'Format:', 2, [4 5], 'Visible', 'off');
            app.Single_DropDown_TextFormat = at(app.textFormatDropdown(P, @onTextFormatChanged), 2, [6 8]);
            app.Single_DropDown_step = at(uidropdown(P, 'Items', {'STEP', app.OneDegreeItem}, 'Value', 'STEP', 'Enable', 'off', 'Visible', 'off', 'ValueChangedFcn', cb(@stepChanged)), 2, [9 10]);
            app.Single_Export_Output = at(uibutton(P, 'push', 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@exportResults)), 2, [11 12]);
            app.Single_Export_UAN = at(uibutton(P, 'push', 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@exportUAN)), 2, [13 14]);
            rxLabel = app.mkLabel(P, 'Rw Sense', 3, 1);
            app.Single_DropDown_RxPol = at(uidropdown(P, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Value', 'Auto', 'Editable', 'on'), 3, 2);
            rwLabel = app.mkLabel(P, 'Rw (dB)', 3, 3);
            app.Single_Spinner_Rw = at(uispinner(P, 'Value', 6), 3, 4);
            lossLabel = app.mkLabel(P, 'Loss (−) / Gain (+) dB', 3, 5);
            app.Single_Spinner_Loss = at(uispinner(P, 'Step', 0.1), 3, 6);
            txLabel = app.mkLabel(P, 'Tx Pwr (Pt)', 3, 7);
            app.Single_Spinner_Pt = at(uispinner(P), 3, 8);
            app.Single_DropDown_Pt = at(uidropdown(P, 'Items', {'dBW', 'dBm', 'Watts'}, 'Value', 'dBW'), 3, 9);
            distLabel = app.mkLabel(P, 'Distance', 3, 10);
            app.Single_Spinner_R = at(uispinner(P, 'Value', 1), 3, 11);
            app.Single_DropDown_R = at(uidropdown(P, 'Items', {'m', 'km'}, 'Value', 'm'), 3, 12);
            app.Single_Button_Coverage = at(uibutton(P, 'push', 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', cb(@onCoveragePushed)), 3, [13 14]);
            app.Groups = struct('Rx', [rxLabel, app.Single_DropDown_RxPol, rwLabel, app.Single_Spinner_Rw], 'Tx', [txLabel, app.Single_Spinner_Pt, app.Single_DropDown_Pt], ...
                'Distance', [distLabel, app.Single_Spinner_R, app.Single_DropDown_R], 'Loss', [lossLabel, app.Single_Spinner_Loss], ...
                'FFD', [ffdLabel, app.Single_DropDown_FFD], 'Format', [fmtLabel, app.Single_DropDown_TextFormat]);
            set([app.Groups.Rx, app.Groups.Tx, app.Groups.Distance, app.Groups.Loss], 'Visible', 'off');
            % ---- Full antenna pattern
            app.Single_Panel_fullPattern = at(uipanel(G, 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off', 'BackgroundColor', [0.9412 0.9412 0.9412]), [2 3], [1 6]);
            tabs = at(uitabgroup(uigridlayout(app.Single_Panel_fullPattern, [1 1])), 1, 1);
            app.Full = [app.createPatternTab(tabs, 'Contour Plot', "contour", "rect", []), ...
                app.createPatternTab(tabs, 'Circular Contour Plot', "circular", "polar", []), ...
                app.createPatternTab(tabs, '3D Spherical Plot', "sphere3D", "rect", [135 25]), ...
                app.createPatternTab(tabs, '3D Polar Plot', "polar3D", "rect", [135 25]), ...
                app.createPatternTab(tabs, '3D Surface Plot', "rect3D", "rect", [-35 35])];
            % ---- Antenna pattern cut
            app.Single_Panel_Rect = at(uipanel(G, 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off', 'BackgroundColor', [0.9412 0.9412 0.9412]), [2 3], [7 12]);
            cutTabs = at(uitabgroup(uigridlayout(app.Single_Panel_Rect, [1 1])), 1, 1);
            C = uigridlayout(uitab(cutTabs, 'Title', 'Polar Cut Plot'), 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            app.Range_Cut_Max = at(uispinner(C, 'Limits', lim, 'Value', 100, 'Step', 5, 'ValueChangedFcn', @(h, ~) app.setRange("cut", h.Value, 2, true)), 1, 1);
            app.Range_Cut = at(uislider(C, 'range', 'Limits', lim, 'Value', lim, 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(h, ~) app.setRange("cut", h.Value, 0, true)), [2 3], 1);
            app.Range_Cut_Min = at(uispinner(C, 'Limits', lim, 'Value', -250, 'Step', 5, 'ValueChangedFcn', @(h, ~) app.setRange("cut", h.Value, 1, true)), 4, 1);
            app.Single_paxCut = at(polaraxes(C), [1 4], 3); set(app.Single_paxCut, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            app.Button_HPBW = at(uibutton(C, 'state', 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', cb(@onCutChanged)), 1, 4);
            app.Label_HPBW = at(uilabel(C, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold'), 2, 4);
            app.Single_gridEcut = at(uigridlayout(C, [3 1]), 3, 4);
            app.CheckBox_Et = at(uicheckbox(app.Single_gridEcut, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', cb(@onCutChanged)), 1, 1);
            app.CheckBox_Er = at(uicheckbox(app.Single_gridEcut, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', cb(@onCutChanged)), 2, 1);
            app.CheckBox_El = at(uicheckbox(app.Single_gridEcut, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', cb(@onCutChanged)), 3, 1);
            at(uibutton(C, 'push', 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', cb(@exportCut)), 4, 4);
            app.Single_AxesRect = at(uiaxes(uigridlayout(uitab(cutTabs, 'Title', 'Rectangular Cut Plot'), [1 1])), 1, 1);
            xlabel(app.Single_AxesRect, 'Theta (degree)'); ylabel(app.Single_AxesRect, 'Magnitude (dB)'); app.Single_AxesRect.Box = 'on';
            % ---- Data tabs
            app.Single_DropDown_output = at(uidropdown(G, 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Value', 0, 'Visible', 'off', 'ValueChangedFcn', cb(@filterOutput)), 3, [13 14]);
            app.Single_tabData = at(uitabgroup(G, 'Visible', 'off'), 4, [1 14]);
            tOut = uitab(app.Single_tabData, 'Title', 'Results 📤', 'ButtonDownFcn', @(~, ~) set(app.Single_DropDown_output, 'Visible', 'on'));
            app.Single_Table_DataOut = at(uitable(uigridlayout(tOut, [1 1]), 'ColumnWidth', '1x', 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true, 'Visible', 'off'), 1, 1);
            app.Single_Table_DataIn = at(uitable(uigridlayout(uitab(app.Single_tabData, 'Title', 'Input 📥'), [1 1]), 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true, 'Visible', 'off'), 1, 1);
            app.Single_Table_metadata = at(uitable(uigridlayout(uitab(app.Single_tabData, 'Title', 'Metadata 📋'), [1 1]), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {}), 1, 1);
            app.Single_StatusBar = at(uilabel(G, 'Text', 'Ready 🚀', 'Interpreter', 'html'), 5, [1 14]);
            % ---- Plot control
            app.Single_Panel_plotControl = at(uipanel(G, 'Title', 'Plot Control 🎨', 'Visible', 'off'), 2, [13 14]);
            K = uigridlayout(app.Single_Panel_plotControl, 'RowHeight', repmat({'fit'}, 1, 15));
            applyAll = @(~, ~) app.setRange("all", [app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value], 0, true);
            app.mkLabel(K, 'Component', 1, 1);
            app.Single_DropDown_Component = at(uidropdown(K, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'Value', 'E_Total_dB', 'ValueChangedFcn', cb(@onComponentChanged)), 1, 2);
            app.mkLabel(K, 'Cut type', 2, 1);
            app.Single_DropDown_cutType = at(uidropdown(K, 'Items', {'Phi', 'Theta'}, 'Value', 'Phi', 'ValueChangedFcn', cb(@onCutChanged)), 2, 2);
            app.mkLabel(K, 'Cut value', 3, 1);
            app.Single_DropDown_cutValue = at(uispinner(K, 'Limits', [0 360], 'Value', 0, 'ValueChangedFcn', cb(@onCutChanged)), 3, 2);
            app.mkLabel(K, 'Cut fields', 4, 1);
            app.CutFieldBasisDropDown = at(uidropdown(K, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Value', 'Circular', 'Enable', 'off', 'ValueChangedFcn', cb(@onCutChanged)), 4, 2);
            app.mkLabel(K, 'Colorbar max', 5, 1);
            app.Single_Plot_Cmax = at(uispinner(K, 'Limits', lim, 'Value', 10, 'ValueChangedFcn', applyAll), 5, 2);
            app.mkLabel(K, 'Colorbar min', 6, 1);
            app.Single_Plot_Cmin = at(uispinner(K, 'Limits', lim, 'Value', -40, 'ValueChangedFcn', applyAll), 6, 2);
            app.mkLabel(K, 'Colorbar step', 7, 1);
            app.Single_Plot_Cstep = at(uispinner(K, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', @(~, ~) app.applyFullRange(app.ctrLim)), 7, 2);
            app.mkLabel(K, 'Adjust Colorbar', 8, 1);
            at(uibutton(K, 'push', 'Text', 'Apply', 'Tooltip', 'Apply to full-pattern plots; the cut range stays independent for AR.', 'ButtonPushedFcn', applyAll), 8, 2);
            app.mkLabel(K, '3D view', 9, 1);
            app.Single_DropDown_3DView = at(uidropdown(K, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Value', 'iso', 'Tooltip', 'Camera direction for the 3D pattern tabs.', 'ValueChangedFcn', @(~, ~) app.on3DViewChanged()), 9, 2);
            pad = @(n) repmat(char(160), 1, n);      % non-breaking padding centres the switch captions
            app.Single_Switch_AngularSpan = at(uiswitch(K, 'slider', 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'Value', '0° to 360°', 'ValueChangedFcn', @(~, ~) app.refreshAngularView()), 10, [1 2]);
            app.Single_Switch_ThetaSpan = at(uiswitch(K, 'slider', 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'Value', '0° to 180°', 'ValueChangedFcn', @(~, ~) app.refreshAngularView()), 11, [1 2]);
            app.Single_Switch_EHplane = at(uiswitch(K, 'slider', 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'Value', 'E-Plane cut', 'ValueChangedFcn', cb(@onPlaneChanged)), 12, [1 2]);
            app.Single_CheckBox_overlayCut = at(uicheckbox(K, 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', @(~, ~) app.overlayCuts()), 13, [1 2]);
            app.Single_CheckBox_POB = at(uicheckbox(K, 'Text', 'Annotate POB', 'ValueChangedFcn', @(~, ~) app.annotatePOB()), 14, [1 2]);
            app.Single_CheckBox_HPBWBounds = at(uicheckbox(K, 'Text', 'Annotate HPBW Bounds', 'Visible', 'off', 'ValueChangedFcn', @(h, ~) set(findall(app.UIFigure, 'Tag', 'APAT_HPBW'), 'Visible', h.Value)), 15, [1 2]);
        end

        function createCoverageTab(app)
            lim = app.RangeLimits; cb = @(fcn) createCallbackFcn(app, fcn, true);
            G = uigridlayout(app.Tab2_Coverage, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            P = uigridlayout(at(uipanel(G, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 5]), 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'});
            app.Cov_gridPanel_Parm = P;
            bg = at(uibuttongroup(P, 'Title', 'Coverage Type', 'SelectionChangedFcn', cb(@onCovTypeChanged)), [1 2], [1 2]);
            uiradiobutton(bg, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            app.Cov_ButtonGroup_Btn_Conical = uiradiobutton(bg, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            oLabel = app.mkLabel(P, 'Orientation 🧭:', 3, 1, 'Enable', 'off');
            app.Cov_DropDown_Orientation = at(uidropdown(P, 'Items', [{'Auto'}, app.PrincipalAxes.labels], 'ItemsData', 0:numel(app.PrincipalAxes.labels), 'Value', 0, 'Enable', 'off', 'ValueChangedFcn', cb(@onOrientationChanged)), 3, 2);
            cLabel = app.mkLabel(P, 'Component:', 4, 1, 'Enable', 'off');
            app.Cov_DropDown_Component = at(uidropdown(P, 'Items', {'E_Total_dB'}, 'Value', 'E_Total_dB', 'Enable', 'off', 'ValueChangedFcn', cb(@onCovComponentChanged)), 4, 2);
            fLabel = app.mkLabel(P, 'Antenna Pattern:', 1, 3);
            app.Cov_EditField_filePath = at(uieditfield(P, 'text'), 1, [4 8]);
            app.Cov_Button_Load = at(uibutton(P, 'push', 'Text', '📂 Load File', 'ButtonPushedFcn', cb(@onCovLoad)), 1, 9);
            app.Cov_Button_computeCov = at(uibutton(P, 'push', 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', cb(@onComputeCoverage)), 1, 10);
            app.mkLabel(P, 'Threshold  Min (dB):', 2, 3); app.Cov_Spinner_ThreshMin = at(uispinner(P, 'Value', -40), 2, 4);
            app.mkLabel(P, 'Threshold  Max (dB):', 2, 5); app.Cov_Spinner_ThreshMax = at(uispinner(P, 'Value', 10), 2, 6);
            app.mkLabel(P, 'Step (dB):', 2, 7);           app.Cov_Spinner_Step = at(uispinner(P, 'Value', 1), 2, 8);
            app.Cov_Button_Reset = at(uibutton(P, 'push', 'Text', '🔄 Reset', 'Enable', 'off', 'ButtonPushedFcn', cb(@onCovReset)), 2, 9);
            app.Cov_Button_Export = at(uibutton(P, 'push', 'Text', '💾 Export Results', 'Enable', 'off', 'ButtonPushedFcn', cb(@onCovExport)), 2, 10);
            tLabel = app.mkLabel(P, 'Cone θ₀ (°):', 3, 3, 'Enable', 'off');       app.Cov_Spinner_ConeTH = at(uispinner(P, 'Limits', [0 180], 'Enable', 'off'), 3, 4);
            pLabel = app.mkLabel(P, 'Cone φ₀ (°):', 3, 5, 'Enable', 'off');       app.Cov_Spinner_ConePH = at(uispinner(P, 'Limits', [0 360], 'Enable', 'off'), 3, 6);
            aLabel = app.mkLabel(P, 'Cone Angle α (°):', 3, 7, 'Enable', 'off');  app.Cov_Spinner_ConeAng = at(uispinner(P, 'Limits', [0 180], 'Value', 45, 'Enable', 'off'), 3, 8);
            app.Cov_Button_Clear = at(uibutton(P, 'push', 'Text', '🧹 Clear DataTips', 'Enable', 'off', 'ButtonPushedFcn', cb(@onCovClear)), 3, 9);
            app.Cov_Button_toMain = at(uibutton(P, 'push', 'Text', '📊 To Main ◀ ', 'ButtonPushedFcn', @(~, ~) set(app.TabGroup, 'SelectedTab', app.Tab1_Single)), 3, 10);
            qcLabel = app.mkLabel(P, 'Coverage @ dB:', 4, 3, 'Visible', 'off');
            app.Cov_Spinner_queryCov = at(uispinner(P, 'ValueDisplayFormat', '%g dB', 'Visible', 'off'), 4, 4);
            app.Cov_Button_queryCov = at(uibutton(P, 'push', 'Text', '⯐ Query Coverage', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.covRunQuery("cov")), 4, 5);
            qtLabel = app.mkLabel(P, 'Threshold @ %:', 4, 6, 'Visible', 'off');
            app.Cov_Spinner_queryThresh = at(uispinner(P, 'ValueDisplayFormat', '%g%%', 'Value', 50, 'Visible', 'off'), 4, 7);
            app.Cov_Button_queryThresh = at(uibutton(P, 'push', 'Text', '🔍︎ Query Threshold', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', @(~, ~) app.covRunQuery("thr")), 4, 8);
            covFmtLabel = app.mkLabel(P, 'Format:', 4, 9, 'Visible', 'off');
            app.Cov_DropDown_TextFormat = at(app.textFormatDropdown(P, @onCovTextFormatChanged), 4, 10);
            app.Cov_StatusBar = at(uilabel(G, 'Text', 'Ready 🚀', 'Interpreter', 'html'), 3, [1 5]);
            app.Groups.CovFormat = [covFmtLabel, app.Cov_DropDown_TextFormat]; app.Groups.Component = [cLabel, app.Cov_DropDown_Component];
            app.Groups.File = [fLabel, app.Cov_EditField_filePath, app.Cov_Button_Load, app.Cov_Button_computeCov];
            app.Groups.Cone = [tLabel, app.Cov_Spinner_ConeTH, pLabel, app.Cov_Spinner_ConePH, aLabel, app.Cov_Spinner_ConeAng, oLabel, app.Cov_DropDown_Orientation];
            app.Groups.Query = [qcLabel, app.Cov_Spinner_queryCov, app.Cov_Button_queryCov, qtLabel, app.Cov_Spinner_queryThresh, app.Cov_Button_queryThresh];
            % ---- Results
            app.Cov_Panel_Results = at(uipanel(G, 'Title', 'Results', 'Visible', 'off'), 2, [1 5]);
            R = uigridlayout(app.Cov_Panel_Results, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            app.Cov_Tree = at(uitree(R, 'checkbox', 'SelectionChangedFcn', cb(@onTreeSelection), 'CheckedNodesChangedFcn', cb(@onTreeChecked)), [1 2], 1);
            app.Cov_TreeNode_Results = uitreenode(app.Cov_Tree, 'Text', 'Coverage Results');
            app.Cov_Axes = at(uiaxes(R), 1, [2 4]); app.Cov_Axes.Interactions = dataTipInteraction;   % display-only axes
            title(app.Cov_Axes, 'Coverage vs Threshold'); xlabel(app.Cov_Axes, 'Threshold (dB)'); ylabel(app.Cov_Axes, 'Coverage (%)');
            app.Cov_Tabel = at(uitable(R, 'ColumnWidth', '1x', 'RowName', {}), [1 2], 5);
            app.Cov_Spinner_XMin = at(uispinner(R, 'Limits', lim, 'Value', -40, 'ValueChangedFcn', cb(@syncCoverageXRange)), 2, 2);
            app.Cov_Spinner_XRange = at(uislider(R, 'range', 'Limits', lim, 'Value', [-40 10], 'ValueChangedFcn', cb(@syncCoverageXRange), 'ValueChangingFcn', cb(@syncCoverageXRange)), 2, 3);
            app.Cov_Spinner_XMax = at(uispinner(R, 'Limits', lim, 'Value', 10, 'ValueChangedFcn', cb(@syncCoverageXRange)), 2, 4);
        end
    end

    %% ================================================================== public API
    methods (Access = public)
        function app = APAT_v3_M8_16
            createComponents(app); registerApp(app, app.UIFigure); runStartupFcn(app, @startupFcn);
            if nargout == 0, clear app; end
        end

        function closeRequest(app, ~)
            %CLOSEREQUEST Single shutdown path for the figure callback, delete(app) and tests.
            if app.isClosing, return; end
            app.isClosing = true; app.cleanupResources();
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end
        function delete(app), app.closeRequest(); end

        function report = runSelfTest(app)
            %RUNSELFTEST Deterministic numerical smoke checks of every pure service (no UI interaction).
            [P, T] = meshgrid(0:30:330, 0:30:180); tbl = table(T(:), P(:), 10*cosd(T(:)).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            w = solidWeights(tbl.Theta, tbl.Phi); omegaError = abs(sum(w) - 4*pi);
            [peak, axisIndex] = calcOrientation(tbl.Theta, tbl.Phi, tbl.E_Total_dB, w, app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
            [P2, T2] = meshgrid(0:2:358, 0:2:180); analytic = 12*cosd(T2).^2 - 0.5*sind(P2).^2;
            R = resampleCanonical(table(T2(:), P2(:), analytic(:), 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'}), 1);
            native = mod(round(R.Theta), 2) == 0 & mod(round(R.Phi), 2) == 0 & R.Phi < 360;
            numericalError = max(abs(R.E_Total_dB(native) - (12*cosd(R.Theta(native)).^2 - 0.5*sind(R.Phi(native)).^2)));
            spike = repmat(0.02, 100000, 1); spike(1) = 10.02; sp = resolvePeak(spike, app.PeakPercentile, app.PeakMaxExcessDB);
            ffd = [tempname '.ffd']; writelines(["0 180 3"; "-180 180 3"; compose('%d 0 0 1', (1:9)')], ffd); cleanupFFD = onCleanup(@() delete(ffd)); %#ok<NASGU>
            ffdData = readPattern(ffd, "ffd", table());
            report = struct( ...
                'passSolidAngle', omegaError < 1e-9, ...
                'passOrientation', isfinite(peak.value) && axisIndex >= 1 && axisIndex <= 6, ...
                'passResampling', height(R) == 181*361 && all(isfinite(R.Theta)) && all(isfinite(R.Phi)), ...
                'passNumericalEquivalence', numericalError < 1e-10, ...
                'passVisualRange', isequal(peakWindow([3.2; -250; -17], app.PeakPercentile, app.PeakMaxExcessDB), [-45 5]), ...
                'passPeakAwareRange', isequal(peakWindow(spike, app.PeakPercentile, app.PeakMaxExcessDB, [-40 10]), [-45 5]), ...
                'passIsolatedSpike', sp.wasAdjusted && abs(sp.value - 0.02) < 1e-12 && sp.rawIndex == 1, ...
                'passFFDReader', ffdData.userData.source == "HFSS FFD" && isscalar(ffdData.blocks) && height(ffdData.blocks{1}) == 9, ...
                'passARThemeSemantic', all(cellfun(@isAR, {'AR', 'AR_dB', 'AR dB', 'Axial Ratio', 'Axial_Ratio'})), ...
                'passCCDF', isequal(coverageCCDF([0; 10; 20], true(3, 1), [5; 15], [1; 1; 2]), [75; 50]), ...
                'passHPBW', abs(calcHPBW((-180:179)', -abs((-180:179)')/10) - 60) < 1e-9, ...
                'numericalError', numericalError, 'solidAngleError', omegaError, 'orientationIndex', axisIndex);
            flags = fieldnames(report); flags = flags(startsWith(flags, 'pass')); ok = cellfun(@(f) report.(f), flags);
            report.pass = all(ok);
            if ~report.pass, error('apat:test:SelfTestFailed', 'Self-test failed: %s.', strjoin(flags(~ok), ', ')); end
        end
    end
end
%% ====================================================================== local helpers (UI)
function h = at(h, row, col)
%at Place a grid-layout child and return it (enables single-expression construction).
h.Layout.Row = row; h.Layout.Column = col;
end
function tf = isTextFile(fp)
[~, ~, ext] = fileparts(fp); tf = ismember(lower(ext), {'.csv', '.txt', '.dat'});
end
function tf = isAR(component)
%isAR Axial-ratio semantics independent of column spelling (AR, AR_dB, "AR dB", Axial Ratio, Axial_Ratio, ...).
key = regexprep(lower(strtrim(string(component))), '[^a-z0-9]', '');
tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
end
function s = fmtNumber(v, precision)
%fmtNumber 'n/a' for non-finite scalars; compact (≤ 2 decimals, trailing zeros removed) or exactly N decimals.
if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); else, s = sprintf('%.*f', max(0, min(5, round(precision))), v); end
end
function r = clampRange(v, b)
%clampRange Sorted two-element range clamped to B with a minimum width of 1.
v = sort(double(v(:).')); if numel(v) < 2 || any(~isfinite(v(1:2))), r = b; return; end
r = [max(b(1), v(1)), min(b(2), v(2))];
if diff(r) < 1, r(2) = min(b(2), r(1) + 1); r(1) = max(b(1), r(2) - 1); end
end
function t = axisTicks(lim, step)
%axisTicks Multiples of STEP inside LIM plus both limits; empty when degenerate or more than 60 ticks.
t = [];
if numel(lim) ~= 2 || any(~isfinite(lim)) || ~isfinite(step) || step <= 0 || diff(lim) <= 0, return; end
t = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)]);
if numel(t) > 60, t = []; end
end
function c = chooseColumn(T, requested)
%chooseColumn REQUESTED if present, else E_Total_dB, else the first data column.
vars = T.Properties.VariableNames; cands = [string(requested), "E_Total_dB"]; k = find(ismember(cands, vars), 1);
if isempty(k), c = vars{3}; else, c = char(cands(k)); end
end
function writeTable(T, fp)
if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
end
function [x, y] = covQueryPoint(d, mode, q)
%covQueryPoint Coverage at threshold Q ("cov") or threshold reaching coverage Q ("thr") on one CCDF curve.
if mode == "cov"
    x = q; y = interp1(d.thr, d.cov, q, 'linear', NaN);
else
    [c, i] = unique(d.cov, 'last'); y = q; x = NaN; if numel(c) >= 2, x = interp1(c, d.thr(i), q, 'linear', NaN); end
end
end
%% ====================================================================== numerical services (physical coordinates)
function s = gridStep(v)
%gridStep Smallest positive spacing between distinct finite samples (NaN when fewer than two).
d = diff(unique(v(isfinite(v)))); d = d(d > 1e-9);
if isempty(d), s = NaN; else, s = min(d); end
end
function info = resolvePeak(values, pct, excess)
%resolvePeak Effective peak: the raw maximum unless it exceeds the P<pct> level by more than EXCESS dB
% (isolated spike). Then the highest sample at or below that level is the peak and the spikes are masked.
v = double(values(:)); finite = isfinite(v); s = sort(v(finite));
info = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(v)), 'wasAdjusted', false);
if isempty(s), return; end
[info.rawValue, info.rawIndex] = max(v, [], 'omitnan'); info.value = info.rawValue; info.index = info.rawIndex;
level = s(max(1, ceil(pct/100 * numel(s))));                          % nearest-rank percentile: no toolbox dependency
if info.rawValue > level + excess
    info.outlierMask = finite & v > level; c = v; c(~finite | info.outlierMask) = -Inf;
    if any(isfinite(c)), [info.value, info.index] = max(c); info.wasAdjusted = true; else, info.outlierMask(:) = false; end
end
end
function b = peakWindow(values, pct, excess, fallback)
%peakWindow 50-dB window whose top is the effective peak rounded up to the next 5 dB (display range / threshold preset).
if nargin < 4, fallback = [-50 0]; end
p = resolvePeak(values, pct, excess); if ~isfinite(p.value), b = fallback; return; end
top = min(100, ceil(p.value/5)*5); b = [max(-250, top - 50), top];
end
function w = solidWeights(theta, phi)
%solidWeights Exact solid angle of each uniform grid cell; the duplicated closing phi seam gets zero weight.
ts = gridStep(theta); ps = gridStep(mod(phi, 360));
if ~isfinite(ts), ts = 180; end
if ~isfinite(ps), ps = 360; end
w = (cosd(max(theta - ts/2, 0)) - cosd(min(theta + ts/2, 180))) * deg2rad(ps);
seam = 360 - 180*any(phi < 0); w(abs(phi - seam) < 1e-9) = 0;
end
function [peak, axisIndex] = calcOrientation(theta, phi, gainDB, w, axes, pct, excess)
%calcOrientation Peak policy plus the principal axis whose 45° cone captures the most radiated power.
peak = resolvePeak(gainDB, pct, excess); g = double(gainDB(:));
if peak.wasAdjusted, g(peak.outlierMask) = NaN; end
weight = 10.^((g - peak.value)/10) .* w(:); weight(~isfinite(weight)) = 0;
A = [sind(axes.theta(:)).*cosd(axes.phi(:)), sind(axes.theta(:)).*sind(axes.phi(:)), cosd(axes.theta(:))];
S = [sind(theta(:)).*cosd(phi(:)), sind(theta(:)).*sind(phi(:)), cosd(theta(:))];
[~, axisIndex] = max(weight.' * double(S * A.' >= cosd(45)));
end
function m = calcMetrics(T, theta, w, axisTheta, axisPhi, elevation, pct, excess)
%calcMetrics Total-power metrics: directivity, efficiency, front-to-back, principal-plane HPBW and AR at the peak.
gain = T.(chooseColumn(T, 'E_Total_dB')); peak = resolvePeak(gain, pct, excess); k = peak.index;
g = gain; if peak.wasAdjusted, g(peak.outlierMask) = NaN; end
integrated = sum(10.^(g/10) .* w, 'omitnan');
[~, back] = min(cosd(theta)*cosd(theta(k)) + sind(theta)*sind(theta(k)).*cosd(T.Phi - T.Phi(k)));        % antipode of the peak
if axisTheta == 90, hType = "Phi"; hValue = 90*~elevation; else, hType = "Theta"; hValue = 90; end
[eAngle, eRows] = cutGeometry(T.Theta, theta, T.Phi, "Theta", axisPhi);
[hAngle, hRows] = cutGeometry(T.Theta, theta, T.Phi, hType, hValue);
ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(k); end
eff = 100*integrated/(4*pi); if eff < 0 || eff > 100, eff = NaN; end
m = struct('PeakGain_dB', peak.value, 'PeakTheta_deg', theta(k), 'PeakPhi_deg', mod(T.Phi(k), 360), ...
    'HPBW_EPlane_deg', calcHPBW(eAngle, gain(eRows)), 'HPBW_HPlane_deg', calcHPBW(hAngle, gain(hRows)), ...
    'FrontBack_dB', peak.value - gain(back), 'PeakDirectivity_dB', 10*log10(max(4*pi*10^(peak.value/10)/max(integrated, eps), eps)), ...
    'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', ar);
end
function [angle, rows, fixed, symbol, snapped] = cutGeometry(thetaDisp, thetaPhys, phi, type, requested)
%cutGeometry Rows and running angle of one full-circle cut, snapped to the nearest sampled plane.
if type == "Phi"                                  % fixed (display) theta, phi runs around the circle
    levels = unique(thetaDisp); [dist, k] = min(abs(levels - requested)); fixed = levels(k);
    rows = find(abs(thetaDisp - fixed) < 1e-9); [angle, o] = sort(phi(rows)); rows = rows(o); symbol = 'θ';
else                                              % fixed phi: theta 0..180, then 360-theta on the opposite half-plane
    p = mod(phi, 360); levels = unique(p); requested = mod(requested, 360);
    [dist, k] = min(abs(mod(levels - requested + 180, 360) - 180)); fixed = levels(k);
    [~, ko] = min(abs(mod(levels - fixed, 360) - 180));
    a = find(abs(p - fixed) < 1e-9); [~, o] = sort(thetaPhys(a)); a = a(o);
    b = find(abs(p - levels(ko)) < 1e-9 & abs(thetaPhys - 180) > 1e-9); [~, o] = sort(thetaPhys(b), 'descend'); b = b(o);
    rows = [a; b]; angle = [thetaPhys(a); 360 - thetaPhys(b)]; symbol = 'φ';
end
snapped = dist > 0;
end
function [bw, lo, hi] = calcHPBW(angle, gainDB, peakGain, peakAngle)
%calcHPBW Half-power beamwidth of a circular cut with linear interpolation of both -3 dB crossings.
[bw, lo, hi] = deal(NaN); ok = isfinite(angle) & isfinite(gainDB); angle = angle(ok); gainDB = gainDB(ok);
if numel(gainDB) < 3, return; end
if nargin < 3 || isempty(peakGain), [peakGain, i] = max(gainDB); peakAngle = angle(i); end
half = peakGain - 3; [rel, o] = sort(mod(angle - peakAngle + 180, 360) - 180); g = gainDB(o);
L = find(rel < 0 & g <= half, 1, 'last'); R = find(rel > 0 & g <= half, 1, 'first');
if isempty(L) || isempty(R) || L + 1 > numel(g) || R - 1 < 1 || g(L+1) == g(L) || g(R-1) == g(R), return; end
left = rel(L) + (rel(L+1) - rel(L)) * (half - g(L)) / (g(L+1) - g(L));
right = rel(R) + (rel(R-1) - rel(R)) * (half - g(R)) / (g(R-1) - g(R));
lo = peakAngle + left; hi = peakAngle + right; bw = right - left;
end
function cov = coverageCCDF(gain, mask, thr, w)
%coverageCCDF Coverage(T) [%] = 100 · Σ I(G_i > T)·Ω_i / Σ Ω_i over the region, for all thresholds at once.
ok = mask(:) & isfinite(gain(:)) & isfinite(w(:)) & w(:) >= 0; g = double(gain(ok)); ww = double(w(ok)); thr = double(thr(:));
cov = zeros(size(thr)); if isempty(g) || sum(ww) <= 0, return; end
cov = 100 * (ww.' * double(g > thr.')).' / sum(ww);
end
function [pattern, info] = calcPattern(std, param)
%calcPattern Derive every processed quantity from canonical fields (or gain columns) in one vectorised pass.
ud = std.Properties.UserData; info = struct('pol', 'n/a', 'pairs', struct('Linear', ["E_TH","E_PH"], 'Circular', ["E_RCP","E_LCP"]));
if isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly
    pattern = std; if width(pattern) > 2, pattern{:, 3:end} = pattern{:, 3:end} + param.GainLoss_dB; end
    return
end
Eth = complex(std.Re_Eth, std.Im_Eth) * param.FieldScale; Eph = complex(std.Re_Eph, std.Im_Eph) * param.FieldScale;
Ercp = (Eth + 1i*Eph)/sqrt(2); Elcp = (Eth - 1i*Eph)/sqrt(2);
[mTh, mPh, mR, mL] = deal(abs(Eth), abs(Eph), abs(Ercp), abs(Elcp));
total = 10*log10(max(mTh.^2 + mPh.^2, eps));

% Dominant polarisation from mean component power: drives co/cross ordering, the label and the Auto Rx sense.
pw = [mean(mTh.^2, 'omitnan'), mean(mPh.^2, 'omitnan'), mean(mR.^2, 'omitnan'), mean(mL.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP","E_LCP"], ["RHCP","LHCP"]));
elseif pw(1) >= pw(2), info.pol = 'Linear (Vertical)';
else, info.pol = 'Linear (Horizontal)'; end

% Signed axial ratio: + right-hand, − left-hand; equal circular components (linear limit) map to the −100 dB floor.
delta = mR - mL; sense = sign(delta); sense(~isfinite(delta)) = 0;
ar = (mR + mL) ./ max(abs(delta), eps);
signedAR = min(20*log10(ar), 250) .* sense; signedAR(isfinite(delta) & abs(delta) <= eps*max(mR + mL, 1)) = -100;

% Polarisation loss factor against an incident wave of axial ratio RxAR (worst-case tilt, 2Δτ = 180°).
if param.RxMode == "Auto", ws = 2*(info.pairs.Circular(1) == "E_RCP") - 1; elseif param.RxMode == "RHCP", ws = 1; else, ws = -1; end
ra = ar .* sense; ra(sense == 0) = 1e12; rw = ws * 10^(param.RxAR_dB/20);
plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1)) ./ (2*(ra.^2 + 1)*(rw^2 + 1));
plfDB = 10*log10(min(max(plf, eps), 1));

% Link-budget quantities.
eirp = param.Pt_dBW + total; eirpW = 10.^(eirp/10); pfd = eirpW / (4*pi*param.R_m^2); eRMS = sqrt(30*eirpW) / param.R_m;
dB = @(m) 20*log10(max(m, eps)); ph = @(E) rad2deg(angle(E));
pattern = table(std.Theta, std.Phi, total, signedAR, dB(mR), dB(mL), plfDB, total + plfDB, dB(mTh), dB(mPh), ph(Eth), ph(Eph), ph(Ercp), ph(Elcp), eirp, pfd, eRMS, ...
    'VariableNames', {'Theta','Phi','E_Total_dB','AR_dB','E_RCP_dB','E_LCP_dB','PLF_dB','Gain_PolCorrected_dB','E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'});
pattern.Properties.UserData = ud;
end
function T = normalizePattern(T)
%normalizePattern Map any angular convention onto the canonical sphere: theta 0..180, phi 0..360 with a closed
% seam, values rounded to 5 decimals (kills 1e-15 seam artefacts once), duplicate directions removed.
th = T.Theta;
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, T.Theta = 90 - th;                                   % elevation convention
    else, m = th < 0; T.Theta(m) = -th(m); T.Phi(m) = T.Phi(m) + 180; end                     % negative theta → opposite phi
end
T.Theta = mod(T.Theta, 360); over = T.Theta > 180; T.Theta(over) = 360 - T.Theta(over); T.Phi(over) = T.Phi(over) + 180;
num = varfun(@isnumeric, T, 'OutputFormat', 'uniform'); T{:, num} = round(T{:, num}, 5);
T.Phi = mod(T.Phi, 360); T.Theta(abs(T.Theta) < 1e-12) = 0; T.Phi(abs(T.Phi) < 1e-12) = 0;
[~, keep] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(keep, :);
seam = T(abs(T.Phi) < 1e-10, :); seam.Phi(:) = 360; T = [T; seam];
end
function R = resampleCanonical(S, step)
%resampleCanonical Resample PRIMITIVE data onto 0:step:180 × 0:step:360. E-field sources interpolate Re/Im
% components; gain-only sources interpolate linear power. Regular grids use interp2 with a periodic phi seam,
% irregular samples use scatteredInterpolant; both fall back to nearest-neighbour outside the convex hull.
theta = double(S.Theta); phiRaw = double(S.Phi); phi = mod(phiRaw, 360);
keep = isfinite(theta) & isfinite(phi) & theta >= -1e-9 & theta <= 180 + 1e-9 & abs(phiRaw - 360) > 1e-9;     % the phi=0 sample is authoritative
S = S(keep, :); theta = theta(keep); phi = phi(keep);
[~, u] = unique([theta, phi], 'rows', 'stable'); S = S(u, :); theta = theta(u); phi = phi(u);
[qPhi, qTheta] = meshgrid(unique([0:step:360, 360]), 0:step:180);
R = table(qTheta(:), qPhi(:), 'VariableNames', {'Theta', 'Phi'});
names = string(S.Properties.VariableNames(3:end)); isField = all(ismember(["Re_Eth","Im_Eth","Re_Eph","Im_Eph"], names));
sTheta = unique(theta); sPhi = unique(phi); regular = numel(sTheta)*numel(sPhi) == numel(theta);
if regular
    [~, it] = ismember(theta, sTheta); [~, ip] = ismember(phi, sPhi); idx = sub2ind([numel(sTheta), numel(sPhi)], it, ip);
    [gPhi, gTheta] = meshgrid([sPhi; sPhi(1) + 360], sTheta);                                           % periodic closing column
end
for n = names
    v = double(S.(char(n))); toLinear = ~isField && isGainDB(n); if toLinear, v = 10.^(v/10); end
    if regular
        g = nan(numel(sTheta), numel(sPhi)); g(idx) = v; g = [g, g(:, 1)]; %#ok<AGROW>
        q = interp2(gPhi, gTheta, g, qPhi, qTheta, 'linear', NaN); miss = ~isfinite(q);
        if any(miss(:)), nn = interp2(gPhi, gTheta, g, qPhi, qTheta, 'nearest', NaN); q(miss) = nn(miss); end
    else
        F = scatteredInterpolant(phi, theta, v, 'linear', 'nearest'); q = F(qPhi, qTheta);
    end
    if toLinear, q = 10*log10(max(q, realmin)); end
    R.(char(n)) = q(:);
end
R.Properties.UserData = S.Properties.UserData;
end
function tf = isGainDB(name)
%isGainDB Gain-like dB quantities that must be interpolated in linear power.
k = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', '');
tf = contains(k, 'gain') || contains(k, 'directivity') || contains(k, 'eirp') || endsWith(k, 'db');
end
%% ====================================================================== I/O services
function T = fieldTable(theta, phi, Eth, Eph)
T = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'});
end
function [Eth, Eph] = circToLinear(Ercp, Elcp)
Eth = (Ercp + Elcp)/sqrt(2); Eph = (Ercp - Elcp)/(1i*sqrt(2));
end
function E = dbPhase(magDB, phaseDeg)
E = 10.^(magDB/20) .* exp(1i*deg2rad(phaseDeg));
end
function out = readPattern(fp, fmt, cached)
%readPattern Any supported source → struct(rawTbl, blocks{canonical tables}, freqs, userData). UI independent.
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, 'userData', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'isMultiBlock', false, 'hasFrequency', false));
switch ext
    case {'XLSX', 'XLS'},       out = readExcelMatrix(fp);
    case {'CSV', 'TXT', 'DAT'}, out = readGenericText(fp, string(fmt), cached, out);
    case 'CUT',                 out = readGraspCut(fp, out);
    otherwise,                  out = readFarField(fp, ext, out);
end
for f = ["isGainOnly", "isCoverage", "isDep", "isMultiBlock", "hasFrequency"]
    if ~isfield(out.userData, char(f)), out.userData.(char(f)) = false; end
end
end
function out = readGenericText(fp, fmt, T, out)
%readGenericText Gain-only pattern, coverage results, or six-column E-field text with a user-selected layout.
if isempty(T)
    opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
    T = rmmissing(readtable(fp, opts));
end
n = width(T); assert(n >= 2 && ~isempty(T), 'readFile:InvalidFormat', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHeaders = ~all(startsWith(names, "Var")); raw = T; c1 = T{:, 1}; c2 = T{:, 2};
% Coverage results: strictly monotonic thresholds and 0..100 % columns (only when no E-field layout was requested).
covHeader = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
if (fmt == "gain" || n < 6 || covHeader) && all(isfinite(c2)) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:n-1))]; end
    out.rawTbl = T; out.userData.isCoverage = true; return
end
if fmt == "gain"                                              % the wider-spanning of the first two columns is phi
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    T = movevars(T, 'Theta', 'Before', 1); if ~hasHeaders, raw = T; end
    out.rawTbl = raw; out.blocks = {T}; out.userData.isGainOnly = true; return
end
assert(n >= 6, 'readFile:TextEFieldColumns', 'The selected generic E-field format requires six numeric columns.');
V = T{:, 3:6}; magPhase = endsWith(fmt, "magphase"); layout = "not applicable";
if magPhase                                                   % interleaved (mag, phase, mag, phase) vs grouped (mag, mag, phase, phase)
    big = max(abs(V), [], 1, 'omitnan') > 100;
    if big(2) && ~big(3), V = V(:, [1 3 2 4]); layout = "interleaved"; else, layout = "grouped"; end
    C1 = dbPhase(V(:, 1), V(:, 3)); C2 = dbPhase(V(:, 2), V(:, 4));
else
    C1 = complex(V(:, 1), V(:, 2)); C2 = complex(V(:, 3), V(:, 4));
end
if startsWith(fmt, "linear")
    [Eth, Eph] = deal(C1, C2); comp = ["E_TH", "E_PH"]; rect = ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"];
else
    if startsWith(fmt, "rcp"), [Eth, Eph] = circToLinear(C1, C2); else, [Eth, Eph] = circToLinear(C2, C1); end
    comp = ["POL1", "POL2"]; rect = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"];
end
if magPhase, gen = [comp + "_dB", comp + "_deg"]; if layout == "interleaved", gen = gen([1 3 2 4]); end, else, gen = rect; end
if ~hasHeaders, raw.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", gen]); end
out.userData.source = sprintf('Generic text (%s, %s)', fmt, layout);
out.rawTbl = raw; out.blocks = {fieldTable(c1, c2, Eth, Eph)};
end
function out = readGraspCut(fp, out)
%readGraspCut TICRA/GRASP .cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks.
out.userData.source = 'TICRA/GRASP CUT';
L = readlines(fp); L(strlength(strtrim(L)) == 0) = [];
th = {}; ph = {}; D = {}; i = 1; icomp = 1; icut = 1;
while i < numel(L)
    p = sscanf(L(i+1), '%f'); assert(numel(p) >= 7, 'parseCutFile:bad', 'Could not parse cut parameter line.');
    n = p(3); icomp = p(5); icut = p(6);
    B = reshape(sscanf(strjoin(L(i+2:i+1+n), ' '), '%f'), 2*p(7), []).';
    th{end+1, 1} = p(1) + (0:n-1)'*p(2); ph{end+1, 1} = repmat(p(4), n, 1); D{end+1, 1} = B(:, 1:4); i = i + 2 + n; %#ok<AGROW>
end
th = vertcat(th{:}); ph = vertcat(ph{:}); D = vertcat(D{:});
if icut == 2, [th, ph] = deal(ph, th); end                                 % ICUT=2: phi swept, theta constant
neg = th < 0; ph(neg) = ph(neg) + 180; th(neg) = -th(neg);                 % fold negative theta onto the opposite half-plane
if isscalar(unique(ph))                                                    % single cut → body of revolution
    copies = (0:10:350)'; m = numel(th); th = repmat(th, numel(copies), 1); ph = repelem(copies, m); D = repmat(D, numel(copies), 1);
end
C1 = complex(D(:, 1), D(:, 2)); C2 = complex(D(:, 3), D(:, 4));
if icomp == 2, [Eth, Eph] = circToLinear(C1, C2); names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; else, [Eth, Eph] = deal(C1, C2); names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; end
out.rawTbl = array2table([th, ph, D], 'VariableNames', [{'Theta', 'Phi'}, names]); out.blocks = {fieldTable(th, ph, Eth, Eph)};
end
function out = readFarField(fp, ext, out)
%readFarField Column-oriented far-field exports: XGTD UAN/FZ, GRASP OUT, CST FFS, FEKO FFE and HFSS FFD.
[nHdr, ffd] = findHeaderLines(fp);
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = readmatrix(fp, setvartype(opts, opts.VariableNames, 'double')); M = M(~all(isnan(M), 2), 1:min(end, 6));
switch ext
    case {'FZ', 'UAN'}     % Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
        out.userData.source = ['XGTD ' ext]; rawNames = {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'};
        th = M(:, 1); ph = M(:, 2); Eth = dbPhase(M(:, 3), M(:, 5)); Eph = dbPhase(M(:, 4), M(:, 6));
    case 'OUT'             % Theta Phi Re(RHCP) Im(RHCP) Re(LHCP) Im(LHCP)
        out.userData.source = 'TICRA/GRASP OUT'; rawNames = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'};
        th = M(:, 1); ph = M(:, 2); [Eth, Eph] = circToLinear(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)));
    case 'FFS'             % Phi Theta Re(Eth) Im(Eth) Re(Eph) Im(Eph)
        out.userData.source = 'CST FFS'; rawNames = {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'};
        ph = M(:, 1); th = M(:, 2); Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
    case 'FFE'             % Theta Phi Re(Eth) Im(Eth) Re(Eph) Im(Eph) [further columns ignored]
        out.userData.source = 'FEKO FFE'; rawNames = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'};
        th = M(:, 1); ph = M(:, 2); Eth = complex(M(:, 3), M(:, 4)); Eph = complex(M(:, 5), M(:, 6));
    case 'FFD'             % header-defined grid; one Re/Im Eth/Eph block per frequency, "Frequency f" separator rows
        out.userData.source = 'HFSS FFD'; assert(ffd.isFFD, 'readFile:ffd', 'FFD header (theta/phi ranges) not found.');
        thAxis = linspace(ffd.theta(1), ffd.theta(2), ffd.theta(3))'; phAxis = linspace(ffd.phi(1), ffd.phi(2), ffd.phi(3))';
        th = repelem(thAxis, numel(phAxis)); ph = repmat(phAxis, numel(thAxis), 1); n = numel(th);
        sep = isnan(M(:, 1)); freqs = [ffd.freq(:); M(sep & ~isnan(M(:, 2)), 2)].'; rows = M(~sep, 1:4);
        assert(mod(size(rows, 1), n) == 0, 'readFile:ffd', 'FFD mismatch: row count does not match the theta/phi grid.');
        nb = size(rows, 1)/n; freqs(end+1:nb) = NaN; freqs = freqs(1:nb);
        out.userData.isMultiBlock = nb > 1; out.userData.hasFrequency = any(isfinite(freqs)); out.userData.isDep = nb > 1 || any(isfinite(freqs));
        out.blocks = cellfun(@(B) fieldTable(th, ph, complex(B(:, 1), B(:, 2)), complex(B(:, 3), B(:, 4))), mat2cell(rows, repmat(n, nb, 1), 4), 'UniformOutput', false);
        out.freqs = freqs; out.rawTbl = out.blocks{1}; return
    otherwise
        error('readFile:unsupported', 'Unsupported format: %s', ext);
end
out.rawTbl = array2table(M(:, 1:6), 'VariableNames', rawNames); out.blocks = {fieldTable(th, ph, Eth, Eph)};
end
function [nHdr, ffd] = findHeaderLines(fp)
%findHeaderLines Count leading non-data lines; recognise the HFSS FFD header (two axis triples + optional frequencies).
fid = fopen(fp, 'r'); if fid < 0, error('apat:io:OpenFailed', 'Cannot open file: %s', fp); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
ffd = struct('theta', [], 'phi', [], 'freq', [], 'isFFD', false); triples = zeros(0, 3); nHdr = 0;
while size(triples, 1) < 2
    line = fgetl(fid); if ~ischar(line), break; end
    nHdr = nHdr + 1; s = strtrim(line); if isempty(s), continue; end
    v = sscanf(s, '%f').';
    if numel(v) == 3, triples(end+1, :) = v; elseif isempty(triples), break; end %#ok<AGROW>
end
if size(triples, 1) == 2
    ffd.theta = [triples(1, 1:2), round(triples(1, 3))]; ffd.phi = [triples(2, 1:2), round(triples(2, 3))];
    line = fgetl(fid); while ischar(line) && isempty(strtrim(line)), nHdr = nHdr + 1; line = fgetl(fid); end
    if ischar(line)
        nHdr = nHdr + 1; tok = regexp(strtrim(line), '^frequencies?\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if isempty(tok), nHdr = nHdr - 1;                                            % a data line: hand it back to readmatrix
        else, f = sscanf(tok{1}, '%f'); if ~isscalar(f), ffd.freq = f(:); end, end     % a lone "Frequencies N" is only a count
    end
    ffd.isFFD = all(isfinite([ffd.theta, ffd.phi])) && ffd.theta(3) >= 1 && ffd.phi(3) >= 1;
end
if ~ffd.isFFD                                                                        % generic: data starts at the first line with ≥ 4 numbers
    frewind(fid); nHdr = 0; num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?';
    while true
        line = fgetl(fid); if ~ischar(line) || ~isempty(regexp(line, ['^\s*' num '(?:[\s,;]+' num '){3,}\s*$'], 'once')), break; end
        nHdr = nHdr + 1;
    end
end
end
function out = readExcelMatrix(fp)
%readExcelMatrix Template workbooks: summary sheet first, then fixed-name component matrices (C3 origin, phi across
% row 2, theta down column B). dBi magnitude + degree phase sheets are rebuilt into complex Eth/Eph.
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"]; lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'readFile:ExcelMatrixFormat', 'Unsupported Excel workbook: expected the fixed Eth/Eph and/or RHCP/LHCP component sheets after the summary sheet.');
required = [circ(1:4*hasC), lin(1:4*hasL)]; M = struct(); ref = {};
for name = required
    [theta, phi, data] = readExcelSheet(fp, sheets(find(strcmpi(sheets, name), 1)));
    if isempty(ref), ref = {theta, phi};
    else, assert(isequal(size(theta), size(ref{1})) && isequal(size(phi), size(ref{2})) && max(abs(theta - ref{1})) < 1e-9 && max(abs(phi - ref{2})) < 1e-9, ...
            'readFile:ExcelMatrixGrid', 'All Excel Matrix component sheets must use the same theta/phi grid.'); end
    M.(char(name)) = data;
end
if hasL
    Eth = dbPhase(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = dbPhase(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees);
    label = 'Format 1 (Eth/Eph)'; basis = "theta-phi"; if hasC, label = 'Format 3 (Ercp/Elcp + Eth/Eph)'; basis = "theta-phi + RHCP/LHCP"; end
else
    [Eth, Eph] = circToLinear(dbPhase(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), dbPhase(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees));
    label = 'Format 2 (Ercp/Elcp)'; basis = "RHCP/LHCP";
end
[phiGrid, thetaGrid] = meshgrid(ref{2}, ref{1}); block = fieldTable(thetaGrid, phiGrid, Eth, Eph); raw = block;
for name = required, raw.(char(name)) = reshape(M.(char(name)), [], 1); end
md = readExcelSummary(fp, sheets(1));
md.source = ['Excel Matrix ' label]; md.format = regexprep(label, '^Format (\d).*', 'Format$1'); md.file = fp; md.summarySheet = char(sheets(1));
[md.isGainOnly, md.isCoverage, md.isDep, md.isMultiBlock] = deal(false); md.hasFrequency = isfinite(md.frequencyMHz);
md.polarizationBasis = basis; md.componentSheets = cellstr(required);
md.matrixGrid = struct('thetaDeg', ref{1}, 'phiDeg', ref{2}, 'thetaStepDeg', gridStep(ref{1}), 'phiStepDeg', gridStep(ref{2}));
out = struct('rawTbl', raw, 'blocks', {{block}}, 'freqs', NaN, 'userData', md);
end
function [theta, phi, data] = readExcelSheet(fp, sheet)
%readExcelSheet One C3-origin matrix; readcell keeps worksheet coordinates that readmatrix would auto-trim.
C = readcell(fp, 'Sheet', char(sheet));
assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'readFile:ExcelMatrixSheet', 'Sheet "%s" does not contain a C3-origin matrix.', sheet);
isNum = @(x) isnumeric(x) && isscalar(x) && isfinite(x); contiguous = @(m) ~any(m(find(~m, 1):end));     % no numeric cell after the first gap
pm = cellfun(isNum, C(2, 3:end)); tm = cellfun(isNum, C(3:end, 2));
assert(any(pm) && any(tm) && contiguous(pm) && contiguous(tm), 'readFile:ExcelMatrixAxis', 'Sheet "%s" has missing or non-contiguous theta/phi axes.', sheet);
phi = cell2mat(C(2, 2 + (1:nnz(pm)))).'; theta = cell2mat(C(2 + (1:nnz(tm)), 2)); D = C(2 + (1:numel(theta)), 2 + (1:numel(phi)));
assert(all(cellfun(isNum, D), 'all'), 'readFile:ExcelMatrixSheet', 'Sheet "%s" contains non-numeric or missing matrix samples.', sheet);
data = cell2mat(D);
assert(all(diff(theta) > 0) && all(diff(phi) > 0) && theta(1) >= -1e-9 && theta(end) <= 180 + 1e-9 && phi(1) >= -1e-9 && phi(end) < 360 + 1e-9, ...
    'readFile:ExcelMatrixAxis', 'Sheet "%s" needs strictly increasing axes within theta 0..180 and phi 0..360.', sheet);
end
function md = readExcelSummary(fp, sheet)
%readExcelSummary Fixed-layout template summary: every "Label:" in column B becomes a field (first value in C..E),
% plus frequency, frame definition and antenna positions as typed fields.
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch ME, error('readFile:ExcelSummary', 'Unable to read Excel summary sheet "%s": %s', sheet, ME.message); end
normLabel = @(s) regexprep(replace(lower(strtrim(string(s))), {char(160), char(8211), char(8212), char(8722), char(8230)}, {' ', '-', '-', '-', '...'}), {'\s+', '\s*:\s*$'}, {' ', ':'});
isText = cellfun(@(v) ischar(v) || isstring(v), C); labels = strings(size(C)); labels(isText) = normLabel(C(isText));
rowOf = @(label) find(any(labels == normLabel(label), 2), 1); valueAt = @(r) cellValue(C, r, 3:5);
md = struct();
for r = find(isText(:, 2)).'                                                          % generic capture of every labelled row
    v = valueAt(r); if ~isempty(v), md.(char(matlab.lang.makeValidName(regexprep(labels(r, 2), '[^a-zA-Z0-9]+', '_')))) = v; end
end
md.frequencyMHz = toDouble(valueAt(rowOf('Pattern Simulation Freq (MHz):')));
md.numberOfAntennas = toDouble(valueAt(rowOf('Number of Antennas (1 for single, 2 for pair, …):')));
frame = struct('names', ["+X direction", "+Y direction", "+Z direction"], 'azEl', NaN(3, 2));     % F = label, G = az / expression, H = el / handedness
for k = 1:3, r = rowOf(frame.names(k)); if ~isempty(r), frame.azEl(k, :) = [toDouble(C{r, 7}), toDouble(C{r, 8})]; end, end
frame.motionDirection = cellValue(C, rowOf('Motion direction'), 7); frame.vehicleString = cellValue(C, rowOf('Vehicle String'), 7);
r = rowOf('(az, el) => X conversion');
if ~isempty(r), frame.XExpression = C{r, 7}; frame.handedness = C{r, 8}; if r + 2 <= size(C, 1), frame.YExpression = C{r+1, 7}; frame.ZExpression = C{r+2, 7}; end, end
md.frameDefinition = frame; md.antennaPositionsInches = zeros(0, 3);
r = rowOf('Antenna locations as list of (X, Y, Z) [Inches]:'); nAnt = md.numberOfAntennas;
if ~isempty(r) && isfinite(nAnt) && nAnt >= 1
    rows = r:min(r + round(nAnt) - 1, size(C, 1));
    md.antennaPositionsInches = [cellfun(@toDouble, C(rows, 3)), cellfun(@toDouble, C(rows, 4)), cellfun(@toDouble, C(rows, 5))];
end
end
function v = cellValue(C, r, cols)
%cellValue First non-blank cell of row R within COLS (empty when R is empty or the row is blank).
v = [];
if isempty(r), return; end
for c = cols(cols <= size(C, 2))
    x = C{r, c}; if ~(isempty(x) || (~iscell(x) && all(ismissing(x(:))))), v = x; return; end
end
end
function v = toDouble(v)
if isnumeric(v) && ~isempty(v), v = double(v(1)); elseif ischar(v) || isstring(v), v = str2double(strtrim(string(v))); else, v = NaN; end
end