# Builds the zip we hand out to end users, for attaching to a GitHub Release.
#
# Only ships what an end user needs to run the tool: the launchers, the R
# code, the example workbook, the README, and the compiled Technical
# documentation.docx. Dev-only material (tests, this script, CLAUDE.md, the
# markdown source the docx is built from) is left out on purpose.
#
# Named "_internal" so it is clear this is not the file to double click,
# use build_release.bat for that. This script is the real logic behind it,
# and can also be run directly if you prefer typing a command:
#   .\engine\build_release_internal.ps1 -Version 1.1.0
#
# This only builds the zip. It does not publish anything, since creating a
# public GitHub Release is a one-way, visible-to-others action you should
# trigger yourself, on purpose, each time. The script prints the exact
# command to run for that as its last step.

param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$ErrorActionPreference = "Stop"

# This script lives in engine/, so the repo root is one level up.
$root = Split-Path -Parent $PSScriptRoot
$distDir = Join-Path $root "dist"
$stagingDir = Join-Path $distDir "staging"
$zipName = "pacos-pricing-pipeline-v$Version.zip"
$zipPath = Join-Path $distDir $zipName

# Everything that ships as-is, with its path relative to the repo root.
$includePaths = @(
    "start.vbs",
    "Start in RStudio.R",
    "input.xlsx",
    "README.md",
    "Technical documentation.docx",
    "engine\app.R",
    "engine\install_deps.R",
    "engine\make_example.R",
    "engine\start.bat"
)

# Start from a clean staging folder so old builds never leak into a new zip.
if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
New-Item -ItemType Directory -Path $stagingDir | Out-Null

foreach ($relPath in $includePaths) {
    $source = Join-Path $root $relPath
    if (-not (Test-Path $source)) {
        throw "Expected file not found: $relPath"
    }
    $destination = Join-Path $stagingDir $relPath
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item $source $destination
}

# All R modules (the *.R filter naturally skips the empty .gitkeep placeholder).
$rModulesDest = Join-Path $stagingDir "engine\R"
New-Item -ItemType Directory -Path $rModulesDest -Force | Out-Null
Get-ChildItem (Join-Path $root "engine\R") -Filter "*.R" | Copy-Item -Destination $rModulesDest

if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }
Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $zipPath -Force

Remove-Item $stagingDir -Recurse -Force

Write-Host "Built $zipPath"
Write-Host ""
Write-Host "To publish it as a GitHub Release, run:"
Write-Host "  gh release create v$Version `"$zipPath`" --title `"v$Version`" --notes `"<describe what changed>`""
