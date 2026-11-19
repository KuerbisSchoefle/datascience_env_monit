library(readr)
library(dplyr)

keep <- c("TIMESTAMP_START", "TIMESTAMP_END", "TA_F", "SW_IN_F", "VPD_F", "P_F",
          "NETRAD", "G_F_MDS", "H_F_MDS", "H_F_MDS_QC", "LE_F_MDS", "LE_F_MDS_QC",
          "NEE_VUT_REF", "NEE_VUT_REF_QC", "GPP_NT_VUT_REF", "RECO_NT_VUT_REF")

zip_file <- list.files("data/raw", pattern = "\\.zip$", full.names = TRUE)[1]
hh_name  <- grep("FLUXMET_HH", unzip(zip_file, list = TRUE)$Name, value = TRUE)
unzip(zip_file, files = hh_name, exdir = "data/raw/unzipped")

hh <- read_csv(file.path("data/raw/unzipped", hh_name),
               na = "-9999",
               col_select = any_of(keep),
               col_types = cols(TIMESTAMP_START = "c", TIMESTAMP_END = "c", .default = "d")) |>
  mutate(time = as.POSIXct(TIMESTAMP_START, format = "%Y%m%d%H%M", tz = "UTC"))

nrow(hh)
range(hh$time)
mean(hh$NEE_VUT_REF_QC == 0, na.rm = TRUE)   # share of measured NEE

(nrow(hh)-96)/9 # how many rows per year without leap year



### B3 Wrap it in a function -----------------------------------------
read_hh <- function(zip_file) {
  library(readr)
  library(dplyr)

  # define the columns that we want to use
  keep <- c("TIMESTAMP_START", "TIMESTAMP_END", "TA_F", "SW_IN_F", "VPD_F", "P_F",
            "NETRAD", "G_F_MDS", "H_F_MDS", "H_F_MDS_QC", "LE_F_MDS", "LE_F_MDS_QC",
            "NEE_VUT_REF", "NEE_VUT_REF_QC", "GPP_NT_VUT_REF", "RECO_NT_VUT_REF")

  # ZIP-Dateinamen extrahieren (z. B. "prefix_US-Bi2.zip")
  file_name <- tools::file_path_sans_ext(basename(zip_file))
  site_name <- strsplit(file_name, "_")[[1]][2]  # Zweiter Teil nach dem ersten "_"

  hh_name <- grep("FLUXMET_HH", unzip(zip_file, list = TRUE)$Name, value = TRUE)

  unzip(zip_file, files = hh_name, exdir = "data/raw/unzipped")

  # read in csv
  hh_all <- read_csv(file.path("data/raw/unzipped", hh_name),
                     na = "-9999",
                     col_select = any_of(keep),
                     col_types = cols(TIMESTAMP_START = "c", TIMESTAMP_END = "c", .default = "d")) |>
    mutate(time = as.POSIXct(TIMESTAMP_START, format = "%Y%m%d%H%M", tz = "UTC")) %>%
    mutate(site = site_name)  # site-Kürzel basierend auf dem ZIP-Dateinamen hinzufügen

  return(hh_all)
}

	# Get all zip archives
	zip_files <- list.files("data/raw", pattern = "\\.zip$", full.names = TRUE)
	# Apply `read_hh` to each archive and combine the results
	hh_all <- lapply(zip_files, read_hh) |> bind_rows()


