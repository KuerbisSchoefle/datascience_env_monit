"""07_inaturalist.py — citizen-science species observations around your towers.

Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg

iNaturalist public API (no account): all research-grade observations within
RADIUS_KM of each tower. The API allows ~1 request per second; we wait 1 s.
Keep in mind: observations cluster where people are (absence of a record is not
absence of a species); every observation has its own licence; for a paper,
download the same records via GBIF to get a citable DOI.

Packages: pip install pandas requests
Output:   data/external/inaturalist/<SITE>_inat.csv and inat_summary_my_sites.csv
Cite:     iNaturalist contributors, iNaturalist (<year>), https://www.inaturalist.org,
          accessed <date> — or the GBIF download DOI.

Run: python3 scripts/block5/07_inaturalist.py --student 07
"""
import sys
import time
from pathlib import Path

import pandas as pd
import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
from block5_sites import get_my_sites, out_dir, parse_args, say  # noqa: E402

RADIUS_KM = 5
MAX_OBS = 3000          # per tower, to keep it quick
ICONIC_TAXA = None      # e.g. "Plantae" or "Aves,Insecta"; None = all groups
URL = "https://api.inaturalist.org/v1/observations"
HEADERS = {"User-Agent": "EnvMon course, University of Freiburg"}

args = parse_args("iNaturalist observations around your towers")
sites = get_my_sites(args.student, args.sites)
d = out_dir("inaturalist")


def get_page(s, id_above, tries=4):
    params = {"lat": s.lat, "lng": s.lon, "radius": RADIUS_KM, "quality_grade": "research",
              "per_page": 200, "order_by": "id", "order": "asc", "id_above": id_above}
    if ICONIC_TAXA:
        params["iconic_taxa"] = ICONIC_TAXA
    for attempt in range(1, tries + 1):
        r = requests.get(URL, params=params, headers=HEADERS, timeout=60)
        if r.status_code in (429, 500, 502, 503) and attempt < tries:
            time.sleep(10 * attempt)
            continue
        r.raise_for_status()
        return r.json()


summary = []
for s in sites.itertuples():
    say(f"{s.site_id}: observations within {RADIUS_KM} km")
    recs, id_above = [], 0
    while True:
        js = get_page(s, id_above)
        res = js["results"]
        if not res:
            break
        for o in res:
            tx = o.get("taxon") or {}
            xy = (o.get("geojson") or {}).get("coordinates") or [None, None]
            recs.append({
                "site_id": s.site_id, "id": o["id"], "observed_on": o.get("observed_on"),
                "lon": xy[0], "lat": xy[1], "accuracy_m": o.get("positional_accuracy"),
                "taxon": tx.get("name"), "rank": tx.get("rank"),
                "iconic_taxon": tx.get("iconic_taxon_name"),
                "common_name": tx.get("preferred_common_name"),
                "license": o.get("license_code"), "url": o.get("uri"),
            })
        id_above = res[-1]["id"]
        print(f"    {len(recs)} of {js['total_results']}")
        if len(recs) >= MAX_OBS or len(res) < 200:
            break
        time.sleep(1)
    if not recs:
        say(f"{s.site_id}: no research-grade observations")
        continue
    obs = pd.DataFrame(recs)
    obs.to_csv(d / f"{s.site_id}_inat.csv", index=False)
    sp = obs[obs["rank"] == "species"]
    summary.append({
        "site_id": s.site_id, "n_obs": len(obs), "n_species": sp["taxon"].nunique(),
        "n_plant_species": sp.loc[sp["iconic_taxon"] == "Plantae", "taxon"].nunique(),
        "first": obs["observed_on"].min(), "last": obs["observed_on"].max(),
    })
    time.sleep(1)

summ = pd.DataFrame(summary)
summ.to_csv(d / "inat_summary_my_sites.csv", index=False)
print(summ.to_string(index=False))
say(f"Done. Files in {d}\n    Compare n_species between towers with care: more observers ≠ more species.")
