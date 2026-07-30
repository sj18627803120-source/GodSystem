param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Lua = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$modulePath = Join-Path $Lua 'shared\GodSystem\Features\AutoLoader\Module.lua'
$runtimeTest = Join-Path $PSScriptRoot 'Test-GodSystemV422012AutoLoaderModuleRuntime.lua'
$adapterRuntimeTest = Join-Path $PSScriptRoot 'Test-GodSystemV422012AutoLoaderModuleAdaptersRuntime.lua'
$adapterRoot = Join-Path $Lua 'shared\GodSystem\Platform\AutoLoader'
$adapterPaths = @(
    (Join-Path $adapterRoot 'Support.lua'),
    (Join-Path $adapterRoot 'AmmoCatalog.lua'),
    (Join-Path $adapterRoot 'InventoryQuery.lua'),
    (Join-Path $adapterRoot 'InventoryMutation.lua'),
    (Join-Path $adapterRoot 'Store.lua'),
    (Join-Path $adapterRoot 'Sessions.lua'),
    (Join-Path $adapterRoot 'Operations.lua'),
    (Join-Path $adapterRoot 'Synchronization.lua')
)

foreach ($path in @($modulePath, $runtimeTest, $adapterRuntimeTest) + $adapterPaths) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing auto-loader module test input: $path"
    }
}

$moduleText = [IO.File]::ReadAllText($modulePath, [Text.Encoding]::UTF8)
foreach ($dependency in @(
    'autoloader.inventory.query',
    'autoloader.inventory.mutation',
    'ammo.catalog',
    'autoloader.store',
    'autoloader.sessions',
    'autoloader.operations',
    'autoloader.synchronization',
    'notifications'
)) {
    if ($moduleText -notmatch [regex]::Escape('"' + $dependency + '"')) {
        throw "Auto-loader module does not declare dependency: $dependency"
    }
}

if ($moduleText -match 'require\s+"(?:GodSystem_AutoLoader|GodSystem_AutoLoaderClient|GodSystem_AutoLoaderServer|GodSystem_Core|GodSystem_Server|GodSystem_Network|GodSystem_UI)"') {
    throw 'Auto-loader feature depends on a legacy implementation or entry point'
}
if ($moduleText -match 'Events\.[A-Za-z0-9_]+\.(?:Add|Remove)|sendClientCommand|sendServerCommand|ModData\.|getPlayer\s*\(') {
    throw 'Auto-loader feature directly accesses a PZ runtime boundary'
}
foreach ($useCase in @(
    'startDeposit',
    'completeDepositBatch',
    'cancelDeposit',
    'withdraw',
    'manualFill',
    'postReload',
    'cleanupSessions'
)) {
    if ($moduleText -notmatch [regex]::Escape($useCase)) {
        throw "Auto-loader module is missing use case: $useCase"
    }
}
foreach ($constant in @(
    'defaultCapacity = 2000',
    'snapshotItems = 20000',
    'depositBatch = 500',
    'loaders = 64',
    'magazines = 256',
    'sessionLifetimeMs = 60000',
    'withdraw = 500'
)) {
    if ($moduleText -notmatch [regex]::Escape($constant)) {
        throw "Auto-loader module changed a current contract: $constant"
    }
}
if ($moduleText -notmatch 'isProtected' -or $moduleText -notmatch 'rollbackIncomplete') {
    throw 'Auto-loader protection or rollback contract is missing'
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for auto-loader module validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }

& $luaPath $runtimeTest $Lua
if ($LASTEXITCODE -ne 0) { throw 'Auto-loader module runtime test failed' }
& $luaPath $adapterRuntimeTest $Lua
if ($LASTEXITCODE -ne 0) { throw 'Auto-loader PZ adapter runtime test failed' }

$luacExe = Get-Command luac -ErrorAction SilentlyContinue
if (-not $luacExe) {
    $localLuac = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\luac.exe'
    if (Test-Path -LiteralPath $localLuac) { $luacExe = Get-Item -LiteralPath $localLuac }
}
if (-not $luacExe) { throw 'Lua 5.1 compiler is required for auto-loader module validation' }
$luacPath = if ($luacExe.Source) { $luacExe.Source } else { $luacExe.FullName }
& $luacPath -p $modulePath
if ($LASTEXITCODE -ne 0) { throw 'Auto-loader module Lua 5.1 compile failed' }
foreach ($path in $adapterPaths + @($adapterRuntimeTest)) {
    & $luacPath -p $path
    if ($LASTEXITCODE -ne 0) { throw "Auto-loader adapter Lua 5.1 compile failed: $path" }
}

Write-Output 'Test-GodSystemV422012AutoLoaderModule passed'
