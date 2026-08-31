clc; clear; close all;
%% ======================= 0. 参数设置 =======================
scriptFolder = fileparts(mfilename('fullpath'));
addpath(scriptFolder);
cfg = project_config();
era5DataFolder  = cfg.era5DataFolder;
stayInfoFile    = cfg.stayInfoFile;
lidarDataFolder = cfg.lidarDataFolder;
outputFolder    = fullfile(cfg.outputRoot, 'fig01');

% --- 筛选参数 ---
PLOT_HEIGHT_MIN = 150; 
PLOT_HEIGHT_MAX = 3000;
MAX_VALID_WS    = 100;    
g = 9.81;

if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end

%% ======================= 1. 准备工作 =======================
fprintf('正在读取基础数据...\n');
stayData = readtable(stayInfoFile);
try
    temp_time = datetime(stayData.hour_start);
    temp_time.TimeZone = 'UTC+8'; 
    stayData.hour_start_utc = datetime(temp_time, 'TimeZone', 'UTC');
catch
    error('时间格式转换失败。');
end

uniqueHours = unique(stayData.hour_start_utc);
total_hours = numel(uniqueHours);
lidarFiles  = [dir(fullfile(lidarDataFolder, '*.csv')); dir(fullfile(lidarDataFolder, '*.xlsx'))];

% 全局容器
Global_ERA5_WS = []; Global_Lidar_WS = [];
Global_Time = [];    Global_Lat = [];

current_nc_date = datetime(1900,1,1,'TimeZone','UTC');
current_era5_data = struct();

%% ======================= 2. 数据处理循环 =======================
fprintf('开始时空匹配 (保留所有近岸与大洋数据)...\n');
tic;
for i = 1:total_hours
    if mod(i, 100) == 0, fprintf('进度: %.1f%%\n', (i/total_hours)*100); end
    
    t_start = uniqueHours(i); 
    t_end   = t_start + hours(1);
    
    % --- 2.1 提取 Lidar 数据 ---
    all_lidar_profiles_list = {};
    % Lidar daily filenames use local time (UTC+8), whereas t_start is UTC.
    file_date_str = datestr(datetime(t_start, 'TimeZone', 'UTC+8'), 'yyyymmdd');
    for f = 1:length(lidarFiles)
        if ~contains(lidarFiles(f).name, file_date_str), continue; end
        try
            opts = detectImportOptions(fullfile(lidarDataFolder, lidarFiles(f).name));
            opts.VariableNamingRule = 'preserve';
            T = readtable(fullfile(lidarDataFolder, lidarFiles(f).name), opts);
            if ~ismember('Date_time', T.Properties.VariableNames), continue; end
            t_col = T.Date_time;
            if ~isdatetime(t_col), t_col = datetime(t_col, 'InputFormat', 'yyyyMMdd HH:mm:ss'); end
            t_col.TimeZone = 'UTC+8'; t_col_utc = datetime(t_col, 'TimeZone', 'UTC');
            rows = find(t_col_utc >= t_start & t_col_utc < t_end);
            if isempty(rows), continue; end
            subT = T(rows, :);
            vNames = subT.Properties.VariableNames;
            l_h = []; l_ws = [];
            for k = 1:length(vNames)
                tok = regexp(vNames{k}, '^(\d+\.?\d*)m WindSpeed$', 'tokens');
                if ~isempty(tok)
                    h_val = str2double(tok{1}{1});
                    ws_vals = subT.(vNames{k});
                    if iscell(ws_vals), ws_vals = str2double(ws_vals); end
                    ws_vals(ws_vals >= MAX_VALID_WS | ws_vals < 0) = NaN;
                    ws_avg = mean(ws_vals, 'omitnan'); 
                    if ~isnan(ws_avg), l_h = [l_h; h_val]; l_ws = [l_ws; ws_avg]; end
                end
            end
            if ~isempty(l_h), all_lidar_profiles_list{end+1} = table(l_h, l_ws); end
        catch, continue; end
    end
    if isempty(all_lidar_profiles_list), continue; end
    lidar_prof = all_lidar_profiles_list{1}; 
    
    % --- 2.2 读取 ERA5 ---
    hourGridData = stayData(stayData.hour_start_utc == t_start, :);
    if isempty(hourGridData), continue; end
    
    % 仅保留计算纬度，移除离岸距离计算与跳过逻辑
    mean_lat = mean(hourGridData.lat_center);
    
    targetDate = dateshift(t_start, 'start', 'day');
    if targetDate ~= current_nc_date
        current_nc_date = targetDate;
        ncPath = fullfile(era5DataFolder, sprintf('%s_part1.nc', datestr(targetDate, 'yyyy_mm_dd')));
        if exist(ncPath, 'file')
            era5_lon = ncread(ncPath, 'longitude'); era5_lat = ncread(ncPath, 'latitude');
            if any(era5_lon < 0), era5_lon(era5_lon < 0) = era5_lon(era5_lon < 0) + 360; end
            [era5_lon, lon_idx_sort] = sort(era5_lon);
            current_era5_data = struct('u', ncread(ncPath,'u'), 'v', ncread(ncPath,'v'), 'z', ncread(ncPath,'z'));
            current_era5_data.u = current_era5_data.u(lon_idx_sort,:,:,:);
            current_era5_data.v = current_era5_data.v(lon_idx_sort,:,:,:);
            current_era5_data.z = current_era5_data.z(lon_idx_sort,:,:,:);
        end
    end
    
    % 加权平均与插值
    total_stay = sum(hourGridData.stay_hours);
    time_idx = hour(t_start) + 1;
    e_ws_prof = zeros(size(current_era5_data.u, 3), 1);
    e_h_prof = zeros(size(current_era5_data.u, 3), 1);
    
    for j = 1:height(hourGridData)
        w = hourGridData.stay_hours(j)/total_stay;
        [~, lon_ix] = min(abs(era5_lon - hourGridData.lon_center(j)));
        [~, lat_ix] = min(abs(era5_lat - hourGridData.lat_center(j)));
        u_slice = squeeze(current_era5_data.u(lon_ix, lat_ix, :, time_idx));
        v_slice = squeeze(current_era5_data.v(lon_ix, lat_ix, :, time_idx));
        z_slice = squeeze(current_era5_data.z(lon_ix, lat_ix, :, time_idx));
        e_ws_prof = e_ws_prof + sqrt(u_slice.^2 + v_slice.^2) * w;
        e_h_prof = e_h_prof + (z_slice/g) * w;
    end
    
    e_ws_interp = interp1(e_h_prof, e_ws_prof, lidar_prof.l_h, 'linear', NaN);
    valid = ~isnan(lidar_prof.l_ws) & ~isnan(e_ws_interp) & lidar_prof.l_h >= PLOT_HEIGHT_MIN & lidar_prof.l_h <= PLOT_HEIGHT_MAX;
    
    if any(valid)
        Global_Lidar_WS = [Global_Lidar_WS; lidar_prof.l_ws(valid)];
        Global_ERA5_WS  = [Global_ERA5_WS; e_ws_interp(valid)];
        Global_Time     = [Global_Time; repmat(t_start, sum(valid), 1)];
        Global_Lat      = [Global_Lat; repmat(mean_lat, sum(valid), 1)];
    end
end
fprintf('时空匹配完成，耗时 %.1f 秒。\n', toc);

%% ======================= 4. 绘制航线纬度随时间变化图 (网格调浅 + 纯英文格式) =======================
if isempty(Global_Time) || isempty(Global_Lat)
    error('未找到轨迹数据，请确保已运行前面的数据读取和匹配环节。');
end

% 1. 创建大幅宽比例画布
fig_track = figure('Name', 'Ship Track by Wind Belts (Styled)', 'Color', 'w', 'Position', [100, 100, 1400, 450], 'Visible', 'on');
ax = axes(fig_track);
hold(ax, 'on');

% 2. 定义背景颜色
c_westerlies = [0.94, 0.98, 0.94]; % 淡绿
c_trades     = [0.99, 0.96, 0.93]; % 淡橙
c_polar      = [0.94, 0.96, 0.99]; % 淡蓝

% 计算时间范围
t_min = dateshift(min(Global_Time), 'start', 'day');
t_max = dateshift(max(Global_Time), 'start', 'day') + days(2);
xlim_dates = [t_min, t_max];

% 3. 绘制背景色块 (Patch)
patch([t_min t_max t_max t_min], [30 30 60 60], c_westerlies, 'EdgeColor', 'none');
patch([t_min t_max t_max t_min], [0 0 30 30], c_trades, 'EdgeColor', 'none');
patch([t_min t_max t_max t_min], [-30 -30 0 0], c_trades, 'EdgeColor', 'none');
patch([t_min t_max t_max t_min], [-60 -60 -30 -30], c_westerlies, 'EdgeColor', 'none');
patch([t_min t_max t_max t_min], [-90 -90 -60 -60], c_polar, 'EdgeColor', 'none');

% 4. 绘制风带分界虚线
plot([t_min, t_max], [30, 30], 'k--', 'LineWidth', 1.2, 'Color', [0.3 0.3 0.3]);
plot([t_min, t_max], [0, 0], 'k--', 'LineWidth', 1.2, 'Color', [0.3 0.3 0.3]); 
plot([t_min, t_max], [-30, -30], 'k--', 'LineWidth', 1.2, 'Color', [0.3 0.3 0.3]);
plot([t_min, t_max], [-60, -60], 'k--', 'LineWidth', 1.2, 'Color', [0.3 0.3 0.3]);

% 5. 处理轨迹数据 (按天求平均纬度)
t_days = dateshift(Global_Time, 'start', 'day');
[unique_days, ~, idx] = unique(t_days);
daily_lat = accumarray(idx, Global_Lat, [], @mean);

% 绘制蓝色航线
plot(unique_days, daily_lat, '-', 'Color', [0.1, 0.3, 0.8], 'LineWidth', 2);

% 6. 添加纬度数值标注
step = max(1, floor(length(unique_days) / 30));
for k = 1:step:length(unique_days)
    text(unique_days(k), daily_lat(k) + 3.5, num2str(round(daily_lat(k))), ...
        'FontSize', 8, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
        'Color', [0.15 0.15 0.15]);
end

% 7. 添加风带名称文字
txt_x = t_min + days(2);
text(txt_x, 45, '\bf Westerlies (N)',      'Color', [0.1, 0.4, 0.1], 'FontSize', 12);
text(txt_x, 15, '\bf Trade Winds (N)',     'Color', [0.6, 0.4, 0.0], 'FontSize', 12);
text(txt_x, -15,'\bf Trade Winds (S)',     'Color', [0.6, 0.4, 0.0], 'FontSize', 12);
text(txt_x, -45,'\bf Westerlies (S)',      'Color', [0.1, 0.4, 0.1], 'FontSize', 12);
text(txt_x, -75,'\bf Polar Easterlies (S)','Color', [0.2, 0.3, 0.7], 'FontSize', 12);

% 8. 坐标轴美化与英文强制格式化
ylim([-90, 60]); 
yticks(-90:15:60);
xlim(xlim_dates);

% X 轴刻度：每 5 天
ax.XTick = t_min : days(5) : t_max;

% 【重点修改 1：屏蔽中文年份，强制生成纯英文数字字符串】
ax.XTickLabel = datestr(ax.XTick, 'mm/dd'); 
ax.XTickLabelRotation = 45;

% 【重点修改 2：把年份统一用英文写进 X 轴的 Label 里】
xlabel('\bf Date (mm/dd)   [ 2023 - 2024 ]', 'FontSize', 14);
ylabel('\bf Latitude (\circ)', 'FontSize', 14, 'Interpreter', 'tex');

% 图层在顶
set(ax, 'TickDir', 'in', 'FontSize', 11, 'FontWeight', 'bold', ...
    'LineWidth', 1.2, 'Box', 'on', 'Layer', 'top');

% 【重点修改 3：调浅背景网格线】
grid on;
ax.GridColor = [0.5 0.5 0.5]; % 将网格线改为中灰色
ax.GridAlpha = 0.15;          % 降低透明度 (越接近0越浅)
ax.GridLineStyle = '-';

drawnow;

savePath = fullfile(outputFolder, 'Fig01b_latitude_regimes.png');
exportgraphics(fig_track, savePath, 'Resolution', 600, ...
    'BackgroundColor', 'white');
fprintf('Figure saved to:\n%s\n', savePath);
