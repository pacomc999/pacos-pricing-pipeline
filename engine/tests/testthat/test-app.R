# Source app.R to get its helpers (and R/ modules). Sourcing builds the shinyApp object
# but does not launch a server, so this is safe inside tests.
source(normalizePath(file.path(getwd(), "..", "..", "app.R")), local = TRUE)

test_that("output_filename describes the run and stays filename-safe", {
  when <- as.POSIXct("2026-06-29 14:25:30", tz = "UTC")
  # A single line of business is used as is.
  expect_equal(output_filename("fire", 2025, when),
               "Pricing_fire_2025_20260629_142530.xlsx")
  # Spaces and punctuation are stripped; duplicates collapse to one token.
  expect_equal(output_filename(c("motor fleet", "motor fleet"), 2024, when),
               "Pricing_motorfleet_2024_20260629_142530.xlsx")
  # Many distinct lines collapse to a short token.
  expect_equal(output_filename(c("a", "b", "c", "d"), 2024, when),
               "Pricing_multiLOB_2024_20260629_142530.xlsx")
})

test_that("results_report rounds, renames and puts cover before deductible", {
  priced <- data.frame(deductible = 5, cover = 5, expected_loss = 4.5512,
                       sd_loss = 6.1, var = 20, tvar = 25,
                       premium_ev = 5.006, premium_sd = 5.8,
                       oracle = 4.55, oracle_delta = 0.0012)
  tbl <- results_report(priced)
  expect_equal(names(tbl)[1:2], c("Cover", "Deductible"))   # cover leads
  expect_true("Expected loss" %in% names(tbl))
  expect_equal(tbl[["Expected loss"]][1], 4.55)             # rounded to 2 dp
})

test_that("validation_report blanks the closed form for aggregate layers", {
  priced <- data.frame(deductible = 5, cover = 5, expected_loss = 4.5,
                       oracle = c(NA_real_), oracle_delta = c(NA_real_))
  bc <- data.frame(bc_advanced = 3.2)
  tbl <- validation_report(priced, bc)
  expect_equal(names(tbl)[1:2], c("Cover", "Deductible"))
  expect_true(is.na(tbl[["Closed form"]][1]))
  expect_match(tbl$Note[1], "no closed form")
})

test_that("build_contract_df keeps only the pricing columns in order", {
  rows <- data.frame(id = 1:2, deductible = c(5, 10), cover = c(5, 10),
                     aad = c(0, 0), aal = c(0, 0))
  ct <- build_contract_df(rows)
  expect_equal(names(ct), c("deductible", "cover", "aad", "aal"))
  expect_equal(ct$cover, c(5, 10))
})

test_that("validate_contract rejects empty and invalid programs", {
  empty <- build_contract_df(data.frame(
    deductible = numeric(0), cover = numeric(0),
    aad = numeric(0), aal = numeric(0)))
  expect_match(validate_contract(empty), "at least one")

  zero_cover <- data.frame(deductible = 5, cover = 0, aad = 0, aal = 0)
  expect_match(validate_contract(zero_cover), "cover")

  good <- data.frame(deductible = 5, cover = 5, aad = 0, aal = 0)
  expect_null(validate_contract(good))
})

test_that("build_structure_plot_data computes tops and labels, dropping bad rows", {
  ct <- data.frame(deductible = c(0, 5, 10),
                   cover = c(5, 5, 0),          # third row: cover 0 -> dropped
                   aad = c(NA, 5, NA),
                   aal = c(NA, 20, NA))
  d <- build_structure_plot_data(ct)
  expect_equal(nrow(d), 2)
  expect_equal(d$top, c(5, 10))                 # deductible + cover
  expect_equal(d$terms, c("5 xs 0", "5 xs 5"))
  expect_equal(d$aggregate[1], "AAL unlimited / AAD none")  # blank aggregates
  expect_equal(d$aggregate[2], "AAL 20 / AAD 5")
})

test_that("build_structure_plot_data returns empty when no layer has cover", {
  ct <- data.frame(deductible = numeric(0), cover = numeric(0),
                   aad = numeric(0), aal = numeric(0))
  expect_equal(nrow(build_structure_plot_data(ct)), 0)
})

test_that("unit_label joins currency and units, dropping whatever is missing", {
  expect_equal(unit_label("EUR", "millions"), "EUR millions")
  expect_equal(unit_label("EUR", NA), "EUR")
  expect_equal(unit_label(NA, "millions"), "millions")
  expect_equal(unit_label(NA, NA), "")
  expect_equal(unit_label(NULL, NULL), "")
  expect_equal(unit_label("", "millions"), "millions")
})
