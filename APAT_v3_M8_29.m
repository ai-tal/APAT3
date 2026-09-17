classdef APAT_v3_M8_29 < matlab.apps.AppBase %2000-lines
%APAT_V4_M8  Antenna Pattern Analyzer Tool — v4, Milestone 8.
%
%   Single-file MATLAB app that reads, standardizes, analyzes, plots and
%   exports antenna far-field patterns, plus solid-angle coverage (CCDF).
%   M8 consolidates v3 M7.110_5 (5 199 lines) into ~38 % of the code with
%   identical — in places stricter — behaviour, via five structural ideas:
%
%   1. ONE STATE OBJECT     Every mutable value lives in app.S (M7: 35 props).
%   2. ONE WIDGET REGISTRY  Handles live in app.H.<key>; the GUI is data
%                           (layoutSpec) walked by one builder (mk).  M7 used
%                           170 typed properties + 625 imperative lines.
%   3. MEMOIZED STAGE GRAPH std → pattern → view → grid.  invalidate(stage)
%                           dirties it and everything downstream; ensure(stage)
%                           rebuilds the minimum prefix — replacing ~20 ad-hoc
%                           caches, revision counters and manual invalidations.
%   4. REGISTRY-DRIVEN VIEW Plot tabs, renderers and annotations are rows of
%                           VIEWS; one colour range instead of five copies.
%   5. PURE FUNCTIONAL CORE All numerics and parsing are app-free local
%                           functions — unit-testable, with none of the M7
%                           "app wrapper + pure twin" duplication.
%
%   Usage:  app = APAT_v4_M8;      report = app.selfTest;
    %% ---------------------------------------------------------------- const
    properties (Constant, Access = private)
        VERSION  = '4.0-M8'
        RELEASE  = 'APAT v4 Milestone 8'
        LIM      = [-250 100]              % global dB display clamp
        PEAK     = struct('pct', 99.99, 'maxExcessDB', 6)
        FLOOR_M  = 1e-12
        TOL      = 1e-9

        % Right-handed principal axes: [polar theta, phi] in degrees.
        AX6 = struct('label', {{'+Z','-Z','+X','-X','+Y','-Y'}}, ...
                     'theta', [0 180 90 90 90 90], 'phi', [0 0 0 180 90 270])

        STDCOLS  = {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'}
        HIDECOLS = {'E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase', ...
                    'E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'}

        % Canonical component keys and their user-facing labels.
        COMPS = struct( ...
            'key', {"E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","AR_dB","Gain_PolCorrected_dB"}, ...
            'lab', {"Total Gain","Etheta Gain","Ephi Gain","RHCP Gain","LHCP Gain","Axial Ratio","Polarized Gain"})

        % Full-pattern view registry: one row per plot tab.
        VIEWS = struct( ...
            'key',   {'ctr'          ,'cir'                ,'sph'          ,'pol'       ,'rec'            }, ...
            'title', {'Contour Plot' ,'Circular Contour'   ,'3D Spherical' ,'3D Polar'  ,'3D Surface'     }, ...
            'kind',  {'contour'      ,'circular'           ,'sph3d'        ,'pol3d'     ,'rect3d'         }, ...
            'cart',  { true          , false               , true          , true       , true            }, ...
            'view3', { false         , false               , true          , true       , true            })

        % Generic-text interpretation registry (menu label ⇄ parse recipe).
        TXT = struct( ...
            'id',   {'gain','linear_magphase','linear_reim','rcp_lcp_magphase','lcp_rcp_magphase','rcp_lcp_reim','lcp_rcp_reim'}, ...
            'menu', {'1: Gain Pattern', ...
                     '2: Etheta/Ephi — dB magnitude, phase', ...
                     '3: Etheta/Ephi — real, imaginary', ...
                     '4: POL1=RCP, POL2=LCP — dB magnitude, phase', ...
                     '5: POL1=LCP, POL2=RCP — dB magnitude, phase', ...
                     '6: POL1=RCP, POL2=LCP — real, imaginary', ...
                     '7: POL1=LCP, POL2=RCP — real, imaginary'})

        % Dataflow stages, in strict dependency order.
        STAGES = {'std','pattern','view','grid'}
    end
    %% ------------------------------------------------------------- handles
    properties (Access = public)
        UIFigure matlab.ui.Figure
        H struct = struct()      % every widget handle, keyed by short name
    end
    properties (GetAccess = public, SetAccess = private), isClosing logical = false; end
    properties (Access = private), S struct; end   % complete mutable session state
    %% --------------------------------------------------------------- state
    methods (Static, Access = private)
        function s = blankState()
            %BLANKSTATE The entire mutable session in one struct.
            s = struct( ...
                'file',   struct('name','','path','','folder','','base',''), ...
                'src',    validateSource(struct()), ...
                'raw',    table(), 'blocks', {{}}, 'freqs', NaN, ...
                'std',    table(), ...  % canonical Θ/Φ/Re/Im (or gain) source
                'pattern',table(), ...  % processed at native resolution
                'base',   table(), ...  % processed at the selected display step
                'view',   table(), ...  % + display angular convention
                'uan',    table(), 'grid', struct(), ...
                'dirty',  struct('std',true,'pattern',true,'view',true,'grid',true), ...
                'step',   1, 'peak', struct(), 'pob', struct('val',NaN,'th',NaN,'ph',NaN), ...
                'pol',    'n/a', 'axis', 1, 'dOmega', [], 'metrics', struct(), ...
                'pairs',  struct('Linear',["E_TH","E_PH"],'Circular',["E_RCP","E_LCP"]), ...
                'lim',    struct('full',[-55 25],'cut',[-55 25],'gain',[-55 25],'cov',[-40 10]), ...
                'covID',  0, 'covUserRange', false, 'covLastPath', '', ...
                'anno',   {{}}, 'defaults', struct(), 'timer', [], 'dlg', [], 'rawShown', false);
        end
    end
    %% --------------------------------------------------------- construction
    methods (Access = public)
        function app = APAT_v3_M8_29()
            app.S = APAT_v3_M8_29.blankState();
            app.buildUI();
            registerApp(app, app.UIFigure);
            app.startup();
            if nargout == 0, clear app; end
        end
        function delete(app)
            app.isClosing = true;
            app.stopTimer();
            if isgraphics(app.UIFigure), delete(app.UIFigure); end
        end
    end
    %% ----------------------------------------------------- dataflow engine
    methods (Access = private)
        function invalidate(app, stage)
            %INVALIDATE Mark STAGE and every downstream stage dirty.
            k = find(strcmp(app.STAGES, stage), 1);
            for j = k:numel(app.STAGES), app.S.dirty.(app.STAGES{j}) = true; end
        end

        function ensure(app, stage)
            %ENSURE Rebuild the minimum dirty prefix required for STAGE.
            k = find(strcmp(app.STAGES, stage), 1);
            for j = 1:k
                name = app.STAGES{j};
                if app.S.dirty.(name)
                    app.(['build_' name])();
                    app.S.dirty.(name) = false;
                end
            end
        end

        % --- stage 1: canonical source table ------------------------------
        function build_std(app)
            if isempty(app.S.blocks), return, end
            idx = max(1, app.H.ffd.Value);
            block = app.S.blocks{min(idx, numel(app.S.blocks))};
            if app.S.src.isDep, app.S.raw = block; app.S.rawShown = false; end
            t = normalizePattern(block);
            t.Properties.UserData = app.S.src;
            app.S.std = t;
        end

        % --- stage 2: processed pattern at native resolution --------------
        function build_pattern(app)
            if isempty(app.S.std), return, end
            [app.S.pattern, info] = calcPattern(app.S.std, app.params(), app.PEAK);
            app.S.pol   = info.pol;
            app.S.pairs = info.pairs;
            app.S.pob   = struct('val', info.pob, 'th', info.th, 'ph', info.ph);
            app.S.peak  = info.peak;
            app.syncBasisAuto();
            app.syncStepControl();
        end

        % --- stage 3: display view (step + angular convention) ------------
        function build_view(app)
            if isempty(app.S.pattern), return, end
            src = app.S.std;
            if app.oneDegree() && needsResample(src, app.TOL)
                src = downTo1Deg(src, app.TOL);
                src.Properties.UserData = app.S.std.Properties.UserData;
                app.S.base = calcPattern(src, app.params(), app.PEAK);
            else
                app.S.base = app.S.pattern;
            end
            app.S.view   = applySpan(app.S.base, app.signedPhi(), app.elevation());
            app.S.uan    = table();
            app.S.dOmega = [];
            app.S.metrics = struct();
        end

        % --- stage 4: gridded topology / geometry cache -------------------
        function build_grid(app)
            t = app.S.view;
            if isempty(t), app.S.grid = struct(); return, end
            th = unique(t.Theta); ph = unique(t.Phi);
            [~, ti] = ismember(t.Theta, th);
            [~, pj] = ismember(t.Phi,   ph);
            sz = [numel(th) numel(ph)];
            app.S.grid = struct('theta', th, 'phi', ph, 'sz', sz, ...
                'lin', sub2ind(sz, ti, pj), 'comp', struct(), 'geom', struct());
        end
    end
    %% ---------------------------------------------------- declarative GUI
    methods (Access = private)
        function h = mk(app, key, parent, type, row, col, props, labelText)
            %MK Create one widget (and its optional left label) from a spec row.
            persistent C
            if isempty(C)
                wrap = @(f, varargin) @(p, args) f(p, varargin{:}, args{:});
                C = struct('grid',wrap(@uigridlayout), 'tabs',wrap(@uitabgroup), 'tab',wrap(@uitab), ...
                    'panel',wrap(@uipanel,'TitlePosition','centertop','FontWeight','bold'), ...
                    'txt',wrap(@uilabel), 'btn',wrap(@uibutton,'push','FontWeight','bold'), ...
                    'state',wrap(@uibutton,'state','FontWeight','bold'), 'drop',wrap(@uidropdown), ...
                    'spin',wrap(@uispinner), 'check',wrap(@uicheckbox), 'edit',wrap(@uieditfield,'text'), ...
                    'switch',wrap(@uiswitch,'slider'), 'range',wrap(@uislider,'range'), ...
                    'table',wrap(@uitable), 'axes',wrap(@uiaxes), 'polar',wrap(@polaraxes), ...
                    'tree',wrap(@uitree,'checkbox'), 'node',wrap(@uitreenode), ...
                    'bgrp',wrap(@uibuttongroup), 'radio',wrap(@uiradiobutton));
            end
            assert(isfield(C, type), 'apat:ui:type', 'Unknown widget type "%s".', type);
            p = app.H.(parent);
            h = C.(type)(p, props);
            if ~isempty(row) && isprop(h, 'Layout'), h.Layout.Row = row; h.Layout.Column = col; end
            if ~isempty(key), app.H.(key) = h; end
            if nargin >= 8 && ~isempty(labelText)
                lab = uilabel(p, 'Text', labelText, 'HorizontalAlignment', 'right');
                lab.Layout.Row = row; lab.Layout.Column = col(1) - 1;
                app.H.(['l_' key]) = lab;
            end
        end

        function buildUI(app)
            app.UIFigure = uifigure('Name', sprintf('Antenna Pattern Analyzer Tool — %s', app.RELEASE), ...
                'Visible','off', 'Position',[100 100 1280 800], 'WindowState','maximized');
            app.UIFigure.CloseRequestFcn = @(~,~) app.onClose();
            app.H = struct('fig', app.UIFigure);
            spec = app.layoutSpec();
            for k = 1:size(spec, 1), app.mk(spec{k,:}); end
            app.buildViewTabs();
            es = app.extraSpec();
            for k = 1:size(es,1), app.mk(es{k,:}); end
            grid(app.H.axRect,'on'); xlabel(app.H.axRect,'Angle (degree)'); ylabel(app.H.axRect,'Magnitude (dB)');
            xlabel(app.H.covAxes,'Threshold (dB)'); ylabel(app.H.covAxes,'Coverage (%)');
            grid(app.H.covAxes,'on'); hold(app.H.covAxes,'on'); app.H.covAxes.YLim = [0 100];
            for g = {'full','cut','cov'}, app.bindRange(g{1}); end
            app.onCovRegion();
        end

        function spec = layoutSpec(app)
            %LAYOUTSPEC The entire GUI as data: {key parent type row col props label}.
            %   A non-empty label is placed automatically in column col(1)-1, so
            %   label widgets never appear in this table twice.
            lim = app.LIM;  cb = @(f) {'ButtonPushedFcn', f};  vc = @(f) {'ValueChangedFcn', f};
            R = @(stage) @(~,~) app.recompute(stage);
            spec = { ...
            % ------------------------------------------------------------ shell
            'root'   ,'fig'    ,'grid' ,[],[], {'ColumnWidth',{'1x'},'RowHeight',{'1x'},'Padding',[4 4 4 4]}, ''
            'tabs'   ,'root'   ,'tabs' ,1 ,1 , {}, ''
            'tabMain','tabs'   ,'tab'  ,[],[], {'Title','Process Pattern 📡'}, ''
            'tabCov' ,'tabs'   ,'tab'  ,[],[], {'Title','Coverage Analysis 📶'}, ''
            'gMain'  ,'tabMain','grid' ,[],[], {'ColumnWidth',repmat({'1x'},1,14),'RowHeight',{'fit','2x','fit','1x','fit'},'RowSpacing',6}, ''
            % --------------------------------------------------- parameter panel
            'panParam','gMain' ,'panel',1,[1 14], {'Title','Source & Link Parameters'}, ''
            'gParam' ,'panParam','grid',[],[], {'ColumnWidth',{'fit','1x','fit','fit','1x','fit','fit','1x','fit','fit','1x','fit'}, ...
                                                'RowHeight',{'fit','fit'},'ColumnSpacing',6,'RowSpacing',4}, ''
            'path'   ,'gParam' ,'edit' ,1,2 , {'Editable','off','Tooltip','Loaded source file'}, 'Input pattern'
            'load'   ,'gParam' ,'btn'  ,1,3 , [{'Text','Load 📂'} cb(@(~,~) app.onLoad())], ''
            'txtfmt' ,'gParam' ,'drop' ,1,5 , [{'Items',{app.TXT.menu},'ItemsData',{app.TXT.id},'Value','gain','Visible','off', ...
                                                'Tooltip','Interpretation used for CSV/TXT/DAT pattern files.'} vc(@(~,~) app.onReload())], 'Text format'
            'ffd'    ,'gParam' ,'drop' ,1,7 , [{'Items',{'1'},'ItemsData',1,'Visible','off'} vc(R('std'))], 'Freq block'
            'step'   ,'gParam' ,'drop' ,1,9 , [{'Items',{'native'},'Visible','off'} vc(R('view'))], 'Grid step'
            'process','gParam' ,'btn'  ,1,[10 11], [{'Text','Process ▶','BackgroundColor',[0.85 0.93 0.85]} cb(@(~,~) app.onProcess())], ''
            'reset'  ,'gParam' ,'btn'  ,1,12, [{'Text','Reset ↺'} cb(@(~,~) app.onResetParams())], ''
            'loss'   ,'gParam' ,'spin' ,2,2 , [{'Value',0,'Step',0.5,'Limits',[-200 200]} vc(R('pattern'))], 'Loss (dB)'
            'rxpol'  ,'gParam' ,'drop' ,2,4 , [{'Items',{'Auto','RHCP','LHCP','Vertical','Horizontal','None'},'Value','Auto'} vc(R('pattern'))], 'Rx pol'
            'rw'     ,'gParam' ,'spin' ,2,6 , [{'Value',0,'Step',0.5,'Limits',[0 60]} vc(R('pattern'))], 'Rx AR (dB)'
            'pt'     ,'gParam' ,'spin' ,2,8 , [{'Value',0,'Step',1} vc(R('pattern'))], 'Tx power'
            'ptu'    ,'gParam' ,'drop' ,2,9 , [{'Items',{'dBW','dBm','Watts'},'Value','dBW'} vc(R('pattern'))], ''
            'r'      ,'gParam' ,'spin' ,2,11, [{'Value',1,'Step',1,'Limits',[0 Inf]} vc(R('pattern'))], 'Distance'
            'ru'     ,'gParam' ,'drop' ,2,12, [{'Items',{'m','km'},'Value','m'} vc(R('pattern'))], ''
            % ------------------------------------------------ full-pattern panel
            'panFull','gMain'  ,'panel',[2 3],[1 6], {'Title','Full Antenna Pattern','Visible','off'}, ''
            'gFull'  ,'panFull','grid' ,[],[], {'ColumnWidth',{'1x'},'RowHeight',{'1x'},'Padding',[2 2 2 2]}, ''
            'tabPlots','gFull' ,'tabs' ,1,1 , {}, ''
            % ----------------------------------------------------- pattern cut
            'panCut' ,'gMain'  ,'panel',[2 3],[7 12], {'Title','Antenna Pattern Cut','Visible','off'}, ''
            'gCut'   ,'panCut' ,'grid' ,[],[], {'ColumnWidth',{'1x'},'RowHeight',{'1x'},'Padding',[2 2 2 2]}, ''
            'tabCut' ,'gCut'   ,'tabs' ,1,1 , {}, ''
            % ----------------------------------------------------- display panel
            'panCtrl','gMain'  ,'panel',[2 3],[13 14], {'Title','Display','Visible','off'}, ''
            'gCtrl'  ,'panCtrl','grid' ,[],[], {'ColumnWidth',{'fit','1x'},'RowSpacing',3,'RowHeight',repmat({'fit'},1,17)}, ''
            'comp'   ,'gCtrl'  ,'drop' ,1,2 , [{'Items',{'Total Gain'},'ItemsData',{'E_Total_dB'}} vc(@(~,~) app.onComponent())], 'Component'
            'cutType','gCtrl'  ,'drop' ,2,2 , [{'Items',{'Phi','Theta'},'Value','Phi'} vc(@(~,~) app.onCutType())], 'Cut type'
            'cutVal' ,'gCtrl'  ,'spin' ,3,2 , [{'Value',0,'Step',1,'Limits',[-360 360]} vc(@(~,~) app.drawCut())], 'Cut value'
            'basis'  ,'gCtrl'  ,'drop' ,4,2 , [{'Items',{'Linear','Circular'},'Value','Circular'} vc(@(~,~) app.onBasis())], 'Cut basis'
            'eh'     ,'gCtrl'  ,'switch',5,2, [{'Items',{'E','H'},'Value','E'} vc(@(~,~) app.onPlane())], 'Plane'
            'span'   ,'gCtrl'  ,'switch',6,2, [{'Items',{'0° to 360°','-180° to 180°'},'Value','0° to 360°'} vc(R('view'))], 'φ span'
            'thspan' ,'gCtrl'  ,'switch',7,2, [{'Items',{'0° to 180°','-90° to 90°'},'Value','0° to 180°'} vc(R('view'))], 'θ span'
            'view3d' ,'gCtrl'  ,'drop' ,8,2 , [{'Items',{'Default','Top (+Z)','Bottom (-Z)','Front (+X)','Back (-X)','Left (+Y)','Right (-Y)'}} vc(@(~,~) app.apply3DView())], '3D view'
            'cbPOB'  ,'gCtrl'  ,'check',9,[1 2] , [{'Text','Show POB marker','Value',true} vc(@(~,~) app.refreshAnnotations())], ''
            'cbOv'   ,'gCtrl'  ,'check',10,[1 2], [{'Text','Overlay active cut'} vc(@(~,~) app.drawAllViews())], ''
            'cbHB'   ,'gCtrl'  ,'check',11,[1 2], [{'Text','HPBW bound markers'} vc(@(~,~) app.drawCut())], ''
            'cmax'   ,'gCtrl'  ,'spin' ,12,2, {'Limits',lim,'Value',25,'Step',5}, 'Range max'
            'rngFull','gCtrl'  ,'range',13,[1 2], {'Limits',lim,'Value',[-55 25],'Step',1}, ''
            'cmin'   ,'gCtrl'  ,'spin' ,14,2, {'Limits',lim,'Value',-55,'Step',5}, 'Range min'
            'cstep'  ,'gCtrl'  ,'spin' ,15,2, [{'Limits',[0 100],'Value',10,'Step',1} vc(@(~,~) app.drawAllViews())], 'Bar step'
            'climBtn','gCtrl'  ,'btn'  ,16,[1 2], [{'Text','Auto range ⟲'} cb(@(~,~) app.autoRange())], ''
            'expOut' ,'gCtrl'  ,'btn'  ,17,1, [{'Text','Export','Visible','off'} cb(@(~,~) app.onExportTable())], ''
            'expUAN' ,'gCtrl'  ,'btn'  ,17,2, [{'Text','UAN','Visible','off'} cb(@(~,~) app.onExportUAN())], ''
            % --------------------------------------------------------- data tabs
            'tabData','gMain'  ,'tabs' ,4,[1 14], {}, ''
            'tabOut' ,'tabData','tab'  ,[],[], {'Title','Output Data'}, ''
            'gOut'   ,'tabOut' ,'grid' ,[],[], {'ColumnWidth',{'fit','1x'},'RowHeight',{'1x'}}, ''
            'outFilt','gOut'   ,'drop' ,1,1 , [{'Items',{'All','Peak −3 dB','Peak −10 dB','Above 0 dB'},'Value','All'} vc(@(~,~) app.fillOutputTable())], ''
            'tblOut' ,'gOut'   ,'table',1,2 , {}, ''
            'tabIn'  ,'tabData','tab'  ,[],[], {'Title','Input Data'}, ''
            'gIn'    ,'tabIn'  ,'grid' ,[],[], {'ColumnWidth',{'1x'},'RowHeight',{'1x'}}, ''
            'tblIn'  ,'gIn'    ,'table',1,1 , {}, ''
            'tabMeta','tabData','tab'  ,[],[], {'Title','Metadata'}, ''
            'gMeta'  ,'tabMeta','grid' ,[],[], {'ColumnWidth',{'1x'},'RowHeight',{'1x'}}, ''
            'tblMeta','gMeta'  ,'table',1,1 , {'ColumnName',{'Property','Value'},'ColumnWidth',{240,'auto'}}, ''
            'status' ,'gMain'  ,'txt'  ,5,[1 14], {'Text','Ready — load an antenna pattern file.','Interpreter','html'}, ''

            % ==================================================== coverage tab ==
            'gCov'   ,'tabCov' ,'grid' ,[],[], {'ColumnWidth',{'0.85x','1x','1x'},'RowHeight',{'1x','fit'},'RowSpacing',6}, ''
            'panCovP','gCov'   ,'panel',[1 2],1, {'Title','Coverage Setup'}, ''
            'gCovP'  ,'panCovP','grid' ,[],[], {'ColumnWidth',{'fit','1x','fit'},'RowSpacing',4, ...
                        'RowHeight',[repmat({'fit'},1,3) {70} repmat({'fit'},1,12) {'1x'}]}, ''
            'covPath','gCovP'  ,'edit' ,1,2 , {'Editable','off'}, 'Pattern'
            'covLoad','gCovP'  ,'btn'  ,1,3 , [{'Text','Load 📂'} cb(@(~,~) app.onCovLoad())], ''
            'covTxt' ,'gCovP'  ,'drop' ,2,[2 3], [{'Items',{app.TXT.menu},'ItemsData',{app.TXT.id},'Value','gain','Visible','off'} ...
                                                  vc(@(~,~) app.onCovLoad(app.S.covLastPath))], 'Text format'
            'covComp','gCovP'  ,'drop' ,3,[2 3], {'Items',{'Total Gain'},'ItemsData',{'E_Total_dB'}}, 'Component'
            'covType','gCovP'  ,'bgrp' ,4,[1 3], {'Title','Region','BorderType','line','SelectionChangedFcn',@(~,~) app.onCovRegion()}, ''
            'covOri' ,'gCovP'  ,'drop' ,5,[2 3], {'Items',[{'Auto (boresight)'} app.AX6.label],'ItemsData',num2cell(0:6),'Value',0}, 'Orientation'
            'coneTh' ,'gCovP'  ,'spin' ,6,[2 3], {'Value',0,'Limits',[0 180],'Step',1}, 'Cone θ (°)'
            'conePh' ,'gCovP'  ,'spin' ,7,[2 3], {'Value',0,'Limits',[-360 360],'Step',1}, 'Cone φ (°)'
            'coneAng','gCovP'  ,'spin' ,8,[2 3], {'Value',60,'Limits',[0 180],'Step',1}, 'Half-angle α (°)'
            'thrMin' ,'gCovP'  ,'spin' ,9,[2 3], {'Value',-40,'Step',1,'Limits',lim}, 'Threshold min (dB)'
            'thrMax' ,'gCovP'  ,'spin' ,10,[2 3], {'Value',10,'Step',1,'Limits',lim}, 'Threshold max (dB)'
            'thrStep','gCovP'  ,'spin' ,11,[2 3], {'Value',0.5,'Step',0.5,'Limits',[1e-3 50]}, 'Step (dB)'
            'covRun' ,'gCovP'  ,'btn'  ,12,[1 3], [{'Text','Compute coverage ▶','BackgroundColor',[0.85 0.93 0.85]} cb(@(~,~) app.onCovRun())], ''
            'covReset','gCovP' ,'btn'  ,13,1, [{'Text','Reset'} cb(@(~,~) app.onCovReset())], ''
            'covClear','gCovP' ,'btn'  ,13,2, [{'Text','Clear'} cb(@(~,~) app.onCovClear())], ''
            'covExp' ,'gCovP'  ,'btn'  ,13,3, [{'Text','Export'} cb(@(~,~) app.onCovExport())], ''
            'qCov'   ,'gCovP'  ,'spin' ,14,2, {'Value',90,'Limits',[0 100],'Step',1}, 'Query coverage %'
            'qCovBtn','gCovP'  ,'btn'  ,14,3, [{'Text','→ dB'} cb(@(~,~) app.covQuery('cov'))], ''
            'qThr'   ,'gCovP'  ,'spin' ,15,2, {'Value',0,'Step',1,'Limits',lim}, 'Query threshold dB'
            'qThrBtn','gCovP'  ,'btn'  ,15,3, [{'Text','→ %'} cb(@(~,~) app.covQuery('thr'))], ''
            'covToMain','gCovP','btn'  ,16,[1 3], [{'Text','◀ Back to pattern'} cb(@(~,~) set(app.H.tabs,'SelectedTab',app.H.tabMain))], ''
            'panCovR','gCov'   ,'panel',1,[2 3], {'Title','Coverage Results'}, ''
            'gCovR'  ,'panCovR','grid' ,[],[], {'ColumnWidth',{'fit','2.2x','1.15x'},'RowHeight',{'fit','1x','fit'}}, ''
            'covXmax','gCovR'  ,'spin' ,1,1 , {'Limits',lim,'Value',10,'Step',1}, ''
            'covXrng','gCovR'  ,'range',2,1 , {'Limits',lim,'Value',[-40 10],'Orientation','vertical','Step',1}, ''
            'covXmin','gCovR'  ,'spin' ,3,1 , {'Limits',lim,'Value',-40,'Step',1}, ''
            'covAxes','gCovR'  ,'axes' ,[1 3],2, {}, ''
            'covTree','gCovR'  ,'tree' ,[1 2],3, {'Multiselect','off','CheckedNodesChangedFcn',@(~,~) app.drawCoverage()}, ''
            'covTbl' ,'gCovR'  ,'table',3,3 , {}, ''
            'covStat','gCov'   ,'txt'  ,2,[2 3], {'Text','Coverage idle.','Interpreter','html'}, ''
            };
        end

        function buildViewTabs(app)
            %BUILDVIEWTABS One tab + one axes per VIEWS row; range control is global.
            for v = app.VIEWS
                app.mk(['tab_' v.key], 'tabPlots', 'tab', [], [], {'Title', v.title}, '');
                app.mk(['g_' v.key], ['tab_' v.key], 'grid', [], [], ...
                    {'ColumnWidth',{'1x'},'RowHeight',{'1x'},'Padding',[2 2 2 2]}, '');
                ax = app.mk(['ax_' v.key], ['g_' v.key], 'axes', 1, 1, {}, '');
                title(ax, v.title); colormap(ax, 'jet');   % drawView owns all later styling
            end
        end

        function sub = extraSpec(app)
            %EXTRASPEC Cut tabs, coverage tree root and region radio buttons.
            sub = { ...
            'tabPolar','tabCut' ,'tab'  ,[],[], {'Title','Polar Cut'}, ''
            'gPolar' ,'tabPolar','grid' ,[],[], {'ColumnWidth',{'fit','1x','fit'},'RowHeight',{'fit','1x','fit'},'Padding',[2 2 2 2]}, ''
            'maxCut' ,'gPolar' ,'spin' ,1,1, {'Limits',app.LIM,'Value',25,'Step',5}, ''
            'rngCut' ,'gPolar' ,'range',2,1, {'Limits',app.LIM,'Value',[-55 25],'Orientation','vertical','Step',1}, ''
            'minCut' ,'gPolar' ,'spin' ,3,1, {'Limits',app.LIM,'Value',-55,'Step',5}, ''
            'axPolar','gPolar' ,'polar',[1 3],2, {}, ''
            'gEcut'  ,'gPolar' ,'grid' ,[1 3],3, {'ColumnWidth',{'fit'},'RowHeight',repmat({'fit'},1,6)}, ''
            'hpbwBtn','gEcut'  ,'state',1,1, {'Text','HPBW','ValueChangedFcn',@(~,~) app.drawCut()}, ''
            'hpbwLab','gEcut'  ,'txt'  ,2,1, {'Text','','HorizontalAlignment','center','FontWeight','bold'}, ''
            'cbT'    ,'gEcut'  ,'check',3,1, {'Text','Total','Value',true,'ValueChangedFcn',@(~,~) app.drawCut()}, ''
            'cbR'    ,'gEcut'  ,'check',4,1, {'Text','E_RCP','Value',true,'ValueChangedFcn',@(~,~) app.drawCut()}, ''
            'cbL'    ,'gEcut'  ,'check',5,1, {'Text','E_LCP','Value',true,'ValueChangedFcn',@(~,~) app.drawCut()}, ''
            'expCut' ,'gEcut'  ,'btn'  ,6,1, {'Text','Export cut','ButtonPushedFcn',@(~,~) app.onExportCut()}, ''
            'tabRect','tabCut' ,'tab'  ,[],[], {'Title','Rectangular Cut'}, ''
            'gRect'  ,'tabRect','grid' ,[],[], {'ColumnWidth',{'1x'},'RowHeight',{'1x'},'Padding',[2 2 2 2]}, ''
            'axRect' ,'gRect'  ,'axes' ,1,1, {}, ''
            'covNodeRes','covTree','node',[],[], {'Text','📁 Loaded results'}, ''
            'rSph'   ,'covType','radio',[],[], {'Text','Spherical (4π)','Position',[10 26 160 22],'Value',true}, ''
            'rCon'   ,'covType','radio',[],[], {'Text','Conical cone','Position',[10 4 160 22]}, ''
            };
        end
        function bindRange(app, group)
            [s, lo, hi] = app.rangeWidgets(group);
            s.ValueChangedFcn  = @(w,~) app.setRange(group, w.Value);
            lo.ValueChangedFcn = @(w,~) app.setRange(group, [w.Value app.S.lim.(group)(2)]);
            hi.ValueChangedFcn = @(w,~) app.setRange(group, [app.S.lim.(group)(1) w.Value]);
        end
    end
    %% ------------------------------------------------- lifecycle & controls
    methods (Access = private)
        function startup(app)
            app.S.defaults = app.params();
            app.S.defaults.raw = struct('loss',0,'rxpol','Auto','rw',0,'pt',0,'ptu','dBW','r',1,'ru','m');
            app.setStatus('main', sprintf('<b>%s</b> ready — load an antenna pattern file.', app.RELEASE), false);
            app.H.fig.Visible = 'on';
        end

        function onClose(app), delete(app); end

        % --- small typed accessors over widget state ----------------------
        function p = params(app)
            h = app.H;
            p = struct('lossDB', h.loss.Value, 'rxMode', string(h.rxpol.Value), 'rxAR', h.rw.Value, ...
                       'fieldScale', 10^(h.loss.Value/20), 'PtdBW', h.pt.Value, ...
                       'Rm', max(h.r.Value, app.FLOOR_M) * (1 + 999*strcmp(h.ru.Value,'km')));
            if strcmp(h.ptu.Value,'dBm'), p.PtdBW = h.pt.Value - 30;
            elseif strcmp(h.ptu.Value,'Watts'), p.PtdBW = 10*log10(max(h.pt.Value, eps));
            end
        end

        function tf = oneDegree(app),  tf = strcmp(app.H.step.Value, '1° grid'); end
        function tf = signedPhi(app),  tf = strcmp(app.H.span.Value, '-180° to 180°'); end
        function tf = elevation(app),  tf = strcmp(app.H.thspan.Value, '-90° to 90°'); end
        function c  = comp(app),       c  = app.H.comp.Value; end
        function tf = gainOnly(app),   tf = app.S.src.isGainOnly; end

        function syncBasisAuto(app)
            if app.gainOnly() || isequal(app.H.basis.UserData, false), return, end
            if any(strcmp(app.S.pol, {'Linear (Vertical)','Linear (Horizontal)'}))
                app.H.basis.Value = 'Linear';
            else
                app.H.basis.Value = 'Circular';
            end
        end

        function syncStepControl(app)
            dth = gridStep(app.S.pattern.Theta);
            dph = gridStep(mod(app.S.pattern.Phi, 360));
            if ~isfinite(dth), dth = 1; end
            if ~isfinite(dph), dph = dth; end
            app.S.step = max(dth, dph);
            native = sprintf('native (%g°)', app.S.step);
            nonCanonical = abs(dth - 1) > app.TOL || abs(dph - 1) > app.TOL;
            keep1 = nonCanonical && app.oneDegree();
            app.H.step.Items = {native, '1° grid'};
            app.H.step.Value = native;
            if keep1, app.H.step.Value = '1° grid'; end
            set(app.H.step,  'Visible', nonCanonical, 'Enable', nonCanonical);
            set(app.H.l_step, 'Visible', nonCanonical);
            app.H.cutVal.Step = max(dth, 1);
        end

        function recompute(app, stage)
            %RECOMPUTE Invalidate one stage and refresh every dependent surface.
            if isempty(app.S.blocks) && isempty(app.S.std), return, end
            busyGuard = app.busy(sprintf('Updating (%s) …', stage));
            try
                app.invalidate(stage);
                app.ensure('grid');
                app.refreshAll(~strcmp(stage, 'view'));
            catch err
                app.showError(err, 'Update failed');
            end
        end

        function refreshAll(app, rescale)
            if nargin < 2, rescale = true; end
            if isempty(app.S.view), return, end
            app.syncComponentItems();
            app.syncCutControl();
            app.resolvePeakForComponent();
            app.S.axis = orientationAxis(app.S.view, app.dOmega(), app.comp(), app.AX6, app.PEAK);
            app.S.metrics = calcMetrics(app.S.view, app.S.peak, app.dOmega(), app.AX6, app.S.axis, app.elevation());
            if rescale, app.autoRange(false); end
            app.fillOutputTable(); app.fillInputTable(); app.fillMetadata();
            app.drawAllViews(); app.drawCut();
            app.setStatus('main', app.headline(), false);
        end

        function w = dOmega(app)
            if isempty(app.S.dOmega)
                t = app.S.view;
                app.S.dOmega = solidWeights(physTheta(t), t.Phi, gridStep(t.Theta), gridStep(mod(t.Phi,360)));
            end
            w = app.S.dOmega;
        end

        function resolvePeakForComponent(app)
            t = app.S.view; c = app.comp();
            if isempty(t) || ~ismember(c, t.Properties.VariableNames)
                app.S.pob = struct('val',NaN,'th',NaN,'ph',NaN); return
            end
            pk = resolvePeak(t.(c), app.PEAK);
            app.S.peak = pk;
            app.S.pob  = struct('val', pk.value, 'th', t.Theta(pk.index), 'ph', t.Phi(pk.index));
        end

        function syncComponentItems(app)
            avail = string(app.S.view.Properties.VariableNames(3:end));
            if app.gainOnly()
                keys = avail; labs = avail;
            else
                present = ismember([app.COMPS.key], avail);
                keys = [app.COMPS(present).key]; labs = [app.COMPS(present).lab];
            end
            if isempty(keys), return, end
            prev = string(app.H.comp.Value);
            [app.H.comp.Items, app.H.comp.ItemsData] = deal(cellstr(labs), cellstr(keys));
            if any(keys == prev), pick = prev;
            elseif any(keys == "E_Total_dB"), pick = "E_Total_dB";
            else, pick = keys(1);
            end
            app.H.comp.Value = char(pick);
            [app.H.covComp.Items, app.H.covComp.ItemsData] = deal(app.H.comp.Items, app.H.comp.ItemsData);
            if ~ismember(app.H.covComp.Value, app.H.covComp.ItemsData)
                app.H.covComp.Value = app.H.comp.Value;
            end
        end

        function vals = syncCutControl(app)
            t = app.S.view;
            if strcmp(app.H.cutType.Value, 'Phi'), vals = unique(t.Theta); else, vals = unique(t.Phi); end
            if isempty(vals), return, end
            app.H.cutVal.Limits = [min(vals) max(vals)];
            if numel(vals) > 1, app.H.cutVal.Step = min(diff(vals)); end
            [~, k] = min(abs(vals - app.H.cutVal.Value));
            app.H.cutVal.Value = vals(k);
        end
    end
    %% -------------------------------------------------- unified range engine
    methods (Access = private)
        function [slider, lo, hi] = rangeWidgets(app, group)
            %RANGEWIDGETS Every range group is exactly one slider + two spinners.
            keys = struct('full',{{'rngFull','cmin','cmax'}}, 'cut',{{'rngCut','minCut','maxCut'}}, ...
                          'cov', {{'covXrng','covXmin','covXmax'}});
            k = keys.(group);
            [slider, lo, hi] = deal(app.H.(k{1}), app.H.(k{2}), app.H.(k{3}));
        end

        function setRange(app, group, value, silent)
            %SETRANGE Single entry point for every min/max/slider interaction.
            if nargin < 4, silent = false; end
            v = clampRange(value, app.LIM);
            app.S.lim.(group) = v;
            [slider, lo, hi] = app.rangeWidgets(group);
            set(slider, 'Limits', app.LIM, 'Value', v);
            set(lo, 'Limits', [app.LIM(1) v(2)-1e-3], 'Value', v(1));
            set(hi, 'Limits', [v(1)+1e-3 app.LIM(2)], 'Value', v(2));
            switch group
                case 'full'
                    if ~isARComponent(app.comp()), app.S.lim.gain = v; end
                    if ~silent, app.drawAllViews(); end
                case 'cut'
                    if ~silent, app.drawCut(); end
                case 'cov'
                    app.S.covUserRange = ~silent;
                    if ~silent, app.drawCoverage(); end
            end
        end

        function autoRange(app, redraw)
            if nargin < 2, redraw = true; end
            if isempty(app.S.view), return, end
            if isARComponent(app.comp())
                r = [-30 30];
            else
                r = gainWindow(app.S.view.(app.comp()), app.PEAK);
                app.S.lim.gain = r;
            end
            app.setRange('full', r, true);
            app.setRange('cut',  r, true);
            if redraw, app.drawAllViews(); app.drawCut(); end
        end

        function [lims, cmap] = theme(app)
            persistent gainMap arMap
            if isempty(gainMap), gainMap = jet(256); arMap = arColormap(); end
            ar = isARComponent(app.comp());                 % signed AR keeps its own scale
            lims = ternaryMat(ar, [-30 30], app.S.lim.full);
            cmap = ternaryMat(ar, arMap, gainMap);
        end
    end
    %% ------------------------------------------------------------ rendering
    methods (Access = private)
        function [th, ph, G] = gridOf(app, column)
            %GRIDOF Memoized [nTheta x nPhi] matrix for one table column.
            app.ensure('grid');
            g = app.S.grid; th = g.theta; ph = g.phi;
            key = matlab.lang.makeValidName(column);
            if isfield(g.comp, key), G = g.comp.(key); return, end
            G = nan(g.sz);
            G(g.lin) = app.S.view.(column);
            app.S.grid.comp.(key) = G;
        end

        function q = geom(app)
            %GEOM Memoized direction-cosine geometry for the current grid.
            if ~isempty(fieldnames(app.S.grid.geom)), q = app.S.grid.geom; return, end
            g = app.S.grid;
            [P, T] = meshgrid(g.phi, g.theta);
            Tp = T; if app.elevation(), Tp = 90 - T; end
            pr = deg2rad(P); st = sind(Tp);
            q = struct('P',P,'T',T,'Tp',Tp,'x',st.*cos(pr),'y',st.*sin(pr),'z',cosd(Tp));
            app.S.grid.geom = q;
        end
        function drawAllViews(app)
            if isempty(app.S.view), return, end
            app.clearAnnos('view');
            for v = app.VIEWS, app.drawView(v); end
            app.apply3DView();
        end

        function drawView(app, v)
            ax = app.H.(['ax_' v.key]);
            [th, ph, G] = app.gridOf(app.comp());
            [lims, cmap] = app.theme();
            q = app.geom();
            cla(ax, 'reset'); hold(ax, 'on');
            label = app.compLabel();
            [X, Y, Z] = project(v.kind, q.P, ternaryMat(v.cart, q.T, q.Tp), G, lims);
            sfc = surf(ax, X, Y, Z, G, 'EdgeColor','none');
            if v.cart
                if strcmp(v.kind,'rect3d'), view(ax, [-37.5 30]); zlabel(ax,'dB'); ax.ZLim = lims;
                else, view(ax, 2);
                end
                app.formatAngular(ax);
            elseif strcmp(v.kind, 'circular')
                view(ax, 2); axis(ax,'equal'); axis(ax,'off'); drawFisheyeGrid(ax);
            else
                app.format3D(ax, 1.05);
            end
            title(ax, sprintf('%s — %s', label, v.title));
            clim(ax, lims); colormap(ax, cmap);
            applyBarTicks(colorbar(ax), lims, app.H.cstep.Value);
            patternDataTip(sfc, th, ph, G, label);
            if app.H.cbOv.Value, app.overlayCut(ax, v); end
            app.addPOB(ax, v.kind);
            ax.Interactions = [ternaryMat(v.view3, rotateInteraction, panInteraction) ...
                dataTipInteraction zoomInteraction];
        end

        function formatAngular(app, ax)
            if app.signedPhi(), xl = [-180 180]; else, xl = [0 360]; end
            if app.elevation(), yl = [-90 90]; dir = 'normal'; else, yl = [0 180]; dir = 'reverse'; end
            set(ax, 'XLim',xl, 'YLim',yl, 'YDir',dir, 'Box','on', 'Layer','top');
            ax.XTick = xl(1):30:xl(2); ax.YTick = yl(1):15:yl(2);
            xlabel(ax,'Phi (degree)'); ylabel(ax,'Theta (degree)');
        end

        function format3D(~, ax, span)
            axis(ax, 'equal'); axis(ax, 'off'); rotate3d(ax, 'on');
            L = span * 1.15; e = eye(3); names = 'XYZ';
            for k = 1:3
                seg = [-L; L] * e(k,:);
                plot3(ax, seg(:,1), seg(:,2), seg(:,3), 'k-', 'LineWidth',0.5, 'HandleVisibility','off');
                text(ax, L*e(k,1), L*e(k,2), L*e(k,3), names(k));
            end
        end

        function apply3DView(app)
            k = find(strcmp(app.H.view3d.Items, app.H.view3d.Value), 1);
            angles = [-37.5 30; 0 90; 0 -90; 0 0; 180 0; 90 0; -90 0];
            for v = app.VIEWS(strcmp({app.VIEWS.kind}, 'sph3d') | strcmp({app.VIEWS.kind}, 'pol3d'))
                view(app.H.(['ax_' v.key]), angles(k,1), angles(k,2));
            end
        end

        function overlayCut(app, ax, v)
            [ang, data, ~, ~, gm] = app.cutData();
            if isempty(ang), return, end
            [X, Y, Z] = project(v.kind, gm.phi, ternaryMat(v.cart, gm.theta, gm.thetaPolar), data(:,1), app.S.lim.full, 1.01);
            style = ternary(v.cart && ~strcmp(v.kind,'rect3d'), 'w--', 'k-');
            plot3(ax, X, Y, Z, style, 'LineWidth', 1.4, 'HandleVisibility','off');
        end
    end
    %% ------------------------------------------------------------ cut plots
    %% ------------------------------------------------------------ cut plots
    methods (Access = private)
        function [cols, idx] = cutColumns(app)
            if app.gainOnly(), cols = string(app.comp()); idx = 1; return, end
            if strcmp(app.H.basis.Value, 'Linear')
                all3 = ["E_Total_dB","E_TH_dB","E_PH_dB"];  pair = {'E_TH','E_PH'};
            else
                all3 = ["E_Total_dB","E_RCP_dB","E_LCP_dB"]; pair = {'E_RCP','E_LCP'};
            end
            if ~strcmp(app.H.cbR.Text, pair{1}), [app.H.cbR.Text, app.H.cbL.Text] = pair{:}; end
            sel = logical([app.H.cbT.Value, app.H.cbR.Value, app.H.cbL.Value]);
            if ~any(sel), sel(1) = true; end
            idx = find(sel); cols = all3(idx);
        end

        function [ang, data, names, ttl, gm, idx] = cutData(app)
            t = app.S.view;
            [cols, idx] = app.cutColumns();
            type = string(app.H.cutType.Value);
            [ang, rows, fixed, sym, snapped] = cutRows(t, type, app.H.cutVal.Value, physTheta(t));
            sub  = t(rows, :);
            data = sub{:, cellstr(cols)};
            gm   = struct('theta', sub.Theta, 'thetaPolar', physTheta(sub), 'phi', sub.Phi, ...
                          'fixed', fixed, 'type', type);
            if app.signedPhi(), ang(ang > 180) = ang(ang > 180) - 360; [ang, o] = sort(ang);
            else,               o = (1:numel(ang)).';
            end
            [ang, u] = unique(ang(:), 'stable'); o = o(u);
            data = data(o, :); gm = reindex(gm, o);
            if type == "Phi", [ang, data, gm] = closeSeam(ang, data, gm, app.signedPhi()); end
            names = replace(cols, "_", "\_");
            ttl = ternary(app.gainOnly(), char(app.compLabel()), ...
                          sprintf('%s cut @ %s = %g°', type, sym, fixed));
            if snapped, app.setStatus('main', sprintf('Cut snapped to nearest %s = %g°.', sym, fixed), true); end
        end

        function drawCut(app)
            if isempty(app.S.view), return, end
            app.clearAnnos('cut');
            [ang, data, names, ttl, ~, idx] = app.cutData();
            pax = app.H.axPolar; rax = app.H.axRect;
            cla(pax); cla(rax); hold(pax,'on'); hold(rax,'on');
            lims = app.S.lim.cut;
            if lims(1) == lims(2), lims(2) = lims(1) + 1; end

            pl = polarplot(pax, deg2rad(ang), max(data, lims(1)), 'LineWidth', 1.4);
            rl = plot(rax, ang, data, 'LineWidth', 1.4);
            co = rax.ColorOrder;
            colors = num2cell(co(1 + mod(idx(:)-1, size(co,1)), :), 2);
            set(pl(:), {'Color'}, colors); set(rl(:), {'Color'}, colors);
            for k = 1:numel(pl)
                tip = [dataTipTextRow("Angle", ang, '%.3g°'), dataTipTextRow("Magnitude", data(:,k), '%.3g dB')];
                pl(k).DataTipTemplate.DataTipRows = tip;
                rl(k).DataTipTemplate.DataTipRows = tip;
            end
            set(pax, 'ThetaDir','clockwise', 'ThetaZeroLocation','top', 'RLim', lims, ...
                     'RTick', lims(1):max(round(diff(lims)/6),1):lims(2));
            polarSpanTicks(pax, app.signedPhi());
            xl = ternaryMat(app.signedPhi(), [-180 180], [0 360]);
            set(rax, 'YLim',lims, 'XLim',xl, 'XTick',xl(1):30:xl(2), 'XGrid','on','YGrid','on');
            xlabel(rax, ternary(strcmp(app.H.cutType.Value,'Phi'), 'Phi (degree)', 'Theta (degree)'));
            title(pax, ttl, 'Interpreter','none'); title(rax, ttl, 'Interpreter','none');
            legend(rax, cellstr(names), 'Location','best', 'Interpreter','tex');

            % Cut POB is the peak of the plotted curve, not the 3-D pattern peak.
            [pk, pi] = max(data(:,1), [], 'omitnan');
            if isfinite(pk)
                app.addAnno('cut', polarplot(pax, deg2rad(ang(pi)), max(pk,lims(1)), 'ko', ...
                    'MarkerFaceColor','k','MarkerSize',6,'HandleVisibility','off'));
                app.addAnno('cut', plot(rax, ang(pi), pk, 'ko','MarkerFaceColor','k', ...
                    'MarkerSize',6,'HandleVisibility','off'));
            end

            app.H.hpbwLab.Text = '';
            [bw, lo, hi] = deal(NaN);
            if app.H.hpbwBtn.Value && isfinite(pk), [bw, lo, hi] = calcHPBW(ang, data(:,1), pk, ang(pi)); end
            if isfinite(bw)
                b = mod([lo hi] - xl(1), 360) + xl(1);          % wrap into the displayed span
                app.H.hpbwLab.Text = sprintf('HPBW\n%.1f°\n(%.1f° … %.1f°)', bw, b(1), b(2));
                reg = ternaryMat(b(1) <= b(2), b, [xl(1) b(2); b(1) xl(2)]);
                thetaregion(pax, deg2rad(reg(:,1)), deg2rad(reg(:,2)), 'FaceColor','#D95319','FaceAlpha',0.12);
                xregion(rax, reg(:,1), reg(:,2), 'FaceColor','#D95319','FaceAlpha',0.12);
                if app.H.cbHB.Value
                    app.addAnno('cut', plot(rax, b, [pk-3 pk-3], 'o', 'Color','#D95319', ...
                        'LineStyle','none','MarkerFaceColor','#D95319','HandleVisibility','off'));
                end
            end
            app.refreshAnnotations();
        end

    end
    %% ---------------------------------------------------------- annotations
    methods (Access = private)
        function addAnno(app, scope, h)
            app.S.anno{end+1} = struct('scope', scope, 'h', h);
        end

        function addPOB(app, ax, kind)
            if ~isfinite(app.S.pob.val), return, end
            thp = app.S.pob.th; if app.elevation(), thp = 90 - thp; end
            cart = any(strcmp(kind, {'contour','rect3d'}));
            [x, y, z] = project(kind, app.S.pob.ph, ternaryMat(cart, app.S.pob.th, thp), ...
                app.S.pob.val, app.S.lim.full, 1.02);
            m = plot3(ax, x, y, z, 'ko', 'MarkerFaceColor','k', 'MarkerSize',6, ...
                'Clipping','off', 'HandleVisibility','off');
            m.DataTipTemplate.DataTipRows = [ ...
                dataTipTextRow("θ", app.S.pob.th, '%.3g°'); dataTipTextRow("φ", app.S.pob.ph, '%.3g°'); ...
                dataTipTextRow("POB", app.S.pob.val, '%.3g dB')];
            app.addAnno('view', m);
        end

        function refreshAnnotations(app)
            on = app.H.cbPOB.Value;
            for k = 1:numel(app.S.anno)
                h = app.S.anno{k}.h;
                if isgraphics(h), h.Visible = on; end
            end
        end

        function clearAnnos(app, scope)
            keep = true(1, numel(app.S.anno));
            for k = 1:numel(app.S.anno)
                if strcmp(app.S.anno{k}.scope, scope)
                    if isgraphics(app.S.anno{k}.h), delete(app.S.anno{k}.h); end
                    keep(k) = false;
                end
            end
            app.S.anno = app.S.anno(keep);
        end
    end
    %% ------------------------------------------------------ tables & status
    methods (Access = private)
        function l = compLabel(app)
            k = string(app.comp());
            hit = find([app.COMPS.key] == k, 1);
            if isempty(hit), l = replace(k, "_", " "); else, l = app.COMPS(hit).lab; end
        end

        function s = headline(app)
            s = sprintf('Pattern: <b>%s</b> | POB <b>%s dB</b> (<b>θ=%s°, φ=%s°</b>)', ...
                app.S.file.name, num2str(app.S.pob.val,'%.2f'), fmtNum(app.S.pob.th), fmtNum(app.S.pob.ph));
            if ~app.gainOnly() && ~strcmpi(strtrim(app.S.pol),'n/a')
                s = sprintf('%s | Polarization <b>%s</b>', s, app.S.pol);
            end
        end

        function fillOutputTable(app)
            t = app.S.view;
            if isempty(t), return, end
            keep = ~ismember(t.Properties.VariableNames, app.HIDECOLS);
            shown = t(:, keep);
            c = app.comp();
            if ismember(c, shown.Properties.VariableNames)
                floors = [-Inf, app.S.pob.val-3, app.S.pob.val-10, 0];
                shown = shown(shown.(c) >= floors(strcmp(app.H.outFilt.Items, app.H.outFilt.Value)), :);
            end
            app.H.tblOut.Data = shown;
            app.H.tblOut.ColumnName = shown.Properties.VariableNames;
        end
        function fillInputTable(app)
            if app.S.rawShown || isempty(app.S.raw), return, end
            app.H.tblIn.Data = app.S.raw;
            app.H.tblIn.ColumnName = app.S.raw.Properties.VariableNames;
            app.S.rawShown = true;
        end

        function fillMetadata(app)
            t = app.S.view; m = app.S.metrics;
            th = unique(t.Theta); ph = unique(t.Phi);
            rows = { ...
                'Source format', app.S.src.source
                'File',          app.S.file.name
                'Samples',       sprintf('%d (θ:%d × φ:%d)', height(t), numel(th), numel(ph))
                'θ range / step',sprintf('[%s°, %s°] / %s°', fmtNum(min(th)), fmtNum(max(th)), fmtNum(gridStep(th)))
                'φ range / step',sprintf('[%s°, %s°] / %s°', fmtNum(min(ph)), fmtNum(max(ph)), fmtNum(gridStep(ph)))
                'Peak gain (POB)',     sprintf('%s dB', fmtNum(app.S.pob.val))
                'POB direction [θ,φ]', sprintf('[%s°, %s°]', fmtNum(app.S.pob.th), fmtNum(app.S.pob.ph))
                'Boresight axis',      app.AX6.label{app.S.axis}
                'Peak policy',         sprintf('P%.4g, max excess %.4g dB', app.PEAK.pct, app.PEAK.maxExcessDB)
                'Peak adjusted',       char(string(isfield(app.S.peak,'adjusted') && app.S.peak.adjusted))};
            f = app.S.freqs(isfinite(app.S.freqs));
            if ~isempty(f), rows(end+1,:) = {'Frequencies', strjoin(compose('%.4g GHz', f/1e9), ', ')}; end
            if ~app.gainOnly()
                rows = [rows; {'Polarization', app.S.pol; ...
                    'Cut co/cross', char(strjoin(app.S.pairs.(app.H.basis.Value), ' / '))}];
            end
            if isfield(m, 'HPBW_E')
                extra = {'HPBW E-plane', m.HPBW_E, '%s°'; 'HPBW H-plane', m.HPBW_H, '%s°'; ...
                         'Front-to-back', m.FrontBack, '%s dB'; 'Peak directivity', m.Directivity, '%s dB'; ...
                         'Radiation efficiency', m.Efficiency, '%s%%'; 'AR at peak', m.ARatPeak, '%s dB'};
                for k = 1:size(extra,1)
                    if isfinite(extra{k,2}), rows(end+1,:) = {extra{k,1}, sprintf(extra{k,3}, fmtNum(extra{k,2}))}; end %#ok<AGROW>
                end
            end
            app.H.tblMeta.Data = rows;
        end

        function setStatus(app, which, msg, transient)
            if app.isClosing, return, end
            lbl = ternary(strcmp(which,'cov'), app.H.covStat, app.H.status);
            app.stopTimer();
            lbl.Text = char(msg);
            if nargin >= 4 && transient
                app.S.timer = timer('ExecutionMode','singleShot','StartDelay',3, ...
                    'TimerFcn', @(~,~) app.restoreStatus(lbl));
                start(app.S.timer);
            end
        end
        function restoreStatus(app, lbl)
            if app.isClosing || ~isgraphics(lbl), return, end
            lbl.Text = ternary(isequal(lbl, app.H.status), app.headline(), 'Coverage idle.');
        end
        function stopTimer(app)
            if ~isempty(app.S.timer) && isvalid(app.S.timer), stop(app.S.timer); delete(app.S.timer); end
            app.S.timer = [];
        end
        function guard = busy(app, msg)
            %BUSY Modal progress dialog, closed when GUARD leaves the caller's scope.
            app.S.dlg = uiprogressdlg(app.UIFigure, 'Message', msg, 'Indeterminate','on', 'Title', app.RELEASE);
            guard = onCleanup(@() delete(app.S.dlg));
        end
        function showError(app, err, ttl)
            uialert(app.UIFigure, err.message, ttl);
        end
    end
    %% ---------------------------------------------------------- user actions
    methods (Access = private)
        function onLoad(app)
            filters = {'*.ffd;*.ffe;*.ffs;*.uan;*.fz;*.out;*.cut;*.csv;*.txt;*.dat;*.xlsx;*.xls', ...
                       'Antenna pattern files'; '*.*','All files'};
            [f, p] = uigetfile(filters, 'Select an antenna pattern file');
            figure(app.UIFigure);
            if isequal(f, 0), return, end
            app.loadPath(fullfile(p, f));
        end
        function onReload(app)
            if ~isempty(app.S.file.path), app.loadPath(app.S.file.path); end
        end

        function loadPath(app, fp)
            busyGuard = app.busy('Reading source file …');
            try
                [~, base, ext] = fileparts(fp);
                app.S.file = struct('name',[base ext],'path',fp,'folder',fileparts(fp),'base',base);
                app.H.path.Value = fp;
                [src, generic] = readWithFormat(fp, app.H.txtfmt.Value);
                assert(~src.userData.isCoverage, 'apat:io:Coverage', ...
                    'This file holds coverage results — load it on the Coverage tab.');
                set([app.H.l_txtfmt app.H.txtfmt], 'Visible', generic);
                [app.S.raw, app.S.blocks, app.S.freqs, app.S.src] = ...
                    deal(src.rawTbl, src.blocks, src.freqs, src.userData);
                app.S.rawShown = false;
                nb = numel(src.blocks);
                [app.H.ffd.Items, app.H.ffd.ItemsData] = deal(cellstr(blockLabels(src.freqs, nb)), num2cell(1:nb));
                app.H.ffd.Value = 1;
                set([app.H.l_ffd app.H.ffd], 'Visible', nb > 1);
                app.invalidate('std');
                app.setStatus('main', sprintf('Loaded <b>%s</b> (%s) — press <b>Process</b>.', ...
                    app.S.file.name, app.S.src.source), false);
            catch err
                app.showError(err, 'Load failed');
            end
        end

        function onProcess(app)
            if isempty(app.S.blocks)
                uialert(app.UIFigure, 'Load an antenna pattern file first.', 'Process'); return
            end
            busyGuard = app.busy('Processing pattern …');
            try
                app.invalidate('std'); app.ensure('grid');
                app.autoRange(false); app.refreshAll(true);
                set([app.H.panFull app.H.panCut app.H.panCtrl], 'Visible','on');
                hasE = ~app.gainOnly();
                app.H.expOut.Visible = 'on';
                set([app.H.expUAN app.H.cbT app.H.cbR app.H.cbL], 'Visible', hasE);
                app.H.basis.Enable = hasE;
            catch err
                app.showError(err, 'Processing failed');
            end
        end
        function onResetParams(app)
            d = app.S.defaults.raw;
            app.H.loss.Value=d.loss; app.H.rxpol.Value=d.rxpol; app.H.rw.Value=d.rw;
            app.H.pt.Value=d.pt; app.H.ptu.Value=d.ptu; app.H.r.Value=d.r; app.H.ru.Value=d.ru;
            app.recompute('pattern');
        end

        function onComponent(app)
            app.resolvePeakForComponent();
            if isARComponent(app.comp()), app.setRange('full', [-30 30], true);
            else, app.setRange('full', app.S.lim.gain, true);
            end
            app.fillOutputTable(); app.fillMetadata();
            app.drawAllViews(); app.drawCut();
        end

        function onCutType(app), app.syncCutControl(); app.drawCut(); app.drawAllViews(); end
        function onBasis(app), app.H.basis.UserData = false; app.drawCut(); end
        function onPlane(app)
            [app.H.cutType.Value, app.H.cutVal.Value] = ...
                planeCut(app.AX6, app.S.axis, app.elevation(), strcmp(app.H.eh.Value,'E'));
            app.syncCutControl(); app.drawCut(); app.drawAllViews();
        end
        function onExportTable(app)
            app.exportTo(app.S.view, [app.S.file.base '_APAT_output'], 'Export processed table');
        end
        function onExportCut(app)
            [ang, data, names] = app.cutData();
            vars = matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(["Angle_deg", names]));
            app.exportTo(array2table([ang data], 'VariableNames', vars), [app.S.file.base '_cut'], 'Export cut');
        end

        function onExportUAN(app)
            t = app.S.view;
            app.S.uan = table(t.Theta, t.Phi, t.E_TH_dB, t.E_PH_dB, t.E_TH_Phase, t.E_PH_Phase, ...
                'VariableNames', {'Theta','Phi','E_TH_dB','E_PH_dB','E_TH_deg','E_PH_deg'});
            fp = app.askSave({'*.uan','XGTD UAN'}, 'Export UAN', [app.S.file.base '.uan']);
            if isempty(fp), return, end
            writeUAN(app.S.uan, fp);
            app.setStatus('main', sprintf('UAN written to <b>%s</b>.', fp), true);
        end
        function exportTo(app, t, suggested, ttl)
            fp = app.askSave({'*.csv','CSV';'*.xlsx','Excel';'*.txt','Text'}, ttl, suggested);
            if isempty(fp), return, end
            writetable(t, fp);
            app.setStatus('main', sprintf('Saved <b>%s</b>.', fp), true);
        end
        function fp = askSave(app, filters, ttl, suggested)
            [f, d] = uiputfile(filters, ttl, suggested);
            figure(app.UIFigure);
            fp = ternary(isequal(f, 0), '', fullfile(d, f));
        end

    end
    %% ---------------------------------------------------------- coverage tab
    methods (Access = private)
        function onCovRegion(app)
            conical = app.H.rCon.Value;
            set([app.H.l_covOri app.H.covOri app.H.l_coneTh app.H.coneTh app.H.l_conePh ...
                 app.H.conePh app.H.l_coneAng app.H.coneAng], 'Enable', conical);
        end

        function onCovLoad(app, fp)
            if nargin < 2 || isempty(fp)
                [f, p] = uigetfile({'*.ffd;*.ffe;*.ffs;*.uan;*.fz;*.out;*.cut;*.csv;*.txt;*.dat;*.xlsx;*.xls', ...
                    'Pattern or coverage-result files'}, 'Load for coverage');
                figure(app.UIFigure);
                if isequal(f,0), return, end
                fp = fullfile(p, f);
            end
            busyGuard = app.busy('Reading coverage source …');
            try
                app.S.covLastPath = fp;
                app.H.covPath.Value = fp;
                [~, base] = fileparts(fp);
                [src, generic] = readWithFormat(fp, app.H.covTxt.Value);
                set([app.H.l_covTxt app.H.covTxt], 'Visible', generic && ~src.userData.isCoverage);
                if src.userData.isCoverage
                    app.covImportResults(base, src.rawTbl);
                else
                    std = normalizePattern(src.blocks{1});
                    std.Properties.UserData = src.userData;
                    pat = calcPattern(std, app.params(), app.PEAK);
                    w   = solidWeights(physTheta(pat), pat.Phi, gridStep(pat.Theta), gridStep(mod(pat.Phi,360)));
                    node = uitreenode(app.H.covTree, 'Text', ['📡 ' base]);
                    node.NodeData = struct('kind','pattern','name',base,'path',fp, ...
                        'pattern',pat,'dOmega',w,'axis',orientationAxis(pat,w,'E_Total_dB',app.AX6,app.PEAK), ...
                        'cache',struct());
                    app.H.covTree.SelectedNodes = node;
                    app.setStatus('cov', sprintf('Pattern <b>%s</b> ready for coverage.', base), false);
                end
            catch err
                app.showError(err, 'Coverage load failed');
            end
        end

        function node = covTarget(app)
            %COVTARGET Nearest enclosing pattern node, else the last one loaded.
            isPattern = @(n) isstruct(n.NodeData) && strcmp(n.NodeData.kind, 'pattern');
            node = app.H.covTree.SelectedNodes;
            while ~isempty(node) && isa(node,'matlab.ui.container.TreeNode') && ~isPattern(node)
                node = node.Parent;
            end
            if isa(node,'matlab.ui.container.TreeNode') && isPattern(node), return, end
            kids = app.H.covTree.Children;
            hit = arrayfun(isPattern, kids);
            node = ternaryMat(any(hit), kids(find(hit,1,'last')), []);
        end
        function thr = covThresholds(app)
            lo = app.H.thrMin.Value; st = abs(app.H.thrStep.Value);
            hi = max(app.H.thrMax.Value, lo + max(st,1)); app.H.thrMax.Value = hi;
            thr = unique([(lo:st:hi).'; hi]);
        end

        function onCovRun(app)
            node = app.covTarget();
            if isempty(node)
                uialert(app.UIFigure, 'Load or select an antenna pattern node first.', 'Coverage'); return
            end
            busyGuard = app.busy('Computing coverage CCDF …');
            try
                d = node.NodeData; pat = d.pattern;
                comp = app.H.covComp.Value; thr = app.covThresholds();
                if app.H.rCon.Value
                    if app.H.covOri.Value > 0
                        app.H.coneTh.Value = app.AX6.theta(app.H.covOri.Value);
                        app.H.conePh.Value = app.AX6.phi(app.H.covOri.Value);
                    end
                    ct = app.H.coneTh.Value; cp = mod(app.H.conePh.Value, 360); ca = app.H.coneAng.Value;
                    mask  = coneMask(physTheta(pat), pat.Phi, ct, cp, ca);
                    tag   = sprintf('Con_%g_%g_%g', ct, cp, ca);
                    label = sprintf('Conical (θ=%g°, φ=%g°) α=%g°', ct, cp, ca);
                else
                    mask = true(height(pat),1); tag = 'Sph'; label = 'Spherical (4π)';
                end
                key = matlab.lang.makeValidName(sprintf('%s_%s_%g_%g_%g', tag, comp, thr(1), thr(end), numel(thr)));
                reused = isfield(d.cache, key);
                if reused, cov = d.cache.(key);
                else, cov = coverageCCDF(pat.(comp), mask, thr, d.dOmega); d.cache.(key) = cov; node.NodeData = d;
                end
                app.S.covID = app.S.covID + 1;
                job = uitreenode(node, 'Text', sprintf('R%d · %s · %s', app.S.covID, label, comp));
                job.NodeData = struct('kind','job','id',app.S.covID,'thr',thr,'cov',cov,'label',label);
                expand(node);
                app.H.covTree.CheckedNodes = [app.H.covTree.CheckedNodes; job];
                if ~app.S.covUserRange, app.setRange('cov', [thr(1) thr(end)], true); end
                app.drawCoverage();
                app.setStatus('cov', sprintf('Run <b>R%d</b> %s: <b>%s</b> · %s · %d thresholds.', app.S.covID, ...
                    ternary(reused,'reused cached CCDF','computed'), label, comp, numel(thr)), false);
            catch err
                app.showError(err, 'Coverage error');
            end
        end

        function covImportResults(app, name, t)
            node = uitreenode(app.H.covNodeRes, 'Text', ['📄 ' name]);
            node.NodeData = struct('kind','results','name',name);
            thr = t{:,1}; checked = app.H.covTree.CheckedNodes;
            for c = 2:width(t)
                app.S.covID = app.S.covID + 1;
                job = uitreenode(node, 'Text', sprintf('R%d · %s', app.S.covID, t.Properties.VariableNames{c}));
                job.NodeData = struct('kind','job','id',app.S.covID,'thr',thr,'cov',t{:,c}, ...
                    'label',t.Properties.VariableNames{c});
                checked = [checked; job]; %#ok<AGROW>
            end
            expand(node); expand(app.H.covNodeRes);
            app.H.covTree.CheckedNodes = checked;
            app.setRange('cov', [min(thr) max(thr)], true);
            app.drawCoverage();
            app.setStatus('cov', sprintf('Imported <b>%s</b> (%d curves).', name, width(t)-1), false);
        end

        function jobs = covJobs(app)
            all = findobj(app.H.covTree, 'Type','uitreenode');
            jobs = all(arrayfun(@(n) isstruct(n.NodeData) && strcmp(n.NodeData.kind,'job'), all));
            if numel(jobs) > 1
                [~, o] = sort(arrayfun(@(n) n.NodeData.id, jobs)); jobs = jobs(o);
            end
        end

        function shown = drawCoverage(app)
            ax = app.H.covAxes; cla(ax); hold(ax,'on'); grid(ax,'on');
            jobs = app.covJobs();
            shown = jobs(ismember(jobs, app.H.covTree.CheckedNodes));
            cols = ax.ColorOrder; names = cell(1, numel(shown));
            for k = 1:numel(shown)
                d = shown(k).NodeData;
                ln = plot(ax, d.thr, d.cov, 'LineWidth', 1.6, 'Color', cols(1+mod(k-1,size(cols,1)),:));
                ln.DataTipTemplate.DataTipRows = [dataTipTextRow("Threshold", d.thr, '%.3g dB'); ...
                                                  dataTipTextRow("Coverage",  d.cov, '%.2f %%')];
                names{k} = sprintf('R%d %s', d.id, d.label);
            end
            xlabel(ax,'Threshold (dB)'); ylabel(ax,'Coverage (%)');
            ax.XLim = app.S.lim.cov; ax.YLim = [0 100];
            if isempty(names), legend(ax,'off'); else, legend(ax, names, 'Location','southwest'); end
            % One resampled comparison table over the displayed threshold window.
            if isempty(shown), app.H.covTbl.Data = table();
            else
                st = min(arrayfun(@(n) gridStep(n.NodeData.thr), shown));
                if ~isfinite(st) || st <= 0, st = 1; end
                thr = (app.S.lim.cov(1):st:app.S.lim.cov(2)).';
                data = cell2mat(arrayfun(@(n) interp1(n.NodeData.thr, n.NodeData.cov, thr, 'linear', NaN), ...
                    shown(:).', 'UniformOutput', false));
                names = ['Threshold_dB', compose('R%d_pct', arrayfun(@(n) n.NodeData.id, shown(:).'))];
                app.H.covTbl.Data = array2table([thr data], 'VariableNames', cellstr(names));
            end
            app.H.panCovR.Visible = 'on';
        end

        function covQuery(app, mode)
            shown = app.drawCoverage();
            if isempty(shown), app.setStatus('cov','No coverage curve selected.', true); return, end
            d = shown(end).NodeData;
            if strcmp(mode, 'thr')
                x = app.H.qThr.Value; y = interp1(d.thr, d.cov, x, 'linear', NaN);
            else
                y = app.H.qCov.Value; [u, iu] = unique(d.cov, 'stable');
                x = interp1(u, d.thr(iu), y, 'linear', NaN);
            end
            app.H.qCov.Value = max(0, min(100, y));
            app.H.qThr.Value = max(app.LIM(1), min(app.LIM(2), x));
            plot(app.H.covAxes, x, y, 'kd', 'MarkerFaceColor','y','MarkerSize',9,'HandleVisibility','off');
            app.setStatus('cov', sprintf('R%d: <b>%.3g dB</b> ↔ <b>%.2f %%</b>.', d.id, x, y), false);
        end

        function onCovReset(app), app.covPrune([]); end
        function onCovClear(app), app.covPrune(app.H.covTree.SelectedNodes); end

        function covPrune(app, node)
            %COVPRUNE Delete one node, or rebuild an empty tree when none is given.
            if isempty(node)
                delete(app.H.covTree.Children);
                app.mk('covNodeRes','covTree','node',[],[], {'Text','📁 Loaded results'});
                app.S.covID = 0; app.S.covUserRange = false;
                cla(app.H.covAxes); legend(app.H.covAxes,'off'); app.H.covTbl.Data = table();
                app.setStatus('cov','Coverage reset.', false);
            else
                delete(node); app.drawCoverage();
                app.setStatus('cov','Selected node removed.', true);
            end
        end

        function onCovExport(app)
            if isempty(app.H.covTbl.Data)
                uialert(app.UIFigure,'Nothing to export.','Coverage'); return
            end
            fp = app.askSave({'*.csv','CSV';'*.xlsx','Excel'}, 'Export coverage', 'APAT_coverage.csv');
            if isempty(fp), return, end
            writetable(app.H.covTbl.Data, fp);
            app.setStatus('cov', sprintf('Coverage results saved to <b>%s</b>.', fp), true);
        end
    end
    %% -------------------------------------------------------- public API
    methods (Access = public)
        function report = selfTest(app)
            %SELFTEST Deterministic regression battery over the pure functional core.
            P = app.PEAK; t0 = tic;
            g = sin(linspace(0,40,500).')*8; w = ones(500,1); thr = (-20:20).'; a = (-90:0.5:90).';
            nz = normalizePattern(sampleTable());
            cases = { ...
              'canonical θ domain',       @() all(nz.Theta >= -1e-9 & nz.Theta <= 180+1e-9)
              'canonical φ domain',       @() all(nz.Phi >= -1e-9 & nz.Phi < 360+1e-9)
              'Σ dΩ ≈ 4π',                @() abs(sum(solidWeights((0:5:180).'*ones(1,73), ones(37,1)*(0:5:360), 5, 5),'all') - 4*pi) < 0.05
              'CCDF monotone in [0,100]', @() issorted(-coverageCCDF(g,true(500,1),thr,w)) && all(coverageCCDF(g,true(500,1),thr,w) <= 100)
              'peak policy rejects spike',@() resolvePeak([zeros(9999,1);40], P).adjusted
              'HPBW of cos² beam = 90°',  @() abs(calcHPBW(a, 20*log10(max(cosd(a),1e-6))) - 90) < 2
              'all derived components',   @() width(calcPattern(nz, app.params(), P)) >= 9
              'range clamp and order',    @() isequal(clampRange([200 -900], app.LIM), app.LIM)
              'stage graph invalidation', @() invalidateProbe(app)};
            n = size(cases,1); res = strings(n,1); det = strings(n,1);
            for k = 1:n
                try
                    passed = logical(cases{k,2}());
                    res(k) = ternary(passed, "pass", "FAIL");
                    det(k) = ternary(passed, "assertion held", "assertion returned false");
                catch err
                    res(k) = "ERROR"; det(k) = string(err.message);
                end
            end
            report = table(string(cases(:,1)), res, det, 'VariableNames', {'Test','Result','Detail'});
            fprintf('%s self-test: %d/%d passed in %.2f s\n', app.RELEASE, sum(res == "pass"), n, toc(t0));
        end
    end
end
%% ======================================================================
%  PURE CORE — no app handle, no graphics. Directly unit-testable.
%% ======================================================================
% ---------------------------------------------------------------- helpers
function out = ternary(cond, a, b), if cond, out = a; else, out = b; end, end
function m = ternaryMat(c, a, b), if c, m = a; else, m = b; end, end
function s = fmtNum(v)
if ~isfinite(v), s = 'n/a'; return, end
s = strtrim(sprintf('%.2f', v));
s = regexprep(s, '(\.\d*?[1-9])0+$', '$1');
s = regexprep(s, '\.0*$', '');
end
function r = clampRange(v, bounds)
v = sort(double(v(:)).');
r = [max(v(1), bounds(1)), min(v(2), bounds(2))];
if r(2) <= r(1), r(2) = min(bounds(2), r(1) + 1); end
end
function s = gridStep(v)
d = diff(unique(v(isfinite(v)))); d = d(d > 1e-9);
s = ternary(isempty(d), NaN, min(d));
end
function tf = isARComponent(name)
k = regexprep(lower(strtrim(char(name))), '[^a-z0-9]', '');
tf = strcmp(k,'ar') || startsWith(k,'ardb') || startsWith(k,'axialratio');
end
function c = arColormap()
c = interp1([-1 0 1], [0 0 1; 1 1 1; 1 0 0], linspace(-1,1,256));
end
function th = physTheta(t)
u = t.Properties.UserData;
elev = isstruct(u) && isfield(u,'thetaMode') && strcmp(u.thetaMode,'elevation');
th = ternaryMat(elev, 90 - t.Theta, t.Theta);
end
function labels = blockLabels(freqs, n)
labels = compose('Block %d', 1:n);
ok = numel(freqs) == n & isfinite(freqs(:).');
if any(ok), labels(ok) = compose('%.6g GHz', freqs(ok)/1e9); end
end
function tf = invalidateProbe(app)
app.invalidate('pattern');
tf = app.S.dirty.pattern && app.S.dirty.view && app.S.dirty.grid;
end
function t = sampleTable()
[P, T] = meshgrid(0:10:350, 0:10:180);
E = cosd(T(:)/2).^2 + 1e-3;
t = table(T(:), P(:), E, zeros(size(E)), 0.1*E, zeros(size(E)), ...
    'VariableNames', {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'});
t.Properties.UserData = validateSource(struct());
end
% ------------------------------------------------------- source metadata
function m = validateSource(m)
if nargin == 0 || ~isstruct(m), m = struct(); end
d = {'source','unknown'; 'isGainOnly',false; 'isCoverage',false; 'isDep',false; ...
     'isMultiBlock',false; 'hasFrequency',false; 'absoluteCalibration',[]; 'polarizationBasis',"theta-phi"};
for k = 1:size(d,1)
    if ~isfield(m, d{k,1}) || isempty(m.(d{k,1})), m.(d{k,1}) = d{k,2}; end
end
if isempty(m.absoluteCalibration), m.absoluteCalibration = ~m.isGainOnly; end
if ~isfield(m,'quantityType'), m.quantityType = ternary(m.isGainOnly, "gain-like", "complex-electric-field"); end
end
% ---------------------------------------------------- canonical geometry
function t = normalizePattern(t)
%NORMALIZEPATTERN Fold any angular convention onto θ∈[0,180], φ∈[0,360).
th = t.Theta;
if any(th < -1e-9) && min(th,[],'omitnan') >= -90 && max(th,[],'omitnan') <= 90
    t.Theta = 90 - th;                       % elevation source → polar theta
end
t.Theta = mod(t.Theta, 360);
over = t.Theta > 180;
t.Theta(over) = 360 - t.Theta(over);
t.Phi(over)   = t.Phi(over) + 180;
num = varfun(@isnumeric, t, 'OutputFormat','uniform');
if any(num), t{:, num} = round(t{:, num}, 5); end
t.Phi = mod(t.Phi, 360);
[~, keep] = unique([t.Theta t.Phi], 'rows', 'stable');
t = t(sort(keep), :);
t = sortrows(t, {'Phi','Theta'});
end
function t = applySpan(t, signedPhi, elevation)
%APPLYSPAN Materialize the display convention from the canonical table.
if signedPhi
    t(abs(t.Phi - 360) <= 1e-9, :) = [];
    m = t.Phi > 180; t.Phi(m) = t.Phi(m) - 360;
    seam = abs(t.Phi - 180) < 1e-9;
    if any(seam), d = t(seam,:); d.Phi(:) = -180; t = [d; t]; end
end
if elevation, t.Theta = 90 - t.Theta; end
u = t.Properties.UserData; if ~isstruct(u), u = struct(); end
u.thetaMode = ternary(elevation, 'elevation', 'polar');
t.Properties.UserData = u;
if signedPhi || elevation, t = sortrows(t, {'Phi','Theta'}); end
end
function tf = needsResample(t, tol)
dth = gridStep(t.Theta); dph = gridStep(mod(t.Phi,360));
tf = ~isfinite(dth) || abs(dth-1) > tol || ~isfinite(dph) || abs(dph-1) > tol;
end
function t = downTo1Deg(t, tol)
%DOWNTO1DEG Decimate to the integer sub-grid when possible, else interpolate.
dth = gridStep(t.Theta); dph = gridStep(mod(t.Phi,360));
if isfinite(dth) && isfinite(dph) && dth < 1 && dph < 1
    keep = abs(t.Theta - round(t.Theta)) < tol & abs(t.Phi - round(t.Phi)) < tol;
    if any(keep), t = t(keep,:); return, end
end
t = resampleCanonical(t, 1);
end
function out = resampleCanonical(src, stepDeg)
%RESAMPLECANONICAL Regrid primitive quantities onto a uniform θ/φ lattice.
%   dB-valued columns are interpolated in linear power, never in dB.
names = string(src.Properties.VariableNames);
th = double(src.Theta); ph = mod(double(src.Phi), 360);
keep = isfinite(th) & isfinite(ph) & th >= -1e-9 & th <= 180+1e-9 & abs(double(src.Phi)-360) > 1e-9;
[src, th, ph] = deal(src(keep,:), th(keep), ph(keep));
[~, u] = unique([th ph], 'rows', 'stable');
[src, th, ph] = deal(src(u,:), th(u), ph(u));

tPh = (0:stepDeg:360).'; if tPh(end) ~= 360, tPh(end+1) = 360; end
[QP, QT] = meshgrid(tPh, (0:stepDeg:180).');
out = table(QT(:), QP(:), 'VariableNames', {'Theta','Phi'});

uTh = unique(th); uPh = unique(ph);
regular = numel(uTh)*numel(uPh) == numel(th);
if regular
    [~, ri] = ismember(th, uTh); [~, ci] = ismember(ph, uPh);
    lin = sub2ind([numel(uTh) numel(uPh)], ri, ci);
    pPh = [uPh; uPh(1)+360].';                       % periodic wrap column
end
for n = names(3:end)
    v = double(src.(n));
    isdb = endsWith(n, "_dB") || endsWith(n, "dBi");
    if isdb, v = 10.^(v/10); end
    if regular
        M = nan(numel(uTh), numel(uPh)); M(lin) = v; M = [M M(:,1)]; %#ok<AGROW>
        q = interp2(pPh, uTh, M, mod(QP,360), QT, 'linear');
        bad = isnan(q);
        q(bad) = interp2(pPh, uTh, M, mod(QP(bad),360), QT(bad), 'nearest');
    else
        F = scatteredInterpolant(ph, th, v, 'linear', 'nearest'); q = F(mod(QP,360), QT);
    end
    out.(n) = reshape(ternaryMat(isdb, 10*log10(max(q, eps)), q), [], 1);
end
out.Properties.UserData = src.Properties.UserData;
end
function dOmega = solidWeights(theta, phi, dth, dph)
%SOLIDWEIGHTS Exact per-cell solid angle for a uniform θ/φ lattice.
if nargin < 3 || ~isfinite(dth), dth = gridStep(theta); end
if nargin < 4 || ~isfinite(dph), dph = gridStep(mod(phi,360)); end
if ~isfinite(dth), dth = 180; end
if ~isfinite(dph), dph = 360; end
lo = max(theta - dth/2, 0); hi = min(theta + dth/2, 180);
dOmega = (cosd(lo) - cosd(hi)) * deg2rad(dph);
seam = 180*any(phi(:) < 0) + 360*~any(phi(:) < 0);
dOmega(abs(phi - seam) < 1e-9) = 0;               % never double-count the seam
end
function mask = coneMask(theta, phi, ct, cp, alpha)
mask = (cosd(theta).*cosd(ct) + sind(theta).*sind(ct).*cosd(phi - cp)) >= cosd(alpha);
end
function idx = orientationAxis(t, dOmega, column, AX6, peakPolicy) %#ok<INUSD>
%ORIENTATIONAXIS Principal axis whose 45° cone carries the most radiated energy.
if ~ismember(column, t.Properties.VariableNames), column = t.Properties.VariableNames{3}; end
g = 10.^(double(t.(column))/10);
th = physTheta(t); ph = t.Phi;
e = zeros(1, numel(AX6.theta));
for k = 1:numel(e)
    e(k) = sum(g .* dOmega .* coneMask(th, ph, AX6.theta(k), AX6.phi(k), 45), 'omitnan');
end
[~, idx] = max(e);
end
% ----------------------------------------------------------- peak policy
function info = resolvePeak(values, policy)
%RESOLVEPEAK Percentile-guarded maximum: rejects isolated numerical spikes.
v = double(values(:));
finite = isfinite(v);
info = struct('value',NaN,'index',1,'adjusted',false,'outliers',false(size(v)));
if ~any(finite), return, end
[raw, rawIdx] = max(v(finite));
fIdx = find(finite);
info.value = raw; info.index = fIdx(rawIdx);
if nnz(finite) < 20, return, end
pct = prctile(v(finite), policy.pct);
if ~isfinite(pct) || raw - pct <= policy.maxExcessDB, return, end
out = finite & (v > pct) & (v - pct > policy.maxExcessDB);
cand = finite & ~out;
if ~any(cand), return, end
tmp = v; tmp(~cand) = -Inf;
[info.value, info.index] = max(tmp);
info.outliers = out; info.adjusted = true;
end
function b = gainWindow(values, policy)
%GAINWINDOW 50 dB display window anchored on the guarded peak.
pk = resolvePeak(values, policy).value;
if ~isfinite(pk), b = [-50 0]; return, end
hi = ceil(pk/5)*5;
b = max(min([hi-50, hi], [100 100]), [-250 -250]);
end
% ------------------------------------------------------- pattern maths
function [out, info] = calcPattern(std, param, policy)
%CALCPATTERN Canonical source fields → every derived engineering quantity.
info = struct('pob',NaN,'th',NaN,'ph',NaN,'pol','n/a','peak',struct(), ...
    'pairs', struct('Linear',["E_TH","E_PH"],'Circular',["E_RCP","E_LCP"]));
ud = std.Properties.UserData;

if isfield(ud,'isGainOnly') && ud.isGainOnly
    out = std;
    if width(out) > 2, out{:,3:end} = out{:,3:end} + param.lossDB; end
    pk = resolvePeak(out{:,3}, policy);
    [info.peak, info.pob] = deal(pk, pk.value);
    [info.th, info.ph] = deal(out.Theta(pk.index), out.Phi(pk.index));
    return
end

Eth = complex(std.Re_Eth, std.Im_Eth) * param.fieldScale;
Eph = complex(std.Re_Eph, std.Im_Eph) * param.fieldScale;
Erc = (Eth + 1i*Eph)/sqrt(2);
Elc = (Eth - 1i*Eph)/sqrt(2);
[mt, mp, mr, ml] = deal(abs(Eth), abs(Eph), abs(Erc), abs(Elc));
total = 10*log10(max(mt.^2 + mp.^2, eps));

pk = resolvePeak(total, policy);
[info.peak, info.pob] = deal(pk, pk.value);
[info.th, info.ph] = deal(std.Theta(pk.index), std.Phi(pk.index));

% Dominant-polarization classification drives co/cross ordering and Auto-Rx.
P = cellfun(@(v) mean(v.^2,'omitnan'), {mt, mp, mr, ml});
if P(2) > P(1), info.pairs.Linear   = fliplr(info.pairs.Linear);   end
if P(4) > P(3), info.pairs.Circular = fliplr(info.pairs.Circular); end
if max(P(3:4)) > max(P(1:2))
    info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP","E_LCP"], ["RHCP","LHCP"]));
else
    info.pol = ternary(P(1) >= P(2), 'Linear (Vertical)', 'Linear (Horizontal)');
end

% Signed axial ratio: the sign carries handedness; equal components → −100 dB.
d = mr - ml;
arDB = 20*log10(max((mr + ml)./max(abs(d), eps), eps)) .* sign(d);
arDB(~isfinite(arDB) | (isfinite(d) & abs(d) <= eps(max(mr, ml)))) = -100;

[plf, ud.rxUsed] = polLossFactor(param, info, mt, mp, mr, ml);
gainPol = total + 10*log10(max(plf, eps));
eirp = param.PtdBW + gainPol;
dB20 = @(v) 20*log10(max(v, eps));

out = table(std.Theta, std.Phi, total, dB20(mt), dB20(mp), dB20(mr), dB20(ml), arDB, gainPol, ...
    rad2deg(angle(Eth)), rad2deg(angle(Eph)), rad2deg(angle(Erc)), rad2deg(angle(Elc)), eirp, ...
    10.^((eirp - 10*log10(4*pi*param.Rm^2))/10), sqrt(30 * 10.^(eirp/10))/param.Rm, ...
    'VariableNames', {'Theta','Phi','E_Total_dB','E_TH_dB','E_PH_dB','E_RCP_dB','E_LCP_dB', ...
    'AR_dB','Gain_PolCorrected_dB','E_TH_Phase','E_PH_Phase','E_RCP_Phase','E_LCP_Phase', ...
    'EIRP_dBW','PFD_Wm2','E_RMS_Vm'});
out.Properties.UserData = ud;
end
function [plf, mode] = polLossFactor(param, info, mt, mp, mr, ml)
%POLLOSSFACTOR Power efficiency between the pattern and the reference receiver.
%   The receiver's axial ratio ρ (dB) maps to a cross-hand amplitude ratio
%   q = (ρ_lin−1)/(ρ_lin+1); q = 0 is a pure co-polarized receiver.
mode = char(param.rxMode);
if strcmp(mode, 'Auto')
    if startsWith(info.pol, 'Circular')
        mode = ternary(info.pairs.Circular(1) == "E_RCP", 'RHCP', 'LHCP');
    else
        mode = ternary(strcmp(info.pol,'Linear (Vertical)'), 'Vertical', 'Horizontal');
    end
end
if strcmp(mode, 'None'), plf = ones(size(mt)); return, end
rho = 10^(abs(param.rxAR)/20);
q   = (rho - 1)/(rho + 1);
switch mode
    case 'RHCP',      co = mr; cx = ml;
    case 'LHCP',      co = ml; cx = mr;
    case 'Vertical',  co = mt; cx = mp;
    otherwise,        co = mp; cx = mt;
end
plf = (co.^2 + q^2 * cx.^2) ./ max((1 + q^2) * (co.^2 + cx.^2), eps);
end
function m = calcMetrics(t, peakInfo, dOmega, AX6, axisIdx, elevation)
%CALCMETRICS Scalar antenna figures of merit for the active view.
m = struct();
if isempty(t) || ~ismember('E_Total_dB', t.Properties.VariableNames), return, end
g = t.E_Total_dB;
if ~isstruct(peakInfo) || ~isfield(peakInfo,'index')
    peakInfo = resolvePeak(g, struct('pct',99.99,'maxExcessDB',6));
end
i = peakInfo.index; pk = g(i);
thP = physTheta(t); phP = t.Phi;

radiated = sum(10.^(g/10) .* dOmega, 'omitnan');
directivity = 10*log10(max(4*pi*10.^(pk/10)/max(radiated, eps), eps));
efficiency = 100 * 10.^((pk - directivity)/10);
if ~isfinite(efficiency) || efficiency <= 0 || efficiency > 100, efficiency = NaN; end
[~, back] = min(cosd(thP).*cosd(thP(i)) + sind(thP).*sind(thP(i)).*cosd(phP - phP(i)));

[eType, eVal] = planeCut(AX6, axisIdx, elevation, true);
[hType, hVal] = planeCut(AX6, axisIdx, elevation, false);
[aE, rE] = cutRows(t, eType, eVal, thP);
[aH, rH] = cutRows(t, hType, hVal, thP);
ar = NaN;
if ismember('AR_dB', t.Properties.VariableNames), ar = t.AR_dB(i); end
m = struct('PeakGain', pk, 'PeakTheta', t.Theta(i), 'PeakPhi', phP(i), ...
    'HPBW_E', calcHPBW(aE, g(rE)), 'HPBW_H', calcHPBW(aH, g(rH)), ...
    'FrontBack', pk - g(back), 'Directivity', directivity, ...
    'Efficiency', efficiency, 'ARatPeak', ar);
end
function [type, value] = planeCut(AX6, axisIdx, elevation, isE)
%PLANECUT E-plane = boresight meridian; H-plane = the orthogonal great circle.
if isE, type = 'Theta'; value = AX6.phi(axisIdx);
elseif AX6.theta(axisIdx) == 90, type = 'Phi';   value = 90*~elevation;
else,   type = 'Theta'; value = mod(AX6.phi(axisIdx) + 90, 360);
end
end
function [bw, lo, hi] = calcHPBW(ang, gain, pk, pkAng)
%CALCHPBW Interpolated −3 dB beamwidth around the (wrap-aware) peak.
[bw, lo, hi] = deal(NaN);
ok = isfinite(ang) & isfinite(gain);
ang = ang(ok); gain = gain(ok);
if numel(gain) < 3, return, end
if nargin < 3 || isempty(pk) || ~isfinite(pk), [pk, k] = max(gain); pkAng = ang(k); end
rel = gain - pk;
d = mod(ang - pkAng + 180, 360) - 180;
[d, o] = sort(d); rel = rel(o);
c = find(abs(d) == min(abs(d)), 1);
half = -3;
lIdx = find(d < 0 & rel < half, 1, 'last');
rIdx = find(d > 0 & rel < half, 1, 'first');
if isempty(lIdx) || isempty(rIdx) || lIdx+1 > numel(rel) || rIdx-1 < 1, return, end
cross = @(i, j) d(i) + (d(j)-d(i))*(half-rel(i))/(rel(j)-rel(i));
if rel(lIdx+1) == rel(lIdx) || rel(rIdx) == rel(rIdx-1) || c < 1, return, end
lo = cross(lIdx, lIdx+1); hi = cross(rIdx-1, rIdx);
bw = hi - lo;
lo = pkAng + lo; hi = pkAng + hi;
end
function cov = coverageCCDF(gain, mask, thresholds, dOmega)
%COVERAGECCDF  Coverage(T) = 100 · Σ Ωᵢ·I(Gᵢ>T) / Σ Ωᵢ  over the region.
g = double(gain(:)); mask = logical(mask(:)); w = double(dOmega(:));
thresholds = double(thresholds(:));
ok = mask & isfinite(g) & isfinite(w) & w >= 0;
gr = g(ok); wr = w(ok); tot = sum(wr);
cov = zeros(size(thresholds));
if isempty(gr) || tot <= 0, return, end
cov = 100 * (wr.' * (gr > thresholds.')).' / tot;
end
% --------------------------------------------------------- cut geometry
function [ang, rows, fixed, sym, snapped] = cutRows(t, type, requested, thPhys)
%CUTROWS Snap to the nearest available cut and return an ordered 0…360° ring.
if nargin < 4, thPhys = physTheta(t); end
if strcmp(type, 'Phi')
    vals = unique(t.Theta);
    [dist, k] = min(abs(vals - requested));
    fixed = vals(k);
    rows = find(abs(t.Theta - fixed) < 1e-9);
    [ang, o] = sort(t.Phi(rows)); rows = rows(o);
    sym = 'θ';
else
    vals = unique(t.Phi);
    [dist, k] = min(abs(vals - requested));
    fixed = vals(k);
    opp = mod(fixed + 180, 360);
    if any(t.Phi < 0) && opp > 180, opp = opp - 360; end
    primary  = find(abs(t.Phi - fixed) < 1e-9);
    opposite = find(abs(t.Phi - opp) < 1e-9 & abs(thPhys) > 1e-9);
    [~, o1] = sort(thPhys(primary));
    [~, o2] = sort(thPhys(opposite), 'descend');
    primary = primary(o1); opposite = opposite(o2);
    rows = [primary; opposite];
    ang  = [thPhys(primary); 360 - thPhys(opposite)];
    sym  = 'φ';
end
snapped = dist > 0;
end
function [ang, data, gm] = closeSeam(ang, data, gm, signedPhi)
%CLOSESEAM Guarantee a closed φ ring so polar curves never show a gap.
%   Works on row indices, so every parallel geometry field stays in step.
if signedPhi, lo = -180; hi = 180; else, lo = 0; hi = 360; end
n = numel(ang);
li = find(abs(ang - lo) < 1e-9, 1); hj = find(abs(ang - hi) < 1e-9, 1);
if isempty(li) && ~isempty(hj),      idx = [hj 1:n];  ang = [lo; ang];
elseif ~isempty(li) && isempty(hj),  idx = [1:n li];  ang = [ang; hi];
elseif isempty(li) && isempty(hj) && n > 1
    w = (hi - ang(end)) / max(ang(1) - lo + hi - ang(end), eps);
    idx = [n 1:n 1]; ang = [lo; ang; hi];
    data = [(1-w)*data(end,:) + w*data(1,:); data; (1-w)*data(end,:) + w*data(1,:)];
    gm = reindex(gm, idx); gm.phi([1 end]) = [lo; hi];
    return
else
    return
end
data = data(idx, :);
gm = reindex(gm, idx);
if abs(ang(1)   - lo) < 1e-9, gm.phi(1)   = lo; end
if abs(ang(end) - hi) < 1e-9, gm.phi(end) = hi; end
end
function gm = reindex(gm, idx)
for f = ["theta","thetaPolar","phi"], gm.(f) = gm.(f)(idx); end
end
% ------------------------------------------------------ plotting helpers
function [X, Y, Z] = project(kind, phi, thetaPolar, values, lims, lift)
%PROJECT One geometry contract for every renderer, overlay and marker.
%   PHI/THETAPOLAR may be grids (surfaces) or vectors (cuts, single points).
if nargin < 6, lift = 1; end
switch kind
    case 'contour',  X = phi; Y = thetaPolar; Z = lift*ones(size(phi));
    case 'rect3d',   X = phi; Y = thetaPolar; Z = values;
    case 'circular', r = lift*thetaPolar/90; X = r.*cosd(phi); Y = r.*sind(phi); Z = ones(size(phi));
    otherwise
        r = lift*ones(size(phi));
        if strcmp(kind,'pol3d')
            r = lift*(min(max(values, lims(1)), lims(2)) - lims(1))/max(diff(lims), eps);
        end
        st = sind(thetaPolar);
        X = r.*st.*cosd(phi); Y = r.*st.*sind(phi); Z = r.*cosd(thetaPolar);
end
end
function applyBarTicks(cb, lims, step)
if ~isgraphics(cb) || ~isfinite(step) || step <= 0 || diff(lims) <= 0, return, end
ticks = unique([lims(1), ceil(lims(1)/step)*step : step : floor(lims(2)/step)*step, lims(2)], 'stable');
if numel(ticks) >= 2 && numel(ticks) <= 60, cb.Ticks = ticks; end
end
function patternDataTip(s, theta, phi, G, label)
if ~isgraphics(s), return, end
[P, T] = meshgrid(phi, theta);
s.DataTipTemplate.DataTipRows = [ ...
    dataTipTextRow("θ", T, '%.3g°'); dataTipTextRow("φ", P, '%.3g°'); ...
    dataTipTextRow(char(label), G, '%.3g dB')];
end
function drawFisheyeGrid(ax)
%DRAWFISHEYEGRID Rings and spokes for the boresight-centred circular view.
hold(ax, 'on'); t = linspace(0, 2*pi, 181);
for r = 1/3:1/3:2
    plot3(ax, r*cos(t), r*sin(t), ones(size(t)), ':', 'Color',[0.4 0.4 0.4], 'HandleVisibility','off');
end
for a = 0:30:330
    plot3(ax, [0 2]*cosd(a), [0 2]*sind(a), [1 1], ':', 'Color',[0.4 0.4 0.4], 'HandleVisibility','off');
    text(ax, 2.06*cosd(a), 2.06*sind(a), 1, sprintf('%d°', a), 'FontSize',8, 'HorizontalAlignment','center');
end
xlim(ax, [-2.25 2.25]); ylim(ax, [-2.25 2.25]);
end
function polarSpanTicks(pax, signedPhi)
a = 0:30:330;
if signedPhi, a(a > 180) = a(a > 180) - 360; end
pax.ThetaTick = 0:30:330;
pax.ThetaTickLabel = compose('%d°', a);
end
% ------------------------------------------------------------- UAN export
function writeUAN(u, fp)
fid = fopen(fp, 'w');
if fid < 0, error('apat:io:Write','Cannot write %s', fp); end
c = onCleanup(@() fclose(fid));
fprintf(fid, '# APAT UAN export — Theta Phi E_TH_dB E_PH_dB E_TH_deg E_PH_deg\n');
fprintf(fid, '%.4f %.4f %.6f %.6f %.4f %.4f\n', u{:,:}.');
end
%% ======================================================================
%  I/O CORE — one descriptor table drives every columnar far-field format.
%% ======================================================================

function d = columnFormats()
%COLUMNFORMATS Declarative descriptors for fixed-column far-field files.
%   cols  : source column meaning, in file order
%   pair  : how columns 3:6 encode the two orthogonal components
d = struct( ...
 'ext',  {'UAN','FZ','OUT','FFS','FFE','FFD'}, ...
 'name', {'XGTD UAN','XGTD FZ','TICRA/GRASP OUT','CST FFS','FEKO FFE','HFSS FFD'}, ...
 'cols', {{'Theta','Phi','E_TH_dB','E_PH_dB','E_TH_deg','E_PH_deg'}, ...
          {'Theta','Phi','E_TH_dB','E_PH_dB','E_TH_deg','E_PH_deg'}, ...
          {'Theta','Phi','Re_RHCP','Im_RHCP','Re_LHCP','Im_LHCP'}, ...
          {'Phi','Theta','Re_Eth','Im_Eth','Re_Eph','Im_Eph'}, ...
          {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'}, ...
          {'Re_Eth','Im_Eth','Re_Eph','Im_Eph'}}, ...
 'pair', {'linear_magphase','linear_magphase','rcp_lcp_reim','linear_reim','linear_reim','linear_reim'});
end
function [out, generic] = readWithFormat(fp, textFormat)
%READWITHFORMAT Read FP, using TEXTFORMAT only when the extension is generic.
[~, ~, ext] = fileparts(fp);
generic = ismember(lower(ext), {'.csv','.txt','.dat'});
out = readSource(fp, ternary(generic, textFormat, 'gain'));
end
function out = readSource(fp, textFormat)
%READSOURCE Unified entry point: file → {rawTbl, blocks, freqs, userData}.
[~, ~, ext] = fileparts(fp);
ext = upper(erase(ext, '.'));
out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, ...
             'userData', validateSource(struct('source', ext)));

switch true
    case ismember(ext, {'XLSX','XLS'}), out = readExcelMatrix(fp);
    case ismember(ext, {'CSV','TXT','DAT'}), out = readTextTable(fp, string(textFormat));
    case strcmp(ext, 'CUT'), out = readGraspCut(fp);
    otherwise, out = readColumnar(fp, ext);
end
out.userData = validateSource(out.userData);
end
% ------------------------------------------------------- generic text
function out = readTextTable(fp, textFormat)
out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, ...
             'userData', validateSource(struct('source','Generic text')));
opts = detectImportOptions(fp, 'FileType','text', 'Delimiter',{' ','\t',',',';'}, ...
    'ConsecutiveDelimitersRule','join', 'LeadingDelimitersRule','ignore');
opts = setvaropts(setvartype(opts, 'double'), 'TrimNonNumeric', true);
opts.VariableNamingRule = 'preserve';
t = rmmissing(readtable(fp, opts));
n = width(t);
assert(n >= 2 && height(t) > 0, 'apat:io:Columns', 'File needs at least two numeric columns.');
names = string(t.Properties.VariableNames);
headed = ~all(startsWith(names, "Var"));
c1 = t{:,1}; c2 = t{:,2};

% Coverage-result detection precedes any pattern interpretation.
covHeader = contains(lower(names(1)),"threshold") || any(contains(lower(names(2:end)),"coverage"));
if (textFormat == "gain" || n < 6 || covHeader) && all(isfinite(c2)) && ...
        all(c2 >= 0 & c2 <= 100) && issorted(c1, 'strictmonotonic')
    if ~headed
        t.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:n-1))];
    end
    out.rawTbl = t; out.userData.isCoverage = true; return
end

if textFormat == "gain"
    wide = max(c1)-min(c1) > max(c2)-min(c2);          % the wider column spans phi
    t.Properties.VariableNames(1:2) = ternaryMat(wide, {'Phi','Theta'}, {'Theta','Phi'});
    out.rawTbl = movevars(t, 'Theta', 'Before', 1);
    out.blocks = {out.rawTbl};
    out.userData.source = 'Generic gain text';
    out.userData.isGainOnly = true;
    return
end

assert(n >= 6, 'apat:io:EField', 'The selected E-field text format needs six numeric columns.');
[Eth, Eph, layout] = decodePair(t{:,3:6}, char(textFormat));
out.userData.source = sprintf('Generic text (%s, %s)', textFormat, layout);
out.rawTbl = t;
out.blocks = {stdTable(t{:,1}, t{:,2}, Eth, Eph)};
end
function [Eth, Eph, layout] = decodePair(v, mode)
%DECODEPAIR Columns 3:6 → complex (Eθ, Eφ) for every supported convention.
layout = 'reim';
if endsWith(mode, 'magphase')
    isPhase = max(abs(v), [], 1, 'omitnan') > 100;
    if isPhase(2) && ~isPhase(3), mc = [1 3]; pc = [2 4]; layout = 'interleaved';
    else,                          mc = [1 2]; pc = [3 4]; layout = 'grouped';
    end
    a = 10.^(v(:,mc(1))/20) .* exp(1i*deg2rad(v(:,pc(1))));
    b = 10.^(v(:,mc(2))/20) .* exp(1i*deg2rad(v(:,pc(2))));
else
    a = complex(v(:,1), v(:,2)); b = complex(v(:,3), v(:,4));
end
if startsWith(mode, 'linear')
    Eth = a; Eph = b;
else
    if startsWith(mode, 'rcp'), Erc = a; Elc = b; else, Elc = a; Erc = b; end
    Eth = (Erc + Elc)/sqrt(2);
    Eph = (Erc - Elc)/(1i*sqrt(2));
end
end
function t = stdTable(theta, phi, Eth, Eph)
t = table(theta(:), phi(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), ...
    'VariableNames', {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'});
end
% ------------------------------------------------- columnar far-field files
function out = readColumnar(fp, ext)
d = columnFormats();
k = find(strcmp({d.ext}, ext), 1);
assert(~isempty(k), 'apat:io:Unsupported', 'Unsupported format: %s', ext);
d = d(k);
out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, ...
             'userData', validateSource(struct('source', d.name)));
[nHdr, ffd] = headerScan(fp);
opts = detectImportOptions(fp, 'FileType','text', 'NumHeaderLines', nHdr, 'Delimiter',{' ','\t',',',';'}, ...
    'ConsecutiveDelimitersRule','join', 'LeadingDelimitersRule','ignore');
M = readmatrix(fp, setvartype(opts, opts.VariableNames, 'double'));
M = M(~all(isnan(M), 2), :);

if ~strcmp(ext, 'FFD')
    M = M(:, 1:min(size(M,2), 6));
    assert(size(M,2) >= 6, 'apat:io:Columns', '%s needs six numeric columns.', d.name);
    out.rawTbl = array2table(M, 'VariableNames', d.cols);
    [Eth, Eph] = decodePair(M(:,3:6), d.pair);
    out.blocks = {stdTable(M(:, strcmp(d.cols,'Theta')), M(:, strcmp(d.cols,'Phi')), Eth, Eph)};
    return
end

assert(ffd.isFFD, 'apat:io:FFD', 'FFD header (theta/phi ranges) not found.');
th = linspace(ffd.theta.start, ffd.theta.stop, ffd.theta.count).';
ph = linspace(ffd.phi.start,   ffd.phi.stop,   ffd.phi.count).';
theta = repelem(th, numel(ph)); phi = repmat(ph, numel(th), 1);
sep = isnan(M(:,1)); fseps = M(sep, 2);
freqs = [ffd.freq(:); fseps(~isnan(fseps))].';
rows = M(~sep, 1:4); per = numel(th)*numel(ph);
assert(mod(size(rows,1), per) == 0, 'apat:io:FFD', 'FFD row count does not match the θ/φ grid.');
nb = size(rows,1)/per;
out.userData.isMultiBlock = nb > 1;
out.userData.hasFrequency = ~isempty(freqs) && any(isfinite(freqs));
out.userData.isDep = out.userData.isMultiBlock || out.userData.hasFrequency;
freqs(end+1:nb) = NaN; freqs = freqs(1:nb);
out.blocks = cellfun(@(b) stdTable(theta, phi, complex(b(:,1),b(:,2)), complex(b(:,3),b(:,4))), ...
    mat2cell(rows, repmat(per, nb, 1), 4), 'UniformOutput', false);
out.freqs = freqs;
out.rawTbl = out.blocks{1};
end
function [nHdr, ffd] = headerScan(fp)
%HEADERSCAN Count leading non-data lines and parse an optional HFSS FFD header.
fid = fopen(fp, 'r');
if fid < 0, error('apat:io:Open', 'Cannot open file: %s', fp); end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
nHdr = 0; ffd = struct('theta',[], 'phi',[], 'freq',[], 'isFFD', false);
triples = zeros(0,3);
while size(triples,1) < 2
    line = fgetl(fid);
    if ~ischar(line), break, end
    nHdr = nHdr + 1;
    v = sscanf(strtrim(line), '%f').';
    if numel(v) == 3, triples(end+1,:) = v; %#ok<AGROW>
    elseif ~isempty(strtrim(line)) && isempty(triples), break
    end
end
if size(triples,1) == 2
    fields = {'start','stop','count'};
    ffd.theta = cell2struct(num2cell(triples(1,:)).', fields);
    ffd.phi   = cell2struct(num2cell(triples(2,:)).', fields);
    ffd.theta.count = round(ffd.theta.count); ffd.phi.count = round(ffd.phi.count);
    line = fgetl(fid);
    while ischar(line) && isempty(strtrim(line)), nHdr = nHdr + 1; line = fgetl(fid); end
    if ischar(line)
        nHdr = nHdr + 1;
        tok = regexp(strtrim(line), '^frequencies?\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if isempty(tok), nHdr = nHdr - 1;                 % it is really a data row
        else
            f = sscanf(tok{1}, '%f').';
            if ~isscalar(f), ffd.freq = f(:); end          % a lone count is metadata only
        end
    end
    ffd.isFFD = all(isfinite(triples(:))) && ffd.theta.count >= 1 && ffd.phi.count >= 1;
end
if ~ffd.isFFD                                              % generic: first ≥4-number row
    frewind(fid); nHdr = 0;
    num = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?';
    pat = ['^\s*' num '(?:[\s,;]+' num '){3,}\s*$'];
    while true
        line = fgetl(fid);
        if ~ischar(line) || ~isempty(regexp(line, pat, 'once')), break, end
        nHdr = nHdr + 1;
    end
end
end
% ------------------------------------------------------ TICRA/GRASP .cut
function out = readGraspCut(fp)
%READGRASPCUT TICRA/GRASP .cut: repeated [title; 7-parameter line; data] blocks.
out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, ...
             'userData', validateSource(struct('source','TICRA/GRASP CUT')));
L = readlines(fp); L(strlength(strtrim(L)) == 0) = [];
[thC, phC, dC] = deal({});
icomp = 1; icut = 1; i = 1;
while i < numel(L)
    q = sscanf(L(i+1), '%f');
    assert(numel(q) >= 7, 'apat:io:Cut', 'Malformed .cut parameter line at %d.', i+1);
    n = q(3); icomp = q(5); icut = q(6);
    blk = reshape(sscanf(strjoin(L(i+2 : i+1+n), ' '), '%f'), 2*q(7), []).';
    thC{end+1,1} = q(1) + (0:n-1).'*q(2);  phC{end+1,1} = repmat(q(4), n, 1);  dC{end+1,1} = blk(:,1:4); %#ok<AGROW>
    i = i + 2 + n;
end
theta = vertcat(thC{:}); phi = vertcat(phC{:}); V = vertcat(dC{:});
if icut == 2, [theta, phi] = deal(phi, theta); end       % ICUT=2 sweeps phi
neg = theta < 0;
phi(neg) = phi(neg) + 180; theta(neg) = -theta(neg);
if isscalar(unique(phi))                                  % single cut → body of revolution
    reps = (0:10:350).'; m = numel(theta);
    theta = repmat(theta, numel(reps), 1); phi = repelem(reps, m); V = repmat(V, numel(reps), 1);
end
circular = icomp == 2;
names = ternaryMat(circular, {'Theta','Phi','Re_RHCP','Im_RHCP','Re_LHCP','Im_LHCP'}, ...
                             {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'});
[Eth, Eph] = decodePair(V, ternary(circular, 'rcp_lcp_reim', 'linear_reim'));
out.rawTbl = array2table([theta phi V], 'VariableNames', names);
out.blocks = {stdTable(theta, phi, Eth, Eph)};
end
% -------------------------------------------------- Excel matrix workbooks
function out = readExcelMatrix(fp)
%READEXCELMATRIX Self-describing matrix workbooks (Eθ/Eφ and/or RHCP/LHCP).
sheets = string(sheetnames(fp));
circ = ["RHCP_Gain_dBi","RHCP_Phase_degrees","LHCP_Gain_dBi","LHCP_Phase_degrees"];
lin  = ["Etheta_Gain_dBi","Etheta_Phase_degrees","Ephi_Gain_dBi","Ephi_Phase_degrees"];
hasC = all(ismember(lower(circ), lower(sheets)));
hasL = all(ismember(lower(lin),  lower(sheets)));
assert(hasL || hasC, 'apat:io:Excel', ['Unsupported workbook: sheet 1 is the summary and the ' ...
    'remaining sheets must be the fixed Eθ/Eφ and/or RHCP/LHCP component matrices.']);
req  = [lin(repmat(hasL,1,4)) circ(repmat(hasC,1,4))];
fmt  = sprintf('Excel Matrix (%s)', strjoin(["Eθ/Eφ"; "RHCP/LHCP"](logical([hasL hasC])), ' + '));

M = struct(); thRef = []; phRef = [];
for k = 1:numel(req)
    [th, ph, D] = readMatrixSheet(fp, sheets(find(strcmpi(sheets, req(k)), 1)));
    if isempty(thRef), thRef = th; phRef = ph; end
    assert(isequal(size(th),size(thRef)) && isequal(size(ph),size(phRef)) && ...
        max(abs(th-thRef)) < 1e-9 && max(abs(ph-phRef)) < 1e-9, ...
        'apat:io:ExcelGrid', 'All component sheets must share one θ/φ grid.');
    M.(matlab.lang.makeValidName(req(k))) = D;
end
cplx = @(a, b) 10.^(M.(a)/20) .* exp(1i*deg2rad(M.(b)));
if hasL
    Eth = cplx('Etheta_Gain_dBi','Etheta_Phase_degrees');
    Eph = cplx('Ephi_Gain_dBi','Ephi_Phase_degrees');
    basis = ternary(hasC, "theta-phi + RHCP/LHCP", "theta-phi");
else
    Erc = cplx('RHCP_Gain_dBi','RHCP_Phase_degrees');
    Elc = cplx('LHCP_Gain_dBi','LHCP_Phase_degrees');
    Eth = (Erc + Elc)/sqrt(2); Eph = (Erc - Elc)/(1i*sqrt(2));
    basis = "RHCP/LHCP";
end

TG = repmat(thRef(:), 1, numel(phRef));  PG = repmat(phRef(:).', numel(thRef), 1);
block = stdTable(TG(:), PG(:), Eth(:), Eph(:));
raw = block;
for k = 1:numel(req)
    key = matlab.lang.makeValidName(req(k)); raw.(key) = M.(key)(:);
end
md = readSummarySheet(fp, sheets(1));
md.source = char(fmt); md.file = fp; md.summarySheet = char(sheets(1));
md.quantityType = "complex-electric-field"; md.absoluteCalibration = true;
md.polarizationBasis = basis; md.componentSheets = cellstr(req);
md.hasFrequency = isfield(md,'frequencyMHz') && isfinite(md.frequencyMHz);
md.matrixGrid = struct('thetaDeg',thRef(:),'phiDeg',phRef(:), ...
    'thetaStepDeg',gridStep(thRef),'phiStepDeg',gridStep(phRef));
out = struct('rawTbl', raw, 'blocks', {{block}}, 'freqs', NaN, 'userData', validateSource(md));
if md.hasFrequency, out.freqs = md.frequencyMHz * 1e6; end
end
function [theta, phi, D] = readMatrixSheet(fp, sheet)
%READMATRIXSHEET C3-origin matrix: row 2 = φ axis, column 2 = θ axis.
%   readcell (not readmatrix) preserves the template's worksheet coordinates.
C = readcell(fp, 'Sheet', char(sheet));
assert(size(C,1) >= 3 && size(C,2) >= 3, 'apat:io:ExcelSheet', 'Sheet "%s" is too small.', sheet);
phi   = cellfun(@toDouble, C(2, 3:end)).';
theta = cellfun(@toDouble, C(3:end, 2));
D     = cellfun(@toDouble, C(3:end, 3:end));
okP = isfinite(phi); okT = isfinite(theta);
phi = phi(okP); theta = theta(okT); D = D(okT, okP);
assert(~isempty(theta) && ~isempty(phi), 'apat:io:ExcelSheet', 'Sheet "%s" has no numeric grid.', sheet);
assert(min(theta) >= -1e-9 && max(theta) <= 180+1e-9 && min(phi) >= -1e-9 && max(phi) < 360+1e-9, ...
    'apat:io:ExcelAxis', 'Sheet "%s" leaves the θ∈[0,180], φ∈[0,360) domain.', sheet);
end
function md = readSummarySheet(fp, sheet)
%READSUMMARYSHEET Generic "Label:" → value harvest over columns A:H.
%   No hard-coded label list, so template revisions add metadata for free.
md = struct();
try, C = readcell(fp, 'Sheet', char(sheet), 'Range', 'A1:H80'); catch, return, end
for r = 1:size(C,1)
    for c = 1:min(size(C,2)-1, 7)
        lab = C{r,c};
        if ~(ischar(lab) || isstring(lab)), continue, end
        lab = strtrim(string(lab));
        if strlength(lab) == 0 || ~endsWith(lab, ":"), continue, end
        val = firstValue(C(r, c+1:end));
        key = matlab.lang.makeValidName(lower(regexprep(char(lab), '[^a-zA-Z0-9]+', '_')));
        if ~isempty(val) && ~isfield(md, key), md.(key) = val; end
    end
end
fn = fieldnames(md);
hit = fn(contains(fn,'freq') & contains(fn,'mhz'));
if ~isempty(hit), md.frequencyMHz = toDouble(md.(hit{1})); end
end
function v = firstValue(cells)
v = [];
for k = 1:numel(cells)
    c = cells{k};
    if isnumeric(c) && isscalar(c) && isfinite(c), v = c; return, end
    if (ischar(c) || isstring(c)) && strlength(strtrim(string(c))) > 0
        v = char(strtrim(string(c))); return
    end
end
end
function d = toDouble(v)
if isnumeric(v) && isscalar(v), d = double(v);
elseif ischar(v) || isstring(v)
    n = str2double(v); d = n;
else, d = NaN;
end
if isempty(d), d = NaN; end
end