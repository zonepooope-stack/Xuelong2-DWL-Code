function resultTable = build_ship_grid_stay_table(lidarDataFolder, outputFile)
%BUILD_SHIP_GRID_STAY_TABLE Rebuild the hourly ERA5-grid residence table.
%
% resultTable = build_ship_grid_stay_table()
% resultTable = build_ship_grid_stay_table(lidarDataFolder, outputFile)
%
% The calculation uses the Date_time, Longitude, and Latitude fields from
% the released Xuelong2-DWL daily files. Timestamps are interpreted as
% China Standard Time (UTC+8). Each trajectory point is assigned to the
% nearest 0.25-degree ERA5 grid centre. The time interval to the next
% point is used as the residence duration; intervals longer than one hour
% are treated as data gaps. Groups contributing no more than 0.01 h are
% excluded, matching the table used for the manuscript analysis.

scriptFolder = fileparts(mfilename('fullpath'));
addpath(scriptFolder);
cfg = project_config();

if nargin < 1 || isempty(lidarDataFolder)
    lidarDataFolder = cfg.lidarDataFolder;
end
if nargin < 2 || isempty(outputFile)
    outputFile = cfg.stayInfoFile;
end

gridResolution = 0.25;
lidarFiles = [dir(fullfile(lidarDataFolder, '*.csv')); ...
              dir(fullfile(lidarDataFolder, '*.xlsx'))];
if isempty(lidarFiles)
    error('No lidar CSV or XLSX files were found in %s.', lidarDataFolder);
end

fprintf('Reading vessel positions from %d lidar files...\n', numel(lidarFiles));
rawTrack = table();
requiredVariables = {'Date_time', 'Longitude', 'Latitude'};

for fileIndex = 1:numel(lidarFiles)
    fullPath = fullfile(lidarFiles(fileIndex).folder, lidarFiles(fileIndex).name);
    try
        options = detectImportOptions(fullPath);
        options.VariableNamingRule = 'preserve';
        if ~all(ismember(requiredVariables, options.VariableNames))
            warning('Skipping %s: required position fields were not found.', ...
                lidarFiles(fileIndex).name);
            continue;
        end
        options.SelectedVariableNames = requiredVariables;
        dailyTable = readtable(fullPath, options);

        rawTime = dailyTable.Date_time;
        if isdatetime(rawTime)
            profileTime = rawTime;
        elseif isnumeric(rawTime)
            profileTime = datetime(rawTime, 'ConvertFrom', 'excel');
        else
            try
                profileTime = datetime(rawTime, 'InputFormat', 'yyyyMMdd HH:mm:ss');
            catch
                profileTime = datetime(rawTime);
            end
        end
        if isempty(profileTime.TimeZone)
            profileTime.TimeZone = 'UTC+8';
        else
            profileTime = datetime(profileTime, 'TimeZone', 'UTC+8');
        end
        dailyTable.Date_time = profileTime;

        valid = ~isnat(dailyTable.Date_time) & ...
                ~isnan(dailyTable.Longitude) & ~isnan(dailyTable.Latitude);
        dailyTable = dailyTable(valid, requiredVariables);
        if ~isempty(dailyTable)
            rawTrack = [rawTrack; dailyTable]; %#ok<AGROW>
        end
    catch exception
        warning('Skipping %s: %s', lidarFiles(fileIndex).name, exception.message);
    end
end

if isempty(rawTrack)
    error('No valid vessel positions were read from the lidar files.');
end

rawTrack = sortrows(rawTrack, 'Date_time');
deltaSeconds = seconds(diff(rawTrack.Date_time));
deltaSeconds = [deltaSeconds; median(deltaSeconds, 'omitnan')];
deltaSeconds(deltaSeconds > 3600) = 0;
rawTrack.Stay_Seconds = deltaSeconds;

rawTrack.Grid_Lon = round(rawTrack.Longitude / gridResolution) * gridResolution;
rawTrack.Grid_Lat = round(rawTrack.Latitude / gridResolution) * gridResolution;
rawTrack.Grid_Lon(rawTrack.Grid_Lon < 0) = ...
    rawTrack.Grid_Lon(rawTrack.Grid_Lon < 0) + 360;
rawTrack.Hour_Start = dateshift(rawTrack.Date_time, 'start', 'hour');

[groupIndex, hour_start, lon_center, lat_center] = findgroups( ...
    rawTrack.Hour_Start, rawTrack.Grid_Lon, rawTrack.Grid_Lat);
totalSeconds = splitapply(@sum, rawTrack.Stay_Seconds, groupIndex);
point_counts = splitapply(@numel, rawTrack.Stay_Seconds, groupIndex);
stay_hours = totalSeconds / 3600;

resultTable = table(hour_start, lon_center, lat_center, point_counts, stay_hours);
resultTable = resultTable(resultTable.stay_hours > 0.01, :);
resultTable = sortrows(resultTable, {'hour_start', 'lon_center', 'lat_center'});

outputFolder = fileparts(outputFile);
if ~isempty(outputFolder) && ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end
writetable(resultTable, outputFile);
fprintf('Wrote %d residence-time rows to %s\n', height(resultTable), outputFile);
end
