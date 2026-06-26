# CLAUDE.md

Project-specific guidance for Paco's Pragmatic Pricing Pipeline. This overrides
the workspace CLAUDE.md (which is for the browser game and visualizer projects).

## What this is
An R + Shiny tool that prices non-proportional reinsurance from a historical
loss list. Excel in, Excel plus dashboard out. Methodology follows the
experience-pricing recipe in Literature/Reinsurance_Analytics_2026_vFeb.pdf
(Section 2.8), generalised to a spliced lognormal plus Pareto severity.

## Running
For end users: double-click `start.vbs` in the parent folder (hidden launch) or
`engine\start.bat` (visible, for troubleshooting). All commands below run from
inside this `engine/` folder:
- Install dependencies once: `Rscript install_deps.R`
- Run the test suite: `Rscript run_tests.R`
- Launch the dashboard: `Rscript -e "shiny::runApp('.')"` (or open app.R in RStudio and click Run App)
- Price a workbook without the UI: source R/pipeline.R and call run_pricing()
- Regenerate the top-level input.xlsx template: `Rscript make_example.R`

## Layout
- This project lives in `engine/`; the parent folder holds only `start.vbs`,
  `input.xlsx`, and `README.md` so end users see a clean folder.
- R/ holds one module per responsibility (see the design spec).
- tests/testthat/ holds one test file per module; helper-setup.R sources R/.
- docs/superpowers/ holds the design spec and the implementation plan.
- make_example.R writes the template one level up (../input.xlsx).

## Conventions
- R + Shiny only. No TypeScript.
- Never use dashes (em dash, en dash) in visible text or copy.
- Modules use package::function calls; no library() inside R/ files.
- Clear variable names, a comment per section, short focused functions.
- Commit messages in present tense.

## Developer
Francisco Martinez Checa (GitHub: pacomc999). Learning as I go; explain changes.
