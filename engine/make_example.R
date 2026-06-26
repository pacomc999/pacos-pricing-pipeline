# Writes the top-level input.xlsx template: a richer dataset that populates both
# the lognormal body (losses 5 to 15) and the Pareto tail (losses above 15), so
# the demo exercises the full spliced severity. Layers span body, splice, tail.
# This file lives in engine/, so the workbook is written one level up (..).
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
openxlsx::addWorksheet(wb, "parameters")
openxlsx::writeData(wb, "parameters", data.frame(
  key = c("reporting_threshold", "loss_inflation_pa", "modelling_threshold",
          "splice_threshold", "frequency_model", "n_simulations",
          "valuation_year", "loading_ev", "loading_sd", "var_level"),
  value = c("5", "0.03", "5", "15", "poisson", "200000", "2026",
            "0.1", "0.2", "0.99")
))
openxlsx::addWorksheet(wb, "contract")
openxlsx::writeData(wb, "contract", data.frame(
  deductible = c(5, 10, 20), cover = c(5, 10, 20),
  n_reinstatements = c(999, 999, 999), reinstatement_cost = c(0, 0, 0),
  aad = c(0, 0, 0), aal = c(0, 0, 0)
))
openxlsx::saveWorkbook(wb, "../input.xlsx", overwrite = TRUE)
cat("Wrote input.xlsx\n")
