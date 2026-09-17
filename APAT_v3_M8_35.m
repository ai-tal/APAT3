classdef APAT_v3_M8_35 < handle %AST %1571-lines
    % APAT M8.0-rc1: a grid-native antenna-pattern workbench.
    % Base MATLAB R2023b+. Run APAT_v3_M8.selfTest before production use.
    % This is a redesigned candidate, not a drop-in M7 GUI replacement.
    properties (SetAccess = private)
        UIFigure
        Source = struct()
        Pattern = struct()
        Metrics = struct()
        Revision = uint64(0)
    end
    properties (Access = private)
        UI = struct()
        Graphics = struct()
        Cache = struct()
        Jobs = struct('Name', {}, 'Threshold', {}, 'Coverage', {}, ...
            'Distribution', {}, 'Loss', {}, 'Region', {})
        Busy = false
        Closing = false
    end
    properties (Constant)
        Version = '3.0-M8.0-rc1'
        Baseline = 'APAT_v3_M7_110_5.m'
    end
    methods
        function app = APAT_v3_M8_35(path)
            app.createUI();
            if nargin > 0
                app.run('loadPath', path);
            else
                app.run('demo');
            end
        end

        function delete(app)
            if app.Closing
                return
            end
            app.Closing = true;
            if isgraphics(app.UIFigure)
                app.UIFigure.CloseRequestFcn = [];
                delete(app.UIFigure);
            end
        end
    end
    methods (Static)
        function source = read(path, options)
            if nargin < 2
                options = struct();
            end
            source = m8Read(char(path), m8Options(options));
        end

        function result = analyze(input, options)
            if nargin < 2
                options = struct();
            end
            options = m8Options(options);
            if istable(input)
                source = m8Source(input, 'MATLAB table', options);
            else
                source = m8Read(char(input), options);
            end
            pattern = m8Canonical(source.Blocks{1}, source.Metadata{1});
            if options.StepDeg > 0
                pattern = m8Resample(pattern, options.StepDeg, options.Interpolation);
            end
            result = struct('Pattern', pattern, 'Metrics', m8Metrics(pattern), ...
                'Parameters', options);
        end

        function values = column(pattern, name, options)
            if nargin < 3
                options = struct();
            end
            values = m8Column(pattern, char(name), m8Options(options));
        end

        function pattern = resample(pattern, stepDeg, method)
            if nargin < 3
                method = 'cartesian';
            end
            pattern = m8Resample(pattern, stepDeg, method);
        end

        function [coverage, distribution] = coverage(gain, weights, thresholds, mask)
            if nargin < 4
                mask = true(size(gain));
            end
            distribution = m8Distribution(gain, weights, mask);
            coverage = m8Evaluate(distribution, thresholds);
        end

        function result = selfTest()
            tests = {@m8TestWeights, @m8TestPartial, @m8TestPrecision, ...
                @m8TestDuplicates, @m8TestCoverage, @m8TestRandomCoverage, ...
                @m8TestEmpty, @m8TestZeroPower, @m8TestLoss, ...
                @m8TestCircular, @m8TestPLF, @m8TestResample, ...
                @m8TestHPBW, @m8TestIsotropic, @m8TestCSV, @m8TestFFD, ...
                @m8TestPeriodicTarget, @m8TestRawPeak, @m8TestAmbiguousPhase};
            names = string(cellfun(@func2str, tests, 'UniformOutput', false)).';
            passed = false(numel(tests), 1);
            detail = strings(numel(tests), 1);
            for k = 1:numel(tests)
                try
                    tests{k}();
                    passed(k) = true;
                    detail(k) = "Passed";
                catch exception
                    detail(k) = string(exception.identifier) + ": " + exception.message;
                end
            end
            result = table(names, passed, detail, ...
                'VariableNames', {'Test', 'Passed', 'Detail'});
            if nargout == 0
                disp(result);
                assert(all(passed), 'APAT:TestFailure', 'One or more M8 tests failed.');
            end
        end
    end
    methods (Access = private)
        function createUI(app)
            app.UIFigure = uifigure('Name', ['APAT ' app.Version], ...
                'Position', [80 80 1320 820], 'Color', [0.97 0.97 0.99], ...
                'CloseRequestFcn', @(~, ~) delete(app));
            root = uigridlayout(app.UIFigure, [3 2]);
            root.RowHeight = {44, '1x', 25};
            root.ColumnWidth = {235, '1x'};
            tools = uigridlayout(root, [1 7]);
            tools.Layout.Column = [1 2];
            tools.ColumnWidth = {'1x', 90, 90, 105, 105, 100, 85};
            uilabel(tools, 'Text', 'APAT / M8 WORKBENCH', 'FontWeight', 'bold', 'FontSize', 18);
            actions = {'Load', 'Demo', 'Export CSV', 'Export MAT', 'Export plot', 'Self-test'};
            commands = {'load', 'demo', 'exportCSV', 'exportMAT', 'exportPlot', 'test'};
            for k = 1:numel(actions)
                command = commands{k};
                uibutton(tools, 'Text', actions{k}, 'ButtonPushedFcn', ...
                    @(~, ~) app.run(command));
            end
            settings = uigridlayout(root, [24 2]);
            settings.Layout.Row = 2;
            settings.ColumnWidth = {'1x', '1x'};
            settings.RowHeight = repmat({25}, 1, 24);
            settings.Scrollable = 'on';
            app.control(settings, 1, 'Text format', 'Format', 'drop', ...
                {'named', 'gain', 'complex', 'magnitude-phase'}, 'view');
            app.control(settings, 2, 'Theta coordinate', 'ThetaConvention', 'drop', ...
                {'polar', 'elevation'}, 'view');
            app.control(settings, 3, 'FFD ordering', 'FFDOrder', 'drop', ...
                {'theta-fast', 'phi-fast'}, 'view');
            uilabel(settings, 'Text', 'Calibrated gain');
            app.UI.AbsoluteGain = uicheckbox(settings, 'Text', 'dBi', 'Value', false);
            app.control(settings, 5, 'Frequency', 'Block', 'drop', {'1'}, 'rebuild');
            app.control(settings, 6, 'Angular grid', 'Step', 'drop', {'Native', '1 degree'}, 'rebuild');
            app.control(settings, 7, 'Interpolation', 'Interpolation', 'drop', ...
                {'cartesian', 'power-phase'}, 'rebuild');
            app.control(settings, 8, 'Component', 'Component', 'drop', {'E_Total_dB'}, 'view');
            app.control(settings, 9, 'Full pattern', 'View', 'drop', ...
                {'Contour', 'Circular', '3D sphere', '3D gain', '3D rectangular'}, 'view');
            app.control(settings, 10, 'Theta display', 'Elevation', 'drop', {'Polar', 'Elevation'}, 'view');
            app.control(settings, 11, 'Phi display', 'SignedPhi', 'drop', {'0 to 360', '-180 to 180'}, 'view');
            app.control(settings, 12, 'Gain offset (dB)', 'LossDB', 'number', [-200 100 0], 'view');
            app.control(settings, 13, 'Receive state', 'RxMode', 'drop', ...
                {'Auto', 'RHCP', 'LHCP', 'Theta', 'Phi'}, 'view');
            app.control(settings, 14, 'Receive AR (dB)', 'RxARDB', 'number', [0 100 0], 'view');
            app.control(settings, 15, 'Receive tilt (deg)', 'RxTiltDeg', 'number', [-180 180 0], 'view');
            app.control(settings, 16, 'Tx power (dBW)', 'PowerDBW', 'number', [-200 100 0], 'view');
            app.control(settings, 17, 'Distance (m)', 'DistanceM', 'number', [1e-6 1e12 1], 'view');
            app.control(settings, 18, 'Color minimum', 'ColorMin', 'number', [-400 300 -40], 'view');
            app.control(settings, 19, 'Color maximum', 'ColorMax', 'number', [-400 300 10], 'view');
            app.control(settings, 20, 'Cut sweep', 'CutType', 'drop', {'Theta', 'Phi'}, 'view');
            app.control(settings, 21, 'Fixed angle (deg)', 'CutAngle', 'number', [-360 360 0], 'view');
            app.control(settings, 22, 'Cut display', 'CutView', 'drop', {'Rectangular', 'Polar'}, 'view');
            app.UI.Reset = uibutton(settings, 'Text', 'Reset parameters', ...
                'ButtonPushedFcn', @(~, ~) app.run('reset'));
            app.UI.Reset.Layout.Column = [1 2];
            app.UI.Reset.Layout.Row = 23;
            note = uilabel(settings, 'Text', 'Import options apply on Load.', 'FontSize', 10);
            note.Layout.Column = [1 2];
            note.Layout.Row = 24;
            app.UI.Tabs = uitabgroup(root, 'SelectionChangedFcn', @(~, ~) app.run('view'));
            app.UI.Tabs.Layout.Row = 2;
            app.UI.Tabs.Layout.Column = 2;
            patternTab = uitab(app.UI.Tabs, 'Title', 'Pattern');
            displayGrid = uigridlayout(patternTab, [2 2]);
            displayGrid.ColumnWidth = {'2x', '1x'};
            displayGrid.RowHeight = {'1x', '1x'};
            app.UI.Axes = uiaxes(displayGrid);
            app.UI.Axes.Layout.Row = [1 2];
            app.UI.Axes.Layout.Column = 1;
            app.Graphics.Colorbar = colorbar(app.UI.Axes);
            cutPanel = uipanel(displayGrid, 'BorderType', 'none');
            cutPanel.Layout.Row = 1;
            cutPanel.Layout.Column = 2;
            app.UI.CutAxes = uiaxes(cutPanel, 'Units', 'normalized', ...
                'Position', [0.07 0.08 0.88 0.86]);
            app.UI.PolarAxes = polaraxes(cutPanel, 'Units', 'normalized', ...
                'Position', [0.15 0.15 0.72 0.7], 'Visible', 'off');
            app.UI.Metrics = uitable(displayGrid, 'ColumnName', {'Metric', 'Value'});
            app.UI.Metrics.Layout.Row = 2;
            app.UI.Metrics.Layout.Column = 2;
            app.createCoverageTab();
            dataTab = uitab(app.UI.Tabs, 'Title', 'Data');
            dataGrid = uigridlayout(dataTab, [3 1]);
            dataGrid.RowHeight = {28, 22, '1x'};
            app.UI.DataKind = uidropdown(dataGrid, 'Items', {'Results', 'Input', 'Metadata'}, ...
                'ValueChangedFcn', @(~, ~) app.run('view'));
            app.UI.DataNote = uilabel(dataGrid, 'Text', '');
            app.UI.DataTable = uitable(dataGrid);
            app.UI.Status = uilabel(root, 'Text', 'M8 release candidate. MATLAB validation required.', ...
                'Interpreter', 'none', 'FontSize', 11);
            app.UI.Status.Layout.Row = 3;
            app.UI.Status.Layout.Column = [1 2];
        end

        function control(app, parent, row, label, key, kind, data, action)
            text = uilabel(parent, 'Text', label, 'FontSize', 11);
            text.Layout.Row = row;
            text.Layout.Column = 1;
            callback = @(~, ~) app.run(action);
            if strcmp(kind, 'drop')
                handle = uidropdown(parent, 'Items', data, 'ValueChangedFcn', callback);
            else
                handle = uispinner(parent, 'Limits', data(1:2), 'Value', data(3), ...
                    'ValueChangedFcn', callback);
            end
            handle.Layout.Row = row;
            handle.Layout.Column = 2;
            app.UI.(key) = handle;
        end

        function createCoverageTab(app)
            tab = uitab(app.UI.Tabs, 'Title', 'Coverage');
            grid = uigridlayout(tab, [2 2]);
            grid.RowHeight = {210, '1x'};
            grid.ColumnWidth = {'1x', 300};
            controls = uigridlayout(grid, [6 4]);
            controls.Layout.Column = [1 2];
            controls.ColumnWidth = {130, '1x', 130, '1x'};
            left = uigridlayout(controls, [6 2]);
            left.Layout.Column = [1 2];
            left.Layout.Row = [1 6];
            right = uigridlayout(controls, [6 2]);
            right.Layout.Column = [3 4];
            right.Layout.Row = [1 6];
            app.control(left, 1, 'Region', 'Region', 'drop', {'Sampled sphere', 'Cone'}, 'view');
            app.control(left, 2, 'Cone theta (deg)', 'ConeTheta', 'number', [0 180 0], 'view');
            app.control(left, 3, 'Cone phi (deg)', 'ConePhi', 'number', [-360 360 0], 'view');
            app.control(left, 4, 'Half-angle (deg)', 'ConeAngle', 'number', [0 180 45], 'view');
            app.control(left, 5, 'Query threshold', 'Query', 'number', [-400 300 0], 'query');
            app.UI.QueryResult = uilabel(left, 'Text', 'Compute a distribution first.');
            app.UI.QueryResult.Layout.Row = 6;
            app.UI.QueryResult.Layout.Column = [1 2];
            app.control(right, 1, 'Minimum (dB)', 'ThresholdMin', 'number', [-400 300 -40], 'view');
            app.control(right, 2, 'Maximum (dB)', 'ThresholdMax', 'number', [-400 300 20], 'view');
            app.control(right, 3, 'Step (dB)', 'ThresholdStep', 'number', [0.01 100 1], 'view');
            app.UI.Compute = uibutton(right, 'Text', 'Compute coverage', ...
                'ButtonPushedFcn', @(~, ~) app.run('coverage'));
            app.UI.Compute.Layout.Column = [1 2];
            app.UI.Compute.Layout.Row = 4;
            app.UI.Job = uidropdown(right, 'Items', {'No jobs'}, ...
                'ValueChangedFcn', @(~, ~) app.run('query'));
            app.UI.Job.Layout.Row = 5;
            app.UI.Job.Layout.Column = [1 2];
            uibutton(right, 'Text', 'Export curve', 'ButtonPushedFcn', @(~, ~) app.run('exportCoverage'));
            uibutton(right, 'Text', 'Clear jobs', 'ButtonPushedFcn', @(~, ~) app.run('clearCoverage'));
            app.UI.CoverageAxes = uiaxes(grid);
            app.UI.CoverageAxes.Layout.Row = 2;
            app.UI.CoverageAxes.Layout.Column = 1;
            app.UI.CoverageTable = uitable(grid);
            app.UI.CoverageTable.Layout.Row = 2;
            app.UI.CoverageTable.Layout.Column = 2;
        end

        function cfg = config(app)
            cfg = m8Options(struct());
            fields = {'Format', 'ThetaConvention', 'FFDOrder', 'AbsoluteGain', ...
                'Interpolation', 'LossDB', 'RxMode', 'RxARDB', 'RxTiltDeg', ...
                'PowerDBW', 'DistanceM'};
            for k = 1:numel(fields)
                cfg.(fields{k}) = app.UI.(fields{k}).Value;
            end
            cfg.StepDeg = double(strcmp(app.UI.Step.Value, '1 degree'));
        end

        function run(app, action, varargin)
            if app.Busy || app.Closing
                return
            end
            app.Busy = true;
            cleanup = onCleanup(@() app.release()); %#ok<NASGU>
            try
                cfg = app.config();
                switch action
                    case 'load'
                        [file, folder] = uigetfile({'*.csv;*.txt;*.dat;*.mat;*.xlsx;*.xls;*.ffd;*.ffe', ...
                            'Supported antenna patterns'}, 'Load antenna pattern');
                        if isequal(file, 0)
                            return
                        end
                        candidate = m8Read(fullfile(folder, file), cfg);
                        app.install(candidate, 1, cfg);
                    case 'loadPath'
                        app.install(m8Read(char(varargin{1}), cfg), 1, cfg);
                    case 'demo'
                        app.install(m8DemoSource(), 1, cfg);
                    case 'rebuild'
                        if ~isfield(app.Source, 'Blocks')
                            return
                        end
                        app.install(app.Source, str2double(app.UI.Block.Value), cfg);
                    case 'reset'
                        defaults = m8Options(struct());
                        names = {'LossDB', 'RxMode', 'RxARDB', 'RxTiltDeg', 'PowerDBW', 'DistanceM'};
                        for k = 1:numel(names)
                            app.UI.(names{k}).Value = defaults.(names{k});
                        end
                    case 'coverage'
                        app.computeCoverage();
                    case 'clearCoverage'
                        app.Jobs = app.Jobs([]);
                        app.UI.Job.Items = {'No jobs'};
                        app.UI.QueryResult.Text = 'Compute a distribution first.';
                        app.UI.CoverageTable.Data = table();
                        if isfield(app.Graphics, 'Coverage') && isgraphics(app.Graphics.Coverage)
                            set(app.Graphics.Coverage, 'XData', [], 'YData', []);
                        end
                    case 'test'
                        result = APAT_v3_M8_35.selfTest();
                        disp(result);
                        uialert(app.UIFigure, sprintf('%d of %d self-tests passed. See Command Window.', ...
                            nnz(result.Passed), height(result)), 'M8 self-test', 'Icon', 'info');
                    otherwise
                        if startsWith(action, 'export')
                            app.export(action);
                        end
                end
                if isfield(app.Pattern, 'Theta')
                    app.render();
                end
            catch exception
                if ~app.Closing && isgraphics(app.UIFigure)
                    app.UI.Status.Text = ['Error: ' exception.message];
                    uialert(app.UIFigure, exception.message, 'APAT M8', 'Interpreter', 'none');
                end
            end
        end

        function release(app)
            if isvalid(app)
                app.Busy = false;
            end
        end

        function install(app, source, block, cfg)
            validateattributes(block, {'double'}, {'scalar', 'integer', '>=', 1, '<=', numel(source.Blocks)});
            candidate = m8Canonical(source.Blocks{block}, source.Metadata{block});
            if cfg.StepDeg > 0
                candidate = m8Resample(candidate, cfg.StepDeg, cfg.Interpolation);
            end
            metrics = m8Metrics(candidate);
            % Commit only after parsing, topology validation and math succeed.
            app.Source = source;
            app.Pattern = candidate;
            app.Metrics = metrics;
            app.Revision = app.Revision + 1;
            app.Cache = struct();
            app.UI.Block.Items = cellstr(string(1:numel(source.Blocks)));
            app.UI.Block.Value = char(string(block));
            app.UI.Block.Tooltip = char(strjoin(compose('Block %d: %.6g Hz', ...
                (1:numel(source.Blocks)).', source.FrequenciesHz(:)), newline));
            definitions = m8Definitions(candidate);
            previous = app.UI.Component.Value;
            visible = definitions(ismember({definitions.Kind}, {'level', 'ratio'}));
            app.UI.Component.Items = {visible.Name};
            if ismember(previous, app.UI.Component.Items)
                app.UI.Component.Value = previous;
            else
                app.UI.Component.Value = 'E_Total_dB';
            end
        end

        function values = columnCached(app, name, cfg)
            base = cfg;
            base.LossDB = 0;
            key = 'source';
            if ismember(name, {'PLF_dB', 'Gain_PolCorrected_dB'})
                key = sprintf('%s|%.17g|%.17g', cfg.RxMode, cfg.RxARDB, cfg.RxTiltDeg);
            elseif strcmp(name, 'EIRP_dBW')
                key = sprintf('%.17g', cfg.PowerDBW);
            elseif ismember(name, {'PFD_Wm2', 'E_RMS_Vm'})
                key = sprintf('%.17g|%.17g', cfg.PowerDBW, cfg.DistanceM);
            end
            if ~isfield(app.Cache, name) || ~strcmp(app.Cache.(name).Key, key)
                app.Cache.(name) = struct('Key', key, 'Value', m8Column(app.Pattern, name, base));
            end
            values = app.Cache.(name).Value;
            definitions = m8Definitions(app.Pattern);
            definition = definitions(strcmp({definitions.Name}, name));
            if definition.Offset && cfg.LossDB ~= 0
                values = values + cfg.LossDB;
            elseif strcmp(name, 'PFD_Wm2') && cfg.LossDB ~= 0
                values = values .* 10^(cfg.LossDB / 10);
            elseif strcmp(name, 'E_RMS_Vm') && cfg.LossDB ~= 0
                values = values .* 10^(cfg.LossDB / 20);
            end
        end

        function render(app)
            cfg = app.config();
            tab = app.UI.Tabs.SelectedTab.Title;
            if strcmp(tab, 'Pattern')
                values = app.columnCached(app.UI.Component.Value, cfg);
                app.renderPattern(values);
                app.renderCut(values);
                metrics = app.Metrics;
                rows = {'Source', app.Pattern.Meta.Name; ...
                    'Samples', numel(values); 'Frequency (Hz)', app.Pattern.Meta.FrequencyHz; ...
                    'Level unit', app.Pattern.Meta.Unit; ...
                    'Total peak (dB)', metrics.PeakDB + cfg.LossDB; ...
                    'Peak theta (deg)', metrics.ThetaDeg; 'Peak phi (deg)', metrics.PhiDeg; ...
                    'Directivity (dB)', metrics.DirectivityDB; ...
                    'Gain integral (%)', metrics.EfficiencyPct * 10^(cfg.LossDB / 10); ...
                    'Front/back (dB)', metrics.FrontBackDB; ...
                    'Sampled solid angle (sr)', metrics.Omega; ...
                    'Full sphere', app.Pattern.FullSphere};
                app.UI.Metrics.Data = rows;
            elseif strcmp(tab, 'Coverage')
                app.renderCoverage();
            else
                app.renderData(cfg);
            end
            app.UI.Status.Text = sprintf('%s | %d samples | %s | M8 candidate, validate before production', ...
                app.Pattern.Meta.Name, prod(app.Pattern.Size), app.Pattern.Meta.Unit);
        end

        function renderPattern(app, values)
            pattern = app.Pattern;
            limits = [app.UI.ColorMin.Value app.UI.ColorMax.Value];
            assert(limits(1) < limits(2), 'APAT:Range', 'Color minimum must be below maximum.');
            phi = pattern.Phi;
            if strcmp(app.UI.SignedPhi.Value, '-180 to 180')
                phi = mod(phi + 180, 360) - 180;
            end
            [phi, order] = sort(phi);
            values = values(:, order);
            if pattern.PeriodicPhi
                phi(end + 1) = phi(1) + 360;
                values(:, end + 1) = values(:, 1);
            end
            [ph, th] = meshgrid(phi, pattern.Theta);
            visibleTheta = th;
            if strcmp(app.UI.Elevation.Value, 'Elevation')
                visibleTheta = 90 - th;
            end
            clipped = min(max(values, limits(1)), limits(2));
            mode = app.UI.View.Value;
            switch mode
                case 'Contour'
                    x = ph; y = visibleTheta; z = zeros(size(th));
                case 'Circular'
                    x = (th / 180) .* cosd(ph); y = (th / 180) .* sind(ph); z = zeros(size(th));
                case '3D rectangular'
                    x = ph; y = visibleTheta; z = clipped;
                otherwise
                    radius = ones(size(th));
                    if strcmp(mode, '3D gain')
                        radius = (clipped - limits(1)) / diff(limits);
                    end
                    x = radius .* sind(th) .* cosd(ph);
                    y = radius .* sind(th) .* sind(ph);
                    z = radius .* cosd(th);
            end
            ax = app.UI.Axes;
            if ~isfield(app.Graphics, 'Surface') || ~isgraphics(app.Graphics.Surface)
                app.Graphics.Surface = surf(ax, x, y, z, values, 'EdgeColor', 'none', 'FaceColor', 'interp');
            else
                set(app.Graphics.Surface, 'XData', x, 'YData', y, 'ZData', z, 'CData', values);
            end
            clim(ax, limits);
            colormap(ax, parula(256));
            title(ax, strrep(app.UI.Component.Value, '_', ' '), 'Interpreter', 'none');
            axis(ax, 'normal');
            axis(ax, 'tight');
            grid(ax, 'on');
            changedMode = ~isfield(app.Graphics, 'ViewMode') || ~strcmp(app.Graphics.ViewMode, mode);
            if changedMode
                view(ax, 3);
                if ismember(mode, {'Contour', 'Circular'})
                    view(ax, 2);
                end
                app.Graphics.ViewMode = mode;
            end
            xlabel(ax, 'X'); ylabel(ax, 'Y'); zlabel(ax, 'Z');
            if ismember(mode, {'Contour', '3D rectangular'})
                xlabel(ax, 'Phi (deg)'); ylabel(ax, [app.UI.Elevation.Value ' theta (deg)']);
            else
                axis(ax, 'equal');
            end
        end

        function renderCut(app, values)
            [angles, cut, fixed, closed] = m8Cut(app.Pattern, values, ...
                app.UI.CutType.Value, app.UI.CutAngle.Value);
            definitions = m8Definitions(app.Pattern);
            definition = definitions(strcmp({definitions.Name}, app.UI.Component.Value));
            width = NaN;
            if strcmp(definition.Kind, 'level')
                width = m8HPBW(angles, cut, closed);
            end
            polar = strcmp(app.UI.CutView.Value, 'Polar');
            app.UI.CutAxes.Visible = matlab.lang.OnOffSwitchState(~polar);
            app.UI.PolarAxes.Visible = matlab.lang.OnOffSwitchState(polar);
            if polar
                ax = app.UI.PolarAxes;
                floorDB = app.UI.ColorMin.Value;
                radius = max(cut - floorDB, 0);
                if ~isfield(app.Graphics, 'PolarCut') || ~isgraphics(app.Graphics.PolarCut)
                    app.Graphics.PolarCut = polarplot(ax, deg2rad(angles), radius, 'LineWidth', 1.6);
                else
                    set(app.Graphics.PolarCut, 'ThetaData', deg2rad(angles), 'RData', radius);
                end
                ax.RTickLabel = compose('%g', ax.RTick + floorDB);
            else
                ax = app.UI.CutAxes;
                if ~isfield(app.Graphics, 'Cut') || ~isgraphics(app.Graphics.Cut)
                    app.Graphics.Cut = plot(ax, angles, cut, 'LineWidth', 1.6);
                else
                    set(app.Graphics.Cut, 'XData', angles, 'YData', cut);
                end
                xlabel(ax, 'Sweep angle (deg)'); ylabel(ax, 'Selected component'); grid(ax, 'on');
            end
            if isfield(app.Graphics, 'Cut')
                app.Graphics.Cut.Visible = matlab.lang.OnOffSwitchState(~polar);
            end
            if isfield(app.Graphics, 'PolarCut')
                app.Graphics.PolarCut.Visible = matlab.lang.OnOffSwitchState(polar);
            end
            title(ax, sprintf('%s sweep; fixed %.4g deg; HPBW %.4g deg', ...
                app.UI.CutType.Value, fixed, width), 'FontSize', 10);
        end

        function renderData(app, cfg)
            kind = app.UI.DataKind.Value;
            if strcmp(kind, 'Metadata')
                metadata = app.Pattern.Meta;
                names = fieldnames(metadata);
                text = cell(size(names));
                for k = 1:numel(names)
                    text{k} = char(strjoin(string(metadata.(names{k})), ', '));
                end
                data = table(string(names), string(text), 'VariableNames', {'Property', 'Value'});
                totalRows = height(data);
            elseif strcmp(kind, 'Input')
                data = app.Source.Blocks{str2double(app.UI.Block.Value)};
                totalRows = height(data);
            else
                totalRows = prod(app.Pattern.Size);
                previewIndex = (1:min(500, totalRows)).';
                [row, col] = ind2sub(app.Pattern.Size, previewIndex);
                theta = app.Pattern.Theta(row); phi = app.Pattern.Phi(col);
                data = table(theta(:), phi(:), 'VariableNames', {'Theta', 'Phi'});
                definitions = m8Definitions(app.Pattern);
                for k = 1:numel(definitions)
                    values = app.columnCached(definitions(k).Name, cfg);
                    data.(definitions(k).Name) = values(previewIndex);
                end
            end
            app.UI.DataNote.Text = sprintf('Preview: first %d of %d rows. CSV exports all result rows.', ...
                min(500, height(data)), totalRows);
            app.UI.DataTable.Data = data(1:min(500, height(data)), :);
        end

        function computeCoverage(app)
            cfg = app.config();
            name = app.UI.Component.Value;
            definitions = m8Definitions(app.Pattern);
            definition = definitions(strcmp({definitions.Name}, name));
            assert(strcmp(definition.Kind, 'level') || strcmp(name, 'PLF_dB'), ...
                'APAT:CoverageColumn', 'Coverage supports gain-like levels and PLF; select one of these components.');
            values = app.columnCached(name, cfg);
            weights = app.Pattern.ThetaWeight * app.Pattern.PhiWeight;
            mask = true(size(values));
            region = app.UI.Region.Value;
            if strcmp(region, 'Cone')
                [ph, th] = meshgrid(app.Pattern.Phi, app.Pattern.Theta);
                cosine = cosd(th) * cosd(app.UI.ConeTheta.Value) + ...
                    sind(th) * sind(app.UI.ConeTheta.Value) .* cosd(ph - app.UI.ConePhi.Value);
                mask = cosine >= cosd(app.UI.ConeAngle.Value) - 1e-12;
                region = sprintf('Cone %.4g/%.4g, half-angle %.4g', app.UI.ConeTheta.Value, ...
                    app.UI.ConePhi.Value, app.UI.ConeAngle.Value);
            end
            low = app.UI.ThresholdMin.Value;
            high = app.UI.ThresholdMax.Value;
            step = app.UI.ThresholdStep.Value;
            assert(low < high, 'APAT:ThresholdRange', 'Threshold minimum must be below maximum.');
            count = floor((high - low) / step + 1e-10);
            assert(count <= 20000, 'APAT:ThresholdLimit', 'Use at most 20,001 thresholds per job.');
            thresholds = low + (0:count).' * step;
            distribution = m8Distribution(values, weights, mask);
            job = struct('Name', sprintf('%d: %s / %s', numel(app.Jobs) + 1, ...
                app.Pattern.Meta.Name, name), 'Threshold', thresholds, ...
                'Coverage', m8Evaluate(distribution, thresholds), 'Distribution', distribution, ...
                'Loss', cfg.LossDB, 'Region', region);
            app.Jobs(end + 1) = job;
            app.UI.Job.Items = {app.Jobs.Name};
            app.UI.Job.Value = job.Name;
        end

        function renderCoverage(app)
            if isempty(app.Jobs)
                return
            end
            job = app.Jobs(strcmp({app.Jobs.Name}, app.UI.Job.Value));
            ax = app.UI.CoverageAxes;
            if ~isfield(app.Graphics, 'Coverage') || ~isgraphics(app.Graphics.Coverage)
                app.Graphics.Coverage = stairs(ax, job.Threshold, job.Coverage, 'LineWidth', 1.8);
            else
                set(app.Graphics.Coverage, 'XData', job.Threshold, 'YData', job.Coverage);
            end
            xlabel(ax, 'Threshold (dB)'); ylabel(ax, 'Weighted coverage (%)');
            ylim(ax, [0 100]); grid(ax, 'on'); title(ax, job.Region, 'Interpreter', 'none');
            app.UI.CoverageTable.Data = table(job.Threshold, job.Coverage, ...
                'VariableNames', {'Threshold_dB', 'Coverage_pct'});
            value = m8Evaluate(job.Distribution, app.UI.Query.Value);
            app.UI.QueryResult.Text = sprintf('Strict > threshold: %.6g%% (snapshot)', value);
        end

        function export(app, action)
            assert(isfield(app.Pattern, 'Theta'), 'APAT:NoPattern', 'Load a pattern first.');
            if strcmp(action, 'exportPlot')
                [name, folder] = uiputfile('*.png', 'Export full-pattern plot');
                if ~isequal(name, 0)
                    exportgraphics(app.UI.Axes, fullfile(folder, name), 'Resolution', 200);
                end
                return
            end
            extension = '*.csv';
            if strcmp(action, 'exportMAT')
                extension = '*.mat';
            end
            [name, folder] = uiputfile(extension, 'Export APAT data');
            if isequal(name, 0)
                return
            end
            path = fullfile(folder, name);
            if strcmp(action, 'exportCoverage')
                assert(~isempty(app.Jobs), 'APAT:NoCoverage', 'Compute a coverage job first.');
                job = app.Jobs(strcmp({app.Jobs.Name}, app.UI.Job.Value));
                writetable(table(job.Threshold, job.Coverage, ...
                    'VariableNames', {'Threshold_dB', 'Coverage_pct'}), path);
            elseif strcmp(action, 'exportMAT')
                PatternTable = m8PrimitiveTable(app.Pattern); %#ok<NASGU>
                Metadata = app.Pattern.Meta; %#ok<NASGU>
                Parameters = app.config(); %#ok<NASGU>
                save(path, 'PatternTable', 'Metadata', 'Parameters');
            else
                writetable(m8ExportTable(app.Pattern, app.config()), path);
            end
        end
    end
end

function options = m8Options(given)
options = struct('Format', 'named', 'ThetaConvention', 'polar', ...
    'FFDOrder', 'theta-fast', 'AbsoluteGain', false, 'StepDeg', 0, ...
    'Interpolation', 'cartesian', 'LossDB', 0, 'RxMode', 'Auto', ...
    'RxARDB', 0, 'RxTiltDeg', 0, 'PowerDBW', 0, 'DistanceM', 1);
names = fieldnames(given);
for k = 1:numel(names)
    assert(isfield(options, names{k}), 'APAT:Option', 'Unknown option: %s', names{k});
    options.(names{k}) = given.(names{k});
end
validateattributes(options.DistanceM, {'numeric'}, {'scalar', 'positive', 'finite'});
validateattributes(options.LossDB, {'numeric'}, {'scalar', 'finite'});
validateattributes(options.PowerDBW, {'numeric'}, {'scalar', 'finite'});
validateattributes(options.RxARDB, {'numeric'}, {'scalar', 'nonnegative', 'finite'});
validateattributes(options.RxTiltDeg, {'numeric'}, {'scalar', 'finite'});
validateattributes(options.StepDeg, {'numeric'}, {'scalar', 'nonnegative', 'finite'});
assert(ismember(string(options.ThetaConvention), ["polar", "elevation"]), 'APAT:Convention', 'Unknown theta convention.');
assert(ismember(string(options.RxMode), ["Auto", "RHCP", "LHCP", "Theta", "Phi"]), 'APAT:RxMode', 'Unknown receive state.');
end

function source = m8Source(data, name, options)
metadata = struct('Name', char(name), 'Format', options.Format, ...
    'Unit', 'dB relative', 'AbsoluteGain', logical(options.AbsoluteGain), ...
    'ThetaConvention', options.ThetaConvention, 'FrequencyHz', NaN, 'Notes', '');
if metadata.AbsoluteGain
    metadata.Unit = 'dBi';
end
source = struct('Blocks', {{data}}, 'Metadata', {{metadata}}, 'FrequenciesHz', NaN);
end

function pattern = m8Canonical(data, metadata)
required = {'Theta', 'Phi'};
assert(istable(data) && ~isempty(data) && all(ismember(required, data.Properties.VariableNames)), ...
    'APAT:Input', 'Expected a nonempty table with Theta and Phi.');
fieldNames = {'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'};
hasFields = all(ismember(fieldNames, data.Properties.VariableNames));
if hasFields
    columns = fieldNames;
else
    assert(ismember('Gain_dB', data.Properties.VariableNames), ...
        'APAT:Columns', 'Provide Gain_dB or all four canonical real/imaginary field columns.');
    columns = {'Gain_dB'};
end
angles = double(data{:, required});
values = double(data{:, columns});
assert(isreal(angles) && isreal(values), 'APAT:RealColumns', 'Real/imaginary columns must themselves be real.');
assert(all(isfinite(angles), 'all'), 'APAT:Angles', 'Angles must be finite.');
if strcmp(metadata.ThetaConvention, 'elevation')
    angles(:, 1) = 90 - angles(:, 1);
end
assert(all(angles(:, 1) >= -1e-8 & angles(:, 1) <= 180 + 1e-8), ...
    'APAT:ThetaDomain', 'Polar theta must be in [0,180]. Convert extended-angle field bases explicitly.');
assert(~any(values == Inf, 'all'), 'APAT:InfiniteValue', 'Positive infinite source values are not supported.');
if hasFields
    assert(~any(values == -Inf, 'all'), 'APAT:InfiniteField', 'Field components must be finite or NaN.');
end
phiRaw = angles(:, 2);
angles(:, 1) = min(180, max(0, round(angles(:, 1), 9)));
angles(:, 2) = mod(round(angles(:, 2), 9), 360);
[directions, first, group] = unique(angles, 'rows', 'sorted');
reference = values(first(group), :);
scale = max(max(abs(values), abs(reference)), [], 2);
if ~hasFields
    scale = max(scale, 1);
end
tolerance = 128 * eps(scale);
agreement = values == reference | (isnan(values) & isnan(reference)) | abs(values - reference) <= tolerance;
assert(all(agreement, 'all'), 'APAT:DuplicateConflict', 'Duplicate directions or seam endpoints contain conflicting values.');
values = values(first, :);
theta = unique(directions(:, 1));
phi = unique(directions(:, 2)).';
assert(numel(theta) >= 2 && numel(phi) >= 2, 'APAT:GridDimension', 'At least two theta and two phi coordinates are required.');
assert(numel(theta) * numel(phi) == size(directions, 1), ...
    'APAT:IncompleteGrid', 'A complete rectangular angular grid is required; missing cells are not fabricated.');
[~, thetaIndex] = ismember(directions(:, 1), theta);
[~, phiIndex] = ismember(directions(:, 2), phi);
shape = [numel(theta), numel(phi)];
index = sub2ind(shape, thetaIndex, phiIndex);
delta = diff(phi);
uniformPhi = max(abs(delta - delta(1))) < 1e-8;
closedSource = max(phiRaw) - min(phiRaw) >= 360 - 1e-8;
periodic = closedSource || (uniformPhi && abs(phi(end) - phi(1) + delta(1) - 360) < 1e-8);
assert(periodic || ~any(delta > 180), 'APAT:WrappedPartialPhi', ...
    'A partial phi domain crossing the zero seam needs an explicit domain model; rc1 refuses to invent its extent.');
thetaEdges = [theta(1); (theta(1:end-1) + theta(2:end)) / 2; theta(end)];
thetaWeight = cosd(thetaEdges(1:end-1)) - cosd(thetaEdges(2:end));
if periodic
    gaps = diff([phi phi(1) + 360]);
    phiWeight = deg2rad((gaps + gaps([end 1:end-1])) / 2);
else
    phiEdges = [phi(1), (phi(1:end-1) + phi(2:end)) / 2, phi(end)];
    phiWeight = deg2rad(diff(phiEdges));
end
metadata.ThetaConvention = 'polar';
pattern = struct('Theta', theta, 'Phi', phi, 'Size', shape, ...
    'ThetaWeight', thetaWeight, 'PhiWeight', phiWeight, ...
    'PeriodicPhi', periodic, 'FullSphere', periodic && theta(1) == 0 && theta(end) == 180, ...
    'HasFields', hasFields, 'Eth', [], 'Eph', [], 'Gain', [], 'Meta', metadata);
if hasFields
    eth = complex(zeros(shape)); eph = eth;
    eth(index) = complex(values(:, 1), values(:, 2));
    eph(index) = complex(values(:, 3), values(:, 4));
    pattern.Eth = eth; pattern.Eph = eph;
else
    gain = zeros(shape); gain(index) = values;
    pattern.Gain = gain;
end
end

function definitions = m8Definitions(pattern)
names = {'E_Total_dB'};
kinds = {'level'};
if pattern.HasFields
    names = [names, {'E_TH_dB', 'E_PH_dB', 'E_RCP_dB', 'E_LCP_dB', ...
        'AR_dB', 'Signed_AR_dB', 'PLF_dB', 'Gain_PolCorrected_dB', ...
        'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase'}];
    kinds = [kinds, {'level', 'level', 'level', 'level', 'ratio', 'ratio', ...
        'ratio', 'level', 'phase', 'phase', 'phase', 'phase'}];
end
if pattern.Meta.AbsoluteGain
    names = [names, {'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'}];
    kinds = [kinds, {'link', 'link', 'link'}];
end
definitions = struct('Name', names, 'Kind', kinds, 'Offset', false);
for k = 1:numel(names)
    definitions(k).Offset = strcmp(kinds{k}, 'level') || strcmp(names{k}, 'EIRP_dBW');
end
end

function values = m8Column(pattern, name, cfg)
definitions = m8Definitions(pattern);
assert(ismember(name, {definitions.Name}), 'APAT:Component', 'Unavailable component: %s', name);
if ismember(name, {'E_Total_dB', 'EIRP_dBW', 'PFD_Wm2', 'E_RMS_Vm'})
    if pattern.HasFields
        gain = 20 * log10(hypot(abs(pattern.Eth), abs(pattern.Eph)));
    else
        gain = pattern.Gain;
    end
end
switch name
    case 'E_Total_dB'
        values = gain + cfg.LossDB;
    case {'E_TH_dB', 'E_PH_dB', 'E_RCP_dB', 'E_LCP_dB', ...
            'E_TH_Phase', 'E_PH_Phase', 'E_RCP_Phase', 'E_LCP_Phase'}
        if startsWith(name, 'E_TH_')
            field = pattern.Eth;
        elseif startsWith(name, 'E_PH_')
            field = pattern.Eph;
        else
            [right, left] = m8Circular(pattern.Eth, pattern.Eph);
            field = right;
            if startsWith(name, 'E_LCP_')
                field = left;
            end
        end
        if endsWith(name, 'Phase')
            values = rad2deg(angle(field));
            values(abs(field) == 0) = NaN;
        else
            values = 20 * log10(abs(field)) + cfg.LossDB;
        end
    case {'AR_dB', 'Signed_AR_dB'}
        [right, left] = m8Circular(pattern.Eth, pattern.Eph);
        difference = abs(right) - abs(left);
        sumMagnitude = abs(right) + abs(left);
        values = 20 * log10(sumMagnitude ./ abs(difference));
        values(sumMagnitude == 0) = NaN;
        if strcmp(name, 'Signed_AR_dB')
            values = values .* sign(difference);
            values(abs(difference) <= 16 * eps(sumMagnitude)) = NaN;
        end
    case {'PLF_dB', 'Gain_PolCorrected_dB'}
        [receiveTheta, receivePhi] = m8Receiver(pattern, cfg);
        scale = max(abs(pattern.Eth), abs(pattern.Eph));
        normalizedTheta = pattern.Eth ./ scale;
        normalizedPhi = pattern.Eph ./ scale;
        received = abs(conj(receiveTheta) .* normalizedTheta + conj(receivePhi) .* normalizedPhi).^2;
        if strcmp(name, 'PLF_dB')
            total = abs(normalizedTheta).^2 + abs(normalizedPhi).^2;
            fraction = min(max(received ./ total, 0), 1);
            fraction(scale == 0 | isnan(pattern.Eth) | isnan(pattern.Eph)) = NaN;
            values = 10 * log10(fraction);
        else
            values = 10 * log10(received) + 20 * log10(scale) + cfg.LossDB;
            values(scale == 0) = -Inf;
            values(isnan(pattern.Eth) | isnan(pattern.Eph)) = NaN;
        end
    case 'EIRP_dBW'
        values = cfg.PowerDBW + gain + cfg.LossDB;
    case 'PFD_Wm2'
        values = 10.^((cfg.PowerDBW + gain + cfg.LossDB) / 10) / (4 * pi * cfg.DistanceM^2);
    case 'E_RMS_Vm'
        values = sqrt(30 * 10.^((cfg.PowerDBW + gain + cfg.LossDB) / 10)) / cfg.DistanceM;
end
end

function [right, left] = m8Circular(eth, eph)
% e^(+jwt), right-handed (theta, phi, r): conjugate-basis projection.
right = (eth + 1i * eph) / sqrt(2);
left = (eth - 1i * eph) / sqrt(2);
end

function [eth, eph] = m8Receiver(pattern, cfg)
mode = cfg.RxMode;
if strcmp(mode, 'Auto')
    power = hypot(abs(pattern.Eth), abs(pattern.Eph));
    power(~isfinite(power)) = -Inf;
    [~, index] = max(power(:));
    [right, left] = m8Circular(pattern.Eth(index), pattern.Eph(index));
    mode = 'RHCP';
    if abs(left) > abs(right)
        mode = 'LHCP';
    end
end
if strcmp(mode, 'Theta')
    eth = 1; eph = 0;
elseif strcmp(mode, 'Phi')
    eth = 0; eph = 1;
else
    sense = 1 - 2 * strcmp(mode, 'LHCP');
    minor = 10^(-cfg.RxARDB / 20);
    scale = sqrt(1 + minor^2);
    eth = (cosd(cfg.RxTiltDeg) + 1i * sense * minor * sind(cfg.RxTiltDeg)) / scale;
    eph = (sind(cfg.RxTiltDeg) - 1i * sense * minor * cosd(cfg.RxTiltDeg)) / scale;
end
end

function metrics = m8Metrics(pattern)
gain = m8Column(pattern, 'E_Total_dB', m8Options(struct()));
weights = pattern.ThetaWeight * pattern.PhiWeight;
metrics = struct('PeakDB', NaN, 'ThetaDeg', NaN, 'PhiDeg', NaN, ...
    'DirectivityDB', NaN, 'EfficiencyPct', NaN, 'FrontBackDB', NaN, 'Omega', sum(weights, 'all'));
candidate = gain;
candidate(isnan(candidate)) = -Inf;
[peak, index] = max(candidate(:));
if ~isfinite(peak)
    return
end
[row, col] = ind2sub(pattern.Size, index);
metrics.PeakDB = peak;
metrics.ThetaDeg = pattern.Theta(row);
metrics.PhiDeg = pattern.Phi(col);
if ~pattern.FullSphere || any(isnan(gain), 'all')
    return
end
integral = sum(10.^((gain - peak) / 10) .* weights, 'all');
if integral > 0
    metrics.DirectivityDB = 10 * log10(4 * pi / integral);
    if pattern.Meta.AbsoluteGain
        metrics.EfficiencyPct = 100 * 10^((peak - metrics.DirectivityDB) / 10);
    end
end
[ph, th] = meshgrid(pattern.Phi, pattern.Theta);
similarity = cosd(th) * cosd(metrics.ThetaDeg) + ...
    sind(th) * sind(metrics.ThetaDeg) .* cosd(ph - metrics.PhiDeg);
[~, back] = min(similarity(:));
metrics.FrontBackDB = peak - gain(back);
end

function distribution = m8Distribution(gain, weights, mask)
assert(isequal(size(gain), size(weights), size(mask)), 'APAT:CoverageSize', 'Gain, weights and mask must have identical sizes.');
validateattributes(weights, {'numeric'}, {'real', 'nonnegative', 'finite'});
assert(islogical(mask) || (isnumeric(mask) && isreal(mask) && all(isfinite(mask), 'all')), ...
    'APAT:CoverageMask', 'A region mask must be logical or finite real numeric data.');
assert(isreal(gain) && ~any(gain == Inf, 'all'), 'APAT:CoverageGain', 'Gain must be real and cannot contain +Inf.');
valid = logical(mask) & ~isnan(gain) & weights > 0;
[levels, order] = sort(double(gain(valid)));
weight = double(weights(valid));
weight = weight(order);
tail = [flipud(cumsum(flipud(weight(:)))); 0];
distribution = struct('Levels', levels(:), 'Tail', tail, 'Omega', tail(1), ...
    'RegionOmega', sum(weights(logical(mask))));
end

function coverage = m8Evaluate(distribution, thresholds)
% Coverage(T) = 100 * sum(weight(gain > T)) / sum(valid region weight).
% Upper-bound search preserves strict ties without an N-by-T allocation.
validateattributes(thresholds, {'numeric'}, {'real'});
coverage = NaN(size(thresholds));
if distribution.Omega <= 0
    return
end
levels = distribution.Levels;
for k = 1:numel(thresholds)
    if isnan(thresholds(k))
        continue
    end
    lo = 1; hi = numel(levels) + 1;
    while lo < hi
        middle = floor((lo + hi) / 2);
        if middle <= numel(levels) && levels(middle) <= thresholds(k)
            lo = middle + 1;
        else
            hi = middle;
        end
    end
    coverage(k) = 100 * distribution.Tail(lo) / distribution.Omega;
end
end

function [angles, values, fixed, closed] = m8Cut(pattern, grid, type, request)
closed = pattern.PeriodicPhi;
if strcmp(type, 'Phi')
    [~, index] = min(abs(pattern.Theta - request));
    fixed = pattern.Theta(index);
    angles = pattern.Phi(:);
    values = grid(index, :).';
else
    [~, index] = min(abs(mod(pattern.Phi - request + 180, 360) - 180));
    fixed = pattern.Phi(index);
    opposite = find(abs(mod(pattern.Phi - fixed, 360) - 180) < 1e-8, 1);
    angles = pattern.Theta;
    values = grid(:, index);
    closed = closed && ~isempty(opposite) && pattern.Theta(1) == 0 && pattern.Theta(end) == 180;
    if closed
        angles = [angles; 360 - flipud(pattern.Theta(2:end-1))];
        values = [values; flipud(grid(2:end-1, opposite))];
    end
end
if closed
    angles(end + 1) = angles(1) + 360;
    values(end + 1) = values(1);
end
end

function width = m8HPBW(angles, values, closed)
width = NaN;
angles = angles(:); values = values(:);
if numel(values) < 3
    return
end
if closed && abs(angles(end) - angles(1) - 360) < 1e-8
    angles(end) = []; values(end) = [];
end
candidate = values; candidate(~isfinite(candidate)) = -Inf;
[peak, index] = max(candidate);
if ~isfinite(peak)
    return
end
if closed
    count = numel(values);
    angles = [angles - 360; angles; angles + 360];
    values = [values; values; values];
    index = index + count;
end
half = peak - 10 * log10(2);
left = index; right = index;
while left > 1 && values(left) > half
    left = left - 1;
end
while right < numel(values) && values(right) > half
    right = right + 1;
end
if left == index || right == index || values(left) > half || values(right) > half || ...
        any(~isfinite(values(left:right)))
    return
end
lower = angles(left) + (half - values(left)) * ...
    (angles(left + 1) - angles(left)) / (values(left + 1) - values(left));
upper = angles(right - 1) + (half - values(right - 1)) * ...
    (angles(right) - angles(right - 1)) / (values(right) - values(right - 1));
if upper - lower < 360
    width = upper - lower;
end
end

function target = m8Resample(pattern, step, method)
validateattributes(step, {'numeric'}, {'scalar', 'positive', 'finite'});
assert(ismember(string(method), ["cartesian", "power-phase"]), 'APAT:Interpolation', 'Unknown interpolation method.');
thetaCount = ceil((pattern.Theta(end) - pattern.Theta(1)) / step) + 1;
phiSpan = pattern.Phi(end) - pattern.Phi(1);
if pattern.PeriodicPhi
    phiSpan = 360;
end
phiCount = ceil(phiSpan / step) + double(~pattern.PeriodicPhi);
assert(thetaCount * phiCount <= 2e6, 'APAT:GridLimit', ...
    'Requested grid exceeds two million samples; allocation was not attempted.');
theta = m8TargetAxis(pattern.Theta(1), pattern.Theta(end), step);
if pattern.PeriodicPhi
    phi = 0:step:(360 - 1e-9);
else
    phi = m8TargetAxis(pattern.Phi(1), pattern.Phi(end), step).';
end
assert(numel(theta) * numel(phi) <= 2e6, 'APAT:GridLimit', 'Requested grid exceeds two million samples.');
[queryPhi, queryTheta] = meshgrid(phi, theta);
if pattern.PeriodicPhi
    queryPhi = mod(queryPhi - pattern.Phi(1), 360) + pattern.Phi(1);
end
[exactTheta, thetaIndex] = ismember(round(theta, 9), round(pattern.Theta, 9));
[exactPhi, phiIndex] = ismember(round(phi, 9), round(pattern.Phi, 9));
target = pattern;
fields = {'Gain'};
if pattern.HasFields
    fields = {'Eth', 'Eph'};
end
for k = 1:numel(fields)
    name = fields{k};
    data = pattern.(name);
    if all(exactTheta) && all(exactPhi)
        target.(name) = data(thetaIndex, phiIndex);
        continue
    end
    if strcmp(name, 'Gain')
        finite = data(isfinite(data));
        reference = 0;
        if ~isempty(finite)
            reference = max(finite);
        end
        power = 10.^((data - reference) / 10);
        target.(name) = 10 * log10(m8Interpolate(pattern, power, queryTheta, queryPhi)) + reference;
    elseif strcmp(method, 'cartesian')
        target.(name) = m8Interpolate(pattern, real(data), queryTheta, queryPhi) + ...
            1i * m8Interpolate(pattern, imag(data), queryTheta, queryPhi);
    else
        amplitude = abs(data);
        phasor = zeros(size(data));
        nonzero = amplitude > 0;
        phasor(nonzero) = data(nonzero) ./ amplitude(nonzero);
        phasor(isnan(amplitude)) = NaN;
        power = m8Interpolate(pattern, amplitude.^2, queryTheta, queryPhi);
        direction = m8Interpolate(pattern, real(phasor), queryTheta, queryPhi) + ...
            1i * m8Interpolate(pattern, imag(phasor), queryTheta, queryPhi);
        field = sqrt(max(power, 0)) .* exp(1i * angle(direction));
        field(abs(direction) < 1e-12 & power > 0) = NaN;
        field(isnan(power) | isnan(direction)) = NaN;
        target.(name) = field;
    end
end
target.Theta = theta(:); target.Phi = phi(:).'; target.Size = [numel(theta), numel(phi)];
metadata = target.Meta;
metadata.Notes = [metadata.Notes ' Resampled: ' char(method) '.'];
data = m8PrimitiveTable(target);
if pattern.PeriodicPhi
    seam = data(data.Phi == 0, :);
    seam.Phi(:) = 360;
    data = [data; seam];
end
target = m8Canonical(data, metadata);
end

function axis = m8TargetAxis(low, high, step)
axis = low + (0:floor((high - low) / step + 1e-10)).' * step;
if abs(axis(end) - high) > 1e-8
    axis(end + 1) = high;
end
end

function values = m8Interpolate(pattern, data, theta, phi)
sourcePhi = pattern.Phi;
if pattern.PeriodicPhi
    sourcePhi(end + 1) = sourcePhi(1) + 360;
    data(:, end + 1) = data(:, 1);
end
interpolant = griddedInterpolant({pattern.Theta, sourcePhi}, data, 'linear', 'none');
values = interpolant(theta, phi);
end

function data = m8PrimitiveTable(pattern)
[ph, th] = meshgrid(pattern.Phi, pattern.Theta);
data = table(th(:), ph(:), 'VariableNames', {'Theta', 'Phi'});
if pattern.HasFields
    data.Re_Eth = real(pattern.Eth(:)); data.Im_Eth = imag(pattern.Eth(:));
    data.Re_Eph = real(pattern.Eph(:)); data.Im_Eph = imag(pattern.Eph(:));
else
    data.Gain_dB = pattern.Gain(:);
end
end

function data = m8ExportTable(pattern, cfg)
[ph, th] = meshgrid(pattern.Phi, pattern.Theta);
data = table(th(:), ph(:), 'VariableNames', {'Theta', 'Phi'});
definitions = m8Definitions(pattern);
for k = 1:numel(definitions)
    values = m8Column(pattern, definitions(k).Name, cfg);
    data.(definitions(k).Name) = values(:);
end
end

function source = m8Read(path, options)
assert(isfile(path), 'APAT:File', 'File does not exist: %s', path);
[~, name, extension] = fileparts(path);
switch lower(extension)
    case {'.csv', '.txt', '.dat'}
        if strcmp(options.Format, 'named')
            original = readtable(path, 'VariableNamingRule', 'preserve');
            keys = lower(regexprep(string(original.Properties.VariableNames), '[^a-zA-Z0-9]', ''));
            thetaIndex = find(ismember(keys, ["theta", "thetadeg", "elevation", "elevationdeg", "el"]), 1);
            phiIndex = find(ismember(keys, ["phi", "phideg", "azimuth", "azimuthdeg", "az"]), 1);
            assert(~isempty(thetaIndex) && ~isempty(phiIndex), 'APAT:NamedAxes', ...
                'Named import requires theta/phi or elevation/azimuth headers. Choose an explicit layout for headerless data.');
            if ismember(keys(thetaIndex), ["elevation", "elevationdeg", "el"])
                options.ThetaConvention = 'elevation';
            end
            fieldKeys = ["reeth", "imeth", "reeph", "imeph"];
            [hasFields, indices] = ismember(fieldKeys, keys);
            if all(hasFields)
                data = m8Numeric(original{:, [thetaIndex phiIndex indices]}, 'complex');
            else
                gainIndex = find(ismember(keys, ["gain", "gaindb", "gaindbi", "etotaldb", "totalgaindbi"]), 1);
                assert(~isempty(gainIndex), 'APAT:NamedValues', 'Expected Gain_dB/Gain_dBi or Re_Eth, Im_Eth, Re_Eph, Im_Eph.');
                data = m8Numeric(original{:, [thetaIndex phiIndex gainIndex]}, 'gain');
                options.AbsoluteGain = options.AbsoluteGain || contains(keys(gainIndex), 'dbi');
            end
        else
            matrix = readmatrix(path);
            assert(size(matrix, 2) >= 3, 'APAT:TextColumns', 'At least three numeric columns are required.');
            data = m8Numeric(matrix, options.Format);
        end
        source = m8Source(data, [name extension], options);
    case '.mat'
        saved = load(path, 'PatternTable', 'Metadata');
        assert(isfield(saved, 'PatternTable') && istable(saved.PatternTable), ...
            'APAT:MATSchema', 'MAT input must contain the table PatternTable.');
        source = m8Source(saved.PatternTable, [name extension], options);
        if isfield(saved, 'Metadata')
            known = fieldnames(source.Metadata{1});
            for k = 1:numel(known)
                if isfield(saved.Metadata, known{k})
                    source.Metadata{1}.(known{k}) = saved.Metadata.(known{k});
                end
            end
            source.FrequenciesHz = source.Metadata{1}.FrequencyHz;
        end
    case '.ffd'
        source = m8ReadFFD(path, options);
    case '.ffe'
        source = m8ReadFFE(path, options);
    case {'.xlsx', '.xls'}
        source = m8ReadExcel(path, options);
    otherwise
        error('APAT:UnsupportedFormat', ...
            'M8 rc1 does not yet implement %s. Convert to canonical CSV using M7; consult the compatibility matrix.', extension);
end
end

function data = m8Numeric(matrix, format)
assert(isnumeric(matrix) && isreal(matrix), 'APAT:NumericInput', 'Selected columns must be numeric and real.');
if strcmp(format, 'gain')
    assert(size(matrix, 2) >= 3, 'APAT:GainColumns', 'Gain layout: theta, phi, gain_dB.');
    data = array2table(matrix(:, 1:3), 'VariableNames', {'Theta', 'Phi', 'Gain_dB'});
else
    assert(size(matrix, 2) >= 6, 'APAT:FieldColumns', 'Field layouts require six numeric columns.');
    matrix = matrix(:, 1:6);
    if strcmp(format, 'magnitude-phase')
        % Explicit layout: theta, phi, theta_dB, phi_dB, theta_deg, phi_deg.
        eth = 10.^(matrix(:, 3) / 20) .* exp(1i * deg2rad(matrix(:, 5)));
        eph = 10.^(matrix(:, 4) / 20) .* exp(1i * deg2rad(matrix(:, 6)));
        eth(matrix(:, 3) == -Inf) = 0;
        eph(matrix(:, 4) == -Inf) = 0;
        matrix = [matrix(:, 1:2), real(eth), imag(eth), real(eph), imag(eph)];
    else
        assert(strcmp(format, 'complex'), 'APAT:TextFormat', 'Unknown explicit text layout.');
    end
    data = array2table(matrix, 'VariableNames', {'Theta', 'Phi', 'Re_Eth', 'Im_Eth', 'Re_Eph', 'Im_Eph'});
end
end

function source = m8ReadFFD(path, options)
lines = strtrim(splitlines(string(fileread(path))));
lines(strlength(lines) == 0) = [];
assert(numel(lines) >= 5, 'APAT:FFDHeader', 'Incomplete FFD file.');
thetaHeader = sscanf(lines(1), '%f').';
phiHeader = sscanf(lines(2), '%f').';
assert(numel(thetaHeader) == 3 && numel(phiHeader) == 3, 'APAT:FFDCoordinates', ...
    'Only theta/phi FFD is supported; AzOverEl and ElOverAz need explicit vector-basis conversion.');
counts = [thetaHeader(3), phiHeader(3)];
assert(all(counts >= 2 & counts == fix(counts)) && prod(counts) <= 2e6, 'APAT:FFDSize', 'Invalid FFD dimensions.');
theta = linspace(thetaHeader(1), thetaHeader(2), counts(1));
phi = linspace(phiHeader(1), phiHeader(2), counts(2));
token = regexp(char(lines(3)), '^Frequencies\s+(\d+)$', 'tokens', 'once');
assert(~isempty(token), 'APAT:FFDFrequencies', 'Expected Frequencies N in the third line.');
blockCount = str2double(token{1});
assert(blockCount >= 1 && blockCount <= 10000, 'APAT:FFDBlocks', 'Invalid FFD frequency count.');
assert(ismember(string(options.FFDOrder), ["theta-fast", "phi-fast"]), 'APAT:FFDOrder', 'Specify theta-fast or phi-fast.');
if strcmp(options.FFDOrder, 'theta-fast')
    [th, ph] = ndgrid(theta, phi);
else
    [ph, th] = ndgrid(phi, theta);
end
source = struct('Blocks', {cell(blockCount, 1)}, 'Metadata', {cell(blockCount, 1)}, ...
    'FrequenciesHz', NaN(blockCount, 1));
cursor = 4;
for block = 1:blockCount
    assert(cursor <= numel(lines), 'APAT:FFDEOF', 'Missing FFD frequency block.');
    token = regexp(char(lines(cursor)), '^Frequency\s+([+\-\d.eEdD]+)$', 'tokens', 'once');
    assert(~isempty(token), 'APAT:FFDFrequency', 'Expected Frequency followed by hertz.');
    frequency = str2double(regexprep(token{1}, '[dD]', 'E'));
    assert(isfinite(frequency) && frequency > 0, 'APAT:Frequency', 'Frequency must be positive and finite.');
    cursor = cursor + 1;
    count = prod(counts);
    assert(cursor + count - 1 <= numel(lines), 'APAT:FFDEOF', 'Truncated FFD field block.');
    fields = zeros(count, 4);
    for k = 1:count
        row = sscanf(regexprep(lines(cursor + k - 1), '[dD]', 'E'), '%f').';
        assert(numel(row) == 4, 'APAT:FFDRow', 'Every FFD field row must have four values.');
        fields(k, :) = row;
    end
    data = m8Numeric([th(:), ph(:), fields], 'complex');
    temporary = m8Source(data, path, options);
    metadata = temporary.Metadata{1};
    metadata.Format = 'FFD'; metadata.FrequencyHz = frequency;
    metadata.Notes = ['Explicit FFD order: ' options.FFDOrder '. No sidecar calibration.'];
    source.Blocks{block} = data; source.Metadata{block} = metadata;
    source.FrequenciesHz(block) = frequency;
    cursor = cursor + count;
end
assert(cursor > numel(lines), 'APAT:FFDTrailing', 'Unexpected data after the declared FFD blocks.');
end

function source = m8ReadFFE(path, options)
lines = splitlines(string(fileread(path)));
frequencyLines = find(~cellfun(@isempty, regexp(cellstr(lines), '^\s*#\s*Frequency\s*:', 'once')));
assert(~isempty(frequencyLines), 'APAT:FFEFrequency', 'FFE requires #Frequency: headers.');
blockCount = numel(frequencyLines);
source = struct('Blocks', {cell(blockCount, 1)}, 'Metadata', {cell(blockCount, 1)}, ...
    'FrequenciesHz', NaN(blockCount, 1));
boundaries = [frequencyLines; numel(lines) + 1];
for block = 1:blockCount
    chunk = lines(boundaries(block):boundaries(block + 1) - 1);
    header = strjoin(chunk, newline);
    coordinate = regexp(char(header), '(?im)^\s*#\s*Coordinate System\s*:\s*([^\r\n]+)', 'tokens', 'once');
    assert(~isempty(coordinate) && strcmpi(strtrim(coordinate{1}), 'Spherical'), ...
        'APAT:FFECoordinates', 'Only explicitly spherical FFE blocks are supported.');
    assert(isempty(regexp(char(header), '(?im)^\s*#\s*Result Type\s*:\s*RCS', 'once')), ...
        'APAT:FFERCS', 'RCS is not an antenna gain pattern.');
    token = regexp(char(chunk(1)), ':\s*([+\-\d.eEdD]+)', 'tokens', 'once');
    frequency = str2double(regexprep(token{1}, '[dD]', 'E'));
    assert(isfinite(frequency) && frequency > 0, 'APAT:Frequency', 'Frequency must be positive and finite.');
    rows = cell(numel(chunk), 1);
    count = 0;
    for k = 1:numel(chunk)
        if isempty(regexp(char(chunk(k)), '^\s*[+\-\d.]', 'once'))
            continue
        end
        row = sscanf(regexprep(chunk(k), '[dD]', 'E'), '%f').';
        assert(numel(row) >= 6, 'APAT:FFERow', 'FFE data rows require at least six values.');
        count = count + 1;
        rows{count} = row(1:6);
    end
    assert(count > 0 && count <= 2e6, 'APAT:FFERows', 'Invalid FFE sample count.');
    data = m8Numeric(vertcat(rows{1:count}), 'complex');
    temporary = m8Source(data, path, options);
    metadata = temporary.Metadata{1};
    metadata.Format = 'FFE'; metadata.FrequencyHz = frequency;
    metadata.Notes = 'Spherical complex fields. Vendor gain columns are not used for calibration in rc1.';
    source.Blocks{block} = data; source.Metadata{block} = metadata;
    source.FrequenciesHz(block) = frequency;
end
end

function source = m8ReadExcel(path, options)
sheets = string(sheetnames(path));
linear = ["Etheta_Gain_dBi", "Etheta_Phase_degrees", "Ephi_Gain_dBi", "Ephi_Phase_degrees"];
circular = ["RHCP_Gain_dBi", "RHCP_Phase_degrees", "LHCP_Gain_dBi", "LHCP_Phase_degrees"];
hasLinear = all(ismember(lower(linear), lower(sheets)));
hasCircular = all(ismember(lower(circular), lower(sheets)));
assert(hasLinear || hasCircular, 'APAT:ExcelSheets', 'Missing the four fixed linear or circular component sheets.');
required = linear;
if ~hasLinear
    required = circular;
end
matrices = cell(1, 4);
for k = 1:4
    sheet = sheets(find(strcmpi(sheets, required(k)), 1));
    cells = readcell(path, 'Sheet', char(sheet));
    assert(size(cells, 1) >= 4 && size(cells, 2) >= 4, 'APAT:ExcelSize', 'Expected a C3-origin matrix.');
    candidateTheta = cellfun(@m8CellNumber, cells(3:end, 2));
    candidatePhi = cellfun(@m8CellNumber, cells(2, 3:end));
    row = find(isfinite(candidateTheta)); col = find(isfinite(candidatePhi));
    assert(numel(row) >= 2 && numel(col) >= 2 && row(1) == 1 && col(1) == 1 && ...
        all(diff(row) == 1) && all(diff(col) == 1), 'APAT:ExcelAxes', 'Matrix axes must be contiguous from B3 and C2.');
    currentTheta = candidateTheta(row); currentPhi = candidatePhi(col);
    if k == 1
        theta = currentTheta; phi = currentPhi;
    else
        assert(isequal(theta, currentTheta) && isequal(phi, currentPhi), ...
            'APAT:ExcelGrid', 'All component worksheets must share identical axes.');
    end
    matrices{k} = cellfun(@m8CellNumber, cells(row + 2, col + 2));
end
first = 10.^(matrices{1} / 20) .* exp(1i * deg2rad(matrices{2}));
second = 10.^(matrices{3} / 20) .* exp(1i * deg2rad(matrices{4}));
first(matrices{1} == -Inf) = 0;
second(matrices{3} == -Inf) = 0;
if hasLinear
    eth = first; eph = second;
else
    eth = (first + second) / sqrt(2); eph = (first - second) / (1i * sqrt(2));
end
[ph, th] = meshgrid(phi, theta);
data = m8Numeric([th(:), ph(:), real(eth(:)), imag(eth(:)), real(eph(:)), imag(eph(:))], 'complex');
options.AbsoluteGain = true; options.ThetaConvention = 'polar';
source = m8Source(data, path, options);
source.Metadata{1}.Format = 'Excel C3 matrix';
if hasLinear && hasCircular
    source.Metadata{1}.Notes = 'Linear sheets are authoritative. Redundant circular sheets are not cross-validated in rc1.';
end
end

function value = m8CellNumber(cellValue)
if isnumeric(cellValue) && isscalar(cellValue)
    value = double(cellValue);
elseif ischar(cellValue) || (isstring(cellValue) && isscalar(cellValue))
    value = str2double(cellValue);
else
    value = NaN;
end
end

function source = m8DemoSource()
[ph, th] = meshgrid(0:5:355, 0:5:180);
power = 0.015 + (0.5 + 0.5 * sind(th) .* cosd(ph)).^5;
eth = sqrt(power) .* exp(1i * deg2rad(30 * sind(th)));
eph = -0.55i * eth;
data = m8Numeric([th(:), ph(:), real(eth(:)), imag(eth(:)), real(eph(:)), imag(eph(:))], 'complex');
source = m8Source(data, 'Analytic demonstration (not measured)', m8Options(struct()));
source.Metadata{1}.Notes = 'Synthetic lobe. Relative field levels; no absolute-gain or efficiency claim.';
end

function pattern = m8Fixture(kind)
[ph, th] = meshgrid(0:30:330, 0:30:180);
options = m8Options(struct());
options.AbsoluteGain = true;
if strcmp(kind, 'gain')
    data = m8Numeric([th(:), ph(:), zeros(numel(th), 1)], 'gain');
else
    eth = ones(size(th)); eph = -1i * ones(size(th));
    data = m8Numeric([th(:), ph(:), real(eth(:)), imag(eth(:)), real(eph(:)), imag(eph(:))], 'complex');
end
source = m8Source(data, 'Test fixture', options);
pattern = m8Canonical(source.Blocks{1}, source.Metadata{1});
end

function m8TestWeights()
pattern = m8Fixture('gain');
assert(abs(sum(pattern.ThetaWeight) * sum(pattern.PhiWeight) - 4 * pi) < 1e-12);
end

function m8TestPartial()
pattern = m8Fixture('gain');
data = m8PrimitiveTable(pattern);
partial = m8Canonical(data(data.Theta <= 90, :), pattern.Meta);
assert(~partial.FullSphere);
assert(abs(sum(partial.ThetaWeight) * sum(partial.PhiWeight) - 2 * pi) < 1e-12);
metrics = m8Metrics(partial);
assert(isnan(metrics.EfficiencyPct) && isnan(metrics.DirectivityDB));
resampled = m8Resample(partial, 15, 'cartesian');
assert(max(resampled.Theta) == 90);
end

function m8TestPrecision()
pattern = m8Fixture('field');
pattern.Eth(:) = complex(1.234567891234e-9, 4.567891234e-12);
data = m8PrimitiveTable(pattern);
rebuilt = m8Canonical(data, pattern.Meta);
assert(isequal(pattern.Eth, rebuilt.Eth));
end

function m8TestDuplicates()
pattern = m8Fixture('gain');
data = m8PrimitiveTable(pattern);
duplicate = data(data.Phi == 0, :); duplicate.Phi(:) = 360;
rebuilt = m8Canonical([data; duplicate], pattern.Meta);
assert(isequal(rebuilt.Gain, pattern.Gain));
duplicate.Gain_dB(1) = 1;
identifier = '';
try
    m8Canonical([data; duplicate], pattern.Meta);
catch exception
    identifier = exception.identifier;
end
assert(strcmp(identifier, 'APAT:DuplicateConflict'));
fieldPattern = m8Fixture('field');
fieldData = m8PrimitiveTable(fieldPattern);
fieldSeam = fieldData(fieldData.Phi == 0, :);
fieldSeam.Phi(:) = 360;
fieldSeam.Im_Eth(1) = 4 * eps(1);
rebuilt = m8Canonical([fieldData; fieldSeam], fieldPattern.Meta);
assert(isequal(rebuilt.Eth, fieldPattern.Eth));
end

function m8TestCoverage()
[actual, distribution] = APAT_v3_M8_35.coverage([0; 0; 10], [1; 2; 1], [-1; 0; 10]);
assert(isequal(actual, [100; 25; 0]));
assert(m8Evaluate(distribution, 0) == 25);
end

function m8TestRandomCoverage()
state = rng; cleanup = onCleanup(@() rng(state)); %#ok<NASGU>
rng(18);
gain = round(randn(300, 1) * 10);
weights = rand(300, 1); mask = rand(300, 1) > 0.2;
thresholds = [-Inf; (-30:0.25:30).'; Inf; NaN];
actual = APAT_v3_M8_35.coverage(gain, weights, thresholds, mask);
for k = 1:numel(thresholds) - 1
    expected = 100 * sum(weights(mask & gain > thresholds(k))) / sum(weights(mask));
    assert(abs(actual(k) - expected) < 1e-10);
end
assert(isnan(actual(end)));
end

function m8TestEmpty()
actual = APAT_v3_M8_35.coverage([1; 2], [0; 0], [0; 1]);
assert(all(isnan(actual)));
end

function m8TestZeroPower()
actual = APAT_v3_M8_35.coverage([-Inf; 0], [1; 1], [-Inf; -100; 0]);
assert(isequal(actual, [50; 50; 0]));
end

function m8TestLoss()
gain = [-8; -2; 2; 4]; weights = [1; 3; 2; 1]; threshold = (-12:12).';
first = APAT_v3_M8_35.coverage(gain + 7, weights, threshold);
second = APAT_v3_M8_35.coverage(gain, weights, threshold - 7);
assert(isequal(first, second));
end

function m8TestCircular()
[right, left] = m8Circular(1, -1i);
assert(abs(right - sqrt(2)) < 1e-14 && left == 0);
eth = (right + left) / sqrt(2); eph = (right - left) / (1i * sqrt(2));
assert(abs(eth - 1) < 1e-14 && abs(eph + 1i) < 1e-14);
end

function m8TestPLF()
pattern = m8Fixture('field');
cfg = m8Options(struct('RxMode', 'RHCP'));
value = m8Column(pattern, 'PLF_dB', cfg);
assert(max(abs(value), [], 'all') < 1e-12);
cfg.RxMode = 'LHCP'; value = m8Column(pattern, 'PLF_dB', cfg);
assert(all(value == -Inf, 'all'));
pattern.Eth(2, 2) = NaN;
value = m8Column(pattern, 'PLF_dB', cfg);
assert(isnan(value(2, 2)));
end

function m8TestResample()
pattern = m8Fixture('gain');
pattern.Gain(:, 1) = 0; pattern.Gain(:, 2) = 10;
target = m8Resample(pattern, 15, 'cartesian');
assert(abs(target.Gain(3, 2) - 10 * log10(5.5)) < 1e-12);
coarse = m8Resample(pattern, 60, 'cartesian');
assert(isequal(coarse.Gain, pattern.Gain(1:2:end, 1:2:end)));
identifier = '';
try
    m8Resample(pattern, 1e-12, 'cartesian');
catch exception
    identifier = exception.identifier;
end
assert(strcmp(identifier, 'APAT:GridLimit'));
end

function m8TestHPBW()
angle = (0:360).'; relative = mod(angle + 180, 360) - 180;
gain = -10 * log10(2) * (relative / 10).^2;
assert(abs(m8HPBW(angle, gain, true) - 20) < 1e-10);
end

function m8TestIsotropic()
metrics = m8Metrics(m8Fixture('gain'));
assert(abs(metrics.DirectivityDB) < 1e-12);
assert(abs(metrics.EfficiencyPct - 100) < 1e-10);
assert(metrics.FrontBackDB == 0);
end

function m8TestCSV()
path = [tempname '.csv']; cleanup = onCleanup(@() delete(path)); %#ok<NASGU>
pattern = m8Fixture('gain');
data = m8PrimitiveTable(pattern); data.Unused = NaN(height(data), 1);
writetable(data, path);
source = m8Read(path, m8Options(struct()));
assert(height(source.Blocks{1}) == height(data));
end

function m8TestFFD()
path = [tempname '.ffd']; cleanup = onCleanup(@() delete(path)); %#ok<NASGU>
file = fopen(path, 'wt');
assert(file >= 0, 'Cannot create fixture.');
fprintf(file, '0 180 2\n0 180 2\nFrequencies 1\nFrequency 1e9\n1 0 0 0\n2 0 0 0\n3 0 0 0\n4 0 0 0\n');
fclose(file);
source = m8Read(path, m8Options(struct('FFDOrder', 'theta-fast')));
pattern = m8Canonical(source.Blocks{1}, source.Metadata{1});
assert(isequal(real(pattern.Eth), [1 3; 2 4]));
source = m8Read(path, m8Options(struct('FFDOrder', 'phi-fast')));
pattern = m8Canonical(source.Blocks{1}, source.Metadata{1});
assert(isequal(real(pattern.Eth), [1 2; 3 4]));
end

function m8TestPeriodicTarget()
target = m8Resample(m8Fixture('gain'), 7, 'cartesian');
assert(target.PeriodicPhi && target.FullSphere);
assert(target.Theta(end) == 180);
assert(abs(sum(target.ThetaWeight) * sum(target.PhiWeight) - 4 * pi) < 1e-12);
end

function m8TestRawPeak()
pattern = m8Fixture('gain'); pattern.Gain(3, 3) = 80;
metrics = m8Metrics(pattern);
assert(metrics.PeakDB == 80);
end

function m8TestAmbiguousPhase()
pattern = m8Fixture('field');
pattern.Eth(:, 1) = 1; pattern.Eth(:, 2) = -1;
target = m8Resample(pattern, 15, 'power-phase');
assert(isnan(target.Eth(3, 2)));
end