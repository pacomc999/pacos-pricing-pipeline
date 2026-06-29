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

# Prices a single layer from the simulated years.
price_layer <- function(sims, layer_row, premium_params) {
  D <- layer_row$deductible
  C <- layer_row$cover
  annual <- layer_annual_losses(sims, layer_row)

  expected_loss <- mean(annual)
  sd_loss <- stats::sd(annual)
  var_q <- stats::quantile(annual, premium_params$var_level, names = FALSE)
  tvar <- mean(annual[annual >= var_q])

  premium_ev <- (1 + premium_params$loading_ev) * expected_loss
  premium_sd <- expected_loss + premium_params$loading_sd * sd_loss

  data.frame(
    cover = C, deductible = D,
    expected_loss = expected_loss, sd_loss = sd_loss,
    var = var_q, tvar = tvar,
    premium_ev = premium_ev, premium_sd = premium_sd
  )
}

# Prices every layer in the program.
price_program <- function(sims, contract, premium_params) {
  rows <- lapply(seq_len(nrow(contract)), function(i) {
    price_layer(sims, contract[i, ], premium_params)
  })
  do.call(rbind, rows)
}
