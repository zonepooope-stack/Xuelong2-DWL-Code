function cfg = project_config()
%PROJECT_CONFIG Portable paths for the Xuelong2-DWL figure scripts.
%
% Default repository layout:
%   data/era5_hourly_pressure_levels/*.nc
%   data/lidar_profiles/*.csv or *.xlsx
%   data/ship_grid_stay_all_hours.csv
%   outputs/
%
% For data stored elsewhere, set XUELONG2_DATA_ROOT before starting MATLAB.
% To redirect generated figures, set XUELONG2_OUTPUT_ROOT.

repo_root = fileparts(mfilename('fullpath'));

data_root = getenv('XUELONG2_DATA_ROOT');
if isempty(data_root)
    data_root = fullfile(repo_root, 'data');
end

output_root = getenv('XUELONG2_OUTPUT_ROOT');
if isempty(output_root)
    output_root = fullfile(repo_root, 'outputs');
end

cfg.repoRoot = repo_root;
cfg.dataRoot = data_root;
cfg.outputRoot = output_root;
cfg.era5DataFolder = getenv('XUELONG2_ERA5_DIR');
if isempty(cfg.era5DataFolder)
    cfg.era5DataFolder = fullfile(data_root, 'era5_hourly_pressure_levels');
end

cfg.lidarDataFolder = getenv('XUELONG2_LIDAR_DIR');
if isempty(cfg.lidarDataFolder)
    cfg.lidarDataFolder = fullfile(data_root, 'lidar_profiles');
end

cfg.stayInfoFile = getenv('XUELONG2_STAY_FILE');
if isempty(cfg.stayInfoFile)
    cfg.stayInfoFile = fullfile(data_root, 'ship_grid_stay_all_hours.csv');
end
end
