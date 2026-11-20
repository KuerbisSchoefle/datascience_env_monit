# Block 5 · Complementary data for your five towers

Environmental Monitoring and Data Analysis · University of Freiburg · WS 2026/27

Each script downloads one dataset for **your five towers** (from `tower_sets_block4.csv`, as in Block 4) and writes a tidy CSV with a `site_id` column to `data/external/<dataset>/`. Every script exists in R and in Python and does the same thing. Pick your language.

| # | Script | Dataset | What you get at each tower | Account? | Time |
|---|---|---|---|---|---|
| 01 | `01_era5land` | ERA5-Land (0.1°, hourly, 1950–) | soil moisture & soil temperature, air temperature, last 10 tower years | **yes, CDS** | 5–30 min (queue) |
| 02 | `02_worldclim` | WorldClim 2.1 (5′) | 19 bioclimatic variables + monthly normals 1970–2000 | no | 2 min |
| 03 | `03_dheed` | Dheed (ERA5, 0.25°, 1950–2023) | compound dry-and-hot events during your tower years | no | 1 min |
| 04 | `04_soilgrids` | SoilGrids 2.0 (250 m) | clay, sand, silt, SOC, pH, bulk density, N, CEC at 6 depths | no | 2 min |
| 05 | `05_planttraits` | planttraits.earth (1 km) | 7 community-weighted plant traits + uncertainty | no | 1–5 min |
| 06 | `06_deadtrees` | deadtrees.earth (10 m, Europe) | yearly tree cover and standing deadwood 2017–2025 | no | 2–5 min |
| 07 | `07_inaturalist` | iNaturalist | research-grade species observations within 5 km | no | 1–5 min |
| 08 | `08_modis_ndvi_evi` | MODIS MOD13Q1 (250 m, 16 days) | red/NIR/blue reflectance → **your own NDVI and EVI** | no | 3–10 min |
| 09 | `09_merge` | — | `data/processed/site_static.csv` and `site_daily.csv` | — | 1 min |

## Setup

1. Put the folder `scripts/block5/` into your project folder (the one with `data/raw` from Block 4) and keep `tower_sets_block4.csv` in the project folder.
2. Set your student number **once** in `block5_sites.R` (`my_student <- "07"`) or `block5_sites.py` (`MY_STUDENT = "07"`), or pass it each time: `Rscript scripts/block5/04_soilgrids.R 07` / `python3 scripts/block5/04_soilgrids.py --student 07`.
3. Install the packages:

```r
install.packages(c("httr2", "jsonlite", "terra", "geodata", "MODISTools",
                   "ecmwfr", "dplyr", "tidyr", "readr"))
```

```bash
pip install pandas numpy requests rasterio pyproj cdsapi
pip install xarray zarr        # only for the optional LabelCube check in 03_dheed.py
```

4. **Before class, for ERA5-Land only:** make a free account at <https://cds.climate.copernicus.eu>, accept the licence of the dataset *ERA5-Land hourly time-series data from 1950 to present* (tab Download → Terms of use), and store your Personal Access Token (see the top of `01_era5land.R` / `.py`).

Run every script from your project folder. Data stay out of Git (`data/` is in your `.gitignore`).

## Order

Any order works for 01–08. Run `09_merge` last; it uses whatever is there.

## When something fails

| You see | Usually it means |
|---|---|
| `tower_sets_block4.csv not found` | Your working directory is not the project folder. In Positron: *Session → Set Working Directory*, or `setwd()`. |
| SoilGrids `429` or `503` | Too many requests or the beta service is down. The script waits and retries; otherwise try again in 10 minutes. |
| ERA5-Land `401` / `403` | Token missing or licence not accepted on the dataset page. |
| ERA5-Land waits a long time | Your request is in the CDS queue. Let it run; do the other scripts meanwhile. |
| `06_deadtrees`: none of your towers is in Europe | Expected: the satellite maps cover Europe. Look for drone data near your towers at <https://deadtrees.earth/dataset>. |
| PlantTraits very slow | Reading over HTTP needs a good connection. Download the `.tif` from Zenodo in the browser and set `local_dir`. |
| NA in SoilGrids or PlantTraits | The pixel is masked (water, urban, bare rock) or outside the model's area of applicability. Report it; do not invent a value. |

## Citations

Every dataset has its citation at the top of its script. Copy them into your report.
