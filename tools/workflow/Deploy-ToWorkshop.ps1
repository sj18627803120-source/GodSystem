[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$WorkshopRoot = 'C:\Users\Admin\Zomboid\Workshop\GodSystem',
    [switch]$ConfirmDeployment,
    [switch]$AllowDestinationChanges
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfirmDeployment) { throw 'Pass -ConfirmDeployment only after automated tests pass.' }
if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Source is missing: $Source" }
if (-not (Test-Path -LiteralPath $WorkshopRoot -PathType Container)) { throw "Workshop root is missing: $WorkshopRoot" }
$sourceRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Source).Path).TrimEnd('\')
$workshopRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $WorkshopRoot).Path).TrimEnd('\')
if ($sourceRoot -ieq $workshopRoot) { throw 'Source and Workshop must be different directories.' }

$workshopGit = Join-Path $workshopRoot '.git'
if ((Test-Path -LiteralPath $workshopGit -PathType Container) -and -not $AllowDestinationChanges) {
    $pending = @(& git -C $workshopRoot status --porcelain)
    if ($pending.Count -gt 0) {
        throw 'Workshop has unconfirmed Git changes. First absorb them with Start-FeatureFromWorkshop, or explicitly pass -AllowDestinationChanges.'
    }
}

& robocopy $sourceRoot $workshopRoot /MIR /XD .git /R:1 /W:1 | Out-Host
if ($LASTEXITCODE -gt 7) { throw "Workshop deployment failed with robocopy exit code $LASTEXITCODE." }

$compare = Join-Path $PSScriptRoot 'Compare-DeploymentManifest.ps1'
& $compare -Source $sourceRoot -Deployment $workshopRoot -FailOnDifference
Write-Output 'Workshop deployment completed and manifest verified (excluding .git).'
