classdef APAT_v3_M8_27 < matlab.apps.AppBase %1970-lines
% APAT v3 M8 — Antenna Pattern Analyzer Tool (concise re-architecture of M7.110_5).
%
%   Design pillars of M8
%   1. One handle registry (app.h) built by a declarative UI builder.
%   2. Physical-coordinate view model: every numeric service (peak, metrics,
%      orientation, coverage, cuts, UAN export) works on the canonical table
%      (theta 0..180, phi 0..360).  The selected display convention is
%      materialized exactly once into app.dispTbl for tables and plots.
%   3. Tag-based annotations: POB and HPBW markers are ordinary graphics
%      objects tagged 'APAT_POB' / 'APAT_HPBW'; visibility is a findall/set.
%   4. One guarded callback wrapper (app.cb) replaces per-callback try/catch.
%   5. Single implementations of shared numerics (cutGeometry, peakWindow,
%      solidWeights, resolvePeak, ...) used by both Main and Coverage tabs.

    properties (Access = public)
        UIFigure matlab.ui.Figure
        h struct = struct()                % UI handle registry
    end

    properties (GetAccess = public, SetAccess = private)
        isClosing logical = false
    end

    properties (Access = private)
        filePath char = ''
        fileName char = ''
        folderPath char = ''
        baseName char = ''
        rawTbl table                       % data as found in the file
        stdTbl table                       % canonical E-field / gain table of the active block
        patTbl table                       % processed pattern at native resolution
        viewTbl table                      % processed pattern at selected step (physical coordinates)
        dispTbl table                      % viewTbl in the selected display convention
        ffdBlocks cell = {}
        freqs double = NaN
        srcUD struct = struct()
        grid struct = struct()             % display-grid cache (topology, geometry, component grids)
        POB double = NaN
        POBth double = NaN
        POBph double = NaN
        polLabel char = 'n/a'
        polPairs struct = struct('Linear', ["E_TH","E_PH"], 'Circular', ["E_RCP","E_LCP"])
        boresightIndex double = 1
        peakInfo struct = struct()
        metrics struct = struct()
        viewSolidAngle double = []
        defaultParams struct = struct()
        gainLim double = [-40 10]          % authoritative non-AR colour scale
        cutLim double = [-40 10]
        full struct = struct([])           % full-pattern tab specs: name, tab, axes, slider, minSpin, maxSpin
        covRunID double = 0
        covPresetKey string = ""
        covPlotInit logical = false
        statusTimer = []
        operationDialog = []
        perfTracker = @(~) []
        filterStyles cell = {}
    end

    properties (Constant, Access = private)
        PrincipalAxes = struct('labels', {{'+Z','-Z','+X','-X','+Y','-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        ComponentNames = ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","AR_dB","Gain_PolCorrected_dB"]
        ComponentLabels = ["Total Gain","Etheta Gain","Ephi Gain","RHCP Gain","LHCP Gain","Axial Ratio","Polarized Gain"]
        HiddenOutputColumns = {'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'}
        TextFormats = struct('Items', {{'1: Gain Pattern','2: Etheta/Ephi — dB magnitude, phase','3: Etheta/Ephi — real, imaginary', ...
            '4: POL1=RCP, POL2=LCP — dB magnitude, phase','5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
            '6: POL1=RCP, POL2=LCP — real, imaginary','7: POL1=LCP, POL2=RCP — real, imaginary'}}, ...
            'ItemsData', {{'gain','linear_magphase','linear_reim','rcp_lcp_magphase','lcp_rcp_magphase','rcp_lcp_reim','lcp_rcp_reim'}})
        FileFilter = {'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage files'; '*.*', 'All files'}
        ExportFilter = {'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}
        PeakPercentile = 99.99
        PeakMaxExcessDB = 6
        DistanceFloorM = 1e-12
        DBRange = [-250 100]
        OneDegree = ['STEP: 1' char(176)]
        SignedPhi = '-180° to 180°'
        ElevationTheta = '-90° to 90°'
        ReleaseName = 'APAT v3 Milestone 8'
        ReleaseVersion = '3.0-M8'
    end

    %% ------------------------------------------------------------------ lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_27
            app.createComponents();
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @startupFcn);
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true;
            app.stopStatusTimer();
            if ~isempty(app.operationDialog) && isvalid(app.operationDialog), delete(app.operationDialog); end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end

        function f = cb(app, fcn)
            % Guarded callback: every UI event runs through one error path.
            f = @(src, evt) app.guard(fcn, src, evt);
        end
    end

    methods (Access = private)
        function guard(app, fcn, src, evt)
            try
                fcn(src, evt);
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled')
                    app.setStatus(app.h.status1, 'Operation cancelled by user.', true);
                else
                    app.showError(ME, 'APAT Error');
                end
            end
        end

        function startupFcn(app)
            H = app.h;
            fixedAxes = {H.axCtr, H.axRect, H.paxPattern, H.paxCut, H.ax3dSph, H.ax3dPol, H.ax3dRect};
            for k = 1:numel(fixedAxes)
                ax = fixedAxes{k}; enableDefaultInteractivity(ax);
                if isa(ax, 'matlab.graphics.axis.PolarAxes'), continue; end
                if k > 4, ax.Interactions = [rotateInteraction, dataTipInteraction]; else, ax.Interactions = [zoomInteraction, dataTipInteraction]; end
                app.attachContextMenu(ax);
            end
            app.cutLim = app.gainLim;
            set(H.covAxes, 'Box', 'on', 'Layer', 'top', 'YLim', [0 100]); hold(H.covAxes, 'on'); grid(H.covAxes, 'on');
            set([H.status1, H.covStatus], 'Text', 'Ready -- load an antenna pattern file to begin 🚀', 'UserData', 'Ready -- load an antenna pattern file to begin 🚀');
            app.defaultParams = app.getParam();
            app.setCoverageUI();
        end
    end

    %% ------------------------------------------------------------------ UI construction
    methods (Access = private)
        function c = add(app, name, c, row, col, varargin)
            % Register a component in app.h, place it in its grid and apply properties.
            if ~isempty(varargin), set(c, varargin{:}); end
            if ~isempty(row), c.Layout.Row = row; end
            if ~isempty(col), c.Layout.Column = col; end
            if ~isempty(name), app.h.(name) = c; end
        end

        function c = lbl(app, parent, text, row, col, varargin)
            c = app.add('', uilabel(parent), row, col, 'Text', text, 'HorizontalAlignment', 'right', varargin{:});
        end

        function createComponents(app)
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.ReleaseName], 'Visible', 'off', ...
                'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) delete(app));
            root = uigridlayout(app.UIFigure, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            tabs = app.add('tabGroup', uitabgroup(root), 1, 1);

            %% ---- Main tab
            tabMain = app.add('tabMain', uitab(tabs, 'Title', 'Process Pattern 📡'), [], []);
            gMain = uigridlayout(tabMain, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});

            % Inputs & parameters
            pParam = app.add('panelParam', uipanel(gMain, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 14]);
            gP = uigridlayout(pParam, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});
            app.lbl(gP, 'Input Pattern:', 1, 1);
            app.add('pathField', uieditfield(gP, 'text'), 1, [2 8]);
            app.add('ffdLabel', app.lbl(gP, 'FFD Freq:', 1, 9), [], [], 'Visible', 'off');
            app.add('ffdDD', uidropdown(gP, 'Items', {'Frequencies'}), 1, 10, 'Visible', 'off', 'ValueChangedFcn', app.cb(@(s, e) app.onFFDChanged()));
            app.add('loadBtn', uibutton(gP, 'push'), 1, [11 12], 'Text', '📂 Load File', 'FontWeight', 'bold', 'FontSize', 14, 'ButtonPushedFcn', app.cb(@(s, e) app.onLoad()));
            app.add('processBtn', uibutton(gP, 'push'), 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', app.cb(@(s, e) app.onProcess()));
            app.add('resetBtn', uibutton(gP, 'push'), 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', app.cb(@(s, e) app.resetParams()));
            app.add('formatLabel', app.lbl(gP, 'Format:', 2, [4 5]), [], [], 'Visible', 'off');
            app.add('formatDD', app.textFormatDropdown(gP), 2, [6 8], 'Visible', 'off', 'ValueChangedFcn', app.cb(@(s, e) app.onTextFormatChanged()));
            app.add('stepDD', uidropdown(gP, 'Items', {'STEP', app.OneDegree}), 2, [9 10], 'Visible', 'off', 'Enable', 'off', 'UserData', false, 'ValueChangedFcn', app.cb(@(s, e) app.onStepChanged()));
            app.add('exportBtn', uibutton(gP, 'push'), 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@(s, e) app.exportResults()));
            app.add('exportUAN', uibutton(gP, 'push'), 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@(s, e) app.exportUAN()));
            app.add('rxPolLabel', app.lbl(gP, 'Rw Sense', 3, 1), [], [], 'Visible', 'off');
            app.add('rxPol', uidropdown(gP, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Editable', 'on'), 3, 2, 'Visible', 'off');
            app.add('rwLabel', app.lbl(gP, 'Rw (dB)', 3, 3), [], [], 'Visible', 'off');
            app.add('rwSpin', uispinner(gP, 'Value', 6), 3, 4, 'Visible', 'off');
            app.add('lossLabel', app.lbl(gP, 'Loss (−) / Gain (+) dB', 3, 5), [], [], 'Visible', 'off');
            app.add('lossSpin', uispinner(gP, 'Step', 0.1), 3, 6, 'Visible', 'off');
            app.add('ptLabel', app.lbl(gP, 'Tx Pwr (Pt)', 3, 7), [], [], 'Visible', 'off');
            app.add('ptSpin', uispinner(gP), 3, 8, 'Visible', 'off');
            app.add('ptUnit', uidropdown(gP, 'Items', {'dBW', 'dBm', 'Watts'}), 3, 9, 'Visible', 'off');
            app.add('rLabel', app.lbl(gP, 'Distance', 3, 10), [], [], 'Visible', 'off');
            app.add('rSpin', uispinner(gP, 'Value', 1), 3, 11, 'Visible', 'off');
            app.add('rUnit', uidropdown(gP, 'Items', {'m', 'km'}), 3, 12, 'Visible', 'off');
            app.add('coverageBtn', uibutton(gP, 'push'), 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@(s, e) app.onCoverageFromMain()));

            % Full-pattern panel: five tabs share one factory.
            pFull = app.add('panelFull', uipanel(gMain, 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [1 6]);
            gF = uigridlayout(pFull, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            tabPlots = app.add('tabPlots', uitabgroup(gF), 1, 1, 'SelectionChangedFcn', @(~, ~) app.syncAnnotationVisibility());
            names = {'contour', 'circular', 'sphere3D', 'polar3D', 'rect3D'};
            titles = {'Contour Plot', 'Circular Contour Plot', '3D Spherical Plot', '3D Polar Plot', '3D Surface Plot'};
            axesNames = {'axCtr', 'paxPattern', 'ax3dSph', 'ax3dPol', 'ax3dRect'};
            for k = 1:numel(names)
                s.name = names{k};
                s.tab = uitab(tabPlots, 'Title', titles{k});
                g = uigridlayout(s.tab, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
                if k == 2, s.axes = polaraxes(g); else, s.axes = uiaxes(g); end
                app.add(axesNames{k}, s.axes, [1 3], 2);
                s.maxSpin = app.add('', uispinner(g, 'Limits', app.DBRange, 'Value', 100, 'Step', 5), 1, 1, 'ValueChangedFcn', app.cb(@(src, e) app.setRange(src.Value, 2, "full")));
                s.slider = app.add('', uislider(g, 'range', 'Limits', app.DBRange, 'Value', app.DBRange, 'Orientation', 'vertical', 'Step', 1), 2, 1, 'ValueChangedFcn', app.cb(@(src, e) app.setRange(src.Value, 0, "full")));
                s.minSpin = app.add('', uispinner(g, 'Limits', app.DBRange, 'Value', -250, 'Step', 5), 3, 1, 'ValueChangedFcn', app.cb(@(src, e) app.setRange(src.Value, 1, "full")));
                if k == 1, app.full = s; else, app.full(k) = s; end
            end
            set([app.h.paxPattern], 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');

            % Cut panel
            pCut = app.add('panelCut', uipanel(gMain, 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [7 12]);
            gC = uigridlayout(pCut, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            tabCut = app.add('tabCut', uitabgroup(gC), 1, 1, 'SelectionChangedFcn', @(~, ~) app.syncAnnotationVisibility());
            tabPolar = app.add('tabPolar', uitab(tabCut, 'Title', 'Polar Cut Plot'), [], []);
            gPol = uigridlayout(tabPolar, 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            app.add('cutMax', uispinner(gPol, 'Limits', app.DBRange, 'Value', 100, 'Step', 5), 1, 1, 'ValueChangedFcn', app.cb(@(src, e) app.setRange(src.Value, 2, "cut")));
            app.add('cutSlider', uislider(gPol, 'range', 'Limits', app.DBRange, 'Value', app.DBRange, 'Orientation', 'vertical', 'Step', 1), [2 3], 1, 'ValueChangedFcn', app.cb(@(src, e) app.setRange(src.Value, 0, "cut")));
            app.add('cutMin', uispinner(gPol, 'Limits', app.DBRange, 'Value', -250, 'Step', 5), 4, 1, 'ValueChangedFcn', app.cb(@(src, e) app.setRange(src.Value, 1, "cut")));
            app.add('paxCut', polaraxes(gPol), [1 4], 3, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            app.add('hpbwBtn', uibutton(gPol, 'state'), 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', app.cb(@(s, e) app.onCutChanged()));
            app.add('hpbwLabel', uilabel(gPol, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold'), 2, 4);
            gE = app.add('gridEcut', uigridlayout(gPol, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x', '1x', '1x'}), 3, 4);
            app.add('cbEt', uicheckbox(gE, 'Text', 'E_Total', 'Value', true), 1, 1, 'ValueChangedFcn', app.cb(@(s, e) app.onCutChanged()));
            app.add('cbEr', uicheckbox(gE, 'Text', 'E_RCP', 'Value', true), 2, 1, 'ValueChangedFcn', app.cb(@(s, e) app.onCutChanged()));
            app.add('cbEl', uicheckbox(gE, 'Text', 'E_LCP', 'Value', true), 3, 1, 'ValueChangedFcn', app.cb(@(s, e) app.onCutChanged()));
            app.add('exportCutBtn', uibutton(gPol, 'push'), 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', app.cb(@(s, e) app.exportCut()));
            tabRect = app.add('tabRect', uitab(tabCut, 'Title', 'Rectangular Cut Plot'), [], []);
            gR = uigridlayout(tabRect);
            app.add('axRect', uiaxes(gR), [1 2], [1 2], 'Box', 'on');
            xlabel(app.h.axRect, 'Theta (degree)'); ylabel(app.h.axRect, 'Magnitude (dB)');

            % Plot control panel
            pCtrl = app.add('panelCtrl', uipanel(gMain, 'Title', 'Plot Control 🎨', 'Visible', 'off'), 2, [13 14]);
            gK = uigridlayout(pCtrl, 'RowHeight', repmat({'fit'}, 1, 15));
            app.lbl(gK, 'Component', 1, 1);
            app.add('component', uidropdown(gK, 'Items', cellstr(app.ComponentLabels), 'ItemsData', cellstr(app.ComponentNames)), 1, 2, 'ValueChangedFcn', app.cb(@(s, e) app.onComponentChanged()));
            app.lbl(gK, 'Cut type', 2, 1);
            app.add('cutType', uidropdown(gK, 'Items', {'Phi', 'Theta'}), 2, 2, 'ValueChangedFcn', app.cb(@(s, e) app.onCutChanged(true)));
            app.lbl(gK, 'Cut value', 3, 1);
            app.add('cutValue', uispinner(gK, 'Limits', [0 360], 'Value', 0), 3, 2, 'ValueChangedFcn', app.cb(@(s, e) app.onCutChanged()));
            app.lbl(gK, 'Cut fields', 4, 1);
            app.add('cutBasis', uidropdown(gK, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Enable', 'off', 'UserData', true), 4, 2, ...
                'ValueChangedFcn', app.cb(@(s, e) app.onCutBasisChanged()));
            app.lbl(gK, 'Colorbar max', 5, 1);
            app.add('cMax', uispinner(gK, 'Limits', app.DBRange, 'Value', 10), 5, 2, 'ValueChangedFcn', app.cb(@(s, e) app.setRange([app.h.cMin.Value, app.h.cMax.Value], 0, "all")));
            app.lbl(gK, 'Colorbar min', 6, 1);
            app.add('cMin', uispinner(gK, 'Limits', app.DBRange, 'Value', -40), 6, 2, 'ValueChangedFcn', app.cb(@(s, e) app.setRange([app.h.cMin.Value, app.h.cMax.Value], 0, "all")));
            app.lbl(gK, 'Colorbar step', 7, 1);
            app.add('cStep', uispinner(gK, 'Limits', [0.1 100], 'Value', 5), 7, 2, 'ValueChangedFcn', app.cb(@(s, e) app.applyFullRange(app.rangeFor(app.comp()))));
            app.lbl(gK, 'Adjust Colorbar', 8, 1);
            app.add('', uibutton(gK, 'push'), 8, 2, 'Text', 'Apply', 'Tooltip', 'Apply to full-pattern plots; gain-cut limits remain independent for AR.', ...
                'ButtonPushedFcn', app.cb(@(s, e) app.setRange([app.h.cMin.Value, app.h.cMax.Value], 0, "all")));
            app.lbl(gK, '3D view', 9, 1);
            app.add('view3D', uidropdown(gK, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Tooltip', 'Camera direction for the 3D pattern tabs.'), 9, 2, ...
                'ValueChangedFcn', app.cb(@(s, e) app.apply3DViews()));
            pad = @(n) repmat(char(160), 1, n);
            app.add('phiSpan', uiswitch(gK, 'slider', 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', app.SignedPhi}), 10, [1 2], ...
                'ValueChangedFcn', app.cb(@(s, e) app.onSpanChanged()));
            app.add('thetaSpan', uiswitch(gK, 'slider', 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', app.ElevationTheta}), 11, [1 2], ...
                'ValueChangedFcn', app.cb(@(s, e) app.onSpanChanged()));
            app.add('ehSwitch', uiswitch(gK, 'slider', 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E', 'H'}), 12, [1 2], 'ValueChangedFcn', app.cb(@(s, e) app.onEHPlane()));
            app.add('cbOverlay', uicheckbox(gK, 'Text', 'Overlay Cut on 3D Plot'), 13, [1 2], 'ValueChangedFcn', app.cb(@(s, e) app.drawOverlay3D()));
            app.add('cbPOB', uicheckbox(gK, 'Text', 'Annotate POB'), 14, [1 2], 'ValueChangedFcn', app.cb(@(s, e) app.onPOBToggled()));
            app.add('cbHPBW', uicheckbox(gK, 'Text', 'Annotate HPBW Bounds', 'Visible', 'off'), 15, [1 2], 'ValueChangedFcn', app.cb(@(s, e) app.onCutChanged()));

            % Data tables
            app.add('outputDD', uidropdown(gMain, 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'Value', 0, 'Visible', 'off'), 3, [13 14], 'ValueChangedFcn', app.cb(@(s, e) app.filterOutput()));
            tabData = app.add('tabData', uitabgroup(gMain, 'Visible', 'off'), 4, [1 14]);
            tabOut = uitab(tabData, 'Title', 'Results 📤', 'ButtonDownFcn', @(~, ~) set(app.h.outputDD, 'Visible', 'on'));
            app.add('tableOut', uitable(uigridlayout(tabOut, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}), 'ColumnWidth', '1x', 'RowName', 'numbered', 'ColumnSortable', true, 'ColumnRearrangeable', 'on'), 1, 1);
            tabIn = uitab(tabData, 'Title', 'Input 📥');
            app.add('tableIn', uitable(uigridlayout(tabIn, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}), 'RowName', 'numbered', 'ColumnSortable', true, 'ColumnRearrangeable', 'on'), 1, 1);
            tabMeta = uitab(tabData, 'Title', 'Metadata 📋');
            app.add('tableMeta', uitable(uigridlayout(tabMeta, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}), 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {}), 1, 1);
            app.add('status1', uilabel(gMain, 'Interpreter', 'html', 'Text', 'Ready 🚀'), 5, [1 14]);

            %% ---- Coverage tab
            tabCov = app.add('tabCov', uitab(tabs, 'Title', 'Compute Coverage 📈'), [], []);
            gCov = uigridlayout(tabCov, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            pCP = uipanel(gCov, 'Title', 'Inputs & Parameters 🎛️'); pCP.Layout.Row = 1; pCP.Layout.Column = [1 5];
            gQ = app.add('covParamGrid', uigridlayout(pCP, 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'}), [], []);
            bg = app.add('covType', uibuttongroup(gQ, 'Title', 'Coverage Type'), [1 2], [1 2], 'SelectionChangedFcn', app.cb(@(s, e) app.onCovTypeChanged()));
            uiradiobutton(bg, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            app.add('covConical', uiradiobutton(bg, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]), [], []);
            app.add('covOrientLabel', app.lbl(gQ, 'Orientation 🧭:', 3, 1), [], [], 'Enable', 'off');
            app.add('covOrient', uidropdown(gQ, 'Items', [{'Auto'}, app.PrincipalAxes.labels], 'ItemsData', 0:numel(app.PrincipalAxes.labels), 'Value', 0, 'Enable', 'off'), 3, 2, ...
                'ValueChangedFcn', app.cb(@(s, e) app.onCovOrientationChanged()));
            app.add('covCompLabel', app.lbl(gQ, 'Component:', 4, 1), [], [], 'Enable', 'off');
            app.add('covComp', uidropdown(gQ, 'Items', {'E_Total_dB'}, 'Enable', 'off'), 4, 2, 'ValueChangedFcn', app.cb(@(s, e) app.onCovComponentChanged()));
            app.add('covPathLabel', app.lbl(gQ, 'Antenna Pattern:', 1, 3), [], []);
            app.add('covPath', uieditfield(gQ, 'text'), 1, [4 8]);
            app.add('covLoadBtn', uibutton(gQ, 'push'), 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', app.cb(@(s, e) app.onCovLoad()));
            app.add('covComputeBtn', uibutton(gQ, 'push'), 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@(s, e) app.onCovCompute()));
            app.lbl(gQ, 'Threshold  Min (dB):', 2, 3); app.add('thrMin', uispinner(gQ, 'Value', -40), 2, 4);
            app.lbl(gQ, 'Threshold  Max (dB):', 2, 5); app.add('thrMax', uispinner(gQ, 'Value', 10), 2, 6);
            app.lbl(gQ, 'Step (dB):', 2, 7);           app.add('thrStep', uispinner(gQ, 'Value', 1), 2, 8);
            app.add('covResetBtn', uibutton(gQ, 'push'), 2, 9, 'Text', '🔄 Reset', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@(s, e) app.onCovReset()));
            app.add('covExportBtn', uibutton(gQ, 'push'), 2, 10, 'Text', '💾 Export Results', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@(s, e) app.onCovExport()));
            app.add('coneThLabel', app.lbl(gQ, 'Cone θ₀ (°):', 3, 3), [], [], 'Enable', 'off'); app.add('coneTh', uispinner(gQ, 'Limits', [0 180], 'Enable', 'off'), 3, 4);
            app.add('conePhLabel', app.lbl(gQ, 'Cone φ₀ (°):', 3, 5), [], [], 'Enable', 'off'); app.add('conePh', uispinner(gQ, 'Limits', [0 360], 'Enable', 'off'), 3, 6);
            app.add('coneAngLabel', app.lbl(gQ, 'Cone Angle α (°):', 3, 7), [], [], 'Enable', 'off'); app.add('coneAng', uispinner(gQ, 'Limits', [0 180], 'Value', 45, 'Enable', 'off'), 3, 8);
            app.add('covClearBtn', uibutton(gQ, 'push'), 3, 9, 'Text', '🧹 Clear DataTips', 'Enable', 'off', 'ButtonPushedFcn', app.cb(@(s, e) app.onCovClear()));
            app.add('covToMainBtn', uibutton(gQ, 'push'), 3, 10, 'Text', '📊 To Main ◀ ', 'ButtonPushedFcn', @(~, ~) set(app.h.tabGroup, 'SelectedTab', app.h.tabMain));
            app.add('qCovLabel', app.lbl(gQ, 'Coverage @ dB:', 4, 3), [], [], 'Visible', 'off');
            app.add('qCov', uispinner(gQ, 'ValueDisplayFormat', '%g dB', 'Visible', 'off'), 4, 4);
            app.add('qCovBtn', uibutton(gQ, 'push'), 4, 5, 'Text', '⯐ Query Coverage', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@(s, e) app.covQuery("cov")));
            app.add('qThrLabel', app.lbl(gQ, 'Threshold @ %:', 4, 6), [], [], 'Visible', 'off');
            app.add('qThr', uispinner(gQ, 'ValueDisplayFormat', '%g%%', 'Value', 50, 'Visible', 'off'), 4, 7);
            app.add('qThrBtn', uibutton(gQ, 'push'), 4, 8, 'Text', '🔍︎ Query Threshold', 'Enable', 'off', 'Visible', 'off', 'ButtonPushedFcn', app.cb(@(s, e) app.covQuery("thr")));
            app.add('covFormatLabel', app.lbl(gQ, 'Format:', 4, 9), [], [], 'Visible', 'off');
            app.add('covFormatDD', app.textFormatDropdown(gQ), 4, 10, 'Visible', 'off', 'ValueChangedFcn', app.cb(@(s, e) app.onCovTextFormatChanged()));
            app.h.covQueryCtl = [app.h.qCovLabel, app.h.qCov, app.h.qCovBtn, app.h.qThrLabel, app.h.qThr, app.h.qThrBtn];

            pRes = app.add('covResults', uipanel(gCov, 'Title', 'Results', 'Visible', 'off'), 2, [1 5]);
            gRes = uigridlayout(pRes, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            tree = app.add('covTree', uitree(gRes, 'checkbox'), [1 2], 1, 'SelectionChangedFcn', app.cb(@(s, e) app.onCovTreeSelection()), 'CheckedNodesChangedFcn', app.cb(@(s, e) app.onCovTreeChecked()));
            app.h.covRoot = uitreenode(tree, 'Text', 'Coverage Results');
            ax = app.add('covAxes', uiaxes(gRes, 'Interactions', dataTipInteraction), 1, [2 4]);
            title(ax, 'Coverage vs Threshold'); xlabel(ax, 'Threshold (dB)'); ylabel(ax, 'Coverage (%)');
            app.add('covTable', uitable(gRes, 'ColumnWidth', '1x', 'RowName', {}), [1 2], 5);
            app.add('xMin', uispinner(gRes, 'Limits', app.DBRange, 'Value', -40), 2, 2, 'ValueChangedFcn', app.cb(@(s, e) app.onCovXRange(false)));
            app.add('xRange', uislider(gRes, 'range', 'Limits', app.DBRange, 'Value', [-40 10]), 2, 3, 'ValueChangedFcn', app.cb(@(s, e) app.onCovXRange(true)), 'ValueChangingFcn', app.cb(@(s, e) app.onCovXRange(true, e.Value)));
            app.add('xMax', uispinner(gRes, 'Limits', app.DBRange, 'Value', 10), 2, 4, 'ValueChangedFcn', app.cb(@(s, e) app.onCovXRange(false)));
            app.add('covStatus', uilabel(gCov, 'Interpreter', 'html', 'Text', 'Ready 🚀'), 3, [1 5]);
            app.UIFigure.Visible = 'on';
        end

        function dd = textFormatDropdown(app, parent)
            dd = uidropdown(parent, 'Items', app.TextFormats.Items, 'ItemsData', app.TextFormats.ItemsData, 'Value', 'gain', ...
                'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.');
        end

        function attachContextMenu(app, ax)
            % DataTip actions on every plot without disturbing rotate/zoom gestures.
            menu = uicontextmenu(app.UIFigure, 'Tag', 'APAT_PlotContextMenu');
            uimenu(menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ~) delete(findall(ax, 'Type', 'datatip')));
            set([ax; findall(ax, '-property', 'ContextMenu')], 'ContextMenu', menu);
        end
    end

    %% ------------------------------------------------------------------ load / process / export
    methods (Access = private)
        function onLoad(app)
            H = app.h; previousPath = H.pathField.Value; fp = strtrim(previousPath);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.filePath)
                while true
                    [f, p] = uigetfile(app.FileFilter, 'Select an antenna pattern file');
                    if isequal(f, 0), return; end
                    fp = fullfile(p, f);
                    if ~strcmp(fp, app.filePath), break; end
                    choice = uiconfirm(app.UIFigure, sprintf('"<strong>%s</strong>" is already loaded', f), 'File Already Loaded', ...
                        'Options', {'Select Another File', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2, 'Interpreter', 'html');
                    if strcmp(choice, 'Cancel'), return; end
                end
                H.pathField.Value = fp;
            end
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Loading Data', 'Message', 'Reading file...', 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            app.operationDialog = dlg; cleaner = onCleanup(@() close(dlg)); drawnow;
            endPerf = app.startPerf("Load pattern"); finish = onCleanup(endPerf);
            try
                out = app.prepareTextFormat(fp, H.formatLabel, H.formatDD);
                app.perfTracker("Read file"); app.checkCancelled();
                if out.userData.isCoverage                       % route coverage files without touching Main state
                    H.pathField.Value = previousPath; set([H.formatLabel, H.formatDD], 'Visible', 'off');
                    [H.tabGroup.SelectedTab, H.covPath.Value] = deal(H.tabCov, fp);
                    app.covLoadResults(fp, out.rawTbl); return
                end
                app.filePath = fp; [app.folderPath, app.baseName, ext] = fileparts(fp); app.fileName = [app.baseName, ext];
                app.activateSource(out);
                isDep = out.userData.isDep;
                if isDep
                    items = compose('Pattern %d: %.4g GHz', (1:numel(out.blocks))', out.freqs(:) / 1e9);
                    items(isnan(out.freqs(:))) = compose('Pattern %d', find(isnan(out.freqs(:))));
                    [H.ffdDD.Items, H.ffdDD.Value] = deal(items, items{1});
                end
                set([H.ffdDD, H.ffdLabel], 'Visible', isDep, 'Enable', isDep);
                [H.stepDD.UserData, H.cutBasis.UserData] = deal(false, true);
                app.refresh();
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.setStatus(H.status1, 'Loading cancelled by user.', true);
                else, app.showError(ME, 'Loading Error'); end
            end
        end

        function out = prepareTextFormat(app, fp, label, dropdown)
            % Generic text files expose the format selector; all other sources are self-describing.
            [~, ~, ext] = fileparts(fp); generic = ismember(lower(ext), {'.csv', '.txt', '.dat'});
            if generic, fmt = "gain"; else, fmt = string(dropdown.Value); end
            out = readPattern(fp, fmt);
            showSelector = generic && ~out.userData.isCoverage;
            if showSelector, dropdown.Value = 'gain'; end
            set([label, dropdown], 'Visible', showSelector);
        end

        function activateSource(app, out)
            [app.rawTbl, app.ffdBlocks, app.freqs, app.srcUD] = deal(out.rawTbl, out.blocks, out.freqs, out.userData);
            app.selectBlock(1);
        end

        function selectBlock(app, k)
            block = app.ffdBlocks{k};
            if app.srcUD.isDep, app.rawTbl = block; end
            app.stdTbl = normalizePattern(block); app.stdTbl.Properties.UserData = app.srcUD;
            set(app.h.tableIn, 'Data', app.rawTbl, 'ColumnName', app.rawTbl.Properties.VariableNames);
        end

        function onProcess(app)
            H = app.h;
            if isempty(app.stdTbl), uialert(app.UIFigure, 'No file! Load a pattern first.', 'Warning', 'Icon', 'warning'); return; end
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Processing', 'Message', 'Re-processing pattern...', 'Indeterminate', 'on');
            cleaner = onCleanup(@() close(dlg)); finish = onCleanup(app.startPerf("Reprocess pattern"));
            H.stepDD.UserData = strcmp(H.stepDD.Value, app.OneDegree);
            if app.isGenericText(app.filePath)                    % reinterpret the cached generic table with the selected format
                out = readPattern(app.filePath, H.formatDD.Value, app.rawTbl);
                assert(~out.userData.isCoverage, 'The selected generic format identifies a coverage-results file.');
                app.activateSource(out); app.perfTracker("Reinterpret generic source");
            end
            app.refresh();
            app.setStatus(H.status1, ['Re-processed <b>' app.fileName '</b> with current parameters ' char(9989)], true);
        end

        function onTextFormatChanged(app)
            if strcmp(strtrim(app.h.pathField.Value), app.filePath) && app.isGenericText(app.filePath)
                app.h.cutBasis.UserData = true; app.onProcess();
            end
        end

        function onFFDChanged(app)
            finish = onCleanup(app.startPerf("Switch FFD block")); %#ok<NASGU>
            k = find(strcmp(app.h.ffdDD.Items, app.h.ffdDD.Value), 1);
            app.h.cutBasis.UserData = true; app.selectBlock(k); app.refresh();
            app.setStatus(app.h.status1, sprintf('Switched to FFD block %d (%s).', k, app.h.ffdDD.Value), true);
        end

        function onStepChanged(app)
            finish = onCleanup(app.startPerf("Change angular step")); %#ok<NASGU>
            app.applyStep(); app.updateComponentItems(); app.updateViewResults(true);
        end

        function onSpanChanged(app)
            if isempty(app.viewTbl), return; end
            finish = onCleanup(app.startPerf("Change angular span")); %#ok<NASGU>
            app.rebuildDisplay(); app.updateViewResults();
        end

        function resetParams(app)
            if isempty(fieldnames(app.defaultParams)), return; end
            app.applyParam(app.defaultParams);
            if ~isempty(app.stdTbl), app.refresh(); end
        end

        function exportResults(app)
            if isempty(app.viewTbl), return; end
            [f, p] = uiputfile(app.ExportFilter, 'Export Results', fullfile(app.folderPath, [app.baseName '_APAT_results.csv']));
            if isequal(f, 0), return; end
            app.writeTable(app.h.tableOut.Data, fullfile(p, f));          % respects the active column filter
            app.setStatus(app.h.status1, ['Results exported to <b>' fullfile(p, f) '</b>'], true);
        end

        function exportCut(app)
            if isempty(app.viewTbl), return; end
            [ang, data, cols, titleText] = app.cutData();
            [f, p] = uiputfile(app.ExportFilter(1:2, :), 'Export Cut', fullfile(app.folderPath, [app.baseName '_cut.csv']));
            if isequal(f, 0), return; end
            app.writeTable(array2table([ang, data], 'VariableNames', [{'Angle_deg'}, cellstr(cols)]), fullfile(p, f));
            app.setStatus(app.h.status1, ['Cut (' titleText ') exported to <b>' fullfile(p, f) '</b>'], true);
        end

        function exportUAN(app)
            if app.srcUD.isGainOnly, uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            T = app.viewTbl;                                               % physical coordinates by construction
            U = sortrows(table(T.Theta, T.Phi, round(T.E_TH_dB, 5), round(T.E_PH_dB, 5), round(T.E_TH_Phase, 5), round(T.E_PH_Phase, 5), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'}), {'Phi', 'Theta'});
            thetaStep = gridStep(U.Theta); phiStep = gridStep(U.Phi); if ~isfinite(thetaStep), thetaStep = 1; end
            peak = max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan');
            [f, p] = uiputfile([{'*.uan', 'XGTD user-defined antenna (*.uan)'}; app.ExportFilter(1:2, :)], 'Export UAN / E-field data', ...
                fullfile(app.folderPath, sprintf('%s_%.5f_%gdeg.uan', app.baseName, peak, thetaStep)));
            if isequal(f, 0), return; end
            fp = fullfile(p, f);
            if endsWith(fp, '.uan', 'IgnoreCase', true)
                header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                    min(U.Phi), max(U.Phi), phiStep, min(U.Theta), max(U.Theta), thetaStep, peak);
                writelines(header, fp);
                writetable(U, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
            else
                app.writeTable(U, fp);
            end
            app.setStatus(app.h.status1, ['UAN exported to <b>' fp '</b>'], true);
        end

        function writeTable(~, T, fp)
            if endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t'); else, writetable(T, fp); end
        end
    end

    %% ------------------------------------------------------------------ pipeline & view model
    methods (Access = private)
        function refresh(app)
            H = app.h;
            [app.patTbl, info] = calcPattern(app.stdTbl, app.getParam(), app.PeakPercentile, app.PeakMaxExcessDB);
            app.perfTracker("Process pattern"); app.checkCancelled();
            [app.polLabel, app.polPairs] = deal(info.pol, info.pairs);
            hasE = ~app.srcUD.isGainOnly;
            if isequal(H.cutBasis.UserData, true) && hasE
                if startsWith(info.pol, 'Linear'), H.cutBasis.Value = 'Linear'; else, H.cutBasis.Value = 'Circular'; end
            end
            thetaStep = gridStep(app.patTbl.Theta); phiStep = gridStep(mod(app.patTbl.Phi, 360));
            if ~isfinite(thetaStep), thetaStep = 1; end
            if ~isfinite(phiStep), phiStep = thetaStep; end
            native = sprintf('STEP: %g%c', max(thetaStep, phiStep), char(176));
            nonCanonical = abs(thetaStep - 1) > 1e-9 || abs(phiStep - 1) > 1e-9;
            H.stepDD.Items = {native, app.OneDegree}; H.stepDD.Value = native;
            if nonCanonical && isequal(H.stepDD.UserData, true), H.stepDD.Value = app.OneDegree; end
            set(H.stepDD, 'UserData', false, 'Visible', nonCanonical, 'Enable', nonCanonical);
            H.cutValue.Step = max(thetaStep, 1);
            app.applyStep(); app.updateComponentItems();
            app.perfTracker("Prepare view"); app.checkCancelled();
            app.updateViewResults(true, false, false);
            app.perfTracker("Populate tables and ranges"); app.checkCancelled();
            app.onEHPlane(); drawnow limitrate
            app.renderAllFull(); app.perfTracker("Build plots");
            set([H.panelCut, H.panelFull, H.panelCtrl, H.exportBtn, H.coverageBtn], 'Visible', 'on');
            set([H.exportUAN, H.gridEcut, H.cbEt, H.cbEr, H.cbEl], 'Visible', hasE); set([H.cbEr, H.cbEl, H.cutBasis], 'Enable', hasE);
            app.updateInputVisibility();
            pol = ''; if hasE && ~strcmpi(strtrim(app.polLabel), 'n/a'), pol = sprintf(' | Polarization <b>%s</b>', app.polLabel); end
            app.setStatus(H.status1, sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)%s', ...
                app.fileName, app.fmt(app.POB, 2), app.fmt(app.POBth), app.fmt(app.POBph), pol), false);
        end

        function applyStep(app)
            % Resample the primitive canonical source (never derived dB quantities), then recompute.
            src = app.stdTbl;
            thetaStep = gridStep(src.Theta); phiStep = gridStep(mod(src.Phi, 360));
            canonical = abs(thetaStep - 1) <= 1e-9 && abs(phiStep - 1) <= 1e-9;   % NaN-safe
            if strcmp(app.h.stepDD.Value, app.OneDegree) && ~canonical
                if thetaStep < 1 && phiStep < 1                                  % decimate exact integer-degree samples
                    src = src(abs(src.Theta - round(src.Theta)) < 1e-9 & abs(src.Phi - round(src.Phi)) < 1e-9, :);
                else
                    src = resampleCanonical(src, 1);
                end
                src.Properties.UserData = app.stdTbl.Properties.UserData;
                app.viewTbl = calcPattern(src, app.getParam(), app.PeakPercentile, app.PeakMaxExcessDB);
            else
                app.viewTbl = app.patTbl;
            end
            app.viewSolidAngle = [];
            app.rebuildDisplay();
        end

        function rebuildDisplay(app)
            % Materialize the display convention once; every renderer/table reads dispTbl.
            T = app.viewTbl;
            if app.signedPhi()
                T(abs(T.Phi - 360) <= 1e-9, :) = [];
                T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
                seam = T(abs(T.Phi - 180) < 1e-9, :); seam.Phi(:) = -180; T = [seam; T];
            end
            if app.elevation(), T.Theta = 90 - T.Theta; end
            app.dispTbl = sortrows(T, {'Phi', 'Theta'});
            app.grid = struct(); app.metrics = struct();
        end

        function tf = signedPhi(app), tf = strcmp(app.h.phiSpan.Value, app.SignedPhi); end
        function tf = elevation(app), tf = strcmp(app.h.thetaSpan.Value, app.ElevationTheta); end
        function c = comp(app), c = app.h.component.Value; end
        function tf = isGenericText(~, fp), [~, ~, ext] = fileparts(fp); tf = ismember(lower(ext), {'.csv', '.txt', '.dat'}); end

        function [theta, phi] = toDisplay(app, theta, phi)
            % Map physical angles to the active display convention.
            if app.signedPhi(), phi = mod(phi, 360); phi(phi > 180) = phi(phi > 180) - 360; end
            if app.elevation(), theta = 90 - theta; end
        end

        function label = compLabel(app)
            dd = app.h.component; k = find(strcmp(dd.ItemsData, dd.Value), 1);
            if isempty(k), label = strrep(string(dd.Value), '_', ' '); else, label = string(dd.Items{k}); end
        end

        function param = getParam(app)
            H = app.h;
            param = struct('GainLoss_dB', H.lossSpin.Value, 'RxMode', string(H.rxPol.Value), 'RxAR_dB', H.rwSpin.Value, ...
                'Power', H.ptSpin.Value, 'PowerUnit', string(H.ptUnit.Value), 'Distance', H.rSpin.Value, 'DistanceUnit', string(H.rUnit.Value));
            param.FieldScale = 10 .^ (param.GainLoss_dB / 20);
            switch param.PowerUnit
                case "dBm",   param.Pt_dBW = param.Power - 30;
                case "Watts", param.Pt_dBW = 10 * log10(max(param.Power, eps));
                otherwise,    param.Pt_dBW = param.Power;
            end
            param.R_m = max(param.Distance, app.DistanceFloorM) * (1 + 999 * (param.DistanceUnit == "km"));
        end

        function applyParam(app, p)
            H = app.h;
            [H.lossSpin.Value, H.rxPol.Value, H.rwSpin.Value, H.ptSpin.Value, H.ptUnit.Value, H.rSpin.Value, H.rUnit.Value] = ...
                deal(p.GainLoss_dB, char(p.RxMode), p.RxAR_dB, p.Power, char(p.PowerUnit), p.Distance, char(p.DistanceUnit));
        end

        function [columns, labels] = componentMap(app, T)
            available = string(T.Properties.VariableNames(3:end));
            if T.Properties.UserData.isGainOnly, [columns, labels] = deal(available); return; end
            present = ismember(app.ComponentNames, available);
            [columns, labels] = deal(app.ComponentNames(present), app.ComponentLabels(present));
        end

        function c = preferredComponent(~, previous, columns)
            if any(columns == string(previous)), c = char(previous);
            elseif any(columns == "E_Total_dB"), c = 'E_Total_dB';
            else, c = char(columns(1)); end
        end

        function updateComponentItems(app)
            [columns, labels] = app.componentMap(app.viewTbl); dd = app.h.component; previous = dd.Value;
            [dd.Items, dd.ItemsData] = deal(cellstr(labels), cellstr(columns));
            if ~isempty(columns), dd.Value = app.preferredComponent(previous, columns); end
        end

        function updateViewResults(app, refreshRanges, renderFull, updateCut)
            if nargin < 2, refreshRanges = false; end
            if nargin < 3, renderFull = true; end
            if nargin < 4, updateCut = true; end
            T = app.viewTbl; c = app.comp();
            if numel(app.viewSolidAngle) ~= height(T), app.viewSolidAngle = solidWeights(T.Theta, T.Phi); end
            [peak, app.boresightIndex] = calcOrientation(T, app.viewSolidAngle, c, app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
            [app.peakInfo, app.POB, app.POBth, app.POBph] = deal(peak, peak.value, T.Theta(peak.index), T.Phi(peak.index));
            app.metrics = calcMetrics(T, app.viewSolidAngle, app.PrincipalAxes, app.boresightIndex, app.PeakPercentile, app.PeakMaxExcessDB);
            if refreshRanges
                if ~app.isAR(c) && ismember('E_Total_dB', T.Properties.VariableNames)
                    app.gainLim = peakWindow(T.E_Total_dB, app.PeakPercentile, app.PeakMaxExcessDB);
                end
                app.setRange(app.rangeFor(c), 0, "all", false);
            end
            app.updateTables(); app.updateMetadata();
            if updateCut, app.updateCutControl(); app.plotCut(); end
            if renderFull, app.renderAllFull(); end
        end

        function onComponentChanged(app)
            if app.srcUD.isGainOnly, app.onEHPlane(); end
            app.updateViewResults(true);
        end

        function updateTables(app)
            H = app.h; dd = H.outputDD; columns = app.dispTbl.Properties.VariableNames(3:end);
            schemaChanged = ~isequal(regexprep(dd.Items(2:end), '^✓ ?', ''), columns);
            if schemaChanged
                [dd.Items, dd.ItemsData, dd.Value] = deal([{'--- column filter ---'}, columns], 0:numel(columns), 0);
                dd.UserData = ~ismember(columns, app.HiddenOutputColumns);
                set([dd, H.tableOut, H.tabData, H.tableIn], 'Visible', 'on');
            end
            app.filterOutput(schemaChanged);
        end

        function filterOutput(app, restyle)
            if nargin < 2, restyle = true; end
            dd = app.h.outputDD;
            if dd.Value > 0, dd.UserData(dd.Value) = ~dd.UserData(dd.Value); dd.Value = 0; end
            if restyle
                if numel(app.filterStyles) ~= 2
                    app.filterStyles = {uistyle('FontWeight', 'bold', 'FontColor', 'black', 'BackgroundColor', [0.8 1 0.8]), uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9])};
                end
                dd.Items = regexprep(dd.Items, '^✓ ?', ''); removeStyle(dd);
                on = find(dd.UserData) + 1; dd.Items(on) = append('✓ ', dd.Items(on));
                addStyle(dd, app.filterStyles{1}, 'Item', on); addStyle(dd, app.filterStyles{2}, 'Item', find([true, ~dd.UserData]));
            end
            app.h.tableOut.Data = app.dispTbl(:, [true, true, dd.UserData]);
            app.updateInputVisibility();
        end

        function updateInputVisibility(app)
            H = app.h; columns = app.dispTbl.Properties.VariableNames(3:end); shown = string(columns(H.outputDD.UserData));
            has = @(list) any(ismember(shown, list));
            set([H.rxPolLabel, H.rxPol, H.rwLabel, H.rwSpin], 'Visible', has(["PLF_dB", "Gain_PolCorrected_dB"]));
            set([H.ptLabel, H.ptSpin, H.ptUnit], 'Visible', has(["EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
            set([H.rLabel, H.rSpin, H.rUnit], 'Visible', has(["PFD_Wm2", "E_RMS_Vm"]));
            set([H.lossLabel, H.lossSpin], 'Visible', app.srcUD.isGainOnly || has(["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "Gain_PolCorrected_dB", "EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]));
        end

        function updateMetadata(app)
            T = app.dispTbl; theta = unique(T.Theta); phi = unique(T.Phi); m = app.metrics; f = @(v) app.fmt(v);
            rows = {'Source format', app.srcUD.source; 'File', app.fileName; ...
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(T), numel(theta), numel(phi)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', f(min(theta)), f(max(theta)), f(gridStep(theta))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', f(min(phi)), f(max(phi)), f(gridStep(phi)))};
            valid = app.freqs(isfinite(app.freqs));
            if ~isempty(valid), rows(end+1, :) = {'Frequencies', strjoin(compose('%.4g GHz', valid / 1e9), ', ')}; end
            if ~app.srcUD.isGainOnly
                if ~strcmpi(strtrim(app.polLabel), 'n/a'), rows(end+1, :) = {'Polarization', app.polLabel}; end
                rows(end+1, :) = {'Cut Co-pol / Cross-pol', char(strjoin(app.polPairs.(app.h.cutBasis.Value), ' / '))};
            end
            [dTh, dPh] = app.toDisplay(app.POBth, app.POBph);
            rows = [rows; {sprintf('POB (%s)', app.compLabel()), sprintf('%s dB', f(app.POB)); 'POB direction [θ, φ]', sprintf('[%s°, %s°]', f(dTh), f(dPh)); ...
                'Boresight axis', app.PrincipalAxes.labels{app.boresightIndex}; ...
                'Peak policy', sprintf('P%.4g, max excess %.4g dB', app.PeakPercentile, app.PeakMaxExcessDB); 'Peak adjusted', char(string(app.peakInfo.wasAdjusted))}];
            if isfield(m, 'PeakGain_dB')
                rows = [rows; {'Peak total gain', sprintf('%s dB', f(m.PeakGain_dB)); 'HPBW E-plane', sprintf('%s°', f(m.HPBW_EPlane_deg)); 'HPBW H-plane', sprintf('%s°', f(m.HPBW_HPlane_deg)); ...
                    'Front-to-back', sprintf('%s dB', f(m.FrontBack_dB)); 'Peak directivity', sprintf('%s dB', f(m.PeakDirectivity_dB))}];
                if isfinite(m.Efficiency_pct), rows(end+1, :) = {'Radiation efficiency', sprintf('%s%%', f(m.Efficiency_pct))}; end
                if isfinite(m.AxialRatioAtPeak_dB), rows(end+1, :) = {'AR at peak', sprintf('%s dB', f(m.AxialRatioAtPeak_dB))}; end
            end
            app.h.tableMeta.Data = rows;
        end

        function text = fmt(~, value, precision)
            % Compact number formatting: up to 2 decimals (trailing zeros removed) or exactly N decimals.
            if ~isscalar(value) || ~isnumeric(value) || ~isfinite(value), text = 'n/a'; return; end
            if nargin < 3, text = regexprep(sprintf('%.2f', value), '\.?0+$', '');
            else, text = sprintf('%.*f', max(0, min(5, round(precision))), value); end
        end
    end

    %% ------------------------------------------------------------------ display grid & ranges
    methods (Access = private)
        function [g, G] = gridComp(app, column)
            % Display-grid cache: topology + geometry once per view, one matrix per component.
            g = app.grid; T = app.dispTbl;
            if ~isfield(g, 'theta')
                g.theta = unique(T.Theta); g.phi = unique(T.Phi); g.sz = [numel(g.theta), numel(g.phi)];
                [~, it] = ismember(T.Theta, g.theta); [~, ip] = ismember(T.Phi, g.phi); g.idx = sub2ind(g.sz, it, ip);
                [g.phiGrid, g.thetaGrid] = meshgrid(g.phi, g.theta);
                g.thetaPolar = g.thetaGrid; if app.elevation(), g.thetaPolar = 90 - g.thetaGrid; end
                g.phiRad = deg2rad(g.phiGrid); st = sind(g.thetaPolar);
                g.x = st .* cos(g.phiRad); g.y = st .* sin(g.phiRad); g.z = cosd(g.thetaPolar); g.comp = struct();
            end
            key = matlab.lang.makeValidName(column);
            if ~isfield(g.comp, key), G = nan(g.sz); G(g.idx) = T.(column); g.comp.(key) = G; end
            G = g.comp.(key); app.grid = g;
        end

        function tf = isAR(~, column)
            key = regexprep(lower(strtrim(string(column))), '[^a-z0-9]', '');
            tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
        end

        function r = rangeFor(app, column)
            if app.isAR(column), r = [-30 30]; else, r = app.gainLim; end
        end

        function [limits, map] = plotTheme(app)
            persistent gainMap arMap
            if isempty(gainMap), gainMap = jet(256); arMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
            if app.isAR(app.comp()), limits = [-30 30]; map = arMap; else, limits = app.gainLim; map = gainMap; end
        end

        function applyTheme(app, ax, limits, map)
            clim(ax, limits); colormap(ax, map); app.applyColorbarTicks(colorbar(ax), limits);
        end

        function ticks = axisTicks(app, limits)
            step = app.h.cStep.Value; ticks = [];
            if ~isfinite(step) || step <= 0 || diff(limits) <= 0, return; end
            ticks = unique([limits(1), ceil(limits(1) / step) * step:step:floor(limits(2) / step) * step, limits(2)], 'stable');
            if numel(ticks) > 60, ticks = []; end
        end

        function applyColorbarTicks(app, cbar, limits)
            ticks = app.axisTicks(limits); if ~isempty(ticks), cbar.Ticks = ticks; end
        end

        function r = clampRange(app, values)
            values = sort(double(values(:).')); b = app.DBRange;
            if numel(values) < 2 || any(~isfinite(values(1:2))), r = b; return; end
            r = [max(b(1), values(1)), min(b(2), values(2))];
            if diff(r) < 1, r(2) = min(b(2), r(1) + 1); r(1) = max(b(1), r(2) - 1); end
        end

        function setRange(app, value, mode, scope, applyNow)
            % Synchronize sliders/spinners for "full", "cut" or "all"; mode 0 = both ends, 1 = min, 2 = max.
            if nargin < 5, applyNow = true; end
            H = app.h;
            if scope == "all"
                r = app.clampRange(value); [H.cMin.Value, H.cMax.Value] = deal(r(1), r(2));
                app.setRange(r, 0, "full", applyNow); app.setRange(r, 0, "cut", applyNow); return
            end
            if scope == "full", sliders = [app.full.slider]; mins = [app.full.minSpin]; maxs = [app.full.maxSpin]; r = app.rangeFor(app.comp());
            else, sliders = H.cutSlider; mins = H.cutMin; maxs = H.cutMax; r = app.cutLim; end
            if mode == 0, r = value; else, r(mode) = double(value); end
            r = app.clampRange(r); limits = r;
            if mode ~= 0, limits = [min(sliders(1).Limits(1), r(1)), max(sliders(1).Limits(2), r(2))]; end
            set(sliders, 'Limits', app.DBRange, 'Value', r); set(sliders, 'Limits', limits);
            set(mins, 'Limits', [app.DBRange(1), r(2) - 1], 'Value', r(1)); set(maxs, 'Limits', [r(1) + 1, app.DBRange(2)], 'Value', r(2));
            if scope == "full", if ~app.isAR(app.comp()), app.gainLim = r; end, else, app.cutLim = r; end
            if ~applyNow || isempty(app.viewTbl), return; end
            if scope == "full", app.applyFullRange(r); else, set(H.paxCut, 'RLim', r); set(H.axRect, 'YLim', r); end
            drawnow limitrate
        end

        function applyFullRange(app, limits)
            for s = app.full
                clim(s.axes, limits); if strcmp(s.name, 'rect3D'), zlim(s.axes, limits); end
                cbar = findall(app.UIFigure, 'Type', 'ColorBar', 'Axes', s.axes);
                if ~isempty(cbar), app.applyColorbarTicks(cbar(1), limits); end
            end
        end
    end

    %% ------------------------------------------------------------------ full-pattern renderers
    methods (Access = private)
        function renderAllFull(app)
            if isempty(app.viewTbl), return; end
            for s = app.full
                if app.isClosing, return; end
                app.checkCancelled();
                switch s.name
                    case 'contour',  app.drawContour();
                    case 'circular', app.drawFisheye();
                    case 'sphere3D', app.drawPattern3D(s.axes, "sphere");
                    case 'polar3D',  app.drawPattern3D(s.axes, "polar");
                    case 'rect3D',   app.drawRect3();
                end
            end
            drawnow limitrate                                            % surfaces must exist before DataTips attach
            app.annotatePOB();
        end

        function setTipTemplate(app, S, G)
            g = app.grid; if app.elevation(), tl = "Elevation"; else, tl = "Theta"; end
            rows = [dataTipTextRow(tl, g.thetaGrid, '%.3g°'); dataTipTextRow("Phi", g.phiGrid, '%.3g°'); dataTipTextRow(replace(app.compLabel(), "_", "\_"), G, '%.3g dB')];
            try, S.DataTipTemplate.DataTipRows = rows; catch, end
        end

        function drawContour(app)
            [g, G] = app.gridComp(app.comp()); ax = app.h.axCtr; cla(ax); hold(ax, 'on');
            S = pcolor(ax, g.phi, g.theta, G, 'FaceColor', 'interp', 'LineStyle', 'none', 'Tag', 'APAT_PatternSurface');
            [limits, map] = app.plotTheme(); app.applyTheme(ax, limits, map);
            app.formatAngularAxes(ax, 30, 15); daspect(ax, [1 1 1]);
            title(ax, app.compLabel(), 'Interpreter', 'none'); app.setTipTemplate(S, G);
        end

        function drawFisheye(app)
            [g, G] = app.gridComp(app.comp()); pax = app.h.paxPattern; cla(pax); hold(pax, 'on');
            S = surface(pax, g.phiRad, g.thetaPolar, zeros(g.sz), G, 'EdgeColor', 'none', 'Tag', 'APAT_PatternSurface');
            [limits, map] = app.plotTheme(); app.applyTheme(pax, limits, map);
            app.setPolarTicks(pax); radial = 0:30:180; if app.elevation(), radial = 90 - radial; end
            set(pax, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise', 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', radial));
            title(pax, sprintf('%s  |  r=θ, angle=φ', app.compLabel()), 'Interpreter', 'none', 'FontSize', 9); app.setTipTemplate(S, G);
        end

        function drawPattern3D(app, ax, kind)
            [g, G] = app.gridComp(app.comp()); [limits, map] = app.plotTheme();
            X = g.x; Y = g.y; Z = g.z;
            if kind == "polar"
                r = max(G - limits(1), 0) / max(diff(limits), eps); r = r / max(max(r, [], 'all', 'omitnan'), eps);
                X = r .* X; Y = r .* Y; Z = r .* Z;
            end
            cla(ax); hold(ax, 'on');
            S = surf(ax, X, Y, Z, G, 'EdgeColor', 'none', 'Tag', 'APAT_PatternSurface');
            app.applyTheme(ax, limits, map);
            set(ax, 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1], 'Projection', 'orthographic');
            axis(ax, 'off'); app.drawXYZ(ax); app.apply3DView(ax, [135 25]);
            if app.h.cbOverlay.Value, app.overlayCut3D(ax, kind, limits); end
            title(ax, sprintf('%s  |  θ: %s  |  φ: %s', app.compLabel(), app.h.thetaSpan.Value, app.h.phiSpan.Value), 'Interpreter', 'none');
            app.attachContextMenu(ax); app.setTipTemplate(S, G);
        end

        function drawRect3(app)
            [g, G] = app.gridComp(app.comp()); ax = app.h.ax3dRect; cla(ax); hold(ax, 'on');
            S = surf(ax, g.phiGrid, g.thetaGrid, G, 'EdgeColor', 'none', 'Tag', 'APAT_PatternSurface');
            [limits, map] = app.plotTheme(); app.applyTheme(ax, limits, map); zlim(ax, limits);
            ticks = app.axisTicks(limits); if ~isempty(ticks), ax.ZTick = ticks; end
            app.formatAngularAxes(ax, 60, 30); grid(ax, 'on');
            if app.elevation(), tl = 'Elevation (degree)'; else, tl = 'Theta (degree)'; end
            xlabel(ax, 'Phi (degree)'); ylabel(ax, tl); zlabel(ax, app.compLabel() + " (dB)", 'Interpreter', 'none');
            app.apply3DView(ax, [-35 35]); title(ax, app.compLabel(), 'Interpreter', 'none'); app.setTipTemplate(S, G);
        end

        function drawXYZ(~, ax)
            colors = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            for k = 1:3
                d = 1.35 * double((1:3) == k);
                quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12 * d(1), 1.12 * d(2), 1.12 * d(3), labels{k}, 'Color', colors{k}, 'FontWeight', 'bold');
            end
        end

        function apply3DView(app, ax, defaultView)
            views = struct('top', {0, 90, [0 1 0]}, 'bottom', {0, -90, [0 1 0]}, 'right', {90, 0, [0 0 1]}, 'left', {-90, 0, [0 0 1]}, 'front', {0, 0, [0 0 1]}, 'back', {180, 0, [0 0 1]});
            code = app.h.view3D.Value;
            if isfield(views, code), v = views(1).(code); e = views(2).(code); up = views(3).(code); else, v = defaultView(1); e = defaultView(2); up = [0 0 1]; end
            view(ax, v, e); try, camup(ax, up); catch, end
        end

        function apply3DViews(app)
            if isempty(app.viewTbl), return; end
            app.apply3DView(app.h.ax3dSph, [135 25]); app.apply3DView(app.h.ax3dPol, [135 25]); app.apply3DView(app.h.ax3dRect, [-35 35]);
            drawnow limitrate
        end

        function formatAngularAxes(app, ax, phiStep, thetaStep)
            if app.signedPhi(), xl = [-180 180]; else, xl = [0 360]; end
            if app.elevation(), yl = [-90 90]; dir = 'normal'; else, yl = [0 180]; dir = 'reverse'; end
            set(ax, 'XLim', xl, 'YLim', yl, 'YDir', dir, 'Box', 'on', 'Layer', 'top', 'XTick', xl(1):phiStep:xl(2), 'YTick', yl(1):thetaStep:yl(2));
        end

        function setPolarTicks(app, pax)
            angles = 0:30:330; if app.signedPhi(), angles(angles > 180) = angles(angles > 180) - 360; end
            set(pax, 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', angles));
        end

        function drawOverlay3D(app)
            % Toggle the black cut trace on the two spatial 3-D plots.
            if isempty(app.viewTbl), return; end
            specs = {app.h.ax3dSph, "sphere"; app.h.ax3dPol, "polar"};
            for k = 1:2
                ax = specs{k, 1}; delete(findall(ax, 'Tag', 'APAT_CutOverlay'));
                if app.h.cbOverlay.Value, app.overlayCut3D(ax, specs{k, 2}, app.rangeFor(app.comp())); end
            end
        end

        function overlayCut3D(app, ax, kind, limits)
            [~, data, ~, ~, geom] = app.cutData(); v = data(:, 1);
            if kind == "sphere", r = 1.02; else, r = max(v - limits(1), 0) / max(diff(limits), eps) * 1.01; end
            plot3(ax, r .* sind(geom(:, 1)) .* cosd(geom(:, 2)), r .* sind(geom(:, 1)) .* sind(geom(:, 2)), r .* cosd(geom(:, 1)), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay');
        end
    end

    %% ------------------------------------------------------------------ cuts
    methods (Access = private)
        function onEHPlane(app)
            % E-plane: theta cut through the boresight phi. H-plane: orthogonal principal cut.
            ax = app.PrincipalAxes; k = app.boresightIndex; H = app.h;
            if strcmp(H.ehSwitch.Value, 'E'), H.cutType.Value = 'Theta'; target = ax.phi(k);
            elseif ax.theta(k) == 90, H.cutType.Value = 'Phi'; target = 90;
            else, H.cutType.Value = 'Theta'; target = 90; end
            values = app.updateCutControl(); [~, n] = min(abs(values - target)); H.cutValue.Value = values(n);
            app.onCutChanged();
        end

        function values = updateCutControl(app)
            % Cut value = fixed physical theta (Phi cut) or fixed phi (Theta cut); snaps to available samples.
            H = app.h;
            if strcmp(H.cutType.Value, 'Phi'), values = unique(app.viewTbl.Theta); else, values = unique(mod(app.viewTbl.Phi, 360)); end
            if isempty(values), return; end
            H.cutValue.Limits = [min(values), max(values)];
            if numel(values) > 1, H.cutValue.Step = min(diff(values)); end
            [~, n] = min(abs(values - H.cutValue.Value)); H.cutValue.Value = values(n);
        end

        function onCutBasisChanged(app)
            app.h.cutBasis.UserData = false; app.updateMetadata(); app.onCutChanged();
        end

        function onCutChanged(app, typeChanged)
            if nargin > 1 && typeChanged, app.updateCutControl(); end
            H = app.h; showBounds = H.hpbwBtn.Value;
            H.cbHPBW.Visible = showBounds; if ~showBounds, H.cbHPBW.Value = false; end
            app.plotCut();
            if H.cbOverlay.Value, app.drawOverlay3D(); end
        end

        function [cols, idx] = cutCols(app)
            H = app.h;
            if app.srcUD.isGainOnly, [cols, idx] = deal(string(app.viewTbl.Properties.VariableNames(3)), 1); return; end
            if strcmp(H.cutBasis.Value, 'Linear'), trio = ["E_Total_dB", "E_TH_dB", "E_PH_dB"]; else, trio = ["E_Total_dB", "E_RCP_dB", "E_LCP_dB"]; end
            [H.cbEr.Text, H.cbEl.Text] = deal(char(extractBefore(trio(2), "_dB")), char(extractBefore(trio(3), "_dB")));
            sel = logical([H.cbEt.Value, H.cbEr.Value, H.cbEl.Value]); if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = trio(idx);
        end

        function [ang, data, cols, titleText, geom] = cutData(app)
            % Active cut as one closed circle in the selected span convention; geom = [theta phi] physical.
            T = app.viewTbl; [cols, ~] = app.cutCols(); cutType = app.h.cutType.Value;
            [ang, rows, fixed, sym, snapped, requested] = cutGeometry(T, cutType, app.h.cutValue.Value);
            if snapped, app.setStatus(app.h.status1, sprintf('Requested %s cut @ %s=%g° (snapped to nearest %s=%g°)', cutType, sym, requested, sym, fixed), false); end
            data = T{rows, cellstr(cols)}; geom = [T.Theta(rows), T.Phi(rows)];
            if app.signedPhi(), ang(ang > 180) = ang(ang > 180) - 360; end
            [ang, order] = unique(ang); data = data(order, :); geom = geom(order, :);
            if strcmp(cutType, 'Phi')                                        % close the seam of the circle
                lim = [0 360]; if app.signedPhi(), lim = [-180 180]; end
                hasLo = abs(ang(1) - lim(1)) < 1e-9; hasHi = abs(ang(end) - lim(2)) < 1e-9;
                if hasLo && ~hasHi, ang(end+1) = lim(2); data(end+1, :) = data(1, :); geom(end+1, :) = geom(1, :);
                elseif hasHi && ~hasLo, ang = [lim(1); ang]; data = [data(end, :); data]; geom = [geom(end, :); geom];
                elseif ~hasLo && ~hasHi
                    w = (lim(2) - ang(end)) / max(ang(1) - lim(1) + lim(2) - ang(end), eps);
                    sd = (1 - w) * data(end, :) + w * data(1, :); sg = [(1 - w) * geom(end, 1) + w * geom(1, 1), lim(1)];
                    ang = [lim(1); ang; lim(2)]; data = [sd; data; sd]; geom = [sg; geom; sg];
                end
            end
            if app.srcUD.isGainOnly, titleText = char(string(app.comp())); else, titleText = sprintf('%s cut @ %s = %g°', cutType, sym, fixed); end
        end

        function plotCut(app)
            if isempty(app.viewTbl), return; end
            H = app.h; pax = H.paxCut; ax = H.axRect;
            [ang, data, cols, titleText, ~] = app.cutData(); names = replace(cols, "_", "\_");
            cla(pax); cla(ax); hold(pax, 'on'); hold(ax, 'on');
            limits = app.cutLim; [~, idx] = app.cutCols();
            colors = ax.ColorOrder(1 + mod(idx - 1, size(ax.ColorOrder, 1)), :);
            pLines = polarplot(pax, deg2rad(ang), max(data, limits(1)), 'LineWidth', 1.4);   % clamp keeps polar traces inside RLim
            rLines = plot(ax, ang, data, 'LineWidth', 1.4);
            for k = 1:numel(pLines)
                rows = [dataTipTextRow("Angle", ang, '%.3g°'), dataTipTextRow("Magnitude", data(:, k), '%.3g dB')];
                set([pLines(k), rLines(k)], 'Color', colors(k, :)); pLines(k).DataTipTemplate.DataTipRows = rows; rLines(k).DataTipTemplate.DataTipRows = rows;
            end
            if app.signedPhi(), xl = [-180 180]; else, xl = [0 360]; end
            set(pax, 'ThetaDir', 'clockwise', 'ThetaZeroLocation', 'top', 'RLim', limits, 'RTick', limits(1):5:limits(2)); app.setPolarTicks(pax);
            set(ax, 'YLim', limits, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(ax, [H.cutType.Value ' (degree)']); title(pax, titleText, 'Interpreter', 'none'); title(ax, titleText, 'Interpreter', 'none');
            % Cut peak (POB of the displayed 1-D trace) and HPBW.
            [peak, pk] = max(data(:, 1), [], 'omitnan'); H.hpbwLabel.Text = '';
            if isfinite(peak) && H.cbPOB.Value
                rows = [dataTipTextRow("Angle", ang(pk), '%.3g°'); dataTipTextRow("Magnitude", peak, '%.3g dB')];
                app.marker(pax, deg2rad(ang(pk)), max(peak, limits(1)), [], rows, 'APAT_POB'); app.marker(ax, ang(pk), peak, [], rows, 'APAT_POB');
            end
            if H.hpbwBtn.Value && isfinite(peak)
                [bw, lo, hi] = calcHPBW(ang, data(:, 1), peak, ang(pk));
                if isfinite(bw)
                    if xl(1) < 0, b = mod([lo hi] + 180, 360) - 180; else, b = mod([lo hi], 360); end
                    H.hpbwLabel.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                    if b(1) <= b(2), regions = b; else, regions = [xl(1), b(2); b(1), xl(2)]; end
                    thetaregion(pax, deg2rad(regions(:, 1)), deg2rad(regions(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    xregion(ax, regions(:, 1), regions(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    if H.cbHPBW.Value
                        labels = ["Lower HPBW", "Upper HPBW"];
                        for k = 1:2
                            rows = [dataTipTextRow(labels(k), b(k), '%.2f°'); dataTipTextRow("Gain", peak - 3, '%.2f dB')];
                            app.marker(pax, deg2rad(b(k)), peak - 3, '#D95319', rows, 'APAT_HPBW'); app.marker(ax, b(k), peak - 3, '#D95319', rows, 'APAT_HPBW');
                        end
                    end
                end
            end
            legend(pax, pLines, names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(ax, rLines, names, 'Location', 'best');
            app.syncAnnotationVisibility();
        end
    end

    %% ------------------------------------------------------------------ annotations (tag based)
    methods (Access = private)
        function marker(app, ax, x, y, color, rows, tag, z)
            % One filled marker + pinned DataTip, both carrying TAG. Errors never break rendering.
            if isempty(color), color = 'k'; end
            try
                if isa(ax, 'matlab.graphics.axis.PolarAxes'), m = polarplot(ax, x, y, 'o');
                elseif nargin >= 8, m = plot3(ax, x, y, z, 'o', 'Clipping', 'off');
                else, m = plot(ax, x, y, 'o'); end
                set(m, 'MarkerSize', 5, 'Color', color, 'MarkerFaceColor', color, 'HandleVisibility', 'off', 'Tag', tag);
                m.DataTipTemplate.DataTipRows = rows;
                tip = datatip(m, 'DataIndex', 1, 'FontSize', 9, 'Tag', tag, 'HandleVisibility', 'off');
                if isequal(ax, app.h.axCtr) && abs(y - ax.YLim(1 + strcmp(ax.YDir, 'normal'))) <= diff(ax.YLim) / 1000
                    if x <= mean(ax.XLim), tip.Location = 'southeast'; else, tip.Location = 'southwest'; end
                end
            catch ME
                if ~app.isClosing, warning('APAT:Annotation', 'Could not create annotation: %s', ME.message); end
            end
        end

        function annotatePOB(app)
            % Full-pattern POB markers at the display-grid cell nearest the physical peak.
            for s = app.full, delete(findall(s.axes, 'Tag', 'APAT_POB')); end
            if ~app.h.cbPOB.Value || isempty(app.viewTbl) || ~isfinite(app.POBth), return; end
            g = app.grid; if ~isfield(g, 'theta'), return; end
            [th, ph] = app.toDisplay(app.POBth, app.POBph);
            [~, r] = min(abs(g.theta - th)); [~, c] = min(abs(g.phi - ph));
            if app.elevation(), tl = "Elevation"; else, tl = "Theta"; end
            for s = app.full
                S = findobj(s.axes, 'Tag', 'APAT_PatternSurface'); if isempty(S), continue; end
                S = S(1); G = S.CData; if isempty(G), G = S.ZData; end
                rows = [dataTipTextRow(tl, g.theta(r), '%.3g°'); dataTipTextRow("Phi", g.phi(c), '%.3g°'); dataTipTextRow(app.compLabel(), G(r, c), '%.3g dB')];
                X = S.XData; Y = S.YData; Z = S.ZData;
                if isvector(X), x = X(c); y = Y(r); else, x = X(r, c); y = Y(r, c); end
                if isempty(Z) || isscalar(Z), z = 0; else, z = Z(r, c); end
                app.marker(s.axes, x, y, [], rows, 'APAT_POB', z);
            end
            app.syncAnnotationVisibility();
        end

        function onPOBToggled(app)
            if isempty(app.viewTbl), return; end
            app.annotatePOB(); app.plotCut();
        end

        function syncAnnotationVisibility(app)
            % POB follows its checkbox; HPBW bound tips are shown only on the selected cut tab.
            H = app.h; if app.isClosing, return; end
            set(findall(app.UIFigure, 'Tag', 'APAT_POB'), 'Visible', H.cbPOB.Value);
            set(findall(H.tabPolar, 'Tag', 'APAT_HPBW'), 'Visible', H.cbHPBW.Value && H.tabCut.SelectedTab == H.tabPolar);
            set(findall(H.tabRect, 'Tag', 'APAT_HPBW'), 'Visible', H.cbHPBW.Value && H.tabCut.SelectedTab == H.tabRect);
        end
    end

    %% ------------------------------------------------------------------ coverage: sources & nodes
    methods (Access = private)
        function onCoverageFromMain(app)
            % Coverage always receives the CURRENT physical view table (step/loss/component state included).
            if isempty(app.viewTbl), uialert(app.UIFigure, 'No processed View Table is available. Load and process a pattern first.', 'Coverage'); return; end
            H = app.h; [H.tabGroup.SelectedTab, H.covPath.Value] = deal(H.tabCov, app.filePath);
            node = app.covFindByPath(app.filePath);
            if isempty(node), app.covAddPattern(app.baseName, app.viewTbl, app.filePath);
            else, app.covSyncFromView(node); H.covTree.SelectedNodes = node; app.setCoverageUI(); end
            app.setStatus(H.covStatus, 'Coverage source synchronized from the current Main-tab View Table.', false);
        end

        function onCovLoad(app)
            H = app.h; fp = strtrim(H.covPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFindByPath(fp))
                [f, p] = uigetfile(app.FileFilter, 'Select a pattern or coverage results file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            existing = app.covFindByPath(fp);
            if ~isempty(existing)
                H.covTree.SelectedNodes = existing; app.onCovTreeSelection(); H.covPath.Value = fp; app.setCoverageUI();
                app.setStatus(H.covStatus, 'File already loaded -- node selected. Add another job or load a different file.', true); return
            end
            H.covPath.Value = fp;
            out = app.prepareTextFormat(fp, H.covFormatLabel, H.covFormatDD);
            if out.userData.isCoverage
                target = app.covPatternTarget(); if ~isempty(target), H.covPath.Value = target.NodeData.path; end
                app.covLoadResults(fp, out.rawTbl);
            else
                [~, name] = fileparts(fp); app.covAddPattern(name, app.buildPattern(out), fp);
            end
            H.covResults.Visible = 'on';
        end

        function onCovTextFormatChanged(app)
            % Re-interpret an existing generic coverage-pattern node with the newly selected format.
            fp = strtrim(app.h.covPath.Value); old = app.covFindByPath(fp);
            if isempty(old) || ~app.isGenericText(fp), return; end
            out = readPattern(fp, app.h.covFormatDD.Value);
            if out.userData.isCoverage, app.setStatus(app.h.covStatus, 'Coverage-result format is detected automatically; no pattern reprocessing required.', true); return; end
            name = old.NodeData.name; app.deleteJobs(app.covNodes('job', old)); delete(old);
            app.covAddPattern(name, app.buildPattern(out), fp); app.covRebuild();
            app.setStatus(app.h.covStatus, sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
        end

        function pattern = buildPattern(app, out)
            % Auxiliary processed pattern (block 1) without touching the Main view.
            standard = normalizePattern(out.blocks{1}); standard.Properties.UserData = out.userData;
            pattern = calcPattern(standard, app.getParam(), app.PeakPercentile, app.PeakMaxExcessDB);
        end

        function node = covAddPattern(app, name, pattern, fp)
            H = app.h; node = uitreenode(H.covRoot, 'Text', ['📡 ' name]);
            node.NodeData = struct('kind', 'pattern', 'name', name, 'path', fp, 'pattern', pattern, 'solidAngle', solidWeights(pattern.Theta, pattern.Phi), 'revision', 0, 'cache', struct());
            expand(H.covTree); [H.covTree.CheckedNodes, H.covTree.SelectedNodes] = deal([H.covTree.CheckedNodes; node], node);
            app.syncCoveragePattern(node);
            set([H.covComputeBtn, H.covResetBtn, H.covComp, H.covCompLabel], 'Enable', 'on'); app.setCoverageUI();
            app.setStatus(H.covStatus, sprintf('Pattern "<b>%s</b>" added %s ready to compute coverage.', name, char(8212)), false);
        end

        function covSyncFromView(app, node)
            d = node.NodeData; d.pattern = app.viewTbl; d.solidAngle = solidWeights(app.viewTbl.Theta, app.viewTbl.Phi);
            d.revision = d.revision + 1; d.name = app.baseName; d.cache = struct(); node.NodeData = d;
            app.syncCoveragePattern(node);
        end

        function syncCoveragePattern(app, node)
            % Align the component selector, boresight detection and threshold preset with the node.
            H = app.h; d = node.NodeData; [columns, labels] = app.componentMap(d.pattern);
            if isfield(d, 'component'), previous = d.component; else, previous = H.covComp.Value; end
            component = app.preferredComponent(previous, columns);
            if ~isequal(string(H.covComp.ItemsData), columns), [H.covComp.Items, H.covComp.ItemsData] = deal(cellstr(labels), cellstr(columns)); end
            H.covComp.Value = component;
            changed = ~isfield(d, 'component') || ~strcmp(d.component, component);
            if changed
                [~, d.boresightIndex] = calcOrientation(d.pattern, d.solidAngle, component, app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
                d.component = component; node.NodeData = d;
            end
            key = sprintf('%s|%s|%d', d.path, component, d.revision);
            if app.covPresetKey ~= string(key)                                  % automatic preset only when pattern/component/view changes
                app.covPresetKey = string(key); b = peakWindow(d.pattern.(component), app.PeakPercentile, app.PeakMaxExcessDB);
                if ~isempty(app.covNodes('job')), b = [min(H.thrMin.Value, b(1)), max(H.thrMax.Value, b(2))]; end
                H.thrMin.Limits = [app.DBRange(1), b(2) - 0.1]; H.thrMax.Limits = [b(1) + 0.1, app.DBRange(2)];
                [H.thrMin.Value, H.thrMax.Value] = deal(b(1), b(2));
            end
            if changed && H.covOrient.Value == 0, app.onCovOrientationChanged(); end
        end

        function node = covPatternTarget(app)
            % Selected pattern node (or the pattern owning the selected job), else the most recent pattern.
            node = []; sel = app.h.covTree.SelectedNodes;
            if ~isempty(sel)
                n = sel(1);
                while isa(n, 'matlab.ui.container.TreeNode')
                    if isstruct(n.NodeData) && strcmp(n.NodeData.kind, 'pattern'), node = n; return; end
                    n = n.Parent;
                end
            end
            patterns = app.covNodes('pattern'); if ~isempty(patterns), node = patterns(end); end
        end

        function node = covFindByPath(app, fp)
            node = []; kids = app.h.covRoot.Children;
            for k = 1:numel(kids)
                if isstruct(kids(k).NodeData) && isfield(kids(k).NodeData, 'path') && strcmp(kids(k).NodeData.path, fp), node = kids(k); return; end
            end
        end

        function nodes = covNodes(app, kind, root)
            % All tree nodes of KIND under ROOT (default: whole tree), jobs ordered by run id.
            if nargin < 3, root = app.h.covRoot; end
            nodes = findobj(root);
            nodes = nodes(arrayfun(@(n) isstruct(n.NodeData) && isfield(n.NodeData, 'kind') && strcmp(n.NodeData.kind, kind), nodes));
            if strcmp(kind, 'job') && numel(nodes) > 1, [~, order] = sort(arrayfun(@(n) n.NodeData.id, nodes)); nodes = nodes(order); end
        end

        function checked = covChecked(app, jobs)
            checked = jobs(ismember(jobs, app.h.covTree.CheckedNodes));
        end
    end

    %% ------------------------------------------------------------------ coverage: jobs, compute, table
    methods (Access = private)
        function jobNode = covAddJob(app, parent, thresholds, coverage, tag, component, label, meta)
            if nargin < 8, meta = struct(); end
            app.covRunID = app.covRunID + 1; icon = '📉'; if strcmp(tag, 'Res'), icon = '📈'; end
            text = sprintf('%s R%d %s %s %s', icon, app.covRunID, label, char(183), component);
            line = plot(app.h.covAxes, thresholds, coverage, 'LineWidth', 1.6, 'DisplayName', text);
            [invCov, invRows] = unique(coverage, 'last');
            jobNode = uitreenode(parent, 'Text', text);
            d = struct('kind', 'job', 'id', app.covRunID, 'tag', tag, 'thr', thresholds(:), 'cov', coverage(:), 'invCov', invCov, 'invThr', thresholds(invRows), ...
                'line', line, 'label', text, 'tableTag', label, 'isConical', false, 'orientationLabel', "n/a", ...
                'thresholdMin', thresholds(1), 'thresholdMax', thresholds(end), 'thresholdStep', gridStep(thresholds), 'coneTheta', NaN, 'conePhi', NaN, 'coneAngle', NaN);
            for f = string(fieldnames(meta))', d.(f) = meta.(f); end
            jobNode.NodeData = d;
        end

        function deleteJobs(app, jobs)
            for j = jobs(:)'
                if isgraphics(j.NodeData.line), delete(findall(j.NodeData.line, 'Type', 'datatip')); delete(j.NodeData.line); end
                delete(findall(app.h.covAxes, 'Tag', sprintf('CovQ_%d', j.NodeData.id)));
            end
        end

        function covLoadResults(app, fp, T)
            H = app.h; [~, name] = fileparts(fp);
            node = uitreenode(H.covRoot, 'Text', ['📄 ' name]); node.NodeData = struct('kind', 'results', 'name', name, 'path', fp);
            thresholds = T{:, 1}; n = width(T) - 1; jobs = cell(n, 1);
            for k = 1:n, jobs{k} = app.covAddJob(node, thresholds, T{:, k + 1}, 'Res', T.Properties.VariableNames{k + 1}, 'Res'); end
            step = gridStep(thresholds); if isfinite(step) && step < H.thrStep.Value, H.thrStep.Value = step; end
            H.covTree.CheckedNodes = [H.covTree.CheckedNodes; node; vertcat(jobs{:})]; expand(node);
            app.setCovXRange([min(thresholds), max(thresholds)], true); app.covRebuild(); H.covResults.Visible = 'on';
            app.setStatus(H.covStatus, sprintf('Coverage results file "%s" loaded (%d curves).', name, n), false);
        end

        function thresholds = covThresholds(app)
            % Current threshold controls verbatim (presets are applied only on pattern/component/view change).
            H = app.h; tMin = H.thrMin.Value; tMax = H.thrMax.Value; step = max(H.thrStep.Value, 0.1);
            if tMax <= tMin, tMax = min(app.DBRange(2), tMin + step); H.thrMax.Value = tMax; end
            thresholds = (tMin:step:tMax)'; if isempty(thresholds) || thresholds(end) < tMax, thresholds(end+1, 1) = tMax; end
        end

        function onCovCompute(app)
            H = app.h; node = app.covPatternTarget();
            if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if ~isempty(app.viewTbl) && strcmp(node.NodeData.path, app.filePath), app.covSyncFromView(node); end   % Main pattern → current view
            finish = onCleanup(app.startPerf("Compute coverage")); %#ok<NASGU>
            d = node.NodeData; T = d.pattern; component = H.covComp.Value; thresholds = app.covThresholds();
            conical = H.covConical.Value; meta = struct('isConical', conical, 'thresholdMin', thresholds(1), 'thresholdMax', thresholds(end), 'thresholdStep', gridStep(thresholds));
            if conical
                orientationIndex = H.covOrient.Value; if orientationIndex == 0, orientationIndex = d.boresightIndex; end
                th0 = H.coneTh.Value; ph0 = mod(H.conePh.Value, 360); alpha = H.coneAng.Value;
                region = cosd(T.Theta) .* cosd(th0) + sind(T.Theta) .* sind(th0) .* cosd(T.Phi - ph0) >= cosd(alpha);
                center = app.coneCenterLabel(th0, ph0);
                tag = sprintf('Con_%.15g_%.15g_%.15g', th0, ph0, alpha); label = sprintf('Conical coverage (%s) α=%s°', center, app.fmt(alpha));
                meta.tableTag = sprintf('Con %s α%s°', erase(center, ["=", ","]), app.fmt(alpha)); meta.orientationLabel = string(app.PrincipalAxes.labels{orientationIndex});
                meta.coneTheta = th0; meta.conePhi = ph0; meta.coneAngle = alpha;
            else
                region = true(height(T), 1); tag = 'Sph'; label = 'Sph coverage'; meta.tableTag = 'Sph';
            end
            key = matlab.lang.makeValidName(sprintf('%s_%s_%g_%g_%g_%d', component, tag, thresholds(1), thresholds(end), gridStep(thresholds), numel(thresholds)));
            hit = isfield(d.cache, key);
            if hit, coverage = d.cache.(key); else, coverage = coverageCCDF(T.(component), region, thresholds, d.solidAngle); d.cache.(key) = coverage; node.NodeData = d; end
            job = app.covAddJob(node, thresholds, coverage, tag, component, label, meta);
            H.covTree.CheckedNodes = [H.covTree.CheckedNodes; job]; expand(node);
            app.covRebuild(); app.setCovXRange([thresholds(1), thresholds(end)], true); H.covResults.Visible = 'on';
            if hit, action = 'reused cached CCDF'; else, action = 'computed'; end
            status = sprintf('Run-<b>%d</b> %s: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', app.covRunID, action, label, d.name, component, numel(thresholds));
            if conical, status = sprintf('%s | Orientation <b>%s</b>', status, meta.orientationLabel); end
            app.setStatus(H.covStatus, status, false);
        end

        function covRebuild(app)
            % Checked jobs drive line visibility, legend and the results table together.
            H = app.h; jobs = app.covNodes('job'); checked = app.covChecked(jobs);
            for j = jobs(:)'
                on = ismember(j, checked); d = j.NodeData; d.line.Visible = on;
                set([findall(d.line, 'Type', 'datatip'); findall(H.covAxes, 'Tag', sprintf('CovQ_%d', d.id))], 'Visible', on);
            end
            if isempty(checked), legend(H.covAxes, 'off'); H.covTable.Data = table(); app.setCoverageUI(); return; end
            field = @(name) arrayfun(@(n) n.NodeData.(name), checked, 'UniformOutput', false);
            lines = field('line'); thrs = field('thr');
            legend(H.covAxes, [lines{:}], field('label'), 'Location', 'southwest', 'Interpreter', 'none');
            thr = unique(vertcat(thrs{:})); values = nan(numel(thr), numel(checked) + 1); values(:, 1) = thr; names = cell(1, numel(checked) + 1); names{1} = 'Threshold (dB)';
            for k = 1:numel(checked)
                d = checked(k).NodeData; values(:, k + 1) = interp1(d.thr, d.cov, thr, 'linear', NaN); names{k + 1} = sprintf('R%d %s %%', d.id, d.tableTag);
            end
            H.covTable.Data = array2table(compose('%.2f', values), 'VariableNames', names);
            expand(H.covRoot); app.setCoverageUI();
        end

        function setCoverageUI(app, mode)
            H = app.h;
            if nargin < 2
                if ~isempty(app.covPatternTarget()), mode = "pattern"; elseif ~isempty(app.covNodes('job')), mode = "results"; else, mode = "empty"; end
            end
            hasResults = ~isempty(app.covNodes('job'));
            kids = H.covParamGrid.Children;
            if mode == "pattern"
                set(kids, 'Visible', 'on', 'Enable', 'on');
                set([H.covExportBtn, H.covClearBtn, H.covQueryCtl], 'Enable', hasResults);
                app.onCovTypeChanged(); set([H.covFormatLabel, H.covFormatDD], 'Visible', app.isGenericText(H.covPath.Value), 'Enable', app.isGenericText(H.covPath.Value)); return
            end
            set(kids, 'Visible', 'off', 'Enable', 'off');
            shown = [H.covPathLabel, H.covPath, H.covLoadBtn, H.covComputeBtn];
            if mode == "results", shown = [shown, H.covQueryCtl, H.covResetBtn, H.covExportBtn, H.covClearBtn, H.covToMainBtn]; end
            set(shown, 'Visible', 'on', 'Enable', 'on'); H.covComputeBtn.Enable = 'off';
        end

        function onCovReset(app)
            H = app.h; app.deleteJobs(app.covNodes('job')); delete(H.covRoot.Children);
            delete(findall(H.covAxes, 'Type', 'datatip')); cla(H.covAxes); legend(H.covAxes, 'off');
            hold(H.covAxes, 'on'); grid(H.covAxes, 'on'); set(H.covAxes, 'YLim', [0 100], 'Box', 'on', 'Layer', 'top', 'XLimMode', 'auto');
            [H.covTable.Data, app.covRunID, app.covPresetKey, app.covPlotInit] = deal(table(), 0, "", false);
            set([H.xMin, H.xMax], 'Limits', app.DBRange); [H.xMin.Value, H.xMax.Value] = deal(-40, 10); set(H.xRange, 'Limits', app.DBRange, 'Value', [-40 10]);
            H.covResults.Visible = 'off'; app.setCoverageUI("empty");
            app.setStatus(H.covStatus, 'Coverage workspace reset 🔄', true);
        end

        function onCovClear(app)
            sel = app.h.covTree.SelectedNodes;
            if isempty(sel), app.setStatus(app.h.covStatus, 'Select a node to clear.', true); return; end
            jobs = app.covNodes('job', sel(1));
            if isempty(jobs), app.setStatus(app.h.covStatus, 'No coverage results under selected node.', true); return; end
            for j = jobs(:)'
                delete(findall(j.NodeData.line, 'Type', 'datatip')); delete(findall(app.h.covAxes, 'Tag', sprintf('CovQ_%d', j.NodeData.id)));
            end
            app.setStatus(app.h.covStatus, 'Selected DataTips and query markers cleared.', true);
        end

        function onCovExport(app)
            if isempty(app.h.covTable.Data), return; end
            [f, p] = uiputfile(app.ExportFilter, 'Export Coverage Results', fullfile(app.folderPath, 'coverage_results.csv'));
            if isequal(f, 0), return; end
            app.writeTable(app.h.covTable.Data, fullfile(p, f));
            app.setStatus(app.h.covStatus, ['Coverage results exported to ' fullfile(p, f)], true);
        end
    end

    %% ------------------------------------------------------------------ coverage: orientation, queries, ranges
    methods (Access = private)
        function onCovTypeChanged(app)
            H = app.h; conical = H.covConical.Value;
            set([H.coneTh, H.conePh, H.coneAng, H.coneThLabel, H.conePhLabel, H.coneAngLabel, H.covOrient, H.covOrientLabel], 'Enable', conical, 'Visible', conical);
            if conical
                node = app.covPatternTarget(); if ~isempty(node), app.syncCoveragePattern(node); end
                app.reportOrientation();
            else
                H.covStatus.Text = regexprep(char(H.covStatus.Text), '\s*\|\s*Orientation <b>.*?</b>', '');
            end
        end

        function index = resolvedOrientation(app)
            index = app.h.covOrient.Value;
            if index == 0
                node = app.covPatternTarget();
                if isempty(node) || ~isfield(node.NodeData, 'boresightIndex'), index = NaN; else, index = node.NodeData.boresightIndex; end
            end
        end

        function reportOrientation(app)
            % Append the resolved conical orientation to the current Coverage status.
            index = app.resolvedOrientation(); if ~app.h.covConical.Value || ~isfinite(index), return; end
            base = regexprep(char(app.h.covStatus.Text), '\s*\|\s*Orientation <b>.*?</b>$', '');
            app.setStatus(app.h.covStatus, sprintf('%s | Orientation <b>%s</b>', base, app.PrincipalAxes.labels{index}), false);
        end

        function onCovOrientationChanged(app)
            % Auto fills the cone centre from the detected axis; explicit choices are authoritative.
            index = app.resolvedOrientation(); if ~isfinite(index), return; end
            [app.h.coneTh.Value, app.h.conePh.Value] = deal(app.PrincipalAxes.theta(index), app.PrincipalAxes.phi(index));
            app.reportOrientation();
        end

        function onCovComponentChanged(app)
            node = app.covPatternTarget(); if isempty(node), return; end
            d = node.NodeData; component = app.h.covComp.Value;
            if ~ismember(component, d.pattern.Properties.VariableNames), return; end
            [~, d.boresightIndex] = calcOrientation(d.pattern, d.solidAngle, component, app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
            d.component = component; node.NodeData = d; app.reportOrientation();
        end

        function label = coneCenterLabel(app, theta, phi)
            % Principal-axis name when the centre coincides with ±X/±Y/±Z, else explicit angles.
            ax = app.PrincipalAxes; v = [sind(theta) * cosd(phi), sind(theta) * sind(phi), cosd(theta)];
            A = [sind(ax.theta(:)) .* cosd(ax.phi(:)), sind(ax.theta(:)) .* sind(ax.phi(:)), cosd(ax.theta(:))];
            k = find(A * v(:) >= 1 - 1e-9, 1);
            if isempty(k), label = sprintf('θ=%s°, φ=%s°', app.fmt(theta), app.fmt(phi)); else, label = string(ax.labels{k}); end
        end

        function [thr, cov] = covQueryPoint(~, d, mode, q)
            if mode == "cov", thr = q; cov = interp1(d.thr, d.cov, q, 'linear', NaN);
            else, cov = q; thr = interp1(d.invCov, d.invThr, q, 'linear', NaN); end
        end

        function covQuery(app, mode)
            % Project a threshold→coverage (cov) or coverage→threshold (thr) query on every checked job under the selection.
            H = app.h; ax = H.covAxes; sel = H.covTree.SelectedNodes;
            if mode == "cov", q = H.qCov.Value; else, q = H.qThr.Value; end
            if isempty(sel), app.setStatus(H.covStatus, 'Select a node to query.', true); return; end
            jobs = app.covChecked(app.covNodes('job', sel(1)));
            if isempty(jobs), app.setStatus(H.covStatus, 'No checked results under selected node.', true); return; end
            fmtDB = @(v) sprintf('%s dB', app.fmt(v)); fmtPct = @(v) sprintf('%s%%', app.fmt(v));
            rows = [dataTipTextRow("Threshold", @(x, ~) arrayfun(fmtDB, x, 'UniformOutput', false)); dataTipTextRow("Coverage", @(~, y) arrayfun(fmtPct, y, 'UniformOutput', false))];
            hit = false;
            for j = jobs(:)'
                d = j.NodeData; tag = sprintf('CovQ_%d', d.id);
                delete([findall(ax, 'Tag', tag); findall(d.line, 'Tag', tag)]);
                try, d.line.DataTipTemplate.DataTipRows = rows; catch, end
                [x, y] = app.covQueryPoint(d, mode, q);
                if ~isfinite(x) || ~isfinite(y), continue; end
                line(ax, [x x], [ax.YLim(1) y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [app.DBRange(1) x], [y y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'HandleVisibility', 'off', 'FontSize', 9, 'Tag', tag);   % exact interpolated point
                hit = true;
            end
            if ~hit, app.setStatus(H.covStatus, 'Query value is outside selected checked range.', true);
            elseif mode == "cov", app.setStatus(H.covStatus, sprintf('Coverage queried at %s.', fmtDB(q)), false);
            else, app.setStatus(H.covStatus, sprintf('Threshold queried at %s coverage.', fmtPct(q)), false); end
        end

        function onCovTreeChecked(app), app.covRebuild(); end

        function onCovTreeSelection(app)
            H = app.h; sel = H.covTree.SelectedNodes; jobs = app.covNodes('job');
            for j = jobs(:)', d = j.NodeData; d.line.LineWidth = 1.6 + 1.0 * (~isempty(sel) && isequal(j, sel(1))); end   % emphasis only
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(H.covStatus, 'Ready.', false); return; end
            d = sel(1).NodeData; target = app.covPatternTarget(); if ~isempty(target), app.syncCoveragePattern(target); end
            if ~strcmp(d.kind, 'job')
                n = numel(sel(1).Children); kind = 'Pattern'; if strcmp(d.kind, 'results'), kind = 'Results'; end
                app.setStatus(H.covStatus, sprintf('%s <b>"%s"</b> -- <b>%d</b> coverage job%s.', kind, d.name, n, repmat('s', 1, n ~= 1)), false);
                if strcmp(d.kind, 'pattern') && H.covConical.Value, app.reportOrientation(); end
                return
            end
            parts = {char(d.label)};
            if d.isConical && d.orientationLabel ~= "n/a", parts{end+1} = sprintf('Orientation <b>%s</b>', d.orientationLabel); end
            if isfield(d, 'thresholdMin'), parts{end+1} = sprintf('Threshold [%s, %s] dB | Step %s dB', app.fmt(d.thresholdMin), app.fmt(d.thresholdMax), app.fmt(d.thresholdStep)); end
            shown = round(d.cov, 2); [mx, k] = max(shown); k = find(shown == mx, 1, 'last');
            if isfinite(mx), maxText = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', app.fmt(mx), app.fmt(d.thr(k))); else, maxText = 'max <b>n/a</b>'; end
            [thr50, cov50] = app.covQueryPoint(d, "thr", 50);
            if isfinite(thr50), mid = sprintf('<b>%s%%</b>-coverage threshold <b>%s dB</b>', app.fmt(cov50), app.fmt(thr50)); else, mid = '<b>50%-coverage unavailable</b>'; end
            app.setStatus(H.covStatus, sprintf('%s | %s | %s', strjoin(parts, ' | '), mid, maxText), false);
        end

        function setCovXRange(app, bounds, expandOnly)
            % Plot X-range: the first result sets the baseline; later results may only widen it.
            H = app.h; b = app.clampRange(bounds);
            if expandOnly && app.covPlotInit, b = [min(H.covAxes.XLim(1), b(1)), max(H.covAxes.XLim(2), b(2))]; end
            app.covPlotInit = true; set(H.covAxes, 'XLimMode', 'manual', 'XLim', b);
            set(H.xRange, 'Limits', app.DBRange, 'Value', b); H.xRange.Limits = b;
            set([H.xMin, H.xMax], 'Limits', app.DBRange); [H.xMin.Value, H.xMax.Value] = deal(b(1), b(2));
            H.xMin.Limits = [app.DBRange(1), b(2) - 0.1]; H.xMax.Limits = [b(1) + 0.1, app.DBRange(2)];
        end

        function onCovXRange(app, fromSlider, liveValue)
            % Spinners are the master range (they define slider travel); the slider only selects within it.
            H = app.h;
            if fromSlider
                if nargin < 3, liveValue = H.xRange.Value; end
                v = sort(double(liveValue)); if diff(v) <= 0, return; end
                [H.xMin.Value, H.xMax.Value] = deal(v(1), v(2)); set(H.covAxes, 'XLimMode', 'manual', 'XLim', v); return
            end
            app.setCovXRange([H.xMin.Value, H.xMax.Value], false);
        end
    end

    %% ------------------------------------------------------------------ status, errors, diagnostics
    methods (Access = private)
        function setStatus(app, label, message, temporary)
            % Persistent messages are remembered in UserData; temporary ones revert after 3 s.
            if app.isClosing || ~isgraphics(label), return; end
            app.stopStatusTimer(); label.Text = char(message);
            if ~temporary, label.UserData = char(message); return; end
            app.statusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, 'TimerFcn', @(t, ~) app.restoreStatus(label), 'StopFcn', @(t, ~) delete(t));
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

        function showError(app, ME, titleText)
            if app.isClosing || ~isvalid(app.UIFigure), return; end
            where = ''; if ~isempty(ME.stack), where = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.UIFigure, [ME.message where], titleText, 'Icon', 'error');
        end

        function checkCancelled(app)
            dlg = app.operationDialog;
            if ~isempty(dlg) && isvalid(dlg) && dlg.CancelRequested
                dlg.Message = 'Aborting...'; drawnow limitrate; error('APAT:Cancelled', 'Operation cancelled by user.');
            end
        end

        function endPerf = startPerf(app, operation)
            % Stage timer; results land in base workspace variable Perf_<class> when the operation ends.
            stages = cell(0, 2); stageTimer = tic; total = tic; app.perfTracker = @track; endPerf = @save;
            function track(stage), stages(end+1, :) = {string(stage), toc(stageTimer)}; stageTimer = tic; end
            function save()
                perf = struct('AppVersion', app.ReleaseVersion, 'Operation', string(operation), 'Stages', cell2table(stages, 'VariableNames', {'Stage', 'Seconds'}), 'TotalSeconds', toc(total));
                assignin('base', matlab.lang.makeValidName("Perf_" + string(class(app))), perf); app.perfTracker = @(~) [];
            end
        end
    end

    %% ------------------------------------------------------------------ self test
    methods (Access = public)
        function report = runSelfTest(app)
            %RUNSELFTEST Deterministic numerical smoke checks (no UI interaction required).
            [p, t] = meshgrid(0:30:330, 0:30:180);
            T = table(t(:), p(:), 10 * cosd(t(:)).^2, 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'});
            w = solidWeights(T.Theta, T.Phi); report.solidAngleError = abs(sum(w) - 4 * pi);
            [peak, axisIndex] = calcOrientation(T, w, 'E_Total_dB', app.PrincipalAxes, app.PeakPercentile, app.PeakMaxExcessDB);
            report.passSolidAngle = report.solidAngleError < 1e-9;
            report.passOrientation = isfinite(peak.value) && axisIndex == 1;
            % Resampling: regular 2° grid → 1° canonical grid, exact on native samples.
            [p2, t2] = meshgrid(0:2:358, 0:2:180); analytic = 12 * cosd(t2).^2 - 0.5 * sind(p2).^2;
            R = resampleCanonical(table(t2(:), p2(:), analytic(:), 'VariableNames', {'Theta', 'Phi', 'E_Total_dB'}), 1);
            native = mod(R.Theta, 2) == 0 & mod(R.Phi, 2) == 0 & R.Phi < 360;
            report.numericalError = max(abs(R.E_Total_dB(native) - (12 * cosd(R.Theta(native)).^2 - 0.5 * sind(R.Phi(native)).^2)));
            report.passResampling = height(R) == 181 * 361 && report.numericalError < 1e-10;
            % Peak policy and 50-dB display window.
            spike = repmat(0.02, 100000, 1); spike(1) = 10.02; pk = resolvePeak(spike, app.PeakPercentile, app.PeakMaxExcessDB);
            report.passIsolatedSpike = pk.wasAdjusted && abs(pk.value - 0.02) < 1e-12 && pk.rawIndex == 1;
            report.passPeakWindow = isequal(peakWindow([3.2; -250; -17], app.PeakPercentile, app.PeakMaxExcessDB), [-45 5]) && isequal(peakWindow(spike, app.PeakPercentile, app.PeakMaxExcessDB), [-45 5]);
            % Coverage CCDF: uniform gain is fully covered below it and uncovered above it.
            cov = coverageCCDF(5 * ones(height(T), 1), true(height(T), 1), [0; 5; 10], w);
            report.passCoverage = isequal(round(cov), [100; 0; 0]);
            % HPBW of a cos^2 pattern in dB (10*log10(cos^2)) → -3 dB at ±45°.
            ang = (0:359)'; g = 20 * log10(max(abs(cosd(ang)), 1e-6)); bw = calcHPBW(ang, g, 0, 0);
            report.passHPBW = abs(bw - 90) < 1;
            % FFD header contract.
            ffd = [tempname '.ffd']; fid = fopen(ffd, 'w'); c = onCleanup(@() delete(ffd));
            fprintf(fid, '0 180 3\n-180 180 3\n'); fprintf(fid, '%d 0 0 1\n', 1:9); fclose(fid);
            out = readPattern(ffd, 'ffd'); report.passFFDReader = out.userData.source == "HFSS FFD" && height(out.blocks{1}) == 9;
            report.passARSemantic = all(arrayfun(@(s) app.isAR(s), ["AR", "AR_dB", "AR dB", "Axial Ratio", "Axial_Ratio"]));
            names = fieldnames(report); flags = names(startsWith(names, 'pass'));
            report.pass = all(cellfun(@(f) report.(f), flags));
            if ~report.pass
                error('apat:test:SelfTestFailed', 'Self-test failed: %s', strjoin(flags(~cellfun(@(f) report.(f), flags)), ', '));
            end
        end
    end
end

%% ====================================================================== local functions: I/O
function out = readPattern(fp, textFormat, tableData)
%READPATTERN Parse any APAT-supported source into {rawTbl, blocks, freqs, userData}.
%   blocks{k} is a canonical table {Theta,Phi,Re_Eth,Im_Eth,Re_Eph,Im_Eph} (E-field) or
%   {Theta,Phi,<gain columns>} (gain-only). Coverage-result files return rawTbl only.
if nargin < 3, tableData = table(); end
textFormat = string(textFormat);
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, 'userData', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'isMultiBlock', false, 'hasFrequency', false));
switch ext
    case {'XLSX', 'XLS'}
        out = readExcelMatrix(fp);
    case {'CSV', 'TXT', 'DAT'}
        out = readGenericText(fp, textFormat, tableData, out);
    case 'CUT'
        out = readGraspCut(fp, out);
    otherwise
        [nHdr, ffd] = findHeaderLines(fp);
        opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
        M = readmatrix(fp, setvartype(opts, opts.VariableNames, 'double'));
        M = M(~all(isnan(M), 2), 1:min(size(M, 2), 6));
        switch ext
            case {'FZ', 'UAN'}  % Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
                out.userData.source = ['XGTD ' ext]; out.rawTbl = array2table(M, 'VariableNames', {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'});
                out.blocks = {fieldTable(M(:, 1), M(:, 2), magPhase(M(:, 3), M(:, 5)), magPhase(M(:, 4), M(:, 6)))};
            case 'OUT'          % TICRA/GRASP: Theta Phi Re/Im POL1 (RHCP) Re/Im POL2 (LHCP)
                out.userData.source = 'TICRA/GRASP OUT'; out.rawTbl = array2table(M, 'VariableNames', {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'});
                [Eth, Eph] = circularToLinear(complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6))); out.blocks = {fieldTable(M(:, 1), M(:, 2), Eth, Eph)};
            case 'FFS'          % CST: Phi Theta Re/Im Eth Re/Im Eph
                out.userData.source = 'CST FFS'; out.rawTbl = array2table(M, 'VariableNames', {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
                out.blocks = {fieldTable(M(:, 2), M(:, 1), complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)))};
            case 'FFE'          % FEKO: Theta Phi Re/Im Eth Re/Im Eph (extra columns ignored)
                out.userData.source = 'FEKO FFE'; out.rawTbl = array2table(M, 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
                out.blocks = {fieldTable(M(:, 1), M(:, 2), complex(M(:, 3), M(:, 4)), complex(M(:, 5), M(:, 6)))};
            case 'FFD'          % HFSS: header ranges + Re/Im Eth Re/Im Eph blocks (one per frequency)
                assert(ffd.isFFD, 'readFile:ffd', 'FFD header (theta/phi ranges) not found.');
                out.userData.source = 'HFSS FFD';
                thetaAxis = linspace(ffd.theta(1), ffd.theta(2), ffd.theta(3))'; phiAxis = linspace(ffd.phi(1), ffd.phi(2), ffd.phi(3))';
                theta = repelem(thetaAxis, numel(phiAxis)); phi = repmat(phiAxis, numel(thetaAxis), 1);
                sep = isnan(M(:, 1)); freqs = [ffd.freq(:); M(sep & ~isnan(M(:, 2)), 2)]'; rows = M(~sep, 1:4);
                n = numel(theta); assert(mod(size(rows, 1), n) == 0, 'FFD mismatch: row count does not match theta/phi grid');
                blockCount = size(rows, 1) / n; freqs(end+1:blockCount) = NaN; freqs = freqs(1:blockCount);
                out.userData.isMultiBlock = blockCount > 1; out.userData.hasFrequency = any(isfinite(freqs)); out.userData.isDep = out.userData.isMultiBlock || out.userData.hasFrequency;
                out.blocks = cellfun(@(B) fieldTable(theta, phi, complex(B(:, 1), B(:, 2)), complex(B(:, 3), B(:, 4))), mat2cell(rows, repmat(n, blockCount, 1), 4), 'UniformOutput', false);
                out.freqs = freqs; out.rawTbl = out.blocks{1};
            otherwise
                error('readFile:unsupported', 'Unsupported format: %s', ext);
        end
end
out.userData = normalizeMeta(out.userData);
end

function T = fieldTable(theta, phi, Eth, Eph)
T = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function E = magPhase(dB, deg), E = 10 .^ (dB / 20) .* exp(1i * deg2rad(deg)); end

function [Eth, Eph] = circularToLinear(Ercp, Elcp)
Eth = (Ercp + Elcp) / sqrt(2); Eph = (Ercp - Elcp) / (1i * sqrt(2));
end

function meta = normalizeMeta(meta)
defaults = struct('source', 'unknown', 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'isMultiBlock', false, 'hasFrequency', false);
for f = fieldnames(defaults)'
    if ~isfield(meta, f{1}) || isempty(meta.(f{1})), meta.(f{1}) = defaults.(f{1}); end
end
end

function out = readGenericText(fp, textFormat, T, out)
%READGENERICTEXT CSV/TXT/DAT: coverage results, gain-only pattern, or six-column E-field table.
if isempty(T)
    opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
    opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
    T = rmmissing(readtable(fp, opts));
end
n = width(T); assert(n >= 2 && ~isempty(T), 'readFile:InvalidFormat', 'File needs at least two numeric columns.');
names = lower(string(T.Properties.VariableNames)); hasHeaders = ~all(startsWith(names, "var"));
c1 = T{:, 1}; c2 = T{:, 2};
coverageHeader = contains(names(1), "threshold") || any(contains(names(2:end), "coverage"));
if (textFormat == "gain" || n < 6 || coverageHeader) && all(isfinite(c2)) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:n - 1))]; end
    out.rawTbl = T; out.userData.isCoverage = true; return
end
if textFormat == "gain"                                % the wider-spanning of the first two columns is phi
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi', 'Theta'}; else, T.Properties.VariableNames(1:2) = {'Theta', 'Phi'}; end
    T = movevars(T, 'Theta', 'Before', 1);
    out.rawTbl = T; out.blocks = {T}; out.userData.isGainOnly = true; return
end
assert(n >= 6, 'readFile:TextEFieldColumns', 'The selected generic E-field format requires six numeric columns.');
V = T{:, 3:6}; layout = "not applicable";
if endsWith(textFormat, "magphase")
    interleaved = max(abs(V(:, 2)), [], 'omitnan') > 100 && max(abs(V(:, 3)), [], 'omitnan') <= 100;   % |phase| exceeds 100 → mag,phase,mag,phase
    if interleaved, layout = "interleaved"; m = [1 3]; p = [2 4]; else, layout = "grouped"; m = [1 2]; p = [3 4]; end
    E1 = magPhase(V(:, m(1)), V(:, p(1))); E2 = magPhase(V(:, m(2)), V(:, p(2)));
else
    E1 = complex(V(:, 1), V(:, 2)); E2 = complex(V(:, 3), V(:, 4));
end
linear = startsWith(textFormat, "linear");
if linear, Eth = E1; Eph = E2; base = ["E_TH", "E_PH"]; gen = ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"];
elseif startsWith(textFormat, "rcp"), [Eth, Eph] = circularToLinear(E1, E2); base = ["POL1", "POL2"]; gen = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"];
else, [Eth, Eph] = circularToLinear(E2, E1); base = ["POL1", "POL2"]; gen = ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"]; end
if layout ~= "not applicable"
    gen = [base + "_dB", base + "_deg"]; if layout == "interleaved", gen = gen([1 3 2 4]); end
end
if ~hasHeaders, T.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", gen]); end
out.userData.source = sprintf('Generic text (%s, %s)', textFormat, layout);
out.rawTbl = T; out.blocks = {fieldTable(T{:, 1}, T{:, 2}, Eth, Eph)};
end

function out = readGraspCut(fp, out)
%READGRASPCUT TICRA *.cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks.
out.userData.source = 'TICRA/GRASP CUT';
lines = readlines(fp); lines(strlength(strtrim(lines)) == 0) = [];
theta = {}; phi = {}; data = {}; k = 1; icomp = 1; icut = 1;
while k < numel(lines)
    prm = sscanf(lines(k + 1), '%f'); assert(numel(prm) >= 7, 'parseCutFile:bad', 'Could not parse cut parameter line.');
    n = prm(3); icomp = prm(5); icut = prm(6);
    block = reshape(sscanf(strjoin(lines(k + 2:k + 1 + n), ' '), '%f'), 2 * prm(7), []).';
    theta{end+1, 1} = prm(1) + (0:n - 1)' * prm(2); phi{end+1, 1} = repmat(prm(4), n, 1); data{end+1, 1} = block(:, 1:4); %#ok<AGROW>
    k = k + 2 + n;
end
theta = vertcat(theta{:}); phi = vertcat(phi{:}); D = vertcat(data{:});
if icut == 2, [theta, phi] = deal(phi, theta); end                       % ICUT=2: phi swept, theta constant
neg = theta < 0; phi(neg) = phi(neg) + 180; theta(neg) = -theta(neg);   % fold negative theta onto opposite phi
if isscalar(unique(phi))                                                 % single cut → body of revolution
    copies = (0:10:350)'; m = numel(theta); theta = repmat(theta, numel(copies), 1); phi = repelem(copies, m); D = repmat(D, numel(copies), 1);
end
if icomp == 2, names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; [Eth, Eph] = circularToLinear(complex(D(:, 1), D(:, 2)), complex(D(:, 3), D(:, 4)));
else, names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; Eth = complex(D(:, 1), D(:, 2)); Eph = complex(D(:, 3), D(:, 4)); end
out.rawTbl = array2table([theta, phi, D], 'VariableNames', [{'Theta', 'Phi'}, names]);
out.blocks = {fieldTable(theta, phi, Eth, Eph)};
end

function [nHdr, ffd] = findHeaderLines(fp)
%FINDHEADERLINES Count leading non-data lines; recognise the HFSS FFD header (two numeric triples + optional Frequencies line).
fid = fopen(fp, 'r'); if fid < 0, error('apat:io:OpenFailed', 'Cannot open file: %s', fp); end
c = onCleanup(@() fclose(fid));
ffd = struct('theta', [], 'phi', [], 'freq', [], 'isFFD', false); triples = zeros(0, 3); nHdr = 0;
while size(triples, 1) < 2
    line = fgetl(fid); if ~ischar(line), break; end
    nHdr = nHdr + 1; v = sscanf(strtrim(line), '%f').';
    if numel(v) == 3, triples(end+1, :) = v; elseif ~isempty(strtrim(line)) && isempty(triples), break; end %#ok<AGROW>
end
if size(triples, 1) == 2
    ffd.theta = triples(1, :); ffd.phi = triples(2, :); ffd.theta(3) = round(ffd.theta(3)); ffd.phi(3) = round(ffd.phi(3));
    line = fgetl(fid);
    while ischar(line) && isempty(strtrim(line)), nHdr = nHdr + 1; line = fgetl(fid); end
    if ischar(line)
        tok = regexp(strtrim(line), '^frequencies?\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok), nHdr = nHdr + 1; f = sscanf(tok{1}, '%f'); if ~isscalar(f), ffd.freq = f(:); end, end   % "Frequencies N" alone → values sit on separator rows
    end
    ffd.isFFD = all(isfinite([ffd.theta, ffd.phi])) && ffd.theta(3) >= 1 && ffd.phi(3) >= 1;
end
if ~ffd.isFFD                                                            % generic: first line with ≥4 numeric fields starts the data
    frewind(fid); nHdr = 0; num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?';
    pattern = ['^\s*' num '(?:[\s,;]+' num '){3,}\s*$'];
    while true
        line = fgetl(fid); if ~ischar(line) || ~isempty(regexp(line, pattern, 'once')), break; end
        nHdr = nHdr + 1;
    end
end
end

function out = readExcelMatrix(fp)
%READEXCELMATRIX Excel matrix templates: summary sheet + fixed component sheets (Eth/Eph and/or RHCP/LHCP, dBi + degrees).
sheets = string(sheetnames(fp));
circular = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"];
linear = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circular), lower(sheets))); hasL = all(ismember(lower(linear), lower(sheets)));
assert(hasC || hasL, 'readFile:ExcelMatrixFormat', 'Unsupported Excel workbook: the component worksheets Etheta/Ephi and/or RHCP/LHCP (Gain_dBi + Phase_degrees) were not found.');
required = string.empty; if hasC, required = [required, circular]; end; if hasL, required = [required, linear]; end
formatName = {'Excel Matrix Format 2 (Ercp/Elcp)', 'Excel Matrix Format 1 (Eth/Eph)', 'Excel Matrix Format 3 (Ercp/Elcp + Eth/Eph)'}; formatName = formatName{hasC + 2 * hasL};
M = struct(); thetaRef = []; phiRef = [];
for s = required
    [theta, phi, data] = readExcelMatrixSheet(fp, sheets(find(strcmpi(sheets, s), 1)));
    if isempty(thetaRef), thetaRef = theta; phiRef = phi;
    else, assert(isequal(size(theta), size(thetaRef)) && isequal(size(phi), size(phiRef)) && max(abs(theta - thetaRef)) < 1e-9 && max(abs(phi - phiRef)) < 1e-9, ...
            'readFile:ExcelMatrixGrid', 'All Excel Matrix component sheets must use the same theta/phi grid.'); end
    M.(char(s)) = data;
end
if hasL, Eth = magPhase(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = magPhase(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees);
else, [Eth, Eph] = circularToLinear(magPhase(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), magPhase(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees)); end
[PG, TG] = meshgrid(phiRef, thetaRef);
block = fieldTable(TG, PG, Eth, Eph); raw = block;
for s = required, raw.(char(s)) = reshape(M.(char(s)), [], 1); end
meta = readExcelSummary(fp, sheets(1));
meta.source = formatName; meta.file = fp; meta.isGainOnly = false; meta.isCoverage = false; meta.isDep = false; meta.isMultiBlock = false;
meta.hasFrequency = isfield(meta, 'frequencyMHz') && isfinite(meta.frequencyMHz); meta.componentSheets = cellstr(required);
out = struct('rawTbl', raw, 'blocks', {{block}}, 'freqs', NaN, 'userData', meta);
end

function [theta, phi, data] = readExcelMatrixSheet(fp, sheet)
%READEXCELMATRIXSHEET C3-origin matrix: row 2 = phi (C onward), column B = theta (row 3 onward). readcell keeps worksheet coordinates.
C = readcell(fp, 'Sheet', char(sheet));
assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'readFile:ExcelMatrixSheet', 'Sheet "%s" does not contain a C3-origin matrix.', sheet);
isNum = @(x) isnumeric(x) && isscalar(x) && isfinite(x);
pm = cellfun(isNum, C(2, 3:end)); tm = cellfun(isNum, C(3:end, 2));
contiguous = @(m) isempty(find(~m, 1)) || ~any(m(find(~m, 1) + 1:end));
assert(any(pm) && any(tm), 'readFile:ExcelMatrixSheet', 'Sheet "%s" has no numeric theta/phi axes.', sheet);
assert(contiguous(pm) && contiguous(tm), 'readFile:ExcelMatrixAxis', 'Sheet "%s" has a gap in the theta/phi axis.', sheet);
phi = cellfun(@double, C(2, 2 + (1:nnz(pm)))); theta = cellfun(@double, C(2 + (1:nnz(tm)), 2)); phi = phi(:); theta = theta(:);
cells = C(2 + (1:numel(theta)), 2 + (1:numel(phi)));
assert(all(cellfun(isNum, cells(:))), 'readFile:ExcelMatrixSheet', 'Sheet "%s" contains nonnumeric/missing matrix samples.', sheet);
data = cellfun(@double, cells);
assert(all(diff(theta) > 0) && all(diff(phi) > 0), 'readFile:ExcelMatrixAxis', 'Sheet "%s" must have strictly increasing theta/phi axes.', sheet);
assert(theta(1) >= -1e-9 && theta(end) <= 180 + 1e-9 && phi(1) >= -1e-9 && phi(end) < 360 + 1e-9, 'readFile:ExcelMatrixAxis', 'Sheet "%s" has angles outside [theta 0..180, phi 0..360).', sheet);
end

function meta = readExcelSummary(fp, sheet)
%READEXCELSUMMARY Harvest every "Label: value" row of the summary sheet (label in column B, value in C..E) plus the simulation frequency.
meta = struct();
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70'); catch, return; end
clean = @(s) regexprep(lower(strtrim(replace(string(s), char(160), ' '))), '\s+', ' ');
for r = 1:size(C, 1)
    label = C{r, 2}; if ~(ischar(label) || isstring(label)) || strlength(strtrim(string(label))) == 0, continue; end
    value = []; for c = 3:min(size(C, 2), 5), if ~isempty(C{r, c}) && ~(isa(C{r, c}, 'missing')), value = C{r, c}; break; end, end
    if isempty(value), continue; end
    key = matlab.lang.makeValidName(lower(regexprep(char(label), '[^a-zA-Z0-9]+', '_'))); meta.(key) = value;
    if startsWith(clean(label), "pattern simulation freq")
        if isnumeric(value), meta.frequencyMHz = double(value(1)); else, meta.frequencyMHz = str2double(string(value)); end
    end
end
end

%% ====================================================================== local functions: numerics
function [pattern, info] = calcPattern(standard, param, pct, excess)
%CALCPATTERN Canonical fields → processed pattern table + polarization summary.
info = struct('POB', NaN, 'POBth', NaN, 'POBph', NaN, 'pol', 'n/a', 'pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
ud = standard.Properties.UserData;
if isfield(ud, 'isGainOnly') && ud.isGainOnly
    pattern = standard; if width(pattern) > 2, pattern{:, 3:end} = pattern{:, 3:end} + param.GainLoss_dB; end
    info.peak = resolvePeak(pattern{:, 3}, pct, excess);
    [info.POB, info.POBth, info.POBph] = deal(info.peak.value, pattern.Theta(info.peak.index), pattern.Phi(info.peak.index)); return
end
Eth = complex(standard.Re_Eth, standard.Im_Eth) * param.FieldScale; Eph = complex(standard.Re_Eph, standard.Im_Eph) * param.FieldScale;
Ercp = (Eth + 1i * Eph) / sqrt(2); Elcp = (Eth - 1i * Eph) / sqrt(2);
mTh = abs(Eth); mPh = abs(Eph); mR = abs(Ercp); mL = abs(Elcp);
total = 10 * log10(max(mTh.^2 + mPh.^2, eps));
info.peak = resolvePeak(total, pct, excess); [info.POB, info.POBth, info.POBph] = deal(info.peak.value, standard.Theta(info.peak.index), standard.Phi(info.peak.index));
% Dominant components drive co/cross ordering, the displayed polarization and the Auto Rx sense.
P = [mean(mTh.^2, 'omitnan'), mean(mPh.^2, 'omitnan'), mean(mR.^2, 'omitnan'), mean(mL.^2, 'omitnan')];
if P(2) > P(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if P(4) > P(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(P(3:4)) > max(P(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif P(1) >= P(2), info.pol = 'Linear (Vertical)'; else, info.pol = 'Linear (Horizontal)'; end
% Signed axial ratio: + RHCP-dominant, − LHCP-dominant; equal circular components = linear limit (−100 dB floor).
delta = mR - mL; sense = sign(delta); sense(~isfinite(delta)) = 0;
ar = (mR + mL) ./ max(abs(delta), eps);
signedAR = min(20 * log10(ar), 250) .* sense; signedAR(isfinite(delta) & abs(delta) <= eps .* max(mR + mL, 1)) = -100;
% Polarization loss factor against an incident wave of axial ratio RxAR_dB (tilt difference fixed at 90°, M7 convention).
if param.RxMode == "Auto", waveSense = 2 * (info.pairs.Circular(1) == "E_RCP") - 1; elseif param.RxMode == "RHCP", waveSense = 1; else, waveSense = -1; end
Ra = ar .* sense; Ra(sense == 0) = 1e12; Rw = waveSense * 10 .^ (param.RxAR_dB / 20);
plf = 10 * log10(min(max(0.5 + (4 * Ra * Rw - (Ra.^2 - 1) * (Rw^2 - 1)) ./ (2 * (Ra.^2 + 1) * (Rw^2 + 1)), eps), 1));
eirp = param.Pt_dBW + total; eirpW = 10 .^ (eirp / 10);
pattern = table(standard.Theta, standard.Phi, total, signedAR, 20 * log10(max(mR, eps)), 20 * log10(max(mL, eps)), plf, total + plf, ...
    20 * log10(max(mTh, eps)), 20 * log10(max(mPh, eps)), rad2deg(angle(Eth)), rad2deg(angle(Eph)), rad2deg(angle(Ercp)), rad2deg(angle(Elcp)), ...
    eirp, eirpW ./ (4 * pi * param.R_m^2), sqrt(30 * eirpW) ./ param.R_m, 'VariableNames', ...
    {'Theta', 'Phi', 'E_Total_dB', 'AR_dB', 'E_RCP_dB', 'E_LCP_dB', 'PLF_dB', 'Gain_PolCorrected_dB', 'E_TH_dB', 'E_PH_dB', 'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'});
pattern.Properties.UserData = ud;
end

function info = resolvePeak(values, pct, excess)
%RESOLVEPEAK Peak policy: accept the raw maximum unless it exceeds the P<pct> percentile by more than EXCESS dB;
%   otherwise the highest sample at or below the percentile is the effective peak and the outliers are masked.
finite = isfinite(values);
info = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(values)), 'wasAdjusted', false);
if ~any(finite), return; end
[info.rawValue, info.rawIndex] = max(values, [], 'omitnan'); [info.value, info.index] = deal(info.rawValue, info.rawIndex);
p = prctile(values(finite), pct);
if info.rawValue <= p + excess, return; end
outliers = finite & values > p; candidates = values; candidates(~finite | outliers) = -Inf;
if any(~outliers & finite), [info.value, info.index] = max(candidates); info.outlierMask = outliers; info.wasAdjusted = true; end
end

function b = peakWindow(values, pct, excess)
%PEAKWINDOW 50-dB display/threshold window whose top is the effective peak rounded up to 5 dB.
v = double(values(isfinite(values))); b = [-50 0]; if isempty(v), return; end
peak = resolvePeak(v, pct, excess); if ~isfinite(peak.value), return; end
top = ceil(peak.value / 5) * 5; b = min(max([top - 50, top], -250), 100);
if diff(b) < 1, b(1) = max(-250, b(2) - 50); end
end

function T = normalizePattern(T)
%NORMALIZEPATTERN Map angles onto the canonical sphere: theta 0..180, phi 0..360 with the 360° seam closed.
theta = T.Theta;
if any(theta < 0)
    if min(theta) >= -90 && max(theta) <= 90, T.Theta = 90 - theta;                       % elevation source
    else, T.Theta(theta < 0) = -theta(theta < 0); T.Phi(theta < 0) = T.Phi(theta < 0) + 180; end
end
T.Theta = mod(T.Theta, 360); over = T.Theta > 180; T.Theta(over) = 360 - T.Theta(over); T.Phi(over) = T.Phi(over) + 180;
num = varfun(@isnumeric, T, 'OutputFormat', 'uniform'); T{:, num} = round(T{:, num}, 5);   % remove 1e-15 seam artefacts once
T.Theta = mod(T.Theta, 360); over = T.Theta > 180; T.Theta(over) = 360 - T.Theta(over); T.Phi = mod(T.Phi, 360);
[~, u] = unique(T{:, {'Phi', 'Theta'}}, 'rows', 'first'); T = T(u, :);
seam = T(T.Phi == 0, :); seam.Phi(:) = 360; T = [T; seam];
end

function R = resampleCanonical(T, step)
%RESAMPLECANONICAL Interpolate primitive columns onto the canonical STEP grid. Regular grids use interp2 with a periodic phi seam;
%   irregular sources use scattered interpolation. Gain-only dB columns are interpolated in linear power.
names = T.Properties.VariableNames(3:end); assert(~isempty(T), 'apat:math:EmptyPattern', 'Cannot resample an empty pattern.');
theta = double(T.Theta); phiRaw = double(T.Phi);
keep = isfinite(theta) & isfinite(phiRaw) & theta >= -1e-9 & theta <= 180 + 1e-9 & abs(phiRaw - 360) > 1e-9;
theta = theta(keep); phi = mod(phiRaw(keep), 360); T = T(keep, :);
[~, u] = unique([theta, phi], 'rows', 'stable'); theta = theta(u); phi = phi(u); T = T(u, :);
tq = (0:step:180)'; pq = unique([0:step:360, 360])'; [PQ, TQ] = meshgrid(pq, tq);
R = table(TQ(:), PQ(:), 'VariableNames', {'Theta', 'Phi'});
st = unique(theta); sp = unique(phi); regular = numel(st) * numel(sp) == numel(theta);
if regular
    [PG, TG] = meshgrid(sp, st); [~, it] = ismember(theta, st); [~, ip] = ismember(phi, sp); li = sub2ind(size(PG), it, ip);
    regular = numel(unique(li)) == numel(li);
    if regular && sp(end) < 360 - 1e-9, PG(:, end+1) = PG(:, 1) + 360; TG(:, end+1) = TG(:, 1); end   % periodic closing column
end
primitiveField = all(ismember({'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}, names));
for k = 1:numel(names)
    v = double(T.(names{k})); asPower = ~primitiveField && isGainDB(names{k});
    if asPower, v = 10 .^ (v / 10); end
    if regular
        G = nan(numel(st), numel(sp)); G(li) = v; if size(PG, 2) > numel(sp), G(:, end+1) = G(:, 1); end
        q = interp2(PG, TG, G, PQ, TQ, 'linear', NaN); miss = ~isfinite(q);
        if any(miss(:)), near = interp2(PG, TG, G, PQ, TQ, 'nearest', NaN); q(miss) = near(miss); end
    else
        F = scatteredInterpolant(phi, theta, v, 'linear', 'nearest'); q = F(PQ, TQ);
    end
    if asPower, q = 10 * log10(max(q, realmin)); end
    R.(names{k}) = q(:);
end
R.Properties.UserData = T.Properties.UserData;
end

function tf = isGainDB(name)
key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', '');
tf = contains(key, 'gain') || contains(key, 'directivity') || contains(key, 'eirp') || endsWith(key, 'db');
end

function dOmega = solidWeights(theta, phi)
%SOLIDWEIGHTS Exact uniform-cell solid-angle weights on the canonical grid (closing 360° seam weighted zero).
ts = gridStep(theta); ps = gridStep(mod(phi, 360)); if ~isfinite(ts), ts = 180; end, if ~isfinite(ps), ps = 360; end
dOmega = (cosd(max(theta - ts / 2, 0)) - cosd(min(theta + ts / 2, 180))) * deg2rad(ps);
dOmega(abs(phi - 360) < 1e-9) = 0;
end

function coverage = coverageCCDF(gain, region, thresholds, dOmega)
%COVERAGECCDF Coverage(T) [%] = 100 · Σ I(G_i > T) Ω_i / Σ_region Ω_i, all thresholds at once.
valid = region(:) & isfinite(gain(:)) & isfinite(dOmega(:)) & dOmega(:) >= 0;
g = gain(valid); w = dOmega(valid); coverage = zeros(numel(thresholds), 1);
if isempty(g) || sum(w) <= 0, return; end
coverage = 100 * (w(:).' * (g(:) > thresholds(:).')).' / sum(w);
end

function [peak, axisIndex] = calcOrientation(T, dOmega, column, axes, pct, excess)
%CALCORIENTATION Effective peak of COLUMN and the principal axis whose 45° cone captures the most weighted energy.
gain = chooseGain(T, column); peak = resolvePeak(gain, pct, excess);
if peak.wasAdjusted, gain(peak.outlierMask) = NaN; end
w = 10 .^ ((gain - peak.value) / 10) .* dOmega(:); w(~isfinite(w)) = 0;
A = [sind(axes.theta(:)) .* cosd(axes.phi(:)), sind(axes.theta(:)) .* sind(axes.phi(:)), cosd(axes.theta(:))];
V = [sind(T.Theta) .* cosd(T.Phi), sind(T.Theta) .* sind(T.Phi), cosd(T.Theta)];
[~, axisIndex] = max(w.' * double(V * A.' >= cosd(45)));
end

function m = calcMetrics(T, dOmega, axes, axisIndex, pct, excess)
%CALCMETRICS Scalar antenna metrics of the total-gain column on the physical sphere.
gain = chooseGain(T, 'E_Total_dB'); peak = resolvePeak(gain, pct, excess); k = peak.index;
g = gain; if peak.wasAdjusted, g(peak.outlierMask) = NaN; end
integrated = sum(10 .^ (g / 10) .* dOmega(:), 'omitnan');
directivity = 10 * log10(max(4 * pi * 10^(peak.value / 10) / max(integrated, eps), eps));
eff = 100 * integrated / (4 * pi); if eff < 0 || eff > 100, eff = NaN; end
[~, back] = min(cosd(T.Theta) * cosd(T.Theta(k)) + sind(T.Theta) * sind(T.Theta(k)) .* cosd(T.Phi - T.Phi(k)));
ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(k); end
[eAng, eRows] = cutGeometry(T, 'Theta', axes.phi(axisIndex));                                     % E-plane: through the boresight axis
if axes.theta(axisIndex) == 90, [hAng, hRows] = cutGeometry(T, 'Phi', 90); else, [hAng, hRows] = cutGeometry(T, 'Theta', 90); end
m = struct('PeakGain_dB', peak.value, 'PeakTheta_deg', T.Theta(k), 'PeakPhi_deg', T.Phi(k), 'HPBW_EPlane_deg', calcHPBW(eAng, gain(eRows)), ...
    'HPBW_HPlane_deg', calcHPBW(hAng, gain(hRows)), 'FrontBack_dB', peak.value - gain(back), 'PeakDirectivity_dB', directivity, 'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', ar);
end

function [ang, rows, fixed, symbol, snapped, requested] = cutGeometry(T, cutType, requested)
%CUTGEOMETRY One full-circle cut on the physical sphere: Phi cut = fixed theta (angle = phi), Theta cut = fixed phi
%   (angle = theta on the primary half, 360 − theta on the opposite half). Requested angles snap to available samples.
if strcmp(cutType, 'Phi')
    values = unique(T.Theta); [dist, k] = min(abs(values - requested)); fixed = values(k); symbol = 'θ';
    rows = find(abs(T.Theta - fixed) < 1e-9); [ang, order] = sort(T.Phi(rows)); rows = rows(order);
else
    requested = mod(requested, 360); phi = mod(T.Phi, 360); values = unique(phi);
    [dist, k] = min(abs(mod(values - requested + 180, 360) - 180)); fixed = values(k); symbol = 'φ';
    [~, o] = min(abs(mod(values - fixed, 360) - 180));
    primary = find(abs(phi - fixed) < 1e-9); opposite = find(abs(phi - values(o)) < 1e-9 & abs(T.Theta - 180) > 1e-9);
    [~, i1] = sort(T.Theta(primary)); [~, i2] = sort(T.Theta(opposite), 'descend'); primary = primary(i1); opposite = opposite(i2);
    rows = [primary; opposite]; ang = [T.Theta(primary); 360 - T.Theta(opposite)];
end
snapped = dist > 0;
end

function [bw, lo, hi] = calcHPBW(ang, gain, peakGain, peakAngle)
%CALCHPBW Half-power beamwidth of a circular cut with linear interpolation of both −3 dB crossings.
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(gain); ang = ang(ok); gain = gain(ok);
if numel(gain) < 3, return; end
if nargin < 3 || isempty(peakGain), [peakGain, k] = max(gain); peakAngle = ang(k); end
[rel, order] = sort(mod(ang - peakAngle + 180, 360) - 180); g = gain(order); half = peakGain - 3;
L = find(rel < 0 & g <= half, 1, 'last'); Rr = find(rel > 0 & g <= half, 1, 'first');
if isempty(L) || isempty(Rr) || L + 1 > numel(g) || Rr < 2, return; end
cross = @(i, j) rel(i) + (rel(j) - rel(i)) * (half - g(i)) / (g(j) - g(i));
if g(L + 1) == g(L) || g(Rr - 1) == g(Rr), return; end
left = cross(L, L + 1); right = cross(Rr, Rr - 1);
lo = peakAngle + left; hi = peakAngle + right; bw = right - left;
end

function step = gridStep(values)
%GRIDSTEP Smallest positive spacing between distinct finite samples (NaN when undefined).
d = diff(unique(values(isfinite(values)))); d = d(d > 1e-9);
if isempty(d), step = NaN; else, step = min(d); end
end

function gain = chooseGain(T, requested)
%CHOOSEGAIN Requested column, else E_Total_dB, else the first data column.
vars = T.Properties.VariableNames; candidates = [string(requested), "E_Total_dB"];
k = find(ismember(candidates, string(vars)), 1);
if isempty(k), gain = T{:, 3}; else, gain = T.(char(candidates(k))); end
end