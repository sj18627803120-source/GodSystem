$ErrorActionPreference = 'Stop'

$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Lua = Join-Path $Mod '42\media\lua'

$CorePath = Join-Path $Lua 'client\GodSystem_Core.lua'
$ServerPath = Join-Path $Lua 'server\GodSystem_Server.lua'
$ConfigPath = Join-Path $Lua 'shared\GodSystem_Config.lua'
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
$server = Read-Utf8 $ServerPath
$config = Read-Utf8 $ConfigPath
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$readme = Read-Utf8 $ReadmePath

$clientCure = Extract-Block $core 'local\s+function\s+gsMedicalClearInfection\s*\(' '\r?\nlocal\s+function\s+gsMedicalFormatTemplate' 'Client cure function missing'
$serverCure = Extract-Block $server 'local\s+function\s+medicalClearInfection\s*\(' '\r?\nlocal\s+function\s+medicalHealPart' 'Server cure function missing'

Require-Text $clientCure 'CharacterStat\.ZOMBIE_INFECTION' 'Client cure must clear CharacterStat.ZOMBIE_INFECTION like the RaccoonCity vaccine'
Require-Text $clientCure 'getStats' 'Client cure must access player stats before clearing zombie infection stat'
Require-Text $clientCure '[:.]set\(CharacterStat\.ZOMBIE_INFECTION,\s*0\)' 'Client cure must set zombie infection stat to 0'
Require-Text $serverCure 'CharacterStat\.ZOMBIE_INFECTION' 'Server cure must clear CharacterStat.ZOMBIE_INFECTION like the RaccoonCity vaccine'
Require-Text $serverCure 'getStats' 'Server cure must access player stats before clearing zombie infection stat'
Require-Text $serverCure '[:.]set\(CharacterStat\.ZOMBIE_INFECTION,\s*0\)' 'Server cure must set zombie infection stat to 0'

foreach ($text in @($core, $server)) {
    Require-NoText $text 'suppressInfection' 'Suppression action must remain removed'
    Require-NoText $text 'MedicalSuppressInfectionCost' 'Suppression config must remain removed'
    Require-NoText $text 'setInfectionTime"\s*,\s*nil\s*,\s*0' 'Runtime code must not set infection time to 0'
    Require-Text $text 'setInfectionTime"\s*,\s*nil\s*,\s*-1\.0' 'Cure must keep setting infection time to -1.0'
    Require-Text $text 'setInfectionMortalityDuration"\s*,\s*nil\s*,\s*-1\.0' 'Cure must keep clearing infection mortality duration'
    Require-Text $text 'setInfected"\s*,\s*nil\s*,\s*false' 'Cure must keep clearing infected flag'
}

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.42"' 'Config version must be 1.16.42'
Require-Text $rootInfo '(?m)^modversion=1\.16\.42$' 'Root mod.info version must be 1.16.42'
Require-Text $b42Info '(?m)^modversion=1\.16\.42$' 'B42 mod.info version must be 1.16.42'
Require-Text $readme 'v1\.16\.42' 'README must include v1.16.42 notes'

$files = Get-ChildItem -LiteralPath $Lua -Recurse -Filter *.lua
foreach ($file in $files) {
    $text = Read-Utf8 $file.FullName
    if ($text.Contains([char]0xFFFD)) {
        throw "Replacement character found: $($file.FullName)"
    }
}

Write-Output 'Test-GodSystemV11642 passed'
