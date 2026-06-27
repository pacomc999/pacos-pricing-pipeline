# Shiny dashboard for the reinsurance pricing pipeline.
# All numerical work lives in R/; this file wires the UI to the pipeline.
# The UI is a four-step flow (Data -> Model -> Structure -> Price): each step
# pairs its controls with its own feedback. The steps are clickable, so an
# expert can jump back to iterate; Back/Next buttons walk the linear path.
# The Excel workbook holds the data; the modelling choices and the contract
# structure are set in the dashboard.
# Run with: Rscript -e "shiny::runApp('.', launch.browser = TRUE)"

# Load every pipeline module (no-op when sourced from a different directory,
# e.g. tests, where the modules are already loaded by the test helper).
for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)

# A numericInput that shows greyed placeholder text when empty (e.g. "none",
# "unlimited"). Used for AAD/AAL so a blank field reads clearly instead of
# defaulting to a misleading 0.
numeric_input_ph <- function(id, value, placeholder) {
  ni <- shiny::numericInput(id, NULL, value = value)
  htmltools::tagQuery(ni)$find("input")$addAttrs(placeholder = placeholder)$allTags()
}

# Assembles the contract data frame the pricer expects from the edited layer
# rows, keeping only the pricing columns in the right order (pure, unit-tested).
build_contract_df <- function(layer_rows) {
  data.frame(
    deductible = as.numeric(layer_rows$deductible),
    cover      = as.numeric(layer_rows$cover),
    aad        = as.numeric(layer_rows$aad),
    aal        = as.numeric(layer_rows$aal)
  )
}

# Checks the edited contract before pricing. Returns NULL when it is fine to
# price, otherwise a plain message to show the user (pure, unit-tested).
validate_contract <- function(contract) {
  if (nrow(contract) == 0) return("Add at least one layer to price.")
  if (any(is.na(contract$cover)) || any(contract$cover <= 0)) {
    return("Every layer needs a cover greater than 0.")
  }
  if (any(contract$deductible < 0, na.rm = TRUE)) {
    return("Deductible cannot be negative.")
  }
  if (any(contract$aad < 0, na.rm = TRUE) || any(contract$aal < 0, na.rm = TRUE)) {
    return("AAD and AAL cannot be negative.")
  }
  NULL
}

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

# Navy and blue theme. A deep navy banner, a blue accent for primary actions and
# the active step, and cool neutral surfaces. Red (--error) is reserved for
# destructive buttons (Shut down, Remove) and error messages, so the accent
# never competes with the 'something is wrong' signal. Restyles the default
# Bootstrap look and turns the step tabs into a numbered progress strip.
app_css <- shiny::tags$style(shiny::HTML("
  :root {
    --navy-deep: #16233f; --navy-mid: #26395f;
    --accent: #2f6fd0; --accent-dark: #2357a8;
    --error: #d93a3a; --error-dark: #b02828;
    --text-main: #1f2733; --text-muted: #69707c;
    --bg-main: #f5f7fa; --bg-card: #ffffff; --border: #dde3ec;
  }
  body { background: var(--bg-main); color: var(--text-main);
         font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
  .container-fluid { max-width: 1180px; }
  h4 { color: var(--navy-mid); font-weight: 600; }
  .help-block { color: var(--text-muted); }

  /* Top banner */
  #topbar { background: linear-gradient(90deg, var(--navy-deep), var(--navy-mid));
            border-radius: 8px; padding: 14px 24px; margin: 10px 0 18px;
            display: flex; align-items: center; justify-content: space-between; }
  .topbar-title { color: #fff; font-size: 24px; font-weight: 700; letter-spacing: 2px; }
  .topbar-actions { text-align: right; }
  .topbar-note { color: #aeb9cc; font-size: 11px; margin-top: 4px; }

  /* Step tabs as a numbered progress strip */
  #step.nav-tabs { display: flex; counter-reset: step; margin-bottom: 0; border-bottom: none; }
  #step.nav-tabs > li { flex: 1; text-align: center; float: none; margin-right: 3px; }
  #step.nav-tabs > li:last-child { margin-right: 0; }
  #step.nav-tabs > li > a {
    border: none; border-radius: 8px 8px 0 0; color: var(--text-muted);
    font-weight: 600; background: #e9edf3; margin: 0;
  }
  #step.nav-tabs > li > a:hover { background: #dde3ec; color: var(--text-main); }
  #step.nav-tabs > li > a::before {
    counter-increment: step; content: counter(step) '  '; color: #9aa6b8;
  }
  #step.nav-tabs > li.active > a,
  #step.nav-tabs > li.active > a:hover,
  #step.nav-tabs > li.active > a:focus {
    color: #fff; background: var(--accent); border: none;
  }
  #step.nav-tabs > li.active > a::before { color: #fff; }

  /* Active step content sits in a white card under the tabs */
  .tab-content { background: var(--bg-card); border: 1px solid var(--border);
                 border-radius: 0 0 8px 8px; padding: 26px 30px; margin-bottom: 24px; }

  /* Buttons. Shiny appends the custom class to the default btn-default, so use
     two-class selectors to win over .btn-default regardless of source order.
     Primary actions are blue; danger buttons stay red so red only ever means
     'destructive or wrong'. */
  .btn-default { background: #fff; border: 1px solid var(--border); color: var(--text-main); }
  .btn-default:hover { background: var(--bg-main); border-color: #c3cddd; }
  .btn.btn-primary { background: var(--accent); border-color: var(--accent); color: #fff; }
  .btn.btn-primary:hover, .btn.btn-primary:focus { background: var(--accent-dark); border-color: var(--accent-dark); color: #fff; }
  .btn.btn-danger { background: #fff; border: 1px solid var(--error); color: var(--error); }
  .btn.btn-danger:hover { background: var(--error); border-color: var(--error); color: #fff; }
  #topbar .btn.btn-danger { background: rgba(255,255,255,0.12); border-color: rgba(255,255,255,0.45); color: #fff; }
  #topbar .btn.btn-danger:hover { background: var(--error); border-color: var(--error); }

  /* Inputs */
  .form-control:focus { border-color: var(--accent); box-shadow: 0 0 0 2px rgba(47,111,208,0.15); }
  .progress-bar { background-color: var(--accent); }

  /* Tables */
  .table > thead > tr > th { color: var(--text-muted); text-transform: uppercase;
    font-size: 11px; letter-spacing: 0.8px; border-bottom: 1px solid var(--border); }
  .table > tbody > tr > td { border-top: 1px dashed var(--border); }
  .table > tbody > tr:hover > td { background: var(--bg-main); }

  /* Scrollable loss list: fixed height, header stays put while scrolling */
  .loss-scroll { max-height: 320px; overflow-y: auto;
                 border: 1px solid var(--border); border-radius: 6px; }
  .loss-scroll table { margin-bottom: 0; }
  .loss-scroll thead th { position: sticky; top: 0; background: var(--bg-card); }
"))

# One Back/Next footer for a step. Either button id may be NULL to omit it.
step_nav <- function(back_id = NULL, back_label = NULL,
                     next_id = NULL, next_label = NULL) {
  shiny::tags$div(
    style = "margin-top: 20px; display: flex; justify-content: space-between;",
    if (is.null(back_id)) shiny::tags$span() else
      shiny::actionButton(back_id, back_label),
    if (is.null(next_id)) shiny::tags$span() else
      shiny::actionButton(next_id, next_label, class = "btn-primary")
  )
}

ui <- shiny::fluidPage(
  app_css,
  # Burgundy top banner: title on the left, always-visible Shut down on the right.
  shiny::tags$div(id = "topbar",
    shiny::tags$div(class = "topbar-title", "Paco's Pricing Pipeline"),
    shiny::tags$div(class = "topbar-actions",
      shiny::actionButton("quit", "Shut down", class = "btn-danger btn-sm"),
      shiny::tags$div(class = "topbar-note", "Or close this tab to stop the tool.")
    )
  ),
  shiny::tabsetPanel(id = "step",
    # Step 1: load the data and see what came in.
    shiny::tabPanel("Data", value = "data",
      shiny::fileInput("file", "Upload pricing workbook (.xlsx)", accept = ".xlsx"),
      shiny::helpText("Your upload stays loaded across page refreshes."),
      shiny::uiOutput("data_info"),
      shiny::fluidRow(
        shiny::column(6, shiny::tags$h4("Losses"),
          shiny::tags$div(class = "loss-scroll", shiny::tableOutput("loss_preview"))),
        shiny::column(6,
          shiny::tags$h4("Exposure & inflation by year"),
          shiny::tags$div(class = "loss-scroll", shiny::tableOutput("year_table")),
          shiny::tags$h4("Data parameters"),
          shiny::tableOutput("data_params"))
      ),
      step_nav(next_id = "nav_1_next", next_label = "Next: Model")),

    # Step 2: choose the modelling thresholds while watching the fit.
    shiny::tabPanel("Model", value = "model",
      shiny::fluidRow(
        shiny::column(4,
          shiny::helpText("Pick where the tail begins. The plots update live. Red line = MT, blue dashed = splice."),
          shiny::numericInput("mt", "Modelling threshold (MT)", value = NA),
          shiny::numericInput("s", "Splice threshold (lognormal to Pareto)", value = NA),
          shiny::selectInput("freq", "Frequency model",
                             choices = c("Poisson" = "poisson",
                                         "Negative Binomial" = "negbin",
                                         "Binomial" = "binomial"),
                             selected = "poisson")),
        shiny::column(8,
          shiny::plotOutput("me_plot"),
          shiny::plotOutput("sev_plot"),
          shiny::tableOutput("fit_params"))
      ),
      step_nav("nav_2_back", "Back: Data", "nav_2_next", "Next: Structure")),

    # Step 3: build the program to price.
    shiny::tabPanel("Structure", value = "structure",
      shiny::helpText("Define the reinsurance layers to price. Each row is a cover excess of a deductible. Add or remove layers."),
      shiny::helpText("Leave AAD blank for no aggregate deductible, and AAL blank for an unlimited aggregate. A blank is not the same as 0."),
      shiny::fluidRow(
        shiny::column(3, shiny::tags$strong("Deductible")),
        shiny::column(3, shiny::tags$strong("Cover")),
        shiny::column(2, shiny::tags$strong("AAD")),
        shiny::column(2, shiny::tags$strong("AAL")),
        shiny::column(2, "")
      ),
      shiny::uiOutput("structure_ui"),
      shiny::actionButton("add_layer", "Add layer"),
      step_nav("nav_3_back", "Back: Model", "nav_3_next", "Next: Price")),

    # Step 4: set the loadings, run the Monte Carlo, read the price.
    shiny::tabPanel("Price", value = "price",
      shiny::fluidRow(
        shiny::column(4,
          shiny::numericInput("load_ev", "Loading (expected value)", value = 0.1, step = 0.05),
          shiny::numericInput("load_sd", "Loading (std dev)", value = 0.2, step = 0.05),
          shiny::numericInput("var_level", "VaR / TVaR level", value = 0.99, min = 0.5, max = 0.999, step = 0.005),
          shiny::numericInput("nsim", "Simulations", value = 100000, min = 1000, step = 1000),
          shiny::numericInput("seed", "Random seed", value = 1),
          shiny::actionButton("run", "Run pricing", class = "btn-primary"),
          shiny::tags$br(), shiny::tags$br(),
          shiny::downloadButton("download", "Download results")),
        shiny::column(8,
          shiny::tags$h4("Results"), shiny::tableOutput("results"),
          shiny::tags$h4("Validation"), shiny::tableOutput("validation"))
      ),
      step_nav("nav_4_back", "Back: Structure"))
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

  # ---- Step navigation ----
  # The tabs are clickable (free jumping); these Back/Next buttons just move the
  # active step for the linear path. Nothing is gated.
  go_to <- function(step) shiny::updateTabsetPanel(session, "step", selected = step)
  shiny::observeEvent(input$nav_1_next, go_to("model"))
  shiny::observeEvent(input$nav_2_back, go_to("data"))
  shiny::observeEvent(input$nav_2_next, go_to("structure"))
  shiny::observeEvent(input$nav_3_back, go_to("model"))
  shiny::observeEvent(input$nav_3_next, go_to("price"))
  shiny::observeEvent(input$nav_4_back, go_to("structure"))

  # ---- Editable contract structure ----
  # The dashboard owns the program now (it is no longer in the workbook). Layers
  # live in a reactiveValues data frame keyed by a stable integer id, so adding
  # or removing one never reshuffles the others. Each layer's live values are
  # held in numericInputs named layer_<id>_<field>, read back when pricing.
  layers <- shiny::reactiveValues(seq = 0L, df = NULL)
  observed_removes <- new.env(parent = emptyenv())

  # Copies current input values back into layers$df so an add/remove (which
  # re-renders the table) does not lose edits made to the other rows.
  snapshot_edits <- function() {
    df <- layers$df
    if (is.null(df) || nrow(df) == 0) return(invisible())
    for (i in seq_len(nrow(df))) {
      id <- df$id[i]
      for (f in c("deductible", "cover", "aad", "aal")) {
        v <- input[[paste0("layer_", id, "_", f)]]
        if (!is.null(v) && !is.na(v)) df[i, f] <- v
      }
    }
    layers$df <- df
  }

  # Wires one Remove button to drop its layer. Guarded so re-renders do not
  # stack duplicate observers on the same id.
  make_remove_observer <- function(id) {
    key <- as.character(id)
    if (!is.null(observed_removes[[key]])) return(invisible())
    observed_removes[[key]] <- TRUE
    shiny::observeEvent(input[[paste0("remove_", id)]], {
      snapshot_edits()
      layers$df <- layers$df[layers$df$id != id, , drop = FALSE]
    }, ignoreInit = TRUE)
  }

  # Seed the default program when the session starts.
  local({
    dc <- default_contract()
    dc$id <- seq_len(nrow(dc))
    layers$seq <- nrow(dc)
    layers$df <- dc[, c("id", "deductible", "cover", "aad", "aal")]
    for (id in dc$id) make_remove_observer(id)
  })

  # Add a fresh layer seeded with sensible defaults.
  shiny::observeEvent(input$add_layer, {
    snapshot_edits()
    layers$seq <- layers$seq + 1L
    new_row <- data.frame(id = layers$seq, deductible = 0, cover = 5,
                          aad = NA_real_, aal = NA_real_)
    layers$df <- rbind(layers$df, new_row)
    make_remove_observer(layers$seq)
  })

  # Render one row of numeric inputs per layer.
  output$structure_ui <- shiny::renderUI({
    df <- layers$df
    if (is.null(df) || nrow(df) == 0) {
      return(shiny::helpText("No layers. Click Add layer to start."))
    }
    rows <- lapply(seq_len(nrow(df)), function(i) {
      id <- df$id[i]
      nid <- function(f) paste0("layer_", id, "_", f)
      shiny::fluidRow(
        shiny::column(3, shiny::numericInput(nid("deductible"), NULL, value = df$deductible[i])),
        shiny::column(3, shiny::numericInput(nid("cover"), NULL, value = df$cover[i])),
        shiny::column(2, numeric_input_ph(nid("aad"), df$aad[i], "none")),
        shiny::column(2, numeric_input_ph(nid("aal"), df$aal[i], "unlimited")),
        shiny::column(2, shiny::actionButton(paste0("remove_", id), "Remove", class = "btn-danger btn-sm"))
      )
    })
    do.call(shiny::tagList, rows)
  })

  # The current contract, assembled from the live layer inputs.
  contract <- shiny::reactive({
    df <- layers$df
    empty <- data.frame(deductible = numeric(0), cover = numeric(0),
                        aad = numeric(0), aal = numeric(0))
    if (is.null(df) || nrow(df) == 0) return(build_contract_df(empty))
    rows <- lapply(seq_len(nrow(df)), function(i) {
      id <- df$id[i]
      val <- function(f) {
        v <- input[[paste0("layer_", id, "_", f)]]
        if (is.null(v)) df[i, f] else v
      }
      data.frame(deductible = val("deductible"), cover = val("cover"),
                 aad = val("aad"), aal = val("aal"))
    })
    build_contract_df(do.call(rbind, rows))
  })

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

  # ---- Step 1 data preview ----
  # A short confirmation of what loaded: filename, loss count, and year range.
  output$data_info <- shiny::renderUI({
    d <- input_data()
    yrs <- range(d$losses$year)
    shiny::tags$p(shiny::tags$strong(rv$name), sprintf(
      " loaded: %d losses across %d-%d.", nrow(d$losses), yrs[1], yrs[2]))
  })

  # The full loss list, so the user can sanity-check every claim. The table sits
  # in a fixed-height scrollable box (see .loss-scroll), so a long list does not
  # push the rest of the screen down.
  output$loss_preview <- shiny::renderTable(input_data()$losses)

  # Exposure and the per-year loss inflation, side by side per year.
  output$year_table <- shiny::renderTable({
    d <- input_data()
    yt <- merge(d$exposure, d$inflation, by = "year", all = TRUE)
    yt <- yt[order(yt$year), ]
    data.frame(
      Year = as.character(yt$year),
      Exposure = yt$exposure,
      `Inflation %` = round(yt$inflation * 100, 2),
      check.names = FALSE
    )
  })

  # The data parameters carried by the workbook (read-only here; the modelling
  # choices are set on the Model step, not in the file).
  output$data_params <- shiny::renderTable({
    p <- input_data()$parameters
    data.frame(
      Parameter = c("Reporting threshold", "Valuation year"),
      Value = c(p$reporting_threshold, p$valuation_year),
      check.names = FALSE
    )
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
    ct <- contract()
    msg <- validate_contract(ct)
    shiny::validate(shiny::need(is.null(msg), msg))
    # Show a progress bar through the pricing phases; the Monte Carlo simulation
    # is the slow step, so the bar sits there the longest.
    shiny::withProgress(message = "Pricing", value = 0, {
      shiny::incProgress(0.15, detail = "Fitting frequency and severity")
      f <- fit_models(inp, st)
      shiny::incProgress(0.55, detail = "Running Monte Carlo simulation")
      out <- price_models(f, ct, st, input$seed)
      shiny::incProgress(0.3, detail = "Summarising results")
      out
    })
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
