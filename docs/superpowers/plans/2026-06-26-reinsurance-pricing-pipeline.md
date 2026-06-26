# Reinsurance Pricing Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an R + Shiny tool that prices non-proportional reinsurance from an Excel loss list and returns prices plus risk metrics as Excel and an interactive dashboard.

**Architecture:** A set of small, single-responsibility R modules in `R/` (Excel I/O, pre-processing, frequency fit, severity fit, closed-form validation, Monte Carlo simulation, contract pricing, orchestration) consumed by a thin Shiny app (`app.R`). The Monte Carlo simulation produces the aggregate loss distribution; closed-form formulas act as an exact validation oracle for the simulated expected layer loss.

**Tech Stack:** R, Shiny, `actuar`, `fitdistrplus`, `readxl`, `openxlsx`, `ggplot2`, `testthat`.

## Global Constraints

- Stack is R + Shiny. No TypeScript. No other frameworks.
- Every module uses `package::function` qualified calls (no `library()` inside `R/` files) so tests can source files without side effects.
- Coding rules (from CLAUDE.md): never use dashes (em dash, en dash) in visible text or copy; clear variable names; comment each section explaining what it does; short focused functions.
- Default frequency model is Poisson.
- Modelling/splice threshold `u` must satisfy `reporting_threshold <= u <= lowest layer deductible`. v1 layers therefore attach at or above `u`; the lognormal body is fitted and displayed but does not affect v1 layer prices.
- Severity is a spliced distribution: lognormal body (losses `<= u`), Pareto tail (losses `> u`), `x0 = u`, tail weight `= empirical P(X > u)`, mixture CDF continuous at `u`.
- Closed-form expected layer loss is the validation oracle: simulated mean must converge to it for pure per-layer cases.
- Git commits after every task. Commit messages in present tense, short.

---

## File structure

```
R/
  io.R            # read_input, write_output (Excel)
  layers.R        # apply_layer (shared layer function)
  preprocess.R    # index_losses, exposure_factor, burning_cost
  fit_frequency.R # annual_counts, fit_frequency, sample_frequency
  fit_severity.R  # fit_pareto_alpha, fit_severity, severity_cdf, sample_tail, sample_severity
  validate.R      # pareto_layer_ev, lnorm_limited_ev, expected_layer_loss
  simulate.R      # simulate_annual_losses
  price.R         # price_layer, price_program
  pipeline.R      # run_pricing (end to end orchestration)
app.R             # Shiny UI + server
run_tests.R       # testthat::test_dir("tests/testthat")
tests/testthat/
  helper-setup.R  # sources all R/*.R before tests
  test-*.R        # one per module
make_example.R    # writes example_input.xlsx
CLAUDE.md
README.md
docs/superpowers/...
```

---

### Task 1: Project scaffold, dependencies, test harness, CLAUDE.md

**Files:**
- Create: `R/.gitkeep`, `run_tests.R`, `tests/testthat/helper-setup.R`, `tests/testthat/test-smoke.R`, `install_deps.R`, `CLAUDE.md`, `.gitignore`

**Interfaces:**
- Produces: a runnable test harness. `run_tests.R` executes `testthat::test_dir("tests/testthat")`; `tests/testthat/helper-setup.R` sources every file in `R/`.

- [ ] **Step 1: Create `.gitignore`**

```gitignore
.Rproj.user
.Rhistory
.RData
.Rapp.history
*.xlsx
!example_input.xlsx
```

- [ ] **Step 2: Create `install_deps.R`**

```r
# Installs every package the pipeline needs. Run once after cloning.
pkgs <- c("shiny", "actuar", "fitdistrplus", "readxl", "openxlsx", "ggplot2", "testthat")
to_install <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(to_install) > 0) install.packages(to_install)
```

- [ ] **Step 3: Create `tests/testthat/helper-setup.R`**

```r
# Sources every module in R/ so tests can call the functions directly.
# testthat sets the working directory to tests/testthat, so the project
# root is two levels up.
.project_root <- normalizePath(file.path(getwd(), "..", ".."))
r_files <- list.files(file.path(.project_root, "R"), pattern = "[.]R$", full.names = TRUE)
for (f in r_files) source(f, local = FALSE)
```

- [ ] **Step 4: Create `run_tests.R`**

```r
# Runs the full test suite from the project root.
testthat::test_dir("tests/testthat")
```

- [ ] **Step 5: Create `R/.gitkeep`** (empty file so the empty dir is tracked)

```
```

- [ ] **Step 6: Write the smoke test `tests/testthat/test-smoke.R`**

```r
test_that("test harness runs", {
  expect_equal(1 + 1, 2)
})
```

- [ ] **Step 7: Run the suite to verify it passes**

Run: `Rscript run_tests.R`
Expected: PASS (1 test), no errors.

- [ ] **Step 8: Create `CLAUDE.md`**

```markdown
# CLAUDE.md

Project-specific guidance for Paco's Pragmatic Pricing Pipeline. This overrides
the workspace CLAUDE.md (which is for the browser game and visualizer projects).

## What this is
An R + Shiny tool that prices non-proportional reinsurance from a historical
loss list. Excel in, Excel plus dashboard out. Methodology follows the
experience-pricing recipe in Literature/Reinsurance_Analytics_2026_vFeb.pdf
(Section 2.8), generalised to a spliced lognormal plus Pareto severity.

## Running
- Install dependencies once: `Rscript install_deps.R`
- Run the test suite: `Rscript run_tests.R`
- Launch the dashboard: `Rscript -e "shiny::runApp('.')"` (or open app.R in RStudio and click Run App)
- Price a workbook without the UI: source R/pipeline.R and call run_pricing()

## Layout
- R/ holds one module per responsibility (see the design spec).
- tests/testthat/ holds one test file per module; helper-setup.R sources R/.
- docs/superpowers/ holds the design spec and this plan.

## Conventions
- R + Shiny only. No TypeScript.
- Never use dashes (em dash, en dash) in visible text or copy.
- Modules use package::function calls; no library() inside R/ files.
- Clear variable names, a comment per section, short focused functions.
- Commit messages in present tense.

## Developer
Francisco Martinez Checa (GitHub: pacomc999). Learning as I go; explain changes.
```

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Scaffold project structure and test harness"
```

---

### Task 2: Excel input reader

**Files:**
- Create: `R/io.R`, `tests/testthat/test-io.R`

**Interfaces:**
- Produces: `read_input(path)` returns a list with elements `losses` (data.frame: `year`, `loss`, `line_of_business`), `exposure` (data.frame: `year`, `exposure`), `parameters` (named list), `contract` (data.frame: `deductible`, `cover`, `n_reinstatements`, `reinstatement_cost`, `aad`, `aal`). `parameters` contains `reporting_threshold`, `loss_inflation_pa`, `splice_threshold_u`, `frequency_model`, `n_simulations`, `valuation_year`, `loading_ev`, `loading_sd`, `var_level`.

- [ ] **Step 1: Write the failing test `tests/testthat/test-io.R`**

```r
# Helper that writes a minimal valid workbook to a temp file.
write_tmp_workbook <- function() {
  path <- tempfile(fileext = ".xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "losses")
  openxlsx::writeData(wb, "losses", data.frame(
    year = c(2021, 2021, 2023),
    loss = c(12, 9.5, 18),
    line_of_business = c("fire", "fire", "fire")
  ))
  openxlsx::addWorksheet(wb, "exposure")
  openxlsx::writeData(wb, "exposure", data.frame(
    year = 2021:2025,
    exposure = c(120, 120, 130, 140, 145)
  ))
  openxlsx::addWorksheet(wb, "parameters")
  openxlsx::writeData(wb, "parameters", data.frame(
    key = c("reporting_threshold", "loss_inflation_pa", "splice_threshold_u",
            "frequency_model", "n_simulations", "valuation_year",
            "loading_ev", "loading_sd", "var_level"),
    value = c("5", "0.02", "5", "poisson", "100000", "2026", "0.1", "0.2", "0.99")
  ))
  openxlsx::addWorksheet(wb, "contract")
  openxlsx::writeData(wb, "contract", data.frame(
    deductible = c(5, 10), cover = c(5, 10),
    n_reinstatements = c(1, 1), reinstatement_cost = c(1, 1),
    aad = c(0, 0), aal = c(0, 0)
  ))
  openxlsx::saveWorkbook(wb, path)
  path
}

test_that("read_input parses all four sheets with correct types", {
  path <- write_tmp_workbook()
  input <- read_input(path)

  expect_equal(nrow(input$losses), 3)
  expect_true(is.numeric(input$losses$loss))

  expect_equal(input$parameters$frequency_model, "poisson")
  expect_equal(input$parameters$valuation_year, 2026)
  expect_equal(input$parameters$loss_inflation_pa, 0.02)

  expect_equal(nrow(input$contract), 2)
  expect_equal(input$contract$deductible[2], 10)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-io.R')"`
Expected: FAIL with "could not find function read_input".

- [ ] **Step 3: Write `R/io.R`**

```r
# Reads the four-sheet pricing workbook into a structured list.
read_input <- function(path) {
  losses <- as.data.frame(readxl::read_excel(path, sheet = "losses"))
  exposure <- as.data.frame(readxl::read_excel(path, sheet = "exposure"))
  contract <- as.data.frame(readxl::read_excel(path, sheet = "contract"))

  # Parameters arrive as key/value rows; turn them into a typed named list.
  raw_params <- as.data.frame(readxl::read_excel(path, sheet = "parameters"))
  pv <- setNames(as.character(raw_params$value), raw_params$key)
  num <- function(k) as.numeric(pv[[k]])
  parameters <- list(
    reporting_threshold = num("reporting_threshold"),
    loss_inflation_pa   = num("loss_inflation_pa"),
    splice_threshold_u  = num("splice_threshold_u"),
    frequency_model     = pv[["frequency_model"]],
    n_simulations       = as.integer(num("n_simulations")),
    valuation_year      = as.integer(num("valuation_year")),
    loading_ev          = num("loading_ev"),
    loading_sd          = num("loading_sd"),
    var_level           = num("var_level")
  )

  losses$loss <- as.numeric(losses$loss)
  losses$year <- as.integer(losses$year)

  list(losses = losses, exposure = exposure,
       parameters = parameters, contract = contract)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-io.R')"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/io.R tests/testthat/test-io.R
git commit -m "Add Excel input reader"
```

---

### Task 3: Layer function, pre-processing, burning cost

**Files:**
- Create: `R/layers.R`, `R/preprocess.R`, `tests/testthat/test-preprocess.R`

**Interfaces:**
- Consumes: `losses`, `exposure`, `parameters` from `read_input`.
- Produces:
  - `apply_layer(x, D, C)` returns `pmin(pmax(x - D, 0), C)` (vectorised).
  - `exposure_factor(exposure, loss_year, valuation_year)` returns the exposure scaling ratio.
  - `index_losses(losses, exposure, params)` returns `losses` with a new numeric column `loss_indexed`.
  - `burning_cost(losses_indexed, contract)` returns a data.frame with one row per layer and columns `deductible`, `cover`, `bc_simple`, `bc_advanced`.

- [ ] **Step 1: Write the failing test `tests/testthat/test-preprocess.R`**

```r
test_that("apply_layer caps and floors correctly", {
  expect_equal(apply_layer(12, 5, 5), 5)   # loss above top of layer
  expect_equal(apply_layer(7, 5, 5), 2)    # loss inside layer
  expect_equal(apply_layer(3, 5, 5), 0)    # loss below attachment
  expect_equal(apply_layer(c(3, 7, 12), 5, 5), c(0, 2, 5))
})

test_that("index_losses reproduces the notes advanced burning cost basis", {
  # From Reinsurance Analytics Table 8: 2% inflation, exposure growth to 150.
  losses <- data.frame(year = c(2021, 2021), loss = c(12, 9.5),
                       line_of_business = c("x", "x"))
  exposure <- data.frame(year = 2021:2026,
                         exposure = c(120, 120, 130, 140, 145, 150))
  params <- list(loss_inflation_pa = 0.02, valuation_year = 2026)

  out <- index_losses(losses, exposure, params)
  # 12 * 1.02^5 * (150/120) = 13.25 * 1.25 = 16.56 (to 2 dp)
  expect_equal(round(out$loss_indexed[1], 2), 16.56)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-preprocess.R')"`
Expected: FAIL with "could not find function apply_layer".

- [ ] **Step 3: Write `R/layers.R`**

```r
# Loss to a layer C excess of D, vectorised over x.
apply_layer <- function(x, D, C) {
  pmin(pmax(x - D, 0), C)
}
```

- [ ] **Step 4: Write `R/preprocess.R`**

```r
# Ratio of exposure in the valuation year to exposure in the loss year.
exposure_factor <- function(exposure, loss_year, valuation_year) {
  e_now <- exposure$exposure[exposure$year == valuation_year]
  e_then <- exposure$exposure[exposure$year == loss_year]
  if (length(e_now) == 0 || length(e_then) == 0) return(1)
  e_now / e_then
}

# Revalues each loss to the valuation year: loss inflation then exposure change.
index_losses <- function(losses, exposure, params) {
  infl <- (1 + params$loss_inflation_pa) ^ (params$valuation_year - losses$year)
  expo <- vapply(losses$year, function(y) {
    exposure_factor(exposure, y, params$valuation_year)
  }, numeric(1))
  losses$loss_indexed <- losses$loss * infl * expo
  losses
}

# Average loss to each layer, simple (raw) and advanced (indexed), per year.
burning_cost <- function(losses_indexed, contract) {
  years <- sort(unique(losses_indexed$year))
  rows <- lapply(seq_len(nrow(contract)), function(i) {
    D <- contract$deductible[i]; C <- contract$cover[i]
    simple_by_year <- vapply(years, function(y) {
      sum(apply_layer(losses_indexed$loss[losses_indexed$year == y], D, C))
    }, numeric(1))
    adv_by_year <- vapply(years, function(y) {
      sum(apply_layer(losses_indexed$loss_indexed[losses_indexed$year == y], D, C))
    }, numeric(1))
    data.frame(deductible = D, cover = C,
               bc_simple = mean(simple_by_year),
               bc_advanced = mean(adv_by_year))
  })
  do.call(rbind, rows)
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-preprocess.R')"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add R/layers.R R/preprocess.R tests/testthat/test-preprocess.R
git commit -m "Add layer function, indexation and burning cost"
```

---

### Task 4: Frequency fitting

**Files:**
- Create: `R/fit_frequency.R`, `tests/testthat/test-fit_frequency.R`

**Interfaces:**
- Consumes: `losses` (indexed or raw), the observation period from `exposure$year`, threshold `u`.
- Produces:
  - `annual_counts(losses, years, threshold)` returns an integer vector of counts of losses above `threshold` for each year in `years` (zero-loss years included).
  - `fit_frequency(counts, model)` returns a list `list(type, params, expected)`. `model` is one of `"poisson"`, `"negbin"`, `"binomial"`. `expected` is `E[N]`.
  - `sample_frequency(fit, n)` returns an integer vector of `n` simulated annual counts.

- [ ] **Step 1: Write the failing test `tests/testthat/test-fit_frequency.R`**

```r
test_that("annual_counts includes zero-loss years", {
  losses <- data.frame(year = c(2021, 2021, 2023, 2024, 2024, 2024, 2025),
                       loss = c(12, 9.5, 18, 13, 7, 11, 14))
  counts <- annual_counts(losses, years = 2021:2025, threshold = 5)
  expect_equal(counts, c(2, 0, 1, 3, 1))   # 2022 is a zero year
})

test_that("Poisson fit matches the notes lambda of 1.4", {
  counts <- c(2, 0, 1, 3, 1)
  fit <- fit_frequency(counts, "poisson")
  expect_equal(fit$type, "poisson")
  expect_equal(fit$expected, 1.4)
})

test_that("sample_frequency returns non-negative integers of correct length", {
  set.seed(1)
  fit <- fit_frequency(c(2, 0, 1, 3, 1), "poisson")
  s <- sample_frequency(fit, 1000)
  expect_length(s, 1000)
  expect_true(all(s >= 0))
  expect_equal(abs(mean(s) - 1.4) < 0.2, TRUE)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-fit_frequency.R')"`
Expected: FAIL with "could not find function annual_counts".

- [ ] **Step 3: Write `R/fit_frequency.R`**

```r
# Counts losses above the threshold for each year in the observation period.
annual_counts <- function(losses, years, threshold) {
  above <- losses[losses$loss > threshold, ]
  vapply(years, function(y) sum(above$year == y), integer(1))
}

# Fits a frequency distribution to annual counts. Poisson is the default.
fit_frequency <- function(counts, model = "poisson") {
  m <- mean(counts)
  v <- stats::var(counts)
  if (model == "poisson") {
    list(type = "poisson", params = list(lambda = m), expected = m)
  } else if (model == "negbin") {
    # Method of moments: var = mean * (1 + beta), size r = mean^2 / (var - mean).
    if (v <= m) stop("Negative Binomial needs variance greater than mean.")
    size <- m^2 / (v - m)
    list(type = "negbin", params = list(size = size, mu = m), expected = m)
  } else if (model == "binomial") {
    # Method of moments for Binomial: p = 1 - var/mean, n = mean / p.
    if (v >= m) stop("Binomial needs variance smaller than mean.")
    p <- 1 - v / m
    n <- round(m / p)
    list(type = "binomial", params = list(size = n, prob = p), expected = n * p)
  } else {
    stop("Unknown frequency model: ", model)
  }
}

# Draws n simulated annual counts from a fitted frequency distribution.
sample_frequency <- function(fit, n) {
  p <- fit$params
  switch(fit$type,
    poisson  = stats::rpois(n, p$lambda),
    negbin   = stats::rnbinom(n, size = p$size, mu = p$mu),
    binomial = stats::rbinom(n, size = p$size, prob = p$prob),
    stop("Unknown frequency type: ", fit$type)
  )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-fit_frequency.R')"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/fit_frequency.R tests/testthat/test-fit_frequency.R
git commit -m "Add frequency fitting and sampling"
```

---

### Task 5: Severity fitting (spliced lognormal plus Pareto)

**Files:**
- Create: `R/fit_severity.R`, `tests/testthat/test-fit_severity.R`

**Interfaces:**
- Consumes: indexed losses (numeric vector), threshold `u`.
- Produces:
  - `fit_pareto_alpha(x, x0)` returns the MLE `length(x) / sum(log(x / x0))`.
  - `fit_severity(loss_values, u)` returns a list `list(u, weight, lnorm = list(meanlog, sdlog), pareto = list(x0, alpha))`. `weight` is the empirical `P(X > u)`. `lnorm` is fitted to `loss_values[loss_values <= u]`; if fewer than two such points exist, `lnorm` is `NULL`.
  - `sample_tail(fit, n)` returns `n` Pareto draws conditional on exceeding `u` (the severity entering v1 layers).
  - `severity_cdf(fit, x)` returns the full spliced mixture CDF at `x` (for diagnostics).
  - `sample_severity(fit, n)` returns `n` draws from the full spliced mixture (for v2 and diagnostics).

- [ ] **Step 1: Write the failing test `tests/testthat/test-fit_severity.R`**

```r
test_that("fit_pareto_alpha reproduces the notes alpha of 1.184", {
  x <- c(12, 9.5, 18, 13, 7, 11, 14)   # losses above u = 5
  alpha <- fit_pareto_alpha(x, x0 = 5)
  expect_equal(round(alpha, 3), 1.184)
})

test_that("sample_tail draws stay above u and follow the Pareto tail", {
  set.seed(42)
  fit <- list(u = 5, weight = 1,
              lnorm = list(meanlog = 0, sdlog = 1),
              pareto = list(x0 = 5, alpha = 1.184))
  s <- sample_tail(fit, 50000)
  expect_true(all(s >= 5))
  # Survival at 10 should be (10/5)^-1.184 = 0.44 (to 2 dp).
  expect_equal(round(mean(s > 10), 2), 0.44)
})

test_that("severity_cdf is continuous at u", {
  fit <- list(u = 5, weight = 0.3,
              lnorm = list(meanlog = log(3), sdlog = 0.5),
              pareto = list(x0 = 5, alpha = 1.5))
  below <- severity_cdf(fit, 5 - 1e-6)
  at    <- severity_cdf(fit, 5)
  expect_lt(abs(at - below), 1e-3)   # no jump at the splice point
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-fit_severity.R')"`
Expected: FAIL with "could not find function fit_pareto_alpha".

- [ ] **Step 3: Write `R/fit_severity.R`**

```r
# Maximum likelihood alpha for a Pareto with known lower bound x0.
fit_pareto_alpha <- function(x, x0) {
  x <- x[x > x0]
  length(x) / sum(log(x / x0))
}

# Fits the spliced severity: lognormal body below u, Pareto tail above u.
fit_severity <- function(loss_values, u) {
  body <- loss_values[loss_values <= u]
  tail <- loss_values[loss_values > u]
  weight <- length(tail) / length(loss_values)   # empirical P(X > u)

  lnorm <- NULL
  if (length(body) >= 2) {
    fit <- fitdistrplus::fitdist(body, "lnorm")
    lnorm <- list(meanlog = unname(fit$estimate["meanlog"]),
                  sdlog   = unname(fit$estimate["sdlog"]))
  }

  list(
    u = u,
    weight = weight,
    lnorm = lnorm,
    pareto = list(x0 = u, alpha = fit_pareto_alpha(tail, u))
  )
}

# Draws n Pareto tail severities (conditional on exceeding u). Inverse CDF:
# X = x0 * U^(-1/alpha) gives P(X > x) = (x/x0)^(-alpha).
sample_tail <- function(fit, n) {
  u <- runif(n)
  fit$pareto$x0 * u ^ (-1 / fit$pareto$alpha)
}

# Full spliced mixture CDF (body weighted 1-w, tail weighted w). Continuous at u.
severity_cdf <- function(fit, x) {
  w <- fit$weight
  u <- fit$u
  alpha <- fit$pareto$alpha
  # Body contribution: lognormal mass scaled so it reaches (1 - w) at u.
  body_cdf <- if (!is.null(fit$lnorm)) {
    raw <- stats::plnorm(pmin(x, u), fit$lnorm$meanlog, fit$lnorm$sdlog)
    at_u <- stats::plnorm(u, fit$lnorm$meanlog, fit$lnorm$sdlog)
    (1 - w) * raw / at_u
  } else {
    rep(0, length(x))
  }
  # Tail contribution: 0 below u, then climbs from (1-w) to 1.
  tail_cdf <- ifelse(x > u, (1 - w) + w * (1 - (x / u) ^ (-alpha)), 0)
  ifelse(x <= u, body_cdf, tail_cdf)
}

# Draws n severities from the full spliced mixture (for diagnostics and v2).
sample_severity <- function(fit, n) {
  w <- fit$u  # placeholder guard; real weight below
  w <- fit$weight
  is_tail <- runif(n) < w
  out <- numeric(n)
  out[is_tail] <- sample_tail(fit, sum(is_tail))
  if (any(!is_tail) && !is.null(fit$lnorm)) {
    # Lognormal truncated to (0, u] via inverse CDF on the truncated range.
    at_u <- stats::plnorm(fit$u, fit$lnorm$meanlog, fit$lnorm$sdlog)
    u_draw <- runif(sum(!is_tail), 0, at_u)
    out[!is_tail] <- stats::qlnorm(u_draw, fit$lnorm$meanlog, fit$lnorm$sdlog)
  }
  out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-fit_severity.R')"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/fit_severity.R tests/testthat/test-fit_severity.R
git commit -m "Add spliced severity fitting and sampling"
```

---

### Task 6: Closed-form validation oracle

**Files:**
- Create: `R/validate.R`, `tests/testthat/test-validate.R`

**Interfaces:**
- Consumes: a frequency fit (`expected`), a severity fit (`u`, `pareto$alpha`).
- Produces:
  - `pareto_layer_ev(x0, alpha, D, C)` returns the expected loss to layer `C xs D` for a Pareto severity (requires `D >= x0`, `alpha != 1`).
  - `lnorm_limited_ev(meanlog, sdlog, u)` returns `E[min(X, u)]` for a lognormal (used in v2 and for completeness).
  - `expected_layer_loss(freq_fit, sev_fit, D, C)` returns `freq_fit$expected * pareto_layer_ev(sev_fit$u, sev_fit$pareto$alpha, D, C)`, the closed-form expected annual loss to the layer (valid for `D >= u`).

- [ ] **Step 1: Write the failing test `tests/testthat/test-validate.R`**

```r
test_that("pareto_layer_ev reproduces the notes Table 13 severity layer costs", {
  alpha <- 1.184; x0 <- 5
  expect_equal(round(pareto_layer_ev(x0, alpha, 5, 5), 2), 3.25)
  expect_equal(round(pareto_layer_ev(x0, alpha, 10, 10), 2), 2.86)
  expect_equal(round(pareto_layer_ev(x0, alpha, 20, 10), 2), 1.51)
})

test_that("expected_layer_loss multiplies by frequency (Table 13 expected sums)", {
  freq <- list(expected = 1.4)
  sev <- list(u = 5, pareto = list(x0 = 5, alpha = 1.184))
  # 1.4 * 3.25 = 4.55 (notes report 4.56 with rounding)
  expect_equal(round(expected_layer_loss(freq, sev, 5, 5), 2), 4.55)
})

test_that("lnorm_limited_ev is bounded above by u and below by the unlimited mean", {
  m <- log(3); s <- 0.5
  unlimited <- exp(m + s^2 / 2)
  lev <- lnorm_limited_ev(m, s, u = 4)
  expect_lt(lev, unlimited)
  expect_lt(lev, 4)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-validate.R')"`
Expected: FAIL with "could not find function pareto_layer_ev".

- [ ] **Step 3: Write `R/validate.R`**

```r
# Expected loss to layer C xs D for a Pareto(x0, alpha) severity, D >= x0.
# E[L] = integral_D^{D+C} (t/x0)^{-alpha} dt  (Darth Vader rule, Example 2.45).
pareto_layer_ev <- function(x0, alpha, D, C) {
  if (alpha == 1) {
    x0 * (log(D + C) - log(D))
  } else {
    (x0 ^ alpha / (1 - alpha)) * ((D + C) ^ (1 - alpha) - D ^ (1 - alpha))
  }
}

# Limited expected value E[min(X, u)] for a lognormal(meanlog, sdlog).
lnorm_limited_ev <- function(meanlog, sdlog, u) {
  m <- meanlog; s <- sdlog
  exp(m + s^2 / 2) * stats::pnorm((log(u) - m - s^2) / s) +
    u * (1 - stats::pnorm((log(u) - m) / s))
}

# Closed-form expected annual loss to a layer (validation oracle, D >= u).
expected_layer_loss <- function(freq_fit, sev_fit, D, C) {
  freq_fit$expected *
    pareto_layer_ev(sev_fit$pareto$x0, sev_fit$pareto$alpha, D, C)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-validate.R')"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/validate.R tests/testthat/test-validate.R
git commit -m "Add closed-form validation oracle"
```

---

### Task 7: Monte Carlo simulation

**Files:**
- Create: `R/simulate.R`, `tests/testthat/test-simulate.R`

**Interfaces:**
- Consumes: a frequency fit, a severity sampler function `function(n) -> numeric`, `n_sims`, optional `seed`.
- Produces: `simulate_annual_losses(freq_fit, severity_sampler, n_sims, seed = NULL)` returns a list of length `n_sims`; each element is a numeric vector of the individual losses simulated for that year (length equals that year's drawn count, possibly zero).

- [ ] **Step 1: Write the failing test `tests/testthat/test-simulate.R`**

```r
test_that("simulate_annual_losses returns one element per simulated year", {
  freq <- list(type = "poisson", params = list(lambda = 1.4), expected = 1.4)
  sampler <- function(n) rep(10, n)   # deterministic severity for counting
  sims <- simulate_annual_losses(freq, sampler, n_sims = 1000, seed = 7)
  expect_length(sims, 1000)
  # Mean count per year should be close to lambda = 1.4.
  mean_count <- mean(vapply(sims, length, integer(1)))
  expect_true(abs(mean_count - 1.4) < 0.15)
})

test_that("simulated total loss mean matches frequency times severity mean", {
  freq <- list(type = "poisson", params = list(lambda = 2), expected = 2)
  sampler <- function(n) rep(5, n)
  sims <- simulate_annual_losses(freq, sampler, n_sims = 20000, seed = 3)
  totals <- vapply(sims, sum, numeric(1))
  expect_true(abs(mean(totals) - 2 * 5) < 0.2)   # E[N]*E[X] = 10
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-simulate.R')"`
Expected: FAIL with "could not find function simulate_annual_losses".

- [ ] **Step 3: Write `R/simulate.R`**

```r
# Monte Carlo of annual ground-up losses entering the layers.
# Each simulated year: draw a loss count N, then draw N severities.
simulate_annual_losses <- function(freq_fit, severity_sampler, n_sims, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  counts <- sample_frequency(freq_fit, n_sims)
  lapply(counts, function(n) {
    if (n == 0) numeric(0) else severity_sampler(n)
  })
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-simulate.R')"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/simulate.R tests/testthat/test-simulate.R
git commit -m "Add Monte Carlo simulation engine"
```

---

### Task 8: Contract pricing and premium principles

**Files:**
- Create: `R/price.R`, `tests/testthat/test-price.R`

**Interfaces:**
- Consumes: simulated annual losses (list), a contract row, premium parameters (`loading_ev`, `loading_sd`, `var_level`).
- Produces:
  - `annual_layer_loss(year_losses, D, C, n_reinstatements, aad, aal)` returns the reinsured loss for one simulated year after per-loss layering, aggregate cover limit from reinstatements, AAD and AAL.
  - `price_layer(sims, layer_row, premium_params)` returns a one-row data.frame with `deductible`, `cover`, `expected_loss`, `sd_loss`, `var`, `tvar`, `rol`, `premium_ev`, `premium_sd`.
  - `price_program(sims, contract, premium_params)` binds `price_layer` over all layers.

- [ ] **Step 1: Write the failing test `tests/testthat/test-price.R`**

```r
test_that("annual_layer_loss applies reinstatement cover, AAD and AAL", {
  # Two losses of 8, layer 5 xs 5 -> each contributes min(8-5,5)=3, total 6.
  losses <- c(8, 8)
  # No reinstatements: aggregate cover capped at C = 5.
  expect_equal(annual_layer_loss(losses, D = 5, C = 5,
                                 n_reinstatements = 0, aad = 0, aal = 0), 5)
  # One reinstatement: cover capped at C*(1+1) = 10, so full 6 paid.
  expect_equal(annual_layer_loss(losses, D = 5, C = 5,
                                 n_reinstatements = 1, aad = 0, aal = 0), 6)
  # AAD of 2 removes the first 2 of aggregate: 6 - 2 = 4.
  expect_equal(annual_layer_loss(losses, D = 5, C = 5,
                                 n_reinstatements = 1, aad = 2, aal = 0), 4)
  # AAL of 3 caps the aggregate at 3.
  expect_equal(annual_layer_loss(losses, D = 5, C = 5,
                                 n_reinstatements = 1, aad = 0, aal = 3), 3)
})

test_that("price_layer expected loss converges to the closed-form oracle", {
  # Pure per-layer case (no reinstatement cap, no aggregate features).
  set.seed(11)
  freq <- list(type = "poisson", params = list(lambda = 1.4), expected = 1.4)
  sev <- list(u = 5, weight = 1, lnorm = NULL,
              pareto = list(x0 = 5, alpha = 1.184))
  sims <- simulate_annual_losses(freq, function(n) sample_tail(sev, n),
                                 n_sims = 200000, seed = 11)
  layer <- data.frame(deductible = 5, cover = 5,
                      n_reinstatements = 999, reinstatement_cost = 0,
                      aad = 0, aal = 0)
  pp <- list(loading_ev = 0.1, loading_sd = 0.2, var_level = 0.99)
  priced <- price_layer(sims, layer, pp)
  oracle <- expected_layer_loss(freq, sev, 5, 5)   # ~4.55
  expect_true(abs(priced$expected_loss - oracle) / oracle < 0.02)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-price.R')"`
Expected: FAIL with "could not find function annual_layer_loss".

- [ ] **Step 3: Write `R/price.R`**

```r
# Reinsured loss for one simulated year, in this order:
# per-loss layering -> aggregate cover limit from reinstatements -> AAD -> AAL.
annual_layer_loss <- function(year_losses, D, C, n_reinstatements, aad, aal) {
  per_loss <- apply_layer(year_losses, D, C)
  agg <- sum(per_loss)
  # Total cover available across the year: the layer plus its reinstatements.
  max_cover <- C * (1 + n_reinstatements)
  agg <- min(agg, max_cover)
  # Annual aggregate deductible removes the first aad of aggregate loss.
  agg <- max(agg - aad, 0)
  # Annual aggregate limit caps the aggregate (0 means unlimited).
  if (!is.na(aal) && aal > 0) agg <- min(agg, aal)
  agg
}

# Prices a single layer from the simulated years.
price_layer <- function(sims, layer_row, premium_params) {
  D <- layer_row$deductible; C <- layer_row$cover
  annual <- vapply(sims, function(yl) {
    annual_layer_loss(yl, D, C, layer_row$n_reinstatements,
                      layer_row$aad, layer_row$aal)
  }, numeric(1))

  expected_loss <- mean(annual)
  sd_loss <- stats::sd(annual)
  var_q <- stats::quantile(annual, premium_params$var_level, names = FALSE)
  tvar <- mean(annual[annual >= var_q])

  premium_ev <- (1 + premium_params$loading_ev) * expected_loss
  premium_sd <- expected_loss + premium_params$loading_sd * sd_loss

  data.frame(
    deductible = D, cover = C,
    expected_loss = expected_loss, sd_loss = sd_loss,
    var = var_q, tvar = tvar,
    rol = premium_ev / C,
    premium_ev = premium_ev, premium_sd = premium_sd
  )
}

# Prices every layer in the program.
price_program <- function(sims, contract, premium_params) {
  rows <- lapply(seq_len(nrow(contract)), function(i) {
    price_layer(sims, contract[i, ], premium_params)
  })
  do.call(rbind, rows)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-price.R')"`
Expected: PASS (the convergence test confirms the simulator is unbiased against the oracle).

- [ ] **Step 5: Commit**

```bash
git add R/price.R tests/testthat/test-price.R
git commit -m "Add contract pricing and premium principles"
```

---

### Task 9: Excel output writer

**Files:**
- Modify: `R/io.R` (add `write_output`)
- Create: `tests/testthat/test-io-write.R`

**Interfaces:**
- Consumes: a results data.frame (from `price_program`), an assumptions data.frame.
- Produces: `write_output(path, results, assumptions)` writes a workbook with sheets `results` and `assumptions`; returns `path` invisibly.

- [ ] **Step 1: Write the failing test `tests/testthat/test-io-write.R`**

```r
test_that("write_output produces a readable two-sheet workbook", {
  results <- data.frame(deductible = 5, cover = 5, expected_loss = 4.55,
                        premium_ev = 5.0)
  assumptions <- data.frame(key = "frequency_model", value = "poisson")
  path <- tempfile(fileext = ".xlsx")

  write_output(path, results, assumptions)

  back <- as.data.frame(readxl::read_excel(path, sheet = "results"))
  expect_equal(back$expected_loss, 4.55)
  sheets <- readxl::excel_sheets(path)
  expect_true(all(c("results", "assumptions") %in% sheets))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-io-write.R')"`
Expected: FAIL with "could not find function write_output".

- [ ] **Step 3: Add `write_output` to `R/io.R`**

```r
# Writes pricing results and the assumptions echo to a two-sheet workbook.
write_output <- function(path, results, assumptions) {
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "results")
  openxlsx::writeData(wb, "results", results)
  openxlsx::addWorksheet(wb, "assumptions")
  openxlsx::writeData(wb, "assumptions", assumptions)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  invisible(path)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-io-write.R')"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/io.R tests/testthat/test-io-write.R
git commit -m "Add Excel output writer"
```

---

### Task 10: End-to-end orchestration

**Files:**
- Create: `R/pipeline.R`, `make_example.R`, `tests/testthat/test-pipeline.R`

**Interfaces:**
- Consumes: an input workbook path; everything from earlier tasks.
- Produces:
  - `run_pricing(input_path, output_path = NULL, seed = NULL)` reads the workbook, indexes losses, fits frequency and severity, simulates, prices, attaches the closed-form `oracle` and `oracle_delta` columns, optionally writes the output workbook, and returns a list `list(results, fit_frequency, fit_severity, burning_cost, sims)`.
  - `make_example.R` writes `example_input.xlsx` reproducing the notes example (losses above 5 for 2021 to 2025, u = 5).

- [ ] **Step 1: Write `make_example.R`**

```r
# Writes example_input.xlsx reproducing the Reinsurance Analytics notes example.
wb <- openxlsx::createWorkbook()
openxlsx::addWorksheet(wb, "losses")
openxlsx::writeData(wb, "losses", data.frame(
  year = c(2021, 2021, 2023, 2024, 2024, 2024, 2025),
  loss = c(12, 9.5, 18, 13, 7, 11, 14),
  line_of_business = "fire"
))
openxlsx::addWorksheet(wb, "exposure")
openxlsx::writeData(wb, "exposure", data.frame(
  year = 2021:2026, exposure = c(120, 120, 130, 140, 145, 150)
))
openxlsx::addWorksheet(wb, "parameters")
openxlsx::writeData(wb, "parameters", data.frame(
  key = c("reporting_threshold", "loss_inflation_pa", "splice_threshold_u",
          "frequency_model", "n_simulations", "valuation_year",
          "loading_ev", "loading_sd", "var_level"),
  value = c("5", "0", "5", "poisson", "200000", "2025", "0.1", "0.2", "0.99")
))
openxlsx::addWorksheet(wb, "contract")
openxlsx::writeData(wb, "contract", data.frame(
  deductible = c(5, 10, 20), cover = c(5, 10, 10),
  n_reinstatements = c(999, 999, 999), reinstatement_cost = c(0, 0, 0),
  aad = c(0, 0, 0), aal = c(0, 0, 0)
))
openxlsx::saveWorkbook(wb, "example_input.xlsx", overwrite = TRUE)
cat("Wrote example_input.xlsx\n")
```

- [ ] **Step 2: Write the failing test `tests/testthat/test-pipeline.R`**

```r
test_that("run_pricing reproduces the notes Table 13 expected losses end to end", {
  # Build the notes example workbook in a temp file (inflation 0 to match Table 13).
  path <- tempfile(fileext = ".xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "losses")
  openxlsx::writeData(wb, "losses", data.frame(
    year = c(2021, 2021, 2023, 2024, 2024, 2024, 2025),
    loss = c(12, 9.5, 18, 13, 7, 11, 14), line_of_business = "fire"))
  openxlsx::addWorksheet(wb, "exposure")
  openxlsx::writeData(wb, "exposure", data.frame(
    year = 2021:2025, exposure = rep(100, 5)))
  openxlsx::addWorksheet(wb, "parameters")
  openxlsx::writeData(wb, "parameters", data.frame(
    key = c("reporting_threshold", "loss_inflation_pa", "splice_threshold_u",
            "frequency_model", "n_simulations", "valuation_year",
            "loading_ev", "loading_sd", "var_level"),
    value = c("5", "0", "5", "poisson", "200000", "2025", "0.1", "0.2", "0.99")))
  openxlsx::addWorksheet(wb, "contract")
  openxlsx::writeData(wb, "contract", data.frame(
    deductible = c(5, 10, 20), cover = c(5, 10, 10),
    n_reinstatements = 999, reinstatement_cost = 0, aad = 0, aal = 0))
  openxlsx::saveWorkbook(wb, path)

  res <- run_pricing(path, seed = 99)$results
  # Table 13 expected sums: 4.56, 4.01, 2.12 (within simulation tolerance).
  expect_true(abs(res$expected_loss[1] - 4.56) < 0.15)
  expect_true(abs(res$expected_loss[2] - 4.01) < 0.15)
  expect_true(abs(res$expected_loss[3] - 2.12) < 0.15)
  # Simulated mean should track the closed-form oracle closely.
  expect_true(all(abs(res$oracle_delta) / res$oracle < 0.03))
})
```

- [ ] **Step 3: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-pipeline.R')"`
Expected: FAIL with "could not find function run_pricing".

- [ ] **Step 4: Write `R/pipeline.R`**

```r
# End-to-end pricing: read, index, fit, simulate, price, validate, write.
run_pricing <- function(input_path, output_path = NULL, seed = NULL) {
  input <- read_input(input_path)
  params <- input$parameters

  # Pre-process: revalue losses to the valuation year.
  losses <- index_losses(input$losses, input$exposure, params)

  # Fit frequency at the modelling threshold over the exposure observation period.
  years <- sort(unique(input$exposure$year))
  counts <- annual_counts(
    data.frame(year = losses$year, loss = losses$loss_indexed),
    years, params$splice_threshold_u)
  freq <- fit_frequency(counts, params$frequency_model)

  # Fit the spliced severity on the indexed losses.
  sev <- fit_severity(losses$loss_indexed, params$splice_threshold_u)

  # Simulate: v1 layers attach above u, so the engine samples the Pareto tail.
  sims <- simulate_annual_losses(freq, function(n) sample_tail(sev, n),
                                 params$n_simulations, seed)

  # Price every layer.
  pp <- list(loading_ev = params$loading_ev,
             loading_sd = params$loading_sd,
             var_level = params$var_level)
  results <- price_program(sims, input$contract, pp)

  # Attach the closed-form oracle and the simulation delta.
  results$oracle <- vapply(seq_len(nrow(results)), function(i) {
    expected_layer_loss(freq, sev, results$deductible[i], results$cover[i])
  }, numeric(1))
  results$oracle_delta <- results$expected_loss - results$oracle

  bc <- burning_cost(losses, input$contract)

  if (!is.null(output_path)) {
    assumptions <- data.frame(
      key = c("frequency_model", "lambda", "pareto_alpha", "splice_u",
              "n_simulations", "valuation_year"),
      value = c(freq$type, round(freq$expected, 4),
                round(sev$pareto$alpha, 4), sev$u,
                params$n_simulations, params$valuation_year))
    write_output(output_path, results, assumptions)
  }

  list(results = results, fit_frequency = freq, fit_severity = sev,
       burning_cost = bc, sims = sims)
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-pipeline.R')"`
Expected: PASS.

- [ ] **Step 6: Generate the example workbook and run the full suite**

Run: `Rscript make_example.R && Rscript run_tests.R`
Expected: `example_input.xlsx` written; all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add R/pipeline.R make_example.R example_input.xlsx tests/testthat/test-pipeline.R
git commit -m "Add end to end pricing orchestration and example workbook"
```

---

### Task 11: Shiny dashboard

**Files:**
- Create: `app.R`, `tests/testthat/test-app.R`

**Interfaces:**
- Consumes: `run_pricing` and the fitted objects it returns.
- Produces: a Shiny app. The pricing logic stays in `R/pipeline.R`; `app.R` only handles upload, parameter overrides, plots, the results table, the validation comparison, and the download button. A small pure helper `build_results_table(priced)` (defined in `app.R`) formats the results data.frame for display and is unit-tested.

- [ ] **Step 1: Write the failing test `tests/testthat/test-app.R`**

```r
# app.R sources R/ and defines build_results_table; source it for the test.
source(normalizePath(file.path(getwd(), "..", "..", "app.R")), local = TRUE)

test_that("build_results_table rounds and renames for display", {
  priced <- data.frame(deductible = 5, cover = 5, expected_loss = 4.5512,
                       sd_loss = 6.1, var = 20, tvar = 25, rol = 1.0,
                       premium_ev = 5.006, premium_sd = 5.8,
                       oracle = 4.55, oracle_delta = 0.0012)
  tbl <- build_results_table(priced)
  expect_true("Expected loss" %in% names(tbl))
  expect_equal(tbl[["Expected loss"]][1], 4.55)   # rounded to 2 dp
})
```

Note: guard `app.R` so sourcing it does not launch the app (see Step 3).

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-app.R')"`
Expected: FAIL (cannot open app.R / function not found).

- [ ] **Step 3: Write `app.R`**

```r
# Shiny dashboard for the reinsurance pricing pipeline.
# All numerical work lives in R/; this file only wires the UI to run_pricing.

# Load every pipeline module.
for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)

# Formats the priced results for on-screen display (pure, unit-tested).
build_results_table <- function(priced) {
  data.frame(
    Deductible = priced$deductible,
    Cover = priced$cover,
    `Expected loss` = round(priced$expected_loss, 2),
    `Std dev` = round(priced$sd_loss, 2),
    VaR = round(priced$var, 2),
    TVaR = round(priced$tvar, 2),
    RoL = round(priced$rol, 4),
    `Premium (EV)` = round(priced$premium_ev, 2),
    `Premium (SD)` = round(priced$premium_sd, 2),
    `Closed form` = round(priced$oracle, 2),
    check.names = FALSE
  )
}

ui <- shiny::fluidPage(
  shiny::titlePanel("Paco's Pragmatic Pricing Pipeline"),
  shiny::sidebarLayout(
    shiny::sidebarPanel(
      shiny::fileInput("file", "Upload pricing workbook (.xlsx)",
                       accept = ".xlsx"),
      shiny::numericInput("seed", "Random seed", value = 1),
      shiny::actionButton("run", "Run pricing"),
      shiny::downloadButton("download", "Download results")
    ),
    shiny::mainPanel(
      shiny::tabsetPanel(
        shiny::tabPanel("Pricing", shiny::tableOutput("results")),
        shiny::tabPanel("Severity fit", shiny::plotOutput("sev_plot")),
        shiny::tabPanel("Validation", shiny::tableOutput("validation"))
      )
    )
  )
)

server <- function(input, output, session) {
  priced <- shiny::eventReactive(input$run, {
    shiny::req(input$file)
    run_pricing(input$file$datapath, seed = input$seed)
  })

  output$results <- shiny::renderTable({
    build_results_table(priced()$results)
  })

  output$validation <- shiny::renderTable({
    r <- priced()$results
    data.frame(Deductible = r$deductible, Cover = r$cover,
               Simulated = round(r$expected_loss, 3),
               `Closed form` = round(r$oracle, 3),
               Delta = round(r$oracle_delta, 4), check.names = FALSE)
  })

  output$sev_plot <- shiny::renderPlot({
    fit <- priced()$fit_severity
    xs <- seq(fit$u, fit$u * 8, length.out = 200)
    plot(xs, severity_cdf(fit, xs), type = "l",
         xlab = "Loss", ylab = "CDF", main = "Fitted spliced severity")
  })

  output$download <- shiny::downloadHandler(
    filename = function() "pricing_results.xlsx",
    content = function(file) {
      r <- priced()$results
      write_output(file, r, data.frame(key = "generated_by",
                                       value = "PPPP dashboard"))
    }
  )
}

# Only launch when run as an app, not when sourced by tests.
if (identical(environment(), globalenv()) && interactive()) {
  shiny::shinyApp(ui, server)
} else if (!exists(".testing_app")) {
  app <- shiny::shinyApp(ui, server)
}
```

Note: for the test to source `app.R` without launching, set `.testing_app <- TRUE` before sourcing. Update the test Step 1 to define `.testing_app <- TRUE` before the `source(...)` line.

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-app.R')"`
Expected: PASS.

- [ ] **Step 5: Manual smoke test of the UI**

Run: `Rscript -e "shiny::runApp('.', launch.browser = TRUE)"`
Expected: app opens; upload `example_input.xlsx`, click Run pricing, see the three layers priced, the severity CDF plot, and the validation table with small deltas; Download produces a workbook.

- [ ] **Step 6: Commit**

```bash
git add app.R tests/testthat/test-app.R
git commit -m "Add Shiny dashboard"
```

---

### Task 12: README and final documentation

**Files:**
- Create: `README.md`

**Interfaces:**
- Produces: user-facing run instructions and an input-format description.

- [ ] **Step 1: Write `README.md`**

```markdown
# Paco's Pragmatic Pricing Pipeline

An R and Shiny tool that prices non-proportional reinsurance from a historical
loss list. Excel in, Excel plus dashboard out.

## Quick start
1. Install R (4.x).
2. Install dependencies: `Rscript install_deps.R`
3. Generate the example workbook: `Rscript make_example.R`
4. Launch the dashboard: `Rscript -e "shiny::runApp('.', launch.browser = TRUE)"`
5. Upload `example_input.xlsx`, click Run pricing.

## Pricing without the UI
```r
source("R/pipeline.R")  # plus the other R/ files, or source app.R
result <- run_pricing("example_input.xlsx", output_path = "out.xlsx", seed = 1)
result$results
```

## Input workbook
Four sheets: `losses` (year, loss, line_of_business), `exposure` (year,
exposure), `parameters` (key, value), `contract` (deductible, cover,
n_reinstatements, reinstatement_cost, aad, aal). See `make_example.R`.

## Method
Spliced lognormal plus Pareto severity, Poisson frequency by default, Monte
Carlo aggregate loss, closed-form expected loss as a validation check. Follows
the experience-pricing recipe in the FS 2026 Reinsurance Analytics notes
(Section 2.8). See docs/superpowers/specs for the full design.

## Tests
`Rscript run_tests.R`
```

- [ ] **Step 2: Run the full suite one last time**

Run: `Rscript run_tests.R`
Expected: all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Add README and run instructions"
```

---

## Self-Review

**Spec coverage:**
- Excel input (§4) -> Task 2. Excel output (§10) -> Task 9.
- Pre-processing: indexation + exposure + burning cost (§5) -> Task 3.
- Spliced severity, continuity (§6) -> Task 5.
- Frequency Poisson/NegBin/Binomial, default Poisson (§7) -> Task 4.
- Monte Carlo engine (§8) -> Task 7.
- Closed-form validation oracle (§8) -> Task 6, wired in Task 10.
- Premium principles, RoL, VaR/TVaR (§9) -> Task 8.
- Dashboard (§10) -> Task 11.
- Module structure (§11) -> file structure section; one task per module.
- Validation/testing (§12) -> tests in every task; Table 13 reproduced in Task 10.
- Dependencies (§13) -> Task 1 install_deps.R.
- v2 hooks (§14): `sample_severity` and `lnorm_limited_ev` built and tested but unused in v1 wiring, so proportional/low-layer work is a wiring change.

**Refinement noted:** the lognormal body does not affect v1 layer prices because every layer attaches at or above `u`; v1 simulates the Pareto tail and reproduces the notes exactly. The body is still fitted, displayed, and tested for v2. This is consistent across the spec constraint, Task 5, Task 7, Task 10, and the validation oracle in Task 6.

**Placeholder scan:** no TBD/TODO; every code step shows complete code; every test step shows real assertions with numeric expected values drawn from the notes.

**Type consistency:** `fit_severity` returns `list(u, weight, lnorm, pareto=list(x0, alpha))`, consumed identically in `sample_tail`, `severity_cdf`, `expected_layer_loss`, and `run_pricing`. Frequency fit returns `list(type, params, expected)`, consumed identically in `sample_frequency`, `simulate_annual_losses`, and `expected_layer_loss`. `apply_layer(x, D, C)` used identically in `burning_cost` and `annual_layer_loss`. `run_pricing` returns `list(results, fit_frequency, fit_severity, burning_cost, sims)`, consumed by `app.R`.
