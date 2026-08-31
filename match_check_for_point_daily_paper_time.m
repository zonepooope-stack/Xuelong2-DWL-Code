%=====================================================================
%  Sci-Vis: ERA5 vs Lidar (热力图版：颜色代表停留时长)
%=====================================================================
%  核心修改：
%  1. 颜色逻辑：不再随机。格点颜色深浅代表船只在该网格内的停留时长。
%  2. 新增 Colorbar：右侧显示颜色对应的时长 (小时)。
%  3. 保留所有美化：Times New Roman, 稀疏坐标轴, 完美正方形。
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

% --- 配色配置 ---
color_ocean     = [0.88, 0.95, 0.98];  % 冰川蓝
color_land      = [0.45, 0.45, 0.45];  % 中灰陆地
color_grid_line = [0.55, 0.55, 0.55];  % 网格线
color_bg_point  = [0.50, 0.50, 0.50];  % 背景点

% 创建输出文件夹
checkFolder_Art = fullfile(outputFolder, 'Daily_Check_Heatmap'); 
if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end
if ~exist(checkFolder_Art, 'dir'), mkdir(checkFolder_Art); end

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
files_read_count = 0;
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
                    files_read_count = files_read_count + 1;
                end
            end
        end
    catch; end
end
if isempty(allLidar), warning('没有读取到雷达数据'); else, allLidar = sortrows(allLidar, 'Date_time'); end
fprintf('    成功读取 %d 个文件，共 %d 行数据。\n', files_read_count, height(allLidar));

%% ====================================================================
%              Part 3: 绘图 (热力图模式)
% ====================================================================
fprintf('>>> [3/3] 开始绘图 (Color by Duration)...\n');

try, land_shapes = shaperead('landareas', 'UseGeoCoords', true); catch, land_shapes = []; end
try, coast_lines = load('coastlines'); catch, coast_lines.coastlat=[]; coast_lines.coastlon=[]; end

% 本代码只生成 2023-11-01（UTC）这一天。
% 对应北京时间：2023-11-01 08:00 至 2023-11-02 08:00。
unique_days_utc = datetime(2023, 11, 1, 'TimeZone', 'UTC');
num_days = 1;

% 定义热力图色谱 (Turbo 比较适合显示强度，且两端区分明显)
colormap_style = turbo(256); 

for i = 1:num_days
    target_date_utc = unique_days_utc(i); 
    date_str = datestr(target_date_utc, 'yyyy-mm-dd');
    
    day_mask = FinalData.hour_start_utc >= target_date_utc & FinalData.hour_start_utc < target_date_utc + days(1);
    DailyGrid = FinalData(day_mask, :);
    if isempty(DailyGrid), continue; end
    
    lidar_mask = allLidar.Date_time >= target_date_utc & allLidar.Date_time < target_date_utc + days(1);
    DailyRaw = allLidar(lidar_mask, :);
    
    % --- 1. 画布设置 ---
    fig = figure('Visible', 'on', 'Position', [100, 100, 1050, 900], 'Color', 'w'); % 运行后显示图窗
    ax = axes; hold(ax, 'on');
    set(ax, 'Color', color_ocean);
    
    if ~isempty(land_shapes), geoshow(ax, land_shapes, 'FaceColor', color_land, 'EdgeColor', 'none'); end
    % if ~isempty(coast_lines.coastlat), plot(coast_lines.coastlon, coast_lines.coastlat, '-', 'Color', color_coast, 'LineWidth', 0.8); end
    
    % --- 2. 视野调整 ---
    lat_min = min(DailyGrid.lat_center); lat_max = max(DailyGrid.lat_center);
    lon_min = min(DailyGrid.lon_center); lon_max = max(DailyGrid.lon_center);
    cen_lat = (lat_min + lat_max) / 2; cen_lon = (lon_min + lon_max) / 2;
    
    span_lat = lat_max - lat_min;
    span_lon_equiv = (lon_max - lon_min) * cosd(cen_lat);
    base_span = max([span_lat, span_lon_equiv, 0.8]) * 1.4; 
    
    half_lat = base_span / 2; half_lon = (base_span / cosd(cen_lat)) / 2;
    ylim_val = [cen_lat - half_lat, cen_lat + half_lat];
    xlim_val = [cen_lon - half_lon, cen_lon + half_lon];
    axis([xlim_val ylim_val]); daspect([1 cosd(cen_lat) 1]); 
    
    % --- 3. 背景网格 ---
    res = 0.25; half = 0.125;
    glon_s = floor(xlim_val(1)/res)*res - half; glon_e = ceil(xlim_val(2)/res)*res + half;
    glat_s = floor(ylim_val(1)/res)*res - half; glat_e = ceil(ylim_val(2)/res)*res + half;
    
    for gx = glon_s:res:glon_e, plot([gx gx], ylim_val, ':', 'Color', color_grid_line, 'LineWidth', 0.5); end
    for gy = glat_s:res:glat_e, plot(xlim_val, [gy gy], ':', 'Color', color_grid_line, 'LineWidth', 0.5); end
    [bg_x, bg_y] = meshgrid(glon_s+half : res : glon_e, glat_s+half : res : glat_e);
    plot(bg_x(:), bg_y(:), 's', 'MarkerSize', 2, 'MarkerFaceColor', color_bg_point, 'MarkerEdgeColor', 'none');

    % --- 4. 核心计算与绘制 (停留时长) ---
    [unique_grids, ia, ic] = unique([DailyGrid.lat_center, DailyGrid.lon_center], 'rows');
    num_grids = size(unique_grids, 1);
    
    % 4.1 预先计算每个格子的停留时长
    grid_durations = zeros(num_grids, 1);
    
    for k = 1:num_grids
        u_lat = unique_grids(k, 1);
        u_lon = unique_grids(k, 2);
        
        if ~isempty(DailyRaw)
            in_box = DailyRaw.Longitude >= (u_lon-half) & DailyRaw.Longitude < (u_lon+half) & ...
                     DailyRaw.Latitude >= (u_lat-half) & DailyRaw.Latitude < (u_lat+half);
            if any(in_box)
                % 计算最大时间差 (小时)
                grid_time = DailyRaw.Date_time(in_box);
                grid_durations(k) = hours(max(grid_time) - min(grid_time));
                % 如果只有一个点或时间极短，给一个最小值以便显示颜色
                if grid_durations(k) == 0, grid_durations(k) = 0.1; end 
            end
        end
    end
    
    % 4.2 设置颜色映射范围 (Color Axis)
    % 自动归一化：最短时间 -> 蓝色，最长时间 -> 红色
    max_dur = max(grid_durations);
    if max_dur == 0, max_dur = 1; end % 防止除以0
    caxis([0, max_dur]); % 设置当前图的颜色范围
    colormap(ax, colormap_style); % 应用 Turbo 色谱
    
    % 4.3 循环绘图
    % 虚拟图例 (颜色由时长决定，这里图例只显示符号)
    h_center_dummy = plot(NaN, NaN, 's', 'MarkerSize', 5, 'MarkerFaceColor', [0.3 0.3 0.3], 'MarkerEdgeColor', 'k', 'LineWidth', 0.5, 'DisplayName', 'ERA5 Center');
    h_ship_dummy  = scatter(NaN, NaN, 20, 'k', 'filled', 'MarkerFaceColor', [0.2 0.2 0.2], 'DisplayName', 'Lidar Points');
    
    for k = 1:num_grids
        u_lat = unique_grids(k, 1);
        u_lon = unique_grids(k, 2);
        
        duration = grid_durations(k);
        
        % 映射颜色: 将 duration 映射到 1-256 的色谱索引
        color_idx = max(1, min(256, round((duration / max_dur) * 256)));
        this_color = colormap_style(color_idx, :);
        this_dark = this_color * 0.7; % 点稍微深一点
        
        % A. 矩形 (颜色代表时长)
        x_box = [u_lon-half, u_lon+half, u_lon+half, u_lon-half]; 
        y_box = [u_lat-half, u_lat-half, u_lat+half, u_lat+half];
        % Alpha 设为 0.5，保证颜色可见但透出网格
        patch(x_box, y_box, this_color, 'FaceAlpha', 0.5, 'EdgeColor', 'none');
        
        % B. ERA5 中心
        plot(u_lon, u_lat, 's', 'MarkerSize', 5, 'MarkerFaceColor', this_dark, 'MarkerEdgeColor', 'k', 'LineWidth', 0.5); 
        
        % C. 雷达点 (同色系深色)
        if ~isempty(DailyRaw)
             in_box = DailyRaw.Longitude >= (u_lon-half) & DailyRaw.Longitude < (u_lon+half) & ...
                      DailyRaw.Latitude >= (u_lat-half) & DailyRaw.Latitude < (u_lat+half);
             if any(in_box)
                scatter(DailyRaw.Longitude(in_box), DailyRaw.Latitude(in_box), 12, ...
                    'MarkerFaceColor', this_dark, 'MarkerEdgeColor', 'none', 'MarkerFaceAlpha', 0.9);
             end
        end
    end
    
    % --- 5. 坐标轴与 Colorbar ---
    box on; 
    set(ax, 'Layer', 'top', 'FontName', 'Times New Roman', ...
        'FontSize', 18, 'FontWeight', 'bold', 'LineWidth', 1.5, 'TickDir', 'out');
    
    xlabel('Longitude', 'FontSize', 20, 'FontWeight', 'bold', 'FontName', 'Times New Roman'); 
    ylabel('Latitude',  'FontSize', 20, 'FontWeight', 'bold', 'FontName', 'Times New Roman');
    
    % 强制刷新刻度 & 稀疏化
    drawnow;
    raw_xt = xticks;
    if length(raw_xt) > 3, new_xt = raw_xt(1:2:end); xticks(new_xt); end
    
    xt = xticks; xl = cell(size(xt));
    for k=1:length(xt), if xt(k)>=0, xl{k}=sprintf('%.1f°E', xt(k)); else, xl{k}=sprintf('%.1f°W', abs(xt(k))); end; end
    xticklabels(xl); xtickangle(0);
    
    yt = yticks; yl = cell(size(yt));
    for k=1:length(yt), if yt(k)>=0, yl{k}=sprintf('%.1f°N', yt(k)); else, yl{k}=sprintf('%.1f°S', abs(yt(k))); end; end
    yticklabels(yl); ytickangle(0);
    
    % title({['\bf Geometric Match: ' date_str ' (UTC)']}, 'Interpreter', 'tex', 'FontSize', 18, 'FontName', 'Times New Roman');
    
    % 图例 (仅位置)
    legend([h_center_dummy, h_ship_dummy], 'Location', 'NorthEast', ...
        'FontSize', 18, 'FontName', 'Times New Roman', 'Box', 'off', 'Color', 'none'); 
    
    % === [核心新增] Colorbar 设置 ===
    cb = colorbar;
    cb.Label.String = 'Stay Duration (Hours)'; % 标签
    cb.Label.FontSize = 16;
    cb.Label.FontName = 'Times New Roman';
    cb.FontSize = 20;
    cb.FontName = 'Times New Roman';
    cb.FontWeight = 'bold';
    % 调整位置以防遮挡 (放在右侧外面)
    % set(cb, 'Location', 'eastoutside'); 
    
    savePath = fullfile(checkFolder_Art, sprintf('Heatmap_%s.png', date_str));
    exportgraphics(fig, savePath, 'Resolution', 600, 'BackgroundColor', 'white');
    drawnow;
    figure(fig); % 保存后保持图窗显示，不自动关闭
    if mod(i, 10) == 0, fprintf('    已生成 %d / %d 张...\n', i, num_days); end
end
fprintf('全部完成！请查看: %s\n', checkFolder_Art);
