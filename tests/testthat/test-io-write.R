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
