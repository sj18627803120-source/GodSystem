param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Media = Join-Path $Mod '42\media'
$Lua = Join-Path $Media 'lua'

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Reject-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw $Message }
}

function New-TextFromCodepoints([int[]]$Codepoints) {
    return -join ($Codepoints | ForEach-Object { [char]$_ })
}

$config = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Config.lua')
$core = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Core.lua')
$ui = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$companion = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Companion.lua')
$server = Read-Utf8 (Join-Path $Lua 'server\GodSystem_Server.lua')
$items = Read-Utf8 (Join-Path $Media 'scripts\GodSystem_Items.txt')
$registries = Read-Utf8 (Join-Path $Media 'registries.lua')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$cn = Read-Utf8 (Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt')
$ch = Read-Utf8 (Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.54"' 'Config version must be 1.16.54'
Require-Text $rootInfo '(?m)^modversion=1\.16\.54\r?$' 'Root mod.info version must be 1.16.54'
Require-Text $b42Info '(?m)^modversion=1\.16\.54\r?$' 'B42 mod.info version must be 1.16.54'
Require-Text $workshop '(?m)^description=v1\.16\.54\r?$' 'Workshop metadata must mention v1.16.54'

Require-Text $registries 'ItemBodyLocation\.register\("GodSystem:GodSystemTerminal"\)' 'System terminal registry entry missing'
Require-Text $items 'BodyLocation\s*=\s*GodSystem:GodSystemTerminal\s*,' 'System terminal BodyLocation missing'
Require-Text $items 'CanBeEquipped\s*=\s*GodSystem:GodSystemTerminal\s*,' 'System terminal CanBeEquipped missing'

$levelsMatch = [regex]::Match($config, '(?s)GodSystemConfig\.AutoRecyclerLevels\s*=\s*\{(?<body>.*?)\n\}')
if (-not $levelsMatch.Success) { throw 'Terminal level table missing' }
$levelRows = [regex]::Matches($levelsMatch.Groups['body'].Value, '\{\s*level\s*=\s*(\d+)[^\r\n]*capacity\s*=\s*(\d+)')
if ($levelRows.Count -ne 8) { throw "Expected 8 terminal levels, found $($levelRows.Count)" }
$maxLevel = ($levelRows | ForEach-Object { [int]$_.Groups[1].Value } | Measure-Object -Maximum).Maximum
$maxCapacity = ($levelRows | ForEach-Object { [int]$_.Groups[2].Value } | Measure-Object -Maximum).Maximum
if ($maxLevel -ne 8) { throw "Terminal max level must be 8, found $maxLevel" }
if ($maxCapacity -gt 49) { throw "Terminal capacity must not exceed 49, found $maxCapacity" }
Reject-Text $config 'AutoRecyclerLegacyFullTypes' 'Unpublished legacy waist-container map must be removed'
$aliases = [regex]::Match($config, '(?s)GodSystemConfig\.AutoRecyclerFullTypes\s*=\s*\{(?<body>.*?)\n\}')
Reject-Text $aliases.Groups['body'].Value 'Base\.Bag_FannyPack(?:Front|Back)' 'Vanilla waist bags must not remain system-container aliases'
Reject-Text $core 'migrateSystemSpaceTerminal|terminalMigrationActive|isAutoRecyclerNamedItem|clearAutoRecyclerContainer' 'SP legacy terminal migration residue remains'
Reject-Text $server 'migrateSystemSpaceTerminal|isAutoRecyclerNamedItem' 'MP legacy terminal migration residue remains'
Require-Text $core 'data\.autoRecyclerLevel\s*=\s*math\.max\(1,\s*math\.min\([^\r\n]*AutoRecyclerLevels' 'SP terminal level must be clamped during normalization'
Require-Text $server 'data\.autoRecyclerLevel\s*=\s*math\.max\(1,\s*math\.min\([^\r\n]*AutoRecyclerLevels' 'MP terminal level must be clamped during normalization'

Require-Text $ui 'GS_NON_SELECTABLE_KINDS\[payload\.kind\]' 'List selection must honor non-selectable rows'
foreach ($kind in @('traitHeader', 'attributeHeader', 'lotteryInfo', 'lotteryHeader', 'companionState', 'bankSummary', 'bankLoanSummary', 'adminInfo', 'empty', 'detailLine', 'info', 'history', 'diagnostics', 'lotteryResult')) {
    Require-Text $ui ('(?m)^\s*' + $kind + '\s*=\s*true,?\s*$') "Non-selectable row kind is not registered: $kind"
}
Require-Text $ui 'function\s+GodSystemWindow:getNavPageLayout\b' 'Balanced navigation page-layout helper missing'
Require-Text $ui 'math\.ceil\(count\s*/\s*pageCount\)' 'Navigation pages must balance item counts'
Require-Text $ui 'availableGap|distributedGap' 'Navigation rows must distribute vertical space'

Require-Text $ui 'Attribute_NextLevel' 'Attribute next-level action label missing'
Require-Text $ui 'function\s+GodSystemWindow:showAttributeNextLevelConfirm\b' 'Attribute next-level confirmation helper missing'
Require-Text $ui 'function\s+GodSystemWindow:onAttributeNextLevelConfirm\b' 'Attribute next-level confirmation callback missing'
Require-Text $ui 'getAttributeQuote\([^\r\n]*"targetLevel"[^\r\n]*currentLevel\s*\+\s*1' 'Next-level confirmation must quote exactly one level'
Require-Text $ui 'performAttributePurchase\([^\r\n]*"targetLevel"' 'Confirmed next-level action must reuse targetLevel purchase logic'
Reject-Text $ui 'showAttributeAmountDialog\("targetLevel"' 'Target-level text input must no longer be opened'

Reject-Text $companion 'require\s+["'']ISCoordConversion["'']' 'Invalid ISCoordConversion module require remains'
Require-Text $companion 'if\s+not\s+ISCoordConversion\s+or\s+not\s+ISCoordConversion\.ToScreen\s+then' 'Companion renderer must guard the global coordinate API'
Require-Text $companion 'queueEffectVisual\("guardian"' 'Guardian trigger visual is not queued'
Require-Text $companion 'queueEffectVisual\("blast"' 'Blast visual is not queued'
Require-Text $companion 'kind\s*=\s*kind[\s\S]*x\s*=\s*sourceX[\s\S]*y\s*=\s*sourceY[\s\S]*z\s*=\s*sourceZ' 'Companion effects must snapshot trigger coordinates'
Require-Text $companion 'visual\.kind\s*==\s*"guardian"' 'Guardian render branch missing'
Require-Text $companion 'visual\.kind\s*==\s*"blast"' 'Blast render branch missing'

$waistBag = New-TextFromCodepoints @(0x8170, 0x5305)
foreach ($source in @($localization, $cn, $ch)) {
    if ($source.Contains($waistBag)) { throw 'Live localization still contains an obsolete waist-bag label' }
}
$systemTerminal = New-TextFromCodepoints @(0x7CFB, 0x7EDF, 0x7A7A, 0x95F4, 0x7EC8, 0x7AEF)
$terminalPage = New-TextFromCodepoints @(0x7A7A, 0x95F4, 0x7EC8, 0x7AEF)
$terminalRecycle = New-TextFromCodepoints @(0x7EC8, 0x7AEF, 0x56DE, 0x6536)
$terminalRecycleAndList = New-TextFromCodepoints @(0x7EC8, 0x7AEF, 0x56DE, 0x6536, 0x5E76, 0x4E0A, 0x67B6)
Require-Text $localization ('(?m)^AutoRecycler_Name:\s*"' + [regex]::Escape($systemTerminal) + '"\r?$') 'Terminal item/status name is not unified'
Require-Text $localization ('(?m)^Tab_WaistSpace:\s*"' + [regex]::Escape($terminalPage) + '"\r?$') 'Terminal page name is not unified'
Require-Text $localization ('(?m)^Shortcut_RecycleWaistOnly:\s*"' + [regex]::Escape($terminalRecycle) + '"\r?$') 'Terminal recycle shortcut is not unified'
Require-Text $localization ('(?m)^Shortcut_RecycleWaistAndList:\s*"' + [regex]::Escape($terminalRecycleAndList) + '"\r?$') 'Terminal recycle-and-list shortcut is not unified'

Write-Output 'Test-GodSystemV11654 passed'
