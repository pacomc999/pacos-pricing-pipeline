# Counts losses above the threshold for each year in the observation period.
annual_counts <- function(losses, years, threshold) {
  above <- losses[losses$loss > threshold, ]
  vapply(years, function(y) sum(above$year == y), integer(1))
}

# Fits a frequency distribution to annual counts. Poisson is the default.
fit_frequency <- function(counts, model = "poisson") {
  m <- mean(counts)
  v <- stats::var(counts)
  if (model == "poisson") {
    list(type = "poisson", params = list(lambda = m), expected = m)
  } else if (model == "negbin") {
    # Method of moments: var = mean * (1 + beta), size r = mean^2 / (var - mean).
    if (v <= m) stop("Negative Binomial needs variance greater than mean.")
    size <- m^2 / (v - m)
    list(type = "negbin", params = list(size = size, mu = m), expected = m)
  } else if (model == "binomial") {
    # Method of moments for Binomial: p = 1 - var/mean, n = mean / p.
    if (v >= m) stop("Binomial needs variance smaller than mean.")
    p <- 1 - v / m
    n <- round(m / p)
    list(type = "binomial", params = list(size = n, prob = p), expected = n * p)
  } else {
    stop("Unknown frequency model: ", model)
  }
}

# Draws n simulated annual counts from a fitted frequency distribution.
sample_frequency <- function(fit, n) {
  p <- fit$params
  switch(fit$type,
    poisson  = stats::rpois(n, p$lambda),
    negbin   = stats::rnbinom(n, size = p$size, mu = p$mu),
    binomial = stats::rbinom(n, size = p$size, prob = p$prob),
    stop("Unknown frequency type: ", fit$type)
  )
}
