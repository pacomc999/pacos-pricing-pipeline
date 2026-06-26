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

# Counts connected browser sessions so the app can shut itself down when the
# last tab closes. An environment is used because it is mutable by reference and
# shared across all sessions. A short grace period (see server) tolerates a page
# refresh, which briefly drops to zero sessions before reconnecting.
.app_sessions <- new.env(parent = emptyenv())
.app_sessions$count <- 0L

ui <- shiny::fluidPage(
  shiny::titlePanel("Paco's Pragmatic Pricing Pipeline"),
  shiny::sidebarLayout(
    shiny::sidebarPanel(
      shiny::fileInput("file", "Upload pricing workbook (.xlsx)",
                       accept = ".xlsx"),
      shiny::numericInput("seed", "Random seed", value = 1),
      shiny::actionButton("run", "Run pricing"),
      shiny::downloadButton("download", "Download results"),
      shiny::tags$hr(),
      shiny::actionButton("quit", "Shut down", class = "btn-danger"),
      shiny::helpText("Shut down (or just close this browser tab) to stop the tool.")
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
  # Self-shutdown lifecycle: count this session, and when a session ends, stop
  # the app after a grace period if no sessions remain (so refresh is safe).
  .app_sessions$count <- .app_sessions$count + 1L
  session$onSessionEnded(function() {
    .app_sessions$count <- .app_sessions$count - 1L
    later::later(function() {
      if (.app_sessions$count <= 0L) shiny::stopApp()
    }, delay = 5)
  })

  # Explicit shut-down button.
  shiny::observeEvent(input$quit, {
    shiny::stopApp()
  })

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
