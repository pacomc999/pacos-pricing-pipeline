# Maximum likelihood alpha for a Pareto with known lower bound x0. The MLE
# n / sum(log(x / x0)) is biased upward in small samples (its expectation is
# alpha * n / (n - 1)), which understates the tail exactly where reinsurance
# samples are thinnest, so by default the unbiased (n - 1)/n correction is
# applied. With a single point the factor would zero the alpha, so the plain
# MLE is kept there. bias_correct = FALSE gives the uncorrected MLE (the form
# used in the Reinsurance Analytics notes).
fit_pareto_alpha <- function(x, x0, bias_correct = TRUE) {
  x <- x[x > x0]
  n <- length(x)
  alpha <- n / sum(log(x / x0))
  if (bias_correct && n >= 2) alpha * (n - 1) / n else alpha
}

# Truncated lognormal MLE on (lo, hi]: maximises the likelihood of the body
# model as it is actually used, the lognormal conditioned to the window,
# f(x) / (F(hi) - F(lo)). An unconditional fit on the windowed data would bias
# mu and sigma, explaining the missing tails as low variance.
fit_lnorm_truncated <- function(x, lo, hi) {
  nll <- function(par) {
    m <- par[1]; s <- exp(par[2])   # log-sd keeps the search unconstrained
    denom <- stats::plnorm(hi, m, s) - stats::plnorm(lo, m, s)
    if (!is.finite(denom) || denom <= 0) return(Inf)
    -sum(stats::dlnorm(x, m, s, log = TRUE)) + length(x) * log(denom)
  }
  lx <- log(x)
  # Start from the unconditional estimates; the sd is floored so identical
  # losses (sd 0) still give a workable starting point.
  start <- c(mean(lx), log(max(stats::sd(lx), 1e-3)))
  opt <- stats::optim(start, nll)
  list(meanlog = opt$par[1], sdlog = exp(opt$par[2]))
}

# Fits the spliced severity conditional on X > mt: lognormal body on (mt, s],
# Pareto tail on (s, Inf). Continuity at s comes from the mixture weight.
# bias_correct is passed through to fit_pareto_alpha.
fit_severity <- function(loss_values, mt, s, bias_correct = TRUE) {
  modelled <- loss_values[loss_values > mt]   # only losses above MT are modelled
  body <- modelled[modelled <= s]             # (mt, s]
  tail <- modelled[modelled > s]              # (s, Inf)
  # The Pareto tail needs data above s; without it alpha is undefined (NaN).
  if (length(tail) < 1) {
    stop("No losses above the splice threshold s (", s,
         "); lower the splice threshold or check the data.")
  }
  weight <- length(tail) / length(modelled)   # P(X > s | X > mt)

  lnorm <- NULL
  if (length(body) >= 2) {
    lnorm <- fit_lnorm_truncated(body, mt, s)
  }

  list(mt = mt, s = s, weight = weight, lnorm = lnorm, n_body = length(body),
       pareto = list(x0 = s, alpha = fit_pareto_alpha(tail, s, bias_correct)))
}

# Caution for the dashboard about the lognormal body. The body is only "active"
# when the splice sits above the modelling threshold; at splice = mt there is no
# body (a single Pareto) and no warning. When the body is active, warn if its
# region holds too few losses to fit a lognormal: either none at all (an empty
# region the user probably did not intend) or fewer than n_min. n_min defaults to
# 10 (about five losses per lognormal parameter): reinsurance samples are usually
# too small to support the extra body parameters reliably.
severity_body_warning <- function(n_body, body_active, n_min = 10) {
  if (!body_active || n_body >= n_min) return(NULL)
  if (n_body == 0) {
    return(paste0("The splice threshold is above the modelling threshold but no",
                  " losses fall between them, so the lognormal body region is",
                  " empty. Select the Single Pareto severity model instead."))
  }
  paste0("The lognormal body is fitted on only ", n_body,
         if (n_body == 1) " loss" else " losses",
         " - too few for a reliable fit. Select the Single Pareto severity",
         " model instead.")
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
