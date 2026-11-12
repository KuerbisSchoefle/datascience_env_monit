# get_my_towers.R — download your five FLUXNET towers with the FLUXNET Shuttle
# Environmental Monitoring and Data Analysis · Block 4 · University of Freiburg
#
# R version of get_my_towers.py. Uses base R only (no packages needed).
# The FLUXNET Shuttle itself is a Python tool: this script finds Python on your
# computer, installs the Shuttle if needed and runs it for you.
#
# What it does
#   1. Reads your five site IDs from tower_sets_block4.csv (ILIAS), or uses my_sites below.
#   2. Installs the FLUXNET Shuttle into Python (if it is missing).
#   3. Makes a snapshot of all available FLUXNET data  -> data/snapshots/
#   4. Downloads your five zip files                   -> data/raw/
#   5. Checks each zip and writes data/raw/CITATIONS.txt with the citation of every site.
#
# How to run it (working directory = your project folder, the one with scripts/ and data/)
#   In Positron: set my_student below, then press Run (or source the file).
#   In a terminal: Rscript get_my_towers.R 07
#
# Needs: Python 3.9 or newer, Git (to install the Shuttle), internet, ~2-3 GB free disk space.

# ---- 1. Your settings -------------------------------------------------------
my_student   <- "07"       # your student number from tower_sets_block4.csv
my_sites     <- NULL       # or give sites yourself, e.g. c("DE-Hai", "FR-Hes"); then my_student is ignored
tower_csv    <- "tower_sets_block4.csv"
new_snapshot <- FALSE      # TRUE = make a fresh snapshot even if one exists

shuttle_source <- "git+https://github.com/fluxnet/shuttle.git"
snap_dir <- file.path("data", "snapshots")
raw_dir  <- file.path("data", "raw")

# A student number given on the command line (Rscript get_my_towers.R 07) wins
cl_args <- commandArgs(trailingOnly = TRUE)
if (length(cl_args) >= 1) my_student <- cl_args[1]

say  <- function(...) cat("\n==> ", ..., "\n", sep = "")
halt <- function(...) stop(paste0(...), call. = FALSE)

# ---- 2. Which sites? ---------------------------------------------------------
if (is.null(my_sites)) {
  if (!file.exists(tower_csv)) {
    halt(tower_csv, " not found in ", getwd(), ".\n",
         "Download it from ILIAS (folder DATA) into your project folder, or set my_sites.")
  }
  towers <- read.csv(tower_csv, colClasses = "character", encoding = "UTF-8")
  number <- sprintf("%02d", as.integer(my_student))
  mine   <- towers[sprintf("%02d", as.integer(towers$student_no)) == number, ]
  if (nrow(mine) == 0) halt("No towers found for student number ", number, " in ", tower_csv, ".")
  say("Tower set ", number, " (", mine$student_name[1], "):")
  for (i in seq_len(nrow(mine))) {
    cat(sprintf("    %-8s %-4s %s  %s  (%s-%s)\n", mine$site_id[i], mine$igbp[i], mine$country[i],
                mine$site_name[i], mine$first_year[i], mine$last_year[i]))
  }
  my_sites <- mine$site_id
}

# ---- 3. Find Python and the Shuttle -----------------------------------------
find_python <- function() {
  # Prefer the project's virtual environment from Block 1, then the system Python
  venv <- c(file.path(".venv", "bin", "python"), file.path(".venv", "Scripts", "python.exe"))
  cands <- list()
  for (v in venv) if (file.exists(v)) cands[[length(cands) + 1]] <- list(cmd = normalizePath(v), pre = character())
  for (p in c("python3", "python")) {
    w <- Sys.which(p)
    if (nzchar(w)) cands[[length(cands) + 1]] <- list(cmd = unname(w), pre = character())
  }
  if (.Platform$OS.type == "windows" && nzchar(Sys.which("py"))) {
    cands[[length(cands) + 1]] <- list(cmd = unname(Sys.which("py")), pre = "-3")
  }
  for (c in cands) {
    ok <- suppressWarnings(system2(c$cmd, c(c$pre, "-c",
            shQuote("import sys; print(sys.version_info >= (3, 9))")), stdout = TRUE, stderr = FALSE))
    if (length(ok) && identical(trimws(ok[1]), "True")) return(c)
  }
  halt("No Python 3.9 or newer found.\n",
       "Install Python from https://www.python.org (Windows: tick 'Add python.exe to PATH') and restart Positron.")
}

py <- find_python()
run_py <- function(args, ...) system2(py$cmd, c(py$pre, args), ...)
say("Using Python: ", py$cmd)

has_shuttle <- run_py(c("-c", shQuote("import fluxnet_shuttle")), stdout = FALSE, stderr = FALSE) == 0
if (has_shuttle) {
  say("FLUXNET Shuttle is already installed.")
} else {
  say("Installing the FLUXNET Shuttle (one time, takes a minute) ...")
  if (run_py(c("-m", "pip", "install", shQuote(shuttle_source))) != 0) {
    halt("Installing the Shuttle failed.\n",
         "  - Is Git installed? (run git --version in the terminal)\n",
         "  - On a system Python you may need a virtual environment: in the terminal run\n",
         "      python3 -m venv .venv   then run this script again (it uses .venv automatically).")
  }
}
shuttle <- function(...) run_py(c("-m", "fluxnet_shuttle.main", "--no-logfile", ...))

# ---- 4. Snapshot -----------------------------------------------------------
dir.create(snap_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(raw_dir,  recursive = TRUE, showWarnings = FALSE)

newest_snapshot <- function() {
  # Newest snapshot that actually lists sites (a failed run can leave an empty one)
  snaps <- sort(list.files(snap_dir, pattern = "^fluxnet_shuttle_snapshot_.*\\.csv$", full.names = TRUE),
                decreasing = TRUE)
  for (s in snaps) if (length(readLines(s, warn = FALSE)) > 1) return(s)
  NULL
}

snapshot <- if (new_snapshot) NULL else newest_snapshot()
if (!is.null(snapshot)) {
  say("Using existing snapshot ", basename(snapshot), " (set new_snapshot <- TRUE for a fresh one).")
} else {
  say("Making a snapshot of all available FLUXNET data ...")
  shuttle("listall", "-o", shQuote(snap_dir))
  snapshot <- newest_snapshot()
  if (is.null(snapshot)) {
    halt("The snapshot is empty: no data hub could be reached.\n",
         "  Check your internet connection and run the script again.")
  }
}

snap <- read.csv(snapshot, colClasses = "character", encoding = "UTF-8")
missing_sites <- setdiff(my_sites, snap$site_id)
if (length(missing_sites) > 0) {
  halt("Not in the snapshot: ", paste(missing_sites, collapse = " "),
       ". Check the site IDs, or set new_snapshot <- TRUE.")
}

# ---- 5. Download -------------------------------------------------------------
say("Downloading ", length(my_sites), " sites to ", raw_dir, "/ - large sites can take several minutes ...")
status <- shuttle("download", "-f", shQuote(snapshot), "-s", my_sites, "-o", shQuote(raw_dir), "--quiet")
if (status != 0) cat("\nThe download reported an error; checking what arrived ...\n")

# ---- 6. Check the zips and write citations ----------------------------------
say("Checking the downloaded files ...")
all_ok <- TRUE
citations <- character()
for (site in my_sites) {
  zips <- sort(list.files(raw_dir, pattern = paste0("_", site, "_FLUXNET_.*\\.zip$"), full.names = TRUE))
  if (length(zips) == 0) {
    cat(sprintf("    %-8s MISSING - run the script again, or ask for help on ILIAS\n", site))
    all_ok <- FALSE
    next
  }
  z <- zips[length(zips)]
  members <- tryCatch(utils::unzip(z, list = TRUE)$Name, error = function(e) NULL)
  if (is.null(members)) {
    cat(sprintf("    %-8s BROKEN ZIP - delete %s and run the script again\n", site, basename(z)))
    all_ok <- FALSE
    next
  }
  has_hh <- any(grepl("FLUXMET_HH", members))
  cat(sprintf("    %-8s %s  (%.0f MB)  %s\n", site, basename(z), file.size(z) / 1e6,
              if (has_hh) "ok" else "check: no FLUXMET_HH file inside"))
  cit <- snap$product_citation[match(site, snap$site_id)]
  citations <- c(citations, paste0(site, ": ", ifelse(is.na(cit) || cit == "", "citation not found in snapshot", cit)))
}

cit_file <- file.path(raw_dir, "CITATIONS.txt")
writeLines(c("Data citations for my towers (from the FLUXNET Shuttle snapshot)", "",
             paste0(citations, "\n"),
             "Also cite: Pastorello et al. (2020), Scientific Data 7, 225, https://doi.org/10.1038/s41597-020-0534-3"),
           cit_file, useBytes = TRUE)
cat("\n    Citations written to", cit_file, "\n")

if (all_ok) {
  say("Done. Next: Part B of the assignment - read one FLUXMET_HH file.")
  cat("    Keep data/ out of Git: it must be listed in your .gitignore.\n")
} else {
  halt("Some towers are missing or broken. Run the script again; existing files are re-downloaded.")
}
