# Paco's Pricing Pipeline - run this when the double-click launcher is blocked.
#
# Some company computers block script files (start.vbs and start.bat), so a
# double-click does nothing at all. This file runs the tool through R itself,
# which those blocks do not touch. You need R installed (you already have it).
#
# HOW TO USE:
#   1. Open RStudio.
#   2. File > Open File... and pick this file ("Run in RStudio.R").
#   3. Click the "Source" button at the top right of the editor (or press
#      Ctrl+Shift+S). A browser tab opens with the dashboard.
#   To stop the tool, click "Shut down" in the dashboard or close the browser tab.
#
# No console window, no .bat, no .vbs. Everything runs inside RStudio.

# Find the folder this file lives in, so we can reach the engine folder next to
# it. This works both when the file is Sourced from the RStudio editor and when
# it is run with source("Run in RStudio.R") from the console.
find_this_folder <- function() {
  # When run via source(), each call frame carries the file path in $ofile.
  for (i in rev(seq_len(sys.nframe()))) {
    ofile <- sys.frame(i)$ofile
    if (!is.null(ofile)) return(dirname(normalizePath(ofile, winslash = "/")))
  }
  # When opened in the RStudio editor, ask RStudio for the open file's path.
  if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    path <- rstudioapi::getSourceEditorContext()$path
    if (!is.null(path) && nzchar(path)) {
      return(dirname(normalizePath(path, winslash = "/")))
    }
  }
  # Last resort: assume the working directory is the folder this file is in.
  getwd()
}

# Run everything from inside the engine folder, then restore the working
# directory afterwards so we leave the R session as we found it.
launch_pipeline <- function() {
  root <- find_this_folder()
  engine <- file.path(root, "engine")
  if (!dir.exists(engine)) {
    stop("Could not find the 'engine' folder next to this file. Make sure you ",
         "extracted the whole zip and kept the folders together.")
  }
  old_wd <- setwd(engine)
  on.exit(setwd(old_wd), add = TRUE)

  # Make sure there is a personal library we can write to (no admin rights
  # needed), and put it first on the search path. Same idea as install_deps.R.
  user_lib <- strsplit(Sys.getenv("R_LIBS_USER"), .Platform$path.sep)[[1]][1]
  if (!is.na(user_lib) && nzchar(user_lib)) {
    if (!dir.exists(user_lib)) dir.create(user_lib, recursive = TRUE)
    .libPaths(c(user_lib, .libPaths()))
  }

  # Use the public CRAN by default; allow an internal mirror via CRAN_MIRROR.txt.
  options(repos = c(CRAN = "https://cran.r-project.org"))
  if (file.exists("CRAN_MIRROR.txt")) {
    mirror <- trimws(readLines("CRAN_MIRROR.txt", warn = FALSE))[1]
    if (!is.na(mirror) && nzchar(mirror)) options(repos = c(CRAN = mirror))
  }

  # Install any missing runtime packages. We use stop() (not quit()) on failure
  # so a problem shows as a clear red message in the console instead of trying
  # to close RStudio.
  runtime <- c("shiny", "later", "fitdistrplus", "readxl", "openxlsx")
  missing <- runtime[!runtime %in% rownames(installed.packages())]
  if (length(missing) > 0) {
    message("Installing missing packages: ", paste(missing, collapse = ", "),
            " (the first run can take a few minutes)")
    try(install.packages(missing), silent = TRUE)
  }
  still_missing <- runtime[!runtime %in% rownames(installed.packages())]
  if (length(still_missing) > 0) {
    stop("Could not install these packages: ",
         paste(still_missing, collapse = ", "), ".\n",
         "This computer probably cannot reach CRAN (company firewall or proxy).\n",
         "Ask IT to allow https://cran.r-project.org, or put an internal CRAN\n",
         "mirror URL in a file named CRAN_MIRROR.txt inside the engine folder,\n",
         "then run this file again.")
  }

  # Create the top-level input.xlsx template on the first run only.
  if (!file.exists(file.path("..", "input.xlsx"))) source("make_example.R")

  message("Starting Paco's Pricing Pipeline. A browser tab will open shortly.")
  shiny::runApp(".", launch.browser = TRUE)
}

launch_pipeline()
