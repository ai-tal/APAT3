classdef APAT_v3_M8_6 < matlab.apps.AppBase %1618-lines %ISSUES: %1. Lazy Full Pattern plots loading/rendering  %2. Output Table Columns filter doesn't use color scheme/customization in filtering  %3. Interactive DataTip labeling not-working/not-enabled on the 3D Spherical & 3D Polar plots  %3. When Switching Phi angular span while the POB DataTip is enabled, in the Cut plots, it keeps the old POB DataTip and also labels the new/adjusted/shifted/spanned POB DataTip (It's working properly in the Full Antenna Pattern plots, we should do the same behavior/implementation (update/adjust the old/existing one (or delete and create! Not sure how it's implemented, but it's working properly)  %4. Custom DataTip context menu not working, throwing error: "Unrecognized method, property, or field 'ContextObject' for class 'matlab.ui.eventdata.ActionData'"  %5. On Coverage, the Coverage Results main node shouldn't show by default/on-load if we don't have Coverage Results files already loaded!  %6. On Coverage, When Clearing or Resetting, it doesn't clear the projection lines!  %7. On Coverage Threshold Query, it doesn't return/place the DataTip at the exact requested/queried value (it snaps to nearest data-point! whereas the projection lines are traced properly at the requested location!)
%APAT_V3_M8  Antenna Pattern Analyzer Tool — v3 Milestone 8.
%
%  One grid-native pattern, one derivation, one registry, one update path.
%
%  DATAFLOW (every arrow is one function; nothing is stored twice)
%    FILE ─► io_read ─► Source{Raw, Blocks, Freqs, Meta}
%         ─► pat_build ─► Pattern{Theta, Phi, dTheta, dPhi, Eth/Eph | G.(col), Meta}
%         ─► (pat_resample) ─► geo_build ─► Geometry{wTheta, dOmega, Omega, PhiPeriodic, IsFullSphere}
%         ─► pat_derive(Pattern, Geometry, Params) ─► Derived{Cols.(name), Kind, Peak, Pol, Boresight, Metrics}
%         ─► app.Pats(k)                       ◄── ONE entry per loaded file (Main tab = Pats(Main))
%    widgets ─► readConfig ─► View ─► geo_displayMap ─► Map{ColIdx, ThetaAxis, PhiAxis}  (display only)
%    View + Map + Derived ─► render*/apply*        (the ONLY writers of graphics/widget state)
%
%  RULE: widgets are read in readConfig/readCoverageConfig only; math never sees the app;
%        every callback is app.on(scope); on() owns try/catch, busy flag, perf and drawnow.

    properties (Access = public)
        UIFigure
        GridLayout
        TabGroup
        Tab1_Single
        Single_Grid
        Single_panelParam
        Single_gridPanel_Param
        Single_DropDown_FFD
        FFDFreqDropDownLabel
        Single_DropDown_TextFormat
        TextFormatLabel
        Single_Export_UAN
        Single_Button_ResetParams
        Single_Export_Output
        Single_Button_Coverage
        Single_Button_Process
        Single_DropDown_step
        Single_DropDown_R
        Single_Spinner_R
        DistanceLabel
        Single_Button_Load
        Single_DropDown_Pt
        Single_Spinner_Pt
        TransmitPowerLabel
        Single_Spinner_Loss
        LossindBLabel
        Single_Spinner_Rw
        IncidentWaveARRwPLFLabel
        Single_DropDown_RxPol
        RxPolLabel
        Single_EditField_Path
        InputPatternLabel
        Single_StatusBar
        Single_Panel_plotControl
        Single_gridPanel_Ctrl
        View3DLabel
        Single_DropDown_3DView
        Singel_CheckBox_overlayCut
        Single_CheckBox_POB
        Single_CheckBox_HPBWBounds
        Single_Switch_EHplane
        Single_Switch_AngularSpan
        Single_Switch_ThetaSpan
        CutvalueSpinnerLabel
        Single_Label_Clim
        Single_Button_Clim
        Single_Plot_Cstep
        ColorbarstepLabel
        Single_Plot_Cmin
        ColorbarminLabel
        Single_Plot_Cmax
        ColorbarmaxLabel
        Single_DropDown_cutValue
        Single_DropDown_cutType
        CutFieldBasisDropDown
        CuttypeDropDownLabel
        Single_DropDown_Component
        ComponentLabel
        Single_tabData
        Single_tabDataOut
        Single_gridDataOut
        Single_Table_DataOut
        Single_tabDataIn
        Single_gridDataIn
        Single_Table_DataIn
        MetadataTab
        Single_gridMetadata
        Single_Table_metadata
        Single_DropDown_output
        Single_Panel_Rect
        Single_gridPanel_Cut
        Single_tabCut
        Single_tabPolarPlot
        Single_Grid_Polar
        Single_gridEcut
        CheckBox_Et
        CheckBox_Er
        CheckBox_El
        Button_ExportCut
        Range_Cut_Max
        Range_Cut_Min
        Label_HPBW
        Button_HPBW
        Range_Cut
        Single_tabRectPlot
        Single_gridRect
        Single_AxesRect
        Single_Panel_fullPattern
        Single_gridPanel_full
        Single_tabPlots
        Single_tabContour
        Single_gridContour
        Range_Ctr_Min
        Range_Ctr_Max
        Range_Ctr
        Single_Axes_Ctr
        Single_tabCircular
        Single_gridCircular
        Range_Cir_Min
        Range_Cir_Max
        Range_Cir
        Single_tab3DSpherical
        Single_grid3dSpherical
        Range_3dSph_Min
        Range_3dSph_Max
        Range_3dSph
        Single_Axes_3dSph
        Single_tab3DPolar
        Single_grid3dPolar
        Range_3dPol_Min
        Range_3dPol_Max
        Range_3dPol
        Single_Axes_3dPol
        Single_tab3DRect
        Single_grid3dRect
        Range_3dRect_Min
        Range_3dRect_Max
        Range_3dRect
        Single_Axes_3dRect
        Tab2_Coverage
        Cov_Grid
        Cov_Panel_Results
        GridLayout2
        Cov_Spinner_XMin
        Cov_Spinner_XMax
        Cov_Spinner_XRange
        Cov_Tabel
        Cov_Tree
        Cov_TreeNode_Results
        Cov_Axes
        Cov_StatusBar
        Cov_Panel_Param
        Cov_gridPanel_Parm
        Cov_DropDown_OrientationLabel
        Cov_DropDown_TextFormat
        Cov_TextFormatLabel
        Cov_Button_queryThresh
        Cov_Button_queryCov
        Cov_DropDown_Component
        Cov_DropDown_ComponentLabel
        Cov_Spinner_queryThresh
        Cov_QueryThresholdLabel
        Cov_Spinner_queryCov
        Cov_QueryCoverageLabel
        Cov_Button_toMain
        Cov_Button_Clear
        Cov_Spinner_ConeAng
        ConeAngleLabel
        Cov_Spinner_ConePH
        ConeLabel
        Cov_Spinner_ConeTH
        ConeSpinnerLabel
        Cov_Spinner_Step
        StepdBSpinnerLabel
        Cov_Spinner_ThreshMax
        ThresholdMaxdBSpinnerLabel
        Cov_Spinner_ThreshMin
        ThresholdMindBSpinnerLabel
        Cov_Button_Export
        Cov_Button_Reset
        Cov_Button_computeCov
        Cov_Button_Load
        Cov_EditField_filePath
        AntennaPatternEditFieldLabel
        Cov_DropDown_Orientation
        Cov_ButtonGroup_CovType
        Cov_ButtonGroup_Btn_Conical
        Cov_ButtonGroup_Btn_Spherical
    end

    properties (Access = private)
        Pats = struct('Name', {}, 'Path', {}, 'Source', {}, 'Pattern', {}, 'Geometry', {}, 'Derived', {}, 'Params', {}) % pattern registry (I14)
        Main double = 0                 % index into Pats shown on the Main tab (0 = nothing loaded)
        View struct = struct()          % last readConfig() snapshot
        Map struct = struct()           % display permutation/axes for the active span switches
        Gfx struct = struct()           % retained graphics handles per view: surface, pob, tip, colorbar, overlay
        Dirty logical = true(1, 5)      % full-pattern tabs that must be re-rendered when shown
        ShowCols logical = logical([])  % Results-table column filter (one flag per Derived column)
        Range struct = struct('full', [-40 10], 'cut', [-40 10], 'cov', [-40 10], 'AutoFull', true, 'AutoCut', true, 'AutoCov', true)
        PaxCut                          % polar cut axes
        PaxPattern                      % polar full-pattern (fisheye) axes
        PlotMenu                        % one shared "Delete DataTips" context menu
        Status struct = struct('main', 'Ready 🚀', 'cov', 'Ready 🚀') % persistent status text per bar
        StatusTimer                     % one timer restoring the persistent status after a transient message
        Busy logical = false            % re-entrancy guard for on()
        Dlg = []                        % active cancelable progress dialog, when present
        CovRunID double = 0             % incremental coverage job id
        Perf struct = struct('action', {}, 'stage', {}, 'seconds', {}) % per-stage timings of every on(scope)
        PerfClock uint64 = tic
        Defaults struct = struct()      % startup parameter widget values (Reset Params)
    end

    properties (Constant, Access = private)
        ReleaseName = 'APAT v3 Milestone 8'
        Axes6 = struct('labels', {{'+Z', '-Z', '+X', '-X', '+Y', '-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270]) % principal axes [polar theta, phi]
        PeakExcessDB = 6                % a sample is a spike iff it exceeds every grid neighbour by more than this (I5)
        ConeHalfAngleDeg = 45           % boresight detection cone
        PLFTiltDeg = 90                 % worst-case relative tilt used by the PLF formula (M7-compatible)
        LinearARFloorDB = -100          % signed AR shown for numerically linear samples
        DistanceFloorM = 1e-12
        FullTabs = ["ctr", "cir", "sph", "pol", "rect"]
        HiddenCols = ["E_TH_dB", "E_PH_dB", "E_TH_Phase", "E_PH_Phase", "E_RCP_Phase", "E_LCP_Phase", "EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]
        TextFormats = {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
            '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
            '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}
        TextFormatCodes = {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'}
    end

    %% ------------------------------------------------------------------ construction / layout
    methods (Access = public)
        function app = APAT_v3_M8_6
            app.createComponents();
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @startupFcn);
            if nargout == 0, clear app; end
        end

        function delete(app)
            app.stopTimer();
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end
    end

    methods (Access = private)
        function h = place(~, h, row, col, varargin)
            % Declarative placement: one call per widget (I15).
            h.Layout.Row = row; h.Layout.Column = col;
            if ~isempty(varargin), set(h, varargin{:}); end
        end

        function h = lbl(app, parent, text, row, col, varargin)
            h = app.place(uilabel(parent, 'Text', text, 'HorizontalAlignment', 'right'), row, col, varargin{:});
        end

        function dd = fmtDropdown(app, parent, scope)
            dd = uidropdown(parent, 'Items', app.TextFormats, 'ItemsData', app.TextFormatCodes, 'Value', 'gain', ...
                'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'ValueChangedFcn', @(~, ~) app.on(scope));
        end

        function [tab, g, ax, slider, spMin, spMax] = patternTab(app, group, titleTxt, axesTitle, key)
            tab = uitab(group, 'Title', titleTxt);
            g = uigridlayout(tab, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});
            ax = [];
            if ~isempty(axesTitle)
                ax = app.place(uiaxes(g), [1 3], 2, 'XLim', [0 360], 'YLim', [0 180], 'YDir', 'reverse', 'XTick', 0:30:360, 'YTick', 0:15:180, 'Box', 'on');
                title(ax, axesTitle); xlabel(ax, 'Phi (degree)'); ylabel(ax, 'Theta (degree)');
            end
            slider = app.place(uislider(g, 'range', 'Limits', [-250 100], 'Value', [-250 100], 'Orientation', 'vertical', 'Step', 1), 2, 1, ...
                'ValueChangedFcn', @(s, ~) app.on("range", "full", s.Value));
            spMax = app.place(uispinner(g, 'Limits', [-250 100], 'Value', 100, 'Step', 5), 1, 1, 'ValueChangedFcn', @(s, ~) app.on("range", "full", [NaN s.Value]));
            spMin = app.place(uispinner(g, 'Limits', [-250 100], 'Value', -250, 'Step', 5), 3, 1, 'ValueChangedFcn', @(s, ~) app.on("range", "full", [s.Value NaN]));
            tab.Tag = char(key);
        end

        function createComponents(app)
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.ReleaseName], 'Visible', 'off', 'Position', [100 100 1136 739], 'WindowState', 'maximized');
            app.UIFigure.CloseRequestFcn = @(~, ~) delete(app);
            app.GridLayout = uigridlayout(app.UIFigure, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.TabGroup = app.place(uitabgroup(app.GridLayout), 1, 1);
            app.Tab1_Single = uitab(app.TabGroup, 'Title', 'Process Pattern 📡');
            app.Single_Grid = uigridlayout(app.Tab1_Single, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});

            % --- Full antenna pattern panel (five retained views)
            app.Single_Panel_fullPattern = app.place(uipanel(app.Single_Grid, 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [1 6]);
            app.Single_gridPanel_full = uigridlayout(app.Single_Panel_fullPattern, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_tabPlots = app.place(uitabgroup(app.Single_gridPanel_full), 1, 1, 'SelectionChangedFcn', @(~, ~) app.on("fulltab"));
            [app.Single_tabContour, app.Single_gridContour, app.Single_Axes_Ctr, app.Range_Ctr, app.Range_Ctr_Min, app.Range_Ctr_Max] = app.patternTab(app.Single_tabPlots, 'Contour Plot', 'Antenna Gain Pattern', "ctr");
            [app.Single_tabCircular, app.Single_gridCircular, ~, app.Range_Cir, app.Range_Cir_Min, app.Range_Cir_Max] = app.patternTab(app.Single_tabPlots, 'Circular (Fisheye) Plot', '', "cir");
            [app.Single_tab3DSpherical, app.Single_grid3dSpherical, app.Single_Axes_3dSph, app.Range_3dSph, app.Range_3dSph_Min, app.Range_3dSph_Max] = app.patternTab(app.Single_tabPlots, '3D Spherical Plot', '3D Spherical Plot', "sph");
            [app.Single_tab3DPolar, app.Single_grid3dPolar, app.Single_Axes_3dPol, app.Range_3dPol, app.Range_3dPol_Min, app.Range_3dPol_Max] = app.patternTab(app.Single_tabPlots, '3D Polar Plot', '3D Polar Plot', "pol");
            [app.Single_tab3DRect, app.Single_grid3dRect, app.Single_Axes_3dRect, app.Range_3dRect, app.Range_3dRect_Min, app.Range_3dRect_Max] = app.patternTab(app.Single_tabPlots, '3D Surface Plot', '3D Surface (Rectangular) Plot', "rect");
            app.PaxPattern = app.place(polaraxes(app.Single_gridCircular), [1 3], 2, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');

            % --- Cut panel
            app.Single_Panel_Rect = app.place(uipanel(app.Single_Grid, 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'Visible', 'off'), [2 3], [7 12]);
            app.Single_gridPanel_Cut = uigridlayout(app.Single_Panel_Rect, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_tabCut = app.place(uitabgroup(app.Single_gridPanel_Cut), 1, 1, 'SelectionChangedFcn', @(~, ~) app.on("cut"));
            app.Single_tabPolarPlot = uitab(app.Single_tabCut, 'Title', 'Polar Cut Plot');
            app.Single_Grid_Polar = uigridlayout(app.Single_tabPolarPlot, 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            app.Range_Cut = app.place(uislider(app.Single_Grid_Polar, 'range', 'Limits', [-250 100], 'Value', [-250 100], 'Orientation', 'vertical', 'Step', 1), [2 3], 1, 'ValueChangedFcn', @(s, ~) app.on("range", "cut", s.Value));
            app.Range_Cut_Max = app.place(uispinner(app.Single_Grid_Polar, 'Limits', [-250 100], 'Value', 100, 'Step', 5), 1, 1, 'ValueChangedFcn', @(s, ~) app.on("range", "cut", [NaN s.Value]));
            app.Range_Cut_Min = app.place(uispinner(app.Single_Grid_Polar, 'Limits', [-250 100], 'Value', -250, 'Step', 5), 4, 1, 'ValueChangedFcn', @(s, ~) app.on("range", "cut", [s.Value NaN]));
            app.Button_HPBW = app.place(uibutton(app.Single_Grid_Polar, 'state', 'Text', 'HPBW', 'FontWeight', 'bold'), 1, 4, 'ValueChangedFcn', @(~, ~) app.on("cut"));
            app.Label_HPBW = app.place(uilabel(app.Single_Grid_Polar, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold'), 2, 4);
            app.Single_gridEcut = app.place(uigridlayout(app.Single_Grid_Polar, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x', '1x', '1x'}), 3, 4);
            app.CheckBox_Et = app.place(uicheckbox(app.Single_gridEcut, 'Text', 'E_Total', 'Value', true), 1, 1, 'ValueChangedFcn', @(~, ~) app.on("cut"));
            app.CheckBox_Er = app.place(uicheckbox(app.Single_gridEcut, 'Text', 'E_RCP', 'Value', true), 2, 1, 'ValueChangedFcn', @(~, ~) app.on("cut"));
            app.CheckBox_El = app.place(uicheckbox(app.Single_gridEcut, 'Text', 'E_LCP', 'Value', true), 3, 1, 'ValueChangedFcn', @(~, ~) app.on("cut"));
            app.Button_ExportCut = app.place(uibutton(app.Single_Grid_Polar, 'push', 'Text', 'Export Cut', 'FontWeight', 'bold'), 4, 4, 'ButtonPushedFcn', @(~, ~) app.on("exportcut"));
            app.PaxCut = app.place(polaraxes(app.Single_Grid_Polar), [1 4], 3, 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            app.Single_tabRectPlot = uitab(app.Single_tabCut, 'Title', 'Rectangular Cut Plot');
            app.Single_gridRect = uigridlayout(app.Single_tabRectPlot);
            app.Single_AxesRect = app.place(uiaxes(app.Single_gridRect), [1 2], [1 2], 'XLim', [0 180], 'XTick', 0:15:180, 'Box', 'on');
            xlabel(app.Single_AxesRect, 'Theta (degree)'); ylabel(app.Single_AxesRect, 'Magnitude (dB)');

            % --- Data tabs
            app.Single_DropDown_output = app.place(uidropdown(app.Single_Grid, 'Items', {'Select Output:'}, 'Visible', 'off'), 3, [13 14], 'ValueChangedFcn', @(~, ~) app.on("filter"));
            app.Single_tabData = app.place(uitabgroup(app.Single_Grid, 'Visible', 'off'), 4, [1 14]);
            app.Single_tabDataOut = uitab(app.Single_tabData, 'Title', 'Results 📤', 'ButtonDownFcn', @(~, ~) set(app.Single_DropDown_output, 'Visible', 'on'));
            app.Single_gridDataOut = uigridlayout(app.Single_tabDataOut, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_DataOut = app.place(uitable(app.Single_gridDataOut, 'ColumnWidth', '1x', 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true, 'Visible', 'off'), 1, 1);
            app.Single_tabDataIn = uitab(app.Single_tabData, 'Title', 'Input 📥');
            app.Single_gridDataIn = uigridlayout(app.Single_tabDataIn, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_DataIn = app.place(uitable(app.Single_gridDataIn, 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true, 'Visible', 'off'), 1, 1);
            app.MetadataTab = uitab(app.Single_tabData, 'Title', 'Metadata 📋');
            app.Single_gridMetadata = uigridlayout(app.MetadataTab, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_metadata = app.place(uitable(app.Single_gridMetadata, 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {}), 1, 1);

            % --- Plot control panel
            app.Single_Panel_plotControl = app.place(uipanel(app.Single_Grid, 'Title', 'Plot Control 🎨', 'Visible', 'off'), 2, [13 14]);
            g = uigridlayout(app.Single_Panel_plotControl, 'RowHeight', repmat({'fit'}, 1, 15)); app.Single_gridPanel_Ctrl = g;
            app.ComponentLabel = app.lbl(g, 'Component', 1, 1);
            app.Single_DropDown_Component = app.place(uidropdown(g, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}), 1, 2, 'ValueChangedFcn', @(~, ~) app.on("component"));
            app.CuttypeDropDownLabel = app.lbl(g, 'Cut type', 2, 1);
            app.Single_DropDown_cutType = app.place(uidropdown(g, 'Items', {'Phi', 'Theta'}, 'Value', 'Phi'), 2, 2, 'ValueChangedFcn', @(~, ~) app.on("cut"));
            app.CutvalueSpinnerLabel = app.lbl(g, 'Cut value', 3, 1);
            app.Single_DropDown_cutValue = app.place(uispinner(g, 'Limits', [0 360], 'Value', 0), 3, 2, 'ValueChangedFcn', @(~, ~) app.on("cut"));
            app.lbl(g, 'Cut fields', 4, 1);
            app.CutFieldBasisDropDown = app.place(uidropdown(g, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Value', 'Circular'), 4, 2, 'ValueChangedFcn', @(~, ~) app.on("cut"));
            app.ColorbarmaxLabel = app.lbl(g, 'Colorbar max', 5, 1);
            app.Single_Plot_Cmax = app.place(uispinner(g, 'Limits', [-250 100], 'Value', 10), 5, 2, 'ValueChangedFcn', @(~, ~) app.on("range", "all", [app.Single_Plot_Cmin.Value app.Single_Plot_Cmax.Value]));
            app.ColorbarminLabel = app.lbl(g, 'Colorbar min', 6, 1);
            app.Single_Plot_Cmin = app.place(uispinner(g, 'Limits', [-250 100], 'Value', -40), 6, 2, 'ValueChangedFcn', @(~, ~) app.on("range", "all", [app.Single_Plot_Cmin.Value app.Single_Plot_Cmax.Value]));
            app.ColorbarstepLabel = app.lbl(g, 'Colorbar step', 7, 1);
            app.Single_Plot_Cstep = app.place(uispinner(g, 'Limits', [0.1 100], 'Value', 5), 7, 2, 'ValueChangedFcn', @(~, ~) app.on("cstep"));
            app.Single_Label_Clim = app.lbl(g, 'Adjust Colorbar', 8, 1);
            app.Single_Button_Clim = app.place(uibutton(g, 'push', 'Text', 'Apply'), 8, 2, 'ButtonPushedFcn', @(~, ~) app.on("range", "all", [app.Single_Plot_Cmin.Value app.Single_Plot_Cmax.Value]));
            app.View3DLabel = app.lbl(g, '3D view', 9, 1);
            app.Single_DropDown_3DView = app.place(uidropdown(g, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Value', 'iso'), 9, 2, 'ValueChangedFcn', @(~, ~) app.on("view3d"));
            pad = @(n) repmat(char(160), 1, n);
            app.Single_Switch_AngularSpan = app.place(uiswitch(g, 'slider', 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'Value', '0° to 360°'), 10, [1 2], 'ValueChangedFcn', @(~, ~) app.on("span"));
            app.Single_Switch_ThetaSpan = app.place(uiswitch(g, 'slider', 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'Value', '0° to 180°'), 11, [1 2], 'ValueChangedFcn', @(~, ~) app.on("span"));
            app.Single_Switch_EHplane = app.place(uiswitch(g, 'slider', 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'Value', 'E-Plane cut'), 12, [1 2], 'ValueChangedFcn', @(~, ~) app.on("plane"));
            app.Singel_CheckBox_overlayCut = app.place(uicheckbox(g, 'Text', 'Overlay Cut on 3D Plot'), 13, [1 2], 'ValueChangedFcn', @(~, ~) app.on("cut"));
            app.Single_CheckBox_POB = app.place(uicheckbox(g, 'Text', 'Annotate POB'), 14, [1 2], 'ValueChangedFcn', @(~, ~) app.on("annot"));
            app.Single_CheckBox_HPBWBounds = app.place(uicheckbox(g, 'Text', 'Annotate HPBW Bounds', 'Visible', 'off'), 15, [1 2], 'ValueChangedFcn', @(~, ~) app.on("cut"));

            % --- Status bar and parameter panel
            app.Single_StatusBar = app.place(uilabel(app.Single_Grid, 'Interpreter', 'html', 'Text', 'Ready 🚀', 'Tag', 'main'), 5, [1 14]);
            app.Single_panelParam = app.place(uipanel(app.Single_Grid, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 14]);
            g = uigridlayout(app.Single_panelParam, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'}); app.Single_gridPanel_Param = g;
            app.InputPatternLabel = app.lbl(g, 'Input Pattern:', 1, 1);
            app.Single_EditField_Path = app.place(uieditfield(g, 'text'), 1, [2 8]);
            app.FFDFreqDropDownLabel = app.place(uilabel(g, 'Text', 'FFD Freq:', 'Visible', 'off'), 1, 9);
            app.Single_DropDown_FFD = app.place(uidropdown(g, 'Items', {'Frequencies'}, 'Visible', 'off'), 1, 10, 'ValueChangedFcn', @(~, ~) app.on("block"));
            app.Single_Button_Load = app.place(uibutton(g, 'push', 'Text', '📂 Load File', 'FontSize', 14), 1, [11 12], 'ButtonPushedFcn', @(~, ~) app.on("load"));
            app.Single_Button_Process = app.place(uibutton(g, 'push', 'Text', '⚙️ Process'), 1, [13 14], 'ButtonPushedFcn', @(~, ~) app.on("params"));
            app.Single_Button_ResetParams = app.place(uibutton(g, 'push', 'Text', 'Reset Params'), 2, [1 3], 'ButtonPushedFcn', @(~, ~) app.on("resetparams"));
            app.TextFormatLabel = app.lbl(g, 'Format:', 2, [4 5], 'Visible', 'off');
            app.Single_DropDown_TextFormat = app.place(app.fmtDropdown(g, "format"), 2, [6 8], 'Visible', 'off');
            app.Single_DropDown_step = app.place(uidropdown(g, 'Items', {'STEP'}, 'Visible', 'off'), 2, [9 10], 'ValueChangedFcn', @(~, ~) app.on("step"));
            app.Single_Export_Output = app.place(uibutton(g, 'push', 'Text', '💾 Export Results', 'Visible', 'off'), 2, [11 12], 'ButtonPushedFcn', @(~, ~) app.on("exportresults"));
            app.Single_Export_UAN = app.place(uibutton(g, 'push', 'Text', '💾 Export UAN', 'Visible', 'off'), 2, [13 14], 'ButtonPushedFcn', @(~, ~) app.on("exportuan"));
            app.RxPolLabel = app.lbl(g, 'Rw Sense', 3, 1, 'Visible', 'off');
            app.Single_DropDown_RxPol = app.place(uidropdown(g, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Value', 'Auto', 'Visible', 'off'), 3, 2);
            app.IncidentWaveARRwPLFLabel = app.lbl(g, 'Rw (dB)', 3, 3, 'Visible', 'off');
            app.Single_Spinner_Rw = app.place(uispinner(g, 'Value', 6, 'Visible', 'off'), 3, 4);
            app.LossindBLabel = app.lbl(g, 'Loss (−) / Gain (+) dB', 3, 5, 'Visible', 'off');
            app.Single_Spinner_Loss = app.place(uispinner(g, 'Step', 0.1, 'Visible', 'off'), 3, 6);
            app.TransmitPowerLabel = app.lbl(g, 'Tx Pwr (Pt)', 3, 7, 'Visible', 'off');
            app.Single_Spinner_Pt = app.place(uispinner(g, 'Visible', 'off'), 3, 8);
            app.Single_DropDown_Pt = app.place(uidropdown(g, 'Items', {'dBW', 'dBm', 'Watts'}, 'Value', 'dBW', 'Visible', 'off'), 3, 9);
            app.DistanceLabel = app.lbl(g, 'Distance', 3, 10, 'Visible', 'off');
            app.Single_Spinner_R = app.place(uispinner(g, 'Value', 1, 'Visible', 'off'), 3, 11);
            app.Single_DropDown_R = app.place(uidropdown(g, 'Items', {'m', 'km'}, 'Value', 'm', 'Visible', 'off'), 3, 12);
            app.Single_Button_Coverage = app.place(uibutton(g, 'push', 'Text', '📉 Coverage ▶', 'Visible', 'off'), 3, [13 14], 'ButtonPushedFcn', @(~, ~) app.on("tocoverage"));

            % --- Coverage tab
            app.Tab2_Coverage = uitab(app.TabGroup, 'Title', 'Compute Coverage 📈');
            app.Cov_Grid = uigridlayout(app.Tab2_Coverage, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            app.Cov_Panel_Param = app.place(uipanel(app.Cov_Grid, 'Title', 'Inputs & Parameters 🎛️'), 1, [1 5]);
            g = uigridlayout(app.Cov_Panel_Param, 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'}); app.Cov_gridPanel_Parm = g;
            app.Cov_ButtonGroup_CovType = app.place(uibuttongroup(g, 'Title', 'Coverage Type'), [1 2], [1 2], 'SelectionChangedFcn', @(~, ~) app.on("covtype"));
            app.Cov_ButtonGroup_Btn_Spherical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            app.Cov_ButtonGroup_Btn_Conical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            app.Cov_DropDown_OrientationLabel = app.lbl(g, 'Orientation:', 3, 1, 'Enable', 'off');
            app.Cov_DropDown_Orientation = app.place(uidropdown(g, 'Items', [{'Auto'}, app.Axes6.labels], 'ItemsData', 0:6, 'Value', 0, 'Enable', 'off'), 3, 2, 'ValueChangedFcn', @(~, ~) app.on("covtype"));
            app.AntennaPatternEditFieldLabel = app.lbl(g, 'Antenna Pattern:', 1, 3);
            app.Cov_EditField_filePath = app.place(uieditfield(g, 'text'), 1, [4 8]);
            app.Cov_Button_Load = app.place(uibutton(g, 'push', 'Text', '📂 Load File'), 1, 9, 'ButtonPushedFcn', @(~, ~) app.on("covload"));
            app.Cov_Button_computeCov = app.place(uibutton(g, 'push', 'Text', '⚙️ Compute Coverage', 'Enable', 'off'), 1, 10, 'ButtonPushedFcn', @(~, ~) app.on("covcompute"));
            app.ThresholdMindBSpinnerLabel = app.lbl(g, 'Threshold  Min (dB):', 2, 3);
            app.Cov_Spinner_ThreshMin = app.place(uispinner(g, 'Value', -40), 2, 4, 'ValueChangedFcn', @(~, ~) app.on("covedit"));
            app.ThresholdMaxdBSpinnerLabel = app.lbl(g, 'Threshold  Max (dB):', 2, 5);
            app.Cov_Spinner_ThreshMax = app.place(uispinner(g, 'Value', 10), 2, 6, 'ValueChangedFcn', @(~, ~) app.on("covedit"));
            app.StepdBSpinnerLabel = app.lbl(g, 'Step (dB):', 2, 7);
            app.Cov_Spinner_Step = app.place(uispinner(g, 'Value', 1, 'Limits', [1e-3 100]), 2, 8, 'ValueChangedFcn', @(~, ~) app.on("covedit"));
            app.Cov_Button_Reset = app.place(uibutton(g, 'push', 'Text', '🔄 Reset', 'Enable', 'off'), 2, 9, 'ButtonPushedFcn', @(~, ~) app.on("covreset"));
            app.Cov_Button_Export = app.place(uibutton(g, 'push', 'Text', '💾 Export Results', 'Enable', 'off'), 2, 10, 'ButtonPushedFcn', @(~, ~) app.on("covexport"));
            app.ConeSpinnerLabel = app.lbl(g, 'Cone θ₀ (°):', 3, 3, 'Enable', 'off');
            app.Cov_Spinner_ConeTH = app.place(uispinner(g, 'Limits', [0 180], 'Enable', 'off'), 3, 4);
            app.ConeLabel = app.lbl(g, 'Cone φ₀ (°):', 3, 5, 'Enable', 'off');
            app.Cov_Spinner_ConePH = app.place(uispinner(g, 'Limits', [0 360], 'Enable', 'off'), 3, 6);
            app.ConeAngleLabel = app.lbl(g, 'Cone Angle α (°):', 3, 7, 'Enable', 'off');
            app.Cov_Spinner_ConeAng = app.place(uispinner(g, 'Limits', [0 180], 'Value', 45, 'Enable', 'off'), 3, 8);
            app.Cov_Button_Clear = app.place(uibutton(g, 'push', 'Text', '🧹 Clear DataTips', 'Enable', 'off'), 3, 9, 'ButtonPushedFcn', @(~, ~) app.on("covclear"));
            app.Cov_Button_toMain = app.place(uibutton(g, 'push', 'Text', '📊 To Main ◀ '), 3, 10, 'ButtonPushedFcn', @(~, ~) set(app.TabGroup, 'SelectedTab', app.Tab1_Single));
            app.Cov_DropDown_ComponentLabel = app.lbl(g, 'Component:', 4, 1, 'Enable', 'off');
            app.Cov_DropDown_Component = app.place(uidropdown(g, 'Items', {'E_Total_dB'}, 'Enable', 'off'), 4, 2);
            app.Cov_QueryCoverageLabel = app.lbl(g, 'Coverage @ dB:', 4, 3, 'Visible', 'off');
            app.Cov_Spinner_queryCov = app.place(uispinner(g, 'ValueDisplayFormat', '%g dB', 'Visible', 'off'), 4, 4);
            app.Cov_Button_queryCov = app.place(uibutton(g, 'push', 'Text', 'Query Coverage', 'Visible', 'off'), 4, 5, 'ButtonPushedFcn', @(~, ~) app.on("covquery", "cov"));
            app.Cov_QueryThresholdLabel = app.lbl(g, 'Threshold @ %:', 4, 6, 'Visible', 'off');
            app.Cov_Spinner_queryThresh = app.place(uispinner(g, 'ValueDisplayFormat', '%g%%', 'Value', 50, 'Limits', [0 100], 'Visible', 'off'), 4, 7);
            app.Cov_Button_queryThresh = app.place(uibutton(g, 'push', 'Text', 'Query Threshold', 'Visible', 'off'), 4, 8, 'ButtonPushedFcn', @(~, ~) app.on("covquery", "thr"));
            app.Cov_TextFormatLabel = app.lbl(g, 'Format:', 4, 9, 'Visible', 'off');
            app.Cov_DropDown_TextFormat = app.place(app.fmtDropdown(g, "covformat"), 4, 10, 'Visible', 'off');
            app.Cov_StatusBar = app.place(uilabel(app.Cov_Grid, 'Interpreter', 'html', 'Text', 'Ready 🚀', 'Tag', 'cov'), 3, [1 5]);
            app.Cov_Panel_Results = app.place(uipanel(app.Cov_Grid, 'Title', 'Results', 'Visible', 'off'), 2, [1 5]);
            app.GridLayout2 = uigridlayout(app.Cov_Panel_Results, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});
            app.Cov_Axes = app.place(uiaxes(app.GridLayout2, 'Interactions', dataTipInteraction, 'Box', 'on', 'Layer', 'top', 'YLim', [0 100], 'NextPlot', 'add', 'XGrid', 'on', 'YGrid', 'on'), 1, [2 4]);
            title(app.Cov_Axes, 'Coverage vs Threshold'); xlabel(app.Cov_Axes, 'Threshold (dB)'); ylabel(app.Cov_Axes, 'Coverage (%)');
            app.Cov_Tree = app.place(uitree(app.GridLayout2, 'checkbox'), [1 2], 1, 'SelectionChangedFcn', @(~, ~) app.on("covselect"), 'CheckedNodesChangedFcn', @(~, ~) app.on("covcheck"));
            app.Cov_TreeNode_Results = uitreenode(app.Cov_Tree, 'Text', 'Coverage Results', 'NodeData', struct('kind', "root"));
            app.Cov_Tabel = app.place(uitable(app.GridLayout2, 'ColumnWidth', '1x', 'RowName', {}), [1 2], 5);
            app.Cov_Spinner_XMin = app.place(uispinner(app.GridLayout2, 'Limits', [-250 100], 'Value', -40), 2, 2, 'ValueChangedFcn', @(s, ~) app.on("range", "cov", [s.Value NaN]));
            app.Cov_Spinner_XRange = app.place(uislider(app.GridLayout2, 'range', 'Limits', [-250 100], 'Value', [-40 10]), 2, 3, 'ValueChangedFcn', @(s, ~) app.on("range", "cov", s.Value));
            app.Cov_Spinner_XMax = app.place(uispinner(app.GridLayout2, 'Limits', [-250 100], 'Value', 10), 2, 4, 'ValueChangedFcn', @(s, ~) app.on("range", "cov", [NaN s.Value]));
            app.UIFigure.Visible = 'on';
        end

        function startupFcn(app)
            % Graphics that exist for the life of the app: one context menu, one colorbar per view, one POB marker per view.
            app.PlotMenu = uicontextmenu(app.UIFigure);
            uimenu(app.PlotMenu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, e) delete(findobj(ancestor(e.ContextObject, {'axes', 'polaraxes'}), 'Type', 'datatip')));
            axesList = {app.Single_Axes_Ctr, app.PaxPattern, app.Single_Axes_3dSph, app.Single_Axes_3dPol, app.Single_Axes_3dRect};
            for k = 1:5
                ax = axesList{k}; ax.ContextMenu = app.PlotMenu; ax.NextPlot = 'add';
                if k >= 3, ax.Interactions = [rotateInteraction, dataTipInteraction]; elseif k == 1, ax.Interactions = [zoomInteraction, dataTipInteraction]; end
                hold(ax, 'on');   % retained axes are additive: chart-level creators (surf/plot3) add without resetting the axes
                app.Gfx.(app.FullTabs(k)) = struct('ax', ax, 'surf', gobjects(0), 'pob', gobjects(0), 'tip', gobjects(0), 'overlay', gobjects(0), 'cb', colorbar(ax), 'triad', gobjects(0), 'size', [0 0]);
            end
            set([app.Single_AxesRect, app.PaxCut], 'ContextMenu', app.PlotMenu);
            app.Single_AxesRect.Interactions = [zoomInteraction, dataTipInteraction];
            app.StatusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, 'TimerFcn', @(~, ~) app.restoreStatus());
            V = app.readConfig(); app.Defaults = V.Params;
            app.applyCoverageUI();
        end
    end

    %% ------------------------------------------------------------------ orchestration
    methods (Access = private)
        function on(app, scope, varargin)
            % The only callback. Owns re-entrancy, error handling, cancellation, perf and the single drawnow.
            if app.Busy, return; end
            app.Busy = true; guard = onCleanup(@() app.clearBusy()); app.PerfClock = tic;
            try
                switch scope
                    case "load",          app.loadMain('');
                    case "format",        if app.Main > 0 && io_isGeneric(app.Pats(app.Main).Path), app.loadMain(app.Pats(app.Main).Path); end
                    case {"block", "step"}, app.update("pattern");
                    case "params",        app.update("derived");
                    case "resetparams",   app.writeParams(app.Defaults); app.update("derived");
                    case "component",     app.update("component");
                    case "span",          app.update("span");
                    case "plane",         app.applyPlane(); app.applyChoices(false); app.update("cut");
                    case "cut",           app.update("cut");
                    case "annot",         app.applyAnnotations();
                    case "fulltab",       app.renderFull();
                    case "cstep",         app.Dirty(:) = true; app.renderFull();
                    case "view3d",        app.applyView3D();
                    case "range",         app.applyRange(varargin{:}, true);
                    case "filter",        app.applyTables(true);
                    case "exportresults", app.exportResults();
                    case "exportuan",     app.exportUAN();
                    case "exportcut",     app.exportCut();
                    otherwise,            app.onCoverage(scope, varargin{:});
                end
                drawnow limitrate
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.setStatus(app.Single_StatusBar, 'Cancelled by user.', true);
                else, app.showError(ME, sprintf('%s error', scope)); end
            end
            app.perf(scope, "total");
        end

        function clearBusy(app), app.Busy = false; if ~isempty(app.Dlg) && isvalid(app.Dlg), close(app.Dlg); end, app.Dlg = []; end

        function perf(app, action, stage)
            % Eight-line tracker: one record per stage; inspect Perf_APAT_v3_M8 in the base workspace.
            app.Perf(end + 1) = struct('action', string(action), 'stage', string(stage), 'seconds', toc(app.PerfClock));
            app.PerfClock = tic;
            assignin('base', 'Perf_APAT_v3_M8', app.Perf);
        end

        function tick(app, message)
            % Progress + cancellation check between pipeline stages.
            if isempty(app.Dlg) || ~isvalid(app.Dlg), return; end
            if app.Dlg.CancelRequested, error('APAT:Cancelled', 'Cancelled'); end
            app.Dlg.Message = message; drawnow limitrate
        end

        function V = readConfig(app)
            % The ONLY reader of Main-tab widget values (I11).
            V.Component = app.Single_DropDown_Component.Value;
            V.CutType = string(app.Single_DropDown_cutType.Value);
            V.CutValue = app.Single_DropDown_cutValue.Value;
            V.SignedPhi = strcmp(app.Single_Switch_AngularSpan.Value, '-180° to 180°');
            V.Elevation = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°');
            V.Basis = string(app.CutFieldBasisDropDown.Value);
            V.Traces = logical([app.CheckBox_Et.Value, app.CheckBox_Er.Value, app.CheckBox_El.Value]);
            V.HPBW = app.Button_HPBW.Value; V.HPBWTips = app.Single_CheckBox_HPBWBounds.Value;
            V.POB = app.Single_CheckBox_POB.Value; V.Overlay = app.Singel_CheckBox_overlayCut.Value;
            V.View3D = string(app.Single_DropDown_3DView.Value);
            V.CStep = app.Single_Plot_Cstep.Value;
            V.Block = max([1, find(strcmp(app.Single_DropDown_FFD.Items, app.Single_DropDown_FFD.Value), 1)]);
            V.OneDegree = strcmp(app.Single_DropDown_step.Value, ['STEP: 1' char(176)]);
            V.Format = string(app.Single_DropDown_TextFormat.Value);
            V.FullTab = string(app.Single_tabPlots.SelectedTab.Tag);
            V.PolarCutShown = app.Single_tabCut.SelectedTab == app.Single_tabPolarPlot;
            p = struct('Loss_dB', app.Single_Spinner_Loss.Value, 'RxMode', string(app.Single_DropDown_RxPol.Value), 'RxAR_dB', app.Single_Spinner_Rw.Value, ...
                'Pt', app.Single_Spinner_Pt.Value, 'PtUnit', string(app.Single_DropDown_Pt.Value), 'R', app.Single_Spinner_R.Value, 'RUnit', string(app.Single_DropDown_R.Value));
            switch p.PtUnit, case "dBm", p.Pt_dBW = p.Pt - 30; case "Watts", p.Pt_dBW = 10*log10(max(p.Pt, eps)); otherwise, p.Pt_dBW = p.Pt; end
            p.R_m = max(p.R, app.DistanceFloorM) * (1 + 999*(p.RUnit == "km"));
            V.Params = p;
        end

        function writeParams(app, p)
            [app.Single_Spinner_Loss.Value, app.Single_DropDown_RxPol.Value, app.Single_Spinner_Rw.Value, app.Single_Spinner_Pt.Value, ...
                app.Single_DropDown_Pt.Value, app.Single_Spinner_R.Value, app.Single_DropDown_R.Value] = deal(p.Loss_dB, char(p.RxMode), p.RxAR_dB, p.Pt, char(p.PtUnit), p.R, char(p.RUnit));
        end

        function loadMain(app, fp)
            % Browse (or reuse fp), read, register and run the full pipeline. Coverage-results files route to the Coverage tab.
            if isempty(fp)
                fp = strtrim(app.Single_EditField_Path.Value);
                if ~isfile(fp)
                    [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.csv;*.dat;*.txt', 'Pattern/Gain Files'}, 'Select an antenna pattern file');
                    if isequal(f, 0), return; end
                    fp = fullfile(p, f);
                end
            end
            app.Dlg = uiprogressdlg(app.UIFigure, 'Title', 'Loading Data', 'Message', 'Reading file...', 'Indeterminate', 'on', 'Cancelable', 'on');
            S = io_read(fp, app.Single_DropDown_TextFormat.Value);
            app.perf("load", "read");
            if S.Meta.IsCoverage
                app.TabGroup.SelectedTab = app.Tab2_Coverage; app.Cov_EditField_filePath.Value = fp;
                app.covLoadResults(fp, S.Raw); return
            end
            app.Single_EditField_Path.Value = fp;
            set([app.TextFormatLabel, app.Single_DropDown_TextFormat], 'Visible', S.Meta.IsGeneric);
            k = app.registerSource(fp, S); app.Main = k;
            items = compose('Pattern %d: %.4g GHz', (1:numel(S.Blocks))', S.Freqs(:)/1e9); items(isnan(S.Freqs(:))) = compose('Pattern %d', find(isnan(S.Freqs(:))));
            items = cellstr(items); set(app.Single_DropDown_FFD, 'Items', items, 'Value', items{1});
            set([app.Single_DropDown_FFD, app.FFDFreqDropDownLabel], 'Visible', numel(items) > 1);
            set(app.Single_DropDown_step, 'Items', {'STEP'}, 'Value', 'STEP');   % a new file always starts at its native step
            app.Single_Table_DataIn.Data = S.Raw; app.Single_Table_DataIn.ColumnName = S.Raw.Properties.VariableNames; app.Single_Table_DataIn.Visible = 'on';
            app.update("source");
        end

        function k = registerSource(app, fp, S)
            % One registry entry per path; reloading replaces the entry in place so coverage nodes keep their index.
            k = find(strcmp({app.Pats.Path}, fp), 1);
            if isempty(k), k = numel(app.Pats) + 1; end
            [~, name] = fileparts(fp);
            app.Pats(k).Name = name; app.Pats(k).Path = fp; app.Pats(k).Source = S;
            app.Pats(k).Pattern = []; app.Pats(k).Derived = []; app.Pats(k).Geometry = []; app.Pats(k).Params = [];
        end

        function derive(app, k, block, oneDegree, params)
            % Build-then-commit (I13): the registry entry is replaced only when every stage succeeded.
            E = app.Pats(k);
            if isempty(E.Pattern) || E.Pattern.Block ~= block || E.Pattern.OneDegree ~= oneDegree
                P = pat_build(E.Source, block); app.tick('Building pattern...');
                if oneDegree, P = pat_resample(P, 1); end
                P.Block = block; P.OneDegree = oneDegree;
                E.Pattern = P; E.Geometry = geo_build(P);
            end
            app.tick('Deriving quantities...');
            E.Derived = pat_derive(E.Pattern, E.Geometry, params, app.Axes6, app.PeakExcessDB, app.ConeHalfAngleDeg, app.PLFTiltDeg, app.LinearARFloorDB);
            E.Params = params;
            app.Pats(k) = E;
        end

        function update(app, level)
            % level: "source" ⊃ "pattern" ⊃ "derived" ⊃ "component" | "span" ⊃ "cut". Each level recomputes only its invalidation radius.
            k = app.Main; if k == 0, return; end
            V = app.readConfig();
            if any(level == ["source", "pattern", "derived"])
                if level == "source", V.OneDegree = false; V.Block = 1; end
                app.derive(k, V.Block, V.OneDegree, V.Params); app.perf("update", "derive");
                app.applyChoices(level == "source"); V = app.readConfig();
                if level == "source", app.Range.AutoFull = true; end
                if level ~= "derived" && app.Range.AutoFull, app.applyRange("all", util_presetRange(app.Pats(k).Derived.Peak.value), false); end
            end
            app.View = V; app.Map = geo_displayMap(app.Pats(k).Pattern, app.Pats(k).Geometry, V);
            if level == "span", app.applyChoices(false); app.View = app.readConfig(); end
            if level ~= "cut"
                app.Dirty(:) = true; app.renderFull(); app.perf("update", "full");
                if level ~= "component" && level ~= "span", app.applyTables(true); end
                app.applyMetadata();
            end
            app.renderCut(); app.perf("update", "cut");
            app.applyVisibility();
        end

        function applyChoices(app, newSource)
            % Items/limits that follow the loaded pattern: component list, step list, cut-value domain, trace labels, output filter.
            E = app.Pats(app.Main); D = E.Derived; P = E.Pattern; V = app.readConfig();
            dd = app.Single_DropDown_Component; previous = string(dd.Value);
            [dd.Items, dd.ItemsData] = deal(cellstr(D.Labels(D.Menu)), cellstr(D.Names(D.Menu)));
            if any(D.Names(D.Menu) == previous), dd.Value = char(previous); else, dd.Value = char(D.Total); end
            native = max(P.NativeStep);
            items = {sprintf('STEP: %g%c', native, char(176))}; if abs(native - 1) > 1e-9, items{end + 1} = ['STEP: 1' char(176)]; end
            app.Single_DropDown_step.Items = items; app.Single_DropDown_step.Value = items{1 + (V.OneDegree && numel(items) > 1)};
            set(app.Single_DropDown_step, 'Visible', numel(items) > 1, 'Enable', numel(items) > 1);
            if numel(app.ShowCols) ~= numel(D.Names), app.ShowCols = ~ismember(D.Names, app.HiddenCols); end
            if newSource
                app.CutFieldBasisDropDown.Value = char(D.Pol.Basis);
                app.ShowCols = ~ismember(D.Names, app.HiddenCols);
                names = cellstr(D.Names);
                set(app.Single_DropDown_output, 'Items', [{'--- column filter ---'}, names], 'ItemsData', 0:numel(names), 'Value', 0);
                set([app.Single_DropDown_output, app.Single_Table_DataOut, app.Single_tabData], 'Visible', 'on');
                app.applyPlane();
            end
            V = app.readConfig();   % basis and cut type may have just been written above
            pair = D.Pol.Pairs.(V.Basis); [app.CheckBox_Er.Text, app.CheckBox_El.Text] = deal(char(pair(1)), char(pair(2)));
            M = geo_displayMap(P, E.Geometry, V);
            if V.CutType == "Phi", domain = M.ThetaAxis; step = P.dTheta; else, domain = M.PhiAxis; step = P.dPhi; end
            sp = app.Single_DropDown_cutValue; sp.Limits = [-Inf Inf]; if step > 0, sp.Step = step; end
            [~, nearest] = min(abs(domain - sp.Value)); sp.Value = domain(nearest);
            % sp.Limits = [min(domain), max(domain) + step*(min(domain) == max(domain))];
            sp.Limits = [min(domain), max(domain) + (min(domain) == max(domain))];   % +1° keeps Limits strictly increasing
        end

        function applyPlane(app)
            % E/H switch → cut controls (display convention through Map, I8). E-plane: φ = boresight φ; H-plane: orthogonal principal plane.
            E = app.Pats(app.Main); V = app.readConfig(); pl = E.Derived.Planes;
            if strcmp(app.Single_Switch_EHplane.Value, 'E-Plane cut'), cut = pl.E; else, cut = pl.H; end
            app.Single_DropDown_cutType.Value = char(cut.Type);
            value = cut.Value;
            if cut.Type == "Phi" && V.Elevation, value = 90 - value; elseif cut.Type == "Theta" && V.SignedPhi && value > 180, value = value - 360; end
            app.Single_DropDown_cutValue.Limits = [-Inf Inf]; app.Single_DropDown_cutValue.Value = value;   % applyChoices restores the grid domain
        end

        function applyRange(app, group, limits, userDriven)
            % One range writer for every slider/spinner group. NaN in limits keeps the current bound. group ∈ full | cut | all | cov.
            groups = string(group); if group == "all", groups = ["full", "cut"]; end
            for gname = groups
                current = app.Range.(gname); limits = double(limits(:)'); limits(isnan(limits)) = current(isnan(limits));
                limits = sort(limits); if diff(limits) < 1, limits(2) = limits(1) + 1; end
                limits = min(max(limits, -250), 100); app.Range.(gname) = limits;
                switch gname
                    case "full"
                        app.Range.AutoFull = ~userDriven;
                        set([app.Range_Ctr, app.Range_Cir, app.Range_3dSph, app.Range_3dPol, app.Range_3dRect], 'Value', limits);
                        set([app.Range_Ctr_Min, app.Range_Cir_Min, app.Range_3dSph_Min, app.Range_3dPol_Min, app.Range_3dRect_Min, app.Single_Plot_Cmin], 'Value', limits(1));
                        set([app.Range_Ctr_Max, app.Range_Cir_Max, app.Range_3dSph_Max, app.Range_3dPol_Max, app.Range_3dRect_Max, app.Single_Plot_Cmax], 'Value', limits(2));
                        if app.Main > 0 && userDriven, app.Dirty(:) = true; app.renderFull(); end
                    case "cut"
                        app.Range_Cut.Value = limits; app.Range_Cut_Min.Value = limits(1); app.Range_Cut_Max.Value = limits(2);
                        if app.Main > 0 && userDriven, app.renderCut(); end
                    case "cov"
                        app.Range.AutoCov = ~userDriven;
                        app.Cov_Spinner_XRange.Value = limits; app.Cov_Spinner_XMin.Value = limits(1); app.Cov_Spinner_XMax.Value = limits(2);
                        app.Cov_Axes.XLim = limits;
                end
            end
        end

        function applyVisibility(app)
            % Panel and parameter visibility follow what is loaded and which column kinds are shown (D69).
            E = app.Pats(app.Main); D = E.Derived; hasField = ~E.Pattern.IsGainOnly;
            set([app.Single_Panel_Rect, app.Single_Export_Output, app.Single_Panel_fullPattern, app.Single_Panel_plotControl, app.Single_Button_Coverage], 'Visible', 'on');
            set([app.Single_Export_UAN, app.Single_gridEcut, app.CheckBox_Et, app.CheckBox_Er, app.CheckBox_El], 'Visible', hasField);
            set([app.CheckBox_Er, app.CheckBox_El, app.CutFieldBasisDropDown], 'Enable', hasField);
            shown = D.Kind(app.ShowCols);
            set([app.RxPolLabel, app.Single_DropDown_RxPol, app.IncidentWaveARRwPLFLabel, app.Single_Spinner_Rw], 'Visible', any(shown == "plf"));
            set([app.TransmitPowerLabel, app.Single_Spinner_Pt, app.Single_DropDown_Pt], 'Visible', any(shown == "eirp" | shown == "pfd" | shown == "field"));
            set([app.DistanceLabel, app.Single_Spinner_R, app.Single_DropDown_R], 'Visible', any(shown == "pfd" | shown == "field"));
            set([app.LossindBLabel, app.Single_Spinner_Loss], 'Visible', any(shown ~= "phase"));
            pk = D.Peak; polText = '';
            if hasField, polText = sprintf(' | Polarization <b>%s</b>', D.Pol.Label); end
            app.setStatus(app.Single_StatusBar, sprintf('Pattern: <b>%s</b> | POB <b>%s %s</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)%s', E.Name, util_fmtNumber(pk.value, 2), ...
                E.Pattern.Meta.UnitLabel, util_fmtNumber(pk.theta), util_fmtNumber(pk.phi), polText), false);
        end

        function applyTables(app, filterChanged)
            % Results table = Derived columns as one long table, filtered by ShowCols. Built only when Derived or the filter changed.
            dd = app.Single_DropDown_output; D = app.Pats(app.Main).Derived;
            if filterChanged && dd.Value > 0, app.ShowCols(dd.Value) = ~app.ShowCols(dd.Value); dd.Value = 0; end
            names = cellstr(D.Names); on = find(app.ShowCols);
            dd.Items = [{'--- column filter ---'}, names]; dd.Items(on + 1) = append('✓ ', dd.Items(on + 1));
            T = app.longTable(D, D.Names(app.ShowCols));
            app.Single_Table_DataOut.Data = T; app.Single_Table_DataOut.ColumnName = T.Properties.VariableNames;
            if app.Main > 0, app.applyVisibility(); end
        end

        function T = longTable(app, D, names)
            % Canonical long table (θ, φ, columns…) in the display convention of the active Map.
            M = app.Map;
            [phiGrid, thetaGrid] = meshgrid(M.PhiAxis, M.ThetaAxis);
            T = table(thetaGrid(:), phiGrid(:), 'VariableNames', {'Theta', 'Phi'});
            for n = names(:).', C = D.Cols.(n)(:, M.ColIdx); T.(n) = C(:); end
        end

        function applyMetadata(app)
            E = app.Pats(app.Main); P = E.Pattern; G = E.Geometry; D = E.Derived; m = D.Metrics; f = @util_fmtNumber;
            rows = {'Source format', P.Meta.Format; 'File', E.Name; 'Level unit', P.Meta.UnitLabel; ...
                'Samples', sprintf('%d samples (θ: %d × φ: %d)', numel(P.Theta)*numel(P.Phi), numel(P.Theta), numel(P.Phi)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', f(P.Theta(1)), f(P.Theta(end)), f(P.dTheta)); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', f(P.Phi(1)), f(P.Phi(end)), f(P.dPhi)); ...
                'Sphere coverage', sprintf('Ω = %s sr (%s), φ periodic: %s', f(G.Omega, 3), util_pick(G.IsFullSphere, 'full sphere', 'partial sphere'), util_pick(G.PhiPeriodic, 'yes', 'no'))};
            if any(isfinite(E.Source.Freqs)), rows(end + 1, :) = {'Frequencies', strjoin(compose('%.4g GHz', E.Source.Freqs(isfinite(E.Source.Freqs))/1e9), ', ')}; end
            if ~P.IsGainOnly
                rows = [rows; {'Polarization', D.Pol.Label; 'Cut Co-pol / Cross-pol', char(strjoin(D.Pol.Pairs.(app.View.Basis), ' / '))}];
                rows = [rows; {'Parameters', sprintf('Loss %s dB | Rx %s (Rw %s dB) | Pt %s dBW | R %s m', f(E.Params.Loss_dB), E.Params.RxMode, f(E.Params.RxAR_dB), f(E.Params.Pt_dBW), f(E.Params.R_m))}];
            end
            rows = [rows; {'Peak (POB)', sprintf('%s %s at [θ %s°, φ %s°]', f(D.Peak.value), P.Meta.UnitLabel, f(D.Peak.theta), f(D.Peak.phi)); ...
                'Peak policy', sprintf('spatial isolation > %g dB; spikes: %d; raw max %s dB', app.PeakExcessDB, D.Peak.spikeCount, f(D.Peak.rawValue)); ...
                'Boresight axis', app.Axes6.labels{D.Boresight}; ...
                'HPBW E-plane / H-plane', sprintf('%s° / %s°', f(m.HPBW_E), f(m.HPBW_H)); 'Peak directivity', sprintf('%s dB', f(m.Directivity_dB)); ...
                'Front-to-back', sprintf('%s dB', f(m.FrontBack_dB)); 'Radiation efficiency', sprintf('%s%%', f(m.Efficiency_pct)); 'AR at peak', sprintf('%s dB', f(m.AR_at_peak_dB))}];
            for n = 1:numel(P.Meta.Notes), rows(end + 1, :) = {sprintf('Note %d', n), char(P.Meta.Notes(n))}; end %#ok<AGROW>
            app.Single_Table_metadata.Data = cellfun(@(v) char(string(v)), rows, 'UniformOutput', false);
        end

        function setStatus(app, label, message, transient)
            % Persistent text lives in app.Status; a transient message is restored by the single timer.
            stop(app.StatusTimer); label.Text = char(message);
            if ~transient, app.Status.(label.Tag) = char(message); return; end
            app.StatusTimer.UserData = label; start(app.StatusTimer);
        end

        function restoreStatus(app)
            label = app.StatusTimer.UserData;
            if ~isempty(label) && isvalid(label), label.Text = app.Status.(label.Tag); end
        end

        function stopTimer(app)
            if ~isempty(app.StatusTimer) && isvalid(app.StatusTimer), stop(app.StatusTimer); delete(app.StatusTimer); end
        end

        function showError(app, ME, titleText)
            if isempty(app.UIFigure) || ~isvalid(app.UIFigure), rethrow(ME); end
            uialert(app.UIFigure, ME.message, titleText, 'Icon', 'error');
        end

        function exportResults(app)
            if app.Main == 0, return; end
            E = app.Pats(app.Main);
            [f, p] = uiputfile({'*.csv', 'Comma-delimited (*.csv)'; '*.txt', 'Tab-delimited (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'}, 'Export Results', fullfile(fileparts(E.Path), [E.Name '_APAT_results.csv']));
            if isequal(f, 0), return; end
            writetable(app.Single_Table_DataOut.Data, fullfile(p, f), 'WriteVariableNames', true);
            app.setStatus(app.Single_StatusBar, ['Results exported to <b>' fullfile(p, f) '</b>'], true);
        end

        function exportUAN(app)
            E = app.Pats(app.Main); D = E.Derived; P = E.Pattern;
            if P.IsGainOnly, uialert(app.UIFigure, 'No E-field data to export.', 'Export UAN'); return; end
            [phiGrid, thetaGrid] = meshgrid(P.Phi, P.Theta);
            T = table(thetaGrid(:), phiGrid(:), round(D.Cols.E_TH_dB(:), 5), round(D.Cols.E_PH_dB(:), 5), round(D.Cols.E_TH_Phase(:), 5), round(D.Cols.E_PH_Phase(:), 5), ...
                'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'});
            T = sortrows(T, {'Phi', 'Theta'});
            [f, p] = uiputfile({'*.uan', 'XGTD user-defined antenna (*.uan)'; '*.csv', 'CSV (*.csv)'; '*.txt', 'Text (*.txt)'}, 'Export UAN / E-field data', ...
                fullfile(fileparts(E.Path), sprintf('%s_%.5f_%gdeg.uan', E.Name, D.Peak.value, P.dTheta)));
            if isequal(f, 0), return; end
            fp = fullfile(p, f);
            if endsWith(fp, '.uan', 'IgnoreCase', true)
                fid = fopen(fp, 'w'); c = onCleanup(@() fclose(fid));
                fprintf(fid, 'begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\ncomplex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>\n', ...
                    P.Phi(1), P.Phi(end), P.dPhi, P.Theta(1), P.Theta(end), P.dTheta, D.Peak.value);
                fprintf(fid, '%g %g %.5f %.5f %.5f %.5f\n', T{:, :}.');
            else
                writetable(T, fp);
            end
            app.setStatus(app.Single_StatusBar, ['UAN exported to <b>' fp '</b>'], true);
        end

        function exportCut(app)
            if app.Main == 0, return; end
            cut = app.currentCut(); E = app.Pats(app.Main);
            [f, p] = uiputfile({'*.csv'; '*.txt'}, 'Export Cut', fullfile(fileparts(E.Path), sprintf('%s_%s_cut_%g.csv', E.Name, cut.Type, cut.Fixed)));
            if isequal(f, 0), return; end
            writetable(array2table([cut.Angle, cut.Theta, cut.Phi, cut.Values], 'VariableNames', [{'Angle', 'Theta', 'Phi'}, cellstr(cut.Names)]), fullfile(p, f));
            app.setStatus(app.Single_StatusBar, ['Cut exported to <b>' fullfile(p, f) '</b>'], true);
        end
    end

    %% ------------------------------------------------------------------ rendering (retained graphics, visible tab only)
    methods (Access = private)
        function [limits, cmap] = theme(app, kind)
            % Signed AR: fixed ±30 dB blue-white-red. Everything else: the shared gain range with jet.
            persistent jetMap arMap
            if isempty(jetMap), jetMap = jet(256); arMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
            if kind == "ar", limits = [-30 30]; cmap = arMap; else, limits = app.Range.full; cmap = jetMap; end
        end

        function renderFull(app)
            % Render the visible full-pattern view if dirty. Surfaces are created once per grid size and updated by data assignment (I12).
            if app.Main == 0, return; end
            key = string(app.Single_tabPlots.SelectedTab.Tag); slot = find(app.FullTabs == key);
            if ~app.Dirty(slot), return; end
            E = app.Pats(app.Main); D = E.Derived; P = E.Pattern; M = app.Map; V = app.View; g = app.Gfx.(key); ax = g.ax;
            C = D.Cols.(V.Component)(:, M.ColIdx); label = D.Labels(D.Names == V.Component);
            [limits, cmap] = app.theme(D.Kind(D.Names == V.Component));
            [phiGrid, thetaGrid] = meshgrid(M.PhiAxis, M.ThetaAxis);
            thetaPhys = repmat(P.Theta, 1, numel(M.ColIdx)); phiRad = deg2rad(phiGrid);
            unitR = 1; if key == "pol", unitR = min(max((C - limits(1)) / diff(limits), 0), 1); end
            switch key
                case "ctr",  X = phiGrid; Y = thetaGrid; Z = zeros(size(C));
                case "cir",  X = phiRad; Y = thetaPhys; Z = zeros(size(C));
                case "rect", X = phiGrid; Y = thetaGrid; Z = C;
                otherwise,   X = unitR .* sind(thetaPhys) .* cos(phiRad); Y = unitR .* sind(thetaPhys) .* sin(phiRad); Z = unitR .* cosd(thetaPhys);
            end
            if isempty(g.surf) || ~isvalid(g.surf) || ~isequal(g.size, size(C))
                delete([g.surf, g.pob, g.triad]);
                g.surf = surf(ax, X, Y, Z, C, 'EdgeColor', 'none', 'ContextMenu', app.PlotMenu); g.size = size(C);
                if key == "cir", g.pob = polarplot(ax, 0, 0, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off');
                % else, g.pob = line(ax, 0, 0, 0, 'LineStyle', 'none', 'Marker', 'o', 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'k', 'MarkerSize', 5, 'Clipping', 'off', 'HandleVisibility', 'off'); end
                else, g.pob = plot3(ax, 0, 0, 0, 'o', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'Clipping', 'off', 'HandleVisibility', 'off'); end
                g.tip = datatip(g.pob, 'DataIndex', 1, 'FontSize', 9, 'Visible', 'off');
                if any(key == ["sph", "pol"]), g.triad = app.drawTriad(ax); end
            else
                set(g.surf, 'XData', X, 'YData', Y, 'ZData', Z, 'CData', C);
            end
            g.surf.DataTipTemplate.DataTipRows = [dataTipTextRow('θ', thetaPhys, '%.2f°'), dataTipTextRow('φ', phiGrid, '%.2f°'), dataTipTextRow(label, C, '%.2f')];
            clim(ax, limits); colormap(ax, cmap); ticks = util_ticks(limits, V.CStep);
            if isempty(ticks), g.cb.TicksMode = 'auto'; else, g.cb.Ticks = ticks; end
            titleText = sprintf('%s  |  θ: %s  |  φ: %s', label, app.Single_Switch_ThetaSpan.Value, app.Single_Switch_AngularSpan.Value);
            switch key
                case "ctr"
                    set(ax, 'XLim', M.PhiLim, 'YLim', M.ThetaLim, 'YDir', M.ThetaDir, 'XTick', M.PhiLim(1):30:M.PhiLim(2), 'YTick', M.ThetaLim(1):15:M.ThetaLim(2), 'Box', 'on', 'Layer', 'top');
                    view(ax, 2); xlabel(ax, 'Phi (degree)'); ylabel(ax, M.ThetaLabel + " (degree)");
                case "cir"
                    ticks = 0:30:330; if V.SignedPhi, ticks(ticks > 180) = ticks(ticks > 180) - 360; end
                    rt = 0:30:180; if V.Elevation, rt = 90 - rt; end
                    set(ax, 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', rt), 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', ticks));
                    titleText = sprintf('%s  |  r=θ, angle=φ', label);
                case "rect"
                    set(ax, 'XLim', M.PhiLim, 'YLim', M.ThetaLim, 'ZLim', limits, 'YDir', M.ThetaDir, 'XTick', M.PhiLim(1):60:M.PhiLim(2), 'YTick', M.ThetaLim(1):30:M.ThetaLim(2), 'ZTick', util_ticks(limits, V.CStep), 'Box', 'on');
                    grid(ax, 'on'); xlabel(ax, 'Phi (degree)'); ylabel(ax, M.ThetaLabel + " (degree)"); zlabel(ax, label + " (" + P.Meta.UnitLabel + ")");
                otherwise
                    set(ax, 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1], 'Projection', 'orthographic', 'Visible', 'off');
            end
            title(ax, titleText, 'Interpreter', 'none', 'FontSize', 9);
            % POB marker of the displayed component (plots only, I4): physical peak → display column.
            pk = met_peak(D.Cols.(V.Component), E.Geometry.PhiPeriodic, app.PeakExcessDB); jd = find(M.ColIdx == pk.col, 1);
            pos = [X(pk.row, jd), Y(pk.row, jd), Z(pk.row, jd)];
            if key == "ctr", pos(3) = 1; elseif key == "sph", pos = 1.02 * pos; end
            if key == "cir", set(g.pob, 'ThetaData', pos(1), 'RData', pos(2)); else, set(g.pob, 'XData', pos(1), 'YData', pos(2), 'ZData', pos(3)); end
            g.pob.DataTipTemplate.DataTipRows = [dataTipTextRow('θ', P.Theta(pk.row), '%.2f°'); dataTipTextRow('φ', M.PhiAxis(jd), '%.2f°'); dataTipTextRow(label, pk.value, '%.2f')];
            set([g.pob, g.tip], 'Visible', V.POB);
            app.Gfx.(key) = g; app.Dirty(slot) = false;
            app.applyView3D(); app.renderOverlay();
        end

        function h = drawTriad(~, ax)
            % Principal axes X red / Y green / Z blue with their (θ, φ) labels; drawn once per 3-D axes.
            colors = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]}; labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'}; d = 1.35 * eye(3);
            h = gobjects(1, 6);
            for k = 1:3
                h(k) = quiver3(ax, 0, 0, 0, d(k, 1), d(k, 2), d(k, 3), 0, 'Color', colors{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25, 'HandleVisibility', 'off');
                h(k + 3) = text(ax, 1.12*d(k, 1), 1.12*d(k, 2), 1.12*d(k, 3), labels{k}, 'Color', colors{k}, 'FontWeight', 'bold');
            end
        end

        function applyView3D(app)
            views = struct('iso', [135 25], 'top', [0 90], 'bottom', [0 -90], 'right', [90 0], 'left', [-90 0], 'front', [0 0], 'back', [180 0]);
            code = app.Single_DropDown_3DView.Value; v = views.(code);
            for ax = [app.Single_Axes_3dSph, app.Single_Axes_3dPol]
                view(ax, v(1), v(2)); if any(strcmp(code, {'top', 'bottom'})), camup(ax, [0 1 0]); else, camup(ax, [0 0 1]); end
            end
            if strcmp(code, 'iso'), view(app.Single_Axes_3dRect, -35, 35); else, view(app.Single_Axes_3dRect, v(1), v(2)); end
        end

        function renderOverlay(app)
            % Cut overlay on the 3-D views: one retained line per view, same radius law as the surface (D60).
            cut = []; 
            for key = ["sph", "pol"]
                g = app.Gfx.(key); delete(g.overlay); g.overlay = gobjects(0);
                if app.View.Overlay && ~app.Dirty(app.FullTabs == key)
                    if isempty(cut), cut = app.currentCut(); end
                    if key == "sph", r = 1.02; else, lim = app.theme(app.Pats(app.Main).Derived.Kind(app.Pats(app.Main).Derived.Names == app.View.Component)); r = 1.01 * min(max((cut.Values(:, 1) - lim(1)) / diff(lim), 0), 1); end
                    g.overlay = line(g.ax, r .* sind(cut.Theta) .* cosd(cut.Phi), r .* sind(cut.Theta) .* sind(cut.Phi), r .* cosd(cut.Theta), 'Color', 'k', 'LineWidth', 1.6, 'HandleVisibility', 'off');
                end
                app.Gfx.(key) = g;
            end
        end

        function cut = currentCut(app)
            % The active cut in physical angles: traces, snapped fixed angle and a full 0..360° sweep (one geo_cut per change, D15/D61).
            E = app.Pats(app.Main); D = E.Derived; P = E.Pattern; V = app.View;
            if P.IsGainOnly, names = string(V.Component); idx = 1;
            else, names = ["E_Total_dB", D.Pol.Pairs.(V.Basis) + "_dB"]; sel = V.Traces; if ~any(sel), sel(1) = true; end, idx = find(sel); names = names(idx); end
            value = V.CutValue;
            if V.CutType == "Phi" && V.Elevation, value = 90 - value; elseif V.CutType == "Theta", value = mod(value, 360); end
            cut = geo_cut(P, D.Cols, names, V.CutType, value);
            cut.Names = names; cut.Idx = idx; cut.Type = V.CutType;
            shown = cut.Fixed; symbol = 'φ';
            if V.CutType == "Phi", symbol = 'θ'; if V.Elevation, shown = 90 - shown; end, elseif V.SignedPhi && shown > 180, shown = shown - 360; end
            if P.IsGainOnly, cut.Title = char(D.Labels(D.Names == V.Component)); else, cut.Title = sprintf('%s cut @ %s = %g°', V.CutType, symbol, shown); end
            if cut.Snapped, app.setStatus(app.Single_StatusBar, sprintf('Requested %s cut snapped to nearest %s = %g°', V.CutType, symbol, shown), true); end
        end

        function renderCut(app)
            % Polar + rectangular cut with POB marker, HPBW shading and optional boundary tips. Cheap enough to redraw fully.
            if app.Main == 0, return; end
            cut = app.currentCut(); V = app.View; pax = app.PaxCut; rax = app.Single_AxesRect; lim = app.Range.cut;
            angle = cut.Angle; vals = cut.Values;
            if V.SignedPhi
                angle = mod(angle + 180, 360) - 180; [angle, order] = unique(angle, 'first'); vals = vals(order, :);
                if angle(1) == -180, angle(end + 1) = 180; vals(end + 1, :) = vals(1, :); end
                xlimits = [-180 180];
            else
                xlimits = [0 360];
            end
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on');
            pl = polarplot(pax, deg2rad(angle), max(vals, lim(1)), 'LineWidth', 1.4); rl = plot(rax, angle, vals, 'LineWidth', 1.4);
            colors = rax.ColorOrder(1 + mod(cut.Idx - 1, 7), :);
            for k = 1:numel(pl)
                rows = [dataTipTextRow("Angle", angle, '%.3g°'), dataTipTextRow("Magnitude", vals(:, k), '%.3g dB')];
                set([pl(k), rl(k)], 'Color', colors(k, :)); pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            ticks = 0:30:330; if V.SignedPhi, ticks(ticks > 180) = ticks(ticks > 180) - 360; end
            set(pax, 'RLim', lim, 'RTick', lim(1):5:lim(2), 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', ticks));
            set(rax, 'YLim', lim, 'XLim', xlimits, 'XTick', xlimits(1):30:xlimits(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, cut.Type + " (degree)"); title(pax, cut.Title, 'Interpreter', 'none'); title(rax, cut.Title, 'Interpreter', 'none');
            % POB of the plotted cut (first trace)
            [pk, ip] = max(vals(:, 1), [], 'omitnan'); tipRows = [dataTipTextRow("Angle", angle(ip), '%.3g°'); dataTipTextRow("Magnitude", pk, '%.3g dB')];
            mk = [polarplot(pax, deg2rad(angle(ip)), pk, 'ko', 'MarkerFaceColor', 'k', 'HandleVisibility', 'off'), plot(rax, angle(ip), pk, 'ko', 'MarkerFaceColor', 'k', 'HandleVisibility', 'off')];
            for m = mk, m.DataTipTemplate.DataTipRows = tipRows; if V.POB, datatip(m, 'DataIndex', 1, 'FontSize', 9); end, end
            % HPBW
            app.Label_HPBW.Text = '';
            if V.HPBW
                [bw, lo, hi] = met_hpbw(angle, vals(:, 1));
                if isfinite(bw)
                    b = mod([lo hi] - xlimits(1), 360) + xlimits(1);
                    app.Label_HPBW.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                    if b(1) <= b(2), regions = b; else, regions = [xlimits(1), b(2); b(1), xlimits(2)]; end
                    thetaregion(pax, deg2rad(regions(:, 1)), deg2rad(regions(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    xregion(rax, regions(:, 1), regions(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    if V.HPBWTips
                        for k = 1:2
                            rows = [dataTipTextRow(util_pick(k == 1, "Lower HPBW", "Upper HPBW"), b(k), '%.2f°'); dataTipTextRow("Gain", pk - 3, '%.2f dB')];
                            h = [polarplot(pax, deg2rad(b(k)), pk - 3, 'o', 'Color', '#D95319', 'MarkerFaceColor', '#D95319', 'HandleVisibility', 'off'), plot(rax, b(k), pk - 3, 'o', 'Color', '#D95319', 'MarkerFaceColor', '#D95319', 'HandleVisibility', 'off')];
                            for m = h, m.DataTipTemplate.DataTipRows = rows; datatip(m, 'DataIndex', 1, 'FontSize', 9); end
                        end
                    end
                end
            end
            names = replace(cut.Names, "_", "\_");
            legend(pax, pl, names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rl, names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off');
            app.Single_CheckBox_HPBWBounds.Visible = V.HPBW;
            app.renderOverlay();
        end

        function applyAnnotations(app)
            % POB visibility toggle: retained markers/tips on the full views, cut redrawn (its marker is part of the cut).
            V = app.readConfig(); app.View = V;
            for key = app.FullTabs, g = app.Gfx.(key); set([g.pob, g.tip], 'Visible', V.POB); end
            app.renderCut();
        end
    end

    %% ------------------------------------------------------------------ coverage tab (tree = job registry; job = curve {T, cov})
    methods (Access = private)
        function c = readCoverageConfig(app)
            % The ONLY reader of Coverage-tab widget values (I11).
            c.Conical = app.Cov_ButtonGroup_Btn_Conical.Value; c.Orientation = app.Cov_DropDown_Orientation.Value;
            c.ConeTheta = app.Cov_Spinner_ConeTH.Value; c.ConePhi = mod(app.Cov_Spinner_ConePH.Value, 360); c.ConeAngle = app.Cov_Spinner_ConeAng.Value;
            c.Tmin = app.Cov_Spinner_ThreshMin.Value; c.Tmax = app.Cov_Spinner_ThreshMax.Value; c.Step = app.Cov_Spinner_Step.Value;
            c.Component = string(app.Cov_DropDown_Component.Value); c.Format = app.Cov_DropDown_TextFormat.Value;
            c.QueryCov = app.Cov_Spinner_queryCov.Value; c.QueryThr = app.Cov_Spinner_queryThresh.Value;
        end

        function onCoverage(app, scope, varargin)
            switch scope
                case "tocoverage"
                    app.TabGroup.SelectedTab = app.Tab2_Coverage; app.Cov_EditField_filePath.Value = app.Pats(app.Main).Path;
                    app.Cov_Tree.SelectedNodes = app.covAddPattern(app.Main); app.covSelect();
                case "covload",    app.covLoad();
                case "covformat"
                    node = app.covNode(); if isempty(node) || ~io_isGeneric(app.Pats(node.NodeData.k).Path), return; end
                    app.covLoad(app.Pats(node.NodeData.k).Path);
                case "covcompute", app.covCompute();
                case "covselect",  app.covSelect();
                case "covcheck",   app.covRefresh();
                case "covtype",    app.applyCoverageUI();
                case "covedit"
                    if app.Cov_Spinner_ThreshMax.Value <= app.Cov_Spinner_ThreshMin.Value, app.Cov_Spinner_ThreshMax.Value = app.Cov_Spinner_ThreshMin.Value + app.Cov_Spinner_Step.Value; end
                case "covreset"
                    for j = app.covJobs().', delete(j.NodeData.line); delete(j); end
                    app.covClear(); app.Cov_Tabel.Data = table(); app.CovRunID = 0; app.covRefresh();
                    app.setStatus(app.Cov_StatusBar, 'All coverage results cleared.', false);
                case "covclear",   app.covClear();
                case "covexport"
                    if isempty(app.Cov_Tabel.Data), return; end
                    [f, p] = uiputfile({'*.csv'; '*.txt'; '*.xlsx'}, 'Export Coverage Results', 'coverage_results.csv'); if isequal(f, 0), return; end
                    writetable(app.Cov_Tabel.Data, fullfile(p, f)); app.setStatus(app.Cov_StatusBar, ['Coverage results exported to <b>' fullfile(p, f) '</b>'], true);
                case "covquery",   app.covQuery(varargin{1});
            end
        end

        function node = covNode(app)
            % Pattern node owning the current selection (job → parent), or [] for results/root nodes.
            node = app.Cov_Tree.SelectedNodes;
            if isempty(node), return; end
            node = node(1); if node.NodeData.kind == "job", node = node.Parent; end
            if node.NodeData.kind ~= "pattern", node = []; end
        end

        function jobs = covJobs(app, root)
            % All job nodes (optionally below one node), ordered by id.
            if nargin < 2, root = app.Cov_Tree; end
            nodes = findobj(root, '-isa', 'matlab.ui.container.TreeNode'); jobs = gobjects(0, 1);
            for n = nodes(:).', if isstruct(n.NodeData) && n.NodeData.kind == "job", jobs(end + 1, 1) = n; end, end %#ok<AGROW>
            if numel(jobs) > 1, [~, order] = sort(arrayfun(@(n) n.NodeData.id, jobs)); jobs = jobs(order); end
        end

        function node = covAddPattern(app, k)
            % One tree node per registry entry; NodeData holds only the index (I14).
            for n = app.Cov_Tree.Children.', if n.NodeData.kind == "pattern" && n.NodeData.k == k, node = n; return; end, end
            node = uitreenode(app.Cov_Tree, 'Text', ['📡 ' app.Pats(k).Name], 'NodeData', struct('kind', "pattern", 'k', k));
            move(node, app.Cov_TreeNode_Results, 'before');
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node]; app.Cov_Panel_Results.Visible = 'on';
        end

        function job = covAddJob(app, parent, label, T, cov, component)
            app.CovRunID = app.CovRunID + 1; id = app.CovRunID;
            text = sprintf('R%d: %s | %s [%g:%g:%g dB]', id, label, component, T(1), util_gridStep(T), T(end));
            ln = plot(app.Cov_Axes, T, cov, 'LineWidth', 1.5, 'DisplayName', sprintf('R%d %s', id, label));
            ln.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", T, '%.2f dB'), dataTipTextRow("Coverage", cov, '%.2f%%')];
            job = uitreenode(parent, 'Text', text, 'NodeData', struct('kind', "job", 'id', id, 'label', string(label), 'T', T(:), 'cov', cov(:), 'comp', string(component), 'line', ln));
            expand(parent); app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; job];
        end

        function covLoad(app, fp)
            % Load a pattern (registered once, derived with the current Main parameters) or a results file into the tree.
            if nargin < 2
                fp = strtrim(app.Cov_EditField_filePath.Value);
                if ~isfile(fp) || any(strcmp({app.Pats.Path}, fp))
                    [f, p] = uigetfile({'*.uan;*.fz;*.out;*.ffd;*.ffe;*.ffs;*.cut;*.xlsx;*.csv;*.dat;*.txt', 'Pattern / coverage data'}, 'Select a pattern or coverage results file');
                    if isequal(f, 0), return; end
                    fp = fullfile(p, f);
                end
            end
            app.Cov_EditField_filePath.Value = fp;
            S = io_read(fp, app.Cov_DropDown_TextFormat.Value);
            set([app.Cov_TextFormatLabel, app.Cov_DropDown_TextFormat], 'Visible', S.Meta.IsGeneric && ~S.Meta.IsCoverage);
            if S.Meta.IsCoverage, app.covLoadResults(fp, S.Raw); return; end
            k = app.registerSource(fp, S);
            for n = app.Cov_Tree.Children.', if n.NodeData.kind == "pattern" && n.NodeData.k == k, for j = n.Children.', delete(j.NodeData.line); end, delete(n); end, end
            V = app.readConfig(); app.derive(k, 1, false, V.Params);
            if k == app.Main, app.update("pattern"); end
            app.Cov_Tree.SelectedNodes = app.covAddPattern(k); app.covSelect();
            app.setStatus(app.Cov_StatusBar, sprintf('Pattern <b>"%s"</b> added — ready to compute coverage.', app.Pats(k).Name), false);
        end

        function covLoadResults(app, fp, T)
            [~, name] = fileparts(fp);
            node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📄 ' name], 'NodeData', struct('kind', "results", 'name', string(name)));
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node];
            for c = 2:width(T), app.covAddJob(node, T.Properties.VariableNames{c}, T{:, 1}, T{:, c}, 'file'); end
            expand(app.Cov_TreeNode_Results); app.Cov_Panel_Results.Visible = 'on';
            app.covRefresh(); app.setStatus(app.Cov_StatusBar, sprintf('Coverage results file "%s" loaded (%d curves).', name, width(T) - 1), false);
        end

        function covSelect(app)
            % Selection changes items only (component list, cone centre); it never recomputes numerics (D37).
            node = app.covNode(); sel = app.Cov_Tree.SelectedNodes;
            if ~isempty(node)
                D = app.Pats(node.NodeData.k).Derived; dd = app.Cov_DropDown_Component; previous = dd.Value;
                dd.Items = cellstr(D.Names(D.Kind == "gain"));
                if any(strcmp(dd.Items, previous)), dd.Value = previous; else, dd.Value = char(D.Total); end
                app.Cov_EditField_filePath.Value = app.Pats(node.NodeData.k).Path;
            end
            app.applyCoverageUI();
            if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Ready.', false); return; end
            d = sel(1).NodeData;
            if d.kind == "job", app.setStatus(app.Cov_StatusBar, sprintf('%s | peak coverage %s%% at %s dB', sel(1).Text, util_fmtNumber(max(d.cov)), util_fmtNumber(d.T(find(d.cov == max(d.cov), 1)))), false);
            elseif d.kind ~= "root", app.setStatus(app.Cov_StatusBar, sprintf('<b>%s</b> — %d coverage job(s).', sel(1).Text, numel(sel(1).Children)), false); end
        end

        function applyCoverageUI(app)
            % Enable/visible states only; never triggers numerics (D53).
            c = app.readCoverageConfig(); node = app.covNode(); hasPattern = ~isempty(node); jobs = app.covJobs(); hasJobs = ~isempty(jobs);
            set([app.ConeSpinnerLabel, app.Cov_Spinner_ConeTH, app.ConeLabel, app.Cov_Spinner_ConePH, app.ConeAngleLabel, app.Cov_Spinner_ConeAng, app.Cov_DropDown_Orientation, app.Cov_DropDown_OrientationLabel], 'Enable', c.Conical);
            set([app.Cov_Button_computeCov, app.Cov_DropDown_Component, app.Cov_DropDown_ComponentLabel], 'Enable', hasPattern);
            set([app.Cov_Button_Reset, app.Cov_Button_Export, app.Cov_Button_Clear], 'Enable', hasJobs);
            set([app.Cov_QueryCoverageLabel, app.Cov_Spinner_queryCov, app.Cov_Button_queryCov, app.Cov_QueryThresholdLabel, app.Cov_Spinner_queryThresh, app.Cov_Button_queryThresh], 'Visible', hasJobs);
            if c.Conical && hasPattern
                axisIndex = c.Orientation; if axisIndex == 0, axisIndex = app.Pats(node.NodeData.k).Derived.Boresight; end
                app.Cov_Spinner_ConeTH.Value = app.Axes6.theta(axisIndex); app.Cov_Spinner_ConePH.Value = app.Axes6.phi(axisIndex);
            end
        end

        function covCompute(app)
            % Coverage(T) = 100·Ω_R(C > T)/Ω_R on the canonical grid — one kernel, result stored as a curve (I7).
            node = app.covNode(); if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            c = app.readCoverageConfig(); E = app.Pats(node.NodeData.k); C = E.Derived.Cols.(c.Component);
            T = cov_thresholds(c.Tmin, c.Tmax, c.Step);
            if c.Conical
                mask = cov_coneMask(E.Pattern, c.ConeTheta, c.ConePhi, c.ConeAngle);
                label = sprintf('Conical (θ₀=%s°, φ₀=%s°) α=%s°', util_fmtNumber(c.ConeTheta), util_fmtNumber(c.ConePhi), util_fmtNumber(c.ConeAngle));
            else
                mask = true(size(C)); label = 'Spherical';
            end
            cov = cov_curve(C, mask, E.Geometry.dOmega, T); app.perf("coverage", "kernel");
            app.covAddJob(node, label, T, cov, c.Component);
            if app.Range.AutoCov, app.applyRange("cov", [min(app.Range.cov(1), T(1)), max(app.Range.cov(2), T(end))], false); end
            app.covRefresh();
            app.setStatus(app.Cov_StatusBar, sprintf('Run-<b>%d</b> computed: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds, Loss %s dB).', app.CovRunID, label, E.Name, c.Component, numel(T), util_fmtNumber(E.Params.Loss_dB)), false);
        end

        function covRefresh(app)
            % Visibility follows the checkboxes; the table is the union of checked curves read through interp1 (§6.9).
            jobs = app.covJobs(); checked = app.Cov_Tree.CheckedNodes; shown = gobjects(0, 1); Tall = [];
            for j = jobs.'
                on = ismember(j, checked); d = j.NodeData; d.line.Visible = on;
                set(findobj(app.Cov_Axes, 'Tag', sprintf('CovQ%d', d.id)), 'Visible', on); set(findobj(d.line, 'Type', 'datatip'), 'Visible', on);
                if on, shown(end + 1, 1) = j; Tall = union(Tall, d.T); end %#ok<AGROW>
            end
            if isempty(shown), app.Cov_Tabel.Data = table(); legend(app.Cov_Axes, 'off');
            else
                data = Tall(:); names = {'Threshold_dB'};
                for j = shown.', d = j.NodeData; data(:, end + 1) = cov_at(d, Tall); names{end + 1} = sprintf('R%d_%s', d.id, matlab.lang.makeValidName(char(d.label))); end %#ok<AGROW>
                app.Cov_Tabel.Data = array2table(round(data, 2), 'VariableNames', names);
                lines = arrayfun(@(j) j.NodeData.line, shown, 'UniformOutput', false); legend(app.Cov_Axes, [lines{:}], 'Location', 'southwest');
            end
            app.applyCoverageUI();
        end

        function covQuery(app, mode)
            % One datatip per checked job under the selection, at the interpolated (T, cov) point (D74).
            c = app.readCoverageConfig(); sel = app.Cov_Tree.SelectedNodes;
            if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to query.', true); return; end
            jobs = app.covJobs(sel(1)); jobs = jobs(ismember(jobs, app.Cov_Tree.CheckedNodes)); hit = false;
            for j = jobs.'
                d = j.NodeData; tag = sprintf('CovQ%d', d.id);
                if mode == "cov", x = c.QueryCov; y = cov_at(d, x); else, y = c.QueryThr; x = thr_at(d, y); end
                if ~isfinite(x) || ~isfinite(y), continue; end
                line(app.Cov_Axes, [x x], [0 y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(app.Cov_Axes, [app.Cov_Axes.XLim(1) x], [y y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'FontSize', 9); hit = true;
            end
            if hit, app.setStatus(app.Cov_StatusBar, sprintf('Queried %s.', util_pick(mode == "cov", sprintf('coverage at %s dB', util_fmtNumber(c.QueryCov)), sprintf('threshold at %s%% coverage', util_fmtNumber(c.QueryThr)))), false);
            else, app.setStatus(app.Cov_StatusBar, 'Query value is outside the checked curves.', true); end
        end

        function covClear(app)
            delete(findobj(app.Cov_Axes, 'Type', 'datatip')); delete(findobj(app.Cov_Axes, '-regexp', 'Tag', '^CovQ'));
        end
    end
end % classdef

%% ======================================================================= numerical core (app-free, widget-free, alert-free)

function P = pat_build(S, block)
%PAT_BUILD Long source table → grid-native canonical pattern: θ ascending in [0,180], φ ascending in [0,360), uniform steps (I1).
% Angles are snapped to 5 decimals; field values are never rounded (D03). Regularity and uniformity are asserted once here (D18).
T = S.Blocks{min(block, numel(S.Blocks))}; notes = S.Meta.Notes;
theta = double(T.Theta); phi = double(T.Phi); vals = T{:, 3:end}; names = string(matlab.lang.makeValidName(T.Properties.VariableNames(3:end)));
if any(theta < 0)
    if min(theta) >= -90 && max(theta) <= 90, theta = 90 - theta; notes(end + 1) = "θ given as elevation (−90..90°): converted to polar θ = 90° − el.";
    else, neg = theta < 0; theta(neg) = -theta(neg); phi(neg) = phi(neg) + 180; notes(end + 1) = "Negative θ folded onto φ + 180°."; end
end
theta = mod(theta, 360); over = theta > 180; theta(over) = 360 - theta(over); phi(over) = phi(over) + 180;
theta = round(theta, 5); phi = round(mod(phi, 360), 5); phi(phi >= 360) = 0;
[~, keep] = unique([theta phi], 'rows', 'first');                    % φ = 360 duplicates of φ = 0 and repeated rows: first wins
theta = theta(keep); phi = phi(keep); vals = vals(keep, :);
thetaAxis = unique(theta); phiAxis = unique(phi).'; n = [numel(thetaAxis), numel(phiAxis)];
assert(prod(n) == numel(theta), 'APAT:IrregularGrid', 'The pattern is not a complete θ×φ grid: %d samples for %d θ × %d φ values.', numel(theta), n(1), n(2));
P = struct('Theta', thetaAxis(:), 'Phi', phiAxis, 'dTheta', util_assertUniform(thetaAxis, 'θ'), 'dPhi', util_assertUniform(phiAxis, 'φ'), ...
    'IsGainOnly', S.Meta.IsGainOnly, 'Names', names, 'Meta', S.Meta, 'Block', block, 'OneDegree', false, 'Revision', 1);
if isnan(P.dTheta), P.dTheta = 180; end, if isnan(P.dPhi), P.dPhi = 360; end
P.NativeStep = [P.dTheta, P.dPhi]; P.Meta.Notes = notes;
[~, it] = ismember(theta, thetaAxis); [~, ip] = ismember(phi, phiAxis); lin = sub2ind(n, it, ip);
if P.IsGainOnly
    for c = 1:numel(names), P.G.(names(c)) = util_grid(n, lin, vals(:, c)); end
else
    grid = @(nm) util_grid(n, lin, vals(:, names == nm));
    P.Eth = complex(grid("Re_Eth"), grid("Im_Eth")); P.Eph = complex(grid("Re_Eph"), grid("Im_Eph"));
end
end

function P = pat_resample(P, step)
%PAT_RESAMPLE Uniform grid → uniform grid at STEP degrees. Exact decimation when the ratio is integer; otherwise bilinear on the
% φ-closed grid: E-fields as linear power + unit phasor, gain-kind columns as linear power, everything else linear (I6, D04/D16).
% Target axes never leave the source domain (D05).
nP = numel(P.Phi); periodic = abs(nP*P.dPhi - 360) < 1e-6; ratio = step ./ [P.dTheta, P.dPhi]; decimate = all(abs(ratio - round(ratio)) < 1e-9);
if decimate
    it = 1:round(ratio(1)):numel(P.Theta); ip = 1:round(ratio(2)):nP; thetaQ = P.Theta(it); phiQ = P.Phi(ip);
else
    thetaQ = (P.Theta(1):step:P.Theta(end)).';
    if periodic, phiQ = P.Phi(1):step:P.Phi(1) + 360 - step/2; phiS = [P.Phi, P.Phi(1) + 360]; cols = [1:nP, 1];
    else, phiQ = P.Phi(1):step:P.Phi(end); phiS = P.Phi; cols = 1:nP; end
    lin = @(X) interp2(phiS, P.Theta, X(:, cols), phiQ, thetaQ, 'linear');
end
if P.IsGainOnly
    for nm = P.Names
        X = P.G.(nm);
        if decimate, X = X(it, ip); elseif util_colKind(nm) == "gain", X = 10*log10(max(lin(10.^(X/10)), realmin)); else, X = lin(X); end
        P.G.(nm) = X;
    end
else
    for f = ["Eth", "Eph"]
        E = P.(f);
        if decimate, P.(f) = E(it, ip); continue; end
        u = E ./ max(abs(E), realmin); power = max(lin(abs(E).^2), 0); phasor = complex(lin(real(u)), lin(imag(u)));
        P.(f) = sqrt(power) .* phasor ./ max(abs(phasor), realmin);
    end
end
P.Theta = thetaQ(:); P.Phi = phiQ(:).'; P.dTheta = step; P.dPhi = step; P.Revision = P.Revision + 1;
end

function G = geo_build(P)
%GEO_BUILD Separable solid-angle geometry: ΔΩ(i,j) = wθ(i)·Δφ with wθ = cos(θ−Δθ/2) − cos(θ+Δθ/2) clipped to [0,180].
% Adjacent cells share boundaries, so ΣΔΩ telescopes to exactly 4π on a full sphere for any step (I2, B.1).
lo = max(P.Theta - P.dTheta/2, 0); hi = min(P.Theta + P.dTheta/2, 180);
G.wTheta = cosd(lo) - cosd(hi); G.dPhi = deg2rad(P.dPhi);
G.PhiPeriodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
G.dOmega = G.wTheta * ones(1, numel(P.Phi)) * G.dPhi; G.Omega = sum(G.dOmega, 'all');
G.IsFullSphere = G.PhiPeriodic && P.Theta(1) <= P.dTheta/2 + 1e-9 && P.Theta(end) >= 180 - P.dTheta/2 - 1e-9;
end

function D = pat_derive(P, G, prm, axes6, excessDB, coneDeg, tiltDeg, arFloorDB)
%PAT_DERIVE Pattern + parameters → every column and every base fact, once (I3). Loss scales fields by 10^(L/20) here and nowhere else.
% Physical facts (peak, boresight, planes, metrics) are defined on total gain (I4). Partial-sphere / unit honesty per I9.
dBi = P.Meta.Unit == "dBi"; unitLabel = P.Meta.UnitLabel;
if P.IsGainOnly
    D.Names = P.Names; D.Labels = P.Names; D.Kind = arrayfun(@util_colKind, P.Names); D.Menu = true(size(P.Names));
    for c = 1:numel(P.Names), X = P.G.(P.Names(c)); if D.Kind(c) == "gain", X = X + prm.Loss_dB; end, D.Cols.(P.Names(c)) = X; end
    D.Total = P.Names(find(D.Kind == "gain", 1)); if isempty(D.Total), D.Total = P.Names(1); end
    D.Pol = struct('Label', "n/a", 'Basis', "Circular", 'Pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]));
else
    s = 10^(prm.Loss_dB/20); Eth = P.Eth*s; Eph = P.Eph*s; Er = pol_circular(Eth, Eph, 1); El = pol_circular(Eth, Eph, 2);
    dB = @(E) 20*log10(max(abs(E), realmin)); ph = @(E) rad2deg(angle(E));
    total = 10*log10(max(abs(Eth).^2 + abs(Eph).^2, realmin));
    [AR, isLinear] = pol_signedAR(Er, El, arFloorDB);
    % Polarisation classification from Ω-weighted power inside the −3 dB main beam (D13); same pairs drive cuts and Auto-Rx.
    pk0 = met_peak(total, G.PhiPeriodic, excessDB); beam = isfinite(total) & total >= pk0.value - 3;
    pw = @(E) sum(abs(E(beam)).^2 .* G.dOmega(beam)); p = [pw(Eth), pw(Eph), pw(Er), pw(El)];
    pairs = struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]);
    if p(2) > p(1), pairs.Linear = flip(pairs.Linear); end, if p(4) > p(3), pairs.Circular = flip(pairs.Circular); end
    if max(p(3:4)) > max(p(1:2)), label = "Circular (" + util_pick(pairs.Circular(1) == "E_RCP", "RHCP", "LHCP") + ")"; basis = "Circular";
    else, label = "Linear (" + util_pick(p(1) >= p(2), "Vertical", "Horizontal") + ")"; basis = "Linear"; end
    D.Pol = struct('Label', label, 'Basis', basis, 'Pairs', pairs);
    % Polarisation loss factor between antenna ellipse (ra, signed) and incident wave ellipse (rw, signed), relative tilt = tiltDeg:
    %   PLF = 1/2 + [4·ra·rw + (ra²−1)(rw²−1)·cos(2Δτ)] / [2(ra²+1)(rw²+1)]    (NaN fields stay NaN, D08)
    switch prm.RxMode, case "Auto", sense = 2*(pairs.Circular(1) == "E_RCP") - 1; case "RHCP", sense = 1; otherwise, sense = -1; end
    d = abs(Er) - abs(El); ra = sign(d) .* (abs(Er) + abs(El)) ./ max(abs(d), realmin); ra(isLinear) = 1e12; rw = sense * 10^(prm.RxAR_dB/20);
    plf = 0.5 + (4*ra*rw + (ra.^2 - 1)*(rw^2 - 1)*cosd(2*tiltDeg)) ./ (2*(ra.^2 + 1)*(rw^2 + 1));
    plf = 10*log10(min(max(plf, eps), 1));
    D.Cols = struct('E_Total_dB', total, 'E_TH_dB', dB(Eth), 'E_PH_dB', dB(Eph), 'E_RCP_dB', dB(Er), 'E_LCP_dB', dB(El), 'AR_dB', AR, ...
        'Gain_PolCorrected_dB', total + plf, 'PLF_dB', plf, 'E_TH_Phase', ph(Eth), 'E_PH_Phase', ph(Eph), 'E_RCP_Phase', ph(Er), 'E_LCP_Phase', ph(El));
    D.Names = ["E_Total_dB", "E_TH_dB", "E_PH_dB", "E_RCP_dB", "E_LCP_dB", "AR_dB", "Gain_PolCorrected_dB", "PLF_dB", "E_TH_Phase", "E_PH_Phase", "E_RCP_Phase", "E_LCP_Phase"];
    D.Labels = ["Total Gain", "Etheta Gain", "Ephi Gain", "RHCP Gain", "LHCP Gain", "Axial Ratio", "Polarized Gain", "PLF", "Etheta Phase", "Ephi Phase", "RHCP Phase", "LHCP Phase"];
    if dBi   % EIRP / PFD / field strength are meaningful only for absolute gain in dBi (I9)
        eirp = prm.Pt_dBW + total; D.Cols.EIRP_dBW = eirp; D.Cols.PFD_Wm2 = 10.^(eirp/10) / (4*pi*prm.R_m^2); D.Cols.E_RMS_Vm = sqrt(30*10.^(eirp/10)) / prm.R_m;
        D.Names(end + (1:3)) = ["EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"]; D.Labels(end + (1:3)) = ["EIRP", "Power Flux Density", "E-field RMS"];
    end
    D.Kind = arrayfun(@util_colKind, D.Names); D.Menu = ismember(D.Names, D.Names(1:7)); D.Total = "E_Total_dB";
end
% ---- facts on total gain
C = D.Cols.(D.Total); D.Peak = met_peak(C, G.PhiPeriodic, excessDB); D.Peak.theta = P.Theta(D.Peak.row); D.Peak.phi = P.Phi(D.Peak.col);
w = 10.^(C/10) .* G.dOmega; w(D.Peak.spike | ~isfinite(w)) = 0;
cosGamma = @(t, f) cosd(P.Theta) .* cosd(t) + sind(P.Theta) .* sind(t) .* cosd(P.Phi - f);   % spherical law of cosines, nθ×nφ
energy = arrayfun(@(a) sum(w(cosGamma(axes6.theta(a), axes6.phi(a)) >= cosd(coneDeg))), 1:numel(axes6.theta));
[~, D.Boresight] = max(energy); aT = axes6.theta(D.Boresight); aP = axes6.phi(D.Boresight);
D.Planes.E = struct('Type', "Theta", 'Value', aP);
if aT == 90, D.Planes.H = struct('Type', "Phi", 'Value', 90); else, D.Planes.H = struct('Type', "Theta", 'Value', mod(aP + 90, 360)); end
integral = sum(w, 'all');
m.Directivity_dB = 10*log10(max(4*pi*10^(D.Peak.value/10) / max(integral, realmin), realmin));
m.Efficiency_pct = NaN; m.FrontBack_dB = NaN; m.AR_at_peak_dB = NaN;
if G.IsFullSphere && dBi, m.Efficiency_pct = 100*integral/(4*pi); if m.Efficiency_pct > 100.5, m.Efficiency_pct = NaN; end, end
if G.IsFullSphere, [~, back] = min(cosGamma(D.Peak.theta, D.Peak.phi), [], 'all', 'linear'); m.FrontBack_dB = D.Peak.value - C(back); end
if isfield(D.Cols, 'AR_dB'), m.AR_at_peak_dB = D.Cols.AR_dB(D.Peak.row, D.Peak.col); end
cutE = geo_cut(P, D.Cols, D.Total, D.Planes.E.Type, D.Planes.E.Value); m.HPBW_E = met_hpbw(cutE.Angle, cutE.Values);
cutH = geo_cut(P, D.Cols, D.Total, D.Planes.H.Type, D.Planes.H.Value); m.HPBW_H = met_hpbw(cutH.Angle, cutH.Values);
D.Metrics = m; D.UnitLabel = unitLabel;
end

function E = pol_circular(Eth, Eph, which)
%POL_CIRCULAR RHCP (which = 1) / LHCP (which = 2) component of E = Eθ θ̂ + Eφ φ̂ under e^{+jωt}, (θ̂, φ̂, r̂) right-handed (I10, B.4):
%   ê_R = (θ̂ − jφ̂)/√2  ⇒  E_R = E·ê_R* = (Eθ + jEφ)/√2,  E_L = (Eθ − jEφ)/√2.   Check: E = ê_R ⇒ E_R = 1, E_L = 0.
if which == 1, E = (Eth + 1i*Eph) / sqrt(2); else, E = (Eth - 1i*Eph) / sqrt(2); end
end

function [Eth, Eph] = pol_fromCircular(Er, El)
%POL_FROMCIRCULAR Inverse of pol_circular (GRASP .out, .cut ICOMP = 2, Excel format 2, generic RCP/LCP text).
Eth = (Er + El) / sqrt(2); Eph = (Er - El) / (1i*sqrt(2));
end

function [AR, isLinear] = pol_signedAR(Er, El, floorDB)
%POL_SIGNEDAR Signed axial ratio in dB: +RHCP sense, −LHCP sense; numerically equal components are linear → floorDB (§15-2).
r = abs(Er); l = abs(El); d = r - l;
isLinear = isfinite(d) & abs(d) <= eps(max(r + l, 1));
AR = min(20*log10((r + l) ./ max(abs(d), realmin)), 250) .* sign(d); AR(isLinear) = floorDB;
end

function K = met_peak(C, periodic, excessDB)
%MET_PEAK Effective peak by spatial isolation (I5): a sample is a spike iff it exceeds all 4 grid neighbours by more than excessDB
% (φ wraps when periodic; pole rows see the adjacent ring). Effective peak = highest non-spike sample. Raw peak reported too.
[n, m] = size(C); nb = -inf(n, m);
if n > 1, nb(2:n, :) = max(nb(2:n, :), C(1:n-1, :)); nb(1:n-1, :) = max(nb(1:n-1, :), C(2:n, :)); end
if periodic, L = circshift(C, 1, 2); R = circshift(C, -1, 2); else, L = [-inf(n, 1), C(:, 1:m-1)]; R = [C(:, 2:m), -inf(n, 1)]; end
nb = max(nb, max(L, R));
K.spike = isfinite(C) & (C - nb > excessDB);
[K.rawValue, K.rawIndex] = max(C(:), [], 'omitnan');
cand = C; cand(K.spike) = -Inf; [K.value, K.index] = max(cand(:), [], 'omitnan');
[K.row, K.col] = ind2sub([n m], K.index); K.wasAdjusted = K.spike(K.rawIndex); K.spikeCount = nnz(K.spike);
end

function [bw, lo, hi] = met_hpbw(angleDeg, gainDB)
%MET_HPBW Half-power beamwidth of one closed cut: first −3 dB crossings on either side of the cut peak, linearly interpolated.
[bw, lo, hi] = deal(NaN); ok = isfinite(angleDeg(:)) & isfinite(gainDB(:)); a = angleDeg(ok); g = gainDB(ok);
if numel(g) < 3, return; end
[peak, ip] = max(g); half = peak - 3;
[rel, order] = sort(mod(a - a(ip) + 180, 360) - 180); g = g(order);
left = find(rel < 0 & g <= half, 1, 'last'); right = find(rel > 0 & g <= half, 1, 'first');
if isempty(left) || isempty(right) || right == 1 || left == numel(g), return; end
cross = @(i, j) rel(i) + (rel(j) - rel(i)) * (half - g(i)) / (g(j) - g(i));
lo = a(ip) + cross(left, left + 1); hi = a(ip) + cross(right, right - 1); bw = hi - lo;
end

function cut = geo_cut(P, Cols, names, cutType, value)
%GEO_CUT One closed great-circle cut as row/column slices of the grid (no table scan, D61). Angle runs 0..360° in physical degrees.
%   "Phi"  : fixed θ (nearest row),  sweep φ; closed at φ₀ + 360 when periodic.
%   "Theta": fixed φ (nearest column) sweep θ 0..180, then back along φ + 180 with angle 360 − θ (poles counted once).
names = string(names); k = numel(names);
if cutType == "Phi"
    [dist, i] = min(abs(P.Theta - value)); fixed = P.Theta(i); periodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
    angle = P.Phi(:); vals = zeros(numel(angle), k); for c = 1:k, vals(:, c) = Cols.(names(c))(i, :).'; end
    theta = fixed + zeros(size(angle)); phi = angle;
    if periodic, angle(end + 1) = P.Phi(1) + 360; vals(end + 1, :) = vals(1, :); theta(end + 1) = fixed; phi(end + 1) = P.Phi(1); end
else
    wrap = @(a, b) abs(mod(a - b + 180, 360) - 180);
    [dist, j] = min(wrap(P.Phi, value)); fixed = P.Phi(j); [dOpp, j2] = min(wrap(P.Phi, fixed + 180)); hasOpp = dOpp <= P.dPhi/2 + 1e-9;
    inner = P.Theta > 1e-9 & P.Theta < 180 - 1e-9;
    angle = P.Theta(:); theta = P.Theta(:); phi = fixed + zeros(size(angle)); vals = zeros(numel(angle), k);
    for c = 1:k, vals(:, c) = Cols.(names(c))(:, j); end
    if hasOpp
        angle = [angle; 360 - flip(P.Theta(inner))]; theta = [theta; flip(P.Theta(inner))]; phi = [phi; P.Phi(j2) + zeros(nnz(inner), 1)];
        opp = zeros(nnz(inner), k); for c = 1:k, opp(:, c) = flipud(Cols.(names(c))(inner, j2)); end, vals = [vals; opp];
        if P.Theta(1) <= 1e-9, angle(end + 1) = 360; theta(end + 1) = 0; phi(end + 1) = fixed; vals(end + 1, :) = vals(1, :); end
    end
end
cut = struct('Angle', angle, 'Values', vals, 'Theta', theta, 'Phi', mod(phi, 360), 'Fixed', fixed, 'Snapped', dist > 1e-9);
end

function M = geo_displayMap(P, G, V)
%GEO_DISPLAYMAP Display convention = column permutation + axis labels; Pattern/Geometry/Derived are untouched (I8).
n = numel(P.Phi); perm = 1:n; j0 = find(P.Phi >= 180, 1);
if V.SignedPhi && ~isempty(j0), perm = [j0:n, 1:j0-1]; end
M.ColIdx = perm; M.PhiAxis = P.Phi(perm);
if V.SignedPhi, M.PhiAxis(M.PhiAxis >= 180) = M.PhiAxis(M.PhiAxis >= 180) - 360; end
if G.PhiPeriodic, M.ColIdx(end + 1) = perm(1); M.PhiAxis(end + 1) = M.PhiAxis(1) + 360; end      % closing column for display only
if V.Elevation, M.ThetaAxis = 90 - P.Theta; M.ThetaDir = 'normal'; M.ThetaLabel = "Elevation"; M.ThetaLim = [-90 90];
else, M.ThetaAxis = P.Theta; M.ThetaDir = 'reverse'; M.ThetaLabel = "Theta"; M.ThetaLim = [0 180]; end
M.PhiLim = util_pick(V.SignedPhi, [-180 180], [0 360]);
end

function cov = cov_curve(C, mask, dOmega, T)
%COV_CURVE Coverage(T) = 100 · Ω_R(C > T) / Ω_R,  Ω_R(C > T) = Σ_{(i,j)∈R, C(i,j) > T} ΔΩ(i,j)   (strict ">", I7, A.1)
v = mask & isfinite(C); g = C(v); w = dOmega(v); Omega = sum(w);
cov = zeros(size(T)); if Omega <= 0, return; end
cov = 100 * arrayfun(@(t) sum(w(g > t)), T) / Omega;          % the definition, one threshold at a time (O(N) memory, D10)
end

function m = cov_coneMask(P, thetaC, phiC, alphaDeg)
%COV_CONEMASK (i,j) ∈ cone ⇔ cos γ ≥ cos α with cos γ = cos θᵢ cos θc + sin θᵢ sin θc cos(φⱼ − φc)  (spherical law of cosines)
m = cosd(P.Theta) .* cosd(thetaC) + sind(P.Theta) .* sind(thetaC) .* cosd(P.Phi - phiC) >= cosd(alphaDeg) - 1e-12;
end

function T = cov_thresholds(tMin, tMax, step)
%COV_THRESHOLDS Counting, not accumulation: tMin + k·step for k = 0..round((tMax−tMin)/step).
T = tMin + (0:round((tMax - tMin)/step)).' * step; if T(end) > tMax + 1e-9, T(end) = []; end
end

function c = cov_at(job, t)
%COV_AT Coverage at threshold t read from the sampled curve (linear between samples, NaN outside).
c = interp1(job.T, job.cov, t);
end

function t = thr_at(job, c)
%THR_AT Threshold at coverage c: the curve is non-increasing, so keep the highest T per coverage level (plateau upper end) and invert.
[cu, iu] = unique(job.cov, 'last'); t = NaN; if numel(cu) >= 2, t = interp1(cu, job.T(iu), c); end
end

%% ======================================================================= I/O (file → Source; one field builder for every six-column layout)

function S = io_read(fp, fmt)
%IO_READ File → Source{Raw (Input tab), Blocks{f} (long tables), Freqs, Meta}. Meta.Unit is a static property of the format (I9);
% every reader decision that changes the data is disclosed in Meta.Notes and shown in the Metadata tab.
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
S = struct('Raw', table(), 'Blocks', {{}}, 'Freqs', NaN, 'Meta', struct('Format', ext, 'Unit', "dB", 'UnitLabel', "dB", ...
    'IsGainOnly', false, 'IsCoverage', false, 'IsGeneric', io_isGeneric(fp), 'Notes', strings(0, 1)));
switch ext
    case {'XLSX', 'XLS'},                          S = io_excel(fp, S);
    case {'CSV', 'TXT', 'DAT'},                    S = io_text(fp, string(fmt), S);
    case 'CUT',                                    S = io_cut(fp, S);
    case {'UAN', 'FZ', 'OUT', 'FFS', 'FFE', 'FFD'}, S = io_farfield(fp, ext, S);
    otherwise, error('APAT:Unsupported', 'Unsupported format: %s', ext);
end
if ~S.Meta.IsCoverage, S.Freqs(end + 1:numel(S.Blocks)) = NaN; S.Freqs = S.Freqs(1:numel(S.Blocks)); end
end

function tf = io_isGeneric(fp)
[~, ~, ext] = fileparts(fp); tf = any(strcmpi(ext, {'.csv', '.txt', '.dat'}));
end

function B = io_fields(M, order, form, basis)
%IO_FIELDS Six numeric columns → canonical field block. order: "tp"|"pt" (θ,φ or φ,θ first); form: "reim" | "dbdeg" (m m p p) |
% "dbdeg_i" (m p m p); basis: "lin" (θ/φ), "rl" (RHCP,LHCP), "lr" (LHCP,RHCP).
M = M(~any(isnan(M(:, 1:6)), 2), 1:6);
if order == "pt", M(:, [1 2]) = M(:, [2 1]); end
switch form
    case "dbdeg",   c1 = 10.^(M(:, 3)/20) .* exp(1i*deg2rad(M(:, 5))); c2 = 10.^(M(:, 4)/20) .* exp(1i*deg2rad(M(:, 6)));
    case "dbdeg_i", c1 = 10.^(M(:, 3)/20) .* exp(1i*deg2rad(M(:, 4))); c2 = 10.^(M(:, 5)/20) .* exp(1i*deg2rad(M(:, 6)));
    otherwise,      c1 = complex(M(:, 3), M(:, 4)); c2 = complex(M(:, 5), M(:, 6));
end
switch basis, case "rl", [Eth, Eph] = pol_fromCircular(c1, c2); case "lr", [Eth, Eph] = pol_fromCircular(c2, c1); otherwise, Eth = c1; Eph = c2; end
B = table(M(:, 1), M(:, 2), real(Eth), imag(Eth), real(Eph), imag(Eph), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function S = io_farfield(fp, ext, S)
%IO_FARFIELD XGTD UAN/FZ, GRASP OUT, CST FFS, FEKO FFE (multi-frequency), HFSS FFD (multi-frequency).
[nHdr, ffd] = io_header(fp);
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = readmatrix(fp, setvartype(opts, 'double')); M = M(~all(isnan(M), 2), :);
switch ext
    case {'UAN', 'FZ'}
        S.Meta.Format = ['XGTD ' ext]; S.Meta.Unit = "dBi"; S.Meta.UnitLabel = "dBi";
        S.Raw = array2table(M(:, 1:6), 'VariableNames', {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}); S.Blocks = {io_fields(M, "tp", "dbdeg", "lin")};
    case 'OUT'
        S.Meta.Format = 'TICRA/GRASP OUT'; S.Meta.Notes(end + 1) = "GRASP .out POL-1/POL-2 read as RHCP/LHCP field amplitudes; levels are relative dB, not dBi.";
        S.Raw = array2table(M(:, 1:6), 'VariableNames', {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}); S.Blocks = {io_fields(M, "tp", "reim", "rl")};
    case 'FFS'
        S.Meta.Format = 'CST FFS'; S.Meta.Notes(end + 1) = "CST .ffs complex E-fields; levels are 20·log10|E| in dB relative to 1 V/m, not dBi.";
        S.Raw = array2table(M(:, 1:6), 'VariableNames', {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}); S.Blocks = {io_fields(M, "pt", "reim", "lin")};
    case 'FFE'
        S.Meta.Format = 'FEKO FFE'; S.Meta.Notes(end + 1) = "FEKO .ffe complex E-fields (first six columns); levels are dB relative to 1 V/m, not dBi.";
        S.Raw = array2table(M(:, 1:6), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
        f = regexp(fileread(fp), '#Frequency:\s*([\d.eE+-]+)', 'tokens'); S.Freqs = cellfun(@(t) str2double(t{1}), f);
        S.Blocks = io_blocks(io_fields(M, "tp", "reim", "lin"), []);
    case 'FFD'
        S.Meta.Format = 'HFSS FFD'; S.Meta.Notes(end + 1) = "HFSS .ffd complex E-fields; levels are dB relative to 1 V/m, not dBi.";
        assert(ffd.isFFD, 'APAT:FFDHeader', 'FFD header (theta/phi ranges) not found.');
        sep = isnan(M(:, 1)); S.Freqs = [ffd.freq(:); M(sep & isfinite(M(:, 2)), 2)].'; F = M(~sep, 1:4);
        thetaAxis = linspace(ffd.theta(1), ffd.theta(2), ffd.theta(3)).'; phiAxis = linspace(ffd.phi(1), ffd.phi(2), ffd.phi(3)).';
        pts = numel(thetaAxis)*numel(phiAxis); assert(mod(size(F, 1), pts) == 0, 'APAT:FFDRows', 'FFD row count does not match the header θ/φ grid.');
        B = table(repmat(repelem(thetaAxis, numel(phiAxis)), size(F, 1)/pts, 1), repmat(phiAxis, size(F, 1)/numel(phiAxis), 1), F(:, 1), F(:, 2), F(:, 3), F(:, 4), ...
            'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
        S.Blocks = io_blocks(B, pts); S.Raw = S.Blocks{1};
end
end

function blocks = io_blocks(B, pointsPerBlock)
%IO_BLOCKS Split a long table into equal frequency blocks (FFE/FFD). Block size defaults to the number of distinct (θ, φ) directions.
if isempty(pointsPerBlock), pointsPerBlock = size(unique([B.Theta, B.Phi], 'rows'), 1); end
n = max(1, floor(height(B)/pointsPerBlock)); B = B(1:n*pointsPerBlock, :);
blocks = mat2cell(B, repmat(pointsPerBlock, n, 1), width(B));
end

function [nHdr, ffd] = io_header(fp)
%IO_HEADER Count leading non-data lines; parse the HFSS FFD header (two numeric triples + optional "Frequencies" line) when present.
lines = readlines(fp); lines = lines(1:min(end, 200)); ffd = struct('isFFD', false, 'theta', [], 'phi', [], 'freq', []);
count = @(k) numel(sscanf(lines(k), '%f')); nonEmpty = find(strlength(strtrim(lines)) > 0);
if numel(nonEmpty) >= 2 && count(nonEmpty(1)) == 3 && count(nonEmpty(2)) == 3
    ffd.theta = sscanf(lines(nonEmpty(1)), '%f').'; ffd.phi = sscanf(lines(nonEmpty(2)), '%f').'; ffd.theta(3) = round(ffd.theta(3)); ffd.phi(3) = round(ffd.phi(3));
    ffd.isFFD = all(isfinite([ffd.theta ffd.phi])) && ffd.theta(3) >= 1 && ffd.phi(3) >= 1; nHdr = nonEmpty(2);
    if numel(nonEmpty) >= 3
        tok = regexp(strtrim(lines(nonEmpty(3))), '^frequencies?\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok), nHdr = nonEmpty(3); f = sscanf(tok{1}, '%f'); if ~isscalar(f), ffd.freq = f(:); end, end
    end
    return
end
nHdr = 0;
for k = 1:numel(lines), if count(k) >= 4, nHdr = k - 1; return; end, end
end

function S = io_cut(fp, S)
%IO_CUT TICRA/GRASP .cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks. ICOMP 1 = θ/φ, 2 = RHCP/LHCP (else error, D19).
S.Meta.Format = 'TICRA/GRASP CUT'; S.Meta.Notes(end + 1) = "GRASP .cut field amplitudes are relative dB, not dBi.";
lines = readlines(fp); lines(strlength(strtrim(lines)) == 0) = []; k = 1; rows = {};
while k < numel(lines)
    h = sscanf(lines(k + 1), '%f'); assert(numel(h) >= 7, 'APAT:CutHeader', 'Could not parse a .cut parameter line.');
    n = h(3); data = reshape(sscanf(strjoin(lines(k + 2:k + 1 + n), ' '), '%f'), 2*h(7), []).';
    sweep = h(1) + (0:n - 1).' * h(2); fixed = repmat(h(4), n, 1);
    if h(6) == 2, rows{end + 1} = [fixed, sweep, data(:, 1:4)]; else, rows{end + 1} = [sweep, fixed, data(:, 1:4)]; end %#ok<AGROW>
    icomp = h(5); k = k + 2 + n;
end
M = vertcat(rows{:}); assert(any(icomp == [1 2]), 'APAT:UnsupportedICOMP', 'Unsupported .cut ICOMP = %g (only 1 = θ/φ and 2 = RHCP/LHCP are supported).', icomp);
if isscalar(unique(M(:, 2)))   % one cut → body of revolution, disclosed (D20)
    M = repmat(M, 36, 1); M(:, 2) = repelem((0:10:350).', size(M, 1)/36); S.Meta.Notes(end + 1) = "Single φ cut replicated every 10° as a body of revolution.";
end
if icomp == 2, names = {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; basis = "rl"; else, names = {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; basis = "lin"; end
S.Raw = array2table(M, 'VariableNames', names); S.Blocks = {io_fields(M, "tp", "reim", basis)};
end

function S = io_text(fp, fmt, S)
%IO_TEXT Generic CSV/TXT/DAT: coverage-results table, gain-only pattern, or six-column E-field table in the selected format.
opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
T = readtable(fp, opts); T = T(~any(isnan(T{:, 1:2}), 2), :);                            % drop rows only on θ/φ NaN (D24)
assert(width(T) >= 2 && height(T) > 0, 'APAT:TextColumns', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames); hasHeaders = ~all(startsWith(names, "Var")); c1 = T{:, 1}; c2 = T{:, 2};
byKeyword = contains(lower(names(1)), "threshold") || any(contains(lower(names(2:end)), "coverage"));
if byKeyword || (~hasHeaders && width(T) < 6 && issorted(c1, 'strictmonotonic') && all(c2 >= 0 & c2 <= 100))   % (D27)
    if ~hasHeaders, T.Properties.VariableNames = cellstr(["Threshold_dB", "Coverage_" + (1:width(T) - 1)]); end
    S.Raw = T; S.Meta.IsCoverage = true; return
end
if fmt == "gain"
    phiFirst = util_pick(hasHeaders && any(startsWith(lower(names(1:2)), ["phi", "az"])), startsWith(lower(names(1)), ["phi", "az"]), max(c1) - min(c1) > max(c2) - min(c2));
    if ~hasHeaders, S.Meta.Notes(end + 1) = "No header: the column with the wider span was taken as φ."; end
    T.Properties.VariableNames(1:2) = util_pick(phiFirst, {'Phi', 'Theta'}, {'Theta', 'Phi'}); T = movevars(T, 'Theta', 'Before', 1);
    S.Raw = T; S.Blocks = {T}; S.Meta.IsGainOnly = true; S.Meta.Format = 'Generic text (gain)'; S.Meta.Unit = "dBi"; S.Meta.UnitLabel = "dBi"; return
end
assert(width(T) >= 6, 'APAT:TextEField', 'The selected generic E-field format requires six numeric columns.');
M = T{:, 1:6}; form = "reim";
if endsWith(fmt, "magphase")
    form = "dbdeg"; big = max(abs(M(:, 3:6)), [], 1, 'omitnan') > 100;
    if big(2) && ~big(3), form = "dbdeg_i"; end
    S.Meta.Notes(end + 1) = "Magnitude/phase layout detected as " + util_pick(form == "dbdeg", "grouped (m m p p)", "interleaved (m p m p)") + " from value ranges.";
end
basis = util_pick(startsWith(fmt, "linear"), "lin", util_pick(startsWith(fmt, "rcp"), "rl", "lr"));
S.Raw = T; S.Blocks = {io_fields(M, "tp", form, basis)}; S.Meta.Format = sprintf('Generic text (%s)', fmt);
S.Meta.Notes(end + 1) = "Generic E-field text: levels are relative dB unless the file already holds dBi magnitudes.";
end

function S = io_excel(fp, S)
%IO_EXCEL Excel matrix templates: component sheets (row 2 = φ from C, column B = θ from row 3, C3-origin matrix), first sheet = summary.
sheets = sheetnames(fp);
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"]; linr = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(linr), lower(sheets)));
assert(hasC || hasL, 'APAT:ExcelSheets', 'Unsupported workbook: expected the fixed Etheta/Ephi and/or RHCP/LHCP component sheets.');
required = [linr(1:4*hasL), circ(1:4*hasC)]; Z = struct(); ref = [];
for nm = required
    C = readcell(fp, 'Sheet', char(sheets(strcmpi(sheets, nm))));
    phi = util_num(C(2, 3:end)); theta = util_num(C(3:end, 2)); X = util_num(C(3:end, 3:end));
    keepR = isfinite(theta) & any(isfinite(X), 2); keepC = isfinite(phi) & any(isfinite(X), 1); theta = theta(keepR); phi = phi(keepC); X = X(keepR, keepC);
    if isempty(ref), ref = {theta, phi}; else, assert(isequal(size(X), [numel(ref{1}), numel(ref{2})]), 'APAT:ExcelGrid', 'All component sheets must share the same θ/φ grid.'); end
    Z.(nm) = X;
end
[phiG, thetaG] = meshgrid(ref{2}, ref{1}); field = @(g, p) 10.^(Z.(g)/20) .* exp(1i*deg2rad(Z.(p)));
if hasL, Eth = field("Etheta_Gain_dBi", "Etheta_Phase_degrees"); Eph = field("Ephi_Gain_dBi", "Ephi_Phase_degrees");
else, [Eth, Eph] = pol_fromCircular(field("RHCP_Gain_dBi", "RHCP_Phase_degrees"), field("LHCP_Gain_dBi", "LHCP_Phase_degrees")); end
S.Raw = table(thetaG(:), phiG(:), 'VariableNames', {'Theta', 'Phi'}); for nm = required, S.Raw.(nm) = Z.(nm)(:); end
S.Blocks = {table(thetaG(:), phiG(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'})};
S.Meta.Format = sprintf('Excel Matrix Format %d', 1*(hasL && ~hasC) + 2*(hasC && ~hasL) + 3*(hasL && hasC)); S.Meta.Unit = "dBi"; S.Meta.UnitLabel = "dBi";
summary = readcell(fp, 'Sheet', char(sheets(1)));                                        % only the frequency cell is used (D30)
[r, c] = find(cellfun(@(v) (ischar(v) || isstring(v)) && contains(string(v), 'Pattern Simulation Freq', 'IgnoreCase', true), summary), 1);
if ~isempty(r), v = util_num(summary(r, c + 1:end)); v = v(find(isfinite(v), 1)); if ~isempty(v), S.Freqs = v*1e6; end, end
end

%% ======================================================================= utilities

function kind = util_colKind(name)
%UTIL_COLKIND Semantic kind of a column from its name: gain | ar | plf | phase | eirp | pfd | field | other.
key = lower(regexprep(char(name), '[^a-zA-Z0-9]', ''));
if strcmp(key, 'ar') || startsWith(key, 'ardb') || contains(key, 'axialratio'), kind = "ar";
elseif contains(key, 'plf'), kind = "plf";
elseif contains(key, 'phase') || endsWith(key, 'deg'), kind = "phase";
elseif contains(key, 'eirp'), kind = "eirp";
elseif contains(key, 'pfd'), kind = "pfd";
elseif contains(key, 'rms'), kind = "field";
elseif contains(key, 'gain') || contains(key, 'directivity') || endsWith(key, 'db') || endsWith(key, 'dbi'), kind = "gain";
else, kind = "other";
end
end

function step = util_assertUniform(axis, name)
%UTIL_ASSERTUNIFORM Median step of a sorted axis; errors when any gap deviates (§15-1). NaN for a single value.
d = diff(axis(:)); step = NaN; if isempty(d), return; end, step = median(d);
if any(abs(d - step) > 1e-6), error('APAT:NonUniformGrid', '%s axis is not uniform: steps range %.6g°..%.6g° (APAT requires uniform grids).', name, min(d), max(d)); end
end

function X = util_grid(n, lin, v), X = nan(n); X(lin) = v; end

function step = util_gridStep(v), d = diff(unique(v(isfinite(v)))); d = d(d > 1e-9); step = NaN; if ~isempty(d), step = min(d); end, end

function out = util_pick(cond, a, b), if cond, out = a; else, out = b; end, end

function v = util_num(c)
%UTIL_NUM Cell array from readcell → double array (missing/text → NaN).
v = cellfun(@(x) util_pick(isnumeric(x) && isscalar(x), double(x), str2double(string(x))), c);
end

function s = util_fmtNumber(v, prec)
%UTIL_FMTNUMBER Compact (≤ 2 decimals, no trailing zeros, never "-0") or fixed precision; 'n/a' when not finite.
if ~(isscalar(v) && isnumeric(v) && isfinite(v)), s = 'n/a'; return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v), {'0+$', '\.$'}, ''); else, s = sprintf('%.*f', prec, v); end
if ~isempty(regexp(s, '^-0(\.0*)?$', 'once')), s = s(2:end); end
end

function bounds = util_presetRange(peak)
%UTIL_PRESETRANGE 50 dB window ending at the peak rounded up to 5 dB, clamped to the widget limits.
if ~isfinite(peak), bounds = [-50 0]; return; end
upper = ceil(peak/5)*5; bounds = min(max([upper - 50, upper], -250), 100);
end

function ticks = util_ticks(limits, step)
%UTIL_TICKS Tick vector at multiples of step inside limits (limits included), empty when it would be unreadable.
ticks = []; if ~isfinite(step) || step <= 0 || diff(limits) <= 0, return; end
ticks = unique([limits(1), ceil(limits(1)/step)*step:step:floor(limits(2)/step)*step, limits(2)], 'stable');
if numel(ticks) > 60, ticks = []; end
end