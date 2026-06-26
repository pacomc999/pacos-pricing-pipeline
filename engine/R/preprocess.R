# Ratio of exposure in the valuation year to exposure in the loss year.
exposure_factor <- function(exposure, loss_year, valuation_year) {
  e_now <- exposure$exposure[exposure$year == valuation_year]
  e_then <- exposure$exposure[exposure$year == loss_year]
  if (length(e_now) == 0 || length(e_then) == 0) return(1)
  e_now / e_then
}

# Revalues each loss to the valuation year: loss inflation then exposure change.
index_losses <- function(losses, exposure, params) {
  infl <- (1 + params$loss_inflation_pa) ^ (params$valuation_year - losses$year)
  expo <- vapply(losses$year, function(y) {
    exposure_factor(exposure, y, params$valuation_year)
  }, numeric(1))
  losses$loss_indexed <- losses$loss * infl * expo
  losses
}

# Average loss to each layer, simple (raw) and advanced (indexed), per year.
burning_cost <- function(losses_indexed, contract) {
  years <- sort(unique(losses_indexed$year))
  rows <- lapply(seq_len(nrow(contract)), function(i) {
    D <- contract$deductible[i]; C <- contract$cover[i]
    simple_by_year <- vapply(years, function(y) {
      sum(apply_layer(losses_indexed$loss[losses_indexed$year == y], D, C))
    }, numeric(1))
    adv_by_year <- vapply(years, function(y) {
      sum(apply_layer(losses_indexed$loss_indexed[losses_indexed$year == y], D, C))
    }, numeric(1))
    data.frame(deductible = D, cover = C,
               bc_simple = mean(simple_by_year),
               bc_advanced = mean(adv_by_year))
  })
  do.call(rbind, rows)
}
