# 06_deadtrees.R — tree cover and standing deadwood around your towers (deadtrees.earth)
# Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg
#
# deadtrees.earth (made in our chair) has two kinds of data:
#   1. Drone and aerial orthophotos (cm resolution) with dead-tree labels, worldwide.
#      Browse and download them by hand: https://deadtrees.earth/dataset
#   2. Satellite maps: yearly 10 m maps of tree cover and standing deadwood cover
#      for EUROPE, 2017–2025, made by extrapolating the drone labels with Sentinel
#      data and deep learning. Cloud-optimised GeoTIFFs in EPSG:3035 (LAEA Europe),
#      version 5 (Oct 2026). Band 1: cover, 0–255 = 0–100 %. Band 2: 0 = no data,
#      255 = data. Band 1 is also 0 where there is no data, so we use band 2 as the mask.
# This script uses (2): it cuts a small box around each European tower for every
# year and computes mean tree cover, mean deadwood cover and the area of mortality.
# Towers outside Europe are skipped (look at the drone data browser instead).
#
# Packages: install.packages("terra")
# Output:   data/external/deadtrees/deadtrees_my_sites.csv (site × year)
#           data/external/deadtrees/clips/<SITE>_<layer>_<year>.tif (small maps to plot)
# Cite:     Mosig, C. et al. (2026) deadtrees.earth — An open-access and interactive database
#           for centimeter-scale aerial imagery to uncover global tree mortality dynamics.
#           Remote Sens. Environ. 332, 115027. https://doi.org/10.1016/j.rse.2025.115027

source(file.path("scripts", "block5", "block5_sites.R"))
library(terra)

years      <- 2017:2025
half_box_m <- 1000   # box of 2 km × 2 km around the tower (≈ a generous flux footprint)
forest_min <- 0.20   # a pixel is forest if tree cover > 20 %
dead_min   <- 0.30   # ... and "mortality" if standing deadwood cover > 30 %
base <- "https://data.rsc4earth.de/download/deadtrees.earth_maps/v5_europe_composite_epsg_3035"

d <- out_dir("deadtrees")
clip_dir <- file.path(d, "clips"); dir.create(clip_dir, showWarnings = FALSE)
eu <- sites[sites$continent == "Europe", ]
if (nrow(eu) == 0) {
  stop("None of your towers is in Europe, so the satellite maps do not cover them.\n",
       "Use the drone data browser instead: https://deadtrees.earth/dataset", call. = FALSE)
}
if (nrow(eu) < nrow(sites)) {
  say("Skipped (outside Europe): ", paste(setdiff(sites$site_id, eu$site_id), collapse = ", "))
}

load_box <- function(layer, year, box) {
  r <- try(rast(sprintf("/vsicurl/%s/%s_%d.tif", base, layer, year)), silent = TRUE)
  if (inherits(r, "try-error")) return(NULL)            # year not available
  b <- crop(r, box)
  cover <- b[[1]] / 255                                   # 0–255 -> fraction 0–1
  cover[b[[2]] == 0] <- NA                                # band 2 = 0: no data
  names(cover) <- layer
  cover
}

rows <- list()
for (i in seq_len(nrow(eu))) {
  s <- eu[i, ]
  xy  <- project(vect(s, geom = c("lon", "lat"), crs = "EPSG:4326"), "EPSG:3035")
  c0  <- crds(xy)
  box <- ext(c0[1] - half_box_m, c0[1] + half_box_m, c0[2] - half_box_m, c0[2] + half_box_m)
  for (y in years) {
    tc <- load_box("tree_cover", y, box)
    dw <- load_box("standing_deadwood_cover", y, box)
    if (is.null(tc) || is.null(dw)) { say(s$site_id, " ", y, ": not available"); next }
    writeRaster(tc, file.path(clip_dir, sprintf("%s_tree_cover_%d.tif", s$site_id, y)), overwrite = TRUE)
    writeRaster(dw, file.path(clip_dir, sprintf("%s_deadwood_%d.tif", s$site_id, y)), overwrite = TRUE)
    forest <- tc > forest_min
    pix_ha <- prod(res(tc)) / 1e4
    rows[[length(rows) + 1]] <- data.frame(
      site_id = s$site_id, year = y,
      tree_cover_pct   = 100 * global(tc, "mean", na.rm = TRUE)[[1]],
      deadwood_pct     = 100 * global(dw, "mean", na.rm = TRUE)[[1]],
      forest_ha        = global(forest, "sum", na.rm = TRUE)[[1]] * pix_ha,
      mortality_ha     = global(forest & (dw > dead_min), "sum", na.rm = TRUE)[[1]] * pix_ha)
    say(s$site_id, " ", y, ": done")
  }
}
res_tab <- do.call(rbind, rows)
write.csv(res_tab, file.path(d, "deadtrees_my_sites.csv"), row.names = FALSE)
print(res_tab, row.names = FALSE, digits = 3)
say("Done. Files in ", d,
    "\n    A grassland or cropland tower has little tree cover: that is a result, not an error.",
    "\n    Plot the clips: plot(rast('", clip_dir, "/<SITE>_deadwood_2023.tif'))")
