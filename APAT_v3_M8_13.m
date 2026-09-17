classdef APAT_v3_M8_13 < matlab.apps.AppBase  %1709-lines %Edge POB DataTip positioning OK % Customized Interactive DataTip NOT-OK ON Contour Plot & Fisheye Plot (shows default X_Y_Z/Theta_R_Z) %Manual/Interactive DataTip labeling not working on 3d surface Plot % When loading new pattern while POB is active/enabled, it shows new POB but doesn't delete old POB % Cut Overlay Fixed % Coverage Threshold Query snaps to nearest Data Point instead of returning requested/query point! %Context menu shows error: "Warning: You cannot set 'ContextMenu' property of DataTip."
% APAT v3 M8 — Antenna Pattern Analyzer Tool (concise-architecture release).
%
%   Data flow (one direction, one table per stage):
%     file ─readSource─▶ src.blocks{k} ─normalizePattern─▶ stdTbl ─calcPattern─▶ patTbl
%     patTbl ─applyStep (optional 1° resample of the *primitive* data)─▶ viewBase
%     viewBase ─applySpan (φ/θ display convention only)─▶ viewTbl
%     viewTbl ─▶ tables · metadata · cut plots · 5 full-pattern plots · coverage (CCDF)
%
%   Layers:
%     (1) UI construction  — buildUI (+ at/lbl helpers); every handle lives in the `ui` struct.
%     (2) Application      — typed state properties (no hidden UserData flags), event handlers,
%                            view/render methods.  Annotations are tag-based (APAT_POB / APAT_HPBW).
%     (3) Pure services    — UI-free local functions at the end of this file (I/O, math, formatting).
%
%   Requires MATLAB R2023b or newer (range sliders, xregion/thetaregion). No toolboxes.

    properties (SetAccess = private)
        ui struct = struct()              % All graphics handles, grouped by role (see buildUI)
        isClosing logical = false
    end

    properties (Access = private)
        file struct = struct('path','','folder','','base','','name','')
        src struct = struct()             % raw, blocks, freqs, meta  (output of readSource)
        stdTbl table                      % canonical source (θ 0..180, φ 0..360, closed seam)
        patTbl table                      % processed full-resolution pattern
        viewBase table                    % processed pattern at the selected step
        viewTbl table                     % viewBase in the selected display convention
        omega double = []                 % solid-angle weights aligned with viewTbl
        viewRev double = 0                % increments whenever viewTbl changes
        gridCache struct = struct()       % cached θ×φ topology/geometry + rasterized columns
        step double = 1
        POB double = NaN
        POBth double = NaN
        POBph double = NaN
        polLabel char = 'n/a'
        polPairs struct = struct('Linear',["E_TH","E_PH"],'Circular',["E_RCP","E_LCP"])
        boresight double = 1              % index into Axes
        peak struct = struct()            % resolved peak of the selected component
        metrics struct = struct()
        gainLim double = [-40 10]         % authoritative non-AR colour scale
        ctrLim double = [-40 10]          % current full-pattern range
        cutLim double = [-40 10]          % current cut range
        outputMask logical = logical([])  % visible result columns (3:end)
        autoBasis logical = true          % cut basis follows detected polarization until the user picks
        keepOneDegree logical = false     % re-select "1°" after a reprocess
        defaults cell = {}
        styles cell = {}
        covRunID double = 0
        covMode string = ""
        covPresetKey string = ""          % pattern|component|view key of the last automatic threshold preset
        statusTimer = []
        opDialog = []
    end

    properties (Constant, Access = private)
        Axes = struct('labels',{{'+Z','-Z','+X','-X','+Y','-Y'}},'theta',[0 180 90 90 90 90],'phi',[0 0 0 180 90 270])
        HiddenCols = {'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'}
        PeakPct = 99.99
        PeakExcess = 6
        DBRange = [-250 100]
        Views = struct('iso',[135 25 0 0 1],'top',[0 90 0 1 0],'bottom',[0 -90 0 1 0],'right',[90 0 0 0 1],'left',[-90 0 0 0 1],'front',[0 0 0 0 1],'back',[180 0 0 0 1])
        Release = 'APAT v3 M8'
    end

    %% ------------------------------------------------------------------ lifecycle
    methods (Access = public)
        function app = APAT_v3_M8_13
            app.buildUI();
            registerApp(app, app.ui.fig);
            runStartupFcn(app, @startup);
            if nargout == 0, clear app; end
        end

        function delete(app)
            if app.isClosing, return; end
            app.isClosing = true;
            app.stopStatusTimer();
            if ~isempty(app.opDialog) && isvalid(app.opDialog), delete(app.opDialog); end
            if isfield(app.ui,'fig') && isgraphics(app.ui.fig), delete(app.ui.fig); end
        end

        function r = runSelfTest(app)
            %RUNSELFTEST Deterministic numerical smoke checks (no UI interaction).
            [P, T] = meshgrid(0:30:330, 0:30:180);
            tbl = table(T(:), P(:), 10*cosd(T(:)/2).^2, 'VariableNames', {'Theta','Phi','E_Total_dB'});
            w = solidWeights(tbl.Theta, tbl.Phi);
            r.solidAngleError = abs(sum(w) - 4*pi); r.passSolidAngle = r.solidAngleError < 1e-9;
            [pk, k] = calcOrientation(tbl, w, 'E_Total_dB', app.Axes, app.PeakPct, app.PeakExcess);
            r.passOrientation = isfinite(pk.value) && k == 1;
            [P2, T2] = meshgrid(0:2:358, 0:2:180); a = 12*cosd(T2).^2 - 0.5*sind(P2).^2;
            R = resampleCanonical(table(T2(:), P2(:), a(:), 'VariableNames', {'Theta','Phi','E_Total_dB'}), 1);
            native = mod(R.Theta,2) == 0 & mod(R.Phi,2) == 0 & R.Phi < 360;
            r.numericalError = max(abs(R.E_Total_dB(native) - (12*cosd(R.Theta(native)).^2 - 0.5*sind(R.Phi(native)).^2)));
            r.passResampling = height(R) == 181*361 && r.numericalError < 1e-10;
            r.passVisualRange = isequal(displayRange([3.2; -250; -17], app.PeakPct, app.PeakExcess), [-45 5]);
            spike = repmat(0.02, 1e5, 1); spike(1) = 10.02; sp = resolvePeak(spike, app.PeakPct, app.PeakExcess);
            r.passIsolatedSpike = sp.wasAdjusted && abs(sp.value - 0.02) < 1e-12 && isequal(displayRange(spike, app.PeakPct, app.PeakExcess), [-45 5]);
            r.passARSemantic = all(arrayfun(@isAR, ["AR","AR_dB","AR dB","Axial Ratio","Axial_Ratio"])) && ~isAR("E_Total_dB");
            r.passCCDF = max(abs(coverageCCDF([0;10;20], true(3,1), [5;15;25], [1;1;1]) - [200/3; 100/3; 0])) < 1e-12;
            tri = -abs(mod((0:359)' + 180, 360) - 180)/10;   % 0.1 dB/deg triangle peaked at 0° → HPBW 60°
            r.passHPBW = abs(calcHPBW((0:359)', tri) - 60) < 1e-9;
            f = [tempname '.ffd']; fid = fopen(f, 'w'); fprintf(fid, '0 180 3\n-180 180 3\n'); fprintf(fid, '%d 0 0 1\n', 1:9); fclose(fid);
            c = onCleanup(@() delete(f)); %#ok<NASGU>
            d = readSource(f, "auto"); r.passFFDReader = d.meta.source == "HFSS FFD" && isscalar(d.blocks) && height(d.blocks{1}) == 9;
            flags = fieldnames(r); flags = flags(startsWith(flags, 'pass')); ok = cellfun(@(n) r.(n), flags);
            r.pass = all(ok);
            if ~r.pass, error('apat:test:SelfTestFailed', 'Self-test failed: %s', strjoin(flags(~ok), ', ')); end
        end
    end

    %% ------------------------------------------------------------------ UI construction
    methods (Access = private)
        function h = at(~, h, row, col)
            h.Layout.Row = row; h.Layout.Column = col;
        end

        function h = lbl(app, parent, str, row, col, varargin)
            h = app.at(uilabel(parent, 'Text', str, 'HorizontalAlignment', 'right', varargin{:}), row, col);
        end

        function d = fmtDropdown(~, parent, callback)
            d = uidropdown(parent, 'Visible', 'off', 'ValueChangedFcn', callback, 'Tooltip', 'Interpretation used for CSV/TXT/DAT pattern files.', ...
                'Items', {'1: Gain Pattern', '2: Etheta/Ephi — dB magnitude, phase', '3: Etheta/Ephi — real, imaginary', ...
                '4: POL1=RCP, POL2=LCP — dB magnitude, phase', '5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
                '6: POL1=RCP, POL2=LCP — real, imaginary', '7: POL1=LCP, POL2=RCP — real, imaginary'}, ...
                'ItemsData', {'gain','linear_magphase','linear_reim','rcp_lcp_magphase','lcp_rcp_magphase','rcp_lcp_reim','lcp_rcp_reim'});
        end

        function buildUI(app)
            u = struct(); R = app.DBRange;
            u.fig = uifigure('Name', ['Antenna Pattern Analyzer Tool — ' app.Release], 'Visible', 'off', 'Position', [100 100 1136 739], ...
                'WindowState', 'maximized', 'CloseRequestFcn', @(~,~) delete(app));
            u.tabs = uitabgroup(uigridlayout(u.fig, [1 1]));
            u.tabMain = uitab(u.tabs, 'Title', 'Process Pattern 📡');
            u.tabCov = uitab(u.tabs, 'Title', 'Compute Coverage 📈');

            % ---- Main tab: inputs & parameters -------------------------------------------
            g = uigridlayout(u.tabMain, 'ColumnWidth', repmat({'1x'},1,14), 'RowHeight', {'fit','2x','fit','1x','fit'});
            p = uigridlayout(app.at(uipanel(g,'Title','Inputs & Parameters 🎛️'), 1, [1 14]), 'ColumnWidth', repmat({'1x'},1,14), 'RowHeight', {'1x','1x','1x'});
            app.lbl(p, 'Input Pattern:', 1, 1);
            u.pathField = app.at(uieditfield(p,'text'), 1, [2 8]);
            u.ffdLabel  = app.lbl(p, 'FFD Freq:', 1, 9, 'Visible','off');
            u.ffdDrop   = app.at(uidropdown(p,'Items',{'-'},'Visible','off','ValueChangedFcn',@(~,~) app.onFFDChanged()), 1, 10);
            u.loadBtn   = app.at(uibutton(p,'push','Text','📂 Load File','FontSize',14,'FontWeight','bold','ButtonPushedFcn',@(~,~) app.onLoad()), 1, [11 12]);
            u.processBtn = app.at(uibutton(p,'push','Text','⚙️ Process','ButtonPushedFcn',@(~,~) app.onProcess()), 1, [13 14]);
            u.resetBtn  = app.at(uibutton(p,'push','Text','Reset Params','ButtonPushedFcn',@(~,~) app.resetParams()), 2, [1 3]);
            u.fmtLabel  = app.lbl(p, 'Format:', 2, [4 5], 'Visible','off');
            u.fmtDrop   = app.at(app.fmtDropdown(p, @(~,~) app.onFormatChanged()), 2, [6 8]);
            u.stepDrop  = app.at(uidropdown(p,'Items',{'STEP','STEP: 1°'},'ItemsData',{'native','1deg'},'Visible','off','ValueChangedFcn',@(~,~) app.onStepChanged()), 2, [9 10]);
            u.exportBtn = app.at(uibutton(p,'push','Text','💾 Export Results','FontWeight','bold','Visible','off','ButtonPushedFcn',@(~,~) app.exportResults()), 2, [11 12]);
            u.uanBtn    = app.at(uibutton(p,'push','Text','💾 Export UAN','FontWeight','bold','Visible','off','ButtonPushedFcn',@(~,~) app.exportUAN()), 2, [13 14]);
            u.rxPolLabel = app.lbl(p, 'Rw Sense', 3, 1, 'Visible','off');
            u.rxPol     = app.at(uidropdown(p,'Items',{'Auto','RHCP','LHCP'},'Editable','on','Visible','off'), 3, 2);
            u.rwLabel   = app.lbl(p, 'Rw (dB)', 3, 3, 'Visible','off');
            u.rw        = app.at(uispinner(p,'Value',6,'Visible','off'), 3, 4);
            u.lossLabel = app.lbl(p, 'Loss (−) / Gain (+) dB', 3, 5, 'Visible','off');
            u.loss      = app.at(uispinner(p,'Step',0.1,'Visible','off'), 3, 6);
            u.ptLabel   = app.lbl(p, 'Tx Pwr (Pt)', 3, 7, 'Visible','off');
            u.pt        = app.at(uispinner(p,'Visible','off'), 3, 8);
            u.ptUnit    = app.at(uidropdown(p,'Items',{'dBW','dBm','Watts'},'Visible','off'), 3, 9);
            u.rLabel    = app.lbl(p, 'Distance', 3, 10, 'Visible','off');
            u.r         = app.at(uispinner(p,'Value',1,'Visible','off'), 3, 11);
            u.rUnit     = app.at(uidropdown(p,'Items',{'m','km'},'Visible','off'), 3, 12);
            u.covBtn    = app.at(uibutton(p,'push','Text','📉 Coverage ▶','FontWeight','bold','Visible','off','ButtonPushedFcn',@(~,~) app.toCoverage()), 3, [13 14]);

            % ---- Main tab: full-pattern plots (5 tabs share one layout recipe) -----------
            u.fullPanel = app.at(uipanel(g,'Title','Full Antenna Pattern','TitlePosition','centertop','FontWeight','bold','Visible','off'), [2 3], [1 6]);
            u.fullTabs = uitabgroup(uigridlayout(u.fullPanel, [1 1]));
            names = {'contour','circular','sphere','polar','rect'};
            titles = {'Contour Plot','Circular Contour Plot','3D Spherical Plot','3D Polar Plot','3D Surface Plot'};
            for k = 1:5
                f.name = names{k};
                f.tab = uitab(u.fullTabs, 'Title', titles{k});
                f.grid = uigridlayout(f.tab, 'ColumnWidth', {'fit','1x'}, 'RowHeight', {'fit','1x','fit'});
                f.ax = gobjects(0); if k ~= 2, f.ax = app.at(uiaxes(f.grid), [1 3], 2); end   % polar axes are added in startup
                f.maxSp  = app.at(uispinner(f.grid,'Limits',R,'Value',R(2),'Step',5,'ValueChangedFcn',@(s,~) app.setRange("full", s.Value, 2)), 1, 1);
                f.slider = app.at(uislider(f.grid,'range','Limits',R,'Value',R,'Orientation','vertical','ValueChangedFcn',@(s,~) app.setRange("full", s.Value, 0)), 2, 1);
                f.minSp  = app.at(uispinner(f.grid,'Limits',R,'Value',R(1),'Step',5,'ValueChangedFcn',@(s,~) app.setRange("full", s.Value, 1)), 3, 1);
                u.full(k) = f;
            end

            % ---- Main tab: cut plots -----------------------------------------------------
            u.cutPanel = app.at(uipanel(g,'Title','Antenna Pattern Cut','TitlePosition','centertop','FontWeight','bold','Visible','off'), [2 3], [7 12]);
            u.cutTabs = uitabgroup(uigridlayout(u.cutPanel, [1 1]), 'SelectionChangedFcn', @(~,~) app.setAnnotationVisibility());
            u.cutPolarTab = uitab(u.cutTabs, 'Title', 'Polar Cut Plot');
            u.cutPolarGrid = uigridlayout(u.cutPolarTab, 'ColumnWidth', {'fit','0.26x','1x','0.23x'}, 'RowHeight', {'fit','0.25x','1x','fit'});
            u.cutMax    = app.at(uispinner(u.cutPolarGrid,'Limits',R,'Value',R(2),'Step',5,'ValueChangedFcn',@(s,~) app.setRange("cut", s.Value, 2)), 1, 1);
            u.cutSlider = app.at(uislider(u.cutPolarGrid,'range','Limits',R,'Value',R,'Orientation','vertical','ValueChangedFcn',@(s,~) app.setRange("cut", s.Value, 0)), [2 3], 1);
            u.cutMin    = app.at(uispinner(u.cutPolarGrid,'Limits',R,'Value',R(1),'Step',5,'ValueChangedFcn',@(s,~) app.setRange("cut", s.Value, 1)), 4, 1);
            u.hpbwBtn   = app.at(uibutton(u.cutPolarGrid,'state','Text','HPBW','FontWeight','bold','ValueChangedFcn',@(~,~) app.onCutChanged()), 1, 4);
            u.hpbwLabel = app.at(uilabel(u.cutPolarGrid,'Text','','HorizontalAlignment','center','FontWeight','bold'), 2, 4);
            u.cutFieldGrid = app.at(uigridlayout(u.cutPolarGrid,'ColumnWidth',{'1x'},'RowHeight',{'1x','1x','1x'}), 3, 4);
            u.chkTotal  = app.at(uicheckbox(u.cutFieldGrid,'Text','E_Total','Value',true,'ValueChangedFcn',@(~,~) app.onCutChanged()), 1, 1);
            u.chkCo     = app.at(uicheckbox(u.cutFieldGrid,'Text','E_RCP','Value',true,'ValueChangedFcn',@(~,~) app.onCutChanged()), 2, 1);
            u.chkCx     = app.at(uicheckbox(u.cutFieldGrid,'Text','E_LCP','Value',true,'ValueChangedFcn',@(~,~) app.onCutChanged()), 3, 1);
            u.exportCutBtn = app.at(uibutton(u.cutPolarGrid,'push','Text','Export Cut','FontWeight','bold','ButtonPushedFcn',@(~,~) app.exportCut()), 4, 4);
            u.cutRectTab = uitab(u.cutTabs, 'Title', 'Rectangular Cut Plot');
            u.cutRect = uiaxes(uigridlayout(u.cutRectTab, [1 1]));
            xlabel(u.cutRect, 'Theta (degree)'); ylabel(u.cutRect, 'Magnitude (dB)');

            % ---- Main tab: plot control --------------------------------------------------
            u.ctrlPanel = app.at(uipanel(g,'Title','Plot Control 🎨','Visible','off'), 2, [13 14]);
            c = uigridlayout(u.ctrlPanel, 'RowHeight', repmat({'fit'},1,15));
            app.lbl(c,'Component',1,1);   u.component = app.at(uidropdown(c,'Items',{'Total Gain'},'ItemsData',{'E_Total_dB'},'ValueChangedFcn',@(~,~) app.onComponentChanged()), 1, 2);
            app.lbl(c,'Cut type',2,1);    u.cutType = app.at(uidropdown(c,'Items',{'Phi','Theta'},'ValueChangedFcn',@(~,~) app.onCutChanged(true)), 2, 2);
            app.lbl(c,'Cut value',3,1);   u.cutValue = app.at(uispinner(c,'Limits',[0 360],'ValueChangedFcn',@(~,~) app.onCutChanged()), 3, 2);
            app.lbl(c,'Cut fields',4,1);  u.cutBasis = app.at(uidropdown(c,'Items',{'Circular: RCP/LCP','Linear: Etheta/Ephi'},'ItemsData',{'Circular','Linear'},'Enable','off','ValueChangedFcn',@(~,~) app.onBasisChanged()), 4, 2);
            app.lbl(c,'Colorbar max',5,1); u.cmax = app.at(uispinner(c,'Limits',R,'Value',10,'ValueChangedFcn',@(~,~) app.applyColorbar()), 5, 2);
            app.lbl(c,'Colorbar min',6,1); u.cmin = app.at(uispinner(c,'Limits',R,'Value',-40,'ValueChangedFcn',@(~,~) app.applyColorbar()), 6, 2);
            app.lbl(c,'Colorbar step',7,1); u.cstep = app.at(uispinner(c,'Limits',[0.1 100],'Value',5,'ValueChangedFcn',@(~,~) app.applyFullRange(app.ctrLim)), 7, 2);
            app.lbl(c,'Adjust Colorbar',8,1); app.at(uibutton(c,'push','Text','Apply','Tooltip','Apply the colour range to full-pattern and cut plots.','ButtonPushedFcn',@(~,~) app.applyColorbar()), 8, 2);
            app.lbl(c,'3D view',9,1);     u.view3D = app.at(uidropdown(c,'Items',{'Isometric','Top (+Z)','Bottom (-Z)','Right (+X)','Left (-X)','Front (-Y)','Back (+Y)'},'ItemsData',fieldnames(app.Views).','ValueChangedFcn',@(~,~) app.apply3DViews()), 9, 2);
            nb = @(n) repmat(char(160), 1, n);   % non-breaking padding centres the switch captions
            u.phiSpan   = app.at(uiswitch(c,'slider','Items',{['φ span: 0° to 360°' nb(3)],'−180° to 180°'},'ItemsData',{'0-360','signed'},'ValueChangedFcn',@(~,~) app.onSpanChanged()), 10, [1 2]);
            u.thetaSpan = app.at(uiswitch(c,'slider','Items',{'θ span: 0° to 180°',['−90° to 90°' nb(2)]},'ItemsData',{'polar','elevation'},'ValueChangedFcn',@(~,~) app.onSpanChanged()), 11, [1 2]);
            u.ehSwitch  = app.at(uiswitch(c,'slider','Items',{[nb(8) 'E-Plane cut'],'H-Plane cut'},'ItemsData',{'E','H'},'ValueChangedFcn',@(~,~) app.onPlaneChanged()), 12, [1 2]);
            u.overlayCut = app.at(uicheckbox(c,'Text','Overlay Cut on 3D Plot','ValueChangedFcn',@(~,~) app.drawOverlays()), 13, [1 2]);
            u.showPOB   = app.at(uicheckbox(c,'Text','Annotate POB','ValueChangedFcn',@(~,~) app.setAnnotationVisibility()), 14, [1 2]);
            u.showHPBW  = app.at(uicheckbox(c,'Text','Annotate HPBW Bounds','Visible','off','ValueChangedFcn',@(~,~) app.setAnnotationVisibility()), 15, [1 2]);

            % ---- Main tab: data tables & status -----------------------------------------
            u.outFilter = app.at(uidropdown(g,'Items',{'--- column filter ---'},'ItemsData',0,'Visible','off','ValueChangedFcn',@(~,~) app.filterOutput()), 3, [13 14]);
            u.dataTabs  = app.at(uitabgroup(g,'Visible','off'), 4, [1 14]);
            u.tableOut  = uitable(uigridlayout(uitab(u.dataTabs,'Title','Results 📤'), [1 1]), 'ColumnSortable', true, 'RowName', 'numbered', 'ColumnWidth', '1x');
            u.tableIn   = uitable(uigridlayout(uitab(u.dataTabs,'Title','Input 📥'), [1 1]), 'ColumnSortable', true, 'RowName', 'numbered');
            u.tableMeta = uitable(uigridlayout(uitab(u.dataTabs,'Title','Metadata 📋'), [1 1]), 'ColumnName', {'Property','Value'}, 'ColumnWidth', {200,'auto'}, 'RowName', {});
            u.status = app.at(uilabel(g,'Text','Ready -- load an antenna pattern file to begin 🚀','Interpreter','html'), 5, [1 14]);

            % ---- Coverage tab ------------------------------------------------------------
            g2 = uigridlayout(u.tabCov, 'ColumnWidth', {'0.75x','fit','1x','fit','1x'}, 'RowHeight', {'0.25x','1x','fit'});
            u.covParamGrid = uigridlayout(app.at(uipanel(g2,'Title','Inputs & Parameters 🎛️'), 1, [1 5]), 'ColumnWidth', [{'fit'} repmat({'1x'},1,9)], 'RowHeight', {'1x','fit','fit','fit'});
            q = u.covParamGrid;
            u.covType = app.at(uibuttongroup(q,'Title','Coverage Type','SelectionChangedFcn',@(~,~) app.onCovTypeChanged()), [1 2], [1 2]);
            u.covSpherical = uiradiobutton(u.covType,'Text','Spherical 🌐','Position',[11 63 91 22],'Value',true);
            u.covConical   = uiradiobutton(u.covType,'Text','Conical 🔻','Position',[11 41 82 22]);
            u.orientLabel = app.lbl(q,'Orientation 🧭:',3,1,'Enable','off');
            u.orient = app.at(uidropdown(q,'Items',[{'Auto'} app.Axes.labels],'ItemsData',0:6,'Enable','off','ValueChangedFcn',@(~,~) app.onOrientationChanged()), 3, 2);
            u.covCompLabel = app.lbl(q,'Component:',4,1,'Enable','off');
            u.covComp = app.at(uidropdown(q,'Items',{'E_Total_dB'},'Enable','off','ValueChangedFcn',@(~,~) app.onCovComponentChanged()), 4, 2);
            u.covPathLabel = app.lbl(q,'Antenna Pattern:',1,3);
            u.covPath   = app.at(uieditfield(q,'text'), 1, [4 8]);
            u.covLoad   = app.at(uibutton(q,'push','Text','📂 Load File','ButtonPushedFcn',@(~,~) app.onCovLoad()), 1, 9);
            u.covCompute = app.at(uibutton(q,'push','Text','⚙️ Compute Coverage','FontWeight','bold','Enable','off','ButtonPushedFcn',@(~,~) app.onCovCompute()), 1, 10);
            u.thrMinLabel = app.lbl(q,'Threshold  Min (dB):',2,3);  u.thrMin = app.at(uispinner(q,'Value',-40), 2, 4);
            u.thrMaxLabel = app.lbl(q,'Threshold  Max (dB):',2,5);  u.thrMax = app.at(uispinner(q,'Value',10), 2, 6);
            u.thrStepLabel = app.lbl(q,'Step (dB):',2,7);           u.thrStep = app.at(uispinner(q,'Value',1,'Limits',[0.1 100]), 2, 8);
            u.covReset  = app.at(uibutton(q,'push','Text','🔄 Reset','Enable','off','ButtonPushedFcn',@(~,~) app.onCovReset()), 2, 9);
            u.covExport = app.at(uibutton(q,'push','Text','💾 Export Results','Enable','off','ButtonPushedFcn',@(~,~) app.onCovExport()), 2, 10);
            u.coneThLabel = app.lbl(q,'Cone θ₀ (°):',3,3,'Enable','off');       u.coneTh = app.at(uispinner(q,'Limits',[0 180],'Enable','off'), 3, 4);
            u.conePhLabel = app.lbl(q,'Cone φ₀ (°):',3,5,'Enable','off');       u.conePh = app.at(uispinner(q,'Limits',[0 360],'Enable','off'), 3, 6);
            u.coneAngLabel = app.lbl(q,'Cone Angle α (°):',3,7,'Enable','off'); u.coneAng = app.at(uispinner(q,'Limits',[0 180],'Value',45,'Enable','off'), 3, 8);
            u.covClear  = app.at(uibutton(q,'push','Text','🧹 Clear DataTips','Enable','off','ButtonPushedFcn',@(~,~) app.onCovClear()), 3, 9);
            u.covToMain = app.at(uibutton(q,'push','Text','📊 To Main ◀','ButtonPushedFcn',@(~,~) set(u.tabs,'SelectedTab',u.tabMain)), 3, 10);
            u.qCovLabel = app.lbl(q,'Coverage @ dB:',4,3,'Visible','off');  u.qCov = app.at(uispinner(q,'ValueDisplayFormat','%g dB','Visible','off'), 4, 4);
            u.qCovBtn   = app.at(uibutton(q,'push','Text','⯐ Query Coverage','Visible','off','ButtonPushedFcn',@(~,~) app.covQuery("cov")), 4, 5);
            u.qThrLabel = app.lbl(q,'Threshold @ %:',4,6,'Visible','off');  u.qThr = app.at(uispinner(q,'Value',50,'ValueDisplayFormat','%g%%','Visible','off'), 4, 7);
            u.qThrBtn   = app.at(uibutton(q,'push','Text','🔍 Query Threshold','Visible','off','ButtonPushedFcn',@(~,~) app.covQuery("thr")), 4, 8);
            u.covFmtLabel = app.lbl(q,'Format:',4,9,'Visible','off');
            u.covFmtDrop = app.at(app.fmtDropdown(q, @(~,~) app.onCovFormatChanged()), 4, 10);
            u.covResults = app.at(uipanel(g2,'Title','Results','Visible','off'), 2, [1 5]);
            r = uigridlayout(u.covResults, 'ColumnWidth', {'1x','fit','1x','fit','1x'}, 'RowHeight', {'1x','fit'});
            u.covTree = app.at(uitree(r,'checkbox','SelectionChangedFcn',@(~,~) app.onCovSelection(),'CheckedNodesChangedFcn',@(~,~) app.onCovChecked()), [1 2], 1);
            u.covRoot = uitreenode(u.covTree, 'Text', 'Coverage Results');
            u.covAxes = app.at(uiaxes(r), 1, [2 4]);
            title(u.covAxes, 'Coverage vs Threshold'); xlabel(u.covAxes, 'Threshold (dB)'); ylabel(u.covAxes, 'Coverage (%)');
            u.covAxes.Interactions = dataTipInteraction;   % display-only axes
            u.covXMin   = app.at(uispinner(r,'Limits',R,'Value',-40,'ValueChangedFcn',@(s,~) app.onCovXRange(s)), 2, 2);
            u.covXRange = app.at(uislider(r,'range','Limits',R,'Value',[-40 10],'ValueChangedFcn',@(s,~) app.onCovXRange(s),'ValueChangingFcn',@(s,e) app.onCovXRange(s, e.Value)), 2, 3);
            u.covXMax   = app.at(uispinner(r,'Limits',R,'Value',10,'ValueChangedFcn',@(s,~) app.onCovXRange(s)), 2, 4);
            u.covTable  = app.at(uitable(r,'ColumnWidth','1x','RowName',{}), [1 2], 5);
            u.covStatus = app.at(uilabel(g2,'Text','Ready 🚀','Interpreter','html'), 3, [1 5]);
            app.ui = u;
        end

        function startup(app)
            u = app.ui;
            app.ui.full(2).ax = app.at(polaraxes(u.full(2).grid), [1 3], 2);     % polaraxes cannot be created by uiaxes
            app.ui.cutPolar = app.at(polaraxes(u.cutPolarGrid), [1 4], 3);
            set([app.ui.full(2).ax app.ui.cutPolar], 'ThetaZeroLocation', 'top', 'ThetaDir', 'clockwise');
            for k = [1 3 4 5]
                ax = u.full(k).ax; enableDefaultInteractivity(ax);
                if k > 2, ax.Interactions = [rotateInteraction dataTipInteraction]; else, ax.Interactions = [zoomInteraction dataTipInteraction]; end
                ax.ContextMenu = uicontextmenu(u.fig); uimenu(ax.ContextMenu, 'Text', 'Delete DataTips', 'MenuSelectedFcn', @(~,~) delete(findall(ax, 'Type', 'datatip')));
            end
            enableDefaultInteractivity(u.cutRect); u.cutRect.Interactions = [zoomInteraction dataTipInteraction];
            hold(u.covAxes, 'on'); grid(u.covAxes, 'on'); ylim(u.covAxes, [0 100]); set(u.covAxes, 'Box', 'on', 'Layer', 'top');
            set([u.status u.covStatus], {'UserData'}, {u.status.Text; u.covStatus.Text});
            app.defaults = get(app.paramControls(), 'Value');
            app.styles = {uistyle('FontWeight','bold','BackgroundColor',[0.8 1 0.8]), uistyle('FontColor',[0.5 0.5 0.5],'BackgroundColor',[0.9 0.9 0.9])};
            app.setCoverageUI();
            u.fig.Visible = 'on';
        end
    end

    %% ------------------------------------------------------------------ small accessors
    methods (Access = private)
        function c = paramControls(app), u = app.ui; c = [u.loss u.rxPol u.rw u.pt u.ptUnit u.r u.rUnit]; end
        function c = queryControls(app), u = app.ui; c = [u.qCovLabel u.qCov u.qCovBtn u.qThrLabel u.qThr u.qThrBtn]; end
        function tf = isElevation(app), tf = strcmp(app.ui.thetaSpan.Value, 'elevation'); end
        function tf = isSignedPhi(app), tf = strcmp(app.ui.phiSpan.Value, 'signed'); end
        function tf = isGainOnly(app), tf = isfield(app.src, 'meta') && app.src.meta.isGainOnly; end
        function c = comp(app), c = app.ui.component.Value; end
        function s = thetaLabel(app), if app.isElevation(), s = "Elevation"; else, s = "Theta"; end, end

        function s = compLabel(app)
            d = app.ui.component; k = find(strcmp(d.ItemsData, d.Value), 1);
            if isempty(k), s = string(d.Value); else, s = string(d.Items{k}); end
        end

        function [phiLim, thetaLim] = spanLimits(app)
            if app.isSignedPhi(), phiLim = [-180 180]; else, phiLim = [0 360]; end
            if app.isElevation(), thetaLim = [-90 90]; else, thetaLim = [0 180]; end
        end

        function p = getParam(app)
            u = app.ui;
            p = struct('GainLoss_dB', u.loss.Value, 'RxMode', string(u.rxPol.Value), 'RxAR_dB', u.rw.Value);
            p.FieldScale = 10^(p.GainLoss_dB/20);
            switch u.ptUnit.Value
                case 'dBm',   p.Pt_dBW = u.pt.Value - 30;
                case 'Watts', p.Pt_dBW = 10*log10(max(u.pt.Value, eps));
                otherwise,    p.Pt_dBW = u.pt.Value;
            end
            p.R_m = max(u.r.Value, 1e-12) * (1 + 999*strcmp(u.rUnit.Value, 'km'));
        end
    end

    %% ------------------------------------------------------------------ pipeline: load → process → view
    methods (Access = private)
        function onLoad(app)
            u = app.ui; fp = strtrim(u.pathField.Value);
            if isempty(fp) || ~isfile(fp) || strcmp(fp, app.file.path)
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.cut;*.ffd;*.ffe;*.ffs;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern/Gain Files'}, 'Select an antenna pattern file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            dlg = uiprogressdlg(u.fig, 'Title', 'Loading Data', 'Message', 'Reading file...', 'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Abort');
            app.opDialog = dlg; cleaner = onCleanup(@() close(dlg)); drawnow %#ok<NASGU>
            try
                out = app.readWithFormat(fp, u.fmtLabel, u.fmtDrop);
                if out.meta.isCoverage   % coverage results never replace the Main state
                    u.tabs.SelectedTab = u.tabCov; u.covPath.Value = fp; app.covLoadResults(fp, out.raw); return
                end
                [folder, base, ext] = fileparts(fp);
                app.file = struct('path', fp, 'folder', folder, 'base', base, 'name', [base ext]); u.pathField.Value = fp;
                app.activate(out);
                if out.meta.isDep
                    items = compose('Pattern %d: %.4g GHz', (1:numel(out.blocks))', out.freqs(:)/1e9);
                    missing = isnan(out.freqs(:)); items(missing) = compose('Pattern %d', find(missing));
                    u.ffdDrop.Items = items; u.ffdDrop.Value = items{1};
                end
                set([u.ffdDrop u.ffdLabel], 'Visible', out.meta.isDep);
                app.autoBasis = true; app.keepOneDegree = false;
                app.refresh();
            catch ME
                if strcmp(ME.identifier, 'APAT:Cancelled'), app.setStatus(u.status, 'Loading cancelled by user.', true); else, app.showError(ME, 'Loading Error'); end
            end
        end

        function out = readWithFormat(app, fp, label, dropdown)
            % Excel/native formats are self-describing; generic text files expose the format selector.
            generic = isGenericText(fp); fmt = "auto"; if generic, fmt = "gain"; end
            out = readSource(fp, fmt);
            show = generic && ~out.meta.isCoverage; if show, dropdown.Value = 'gain'; end
            set([label dropdown], 'Visible', show);
            app.checkCancelled();
        end

        function activate(app, out)
            app.src = out; app.selectBlock(1);
        end

        function selectBlock(app, k)
            blk = app.src.blocks{k};
            if app.src.meta.isDep, app.src.raw = blk; end
            app.stdTbl = normalizePattern(blk); app.stdTbl.Properties.UserData = app.src.meta;
            set(app.ui.tableIn, 'Data', app.src.raw, 'ColumnName', app.src.raw.Properties.VariableNames);
        end

        function T = buildPattern(app, out)
            % Auxiliary pattern (coverage tab) without touching the Main state; multi-block sources use block 1.
            S = normalizePattern(out.blocks{1}); S.Properties.UserData = out.meta;
            T = calcPattern(S, app.getParam(), app.PeakPct, app.PeakExcess);
        end

        function refresh(app)
            u = app.ui;
            [app.patTbl, info] = calcPattern(app.stdTbl, app.getParam(), app.PeakPct, app.PeakExcess);
            app.checkCancelled();
            [app.polLabel, app.polPairs] = deal(info.pol, info.pairs); hasE = ~app.isGainOnly();
            if app.autoBasis && hasE
                if startsWith(info.pol, 'Linear'), u.cutBasis.Value = 'Linear'; else, u.cutBasis.Value = 'Circular'; end
            end
            % Native step and the optional 1° resampling selector
            ts = gridStep(app.patTbl.Theta); ps = gridStep(mod(app.patTbl.Phi, 360));
            if ~isfinite(ts), ts = 1; end; if ~isfinite(ps), ps = ts; end
            app.step = max(ts, ps); nonCanonical = abs(ts-1) > 1e-9 || abs(ps-1) > 1e-9;
            u.stepDrop.Items = {sprintf('STEP: %g°', app.step), 'STEP: 1°'};
            if app.keepOneDegree && nonCanonical, u.stepDrop.Value = '1deg'; else, u.stepDrop.Value = 'native'; end
            app.keepOneDegree = false; set(u.stepDrop, 'Visible', nonCanonical, 'Enable', nonCanonical);
            u.cutValue.Step = max(ts, 1);
            app.applyStep(); app.updateComponentItems(); app.checkCancelled();
            app.updateView(true, false, false);   % orientation, metrics, ranges, tables (plots below)
            app.onPlaneChanged();                 % fast initial E/H-plane cut
            drawnow limitrate
            app.renderFull();
            set([u.cutPanel u.exportBtn u.fullPanel u.ctrlPanel u.covBtn u.dataTabs u.outFilter], 'Visible', 'on');
            set([u.uanBtn u.cutFieldGrid u.chkTotal u.chkCo u.chkCx], 'Visible', hasE); set([u.chkCo u.chkCx u.cutBasis], 'Enable', hasE);
            app.updateInputVisibility();
            txt = sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>&theta;=%s&deg;, &phi;=%s&deg;</b>)', app.file.name, fmtNum(app.POB, 2), fmtNum(app.POBth), fmtNum(app.POBph));
            if hasE && ~strcmpi(strtrim(app.polLabel), 'n/a'), txt = sprintf('%s | Polarization <b>%s</b>', txt, app.polLabel); end
            app.setStatus(u.status, txt, false);
        end

        function applyStep(app)
            % Resample the *canonical primitive* data (fields / gain) when 1° is requested, then recompute derived quantities.
            S = app.stdTbl; base = app.patTbl;
            ts = gridStep(S.Theta); ps = gridStep(mod(S.Phi, 360));
            if strcmp(app.ui.stepDrop.Value, '1deg') && ~(abs(ts-1) <= 1e-9 && abs(ps-1) <= 1e-9)
                if ts < 1 && ps < 1   % finer-than-1° regular data: pure decimation keeps exact samples
                    S = S(abs(S.Theta - round(S.Theta)) < 1e-9 & abs(S.Phi - round(S.Phi)) < 1e-9, :);
                else
                    S = resampleCanonical(S, 1);
                end
                S.Properties.UserData = app.stdTbl.Properties.UserData;
                base = calcPattern(S, app.getParam(), app.PeakPct, app.PeakExcess);
            end
            app.viewBase = base; app.applySpan();
        end

        function applySpan(app)
            % Materialize only the display convention (signed φ / elevation θ); the canonical table stays untouched.
            T = app.viewBase; signed = app.isSignedPhi(); elev = app.isElevation();
            if signed
                T(abs(T.Phi - 360) <= 1e-9, :) = [];
                T.Phi(T.Phi > 180) = T.Phi(T.Phi > 180) - 360;
                seam = T(abs(T.Phi - 180) < 1e-9, :); seam.Phi(:) = -180; T = [seam; T];
            end
            if elev, T.Theta = 90 - T.Theta; end
            meta = app.src.meta; meta.elevation = elev; T.Properties.UserData = meta;
            if signed || elev, T = sortrows(T, {'Phi','Theta'}); end
            app.viewTbl = T; app.omega = solidWeights(physTheta(T), T.Phi);
            app.gridCache = struct(); app.viewRev = app.viewRev + 1;
        end

        function updateView(app, refreshRanges, renderFull, updateCut)
            if nargin < 3, renderFull = true; end; if nargin < 4, updateCut = true; end
            T = app.viewTbl; c = app.comp();
            [app.peak, app.boresight] = calcOrientation(T, app.omega, c, app.Axes, app.PeakPct, app.PeakExcess);
            app.POB = app.peak.value; th = physTheta(T); app.POBth = th(app.peak.index); app.POBph = mod(T.Phi(app.peak.index), 360);
            app.metrics = calcMetrics(T, app.omega, app.Axes, app.boresight, app.isElevation(), app.PeakPct, app.PeakExcess);
            if refreshRanges
                if ~isAR(c) && ismember('E_Total_dB', T.Properties.VariableNames), app.gainLim = displayRange(T.E_Total_dB, app.PeakPct, app.PeakExcess); end
                if isAR(c), req = [-30 30]; else, req = app.gainLim; end
                app.setRange("all", req, 0, false);
            end
            app.updateTables(); app.updateMetadata();
            if updateCut, app.updateCutControl(); app.plotCut(); end
            if renderFull, app.renderFull(); end
        end

        function updateComponentItems(app)
            [cols, labels] = componentMap(app.viewTbl); d = app.ui.component; prev = string(d.Value);
            [d.Items, d.ItemsData] = deal(cellstr(labels), cellstr(cols));
            if ~isempty(cols), d.Value = preferredComponent(prev, cols); end
        end

        function updateTables(app)
            d = app.ui.outFilter; cols = app.viewTbl.Properties.VariableNames(3:end);
            if ~isequal(regexprep(d.Items(2:end), '^✓ ?', ''), cols)   % schema changed → rebuild the column filter
                [d.Items, d.ItemsData] = deal([{'--- column filter ---'} cols], 0:numel(cols));
                app.outputMask = ~ismember(cols, app.HiddenCols); d.Value = 0;
            end
            app.filterOutput();
        end

        function filterOutput(app)
            d = app.ui.outFilter;
            if d.Value > 0, app.outputMask(d.Value) = ~app.outputMask(d.Value); d.Value = 0; end
            d.Items = regexprep(d.Items, '^✓ ?', ''); removeStyle(d);
            on = find(app.outputMask) + 1; d.Items(on) = append('✓ ', d.Items(on));
            if ~isempty(on), addStyle(d, app.styles{1}, 'Item', on); end; addStyle(d, app.styles{2}, 'Item', find([true, ~app.outputMask]));
            app.ui.tableOut.Data = app.viewTbl(:, [true true app.outputMask]);
            app.updateInputVisibility();
        end

        function updateInputVisibility(app)
            u = app.ui; cols = string(app.viewTbl.Properties.VariableNames(3:end)); sel = cols(app.outputMask);
            has = @(names) any(ismember(sel, names));
            set([u.rxPolLabel u.rxPol u.rwLabel u.rw], 'Visible', has(["PLF_dB","Gain_PolCorrected_dB"]));
            set([u.ptLabel u.pt u.ptUnit], 'Visible', has(["EIRP_dBW","PFD_Wm2","E_RMS_Vm"]));
            set([u.rLabel u.r u.rUnit], 'Visible', has(["PFD_Wm2","E_RMS_Vm"]));
            set([u.lossLabel u.loss], 'Visible', app.isGainOnly() || has(["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","Gain_PolCorrected_dB","EIRP_dBW","PFD_Wm2","E_RMS_Vm"]));
        end

        function updateMetadata(app)
            if isempty(app.viewTbl), return; end
            T = app.viewTbl; m = app.metrics; th = unique(T.Theta); ph = unique(T.Phi); f = app.src.freqs(isfinite(app.src.freqs));
            rows = {'Source format', app.src.meta.source; 'File', app.file.name; ...
                'Samples', sprintf('%d samples  (θ: %d × φ: %d)', height(T), numel(th), numel(ph)); ...
                'θ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(min(th)), fmtNum(max(th)), fmtNum(gridStep(th))); ...
                'φ range / step', sprintf('[%s°, %s°] / %s°', fmtNum(min(ph)), fmtNum(max(ph)), fmtNum(gridStep(ph)))};
            if ~isempty(f), rows(end+1,:) = {'Frequencies', strjoin(compose('%.4g GHz', f(:)/1e9), ', ')}; end
            if ~app.isGainOnly()
                if ~strcmpi(strtrim(app.polLabel), 'n/a'), rows(end+1,:) = {'Polarization', app.polLabel}; end
                rows(end+1,:) = {'Cut Co-pol / Cross-pol', char(strjoin(app.polPairs.(app.ui.cutBasis.Value), ' / '))};
            end
            rows = [rows; {'Peak gain (POB)', sprintf('%s dB', fmtNum(m.PeakGain_dB)); 'POB direction [θ, φ]', sprintf('[%s°, %s°]', fmtNum(m.PeakTheta_deg), fmtNum(m.PeakPhi_deg)); ...
                'Boresight axis', app.Axes.labels{app.boresight}; 'Peak policy', sprintf('P%.4g, max excess %.4g dB', app.PeakPct, app.PeakExcess); ...
                'Peak adjusted', char(string(app.peak.wasAdjusted)); 'HPBW E-plane', sprintf('%s°', fmtNum(m.HPBW_EPlane_deg)); 'HPBW H-plane', sprintf('%s°', fmtNum(m.HPBW_HPlane_deg)); ...
                'Front-to-back', sprintf('%s dB', fmtNum(m.FrontBack_dB)); 'Peak directivity', sprintf('%s dB', fmtNum(m.PeakDirectivity_dB))}];
            if isfinite(m.Efficiency_pct), rows(end+1,:) = {'Radiation efficiency', sprintf('%s%%', fmtNum(m.Efficiency_pct))}; end
            if isfinite(m.AxialRatioAtPeak_dB), rows(end+1,:) = {'AR at peak', sprintf('%s dB', fmtNum(m.AxialRatioAtPeak_dB))}; end
            app.ui.tableMeta.Data = rows;
        end
    end

    %% ------------------------------------------------------------------ event handlers (Main tab)
    methods (Access = private)
        function onProcess(app)
            u = app.ui;
            if isempty(app.stdTbl), uialert(u.fig, 'No file! Load a pattern first.', 'Warning', 'Icon', 'warning'); return; end
            dlg = uiprogressdlg(u.fig, 'Title', 'Processing', 'Message', 'Re-processing pattern...', 'Indeterminate', 'on'); cleaner = onCleanup(@() close(dlg)); %#ok<NASGU>
            app.keepOneDegree = strcmp(u.stepDrop.Value, '1deg');
            try
                if isGenericText(app.file.path)   % re-interpret the generic source with the selected text format
                    out = readSource(app.file.path, u.fmtDrop.Value);
                    assert(~out.meta.isCoverage, 'The selected generic format identifies a coverage-results file.'); app.activate(out);
                end
                app.refresh();
                app.setStatus(u.status, ['Re-processed <b>' app.file.name '</b> with current parameters ✅'], true);
            catch ME
                app.showError(ME, 'Processing Error');
            end
        end

        function onFormatChanged(app)
            if strcmp(strtrim(app.ui.pathField.Value), app.file.path) && isGenericText(app.file.path), app.autoBasis = true; app.onProcess(); end
        end

        function onStepChanged(app), app.applyStep(); app.updateComponentItems(); app.updateView(true); end
        function onSpanChanged(app), if ~isempty(app.viewBase), app.applySpan(); app.updateView(false); end, end
        function onComponentChanged(app), if ~isempty(app.viewTbl), app.updateView(true); end, end
        function onBasisChanged(app), app.autoBasis = false; app.updateMetadata(); app.onCutChanged(); end

        function onFFDChanged(app)
            u = app.ui; k = find(strcmp(u.ffdDrop.Items, u.ffdDrop.Value), 1); app.autoBasis = true;
            app.selectBlock(k); app.refresh();
            app.setStatus(u.status, sprintf('Switched to FFD block %d (%s).', k, u.ffdDrop.Value), true);
        end

        function resetParams(app)
            set(app.paramControls(), {'Value'}, app.defaults);
            if ~isempty(app.stdTbl), app.refresh(); end
        end

        function onPlaneChanged(app)
            % E-plane: θ-cut through the boresight φ.  H-plane: the orthogonal plane through the boresight axis.
            u = app.ui; a = app.Axes; k = app.boresight;
            if strcmp(u.ehSwitch.Value, 'E'),  u.cutType.Value = 'Theta'; target = a.phi(k);
            elseif a.theta(k) == 90,           u.cutType.Value = 'Phi';   target = 90 * ~app.isElevation();
            else,                              u.cutType.Value = 'Theta'; target = 90;
            end
            values = app.updateCutControl(); [~, i] = min(abs(values - target)); u.cutValue.Value = values(i);
            app.onCutChanged();
        end

        function onCutChanged(app, typeChanged)
            if isempty(app.viewTbl), return; end
            if nargin > 1 && typeChanged, app.updateCutControl(); end
            u = app.ui; u.showHPBW.Visible = u.hpbwBtn.Value; if ~u.hpbwBtn.Value, u.showHPBW.Value = false; end
            app.plotCut();
            if u.overlayCut.Value, app.drawOverlays(); end
        end

        function values = updateCutControl(app)
            % Cut value = fixed θ for a Phi cut, fixed φ for a Theta cut; snap to the sampled planes.
            u = app.ui;
            if strcmp(u.cutType.Value, 'Phi'), values = unique(app.viewTbl.Theta); else, values = unique(mod(app.viewTbl.Phi, 360)); end
            if numel(values) > 1, u.cutValue.Limits = [min(values) max(values)]; u.cutValue.Step = min(diff(values)); end
            [~, i] = min(abs(values - u.cutValue.Value)); u.cutValue.Value = values(i);
        end
    end

    %% ------------------------------------------------------------------ ranges & theme
    methods (Access = private)
        function setRange(app, scope, value, which, applyNow)
            % Synchronize slider/spinner triplets.  scope: "all" | "full" | "cut";  which: 0 both, 1 min, 2 max.
            if nargin < 5, applyNow = true; end
            u = app.ui; R = app.DBRange;
            if scope == "all"
                req = clampRange(value, R); [u.cmin.Value, u.cmax.Value] = deal(req(1), req(2));
                app.setRange("full", req, 0, applyNow); app.setRange("cut", req, 0, applyNow); return
            end
            if scope == "full", sliders = [u.full.slider]; mins = [u.full.minSp]; maxs = [u.full.maxSp]; req = app.ctrLim;
            else,               sliders = u.cutSlider;     mins = u.cutMin;       maxs = u.cutMax;       req = app.cutLim;
            end
            if which == 0, req = value; else, req(which) = value; end
            req = clampRange(req, R);
            lim = req; if which ~= 0, lim = [min(sliders(1).Limits(1), req(1)), max(sliders(1).Limits(2), req(2))]; end   % single-end edits only widen
            set(sliders, 'Limits', R, 'Value', req); set(sliders, 'Limits', lim);
            set(mins, 'Limits', [R(1), req(2)-1], 'Value', req(1)); set(maxs, 'Limits', [req(1)+1, R(2)], 'Value', req(2));
            if scope == "full", app.ctrLim = req; if ~isAR(app.comp()), app.gainLim = req; end, else, app.cutLim = req; end
            if applyNow && ~isempty(app.viewTbl)
                if scope == "full", app.applyFullRange(req); else, set(u.cutPolar, 'RLim', req); set(u.cutRect, 'YLim', req); end
                drawnow limitrate
            end
        end

        function applyColorbar(app), app.setRange("all", [app.ui.cmin.Value app.ui.cmax.Value], 0, true); end

        function applyFullRange(app, lim)
            for f = app.ui.full
                if ~isgraphics(f.ax), continue; end
                clim(f.ax, lim); if strcmp(f.name, 'rect'), zlim(f.ax, lim); end
                cb = findall(ancestor(f.ax, 'figure'), 'Type', 'ColorBar', 'Axes', f.ax);
                if ~isempty(cb), app.setColorbarTicks(cb(1), lim); end
            end
        end

        function setColorbarTicks(app, cb, lim)
            t = axisTicks(lim, app.ui.cstep.Value); if ~isempty(t), cb.Ticks = t; end
        end

        function [lim, cmap] = plotTheme(app)
            % Signed axial ratio: fixed ±30 dB blue–white–red scale.  Everything else: the shared gain scale with jet.
            if isAR(app.comp()), lim = [-30 30]; cmap = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1, 1, 256));
            else,                lim = app.gainLim; cmap = jet(256);
            end
        end

        function r = polarRadius(app, values, lim)
            % One radial mapping shared by the 3-D polar surface and its cut overlay (normalized to the pattern maximum).
            scale = @(v) max(v - lim(1), 0) / max(diff(lim), eps);
            r = scale(values) / max(max(scale(app.viewTbl.(app.comp())), [], 'omitnan'), eps);
        end
    end

    %% ------------------------------------------------------------------ rendering
    methods (Access = private)
        function [theta, phi, G] = gridOf(app, col)
            % Rasterize one view-table column onto the θ×φ display grid; topology/geometry are cached per view.
            T = app.viewTbl; g = app.gridCache;
            if ~isfield(g, 'idx')
                g.theta = unique(T.Theta); g.phi = unique(T.Phi);
                [~, it] = ismember(T.Theta, g.theta); [~, ip] = ismember(T.Phi, g.phi);
                g.sz = [numel(g.theta) numel(g.phi)]; g.idx = sub2ind(g.sz, it, ip); g.data = struct();
                [g.phiGrid, g.thetaGrid] = meshgrid(g.phi, g.theta);
                g.thetaPolar = g.thetaGrid; if app.isElevation(), g.thetaPolar = 90 - g.thetaGrid; end
                g.phiRad = deg2rad(g.phiGrid); s = sind(g.thetaPolar);
                [g.x, g.y, g.z] = deal(s.*cos(g.phiRad), s.*sin(g.phiRad), cosd(g.thetaPolar));
            end
            key = matlab.lang.makeValidName(col);
            if ~isfield(g.data, key), G = nan(g.sz); G(g.idx) = T.(col); g.data.(key) = G; end
            G = g.data.(key); theta = g.theta; phi = g.phi; app.gridCache = g;
        end

        function renderFull(app)
            if isempty(app.viewTbl), return; end
            for k = 1:5, app.checkCancelled(); app.drawFull(k); end
            drawnow limitrate
            app.annotateFull();
        end

        function drawFull(app, k)
            f = app.ui.full(k); ax = f.ax; [theta, phi, G] = app.gridOf(app.comp()); g = app.gridCache; name = app.compLabel();
            [lim, cmap] = app.plotTheme(); cla(ax); hold(ax, 'on');
            switch f.name
                case 'contour'
                    s = pcolor(ax, phi, theta, G); set(s, 'FaceColor', 'interp', 'LineStyle', 'none');
                    app.formatAngularAxes(ax, 30, 15); daspect(ax, [1 1 1]); title(ax, name, 'Interpreter', 'none');
                case 'circular'
                    s = surface(ax, g.phiRad, g.thetaPolar, zeros(size(G)), G, 'EdgeColor', 'none');
                    app.polarTicks(ax); rl = 0:30:180; if app.isElevation(), rl = 90 - rl; end
                    set(ax, 'RLim', [0 180], 'RTick', 0:30:180, 'RTickLabel', compose('%d°', rl));
                    title(ax, sprintf('%s  |  r=θ, angle=φ', name), 'Interpreter', 'none', 'FontSize', 9);
                case {'sphere','polar'}
                    r = 1; if strcmp(f.name, 'polar'), r = app.polarRadius(G, lim); end
                    s = surf(ax, r.*g.x, r.*g.y, r.*g.z, G, 'EdgeColor', 'none');
                    set(ax, 'XLim', [-1.5 1.5], 'YLim', [-1.5 1.5], 'ZLim', [-1.5 1.5], 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1], 'Projection', 'orthographic');
                    axis(ax, 'off'); app.drawXYZ(ax); app.overlayCut(ax, f.name, lim);
                    title(ax, sprintf('%s  |  θ: %s  |  φ: %s', name, app.ui.thetaSpan.Value, app.ui.phiSpan.Value), 'Interpreter', 'none');
                case 'rect'
                    s = surf(ax, g.phiGrid, g.thetaGrid, G, 'EdgeColor', 'none'); zlim(ax, lim);
                    zt = axisTicks(lim, app.ui.cstep.Value); if ~isempty(zt), ax.ZTick = zt; end
                    app.formatAngularAxes(ax, 60, 30); grid(ax, 'on');
                    xlabel(ax, 'Phi (degree)'); ylabel(ax, app.thetaLabel() + " (degree)"); zlabel(ax, name + " (dB)", 'Interpreter', 'none'); title(ax, name, 'Interpreter', 'none');
            end
            s.Tag = 'APAT_Surface'; clim(ax, lim); colormap(ax, cmap); app.setColorbarTicks(colorbar(ax), lim);
            if k >= 3, app.apply3DView(k); set(findall(ax, '-property', 'ContextMenu'), 'ContextMenu', ax.ContextMenu); end
            hold(ax, 'off');
            try, s.DataTipTemplate.DataTipRows = [dataTipTextRow(app.thetaLabel(), g.thetaGrid, '%.3g°'); dataTipTextRow("Phi", g.phiGrid, '%.3g°'); dataTipTextRow(replace(name, "_", "\_"), G, '%.3g dB')]; catch, end
        end

        function annotateFull(app)
            % One pinned POB datatip per full-pattern plot at the grid cell nearest to the resolved peak (tag-based, no registry).
            delete(findall(app.ui.fullPanel, 'Tag', 'APAT_POB'));
            if ~isfinite(app.POBth) || ~isfinite(app.POBph), return; end
            g = app.gridCache; th = app.POBth; ph = mod(app.POBph, 360);
            if app.isElevation(), th = 90 - th; end; if app.isSignedPhi() && ph > 180, ph = ph - 360; end
            [~, r] = min(abs(g.theta - th)); [~, c] = min(abs(g.phi - ph)); [~, ~, G] = app.gridOf(app.comp()); v = G(r, c);
            rows = [dataTipTextRow(app.thetaLabel(), g.thetaGrid(r,c), '%.3g°'); dataTipTextRow("Phi", g.phiGrid(r,c), '%.3g°'); dataTipTextRow(replace(app.compLabel(), "_", "\_"), v, '%.3g dB')];
            [lim, ~] = app.plotTheme(); rad = app.polarRadius(v, lim);
            for f = app.ui.full
                switch f.name
                    case 'contour',  app.markPoint(f.ax, g.phi(c), g.theta(r), [], [], rows, 'APAT_POB');
                    case 'circular', app.markPoint(f.ax, g.phiRad(r,c), g.thetaPolar(r,c), [], [], rows, 'APAT_POB');
                    case 'sphere',   app.markPoint(f.ax, g.x(r,c), g.y(r,c), g.z(r,c), [], rows, 'APAT_POB');
                    case 'polar',    app.markPoint(f.ax, rad*g.x(r,c), rad*g.y(r,c), rad*g.z(r,c), [], rows, 'APAT_POB');
                    case 'rect',     app.markPoint(f.ax, g.phiGrid(r,c), g.thetaGrid(r,c), v, [], rows, 'APAT_POB');
                end
            end
            app.setAnnotationVisibility();
        end

        function markPoint(app, ax, x, y, z, color, rows, tag)
            % One marker + pinned datatip; tagged so visibility toggles need no bookkeeping.
            if isempty(color), color = 'k'; end
            held = ishold(ax); hold(ax, 'on'); isPolar = isa(ax, 'matlab.graphics.axis.PolarAxes');
            if isPolar, h = polarplot(ax, x, y, 'o'); elseif isempty(z), h = plot(ax, x, y, 'o'); else, h = plot3(ax, x, y, z, 'o', 'Clipping', 'off'); end
            set(h, 'Color', color, 'MarkerFaceColor', color, 'MarkerSize', 5, 'HandleVisibility', 'off', 'Tag', tag);
            h.DataTipTemplate.DataTipRows = rows;
            tip = datatip(h, 'DataIndex', 1, 'FontSize', 9, 'HandleVisibility', 'off'); tip.Tag = tag;
            if ~isPolar && isempty(z) && isequal(ax, app.ui.full(1).ax)   % keep contour tips inside the axes at the top edge
                top = ax.YLim(2); if strcmp(ax.YDir, 'reverse'), top = ax.YLim(1); end
                if abs(y - top) <= diff(ax.YLim)/1000, locs = {'southeast','southwest'}; tip.Location = locs{1 + (x > mean(ax.XLim))}; end
            end
            if ~held, hold(ax, 'off'); end
        end

        function setAnnotationVisibility(app)
            % Tag-based visibility: POB follows its checkbox; HPBW tips additionally follow the active cut tab.
            u = app.ui; if ~isfield(u, 'cutPolar'), return; end
            set(findall(u.fig, 'Tag', 'APAT_POB'), 'Visible', u.showPOB.Value);
            tabs = [u.cutPolarTab u.cutRectTab]; axs = {u.cutPolar, u.cutRect};
            for k = 1:2
                set(findall(axs{k}, 'Type', 'line', 'Tag', 'APAT_HPBW'), 'Visible', u.showHPBW.Value);
                set(findall(axs{k}, 'Type', 'datatip', 'Tag', 'APAT_HPBW'), 'Visible', u.showHPBW.Value && u.cutTabs.SelectedTab == tabs(k));
            end
        end

        function formatAngularAxes(app, ax, phiStep, thetaStep)
            [pl, tl] = app.spanLimits(); dirs = {'reverse','normal'};
            set(ax, 'XLim', pl, 'YLim', tl, 'YDir', dirs{1 + app.isElevation()}, 'Box', 'on', 'Layer', 'top', 'XTick', pl(1):phiStep:pl(2), 'YTick', tl(1):thetaStep:tl(2));
        end

        function polarTicks(app, pax)
            a = 0:30:330; if app.isSignedPhi(), a(a > 180) = a(a > 180) - 360; end
            set(pax, 'ThetaTick', 0:30:330, 'ThetaTickLabel', compose('%d°', a));
        end

        function drawXYZ(~, ax)
            col = {[0.85 0.1 0.1], [0.1 0.6 0.1], [0.1 0.2 0.9]}; txt = {'+X  (θ=90°, φ=0°)', '+Y  (θ=90°, φ=90°)', '+Z  (θ=0°)'}; D = 1.35*eye(3);
            for k = 1:3
                quiver3(ax, 0, 0, 0, D(k,1), D(k,2), D(k,3), 0, 'Color', col{k}, 'LineWidth', 1.6, 'MaxHeadSize', 0.25);
                text(ax, 1.12*D(k,1), 1.12*D(k,2), 1.12*D(k,3), txt{k}, 'Color', col{k}, 'FontWeight', 'bold');
            end
        end

        function apply3DView(app, k)
            iso = [135 25]; if k == 5, iso = [-35 35]; end
            v = app.Views.(app.ui.view3D.Value); if strcmp(app.ui.view3D.Value, 'iso'), v(1:2) = iso; end
            view(app.ui.full(k).ax, v(1), v(2)); camup(app.ui.full(k).ax, v(3:5));
        end

        function apply3DViews(app)
            if isempty(app.viewTbl), return; end
            for k = 3:5, app.apply3DView(k); end
        end

        function overlayCut(app, ax, kind, lim)
            delete(findall(ax, 'Tag', 'APAT_CutOverlay'));
            if ~app.ui.overlayCut.Value, return; end
            [~, D, ~, ~, geo] = app.cutData(); th = geo(:,1); ph = geo(:,2);
            if strcmp(kind, 'sphere'), r = 1.02; else, r = 1.01 * app.polarRadius(D(:,1), lim); end
            held = ishold(ax); hold(ax, 'on');
            plot3(ax, r.*sind(th).*cosd(ph), r.*sind(th).*sind(ph), r.*cosd(th), 'k', 'LineWidth', 1.6, 'Tag', 'APAT_CutOverlay');
            if ~held, hold(ax, 'off'); end
        end

        function drawOverlays(app)
            if isempty(app.viewTbl), return; end
            [lim, ~] = app.plotTheme(); app.overlayCut(app.ui.full(3).ax, 'sphere', lim); app.overlayCut(app.ui.full(4).ax, 'polar', lim);
        end
    end

    %% ------------------------------------------------------------------ cuts
    methods (Access = private)
        function [cols, idx] = cutCols(app)
            % Selected traces: Total plus the co/cross pair of the active basis; idx keeps colours stable.
            u = app.ui;
            if app.isGainOnly(), cols = {app.comp()}; idx = 1; return; end
            if strcmp(u.cutBasis.Value, 'Linear'), cols = {'E_Total_dB','E_TH_dB','E_PH_dB'}; else, cols = {'E_Total_dB','E_RCP_dB','E_LCP_dB'}; end
            [u.chkCo.Text, u.chkCx.Text] = deal(erase(cols{2}, '_dB'), erase(cols{3}, '_dB'));
            sel = logical([u.chkTotal.Value u.chkCo.Value u.chkCx.Value]); if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = cols(idx);
        end

        function [ang, D, cols, ttl, geo] = cutData(app)
            % The active cut as one closed circle in the selected angular convention; geo = [physical θ, φ] per sample.
            T = app.viewTbl; u = app.ui; cols = app.cutCols(); type = string(u.cutType.Value); th = physTheta(T);
            [ang, rows, fixed, sym, snapped] = cutGeometry(T, type, u.cutValue.Value, th);
            if snapped, app.setStatus(u.status, sprintf('Requested %s cut @ %s=%g° (snapped to nearest %s=%g°)', type, sym, u.cutValue.Value, sym, fixed), false); end
            D = T{rows, cols}; geo = [th(rows) T.Phi(rows)];
            if app.isSignedPhi(), ang(ang > 180) = ang(ang > 180) - 360; [ang, o] = sort(ang); D = D(o,:); geo = geo(o,:); end
            [ang, k] = unique(ang, 'stable'); D = D(k,:); geo = geo(k,:);
            if type == "Phi"   % guarantee both seam samples so the circle closes exactly once
                edges = [0 360] - 180*app.isSignedPhi(); ext = [ang(end)-360; ang; ang(1)+360]; Dext = [D(end,:); D; D(1,:)];
                for e = edges(~ismembertol(edges, ang, 1e-9, 'DataScale', 1))
                    ang(end+1,1) = e; D(end+1,:) = interp1(ext, Dext, e); geo(end+1,:) = [geo(1,1) e]; %#ok<AGROW>
                end
                [ang, o] = sort(ang); D = D(o,:); geo = geo(o,:);
            end
            if app.isGainOnly(), ttl = char(app.compLabel()); else, ttl = sprintf('%s cut @ %s = %g°', type, sym, fixed); end
        end

        function plotCut(app)
            u = app.ui; [ang, D, cols, ttl] = app.cutData(); [~, idx] = app.cutCols(); names = replace(string(cols), "_", "\_");
            pax = u.cutPolar; rax = u.cutRect; lim = app.cutLim; xl = app.spanLimits();
            cla(pax); cla(rax); hold(pax, 'on'); hold(rax, 'on');
            pl = polarplot(pax, deg2rad(ang), max(D, lim(1)), 'LineWidth', 1.4);   % clamp: no reflection spikes below the inner RLim
            rl = plot(rax, ang, D, 'LineWidth', 1.4);
            colors = rax.ColorOrder(1 + mod(idx-1, size(rax.ColorOrder, 1)), :);
            set([pl(:); rl(:)], {'Color'}, num2cell([colors; colors], 2));
            for k = 1:numel(pl)
                rows = [dataTipTextRow("Angle", ang, '%.3g°'), dataTipTextRow("Magnitude", D(:,k), '%.3g dB')];
                pl(k).DataTipTemplate.DataTipRows = rows; rl(k).DataTipTemplate.DataTipRows = rows;
            end
            set(pax, 'RLim', lim, 'RTick', lim(1):5:lim(2)); app.polarTicks(pax);
            set(rax, 'YLim', lim, 'XLim', xl, 'XTick', xl(1):30:xl(2), 'XGrid', 'on', 'YGrid', 'on');
            xlabel(rax, [u.cutType.Value ' (degree)']); title(pax, ttl, 'Interpreter', 'none'); title(rax, ttl, 'Interpreter', 'none');
            % POB of the cut = peak of the plotted primary trace
            [pk, i] = max(D(:,1), [], 'omitnan'); u.hpbwLabel.Text = '';
            if isfinite(pk)
                rows = [dataTipTextRow("Angle", ang(i), '%.3g°'); dataTipTextRow("Magnitude", pk, '%.3g dB')];
                app.markPoint(pax, deg2rad(ang(i)), max(pk, lim(1)), [], [], rows, 'APAT_POB'); app.markPoint(rax, ang(i), pk, [], [], rows, 'APAT_POB');
            end
            % HPBW: wrap-aware shaded region and optional interpolated boundary tips
            if u.hpbwBtn.Value && isfinite(pk)
                [bw, lo, hi] = calcHPBW(ang, D(:,1), pk, ang(i));
                if isfinite(bw)
                    b = mod([lo hi] - xl(1), 360) + xl(1);   % wrap into the displayed span
                    u.hpbwLabel.Text = sprintf('HPBW\n%.1f°\n(%.1f° to %.1f°)', bw, b(1), b(2));
                    if b(1) <= b(2), reg = b; else, reg = [xl(1) b(2); b(1) xl(2)]; end
                    thetaregion(pax, deg2rad(reg(:,1)), deg2rad(reg(:,2)), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    xregion(rax, reg(:,1), reg(:,2), 'FaceColor', '#D95319', 'FaceAlpha', 0.12);
                    lbls = ["Lower HPBW", "Upper HPBW"];
                    for j = 1:2
                        rows = [dataTipTextRow(lbls(j), b(j), '%.2f°'); dataTipTextRow("Gain", pk-3, '%.2f dB')];
                        app.markPoint(pax, deg2rad(b(j)), pk-3, [], '#D95319', rows, 'APAT_HPBW'); app.markPoint(rax, b(j), pk-3, [], '#D95319', rows, 'APAT_HPBW');
                    end
                end
            end
            legend(pax, pl, names, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend(rax, rl, names, 'Location', 'best');
            hold(pax, 'off'); hold(rax, 'off'); app.setAnnotationVisibility();
        end
    end

    %% ------------------------------------------------------------------ coverage tab
    methods (Access = private)
        function toCoverage(app)
            % Coverage is always fed from the CURRENT Main view table (loss, step, span already applied).
            u = app.ui; if isempty(app.viewTbl), uialert(u.fig, 'Load and process a pattern first.', 'Coverage'); return; end
            u.tabs.SelectedTab = u.tabCov; u.covPath.Value = app.file.path; node = app.covFind(app.file.path);
            if isempty(node), app.covAddPattern(app.file.base, app.viewTbl, app.file.path, app.viewTbl);
            else, app.covSyncFromView(node); u.covTree.SelectedNodes = node; app.setCoverageUI();
            end
            app.setStatus(u.covStatus, 'Coverage source synchronized from the current Main-tab View Table.', false);
        end

        function onCovLoad(app)
            u = app.ui; fp = strtrim(u.covPath.Value);
            if isempty(fp) || ~isfile(fp) || ~isempty(app.covFind(fp))
                [f, p] = uigetfile({'*.uan;*.fz;*.out;*.ffd;*.ffe;*.ffs;*.cut;*.xlsx;*.xls;*.csv;*.dat;*.txt', 'Pattern / coverage data'; '*.*', 'All files'}, 'Select a pattern or coverage results file');
                if isequal(f, 0), return; end
                fp = fullfile(p, f);
            end
            existing = app.covFind(fp);
            if ~isempty(existing)
                u.covTree.SelectedNodes = existing; app.onCovSelection(); u.covPath.Value = fp; app.setCoverageUI();
                app.setStatus(u.covStatus, 'File already loaded -- node selected.', true); return
            end
            u.covPath.Value = fp;
            try
                out = app.readWithFormat(fp, u.covFmtLabel, u.covFmtDrop);
                if out.meta.isCoverage
                    app.covLoadResults(fp, out.raw); t = app.covTarget(); if ~isempty(t), u.covPath.Value = t.NodeData.path; end
                else
                    [~, name] = fileparts(fp); app.covAddPattern(name, app.buildPattern(out), fp, out.raw);
                end
                u.covResults.Visible = 'on';
            catch ME
                app.showError(ME, 'Coverage Load Error');
            end
        end

        function onCovFormatChanged(app)
            u = app.ui; fp = strtrim(u.covPath.Value); old = app.covFind(fp);
            if isempty(old) || ~isGenericText(fp), return; end
            try
                out = readSource(fp, u.covFmtDrop.Value);
                if out.meta.isCoverage, app.setStatus(u.covStatus, 'Coverage-result format is detected automatically; no reprocessing required.', true); return; end
                name = old.NodeData.name; for j = app.covJobs(old), delete(j.NodeData.line); end; delete(old);
                app.covAddPattern(name, app.buildPattern(out), fp, out.raw); app.covFinalize();
                app.setStatus(u.covStatus, sprintf('Pattern <b>"%s"</b> reprocessed with the selected format.', name), true);
            catch ME
                app.showError(ME, 'Coverage Format Error');
            end
        end

        function covLoadResults(app, fp, T)
            [~, name] = fileparts(fp); u = app.ui;
            node = uitreenode(u.covRoot, 'Text', ['📄 ' name], 'NodeData', struct('kind', 'results', 'name', name, 'path', fp));
            u.covTree.CheckedNodes = [u.covTree.CheckedNodes; node]; thr = T{:,1};
            app.setCovXRange([min(thr) max(thr)], gridStep(thr));
            for k = 2:width(T), app.covAddJob(node, thr, T{:,k}, 'Res', T.Properties.VariableNames{k}, false, "n/a"); end
            app.covFinalize(node); u.covResults.Visible = 'on';
            app.setStatus(u.covStatus, sprintf('Coverage results file "%s" loaded (%d curves).', name, width(T)-1), false);
        end

        function node = covAddPattern(app, name, T, fp, raw)
            u = app.ui;
            d = struct('kind', 'pattern', 'name', name, 'path', fp, 'pattern', T, 'raw', raw, 'omega', solidWeights(physTheta(T), T.Phi), ...
                'component', "", 'boresight', 1, 'cache', struct(), 'rev', 0);
            node = uitreenode(u.covRoot, 'Text', ['📡 ' name], 'NodeData', d);
            expand(u.covTree); u.covTree.CheckedNodes = [u.covTree.CheckedNodes; node]; u.covTree.SelectedNodes = node;
            app.covSync(node);
            set([u.covCompute u.covReset u.covComp u.covCompLabel], 'Enable', 'on'); app.setCoverageUI(); u.covResults.Visible = 'on';
            app.setStatus(u.covStatus, sprintf('Pattern "<b>%s</b>" added — ready to compute coverage.', name), false);
        end

        function covSyncFromView(app, node)
            d = node.NodeData; T = app.viewTbl;
            d.pattern = T; d.raw = T; d.omega = app.omega; d.rev = app.viewRev; d.name = app.file.base; node.NodeData = d;
            app.covSync(node);
        end

        function covSync(app, node)
            % Align the component list/orientation with the node and apply the automatic threshold preset once per (pattern, component, view).
            u = app.ui; d = node.NodeData; T = d.pattern; [cols, labels] = componentMap(T);
            prev = d.component; if prev == "", prev = string(u.covComp.Value); end
            c = preferredComponent(prev, cols);
            if ~isequal(string(u.covComp.ItemsData), cols), [u.covComp.Items, u.covComp.ItemsData] = deal(cellstr(labels), cellstr(cols)); end
            u.covComp.Value = c; changed = d.component ~= string(c);
            if changed
                [~, d.boresight] = calcOrientation(T, d.omega, c, app.Axes, app.PeakPct, app.PeakExcess); d.component = string(c); node.NodeData = d;
            end
            key = string(sprintf('%s|%s|%d', d.path, c, d.rev));
            if app.covPresetKey ~= key
                b = displayRange(T.(c), app.PeakPct, app.PeakExcess);
                if app.covPresetKey ~= "", b = [min(u.thrMin.Value, b(1)) max(u.thrMax.Value, b(2))]; end   % later presets only widen
                app.covPresetKey = key; app.setSpinnerPair(u.thrMin, u.thrMax, b, 0.1);
            end
            if changed && u.orient.Value == 0, app.onOrientationChanged(); end
        end

        function thr = covThresholds(app)
            % The user's CURRENT threshold controls, verbatim (presets are applied only by covSync).
            u = app.ui; lo = u.thrMin.Value; hi = u.thrMax.Value; st = max(u.thrStep.Value, 0.1);
            if hi <= lo, hi = min(app.DBRange(2), lo + st); u.thrMax.Value = hi; end
            thr = (lo:st:hi)'; if isempty(thr) || thr(end) < hi, thr(end+1,1) = hi; end
        end

        function onCovCompute(app)
            u = app.ui; node = app.covTarget();
            if isempty(node), uialert(u.fig, 'Load (or select) an antenna pattern node first.', 'Compute Coverage'); return; end
            if strcmp(node.NodeData.path, app.file.path) && ~isempty(app.viewTbl), app.covSyncFromView(node); end
            try
                d = node.NodeData; T = d.pattern; c = u.covComp.Value; thr = app.covThresholds(); conical = u.covConical.Value; orient = "n/a";
                if conical
                    th0 = u.coneTh.Value; ph0 = mod(u.conePh.Value, 360); cone = u.coneAng.Value; pt = physTheta(T);
                    mask = cosd(pt).*cosd(th0) + sind(pt).*sind(th0).*cosd(T.Phi - ph0) >= cosd(cone);
                    k = u.orient.Value; if k == 0, k = d.boresight; end; orient = string(app.Axes.labels{k});
                    tag = sprintf('Con %s α%s°', app.coneLabel(th0, ph0), fmtNum(cone));
                else
                    mask = true(height(T), 1); tag = 'Sph';
                end
                key = matlab.lang.makeValidName(sprintf('%s_%d_%s_%g_%g_%g_%d', c, d.rev, tag, thr(1), thr(end), gridStep(thr), numel(thr)));
                hit = isfield(d.cache, key);
                if hit, cov = d.cache.(key); else, cov = coverageCCDF(T.(c), mask, thr, d.omega); d.cache.(key) = cov; node.NodeData = d; end
                app.covAddJob(node, thr, cov, tag, c, conical, orient); app.covFinalize(node);
                app.setCovXRange([thr(1) thr(end)]); u.covResults.Visible = 'on';
                act = {'computed', 'reused cached CCDF'};
                msg = sprintf('Run-<b>%d</b> %s: <b>%s</b> on <b>"%s"</b> (%s, %d thresholds).', app.covRunID, act{1 + hit}, tag, d.name, c, numel(thr));
                if conical, msg = sprintf('%s | Orientation <b>%s</b>', msg, orient); end
                app.setStatus(u.covStatus, msg, false);
            catch ME
                app.showError(ME, 'Coverage Error');
            end
        end

        function node = covAddJob(app, parent, thr, cov, tag, compName, conical, orient)
            u = app.ui; app.covRunID = app.covRunID + 1; icon = '📉'; if strcmp(tag, 'Res'), icon = '📈'; end
            label = sprintf('%s R%d %s · %s', icon, app.covRunID, tag, compName);
            ln = plot(u.covAxes, thr, cov, 'LineWidth', 1.6, 'DisplayName', label);
            ln.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", 'XData', '%.2f dB'); dataTipTextRow("Coverage", 'YData', '%.2f%%')];
            node = uitreenode(parent, 'Text', label, 'NodeData', struct('kind', 'job', 'id', app.covRunID, 'tag', tag, 'thr', thr(:), 'cov', cov(:), ...
                'line', ln, 'label', label, 'conical', conical, 'orientation', string(orient)));
            u.covTree.CheckedNodes = [u.covTree.CheckedNodes; node];
        end

        function covFinalize(app, node)
            % Rebuild the results table (union of thresholds, one column per checked job) and the legend.
            u = app.ui; if nargin > 1, expand(node); end; expand(u.covRoot);
            jobs = app.covJobs(); checked = jobs(ismember(jobs, u.covTree.CheckedNodes));
            if isempty(checked)
                u.covTable.Data = table(); legend(u.covAxes, 'off');
            else
                nd = [checked.NodeData]; thr = unique(vertcat(nd.thr));
                vals = [thr, cell2mat(arrayfun(@(d) interp1(d.thr, d.cov, thr, 'linear', NaN), nd, 'UniformOutput', false))];
                names = [{'Threshold (dB)'}, arrayfun(@(d) sprintf('R%d %s %%', d.id, d.tag), nd, 'UniformOutput', false)];
                u.covTable.Data = array2table(compose('%.2f', vals), 'VariableNames', names);
                legend(u.covAxes, [nd.line], {nd.label}, 'Location', 'southwest', 'Interpreter', 'none');
            end
            app.setCoverageUI();
        end

        function jobs = covJobs(app, root)
            % Job nodes (ordered by run id) below ROOT; the tree is the single source of truth.
            if nargin < 2, root = app.ui.covRoot; end
            nodes = findobj(root); jobs = nodes(arrayfun(@(n) isstruct(n.NodeData) && strcmp(n.NodeData.kind, 'job'), nodes));
            jobs = reshape(jobs, 1, []); if numel(jobs) > 1, [~, o] = sort(arrayfun(@(n) n.NodeData.id, jobs)); jobs = jobs(o); end
        end

        function node = covTarget(app)
            % Pattern node to operate on: the selection (or its pattern ancestor), else the most recently added pattern.
            node = []; sel = app.ui.covTree.SelectedNodes;
            if ~isempty(sel)
                n = sel(1);
                while isa(n, 'matlab.ui.container.TreeNode')
                    if isstruct(n.NodeData) && strcmp(n.NodeData.kind, 'pattern'), node = n; return; end
                    n = n.Parent;
                end
            end
            kids = app.ui.covRoot.Children;
            for k = numel(kids):-1:1
                if isstruct(kids(k).NodeData) && strcmp(kids(k).NodeData.kind, 'pattern'), node = kids(k); return; end
            end
        end

        function node = covFind(app, fp)
            node = []; kids = app.ui.covRoot.Children;
            for k = 1:numel(kids)
                if isstruct(kids(k).NodeData) && strcmp(kids(k).NodeData.path, fp), node = kids(k); return; end
            end
        end

        function setCoverageUI(app)
            u = app.ui; hasPattern = ~isempty(app.covTarget()); hasJobs = ~isempty(app.covJobs());
            mode = "empty"; if hasPattern, mode = "pattern"; elseif hasJobs, mode = "results"; end
            if mode ~= app.covMode
                app.covMode = mode; kids = u.covParamGrid.Children;
                if mode == "pattern", set(kids, 'Visible', 'on', 'Enable', 'on');
                else
                    set(kids, 'Visible', 'off'); set([u.covPathLabel u.covPath u.covLoad u.covCompute], 'Visible', 'on', 'Enable', 'on');
                    if mode == "results", set([app.queryControls() u.covReset u.covExport u.covClear u.covToMain], 'Visible', 'on', 'Enable', 'on'); end
                end
            end
            if mode == "pattern"
                set([u.covExport u.covClear app.queryControls()], 'Enable', hasJobs); app.onCovTypeChanged();
                generic = isGenericText(u.covPath.Value); set([u.covFmtLabel u.covFmtDrop], 'Visible', generic, 'Enable', generic);
            end
        end

        function onCovTypeChanged(app)
            u = app.ui; on = u.covConical.Value;
            set([u.coneTh u.conePh u.coneAng u.coneThLabel u.conePhLabel u.coneAngLabel u.orient u.orientLabel], 'Enable', on, 'Visible', on);
            if on, t = app.covTarget(); if ~isempty(t), app.covSync(t); end; app.reportOrientation();
            else, u.covStatus.Text = regexprep(char(u.covStatus.Text), '\s*\|\s*Orientation <b>.*?</b>', '');
            end
        end

        function reportOrientation(app)
            % Append the resolved conical orientation (Auto → detected boresight) to the current Coverage status.
            u = app.ui; if ~u.covConical.Value, return; end
            k = u.orient.Value; if k == 0, t = app.covTarget(); if isempty(t), return; end; k = t.NodeData.boresight; end
            msg = regexprep(char(u.covStatus.Text), '\s*\|\s*Orientation <b>.*?</b>$', '');
            app.setStatus(u.covStatus, sprintf('%s | Orientation <b>%s</b>', msg, app.Axes.labels{k}), false);
        end

        function onOrientationChanged(app)
            u = app.ui; k = u.orient.Value;
            if k == 0, t = app.covTarget(); if isempty(t), return; end; k = t.NodeData.boresight; end
            [u.coneTh.Value, u.conePh.Value] = deal(app.Axes.theta(k), app.Axes.phi(k)); app.reportOrientation();
        end

        function onCovComponentChanged(app)
            % The user's component choice is authoritative: refresh orientation only (no threshold re-preset here).
            t = app.covTarget(); if isempty(t), return; end
            d = t.NodeData; c = app.ui.covComp.Value; if ~ismember(c, d.pattern.Properties.VariableNames), return; end
            d.component = string(c); [~, d.boresight] = calcOrientation(d.pattern, d.omega, c, app.Axes, app.PeakPct, app.PeakExcess); t.NodeData = d;
            app.reportOrientation();
        end

        function s = coneLabel(app, th, ph)
            % Principal-axis name when the cone centre is exactly ±X/±Y/±Z, otherwise the spherical coordinates.
            a = app.Axes; A = [sind(a.theta(:)).*cosd(a.phi(:)), sind(a.theta(:)).*sind(a.phi(:)), cosd(a.theta(:))];
            k = find(A * [sind(th)*cosd(ph); sind(th)*sind(ph); cosd(th)] >= 1 - 1e-9, 1);
            if isempty(k), s = sprintf('θ%s° φ%s°', fmtNum(th), fmtNum(ph)); else, s = a.labels{k}; end
        end

        function covQuery(app, mode)
            % Project a threshold ("cov") or a coverage level ("thr") onto every checked job below the selected node.
            u = app.ui; ax = u.covAxes; sel = u.covTree.SelectedNodes;
            if isempty(sel), app.setStatus(u.covStatus, 'Select a node to query.', true); return; end
            jobs = app.covJobs(sel(1)); jobs = jobs(ismember(jobs, u.covTree.CheckedNodes));
            if isempty(jobs), app.setStatus(u.covStatus, 'No checked results under selected node.', true); return; end
            if mode == "cov", q = u.qCov.Value; else, q = u.qThr.Value; end
            hit = false;
            for j = jobs
                d = j.NodeData; tag = sprintf('CovQ_%s_%d', mode, d.id); delete(findall(ax, 'Tag', tag)); delete(findall(d.line, 'Tag', tag));
                [x, y] = covQueryPoint(d.thr, d.cov, mode, q); if ~isfinite(x) || ~isfinite(y), continue; end
                line(ax, [x x], [ax.YLim(1) y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                line(ax, [app.DBRange(1) x], [y y], 'Color', d.line.Color, 'LineStyle', ':', 'HandleVisibility', 'off', 'Tag', tag);
                tip = datatip(d.line, x, y, 'SnapToDataVertex', 'off', 'FontSize', 9, 'HandleVisibility', 'off'); tip.Tag = tag; hit = true;
            end
            if ~hit,             app.setStatus(u.covStatus, 'Query value is outside the selected checked range.', true);
            elseif mode == "cov", app.setStatus(u.covStatus, sprintf('Coverage queried at %s dB.', fmtNum(q)), false);
            else,                app.setStatus(u.covStatus, sprintf('Threshold queried at %s%% coverage.', fmtNum(q)), false);
            end
        end

        function onCovChecked(app)
            u = app.ui; checked = u.covTree.CheckedNodes;
            for j = app.covJobs()
                d = j.NodeData; on = ismember(j, checked); d.line.Visible = on;
                set([findall(u.covAxes, '-regexp', 'Tag', sprintf('^CovQ_\\w+_%d$', d.id)); findall(d.line, 'Type', 'datatip')], 'Visible', on);
            end
            app.covFinalize();
        end

        function onCovSelection(app)
            u = app.ui; sel = u.covTree.SelectedNodes;
            for j = app.covJobs(), ln = j.NodeData.line; ln.LineWidth = 1.6; end
            if isempty(sel) || ~isstruct(sel(1).NodeData), app.setStatus(u.covStatus, 'Ready.', false); return; end
            d = sel(1).NodeData; t = app.covTarget(); if ~isempty(t), app.covSync(t); end
            if ~strcmp(d.kind, 'job')
                n = numel(sel(1).Children); kinds = struct('results', 'Results', 'pattern', 'Pattern');
                app.setStatus(u.covStatus, sprintf('%s <b>"%s"</b> -- <b>%d</b> coverage job%s.', kinds.(d.kind), d.name, n, repmat('s', 1, double(n ~= 1))), false);
                if strcmp(d.kind, 'pattern'), app.reportOrientation(); end
                return
            end
            d.line.LineWidth = 2.6;   % selection = visual emphasis only; checked state controls visibility
            x50 = covQueryPoint(d.thr, d.cov, "thr", 50); shown = round(d.cov, 2); mx = max(shown); i = find(shown == mx, 1, 'last');
            parts = {char(d.label)};
            if d.conical, parts{end+1} = sprintf('Orientation <b>%s</b>', d.orientation); end
            parts{end+1} = sprintf('Threshold [%s, %s] dB, step %s dB', fmtNum(d.thr(1)), fmtNum(d.thr(end)), fmtNum(gridStep(d.thr)));
            if isfinite(x50), parts{end+1} = sprintf('<b>50%%</b>-coverage threshold <b>%s dB</b>', fmtNum(x50)); else, parts{end+1} = '<b>50%-coverage unavailable</b>'; end
            parts{end+1} = sprintf('max <b>%s%%</b> @ <b>%s dB</b>', fmtNum(mx), fmtNum(d.thr(i)));
            app.setStatus(u.covStatus, strjoin(parts, ' | '), false);
        end

        function onCovReset(app)
            u = app.ui; delete(u.covRoot.Children);
            cla(u.covAxes); legend(u.covAxes, 'off'); hold(u.covAxes, 'on'); grid(u.covAxes, 'on'); ylim(u.covAxes, [0 100]); u.covAxes.XLimMode = 'auto';
            u.covTable.Data = table(); app.covRunID = 0; app.covPresetKey = ""; app.covMode = "";
            set([u.covCompute u.covExport u.covClear u.qCovBtn u.qThrBtn u.covReset], 'Enable', 'off'); u.covResults.Visible = 'off';
            u.covXRange.Limits = app.DBRange; u.covXRange.Value = [-40 10]; app.setSpinnerPair(u.covXMin, u.covXMax, [-40 10], 0);
            app.setCoverageUI(); app.setStatus(u.covStatus, 'Coverage workspace reset 🔄', true);
        end

        function onCovClear(app)
            u = app.ui; sel = u.covTree.SelectedNodes;
            if isempty(sel), app.setStatus(u.covStatus, 'Select a node to clear.', true); return; end
            for j = app.covJobs(sel(1))
                delete(findall(u.covAxes, '-regexp', 'Tag', sprintf('^CovQ_\\w+_%d$', j.NodeData.id))); delete(findall(j.NodeData.line, 'Type', 'datatip'));
            end
            app.setStatus(u.covStatus, 'Selected DataTips and query markers cleared.', true);
        end

        function onCovExport(app)
            if ~isempty(app.ui.covTable.Data), app.exportTable(app.ui.covTable.Data, 'coverage_results.csv', 'Coverage results', app.ui.covStatus); end
        end

        function setCovXRange(app, b, step)
            % The first result establishes the X baseline; later results may only widen it.
            u = app.ui; b = clampRange(b, app.DBRange);
            if strcmp(u.covAxes.XLimMode, 'manual'), b = [min(u.covAxes.XLim(1), b(1)) max(u.covAxes.XLim(2), b(2))]; end
            u.covAxes.XLim = b; u.covXRange.Limits = app.DBRange; u.covXRange.Value = b; u.covXRange.Limits = b;
            app.setSpinnerPair(u.covXMin, u.covXMax, b, 0.1);
            if nargin > 2 && isfinite(step) && step < u.thrStep.Value, u.thrStep.Value = step; end
        end

        function onCovXRange(app, src, value)
            % Spinners are the master (they define the slider travel); the slider only moves within it.
            u = app.ui; if nargin < 3, value = src.Value; end
            if src == u.covXRange
                v = sort(double(value)); if diff(v) <= 0, return; end
                [u.covXMin.Value, u.covXMax.Value] = deal(v(1), v(2)); u.covAxes.XLim = v; return
            end
            b = sort([u.covXMin.Value u.covXMax.Value]);
            if diff(b) <= 0, if src == u.covXMin, b(2) = min(app.DBRange(2), b(1) + 0.1); else, b(1) = max(app.DBRange(1), b(2) - 0.1); end, end
            u.covXRange.Limits = app.DBRange; u.covXRange.Value = b; u.covXRange.Limits = b;
            app.setSpinnerPair(u.covXMin, u.covXMax, b, 0.1); u.covAxes.XLim = b;
        end

        function setSpinnerPair(app, lo, hi, b, gap)
            set([lo hi], 'Limits', app.DBRange); lo.Value = b(1); hi.Value = b(2);
            lo.Limits = [app.DBRange(1) b(2)-gap]; hi.Limits = [b(1)+gap app.DBRange(2)];
        end
    end

    %% ------------------------------------------------------------------ export, status, errors
    methods (Access = private)
        function exportResults(app)
            if ~isempty(app.viewTbl), app.exportTable(app.ui.tableOut.Data, [app.file.base '_APAT_results.csv'], 'Results', app.ui.status); end
        end

        function exportCut(app)
            if isempty(app.viewTbl), return; end
            [ang, D, cols, ttl] = app.cutData();
            app.exportTable(array2table([ang D], 'VariableNames', [{'Angle_deg'} cols]), [app.file.base '_cut.csv'], ['Cut (' ttl ')'], app.ui.status);
        end

        function exportUAN(app)
            if app.isGainOnly(), uialert(app.ui.fig, 'No E-field data to export.', 'Export UAN'); return; end
            V = app.viewTbl; r5 = @(c) round(V.(c), 5);
            U = sortrows(table(physTheta(V), V.Phi, r5('E_TH_dB'), r5('E_PH_dB'), r5('E_TH_Phase'), r5('E_PH_Phase'), ...
                'VariableNames', {'Theta','Phi','E_TH_DB','E_PH_DB','E_TH_DG','E_PH_DG'}), {'Phi','Theta'});
            ts = gridStep(U.Theta); if ~isfinite(ts), ts = 1; end; ps = gridStep(mod(U.Phi, 360)); if ~isfinite(ps), ps = ts; end
            gmax = max([U.E_TH_DB; U.E_PH_DB], [], 'omitnan');
            header = sprintf(['begin_<parameters>\nformat free\nphi_min %g\nphi_max %g\nphi_inc %g\ntheta_min %g\ntheta_max %g\ntheta_inc %g\n' ...
                'complex\nmag_phase\npattern gain\nmagnitude dB\nmaximum_gain %.5f\nphase degrees\ndirection degrees\npolarization theta_phi\nend_<parameters>'], ...
                min(U.Phi), max(U.Phi), ps, min(U.Theta), max(U.Theta), ts, gmax);
            app.exportTable(U, sprintf('%s_%.5f_%gdeg.uan', app.file.base, gmax, ts), 'UAN', app.ui.status, header);
        end

        function exportTable(app, T, defaultName, label, statusBar, uanHeader)
            filters = {'*.csv', 'Comma-delimited text (*.csv)'; '*.txt', 'Tab-delimited text (*.txt)'; '*.xlsx', 'Excel (*.xlsx)'};
            if nargin > 5, filters = [{'*.uan', 'XGTD user-defined antenna (*.uan)'}; filters(1:2,:)]; else, uanHeader = ''; end
            [f, p] = uiputfile(filters, ['Export ' label], fullfile(app.file.folder, defaultName));
            if isequal(f, 0), return; end
            try
                fp = fullfile(p, f); writeTable(T, fp, uanHeader);
                app.setStatus(statusBar, sprintf('%s exported to <b>%s</b>', label, fp), true);
            catch ME
                app.showError(ME, ['Export ' label ' Error']);
            end
        end

        function setStatus(app, label, msg, transient)
            % Persistent messages are remembered in UserData; transient ones revert after 3 s (one timer per app).
            if app.isClosing || ~isgraphics(label), return; end
            app.stopStatusTimer(); label.Text = char(msg);
            if ~transient, label.UserData = char(msg); return; end
            app.statusTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 3, 'TimerFcn', @(~,~) app.restoreStatus(label), 'StopFcn', @(t,~) delete(t));
            start(app.statusTimer);
        end

        function restoreStatus(app, label)
            if ~app.isClosing && isgraphics(label), label.Text = label.UserData; end
        end

        function stopStatusTimer(app)
            t = app.statusTimer; app.statusTimer = [];
            if ~isempty(t) && isvalid(t), stop(t); end
        end

        function showError(app, ME, ttl)
            if app.isClosing, return; end
            loc = ''; if ~isempty(ME.stack), loc = sprintf('\n(%s line %d)', ME.stack(1).name, ME.stack(1).line); end
            uialert(app.ui.fig, [ME.message loc], ttl, 'Icon', 'error');
        end

        function checkCancelled(app)
            d = app.opDialog;
            if ~isempty(d) && isvalid(d) && d.CancelRequested, error('APAT:Cancelled', 'Operation cancelled by user.'); end
        end
    end
end

%% ====================================================================== I/O services (UI-free)
function tf = isGenericText(fp)
[~, ~, e] = fileparts(fp); tf = any(strcmpi(e, {'.csv','.txt','.dat'}));
end

function out = readSource(fp, textFormat)
%readSource Read any supported pattern/coverage file into {raw, blocks, freqs, meta}.
%   blocks{k} are canonical tables {Theta,Phi,Re_Eth,Im_Eth,Re_Eph,Im_Eph} (or a gain-only table).
[~, ~, ext] = fileparts(fp); ext = upper(erase(ext, '.'));
out = struct('raw', table(), 'blocks', {{}}, 'freqs', NaN, 'meta', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false, 'hasFrequency', false));
switch ext
    case {'XLSX','XLS'},      out = readExcelMatrix(fp); return
    case {'CSV','TXT','DAT'}, out = readGenericText(fp, string(textFormat), out); return
    case 'CUT',               out = readGraspCut(fp, out); return
end
% Column-oriented far-field exports (one direction per row)
[nHdr, ffd] = findHeaderLines(fp);
opts = detectImportOptions(fp, 'FileType', 'text', 'NumHeaderLines', nHdr, 'Delimiter', {' ','\t',',',';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
M = readmatrix(fp, setvartype(opts, opts.VariableNames, 'double')); M = M(~all(isnan(M), 2), :);
if strcmp(ext, 'FFD')   % HFSS: header defines the grid; data are Re/Im pairs, optional "Frequency f" separator rows between blocks
    out.meta.source = 'HFSS FFD'; assert(ffd.isFFD, 'readFile:ffd', 'FFD header (theta/phi ranges) not found.');
    th = linspace(ffd.theta(1), ffd.theta(2), ffd.theta(3)).'; ph = linspace(ffd.phi(1), ffd.phi(2), ffd.phi(3)).';
    theta = repelem(th, numel(ph)); phi = repmat(ph, numel(th), 1); n = numel(theta);
    sep = isnan(M(:,1)); freqs = [ffd.freq(:); M(sep & ~isnan(M(:,2)), 2)].'; F = M(~sep, 1:4);
    assert(mod(size(F,1), n) == 0, 'readFile:ffd', 'FFD row count does not match the theta/phi grid.');
    nb = size(F,1)/n; freqs(end+1:nb) = NaN; freqs = freqs(1:nb);
    out.meta.hasFrequency = any(isfinite(freqs)); out.meta.isDep = nb > 1 || out.meta.hasFrequency; out.freqs = freqs;
    out.blocks = cellfun(@(B) fieldTable(theta, phi, complex(B(:,1), B(:,2)), complex(B(:,3), B(:,4))), mat2cell(F, repmat(n, nb, 1), 4), 'UniformOutput', false);
    out.raw = out.blocks{1}; return
end
assert(size(M,2) >= 6, 'readFile:columns', 'Expected six numeric columns in %s.', fp); M = M(:, 1:6);
switch ext
    case {'FZ','UAN'}   % XGTD: Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg
        src = ['XGTD ' ext]; names = {'Theta','Phi','E_TH_dB','E_PH_dB','E_TH_deg','E_PH_deg'}; ang = M(:,1:2);
        Eth = dbPhase(M(:,3), M(:,5)); Eph = dbPhase(M(:,4), M(:,6));
    case 'OUT'          % TICRA/GRASP: Theta Phi Re/Im(POL1=RHCP) Re/Im(POL2=LHCP)
        src = 'TICRA/GRASP OUT'; names = {'Theta','Phi','Re_RHCP','Im_RHCP','Re_LHCP','Im_LHCP'}; ang = M(:,1:2);
        [Eth, Eph] = circToLin(complex(M(:,3), M(:,4)), complex(M(:,5), M(:,6)));
    case 'FFS'          % CST: Phi Theta Re/Im(E-TH) Re/Im(E-PH)
        src = 'CST FFS'; names = {'Phi','Theta','Re_Eth','Im_Eth','Re_Eph','Im_Eph'}; ang = M(:,[2 1]);
        Eth = complex(M(:,3), M(:,4)); Eph = complex(M(:,5), M(:,6));
    case 'FFE'          % FEKO: Theta Phi Re/Im(E-TH) Re/Im(E-PH) (extra columns ignored)
        src = 'FEKO FFE'; names = {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'}; ang = M(:,1:2);
        Eth = complex(M(:,3), M(:,4)); Eph = complex(M(:,5), M(:,6));
    otherwise, error('readFile:unsupported', 'Unsupported format: %s', ext);
end
out.meta.source = src; out.raw = array2table(M, 'VariableNames', names); out.blocks = {fieldTable(ang(:,1), ang(:,2), Eth, Eph)};
end

function E = dbPhase(magDB, phaseDeg), E = 10.^(magDB/20) .* exp(1i*deg2rad(phaseDeg)); end
function [Eth, Eph] = circToLin(Ercp, Elcp), Eth = (Ercp + Elcp)/sqrt(2); Eph = (Ercp - Elcp)/(1i*sqrt(2)); end
function T = fieldTable(theta, phi, Eth, Eph)
T = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'});
end

function [nHdr, ffd] = findHeaderLines(fp)
%findHeaderLines Count leading non-data lines; recognise the HFSS FFD header (two numeric triples + optional 'Frequencies').
fid = fopen(fp, 'r'); assert(fid > 0, 'apat:io:OpenFailed', 'Cannot open file: %s', fp); c = onCleanup(@() fclose(fid)); %#ok<NASGU>
lines = strings(0, 1); while numel(lines) < 200, l = fgetl(fid); if ~ischar(l), break; end; lines(end+1, 1) = string(l); end %#ok<AGROW>
ffd = struct('isFFD', false, 'theta', [], 'phi', [], 'freq', []); ne = find(strlength(strtrim(lines)) > 0);
triples = cellfun(@(s) sscanf(s, '%f').', cellstr(lines(ne(1:min(2, end)))), 'UniformOutput', false);
if numel(triples) == 2 && all(cellfun(@numel, triples) == 3)
    ffd.theta = triples{1}; ffd.phi = triples{2}; ffd.theta(3) = round(ffd.theta(3)); ffd.phi(3) = round(ffd.phi(3));
    ffd.isFFD = all(isfinite([ffd.theta ffd.phi])) && ffd.theta(3) >= 1 && ffd.phi(3) >= 1; nHdr = ne(2);
    if numel(ne) >= 3   % "Frequencies N" (count only) or "Frequencies f1 f2 ..."; singular "Frequency f" rows stay in the data section
        tok = regexp(char(strtrim(lines(ne(3)))), '^frequencies\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok), v = sscanf(tok{1}, '%f'); if ~isscalar(v), ffd.freq = v(:); end; nHdr = ne(3); end
    end
    if ffd.isFFD, return; end
end
num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?';   % first line with ≥4 numeric fields starts the data
isData = ~cellfun(@isempty, regexp(cellstr(lines), ['^\s*' num '(?:[\s,;]+' num '){3,}\s*$'], 'once'));
nHdr = find(isData, 1) - 1; if isempty(nHdr), nHdr = 0; end
end

function out = readGenericText(fp, fmt, out)
%readGenericText CSV/TXT/DAT: coverage results (auto-detected), gain-only pattern, or a six-column E-field table.
opts = detectImportOptions(fp, 'FileType', 'text', 'Delimiter', {' ','\t',',',';'}, 'ConsecutiveDelimitersRule', 'join', 'LeadingDelimitersRule', 'ignore');
opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true); opts.VariableNamingRule = 'preserve';
T = rmmissing(readtable(fp, opts)); n = width(T); raw = T;
assert(n >= 2 && height(T) > 0, 'readFile:InvalidFormat', 'File needs at least two numeric columns.');
names = lower(string(T.Properties.VariableNames)); hasHeaders = ~all(startsWith(names, "var")); c1 = T{:,1}; c2 = T{:,2};
covHeader = contains(names(1), "threshold") || any(contains(names(2:end), "coverage"));
if (fmt == "gain" || n < 6 || covHeader) && all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~hasHeaders, T.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:n-1))]; end
    out.raw = T; out.meta.isCoverage = true; return
end
if fmt == "gain"   % the wider-spanning angle column is phi
    if max(c1) - min(c1) > max(c2) - min(c2), T.Properties.VariableNames(1:2) = {'Phi','Theta'}; T = movevars(T, 'Theta', 'Before', 1);
    else, T.Properties.VariableNames(1:2) = {'Theta','Phi'};
    end
    if ~hasHeaders, raw = T; end
    out.raw = raw; out.blocks = {T}; out.meta.isGainOnly = true; out.meta.source = 'Generic text (gain)'; return
end
assert(n >= 6, 'readFile:TextEFieldColumns', 'The selected generic E-field format requires six numeric columns.');
V = T{:,3:6}; layout = "not applicable";
if endsWith(fmt, "magphase")
    big = max(abs(V), [], 1, 'omitnan') > 100;   % phase columns exceed 100 (degrees); detect grouped vs interleaved layout
    if big(2) && ~big(3), m = [1 3]; p = [2 4]; layout = "interleaved"; else, m = [1 2]; p = [3 4]; layout = "grouped"; end
    C1 = dbPhase(V(:,m(1)), V(:,p(1))); C2 = dbPhase(V(:,m(2)), V(:,p(2)));
else
    C1 = complex(V(:,1), V(:,2)); C2 = complex(V(:,3), V(:,4));
end
if startsWith(fmt, "linear"), Eth = C1; Eph = C2; elseif startsWith(fmt, "rcp"), [Eth, Eph] = circToLin(C1, C2); else, [Eth, Eph] = circToLin(C2, C1); end
if ~hasHeaders
    if startsWith(fmt, "linear"), cn = ["E_TH","E_PH"]; else, cn = ["POL1","POL2"]; end
    if endsWith(fmt, "magphase"), fn = [cn + "_dB", cn + "_deg"]; if layout == "interleaved", fn = fn([1 3 2 4]); end, else, fn = [cn(1) + ["_re","_im"], cn(2) + ["_re","_im"]]; end
    raw.Properties.VariableNames(1:6) = cellstr(["Theta", "Phi", fn]);
end
out.meta.source = sprintf('Generic text (%s, %s)', fmt, layout); out.raw = raw; out.blocks = {fieldTable(c1, c2, Eth, Eph)};
end

function out = readGraspCut(fp, out)
%readGraspCut TICRA/GRASP *.cut: repeated [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data] blocks (one φ per block).
out.meta.source = 'TICRA/GRASP CUT'; L = readlines(fp); L(strlength(strtrim(L)) == 0) = [];
th = {}; ph = {}; D = {}; i = 1;
while i < numel(L)
    h = sscanf(L(i+1), '%f'); assert(numel(h) >= 7, 'parseCutFile:bad', 'Could not parse cut parameter line.');
    n = h(3); B = reshape(sscanf(strjoin(L(i+2:i+1+n), ' '), '%f'), 2*h(7), []).';
    th{end+1} = h(1) + (0:n-1)'*h(2); ph{end+1} = repmat(h(4), n, 1); D{end+1} = B(:,1:4); i = i + 2 + n; %#ok<AGROW>
end
theta = vertcat(th{:}); phi = vertcat(ph{:}); D = vertcat(D{:});
if h(6) == 2, [theta, phi] = deal(phi, theta); end                        % ICUT=2: φ swept, θ constant
neg = theta < 0; phi(neg) = phi(neg) + 180; theta(neg) = -theta(neg);     % fold negative θ onto the opposite φ
if isscalar(unique(phi))                                                 % single cut → body of revolution
    theta = repmat(theta, 36, 1); phi = repelem((0:10:350)', numel(phi)); D = repmat(D, 36, 1);
end
C1 = complex(D(:,1), D(:,2)); C2 = complex(D(:,3), D(:,4));
if h(5) == 2, names = {'Re_RHCP','Im_RHCP','Re_LHCP','Im_LHCP'}; [Eth, Eph] = circToLin(C1, C2);
else,         names = {'Re_Eth','Im_Eth','Re_Eph','Im_Eph'};     Eth = C1; Eph = C2;
end
out.raw = array2table([theta phi D], 'VariableNames', [{'Theta','Phi'} names]); out.blocks = {fieldTable(theta, phi, Eth, Eph)};
end

function out = readExcelMatrix(fp)
%readExcelMatrix Excel matrix templates: summary sheet + fixed component sheets (Eth/Eph and/or RHCP/LHCP as dBi + degrees).
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi","RHCP_Phase_degrees","LHCP_Gain_dBi","LHCP_Phase_degrees"]; lin = ["Etheta_Gain_dBi","Etheta_Phase_degrees","Ephi_Gain_dBi","Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets))); hasL = all(ismember(lower(lin), lower(sheets)));
assert(hasC || hasL, 'readFile:ExcelMatrixFormat', 'Unsupported Excel workbook: expected Etheta/Ephi and/or RHCP/LHCP component sheets after the summary sheet.');
req = [circ(1:4*hasC) lin(1:4*hasL)]; M = struct();
for k = 1:numel(req)
    [th, ph, data] = readExcelMatrixSheet(fp, sheets(find(strcmpi(sheets, req(k)), 1)));
    if k == 1, thRef = th; phRef = ph;
    else, assert(isequal(size(th), size(thRef)) && isequal(size(ph), size(phRef)) && max(abs(th - thRef)) < 1e-9 && max(abs(ph - phRef)) < 1e-9, 'readFile:ExcelMatrixGrid', 'All component sheets must share one theta/phi grid.');
    end
    M.(char(req(k))) = data;
end
[PH, TH] = meshgrid(phRef, thRef);
if hasL, Eth = dbPhase(M.Etheta_Gain_dBi, M.Etheta_Phase_degrees); Eph = dbPhase(M.Ephi_Gain_dBi, M.Ephi_Phase_degrees);
else,    [Eth, Eph] = circToLin(dbPhase(M.RHCP_Gain_dBi, M.RHCP_Phase_degrees), dbPhase(M.LHCP_Gain_dBi, M.LHCP_Phase_degrees));
end
block = fieldTable(TH, PH, Eth, Eph); raw = block;
for k = 1:numel(req), raw.(char(req(k))) = reshape(M.(char(req(k))), [], 1); end
meta = readExcelSummary(fp, sheets(1)); fmt = hasL + 2*hasC; kinds = {'Eth/Eph', 'Ercp/Elcp', 'Ercp/Elcp + Eth/Eph'};
meta.source = sprintf('Excel Matrix Format %d (%s)', fmt, kinds{fmt}); meta.isGainOnly = false; meta.isCoverage = false; meta.isDep = false;
meta.hasFrequency = isfinite(meta.frequencyMHz); freqs = NaN; if meta.hasFrequency, freqs = meta.frequencyMHz*1e6; end
out = struct('raw', raw, 'blocks', {{block}}, 'freqs', freqs, 'meta', meta);
end

function [theta, phi, data] = readExcelMatrixSheet(fp, sheet)
%readExcelMatrixSheet One C3-origin matrix: row 2 = φ axis (column C onward), column B = θ axis (row 3 onward).
C = readcell(fp, 'Sheet', char(sheet));   % readcell keeps worksheet coordinates (readmatrix would auto-trim the template area)
assert(size(C,1) >= 3 && size(C,2) >= 3, 'readFile:ExcelMatrixSheet', 'Sheet "%s" does not contain a C3-origin matrix.', sheet);
isNum = @(c) cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), c);
pm = isNum(C(2,3:end)); tm = isNum(C(3:end,2));
nP = find(~pm, 1) - 1; if isempty(nP), nP = numel(pm); end; nT = find(~tm, 1) - 1; if isempty(nT), nT = numel(tm); end
assert(nP > 0 && nT > 0 && ~any(pm(nP+1:end)) && ~any(tm(nT+1:end)), 'readFile:ExcelMatrixAxis', 'Sheet "%s" has an empty or gapped theta/phi axis.', sheet);
phi = cellfun(@double, C(2,3:2+nP)); theta = cellfun(@double, C(3:2+nT,2)); cells = C(3:2+nT, 3:2+nP);
assert(all(isNum(cells), 'all'), 'readFile:ExcelMatrixSheet', 'Sheet "%s" contains nonnumeric/missing matrix samples.', sheet);
data = cellfun(@double, cells);
assert(all(diff(theta) > 0) && all(diff(phi) > 0) && theta(1) >= -1e-9 && theta(end) <= 180+1e-9 && phi(1) >= -1e-9 && phi(end) < 360+1e-9, ...
    'readFile:ExcelMatrixAxis', 'Sheet "%s" needs strictly increasing axes within theta 0..180 and phi 0..360.', sheet);
end

function meta = readExcelSummary(fp, sheet)
%readExcelSummary Generic label→value capture of the template summary sheet (A:H); every labelled row becomes a metadata field.
meta = struct('frequencyMHz', NaN); C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H70');
clean = @(s) regexprep(lower(strtrim(replace(string(s), char(160), ' '))), '\s+', ' ');
isText = cellfun(@(x) ischar(x) || isstring(x), C); empty = @(x) isempty(x) || isa(x, 'missing');
for r = find(any(isText(:,1:2), 2))'
    col = find(isText(r,1:2), 1); label = clean(C{r,col}); v = C(r, col+1:min(end, 5)); v = v(~cellfun(empty, v));
    if strlength(label) == 0 || isempty(v), continue; end
    meta.(matlab.lang.makeValidName(char(label))) = v{1};
end
f = matlab.lang.makeValidName(char(clean('Pattern Simulation Freq (MHz):')));
if isfield(meta, f), meta.frequencyMHz = str2double(string(meta.(f))); end
end

function writeTable(T, fp, uanHeader)
%writeTable TXT is tab-delimited; UAN = XGTD parameter header + tab-delimited rows; CSV/XLSX use writetable defaults.
if endsWith(fp, '.uan', 'IgnoreCase', true)
    writelines(uanHeader, fp); writetable(T, fp, 'Delimiter', '\t', 'WriteVariableNames', false, 'WriteMode', 'append', 'FileType', 'text');
elseif endsWith(fp, '.txt', 'IgnoreCase', true), writetable(T, fp, 'Delimiter', '\t');
else, writetable(T, fp);
end
end

%% ====================================================================== numerical services (UI-free)
function T = normalizePattern(T)
%normalizePattern Map angular coordinates onto the canonical sphere: θ∈[0,180], φ∈[0,360] with the φ=360 seam closed once.
th = T.Theta;
if any(th < 0)
    if min(th, [], 'omitnan') >= -90 && max(th, [], 'omitnan') <= 90, T.Theta = 90 - th;              % elevation convention
    else, m = th < 0; T.Theta(m) = -th(m); T.Phi(m) = T.Phi(m) + 180;                                 % signed polar convention
    end
end
T.Theta = mod(T.Theta, 360); over = T.Theta > 180; T.Theta(over) = 360 - T.Theta(over); T.Phi(over) = T.Phi(over) + 180;
num = varfun(@isnumeric, T, 'OutputFormat', 'uniform'); T{:, num} = round(T{:, num}, 5);              % kill 1e-15 seam artefacts once
T.Phi = mod(T.Phi, 360); T.Theta(abs(T.Theta) < 1e-12) = 0; T.Phi(abs(T.Phi) < 1e-12) = 0;
[~, u] = unique(T{:, {'Phi','Theta'}}, 'rows', 'first'); T = T(u, :);
seam = T(abs(T.Phi) < 1e-10, :); seam.Phi(:) = 360; T = [T; seam];
end

function [P, info] = calcPattern(S, param, pct, excess)
%calcPattern Canonical source → processed table (gains, signed AR, PLF, polarized gain, phases, EIRP/PFD/E-field).
info = struct('POB', NaN, 'POBth', NaN, 'POBph', NaN, 'pol', 'n/a', 'pairs', struct('Linear', ["E_TH","E_PH"], 'Circular', ["E_RCP","E_LCP"]));
ud = S.Properties.UserData;
if isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly
    P = S; if width(P) > 2, P{:, 3:end} = P{:, 3:end} + param.GainLoss_dB; end
    pk = resolvePeak(P{:, 3}, pct, excess); info.peak = pk; info.POB = pk.value; info.POBth = P.Theta(pk.index); info.POBph = P.Phi(pk.index); return
end
Eth = complex(S.Re_Eth, S.Im_Eth) * param.FieldScale; Eph = complex(S.Re_Eph, S.Im_Eph) * param.FieldScale;
Ercp = (Eth + 1i*Eph)/sqrt(2); Elcp = (Eth - 1i*Eph)/sqrt(2);
[mTh, mPh, mR, mL] = deal(abs(Eth), abs(Eph), abs(Ercp), abs(Elcp));
total = 10*log10(max(mTh.^2 + mPh.^2, eps));
pk = resolvePeak(total, pct, excess); info.peak = pk; info.POB = pk.value; info.POBth = S.Theta(pk.index); info.POBph = S.Phi(pk.index);
% Dominant components drive co/cross ordering, the displayed polarization and the Auto-Rx sense
pw = [mean(mTh.^2, 'omitnan'), mean(mPh.^2, 'omitnan'), mean(mR.^2, 'omitnan'), mean(mL.^2, 'omitnan')];
if pw(2) > pw(1), info.pairs.Linear = fliplr(info.pairs.Linear); end
if pw(4) > pw(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(pw(3:4)) > max(pw(1:2)), info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP","E_LCP"], ["RHCP","LHCP"]));
elseif pw(1) >= pw(2),           info.pol = 'Linear (Vertical)';
else,                            info.pol = 'Linear (Horizontal)';
end
% Signed axial ratio (+ RHCP-dominant, − LHCP-dominant); equal components = linear limit → −100 dB floor
delta = mR - mL; sense = sign(delta); sense(~isfinite(delta)) = 0; ar = (mR + mL) ./ max(abs(delta), eps);
signedAR = min(20*log10(ar), 250) .* sense; signedAR(isfinite(delta) & abs(delta) <= eps .* max(mR + mL, 1)) = -100;
% Polarization loss factor against the incident wave (Rw axial ratio, sense Auto/RHCP/LHCP)
if param.RxMode == "Auto", ws = 2*(info.pairs.Circular(1) == "E_RCP") - 1; elseif param.RxMode == "RHCP", ws = 1; else, ws = -1; end
ra = ar .* sense; ra(sense == 0) = 1e12; rw = ws * 10^(param.RxAR_dB/20);
plf = 0.5 + (4*ra*rw - (ra.^2 - 1)*(rw^2 - 1)) ./ (2*(ra.^2 + 1)*(rw^2 + 1)); plfDB = 10*log10(min(max(plf, eps), 1));
eirpDB = param.Pt_dBW + total; eirpW = 10.^(eirpDB/10);
dB20 = @(m) 20*log10(max(m, eps)); ph = @(E) rad2deg(angle(E));
P = table(S.Theta, S.Phi, total, signedAR, dB20(mR), dB20(mL), plfDB, total + plfDB, dB20(mTh), dB20(mPh), ph(Eth), ph(Eph), ph(Ercp), ph(Elcp), ...
    eirpDB, eirpW./(4*pi*param.R_m^2), sqrt(30*eirpW)/param.R_m, 'VariableNames', {'Theta','Phi','E_Total_dB','AR_dB','E_RCP_dB','E_LCP_dB','PLF_dB', ...
    'Gain_PolCorrected_dB','E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'});
P.Properties.UserData = ud;
end

function R = resampleCanonical(S, stepDeg)
%resampleCanonical Resample primitive canonical data onto 0:step:180 × 0:step:360 (closing seam included once).
%   Regular grids: periodic interp2 (nearest fill at the edges).  Irregular samples: one scatteredInterpolant per column.
%   Gain-like dB columns of gain-only sources are interpolated in linear power.
cols = string(S.Properties.VariableNames(3:end)); ud = S.Properties.UserData;
S = S(isfinite(S.Theta) & isfinite(S.Phi) & abs(S.Phi - 360) > 1e-9, :);                 % drop the duplicated closing seam
[~, u] = unique([S.Theta mod(S.Phi, 360)], 'rows', 'stable'); S = S(u, :); theta = S.Theta; phi = mod(S.Phi, 360);
tT = (0:stepDeg:180)'; tP = (0:stepDeg:360)'; if tP(end) ~= 360, tP(end+1) = 360; end
[QP, QT] = meshgrid(tP, tT); R = table(QT(:), QP(:), 'VariableNames', {'Theta','Phi'});
uT = unique(theta); uP = unique(phi); regular = numel(uT)*numel(uP) == numel(theta);
if regular, [~, it] = ismember(theta, uT); [~, ip] = ismember(phi, uP); lin = sub2ind([numel(uT) numel(uP)], it, ip); regular = numel(unique(lin)) == numel(lin); end
powerDomain = ~all(ismember(["Re_Eth","Im_Eth","Re_Eph","Im_Eph"], cols));
for c = cols
    v = double(S.(char(c))); toPower = powerDomain && isGainDB(c); if toPower, v = 10.^(v/10); end
    if regular
        G = nan(numel(uT), numel(uP)); G(lin) = v; [PG, TG] = meshgrid(uP, uT);
        if uP(end) < uP(1) + 360 - 1e-9, PG(:, end+1) = PG(:, 1) + 360; TG(:, end+1) = TG(:, 1); G(:, end+1) = G(:, 1); end   % periodic closure
        q = interp2(PG, TG, G, QP, QT, 'linear', NaN); miss = ~isfinite(q);
        if any(miss(:)), qn = interp2(PG, TG, G, QP, QT, 'nearest', NaN); q(miss) = qn(miss); end
    else
        F = scatteredInterpolant(phi, theta, v, 'linear', 'nearest'); q = F(QP, QT);
    end
    if toPower, q = 10*log10(max(q, realmin)); end
    R.(char(c)) = q(:);
end
R.Properties.UserData = ud;
end

function tf = isGainDB(name)
key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', ''); tf = contains(key, ["gain","directivity","eirp"]) || endsWith(key, "db");
end

function info = resolvePeak(v, pct, maxExcessDB)
%resolvePeak APAT peak policy: accept the raw maximum unless it exceeds P<pct> by more than maxExcessDB;
%   then the highest sample at or below that percentile is the effective peak (isolated-spike rejection).
v = double(v(:)); finite = isfinite(v);
info = struct('value', NaN, 'index', 1, 'rawValue', NaN, 'rawIndex', 1, 'outlierMask', false(size(v)), 'wasAdjusted', false);
if ~any(finite), return; end
[info.rawValue, info.rawIndex] = max(v, [], 'omitnan'); info.value = info.rawValue; info.index = info.rawIndex;
p = percentile(v(finite), pct);
if info.rawValue > p + maxExcessDB
    mask = finite & v > p; cand = v; cand(~finite | mask) = -Inf;
    if any(cand > -Inf), [info.value, info.index] = max(cand); info.outlierMask = mask; info.wasAdjusted = true; end
end
end

function v = percentile(x, p)
%percentile Toolbox-free equivalent of prctile (mid-rank linear interpolation, clamped at the extremes).
x = sort(x(:)); n = numel(x); if n < 2, v = x; return; end
v = interp1(100*((1:n)' - 0.5)/n, x, p, 'linear'); if isnan(v), v = x(1 + (p > 50)*(n - 1)); end
end

function b = displayRange(v, pct, excess)
%displayRange 50-dB window whose top is the effective peak rounded up to 5 dB (shared by the colour scale and the coverage preset).
pk = resolvePeak(v, pct, excess);
if ~isfinite(pk.value), b = [-40 10]; return; end
top = min(100, max(-245, ceil(pk.value/5)*5)); b = [max(-250, top - 50), top];
end

function w = solidWeights(theta, phi)
%solidWeights Exact uniform-cell solid-angle weights (sr); the duplicated closing φ seam receives zero weight.
ts = gridStep(theta); ps = gridStep(mod(phi, 360)); if ~isfinite(ts), ts = 180; end; if ~isfinite(ps), ps = 360; end
w = (cosd(max(theta - ts/2, 0)) - cosd(min(theta + ts/2, 180))) * deg2rad(ps);
seam = 360 - 180*any(phi < 0); w(abs(phi - seam) < 1e-9) = 0;
end

function step = gridStep(values)
%gridStep Smallest positive spacing between distinct finite values (NaN when undefined).
d = diff(unique(values(isfinite(values)))); d = d(d > 1e-9); if isempty(d), step = NaN; else, step = min(d); end
end

function [bw, lo, hi] = calcHPBW(ang, g, peakGain, peakAngle)
%calcHPBW Half-power beamwidth of a circular cut by linear interpolation of the −3 dB crossings either side of the peak.
[bw, lo, hi] = deal(NaN); ok = isfinite(ang) & isfinite(g); ang = ang(ok); g = g(ok);
if numel(g) < 3, return; end
if nargin < 3 || isempty(peakGain), [peakGain, i] = max(g); peakAngle = ang(i); end
half = peakGain - 3; [rel, o] = sort(mod(ang - peakAngle + 180, 360) - 180); g = g(o);
L = find(rel < 0 & g <= half, 1, 'last'); Rr = find(rel > 0 & g <= half, 1, 'first');
if isempty(L) || isempty(Rr) || L + 1 > numel(g) || Rr - 1 < 1, return; end
gl = g([L L+1]); gr = g([Rr Rr-1]); if diff(gl) == 0 || diff(gr) == 0, return; end
xl = rel(L) + diff(rel([L L+1])) * (half - gl(1)) / diff(gl); xr = rel(Rr) + diff(rel([Rr Rr-1])) * (half - gr(1)) / diff(gr);
lo = peakAngle + xl; hi = peakAngle + xr; bw = xr - xl;
end

function [ang, rows, fixed, sym, snapped] = cutGeometry(T, cutType, request, physicalTheta)
%cutGeometry Rows of one full-circle cut (snapped to the nearest sampled plane) and their circle angles [0,360).
%   Phi cut: fixed θ, angle = φ.  Theta cut: fixed φ plus its opposite half-plane, angle = θ / 360−θ.
if cutType == "Phi"
    tv = unique(T.Theta); [dist, k] = min(abs(tv - request)); fixed = tv(k); sym = 'θ';
    rows = find(abs(T.Theta - fixed) < 1e-9); [ang, o] = sort(T.Phi(rows)); rows = rows(o);
else
    wp = mod(T.Phi, 360); pv = unique(wp); request = mod(request, 360);
    [dist, k] = min(abs(mod(pv - request + 180, 360) - 180)); [~, k2] = min(abs(mod(pv - pv(k), 360) - 180)); fixed = pv(k); sym = 'φ';
    a = find(abs(wp - fixed) < 1e-9); b = find(abs(wp - pv(k2)) < 1e-9 & abs(physicalTheta - 180) > 1e-9);
    [~, oa] = sort(physicalTheta(a)); [~, ob] = sort(physicalTheta(b), 'descend'); a = a(oa); b = b(ob);
    rows = [a; b]; ang = [physicalTheta(a); 360 - physicalTheta(b)];
end
snapped = dist > 0;
end

function [pk, axisIndex] = calcOrientation(T, omega, col, axes, pct, excess)
%calcOrientation Effective peak of COL and the principal axis whose 45° cone captures the most weighted power.
g = chooseGain(T, col); pk = resolvePeak(g, pct, excess); th = physTheta(T);
if pk.wasAdjusted, g(pk.outlierMask) = NaN; end
w = 10.^((g - pk.value)/10) .* omega(:); w(~isfinite(w)) = 0;
A = [sind(axes.theta(:)).*cosd(axes.phi(:)), sind(axes.theta(:)).*sind(axes.phi(:)), cosd(axes.theta(:))];
Sv = [sind(th).*cosd(T.Phi), sind(th).*sind(T.Phi), cosd(th)];
[~, axisIndex] = max(w.' * double(Sv * A.' >= cosd(45)));
end

function m = calcMetrics(T, omega, axes, boresight, elevation, pct, excess)
%calcMetrics Scalar antenna metrics from total gain: peak, E/H-plane HPBW, front-to-back, directivity, efficiency, AR at peak.
g = chooseGain(T, 'E_Total_dB'); pk = resolvePeak(g, pct, excess); th = physTheta(T); i = pk.index;
gi = g; if pk.wasAdjusted, gi(pk.outlierMask) = NaN; end
Pint = sum(10.^(gi/10) .* omega(:), 'omitnan'); eff = 100*Pint/(4*pi); if eff < 0 || eff > 100, eff = NaN; end
[~, back] = min(cosd(th)*cosd(th(i)) + sind(th)*sind(th(i)).*cosd(T.Phi - T.Phi(i)));
if axes.theta(boresight) == 90, hType = "Phi"; hVal = 90*~elevation; else, hType = "Theta"; hVal = 90; end
[eA, eR] = cutGeometry(T, "Theta", axes.phi(boresight), th); [hA, hR] = cutGeometry(T, hType, hVal, th);
ar = NaN; if ismember('AR_dB', T.Properties.VariableNames), ar = T.AR_dB(i); end
m = struct('PeakGain_dB', pk.value, 'PeakTheta_deg', th(i), 'PeakPhi_deg', mod(T.Phi(i), 360), 'HPBW_EPlane_deg', calcHPBW(eA, g(eR)), 'HPBW_HPlane_deg', calcHPBW(hA, g(hR)), ...
    'FrontBack_dB', pk.value - g(back), 'PeakDirectivity_dB', 10*log10(max(4*pi*10^(pk.value/10)/max(Pint, eps), eps)), 'Efficiency_pct', eff, 'AxialRatioAtPeak_dB', ar);
end

function cov = coverageCCDF(gain, regionMask, thresholds, omega)
%coverageCCDF Coverage(T) [%] = 100 · Σ I(G_i > T)·Ω_i / Σ Ω_i over the region (all thresholds at once).
ok = logical(regionMask(:)) & isfinite(gain(:)) & isfinite(omega(:)) & omega(:) >= 0;
g = double(gain(ok)); w = double(omega(ok)); thresholds = double(thresholds(:)); cov = zeros(size(thresholds));
if isempty(g) || sum(w) <= 0, return; end
cov = 100 * (w.' * double(g > thresholds.')).' / sum(w);
end

function [x, y] = covQueryPoint(thr, cov, mode, q)
%covQueryPoint Coverage at a threshold ("cov") or threshold at a coverage level ("thr"), linearly interpolated.
if mode == "cov", x = q; y = interp1(thr, cov, q, 'linear', NaN); return; end
[c, i] = unique(cov, 'last'); y = q; if numel(c) < 2, x = NaN; else, x = interp1(c, thr(i), q, 'linear', NaN); end
end

%% ====================================================================== small shared helpers
function th = physTheta(T)
%physTheta Physical polar θ of a view table regardless of the active display convention.
th = T.Theta; ud = T.Properties.UserData;
if isstruct(ud) && isfield(ud, 'elevation') && ud.elevation, th = 90 - th; end
end

function [g, col] = chooseGain(T, requested)
%chooseGain Requested column if present, else E_Total_dB, else the first data column.
vars = T.Properties.VariableNames; cand = [string(requested), "E_Total_dB"]; k = find(ismember(cand, vars), 1);
if isempty(k), col = vars{3}; else, col = char(cand(k)); end; g = double(T.(col));
end

function [cols, labels] = componentMap(T)
%componentMap Canonical component columns with user-facing labels (gain-only sources expose every data column).
cols = string(T.Properties.VariableNames(3:end)); labels = cols; ud = T.Properties.UserData;
if isstruct(ud) && isfield(ud, 'isGainOnly') && ud.isGainOnly, return; end
known = ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","AR_dB","Gain_PolCorrected_dB"];
txt = ["Total Gain","Etheta Gain","Ephi Gain","RHCP Gain","LHCP Gain","Axial Ratio","Polarized Gain"];
keep = ismember(known, cols); cols = known(keep); labels = txt(keep);
end

function c = preferredComponent(previous, cols)
if any(cols == string(previous)), c = char(previous); elseif any(cols == "E_Total_dB"), c = 'E_Total_dB'; else, c = char(cols(1)); end
end

function tf = isAR(name)
%isAR Axial-ratio semantics independent of column spelling (AR, AR_dB, AR dB, Axial Ratio, Axial_Ratio).
key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', ''); tf = key == "ar" || startsWith(key, "ardb") || startsWith(key, "axialratio");
end

function s = fmtNum(v, precision)
%fmtNum 'n/a' for non-finite; compact (≤2 decimals, trailing zeros trimmed) or a fixed precision when given.
if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v), s = 'n/a'; return; end
if nargin > 1, s = sprintf(sprintf('%%.%df', precision), v); else, s = regexprep(sprintf('%.2f', v), '\.?0+$', ''); end
end

function r = clampRange(v, bounds)
%clampRange Sorted, clamped range with a minimum width of one unit.
v = sort(double(v(:).')); if numel(v) < 2 || any(~isfinite(v(1:2))), r = bounds; return; end
r = [max(bounds(1), v(1)), min(bounds(2), v(2))];
if diff(r) < 1, r(2) = min(bounds(2), r(1) + 1); r(1) = max(bounds(1), r(2) - 1); end
end

function t = axisTicks(lim, step)
%axisTicks Limits plus every multiple of STEP inside them (empty when degenerate or overly dense).
t = []; if ~isfinite(step) || step <= 0 || diff(lim) <= 0, return; end
t = unique([lim(1), ceil(lim(1)/step)*step:step:floor(lim(2)/step)*step, lim(2)]); if numel(t) > 60, t = []; end
end