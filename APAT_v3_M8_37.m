classdef APAT_v3_M8_37 < handle %AST %1450-lines
    % APAT M8 candidate: a grid-native antenna-pattern application.
    % MATLAB R2023b or newer. No optional toolbox is intentionally used.
    %
    % GUI:      app = APAT_v3_M8;
    % Headless: app = APAT_v3_M8("headless");
    % Import:   app.import(T, Unit="dBi");
    % Coverage: c = app.coverage((-30:0.5:10)', Loss=-2);
    % Tests:    results = runtests("APAT_M8_tests.m");
    %
    % This is a scoped replacement, not a verified M7-compatible release.
    % See APAT_M8_CHANGES.md for reader, UI, and verification limitations.

    properties (SetAccess = private)
        Pattern = struct([])
        Geometry = struct([])
        Revision = uint64(0)
        UIFigure = []
    end

    properties (Access = private)
        Original = struct([])
        Columns
        Distributions
        Controls = struct()
        Axes = struct()
        Graphics = struct()
        Busy = false
    end

    methods
        function app = APAT_v3_M8_37(mode)
            app.clearCaches();
            if nargin > 0 && string(mode) == "headless"
                return
            end
            app.createUI();
            [theta, phi] = ndgrid((0:2:180)', 0:2:358);
            gain = 8 + 10*log10(0.01 + sind(theta).^6 .* ...
                ((1 + cosd(phi))/2).^4);
            demo = table(theta(:), phi(:), gain(:), ...
                'VariableNames', {'Theta','Phi','Gain_dB'});
            app.import(demo, Name="Synthetic directional pattern");
            if nargin > 0
                app.run(@() app.open(string(mode)));
            end
        end

        function delete(app)
            if ~isempty(app.UIFigure) && isgraphics(app.UIFigure)
                app.UIFigure.CloseRequestFcn = [];
                delete(app.UIFigure);
            end
        end

        function import(app, data, options)
            arguments
                app
                data table
                options.Unit (1,1) string = "dB"
                options.ThetaConvention (1,1) string = "polar"
                options.PhiPeriodic (1,1) string = "auto"
                options.Name (1,1) string = "Imported pattern"
                options.GainColumns string = strings(0)
            end
            candidate = APAT_v3_M8_37.canonicalize(data, options);
            geometry = APAT_v3_M8_37.geometry(candidate);
            app.commit(candidate, geometry, true);
        end

        function open(app, path)
            arguments
                app
                path (1,1) string
            end
            if ~isfile(path)
                error('APAT:MissingFile', 'File does not exist: %s', path);
            end
            [~, name, extension] = fileparts(path);
            supported = [".csv",".tsv",".txt",".dat",".xlsx",".xls"];
            if ~ismember(lower(extension), supported)
                error('APAT:UnsupportedFormat', ...
                    ['This candidate imports headed long-form tables. ', ...
                    'Convert proprietary formats to the documented CSV schema.']);
            end
            data = readtable(path, 'VariableNamingRule', 'preserve');
            unit = "dB";
            if ismember('Gain_dBi', data.Properties.VariableNames)
                unit = "dBi";
            end
            if isfile(path + ".json")
                metadata = jsondecode(fileread(path + ".json"));
                if isfield(metadata,'Unit')
                    unit = string(metadata.Unit);
                end
            end
            app.import(data, Unit=unit, Name=name + extension);
        end

        function resample(app, step, method)
            arguments
                app
                step (1,1) double {mustBeReal,mustBeFinite,mustBePositive} = 1
                method (1,1) string = "cartesian"
            end
            app.requirePattern();
            mustBeMember(method, ["cartesian","power-phase"]);
            source = app.Original;
            thetaCount = ceil((source.Theta(end)-source.Theta(1))/step)+1;
            phiCount = ceil((source.Phi(end)-source.Phi(1))/step)+1;
            if source.Meta.PhiPeriodic
                phiCount = round(360/step);
            end
            if ~isfinite(thetaCount*phiCount) || thetaCount*phiCount > 2e6
                error('APAT:GridBudget', 'Requested grid exceeds two million samples.');
            end
            theta = APAT_v3_M8_37.boundedAxis(source.Theta, step);
            if source.Meta.PhiPeriodic
                count = round(360/step);
                if count < 2 || abs(count*step - 360) > 1e-8
                    error('APAT:PeriodicStep', 'The phi step must divide 360 degrees.');
                end
                phi = source.Phi(1) + (0:count-1)'*step;
            else
                phi = APAT_v3_M8_37.boundedAxis(source.Phi, step);
            end
            candidate = source;
            if source.HasFields
                candidate.Eth = APAT_v3_M8_37.interpolateField( ...
                    source, source.Eth, theta, phi, method);
                candidate.Eph = APAT_v3_M8_37.interpolateField( ...
                    source, source.Eph, theta, phi, method);
            else
                for name = string(fieldnames(source.Gains))'
                    candidate.Gains.(name) = APAT_v3_M8_37.interpolateGain( ...
                        source, source.Gains.(name), theta, phi);
                end
            end
            [canonicalPhi, order] = sort(mod(phi, 360));
            if source.HasFields
                candidate.Eth = candidate.Eth(:, order);
                candidate.Eph = candidate.Eph(:, order);
            else
                for name = string(fieldnames(candidate.Gains))'
                    candidate.Gains.(name) = candidate.Gains.(name)(:, order);
                end
            end
            candidate.Theta = theta;
            candidate.Phi = canonicalPhi;
            candidate.Meta.Resampling = method + ", " + step + " deg";
            geometry = APAT_v3_M8_37.geometry(candidate);
            app.commit(candidate, geometry, false);
        end

        function resetGrid(app)
            app.requirePattern();
            app.commit(app.Original, APAT_v3_M8_37.geometry(app.Original), false);
        end

        function values = column(app, name, options)
            arguments
                app
                name (1,1) string = "E_Total_dB"
                options.Loss (1,1) double {mustBeReal,mustBeFinite} = 0
                options.Rx (1,1) string = "RHCP"
                options.RxAR (1,1) double {mustBeReal,mustBeFinite,mustBeNonnegative} = 0
                options.RxTilt (1,1) double {mustBeReal,mustBeFinite} = 0
                options.Pt_dBW (1,1) double {mustBeReal,mustBeFinite} = 0
                options.Distance_m (1,1) double {mustBeReal,mustBeFinite,mustBePositive} = 1
            end
            app.requirePattern();
            mustBeMember(options.Rx, ["RHCP","LHCP","Theta","Phi"]);
            if options.RxAR > 120
                error('APAT:RxRatio', 'Receiver axial ratio must not exceed 120 dB.');
            end
            linkNames = ["EIRP_dBW","PFD_Wm2","E_RMS_Vm"];
            if ismember(name, linkNames)
                if app.Pattern.Meta.Unit ~= "dBi"
                    error('APAT:Calibration', 'Link quantities require calibrated dBi data.');
                end
                eirp = app.column("E_Total_dB", Loss=options.Loss) + options.Pt_dBW;
                switch name
                    case "EIRP_dBW"
                        values = eirp;
                    case "PFD_Wm2"
                        values = 10.^((eirp - 10*log10(4*pi) - ...
                            20*log10(options.Distance_m))/10);
                    case "E_RMS_Vm"
                        values = 10.^((eirp + 10*log10(30) - ...
                            20*log10(options.Distance_m))/20);
                end
                return
            end
            key = char(name);
            if ismember(name, ["PLF_dB","Gain_PolCorrected_dB"])
                key = sprintf('%s|%s|%.17g|%.17g', ...
                    name, options.Rx, options.RxAR, options.RxTilt);
            end
            if isKey(app.Columns, key)
                values = app.Columns(key);
            else
                values = app.baseColumn(name, options);
                app.Columns(key) = values;
            end
            if app.isGain(name)
                values = values + options.Loss;
            end
        end

        function result = metrics(app, loss)
            arguments
                app
                loss (1,1) double {mustBeReal,mustBeFinite} = 0
            end
            app.requirePattern();
            if isKey(app.Columns, '__metrics')
                result = app.Columns('__metrics');
            else
                gain = app.column("E_Total_dB");
                peak = APAT_v3_M8_37.peak(gain);
                result = struct('PeakGain_dB',peak.Value, ...
                    'PeakTheta_deg',NaN,'PeakPhi_deg',NaN, ...
                    'Directivity_dB',NaN,'Efficiency_pct',NaN, ...
                    'FrontBack_dB',NaN,'HPBW_E_deg',NaN, ...
                    'HPBW_H_deg',NaN,'AxialRatio_dB',NaN);
                if isfinite(peak.Value)
                    [row, col] = ind2sub(size(gain), peak.Index);
                    result.PeakTheta_deg = app.Pattern.Theta(row);
                    result.PeakPhi_deg = app.Pattern.Phi(col);
                    complete = app.Geometry.IsFullSphere && ~any(isnan(gain(:)));
                    if complete
                        normalized = 10.^((gain - peak.Value)/10);
                        integral = app.Geometry.WeightTheta' * ...
                            normalized * app.Geometry.WeightPhi;
                        result.Directivity_dB = 10*log10(4*pi/integral);
                        if app.Pattern.Meta.Unit == "dBi"
                            result.Efficiency_pct = 100*10.^ ...
                                ((peak.Value - result.Directivity_dB)/10);
                        end
                        back = APAT_v3_M8_37.interpolateGain(app.Pattern, gain, ...
                            180-result.PeakTheta_deg, result.PeakPhi_deg+180);
                        result.FrontBack_dB = peak.Value - back;
                        [eCut, hCut] = app.principalCuts(gain);
                        result.HPBW_E_deg = APAT_v3_M8_37.hpbw( ...
                            eCut.Angle, eCut.Value, eCut.IsClosed);
                        result.HPBW_H_deg = APAT_v3_M8_37.hpbw( ...
                            hCut.Angle, hCut.Value, hCut.IsClosed);
                    end
                    if app.Pattern.HasFields
                        ar = app.column("AR_dB");
                        result.AxialRatio_dB = ar(peak.Index);
                    end
                elseif peak.Value == -Inf && app.Geometry.IsFullSphere && ...
                        ~any(isnan(gain(:))) && app.Pattern.Meta.Unit == "dBi"
                    result.Efficiency_pct = 0;
                end
                app.Columns('__metrics') = result;
            end
            result.PeakGain_dB = result.PeakGain_dB + loss;
            result.Efficiency_pct = result.Efficiency_pct*10^(loss/10);
        end

        function result = cut(app, type, value, component, loss)
            arguments
                app
                type (1,1) string = "Theta"
                value (1,1) double {mustBeReal,mustBeFinite} = 0
                component (1,1) string = "E_Total_dB"
                loss (1,1) double {mustBeReal,mustBeFinite} = 0
            end
            mustBeMember(type, ["Theta","Phi"]);
            values = app.column(component, Loss=loss);
            result = APAT_v3_M8_37.extractCut(app.Pattern, values, type, value);
        end

        function coverage = coverage(app, thresholds, options)
            arguments
                app
                thresholds double
                options.Component (1,1) string = "E_Total_dB"
                options.Loss (1,1) double {mustBeReal,mustBeFinite} = 0
                options.Cone double = []
                options.Rx (1,1) string = "RHCP"
                options.RxAR (1,1) double {mustBeReal,mustBeFinite,mustBeNonnegative} = 0
                options.RxTilt (1,1) double {mustBeReal,mustBeFinite} = 0
            end
            app.requirePattern();
            if ~app.isGain(options.Component)
                error('APAT:CoverageQuantity', 'Coverage requires a gain-like dB component.');
            end
            APAT_v3_M8_37.validateCone(options.Cone);
            key = sprintf('%s|%s|%.17g|%.17g|%s', options.Component, ...
                options.Rx, options.RxAR, options.RxTilt, mat2str(options.Cone, 17));
            if ~isKey(app.Distributions, key)
                values = app.column(options.Component, Rx=options.Rx, ...
                    RxAR=options.RxAR, RxTilt=options.RxTilt);
                weights = app.Geometry.WeightTheta * app.Geometry.WeightPhi';
                if ~isempty(options.Cone)
                    mask = APAT_v3_M8_37.coneMask(app.Pattern, options.Cone);
                    weights(~mask) = 0;
                end
                app.Distributions(key) = APAT_v3_M8_37.distribution(values, weights);
            end
            coverage = APAT_v3_M8_37.evaluateDistribution( ...
                app.Distributions(key), thresholds-options.Loss);
        end

        function output = exportTable(app, options)
            arguments
                app
                options.Loss (1,1) double {mustBeReal,mustBeFinite} = 0
            end
            app.requirePattern();
            [theta, phi] = ndgrid(app.Pattern.Theta, app.Pattern.Phi);
            output = table(theta(:), phi(:), 'VariableNames', {'Theta','Phi'});
            for name = app.componentNames()
                values = app.column(name, Loss=options.Loss);
                output.(name) = values(:);
            end
            if app.Pattern.HasFields
                scale = 10^(options.Loss/20);
                output.Re_Eth = real(app.Pattern.Eth(:))*scale;
                output.Im_Eth = imag(app.Pattern.Eth(:))*scale;
                output.Re_Eph = real(app.Pattern.Eph(:))*scale;
                output.Im_Eph = imag(app.Pattern.Eph(:))*scale;
            end
            output.Properties.UserData = app.Pattern.Meta;
        end
    end

    methods (Static)
        function coverage = weightedCoverage(values, weights, thresholds)
            distribution = APAT_v3_M8_37.distribution(values, weights);
            coverage = APAT_v3_M8_37.evaluateDistribution(distribution, thresholds);
        end

        function geometry = geometry(pattern)
            theta = pattern.Theta(:);
            phi = pattern.Phi(:);
            thetaEdges = [theta(1); (theta(1:end-1)+theta(2:end))/2; theta(end)];
            weightTheta = cosd(thetaEdges(1:end-1)) - cosd(thetaEdges(2:end));
            if pattern.Meta.PhiPeriodic
                extended = [phi(end)-360; phi; phi(1)+360];
                weightPhi = deg2rad((extended(3:end)-extended(1:end-2))/2);
            else
                edges = [phi(1); (phi(1:end-1)+phi(2:end))/2; phi(end)];
                weightPhi = deg2rad(diff(edges));
            end
            geometry = struct('WeightTheta',weightTheta, ...
                'WeightPhi',weightPhi, ...
                'SolidAngle_sr',sum(weightTheta)*sum(weightPhi), ...
                'IsFullSphere',pattern.Meta.PhiPeriodic && ...
                abs(theta(1)) < 1e-9 && abs(theta(end)-180) < 1e-9);
        end

        function result = hpbw(angleDeg, gain, closed)
            arguments
                angleDeg double
                gain double
                closed (1,1) logical = true
            end
            result = NaN;
            if numel(angleDeg) ~= numel(gain) || numel(gain) < 3
                return
            end
            angleDeg = angleDeg(:);
            gain = gain(:);
            if closed
                angleDeg = mod(angleDeg, 360);
            end
            [angleDeg, indices] = unique(angleDeg, 'sorted');
            gain = gain(indices);
            peak = APAT_v3_M8_37.peak(gain);
            if ~isfinite(peak.Value)
                return
            end
            center = peak.Index;
            if closed
                center = center + numel(gain);
                angleDeg = [angleDeg-360; angleDeg; angleDeg+360];
                gain = repmat(gain, 3, 1);
            end
            half = peak.Value - 10*log10(2);
            left = center;
            right = center;
            while left > 1 && gain(left) > half
                left = left-1;
            end
            while right < numel(gain) && gain(right) > half
                right = right+1;
            end
            if left == center || right == center || ...
                    ~isfinite(gain(left)) || ~isfinite(gain(right)) || ...
                    gain(left) > half || gain(right) > half
                return
            end
            lower = APAT_v3_M8_37.crossing(angleDeg(left:left+1), gain(left:left+1), half);
            upper = APAT_v3_M8_37.crossing(angleDeg(right-1:right), gain(right-1:right), half);
            width = upper-lower;
            if width > 0 && width <= 360
                result = width;
            end
        end
    end

    methods (Static, Access = private)
        function pattern = canonicalize(data, options)
            mustBeMember(options.Unit, ["dB","dBi"]);
            mustBeMember(options.ThetaConvention, ["polar","elevation"]);
            mustBeMember(options.PhiPeriodic, ["auto","true","false"]);
            names = string(data.Properties.VariableNames);
            if ~all(ismember(["Theta","Phi"], names)) || isempty(data)
                error('APAT:Schema', 'A nonempty table with Theta and Phi columns is required.');
            end
            theta = double(data.Theta);
            phiRaw = double(data.Phi);
            if ~iscolumn(theta) || ~iscolumn(phiRaw) || ...
                    ~isreal(theta) || ~isreal(phiRaw) || ...
                    any(~isfinite(theta)) || any(~isfinite(phiRaw))
                error('APAT:Angles', 'Angular coordinates must be finite real numbers.');
            end
            if options.ThetaConvention == "elevation"
                if any(theta < -90 | theta > 90)
                    error('APAT:Angles', 'Elevation must be in [-90,90] degrees.');
                end
                theta = 90-theta;
            end
            if any(theta < -1e-9 | theta > 180+1e-9)
                error('APAT:Angles', 'Polar theta must be in [0,180] degrees.');
            end
            theta = round(min(max(theta, 0), 180), 9);
            phi = mod(round(phiRaw, 9), 360);
            [directions, keep, groups] = unique([theta,phi], 'rows', 'sorted');
            thetaAxis = unique(theta);
            phiAxis = unique(phi);
            if numel(thetaAxis) < 2 || numel(phiAxis) < 2
                error('APAT:Grid', 'A pattern requires at least two samples on each axis.');
            end
            if numel(thetaAxis)*numel(phiAxis) ~= size(directions,1)
                error('APAT:MissingCell', 'The angular grid is incomplete; no cells are fabricated.');
            end
            [~, ti] = ismember(theta(keep), thetaAxis);
            [~, pj] = ismember(phi(keep), phiAxis);
            shape = [numel(thetaAxis),numel(phiAxis)];
            linear = sub2ind(shape, ti, pj);
            gaps = diff(phiAxis);
            uniformCycle = max(abs(gaps-median(gaps))) < 1e-8 && ...
                abs(numel(phiAxis)*median(gaps)-360) < 1e-8;
            closingTheta = unique(theta(abs(phiRaw-360) < 1e-9));
            openingTheta = unique(theta(abs(phiRaw) < 1e-9));
            closedInSource = isequal(closingTheta,thetaAxis) && ...
                isequal(openingTheta,thetaAxis);
            periodic = uniformCycle || closedInSource;
            if options.PhiPeriodic ~= "auto"
                periodic = options.PhiPeriodic == "true";
            end
            if ~periodic && max(gaps) > 180
                error('APAT:PartialSeam', ...
                    'A partial grid crossing the phi seam needs an explicit domain adapter.');
            end
            hasComplex = all(ismember(["Eth","Eph"], names));
            fieldNames = ["Re_Eth","Im_Eth","Re_Eph","Im_Eph"];
            hasFields = hasComplex || all(ismember(fieldNames, names));
            meta = struct('Name',options.Name,'Unit',options.Unit, ...
                'ThetaConvention',options.ThetaConvention, ...
                'PhiPeriodic',periodic,'Resampling',"native", ...
                'PhaseConvention',"exp(+j*omega*t); outward theta/phi basis");
            pattern = struct('Theta',thetaAxis,'Phi',phiAxis, ...
                'HasFields',hasFields,'Eth',[],'Eph',[], ...
                'Gains',struct(),'Meta',meta);
            if hasFields
                if hasComplex
                    eth = double(data.Eth);
                    eph = double(data.Eph);
                else
                    eth = complex(double(data.Re_Eth), double(data.Im_Eth));
                    eph = complex(double(data.Re_Eph), double(data.Im_Eph));
                end
                pattern.Eth = APAT_v3_M8_37.pack(eth, keep, groups, linear, shape, true);
                pattern.Eph = APAT_v3_M8_37.pack(eph, keep, groups, linear, shape, true);
            else
                gainNames = options.GainColumns;
                if isempty(gainNames)
                    gainNames = names(ismember(names, ["Gain_dBi","Gain_dB","E_Total_dB"]));
                end
                if isempty(gainNames) || ~all(ismember(gainNames, names))
                    error('APAT:Schema', ...
                        'Supply complex fields, Gain_dB/Gain_dBi, or explicit GainColumns.');
                end
                for name = reshape(gainNames, 1, [])
                    if ~isvarname(name)
                        error('APAT:ColumnName', 'Gain column names must be valid identifiers.');
                    end
                    pattern.Gains.(name) = APAT_v3_M8_37.pack( ...
                        double(data.(name)), keep, groups, linear, shape, false);
                end
                pattern.Meta.TotalColumn = gainNames(1);
            end
        end

        function grid = pack(values, keep, groups, linear, shape, complexAllowed)
            if ~isvector(values) || numel(values) ~= numel(groups)
                error('APAT:ColumnShape', 'Every quantity must be one value per direction.');
            end
            values = values(:);
            if complexAllowed
                invalid = isinf(real(values)) | isinf(imag(values));
            else
                invalid = ~isreal(values) | values == Inf;
            end
            if any(invalid)
                error('APAT:Values', 'Infinite fields, complex gains, and +Inf gains are invalid.');
            end
            reference = values(keep);
            repeated = reference(groups);
            tolerance = 1e-10*max(abs(values), abs(repeated));
            same = values == repeated | (isnan(values) & isnan(repeated)) | ...
                (isfinite(values) & isfinite(repeated) & abs(values-repeated) <= tolerance);
            if ~all(same)
                error('APAT:DuplicateConflict', 'Duplicate directions contain conflicting values.');
            end
            grid = nan(shape, 'like', values);
            grid(linear) = values(keep);
        end

        function axis = boundedAxis(sourceAxis, step)
            axis = (sourceAxis(1):step:sourceAxis(end))';
            if abs(axis(end)-sourceAxis(end)) > 1e-9
                axis(end+1) = sourceAxis(end);
            end
        end

        function [isSubset, ti, pj] = nativeIndices(pattern, theta, phi)
            [hasTheta, ti] = ismember(round(theta(:),9), round(pattern.Theta,9));
            [hasPhi, pj] = ismember(mod(round(phi(:),9),360), round(pattern.Phi,9));
            isSubset = all(hasTheta) && all(hasPhi);
        end

        function values = interpolate(pattern, source, theta, phi)
            theta = theta(:);
            phi = phi(:);
            [isSubset, ti, pj] = APAT_v3_M8_37.nativeIndices(pattern, theta, phi);
            if isSubset
                values = source(ti, pj);
                return
            end
            sourcePhi = pattern.Phi;
            if pattern.Meta.PhiPeriodic
                phi = mod(phi-sourcePhi(1),360)+sourcePhi(1);
                sourcePhi = [sourcePhi; sourcePhi(1)+360];
                source = [source,source(:,1)];
            end
            interpolant = griddedInterpolant( ...
                {pattern.Theta,sourcePhi}, source, 'linear', 'none');
            values = interpolant({theta,phi});
        end

        function values = interpolateGain(pattern, gain, theta, phi)
            [isSubset, ti, pj] = APAT_v3_M8_37.nativeIndices(pattern, theta, phi);
            if isSubset
                values = gain(ti,pj);
                return
            end
            peak = APAT_v3_M8_37.peak(gain);
            if peak.Value == -Inf
                peak.Value = 0;
            end
            if isnan(peak.Value)
                values = NaN(numel(theta),numel(phi));
                return
            end
            linear = 10.^((gain-peak.Value)/10);
            values = APAT_v3_M8_37.interpolate(pattern, linear, theta, phi);
            values = peak.Value + 10*log10(values);
        end

        function values = interpolateField(pattern, field, theta, phi, method)
            [isSubset, ti, pj] = APAT_v3_M8_37.nativeIndices(pattern, theta, phi);
            if isSubset
                values = field(ti,pj);
                return
            end
            if method == "cartesian"
                values = APAT_v3_M8_37.interpolate(pattern, field, theta, phi);
                return
            end
            amplitude = abs(field);
            scale = max(amplitude(:), [], 'omitnan');
            if isempty(scale) || ~isfinite(scale) || scale == 0
                values = APAT_v3_M8_37.interpolate(pattern, field, theta, phi);
                return
            end
            power = (amplitude/scale).^2;
            phasor = field./amplitude;
            phasor(amplitude == 0) = 0;
            power = APAT_v3_M8_37.interpolate(pattern, power, theta, phi);
            phasor = APAT_v3_M8_37.interpolate(pattern, phasor, theta, phi);
            ambiguous = abs(phasor) < 1e-12 & power > 0;
            values = scale*sqrt(max(power,0)).*exp(1i*angle(phasor));
            values(ambiguous) = NaN;
            if any(ambiguous(:))
                warning('APAT:PhaseAmbiguity', ...
                    'Opposing phasors produced missing samples; refine the source grid.');
            end
        end

        function [right, left] = circular(eth, eph)
            right = eth/sqrt(2) + 1i*eph/sqrt(2);
            left = eth/sqrt(2) - 1i*eph/sqrt(2);
        end

        function peak = peak(gain)
            valid = ~isnan(gain(:));
            peak = struct('Value',NaN,'Index',1);
            if any(valid)
                candidates = find(valid);
                [peak.Value, index] = max(gain(candidates));
                peak.Index = candidates(index);
            end
        end

        function distribution = distribution(values, weights)
            if numel(values) ~= numel(weights) || ~isreal(values) || ~isreal(weights)
                error('APAT:CoverageShape', 'Real values and weights must have equal sample counts.');
            end
            values = double(values(:));
            weights = double(weights(:));
            if any(weights < 0 | ~isfinite(weights)) || any(values == Inf)
                error('APAT:CoverageValues', 'Weights must be finite/nonnegative; +Inf gain is invalid.');
            end
            valid = ~isnan(values) & weights > 0;
            [levels, ~, bins] = unique(values(valid), 'sorted');
            masses = zeros(0,1);
            if ~isempty(levels)
                regionWeights = weights(valid);
                regionWeights = regionWeights/max(regionWeights);
                masses = accumarray(bins, regionWeights, [numel(levels),1]);
            end
            distribution = struct('Levels',levels, ...
                'Tail',[flipud(cumsum(flipud(masses)));0], ...
                'Weight',sum(masses));
        end

        function coverage = evaluateDistribution(distribution, thresholds)
            if ~isreal(thresholds)
                error('APAT:Threshold', 'Thresholds must be real.');
            end
            coverage = nan(size(thresholds));
            if distribution.Weight <= 0
                return
            end
            levels = distribution.Levels;
            for query = 1:numel(thresholds)
                threshold = thresholds(query);
                if isnan(threshold)
                    continue
                end
                % Upper bound implements strict >, including repeated levels.
                low = 1;
                high = numel(levels)+1;
                while low < high
                    middle = floor((low+high)/2);
                    if levels(middle) <= threshold
                        low = middle+1;
                    else
                        high = middle;
                    end
                end
                coverage(query) = 100*distribution.Tail(low)/distribution.Weight;
            end
        end

        function validateCone(cone)
            if isempty(cone)
                return
            end
            if numel(cone) ~= 3 || ~isreal(cone) || any(~isfinite(cone)) || ...
                    cone(1) < 0 || cone(1) > 180 || cone(3) < 0 || cone(3) > 180
                error('APAT:Cone', 'Cone is [polar theta, phi, half-angle] in degrees.');
            end
        end

        function mask = coneMask(pattern, cone)
            similarity = cosd(pattern.Theta)*cosd(cone(1)) + ...
                sind(pattern.Theta)*sind(cone(1)).*cosd(pattern.Phi'-cone(2));
            mask = similarity >= cosd(cone(3))-1e-12;
        end

        function result = extractCut(pattern, grid, type, requested)
            closed = false;
            if type == "Phi"
                [~, index] = min(abs(pattern.Theta-requested));
                fixed = pattern.Theta(index);
                angles = pattern.Phi;
                values = grid(index,:)';
                closed = pattern.Meta.PhiPeriodic;
            else
                distance = abs(mod(pattern.Phi-requested+180,360)-180);
                [~, index] = min(distance);
                fixed = pattern.Phi(index);
                angles = pattern.Theta;
                values = grid(:,index);
                opposite = abs(mod(pattern.Phi-fixed,360)-180);
                [difference, other] = min(opposite);
                fullTheta = abs(angles(1)) < 1e-9 && abs(angles(end)-180) < 1e-9;
                if difference < 1e-8 && fullTheta
                    angles = [angles;360-flipud(angles(2:end-1))];
                    values = [values;flipud(grid(2:end-1,other))];
                    closed = true;
                end
            end
            result = struct('Angle',angles,'Value',values, ...
                'Fixed',fixed,'Requested',requested,'Type',type,'IsClosed',closed);
        end

        function value = crossing(angles, gains, target)
            if gains(1) == gains(2)
                value = NaN;
            else
                value = angles(1) + diff(angles)*(target-gains(1))/diff(gains);
            end
        end

        function handle = place(factory, parent, row, column, varargin)
            handle = factory(parent, varargin{:});
            handle.Layout.Row = row;
            handle.Layout.Column = column;
        end
    end

    methods (Access = private)
        function requirePattern(app)
            if isempty(app.Pattern)
                error('APAT:NoPattern', 'Import a pattern first.');
            end
        end

        function clearCaches(app)
            app.Columns = containers.Map('KeyType','char','ValueType','any');
            app.Distributions = containers.Map('KeyType','char','ValueType','any');
        end

        function commit(app, candidate, geometry, replaceOriginal)
            % All validation/interpolation happens before any live state changes.
            app.Pattern = candidate;
            app.Geometry = geometry;
            if replaceOriginal
                app.Original = candidate;
            end
            app.Revision = app.Revision+1;
            app.clearCaches();
            if ~isempty(app.UIFigure) && isgraphics(app.UIFigure)
                previous = string(app.Controls.Component.Value);
                names = app.componentNames();
                app.Controls.Component.Items = cellstr(names);
                if ismember(previous, names)
                    app.Controls.Component.Value = char(previous);
                else
                    app.Controls.Component.Value = char(names(1));
                end
                app.render();
            end
        end

        function names = componentNames(app)
            if app.Pattern.HasFields
                names = ["E_Total_dB","E_TH_dB","E_PH_dB", ...
                    "E_RCP_dB","E_LCP_dB","AR_dB", ...
                    "PLF_dB","Gain_PolCorrected_dB"];
            else
                names = ["E_Total_dB",string(fieldnames(app.Pattern.Gains))'];
                names = unique(names, 'stable');
            end
        end

        function result = isGain(app, name)
            result = ismember(name, ["E_Total_dB","E_TH_dB","E_PH_dB", ...
                "E_RCP_dB","E_LCP_dB","Gain_PolCorrected_dB"]);
            if ~isempty(app.Pattern) && ~app.Pattern.HasFields
                result = result || isfield(app.Pattern.Gains, name);
            end
        end

        function values = baseColumn(app, name, options)
            pattern = app.Pattern;
            if ~pattern.HasFields
                if name == "E_Total_dB"
                    values = pattern.Gains.(pattern.Meta.TotalColumn);
                elseif isfield(pattern.Gains, name)
                    values = pattern.Gains.(name);
                else
                    error('APAT:Component', 'The source does not contain %s.', name);
                end
                return
            end
            eth = pattern.Eth;
            eph = pattern.Eph;
            magnitude = hypot(abs(eth),abs(eph));
            switch name
                case "E_Total_dB"
                    values = 20*log10(magnitude);
                case "E_TH_dB"
                    values = 20*log10(abs(eth));
                case "E_PH_dB"
                    values = 20*log10(abs(eph));
                case {"E_RCP_dB","E_LCP_dB","AR_dB"}
                    [right, left] = APAT_v3_M8_37.circular(eth, eph);
                    if name == "E_RCP_dB"
                        values = 20*log10(abs(right));
                    elseif name == "E_LCP_dB"
                        values = 20*log10(abs(left));
                    else
                        r = abs(right)./magnitude;
                        l = abs(left)./magnitude;
                        difference = r-l;
                        values = sign(difference).*20*log10((r+l)./abs(difference));
                        linear = abs(difference) <= eps*(r+l);
                        values(linear) = -100;
                        values(magnitude == 0) = NaN;
                    end
                case {"PLF_dB","Gain_PolCorrected_dB"}
                    if options.Rx == "Theta"
                        rx = [1;0];
                    elseif options.Rx == "Phi"
                        rx = [0;1];
                    else
                        ratio = 10^(options.RxAR/20);
                        sense = 2*(options.Rx == "RHCP")-1;
                        rx = [ratio;-1i*sense]/hypot(ratio,1);
                        rotation = [cosd(options.RxTilt),-sind(options.RxTilt); ...
                            sind(options.RxTilt),cosd(options.RxTilt)];
                        rx = rotation*rx;
                    end
                    normalizedTheta = eth./magnitude;
                    normalizedPhi = eph./magnitude;
                    coupling = abs(conj(rx(1))*normalizedTheta + conj(rx(2))*normalizedPhi);
                    values = 20*log10(min(coupling,1));
                    values(magnitude == 0 | isnan(magnitude)) = NaN;
                    if name == "Gain_PolCorrected_dB"
                        values = values + 20*log10(magnitude);
                    end
                otherwise
                    error('APAT:Component', 'Unknown component: %s', name);
            end
        end

        function [eCut, hCut] = principalCuts(app, gain)
            axesTheta = [0,180,90,90,90,90];
            axesPhi = [0,0,0,180,90,270];
            peak = APAT_v3_M8_37.peak(gain);
            normalized = 10.^((gain-peak.Value)/10);
            normalized(isnan(normalized)) = 0;
            weights = app.Geometry.WeightTheta * app.Geometry.WeightPhi';
            energy = zeros(1,6);
            for index = 1:6
                mask = APAT_v3_M8_37.coneMask(app.Pattern, ...
                    [axesTheta(index),axesPhi(index),45]);
                energy(index) = sum(normalized.*weights.*mask, 'all');
            end
            [~, axisIndex] = max(energy);
            eCut = APAT_v3_M8_37.extractCut(app.Pattern, gain, "Theta", axesPhi(axisIndex));
            if axesTheta(axisIndex) == 90
                hCut = APAT_v3_M8_37.extractCut(app.Pattern, gain, "Phi", 90);
            else
                hCut = APAT_v3_M8_37.extractCut(app.Pattern, gain, "Theta", 90);
            end
        end

        function config = readConfig(app)
            config = struct('Component',string(app.Controls.Component.Value), ...
                'Loss',app.Controls.Loss.Value, ...
                'CutType',string(app.Controls.CutType.Value), ...
                'CutValue',app.Controls.CutValue.Value, ...
                'SignedPhi',app.Controls.SignedPhi.Value, ...
                'Elevation',app.Controls.Elevation.Value, ...
                'Threshold',app.Controls.Threshold.Value, ...
                'Tab',string(app.Controls.Tabs.SelectedTab.Title));
        end

        function run(app, operation)
            if app.Busy
                return
            end
            app.Busy = true;
            cleanup = onCleanup(@() app.releaseBusy());
            try
                operation();
            catch exception
                if ~isempty(app.UIFigure) && isgraphics(app.UIFigure)
                    uialert(app.UIFigure, exception.message, 'APAT M8');
                else
                    rethrow(exception);
                end
            end
        end

        function releaseBusy(app)
            if isvalid(app)
                app.Busy = false;
            end
        end

        function chooseFile(app)
            [file, folder] = uigetfile( ...
                {'*.csv;*.tsv;*.txt;*.dat;*.xlsx;*.xls','Canonical pattern tables'});
            if ~isequal(file,0)
                app.open(string(fullfile(folder,file)));
            end
        end

        function saveFile(app)
            [file, folder] = uiputfile('*.csv', 'Export canonical pattern');
            if isequal(file,0)
                return
            end
            config = app.readConfig();
            output = app.exportTable(Loss=config.Loss);
            path = fullfile(folder,file);
            writetable(output, path);
            metadata = app.Pattern.Meta;
            metadata.SourceThetaConvention = metadata.ThetaConvention;
            metadata.ThetaConvention = "polar";
            metadata.AppliedGainOffset_dB = config.Loss;
            metadata.Revision = double(app.Revision);
            handle = fopen([path '.json'], 'w', 'n', 'UTF-8');
            if handle < 0
                error('APAT:ExportMetadata', 'CSV was saved, but its metadata sidecar could not be opened.');
            end
            cleanup = onCleanup(@() fclose(handle));
            fprintf(handle, '%s', jsonencode(metadata, 'PrettyPrint', true));
        end

        function render(app)
            if isempty(app.Pattern) || ~isgraphics(app.UIFigure)
                return
            end
            config = app.readConfig();
            values = app.column(config.Component, Loss=config.Loss);
            switch config.Tab
                case {"3D pattern","Pattern map"}
                    app.renderSurface(values, config);
                case "Cuts"
                    cut = app.cut(config.CutType, config.CutValue, config.Component, config.Loss);
                    angles = cut.Angle;
                    levels = cut.Value;
                    if cut.IsClosed
                        angles(end+1) = angles(1)+360;
                        levels(end+1) = levels(1);
                    end
                    set(app.Graphics.Cut, 'XData',angles,'YData',levels);
                    xlabel(app.Axes.Cut, 'Cut angle (deg)');
                    ylabel(app.Axes.Cut, char(config.Component));
                    width = NaN;
                    if app.isGain(config.Component)
                        width = APAT_v3_M8_37.hpbw(cut.Angle, cut.Value, cut.IsClosed);
                    end
                    title(app.Axes.Cut, sprintf('%s cut at %.4g deg | HPBW %.4g deg', ...
                        config.CutType, cut.Fixed, width), 'Interpreter','none');
                case "Coverage"
                    if ~app.isGain(config.Component)
                        set(app.Graphics.Coverage, 'XData',NaN,'YData',NaN);
                        title(app.Axes.Coverage, 'Select a gain component for coverage');
                    else
                        peak = APAT_v3_M8_37.peak(values);
                        upper = peak.Value;
                        if ~isfinite(upper)
                            upper = 0;
                        end
                        thresholds = linspace(upper-50,upper+5,221);
                        coverage = app.coverage(thresholds, ...
                            Component=config.Component, Loss=config.Loss);
                        set(app.Graphics.Coverage, 'XData',thresholds,'YData',coverage);
                        query = app.coverage(config.Threshold, ...
                            Component=config.Component, Loss=config.Loss);
                        title(app.Axes.Coverage, sprintf( ...
                            'Measured-domain coverage: %.4g%% above %.4g dB', query, config.Threshold));
                    end
                case "Data"
                    [theta,phi] = ndgrid(app.Pattern.Theta,app.Pattern.Phi);
                    count = min(numel(values),1000);
                    app.Controls.Data.Data = table(theta(1:count)',phi(1:count)', ...
                        values(1:count)', 'VariableNames',{'Theta','Phi','SelectedComponent'});
                case "Metadata"
                    metrics = app.metrics(config.Loss);
                    fields = string(fieldnames(metrics));
                    rows = cell(numel(fields)+6,2);
                    rows(1:6,:) = {'Source',char(app.Pattern.Meta.Name); ...
                        'Units',char(app.Pattern.Meta.Unit); ...
                        'Grid',sprintf('%d x %d',numel(app.Pattern.Theta),numel(app.Pattern.Phi)); ...
                        'Solid angle (sr)',app.Geometry.SolidAngle_sr; ...
                        'Full sphere',app.Geometry.IsFullSphere; ...
                        'Revision',double(app.Revision)};
                    for index = 1:numel(fields)
                        rows(index+6,:) = {char(fields(index)),metrics.(fields(index))};
                    end
                    app.Controls.Metadata.Data = rows;
            end
            app.Controls.Status.Text = sprintf( ...
                '%s | %d samples | %s | canonical export | table preview: 1,000 rows | M8 candidate', ...
                app.Pattern.Meta.Name,numel(values),app.Pattern.Meta.Unit);
            drawnow limitrate nocallbacks
        end

        function renderSurface(app, values, config)
            phi = app.Pattern.Phi;
            theta = app.Pattern.Theta;
            if config.Tab == "Pattern map"
                if config.SignedPhi
                    phi(phi >= 180) = phi(phi >= 180)-360;
                    [phi,order] = sort(phi);
                    values = values(:,order);
                end
                if config.Elevation
                    theta = 90-theta;
                end
            end
            if app.Pattern.Meta.PhiPeriodic
                phi(end+1) = phi(1)+360;
                values(:,end+1) = values(:,1);
            end
            [phiGrid,thetaGrid] = meshgrid(phi,theta);
            if config.Tab == "3D pattern"
                radius = ones(size(values));
                if app.isGain(config.Component)
                    peak = APAT_v3_M8_37.peak(values);
                    radius = max(0,min(1,(values-peak.Value+40)/40));
                    radius(~isfinite(radius)) = 0;
                end
                set(app.Graphics.Surface, ...
                    'XData',radius.*sind(thetaGrid).*cosd(phiGrid), ...
                    'YData',radius.*sind(thetaGrid).*sind(phiGrid), ...
                    'ZData',radius.*cosd(thetaGrid),'CData',values);
                ax = app.Axes.Surface;
            else
                set(app.Graphics.Map, 'XData',phiGrid,'YData',thetaGrid, ...
                    'ZData',zeros(size(values)),'CData',values);
                ax = app.Axes.Map;
                xlim(ax,[min(phi),max(phi)]);
                ylim(ax,[min(theta),max(theta)]);
                if config.Elevation
                    ax.YDir = 'normal';
                    ylabel(ax,'Elevation (deg)');
                else
                    ax.YDir = 'reverse';
                    ylabel(ax,'Polar theta (deg)');
                end
            end
            if config.Component == "AR_dB"
                clim(ax,[-30,30]);
            else
                peak = APAT_v3_M8_37.peak(values);
                upper = peak.Value;
                if ~isfinite(upper)
                    upper = 0;
                end
                clim(ax,[upper-40,upper]);
            end
            title(ax,char(config.Component),'Interpreter','none');
        end

        function createUI(app)
            app.UIFigure = uifigure('Name','APAT M8 | Candidate', ...
                'Position',[100,100,1180,780], ...
                'CloseRequestFcn',@(~,~) delete(app));
            root = uigridlayout(app.UIFigure,[4,1]);
            root.RowHeight = {44,92,'1x',28};
            header = APAT_v3_M8_37.place(@uigridlayout,root,1,1,[1,5]);
            header.ColumnWidth = {'1x',120,120,120,120};
            APAT_v3_M8_37.place(@uilabel,header,1,1, ...
                'Text','APAT M8 | Grid-native antenna analysis','FontSize',18,'FontWeight','bold');
            actions = {@() app.chooseFile(),@() app.saveFile(), ...
                @() app.resample(1),@() app.resetGrid()};
            labels = {'Open pattern','Export CSV','Resample 1 deg','Native grid'};
            for index = 1:4
                action = actions{index};
                APAT_v3_M8_37.place(@uibutton,header,1,index+1, ...
                    'Text',labels{index},'ButtonPushedFcn',@(~,~) app.run(action));
            end
            parameters = APAT_v3_M8_37.place(@uigridlayout,root,2,1,[2,6]);
            parameters.RowHeight = {22,30};
            parameterLabels = {'Component','Gain offset (dB)','Cut direction', ...
                'Fixed angle (deg)','Query threshold (dB)','Display coordinates'};
            for index = 1:6
                APAT_v3_M8_37.place(@uilabel,parameters,1,index,'Text',parameterLabels{index});
            end
            callback = @(~,~) app.run(@() app.render());
            app.Controls.Component = APAT_v3_M8_37.place(@uidropdown,parameters,2,1, ...
                'Items',{'E_Total_dB'},'ValueChangedFcn',callback);
            app.Controls.Loss = APAT_v3_M8_37.place(@uispinner,parameters,2,2, ...
                'Value',0,'Limits',[-200,100],'ValueChangedFcn',callback);
            app.Controls.CutType = APAT_v3_M8_37.place(@uidropdown,parameters,2,3, ...
                'Items',{'Theta','Phi'},'ValueChangedFcn',callback);
            app.Controls.CutValue = APAT_v3_M8_37.place(@uispinner,parameters,2,4, ...
                'Value',0,'Limits',[-360,360],'ValueChangedFcn',callback);
            app.Controls.Threshold = APAT_v3_M8_37.place(@uispinner,parameters,2,5, ...
                'Value',0,'ValueChangedFcn',callback);
            toggles = APAT_v3_M8_37.place(@uigridlayout,parameters,2,6,[1,2]);
            toggles.Padding = [0,0,0,0];
            app.Controls.SignedPhi = APAT_v3_M8_37.place(@uicheckbox,toggles,1,1, ...
                'Text','Signed phi','ValueChangedFcn',callback);
            app.Controls.Elevation = APAT_v3_M8_37.place(@uicheckbox,toggles,1,2, ...
                'Text','Elevation','ValueChangedFcn',callback);
            app.Controls.Tabs = APAT_v3_M8_37.place(@uitabgroup,root,3,1, ...
                'SelectionChangedFcn',callback);
            tabNames = ["3D pattern","Pattern map","Cuts","Coverage","Data","Metadata"];
            layouts = cell(1,numel(tabNames));
            for index = 1:numel(tabNames)
                tab = uitab(app.Controls.Tabs,'Title',char(tabNames(index)));
                layouts{index} = uigridlayout(tab,[1,1]);
            end
            app.Axes.Surface = uiaxes(layouts{1});
            app.Graphics.Surface = surf(app.Axes.Surface,nan(2),nan(2),nan(2), ...
                'EdgeColor','none');
            axis(app.Axes.Surface,'equal');
            view(app.Axes.Surface,35,25);
            grid(app.Axes.Surface,'on');
            colorbar(app.Axes.Surface);
            xlabel(app.Axes.Surface,'X');
            ylabel(app.Axes.Surface,'Y');
            zlabel(app.Axes.Surface,'Z');
            app.Axes.Map = uiaxes(layouts{2});
            app.Graphics.Map = surf(app.Axes.Map,nan(2),nan(2),nan(2), ...
                'EdgeColor','none');
            view(app.Axes.Map,2);
            colorbar(app.Axes.Map);
            xlabel(app.Axes.Map,'Phi (deg)');
            app.Axes.Cut = uiaxes(layouts{3});
            app.Graphics.Cut = plot(app.Axes.Cut,NaN,NaN,'LineWidth',1.6);
            grid(app.Axes.Cut,'on');
            app.Axes.Coverage = uiaxes(layouts{4});
            app.Graphics.Coverage = plot(app.Axes.Coverage,NaN,NaN,'LineWidth',1.6);
            grid(app.Axes.Coverage,'on');
            ylim(app.Axes.Coverage,[0,100]);
            xlabel(app.Axes.Coverage,'Gain threshold (dB), strict >');
            ylabel(app.Axes.Coverage,'Weighted coverage (%)');
            app.Controls.Data = uitable(layouts{5});
            app.Controls.Metadata = uitable(layouts{6},'ColumnName',{'Property','Value'});
            app.Controls.Status = APAT_v3_M8_37.place(@uilabel,root,4,1,'Text','Ready');
        end
    end
end