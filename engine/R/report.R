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

# The validation table: simulated against closed-form expected loss, their delta,
# the burning cost benchmark and a note. The closed form is blank (NA) for layers
# with aggregate conditions, so the note points the reader to the simulation.
validation_report <- function(results, burning_cost) {
  note <- ifelse(is.na(results$oracle),
                 "Aggregate conditions: no closed form, use the simulation", "")
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
