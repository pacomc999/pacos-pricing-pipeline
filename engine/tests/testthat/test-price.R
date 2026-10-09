test_that("annual_layer_loss aggregates per-loss recoveries, AAD and AAL", {
  # Two losses of 8, layer 5 xs 5 -> each contributes min(8-5,5)=3, total 6.
  losses <- c(8, 8)
  # No aggregate controls: the full aggregate of 6 is paid (no reinstatement cap).
  expect_equal(annual_layer_loss(losses, D = 5, C = 5, aad = 0, aal = 0), 6)
  # AAD of 2 removes the first 2 of aggregate: 6 - 2 = 4.
  expect_equal(annual_layer_loss(losses, D = 5, C = 5, aad = 2, aal = 0), 4)
  # AAL of 3 caps the aggregate at 3.
  expect_equal(annual_layer_loss(losses, D = 5, C = 5, aad = 0, aal = 3), 3)
})

test_that("layer_annual_losses returns one annual loss per simulated year", {
  # Three hand-built simulated years; layer 5 xs 5, no aggregate controls.
  sims <- list(c(8, 8), numeric(0), c(12, 3, 7))
  layer <- data.frame(deductible = 5, cover = 5, aad = 0, aal = 0)
  annual <- layer_annual_losses(sims, layer)
  # One value per year, each equal to annual_layer_loss for that year:
  # 2021: min(8-5,5)*2 = 6; 2022: no losses = 0; 2023: 5 + 0 + 2 = 7.
  expect_equal(length(annual), length(sims))
  expect_equal(annual, c(6, 0, 7))

  # Its mean is exactly the expected loss price_layer reports (one source).
  pp <- list(loading_ev = 0.1, loading_sd = 0.2, var_level = 0.99)
  expect_equal(price_layer(sims, layer, pp)$expected_loss, mean(annual))
})

test_that("price_layer expected loss converges to the validation oracle", {
  # Spliced severity with a real lognormal body; layer 5 xs 5 dips into it.
  set.seed(11)
  freq <- list(type = "poisson", params = list(lambda = 1.4), expected = 1.4)
  sev <- list(mt = 5, s = 15, weight = 0.3,
              lnorm = list(meanlog = log(8), sdlog = 0.4),
              pareto = list(x0 = 15, alpha = 1.5))
  sims <- simulate_annual_losses(freq, function(n) sample_severity(sev, n),
                                 n_sims = 200000, seed = 11)
  layer <- data.frame(deductible = 5, cover = 5, aad = 0, aal = 0)
  pp <- list(loading_ev = 0.1, loading_sd = 0.2, var_level = 0.99)
  priced <- price_layer(sims, layer, pp)
  oracle <- expected_layer_loss(freq, sev, 5, 5)   # numerical survival integral
  expect_true(abs(priced$expected_loss - oracle) / oracle < 0.02)
})

test_that("expected_shortfall averages exactly the worst (1 - q) of years", {
  # Plain case: 100 years 1..100, the worst 1% is the single year of 100 and
  # the worst 5% is the mean of 96..100.
  expect_equal(expected_shortfall(1:100, 0.99), 100)
  expect_equal(expected_shortfall(1:100, 0.95), mean(96:100))
  # Floating point in (1 - q) * n must not add an extra year: 100,000 years at
  # 0.99 is exactly 1,000 tail years.
  annual <- c(rep(0, 98999), rep(1, 1000), 5)
  expect_equal(expected_shortfall(annual, 0.99), (999 + 5) / 1000)
})

test_that("TVaR is not dragged down by a point mass of zero years", {
  # A rarely hit layer: 995 of 1,000 years at zero, 5 years with a loss. VaR99
  # is 0, but the TVaR must still be the mean of the worst 10 years (the five
  # losses plus five zeros), not the mean of every year.
  annual <- c(rep(0, 995), 8, 12, 15, 20, 14)
  row <- summarise_layer_losses(annual, list(cover = 20, deductible = 20),
    list(loading_ev = 0.1, loading_sd = 0.2, var_level = 0.99))
  expect_equal(row$var, 0)
  expect_equal(row$tvar, 69 / 10)
  expect_gt(row$tvar, row$expected_loss)
})

test_that("TVaR is not dragged down by a point mass at the full limit", {
  # 1,000 years: 950 at zero, 45 exhausting the layer exactly (50), 5 above it
  # (several losses in one year). VaR99 lands on the limit point mass; the
  # TVaR is the mean of the worst 10 years, 5 above the limit and 5 at it.
  annual <- c(rep(0, 950), rep(50, 45), 60, 70, 80, 90, 100)
  row <- summarise_layer_losses(annual, list(cover = 50, deductible = 50),
    list(loading_ev = 0.1, loading_sd = 0.2, var_level = 0.99))
  expect_equal(row$var, 50)
  expect_equal(row$tvar, (60 + 70 + 80 + 90 + 100 + 5 * 50) / 10)
})
