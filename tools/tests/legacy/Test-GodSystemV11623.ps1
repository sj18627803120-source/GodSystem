param(
    [string]$Root = "C:\Users\Admin\Zomboid\Workshop\GodSystem"
)

$ErrorActionPreference = "Stop"

$uiPath = Join-Path $Root "Contents\mods\GodSystem\42\media\lua\client\GodSystem_UI.lua"
$configPath = Join-Path $Root "Contents\mods\GodSystem\42\media\lua\shared\GodSystem_Config.lua"

if (-not (Test-Path -LiteralPath $uiPath)) {
    throw "Missing UI file: $uiPath"
}
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Missing config file: $configPath"
}

$ui = [System.IO.File]::ReadAllText($uiPath, [System.Text.Encoding]::UTF8)
$config = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8)

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Message
    )
    if (-not $Text.Contains($Needle)) {
        throw $Message
    }
}

function Assert-Matches {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )
    if (-not [regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        throw $Message
    }
}

Assert-Contains $ui 'local function gsSafeScrollingListPrerender(self)' "Missing GodSystem safe scrolling-list prerender"
Assert-Contains $ui 'local function gsInstallSafeScrollingListPrerender(list)' "Missing safe prerender installer"
Assert-Contains $ui 'local gsOriginalScrollingListPrerender = ISScrollingListBox.prerender' "Missing original scrolling-list prerender capture"
Assert-Matches $ui 'gsSafeScrollingListPrerender\(self\).*?gsSyncScrollingListGeometry\(self\).*?gsOriginalScrollingListPrerender\(self\).*?gsSyncScrollingListGeometry\(self\)' "Safe prerender does not resync geometry before and after vanilla prerender"
Assert-Matches $ui 'gsInstallSafeScrollingListPrerender\(self\.list\).*?gsInstallSafeScrollingListPrerender\(self\.detailList\).*?gsInstallSafeScrollingListPrerender\(self\.activeList\)' "Safe prerender is not installed on all GodSystem list boxes"
Assert-Contains $config 'GodSystemConfig.Version = "1.16.23"' "Config version is not 1.16.23"

Write-Output "V11623CheckOK"
