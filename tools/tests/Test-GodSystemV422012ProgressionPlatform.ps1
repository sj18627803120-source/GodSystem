param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$platformRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua\shared\GodSystem\Platform\Progression'
$required = @{
    'UpgradesConfig.lua' = @('upgrades.config', 'quote')
    'UpgradesState.lua' = @('upgrades.state')
    'UpgradesAbilities.lua' = @('upgrades.abilities', 'snapshot', 'apply', 'restore')
    'UpgradesTasks.lua' = @('upgrades.tasks', 'addOpen', 'rollback')
    'UpgradesWallet.lua' = @('upgrades.wallet')
    'MedicalConfig.lua' = @('medical.config', 'cost')
    'MedicalState.lua' = @('medical.state')
    'MedicalBody.lua' = @('medical.body', 'inspect', 'snapshot', 'apply', 'restore')
    'MedicalWallet.lua' = @('medical.wallet')
    'HomeConfig.lua' = @('home.config', 'isEnabled', 'cost', 'maxTempSlots', 'safeLevel', 'nextSafeLevel')
    'HomeState.lua' = @('home.state')
    'HomePosition.lua' = @('home.position', 'blockedReason', 'current', 'validate', 'teleport', 'restore')
    'HomeWorld.lua' = @('home.world', 'planClear', 'executeClear')
    'HomeWallet.lua' = @('home.wallet')
}

$stateFactory = [IO.File]::ReadAllText((Join-Path $platformRoot 'StateFactory.lua'), [Text.Encoding]::UTF8)
foreach ($method in @('public.load', 'public.save')) {
    if ($stateFactory -notmatch [regex]::Escape($method)) { throw "State factory is missing $method" }
}
$walletFactory = [IO.File]::ReadAllText((Join-Path $platformRoot 'WalletFactory.lua'), [Text.Encoding]::UTF8)
foreach ($method in @('public.charge', 'public.refund', 'funds.debit', 'funds.restore')) {
    if ($walletFactory -notmatch [regex]::Escape($method)) { throw "Wallet factory is missing $method" }
}

$allText = ""
foreach ($entry in $required.GetEnumerator()) {
    $path = Join-Path $platformRoot $entry.Key
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing progression adapter: $($entry.Key)" }
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    $allText += $text
    foreach ($token in $entry.Value) {
        if ($text -notmatch [regex]::Escape($token)) {
            throw "Progression adapter '$($entry.Key)' is missing '$token'"
        }
    }
    if ($text -match 'require\s+"(?:GodSystem_Core|GodSystem_Server|GodSystem_UI|GodSystem_CarryCapacity|GodSystem_TerminalUpgrades|GodSystem_TerminalRelief)"') {
        throw "Progression adapter requires a legacy business implementation: $($entry.Key)"
    }
    if ($text -match '\b(?:Events|sendClientCommand|sendServerCommand|OnClientCommand|OnServerCommand)\b') {
        throw "Progression adapter bypasses the strict event/command boundary: $($entry.Key)"
    }
}

$abilitiesPath = Join-Path $platformRoot 'UpgradesAbilities.lua'
$abilities = [IO.File]::ReadAllText($abilitiesPath, [Text.Encoding]::UTF8)
foreach ($forbidden in @('findAutoRecycler', 'inventoryRows', 'collectInventory', 'getPlayer')) {
    if ($abilities -match [regex]::Escape($forbidden)) {
        throw "Terminal adapter contains forbidden player-inventory discovery: $forbidden"
    }
}
if ($abilities -match 'actor\s*[,:\.]\s*getInventory|actor:getInventory') {
    throw 'Terminal adapter scans the actor inventory'
}
if ($abilities -notmatch 'request\.terminal' -or $abilities -notmatch 'binding\.resolveTerminal') {
    throw 'Terminal adapter lacks explicit terminal resolution'
}
if ($allText -match '(?i)terminalCompression|originalCapacities|StorageController') {
    throw 'Retired compression/controller logic returned in progression adapters'
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for progression adapter validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV422012ProgressionPlatformRuntime.lua') `
    (Join-Path $Root 'Contents\mods\GodSystem\42\media\lua')
if ($LASTEXITCODE -ne 0) { throw 'Progression adapter runtime test failed' }

Write-Output 'Test-GodSystemV422012ProgressionPlatform passed'
