[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9][a-z0-9-]*$')][string]$FeatureName,
    [string]$WorkshopRoot = 'C:\Users\Admin\Zomboid\Workshop\GodSystem',
    [string]$GitSource = 'C:\Users\Admin\Documents\GodSystem-Dev',
    [string]$WorktreeRoot = 'C:\Users\Admin\Documents\GodSystem-Worktrees'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $WorkshopRoot -PathType Container)) { throw "Workshop root is missing: $WorkshopRoot" }
if (-not (Test-Path -LiteralPath $GitSource -PathType Container)) { throw "Git source is missing: $GitSource" }
if (-not (Test-Path -LiteralPath (Join-Path $GitSource '.git') -PathType Container)) { throw "Git source has no .git directory: $GitSource" }

$target = Join-Path $WorktreeRoot $FeatureName
if (Test-Path -LiteralPath $target) { throw "Refusing to reuse an existing feature directory: $target" }
New-Item -ItemType Directory -Path $WorktreeRoot -Force | Out-Null

& git clone $GitSource $target
if ($LASTEXITCODE -ne 0) { throw 'Git clone failed; the new directory was left untouched for inspection.' }
$branch = "codex/feature-$FeatureName"
& git -C $target checkout -b $branch
if ($LASTEXITCODE -ne 0) { throw "Unable to create feature branch $branch." }

& robocopy $WorkshopRoot $target /MIR /XD .git /R:1 /W:1 | Out-Host
if ($LASTEXITCODE -gt 7) { throw "Workshop snapshot copy failed with robocopy exit code $LASTEXITCODE." }

Write-Output "Created $target on $branch from the current Workshop snapshot (excluding .git)."
& git -C $target status --short
