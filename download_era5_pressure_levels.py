#!/usr/bin/env python3
"""Download the daily ERA5 pressure-level subsets used by Xuelong2-DWL.

The spatial bounds in ``data/era5_request_manifest.csv`` were extracted from
the ERA5 files used for the manuscript analysis.  Longitudes with east < west
cross the antimeridian, which is supported by the CDS API.

Authentication is handled by the CDS API client.  Do not place an API token in
this repository; configure it according to the CDS instructions instead.
"""

from __future__ import annotations

import argparse
import csv
import json
import time
from datetime import date
from pathlib import Path
from typing import Any


DATASET = "reanalysis-era5-pressure-levels"
PRESSURE_LEVELS = [
    "1000", "975", "950", "925", "900", "875", "850", "825",
    "800", "775", "750", "700", "650", "600", "550", "500",
]
VARIABLES = [
    "u_component_of_wind",
    "v_component_of_wind",
    "geopotential",
]
TIMES = [f"{hour:02d}:00" for hour in range(24)]
REQUIRED_COLUMNS = {"date", "north", "west", "south", "east"}


def parse_args() -> argparse.Namespace:
    repository_root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description="Download daily ERA5 pressure-level subsets for Xuelong2-DWL."
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=repository_root / "data" / "era5_request_manifest.csv",
        help="CSV containing date and north/west/south/east request bounds.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=repository_root / "data" / "era5_hourly_pressure_levels",
        help="Directory for downloaded NetCDF files.",
    )
    parser.add_argument("--start-date", type=date.fromisoformat)
    parser.add_argument("--end-date", type=date.fromisoformat)
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace an existing daily NetCDF file.",
    )
    parser.add_argument(
        "--max-retries",
        type=int,
        default=5,
        help="Maximum CDS retrieval attempts for each daily file (default: 5).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print requests without contacting the CDS.",
    )
    return parser.parse_args()


def read_manifest(
    path: Path, start_date: date | None, end_date: date | None
) -> list[dict[str, Any]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        columns = set(reader.fieldnames or [])
        missing = REQUIRED_COLUMNS - columns
        if missing:
            raise ValueError(f"Manifest is missing columns: {sorted(missing)}")

        rows: list[dict[str, Any]] = []
        for source_row in reader:
            request_date = date.fromisoformat(source_row["date"])
            if start_date and request_date < start_date:
                continue
            if end_date and request_date > end_date:
                continue

            row = {
                "date": request_date,
                "north": float(source_row["north"]),
                "west": float(source_row["west"]),
                "south": float(source_row["south"]),
                "east": float(source_row["east"]),
            }
            if row["north"] < row["south"]:
                raise ValueError(f"North is below south for {request_date}")
            if not all(-180 <= row[key] <= 180 for key in ("west", "east")):
                raise ValueError(f"Longitude is outside [-180, 180] for {request_date}")
            rows.append(row)

    if not rows:
        raise ValueError("No manifest rows matched the requested date range.")
    return rows


def build_request(row: dict[str, Any]) -> dict[str, Any]:
    request_date: date = row["date"]
    return {
        "product_type": ["reanalysis"],
        "variable": VARIABLES,
        "year": [f"{request_date.year:04d}"],
        "month": [f"{request_date.month:02d}"],
        "day": [f"{request_date.day:02d}"],
        "time": TIMES,
        "pressure_level": PRESSURE_LEVELS,
        "data_format": "netcdf",
        "download_format": "unarchived",
        "area": [row["north"], row["west"], row["south"], row["east"]],
    }


def main() -> None:
    args = parse_args()
    if args.start_date and args.end_date and args.start_date > args.end_date:
        raise ValueError("--start-date must not be after --end-date.")
    if args.max_retries < 1:
        raise ValueError("--max-retries must be at least 1.")

    rows = read_manifest(args.manifest, args.start_date, args.end_date)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    if args.dry_run:
        client = None
    else:
        try:
            import cdsapi
        except ImportError as exc:
            raise SystemExit(
                "The cdsapi package is required. Run: "
                "python -m pip install -r requirements.txt"
            ) from exc
        client = cdsapi.Client()

    for index, row in enumerate(rows, start=1):
        request_date: date = row["date"]
        target = args.output_dir / f"{request_date:%Y_%m_%d}_part1.nc"
        request = build_request(row)

        if target.exists() and not args.overwrite:
            print(f"[{index}/{len(rows)}] SKIP {target.name} (already exists)")
            continue

        print(f"[{index}/{len(rows)}] {request_date} -> {target}")
        if args.dry_run:
            print(json.dumps(request, indent=2))
        else:
            assert client is not None
            for attempt in range(1, args.max_retries + 1):
                try:
                    client.retrieve(DATASET, request, str(target))
                    break
                except Exception:
                    if attempt == args.max_retries:
                        raise
                    wait_seconds = 30 * attempt
                    print(
                        f"  Retrieval attempt {attempt} failed; "
                        f"retrying in {wait_seconds} s."
                    )
                    time.sleep(wait_seconds)


if __name__ == "__main__":
    main()
