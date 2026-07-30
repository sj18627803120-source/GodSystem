$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$luaRoot = Join-Path $root 'Contents\mods\GodSystem\42\media\lua'
$runtime = Join-Path $PSScriptRoot 'Test-GodSystemV422012UseCaseDispatcherRuntime.lua'
$lua = Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\lua.exe'

if (-not (Test-Path -LiteralPath $lua)) {
    throw "Lua 5.1 runtime not found: $lua"
}

& $lua $runtime $luaRoot
if ($LASTEXITCODE -ne 0) {
    throw 'Use-case dispatcher runtime test failed'
}

$protocol = Get-Content -LiteralPath (Join-Path $luaRoot 'shared\GodSystem\Runtime\Protocol422012.lua') -Raw
$dispatcher = Get-Content -LiteralPath (Join-Path $luaRoot 'shared\GodSystem\Runtime\UseCaseDispatcher.lua') -Raw

if ($protocol -notmatch 'Protocol\.Version\s*=\s*"42\.20\.1\.2"') {
    throw 'Protocol version is not exact'
}
if ($dispatcher -match '\b(?:Events|sendClientCommand|sendServerCommand|ModData|getPlayer|getCell)\b') {
    throw 'Use-case dispatcher crossed the platform boundary'
}
if ($dispatcher -notmatch 'protocolMismatch' -or $dispatcher -notmatch 'moduleUnavailable') {
    throw 'Dispatcher boundary failures are not explicit'
}

Write-Output 'Test-GodSystemV422012UseCaseDispatcher passed'
