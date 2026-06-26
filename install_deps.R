# Installs every package the pipeline needs. Run once after cloning.
options(repos = c(CRAN = "https://cran.r-project.org"))
pkgs <- c("shiny", "actuar", "fitdistrplus", "readxl", "openxlsx", "ggplot2", "testthat")
to_install <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(to_install) > 0) install.packages(to_install)
