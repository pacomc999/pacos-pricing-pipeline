# Regenerate "Technical documentation.docx" from documentation.md.
#
# The Word version is a generated artifact, not hand-maintained: edit
# documentation.md, then run this to rebuild the .docx. Pandoc does the work; it
# ships bundled with RStudio and Quarto, so this finds it even when it is not on
# the system PATH.
#
# Run from anywhere:  Rscript engine/docs/build_docx.R

# Locate this script so the paths work whatever the working directory is.
args <- commandArgs(FALSE)
file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
script_dir <- if (length(file_arg)) dirname(normalizePath(file_arg)) else getwd()

md <- file.path(script_dir, "documentation.md")
# The .docx lives at the repo root, two levels up from engine/docs.
docx <- normalizePath(file.path(script_dir, "..", "..", "Technical documentation.docx"),
                      mustWork = FALSE)

# Find pandoc: the PATH first, then the usual RStudio / Quarto bundle locations.
find_pandoc <- function() {
  on_path <- Sys.which("pandoc")
  if (nzchar(on_path)) return(unname(on_path))
  pf <- Sys.getenv("PROGRAMFILES")
  candidates <- c(
    file.path(pf, "RStudio", "resources", "app", "bin", "quarto", "bin", "tools", "pandoc.exe"),
    file.path(pf, "RStudio", "bin", "pandoc", "pandoc.exe"),
    file.path(pf, "Quarto", "bin", "tools", "pandoc.exe")
  )
  hit <- candidates[file.exists(candidates)]
  if (length(hit)) return(hit[1])
  stop("pandoc not found. Install pandoc, or RStudio/Quarto, which bundle it.")
}

pandoc <- find_pandoc()
status <- system2(pandoc, c(shQuote(md), "-o", shQuote(docx)))
if (status != 0) stop("pandoc failed with status ", status)
cat("Wrote", docx, "\n")
