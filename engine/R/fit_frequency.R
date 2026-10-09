# Counts losses above the threshold for each year in the observation period.
# The threshold is strict, so the default sits just below the smallest loss to
# count every loss.
annual_counts <- function(losses, years, threshold) {
  above <- losses[losses$loss > threshold, ]
  vapply(years, function(y) sum(above$year == y), integer(1))
}

# Fits a frequency distribution to annual counts. Poisson is the default. The
# Binomial is not fitted here: it needs the exposure as a count of risks (see
# fit_binomial_risks), never a number of trials estimated from the counts.
fit_frequency <- function(counts, model = "poisson") {
  m <- mean(counts)
  v <- stats::var(counts)
  if (model == "poisson") {
    list(type = "poisson", params = list(lambda = m), expected = m)
  } else if (model == "negbin") {
    # Method of moments: var = mean * (1 + beta), size r = mean^2 / (var - mean).
    if (length(counts) < 2 || v <= m) {
      stop("Negative Binomial needs variance greater than mean.")
    }
    size <- m^2 / (v - m)
    list(type = "negbin", params = list(size = size, mu = m), expected = m)
  } else if (model == "binomial") {
    stop("The Binomial needs the exposure as the number of insured risks;",
         " fit it with fit_binomial_risks.")
  } else {
    stop("Unknown frequency model: ", model)
  }
}

# Fits the Binomial with the exposure read as the number of insured risks:
# in year t, each of the N_t risks independently produces a loss above the
# modelling threshold with probability p (at most one per risk per year), so
# the count is Binomial(N_t, p). N is never estimated from the counts (that
# estimate is unstable and moves the support with the noise in a few years of
# data); it is the exposure. p is the maximum likelihood estimate, total claims
# over total risk-years, and the forward count is Binomial(N_V, p) with N_V the
# valuation-year exposure. Stops with a plain message when the exposure cannot
# be a count of risks.
fit_binomial_risks <- function(counts, risks_obs, risks_fwd) {
  is_whole <- function(x) abs(x - round(x)) < 1e-9
  if (length(risks_fwd) != 1 || is.na(risks_fwd)) {
    stop("The Binomial needs the number of risks in the book being priced:",
         " add the valuation year to the 'exposure' sheet.")
  }
  if (!all(is_whole(c(risks_obs, risks_fwd)))) {
    stop("The Binomial reads the exposure as the number of insured risks, but",
         " the 'exposure' sheet has values that are not whole numbers. Use",
         " Poisson or Negative Binomial for a monetary exposure.")
  }
  if (any(counts > risks_obs)) {
    stop("A year has more claims than insured risks, which the Binomial does",
         " not allow. Check that the exposure is the number of risks, or use",
         " Poisson or Negative Binomial.")
  }
  p <- sum(counts) / sum(risks_obs)
  N <- as.integer(round(risks_fwd))
  list(type = "binomial", params = list(size = N, prob = p), expected = N * p,
       risks_obs = as.integer(round(risks_obs)))
}

# Scales a fitted frequency distribution's mean by a factor (e.g. to project the
# observed-period rate onto a larger or smaller prospective book). Poisson and
# Negative Binomial scale their mean parameter directly. The Binomial is never
# scaled: fit_binomial_risks already takes the forward number of risks as its
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

# Probability mass function of a fitted frequency model at counts k, vectorised
# over k: the probability of seeing exactly k claims in a year. Lets the
# dashboard plot the fitted count distribution against the empirical one.
frequency_pmf <- function(fit, k) {
  p <- fit$params
  switch(fit$type,
    poisson  = stats::dpois(k, p$lambda),
    negbin   = stats::dnbinom(k, size = p$size, mu = p$mu),
    binomial = stats::dbinom(k, p$size, p$prob),
    stop("Unknown frequency type: ", fit$type)
  )
}

# The fitted probability of each yearly count over the observed years, on the
# same basis as the empirical counts. Poisson and Negative Binomial use the
# fit on the observed counts directly. The Binomial has a different number of
# risks each year, so its observed-period distribution is the average of
# Binomial(N_t, p) over the observed years.
observed_frequency_pmf <- function(fit, k) {
  if (fit$type != "binomial") return(frequency_pmf(fit, k))
  rowMeans(vapply(fit$risks_obs, function(n) {
    stats::dbinom(k, n, fit$params$prob)
  }, numeric(length(k))))
}
