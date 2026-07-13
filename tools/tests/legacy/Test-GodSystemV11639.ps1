$ErrorActionPreference = 'Stop'

$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Lua = Join-Path $Mod '42\media\lua'

$CorePath = Join-Path $Lua 'client\GodSystem_Core.lua'
$UiPath = Join-Path $Lua 'client\GodSystem_UI.lua'
$NetworkPath = Join-Path $Lua 'client\GodSystem_Network.lua'
$ProtocolPath = Join-Path $Lua 'shared\GodSystem_Protocol.lua'
$ServerPath = Join-Path $Lua 'server\GodSystem_Server.lua'
$ConfigPath = Join-Path $Lua 'shared\GodSystem_Config.lua'
$AdminPath = Join-Path $Lua 'shared\GodSystem_AdminConfig.lua'
$OverridePath = Join-Path $Lua 'shared\GodSystem_Localization_Override.lua'
$CnPath = Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt'
$ChPath = Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt'
$ReadmePath = (Get-ChildItem -LiteralPath $Root -Filter 'README_*.md' | Select-Object -First 1).FullName
if ([string]::IsNullOrWhiteSpace($ReadmePath)) {
    throw 'README upload note file not found'
}

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Require-NoText([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) {
        throw $Message
    }
}

function Extract-Block([string]$Text, [string]$StartPattern, [string]$EndLookahead, [string]$Message) {
    $match = [regex]::Match($Text, $StartPattern + '[\s\S]*?(?=' + $EndLookahead + ')')
    if (-not $match.Success) {
        throw $Message
    }
    return $match.Value
}

$core = Read-Utf8 $CorePath
$ui = Read-Utf8 $UiPath
$network = Read-Utf8 $NetworkPath
$protocol = Read-Utf8 $ProtocolPath
$server = Read-Utf8 $ServerPath
$config = Read-Utf8 $ConfigPath
$admin = Read-Utf8 $AdminPath
$override = Read-Utf8 $OverridePath
$cn = Read-Utf8 $CnPath
$ch = Read-Utf8 $ChPath
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$readme = Read-Utf8 $ReadmePath

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.39"' 'Config version must be 1.16.39'
Require-Text $rootInfo '(?m)^modversion=1\.16\.39$' 'Root mod.info version must be 1.16.39'
Require-Text $b42Info '(?m)^modversion=1\.16\.39$' 'B42 mod.info version must be 1.16.39'
Require-Text $readme 'v1\.16\.39' 'README must include v1.16.39 notes'

Require-Text $config 'GodSystemConfig\.AutoShopListOnlyCostRatio\s*=\s*0\.5' 'Default list-only cost ratio must be 0.5'
Require-Text $config 'GodSystemConfig\.AutoShopListOnlyMinCost\s*=\s*50' 'Default list-only minimum cost must be 50'
Require-Text $admin 'key\s*=\s*"AutoShopListOnlyCostRatio"' 'Admin config must expose AutoShopListOnlyCostRatio'
Require-Text $admin 'key\s*=\s*"AutoShopListOnlyMinCost"' 'Admin config must expose AutoShopListOnlyMinCost'
Require-Text $admin 'target\s*=\s*"AutoShopListOnlyCostRatio"' 'Admin ratio setting must target the runtime config'
Require-Text $admin 'target\s*=\s*"AutoShopListOnlyMinCost"' 'Admin min-cost setting must target the runtime config'

$costBlock = Extract-Block $core 'function\s+GodSystem\.getAutoShopListOnlyCost\s*\(' '\r?\nfunction\s+GodSystem\.' 'Client list-only cost helper is missing'
Require-Text $costBlock 'getAutoShopBuyPriceForItem\s*\(' 'List-only cost must derive from expected shop buy price'
Require-Text $costBlock 'AutoShopListOnlyCostRatio' 'List-only cost must use configurable ratio'
Require-Text $costBlock 'AutoShopListOnlyMinCost' 'List-only cost must use configurable minimum'
Require-Text $costBlock 'math\.ceil' 'List-only cost must round ratio fee up'

$clientBlock = Extract-Block $core 'function\s+GodSystem\.listOnlyAutoShopItem\s*\(' '\r?\nfunction\s+GodSystem\.' 'Client listOnlyAutoShopItem function is missing'
Require-Text $clientBlock 'gsFindInventoryItems\s*\(\s*fullType\s*,\s*false\s*,\s*false\s*\)' 'Client list-only must verify a real backpack item'
Require-Text $clientBlock 'isAutoShopUnlockAllowed\s*\(' 'Client list-only must respect unlock allow rules'
Require-Text $clientBlock 'getSpendableBalance\s*\(\s*\)' 'Client list-only must check spendable balance'
Require-Text $clientBlock 'spendCurrency\s*\(\s*cost\s*\)|addPoints\s*\(\s*-cost' 'Client list-only must charge the existing spend path'
Require-Text $clientBlock 'unlockAutoShopItem\s*\(' 'Client list-only must unlock the auto-shop entry'
Require-NoText $clientBlock 'removeInventoryItems|removeItemFromContainer' 'Client list-only must not remove the item'

Require-Text $ui 'Menu_ListOnly' 'Recycle context menu must include Menu_ListOnly'
Require-Text $ui 'function\s+GodSystemWindow:confirmListOnlyAutoShop\s*\(' 'UI must confirm list-only action'
Require-Text $ui 'function\s+GodSystemWindow:onListOnlyAutoShopConfirm\s*\(' 'UI must handle list-only confirmation'
Require-Text $ui 'ISModalDialog:new' 'UI list-only action must use a confirmation modal'
Require-Text $ui 'GodSystem\.listOnlyAutoShopItem\s*\(' 'UI must call listOnlyAutoShopItem after confirmation'

Require-Text $network 'wrap\s*\(\s*"listOnlyAutoShopItem"' 'Network bridge must wrap listOnlyAutoShopItem'
Require-Text $network 'send\s*\(\s*"listOnlyAutoShop"' 'Network bridge must send listOnlyAutoShop'
Require-Text $protocol 'ListOnlyAutoShop\s*=\s*"listOnlyAutoShop"' 'Protocol C2S must include ListOnlyAutoShop'
Require-Text $protocol '(?s)StateCommands\s*=\s*\{.*listOnlyAutoShop\s*=\s*true' 'Protocol state commands must include listOnlyAutoShop'
Require-Text $protocol '(?s)KeyCommands\s*=\s*\{.*listOnlyAutoShop\s*=\s*true' 'Protocol key commands must include listOnlyAutoShop'

Require-Text $server 'local\s+function\s+autoShopListOnlyCost\s*\(' 'Server must compute list-only cost independently'
Require-Text $server 'local\s+function\s+isAutoShopListOnlyAllowed\s*\(' 'Server must validate list-only eligibility independently'
$serverBlock = Extract-Block $server 'function\s+Commands\.listOnlyAutoShop\s*\(' '\r?\n(?:local\s+function|function\s+Commands\.)' 'Server listOnlyAutoShop command is missing'
Require-Text $serverBlock 'inventoryItems\s*\(\s*player\s*,\s*fullType\s*,\s*false\s*,\s*false\s*\)' 'Server list-only must verify the item exists in player inventory'
Require-Text $serverBlock 'isAutoShopListOnlyAllowed\s*\(' 'Server list-only must reject disabled or blacklisted items'
Require-Text $serverBlock 'canAfford\s*\(' 'Server list-only must check affordability before charging'
Require-Text $serverBlock 'addPoints\s*\(\s*player\s*,\s*-cost\s*,\s*data\s*\)' 'Server list-only must charge with bank-first spend path'
Require-Text $serverBlock 'unlockAutoShopItem\s*\(' 'Server list-only must unlock after charging'
Require-NoText $serverBlock 'removeItemFromContainer|removeInventoryItems' 'Server list-only must not remove the item'

foreach ($key in @(
    'Menu_ListOnly',
    'Confirm_ListOnlyAutoShop',
    'Notify_ListOnlyAlreadyUnlocked',
    'Notify_ListOnlyDisabled',
    'Notify_ListOnlyInsufficient',
    'Notify_ListOnlySuccess',
    'History_ListOnlyAutoShop',
    'AdminSetting_AutoShopListOnlyCostRatio',
    'AdminSetting_AutoShopListOnlyMinCost'
)) {
    Require-Text $override ([regex]::Escape('["' + $key + '"]')) "Fallback localization missing $key"
    Require-Text $cn ("IGUI_GodSystem_" + [regex]::Escape($key) + "\s*=") "CN translation missing $key"
    Require-Text $ch ("IGUI_GodSystem_" + [regex]::Escape($key) + "\s*=") "CH translation missing $key"
}

$files = Get-ChildItem -LiteralPath $Lua -Recurse -Filter *.lua
foreach ($file in $files) {
    $text = Read-Utf8 $file.FullName
    if ($text.Contains([char]0xFFFD)) {
        throw "Replacement character found: $($file.FullName)"
    }
}

Write-Output 'Test-GodSystemV11639 passed'
