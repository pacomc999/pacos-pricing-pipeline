# Writes the top-level input.xlsx template: a richer dataset that populates both
# the lognormal body (losses 5 to 15) and the Pareto tail (losses above 15), so
# the demo exercises the full spliced severity. The contract structure is set in
# the dashboard (not the workbook), so this template has four data sheets:
# losses, exposure, a per-year inflation sheet, and parameters. This file lives
# in engine/, so the workbook is written one level up.
wb <- openxlsx::createWorkbook()
openxlsx::addWorksheet(wb, "losses")
openxlsx::writeData(wb, "losses", data.frame(
  year = c(2021, 2021, 2021, 2022, 2022, 2023, 2023, 2023,
           2024, 2024, 2024, 2024, 2024, 2025, 2025, 2025, 2025),
  loss = c(6, 8, 22, 7, 35, 9, 11, 18,
           6, 7, 13, 28, 45, 8, 10, 16, 60),
  line_of_business = "fire"
))
openxlsx::addWorksheet(wb, "exposure")
openxlsx::writeData(wb, "exposure", data.frame(
  year = 2021:2026, exposure = c(120, 120, 130, 140, 145, 150)
))
openxlsx::addWorksheet(wb, "inflation")
# Loss inflation is a per-year rate, not a single constant. One row per year;
# the rate is the inflation experienced during that year and accrues on losses
# from earlier years when they are revalued to the valuation year.
openxlsx::writeData(wb, "inflation", data.frame(
  year = 2021:2026, inflation = c(0.02, 0.03, 0.025, 0.04, 0.03, 0.035)
))
openxlsx::addWorksheet(wb, "parameters")
# Only the data parameters live in the workbook now. The modelling choices
# (thresholds, frequency model, simulations, loadings) are set in the dashboard.
openxlsx::writeData(wb, "parameters", data.frame(
  key = c("reporting_threshold", "valuation_year"),
  value = c("5", "2026")
))
openxlsx::saveWorkbook(wb, "../input.xlsx", overwrite = TRUE)
cat("Wrote input.xlsx\n")
