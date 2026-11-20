# 04_soilgrids.R — soil properties at your five towers
# Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg
#
# SoilGrids 2.0 (ISRIC): machine-learning maps of soil properties at 250 m,
# six depths from 0–5 cm to 100–200 cm, with uncertainty.
# We read the global maps directly from the ISRIC file server (Cloud-optimised
# GeoTIFFs behind one .vrt file per property × depth), only the pixel under each tower.
# No account. 8 properties × 6 depths × (mean + uncertainty) = 96 maps, a few
# seconds each: count 5–15 min. Set with_uncertainty <- FALSE to halve that.
# (SoilGrids also has a REST API, rest.isric.org, but it is a beta service and often down.)
#
# The maps store integers ("mapped units"); divide by d_factor for conventional units:
#   clay, sand, silt: g/kg -> /10 -> %        soc: dg/kg -> /10 -> g/kg
#   phh2o: pH*10 -> /10 -> pH                 bdod: cg/cm³ -> /100 -> kg/dm³
#   nitrogen: cg/kg -> /100 -> g/kg           cec: mmol(c)/kg -> /10 -> cmol(c)/kg
#   uncertainty = (Q95 − Q05) / median × 10 -> /10 -> ratio (higher = less certain)
#
# Packages: install.packages("terra")
# Output:   data/external/soilgrids/soilgrids_my_sites.csv (long: site × property × depth)
# Cite:     Poggio, L. et al. (2021) SoilGrids 2.0. SOIL 7, 217–240.
#           https://doi.org/10.5194/soil-7-217-2021

source(file.path("scripts", "block5", "block5_sites.R"))
library(terra)

properties <- c("clay", "sand", "silt", "soc", "phh2o", "bdod", "nitrogen", "cec")
depths     <- c("0-5cm", "5-15cm", "15-30cm", "30-60cm", "60-100cm", "100-200cm")
with_uncertainty <- TRUE
d_factor <- c(clay = 10, sand = 10, silt = 10, soc = 10, phh2o = 10, bdod = 100, nitrogen = 100, cec = 10)
unit     <- c(clay = "%", sand = "%", silt = "%", soc = "g/kg", phh2o = "pH", bdod = "kg/dm³",
              nitrogen = "g/kg", cec = "cmol(c)/kg")
base <- "https://files.isric.org/soilgrids/latest/data"
d <- out_dir("soilgrids")
setGDALconfig("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")   # do not list the server folder

# Read one map at all towers; NULL if the server does not answer
read_layer <- function(prop, depth, stat) {
  url <- sprintf("/vsicurl/%s/%s/%s_%s_%s.vrt", base, prop, prop, depth, stat)
  for (try in 1:3) {
    out <- tryCatch({
      r <- rast(url)
      pts <- project(vect(sites, geom = c("lon", "lat"), crs = "EPSG:4326"), crs(r))
      v <- extract(r, pts, ID = FALSE)[[1]]
      v[v %in% c(-32768, 65535)] <- NA                 # fill values: no data at this pixel
      v
    }, error = function(e) NULL)
    if (!is.null(out)) return(out)
    Sys.sleep(10 * try)
  }
  NULL
}

stats <- if (with_uncertainty) c("mean", "uncertainty") else "mean"
say("Reading ", length(properties) * length(depths) * length(stats),
    " SoilGrids maps from files.isric.org (5–15 min)")
rows <- list()
for (p in properties) {
  for (dep in depths) {
    v <- lapply(stats, function(st) read_layer(p, dep, st))
    if (any(vapply(v, is.null, logical(1)))) {
      stop("\n\nSoilGrids is not reachable right now (", base, "/", p, ").\n",
           "This is the ISRIC server, not your script. Try again in 30 minutes;\n",
           "maps that were already read are not kept, the script starts again.\n",
           "If it keeps failing, test it in the browser: ", base, "/", call. = FALSE)
    }
    top_bottom <- as.numeric(strsplit(sub("cm", "", dep), "-")[[1]])
    rows[[length(rows) + 1]] <- data.frame(
      site_id = sites$site_id, property = p, depth = dep,
      top_cm = top_bottom[1], bottom_cm = top_bottom[2],
      mean = v[[1]] / d_factor[[p]],
      uncertainty = if (with_uncertainty) v[[2]] / 10 else NA_real_,
      unit = unit[[p]])
  }
  say(p, ": done")
}
soil <- do.call(rbind, rows)
soil <- soil[order(soil$site_id, soil$property, soil$top_cm), ]
write.csv(soil, file.path(d, "soilgrids_my_sites.csv"), row.names = FALSE)

# A quick wide view of the topsoil (0–30 cm, thickness-weighted mean)
top <- soil[soil$bottom_cm <= 30, ]
top$w <- top$bottom_cm - top$top_cm
wide <- sapply(split(top, top$property), function(x)
  sapply(split(x, x$site_id), function(y) weighted.mean(y$mean, y$w, na.rm = TRUE)))
say("Topsoil 0–30 cm (thickness-weighted):")
print(round(wide, 2))
say("Done. File: ", file.path(d, "soilgrids_my_sites.csv"),
    "\n    NA everywhere? The tower may sit on a pixel SoilGrids masks (water, urban, rock).",
    "\n    Report it; do not invent a value.")
