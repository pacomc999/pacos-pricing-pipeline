# Limit-case tests for the two as-if adjustments: claims inflation (which trends
# the loss sizes, i.e. the severity) and exposure (which scales the frequency
# only). The cases below are chosen so the expected result is exact, so we can
# assert hard equalities rather than fuzzy tolerances.

# Builds the in-memory input list fit_models expects. Exposure and inflation
# default to a flat book of 100 and zero inflation over the loss years up to the
# valuation year.
mk_input <- function(losses, valuation_year, reporting_threshold,
                     exposure = NULL, inflation = NULL) {
  yrs <- seq.int(min(losses$year), valuation_year)
  if (is.null(exposure)) exposure <- data.frame(year = yrs, exposure = rep(100, length(yrs)))
  if (is.null(inflation)) inflation <- data.frame(year = yrs, inflation = rep(0, length(yrs)))
  list(losses = losses, exposure = exposure, inflation = inflation,
       parameters = list(valuation_year = as.integer(valuation_year),
                         reporting_threshold = reporting_threshold))
}

# Single-Pareto settings at modelling threshold mt (splice = mt collapses the
# lognormal body). A small simulation count is fine: the exactness in the scaling
# tests comes from the fixed seed, not the sample size.
mk_settings <- function(params, mt, n_sims = 2000L) {
  resolve_settings(params, list(modelling_threshold = mt, splice_threshold = mt,
                                frequency_model = "poisson", n_simulations = n_sims,
                                loading_ev = 0.1, loading_sd = 0.2, var_level = 0.99))
}

# The experience-pricing example losses (Reinsurance Analytics, Figure 8), all
# comfortably above a modelling threshold of 5.
EX_LOSSES <- data.frame(
  year = c(2021, 2021, 2023, 2024, 2024, 2024, 2025),
  loss = c(12, 9.5, 18, 13, 7, 11, 14))

# ---- Exposure: linear in frequency, orthogonal to severity --------------------

test_that("doubling the valuation-year exposure doubles the frequency, not the severity", {
  base <- mk_input(EX_LOSSES, 2026, 3)   # flat exposure 100 including 2026
  dbl  <- mk_input(EX_LOSSES, 2026, 3,
    exposure = data.frame(year = 2021:2026, exposure = c(100, 100, 100, 100, 100, 200)))
  s <- mk_settings(base$parameters, mt = 5)
  fb <- fit_models(base, s)
  fd <- fit_models(dbl, s)

  # Frequency factor is E_V / mean(E_obs): 200/100 = 2 versus 100/100 = 1.
  expect_equal(fd$fit_frequency$expected, 2 * fb$fit_frequency$expected)
  # Severity is untouched: exposure does not enter the loss sizes.
  expect_equal(fd$fit_severity$pareto$alpha, fb$fit_severity$pareto$alpha)
  expect_equal(fd$fit_severity$weight, fb$fit_severity$weight)
  # The closed-form oracle for a layer therefore doubles exactly.
  ob <- expected_layer_loss(fb$fit_frequency, fb$fit_severity, 5, 5)
  od <- expected_layer_loss(fd$fit_frequency, fd$fit_severity, 5, 5)
  expect_equal(od, 2 * ob)
})

# ---- Inflation: exact only under full scale-invariance ------------------------

test_that("scaling losses, thresholds and the layer by k scales the price by exactly k", {
  k <- 3
  # One plain layer and one with aggregate conditions; scale every term by k.
  contract_base <- data.frame(deductible = c(10, 5), cover = c(10, 5),
                              aad = c(0, 2), aal = c(0, 8))
  contract_k <- data.frame(deductible = c(10, 5) * k, cover = c(10, 5) * k,
                           aad = c(0, 2) * k, aal = c(0, 8) * k)

  base <- mk_input(EX_LOSSES, 2026, 3)
  # (k - 1) inflation in the valuation year multiplies every loss by k.
  infl_k <- data.frame(year = 2021:2026, inflation = c(0, 0, 0, 0, 0, k - 1))
  scaled <- mk_input(EX_LOSSES, 2026, 3 * k, inflation = infl_k)

  s_base <- mk_settings(base$parameters, mt = 5)
  s_k    <- mk_settings(scaled$parameters, mt = 5 * k)
  fb <- fit_models(base, s_base)
  fk <- fit_models(scaled, s_k)
  pb <- price_models(fb, contract_base, s_base, seed = 1)
  pk <- price_models(fk, contract_k, s_k, seed = 1)

  # Every layer's simulated expected loss scales by exactly k.
  expect_equal(pk$results$expected_loss, k * pb$results$expected_loss)
  # The closed-form oracle (plain layer, row 1) also scales by exactly k.
  expect_equal(pk$results$oracle[1], k * pb$results$oracle[1])
  # And so does the advanced burning cost (both layers).
  bcb <- burning_cost(fb$losses, contract_base, base$exposure, 2026)
  bck <- burning_cost(fk$losses, contract_k, scaled$exposure, 2026)
  expect_equal(bck$bc_advanced, k * bcb$bc_advanced)
})

test_that("inflation moves the frequency only through losses crossing the threshold", {
  # All losses stay well above MT = 5, so inflation leaves the count unchanged.
  hi <- data.frame(year = 2021:2025, loss = c(10, 12, 15, 20, 8))
  base <- mk_input(hi, 2026, 3)
  infl <- mk_input(hi, 2026, 3,
    inflation = data.frame(year = 2021:2026, inflation = c(0, 0, 0, 0, 0, 1)))  # x2
  s <- mk_settings(base$parameters, mt = 5)
  expect_equal(fit_models(infl, s)$fit_frequency$expected,
               fit_models(base, s)$fit_frequency$expected)

  # A loss of 4 sits below MT; doubling it to 8 lifts it above MT, so the count
  # (and the frequency) rises.
  near <- data.frame(year = 2021:2025, loss = c(10, 12, 15, 20, 4))
  base2 <- mk_input(near, 2026, 1)
  infl2 <- mk_input(near, 2026, 1,
    inflation = data.frame(year = 2021:2026, inflation = c(0, 0, 0, 0, 0, 1)))  # 4 -> 8
  s2 <- mk_settings(base2$parameters, mt = 5)
  expect_gt(fit_models(infl2, s2)$fit_frequency$expected,
            fit_models(base2, s2)$fit_frequency$expected)
})

test_that("doubling the losses with the layer and thresholds fixed does NOT double the price", {
  # A high layer, where the caps and piercing clearly bite.
  contract <- data.frame(deductible = 10, cover = 10, aad = 0, aal = 0)
  base <- mk_input(EX_LOSSES, 2026, 3)
  dbl  <- mk_input(EX_LOSSES, 2026, 3,
    inflation = data.frame(year = 2021:2026, inflation = c(0, 0, 0, 0, 0, 1)))  # x2
  s <- mk_settings(base$parameters, mt = 5)
  pb <- price_models(fit_models(base, s), contract, s, seed = 1)
  pd <- price_models(fit_models(dbl, s), contract, s, seed = 1)

  # With the layer and MT fixed in money, doubling the losses does not give 2x:
  # the layer caps are non-linear and the severity is conditioned at a fixed MT.
  # (Contrast the scale-invariance test, where scaling everything gives exactly 2x.)
  ratio <- pd$results$expected_loss / pb$results$expected_loss
  expect_false(isTRUE(all.equal(ratio, 2, tolerance = 0.05)))
})
