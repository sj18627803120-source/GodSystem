param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$runtime = Join-Path $PSScriptRoot 'Test-GodSystemV422012RuntimeModeRuntime.lua'
$lua = Get-Command lua5.1 -ErrorAction SilentlyContinue
if (-not $lua) { $lua = Get-Command lua -ErrorAction Stop }
& $lua.Source $runtime $luaRoot
if ($LASTEXITCODE -ne 0) { throw 'Runtime mode Lua test failed' }

$guarded = @(
    'client\GodSystem_Core.lua',
    'client\GodSystem_Companion.lua',
    'client\GodSystem_Network.lua',
    'client\GodSystem_AutoLoaderClient.lua',
    'client\GodSystem_StorageClient.lua',
    'server\GodSystem_Server.lua',
    'server\GodSystem_AutoLoaderServer.lua',
    'server\GodSystem_StorageServer.lua',
    'server\GodSystem_SPVehicleRepair.lua'
)
foreach ($relative in $guarded) {
    $path = Join-Path $luaRoot $relative
    $source = Get-Content -LiteralPath $path -Raw
    if ($source -notmatch 'require "GodSystem_RuntimeMode"') {
        throw "Runtime mode import missing: $relative"
    }
    if ($source -notmatch 'legacyBusinessEnabled') {
        throw "Legacy runtime registration guard missing: $relative"
    }
}
Write-Output 'Test-GodSystemV422012RuntimeMode passed'
