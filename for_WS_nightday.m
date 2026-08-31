%=====================================================================
%  全能版：ERA5 vs Lidar (独立输出：纯白天 & 纯夜晚 + 拟合线 + 弹窗)
%  更新内容：
%     1. 增加 Linear Fit (拟合线) 绘制。
%     2. figure 设置为 visible on，并且不关闭，运行后直接弹窗。
%=====================================================================
clc; clear; close all;
%% ======================= 0. 参数设置 =======================
PLOT_HEIGHT_MIN = 0; PLOT_HEIGHT_MAX = 3000;
MAX_VALID_WS = 100; 
% === Portable repository paths ===
scriptFolder = fileparts(mfilename('fullpath'));
addpath(scriptFolder);
cfg = project_config();
era5DataFolder  = cfg.era5DataFolder;
stayInfoFile    = cfg.stayInfoFile;
lidarDataFolder = cfg.lidarDataFolder;
outputFolder    = cfg.outputRoot;
% 输出文件夹
outputImgFolder = fullfile(outputFolder, 'fig09'); 
if ~exist(outputImgFolder, 'dir'), mkdir(outputImgFolder); end
g = 9.81;
SOLAR_ELEV_THRESHOLD = 0; % >0 为白天

%% ======================= 1. 数据准备 =======================
fprintf('正在读取船舶停留时间文件...\n');
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
lidarFiles = [dir(fullfile(lidarDataFolder, '*.csv')); dir(fullfile(lidarDataFolder, '*.xlsx'))];

Global_ERA5 = [];
Global_Lidar = [];
Global_Time = []; 
Global_IsDay = logical([]); 
current_nc_date = datetime(1900,1,1,'TimeZone','UTC');
current_era5_data = struct();
era5VarNames = {};

%% ======================= 2. 数据处理循环 =======================
fprintf('开始处理数据 (收集所有点)...\n');
tic;
for i = 1:total_hours
    if mod(i, 50) == 0, fprintf('进度: %d / %d (%.1f%%)\n', i, total_hours, (i/total_hours)*100); end
    t_start = uniqueHours(i); t_end = t_start + hours(1);
    
    % --- 读取 Lidar ---
    all_lidar_profiles_list = {};
    for f = 1:length(lidarFiles)
        try
            file_date_str = datestr(datetime(t_start, 'TimeZone', 'UTC+8'), 'yyyymmdd');
            if ~contains(lidarFiles(f).name, file_date_str), continue; end
            opts = detectImportOptions(fullfile(lidarDataFolder, lidarFiles(f).name));
            opts.VariableNamingRule = 'preserve';
            T = readtable(fullfile(lidarDataFolder, lidarFiles(f).name), opts);
            if isdatetime(T.Date_time), t_col = T.Date_time; else, t_col = datetime(T.Date_time, 'InputFormat', 'yyyyMMdd HH:mm:ss'); end
            t_col.TimeZone = 'UTC+8'; t_col_utc = datetime(t_col, 'TimeZone', 'UTC');
            rows = find(t_col_utc >= t_start & t_col_utc < t_end);
            if isempty(rows), continue; end
            subT = T(rows, :);
            lidar_h = []; lidar_ws = [];
            vNames = subT.Properties.VariableNames;
            for k = 1:length(vNames)
                tok = regexp(vNames{k}, '^(\d+\.?\d*)m WindSpeed', 'tokens', 'once');
                if ~isempty(tok) && ~contains(vNames{k}, 'Max') && ~contains(vNames{k}, 'Min')
                    h_val = str2double(tok{1});
                    ws_vals = subT.(vNames{k});
                    if size(ws_vals, 2) > 1, ws_vals = ws_vals(:, 1); end 
                    if iscell(ws_vals), ws_vals = str2double(ws_vals); end
                    ws_vals(ws_vals >= MAX_VALID_WS | ws_vals < 0) = NaN;
                    ws_avg = mean(ws_vals, 'omitnan'); 
                    if ~isnan(ws_avg), lidar_h = [lidar_h; h_val]; lidar_ws = [lidar_ws; ws_avg]; end
                end
            end
            if ~isempty(lidar_h)
                all_lidar_profiles_list{end+1} = table(lidar_h, lidar_ws, 'VariableNames', {'Height', 'WindSpeed'});
            end
        catch, continue; end
    end
    lidar_avg_profile = [];
    if ~isempty(all_lidar_profiles_list), lidar_avg_profile = all_lidar_profiles_list{1}; lidar_avg_profile.Properties.VariableNames = {'Height_m', 'wind_speed'}; end
    if isempty(lidar_avg_profile), continue; end 
    
    % --- 读取 ERA5 ---
    hourGridData = stayData(stayData.hour_start_utc == t_start, :);
    if isempty(hourGridData), continue; end
    targetDate = dateshift(t_start, 'start', 'day');
    time_idx = hour(t_start) + 1;
    if targetDate ~= current_nc_date
        current_nc_date = targetDate;
        ncFilename = sprintf('%s_part1.nc', datestr(targetDate, 'yyyy_mm_dd'));
        ncPath = fullfile(era5DataFolder, ncFilename);
        if exist(ncPath, 'file')
            try
                ncInfo = ncinfo(ncPath); allVars = {ncInfo.Variables.Name};
                era5VarNames = setdiff(allVars, {'longitude', 'latitude', 'pressure_level', 'valid_time', 'time', 'number', 'expver'});
                era5_lon = ncread(ncPath, 'longitude'); era5_lat = ncread(ncPath, 'latitude'); era5_pressure = ncread(ncPath, 'pressure_level');
                if any(era5_lon < 0), era5_lon(era5_lon < 0) = era5_lon(era5_lon < 0) + 360; end
                [era5_lon, lon_sort_idx] = sort(era5_lon);
                current_era5_data = struct();
                for v = 1:length(era5VarNames)
                    vn = era5VarNames{v}; raw = ncread(ncPath, vn);
                    if ndims(raw)==4, raw = raw(lon_sort_idx,:,:,:); else, raw = raw(lon_sort_idx,:,:); end
                    current_era5_data.(vn) = raw;
                end
            catch, current_era5_data = struct(); end
        else, current_era5_data = struct(); end
    end
    if isempty(fieldnames(current_era5_data)), continue; end
    total_stay = sum(hourGridData.stay_hours);
    if total_stay > 0
        hourly_vals = zeros(length(era5_pressure), length(era5VarNames));
        avg_lat_hour = sum(hourGridData.lat_center .* hourGridData.stay_hours) / total_stay;
        avg_lon_hour = sum(hourGridData.lon_center .* hourGridData.stay_hours) / total_stay;
        for j = 1:height(hourGridData)
            w = hourGridData.stay_hours(j) / total_stay;
            [~, lon_idx] = min(abs(era5_lon - hourGridData.lon_center(j)));
            [~, lat_idx] = min(abs(era5_lat - hourGridData.lat_center(j)));
            for v = 1:length(era5VarNames)
                vn = era5VarNames{v}; data = current_era5_data.(vn);
                if ndims(data)==4, val = squeeze(data(lon_idx, lat_idx, :, time_idx)); else, val = squeeze(data(lon_idx, lat_idx, :)); end
                hourly_vals(:, v) = hourly_vals(:, v) + val * w;
            end
        end
        era5_tab = array2table(hourly_vals, 'VariableNames', era5VarNames);
        era5_tab.Height_m = era5_tab.z / g;
        era5_tab.wind_speed = sqrt(era5_tab.u.^2 + era5_tab.v.^2);
        
        [e_h, sort_i] = sort(era5_tab.Height_m); e_ws = era5_tab.wind_speed(sort_i);
        mask = ~isnan(e_h) & ~isnan(e_ws); e_h = e_h(mask); e_ws = e_ws(mask);
        
        if length(e_h) > 1
            l_h = lidar_avg_profile.Height_m; l_ws = lidar_avg_profile.wind_speed;
            e_ws_interp = interp1(e_h, e_ws, l_h, 'linear', NaN);
            valid = ~isnan(l_ws) & ~isnan(e_ws_interp) & l_h >= PLOT_HEIGHT_MIN & l_h <= PLOT_HEIGHT_MAX;
            if any(valid)
                count = sum(valid);
                Global_Lidar = [Global_Lidar; l_ws(valid)];
                Global_ERA5 = [Global_ERA5; e_ws_interp(valid)];
                Global_Time = [Global_Time; repmat(t_start, count, 1)];
                sun_elev = calculate_sun_elevation(t_start, avg_lat_hour, avg_lon_hour);
                is_day_flag = sun_elev > SOLAR_ELEV_THRESHOLD;
                Global_IsDay = [Global_IsDay; repmat(logical(is_day_flag), count, 1)];
            end
        end
    end
end
fprintf('\n数据收集完成。共 %d 个点。\n', length(Global_Lidar));

%% ======================= 3. 绘图 (Day/Night 并排共享Y轴) =======================
fprintf('正在绘制最终合并图 (Shared Y-Axis)...\n');

% 调用合并绘图函数
save_name = fullfile(outputImgFolder, '00_Total_DayNight_Combined.png');
plotCombinedScatter(Global_ERA5, Global_Lidar, Global_IsDay, save_name);

fprintf('完成！图片已保存在: %s\n', save_name);


%% ======================= 4. 辅助函数 =======================
function plotCombinedScatter(era5, lidar, is_day, savePath)
    % 准备数据
    is_day = logical(is_day);
    e_d = era5(is_day);  l_d = lidar(is_day);
    e_n = era5(~is_day); l_n = lidar(~is_day);
    
    % 计算统一的坐标轴范围 (取全局最大值)
    max_val = max([era5; lidar]);
    if isempty(max_val) || isnan(max_val), max_val = 20; end
    if max_val > 50, max_val = 50; end % 强制最大 50
    axis_lim = [0, max_val];
    
    % 创建画布 (宽一点，1200x600)
    fig = figure('visible', 'on', 'Color', 'w', 'Position', [100, 100, 1200, 600]);
    
    % === 定义紧凑布局位置 ===
    % [Left, Bottom, Width, Height]
    % 关键：让两个图靠得很近 (Gap 只有 0.02)
    pos1 = [0.08, 0.15, 0.40, 0.75]; % 左图
    pos2 = [0.50, 0.15, 0.40, 0.75]; % 右图 (起始位置 = 左图Left + 左图Width + 微小间距)
    
    % -----------------------
    % 左子图: Day (Cyan/Red)
    % -----------------------
    ax1 = axes('Position', pos1);
    draw_sub_scatter(ax1, e_d, l_d, 'r', 'Day', '(a) Day Time', axis_lim, true); % true = 显示Y轴标签
    
    % -----------------------
    % 右子图: Night (Blue)
    % -----------------------
    ax2 = axes('Position', pos2);
    draw_sub_scatter(ax2, e_n, l_n, 'b', 'Night', '(b) Night Time', axis_lim, false); % false = 隐藏Y轴标签
    ylabel(''); % 右图不需要 Y 轴标题
    
    % 保存
    % Use Arial bold for every text-bearing graphics object.
    set(findall(fig, '-property', 'FontName'), 'FontName', 'Arial');
    set(findall(fig, '-property', 'FontWeight'), 'FontWeight', 'bold');
    exportgraphics(fig, savePath, 'Resolution', 300);
end

function draw_sub_scatter(ax, x, y, colorChar, labelStr, panelStr, limits, showYLabel)
    axes(ax); hold on;
    
    % 1. 散点
    scatter(x, y, 20, colorChar, 'filled', 'MarkerFaceAlpha', 0.15, 'DisplayName', labelStr);
    
    % 2. 1:1 参考线
    plot(limits, limits, 'k--', 'LineWidth', 1.5, 'DisplayName', '1:1 Line');
    
    % 3. 拟合线
    if length(x) > 2
        p = polyfit(x, y, 1);
        x_fit = limits;
        y_fit = polyval(p, x_fit);
        fitStr = sprintf('Fit: y=%.2fx %+.2f', p(1), p(2));
        plot(x_fit, y_fit, '-', 'Color', [1 0 0], 'LineWidth', 2.5, 'DisplayName', fitStr);
    end
    
    % 4. 坐标轴设置
    xlim(limits); ylim(limits);
    grid on; axis square;
    box on;
    set(gca, 'LineWidth', 1.2, 'FontSize', 12);
    
    xlabel('ERA5 Wind Speed (m/s)', 'FontSize', 18, 'FontWeight', 'bold');
    
    if showYLabel
        ylabel('Lidar Wind Speed (m/s)', 'FontSize', 18, 'FontWeight', 'bold');
    else
        set(gca, 'YTickLabel', []); % 【关键】隐藏 Y 轴数值
    end
    
    % 5. 统计信息文本框 (左上角)
    s = calc_stats(x, y);
    info_str = {
        ['\bf{' panelStr '}'], ...
        sprintf('N = %d', s.N), ...
        sprintf('Bias = %.2f m/s', s.Bias), ...
        sprintf('RMSE = %.2f m/s', s.RMSE), ...
        sprintf('R = %.3f', s.R)
    };
    % 在子图坐标系内通过 normalized 坐标放置
    text(0.05, 0.95, info_str, 'Units', 'normalized', ...
        'VerticalAlignment', 'top', 'EdgeColor', 'k', 'BackgroundColor', 'w', ...
        'FontSize', 11);
    
    % 6. 图例 (右下角)
    legend('Location', 'southeast', 'FontSize', 14);
end

function s = calc_stats(x, y)
    if isempty(x)
        s.N=0; s.Bias=NaN; s.RMSE=NaN; s.R=NaN; return; 
    end
    s.N = length(x);
    diff = y - x;
    s.Bias = mean(diff);
    s.RMSE = sqrt(mean(diff.^2));
    R = corrcoef(x, y);
    if numel(R)>1, s.R = R(1,2); else, s.R = NaN; end
end
% --- 太阳高度角 ---
function elev = calculate_sun_elevation(t, lat, lon)
    d = days(t - datetime(year(t), 1, 1, 'TimeZone', 'UTC')) + 1; 
    rad = pi/180; lat_r = lat * rad;
    delta = 23.45 * sind(360/365 * (d - 81)); delta_r = delta * rad;
    utc_hours = hour(t) + minute(t)/60 + second(t)/3600;
    lst = utc_hours + lon/15; omega = (lst - 12) * 15; omega_r = omega * rad;
    sin_elev = sin(lat_r).*sin(delta_r) + cos(lat_r).*cos(delta_r).*cos(omega_r);
    elev = asin(sin_elev) / rad; 
end
