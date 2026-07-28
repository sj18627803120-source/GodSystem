param(
    [string]$Root = "",
    [string]$ExpectedVersion = "1.16.71",
    [switch]$AllowStorageRoutingV11673
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Media = Join-Path $Mod '42\media'
$Lua = Join-Path $Media 'lua'

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}
function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}
function Reject-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw $Message }
}

$storage = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Storage.lua')
$manager = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_StorageManager.lua')
$server = Read-Utf8 (Join-Path $Lua 'server\GodSystem_StorageServer.lua')
$client = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageClient.lua')
$context = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageContext.lua')
$storageUi = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageUI.lua')
$mainUi = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$config = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Config.lua')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$fallback = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Localization_Override.lua')
$cn = Read-Utf8 (Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt')
$ch = Read-Utf8 (Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt')

$version = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $version + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $version + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $version + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + $version + '\r?$') "Workshop version must be $ExpectedVersion"

Reject-Text $manager 'collectSafeDepositItems|args\.safeAll' 'The recursive safeAll deposit route must be removed'
Reject-Text $server 'args\s+and\s+args\.safeAll' 'The operation fingerprint must not retain safeAll'
Reject-Text $client 'safeAll\s*=' 'The client must not send safeAll'
Require-Text $manager 'mode\s*~=\s*"selected"\s+and\s+mode\s*~=\s*"sourceAll"' 'selected/sourceAll deposit mode validation is missing'
Require-Text $manager 'args\.sourceItemId' 'Deposit source identity validation is missing'
Require-Text $manager 'args\.requests' 'Multi-request withdraw protocol is missing'
Require-Text $storage 'objectId\s*=\s*link\.objectId' 'Container summaries must include objectId'
Require-Text $storage 'isCoreHost\s*=' 'Container summaries must identify core-host slots'
Require-Text $context 'setHighlightColor' 'Context-menu furniture highlighting is missing'
Require-Text $context 'onHighlightParams' 'Context-menu hover highlighting is missing'
Require-Text $context 'connectedObjectIds' 'Marker colors must use current connectivity state'
Require-Text $context 'markerHorizontalSlot' 'Compact same-square marker positioning is missing'
Require-Text $context 'markerChevronCount' 'Low/middle/high chevron markers are missing'
Require-Text $context 'candidateLevelLabel' 'Context-menu level labels are missing'
Reject-Text $context 'DrawStringCentre' 'Compact connection markers must not draw overlapping numeric labels'
Reject-Text $client 'if\s+payload\s+and\s+GodSystemStorageUI\s+and\s+GodSystemStorageUI\.onOperationResult' 'SP failures without payload must still reach equipment restoration'
Require-Text $client 'pcall\(GodSystemStorageUI\.onOperationResult' 'UI result failures must not block SP storage refresh'
Require-Text $client 'networkSummaryForPlayer' 'Container marking must refresh connectivity without an open storage window'
Require-Text $manager 'function\s+Manager\.networkSummaryForPlayer' 'Current-network summary helper is missing'
Require-Text $client 'function\s+Client\.hasPendingOperation' 'The UI needs a stable pending-operation guard'
Require-Text $storageUi 'sourceList' 'The character inventory source list is missing'
Require-Text $storageUi 'inventoryList' 'The character inventory item list is missing'
Require-Text $storageUi 'warehouseList' 'The network warehouse list is missing'
Require-Text $storageUi 'selectedInventoryKeys' 'Stable character multi-selection is missing'
Require-Text $storageUi 'selectedWarehouseKeys' 'Stable warehouse multi-selection is missing'
Require-Text $storageUi 'ISUnequipAction' 'Manual equipped-item deposit must queue native unequip actions'
Require-Text $storageUi 'ISWaitWhileGettingUp' 'Equipped-item deposit completion barrier is missing'
Require-Text $storageUi 'item\s+and\s+not\s+Storage\.isEquippedItem\(player,\s*item\)' 'Deposit must revalidate that queued equipment was actually unequipped'
Require-Text $storageUi 'hasPendingOperation\("deposit"\)' 'Deposit UI must not overwrite pending equipment recovery state'
Require-Text $storageUi 'selectedLinkId' 'Container management selection identity is missing'
Require-Text $storageUi 'warehouseRowSelected' 'Container management selected-row rendering is missing'
Reject-Text $storageUi 'exactButton' 'The duplicate exact-withdraw button must be removed'
Require-Text $storageUi 'selectedInstanceId[\s\S]{0,500}withdrawRequests' 'The main withdraw action must support a selected exact instance'
Require-Text $storageUi 'isMultiplayerSession' 'SP must hide the administrator take-over control'
Require-Text $storageUi 'sourceDisplayLabel' 'Warehouse source filters must use short container labels'
Reject-Text $storageUi 'Storage_DepositAll",\s*"Safe deposit all"' 'The old safe-deposit-all control remains'

foreach ($key in @(
    'Storage_InventorySource',
    'Storage_InventoryCarried',
    'Storage_InventoryEquipped',
    'Storage_Warehouse',
    'Storage_DepositSelected',
    'Storage_DepositSourceAll',
    'Storage_WithdrawSelected',
    'Storage_Context_DepositOne',
    'Storage_Context_DepositHalf',
    'Storage_Context_DepositAll',
    'Storage_Context_WithdrawOne',
    'Storage_Context_WithdrawHalf',
    'Storage_Context_WithdrawAll',
    'Storage_Context_DepositSelectedAll',
    'Storage_Context_WithdrawSelectedAll',
    'Storage_CoreHost',
    'Storage_Level_Low',
    'Storage_Level_Middle',
    'Storage_Level_High'
)) {
    Require-Text $localization ('(?m)^' + [regex]::Escape($key) + ':') "Localization key is missing: $key"
    Require-Text $fallback ('GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]') "Lua fallback key is missing: $key"
    Require-Text $cn ('IGUI_GodSystem_' + [regex]::Escape($key)) "CN translation key is missing: $key"
    Require-Text $ch ('IGUI_GodSystem_' + [regex]::Escape($key)) "CH translation key is missing: $key"
}
Reject-Text $localization 'Storage_DepositAll:\s*"安全存入全部"' 'The old safe-deposit label must be removed'
Reject-Text $localization '全部储物格清空|锁定为 0|容量锁定为 0' 'Core-host instructions still describe the retired capacity lock'
Reject-Text $mainUi 'Empty one marked furniture completely|storage slots are locked' 'The storage-page fallback still describes the retired host behavior'

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for v1.16.71 storage validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11671Runtime.lua') $Lua $(if ($AllowStorageRoutingV11673) { 'v11673' } else { 'v11671' })
if ($LASTEXITCODE -ne 0) { throw 'v1.16.71 runtime test failed' }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11671ContextRuntime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'v1.16.71 context runtime test failed' }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11671ServerRuntime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'v1.16.71 server runtime test failed' }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11671ClientRuntime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'v1.16.71 client runtime test failed' }

Write-Output 'Test-GodSystemV11671 passed'
