"""05_planttraits.py — plant functional traits at your five towers (planttraits.earth).

Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg

Global 1 km maps of 31 plant traits (Lusk et al. 2026, Nat. Commun.), made in our
chair from ~40 million citizen-science plant observations (GBIF) + sPlot + TRY +
Earth observation. Values are community-weighted means (CWM).

Each GeoTIFF has 3 bands: 1 = trait, 2 = coefficient of variation (uncertainty),
3 = area of applicability. Projection EPSG:6933. Files are ~0.5–0.7 GB each, so we
read only the pixels we need over HTTP (GDAL /vsicurl/). If that is slow or fails,
download the file in the browser and set LOCAL_DIR.

Packages: pip install pandas rasterio pyproj
Output:   data/external/planttraits/planttraits_my_sites.csv
Cite:     Lusk et al. (2026) Nat. Commun. 17, 1203, doi:10.1038/s41467-026-68996-y
          data: doi:10.5281/zenodo.14646322

Run: python3 scripts/block5/05_planttraits.py --student 07
"""
import sys
from pathlib import Path

import pandas as pd
import rasterio
from pyproj import Transformer

sys.path.insert(0, str(Path(__file__).resolve().parent))
from block5_sites import get_my_sites, out_dir, parse_args, say  # noqa: E402

# TRY trait ID: (short name, unit). * = experimental map (cross-validated r < 0.5)
TRAITS = {
    3117: ("SLA", "m2 kg-1"),
    14: ("leaf_N_mass", "mg g-1"),
    50: ("leaf_N_area", "g m-2"),
    4: ("stem_density", "g cm-3"),
    6: ("rooting_depth", "m"),
    3113: ("leaf_area", "mm2"),
    3106: ("plant_height", "m"),   # * stored in coarse ~0.9 m steps: low vegetation reads 0.68 m
}
LOCAL_DIR = None   # e.g. "data/external/planttraits/tif" if you downloaded the files
BASE = "https://zenodo.org/records/14646322/files"

args = parse_args("Plant trait maps at your towers")
sites = get_my_sites(args.student, args.sites)
d = out_dir("planttraits")
out = sites[["site_id", "igbp", "lat", "lon"]].copy()

env = {"GDAL_DISABLE_READDIR_ON_OPEN": "EMPTY_DIR", "GDAL_HTTP_MAX_RETRY": "3",
       "GDAL_HTTP_RETRY_DELAY": "5"}
with rasterio.Env(**env):
    for tid, (name, unit) in TRAITS.items():
        f = f"X{tid}_mean_Shrub_Tree_Grass_1km.tif"
        src_path = f"/vsicurl/{BASE}/{f}" if LOCAL_DIR is None else str(Path(LOCAL_DIR) / f)
        say(f"{name} (TRY {tid})")
        with rasterio.open(src_path) as src:
            to_map = Transformer.from_crs("EPSG:4326", src.crs, always_xy=True)
            xy = [to_map.transform(lon, lat) for lon, lat in zip(sites["lon"], sites["lat"])]
            vals = list(src.sample(xy, indexes=[1, 2, 3]))
            nodata, scales, offsets = src.nodata, src.scales, src.offsets
        # The files store integers: real value = stored * scale + offset (per band)
        clean = [[None if (nodata is not None and x == nodata) else float(x) * sc + of
                  for x, sc, of in zip(v, scales, offsets)] for v in vals]
        out[name] = [v[0] for v in clean]
        out[f"{name}_cov"] = [v[1] for v in clean]
        out[f"{name}_aoa"] = [v[2] for v in clean]

out.to_csv(d / "planttraits_my_sites.csv", index=False)
pd.DataFrame([(k, n, u) for k, (n, u) in TRAITS.items()], columns=["try_id", "name", "unit"]) \
    .to_csv(d / "planttraits_units.csv", index=False)
print(out[["site_id", "igbp", "SLA", "leaf_N_mass", "stem_density", "rooting_depth"]].to_string(index=False))
say(f"Done. File: {d / 'planttraits_my_sites.csv'}\n"
    "    Read the _aoa column before you trust a value: outside the area of applicability\n"
    "    the model extrapolates.")
