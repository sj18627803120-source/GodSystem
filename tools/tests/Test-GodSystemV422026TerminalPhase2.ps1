param(
    [string]$Root = "",
    [string]$ExpectedVersion = "42.20_2.6",
    [switch]$SkipRuntime
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}

$mod = Join-Path $Root 'Contents\mods\GodSystem'
$lua = Join-Path $mod '42\media\lua'
$config = Read-Utf8 (Join-Path $lua 'shared\GodSystem_Config.lua')
$bridge = Read-Utf8 (Join-Path $lua 'shared\GodSystem_B42JavaCalls.lua')
$admin = Read-Utf8 (Join-Path $lua 'shared\GodSystem_AdminConfig.lua')
$sandbox = Read-Utf8 (Join-Path $mod '42\media\sandbox-options.txt')
$relief = Read-Utf8 (Join-Path $lua 'shared\GodSystem_TerminalRelief.lua')
$upgrades = Read-Utf8 (Join-Path $lua 'shared\GodSystem_TerminalUpgrades.lua')
$core = Read-Utf8 (Join-Path $lua 'client\GodSystem_Core.lua')
$network = Read-Utf8 (Join-Path $lua 'client\GodSystem_Network.lua')
$ui = Read-Utf8 (Join-Path $lua 'client\GodSystem_UI.lua')
$server = Read-Utf8 (Join-Path $lua 'server\GodSystem_Server.lua')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$override = Read-Utf8 (Join-Path $lua 'shared\GodSystem_Localization_Override.lua')
$cn = Read-Utf8 (Join-Path $lua 'shared\Translate\CN\IG_UI_CN.txt')
$ch = Read-Utf8 (Join-Path $lua 'shared\Translate\CH\IG_UI_CH.txt')

$escapedVersion = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $escapedVersion + '"') "Config version must be $ExpectedVersion"

Require-Text $config 'TerminalPhase2CapacityPerLevel\s*=\s*10' 'Phase-two capacity step must be 10'
Require-Text $config 'TerminalPhase2CapacityMaxOffset\s*=\s*5000' 'Phase-two default maximum must be 5000'
Require-Text $config 'TerminalPhase2UpgradeCost\s*=\s*2000' 'Phase-two default price must be 2000'
Require-Text $config 'AutoRecyclerPhase2CapacityLevelKey' 'Phase-two terminal metadata key is missing'
Require-Text $config 'TerminalPhase2OffsetKey' 'Phase-two offset metadata key is missing'
Require-Text $config 'TerminalCompensationOffsetKey' 'Combined compensation metadata key is missing'

foreach ($key in @('TerminalPhase2UpgradeCost', 'TerminalPhase2CapacityMaxOffset')) {
    Require-Text $admin ('key\s*=\s*"' + $key + '"') "Admin metadata missing: $key"
    Require-Text $sandbox ('GodSystem\.' + $key) "Sandbox option missing: $key"
}
Require-Text $admin 'TerminalPhase2CapacityMaxOffset[\s\S]{0,220}max\s*=\s*5000' 'Phase-two admin maximum must not exceed 5000'

foreach ($name in @('getPhase2MaxLevel', 'getPhase2Level', 'setPhase2Level', 'getPhase2Offset', 'getPhase2UpgradeInfo', 'getTotalOffset')) {
    Require-Text $relief ('function\s+GodSystemTerminalRelief\.' + $name + '\s*\(') "Phase-two relief API missing: $name"
}
Require-Text $relief 'autoRecyclerPhase2CapacityLevel' 'Old saves must initialize the phase-two level field'
Require-Text $relief 'TerminalCompensationOffsetKey' 'The helper item must record its combined compensation'
Require-Text $relief 'getTotalOffset\(data\)' 'The helper item must apply both compensation sources together'

Require-Text $upgrades 'terminalPhase2|"phase2"' 'Terminal upgrades must expose phase two'
Require-Text $upgrades 'autoRecyclerPhase2CapacityLevel' 'Terminal upgrades must persist a separate phase-two player field'
Require-Text $upgrades 'applyTerminalPhase2' 'Phase-two must use a dedicated compensation-only apply path'
Require-Text $upgrades 'isPhase2Unlocked' 'Phase-two must require the native capacity line to be maxed'
$phase2Apply = [regex]::Match($upgrades, 'function\s+GodSystemTerminalUpgrades\.applyTerminalPhase2[\s\S]*?\nend\n\nfunction\s+GodSystemTerminalUpgrades\.getAppliedStatus')
if (-not $phase2Apply.Success) { throw 'Unable to isolate the phase-two apply path for native-write checks.' }
if ($phase2Apply.Value -match 'setCapacity|setWeightReduction') { throw 'Phase-two apply path must not write native capacity or reduction.' }

Require-Text $bridge 'getEffectiveCapacity\s*=\s*function' 'Effective terminal capacity must use an explicit B42 bridge call'
Require-Text $upgrades 'effectiveCapacity\s*=\s*readNumberMethod' 'Terminal status must expose the game-reported effective capacity'

Require-Text $core 'upgradeType ~= "phase2"' 'Client terminal command must accept phase two'
Require-Text $core 'getUpgradeInfo\(data, "phase2"\)' 'Terminal status must expose phase-two information'
Require-Text $core 'effectiveCapacity\s*=\s*nativeCapacity\s*\+\s*compensationOffset' 'Final terminal space must add phase two to the live native capacity'
Require-Text $ui 'terminalPhase2' 'The terminal upgrade page must list phase two after native capacity is maxed'
Require-Text $server 'terminalPhase2\s*=\s*"phase2"' 'Server command map must include terminalPhase2'
Require-Text $server 'isPhase2Unlocked' 'Server must validate the phase-two unlock requirement'
Require-Text $server 'applyTerminalPhase2' 'Server phase-two purchases must avoid the native capacity apply path'
Require-Text $server 'terminalExtensionSync' 'Server must send a phase-two-only terminal delta'
Require-Text $server 'GodSystemTransactionOps\.get' 'Phase-two requests must use the existing transaction replay guard'
Require-Text $network 'applyAuthoritativeTerminalExtensionState' 'Client must apply the phase-two delta separately'
Require-Text $network 'terminalExtensionSync' 'Client result handling must recognize the phase-two delta'
$extensionApply = [regex]::Match($network, 'function\s+GodSystemNetwork\.applyAuthoritativeTerminalExtensionState[\s\S]*?\nend\n\nfunction\s+GodSystemNetwork\.updatePendingTerminalExtensionSync')
if (-not $extensionApply.Success) { throw 'Unable to isolate the phase-two client delta path for native-write checks.' }
if ($extensionApply.Value -match 'setCapacity|setWeightReduction') { throw 'Phase-two client delta must not write native capacity or reduction.' }

foreach ($key in @(
    'Btn_UpgradeTerminalPhase2', 'Waist_Phase2', 'Waist_Phase2Rule',
    'Notify_TerminalPhase2Locked', 'Notify_TerminalPhase2ApplyFailed', 'NotifyMP_TerminalPhase2Locked',
    'NotifyMP_TerminalPhase2ApplyFailed', 'AdminSetting_TerminalPhase2UpgradeCost',
    'AdminSetting_TerminalPhase2UpgradeCost_Desc', 'AdminSetting_TerminalPhase2CapacityMaxOffset',
    'AdminSetting_TerminalPhase2CapacityMaxOffset_Desc'
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
        & $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV422026TerminalPhase2Runtime.lua') $lua
        if ($LASTEXITCODE -ne 0) { throw 'Phase-two terminal runtime test failed' }
    }
    else {
        Write-Warning 'Lua executable was not found; phase-two runtime validation was skipped.'
    }
}

Write-Output 'Test-GodSystemV422026TerminalPhase2 passed'
