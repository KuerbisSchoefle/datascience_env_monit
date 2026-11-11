# Block 4 Assignment: Download your towers and write a data summary

## Overview

This assignment takes about 2 hours in class plus some time at home. You download the half-hourly FLUXNET data of your five towers with the FLUXNET Shuttle, read them in cleanly, and write a short data summary report as an HTML page rendered from code.

You hand in two things on ILIAS **before Block 5 (Friday 20 November, 8:30)**: the rendered HTML report and the link to your fork on GitHub that contains the report's source (`.qmd`, `.Rmd` or `.ipynb`).

| Part | What you do | Time |
| --- | --- | --- |
| 0 | Sync your fork with the course repository | 10 min |
| A | Find your towers, download them with the Shuttle | 30 min |
| B | Unzip and read one half-hourly file cleanly | 30 min |
| C | Write the data summary report | 90 min |
| Hand-in | Check the list and submit on ILIAS | 10 min |

**Before you start, you need:**

- Your fork of the course repository, cloned to your laptop (Block 2).
- R in Positron or Python in VS Code (Block 1).
- Python 3.9 or newer for the FLUXNET Shuttle (also on the R route; the script on ILIAS sets it up for you).
- About 2–3 GB of free disk space. If your laptop is short on space, work in your bwUniCluster workspace `envmon`.
- Quarto for the report: Positron includes it. In VS Code, install Quarto from <https://quarto.org> and the Quarto extension. Python users may hand in a Jupyter notebook exported to HTML instead.

## Part A: Find your towers and download them (30 min)

### A1. Find your set

Open `tower_sets_block4.csv` (ILIAS, folder DATA). Find your name and write down your five site IDs. Look them up in the [flux4student explorer](https://negin-katal.github.io/datascience_env_monit/flux4student/): where are they, which ecosystem, which years have good data?

**Check:** you can say for each of your towers in one sentence what kind of ecosystem it is and where it is.

### A2. Prepare the folders

Data never go into Git. In your project folder:

```bash
mkdir -p data/raw data/snapshots data/processed
echo "data/" >> .gitignore
git add .gitignore
git commit -m "Keep downloaded flux data out of Git"
```

**Check:** `git status` does not list anything under `data/`.

### A3. Download with the Shuttle

Use the Shuttle script from ILIAS (it brings all dependencies). Under the hood it runs these three commands, which you can also type yourself:

```bash
pip install git+https://github.com/fluxnet/shuttle.git
fluxnet-shuttle listall -o data/snapshots
fluxnet-shuttle download -f data/snapshots/fluxnet_shuttle_snapshot_*.csv \
  -s SITE1 SITE2 SITE3 SITE4 SITE5 -o data/raw
```

Replace `SITE1` … `SITE5` with your five site IDs. The Shuttle asks for your name, email and intended use. This is optional; it may be passed to the site teams so they can tell you about corrections. Press Enter to skip, or add `--quiet`.

On Windows PowerShell, write the download command on one line (PowerShell does not use `\` to continue lines).

**Check:** `data/raw` holds five `.zip` files, and `data/snapshots` holds one `fluxnet_shuttle_snapshot_YYYYMMDDTHHMMSS.csv`. Keep the snapshot: it records what you downloaded and the citation of each site.

## Part B: Read one half-hourly file cleanly (30 min)

### B1. Look inside a zip

Each zip holds several CSV files. Unzip one and list them.

| File (pattern) | What is in it |
| --- | --- |
| `…_FLUXMET_HH_….csv` | Fluxes and meteorology every 30 minutes. **This assignment uses these.** |
| `…_FLUXMET_DD/WW/MM/YY_….csv` | The same variables as daily, weekly, monthly, yearly values |
| `…_ERA5_HH … YY_….csv` | ERA5 reanalysis weather downscaled to the site |
| `…_BIF_….csv` | Site and ancillary information (BADM): location, IGBP, canopy height, LAI, soil … |
| `…_BIFVARINFO_….csv` | For each variable: measurement height or depth, instrument |

Read the file name: `AMF_US-Ha1_FLUXNET_FLUXMET_HH_1991-2025_v1.3_r1.csv` = hub, site ID, product, dataset, time step, years, ONEFlux code version, run.

### B2. Read it in

Three things must be right: **−9999 is missing**, **time stamps are read as text and converted to dates**, and **one row is one half hour**. The HH files have hundreds of columns; read only the ones you need.

**R route**

```r
library(readr)
library(dplyr)

keep <- c("TIMESTAMP_START", "TIMESTAMP_END", "TA_F", "SW_IN_F", "VPD_F", "P_F",
          "NETRAD", "G_F_MDS", "H_F_MDS", "H_F_MDS_QC", "LE_F_MDS", "LE_F_MDS_QC",
          "NEE_VUT_REF", "NEE_VUT_REF_QC", "GPP_NT_VUT_REF", "RECO_NT_VUT_REF")

zip_file <- list.files("data/raw", pattern = "\\.zip$", full.names = TRUE)[1]
hh_name  <- grep("FLUXMET_HH", unzip(zip_file, list = TRUE)$Name, value = TRUE)
unzip(zip_file, files = hh_name, exdir = "data/raw/unzipped")

hh <- read_csv(file.path("data/raw/unzipped", hh_name),
               na = "-9999",
               col_select = any_of(keep),
               col_types = cols(TIMESTAMP_START = "c", TIMESTAMP_END = "c", .default = "d")) |>
  mutate(time = as.POSIXct(TIMESTAMP_START, format = "%Y%m%d%H%M", tz = "UTC"))

nrow(hh)
range(hh$time)
mean(hh$NEE_VUT_REF_QC == 0, na.rm = TRUE)   # share of measured NEE
```

**Python route**

```python
import zipfile
from pathlib import Path
import pandas as pd

keep = ["TIMESTAMP_START", "TIMESTAMP_END", "TA_F", "SW_IN_F", "VPD_F", "P_F",
        "NETRAD", "G_F_MDS", "H_F_MDS", "H_F_MDS_QC", "LE_F_MDS", "LE_F_MDS_QC",
        "NEE_VUT_REF", "NEE_VUT_REF_QC", "GPP_NT_VUT_REF", "RECO_NT_VUT_REF"]

zip_file = sorted(Path("data/raw").glob("*.zip"))[0]
with zipfile.ZipFile(zip_file) as z:
    hh_name = [n for n in z.namelist() if "FLUXMET_HH" in n][0]
    with z.open(hh_name) as f:
        hh = pd.read_csv(f, na_values=[-9999],
                         usecols=lambda c: c in keep,
                         dtype={"TIMESTAMP_START": str, "TIMESTAMP_END": str})

hh["time"] = pd.to_datetime(hh["TIMESTAMP_START"], format="%Y%m%d%H%M")
print(len(hh), hh["time"].min(), hh["time"].max())
print((hh["NEE_VUT_REF_QC"] == 0).mean())    # share of measured NEE
```

The time stamps are **local standard time** (no daylight-saving jump). We store them with `tz = "UTC"` only as a container; say in your report that the clock is local standard time.

**Check:**

- `range(hh$time)` matches the years in the file name.
- A full year has 17,520 rows (17,568 in a leap year). Count rows per year.
- There are no duplicated time stamps.
- `summary(hh$TA_F)` looks like air temperature in °C, not −9999.

### B3. Wrap it in a function

Turn B2 into a function `read_hh(zip_file)` that returns one tidy table with a `site` column (the site ID from the file name), then read all five towers into one table. You will reuse this function in Block 5.

## Part C: The data summary report (90 min)

Create `reports/block4_data_summary.qmd` (or `.ipynb`) in your fork. It must render to HTML from a fresh clone with the commands in your README, provided the data are in `data/raw`.

```yaml
---
title: "Data summary of my five flux towers"
author: "Your Name"
date: today
format:
  html:
    toc: true
    embed-resources: true
execute:
  warning: false
---
```

`embed-resources: true` puts the figures inside the HTML, so a single file is enough to hand in. Render with `quarto render reports/block4_data_summary.qmd`.

The report has six sections.

### C1. Site overview

A table with one row per tower: site ID, name, country, IGBP class, latitude, longitude, first and last year, hub, and the data citation. Most of it is in your snapshot CSV. Add a simple map of the five sites (a world map with five points is enough).

### C2. Data coverage

For each site and year, the share of half hours in which NEE was measured (`NEE_VUT_REF_QC == 0`). Show it as a heat map: sites on the y-axis, years on the x-axis, colour = share measured. Add one sentence: which site and years have the best data?

### C3. Summary statistics

A table per site with mean, minimum, maximum and % missing for `TA_F`, `SW_IN_F`, `VPD_F`, `P_F`, `NEE_VUT_REF`, `GPP_NT_VUT_REF`, `RECO_NT_VUT_REF`, `H_F_MDS` and `LE_F_MDS`. Give the units in the column headers. For precipitation, give the mean annual sum instead of the mean.

### C4. Time series

Aggregate the half-hourly data to daily values yourself and plot daily NEE, GPP and RECO over the whole record, one panel per site.

Unit conversion: 1 µmol CO₂ m⁻² s⁻¹ = 1.0378 g C m⁻² d⁻¹ (× 86 400 s × 12.011 g mol⁻¹ × 10⁻⁶). So a daily mean in µmol m⁻² s⁻¹ × 1.0378 gives g C m⁻² d⁻¹.

Check your aggregation once against the daily `FLUXMET_DD` file for one site.

### C5. Diurnal cycles

The mean daily course (hour of day on the x-axis) of NEE and LE for each season, all five sites in one figure. Careful: seasons are reversed in the southern hemisphere. Use latitude to define the seasons correctly and say how you did it.

### C6. Your reading

1. **Energy balance** for one tower: scatter of `H_F_MDS + LE_F_MDS` against `NETRAD − G_F_MDS`, using only half hours where H and LE were measured (`_QC == 0`). Add the 1:1 line and the slope of a linear fit. Some towers have no `NETRAD` or `G`; pick one that has them.
2. **5–8 sentences** comparing your towers: which takes up the most carbon per year, which has the largest seasonal cycle, which surprised you, and how much of the data is gap-filled.

Close the report with a **Data and citation** section: each site's citation from the snapshot, Pastorello et al. (2020), *Scientific Data* 7, 225, <https://doi.org/10.1038/s41597-020-0534-3>, and the FLUXNET acknowledgement from `flux4student/README.md`.

## Hand-in and checklist

Submit these two things on ILIAS before Block 5:

1. The rendered HTML report.
2. The link to your fork on GitHub (`https://github.com/YOUR-USER/datascience_env_monit`) with the report's source.

Tick everything before you submit:

- [ ] Five zips in `data/raw`, untouched; `data/` is in `.gitignore`
- [ ] −9999 is read as missing and time stamps are parsed as dates
- [ ] The report names the snapshot file and the file versions (for example `v1.3_r1`)
- [ ] The report says which variables you used (`_VUT_REF`, night-time or day-time partitioning)
- [ ] Every figure has axis labels with units and a site label
- [ ] The six sections C1–C6 are there
- [ ] Data citations and the FLUXNET acknowledgement are in the report
- [ ] It renders from a fresh clone with the commands in your README

## Troubleshooting

| You see | Usually it means |
| --- | --- |
| `fluxnet-shuttle: command not found` | The Shuttle is not installed in the active Python. Use the ILIAS script, or activate your virtual environment first. |
| `Output directory does not exist` | Create the folder first (`mkdir -p data/raw`). The Shuttle does not create it. |
| A download stops halfway | Network problem. Run the download again for that one site with `-s SITE`. Existing files are overwritten. |
| Means like −2000 °C | −9999 was not read as missing. Add `na = "-9999"` / `na_values=[-9999]`. |
| Time stamps like `2.02e+11` | The time stamp was read as a number. Read it as text (`"c"` / `str`). |
| `Error: cannot allocate vector` or a frozen laptop | The file is big. Read only the columns you need, or work on bwUniCluster. |
| One tower has almost no measured NEE | Note it in C2 and tell Negin. You may get a replacement tower. |
| Quarto not found in VS Code | Install Quarto from quarto.org and restart VS Code. |

Stuck for more than 10 minutes? Post the exact command and the last lines of the error on ILIAS.

**Further reading**

- Pastorello et al. (2020): The FLUXNET2015 dataset and the ONEFlux processing pipeline for eddy covariance data. *Scientific Data* 7, 225. Sections on variables, quality flags and partitioning.
- FLUXNET Shuttle documentation: <https://fluxnet.github.io/shuttle/>
- Kljun et al. (2015): A simple two-dimensional parameterisation for Flux Footprint Prediction (FFP). *Geosci. Model Dev.* 8, 3695–3713.
- Burba (2013): *Eddy Covariance Method for Scientific, Industrial, Agricultural and Regulatory Applications*. LI-COR Biosciences. A free, readable introduction.
