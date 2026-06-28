# Writes the top-level input.xlsx template: a richer dataset that populates both
# the lognormal body (losses 5 to 15) and the Pareto tail (losses above 15), so
# the demo exercises the full spliced severity. The contract structure is set in
# the dashboard (not the workbook), so this template has four data sheets:
# losses, exposure, a per-year inflation sheet, and general inputs. This file lives
# in engine/, so the workbook is written one level up.
#
# The sheets are styled (navy headers matching the dashboard, borders, a frozen
# header row, inflation as a percentage) so the template reads cleanly in Excel.
# Styling only affects display; read_input reads the underlying values.

# ---- Data -------------------------------------------------------------------
losses <- data.frame(
  year = c(2021, 2021, 2021, 2022, 2022, 2023, 2023, 2023,
           2024, 2024, 2024, 2024, 2024, 2025, 2025, 2025, 2025),
  loss = c(6, 8, 22, 7, 35, 9, 11, 18,
           6, 7, 13, 28, 45, 8, 10, 16, 60),
  line_of_business = "fire"
)
exposure <- data.frame(year = 2021:2026, exposure = c(120, 120, 130, 140, 145, 150))
# Loss inflation is a per-year rate, not a single constant. One row per year; the
# rate is the inflation experienced during that year and accrues on losses from
# earlier years when they are revalued to the valuation year.
inflation <- data.frame(year = 2021:2026, inflation = c(0.02, 0.03, 0.025, 0.04, 0.03, 0.035))
# Only the general inputs live in the workbook; the modelling choices (thresholds,
# frequency model, simulations, loadings) are set in the dashboard. The valuation
# year is required; currency and amount units are optional and only label figures.
# The notes column documents this in the sheet; read_input ignores extra columns.
parameters <- data.frame(
  key   = c("valuation_year", "currency", "amount_units"),
  value = c("2026", "EUR", "millions"),
  notes = c("Required: the year losses are revalued to.",
            "Optional: shown next to amounts.",
            "Optional: shown next to amounts (e.g. millions, thousands)."))

# ---- Styles (navy header to match the dashboard banner) ---------------------
header  <- openxlsx::createStyle(fontColour = "#FFFFFF", fgFill = "#1B2A4A",
             textDecoration = "bold", halign = "center", valign = "center",
             border = "TopBottomLeftRight", borderColour = "#1B2A4A")
yr_st   <- openxlsx::createStyle(numFmt = "0", halign = "center",
             border = "TopBottomLeftRight", borderColour = "#DDE3EC")
num_st  <- openxlsx::createStyle(numFmt = "#,##0",
             border = "TopBottomLeftRight", borderColour = "#DDE3EC")
pct_st  <- openxlsx::createStyle(numFmt = "0.0%",
             border = "TopBottomLeftRight", borderColour = "#DDE3EC")
cell_st <- openxlsx::createStyle(border = "TopBottomLeftRight", borderColour = "#DDE3EC")

wb <- openxlsx::createWorkbook()

# Adds a sheet with the navy header and a frozen header row.
add_sheet <- function(name, df, widths) {
  openxlsx::addWorksheet(wb, name)
  openxlsx::writeData(wb, name, df, headerStyle = header)
  openxlsx::setColWidths(wb, name, cols = seq_along(widths), widths = widths)
  openxlsx::freezePane(wb, name, firstActiveRow = 2)
}
# Applies a style to a data column (rows below the header).
col_style <- function(name, n, col, style) {
  openxlsx::addStyle(wb, name, style, rows = 2:(n + 1), cols = col, gridExpand = TRUE)
}

add_sheet("losses", losses, c(10, 14, 20))
col_style("losses", nrow(losses), 1, yr_st)
col_style("losses", nrow(losses), 2, num_st)
col_style("losses", nrow(losses), 3, cell_st)

add_sheet("exposure", exposure, c(10, 14))
col_style("exposure", nrow(exposure), 1, yr_st)
col_style("exposure", nrow(exposure), 2, num_st)

add_sheet("inflation", inflation, c(10, 14))
col_style("inflation", nrow(inflation), 1, yr_st)
col_style("inflation", nrow(inflation), 2, pct_st)

add_sheet("general inputs", parameters, c(18, 12, 52))
col_style("general inputs", nrow(parameters), 1, cell_st)
col_style("general inputs", nrow(parameters), 2, cell_st)
col_style("general inputs", nrow(parameters), 3, cell_st)

openxlsx::saveWorkbook(wb, "../input.xlsx", overwrite = TRUE)
cat("Wrote input.xlsx\n")
