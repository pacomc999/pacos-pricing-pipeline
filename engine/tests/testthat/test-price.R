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
