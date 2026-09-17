function varargout = APAT_v3_M8_34(action, varargin) %AST %1386-lines
%APAT_V3_M8 A compact, inspectable antenna-pattern analysis candidate.
% Target: MATLAB R2023b or newer. No optional toolboxes are required.
% This is a function-based redesign, not an App Designer class replacement.
% Read APAT_M8_CHANGES.md for compatibility limits and validation status.
%
%   APAT_v3_M8                         Open the desktop application.
%   S = APAT_v3_M8('read', path, opts)  Read a supported pattern file.
%   A = APAT_v3_M8('analyze', S, opts)  Prepare geometry and derive results.
%   [C,D] = APAT_v3_M8('coverage', A, thresholds, component, region)
%   K = APAT_v3_M8('cut', A, 'Theta', 0, 'E_Total_dB')
%   APAT_v3_M8('export', A, 'pattern.csv')
%   results = runtests('APAT_M8_tests.m'); assertSuccess(results)
%
% Dataflow: reader -> canonical primitives -> optional resampling -> geometry
%          -> derived quantities -> selected renderer / coverage / export.
% Display conventions never modify the canonical coordinates.

if nargin == 0
    action = 'app';
end
switch lower(string(action))
    case "app"
        varargout{1} = launchApp();
    case "defaults"
        varargout{1} = optionsWithDefaults();
    case "demo"
        varargout{1} = demoSource(varargin{:});
    case "read"
        varargout{1} = readSource(varargin{:});
    case "analyze"
        varargout{1} = analyzeSource(varargin{:});
    case "distribution"
        varargout{1} = distributionFor(varargin{:});
    case "evaluate"
        varargout{1} = evaluateDistribution(varargin{:});
    case "coverage"
        analysis = varargin{1};
        thresholds = varargin{2};
        distribution = distributionFor(analysis, varargin{3:end});
        varargout{1} = evaluateDistribution(distribution, thresholds);
        varargout{2} = distribution;
    case "cut"
        varargout{1} = extractCut(varargin{:});
    case "table"
        varargout{1} = outputTable(varargin{:});
    case "export"
        writeOutput(varargin{:});
    otherwise
        error('APAT:Action', 'Unknown action: %s.', action);
end
end

function options = optionsWithDefaults(supplied)
options = struct('TextFormat', "gain", 'FieldBasis', "linear", ...
    'ThetaConvention', "polar", 'PhaseUnit', "degrees", ...
    'FrequencyIndex', 1, 'StepDeg', 0, 'PeriodicPhi', true, ...
    'GainOffsetDB', 0, 'AbsoluteGain', false, 'TxPowerDBW', 0, ...
    'DistanceM', 1, 'RxMode', "RHCP", 'RxARDB', 0, 'RxTiltDeg', 0, ...
    'PeakPolicy', "legacy", 'PeakPercentile', 99.99, ...
    'PeakExcessDB', 6, 'AngleTolerance', 1e-7, 'FFDOrder', "theta-fast");
if nargin > 0 && ~isempty(supplied)
    assert(isstruct(supplied) && isscalar(supplied), ...
        'APAT:Options', 'Options must be a scalar struct.');
    names = fieldnames(supplied);
    for index = 1:numel(names)
        name = names{index};
        assert(isfield(options, name), 'APAT:Option', 'Unknown option: %s.', name);
        options.(name) = supplied.(name);
    end
end
choiceFields = {'TextFormat','FieldBasis','ThetaConvention','PhaseUnit', ...
    'RxMode','PeakPolicy','FFDOrder'};
choices = {{'gain','reim','magphase'}, {'linear','circular'}, ...
    {'polar','elevation','signed-polar'}, {'degrees','radians'}, ...
    {'Auto','RHCP','LHCP','Theta','Phi'}, {'raw','legacy'}, ...
    {'theta-fast','phi-fast'}};
for index = 1:numel(choiceFields)
    name = choiceFields{index};
    options.(name) = string(validatestring(options.(name), choices{index}));
end
validateattributes(options.FrequencyIndex, {'numeric'}, {'scalar','integer','positive','finite'});
validateattributes(options.StepDeg, {'numeric'}, {'scalar','real','finite','>=',0,'<=',180});
if options.StepDeg > 0
    assert(options.StepDeg >= 0.25, 'APAT:GridBudget', 'Minimum resampling step is 0.25 degrees.');
end
validateattributes(options.DistanceM, {'numeric'}, {'scalar','real','finite','positive'});
validateattributes(options.RxARDB, {'numeric'}, {'scalar','real','finite','>=',0,'<=',300});
validateattributes(options.PeakPercentile, {'numeric'}, {'scalar','real','finite','>',0,'<=',100});
validateattributes(options.PeakExcessDB, {'numeric'}, {'scalar','real','finite','nonnegative'});
validateattributes(options.AngleTolerance, {'numeric'}, {'scalar','real','finite','positive','<=',1e-3});
for name = ["GainOffsetDB", "TxPowerDBW", "RxTiltDeg"]
    validateattributes(options.(name), {'numeric'}, {'scalar','real','finite','>=',-300,'<=',300});
end
validateattributes(options.PeriodicPhi, {'logical'}, {'scalar'});
validateattributes(options.AbsoluteGain, {'logical'}, {'scalar'});
end

function analysis = analyzeSource(source, supplied)
if nargin < 2
    supplied = struct();
end
options = optionsWithDefaults(supplied);
if isfield(source, 'Blocks')
    assert(options.FrequencyIndex <= numel(source.Blocks), ...
        'APAT:Frequency', 'Frequency index exceeds the source block count.');
    block = source.Blocks{options.FrequencyIndex};
else
    block = source;
end
pattern = canonicalPattern(block, options);
if options.StepDeg > 0
    pattern = resamplePattern(pattern, options.StepDeg);
end
pattern.Geometry = buildGeometry(pattern);
analysis = derivePattern(pattern, options);
end

function pattern = canonicalPattern(block, options)
required = {'Theta','Phi','Fields','Values','Names','Kinds','Meta'};
assert(isstruct(block) && isscalar(block), 'APAT:Schema', 'A source block must be a scalar struct.');
assert(all(isfield(block, required)), 'APAT:Schema', 'Invalid source block schema.');
metadataFields = {'Name','Path','Format','AbsoluteGain','FrequencyHz','Notes'};
assert(isstruct(block.Meta) && isscalar(block.Meta) && all(isfield(block.Meta,metadataFields)), ...
    'APAT:Metadata', 'Source metadata does not satisfy the documented contract.');
validateattributes(block.Meta.AbsoluteGain, {'logical'}, {'scalar'});
theta = double(block.Theta(:));
phi = double(block.Phi(:));
assert(~isempty(theta) && numel(theta) == numel(phi), ...
    'APAT:Coordinates', 'Theta and Phi must be nonempty vectors of equal length.');
assert(isreal(theta) && isreal(phi), 'APAT:Coordinates', 'Angular coordinates must be real.');
assert(all(isfinite(theta) & isfinite(phi)), 'APAT:Coordinates', 'Angles must be finite.');
pattern = block;
pattern.Names = reshape(string(block.Names),1,[]);
pattern.Kinds = reshape(string(block.Kinds),1,[]);
assert(xor(isempty(block.Fields),isempty(block.Values)), ...
    'APAT:Schema', 'Supply either complex fields or scalar values, not both or neither.');
isField = ~isempty(block.Fields);
if isField
    values = double(block.Fields);
    assert(size(values, 2) == 2, 'APAT:Fields', 'Exactly two complex field components are required.');
else
    values = double(block.Values);
    assert(size(values, 2) == numel(block.Names) && ~isempty(values), ...
        'APAT:Values', 'Value columns and names must match.');
    assert(numel(pattern.Kinds)==numel(pattern.Names) ...
        && all(ismember(pattern.Kinds,["gain","diagnostic"])), ...
        'APAT:Kinds', 'Each value column needs a gain or diagnostic quantity kind.');
    assert(isreal(values), 'APAT:Values', 'Gain and diagnostic columns must be real.');
end
assert(size(values, 1) == numel(theta), 'APAT:Rows', 'Coordinate and value row counts differ.');
if isField
    assert(~any(isinf(values), 'all'), 'APAT:Fields', 'Infinite field components are not supported.');
    assert(~any(abs(values) > 1e100, 'all'), 'APAT:Fields', 'Field magnitudes exceed the numerical budget.');
else
    positiveInfinity = values==Inf;
    axialColumns = pattern.Kinds=="diagnostic" & ...
        (ismember(lower(pattern.Names),["ar","ar_db"]) | contains(lower(pattern.Names),"axial"));
    positiveInfinity(:,axialColumns) = false;
    assert(~any(positiveInfinity,'all'), 'APAT:Values', ...
        'Positive infinity is valid only for explicitly identified axial-ratio diagnostics.');
end
if options.ThetaConvention == "elevation"
    assert(all(theta >= -90-options.AngleTolerance & theta <= 90+options.AngleTolerance), ...
        'APAT:Angles', 'Elevation must be within [-90,90] up to the angular tolerance.');
    theta = 90 - theta;
elseif options.ThetaConvention == "signed-polar"
    theta = mod(theta, 360);
    folded = theta > 180;
    theta(folded) = 360 - theta(folded);
    phi(folded) = phi(folded) + 180;
    if isField
        values(folded, :) = -values(folded, :);
    end
else
    assert(all(theta >= -options.AngleTolerance & theta <= 180+options.AngleTolerance), 'APAT:Angles', ...
        'Polar theta must be in [0,180]; select the coordinate convention explicitly.');
end
tolerance = options.AngleTolerance;
theta = min(max(round(theta / tolerance) * tolerance,0),180);
phi = mod(round(phi / tolerance) * tolerance, 360);
phi(abs(phi - 360) < tolerance / 2) = 0;
[coordinates, first, group] = unique([phi, theta], 'rows');
if numel(first) < numel(theta)
    reference = values(first(group), :);
    same = values == reference | (isnan(values) & isnan(reference));
    finitePair = isfinite(values) & isfinite(reference);
    same = same | finitePair & abs(values-reference) <= 1e-12 + 1e-8 * max(abs(values),abs(reference));
    assert(all(same, 'all'), 'APAT:DuplicateConflict', ...
        'Duplicate angular samples disagree, including a possible 0/360 seam conflict.');
end
pattern.Theta = coordinates(:, 2);
pattern.Phi = coordinates(:, 1);
if isField
    pattern.Fields = values(first, :);
else
    pattern.Values = values(first, :);
end
pattern.ThetaAxis = unique(pattern.Theta);
pattern.PhiAxis = unique(pattern.Phi);
pattern.IsGrid = numel(pattern.ThetaAxis) * numel(pattern.PhiAxis) == numel(first);
gaps = diff([pattern.PhiAxis; pattern.PhiAxis(1) + 360]);
pattern.PeriodicPhi = options.PeriodicPhi && numel(gaps) >= 3 ...
    && max(gaps) <= 1.5 * median(gaps) + tolerance;
pattern.Meta.AbsoluteGain = options.AbsoluteGain || pattern.Meta.AbsoluteGain;
end

function pattern = resamplePattern(pattern, step)
thetaTarget = sampleAxis(pattern.ThetaAxis(1), pattern.ThetaAxis(end), step);
if pattern.PeriodicPhi
    phiTarget = (0:step:360).';
    phiTarget(phiTarget >= 360) = [];
else
    phiTarget = sampleAxis(pattern.PhiAxis(1), pattern.PhiAxis(end), step);
end
[thetaQuery, phiQuery] = ndgrid(thetaTarget, phiTarget);
isField = ~isempty(pattern.Fields);
if isField
    values = [real(pattern.Fields), imag(pattern.Fields)];
else
    assert(all(pattern.Kinds == "gain"), 'APAT:ResampleQuantity', ...
        'Resampling diagnostic-only AR/phase columns is unsafe; supply primitive fields or gain columns only.');
    values = pattern.Values;
end
result = nan(numel(thetaQuery), size(values, 2));
interpolant = [];
for column = 1:size(values, 2)
    current = values(:, column);
    offset = 0;
    if ~isField
        finiteGain = current(isfinite(current));
        if ~isempty(finiteGain)
            offset = max(finiteGain);
        end
        current = 10.^((current - offset) / 10);
    end
    if pattern.IsGrid
        grid = reshape(current, numel(pattern.ThetaAxis), numel(pattern.PhiAxis));
        phi = pattern.PhiAxis;
        if pattern.PeriodicPhi
            phi = [phi(end) - 360; phi; phi(1) + 360];
            grid = [grid(:, end), grid, grid(:, 1)];
        end
        if numel(pattern.ThetaAxis) == 1 && numel(phi) == 1
            query = repmat(grid, size(thetaQuery));
        elseif numel(pattern.ThetaAxis) == 1
            query = interp1(phi, grid(:), phiQuery, 'linear', NaN);
        elseif numel(phi) == 1
            query = interp1(pattern.ThetaAxis, grid, thetaQuery, 'linear', NaN);
        else
            if isempty(interpolant)
                interpolant = griddedInterpolant({pattern.ThetaAxis, phi}, grid, 'linear', 'none');
            else
                interpolant.Values = grid;
            end
            query = interpolant(thetaQuery, phiQuery);
        end
    else
        theta = pattern.Theta;
        phi = pattern.Phi;
        if pattern.PeriodicPhi
            theta = repmat(theta, 3, 1);
            phi = [phi - 360; phi; phi + 360];
            current = repmat(current, 3, 1);
        end
        if isempty(interpolant)
            assert(rank([theta - mean(theta), phi - mean(phi)]) == 2, ...
                'APAT:DegenerateGrid', 'Scattered interpolation requires a two-dimensional sample domain.');
            interpolant = scatteredInterpolant(theta, phi, current, 'linear', 'none');
        else
            interpolant.Values = current;
        end
        query = interpolant(thetaQuery, phiQuery);
    end
    if ~isField
        query = 10 * log10(max(query, 0)) + offset;
    end
    result(:, column) = query(:);
end
pattern.Theta = thetaQuery(:);
pattern.Phi = phiQuery(:);
pattern.ThetaAxis = thetaTarget;
pattern.PhiAxis = phiTarget;
pattern.IsGrid = true;
if isField
    pattern.Fields = complex(result(:, 1:2), result(:, 3:4));
else
    pattern.Values = result;
end
end

function axis = sampleAxis(first, last, step)
axis = (first:step:last).';
if isempty(axis) || abs(axis(end) - last) > 1e-9
    axis(end + 1) = last;
end
end

function geometry = buildGeometry(pattern)
geometry = struct('Weights', nan(size(pattern.Theta)), 'FullSphere', false, ...
    'Omega', NaN, 'UnitVectors', [sind(pattern.Theta).*cosd(pattern.Phi), ...
    sind(pattern.Theta).*sind(pattern.Phi), cosd(pattern.Theta)]);
theta = pattern.ThetaAxis;
phi = pattern.PhiAxis;
if ~pattern.IsGrid || numel(theta) < 2 || numel(phi) < 2
    return
end
thetaEdges = [theta(1); (theta(1:end-1) + theta(2:end)) / 2; theta(end)];
thetaWeight = cosd(thetaEdges(1:end-1)) - cosd(thetaEdges(2:end));
if pattern.PeriodicPhi
    previous = [phi(end) - 360; phi(1:end-1)];
    following = [phi(2:end); phi(1) + 360];
    phiWeight = deg2rad((following - previous) / 2);
else
    phiEdges = [phi(1); (phi(1:end-1) + phi(2:end)) / 2; phi(end)];
    phiWeight = deg2rad(diff(phiEdges));
end
weights = thetaWeight * phiWeight.';
geometry.Weights = weights(:);
geometry.Omega = sum(weights, 'all');
geometry.FullSphere = pattern.PeriodicPhi && abs(theta(1)) < 1e-7 ...
    && abs(theta(end) - 180) < 1e-7;
end

function analysis = derivePattern(pattern, options)
columns = struct();
if isempty(pattern.Fields)
    names = string(matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(cellstr(pattern.Names))));
    pattern.Names = names;
    for index = 1:numel(names)
        values = pattern.Values(:, index);
        if pattern.Kinds(index) == "gain"
            values = values + options.GainOffsetDB;
        end
        columns.(names(index)) = values;
    end
    totalIndex = find(pattern.Kinds == "gain", 1);
    assert(~isempty(totalIndex), 'APAT:NoGain', 'At least one declared gain quantity is required.');
    explicitTotal = find(ismember(lower(names), ["e_total_db","gain_dbi","gain_db","totalgain"]) ...
        & pattern.Kinds=="gain", 1);
    if ~isempty(explicitTotal)
        totalIndex = explicitTotal;
    end
    total = columns.(names(totalIndex));
    columns.E_Total_dB = total;
else
    eth = pattern.Fields(:, 1);
    eph = pattern.Fields(:, 2);
    er = (eth + 1i * eph) / sqrt(2);
    el = (eth - 1i * eph) / sqrt(2);
    totalMagnitude = hypot(abs(eth), abs(eph));
    total = 20 * log10(totalMagnitude) + options.GainOffsetDB;
    columns.E_Total_dB = total;
    columns.E_TH_dB = 20 * log10(abs(eth)) + options.GainOffsetDB;
    columns.E_PH_dB = 20 * log10(abs(eph)) + options.GainOffsetDB;
    columns.E_RCP_dB = 20 * log10(abs(er)) + options.GainOffsetDB;
    columns.E_LCP_dB = 20 * log10(abs(el)) + options.GainOffsetDB;
    delta = abs(er) - abs(el);
    denominator = abs(delta);
    linear = denominator <= 8 * eps .* (abs(er) + abs(el));
    axialRatio = (abs(er) + abs(el)) ./ denominator;
    axialRatio(linear & totalMagnitude > 0) = Inf;
    axialRatio(totalMagnitude == 0) = NaN;
    columns.AR_dB = 20 * log10(axialRatio);
    columns.PolSense = sign(delta);
    columns.PolSense(linear | totalMagnitude == 0) = 0;
    receiver = receiverJones(options, er, el, pattern.Geometry.Weights);
    normalizedTheta = eth ./ totalMagnitude;
    normalizedPhi = eph ./ totalMagnitude;
    plf = abs(conj(receiver(1)) * normalizedTheta + conj(receiver(2)) * normalizedPhi).^2;
    plf = min(max(plf, 0), 1);
    plf(totalMagnitude == 0) = NaN;
    columns.PLF_dB = 10 * log10(plf);
    columns.Gain_PolCorrected_dB = total + columns.PLF_dB;
    columns.Gain_PolCorrected_dB(totalMagnitude==0) = -Inf;
end
analysis = struct('Pattern', pattern, 'Columns', columns, 'Options', options, ...
    'Peak', resolvePeak(total, options), 'Metrics', struct());
analysis.Metrics = computeMetrics(analysis);
end

function receiver = receiverJones(options, er, el, weights)
mode = options.RxMode;
if mode == "Theta"
    receiver = [1, 0];
    return
elseif mode == "Phi"
    receiver = [0, 1];
    return
elseif mode == "Auto"
    if ~all(isfinite(weights))
        error('APAT:AutoRx', 'Auto receive polarization requires a supported angular quadrature.');
    end
    rightPower = sum(abs(er).^2 .* weights, 'omitnan');
    leftPower = sum(abs(el).^2 .* weights, 'omitnan');
    mode = "RHCP";
    if leftPower > rightPower
        mode = "LHCP";
    end
end
sense = 1;
if mode == "LHCP"
    sense = -1;
end
minor = -1i * sense * 10^(-options.RxARDB / 20);
tilt = options.RxTiltDeg;
receiver = [cosd(tilt) - minor * sind(tilt), sind(tilt) + minor * cosd(tilt)];
receiver = receiver / norm(receiver);
end

function peak = resolvePeak(values, options)
valid = find(~isnan(values) & values < Inf);
peak = struct('ValueDB', NaN, 'Index', NaN, 'RawValueDB', NaN, ...
    'RawIndex', NaN, 'Adjusted', false, 'PercentileDB', NaN);
if isempty(valid)
    return
end
[peak.RawValueDB, local] = max(values(valid));
peak.RawIndex = valid(local);
peak.ValueDB = peak.RawValueDB;
peak.Index = peak.RawIndex;
finite = sort(values(isfinite(values)));
if options.PeakPolicy == "raw" || isempty(finite)
    return
end
position = min(max(numel(finite) * options.PeakPercentile / 100 + 0.5, 1), numel(finite));
lowerIndex = floor(position);
upperIndex = ceil(position);
peak.PercentileDB = finite(lowerIndex) + (position - lowerIndex) * (finite(upperIndex) - finite(lowerIndex));
if peak.RawValueDB > peak.PercentileDB + options.PeakExcessDB
    candidates = find(isfinite(values) & values <= peak.PercentileDB);
    [peak.ValueDB, local] = max(values(candidates));
    peak.Index = candidates(local);
    peak.Adjusted = true;
end
end

function metrics = computeMetrics(analysis)
pattern = analysis.Pattern;
geometry = pattern.Geometry;
gain = analysis.Columns.E_Total_dB;
peak = analysis.Peak;
metrics = struct('RawPeakDB', peak.RawValueDB, 'DisplayPeakDB', peak.ValueDB, ...
    'ThetaDeg', NaN, 'PhiDeg', NaN, 'DirectivityDB', NaN, 'GainIntegralPct', NaN, ...
    'FrontBackDB', NaN, 'BackDirectionErrorDeg', NaN, 'EPlaneHPBWDeg', NaN, ...
    'HPlaneHPBWDeg', NaN, 'BoresightAxis', "unavailable", 'SolidAngleSR', geometry.Omega);
if ~isfinite(peak.RawIndex) || ~isfinite(peak.RawValueDB)
    return
end
index = peak.RawIndex;
metrics.ThetaDeg = pattern.Theta(index);
metrics.PhiDeg = pattern.Phi(index);
similarity = geometry.UnitVectors * geometry.UnitVectors(index, :).';
[minimum, back] = min(similarity);
metrics.BackDirectionErrorDeg = acosd(min(max(-minimum, -1), 1));
if metrics.BackDirectionErrorDeg <= 1e-5
    metrics.FrontBackDB = peak.RawValueDB - gain(back);
end
weights = geometry.Weights;
if any(~isfinite(weights))
    return
end
scaledPower = 10.^((gain - peak.RawValueDB) / 10);
complete = ~any(isnan(gain) & weights > 0);
integral = sum(scaledPower .* weights, 'omitnan');
if geometry.FullSphere && complete && integral > 0
    metrics.DirectivityDB = 10 * log10(4 * pi / integral);
    if pattern.Meta.AbsoluteGain
        metrics.GainIntegralPct = 100 * 10^((peak.RawValueDB - metrics.DirectivityDB) / 10);
    end
end
axes = [0 0 1; 0 0 -1; 1 0 0; -1 0 0; 0 1 0; 0 -1 0];
axisNames = ["+Z","-Z","+X","-X","+Y","-Y"];
energy = zeros(1, 6);
for axisIndex = 1:6
    mask = geometry.UnitVectors * axes(axisIndex, :).' >= cosd(45);
    energy(axisIndex) = sum(scaledPower(mask) .* weights(mask), 'omitnan');
end
[~, axisIndex] = max(energy);
metrics.BoresightAxis = axisNames(axisIndex);
axisPhi = [0, 0, 0, 180, 90, 270];
cutE = extractCut(analysis, "Theta", axisPhi(axisIndex), "E_Total_dB");
if axisIndex <= 2
    cutH = extractCut(analysis, "Theta", 90, "E_Total_dB");
else
    cutH = extractCut(analysis, "Phi", 90, "E_Total_dB");
end
metrics.EPlaneHPBWDeg = cutE.HPBWDeg;
metrics.HPlaneHPBWDeg = cutH.HPBWDeg;
end

function cut = extractCut(analysis, type, requested, component)
if nargin < 4
    component = "E_Total_dB";
end
validateattributes(requested, {'numeric'}, {'scalar','real','finite'});
pattern = analysis.Pattern;
assert(isfield(analysis.Columns, component), 'APAT:Component', 'Unknown component: %s.', component);
complete = false;
if strcmpi(type, 'Phi')
    [~, nearest] = min(abs(pattern.ThetaAxis - requested));
    fixed = pattern.ThetaAxis(nearest);
    rows = find(abs(pattern.Theta - fixed) < 1e-7);
    angles = pattern.Phi(rows);
    complete = pattern.PeriodicPhi;
else
    assert(strcmpi(type, 'Theta'), 'APAT:Cut', 'Cut type must be Theta or Phi.');
    [~, nearest] = min(abs(wrap180(pattern.PhiAxis - requested)));
    fixed = pattern.PhiAxis(nearest);
    opposite = mod(fixed + 180, 360);
    primary = find(abs(wrap180(pattern.Phi - fixed)) < 1e-7);
    secondary = find(abs(wrap180(pattern.Phi - opposite)) < 1e-7 ...
        & pattern.Theta > 1e-7 & pattern.Theta < 180 - 1e-7);
    rows = [primary; secondary];
    angles = [pattern.Theta(primary); 360 - pattern.Theta(secondary)];
    complete = ~isempty(secondary) && any(pattern.Theta(primary) == 0) ...
        && any(pattern.Theta(primary) == 180);
end
[angles, order] = sort(angles);
rows = rows(order);
values = analysis.Columns.(component);
cut = struct('AngleDeg', angles, 'Values', values(rows), 'Rows', rows, ...
    'FixedDeg', fixed, 'RequestedDeg', requested, 'Complete', complete, ...
    'HPBWDeg', NaN, 'BoundsDeg', [NaN, NaN]);
if complete && isGainQuantity(analysis,component)
    [cut.HPBWDeg, cut.BoundsDeg] = halfPowerWidth(angles, cut.Values);
end
end

function [width, bounds] = halfPowerWidth(angles, gain)
width = NaN;
bounds = [NaN, NaN];
if numel(gain) < 3 || any(isnan(gain))
    return
end
[peak, index] = max(gain);
if ~isfinite(peak)
    return
end
[relative, order] = sort(wrap180(angles - angles(index)));
values = gain(order);
half = peak + 10 * log10(0.5);
left = find(relative < 0 & values <= half, 1, 'last');
right = find(relative > 0 & values <= half, 1, 'first');
if isempty(left) || isempty(right)
    return
end
leftPair = [left, left + 1];
rightPair = [right - 1, right];
if any(~isfinite(values([leftPair, rightPair])))
    return
end
crossLeft = relative(left);
crossRight = relative(right);
if values(left) ~= half
    crossLeft = interp1(values(leftPair), relative(leftPair), half, 'linear');
end
if values(right) ~= half
    crossRight = interp1(values(rightPair), relative(rightPair), half, 'linear');
end
width = crossRight - crossLeft;
bounds = angles(index) + [crossLeft, crossRight];
end

function result = isGainQuantity(analysis,component)
gainNames = ["E_Total_dB","E_TH_dB","E_PH_dB","E_RCP_dB","E_LCP_dB","Gain_PolCorrected_dB"];
declaredGain = analysis.Pattern.Names(analysis.Pattern.Kinds=="gain");
result = ismember(string(component),[gainNames,declaredGain]);
end

function distribution = distributionFor(analysis, component, region)
if nargin < 2 || isempty(component)
    component = "E_Total_dB";
end
if nargin < 3 || isempty(region)
    region = struct('Type', "sphere");
end
assert(isfield(analysis.Columns, component), 'APAT:Component', 'Unknown component.');
assert(isGainQuantity(analysis,component), 'APAT:CoverageQuantity', ...
    'Coverage in this candidate is defined for gain quantities, not AR, phase, PLF or handedness.');
assert(isfield(region, 'Type'), 'APAT:Region', 'A region needs a Type field.');
geometry = analysis.Pattern.Geometry;
weights = geometry.Weights;
assert(all(isfinite(weights)), 'APAT:Quadrature', ...
    'Coverage requires a rectangular angular grid with at least two samples per axis.');
mask = true(size(weights));
if strcmpi(region.Type, 'cone')
    assert(all(isfield(region, {'ThetaDeg','PhiDeg','HalfAngleDeg'})), ...
        'APAT:Cone', 'Cone requires ThetaDeg, PhiDeg and HalfAngleDeg.');
    validateattributes(region.ThetaDeg, {'numeric'}, {'scalar','real','finite','>=',0,'<=',180});
    validateattributes(region.PhiDeg, {'numeric'}, {'scalar','real','finite'});
    validateattributes(region.HalfAngleDeg, {'numeric'}, {'scalar','real','finite','>=',0,'<=',180});
    direction = [sind(region.ThetaDeg)*cosd(region.PhiDeg), ...
        sind(region.ThetaDeg)*sind(region.PhiDeg), cosd(region.ThetaDeg)];
    mask = geometry.UnitVectors * direction.' >= cosd(region.HalfAngleDeg);
else
    assert(strcmpi(region.Type, 'sphere'), 'APAT:Region', 'Region must be sphere or cone.');
end
gain = analysis.Columns.(component);
valid = mask & weights > 0 & ~isnan(gain) & gain < Inf;
[levels, ~, group] = unique(gain(valid));
mass = zeros(0,1);
if ~isempty(levels)
    mass = accumarray(group, weights(valid), [numel(levels), 1], @sum, 0);
end
total = sum(mass);
survival = [flipud(cumsum(flipud(mass))); 0];
if total > 0
    survival = 100 * survival / total;
else
    survival(:) = NaN;
end
distribution = struct('Levels', levels, 'Survival', survival, 'ValidOmega', total, ...
    'RegionOmega', sum(weights(mask)), 'MissingOmega', sum(weights(mask & ~valid)), ...
    'Component', string(component), 'Region', region, 'FullSphere', geometry.FullSphere);
end

function coverage = evaluateDistribution(distribution, thresholds)
validateattributes(thresholds, {'numeric'}, {'real'});
shape = size(thresholds);
thresholds = double(thresholds(:));
coverage = nan(size(thresholds));
if distribution.ValidOmega <= 0
    coverage = reshape(coverage, shape);
    return
end
levels = distribution.Levels;
for index = 1:numel(thresholds)
    if isnan(thresholds(index))
        continue
    end
    lower = 1;
    upper = numel(levels) + 1;
    % Upper-bound search preserves strict > semantics, including tied gains.
    while lower < upper
        middle = floor((lower + upper) / 2);
        if middle <= numel(levels) && levels(middle) <= thresholds(index)
            lower = middle + 1;
        else
            upper = middle;
        end
    end
    coverage(index) = distribution.Survival(lower);
end
coverage = reshape(coverage, shape);
end

function values = wrap180(values)
values = mod(values + 180, 360) - 180;
end

function output = outputTable(analysis, includeLink)
if nargin < 2
    includeLink = false;
end
pattern = analysis.Pattern;
output = table(pattern.Theta, pattern.Phi, 'VariableNames', {'Theta','Phi'});
names = fieldnames(analysis.Columns);
for index = 1:numel(names)
    output.(names{index}) = analysis.Columns.(names{index});
end
if includeLink
    options = analysis.Options;
    total = analysis.Columns.E_Total_dB;
    eirp = nan(size(total));
    if pattern.Meta.AbsoluteGain
        eirp = total + options.TxPowerDBW;
    end
    output.EIRP_dBW = eirp;
    output.PFD_Wm2 = 10.^((eirp - 10*log10(4*pi) - 20*log10(options.DistanceM))/10);
    output.E_RMS_Vm = sqrt(120*pi*output.PFD_Wm2);
end
output.Properties.UserData = struct('Release', 'M8-candidate', 'Metadata', pattern.Meta, ...
    'Options', analysis.Options, 'Metrics', analysis.Metrics);
end

function writeOutput(analysis, path)
[~, ~, extension] = fileparts(path);
if strcmpi(extension, '.uan')
    pattern = analysis.Pattern;
    assert(~isempty(pattern.Fields), 'APAT:Export', 'UAN export requires complex fields.');
    assert(pattern.Meta.AbsoluteGain, 'APAT:Calibration', 'UAN gain export requires calibrated gain-normalized fields.');
    file = fopen(path, 'w');
    assert(file >= 0, 'APAT:Write', 'Unable to open output file.');
    cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
    fprintf(file, 'begin_<parameters>\nformat free\ncomplex\nmag_phase\npattern gain\n');
    fprintf(file, 'magnitude dB\nphase degrees\ndirection degrees\npolarization theta_phi\n');
    if isfinite(pattern.Meta.FrequencyHz)
        fprintf(file, 'frequency %.17g\n', pattern.Meta.FrequencyHz);
    end
    fprintf(file, 'end_<parameters>\nbegin_<data>\n');
    fields = pattern.Fields;
    magnitude = 20*log10(abs(fields)) + analysis.Options.GainOffsetDB;
    phase = rad2deg(angle(fields));
    data = [pattern.Theta, pattern.Phi, magnitude(:,1), phase(:,1), magnitude(:,2), phase(:,2)];
    fprintf(file, '%.17g %.17g %.17g %.17g %.17g %.17g\n', data.');
    fprintf(file, 'end_<data>\n');
else
    assert(any(strcmpi(extension, {'.csv','.txt','.xlsx'})), ...
        'APAT:Export', 'Output extension must be csv, txt, xlsx or uan.');
    writetable(outputTable(analysis, true), path);
end
end

% READERS: strict, explicit contracts. Unsupported vendor variants fail loudly.
function source = readSource(path, supplied)
if nargin < 2
    supplied = struct();
end
options = optionsWithDefaults(supplied);
assert(isfile(path), 'APAT:Read', 'File does not exist: %s.', path);
[~, name, extension] = fileparts(path);
metadata = struct('Name', string(name), 'Path', string(path), ...
    'Format', lower(string(extension)), 'AbsoluteGain', options.AbsoluteGain, ...
    'FrequencyHz', NaN, 'Notes', "Source calibration must be confirmed by the user.");
switch lower(extension)
    case {'.csv','.txt','.dat'}
        input = readtable(path, 'VariableNamingRule', 'preserve');
        numeric = varfun(@isnumeric, input, 'OutputFormat', 'uniform');
        assert(all(numeric) && width(input) >= 3, 'APAT:TextSchema', ...
            'Text input requires a header, numeric columns, then Theta, Phi and values.');
        names = string(input.Properties.VariableNames);
        assert(strcmpi(names(1), 'Theta') && strcmpi(names(2), 'Phi'), ...
            'APAT:TextSchema', 'First two headers must be Theta and Phi; no axis guessing is performed.');
        matrix = input{:, :};
        blocks = {makeBlock(matrix(:,1), matrix(:,2), matrix(:,3:end), ...
            names(3:end), options.TextFormat, options.FieldBasis, options.PhaseUnit, metadata)};
    case '.uan'
        lines = strip(splitlines(string(fileread(path))));
        first = find(startsWith(lower(lines), 'begin_<data>'), 1);
        last = find(startsWith(lower(lines), 'end_<data>'), 1);
        assert(~isempty(first) && ~isempty(last) && last > first, 'APAT:UAN', 'Missing UAN data delimiters.');
        assert(contains(lower(join(lines(1:first))), 'magnitude db'), 'APAT:UAN', 'Only dB-magnitude UAN is supported.');
        assert(contains(lower(join(lines(1:first))), 'phase degrees'), 'APAT:UAN', 'Only degree-phase UAN is supported.');
        header = lower(join(lines(1:first)));
        frequencyLine = find(startsWith(lower(lines(1:first)), 'frequency '),1);
        if ~isempty(frequencyLine)
            frequency = sscanf(extractAfter(lines(frequencyLine), ' '), '%f');
            assert(isscalar(frequency) && isfinite(frequency), 'APAT:UAN', 'Invalid UAN frequency in Hz.');
            metadata.FrequencyHz = frequency;
        end
        basis = "linear";
        if contains(header, 'polarization circular') || contains(header, 'polarization rhcp_lhcp')
            basis = "circular";
        else
            assert(contains(header, 'polarization theta_phi'), 'APAT:UAN', 'Unsupported or missing UAN polarization basis.');
        end
        matrix = numericRows(lines(first+1:last-1), 6);
        blocks = {makeBlock(matrix(:,1), matrix(:,2), matrix(:,3:6), [], ...
            "magphase", basis, "degrees", metadata)};
    case '.ffd'
        lines = strip(splitlines(string(fileread(path))));
        lines(lines == "") = [];
        assert(numel(lines) >= 4, 'APAT:FFD', 'Incomplete FFD file.');
        thetaSpec = sscanf(lines(1), '%f');
        phiSpec = sscanf(lines(2), '%f');
        assert(numel(thetaSpec) == 3 && numel(phiSpec) == 3, 'APAT:FFD', 'FFD requires two start/stop/count headers.');
        validateattributes(thetaSpec(3), {'numeric'}, {'integer','positive','<=',10000});
        validateattributes(phiSpec(3), {'numeric'}, {'integer','positive','<=',10000});
        assert(thetaSpec(3)*phiSpec(3) <= 2e6, 'APAT:GridBudget', 'FFD grid exceeds two million samples.');
        theta = linspace(thetaSpec(1), thetaSpec(2), thetaSpec(3));
        phi = linspace(phiSpec(1), phiSpec(2), phiSpec(3));
        [thetaGrid, phiGrid] = ndgrid(theta, phi);
        if options.FFDOrder == "phi-fast"
            thetaGrid = thetaGrid.';
            phiGrid = phiGrid.';
        end
        starts = find(~cellfun('isempty', regexp(cellstr(lines), '^Frequency\s+[-+0-9.]', 'once')));
        assert(~isempty(starts), 'APAT:FFD', 'Each FFD block requires a Frequency header.');
        stops = [starts(2:end); numel(lines)+1];
        blocks = cell(1, numel(starts));
        for index = 1:numel(starts)
            frequency = sscanf(extractAfter(lines(starts(index)), 'Frequency'), '%f');
            assert(isscalar(frequency) && isfinite(frequency), 'APAT:FFD', 'Invalid FFD frequency.');
            metadata.FrequencyHz = frequency;
            matrix = numericRows(lines(starts(index)+1:stops(index)-1), 4);
            assert(size(matrix,1) == numel(thetaGrid), 'APAT:FFD', 'FFD block size differs from its angular headers.');
            blocks{index} = makeBlock(thetaGrid(:), phiGrid(:), matrix, [], ...
                "reim", "linear", "degrees", metadata);
        end
    case '.ffe'
        blocks = readFeko(path,metadata);
    case '.cut'
        blocks = {readGrasp(path,metadata)};
    case {'.xlsx','.xls'}
        blocks = {readMatrixWorkbook(path, metadata)};
    otherwise
        error('APAT:UnsupportedFormat', ...
            'This candidate supports headered text, UAN, explicit-order FFD, FFE, polar CUT and matrix Excel. Convert %s explicitly; unsupported vendor adapters are not guessed.', extension);
end
source = struct('Blocks', {blocks}, 'Path', string(path), 'Name', string(name), ...
    'FrequenciesHz', cellfun(@(block) block.Meta.FrequencyHz, blocks));
end

function matrix = numericRows(lines, columns)
lines = lines(lines ~= "");
rows = cell(numel(lines), 1);
for index = 1:numel(lines)
    line = regexprep(char(lines(index)), '[dD]([+-]?\d+)', 'E$1');
    [values, count, ~, next] = sscanf(line, '%f');
    assert(count == columns && isempty(strtrim(line(next:end))), ...
        'APAT:NumericRow', 'Malformed numeric row %d; expected exactly %d columns.', index, columns);
    rows{index} = values.';
end
assert(~isempty(rows), 'APAT:Empty', 'No numeric samples found.');
matrix = vertcat(rows{:});
end

function block = makeBlock(theta, phi, values, names, format, basis, phaseUnit, metadata)
block = struct('Theta', theta(:), 'Phi', phi(:), 'Fields', [], 'Values', [], ...
    'Names', strings(1,0), 'Kinds', strings(1,0), 'Meta', metadata);
if format == "gain"
    assert(size(values,2) == numel(names), 'APAT:Columns', 'Every value column needs a name.');
    block.Values = values;
    block.Names = string(names);
    block.Kinds = repmat("gain", size(block.Names));
    diagnostic = contains(lower(block.Names), ["phase","axial","plf","eirp","pfd","rms"]) ...
        | ismember(lower(block.Names), ["ar","ar_db","polsense"]);
    block.Kinds(diagnostic) = "diagnostic";
    return
end
assert(size(values,2) == 4, 'APAT:Columns', 'Field input requires exactly four value columns.');
if format == "reim"
    components = complex(values(:,[1,3]), values(:,[2,4]));
else
    phases = values(:,[2,4]);
    if phaseUnit == "degrees"
        phases = deg2rad(phases);
    end
    components = 10.^(values(:,[1,3])/20) .* exp(1i*phases);
end
if basis == "circular"
    components = [(components(:,1)+components(:,2))/sqrt(2), ...
        (components(:,1)-components(:,2))/(1i*sqrt(2))];
end
block.Fields = components;
end

function blocks = readFeko(path,metadata)
lines = strip(splitlines(string(fileread(path))));
starts = find(startsWith(lower(lines),'#frequency:'));
assert(~isempty(starts), 'APAT:FFE', 'Expected #Frequency: headers in Hz.');
stops = [starts(2:end);numel(lines)+1];
blocks = cell(1,numel(starts));
for index = 1:numel(starts)
    frequency = str2double(strip(extractAfter(lines(starts(index)),':')));
    assert(isfinite(frequency) && frequency>0, 'APAT:FFE', 'Invalid FEKO frequency.');
    metadata.FrequencyHz = frequency;
    content = lines(starts(index)+1:stops(index)-1);
    content(content=="" | startsWith(content,'#') | startsWith(content,'*')) = [];
    assert(~isempty(content), 'APAT:FFE', 'Empty FEKO frequency block.');
    columns = numel(sscanf(content(1),'%f'));
    assert(columns>=6, 'APAT:FFE', 'FEKO rows need theta, phi and four Re/Im columns.');
    matrix = numericRows(content,columns);
    metadata.Notes = "FEKO Re/Im field columns; additional gain columns retained neither as calibration nor as total gain.";
    blocks{index} = makeBlock(matrix(:,1),matrix(:,2),matrix(:,3:6),[], ...
        "reim","linear","degrees",metadata);
end
end

function block = readGrasp(path,metadata)
lines = strip(splitlines(string(fileread(path))));
lines(lines=="") = [];
parts = {};
index = 1;
while index <= numel(lines)
    header = sscanf(lines(index),'%f');
    if isempty(header)
        index = index+1;
        continue
    end
    assert(numel(header)==7, 'APAT:CUT', 'Expected a seven-number GRASP cut header.');
    count = header(3);
    validateattributes(count, {'numeric'}, {'scalar','integer','positive','<=',2e6});
    assert(header(6)==1 && header(7)==2 && ismember(header(5),[1,2]), ...
        'APAT:CUT', 'Only ICUT=1, NCOMP=2 and ICOMP=1 or 2 are supported.');
    assert(index+count <= numel(lines), 'APAT:CUT', 'Truncated GRASP cut block.');
    matrix = numericRows(lines(index+1:index+count),4);
    theta = header(1)+(0:count-1).'*header(2);
    phi = repmat(header(4),count,1);
    basis = "linear";
    if header(5)==2
        basis = "circular";
    end
    parts{end+1} = makeBlock(theta,phi,matrix,[],"reim",basis,"degrees",metadata); %#ok<AGROW>
    index = index+count+1;
end
assert(~isempty(parts), 'APAT:CUT', 'No GRASP cut blocks found.');
block = parts{1};
theta = cellfun(@(part) part.Theta,parts,'UniformOutput',false);
phi = cellfun(@(part) part.Phi,parts,'UniformOutput',false);
fields = cellfun(@(part) part.Fields,parts,'UniformOutput',false);
block.Theta = vertcat(theta{:});
block.Phi = vertcat(phi{:});
block.Fields = vertcat(fields{:});
block.Meta.Notes = "GRASP polar cuts; negative theta requires explicit signed-polar mode. No rotational symmetry is synthesized.";
end

function block = readMatrixWorkbook(path, metadata)
sheets = string(sheetnames(path));
linear = ["Etheta_Gain_dBi","Etheta_Phase_degrees","Ephi_Gain_dBi","Ephi_Phase_degrees"];
circular = ["RHCP_Gain_dBi","RHCP_Phase_degrees","LHCP_Gain_dBi","LHCP_Phase_degrees"];
basis = "linear";
required = linear;
if ~all(ismember(lower(linear), lower(sheets)))
    required = circular;
    basis = "circular";
end
assert(all(ismember(lower(required), lower(sheets))), 'APAT:Workbook', 'Required component sheets are missing.');
values = cell(1,4);
for index = 1:4
    sheet = sheets(find(strcmpi(sheets, required(index)), 1));
    cells = readcell(path, 'Sheet', char(sheet));
    assert(size(cells,1) >= 3 && size(cells,2) >= 3, 'APAT:Workbook', 'Expected a C3-origin component matrix.');
    isNumber = @(value) isnumeric(value) && isscalar(value) && isfinite(value);
    rowIndices = find(cellfun(isNumber, cells(3:end,2))) + 2;
    columnIndices = find(cellfun(isNumber, cells(2,3:end))) + 2;
    assert(~isempty(rowIndices) && ~isempty(columnIndices), 'APAT:Workbook', 'Missing numeric matrix axes.');
    assert(all(diff(rowIndices)==1) && all(diff(columnIndices)==1), 'APAT:Workbook', 'Matrix axes must be contiguous.');
    theta = cell2mat(cells(rowIndices,2));
    phi = cell2mat(cells(2,columnIndices)).';
    data = cells(rowIndices,columnIndices);
    assert(all(cellfun(@(value) isnumeric(value) && isscalar(value), data), 'all'), ...
        'APAT:Workbook', 'Missing or nonnumeric component values.');
    if index == 1
        thetaReference = theta;
        phiReference = phi;
    else
        assert(isequal(theta,thetaReference) && isequal(phi,phiReference), ...
            'APAT:Workbook', 'Every component sheet must use identical axes.');
    end
    values{index} = cell2mat(data);
end
[thetaGrid,phiGrid] = ndgrid(thetaReference,phiReference);
matrix = cellfun(@(value) value(:), values, 'UniformOutput', false);
metadata.AbsoluteGain = true;
metadata.Notes = "Workbook gain-dBi contract; theta in B3 down, phi in C2 across. Linear basis takes precedence when both are supplied.";
block = makeBlock(thetaGrid(:),phiGrid(:),horzcat(matrix{:}),[], ...
    "magphase",basis,"degrees",metadata);
end

function source = demoSource(step)
if nargin < 1
    step = 5;
end
validateattributes(step, {'numeric'}, {'scalar','real','finite','>=',1,'<=',90});
[theta,phi] = ndgrid(sampleAxis(0,180,step), (0:step:360-step).');
power = 0.03 + 8 * max(sind(theta).*cosd(phi),0).^6;
metadata = struct('Name', "Synthetic directional pattern", 'Path', "", ...
    'Format', "synthetic", 'AbsoluteGain', false, 'FrequencyHz', 1e9, ...
    'Notes', "Analytic demo, not a measured or calibrated antenna.");
fields = [sqrt(power(:)), zeros(numel(power),1)];
matrix = [real(fields(:,1)),imag(fields(:,1)),real(fields(:,2)),imag(fields(:,2))];
block = makeBlock(theta(:),phi(:),matrix,[],"reim","linear","degrees",metadata);
source = struct('Blocks',{{block}},'Path',"",'Name',metadata.Name,'FrequenciesHz',1e9);
end

% DESKTOP UI: one event boundary, one committed analysis and lazy tab rendering.
function figureHandle = launchApp()
state = struct('Source', [], 'Analysis', [], 'Busy', false, 'Revision', 0, ...
    'Jobs', {{}}, 'Graphics', [], 'GraphicKind', "", 'RenderKeys', strings(1,4));
ui = struct();
ui.Figure = uifigure('Name','APAT M8 | Refactor candidate','Position',[100,80,1240,790]);
figureHandle = ui.Figure;
root = uigridlayout(ui.Figure,[2,2]);
root.ColumnWidth = {280,'1x'};
root.RowHeight = {'1x',26};
controls = uigridlayout(root,[23,2]);
controls.Layout.Row = 1;
controls.ColumnWidth = {115,'1x'};
controls.RowHeight = repmat({27},1,23);
controls.Scrollable = 'on';
addText(controls,1,'APAT M8','FontWeight','bold','FontSize',20);
ui.Load = addButton(controls,2,'Load pattern',@(~,~) dispatch('load'));
addButton(controls,3,'Load analytic demo',@(~,~) dispatch('demo'));
ui.Path = addText(controls,4,'No source loaded','FontSize',10);
ui.Format = addChoice(controls,5,'Text values',{'gain','reim','magphase'},'gain');
ui.Basis = addChoice(controls,6,'Field basis',{'linear','circular'},'linear');
ui.Convention = addChoice(controls,7,'Coordinates',{'polar','elevation','signed-polar'},'polar');
ui.FFDOrder = addChoice(controls,8,'FFD row order',{'theta-fast','phi-fast'},'theta-fast');
ui.Frequency = addChoice(controls,9,'Frequency',{'1'},'1');
ui.Frequency.ValueChangedFcn = @(~,~) dispatch('rebuild');
ui.Step = addChoice(controls,10,'Resample (deg)',{'Native','1','2','5'},'Native');
ui.Step.ValueChangedFcn = @(~,~) dispatch('rebuild');
ui.Offset = addNumber(controls,11,'Gain offset (dB)',0,[-300,300]);
ui.Rx = addChoice(controls,12,'Receiver',{'Auto','RHCP','LHCP','Theta','Phi'},'RHCP');
ui.AR = addNumber(controls,13,'Rx AR (dB)',0,[0,300]);
ui.Tilt = addNumber(controls,14,'Rx tilt (deg)',0,[-180,180]);
ui.Power = addNumber(controls,15,'Tx power (dBW)',0,[-300,300]);
ui.Distance = addNumber(controls,16,'Distance (m)',1,[1e-9,Inf]);
ui.Calibrated = uicheckbox(controls,'Text','Override: calibrated gain','Value',false);
ui.Calibrated.Layout.Row = 17;
ui.Calibrated.Layout.Column = [1,2];
addButton(controls,18,'Apply parameters',@(~,~) dispatch('params'));
addButton(controls,19,'Re-read with input settings',@(~,~) dispatch('reread'));
addButton(controls,20,'Export pattern',@(~,~) dispatch('export'));
addText(controls,22,'Candidate: MATLAB validation pending','FontSize',10);
ui.Tabs = uitabgroup(root);
ui.Tabs.Layout.Row = 1;
ui.Tabs.Layout.Column = 2;
ui.Tabs.SelectionChangedFcn = @(~,~) dispatch('view');
titles = {'Pattern','Cuts','Data','Coverage'};
tabs = gobjects(1,4);
for index = 1:4
    tabs(index) = uitab(ui.Tabs,'Title',titles{index});
end
patternGrid = uigridlayout(tabs(1),[3,4]);
patternGrid.RowHeight = {30,30,'1x'};
ui.Component = uidropdown(patternGrid,'Items',{'E_Total_dB'},'ValueChangedFcn',@(~,~) dispatch('view'));
ui.Component.Layout.Column = [1,2];
ui.View = uidropdown(patternGrid,'Items',{'3D pattern','Angular map','3D angular'},'ValueChangedFcn',@(~,~) dispatch('view'));
ui.View.Layout.Column = [3,4];
ui.Signed = uicheckbox(patternGrid,'Text','Signed phi','ValueChangedFcn',@(~,~) dispatch('view'));
ui.Signed.Layout.Row = 2;
ui.Elevation = uicheckbox(patternGrid,'Text','Elevation labels','ValueChangedFcn',@(~,~) dispatch('view'));
ui.Elevation.Layout.Row = 2;
ui.Elevation.Layout.Column = 2;
ui.Minimum = uispinner(patternGrid,'Value',-30,'Limits',[-300,300],'ValueChangedFcn',@(~,~) dispatch('view'));
ui.Minimum.Layout.Row = 2;
ui.Minimum.Layout.Column = 3;
ui.Maximum = uispinner(patternGrid,'Value',10,'Limits',[-300,300],'ValueChangedFcn',@(~,~) dispatch('view'));
ui.Maximum.Layout.Row = 2;
ui.Maximum.Layout.Column = 4;
ui.Axes = uiaxes(patternGrid);
ui.Axes.Layout.Row = 3;
ui.Axes.Layout.Column = [1,4];
cutGrid = uigridlayout(tabs(2),[2,3]);
cutGrid.RowHeight = {32,'1x'};
ui.CutType = uidropdown(cutGrid,'Items',{'Theta','Phi'},'ValueChangedFcn',@(~,~) dispatch('view'));
ui.CutAngle = uispinner(cutGrid,'Value',0,'Limits',[-360,360],'ValueChangedFcn',@(~,~) dispatch('view'));
ui.CutInfo = uilabel(cutGrid,'Text','Full-circle cuts');
ui.CutAxes = uiaxes(cutGrid);
ui.CutAxes.Layout.Row = 2;
ui.CutAxes.Layout.Column = [1,3];
ui.CutLine = plot(ui.CutAxes,NaN,NaN,'LineWidth',1.5);
grid(ui.CutAxes,'on');
dataGrid = uigridlayout(tabs(3),[2,1]);
dataGrid.RowHeight = {160,'1x'};
ui.Metadata = uitable(dataGrid,'ColumnName',{'Metric','Value'});
ui.Data = uitable(dataGrid);
coverageGrid = uigridlayout(tabs(4),[4,6]);
coverageGrid.RowHeight = {30,30,'1x',30};
ui.ThresholdMin = uispinner(coverageGrid,'Value',-30,'Tooltip','Minimum threshold (dB)');
ui.ThresholdMax = uispinner(coverageGrid,'Value',10,'Tooltip','Maximum threshold (dB)');
ui.ThresholdStep = uispinner(coverageGrid,'Value',1,'Limits',[0.01,100],'Tooltip','Threshold step (dB)');
ui.Region = uidropdown(coverageGrid,'Items',{'sphere','cone'});
uibutton(coverageGrid,'Text','Compute','ButtonPushedFcn',@(~,~) dispatch('coverage'));
uibutton(coverageGrid,'Text','Clear','ButtonPushedFcn',@(~,~) dispatch('clear'));
ui.ConeTheta = uispinner(coverageGrid,'Value',90,'Limits',[0,180],'Tooltip','Cone polar theta (deg)');
ui.ConePhi = uispinner(coverageGrid,'Value',0,'Limits',[-360,360],'Tooltip','Cone phi (deg)');
ui.ConeHalf = uispinner(coverageGrid,'Value',45,'Limits',[0,180],'Tooltip','Cone half angle (deg)');
ui.Query = uispinner(coverageGrid,'Value',0,'Tooltip','Query threshold (dB)','ValueChangedFcn',@(~,~) dispatch('query'));
ui.QueryText = uilabel(coverageGrid,'Text','No curve yet');
ui.QueryText.Layout.Column = [5,6];
ui.CoverageAxes = uiaxes(coverageGrid);
ui.CoverageAxes.Layout.Row = 3;
ui.CoverageAxes.Layout.Column = [1,6];
grid(ui.CoverageAxes,'on');
xlabel(ui.CoverageAxes,'Threshold (dB)');
ylabel(ui.CoverageAxes,'Valid sampled solid angle (%)');
ui.CoverageInfo = uilabel(coverageGrid,'Text','Coverage uses strict gain > threshold.');
ui.CoverageInfo.Layout.Row = 4;
ui.CoverageInfo.Layout.Column = [1,4];
exportCoverage = uibutton(coverageGrid,'Text','Export curves','ButtonPushedFcn',@(~,~) dispatch('exportCoverage'));
exportCoverage.Layout.Row = 4;
exportCoverage.Layout.Column = [5,6];
ui.Status = uilabel(root,'Text','Load a supported pattern or the analytic demo.');
ui.Status.Layout.Row = 2;
ui.Status.Layout.Column = [1,2];

    function options = readOptions()
        options = optionsWithDefaults();
        options.TextFormat = string(ui.Format.Value);
        options.FieldBasis = string(ui.Basis.Value);
        options.ThetaConvention = string(ui.Convention.Value);
        options.FFDOrder = string(ui.FFDOrder.Value);
        options.FrequencyIndex = str2double(ui.Frequency.Value);
        if ~strcmp(ui.Step.Value,'Native')
            options.StepDeg = str2double(ui.Step.Value);
        end
        options.GainOffsetDB = ui.Offset.Value;
        options.RxMode = string(ui.Rx.Value);
        options.RxARDB = ui.AR.Value;
        options.RxTiltDeg = ui.Tilt.Value;
        options.TxPowerDBW = ui.Power.Value;
        options.DistanceM = ui.Distance.Value;
        options.AbsoluteGain = ui.Calibrated.Value;
        options = optionsWithDefaults(options);
    end

    function dispatch(scope)
        if state.Busy || ~isvalid(ui.Figure)
            return
        end
        state.Busy = true;
        ui.Figure.Pointer = 'watch';
        dialog = [];
        cleanup = onCleanup(@finishOperation); %#ok<NASGU>
        try
            if any(strcmp(scope,{'load','demo','reread','rebuild','params'}))
                options = readOptions();
                source = state.Source;
                if strcmp(scope,'load')
                    [file,folder] = uigetfile({'*.csv;*.txt;*.dat;*.uan;*.ffd;*.ffe;*.cut;*.xlsx;*.xls','Supported patterns'});
                    if isequal(file,0)
                        return
                    end
                    options.FrequencyIndex = 1;
                    source = readSource(fullfile(folder,file),options);
                elseif strcmp(scope,'demo')
                    source = demoSource();
                    options.FrequencyIndex = 1;
                    options.ThetaConvention = "polar";
                elseif strcmp(scope,'reread')
                    assert(~isempty(source) && strlength(source.Path)>0, 'APAT:Source', 'Load a file before re-reading.');
                    source = readSource(source.Path,options);
                end
                assert(~isempty(source), 'APAT:Source', 'Load a pattern first.');
                dialog = uiprogressdlg(ui.Figure,'Title','APAT M8','Message','Preparing pattern...', ...
                    'Indeterminate','on','Cancelable','on');
                checkpoint();
                if strcmp(scope,'params') && ~isempty(state.Analysis)
                    inputNames = ["TextFormat","FieldBasis","ThetaConvention","PhaseUnit", ...
                        "FrequencyIndex","StepDeg","PeriodicPhi","FFDOrder"];
                    for inputName = inputNames
                        options.(inputName) = state.Analysis.Options.(inputName);
                    end
                    prepared = state.Analysis.Pattern;
                    prepared.Meta.AbsoluteGain = options.AbsoluteGain ...
                        || source.Blocks{options.FrequencyIndex}.Meta.AbsoluteGain;
                    candidate = derivePattern(prepared,options);
                else
                    candidate = analyzeSource(source,options);
                end
                checkpoint();
                state.Source = source;
                state.Analysis = candidate;
                state.Revision = state.Revision + 1;
                ui.Path.Text = char(source.Name);
                ui.Frequency.Items = cellstr(string(1:numel(source.Blocks)));
                ui.Frequency.Value = char(string(options.FrequencyIndex));
                ui.Convention.Value = char(options.ThetaConvention);
                previous = ui.Component.Value;
                ui.Component.Items = fieldnames(candidate.Columns).';
                if any(strcmp(previous,ui.Component.Items))
                    ui.Component.Value = previous;
                else
                    ui.Component.Value = 'E_Total_dB';
                end
                ui.Status.Text = sprintf('%s | %d canonical samples | display peak %.3f dB | runtime validation pending', ...
                    source.Name,numel(candidate.Pattern.Theta),candidate.Peak.ValueDB);
            elseif strcmp(scope,'export')
                requireAnalysis();
                [file,folder] = uiputfile({'*.csv';'*.xlsx';'*.uan'},'Export canonical pattern');
                if ~isequal(file,0)
                    writeOutput(state.Analysis,fullfile(folder,file));
                    ui.Status.Text = ['Exported ' file];
                end
                return
            elseif strcmp(scope,'coverage')
                requireAnalysis();
                bounds = [ui.ThresholdMin.Value,ui.ThresholdMax.Value];
                assert(all(isfinite(bounds)) && diff(bounds)>0, ...
                    'APAT:Thresholds', 'Threshold bounds must be finite and increasing.');
                assert(diff(bounds)/ui.ThresholdStep.Value<=9999, ...
                    'APAT:Thresholds', 'Limit the threshold grid to 10,000 points before allocation.');
                thresholds = (ui.ThresholdMin.Value:ui.ThresholdStep.Value:ui.ThresholdMax.Value).';
                region = struct('Type',string(ui.Region.Value),'ThetaDeg',ui.ConeTheta.Value, ...
                    'PhiDeg',ui.ConePhi.Value,'HalfAngleDeg',ui.ConeHalf.Value);
                distribution = distributionFor(state.Analysis,ui.Component.Value,region);
                curve = evaluateDistribution(distribution,thresholds);
                name = sprintf('R%d %s',numel(state.Jobs)+1,ui.Component.Value);
                hold(ui.CoverageAxes,'on');
                line = stairs(ui.CoverageAxes,thresholds,curve,'LineWidth',1.5,'DisplayName',name);
                state.Jobs{end+1} = struct('Name',name,'Distribution',distribution,'Thresholds',thresholds,'Line',line);
                legend(ui.CoverageAxes,'show','Location','best');
                ui.CoverageInfo.Text = sprintf('Valid %.5g sr | missing %.5g sr | %d immutable jobs', ...
                    distribution.ValidOmega,distribution.MissingOmega,numel(state.Jobs));
                updateQuery();
                return
            elseif strcmp(scope,'query')
                updateQuery();
                return
            elseif strcmp(scope,'clear')
                for index = 1:numel(state.Jobs)
                    delete(state.Jobs{index}.Line);
                end
                state.Jobs = {};
                legend(ui.CoverageAxes,'off');
                ui.QueryText.Text = 'No curve yet';
                ui.CoverageInfo.Text = 'Coverage jobs cleared.';
                return
            elseif strcmp(scope,'exportCoverage')
                assert(~isempty(state.Jobs), 'APAT:Coverage', 'Compute a coverage curve first.');
                allThresholds = cellfun(@(job) job.Thresholds,state.Jobs,'UniformOutput',false);
                thresholds = unique(vertcat(allThresholds{:}));
                output = table(thresholds,'VariableNames',{'Threshold_dB'});
                for index = 1:numel(state.Jobs)
                    output.(sprintf('R%d_Coverage_pct',index)) = evaluateDistribution(state.Jobs{index}.Distribution,thresholds);
                end
                [file,folder] = uiputfile('*.csv','Export coverage curves');
                if ~isequal(file,0)
                    writetable(output,fullfile(folder,file));
                end
                return
            end
            renderSelected();
        catch exception
            if isvalid(ui.Figure) && ~strcmp(exception.identifier,'APAT:Cancelled')
                ui.Status.Text = ['Error: ' exception.message];
                uialert(ui.Figure,exception.message,'APAT M8','Icon','error');
            end
        end

        function checkpoint()
            drawnow;
            if ~isvalid(ui.Figure) || (~isempty(dialog) && isvalid(dialog) && dialog.CancelRequested)
                error('APAT:Cancelled','Operation cancelled; previous analysis retained.');
            end
        end

        function finishOperation()
            state.Busy = false;
            if ~isempty(dialog) && isvalid(dialog)
                close(dialog);
            end
            if isvalid(ui.Figure)
                ui.Figure.Pointer = 'arrow';
            end
        end
    end

    function requireAnalysis()
        assert(~isempty(state.Analysis), 'APAT:Source', 'Load a pattern first.');
    end

    function updateQuery()
        if isempty(state.Jobs)
            ui.QueryText.Text = 'No curve yet';
            return
        end
        value = evaluateDistribution(state.Jobs{end}.Distribution,ui.Query.Value);
        ui.QueryText.Text = sprintf('Latest: %.5g %%',value);
    end

    function renderSelected()
        if isempty(state.Analysis)
            return
        end
        selected = find(tabs == ui.Tabs.SelectedTab,1);
        component = string(ui.Component.Value);
        key = join(string([state.Revision,ui.Signed.Value,ui.Elevation.Value,ui.Minimum.Value, ...
            ui.Maximum.Value,ui.CutAngle.Value]),'|') + component + string(ui.View.Value) + string(ui.CutType.Value);
        if state.RenderKeys(selected) == key
            return
        end
        analysis = state.Analysis;
        switch selected
            case 1
                renderPattern(analysis,component);
            case 2
                cut = extractCut(analysis,ui.CutType.Value,ui.CutAngle.Value,component);
                set(ui.CutLine,'XData',cut.AngleDeg,'YData',cut.Values);
                title(ui.CutAxes,char(component),'Interpreter','none');
                xlabel(ui.CutAxes,'Physical cut angle (deg)');
                ylabel(ui.CutAxes,'Component value');
                ui.CutInfo.Text = sprintf('Snapped %.4g deg | HPBW %.4g deg',cut.FixedDeg,cut.HPBWDeg);
            case 3
                ui.Data.Data = outputTable(analysis,true);
                names = fieldnames(analysis.Metrics);
                values = struct2cell(analysis.Metrics);
                values = cellfun(@(value) char(string(value)),values,'UniformOutput',false);
                ui.Metadata.Data = [names,values];
        end
        state.RenderKeys(selected) = key;
    end

    function renderPattern(analysis,component)
        pattern = analysis.Pattern;
        isMesh = pattern.IsGrid && numel(pattern.ThetaAxis)>1 && numel(pattern.PhiAxis)>1;
        limits = [ui.Minimum.Value,ui.Maximum.Value];
        assert(diff(limits)>0, 'APAT:Range', 'The color maximum must exceed the minimum.');
        values = analysis.Columns.(component);
        values = min(max(values,limits(1)),limits(2));
        if isMesh
            theta = pattern.ThetaAxis;
            phi = pattern.PhiAxis;
            data = reshape(values,numel(theta),numel(phi));
            if ui.Signed.Value
                [phi,order] = sort(wrap180(phi));
                data = data(:,order);
            end
            if pattern.PeriodicPhi
                phi(end+1) = phi(1)+360;
                data(:,end+1) = data(:,1);
            end
            [thetaGrid,phiGrid] = ndgrid(theta,phi);
        else
            thetaGrid = pattern.Theta;
            phiGrid = pattern.Phi;
            data = values;
        end
        kind = string(ui.View.Value);
        if kind == "3D pattern"
            radius = (data-limits(1))/diff(limits);
            x = radius.*sind(thetaGrid).*cosd(phiGrid);
            y = radius.*sind(thetaGrid).*sind(phiGrid);
            z = radius.*cosd(thetaGrid);
        else
            x = phiGrid;
            if ui.Signed.Value && ~isMesh
                x = wrap180(x);
            end
            y = thetaGrid;
            if ui.Elevation.Value
                y = 90-y;
            end
            z = data;
            if kind == "Angular map"
                z = zeros(size(data));
            end
        end
        graphicKind = kind + string(isMesh);
        if isempty(state.Graphics) || ~isgraphics(state.Graphics) || state.GraphicKind ~= graphicKind
            cla(ui.Axes);
            if isMesh
                state.Graphics = surf(ui.Axes,x,y,z,data,'EdgeColor','none');
            else
                state.Graphics = scatter3(ui.Axes,x,y,z,12,data,'filled');
            end
            state.GraphicKind = graphicKind;
            colorbar(ui.Axes);
            colormap(ui.Axes,turbo(256));
        else
            set(state.Graphics,'XData',x,'YData',y,'ZData',z,'CData',data);
        end
        clim(ui.Axes,limits);
        axis(ui.Axes,'auto');
        if kind == "Angular map"
            view(ui.Axes,2);
        else
            view(ui.Axes,35,25);
        end
        if kind == "3D pattern"
            axis(ui.Axes,'equal');
            xlabel(ui.Axes,'X');
            ylabel(ui.Axes,'Y');
            zlabel(ui.Axes,'Z');
        else
            xlabel(ui.Axes,'Phi (deg)');
            ylabel(ui.Axes,'Theta / elevation (deg)');
            zlabel(ui.Axes,'Component value');
        end
        title(ui.Axes,char(component),'Interpreter','none');
    end
end

function label = addText(parent,row,text,varargin)
label = uilabel(parent,'Text',text,varargin{:});
label.Layout.Row = row;
label.Layout.Column = [1,2];
end

function button = addButton(parent,row,text,callback)
button = uibutton(parent,'Text',text,'ButtonPushedFcn',callback);
button.Layout.Row = row;
button.Layout.Column = [1,2];
end

function control = addChoice(parent,row,label,items,value)
text = uilabel(parent,'Text',label);
text.Layout.Row = row;
text.Layout.Column = 1;
control = uidropdown(parent,'Items',items,'Value',value);
control.Layout.Row = row;
control.Layout.Column = 2;
end

function control = addNumber(parent,row,label,value,limits)
text = uilabel(parent,'Text',label);
text.Layout.Row = row;
text.Layout.Column = 1;
control = uispinner(parent,'Value',value,'Limits',limits);
control.Layout.Row = row;
control.Layout.Column = 2;
end