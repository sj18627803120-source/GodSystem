param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Lua = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$maintenancePath = Join-Path $Lua 'shared\GodSystem_Maintenance.lua'
$maintenance = [System.IO.File]::ReadAllText($maintenancePath, [System.Text.Encoding]::UTF8)

if ($maintenance -notmatch 'after\.damaged\s*<\s*before\.damaged') {
    throw 'Vehicle repair must accept measurable repair progress when an invalid MOD part remains'
}
if ($maintenance -notmatch 'after\.damaged\s*>\s*0[\s\S]{0,500}VehicleRepairFailed') {
    throw 'Vehicle repair must still reject a call that makes no measurable progress'
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = Join-Path $env:USERPROFILE 'Tools\Lua51\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if ($luaExe) {
    $luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
    & $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11663VehicleRepairRuntime.lua') (Join-Path $Lua 'shared')
    if ($LASTEXITCODE -ne 0) { throw 'v1.16.63 vehicle repair runtime test failed' }
}
else {
    Write-Warning 'Lua executable was not found; vehicle repair runtime validation was skipped.'
}

Write-Output 'Test-GodSystemV11663VehicleRepair passed'
