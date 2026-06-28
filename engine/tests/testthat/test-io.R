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
  openxlsx::addWorksheet(wb, "inflation")
  openxlsx::writeData(wb, "inflation", data.frame(
    year = 2021:2025, inflation = c(0.02, 0.03, 0.025, 0.04, 0.03)
  ))
  openxlsx::addWorksheet(wb, "general inputs")
  openxlsx::writeData(wb, "general inputs", data.frame(
    key = c("modelling_threshold",
            "splice_threshold", "frequency_model", "n_simulations",
            "valuation_year", "loading_ev", "loading_sd", "var_level",
            "currency", "amount_units"),
    value = c("5", "15", "poisson", "100000", "2026",
              "0.1", "0.2", "0.99", "EUR", "millions")
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
  expect_true(is.integer(input$parameters$valuation_year))
  expect_true(is.integer(input$parameters$n_simulations))

  # Optional general inputs that label the figures.
  expect_equal(input$parameters$currency, "EUR")
  expect_equal(input$parameters$amount_units, "millions")

  # Inflation is a per-year table now, not a single parameter.
  expect_null(input$parameters$loss_inflation_pa)
  expect_equal(nrow(input$inflation), 5)
  expect_equal(input$inflation$inflation[2], 0.03)

  # The contract no longer lives in the workbook; the dashboard owns it.
  expect_null(input$contract)
})

test_that("read_input accepts a workbook with only the required data parameter", {
  path <- write_tmp_workbook()
  wb <- openxlsx::loadWorkbook(path)
  openxlsx::removeWorksheet(wb, "general inputs")
  openxlsx::addWorksheet(wb, "general inputs")
  # Only the required data parameter; modelling choices are set in the UI.
  openxlsx::writeData(wb, "general inputs", data.frame(
    key = "valuation_year", value = "2026"))
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)

  input <- read_input(path)
  expect_equal(input$parameters$valuation_year, 2026)
  expect_null(input$parameters$reporting_threshold)          # no longer read
  expect_true(is.na(input$parameters$modelling_threshold))   # optional, absent
  expect_true(is.na(input$parameters$frequency_model))
  expect_true(is.na(input$parameters$currency))              # optional, absent
  expect_true(is.na(input$parameters$amount_units))
})

test_that("read_input errors clearly on a missing required parameter", {
  path <- write_tmp_workbook()
  wb <- openxlsx::loadWorkbook(path)
  openxlsx::removeWorksheet(wb, "general inputs")
  openxlsx::addWorksheet(wb, "general inputs")
  openxlsx::writeData(wb, "general inputs",
    data.frame(key = "modelling_threshold", value = "5"))
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  expect_error(read_input(path), "Missing required parameter")
})

test_that("read_input errors clearly when a required sheet is missing", {
  path <- tempfile(fileext = ".xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "losses")
  openxlsx::writeData(wb, "losses",
    data.frame(year = 2021, loss = 10, line_of_business = "x"))
  openxlsx::saveWorkbook(wb, path)
  expect_error(read_input(path), "missing required sheet")
})
