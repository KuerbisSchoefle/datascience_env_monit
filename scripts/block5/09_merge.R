# 09_merge.R — put the tower and the new data into two tidy tables
# Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg
#
# Two kinds of data, two tables:
#   site_static.csv  one row per tower: climate normals, soil, traits, biodiversity
#   site_daily.csv   one row per tower and day: FLUXNET daily fluxes + ERA5-Land
#                    soil moisture + MODIS NDVI/EVI (interpolated to days) + Dheed flag
# Join keys: site_id (static) and site_id + date (daily).
# Run the download scripts first; whatever is missing is simply left out.
#
# Packages: install.packages(c("dplyr", "readr", "tidyr"))
# Output:   data/processed/site_static.csv, data/processed/site_daily.csv

source(file.path("scripts", "block5", "block5_sites.R"))
suppressPackageStartupMessages({ library(dplyr); library(readr); library(tidyr) })

ext <- function(...) file.path("data", "external", ...)
read_if <- function(path) if (file.exists(path)) read_csv(path, show_col_types = FALSE) else NULL
dir.create(file.path("data", "processed"), recursive = TRUE, showWarnings = FALSE)

# ---- 1. Static table: one row per tower ---------------------------------------
static <- sites
wc <- read_if(ext("worldclim", "worldclim_bio_my_sites.csv"))
if (!is.null(wc)) static <- left_join(static, select(wc, site_id, BIO1, BIO4, BIO12, BIO15), by = "site_id")

soil <- read_if(ext("soilgrids", "soilgrids_my_sites.csv"))
if (!is.null(soil)) {
  topsoil <- soil |>
    filter(bottom_cm <= 30) |>
    group_by(site_id, property) |>
    summarise(value = weighted.mean(mean, bottom_cm - top_cm, na.rm = TRUE), .groups = "drop") |>
    pivot_wider(names_from = property, values_from = value, names_prefix = "soil0_30_")
  static <- left_join(static, topsoil, by = "site_id")
}
tr <- read_if(ext("planttraits", "planttraits_my_sites.csv"))
if (!is.null(tr)) static <- left_join(static, select(tr, -igbp, -lat, -lon), by = "site_id")
inat <- read_if(ext("inaturalist", "inat_summary_my_sites.csv"))
if (!is.null(inat)) static <- left_join(static, select(inat, site_id, n_obs, n_species, n_plant_species), by = "site_id")
write_csv(static, file.path("data", "processed", "site_static.csv"))
say("site_static.csv: ", nrow(static), " towers × ", ncol(static), " columns")

# ---- 2. Daily table: FLUXNET daily file from your Block 4 zips -----------------
read_dd <- function(zip_file) {
  dd <- grep("FLUXMET_DD", unzip(zip_file, list = TRUE)$Name, value = TRUE)[1]
  if (is.na(dd)) return(NULL)
  keep <- c("TIMESTAMP", "TA_F", "SW_IN_F", "VPD_F", "P_F", "LE_F_MDS",
            "NEE_VUT_REF", "GPP_NT_VUT_REF", "RECO_NT_VUT_REF", "NEE_VUT_REF_QC")
  read_csv(unz(zip_file, dd), na = c("-9999", "-9999.0"), col_select = any_of(keep),
           col_types = cols(TIMESTAMP = "c", .default = "d"), show_col_types = FALSE) |>
    mutate(date = as.Date(TIMESTAMP, format = "%Y%m%d"),
           site_id = sub("^[A-Z]+_([A-Z]{2}-[A-Za-z0-9]{3})_.*$", "\\1", basename(zip_file))) |>
    select(-TIMESTAMP)
}
zips  <- list.files(file.path("data", "raw"), pattern = "FLUXNET.*\\.zip$", full.names = TRUE)
flux  <- bind_rows(lapply(zips, read_dd)) |> filter(site_id %in% sites$site_id)
if (nrow(flux) == 0) stop("No FLUXMET_DD files found in data/raw (Block 4 zips).", call. = FALSE)
daily <- flux

era <- bind_rows(lapply(list.files(ext("era5land"), "_era5land_daily\\.csv$", full.names = TRUE),
                        read_csv, show_col_types = FALSE))
if (nrow(era) > 0) daily <- left_join(daily, rename_with(era, ~ paste0("era5l_", .x), -c(site_id, date)),
                                      by = c("site_id", "date"))

vi <- read_if(ext("modis", "modis_vi_my_sites.csv"))
if (!is.null(vi)) {
  # 16-day composites -> daily by linear interpolation between composite dates (per site)
  vi_daily <- vi |>
    group_by(site_id) |>
    reframe(day  = seq(min(date), max(date), by = "day"),
            ndvi = approx(date, ndvi, xout = day)$y,
            evi  = approx(date, evi,  xout = day)$y) |>
    rename(date = day)
  daily <- left_join(daily, vi_daily, by = c("site_id", "date"))
}
dh <- read_if(ext("dheed", "dheed_daily_flags_my_sites.csv"))
if (!is.null(dh)) {
  daily <- left_join(daily, select(dh, site_id, date, dheed_event, dheed_label), by = c("site_id", "date")) |>
    mutate(dheed_event = coalesce(dheed_event, FALSE))
}
write_csv(daily, file.path("data", "processed", "site_daily.csv"))
say("site_daily.csv: ", nrow(daily), " tower-days × ", ncol(daily), " columns",
    "\n    Units: GPP/NEE/RECO in the DD files are g C m⁻² d⁻¹; LE in W m⁻²; era5l_swvl in m³ m⁻³.")
