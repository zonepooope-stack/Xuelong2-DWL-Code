% =========================================================================
%  Script: ERA5 vs Lidar - 2x4 Unified Matrix Analysis (No Data Exclusion)
%  功能：
%     1. 全量数据处理：不使用任何人为过滤条件，保留原汁原味的环流带数据。
%     2. 视觉极致优化：
%        - 无红色拟合线，保持画面绝对纯净
%        - 标题极简化，仅保留 (a)-(h)
%        - 第一行标 N 等统计值，第二行仅标 Agreement Ratio
%        - 极低透明度(0.15)叠加，解决密集区糊图问题
%========================================================================
clc; clear; close all;

%% ======================= 0. 参数设置 =======================
PLOT_HEIGHT_MIN = 0; 
PLOT_HEIGHT_MAX = 3000; % 仅保留物理界限 0-3000m 
MAX_VALID_WS = 100;     % 剔除仪器异常值

% --- Portable repository paths ---
scriptFolder = fileparts(mfilename('fullpath'));
addpath(scriptFolder);
cfg = project_config();
era5DataFolder = cfg.era5DataFolder;
stayInfoFile = cfg.stayInfoFile;
lidarDataFolder = cfg.lidarDataFolder;
outputFolder = fullfile(cfg.outputRoot, 'fig07');
outputGlobalFolder = outputFolder;

if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end
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

Global_ERA5_WS  = [];
Global_Lidar_WS = [];
Global_Lat      = []; 

current_nc_date = datetime(1900,1,1,'TimeZone','UTC');
current_era5_data = struct();
era5VarNames = {};
cached_lidar_date = '';
cached_lidar_table = table();
cached_lidar_time_utc = datetime.empty(0, 1);

%% ======================= 2. 数据处理循环 (全量保留) =======================
fprintf('开始处理风速数据 (加权平均法)...\n');
tic;
for i = 1:total_hours
    if mod(i, 50) == 0
        fprintf('进度: %d / %d (%.1f%%) - 耗时 %.0f 秒\n', i, total_hours, (i/total_hours)*100, toc);
    end
    t_start = uniqueHours(i); 
    t_end = t_start + hours(1);
    
    % --- 读取 Lidar ---
    file_date_str = datestr(datetime(t_start, 'TimeZone', 'UTC+8'), 'yyyymmdd');
    current_lidar_file = [];
    for f = 1:length(lidarFiles)
        if contains(lidarFiles(f).name, file_date_str)
            current_lidar_file = lidarFiles(f);
            break;
        end
    end
    if isempty(current_lidar_file), continue; end

    try
        % Read each daily lidar file only once; the matching calculation is
        % unchanged, but repeated disk I/O is avoided.
        if ~strcmp(cached_lidar_date, file_date_str)
            opts = detectImportOptions(fullfile(lidarDataFolder, current_lidar_file.name));
            opts.VariableNamingRule = 'preserve';
            cached_lidar_table = readtable( ...
                fullfile(lidarDataFolder, current_lidar_file.name), opts);
            if ~ismember('Date_time', cached_lidar_table.Properties.VariableNames)
                cached_lidar_table = table();
                cached_lidar_time_utc = datetime.empty(0, 1);
                cached_lidar_date = file_date_str;
                continue;
            end
            t_col = cached_lidar_table.Date_time;
            if ~isdatetime(t_col)
                t_col = datetime(t_col, 'InputFormat', 'yyyyMMdd HH:mm:ss');
            end
            if isempty(t_col.TimeZone), t_col.TimeZone = 'UTC+8'; end
            cached_lidar_time_utc = datetime(t_col, 'TimeZone', 'UTC');
            cached_lidar_date = file_date_str;
        end
        if isempty(cached_lidar_table), continue; end

        rows = find(cached_lidar_time_utc >= t_start & ...
                    cached_lidar_time_utc < t_end);
        if isempty(rows), continue; end
        subT = cached_lidar_table(rows, :);

        lidar_h = [];
        lidar_ws = [];
        vNames = subT.Properties.VariableNames;
        for k = 1:length(vNames)
            tok = regexp(vNames{k}, '^(\d+\.?\d*)m WindSpeed$', 'tokens');
            if ~isempty(tok)
                h_val = str2double(tok{1}{1});
                ws_vals = subT.(vNames{k});
                if iscell(ws_vals), ws_vals = str2double(ws_vals); end
                ws_vals(ws_vals >= MAX_VALID_WS | ws_vals < 0) = NaN;
                ws_avg = mean(ws_vals, 'omitnan');
                if ~isnan(ws_avg)
                    lidar_h = [lidar_h; h_val];
                    lidar_ws = [lidar_ws; ws_avg];
                end
            end
        end
        if isempty(lidar_h), continue; end
        lidar_avg_profile = table(lidar_h, lidar_ws, ...
            'VariableNames', {'Height_m', 'wind_speed'});
    catch
        continue;
    end
    
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
                Global_ERA5_WS  = [Global_ERA5_WS; e_ws_interp(valid)];
                Global_Lat      = [Global_Lat; repmat(avg_lat, count, 1)];
            end
        end
    end
end
if isempty(Global_ERA5_WS), error('未匹配到有效数据，请检查路径。'); end
fprintf('\n数据提取完成，准备绘制单轴极简机制图...\n');

%% ======================= 3. 绘制单轴极简依赖性机制图 =======================
% Retain the duplicated legacy block only for traceability; skip it so the
% matching calculation and final figure are each produced once.
if false
fprintf('=== Skipped legacy duplicate block ===\n');

wind_belts = {
    '(a) N. Trade Winds (0°~30°N)',    0,   30,  0;  
    '(b) S. Trade Winds (30°S~0°)',  -30,    0,  0;  
    '(c) Westerlies (30°~60°)',       30,   60,  1;  
    '(d) Polar Easterlies (60°~90°)', 60,   90,  1   
};

% 核心配色保持经典学术感
c_scatter = [0.80, 0.80, 0.80]; 
c_shadow  = [0.75, 0.88, 0.95]; 
c_line    = [0.00, 0.35, 0.75]; 

fig = figure('Color', 'w', 'Position', [100, 100, 1500, 850]);
t = tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'loose');
plot_handles = []; 

for b = 1:size(wind_belts, 1)
    b_name  = wind_belts{b, 1};
    b_min   = wind_belts{b, 2};
    b_max   = wind_belts{b, 3};
    use_abs = wind_belts{b, 4};
    
    if use_abs == 1
        if b_max == 90, belt_mask = (abs(Global_Lat) >= b_min & abs(Global_Lat) <= b_max);
        else,           belt_mask = (abs(Global_Lat) >= b_min & abs(Global_Lat) < b_max); end
    else
        if b_max == 0,  belt_mask = (Global_Lat > b_min & Global_Lat < b_max);
        else,           belt_mask = (Global_Lat >= b_min & Global_Lat < b_max); end
    end
    
    b_era5  = Global_ERA5_WS(belt_mask);
    b_lidar = Global_Lidar_WS(belt_mask);
    ws_diff = b_lidar - b_era5; % Bias (Lidar - ERA5)
    
    ax = nexttile(b); hold(ax, 'on');
    
    N_total = length(b_era5);
    if N_total < 30
        text(ax, 10, 0, 'No Sufficient Data', 'FontSize', 14, 'HorizontalAlignment', 'center');
        title(ax, b_name, 'FontSize', 16, 'FontWeight', 'bold', 'FontName', font_n);
        continue;
    end
    
    overall_bias = mean(ws_diff);
    
    % 1. 原始散点图 (Raw Data)
    h_sc = scatter(ax, b_era5, ws_diff, 8, c_scatter, 'filled', 'MarkerFaceAlpha', 0.25, 'MarkerEdgeColor', 'none', 'DisplayName', 'Raw Data');
    
    % 2. 等样本分箱 (Equal-sample binning)
    BIN_SIZE = 200; 
    [sorted_ws, order] = sort(b_era5);
    sorted_diff = ws_diff(order);
    numBins = ceil(length(sorted_ws) / BIN_SIZE);
    
    bin_x = nan(numBins,1); bin_mean = nan(numBins,1); bin_sem = nan(numBins,1);
    for k = 1:numBins
        id = ((k-1)*BIN_SIZE + 1) : min(k*BIN_SIZE, length(sorted_ws));
        bin_x(k) = mean(sorted_ws(id));
        bin_mean(k) = mean(sorted_diff(id));
        bin_sem(k) = std(sorted_diff(id)) / sqrt(length(id)); % 标准误
    end
    
    % 清洗空值防止绘图报错
    valid_bins = ~isnan(bin_mean);
    bc = bin_x(valid_bins); bm = bin_mean(valid_bins); bci = 1.96 * bin_sem(valid_bins);
    if length(unique(bc)) < length(bc), bc = bc + (1:length(bc))' * 1e-6; end
    
    % 3. 95% 置信区间阴影
    x_conf = [bc', fliplr(bc')]; 
    y_conf = [(bm + bci)', fliplr((bm - bci)')];
    h_sh = fill(ax, x_conf, y_conf, c_shadow, 'FaceAlpha', 0.6, 'EdgeColor', 'none', 'DisplayName', '95% CI');
    
    % 4. 均值线 (Mean Bias)
    h_line = plot(ax, bc, bm, '-', 'Color', c_line, 'LineWidth', 2.5, 'DisplayName', 'Mean Bias');
    
    % 5. 基准线 (Zero-bias line)
    yline(ax, 0, 'k--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
    
    % ================= 格式化与美化 =================
    ylim(ax, [-12, 16]);
    xlim(ax, [0, max([b_era5; 15])*1.05]); 
    xlabel(ax, '');
    ylabel(ax, '');
    set(ax, 'FontSize', 18, 'FontWeight', 'bold', ...
        'LineWidth', 1.5, 'Box', 'on', 'TickDir', 'in', ...
        'FontName', font_n);
    grid(ax, 'on'); ax.GridAlpha = 0.4;
    
    % ================= 右上角统计标签 =================
    text(ax, 0.015, 0.975, sub_labels{b}, 'Units', 'normalized', ...
        'VerticalAlignment', 'top', 'HorizontalAlignment', 'left', ...
        'FontSize', 18, 'FontName', font_n, 'FontWeight', 'bold', ...
        'Color', 'k');

    belt_label = regexprep(b_name, '^\([a-d]\)\s*', '');
    statsStr = sprintf('%s\nN = %d\nBias = %.2f m/s', ...
        belt_label, N_total, overall_bias);
    text(ax, 0.97, 0.96, statsStr, 'Units', 'normalized', ...
        'VerticalAlignment', 'top', 'HorizontalAlignment', 'right', ...
        'FontSize', 14, 'FontName', font_n, 'FontWeight', 'bold', ...
        'EdgeColor', 'none', 'BackgroundColor', [1 1 1 0.70], ...
        'Margin', 3);
        
    % 收集图例句柄 (仅第一张图)
    if b == 1, plot_handles = [h_sc, h_sh, h_line]; end
end
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

Global_ERA5_WS  = [];
Global_Lidar_WS = [];
Global_Lat      = []; 

current_nc_date = datetime(1900,1,1,'TimeZone','UTC');
current_era5_data = struct();
era5VarNames = {};

%% ======================= 2. 数据处理循环 (全量保留) =======================
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
                Global_ERA5_WS  = [Global_ERA5_WS; e_ws_interp(valid)];
                Global_Lat      = [Global_Lat; repmat(avg_lat, count, 1)];
            end
        end
    end
end
if isempty(Global_ERA5_WS), error('未匹配到有效数据，请检查路径。'); end
fprintf('\n数据提取完成，准备绘制单轴极简机制图...\n');

%% ======================= 3. 绘制单轴极简依赖性机制图 =======================
end
fprintf('=== Generating Single-Axis Bias Dependence Figure ===\n');
sub_labels = {'(a)', '(b)', '(c)', '(d)'};

wind_belts = {
    '(a) N. Trade Winds (0°~30°N)',    0,   30,  0;  
    '(b) S. Trade Winds (30°S~0°)',  -30,    0,  0;  
    '(c) Westerlies (30°~60°)',       30,   60,  1;  
    '(d) Polar Easterlies (60°~90°)', 60,   90,  1   
};

% 核心配色保持经典学术感
c_scatter = [0.80, 0.80, 0.80]; 
c_shadow  = [0.75, 0.88, 0.95]; 
c_line    = [0.00, 0.35, 0.75]; 

fig = figure('Color', 'w', 'Position', [100, 100, 1500, 850]);
t = tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'loose');
plot_handles = []; 

for b = 1:size(wind_belts, 1)
    b_name  = wind_belts{b, 1};
    b_min   = wind_belts{b, 2};
    b_max   = wind_belts{b, 3};
    use_abs = wind_belts{b, 4};
    
    if use_abs == 1
        if b_max == 90, belt_mask = (abs(Global_Lat) >= b_min & abs(Global_Lat) <= b_max);
        else,           belt_mask = (abs(Global_Lat) >= b_min & abs(Global_Lat) < b_max); end
    else
        if b_max == 0,  belt_mask = (Global_Lat > b_min & Global_Lat < b_max);
        else,           belt_mask = (Global_Lat >= b_min & Global_Lat < b_max); end
    end
    
    b_era5  = Global_ERA5_WS(belt_mask);
    b_lidar = Global_Lidar_WS(belt_mask);
    ws_diff = b_lidar - b_era5; % Bias (Lidar - ERA5)
    
    ax = nexttile(b); hold(ax, 'on');
    
    N_total = length(b_era5);
    if N_total < 30
        text(ax, 10, 0, 'No Sufficient Data', 'FontSize', 14, 'HorizontalAlignment', 'center');
        title(ax, b_name, 'FontSize', 16, 'FontWeight', 'bold', 'FontName', font_n);
        continue;
    end
    
    overall_bias = mean(ws_diff);
    
    % 1. 原始散点图 (Raw Data)
    h_sc = scatter(ax, b_era5, ws_diff, 8, c_scatter, 'filled', 'MarkerFaceAlpha', 0.25, 'MarkerEdgeColor', 'none', 'DisplayName', 'Raw Data');
    
    % 2. 等样本分箱 (Equal-sample binning)
    BIN_SIZE = 200; 
    [sorted_ws, order] = sort(b_era5);
    sorted_diff = ws_diff(order);
    numBins = ceil(length(sorted_ws) / BIN_SIZE);
    
    bin_x = nan(numBins,1); bin_mean = nan(numBins,1); bin_sem = nan(numBins,1);
    for k = 1:numBins
        id = ((k-1)*BIN_SIZE + 1) : min(k*BIN_SIZE, length(sorted_ws));
        bin_x(k) = mean(sorted_ws(id));
        bin_mean(k) = mean(sorted_diff(id));
        bin_sem(k) = std(sorted_diff(id)) / sqrt(length(id)); % 标准误
    end
    
    % 清洗空值防止绘图报错
    valid_bins = ~isnan(bin_mean);
    bc = bin_x(valid_bins); bm = bin_mean(valid_bins); bci = 1.96 * bin_sem(valid_bins);
    if length(unique(bc)) < length(bc), bc = bc + (1:length(bc))' * 1e-6; end
    
    % 3. 95% 置信区间阴影
    x_conf = [bc', fliplr(bc')]; 
    y_conf = [(bm + bci)', fliplr((bm - bci)')];
    h_sh = fill(ax, x_conf, y_conf, c_shadow, 'FaceAlpha', 0.6, 'EdgeColor', 'none', 'DisplayName', '95% CI');
    
    % 4. 均值线 (Mean Bias)
    h_line = plot(ax, bc, bm, '-', 'Color', c_line, 'LineWidth', 2.5, 'DisplayName', 'Mean Bias');
    
    % 5. 基准线 (Zero-bias line)
    yline(ax, 0, 'k--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
    
    % ================= 格式化与美化 =================
    ylim(ax, [-12, 16]);
    xlim(ax, [0, max([b_era5; 15])*1.05]); 
    xlabel(ax, '');
    ylabel(ax, '');
    set(ax, 'FontSize', 18, 'FontWeight', 'bold', ...
        'LineWidth', 1.5, 'Box', 'on', 'TickDir', 'in', ...
        'FontName', font_n);
    grid(ax, 'on'); ax.GridAlpha = 0.4;
    
    % ================= 右上角统计标签 =================
    text(ax, 0.015, 0.975, sub_labels{b}, 'Units', 'normalized', ...
        'VerticalAlignment', 'top', 'HorizontalAlignment', 'left', ...
        'FontSize', 18, 'FontName', font_n, 'FontWeight', 'bold', ...
        'Color', 'k');

    belt_label = regexprep(b_name, '^\([a-d]\)\s*', '');
    statsStr = sprintf('%s\nN = %d\nBias = %.2f m/s', ...
        belt_label, N_total, overall_bias);
    text(ax, 0.97, 0.96, statsStr, 'Units', 'normalized', ...
        'VerticalAlignment', 'top', 'HorizontalAlignment', 'right', ...
        'FontSize', 14, 'FontName', font_n, 'FontWeight', 'bold', ...
        'EdgeColor', 'none', 'BackgroundColor', [1 1 1 0.70], ...
        'Margin', 3);
        
    % 收集图例句柄 (仅第一张图)
    if b == 1, plot_handles = [h_sc, h_sh, h_line]; end
end

% ---------------- 顶部全局图例 (去除大标题) ----------------
xlabel(t, 'ERA5 Wind Speed (m/s)', ...
    'FontSize', 18, 'FontWeight', 'bold', 'FontName', font_n);
common_label_ax = axes(fig, ...
    'Position', [0, 0, 1, 1], ...
    'Visible', 'off', ...
    'HitTest', 'off');
text(common_label_ax, 0.02, 0.50, 'Wind Speed Diff. (m/s)', ...
    'Units', 'normalized', ...
    'Rotation', 90, ...
    'FontSize', 18, ...
    'FontWeight', 'bold', ...
    'FontName', font_n, ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'Color', 'k');
lgd = legend(plot_handles, 'Orientation', 'horizontal', ...
    'FontSize', 18, 'FontWeight', 'bold', 'FontName', font_n);
lgd.Layout.Tile = 'north'; 
lgd.Box = 'off';

% 保存图片
savePath = fullfile(outputGlobalFolder, 'Bias_Dependence_Clean_SingleAxis.png');
exportgraphics(fig, savePath, 'Resolution', 300);
fprintf('\n极简排版完成！图像已保存至:\n%s\n', savePath);
% ---------------- 顶部全局图例 (去除大标题) ----------------
% Common axis labels and the shared legend were configured above.
lgd.Layout.Tile = 'north'; 
lgd.Box = 'off';

% 保存图片
savePath = fullfile(outputGlobalFolder, 'Bias_Dependence_Clean_SingleAxis.png');
exportgraphics(fig, savePath, 'Resolution', 300);
fprintf('\n极简排版完成！图像已保存至:\n%s\n', savePath); 
