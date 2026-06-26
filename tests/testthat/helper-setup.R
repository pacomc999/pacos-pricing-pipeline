# Sources every module in R/ so tests can call the functions directly.
# testthat sets the working directory to tests/testthat, so the project
# root is two levels up.
.project_root <- normalizePath(file.path(getwd(), "..", ".."))
r_files <- list.files(file.path(.project_root, "R"), pattern = "[.]R$", full.names = TRUE)
for (f in r_files) source(f, local = FALSE)
