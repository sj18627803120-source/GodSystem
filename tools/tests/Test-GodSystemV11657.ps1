param(
    [string]$Root = "",
    [string]$ExpectedVersion = "1.16.57",
    [switch]$SkipRuntime
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Lua = Join-Path $Mod '42\media\lua'

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Reject-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw $Message }
}

$config = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Config.lua')
$carry = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_CarryCapacity.lua')
$core = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Core.lua')
$ui = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$network = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Network.lua')
$context = Read-Utf8 (Join-Path $Lua 'client\GodSystem_RecycleContext.lua')
$protocol = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Protocol.lua')
$server = Read-Utf8 (Join-Path $Lua 'server\GodSystem_Server.lua')
$transactions = Read-Utf8 (Join-Path $Lua 'server\GodSystem_TransactionOps.lua')
$terminal = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_TerminalUpgrades.lua')
$variants = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_ShopVariants.lua')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$fallback = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Localization_Override.lua')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

$versionPattern = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $versionPattern + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $versionPattern + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $versionPattern + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + $versionPattern + '\r?$') "Workshop metadata must mention v$ExpectedVersion"

Require-Text $config 'CarryCapacityPerLevel\s*=\s*2' 'Carry bonus per level must be 2'
Require-Text $config 'CarryCapacityBaseCost\s*=\s*2000' 'Carry base cost must be 2000'
Require-Text $config 'CarryCapacityCostMultiplier\s*=\s*1\.5' 'Carry price multiplier must be 1.5'
Require-Text $carry 'math\.ceil\(raw\)' 'Carry price must round upward'
Require-Text $carry 'SAFE_INTEGER\s*=\s*9007199254740991' 'Carry calculations need a safe-integer guard'
Require-Text $carry 'getMaxWeightDelta' 'Carry bonus must read the additive delta'
Require-Text $carry 'setMaxWeightDelta' 'Carry bonus must write the additive delta'
Require-Text $carry 'getMaxWeightBase' 'Carry bonus must convert carry units using the player base'
Require-Text $carry 'desiredBonus\s*/\s*maxWeightBase' 'Carry units must be converted to the native multiplier'
Require-Text $carry 'verificationFailed' 'Carry writes must verify the final capacity'
Reject-Text $carry 'setMaxWeightBase' 'Carry bonus must not overwrite base carry capacity'
Require-Text $carry 'externalDelta\s*=\s*current\s*-\s*previous' 'Carry refresh must remove its previous contribution before applying'

Require-Text $core 'carryCapacityLevel' 'SP data must persist the carry level'
Require-Text $server 'carryCapacityLevel' 'MP data must persist the carry level'
Require-Text $core 'Events\.OnCreatePlayer\.Add\(GodSystem\.onCreatePlayer\)' 'SP respawn must reapply carry capacity'
Require-Text $server 'Commands\.refreshCarryCapacity' 'MP refresh command is missing'
Require-Text $server 'Commands\.hello[\s\S]*GodSystemCarryCapacity\.apply' 'MP hello must restore carry capacity'
Require-Text $network 'pcall\(GodSystem\.applyCarryCapacity, player\(\), args\.data\)' 'MP state must apply the local carry display/runtime bonus'
Require-Text $protocol 'RefreshCarryCapacity\s*=\s*"refreshCarryCapacity"' 'Carry refresh protocol command is missing'
Require-Text $protocol 'StateCommands\s*=\s*\{[\s\S]*refreshCarryCapacity\s*=\s*true' 'Carry refresh must wait for authoritative state'
Require-Text $protocol 'KeyCommands\s*=\s*\{[\s\S]*refreshCarryCapacity\s*=\s*true' 'Carry refresh must use the key-command mutex'
Require-Text $ui '"activeTasks",\s*"dailyTasks",\s*"carryCapacity"' 'Carry capacity must appear in system upgrades'
Require-Text $ui 'Btn_RefreshCarryCapacity' 'Carry refresh button is missing'
Require-Text $ui 'Upgrade_CarryBase' 'Carry base display is missing'
Require-Text $ui 'Upgrade_CarryBonus' 'Carry bonus display is missing'
Require-Text $ui 'Upgrade_CarryTotal' 'Carry total display is missing'

Require-Text $context 'classifyItems' 'Context menu must classify mixed selections'
Require-Text $context 'classification\.eligible' 'Context menu must retain eligible items'
Require-Text $context 'skippedCount' 'Context menu must report skipped items'
Reject-Text $context 'disabledReason\(' 'Legacy all-or-nothing context validation must be removed'
Require-Text $core 'if not eligible then[\s\S]*skipped\s*=\s*skipped\s*\+\s*1' 'SP selected recycle must skip ineligible items'
Require-Text $server 'if not eligible then[\s\S]*skipped\s*=\s*skipped\s*\+\s*1' 'MP selected recycle must skip ineligible items'
Require-Text $server 'RecycleSelectionContainerChanged' 'Container signature changes must still cancel the transaction'
Require-Text $server 'restoreRecycleSelection' 'MP removal failure must still restore selected items'
Require-Text $core 'refundCurrencySources\(fromBank, fromCash\)' 'SP list-only rollback must restore original payment sources'
Require-Text $server 'refundCurrencySources\(player, data, fromBank, fromCash\)' 'MP list-only rollback must restore original payment sources'

Require-Text $network 'timedOutTransactionOperation' 'Client must retain timed-out carry/recycle operations'
Require-Text $network 'transactionFingerprint' 'Client must bind operation IDs to request fingerprints'
Require-Text $network 'if command == upgradeCommand then' 'Every system upgrade type must receive a transaction operation ID'
Require-Text $transactions 'status\s*=\s*"processing"' 'Server transaction cache must persist processing operations'
Require-Text $transactions 'status\s*=\s*"unknown"' 'Server transaction cache must quarantine interrupted operations'
Require-Text $transactions 'while bucket and #bucket\.order > MAX_RESULTS' 'Server transaction cache must stay bounded'
Require-Text $server 'GodSystemTransactionOps\.remember' 'Carry/recycle results must be cached'
Require-Text $server 'local persisted, persistError = transmitStore\(\)' 'Transaction processing state must be persisted before economic mutation'
Reject-Text $server 'function Commands\.upgradeSystem[\s\S]*finish\(player, true, "系统升级成功"\)' 'Legacy system upgrades must use the cached transaction result path'

foreach ($name in @('TerminalCapacityLevels', 'TerminalReductionLevels', 'TerminalCompressionLevels')) {
    Require-Text $config ("GodSystemConfig\." + $name + '\s*=\s*\{') ("Missing terminal level table: " + $name)
}
foreach ($value in @(10,15,20,25,30,35,42,49)) { Require-Text $config ("value\s*=\s*" + $value + '(?:\D|$)') ("Missing terminal capacity value: " + $value) }
Require-Text $config '(?s)TerminalCapacityLevels\s*=\s*\{.*?value\s*=\s*10,\s*upgradeCost\s*=\s*0.*?value\s*=\s*15,\s*upgradeCost\s*=\s*60.*?value\s*=\s*20,\s*upgradeCost\s*=\s*120.*?value\s*=\s*49,\s*upgradeCost\s*=\s*1100' 'Terminal capacity values/costs do not match the approved table'
Require-Text $config '(?s)TerminalReductionLevels\s*=\s*\{.*?value\s*=\s*50,\s*upgradeCost\s*=\s*0.*?value\s*=\s*55,\s*upgradeCost\s*=\s*100.*?value\s*=\s*90,\s*upgradeCost\s*=\s*1700.*?value\s*=\s*99,\s*upgradeCost\s*=\s*2500' 'Terminal reduction values/costs do not match the approved table'
Require-Text $config '(?s)TerminalCompressionLevels\s*=\s*\{.*?value\s*=\s*0,\s*upgradeCost\s*=\s*0.*?value\s*=\s*15,\s*upgradeCost\s*=\s*500.*?value\s*=\s*85,\s*upgradeCost\s*=\s*8000.*?value\s*=\s*90,\s*upgradeCost\s*=\s*12000' 'Terminal compression values/costs do not match the approved table'
Require-Text $terminal 'writeNumberMethod\(inventory,\s*"setWeightReduction",\s*"getWeightReduction",\s*reduction\)' 'Terminal reduction must use the child ItemContainer API'
Require-Text $terminal 'setActualWeight' 'Compression must update item instances'
Require-Text $terminal 'setCustomWeight' 'Compression must mark instance custom weight'
Reject-Text $terminal 'ScriptItem' 'Compression must not edit shared ScriptItem weights'
Require-Text $terminal 'MAX_DEPTH\s*=\s*32' 'Nested compression must be depth-bounded'
Require-Text $terminal 'BATCH_SIZE\s*=\s*32' 'Compression work must use fixed-size batches'
Require-Text $terminal 'MIN_WEIGHT\s*=\s*0\.01' 'Compression must enforce a positive minimum weight'
Require-Text $terminal 'BASE_WEIGHT_KEY' 'Compression must persist original instance weight'
Require-Text $terminal 'restoreSnapshot' 'Terminal upgrades need rollback snapshots'
Require-Text $server 'terminalCapacity\s*=\s*"capacity"' 'MP capacity upgrade route missing'
Require-Text $server 'terminalReduction\s*=\s*"reduction"' 'MP reduction upgrade route missing'
Require-Text $server 'terminalCompression\s*=\s*"compression"' 'MP compression upgrade route missing'
Require-Text $core 'isClient\s+and\s+isClient\(\)\s+then\s+return true' 'MP clients must not write authoritative terminal weights'
Require-Text $ui 'Btn_UpgradeTerminalCapacity' 'Capacity button missing'
Require-Text $ui 'Btn_UpgradeTerminalReduction' 'Reduction button missing'
Require-Text $ui 'Btn_UpgradeTerminalCompression' 'Compression button missing'
Require-Text $variants 'getWorldSprite' 'Furniture variants must capture world sprites'
Require-Text $variants 'ReadFromWorldSprite' 'Furniture purchases must restore the saved world sprite'
Require-Text $variants 'InventoryItemFactory\.CreateItem' 'Furniture purchases must create an exact Moveable instance'
Require-Text $server 'GodSystemShopVariants\.getKey\(fullType, item\)' 'MP listing must distinguish furniture variants'
Require-Text $core 'GodSystemShopVariants\.getKey\(fullType, item\)' 'SP listing must distinguish furniture variants'
$taskTitle = -join @([char]0x533A, [char]0x57DF, [char]0x8C03, [char]0x67E5)
$oldTaskTitle = -join @([char]0x533A, [char]0x57DF, [char]0x8E0F, [char]0x67E5)
Require-Text $config ('title\s*=\s*"' + [regex]::Escape($taskTitle) + '"') 'Task title typo must be fixed in config'
Reject-Text ($config + $localization + $fallback) ([regex]::Escape($oldTaskTitle)) 'Old task title typo must be removed'

foreach ($key in @(
    'Upgrade_CarryCapacity',
    'Btn_RefreshCarryCapacity',
    'NotifyMP_CarryCapacityUpgraded',
    'NotifyMP_SystemUpgradeSuccess',
    'Context_EligibleSummary',
    'Notify_RecycleSelectionSuccessPartial',
    'NotifyMP_RecycleSelectionSuccessPartial',
    'NotifyMP_TransactionOperationUnknown'
    'Btn_UpgradeTerminalCapacity'
    'Btn_UpgradeTerminalReduction'
    'Btn_UpgradeTerminalCompression'
    'Terminal_Compressing'
    'Task_move_1500_Title'
)) {
    Require-Text $localization ("(?m)^" + [regex]::Escape($key) + ':') ("Localization source missing key: " + $key)
    Require-Text $fallback ('GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]') ("Lua fallback missing key: " + $key)
}

$expectedCosts = @(2000, 3000, 4500, 6750, 10125, 15188, 22782)
for ($level = 0; $level -lt $expectedCosts.Count; $level++) {
    $actual = [math]::Ceiling(2000 * [math]::Pow(1.5, $level))
    if ($actual -ne $expectedCosts[$level]) { throw "Unexpected carry cost at level ${level}: $actual" }
}

if (-not $SkipRuntime) {
    $luaExe = Get-Command lua -ErrorAction SilentlyContinue
    if (-not $luaExe) {
        $localLua = Join-Path $env:USERPROFILE 'Tools\Lua51\lua.exe'
        if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
    }
    if ($luaExe) {
        $luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
        & $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11657Runtime.lua') (Join-Path $Lua 'shared\GodSystem_CarryCapacity.lua')
        if ($LASTEXITCODE -ne 0) { throw 'v1.16.57 carry runtime test failed' }
        & $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11657TerminalRuntime.lua') (Join-Path $Lua 'shared\GodSystem_TerminalUpgrades.lua')
        if ($LASTEXITCODE -ne 0) { throw 'v1.16.57 terminal runtime test failed' }
        & $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11657ShopVariantRuntime.lua') (Join-Path $Lua 'shared\GodSystem_ShopVariants.lua')
        if ($LASTEXITCODE -ne 0) { throw 'v1.16.57 shop variant runtime test failed' }
    }
    else {
        Write-Warning 'Lua executable was not found; v1.16.57 runtime validation was skipped.'
    }
}

Write-Output 'Test-GodSystemV11657 passed'
