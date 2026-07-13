param(
    [string]$Root = "C:\Users\Admin\Zomboid\Workshop\GodSystem",
    [string]$HandoffRoot = "C:\Users\Admin\Desktop\PJ\GodSystem_DevHandoff_CN"
)

$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Assert-Contains([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotContains([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) {
        throw $Message
    }
}

function Find-OneFile([string]$Root, [string]$Filter) {
    $file = Get-ChildItem -LiteralPath $Root -File -Filter $Filter | Select-Object -First 1
    if (-not $file) {
        throw "Missing file matching $Filter under $Root"
    }
    return $file.FullName
}

$modRoot = Join-Path $Root "Contents\mods\GodSystem"
$luaRoot = Join-Path $modRoot "42\media\lua"
$sharedRoot = Join-Path $luaRoot "shared"
$clientRoot = Join-Path $luaRoot "client"
$serverRoot = Join-Path $luaRoot "server"

$config = Read-Utf8 (Join-Path $sharedRoot "GodSystem_Config.lua")
$core = Read-Utf8 (Join-Path $clientRoot "GodSystem_Core.lua")
$server = Read-Utf8 (Join-Path $serverRoot "GodSystem_Server.lua")
$rootInfo = Read-Utf8 (Join-Path $modRoot "mod.info")
$b42Info = Read-Utf8 (Join-Path $modRoot "42\mod.info")
$workshop = Read-Utf8 (Join-Path $Root "workshop.txt")
$readme = Read-Utf8 (Find-OneFile $Root "README_*.md")

Assert-Contains $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.34"' "Config version is not 1.16.34"
Assert-Contains $rootInfo 'modversion=1\.16\.34' "Root mod.info version is not 1.16.34"
Assert-Contains $b42Info 'modversion=1\.16\.34' "B42 mod.info version is not 1.16.34"
Assert-Contains $workshop 'v1\.16\.34' "workshop.txt does not mention v1.16.34"
Assert-Contains $readme 'v1\.16\.34' "upload README does not mention v1.16.34"

$eligibilityPath = Join-Path $sharedRoot "GodSystem_ItemEligibility.lua"
if (-not (Test-Path -LiteralPath $eligibilityPath)) {
    throw "Missing GodSystem_ItemEligibility.lua"
}
$eligibility = Read-Utf8 $eligibilityPath
Assert-Contains $eligibility 'function\s+GodSystem\.isEconomicItemAllowed\s*\(' "Missing GodSystem.isEconomicItemAllowed"
Assert-Contains $eligibility 'getScriptManager' "Eligibility helper must use getScriptManager"
Assert-Contains $eligibility 'FindItem' "Eligibility helper must use FindItem"
Assert-Contains $eligibility 'getObsolete' "Eligibility helper must check getObsolete"
Assert-Contains $eligibility 'isHidden' "Eligibility helper must check isHidden"
Assert-Contains $eligibility 'getDisplayCategory' "Eligibility helper must inspect DisplayCategory"
Assert-Contains $eligibility 'isBodyLocation' "Eligibility helper must use body location API"
Assert-Contains $eligibility 'ItemBodyLocation\.ZED_DMG' "Eligibility helper must exclude ZED_DMG body location"
Assert-Contains $eligibility 'ItemBodyLocation\.WOUND' "Eligibility helper must exclude WOUND body location"
Assert-Contains $eligibility 'ItemBodyLocation\.BANDAGE' "Eligibility helper must exclude BANDAGE body location"
Assert-Contains $eligibility 'Base\.ZedDmg_' "Eligibility helper must exclude Base.ZedDmg_"
Assert-Contains $eligibility 'Base\.TestHotDrink' "Eligibility helper must exclude Base.TestHotDrink"
Assert-Contains $eligibility 'Base\.TestMug' "Eligibility helper must exclude Base.TestMug"
Assert-Contains $eligibility 'Base\.TestWaterMug' "Eligibility helper must exclude Base.TestWaterMug"
Assert-Contains $eligibility 'Base\.Animal_Item_Dummy' "Eligibility helper must exclude Base.Animal_Item_Dummy"
Assert-NotContains $eligibility 'lower\(\):find\("bandage"' "Eligibility helper must not exclude by matching bandage in fullType"
Assert-NotContains $eligibility "lower\(\):find\('bandage'" "Eligibility helper must not exclude by matching bandage in fullType"

Assert-Contains $core 'require\s+"GodSystem_ItemEligibility"' "Client core must require GodSystem_ItemEligibility"
Assert-Contains $server 'require\s+"GodSystem_ItemEligibility"' "Server must require GodSystem_ItemEligibility"
Assert-Contains $core 'GodSystem\.isEconomicItemAllowed\(fullType,\s*"lottery"\)' "Client lottery candidate path must use economic eligibility"
Assert-Contains $server 'GodSystem\.isEconomicItemAllowed\(fullType,\s*"lottery"\)' "Server lottery candidate path must use economic eligibility"
Assert-Contains $core 'getShopLotteryCandidates[\s\S]*GodSystem\.isEconomicItemAllowed\(fullType,\s*"lottery"\)' "Old shop lottery client path must use economic eligibility"

$prices = Read-Utf8 (Join-Path $sharedRoot "GodSystem_Prices.lua")
Assert-Contains $prices 'Base\.ZedDmg_BACK_Slash' "Price table sample Base.ZedDmg_BACK_Slash missing; test fixture changed"
Assert-Contains $prices 'Base\.Bandage_LeftUpperArm' "Price table sample Base.Bandage_LeftUpperArm missing; test fixture changed"
Assert-Contains $prices 'Base\.Wound_Chest_Bite_Male' "Price table sample Base.Wound_Chest_Bite_Male missing; test fixture changed"

$handoff = Read-Utf8 (Find-OneFile $HandoffRoot "07_*.md")
Assert-Contains $handoff '1\.16\.34' "Handoff version record does not mention 1.16.34"

Write-Output "GodSystem v1.16.34 lottery eligibility static checks passed."
