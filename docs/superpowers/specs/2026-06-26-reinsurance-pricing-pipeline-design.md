# Paco's Pragmatic Pricing Pipeline — Design Spec (v1)

Date: 2026-06-26
Status: Approved (design); pending implementation plan
Author: Francisco Martinez Checa, with Claude

## 1. Purpose

An R + Shiny tool that prices non-proportional (NP) reinsurance from a list of
historical losses. The user uploads an Excel workbook; the tool fits a loss
model, runs a Monte Carlo simulation of the aggregate loss, applies the
reinsurance contract structure, and returns prices and risk metrics as an Excel
workbook plus an interactive dashboard.

The methodology follows the experience-pricing recipe in *Reinsurance Analytics,
FS 2026* (P. Arbenz), Section 2.8, generalised so the severity is not restricted
to a single Pareto. The architecture is built so proportional (quota share)
business can be added later without rework.

## 2. Scope

### In scope (v1)
- Experience pricing of NP per-risk excess-of-loss (XL) programs (multiple layers).
- Reinstatements and aggregate features (annual aggregate deductible AAD, annual
  aggregate limit AAL).
- Spliced severity: lognormal body + Pareto tail, continuity enforced.
- Frequency: Poisson (default), Negative Binomial, or Binomial.
- Loss inflation (indexation) and exposure correction (advanced burning cost).
- Burning cost analysis (simple and advanced) as a benchmark.
- Monte Carlo aggregate loss distribution.
- Closed-form expected layer loss as a validation oracle for the simulation.
- Excel input and Excel output, plus a Shiny dashboard.

### Out of scope (v1)
- Proportional treaties (quota share / surplus) — deferred to v2; engine designed
  to accommodate.
- Loss development / IBNR (v1 assumes short-tail, per Section 2.8).
- Natural catastrophe models.
- Multi-line-of-business aggregation.
- Exposure rating curves (e.g. MBBEFD / Swiss Re curves).

## 3. Data flow

```
Excel input
  -> pre-process (loss inflation indexation + exposure correction)
  -> fit frequency (Poisson / NegBin / Binomial)
  -> fit spliced severity (lognormal below threshold u, Pareto above)
  -> Monte Carlo: draw N, draw N severities, apply contract structure
  -> price each layer + risk metrics
  -> closed-form expected-loss validation check
  -> Excel output + Shiny dashboard
```

## 4. Input Excel format

A single workbook with four sheets.

### Sheet `losses`
| column | type | notes |
|--------|------|-------|
| `year` | integer | accident/occurrence year |
| `loss` | numeric | ground-up (from-ground-up, FGU) loss amount |
| `line_of_business` | text | optional; informational in v1 |

One row per individual loss. Years with no reported losses are inferred from the
`exposure` / `parameters` year range (so zero-loss years count correctly in the
frequency estimate).

### Sheet `exposure`
| column | type | notes |
|--------|------|-------|
| `year` | integer | |
| `exposure` | numeric | exposure measure, e.g. number of risks or sum insured |

Used for the exposure-correction factor (exposure in valuation year / exposure in
loss year).

### Sheet `parameters`
| key | example | notes |
|-----|---------|-------|
| `reporting_threshold` | 3,000,000 | losses below this are not reported in the data |
| `loss_inflation_pa` | 0.02 | annual loss inflation used for indexation |
| `modelling_threshold` | 5,000,000 | MT: losses above this enter the model and drive frequency; must satisfy `reporting_threshold <= MT <= lowest layer deductible` |
| `splice_threshold` | 15,000,000 | s: lognormal body below, Pareto tail above; must satisfy `MT < s` and should sit inside the layer range so the body prices lower layers |
| `frequency_model` | `poisson` | one of `poisson`, `negbin`, `binomial` |
| `n_simulations` | 100,000 | Monte Carlo iterations |
| `valuation_year` | 2026 | year all losses are revalued to |

### Sheet `contract`
One row per XL layer in the program.
| column | type | notes |
|--------|------|-------|
| `deductible` | numeric | attachment point D (C xs D) |
| `cover` | numeric | layer width C |
| `n_reinstatements` | integer | number of reinstatements (0 = none) |
| `reinstatement_cost` | numeric | reinstatement premium as fraction of layer premium (e.g. 1.0 = at 100%) |
| `aad` | numeric | annual aggregate deductible (0 = none) |
| `aal` | numeric | annual aggregate limit (blank/0 = unlimited) |

## 5. Pre-processing (advanced burning cost, Section 2.2)

1. **Indexation (loss inflation).** Revalue each historical loss to the valuation
   year: `loss * (1 + loss_inflation_pa) ^ (valuation_year - loss_year)`.
2. **Exposure correction.** Multiply by `exposure[valuation_year] /
   exposure[loss_year]`.
3. **Burning cost benchmark.** Compute simple and advanced burning cost (average
   indexed/exposure-adjusted loss to each layer) to use as the sense-check in the
   validation step (Section 9).

## 6. Severity model — spliced lognormal + Pareto (two thresholds)

The severity is modelled **conditional on a loss exceeding the modelling
threshold MT** (those are the only losses that enter the model). Above MT the
severity is spliced at a higher point `s` (the splice threshold), with continuity
enforced. Because `s` sits inside the layer range, lower layers are priced off
the lognormal body and higher layers off the Pareto tail.

- **Body (MT < X <= s):** lognormal(mu, sigma), fitted by maximum likelihood on
  the indexed losses in `(MT, s]` (via `fitdistrplus`); used as a lognormal
  truncated to `(MT, s]` inside the mixture.
- **Tail (X > s):** Pareto(x0 = s, alpha), with alpha by MLE
  `alpha_hat = n / sum(log(x_i / s))` over losses above `s`.
- **Tail weight:** `w = empirical P(X > s | X > MT)` =
  (count of losses > s) / (count of losses > MT).
- **Continuity:** `x0 = s` and the branches are weighted by `1 - w` (truncated
  lognormal body) and `w` (Pareto tail), so the conditional mixture CDF is
  continuous at `s`.

Conditional mixture survival function `S(t) = P(X > t | X > MT)`:
- `t <= MT`: 1
- `MT < t <= s`: `(1 - w) * (F_ln(s) - F_ln(t)) / (F_ln(s) - F_ln(MT)) + w`
- `t > s`: `w * (t / s)^(-alpha)`

**Sampling (Monte Carlo).** Draw a uniform `v ~ U(0,1)`; if `v < w` draw from the
Pareto tail (inverse-CDF `s * U^(-1/alpha)`), else draw from the lognormal body
truncated to `(MT, s]` (inverse-CDF on the truncated range).

Special cases that aid validation: setting `s = MT` empties the body and collapses
the model to a single Pareto, reproducing the course example (notes Table 13).

## 7. Frequency model

User-selectable, default Poisson. Calibrated from annual counts of losses above
the **modelling threshold MT** (the same conditioning as the severity, so
frequency and severity are coherent: `E[annual layer loss] = E[N] * E[layer cost
per loss | X > MT]`).

- **Poisson (default):** `lambda_hat` = mean annual count of losses > MT.
- **Negative Binomial:** fit by matching mean and variance (or MLE) on annual
  counts; appropriate only when a systemic risk driver is suspected.
- **Binomial:** for a finite, known number of risks producing similar events.

Note: reinsurance data is typically too sparse to *select* the distribution class
from data; Poisson is the principled default and the others are user overrides.

## 8. Pricing engine

### Monte Carlo (core)
Each iteration of the simulation:
1. Draw the annual loss count `N` from the fitted frequency distribution (counts
   above MT).
2. Draw `N` severities from the **full spliced** severity distribution conditional
   on `X > MT` (Section 6) — so draws can land in either the lognormal body or the
   Pareto tail.
3. Apply the contract structure to the year's losses:
   - per-loss layer function `L_{D,C}(x) = min(max(x - D, 0), C)` for each layer;
   - aggregate the layer losses over the year;
   - apply AAD/AAL to the annual aggregate;
   - apply reinstatement limits (cap reinstated cover, accumulate reinstatement
     premium).
4. Record the reinsured loss (and reinstatement premium) for each layer.

After all iterations, build the empirical aggregate loss distribution per layer.

### Validation oracle (simulation-independent)
In parallel, compute the expected layer loss without sampling and compare to the
simulated mean (must converge as `n_simulations` grows). Using the Darth Vader
rule `E[L_{D,C}] = integral_D^{D+C} S(t) dt` with the conditional mixture survival
`S` from Section 6, computed by **deterministic numerical integration** so it
shares no machinery with the Monte Carlo path (a genuine cross-check). Then
multiply by expected frequency `E[N]` for the expected annual loss.

For the pure-Pareto region (`D >= s`) the integral has the exact closed form
`E[L_{D,C}] = w * (s^alpha / (1 - alpha)) * ((D+C)^(1-alpha) - D^(1-alpha))`,
which is kept as a closed-form unit-test anchor: the numerical integrator must
match it when the layer sits entirely in the tail. The lognormal limited expected
value `E[X ^ u] = exp(mu + sigma^2/2) * Phi((ln u - mu - sigma^2)/sigma) + u * (1
- Phi((ln u - mu)/sigma))` is implemented for body-layer reasoning and v2.

This applies to per-layer expected loss only; aggregate features (AAD/AAL),
reinstatements, and volatility metrics come from the simulation.

## 9. Outputs and premium principles

Per layer:
- Expected loss (simulated) and closed-form expected loss + the validation delta.
- Standard deviation, VaR and TVaR at user-chosen levels.
- Rate-on-line `RoL = premium / limit`.
- Return period and excess frequency at the attachment point.
- Premium under:
  - **Expected-value principle:** `P = (1 + theta) * E[loss]`.
  - **Standard-deviation principle:** `P = E[loss] + theta * sd[loss]`.
  - Loading factors `theta` are user inputs.
- Burning cost (simple and advanced) shown alongside as a benchmark.

## 10. Output Excel and dashboard

### Excel output
- `results` sheet: one row per layer with all metrics from Section 9.
- `assumptions` sheet: echo of the fitted parameters and all inputs used.

### Shiny dashboard
- Excel upload and parameter overrides.
- Fitted-distribution diagnostics: severity QQ plot, mean-excess plot (to support
  threshold choice), fitted vs empirical CDF, frequency fit summary.
- Per-layer pricing table.
- Simulated aggregate loss distribution plots.
- Closed-form vs simulation validation comparison.
- Download button for the Excel output.

## 11. R module structure

Each module is independently testable.

| file | responsibility |
|------|----------------|
| `io.R` | read input workbook, write output workbook (`readxl`, `openxlsx`) |
| `preprocess.R` | indexation, exposure correction, burning cost benchmark |
| `fit_severity.R` | fit spliced lognormal + Pareto, expose CDF / sampler |
| `fit_frequency.R` | fit Poisson / NegBin / Binomial from counts |
| `simulate.R` | Monte Carlo aggregate loss generation |
| `price.R` | apply contract structures, compute premium principles and metrics |
| `validate.R` | closed-form expected layer loss formulas |
| `app.R` | Shiny UI + server |

## 12. Validation and testing

- `testthat` unit tests per module.
- Key invariant: simulated expected layer loss converges to the `validate.R`
  oracle (within Monte Carlo tolerance), for layers in the body, the tail, or
  straddling the splice.
- Reproduce the course example (Table 13) by setting `s = MT` to collapse the
  body, giving a single Pareto, and checking expected layer losses against the
  notes.
- Sense checks per Section 2.8 Step 3e: compare to burning cost; test sensitivity
  to indexation and exposure; check frequency plausibility at attachment and at
  the top of the program.

## 13. Dependencies

R packages: `shiny`, `actuar` (loss distributions, coverage modifications,
limited expected values), `fitdistrplus` (MLE fitting), `readxl` (read Excel),
`openxlsx` (write Excel), `ggplot2` (plots), `testthat` (tests).

## 14. Future (v2+)

- Proportional treaties (quota share / surplus): `E[cX]` closed form
  (Corollary 2.46) and simulation reuse.
- Loss development / IBNR for long-tail lines.
- Exposure rating curves for low-data lines.
- Multi-line-of-business portfolio aggregation.
