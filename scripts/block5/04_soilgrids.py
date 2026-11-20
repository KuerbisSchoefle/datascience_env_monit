"""04_soilgrids.py — soil properties at your five towers.

Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg

SoilGrids 2.0 (ISRIC): machine-learning maps of soil properties at 250 m, six
depths from 0–5 cm to 100–200 cm, with uncertainty. We read the global maps
directly from the ISRIC file server (Cloud-optimised GeoTIFFs behind one .vrt
per property × depth), only the pixel under each tower. No account.
8 properties × 6 depths × (mean + uncertainty) = 96 maps, a few seconds each:
count 5–15 min. Set WITH_UNCERTAINTY = False to halve that.
(SoilGrids also has a REST API, rest.isric.org, but it is a beta service and often down.)

The maps store integers; dividing by d_factor gives conventional units:
clay/sand/silt %, soc g/kg, pH, bdod kg/dm3, nitrogen g/kg, cec cmol(c)/kg.
uncertainty = (Q95 - Q05) / median * 10 -> /10 -> ratio (higher = less certain).

Packages: pip install pandas rasterio pyproj
Output:   data/external/soilgrids/soilgrids_my_sites.csv (long: site × property × depth)
Cite:     Poggio et al. (2021) SOIL 7, 217–240, doi:10.5194/soil-7-217-2021

Run: python3 scripts/block5/04_soilgrids.py --student 07
"""
import sys
import time
from pathlib import Path

import pandas as pd
import rasterio
from pyproj import Transformer
from rasterio.errors import RasterioIOError

sys.path.insert(0, str(Path(__file__).resolve().parent))
from block5_sites import get_my_sites, out_dir, parse_args, say  # noqa: E402

PROPERTIES = ["clay", "sand", "silt", "soc", "phh2o", "bdod", "nitrogen", "cec"]
DEPTHS = ["0-5cm", "5-15cm", "15-30cm", "30-60cm", "60-100cm", "100-200cm"]
WITH_UNCERTAINTY = True
D_FACTOR = {"clay": 10, "sand": 10, "silt": 10, "soc": 10, "phh2o": 10, "bdod": 100,
            "nitrogen": 100, "cec": 10}
UNIT = {"clay": "%", "sand": "%", "silt": "%", "soc": "g/kg", "phh2o": "pH", "bdod": "kg/dm³",
        "nitrogen": "g/kg", "cec": "cmol(c)/kg"}
BASE = "https://files.isric.org/soilgrids/latest/data"

args = parse_args("SoilGrids at your towers")
sites = get_my_sites(args.student, args.sites)
d = out_dir("soilgrids")


def read_layer(prop, depth, stat, tries=3):
    """Values of one map at all towers; None if the server does not answer."""
    url = f"/vsicurl/{BASE}/{prop}/{prop}_{depth}_{stat}.vrt"
    for attempt in range(1, tries + 1):
        try:
            with rasterio.open(url) as src:
                to_map = Transformer.from_crs("EPSG:4326", src.crs, always_xy=True)
                xy = [to_map.transform(lon, lat) for lon, lat in zip(sites["lon"], sites["lat"])]
                return [None if v[0] in (-32768, 65535) else float(v[0])   # fill = no data
                        for v in src.sample(xy)]
        except RasterioIOError:
            time.sleep(10 * attempt)
    return None


stats = ["mean", "uncertainty"] if WITH_UNCERTAINTY else ["mean"]
say(f"Reading {len(PROPERTIES) * len(DEPTHS) * len(stats)} SoilGrids maps from files.isric.org (5–15 min)")
rows = []
with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR"):   # do not list the server folder
    for p in PROPERTIES:
        for dep in DEPTHS:
            v = [read_layer(p, dep, st) for st in stats]
            if any(x is None for x in v):
                raise SystemExit(
                    f"\n\nSoilGrids is not reachable right now ({BASE}/{p}).\n"
                    "This is the ISRIC server, not your script. Try again in 30 minutes;\n"
                    "maps that were already read are not kept, the script starts again.\n"
                    f"If it keeps failing, test it in the browser: {BASE}/")
            top, bottom = (int(x) for x in dep.removesuffix("cm").split("-"))
            for k, s in enumerate(sites.itertuples()):
                mean, unc = v[0][k], (v[1][k] if WITH_UNCERTAINTY else None)
                rows.append({
                    "site_id": s.site_id, "property": p, "depth": dep,
                    "top_cm": top, "bottom_cm": bottom,
                    "mean": None if mean is None else mean / D_FACTOR[p],
                    "uncertainty": None if unc is None else unc / 10,
                    "unit": UNIT[p],
                })
        say(f"{p}: done")

soil = pd.DataFrame(rows).sort_values(["site_id", "property", "top_cm"])
soil.to_csv(d / "soilgrids_my_sites.csv", index=False)

# Quick wide view of the topsoil (0–30 cm, thickness-weighted mean)
top = soil[soil["bottom_cm"] <= 30].dropna(subset=["mean"]).copy()
top["w"] = top["bottom_cm"] - top["top_cm"]
wide = (top.assign(wm=top["mean"] * top["w"]).groupby(["site_id", "property"])[["wm", "w"]].sum()
        .eval("wm / w").unstack("property").round(2))
say("Topsoil 0–30 cm (thickness-weighted):")
print(wide.to_string())
say(f"Done. File: {d / 'soilgrids_my_sites.csv'}\n"
    "    NA everywhere? The tower may sit on a pixel SoilGrids masks (water, urban, rock).\n"
    "    Report it; do not invent a value.")
