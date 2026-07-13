param(
    [string]$CodexHome = (Join-Path $env:USERPROFILE '.codex')
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Source = Join-Path $RepoRoot 'tools\codex\skills\pz-mod-dev'
$Destination = Join-Path $CodexHome 'skills\pz-mod-dev'

if (-not (Test-Path -LiteralPath $Source)) {
    throw "Bundled skill is missing: $Source"
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
Write-Output ("CodexSkillInstalled={0}" -f $Destination)
