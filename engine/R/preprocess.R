# Ratio of exposure in the valuation year to exposure in the loss year.
exposure_factor <- function(exposure, loss_year, valuation_year) {
  e_now <- exposure$exposure[exposure$year == valuation_year]
  e_then <- exposure$exposure[exposure$year == loss_year]
  if (length(e_now) == 0 || length(e_then) == 0) return(1)
  e_now / e_then
}

# Factor that scales the expected claim frequency from the observed period to
# the prospective (valuation) year: the forward book size relative to the
# average book size over the observed years. A bigger forward book is expected
# to produce proportionally more claims. Returns 1 when exposure is unavailable.
exposure_frequency_factor <- function(exposure, observed_years, valuation_year) {
  e_fwd <- exposure$exposure[exposure$year == valuation_year]
  e_obs <- exposure$exposure[exposure$year %in% observed_years]
  if (length(e_fwd) == 0 || length(e_obs) == 0 || mean(e_obs) == 0) return(1)
  e_fwd / mean(e_obs)
}

# Cumulative loss-inflation factor from a loss year up to the valuation year.
# Inflation is a per-year rate; a loss is already in money of its own year, so
# each later year's rate accrues on top: factor = prod(1 + rate_t) for the years
# t between loss_year + 1 and valuation_year. If the valuation year is earlier
# than the loss year, the same product deflates instead.
inflation_factor <- function(inflation, loss_year, valuation_year) {
  if (valuation_year == loss_year) return(1)
  lo <- min(loss_year, valuation_year)
  hi <- max(loss_year, valuation_year)
  yrs <- (lo + 1):hi
  rates <- inflation$inflation[match(yrs, inflation$year)]
  if (any(is.na(rates))) {
    stop("Missing inflation rate for year(s): ",
         paste(yrs[is.na(rates)], collapse = ", "))
  }
  factor <- prod(1 + rates)
  if (valuation_year < loss_year) 1 / factor else factor
}

# Trends each loss to the valuation year for loss inflation only, restating old
# losses in today's money. Exposure is deliberately not applied here: it is a
# volume measure that drives how many claims happen (frequency), not how big each
# one is (severity), so it is handled on the frequency side (see fit_models's
# exposure_frequency_factor scaling). The exposure argument is kept for a stable
# signature but unused. Both the severity fit and the frequency count read these
# inflation-trended losses.
index_losses <- function(losses, exposure, inflation, params) {
  infl <- vapply(losses$year, function(y) {
    inflation_factor(inflation, y, params$valuation_year)
  }, numeric(1))
  losses$loss_indexed <- losses$loss * infl
  losses
}

# Average annual loss to each layer, simple (raw) and advanced (as-if), per year.
# Each year's losses are layered per loss and then run through the layer's annual
# aggregate deductible and limit, so the benchmark uses the same layer definition
# as the pricer (annual_layer_loss in price.R).
#
# The advanced figure puts the history on the basis of the book being priced: the
# losses are already trended for inflation (loss_indexed), and each year's volume
# is then on-levelled to the valuation-year book by the exposure ratio
# (valuation-year exposure / that year's exposure). Exposure is a volume measure,
# so a year with a smaller book is expected to have produced proportionally fewer
# claims; scaling the aggregate of recoveries restores it to the forward book.
# The scaling is applied before the AAD and AAL (via annual_layer_loss's scale
# argument), so the aggregate conditions still cap the on-levelled figure. This is
# the frequency (volume) channel, not a change to the loss sizes, matching how the
# pricer scales the frequency.
burning_cost <- function(losses_indexed, contract, exposure, valuation_year) {
  # Average over the observed years (the exposure years up to the latest loss
  # year), the same window the frequency uses, so a year with no losses counts as
  # a zero rather than being dropped from the denominator (which would overstate
  # the burning cost).
  obs_years <- sort(unique(exposure$year[exposure$year <= max(losses_indexed$year)]))
  expo_level <- vapply(obs_years, function(y) {
    exposure_factor(exposure, y, valuation_year)
  }, numeric(1))
  rows <- lapply(seq_len(nrow(contract)), function(i) {
    D <- contract$deductible[i]; C <- contract$cover[i]
    aad <- contract$aad[i]; aal <- contract$aal[i]
    simple_by_year <- vapply(seq_along(obs_years), function(j) {
      annual_layer_loss(losses_indexed$loss[losses_indexed$year == obs_years[j]], D, C, aad, aal)
    }, numeric(1))
    adv_by_year <- vapply(seq_along(obs_years), function(j) {
      annual_layer_loss(losses_indexed$loss_indexed[losses_indexed$year == obs_years[j]],
                        D, C, aad, aal, scale = expo_level[j])
    }, numeric(1))
    data.frame(deductible = D, cover = C,
               bc_simple = mean(simple_by_year),
               bc_advanced = mean(adv_by_year))
  })
  do.call(rbind, rows)
}
