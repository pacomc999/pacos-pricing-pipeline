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
