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

Assert-Matches $config 'GodSystemConfig\.Version\s*=\s*"\d+\.\d+\.\d+"' "Config version is not a semantic version"
Assert-Contains $ui 'function GodSystemWindow:resetScrollingListState(list)' "Missing resetScrollingListState helper"
Assert-Matches $ui 'function\s+GodSystemWindow:clearList\(\).*?resetScrollingListState\(self\.list\).*?resetScrollingListState\(self\.activeList\).*?resetScrollingListState\(self\.detailList\)' "clearList does not reset all list scroll states"
Assert-Contains $ui 'list:setYScroll(0)' "List y-scroll is not reset"
Assert-Contains $ui 'list:setScrollHeight(0)' "List scroll height is not reset"
Assert-Contains $ui 'list.smoothScrollTargetY = nil' "Smooth scroll target is not reset"
Assert-Contains $ui 'list.smoothScrollY = nil' "Smooth scroll current value is not reset"
Assert-Contains $ui 'payload.displayText = tostring(text or "")' "List rows do not preserve displayText fallback"
Assert-Contains $ui 'item.text or payload.displayText or payload.label' "List drawing does not use displayText fallback"
Assert-Matches $ui 'function\s+GodSystemWindow:setDetailText\(text\).*?resetScrollingListState\(self\.detailList\)' "Detail list text rebuild does not reset list scroll state"

Write-Output "V11621CheckOK"
