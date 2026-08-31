# Cleaned-dataset validation

Validation date: 2026-08-29

## Scope

- The original `最终代码` folder was left unchanged.
- Among copied MATLAB files, only `project_config.m` was changed; `README.md`
  was updated to document the new local layout.
- The figure and statistical algorithms were not modified.
- `run_all_figures.m` was added as an optional batch runner.
- Generated files were written under this copy's `outputs/` folder.

## Input verification

The cleaned-dataset verification record reports:

- status: PASS;
- 166 daily CSV files;
- 23,675 profile rows;
- 40,436,900 retained data cells compared;
- all retained values identical to the source files;
- source files unchanged;
- no simplified-filename collisions.

The removed fields are `Temperature`, `Humidity`, `Pressure`, `LandWindSpd`,
`LandWindDir`, `RainLevel(mm)` and `RainSpeed(mm/min)`. None of the manuscript
figure scripts uses these fields.

## MATLAB run result

All ten code-based figure entries completed successfully:

| Figure | Script | Result |
|---|---|---|
| Fig. 1a | `shiptravel_in_paper.m` | PASS |
| Fig. 1b | `shiptravel_windband.m` | PASS |
| Fig. 3a | `match_check_for_whole_paper_time.m` | PASS |
| Fig. 3b | `match_check_for_point_daily_paper_time.m` | PASS |
| Fig. 4 | `reliable_lidar_data_threecase.m` | PASS |
| Fig. 5 | `shiptravel_rmse_1plus3plus3.m` | PASS |
| Fig. 6 | `windband_new.m` | PASS |
| Fig. 7 | `wind_dependence.m` | PASS |
| Fig. 8 | `distance_to_shore_each_windband.m` | PASS |
| Fig. 9 | `for_WS_nightday.m` | PASS |

The machine-readable run record is `outputs/run_status.csv`.

## Numerical cross-checks

The mutually exclusive circulation-regime counts in Figs. 6 and 8 are:

| Regime | N | Bias (m/s) |
|---|---:|---:|
| Northern Trade Winds | 21,165 | 0.57 |
| Southern Trade Winds | 7,739 | 5.02 |
| Westerlies | 32,221 | 2.05 |
| Polar Easterlies | 29,394 | 3.43 |
| Total | 90,519 | — |

The Fig. 9 day/night counts are:

| Period | N | Bias (m/s) | RMSE (m/s) | Pearson R |
|---|---:|---:|---:|---:|
| Day Time | 60,211 | 2.38 | 5.62 | 0.648 |
| Night Time | 30,308 | 2.45 | 5.55 | 0.633 |
| Total | 90,519 | — | — | — |

Both independent partitions sum to 90,519 samples. These values match the
final corrected time-matching and mutually exclusive wind-regime logic. Because
all fields used by the scripts are retained byte-for-byte, the cleaned release
does not change the scientific results.
