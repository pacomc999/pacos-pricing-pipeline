# Shiny dashboard for the reinsurance pricing pipeline.
# All numerical work lives in R/; this file only wires the UI to run_pricing.
# Run with: Rscript -e "shiny::runApp('.', launch.browser = TRUE)"

# Load every pipeline module (no-op when sourced from a different directory,
# e.g. tests, where the modules are already loaded by the test helper).
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
    xs <- seq(fit$mt, fit$s * 6, length.out = 200)
    # Plot the fitted conditional CDF (1 - survival); the splice point is marked.
    plot(xs, 1 - severity_survival(fit, xs), type = "l",
         xlab = "Loss", ylab = "CDF (conditional on X > MT)",
         main = "Fitted spliced severity")
    abline(v = fit$s, lty = 2)
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

# Returning the app object is the standard app.R contract: shiny::runApp('.')
# launches it, while sourcing this file (in tests) only builds it.
shiny::shinyApp(ui, server)
