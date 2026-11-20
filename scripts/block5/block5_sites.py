"""block5_sites.py — your five towers, shared by all Block 5 scripts.

Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg

Every Block 5 Python script imports this file. Set your student number ONCE
here, or pass it on the command line:
    python3 scripts/block5/04_soilgrids.py --student 07
Run all scripts from your project folder (the one with data/ and scripts/).
"""
import argparse
from pathlib import Path

import pandas as pd

# ---- Your settings -----------------------------------------------------------
MY_STUDENT = "07"          # your student number from tower_sets_block4.csv
MY_SITES = None            # or pick sites yourself, e.g. ["DE-Hai", "FR-Hes"]
TOWER_CSV = "tower_sets_block4.csv"   # from ILIAS (folder DATA), same file as Block 4


def parse_args(description=""):
    p = argparse.ArgumentParser(description=description)
    p.add_argument("--student", default=MY_STUDENT, help="student number, e.g. 07")
    p.add_argument("--sites", nargs="*", default=MY_SITES, help="site IDs instead of a student number")
    return p.parse_args()


def get_my_sites(student=MY_STUDENT, sites=MY_SITES, tower_csv=TOWER_CSV):
    if not Path(tower_csv).exists():
        raise SystemExit(f"{tower_csv} not found in {Path.cwd()}.\n"
                         "Download it from ILIAS (folder DATA) into your project folder.")
    towers = pd.read_csv(tower_csv, dtype=str)
    if sites:
        mine = towers[towers["site_id"].isin(sites)]
        missing = set(sites) - set(mine["site_id"])
        if missing:
            raise SystemExit(f"Not in {tower_csv}: {', '.join(sorted(missing))}")
    else:
        number = f"{int(student):02d}"
        mine = towers[towers["student_no"].astype(int).map(lambda n: f"{n:02d}") == number]
    if mine.empty:
        raise SystemExit(f"No towers found for student {student}")
    keep = ["site_id", "site_name", "country", "continent", "igbp", "lat", "lon",
            "first_year", "last_year"]
    mine = mine.drop_duplicates("site_id")[keep].reset_index(drop=True)
    mine[["lat", "lon"]] = mine[["lat", "lon"]].astype(float)
    mine[["first_year", "last_year"]] = mine[["first_year", "last_year"]].astype(int)
    print("\n==> Your towers:")
    print(mine[["site_id", "igbp", "country", "lat", "lon", "first_year", "last_year"]]
          .to_string(index=False))
    return mine


def out_dir(name):
    """Folder for one dataset: data/external/<name> (data/ is in your .gitignore)."""
    d = Path("data") / "external" / name
    d.mkdir(parents=True, exist_ok=True)
    return d


def say(*args):
    print("\n==> " + "".join(str(a) for a in args), flush=True)
