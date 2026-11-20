"""08_modis_ndvi_evi.py — compute NDVI and EVI at your towers from MODIS reflectance.

Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg

MODIS Terra MOD13Q1 (Collection 6.1): 250 m, one composite every 16 days, from
February 2000. We download red, NIR and blue surface reflectance, compute

    NDVI = (NIR - Red) / (NIR + Red)
    EVI  = 2.5 * (NIR - Red) / (NIR + 6*Red - 7.5*Blue + 1)

ourselves. With COMPARE_OFFICIAL = True we also download the official NDVI/EVI
bands and compare (50 % more download time).

Source: ORNL DAAC MODIS/VIIRS subset web service (no account), REST API.
Window: 9 x 9 pixels (~2 x 2 km) around each tower; we keep pixel_reliability 0
(good) and 1 (marginal); 2 = snow/ice, 3 = cloudy. The service sends at most
10 dates of ONE band per request, and each request can take 5–40 s when the
service is busy: count 5–20 min per tower for 3 years. "Retrying" after an
error 502 is the busy server; the script retries by itself. A tower that
finished is saved; run the script again and it continues with the next.

Packages: pip install pandas numpy requests
Output:   data/external/modis/<SITE>_mod13q1_pixels.csv  (every pixel, every date)
          data/external/modis/modis_vi_my_sites.csv       (site mean per date)
Cite:     Didan (2021) MOD13Q1 V061, NASA LP DAAC, doi:10.5067/MODIS/MOD13Q1.061
          + ORNL DAAC (2018) MODIS Land Product Subsets Web Service, doi:10.3334/ORNLDAAC/1557

Run: python3 scripts/block5/08_modis_ndvi_evi.py --student 07
"""
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
from block5_sites import get_my_sites, out_dir, parse_args, say  # noqa: E402

YEARS_BACK = 3   # last N years of each tower record; more years = longer download
KM = 1     # km left/right and above/below -> 9 x 9 pixels at 250 m
COMPARE_OFFICIAL = False   # True: also download MODIS's own NDVI and EVI to compare
API = "https://modis.ornl.gov/rst/api/v1/MOD13Q1"
HEADERS = {"Accept": "application/json", "User-Agent": "EnvMon course, University of Freiburg"}
BANDS = {
    "250m_16_days_red_reflectance": "red",
    "250m_16_days_NIR_reflectance": "nir",
    "250m_16_days_blue_reflectance": "blue",
    "250m_16_days_pixel_reliability": "reliability",
}
OFFICIAL = {"250m_16_days_NDVI": "ndvi_modis", "250m_16_days_EVI": "evi_modis"}
DOWNLOAD = list(BANDS) + (list(OFFICIAL) if COMPARE_OFFICIAL else [])
BANDS |= OFFICIAL   # names for reading pixel files, whichever bands they contain

args = parse_args("MODIS NDVI and EVI at your towers")
sites = get_my_sites(args.student, args.sites)
d = out_dir("modis")


def get_json(url, params, tries=6):
    for attempt in range(1, tries + 1):
        try:
            r = requests.get(url, params=params, headers=HEADERS, timeout=120)
            if r.status_code == 200:
                return r.json()
            problem = f"error {r.status_code}"
        except requests.RequestException as e:
            problem = type(e).__name__
        if attempt < tries:
            print(f"\n    {problem} (service busy). Retrying in {10 * attempt} s ...", flush=True)
            time.sleep(10 * attempt)
    raise SystemExit(
        "\n\nThe MODIS service (modis.ornl.gov) is not answering right now (error 502 =\n"
        "server busy or down). This is the NASA server, not your script.\n"
        f"Towers that finished are saved in {d}; run the script again later and it\n"
        "continues with the next tower. Check the service in the browser:\n"
        "https://modis.ornl.gov/rst/api/v1/products")


def download_site(s, first, last):
    loc = {"latitude": s.lat, "longitude": s.lon}
    dates = get_json(f"{API}/dates", loc)["dates"]
    dates = [x for x in dates if f"{first}-01-01" <= x["calendar_date"] <= f"{last}-12-31"]
    chunks = [dates[i:i + 10] for i in range(0, len(dates), 10)]
    rows = []
    for band in DOWNLOAD:
        for k, ch in enumerate(chunks, start=1):
            js = get_json(f"{API}/subset", {**loc, "band": band,
                                            "startDate": ch[0]["modis_date"], "endDate": ch[-1]["modis_date"],
                                            "kmAboveBelow": KM, "kmLeftRight": KM})
            for sub in js["subset"]:
                for pixel, value in enumerate(sub["data"]):
                    rows.append({"date": sub["calendar_date"], "band": band, "pixel": pixel, "value": value})
            print(f"    {BANDS[band]:12s} {k}/{len(chunks)}", end="\r", flush=True)
        print()
    return pd.DataFrame(rows)


all_sites = []
for s in sites.itertuples():
    first = max(s.first_year, s.last_year - YEARS_BACK + 1, 2000)
    pix_file = d / f"{s.site_id}_mod13q1_pixels.csv"
    if pix_file.exists():
        say(f"{s.site_id}: already downloaded, reading {pix_file}")
        raw = pd.read_csv(pix_file)
    else:
        say(f"{s.site_id}: downloading {len(DOWNLOAD)} MOD13Q1 bands, {first}–{s.last_year} (5–20 min)")
        raw = download_site(s, first, s.last_year)
        raw.to_csv(pix_file, index=False)

    px = (raw.assign(band=raw["band"].map(BANDS))
             .pivot_table(index=["date", "pixel"], columns="band", values="value")
             .reset_index())
    for c in [c for c in ["red", "nir", "blue", "ndvi_modis", "evi_modis"] if c in px]:
        px[c] = np.where(px[c] <= -1000, np.nan, px[c] * 0.0001)   # fill -1000/-3000; scale 0.0001
    px["ndvi"] = (px["nir"] - px["red"]) / (px["nir"] + px["red"])
    px["evi"] = 2.5 * (px["nir"] - px["red"]) / (px["nir"] + 6 * px["red"] - 7.5 * px["blue"] + 1)
    px = px[px["reliability"].isin([0, 1])]

    has_official = {"ndvi_modis", "evi_modis"} <= set(px.columns)
    agg = dict(n_good_pixels=("ndvi", "size"), ndvi=("ndvi", "mean"), evi=("evi", "mean"))
    if has_official:
        agg |= dict(ndvi_modis=("ndvi_modis", "mean"), evi_modis=("evi_modis", "mean"))
    ts = px.groupby("date").agg(**agg).reset_index()
    ts.insert(0, "site_id", s.site_id)
    all_sites.append(ts)
    say(f"{s.site_id}: {len(ts)} dates"
        + (f"; r(own NDVI, MODIS NDVI) = {ts['ndvi'].corr(ts['ndvi_modis']):.3f}" if has_official else ""))

vi = pd.concat(all_sites)
vi.to_csv(d / "modis_vi_my_sites.csv", index=False)
say(f"Done. File: {d / 'modis_vi_my_sites.csv'}\n"
    + ("    Your NDVI should match the MODIS NDVI almost exactly. Does your EVI? Why (not)?\n"
       if COMPARE_OFFICIAL else "")
    + "    Next: plot EVI and the tower's GPP on one time axis.")
