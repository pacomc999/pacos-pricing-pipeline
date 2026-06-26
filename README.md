# Paco's Pragmatic Pricing Pipeline

An R and Shiny tool that prices non-proportional reinsurance from a historical
loss list. Excel in, Excel plus dashboard out.

## Easiest start (Windows)
**Double-click `start.bat`.** That is all most users need to do. On the first
run it will:
- install R automatically if it is not already on the machine (approve the
  Windows security prompt and accept the defaults),
- install the R package dependencies,
- generate the example workbook,
- open the dashboard in your browser.

Keep the small black window open while you use the tool; close it to stop the
dashboard. Loss data stays on the machine and is never uploaded anywhere. The
first run can take several minutes (downloading R and packages); later runs
start in seconds. If antivirus or SmartScreen warns about the downloaded R
installer, it is the official installer from https://cran.r-project.org.

## Quick start (any platform, command line)
1. Install R (4.x).
2. Install dependencies: `Rscript install_deps.R`
3. Generate the example workbook: `Rscript make_example.R`
4. Launch the dashboard: `Rscript -e "shiny::runApp('.', launch.browser = TRUE)"`
5. Upload `example_input.xlsx`, click Run pricing.

## Pricing without the UI

```r
# Source app.R (it loads every R/ module), then call run_pricing.
source("app.R")
result <- run_pricing("example_input.xlsx", output_path = "out.xlsx", seed = 1)
result$results
```

## Input workbook
Four sheets:
- `losses`: `year`, `loss`, `line_of_business`
- `exposure`: `year`, `exposure`
- `parameters`: `key`, `value` (keys: `reporting_threshold`, `loss_inflation_pa`,
  `modelling_threshold`, `splice_threshold`, `frequency_model`, `n_simulations`,
  `valuation_year`, `loading_ev`, `loading_sd`, `var_level`)
- `contract`: `deductible`, `cover`, `n_reinstatements`, `reinstatement_cost`,
  `aad`, `aal`

See `make_example.R` for a complete example.

## Method
Spliced lognormal plus Pareto severity with two thresholds (a modelling
threshold MT that drives frequency, and a higher splice point s where the
lognormal body hands over to the Pareto tail), Poisson frequency by default,
Monte Carlo aggregate loss, and a simulation-independent expected loss as a
validation check. Follows the experience-pricing recipe in the FS 2026
Reinsurance Analytics notes (Section 2.8). See docs/superpowers/specs for the
full design.

## Tests
`Rscript run_tests.R`
