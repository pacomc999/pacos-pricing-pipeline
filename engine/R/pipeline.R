# Resolves the modelling and pricing settings used for fitting and pricing.
# Precedence: explicit overrides (from the dashboard) > values in the workbook
# parameters sheet > built-in defaults. A NA splice threshold means "use the
# modelling threshold", which collapses the body and gives a single Pareto. The
# modelling threshold defaults to the reporting threshold (the loss size above
# which the data is complete), unless the workbook or the dashboard sets one.
resolve_settings <- function(parameters, overrides = list()) {
  defaults <- list(
    modelling_threshold = parameters$reporting_threshold,
    splice_threshold    = NA_real_,
    frequency_model     = "poisson",
    n_simulations       = 100000L,
    loading_ev          = 0.1,
    loading_sd          = 0.2,
    var_level           = 0.99
  )
  pick <- function(k) {
    o <- overrides[[k]]
    if (!is.null(o) && !all(is.na(o))) return(o)
    p <- parameters[[k]]
    if (!is.null(p) && !all(is.na(p))) return(p)
    defaults[[k]]
  }
  s <- list(
    modelling_threshold = pick("modelling_threshold"),
    splice_threshold    = pick("splice_threshold"),
    frequency_model     = pick("frequency_model"),
    n_simulations       = as.integer(pick("n_simulations")),
    loading_ev          = pick("loading_ev"),
    loading_sd          = pick("loading_sd"),
    var_level           = pick("var_level")
  )
  if (is.na(s$splice_threshold)) s$splice_threshold <- s$modelling_threshold
  s
}

# Fits frequency and the spliced severity. This is the fast part (no Monte
# Carlo), so the dashboard can call it live as the thresholds change.
fit_models <- function(input, settings) {
  losses <- index_losses(input$losses, input$exposure, input$inflation, input$parameters)
  # Observation window: exposure years up to the latest loss year only (the
  # prospective valuation year carries exposure but no losses).
  obs_years <- input$exposure$year[input$exposure$year <= max(input$losses$year)]
  years <- sort(unique(obs_years))
  counts <- annual_counts(
    data.frame(year = losses$year, loss = losses$loss_indexed),
    years, settings$modelling_threshold)
  # Frequency is the observed-period rate, scaled to the prospective book: a
  # larger forward exposure is expected to produce proportionally more claims.
  freq <- fit_frequency(counts, settings$frequency_model)
  freq <- scale_frequency(freq, exposure_frequency_factor(
    input$exposure, years, input$parameters$valuation_year))
  sev <- fit_severity(losses$loss_indexed,
                      settings$modelling_threshold, settings$splice_threshold)
  list(losses = losses, years = years, counts = counts,
       fit_frequency = freq, fit_severity = sev)
}

# Simulates and prices the program from fitted models. This is the expensive
# part, so the dashboard runs it only on demand.
price_models <- function(fits, contract, settings, seed = NULL) {
  sims <- simulate_annual_losses(
    fits$fit_frequency,
    function(n) sample_severity(fits$fit_severity, n),
    settings$n_simulations, seed)
  pp <- list(loading_ev = settings$loading_ev,
             loading_sd = settings$loading_sd,
             var_level = settings$var_level)
  results <- price_program(sims, contract, pp)
  # Attach the closed-form oracle and the simulation delta. The oracle is a
  # per-loss integral, so it only applies when the layer has no aggregate
  # conditions. AAD/AAL act on the annual aggregate, which has no closed form,
  # so those layers get NA and lean on the simulation instead.
  results$oracle <- vapply(seq_len(nrow(results)), function(i) {
    has_aad <- !is.na(contract$aad[i]) && contract$aad[i] > 0
    has_aal <- !is.na(contract$aal[i]) && contract$aal[i] > 0
    if (has_aad || has_aal) return(NA_real_)
    expected_layer_loss(fits$fit_frequency, fits$fit_severity,
                        results$deductible[i], results$cover[i])
  }, numeric(1))
  results$oracle_delta <- results$expected_loss - results$oracle
  list(results = results, sims = sims)
}

# End-to-end pricing from a workbook. `overrides` is a named list of modelling
# settings (as the dashboard supplies); anything omitted falls back to the
# workbook then to built-in defaults. `contract` is the program to price; the
# workbook no longer carries it, so it defaults to the built-in demo program.
run_pricing <- function(input_path, overrides = list(),
                        contract = default_contract(), output_path = NULL,
                        seed = NULL) {
  input <- read_input(input_path)
  settings <- resolve_settings(input$parameters, overrides)
  fits <- fit_models(input, settings)
  priced <- price_models(fits, contract, settings, seed)
  results <- priced$results
  bc <- burning_cost(fits$losses, contract)

  if (!is.null(output_path)) {
    assumptions <- data.frame(
      key = c("frequency_model", "lambda", "pareto_alpha",
              "modelling_threshold", "splice_threshold",
              "n_simulations", "valuation_year"),
      value = c(settings$frequency_model, round(fits$fit_frequency$expected, 4),
                round(fits$fit_severity$pareto$alpha, 4),
                settings$modelling_threshold, settings$splice_threshold,
                settings$n_simulations, input$parameters$valuation_year))
    # The Excel sheets mirror the dashboard's Results and Validation tables.
    write_output(output_path, results_report(results), assumptions,
                 validation = validation_report(results, bc))
  }

  list(results = results, fit_frequency = fits$fit_frequency,
       fit_severity = fits$fit_severity, burning_cost = bc,
       sims = priced$sims, settings = settings)
}
