param([string]$Root = "")
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$module = Join-Path $luaRoot 'shared\GodSystem\Features\System\Module.lua'
if (-not (Test-Path -LiteralPath $module)) { throw 'System module missing' }
$text = [IO.File]::ReadAllText($module, [Text.Encoding]::UTF8)
if ($text -match '\b(?:Events|sendClientCommand|sendServerCommand|ModData|getPlayer|getCell)\b') {
    throw 'System module crossed the platform boundary'
}
foreach ($contract in @('ensureInitialized', 'setPreference', 'history', 'pendingCurrencyGrant')) {
    if ($text -notmatch $contract) { throw "System contract missing: $contract" }
}
$lua = Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\lua.exe'
if (-not (Test-Path -LiteralPath $lua)) { throw "Lua 5.1 runtime missing: $lua" }
& $lua (Join-Path $PSScriptRoot 'Test-GodSystemV422012SystemModuleRuntime.lua') $luaRoot
if ($LASTEXITCODE -ne 0) { throw 'System module runtime test failed' }
Write-Output 'Test-GodSystemV422012SystemModule passed'
