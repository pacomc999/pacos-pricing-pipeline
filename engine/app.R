# Shiny dashboard for the reinsurance pricing pipeline.
# All numerical work lives in R/; this file wires the UI to the pipeline.
# The Excel workbook holds the data; the modelling choices (thresholds,
# frequency model, simulations, loadings) are set here and previewed live.
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
# last tab closes. An environment is mutable by reference and shared across
# sessions; a short grace period (see server) tolerates a page refresh.
.app_sessions <- new.env(parent = emptyenv())
.app_sessions$count <- 0L

# Process-level store for the most recently uploaded data. It outlives an
# individual browser session, so a page refresh (which starts a new session)
# reloads the same data instead of clearing it. It is empty again when the tool
# is closed and relaunched (a new R process).
.app_state <- new.env(parent = emptyenv())
.app_state$data <- NULL
.app_state$name <- NULL

ui <- shiny::fluidPage(
  shiny::titlePanel("Paco's Pricing Pipeline"),
  shiny::sidebarLayout(
    shiny::sidebarPanel(
      shiny::fileInput("file", "Upload pricing workbook (.xlsx)", accept = ".xlsx"),
      shiny::helpText("Your upload stays loaded across page refreshes. Adjust the thresholds and watch the Fit tab update."),
      shiny::numericInput("mt", "Modelling threshold (MT)", value = NA),
      shiny::numericInput("s", "Splice threshold (lognormal to Pareto)", value = NA),
      shiny::selectInput("freq", "Frequency model",
                         choices = c("Poisson" = "poisson",
                                     "Negative Binomial" = "negbin",
                                     "Binomial" = "binomial"),
                         selected = "poisson"),
      shiny::numericInput("nsim", "Simulations", value = 100000, min = 1000, step = 1000),
      shiny::numericInput("load_ev", "Loading (expected value)", value = 0.1, step = 0.05),
      shiny::numericInput("load_sd", "Loading (std dev)", value = 0.2, step = 0.05),
      shiny::numericInput("var_level", "VaR / TVaR level", value = 0.99, min = 0.5, max = 0.999, step = 0.005),
      shiny::numericInput("seed", "Random seed", value = 1),
      shiny::actionButton("run", "Run pricing", class = "btn-primary"),
      shiny::downloadButton("download", "Download results"),
      shiny::tags$hr(),
      shiny::actionButton("quit", "Shut down", class = "btn-danger"),
      shiny::helpText("Shut down (or just close this browser tab) to stop the tool.")
    ),
    shiny::mainPanel(
      shiny::tabsetPanel(
        shiny::tabPanel("Fit",
          shiny::helpText("These update live as you change MT and the splice. Red line = MT, blue dashed = splice."),
          shiny::plotOutput("me_plot"),
          shiny::plotOutput("sev_plot"),
          shiny::tableOutput("fit_params")),
        shiny::tabPanel("Pricing", shiny::tableOutput("results")),
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
  shiny::observeEvent(input$quit, shiny::stopApp())

  # Initialise this session's data from the process-level store, so a refresh
  # comes back to the last upload.
  rv <- shiny::reactiveValues(data = .app_state$data, name = .app_state$name)

  # On upload, read the workbook and remember it for this session and the process.
  shiny::observeEvent(input$file, {
    rv$data <- read_input(input$file$datapath)
    rv$name <- input$file$name
    .app_state$data <- rv$data
    .app_state$name <- rv$name
  })

  input_data <- shiny::reactive({
    shiny::validate(shiny::need(!is.null(rv$data),
      "Upload a pricing workbook (.xlsx) to begin."))
    rv$data
  })

  # When a workbook is loaded, seed the controls from its defaults (or built-in
  # defaults) so the user starts from a sensible point.
  shiny::observeEvent(input_data(), {
    st <- resolve_settings(input_data()$parameters)
    shiny::updateNumericInput(session, "mt", value = st$modelling_threshold)
    shiny::updateNumericInput(session, "s", value = st$splice_threshold)
    shiny::updateSelectInput(session, "freq", selected = st$frequency_model)
    shiny::updateNumericInput(session, "nsim", value = st$n_simulations)
    shiny::updateNumericInput(session, "load_ev", value = st$loading_ev)
    shiny::updateNumericInput(session, "load_sd", value = st$loading_sd)
    shiny::updateNumericInput(session, "var_level", value = st$var_level)
  })

  # Current modelling settings from the controls.
  settings <- shiny::reactive({
    list(modelling_threshold = input$mt, splice_threshold = input$s,
         frequency_model = input$freq, n_simulations = input$nsim,
         loading_ev = input$load_ev, loading_sd = input$load_sd,
         var_level = input$var_level)
  })

  # Fast fit (no simulation): drives the Fit tab and updates as thresholds change.
  fits <- shiny::reactive({
    inp <- input_data()
    shiny::validate(
      shiny::need(!is.na(input$mt), "Set the modelling threshold."),
      shiny::need(!is.na(input$s), "Set the splice threshold."),
      shiny::need(input$s >= input$mt, "Splice threshold must be at least the modelling threshold.")
    )
    tryCatch(fit_models(inp, settings()),
             error = function(e) shiny::validate(shiny::need(FALSE, conditionMessage(e))))
  })

  output$me_plot <- shiny::renderPlot({
    x <- fits()$losses$loss_indexed
    hi <- as.numeric(stats::quantile(x, 0.95))
    us <- seq(min(x), max(hi, input$mt * 1.01), length.out = 50)
    me <- mean_excess(x, us)
    plot(me$threshold, me$mean_excess, type = "l",
         xlab = "Threshold u", ylab = "Mean excess e(u)",
         main = "Mean excess plot (roughly linear where a Pareto tail fits)")
    abline(v = input$mt, col = "red")
    abline(v = input$s, col = "blue", lty = 2)
  })

  output$sev_plot <- shiny::renderPlot({
    f <- fits()
    fit <- f$fit_severity
    above <- f$losses$loss_indexed[f$losses$loss_indexed > fit$mt]
    xs <- seq(fit$mt, max(above), length.out = 200)
    plot(xs, 1 - severity_survival(fit, xs), type = "l",
         xlab = "Loss", ylab = "CDF (conditional on X > MT)",
         main = "Fitted vs empirical severity")
    lines(sort(above), stats::ecdf(above)(sort(above)), type = "s", col = "grey50")
    abline(v = fit$s, col = "blue", lty = 2)
    legend("bottomright", c("Fitted", "Empirical"),
           col = c("black", "grey50"), lty = 1, bty = "n")
  })

  output$fit_params <- shiny::renderTable({
    f <- fits()
    sev <- f$fit_severity
    mu <- if (is.null(sev$lnorm)) NA else round(sev$lnorm$meanlog, 3)
    sg <- if (is.null(sev$lnorm)) NA else round(sev$lnorm$sdlog, 3)
    data.frame(
      Quantity = c("Frequency lambda", "Pareto alpha", "Lognormal mu",
                   "Lognormal sigma", "Tail weight P(X>s | X>MT)"),
      Value = c(round(f$fit_frequency$expected, 3), round(sev$pareto$alpha, 3),
                mu, sg, round(sev$weight, 3)),
      check.names = FALSE
    )
  })

  # Pricing runs only on demand (the expensive Monte Carlo step).
  priced <- shiny::eventReactive(input$run, {
    inp <- input_data()
    st <- settings()
    f <- fit_models(inp, st)
    price_models(f, inp$contract, st, input$seed)
  })

  output$results <- shiny::renderTable(build_results_table(priced()$results))

  output$validation <- shiny::renderTable({
    r <- priced()$results
    data.frame(Deductible = r$deductible, Cover = r$cover,
               Simulated = round(r$expected_loss, 3),
               `Closed form` = round(r$oracle, 3),
               Delta = round(r$oracle_delta, 4), check.names = FALSE)
  })

  output$download <- shiny::downloadHandler(
    filename = function() "output.xlsx",
    content = function(file) {
      st <- settings()
      r <- priced()$results
      assumptions <- data.frame(
        key = c("modelling_threshold", "splice_threshold", "frequency_model",
                "n_simulations", "loading_ev", "loading_sd", "var_level"),
        value = c(st$modelling_threshold, st$splice_threshold, st$frequency_model,
                  st$n_simulations, st$loading_ev, st$loading_sd, st$var_level))
      write_output(file, r, assumptions)
    }
  )
}

# Returning the app object is the standard app.R contract: shiny::runApp('.')
# launches it, while sourcing this file (in tests) only builds it.
shiny::shinyApp(ui, server)
