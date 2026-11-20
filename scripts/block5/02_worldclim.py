"""02_worldclim.py — long-term climate (1970–2000) at your five towers.

Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg

WorldClim 2.1: monthly normals 1970–2000 and 19 bioclimatic variables
(BIO1 = mean annual temperature in °C, BIO12 = annual precipitation in mm, ...).
No account needed.

Packages: pip install pandas rasterio requests
Output:   data/external/worldclim/worldclim_bio_my_sites.csv (+ monthly normals)
Cite:     Fick & Hijmans (2017) Int. J. Climatol. 37, 4302–4315, doi:10.1002/joc.5086

Run: python3 scripts/block5/02_worldclim.py --student 07
"""
import sys
import zipfile
from pathlib import Path

import pandas as pd
import rasterio
import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
from block5_sites import get_my_sites, out_dir, parse_args, say  # noqa: E402

RES = "5m"   # "10m" (~18 km), "5m" (~9 km), "2.5m" (~4.5 km), "30s" (~1 km, ~10 GB for bio)
BASE = "https://geodata.ucdavis.edu/climate/worldclim/2_1/base"

args = parse_args("WorldClim normals for your towers")
sites = get_my_sites(args.student, args.sites)
d = out_dir("worldclim")
xy = list(zip(sites["lon"], sites["lat"]))


def get_var(var):
    """Download and unzip wc2.1_<RES>_<var>.zip once; return the sorted GeoTIFF paths."""
    stem = f"wc2.1_{RES}_{var}"
    folder = d / stem
    if not folder.exists():
        zpath = d / f"{stem}.zip"
        say(f"Downloading {stem}.zip (once)")
        with requests.get(f"{BASE}/{stem}.zip", stream=True, timeout=120) as r:
            r.raise_for_status()
            with open(zpath, "wb") as f:
                for chunk in r.iter_content(1 << 20):
                    f.write(chunk)
        with zipfile.ZipFile(zpath) as z:
            z.extractall(folder)
        zpath.unlink()
    # natural sort: _1, _2, ..., _10 (not _1, _10, _11, ...)
    return sorted(folder.glob("*.tif"), key=lambda p: int(p.stem.split("_")[-1]))


def sample(tifs):
    """One column per GeoTIFF, one row per site (nearest cell; files are EPSG:4326)."""
    cols = {}
    for i, tif in enumerate(tifs, start=1):
        with rasterio.open(tif) as src:
            vals = [v[0] for v in src.sample(xy)]
            nodata = src.nodata
        cols[i] = [None if (nodata is not None and v == nodata) else float(v) for v in vals]
    return cols


# ---- Bioclimatic variables -----------------------------------------------------
bio = sample(get_var("bio"))
bio_df = sites[["site_id", "igbp", "lat", "lon"]].copy()
for i, vals in bio.items():
    bio_df[f"BIO{i}"] = vals
bio_df.to_csv(d / "worldclim_bio_my_sites.csv", index=False)
print(bio_df[["site_id", "igbp", "BIO1", "BIO12", "BIO4", "BIO15"]].to_string(index=False))

# ---- Monthly normals ----------------------------------------------------------
rows = []
tavg, prec = sample(get_var("tavg")), sample(get_var("prec"))
for k, site in enumerate(sites["site_id"]):
    for m in range(1, 13):
        rows.append({"site_id": site, "month": m, "tavg": tavg[m][k], "prec": prec[m][k]})
pd.DataFrame(rows).to_csv(d / "worldclim_monthly_normals_my_sites.csv", index=False)

say(f"Done. Files in {d}\n"
    "    BIO1 = mean annual temperature (°C), BIO12 = annual precipitation (mm),\n"
    "    BIO4 = temperature seasonality, BIO15 = precipitation seasonality.\n"
    "    Question: are your tower years warmer or wetter than the 1970–2000 normal?")
