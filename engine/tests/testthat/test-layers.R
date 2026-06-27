test_that("default_contract returns the three-layer demo program", {
  dc <- default_contract()
  expect_equal(nrow(dc), 3)
  expect_setequal(names(dc), c("deductible", "cover", "aad", "aal"))
  # Reinstatements are not modelled; the column should not be present.
  expect_false("n_reinstatements" %in% names(dc))
  expect_equal(dc$cover, c(5, 10, 20))
})
