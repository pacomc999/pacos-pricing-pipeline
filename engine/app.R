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

# Turns the live contract into per-layer rows for the structure tower plot: each
# block spans deductible to deductible+cover, with a terms label and a formatted
# aggregate (AAD/AAL) label. Rows without a positive cover (blank or mid-edit)
# are dropped. Pure and unit-tested; the render only draws from this.
build_structure_plot_data <- function(contract) {
  fmt <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
  keep <- is.finite(contract$cover) & contract$cover > 0 &
          is.finite(contract$deductible) & contract$deductible >= 0
  ct <- contract[keep, , drop = FALSE]
  if (nrow(ct) == 0) {
    return(data.frame(layer = integer(0), deductible = numeric(0),
                      top = numeric(0), terms = character(0),
                      aggregate = character(0), stringsAsFactors = FALSE))
  }
  aad_txt <- ifelse(is.na(ct$aad), "none", fmt(ct$aad))
  aal_txt <- ifelse(is.na(ct$aal), "unlimited", fmt(ct$aal))
  data.frame(
    layer = seq_len(nrow(ct)),
    deductible = ct$deductible,
    top = ct$deductible + ct$cover,
    terms = paste0(fmt(ct$cover), " xs ", fmt(ct$deductible)),
    aggregate = paste0("AAD ", aad_txt, " / AAL ", aal_txt),
    stringsAsFactors = FALSE
  )
}

# Builds a short money-unit label like "EUR millions" from the optional currency
# and amount_units general inputs, dropping whichever is missing ("" if neither).
unit_label <- function(currency, units) {
  parts <- c(currency, units)
  parts <- parts[!is.na(parts) & nzchar(as.character(parts))]
  paste(parts, collapse = " ")
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
    `Premium (EV)` = round(priced$premium_ev, 2),
    `Premium (SD)` = round(priced$premium_sd, 2),
    check.names = FALSE
  )
}

# A signature of the inputs that determine a price (data, modelling settings,
# contract, seed). Two equal signatures mean the same price, so comparing the
# signature from the last run with the live one tells us if results are stale.
price_signature <- function(data, settings, contract, seed) {
  list(data = data, settings = settings, contract = contract, seed = seed)
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

  /* Premiums are the headline numbers: emphasise the last two result column
     headers (Premium (EV) and Premium (SD)). Scoped to #results so the
     validation and data preview tables are untouched. */
  #results th:last-child, #results th:nth-last-child(2) { color: var(--navy-mid); }

  /* Stale results: amber notice plus faded tables until the next Run. Amber, not
     red, because red is reserved for destructive actions and errors. */
  .stale-banner { background: #fff7e6; border: 1px solid #f0c36d;
    border-left: 4px solid #d98324; border-radius: 6px; padding: 10px 14px;
    margin-bottom: 16px; color: #7a4f12; font-weight: 600; }
  .results-area.stale { opacity: 0.5; transition: opacity 0.15s ease; }

  /* Scrollable data preview: fixed height so the Losses and Exposure tables
     line up top and bottom; the header stays put while scrolling. */
  .loss-scroll { height: 320px; overflow-y: auto;
                 border: 1px solid var(--border); border-radius: 6px; }
  .loss-scroll table { margin-bottom: 0; }
  .loss-scroll thead th { position: sticky; top: 0; background: var(--bg-card); }

  /* Collapsible 'More information' panel at the top of each step */
  .info-panel { background: #eef3fb; border: 1px solid var(--border);
                border-left: 4px solid var(--accent); border-radius: 6px;
                padding: 0 16px; margin-bottom: 22px; }
  .info-panel > summary { cursor: pointer; padding: 12px 0; font-weight: 600;
                color: var(--navy-mid); list-style: none; }
  .info-panel > summary::-webkit-details-marker { display: none; }
  .info-panel > summary::before { content: 'i'; display: inline-block;
                width: 18px; height: 18px; line-height: 18px; text-align: center;
                margin-right: 8px; border-radius: 50%; font-style: italic;
                font-weight: 700; background: var(--accent); color: #fff; }
  .info-panel[open] > summary { border-bottom: 1px solid var(--border); }
  .info-panel .info-body { padding: 12px 2px 16px; color: var(--text-main); font-size: 14px; }
  .info-panel .info-body p { margin-bottom: 8px; }
  .info-panel .info-body ul { margin-bottom: 0; padding-left: 20px; }
  .info-panel .info-body li { margin-bottom: 4px; }

  /* Premium method card: groups one loading with the formula it drives, so the
     two methods read as alternatives rather than margins added together */
  .method-card { background: var(--bg-main); border: 1px solid var(--border);
                 border-radius: 6px; padding: 12px 14px 2px; margin-bottom: 14px; }
  .method-card .method-title { font-weight: 600; color: var(--navy-mid);
                 font-size: 14px; margin-bottom: 2px; }
  .method-card .method-formula { color: var(--text-muted); font-size: 12px;
                 margin-bottom: 8px; }

  /* Calibration card: groups one calibration (frequency or severity) with its
     own controls and outputs, so the Model step reads as two separate pieces
     stacked vertically rather than one mixed block. */
  .calib-card { background: #f4f7fc; border: 1px solid var(--border);
                border-radius: 8px; padding: 18px 20px 8px; margin-bottom: 18px; }
  .calib-card .calib-title { font-weight: 600; color: var(--navy-mid);
                font-size: 16px; margin: 0 0 14px; }
"))

# A collapsible 'More information' panel for the top of a step. It starts closed
# so the guided flow stays uncluttered, and opens on click to explain what the
# tool does and what this step is for. Content is passed as child tags.
info_panel <- function(...) {
  shiny::tags$details(class = "info-panel",
    shiny::tags$summary("More information"),
    shiny::tags$div(class = "info-body", ...)
  )
}

# A titled card for one premium method: its name, the formula it uses, and the
# loading input that drives it. Shows the two methods are alternatives, each with
# its own premium, rather than two margins added together.
method_card <- function(title, formula, input) {
  shiny::tags$div(class = "method-card",
    shiny::tags$div(class = "method-title", title),
    shiny::tags$div(class = "method-formula", formula),
    input
  )
}

# A titled card for one calibration (frequency or severity): its name plus its
# own controls and outputs. Stacking two of these vertically keeps the frequency
# and severity calibrations visually separate on the Model step.
calib_card <- function(title, ...) {
  shiny::tags$div(class = "calib-card",
    shiny::tags$div(class = "calib-title", title),
    ...
  )
}

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
      info_panel(
        shiny::tags$p(shiny::tags$strong("What this tool does."),
          " Paco's Pricing Pipeline prices non-proportional reinsurance from a",
          " historical loss list. You load the data here, define the layers to",
          " price, choose how to model it, then run a simulation to get a premium."),
        shiny::tags$p(shiny::tags$strong("This step"),
          " loads the pricing template, a ready-made Excel workbook provided",
          " with the tool. You do not build it yourself; you just fill your own",
          " figures into its four sheets:"),
        shiny::tags$ul(
          shiny::tags$li(shiny::tags$strong("general inputs"), ": the valuation year (the year losses are revalued to) and the reporting threshold (the loss size above which the data is complete), both required, plus an optional currency and amount units that label the figures."),
          shiny::tags$li(shiny::tags$strong("losses"), ": one row per claim (year and loss amount)."),
          shiny::tags$li(shiny::tags$strong("exposure"), ": a measure of how much business was written each year."),
          shiny::tags$li(shiny::tags$strong("inflation"), ": the loss inflation rate for each year.")
        ),
        shiny::tags$p("The losses are revalued to the valuation year using the",
          " inflation rates, and the claim frequency is scaled by how exposure",
          " changes. The preview below lets you sanity-check what came in.")
      ),
      # Upload control on the left, the workbook's general inputs to its right,
      # so the two preview tables below start at the same height.
      shiny::fluidRow(
        shiny::column(6,
          shiny::fileInput("file", "Upload the filled-in template (.xlsx)", accept = ".xlsx"),
          shiny::uiOutput("data_info")),
        shiny::column(6,
          shiny::tags$h4("General inputs"),
          shiny::tableOutput("data_params"))
      ),
      shiny::fluidRow(
        shiny::column(6,
          shiny::tags$h4("Losses"),
          shiny::tags$div(class = "loss-scroll", shiny::tableOutput("loss_preview"))),
        shiny::column(6,
          shiny::tags$h4("Exposure & inflation by year"),
          shiny::tags$div(class = "loss-scroll", shiny::tableOutput("year_table")))
      ),
      step_nav(next_id = "nav_1_next", next_label = "Next: Reinsurance structure")),

    # Step 2: build the program to price. This comes before modelling so the
    # lowest deductible is known when the modelling threshold is chosen.
    shiny::tabPanel("Reinsurance structure", value = "structure",
      info_panel(
        shiny::tags$p(shiny::tags$strong("This step"),
          " defines the reinsurance program to price. Each layer pays a cover",
          " excess of a deductible. Add or remove as many layers as you like;",
          " the structure lives here in the dashboard, not in the workbook."),
        shiny::tags$ul(
          shiny::tags$li(shiny::tags$strong("Deductible"),
            ": the loss size where the layer starts paying."),
          shiny::tags$li(shiny::tags$strong("Cover"),
            ": the most the layer pays on a single loss."),
          shiny::tags$li(shiny::tags$strong("AAD (annual aggregate deductible)"),
            ": the layer absorbs this much in total over the year before it pays anything. Blank means none."),
          shiny::tags$li(shiny::tags$strong("AAL (annual aggregate limit)"),
            ": the most the layer pays across the whole year. Blank means unlimited.")
        ),
        shiny::tags$p("A blank aggregate is not the same as 0: blank turns the",
          " control off, while 0 would mean a zero deductible or a zero limit.")
      ),
      shiny::fluidRow(
        shiny::column(3, shiny::tags$strong("Deductible")),
        shiny::column(3, shiny::tags$strong("Cover")),
        shiny::column(2, shiny::tags$strong("AAD")),
        shiny::column(2, shiny::tags$strong("AAL")),
        shiny::column(2, "")
      ),
      shiny::uiOutput("structure_ui"),
      shiny::actionButton("add_layer", "Add layer"),
      shiny::tags$h4("Layer structure", style = "margin-top: 26px;"),
      shiny::plotOutput("structure_plot", height = "360px"),
      step_nav("nav_2_back", "Back: Data", "nav_2_next", "Next: Model")),

    # Step 3: choose the modelling thresholds while watching the fit.
    shiny::tabPanel("Model", value = "model",
      info_panel(
        shiny::tags$p(shiny::tags$strong("This step"),
          " fits the two ingredients of the price: how often losses happen",
          " (frequency) and how big they are (severity)."),
        shiny::tags$ul(
          shiny::tags$li(shiny::tags$strong("Frequency model"),
            ": how the yearly count of losses is distributed (Poisson, Negative Binomial or Binomial)."),
          shiny::tags$li(shiny::tags$strong("Severity"),
            ": a lognormal body for ordinary losses spliced onto a Pareto tail for the large ones."),
          shiny::tags$li(shiny::tags$strong("Modelling threshold (MT)"),
            ": the loss size where modelling starts; smaller losses are ignored."),
          shiny::tags$li(shiny::tags$strong("Splice threshold"),
            ": where the lognormal body hands over to the heavier Pareto tail.")
        ),
        shiny::tags$p("The severity plot updates live as you move the thresholds,",
          " so you can see how well the fitted curve matches the data and choose",
          " where the tail begins.")
      ),
      # Shared modelling threshold: it gates both calibrations (which losses are
      # counted, and where the severity fit starts), so it sits above both cards.
      shiny::fluidRow(
        shiny::column(4,
          shiny::numericInput("mt", "Modelling threshold (MT)", value = NA),
          shiny::helpText("The loss size where modelling starts; smaller losses are ignored."))
      ),
      # Frequency calibration: the model choice and its fitted summary.
      calib_card("Frequency calibration",
        shiny::fluidRow(
          shiny::column(4,
            shiny::selectInput("freq", "Frequency model",
                               choices = c("Poisson" = "poisson",
                                           "Negative Binomial" = "negbin",
                                           "Binomial" = "binomial"),
                               selected = "poisson")),
          shiny::column(8,
            shiny::plotOutput("freq_plot"),
            shiny::tableOutput("freq_summary")))
      ),
      # Severity calibration: the splice threshold, the live fit plot, and params.
      calib_card("Severity calibration",
        shiny::fluidRow(
          shiny::column(4,
            shiny::selectInput("sev_model", "Severity model",
                               choices = c("Single Pareto" = "single",
                                           "Lognormal body + Pareto tail" = "spliced"),
                               selected = "single"),
            # The splice threshold only matters for the spliced model; hide it for
            # the single Pareto (where it is fixed at the modelling threshold).
            shiny::conditionalPanel(
              condition = "input.sev_model == 'spliced'",
              shiny::numericInput("s", "Splice threshold (lognormal to Pareto)", value = NA),
              shiny::helpText("Pick where the tail begins. The plot updates live. Orange dashed line = splice threshold."))),
          shiny::column(8,
            shiny::uiOutput("sev_body_warning"),
            shiny::plotOutput("sev_plot"),
            shiny::tableOutput("sev_params")))
      ),
      step_nav("nav_3_back", "Back: Reinsurance structure", "nav_3_next", "Next: Price")),

    # Step 4: set the loadings, run the Monte Carlo, read the price.
    shiny::tabPanel("Price", value = "price",
      info_panel(
        shiny::tags$p(shiny::tags$strong("This step"),
          " runs the Monte Carlo simulation: it draws many simulated years from",
          " the fitted frequency and severity, applies each layer, and turns the",
          " resulting losses into a premium."),
        shiny::tags$p(shiny::tags$strong("Two premium methods."),
          " The tool prices each layer both ways and shows both so you can",
          " compare. They are alternatives, not added together:"),
        shiny::tags$ul(
          shiny::tags$li(shiny::tags$strong("Expected value method"),
            ": premium = (1 + loading) × expected loss. A flat margin on top of the average loss."),
          shiny::tags$li(shiny::tags$strong("Standard deviation method"),
            ": premium = expected loss + loading × volatility. A margin that grows with how volatile the layer is."),
          shiny::tags$li(shiny::tags$strong("VaR / TVaR level"),
            ": the percentile used for the tail risk measures."),
          shiny::tags$li(shiny::tags$strong("Simulations"),
            ": more simulations give a smoother result but take longer to run."),
          shiny::tags$li(shiny::tags$strong("Random seed"),
            ": fixes the random draws so a run is reproducible.")
        ),
        shiny::tags$p("Results show the expected loss, risk measures and two",
          " premiums. Validation compares the simulated expected loss to a",
          " closed-form figure as a sanity check; small differences are expected."),
        shiny::tags$p(shiny::tags$strong("Burning cost"),
          " in the validation table is the average annual loss to each layer",
          " measured straight from the history, on an as-if basis: every past",
          " loss is first restated to today by indexing it for inflation and",
          " correcting for the change in exposure (as if it had happened now).",
          " It is a purely empirical benchmark, so if the modelled expected loss",
          " sits far from it, the fit is worth a second look.")
      ),
      shiny::fluidRow(
        shiny::column(4,
          method_card("Expected value method",
                      "Premium = (1 + loading) × expected loss",
                      shiny::numericInput("load_ev", "Loading", value = 0.1, step = 0.05)),
          method_card("Standard deviation method",
                      "Premium = expected loss + loading × std dev",
                      shiny::numericInput("load_sd", "Loading", value = 0.2, step = 0.05)),
          shiny::numericInput("var_level", "VaR / TVaR level", value = 0.99, min = 0.5, max = 0.999, step = 0.005),
          shiny::numericInput("nsim", "Simulations", value = 100000, min = 1000, step = 1000),
          shiny::numericInput("seed", "Random seed", value = 1),
          shiny::actionButton("run", "Run pricing", class = "btn-primary"),
          shiny::tags$br(), shiny::tags$br(),
          shiny::downloadButton("download", "Download results")),
        shiny::column(8,
          shiny::uiOutput("results_area"))
      ),
      step_nav("nav_4_back", "Back: Model"))
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
  shiny::observeEvent(input$nav_1_next, go_to("structure"))
  shiny::observeEvent(input$nav_2_back, go_to("data"))
  shiny::observeEvent(input$nav_2_next, go_to("model"))
  shiny::observeEvent(input$nav_3_back, go_to("structure"))
  shiny::observeEvent(input$nav_3_next, go_to("price"))
  shiny::observeEvent(input$nav_4_back, go_to("model"))

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

  # Live tower plot of the layer structure, so the user can visually check the
  # program. Reads the same contract() as pricing, so it always matches.
  output$structure_plot <- shiny::renderPlot({
    d <- build_structure_plot_data(contract())
    if (nrow(d) == 0) {
      plot.new()
      graphics::text(0.5, 0.5, "Add a layer to see the structure.",
                     col = "#69707c", cex = 1.1)
      return(invisible())
    }
    n <- nrow(d)
    ymax <- max(d$top) * 1.14
    u <- money_units()
    ylab_txt <- if (nzchar(u)) paste0("Loss amount (", u, ")") else "Loss amount"
    plot(NA, xlim = c(0.5, n + 0.5), ylim = c(0, ymax), xaxt = "n",
         xlab = "", ylab = ylab_txt)
    graphics::axis(1, at = seq_len(n), labels = paste("Layer", d$layer))
    # Dotted guide lines at every layer boundary (each deductible and top). When
    # two layers meet exactly, their lines coincide; a gap or overlap shows as
    # two separate lines, so alignment is easy to check by eye.
    graphics::abline(h = sort(unique(c(d$deductible, d$top))),
                     lty = 3, col = "#9aa6b8")
    w <- 0.35
    graphics::rect(d$layer - w, d$deductible, d$layer + w, d$top,
                   col = "#dce6f6", border = "#2357a8", lwd = 2)
    graphics::text(d$layer, (d$deductible + d$top) / 2, d$terms,
                   font = 2, col = "#16233f")
    graphics::text(d$layer, d$top, d$aggregate, pos = 3, cex = 0.8,
                   col = "#69707c")
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
      "Upload the filled-in input data template (.xlsx) to begin."))
    rv$data
  })

  # Money-unit label ("EUR millions" or "") from the optional general inputs.
  # Read straight from rv$data so it works before any upload (no upload guard),
  # which the always-on structure plot needs.
  money_units <- shiny::reactive({
    p <- rv$data$parameters
    unit_label(p$currency, p$amount_units)
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
    shown <- function(x) {
      if (is.null(x) || all(is.na(x)) || !nzchar(as.character(x))) "(not set)"
      else as.character(x)
    }
    data.frame(
      Parameter = c("Valuation year", "Reporting threshold",
                    "Currency", "Amount units"),
      Value = c(as.character(p$valuation_year), as.character(p$reporting_threshold),
                shown(p$currency), shown(p$amount_units)),
      check.names = FALSE
    )
  })

  # When a workbook is loaded, seed the controls from its defaults (or built-in
  # defaults) so the user starts from a sensible point.
  shiny::observeEvent(input_data(), {
    st <- resolve_settings(input_data()$parameters)
    shiny::updateNumericInput(session, "mt", value = st$modelling_threshold)
    shiny::updateNumericInput(session, "s", value = st$splice_threshold)
    # Start spliced only if the workbook places the splice above the threshold;
    # otherwise the single Pareto (the recommended default) is selected.
    shiny::updateSelectInput(session, "sev_model",
      selected = if (!is.na(st$splice_threshold) &&
                     st$splice_threshold > st$modelling_threshold) "spliced" else "single")
    shiny::updateSelectInput(session, "freq", selected = st$frequency_model)
    shiny::updateNumericInput(session, "nsim", value = st$n_simulations)
    shiny::updateNumericInput(session, "load_ev", value = st$loading_ev)
    shiny::updateNumericInput(session, "load_sd", value = st$loading_sd)
    shiny::updateNumericInput(session, "var_level", value = st$var_level)
  })

  # Current modelling settings from the controls. The single Pareto is just the
  # spliced model with the splice pinned to the modelling threshold (empty body),
  # so the backend is unchanged: it only ever receives a splice threshold.
  settings <- shiny::reactive({
    splice <- if (identical(input$sev_model, "spliced")) input$s else input$mt
    list(modelling_threshold = input$mt, splice_threshold = splice,
         frequency_model = input$freq, n_simulations = input$nsim,
         loading_ev = input$load_ev, loading_sd = input$load_sd,
         var_level = input$var_level)
  })

  # Fast fit (no simulation): drives the Fit tab and updates as thresholds change.
  fits <- shiny::reactive({
    inp <- input_data()
    shiny::validate(shiny::need(!is.na(input$mt), "Set the modelling threshold."))
    # The splice threshold is only needed (and shown) for the spliced model.
    if (identical(input$sev_model, "spliced")) {
      shiny::validate(
        shiny::need(!is.na(input$s), "Set the splice threshold."),
        shiny::need(input$s >= input$mt, "Splice threshold must be at least the modelling threshold.")
      )
    }
    tryCatch(fit_models(inp, settings()),
             error = function(e) shiny::validate(shiny::need(FALSE, conditionMessage(e))))
  })

  # bg matches the .calib-card colour so the plot blends into the severity card
  # instead of showing as a white rectangle inside the tint.
  output$sev_plot <- shiny::renderPlot(bg = "#f4f7fc", {
    f <- fits()
    fit <- f$fit_severity
    above <- f$losses$loss_indexed[f$losses$loss_indexed > fit$mt]
    xs <- seq(fit$mt, max(above), length.out = 200)
    u <- money_units()
    xlab_txt <- if (nzchar(u)) paste0("Loss (", u, ")") else "Loss"
    # Set up the axes only; the curves are drawn after the white panel below.
    plot(xs, 1 - severity_survival(fit, xs), type = "n", ylim = c(0, 1),
         xlab = xlab_txt, ylab = "CDF", main = "Fitted vs empirical severity")
    # Fill the panel interior white so only the margins keep the card tint.
    usr <- graphics::par("usr")
    graphics::rect(usr[1], usr[3], usr[2], usr[4], col = "white", border = NA)
    # Draw the curves on top, thick enough that the colours read clearly. Colours
    # match the frequency plot: blue fitted, grey empirical.
    graphics::lines(xs, 1 - severity_survival(fit, xs), col = "#2f6fd0", lwd = 2.5)
    graphics::lines(sort(above), stats::ecdf(above)(sort(above)), type = "s",
                    col = "grey50", lwd = 2.5)
    # The splice line and its legend entry only make sense for the spliced model
    # (single Pareto has the splice pinned at the modelling threshold).
    spliced <- fit$s > fit$mt
    if (spliced) graphics::abline(v = fit$s, col = "darkorange3", lty = 2, lwd = 2)
    graphics::box()
    labels <- c("Fitted", "Empirical")
    cols   <- c("#2f6fd0", "grey50")
    ltys   <- c(1, 1)
    if (spliced) {
      labels <- c(labels, "Splice threshold")
      cols   <- c(cols, "darkorange3")
      ltys   <- c(ltys, 2)
    }
    legend("bottomright", labels, col = cols, lty = ltys, lwd = 2.5, bty = "n")
  })

  # Caution (amber, non-blocking) when the splice is raised so the lognormal body
  # is fitted on too few losses. Empty when the body is inactive (splice = mt) or
  # there is enough data, so the recommended single-Pareto default stays silent.
  # The body is active only when the splice sits above the modelling threshold;
  # severity_body_warning stays silent for the single-Pareto default and flags an
  # empty or underpopulated body region otherwise.
  output$sev_body_warning <- shiny::renderUI({
    sev <- fits()$fit_severity
    msg <- severity_body_warning(sev$n_body, sev$s > sev$mt)
    if (is.null(msg)) return(NULL)
    shiny::tags$div(class = "stale-banner", msg)
  })

  # Fitted vs empirical frequency: the probability of each yearly claim count,
  # as side-by-side bars. The fitted PMF is refit on the observed counts
  # (unscaled), so it shares a basis with the empirical bars instead of the
  # forward-scaled pricing fit.
  output$freq_plot <- shiny::renderPlot(bg = "#f4f7fc", {
    f <- fits()
    counts <- f$counts
    fq <- fit_frequency(counts, f$fit_frequency$type)
    # x range: cover the observed counts and the fitted upper tail.
    kmax <- max(counts)
    while (sum(frequency_pmf(fq, 0:kmax)) < 0.999 && kmax < 200) kmax <- kmax + 1
    ks <- 0:kmax
    # Empirical mass = fraction of observed years with each count.
    emp_pmf <- as.numeric(table(factor(counts, levels = ks))) / length(counts)
    mat <- rbind(Empirical = emp_pmf, Fitted = frequency_pmf(fq, ks))
    ymax <- max(mat) * 1.1
    # First pass draws invisible bars to set up the axes and bar positions; then
    # paint the panel white and redraw the bars on top, so only the margins keep
    # the card tint.
    barplot(mat, beside = TRUE, ylim = c(0, ymax), col = NA, border = NA,
            names.arg = ks, xlab = "Claims per year", ylab = "Probability",
            main = "Fitted vs empirical frequency")
    usr <- graphics::par("usr")
    graphics::rect(usr[1], usr[3], usr[2], usr[4], col = "white", border = NA)
    barplot(mat, beside = TRUE, col = c("grey70", "#2f6fd0"), border = NA,
            axes = FALSE, axisnames = FALSE, add = TRUE)
    graphics::box()
    legend("topright", c("Empirical", "Fitted"),
           fill = c("grey70", "#2f6fd0"), border = NA, bty = "n")
  })

  # Frequency summary: the model, the forward expected claim count (exposure
  # scaled) and the historical basis it was scaled from. Updates live with MT and
  # the chosen frequency model.
  output$freq_summary <- shiny::renderTable({
    f <- fits()
    fq <- f$fit_frequency
    model_label <- c(poisson = "Poisson", negbin = "Negative Binomial",
                     binomial = "Binomial")[[fq$type]]
    data.frame(
      Quantity = c("Model", "Expected claims per year",
                   "Observed average per year", "Years observed"),
      Value = c(model_label, format(round(fq$expected, 2)),
                format(round(mean(f$counts), 2)), as.character(length(f$counts))),
      check.names = FALSE
    )
  })

  output$sev_params <- shiny::renderTable({
    f <- fits()
    sev <- f$fit_severity
    # Single Pareto (splice = MT): only the tail index is meaningful; the
    # lognormal rows are NA and the weight is always 1, so show just alpha.
    if (!(sev$s > sev$mt)) {
      return(data.frame(Quantity = "Pareto alpha",
                        Value = round(sev$pareto$alpha, 3),
                        check.names = FALSE))
    }
    # Spliced model: tail index, lognormal body, and the body/tail mixture weight.
    # mu/sigma stay NA if the body is too sparse to fit (warned above the plot).
    mu <- if (is.null(sev$lnorm)) NA else round(sev$lnorm$meanlog, 3)
    sg <- if (is.null(sev$lnorm)) NA else round(sev$lnorm$sdlog, 3)
    data.frame(
      Quantity = c("Pareto alpha", "Lognormal mu",
                   "Lognormal sigma", "Tail weight P(X>s | X>MT)"),
      Value = c(round(sev$pareto$alpha, 3),
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
      # Empirical benchmark for validation: the average annual loss to each layer
      # on an as-if basis (losses indexed and exposure corrected), in layer order.
      out$burning_cost <- burning_cost(f$losses, ct)
      out
    })
  })

  # ---- Stale-results detection ----
  # Results persist from the last Run, so changing an input afterwards leaves the
  # tables showing a price that no longer matches the controls. We snapshot the
  # price-determining inputs at each Run and compare them with the live values to
  # flag (and fade) stale results until the user reruns.
  last_sig <- shiny::reactiveVal(NULL)

  # Record what was priced on each valid Run. rv$data sidesteps input_data()'s
  # upload-required guard; the default contract is already valid.
  shiny::observeEvent(input$run, {
    if (is.null(rv$data)) return()
    ct <- contract()
    if (is.null(validate_contract(ct))) {
      last_sig(price_signature(rv$data, settings(), ct, input$seed))
    }
  })

  # Stale when a run has happened and the live inputs no longer match it. The &&
  # short-circuits before the first run, so there is no banner on launch.
  is_stale <- shiny::reactive({
    sig <- last_sig()
    !is.null(sig) &&
      !identical(sig, price_signature(rv$data, settings(), contract(), input$seed))
  })

  # Banner plus a dimmable wrapper around the two result tables. The table
  # outputs below stay unchanged; this just places them inside a fadeable div.
  output$results_area <- shiny::renderUI({
    stale <- isTRUE(is_stale())
    shiny::tagList(
      if (stale) shiny::tags$div(class = "stale-banner",
        "These results are out of date: an input changed since the last run. Click Run pricing to update."),
      shiny::tags$div(class = if (stale) "results-area stale" else "results-area",
        shiny::tags$h4("Results"),
        if (nzchar(money_units()))
          shiny::helpText(paste0("Amounts are in ", money_units(), ".")),
        shiny::tableOutput("results"),
        shiny::tags$h4("Validation"), shiny::tableOutput("validation"))
    )
  })

  output$results <- shiny::renderTable(build_results_table(priced()$results))

  output$validation <- shiny::renderTable({
    p <- priced()
    r <- p$results
    bc <- p$burning_cost
    data.frame(Deductible = r$deductible, Cover = r$cover,
               Simulated = round(r$expected_loss, 3),
               `Closed form` = round(r$oracle, 3),
               Delta = round(r$oracle_delta, 4),
               `Burning cost` = round(bc$bc_advanced, 3), check.names = FALSE)
  })

  output$download <- shiny::downloadHandler(
    filename = function() "output.xlsx",
    content = function(file) {
      st <- settings()
      r <- priced()$results
      gp <- input_data()$parameters
      assumptions <- data.frame(
        key = c("valuation_year", "currency", "amount_units",
                "modelling_threshold", "splice_threshold", "frequency_model",
                "n_simulations", "loading_ev", "loading_sd", "var_level"),
        value = c(gp$valuation_year, gp$currency, gp$amount_units,
                  st$modelling_threshold, st$splice_threshold, st$frequency_model,
                  st$n_simulations, st$loading_ev, st$loading_sd, st$var_level))
      write_output(file, r, assumptions)
    }
  )
}

# If the app starts but no browser ever connects (a 'lost' launch, e.g. the tab
# never opened), it would otherwise linger forever as an orphan process, since
# the per-session shutdown above only runs once a session exists. This runs once
# at startup and stops the app if nothing has connected within the timeout. The
# timeout is an option so tests can use a short value; it defaults to 60 seconds.
app_onstart <- function() {
  later::later(function() {
    if (.app_sessions$count <= 0L) shiny::stopApp()
  }, delay = getOption("ppp.no_connect_timeout", 60))
}

# Returning the app object is the standard app.R contract: shiny::runApp('.')
# launches it, while sourcing this file (in tests) only builds it.
shiny::shinyApp(ui, server, onStart = app_onstart)
