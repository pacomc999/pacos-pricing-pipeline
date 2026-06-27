# Dashboard Stepper Flow — Design Spec

Date: 2026-06-26
Status: Approved, ready to implement.

## Problem
The dashboard puts every control in one always-visible sidebar, mixing three
different kinds of decision (data, modelling, pricing) at equal prominence. It
reads as "adjust everything all the time" and separates each control from its
own feedback (thresholds in the sidebar, fit plots in a tab).

## Goal
Replace the single sidebar + output tabs with a guided, four-step flow that
pairs each control with the feedback for that decision, while still letting an
expert jump around to iterate.

## Approach
A **clickable stepper** built from the existing `tabsetPanel` (its tabs are
already clickable, giving non-blocking navigation for free), plus Back / Next
buttons that call `updateTabsetPanel()`. Light CSS turns the four tab labels
into a numbered progress strip. No new package.

## The four steps
1. **Data** — upload the workbook; show a preview of what loaded: filename, loss
   count and year range, the first rows of the loss list, and the read-only data
   parameters (`reporting_threshold`, `loss_inflation_pa`, `valuation_year`).
2. **Model** — modelling threshold, splice, frequency model on the left; the live
   mean-excess plot, severity plot, and fitted-parameter table on the right.
3. **Structure** — the add/remove layer editor (unchanged).
4. **Price** — loadings (EV, SD), VaR level, simulations, seed, the Run pricing
   button and Download on the left; the results table and the
   simulation-vs-closed-form validation on the right.

The **Shut down** button moves to a slim always-visible top bar.

## What changes
- `app.R` UI only: the `sidebarLayout` becomes a top bar + a stepped
  `tabsetPanel(id = "step")` with the four panels above; a `tags$style` block adds
  the progress-strip styling.
- `app.R` server: add Back/Next observers that switch the active step, and a data
  preview output for Step 1. Existing reactives (`fits`, `contract`, `priced`,
  plots, settings, the workbook-seeding observer) are unchanged — the inputs keep
  the same ids, they just live in different panels.

## Non-goals
- No change to pricing/fitting math (`R/` is untouched).
- No gating: every step is reachable at any time.

## Testing
- Existing suite stays green (the pure helpers and pipeline are unaffected).
- `testServer` check: Next/Back observers move `input$step` between
  `data → model → structure → price` and back.
- Manual: launch and click through the four steps.
