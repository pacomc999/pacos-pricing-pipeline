# Reads the four-sheet pricing workbook into a structured list. The contract
# structure no longer lives in the workbook; the dashboard owns it (see
# default_contract() and run_pricing's contract argument). Loss inflation is a
# per-year rate (its own sheet), not a single constant.
read_input <- function(path) {
  if (!file.exists(path)) stop("Input workbook not found: ", path)
  required_sheets <- c("losses", "exposure", "general inputs", "inflation")
  present <- readxl::excel_sheets(path)
  missing <- setdiff(required_sheets, present)
  if (length(missing) > 0) {
    stop("Input workbook is missing required sheet(s): ",
         paste(missing, collapse = ", "))
  }

  losses <- as.data.frame(readxl::read_excel(path, sheet = "losses"))
  exposure <- as.data.frame(readxl::read_excel(path, sheet = "exposure"))
  inflation <- as.data.frame(readxl::read_excel(path, sheet = "inflation"))

  # General inputs arrive as key/value rows (any extra columns, e.g. a notes
  # column, are ignored); turn them into a typed named list.
  raw_params <- as.data.frame(readxl::read_excel(path, sheet = "general inputs"))
  pv <- setNames(as.character(raw_params$value), raw_params$key)
  # pv is a named character vector, so check the name exists before subsetting
  # (pv[["missing"]] would throw "subscript out of bounds", not return NULL).
  # Required parameters describe the data and the valuation basis.
  num <- function(k) {
    if (!k %in% names(pv) || is.na(pv[[k]])) {
      stop("Missing required parameter in the 'general inputs' sheet: ", k)
    }
    as.numeric(pv[[k]])
  }
  # Optional parameters are the modelling choices; the dashboard sets these, so
  # they may be absent from the workbook (NA means "use the default / the UI").
  opt_num <- function(k) {
    if (k %in% names(pv) && !is.na(pv[[k]])) as.numeric(pv[[k]]) else NA_real_
  }
  opt_int <- function(k) {
    v <- opt_num(k); if (is.na(v)) NA_integer_ else as.integer(v)
  }
  opt_chr <- function(k) {
    if (k %in% names(pv) && !is.na(pv[[k]])) pv[[k]] else NA_character_
  }
  parameters <- list(
    valuation_year      = as.integer(num("valuation_year")),
    # The loss size above which the data is complete (required). It bounds the
    # modelling threshold from below.
    reporting_threshold = num("reporting_threshold"),
    currency            = opt_chr("currency"),
    amount_units        = opt_chr("amount_units"),
    # The last year with complete loss data (optional). It ends the frequency
    # and burning cost observation window; when absent, the latest loss year is
    # used instead.
    last_complete_year  = opt_int("last_complete_year"),
    modelling_threshold = opt_num("modelling_threshold"),
    splice_threshold    = opt_num("splice_threshold"),
    frequency_model     = opt_chr("frequency_model"),
    n_simulations       = opt_int("n_simulations"),
    loading_ev          = opt_num("loading_ev"),
    loading_sd          = opt_num("loading_sd"),
    var_level           = opt_num("var_level")
  )

  losses$loss <- as.numeric(losses$loss)
  losses$year <- as.integer(losses$year)
  exposure$year <- as.integer(exposure$year)
  inflation$year <- as.integer(inflation$year)
  inflation$inflation <- as.numeric(inflation$inflation)

  warnings <- validate_input(losses, exposure, inflation, parameters)

  list(losses = losses, exposure = exposure,
       parameters = parameters, inflation = inflation, warnings = warnings)
}

# Checks the parsed workbook data. Problems the pipeline cannot price safely
# stop with a plain message naming the sheet to fix; soft problems come back as
# a character vector of warnings that the Data step shows next to the preview.
validate_input <- function(losses, exposure, inflation, parameters) {
  problems <- character(0)
  # Losses: every row needs a year and a positive amount.
  if (any(is.na(losses$year)) || any(is.na(losses$loss))) {
    problems <- c(problems,
      "The 'losses' sheet has rows with a missing year or loss amount.")
  }
  if (any(!is.na(losses$loss) & losses$loss <= 0)) {
    problems <- c(problems, paste0(
      "The 'losses' sheet has loss amounts of 0 or less;",
      " every loss must be a positive amount."))
  }
  # Exposure: one positive value per year, no repeats (duplicate years would
  # break the per-year lookups in the on-levelling).
  if (any(is.na(exposure$year)) || any(is.na(exposure$exposure))) {
    problems <- c(problems,
      "The 'exposure' sheet has rows with a missing year or exposure.")
  }
  if (anyDuplicated(stats::na.omit(exposure$year)) > 0) {
    problems <- c(problems, "The 'exposure' sheet lists the same year twice.")
  }
  if (any(!is.na(exposure$exposure) & exposure$exposure <= 0)) {
    problems <- c(problems, paste0(
      "The 'exposure' sheet has exposures of 0 or less;",
      " every year needs a positive exposure."))
  }
  # Inflation: one rate per year, no repeats.
  if (any(is.na(inflation$year)) || any(is.na(inflation$inflation))) {
    problems <- c(problems,
      "The 'inflation' sheet has rows with a missing year or rate.")
  }
  if (anyDuplicated(stats::na.omit(inflation$year)) > 0) {
    problems <- c(problems, "The 'inflation' sheet lists the same year twice.")
  }
  # Every loss year needs an exposure row, or the year silently drops out of
  # the frequency window while its losses still enter the severity fit.
  missing_expo <- setdiff(losses$year[!is.na(losses$year)], exposure$year)
  if (length(missing_expo) > 0) {
    problems <- c(problems, paste0(
      "Loss year(s) ", paste(missing_expo, collapse = ", "),
      " have no row in the 'exposure' sheet."))
  }
  # Indexation needs a rate for every year between the oldest loss (plus one)
  # and the valuation year, in either direction.
  yrs <- c(losses$year[!is.na(losses$year)], parameters$valuation_year)
  lo <- min(yrs); hi <- max(yrs)
  if (hi > lo) {
    missing_infl <- setdiff((lo + 1):hi, inflation$year)
    if (length(missing_infl) > 0) {
      problems <- c(problems, paste0(
        "The 'inflation' sheet is missing the rate for year(s) ",
        paste(missing_infl, collapse = ", "),
        ", needed to revalue the losses to the valuation year."))
    }
  }
  if (length(problems) > 0) {
    stop("The input workbook has problems:\n- ",
         paste(problems, collapse = "\n- "), call. = FALSE)
  }
  # Soft checks: suspicious but priceable, so they warn instead of stopping.
  warnings <- character(0)
  n_below <- sum(!is.na(losses$loss) &
                 losses$loss <= parameters$reporting_threshold)
  if (n_below > 0) {
    warnings <- c(warnings, paste0(
      n_below, if (n_below == 1) " loss sits" else " losses sit",
      " at or below the reporting threshold (", parameters$reporting_threshold,
      "). The data is declared complete only above that size, so check the",
      " threshold or the loss list."))
  }
  warnings
}

# Writes the pricing results, an optional validation table and the assumptions
# echo to a workbook. The results and validation sheets mirror the dashboard
# tables (same columns and order); validation is optional for backward
# compatibility, so callers that only need results can omit it.
write_output <- function(path, results, assumptions, validation = NULL) {
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "results")
  openxlsx::writeData(wb, "results", results)
  if (!is.null(validation)) {
    openxlsx::addWorksheet(wb, "validation")
    openxlsx::writeData(wb, "validation", validation)
  }
  openxlsx::addWorksheet(wb, "assumptions")
  openxlsx::writeData(wb, "assumptions", assumptions)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  invisible(path)
}
