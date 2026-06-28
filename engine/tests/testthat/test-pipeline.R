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
  openxlsx::addWorksheet(wb, "inflation")
  openxlsx::writeData(wb, "inflation", data.frame(
    year = 2021:2025, inflation = rep(0, 5)))   # zero inflation to match Table 13
  openxlsx::addWorksheet(wb, "general inputs")
  # splice_threshold = modelling_threshold collapses the body, giving the pure
  # Pareto model the notes use, so the result must match Table 13.
  openxlsx::writeData(wb, "general inputs", data.frame(
    key = c("modelling_threshold",
            "splice_threshold", "frequency_model", "n_simulations",
            "valuation_year", "loading_ev", "loading_sd", "var_level"),
    value = c("5", "5", "poisson", "200000", "2025",
              "0.1", "0.2", "0.99")))
  openxlsx::saveWorkbook(wb, path)

  # The contract is supplied by the caller (dashboard or, here, the test); it is
  # no longer a workbook sheet. These are the three notes Table 13 layers.
  contract <- data.frame(
    deductible = c(5, 10, 20), cover = c(5, 10, 10),
    aad = 0, aal = 0)

  res <- run_pricing(path, contract = contract, seed = 99)$results
  # Table 13 expected sums: 4.56, 4.01, 2.12 (within simulation tolerance).
  expect_true(abs(res$expected_loss[1] - 4.56) < 0.15)
  expect_true(abs(res$expected_loss[2] - 4.01) < 0.15)
  expect_true(abs(res$expected_loss[3] - 2.12) < 0.15)
  # Simulated mean should track the closed-form oracle closely.
  expect_true(all(abs(res$oracle_delta) / res$oracle < 0.03))
})

test_that("frequency window excludes the prospective valuation year", {
  # 6 losses above mt=5 over 3 observed years (2021-2023) -> lambda = 2.0.
  # Exposure carries 2024 (valuation year) with no losses; it must not dilute.
  path <- tempfile(fileext = ".xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "losses")
  openxlsx::writeData(wb, "losses", data.frame(
    year = c(2021, 2021, 2022, 2023, 2023, 2023),
    loss = c(8, 9, 10, 7, 11, 13), line_of_business = "fire"))
  openxlsx::addWorksheet(wb, "exposure")
  openxlsx::writeData(wb, "exposure", data.frame(
    year = 2021:2024, exposure = rep(100, 4)))
  openxlsx::addWorksheet(wb, "inflation")
  openxlsx::writeData(wb, "inflation", data.frame(
    year = 2021:2024, inflation = rep(0, 4)))
  openxlsx::addWorksheet(wb, "general inputs")
  openxlsx::writeData(wb, "general inputs", data.frame(
    key = c("modelling_threshold",
            "splice_threshold", "frequency_model", "n_simulations",
            "valuation_year", "loading_ev", "loading_sd", "var_level"),
    value = c("5", "5", "poisson", "1000", "2024",
              "0.1", "0.2", "0.99")))
  openxlsx::saveWorkbook(wb, path)

  res <- run_pricing(path, seed = 1)   # default contract; frequency is unaffected
  expect_equal(res$fit_frequency$expected, 2.0)   # 6/3, not 6/4
})

test_that("a growing book scales the projected frequency by exposure", {
  # Same 6 losses over 3 observed years (lambda 2.0), but the prospective book
  # (2024) is twice the observed average, so the expected frequency doubles.
  path <- tempfile(fileext = ".xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "losses")
  openxlsx::writeData(wb, "losses", data.frame(
    year = c(2021, 2021, 2022, 2023, 2023, 2023),
    loss = c(8, 9, 10, 7, 11, 13), line_of_business = "fire"))
  openxlsx::addWorksheet(wb, "exposure")
  openxlsx::writeData(wb, "exposure", data.frame(
    year = 2021:2024, exposure = c(100, 100, 100, 200)))   # forward book = 2x
  openxlsx::addWorksheet(wb, "inflation")
  openxlsx::writeData(wb, "inflation", data.frame(
    year = 2021:2024, inflation = rep(0, 4)))
  openxlsx::addWorksheet(wb, "general inputs")
  openxlsx::writeData(wb, "general inputs", data.frame(
    key = c("modelling_threshold", "splice_threshold",
            "frequency_model", "n_simulations", "valuation_year",
            "loading_ev", "loading_sd", "var_level"),
    value = c("5", "5", "poisson", "1000", "2024",
              "0.1", "0.2", "0.99")))
  openxlsx::saveWorkbook(wb, path)

  res <- run_pricing(path, seed = 1)
  expect_equal(res$fit_frequency$expected, 4.0)   # 2.0 observed rate x 2.0 growth
})

test_that("dashboard-style overrides drive a data-only workbook", {
  # Workbook carries only the data parameters; modelling choices come as overrides.
  path <- tempfile(fileext = ".xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "losses")
  openxlsx::writeData(wb, "losses", data.frame(
    year = c(2021, 2021, 2023, 2024, 2024, 2024, 2025),
    loss = c(12, 9.5, 18, 13, 7, 11, 14), line_of_business = "fire"))
  openxlsx::addWorksheet(wb, "exposure")
  openxlsx::writeData(wb, "exposure", data.frame(
    year = 2021:2025, exposure = rep(100, 5)))
  openxlsx::addWorksheet(wb, "inflation")
  openxlsx::writeData(wb, "inflation", data.frame(
    year = 2021:2025, inflation = rep(0, 5)))
  openxlsx::addWorksheet(wb, "general inputs")
  openxlsx::writeData(wb, "general inputs", data.frame(
    key = "valuation_year", value = "2025"))
  openxlsx::saveWorkbook(wb, path)

  contract <- data.frame(
    deductible = c(5, 10, 20), cover = c(5, 10, 10),
    aad = 0, aal = 0)
  overrides <- list(modelling_threshold = 5, splice_threshold = 5,
                    frequency_model = "poisson", n_simulations = 200000,
                    loading_ev = 0.1, loading_sd = 0.2, var_level = 0.99)
  res <- run_pricing(path, overrides = overrides, contract = contract,
                     seed = 99)$results
  # Same as the notes Table 13 since overrides reproduce that configuration.
  expect_true(abs(res$expected_loss[1] - 4.56) < 0.15)
  expect_true(abs(res$expected_loss[3] - 2.12) < 0.15)
})

test_that("resolve_settings defaults the modelling threshold to the smallest loss", {
  params <- list(valuation_year = 2026L)   # no modelling_threshold in the workbook
  losses <- c(8, 6, 12, 6, 30)

  # Default: the smallest historical loss, so the model includes every loss.
  expect_equal(resolve_settings(params, losses = losses)$modelling_threshold, 6)

  # A workbook modelling_threshold still wins over the default.
  params_mt <- c(params, list(modelling_threshold = 9))
  expect_equal(resolve_settings(params_mt, losses = losses)$modelling_threshold, 9)

  # A dashboard override wins over everything.
  expect_equal(
    resolve_settings(params_mt, overrides = list(modelling_threshold = 4),
                     losses = losses)$modelling_threshold, 4)
})
