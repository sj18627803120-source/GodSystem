param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [string]$ExpectedVersion = "42.20.2.1"
)

$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
    Write-Output "  OK: $Message"
}

function Reject-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw $Message }
    Write-Output "  OK: $Message"
}

Write-Output "=== Test-GodSystemV422021: Unified Economy Policy ==="

$lua = Join-Path $Root "Contents\mods\GodSystem\42\media\lua"
$policy = Read-Utf8 (Join-Path $lua "shared\GodSystem_EconomyPolicy.lua")
$config = Read-Utf8 (Join-Path $lua "shared\GodSystem_Config.lua")
$admin = Read-Utf8 (Join-Path $lua "shared\GodSystem_AdminConfig.lua")
$protocol = Read-Utf8 (Join-Path $lua "shared\GodSystem_Protocol.lua")
$variants = Read-Utf8 (Join-Path $lua "shared\GodSystem_ShopVariants.lua")
$core = Read-Utf8 (Join-Path $lua "client\GodSystem_Core.lua")
$network = Read-Utf8 (Join-Path $lua "client\GodSystem_Network.lua")
$ui = Read-Utf8 (Join-Path $lua "client\GodSystem_UI.lua")
$economyUi = Read-Utf8 (Join-Path $lua "client\GodSystem_ItemEconomyUI.lua")
$server = Read-Utf8 (Join-Path $lua "server\GodSystem_Server.lua")
$transactions = Read-Utf8 (Join-Path $lua "server\GodSystem_TransactionOps.lua")
$localization = Read-Utf8 (Join-Path $Root "tools\localization\godsystem_v11645_localization.yml")
$rootInfo = Read-Utf8 (Join-Path $Root "Contents\mods\GodSystem\mod.info")
$b42Info = Read-Utf8 (Join-Path $Root "Contents\mods\GodSystem\42\mod.info")
$workshop = Read-Utf8 (Join-Path $Root "workshop.txt")

Require-Text $policy 'function\s+Policy\.quote\s*\(' 'Economy policy exposes one quote entry point'
foreach ($field in @('eligible', 'category', 'referenceBuy', 'recycleValue', 'conversionValue', 'safeMinimum', 'finalBuy', 'priceSource', 'verificationStatus', 'warnings')) {
    Require-Text $policy ($field + '\s*=') "Economy quote contains $field"
}
Require-Text $policy 'Base\.MoneyBundle[\s\S]{0,180}Base\.Money[\s\S]{0,120}count\s*=\s*100' 'MoneyBundle has a deterministic 100-money conversion route'
Require-Text $policy 'MAX_DEPTH\s*=\s*32' 'Conversion recursion is bounded to 32 levels'
Require-Text $policy 'visiting\[fullType\]' 'Conversion recursion detects cycles'
Require-Text $policy 'getAllRecipes|getAllItems' 'Runtime conversion index scans loaded scripts'
Require-Text $policy 'getReplaceOnUse|getReplaceOnDeplete' 'Runtime conversion index reads replacement rules'
Require-Text $policy 'EconomyUnknownDynamicOutputCount[\s\S]{0,240}UnknownModItemRecycleValue' 'Unknown dynamic items use the configured conservative floor'
Require-Text $config 'UnknownModItemRecycleValue\s*=\s*1' 'Unknown Mod items recycle for one coin by default'
Require-Text $config 'EconomyConversionSafetyMargin\s*=\s*0\.10' 'Conversion safety margin defaults to ten percent'
Require-Text $config 'EconomyUnknownDynamicOutputCount\s*=\s*500' 'Unknown dynamic output guarantee defaults to 500'
Reject-Text $config 'DefaultRecycleValueCap|RecycleValues|RecycleCategoryValues|AutoShopBuyMultiplier|AutoShopMinMarkup|LooseAmmoRecycleUnitDivisor|ShellRecycleUnitDivisor|SmallUnitRecycleDivisor' 'Retired recycle tables and batch-divisor pricing are removed'

Require-Text $core 'require\s+"GodSystem_EconomyPolicy"' 'SP core loads the shared economy policy'
Require-Text $server 'require\s+"GodSystem_EconomyPolicy"' 'MP server loads the shared economy policy'
Require-Text ($core + $server) 'GodSystemEconomyPolicy\.quote' 'SP and MP price reads call the shared quote policy'
Require-Text ($core + $server) 'GodSystemEconomyPolicy\.listingCost' 'SP and MP listing fees call the shared policy'
Reject-Text ($core + $server) 'getRecycleUnitDivisor|unitDivisor' 'No runtime batch-divisor branch remains'
Require-Text $admin 'shopMode\s*==\s*"forced"|shopMode\s*=\s*shopMode' 'Administrator overrides support forced shop mode'
Require-Text $admin 'shopEnabled\s*==\s*false[\s\S]{0,120}shopMode\s*=\s*"disabled"' 'Legacy disabled shop overrides migrate to tri-state mode'
Require-Text $protocol 'AdminEconomyOverrideSet|AdminEconomyOverrideClear' 'Protocol exposes atomic item economy override commands'
Require-Text $server 'Unsafe internal item is read-only' 'Server keeps internal economic items read-only'
Require-Text $server 'Furniture requires a known world sprite' 'Server refuses forced furniture without an exact variant'
Require-Text $variants 'mode\s*~=\s*"forced"' 'Forced global products are excluded from player hidden management'

Require-Text $network 'buyShop[\s\S]{0,180}args\.id[\s\S]{0,120}args\.quantity' 'Shop purchases bind retry IDs to product and quantity'
Require-Text $network 'listOnly[\s\S]{0,180}args\.fullType[\s\S]{0,120}args\.itemId' 'Single-item listings bind retry IDs to the exact item'
Require-Text $transactions 'kind\s*==\s*"buyShop"' 'Server transaction cache fingerprints shop purchases'
Require-Text $transactions 'kind\s*==\s*"listOnlyAutoShop"' 'Server transaction cache fingerprints single-item listings'
Require-Text $server 'txKind\s*=\s*"buyShop"[\s\S]{0,2500}GodSystemTransactionOps\.begin' 'Shop purchase uses persistent idempotence results'
Require-Text $server 'txKind\s*=\s*"listOnlyAutoShop"[\s\S]{0,2500}GodSystemTransactionOps\.begin' 'Single-item listing uses persistent idempotence results'

Require-Text $ui 'GodSystemItemEconomyUI\.open' 'Administrator page opens the item economy window'
Require-Text $economyUi 'local\s+PAGE_SIZE\s*=\s*200' 'Item economy catalog is paged at 200 rows'
Require-Text $economyUi 'EconomyFilter_Category|EconomyFilter_Safety|EconomyFilter_Shop|EconomyFilter_Override' 'Item economy window provides all required filters'
Require-Text $economyUi 'saveEconomyOverride' 'Item economy window submits one combined override'
Reject-Text $economyUi 'Events\.|OnTick|OnPlayerUpdate|OnRender' 'Item economy catalog does not add background or per-frame scans'

foreach ($key in @(
    'EconomyAdmin_Open', 'EconomyAdmin_Title', 'EconomyDetail_Buy', 'EconomyDetail_Recycle',
    'EconomyDetail_SafeMinimum', 'EconomyWarning_Arbitrage', 'AdminSetting_EconomySafetyMargin',
    'AdminSetting_EconomyUnknownOutput', 'NotifyMP_ShopBuySuccess', 'NotifyMP_ShopItemNotFound',
    'NotifyMP_ListOnlySuccess'
)) {
    Require-Text $localization ("(?m)^" + [regex]::Escape($key) + ":") "Localization source contains: $key"
}

$versionPattern = [regex]::Escape($ExpectedVersion)
Require-Text $rootInfo ("(?m)^modversion=" + $versionPattern + "\r?$") "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ("(?m)^modversion=" + $versionPattern + "\r?$") "B42 mod.info version must be $ExpectedVersion"
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $versionPattern + '"') "Config version must be $ExpectedVersion"
Require-Text $workshop ("(?m)^description=v" + $versionPattern + "\r?$") "Workshop headline version must be v$ExpectedVersion"
Require-Text $workshop '(?m)^id=3773949382\r?$' 'Workshop ID remains unchanged'
Require-Text $rootInfo '(?m)^id=GodSystem_CN\r?$' 'Mod ID remains unchanged'

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = Join-Path $env:LOCALAPPDATA "Programs\Lua51\5.1.5\lua.exe"
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw "Lua 5.1 runtime is required for 42.20.2.1 validation" }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot "Test-GodSystemV422021EconomyRuntime.lua") ($Root -replace '\\', '/')
if ($LASTEXITCODE -ne 0) { throw "42.20.2.1 economy runtime test failed" }
& $luaPath (Join-Path $PSScriptRoot "Test-GodSystemV422021TransactionRuntime.lua") (Join-Path $lua "server\GodSystem_TransactionOps.lua")
if ($LASTEXITCODE -ne 0) { throw "42.20.2.1 transaction runtime test failed" }

Write-Output "Test-GodSystemV422021 passed for $ExpectedVersion"
