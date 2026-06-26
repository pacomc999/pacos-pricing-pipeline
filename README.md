# Paco's Pragmatic Pricing Pipeline

An R and Shiny tool that prices non-proportional reinsurance from a historical
loss list. Excel in, Excel plus dashboard out.

## Easiest start (Windows)
**Double-click `start.bat`.** It is pure batch (no PowerShell) so it runs on
locked-down company machines. It finds an existing R install automatically,
whatever the version and wherever it lives, by checking:
1. a `R_PATH.txt` file in this folder, if present (see below),
2. `Rscript` on the PATH,
3. the Windows registry (where R records its install path),
4. the usual folders (`Program Files\R`, `Program Files (x86)\R`, and the
   per-user `Local\Programs\R`), newest version first.

Then it installs the package dependencies (first run only), generates the
example workbook, and opens the dashboard in your browser. Keep the small black
window open while you use the tool; close it to stop the dashboard. Loss data
stays on the machine and is never uploaded anywhere.

R must already be installed (this launcher does not install it, since company
machines often block installers). If `start.bat` cannot find R, either install
R from https://cran.r-project.org or, when R sits in an unusual location,
create a file named `R_PATH.txt` next to `start.bat` containing the full path
to `Rscript.exe`, for example:

```
D:\Tools\R\R-4.5.2\bin\Rscript.exe
```

If the required R packages cannot be installed (for example the company network
blocks CRAN), `start.bat` stops and prints a plain-English message naming the
missing packages instead of launching into an error. To use an internal CRAN
mirror, create a file named `CRAN_MIRROR.txt` next to `start.bat` containing the
mirror URL, then run `start.bat` again. The packages used are `shiny`,
`actuar`, `fitdistrplus`, `readxl`, `openxlsx`, and `ggplot2` (all available as
ready-built Windows binaries on CRAN, so no compiler is needed).

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
