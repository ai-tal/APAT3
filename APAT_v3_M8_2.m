classdef APAT_v3_M8_2 < matlab.apps.AppBase %1623-lines % >> Loading Error: "Unrecognized field name "Component". (APAT_v3_M8.renderFull line 414)"
% APAT v3 M8 — Antenna Pattern Analyzer Tool.
%
% One grid-native pattern, one derivation function, one pattern registry shared by
% both tabs, one dispatcher, one declarative layout.  Base MATLAB only (R2023b+).
%
%   SOURCE ─► PATTERN(Revision) ─► GEOMETRY ─► DERIVED(Revision, Params)   all in Pats(k)
%     │            └─► PLOTS / CUTS / TABLES / METADATA (+Map)     └─► COVERAGE job = curve {T, cov}
%   VIEW (widgets, read once by readConfig) ─► MAP (display permutation, touches no data)
%
% Rule: widgets are read only in readConfig/readCoverageConfig; math never sees a widget;
% widgets are written only in apply*/render*.  Every callback is app.on("<scope>").

    properties (GetAccess = public, SetAccess = private)
        isClosing logical = false
        Perf struct = struct()                       % last timed operation {AppVersion, Operation, Stages, TotalSeconds}
    end

    properties (Access = public)  % UI handles (App Designer style; names unchanged from M7)
        UIFigure; GridLayout; TabGroup; Tab1_Single; Single_Grid; Single_panelParam; Single_gridPanel_Param
        Single_DropDown_FFD; FFDFreqDropDownLabel; Single_DropDown_TextFormat; TextFormatLabel
        Single_Export_UAN; Single_Button_ResetParams; Single_Export_Output; Single_Button_Coverage; Single_Button_Process
        Single_DropDown_step; Single_DropDown_R; Single_Spinner_R; DistanceLabel; Single_Button_Load
        Single_DropDown_Pt; Single_Spinner_Pt; TransmitPowerLabel; Single_Spinner_Loss; LossindBLabel
        Single_Spinner_Rw; IncidentWaveARRwPLFLabel; Single_DropDown_RxPol; RxPolLabel
        Single_EditField_Path; InputPatternLabel; Single_StatusBar
        Single_Panel_plotControl; Single_gridPanel_Ctrl; View3DLabel; Single_DropDown_3DView
        Singel_CheckBox_overlayCut; Single_CheckBox_POB; Single_CheckBox_HPBWBounds
        Single_Switch_EHplane; Single_Switch_AngularSpan; Single_Switch_ThetaSpan; CutvalueSpinnerLabel
        Single_Label_Clim; Single_Button_Clim; Single_Plot_Cstep; ColorbarstepLabel
        Single_Plot_Cmin; ColorbarminLabel; Single_Plot_Cmax; ColorbarmaxLabel
        Single_DropDown_cutValue; Single_DropDown_cutType; CutFieldBasisDropDown; CuttypeDropDownLabel; CutFieldsLabel
        Single_DropDown_Component; ComponentLabel
        Single_tabData; Single_tabDataOut; Single_gridDataOut; Single_Table_DataOut
        Single_tabDataIn; Single_gridDataIn; Single_Table_DataIn; MetadataTab; Single_gridMetadata; Single_Table_metadata
        Single_DropDown_output; Single_Panel_Rect; Single_gridPanel_Cut; Single_tabCut
        Single_tabPolarPlot; Single_Grid_Polar; Single_gridEcut; CheckBox_Et; CheckBox_Er; CheckBox_El
        Button_ExportCut; Range_Cut_Max; Range_Cut_Min; Label_HPBW; Button_HPBW; Range_Cut
        Single_tabRectPlot; Single_gridRect; Single_AxesRect
        Single_Panel_fullPattern; Single_gridPanel_full; Single_tabPlots
        Single_tabContour; Single_gridContour; Range_Ctr_Min; Range_Ctr_Max; Range_Ctr; Single_Axes_Ctr
        Single_tabCircular; Single_gridCircular; Range_Cir_Min; Range_Cir_Max; Range_Cir
        Single_tab3DSpherical; Single_grid3dSpherical; Range_3dSph_Min; Range_3dSph_Max; Range_3dSph; Single_Axes_3dSph
        Single_tab3DPolar; Single_grid3dPolar; Range_3dPol_Min; Range_3dPol_Max; Range_3dPol; Single_Axes_3dPol
        Single_tab3DRect; Single_grid3dRect; Range_3dRect_Min; Range_3dRect_Max; Range_3dRect; Single_Axes_3dRect
        Tab2_Coverage; Cov_Grid; Cov_Panel_Results; GridLayout2
        Cov_Spinner_XMin; Cov_Spinner_XMax; Cov_Spinner_XRange; Cov_Tabel; Cov_Tree; Cov_TreeNode_Results; Cov_Axes; Cov_StatusBar
        Cov_Panel_Param; Cov_gridPanel_Parm; Cov_DropDown_OrientationLabel; Cov_DropDown_TextFormat; Cov_TextFormatLabel
        Cov_Button_queryThresh; Cov_Button_queryCov; Cov_DropDown_Component; Cov_DropDown_ComponentLabel
        Cov_Spinner_queryThresh; Cov_QueryThresholdLabel; Cov_Spinner_queryCov; Cov_QueryCoverageLabel
        Cov_Button_toMain; Cov_Button_Clear; Cov_Spinner_ConeAng; ConeAngleLabel; Cov_Spinner_ConePH; ConeLabel
        Cov_Spinner_ConeTH; ConeSpinnerLabel; Cov_Spinner_Step; StepdBSpinnerLabel
        Cov_Spinner_ThreshMax; ThresholdMaxdBSpinnerLabel; Cov_Spinner_ThreshMin; ThresholdMindBSpinnerLabel
        Cov_Button_Export; Cov_Button_Reset; Cov_Button_computeCov; Cov_Button_Load
        Cov_EditField_filePath; AntennaPatternEditFieldLabel; Cov_DropDown_Orientation
        Cov_ButtonGroup_CovType; Cov_ButtonGroup_Btn_Conical; Cov_ButtonGroup_Btn_Spherical
        PaxCut; PaxPattern                           % polar axes (created in startupFcn)
    end

    properties (Access = private)
        Pats = struct('Name', {}, 'Path', {}, 'Source', {}, 'Pattern', {}, 'Geometry', {}, 'Derived', {}, 'Params', {})
        Main double = 0                              % index into Pats shown on the Main tab (0 = none)
        View struct = struct('OutMask', logical([]), 'BasisAuto', true)
        Map struct = struct()                        % display permutation/axes (geo_displayMap)
        Range struct = struct('full', [-40 10], 'cut', [-40 10], 'cov', [-40 10], 'covX', [-40 10], ...
            'Auto', struct('full', true, 'cut', true, 'cov', true, 'covX', true))
        Gfx struct = struct()                        % retained graphics: Full(k).{Axes,Surface,Marker,Tip,Overlay,Colorbar,Key}, Menu
        CutK struct = struct('Key', '')              % current cut extract (geo_cut) shared by cut plots and 3-D overlays
        PeakSel struct = struct()                    % peak of the selected component (marker/status)
        Status struct = struct()                     % persistent status text per status label
        Busy logical = false
        Dialog = []                                  % cancellable progress dialog while a long stage runs
        StatusTimer = []                             % the one transient-status timer
        PerfRun = []
        CovRunID double = 0
        Defaults cell = {}                           % parameter defaults captured at startup (Reset Params)
    end

    properties (Constant, Access = private)
        %        name                    label             kind      hidden
        Cols = {'E_Total_dB'            'Total Gain'      'gain'    false
                'E_TH_dB'               'Etheta Gain'     'gain'    true
                'E_PH_dB'               'Ephi Gain'       'gain'    true
                'E_RCP_dB'              'RHCP Gain'       'gain'    false
                'E_LCP_dB'              'LHCP Gain'       'gain'    false
                'AR_dB'                 'Axial Ratio'     'ar'      false
                'PLF_dB'                'PLF'             'plf'     false
                'Gain_PolCorrected_dB'  'Polarized Gain'  'gain'    false
                'E_TH_Phase'            'Etheta Phase'    'phase'   true
                'E_PH_Phase'            'Ephi Phase'      'phase'   true
                'E_RCP_Phase'           'RHCP Phase'      'phase'   true
                'E_LCP_Phase'           'LHCP Phase'      'phase'   true
                'EIRP_dBW'              'EIRP'            'link'    true
                'PFD_Wm2'               'PFD'             'link'    true
                'E_RMS_Vm'              'E_RMS'           'link'    true}
        Views = {'contour', 'circular', 'sphere3D', 'polar3D', 'rect3D'}   % rows of Gfx.Full; order = tab order
        PrincipalAxes = struct('labels', {{'+Z', '-Z', '+X', '-X', '+Y', '-Y'}}, 'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])
        PeakExcessDB = 6                             % spatial-isolation spike excess (I5)
        ARLimits = [-30 30]                          % signed axial-ratio colour scale
        Hard = [-250 100]                            % hard limits of every dB range control
        DistanceFloorM = 1e-12
        ReleaseName = 'APAT v3 Milestone 8'
    end

    %% ---------------------------------------------------------------- orchestration
    methods (Access = private)

        function [V, prm] = readConfig(app)
            % The ONLY reader of Main-tab widget values.  Returns the view and the parameters.
            V = app.View;                                             % keeps OutMask / BasisAuto (non-widget state)
            V.Component = string(app.Single_DropDown_Component.Value);
            V.CutType = string(app.Single_DropDown_cutType.Value);  V.CutValue = app.Single_DropDown_cutValue.Value;
            V.SignedPhi = strcmp(app.Single_Switch_AngularSpan.Value, '-180° to 180°');
            V.Elevation = strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°');
            V.Basis = string(app.CutFieldBasisDropDown.Value);
            V.Traces = logical([app.CheckBox_Et.Value, app.CheckBox_Er.Value, app.CheckBox_El.Value]);
            V.HPBW = app.Button_HPBW.Value;  V.HPBWTips = app.Single_CheckBox_HPBWBounds.Value;
            V.POB = app.Single_CheckBox_POB.Value;  V.Overlay = app.Singel_CheckBox_overlayCut.Value;
            V.OneDegree = strcmp(app.Single_DropDown_step.Value, 'STEP: 1°');
            V.FreqIndex = max([1, find(strcmp(app.Single_DropDown_FFD.Items, app.Single_DropDown_FFD.Value), 1)]);
            V.Camera = string(app.Single_DropDown_3DView.Value);  V.CStep = app.Single_Plot_Cstep.Value;
            V.TextFormat = string(app.Single_DropDown_TextFormat.Value);
            prm.L = app.Single_Spinner_Loss.Value;  prm.RxMode = string(app.Single_DropDown_RxPol.Value);  prm.RxAR_dB = app.Single_Spinner_Rw.Value;
            pt = app.Single_Spinner_Pt.Value;
            switch app.Single_DropDown_Pt.Value, case 'dBm', prm.Pt_dBW = pt - 30; case 'Watts', prm.Pt_dBW = 10*log10(max(pt, eps)); otherwise, prm.Pt_dBW = pt; end
            prm.R_m = max(app.Single_Spinner_R.Value, app.DistanceFloorM) * (1 + 999*strcmp(app.Single_DropDown_R.Value, 'km'));
            prm.Key = sprintf('%g|%s|%g|%g|%g', prm.L, prm.RxMode, prm.RxAR_dB, prm.Pt_dBW, prm.R_m);
        end

        function on(app, scope, varargin)
            % Guard around every user action: busy flag, try/catch, cancellation, timing, one drawnow.
            if app.Busy || app.isClosing, return; end
            app.Busy = true;  guard = onCleanup(@() app.setBusy(false)); 
            app.perf("begin " + scope);
            try
                app.update(scope, varargin{:});  drawnow limitrate
            catch err
                if ~isempty(app.Dialog) && isvalid(app.Dialog), delete(app.Dialog); end
                if strcmp(err.identifier, 'APAT:Cancelled'), app.setStatus(app.Single_StatusBar, 'Operation cancelled by user.', true);
                else, app.showError(err, char(scope)); end
            end
            app.perf("end");
        end

        function setBusy(app, tf), if ~app.isClosing, app.Busy = tf; end, end

        function update(app, scope, varargin)
            % The dispatcher.  Ladder: source ⊃ freq ⊃ step ⊃ params ⊃ {component, span, cut, plane, range, annot, camera}.
            switch scope
                case "source",                  if ~app.loadMain(varargin{:}), return; end
                case {"freq", "step", "params"}, if app.Main == 0, return; end, app.rebuild(scope);
                case "reset",                   app.applyDefaults();  if app.Main == 0, return; end, scope = "params";  app.rebuild(scope);
                case "range",                   app.applyRange(varargin{:});  return
                case "camera",                  app.applyCamera();  return
                case "tables",                  app.renderTables();  return
                case "filter",                  app.applyFilter();  app.renderTables();  app.applyVisibility();  return
                case "plane",                   if app.Main == 0, return; end, app.applyChoices("plane");  scope = "cut";
                case "cutType",                 if app.Main == 0, return; end, app.applyChoices("cut");  scope = "cut";
                case "basis",                   app.View.BasisAuto = false;  scope = "cut";
                case {"exportResults", "exportCut", "exportUAN"}, app.export(scope);  return
                case "covFromMain",             app.covFromMain();  return
                case "covLoad",                 app.covLoad(varargin{:});  return
                case "covRun",                  app.covRun();  return
                case "covQuery",                app.covQuery(varargin{:});  return
                case "covSelect",               app.covSelect();  return
                case "covCheck",                app.covCheck();  return
                case "covType",                 app.covSync();  app.applyVisibility();  return
                case "covOrient",               app.covOrient();  return
                case "covComp",                 app.covSync();  return
                case "covRange",                app.Range.Auto.cov = false;  return
                case "covReset",                app.covReset();  return
                case "covClear",                app.covClear();  return
                case "covExport",               app.export("covExport");  return
            end
            if app.Main == 0, return; end
            if any(scope == ["source", "freq", "step", "span"]), app.applyChoices("cut"); end
            [app.View, ~] = app.readConfig();
            E = app.Pats(app.Main);  V = app.View;
            app.Map = geo_displayMap(E.Pattern, E.Geometry, V.SignedPhi, V.Elevation);
            if V.Component == "E_Total_dB" || E.Pattern.IsGainOnly && V.Component == util_firstGain(E.Derived.Cols)
                app.PeakSel = E.Derived.Peak;
            else
                app.PeakSel = met_peak(E.Derived.Cols.(V.Component), E.Geometry.PhiPeriodic, app.PeakExcessDB);
            end
            numeric = any(scope == ["source", "freq", "step", "params"]);
            if numeric || any(scope == ["component", "span", "cut"]), app.renderCut(); end
            app.renderFull(app.visibleView());  app.applyCamera();  app.applyAnnot();
            if numeric || any(scope == ["component", "span"]), app.renderTables();  app.renderMetadata();  app.renderStatus(); end
            app.applyVisibility();
        end

        function ok = loadMain(app, fp)
            % Load (or reload) a file into the Main tab.  Coverage-result files are routed to the Coverage tab.
            ok = false;
            if nargin >= 2 && isempty(fp), return; end                    % format change with no file loaded
            if nargin < 2
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.csv;*.dat;*.txt', 'Pattern/Gain Files'}, 'Select an antenna pattern file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            app.Dialog = uiprogressdlg(app.UIFigure, 'Title', 'Loading Data', 'Message', 'Reading file...', 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            closer = onCleanup(@() delete(app.Dialog)); 
            [V, ~] = app.readConfig();
            S = io_read(fp, V.TextFormat);  app.perf("Read file");  app.checkCancelled();
            if S.Meta.IsCoverage
                app.TabGroup.SelectedTab = app.Tab2_Coverage;  app.Cov_EditField_filePath.Value = fp;
                app.covLoadResults(fp, S.Raw);  return
            end
            [~, name, ext] = fileparts(fp);
            E = struct('Name', [name ext], 'Path', fp, 'Source', S, 'Pattern', [], 'Geometry', [], 'Derived', [], 'Params', []);
            k = find(strcmp({app.Pats.Path}, fp), 1);  if isempty(k), k = numel(app.Pats) + 1; end
            app.Pats(k) = E;  app.Main = k;  app.Single_EditField_Path.Value = fp;
            app.View.BasisAuto = true;  app.View.OutMask = logical([]);
            app.Single_DropDown_FFD.Items = cellstr(compose('Pattern %d: %.4g GHz', (1:numel(S.Blocks))', S.Freqs(:)/1e9));
            app.rebuild("source");  ok = true;
        end

        function rebuild(app, scope)
            % Build-then-commit of the numeric layers of Pats(app.Main); nothing is stored before the end (I13).
            E = app.Pats(app.Main);
            [V, prm] = app.readConfig();
            if scope == "params"
                P = E.Pattern;  G = E.Geometry;
            else
                P = pat_build(E.Source, V.FreqIndex);  app.perf("Build pattern");  app.checkCancelled();
                app.applyChoices("step", P);
                V = app.readConfig();
                if V.OneDegree && (abs(P.dTheta - 1) > 1e-9 || abs(P.dPhi - 1) > 1e-9), P = pat_resample(P, 1);  app.perf("Resample"); end
                G = geo_build(P);
            end
            D = pat_derive(P, G, prm, app.PrincipalAxes, app.PeakExcessDB);  app.perf("Derive");  app.checkCancelled();
            E.Pattern = P;  E.Geometry = G;  E.Derived = D;  E.Params = prm;  app.Pats(app.Main) = E;      % commit
            if scope == "params", return; end
            app.applyChoices("all");
            preset = util_presetRange(D.Peak.value);
            if app.Range.Auto.full, app.applyRange("full", -1, preset); end
            if app.Range.Auto.cut,  app.applyRange("cut", -1, preset); end
            app.Gfx.RawKey = '';  app.CutK.Key = '';
        end

        function applyChoices(app, what, P)
            % The only writer of data-derived Items/ItemsData/Limits/Step/Value on the Main tab.
            E = app.Pats(app.Main);  if nargin < 3, P = E.Pattern; end
            if any(what == ["step", "all"])
                native = max(P.NativeStep);  dd = app.Single_DropDown_step;
                items = {sprintf('STEP: %g°', native)};  if abs(native - 1) > 1e-9, items{end+1} = 'STEP: 1°'; end
                keepOne = strcmp(dd.Value, 'STEP: 1°') && numel(items) == 2;
                dd.Items = items;  dd.Value = items{1 + keepOne};
                if what == "step", return; end
            end
            D = E.Derived;
            if what == "all"
                [names, labels] = app.componentList(D.Cols, P.IsGainOnly);
                for dd = [app.Single_DropDown_Component, app.Cov_DropDown_Component]
                    prev = dd.Value;  dd.Items = labels;  dd.ItemsData = names;
                    if any(strcmp(names, prev)), dd.Value = prev; end
                end
                if isempty(app.View.OutMask) || numel(app.View.OutMask) ~= numel(fieldnames(D.Cols))
                    app.View.OutMask = ~util_colHidden(fieldnames(D.Cols), app.Cols);
                end
                dd = app.Single_DropDown_output;  cols = fieldnames(D.Cols)';
                dd.Items = [{'--- column filter ---'}, cols];  dd.ItemsData = 0:numel(cols);  dd.Value = 0;  app.applyFilter();
                if ~P.IsGainOnly
                    if app.View.BasisAuto, app.CutFieldBasisDropDown.Value = char(D.Pol.basis); end
                    pair = D.Pol.pairs.(app.CutFieldBasisDropDown.Value);
                    [app.CheckBox_Er.Text, app.CheckBox_El.Text] = deal(char(pair(1)), char(pair(2)));
                end
                what = "plane";
            end
            if what == "plane"       % E/H switch → cut type/value from the derived principal planes
                S = D.Planes.(char(extractBefore(app.Single_Switch_EHplane.Value, 2)));
                app.Single_DropDown_cutType.Value = char(S.type);  value = S.value;
                if S.type == "Phi" && strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°'), value = 90 - value; end
                app.Single_DropDown_cutValue.Value = value;
            end
            % cut-value domain follows the display convention (I8)
            M = geo_displayMap(P, E.Geometry, strcmp(app.Single_Switch_AngularSpan.Value, '-180° to 180°'), strcmp(app.Single_Switch_ThetaSpan.Value, '-90° to 90°'));
            if strcmp(app.Single_DropDown_cutType.Value, 'Phi'), vals = M.ThetaAxis;  step = P.dTheta; else, vals = M.PhiAxis(1:numel(P.Phi));  step = P.dPhi; end
            sp = app.Single_DropDown_cutValue;  sp.Limits = util_span(vals);  sp.Step = step;
            [~, i] = min(abs(vals - sp.Value));  sp.Value = vals(i);
        end

        function [names, labels] = componentList(app, C, gainOnly)
            names = fieldnames(C)';
            if gainOnly, labels = names;  return; end
            keep = ismember(names, app.Cols(ismember(app.Cols(:, 3), {'gain', 'ar', 'plf'}), 1)');
            names = names(keep);  [~, i] = ismember(names, app.Cols(:, 1));  labels = app.Cols(i, 2)';
        end

        function applyFilter(app)
            % Results column filter: dropdown click toggles one column of View.OutMask; styles show the state.
            dd = app.Single_DropDown_output;  mask = app.View.OutMask;
            if dd.Value > 0, mask(dd.Value) = ~mask(dd.Value);  dd.Value = 0; end
            app.View.OutMask = mask;  dd.Items = regexprep(dd.Items, '^✓ ?', '');
            removeStyle(dd);  on = find(mask) + 1;  dd.Items(on) = append('✓ ', dd.Items(on));
            if ~isempty(on), addStyle(dd, uistyle('FontWeight', 'bold', 'BackgroundColor', [0.8 1 0.8]), 'Item', on); end
            addStyle(dd, uistyle('FontColor', [0.5 0.5 0.5], 'BackgroundColor', [0.9 0.9 0.9]), 'Item', find([true, ~mask(:).']));
        end

        function applyDefaults(app)
            d = app.Defaults;
            [app.Single_Spinner_Loss.Value, app.Single_DropDown_RxPol.Value, app.Single_Spinner_Rw.Value, app.Single_Spinner_Pt.Value, ...
                app.Single_DropDown_Pt.Value, app.Single_Spinner_R.Value, app.Single_DropDown_R.Value] = deal(d{:});
        end

        function applyRange(app, group, which, value)
            % One controller for the four dB range groups.  which: -1 preset, 0 apply both, 1 min spinner, 2 max spinner, 3 slider.
            if group == "all", app.applyRange("full", which, value);  app.applyRange("cut", which, value);  return; end
            H = app.Hard;  lim = app.Range.(group);  gap = 1;  if any(group == ["cov", "covX"]), gap = 0.1; end
            if which == 1 || which == 2, lim(which) = double(value); else, lim = sort(double(value(:).')); end
            lim = [max(H(1), lim(1)), min(H(2), lim(2))];
            if diff(lim) < gap, if which == 2, lim(1) = max(H(1), lim(2) - gap); else, lim(2) = min(H(2), lim(1) + gap); end, end
            app.Range.(group) = lim;  if which >= 0, app.Range.Auto.(group) = false; end
            switch group
                case "full", sl = [app.Range_Ctr, app.Range_Cir, app.Range_3dSph, app.Range_3dPol, app.Range_3dRect];
                             mn = [app.Range_Ctr_Min, app.Range_Cir_Min, app.Range_3dSph_Min, app.Range_3dPol_Min, app.Range_3dRect_Min, app.Single_Plot_Cmin];
                             mx = [app.Range_Ctr_Max, app.Range_Cir_Max, app.Range_3dSph_Max, app.Range_3dPol_Max, app.Range_3dRect_Max, app.Single_Plot_Cmax];
                case "cut",  sl = app.Range_Cut;  mn = app.Range_Cut_Min;  mx = app.Range_Cut_Max;
                case "cov",  sl = [];  mn = app.Cov_Spinner_ThreshMin;  mx = app.Cov_Spinner_ThreshMax;
                case "covX", sl = app.Cov_Spinner_XRange;  mn = app.Cov_Spinner_XMin;  mx = app.Cov_Spinner_XMax;
            end
            if ~isempty(sl)
                travel = lim;  if which == 3, travel = sl(1).Limits; elseif which == 1 || which == 2, travel = [min(sl(1).Limits(1), lim(1)), max(sl(1).Limits(2), lim(2))]; end
                set(sl, 'Limits', H, 'Value', lim);  set(sl, 'Limits', travel);
            end
            set(mn, 'Limits', [H(1), lim(2) - gap], 'Value', lim(1));  set(mx, 'Limits', [lim(1) + gap, H(2)], 'Value', lim(2));
            switch group
                case "full", if app.Main > 0, app.renderFull(app.visibleView()); end
                case "cut",  set(app.PaxCut, 'RLim', lim, 'RTick', lim(1):5:lim(2));  set(app.Single_AxesRect, 'YLim', lim);
                case "covX", set(app.Cov_Axes, 'XLimMode', 'manual', 'XLim', lim);
            end
        end

        function applyVisibility(app)
            % The only writer of Visible/Enable; computed from source kind, selected component and coverage state.
            has = app.Main > 0;  field = has && ~app.Pats(app.Main).Pattern.IsGainOnly;
            set([app.Single_Panel_Rect, app.Single_Export_Output, app.Single_Panel_fullPattern, app.Single_Panel_plotControl, ...
                app.Single_Button_Coverage, app.Single_tabData, app.Single_DropDown_output, app.Single_Table_DataOut, app.Single_Table_DataIn], 'Visible', has);
            set([app.Single_Export_UAN, app.Single_gridEcut, app.CheckBox_Et, app.CheckBox_Er, app.CheckBox_El], 'Visible', field);
            set([app.CheckBox_Er, app.CheckBox_El, app.CutFieldBasisDropDown], 'Enable', field);
            set([app.FFDFreqDropDownLabel, app.Single_DropDown_FFD], 'Visible', has && numel(app.Single_DropDown_FFD.Items) > 1, 'Enable', 'on');
            set(app.Single_DropDown_step, 'Visible', has && numel(app.Single_DropDown_step.Items) > 1, 'Enable', 'on');
            set([app.TextFormatLabel, app.Single_DropDown_TextFormat], 'Visible', util_isGenericText(app.Single_EditField_Path.Value));
            app.Single_CheckBox_HPBWBounds.Visible = app.Button_HPBW.Value;
            sel = strings(0);  if has, cols = string(fieldnames(app.Pats(app.Main).Derived.Cols));  sel = [cols(app.View.OutMask); app.View.Component]; end
            set([app.RxPolLabel, app.Single_DropDown_RxPol, app.IncidentWaveARRwPLFLabel, app.Single_Spinner_Rw], 'Visible', any(ismember(sel, ["PLF_dB", "Gain_PolCorrected_dB"])));
            set([app.TransmitPowerLabel, app.Single_Spinner_Pt, app.Single_DropDown_Pt], 'Visible', any(ismember(sel, ["EIRP_dBW", "PFD_Wm2", "E_RMS_Vm"])));
            set([app.DistanceLabel, app.Single_Spinner_R, app.Single_DropDown_R], 'Visible', any(ismember(sel, ["PFD_Wm2", "E_RMS_Vm"])));
            set([app.LossindBLabel, app.Single_Spinner_Loss], 'Visible', has && (~field || any(util_colKind(sel) == "gain")));
            % coverage tab: empty | pattern | results
            node = app.covTarget();  jobs = app.covJobs();  ctl = app.Cov_gridPanel_Parm.Children;
            always = [app.AntennaPatternEditFieldLabel, app.Cov_EditField_filePath, app.Cov_Button_Load, app.Cov_Button_computeCov, app.Cov_Button_toMain];
            query = [app.Cov_QueryCoverageLabel, app.Cov_Spinner_queryCov, app.Cov_Button_queryCov, app.Cov_QueryThresholdLabel, app.Cov_Spinner_queryThresh, app.Cov_Button_queryThresh];
            set(ctl, 'Visible', ~isempty(node), 'Enable', ~isempty(node));  set(always, 'Visible', 'on', 'Enable', 'on');
            set([query, app.Cov_Button_Reset, app.Cov_Button_Export, app.Cov_Button_Clear], 'Visible', 'on', 'Enable', ~isempty(jobs));
            set([app.Cov_Button_computeCov, app.Cov_DropDown_Component, app.Cov_DropDown_ComponentLabel], 'Enable', ~isempty(node));
            conical = app.Cov_ButtonGroup_Btn_Conical.Value;
            set([app.Cov_Spinner_ConeTH, app.Cov_Spinner_ConePH, app.Cov_Spinner_ConeAng, app.ConeSpinnerLabel, app.ConeLabel, app.ConeAngleLabel, ...
                app.Cov_DropDown_Orientation, app.Cov_DropDown_OrientationLabel], 'Enable', conical, 'Visible', conical && ~isempty(node));
            set([app.Cov_TextFormatLabel, app.Cov_DropDown_TextFormat], 'Visible', ~isempty(node) && util_isGenericText(app.Cov_EditField_filePath.Value));
            app.Cov_Panel_Results.Visible = ~isempty(app.Cov_TreeNode_Results.Children);
        end

        function perf(app, stage)
            % perf("begin <op>") | perf("<stage>") | perf("end") → app.Perf and base-workspace Perf_APAT_v3_M8 (same record as M7).
            if startsWith(stage, "begin"), app.PerfRun = struct('Op', extractAfter(stage, 6), 'T0', tic, 'T', tic, 'Rows', {cell(0, 2)});  return; end
            if isempty(app.PerfRun), return; end
            app.PerfRun.Rows(end+1, :) = {char(stage), toc(app.PerfRun.T)};  app.PerfRun.T = tic;
            if stage ~= "end", return; end
            app.Perf = struct('AppVersion', class(app), 'Operation', app.PerfRun.Op, 'Stages', cell2table(app.PerfRun.Rows, 'VariableNames', {'Stage', 'Seconds'}), 'TotalSeconds', toc(app.PerfRun.T0));
            assignin('base', "Perf_" + class(app), app.Perf);  app.PerfRun = [];
        end

        function setStatus(app, label, msg, transient)
            % One reusable timer; persistent text lives in app.Status.(label.Tag), never in a widget.
            if app.isClosing || ~isgraphics(label), return; end
            stop(app.StatusTimer);  label.Text = char(msg);
            if ~transient, app.Status.(label.Tag) = char(msg);  return; end
            app.StatusTimer.TimerFcn = @(~, ~) set(label, 'Text', app.Status.(label.Tag));  start(app.StatusTimer);
        end

        function checkCancelled(app)
            if ~isempty(app.Dialog) && isvalid(app.Dialog) && app.Dialog.CancelRequested, error('APAT:Cancelled', 'Operation cancelled by user.'); end
        end

        function showError(app, err, title)
            if app.isClosing, return; end
            where = '';  if ~isempty(err.stack), where = sprintf('\n(%s line %d)', err.stack(1).name, err.stack(1).line); end
            uialert(app.UIFigure, [err.message where], ['APAT — ' title], 'Icon', 'error');
        end
    end

    %% ---------------------------------------------------------------- renderers
    methods (Access = private)

        function k = visibleView(app)
            k = find(app.Single_tabPlots.SelectedTab == [app.Single_tabContour, app.Single_tabCircular, app.Single_tab3DSpherical, app.Single_tab3DPolar, app.Single_tab3DRect], 1);
        end

        function [label, unit, fmt] = compInfo(app, name)
            % Display label, unit and datatip format of a column (Meta.UnitLabel for levels, dB otherwise).
            if nargin < 2, name = app.View.Component; end
            i = find(strcmp(app.Cols(:, 1), name), 1);  label = char(name);  if ~isempty(i), label = app.Cols{i, 2}; end
            unit = 'dB';  if util_colKind(name) == "gain", unit = char(app.Pats(app.Main).Pattern.Meta.UnitLabel); end
            fmt = ['%.3g ' unit];
        end

        function renderFull(app, k)
            % Render one full-pattern view in place; skipped when its key is unchanged (I12).
            if app.Main == 0 || isempty(k), return; end
            E = app.Pats(app.Main);  P = E.Pattern;  V = app.View;  M = app.Map;  s = app.Gfx.Full(k);  ax = s.Axes;
            isAR = util_colKind(V.Component) == "ar";  lim = app.Range.full;  if isAR, lim = app.ARLimits; end
            [label, unit, fmt] = app.compInfo();  tex = replace(label, '_', '\_');
            key = sprintf('%d|%s|%s|%s|%s|%g|%d', P.Revision, E.Params.Key, V.Component, M.Key, mat2str(lim), V.CStep, app.PeakSel.index);
            if strcmp(s.Key, key), return; end
            C = E.Derived.Cols.(V.Component);  C = C(:, M.ColIdx);
            switch app.Views{k}
                case 'contour',  X = M.PhiGrid;  Y = M.ThetaGrid;  Z = zeros(size(C));
                case 'circular', X = deg2rad(M.PhiPhys);  Y = M.ThetaPhys;  Z = zeros(size(C));
                case 'sphere3D', [X, Y, Z] = util_sph(M.ThetaPhys, M.PhiPhys, 1);
                case 'polar3D',  [X, Y, Z] = util_sph(M.ThetaPhys, M.PhiPhys, util_polarRadius(C, lim));
                case 'rect3D',   X = M.PhiGrid;  Y = M.ThetaGrid;  Z = C;
            end
            if isgraphics(s.Surface) && isequal(size(s.Surface.CData), size(C))
                set(s.Surface, 'XData', X, 'YData', Y, 'ZData', Z, 'CData', C);
            else
                delete([s.Surface, s.Marker, s.Tip, s.Overlay]);  hold(ax, 'on');       % grid size changed: rebuild the view's objects
                s.Surface = surface(ax, X, Y, Z, C, 'EdgeColor', 'none', 'FaceColor', 'interp', 'ContextMenu', app.Gfx.Menu);
                if s.IsPolar, s.Marker = polarplot(ax, 0, 0, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off');
                else, s.Marker = plot3(ax, 0, 0, 0, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off', 'Clipping', 'off'); end
                s.Tip = gobjects(0);  s.Overlay = gobjects(0);  hold(ax, 'off');  if k == 1, view(ax, 2); end
            end
            try, s.Surface.DataTipTemplate.DataTipRows = [dataTipTextRow(M.ThetaLabel, M.ThetaGrid, '%.3g°'); dataTipTextRow("Phi", M.PhiGrid, '%.3g°'); dataTipTextRow(tex, C, fmt)];
            catch err, app.Status.Warning = err.message; end
            % theme
            clim(ax, lim);  colormap(ax, util_colormap(isAR));  ticks = util_ticks(lim, V.CStep);
            if ~isempty(ticks), s.Colorbar.Ticks = ticks; end
            s.Colorbar.Label.String = sprintf('%s (%s)', label, unit);  s.Colorbar.Label.Interpreter = 'none';
            % axes convention
            phiLab = 0:30:330;  if V.SignedPhi, phiLab(phiLab > 180) = phiLab(phiLab > 180) - 360; end
            switch app.Views{k}
                case {'contour', 'rect3D'}
                    xl = util_span(M.PhiAxis);  yl = util_span(M.ThetaAxis);  st = 15 + 15*(k == 5);
                    set(ax, 'XLim', xl, 'YLim', yl, 'YDir', M.ThetaDir, 'XTick', ceil(xl(1)/(2*st))*2*st:2*st:xl(2), 'YTick', ceil(yl(1)/st)*st:st:yl(2));
                    xlabel(ax, 'Phi (degree)');  ylabel(ax, sprintf('%s (degree)', M.ThetaLabel));
                    if k == 5, zlim(ax, lim);  if ~isempty(ticks), ax.ZTick = ticks; end, zlabel(ax, sprintf('%s (%s)', label, unit), 'Interpreter', 'none'); end
                case 'circular'
                    rLab = 0:30:180;  if V.Elevation, rLab = 90 - rLab; end
                    set(ax, 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', rLab), 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', phiLab));
            end
            if k == 2, ttl = sprintf('%s  |  r=%s, angle=φ', label, M.ThetaLabel); else, ttl = sprintf('%s  |  θ: %s  |  φ: %s', label, app.Single_Switch_ThetaSpan.Value, app.Single_Switch_AngularSpan.Value); end
            title(ax, ttl, 'Interpreter', 'none', 'FontSize', 10);
            % POB marker: index of the selected-component peak, re-indexed through the display permutation
            [i, j] = ind2sub(size(E.Derived.Cols.(V.Component)), app.PeakSel.index);  li = sub2ind(size(C), i, find(M.ColIdx == j, 1));
            if s.IsPolar, set(s.Marker, 'ThetaData', X(li), 'RData', Y(li)); else, set(s.Marker, 'XData', X(li), 'YData', Y(li), 'ZData', Z(li)); end
            s.Marker.DataTipTemplate.DataTipRows = [dataTipTextRow(M.ThetaLabel, M.ThetaGrid(li), '%.3g°'); dataTipTextRow("Phi", M.PhiGrid(li), '%.3g°'); dataTipTextRow(tex, C(li), fmt)];
            if isempty(s.Tip) || ~isgraphics(s.Tip), drawnow limitrate;  s.Tip = datatip(s.Marker, 'DataIndex', 1, 'FontSize', 9, 'Tag', 'APAT'); end
            s.Key = key;  app.Gfx.Full(k) = s;  app.renderOverlay(k);
        end

        function renderOverlay(app, k)
            % Cut overlay on the two spatial 3-D views, fed by the shared cut extract.
            s = app.Gfx.Full(k);  K = app.CutK;
            if k < 3 || k > 4 || ~isfield(K, 'theta') || ~isgraphics(s.Axes), return; end
            if isempty(s.Overlay) || ~isgraphics(s.Overlay)
                hold(s.Axes, 'on');  s.Overlay = plot3(s.Axes, NaN, NaN, NaN, 'k', 'LineWidth', 1.6, 'HandleVisibility', 'off');  hold(s.Axes, 'off');
            end
            lim = app.Range.full;  if util_colKind(app.View.Component) == "ar", lim = app.ARLimits; end
            if k == 3, r = 1.02; else, r = util_polarRadius(K.y(:, 1), lim) * 1.01; end
            [X, Y, Z] = util_sph(K.theta, K.phi, r);
            set(s.Overlay, 'XData', X, 'YData', Y, 'ZData', Z, 'Visible', app.View.Overlay);  app.Gfx.Full(k) = s;
        end

        function renderCut(app)
            % One geo_cut extract serves the polar cut, the rectangular cut, both 3-D overlays, POB and HPBW.
            E = app.Pats(app.Main);  P = E.Pattern;  D = E.Derived;  V = app.View;
            if P.IsGainOnly
                names = V.Component;  idx = 1;
            else
                names = ["E_Total_dB", D.Pol.pairs.(V.Basis) + "_dB"];  idx = find(V.Traces);  if isempty(idx), idx = 1; end
                names = names(idx);
            end
            value = V.CutValue;  if V.Elevation && V.CutType == "Phi", value = 90 - value; end
            K = geo_cut(P, E.Geometry, cellfun(@(n) D.Cols.(n), cellstr(names), 'UniformOutput', false), V.CutType, value);
            a = K.angle;  if V.SignedPhi, a(a > 180) = a(a > 180) - 360; end
            [a, o] = unique(a);  Y = K.y(o, :);  th = K.theta(o);  ph = K.phi(o);
            if V.SignedPhi && any(a == 180) && ~any(a == -180), r = find(a == 180, 1);  a = [-180; a];  Y = [Y(r, :); Y];  th = [th(r); th];  ph = [ph(r); ph]; end
            K.angle = a;  K.y = Y;  K.theta = th;  K.phi = ph;  K.names = names;  app.CutK = K;
            if K.snapped, app.setStatus(app.Single_StatusBar, sprintf('Requested %s cut @ %s=%g° snapped to nearest %s=%g°', V.CutType, K.symbol, V.CutValue, K.symbol, K.fixed), true); end
            [~, unit, fmt] = app.compInfo(names(1));  lbl = replace(names, "_", "\_");
            pax = app.PaxCut;  ax = app.Single_AxesRect;  lim = app.Range.cut;  xl = [0 360];  if V.SignedPhi, xl = [-180 180]; end
            cla(pax);  cla(ax);  hold(pax, 'on');  hold(ax, 'on');
            hp = polarplot(pax, deg2rad(a), max(Y, lim(1)), 'LineWidth', 1.4);  hr = plot(ax, a, Y, 'LineWidth', 1.4);
            co = ax.ColorOrder(1 + mod(idx - 1, size(ax.ColorOrder, 1)), :);  set(hp, {'Color'}, num2cell(co, 2));  set(hr, {'Color'}, num2cell(co, 2));
            for t = 1:numel(hp)
                rows = [dataTipTextRow("Angle", a, '%.3g°'); dataTipTextRow(lbl(t), Y(:, t), fmt)];
                hp(t).DataTipTemplate.DataTipRows = rows;  hr(t).DataTipTemplate.DataTipRows = rows;
            end
            phiLab = 0:30:330;  if V.SignedPhi, phiLab(phiLab > 180) = phiLab(phiLab > 180) - 360; end
            set(pax, 'ThetaDir', 'clockwise', 'ThetaZeroLocation', 'top', 'RLim', lim, 'RTick', lim(1):5:lim(2), 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', phiLab));
            set(ax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(ax, sprintf('%s (degree)', V.CutType));  ylabel(ax, sprintf('Magnitude (%s)', unit));
            ttl = sprintf('%s cut @ %s = %g°  |  %s', V.CutType, K.symbol, K.fixed, app.compInfo(names(1)));
            title(pax, ttl, 'Interpreter', 'none');  title(ax, ttl, 'Interpreter', 'none');
            % POB of the cut = peak of the first trace
            [pk, ip] = max(Y(:, 1), [], 'omitnan');  app.Gfx.CutPOB = gobjects(1, 0);  app.Gfx.HPBWTips = {gobjects(1, 0), gobjects(1, 0)};
            if isfinite(pk)
                app.Gfx.CutPOB = app.cutMarker(a(ip), pk, 'k', [dataTipTextRow("Angle", a(ip), '%.3g°'); dataTipTextRow(lbl(1), pk, fmt)]);
            end
            app.Label_HPBW.Text = '';
            if V.HPBW && isfinite(pk)
                [bw, lo, hi] = met_hpbw(a, Y(:, 1), pk, a(ip));
                if isfinite(bw)
                    b = mod([lo hi] - xl(1), 360) + xl(1);
                    app.Label_HPBW.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b);
                    if b(1) <= b(2), reg = b; else, reg = [xl(1), b(2); b(1), xl(2)]; end
                    thetaregion(pax, deg2rad(reg(:, 1)), deg2rad(reg(:, 2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    xregion(ax, reg(:, 1), reg(:, 2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    sides = ["Lower", "Upper"];
                    for q = 1:2
                        h = app.cutMarker(b(q), pk - 3, '#D95319', [dataTipTextRow(sides(q) + " HPBW", b(q), '%.2f°'); dataTipTextRow(lbl(1), pk - 3, fmt)]);
                        app.Gfx.HPBWTips{1}(end+1) = h(3);  app.Gfx.HPBWTips{2}(end+1) = h(4);
                    end
                end
            end
            legend(pax, hp, lbl, 'Location', 'southoutside', 'Orientation', 'horizontal');  legend(ax, hr, lbl, 'Location', 'best');
            hold(pax, 'off');  hold(ax, 'off');
            for k = 3:4, app.renderOverlay(k); end
        end

        function h = cutMarker(app, angle, level, color, rows)
            % Marker + pinned datatip on both cut axes: h = [polarMarker, rectMarker, polarTip, rectTip].
            lim = app.Range.cut;
            h = [polarplot(app.PaxCut, deg2rad(angle), max(level, lim(1)), 'o', 'Color', color, 'MarkerFaceColor', color, 'MarkerSize', 5, 'HandleVisibility', 'off'), ...
                 plot(app.Single_AxesRect, angle, level, 'o', 'Color', color, 'MarkerFaceColor', color, 'MarkerSize', 5, 'HandleVisibility', 'off')];
            for m = h, m.DataTipTemplate.DataTipRows = rows; end
            h = [h, datatip(h(1), 'DataIndex', 1, 'FontSize', 9, 'Tag', 'APAT'), datatip(h(2), 'DataIndex', 1, 'FontSize', 9, 'Tag', 'APAT')];
        end

        function applyAnnot(app)
            % Visibility of app-owned annotations only; never creates or computes anything.
            V = app.View;
            for k = 1:5, s = app.Gfx.Full(k);  set([s.Marker, s.Tip], 'Visible', V.POB); end
            if isfield(app.Gfx, 'CutPOB'), set(app.Gfx.CutPOB(isgraphics(app.Gfx.CutPOB)), 'Visible', V.POB); end
            if isfield(app.Gfx, 'HPBWTips')
                tabs = [app.Single_tabPolarPlot, app.Single_tabRectPlot];
                for q = 1:2, set(app.Gfx.HPBWTips{q}(isgraphics(app.Gfx.HPBWTips{q})), 'Visible', V.HPBWTips && app.Single_tabCut.SelectedTab == tabs(q)); end
            end
        end

        function applyCamera(app)
            up = [0 0 1];  def = {[135 25], [135 25], [-35 35]};
            switch app.Single_DropDown_3DView.Value
                case 'top',    cam = [0 90];  up = [0 1 0];
                case 'bottom', cam = [0 -90]; up = [0 1 0];
                case 'right',  cam = [90 0];
                case 'left',   cam = [-90 0];
                case 'front',  cam = [0 0];
                case 'back',   cam = [180 0];
                otherwise,     cam = [];
            end
            for k = 3:5
                ax = app.Gfx.Full(k).Axes;  v = cam;  if isempty(v), v = def{k - 2}; end
                view(ax, v(1), v(2));  camup(ax, up);
            end
        end

        function T = resultsTable(app)
            % Results in the display convention, straight from Derived.Cols (no closing column).
            E = app.Pats(app.Main);  M = app.Map;  n = numel(E.Pattern.Phi);  idx = M.ColIdx(1:n);
            [PH, TH] = meshgrid(M.PhiAxis(1:n), M.ThetaAxis);
            names = fieldnames(E.Derived.Cols)';  keep = names(app.View.OutMask);  data = [TH(:), PH(:)];
            for c = keep, X = E.Derived.Cols.(c{1})(:, idx);  data(:, end+1) = X(:); end %#ok<AGROW>
            T = array2table(data, 'VariableNames', [{'Theta', 'Phi'}, keep]);
        end

        function renderTables(app)
            if app.Main == 0, return; end
            E = app.Pats(app.Main);
            if ~strcmp(app.Gfx.RawKey, E.Path)
                app.Single_Table_DataIn.Data = E.Source.Raw;  app.Single_Table_DataIn.ColumnName = E.Source.Raw.Properties.VariableNames;  app.Gfx.RawKey = E.Path;
            end
            if app.Single_tabData.SelectedTab ~= app.Single_tabDataOut, app.Gfx.OutKey = '';  return; end        % lazy: only when visible
            key = sprintf('%d|%s|%s|%s', E.Pattern.Revision, E.Params.Key, app.Map.Key, char(app.View.OutMask + '0'));
            if strcmp(app.Gfx.OutKey, key), return; end
            app.Single_Table_DataOut.Data = app.resultsTable();  app.Gfx.OutKey = key;
        end

        function renderMetadata(app)
            E = app.Pats(app.Main);  P = E.Pattern;  G = E.Geometry;  D = E.Derived;  K = D.Peak;  m = D.Metrics;  f = @util_fmtNumber;
            [th, ph] = util_peakDir(P, K.index);
            rows = {'Source format', char(P.Meta.Format); 'File', E.Name; 'Level unit', char(P.Meta.UnitLabel)
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', numel(P.Theta)*numel(P.Phi), numel(P.Theta), numel(P.Phi))
                'θ range / step', sprintf('[%s°, %s°] / %s°', f(P.Theta(1)), f(P.Theta(end)), f(P.dTheta))
                'φ range / step', sprintf('[%s°, %s°] / %s°  (%s)', f(P.Phi(1)), f(P.Phi(end)), f(P.dPhi), util_pick(G.PhiPeriodic, 'periodic', 'open'))
                'Native step', sprintf('%s° × %s°', f(P.NativeStep(1)), f(P.NativeStep(2)))
                'Solid angle', sprintf('%s sr  (%s)', f(G.Omega, 4), util_pick(G.IsFullSphere, 'full sphere', 'partial sphere'))};
            if isfinite(P.Freq), rows(end+1, :) = {'Frequency', sprintf('%.4g GHz', P.Freq/1e9)}; end
            if ~P.IsGainOnly
                rows = [rows; {'Polarization', char(D.Pol.label); 'Cut Co-pol / Cross-pol', char(strjoin(D.Pol.pairs.(app.CutFieldBasisDropDown.Value), ' / '))}];
            end
            rows = [rows; {'Peak gain (POB)', sprintf('%s %s', f(K.value), P.Meta.UnitLabel); 'POB direction [θ, φ]', sprintf('[%s°, %s°]', f(th), f(ph))
                'Peak policy', sprintf('spatial isolation > %g dB over 4 neighbours', app.PeakExcessDB)
                'Peak adjusted', sprintf('%s (%d isolated spike(s), raw max %s %s)', util_pick(K.wasAdjusted, 'yes', 'no'), K.spikeCount, f(K.rawValue), P.Meta.UnitLabel)
                'Boresight axis', app.PrincipalAxes.labels{D.Boresight}
                'HPBW E-plane', sprintf('%s°', f(m.HPBW_EPlane_deg)); 'HPBW H-plane', sprintf('%s°', f(m.HPBW_HPlane_deg))
                'Front-to-back', sprintf('%s dB', f(m.FrontBack_dB)); 'Peak directivity', sprintf('%s dBi', f(m.PeakDirectivity_dB))
                'Radiation efficiency', sprintf('%s%%', f(m.Efficiency_pct)); 'AR at peak', sprintf('%s dB', f(m.AxialRatioAtPeak_dB))
                'Parameters', sprintf('L=%g dB, Rx %s (AR %g dB), Pt=%g dBW, R=%g m', E.Params.L, E.Params.RxMode, E.Params.RxAR_dB, E.Params.Pt_dBW, E.Params.R_m)
                'Conventions', 'E_R=(Eθ+jEφ)/√2 (IEEE, e^{+jωt}); AR signed (+RHCP/−LHCP, −100 dB linear); coverage strict ">"'}];
            for n = P.Meta.Notes(:).', rows(end+1, :) = {'Reader note', char(n)}; end %#ok<AGROW>
            app.Single_Table_metadata.Data = rows;
        end

        function renderStatus(app)
            E = app.Pats(app.Main);  P = E.Pattern;  K = app.PeakSel;  [th, ph] = util_peakDir(P, K.index);  [label, unit] = app.compInfo();
            what = 'POB';  if ~strcmp(label, 'Total Gain') && ~P.IsGainOnly, what = ['Peak of ' label]; end
            txt = sprintf('Pattern: <b>%s</b> | %s <b>%s %s</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)', E.Name, what, util_fmtNumber(K.value, 2), unit, util_fmtNumber(th), util_fmtNumber(ph));
            if ~P.IsGainOnly, txt = sprintf('%s | Polarization <b>%s</b>', txt, E.Derived.Pol.label); end
            app.setStatus(app.Single_StatusBar, txt, false);
        end
    end

    %% ---------------------------------------------------------------- export
    methods (Access = private)

        function export(app, what)
            if app.Main == 0 && what ~= "covExport", return; end
            if app.Main > 0, E = app.Pats(app.Main);  [folder, base] = fileparts(E.Path); else, folder = pwd;  base = 'coverage'; end
            filters = {'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'};
            switch what
                case "exportResults", T = app.resultsTable();  name = [base '_APAT_results.csv'];
                case "exportCut",     K = app.CutK;  T = array2table([K.angle, K.y], 'VariableNames', [{'Angle_deg'}, cellstr(K.names)]);  name = [base '_cut.csv'];
                case "covExport",     T = app.Cov_Tabel.Data;  name = 'coverage_results.csv';  if isempty(T), return; end
                case "exportUAN"
                    P = E.Pattern;  s = 10^(E.Params.L/20);  Eth = P.Eth*s;  Eph = P.Eph*s;
                    if E.Geometry.PhiPeriodic, Eth(:, end+1) = Eth(:, 1);  Eph(:, end+1) = Eph(:, 1);  phi = [P.Phi; P.Phi(1) + 360]; else, phi = P.Phi; end
                    [PH, TH] = meshgrid(phi, P.Theta);
                    T = table(TH(:), PH(:), round(20*log10(max(abs(Eth(:)), eps)), 5), round(20*log10(max(abs(Eph(:)), eps)), 5), ...
                        round(rad2deg(angle(Eth(:))), 5), round(rad2deg(angle(Eph(:))), 5), 'VariableNames', {'Theta', 'Phi', 'E_TH_DB', 'E_PH_DB', 'E_TH_DG', 'E_PH_DG'});
                    filters = [{'*.uan', 'XGTD user-defined antenna (*.uan)'}; filters(1:2, :)];
                    name = sprintf('%s_%.5f_%gdeg.uan', base, E.Derived.Peak.value, P.dTheta);
            end
            [f, p] = uiputfile(filters, 'Export', fullfile(folder, name));  if isequal(f, 0), return; end
            out = fullfile(p, f);
            if endsWith(out, '.uan', 'IgnoreCase', true)
                hdr = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                    'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                    min(T.Phi), max(T.Phi), P.dPhi, min(T.Theta), max(T.Theta), P.dTheta, E.Derived.Peak.value);
                writelines(hdr, out);  writetable(T, out, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
            elseif endsWith(out, '.txt', 'IgnoreCase', true), writetable(T, out, 'Delimiter', '\t');
            else, writetable(T, out);
            end
            app.setStatus(app.Single_StatusBar, ['Exported to <b>' out '</b>'], true);
        end
    end

    %% ---------------------------------------------------------------- coverage tab
    methods (Access = private)

        function Q = readCoverageConfig(app)
            % The ONLY reader of Coverage-tab widget values (writes nothing).
            Q.Component = string(app.Cov_DropDown_Component.Value);
            Q.T = cov_thresholds(app.Cov_Spinner_ThreshMin.Value, app.Cov_Spinner_ThreshMax.Value, max(app.Cov_Spinner_Step.Value, 0.1));
            Q.Conical = logical(app.Cov_ButtonGroup_Btn_Conical.Value);
            Q.Cone = [app.Cov_Spinner_ConeTH.Value, mod(app.Cov_Spinner_ConePH.Value, 360), app.Cov_Spinner_ConeAng.Value];
            Q.QueryT = app.Cov_Spinner_queryCov.Value;  Q.QueryC = app.Cov_Spinner_queryThresh.Value;
            Q.TextFormat = string(app.Cov_DropDown_TextFormat.Value);
        end

        function node = covTarget(app)
            % Pattern node to compute on: the selection (or its pattern ancestor), else the most recent pattern node.
            node = [];  n = app.Cov_Tree.SelectedNodes;
            while ~isempty(n) && isa(n(1), 'matlab.ui.container.TreeNode')
                if isstruct(n(1).NodeData) && strcmp(n(1).NodeData.kind, 'pattern'), node = n(1);  return; end
                n = n(1).Parent;
            end
            for c = flip(app.Cov_TreeNode_Results.Children(:)).'
                if strcmp(c.NodeData.kind, 'pattern'), node = c;  return; end
            end
        end

        function node = covNodeFor(app, k)
            node = [];
            for c = app.Cov_TreeNode_Results.Children(:).', if strcmp(c.NodeData.kind, 'pattern') && c.NodeData.k == k, node = c;  return; end, end
        end

        function jobs = covJobs(app, roots)
            % The tree IS the job registry: jobs are the children of pattern/results nodes.
            if nargin < 2, roots = app.Cov_TreeNode_Results.Children; end
            jobs = matlab.ui.container.TreeNode.empty(0, 1);
            for n = roots(:).'
                switch n.NodeData.kind
                    case 'job',  jobs(end+1, 1) = n; %#ok<AGROW>
                    case 'root', jobs = [jobs; app.covJobs(n.Children)]; %#ok<AGROW>
                    otherwise,   jobs = [jobs; n.Children(:)]; %#ok<AGROW>
                end
            end
        end

        function jobs = covChecked(app, roots)
            if nargin < 2, jobs = app.covJobs(); else, jobs = app.covJobs(roots); end
            jobs = jobs(arrayfun(@(n) app.isChecked(n), jobs));
        end

        function tf = isChecked(app, n)
            c = app.Cov_Tree.CheckedNodes;  tf = ~isempty(c) && any(c == n);
        end

        function node = covAddPattern(app, k)
            node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📡 ' app.Pats(k).Name], 'NodeData', struct('kind', 'pattern', 'k', k, 'name', app.Pats(k).Name));
            expand(app.Cov_Tree);  app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node];  app.Cov_Tree.SelectedNodes = node;
        end

        function node = covAddJob(app, parent, T, cov, label, icon)
            % A job is a curve {T, cov}: identical for computed and loaded results.
            app.CovRunID = app.CovRunID + 1;  label = sprintf('R%d %s', app.CovRunID, label);
            h = plot(app.Cov_Axes, T, cov, 'LineWidth', 1.6, 'DisplayName', label);
            h.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", T, '%.2f dB'); dataTipTextRow("Coverage", cov, '%.2f %%')];
            node = uitreenode(parent, 'Text', [icon ' ' label], 'NodeData', struct('kind', 'job', 'id', app.CovRunID, 'label', label, 'T', T(:), 'cov', cov(:), 'Line', h, 'Query', gobjects(1, 0)));
            expand(parent);  app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node];
        end

        function covDelete(app, nodes)
            for n = app.covJobs(nodes).', d = n.NodeData;  delete([d.Line, d.Query(isgraphics(d.Query))]); end
            delete(nodes);
        end

        function covFromMain(app)
            if app.Main == 0, uialert(app.UIFigure, 'Load and process a pattern first.', 'Coverage');  return; end
            app.TabGroup.SelectedTab = app.Tab2_Coverage;  app.Cov_EditField_filePath.Value = app.Pats(app.Main).Path;
            node = app.covNodeFor(app.Main);  if isempty(node), node = app.covAddPattern(app.Main); end
            app.Cov_Tree.SelectedNodes = node;  app.covSync();  app.applyVisibility();
            app.setStatus(app.Cov_StatusBar, sprintf('Pattern "<b>%s</b>" ready — coverage uses its current derivation (L=%g dB).', app.Pats(app.Main).Name, app.Pats(app.Main).Params.L), false);
        end

        function covLoad(app, force)
            % Load a pattern or a coverage-results file on the Coverage tab through the same pat_build → geo_build → pat_derive chain.
            if nargin < 2, force = false; end
            fp = strtrim(app.Cov_EditField_filePath.Value);  k = find(strcmp({app.Pats.Path}, fp), 1);
            if ~force && (isempty(fp) || ~isfile(fp) || ~isempty(k))
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.ffd;*.ffe;*.ffs;*.cut;*.xlsx;*.csv;*.dat;*.txt', 'Pattern / coverage data'; '*.*', 'All files'}, 'Select a pattern or coverage results file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);  k = find(strcmp({app.Pats.Path}, fp), 1);
            end
            if force && ~isfile(fp), return; end
            node = [];  if ~isempty(k), node = app.covNodeFor(k); end
            if ~isempty(node) && ~force
                app.Cov_Tree.SelectedNodes = node;  app.covSelect();  app.setStatus(app.Cov_StatusBar, 'File already loaded — node selected.', true);  return
            end
            app.Dialog = uiprogressdlg(app.UIFigure, 'Title', 'Loading Data', 'Message', 'Reading file...', 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            closer = onCleanup(@() delete(app.Dialog)); 
            Q = app.readCoverageConfig();  S = io_read(fp, Q.TextFormat);  app.perf("Read file");  app.checkCancelled();
            app.Cov_EditField_filePath.Value = fp;
            if S.Meta.IsCoverage, app.covLoadResults(fp, S.Raw);  return; end
            [~, prm] = app.readConfig();  P = pat_build(S, 1);  G = geo_build(P);  D = pat_derive(P, G, prm, app.PrincipalAxes, app.PeakExcessDB);  app.perf("Derive");
            [~, name, ext] = fileparts(fp);
            if isempty(k), k = numel(app.Pats) + 1; end
            app.Pats(k) = struct('Name', [name ext], 'Path', fp, 'Source', S, 'Pattern', P, 'Geometry', G, 'Derived', D, 'Params', prm);   % commit
            if ~isempty(node), app.covDelete(node); end
            app.covAddPattern(k);  app.Gfx.CovK = 0;  app.covSync();  app.covCheck();
            app.setStatus(app.Cov_StatusBar, sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', [name ext]), false);
        end

        function covLoadResults(app, fp, T)
            [~, name] = fileparts(fp);
            node = uitreenode(app.Cov_TreeNode_Results, 'Text', ['📄 ' name], 'NodeData', struct('kind', 'results', 'name', name));
            for c = 2:width(T), app.covAddJob(node, T{:, 1}, T{:, c}, T.Properties.VariableNames{c}, '📈'); end
            app.Cov_Tree.CheckedNodes = [app.Cov_Tree.CheckedNodes; node];  expand(app.Cov_TreeNode_Results);
            app.covCheck();  app.covXAuto();
            app.setStatus(app.Cov_StatusBar, sprintf('Coverage results file "%s" loaded (%d curves).', name, width(T) - 1), false);
        end

        function covSync(app)
            % Keep the coverage component list, threshold preset and Auto orientation aligned with the target pattern node.
            node = app.covTarget();  if isempty(node), return; end
            E = app.Pats(node.NodeData.k);  dd = app.Cov_DropDown_Component;
            [names, labels] = app.componentList(E.Derived.Cols, E.Pattern.IsGainOnly);
            if ~isequal(dd.ItemsData, names), prev = dd.Value;  dd.Items = labels;  dd.ItemsData = names;  if any(strcmp(names, prev)), dd.Value = prev; end, end
            if app.Range.Auto.cov
                C = E.Derived.Cols.(dd.Value);  app.applyRange("cov", -1, util_presetRange(max(C(~E.Derived.Peak.spike), [], 'omitnan')));
            end
            if app.Gfx.CovK ~= node.NodeData.k && app.Cov_DropDown_Orientation.Value == 0, app.covOrient(); end
            app.Gfx.CovK = node.NodeData.k;
        end

        function covOrient(app)
            node = app.covTarget();  idx = app.Cov_DropDown_Orientation.Value;
            if idx == 0, if isempty(node), return; end, idx = app.Pats(node.NodeData.k).Derived.Boresight; end
            A = app.PrincipalAxes;  app.Cov_Spinner_ConeTH.Value = A.theta(idx);  app.Cov_Spinner_ConePH.Value = A.phi(idx);
            app.setStatus(app.Cov_StatusBar, sprintf('Cone centre set to <b>%s</b> (θ=%g°, φ=%g°).', A.labels{idx}, A.theta(idx), A.phi(idx)), true);
        end

        function covRun(app)
            node = app.covTarget();
            if isempty(node), uialert(app.UIFigure, 'Load (or select) an antenna pattern node first.', 'Compute Coverage');  return; end
            k = node.NodeData.k;  E = app.Pats(k);  Q = app.readCoverageConfig();  [~, prm] = app.readConfig();
            if ~strcmp(E.Params.Key, prm.Key)                                     % foreign entries follow the current parameters
                E.Derived = pat_derive(E.Pattern, E.Geometry, prm, app.PrincipalAxes, app.PeakExcessDB);  E.Params = prm;  app.Pats(k) = E;
            end
            C = E.Derived.Cols.(Q.Component);  mask = true(size(C));  region = 'Sph';
            if Q.Conical, mask = cov_coneMask(E.Pattern, Q.Cone(1), Q.Cone(2), Q.Cone(3));  region = sprintf('Con (%s) α=%s°', app.coneLabel(Q.Cone(1), Q.Cone(2)), util_fmtNumber(Q.Cone(3))); end
            cov = cov_curve(C, E.Geometry.dOmega, mask, Q.T);  app.perf("Coverage");
            job = app.covAddJob(node, Q.T, cov, sprintf('%s · %s · L=%g dB', region, Q.Component, prm.L), '📉');
            app.covCheck();  app.covXAuto();  app.Cov_Tree.SelectedNodes = job;  app.covSelect();
            note = '';  if ~any(mask(:) & isfinite(C(:))), note = ' — empty region, coverage ≡ 0'; end
            app.setStatus(app.Cov_StatusBar, sprintf('Run-<b>%d</b> computed: <b>%s</b> on <b>"%s"</b> (%d thresholds%s).', app.CovRunID, job.NodeData.label, E.Name, numel(Q.T), note), false);
        end

        function covXAuto(app)
            if ~app.Range.Auto.covX, return; end
            c = arrayfun(@(n) n.NodeData.T, app.covJobs(), 'UniformOutput', false);  T = vertcat(c{:});
            if ~isempty(T), app.applyRange("covX", -1, [min(T), max(T)]); end
        end

        function label = coneLabel(app, theta, phi)
            A = app.PrincipalAxes;  u = [sind(theta)*cosd(phi), sind(theta)*sind(phi), cosd(theta)];
            i = find([sind(A.theta(:)).*cosd(A.phi(:)), sind(A.theta(:)).*sind(A.phi(:)), cosd(A.theta(:))] * u(:) >= 1 - 1e-9, 1);
            if isempty(i), label = sprintf('θ=%s°, φ=%s°', util_fmtNumber(theta), util_fmtNumber(phi)); else, label = A.labels{i}; end
        end

        function covCheck(app)
            % Check/uncheck = Visible on known handles + table + legend; no numerics.
            for n = app.covJobs().', d = n.NodeData;  set([d.Line, d.Query(isgraphics(d.Query))], 'Visible', app.isChecked(n)); end
            jobs = app.covChecked();
            if isempty(jobs)
                app.Cov_Tabel.Data = table();  legend(app.Cov_Axes, 'off');
            else
                c = arrayfun(@(n) n.NodeData.T, jobs, 'UniformOutput', false);  T = unique(vertcat(c{:}));  data = T;  names = {'Threshold (dB)'};
                for n = jobs.', data(:, end+1) = cov_at(n.NodeData, T);  names{end+1} = sprintf('%s %%', n.NodeData.label); end %#ok<AGROW>
                app.Cov_Tabel.Data = array2table(compose('%.2f', data), 'VariableNames', matlab.lang.makeUniqueStrings(names));
                d = [jobs.NodeData];  legend(app.Cov_Axes, [d.Line], {d.label}, 'Location', 'southwest', 'Interpreter', 'none');
            end
            app.applyVisibility();
        end

        function covSelect(app)
            sel = app.Cov_Tree.SelectedNodes;
            for n = app.covJobs().', n.NodeData.Line.LineWidth = 1.6 + (~isempty(sel) && n == sel(1)); end
            app.covSync();  app.applyVisibility();
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(app.Cov_StatusBar, 'Ready.', false);  return; end
            d = sel(1).NodeData;  f = @util_fmtNumber;
            if ~strcmp(d.kind, 'job')
                app.setStatus(app.Cov_StatusBar, sprintf('%s <b>"%s"</b> — <b>%d</b> coverage job(s).', util_pick(strcmp(d.kind, 'pattern'), 'Pattern', 'Results'), d.name, numel(sel(1).Children)), false);
                return
            end
            shown = round(d.cov, 2);  [mx, i] = max(shown);  i = find(shown == mx, 1, 'last');  t50 = thr_at(d, 50);
            app.setStatus(app.Cov_StatusBar, sprintf('%s | Threshold [%s, %s] dB step %s | 50%%-coverage threshold <b>%s dB</b> | max <b>%s%%</b> @ <b>%s dB</b>', ...
                d.label, f(d.T(1)), f(d.T(end)), f(median(diff(d.T))), f(t50), f(mx), f(d.T(i))), false);
        end

        function covQuery(app, mode)
            % "Coverage at T" = cov_at, "Threshold at c %" = thr_at; one datatip at the coordinate plus two projections.
            Q = app.readCoverageConfig();  sel = app.Cov_Tree.SelectedNodes;  ax = app.Cov_Axes;
            if isempty(sel), app.setStatus(app.Cov_StatusBar, 'Select a node to query.', true);  return; end
            jobs = app.covChecked(sel(1));  hit = false;
            for n = jobs.'
                d = n.NodeData;  delete(d.Query(isgraphics(d.Query)));  d.Query = gobjects(1, 0);
                if mode == "cov", x = Q.QueryT;  y = cov_at(d, x); else, y = Q.QueryC;  x = thr_at(d, y); end
                if isfinite(x) && isfinite(y)
                    c = d.Line.Color;
                    d.Query = [line(ax, [x x], [ax.YLim(1) y], 'Color', c, 'LineStyle', ':', 'HandleVisibility', 'off'), ...
                               line(ax, [ax.XLim(1) x], [y y], 'Color', c, 'LineStyle', ':', 'HandleVisibility', 'off'), ...
                               datatip(d.Line, x, y, 'SnapToDataVertex', 'off', 'FontSize', 9, 'Tag', 'APAT')];
                    hit = true;
                end
                n.NodeData = d;
            end
            if hit, msg = sprintf('Queried %s.', util_pick(mode == "cov", sprintf('coverage at %s dB', util_fmtNumber(Q.QueryT)), sprintf('threshold at %s%% coverage', util_fmtNumber(Q.QueryC))));
            else,   msg = 'Query value is outside the range of the selected checked results.'; end
            app.setStatus(app.Cov_StatusBar, msg, ~hit);
        end

        function covClear(app)
            % The one permitted findobj: user-created datatips are not app-owned.
            sel = app.Cov_Tree.SelectedNodes;  jobs = [];  if ~isempty(sel), jobs = app.covJobs(sel(1)); end
            if isempty(jobs), app.setStatus(app.Cov_StatusBar, 'Select a node with coverage results to clear.', true);  return; end
            for n = jobs.', d = n.NodeData;  delete(d.Query(isgraphics(d.Query)));  d.Query = gobjects(1, 0);  n.NodeData = d;  delete(findobj(d.Line, 'Type', 'datatip')); end
            app.setStatus(app.Cov_StatusBar, 'Selected DataTips and query markers cleared.', true);
        end

        function covReset(app)
            app.covDelete(app.Cov_TreeNode_Results.Children);
            cla(app.Cov_Axes);  legend(app.Cov_Axes, 'off');  hold(app.Cov_Axes, 'on');  grid(app.Cov_Axes, 'on');  ylim(app.Cov_Axes, [0 100]);
            app.Cov_Tabel.Data = table();  app.CovRunID = 0;  app.Gfx.CovK = 0;
            keep = false(size(app.Pats));  if app.Main > 0, keep(app.Main) = true; end
            app.Pats = app.Pats(keep);  app.Main = double(app.Main > 0);                       % drop entries no longer referenced
            app.Range.Auto.cov = true;  app.Range.Auto.covX = true;  app.applyRange("covX", -1, [-40 10]);  app.Cov_Axes.XLimMode = 'auto';
            app.applyVisibility();  app.setStatus(app.Cov_StatusBar, 'Coverage workspace reset 🔄', true);
        end
    end

    %% ---------------------------------------------------------------- lifecycle
    methods (Access = private)

        function startupFcn(app)
            app.PaxCut = polaraxes(app.Single_Grid_Polar);  app.PaxCut.Layout.Row = [1 4];  app.PaxCut.Layout.Column = 3;
            app.PaxPattern = polaraxes(app.Single_gridCircular);  app.PaxPattern.Layout.Row = [1 3];  app.PaxPattern.Layout.Column = 2;
            set([app.PaxCut, app.PaxPattern], 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            app.Gfx.Menu = uicontextmenu(app.UIFigure);
            uimenu(app.Gfx.Menu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~, ~) delete(findobj(app.UIFigure, 'Type', 'datatip', 'Tag', '')));
            axesList = {app.Single_Axes_Ctr, app.PaxPattern, app.Single_Axes_3dSph, app.Single_Axes_3dPol, app.Single_Axes_3dRect};
            for k = 1:5
                ax = axesList{k};  ax.ContextMenu = app.Gfx.Menu;
                app.Gfx.Full(k) = struct('Axes', ax, 'Surface', gobjects(0), 'Marker', gobjects(0), 'Tip', gobjects(0), 'Overlay', gobjects(0), 'Colorbar', colorbar(ax), 'Key', '', 'IsPolar', k == 2);
                if k == 2, enableDefaultInteractivity(ax);
                elseif k >= 3, ax.Interactions = [rotateInteraction, dataTipInteraction];
                else, ax.Interactions = [zoomInteraction, dataTipInteraction];  view(ax, 2);  daspect(ax, [1 1 1]); end
                if k == 3 || k == 4
                    set(ax, 'Projection', 'orthographic', 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1]);
                    axis(ax, 'off');  app.drawTriad(ax);
                end
            end
            app.Gfx.RawKey = '';  app.Gfx.OutKey = '';  app.Gfx.CovK = 0;
            app.StatusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3);
            app.Single_StatusBar.Tag = 'Main';  app.Cov_StatusBar.Tag = 'Cov';
            app.Status = struct('Main', 'Ready -- load an antenna pattern file to begin 🚀', 'Cov', 'Ready 🚀');
            app.Single_StatusBar.Text = app.Status.Main;  app.Cov_StatusBar.Text = app.Status.Cov;
            app.Defaults = {app.Single_Spinner_Loss.Value, app.Single_DropDown_RxPol.Value, app.Single_Spinner_Rw.Value, app.Single_Spinner_Pt.Value, ...
                app.Single_DropDown_Pt.Value, app.Single_Spinner_R.Value, app.Single_DropDown_R.Value};
            hold(app.Cov_Axes, 'on');  grid(app.Cov_Axes, 'on');  ylim(app.Cov_Axes, [0 100]);  set(app.Cov_Axes, 'Box', 'on', 'Layer', 'top', 'Interactions', dataTipInteraction);
            for g = ["full", "cut", "cov", "covX"], app.applyRange(g, -1, [-40 10]); end
            app.applyVisibility();
        end

        function drawTriad(~, ax)
            colors = {[0.85 0.10 0.10], [0.10 0.60 0.10], [0.10 0.20 0.90]};  labels = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'};
            hold(ax, 'on');
            for a = 1:3
                d = 1.35 * double((1:3) == a);
                quiver3(ax, 0, 0, 0, d(1), d(2), d(3), 0, 'Color', colors{a}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25, 'HandleVisibility', 'off');
                text(ax, 1.12*d(1), 1.12*d(2), 1.12*d(3), labels{a}, 'Color', colors{a}, 'FontWeight', 'bold');
            end
            hold(ax, 'off');
        end

        function shutdown(app)
            if app.isClosing, return; end
            app.isClosing = true;
            if isa(app.StatusTimer, 'timer') && isvalid(app.StatusTimer), stop(app.StatusTimer);  delete(app.StatusTimer); end
            if ~isempty(app.Dialog) && isvalid(app.Dialog), delete(app.Dialog); end
            if isgraphics(app.UIFigure), delete(app.UIFigure); end
        end
    end

    %% ---------------------------------------------------------------- layout (declarative; same widgets, names, rows and columns as M7)
    methods (Access = private)

        function h = place(~, ctor, parent, row, col, varargin)
            h = ctor(parent, varargin{:});  h.Layout.Row = row;  h.Layout.Column = col;
        end

        function [lbl, h] = labelled(app, parent, text, row, col, ctor, varargin)
            lbl = app.place(@uilabel, parent, row, col, 'Text', text, 'HorizontalAlignment', 'right');
            h = app.place(ctor, parent, row, col(end) + 1, varargin{:});
        end

        function [tab, g, ax, sl, mn, mx] = patternTab(app, group, title, axesTitle)
            tab = uitab(group, 'Title', title);  g = uigridlayout(tab, 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', '1x', 'fit'});  ax = [];
            if ~isempty(axesTitle), ax = app.place(@uiaxes, g, [1 3], 2);  ax.Title.String = axesTitle;  ax.Box = 'on'; end
            sl = app.place(@(p, varargin) uislider(p, 'range', varargin{:}), g, 2, 1, 'Limits', app.Hard, 'Value', app.Hard, 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s, ~) app.on("range", "full", 3, s.Value));
            mx = app.place(@uispinner, g, 1, 1, 'Limits', app.Hard, 'Value', 100, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.on("range", "full", 2, s.Value));
            mn = app.place(@uispinner, g, 3, 1, 'Limits', app.Hard, 'Value', -250, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.on("range", "full", 1, s.Value));
        end

        function createComponents(app)
            push = @(p, varargin) uibutton(p, 'push', varargin{:});  sw = @(p, varargin) uiswitch(p, 'slider', varargin{:});  H = app.Hard;
            fmtItems = {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', '4: POL1=RCP, POL2=LCP — dB magnitude, phase', ...
                '5: POL1=LCP, POL2=RCP — dB magnitude, phase', '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'};
            fmtData = {'gain', 'linear_magphase', 'linear_reim', 'rcp_lcp_magphase', 'lcp_rcp_magphase', 'rcp_lcp_reim', 'lcp_rcp_reim'};
            app.UIFigure = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.ReleaseName], 'Visible', 'off', 'Position', [100 100 1136 739], 'WindowState', 'maximized', 'CloseRequestFcn', @(~, ~) app.closeRequest());
            app.GridLayout = uigridlayout(app.UIFigure, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.TabGroup = app.place(@uitabgroup, app.GridLayout, 1, 1);
            %% ---- Main tab
            app.Tab1_Single = uitab(app.TabGroup, 'Title', 'Process Pattern 📡');
            app.Single_Grid = uigridlayout(app.Tab1_Single, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'fit', '2x', 'fit', '1x', 'fit'});
            app.Single_Panel_fullPattern = app.place(@uipanel, app.Single_Grid, [2 3], [1 6], 'Title', 'Full Antenna Pattern', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'BackgroundColor', [0.9412 0.9412 0.9412]);
            app.Single_gridPanel_full = uigridlayout(app.Single_Panel_fullPattern, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_tabPlots = app.place(@uitabgroup, app.Single_gridPanel_full, 1, 1, 'SelectionChangedFcn', @(~, ~) app.on("annot"));
            [app.Single_tabContour, app.Single_gridContour, app.Single_Axes_Ctr, app.Range_Ctr, app.Range_Ctr_Min, app.Range_Ctr_Max] = app.patternTab(app.Single_tabPlots, 'Contour Plot', 'Antenna Gain Pattern');
            [app.Single_tabCircular, app.Single_gridCircular, ~, app.Range_Cir, app.Range_Cir_Min, app.Range_Cir_Max] = app.patternTab(app.Single_tabPlots, 'Circular Contour Plot', '');
            [app.Single_tab3DSpherical, app.Single_grid3dSpherical, app.Single_Axes_3dSph, app.Range_3dSph, app.Range_3dSph_Min, app.Range_3dSph_Max] = app.patternTab(app.Single_tabPlots, '3D Spherical Plot', '3D Spherical Plot');
            [app.Single_tab3DPolar, app.Single_grid3dPolar, app.Single_Axes_3dPol, app.Range_3dPol, app.Range_3dPol_Min, app.Range_3dPol_Max] = app.patternTab(app.Single_tabPlots, '3D Polar Plot', '3D Polar Plot');
            [app.Single_tab3DRect, app.Single_grid3dRect, app.Single_Axes_3dRect, app.Range_3dRect, app.Range_3dRect_Min, app.Range_3dRect_Max] = app.patternTab(app.Single_tabPlots, '3D Surface Plot', '3D Surface (Rectangular) Plot');
            app.Single_Panel_Rect = app.place(@uipanel, app.Single_Grid, [2 3], [7 12], 'Title', 'Antenna Pattern Cut', 'TitlePosition', 'centertop', 'FontWeight', 'bold', 'BackgroundColor', [0.9412 0.9412 0.9412]);
            app.Single_gridPanel_Cut = uigridlayout(app.Single_Panel_Rect, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_tabCut = app.place(@uitabgroup, app.Single_gridPanel_Cut, 1, 1, 'SelectionChangedFcn', @(~, ~) app.on("annot"));
            app.Single_tabPolarPlot = uitab(app.Single_tabCut, 'Title', 'Polar Cut Plot');
            app.Single_Grid_Polar = uigridlayout(app.Single_tabPolarPlot, 'ColumnWidth', {'fit', '0.26x', '1x', '0.23x'}, 'RowHeight', {'fit', '0.25x', '1x', 'fit'});
            g = app.Single_Grid_Polar;
            app.Range_Cut = app.place(@(p, varargin) uislider(p, 'range', varargin{:}), g, [2 3], 1, 'Limits', H, 'Value', H, 'Orientation', 'vertical', 'Step', 1, 'ValueChangedFcn', @(s, ~) app.on("range", "cut", 3, s.Value));
            app.Range_Cut_Max = app.place(@uispinner, g, 1, 1, 'Limits', H, 'Value', 100, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.on("range", "cut", 2, s.Value));
            app.Range_Cut_Min = app.place(@uispinner, g, 4, 1, 'Limits', H, 'Value', -250, 'Step', 5, 'ValueChangedFcn', @(s, ~) app.on("range", "cut", 1, s.Value));
            app.Button_HPBW = app.place(@(p, varargin) uibutton(p, 'state', varargin{:}), g, 1, 4, 'Text', 'HPBW', 'FontWeight', 'bold', 'ValueChangedFcn', @(~, ~) app.on("cut"));
            app.Label_HPBW = app.place(@uilabel, g, 2, 4, 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            app.Button_ExportCut = app.place(push, g, 4, 4, 'Text', 'Export Cut', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.on("exportCut"));
            app.Single_gridEcut = app.place(@uigridlayout, g, 3, 4, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x', '1x', '1x'});
            app.CheckBox_Et = app.place(@uicheckbox, app.Single_gridEcut, 1, 1, 'Text', 'E_Total', 'Value', true, 'ValueChangedFcn', @(~, ~) app.on("cut"));
            app.CheckBox_Er = app.place(@uicheckbox, app.Single_gridEcut, 2, 1, 'Text', 'E_RCP', 'Value', true, 'ValueChangedFcn', @(~, ~) app.on("cut"));
            app.CheckBox_El = app.place(@uicheckbox, app.Single_gridEcut, 3, 1, 'Text', 'E_LCP', 'Value', true, 'ValueChangedFcn', @(~, ~) app.on("cut"));
            app.Single_tabRectPlot = uitab(app.Single_tabCut, 'Title', 'Rectangular Cut Plot');
            app.Single_gridRect = uigridlayout(app.Single_tabRectPlot);
            app.Single_AxesRect = app.place(@uiaxes, app.Single_gridRect, [1 2], [1 2], 'XLim', [0 180], 'Box', 'on');
            xlabel(app.Single_AxesRect, 'Theta (degree)');  ylabel(app.Single_AxesRect, 'Magnitude (dB)');
            app.Single_DropDown_output = app.place(@uidropdown, app.Single_Grid, 3, [13 14], 'Items', {'--- column filter ---'}, 'ItemsData', 0, 'ValueChangedFcn', @(~, ~) app.on("filter"));
            app.Single_tabData = app.place(@uitabgroup, app.Single_Grid, 4, [1 14], 'SelectionChangedFcn', @(~, ~) app.on("tables"));
            app.Single_tabDataOut = uitab(app.Single_tabData, 'Title', 'Results 📤');  app.Single_gridDataOut = uigridlayout(app.Single_tabDataOut, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_DataOut = app.place(@uitable, app.Single_gridDataOut, 1, 1, 'ColumnWidth', '1x', 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true);
            app.Single_tabDataIn = uitab(app.Single_tabData, 'Title', 'Input 📥');  app.Single_gridDataIn = uigridlayout(app.Single_tabDataIn, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_DataIn = app.place(@uitable, app.Single_gridDataIn, 1, 1, 'ColumnWidth', '1x', 'ColumnRearrangeable', 'on', 'RowName', 'numbered', 'ColumnSortable', true);
            app.MetadataTab = uitab(app.Single_tabData, 'Title', 'Metadata 📋');  app.Single_gridMetadata = uigridlayout(app.MetadataTab, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            app.Single_Table_metadata = app.place(@uitable, app.Single_gridMetadata, 1, 1, 'ColumnName', {'Property', 'Value'}, 'ColumnWidth', {200, 'auto'}, 'RowName', {});
            % plot control panel
            app.Single_Panel_plotControl = app.place(@uipanel, app.Single_Grid, 2, [13 14], 'Title', 'Plot Control 🎨');
            g = uigridlayout(app.Single_Panel_plotControl, 'RowHeight', repmat({'fit'}, 1, 15));  app.Single_gridPanel_Ctrl = g;
            [app.ComponentLabel, app.Single_DropDown_Component] = app.labelled(g, 'Component', 1, 1, @uidropdown, 'Items', app.Cols(1:8, 2)', 'ItemsData', app.Cols(1:8, 1)', 'Value', 'E_Total_dB', 'ValueChangedFcn', @(~, ~) app.on("component"));
            [app.CuttypeDropDownLabel, app.Single_DropDown_cutType] = app.labelled(g, 'Cut type', 2, 1, @uidropdown, 'Items', {'Phi', 'Theta'}, 'Value', 'Phi', 'ValueChangedFcn', @(~, ~) app.on("cutType"));
            [app.CutvalueSpinnerLabel, app.Single_DropDown_cutValue] = app.labelled(g, 'Cut value', 3, 1, @uispinner, 'Limits', [0 360], 'Value', 0, 'ValueChangedFcn', @(~, ~) app.on("cut"));
            [app.CutFieldsLabel, app.CutFieldBasisDropDown] = app.labelled(g, 'Cut fields', 4, 1, @uidropdown, 'Items', {'Circular: RCP/LCP', 'Linear: Etheta/Ephi'}, 'ItemsData', {'Circular', 'Linear'}, 'Value', 'Circular', 'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.on("basis"));
            applyAll = @(~, ~) app.on("range", "all", 0, [app.Single_Plot_Cmin.Value, app.Single_Plot_Cmax.Value]);
            [app.ColorbarmaxLabel, app.Single_Plot_Cmax] = app.labelled(g, 'Colorbar max', 5, 1, @uispinner, 'Limits', H, 'Value', 10, 'ValueChangedFcn', applyAll);
            [app.ColorbarminLabel, app.Single_Plot_Cmin] = app.labelled(g, 'Colorbar min', 6, 1, @uispinner, 'Limits', H, 'Value', -40, 'ValueChangedFcn', applyAll);
            [app.ColorbarstepLabel, app.Single_Plot_Cstep] = app.labelled(g, 'Colorbar step', 7, 1, @uispinner, 'Limits', [0.1 100], 'Value', 5, 'ValueChangedFcn', @(~, ~) app.on("cstep"));
            [app.Single_Label_Clim, app.Single_Button_Clim] = app.labelled(g, 'Adjust Colorbar', 8, 1, push, 'Text', 'Apply', 'Tooltip', 'Apply to full-pattern and cut plots.', 'ButtonPushedFcn', applyAll);
            [app.View3DLabel, app.Single_DropDown_3DView] = app.labelled(g, '3D view', 9, 1, @uidropdown, 'Items', {'Isometric', 'Top (+Z)', 'Bottom (-Z)', 'Right (+X)', 'Left (-X)', 'Front (-Y)', 'Back (+Y)'}, ...
                'ItemsData', {'iso', 'top', 'bottom', 'right', 'left', 'front', 'back'}, 'Value', 'iso', 'Tooltip', 'Camera direction for the 3D pattern tabs.', 'ValueChangedFcn', @(~, ~) app.on("camera"));
            pad = @(n) repmat(char(160), 1, n);
            app.Single_Switch_AngularSpan = app.place(sw, g, 10, [1 2], 'Items', {['φ span: 0° to 360°' pad(3)], '−180° to 180°'}, 'ItemsData', {'0° to 360°', '-180° to 180°'}, 'Value', '0° to 360°', 'ValueChangedFcn', @(~, ~) app.on("span"));
            app.Single_Switch_ThetaSpan = app.place(sw, g, 11, [1 2], 'Items', {'θ span: 0° to 180°', ['−90° to 90°' pad(2)]}, 'ItemsData', {'0° to 180°', '-90° to 90°'}, 'Value', '0° to 180°', 'ValueChangedFcn', @(~, ~) app.on("span"));
            app.Single_Switch_EHplane = app.place(sw, g, 12, [1 2], 'Items', {[pad(8) 'E-Plane cut'], 'H-Plane cut'}, 'ItemsData', {'E-Plane cut', 'H-Plane cut'}, 'Value', 'E-Plane cut', 'ValueChangedFcn', @(~, ~) app.on("plane"));
            app.Singel_CheckBox_overlayCut = app.place(@uicheckbox, g, 13, [1 2], 'Text', 'Overlay Cut on 3D Plot', 'ValueChangedFcn', @(~, ~) app.on("cut"));
            app.Single_CheckBox_POB = app.place(@uicheckbox, g, 14, [1 2], 'Text', 'Annotate POB', 'ValueChangedFcn', @(~, ~) app.on("annot"));
            app.Single_CheckBox_HPBWBounds = app.place(@uicheckbox, g, 15, [1 2], 'Text', 'Annotate HPBW Bounds', 'ValueChangedFcn', @(~, ~) app.on("annot"));
            app.Single_StatusBar = app.place(@uilabel, app.Single_Grid, 5, [1 14], 'Interpreter', 'html', 'Text', 'Ready 🚀');
            % inputs & parameters panel
            app.Single_panelParam = app.place(@uipanel, app.Single_Grid, 1, [1 14], 'Title', 'Inputs & Parameters 🎛️');
            g = uigridlayout(app.Single_panelParam, 'ColumnWidth', repmat({'1x'}, 1, 14), 'RowHeight', {'1x', '1x', '1x'});  app.Single_gridPanel_Param = g;
            [app.InputPatternLabel, app.Single_EditField_Path] = app.labelled(g, 'Input Pattern:', 1, 1, @uieditfield);  app.Single_EditField_Path.Layout.Column = [2 8];
            [app.FFDFreqDropDownLabel, app.Single_DropDown_FFD] = app.labelled(g, 'FFD Freq:', 1, 9, @uidropdown, 'Items', {'Frequencies'}, 'ValueChangedFcn', @(~, ~) app.on("freq"));
            app.Single_Button_Load = app.place(push, g, 1, [11 12], 'Text', '📂 Load File', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.on("source"));
            app.Single_Button_Process = app.place(push, g, 1, [13 14], 'Text', '⚙️ Process', 'ButtonPushedFcn', @(~, ~) app.on("params"));
            app.Single_Button_ResetParams = app.place(push, g, 2, [1 3], 'Text', 'Reset Params', 'ButtonPushedFcn', @(~, ~) app.on("reset"));
            [app.TextFormatLabel, app.Single_DropDown_TextFormat] = app.labelled(g, 'Format:', 2, [4 5], @uidropdown, 'Items', fmtItems, 'ItemsData', fmtData, 'Value', 'gain', ...
                'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', 'ValueChangedFcn', @(~, ~) app.on("source", app.Single_EditField_Path.Value));
            app.Single_DropDown_TextFormat.Layout.Column = [6 8];
            app.Single_DropDown_step = app.place(@uidropdown, g, 2, [9 10], 'Items', {'STEP'}, 'Placeholder', 'STEP', 'ValueChangedFcn', @(~, ~) app.on("step"));
            app.Single_Export_Output = app.place(push, g, 2, [11 12], 'Text', '💾 Export Results', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.on("exportResults"));
            app.Single_Export_UAN = app.place(push, g, 2, [13 14], 'Text', '💾 Export UAN', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.on("exportUAN"));
            [app.RxPolLabel, app.Single_DropDown_RxPol] = app.labelled(g, 'Rw Sense', 3, 1, @uidropdown, 'Items', {'Auto', 'RHCP', 'LHCP'}, 'Value', 'Auto', 'Editable', 'on');
            [app.IncidentWaveARRwPLFLabel, app.Single_Spinner_Rw] = app.labelled(g, 'Rw (dB)', 3, 3, @uispinner, 'Value', 6);
            [app.LossindBLabel, app.Single_Spinner_Loss] = app.labelled(g, 'Loss (−) / Gain (+) dB', 3, 5, @uispinner, 'Step', 0.1);
            [app.TransmitPowerLabel, app.Single_Spinner_Pt] = app.labelled(g, 'Tx Pwr (Pt)', 3, 7, @uispinner, 'Value', 0);
            app.Single_DropDown_Pt = app.place(@uidropdown, g, 3, 9, 'Items', {'dBW', 'dBm', 'Watts'}, 'Value', 'dBW');
            [app.DistanceLabel, app.Single_Spinner_R] = app.labelled(g, 'Distance', 3, 10, @uispinner, 'Value', 1);
            app.Single_DropDown_R = app.place(@uidropdown, g, 3, 12, 'Items', {'m', 'km'}, 'Value', 'm');
            app.Single_Button_Coverage = app.place(push, g, 3, [13 14], 'Text', '📉 Coverage ▶', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.on("covFromMain"));
            %% ---- Coverage tab
            app.Tab2_Coverage = uitab(app.TabGroup, 'Title', 'Compute Coverage 📈');
            app.Cov_Grid = uigridlayout(app.Tab2_Coverage, 'ColumnWidth', {'0.75x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'0.25x', '1x', 'fit'});
            app.Cov_Panel_Param = app.place(@uipanel, app.Cov_Grid, 1, [1 5], 'Title', 'Inputs & Parameters 🎛️');
            g = uigridlayout(app.Cov_Panel_Param, 'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, 9)], 'RowHeight', {'1x', 'fit', 'fit', 'fit'});  app.Cov_gridPanel_Parm = g;
            app.Cov_ButtonGroup_CovType = app.place(@uibuttongroup, g, [1 2], [1 2], 'Title', 'Coverage Type', 'SelectionChangedFcn', @(~, ~) app.on("covType"));
            app.Cov_ButtonGroup_Btn_Spherical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Spherical 🌐', 'Position', [11 63 91 22], 'Value', true);
            app.Cov_ButtonGroup_Btn_Conical = uiradiobutton(app.Cov_ButtonGroup_CovType, 'Text', 'Conical 🔻', 'Position', [11 41 82 22]);
            [app.Cov_DropDown_OrientationLabel, app.Cov_DropDown_Orientation] = app.labelled(g, 'Orientation 🧭:', 3, 1, @uidropdown, 'Items', [{'Auto'}, app.PrincipalAxes.labels], 'ItemsData', 0:6, 'Value', 0, 'ValueChangedFcn', @(~, ~) app.on("covOrient"));
            [app.AntennaPatternEditFieldLabel, app.Cov_EditField_filePath] = app.labelled(g, 'Antenna Pattern:', 1, 3, @uieditfield);  app.Cov_EditField_filePath.Layout.Column = [4 8];
            app.Cov_Button_Load = app.place(push, g, 1, 9, 'Text', '📂 Load File', 'ButtonPushedFcn', @(~, ~) app.on("covLoad"));
            app.Cov_Button_computeCov = app.place(push, g, 1, 10, 'Text', '⚙️ Compute Coverage', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.on("covRun"));
            app.Cov_Button_Reset = app.place(push, g, 2, 9, 'Text', '🔄 Reset', 'ButtonPushedFcn', @(~, ~) app.on("covReset"));
            app.Cov_Button_Export = app.place(push, g, 2, 10, 'Text', '💾 Export Results', 'ButtonPushedFcn', @(~, ~) app.on("covExport"));
            [app.ThresholdMindBSpinnerLabel, app.Cov_Spinner_ThreshMin] = app.labelled(g, 'Threshold  Min (dB):', 2, 3, @uispinner, 'Value', -40, 'ValueChangedFcn', @(s, ~) app.on("range", "cov", 1, s.Value));
            [app.ThresholdMaxdBSpinnerLabel, app.Cov_Spinner_ThreshMax] = app.labelled(g, 'Threshold  Max (dB):', 2, 5, @uispinner, 'Value', 10, 'ValueChangedFcn', @(s, ~) app.on("range", "cov", 2, s.Value));
            [app.StepdBSpinnerLabel, app.Cov_Spinner_Step] = app.labelled(g, 'Step (dB):', 2, 7, @uispinner, 'Value', 1, 'Limits', [0.01 50], 'ValueChangedFcn', @(~, ~) app.on("covRange"));
            [app.ConeSpinnerLabel, app.Cov_Spinner_ConeTH] = app.labelled(g, 'Cone θ₀ (°):', 3, 3, @uispinner, 'Limits', [0 180]);
            [app.ConeLabel, app.Cov_Spinner_ConePH] = app.labelled(g, 'Cone φ₀ (°):', 3, 5, @uispinner, 'Limits', [0 360]);
            [app.ConeAngleLabel, app.Cov_Spinner_ConeAng] = app.labelled(g, 'Cone Angle α (°):', 3, 7, @uispinner, 'Limits', [0 180], 'Value', 45);
            app.Cov_Button_Clear = app.place(push, g, 3, 9, 'Text', '🧹 Clear DataTips', 'ButtonPushedFcn', @(~, ~) app.on("covClear"));
            app.Cov_Button_toMain = app.place(push, g, 3, 10, 'Text', '📊 To Main ◀ ', 'ButtonPushedFcn', @(~, ~) set(app.TabGroup, 'SelectedTab', app.Tab1_Single));
            [app.Cov_DropDown_ComponentLabel, app.Cov_DropDown_Component] = app.labelled(g, 'Component:', 4, 1, @uidropdown, 'Items', {'Total Gain'}, 'ItemsData', {'E_Total_dB'}, 'ValueChangedFcn', @(~, ~) app.on("covComp"));
            [app.Cov_QueryCoverageLabel, app.Cov_Spinner_queryCov] = app.labelled(g, 'Coverage @ dB:', 4, 3, @uispinner, 'ValueDisplayFormat', '%g dB');
            app.Cov_Button_queryCov = app.place(push, g, 4, 5, 'Text', '⯐ Query Coverage', 'ButtonPushedFcn', @(~, ~) app.on("covQuery", "cov"));
            [app.Cov_QueryThresholdLabel, app.Cov_Spinner_queryThresh] = app.labelled(g, 'Threshold @ %:', 4, 6, @uispinner, 'ValueDisplayFormat', '%g%%', 'Value', 50);
            app.Cov_Button_queryThresh = app.place(push, g, 4, 8, 'Text', '🔍︎ Query Threshold', 'ButtonPushedFcn', @(~, ~) app.on("covQuery", "thr"));
            [app.Cov_TextFormatLabel, app.Cov_DropDown_TextFormat] = app.labelled(g, 'Format:', 4, 9, @uidropdown, 'Items', fmtItems, 'ItemsData', fmtData, 'Value', 'gain', 'ValueChangedFcn', @(~, ~) app.on("covLoad", true));
            app.Cov_StatusBar = app.place(@uilabel, app.Cov_Grid, 3, [1 5], 'Interpreter', 'html', 'Text', 'Ready 🚀');
            app.Cov_Panel_Results = app.place(@uipanel, app.Cov_Grid, 2, [1 5], 'Title', 'Results');
            app.GridLayout2 = uigridlayout(app.Cov_Panel_Results, 'ColumnWidth', {'1x', 'fit', '1x', 'fit', '1x'}, 'RowHeight', {'1x', 'fit'});  g = app.GridLayout2;
            app.Cov_Axes = app.place(@uiaxes, g, 1, [2 4]);
            title(app.Cov_Axes, 'Coverage(T) = 100·Ω_R(G > T) / Ω_R', 'Interpreter', 'none');  xlabel(app.Cov_Axes, 'Threshold (dB)');  ylabel(app.Cov_Axes, 'Coverage (%)');
            app.Cov_Tree = app.place(@(p, varargin) uitree(p, 'checkbox', varargin{:}), g, [1 2], 1, 'SelectionChangedFcn', @(~, ~) app.on("covSelect"), 'CheckedNodesChangedFcn', @(~, ~) app.on("covCheck"));
            app.Cov_TreeNode_Results = uitreenode(app.Cov_Tree, 'Text', 'Coverage Results', 'NodeData', struct('kind', 'root'));
            app.Cov_Tabel = app.place(@uitable, g, [1 2], 5, 'ColumnWidth', '1x', 'RowName', {});
            xr = @(~, e) app.on("range", "covX", 3, e.Value);
            app.Cov_Spinner_XRange = app.place(@(p, varargin) uislider(p, 'range', varargin{:}), g, 2, 3, 'Limits', H, 'Value', [-40 10], 'ValueChangedFcn', xr, 'ValueChangingFcn', xr);
            app.Cov_Spinner_XMax = app.place(@uispinner, g, 2, 4, 'Limits', H, 'Value', 10, 'ValueChangedFcn', @(s, ~) app.on("range", "covX", 2, s.Value));
            app.Cov_Spinner_XMin = app.place(@uispinner, g, 2, 2, 'Limits', H, 'Value', -40, 'ValueChangedFcn', @(s, ~) app.on("range", "covX", 1, s.Value));
            app.UIFigure.Visible = 'on';
        end
    end

    methods (Access = public)
        function app = APAT_v3_M8_2
            createComponents(app);  registerApp(app, app.UIFigure);  runStartupFcn(app, @startupFcn);
            if nargout == 0, clear app; end
        end
        function closeRequest(app, ~), app.shutdown(); end
        function delete(app), app.shutdown(); end
    end
end

%% ======================================================================= readers (file scope; UI-free)
function S = io_read(fp, fmt)
%IO_READ Dispatch by extension; every reader returns a Source {Raw, Blocks, Freqs, Meta}.
if ~isfile(fp), error('APAT:FileNotFound', 'File not found: %s', fp); end
[~, ~, ext] = fileparts(fp);  ext = lower(erase(ext, '.'));
S = struct('Raw', table(), 'Blocks', {{}}, 'Freqs', NaN, 'Meta', io_meta(upper(ext), "dB", false));
switch ext
    case {'xlsx', 'xls'},                            S = io_excel(fp, S);
    case {'csv', 'txt', 'dat'},                      S = io_generic(fp, string(fmt), S);
    case 'cut',                                      S = io_cut(fp, S);
    case {'uan', 'fz', 'out', 'ffs', 'ffe', 'ffd'},  S = io_farfield(fp, ext, S);
    otherwise, error('APAT:Unsupported', 'Unsupported file format: .%s', ext);
end
n = max(1, numel(S.Blocks));  S.Freqs(end+1:n) = NaN;  S.Freqs = S.Freqs(1:n);
end

function m = io_meta(format, unit, gainOnly)
% Meta.Unit is a static property of the format (§15-4); the label carries it into every level axis.
label = unit;  if unit == "dB" && ~gainOnly, label = "dB (rel. field)"; end
m = struct('Format', string(format), 'Unit', string(unit), 'UnitLabel', string(label), 'IsGainOnly', gainOnly, 'IsCoverage', false, 'Notes', strings(0, 1));
end

function T = io_block(theta, phi, Eth, Eph)
T = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end

function [Eth, Eph] = io_fields(M, order, magPhase, basis)
%IO_FIELDS One converter for every six-column field layout: M(:, order(3:6)) = [a b c d] = (|c1|,∠c1,|c2|,∠c2) or (Re,Im,Re,Im).
A = M(:, order(3:6));
if magPhase, c1 = 10.^(A(:, 1)/20) .* exp(1i*deg2rad(A(:, 2)));  c2 = 10.^(A(:, 3)/20) .* exp(1i*deg2rad(A(:, 4)));
else,        c1 = complex(A(:, 1), A(:, 2));  c2 = complex(A(:, 3), A(:, 4)); end
switch basis
    case "thetaphi", Eth = c1;  Eph = c2;
    case "rcplcp",   [Eth, Eph] = pol_fromCircular(c1, c2);
    case "lcprcp",   [Eth, Eph] = pol_fromCircular(c2, c1);
end
end

function [M, freqs, triples] = io_numeric(fp)
%IO_NUMERIC Numeric rows of a text far-field file (dominant column count), frequency lines, leading 3-number header lines (FFD).
t = strtrim(replace(readlines(fp), [",", ";"], " "));
tok = regexp(t, '^#?\s*frequenc\w*\s*:?\s*([-+\d.eE\s]+)$', 'tokens', 'once', 'ignorecase');
tok = tok(~cellfun(@isempty, tok));  freqs = cellfun(@(c) sscanf(char(c{1}), '%f').', tok, 'UniformOutput', false);  freqs = [freqs{:}];
freqs = freqs(freqs >= 1e3);                                                % "Frequencies 1" is a count, not a frequency
num = ~cellfun(@isempty, regexp(t, '^[-+]?(\d|\.\d)', 'once'));
tok = regexp(t(num), '[-+]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][-+]?\d+)?', 'match');
assert(~isempty(tok), 'APAT:NoData', 'No numeric data rows found in %s.', fp);
nc = cellfun(@numel, tok);  w = mode(nc);  rows = tok(nc == w);
M = reshape(sscanf(char(strjoin(replace([rows{:}], ["d", "D"], "e"), ' ')), '%f'), w, []).';
hdr = find(nc == 3 & nc ~= w, 2);  triples = [];  if ~isempty(hdr), triples = str2double(vertcat(tok{hdr})); end
end

function S = io_farfield(fp, ext, S)
%IO_FARFIELD UAN/FZ, OUT, FFS, FFE, FFD through one column spec: {order, magPhase, basis, unit, format, raw names}.
[M, freqs, triples] = io_numeric(fp);
switch ext
    case {'uan', 'fz'}, spec = {[1 2 3 5 4 6], true,  "thetaphi", "dBi", "XGTD " + upper(ext), {'Theta', 'Phi', 'E_TH_dB', 'E_PH_dB', 'E_TH_deg', 'E_PH_deg'}};
    case 'out',         spec = {1:6,           false, "rcplcp",   "dBi", "TICRA/GRASP OUT",    {'Theta', 'Phi', 'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}};
    case 'ffs',         spec = {[2 1 3 4 5 6], false, "thetaphi", "dB",  "CST FFS",            {'Phi', 'Theta', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}};
    case 'ffe',         spec = {1:6,           false, "thetaphi", "dB",  "FEKO FFE",           {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}};
    case 'ffd',         spec = {[0 0 1 2 3 4], false, "thetaphi", "dB",  "HFSS FFD",           {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}};
end
[order, mp, basis, unit, name, rawNames] = spec{:};  S.Meta = io_meta(name, unit, false);
if ext == "ffd"
    assert(size(triples, 1) == 2 && size(M, 2) >= 4, 'APAT:FFD', 'FFD header (theta/phi ranges) not found.');
    th = linspace(triples(1, 1), triples(1, 2), round(triples(1, 3))).';  ph = linspace(triples(2, 1), triples(2, 2), round(triples(2, 3))).';
    theta = repelem(th, numel(ph));  phi = repmat(ph, numel(th), 1);  n = numel(theta);  nb = size(M, 1)/n;
    assert(nb == round(nb), 'APAT:FFD', 'FFD row count (%d) is not a multiple of the θ×φ grid (%d).', size(M, 1), n);
else
    assert(size(M, 2) >= 6, 'APAT:Columns', '%s requires at least six numeric columns.', name);
    nb = max(1, numel(freqs));  n = size(M, 1)/nb;  if n ~= round(n), nb = 1;  n = size(M, 1); end
end
if numel(freqs) ~= nb, if ~isempty(freqs), S.Meta.Notes(end+1) = sprintf("%d frequency line(s) found for %d block(s); frequencies ignored.", numel(freqs), nb); end, freqs = NaN(1, nb); end
for b = 1:nb
    Mb = M((b-1)*n + (1:n), :);
    if ext ~= "ffd", theta = Mb(:, order(1));  phi = Mb(:, order(2)); end
    [Eth, Eph] = io_fields(Mb, order, mp, basis);  S.Blocks{b} = io_block(theta, phi, Eth, Eph);
end
S.Freqs = freqs;  S.Raw = array2table(M(1:n, 1:numel(rawNames)), 'VariableNames', rawNames);
if ext == "ffd", S.Raw = [table(theta, phi, 'VariableNames', {'Theta', 'Phi'}), S.Raw]; end
if nb > 1, S.Meta.Notes(end+1) = sprintf("%d frequency blocks; select one in the FFD Freq list.", nb); end
end

function S = io_cut(fp, S)
%IO_CUT TICRA/GRASP .cut blocks: [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data rows].
S.Meta = io_meta("TICRA/GRASP CUT", "dB", false);
L = readlines(fp);  L(strlength(strtrim(L)) == 0) = [];  i = 1;  th = {};  ph = {};  D = {};
while i < numel(L)
    p = sscanf(char(L(i+1)), '%f');  assert(numel(p) >= 7, 'APAT:CUT', 'Could not parse cut parameter line %d.', i + 1);
    n = p(3);  block = reshape(sscanf(char(strjoin(L(i+2:i+1+n), ' ')), '%f'), 2*p(7), []).';
    th{end+1} = p(1) + (0:n-1).'*p(2);  ph{end+1} = repmat(p(4), n, 1);  D{end+1} = block(:, 1:4);  i = i + 2 + n; %#ok<AGROW>
end
icomp = p(5);  assert(any(icomp == [1 2]), 'APAT:UnsupportedICOMP', 'CUT ICOMP=%d is not supported (1 = linear θ/φ, 2 = RHCP/LHCP).', icomp);
theta = vertcat(th{:});  phi = vertcat(ph{:});  D = vertcat(D{:});
if p(6) == 2, [theta, phi] = deal(phi, theta);  S.Meta.Notes(end+1) = "ICUT=2: φ swept at constant θ."; end
neg = theta < 0;  phi(neg) = phi(neg) + 180;  theta(neg) = -theta(neg);
if isscalar(unique(phi))                                                    % single cut → body of revolution (§15-5)
    m = numel(theta);  theta = repmat(theta, 36, 1);  D = repmat(D, 36, 1);  phi = repelem((0:10:350).', m);
    S.Meta.Notes(end+1) = "Single cut replicated as a body of revolution at 10° φ steps.";
end
c1 = complex(D(:, 1), D(:, 2));  c2 = complex(D(:, 3), D(:, 4));
if icomp == 2, [Eth, Eph] = pol_fromCircular(c1, c2);  names = {'Re_RHCP', 'Im_RHCP', 'Re_LHCP', 'Im_LHCP'}; else, Eth = c1;  Eph = c2;  names = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'}; end
S.Raw = array2table([theta, phi, D], 'VariableNames', [{'Theta', 'Phi'}, names]);  S.Blocks = {io_block(theta, phi, Eth, Eph)};
end

function S = io_generic(fp, fmt, S)
%IO_GENERIC CSV/TXT/DAT: coverage-results table, gain-only table, or six-column field table interpreted per FMT.
opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ', '\t', ',', ';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvartype(opts, 'double');  opts = setvaropts(opts, 'TrimNonNumeric', true);  opts.VariableNamingRule = 'preserve';
T = readtable(fp, opts);  nc = width(T);
assert(nc >= 2 && height(T) > 0, 'APAT:InvalidFormat', 'File needs at least two numeric columns.');
names = string(T.Properties.VariableNames);  low = lower(names);  hasHdr = ~all(startsWith(names, "Var"));  c1 = T{:, 1};  c2 = T{:, 2};
keyword = contains(low(1), "threshold") || any(contains(low(2:end), "coverage"));
looksCov = (fmt == "gain" || nc < 6) && all(isfinite(c2)) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic');
if keyword || (looksCov && ~any(contains(low, ["theta", "phi", "gain", "dbi"])))
    if ~hasHdr, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr("Coverage_" + (1:nc-1))]; end
    S.Raw = T;  S.Meta.IsCoverage = true;  return
end
used = 1:nc;
if fmt ~= "gain", assert(nc >= 6, 'APAT:Columns', 'The selected generic E-field format requires six numeric columns.');  used = 1:6; end
T = rmmissing(T, 'DataVariables', used);                                    % drop rows only for NaN in the used columns (D24)
if fmt == "gain"
    assert(nc >= 3, 'APAT:Columns', 'A gain table needs θ, φ and at least one gain column.');
    if hasHdr && any(contains(low(1:2), ["theta", "phi"])), phiFirst = contains(low(1), "phi");  note = "Axis order taken from the header names.";
    else, span = [max(c1) - min(c1), max(c2) - min(c2)];  phiFirst = span(1) > span(2);  note = sprintf("Axis order inferred from spans (column 1: %g°, column 2: %g°).", span); end
    if phiFirst, T = movevars(T, 2, 'Before', 1); end
    T.Properties.VariableNames = [{'Theta', 'Phi'}, cellstr(matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(T.Properties.VariableNames(3:end)), {'Theta', 'Phi'}))];
    unit = "dB";  if any(contains(low, "dbi")), unit = "dBi"; end
    S.Meta = io_meta("Generic gain table", unit, true);  S.Meta.Notes(end+1) = note;  S.Raw = T;  S.Blocks = {T};
else
    M = T{:, 1:6};  mp = endsWith(fmt, "magphase");  order = 1:6;
    if mp                                                                   % phases exceed 100 (degrees); dB magnitudes do not
        big = max(abs(M(:, 3:6)), [], 1, 'omitnan') > 100;
        if big(2) && ~big(3), S.Meta.Notes(end+1) = "Magnitude/phase columns read as interleaved (m1 p1 m2 p2).";
        else, order = [1 2 3 5 4 6];  S.Meta.Notes(end+1) = "Magnitude/phase columns read as grouped (m1 m2 p1 p2)."; end
    end
    basis = "thetaphi";  if startsWith(fmt, "rcp"), basis = "rcplcp"; elseif startsWith(fmt, "lcp"), basis = "lcprcp"; end
    [Eth, Eph] = io_fields(M, order, mp, basis);
    S.Meta = io_meta("Generic text (" + fmt + ")", "dB", false);  S.Raw = T;  S.Blocks = {io_block(M(:, 1), M(:, 2), Eth, Eph)};
end
end

function S = io_excel(fp, S)
%IO_EXCEL Matrix workbooks: sheet 1 = summary; fixed Etheta/Ephi and/or RHCP/LHCP gain+phase matrix sheets (C3 origin).
sheets = string(sheetnames(fp));  low = lower(sheets);
circ = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"];  lin = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), low));  hasL = all(ismember(lower(lin), low));
assert(hasC || hasL, 'APAT:ExcelFormat', 'Unsupported workbook: sheet 1 is the summary; the others must be the Etheta/Ephi and/or RHCP/LHCP matrix sheets.');
req = [repmat(lin, 1, hasL), repmat(circ, 1, hasC)];  X = cell(1, numel(req));
for k = 1:numel(req)
    [th, ph, X{k}] = io_excelSheet(fp, sheets(find(low == lower(req(k)), 1)));
    if k == 1, th0 = th;  ph0 = ph; else, assert(isequal(size(th), size(th0)) && isequal(size(ph), size(ph0)) && max(abs(th - th0)) < 1e-9 && max(abs(ph - ph0)) < 1e-9, 'APAT:ExcelGrid', 'All matrix sheets must share the same θ/φ grid.'); end
end
mp = @(g, p) 10.^(g/20) .* exp(1i*deg2rad(p));
if hasL, Eth = mp(X{1}, X{2});  Eph = mp(X{3}, X{4});  basis = "Eth/Eph"; else, [Eth, Eph] = pol_fromCircular(mp(X{1}, X{2}), mp(X{3}, X{4}));  basis = "RHCP/LHCP"; end
[PH, TH] = meshgrid(ph0, th0);  S.Raw = io_block(TH, PH, Eth, Eph);
for k = 1:numel(req), S.Raw.(char(req(k))) = reshape(X{k}, [], 1); end
S.Blocks = {S.Raw(:, 1:6)};  S.Meta = io_meta("Excel Matrix (" + basis + ")", "dBi", false);
S.Freqs = 1e6 * xl_lookup(fp, sheets(1), 'Pattern Simulation Freq (MHz):');
end

function [th, ph, X] = io_excelSheet(fp, sheet)
C = readcell(fp, 'Sheet', char(sheet));                                     % readcell keeps worksheet coordinates (C3 origin)
assert(size(C, 1) >= 3 && size(C, 2) >= 3, 'APAT:ExcelSheet', 'Sheet "%s" has no C3-origin matrix.', sheet);
isnum = @(c) cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), c);
pm = isnum(C(2, 3:end));  tm = isnum(C(3:end, 2));  np = find([~pm, true], 1) - 1;  nt = find([~tm; true], 1) - 1;
assert(np > 0 && nt > 0 && ~any(pm(np+1:end)) && ~any(tm(nt+1:end)), 'APAT:ExcelAxis', 'Sheet "%s": θ/φ axes must be contiguous numeric cells.', sheet);
ph = cell2mat(C(2, 3:2+np)).';  th = cell2mat(C(3:2+nt, 2));  D = C(3:2+nt, 3:2+np);
assert(all(isnum(D), 'all'), 'APAT:ExcelSheet', 'Sheet "%s" contains non-numeric or missing matrix samples.', sheet);
X = cell2mat(D);
assert(all(diff(th) > 0) && all(diff(ph) > 0) && th(1) >= -1e-9 && th(end) <= 180 + 1e-9 && ph(1) >= -1e-9 && ph(end) <= 360 + 1e-9, 'APAT:ExcelAxis', 'Sheet "%s": axes must increase within θ∈[0,180], φ∈[0,360].', sheet);
end

function v = xl_lookup(fp, sheet, label)
% Numeric value to the right of a labelled summary cell; NaN when absent (the rest of the summary is not used by APAT).
v = NaN;  C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70');
[r, c] = find(cellfun(@(x) (ischar(x) || isstring(x)) && strcmpi(strtrim(x), label), C), 1);
if isempty(r), return; end
for k = c+1:size(C, 2), if isnumeric(C{r, k}) && isscalar(C{r, k}) && isfinite(C{r, k}), v = double(C{r, k});  return; end, end
end

%% ======================================================================= pattern, geometry, display map, cuts
function P = pat_build(S, f)
%PAT_BUILD Canonical grid-native pattern from source block f: polar θ ascending in [0,180], φ ascending in [0,360),
%   uniform axes asserted once (I1).  Angles are snapped to 5 decimals; field values are never rounded.
T = S.Blocks{min(f, numel(S.Blocks))};  th = T.Theta;  ph = T.Phi;  notes = S.Meta.Notes;
if any(th < 0)
    if min(th) >= -90 && max(th) <= 90, th = 90 - th;  notes(end+1) = "Negative θ read as elevation (θ = 90° − el).";
    else, ph(th < 0) = ph(th < 0) + 180;  th = abs(th);  notes(end+1) = "Negative θ folded onto φ + 180°."; end
end
th = mod(th, 360);  over = th > 180;  th(over) = 360 - th(over);  ph(over) = ph(over) + 180;
th = round(th, 5);  ph = round(mod(ph, 360), 5);
[keys, ia] = unique([ph, th], 'rows', 'first');                              % φ-major, θ-minor ⇒ column-major nθ×nφ
P.Theta = unique(keys(:, 2));  P.Phi = unique(keys(:, 1));  nT = numel(P.Theta);  nP = numel(P.Phi);
if nT*nP ~= size(keys, 1), error('APAT:NonUniformGrid', 'Samples do not form a regular θ×φ grid (%d directions, %d θ × %d φ).', size(keys, 1), nT, nP); end
P.dTheta = util_assertUniform(P.Theta, 'θ', 180);  P.dPhi = util_assertUniform(P.Phi, 'φ', 360);
P.NativeStep = [P.dTheta, P.dPhi];  P.IsGainOnly = S.Meta.IsGainOnly;  V = T{:, 3:end};
if P.IsGainOnly
    P.G = struct();  names = T.Properties.VariableNames(3:end);
    for c = 1:numel(names), P.G.(names{c}) = reshape(V(ia, c), nT, nP); end
else
    P.Eth = reshape(complex(V(ia, 1), V(ia, 2)), nT, nP);  P.Eph = reshape(complex(V(ia, 3), V(ia, 4)), nT, nP);
end
P.Freq = S.Freqs(min(f, end));  P.Revision = 1;  P.Meta = S.Meta;  P.Meta.Notes = notes;
end

function step = util_assertUniform(axis, name, single)
if numel(axis) < 2, step = single;  return; end
d = diff(axis);  step = median(d);
if any(abs(d - step) > 1e-6), error('APAT:NonUniformGrid', '%s axis is not uniform: steps range %.6g°..%.6g° (APAT requires uniform grids).', name, min(d), max(d)); end
end

function P = pat_resample(P, step)
%PAT_RESAMPLE Exact decimation when the step ratio is an integer; otherwise bilinear on the φ-closed grid (I6):
%   E-field as |E|² (power) + unit phasor (B.5), gain-kind columns as linear power, other columns linear.
if numel(P.Theta) < 2 || numel(P.Phi) < 2, return; end
kT = step/P.dTheta;  kP = step/P.dPhi;  periodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
isInt = @(k) k >= 1 && abs(k - round(k)) < 1e-9;
if isInt(kT) && isInt(kP)
    rT = 1:round(kT):numel(P.Theta);  rP = 1:round(kP):numel(P.Phi);  th = P.Theta(rT);  ph = P.Phi(rP);
    I = @(X) X(rT, rP);
else
    th = min(P.Theta(1) + (0:floor((P.Theta(end) - P.Theta(1))/step + 1e-9)).'*step, P.Theta(end));   % never outside the source domain
    cols = 1:numel(P.Phi);  phs = P.Phi;
    if periodic, cols(end+1) = 1;  phs(end+1) = P.Phi(1) + 360;  ph = P.Phi(1) + (0:floor(360/step + 1e-9) - 1).'*step;
    else,        ph = P.Phi(1) + (0:floor((P.Phi(end) - P.Phi(1))/step + 1e-9)).'*step; end
    ph = min(ph, phs(end));  I = @(X) interp2(phs, P.Theta, X(:, cols), ph.', th, 'linear');
end
if P.IsGainOnly
    for n = string(fieldnames(P.G)).'
        if util_colKind(n) == "gain", P.G.(n) = 10*log10(max(I(10.^(P.G.(n)/10)), realmin)); else, P.G.(n) = I(P.G.(n)); end
    end
else
    P.Eth = pat_interpField(P.Eth, I);  P.Eph = pat_interpField(P.Eph, I);
end
P.Theta = th;  P.Phi = ph;  P.dTheta = step;  P.dPhi = step;  P.Revision = P.Revision + 1;
end

function E = pat_interpField(E, I)
% |E|² and the unit phasor are interpolated separately and recombined: exact magnitude for constant |E|, circular-mean phase.
A2 = I(abs(E).^2);  U = E ./ max(abs(E), realmin);  U = I(real(U)) + 1i*I(imag(U));
E = sqrt(max(A2, 0)) .* U ./ max(abs(U), realmin);
end

function G = geo_build(P)
%GEO_BUILD Separable cell solid angles (I2): ΔΩ(i,j) = wθ(i)·Δφ with wθ = cos(θ−Δθ/2) − cos(θ+Δθ/2), edges clipped to [0°,180°].
%   Full sphere: Σ wθ = cos 0° − cos 180° = 2 (telescoping) and nφ·Δφ = 2π  ⇒  Σ ΔΩ = 4π exactly.
lo = max(P.Theta(:) - P.dTheta/2, 0);  hi = min(P.Theta(:) + P.dTheta/2, 180);
G.wTheta = cosd(lo) - cosd(hi);  G.dPhi = deg2rad(P.dPhi);
G.PhiPeriodic = abs(numel(P.Phi)*P.dPhi - 360) < 1e-6;
G.IsFullSphere = G.PhiPeriodic && lo(1) == 0 && hi(end) == 180;
G.dOmega = G.wTheta * G.dPhi * ones(1, numel(P.Phi));  G.Omega = sum(G.dOmega, 'all');
end

function M = geo_displayMap(P, G, signedPhi, elevation)
%GEO_DISPLAYMAP Column permutation and axis relabelling for the display convention; no data is copied or changed (I8).
n = numel(P.Phi);  j0 = find(P.Phi >= 180, 1);  perm = 1:n;
if signedPhi && ~isempty(j0), perm = [j0:n, 1:j0-1]; end
M.ColIdx = perm;  closed = G.PhiPeriodic && n > 1;  if closed, M.ColIdx(end+1) = perm(1); end       % closing column, display only
M.PhiAxis = P.Phi(M.ColIdx);  if signedPhi, M.PhiAxis(M.PhiAxis >= 180) = M.PhiAxis(M.PhiAxis >= 180) - 360; end
if closed, M.PhiAxis(end) = M.PhiAxis(1) + 360; end
if elevation, M.ThetaAxis = 90 - P.Theta;  M.ThetaDir = 'normal';  M.ThetaLabel = 'Elevation';
else,         M.ThetaAxis = P.Theta;       M.ThetaDir = 'reverse'; M.ThetaLabel = 'Theta'; end
[M.PhiGrid, M.ThetaGrid] = meshgrid(M.PhiAxis, M.ThetaAxis);                 % display coordinates (contour, rect, datatips)
[M.PhiPhys, M.ThetaPhys] = meshgrid(P.Phi(M.ColIdx), P.Theta);              % physical coordinates (fisheye, 3-D)
M.Key = sprintf('%d|%d', signedPhi, elevation);
end

function K = geo_cut(P, G, Cs, type, value)
%GEO_CUT One full-circle cut as grid slices.  "Phi": row at fixed θ (angle = φ).  "Theta": column at fixed φ joined with
%   the φ+180 column (angle = θ, then 360−θ).  Cs is a cell of nθ×nφ matrices; K.y has one column per matrix.
nT = numel(P.Theta);
if type == "Phi"
    [d, i] = min(abs(P.Theta - value));  K.fixed = P.Theta(i);  K.symbol = 'θ';
    K.angle = P.Phi;  K.theta = repmat(K.fixed, numel(P.Phi), 1);  K.phi = P.Phi;  K.y = cellfun(@(C) C(i, :).', Cs, 'UniformOutput', false);
    if G.PhiPeriodic, K.angle(end+1) = P.Phi(1) + 360;  K.theta(end+1) = K.fixed;  K.phi(end+1) = P.Phi(1);  K.y = cellfun(@(y) y([1:end, 1]), K.y, 'UniformOutput', false); end
else
    [d, j] = min(abs(mod(P.Phi - value + 180, 360) - 180));  K.fixed = P.Phi(j);  K.symbol = 'φ';
    [~, j2] = min(abs(mod(P.Phi - K.fixed, 360) - 180));                     % nearest column to φ + 180
    keep = P.Theta < 180 - 1e-9;                                              % θ = 180 belongs to both half-cuts once
    K.angle = [P.Theta; 360 - flipud(P.Theta(keep))];  K.theta = [P.Theta; flipud(P.Theta(keep))];
    K.phi = [repmat(K.fixed, nT, 1); repmat(P.Phi(j2), nnz(keep), 1)];
    K.y = cellfun(@(C) [C(:, j); flipud(C(keep, j2))], Cs, 'UniformOutput', false);
end
K.y = [K.y{:}];  K.snapped = d > 1e-9;  K.type = type;
end

%% ======================================================================= derivation, polarisation, metrics
function D = pat_derive(P, G, prm, A, excessDB)
%PAT_DERIVE Every column and every base fact of a pattern at the given parameters (I3).  Nothing downstream adds or scales.
if P.IsGainOnly
    C = P.G;
    for n = string(fieldnames(C)).', if util_colKind(n) == "gain", C.(n) = C.(n) + prm.L; end, end     % loss on gain-kind columns only
    total = C.(util_firstGain(C));  K = met_peak(total, G.PhiPeriodic, excessDB);
    D.Pol = struct('pairs', struct('Linear', ["E_TH", "E_PH"], 'Circular', ["E_RCP", "E_LCP"]), 'label', "n/a", 'basis', "Circular");
else
    s = 10^(prm.L/20);  Eth = P.Eth*s;  Eph = P.Eph*s;                        % loss/gain as an incident-field scale
    Er = pol_circular(Eth, Eph, 1);  El = pol_circular(Eth, Eph, 2);
    C.E_Total_dB = 10*log10(max(abs(Eth).^2 + abs(Eph).^2, eps));
    C.E_TH_dB = 20*log10(max(abs(Eth), eps));  C.E_PH_dB = 20*log10(max(abs(Eph), eps));
    C.E_RCP_dB = 20*log10(max(abs(Er), eps));  C.E_LCP_dB = 20*log10(max(abs(El), eps));
    [C.AR_dB, isLinear] = pol_signedAR(Er, El);
    total = C.E_Total_dB;  K = met_peak(total, G.PhiPeriodic, excessDB);
    D.Pol = pol_classify(Eth, Eph, Er, El, P, G, K);
    C.PLF_dB = pol_plf(C.AR_dB, isLinear, prm.RxMode, prm.RxAR_dB, D.Pol.pairs.Circular(1));
    C.Gain_PolCorrected_dB = C.E_Total_dB + C.PLF_dB;
    C.E_TH_Phase = rad2deg(angle(Eth));  C.E_PH_Phase = rad2deg(angle(Eph));  C.E_RCP_Phase = rad2deg(angle(Er));  C.E_LCP_Phase = rad2deg(angle(El));
    C.EIRP_dBW = prm.Pt_dBW + C.E_Total_dB;  eirpW = 10.^(C.EIRP_dBW/10);
    C.PFD_Wm2 = eirpW ./ (4*pi*prm.R_m^2);  C.E_RMS_Vm = sqrt(30*eirpW) ./ prm.R_m;
end
D.Cols = C;  D.Peak = K;
D.Boresight = met_orientation(total, P, G, K, A);
D.Planes = met_planes(D.Boresight, A);
D.Metrics = met_metrics(total, P, G, K, D.Planes, C);
end

function E = pol_circular(Eth, Eph, which)
%POL_CIRCULAR RHCP (1) / LHCP (2) component of E = Eθ θ̂ + Eφ φ̂ under e^{+jωt} with (θ̂, φ̂, r̂) right-handed.
%   IEEE right-hand unit vector ê_R = (θ̂ − jφ̂)/√2  ⇒  E_R = E·ê_R* = (Eθ + jEφ)/√2,  E_L = (Eθ − jEφ)/√2.
if which == 1, E = (Eth + 1i*Eph)/sqrt(2); else, E = (Eth - 1i*Eph)/sqrt(2); end
end

function [Eth, Eph] = pol_fromCircular(Er, El)
Eth = (Er + El)/sqrt(2);  Eph = (Er - El)/(1i*sqrt(2));
end

function [AR, isLinear] = pol_signedAR(Er, El)
%POL_SIGNEDAR Signed axial ratio in dB: + RHCP sense, − LHCP sense; −100 dB where the sample is numerically linear (§15-2).
r = abs(Er);  l = abs(El);  d = r - l;
isLinear = isfinite(d) & abs(d) <= eps .* max(r + l, 1);
AR = min(20*log10((r + l) ./ max(abs(d), eps)), 250) .* sign(d);  AR(isLinear) = -100;
end

function plf = pol_plf(AR_dB, isLinear, rxMode, rxAR_dB, leadingCircular)
%POL_PLF Polarisation loss factor between the antenna ellipse (signed AR) and the incident wave, major axes orthogonal:
%   PLF = 1/2 + (4·ρa·ρw − (ρa² − 1)(ρw² − 1)) / (2(ρa² + 1)(ρw² + 1)),  ρ = signed linear axial ratio (+RHCP, −LHCP).
switch rxMode, case "RHCP", sw = 1; case "LHCP", sw = -1; otherwise, sw = 2*(leadingCircular == "E_RCP") - 1; end
ra = 10.^(abs(AR_dB)/20) .* sign(AR_dB);  ra(isLinear) = 1e12;              % linear antenna ⇒ |ρa| → ∞
rw = sw * 10^(rxAR_dB/20);
plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1)) ./ (2*(ra.^2 + 1)*(rw^2 + 1));
plf = 10*log10(min(max(plf, eps), 1));  plf(~isfinite(AR_dB)) = NaN;       % NaN in ⇒ NaN out
end

function pol = pol_classify(Eth, Eph, Er, El, P, G, K)
%POL_CLASSIFY Co/cross pairs and label from the main beam: Ω-weighted mean component power inside the 45° cone about the peak.
[i, j] = ind2sub([numel(P.Theta), numel(P.Phi)], K.index);
m = cov_coneMask(P, P.Theta(i), P.Phi(j), 45) & isfinite(Eth) & isfinite(Eph);  w = G.dOmega(m);
pw = @(E) sum(abs(E(m)).^2 .* w) / max(sum(w), eps);
p = struct('E_TH', pw(Eth), 'E_PH', pw(Eph), 'E_RCP', pw(Er), 'E_LCP', pw(El));
pol.pairs.Linear = ["E_TH", "E_PH"];  if p.E_PH > p.E_TH, pol.pairs.Linear = fliplr(pol.pairs.Linear); end
pol.pairs.Circular = ["E_RCP", "E_LCP"];  if p.E_LCP > p.E_RCP, pol.pairs.Circular = fliplr(pol.pairs.Circular); end
pol.basis = "Linear";  pol.label = util_pick(p.E_TH >= p.E_PH, "Linear (Vertical)", "Linear (Horizontal)");
if max(p.E_RCP, p.E_LCP) > max(p.E_TH, p.E_PH), pol.basis = "Circular";  pol.label = "Circular (" + replace(pol.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]) + ")"; end
end

function K = met_peak(C, periodic, excessDB)
%MET_PEAK Effective peak = highest sample that is not an isolated spike (I5):
%   spike(i,j) ⇔ C(i,j) − max(4 grid neighbours) > excessDB;  φ wraps when periodic.  No percentile, no toolbox.
[n, m] = size(C);  nb = -inf(n, m);
if n > 1, nb(2:n, :) = max(nb(2:n, :), C(1:n-1, :));  nb(1:n-1, :) = max(nb(1:n-1, :), C(2:n, :)); end
if m > 1
    if periodic, L = circshift(C, 1, 2);  R = circshift(C, -1, 2); else, L = [-inf(n, 1), C(:, 1:m-1)];  R = [C(:, 2:m), -inf(n, 1)]; end
    nb = max(nb, max(L, R));
end
K.spike = isfinite(C) & (C - nb > excessDB);
[K.rawValue, K.rawIndex] = max(C(:), [], 'omitnan');
cand = C;  cand(K.spike) = -Inf;  [K.value, K.index] = max(cand(:), [], 'omitnan');
K.wasAdjusted = K.spike(K.rawIndex);  K.spikeCount = nnz(K.spike);
end

function idx = met_orientation(total, P, G, K, A)
%MET_ORIENTATION Principal axis whose 45° cone holds the most 10^(G/10)·ΔΩ (spikes excluded).
E = 10.^((total - K.value)/10) .* G.dOmega;  E(~isfinite(E) | K.spike) = 0;  e = zeros(1, numel(A.theta));
for a = 1:numel(e), e(a) = sum(E(cov_coneMask(P, A.theta(a), A.phi(a), 45)), 'all'); end
[~, idx] = max(e);
end

function S = met_planes(axisIndex, A)
%MET_PLANES E-plane: θ-cut through the boresight axis' φ.  H-plane: the orthogonal cut — a φ-cut at θ = 90° for a
%   transverse axis (±X, ±Y), a θ-cut at φ = 90° for ±Z.
S.E = struct('type', "Theta", 'value', A.phi(axisIndex));
if A.theta(axisIndex) == 90, S.H = struct('type', "Phi", 'value', 90); else, S.H = struct('type', "Theta", 'value', 90); end
end

function m = met_metrics(total, P, G, K, S, C)
%MET_METRICS Directivity, efficiency and front-to-back on full spheres only (I9); HPBW on the E/H planes; AR at the peak.
keep = isfinite(total) & ~K.spike;  lin = 10.^(total/10);  Prad = sum(lin(keep) .* G.dOmega(keep));
[i, j] = ind2sub(size(total), K.index);
m = struct('PeakGain_dB', K.value, 'PeakTheta_deg', P.Theta(i), 'PeakPhi_deg', P.Phi(j), 'PeakDirectivity_dB', NaN, 'Efficiency_pct', NaN, 'FrontBack_dB', NaN);
if G.IsFullSphere
    m.PeakDirectivity_dB = 10*log10(4*pi*10^(K.value/10) / max(Prad, eps));
    if P.Meta.Unit == "dBi", m.Efficiency_pct = 100*Prad/(4*pi);  if m.Efficiency_pct > 100, m.Efficiency_pct = NaN; end, end
    [~, ib] = min(abs(P.Theta - (180 - P.Theta(i))));  [~, jb] = min(abs(mod(P.Phi - P.Phi(j), 360) - 180));
    m.FrontBack_dB = K.value - total(ib, jb);
end
Ke = geo_cut(P, G, {total}, S.E.type, S.E.value);  Kh = geo_cut(P, G, {total}, S.H.type, S.H.value);
m.HPBW_EPlane_deg = met_hpbw(Ke.angle, Ke.y);  m.HPBW_HPlane_deg = met_hpbw(Kh.angle, Kh.y);
m.AxialRatioAtPeak_dB = NaN;  if isfield(C, 'AR_dB'), m.AxialRatioAtPeak_dB = C.AR_dB(K.index); end
end

function [bw, lo, hi] = met_hpbw(angleDeg, gainDB, peakGain, peakAngle)
%MET_HPBW Half-power beamwidth of one circular cut: linear interpolation of the −3 dB crossings on either side of the peak.
[bw, lo, hi] = deal(NaN);  v = isfinite(angleDeg) & isfinite(gainDB);  angleDeg = angleDeg(v);  gainDB = gainDB(v);
if numel(gainDB) < 3, return; end
if nargin < 3, [peakGain, ip] = max(gainDB);  peakAngle = angleDeg(ip); end
half = peakGain - 3;  [rel, o] = sort(mod(angleDeg - peakAngle + 180, 360) - 180);  g = gainDB(o);
L = find(rel < 0 & g <= half, 1, 'last');  R = find(rel > 0 & g <= half, 1, 'first');
if isempty(L) || isempty(R) || L + 1 > numel(g) || R < 2 || g(L+1) == g(L) || g(R-1) == g(R), return; end
lc = rel(L) + (rel(L+1) - rel(L)) * (half - g(L)) / (g(L+1) - g(L));
rc = rel(R) + (rel(R-1) - rel(R)) * (half - g(R)) / (g(R-1) - g(R));
lo = peakAngle + lc;  hi = peakAngle + rc;  bw = rc - lc;
end

%% ======================================================================= coverage (the definition, verbatim)
function cov = cov_curve(C, dOmega, mask, T)
%COV_CURVE Coverage(T) = 100·Ω_R(C > T)/Ω_R,  Ω_R(C > T) = Σ_{(i,j)∈R, C(i,j) > T} ΔΩ(i,j)   (I7, strict ">").
%   Samples are binned once between the sorted thresholds and summed from the top: O(N + nT), no N×nT indicator matrix.
v = mask & isfinite(C);  g = C(v);  w = dOmega(v);  Omega = sum(w);  T = T(:);  cov = zeros(size(T));
if Omega <= 0, return; end
b = discretize(g, [-Inf; T; Inf], 'IncludedEdge', 'right');                 % bin k+1 = (T_k, T_{k+1}]  ⇒  C > T_k ⇔ bin ≥ k+1
wb = accumarray(b(:), w(:), [numel(T) + 1, 1]);                               % Ω per bin
cov = 100 * cumsum(wb(2:end), 'reverse') / Omega;                              % Ω_R(C > T_k) = Σ_{bins ≥ k+1}
end

function m = cov_coneMask(P, thC, phC, alphaDeg)
%COV_CONEMASK (i,j) ∈ cone ⇔ cos γ ≥ cos α,  cos γ = cos θᵢ cos θc + sin θᵢ sin θc cos(φⱼ − φc)   (spherical law of cosines)
m = cosd(P.Theta(:))*cosd(thC) + sind(P.Theta(:))*sind(thC) .* cosd(P.Phi(:).' - phC) >= cosd(alphaDeg) - 1e-12;
end

function T = cov_thresholds(tMin, tMax, step)
% Thresholds by counting, never by accumulation.
n = max(1, round((tMax - tMin)/step));  T = tMin + (0:n).'*step;
if T(end) < tMax - 1e-9, T(end+1) = tMax; end
end

function c = cov_at(job, T)
c = interp1(job.T, job.cov, T, 'linear', NaN);                                 % "Coverage at T"
end

function t = thr_at(job, c)
[cv, i] = unique(job.cov, 'last');  t = NaN;                                   % upper end of every plateau ⇒ strictly monotone
if numel(cv) > 1, t = interp1(cv, job.T(i), c, 'linear', NaN); end            % "Threshold at c %"
end

%% ======================================================================= utilities
function k = util_colKind(name)
%UTIL_COLKIND gain | ar | plf | phase | link | other, from the column name (drives loss, peak column, theme, visibility, resampling).
key = regexprep(lower(string(name)), '[^a-z0-9]', '');  k = repmat("other", size(key));
k(endsWith(key, "db") | contains(key, ["gain", "directivity", "dbi"])) = "gain";
k(key == "ar" | startsWith(key, ["ardb", "axialratio"])) = "ar";
k(startsWith(key, "plf")) = "plf";
k(contains(key, ["phase", "deg"])) = "phase";
k(ismember(key, ["eirpdbw", "pfdwm2", "ermsvm"])) = "link";
end

function n = util_firstGain(C)
names = string(fieldnames(C));  i = find(util_colKind(names) == "gain", 1);  if isempty(i), i = 1; end, n = names(i);
end

function hidden = util_colHidden(names, Cols)
names = string(names);  [tf, i] = ismember(names, string(Cols(:, 1)));  hidden = false(size(names));
hidden(tf) = [Cols{i(tf), 4}];  hidden = hidden | ismember(util_colKind(names), ["phase", "link"]);
end

function s = util_fmtNumber(v, prec)
% Compact (≤ 2 decimals, no trailing zeros, never "-0") or fixed precision.
if ~(isscalar(v) && isnumeric(v) && isfinite(v)), s = 'n/a';  return; end
if nargin < 2, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); else, s = sprintf(['%.' num2str(prec) 'f'], v); end
if any(strcmp(s, {'', '-', '-0'})), s = '0'; end
end

function b = util_presetRange(peak)
% 50-dB window under the next multiple of 5 above the peak.
if ~isfinite(peak), b = [-40 10];  return; end
hi = 5*ceil(peak/5);  b = min(max([hi - 50, hi], -250), 100);
end

function t = util_ticks(lim, step)
t = [];  if ~isfinite(step) || step <= 0 || diff(lim) <= 0, return; end
t = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)], 'stable');
if numel(t) > 60, t = []; end
end

function s = util_span(v)
s = [min(v), max(v)];  if diff(s) <= 0, s = s + [-1 1]; end
end

function [X, Y, Z] = util_sph(theta, phi, r)
X = r .* sind(theta) .* cosd(phi);  Y = r .* sind(theta) .* sind(phi);  Z = r .* cosd(theta);
end

function r = util_polarRadius(C, lim)
% Radius of the polar-3D surface and its overlay: 0 at lim(1), 1 at lim(2) (one rule for both, D60).
r = min(max((C - lim(1)) / max(diff(lim), eps), 0), 1);
end

function map = util_colormap(isAR)
persistent gainMap arMap
if isempty(gainMap), gainMap = jet(256);  arMap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256)); end
if isAR, map = arMap; else, map = gainMap; end
end

function [th, ph] = util_peakDir(P, index)
[i, j] = ind2sub([numel(P.Theta), numel(P.Phi)], index);  th = P.Theta(i);  ph = P.Phi(j);
end

function out = util_pick(cond, a, b)
if cond, out = a; else, out = b; end
end

function tf = util_isGenericText(path)
[~, ~, ext] = fileparts(char(path));  tf = any(strcmpi(ext, {'.csv', '.txt', '.dat'}));
end