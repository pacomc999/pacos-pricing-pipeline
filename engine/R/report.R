# Display formatters shared by the dashboard tables and the Excel report, so the
# two always show the same columns, in the same order, with the same names.
# Cover is shown before the deductible, matching the structure step.

# The results table: expected loss, volatility, tail risk and the two premiums.
results_report <- function(results) {
  data.frame(
    Cover = results$cover,
    Deductible = results$deductible,
    `Expected loss` = round(results$expected_loss, 2),
    `Std dev` = round(results$sd_loss, 2),
    VaR = round(results$var, 2),
    TVaR = round(results$tvar, 2),
    `Premium (EV)` = round(results$premium_ev, 2),
    `Premium (SD)` = round(results$premium_sd, 2),
    check.names = FALSE
  )
}

# One assumptions sheet for both export paths (headless run_pricing and the
# dashboard download), so the audit trail always carries the settings AND the
# fitted parameters. The downloaded file is what travels; together with the
# contract echo a result should be reconstructible from it alone.
assumptions_report <- function(settings, parameters, fits, seed = NA) {
  sev <- fits$fit_severity
  lnorm_mu <- if (is.null(sev$lnorm)) NA_real_ else sev$lnorm$meanlog
  lnorm_sd <- if (is.null(sev$lnorm)) NA_real_ else sev$lnorm$sdlog
  data.frame(
    key = c("valuation_year", "currency", "amount_units", "last_complete_year",
            "modelling_threshold", "splice_threshold", "frequency_model",
            "expected_claims_per_year", "pareto_alpha",
            "lognormal_meanlog", "lognormal_sdlog", "tail_weight",
            "n_simulations", "loading_ev", "loading_sd", "var_level", "seed"),
    value = as.character(c(
      parameters$valuation_year, parameters$currency, parameters$amount_units,
      parameters$last_complete_year,
      settings$modelling_threshold, settings$splice_threshold,
      settings$frequency_model,
      round(fits$fit_frequency$expected, 4), round(sev$pareto$alpha, 4),
      round(lnorm_mu, 4), round(lnorm_sd, 4), round(sev$weight, 4),
      settings$n_simulations, settings$loading_ev, settings$loading_sd,
      settings$var_level, seed)))
}

# The validation table: simulated against closed-form expected loss, their delta,
# the burning cost benchmark and a note. The closed form is blank (NA) for layers
# with aggregate conditions, which the note flags.
validation_report <- function(results, burning_cost) {
  note <- ifelse(is.na(results$oracle),
                 "Aggregate conditions: no closed form", "")
  data.frame(
    Cover = results$cover,
    Deductible = results$deductible,
    Simulated = round(results$expected_loss, 3),
    `Closed form` = round(results$oracle, 3),
    Delta = round(results$oracle_delta, 4),
    `Burning cost` = round(burning_cost$bc_advanced, 3),
    Note = note,
    check.names = FALSE
  )
}
