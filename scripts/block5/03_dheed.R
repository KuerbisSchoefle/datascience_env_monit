# 03_dheed.R — compound dry-and-hot extreme events that reached your towers
# Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg
#
# Dheed: a global database of connected compound dry and hot extreme events,
# derived from ERA5 at 0.25°, daily, 1950–2023 (Weynants et al. 2025, ESSD).
# A day in a grid cell is "hot" when daily Tmax is in the top 1 % for that cell,
# "dry" when a 30-, 90- or 180-day water balance is in the bottom 1 %.
# Hot + dry cells connected in space and time (≥ 3 days) form one labelled event.
#
# Two files from Zenodo (downloaded once):
#   LabelCube  (37 MB, Zarr): for every day and 0.25° cell, the label of the event
#              there (empty = no event). We read the ONE cell that contains your tower.
#   EventStats (14 MB, CSV):  one row per event, with statistics of the WHOLE event
#              (its total duration, area, intensity, ...). We add them by label.
#
# Why not just use the bounding boxes in EventStats? A box is a rectangle around an
# irregular event, so "tower inside the box" does not mean the event reached the
# tower. Worse: Dheed longitudes run 0–360°, and an event that crosses 0° (western
# Europe, West Africa) gets the box 0–359.75°, which contains every tower on Earth.
#
# No account needed. Needs: terra (reads the Zarr cube through GDAL).
# Output: data/external/dheed/dheed_events_my_sites.csv
#             one row per event that reached a tower: days AT THE TOWER + whole-event stats
#         data/external/dheed/dheed_daily_flags_my_sites.csv
#             one row per tower-day inside an event (for 09_merge)
# Cite: Weynants, M. et al. (2025) Dheed: an ERA5 based global database of compound
#       dry and hot extreme events from 1950 to 2023. ESSD 17, 6621.
#       https://doi.org/10.5194/essd-17-6621-2025 · data: https://doi.org/10.5281/zenodo.14884254

source(file.path("scripts", "block5", "block5_sites.R"))
library(terra)

record <- "https://zenodo.org/records/14884254/files"
stats_zip <- "MergedEventStats_landonly_int.csv.zip"
cube_name <- "mergedlabels_ranked_pot0.01_ne0.1_cmp_S1_T3_1950_2023.zarr"
dheed_last_year <- 2023
d <- out_dir("dheed")

download <- function(name, size) {
  path <- file.path(d, name)
  if (!file.exists(path)) {
    say("Downloading ", name, " (", size, ", once)")
    options(timeout = 900)
    part <- paste0(path, ".part")
    download.file(paste0(record, "/", name, "?download=1"), part, mode = "wb")
    file.rename(part, path)   # only a complete download gets the real name
  }
  path
}

# ---- 1. The label at the tower's grid cell, day by day ------------------------
cube_zip <- download(paste0(cube_name, ".zip"), "37 MB")
cube <- rast(paste0('ZARR:"/vsizip/', normalizePath(cube_zip), "/", cube_name, '":/labels'))
days <- as.Date(time(cube))
say("LabelCube: ", nlyr(cube), " days, ", format(days[1]), " to ", format(days[nlyr(cube)]))

flags <- list()
for (i in seq_len(nrow(sites))) {
  s <- sites[i, ]
  last <- min(s$last_year, dheed_last_year)
  if (s$first_year > dheed_last_year) {
    say(s$site_id, ": tower starts ", s$first_year, ", Dheed ends ", dheed_last_year, ". Skipped.")
    next
  }
  # Dheed longitudes run 0–360
  label <- as.numeric(extract(cube, cbind(s$lon %% 360, s$lat)))
  keep <- days >= as.Date(paste0(s$first_year, "-01-01")) & days <= as.Date(paste0(last, "-12-31")) &
          !is.na(label) & label > 0 & label < 1e18      # empty days are NA or the Zarr fill value
  note <- if (s$last_year > dheed_last_year) paste0(". Note: Dheed ends ", dheed_last_year,
                                                     ", the tower runs to ", s$last_year) else ""
  say(s$site_id, ": ", sum(keep), " event days at the tower in ", s$first_year, "–", last,
      " (", length(unique(label[keep])), " events)", note)
  if (any(keep)) {
    flags[[s$site_id]] <- data.frame(site_id = s$site_id, date = days[keep],
                                     dheed_event = TRUE, dheed_label = label[keep])
  }
}
daily <- if (length(flags) > 0) do.call(rbind, flags) else
  data.frame(site_id = character(), date = as.Date(character()),
             dheed_event = logical(), dheed_label = numeric())
rownames(daily) <- NULL

# ---- 2. Whole-event statistics from EventStats, joined by label ---------------
zip_file <- download(stats_zip, "14 MB")
csv_name <- grep("\\.csv$", unzip(zip_file, list = TRUE)$Name, value = TRUE)[1]
ev <- read.csv(unz(zip_file, csv_name), check.names = FALSE)

if (nrow(daily) > 0) {
  key <- interaction(daily$site_id, daily$dheed_label, drop = TRUE)
  at_tower <- data.frame(
    site_id            = tapply(daily$site_id, key, `[`, 1),
    label              = tapply(daily$dheed_label, key, `[`, 1),
    first_day_at_tower = as.Date(tapply(daily$date, key, min)),
    last_day_at_tower  = as.Date(tapply(daily$date, key, max)),
    days_at_tower      = as.vector(table(key)))
  events <- merge(at_tower, ev, by = "label", all.x = TRUE)
  events <- events[order(events$site_id, events$first_day_at_tower),
                   c("site_id", setdiff(names(events), "site_id"))]
} else {
  events <- cbind(site_id = character(), ev[0, ])
}
write.csv(events, file.path(d, "dheed_events_my_sites.csv"), row.names = FALSE)
write.csv(daily, file.path(d, "dheed_daily_flags_my_sites.csv"), row.names = FALSE)

if (nrow(events) > 0) {
  cat("\n(days_at_tower = at your tower; start/end/duration/area = the whole event)\n")
  show <- intersect(c("site_id", "label", "first_day_at_tower", "days_at_tower",
                      "start_time", "end_time", "duration", "area"), names(events))
  print(events[, show], row.names = FALSE)
}
say("Done. Files in ", d,
    "\n    Idea: compare NEE and GPP during an event with the same days in other years.")
