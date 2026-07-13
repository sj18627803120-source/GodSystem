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

Assert-Contains $ui 'local function gsSyncScrollingListGeometry(element)' "Missing scrolling-list scrollbar geometry sync helper"
Assert-Matches $ui 'local function gsSetBounds\(element, x, y, width, height\).*?gsSyncScrollingListGeometry\(element\)' "gsSetBounds does not sync reused list scrollbar geometry"
Assert-Matches $ui 'gsSyncScrollingListGeometry\(element\).*?vscroll:setX\(scrollX\).*?vscroll:setHeight\(scrollH\).*?vscroll:updatePos\(\)' "Scrollbar sync does not update x, height, and position"
Assert-Matches $ui 'function\s+GodSystemWindow:resetScrollingListState\(list\).*?gsSyncScrollingListGeometry\(list\)' "List reset does not resync scrollbar geometry"
Assert-Contains $ui 'Btn_RefreshOpenTasksShort' "Task refresh button does not use the short non-truncating label"
Assert-Matches $config 'GodSystemConfig\.Version\s*=\s*"\d+\.\d+\.\d+"' "Config version is not a semantic version"

Write-Output "V11622CheckOK"
