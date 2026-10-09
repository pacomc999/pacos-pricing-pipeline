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
  # A single observed year has no variance, so the Negative Binomial says so
  # plainly instead of failing on a missing value.
  expect_error(fit_frequency(3, "negbin"), "variance greater than mean")
  # The Binomial is never fitted from the counts alone (that would estimate N).
  expect_error(fit_frequency(c(2, 2, 3, 2, 2), "binomial"), "number of insured risks")
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

test_that("fit_binomial_risks takes N from the exposure and p as claims over risk-years", {
  # 5 observed years with 100..140 risks and 2, 2, 3, 2, 2 claims; 150 risks
  # in the book being priced.
  counts <- c(2, 2, 3, 2, 2)
  fit <- fit_binomial_risks(counts, c(100, 110, 120, 130, 140), 150)
  expect_equal(fit$type, "binomial")
  expect_equal(fit$params$size, 150L)              # N is the forward exposure
  expect_equal(fit$params$prob, 11 / 600)          # pooled MLE
  expect_equal(fit$expected, 150 * 11 / 600)
  # N never moves with the data: a different set of counts changes p only.
  fit2 <- fit_binomial_risks(c(0, 1, 5, 0, 1), c(100, 110, 120, 130, 140), 150)
  expect_equal(fit2$params$size, 150L)
  # The forward mean matches the exposure-scaled Poisson rate exactly.
  pois <- scale_frequency(fit_frequency(counts, "poisson"), 150 / 120)
  expect_equal(fit$expected, pois$expected)
})

test_that("fit_binomial_risks stops when the exposure cannot be a count of risks", {
  # Not whole numbers (a monetary exposure): stop, naming the alternatives.
  expect_error(fit_binomial_risks(c(1, 2), c(120.5, 130), 150),
               "not whole numbers")
  expect_error(fit_binomial_risks(c(1, 2), c(120, 130), 150.2),
               "not whole numbers")
  # More claims than risks in a year: impossible under the model.
  expect_error(fit_binomial_risks(c(1, 4), c(5, 3), 6), "more claims than")
  # No valuation-year exposure: there is no forward number of risks.
  expect_error(fit_binomial_risks(c(1, 2), c(5, 6), numeric(0)),
               "valuation year")
})

test_that("observed_frequency_pmf averages Binomial(N_t, p) over the observed years", {
  fit <- fit_binomial_risks(c(1, 0, 2), c(4, 6, 8), 10)
  p <- 3 / 18
  expected <- (stats::dbinom(0:3, 4, p) + stats::dbinom(0:3, 6, p) +
               stats::dbinom(0:3, 8, p)) / 3
  expect_equal(observed_frequency_pmf(fit, 0:3), expected)
  expect_equal(sum(observed_frequency_pmf(fit, 0:8)), 1)
  # Poisson passes straight through to frequency_pmf.
  pois <- fit_frequency(c(2, 0, 1, 3, 1), "poisson")
  expect_equal(observed_frequency_pmf(pois, 0:3), frequency_pmf(pois, 0:3))
})

test_that("sample_frequency draws Binomial counts no larger than N", {
  set.seed(3)
  fit <- fit_binomial_risks(c(2, 1, 3), c(5, 5, 5), 4)
  s <- sample_frequency(fit, 20000)
  expect_true(all(s >= 0 & s <= 4))
  expect_equal(mean(s), 4 * 6 / 15, tolerance = 0.02)
})
