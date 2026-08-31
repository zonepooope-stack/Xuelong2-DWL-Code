% Cruise Track Visualization (Enhanced Visibility Version)
% Features: Larger Fonts, Bold Red Route, Thicker Lines, 2D Satellite
clc; clear; close all;

% === 1. Data Reading (Standard block) ===
scriptFolder = fileparts(mfilename('fullpath'));
addpath(scriptFolder);
cfg = project_config();
dataFolder = cfg.lidarDataFolder;
outputFolder = fullfile(cfg.outputRoot, 'fig01');
if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end
files = [dir(fullfile(dataFolder, '*.xlsx')); dir(fullfile(dataFolder, '*.csv'))];
allData = table();

fprintf('Reading data...\n');
for k = 1:length(files)
    filename = fullfile(dataFolder, files(k).name);
    try
        data = readtable(filename);
        varNames = lower(data.Properties.VariableNames);
        if sum(ismember({'date_time','longitude','latitude'}, varNames)) == 3
             time = data.Date_time; lon = data.Longitude; lat = data.Latitude;
        else
             time = data{:, strcmpi(data.Properties.VariableNames, 'Date_time')};
             lon = data{:, strcmpi(data.Properties.VariableNames, 'Longitude')};
             lat = data{:, strcmpi(data.Properties.VariableNames, 'Latitude')};
        end
        try; time = datetime(time, 'InputFormat', 'yyyyMMdd HH:mm:ss');
        catch; time = datetime(time, 'ConvertFrom', 'excel'); end
        temp = table(time, lon, lat);
        allData = [allData; temp];
    catch
    end
end

if isempty(allData)
    error('No data found!');
end
allData = sortrows(allData, 'time');
allData.lon = unwrap(allData.lon * pi/180) * 180/pi; 

% === 2. Create Figure & Setup Map ===
% Increased figure size slightly for better layout with large fonts
figure('Color', 'w', 'Position', [100 50 1300 900]);
gx = geoaxes;
geobasemap(gx, 'satellite'); 
hold(gx, 'on');

% --- [Modification 1: Larger Axis Fonts] ---
gx.LatitudeLabel.String = 'Latitude';
gx.LongitudeLabel.String = 'Longitude';
gx.FontName = 'Arial'; 
gx.FontSize = 20; % Increased from 11 to 14 (Axis labels & ticks)
gx.TickDir = 'out';
gx.FontWeight = 'bold'; % Added bold for axis tick labels

% === 3. Plot Route (Significantly Enhanced) ===
% --- [Modification 2: bolder, Brighter Route] ---
% Color: 'r' (Pure bright red for maximum contrast)
% LineWidth: 3.5 (Much thicker than before)
geoplot(gx, allData.lat, allData.lon, '-', 'Color', 'r', 'LineWidth', 3.5);

% === 4. Smart Annotation (Larger Text & Thicker Leaders) ===
% Define sites and offsets (Same positions as before, they work well)
sites(1).name = 'Shanghai, China (Start)';
sites(1).lat = 31.23;  sites(1).lon = 121.47;
sites(1).text_lat = 31.23; sites(1).text_lon = 160;

sites(2).name = 'Christchurch, NZ';
sites(2).lat = -43.53; sites(2).lon = 172.63;
sites(2).text_lat = -35.53; sites(2).text_lon = 195; % Slight adjust for larger text box

sites(3).name = 'Qinling Station';
sites(3).lat = -74.9;  sites(3).lon = 163.7;
sites(3).text_lat = -77; sites(3).text_lon = 135;

% sites(4).name = 'McMurdo Station';
% sites(4).lat = -77.85; sites(4).lon = 166.67;
% sites(4).text_lat = -79.5; sites(4).text_lon = 176;

% Loop to plot
for i = 1:length(sites)
    % A. Draw Marker (Larger Yellow Dot)
    geoscatter(gx, sites(i).lat, sites(i).lon, 100, 'filled', ... % Size 80 -> 100
        'MarkerFaceColor', 'y', 'MarkerEdgeColor', 'k', 'LineWidth', 1.5);
    
    % B. Draw Leader Line (Thicker white line)
    % LineWidth increased to 2.0 to match bolder text
    geoplot(gx, [sites(i).lat, sites(i).text_lat], ...
                [sites(i).lon, sites(i).text_lon], ...
                '-', 'Color', [1 1 1], 'LineWidth', 2.0); 
            
    % C. Draw Text Label (Larger Font)
    % FontSize increased from 10 to 13
    text(gx, sites(i).text_lat, sites(i).text_lon, sites(i).name, ...
        'Color', 'k', 'FontSize', 13, 'FontWeight', 'bold', ...
        'BackgroundColor', [1 1 1 0.85], 'Margin', 4, ... % Slightly more opaque box
        'HorizontalAlignment', 'center');
end

% === 5. Final Adjustments ===
% --- [Modification 3: Larger Title Font] ---
% title(gx, 'Cruise Track of the 40th CHINARE (R/V Xuelong 2)', ...
%     'FontSize', 25, 'FontWeight', 'bold'); % Increased from 16 to 22

%Set Limits
geolimits(gx, [-85 40], [100 190]); 

savePath = fullfile(outputFolder, 'Fig01a_cruise_trajectory.png');
exportgraphics(gcf, savePath, 'Resolution', 600, 'BackgroundColor', 'white');

disp('✅ Enhanced visibility plot generated.');
disp('   - Route is now significantly thicker and brighter red.');
disp('   - All fonts (Title, Axis, Labels) have been increased in size.');
fprintf('Figure saved to:\n%s\n', savePath);
