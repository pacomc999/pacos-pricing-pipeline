# Source app.R to get build_results_table. Sourcing builds the shinyApp object
# but does not launch a server, so this is safe inside tests.
source(normalizePath(file.path(getwd(), "..", "..", "app.R")), local = TRUE)

test_that("build_results_table rounds and renames for display", {
  priced <- data.frame(deductible = 5, cover = 5, expected_loss = 4.5512,
                       sd_loss = 6.1, var = 20, tvar = 25, rol = 1.0,
                       premium_ev = 5.006, premium_sd = 5.8,
                       oracle = 4.55, oracle_delta = 0.0012)
  tbl <- build_results_table(priced)
  expect_true("Expected loss" %in% names(tbl))
  expect_equal(tbl[["Expected loss"]][1], 4.55)   # rounded to 2 dp
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
