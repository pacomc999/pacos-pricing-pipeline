# Closed-form expected loss to layer C xs D for a Pareto(x0, alpha), D >= x0.
# E[L] = integral_D^{D+C} (t/x0)^{-alpha} dt  (Darth Vader rule, Example 2.45).
# Kept as the unit-test anchor for the numerical oracle below.
pareto_layer_ev <- function(x0, alpha, D, C) {
  if (alpha == 1) {
    x0 * (log(D + C) - log(D))
  } else {
    (x0 ^ alpha / (1 - alpha)) * ((D + C) ^ (1 - alpha) - D ^ (1 - alpha))
  }
}

# Limited expected value E[min(X, u)] for a lognormal(meanlog, sdlog).
lnorm_limited_ev <- function(meanlog, sdlog, u) {
  m <- meanlog; s <- sdlog
  exp(m + s^2 / 2) * stats::pnorm((log(u) - m - s^2) / s) +
    u * (1 - stats::pnorm((log(u) - m) / s))
}

# Validation oracle: E[N] times the integral of the conditional survival over
# the layer. Deterministic quadrature, independent of the Monte Carlo path.
expected_layer_loss <- function(freq_fit, sev_fit, D, C) {
  integrand <- function(t) severity_survival(sev_fit, t)
  layer_ev <- stats::integrate(integrand, lower = D, upper = D + C)$value
  freq_fit$expected * layer_ev
}
