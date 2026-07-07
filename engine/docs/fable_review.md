# Fable review

A full review of Paco's Pricing Pipeline, covering the actuarial methodology and
the tool itself. Reviewed by Claude (Fable 5), July 2026. Every finding points to
the file and line where it lives, using the `file:line` convention.

**Update, 2 July 2026:** items 1 to 9 of the work table at the bottom have been
implemented (test first, then fix; the full suite passed clean after each one).
Line numbers in the findings below refer to the code as reviewed and may have
drifted; the function names remain valid. Item 10 (bootstrap parameter
uncertainty) stays open, as do the smaller suggestions not in the table
(binomial mean-preserving refit, an alpha <= 1 warning, showing bc_simple,
sample size notes on the Model step). The technical premium wording and the
multi-user hosting note were covered in the documentation pass.

**Update, 7 July 2026:** items 6 and 9 were removed again by Francisco's
decision. Item 9 (the Pareto alpha bias correction) added complexity he judged
unjustified; the plain MLE keeps the tool aligned with the Reinsurance
Analytics notes, and the finding in section 1.4 stands as a known, accepted
limitation. Item 6 (the Monte Carlo standard error column) was judged useless
in practice: at the default simulation count the Monte Carlo noise is
negligible next to the parameter uncertainty from fitting a handful of losses,
so the column suggested precision the price does not have. The real answer to
section 1.5 would be the bootstrap of item 10, which remains open.

## Overall verdict

This is a well built project. Several things stand out that professional pricing
tools often lack:

- The fit is separated from the simulation (`engine/R/pipeline.R:39` vs
  `engine/R/pipeline.R:61`), so the dashboard can refit live and only simulate on
  demand.
- The simulation is cross checked by an oracle that shares none of its machinery
  (`engine/R/validate.R:21`).
- An empirical burning cost benchmark sits alongside the model
  (`engine/R/preprocess.R:69`).
- Limitations are documented honestly
  (`engine/docs/documentation.md`, section "Assumptions and limitations").
- One test file per module under `engine/tests/testthat/`.

The findings below are ordered by how much they matter, not by how many there
are.

---

## Part 1: Actuarial methodology

### 1.1 The reporting threshold is not indexed (most important finding)

**Where:** `engine/R/pipeline.R:45` (frequency counted on indexed losses),
`engine/app.R:831` (the clamp that enforces MT >= reporting threshold),
`engine/R/io.R:47` (the reporting threshold definition).

**The problem.** The data is complete above the reporting threshold in each loss
year's own money. But `fit_models` counts frequency from indexed losses above
MT, and the clamp only enforces MT >= the nominal reporting threshold.

Concrete example with the template data (RT = 2, inflation around 3% per year):
a 2021 loss of 1.9 was never recorded because it sat below RT, but had it been
recorded it would index to about 2.2 in 2026 money. Meanwhile a 2021 loss of
2.05 that was recorded indexes to about 2.4 and gets counted. So near the
threshold, early years are missing losses that belong in the sample in indexed
terms. The frequency (and the severity body near MT) is understated, and more so
for older years, which quietly distorts any trend.

**The fix.** The completeness floor in valuation year money is RT times the
largest cumulative inflation factor across the observed years. The clamp in
`engine/app.R:831` should enforce
`MT >= RT * max over observed years y of inflation_factor(y, V)`
(using `inflation_factor` from `engine/R/preprocess.R:25`). Equivalently, apply
a year specific indexed threshold when counting in
`engine/R/fit_frequency.R:4`.

**Why this is a known trap.** This is the classic "index the threshold" issue in
excess of loss experience rating: when losses are trended, every threshold
defined on the original data must be trended too, or the completeness guarantee
silently breaks. It matters most exactly where reinsurance data is thinnest,
near the threshold in the oldest years.

### 1.2 The observation window ends at a random quantity

**Where:** `engine/R/pipeline.R:42` (window = exposure years up to
`max(input$losses$year)`), same logic repeated in
`engine/R/preprocess.R:74` for the burning cost.

**The problem.** The window end is the latest loss year, which is itself
random. Two failure modes:

- The book was fully observed through 2025 but simply had no losses that year.
  That genuine zero year is dropped from the denominator, so frequency is
  overstated.
- The latest year is only half observed (data cut mid year) but is counted as a
  full year, so frequency is understated.

**The fix.** Add a "last complete experience year" field to the
`general inputs` sheet (`engine/R/io.R:43`, `engine/R/template.R:30`) and use it
as the window end in both places. One workbook cell removes both biases.

### 1.3 The lognormal body is fitted with the wrong likelihood

**Where:** `engine/R/fit_severity.R:22` (plain `fitdistrplus::fitdist` on the
body losses), used truncated in `engine/R/fit_severity.R:55` and
`engine/R/fit_severity.R:78`.

**The problem.** The body losses in (MT, s] are fitted with an unconditional
lognormal MLE, but the fitted distribution is then used truncated to (MT, s].
Fitting an untruncated likelihood to truncated data biases mu and sigma: the fit
tries to explain the missing tails as low variance. The model stays internally
coherent because the survival function renormalises, but the parameters are not
the MLE of the model actually being used.

**The fix.** Maximise the truncated log likelihood instead: either pass
truncated density functions to `fitdistrplus::fitdist`, or write the truncated
log likelihood and call `optim` (a few lines). Given the body is only active in
the spliced model and the dashboard already warns below 10 body losses
(`engine/R/fit_severity.R:38`), this is a correctness point more than a
numbers shifting one, but a peer reviewer would flag it.

### 1.4 Small sample Pareto bias, and no parameter uncertainty anywhere

**Where:** `engine/R/fit_severity.R:2` (the alpha estimator),
`engine/R/pipeline.R` (point estimates only throughout).

Two related points:

- **Bias.** The MLE `alpha = n / sum(log(x / s))` is biased for small n:
  its expectation is `alpha * n / (n - 1)`. With 5 tail losses alpha is
  overstated by about 25% on average, which understates the tail and therefore
  the price of high layers. The standard correction is to multiply the estimate
  by `(n - 1) / n` (or `(n - 2) / n` for the minimum variance version).
- **Uncertainty.** The tool reports point estimates only. With a handful of
  losses, the sampling error of alpha dwarfs the Monte Carlo error the
  validation panel tracks. A bootstrap (resample the loss list, refit, reprice
  with a small simulation count, repeat around 200 times) would give a premium
  range per layer. This is the single most valuable methodological addition
  available: it changes the answer from "the price is 1.23" to "the price is
  1.23 but the data supports anything from 0.9 to 1.7", which is the honest
  state of affairs in reinsurance.

### 1.5 The validation delta has no yardstick

**Where:** `engine/R/pipeline.R:86` (the delta), `engine/R/report.R:23`
(the validation table that shows it).

**The problem.** The Validation table shows `Simulated - Closed form` and the
documentation says small differences are expected, but the user has no way to
know what small means.

**The fix.** The Monte Carlo standard error is free:
`sd_loss / sqrt(n_simulations)` per layer, both already available in
`engine/R/price.R:31`. Show the delta next to (or divided by) that standard
error. The check then becomes quantitative: a delta within about 2 standard
errors is noise, beyond that is a bug.

### 1.6 Smaller methodological points

- **Binomial rounding drifts the mean.** In `engine/R/fit_frequency.R:24`,
  after `n = round(m / p)` the implied mean `n * p` no longer equals m. Refit
  `p = m / n` after rounding. The same issue appears in `scale_frequency`
  (`engine/R/fit_frequency.R:46`), where rounding the scaled size distorts the
  intended exposure factor.
- **Warn when alpha <= 1.** Layer losses stay finite because cover is bounded
  (`engine/R/layers.R:2`), so nothing breaks, but an infinite mean severity is a
  strong statement the user should see flagged next to the fitted alpha on the
  Model step (`engine/app.R:996`, the severity parameters table).
- **Frequency and severity can disagree on which years exist.** Losses in a
  year missing from the exposure sheet are silently excluded from the frequency
  counts (`engine/R/pipeline.R:42` builds the year list from the exposure
  sheet) but still included in the severity fit
  (`engine/R/pipeline.R:53` fits on all indexed losses). Validate on load that
  every loss year appears in the exposure and inflation sheets
  (`engine/R/io.R:5`).
- **The premiums are pure technical premiums.** No expenses, brokerage, or cost
  of capital (`engine/R/price.R:37`). A fine scope choice, but it should be
  stated explicitly in `engine/docs/documentation.md` (Premium principles
  section) and in the Price step info panel (`engine/app.R:497`), because the
  word premium in the output will be read as a market comparable number.
- **`bc_simple` is computed but never shown.** `engine/R/preprocess.R:81`
  computes it, but only `bc_advanced` reaches the validation table
  (`engine/R/report.R:32`). Either surface both (the gap between them shows how
  much the on levelling is doing, which is genuinely useful) or drop the simple
  one.

---

## Part 2: The tool itself

### 2.1 Bugs

- **A blank deductible passes validation and poisons the results.**
  `validate_contract` (`engine/app.R:35`) catches an NA cover at
  `engine/app.R:37`, but checks the deductible only with
  `any(contract$deductible < 0, na.rm = TRUE)` at `engine/app.R:40`, so NA
  slips through. `apply_layer(x, NA, C)` (`engine/R/layers.R:2`) then returns NA
  and the whole results table goes NA or NaN with no explanation. Add
  `any(is.na(contract$deductible))` to the check. The tower plot already drops
  such rows (`engine/app.R:71`), which makes the failure more confusing: the
  plot looks fine while pricing breaks.
- **Error message names the wrong sheet.** `engine/R/io.R:28` says
  "Missing required parameter in the 'parameters' sheet" but the sheet is
  called `general inputs` (`engine/R/io.R:7`). A user staring at their workbook
  will not find a parameters sheet.

### 2.2 Robustness gaps (garbage in, cryptic error out)

`read_input` (`engine/R/io.R:5`) validates sheet presence but not the data.
Things a corporate user will eventually do, and what happens now:

- **Negative, zero, or NA loss amounts** flow silently into the fit
  (`engine/R/io.R:59` coerces without checking).
- **Duplicate years in the exposure or inflation sheet** make
  `exposure_factor` (`engine/R/preprocess.R:2`) return a length 2 vector and
  downstream code misbehaves.
- **Losses below the reporting threshold present in the data** are silently
  accepted, but this contradicts the declared completeness threshold and
  usually means the user misunderstood the field. Worth a visible warning on
  the Data step (`engine/app.R:751`).

A small `validate_input(input)` called from `read_input`, returning plain
English messages, would fit the existing style: the contract already gets
exactly this treatment in `validate_contract` (`engine/app.R:35`). For a tool
whose whole pitch is that a colleague cannot hurt themselves with it, input
validation is the highest leverage engineering improvement.

### 2.3 Consistency and audit trail

- **The two Excel exports disagree.** The headless `run_pricing` assumptions
  sheet includes the fitted lambda and Pareto alpha
  (`engine/R/pipeline.R:105`), while the dashboard's Download omits them and
  includes the loadings instead (`engine/app.R:1199`). The fitted parameters
  are the most important part of the audit trail, since the downloaded file is
  what gets emailed around. Merge the two into one shared assumptions builder,
  the same pattern already used in `engine/R/report.R:1` for the results
  tables.
- **The contract structure is not echoed in the export.** The output workbook
  (`engine/R/io.R:73`) records results per layer but not the AAD and AAL that
  produced them. Six months later nobody can reconstruct the run from the file
  alone.

A pattern worth noticing: everywhere the codebase shares one definition between
two consumers (`engine/R/report.R` for dashboard and Excel,
`engine/R/template.R` for the script and the Generate template button), the
tool is consistent. The one place with two parallel definitions (the
assumptions sheets) is exactly where drift crept in.

### 2.4 Smaller tool suggestions

- **Process level state and multi user hosting.** `.app_state`
  (`engine/app.R:120`) shares the last upload across sessions. Right for a
  single user desktop tool, but if this is ever hosted on a shared Shiny
  server, one user's loss data would appear for the next user. Worth a one line
  comment so future deployments do not trip on it.
- **Show the sample sizes on the Model step.** A note showing how many losses
  sit above MT (and above s) would help users see how thin a sample their
  thresholds create, before the body warning
  (`engine/R/fit_severity.R:38`) trips.

---

## Suggested order of work

| # | Item | Size | Where | Status |
|---|------|------|-------|--------|
| 1 | NA deductible validation | small | `engine/app.R:40` | Fixed |
| 2 | Wrong sheet name in error message | tiny | `engine/R/io.R:28` | Fixed |
| 3 | Index the reporting threshold in the MT clamp | small | `engine/app.R:831`, `engine/docs/documentation.md` | Fixed: `indexed_reporting_threshold` in `engine/R/preprocess.R`; the headless path warns |
| 4 | Last complete experience year input | small | `engine/R/io.R:43`, `engine/R/pipeline.R:42`, `engine/R/preprocess.R:74`, `engine/R/template.R:30` | Fixed: `observation_years` in `engine/R/preprocess.R`; optional `last_complete_year` general input |
| 5 | Input validation on the workbook | medium | `engine/R/io.R:5` | Fixed: `validate_input` in `engine/R/io.R`; soft warnings shown on the Data step |
| 6 | Monte Carlo standard error in the validation table | small | `engine/R/report.R:23`, `engine/R/pipeline.R:86` | Implemented, then removed by decision (7 July 2026): MC noise is negligible next to parameter uncertainty, so the column suggested false precision |
| 7 | Shared assumptions builder for both exports | small | `engine/R/pipeline.R:105`, `engine/app.R:1199` | Fixed: `assumptions_report` in `engine/R/report.R`; contract echoed as its own sheet |
| 8 | Truncated MLE for the lognormal body | medium | `engine/R/fit_severity.R:22` | Fixed: `fit_lnorm_truncated`; the `fitdistrplus` dependency was dropped |
| 9 | Pareto small sample bias correction | small | `engine/R/fit_severity.R:2` | Implemented, then removed by decision (7 July 2026): judged unjustified complexity; the plain MLE stays and the limitation is accepted |
| 10 | Bootstrap parameter uncertainty, premium range per layer | large (headline v2 feature) | new module plus `engine/R/pipeline.R` | Open |
