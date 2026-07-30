param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$runtimes = @(
    (Join-Path $PSScriptRoot 'Test-GodSystemV422012PZRuntimeRuntime.lua'),
    (Join-Path $PSScriptRoot 'Test-GodSystemV422012ModularClientRuntime.lua')
)
$lua = Get-Command lua5.1 -ErrorAction SilentlyContinue
if (-not $lua) { $lua = Get-Command lua -ErrorAction Stop }
foreach ($runtime in $runtimes) {
    & $lua.Source $runtime $luaRoot
    if ($LASTEXITCODE -ne 0) { throw "PZ runtime adapter test failed: $runtime" }
}
Write-Output 'Test-GodSystemV422012PZRuntime passed'
