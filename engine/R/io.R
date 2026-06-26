# Reads the four-sheet pricing workbook into a structured list.
read_input <- function(path) {
  if (!file.exists(path)) stop("Input workbook not found: ", path)
  required_sheets <- c("losses", "exposure", "parameters", "contract")
  present <- readxl::excel_sheets(path)
  missing <- setdiff(required_sheets, present)
  if (length(missing) > 0) {
    stop("Input workbook is missing required sheet(s): ",
         paste(missing, collapse = ", "))
  }

  losses <- as.data.frame(readxl::read_excel(path, sheet = "losses"))
  exposure <- as.data.frame(readxl::read_excel(path, sheet = "exposure"))
  contract <- as.data.frame(readxl::read_excel(path, sheet = "contract"))

  # Parameters arrive as key/value rows; turn them into a typed named list.
  raw_params <- as.data.frame(readxl::read_excel(path, sheet = "parameters"))
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
    reporting_threshold = num("reporting_threshold"),
    loss_inflation_pa   = num("loss_inflation_pa"),
    valuation_year      = as.integer(num("valuation_year")),
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

  list(losses = losses, exposure = exposure,
       parameters = parameters, contract = contract)
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
