function output = APAT_v3_M8_36(action) %AST %1450-lines
% APAT_M8 Compact research candidate. Not a feature-identical M7 replacement.
% APAT_M8                 opens the simplified application with a demo.
% api = APAT_M8('services') exposes pure numerical services for testing.
% Run test_APAT_M8 after adding this file to the MATLAB path.
% Target: MATLAB R2023b or later. MATLAB runtime validation is pending.
% Derived from ai-tal/APAT APAT_v3_M7_110_5.m; see APAT_M8_CHANGELOG.md.
if nargin > 0
    assert(strcmp(action,'services'),'apat:Action','Unknown action.');
    output = struct('read',@readPattern,'normalize',@normalizePattern, ...
        'process',@calcPattern,'resample',@resampleCanonical, ...
        'coverage',@coverageCCDF,'weights',@solidWeights, ...
        'peak',@resolvePeak,'cut',@calcCutGeometry,'hpbw',@calcHPBW);
    return
end
source = struct();
pattern = table();
weights = [];
figureHandle = uifigure('Name','APAT M8 | compact candidate','Position',[100 100 1200 760]);
output = figureHandle;
layout = uigridlayout(figureHandle,[3 1]);
layout.RowHeight = {42,'1x',30};
controls = uigridlayout(layout,[1 10]);
controls.ColumnWidth = {90,140,90,90,90,90,140,110,90,'1x'};
uibutton(controls,'Text','Load pattern','ButtonPushedFcn',@loadSource);
format = uidropdown(controls,'Items',{'gain','linear_reim','linear_magphase', ...
    'rcp_reim','rcp_magphase','lcp_reim','lcp_magphase'});
block = uidropdown(controls,'Items',{'Block 1'},'ItemsData',1,'ValueChangedFcn',@process);
offset = uispinner(controls,'Limits',[-100 100],'Value',0,'Tooltip','Gain adjustment (dB)', ...
    'ValueChangedFcn',@process);
step = uidropdown(controls,'Items',{'Native','1 degree'},'ValueChangedFcn',@process);
uibutton(controls,'Text','Process','ButtonPushedFcn',@process);
component = uidropdown(controls,'Items',{'E_Total_dB'},'ValueChangedFcn',@render);
view = uidropdown(controls,'Items',{'3D pattern','Angular map'},'ValueChangedFcn',@render);
uibutton(controls,'Text','Export CSV','ButtonPushedFcn',@export);
uilabel(controls,'Text','M8 candidate','FontColor',[0.65 0.35 0.15]);
plots = uigridlayout(layout,[2 2]);
mainAxes = uiaxes(plots);
cutAxes = uiaxes(plots);
coverageAxes = uiaxes(plots);
resultTable = uitable(plots);
status = uilabel(layout,'Text','MATLAB validation pending. Demo data; not measured antenna data.');
% A deterministic gain-only demo, with canonical physical coordinates.
[phi,theta] = meshgrid(0:5:355,0:5:180);
demo = table(theta(:),phi(:),10*log10(max(1.5*sind(theta(:)).^2,1e-12)), ...
    'VariableNames',{'Theta','Phi','E_Total_dB'});
metadata = validateSourceModel(struct('source','Analytic dipole demo','isGainOnly',true));
source = struct('blocks',{{demo}},'userData',metadata,'freqs',NaN);
process();

    function loadSource(~,~)
        [name,folder] = uigetfile({'*.csv;*.txt;*.dat;*.ffd;*.ffs;*.ffe;*.uan;*.fz;*.cut;*.out;*.xlsx;*.xls','Antenna patterns'});
        if isequal(name,0), return; end
        try
            candidate = readPattern(fullfile(folder,name),format.Value,table());
            candidate.userData = validateSourceModel(candidate.userData);
            assert(~candidate.userData.isCoverage && ~isempty(candidate.blocks), ...
                'apat:Input','Select an antenna pattern, not a coverage-results file.');
            % Commit only after parsing succeeds.
            source = candidate;
            count = numel(source.blocks);
            block.Items = cellstr(compose('Block %d',1:count));
            block.ItemsData = 1:count;
            block.Value = 1;
            process();
        catch exception
            uialert(figureHandle,exception.message,'Import failed');
        end
    end

    function process(varargin)
        try
            canonical = normalizePattern(source.blocks{block.Value});
            canonical.Properties.UserData = source.userData;
            assert(height(canonical) > 0 && all(isfinite(canonical.Theta)) && ...
                all(isfinite(canonical.Phi)),'apat:Input','Pattern contains invalid angles.');
            if strcmp(step.Value,'1 degree')
                canonical = resampleCanonical(canonical,1);
            end
            param = struct('GainLoss_dB',offset.Value,'FieldScale',10^(offset.Value/20), ...
                'RxMode',"Auto",'RxAR_dB',0,'Pt_dBW',0,'R_m',1);
            [candidate,~] = calcPattern(canonical,param,99.99,6);
            available = string(candidate.Properties.VariableNames(3:end));
            previous = string(component.Value);
            % One authoritative processed table; plots do not modify it.
            pattern = candidate;
            component.Items = cellstr(available);
            if any(available == previous), component.Value = char(previous); end
            weights = [];
            if isFullUniformSphere(pattern)
                weights = solidWeights(pattern.Theta,pattern.Phi);
            end
            render();
        catch exception
            uialert(figureHandle,exception.message,'Processing failed');
        end
    end

    function render(varargin)
        if isempty(pattern), return; end
        values = pattern.(component.Value);
        finiteValues = values(isfinite(values));
        if isempty(finiteValues)
            status.Text = 'Selected component has no finite values.';
            return
        end
        cla(mainAxes);
        switch view.Value
            case '3D pattern'
                peak = max(finiteValues);
                radius = 10.^((values-peak)/20);
                scatter3(mainAxes,radius.*sind(pattern.Theta).*cosd(pattern.Phi), ...
                    radius.*sind(pattern.Theta).*sind(pattern.Phi), ...
                    radius.*cosd(pattern.Theta),8,values,'filled');
                axis(mainAxes,'equal');
                title(mainAxes,'Relative-amplitude pattern');
                xlabel(mainAxes,'X'); ylabel(mainAxes,'Y'); zlabel(mainAxes,'Z');
            otherwise
                scatter(mainAxes,pattern.Phi,pattern.Theta,12,values,'filled');
                title(mainAxes,'Angular sample map');
                xlabel(mainAxes,'Phi (degrees)'); ylabel(mainAxes,'Theta (degrees)');
        end
        colorbar(mainAxes);
        [angle,rows] = calcCutGeometry(pattern,'Theta',0);
        plot(cutAxes,angle,values(rows),'LineWidth',1.5);
        title(cutAxes,'Phi = 0 / 180 degree cut (nearest samples)');
        xlabel(cutAxes,'Angle (degrees)'); ylabel(cutAxes,component.Value,'Interpreter','none');
        grid(cutAxes,'on');
        cla(coverageAxes);
        if isempty(weights)
            title(coverageAxes,'Coverage unavailable: full uniform grid required');
        else
            thresholds = linspace(min(finiteValues)-1,max(finiteValues)+1,201)';
            coverage = coverageCCDF(values,true(height(pattern),1),thresholds,weights);
            plot(coverageAxes,thresholds,coverage,'LineWidth',1.5);
            title(coverageAxes,'Spherical weighted coverage');
            xlabel(coverageAxes,'Threshold'); ylabel(coverageAxes,'Coverage (%)');
            ylim(coverageAxes,[0 100]); grid(coverageAxes,'on');
        end
        % Limit UI table materialization; CSV export always contains every row.
        resultTable.Data = pattern(1:min(height(pattern),500),:);
        status.Text = sprintf('%s | %d samples | preview: first 500 rows | Pt=0 dBW, R=1 m, Auto Rx AR=0 dB', ...
            source.userData.source,height(pattern));
        drawnow limitrate
    end

    function export(~,~)
        if isempty(pattern), return; end
        [name,folder] = uiputfile('*.csv','Export processed pattern','APAT_M8_results.csv');
        if isequal(name,0), return; end
        try
            writetable(pattern,fullfile(folder,name));
            status.Text = sprintf('Exported all %d samples to %s',height(pattern),name);
        catch exception
            uialert(figureHandle,exception.message,'Export failed');
        end
    end
end

function full = isFullUniformSphere(pattern)
% Do not report spherical coverage for unsupported irregular/partial grids.
theta = unique(pattern.Theta);
phi = unique(mod(pattern.Phi,360));
if numel(theta) < 2 || numel(phi) < 2
    full = false;
    return
end
dt = diff(theta);
dp = diff([phi;phi(1)+360]);
full = abs(theta(1)) < 1e-9 && abs(theta(end)-180) < 1e-9 && ...
    max(abs(dt-dt(1))) < 1e-9 && max(abs(dp-dp(1))) < 1e-9 && ...
    size(unique([pattern.Theta,mod(pattern.Phi,360)],'rows'),1) == numel(theta)*numel(phi);
end

function [nHdr, ffdParams] = findHeaderLines(fp)
%FINDHEADERLINES Detect text headers and parse optional HFSS FFD metadata.
% The HFSS FFD header is two numeric triples followed optionally by a
% Frequencies declaration.  Parse the first two non-empty lines explicitly,
% matching the proven APAT v2 reader semantics, while tolerating blank lines
% and both Frequency/Frequencies spellings.

fid = fopen(fp, 'r');
if fid < 0
    error('apat:io:OpenFailed', 'Cannot open file: %s', fp);
end
cleanup = onCleanup(@() fclose(fid));

nHdr = 0;
ffdParams = struct('theta', [], 'phi', [], 'freq', [], 'isFFD', false);

% Read the first two non-empty header lines.  fscanf is deliberately not
% used here because the optional text line after the two triples must remain
% distinguishable when determining NumHeaderLines for readmatrix.
headerTriples = zeros(0, 3);
headerLines = strings(0, 1);

while size(headerTriples, 1) < 2
    line = fgetl(fid);
    if ~ischar(line)
        break
    end

    nHdr = nHdr + 1;
    trimmed = strtrim(line);
    if isempty(trimmed)
        continue
    end

    numericValues = sscanf(trimmed, '%f').';
    if numel(numericValues) == 3
        headerTriples(end + 1, :) = numericValues; %#ok<AGROW>
        headerLines(end + 1, 1) = string(trimmed); %#ok<AGROW>
    else
        % A non-numeric line before the two FFD triples means this is not an
        % HFSS FFD header.  Keep scanning so generic readers still work.
        if isempty(headerTriples)
            break
        end
    end
end

if size(headerTriples, 1) == 2
    ffdParams.theta = struct('start', headerTriples(1, 1), 'stop', headerTriples(1, 2), 'count', round(headerTriples(1, 3)));
    ffdParams.phi = struct('start', headerTriples(2, 1), 'stop', headerTriples(2, 2), 'count', round(headerTriples(2, 3)));

    % The third non-empty header line may declare the frequency count.
    line3 = fgetl(fid);
    while ischar(line3) && isempty(strtrim(line3))
        nHdr = nHdr + 1;
        line3 = fgetl(fid);
    end

    if ischar(line3)
        nHdr = nHdr + 1;
        tokens = regexp(strtrim(line3), '^frequencies?\s+(.+)$', 'tokens', 'once', 'ignorecase');
        if ~isempty(tokens)
            frequencyValues = sscanf(tokens{1}, '%f').';
            if isscalar(frequencyValues)
                % Some HFSS files use "Frequencies N" while the actual
                % frequencies occur on separator rows in the data section.
                % Preserve the count only as metadata; separator rows remain
                % the authoritative frequency values below.
                ffdParams.freq = [];
            else
                ffdParams.freq = frequencyValues(:);
            end
        else
            % The line belongs to the data section.  Rewind to its beginning
            % so readmatrix can consume it when NumHeaderLines is determined.
            nHdr = nHdr - 1;
        end
    end

    ffdParams.isFFD = all(isfinite([ ...
        ffdParams.theta.start, ffdParams.theta.stop, ffdParams.theta.count, ...
        ffdParams.phi.start, ffdParams.phi.stop, ffdParams.phi.count])) && ...
        ffdParams.theta.count >= 1 && ffdParams.phi.count >= 1;
end

if ~ffdParams.isFFD
    % Generic readers still need the number of leading non-data lines.  Find
    % the first line that contains at least four numeric fields.
    frewind(fid);
    nHdr = 0;
    dataPattern = ['^\s*[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?' ...
        '(?:[\s,;]+[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?){3,}\s*$'];
    while true
        pos = ftell(fid); %#ok<NASGU>
        line = fgetl(fid);
        if ~ischar(line)
            break
        end
        if ~isempty(regexp(line, dataPattern, 'once'))
            break
        end
        nHdr = nHdr + 1;
    end
end
end

function out = readPattern(fp, textFormat, tableData)
%APAT.IO.READPATTERN Read APAT-supported pattern/coverage source files.
%   Returns a source adapter struct with rawTbl, blocks, freqs, and userData.
%   This function is UI-independent and intentionally preserves the M2
%   reader semantics while establishing the M3 I/O boundary.

if nargin < 3 || isempty(tableData)
    tableData = table();
end
textFormat = string(textFormat);

    % Universal loader → standardized table {Theta,Phi,Re_Eth,Im_Eth,Re_Eph,Im_Eph} (or gain/coverage table) + raw data + info
    [~, ~, ext] = fileparts(fp);
    ext = upper(erase(ext, '.'));
    out = struct('rawTbl', table(), 'blocks', {{}}, 'freqs', NaN, 'userData', struct('source', ext, 'isGainOnly', false, 'isCoverage', false, 'isDep', false,'isMultiBlock', false,'hasFrequency', false));

    % ---- Excel matrix antenna-pattern workbooks
    if ismember(ext, {'XLSX','XLS'})
        out = readExcelMatrix(fp);
        out.userData = validateSourceModel(out.userData);
        return
    end

    % ---- Generic text tables: gain-only pattern OR coverage results
    if ismember(ext, {'CSV','TXT','DAT'})
        if isempty(tableData)
            opts = detectImportOptions(fp, FileType = 'text', Delimiter = {' ','\t',',',';'}, ConsecutiveDelimitersRule = 'join', LeadingDelimitersRule = 'ignore');
            opts = setvartype(opts, 'double');
            opts = setvaropts(opts, 'TrimNonNumeric', true);
            opts.VariableNamingRule = 'preserve';
            tableData = rmmissing(readtable(fp, opts));
        end
        columnCount = width(tableData); assert(columnCount >= 2 && ~isempty(tableData), ...
            'readFile:InvalidFormat', 'File needs at least two numeric columns.');
        originalTable = tableData; variableNames = string(tableData.Properties.VariableNames); lowerNames = lower(variableNames); hasHeaders = ~all(startsWith(variableNames, "Var"));

        % Detect coverage before applying any selected pattern interpretation.
        firstColumn = tableData{:, 1}; secondColumn = tableData{:, 2};
        coverageHeader = contains(lowerNames(1), "threshold") || any(contains(lowerNames(2:end), "coverage"));
        canBeCoverage = textFormat == "gain" || columnCount < 6 || coverageHeader;
        isCoverage = canBeCoverage && all(isfinite(secondColumn)) && all(secondColumn >= 0 & secondColumn <= 100) && issorted(firstColumn, 'strictmonotonic');
        if isCoverage
            if ~hasHeaders
                tableData.Properties.VariableNames = [{'Threshold_dB'}, cellstr(compose('Coverage_%d', 1:columnCount - 1))];
            end
            out.rawTbl = tableData;
            out.userData.isCoverage = true;
            return
        end

        if textFormat == "gain"
            % Gain-only pattern: infer which of the first two columns spans phi.
            firstSpan = max(firstColumn) - min(firstColumn);
            secondSpan = max(secondColumn) - min(secondColumn);
            if firstSpan > secondSpan
                tableData.Properties.VariableNames(1:2) = {'Phi', 'Theta'};
            else
                tableData.Properties.VariableNames(1:2) = {'Theta', 'Phi'};
            end
            tableData = movevars(tableData, 'Theta', 'Before', 1);
            if ~hasHeaders, originalTable = tableData; end
            out.rawTbl = originalTable;
            out.blocks = {tableData};
            out.userData.isGainOnly = true;
            return
        end

        assert(columnCount >= 6, 'readFile:TextEFieldColumns', 'The selected generic E-field format requires six numeric columns.');
        values = tableData{:, 1:6};
        thetaData = values(:, 1);
        phiData = values(:, 2);
        fieldValues = values(:, 3:6);
        isMagnitudePhase = endsWith(textFormat, "magphase");
        isLinear = startsWith(textFormat, "linear");
        detectedLayout = "not applicable";
        if isMagnitudePhase
            phaseCandidate = max(abs(fieldValues), [], 1, 'omitnan') > 100;
            if phaseCandidate(2) && ~phaseCandidate(3)
                magnitudeColumns = [1, 3]; phaseColumns = [2, 4];
                detectedLayout = "interleaved";
            else
                magnitudeColumns = [1, 2]; phaseColumns = [3, 4];
                detectedLayout = "grouped";
            end
            magnitude = fieldValues(:, magnitudeColumns);
            phase = fieldValues(:, phaseColumns);
            component1 = 10.^(magnitude(:, 1) / 20) .* exp(1i * deg2rad(phase(:, 1)));
            component2 = 10.^(magnitude(:, 2) / 20) .* exp(1i * deg2rad(phase(:, 2)));
        else
            component1 = complex(fieldValues(:, 1), fieldValues(:, 2));
            component2 = complex(fieldValues(:, 3), fieldValues(:, 4));
        end

        if isLinear
            [Etheta, Ephi] = deal(component1, component2);
            [componentNames, rectangularNames] = deal(["E_TH", "E_PH"], ["Re_Eth", "Im_Eth", "Re_Eph", "Im_Eph"]);
        else
            if startsWith(textFormat, "rcp"), [Ercp, Elcp] = deal(component1, component2);
            else, [Elcp, Ercp] = deal(component1, component2);
            end
            Etheta = (Ercp + Elcp) / sqrt(2);
            Ephi = (Ercp - Elcp) / (1i * sqrt(2));
            [componentNames, rectangularNames] = deal(["POL1", "POL2"], ["POL1_real", "POL1_imag", "POL2_real", "POL2_imag"]);
        end

        if isMagnitudePhase
            fieldNames = [componentNames + "_dB", componentNames + "_deg"];
            if detectedLayout == "interleaved", fieldNames = fieldNames([1, 3, 2, 4]); end
        else
            fieldNames = rectangularNames;
        end
        generatedNames = cellstr(["Theta", "Phi", fieldNames]);
        if ~hasHeaders
            originalTable.Properties.VariableNames(1:6) = generatedNames;
        end

        out.userData.source = sprintf('Generic text (%s, %s)', textFormat, detectedLayout);
        out.rawTbl = originalTable;
        out.blocks = {table(thetaData, phiData, real(Etheta), imag(Etheta), real(Ephi), imag(Ephi), ...
            'VariableNames', {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'})};
        return
    end

    % ---- TICRA/GRASP cuts (block structured, parsed line-by-line)
    if strcmp(ext, 'CUT') % GRASP *.cut: repeated blocks of [title; V_INI V_INC V_NUM C ICOMP ICUT NCOMP; data]
        % First two cols = V‑Nr, H‑Nr ⟶ skip, next two = re/im pairs
        % Standard GRASP .cut: theta  Re(Eco) Im(Eco) Re(Ecx) Im(Ecx) | The Phi value is in the header; each block = one phi.
        out.userData.source = 'TICRA/GRASP CUT';

        lines = readlines(fp); lines(strlength(strtrim(lines)) == 0) = [];
        thetaBlocks = {}; phiBlocks = {}; dataBlocks = {};
        componentCode = 1; cutCode = 1; lineIndex = 1;
        while lineIndex < numel(lines)
            cutParams = sscanf(lines(lineIndex + 1), '%f');
            assert(numel(cutParams) >= 7, 'parseCutFile:bad', 'Could not parse cut parameter line.');
            angleCount = cutParams(3); componentCode = cutParams(5); cutCode = cutParams(6);
            valuesPerLine = 2 * cutParams(7);
            blockData = reshape(sscanf(strjoin( lines(lineIndex + 2:lineIndex + 1 + angleCount), ' '), '%f'), valuesPerLine, []).';
            thetaBlocks{end + 1, 1} = cutParams(1) + (0:angleCount - 1)' * cutParams(2); %#ok<AGROW>
            phiBlocks{end + 1, 1} = repmat(cutParams(4), angleCount, 1); %#ok<AGROW>
            dataBlocks{end + 1, 1} = blockData(:, 1:4); %#ok<AGROW>
            lineIndex = lineIndex + 2 + angleCount;
        end
        thetaData = vertcat(thetaBlocks{:});
        phiData = vertcat(phiBlocks{:});
        numericData = vertcat(dataBlocks{:});
        if cutCode == 2, [thetaData, phiData] = deal(phiData, thetaData); end % ICUT=2: phi swept, theta constant
        negativeTheta = thetaData < 0; % fold negative theta onto opposite phi
        phiData(negativeTheta) = phiData(negativeTheta) + 180; thetaData(negativeTheta) = -thetaData(negativeTheta);
        if isscalar(unique(phiData)) % single cut → body of revolution
            phiCopies = (0:10:350)'; sampleCount = numel(thetaData);
            thetaData = repmat(thetaData, numel(phiCopies), 1);
            phiData = repelem(phiCopies, sampleCount);
            numericData = repmat(numericData, numel(phiCopies), 1);
        end

        if componentCode == 2 % circular RHCP/LHCP
            out.rawTbl = table(thetaData, phiData, numericData(:, 1), numericData(:, 2), numericData(:, 3), numericData(:, 4), 'VariableNames', {'Theta','Phi','Re_RHCP','Im_RHCP','Re_LHCP','Im_LHCP'});
            Ercp = complex(numericData(:, 1), numericData(:, 2));
            Elcp = complex(numericData(:, 3), numericData(:, 4));
            Eth = (Ercp + Elcp) ./ sqrt(2);
            Eph = (Ercp - Elcp) ./ (1i*sqrt(2));
        else % linear co/cx -> Etheta/Ephi
            out.rawTbl = table(thetaData, phiData, numericData(:, 1), numericData(:, 2), numericData(:, 3), numericData(:, 4), 'VariableNames', {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'});
            Eth = complex(numericData(:, 1), numericData(:, 2));
            Eph = complex(numericData(:, 3), numericData(:, 4));
        end
        out.blocks = {table(thetaData(:), phiData(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'})};
        return;
    end

    % ---- E-field far-field files
    [nHdr, ffdParams] = findHeaderLines(fp);
    opts = detectImportOptions(fp, FileType = 'text', NumHeaderLines = nHdr, Delimiter = {' ', '\t', ',', ';'}, ConsecutiveDelimitersRule = 'join', LeadingDelimitersRule = 'ignore');
    opts = setvartype(opts, opts.VariableNames, 'double');
    numericData = readmatrix(fp, opts);
    numericData = numericData(~all(isnan(numericData), 2), :); numericData = numericData(:, 1:min(size(numericData, 2), 6));

    switch ext
        case {'FZ','UAN'} % XGTD *.uan/*.fz | Format: Theta	Phi	E_TH_dB	E_PH_dB	E_TH_deg	E_PH_deg
            out.userData.source = sprintf('XGTD %s', ext);
            out.rawTbl = array2table(numericData(:, 1:6), 'VariableNames', {'Theta','Phi','E_TH_dB','E_PH_dB','E_TH_deg','E_PH_deg'});
            thetaData = numericData(:, 1); phiData = numericData(:, 2);
            Eth = 10 .^ (numericData(:, 3) ./ 20) .* exp(1i*deg2rad(numericData(:, 5))); % E_TH_mag = 10^(E_TH_dB/20)
            Eph = 10 .^ (numericData(:, 4) ./ 20) .* exp(1i*deg2rad(numericData(:, 6))); % E_PH_mag = 10^(E_PH_dB/20)

        case 'OUT' % TICRA/GRAP *.out | Format: THETA	PHI	POL-1,real	POL-1,imag	POL-2,real	POL-2,imag (default POL-1/POL-2 are RHCP/LHCP)
            out.userData.source = 'TICRA/GRASP OUT';
            out.rawTbl = array2table(numericData(:, 1:6), 'VariableNames', {'Theta','Phi','Re_RHCP','Im_RHCP','Re_LHCP','Im_LHCP'});
            thetaData = numericData(:, 1); phiData = numericData(:, 2);
            Ercp = complex(numericData(:, 3), numericData(:, 4));
            Elcp = complex(numericData(:, 5), numericData(:, 6));
            Eth = (Ercp + Elcp) ./ sqrt(2);
            Eph = (Ercp - Elcp) ./ (1i * sqrt(2));

        case 'FFS' % CST *.ffs | Format: Phi	Theta	Re(E-TH)	Im(E-TH)	Re(E-PH)	Im(E-PH)
            out.userData.source = 'CST FFS';
            out.rawTbl = array2table(numericData(:, 1:6), 'VariableNames', {'Phi','Theta','Re_Eth','Im_Eth','Re_Eph','Im_Eph'});
            phiData = numericData(:, 1); thetaData = numericData(:, 2);
            Eth = complex(numericData(:, 3), numericData(:, 4));
            Eph = complex(numericData(:, 5), numericData(:, 6));

        case 'FFE' % Feko *.out | Format: Theta	Phi	Re(E-TH)	Im(E-TH)	Re(E-PH)	Im(E-PH)  | Additional columns to be ignored
            out.userData.source = 'FEKO FFE';
            out.rawTbl = array2table(numericData(:, 1:6),'VariableNames', {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'});
            thetaData = numericData(:, 1); phiData = numericData(:, 2);
            Eth = complex(numericData(:, 3), numericData(:, 4));
            Eph = complex(numericData(:, 5), numericData(:, 6));

        case 'FFD' % HFSS *.FFD | Format: Re(E-TH)	Im(E-TH)	Re(E-PH)	Im(E-PH)
            out.userData.source = 'HFSS FFD';
            assert(ffdParams.isFFD, 'readFile:ffd', 'FFD header (theta/phi ranges) not found.');
            thetaAxis = linspace(ffdParams.theta.start, ffdParams.theta.stop, ffdParams.theta.count).';
            phiAxis = linspace(ffdParams.phi.start, ffdParams.phi.stop, ffdParams.phi.count).';
            thetaData = repelem(thetaAxis, numel(phiAxis)); phiData = repmat(phiAxis, numel(thetaAxis), 1);

            sepMask = isnan(numericData(:, 1)); % "Frequency <f>" separator rows
            separatorFreqs = numericData(sepMask, 2);
            freqs = [ffdParams.freq; separatorFreqs(~isnan(separatorFreqs))].';
            fieldRows = numericData(~sepMask, 1:4);

            pointsPerBlock = numel(thetaAxis) * numel(phiAxis);
            assert(mod(size(fieldRows, 1), pointsPerBlock) == 0, 'FFD mismatch: row count does not match theta/phi grid');
            blockCount = size(fieldRows, 1)/pointsPerBlock;
            out.userData.isMultiBlock = blockCount>1;
            out.userData.hasFrequency = ~isempty(freqs) && any(isfinite(freqs));
            out.userData.isDep = out.userData.isMultiBlock || out.userData.hasFrequency;

            % Check if Frequency Dependent FFD (if file specify frequency(ies) or not)
            if isempty(freqs), freqs = NaN(1, blockCount); end
            freqs(end+1:blockCount) = NaN; freqs = freqs(1:blockCount); % Align frequency metadata to blocks

            blocks = mat2cell(fieldRows, repmat(pointsPerBlock, blockCount, 1), 4);
            out.blocks = cellfun(@(blockValues) table(thetaData, phiData, blockValues(:, 1), blockValues(:, 2), blockValues(:, 3), blockValues(:, 4), 'VariableNames', {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'}), blocks, 'UniformOutput', false);
            out.freqs = freqs;
            out.rawTbl = out.blocks{1};
            return;

        otherwise, error('readFile:unsupported','Unsupported format: %s', ext);
    end
    out.blocks = {table(thetaData(:), phiData(:), real(Eth(:)), imag(Eth(:)), real(Eph(:)), imag(Eph(:)), 'VariableNames', {'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'})};
end

% Excel Matrix reader.
function out = readExcelMatrix(fp)
%APAT_IO_READEXCELMATRIX Read the supplied antenna-pattern Excel matrix formats.
%   Supported workbook families:
%     Format 1 / linear Eth/Eph sheets: Etheta/Ephi gain+phase matrices.
%     Format 2 / circular RHCP/LHCP sheets: RHCP/LHCP gain+phase matrices.
%     Format 3 / both component-sheet families: both circular and linear matrices.
%
%   Matrix convention in the supplied templates:
%     row 2, columns C onward = phi [deg]
%     column B, rows 3 onward = theta [deg]
%     C3 = first data sample.
%
%   The reader converts every supported source to APAT's canonical complex
%   Etheta/Ephi representation.  The original matrix values are retained in
%   rawTbl as a long table, while workbook metadata is retained in userData.

    if ~(isfile(fp))
        error('readFile:ExcelNotFound','Excel matrix file does not exist: %s',fp);
    end

    try
        sheets = string(sheetnames(fp));
    catch ME
        error('readFile:ExcelSheets','Unable to inspect Excel workbook "%s": %s',fp,ME.message);
    end

    % The first worksheet is the workbook summary; its display name is not part
    % of the format contract.  Only the component worksheet names are fixed.
    summarySheet = sheets(1);
    circular = ["RHCP_Gain_dBi","RHCP_Phase_degrees", "LHCP_Gain_dBi","LHCP_Phase_degrees"];
    linear = ["Etheta_Gain_dBi","Etheta_Phase_degrees", "Ephi_Gain_dBi","Ephi_Phase_degrees"];
    hasCircular = all(ismember(lower(circular), lower(sheets)));
    hasLinear = all(ismember(lower(linear), lower(sheets)));
    if hasLinear && hasCircular
        formatName = "Excel Matrix Format 3 (Ercp/Elcp + Eth/Eph)";
        required = [circular linear];
    elseif hasLinear
        formatName = "Excel Matrix Format 1 (Eth/Eph)";
        required = linear;
    elseif hasCircular
        formatName = "Excel Matrix Format 2 (Ercp/Elcp)";
        required = circular;
    else
        error('readFile:ExcelMatrixFormat', ...
            ['Unsupported Excel workbook. The first worksheet is treated as the ', ...
             'summary; the remaining worksheets must contain the fixed Eth/Eph ', ...
             'and/or RHCP/LHCP component sheets.']);
    end

    optional = string.empty;

    % Read each component matrix.  The helper trims the template's protected/
    % formatted area and validates that all sheets share exactly the same grid.
    matrices = struct();
    thetaRef = [];
    phiRef = [];
    for k = 1:numel(required)
        sheet = sheets(find(strcmpi(sheets,required(k)),1));
        [theta,phi,data] = readExcelMatrixSheet(fp,sheet);
        if isempty(thetaRef)
            thetaRef = theta;
            phiRef = phi;
        else
            if numel(theta) ~= numel(thetaRef) || numel(phi) ~= numel(phiRef) || ...
                    any(abs(theta(:)-thetaRef(:)) > 1e-9) || any(abs(phi(:)-phiRef(:)) > 1e-9)
                error('readFile:ExcelMatrixGrid', 'All Excel Matrix component sheets must use the same theta/phi grid.');
            end
        end
        matrices.(matlab.lang.makeValidName(required(k))) = data;
    end

    % Reconstruct complex field components.  The workbook quantities are dBi
    % magnitude and degrees phase, as specified by the supplied templates.
    if hasLinear
        Eth = 10.^(matrices.Etheta_Gain_dBi/20) .* exp(1i*deg2rad(matrices.Etheta_Phase_degrees));
        Eph = 10.^(matrices.Ephi_Gain_dBi/20) .* exp(1i*deg2rad(matrices.Ephi_Phase_degrees));
        suppliedBasis = "theta-phi";
        formatCode = "Format1";
        if hasCircular, suppliedBasis = "theta-phi + RHCP/LHCP"; formatCode = "Format3"; end
    else
        Ercp = 10.^(matrices.RHCP_Gain_dBi/20) .* exp(1i*deg2rad(matrices.RHCP_Phase_degrees));
        Elcp = 10.^(matrices.LHCP_Gain_dBi/20) .* exp(1i*deg2rad(matrices.LHCP_Phase_degrees));
        Eth = (Ercp + Elcp) ./ sqrt(2);
        Eph = (Ercp - Elcp) ./ (1i*sqrt(2));
        suppliedBasis = "RHCP/LHCP";
        formatCode = "Format2";
    end

    % Build a long raw table with the actual workbook quantities.  This keeps
    % Input/Data inspection useful without exposing the Excel sheet layout to
    % the rest of APAT.
    thetaGrid = repmat(thetaRef(:),1,numel(phiRef));
    phiGrid = repmat(phiRef(:).',numel(thetaRef),1);
    raw = table(thetaGrid(:),phiGrid(:),real(Eth(:)),imag(Eth(:)),real(Eph(:)),imag(Eph(:)), ...
        'VariableNames',{'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'});

    for k = 1:numel(required), raw.(matlab.lang.makeValidName(required(k))) = matrices.(matlab.lang.makeValidName(required(k)))(:); end

    block = table(thetaGrid(:),phiGrid(:),real(Eth(:)),imag(Eth(:)),real(Eph(:)),imag(Eph(:)), ...
        'VariableNames',{'Theta','Phi','Re_Eth','Im_Eth','Re_Eph','Im_Eph'});

    metadata = readExcelSummary(fp,summarySheet);
    metadata.source = char(formatName);
    metadata.format = formatCode;
    metadata.file = fp;
    metadata.summarySheet = char(summarySheet);
    metadata.isGainOnly = false;
    metadata.isCoverage = false;
    metadata.isDep = false;
    metadata.isMultiBlock = false;
    metadata.hasFrequency = isfield(metadata,'frequencyMHz') && isfinite(metadata.frequencyMHz);
    metadata.quantityType = "complex-electric-field";
    metadata.absoluteCalibration = true;
    metadata.polarizationBasis = suppliedBasis;
    metadata.matrixGrid = struct('thetaDeg',thetaRef(:),'phiDeg',phiRef(:), 'thetaStepDeg',gridStep(thetaRef),'phiStepDeg',gridStep(phiRef));
    metadata.componentSheets = cellstr(required);
    metadata.optionalComponentSheets = cellstr(optional);

    out = struct('rawTbl',raw,'blocks',{{block}},'freqs',NaN,'userData',metadata);
end

function [theta,phi,data] = readExcelMatrixSheet(fp,sheet)
%APAT_IO_READEXCELMATRIXSHEET Read one C3-origin matrix and trim template area.
    % readcell is deliberate here: readmatrix may auto-detect/trim the
    % spreadsheet data region, which would destroy the template's C3-origin
    % coordinate convention.  readcell preserves the worksheet coordinates.
    try
        C = readcell(fp,'Sheet',char(sheet));
    catch ME
        error('readFile:ExcelMatrixRead','Unable to read Excel matrix sheet "%s": %s',sheet,ME.message);
    end
    if size(C,1) < 3 || size(C,2) < 3
        error('readFile:ExcelMatrixSheet','Sheet "%s" does not contain a C3-origin matrix.',sheet);
    end

    phiCells = C(2,3:end);
    thetaCells = C(3:end,2);
    phiMask = cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x),phiCells);
    thetaMask = cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x),thetaCells);
    phi = cellfun(@double,phiCells(phiMask));
    theta = cellfun(@double,thetaCells(thetaMask));
    if isempty(theta) || isempty(phi)
        error('readFile:ExcelMatrixSheet','Sheet "%s" has no numeric theta/phi axes.',sheet);
    end

    % The templates require contiguous axes.  Reject a hole rather than
    % silently compressing the grid and shifting matrix samples.
    firstGap = find(~phiMask,1,'first');
    if ~isempty(firstGap) && any(phiMask(firstGap+1:end))
        error('readFile:ExcelMatrixAxis','Sheet "%s" has a gap in the phi axis.',sheet);
    end
    firstGap = find(~thetaMask,1,'first');
    if ~isempty(firstGap) && any(thetaMask(firstGap+1:end))
        error('readFile:ExcelMatrixAxis','Sheet "%s" has a gap in the theta axis.',sheet);
    end

    nTheta = numel(theta);
    nPhi = numel(phi);
    dataCells = C(3:2+nTheta,3:2+nPhi);
    dataNumericMask = cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x),dataCells);
    if ~all(dataNumericMask(:))
        error('readFile:ExcelMatrixSheet','Sheet "%s" contains nonnumeric/missing matrix samples.',sheet);
    end
    data = cellfun(@double,dataCells);

    if any(diff(theta) <= 0) || any(diff(phi) <= 0)
        error('readFile:ExcelMatrixAxis','Sheet "%s" must have strictly increasing theta/phi axes.',sheet);
    end
    if theta(1) < -1e-9 || theta(end) > 180+1e-9 || phi(1) < -1e-9 || phi(end) >= 360+1e-9
        error('readFile:ExcelMatrixAxis','Sheet "%s" has angles outside the required [theta 0..180, phi 0..360) domain.',sheet);
    end
end

function metadata = readExcelSummary(fp,sheet)
%APAT_IO_READEXCELSUMMARY Read the supplied Matrix-template summary sheet.
%   The templates intentionally use a fixed summary layout.  Use an explicit
%   worksheet range so readcell cannot collapse trailing columns that contain
%   labels/values only in later rows (notably the Frame Definition H column).
%   All matching is whitespace/case tolerant and Unicode punctuation tolerant.
    metadata = struct();
    try
        % The summary metadata used by APAT is contained in columns A:H.
        % Reading an explicit range is important: readcell may otherwise return
        % a 7-column cell array when the last populated column is sparse.
        C = readcell(fp,'Sheet',char(sheet),'Range','A1:H70');
    catch ME
        error('readFile:ExcelSummary','Unable to read Excel summary sheet "%s": %s',sheet,ME.message);
    end

    % General B-column labels with their value in C/D/E when present.
    for r = 1:size(C,1)
        label = C{r,2};
        if ~(ischar(label) || isstring(label)), continue; end
        label = strtrim(string(label));
        if strlength(label) == 0, continue; end
        value = summaryRowValue(C,r);
        if isempty(value), continue; end
        key = lower(regexprep(label,'[^a-zA-Z0-9]+','_'));
        key = matlab.lang.makeValidName(key);
        if strlength(key)>0
            metadata.(key) = value;
        end
    end

    % Stable, normalized fields used by APAT and useful to callers.
    metadata.patternDescription = summaryValue(C,'Pattern Description:');
    metadata.elementModelNumber = summaryValue(C,'Element Model Number:');
    metadata.elementModelName = summaryValue(C,'Element Model Name:');
    metadata.elementPolarization = summaryValue(C,'Element Polarization:');
    metadata.bandName = summaryValue(C,'Pattern Simulation Band name:');
    metadata.frequencyMHz = summaryNumeric(C,'Pattern Simulation Freq (MHz):');
    metadata.validFrequencyMinMHz = summaryNumeric(C,'Lowest Frequency at which the pattern data in this Excel can be deemed valid (MHz):');
    metadata.validFrequencyMaxMHz = summaryNumeric(C,'Highest Frequency at which the pattern data in this Excel can be deemed valid (MHz):');
    metadata.numberOfAntennas = summaryNumeric(C,'Number of Antennas (1 for single, 2 for pair, …):');
    metadata.patternType = summaryValue(C,'Pattern Type : Receive (Rx), Transmit (Tx), Transmit/Receive (TRx)');
    metadata.templateRevision = summaryValue(C,'Template Revision:');
    metadata.author = summaryValue(C,'Author:');
    metadata.revision = summaryValue(C,'Revision:');
    metadata.serialNumber = summaryValue(C,'S/N:');

    % Angular-step table.  The component rows use columns C/D for theta/phi.
    stepRows = { ...
        'RHCP_Gain_dBi:', 'RHCP_Phase_degrees:', 'LHCP_Gain_dBi:', 'LHCP_Phase_degrees:', ...
        'Etheta_Gain_dBi:', 'Etheta_Phase_degrees:', 'Ephi_Gain_dBi:', 'Ephi_Phase_degrees:'};
    steps = NaN(numel(stepRows),2);
    for k = 1:numel(stepRows)
        idx = findSummaryLabel(C,stepRows{k});
        if ~isempty(idx)
            steps(k,1) = toDouble(C{idx,3});
            steps(k,2) = toDouble(C{idx,4});
        end
    end
    metadata.componentStepRows = steps;

    % Frame-definition block: F=label, G=Az/expression, H=El/handedness.
    % Do NOT assume H exists in the automatically detected readcell extent.
    frame = struct();
    frame.azEl = NaN(3,2);
    frame.names = ["+X direction" "+Y direction" "+Z direction"];
    for k = 1:3
        idx = findSummaryLabel(C,frame.names(k));
        if ~isempty(idx)
            frame.azEl(k,1) = toDouble(C{idx,7});
            frame.azEl(k,2) = toDouble(C{idx,8});
        end
    end
    motionIdx = findSummaryLabel(C,'Motion direction');
    if ~isempty(motionIdx), frame.motionDirection = C{motionIdx,7}; else, frame.motionDirection = []; end
    vehicleIdx = findSummaryLabel(C,'Vehicle String');
    if ~isempty(vehicleIdx), frame.vehicleString = C{vehicleIdx,7}; else, frame.vehicleString = []; end
    handIdx = findSummaryLabel(C,'(az, el) => X conversion');
    if ~isempty(handIdx)
        frame.XExpression = C{handIdx,7};
        if handIdx+1 <= size(C,1), frame.YExpression = C{handIdx+1,7}; end
        if handIdx+2 <= size(C,1), frame.ZExpression = C{handIdx+2,7}; end
        frame.handedness = C{handIdx,8};
    end
    metadata.frameDefinition = frame;

    % Antenna positions: C/D/E on rows beginning at the location label.
    nAnt = metadata.numberOfAntennas;
    if isfinite(nAnt) && nAnt >= 1
        positions = NaN(round(nAnt),3);
        startRow = findSummaryLabel(C,'Antenna locations as list of (X, Y, Z) [Inches]:');
        if ~isempty(startRow)
            for k = 1:size(positions,1)
                rr = startRow + k - 1;
                if rr <= size(C,1)
                    positions(k,:) = [toDouble(C{rr,3}),toDouble(C{rr,4}),toDouble(C{rr,5})];
                end
            end
        end
        metadata.antennaPositionsInches = positions;
    else
        metadata.antennaPositionsInches = zeros(0,3);
    end
end

function value = summaryValue(C,label)
    idx = findSummaryLabel(C,label);
    if isempty(idx), value = []; return; end
    value = summaryRowValue(C,idx);
end

function value = summaryRowValue(C,row)
% Return the first meaningful value after the label cell in a summary row.
% For ordinary B-column fields this is C/D/E; for frame rows the caller reads
% G/H explicitly because those columns have semantic meaning.
    value = [];
    for c = 3:min(size(C,2),5)
        if ~isempty(C{row,c})
            value = C{row,c};
            return
        end
    end
end

function value = summaryNumeric(C,label)
    value = toDouble(summaryValue(C,label));
end

function idx = findSummaryLabel(C,label)
    idx = [];
    target = normalizeSummaryLabel(label);
    for r = 1:size(C,1)
        for c = 1:min(size(C,2),8)
            v = C{r,c};
            if ischar(v) || isstring(v)
                if normalizeSummaryLabel(v) == target
                    idx = r;
                    return
                end
            end
        end
    end
end

function value = normalizeSummaryLabel(value)
% Normalize labels without changing their meaning.  This handles Excel's
% non-breaking spaces, typographic punctuation and harmless whitespace.
    value = lower(strtrim(string(value)));
    value = replace(value,char(160),' ');
    value = replace(value,[char(8211),char(8212),char(8722)],'-');
    value = replace(value,char(8230),'...');
    value = regexprep(value,'\s+',' ');
    value = regexprep(value,'\s*:\s*$',':');
end

function value = toDouble(value)
    if isnumeric(value)
        if isempty(value), value = NaN; else, value = double(value(1)); end
    elseif ischar(value) || isstring(value)
        value = str2double(strtrim(string(value)));
    else
        value = NaN;
    end
end

function coverage = coverageCCDF(gain, regionMask, thresholds, solidAngle)
% Weighted strict CCDF, O(N log N + K log N) time, O(N + K) storage.
% Sort once; a suffix sum avoids cancellation in small upper tails.
    gain = double(gain(:));
    solidAngle = double(solidAngle(:));
    regionMask = logical(regionMask(:));
    thresholds = double(thresholds(:));
    assert(numel(gain) == numel(solidAngle) && numel(gain) == numel(regionMask), ...
        'apat:coverage:Shape', 'Gain, region and weight lengths must match.');
    valid = regionMask & isfinite(gain) & isfinite(solidAngle) & solidAngle >= 0;
    [sortedGain, order] = sort(gain(valid));
    weights = solidAngle(valid);
    weights = weights(order);
    coverage = zeros(size(thresholds));
    coverage(isnan(thresholds)) = NaN;
    if isempty(weights) || max(weights) <= 0
        return
    end
    weights = weights / max(weights);
    tail = [flipud(cumsum(flipud(weights))); 0];
    count = numel(sortedGain);
    for k = 1:numel(thresholds)
        if isnan(thresholds(k)), continue; end
        left = 1;
        right = count + 1;
        while left < right
            middle = floor((left + right) / 2);
            if sortedGain(middle) <= thresholds(k)
                left = middle + 1;
            else
                right = middle;
            end
        end
        coverage(k) = 100 * tail(left) / tail(1);
    end
end

function metrics = calcMetrics( ...
    tableData, peakInfo, solidAngle, principalAxes, thetaSpanMode, peakPercentile, peakMaxExcessDB)
%APAT_MATH_COMPUTEMETRICS Calculate scalar antenna metrics.

if isempty(tableData)
    metrics = struct();
    return
end

[gain, ~] = chooseGain(tableData, 'E_Total_dB', 'E_Total_dB');

if nargin < 2 || isempty(peakInfo)
    peakInfo = resolvePeak(gain, peakPercentile, peakMaxExcessDB, tableData.Theta, tableData.Phi);
end

if isfield(peakInfo, 'value')
    peakGain = peakInfo.value;
    peakIndex = peakInfo.index;
else
    peakGain = peakInfo.gain;
    peakIndex = peakInfo.index;
end

peakTheta = tableData.Theta(peakIndex);
peakPhi = tableData.Phi(peakIndex);

if nargin < 3 || isempty(solidAngle) || numel(solidAngle) ~= height(tableData)
    solidAngle = solidWeights(tableData.Theta, tableData.Phi);
end

metricGain = gain;
if isfield(peakInfo, 'wasAdjusted') && peakInfo.wasAdjusted
    metricGain(peakInfo.outlierMask) = NaN;
end

integratedGain = sum(10.^(metricGain / 10) .* solidAngle, 'omitnan');
peakDirectivity = 10 * log10(max(4 * pi * 10^(peakGain / 10) / max(integratedGain, eps), eps));

efficiencyPct = 100 * integratedGain / (4 * pi);
if efficiencyPct < 0 || efficiencyPct > 100
    efficiencyPct = NaN;
end

thetaPhysical = tableData.Theta;
peakThetaPhysical = thetaPhysical(peakIndex);

angularSimilarity = ...
    cosd(thetaPhysical) .* cosd(peakThetaPhysical) + ...
    sind(thetaPhysical) .* sind(peakThetaPhysical) .* ...
    cosd(tableData.Phi - peakPhi);

[~, backIndex] = min(angularSimilarity);

axialRatio = NaN;
if ismember('AR_dB', tableData.Properties.VariableNames)
    axialRatio = tableData.AR_dB(peakIndex);
end

axisIndex = 1;
if isfield(principalAxes, 'index')
    axisIndex = principalAxes.index;
end

if isfield(principalAxes, 'theta')
    axisTheta = principalAxes.theta(axisIndex);
    axisPhi = principalAxes.phi(axisIndex);
else
    axisTheta = peakTheta;
    axisPhi = peakPhi;
end

if axisTheta == 90
    hType = 'Phi';
    hValue = 90;
    if strcmp(thetaSpanMode, '-90° to 90°')
        hValue = 0;
    end
else
    hType = 'Theta';
    hValue = 90;
end

eType = 'Theta';
eValue = axisPhi;

[eAngle, eRows] = calcCutGeometry(tableData, eType, eValue, thetaPhysical);
[hAngle, hRows] = calcCutGeometry(tableData, hType, hValue, thetaPhysical);

ePlaneHPBW = calcHPBW(eAngle, gain(eRows));
hPlaneHPBW = calcHPBW(hAngle, gain(hRows));

metrics = struct( ...
    'PeakGain_dB', peakGain, ...
    'PeakTheta_deg', peakTheta, ...
    'PeakPhi_deg', peakPhi, ...
    'HPBW_EPlane_deg', ePlaneHPBW, ...
    'HPBW_HPlane_deg', hPlaneHPBW, ...
    'FrontBack_dB', peakGain - gain(backIndex), ...
    'PeakDirectivity_dB', peakDirectivity, ...
    'Efficiency_pct', efficiencyPct, ...
    'AxialRatioAtPeak_dB', axialRatio);
end

function [pattern,info] = calcPattern(standard,param,peakPercentile,peakMaxExcessDB)
%APAT_MATH_COMPUTEPATTERN Convert canonical source fields into processed data.
% Keep this hot path allocation-light: avoid temporary Nx4 matrices/structs and
% compute each primitive quantity once before constructing the UI/export table.
info = struct('POB',NaN,'POBth',NaN,'POBph',NaN,'pol','n/a',...
    'pairs',struct('Linear',["E_TH","E_PH"],'Circular',["E_RCP","E_LCP"]));
userData = standard.Properties.UserData;

if isfield(userData,'isGainOnly') && userData.isGainOnly
    pattern = standard;
    if width(pattern)>2
        pattern{:,3:end} = pattern{:,3:end}+param.GainLoss_dB;
    end
    peakInfo = resolvePeak(pattern{:,3},peakPercentile,peakMaxExcessDB,pattern.Theta,pattern.Phi);
    [info.POB,index] = deal(peakInfo.value,peakInfo.index);
    [info.POBth,info.POBph] = deal(pattern.Theta(index),pattern.Phi(index));
    info.peak = peakInfo;
    return
end

Etheta = complex(standard.Re_Eth,standard.Im_Eth).*param.FieldScale;
Ephi = complex(standard.Re_Eph,standard.Im_Eph).*param.FieldScale;
sqrt2 = sqrt(2);
Ercp = (Etheta+1i*Ephi)/sqrt2;
Elcp = (Etheta-1i*Ephi)/sqrt2;

magTheta = abs(Etheta);
magPhi = abs(Ephi);
magRcp = abs(Ercp);
magLcp = abs(Elcp);
totalGain = 10*log10(max(magTheta.^2+magPhi.^2,eps));

peakInfo = resolvePeak(totalGain,peakPercentile,peakMaxExcessDB,standard.Theta,standard.Phi);
[info.POB,index] = deal(peakInfo.value,peakInfo.index);
info.peak = peakInfo;
info.POBth = standard.Theta(index);
info.POBph = standard.Phi(index);

% Keep the four component summaries explicit: the same classification
% drives cut co/cross ordering, displayed polarization, and Auto-Rx sense.
meanPower = struct('E_TH',  mean(magTheta.^2, 'omitnan'), 'E_PH',  mean(magPhi.^2,   'omitnan'), ...
                   'E_RCP', mean(magRcp.^2,   'omitnan'), 'E_LCP', mean(magLcp.^2,   'omitnan'));

if meanPower.E_PH > meanPower.E_TH,    info.pairs.Linear = fliplr(info.pairs.Linear);     end
if meanPower.E_LCP > meanPower.E_RCP,  info.pairs.Circular = fliplr(info.pairs.Circular); end

linearPeakPower = max(meanPower.E_TH, meanPower.E_PH);
circularPeakPower = max(meanPower.E_RCP, meanPower.E_LCP);
if circularPeakPower > linearPeakPower
    info.pol = sprintf('Circular (%s)', replace(info.pairs.Circular(1), ["E_RCP", "E_LCP"], ["RHCP", "LHCP"]));
elseif meanPower.E_TH >= meanPower.E_PH
    info.pol = 'Linear (Vertical)';
else
    info.pol = 'Linear (Horizontal)';
end

% Polarization sense and signed axial ratio.
delta = magRcp - magLcp;
polSense = sign(delta);
polSense(~isfinite(delta)) = 0;
axialRatio = (magRcp + magLcp) ./ max(abs(delta), eps);

% Equal circular components have no handedness.  Treat numerical round-off
% at the scale of the two components as equal without introducing a custom
% tolerance parameter.  Equal components are the linear-polarization limit
% for the signed display, so use the APAT -100 dB floor instead of 0 dB.
equalComponents = isfinite(delta) & abs(delta) <= eps .* max(magRcp + magLcp, 1);
signedAR = min(20*log10(axialRatio), 250) .* polSense;
signedAR(equalComponents) = -100;

if param.RxMode == "Auto",     waveSense = 2*(info.pairs.Circular(1) == "E_RCP") - 1;
elseif param.RxMode == "RHCP", waveSense = 1;
else,                          waveSense = -1;
end

antennaRatio = axialRatio.*polSense;
antennaRatio(polSense==0) = 1e12;
waveRatio = waveSense*10.^(param.RxAR_dB/20);
waveRatio2 = waveRatio^2;
antennaRatio2 = antennaRatio.^2;
plfLinear = 0.5+(4*antennaRatio.*waveRatio+(antennaRatio2-1).*(waveRatio2-1).*cosd(180))./(2*(antennaRatio2+1).*(waveRatio2+1));
plfLinear = min(max(plfLinear,eps),1);
plfDB = 10*log10(plfLinear);

eirpDB = param.Pt_dBW+totalGain;
eirpW = 10.^(eirpDB/10);
pfd = eirpW./(4*pi*param.R_m^2);
electricFieldRMS = sqrt(30*eirpW)./param.R_m;

% Construct output only once all hot-path intermediates are finalized.
ErcpDB = 20*log10(max(magRcp,eps));
ElcpDB = 20*log10(max(magLcp,eps));
EthDB = 20*log10(max(magTheta,eps));
EphDB = 20*log10(max(magPhi,eps));
EthPhase = rad2deg(angle(Etheta));
EphPhase = rad2deg(angle(Ephi));
ErcpPhase = rad2deg(angle(Ercp));
ElcpPhase = rad2deg(angle(Elcp));

pattern = table(standard.Theta,standard.Phi,totalGain,signedAR,ErcpDB,ElcpDB,plfDB,...
    totalGain+plfDB,EthDB,EphDB,EthPhase,EphPhase,ErcpPhase,ElcpPhase,...
    eirpDB,pfd,electricFieldRMS,'VariableNames',...
    {'Theta','Phi','E_Total_dB','AR_dB','E_RCP_dB','E_LCP_dB','PLF_dB',...
     'Gain_PolCorrected_dB','E_TH_dB','E_PH_dB','E_TH_Phase','E_PH_Phase',...
     'E_RCP_Phase','E_LCP_Phase','EIRP_dBW','PFD_Wm2','E_RMS_Vm'});
pattern.Properties.UserData = userData;

end

function [angleDeg,rows,fixedAngle,fixedSymbol,didSnap,requestedAngle] = calcCutGeometry(tableData,cutType,requestedAngle,physicalTheta)
%calcCutGeometry Resolve a snapped full-circle cut.
if nargin<4, physicalTheta = tableData.Theta; end
if strcmp(cutType,'Phi')
    thetaValues = unique(tableData.Theta);
    [snapDistance,snapIndex] = min(abs(thetaValues-requestedAngle));
    fixedAngle = thetaValues(snapIndex); rows = find(abs(tableData.Theta-fixedAngle)<1e-9);
    [angleDeg,order] = sort(tableData.Phi(rows)); rows = rows(order); fixedSymbol = 'θ';
else
    requestedAngle = mod(requestedAngle,360); phiValues = unique(mod(tableData.Phi,360));
    [snapDistance,firstIndex] = min(abs(mod(phiValues-requestedAngle+180,360)-180));
    [~,oppositeIndex] = min(abs(mod(phiValues-phiValues(firstIndex),360)-180));
    fixedAngle = phiValues(firstIndex); wrappedPhi = mod(tableData.Phi,360);
    primaryRows = find(abs(wrappedPhi-fixedAngle)<1e-9);
    oppositeRows = find(abs(wrappedPhi-phiValues(oppositeIndex))<1e-9 & abs(physicalTheta-180)>1e-9);
    [~,primaryOrder] = sort(physicalTheta(primaryRows)); [~,oppositeOrder] = sort(physicalTheta(oppositeRows),'descend');
    primaryRows = primaryRows(primaryOrder); oppositeRows = oppositeRows(oppositeOrder);
    rows = [primaryRows;oppositeRows]; angleDeg = [physicalTheta(primaryRows);360-physicalTheta(oppositeRows)]; fixedSymbol = 'φ';
end
didSnap = snapDistance>0;
end

function [solidAngle, peakInfo, axisIndex] = calcOrientation(patternData, solidAngle, requestedColumn, principalAxes, peakPercentile, peakMaxExcessDB)
%calcOrientation Determine principal-axis cone with maximum weighted energy.
if nargin<3 || isempty(requestedColumn), requestedColumn = "E_Total_dB"; end
if nargin<2 || isempty(solidAngle) || numel(solidAngle)~=height(patternData)
    solidAngle = solidWeights(patternData.Theta,patternData.Phi);
end
[gainDB,~] = chooseGain(patternData,requestedColumn,"E_Total_dB");
peakInfo = resolvePeak(gainDB,peakPercentile,peakMaxExcessDB);
peakInfo.gain = peakInfo.value;
peakInfo.rawGain = peakInfo.rawValue;
if peakInfo.wasAdjusted, gainDB(peakInfo.outlierMask) = NaN; end
sampleWeight = 10.^((gainDB-peakInfo.value)/10).*solidAngle; sampleWeight(~isfinite(sampleWeight)) = 0;
axisVectors = [sind(principalAxes.theta(:)).*cosd(principalAxes.phi(:)),sind(principalAxes.theta(:)).*sind(principalAxes.phi(:)),cosd(principalAxes.theta(:))];
sinTheta = sind(patternData.Theta); phiRad = deg2rad(patternData.Phi);
sampleVectors = [sinTheta.*cos(phiRad),sinTheta.*sin(phiRad),cosd(patternData.Theta)];
coneEnergy = sampleWeight.'*double(sampleVectors*axisVectors.' >= cosd(45));
[~,axisIndex] = max(coneEnergy);
end

function step = gridStep(values)
%gridStep Smallest positive angular/sample spacing.
values = unique(values(isfinite(values)));
d = diff(values); d = d(d>1e-9);
if isempty(d), step = NaN; else, step = min(d); end
end

function [beamwidth, lowerAngle, upperAngle] = calcHPBW(angleDeg,gainDB,peakGain,peakAngle)
%calcHPBW Half-power beamwidth from a circular cut.
[beamwidth,lowerAngle,upperAngle] = deal(NaN);
valid = isfinite(angleDeg)&isfinite(gainDB); angleDeg = angleDeg(valid); gainDB = gainDB(valid);
if numel(gainDB)<3, return; end
if nargin<3 || isempty(peakGain), [peakGain,idx] = max(gainDB); peakAngle = angleDeg(idx); end
if nargin<4 || isempty(peakAngle), [~,idx] = max(gainDB); peakAngle = angleDeg(idx); end
halfPower = peakGain-3;
[relativeAngle,order] = sort(mod(angleDeg-peakAngle+180,360)-180);
relativeGain = gainDB(order);
leftOutside = find(relativeAngle<0 & relativeGain<=halfPower,1,'last');
rightOutside = find(relativeAngle>0 & relativeGain<=halfPower,1,'first');
if isempty(leftOutside)||isempty(rightOutside), return; end
leftIdx = [leftOutside,leftOutside+1]; rightIdx = [rightOutside,rightOutside-1];
if leftIdx(2)>numel(relativeGain)||rightIdx(2)>numel(relativeGain), return; end
leftGain = relativeGain(leftIdx); rightGain = relativeGain(rightIdx);
if diff(leftGain)==0 || diff(rightGain)==0, return; end
leftCross = relativeAngle(leftIdx(1))+diff(relativeAngle(leftIdx))*(halfPower-leftGain(1))/diff(leftGain);
rightCross = relativeAngle(rightIdx(1))+diff(relativeAngle(rightIdx))*(halfPower-rightGain(1))/diff(rightGain);
lowerAngle = peakAngle+leftCross; upperAngle = peakAngle+rightCross; beamwidth = rightCross-leftCross;
end

function tableData = normalizePattern(tableData)
%normalizePattern Map angular coordinates to canonical sphere.
% Canonical convention: Theta [0,180], Phi [0,360], closed Phi seam.
theta = tableData.Theta;
if any(theta < 0)
    if min(theta,[],'omitnan') >= -90 && max(theta,[],'omitnan') <= 90
        tableData.Theta = 90 - theta;
    else
        mask = theta < 0;
        tableData.Theta(mask) = -theta(mask);
        tableData.Phi(mask) = tableData.Phi(mask) + 180;
    end
end
tableData.Theta = mod(tableData.Theta,360);
overPole = tableData.Theta > 180;
tableData.Theta(overPole) = 360-tableData.Theta(overPole);
tableData.Phi(overPole) = tableData.Phi(overPole)+180;
% Canonicalize coordinates only; never quantize complex field amplitudes.
% A 1e-7 field is valid data, not a five-decimal rounding artifact.
tableData.Theta = round(tableData.Theta, 9);
tableData.Phi = round(tableData.Phi, 9);

tableData.Theta = mod(tableData.Theta, 360);
tableData.Theta(tableData.Theta > 180) = 360 - tableData.Theta(tableData.Theta > 180);
tableData.Phi = mod(tableData.Phi, 360);
tableData.Theta(abs(tableData.Theta) < 1e-12) = 0;
tableData.Phi(abs(tableData.Phi) < 1e-12) = 0;
[~,uniqueRows] = unique(tableData{:,{'Phi','Theta'}},'rows','first');
tableData = tableData(uniqueRows,:);
seam = tableData(abs(tableData.Phi)<1e-10,:);
seam.Phi(:) = 360;
tableData = [tableData; seam];
end

function [result, info] = resampleCanonical(sourceTable, stepDeg, options)
% Resample primitive fields or explicitly named gain quantities.
% Both grid paths share quantity conversion and periodic boundary policy.
arguments
    sourceTable table
    stepDeg (1,1) double {mustBeFinite,mustBePositive} = 1
    options.OutputColumns string = string.empty
    options.PeriodicPhi (1,1) logical = true
    options.LinearPowerForGain (1,1) logical = true
    options.Extrapolation char {mustBeMember(options.Extrapolation,{'nearest','none'})} = 'nearest'
end
names = string(sourceTable.Properties.VariableNames);
assert(all(ismember(["Theta","Phi"], names)) && ~isempty(sourceTable), ...
    'apat:math:InvalidPattern', 'A nonempty Theta/Phi table is required.');
outputNames = options.OutputColumns;
if isempty(outputNames), outputNames = names(3:end); end
assert(~isempty(outputNames) && all(ismember(outputNames,names)), ...
    'apat:math:InvalidColumns', 'Requested quantities are missing.');
theta = double(sourceTable.Theta(:));
phi = mod(double(sourceTable.Phi(:)),360);
valid = isfinite(theta) & isfinite(phi) & theta >= 0 & theta <= 180;
source = sourceTable(valid,:);
theta = theta(valid);
phi = phi(valid);
% Prefer phi=0 to its closing duplicate, but retain a 360-only sample.
[~, order] = sort(abs(source.Phi - phi));
[~, keep] = unique([theta(order),phi(order)],'rows','stable');
keep = order(keep);
source = source(keep,:);
theta = theta(keep);
phi = phi(keep);
assert(~isempty(theta), 'apat:math:EmptyPattern', 'No finite angular samples.');
% Prevent an accidental multi-gigabyte target allocation from a tiny step.
assert((ceil(180/stepDeg)+1)*(ceil(360/stepDeg)+1) <= 5000000, ...
    'apat:math:GridBudget', 'Requested grid exceeds five million samples.');
targetTheta = unique([0:stepDeg:180,180]);
targetPhi = unique([0:stepDeg:360,360]);
[queryPhi,queryTheta] = meshgrid(targetPhi,targetTheta);
result = table(queryTheta(:),queryPhi(:),'VariableNames',{'Theta','Phi'});
thetaAxis = unique(theta);
phiAxis = unique(phi);
regular = numel(thetaAxis)*numel(phiAxis) == numel(theta);
[~, ti] = ismember(theta,thetaAxis);
[~, pi] = ismember(phi,phiAxis);
linearIndex = sub2ind([numel(thetaAxis),numel(phiAxis)],ti,pi);
fieldNames = ["Re_Eth","Im_Eth","Re_Eph","Im_Eph"];
fieldMode = all(ismember(fieldNames,outputNames));
for k = 1:numel(outputNames)
    name = outputNames(k);
    values = double(source.(name));
    inPower = options.LinearPowerForGain && isGainDBColumn(name) && ~fieldMode;
    scale = 0;
    if inPower
        finiteValues = values(isfinite(values));
        assert(~isempty(finiteValues),'apat:math:NoFiniteGain','No finite gain values.');
        scale = max(finiteValues);
        values = 10.^((values-scale)/10);
    end
    if regular
        grid = nan(numel(thetaAxis),numel(phiAxis));
        grid(linearIndex) = values;
        sampled = interpolateRegularM8(thetaAxis,phiAxis,grid,queryTheta,queryPhi, ...
            options.PeriodicPhi,options.Extrapolation);
    else
        x = phi;
        y = theta;
        if options.PeriodicPhi
            x = [phi-360;phi;phi+360];
            y = repmat(theta,3,1);
            values = repmat(values,3,1);
        end
        finite = isfinite(values);
        assert(nnz(finite) >= 3,'apat:math:SparseGrid','At least three finite samples required.');
        F = scatteredInterpolant(x(finite),y(finite),values(finite),'linear',options.Extrapolation);
        sampled = F(queryPhi,queryTheta);
    end
    if inPower, sampled = scale + 10*log10(max(sampled,realmin('double'))); end
    result.(name) = sampled(:);
end
result.Properties.UserData = sourceTable.Properties.UserData;
info = struct('isRegularSource',regular,'stepDeg',stepDeg, ...
    'targetSize',size(queryTheta),'periodicPhi',options.PeriodicPhi,'primitiveFieldMode',fieldMode);
if regular, info.method = 'regular-gridded'; else, info.method = 'irregular-scattered'; end
end

function sampled = interpolateRegularM8(thetaAxis,phiAxis,grid,queryTheta,queryPhi,periodic,extrapolation)
if periodic
    phiAxis = [phiAxis(end)-360;phiAxis;phiAxis(1)+360];
    grid = [grid(:,end),grid,grid(:,1)];
end
% Singleton axes are a constant slice, not a 2-D interpolation problem.
if numel(thetaAxis) == 1
    if numel(phiAxis) == 1
        sampled = repmat(grid,size(queryTheta));
    else
        F = griddedInterpolant(phiAxis,grid(:),'linear',extrapolation);
        sampled = F(queryPhi);
    end
    if strcmp(extrapolation,'none'), sampled(queryTheta ~= thetaAxis) = NaN; end
elseif numel(phiAxis) == 1
    F = griddedInterpolant(thetaAxis,grid(:),'linear',extrapolation);
    sampled = F(queryTheta);
    if strcmp(extrapolation,'none'), sampled(queryPhi ~= phiAxis) = NaN; end
else
    F = griddedInterpolant({thetaAxis,phiAxis},grid,'linear',extrapolation);
    sampled = F(queryTheta,queryPhi);
end
end

function tf = isGainDBColumn(name)
%ISGAINDBCOLUMN Identify gain-like dB quantities for linear-power interpolation.

    key = regexprep(lower(strtrim(string(name))), '[^a-z0-9]', '');
    tf = contains(key, 'gain') || contains(key, 'directivity') || contains(key, 'eirp') || ...
        any(key == ["etotaldb","ethdb","ephdb","ercpdb","elcpdb"]);
end

function info = resolvePeak(values, percentile, maximumExcessDB, ~, ~)
%resolvePeak Resolve the authoritative APAT peak using the v2 policy.
% A raw peak is accepted unless it exceeds the P99.99 percentile by more than
% maximumExcessDB. If it is an outlier, the highest sample at or below the
% percentile becomes the effective peak. Angular coordinates are accepted for
% API compatibility but do not participate in peak selection.

validateattributes(values, {'numeric'}, {'vector'});

finiteMask = isfinite(values);
finiteValues = values(finiteMask);

info = struct( ...
    'value', NaN, ...
    'index', 1, ...
    'rawValue', NaN, ...
    'rawIndex', 1, ...
    'outlierMask', false(size(values)), ...
    'wasAdjusted', false, ...
    'method', 'P99.99-plus-maximum-excess', ...
    'percentile', percentile, ...
    'maximumExcessDB', maximumExcessDB);

if isempty(finiteValues)
    return
end

finiteCandidates = values;
finiteCandidates(~finiteMask) = -Inf;
[rawValue, rawIndex] = max(finiteCandidates);
percentileValue = prctile(finiteValues, percentile);

info.rawValue = rawValue;
info.rawIndex = rawIndex;

if rawValue <= percentileValue + maximumExcessDB
    info.value = rawValue;
    info.index = rawIndex;
    return
end

outlierMask = finiteMask & values > percentileValue;
candidateMask = finiteMask & ~outlierMask;

if any(candidateMask)
    candidateValues = values;
    candidateValues(~candidateMask) = -Inf;
    [info.value, info.index] = max(candidateValues);
    info.outlierMask = outlierMask;
    info.wasAdjusted = true;
else
    % Defensive fallback for a degenerate one-sample pattern.
    info.value = rawValue;
    info.index = rawIndex;
end

end

function bounds = robustRange(values,roundToFive)
%robustRange Robust display range.
finiteValues = values(isfinite(values));
if isempty(finiteValues), bounds = [-40 0]; return; end
low = min(finiteValues); high = max(finiteValues); spread = high-low;
if spread<1e-9, spread = max(5,abs(high)*0.05); end
lo = low-0.05*spread; hi = high+0.05*spread;
if nargin>=2 && roundToFive
    lo = 5*floor(lo/5); hi = 5*ceil(hi/5);
end
bounds = [lo hi];
end

function [gain,column] = chooseGain(tableData,requestedColumn,defaultColumn)
%chooseGain Resolve requested/total/first gain column.
vars = tableData.Properties.VariableNames;
if nargin<2 || isempty(requestedColumn), requestedColumn = defaultColumn; end
candidates = [string(requestedColumn),"E_Total_dB"];
idx = find(ismember(candidates,string(vars)),1);
if isempty(idx), column = vars{3}; else, column = char(candidates(idx)); end
gain = tableData.(column);
end

function deltaOmega = solidWeights(theta, phi, thetaStep, phiStep)
%solidWeights Exact uniform-cell solid-angle weights.
if nargin < 3 || ~isfinite(thetaStep), thetaStep = gridStep(theta); end
if nargin < 4 || ~isfinite(phiStep), phiStep = gridStep(mod(phi,360)); end
if ~isfinite(thetaStep), thetaStep = 180; end
if ~isfinite(phiStep), phiStep = 360; end
thetaLower = max(theta-thetaStep/2,0);
thetaUpper = min(theta+thetaStep/2,180);
deltaOmega = (cosd(thetaLower)-cosd(thetaUpper))*deg2rad(phiStep);
seamAngle = 180*any(phi<0)+360*~any(phi<0);
deltaOmega(abs(phi-seamAngle)<1e-9) = 0;
end

function metadata = validateSourceModel(metadata)
%APAT.MODEL.VALIDATESOURCE Normalize source metadata semantics.
if nargin == 0 || isempty(metadata), metadata = struct(); end
fields = {'source','isGainOnly','isCoverage','isDep','isMultiBlock','hasFrequency'};
defaults = {'unknown',false,false,false,false,false};
for k = 1:numel(fields)
    if ~isfield(metadata,fields{k}) || isempty(metadata.(fields{k}))
        metadata.(fields{k}) = defaults{k};
    end
end
if ~isfield(metadata,'quantityType') || isempty(metadata.quantityType)
    if metadata.isGainOnly
        metadata.quantityType = "gain-like";
    else
        metadata.quantityType = "complex-electric-field";
    end
end
if ~isfield(metadata,'absoluteCalibration'), metadata.absoluteCalibration = ~metadata.isGainOnly; end
if ~isfield(metadata,'polarizationBasis'), metadata.polarizationBasis = "theta-phi"; end
end

function cache = emptyGridCache()
cache = struct('valid',false,'theta',[],'phi',[],'linearIndex',[],'sz',[],'data',struct(),'geom',struct(),'viewRevision',uint64(0));
end