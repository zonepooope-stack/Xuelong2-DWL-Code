% =========================================================================
%  Script: ERA5 vs Lidar - 2x4 Unified Matrix Analysis (Ultimate Final Edition)
%  功能：
%     1. 数据处理：使用最新路径，网格停留时间加权提取 ERA5 (0-3000m)。
%     2. 顶级期刊排版规范：
%        - 标题极简化，仅保留 (a)-(h)。
%        - 第一行散点图使用连续日期色标，每个子图保留独立 Colorbar。
%        - 色标日期采用“日 月 / 年”两行格式。
%        - 左上角：统计指标框 (Row 1 含 N/拟合; Row 2 仅 Ratio)。
%        - 右下角：对角标注大气环流带名称 (如 N. Trade Winds)。
%        - Row 1 红色拟合线保留，Row 2 极低透明度(0.15)凸显包络带机制。
%========================================================================
clc; clear; close all;

%% ======================= 0. 参数设置 =======================
PLOT_HEIGHT_MIN = 0; 
PLOT_HEIGHT_MAX = 3000; % 严格限制在 0-3000m 
MAX_VALID_WS = 100;     

% --- Portable repository paths ---
scriptFolder = fileparts(mfilename('fullpath'));
addpath(scriptFolder);
cfg = project_config();
era5DataFolder  = cfg.era5DataFolder;
stayInfoFile    = cfg.stayInfoFile;
lidarDataFolder = cfg.lidarDataFolder;
outputGlobalFolder = fullfile(cfg.outputRoot, 'fig06');
if ~exist(outputGlobalFolder, 'dir'), mkdir(outputGlobalFolder); end
g = 9.81;
font_n = 'Arial';

%% ======================= 1. 数据读取与匹配准备 =======================
fprintf('正在读取船舶停留时间文件...\n');
stayData = readtable(stayInfoFile);
try
    temp_time = datetime(stayData.hour_start);
    temp_time.TimeZone = 'UTC+8'; 
    stayData.hour_start_utc = datetime(temp_time, 'TimeZone', 'UTC');
catch
    error('时间格式转换失败，请检查CSV。');
end
uniqueHours = unique(stayData.hour_start_utc);
total_hours = numel(uniqueHours);
lidarFiles = [dir(fullfile(lidarDataFolder, '*.csv')); dir(fullfile(lidarDataFolder, '*.xlsx'))];

Global_ERA5_WS = [];
Global_Lidar_WS = [];
Global_Lat = []; 
Global_Time = []; 

current_nc_date = datetime(1900,1,1,'TimeZone','UTC');
current_era5_data = struct();
era5VarNames = {};

%% ======================= 2. 数据处理循环 =======================
fprintf('开始处理风速数据 (加权平均法)...\n');
tic;
for i = 1:total_hours
    if mod(i, 50) == 0
        fprintf('进度: %d / %d (%.1f%%) - 耗时 %.0f 秒\n', i, total_hours, (i/total_hours)*100, toc);
    end
    t_start = uniqueHours(i); 
    t_end = t_start + hours(1);
    
    % --- 读取 Lidar ---
    all_lidar_profiles_list = {};
    for f = 1:length(lidarFiles)
        try
            file_date_str = datestr(datetime(t_start, 'TimeZone', 'UTC+8'), 'yyyymmdd');
            if ~contains(lidarFiles(f).name, file_date_str), continue; end
            
            opts = detectImportOptions(fullfile(lidarDataFolder, lidarFiles(f).name));
            opts.VariableNamingRule = 'preserve';
            T = readtable(fullfile(lidarDataFolder, lidarFiles(f).name), opts);
            
            if ~ismember('Date_time', T.Properties.VariableNames), continue; end
            if isdatetime(T.Date_time), t_col = T.Date_time; else, t_col = datetime(T.Date_time, 'InputFormat', 'yyyyMMdd HH:mm:ss'); end
            t_col.TimeZone = 'UTC+8'; t_col_utc = datetime(t_col, 'TimeZone', 'UTC');
            
            rows = find(t_col_utc >= t_start & t_col_utc < t_end);
            if isempty(rows), continue; end
            
            subT = T(rows, :);
            lidar_h = []; lidar_ws = [];
            vNames = subT.Properties.VariableNames;
            for k = 1:length(vNames)
                tok = regexp(vNames{k}, '^(\d+\.?\d*)m WindSpeed$', 'tokens');
                if ~isempty(tok)
                    h_val = str2double(tok{1}{1});
                    ws_vals = subT.(vNames{k});
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
    
    if isempty(all_lidar_profiles_list), continue; end
    lidar_avg_profile = all_lidar_profiles_list{1}; 
    lidar_avg_profile.Properties.VariableNames = {'Height_m', 'wind_speed'};
    
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
                era5_lon = ncread(ncPath, 'longitude'); era5_lat = ncread(ncPath, 'latitude');
                era5_pressure = ncread(ncPath, 'pressure_level'); 
                if any(era5_lon < 0), era5_lon(era5_lon < 0) = era5_lon(era5_lon < 0) + 360; end
                [era5_lon, lon_sort_idx] = sort(era5_lon);
                current_era5_data = struct();
                for v = 1:length(era5VarNames)
                    vn = era5VarNames{v}; raw = ncread(ncPath, vn);
                    if ndims(raw)==4, raw = raw(lon_sort_idx,:,:,:); else, raw = raw(lon_sort_idx,:,:); end
                    current_era5_data.(vn) = raw;
                end
            catch, current_era5_data = struct(); end
        else
            current_era5_data = struct();
        end
    end
    
    if isempty(fieldnames(current_era5_data)), continue; end
    
    total_stay = sum(hourGridData.stay_hours);
    if total_stay > 0
        num_levels = length(era5_pressure);
        hourly_vals = zeros(num_levels, length(era5VarNames));
        avg_lat = sum(hourGridData.lat_center .* hourGridData.stay_hours) / total_stay; 
        
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
        
        [e_h, sort_i] = sort(era5_tab.Height_m);
        e_ws = era5_tab.wind_speed(sort_i);
        mask = ~isnan(e_h) & ~isnan(e_ws);
        e_h = e_h(mask); e_ws = e_ws(mask);
        
        if length(e_h) > 1
            l_h = lidar_avg_profile.Height_m;
            l_ws = lidar_avg_profile.wind_speed;
            e_ws_interp = interp1(e_h, e_ws, l_h, 'linear', NaN);
            
            valid = ~isnan(l_ws) & ~isnan(e_ws_interp) & l_h >= PLOT_HEIGHT_MIN & l_h <= PLOT_HEIGHT_MAX;
            if any(valid)
                count = sum(valid);
                Global_Lidar_WS = [Global_Lidar_WS; l_ws(valid)];
                Global_ERA5_WS = [Global_ERA5_WS; e_ws_interp(valid)];
                Global_Lat = [Global_Lat; repmat(avg_lat, count, 1)];
                Global_Time = [Global_Time; repmat(t_start, count, 1)];
            end
        end
    end
end
fprintf('\n数据提取完成。\n');

%% ======================= 3. 绘制 2x4 极简图集 =======================
fprintf('\n=== Generating 2x4 Matrix Figure (Continuous Date Colorbars) ===\n');

wind_belts = {
    'N. Trade Winds',    0,   30,  0;  
    'S. Trade Winds',  -30,    0,  0;  
    'Westerlies',       30,   60,  1;  
    'Polar Easterlies', 60,   90,  1   
};
row1_labels = {'(a)', '(b)', '(c)', '(d)'};
row2_labels = {'(e)', '(f)', '(g)', '(h)'};

% 创建超宽屏画布
fig_combined = figure('Units', 'pixels', 'Position', [50, 50, 2000, 950], ...
    'Color', 'w', 'DefaultAxesFontName', font_n, 'DefaultTextFontName', font_n, ...
    'DefaultAxesFontWeight', 'bold', 'DefaultTextFontWeight', 'bold');
t = tiledlayout(2, 4, 'TileSpacing', 'compact', 'Padding', 'compact'); 

fixed_max = 35; % 统一坐标轴上限

% 解析 Agreement Envelope (用于第二行)
x_env = linspace(0, fixed_max, 500);
y_up = (x_env <= 9) .* (x_env + 2) + (x_env > 9) .* (11/9 .* x_env);
y_dn = (x_env <= 11) .* max(0, x_env - 2) + (x_env > 11) .* (9/11 .* x_env);

h_legend = gobjects(4, 1); 

for b = 1:size(wind_belts, 1)
    b_name = wind_belts{b, 1}; 
    b_min = wind_belts{b, 2}; 
    b_max = wind_belts{b, 3}; 
    use_abs = wind_belts{b, 4};
    
    if use_abs == 1
        if b_max == 90, belt_mask = (abs(Global_Lat) >= b_min & abs(Global_Lat) <= b_max);
        else,           belt_mask = (abs(Global_Lat) >= b_min & abs(Global_Lat) < b_max); end
    else
        if b_max == 0,  belt_mask = (Global_Lat > b_min & Global_Lat < b_max);
        else,           belt_mask = (Global_Lat >= b_min & Global_Lat < b_max); end
    end
    
    x_data = Global_ERA5_WS(belt_mask); 
    y_data = Global_Lidar_WS(belt_mask);
    z_time = Global_Time(belt_mask);
    
    % ================== 【第一行】：连续日期散点图 ==================
    ax1 = nexttile(b); hold(ax1, 'on');
    
    if length(x_data) < 10
        text(fixed_max/2, fixed_max/2, '(No Data)', 'HorizontalAlignment', 'center', 'FontName', font_n);
        xlim([0, fixed_max]); ylim([0, fixed_max]); continue;
    end
    
    % 绘制连续日期映射散点。
    time_numeric = datenum(z_time);
    scatter(ax1, x_data, y_data, 10, time_numeric, 'filled', 'MarkerFaceAlpha', 0.6);
    
    % 绘制 1:1 线
    plot(ax1, [0, fixed_max], [0, fixed_max], 'k--', 'LineWidth', 1.2);
    
    % 第一行保留红色的线性拟合线
    p1 = polyfit(x_data, y_data, 1);
    plot(ax1, [0, fixed_max], polyval(p1, [0, fixed_max]), '-', 'Color', [0.8 0.1 0.1], 'LineWidth', 1.8);
    
    R_matrix = corrcoef(x_data, y_data); R_val = R_matrix(1,2);
    RMSE_val = sqrt(mean((x_data - y_data).^2));
    Bias_val = mean(y_data - x_data); 
    N_total = length(x_data);
    
    xlim(ax1, [0, fixed_max]); ylim(ax1, [0, fixed_max]);
    grid(ax1, 'on'); axis(ax1, 'square'); box(ax1, 'on');
    set(ax1, 'FontSize', 14, 'FontName', font_n, 'FontWeight', 'bold', 'LineWidth', 1.2, 'TickDir', 'in');
    
    if b == 1, ylabel(ax1, 'Lidar Wind Speed (m/s)', 'FontSize', 16, 'FontWeight', 'bold'); else, set(ax1, 'YTickLabel', []); end
    set(ax1, 'XTickLabel', []); 
    
    % Panel label inside the upper-right corner of the axes.
    text(ax1, 0.97, 0.97, row1_labels{b}, 'Units', 'normalized', ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
        'FontWeight', 'bold', 'FontSize', 18, 'FontName', font_n, ...
        'BackgroundColor', 'w', 'Margin', 2);
    
    % 每个第一行子图保留各自的连续日期色标，不合并。
    colormap(ax1, jet);
    cb = colorbar(ax1);
    cb.Ticks = linspace(cb.Limits(1), cb.Limits(2), 5);
    tick_day_month = cellstr(datestr(cb.Ticks, 'dd mmm'));
    tick_year = cellstr(datestr(cb.Ticks, 'yyyy'));
    cb.TickLabels = strcat(tick_day_month, {'\newline'}, tick_year);
    cb.TickLabelInterpreter = 'tex';
    cb.FontName = font_n;
    cb.FontSize = 12;
    cb.FontWeight = 'bold';
    cb.Label.String = 'Date';
    cb.Label.FontWeight = 'bold';
    cb.Label.FontName = font_n;
    cb.Label.FontSize = 12;
    
    % 【对角标注 1：左上角统计框】
    stats1 = sprintf('N = %d\nR = %.2f\nRMSE = %.2f m/s\nBias = %.2f m/s\ny = %.2fx %+.2f', N_total, R_val, RMSE_val, Bias_val, p1(1), p1(2));
    text(ax1, fixed_max*0.04, fixed_max*0.96, stats1, 'VerticalAlignment', 'top', 'FontSize', 13, 'FontName', font_n, 'FontWeight', 'bold', 'EdgeColor', 'k', 'BackgroundColor', [1 1 1 0.85], 'Margin', 5); 

    % 【对角标注 2：右下角环流带名称】
    text(ax1, fixed_max*0.96, fixed_max*0.04, b_name, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', 'FontSize', 16, 'FontName', font_n, 'FontWeight', 'bold', 'EdgeColor', 'k', 'BackgroundColor', [1 1 1 0.85], 'Margin', 6);

    % ================== 【第二行】：机制分类包络带图 ==================
    ax2 = nexttile(b + 4); hold(ax2, 'on');
    
    delta_U = abs(y_data - x_data);
    U_mean  = (x_data + y_data) / 2;
    threshold = max(2, 0.2 .* U_mean);
    idx_low  = delta_U > threshold;
    ratio_val = ((N_total - sum(idx_low)) / N_total) * 100;
    
    h_env = fill(ax2, [x_env, fliplr(x_env)], [y_up, fliplr(y_dn)], [0.85, 0.92, 0.95], 'EdgeColor', 'none', 'FaceAlpha', 0.25);
    h_all = scatter(ax2, x_data, y_data, 10, [0.65, 0.65, 0.65], 'filled', 'MarkerFaceAlpha', 0.15); 
    h_low = scatter(ax2, x_data(idx_low), y_data(idx_low), 10, [0.90, 0.35, 0.25], 'filled', 'MarkerFaceAlpha', 0.15); 
    h_11  = plot(ax2, [0, fixed_max], [0, fixed_max], 'k--', 'LineWidth', 1.5);
    
    if b == 1, h_legend(1) = h_env; h_legend(2) = h_all; h_legend(3) = h_low; h_legend(4) = h_11; end
    
    xlim(ax2, [0, fixed_max]); ylim(ax2, [0, fixed_max]);
    grid(ax2, 'on'); axis(ax2, 'square'); box(ax2, 'on');
    set(ax2, 'FontSize', 14, 'FontName', font_n, 'FontWeight', 'bold', 'LineWidth', 1.2, 'TickDir', 'in');
    
    if b == 1, ylabel(ax2, 'Lidar Wind Speed (m/s)', 'FontSize', 16, 'FontWeight', 'bold'); else, set(ax2, 'YTickLabel', []); end
    xlabel(ax2, 'ERA5 Wind Speed (m/s)', 'FontSize', 16, 'FontWeight', 'bold');
    
    % Panel label inside the upper-right corner of the axes.
    text(ax2, 0.97, 0.97, row2_labels{b}, 'Units', 'normalized', ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
        'FontWeight', 'bold', 'FontSize', 18, 'FontName', font_n, ...
        'BackgroundColor', 'w', 'Margin', 2);
    
    stats2 = sprintf('Agreement Ratio = %.1f%%', ratio_val);
    text(ax2, fixed_max*0.04, fixed_max*0.96, stats2, 'VerticalAlignment', 'top', 'FontSize', 14, 'FontName', font_n, 'FontWeight', 'bold', 'EdgeColor', 'k', 'BackgroundColor', [1 1 1 0.85], 'Margin', 6);
    text(ax2, fixed_max*0.96, fixed_max*0.04, b_name, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', 'FontSize', 16, 'FontName', font_n, 'FontWeight', 'bold', 'EdgeColor', 'k', 'BackgroundColor', [1 1 1 0.85], 'Margin', 6);
end

% 为第二行添加全局统一图例
lgd = legend(h_legend, {'Agreement envelope', 'All samples', 'Low-agreement samples', '1:1 line'}, 'Location', 'southoutside');
lgd.Layout.Tile = 'south'; 
lgd.Orientation = 'horizontal';
lgd.FontSize = 16;
lgd.FontName = font_n;
lgd.FontWeight = 'bold';
lgd.Box = 'off';

outputFilename = fullfile(outputGlobalFolder, 'Unified_2x4_Ultimate_Matrix.png');
exportgraphics(fig_combined, outputFilename, 'Resolution', 300);
fprintf('完美 2x4 离散日期标注大图生成完毕！图像已保存至: %s\n', outputFilename);
