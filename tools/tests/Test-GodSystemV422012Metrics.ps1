param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$files = @(
    (Join-Path $luaRoot 'shared\GodSystem\Platform\WalletAccounts.lua'),
    (Join-Path $luaRoot 'shared\GodSystem\Platform\Metrics.lua'),
    (Join-Path $PSScriptRoot 'Test-GodSystemV422012MetricsRuntime.lua')
)
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file)) { throw "Missing metrics file: $file" }
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for metrics validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath $files[2] $luaRoot
if ($LASTEXITCODE -ne 0) { throw 'Metrics runtime test failed' }

$luac = Get-Command luac -ErrorAction SilentlyContinue
if (-not $luac) {
    $localLuac = Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\luac.exe'
    if (Test-Path -LiteralPath $localLuac) { $luac = Get-Item -LiteralPath $localLuac }
}
if (-not $luac) { throw 'Lua 5.1 compiler is required for metrics validation' }
$luacPath = if ($luac.Source) { $luac.Source } else { $luac.FullName }
foreach ($file in $files) {
    & $luacPath -p $file
    if ($LASTEXITCODE -ne 0) { throw "Metrics Lua 5.1 compile failed: $file" }
}

Write-Output 'Test-GodSystemV422012Metrics passed'
