test_that("apply_layer caps and floors correctly", {
  expect_equal(apply_layer(12, 5, 5), 5)   # loss above top of layer
  expect_equal(apply_layer(7, 5, 5), 2)    # loss inside layer
  expect_equal(apply_layer(3, 5, 5), 0)    # loss below attachment
  expect_equal(apply_layer(c(3, 7, 12), 5, 5), c(0, 2, 5))
})

test_that("burning_cost applies the layer's aggregate deductible and limit", {
  # Two years, two losses each, all indexed = raw (inflation handled elsewhere).
  losses <- data.frame(
    year = c(2021, 2021, 2022, 2022),
    loss = c(12, 9, 20, 8))
  losses$loss_indexed <- losses$loss
  # Flat exposure so the on-levelling factor is 1 and the aggregates are clean.
  exposure <- data.frame(year = 2021:2023, exposure = c(100, 100, 100))
  vy <- 2023

  # Layer 5 xs 5: per-loss recoveries are 5, 4 (2021) and 5, 3 (2022),
  # so the raw annual aggregates are 9 and 8 (mean 8.5).
  base <- burning_cost(losses, data.frame(
    deductible = 5, cover = 5, aad = 0, aal = 0), exposure, vy)
  expect_equal(base$bc_advanced, 8.5)

  # An AAD of 6 removes the first 6 of each year: 3 and 2 (mean 2.5).
  with_aad <- burning_cost(losses, data.frame(
    deductible = 5, cover = 5, aad = 6, aal = 0), exposure, vy)
  expect_equal(with_aad$bc_advanced, 2.5)

  # An AAL of 8 caps each year at 8: 8 and 8 (mean 8).
  with_aal <- burning_cost(losses, data.frame(
    deductible = 5, cover = 5, aad = 0, aal = 8), exposure, vy)
  expect_equal(with_aal$bc_advanced, 8)
})

test_that("burning_cost on-levels to the forward book by exposure", {
  # One 2021 loss of 12, trended 2% per year to 2026 and on-levelled for the
  # book growing 120 -> 150. Inflation scales the loss size, exposure scales the
  # year's layer loss (the volume channel), reproducing Reinsurance Analytics
  # Table 8: 12 * 1.02^5 * (150 / 120) = 13.25 * 1.25 = 16.56.
  losses <- data.frame(year = 2021, loss = 12)
  inflation <- data.frame(year = 2021:2026, inflation = rep(0.02, 6))
  exposure <- data.frame(year = 2021:2026, exposure = c(120, 120, 130, 140, 145, 150))
  losses <- index_losses(losses, exposure, inflation, list(valuation_year = 2026))

  bc <- burning_cost(losses, data.frame(deductible = 0, cover = 100, aad = 0, aal = 0),
                     exposure, 2026)
  expect_equal(round(bc$bc_advanced, 2), 16.56)
})

test_that("burning_cost counts zero-loss years in the denominator", {
  # Losses in 2021 and 2023 only; 2022 is an observed year with no losses.
  losses <- data.frame(year = c(2021, 2023), loss = c(10, 20))
  losses$loss_indexed <- losses$loss
  exposure <- data.frame(year = 2021:2023, exposure = c(100, 100, 100))
  bc <- burning_cost(losses, data.frame(deductible = 0, cover = 100, aad = 0, aal = 0),
                     exposure, 2023)
  # Three observed years, 2022 contributing 0: (10 + 0 + 20) / 3 = 10,
  # not (10 + 20) / 2 = 15.
  expect_equal(bc$bc_advanced, 10)
})

test_that("burning_cost on-levelling never breaches the AAL", {
  # One 2021 loss of 8 to a 10 xs 0 layer with an AAL of 5; the book grows
  # 120 -> 150 (exposure factor 1.25). On-levelling scales the volume BEFORE the
  # cap: 8 * 1.25 = 10, then the AAL of 5 binds -> 5. It must never exceed 5.
  losses <- data.frame(year = 2021, loss = 8)
  losses$loss_indexed <- losses$loss
  exposure <- data.frame(year = c(2021, 2026), exposure = c(120, 150))
  bc <- burning_cost(losses, data.frame(deductible = 0, cover = 10, aad = 0, aal = 5),
                     exposure, 2026)
  expect_equal(bc$bc_advanced, 5)
  expect_lte(bc$bc_advanced, 5)
})

test_that("index_losses trends losses for inflation only, not exposure", {
  # Exposure must not change the loss size: only the 2% inflation applies.
  losses <- data.frame(year = c(2021, 2021), loss = c(12, 9.5),
                       line_of_business = c("x", "x"))
  exposure <- data.frame(year = 2021:2026,
                         exposure = c(120, 120, 130, 140, 145, 150))
  inflation <- data.frame(year = 2021:2026, inflation = rep(0.02, 6))
  params <- list(valuation_year = 2026)

  out <- index_losses(losses, exposure, inflation, params)
  # 12 * 1.02^5 = 13.25 (to 2 dp); the 150/120 exposure growth is NOT applied.
  expect_equal(round(out$loss_indexed[1], 2), 13.25)
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
