test_that("annual_counts includes zero-loss years", {
  losses <- data.frame(year = c(2021, 2021, 2023, 2024, 2024, 2024, 2025),
                       loss = c(12, 9.5, 18, 13, 7, 11, 14))
  counts <- annual_counts(losses, years = 2021:2025, threshold = 5)
  expect_equal(counts, c(2, 0, 1, 3, 1))   # 2022 is a zero year
})

test_that("Poisson fit matches the notes lambda of 1.4", {
  counts <- c(2, 0, 1, 3, 1)
  fit <- fit_frequency(counts, "poisson")
  expect_equal(fit$type, "poisson")
  expect_equal(fit$expected, 1.4)
})

test_that("sample_frequency returns non-negative integers of correct length", {
  set.seed(1)
  fit <- fit_frequency(c(2, 0, 1, 3, 1), "poisson")
  s <- sample_frequency(fit, 1000)
  expect_length(s, 1000)
  expect_true(all(s >= 0))
  expect_equal(abs(mean(s) - 1.4) < 0.2, TRUE)
})

test_that("fit_frequency guards reject mis-specified distribution choices", {
  # Negative Binomial needs variance greater than mean (over-dispersion).
  expect_error(fit_frequency(c(1, 1, 1), "negbin"), "variance greater than mean")
  # Binomial needs variance smaller than mean (under-dispersion).
  expect_error(fit_frequency(c(1, 4, 9), "binomial"), "variance smaller than mean")
  # An unknown model name is rejected clearly.
  expect_error(fit_frequency(c(1, 2, 3), "weibull"), "Unknown frequency model")
})

test_that("sample_frequency rejects an unknown fit type", {
  expect_error(sample_frequency(list(type = "weibull", params = list()), 10),
               "Unknown frequency type")
})

test_that("frequency_pmf matches the fitted distribution and sums to one", {
  fit <- fit_frequency(c(2, 0, 1, 3, 1), "poisson")   # lambda 1.4
  expect_equal(frequency_pmf(fit, 0:3), stats::dpois(0:3, 1.4))
  # A PMF is non-negative and (over a wide enough support) sums to one.
  pmf <- frequency_pmf(fit, 0:50)
  expect_true(all(pmf >= 0))
  expect_equal(sum(pmf), 1, tolerance = 1e-6)
})

test_that("frequency_pmf rejects an unknown fit type", {
  expect_error(frequency_pmf(list(type = "weibull", params = list()), 0:3),
               "Unknown frequency type")
})

test_that("scale_frequency scales the mean of a Poisson fit", {
  fit <- fit_frequency(c(2, 0, 1, 3, 1), "poisson")   # lambda 1.4
  scaled <- scale_frequency(fit, 2)
  expect_equal(scaled$expected, 2.8)
  expect_equal(scaled$params$lambda, 2.8)
  # A factor of 1 leaves the fit unchanged.
  expect_equal(scale_frequency(fit, 1)$expected, 1.4)
})

test_that("exposure_frequency_factor compares forward book to observed average", {
  exposure <- data.frame(year = 2021:2024, exposure = c(100, 100, 100, 200))
  # Observed 2021-2023 average 100; forward (2024) book 200 -> factor 2.
  expect_equal(exposure_frequency_factor(exposure, 2021:2023, 2024), 2)
  # Missing forward exposure falls back to 1 (no scaling).
  expect_equal(exposure_frequency_factor(exposure, 2021:2023, 2099), 1)
})
