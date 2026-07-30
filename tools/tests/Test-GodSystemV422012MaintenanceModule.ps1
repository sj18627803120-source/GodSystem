param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Lua = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$modulePath = Join-Path $Lua 'shared\GodSystem\Features\Maintenance\Module.lua'
$runtimeTest = Join-Path $PSScriptRoot 'Test-GodSystemV422012MaintenanceModuleRuntime.lua'

foreach ($path in @($modulePath, $runtimeTest)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing maintenance module test input: $path" }
}

$moduleText = [IO.File]::ReadAllText($modulePath, [Text.Encoding]::UTF8)
foreach ($dependency in @(
    'inventory.query',
    'inventory.mutation',
    'wallet',
    'maintenance.rules',
    'notifications'
)) {
    if ($moduleText -notmatch [regex]::Escape('"' + $dependency + '"')) {
        throw "Maintenance module does not declare dependency: $dependency"
    }
}

if ($moduleText -match 'require\s+"GodSystem_(Core|Server|Network|UI)"') {
    throw 'Maintenance feature depends on a legacy entry point'
}
if ($moduleText -match 'Events\.[A-Za-z0-9_]+\.(Add|Remove)|sendClientCommand|sendServerCommand|ModData\.') {
    throw 'Maintenance feature directly accesses a PZ runtime boundary'
}
foreach ($action in @('repairItem', 'enhanceDurability', 'repairVehicle')) {
    if ($moduleText -notmatch [regex]::Escape($action)) {
        throw "Maintenance module is missing action: $action"
    }
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for maintenance module validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }

& $luaPath $runtimeTest $Lua
if ($LASTEXITCODE -ne 0) { throw 'Maintenance module runtime test failed' }

$luacExe = Get-Command luac -ErrorAction SilentlyContinue
if (-not $luacExe) {
    $localLuac = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\luac.exe'
    if (Test-Path -LiteralPath $localLuac) { $luacExe = Get-Item -LiteralPath $localLuac }
}
if ($luacExe) {
    $luacPath = if ($luacExe.Source) { $luacExe.Source } else { $luacExe.FullName }
    & $luacPath -p $modulePath
    if ($LASTEXITCODE -ne 0) { throw 'Maintenance module Lua 5.1 compile failed' }
}

Write-Output 'Test-GodSystemV422012MaintenanceModule passed'
