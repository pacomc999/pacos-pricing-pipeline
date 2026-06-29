# Writes the top-level input.xlsx template. The workbook itself is built by
# build_template_workbook() in R/template.R, which the dashboard's Generate
# template button also uses, so the script and the dashboard produce the same
# file. This script lives in engine/, so the workbook is written one level up.

source("R/template.R")

wb <- build_template_workbook()
openxlsx::saveWorkbook(wb, "../input.xlsx", overwrite = TRUE)
cat("Wrote input.xlsx\n")
