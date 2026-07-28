param(
    [string]$Root = "",
    [switch]$SkipRuntime,
    [string]$ExpectedVersion = "1.16.62",
    [switch]$AllowRetiredCapacity,
    [switch]$AllowRetiredCompatibility
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Lua = Join-Path $Mod '42\media\lua'
function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}
function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}
function Reject-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw $Message }
}

$config = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Config.lua')
$terminal = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_TerminalUpgrades.lua')
$capacity = if (-not $AllowRetiredCapacity) { Read-Utf8 (Join-Path $Lua 'shared\GodSystem_TerminalCapacity.lua') } else { "" }
$legacy = if (-not $AllowRetiredCompatibility) { Read-Utf8 (Join-Path $Lua 'shared\GodSystem_LegacyCompressionCleanup.lua') } else { "" }
$variants = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_ShopVariants.lua')
$protocol = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Protocol.lua')
$core = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Core.lua')
$network = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Network.lua')
$ui = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$server = Read-Utf8 (Join-Path $Lua 'server\GodSystem_Server.lua')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$override = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Localization_Override.lua')
$cn = Read-Utf8 (Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt')
$ch = Read-Utf8 (Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + [regex]::Escape($ExpectedVersion) + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + [regex]::Escape($ExpectedVersion) + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + [regex]::Escape($ExpectedVersion) + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + [regex]::Escape($ExpectedVersion) + '\r?$') "Workshop metadata must mention $ExpectedVersion"

if (-not $AllowRetiredCapacity) {
Require-Text $config 'TerminalCapacityHardLimit\s*=\s*2000' 'Terminal hard limit must follow the reference safety boundary'
Require-Text $config 'TerminalCapacityMaxValue\s*=\s*1999' 'The final reachable capacity must be 1999'
Require-Text $config 'TerminalCapacityStepAfterLevel8\s*=\s*5' 'Post-level-8 capacity step must be 5'
Require-Text $config 'TerminalCapacityCostAfterLevel8\s*=\s*1100' 'Post-level-8 price must stay at 1100'
Require-Text $config 'while\s+nextCapacity\s*<=\s*GodSystemConfig\.TerminalCapacityMaxValue' 'Capacity levels must be extended deterministically to the safe maximum'
Reject-Text $config 'TerminalCompressionLevels|AutoRecyclerCompressionLevelKey' 'Active compression configuration must be removed'

$capacityValues = @(10, 15, 20, 25, 30, 35, 42, 49)
$level = 8
$value = 49
while (($value + 5) -le 1999) { $value += 5; $level += 1 }
if ($level -ne 398 -or $value -ne 1999) { throw "Unexpected terminal maximum: level=$level capacity=$value" }
foreach ($expected in $capacityValues) {
    Require-Text $config ("value\s*=\s*" + $expected + '(?:\D|$)') "Missing legacy capacity value: $expected"
}

Require-Text $capacity 'function\s+GodSystemTerminalCapacity\.install\s*\(' 'Capacity override installer is missing'
Require-Text $capacity '(?:index|__index)\.getEffectiveCapacity' 'Effective-capacity wrapper is missing'
Require-Text $capacity '(?:index|__index)\.hasRoomFor' 'Room-check wrapper is missing'
Require-Text $capacity 'GodSystem\.SystemSpaceTerminal' 'Override must identify only the GodSystem terminal'
Require-Text $capacity 'return\s+capturedEffectiveCapacity\s*\(' 'Non-terminal effective capacity must call the captured original method'
Require-Text $capacity 'return\s+capturedHasRoomFor\s*\(' 'Non-terminal room checks must call the captured original method'
Require-Text $capacity 'setmetatable\([^\r\n]+__mode\s*=\s*"k"' 'Runtime container map must use weak keys'
Require-Text $capacity 'MAX_CAPACITY[\s\S]{0,160}TerminalCapacityHardLimit[\s\S]{0,80}2000' 'Override must enforce its own hard boundary'

Require-Text $terminal 'require\s+"GodSystem_TerminalCapacity"' 'Terminal upgrades must load the capacity override'
Require-Text $terminal 'require\s+"GodSystem_LegacyCompressionCleanup"' 'Terminal upgrades must load one-time cleanup'
Require-Text $terminal 'GodSystemTerminalCapacity\.register\s*\(' 'Applied terminals must register their per-instance target'
Require-Text $terminal 'capacity\s*>\s*NATIVE_SAFE_CAPACITY\s+and\s+not\s+GodSystemTerminalCapacity\.install\(\)' 'Oversized upgrades must fail safely when the override is unavailable'
Require-Text $terminal 'math\.min\(capacity,\s*NATIVE_SAFE_CAPACITY\)' 'Native capacity writes must remain below the risky boundary'
Reject-Text $terminal 'compressItem|setActualWeight|setCustomWeight|terminalCompression|"compression"' 'Active terminal module must not compress items'
}
Reject-Text ($core + $network + $ui + $server) 'terminalCompression|upgradeTerminal\("compression"\)|compressionNextCost|compressionDiagnostics' 'Compression routes and UI must be removed'
Reject-Text $core 'OnContainerUpdate|terminalRefreshPending|getAutoRecyclerContentSignature' 'Retired compression polling must be removed'

if (-not $AllowRetiredCompatibility) {
    Require-Text $legacy 'GodSystemCompressionBaseActualWeight' 'Legacy cleanup must recognize old weight metadata'
    Require-Text $legacy 'function\s+GodSystemLegacyCompressionCleanup\.restorePlayerInventory\s*\(' 'One-time player inventory migration is missing'
    Require-Text $legacy 'legacyCompressionMigrationVersion' 'Successful migration must be recorded'
    Require-Text $legacy 'GodSystemLegacyCompressionCleanupVersion' 'Terminal cleanup needs its own O(1) completion marker'
    Require-Text $legacy 'setActualWeight' 'Legacy cleanup must restore saved instance weight'
    Reject-Text $legacy 'DoParam|setScriptItem|definition:setActualWeight|definition:setWeight' 'Legacy cleanup must never modify shared item definitions'
    Require-Text $terminal 'canRestoreLegacyWeights' 'MP clients must not authoritatively restore legacy weights'
    Require-Text $server 'restorePlayerInventory[\s\S]{0,500}sendItemStats' 'Server migration must synchronize restored instances'
}

Require-Text $variants 'function\s+GodSystemShopVariants\.deleteUnlocked\s*\(' 'Shared precise deletion helper is missing'
Require-Text $core 'function\s+GodSystem\.deleteShopItem\s*\(' 'SP deletion API is missing'
Require-Text $protocol 'DeleteShopItem\s*=\s*"deleteShopItem"' 'Deletion protocol command is missing'
Require-Text $network 'wrap\s*\(\s*"deleteShopItem"' 'MP deletion bridge is missing'
Require-Text $server 'function\s+Commands\.deleteShopItem\s*\(' 'Server deletion handler is missing'
Require-Text $server 'GodSystemShopVariants\.deleteUnlocked\s*\(' 'Server must delete by the shared exact-key helper'
Require-Text $ui 'ShopHidden_Delete' 'Hidden manager delete button is missing'
Require-Text $ui 'Confirm_ShopItemDelete' 'Deletion confirmation is missing'
Require-Text $ui 'GodSystem\.deleteShopItem\s*\(' 'Confirmed deletion must call the dedicated API'
if (-not $AllowRetiredCompatibility) {
    Require-Text $server 'function\s+Commands\.removeUnlocked[\s\S]{0,500}setShopItemHidden' 'Old removeUnlocked command must remain a hide-only compatibility alias'
}

foreach ($key in @(
    'ShopHidden_Delete', 'Confirm_ShopItemDelete',
    'Notify_ShopItemDeleted', 'NotifyMP_ShopItemDeleted',
    'History_ShopItemDeleted', 'HistoryMP_ShopItemDeleted'
)) {
    Require-Text $localization ("(?m)^" + [regex]::Escape($key) + ':') "Localization source missing: $key"
    Require-Text $override ('GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]') "Lua fallback missing: $key"
    Require-Text $cn ('IGUI_GodSystem_' + [regex]::Escape($key)) "CN translation missing: $key"
    Require-Text $ch ('IGUI_GodSystem_' + [regex]::Escape($key)) "CH translation missing: $key"
}

if (-not $AllowRetiredCapacity) {
    foreach ($key in @('Waist_CapacityExtended', 'Waist_CapacityRule')) {
        Require-Text $localization ("(?m)^" + [regex]::Escape($key) + ':') "Localization source missing: $key"
        Require-Text $override ('GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]') "Lua fallback missing: $key"
        Require-Text $cn ('IGUI_GodSystem_' + [regex]::Escape($key)) "CN translation missing: $key"
        Require-Text $ch ('IGUI_GodSystem_' + [regex]::Escape($key)) "CH translation missing: $key"
    }
}

if (-not $SkipRuntime -and -not $AllowRetiredCapacity) {
    $luaExe = Get-Command lua -ErrorAction SilentlyContinue
    if (-not $luaExe) {
        $localLua = Join-Path $env:USERPROFILE 'Tools\Lua51\lua.exe'
        if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
    }
    if ($luaExe) {
        $luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
        & $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11662Runtime.lua') $Lua
        if ($LASTEXITCODE -ne 0) { throw 'v1.16.62 runtime test failed' }
    }
    else {
        Write-Warning 'Lua executable was not found; v1.16.62 runtime validation was skipped.'
    }
}

Write-Output 'Test-GodSystemV11662 passed'
