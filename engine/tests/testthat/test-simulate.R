test_that("simulate_annual_losses returns one element per simulated year", {
  freq <- list(type = "poisson", params = list(lambda = 1.4), expected = 1.4)
  sampler <- function(n) rep(10, n)   # deterministic severity for counting
  sims <- simulate_annual_losses(freq, sampler, n_sims = 1000, seed = 7)
  expect_length(sims, 1000)
  # Mean count per year should be close to lambda = 1.4.
  mean_count <- mean(vapply(sims, length, integer(1)))
  expect_true(abs(mean_count - 1.4) < 0.15)
})

test_that("simulated total loss mean matches frequency times severity mean", {
  freq <- list(type = "poisson", params = list(lambda = 2), expected = 2)
  sampler <- function(n) rep(5, n)
  sims <- simulate_annual_losses(freq, sampler, n_sims = 20000, seed = 3)
  totals <- vapply(sims, sum, numeric(1))
  expect_true(abs(mean(totals) - 2 * 5) < 0.2)   # E[N]*E[X] = 10
})
