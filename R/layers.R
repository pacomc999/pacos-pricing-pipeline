# Loss to a layer C excess of D, vectorised over x.
apply_layer <- function(x, D, C) {
  pmin(pmax(x - D, 0), C)
}
