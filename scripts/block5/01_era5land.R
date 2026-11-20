# 01_era5land.R — ERA5-Land hourly time series at your five towers
# Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg
#
# ERA5-Land: ECMWF land reanalysis, 0.1° (~9 km), hourly, 1950–today.
# Your FLUXNET zips already contain ERA5 weather downscaled to each tower
# (the *_ERA5_*.csv files). ERA5-Land adds what most towers do NOT measure:
# soil moisture and soil temperature in four layers down to 2.89 m.
#
# Dataset: "reanalysis-era5-land-timeseries" on the Copernicus Climate Data Store (CDS),
# a point product: the CDS takes the nearest grid cell and returns a CSV.
#
# ONCE, before class:
#   1. Make a free account at https://cds.climate.copernicus.eu
#   2. Accept the dataset licence: open the dataset page, tab "Download",
#      scroll to "Terms of use" and click Accept.
#   3. Copy your Personal Access Token from your CDS profile page and run in R:
#        install.packages("ecmwfr")
#        ecmwfr::wf_set_key(key = "PASTE-YOUR-TOKEN-HERE")
#
# Output: data/external/era5land/<SITE>_era5land_hourly.csv and <SITE>_era5land_daily.csv
# Cite:   Muñoz-Sabater, J. et al. (2021) ERA5-Land. ESSD 13, 4349–4383.
#         https://doi.org/10.5194/essd-13-4349-2021 (+ "Contains modified Copernicus
#         Climate Change Service information <year>")

source(file.path("scripts", "block5", "block5_sites.R"))
library(ecmwfr)

# ---- Settings -----------------------------------------------------------------
variables <- c("2m_temperature",
               "volumetric_soil_water_layer_1",   #   0–7 cm   (m³ m⁻³)
               "volumetric_soil_water_layer_2",   #   7–28 cm
               "volumetric_soil_water_layer_3",   #  28–100 cm
               "soil_temperature_level_1")        #   0–7 cm   (K)
# More: "total_precipitation", "surface_solar_radiation_downwards", "snow_depth", ...
# Careful: precipitation and radiation are ACCUMULATED variables in ERA5-Land.
# Look at a few hours first before you sum them to days.

years_back <- 10   # how many years at the end of each tower record (the CDS has quotas)

d <- out_dir("era5land")

# Stop early, with a clear message, if the CDS token is not stored yet
if (inherits(try(wf_get_key(), silent = TRUE), "try-error")) {
  stop("\n\nNo CDS token found. Do this once (see the top of this script):\n",
       "  1. Log in at https://cds.climate.copernicus.eu and copy your Personal Access Token\n",
       "     from your profile page.\n",
       "  2. Accept the licence on the dataset page (tab Download, Terms of use).\n",
       "  3. In R: ecmwfr::wf_set_key(key = \"PASTE-YOUR-TOKEN-HERE\")\n", call. = FALSE)
}

for (i in seq_len(nrow(sites))) {
  s <- sites[i, ]
  last  <- min(s$last_year, as.integer(format(Sys.Date(), "%Y")) - 1)
  first <- max(s$first_year, last - years_back + 1, 1950)
  hourly_file <- file.path(d, paste0(s$site_id, "_era5land_hourly.csv"))
  if (file.exists(hourly_file)) { say(s$site_id, ": already there, skipped"); next }
  say(s$site_id, ": requesting ", first, "–", last, " (this can wait in the CDS queue for a few minutes)")

  request <- list(
    dataset_short_name = "reanalysis-era5-land-timeseries",
    variable    = variables,
    location    = list(longitude = round(s$lon, 3), latitude = round(s$lat, 3)),
    date        = paste0(first, "-01-01/", last, "-12-31"),
    data_format = "csv",
    target      = paste0(s$site_id, "_era5land.zip")
  )
  f <- tryCatch(wf_request(request = request, transfer = TRUE, path = d, time_out = 3 * 3600),
                error = function(e) stop("\n\nThe CDS refused or failed the request:\n  ", conditionMessage(e),
                                         "\n401/403 = wrong token or licence not accepted on the dataset page.",
                                         "\nOtherwise the CDS may be busy: try again later. Finished towers are kept.",
                                         call. = FALSE))

  # The CDS sends a zip with one or more CSVs (or a single CSV): read and join them
  csvs <- if (grepl("\\.zip$", f, ignore.case = TRUE)) {
    unzip(f, exdir = file.path(d, paste0(s$site_id, "_parts")))
  } else f
  csvs <- csvs[grepl("\\.csv$", csvs, ignore.case = TRUE)]
  parts <- lapply(csvs, read.csv, check.names = FALSE)
  era <- Reduce(function(a, b) merge(a, b, by = intersect(names(a), names(b)), all = TRUE), parts)

  time_col <- grep("time", names(era), value = TRUE)[1]
  era$time <- as.POSIXct(era[[time_col]], tz = "UTC", tryFormats = c("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"))
  # Kelvin -> °C for temperatures (t2m, stl1, ...)
  for (v in intersect(names(era), c("t2m", "stl1", "stl2", "stl3", "stl4", "skt", "d2m"))) {
    era[[paste0(v, "_C")]] <- era[[v]] - 273.15
  }
  era$site_id <- s$site_id
  write.csv(era, hourly_file, row.names = FALSE)

  # Daily means of the state variables (temperature, soil water). UTC days!
  era$date <- as.Date(era$time)
  state <- intersect(names(era), c("t2m_C", "stl1_C", "swvl1", "swvl2", "swvl3", "swvl4", "sd"))
  daily <- aggregate(era[state], by = list(date = era$date), FUN = mean, na.rm = TRUE)
  daily$site_id <- s$site_id
  write.csv(daily, file.path(d, paste0(s$site_id, "_era5land_daily.csv")), row.names = FALSE)
  say(s$site_id, ": ", nrow(era), " hours, columns: ", paste(names(era), collapse = ", "))
}

say("Done. Files in ", d,
    "\n    Check: is ERA5-Land t2m close to the tower's TA_F? Plot one year of both.")
