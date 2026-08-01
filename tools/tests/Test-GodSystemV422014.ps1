param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [string]$ExpectedVersion = "42.20.1.4"
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

Write-Output "=== Test-GodSystemV422014: List State And Shop Hidden Batch ==="

$lua = Join-Path $Root "Contents\mods\GodSystem\42\media\lua"
$listStatePath = Join-Path $lua "client\GodSystem_ListState.lua"
$ui = Read-Utf8 (Join-Path $lua "client\GodSystem_UI.lua")
$storageUi = Read-Utf8 (Join-Path $lua "client\GodSystem_StorageUI.lua")
$core = Read-Utf8 (Join-Path $lua "client\GodSystem_Core.lua")
$network = Read-Utf8 (Join-Path $lua "client\GodSystem_Network.lua")
$protocol = Read-Utf8 (Join-Path $lua "shared\GodSystem_Protocol.lua")
$server = Read-Utf8 (Join-Path $lua "server\GodSystem_Server.lua")
$transactionOps = Read-Utf8 (Join-Path $lua "server\GodSystem_TransactionOps.lua")
$rootInfo = Read-Utf8 (Join-Path $Root "Contents\mods\GodSystem\mod.info")
$b42Info = Read-Utf8 (Join-Path $Root "Contents\mods\GodSystem\42\mod.info")
$config = Read-Utf8 (Join-Path $lua "shared\GodSystem_Config.lua")
$items = Read-Utf8 (Join-Path $Root "Contents\mods\GodSystem\42\media\scripts\GodSystem_Items.txt")
$cnItems = Read-Utf8 (Join-Path $lua "shared\Translate\CN\Items_CN.txt")
$chItems = Read-Utf8 (Join-Path $lua "shared\Translate\CH\Items_CH.txt")
$workshop = Read-Utf8 (Join-Path $Root "workshop.txt")
$localization = Read-Utf8 (Join-Path $Root "tools\localization\godsystem_v11645_localization.yml")

Require-Text (Read-Utf8 $listStatePath) 'function\s+GodSystemListState\.capture\s*\(' 'Shared list-state helper must capture a list'
Require-Text (Read-Utf8 $listStatePath) 'function\s+GodSystemListState\.restore\s*\(' 'Shared list-state helper must restore a list'
Require-Text (Read-Utf8 $listStatePath) 'function\s+GodSystemListState\.restoreNextTick\s*\(' 'Shared list-state helper must support one next-tick restore'
Require-Text (Read-Utf8 $listStatePath) 'getScrollHeight\s*\(' 'Shared list-state helper must clamp against B42 list scroll height'
Require-Text $ui 'require\s+"GodSystem_ListState"' 'Main UI must load the shared list-state helper'
Require-Text $ui 'function\s+GodSystemWindow:listStateContext\s*\(' 'Main UI must build an explicit list-state context'
Require-Text $ui 'function\s+GodSystemWindow:captureListState\s*\(|(?:GodSystemListState|ListState)\.capture' 'Main UI actions must capture the primary list state'
Require-Text $ui '(?:GodSystemListState|ListState)\.restoreNextTick' 'Main UI must perform at most one delayed restore'
Require-Text $ui 'self:prepareActionSelection\(payload\)[\s\S]{0,300}setShopItemHidden' 'Single-item shop hide must capture state before mutating'
Require-Text $ui 'selectedVariantKeys' 'Hidden manager must retain multi-selection by variant key'
Require-Text $ui 'drawRectBorder\(list,\s*8,\s*y \+ 10,\s*12,\s*12' 'Hidden manager must render a row checkbox'
Require-Text $ui 'setShopItemsHidden' 'Hidden manager must use the batch hidden API'
Require-Text $storageUi 'require\s+"GodSystem_ListState"' 'Storage UI must load the shared list-state helper'
Require-Text $storageUi 'function\s+GodSystemStorageWindow:captureListStates\s*\(' 'Storage UI must capture all list columns before refresh'
Require-Text $storageUi 'function\s+GodSystemStorageWindow:restoreListStates\s*\(' 'Storage UI must restore all list columns after refresh'
Require-Text $storageUi ':rebuild\(true\)' 'Storage snapshot refresh must preserve existing list state'

Require-Text $protocol 'SetShopItemsHidden\s*=\s*"setShopItemsHidden"' 'Batch hidden protocol command is missing'
Require-Text $protocol 'setShopItemsHidden\s*=\s*true' 'Batch hidden command must be state-refreshing and key-guarded'
Require-Text $core 'function\s+GodSystem\.setShopItemsHidden\s*\(' 'SP batch hidden API is missing'
Require-Text $network 'wrap\s*\(\s*"setShopItemsHidden"' 'MP batch hidden bridge is missing'
Require-Text $network 'setShopItemsHidden[\s\S]{0,600}table\.sort' 'MP batch payload must be sorted before send'
Require-Text $network 'local hiddenCommand\s*=\s*\(Protocol\.C2S[\s\S]{0,500}shopHidden' 'MP batch command must have a stable retry fingerprint'
Require-Text $transactionOps 'kind == "setShopItemsHidden"' 'Server operation ledger must fingerprint batch hidden commands'
Require-Text $server 'function\s+Commands\.setShopItemsHidden\s*\(' 'Server batch hidden handler is missing'
Require-Text $server 'ShopItemBatchTooLarge' 'Server must reject a batch above 500 keys'
Require-Text $server 'GodSystemTransactionOps\.begin' 'Server batch handler must retain operation replay protection'
Require-Text $server 'changedKeys' 'Server batch result must report changed keys'
Require-Text $server 'skippedKeys' 'Server batch result must report skipped keys'

foreach ($key in @("ShopHidden_SelectedCount", "Notify_ShopItemsHidden", "Notify_ShopItemsVisible", "NotifyMP_ShopItemsHidden", "NotifyMP_ShopItemsVisible")) {
    Require-Text $localization ("(?m)^" + [regex]::Escape($key) + ":") "Localization source contains: $key"
}

$versionPattern = [regex]::Escape($ExpectedVersion)
Require-Text $rootInfo ("(?m)^modversion=" + $versionPattern + "\r?$") "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ("(?m)^modversion=" + $versionPattern + "\r?$") "B42 mod.info version must be $ExpectedVersion"
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $versionPattern + '"') "Config version must be $ExpectedVersion"
Require-Text $workshop ("(?m)^description=v" + $versionPattern + "\r?$") "Workshop description must be $ExpectedVersion"
$currencyName = -join @([char]0x7CFB, [char]0x7EDF, [char]0x5E01)
Require-Text $config ('GodSystemConfig\.CurrencyName\s*=\s*"' + [regex]::Escape($currencyName) + '"') 'Currency display name must be Chinese'
foreach ($denomination in @(1, 10, 100)) {
    $name = $currencyName + [char]0xFF08 + $denomination + [char]0xFF09
    $namePattern = [regex]::Escape($name)
    Require-Text $items ('DisplayName\s*=\s*' + $namePattern + ',') "Currency script name must be $denomination"
    Require-Text $localization ('(?m)^ItemName_GodSystem\.SystemCoin' + $denomination + ':\s*"' + $namePattern + '"\r?$') "Currency YAML name must be $denomination"
    Require-Text $cnItems ('ItemName_GodSystem\.SystemCoin' + $denomination + '\s*=\s*"' + $namePattern + '"') "CN currency name must be $denomination"
    Require-Text $chItems ('ItemName_GodSystem\.SystemCoin' + $denomination + '\s*=\s*"' + $namePattern + '"') "CH currency name must be $denomination"
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = Join-Path $env:USERPROFILE "Tools\Lua51\lua.exe"
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw "Lua 5.1 runtime is required for 42.20.1.4 validation" }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot "Test-GodSystemV422014ListStateRuntime.lua") $listStatePath
if ($LASTEXITCODE -ne 0) { throw "42.20.1.4 list-state runtime test failed" }
& $luaPath (Join-Path $PSScriptRoot "Test-GodSystemV422014TransactionRuntime.lua") (Join-Path $lua "server\GodSystem_TransactionOps.lua")
if ($LASTEXITCODE -ne 0) { throw "42.20.1.4 batch-hidden transaction runtime test failed" }

Write-Output "Test-GodSystemV422014 passed for $ExpectedVersion"
