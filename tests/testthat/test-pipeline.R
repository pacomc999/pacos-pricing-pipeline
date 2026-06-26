test_that("run_pricing reproduces the notes Table 13 expected losses end to end", {
  # Build the notes example workbook in a temp file (inflation 0 to match Table 13).
  path <- tempfile(fileext = ".xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "losses")
  openxlsx::writeData(wb, "losses", data.frame(
    year = c(2021, 2021, 2023, 2024, 2024, 2024, 2025),
    loss = c(12, 9.5, 18, 13, 7, 11, 14), line_of_business = "fire"))
  openxlsx::addWorksheet(wb, "exposure")
  openxlsx::writeData(wb, "exposure", data.frame(
    year = 2021:2025, exposure = rep(100, 5)))
  openxlsx::addWorksheet(wb, "parameters")
  # splice_threshold = modelling_threshold collapses the body, giving the pure
  # Pareto model the notes use, so the result must match Table 13.
  openxlsx::writeData(wb, "parameters", data.frame(
    key = c("reporting_threshold", "loss_inflation_pa", "modelling_threshold",
            "splice_threshold", "frequency_model", "n_simulations",
            "valuation_year", "loading_ev", "loading_sd", "var_level"),
    value = c("5", "0", "5", "5", "poisson", "200000", "2025",
              "0.1", "0.2", "0.99")))
  openxlsx::addWorksheet(wb, "contract")
  openxlsx::writeData(wb, "contract", data.frame(
    deductible = c(5, 10, 20), cover = c(5, 10, 10),
    n_reinstatements = 999, reinstatement_cost = 0, aad = 0, aal = 0))
  openxlsx::saveWorkbook(wb, path)

  res <- run_pricing(path, seed = 99)$results
  # Table 13 expected sums: 4.56, 4.01, 2.12 (within simulation tolerance).
  expect_true(abs(res$expected_loss[1] - 4.56) < 0.15)
  expect_true(abs(res$expected_loss[2] - 4.01) < 0.15)
  expect_true(abs(res$expected_loss[3] - 2.12) < 0.15)
  # Simulated mean should track the closed-form oracle closely.
  expect_true(all(abs(res$oracle_delta) / res$oracle < 0.03))
})
