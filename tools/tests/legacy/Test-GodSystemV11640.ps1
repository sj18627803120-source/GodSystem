$ErrorActionPreference = 'Stop'

$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Lua = Join-Path $Mod '42\media\lua'

$CorePath = Join-Path $Lua 'client\GodSystem_Core.lua'
$ServerPath = Join-Path $Lua 'server\GodSystem_Server.lua'
$ConfigPath = Join-Path $Lua 'shared\GodSystem_Config.lua'
$AdminPath = Join-Path $Lua 'shared\GodSystem_AdminConfig.lua'
$OverridePath = Join-Path $Lua 'shared\GodSystem_Localization_Override.lua'
$ProtocolPath = Join-Path $Lua 'shared\GodSystem_Protocol.lua'
$CnPath = Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt'
$ChPath = Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt'
$ReadmePath = (Get-ChildItem -LiteralPath $Root -Filter 'README_*.md' | Select-Object -First 1).FullName
if ([string]::IsNullOrWhiteSpace($ReadmePath)) {
    throw 'README upload note file not found'
}

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function New-TextFromCodepoints {
    param([int[]]$Codepoints)
    $chars = foreach ($cp in $Codepoints) { [char]$cp }
    return -join $chars
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
$server = Read-Utf8 $ServerPath
$config = Read-Utf8 $ConfigPath
$admin = Read-Utf8 $AdminPath
$override = Read-Utf8 $OverridePath
$protocol = Read-Utf8 $ProtocolPath
$cn = Read-Utf8 $CnPath
$ch = Read-Utf8 $ChPath
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$readme = Read-Utf8 $ReadmePath

$TextSuppressVirus = New-TextFromCodepoints @(0x538B, 0x5236, 0x75C5, 0x6BD2)
$TextSuppressDesc = New-TextFromCodepoints @(0x6E05, 0x7A7A, 0x5F53, 0x524D, 0x50F5, 0x5C38, 0x75C5, 0x6BD2, 0x8FDB, 0x5EA6)
$TextCureVirus = New-TextFromCodepoints @(0x6CBB, 0x6108, 0x75C5, 0x6BD2)
$TextCureDesc = New-TextFromCodepoints @(0x5F7B, 0x5E95, 0x6E05, 0x9664, 0x50F5, 0x5C38, 0x75C5, 0x6BD2, 0x611F, 0x67D3)
$TextOldSuppressDesc = New-TextFromCodepoints @(0x5EF6, 0x7F13, 0x50F5, 0x5C38, 0x75C5, 0x6BD2, 0x20, 0x7B, 0x31, 0x7D, 0x20, 0x6E38, 0x620F, 0x5C0F, 0x65F6)
$TextOldCureAdmin = New-TextFromCodepoints @(0x6E05, 0x9664, 0x75C5, 0x6BD2, 0x4EF7, 0x683C)

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.40"' 'Config version must be 1.16.40'
Require-Text $rootInfo '(?m)^modversion=1\.16\.40$' 'Root mod.info version must be 1.16.40'
Require-Text $b42Info '(?m)^modversion=1\.16\.40$' 'B42 mod.info version must be 1.16.40'
Require-Text $readme 'v1\.16\.40' 'README must include v1.16.40 notes'

Require-Text $config 'GodSystemConfig\.MedicalCheckInfectionCost\s*=\s*50' 'Infection check price must remain 50'
Require-Text $config 'GodSystemConfig\.MedicalSuppressInfectionCost\s*=\s*200' 'Suppress-virus price must be 200'
Require-Text $config 'GodSystemConfig\.MedicalCureInfectionCost\s*=\s*2000' 'Cure-virus price must be 2000'
Require-NoText $config 'MedicalSuppressInfectionHours' 'Suppress-virus hours config must be removed from active config'
Require-NoText $admin 'MedicalSuppressInfectionHours' 'Admin menu must not expose obsolete suppress-virus hours'

$clientCheckBlock = Extract-Block $core 'if\s+action\s*==\s*"checkInfection"\s+then' 'elseif\s+action\s*==\s*"suppressInfection"' 'Client checkInfection branch missing'
Require-Text $clientCheckBlock 'MedicalCheckInfectionCost\)\s*or\s*50' 'Client infection check default price must remain 50'
Require-Text $clientCheckBlock 'Upgrade_Medical_CheckInfection' 'Client infection check label must remain present'

Require-Text $core 'local\s+function\s+gsMedicalClearInfectionProgress\s*\(' 'Client must have a dedicated infection progress clearing helper'
Require-Text $server 'local\s+function\s+medicalClearInfectionProgress\s*\(' 'Server must have a dedicated infection progress clearing helper'
Require-Text $core 'local\s+function\s+gsMedicalClearBodyPartInfection\s*\(' 'Client cure must clear body-part infection state'
Require-Text $server 'local\s+function\s+medicalClearBodyPartInfection\s*\(' 'Server cure must clear body-part infection state'

$clientSuppress = Extract-Block $core 'local\s+function\s+gsMedicalSuppressInfection\s*\(' '\r?\nlocal\s+function\s+gsMedicalHealPart' 'Client suppress function missing'
Require-Text $clientSuppress 'gsMedicalClearInfectionProgress\s*\(' 'Client suppress must clear infection progress'
Require-NoText $clientSuppress 'setInfected"\s*,\s*nil\s*,\s*false' 'Client suppress must not cure the infection flag'
Require-NoText $clientSuppress 'setIsFakeInfected"\s*,\s*nil\s*,\s*false' 'Client suppress must not clear fake infection flag'
Require-NoText $clientSuppress 'setInfectionMortalityDuration' 'Client suppress must not alter mortality duration'
Require-NoText $clientSuppress 'MedicalSuppressInfectionHours' 'Client suppress must not use obsolete hours'

$serverSuppress = Extract-Block $server 'local\s+function\s+medicalSuppressInfection\s*\(' '\r?\nlocal\s+function\s+medicalHealPart' 'Server suppress function missing'
Require-Text $serverSuppress 'medicalClearInfectionProgress\s*\(' 'Server suppress must clear infection progress'
Require-NoText $serverSuppress 'setInfected"\s*,\s*nil\s*,\s*false' 'Server suppress must not cure the infection flag'
Require-NoText $serverSuppress 'setIsFakeInfected"\s*,\s*nil\s*,\s*false' 'Server suppress must not clear fake infection flag'
Require-NoText $serverSuppress 'setInfectionMortalityDuration' 'Server suppress must not alter mortality duration'
Require-NoText $serverSuppress 'MedicalSuppressInfectionHours' 'Server suppress must not use obsolete hours'

$clientCure = Extract-Block $core 'local\s+function\s+gsMedicalClearInfection\s*\(' '\r?\nlocal\s+function\s+gsMedicalFormatTemplate' 'Client cure function missing'
Require-Text $clientCure 'gsMedicalClearInfectionProgress\s*\(' 'Client cure must clear infection progress'
Require-Text $clientCure 'setInfected"\s*,\s*nil\s*,\s*false' 'Client cure must clear BodyDamage infected flag'
Require-Text $clientCure 'setIsFakeInfected"\s*,\s*nil\s*,\s*false' 'Client cure must clear BodyDamage fake infected flag'
Require-Text $clientCure 'gsMedicalClearBodyPartInfection\s*\(' 'Client cure must clear body-part infection states'
Require-Text $clientCure 'gsMedicalIsInfected\(body\)\s*~=\s*true' 'Client cure must verify infection is gone'

$serverCure = Extract-Block $server 'local\s+function\s+medicalClearInfection\s*\(' '\r?\nlocal\s+function\s+medicalSuppressInfection' 'Server cure function missing'
Require-Text $serverCure 'medicalClearInfectionProgress\s*\(' 'Server cure must clear infection progress'
Require-Text $serverCure 'setInfected"\s*,\s*nil\s*,\s*false' 'Server cure must clear BodyDamage infected flag'
Require-Text $serverCure 'setIsFakeInfected"\s*,\s*nil\s*,\s*false' 'Server cure must clear BodyDamage fake infected flag'
Require-Text $serverCure 'medicalClearBodyPartInfection\s*\(' 'Server cure must clear body-part infection states'
Require-Text $serverCure 'medicalIsInfected\(body\)\s*~=\s*true' 'Server cure must verify infection is gone'

foreach ($block in @($core, $server)) {
    Require-Text $block 'SetInfected"\s*,\s*nil\s*,\s*false' 'Cure path must call bodyPart:SetInfected(false)'
    Require-Text $block 'SetFakeInfected"\s*,\s*nil\s*,\s*false' 'Cure path must call bodyPart:SetFakeInfected(false)'
    Require-Text $block 'setInfectedWound"\s*,\s*nil\s*,\s*false' 'Cure path must clear infected wound flag'
    Require-Text $block 'setWoundInfectionLevel"\s*,\s*nil\s*,\s*-1' 'Cure path must reset wound infection level like vanilla debug command'
}

foreach ($text in @($core, $server)) {
    Require-Text $text 'MedicalSuppressInfectionCost[\s\S]{0,80}(or\s*200|,\s*200\))' 'Suppress-virus runtime default must be 200'
    Require-Text $text 'MedicalCureInfectionCost[\s\S]{0,80}(or\s*2000|,\s*2000\))' 'Cure-virus runtime default must be 2000'
}

Require-Text $protocol 'MedicalService\s*=\s*"medicalService"' 'Protocol must keep medicalService command'
Require-Text $protocol 'medicalService\s*=\s*true' 'Protocol command parity must include medicalService'

foreach ($key in @(
    'Upgrade_Medical_CheckInfection',
    'Upgrade_Medical_SuppressInfection',
    'Upgrade_Medical_SuppressInfectionDesc',
    'Upgrade_Medical_CureInfection',
    'Upgrade_Medical_CureInfectionDesc',
    'Btn_Medical_SuppressInfection',
    'Btn_Medical_CureInfection',
    'AdminSetting_MedicalSuppressInfectionCost',
    'AdminSetting_MedicalCureInfectionCost'
)) {
    Require-Text $override ([regex]::Escape('["' + $key + '"]')) "Fallback localization missing $key"
    Require-Text $cn ("IGUI_GodSystem_" + [regex]::Escape($key) + "\s*=") "CN translation missing $key"
    Require-Text $ch ("IGUI_GodSystem_" + [regex]::Escape($key) + "\s*=") "CH translation missing $key"
}

foreach ($text in @($cn, $ch)) {
    Require-Text $text ([regex]::Escape($TextSuppressVirus)) 'Translate files must rename suppress service'
    Require-Text $text ([regex]::Escape($TextSuppressDesc)) 'Suppress description must say it clears current zombie-virus progress'
    Require-Text $text ([regex]::Escape($TextCureVirus)) 'Translate files must expose cure service'
    Require-Text $text ([regex]::Escape($TextCureDesc)) 'Cure description must say it fully removes zombie infection'
    Require-NoText $text ([regex]::Escape($TextOldSuppressDesc)) 'Old suppress-hours description must be removed'
    Require-NoText $text ([regex]::Escape($TextOldCureAdmin)) 'Admin wording must not describe cure as old clear-virus service'
}

$files = Get-ChildItem -LiteralPath $Lua -Recurse -Filter *.lua
foreach ($file in $files) {
    $text = Read-Utf8 $file.FullName
    if ($text.Contains([char]0xFFFD)) {
        throw "Replacement character found: $($file.FullName)"
    }
}

Write-Output 'Test-GodSystemV11640 passed'
