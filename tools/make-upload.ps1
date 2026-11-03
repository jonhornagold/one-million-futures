# Builds a clean "upload-to-github" folder with only the files that belong in the public repository.
# Private project notes (CLAUDE.md, MEMORY.md, PRD.md, .claude) are deliberately left out.
# Usage:
#   First upload:   powershell -ExecutionPolicy Bypass -File tools\make-upload.ps1
#   Later updates:  powershell -ExecutionPolicy Bypass -File tools\make-upload.ps1 -Update
#   -Update leaves out data\ because the copy on GitHub is newer (it holds the approved daily stories),
#   and uploading the local one would overwrite them.
param([switch]$Update)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root "upload-to-github"

# Make sure the published story file is up to date first
& (Join-Path $root "pipeline\build.ps1")

if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item -ItemType Directory -Force $dest | Out-Null

$items = @(
  "index.html", "README.md", ".gitignore",
  "css", "js", "docs", ".github",
  "data\stories.json", "data\stories.js",
  "pipeline\config.json", "pipeline\collect.ps1", "pipeline\build.ps1",
  "tools\serve.ps1", "tools\make-upload.ps1"
)
if ($Update) { $items = $items | Where-Object { $_ -notlike "data\*" } }
foreach ($i in $items) {
  $src = Join-Path $root $i
  $target = Join-Path $dest $i
  New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
  Copy-Item $src $target -Recurse -Force
}

Write-Host "Upload folder ready: $dest"
Get-ChildItem $dest -Recurse -File | ForEach-Object { "  " + $_.FullName.Substring($dest.Length + 1) }
