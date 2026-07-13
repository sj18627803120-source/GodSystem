$ErrorActionPreference = 'Stop'

$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Media = Join-Path $Mod '42\media'
$Lua = Join-Path $Media 'lua'

$ConfigPath = Join-Path $Lua 'shared\GodSystem_Config.lua'
$ProtocolPath = Join-Path $Lua 'shared\GodSystem_Protocol.lua'
$PricesPath = Join-Path $Lua 'shared\GodSystem_Prices.lua'
$ItemsPath = Join-Path $Media 'scripts\GodSystem_Items.txt'
$SharedMaintenancePath = Join-Path $Lua 'shared\GodSystem_Maintenance.lua'
$ClientPath = Join-Path $Lua 'client\GodSystem_MaintenanceContext.lua'
$CorePath = Join-Path $Lua 'client\GodSystem_Core.lua'
$NetworkPath = Join-Path $Lua 'client\GodSystem_Network.lua'
$ServerPath = Join-Path $Lua 'server\GodSystem_Server.lua'
$OverridePath = Join-Path $Lua 'shared\GodSystem_Localization_Override.lua'
$CnUiPath = Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt'
$ChUiPath = Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt'
$CnItemsPath = Join-Path $Lua 'shared\Translate\CN\Items_CN.txt'
$ChItemsPath = Join-Path $Lua 'shared\Translate\CH\Items_CH.txt'
$CnItemJsonPath = Join-Path $Lua 'shared\Translate\CN\ItemName.json'
$ChItemJsonPath = Join-Path $Lua 'shared\Translate\CH\ItemName.json'
$CnTooltipJsonPath = Join-Path $Lua 'shared\Translate\CN\Tooltip.json'
$ChTooltipJsonPath = Join-Path $Lua 'shared\Translate\CH\Tooltip.json'
$RepairIconPath = Join-Path $Media 'textures\Item_SystemRepairKit.png'
$CoreIconPath = Join-Path $Media 'textures\Item_DurabilityCore.png'

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}

$config = Read-Utf8 $ConfigPath
$protocol = Read-Utf8 $ProtocolPath
$prices = Read-Utf8 $PricesPath
$items = Read-Utf8 $ItemsPath
$network = Read-Utf8 $NetworkPath
$core = Read-Utf8 $CorePath
$server = Read-Utf8 $ServerPath
$maintenance = Read-Utf8 $SharedMaintenancePath
$override = Read-Utf8 $OverridePath
$cnUi = Read-Utf8 $CnUiPath
$chUi = Read-Utf8 $ChUiPath
$cnItems = Read-Utf8 $CnItemsPath
$chItems = Read-Utf8 $ChItemsPath
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.47"' 'Config version must be 1.16.47'
Require-Text $rootInfo '(?m)^modversion=1\.16\.47$' 'Root mod.info version must be 1.16.47'
Require-Text $b42Info '(?m)^modversion=1\.16\.47$' 'B42 mod.info version must be 1.16.47'
Require-Text $workshop '(?m)^description=v1\.16\.47$' 'Workshop metadata must mention v1.16.47'

Require-Text $items '(?s)item\s+SystemRepairKit\s*\{.*?Icon\s*=\s*SystemRepairKit' 'SystemRepairKit item definition missing'
Require-Text $items '(?s)item\s+DurabilityCore\s*\{.*?Icon\s*=\s*DurabilityCore' 'DurabilityCore item definition missing'
Require-Text $items 'Tooltip\s*=\s*Tooltip_GodSystem_SystemRepairKit' 'Repair item tooltip key missing'
Require-Text $items 'Tooltip\s*=\s*Tooltip_GodSystem_DurabilityCore' 'Core item tooltip key missing'

Require-Text $config '(?s)id\s*=\s*"system_repair_kit".*?price\s*=\s*300.*?GodSystem\.SystemRepairKit' 'Repair kit must be an initial 300-coin shop item'
Require-Text $config '(?s)id\s*=\s*"durability_core".*?price\s*=\s*1200.*?GodSystem\.DurabilityCore' 'Durability core must be an initial 1200-coin shop item'
Require-Text $prices '\["GodSystem\.SystemRepairKit"\]\s*=\s*300' 'Repair kit effective buy price must be 300'
Require-Text $prices '\["GodSystem\.DurabilityCore"\]\s*=\s*1200' 'Durability core effective buy price must be 1200'
Require-Text $config '(?s)AutoShopBlacklist\s*=\s*\{.*?GodSystem\.SystemRepairKit.*?GodSystem\.DurabilityCore' 'Maintenance items must not create duplicate unlocked shop rows'
Require-Text $config '(?s)LotteryBlacklist\s*=\s*\{.*?GodSystem\.SystemRepairKit.*?GodSystem\.DurabilityCore' 'Maintenance items must be excluded from lottery'
Require-Text $server 'LotteryBlacklist[^\r\n]*\[fullType\]' 'Server lottery candidates must enforce LotteryBlacklist'
Require-Text $core 'LotteryBlacklist[^\r\n]*\[fullType\]' 'SP lottery candidates must enforce LotteryBlacklist'

Require-Text $protocol 'UseMaintenanceItem\s*=\s*"useMaintenanceItem"' 'Maintenance C2S protocol command missing'
Require-Text $protocol '(?s)StateCommands\s*=\s*\{.*?useMaintenanceItem\s*=\s*true' 'Maintenance command must be state-tracked'
Require-Text $protocol '(?s)KeyCommands\s*=\s*\{.*?useMaintenanceItem\s*=\s*true' 'Maintenance command must use pending-operation protection'
Require-Text $network 'wrap\("useMaintenanceItem"' 'MP maintenance network wrapper missing'

$client = Read-Utf8 $ClientPath
Require-Text $client 'OnFillInventoryObjectContextMenu\.Add' 'Inventory context-menu hook missing'
Require-Text $client 'ISModalDialog:new' 'Maintenance confirmation dialog missing'
Require-Text $client 'getPrimaryHandItem' 'Maintenance target must be the current primary-hand item'
Require-Text $client 'repairHeld' 'Repair action missing'
Require-Text $client 'reinforceHeld' 'Reinforce action missing'
Require-Text $client 'GodSystemMaintenance\.apply' 'Client must reuse the shared maintenance implementation'
Require-Text $client 'consumableItemId' 'Request must identify the selected consumable'
Require-Text $client 'targetItemId' 'Request must identify the confirmed target'

Require-Text $maintenance 'function\s+GodSystemMaintenance\.snapshot\s*\(' 'Shared maintenance snapshot helper missing'
Require-Text $maintenance 'function\s+GodSystemMaintenance\.apply\s*\(' 'Shared maintenance apply helper missing'
Require-Text $maintenance 'function\s+GodSystemMaintenance\.rollback\s*\(' 'Shared maintenance rollback helper missing'
Require-Text $maintenance 'setConditionMax' 'Reinforce must modify per-item maximum condition'
Require-Text $maintenance 'oldCondition\s*\+\s*2' 'Reinforce must add 2 current condition'
Require-Text $maintenance 'oldMax\s*\+\s*2' 'Reinforce must add 2 maximum condition'
Require-Text $maintenance 'setHeadCondition' 'Repair must restore head condition when supported'
Require-Text $maintenance 'setSharpness' 'Repair must restore sharpness when supported'

Require-Text $server 'function\s+Commands\.useMaintenanceItem\s*\(' 'Server maintenance handler missing'
Require-Text $server 'consumableItemId' 'Server must validate the selected consumable id'
Require-Text $server 'targetItemId' 'Server must validate the confirmed target id'
Require-Text $server 'getPrimaryHandItem' 'Server must re-check the current primary-hand item'
Require-Text $server 'repairHeld' 'Server repair action missing'
Require-Text $server 'reinforceHeld' 'Server reinforce action missing'
Require-Text $server 'GodSystemMaintenance\.apply' 'Server must reuse the shared maintenance implementation'
Require-Text $server 'rollbackMaintenanceTarget' 'Server must roll back partial mutations when consumption fails'
Require-Text $server 'finishCode\s*\([^\r\n]*Maintenance' 'Server maintenance results must use structured finishCode codes'

$uiKeys = @(
    'Context_RepairHeld', 'Context_ReinforceHeld',
    'Confirm_RepairHeld', 'Confirm_ReinforceHeld',
    'Maintenance_MainCondition', 'Maintenance_HeadCondition', 'Maintenance_Sharpness',
    'Maintenance_HeadMaxUnchanged',
    'Notify_MaintenanceNoHeldItem', 'Notify_MaintenanceInvalidTarget', 'Notify_MaintenanceAlreadyFull',
    'NotifyMP_MaintenanceTargetChanged', 'NotifyMP_MaintenanceConsumableMissing',
    'NotifyMP_MaintenanceInvalidTarget', 'NotifyMP_MaintenanceAlreadyFull',
    'NotifyMP_MaintenanceRepairSuccess', 'NotifyMP_MaintenanceReinforceSuccess',
    'NotifyMP_MaintenanceFailed', 'NotifyMP_MaintenanceOverflow'
)
foreach ($key in $uiKeys) {
    $translatePattern = '(?m)^\s*IGUI_GodSystem_' + [regex]::Escape($key) + '\s*=\s*".*",\s*$'
    Require-Text $cnUi $translatePattern "CN UI key missing or malformed: $key"
    Require-Text $chUi $translatePattern "CH UI key missing or malformed: $key"
    $fallbackPattern = '(?m)^GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]\s*=\s*"([^\"]*)"\s*$'
    $match = [regex]::Match($override, $fallbackPattern)
    if (-not $match.Success) { throw "Fallback key missing: $key" }
    if ($match.Groups[1].Value -match '[^\x00-\x7F]') { throw "Fallback must be ASCII-only: $key" }
}

$repairNamePattern = 'ItemName_GodSystem\.SystemRepairKit\s*=\s*"[^\"]+"'
$coreNamePattern = 'ItemName_GodSystem\.DurabilityCore\s*=\s*"[^\"]+"'
$repairTooltipPattern = 'Tooltip_GodSystem_SystemRepairKit\s*=\s*"[^\"]*MOD[^\"]*"'
$coreTooltipPattern = 'Tooltip_GodSystem_DurabilityCore\s*=\s*"[^\"]*2[^\"]*"'
if ($cnItems -notmatch $repairNamePattern -or $chItems -notmatch $repairNamePattern) { throw 'Repair item name translation missing' }
if ($cnItems -notmatch $coreNamePattern -or $chItems -notmatch $coreNamePattern) { throw 'Core item name translation missing' }
if ($cnItems -notmatch $repairTooltipPattern -or $chItems -notmatch $repairTooltipPattern) { throw 'Repair tooltip must explain standard MOD durability support' }
if ($cnItems -notmatch $coreTooltipPattern -or $chItems -notmatch $coreTooltipPattern) { throw 'Core tooltip must explain head-condition limitation' }

foreach ($jsonPath in @($CnItemJsonPath, $ChItemJsonPath, $CnTooltipJsonPath, $ChTooltipJsonPath)) {
    $json = Read-Utf8 $jsonPath | ConvertFrom-Json
    if (-not $json) { throw "Invalid localization JSON: $jsonPath" }
}
$cnItemJson = Read-Utf8 $CnItemJsonPath | ConvertFrom-Json
$chItemJson = Read-Utf8 $ChItemJsonPath | ConvertFrom-Json
$cnTooltipJson = Read-Utf8 $CnTooltipJsonPath | ConvertFrom-Json
$chTooltipJson = Read-Utf8 $ChTooltipJsonPath | ConvertFrom-Json
foreach ($json in @($cnItemJson, $chItemJson)) {
    if (-not $json.PSObject.Properties['GodSystem.SystemRepairKit'] -or -not $json.PSObject.Properties['GodSystem.DurabilityCore']) {
        throw 'B42 ItemName JSON keys missing'
    }
}
foreach ($json in @($cnTooltipJson, $chTooltipJson)) {
    if (-not $json.PSObject.Properties['Tooltip_GodSystem_SystemRepairKit'] -or -not $json.PSObject.Properties['Tooltip_GodSystem_DurabilityCore']) {
        throw 'B42 Tooltip JSON keys missing'
    }
}

foreach ($icon in @($RepairIconPath, $CoreIconPath)) {
    if (-not (Test-Path -LiteralPath $icon)) { throw "Missing icon: $icon" }
    if ((Get-Item -LiteralPath $icon).Length -le 0) { throw "Empty icon: $icon" }
}

Write-Output 'Test-GodSystemV11647 passed'
