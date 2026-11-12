#!/usr/bin/env python3
"""
get_my_towers.py — download your five FLUXNET towers with the FLUXNET Shuttle
Environmental Monitoring and Data Analysis · Block 4 · University of Freiburg

What it does
  1. Installs the FLUXNET Shuttle into the Python you run this script with (if it is missing).
  2. Reads your five site IDs from tower_sets_block4.csv (ILIAS), or takes them from --sites.
  3. Makes a snapshot of all available FLUXNET data  -> data/snapshots/
  4. Downloads your five zip files                   -> data/raw/
  5. Checks each zip and writes data/raw/CITATIONS.txt with the citation of every site.

How to run it (from your project folder, the one with scripts/ and data/)
  macOS / Linux:  python3 get_my_towers.py --student 07
  Windows:        py get_my_towers.py --student 07
  Own site list:  python3 get_my_towers.py --sites DE-Hai FR-Hes AU-How US-Kon CN-Dsh

Needs: Python 3.9 or newer, Git (for installing the Shuttle), internet, ~2–3 GB of free disk space.
Tip: use the virtual environment from Block 1 (.venv) so the Shuttle is installed there.
"""

import argparse
import csv
import subprocess
import sys
import zipfile
from pathlib import Path

SHUTTLE_SOURCE = "git+https://github.com/fluxnet/shuttle.git"
DEFAULT_CSV = "tower_sets_block4.csv"
SNAP_DIR = Path("data/snapshots")
RAW_DIR = Path("data/raw")


def say(msg):
    print(f"\n==> {msg}", flush=True)


def stop(msg):
    print(f"\nERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def ensure_shuttle():
    """Install the FLUXNET Shuttle into this Python if it is not there yet."""
    if sys.version_info < (3, 9):
        stop(f"Python 3.9 or newer is needed, you have {sys.version.split()[0]}.")
    try:
        import fluxnet_shuttle  # noqa: F401
        say("FLUXNET Shuttle is already installed.")
        return
    except ImportError:
        pass
    say("Installing the FLUXNET Shuttle (one time, takes a minute) ...")
    cmd = [sys.executable, "-m", "pip", "install", SHUTTLE_SOURCE]
    result = subprocess.run(cmd)
    if result.returncode != 0:
        stop("Installing the Shuttle failed.\n"
             "  - Is Git installed? (git --version)\n"
             "  - On a system Python you may need a virtual environment first:\n"
             "      python3 -m venv .venv  then  source .venv/bin/activate  (Windows: .venv\\Scripts\\Activate.ps1)")


def shuttle(*args):
    """Run a fluxnet-shuttle command with the same Python."""
    cmd = [sys.executable, "-m", "fluxnet_shuttle.main", "--no-logfile", *args]
    return subprocess.run(cmd).returncode


def sites_for_student(csv_path, student):
    path = Path(csv_path)
    if not path.exists():
        stop(f"{csv_path} not found. Download it from ILIAS (folder DATA) into this folder,\n"
             f"or give your sites directly with --sites.")
    number = f"{int(student):02d}"
    with path.open(encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f) if r["student_no"].zfill(2) == number]
    if not rows:
        stop(f"No towers found for student number {number} in {csv_path}.")
    name = rows[0].get("student_name", "")
    say(f"Tower set {number} {('(' + name + ')') if name else ''}:")
    for r in rows:
        print(f"    {r['site_id']:8s} {r['igbp']:4s} {r['country']}  {r['site_name']}  ({r['first_year']}–{r['last_year']})")
    return [r["site_id"] for r in rows]


def newest_snapshot():
    """Newest snapshot that actually lists sites (a failed run can leave an empty one)."""
    for snap in sorted(SNAP_DIR.glob("fluxnet_shuttle_snapshot_*.csv"), reverse=True):
        with snap.open(encoding="utf-8") as f:
            if sum(1 for _ in f) > 1:
                return snap
    return None


def read_snapshot(snapshot):
    with snapshot.open(encoding="utf-8") as f:
        return {r["site_id"]: r for r in csv.DictReader(f)}


def check_zips(sites, snapshot_rows):
    say("Checking the downloaded files ...")
    ok = True
    citations = []
    for site in sites:
        zips = sorted(RAW_DIR.glob(f"*_{site}_FLUXNET_*.zip"))
        if not zips:
            print(f"    {site:8s} MISSING — run the script again, or ask for help on ILIAS")
            ok = False
            continue
        z = zips[-1]
        try:
            with zipfile.ZipFile(z) as zf:
                hh = [n for n in zf.namelist() if "FLUXMET_HH" in n]
                bad = zf.testzip()
        except zipfile.BadZipFile:
            print(f"    {site:8s} BROKEN ZIP — delete {z.name} and run the script again")
            ok = False
            continue
        size_mb = z.stat().st_size / 1e6
        status = "ok" if hh and bad is None else "check: no FLUXMET_HH file inside" if not hh else f"check: damaged member {bad}"
        print(f"    {site:8s} {z.name}  ({size_mb:.0f} MB)  {status}")
        row = snapshot_rows.get(site, {})
        citations.append(f"{site}: {row.get('product_citation', 'citation not found in snapshot')}")
    cit_file = RAW_DIR / "CITATIONS.txt"
    cit_file.write_text(
        "Data citations for my towers (from the FLUXNET Shuttle snapshot)\n\n" + "\n\n".join(citations) +
        "\n\nAlso cite: Pastorello et al. (2020), Scientific Data 7, 225, https://doi.org/10.1038/s41597-020-0534-3\n",
        encoding="utf-8")
    print(f"\n    Citations written to {cit_file}")
    return ok


def main():
    p = argparse.ArgumentParser(description="Download your five FLUXNET towers for Block 4.")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--student", help="your student number from tower_sets_block4.csv, e.g. 07")
    g.add_argument("--sites", nargs="+", help="site IDs to download, e.g. DE-Hai FR-Hes")
    p.add_argument("--csv", default=DEFAULT_CSV, help=f"tower list (default: {DEFAULT_CSV})")
    p.add_argument("--new-snapshot", action="store_true", help="make a fresh snapshot even if one exists")
    args = p.parse_args()

    sites = sites_for_student(args.csv, args.student) if args.student else args.sites

    ensure_shuttle()
    SNAP_DIR.mkdir(parents=True, exist_ok=True)
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    snapshot = None if args.new_snapshot else newest_snapshot()
    if snapshot:
        say(f"Using existing snapshot {snapshot.name} (add --new-snapshot for a fresh one).")
    else:
        say("Making a snapshot of all available FLUXNET data ...")
        shuttle("listall", "-o", str(SNAP_DIR))
        snapshot = newest_snapshot()
        if not snapshot:
            stop("The snapshot is empty: no data hub could be reached.\n"
                 "  Check your internet connection and run the script again.")

    rows = read_snapshot(snapshot)
    missing = [s for s in sites if s not in rows]
    if missing:
        stop(f"Not in the snapshot: {' '.join(missing)}. Check the site IDs, or try --new-snapshot.")

    say(f"Downloading {len(sites)} sites to {RAW_DIR}/ — large sites can take several minutes ...")
    if shuttle("download", "-f", str(snapshot), "-s", *sites, "-o", str(RAW_DIR), "--quiet") != 0:
        print("\nThe download reported an error; checking what arrived ...")

    if check_zips(sites, rows):
        say("Done. Next: Part B of the assignment — read one FLUXMET_HH file.")
        print("    Keep data/ out of Git: it must be listed in your .gitignore.")
    else:
        stop("Some towers are missing or broken. Run the script again; existing files are re-downloaded.")


if __name__ == "__main__":
    main()
