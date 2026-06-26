# Monte Carlo of annual ground-up losses entering the layers.
# Each simulated year: draw a loss count N, then draw N severities.
simulate_annual_losses <- function(freq_fit, severity_sampler, n_sims, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  counts <- sample_frequency(freq_fit, n_sims)
  lapply(counts, function(n) {
    if (n == 0) numeric(0) else severity_sampler(n)
  })
}
