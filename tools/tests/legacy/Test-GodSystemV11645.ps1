$ErrorActionPreference = 'Stop'

$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Lua = Join-Path $Mod '42\media\lua'

$ConfigPath = Join-Path $Lua 'shared\GodSystem_Config.lua'
$ProtocolPath = Join-Path $Lua 'shared\GodSystem_Protocol.lua'
$OverridePath = Join-Path $Lua 'shared\GodSystem_Localization_Override.lua'
$CnPath = Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt'
$ChPath = Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt'
$CorePath = Join-Path $Lua 'client\GodSystem_Core.lua'
$NetworkPath = Join-Path $Lua 'client\GodSystem_Network.lua'
$UiPath = Join-Path $Lua 'client\GodSystem_UI.lua'
$ServerPath = Join-Path $Lua 'server\GodSystem_Server.lua'

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Require-CountAtLeast([string]$Text, [string]$Pattern, [int]$Min, [string]$Message) {
    $count = [regex]::Matches($Text, $Pattern).Count
    if ($count -lt $Min) {
        throw "$Message (found $count, expected at least $Min)"
    }
}

function Require-CommandUsesFinishCode([string]$ServerText, [string]$CommandName) {
    $pattern = '(?s)function\s+Commands\.' + [regex]::Escape($CommandName) + '\b.*?(?=function\s+Commands\.|\z)'
    $match = [regex]::Match($ServerText, $pattern)
    if (-not $match.Success) {
        throw "Server command missing: $CommandName"
    }
    if ($match.Value -notmatch '\bfinishCode\s*\(') {
        throw "Server command should use finishCode: $CommandName"
    }
}

$config = Read-Utf8 $ConfigPath
$protocol = Read-Utf8 $ProtocolPath
$override = Read-Utf8 $OverridePath
$cn = Read-Utf8 $CnPath
$ch = Read-Utf8 $ChPath
$core = Read-Utf8 $CorePath
$network = Read-Utf8 $NetworkPath
$ui = Read-Utf8 $UiPath
$server = Read-Utf8 $ServerPath
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.45"' 'Config version must be 1.16.45'
Require-Text $rootInfo '(?m)^modversion=1\.16\.45$' 'Root mod.info version must be 1.16.45'
Require-Text $b42Info '(?m)^modversion=1\.16\.45$' 'B42 mod.info version must be 1.16.45'

Require-Text $protocol 'ToggleWaistRecycleMode\s*=\s*"toggleWaistRecycleMode"' 'Protocol C2S must declare toggleWaistRecycleMode'
Require-CountAtLeast $protocol '(?m)^\s*toggleWaistRecycleMode\s*=\s*true,\s*$' 2 'Protocol StateCommands and KeyCommands must include toggleWaistRecycleMode'

Require-Text $core 'data\.waistRecycleUnlockMode\s*=\s*data\.waistRecycleUnlockMode\s*==\s*true' 'Client data init must persist waistRecycleUnlockMode'
Require-Text $server 'data\.waistRecycleUnlockMode\s*=\s*data\.waistRecycleUnlockMode\s*==\s*true' 'Server data init must persist waistRecycleUnlockMode'

Require-Text $core 'function\s+GodSystem\.isWaistRecycleUnlockMode\s*\(' 'Client helper missing: isWaistRecycleUnlockMode'
Require-Text $core 'function\s+GodSystem\.toggleWaistRecycleUnlockMode\s*\(' 'Client helper missing: toggleWaistRecycleUnlockMode'
Require-Text $core 'function\s+GodSystem\.recycleWaistSpaceItemsByMode\s*\(' 'Client helper missing: recycleWaistSpaceItemsByMode'
Require-Text $core 'processWaistAutoRecycle[\s\S]*recycleWaistSpaceItemsByMode\s*\(\s*nil\s*\)' 'SP waist auto recycle must use waist mode helper'

Require-Text $network 'wrap\s*\(\s*"toggleWaistRecycleUnlockMode"[\s\S]*toggleWaistRecycleMode' 'MP bridge must wrap toggleWaistRecycleUnlockMode'
Require-Text $network 'updateWaistAutoRecycle[\s\S]*waistRecycleUnlockMode[\s\S]*recycleWaistAndUnlock[\s\S]*recycleWaist' 'MP waist auto recycle must branch by waist mode'
Require-Text $network 'NotifyMP_"\s*\.\.\s*tostring\s*\(\s*args\.code' 'MP result handler must localize result codes before message fallback'

Require-Text $ui 'Btn_WaistModeOnly' 'Waist page must expose only-recycle mode button key'
Require-Text $ui 'Btn_WaistModeUnlock' 'Waist page must expose recycle-and-list mode button key'
Require-Text $ui 'recycleWaistSpaceItemsByMode\s*\(\s*selected\s*\)' 'Waist primary action must use mode helper'
Require-Text $ui 'recycleWaistSpaceItemsByMode\s*\(\s*nil\s*\)' 'Waist secondary action must use mode helper'
Require-Text $ui 'toggleWaistRecycleUnlockMode\s*\(\s*\)' 'Waist fifth action must toggle waist recycle mode'
Require-Text $ui 'Shortcut_RecycleWaistAll' 'Shortcut label should remain localized'
Require-Text $ui 'recycleWaistSpaceItemsByMode\s*\(\s*nil\s*\)' 'Shortcut sell-waist action must use mode helper'

Require-Text $server 'local\s+function\s+finishCode\s*\(' 'Server must provide finishCode(player, ok, code, args, payload)'
Require-Text $server 'function\s+Commands\.toggleWaistRecycleMode' 'Server handler missing: toggleWaistRecycleMode'
Require-Text $server 'updateWaistAutoRecycle[\s\S]*waistRecycleUnlockMode[\s\S]*recycleWaistAndUnlock[\s\S]*recycleWaist' 'Server waist auto recycle must branch by waist mode'
Require-Text $server 'recycleWaistInternal[\s\S]*finishCode' 'Waist recycle internal must use finishCode'
Require-CommandUsesFinishCode $server 'claimWaist'
Require-CommandUsesFinishCode $server 'upgradeWaist'
Require-CommandUsesFinishCode $server 'toggleWaistAuto'
Require-CommandUsesFinishCode $server 'toggleRecycleMode'
Require-CommandUsesFinishCode $server 'toggleWaistRecycleMode'

$keys = @(
    'Btn_WaistModeOnly',
    'Btn_WaistModeUnlock',
    'Btn_WaistSellAndListSelected',
    'Btn_WaistSellAndListAll',
    'Notify_WaistRecycleModeOnly',
    'Notify_WaistRecycleModeUnlock',
    'NotifyMP_RecycleWaist',
    'NotifyMP_RecycleWaistAndUnlock',
    'NotifyMP_CurrencyNotEnough',
    'NotifyMP_ItemGrantFailed',
    'NotifyMP_RecycleDisabled',
    'NotifyMP_RecycleWaistMissing',
    'NotifyMP_RecycleWaistEmpty',
    'NotifyMP_ClaimWaist',
    'NotifyMP_ClaimWaistPaid',
    'NotifyMP_ClaimWaistOwned',
    'NotifyMP_UpgradeWaist',
    'NotifyMP_UpgradeWaistMax',
    'NotifyMP_UpgradeWaistNoMoney',
    'NotifyMP_WaistAutoDisabled',
    'NotifyMP_WaistAutoUnlocked',
    'NotifyMP_WaistAutoRecycleEnabled',
    'NotifyMP_WaistAutoRecycleDisabled',
    'NotifyMP_WaistRecycleModeOnly',
    'NotifyMP_WaistRecycleModeUnlock',
    'NotifyMP_RecycleModeOnly',
    'NotifyMP_RecycleModeUnlock'
)

foreach ($key in $keys) {
    $translatePattern = '(?m)^\s*IGUI_GodSystem_' + [regex]::Escape($key) + '\s*=\s*".*",\s*$'
    Require-Text $cn $translatePattern "CN translate entry must end with comma: $key"
    Require-Text $ch $translatePattern "CH translate entry must end with comma: $key"

    $fallbackPattern = '(?m)^GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]\s*=\s*"([^"]*)"\s*$'
    $match = [regex]::Match($override, $fallbackPattern)
    if (-not $match.Success) {
        throw "Fallback entry missing: $key"
    }
    if ($match.Groups[1].Value -match '[^\x00-\x7F]') {
        throw "Fallback entry must use ASCII byte escapes: $key"
    }
}

if ($cn -match 'Sell and list selected' -or $ch -match 'Sell and list selected') {
    throw 'Waist sell/list button must not remain English in CN/CH translate files'
}
if ($cn -match '不会解锁商城' -or $ch -match '不会解锁商城') {
    throw 'Waist info must not keep stale no-shop-unlock wording'
}

$traitCommandCount = [regex]::Matches($server, '(?m)^\s*function\s+Commands\.trait\b').Count
if ($traitCommandCount -gt 1) {
    throw "Duplicate Commands.trait handlers found: $traitCommandCount"
}

Write-Output 'Test-GodSystemV11645 passed'
