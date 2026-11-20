# 05_planttraits.R — plant functional traits at your five towers (planttraits.earth)
# Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg
#
# Global maps of 31 plant traits at 1 km (Lusk et al. 2026, Nature Communications),
# made in our chair: ~40 million citizen-science plant observations (GBIF,
# e.g. iNaturalist) + sPlot vegetation plots + TRY trait measurements +
# Earth observation predictors. Each value is a community-weighted mean (CWM):
# the average trait of the plants growing in that 1 km cell, weighted by abundance.
#
# Each GeoTIFF has 3 bands: 1 = trait value, 2 = coefficient of variation
# (model uncertainty), 3 = area of applicability (are the predictors at this
# pixel similar to the training data?). Projection EPSG:6933 (equal area).
# One file is ~0.5–0.7 GB, so we do NOT download it: GDAL's /vsicurl/ reads
# only the bytes around your five pixels straight from Zenodo.
# If that is very slow or fails, download the file in the browser and set local_dir.
#
# Packages: install.packages("terra")
# Output:   data/external/planttraits/planttraits_my_sites.csv
# Cite:     Lusk, D. et al. (2026) Crowdsourced biodiversity monitoring fills gaps in
#           global plant trait mapping. Nat. Commun. 17, 1203.
#           https://doi.org/10.1038/s41467-026-68996-y · data: https://doi.org/10.5281/zenodo.14646322

source(file.path("scripts", "block5", "block5_sites.R"))
library(terra)

# TRY trait ID, short name, unit. * = experimental map (cross-validated r < 0.5)
traits <- data.frame(
  id   = c(3117, 14, 50, 4, 6, 3113, 3106),
  name = c("SLA", "leaf_N_mass", "leaf_N_area", "stem_density", "rooting_depth",
           "leaf_area", "plant_height*"),
  unit = c("m2 kg-1", "mg g-1", "g m-2", "g cm-3", "m", "mm2", "m"))
# all 31 traits and their IDs: https://planttraits.earth
# plant_height is stored in coarse steps of ~0.9 m: low vegetation all reads 0.68 m.

local_dir <- NULL   # e.g. "data/external/planttraits/tif" if you downloaded the files
base <- "https://zenodo.org/records/14646322/files"
d <- out_dir("planttraits")
pts <- vect(sites, geom = c("lon", "lat"), crs = "EPSG:4326")

out <- sites[, c("site_id", "igbp", "lat", "lon")]
for (k in seq_len(nrow(traits))) {
  f <- sprintf("X%d_mean_Shrub_Tree_Grass_1km.tif", traits$id[k])
  src <- if (is.null(local_dir)) paste0("/vsicurl/", base, "/", f) else file.path(local_dir, f)
  say(traits$name[k], " (TRY ", traits$id[k], ")")
  r <- rast(src)
  # The files store integers: real value = stored * scale + offset, per band.
  # We apply it ourselves (terra's extract() uses band 1's scale for all bands).
  so <- scoff(r)                                   # matrix: column 1 scale, column 2 offset
  scoff(r) <- cbind(rep(1, nlyr(r)), rep(0, nlyr(r)))
  v <- extract(r, project(pts, crs(r)), ID = FALSE)
  for (b in seq_len(ncol(v))) v[[b]] <- v[[b]] * so[b, 1] + so[b, 2]
  nm <- gsub("\\*", "", traits$name[k])
  out[[nm]]                    <- v[[1]]
  out[[paste0(nm, "_cov")]]    <- v[[2]]
  out[[paste0(nm, "_aoa")]]    <- v[[3]]
}
write.csv(out, file.path(d, "planttraits_my_sites.csv"), row.names = FALSE)
print(out[, c("site_id", "igbp", "SLA", "leaf_N_mass", "stem_density", "rooting_depth")], row.names = FALSE)
write.csv(traits, file.path(d, "planttraits_units.csv"), row.names = FALSE)

say("Done. File: ", file.path(d, "planttraits_my_sites.csv"),
    "\n    Read the _aoa column before you trust a value: outside the area of applicability",
    "\n    the model extrapolates. Croplands and wetlands are often poorly covered.")
