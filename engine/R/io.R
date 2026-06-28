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
      stop("Missing required parameter in the 'parameters' sheet: ", k)
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
    currency            = opt_chr("currency"),
    amount_units        = opt_chr("amount_units"),
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

  list(losses = losses, exposure = exposure,
       parameters = parameters, inflation = inflation)
}

# Writes pricing results and the assumptions echo to a two-sheet workbook.
write_output <- function(path, results, assumptions) {
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "results")
  openxlsx::writeData(wb, "results", results)
  openxlsx::addWorksheet(wb, "assumptions")
  openxlsx::writeData(wb, "assumptions", assumptions)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  invisible(path)
}
