test_that("apply_layer caps and floors correctly", {
  expect_equal(apply_layer(12, 5, 5), 5)   # loss above top of layer
  expect_equal(apply_layer(7, 5, 5), 2)    # loss inside layer
  expect_equal(apply_layer(3, 5, 5), 0)    # loss below attachment
  expect_equal(apply_layer(c(3, 7, 12), 5, 5), c(0, 2, 5))
})

test_that("index_losses reproduces the notes advanced burning cost basis", {
  # From Reinsurance Analytics Table 8: 2% inflation, exposure growth to 150.
  # A flat 2% per-year inflation reproduces the constant-rate result.
  losses <- data.frame(year = c(2021, 2021), loss = c(12, 9.5),
                       line_of_business = c("x", "x"))
  exposure <- data.frame(year = 2021:2026,
                         exposure = c(120, 120, 130, 140, 145, 150))
  inflation <- data.frame(year = 2021:2026, inflation = rep(0.02, 6))
  params <- list(valuation_year = 2026)

  out <- index_losses(losses, exposure, inflation, params)
  # 12 * 1.02^5 * (150/120) = 13.25 * 1.25 = 16.56 (to 2 dp)
  expect_equal(round(out$loss_indexed[1], 2), 16.56)
})

test_that("inflation_factor compounds a per-year rate vector", {
  inflation <- data.frame(year = 2021:2026,
                          inflation = c(0.02, 0.03, 0.025, 0.04, 0.03, 0.035))
  # A 2023 loss revalued to 2025 accrues the 2024 and 2025 rates only.
  expect_equal(inflation_factor(inflation, 2023, 2025), 1.04 * 1.03)
  # Same year means no inflation.
  expect_equal(inflation_factor(inflation, 2025, 2025), 1)
  # A missing rate is reported clearly.
  expect_error(inflation_factor(inflation, 2019, 2026), "Missing inflation rate")
})
