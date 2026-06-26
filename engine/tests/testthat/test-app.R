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
