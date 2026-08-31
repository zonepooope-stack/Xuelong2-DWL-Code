% =========================================================================
%  Seven-panel spatial RMSE maps: one overview + six altitude layers
%
%  Layout
%    (a) 104-3000 m, spanning the first row
%    (b-d) 104-500, 500-1000, 1000-1500 m
%    (e-g) 1500-2000, 2000-2500, 2500-3000 m
%
%  Notes
%    * The measured first lidar gate is 103.9 m and is displayed as 104 m.
%    * Every panel uses the same map limits, RMSE limits and sample criterion.
%    * N is the number of valid paired lidar-ERA5 height samples.
% =========================================================================

clc;
clear;
close all;

%% ========================= 0. Paths and settings =========================
scriptFolder = fileparts(mfilename('fullpath'));
addpath(scriptFolder);
cfg = project_config();
era5DataFolder  = cfg.era5DataFolder;
stayInfoFile    = cfg.stayInfoFile;
lidarDataFolder = cfg.lidarDataFolder;
outputFolder    = fullfile(cfg.outputRoot, 'fig05');

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

FONT_NAME = 'Arial';
MAX_HEIGHT = 3000;
MIN_PAIRED_SAMPLES = 3;
RMSE_LIMITS = [0, 15];
g = 9.81;

% The first edge is updated from the actual lidar headers after loading.
nominalLayerUpperEdges = [500, 1000, 1500, 2000, 2500, 3000];

%% ========================= 1. Ship-grid data ==============================
fprintf('>>> [1/5] Reading ship-grid data...\n');
if ~exist(stayInfoFile, 'file')
    error('Ship-grid file not found: %s', stayInfoFile);
end

stayData = readtable(stayInfoFile);
try
    if ~isdatetime(stayData.hour_start)
        try
            hourStart = datetime(stayData.hour_start, ...
                'InputFormat', 'yyyy-MM-dd HH:mm:ss');
        catch
            hourStart = datetime(stayData.hour_start);
        end
    else
        hourStart = stayData.hour_start;
    end

    if isempty(hourStart.TimeZone)
        hourStart.TimeZone = 'UTC+8';
    end
    stayData.hour_start_utc = datetime(hourStart, 'TimeZone', 'UTC');
catch ME
    error('Unable to parse ship-grid time: %s', ME.message);
end

uniqueHours = unique(stayData.hour_start_utc);

%% ========================= 2. Lidar data ==================================
fprintf('>>> [2/5] Reading lidar wind-speed columns...\n');
lidarFiles = dir(fullfile(lidarDataFolder, '*.csv'));
if isempty(lidarFiles)
    error('No lidar CSV files found in %s.', lidarDataFolder);
end

allLidar = table();
allHeaderMinima = NaN(numel(lidarFiles), 1);

for f = 1:numel(lidarFiles)
    fullName = fullfile(lidarDataFolder, lidarFiles(f).name);
    if mod(f, 25) == 0 || f == numel(lidarFiles)
        fprintf('    Lidar files: %d / %d\n', f, numel(lidarFiles));
    end

    try
        opts = detectImportOptions(fullName);
        opts.VariableNamingRule = 'preserve';
        varNames = opts.VariableNames;

        isTime = strcmpi(varNames, 'Date_time');
        isWindSpeed = false(size(varNames));
        fileHeights = NaN(size(varNames));

        for v = 1:numel(varNames)
            token = regexp(varNames{v}, ...
                '^(\d+\.?\d*)m\s*Wind\s*Speed$', ...
                'tokens', 'once', 'ignorecase');
            if ~isempty(token)
                isWindSpeed(v) = true;
                fileHeights(v) = str2double(token{1});
            else
                % detectImportOptions temporarily converts, for example,
                % "103.9m WindSpeed" to "x103_9mWindSpeed".
                tokenModified = regexp(varNames{v}, ...
                    '^x(\d+)_(\d+)mWindSpeed$', ...
                    'tokens', 'once', 'ignorecase');
                if ~isempty(tokenModified)
                    isWindSpeed(v) = true;
                    fileHeights(v) = str2double( ...
                        [tokenModified{1}, '.', tokenModified{2}]);
                else
                    tokenInteger = regexp(varNames{v}, ...
                        '^x(\d+)mWindSpeed$', ...
                        'tokens', 'once', 'ignorecase');
                    if ~isempty(tokenInteger)
                        isWindSpeed(v) = true;
                        fileHeights(v) = str2double(tokenInteger{1});
                    end
                end
            end
        end

        if ~any(isTime) || ~any(isWindSpeed)
            continue;
        end

        allHeaderMinima(f) = min(fileHeights(isWindSpeed));
        opts.SelectedVariableNames = varNames(isTime | isWindSpeed);
        T = readtable(fullName, opts);

        rawTime = T.(varNames{find(isTime, 1)});
        if isdatetime(rawTime)
            tcol = rawTime;
        else
            try
                tcol = datetime(rawTime, 'InputFormat', 'yyyyMMdd HH:mm:ss');
            catch
                tcol = datetime(rawTime);
            end
        end

        if isempty(tcol.TimeZone)
            tcol.TimeZone = 'UTC+8';
        end
        T.(varNames{find(isTime, 1)}) = datetime(tcol, 'TimeZone', 'UTC');
        T.Properties.VariableNames{find(isTime, 1)} = 'Date_time';
        T = T(~isnat(T.Date_time), :);

        if ~isempty(T)
            if isempty(allLidar)
                allLidar = T;
            else
                allLidar = [allLidar; T]; %#ok<AGROW>
            end
        end
    catch ME
        warning('Skipped %s: %s', lidarFiles(f).name, ME.message);
    end
end

if isempty(allLidar)
    error('No usable lidar records were loaded.');
end

allLidar = sortrows(allLidar, 'Date_time');

validHeaderMinima = allHeaderMinima(isfinite(allHeaderMinima));
lidarMinHeight = min(validHeaderMinima);
fprintf('    Lidar files checked: %d\n', numel(validHeaderMinima));
fprintf('    Lowest lidar gate: %.1f m (reported as %d m)\n', ...
    lidarMinHeight, round(lidarMinHeight));

% Confirm that all files use the same lowest gate.
if any(abs(validHeaderMinima - lidarMinHeight) > 1e-6)
    warning('Not all lidar files have the same minimum height.');
end

layerEdges = [lidarMinHeight, nominalLayerUpperEdges];

% Determine the wind-speed variables and their heights once.
lidarVars = allLidar.Properties.VariableNames;
speedVars = {};
speedHeights = [];
for v = 1:numel(lidarVars)
    token = regexp(lidarVars{v}, ...
        '^(\d+\.?\d*)m\s*Wind\s*Speed$', ...
        'tokens', 'once', 'ignorecase');
    if ~isempty(token)
        speedVars{end+1} = lidarVars{v}; %#ok<SAGROW>
        speedHeights(end+1, 1) = str2double(token{1}); %#ok<SAGROW>
    end
end

[speedHeights, order] = sort(speedHeights);
speedVars = speedVars(order);

%% ========================= 3. Hourly matched RMSE =========================
fprintf('>>> [3/5] Calculating hourly matched RMSE...\n');

currentNcDate = NaT(1, 1, 'TimeZone', 'UTC');
era5 = struct();
results = struct([]);

for i = 1:numel(uniqueHours)
    tStart = uniqueHours(i);
    tEnd = tStart + hours(1);

    if mod(i, 100) == 0 || i == numel(uniqueHours)
        fprintf('    Hours: %d / %d\n', i, numel(uniqueHours));
    end

    lidarRows = allLidar.Date_time >= tStart & allLidar.Date_time < tEnd;
    if ~any(lidarRows)
        continue;
    end

    % Hourly mean lidar profile.
    lidarWs = NaN(numel(speedVars), 1);
    for v = 1:numel(speedVars)
        values = allLidar.(speedVars{v})(lidarRows);
        if iscell(values)
            values = str2double(values);
        elseif isstring(values)
            values = str2double(values);
        end
        values = double(values);
        values(values < 0 | values >= 100) = NaN;
        lidarWs(v) = mean(values, 'omitnan');
    end

    validLidar = isfinite(speedHeights) & isfinite(lidarWs) & ...
        speedHeights >= lidarMinHeight & speedHeights <= MAX_HEIGHT;
    if sum(validLidar) < MIN_PAIRED_SAMPLES
        continue;
    end

    lidarH = speedHeights(validLidar);
    lidarWs = lidarWs(validLidar);

    hourGrid = stayData(stayData.hour_start_utc == tStart, :);
    if isempty(hourGrid)
        continue;
    end

    targetDate = dateshift(tStart, 'start', 'day');
    if isnat(currentNcDate) || targetDate ~= currentNcDate
        currentNcDate = targetDate;
        era5 = struct();

        ncPath = fullfile(era5DataFolder, ...
            sprintf('%s_part1.nc', datestr(targetDate, 'yyyy_mm_dd')));

        if exist(ncPath, 'file')
            try
                era5.lon = ncread(ncPath, 'longitude');
                era5.lat = ncread(ncPath, 'latitude');
                era5.pressure = ncread(ncPath, 'pressure_level');
                era5.z = ncread(ncPath, 'z');
                era5.u = ncread(ncPath, 'u');
                era5.v = ncread(ncPath, 'v');

                if any(era5.lon < 0)
                    era5.lon(era5.lon < 0) = era5.lon(era5.lon < 0) + 360;
                end
                [era5.lon, lonOrder] = sort(era5.lon);
                era5.z = era5.z(lonOrder, :, :, :);
                era5.u = era5.u(lonOrder, :, :, :);
                era5.v = era5.v(lonOrder, :, :, :);
            catch ME
                warning('Unable to read %s: %s', ncPath, ME.message);
                era5 = struct();
            end
        end
    end

    if isempty(fieldnames(era5))
        continue;
    end

    totalStay = sum(hourGrid.stay_hours);
    if ~isfinite(totalStay) || totalStay <= 0
        continue;
    end

    timeIndex = hour(tStart) + 1;
    nLevels = numel(era5.pressure);
    zWeighted = zeros(nLevels, 1);
    uWeighted = zeros(nLevels, 1);
    vWeighted = zeros(nLevels, 1);

    for j = 1:height(hourGrid)
        weight = hourGrid.stay_hours(j) / totalStay;
        [~, lonIndex] = min(abs(era5.lon - hourGrid.lon_center(j)));
        [~, latIndex] = min(abs(era5.lat - hourGrid.lat_center(j)));

        zWeighted = zWeighted + ...
            squeeze(era5.z(lonIndex, latIndex, :, timeIndex)) * weight;
        uWeighted = uWeighted + ...
            squeeze(era5.u(lonIndex, latIndex, :, timeIndex)) * weight;
        vWeighted = vWeighted + ...
            squeeze(era5.v(lonIndex, latIndex, :, timeIndex)) * weight;
    end

    era5H = zWeighted / g;
    era5Ws = sqrt(uWeighted.^2 + vWeighted.^2);
    [era5H, sortIndex] = sort(era5H);
    era5Ws = era5Ws(sortIndex);

    validEra5 = isfinite(era5H) & isfinite(era5Ws);
    if sum(validEra5) < 2
        continue;
    end

    era5AtLidar = interp1(era5H(validEra5), era5Ws(validEra5), ...
        lidarH, 'linear', NaN);
    paired = isfinite(lidarWs) & isfinite(era5AtLidar);
    if sum(paired) < MIN_PAIRED_SAMPLES
        continue;
    end

    hPaired = lidarH(paired);
    difference = lidarWs(paired) - era5AtLidar(paired);

    temp = struct();
    temp.Time_Key = tStart;

    % Full 104-3000 m panel.
    fullMask = hPaired >= lidarMinHeight & hPaired <= MAX_HEIGHT;
    temp.N_Total = sum(fullMask);
    if temp.N_Total >= MIN_PAIRED_SAMPLES
        temp.RMSE_Total = sqrt(mean(difference(fullMask).^2));
    else
        temp.RMSE_Total = NaN;
    end

    % Six altitude layers, all using the same minimum sample criterion.
    for k = 1:6
        hLow = layerEdges(k);
        hHigh = layerEdges(k + 1);
        if k < 6
            layerMask = hPaired >= hLow & hPaired < hHigh;
        else
            layerMask = hPaired >= hLow & hPaired <= hHigh;
        end

        nField = sprintf('N_L%d', k);
        rmseField = sprintf('RMSE_L%d', k);
        temp.(nField) = sum(layerMask);

        if temp.(nField) >= MIN_PAIRED_SAMPLES
            temp.(rmseField) = sqrt(mean(difference(layerMask).^2));
        else
            temp.(rmseField) = NaN;
        end
    end

    if isfinite(temp.RMSE_Total)
        if isempty(results)
            results = temp;
        else
            results(end + 1, 1) = temp; %#ok<SAGROW>
        end
    end
end

if isempty(results)
    error('No valid lidar-ERA5 matched samples were generated.');
end

calcResults = struct2table(results);
fprintf('    Valid matched hours: %d\n', height(calcResults));

FinalData = innerjoin(stayData, calcResults, ...
    'LeftKeys', 'hour_start_utc', 'RightKeys', 'Time_Key');
FinalData = sortrows(FinalData, 'hour_start_utc');

%% ========================= 4. Shared plotting data ========================
fprintf('>>> [4/5] Preparing common panel settings...\n');

rmseFields = {'RMSE_Total', 'RMSE_L1', 'RMSE_L2', 'RMSE_L3', ...
              'RMSE_L4', 'RMSE_L5', 'RMSE_L6'};
nFields = {'N_Total', 'N_L1', 'N_L2', 'N_L3', ...
           'N_L4', 'N_L5', 'N_L6'};

lowestLabel = round(lidarMinHeight);
enDash = char(8211);
panelTitles = {
    sprintf('(a) All heights (%d%c3000 m)', lowestLabel, enDash)
    sprintf('(b) %d%c500 m', lowestLabel, enDash)
    sprintf('(c) 500%c1000 m', enDash)
    sprintf('(d) 1000%c1500 m', enDash)
    sprintf('(e) 1500%c2000 m', enDash)
    sprintf('(f) 2000%c2500 m', enDash)
    sprintf('(g) 2500%c3000 m', enDash)
};

panelN = zeros(7, 1);
for p = 1:7
    panelN(p) = sum(calcResults.(nFields{p}), 'omitnan');
end

%% ========================= 5. Merge the two original map styles ==========
fprintf('>>> [5/5] Merging the original total and layered RMSE maps...\n');

fig = figure('Name', 'Combined RMSE Maps: Original Styles', ...
    'Visible', 'on', 'Color', 'w', ...
    'Position', [30, 20, 1800, 2000]);
set(fig, 'DefaultAxesFontName', FONT_NAME, ...
    'DefaultTextFontName', FONT_NAME, ...
    'DefaultAxesFontSize', 18, ...
    'DefaultTextFontSize', 18, ...
    'DefaultAxesFontWeight', 'bold', ...
    'DefaultTextFontWeight', 'bold');

% Use two rows for the wide total-RMSE map and one row for each set of
% three layer maps. This makes the top map flatter and the six lower maps
% taller while keeping all left and right edges aligned.
t = tiledlayout(fig, 4, 3, ...
    'TileSpacing', 'compact', 'Padding', 'compact');
tileNumbers = [1, 7, 8, 9, 10, 11, 12];
mapAxes = gobjects(7, 1);

for p = 1:7
    gx = geoaxes(t);
    gx.Layout.Tile = tileNumbers(p);
    if p == 1
        gx.Layout.TileSpan = [2, 3];
    end
    mapAxes(p) = gx;

    % Preserve the two original scripts' basemap choices.
    if p == 1
        try
            geobasemap(gx, 'streets');
        catch
            geobasemap(gx, 'bluegreen');
        end
    else
        try
            geobasemap(gx, 'landcover');
        catch
            geobasemap(gx, 'grayland');
        end
    end

    % Hide MATLAB's local geographic scale bar. Its length is only valid
    % near the bar location and is misleading on this wide latitude range.
    % This does not change the geographic projection or longitude axis.
    if isprop(gx, 'Scalebar')
        gx.Scalebar.Visible = 'off';
    end

    hold(gx, 'on');

    rmseValues = FinalData.(rmseFields{p});
    validPlot = isfinite(rmseValues) & rmseValues >= 0;

    if any(validPlot)
        if p == 1
            markerSize = 50;
            markerShape = 'o';
        else
            markerSize = 40;
            markerShape = 's';
        end

        hScatter = geoscatter(gx, ...
            FinalData.lat_center(validPlot), ...
            FinalData.lon_center(validPlot), ...
            markerSize, rmseValues(validPlot), ...
            'filled', 'Marker', markerShape);

        % Retain the useful interactive information from the originals.
        timeDisplay = FinalData.hour_start_utc(validPlot) + hours(8);
        timeStrings = cellstr(datestr(timeDisplay, 'yyyy-mm-dd HH:MM'));
        hScatter.DataTipTemplate.DataTipRows(end+1) = ...
            dataTipTextRow('Time (BJT)', timeStrings);
        hScatter.DataTipTemplate.DataTipRows(end+1) = ...
            dataTipTextRow('RMSE', rmseValues(validPlot), '%.2f m/s');
    end

    geolimits(gx, 'auto');
    if p == 1
        gx.LongitudeAxis.TickValues = 0:60:360;
    else
        gx.LongitudeAxis.TickValues = 0:90:360;
    end
    colormap(gx, jet(256));
    clim(gx, RMSE_LIMITS);
    title(gx, '');

    gx.FontName = FONT_NAME;
    gx.FontWeight = 'bold';
    gx.FontSize = 18;

    if p == 1
        gx.LatitudeLabel.String = 'Latitude';
        gx.LongitudeLabel.String = 'Longitude';
    else
        lowerIndex = p - 1;
        lowerRow = ceil(lowerIndex / 3);
        lowerColumn = mod(lowerIndex - 1, 3) + 1;

        if lowerColumn == 1
            gx.LatitudeLabel.String = 'Latitude';
        else
            gx.LatitudeLabel.String = '';
            gx.LatitudeAxis.TickLabels = {};
        end

        if lowerRow == 2
            gx.LongitudeLabel.String = 'Longitude';
        else
            gx.LongitudeLabel.String = '';
            gx.LongitudeAxis.TickLabels = {};
        end
    end
    gx.LatitudeLabel.FontSize = 18;
    gx.LatitudeLabel.FontWeight = 'bold';
    gx.LongitudeLabel.FontSize = 18;
    gx.LongitudeLabel.FontWeight = 'bold';

    % Put the panel label and effective N inside the map, at the original
    % upper-right legend-box location rather than above the panel.
    drawnow limitrate;
    latLimits = gx.LatitudeLimits;
    lonLimits = gx.LongitudeLimits;
    textLatitude = latLimits(2) - 0.035 * diff(latLimits);
    textLongitude = lonLimits(2) - 0.035 * diff(lonLimits);
    legendText = {panelTitles{p}; ...
        sprintf('N = %.0f', panelN(p))};

    legendFontSize = 14;

    text(gx, textLatitude, textLongitude, legendText, ...
        'FontName', FONT_NAME, ...
        'FontWeight', 'bold', ...
        'FontSize', legendFontSize, ...
        'Interpreter', 'none', ...
        'Color', 'k', ...
        'BackgroundColor', 'w', ...
        'EdgeColor', 'k', ...
        'LineWidth', 0.8, ...
        'Margin', 3, ...
        'VerticalAlignment', 'top', ...
        'HorizontalAlignment', 'right');

    box(gx, 'on');
end

% One shared colorbar for the total map and all six layer maps.
cb = colorbar(mapAxes(1));
cb.Layout.Tile = 'east';
cb.Label.String = 'RMSE (m/s)';
cb.Label.FontName = FONT_NAME;
cb.Label.FontWeight = 'bold';
cb.Label.FontSize = 18;
cb.FontName = FONT_NAME;
cb.FontWeight = 'bold';
cb.FontSize = 18;
cb.Ticks = [0, 5, 10, 15];

drawnow;

savePath = fullfile(outputFolder, ...
    'Layered_RMSE_Map_1plus3plus3.png');
exportgraphics(fig, savePath, ...
    'Resolution', 300, 'BackgroundColor', 'white');

% Keep the MATLAB figure visible after the script finishes.
set(fig, 'Visible', 'on');
figure(fig);
drawnow;

fprintf('Figure saved to:\n%s\n', savePath);
fprintf('Lowest lidar height: %.1f m (use %d m in the paper).\n', ...
    lidarMinHeight, round(lidarMinHeight));
