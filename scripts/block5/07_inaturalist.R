# 07_inaturalist.R — citizen-science species observations around your towers
# Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg
#
# iNaturalist: people photograph organisms, the community identifies them.
# "Research grade" = date, location, photo, and ≥ 2/3 of identifiers agree on a species.
# We use the public API (no account): all research-grade observations within
# radius_km of each tower. The API allows ~1 request per second; we wait 1 s.
#
# Things to keep in mind:
#   - Observations cluster where people are (roads, cities, trails): absence of a
#     record is NOT absence of the species.
#   - Every observation has its own licence (license_code); some have none.
#   - For a paper, download the same records via GBIF instead: a GBIF download
#     gets a DOI you can cite. https://www.gbif.org (dataset "iNaturalist Research-grade Observations")
#
# Packages: install.packages(c("httr2", "jsonlite"))
# Output:   data/external/inaturalist/<SITE>_inat.csv and inat_summary_my_sites.csv
# Cite:     iNaturalist contributors, iNaturalist (<year>). https://www.inaturalist.org,
#           accessed <date>. Or the GBIF download DOI.

source(file.path("scripts", "block5", "block5_sites.R"))
library(httr2)

radius_km   <- 5       # search radius around each tower
max_obs     <- 3000    # per tower, to keep it quick (raise it if you need everything)
iconic_taxa <- NULL    # e.g. "Plantae", or c("Aves", "Insecta"); NULL = all groups
d <- out_dir("inaturalist")

get_page <- function(s, id_above) {
  q <- list(lat = s$lat, lng = s$lon, radius = radius_km, quality_grade = "research",
            per_page = 200, order_by = "id", order = "asc", id_above = id_above)
  if (!is.null(iconic_taxa)) q$iconic_taxa <- paste(iconic_taxa, collapse = ",")
  request("https://api.inaturalist.org/v1/observations") |>
    req_url_query(!!!q) |>
    req_user_agent("EnvMon course, University of Freiburg") |>
    req_retry(max_tries = 4) |>
    req_perform() |>
    resp_body_json()
}
`%||%` <- function(a, b) if (is.null(a)) b else a

summary_rows <- list()
for (i in seq_len(nrow(sites))) {
  s <- sites[i, ]
  say(s$site_id, ": observations within ", radius_km, " km")
  recs <- list(); id_above <- 0; total <- NULL
  repeat {
    js <- get_page(s, id_above)
    if (length(js$results) == 0) break
    for (o in js$results) {
      tx <- o$taxon
      xy <- o$geojson$coordinates
      recs[[length(recs) + 1]] <- data.frame(
        site_id = s$site_id, id = o$id, observed_on = o$observed_on %||% NA,
        lon = if (length(xy) == 2) xy[[1]] else NA, lat = if (length(xy) == 2) xy[[2]] else NA,
        accuracy_m = o$positional_accuracy %||% NA,
        taxon = tx$name %||% NA, rank = tx$rank %||% NA,
        iconic_taxon = tx$iconic_taxon_name %||% NA,
        common_name = tx$preferred_common_name %||% NA,
        license = o$license_code %||% NA, url = o$uri %||% NA)
    }
    id_above <- js$results[[length(js$results)]]$id
    total <- total %||% js$total_results   # later pages count only what is left
    cat("   ", length(recs), "of", total, "\n")
    if (length(recs) >= max_obs || length(js$results) < 200) break
    Sys.sleep(1)
  }
  if (length(recs) == 0) { say(s$site_id, ": no research-grade observations"); next }
  obs <- do.call(rbind, recs)
  write.csv(obs, file.path(d, paste0(s$site_id, "_inat.csv")), row.names = FALSE)
  sp <- obs[obs$rank == "species", ]
  summary_rows[[s$site_id]] <- data.frame(
    site_id = s$site_id, n_obs = nrow(obs), n_species = length(unique(sp$taxon)),
    n_plant_species = length(unique(sp$taxon[which(sp$iconic_taxon == "Plantae")])),   # which(): skip NA
    first = min(obs$observed_on, na.rm = TRUE), last = max(obs$observed_on, na.rm = TRUE))
  Sys.sleep(1)
}
summ <- do.call(rbind, summary_rows)
write.csv(summ, file.path(d, "inat_summary_my_sites.csv"), row.names = FALSE)
print(summ, row.names = FALSE)
say("Done. Files in ", d,
    "\n    Compare n_species between towers with care: more observers ≠ more species.")
