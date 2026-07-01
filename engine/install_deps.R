# Installs the R packages the pipeline needs and reports clearly if it cannot.
# Safe to run repeatedly: it only installs what is missing.

# Use the public CRAN mirror by default so it runs without prompting.
options(repos = c(CRAN = "https://cran.r-project.org"))

# Optional internal mirror: put a mirror URL in CRAN_MIRROR.txt next to this
# file (useful when a company network blocks the public CRAN).
if (file.exists("CRAN_MIRROR.txt")) {
  mirror <- trimws(readLines("CRAN_MIRROR.txt", warn = FALSE))[1]
  if (!is.na(mirror) && nzchar(mirror)) options(repos = c(CRAN = mirror))
}

# Make sure there is a library we are allowed to write to. R is often installed
# under Program Files, whose library needs administrator rights, so a normal
# user cannot write there. R would normally fall back to a personal library, but
# it only offers that interactively; running non-interactively (as the launcher
# does) the install just fails with a "library is not writable" warning. So we
# create the personal library ourselves and put it first on the search path,
# which needs no admin rights. Later R sessions (the app) pick it up
# automatically once the folder exists.
user_lib <- strsplit(Sys.getenv("R_LIBS_USER"), .Platform$path.sep)[[1]][1]
if (!is.na(user_lib) && nzchar(user_lib)) {
  if (!dir.exists(user_lib)) dir.create(user_lib, recursive = TRUE)
  .libPaths(c(user_lib, .libPaths()))
}

# Packages the dashboard needs to run (later ships with shiny and is used for
# the self-shutdown timer). testthat is only for the test suite, so it is
# installed if possible but never blocks the app.
runtime <- c("shiny", "later", "fitdistrplus", "readxl", "openxlsx")
dev <- c("testthat")

missing <- function(pkgs) pkgs[!pkgs %in% rownames(installed.packages())]

to_install <- missing(c(runtime, dev))
if (length(to_install) > 0) {
  cat("Installing:", paste(to_install, collapse = ", "), "\n")
  try(install.packages(to_install), silent = TRUE)
}

# Verify the runtime packages actually made it. install.packages only warns on
# failure, so we re-check rather than trust it.
still_missing <- missing(runtime)
if (length(still_missing) > 0) {
  cat("\n=====================================================\n")
  cat(" SETUP PROBLEM: required packages are missing:\n")
  cat("    ", paste(still_missing, collapse = ", "), "\n\n")
  cat(" The dashboard cannot start without them.\n")
  cat(" Most likely cause: this computer cannot reach CRAN\n")
  cat(" (no internet, or a company firewall or proxy).\n\n")
  cat(" What to do:\n")
  cat("  - Ask IT to allow https://cran.r-project.org, or\n")
  cat("  - Point this tool at an internal CRAN mirror: create a file\n")
  cat("    named CRAN_MIRROR.txt next to start.bat containing the mirror\n")
  cat("    URL, then run start.bat again.\n")
  cat("=====================================================\n\n")
  quit(status = 1)
}

cat("All required packages are installed.\n")
