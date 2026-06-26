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
  num <- function(k) {
    if (!k %in% names(pv) || is.na(pv[[k]])) {
      stop("Missing required parameter in the 'parameters' sheet: ", k)
    }
    as.numeric(pv[[k]])
  }
  if (!"frequency_model" %in% names(pv)) {
    stop("Missing required parameter in the 'parameters' sheet: frequency_model")
  }
  parameters <- list(
    reporting_threshold = num("reporting_threshold"),
    loss_inflation_pa   = num("loss_inflation_pa"),
    modelling_threshold = num("modelling_threshold"),
    splice_threshold    = num("splice_threshold"),
    frequency_model     = pv[["frequency_model"]],
    n_simulations       = as.integer(num("n_simulations")),
    valuation_year      = as.integer(num("valuation_year")),
    loading_ev          = num("loading_ev"),
    loading_sd          = num("loading_sd"),
    var_level           = num("var_level")
  )

  losses$loss <- as.numeric(losses$loss)
  losses$year <- as.integer(losses$year)
  exposure$year <- as.integer(exposure$year)

  list(losses = losses, exposure = exposure,
       parameters = parameters, contract = contract)
}
