param(
    [string]$Root = "C:\Users\Admin\Zomboid\Workshop\GodSystem"
)

$ErrorActionPreference = "Stop"
$modRoot = Join-Path $Root "Contents\mods\GodSystem"
$media = Join-Path $modRoot "42\media"
$shared = Join-Path $media "lua\shared"
$client = Join-Path $media "lua\client"

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Assert-Contains([string]$Path, [string]$Needle) {
    $text = Read-Utf8 $Path
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
        throw "Missing expected text in $Path : $Needle"
    }
}

function Assert-NotContains([string]$Text, [string]$Needle, [string]$Context) {
    if ($Text.IndexOf($Needle, [System.StringComparison]::Ordinal) -ge 0) {
        throw "Unexpected text in $Context : $Needle"
    }
}

function Get-LuaFunctionBlock([string]$Text, [string]$Signature) {
    $start = $Text.IndexOf($Signature, [System.StringComparison]::Ordinal)
    if ($start -lt 0) {
        throw "Function block not found: $Signature"
    }
    $next = $Text.IndexOf("`nfunction ", $start + $Signature.Length, [System.StringComparison]::Ordinal)
    if ($next -lt 0) {
        $next = $Text.Length
    }
    return $Text.Substring($start, $next - $start)
}

$coreFile = Join-Path $client "GodSystem_Core.lua"
$uiFile = Join-Path $client "GodSystem_UI.lua"
$configFile = Join-Path $shared "GodSystem_Config.lua"

Assert-Contains $coreFile "function GodSystem.invalidateInventoryCaches"
Assert-Contains $coreFile "function GodSystem.getCachedCurrencyTotal"
Assert-Contains $coreFile "function GodSystem.getCachedBankSummary"
Assert-Contains $coreFile "function GodSystem.getCachedInventoryRecycleGroups"
Assert-Contains $coreFile "function GodSystem.getCachedWaistSpaceRecycleGroups"
Assert-Contains $coreFile "GodSystem.inventoryCache"

Assert-Contains $uiFile "GodSystem.getCachedCurrencyTotal"
Assert-Contains $uiFile "GodSystem.getCachedBankSummary"
Assert-Contains $uiFile "GodSystem.getCachedInventoryRecycleGroups"
Assert-Contains $uiFile "GodSystem.getCachedWaistSpaceRecycleGroups"

$uiText = Read-Utf8 $uiFile
$floatingBlock = Get-LuaFunctionBlock $uiText "function GodSystemFloatingButton:prerender()"
Assert-NotContains $floatingBlock "GodSystem.getCurrencyTotal" "GodSystemFloatingButton:prerender"

$topStatusBlock = Get-LuaFunctionBlock $uiText "function GodSystemWindow:drawTopStatusBar(activeCount)"
Assert-NotContains $topStatusBlock "GodSystem.getCurrencyTotal" "GodSystemWindow:drawTopStatusBar"

Assert-Contains $configFile 'GodSystemConfig.Version = "1.16.32"'
Assert-Contains (Join-Path $modRoot "mod.info") "1.16.32"
Assert-Contains (Join-Path $modRoot "42\mod.info") "1.16.32"
Assert-Contains (Join-Path $Root "workshop.txt") "v1.16.32"

Write-Output "GodSystem v1.16.32 performance cache checks passed."
