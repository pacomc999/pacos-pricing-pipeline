# CLAUDE.md

Project-specific guidance for Paco's Pricing Pipeline. This overrides
the workspace CLAUDE.md (which is for the browser game and visualizer projects).

## What this is
An R + Shiny tool that prices non-proportional reinsurance from a historical
loss list. Excel in, Excel plus dashboard out. Methodology follows the
experience-pricing recipe in ../Literature/Reinsurance_Analytics_2026_vFeb.pdf
(Section 2.8), generalised to a spliced lognormal plus Pareto severity. That
folder is kept locally and is not committed (third-party material).

## Running
For end users: double-click `start.vbs` in the parent folder (no console window) or
`engine\start.bat` (visible console, for troubleshooting). If those are blocked by the
machine, `Start in RStudio.R` in the parent folder is the fallback: open it in RStudio
and click Source. All commands below run from inside this `engine/` folder:
- Install dependencies once: `Rscript install_deps.R`
- Run the test suite: `Rscript run_tests.R`
- Launch the dashboard: `Rscript -e "shiny::runApp('.')"` (or open app.R in RStudio and click Run App)
- Price a workbook without the UI: `source("app.R")` (loads every R/ module), then call `run_pricing("../input.xlsx", overrides = list(...))`
- Regenerate the top-level input.xlsx template: `Rscript make_example.R`

## Layout
- This project lives in `engine/`; the parent folder holds only `start.vbs`,
  `Start in RStudio.R`, `input.xlsx`, `README.md`, and
  `Technical documentation.docx` so end users see a clean folder.
- R/ holds one module per responsibility (see docs/documentation.md).
- tests/testthat/ holds one test file per module; helper-setup.R sources R/.
- docs/documentation.md is the technical documentation; the Word copy at the repo root is generated from it by docs/build_docx.R (run that after editing, never hand-edit the .docx).
- make_example.R writes the template one level up (../input.xlsx).

## Releasing a new version
End users get the tool as a zip attached to a GitHub Release, not a zip
committed into the repo. To cut a release:
1. `.\engine\build_release.ps1 -Version x.y.z` builds a trimmed, end-user-only
   zip at `dist/pacos-pricing-pipeline-vx.y.z.zip` (dev-only files like
   tests/, this CLAUDE.md, and the docs source are left out on purpose; it
   prints the exact `gh release create` command to run next).
2. Run the `gh release create` command it prints. This is a deliberate,
   user-run step, never automated, since publishing a release is
   visible to others and not easily undone.

## Conventions
- R + Shiny only. No TypeScript.
- Never use dashes (em dash, en dash) in visible text or copy.
- Modules use package::function calls; no library() inside R/ files.
- Clear variable names, a comment per section, short focused functions.
- Commit messages in present tense.

## Developer
Francisco Martinez Checa (GitHub: pacomc999). Learning as I go; explain changes.
