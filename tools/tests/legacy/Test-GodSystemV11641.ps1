$ErrorActionPreference = 'Stop'

$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Lua = Join-Path $Mod '42\media\lua'

$CorePath = Join-Path $Lua 'client\GodSystem_Core.lua'
$ServerPath = Join-Path $Lua 'server\GodSystem_Server.lua'
$ConfigPath = Join-Path $Lua 'shared\GodSystem_Config.lua'
$AdminPath = Join-Path $Lua 'shared\GodSystem_AdminConfig.lua'
$CnPath = Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt'
$ChPath = Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt'
$OverridePath = Join-Path $Lua 'shared\GodSystem_Localization_Override.lua'
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

$core = Read-Utf8 $CorePath
$server = Read-Utf8 $ServerPath
$config = Read-Utf8 $ConfigPath
$admin = Read-Utf8 $AdminPath
$cn = Read-Utf8 $CnPath
$ch = Read-Utf8 $ChPath
$override = Read-Utf8 $OverridePath
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$readme = Read-Utf8 $ReadmePath

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.41"' 'Config version must be 1.16.41'
Require-Text $rootInfo '(?m)^modversion=1\.16\.41$' 'Root mod.info version must be 1.16.41'
Require-Text $b42Info '(?m)^modversion=1\.16\.41$' 'B42 mod.info version must be 1.16.41'
Require-Text $readme 'v1\.16\.41' 'README must include v1.16.41 notes'

foreach ($text in @($config, $admin, $core, $server)) {
    Require-NoText $text 'MedicalSuppressInfectionCost' 'Runtime code must not expose MedicalSuppressInfectionCost'
    Require-NoText $text 'MedicalSuppressInfectionHours' 'Runtime code must not expose MedicalSuppressInfectionHours'
}

foreach ($text in @($core, $server)) {
    Require-NoText $text 'suppressInfection' 'Runtime code must not contain suppressInfection command/action'
    Require-NoText $text 'ClearInfectionProgress' 'Runtime code must not keep the dangerous progress-only helper'
    Require-NoText $text 'setInfectionTime"\s*,\s*nil\s*,\s*0' 'Runtime code must not set infection time to 0'
    Require-Text $text 'cureInfection' 'Cure infection service must remain available'
    Require-Text $text 'setInfected"\s*,\s*nil\s*,\s*false' 'Cure must clear infected flag'
    Require-Text $text 'setInfectionTime"\s*,\s*nil\s*,\s*-1\.0' 'Cure must set infection time to -1.0'
    Require-Text $text 'setInfectionLevel"\s*,\s*nil\s*,\s*0' 'Cure must clear infection level'
}

foreach ($text in @($cn, $ch, $override)) {
    Require-NoText $text 'Upgrade_Medical_SuppressInfection' 'Suppress localization keys should be removed from active localization'
    Require-NoText $text 'Btn_Medical_SuppressInfection' 'Suppress button localization should be removed from active localization'
    Require-NoText $text 'Notify_Medical_Suppressed' 'Suppress notification localization should be removed from active localization'
    Require-NoText $text 'AdminSetting_MedicalSuppressInfectionCost' 'Suppress admin localization should be removed from active localization'
}

Require-Text $cn 'IGUI_GodSystem_Upgrade_Medical_CureInfection\s*=' 'CN cure localization must remain'
Require-Text $ch 'IGUI_GodSystem_Upgrade_Medical_CureInfection\s*=' 'CH cure localization must remain'
Require-Text $override '\["Upgrade_Medical_CureInfection"\]' 'Fallback cure localization must remain'

$files = Get-ChildItem -LiteralPath $Lua -Recurse -Filter *.lua
foreach ($file in $files) {
    $text = Read-Utf8 $file.FullName
    if ($text.Contains([char]0xFFFD)) {
        throw "Replacement character found: $($file.FullName)"
    }
}

Write-Output 'Test-GodSystemV11641 passed'
