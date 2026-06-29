test_that("fit_pareto_alpha reproduces the notes alpha of 1.184", {
  x <- c(12, 9.5, 18, 13, 7, 11, 14)   # losses above s = 5
  expect_equal(round(fit_pareto_alpha(x, x0 = 5), 3), 1.185)
})

test_that("fit_severity splits body and tail at s, conditional on mt", {
  # 2 is below mt and dropped; modelled = 9 values; tail (> 15) = 3 -> w = 3/9.
  loss_values <- c(2, 6, 7, 8, 9, 10, 12, 20, 30, 50)
  fit <- fit_severity(loss_values, mt = 5, s = 15)
  expect_equal(round(fit$weight, 3), round(3 / 9, 3))
  expect_equal(fit$pareto$x0, 15)
  expect_false(is.null(fit$lnorm))
  # n_body counts the losses in (mt, s]: 6, 7, 8, 9, 10, 12 -> 6.
  expect_equal(fit$n_body, 6)
})

test_that("severity_body_warning fires only for a sparse, active body", {
  # Inactive body (e.g. splice = mt) -> no warning.
  expect_null(severity_body_warning(0))
  # Enough points (>= n_min) -> no warning.
  expect_null(severity_body_warning(10))
  expect_null(severity_body_warning(25))
  # Sparse but active body -> a message mentioning the count.
  w <- severity_body_warning(2)
  expect_true(is.character(w))
  expect_match(w, "2 losses")
  # A single body loss is reported in the singular.
  expect_match(severity_body_warning(1), "1 loss")
  # The threshold is tunable.
  expect_null(severity_body_warning(4, n_min = 4))
  expect_false(is.null(severity_body_warning(4, n_min = 5)))
})

test_that("a splice at a threshold below all losses is a clean single Pareto", {
  # With s = mt sitting just under every loss, the body is empty: all mass is in
  # the Pareto (weight 1) and there is no point mass jumping up at the threshold.
  losses <- c(5, 6, 8, 10, 20, 50)
  mt <- min(losses) * (1 - 1e-6)
  fit <- fit_severity(losses, mt = mt, s = mt)
  expect_equal(fit$weight, 1)
  expect_null(fit$lnorm)
  # Survival stays at ~1 just above the threshold (no jump down to a lower value).
  expect_gt(severity_survival(fit, mt + 1e-9), 0.999)
})

test_that("severity_survival is 1 at mt, continuous at s, Pareto above s", {
  fit <- list(mt = 5, s = 15, weight = 0.3,
              lnorm = list(meanlog = log(8), sdlog = 0.4),
              pareto = list(x0 = 15, alpha = 1.5))
  expect_equal(severity_survival(fit, 5), 1)
  left  <- severity_survival(fit, 15 - 1e-6)
  right <- severity_survival(fit, 15 + 1e-6)
  expect_lt(abs(left - right), 1e-3)        # continuous at the splice point
  # At 30 = 2*s: w * (30/15)^-1.5 = 0.3 * 2^-1.5 = 0.106.
  expect_equal(round(severity_survival(fit, 30), 3), 0.106)
})

test_that("sample_severity draws exceed mt and match the tail weight", {
  set.seed(7)
  fit <- list(mt = 5, s = 15, weight = 0.3,
              lnorm = list(meanlog = log(8), sdlog = 0.4),
              pareto = list(x0 = 15, alpha = 1.5))
  d <- sample_severity(fit, 50000)
  expect_true(all(d > 5))
  expect_equal(round(mean(d > 15), 2), 0.30)
})

test_that("fit_severity errors when the splice is above every loss", {
  losses <- c(6, 8, 10, 12)   # all below s = 100, so the Pareto tail is empty
  expect_error(fit_severity(losses, mt = 5, s = 100), "above the splice")
})
