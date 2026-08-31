% =========================================================================
%  Script: ERA5 vs Lidar - Distance Effect & PDF in 2x4 Layout
%  功能：按纬度划分 4 个风带(分离南北信风带)，2x4 面板展示距离效应与误差分布
%  新增功能：在每个子面板的右上角明确标注 Mean Bias 的具体数值
% =========================================================================
clc; clear; close all;

%% ======================= MODULE 0: 参数与路径配置 =======================
PLOT_HEIGHT_MIN = 103.9;  % Lowest measured lidar gate; report as 104 m
PLOT_HEIGHT_MAX = 3000; 
MAX_VALID_WS = 100;     
g = 9.81;

scriptFolder = fileparts(mfilename('fullpath'));
addpath(scriptFolder);
cfg = project_config();
era5DataFolder  = cfg.era5DataFolder;
stayInfoFile    = cfg.stayInfoFile;
lidarDataFolder = cfg.lidarDataFolder;
outputRoot      = fullfile(cfg.outputRoot, 'fig08');
if ~exist(outputRoot, 'dir'), mkdir(outputRoot); end

%% ======================= MODULE 1: 数据读取与匹配 =======================
fprintf('Step 1/3: 读取数据并进行时空匹配...\n');
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

Global_ERA5 = [];  Global_Lidar = [];
Global_Lat  = [];  Global_Lon = [];       

current_nc_date = datetime(1900,1,1,'TimeZone','UTC');
current_era5_data = struct();
era5VarNames = {};
cached_lidar_date = '';
cached_lidar_table = table();
cached_lidar_time_utc = datetime.empty(0, 1);

tic;
for i = 1:total_hours
    if mod(i, 100) == 0, fprintf('     进度: %d / %d (%.1f%%) - 耗时 %.0fs\n', i, total_hours, (i/total_hours)*100, toc); end
    t_start = uniqueHours(i); t_end = t_start + hours(1);
    
    file_date_str = datestr(datetime(t_start, 'TimeZone', 'UTC+8'), 'yyyymmdd');
    found_file = false; current_lidar_file = [];
    for f = 1:length(lidarFiles)
        if contains(lidarFiles(f).name, file_date_str)
            current_lidar_file = lidarFiles(f); found_file = true; break; 
        end
    end
    if ~found_file, continue; end
    
    try
        % Cache the daily lidar table so it is read only once per day.
        if ~strcmp(cached_lidar_date, file_date_str)
            opts = detectImportOptions(fullfile(lidarDataFolder, current_lidar_file.name));
            opts.VariableNamingRule = 'preserve';
            cached_lidar_table = readtable( ...
                fullfile(lidarDataFolder, current_lidar_file.name), opts);

            if ismember('Date_time', cached_lidar_table.Properties.VariableNames)
                t_col_raw = cached_lidar_table.Date_time;
            elseif ismember('Time', cached_lidar_table.Properties.VariableNames)
                t_col_raw = cached_lidar_table.Time;
            else
                cached_lidar_table = table();
                cached_lidar_time_utc = datetime.empty(0, 1);
                cached_lidar_date = file_date_str;
                continue;
            end

            if isdatetime(t_col_raw)
                t_col = t_col_raw;
            else
                t_col = datetime(t_col_raw, ...
                    'InputFormat', 'yyyyMMdd HH:mm:ss');
            end
            if isempty(t_col.TimeZone), t_col.TimeZone = 'UTC+8'; end
            cached_lidar_time_utc = datetime(t_col, 'TimeZone', 'UTC');
            cached_lidar_date = file_date_str;
        end

        if isempty(cached_lidar_table), continue; end
        T = cached_lidar_table;
        rows = find(cached_lidar_time_utc >= t_start & ...
                    cached_lidar_time_utc < t_end);
        if isempty(rows), continue; end
        subT = T(rows, :);
        
        lidar_h_vec = []; lidar_ws_vec = [];
        vNames = subT.Properties.VariableNames;
        for k = 1:length(vNames)
            h_val = parse_lidar_height(vNames{k});
            if isfinite(h_val)
                ws_vals = subT.(vNames{k});
                if iscell(ws_vals), ws_vals = str2double(ws_vals); end
                ws_vals(ws_vals >= MAX_VALID_WS | ws_vals < 0) = NaN; 
                ws_avg = mean(ws_vals, 'omitnan'); 
                if ~isnan(ws_avg), lidar_h_vec = [lidar_h_vec; h_val]; lidar_ws_vec = [lidar_ws_vec; ws_avg]; end
            end
        end
        if isempty(lidar_h_vec), continue; end
    catch, continue; end
    
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
        hourly_vals = zeros(length(ncread(ncPath, 'pressure_level')), length(era5VarNames));
        avg_lat = sum(hourGridData.lat_center .* hourGridData.stay_hours) / total_stay;
        avg_lon = sum(hourGridData.lon_center .* hourGridData.stay_hours) / total_stay;
        
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
            e_ws_interp = interp1(e_h, e_ws, lidar_h_vec, 'linear', NaN);
            valid = ~isnan(lidar_ws_vec) & ~isnan(e_ws_interp) & lidar_h_vec >= PLOT_HEIGHT_MIN & lidar_h_vec <= PLOT_HEIGHT_MAX;
            if any(valid)
                count = sum(valid);
                Global_Lidar = [Global_Lidar; lidar_ws_vec(valid)];
                Global_ERA5  = [Global_ERA5; e_ws_interp(valid)];
                Global_Lat   = [Global_Lat; repmat(avg_lat, count, 1)];
                Global_Lon   = [Global_Lon; repmat(avg_lon, count, 1)];
            end
        end
    end
end
if isempty(Global_Lidar), error('未匹配到任何有效数据！'); end

%% ======================= MODULE 2: 计算离岸距离 =======================
fprintf('Step 2/3: 计算全球离岸距离...\n');
% Distance depends only on position. Compute each unique ship position once,
% then map it back to all height-level samples without changing the result.
[unique_positions, ~, position_index] = unique( ...
    [Global_Lat, Global_Lon], 'rows', 'stable');
unique_distance = calc_distance_to_coast( ...
    unique_positions(:, 1), unique_positions(:, 2));
Global_Dist = unique_distance(position_index);

%% ======================= MODULE 3: 绘制 2x4 矩阵大图 =======================
fprintf('Step 3/3: 开始绘制 2x4 组合矩阵图...\n');

% 定义 4 个风带：分离南北信风带，保留西风带和极地带的绝对纬度合并
% 格式: {名字, lat_min, lat_max, 是否使用绝对纬度(1=是, 0=否)}
wind_belts = {
    'N. Trade Winds (0°~30°N)',    0,   30,  0;  
    'S. Trade Winds (30°S~0°)',  -30,    0,  0;  
    'Westerlies (30°~60°)',       30,   60,  1;  
    'Polar Easterlies (60°~90°)', 60,   90,  1   
};

% 距离图配色 (蓝系)
c_scatter = [0.70, 0.73, 0.75]; 
c_line    = [0.00, 0.30, 0.65]; 
c_shadow  = [0.75, 0.88, 0.95]; 
% PDF图配色 (暖橙红系)
c_pdf_fill = [0.85, 0.40, 0.20]; 
c_pdf_line = [0.75, 0.20, 0.10]; 

% 将图幅适当拉长以适应 4 列
fig = figure('Visible', 'on', 'Color', 'w', 'Position', [50, 50, 2000, 900]);
set(fig, ...
    'DefaultAxesFontName', 'Arial', ...
    'DefaultTextFontName', 'Arial', ...
    'DefaultAxesFontSize', 18, ...
    'DefaultTextFontSize', 18, ...
    'DefaultAxesFontWeight', 'bold', ...
    'DefaultTextFontWeight', 'bold');
t = tiledlayout(2, 4, 'TileSpacing', 'compact', 'Padding', 'compact');

plot_handles = []; 
pdf_handles  = []; 
sub_labels = {'(a)', '(b)', '(c)', '(d)', '(e)', '(f)', '(g)', '(h)'};

for b = 1:size(wind_belts, 1)
    b_name  = wind_belts{b, 1};
    b_min   = wind_belts{b, 2};
    b_max   = wind_belts{b, 3};
    use_abs = wind_belts{b, 4};
    
    % 动态数据筛选逻辑
    if use_abs == 1
        % 使用绝对纬度 (合并南北半球)
        if b_max == 90
            belt_mask = (abs(Global_Lat) >= b_min & abs(Global_Lat) <= b_max);
        else
            belt_mask = (abs(Global_Lat) >= b_min & abs(Global_Lat) < b_max);
        end
    else
        % 不使用绝对纬度 (严格区分南北半球)
        if b_max == 0
            % 南半球 (-30 到 0)
            belt_mask = (Global_Lat > b_min & Global_Lat < b_max);
        else
            % 北半球 (0 到 30)
            belt_mask = (Global_Lat >= b_min & Global_Lat < b_max);
        end
    end
    
    b_lidar = Global_Lidar(belt_mask);
    b_era5  = Global_ERA5(belt_mask);
    b_dist  = Global_Dist(belt_mask);
    ws_diff = b_lidar - b_era5;
    
    valid = ~isnan(ws_diff) & ~isnan(b_dist);
    ws_diff = ws_diff(valid); b_dist = b_dist(valid);
    n_pts = length(ws_diff);
    
    % >>> 计算该风带的总体 Mean Bias <<<
    mean_bias = mean(ws_diff); 

    % =========================================================
    % 【第一行：绘制离岸距离效应图】 -> 定位到 1, 2, 3, 4 号面板
    % =========================================================
    ax1 = nexttile(b); hold(ax1, 'on');
    
    if n_pts < 30
        text(ax1, 0.5, 0.5, 'No Sufficient Data', ...
            'FontSize', 18, 'FontWeight', 'bold', ...
            'FontName', 'Arial', 'HorizontalAlignment', 'center');
    else
        h_sc = scatter(ax1, b_dist, ws_diff, 8, c_scatter, 'filled', 'MarkerFaceAlpha', 0.20, 'MarkerEdgeColor', 'none', 'DisplayName', 'Raw Data');
        
        % Original equal-distance binning: one bin every 40 km.
        bin_step = 40;
        bin_edges = 0:bin_step:max(b_dist);
        if length(bin_edges) < 3, bin_edges = 0:bin_step:500; end
        bin_centers = (bin_edges(1:end-1) + bin_edges(2:end)) / 2;

        bin_mean = nan(size(bin_centers));
        bin_std = nan(size(bin_centers));
        for idx = 1:length(bin_centers)
            mask = b_dist >= bin_edges(idx) & b_dist < bin_edges(idx+1);
            if sum(mask) >= 5
                bin_mean(idx) = mean(ws_diff(mask));
                bin_std(idx) = std(ws_diff(mask));
            end
        end
        valid_bins = ~isnan(bin_mean);
        bc = bin_centers(valid_bins);
        bm = bin_mean(valid_bins);
        bs = bin_std(valid_bins);
        
        if ~isempty(bc)
            x_conf = [bc, fliplr(bc)]; y_conf = [bm + bs, fliplr(bm - bs)];
            h_sh = fill(ax1, x_conf, y_conf, c_shadow, 'FaceAlpha', 0.5, 'EdgeColor', 'none', 'DisplayName', 'Mean \pm 1 STD');
            h_line = plot(ax1, bc, bm, '-', 'Color', c_line, 'LineWidth', 3, 'DisplayName', 'Mean Bias');
            if b == 1, plot_handles = [h_sc, h_sh, h_line]; end
        end
        
        yline(ax1, 0, 'k--', 'LineWidth', 1.5, 'HandleVisibility', 'off');
        
        xlim(ax1, [0, max([b_dist; 100])*1.02]); 
        ylim(ax1, [-12, 16]);
    end

    % Keep the panel label separate at the upper-left corner.
    text(ax1, 0.015, 0.975, sub_labels{b}, ...
        'Units', 'normalized', ...
        'FontSize', 18, ...
        'FontWeight', 'bold', ...
        'FontName', 'Arial', ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'top', ...
        'Color', 'k');

    % Upper row: retain only the belt description and N.
    stats_text1 = sprintf('%s\nN = %d', b_name, n_pts);
    text(ax1, 0.97, 0.96, stats_text1, ...
        'Units', 'normalized', ...
        'FontSize', 14, ...
        'FontWeight', 'bold', ...
        'FontName', 'Arial', ...
        'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'top', ...
        'BackgroundColor', [1, 1, 1, 0.70], ...
        'EdgeColor', 'none', ...
        'Margin', 3);

    xlabel(ax1, 'Distance to Shore (km)', ...
        'FontSize', 18, 'FontWeight', 'bold', 'FontName', 'Arial');
    if b == 1
        ylabel(ax1, 'WS Diff. (m/s)', ...
            'FontSize', 18, 'FontWeight', 'bold', 'FontName', 'Arial');
    else
        ylabel(ax1, '');
        ax1.YTickLabel = [];
    end
    set(ax1, ...
        'FontSize', 18, ...
        'FontWeight', 'bold', ...
        'LineWidth', 1.5, ...
        'Box', 'on', ...
        'TickDir', 'in', ...
        'FontName', 'Arial');
    grid(ax1, 'on');
    ax1.GridAlpha = 0.3;
    
    % =========================================================
    % 【第二行：绘制误差分布 PDF 图】 -> 定位到 5, 6, 7, 8 号面板
    % =========================================================
    ax2 = nexttile(b + 4); hold(ax2, 'on');
    
    if n_pts >= 30
        [pdf_y, pdf_x] = ksdensity(ws_diff);
        h_pdf = fill(ax2, pdf_x, pdf_y, c_pdf_fill, 'FaceAlpha', 0.4, 'EdgeColor', c_pdf_line, 'LineWidth', 2, 'DisplayName', 'Error PDF');
        
        h_mu = xline(ax2, mean_bias, '--', 'Color', c_pdf_line, 'LineWidth', 2.5, 'DisplayName', 'Mean Bias');
        xline(ax2, 0, 'k:', 'LineWidth', 1.5, 'HandleVisibility', 'off');
        
        if b == 1, pdf_handles = [h_pdf, h_mu]; end
        
        xlim(ax2, [-12, 16]); 
        ylim(ax2, [0, 0.25]);
    else
        xlim(ax2, [-12, 16]);
        ylim(ax2, [0, 0.25]);
    end

    % Keep the panel label separate at the upper-left corner.
    text(ax2, 0.015, 0.975, sub_labels{b+4}, ...
        'Units', 'normalized', ...
        'FontSize', 18, ...
        'FontWeight', 'bold', ...
        'FontName', 'Arial', ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'top', ...
        'Color', 'k');

    % Lower row: report Bias here and omit the repeated panel description.
    stats_text2 = sprintf('Bias = %.2f m/s', mean_bias);
    text(ax2, 0.97, 0.96, stats_text2, ...
        'Units', 'normalized', ...
        'FontSize', 14, ...
        'FontWeight', 'bold', ...
        'FontName', 'Arial', ...
        'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'top', ...
        'BackgroundColor', [1, 1, 1, 0.70], ...
        'EdgeColor', 'none', ...
        'Margin', 3);

    xlabel(ax2, 'Wind Speed Diff. (m/s)', ...
        'FontSize', 18, 'FontWeight', 'bold', 'FontName', 'Arial');
    if b == 1
        ylabel(ax2, 'Probability Density', ...
            'FontSize', 18, 'FontWeight', 'bold', 'FontName', 'Arial');
    else
        ylabel(ax2, '');
        ax2.YTickLabel = [];
    end
    set(ax2, ...
        'FontSize', 18, ...
        'FontWeight', 'bold', ...
        'LineWidth', 1.5, ...
        'Box', 'on', ...
        'TickDir', 'in', ...
        'FontName', 'Arial');
    grid(ax2, 'on');
    ax2.GridAlpha = 0.3;
end

% 配置统一图例 (放在顶部)
lgd = legend([plot_handles, pdf_handles], ...
    'Orientation', 'horizontal', ...
    'FontSize', 18, ...
    'FontWeight', 'bold', ...
    'FontName', 'Arial');
lgd.Layout.Tile = 'north'; 
lgd.Box = 'off';

drawnow;
save_path = fullfile(outputRoot, 'Wind_Belts_Analysis_2x4_with_Bias.png');
exportgraphics(fig, save_path, 'Resolution', 300);

fprintf('\n========================================================\n');
fprintf('完美拼版完成！包含具体 Bias 标注的 2x4 矩阵大图保存在:\n%s\n', save_path);
fprintf('========================================================\n');

%% =========================================================================
%                               函数库
% =========================================================================
function height_m = parse_lidar_height(variable_name)
%PARSE_LIDAR_HEIGHT Read height from original or MATLAB-normalized headers.
    height_m = NaN;

    token = regexp(variable_name, ...
        '^(\d+(?:\.\d+)?)m\s*Wind\s*Speed$', 'tokens', 'once');
    if ~isempty(token)
        height_m = str2double(token{1});
        return;
    end

    token = regexp(variable_name, ...
        '^x(\d+)_(\d+)mWindSpeed$', 'tokens', 'once');
    if ~isempty(token)
        height_m = str2double([token{1}, '.', token{2}]);
        return;
    end

    token = regexp(variable_name, ...
        '^x(\d+)mWindSpeed$', 'tokens', 'once');
    if ~isempty(token)
        height_m = str2double(token{1});
    end
end

function dist_km = calc_distance_to_coast(ship_lat, ship_lon)
    base = load('coastlines'); c_lat = base.coastlat; c_lon = base.coastlon;
    valid_c = ~isnan(c_lat) & ~isnan(c_lon); c_lat = c_lat(valid_c); c_lon = c_lon(valid_c);
    
    ship_lon = mod(ship_lon + 180, 360) - 180;
    c_lon    = mod(c_lon + 180, 360) - 180;
    
    n = length(ship_lat); dist_km = zeros(n, 1);
    if exist('distance', 'file')
        for i = 1:n
            d_deg = distance(ship_lat(i), ship_lon(i), c_lat, c_lon);
            dist_km(i) = min(d_deg) * 111.12; 
        end
    else
        c_y = c_lat * 111.12;
        for i = 1:n
            s_y = ship_lat(i) * 111.12; s_x_factor = cosd(ship_lat(i)) * 111.12;
            d_lon = abs(c_lon - ship_lon(i)); d_lon(d_lon > 180) = 360 - d_lon(d_lon > 180);
            dist_km(i) = min(sqrt((d_lon * s_x_factor).^2 + (c_y - s_y).^2));
        end
    end
end
