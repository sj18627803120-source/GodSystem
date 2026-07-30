param([string]$Root = "")
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$runner = Join-Path $luaRoot 'shared\GodSystem\State\MigrationRunner.lua'
$test = Join-Path $PSScriptRoot 'Test-GodSystemV422012MigrationRunnerRuntime.lua'
foreach ($path in @($runner, $test)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing migration runner file: $path" }
}
$lua = Get-Command lua -ErrorAction SilentlyContinue
if (-not $lua) {
    $fallback = Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $fallback) { $lua = Get-Item -LiteralPath $fallback }
}
if (-not $lua) { throw 'Lua 5.1 runtime required' }
$luaPath = if ($lua.Source) { $lua.Source } else { $lua.FullName }
& $luaPath $test $luaRoot
if ($LASTEXITCODE -ne 0) { throw 'Migration runner runtime test failed' }
Write-Output 'Test-GodSystemV422012MigrationRunner passed'
