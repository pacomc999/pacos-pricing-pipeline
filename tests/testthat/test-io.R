# Helper that writes a minimal valid workbook to a temp file.
write_tmp_workbook <- function() {
  path <- tempfile(fileext = ".xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "losses")
  openxlsx::writeData(wb, "losses", data.frame(
    year = c(2021, 2021, 2023),
    loss = c(12, 9.5, 18),
    line_of_business = c("fire", "fire", "fire")
  ))
  openxlsx::addWorksheet(wb, "exposure")
  openxlsx::writeData(wb, "exposure", data.frame(
    year = 2021:2025,
    exposure = c(120, 120, 130, 140, 145)
  ))
  openxlsx::addWorksheet(wb, "parameters")
  openxlsx::writeData(wb, "parameters", data.frame(
    key = c("reporting_threshold", "loss_inflation_pa", "modelling_threshold",
            "splice_threshold", "frequency_model", "n_simulations",
            "valuation_year", "loading_ev", "loading_sd", "var_level"),
    value = c("3", "0.02", "5", "15", "poisson", "100000", "2026",
              "0.1", "0.2", "0.99")
  ))
  openxlsx::addWorksheet(wb, "contract")
  openxlsx::writeData(wb, "contract", data.frame(
    deductible = c(5, 10), cover = c(5, 10),
    n_reinstatements = c(1, 1), reinstatement_cost = c(1, 1),
    aad = c(0, 0), aal = c(0, 0)
  ))
  openxlsx::saveWorkbook(wb, path)
  path
}

test_that("read_input parses all four sheets with correct types", {
  path <- write_tmp_workbook()
  input <- read_input(path)

  expect_equal(nrow(input$losses), 3)
  expect_true(is.numeric(input$losses$loss))

  expect_equal(input$parameters$frequency_model, "poisson")
  expect_equal(input$parameters$valuation_year, 2026)
  expect_equal(input$parameters$loss_inflation_pa, 0.02)

  expect_equal(nrow(input$contract), 2)
  expect_equal(input$contract$deductible[2], 10)
})
