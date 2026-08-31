%=====================================================================
%  Sci-Vis: ERA5 vs Lidar (方块彩带版 + 彻底补全180度以东大陆 + 完美高亮)
%=====================================================================
clc; clear; close all;

%% ====================================================================
%              Part 0: 路径与参数配置
% ====================================================================
scriptFolder = fileparts(mfilename('fullpath'));
addpath(scriptFolder);
cfg = project_config();
stayInfoFile    = cfg.stayInfoFile;
lidarDataFolder = cfg.lidarDataFolder;
outputFolder    = fullfile(cfg.outputRoot, 'fig03');

color_ocean     = [0.92, 0.96, 0.98];  % 淡蓝灰色海洋背景
color_land      = [0.80, 0.82, 0.81];  % 中性蓝灰色陆地

FIXED_MAX_DUR   = 2.5; % 锁定色条最大值

if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end

%% ====================================================================
%              Part 1 & 2: 数据读取 
% ====================================================================
fprintf('>>> [1/3] 读取 ERA5 格点数据...\n');
stayData = readtable(stayInfoFile);
try
    if ~isdatetime(stayData.hour_start)
        try, stayData.hour_start_utc = datetime(stayData.hour_start, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
        catch, stayData.hour_start_utc = datetime(stayData.hour_start); end
    else, stayData.hour_start_utc = stayData.hour_start; end
    if isempty(stayData.hour_start_utc.TimeZone), stayData.hour_start_utc.TimeZone = 'UTC+8'; end
    stayData.hour_start_utc = datetime(stayData.hour_start_utc, 'TimeZone', 'UTC');
catch, error('时间解析失败'); end
FinalData = sortrows(stayData, 'hour_start_utc');

fprintf('>>> [2/3] 读取 Lidar 轨迹数据...\n');
lidarFiles = [dir(fullfile(lidarDataFolder, '*.csv')); dir(fullfile(lidarDataFolder, '*.xlsx'))];
if isempty(lidarFiles), error('文件夹为空'); end
allLidar = table();

for f = 1:length(lidarFiles)
    fname = lidarFiles(f).name;
    fullname = fullfile(lidarDataFolder, fname);
    try
        opts = detectImportOptions(fullname); opts.VariableNamingRule = 'preserve';
        T = readtable(fullname, opts);
        vars = lower(T.Properties.VariableNames);
        idx_t = find(ismember(vars, {'date_time','time','date','datetime'}));
        idx_lon = find(ismember(vars, {'longitude','lon','long'}));
        idx_lat = find(ismember(vars, {'latitude','lat'}));
        
        if ~isempty(idx_t) && ~isempty(idx_lon) && ~isempty(idx_lat)
            temp = T(:, [idx_t(1), idx_lon(1), idx_lat(1)]);
            temp.Properties.VariableNames = {'Date_time', 'Longitude', 'Latitude'};
            raw = temp.Date_time; tc = NaT(height(temp), 1);
            try
                if isnumeric(raw), tc = datetime(raw, 'ConvertFrom', 'excel');
                elseif iscell(raw) || isstring(raw)
                    try, tc = datetime(raw, 'InputFormat', 'yyyyMMdd HH:mm:ss');
                    catch, tc = datetime(raw); end
                elseif ischar(raw)
                    tc = datetime(string(raw), 'InputFormat', 'yyyyMMdd HH:mm:ss');
                end
            catch; end
            if height(tc) == height(temp)
                temp.Date_time = tc;
                if ~all(isnat(tc))
                    if isempty(temp.Date_time.TimeZone), temp.Date_time.TimeZone = 'UTC+8'; end
                    temp.Date_time = datetime(temp.Date_time, 'TimeZone', 'UTC');
                    allLidar = [allLidar; temp];
                end
            end
        end
    catch; end
end
if isempty(allLidar), warning('没有读取到雷达数据'); else, allLidar = sortrows(allLidar, 'Date_time'); end

% 将所有西经（负数）转换为 0~360 体系，补全180度以东航线
FinalData.lon_center(FinalData.lon_center < 0) = FinalData.lon_center(FinalData.lon_center < 0) + 360;
allLidar.Longitude(allLidar.Longitude < 0) = allLidar.Longitude(allLidar.Longitude < 0) + 360;

%% ====================================================================
%              Part 3: 绘制全局航线轨迹
% ====================================================================
fprintf('>>> [3/3] 开始计算停留时间并绘图...\n');

% 【核心修复】：直接读取 X 和 Y 的物理坐标系，绕开地理自动折叠限制
try
    land_shapes = shaperead('landareas'); % 不再使用 'UseGeoCoords'
    land_shapes_ext = land_shapes;
    for idx = 1:length(land_shapes_ext)
        land_shapes_ext(idx).X = land_shapes_ext(idx).X + 360; % 在物理图层向右平移360
        % 同步更新边界框以防渲染剔除
        land_shapes_ext(idx).BoundingBox(:,1) = land_shapes_ext(idx).BoundingBox(:,1) + 360;
    end
    land_shapes = [land_shapes; land_shapes_ext]; 
catch
    land_shapes = [];
end

% --- 1. 画布设置 ---
fig = figure('visible', 'on', 'Position', [60, 120, 1450, 760], 'Color', 'w'); 
ax = axes; hold(ax, 'on');
set(ax, 'Color', color_ocean);

% 直接将物理多边形画入坐标轴
if ~isempty(land_shapes)
    mapshow(ax, land_shapes, 'FaceColor', color_land, 'EdgeColor', 'none'); 
end

% --- 2. 视野调整 ---
lon_min_view = 45;   
lon_max_view = 270;  
lat_min_view = -85; 
lat_max_view = 45;  

xlim([lon_min_view, lon_max_view]);
ylim([lat_min_view, lat_max_view]);

% 仅调整绘图区为更横向的版式，其余地图范围保持不变
pbaspect(ax, [1.70, 1, 1]);

res = 0.25; half = 0.125;

% --- 3. 核心计算 ---
[unique_grids, ~, ~] = unique([FinalData.lat_center, FinalData.lon_center], 'rows');
num_grids = size(unique_grids, 1);
grid_durations = zeros(num_grids, 1);

for k = 1:num_grids
    u_lat = unique_grids(k, 1);
    u_lon = unique_grids(k, 2);
    
    in_box = allLidar.Longitude >= (u_lon-half) & allLidar.Longitude < (u_lon+half) & ...
             allLidar.Latitude >= (u_lat-half) & allLidar.Latitude < (u_lat+half);
             
    if any(in_box)
        grid_time = allLidar.Date_time(in_box);
        days_in_grid = unique(dateshift(grid_time, 'start', 'day'));
        total_hours = 0;
        for d = 1:length(days_in_grid)
            pts_today = grid_time(dateshift(grid_time, 'start', 'day') == days_in_grid(d));
            total_hours = total_hours + hours(max(pts_today) - min(pts_today));
        end
        if total_hours <= 0, total_hours = 0.1; end 
        grid_durations(k) = total_hours;
    end
end

% --- 4. 绘制彩色轨迹方块 ---
valid_idx = grid_durations > 0;
plot_lon = unique_grids(valid_idx, 2);
plot_lat = unique_grids(valid_idx, 1);
plot_dur = grid_durations(valid_idx);

plot_dur(plot_dur > FIXED_MAX_DUR) = FIXED_MAX_DUR;

colormap(ax, turbo(256)); 
caxis([0, FIXED_MAX_DUR]); 

scatter(plot_lon, plot_lat, 35, plot_dur, 'filled', 'Marker', 's', 'MarkerEdgeColor', 'none', 'MarkerFaceAlpha', 0.9);

% =====================================================================
% 【黑底黄框高亮起点】
% =====================================================================
local_time = FinalData.hour_start_utc;
local_time.TimeZone = 'UTC+8';
target_date = datetime(2023, 11, 1, 'TimeZone', 'UTC+8');

day_mask = (dateshift(local_time, 'start', 'day') == target_date);

if any(day_mask)
    mark_lat = FinalData.lat_center(find(day_mask, 1, 'first'));
    mark_lon = FinalData.lon_center(find(day_mask, 1, 'first'));
    
    plot(mark_lon, mark_lat, 's', 'MarkerSize', 20, 'MarkerEdgeColor', 'k', ...
         'MarkerFaceColor', 'none', 'LineWidth', 4.5);
    plot(mark_lon, mark_lat, 's', 'MarkerSize', 20, 'MarkerEdgeColor', '#FFD700', ...
         'MarkerFaceColor', 'none', 'LineWidth', 2.0);
         
    % 将文字标签稍向右上方偏移，避免与航线重叠
    text(mark_lon + 6, mark_lat + 2, ' Nov 1,2023', 'Color', 'k', ...
         'BackgroundColor', '#FFD700', 'EdgeColor', 'k', 'Margin', 2, ...
         'FontSize', 12, 'FontWeight', 'bold');
end

% --- 5. 坐标轴美化 (严格复刻刻度) ---
box on; 
set(ax, 'Layer', 'top', 'FontName', 'Times New Roman', ...
    'FontSize', 16, 'FontWeight', 'bold', 'LineWidth', 1.5, 'TickDir', 'in');

xlabel('Longitude', 'FontSize', 18, 'FontWeight', 'bold'); 
ylabel('Latitude',  'FontSize', 18, 'FontWeight', 'bold');

yticks(-75:15:60);
yt = yticks; yl = cell(size(yt));
for k=1:length(yt)
    if yt(k) > 0
        yl{k} = sprintf('%d°N', yt(k)); 
    elseif yt(k) < 0
        yl{k} = sprintf('%d°S', abs(yt(k))); 
    else
        yl{k} = '0°';
    end
end
yticklabels(yl); 

xticks(45:45:315);
xt = xticks; xl = cell(size(xt));
for k=1:length(xt)
    xl{k} = sprintf('%d°E', xt(k)); 
end
xticklabels(xl); 

title('\bf Full Voyage: Ship Stay Duration per Grid', 'Interpreter', 'tex', 'FontSize', 18);

% === 6. 色标设置 ===
cb = colorbar;
cb.Limits = [0, FIXED_MAX_DUR]; 
cb.Label.String = 'Stay Duration (Hours)'; 
cb.Label.FontSize = 16;
cb.Label.FontWeight = 'bold';
cb.FontSize = 14;
cb.FontWeight = 'bold';

tick_vals = 0 : 0.5 : FIXED_MAX_DUR;
cb.Ticks = tick_vals;

tick_labels = cell(length(tick_vals), 1);
for i = 1:length(tick_vals)
    if i == length(tick_vals)
        tick_labels{i} = ['\geq', num2str(tick_vals(i))]; 
    else
        tick_labels{i} = num2str(tick_vals(i));
    end
end
cb.TickLabels = tick_labels;

drawnow;
figure(fig);

savePath = fullfile(outputFolder, 'Full_Voyage_ScatterTrack_Final.png');
exportgraphics(fig, savePath, 'Resolution', 600, 'BackgroundColor', 'white');
fprintf('全部完成！180度以东的新西兰与南极东部大陆已完美渲染。\n');
