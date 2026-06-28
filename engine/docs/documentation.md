---
title: "Paco's Pricing Pipeline"
subtitle: "Technical and Actuarial Documentation"
author: "Francisco Martinez Checa"
date: "June 2026"
---

# Introduction

Paco's Pricing Pipeline is an R and Shiny tool that prices non-proportional
(excess of loss) reinsurance from a list of historical losses. You upload an
Excel workbook with the loss experience, choose how to model it, define the
reinsurance layers, and the tool runs a Monte Carlo simulation to produce an
expected loss, risk measures and a premium for each layer.

The methodology follows the experience-pricing recipe in *Reinsurance
Analytics, FS 2026* (P. Arbenz), Section 2.8, generalised so the severity is a
spliced lognormal plus Pareto rather than a single Pareto.

This document has two main parts:

- **Part 1, the technical guide**, covers the prerequisites, how to install and
  run the tool, the project layout, the input and output formats, and how the
  software is put together.
- **Part 2, the actuarial methodology**, explains the distributions that are
  fitted, how the Monte Carlo simulation works, the premium principles, and the
  independent validation check.

---

# Part 1: Technical guide

## What the tool does

At a high level the tool turns a history of losses into a price through four
stages:

1. **Pre-process.** Each historical loss is revalued to the valuation year for
   inflation and for the change in exposure, so old losses are stated in
   today's money and today's book size.
2. **Fit.** A frequency distribution is fitted to the yearly count of losses,
   and a severity distribution is fitted to the size of losses.
3. **Simulate.** A Monte Carlo simulation draws many possible years from the
   fitted models, applies the reinsurance layers to each year, and builds the
   distribution of the reinsured loss.
4. **Price.** For each layer the tool reports the expected loss, the volatility,
   tail risk measures, and a premium under two loading principles. A separate
   closed-form calculation cross-checks the simulation.

## The four-step workflow (dashboard)

The dashboard presents these stages as a guided, clickable four-step flow. Each
step has a collapsible "More information" panel that explains what it does.

| Step | Name | What you do |
|------|------|-------------|
| 1 | Data | Upload the workbook and review the general inputs, losses, exposure and inflation that loaded. |
| 2 | Model | Choose the modelling threshold, the splice threshold and the frequency model, while live plots show the fit. |
| 3 | Structure | Define the reinsurance layers (deductible, cover, aggregate deductible, aggregate limit). |
| 4 | Price | Set the loadings and the simulation size, run the pricing, and read the results and validation. |

The steps are clickable, so an experienced user can jump back to iterate;
Back and Next buttons walk the linear path. Nothing is gated.

## Prerequisites

- **Operating system.** Windows (the launcher scripts are Windows specific). The
  R code itself is cross-platform.
- **R.** A recent R installation (developed and tested on R 4.5.2). R is the
  only required runtime; there is no separate build step.
- **R packages.** `shiny` (the dashboard, which also brings `later` for the
  self-shutdown timer), `fitdistrplus` (lognormal maximum likelihood), `readxl`
  (reading Excel), and `openxlsx` (writing Excel). `testthat` is needed only to
  run the test suite. These are installed automatically on first run (see
  below).
- **Internet access (first run only).** Installing the packages needs to reach
  CRAN. On a locked-down network you can point the tool at an internal mirror by
  putting the mirror URL in a file named `CRAN_MIRROR.txt` next to the launcher.
- **Excel.** Not required to run the tool. It is only useful for viewing the
  input and output workbooks.

## Installation and first run

For an end user the simplest path is to double-click `start.vbs` in the top
folder. It launches the tool hidden (no console window) and opens the dashboard
in the default browser. `engine\start.bat` does the same with a visible console,
which is useful for troubleshooting.

On first run the launcher calls `install_deps.R`, which installs any missing
packages and then re-checks them. If a required package cannot be installed (for
example, no internet or a corporate firewall), it prints a clear message
explaining what to do rather than failing silently.

## Project layout

The project is split so end users see a clean top folder, while all the code
lives in `engine/`.

| Path | Contents |
|------|----------|
| `start.vbs` | Hidden launcher (double-click to run). |
| `input.xlsx` | The example input workbook (styled to match the dashboard). |
| `README.md` | Short orientation for the repository. |
| `engine/` | All the code and tests. |
| `engine/app.R` | The Shiny dashboard (UI and server). |
| `engine/R/` | One module per responsibility (see the module map). |
| `engine/tests/testthat/` | One test file per module. |
| `engine/make_example.R` | Regenerates the styled `input.xlsx` template. |
| `engine/install_deps.R` | Installs and verifies the required packages. |
| `engine/docs/` | This documentation (Markdown; a Word copy is at the repo root). |

## Ways to run it

All commands below run from inside the `engine/` folder.

- **Launch the dashboard:** `Rscript -e "shiny::runApp('.')"` (or open `app.R`
  in RStudio and click Run App).
- **Run the test suite:** `Rscript run_tests.R`.
- **Price a workbook without the UI:** source `app.R` (which loads every module)
  then call `run_pricing("../input.xlsx", overrides = list(...))`.
- **Regenerate the example workbook:** `Rscript make_example.R`.

## Input workbook format

A single Excel workbook with four sheets. The reinsurance structure is **not**
in the workbook; it is defined in the dashboard.

**Sheet `general inputs`** (key and value rows; an optional `notes` column may
describe each field and is ignored by the reader):

| key | example | required | notes |
|-----|---------|----------|-------|
| `valuation_year` | 2026 | yes | the year all losses are revalued to |
| `currency` | EUR | no | labels every amount in the dashboard and the export |
| `amount_units` | millions | no | labels the scale of the figures, e.g. millions |

The workbook may optionally also carry modelling defaults (modelling threshold,
splice threshold, frequency model, simulations, loadings, VaR level). When
present they seed the dashboard controls. The precedence is: dashboard control
overrides the workbook value, which overrides the built-in default (see
`resolve_settings` in `pipeline.R`). The modelling threshold has no fixed
built-in default: when neither the dashboard nor the workbook sets it, it starts
at the smallest loss in the history, so the model includes every loss until you
raise it.

**Sheet `losses`** (one row per individual loss):

| column | type | notes |
|--------|------|-------|
| `year` | integer | accident or occurrence year |
| `loss` | numeric | ground-up loss amount |
| `line_of_business` | text | optional, informational |

**Sheet `exposure`** (one row per year, including the prospective valuation
year):

| column | type | notes |
|--------|------|-------|
| `year` | integer | |
| `exposure` | numeric | exposure measure, for example number of risks or sum insured |

**Sheet `inflation`** (loss inflation is a per-year rate, not a single
constant):

| column | type | notes |
|--------|------|-------|
| `year` | integer | |
| `inflation` | numeric | loss inflation during that year, for example 0.03 for 3% |

## Output

When you download results from the dashboard, or pass an `output_path` to
`run_pricing`, the tool writes a two-sheet workbook:

- **`results`**: one row per layer with the expected loss, standard deviation,
  VaR, TVaR, both premiums, the closed-form expected loss, and the
  validation delta.
- **`assumptions`**: an echo of the fitted parameters and the settings used, so
  a result is self-documenting.

## Software architecture

The numerical work is split into small, independently testable modules in
`engine/R/`. The dashboard (`app.R`) only wires the user interface to these
modules; it contains no pricing mathematics of its own.

| module | responsibility |
|--------|----------------|
| `io.R` | read the input workbook, write the output workbook |
| `layers.R` | the per-loss layer function and the default program |
| `preprocess.R` | indexation, exposure correction, burning cost |
| `fit_frequency.R` | fit and scale Poisson, Negative Binomial or Binomial |
| `fit_severity.R` | fit the spliced lognormal and Pareto, survival, sampler |
| `simulate.R` | Monte Carlo of annual ground-up losses |
| `price.R` | apply the layers, compute premiums and risk metrics |
| `validate.R` | closed-form and numerical-integration validation oracle |
| `pipeline.R` | tie the modules together (`fit_models`, `price_models`, `run_pricing`) |
| `app.R` | the Shiny dashboard |

Two design points worth noting:

- **The fit is separated from the simulation.** `fit_models` is fast and runs
  live in the dashboard as you move the thresholds, while `price_models` runs
  the expensive Monte Carlo only when you press Run.
- **The dashboard owns the contract.** The program of layers lives in the
  dashboard, keyed by a stable id so adding or removing a layer never disturbs
  the others. The headless `run_pricing` path takes the same structure as an
  argument, defaulting to the built-in demo program.

The dashboard also manages its own lifecycle: it counts connected browser
sessions and shuts the tool down a few seconds after the last tab closes (a
short grace period tolerates a page refresh), and the most recent upload is kept
in a process-level store so a refresh does not lose the data.

---

# Part 2: Actuarial methodology

This part explains the models that are fitted and how the simulation turns them
into a price. Throughout, $X$ denotes the size of a single loss and $N$ the
number of losses in a year.

## Pre-processing: indexation and exposure

Historical losses cannot be used as they are: they happened in different years,
under different price levels and different book sizes. Two adjustments revalue
each loss to the valuation year.

**Loss inflation (indexation).** A loss is in money of its own year, so to
restate it in valuation-year money we compound the inflation rates of the years
*after* it:

$$ f^{infl}_{y} = \prod_{t = y+1}^{V} (1 + r_t) $$

where $y$ is the loss year, $V$ is the valuation year and $r_t$ is the inflation
rate for year $t$. If the valuation year is earlier than the loss year the same
product deflates instead (the factor is inverted). This is `inflation_factor` in
`preprocess.R`.

**Exposure correction (on-levelling).** The size of a loss is also scaled by how
the book grew or shrank between the loss year and the valuation year:

$$ f^{expo}_{y} = \frac{E_V}{E_y} $$

where $E_y$ is the exposure in year $y$. This is `exposure_factor`.

The indexed loss used everywhere downstream is therefore

$$ X^{indexed} = X \cdot f^{infl}_{y} \cdot f^{expo}_{y}. $$

**Exposure and frequency.** Exposure plays a second, separate role. A larger
prospective book is expected to produce proportionally more claims, so the
fitted frequency is scaled by the forward book size relative to the average book
size over the observed years:

$$ f^{freq} = \frac{E_V}{\frac{1}{n}\sum_{y \in \text{obs}} E_y}. $$

This is `exposure_frequency_factor`. When exposure is flat this factor is 1 and
nothing changes; a book that doubles roughly doubles the expected number of
claims. (The dashboard's information panels now explain both of these exposure
roles to the user.)

## Frequency model

The frequency is calibrated from the annual counts of losses **above the
modelling threshold** (the same conditioning used for the severity, so the two
are coherent). The user can choose one of three distributions; Poisson is the
principled default because reinsurance data is usually too sparse to select a
distribution class from the data alone.

Let $m$ be the mean and $v$ the variance of the annual counts.

- **Poisson.** $\hat\lambda = m$.
- **Negative Binomial** (only when $v > m$, that is, over-dispersion). Method of
  moments: size $r = m^2 / (v - m)$ with mean $\mu = m$.
- **Binomial** (only when $v < m$, that is, under-dispersion). Method of moments:
  $p = 1 - v/m$ and number of trials $n = \mathrm{round}(m / p)$.

The fitted mean is then scaled to the prospective book by the frequency factor
$f^{freq}$ above (`scale_frequency`): Poisson and Negative Binomial scale their
mean parameter directly, Binomial scales the number of trials.

## Severity model: spliced lognormal and Pareto

The severity is modelled **conditional on a loss exceeding the modelling
threshold MT**, because only those losses enter the model. Above MT the
distribution is spliced at a higher point $s$ (the splice threshold):

- **Body, for $MT < X \le s$:** a lognormal$(\mu, \sigma)$ fitted by maximum
  likelihood (via `fitdistrplus`) on the indexed losses in that range, used as a
  lognormal truncated to $(MT, s]$.
- **Tail, for $X > s$:** a Pareto with lower bound $x_0 = s$ and shape $\alpha$
  estimated by maximum likelihood:

$$ \hat\alpha = \frac{n}{\sum_i \log(x_i / s)} $$

over the losses above $s$.

- **Tail weight:** the empirical probability of being in the tail given a
  modelled loss,

$$ w = P(X > s \mid X > MT) = \frac{\#\{x_i > s\}}{\#\{x_i > MT\}}. $$

Because the body is weighted by $1 - w$ and the tail by $w$, with the Pareto
anchored at $x_0 = s$, the conditional mixture is continuous at $s$.

**Conditional survival function** $S(t) = P(X > t \mid X > MT)$, used both for
sampling intuition and directly by the validation oracle:

$$
S(t) =
\begin{cases}
1 & t \le MT \\[4pt]
(1 - w)\,\dfrac{F_{\ln}(s) - F_{\ln}(t)}{F_{\ln}(s) - F_{\ln}(MT)} + w & MT < t \le s \\[8pt]
w \left(\dfrac{t}{s}\right)^{-\alpha} & t > s
\end{cases}
$$

where $F_{\ln}$ is the lognormal CDF.

**Threshold choice.** Setting $s = MT$ empties the body and collapses the model
to a single Pareto. The dashboard shows the fitted versus empirical severity CDF,
which updates live as the thresholds move so the user can see how well the fit
matches the data and choose where the tail begins.

## Monte Carlo simulation

The simulation builds the distribution of the reinsured loss by drawing many
possible years from the fitted models. For a fixed random seed (so runs are
reproducible), each of the `n_simulations` iterations does the following:

1. **Draw the count.** Draw the annual number of losses $N$ from the fitted
   frequency distribution (`sample_frequency`).
2. **Draw the severities.** Draw $N$ loss sizes from the spliced severity
   conditional on $X > MT$ (`sample_severity`). Each draw uses inverse-CDF
   sampling: with probability $w$ it comes from the Pareto tail,
   $s \cdot U^{-1/\alpha}$; otherwise from the lognormal body truncated to
   $(MT, s]$.

This produces, for each simulated year, the list of ground-up losses
(`simulate.R`). The layers are then applied to each year (`price.R`).

**Applying a layer.** For a layer of cover $C$ excess of deductible $D$, each
loss contributes

$$ L_{D,C}(x) = \min(\max(x - D, 0),\, C). $$

These per-loss recoveries are summed over the year, and then the annual
aggregate features are applied **in this order**:

1. **Annual aggregate deductible (AAD):** the layer absorbs the first AAD of
   aggregate loss, so the aggregate becomes $\max(\text{agg} - \text{AAD}, 0)$. A
   blank or zero AAD means no aggregate deductible.
2. **Annual aggregate limit (AAL):** the aggregate is capped at AAL, so it
   becomes $\min(\text{agg}, \text{AAL})$. A blank or zero AAL means an unlimited
   aggregate.

A blank aggregate is deliberately distinguished from a value of 0 in the
dashboard: blank turns the control off, while 0 would mean a zero deductible or
a zero limit. Reinstatements are not modelled.

## Premium principles and risk metrics

Collecting the reinsured aggregate loss across all simulated years gives the
empirical loss distribution for each layer. From it (`price_layer`):

- **Expected loss** $E[L]$, the simulated mean.
- **Standard deviation** $\mathrm{sd}[L]$, the volatility of the annual loss.
- **Value at Risk** $\mathrm{VaR}_q$, the $q$ quantile of the annual loss at the
  user-chosen level $q$ (default 0.99).
- **Tail Value at Risk** $\mathrm{TVaR}_q$, the mean of the losses at or above
  the VaR.

Two premium principles are reported, both driven by user-set loadings:

$$ P_{EV} = (1 + \theta_{EV})\, E[L], \qquad P_{SD} = E[L] + \theta_{SD}\,\mathrm{sd}[L]. $$

## Validation: an independent oracle

The simulation is cross-checked by a calculation that shares none of its
machinery. The expected loss to a layer can be written, via the layer-integral
("Darth Vader") identity, as the integral of the survival function over the
layer, multiplied by the expected frequency:

$$ E[L_{D,C}] = E[N] \cdot \int_{D}^{D+C} S(t)\, dt. $$

The tool computes this integral by **deterministic numerical integration** of
the conditional survival $S$ (`expected_layer_loss` in `validate.R`), so it is
genuinely independent of the Monte Carlo path. As the number of simulations
grows, the simulated expected loss must converge to this oracle; the dashboard's
Validation table shows both and their difference per layer.

For a layer that sits entirely in the Pareto tail ($D \ge s$) the integral has a
closed form, which is kept as a unit-test anchor that the numerical integrator
must match:

$$ E[L_{D,C}] = w \cdot \frac{s^{\alpha}}{1 - \alpha}\left[(D+C)^{1-\alpha} - D^{1-\alpha}\right] \quad (\alpha \ne 1). $$

This validation applies to the per-layer expected loss; the aggregate features
(AAD and AAL) and the volatility and tail metrics come from the simulation only.

Alongside the oracle, the Validation table also shows the **burning cost**: the
average annual loss to each layer taken straight from the history, on an as-if
basis (every past loss indexed for inflation and corrected for exposure, as if it
had happened in the valuation year). Unlike the oracle, this carries no model, so
it is the external sense-check. Where the history is thick the modelled expected
loss should sit close to it; for a high layer above the historical experience the
burning cost reads near zero and the fitted Pareto tail is doing the work, which
is exactly where a parametric model earns its keep.

## Assumptions and limitations

- **Short-tail business.** The tool assumes losses are essentially fully
  developed; there is no loss development or IBNR allowance.
- **Non-proportional only.** It prices per-risk excess-of-loss programs.
  Proportional treaties are not yet supported.
- **No reinstatements.** The annual aggregate is the sum of per-loss recoveries
  subject to AAD then AAL.
- **No catastrophe model or exposure curves.** Pricing is purely experience
  based; there are no exposure rating curves or natural catastrophe models.
- **Distribution selection.** The frequency class is chosen by the user, not
  selected from the data, because reinsurance data is typically too sparse to
  support that choice.

## Future work

Several extensions were planned but deferred from v1, and the engine was
structured to accommodate them without rework: proportional treaties (quota
share and surplus), loss development and IBNR for long-tail lines, exposure
rating curves for low-data lines, and portfolio aggregation across several lines
of business (v1 prices a single book at a time).

---

# References

- P. Arbenz, *Reinsurance Analytics*, FS 2026, Section 2.8 (experience pricing).
  This third-party material is kept locally and is not distributed with the
  tool.
- The design and methodology are documented here; the implementation is in the
  R modules under `engine/R/`, each with a matching test in
  `engine/tests/testthat/`.
