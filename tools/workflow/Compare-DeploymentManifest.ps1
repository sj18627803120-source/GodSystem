[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Deployment,
    [switch]$FailOnDifference
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Directory([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label does not exist or is not a directory: $Path"
    }
    return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path).TrimEnd('\')
}

function Get-Manifest([string]$Root) {
    $rows = @{}
    Get-ChildItem -LiteralPath $Root -Recurse -Force -File |
        Where-Object {
            $relative = $_.FullName.Substring($Root.Length).TrimStart('\')
            $relative -notmatch '(^|\\)\.git(\\|$)'
        } |
        ForEach-Object {
            $relative = $_.FullName.Substring($Root.Length).TrimStart('\')
            $rows[$relative] = [pscustomobject]@{
                Length = $_.Length
                Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        }
    return $rows
}

$sourceRoot = Resolve-Directory $Source 'Source'
$deploymentRoot = Resolve-Directory $Deployment 'Deployment'
if ($sourceRoot -ieq $deploymentRoot) { throw 'Source and deployment must be different directories.' }

$sourceManifest = Get-Manifest $sourceRoot
$deploymentManifest = Get-Manifest $deploymentRoot
$paths = @($sourceManifest.Keys + $deploymentManifest.Keys | Sort-Object -Unique)
$differences = @()

foreach ($path in $paths) {
    $left = $sourceManifest[$path]
    $right = $deploymentManifest[$path]
    if ($null -eq $left) {
        $differences += [pscustomobject]@{ Path = $path; Status = 'OnlyInDeployment' }
    }
    elseif ($null -eq $right) {
        $differences += [pscustomobject]@{ Path = $path; Status = 'OnlyInSource' }
    }
    elseif ($left.Length -ne $right.Length -or $left.Sha256 -ne $right.Sha256) {
        $differences += [pscustomobject]@{ Path = $path; Status = 'ContentDiffers' }
    }
}

if ($differences.Count -eq 0) {
    Write-Output "Deployment manifest matches: $($sourceManifest.Count) files."
    exit 0
}

$differences | Format-Table -AutoSize | Out-Host
Write-Output "Deployment manifest differs in $($differences.Count) path(s)."
if ($FailOnDifference) { throw 'Deployment manifest comparison failed.' }
