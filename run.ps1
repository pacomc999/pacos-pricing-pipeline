# Bootstrapping launcher for Paco's Pragmatic Pricing Pipeline.
# Finds R (installing it if necessary), installs package dependencies, and opens
# the dashboard. Invoked by start.bat so users only have to double-click.

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

# Locate Rscript: PATH first, then any per-machine or per-user R install.
function Find-Rscript {
  $onPath = (Get-Command Rscript.exe -ErrorAction SilentlyContinue).Source
  if ($onPath) { return $onPath }
  $roots = @("$env:ProgramFiles\R", "${env:ProgramFiles(x86)}\R",
             "$env:LOCALAPPDATA\Programs\R")
  foreach ($root in $roots) {
    if (Test-Path $root) {
      $newest = Get-ChildItem $root -Directory -Filter 'R-*' -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -First 1
      if ($newest) {
        $rs = Join-Path $newest.FullName 'bin\Rscript.exe'
        if (Test-Path $rs) { return $rs }
      }
    }
  }
  return $null
}

# Download the current R installer from CRAN and run it.
function Install-R {
  Write-Host "R is not installed. Downloading R from CRAN (this can take a few minutes)..."
  $base = 'https://cran.r-project.org/bin/windows/base/'
  $file = 'R-4.5.2-win.exe'   # fallback if the page cannot be parsed
  try {
    $page = Invoke-WebRequest -Uri $base -UseBasicParsing
    $m = [regex]::Match($page.Content, 'R-\d+\.\d+\.\d+-win\.exe')
    if ($m.Success) { $file = $m.Value }
  } catch { }
  $url = $base + $file
  $dest = Join-Path $env:TEMP $file
  Write-Host "Downloading $url"
  Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
  Write-Host "Installing R. Please approve the security prompt and accept the defaults."
  try {
    # Silent install (needs administrator approval via the UAC prompt).
    Start-Process -FilePath $dest `
      -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -Verb RunAs -Wait
  } catch {
    # If elevation is declined, fall back to the normal installer window.
    Write-Host "Opening the R installer for manual setup; accept the defaults."
    Start-Process -FilePath $dest -Wait
  }
}

$rscript = Find-Rscript
if (-not $rscript) {
  Install-R
  $rscript = Find-Rscript
}
if (-not $rscript) {
  Write-Host ""
  Write-Host "R could not be installed automatically. Please install it manually"
  Write-Host "from https://cran.r-project.org and run this again."
  exit 1
}

Write-Host "Using R at: $rscript"
Write-Host "Checking dependencies (the first run can take a few minutes)..."
& $rscript 'install_deps.R'
if (-not (Test-Path 'example_input.xlsx')) { & $rscript 'make_example.R' }

Write-Host ""
Write-Host "Starting Paco's Pragmatic Pricing Pipeline."
Write-Host "A browser tab will open. Keep this window open while you use the tool;"
Write-Host "close it to stop the dashboard."
& $rscript '-e' 'shiny::runApp(".", launch.browser = TRUE)'
