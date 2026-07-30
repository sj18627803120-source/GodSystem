param([string]$Root = "")
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$kernel = Join-Path $luaRoot 'shared\GodSystem\Runtime\Kernel.lua'
$test = Join-Path $PSScriptRoot 'Test-GodSystemV422012RuntimeKernelRuntime.lua'
foreach ($path in @($kernel, $test)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing runtime kernel file: $path" }
}
$lua = Get-Command lua -ErrorAction SilentlyContinue
if (-not $lua) {
    $fallback = Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $fallback) { $lua = Get-Item -LiteralPath $fallback }
}
if (-not $lua) { throw 'Lua 5.1 runtime required' }
$luaPath = if ($lua.Source) { $lua.Source } else { $lua.FullName }
& $luaPath $test $luaRoot
if ($LASTEXITCODE -ne 0) { throw 'Runtime kernel test failed' }
Write-Output 'Test-GodSystemV422012RuntimeKernel passed'
