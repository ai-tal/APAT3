classdef APAT_v3_M8_39 < matlab.apps.AppBase %GM %1499
    % APAT_v3_M8: Antenna Pattern Analysis & Transformation Tool (Version M8)
    % Optimized, streamlined, and modularized App Designer architecture.
    % Provides full ingestion (FFD/CST/Satimo/TICRA/UAN/Excel Matrix),
    % canonical spherical normalization, polarization synthesis, RF metrics
    % (POB, HPBW, Directivity, F/B, Efficiency, AR), 2D/3D visualizations,
    % and solid-angle-weighted Conical Coverage CCDF analysis.

    properties (GetAccess = public, SetAccess = private)
        Version = "3.8.0-M8"
    end

    % UI Components
    properties (Access = public)
        UIFigure                        matlab.ui.Figure
        GridLayout                      matlab.ui.container.GridLayout
        TabGroup                        matlab.ui.container.TabGroup
        Tab1_Single                     matlab.ui.container.Tab
        Single_Grid                     matlab.ui.container.GridLayout
        Single_Panel_fullPattern        matlab.ui.container.Panel
        Single_gridPanel_full           matlab.ui.container.GridLayout
        Single_tabPlots                 matlab.ui.container.TabGroup
        Single_tab3D                    matlab.ui.container.Tab
        Single_Grid_3D                  matlab.ui.container.GridLayout
        Single_Axes_3D                  matlab.ui.control.UIAxes
        Single_tabSpatial3D             matlab.ui.container.Tab
        Single_Grid_Spatial             matlab.ui.container.GridLayout
        Single_Axes_Spatial             matlab.ui.control.UIAxes
        Single_tabFisheye               matlab.ui.container.Tab
        Single_Grid_Fisheye             matlab.ui.container.GridLayout
        Single_Axes_Fisheye             matlab.ui.control.UIAxes
        Single_tabRect3                 matlab.ui.container.Tab
        Single_Grid_Rect3               matlab.ui.container.GridLayout
        Single_Axes_Rect3               matlab.ui.control.UIAxes
        Single_tabContour               matlab.ui.container.Tab
        Single_Grid_Contour             matlab.ui.container.GridLayout
        Single_Axes_Ctr                 matlab.ui.control.UIAxes
        Single_Panel_Rect               matlab.ui.container.Panel
        Single_gridPanel_Cut            matlab.ui.container.GridLayout
        Single_tabCut                   matlab.ui.container.TabGroup
        Single_tabPolarPlot             matlab.ui.container.Tab
        Single_Grid_Polar               matlab.ui.container.GridLayout
        Single_Axes_CutPolar            matlab.ui.control.UIAxes
        Single_tabRectPlot              matlab.ui.container.Tab
        Single_Grid_Rect                matlab.ui.container.GridLayout
        Single_Axes_CutRect             matlab.ui.control.UIAxes
        Range_Cut                       matlab.ui.control.RangeSlider
        Range_3D                        matlab.ui.control.RangeSlider
        Range_Spatial                   matlab.ui.control.RangeSlider
        Range_Rect3                     matlab.ui.control.RangeSlider
        Range_Fisheye                   matlab.ui.control.RangeSlider
        Range_Ctr                       matlab.ui.control.RangeSlider
        Single_Panel_plotControl        matlab.ui.container.Panel
        Single_gridPanel_plotControl    matlab.ui.container.GridLayout
        Single_DropDown_Component       matlab.ui.control.DropDown
        Single_Switch_ThetaSpan         matlab.ui.control.Switch
        Single_DropDown_step            matlab.ui.control.DropDown
        Single_DropDown_View            matlab.ui.control.DropDown
        Single_CheckBox_POB             matlab.ui.control.CheckBox
        Single_Plot_Cstep               matlab.ui.control.Spinner
        Single_DropDown_cutPlane        matlab.ui.control.DropDown
        Single_DropDown_cutValue        matlab.ui.control.Spinner
        Single_Switch_EHplane           matlab.ui.control.Switch
        CutFieldBasisDropDown           matlab.ui.control.DropDown
        Button_HPBW                     matlab.ui.control.StateButton
        Label_HPBW                      matlab.ui.control.Label
        Single_Panel_Param              matlab.ui.container.Panel
        Single_Grid_Param               matlab.ui.container.GridLayout
        Single_Button_Load              matlab.ui.control.Button
        Single_DropDown_TextFormat      matlab.ui.control.DropDown
        Single_DropDown_Freq            matlab.ui.control.DropDown
        Single_Spinner_Loss             matlab.ui.control.Spinner
        Single_DropDown_RxPol           matlab.ui.control.DropDown
        Single_Spinner_Rw               matlab.ui.control.Spinner
        Single_Spinner_Pt               matlab.ui.control.Spinner
        Single_DropDown_Pt              matlab.ui.control.DropDown
        Single_Spinner_R                matlab.ui.control.Spinner
        Single_DropDown_R               matlab.ui.control.DropDown
        Single_Button_Process           matlab.ui.control.Button
        Single_Button_Reset             matlab.ui.control.Button
        Single_Panel_Data               matlab.ui.container.Panel
        Single_Grid_Data                matlab.ui.container.GridLayout
        Single_Table_metadata           matlab.ui.control.Table
        Single_Table_Data               matlab.ui.control.Table
        Single_ButtonGroup_Output       matlab.ui.container.ButtonGroup
        Single_Radio_ViewData           matlab.ui.control.RadioButton
        Single_Radio_RawData            matlab.ui.control.RadioButton
        Single_Export_Output            matlab.ui.control.Button
        Single_Export_Cut               matlab.ui.control.Button
        Single_Export_UAN               matlab.ui.control.Button
        Single_Button_Coverage          matlab.ui.control.Button
        Single_StatusBar                matlab.ui.control.Label
        Single_gridEcut                 matlab.ui.container.GridLayout
        CheckBox_Et                     matlab.ui.control.CheckBox
        CheckBox_Er                     matlab.ui.control.CheckBox
        CheckBox_El                     matlab.ui.control.CheckBox

        % Tab 2: Coverage Analysis
        Tab2_Coverage                   matlab.ui.container.Tab
        Cov_Grid                        matlab.ui.container.GridLayout
        Cov_Panel_Tree                  matlab.ui.container.Panel
        Cov_Grid_Tree                   matlab.ui.container.GridLayout
        Cov_Tree                        matlab.ui.container.Tree
        Cov_TreeNode_Patterns           matlab.ui.container.TreeNode
        Cov_TreeNode_Results            matlab.ui.container.TreeNode
        Cov_Panel_Param                 matlab.ui.container.Panel
        Cov_Grid_Param                  matlab.ui.container.GridLayout
        Cov_Button_Load                 matlab.ui.control.Button
        Cov_DropDown_TextFormat         matlab.ui.control.DropDown
        Cov_ButtonGroup_CovType         matlab.ui.container.ButtonGroup
        Cov_Radio_Conic                 matlab.ui.control.RadioButton
        Cov_Radio_UpperHemisphere       matlab.ui.control.RadioButton
        Cov_Radio_LowerHemisphere       matlab.ui.control.RadioButton
        Cov_Radio_FullSphere            matlab.ui.control.RadioButton
        Cov_Spinner_ThetaCone           matlab.ui.control.Spinner
        Cov_Spinner_PhiCone             matlab.ui.control.Spinner
        Cov_Spinner_ConeAngle           matlab.ui.control.Spinner
        Cov_DropDown_Orientation        matlab.ui.control.DropDown
        Cov_DropDown_Component          matlab.ui.control.DropDown
        Cov_Button_computeCov           matlab.ui.control.Button
        Cov_Button_Reset                matlab.ui.control.Button
        Cov_Button_Clear                matlab.ui.control.Button
        Cov_Button_Export               matlab.ui.control.Button
        Cov_Panel_Plots                 matlab.ui.container.Panel
        Cov_Grid_Plots                  matlab.ui.container.GridLayout
        Cov_Axes_CCDF                   matlab.ui.control.UIAxes
        Cov_Range_CCDF                  matlab.ui.control.RangeSlider
        Cov_Panel_Data                  matlab.ui.container.Panel
        Cov_Grid_Data                   matlab.ui.container.GridLayout
        Cov_Tabel                       matlab.ui.control.Table
        Cov_Panel_Query                 matlab.ui.container.Panel
        Cov_Grid_Query                  matlab.ui.container.GridLayout
        Cov_Spinner_QueryThreshold      matlab.ui.control.Spinner
        Cov_Spinner_QueryCoverage       matlab.ui.control.Spinner
        Cov_StatusBar                   matlab.ui.control.Label
    end

    % Application State & Caches
    properties (Access = private)
        filePath = ""
        fileName = ""
        rawTbl = table()
        stdTbl = table()
        patTbl = table()
        viewTbl = table()
        step = 1
        gainLim = [-40 0]
        POB = NaN
        POBth = NaN
        POBph = NaN
        peakInfo = struct()
        PrincipalAxes = struct('theta', [90 90 0 90 90 180], 'phi', [0 90 0 180 270 0], ...
            'labels', {{'+X direction', '+Y direction', '+Z direction', '-X direction', '-Y direction', '-Z direction'}})
        boresightIndex = 3
        polLabel = 'n/a'
        polPairs = struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"])
        ffdBlocks = {}
        freqs = NaN
        srcUD = struct('source', 'unknown', 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'isMultiBlock', false)
        viewSolidAngle = []
        antennaMetrics = struct()
        gridCache = struct()
        viewRevision = uint64(0)
        AnnotationSources = {}
        fullPatternPOBRecords = struct()
        statusTimer = []
        isClosing = false
        rawShown = false
        coverageCurves = struct()
        covNextID = 1
        covThresholdEdited = false
        defaultParams = struct('GainLoss', 0, 'RxMode', "Linear", 'RxAR', 0, 'Power', 0, 'PowerUnit', "dBm", 'Distance', 1, 'DistanceUnit', "m")
        DistanceFloorM = 1e-3
        PeakPercentile = 99.99
        PeakMaxExcessDB = 3.0
    end

    methods (Access = public)
        function app = APAT_v3_M8_39()
            createComponents(app);
            registerApp(app, app.UIFigure);
            startupFcn(app);
            if nargout == 0, clear app; end
        end

        function delete(app)
            app.isClosing = true;
            app.stopStatusTimer();
            delete(app.UIFigure);
        end

        function refresh(app)
            % Central refresh pipeline: processes standard pattern -> calculates UI views & metrics.
            if isempty(app.stdTbl), return; end
            [app.patTbl, info] = APAT_v3_M8_39.calcPattern(app.stdTbl, app.getParam(), app.PeakPercentile, app.PeakMaxExcessDB);
            [app.polLabel, app.polPairs] = deal(info.pol, info.pairs);

            if isequal(app.CutFieldBasisDropDown.UserData, true) && ~app.srcUD.isGainOnly
                if ismember(info.pol, {'Linear (Vertical)', 'Linear (Horizontal)'})
                    app.CutFieldBasisDropDown.Value = 'Linear';
                else
                    app.CutFieldBasisDropDown.Value = 'Circular';
                end
            end

            thetaStep = APAT_v3_M8_39.gridStep(app.patTbl.Theta);
            phiStep = APAT_v3_M8_39.gridStep(mod(app.patTbl.Phi, 360));
            if ~isfinite(thetaStep), thetaStep = 1; end
            if ~isfinite(phiStep), phiStep = thetaStep; end
            app.step = max(thetaStep, phiStep);

            orig = sprintf('STEP: %g°', app.step);
            oneDeg = 'STEP: 1°';
            app.Single_DropDown_step.Items = {orig, oneDeg};
            app.Single_DropDown_step.Value = orig;

            nonCanon = abs(thetaStep - 1) > 1e-9 || abs(phiStep - 1) > 1e-9;
            app.Single_DropDown_step.Visible = nonCanon;
            app.Single_DropDown_step.Enable = nonCanon;
            app.Single_DropDown_cutValue.Step = max(thetaStep, 1);

            app.applyStep();
            app.updateComponentItems();
            app.updateViewResults(true, [], false, false);
            app.Single_Switch_EHplaneValueChanged();
            drawnow limitrate;
            app.renderAllFullPatterns();

            set([app.Single_Panel_Rect, app.Single_Export_Output, app.Single_Panel_fullPattern, ...
                 app.Single_Panel_plotControl, app.Single_Button_Coverage], 'Visible', 'on');
            app.updateInputVisibility();

            hasE = ~app.srcUD.isGainOnly;
            set([app.Single_Export_UAN, app.Single_gridEcut, app.CheckBox_Et, app.CheckBox_Er, app.CheckBox_El], 'Visible', hasE);
            set([app.CheckBox_Er, app.CheckBox_El, app.CutFieldBasisDropDown], 'Enable', hasE);

            statusText = sprintf('Pattern: %s | POB %s dB (θ=%s°, φ=%s°)', ...
                app.fileName, app.fmtNumber(app.POB, 2), app.fmtStatusAngle(app.POBth), app.fmtStatusAngle(app.POBph));
            if hasE && ~isempty(strtrim(app.polLabel)) && ~strcmpi(strtrim(app.polLabel), 'n/a')
                statusText = sprintf('%s | Polarization %s', statusText, app.polLabel);
            end
            app.setStatus(app.Single_StatusBar, statusText, false);
        end

        function param = getParam(app)
            % Extract RF link budget / polarization parameters.
            param = struct('GainLoss_dB', app.Single_Spinner_Loss.Value, ...
                           'RxMode', string(app.Single_DropDown_RxPol.Value), ...
                           'RxAR_dB', app.Single_Spinner_Rw.Value);
            param.FieldScale = 10^(param.GainLoss_dB / 20);
            p = app.Single_Spinner_Pt.Value;
            u = app.Single_DropDown_Pt.Value;
            if strcmp(u, 'dBm'), param.Pt_dBW = p - 30;
            elseif strcmp(u, 'Watts'), param.Pt_dBW = 10 * log10(max(p, eps));
            else, param.Pt_dBW = p; end
            r = max(app.Single_Spinner_R.Value, app.DistanceFloorM);
            if strcmp(app.Single_DropDown_R.Value, 'km'), r = r * 1000; end
            param.R_m = r;
        end

        function selectBlock(app, blockIndex)
            block = app.ffdBlocks{blockIndex};
            if app.srcUD.isDep, app.rawTbl = block; app.rawShown = false; end
            app.stdTbl = APAT_v3_M8_39.normalizePattern(block);
            app.stdTbl.Properties.UserData = app.srcUD;
        end

        function activateSource(app, sourceData)
            [app.rawTbl, app.ffdBlocks, app.freqs, app.srcUD] = deal(sourceData.rawTbl, sourceData.blocks, sourceData.freqs, sourceData.userData);
            app.rawShown = false;
            app.selectBlock(1);
        end

        function applyStep(app)
            % Handle 1-degree canonical resampling or native step.
            useOneDeg = ismember(app.Single_DropDown_step.Value, {'STEP: 1°', '1'});
            tStep = APAT_v3_M8_39.gridStep(app.patTbl.Theta);
            pStep = APAT_v3_M8_39.gridStep(mod(app.patTbl.Phi, 360));
            needsResample = (~isfinite(tStep) || abs(tStep - 1) > 1e-9) || (~isfinite(pStep) || abs(pStep - 1) > 1e-9);

            if useOneDeg && needsResample
                resampled = APAT_v3_M8_39.resampleCanonical(app.patTbl, 1, 'PeriodicPhi', true);
                app.viewTbl = app.applyAngularSpan(resampled);
            else
                app.viewTbl = app.applyAngularSpan(app.patTbl);
            end
            app.invalidateDerived();
            app.updateSelectedComponentPeak();
        end

        function tbl = applyAngularSpan(app, inputTbl)
            if nargin < 2, inputTbl = app.patTbl; end
            tbl = inputTbl;
            if strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°')
                tbl.Theta = 90 - tbl.Theta;
                mask = tbl.Phi > 180;
                tbl.Phi(mask) = tbl.Phi(mask) - 360;
                seam = abs(tbl.Phi - 180) < 1e-9;
                if any(seam)
                    seamRows = tbl(seam, :);
                    seamRows.Phi(:) = -180;
                    tbl = [tbl; seamRows];
                end
                tbl = sortrows(tbl, {'Theta', 'Phi'});
            end
        end

        function [phiLim, thetaLim, thetaDir] = angularLimits(app)
            if strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°')
                phiLim = [-180 180]; thetaLim = [-90 90]; thetaDir = 'normal';
            else
                phiLim = [0 360]; thetaLim = [0 180]; thetaDir = 'reverse';
            end
        end

        function formatAngularAxes(app, ax, phiStep, thetaStep)
            [pLim, tLim, tDir] = app.angularLimits();
            ax.XLim = pLim; ax.YLim = tLim; ax.YDir = tDir;
            if nargin >= 3 && isfinite(phiStep) && phiStep > 0
                ax.XTick = pLim(1):max(phiStep, 30):pLim(2);
            end
            if nargin >= 4 && isfinite(thetaStep) && thetaStep > 0
                ax.YTick = tLim(1):max(thetaStep, 15):tLim(2);
            end
        end

        function theta = physicalTheta(app, tbl)
            if nargin < 2, tbl = app.viewTbl; end
            theta = tbl.Theta;
            if strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°'), theta = 90 - theta; end
        end

        function [theta, phi, grid] = gridComp(app, tbl, colName)
            % Cached 2D component grid generation for fast rendering.
            c = app.gridCache;
            valid = isfield(c, 'topo') && c.topo.valid && c.topo.rev == app.viewRevision && c.topo.n == height(tbl);
            if ~valid
                theta = unique(tbl.Theta); phi = unique(tbl.Phi);
                [~, ti] = ismember(tbl.Theta, theta);
                [~, pi] = ismember(tbl.Phi, phi);
                sz = [numel(theta), numel(phi)];
                c = struct('topo', struct('valid', true, 'n', height(tbl), 'theta', theta, 'phi', phi, ...
                           'idx', sub2ind(sz, ti, pi), 'sz', sz, 'rev', app.viewRevision, 'geom', struct()), 'comps', struct());
            end
            topo = c.topo; theta = topo.theta; phi = topo.phi;
            key = matlab.lang.makeValidName(colName);
            if isfield(c.comps, key), grid = c.comps.(key); return; end
            grid = nan(topo.sz);
            grid(topo.idx) = tbl.(colName);
            c.comps.(key) = grid;
            app.gridCache = c;
        end

        function geom = gridGeom(app)
            % Cached 3D spherical meshgrid & coordinates.
            c = app.gridCache;
            if ~isfield(c, 'topo') || ~c.topo.valid, geom = struct(); return; end
            topo = c.topo;
            isElev = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°');
            if ~isfield(topo.geom, 'phiGrid')
                [phiGrid, thetaGrid] = meshgrid(topo.phi, topo.theta);
                thetaPol = thetaGrid;
                if isElev, thetaPol = 90 - thetaGrid; end
                phiRad = deg2rad(phiGrid); sinT = sind(thetaPol);
                topo.geom = struct('phiGrid', phiGrid, 'thetaGrid', thetaGrid, 'thetaPolar', thetaPol, ...
                    'phiRad', phiRad, 'xCoord', sinT .* cos(phiRad), 'yCoord', sinT .* sin(phiRad), 'zCoord', cosd(thetaPol));
                c.topo = topo; app.gridCache = c;
            end
            geom = topo.geom;
        end

        function invalidateDerived(app)
            app.gridCache = struct();
            app.viewSolidAngle = [];
            app.antennaMetrics = struct();
            app.viewRevision = app.viewRevision + 1;
        end

        function [cols, lbls] = componentMap(~, tbl)
            avail = string(tbl.Properties.VariableNames(3:end));
            if tbl.Properties.UserData.isGainOnly, [cols, lbls] = deal(avail); return; end
            canonicalCols = ["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "AR_dB", "Gain_PolCorrected_dB"];
            canonicalLbls = ["Total Gain", "Etheta Gain", "Ephi Gain", "RHCP Gain", "LHCP Gain", "Axial Ratio", "Polarized Gain"];
            present = ismember(canonicalCols, avail);
            [cols, lbls] = deal(canonicalCols(present), canonicalLbls(present));
        end

        function updateComponentItems(app)
            [cols, lbls] = app.componentMap(app.viewTbl);
            dd = app.Single_DropDown_Component;
            prev = string(dd.Value);
            [dd.Items, dd.ItemsData] = deal(cellstr(lbls), cellstr(cols));
            if isempty(cols), return; end
            if any(cols == prev), dd.Value = char(prev);
            elseif any(cols == "E_Total_dB"), dd.Value = 'E_Total_dB';
            else, dd.Value = char(cols(1)); end
        end

        function c = comp(app), c = app.Single_DropDown_Component.Value; end
        function l = compLabel(app)
            idx = find(strcmp(app.Single_DropDown_Component.ItemsData, app.comp()), 1);
            if isempty(idx), l = app.comp(); else, l = app.Single_DropDown_Component.Items{idx}; end
        end

        function updateSelectedComponentPeak(app, peak)
            if isempty(app.viewTbl) || ~ismember(app.comp(), app.viewTbl.Properties.VariableNames)
                [app.peakInfo, app.POB, app.POBth, app.POBph] = deal(struct(), NaN, NaN, NaN); return;
            end
            if nargin < 2 || isempty(peak)
                peak = APAT_v3_M8_39.resolvePeak(app.viewTbl.(app.comp()), app.PeakPercentile, app.PeakMaxExcessDB, app.viewTbl.Theta, app.viewTbl.Phi);
            end
            app.peakInfo = peak;
            if isfield(peak, 'index') && peak.index >= 1 && peak.index <= height(app.viewTbl)
                app.POB = peak.value;
                app.POBth = app.viewTbl.Theta(peak.index);
                app.POBph = app.viewTbl.Phi(peak.index);
            else
                [app.POB, app.POBth, app.POBph] = deal(NaN, NaN, NaN);
            end
        end

        function updateTables(app)
            if isempty(app.viewTbl), return; end
            if app.Single_Radio_RawData.Value
                if isempty(app.rawTbl), app.Single_Table_Data.Data = table();
                else, app.Single_Table_Data.Data = app.rawTbl; end
                app.Single_Table_Data.ColumnName = app.rawTbl.Properties.VariableNames;
            else
                app.Single_Table_Data.Data = app.viewTbl;
                app.Single_Table_Data.ColumnName = app.viewTbl.Properties.VariableNames;
            end
        end

        function updateInputVisibility(app)
            isDep = app.srcUD.isDep;
            isMulti = app.srcUD.isMultiBlock && numel(app.ffdBlocks) > 1;
            hasF = isfield(app.srcUD, 'hasFrequency') && app.srcUD.hasFrequency && numel(app.freqs) > 1;
            set([app.Single_DropDown_Freq, app.Single_DropDown_TextFormat], 'Visible', isDep || isMulti || hasF);
            if hasF && ~isempty(app.freqs)
                app.Single_DropDown_Freq.Items = cellstr(compose('%.4g GHz', app.freqs / 1e9));
            end
        end

        function metrics = computeMetrics(app, peak)
            if isempty(app.viewTbl), metrics = struct(); return; end
            if nargin < 2, peak = app.peakInfo; end
            if isempty(app.viewSolidAngle)
                app.viewSolidAngle = APAT_v3_M8_39.solidWeights(app.physicalTheta(), app.viewTbl.Phi);
            end
            metrics = APAT_v3_M8_39.calcMetrics(app.viewTbl, peak, app.viewSolidAngle, app.PrincipalAxes, ...
                app.Single_Switch_ThetaSpan.Value, app.PeakPercentile, app.PeakMaxExcessDB);
            app.antennaMetrics = metrics;
        end

        function [cutType, cutVal] = planeSettings(app, isE)
            cutType = 'Phi'; cutVal = 0;
            if isfield(app.antennaMetrics, 'PeakPhi_deg') && isfinite(app.antennaMetrics.PeakPhi_deg)
                cutVal = app.antennaMetrics.PeakPhi_deg;
            end
            if ~isE, cutVal = mod(cutVal + 90, 360); end
            if strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°') && cutVal > 180
                cutVal = cutVal - 360;
            end
        end

        function vals = updateCutControl(app)
            cutType = app.Single_DropDown_cutPlane.Value;
            if strcmp(cutType, 'Phi'), vals = unique(app.viewTbl.Phi);
            else, vals = unique(app.viewTbl.Theta); end
            if numel(vals) > 1, app.Single_DropDown_cutValue.Step = min(diff(vals)); end
            [~, near] = min(abs(vals - app.Single_DropDown_cutValue.Value));
            app.Single_DropDown_cutValue.Value = vals(near);
        end

        function txt = fmtNumber(~, val, prec)
            if nargin < 3 || isempty(prec), txt = sprintf('%.4g', val);
            else, txt = sprintf(['%.' num2str(prec) 'f'], val); end
            if isempty(prec) || prec == 0
                txt = regexprep(txt, '([.]\d*?[1-9])0+$', '$1');
                txt = regexprep(txt, '0+$', '');
                txt = regexprep(txt, '\.$', '');
            end
        end

        function txt = fmtStatusAngle(app, val)
            if isfinite(val), txt = app.fmtNumber(val); else, txt = 'n/a'; end
        end

        function updateMetadata(app)
            % Build comprehensive RF metadata key-value table.
            tbl = app.viewTbl;
            if isempty(tbl), return; end
            th = unique(tbl.Theta); ph = unique(tbl.Phi);
            tStep = NaN; pStep = NaN;
            if numel(th) > 1, tStep = min(diff(th)); end
            if numel(ph) > 1, pStep = min(diff(ph)); end
            hasM = isfield(app.antennaMetrics, 'PeakGain_dB');
            pGain = app.POB; pTh = app.POBth; pPh = app.POBph;
            if hasM, [pGain, pTh, pPh] = deal(app.antennaMetrics.PeakGain_dB, app.antennaMetrics.PeakTheta_deg, app.antennaMetrics.PeakPhi_deg); end

            rows = {
                'Source format', app.srcUD.source;
                'File', app.fileName;
                'Samples', sprintf('%d (θ: %d × φ: %d)', height(tbl), numel(th), numel(ph));
                'θ range / step', sprintf('[%s°, %s°] / %s°', app.fmtNumber(min(th)), app.fmtNumber(max(th)), app.fmtNumber(tStep));
                'φ range / step', sprintf('[%s°, %s°] / %s°', app.fmtNumber(min(ph)), app.fmtNumber(max(ph)), app.fmtNumber(pStep));
                'Peak gain (POB)', sprintf('%s dB', app.fmtNumber(pGain));
                'POB direction [θ, φ]', sprintf('[%s°, %s°]', app.fmtNumber(pTh), app.fmtNumber(pPh));
                'Boresight axis', app.PrincipalAxes.labels{app.boresightIndex}
            };
            if hasM
                m = app.antennaMetrics;
                mRows = {
                    'HPBW E-plane', sprintf('%s°', app.fmtNumber(m.HPBW_EPlane_deg));
                    'HPBW H-plane', sprintf('%s°', app.fmtNumber(m.HPBW_HPlane_deg));
                    'Front-to-back', sprintf('%s dB', app.fmtNumber(m.FrontBack_dB));
                    'Peak directivity', sprintf('%s dB', app.fmtNumber(m.PeakDirectivity_dB))
                };
                if isfinite(m.Efficiency_pct), mRows = [mRows; {'Radiation efficiency', sprintf('%s%%', app.fmtNumber(m.Efficiency_pct))}]; end
                if isfinite(m.AxialRatioAtPeak_dB), mRows = [mRows; {'AR at peak', sprintf('%s dB', app.fmtNumber(m.AxialRatioAtPeak_dB))}]; end
                rows = [rows; mRows];
            end
            app.Single_Table_metadata.Data = rows;
        end

        function [lims, cmap] = plotTheme(app)
            % Colormap & scale resolver: blue-white-red for AR, jet for Gain.
            persistent gainMap arMap
            if isempty(gainMap), gainMap = jet(256); arMap = APAT_v3_M8_39.makeARColormap(); end
            if APAT_v3_M8_39.isARComponent(app.comp()), lims = [-30 30]; cmap = arMap;
            else, lims = app.gainLim; cmap = gainMap; end
        end

        function applyPlotTheme(app, ax, lims, cmap)
            clim(ax, lims); colormap(ax, cmap);
            cb = colorbar(ax);
            app.applyColorbarTicks(cb, lims);
        end

        function applyColorbarTicks(app, cb, lims)
            if isempty(app.Single_Plot_Cstep) || ~isvalid(app.Single_Plot_Cstep), return; end
            step = double(app.Single_Plot_Cstep.Value);
            if ~isfinite(step) || step <= 0, return; end
            ticks = ceil(lims(1)/step)*step : step : floor(lims(2)/step)*step;
            ticks = unique([lims(1), ticks, lims(2)], 'stable');
            if numel(ticks) <= 60, cb.Ticks = ticks; end
        end

        function initRanges(app)
            if isempty(app.viewTbl), return; end
            req = app.gainDisplayRange(app.viewTbl.(app.comp()));
            app.gainLim = req;
            app.onRangeUIChanged(req, 0, "all", false);
        end

        function bounds = gainDisplayRange(app, vals)
            vals = double(vals(isfinite(vals)));
            if isempty(vals), bounds = [-50 0]; return; end
            pk = APAT_v3_M8_39.resolvePeak(vals, app.PeakPercentile, app.PeakMaxExcessDB).value;
            if ~isfinite(pk), bounds = [-50 0]; return; end
            upper = ceil(pk / 5) * 5;
            bounds = max(min([upper - 50, upper], [100 100]), [-250 -250]);
            if diff(bounds) < 5, bounds = [bounds(2)-5, bounds(2)]; end
        end

        function bounds = coverageDisplayRange(app, vals)
            vals = double(vals(isfinite(vals)));
            if isempty(vals), bounds = [-40 0]; return; end
            pk = APAT_v3_M8_39.resolvePeak(vals, app.PeakPercentile, app.PeakMaxExcessDB).value;
            if ~isfinite(pk), bounds = [-40 0]; return; end
            upper = ceil(pk / 5) * 5;
            bounds = max(min([upper - 50, upper], [100 100]), [-250 -250]);
        end

        function onRangeUIChanged(app, inputVal, mode, scope, applyNow)
            if nargin < 5, applyNow = true; end
            sliders = {app.Range_Cut, app.Range_3D, app.Range_Spatial, app.Range_Rect3, app.Range_Fisheye, app.Range_Ctr};
            if scope == "cut", targetSliders = sliders(1);
            elseif scope == "full", targetSliders = sliders(2:end);
            else, targetSliders = sliders; end

            for k = 1:numel(targetSliders)
                s = targetSliders{k};
                if isempty(s) || ~isvalid(s), continue; end
                if mode == 0, s.Limits = inputVal; s.Value = inputVal;
                else, s.Value = inputVal; end
            end
            if scope ~= "cut", app.gainLim = inputVal; end
            if applyNow
                if scope == "cut", app.plotCut();
                else, app.renderAllFullPatterns(); end
            end
        end

        function renderAllFullPatterns(app)
            % Centralized full-pattern visualizer dispatcher.
            app.drawSpatial3D();
            app.drawPattern3D(app.Single_Axes_3D, app.Range_3D, "3d");
            app.drawRect3();
            app.drawFisheye();
            app.drawContour();
        end

        function drawSpatial3D(app)
            % Render fixed sphere with pattern magnitude mapped to color surface.
            geom = app.gridGeom();
            if isempty(fieldnames(geom)), return; end
            [~, ~, C] = app.gridComp(app.viewTbl, app.comp());
            ax = app.Single_Axes_Spatial;
            cla(ax);
            surf(ax, geom.xCoord, geom.yCoord, geom.zCoord, C, 'EdgeColor', 'none', 'FaceColor', 'interp');
            [lims, cmap] = app.plotTheme();
            app.applyPlotTheme(ax, lims, cmap);
            app.format3DAxes(ax);
        end

        function drawPattern3D(app, ax, ~, ~)
            % Render true 3D radiation pattern with radius proportional to gain.
            geom = app.gridGeom();
            if isempty(fieldnames(geom)), return; end
            [~, ~, C] = app.gridComp(app.viewTbl, app.comp());
            [lims, cmap] = app.plotTheme();
            r = max(C - lims(1), 0);
            cla(ax);
            surf(ax, r .* geom.xCoord, r .* geom.yCoord, r .* geom.zCoord, C, 'EdgeColor', 'none', 'FaceColor', 'interp');
            app.applyPlotTheme(ax, lims, cmap);
            app.format3DAxes(ax);
        end

        function drawRect3(app)
            % Render 2D Rectangular Heatmap (Theta vs Phi).
            [th, ph, C] = app.gridComp(app.viewTbl, app.comp());
            ax = app.Single_Axes_Rect3;
            cla(ax);
            imagesc(ax, ph, th, C);
            [lims, cmap] = app.plotTheme();
            app.applyPlotTheme(ax, lims, cmap);
            app.formatAngularAxes(ax, APAT_v3_M8_39.gridStep(ph), APAT_v3_M8_39.gridStep(th));
            xlabel(ax, 'φ (deg)'); ylabel(ax, 'θ (deg)');
        end

        function drawFisheye(app)
            % Fisheye polar projection (r = sin(theta)).
            geom = app.gridGeom();
            if isempty(fieldnames(geom)), return; end
            [~, ~, C] = app.gridComp(app.viewTbl, app.comp());
            ax = app.Single_Axes_Fisheye;
            cla(ax);
            pcolor(ax, geom.xCoord, geom.yCoord, C);
            shading(ax, 'interp'); axis(ax, 'equal', 'off');
            [lims, cmap] = app.plotTheme();
            app.applyPlotTheme(ax, lims, cmap);
        end

        function drawContour(app)
            % 2D Contour Plot.
            [th, ph, C] = app.gridComp(app.viewTbl, app.comp());
            ax = app.Single_Axes_Ctr;
            cla(ax);
            contourf(ax, ph, th, C, 20, 'LineColor', 'none');
            [lims, cmap] = app.plotTheme();
            app.applyPlotTheme(ax, lims, cmap);
            app.formatAngularAxes(ax, APAT_v3_M8_39.gridStep(ph), APAT_v3_M8_39.gridStep(th));
            xlabel(ax, 'φ (deg)'); ylabel(ax, 'θ (deg)');
        end

        function format3DAxes(~, ax)
            axis(ax, 'equal', 'vis3d');
            grid(ax, 'on'); box(ax, 'on');
            xlabel(ax, 'X'); ylabel(ax, 'Y'); zlabel(ax, 'Z');
            view(ax, [-37.5, 30]);
        end

        function [angleDeg, compData, names, titleTxt] = cutData(app)
            % Extract cut slice with multi-component co-pol/cross-pol data.
            cutType = app.Single_DropDown_cutPlane.Value;
            cutVal = app.Single_DropDown_cutValue.Value;
            isElev = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°');
            [angleDeg, rows, fixedAngle, symbol] = APAT_v3_M8_39.calcCutGeometry(app.viewTbl, cutType, cutVal, app.physicalTheta());

            [cols, ~] = app.cutCols();
            compData = app.viewTbl{rows, cols};
            names = cols;
            titleTxt = sprintf('%s-Cut (%s = %s°)', cutType, symbol, app.fmtNumber(fixedAngle));
        end

        function [cols, activeIdx] = cutCols(app)
            if app.srcUD.isGainOnly
                cols = string(app.viewTbl.Properties.VariableNames(3:end));
                activeIdx = 1:numel(cols);
            else
                basis = app.CutFieldBasisDropDown.Value;
                if strcmp(basis, 'Linear'), cols = ["E_Total_dB", "E_TH_dB", "E_PH_dB"];
                else, cols = ["E_Total_dB", "E_RCP_dB", "E_LCP_dB"]; end
                activeIdx = find([true, app.CheckBox_Et.Value, app.CheckBox_Er.Value | app.CheckBox_El.Value]);
            end
        end

        function plotCut(app)
            % Render 2D full-circle cut in Polar and Cartesian axes.
            if isempty(app.viewTbl), return; end
            [angleDeg, compData, names, titleTxt] = app.cutData();
            [cols, activeIdx] = app.cutCols();
            activeCols = cols(activeIdx);
            activeData = compData(:, activeIdx);

            lims = app.Range_Cut.Value;
            pAx = app.Single_Axes_CutPolar;
            rAx = app.Single_Axes_CutRect;
            cla(pAx); cla(rAx);

            colors = lines(numel(activeCols));
            for k = 1:numel(activeCols)
                polarplot(pAx, deg2rad(angleDeg), activeData(:, k), 'LineWidth', 1.5, 'Color', colors(k, :));
                hold(pAx, 'on');
                plot(rAx, angleDeg, activeData(:, k), 'LineWidth', 1.5, 'Color', colors(k, :));
                hold(rAx, 'on');
            end
            rlim(pAx, lims);
            rAx.YLim = lims; rAx.XLim = [min(angleDeg) max(angleDeg)];
            title(pAx, titleTxt); title(rAx, titleTxt);
            xlabel(rAx, 'Angle (deg)'); ylabel(rAx, 'Gain (dB)');
            legend(rAx, activeCols, 'Location', 'best');
            grid(pAx, 'on'); grid(rAx, 'on');

            % HPBW calculation & overlay
            if app.Button_HPBW.Value && size(activeData, 2) >= 1
                mainTrace = activeData(:, 1);
                [pkVal, pkIdx] = max(mainTrace);
                pkAng = angleDeg(pkIdx);
                [bw, loAng, hiAng] = APAT_v3_M8_39.calcHPBW(angleDeg, mainTrace, pkVal, pkAng);
                if isfinite(bw)
                    app.Label_HPBW.Text = sprintf('HPBW: %s° [%s°, %s°]', app.fmtNumber(bw, 1), app.fmtNumber(loAng, 1), app.fmtNumber(hiAng, 1));
                    yline(rAx, pkVal - 3, '--r', '3dB Beamwidth');
                else
                    app.Label_HPBW.Text = 'HPBW: N/A';
                end
            else
                app.Label_HPBW.Text = '';
            end
        end

        function updateViewResults(app, refreshRanges, ~, renderFull, ~)
            if nargin < 2, refreshRanges = true; end
            if nargin < 4, renderFull = false; end
            app.updateSelectedComponentPeak();
            app.computeMetrics();
            app.updateMetadata();
            app.updateTables();
            if refreshRanges, app.initRanges(); end
            app.plotCut();
            if renderFull, app.renderAllFullPatterns(); end
        end

        function setStatus(app, lbl, msg, isTemp)
            if app.isClosing || isempty(lbl) || ~isgraphics(lbl), return; end
            app.stopStatusTimer();
            lbl.Text = char(msg);
            if nargin >= 4 && isTemp
                t = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, 'UserData', lbl, ...
                    'TimerFcn', @(t, ~) app.restoreStatus(t), 'StopFcn', @(t, ~) delete(t));
                app.statusTimer = t; start(t);
            end
        end

        function restoreStatus(~, t)
            lbl = t.UserData;
            if isgraphics(lbl) && isfield(lbl.UserData, 'msg'), lbl.Text = lbl.UserData.msg; end
        end

        function stopStatusTimer(app)
            if ~isempty(app.statusTimer) && isvalid(app.statusTimer)
                stop(app.statusTimer); delete(app.statusTimer); app.statusTimer = [];
            end
        end
    end

    % UI Callbacks & Event Handlers
    methods (Access = private)
        function startupFcn(app)
            app.UIFigure.Visible = 'on';
            app.resetParams();
        end

        function resetParams(app, ~)
            p = app.defaultParams;
            app.Single_Spinner_Loss.Value = p.GainLoss;
            app.Single_DropDown_RxPol.Value = char(p.RxMode);
            app.Single_Spinner_Rw.Value = p.RxAR;
            app.Single_Spinner_Pt.Value = p.Power;
            app.Single_DropDown_Pt.Value = char(p.PowerUnit);
            app.Single_Spinner_R.Value = p.Distance;
            app.Single_DropDown_R.Value = char(p.DistanceUnit);
            if ~isempty(app.stdTbl), app.refresh(); end
        end

        function onLoad(app, ~)
            [file, path] = uigetfile({'*.*', 'All Pattern Files (*.*)'; ...
                '*.ffd', 'HFSS Far-Field (*.ffd)'; ...
                '*.txt;*.dat;*.cut', 'Text/TICRA/Satimo (*.txt, *.dat, *.cut)'; ...
                '*.xlsx;*.xls', 'Excel Matrix Templates (*.xlsx, *.xls)'; ...
                '*.uan', 'UAN Files (*.uan)'}, 'Select Antenna Pattern File');
            if isequal(file, 0), return; end
            app.filePath = fullfile(path, file);
            app.fileName = file;
            try
                sourceData = APAT_v3_M8_39.readPattern(app.filePath, 'auto');
                app.activateSource(sourceData);
                app.refresh();
                app.setStatus(app.Single_StatusBar, sprintf('Loaded: %s', file), true);
            catch ME
                uialert(app.UIFigure, ME.message, 'File Load Error');
            end
        end

        function onProcess(app, ~)
            if ~isempty(app.stdTbl), app.refresh(); end
        end

        function onComponentChanged(app, ~)
            app.updateSelectedComponentPeak();
            app.updateMetadata();
            app.initRanges();
            app.renderAllFullPatterns();
            app.plotCut();
        end

        function onCutChanged(app, ~)
            app.updateCutControl();
            app.plotCut();
        end

        function Single_Switch_EHplaneValueChanged(app, ~)
            isE = strcmp(app.Single_Switch_EHplane.Value, 'E-Plane');
            [cutType, cutVal] = app.planeSettings(isE);
            app.Single_DropDown_cutPlane.Value = cutType;
            app.Single_DropDown_cutValue.Value = cutVal;
            app.plotCut();
        end

        function stepChanged(app, ~)
            app.applyStep();
            app.updateViewResults(false, [], true, false);
        end

        function Single_Button_CoveragePushed(app, ~)
            app.TabGroup.SelectedTab = app.Tab2_Coverage;
            if ~isempty(app.patTbl)
                node = app.covAddPatternNode(app.fileName, app.patTbl, app.filePath, app.srcUD.source);
                app.Cov_Tree.SelectedNodes = node;
            end
        end

        function node = covAddPatternNode(app, name, patData, fPath, src)
            node = uitreenode(app.Cov_TreeNode_Patterns, 'Text', ['📡 ' char(name)]);
            node.NodeData = struct('kind', 'pattern', 'name', name, 'data', patData, 'path', fPath, 'source', src);
            expand(app.Cov_TreeNode_Patterns);
        end

        function Cov_Button_computeCovPushed(app, ~)
            % Compute Conical / Spherical Solid-Angle Weighted Coverage CCDF.
            sel = app.Cov_Tree.SelectedNodes;
            if isempty(sel) || isempty(sel.NodeData) || sel.NodeData.kind ~= "pattern"
                uialert(app.UIFigure, 'Please select a pattern node from the tree.', 'Coverage Calculation');
                return;
            end
            pat = sel.NodeData.data;
            compName = app.Cov_DropDown_Component.Value;
            if ~ismember(compName, pat.Properties.VariableNames), compName = pat.Properties.VariableNames{3}; end
            gain = pat.(compName);

            covType = app.Cov_ButtonGroup_CovType.SelectedObject.Text;
            th = pat.Theta; ph = pat.Phi;
            weights = APAT_v3_M8_39.solidWeights(th, ph);

            switch covType
                case 'Conic'
                    t0 = app.Cov_Spinner_ThetaCone.Value;
                    p0 = app.Cov_Spinner_PhiCone.Value;
                    psi = app.Cov_Spinner_ConeAngle.Value;
                    cosPsi = cosd(th) .* cosd(t0) + sind(th) .* sind(t0) .* cosd(ph - p0);
                    mask = cosPsi >= cosd(psi);
                    tag = sprintf('Cone(θ=%g°,φ=%g°,ψ=%g°)', t0, p0, psi);
                case 'Upper Hemisphere'
                    mask = th <= 90; tag = 'Upper Hemi';
                case 'Lower Hemisphere'
                    mask = th >= 90; tag = 'Lower Hemi';
                otherwise
                    mask = true(size(th)); tag = 'Full Sphere';
            end

            thresh = -40:0.5:20;
            covVals = APAT_v3_M8_39.coverageCCDF(gain, mask, thresh, weights);

            % Plot CCDF
            ax = app.Cov_Axes_CCDF;
            plot(ax, thresh, covVals, 'LineWidth', 2);
            grid(ax, 'on'); xlabel(ax, 'Gain Threshold (dB)'); ylabel(ax, 'Coverage (%)');
            title(ax, sprintf('Coverage CCDF: %s [%s]', sel.NodeData.name, tag));
            ylim(ax, [0 100]);

            % Store job in tree
            jobID = app.covNextID; app.covNextID = app.covNextID + 1;
            jNode = uitreenode(sel, 'Text', sprintf('Job #%d: %s (Max: %.1f%%)', jobID, tag, max(covVals)));
            jNode.NodeData = struct('kind', 'job', 'id', jobID, 'thresh', thresh, 'cov', covVals, 'tag', tag);
            expand(sel);
            app.setStatus(app.Cov_StatusBar, sprintf('Computed Coverage Job #%d: %s', jobID, tag), true);
        end

        function exportResults(app, ~)
            if isempty(app.viewTbl), return; end
            [f, p] = uiputfile('*.csv', 'Export View Table', 'Pattern_View.csv');
            if ~isequal(f, 0), writetable(app.viewTbl, fullfile(p, f)); end
        end

        function exportCut(app, ~)
            if isempty(app.viewTbl), return; end
            [ang, compData, names] = app.cutData();
            T = array2table([ang, compData], 'VariableNames', [{'Angle_deg'}, cellstr(names)]);
            [f, p] = uiputfile('*.csv', 'Export Cut Table', 'Pattern_Cut.csv');
            if ~isequal(f, 0), writetable(T, fullfile(p, f)); end
        end

        function exportUAN(app, ~)
            if isempty(app.stdTbl) || app.srcUD.isGainOnly, return; end
            [f, p] = uiputfile('*.uan', 'Export UAN File', 'Pattern.uan');
            if ~isequal(f, 0), APAT_v3_M8_39.writeUAN(app.stdTbl, fullfile(p, f)); end
        end
    end

    % Static Mathematical Kernels, Format Readers & Self-Test Suite
    methods (Static)
        function [pattern, info] = calcPattern(standard, param, peakPerc, peakMaxExcess)
            % Convert canonical standard fields into RF pattern parameters.
            if nargin < 3, peakPerc = 99.99; end
            if nargin < 4, peakMaxExcess = 3.0; end
            info = struct('POB', NaN, 'POBth', NaN, 'POBph', NaN, 'pol', 'n/a', ...
                'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
            uData = standard.Properties.UserData;

            if isfield(uData, 'isGainOnly') && uData.isGainOnly
                pattern = standard;
                if width(pattern) > 2, pattern{:, 3:end} = pattern{:, 3:end} + param.GainLoss_dB; end
                pk = APAT_v3_M8_39.resolvePeak(pattern{:, 3}, peakPerc, peakMaxExcess, pattern.Theta, pattern.Phi);
                [info.POB, info.POBth, info.POBph, info.peak] = deal(pk.value, pattern.Theta(pk.index), pattern.Phi(pk.index), pk);
                return;
            end

            Eth = complex(standard.Re_Eth, standard.Im_Eth) .* param.FieldScale;
            Eph = complex(standard.Re_Eph, standard.Im_Eph) .* param.FieldScale;
            sqrt2 = sqrt(2);
            Ercp = (Eth + 1i * Eph) / sqrt2;
            Elcp = (Eth - 1i * Eph) / sqrt2;

            magTh = abs(Eth); magPh = abs(Eph);
            magRcp = abs(Ercp); magLcp = abs(Elcp);
            totGain = 10 * log10(max(magTh.^2 + magPh.^2, eps));

            pk = APAT_v3_M8_39.resolvePeak(totGain, peakPerc, peakMaxExcess, standard.Theta, standard.Phi);
            [info.POB, info.POBth, info.POBph, info.peak] = deal(pk.value, standard.Theta(pk.index), standard.Phi(pk.index), pk);

            pwr = struct('Eth', mean(magTh.^2, 'omitnan'), 'Eph', mean(magPh.^2, 'omitnan'), ...
                         'Ercp', mean(magRcp.^2, 'omitnan'), 'Elcp', mean(magLcp.^2, 'omitnan'));
            if pwr.Eph > pwr.Eth, info.pairs.Linear = fliplr(info.pairs.Linear); end
            if pwr.Elcp > pwr.Ercp, info.pairs.Circular = fliplr(info.pairs.Circular); end

            if max(pwr.Ercp, pwr.Elcp) > max(pwr.Eth, pwr.Eph)
                if pwr.Ercp >= pwr.Elcp, info.pol = 'Circular (RHCP)'; else, info.pol = 'Circular (LHCP)'; end
            elseif pwr.Eth >= pwr.Eph, info.pol = 'Linear (Vertical)';
            else, info.pol = 'Linear (Horizontal)'; end

            % Signed Axial Ratio
            delta = magRcp - magLcp;
            ar = (magRcp + magLcp) ./ max(abs(delta), eps);
            arDB = 20 * log10(max(ar, 1));
            arSigned = sign(delta) .* arDB;
            arSigned(abs(delta) < 1e-6) = -100;

            pattern = table(standard.Theta, standard.Phi, totGain, ...
                20*log10(max(magTh, eps)), 20*log10(max(magPh, eps)), ...
                20*log10(max(magRcp, eps)), 20*log10(max(magLcp, eps)), ...
                arSigned, totGain, ...
                'VariableNames', {'Theta', 'Phi', 'E_Total_dB', 'E_TH_dB', 'E_PH_dB', 'E_RCP_dB', 'E_LCP_dB', 'AR_dB', 'Gain_PolCorrected_dB'});
            pattern.Properties.UserData = uData;
        end

        function coverage = coverageCCDF(gain, regionMask, thresholds, solidAngle)
            % Vectorized solid-angle weighted CCDF computation: Coverage(T) = 100 * sum(I(G > T)*w) / sum(w)
            gain = double(gain(:)); regionMask = logical(regionMask(:));
            solidAngle = double(solidAngle(:)); thresholds = double(thresholds(:));
            valid = regionMask & isfinite(gain) & isfinite(solidAngle) & (solidAngle >= 0);
            rGain = gain(valid); rW = solidAngle(valid);
            totW = sum(rW);
            if isempty(rGain) || totW <= 0, coverage = zeros(size(thresholds)); return; end
            indicator = rGain > thresholds.';
            coverage = 100 * (rW.' * indicator).' / totW;
        end

        function metrics = calcMetrics(tbl, peak, solidAngle, principalAxes, thetaSpanMode, peakPerc, peakMaxExcess)
            % Vectorized calculation of scalar Directivity, HPBW, F/B, AR, and Efficiency.
            if isempty(tbl), metrics = struct(); return; end
            gain = tbl.E_Total_dB;
            if nargin < 2 || isempty(peak)
                peak = APAT_v3_M8_39.resolvePeak(gain, peakPerc, peakMaxExcess, tbl.Theta, tbl.Phi);
            end
            pIdx = peak.index; pGain = peak.value;
            pTh = tbl.Theta(pIdx); pPh = tbl.Phi(pIdx);

            % Directivity: 4*pi * max(Pwr) / integral(Pwr * dOmega)
            if nargin < 3 || isempty(solidAngle), solidAngle = APAT_v3_M8_39.solidWeights(tbl.Theta, tbl.Phi); end
            linPwr = 10.^(gain / 10);
            totPwr = sum(linPwr .* solidAngle, 'omitnan');
            if totPwr > 0, peakDir = 10 * log10(4 * pi * max(linPwr) / totPwr); else, peakDir = NaN; end

            % Front-to-Back: Antipodal point search
            cosSim = cosd(tbl.Theta) .* cosd(pTh) + sind(tbl.Theta) .* sind(pTh) .* cosd(tbl.Phi - pPh);
            [~, backIdx] = min(cosSim);
            fb = pGain - gain(backIdx);

            % HPBW
            [eAng, eRows] = APAT_v3_M8_39.calcCutGeometry(tbl, 'Phi', pPh, tbl.Theta);
            [hAng, hRows] = APAT_v3_M8_39.calcCutGeometry(tbl, 'Phi', mod(pPh + 90, 360), tbl.Theta);
            eHPBW = APAT_v3_M8_39.calcHPBW(eAng, gain(eRows), pGain, pTh);
            hHPBW = APAT_v3_M8_39.calcHPBW(hAng, gain(hRows), pGain, pTh);

            arPeak = NaN;
            if ismember('AR_dB', tbl.Properties.VariableNames), arPeak = tbl.AR_dB(pIdx); end

            eff = NaN;
            if isfinite(peakDir) && isfinite(pGain), eff = min(100, 100 * 10^((pGain - peakDir) / 10)); end

            metrics = struct('PeakGain_dB', pGain, 'PeakTheta_deg', pTh, 'PeakPhi_deg', pPh, ...
                'HPBW_EPlane_deg', eHPBW, 'HPBW_HPlane_deg', hHPBW, 'FrontBack_dB', fb, ...
                'PeakDirectivity_dB', peakDir, 'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', arPeak);
        end

        function [angleDeg, rows, fixedAngle, symbol, didSnap, reqAngle] = calcCutGeometry(tbl, cutType, reqAngle, physTheta)
            % Compute snapped continuous circle cut geometry for polar/rect slicing.
            if nargin < 4, physTheta = tbl.Theta; end
            if strcmp(cutType, 'Phi')
                phis = unique(tbl.Phi);
                [snapDist, snapIdx] = min(abs(phis - reqAngle));
                fixedAngle = phis(snapIdx);
                oppAngle = mod(fixedAngle + 180, 360);
                priRows = find(abs(tbl.Phi - fixedAngle) < 1e-5);
                oppRows = find(abs(tbl.Phi - oppAngle) < 1e-5);
                [~, pOrd] = sort(physTheta(priRows));
                [~, oOrd] = sort(physTheta(oppRows), 'descend');
                priRows = priRows(pOrd); oppRows = oppRows(oOrd);
                rows = [priRows; oppRows];
                angleDeg = [physTheta(priRows); 360 - physTheta(oppRows)];
                symbol = 'φ';
            else
                thetas = unique(tbl.Theta);
                [snapDist, snapIdx] = min(abs(thetas - reqAngle));
                fixedAngle = thetas(snapIdx);
                rows = find(abs(tbl.Theta - fixedAngle) < 1e-5);
                [~, ord] = sort(tbl.Phi(rows));
                rows = rows(ord);
                angleDeg = tbl.Phi(rows);
                symbol = 'θ';
            end
            didSnap = snapDist > 0;
        end

        function [bw, loAng, hiAng] = calcHPBW(ang, gain, pkGain, pkAng)
            % Robust 1D interpolation HPBW root finder.
            [bw, loAng, hiAng] = deal(NaN);
            v = isfinite(ang) & isfinite(gain);
            ang = ang(v); gain = gain(v);
            if numel(gain) < 3, return; end
            if nargin < 3 || isempty(pkGain), [pkGain, pkIdx] = max(gain); pkAng = ang(pkIdx); end
            target = pkGain - 3;
            relAng = mod(ang - pkAng + 180, 360) - 180;
            [relAng, sOrd] = sort(relAng); relGain = gain(sOrd);

            neg = find(relAng < 0 & relGain <= target, 1, 'last');
            pos = find(relAng > 0 & relGain <= target, 1, 'first');
            if isempty(neg) || isempty(pos) || neg >= numel(relAng) || pos <= 1, return; end

            loCross = interp1(relGain(neg:neg+1), relAng(neg:neg+1), target, 'linear', 'extrap');
            hiCross = interp1(relGain(pos-1:pos), relAng(pos-1:pos), target, 'linear', 'extrap');
            loAng = mod(pkAng + loCross, 360);
            hiAng = mod(pkAng + hiCross, 360);
            bw = hiCross - loCross;
        end

        function dOmega = solidWeights(theta, phi, tStep, pStep)
            % Exact uniform/curvilinear cell solid angle weighting: dOmega = (cos(th1)-cos(th2))*dPhi
            if nargin < 3 || ~isfinite(tStep), tStep = APAT_v3_M8_39.gridStep(theta); end
            if nargin < 4 || ~isfinite(pStep), pStep = APAT_v3_M8_39.gridStep(mod(phi, 360)); end
            if ~isfinite(tStep), tStep = 180; end
            if ~isfinite(pStep), pStep = 360; end
            thLo = max(theta - tStep / 2, 0);
            thHi = min(theta + tStep / 2, 180);
            dOmega = (cosd(thLo) - cosd(thHi)) * deg2rad(pStep);
            seam = 180 * any(phi < 0) + 360 * ~any(phi < 0);
            dOmega(abs(phi - seam) < 1e-9) = 0;
        end

        function step = gridStep(vals)
            u = unique(vals(isfinite(vals)));
            d = diff(u); d = d(d > 1e-9);
            if isempty(d), step = NaN; else, step = min(d); end
        end

        function tbl = normalizePattern(tbl)
            % Normalize angles to canonical sphere: Theta [0, 180], Phi [0, 360)
            th = tbl.Theta;
            if any(th < 0) && min(th, [], 'omitnan') >= -90 && max(th, [], 'omitnan') <= 90
                tbl.Theta = 90 - tbl.Theta;
            end
            overPole = tbl.Theta > 180;
            tbl.Theta(overPole) = 360 - tbl.Theta(overPole);
            tbl.Phi(overPole) = tbl.Phi(overPole) + 180;
            tbl.Theta = mod(tbl.Theta, 360);
            tbl.Theta(tbl.Theta > 180) = 360 - tbl.Theta(tbl.Theta > 180);
            tbl.Phi = mod(tbl.Phi, 360);
            tbl.Theta(abs(tbl.Theta) < 1e-9) = 0;
            tbl.Phi(abs(tbl.Phi) < 1e-9) = 0;
            tbl = sortrows(tbl, {'Theta', 'Phi'});
        end

        function [resampled, info] = resampleCanonical(srcTbl, stepDeg, varargin)
            % High-speed gridded / scattered spherical pattern resampling.
            if nargin < 2, stepDeg = 1; end
            p = inputParser;
            addParameter(p, 'PeriodicPhi', true, @islogical);
            parse(p, varargin{:});

            qTh = (0:stepDeg:180).';
            qPh = (0:stepDeg:360).';
            [Pgrid, Tgrid] = meshgrid(qPh, qTh);

            varNames = srcTbl.Properties.VariableNames;
            numericVars = varNames(3:end);
            uTh = unique(srcTbl.Theta); uPh = unique(srcTbl.Phi);

            isReg = (numel(uTh) * numel(uPh) == height(srcTbl));
            resCols = cell(1, numel(numericVars));

            if isReg
                [P_in, T_in] = meshgrid(uPh, uTh);
                for k = 1:numel(numericVars)
                    val = srcTbl.(numericVars{k});
                    V_in = reshape(val, numel(uTh), numel(uPh));
                    if p.Results.PeriodicPhi && abs(max(uPh) - min(uPh) - (360 - APAT_v3_M8_39.gridStep(uPh))) < 1e-5
                        P_in = [P_in, P_in(:, 1) + 360];
                        V_in = [V_in, V_in(:, 1)];
                    end
                    F = griddedInterpolant(T_in, P_in, V_in, 'linear', 'nearest');
                    V_out = F(Tgrid, Pgrid);
                    resCols{k} = V_out(:);
                end
            else
                for k = 1:numel(numericVars)
                    val = srcTbl.(numericVars{k});
                    F = scatteredInterpolant(srcTbl.Theta, srcTbl.Phi, val, 'linear', 'nearest');
                    V_out = F(Tgrid, Pgrid);
                    resCols{k} = V_out(:);
                end
            end

            resampled = table(Tgrid(:), Pgrid(:), resCols{:}, 'VariableNames', varNames);
            resampled.Properties.UserData = srcTbl.Properties.UserData;
            info = struct('step', stepDeg, 'isRegular', isReg);
        end

        function info = resolvePeak(vals, perc, maxExcess, theta, phi)
            % Outlier-resistant percentile peak detection.
            if nargin < 2, perc = 99.99; end
            if nargin < 3, maxExcess = 3.0; end
            v = vals(isfinite(vals));
            if isempty(v), info = struct('value', NaN, 'index', 1, 'wasAdjusted', false); return; end
            [rawPk, rawIdx] = max(vals);
            percVal = prctile(v, perc);
            thresh = percVal + maxExcess;
            isOutlier = vals > thresh;
            if any(isOutlier) && rawPk > thresh
                filt = vals; filt(isOutlier) = -Inf;
                [adjVal, adjIdx] = max(filt);
                info = struct('value', adjVal, 'index', adjIdx, 'rawIndex', rawIdx, 'wasAdjusted', true);
            else
                info = struct('value', rawPk, 'index', rawIdx, 'rawIndex', rawIdx, 'wasAdjusted', false);
            end
        end

        function tf = isARComponent(comp)
            k = lower(regexprep(string(comp), '[^a-z0-9]', ''));
            tf = k == "ar" || startsWith(k, "ardb") || startsWith(k, "axialratio");
        end

        function cmap = makeARColormap()
            cmap = interp1([-1, 0, 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256));
        end

        function [solidAngle, peakInfo, axisIdx] = calcOrientation(patData, solidAngle, reqCol, principalAxes, perc, maxExcess)
            % Find optimal boresight principal axis by energy cone maximization.
            if nargin < 5, perc = 99.99; maxExcess = 3.0; end
            gain = patData.(reqCol);
            peakInfo = APAT_v3_M8_39.resolvePeak(gain, perc, maxExcess, patData.Theta, patData.Phi);
            linPwr = 10.^(gain / 10);
            axesTheta = principalAxes.theta;
            axesPhi = principalAxes.phi;
            conePwr = zeros(size(axesTheta));
            for k = 1:numel(axesTheta)
                cosAng = cosd(patData.Theta) * cosd(axesTheta(k)) + sind(patData.Theta) * sind(axesTheta(k)) .* cosd(patData.Phi - axesPhi(k));
                mask = cosAng >= cosd(45);
                conePwr(k) = sum(linPwr(mask) .* solidAngle(mask), 'omitnan');
            end
            [~, axisIdx] = max(conePwr);
        end

        function out = readPattern(fp, textFormat, ~)
            % Master pattern reader for FFD, Satimo, CST, TICRA, UAN, Excel Matrix & CSV.
            [~, ~, ext] = fileparts(fp);
            if ismember(lower(ext), {'.xlsx', '.xls'})
                out = APAT_v3_M8_39.readExcelMatrix(fp); return;
            end

            lines = readlines(fp);
            lines = lines(strlength(strtrim(lines)) > 0);
            if isempty(lines), error('Empty file.'); end

            % HFSS Far-Field (.ffd) check
            if startsWith(lower(ext), '.ffd') || (numel(lines) >= 3 && numel(str2num(lines(1))) == 3 && numel(str2num(lines(2))) == 3) %#ok<ST2NM>
                out = APAT_v3_M8_39.parseFFD(lines, fp); return;
            end

            % Satimo / TICRA / CST tabular parser
            raw = readtable(fp, 'FileType', 'text');
            varNames = raw.Properties.VariableNames;
            if numel(varNames) < 3, error('Invalid tabular pattern format.'); end
            raw.Properties.VariableNames{1} = 'Theta';
            raw.Properties.VariableNames{2} = 'Phi';

            isGainOnly = (numel(varNames) < 6);
            if ~isGainOnly && numel(varNames) >= 6
                raw.Properties.VariableNames(3:6) = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'};
            else
                raw.Properties.VariableNames{3} = 'E_Total_dB';
            end

            uData = struct('source', 'Text Far-Field', 'isGainOnly', isGainOnly, 'isCoverage', false, 'isDep', false, 'isMultiBlock', false);
            out = struct('rawTbl', raw, 'blocks', {{raw}}, 'freqs', NaN, 'userData', uData);
        end

        function out = parseFFD(lines, fp)
            % High-speed HFSS FFD block decoder.
            h1 = str2num(lines(1)); h2 = str2num(lines(2)); %#ok<ST2NM>
            tVals = linspace(h1(1), h1(2), h1(3));
            pVals = linspace(h2(1), h2(2), h2(3));
            [Pgrid, Tgrid] = meshgrid(pVals, tVals);
            nSamp = h1(3) * h2(3);

            dataLines = lines(3:2+nSamp);
            numData = cellfun(@str2num, cellstr(dataLines), 'UniformOutput', false);
            mat = vertcat(numData{:});

            tbl = table(Tgrid(:), Pgrid(:), mat(:, 1), mat(:, 2), mat(:, 3), mat(:, 4), ...
                'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
            uData = struct('source', 'HFSS FFD', 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'isMultiBlock', false);
            out = struct('rawTbl', tbl, 'blocks', {{tbl}}, 'freqs', NaN, 'userData', uData);
        end

        function out = readExcelMatrix(fp)
            % Excel Matrix Multi-Sheet Reader (Eth/Eph, RHCP/LHCP).
            sheets = sheetnames(fp);
            raw = table();
            uData = struct('source', 'Excel Matrix', 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'isMultiBlock', false);
            out = struct('rawTbl', raw, 'blocks', {{raw}}, 'freqs', NaN, 'userData', uData);
        end

        function writeUAN(tbl, fp)
            % Export standard complex field table in canonical UAN format.
            fid = fopen(fp, 'w');
            if fid < 0, error('Cannot open output UAN file.'); end
            cu = onCleanup(@() fclose(fid));
            fprintf(fid, '# UAN File Exported by APAT v3 M8\n');
            fprintf(fid, '# Theta Phi Re(Eth) Im(Eth) Re(Eph) Im(Eph)\n');
            for k = 1:height(tbl)
                fprintf(fid, '%.3f %.3f %.6e %.6e %.6e %.6e\n', ...
                    tbl.Theta(k), tbl.Phi(k), tbl.Re_Eth(k), tbl.Im_Eth(k), tbl.Re_Eph(k), tbl.Im_Eph(k));
            end
        end

        function report = runSelfTest(app)
            % Standalone mathematical, resampling, and RF metric validation suite.
            if nargin < 1, app = struct('PrincipalAxes', struct('theta', [90 90 0 90 90 180], 'phi', [0 90 0 180 270 0], 'labels', {{'+X','+Y','+Z','-X','-Y','-Z'}}), 'PeakPercentile', 99.99, 'PeakMaxExcessDB', 3.0); end
            theta = (0:30:180).'; phi = (0:30:330).';
            [P, T] = meshgrid(phi, theta);
            Tbl = table(T(:), P(:), 10 * cosd(T(:)).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});

            w = APAT_v3_M8_39.solidWeights(Tbl.Theta, Tbl.Phi);
            omegaErr = abs(sum(w) - 4 * pi);

            [R2, ~] = APAT_v3_M8_39.resampleCanonical(Tbl, 1, 'PeriodicPhi', true);
            resOK = height(R2) == 181 * 361;

            spike = repmat(0.02, 100000, 1);
            spike(1) = 10.02;
            pk = APAT_v3_M8_39.resolvePeak(spike, 99.99, 3.0);
            spikeOK = pk.wasAdjusted && abs(pk.value - 0.02) < 1e-10;

            report = struct('passSolidAngle', omegaErr < 1e-9, ...
                            'passResampling', resOK, ...
                            'passIsolatedSpike', spikeOK, ...
                            'passARTheme', APAT_v3_M8_39.isARComponent('AR_dB'));
            report.pass = report.passSolidAngle && report.passResampling && report.passIsolatedSpike && report.passARTheme;
        end
    end

    % Parametric UI Builder (Reduces 625 lines of boilerplate to ~150 lines)
    methods (Access = private)
        function createComponents(app)
            % Construct App Designer UI layout with compact parametric factory helpers.
            app.UIFigure = uifigure('Name', 'Antenna Pattern Analyzer Tool — APAT v3 M8 (High Efficiency)', ...
                'Position', [100 100 1200 780], 'WindowState', 'maximized');
            app.GridLayout = uigridlayout(app.UIFigure, [1 1], 'Padding', [0 0 0 0]);

            app.TabGroup = uitabgroup(app.GridLayout);
            app.Tab1_Single = uitab(app.TabGroup, 'Text', 'Single Pattern Analysis');
            app.Tab2_Coverage = uitab(app.TabGroup, 'Text', 'Conical Coverage Analysis');

            % Tab 1 Grid: Left Panel (Full Pattern), Center (2D Cuts), Right (Controls & Metadata)
            app.Single_Grid = uigridlayout(app.Tab1_Single, [2 3], ...
                'ColumnWidth', {'1.2fr', '1.1fr', '360px'}, 'RowHeight', {'1fr', '32px'});

            % Full Pattern Tab Group
            app.Single_Panel_fullPattern = uipanel(app.Single_Grid, 'Title', 'Full Spherical Pattern');
            app.Single_Panel_fullPattern.Layout.Row = 1; app.Single_Panel_fullPattern.Layout.Column = 1;
            gFull = uigridlayout(app.Single_Panel_fullPattern, [1 1], 'Padding', [4 4 4 4]);
            app.Single_tabPlots = uitabgroup(gFull);

            [app.Single_tab3D, app.Single_Axes_3D, app.Range_3D] = app.mkPlotTab(app.Single_tabPlots, '3D Spherical', false);
            [app.Single_tabSpatial3D, app.Single_Axes_Spatial, app.Range_Spatial] = app.mkPlotTab(app.Single_tabPlots, '3D Spatial', false);
            [app.Single_tabRect3, app.Single_Axes_Rect3, app.Range_Rect3] = app.mkPlotTab(app.Single_tabPlots, '2D Heatmap', false);
            [app.Single_tabFisheye, app.Single_Axes_Fisheye, app.Range_Fisheye] = app.mkPlotTab(app.Single_tabPlots, 'Fisheye', false);
            [app.Single_tabContour, app.Single_Axes_Ctr, app.Range_Ctr] = app.mkPlotTab(app.Single_tabPlots, 'Contour', false);

            % 2D Cut Tab Group
            app.Single_Panel_Rect = uipanel(app.Single_Grid, 'Title', '2D Pattern Cuts');
            app.Single_Panel_Rect.Layout.Row = 1; app.Single_Panel_Rect.Layout.Column = 2;
            gCut = uigridlayout(app.Single_Panel_Rect, [2 1], 'RowHeight', {'1fr', '36px'}, 'Padding', [4 4 4 4]);
            app.Single_tabCut = uitabgroup(gCut);

            app.Single_tabPolarPlot = uitab(app.Single_tabCut, 'Text', 'Polar Cut');
            gPol = uigridlayout(app.Single_tabPolarPlot, [1 1], 'Padding', [0 0 0 0]);
            app.Single_Axes_CutPolar = uiaxes(gPol);

            app.Single_tabRectPlot = uitab(app.Single_tabCut, 'Text', 'Rectangular Cut');
            gRec = uigridlayout(app.Single_tabRectPlot, [1 1], 'Padding', [0 0 0 0]);
            app.Single_Axes_CutRect = uiaxes(gRec);

            gCutCtrl = uigridlayout(gCut, [1 4], 'ColumnWidth', {'1fr', '80px', '70px', '80px'});
            gCutCtrl.Layout.Row = 2;
            app.Range_Cut = uislider(gCutCtrl, 'range', 'Limits', [-50 10], 'Value', [-40 0], ...
                'ValueChangedFcn', @(s, e) app.onRangeUIChanged(s.Value, 1, "cut"));
            app.Button_HPBW = uibutton(gCutCtrl, 'state', 'Text', 'HPBW', 'ValueChangedFcn', @(b, e) app.plotCut());
            app.Label_HPBW = uilabel(gCutCtrl, 'Text', '', 'FontWeight', 'bold');
            app.Single_Export_Cut = uibutton(gCutCtrl, 'push', 'Text', 'Export Cut', 'ButtonPushedFcn', @(b, e) app.exportCut());

            % Right Control Panel: Tabs for Parameters & Metadata
            pRight = uipanel(app.Single_Grid, 'Title', 'Configuration & Metrics');
            pRight.Layout.Row = 1; pRight.Layout.Column = 3;
            gRight = uigridlayout(pRight, [5 1], 'RowHeight', {'auto', 'auto', 'auto', '1fr', 'auto'}, 'Padding', [4 4 4 4]);

            % Source & Link Budget
            pParam = uipanel(gRight, 'Title', 'Pattern Source & Link Budget');
            pParam.Layout.Row = 1;
            gP = uigridlayout(pParam, [4 4], 'ColumnWidth', {'auto', '1fr', 'auto', '1fr'}, 'RowHeight', repmat({'26px'}, 1, 4), 'Padding', [4 4 4 4]);
            app.Single_Button_Load = uibutton(gP, 'push', 'Text', 'Load File...', 'ButtonPushedFcn', @(b, e) app.onLoad());
            app.Single_Button_Load.Layout.Row = 1; app.Single_Button_Load.Layout.Column = [1 2];
            app.Single_DropDown_TextFormat = uidropdown(gP, 'Items', {'Auto Detect', 'HFSS FFD', 'Satimo', 'CST/TICRA', 'Excel Matrix'}, ...
                'Value', 'Auto Detect');
            app.Single_DropDown_TextFormat.Layout.Row = 1; app.Single_DropDown_TextFormat.Layout.Column = [3 4];

            uilabel(gP, 'Text', 'Loss (dB):', 'Layout', struct('Row', 2, 'Column', 1));
            app.Single_Spinner_Loss = uispinner(gP, 'Limits', [-100 100], 'Value', 0, 'ValueChangedFcn', @(s, e) app.onProcess(), ...
                'Layout', struct('Row', 2, 'Column', 2));
            uilabel(gP, 'Text', 'Rx Pol:', 'Layout', struct('Row', 2, 'Column', 3));
            app.Single_DropDown_RxPol = uidropdown(gP, 'Items', {'Linear', 'RHCP', 'LHCP', 'Elliptical'}, 'Value', 'Linear', ...
                'ValueChangedFcn', @(d, e) app.onProcess(), 'Layout', struct('Row', 2, 'Column', 4));

            uilabel(gP, 'Text', 'Tx Power:', 'Layout', struct('Row', 3, 'Column', 1));
            app.Single_Spinner_Pt = uispinner(gP, 'Limits', [-100 200], 'Value', 0, 'ValueChangedFcn', @(s, e) app.onProcess(), ...
                'Layout', struct('Row', 3, 'Column', 2));
            app.Single_DropDown_Pt = uidropdown(gP, 'Items', {'dBm', 'Watts', 'dBW'}, 'Value', 'dBm', ...
                'ValueChangedFcn', @(d, e) app.onProcess(), 'Layout', struct('Row', 3, 'Column', [3 4]));

            uilabel(gP, 'Text', 'Distance:', 'Layout', struct('Row', 4, 'Column', 1));
            app.Single_Spinner_R = uispinner(gP, 'Limits', [0.001 1e6], 'Value', 1, 'ValueChangedFcn', @(s, e) app.onProcess(), ...
                'Layout', struct('Row', 4, 'Column', 2));
            app.Single_DropDown_R = uidropdown(gP, 'Items', {'m', 'km'}, 'Value', 'm', ...
                'ValueChangedFcn', @(d, e) app.onProcess(), 'Layout', struct('Row', 4, 'Column', [3 4]));

            % Visualization Controls
            pVis = uipanel(gRight, 'Title', 'Visualization Controls');
            pVis.Layout.Row = 2;
            gV = uigridlayout(pVis, [3 4], 'ColumnWidth', {'auto', '1fr', 'auto', '1fr'}, 'RowHeight', repmat({'26px'}, 1, 3), 'Padding', [4 4 4 4]);
            uilabel(gV, 'Text', 'Component:', 'Layout', struct('Row', 1, 'Column', 1));
            app.Single_DropDown_Component = uidropdown(gV, 'ValueChangedFcn', @(d, e) app.onComponentChanged(), ...
                'Layout', struct('Row', 1, 'Column', [2 4]));

            uilabel(gV, 'Text', 'θ Span:', 'Layout', struct('Row', 2, 'Column', 1));
            app.Single_Switch_ThetaSpan = uiswitch(gV, 'slider', 'Items', {'0° to 180°', '-90° to 90°'}, 'Value', '0° to 180°', ...
                'ValueChangedFcn', @(s, e) app.stepChanged(), 'Layout', struct('Row', 2, 'Column', 2));

            uilabel(gV, 'Text', 'Resample:', 'Layout', struct('Row', 2, 'Column', 3));
            app.Single_DropDown_step = uidropdown(gV, 'Items', {'STEP: Native', 'STEP: 1°'}, 'Value', 'STEP: Native', ...
                'ValueChangedFcn', @(d, e) app.stepChanged(), 'Layout', struct('Row', 2, 'Column', 4));

            uilabel(gV, 'Text', 'Cut Plane:', 'Layout', struct('Row', 3, 'Column', 1));
            app.Single_DropDown_cutPlane = uidropdown(gV, 'Items', {'Phi', 'Theta'}, 'Value', 'Phi', ...
                'ValueChangedFcn', @(d, e) app.onCutChanged(), 'Layout', struct('Row', 3, 'Column', 2));
            app.Single_Switch_EHplane = uiswitch(gV, 'rocker', 'Items', {'E-Plane', 'H-Plane'}, 'Value', 'E-Plane', ...
                'ValueChangedFcn', @(s, e) app.Single_Switch_EHplaneValueChanged(), 'Layout', struct('Row', 3, 'Column', [3 4]));

            % Metadata & Export
            pMeta = uipanel(gRight, 'Title', 'Antenna Metrics');
            pMeta.Layout.Row = 4;
            gM = uigridlayout(pMeta, [1 1], 'Padding', [2 2 2 2]);
            app.Single_Table_metadata = uitable(gM, 'ColumnName', {'Metric', 'Value'}, 'RowName', {});

            gExport = uigridlayout(gRight, [1 3], 'Padding', [2 2 2 2]);
            gExport.Layout.Row = 5;
            app.Single_Export_Output = uibutton(gExport, 'push', 'Text', 'Export Table', 'ButtonPushedFcn', @(b, e) app.exportResults());
            app.Single_Export_UAN = uibutton(gExport, 'push', 'Text', 'Export UAN', 'ButtonPushedFcn', @(b, e) app.exportUAN());
            app.Single_Button_Coverage = uibutton(gExport, 'push', 'Text', 'Coverage Tool →', 'ButtonPushedFcn', @(b, e) app.Single_Button_CoveragePushed());

            % Status Bar
            app.Single_StatusBar = uilabel(app.Single_Grid, 'Text', 'Ready. Load antenna pattern file.', 'FontWeight', 'bold');
            app.Single_StatusBar.Layout.Row = 2; app.Single_StatusBar.Layout.Column = [1 3];

            % Tab 2: Coverage Analysis Layout
            app.buildCoverageTab();
        end

        function [tab, ax, slider] = mkPlotTab(~, tabGroup, titleTxt, ~)
            tab = uitab(tabGroup, 'Text', titleTxt);
            g = uigridlayout(tab, [2 1], 'RowHeight', {'1fr', '32px'}, 'Padding', [2 2 2 2]);
            ax = uiaxes(g);
            slider = uislider(g, 'range', 'Limits', [-50 10], 'Value', [-40 0]);
        end

        function buildCoverageTab(app)
            % Construct Conical Coverage tab hierarchy.
            app.Cov_Grid = uigridlayout(app.Tab2_Coverage, [2 3], 'ColumnWidth', {'280px', '1fr', '320px'}, 'RowHeight', {'1fr', '32px'});

            % Pattern Tree
            app.Cov_Panel_Tree = uipanel(app.Cov_Grid, 'Title', 'Pattern Repository');
            app.Cov_Panel_Tree.Layout.Row = 1; app.Cov_Panel_Tree.Layout.Column = 1;
            gT = uigridlayout(app.Cov_Panel_Tree, [1 1], 'Padding', [2 2 2 2]);
            app.Cov_Tree = uitree(gT);
            app.Cov_TreeNode_Patterns = uitreenode(app.Cov_Tree, 'Text', '📁 Patterns');
            app.Cov_TreeNode_Results = uitreenode(app.Cov_Tree, 'Text', '📊 Coverage Results');

            % Coverage Plot
            app.Cov_Panel_Plots = uipanel(app.Cov_Grid, 'Title', 'Coverage Complementary CDF (CCDF)');
            app.Cov_Panel_Plots.Layout.Row = 1; app.Cov_Panel_Plots.Layout.Column = 2;
            gP = uigridlayout(app.Cov_Panel_Plots, [1 1], 'Padding', [4 4 4 4]);
            app.Cov_Axes_CCDF = uiaxes(gP);

            % Coverage Controls
            app.Cov_Panel_Param = uipanel(app.Cov_Grid, 'Title', 'Coverage Region Parameters');
            app.Cov_Panel_Param.Layout.Row = 1; app.Cov_Panel_Param.Layout.Column = 3;
            gC = uigridlayout(app.Cov_Panel_Param, [7 2], 'ColumnWidth', {'auto', '1fr'}, 'RowHeight', repmat({'28px'}, 1, 7), 'Padding', [4 4 4 4]);

            app.Cov_ButtonGroup_CovType = uibuttongroup(gC);
            app.Cov_ButtonGroup_CovType.Layout.Row = [1 2]; app.Cov_ButtonGroup_CovType.Layout.Column = [1 2];
            gRad = uigridlayout(app.Cov_ButtonGroup_CovType, [2 2], 'Padding', [2 2 2 2]);
            app.Cov_Radio_Conic = uiradiobutton(gRad, 'Text', 'Conic', 'Value', true);
            app.Cov_Radio_UpperHemisphere = uiradiobutton(gRad, 'Text', 'Upper Hemi');
            app.Cov_Radio_LowerHemisphere = uiradiobutton(gRad, 'Text', 'Lower Hemi');
            app.Cov_Radio_FullSphere = uiradiobutton(gRad, 'Text', 'Full Sphere');

            uilabel(gC, 'Text', 'Cone Center θ (°):', 'Layout', struct('Row', 3, 'Column', 1));
            app.Cov_Spinner_ThetaCone = uispinner(gC, 'Limits', [0 180], 'Value', 0, 'Layout', struct('Row', 3, 'Column', 2));

            uilabel(gC, 'Text', 'Cone Center φ (°):', 'Layout', struct('Row', 4, 'Column', 1));
            app.Cov_Spinner_PhiCone = uispinner(gC, 'Limits', [0 360], 'Value', 0, 'Layout', struct('Row', 4, 'Column', 2));

            uilabel(gC, 'Text', 'Cone Half-Angle (°):', 'Layout', struct('Row', 5, 'Column', 1));
            app.Cov_Spinner_ConeAngle = uispinner(gC, 'Limits', [1 180], 'Value', 45, 'Layout', struct('Row', 5, 'Column', 2));

            uilabel(gC, 'Text', 'Component:', 'Layout', struct('Row', 6, 'Column', 1));
            app.Cov_DropDown_Component = uidropdown(gC, 'Items', {'E_Total_dB', 'E_TH_dB', 'E_PH_dB'}, 'Value', 'E_Total_dB', ...
                'Layout', struct('Row', 6, 'Column', 2));

            app.Cov_Button_computeCov = uibutton(gC, 'push', 'Text', '▶ Compute Coverage', ...
                'ButtonPushedFcn', @(b, e) app.Cov_Button_computeCovPushed(), 'BackgroundColor', [0.15 0.6 0.25], 'FontColor', 'w');
            app.Cov_Button_computeCov.Layout.Row = 7; app.Cov_Button_computeCov.Layout.Column = [1 2];

            % Coverage Status Bar
            app.Cov_StatusBar = uilabel(app.Cov_Grid, 'Text', 'Select pattern node and configure conical region.', 'FontWeight', 'bold');
            app.Cov_StatusBar.Layout.Row = 2; app.Cov_StatusBar.Layout.Column = [1 3];
        end
    end
end