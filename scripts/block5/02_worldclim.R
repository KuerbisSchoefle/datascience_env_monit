# 02_worldclim.R — long-term climate (1970–2000) at your five towers
# Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg
#
# WorldClim 2.1: interpolated station climate, monthly normals 1970–2000 and
# 19 "bioclimatic" variables (BIO1 = mean annual temperature, BIO12 = annual
# precipitation, ...). Resolutions 10', 5', 2.5' and 30" (~1 km).
# No account needed. Temperatures are in °C, precipitation in mm.
#
# Packages: install.packages(c("geodata", "terra"))
# Output:   data/external/worldclim/worldclim_bio_my_sites.csv (+ monthly normals)
# Cite:     Fick, S.E. & Hijmans, R.J. (2017) WorldClim 2. Int. J. Climatol. 37, 4302–4315.
#           https://doi.org/10.1002/joc.5086

source(file.path("scripts", "block5", "block5_sites.R"))
library(geodata)
library(terra)

res_min <- 5    # arc-minutes: 10 (~18 km), 5 (~9 km), 2.5 (~4.5 km); 0.5 = 30" (~1 km, big download)
d <- out_dir("worldclim")
pts <- vect(sites, geom = c("lon", "lat"), crs = "EPSG:4326")

# ---- Bioclimatic variables ------------------------------------------------------
say("Downloading WorldClim bio at ", res_min, "' (once; geodata keeps the files)")
bio <- worldclim_global(var = "bio", res = res_min, path = d)
names(bio) <- paste0("BIO", seq_len(nlyr(bio)))
bio_at_sites <- cbind(sites[, c("site_id", "igbp", "lat", "lon")],
                      extract(bio, pts, ID = FALSE))
write.csv(bio_at_sites, file.path(d, "worldclim_bio_my_sites.csv"), row.names = FALSE)
print(bio_at_sites[, c("site_id", "igbp", "BIO1", "BIO12", "BIO4", "BIO15")], row.names = FALSE)

# ---- Monthly normals (mean temperature and precipitation) ----------------------
monthly <- list()
for (v in c("tavg", "prec")) {
  say("Downloading monthly ", v)
  r <- worldclim_global(var = v, res = res_min, path = d)
  vals <- extract(r, pts, ID = FALSE)
  names(vals) <- sprintf("%02d", seq_len(12))
  long <- data.frame(site_id = rep(sites$site_id, each = 12),
                     month   = rep(1:12, times = nrow(sites)),
                     value   = as.vector(t(as.matrix(vals))))
  names(long)[3] <- v
  monthly[[v]] <- long
}
normals <- merge(monthly$tavg, monthly$prec, by = c("site_id", "month"))
write.csv(normals, file.path(d, "worldclim_monthly_normals_my_sites.csv"), row.names = FALSE)

say("Done. Files in ", d,
    "\n    BIO1 = mean annual temperature (°C), BIO12 = annual precipitation (mm),",
    "\n    BIO4 = temperature seasonality, BIO15 = precipitation seasonality.",
    "\n    Question: are your tower years warmer or wetter than the 1970–2000 normal?")
