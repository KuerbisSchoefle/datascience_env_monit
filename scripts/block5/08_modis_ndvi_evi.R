# 08_modis_ndvi_evi.R — compute NDVI and EVI at your towers from MODIS reflectance
# Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg
#
# MODIS Terra MOD13Q1 (Collection 6.1): 250 m pixels, one composite every 16 days,
# from February 2000. Besides the finished NDVI and EVI it contains the surface
# reflectance in the red, near-infrared (NIR) and blue bands. We download those
# and compute NDVI and EVI ourselves. With compare_official <- TRUE we also download
# the official NDVI and EVI and compare (50 % more download time).
#
#   NDVI = (NIR − Red) / (NIR + Red)
#   EVI  = 2.5 · (NIR − Red) / (NIR + 6·Red − 7.5·Blue + 1)
#
# Source: ORNL DAAC MODIS/VIIRS subset web service (no account), via MODISTools.
# We take a window of 9 × 9 pixels (~2 × 2 km) around each tower and keep only
# pixels with pixel_reliability 0 (good) or 1 (marginal); 2 = snow/ice, 3 = cloudy.
# The service sends at most 10 dates of ONE band per request, and each request can
# take 5–40 s when the service is busy: count 5–20 min per tower for 3 years.
# "Request failed [502] ... Retrying" is the busy server; MODISTools retries by itself.
# A tower that finished is saved; run the script again and it continues with the next.
#
# Packages: install.packages(c("MODISTools", "dplyr", "tidyr"))
# Output:   data/external/modis/<SITE>_mod13q1_pixels.csv   (every pixel, every date)
#           data/external/modis/modis_vi_my_sites.csv        (site mean per date)
# Cite:     Didan, K. (2021) MOD13Q1 MODIS/Terra Vegetation Indices 16-Day L3 Global 250m SIN Grid V061.
#           NASA LP DAAC. https://doi.org/10.5067/MODIS/MOD13Q1.061
#           + ORNL DAAC (2018) MODIS Collection 6 Land Product Subsets Web Service.
#           https://doi.org/10.3334/ORNLDAAC/1557

source(file.path("scripts", "block5", "block5_sites.R"))
library(MODISTools)
library(dplyr)
library(tidyr)

years_back <- 3    # last N years of each tower record (MODIS starts 2000-02-18).
                   # More years = proportionally longer download.
km         <- 1    # km left/right and above/below the centre pixel -> 9 × 9 pixels
compare_official <- FALSE   # TRUE: also download MODIS's own NDVI and EVI to compare
bands <- c("250m_16_days_red_reflectance", "250m_16_days_NIR_reflectance",
           "250m_16_days_blue_reflectance", "250m_16_days_pixel_reliability")
if (compare_official) bands <- c(bands, "250m_16_days_NDVI", "250m_16_days_EVI")
d <- out_dir("modis")

all_sites <- list()
for (i in seq_len(nrow(sites))) {
  s <- sites[i, ]
  first <- max(s$first_year, s$last_year - years_back + 1, 2000)
  pix_file <- file.path(d, paste0(s$site_id, "_mod13q1_pixels.csv"))
  if (file.exists(pix_file)) {
    say(s$site_id, ": already downloaded, reading ", pix_file)
    raw <- read.csv(pix_file)
  } else {
    say(s$site_id, ": downloading ", length(bands), " MOD13Q1 bands, ", first, "–", s$last_year,
        " (5–20 min; one progress bar per band)")
    raw <- tryCatch(
      mt_subset(product = "MOD13Q1", lat = s$lat, lon = s$lon, band = bands,
                start = paste0(first, "-01-01"), end = paste0(s$last_year, "-12-31"),
                km_lr = km, km_ab = km, site_name = s$site_id,
                internal = TRUE, progress = TRUE),
      error = function(e) NULL)
    if (is.null(raw) || nrow(raw) == 0) {
      stop("\n\nThe MODIS service (modis.ornl.gov) is not answering right now (error 502 =\n",
           "server busy or down). This is the NASA server, not your script.\n",
           "Towers that finished are saved in ", d, "; run the script again later\n",
           "and it continues with ", s$site_id, ". Check the service in the browser:\n",
           "https://modis.ornl.gov/rst/api/v1/products", call. = FALSE)
    }
    write.csv(raw, pix_file, row.names = FALSE)
  }

  # long -> wide: one row per pixel and date, one column per band
  short <- c("250m_16_days_red_reflectance" = "red", "250m_16_days_NIR_reflectance" = "nir",
             "250m_16_days_blue_reflectance" = "blue", "250m_16_days_NDVI" = "ndvi_modis",
             "250m_16_days_EVI" = "evi_modis", "250m_16_days_pixel_reliability" = "reliability")
  if (!"calendar_date" %in% names(raw)) raw$calendar_date <- raw$date   # file from the Python script
  px <- raw |>
    mutate(band = short[band], value = as.numeric(value)) |>
    select(date = calendar_date, pixel, band, value) |>
    pivot_wider(names_from = band, values_from = value) |>
    mutate(across(any_of(c("red", "nir", "blue", "ndvi_modis", "evi_modis")),
                  ~ ifelse(.x <= -1000, NA, .x * 0.0001)))   # fill values -1000 / -3000; scale 0.0001
  has_official <- all(c("ndvi_modis", "evi_modis") %in% names(px))

  # Compute the indices ourselves, then keep good and marginal pixels only
  px <- px |>
    mutate(ndvi = (nir - red) / (nir + red),
           evi  = 2.5 * (nir - red) / (nir + 6 * red - 7.5 * blue + 1)) |>
    filter(reliability %in% c(0, 1))

  site_ts <- px |>
    group_by(date) |>
    summarise(n_good_pixels = n(),
              ndvi = mean(ndvi, na.rm = TRUE), evi = mean(evi, na.rm = TRUE),
              across(any_of(c("ndvi_modis", "evi_modis")), ~ mean(.x, na.rm = TRUE)),
              .groups = "drop") |>
    mutate(site_id = s$site_id, date = as.Date(date))
  all_sites[[s$site_id]] <- site_ts
  say(s$site_id, ": ", nrow(site_ts), " dates",
      if (has_official) paste0("; r(own NDVI, MODIS NDVI) = ",
                               round(cor(site_ts$ndvi, site_ts$ndvi_modis, use = "complete.obs"), 3)))
}
vi <- bind_rows(all_sites) |> relocate(site_id)
write.csv(vi, file.path(d, "modis_vi_my_sites.csv"), row.names = FALSE)
say("Done. File: ", file.path(d, "modis_vi_my_sites.csv"),
    if (compare_official) "\n    Your NDVI should match the MODIS NDVI almost exactly. Does your EVI? Why (not)?",
    "\n    Next: plot EVI and the tower's GPP on one time axis.")
