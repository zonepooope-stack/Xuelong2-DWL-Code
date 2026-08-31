% =========================================================================
%  Script: Multi-Case Lidar vs ERA5 Profile Matrix
%  功能：在一张图中并排展示 3 个独立的高保真 Case (3x3 矩阵排版)
%  亮点：按列分布不同地理区域，按行分布不同数据(Lidar, ERA5, Diff)
% =========================================================================
clc; clear; close all;

%% ======================= 0. 定义 3 个核心 Case =======================
% 格式：{Start_Time, End_Time, 'Case 标题 (包含地理信息)'}
Cases = {
    datetime(2023, 10, 31, 0, 0, 0, 'TimeZone', 'UTC'), datetime(2023, 11, 9, 23, 0, 0, 'TimeZone', 'UTC'), 'Case 1: Oct 31-Nov 9, 2023, Low-latitude Western Pacific';
    datetime(2023, 11, 13, 0, 0, 0, 'TimeZone', 'UTC'), datetime(2023, 11, 22, 23, 0, 0, 'TimeZone', 'UTC'), 'Case 2: Nov 13-23, 2023, Subtropical Open Ocean';
    datetime(2023, 11, 23, 0, 0, 0, 'TimeZone', 'UTC'), datetime(2023, 12, 2, 23, 0, 0, 'TimeZone', 'UTC'),   'Case 3: Nov 23-Dec 2, 2023, Southern Ocean Transition'
};
num_cases = size(Cases, 1);

%% ======================= 1. 通用参数配置 =======================
Z_MIN = 0;   
Z_MAX = 3000;
Z_STEP = 50; 
Z_grid = (Z_MIN:Z_STEP:Z_MAX)';
MAX_VALID_WS = 100;     
g = 9.81;
font_n = 'Arial';

% --- Portable repository paths ---
scriptFolder = fileparts(mfilename('fullpath'));
addpath(scriptFolder);
cfg = project_config();
era5DataFolder  = cfg.era5DataFolder;
stayInfoFile    = cfg.stayInfoFile;
lidarDataFolder = cfg.lidarDataFolder;
outputRoot      = fullfile(cfg.outputRoot, 'fig04');
if ~exist(outputRoot, 'dir'), mkdir(outputRoot); end

fprintf('正在初始化船舶停留时间文件...\n');
stayData = readtable(stayInfoFile);
try
    temp_time = datetime(stayData.hour_start);
    temp_time.TimeZone = 'UTC+8'; 
    stayData.hour_start_utc = datetime(temp_time, 'TimeZone', 'UTC');
catch
    error('时间格式转换失败。');
end
lidarFiles = [dir(fullfile(lidarDataFolder, '*.csv')); dir(fullfile(lidarDataFolder, '*.xlsx'))];

Lidar_Data_All = cell(num_cases, 1);
ERA5_Data_All  = cell(num_cases, 1);
Diff_Data_All  = cell(num_cases, 1);
Time_Vec_All   = cell(num_cases, 1);
Stats_All      = cell(num_cases, 1);

%% ======================= 2. 循环处理每个 Case 的数据 =======================
cached_lidar_filename = '';
cached_lidar_table = table();
current_nc_date = datetime(1900,1,1,'TimeZone','UTC');
current_era5_data = struct();
era5VarNames = {};

for c = 1:num_cases
    fprintf('\n>>> 正在处理 %s <<<\n', Cases{c, 3});
    START_TIME = Cases{c, 1};
    END_TIME   = Cases{c, 2};
    Time_Vector = (START_TIME : hours(1) : END_TIME)';
    num_hours   = length(Time_Vector);
    
    Lidar_Matrix = NaN(length(Z_grid), num_hours);
    ERA5_Matrix  = NaN(length(Z_grid), num_hours);
    
    for i = 1:num_hours
        t_start = Time_Vector(i); 
        t_end   = t_start + hours(1);
        if mod(i, 48) == 0, fprintf('     进度: %d / %d 小时\n', i, num_hours); end
        
        % --- 读取 Lidar ---
        t_start_bjt = t_start + hours(8);
        file_date_str = datestr(t_start_bjt, 'yyyymmdd');
        current_lidar_file = [];
        for f = 1:length(lidarFiles)
            if contains(lidarFiles(f).name, file_date_str)
                current_lidar_file = lidarFiles(f); break; 
            end
        end
        
        if ~isempty(current_lidar_file)
            try
                if ~strcmp(current_lidar_file.name, cached_lidar_filename)
                    opts = detectImportOptions(fullfile(lidarDataFolder, current_lidar_file.name));
                    opts.VariableNamingRule = 'preserve';
                    cached_lidar_table = readtable(fullfile(lidarDataFolder, current_lidar_file.name), opts);
                    cached_lidar_filename = current_lidar_file.name;
                end
                T = cached_lidar_table;
                if ismember('Date_time', T.Properties.VariableNames), t_col_raw = T.Date_time;
                elseif ismember('Time', T.Properties.VariableNames), t_col_raw = T.Time;
                else, continue; end
                
                if isdatetime(t_col_raw), t_col = t_col_raw; else, t_col = datetime(t_col_raw, 'InputFormat', 'yyyyMMdd HH:mm:ss'); end
                t_col.TimeZone = 'UTC+8'; t_col_utc = datetime(t_col, 'TimeZone', 'UTC');
                
                rows = find(t_col_utc >= t_start & t_col_utc < t_end);
                if ~isempty(rows)
                    subT = T(rows, :);
                    l_h = []; l_ws = [];
                    vNames = subT.Properties.VariableNames;
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
                    if length(l_h) > 1, Lidar_Matrix(:, i) = interp1(l_h, l_ws, Z_grid, 'linear', NaN); end
                end
            catch
            end
        end
        
        % --- 读取 ERA5 ---
        hourGridData = stayData(stayData.hour_start_utc == t_start, :);
        if isempty(hourGridData), continue; end
        targetDate = dateshift(t_start, 'start', 'day');
        time_idx = hour(t_start) + 1;
        
        if targetDate ~= current_nc_date
            current_nc_date = targetDate;
            ncPath = fullfile(era5DataFolder, sprintf('%s_part1.nc', datestr(targetDate, 'yyyy_mm_dd')));
            current_era5_data = struct(); 
            if exist(ncPath, 'file')
                try
                    ncInfo = ncinfo(ncPath); allVars = {ncInfo.Variables.Name};
                    era5VarNames = setdiff(allVars, {'longitude', 'latitude', 'pressure_level', 'valid_time', 'time', 'number', 'expver'});
                    era5_lon = ncread(ncPath, 'longitude'); era5_lat = ncread(ncPath, 'latitude');
                    era5_pressure = ncread(ncPath, 'pressure_level'); 
                    if any(era5_lon < 0), era5_lon(era5_lon < 0) = era5_lon(era5_lon < 0) + 360; end
                    [era5_lon, lon_sort_idx] = sort(era5_lon);
                    for v = 1:length(era5VarNames)
                        vn = era5VarNames{v}; raw = ncread(ncPath, vn);
                        if ndims(raw)==4, raw = raw(lon_sort_idx,:,:,:); else, raw = raw(lon_sort_idx,:,:); end
                        current_era5_data.(vn) = raw;
                    end
                    current_era5_data.pressure_level = era5_pressure;
                catch, end
            end
        end
        if isempty(fieldnames(current_era5_data)), continue; end
        
        total_stay = sum(hourGridData.stay_hours);
        if total_stay > 0 
            num_p_levels = length(current_era5_data.pressure_level);
            hourly_vals = zeros(num_p_levels, length(era5VarNames));
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
            e_z = hourly_vals(:, strcmp(era5VarNames, 'z')) / g;
            e_u = hourly_vals(:, strcmp(era5VarNames, 'u'));
            e_v = hourly_vals(:, strcmp(era5VarNames, 'v'));
            e_ws = sqrt(e_u.^2 + e_v.^2);
            [e_z, sort_i] = sort(e_z); e_ws = e_ws(sort_i);
            mask_e = ~isnan(e_z) & ~isnan(e_ws);
            if sum(mask_e) > 1, ERA5_Matrix(:, i) = interp1(e_z(mask_e), e_ws(mask_e), Z_grid, 'linear', NaN); end
        end
    end
    
    % 掩膜对齐与差值计算
    ERA5_Masked_Matrix = ERA5_Matrix;
    ERA5_Masked_Matrix(isnan(Lidar_Matrix)) = NaN;
    Diff_Matrix = Lidar_Matrix - ERA5_Masked_Matrix;
    
    % 统计参数
    valid_idx = ~isnan(Lidar_Matrix) & ~isnan(ERA5_Masked_Matrix);
    l_flat = Lidar_Matrix(valid_idx); e_flat = ERA5_Masked_Matrix(valid_idx);
    
    stats.N = length(l_flat);
    if stats.N > 0
        stats.RMSE = sqrt(mean((l_flat - e_flat).^2));
        stats.Bias = mean(l_flat - e_flat);
        % Pearson 相关系数：与论文其他脚本一致，取 corrcoef 的非对角元素。
        if stats.N >= 2
            R_matrix = corrcoef(l_flat, e_flat);
            if numel(R_matrix) > 1
                stats.R = R_matrix(1, 2);
            else
                stats.R = NaN;
            end
        else
            stats.R = NaN;
        end
    else
        stats.RMSE = NaN; stats.Bias = NaN; stats.R = NaN;
    end
    stats.Title = Cases{c, 3};
    
    % 存入集合
    Lidar_Data_All{c} = Lidar_Matrix;
    ERA5_Data_All{c}  = ERA5_Masked_Matrix;
    Diff_Data_All{c}  = Diff_Matrix;
    Time_Vec_All{c}   = Time_Vector;
    Stats_All{c}      = stats;
end

%% ======================= 3. 绘制终极 3x3 矩阵大图 =======================
fprintf('\n开始生成 3x3 矩阵式高质量复合图...\n');

fig = figure('Name', 'Multi-Case Matrix', 'Visible', 'on', ...
    'Color', 'w', 'Position', [50, 50, 1800, 1000]);
set(fig, 'DefaultAxesFontName', font_n, 'DefaultTextFontName', font_n, ...
    'DefaultAxesFontWeight', 'bold', 'DefaultTextFontWeight', 'bold');
t = tiledlayout(3, num_cases, 'TileSpacing', 'compact', 'Padding', 'compact');

% 构造高级色谱
n_color = 128;
custom_RdBu = [linspace(0.1, 1, n_color)', linspace(0.3, 1, n_color)', ones(n_color, 1); ...
               ones(n_color, 1), linspace(1, 0.2, n_color)', linspace(1, 0.1, n_color)'];

for c = 1:num_cases
    time_num = datenum(Time_Vec_All{c});
    plot_time = [time_num; time_num(end) + (time_num(end)-time_num(end-1))];
    plot_Z = [Z_grid; Z_grid(end) + (Z_grid(end)-Z_grid(end-1))];
    [T_mesh, Z_mesh] = meshgrid(plot_time, plot_Z);
    
    % ----------------- 第 1 行：Lidar -----------------
    ax1 = nexttile(c); 
    set(ax1, 'Color', [0.85 0.85 0.85]); hold(ax1, 'on'); 
    pcolor(ax1, T_mesh, Z_mesh, [Lidar_Data_All{c}, NaN(size(Z_grid,1),1); NaN(1, size(Time_Vec_All{c},1)+1)]); 
    shading(ax1, 'flat'); colormap(ax1, jet); caxis(ax1, [0 20]);
    
    % 第一行是 Lidar 数据，因此保留第二行 Lidar 剖面标题。
    title(ax1, {Stats_All{c}.Title, ...
        'High-Resolution Shipborne Lidar Wind Speed Profile'}, ...
        'FontSize', 13, 'FontWeight', 'bold', 'FontName', font_n);
    if c == 1, ylabel(ax1, 'Height (m)', 'FontSize', 14, 'FontWeight', 'bold', 'FontName', font_n); end
    
    % 添加 Lidar Colorbar
    if c == num_cases
        cb1 = colorbar(ax1); 
        cb1.FontName = font_n; cb1.FontWeight = 'bold';
        cb1.Label.String = 'V_{lidar} (m/s)'; cb1.Label.FontWeight = 'bold'; cb1.Label.FontName = font_n;
    end
    
    % ----------------- 第 2 行：ERA5 -----------------
    ax2 = nexttile(c + num_cases); 
    set(ax2, 'Color', [0.85 0.85 0.85]); hold(ax2, 'on');
    pcolor(ax2, T_mesh, Z_mesh, [ERA5_Data_All{c}, NaN(size(Z_grid,1),1); NaN(1, size(Time_Vec_All{c},1)+1)]); 
    shading(ax2, 'flat'); colormap(ax2, jet); caxis(ax2, [0 20]);
    
    % 【修改点】：单行无字母标题 + 统一 Y 轴
    title(ax2, 'ERA5 Reanalysis Wind Speed Profile', 'FontSize', 13, 'FontWeight', 'bold', 'FontName', font_n);
    if c == 1, ylabel(ax2, 'Height (m)', 'FontSize', 14, 'FontWeight', 'bold', 'FontName', font_n); end
    
    if c == num_cases
        cb_era = colorbar(ax2); 
        cb_era.FontName = font_n; cb_era.FontWeight = 'bold';
        cb_era.Label.String = 'V_{ERA5} (m/s)'; cb_era.Label.FontWeight = 'bold'; cb_era.Label.FontName = font_n;
    end
    
    % ----------------- 第 3 行：Difference -----------------
    ax3 = nexttile(c + 2*num_cases); 
    set(ax3, 'Color', [0.85 0.85 0.85]); hold(ax3, 'on');
    pcolor(ax3, T_mesh, Z_mesh, [Diff_Data_All{c}, NaN(size(Z_grid,1),1); NaN(1, size(Time_Vec_All{c},1)+1)]); 
    shading(ax3, 'flat'); colormap(ax3, custom_RdBu); caxis(ax3, [-5 5]); 
    
    % 【修改点】：单行无字母标题 + 统一 Y 轴
    title(ax3, 'Wind Speed Difference', 'FontSize', 13, 'FontWeight', 'bold', 'FontName', font_n);
    if c == 1, ylabel(ax3, 'Height (m)', 'FontSize', 14, 'FontWeight', 'bold', 'FontName', font_n); end
    xlabel(ax3, 'Date (UTC)', 'FontSize', 14, 'FontWeight', 'bold', 'FontName', font_n);
    
    if c == num_cases
        cb_diff = colorbar(ax3); 
        cb_diff.FontName = font_n; cb_diff.FontWeight = 'bold';
        cb_diff.Label.String = 'V_{lidar} - V_{ERA5} (m/s)'; cb_diff.Label.FontWeight = 'bold'; cb_diff.Label.FontName = font_n;
    end

    % ----------------- 统计框 -----------------
    stats_str = {sprintf('N = %d', Stats_All{c}.N), ...
                 sprintf('R = %.2f', Stats_All{c}.R), ...
                 sprintf('RMSE = %.2f m/s', Stats_All{c}.RMSE), ...
                 sprintf('Bias = %.2f m/s', Stats_All{c}.Bias)};
    text(ax3, 0.02, 0.95, stats_str, 'Units', 'normalized', 'VerticalAlignment', 'top', ...
        'FontSize', 12, 'FontWeight', 'bold', 'FontName', font_n, ...
        'BackgroundColor', [1 1 1 0.85], 'EdgeColor', 'k', 'Margin', 4);

    % ----------------- 统一格式化当前列的 3 个 Axis -----------------
    axs = [ax1, ax2, ax3];
    for ax = axs
        set(ax, 'FontSize', 13, 'FontWeight', 'bold', ...
            'LineWidth', 1.2, 'Box', 'on', 'TickDir', 'in', ...
            'FontName', font_n);
        xlim(ax, [min(time_num) max(time_num)]);
        ylim(ax, [Z_MIN Z_MAX]);
        
        if c ~= 1, set(ax, 'YTickLabel', []); end
        
        if ax == ax3
            % 三个 Case 均固定为每日刻度，并保持简洁的水平数字格式。
            first_day = dateshift(Time_Vec_All{c}(1), 'start', 'day');
            last_day  = dateshift(Time_Vec_All{c}(end), 'start', 'day');
            daily_ticks = datenum((first_day : days(1) : last_day)');
            set(ax, 'XTick', daily_ticks);
            datetick(ax, 'x', 'mm-dd', 'keepticks', 'keeplimits');
            xtickangle(ax, 0);
        else
            set(ax, 'XTickLabel', []); 
        end
    end
end

drawnow;
save_path = fullfile(outputRoot, 'Multi_Case_Matrix_Profile_Formatted.png');
exportgraphics(fig, save_path, 'Resolution', 300);
set(fig, 'Visible', 'on');
figure(fig);
drawnow;
fprintf('完美完成！排版升级版的 3x3 矩阵图已保存至: %s\n', save_path);
