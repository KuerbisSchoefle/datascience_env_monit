"""09_merge.py — put the tower and the new data into two tidy tables.

Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg

  site_static.csv  one row per tower: climate normals, soil, traits, biodiversity
  site_daily.csv   one row per tower and day: FLUXNET daily fluxes + ERA5-Land
                   soil moisture + MODIS NDVI/EVI (interpolated to days) + Dheed flag
Join keys: site_id (static) and site_id + date (daily).
Run the download scripts first; whatever is missing is simply left out.

Packages: pip install pandas numpy
Output:   data/processed/site_static.csv, data/processed/site_daily.csv

Run: python3 scripts/block5/09_merge.py --student 07
"""
import re
import sys
import zipfile
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from block5_sites import get_my_sites, parse_args, say  # noqa: E402

args = parse_args("Merge tower and external data")
sites = get_my_sites(args.student, args.sites)
EXT = Path("data") / "external"
OUT = Path("data") / "processed"
OUT.mkdir(parents=True, exist_ok=True)


def read_if(path):
    return pd.read_csv(path) if Path(path).exists() else None


# ---- 1. Static table -----------------------------------------------------------
static = sites.copy()
wc = read_if(EXT / "worldclim" / "worldclim_bio_my_sites.csv")
if wc is not None:
    static = static.merge(wc[["site_id", "BIO1", "BIO4", "BIO12", "BIO15"]], on="site_id", how="left")
soil = read_if(EXT / "soilgrids" / "soilgrids_my_sites.csv")
if soil is not None:
    top = soil[soil["bottom_cm"] <= 30].dropna(subset=["mean"]).copy()
    top["w"] = top["bottom_cm"] - top["top_cm"]
    top["wm"] = top["mean"] * top["w"]
    g = top.groupby(["site_id", "property"])[["wm", "w"]].sum()
    wide = (g["wm"] / g["w"]).unstack("property").add_prefix("soil0_30_").reset_index()
    static = static.merge(wide, on="site_id", how="left")
tr = read_if(EXT / "planttraits" / "planttraits_my_sites.csv")
if tr is not None:
    static = static.merge(tr.drop(columns=["igbp", "lat", "lon"]), on="site_id", how="left")
inat = read_if(EXT / "inaturalist" / "inat_summary_my_sites.csv")
if inat is not None:
    static = static.merge(inat[["site_id", "n_obs", "n_species", "n_plant_species"]], on="site_id", how="left")
static.to_csv(OUT / "site_static.csv", index=False)
say(f"site_static.csv: {len(static)} towers x {static.shape[1]} columns")

# ---- 2. Daily table ------------------------------------------------------------
KEEP = ["TIMESTAMP", "TA_F", "SW_IN_F", "VPD_F", "P_F", "LE_F_MDS",
        "NEE_VUT_REF", "GPP_NT_VUT_REF", "RECO_NT_VUT_REF", "NEE_VUT_REF_QC"]
parts = []
for zf in sorted(Path("data/raw").glob("*FLUXNET*.zip")):
    site = re.match(r"^[A-Z]+_([A-Z]{2}-[A-Za-z0-9]{3})_", zf.name)
    if not site or site.group(1) not in set(sites["site_id"]):
        continue
    with zipfile.ZipFile(zf) as z:
        dd = [n for n in z.namelist() if "FLUXMET_DD" in n]
        if not dd:
            continue
        df = pd.read_csv(z.open(dd[0]), na_values=[-9999], usecols=lambda c: c in KEEP,
                         dtype={"TIMESTAMP": str})
    df["date"] = pd.to_datetime(df.pop("TIMESTAMP"), format="%Y%m%d")
    df["site_id"] = site.group(1)
    parts.append(df)
if not parts:
    raise SystemExit("No FLUXMET_DD files found in data/raw (Block 4 zips).")
daily = pd.concat(parts)

era_files = sorted((EXT / "era5land").glob("*_era5land_daily.csv"))
if era_files:
    era = pd.concat(pd.read_csv(f, parse_dates=["date"]) for f in era_files)
    era = era.rename(columns={c: f"era5l_{c}" for c in era.columns if c not in ("site_id", "date")})
    daily = daily.merge(era, on=["site_id", "date"], how="left")

vi = read_if(EXT / "modis" / "modis_vi_my_sites.csv")
if vi is not None:
    vi["date"] = pd.to_datetime(vi["date"])
    vi_daily = (vi.set_index("date").groupby("site_id")[["ndvi", "evi"]]
                  .apply(lambda g: g.resample("D").mean().interpolate("time"))
                  .reset_index())
    daily = daily.merge(vi_daily, on=["site_id", "date"], how="left")

dh = read_if(EXT / "dheed" / "dheed_daily_flags_my_sites.csv")
if dh is not None:
    dh["date"] = pd.to_datetime(dh["date"])
    daily = daily.merge(dh[["site_id", "date", "dheed_event", "dheed_label"]], on=["site_id", "date"], how="left")
    daily["dheed_event"] = daily["dheed_event"].fillna(False).astype(bool)

daily.to_csv(OUT / "site_daily.csv", index=False)
say(f"site_daily.csv: {len(daily)} tower-days x {daily.shape[1]} columns\n"
    "    Units: GPP/NEE/RECO in the DD files are g C m-2 d-1; LE in W m-2; era5l_swvl in m3 m-3.")
