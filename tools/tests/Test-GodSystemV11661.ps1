param(
    [string]$Root = "",
    [string]$ExpectedVersion = "1.16.61",
    [switch]$SkipRuntime,
    [switch]$AllowRetiredRemoveUnlocked
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Lua = Join-Path $Mod '42\media\lua'

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

$variants = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_ShopVariants.lua')
$protocol = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Protocol.lua')
$config = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Config.lua')
$core = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Core.lua')
$network = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Network.lua')
$ui = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$context = Read-Utf8 (Join-Path $Lua 'client\GodSystem_RecycleContext.lua')
$server = Read-Utf8 (Join-Path $Lua 'server\GodSystem_Server.lua')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$override = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Localization_Override.lua')
$cn = Read-Utf8 (Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt')
$ch = Read-Utf8 (Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

Require-Text $variants 'function\s+GodSystemShopVariants\.getConfiguredKeySet\s*\(' 'Configured shop key set helper is missing'
Require-Text $variants 'function\s+GodSystemShopVariants\.isListingKnown\s*\(' 'Shared listing identity check is missing'
Require-Text $variants 'function\s+GodSystemShopVariants\.setHidden\s*\(' 'Idempotent hidden-state helper is missing'
Require-Text $variants 'function\s+GodSystemShopVariants\.getUnlockedRows\s*\(' 'Visible/all unlocked row helper is missing'
Require-Text $variants 'row\.hidden\s*=\s*row\.hidden\s*==\s*true' 'Old unlocked rows must default to visible'

Require-Text $core 'function\s+GodSystem\.setShopItemHidden\s*\(' 'SP shop hide API is missing'
Require-Text $core 'getUnlockedRows\s*\([^,]+,\s*includeHidden' 'Direct and management views must share hidden filtering'
Reject-Text $core 'function\s+GodSystem\.removeUnlockedShopItem[\s\S]{0,700}unlockedShopItems\[[^\]]+\]\s*=\s*nil' 'Legacy client removal path must never delete a committed listing'

Require-Text $protocol 'SetShopItemHidden\s*=\s*"setShopItemHidden"' 'New hidden-state protocol command is missing'
Require-Text $network 'wrap\s*\(\s*"setShopItemHidden"' 'MP hidden-state client bridge is missing'
Require-Text $network 'listOnlyAutoShopItem[\s\S]{0,240}itemId' 'Single listing command must carry an exact item id'
Require-Text $server 'function\s+Commands\.setShopItemHidden\s*\(' 'Server hidden-state command is missing'
if (-not $AllowRetiredRemoveUnlocked) {
    Require-Text $server 'function\s+Commands\.removeUnlocked[\s\S]{0,500}setShopItemHidden' 'Legacy remove command must delegate to hidden state'
}
Reject-Text $server 'function\s+Commands\.removeUnlocked[\s\S]{0,500}unlockedShopItems\[[^\]]+\]\s*=\s*nil' 'Legacy server command must not delete a committed listing'
Require-Text $server 'listOnlyAutoShop[\s\S]{0,1800}itemId' 'MP listing must re-resolve an exact item instance'
Require-Text $server 'shopById[\s\S]{0,1800}hidden' 'Server direct-buy lookup must reject hidden stale rows'
Require-Text $server 'normalizeUnlocked\s*\(\s*data\s*,\s*GodSystemServer\.configuredShopKeySet' 'MP load must migrate configured and duplicate listings'
Require-Text $server 'getWorldSprite\s*\(\s*added\[j\]\s*\)\s*==\s*grant\[i\]\.worldSprite' 'Furniture purchase must verify the restored world sprite before charging'
Require-Text $server 'local function lotteryCandidates[\s\S]{0,1800}data\.unlockedShopItems' 'Lottery must continue reading every player listing, including hidden rows'
Reject-Text $server 'local function lotteryCandidates[\s\S]{0,1800}hidden\s*~?=' 'Lottery candidates must not filter hidden player listings'

Require-Text $context 'ContextReason_ConfiguredListed' 'Built-in listing skip reason is missing from inventory context menu'
Require-Text $context 'ContextReason_HiddenListed' 'Hidden listing restore guidance is missing from inventory context menu'

Require-Text $ui 'GodSystemShopHiddenWindow' 'Hidden item management window is missing'
Require-Text $ui 'Btn_ShopHiddenManager' 'Shop hidden manager button is missing'
Require-Text $ui 'Menu_HideShopItem' 'Shop right-click hide action is missing'
Require-Text $ui 'ShopHidden_FilterAll[\s\S]*ShopHidden_FilterVisible[\s\S]*ShopHidden_FilterHidden' 'Hidden window status filters are incomplete'
Require-Text $ui 'getUnlockedShopItemsList\s*\(\s*true\s*\)' 'Hidden manager must use the synchronized listing table without scanning inventory'
Reject-Text $ui 'Btn_RemoveUnlocked' 'Active UI must not expose the old delete-unlock action'

foreach ($key in @(
    'Btn_HideUnlocked', 'Btn_ShopHiddenManager', 'Menu_HideShopItem',
    'ShopHidden_Title', 'ShopHidden_FilterAll', 'ShopHidden_FilterVisible', 'ShopHidden_FilterHidden',
    'ShopHidden_Add', 'ShopHidden_Remove', 'Notify_ShopItemHidden', 'Notify_ShopItemVisible',
    'Notify_ShopConfiguredAlreadyListed', 'Notify_ShopHiddenAlreadyListed'
)) {
    Require-Text $localization ("(?m)^" + [regex]::Escape($key) + ':') ("Localization source missing: " + $key)
    Require-Text $override ('GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]') ("Lua fallback missing: " + $key)
    Require-Text $cn ('IGUI_GodSystem_' + [regex]::Escape($key)) ("CN translation missing: " + $key)
    Require-Text $ch ('IGUI_GodSystem_' + [regex]::Escape($key)) ("CH translation missing: " + $key)
}

$versionPattern = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $versionPattern + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $versionPattern + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $versionPattern + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + $versionPattern + '\r?$') "Workshop metadata must mention v$ExpectedVersion"

if (-not $SkipRuntime) {
    $luaExe = Get-Command lua -ErrorAction SilentlyContinue
    if (-not $luaExe) {
        $localLua = Join-Path $env:USERPROFILE 'Tools\Lua51\lua.exe'
        if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
    }
    if ($luaExe) {
        $luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
        & $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11661ShopRuntime.lua') (Join-Path $Lua 'shared\GodSystem_ShopVariants.lua')
        if ($LASTEXITCODE -ne 0) { throw 'v1.16.61 shop runtime test failed' }
    }
    else {
        Write-Warning 'Lua executable was not found; v1.16.61 runtime validation was skipped.'
    }
}

Write-Output 'Test-GodSystemV11661 passed'
