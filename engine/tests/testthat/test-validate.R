test_that("pareto_layer_ev reproduces the notes Table 13 severity layer costs", {
  alpha <- 1.184; x0 <- 5
  expect_equal(round(pareto_layer_ev(x0, alpha, 5, 5), 2), 3.25)
  expect_equal(round(pareto_layer_ev(x0, alpha, 10, 10), 2), 2.86)
  expect_equal(round(pareto_layer_ev(x0, alpha, 20, 10), 2), 1.51)
})

test_that("expected_layer_loss integrates the survival and matches the anchor", {
  # Body empty (s = mt) so the survival is pure Pareto and the oracle must
  # equal freq * pareto_layer_ev (Table 13 expected sums).
  freq <- list(expected = 1.4)
  sev <- list(mt = 5, s = 5, weight = 1, lnorm = NULL,
              pareto = list(x0 = 5, alpha = 1.184))
  # 1.4 * pareto_layer_ev(5, 1.184, 5, 5) = 1.4 * 3.2536 = 4.555 -> 4.56 (Table 13)
  expect_equal(round(expected_layer_loss(freq, sev, 5, 5), 2), 4.56)
  expect_equal(round(expected_layer_loss(freq, sev, 10, 10), 2),
               round(1.4 * pareto_layer_ev(5, 1.184, 10, 10), 2))
})

test_that("expected_layer_loss handles a layer that dips into the body", {
  # Layer 5 xs 5 sits below the splice s = 15, so the body drives most of it.
  freq <- list(expected = 2)
  sev <- list(mt = 5, s = 15, weight = 0.3,
              lnorm = list(meanlog = log(8), sdlog = 0.4),
              pareto = list(x0 = 15, alpha = 1.5))
  val <- expected_layer_loss(freq, sev, 5, 5)
  expect_true(val > 0 && is.finite(val))
})

test_that("lnorm_limited_ev is bounded above by u and below by the unlimited mean", {
  m <- log(3); s <- 0.5
  unlimited <- exp(m + s^2 / 2)
  lev <- lnorm_limited_ev(m, s, u = 4)
  expect_lt(lev, unlimited)
  expect_lt(lev, 4)
})
