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
5. Upload `input.xlsx`, set the thresholds on the Model step, then click Run pricing.

## Pricing without the UI
From inside the `engine` folder:

```r
# Source app.R (it loads every R/ module), then call run_pricing.
source("app.R")
result <- run_pricing("../input.xlsx", output_path = "../output.xlsx", seed = 1)
result$results
```

## Input workbook
The workbook holds the data only; the modelling choices and the contract
structure are set in the dashboard. It has four sheets: `losses`, `exposure`,
`inflation`, and `general inputs`. Run `Rscript engine/make_example.R` for a
ready-made example, and see `engine/docs/documentation.md` for the full
column-by-column schema.

## Using the dashboard
A guided, clickable four-step flow, each step with a "More information" panel:
1. **Data** — upload the workbook and review what loaded.
2. **Model** — set the modelling and splice thresholds and the frequency model,
   watching the live fit.
3. **Structure** — build the layer program (a tower diagram updates live).
4. **Price** — set the loadings and simulations, click **Run pricing**, read the
   results and validation, then **Download results**.

It opens with a three-layer demo so you can price straight away. See
`engine/docs/documentation.md` for the full walkthrough.

## Method
Spliced lognormal plus Pareto severity with two thresholds (a modelling
threshold MT that drives frequency, and a higher splice point s where the
lognormal body hands over to the Pareto tail), Poisson frequency by default,
Monte Carlo aggregate loss, and a simulation-independent expected loss as a
validation check. Follows the experience-pricing recipe in the FS 2026
Reinsurance Analytics notes (Section 2.8). See `engine/docs/documentation.md`
for the full methodology.

## Tests
From inside the `engine` folder: `Rscript run_tests.R`
