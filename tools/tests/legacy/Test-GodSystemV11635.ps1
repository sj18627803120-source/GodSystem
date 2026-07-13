$Root = "C:\Users\Admin\Zomboid\Workshop\GodSystem"
$errors = New-Object System.Collections.Generic.List[string]

function Read-Utf8 {
    param([string]$Path)
    [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Message
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        $script:errors.Add("Missing file: $Path")
        return
    }
    $text = Read-Utf8 -Path $Path
    if ($text -notmatch $Pattern) {
        $script:errors.Add($Message)
    }
}

$mod = Join-Path $Root "Contents\mods\GodSystem"
$config = Join-Path $mod "42\media\lua\shared\GodSystem_Config.lua"
$admin = Join-Path $mod "42\media\lua\shared\GodSystem_AdminConfig.lua"
$protocol = Join-Path $mod "42\media\lua\shared\GodSystem_Protocol.lua"
$core = Join-Path $mod "42\media\lua\client\GodSystem_Core.lua"
$network = Join-Path $mod "42\media\lua\client\GodSystem_Network.lua"
$ui = Join-Path $mod "42\media\lua\client\GodSystem_UI.lua"
$server = Join-Path $mod "42\media\lua\server\GodSystem_Server.lua"
$override = Join-Path $mod "42\media\lua\shared\GodSystem_Localization_Override.lua"
$cn = Join-Path $mod "42\media\lua\shared\Translate\CN\IG_UI_CN.txt"
$ch = Join-Path $mod "42\media\lua\shared\Translate\CH\IG_UI_CH.txt"

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.35"' "Config version is not 1.16.35"
Require-Text (Join-Path $mod "mod.info") 'modversion=1\.16\.35' "root mod.info version is not 1.16.35"
Require-Text (Join-Path $mod "42\mod.info") 'modversion=1\.16\.35' "42 mod.info version is not 1.16.35"

foreach ($name in @(
    "MedicalCheckInfectionCost",
    "MedicalSuppressInfectionCost",
    "MedicalSuppressInfectionHours",
    "MedicalHealInjuriesCost",
    "MedicalCureInfectionCost"
)) {
    Require-Text $config "GodSystemConfig\.$name" "Missing config $name"
    Require-Text $admin $name "Missing admin config $name"
}

Require-Text $protocol 'MedicalService\s*=\s*"medicalService"' "Missing protocol medicalService"
Require-Text $protocol 'medicalService\s*=\s*true' "medicalService missing from command sets"
Require-Text $core 'function\s+GodSystem\.getMedicalStatus' "Missing medical status helper"
Require-Text $core 'function\s+GodSystem\.applyMedicalServiceLocally' "Missing local medical application helper"
Require-Text $core 'function\s+GodSystem\.performMedicalService' "Missing SP medical service"
Require-Text $network 'performMedicalService' "Missing MP medical wrapper"
Require-Text $server 'function\s+Commands\.medicalService' "Missing server medicalService handler"
Require-Text $ui 'confirmMedicalService' "Missing medical confirmation UI"
Require-Text $ui 'GodSystemShortcutWindow' "Missing shortcut window"
Require-Text $ui 'y\s*>=\s*top\s*and\s*\(y\s*\+\s*h\)\s*<=\s*bottom' "Nav visibility still allows partial rows"

foreach ($key in @(
    "Upgrade_Medical_CheckInfection",
    "Upgrade_Medical_SuppressInfection",
    "Upgrade_Medical_HealInjuries",
    "Upgrade_Medical_CureInfection",
    "Confirm_MedicalService",
    "Btn_Shortcuts",
    "Shortcut_Title",
    "NotifyMP_MedicalService",
    "HistoryMP_MedicalService"
)) {
    Require-Text $override $key "Override missing $key"
    Require-Text $cn $key "CN missing $key"
    Require-Text $ch $key "CH missing $key"
}

if ($errors.Count -gt 0) {
    foreach ($err in $errors) {
        Write-Error $err
    }
    exit 1
}

Write-Output "Test-GodSystemV11635 passed"
