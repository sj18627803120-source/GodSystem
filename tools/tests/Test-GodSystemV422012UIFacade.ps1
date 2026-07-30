param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$runtime = Join-Path $PSScriptRoot 'Test-GodSystemV422012UIFacadeRuntime.lua'
$lua = Get-Command lua5.1 -ErrorAction SilentlyContinue
if (-not $lua) { $lua = Get-Command lua -ErrorAction Stop }
& $lua.Source $runtime $luaRoot
if ($LASTEXITCODE -ne 0) { throw 'UI facade runtime test failed' }
Write-Output 'Test-GodSystemV422012UIFacade passed'
