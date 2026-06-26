test_that("default_contract returns the three-layer demo program", {
  dc <- default_contract()
  expect_equal(nrow(dc), 3)
  expect_setequal(names(dc),
                  c("deductible", "cover", "n_reinstatements", "aad", "aal"))
  # reinstatement_cost was unused by pricing and is no longer carried.
  expect_false("reinstatement_cost" %in% names(dc))
  expect_equal(dc$cover, c(5, 10, 20))
})
