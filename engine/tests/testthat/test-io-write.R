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

test_that("write_output echoes the priced contract as its own sheet", {
  # Without the layer terms (AAD and AAL included) in the file, a result
  # cannot be reconstructed later from the download alone.
  results <- data.frame(deductible = 5, cover = 5, expected_loss = 4.55)
  assumptions <- data.frame(key = "frequency_model", value = "poisson")
  contract <- data.frame(deductible = c(5, 10), cover = c(5, 10),
                         aad = c(NA, 2), aal = c(NA, 8))
  path <- tempfile(fileext = ".xlsx")

  write_output(path, results, assumptions, contract = contract)

  back <- as.data.frame(readxl::read_excel(path, sheet = "contract"))
  expect_equal(back$deductible, c(5, 10))
  expect_equal(back$aal[2], 8)
})
