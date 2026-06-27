# Paco's Pricing Pipeline

An R and Shiny tool that prices non-proportional reinsurance from a historical
loss list. Excel in, Excel plus dashboard out.

## Easiest start (Windows)
**Double-click `start.vbs`.** The dashboard opens in your browser with no
console window. To stop the tool, click **Shut down** in the dashboard, or just
close the browser tab (it shuts itself down automatically a few seconds later).

If your company blocks `.vbs` files, double-click **`engine\start.bat`**
instead. It does exactly the same thing but shows a small console window (close
it to stop the tool). `engine\start.bat` is also handy when you want to see
progress or error messages directly.

Everything else lives in the `engine` folder; the top level holds only
`start.vbs`, your `input.xlsx`, and this README.

Both launchers find an existing R install automatically, whatever the version
and wherever it lives, by checking:
1. a `R_PATH.txt` file in the `engine` folder, if present (see below),
2. `Rscript` on the PATH,
3. the Windows registry (where R records its install path),
4. the usual folders (`Program Files\R`, `Program Files (x86)\R`, and the
   per-user `Local\Programs\R`), newest version first.

They then install the package dependencies (first run only), generate the
top-level `input.xlsx` template, and open the dashboard. Loss data stays on the
machine and is never uploaded anywhere. (`engine\start.bat` is pure batch with no
PowerShell, so it runs on locked-down machines; `start.vbs` uses Windows Script
Host purely to hide the console.)

R must already be installed (the launchers do not install it, since company
machines often block installers). If R cannot be found, either install R from
https://cran.r-project.org or, when R sits in an unusual location, create a file
named `R_PATH.txt` in the `engine` folder containing the full path to
`Rscript.exe`, for example:

```
D:\Tools\R\R-4.5.2\bin\Rscript.exe
```

If the required R packages cannot be installed (for example the company network
blocks CRAN), the tool does not launch into a cryptic error: `start.bat` prints
a plain-English message naming the missing packages, and `start.vbs` shows the
same message in a popup. To use an internal CRAN mirror, create a file named
`CRAN_MIRROR.txt` in the `engine` folder containing the mirror URL, then run the
launcher again. The packages used are `shiny`, `fitdistrplus`, `readxl`, and
`openxlsx` (plus `later`, which ships with shiny). All are available as
ready-built Windows binaries on CRAN, so no compiler is needed.

## Quick start (any platform, command line)
Run these from inside the `engine` folder:
1. Install R (4.x).
2. Install dependencies: `Rscript install_deps.R`
3. Generate the input template: `Rscript make_example.R` (writes ../input.xlsx)
4. Launch the dashboard: `Rscript -e "shiny::runApp('.', launch.browser = TRUE)"`
5. Upload `input.xlsx`, set the thresholds on the Fit tab, then click Run pricing.

## Pricing without the UI
From inside the `engine` folder:

```r
# Source app.R (it loads every R/ module), then call run_pricing.
source("app.R")
result <- run_pricing("../input.xlsx", output_path = "../output.xlsx", seed = 1)
result$results
```

## Input workbook
The workbook holds the data; the modelling choices and the contract structure
are made in the dashboard. Four sheets:
- `losses`: `year`, `loss`, `line_of_business`
- `exposure`: `year`, `exposure`
- `inflation`: `year`, `inflation` (the per-year loss inflation rate, e.g. 0.03
  for 3%; a loss is revalued by compounding the rates of the years after it up
  to the valuation year)
- `parameters`: `key`, `value` (only the data parameters: `reporting_threshold`,
  `valuation_year`)

The modelling threshold, splice threshold, frequency model, simulation count,
loadings, and VaR level are set as controls in the dashboard (not in the file),
so you can tune them while watching the fit. The reinsurance layers (the
contract structure) are built on the dashboard's **Structure** tab, where you
add or remove layers and edit each one's deductible, cover, AAD, and AAL.

See `engine/make_example.R` for a complete example.

## Using the dashboard
1. Upload your workbook (`input.xlsx`, or any file with the same sheets). The
   upload stays loaded if you refresh the page; it is cleared only when you
   close the tool.
2. On the **Structure** tab, build the program: add or remove layers and edit
   each layer's deductible, cover, AAD, and AAL. It starts with
   a three-layer demo so you can price straight away.
3. On the **Fit** tab, adjust the modelling threshold and splice point while
   watching the mean-excess plot (to choose where the tail begins), the fitted
   vs empirical severity, and the live fitted parameters (lambda, alpha, etc.).
4. Set the frequency model, simulations, and loadings.
5. Click **Run pricing**; view the per-layer table on the **Pricing** tab and
   the simulation-vs-closed-form check on the **Validation** tab.
5. **Download results** writes `output.xlsx`.

## Method
Spliced lognormal plus Pareto severity with two thresholds (a modelling
threshold MT that drives frequency, and a higher splice point s where the
lognormal body hands over to the Pareto tail), Poisson frequency by default,
Monte Carlo aggregate loss, and a simulation-independent expected loss as a
validation check. Follows the experience-pricing recipe in the FS 2026
Reinsurance Analytics notes (Section 2.8). See engine/docs/superpowers/specs for
the full design.

## Tests
From inside the `engine` folder: `Rscript run_tests.R`
