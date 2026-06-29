test_that("build_template_workbook writes a workbook read_input accepts", {
  path <- tempfile(fileext = ".xlsx")
  openxlsx::saveWorkbook(build_template_workbook(), path, overwrite = TRUE)

  # The four data sheets the pipeline expects must all be present.
  expect_true(all(c("losses", "exposure", "inflation", "general inputs") %in%
                    readxl::excel_sheets(path)))

  # read_input parses it without error and recovers the required parameters.
  inp <- read_input(path)
  expect_true(nrow(inp$losses) > 0)
  expect_equal(inp$parameters$valuation_year, 2026L)
  expect_equal(inp$parameters$reporting_threshold, 2)
})
