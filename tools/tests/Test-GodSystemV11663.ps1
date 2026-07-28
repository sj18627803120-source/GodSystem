param(
    [string]$Root = "",
    [string]$ExpectedVersion = "1.16.63",
    [int]$ExpectedAdminSettings = 71,
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
    [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}
function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}
function Reject-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw $Message }
}

$config = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Config.lua')
$admin = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_AdminConfig.lua')
$relief = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_TerminalRelief.lua')
$terminal = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_TerminalUpgrades.lua')
$core = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Core.lua')
$network = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Network.lua')
$ui = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$server = Read-Utf8 (Join-Path $Lua 'server\GodSystem_Server.lua')
$protocol = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Protocol.lua')
$items = Read-Utf8 (Join-Path $Mod '42\media\scripts\GodSystem_Items.txt')
$sandbox = Read-Utf8 (Join-Path $Mod '42\media\sandbox-options.txt')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$override = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Localization_Override.lua')
$cn = Read-Utf8 (Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt')
$ch = Read-Utf8 (Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

$escapedVersion = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $escapedVersion + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $escapedVersion + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $escapedVersion + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + $escapedVersion + '\r?$') "Workshop metadata must mention v$ExpectedVersion"

Require-Text $items 'item\s+SystemTerminalRelief[\s\S]{0,500}Hidden\s*=\s*true' 'Relief item must be hidden'
Require-Text $items 'item\s+SystemTerminalRelief[\s\S]{0,500}ItemType\s*=\s*base:food' 'Relief item must use native Food weight behavior'
Require-Text $items 'item\s+SystemTerminalRelief[\s\S]{0,500}HungerChange\s*=\s*-1' 'Relief item needs a negative script hunger baseline'
Require-Text $items 'item\s+SystemTerminalRelief[\s\S]{0,500}CantEat\s*=\s*true' 'Relief item must not be edible'

Require-Text $config 'TerminalReliefFullType\s*=\s*"GodSystem\.SystemTerminalRelief"' 'Relief full type is missing'
Require-Text $config 'TerminalReliefUpgradeCost\s*=\s*2000' 'Default relief price must be 2000'
Require-Text $config 'TerminalReliefPerLevel\s*=\s*5' 'Default relief step must be 5'
Require-Text $config 'TerminalReliefMaxOffset\s*=\s*2000' 'Default maximum relief must be 2000'
Reject-Text $config 'TerminalCapacityHardLimit|TerminalCapacityMaxValue|TerminalCapacityStepAfterLevel8|TerminalCapacityCostAfterLevel8' 'Failed oversized-capacity configuration must be removed'
if (Test-Path -LiteralPath (Join-Path $Lua 'shared\GodSystem_TerminalCapacity.lua')) { throw 'Failed capacity wrapper file must be removed' }

foreach ($key in @('TerminalReliefUpgradeCost', 'TerminalReliefPerLevel', 'TerminalReliefMaxOffset')) {
    Require-Text $admin ('key\s*=\s*"' + $key + '"') "Admin metadata missing: $key"
    Require-Text $sandbox ('GodSystem\.' + $key) "Sandbox option missing: $key"
}
$metaCount = ([regex]::Matches($admin, '\{\s*key\s*=\s*"')).Count
if ($metaCount -ne $ExpectedAdminSettings) { throw "Expected $ExpectedAdminSettings admin settings, found $metaCount" }

foreach ($name in @('getLevel', 'setLevel', 'getOffset', 'getMaxLevel', 'getUpgradeInfo', 'snapshot', 'restore', 'ensureTerminal', 'isReliefItem', 'removeEscapedFromPlayer')) {
    Require-Text $relief ('function\s+GodSystemTerminalRelief\.' + $name + '\s*\(') "Relief API missing: $name"
}
Require-Text $relief 'setHungChange' 'Relief engine must use the native Food hunger-derived weight path'
Require-Text $relief 'getActualWeight' 'Relief engine must verify the actual negative weight'
Require-Text $relief 'setFavorite' 'Relief item must be protected from transfer-all'
Require-Text $relief 'setUnwanted' 'Relief item must be protected from loot-all'
Require-Text $relief 'isUnwanted\(player\)' 'B42.19 unwanted reads must receive the owning player'
Require-Text $relief 'setUnwanted\(player,\s*true\)' 'B42.19 unwanted writes must receive the owning player'
Reject-Text $relief 'DoParam|setScriptItem|ScriptManager.*setActualWeight|Events\.OnTick|Events\.OnPlayerUpdate' 'Relief engine must avoid shared definitions and continuous polling'

Require-Text $terminal 'require\s+"GodSystem_TerminalRelief"' 'Terminal upgrades must load the relief engine'
Reject-Text $terminal 'GodSystemTerminalCapacity\s*[\.:]' 'Terminal upgrades must not retain the failed capacity wrapper'
Require-Text $terminal 'terminalRelief|"relief"' 'Terminal upgrades must expose relief as a third line'
Require-Text ($core + $network + $server) 'terminalRelief' 'SP/MP terminal relief route is incomplete'
Require-Text $core 'applyTerminal\([^\r\n]*gsPlayer\(\)' 'SP relief application must pass the local player to player-scoped item flags'
Require-Text $server 'applyTerminal\([^\r\n]*player\)' 'MP relief application must pass the authoritative player to player-scoped item flags'
Require-Text $ui 'Btn_UpgradeTerminalRelief' 'Terminal page relief button is missing'
Require-Text $ui 'Waist_Relief' 'Terminal page relief status is missing'
Require-Text $server 'sendAddItemToContainer' 'MP relief creation must synchronize the internal item'
Reject-Text $server 'state\.ticks\s*%\s*300[\s\S]{0,300}markAutoRecycler' 'Relief auditing must not add or retain periodic terminal reapplication'

foreach ($blacklist in @('AutoShopBlacklist', 'RecycleBlacklist')) {
    Require-Text $config ($blacklist + '[\s\S]{0,500}\["GodSystem\.SystemTerminalRelief"\]\s*=\s*true') "Relief item missing from $blacklist"
}
Require-Text ($core + $server) 'isReliefItem' 'Recycle paths must explicitly recognize the internal relief item'

foreach ($key in @(
    'Btn_UpgradeTerminalRelief', 'Waist_Relief', 'Waist_ReliefRule',
    'Notify_TerminalReliefApplyFailed', 'NotifyMP_TerminalReliefApplyFailed',
    'AdminSetting_TerminalReliefUpgradeCost', 'AdminSetting_TerminalReliefUpgradeCost_Desc',
    'AdminSetting_TerminalReliefPerLevel', 'AdminSetting_TerminalReliefPerLevel_Desc',
    'AdminSetting_TerminalReliefMaxOffset', 'AdminSetting_TerminalReliefMaxOffset_Desc'
)) {
    Require-Text $localization ("(?m)^" + [regex]::Escape($key) + ':') "Localization source missing: $key"
    Require-Text $override ('GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]') "Lua fallback missing: $key"
    Require-Text $cn ('IGUI_GodSystem_' + [regex]::Escape($key)) "CN translation missing: $key"
    Require-Text $ch ('IGUI_GodSystem_' + [regex]::Escape($key)) "CH translation missing: $key"
}

if (-not $SkipRuntime) {
    $luaExe = Get-Command lua -ErrorAction SilentlyContinue
    if (-not $luaExe) {
        $localLua = Join-Path $env:USERPROFILE 'Tools\Lua51\lua.exe'
        if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
    }
    if ($luaExe) {
        $luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
        & $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11663Runtime.lua') $Lua
        if ($LASTEXITCODE -ne 0) { throw 'v1.16.63 runtime test failed' }
    }
    else {
        Write-Warning 'Lua executable was not found; v1.16.63 runtime validation was skipped.'
    }
}

Write-Output 'Test-GodSystemV11663 passed'
