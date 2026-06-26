# End-to-end pricing: read, index, fit, simulate, price, validate, write.
run_pricing <- function(input_path, output_path = NULL, seed = NULL) {
  input <- read_input(input_path)
  params <- input$parameters

  # Pre-process: revalue losses to the valuation year.
  losses <- index_losses(input$losses, input$exposure, params)

  # Fit frequency at the modelling threshold over the exposure observation period.
  years <- sort(unique(input$exposure$year))
  counts <- annual_counts(
    data.frame(year = losses$year, loss = losses$loss_indexed),
    years, params$modelling_threshold)
  freq <- fit_frequency(counts, params$frequency_model)

  # Fit the spliced severity (lognormal body, Pareto tail) on the indexed losses.
  sev <- fit_severity(losses$loss_indexed,
                      params$modelling_threshold, params$splice_threshold)

  # Simulate the full conditional severity, so layers can cut body and/or tail.
  sims <- simulate_annual_losses(freq, function(n) sample_severity(sev, n),
                                 params$n_simulations, seed)

  # Price every layer.
  pp <- list(loading_ev = params$loading_ev,
             loading_sd = params$loading_sd,
             var_level = params$var_level)
  results <- price_program(sims, input$contract, pp)

  # Attach the closed-form oracle and the simulation delta.
  results$oracle <- vapply(seq_len(nrow(results)), function(i) {
    expected_layer_loss(freq, sev, results$deductible[i], results$cover[i])
  }, numeric(1))
  results$oracle_delta <- results$expected_loss - results$oracle

  bc <- burning_cost(losses, input$contract)

  if (!is.null(output_path)) {
    assumptions <- data.frame(
      key = c("frequency_model", "lambda", "pareto_alpha",
              "modelling_threshold", "splice_threshold",
              "n_simulations", "valuation_year"),
      value = c(freq$type, round(freq$expected, 4),
                round(sev$pareto$alpha, 4), sev$mt, sev$s,
                params$n_simulations, params$valuation_year))
    write_output(output_path, results, assumptions)
  }

  list(results = results, fit_frequency = freq, fit_severity = sev,
       burning_cost = bc, sims = sims)
}
