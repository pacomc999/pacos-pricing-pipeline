# Maximum likelihood alpha for a Pareto with known lower bound x0.
fit_pareto_alpha <- function(x, x0) {
  x <- x[x > x0]
  length(x) / sum(log(x / x0))
}

# Fits the spliced severity conditional on X >= mt: lognormal body on [mt, s],
# Pareto tail on (s, Inf). Continuity at s comes from the mixture weight.
fit_severity <- function(loss_values, mt, s) {
  modelled <- loss_values[loss_values >= mt]  # losses at or above MT are modelled
  body <- modelled[modelled <= s]             # [mt, s]
  tail <- modelled[modelled > s]              # (s, Inf)
  # The Pareto tail needs data above s; without it alpha is undefined (NaN).
  if (length(tail) < 1) {
    stop("No losses above the splice threshold s (", s,
         "); lower the splice threshold or check the data.")
  }
  weight <- length(tail) / length(modelled)   # P(X > s | X > mt)

  lnorm <- NULL
  if (length(body) >= 2) {
    fit <- fitdistrplus::fitdist(body, "lnorm")
    lnorm <- list(meanlog = unname(fit$estimate["meanlog"]),
                  sdlog   = unname(fit$estimate["sdlog"]))
  }

  list(mt = mt, s = s, weight = weight, lnorm = lnorm,
       pareto = list(x0 = s, alpha = fit_pareto_alpha(tail, s)))
}

# Conditional survival S(t) = P(X > t | X > mt), vectorised over t.
severity_survival <- function(fit, t) {
  w <- fit$weight; mt <- fit$mt; s <- fit$s; alpha <- fit$pareto$alpha
  # Body survival within (mt, s]: fraction of body mass still above t.
  body_S <- function(tt) {
    if (is.null(fit$lnorm)) return(rep(0, length(tt)))
    Fs  <- stats::plnorm(s,  fit$lnorm$meanlog, fit$lnorm$sdlog)
    Fmt <- stats::plnorm(mt, fit$lnorm$meanlog, fit$lnorm$sdlog)
    Ft  <- stats::plnorm(tt, fit$lnorm$meanlog, fit$lnorm$sdlog)
    (Fs - Ft) / (Fs - Fmt)
  }
  out <- numeric(length(t))
  below <- t <= mt
  mid   <- t > mt & t <= s
  above <- t > s
  out[below] <- 1
  out[mid]   <- (1 - w) * body_S(t[mid]) + w
  out[above] <- w * (t[above] / s) ^ (-alpha)
  out
}

# Draws n severities from the conditional mixture (the severity entering layers).
sample_severity <- function(fit, n) {
  is_tail <- stats::runif(n) < fit$weight
  out <- numeric(n)
  # Pareto tail: inverse CDF s * U^(-1/alpha) gives P(X > x) = (x/s)^(-alpha).
  out[is_tail] <- fit$s * stats::runif(sum(is_tail)) ^ (-1 / fit$pareto$alpha)
  # Lognormal body truncated to (mt, s]: inverse CDF on the truncated range.
  n_body <- sum(!is_tail)
  if (n_body > 0) {
    if (is.null(fit$lnorm)) {
      out[!is_tail] <- fit$mt   # degenerate fallback when the body is unfitted
    } else {
      Fmt <- stats::plnorm(fit$mt, fit$lnorm$meanlog, fit$lnorm$sdlog)
      Fs  <- stats::plnorm(fit$s,  fit$lnorm$meanlog, fit$lnorm$sdlog)
      u_draw <- stats::runif(n_body, Fmt, Fs)
      out[!is_tail] <- stats::qlnorm(u_draw, fit$lnorm$meanlog, fit$lnorm$sdlog)
    }
  }
  out
}
