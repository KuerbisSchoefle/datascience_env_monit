# block5_sites.R — your five towers, shared by all Block 5 scripts
# Environmental Monitoring and Data Analysis · Block 5 · University of Freiburg
#
# Every Block 5 script starts with source("scripts/block5/block5_sites.R").
# Set your student number ONCE here (or pass it on the command line:
#   Rscript scripts/block5/04_soilgrids.R 07).
# Run all scripts from your project folder (the one with data/ and scripts/).

# ---- Your settings ------------------------------------------------------------
my_student <- "07"     # your student number from tower_sets_block4.csv
my_sites   <- NULL     # or pick sites yourself, e.g. c("DE-Hai", "FR-Hes")
tower_csv  <- "tower_sets_block4.csv"   # from ILIAS (folder DATA), same file as Block 4

# A student number on the command line wins
cl_args <- commandArgs(trailingOnly = TRUE)
if (length(cl_args) >= 1 && grepl("^[0-9]+$", cl_args[1])) my_student <- cl_args[1]

# ---- Read the tower set -------------------------------------------------------
get_my_sites <- function() {
  if (!file.exists(tower_csv)) {
    stop(tower_csv, " not found in ", getwd(), ".\n",
         "Download it from ILIAS (folder DATA) into your project folder.", call. = FALSE)
  }
  towers <- read.csv(tower_csv, colClasses = "character", encoding = "UTF-8")
  if (!is.null(my_sites)) {
    sites <- towers[towers$site_id %in% my_sites, ]
    missing <- setdiff(my_sites, sites$site_id)
    if (length(missing) > 0) stop("Not in ", tower_csv, ": ", paste(missing, collapse = ", "), call. = FALSE)
  } else {
    number <- sprintf("%02d", as.integer(my_student))
    sites  <- towers[sprintf("%02d", as.integer(towers$student_no)) == number, ]
  }
  if (nrow(sites) == 0) stop("No towers found for student ", my_student, call. = FALSE)
  keep  <- c("site_id", "site_name", "country", "continent", "igbp", "lat", "lon",
             "first_year", "last_year")
  sites <- sites[!duplicated(sites$site_id), keep]
  sites$lat        <- as.numeric(sites$lat)
  sites$lon        <- as.numeric(sites$lon)
  sites$first_year <- as.integer(sites$first_year)
  sites$last_year  <- as.integer(sites$last_year)
  rownames(sites) <- NULL
  sites
}

# Folder for one dataset: data/external/<name>  (data/ is in your .gitignore)
out_dir <- function(name) {
  d <- file.path("data", "external", name)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

say <- function(...) cat("\n==> ", ..., "\n", sep = "")

sites <- get_my_sites()
say("Your towers:")
print(sites[, c("site_id", "igbp", "country", "lat", "lon", "first_year", "last_year")],
      row.names = FALSE)
