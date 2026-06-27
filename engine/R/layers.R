# Loss to a layer C excess of D, vectorised over x.
apply_layer <- function(x, D, C) {
  pmin(pmax(x - D, 0), C)
}

# The starting reinsurance program shown in the dashboard when it opens. One row
# per layer, with exactly the columns the pricer expects (cover excess of
# deductible, annual aggregate deductible and limit). The contract no longer
# lives in the workbook, so this is the single source of the default structure
# for both the dashboard and the headless run_pricing path.
default_contract <- function() {
  data.frame(
    deductible = c(5, 10, 20),
    cover      = c(5, 10, 20),
    aad        = c(0, 0, 0),
    aal        = c(0, 0, 0)
  )
}
