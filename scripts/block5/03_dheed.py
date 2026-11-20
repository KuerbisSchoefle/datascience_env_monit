"""03_dheed.py — compound dry-and-hot extreme events that reached your towers.

Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg

Dheed: global database of connected compound dry and hot extreme events from
ERA5, 0.25°, daily, 1950–2023 (Weynants et al. 2025, ESSD). Hot = daily Tmax in
the top 1 % for that grid cell; dry = 30/90/180-day water balance in the bottom 1 %.
Hot + dry cells connected in space and time (≥ 3 days) form one labelled event.

Two files from Zenodo (downloaded once):
  LabelCube  (37 MB, Zarr): for every day and 0.25° cell, the label of the event
             there (empty = no event). We read the ONE cell that contains your tower.
  EventStats (14 MB, CSV):  one row per event, with statistics of the WHOLE event
             (its total duration, area, intensity, ...). We add them by label.

Why not just use the bounding boxes in EventStats? A box is a rectangle around an
irregular event, so "tower inside the box" does not mean the event reached the
tower. Worse: Dheed longitudes run 0–360°, and an event that crosses 0° (western
Europe, West Africa) gets the box 0–359.75°, which contains every tower on Earth.

Output: data/external/dheed/dheed_events_my_sites.csv
            one row per event that reached a tower: days AT THE TOWER + whole-event stats
        data/external/dheed/dheed_daily_flags_my_sites.csv
            one row per tower-day inside an event (for 09_merge)
Cite:   Weynants et al. (2025) ESSD 17, 6621, doi:10.5194/essd-17-6621-2025
        data: doi:10.5281/zenodo.14884254

Run: python3 scripts/block5/03_dheed.py --student 07
"""
import sys
import zipfile
from pathlib import Path

import pandas as pd
import requests
import xarray as xr
import zarr

sys.path.insert(0, str(Path(__file__).resolve().parent))
from block5_sites import get_my_sites, out_dir, parse_args, say  # noqa: E402

RECORD = "https://zenodo.org/records/14884254/files"
STATS = "MergedEventStats_landonly_int.csv.zip"
CUBE = "mergedlabels_ranked_pot0.01_ne0.1_cmp_S1_T3_1950_2023.zarr"
DHEED_LAST_YEAR = 2023

args = parse_args("Dheed events at your towers")
sites = get_my_sites(args.student, args.sites)
d = out_dir("dheed")


def download(name, size):
    path = d / name
    if not path.exists():
        say(f"Downloading {name} ({size}, once)")
        part = path.with_suffix(path.suffix + ".part")
        with requests.get(f"{RECORD}/{name}?download=1", stream=True, timeout=300) as r:
            r.raise_for_status()
            with open(part, "wb") as f:
                for chunk in r.iter_content(1 << 20):
                    f.write(chunk)
        part.rename(path)   # only a complete download gets the real name
    return path


# ---- 1. The label at the tower's grid cell, day by day ------------------------
store = zarr.storage.ZipStore(str(download(CUBE + ".zip", "37 MB")), mode="r")
cube = xr.open_zarr(store, group=CUBE, consolidated=False)   # dims: Ti, latitude, longitude
say(f"LabelCube: {cube.sizes['Ti']} days × {cube.sizes['latitude']} × {cube.sizes['longitude']} cells")

flags = []
for s in sites.itertuples():
    last = min(s.last_year, DHEED_LAST_YEAR)
    if s.first_year > DHEED_LAST_YEAR:
        say(f"{s.site_id}: tower starts {s.first_year}, Dheed ends {DHEED_LAST_YEAR}. Skipped.")
        continue
    cell = cube["labels"].sel(latitude=s.lat, longitude=s.lon % 360, method="nearest")
    cell = cell.sel(Ti=slice(f"{s.first_year}-01-01", f"{last}-12-31")).to_series()
    hit = cell.dropna()        # empty days are NaN (the Zarr fill value)
    hit = hit[hit > 0]
    say(f"{s.site_id}: {len(hit)} event days at the tower in {s.first_year}–{last}"
        f" ({hit.nunique()} events)"
        + (f". Note: Dheed ends {DHEED_LAST_YEAR}, the tower runs to {s.last_year}"
           if s.last_year > DHEED_LAST_YEAR else ""))
    flags.append(pd.DataFrame({"site_id": s.site_id, "date": hit.index.date,
                               "dheed_event": True, "dheed_label": hit.values.astype("int64")}))

daily = pd.concat(flags) if flags else pd.DataFrame(
    columns=["site_id", "date", "dheed_event", "dheed_label"])

# ---- 2. Whole-event statistics from EventStats, joined by label ---------------
with zipfile.ZipFile(download(STATS, "14 MB")) as z:
    name = [n for n in z.namelist() if n.endswith(".csv")][0]
    ev = pd.read_csv(z.open(name))

at_tower = (daily.groupby(["site_id", "dheed_label"])
            .agg(first_day_at_tower=("date", "min"), last_day_at_tower=("date", "max"),
                 days_at_tower=("date", "size"))
            .reset_index()
            .rename(columns={"dheed_label": "label"}))
events = (at_tower.merge(ev, on="label", how="left")
          .sort_values(["site_id", "first_day_at_tower"]))

events.to_csv(d / "dheed_events_my_sites.csv", index=False)
daily.to_csv(d / "dheed_daily_flags_my_sites.csv", index=False)

if not events.empty:
    show = ["site_id", "label", "first_day_at_tower", "days_at_tower", "start_time", "end_time",
            "duration", "area"]
    print("\n(days_at_tower = at your tower; start/end/duration/area = the whole event)")
    print(events[[c for c in show if c in events]].to_string(index=False))

say(f"Done. Files in {d}\n    Idea: compare NEE and GPP during an event with the same days in other years.")
