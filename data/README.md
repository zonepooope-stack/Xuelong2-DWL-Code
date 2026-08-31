# Input data specification

This directory contains the small derived residence-time table used by the collocation scripts. Large lidar and ERA5 files are not committed to the code repository.

The processed Xuelong2-DWL lidar dataset is archived separately in Zenodo at https://doi.org/10.5281/zenodo.22177312.

## `ship_grid_stay_all_hours.csv`

This table records the time spent by the moving vessel in the traversed ERA5 grid cells during each hourly collocation window.
It can be regenerated from the released lidar positions by running `build_ship_grid_stay_table.m` from the repository root.

| Field | Meaning | Unit or convention |
|---|---|---|
| `hour_start` | Start of the one-hour collocation window | China Standard Time, UTC+8 |
| `lon_center` | ERA5 grid-cell centre longitude | decimal degrees east |
| `lat_center` | ERA5 grid-cell centre latitude | decimal degrees north |
| `point_counts` | Number of vessel-position samples assigned to the grid cell during the hourly window | count |
| `stay_hours` | Cumulative vessel residence time in the grid cell during the hourly window | h |

## `lidar_profiles/`

Place the separately deposited Xuelong2-DWL daily CSV files in this directory, or set `XUELONG2_LIDAR_DIR` to their actual location.

Required fields are `Date_time`, `Longitude`, `Latitude`, and the height-dependent `WindSpeed` columns. Daily filenames must contain the corresponding UTC+8 date as `yyyymmdd`.

## `era5_hourly_pressure_levels/`

Place the downloaded ERA5 daily NetCDF files in this directory, or set `XUELONG2_ERA5_DIR` to their actual location. Files must follow the pattern `yyyy_mm_dd_part1.nc`.

Required NetCDF variables are `longitude`, `latitude`, `pressure_level`, `u`, `v`, and `z`. The scripts convert geopotential to geopotential height using `z / 9.81` and interpolate the residence-time-weighted ERA5 wind-speed profiles to the lidar measurement heights.

ERA5 source:

- https://cds.climate.copernicus.eu/datasets/reanalysis-era5-pressure-levels
- https://doi.org/10.24381/cds.bd0915c6

The ERA5 NetCDF files must not be committed to GitHub.

## `era5_request_manifest.csv`

This file records the date and north/west/south/east bounds of each of the 166 daily ERA5 requests used for the manuscript analysis. It is consumed by `download_era5_pressure_levels.py`. A row with `east < west` denotes an antimeridian-crossing request.
