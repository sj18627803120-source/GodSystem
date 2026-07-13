$Root = "C:\Users\Admin\Zomboid\Workshop\GodSystem"
$errors = New-Object System.Collections.Generic.List[string]

function Read-Utf8 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        $script:errors.Add("Missing file: $Path")
        return ""
    }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Message
    )
    $text = Read-Utf8 -Path $Path
    if ($text -notmatch $Pattern) {
        $script:errors.Add($Message)
    }
}

function Require-NotText {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Message
    )
    $text = Read-Utf8 -Path $Path
    if ($text -match $Pattern) {
        $script:errors.Add($Message)
    }
}

$mod = Join-Path $Root "Contents\mods\GodSystem"
$config = Join-Path $mod "42\media\lua\shared\GodSystem_Config.lua"
$core = Join-Path $mod "42\media\lua\client\GodSystem_Core.lua"
$ui = Join-Path $mod "42\media\lua\client\GodSystem_UI.lua"
$server = Join-Path $mod "42\media\lua\server\GodSystem_Server.lua"
$override = Join-Path $mod "42\media\lua\shared\GodSystem_Localization_Override.lua"
$cn = Join-Path $mod "42\media\lua\shared\Translate\CN\IG_UI_CN.txt"
$ch = Join-Path $mod "42\media\lua\shared\Translate\CH\IG_UI_CH.txt"
$workshop = Join-Path $Root "workshop.txt"

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.36"' "Config version is not 1.16.36"
Require-Text (Join-Path $mod "mod.info") 'modversion=1\.16\.36' "root mod.info version is not 1.16.36"
Require-Text (Join-Path $mod "42\mod.info") 'modversion=1\.16\.36' "42 mod.info version is not 1.16.36"
Require-Text $workshop 'v1\.16\.36' "workshop.txt missing v1.16.36 notes"

Require-Text $core 'function\s+GodSystem\.depositAllCashToBankCurrent' "Missing SP depositAllCash helper"
Require-Text $core 'depositAllCash' "Core bank action does not expose depositAllCash"
Require-Text $server 'action\s*==\s*"depositAllCash"' "Server bank handler missing depositAllCash"
Require-Text $server 'getBalance\(player\)' "Server depositAllCash should scan real player cash"

Require-Text $ui 'function\s+GodSystemShortcutWindow:getActions' "Shortcut window missing dynamic action list"
Require-Text $ui 'action\s*=\s*"teleportHome"' "Shortcut window missing home action"
Require-Text $ui 'action\s*=\s*"return"' "Shortcut window missing return action"
Require-Text $ui 'action\s*=\s*"recycleWaistAll"' "Shortcut window missing waist recycle action"
Require-Text $ui 'action\s*=\s*"depositAllCash"' "Shortcut window missing deposit-all-cash action"
Require-Text $ui 'function\s+GodSystemShortcutWindow:performAction' "Shortcut window missing action executor"
Require-Text $ui 'confirmShortcutHomeAction' "Shortcut home/return should keep confirmation"
Require-NotText $ui 'GodSystemUI\.openMode\(button\.internal\)' "Shortcut still opens page modes"
Require-NotText $ui '\{\s*mode\s*=\s*"tasks"' "Shortcut still contains old page-mode buttons"

Require-Text $ui 'navPageIndex' "Left nav missing page index state"
Require-Text $ui 'function\s+GodSystemWindow:onNavPage' "Left nav missing page button handler"
Require-Text $ui 'Nav_PageUp' "Left nav missing page-up button"
Require-Text $ui 'Nav_PageDown' "Left nav missing page-down button"
Require-Text $ui 'updateNavPageButtons' "Left nav missing page button refresh"

foreach ($key in @(
    "Shortcut_Home",
    "Shortcut_Return",
    "Shortcut_RecycleWaistAll",
    "Shortcut_DepositAllCash",
    "Notify_BankDepositAll",
    "Notify_BankDepositAllEmpty",
    "History_BankDepositAll",
    "NotifyMP_BankDepositAll",
    "HistoryMP_BankDepositAll",
    "Nav_PageUp",
    "Nav_PageDown"
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

Write-Output "Test-GodSystemV11636 passed"
