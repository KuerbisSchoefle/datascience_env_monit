"""06_deadtrees.py — tree cover and standing deadwood around your towers (deadtrees.earth).

Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg

deadtrees.earth (made in our chair):
  1. Drone/aerial orthophotos with dead-tree labels, worldwide — browse and
     download by hand: https://deadtrees.earth/dataset
  2. Yearly 10 m satellite maps of tree cover and standing deadwood cover for
     EUROPE, 2017–2025, cloud-optimised GeoTIFFs in EPSG:3035, version 5 (Oct 2026).
     Band 1: cover, 0–255 = 0–100 %. Band 2: 0 = no data, 255 = data. Band 1 is
     also 0 where there is no data, so we use band 2 as the mask.
This script uses (2): a small box around each European tower, every year.
Towers outside Europe are skipped.

Packages: pip install pandas numpy rasterio pyproj
Output:   data/external/deadtrees/deadtrees_my_sites.csv (site × year)
          data/external/deadtrees/clips/<SITE>_<layer>_<year>.tif
Cite:     Mosig et al. (2026) Remote Sens. Environ. 332, 115027, doi:10.1016/j.rse.2025.115027

Run: python3 scripts/block5/06_deadtrees.py --student 07
"""
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import rasterio
from pyproj import Transformer
from rasterio.errors import RasterioIOError
from rasterio.windows import from_bounds

sys.path.insert(0, str(Path(__file__).resolve().parent))
from block5_sites import get_my_sites, out_dir, parse_args, say  # noqa: E402

YEARS = range(2017, 2026)
HALF_BOX_M = 1000    # 2 km × 2 km box around the tower
FOREST_MIN = 0.20    # forest pixel: tree cover > 20 %
DEAD_MIN = 0.30      # mortality pixel: standing deadwood cover > 30 % (within forest)
BASE = "https://data.rsc4earth.de/download/deadtrees.earth_maps/v5_europe_composite_epsg_3035"

args = parse_args("deadtrees.earth maps around your towers")
sites = get_my_sites(args.student, args.sites)
d = out_dir("deadtrees")
clips = d / "clips"
clips.mkdir(exist_ok=True)

eu = sites[sites["continent"] == "Europe"]
if eu.empty:
    raise SystemExit("None of your towers is in Europe. Use the drone data browser: "
                     "https://deadtrees.earth/dataset")
skipped = sorted(set(sites["site_id"]) - set(eu["site_id"]))
if skipped:
    say(f"Skipped (outside Europe): {', '.join(skipped)}")

to_laea = Transformer.from_crs("EPSG:4326", "EPSG:3035", always_xy=True)


def load_box(layer, year, bounds, out_path):
    """Read only the box from the remote COG, save it, return values as fraction 0–1."""
    try:
        with rasterio.open(f"/vsicurl/{BASE}/{layer}_{year}.tif") as src:
            win = from_bounds(*bounds, transform=src.transform)
            cover = src.read(1, window=win).astype("float64") / 255.0   # 0–255 -> fraction 0–1
            no_data = src.read(2, window=win) == 0                      # band 2 = 0: no data
            arr = np.ma.masked_array(cover, mask=no_data)
            profile = src.profile | {"count": 1, "height": arr.shape[0], "width": arr.shape[1],
                                     "transform": src.window_transform(win), "dtype": "float64",
                                     "nodata": np.nan, "driver": "GTiff"}
            pix_ha = abs(src.res[0] * src.res[1]) / 1e4
    except RasterioIOError:
        return None, None
    profile.pop("blockxsize", None), profile.pop("blockysize", None), profile.pop("tiled", None)
    with rasterio.open(out_path, "w", **profile) as dst:
        dst.write(arr.filled(np.nan), 1)
    return arr, pix_ha


rows = []
with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR", GDAL_HTTP_MAX_RETRY="3"):
    for s in eu.itertuples():
        x, y = to_laea.transform(s.lon, s.lat)
        bounds = (x - HALF_BOX_M, y - HALF_BOX_M, x + HALF_BOX_M, y + HALF_BOX_M)
        for yr in YEARS:
            tc, pix_ha = load_box("tree_cover", yr, bounds, clips / f"{s.site_id}_tree_cover_{yr}.tif")
            dw, _ = load_box("standing_deadwood_cover", yr, bounds, clips / f"{s.site_id}_deadwood_{yr}.tif")
            if tc is None or dw is None:
                say(f"{s.site_id} {yr}: not available")
                continue
            forest = tc > FOREST_MIN
            rows.append({
                "site_id": s.site_id, "year": yr,
                "tree_cover_pct": 100 * float(tc.mean()),
                "deadwood_pct": 100 * float(dw.mean()),
                "forest_ha": float(forest.sum()) * pix_ha,
                "mortality_ha": float((forest & (dw > DEAD_MIN)).sum()) * pix_ha,
            })
            say(f"{s.site_id} {yr}: done")

res = pd.DataFrame(rows)
res.to_csv(d / "deadtrees_my_sites.csv", index=False)
print(res.round(2).to_string(index=False))
say(f"Done. Files in {d}\n"
    "    A grassland or cropland tower has little tree cover: that is a result, not an error.")
