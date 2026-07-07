# Reinsured loss for one simulated year, in this order:
# per-loss layering -> scale -> AAD -> AAL.
# `scale` multiplies the aggregate of per-loss recoveries before the aggregate
# conditions apply. It defaults to 1 (the pricer leaves it alone); the burning
# cost uses it to on-level a year's volume to the book being priced, so the AAD
# and AAL still cap the scaled aggregate (the cap must come after the scaling,
# never before, or the limit can be breached).
annual_layer_loss <- function(year_losses, D, C, aad, aal, scale = 1) {
  per_loss <- apply_layer(year_losses, D, C)
  agg <- sum(per_loss) * scale
  # Annual aggregate deductible removes the first aad of aggregate loss
  # (a blank/NA or zero aad means no aggregate deductible).
  if (!is.na(aad) && aad > 0) agg <- max(agg - aad, 0)
  # Annual aggregate limit caps the aggregate (0 means unlimited).
  if (!is.na(aal) && aal > 0) agg <- min(agg, aal)
  agg
}

# The simulated annual loss to one layer, one value per simulated year. This is
# the empirical loss distribution for the layer; price_layer summarises it into
# the headline stats, and the dashboard plots it.
layer_annual_losses <- function(sims, layer_row) {
  vapply(sims, function(yl) {
    annual_layer_loss(yl, layer_row$deductible, layer_row$cover,
                      layer_row$aad, layer_row$aal)
  }, numeric(1))
}

# Summarises one layer's simulated annual losses into the headline stats row:
# expected loss, volatility, the tail measures and the two premiums.
summarise_layer_losses <- function(annual, layer_row, premium_params) {
  expected_loss <- mean(annual)
  sd_loss <- stats::sd(annual)
  var_q <- stats::quantile(annual, premium_params$var_level, names = FALSE)
  tvar <- mean(annual[annual >= var_q])

  premium_ev <- (1 + premium_params$loading_ev) * expected_loss
  premium_sd <- expected_loss + premium_params$loading_sd * sd_loss

  data.frame(
    cover = layer_row$cover, deductible = layer_row$deductible,
    expected_loss = expected_loss, sd_loss = sd_loss,
    var = var_q, tvar = tvar,
    premium_ev = premium_ev, premium_sd = premium_sd
  )
}

# Prices a single layer from the simulated years.
price_layer <- function(sims, layer_row, premium_params) {
  summarise_layer_losses(layer_annual_losses(sims, layer_row), layer_row, premium_params)
}

# Prices every layer in the program. Each layer's annual loss vector is computed
# once and reused for both the summary row and the returned distribution, so the
# program is layered over the simulated years a single time. Returns the results
# table and the per-layer annual loss vectors (the empirical loss distributions).
price_program <- function(sims, contract, premium_params) {
  annual_by_layer <- lapply(seq_len(nrow(contract)), function(i) {
    layer_annual_losses(sims, contract[i, ])
  })
  results <- do.call(rbind, lapply(seq_len(nrow(contract)), function(i) {
    summarise_layer_losses(annual_by_layer[[i]], contract[i, ], premium_params)
  }))
  list(results = results, annual_by_layer = annual_by_layer)
}
