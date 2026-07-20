param(
    [string]$Root = "",
    [string]$ExpectedVersion = "1.16.53",
    [int]$ExpectedAdminSettings = 68,
    [switch]$SkipLegacyTerminalChecks
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Media = Join-Path $Mod '42\media'
$Lua = Join-Path $Media 'lua'
$Textures = Join-Path $Media 'textures'

$ConfigPath = Join-Path $Lua 'shared\GodSystem_Config.lua'
$AdminConfigPath = Join-Path $Lua 'shared\GodSystem_AdminConfig.lua'
$AttributesPath = Join-Path $Lua 'shared\GodSystem_Attributes.lua'
$ProtocolPath = Join-Path $Lua 'shared\GodSystem_Protocol.lua'
$CompanionConfigPath = Join-Path $Lua 'shared\GodSystem_CompanionConfig.lua'
$MaintenancePath = Join-Path $Lua 'shared\GodSystem_Maintenance.lua'
$CorePath = Join-Path $Lua 'client\GodSystem_Core.lua'
$UiPath = Join-Path $Lua 'client\GodSystem_UI.lua'
$CompanionPath = Join-Path $Lua 'client\GodSystem_Companion.lua'
$CompanionUiPath = Join-Path $Lua 'client\GodSystem_CompanionUI.lua'
$NetworkPath = Join-Path $Lua 'client\GodSystem_Network.lua'
$ServerPath = Join-Path $Lua 'server\GodSystem_Server.lua'
$ItemsPath = Join-Path $Media 'scripts\GodSystem_Items.txt'
$SandboxPath = Join-Path $Media 'sandbox-options.txt'
$LocalizationSource = Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml'
$LocalizationGenerator = Join-Path $Root 'tools\localization\generate_godsystem_v11645_localization.py'

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

$config = Read-Utf8 $ConfigPath
$admin = Read-Utf8 $AdminConfigPath
$attributes = Read-Utf8 $AttributesPath
$protocol = Read-Utf8 $ProtocolPath
$companionConfig = Read-Utf8 $CompanionConfigPath
$maintenance = Read-Utf8 $MaintenancePath
$core = Read-Utf8 $CorePath
$ui = Read-Utf8 $UiPath
$companion = Read-Utf8 $CompanionPath
$companionUi = Read-Utf8 $CompanionUiPath
$network = Read-Utf8 $NetworkPath
$server = Read-Utf8 $ServerPath
$items = Read-Utf8 $ItemsPath
$sandbox = Read-Utf8 $SandboxPath
$localization = Read-Utf8 $LocalizationSource
$generator = Read-Utf8 $LocalizationGenerator
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

$versionPattern = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $versionPattern + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $versionPattern + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $versionPattern + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + $versionPattern + '\r?$') "Workshop metadata must mention v$ExpectedVersion"

$settingCount = ([regex]::Matches($admin, '(?m)^\s*\{\s*key\s*=\s*"')).Count
if ($settingCount -ne $ExpectedAdminSettings) { throw "Expected $ExpectedAdminSettings admin settings, found $settingCount" }
foreach ($key in @('EnableAttributes', 'AttributeXPPerCoin')) {
    Require-Text $admin ('key\s*=\s*"' + $key + '"') "Missing admin setting: $key"
    Require-Text $sandbox ('option\s+GodSystem\.' + $key + '\b') "Missing sandbox option: $key"
}
Require-Text $generator ("Expected " + $ExpectedAdminSettings + " admin settings") "Localization generator must validate $ExpectedAdminSettings settings"

Require-Text $config 'AutoRecyclerFullType\s*=\s*"GodSystem\.SystemSpaceTerminal"' 'Primary system container must be SystemSpaceTerminal'
Require-Text $config '\["GodSystem\.SystemSpaceTerminal"\]\s*=\s*true' 'SystemSpaceTerminal alias missing'
Require-Text $items 'item\s+SystemSpaceTerminal\b' 'SystemSpaceTerminal item definition missing'
if (-not $SkipLegacyTerminalChecks) {
    Require-Text $items 'CanBeEquipped\s*=\s*GodSystem:GodSystemTerminal' 'System terminal body location missing'
    Require-Text (Read-Utf8 (Join-Path $Media 'registries.lua')) 'ItemBodyLocation\.register\("GodSystem:GodSystemTerminal"\)' 'System terminal registry entry missing'
    Require-Text $config 'level\s*=\s*9[^\r\n]*capacity\s*=\s*60[^\r\n]*upgradeCost\s*=\s*1500' 'Level 9 terminal values missing'
    Require-Text $config 'level\s*=\s*10[^\r\n]*capacity\s*=\s*75[^\r\n]*upgradeCost\s*=\s*2100' 'Level 10 terminal values missing'
    Require-Text $config 'level\s*=\s*11[^\r\n]*capacity\s*=\s*90[^\r\n]*upgradeCost\s*=\s*3000' 'Level 11 terminal values missing'
    Require-Text $config 'level\s*=\s*12[^\r\n]*capacity\s*=\s*100[^\r\n]*upgradeCost\s*=\s*4500' 'Level 12 terminal values missing'
    Require-Text $core 'migrateSystemSpaceTerminal' 'SP terminal migration entry missing'
    Require-Text $server 'migrateSystemSpaceTerminal' 'MP terminal migration entry missing'
}
else {
    Require-Text $items 'CanBeEquipped\s*=\s*base:necklace' 'Current system terminal must use the vanilla necklace slot'
    if (Test-Path -LiteralPath (Join-Path $Media 'registries.lua')) { throw 'Legacy terminal registry must be absent when legacy checks are skipped' }
}
Require-Text $core 'function\s+GodSystem\.removeCurrency[\s\S]*GodSystem\.removeCurrencyItem\(' 'SP currency removal must verify each exact item removal'
Require-Text $server 'local function removeCurrency[\s\S]*if\s+not\s+removeItemFromContainer\(' 'MP currency removal must verify each exact item removal'
if (-not $SkipLegacyTerminalChecks) {
    Require-Text $core 'owner:Remove\(oldItem\)[\s\S]*GodSystem\.containerContainsItem\(owner,\s*oldItem\)' 'SP terminal migration must verify the legacy container was removed'
    Require-Text $server 'owner:Remove\(oldItem\)[\s\S]*GodSystemServerContainerContainsItem\(owner,\s*oldItem\)' 'MP terminal migration must verify the legacy container was removed'
    Require-Text $server 'migrateSystemSpaceTerminal[\s\S]*sendAddItemToContainer[^\r\n]*playerInventory[^\r\n]*newItem' 'MP terminal migration must sync the new terminal to the client'
    Require-Text $server 'migrateSystemSpaceTerminal[\s\S]*sendRemoveItemFromContainer[^\r\n]*owner[^\r\n]*oldItem' 'MP terminal migration must sync removal of the legacy container'
}
Require-Text $config 'AutoShopBlacklist[\s\S]*\["GodSystem\.SystemSpaceTerminal"\]\s*=\s*true' 'Terminal auto-list blacklist missing'
Require-Text $config 'RecycleBlacklist[\s\S]*\["GodSystem\.SystemSpaceTerminal"\]\s*=\s*true' 'Terminal recycle blacklist missing'
foreach ($icon in @('Item_SystemSpaceTerminal.png', 'Item_SystemVehicleRepairModule.png')) {
    $iconPath = Join-Path $Textures $icon
    if (-not (Test-Path -LiteralPath $iconPath)) { throw "Missing generated item icon: $icon" }
    if ((Get-Item -LiteralPath $iconPath).Length -le 100) { throw "Generated item icon is empty: $icon" }
}

Require-Text $protocol 'Attribute\s*=\s*"attribute"' 'Attribute protocol command missing'
Require-Text $protocol '(?m)^\s*attribute\s*=\s*true' 'Attribute protocol command sets missing'
Require-Text $server 'function\s+Commands\.attribute\b' 'Server attribute handler missing'
Require-Text $server 'GodSystemServer\.attributeOps' 'MP attribute purchases need a bounded operation-result cache'
Require-Text $server 'attributeOpBucket[\s\S]*local\s+root\s*=\s*store\(\)[\s\S]*root\.attributeOperations' 'MP attribute idempotency cache must survive a server restart in persistent ModData'
Require-Text $server 'GodSystemServer\.attributeOpId\(' 'MP attribute purchases must validate a globally unique operation ID'
Require-Text $server 'GodSystemServer\.attributeOpFingerprint\(' 'MP attribute operation IDs must be bound to the normalized request payload'
Require-Text $server 'GodSystemServer\.getAttributeOpResult\(' 'MP attribute handler must reject duplicate operation IDs'
Require-Text $server 'status\s*==\s*"mismatch"' 'MP attribute handler must reject reuse of an operation ID for different purchase data'
Require-Text $server 'GodSystemServer\.rememberAttributeOpResult\(' 'MP attribute handler must remember completed operation results'
Require-Text $server 'GodSystemServer\.beginAttributeOp\(' 'MP attribute handler must register processing before charging'
Require-Text $server 'GodSystemServer\.markAttributeOpUnknown\(' 'MP attribute handler must lock an unknown outcome after an exception'
Require-Text $server 'status\s*==\s*"processing"[\s\S]*status\s*=\s*"unknown"' 'Persisted in-flight attribute operations must become unknown after server restart'
Require-Text $server 'AttributeOperationInvalid' 'MP attribute handler must reject a missing or malformed operation ID'
Require-Text $network 'operationSessionId' 'Client attribute operation IDs must remain unique across reconnects'
Require-Text $network 'GodSystemNetwork\.operationSeq' 'Client attribute operation sequence must survive a Lua module reload'
Require-Text $network '"gs-"\s*\.\.' 'Client attribute operation IDs must use the versioned unique string format'
Require-Text $network 'timedOutAttributeOperation' 'Client must retain a timed-out attribute operation for safe retry'
Require-Text $network 'sameAttributePayload' 'Client must only reuse an operation ID for the identical attribute request'
Require-Text $attributes 'Perks\.fromIndex' 'Shared attribute module must resolve perk from index'
Require-Text $attributes 'PerkFactory\.getPerk' 'Shared attribute module must resolve registered perk metadata'
Require-Text $attributes 'safeCall\(factoryPerk,\s*"getParent"' 'Attribute parent must come from registered perk metadata first'
Require-Text $attributes 'safeCall\(factoryPerk,\s*"getTotalXpForLevel"' 'Attribute XP curve must come from registered perk metadata first'
Require-Text $server 'SyncXp\s*\(' 'Server must sync XP after purchase'
Require-Text $core ':AddXP\(quote\.info\.perk,\s*quote\.actualXp,\s*false,\s*false,\s*false,\s*false\)' 'SP attribute XP must use the verified no-multiplier AddXP call'
Require-Text $server ':AddXP\(quote\.info\.perk,\s*quote\.actualXp,\s*false,\s*false,\s*false,\s*false\)' 'MP attribute XP must use the verified no-multiplier AddXP call'
Require-Text $core 'appliedXp\s*=[^\r\n]*math\.max\(0,\s*state\.currentXp\s*-\s*before\)' 'SP attribute purchase must settle against the actual XP delta'
Require-Text $server 'appliedXp\s*=[^\r\n]*math\.max\(0,\s*state\.currentXp\s*-\s*before\)' 'MP attribute purchase must settle against the actual XP delta'
Require-Text $core 'GodSystem\.refundCurrencySources\(' 'SP attribute refunds must preserve value when cash restoration fails'
Require-Text $server 'GodSystemServer\.refundCurrencySources\(' 'MP attribute refunds must preserve value when cash restoration fails'
Require-Text $core 'GodSystem\.restoreRemovedCurrencyOrBank\(' 'SP cash-removal rollback failure must fall back to the bank'
Require-Text $server 'GodSystemServer\.restoreRemovedCurrencyOrBank\(' 'MP cash-removal rollback failure must fall back to the bank'
Require-Text $server 'attributeSyncPending' 'MP attribute sync failure must be recorded for a later retry'
Reject-Text $core 'if\s+not\s+okAdd\s+or\s+appliedXp\s*<=\s*0' 'SP must settle a partial XP mutation even if AddXP raised after mutation'
Reject-Text $server 'if\s+not\s+okAdd\s+or\s+appliedXp\s*<=\s*0' 'MP must settle a partial XP mutation even if AddXP raised after mutation'
Require-Text $server 'function\s+Commands\.attribute[\s\S]*spendCurrency\([^\r\n]*quote\.cost\)[\s\S]*fromBank[\s\S]*fromCash' 'MP attribute purchase must preserve bank/cash payment sources for refunds'
Require-Text $core 'function\s+GodSystem\.getAttributePerks\b' 'Attribute enumeration helper missing'
Require-Text $attributes 'Perks\.getMaxIndex\s*\(' 'Attribute enumeration must use Perks.getMaxIndex'
Require-Text $attributes 'getTotalXpForLevel' 'Attribute target-level XP calculation missing'
Require-Text $attributes 'if\s+#args\s*==\s*0\s+then[\s\S]*object\[methodName\]\(object\)' 'Shared attribute safeCall must not pass a synthetic nil argument'
Require-Text $ui '\{\s*id\s*=\s*"attribute"' 'Attribute navigation tab missing'
Require-Text $ui 'populateAttributes|populateAttribute' 'Attribute page population missing'
Require-Text $ui 'function\s+GodSystemWindow:showAttributeAmountDialog\b' 'Attribute amount dialog helper missing'
Require-Text $ui 'self\.mode\s*==\s*"attribute"[\s\S]*showAttributeAmountDialog\(' 'Attribute primary action is not wired'
Require-Text $ui 'self\.mode\s*==\s*"attribute"[\s\S]*showAttributeNextLevelConfirm\(' 'Attribute next-level action is not wired'
Require-Text $ui 'payload\.kind\s*==\s*"attribute"[\s\S]*"attribute:"' 'Attribute rows need stable selection IDs'

Require-Text $items 'item\s+SystemVehicleRepairModule\b' 'Vehicle repair module item definition missing'
Require-Text $config 'SystemVehicleRepairModule' 'Vehicle repair module shop entry or exclusion missing'
Require-Text $config 'price\s*=\s*5000' 'Vehicle repair module default price must be 5000'
Require-Text $server 'action\s*==\s*"repairVehicle"' 'Server vehicle repair action missing'
Require-Text $server 'getVehicleById\s*\(' 'Server vehicle lookup by ID missing'
if ($SkipLegacyTerminalChecks) {
    Require-Text $server 'GodSystemMaintenance\.repairVehicle\s*\(' 'Server shared vehicle repair call missing'
    Require-Text $maintenance 'call\(vehicle,\s*"repair"\)' 'Shared vehicle repair helper must call the BaseVehicle repair method'
}
else {
    Require-Text $server ':repair\s*\(' 'Server vehicle repair call missing'
}
Require-Text $server 'VehicleRepairTooFar|VehicleRepairWrongFloor' 'Server vehicle range validation missing'
Require-Text $server 'giveItem\([^\r\n]*SystemVehicleRepairModule|giveItem\([^\r\n]*expectedType' 'Vehicle repair failure must refund a module'
$vehicleContextFiles = @(Get-ChildItem -LiteralPath (Join-Path $Lua 'client') -Filter '*Vehicle*Context*.lua' -File)
if ($vehicleContextFiles.Count -lt 1) { throw 'Vehicle repair context-menu module missing' }
$vehicleContext = ($vehicleContextFiles | ForEach-Object { Read-Utf8 $_.FullName }) -join "`n"
Require-Text $vehicleContext 'Events\.OnFillWorldObjectContextMenu\.Add' 'Vehicle repair context menu event missing'
Require-Text $vehicleContext 'GodSystem\.SystemVehicleRepairModule' 'Vehicle repair context must require the module item'
Require-Text $vehicleContext 'useMaintenanceItem|UseMaintenanceItem' 'Vehicle repair context must reuse maintenance command'
Require-Text $vehicleContext 'ISModalDialog' 'Vehicle repair confirmation dialog missing'

foreach ($id in @('shock', 'corrosion', 'mark', 'chain', 'blast')) {
    Require-Text $companionConfig ('\b' + $id + '\b') "Companion effect config missing: $id"
}
Require-Text $companionConfig 'EffectOrder\s*=\s*\{\s*"shock"\s*,\s*"corrosion"\s*,\s*"mark"\s*,\s*"chain"\s*,\s*"blast"\s*\}' 'Companion effect unlock order is wrong'
foreach ($cost in @(1000, 2000, 4000, 8000, 16000)) {
    Require-Text $companionConfig ('cost\s*=\s*' + $cost + '\b') "Companion effect cost missing: $cost"
}
Require-Text $companionConfig 'data\.effects\s*=\s*type\(data\.effects\)\s*==\s*"table"' 'Companion effect persistence defaults missing'
Require-Text $companionConfig 'areAllEffectsUnlocked' 'Companion effect completion helper missing'
Require-Text $companionConfig 'getResonanceCost[\s\S]*canPurchaseResonance' 'Resonance purchase must be gated by functional levels and all effects'
Require-Text $companionConfig 'function\s+Config\.getResonanceCost[\s\S]*Config\.canPurchaseResonance\(data\)' 'Resonance price must stay hidden until functional upgrades and effects are complete'
foreach ($token in @('shockCooldowns', 'corrosionStates', 'markStates', 'chain', 'blast')) {
    Require-Text $companion ([regex]::Escape($token)) "Companion runtime effect residue missing: $token"
}
Require-Text $companion 'setHitReaction\s*\(' 'Shock hit reaction missing'
Reject-Text $companion 'SetOnFire\s*\(|setCanWalk\s*\(\s*false|setCrawler\s*\(\s*true' 'Companion effects use forbidden persistent zombie states'
Require-Text $companion 'CompanionEffect|companionEffect' 'Companion effect nodes missing from companion row model'
Require-Text $ui 'GodSystemCompanion\.getRows' 'Main UI must render companion row models'
Reject-Text $protocol '(?i)companionEffect|shock|corrosion|chain|blast' 'SP-only companion effects must not add multiplayer protocol'
Reject-Text $server '(?i)companionEffect|shockCooldowns|corrosionStates|markStates' 'SP-only companion effects must not add server handlers'

foreach ($key in @(
    'ItemName_GodSystem.SystemSpaceTerminal',
    'ItemName_GodSystem.SystemVehicleRepairModule',
    'Tab_Attributes',
    'Attribute_BuyXP',
    'Attribute_NextLevel',
    'NotifyMP_AttributePurchasedSyncPending',
    'Notify_AttributeApplyFailedBankRefund',
    'NotifyMP_AttributeApplyFailedBankRefund',
    'NotifyMP_AttributeOperationInvalid',
    'NotifyMP_AttributeOperationPending',
    'NotifyMP_AttributeOperationUnknown',
    'Context_RepairVehicle',
    'Companion_EffectShock',
    'Companion_EffectCorrosion',
    'Companion_EffectMark',
    'Companion_EffectChain',
    'Companion_EffectBlast'
)) {
    Require-Text $localization ('(?m)^' + [regex]::Escape($key) + ':') "Localization source key missing: $key"
}

$LuaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $LuaExe) {
    $localLua = Join-Path $env:USERPROFILE 'Tools\Lua51\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $LuaExe = Get-Item -LiteralPath $localLua }
}
if ($LuaExe) {
    $LuaExePath = if ($LuaExe.Source) { $LuaExe.Source } else { $LuaExe.FullName }
    & $LuaExePath (Join-Path $PSScriptRoot 'Test-GodSystemV11653Runtime.lua') (Join-Path $Lua 'shared')
    if ($LASTEXITCODE -ne 0) { throw 'v1.16.53 Lua runtime test failed' }
}
else {
    Write-Warning 'Lua executable was not found; v1.16.53 runtime validation was skipped.'
}

Write-Output 'Test-GodSystemV11653 passed'
