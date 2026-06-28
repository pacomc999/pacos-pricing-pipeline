# Counts losses at or above the threshold for each year in the observation
# period. The threshold is inclusive, so a default set to the smallest loss
# counts every loss.
annual_counts <- function(losses, years, threshold) {
  above <- losses[losses$loss >= threshold, ]
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

# Scales a fitted frequency distribution's mean by a factor (e.g. to project the
# observed-period rate onto a larger or smaller prospective book). Poisson and
# Negative Binomial scale their mean parameter directly; Binomial scales the
# number of trials. A factor of 1 returns the fit unchanged.
scale_frequency <- function(fit, factor) {
  if (factor == 1) return(fit)
  switch(fit$type,
    poisson = {
      fit$params$lambda <- fit$params$lambda * factor
      fit$expected <- fit$params$lambda
    },
    negbin = {
      fit$params$mu <- fit$params$mu * factor
      fit$expected <- fit$params$mu
    },
    binomial = {
      fit$params$size <- max(1L, as.integer(round(fit$params$size * factor)))
      fit$expected <- fit$params$size * fit$params$prob
    },
    stop("Unknown frequency type: ", fit$type)
  )
  fit
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
