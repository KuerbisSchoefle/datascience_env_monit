"""01_era5land.py — ERA5-Land hourly time series at your five towers.

Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg

ERA5-Land: ECMWF land reanalysis, 0.1° (~9 km), hourly, 1950–today.
Your FLUXNET zips already contain ERA5 weather downscaled to each tower
(the *_ERA5_*.csv files). ERA5-Land adds what most towers do NOT measure:
soil moisture and soil temperature in four layers down to 2.89 m.

Dataset "reanalysis-era5-land-timeseries" on the Copernicus Climate Data Store
(CDS) is a point product: the CDS takes the nearest grid cell and returns CSV.

ONCE, before class:
  1. Make a free account at https://cds.climate.copernicus.eu
  2. Accept the dataset licence (dataset page, tab "Download", "Terms of use").
  3. pip install cdsapi
  4. Create the file ~/.cdsapirc (Windows: C:\\Users\\<you>\\.cdsapirc) with two lines:
        url: https://cds.climate.copernicus.eu/api
        key: PASTE-YOUR-PERSONAL-ACCESS-TOKEN-HERE

Output: data/external/era5land/<SITE>_era5land_hourly.csv and _daily.csv
Cite:   Muñoz-Sabater et al. (2021) ESSD 13, 4349–4383, doi:10.5194/essd-13-4349-2021
        + "Contains modified Copernicus Climate Change Service information <year>"

Run: python3 scripts/block5/01_era5land.py --student 07
"""
import sys
import zipfile
from datetime import date
from functools import reduce
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from block5_sites import get_my_sites, out_dir, parse_args, say  # noqa: E402

import cdsapi  # noqa: E402

VARIABLES = [
    "2m_temperature",
    "volumetric_soil_water_layer_1",   # 0–7 cm   (m3 m-3)
    "volumetric_soil_water_layer_2",   # 7–28 cm
    "volumetric_soil_water_layer_3",   # 28–100 cm
    "soil_temperature_level_1",        # 0–7 cm   (K)
]
# More: "total_precipitation", "surface_solar_radiation_downwards", "snow_depth", ...
# Careful: precipitation and radiation are ACCUMULATED in ERA5-Land; look before you sum.
YEARS_BACK = 10   # years at the end of each tower record (the CDS has quotas)

args = parse_args("ERA5-Land time series for your towers")
sites = get_my_sites(args.student, args.sites)
d = out_dir("era5land")
try:
    client = cdsapi.Client()
except Exception:   # no ~/.cdsapirc, or the file is incomplete
    raise SystemExit(
        "\n\nNo CDS token found. Do this once (see the top of this script):\n"
        "  1. Log in at https://cds.climate.copernicus.eu and copy your Personal Access Token\n"
        "     from your profile page.\n"
        "  2. Accept the licence on the dataset page (tab Download, Terms of use).\n"
        f"  3. Create the file {Path.home() / '.cdsapirc'} with these two lines:\n"
        "        url: https://cds.climate.copernicus.eu/api\n"
        "        key: PASTE-YOUR-PERSONAL-ACCESS-TOKEN-HERE") from None

for s in sites.itertuples():
    last = min(s.last_year, date.today().year - 1)
    first = max(s.first_year, last - YEARS_BACK + 1, 1950)
    hourly_file = d / f"{s.site_id}_era5land_hourly.csv"
    if hourly_file.exists():
        say(s.site_id, ": already there, skipped")
        continue
    say(s.site_id, f": requesting {first}–{last} (can wait in the CDS queue for a few minutes)")
    target = d / f"{s.site_id}_era5land.zip"
    try:
        client.retrieve(
            "reanalysis-era5-land-timeseries",
            {
                "variable": VARIABLES,
                "location": {"longitude": round(s.lon, 3), "latitude": round(s.lat, 3)},
                "date": [f"{first}-01-01/{last}-12-31"],
                "data_format": "csv",
            },
            str(target),
        )
    except Exception as e:
        raise SystemExit(
            f"\n\nThe CDS refused or failed the request:\n  {e}\n"
            "401/403 = wrong token or licence not accepted on the dataset page.\n"
            "Otherwise the CDS may be busy: try again later. Finished towers are kept.") from None

    # The CDS sends a zip with one or more CSVs (or a single CSV): read and join them
    if zipfile.is_zipfile(target):
        with zipfile.ZipFile(target) as z:
            parts = [pd.read_csv(z.open(n)) for n in z.namelist() if n.lower().endswith(".csv")]
    else:
        parts = [pd.read_csv(target)]
    era = reduce(lambda a, b: a.merge(b, on=[c for c in a.columns if c in b.columns], how="outer"), parts)

    time_col = [c for c in era.columns if "time" in c.lower()][0]
    era["time"] = pd.to_datetime(era[time_col])
    for v in ["t2m", "stl1", "stl2", "stl3", "stl4", "skt", "d2m"]:   # Kelvin -> °C
        if v in era:
            era[f"{v}_C"] = era[v] - 273.15
    era["site_id"] = s.site_id
    era.to_csv(hourly_file, index=False)

    # Daily means of the state variables (temperature, soil water). UTC days!
    state = [c for c in ["t2m_C", "stl1_C", "swvl1", "swvl2", "swvl3", "swvl4", "sd"] if c in era]
    daily = era.set_index("time")[state].resample("D").mean().reset_index().rename(columns={"time": "date"})
    daily["site_id"] = s.site_id
    daily.to_csv(d / f"{s.site_id}_era5land_daily.csv", index=False)
    say(s.site_id, f": {len(era)} hours, columns: {', '.join(era.columns)}")

say(f"Done. Files in {d}\n    Check: is ERA5-Land t2m close to the tower's TA_F? Plot one year of both.")
