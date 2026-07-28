param(
    [string]$Root = "",
    [string]$ExpectedVersion = "1.16.72",
    [switch]$AllowStorageRoutingV11673
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
    [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}
function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}
function Reject-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw $Message }
}

$shared = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_AutoLoader.lua')
$server = Read-Utf8 (Join-Path $Lua 'server\GodSystem_AutoLoaderServer.lua')
$client = Read-Utf8 (Join-Path $Lua 'client\GodSystem_AutoLoaderClient.lua')
$context = Read-Utf8 (Join-Path $Lua 'client\GodSystem_AutoLoaderContext.lua')
$ui = Read-Utf8 (Join-Path $Lua 'client\GodSystem_AutoLoaderUI.lua')
$storageUi = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageUI.lua')
$storageContext = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageContext.lua')
$storageClient = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageClient.lua')
$storageServer = Read-Utf8 (Join-Path $Lua 'server\GodSystem_StorageServer.lua')
$shopUi = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$core = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Core.lua')
$mainServer = Read-Utf8 (Join-Path $Lua 'server\GodSystem_Server.lua')
$depositAction = Read-Utf8 (Join-Path $Lua 'shared\TimedActions\ISGodSystemAutoLoaderDepositAction.lua')
$postAction = Read-Utf8 (Join-Path $Lua 'shared\TimedActions\ISGodSystemAutoLoaderPostReloadAction.lua')
$items = Read-Utf8 (Join-Path $Media 'scripts\GodSystem_Items.txt')
$config = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Config.lua')
$prices = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Prices.lua')
$admin = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_AdminConfig.lua')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$fallback = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Localization_Override.lua')
$cn = Read-Utf8 (Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt')
$ch = Read-Utf8 (Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

$version = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $version + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $version + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $version + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + $version + '\r?$') "Workshop version must be $ExpectedVersion"

$autoLoaderItem = [regex]::Match($items, 'item\s+SystemAutoLoader\s*\{(?<body>[\s\S]*?)\n\s*\}').Groups['body'].Value
if ([string]::IsNullOrWhiteSpace($autoLoaderItem)) { throw 'SystemAutoLoader item definition is missing' }
Require-Text $autoLoaderItem 'ItemType\s*=\s*base:normal' 'SystemAutoLoader must use the B42 normal item type'
Require-Text $autoLoaderItem 'Weight\s*=\s*0\.5' 'SystemAutoLoader weight must be 0.5'
Require-Text $autoLoaderItem 'Icon\s*=\s*SystemAutoLoader' 'SystemAutoLoader icon reference is missing'
Require-Text $prices '\["GodSystem\.SystemAutoLoader"\]\s*=\s*1000' 'SystemAutoLoader price must be 1000'
Require-Text $config 'id\s*=\s*"system_auto_loader"[\s\S]{0,300}featureKey\s*=\s*"EnableAutoLoaderShop"[\s\S]{0,300}GodSystem\.SystemAutoLoader' 'Default shop listing or shop-only switch is missing'
foreach ($blacklist in @('LotteryBlacklist', 'AutoShopBlacklist', 'RecycleBlacklist')) {
    Require-Text $config ($blacklist + '[\s\S]{0,900}\["GodSystem\.SystemAutoLoader"\]\s*=\s*true') "SystemAutoLoader missing from $blacklist"
}
Require-Text $config 'AutoLoaderAmmoCapacity\s*=\s*2000' 'Default per-ammo capacity must be 2000'
Require-Text $admin 'key\s*=\s*"AutoLoaderAmmoCapacity"[\s\S]{0,250}min\s*=\s*100[\s\S]{0,250}max\s*=\s*10000' 'Auto-loader capacity admin range is missing'
Require-Text $admin 'key\s*=\s*"EnableAutoLoaderShop"' 'Auto-loader shop switch is missing'

Require-Text $shared 'MaxSnapshotItems\s*=\s*20000' 'Deposit snapshot limit must be 20000'
Require-Text $shared 'DepositBatchSize\s*=\s*500' 'Deposit action batch size must be 500'
Require-Text $shared 'MaxLoaders\s*=\s*64' 'Carried loader limit must be 64'
Require-Text $shared 'MaxMagazines\s*=\s*256' 'Carried magazine limit must be 256'
Require-Text $shared 'ItemTag\.AMMO' 'Loose-ammo detection must use the B42 ammo tag'
Require-Text $shared 'getAmmoType[\s\S]{0,200}getItemKey' 'Magazine ammo matching must use AmmoType.getItemKey'
Require-Text $shared 'getCurrentAmmoCount' 'Magazine current count API is missing'
Require-Text $shared 'setCurrentAmmoCount' 'Magazine mutation API is missing'
Require-Text $shared 'syncItemFields' 'Magazine field synchronization is missing'
Require-Text $shared 'syncItemModData' 'Loader ModData synchronization is missing'
Require-Text $shared 'math\.min\(15[\s\S]{0,200}math\.ceil\([^\r\n]*/\s*100\)' 'Deposit duration formula is missing'

Require-Text $depositAction 'stopOnWalk\s*=\s*false' 'Deposit must allow ordinary walking'
Require-Text $depositAction 'stopOnRun\s*=\s*true' 'Deposit must stop on running'
Require-Text $depositAction 'stopOnAim\s*=\s*true' 'Deposit must stop on aiming'
Require-Text $depositAction 'getVehicle' 'Deposit must stop after entering a vehicle'
Require-Text $depositAction 'o\.loaderId\s*=\s*loaderId' 'Deposit action loaderId must preserve the network constructor value'
Require-Text $depositAction 'o\.sessionId\s*=\s*sessionId' 'Deposit action sessionId must preserve the network constructor value'
Require-Text $depositAction 'o\.batchIndex\s*=\s*batchIndex' 'Deposit action batchIndex must preserve the network constructor value'
Require-Text $depositAction 'o\.batchCount\s*=\s*batchCount' 'Deposit action batchCount must preserve the network constructor value'
Require-Text $depositAction 'o\.totalCount\s*=\s*totalCount' 'Deposit action totalCount must preserve the network constructor value'
Require-Text $depositAction 'isServer[\s\S]{0,500}runtime\.sessions[\s\S]{0,500}#session\.records' 'Deposit duration must use the authoritative server session size'
Require-Text $postAction 'o\.opId\s*=\s*opId' 'Post-reload action opId must preserve the network constructor value'
Require-Text $client 'BeginAutomaticReload' 'Quick-reload hook is missing'
Require-Text $client 'queueLength' 'Quick-reload hook must compare queue length'
Require-Text $client 'ISGodSystemAutoLoaderPostReloadAction' 'Quick-reload post action is missing'
Require-Text $client 'DepositInterrupted\s*=\s*"AutoLoader_DepositInterrupted"' 'Deposit interruption localization mapping is missing'
Require-Text $client 'function\s+Client\.completeLocalDepositBatch' 'SP deposit settlement bridge is missing'
Require-Text $client 'function\s+Client\.completeLocalPostReload' 'SP quick-reload settlement bridge is missing'
Require-Text $postAction 'completePostReload' 'Post-reload server settlement is missing'

Require-Text $server 'GodSystemAutoLoader' 'Dedicated auto-loader network module is missing'
Require-Text $server 'startDeposit' 'Deposit-session command is missing'
Require-Text $server 'manualFill' 'Manual-fill command is missing'
Require-Text $server 'withdraw' 'Withdraw command is missing'
Require-Text $server 'fingerprint' 'Operation fingerprinting is missing'
Require-Text $context 'OnFillInventoryObjectContextMenu' 'Inventory context menu registration is missing'
Require-Text $ui 'fixedWidth\s*=\s*500' 'Auto-loader window width must be 500'
Require-Text $ui 'fixedHeight\s*=\s*420' 'Auto-loader window height must be 420'
Require-Text $ui 'setOnlyNumbers\(true\)' 'Withdraw count must be numeric'
Require-Text $ui 'drawTextureScaledAspect' 'Ammo icons are missing from the loader list'
Require-Text $ui 'Client\.codeKey' 'Auto-loader UI must resolve result codes through the client mapping'
Require-Text $shopUi 'featureKey[\s\S]{0,180}isFeatureEnabled' 'Shop display must honor per-listing feature switches'
Require-Text $core 'shopItem\.featureKey[\s\S]{0,180}isFeatureEnabled' 'SP purchases must honor per-listing feature switches'
Require-Text $mainServer 'row\.featureKey[\s\S]{0,180}isFeatureEnabled' 'Server purchases must honor per-listing feature switches'
Reject-Text $core 'GodSystemStorage\.isController' 'Client recycle paths must not call the retired storage-controller interface'
Reject-Text $mainServer 'GodSystemStorage\.isController' 'Server recycle paths must not call the retired storage-controller interface'
Require-Text $core 'GodSystemStorage\.isProtected\(item\)' 'Client recycle paths must use the current storage protection interface'
Require-Text $mainServer 'GodSystemStorage\.isProtected\(item\)' 'Server recycle paths must use the current storage protection interface'
Require-Text $storageUi 'function\s+UI\.listRowClip' 'Custom storage rows need explicit viewport clipping'
Require-Text $storageUi 'rowTop\s*=\s*Storage\.number\(y,\s*0\)\s*\+\s*scrollY' 'Storage row clipping must include the active list scroll offset'
Require-Text $storageUi 'setStencilRect\(0,\s*clipY' 'Storage rows must apply their computed visible stencil'
Require-Text $storageUi 'clearStencilRect\(\)' 'Each custom row must clear its temporary stencil like B42 vanilla code'
Reject-Text $storageUi 'restoreListStencil' 'Nested stencils must not be widened with a second setStencilRect call'
Require-Text $storageUi 'function\s+UI\.clearList' 'Reused storage lists need a shared scroll reset helper'
Require-Text $storageUi 'smoothScrollTargetY\s*=\s*nil' 'List rebuilds must clear stale smooth-scroll targets'
Require-Text $storageUi 'originalPrerender' 'Every storage list needs a prerender scrollbar-geometry guard'
Require-Text $storageContext 'RefreshIntervalMs\s*=\s*5000' 'Connection-mode status must refresh every five seconds'
Require-Text $storageContext 'function\s+Context\.onTick' 'Connection-mode periodic refresh handler is missing'
Require-Text $storageContext 'Events\.OnTick\.Add\(Context\.onTick\)' 'Connection-mode refresh must be registered on OnTick'
Require-Text $storageClient 'function\s+Client\.refreshNetworkState' 'A lightweight connectivity refresh path is missing'
Require-Text $storageServer 'function\s+Commands\.networkState' 'The server connectivity refresh command is missing'
Require-Text $shopUi 'depositAllCash[\s\S]{0,300}storageConnectMode' 'The connection-mode shortcut must be appended after existing shortcuts'
Require-Text $shopUi 'storageConnectMode[\s\S]{0,600}toggleConnectMode' 'The connection-mode shortcut action is missing'

$keys = @(
    'AutoLoader_Title', 'AutoLoader_Context', 'AutoLoader_DepositAll', 'AutoLoader_FillAll',
    'AutoLoader_Withdraw', 'AutoLoader_StoredTotal', 'AutoLoader_Empty', 'AutoLoader_Unavailable',
    'AutoLoader_WithdrawAmount', 'AutoLoader_DepositStarted', 'AutoLoader_DepositComplete',
    'AutoLoader_DepositInterrupted', 'AutoLoader_FillSuccess', 'AutoLoader_FillInsufficient',
    'AutoLoader_NoCompatibleMagazine', 'AutoLoader_Error_NotCarried',
    'AdminSetting_AutoLoaderAmmoCapacity', 'AdminSetting_AutoLoaderAmmoCapacity_Desc',
    'AdminSetting_EnableAutoLoaderShop', 'AdminSetting_EnableAutoLoaderShop_Desc'
)
foreach ($key in $keys) {
    Require-Text $localization ('(?m)^' + [regex]::Escape($key) + ':') "Localization key is missing: $key"
    Require-Text $fallback ('GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]') "Lua fallback key is missing: $key"
    Require-Text $cn ('IGUI_GodSystem_' + [regex]::Escape($key)) "CN translation key is missing: $key"
    Require-Text $ch ('IGUI_GodSystem_' + [regex]::Escape($key)) "CH translation key is missing: $key"
}

$iconPath = Join-Path $Media 'textures\Item_SystemAutoLoader.png'
if (-not (Test-Path -LiteralPath $iconPath)) { throw 'SystemAutoLoader icon is missing' }
$iconBytes = [System.IO.File]::ReadAllBytes($iconPath)
if ($iconBytes.Length -lt 100) { throw 'SystemAutoLoader icon is unexpectedly small' }

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for v1.16.72 validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11672Runtime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'v1.16.72 auto-loader runtime test failed' }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11672ServerRuntime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'v1.16.72 auto-loader server runtime test failed' }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11672ClientRuntime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'v1.16.72 auto-loader client runtime test failed' }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11672ContextRuntime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'v1.16.72 inventory context-chain runtime test failed' }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11672UIRuntime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'v1.16.72 storage UI clipping runtime test failed' }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11672StorageRefreshRuntime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'v1.16.72 storage connection refresh runtime test failed' }
if (-not $AllowStorageRoutingV11673) {
    & $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11672StorageRoleRuntime.lua') $Lua
    if ($LASTEXITCODE -ne 0) { throw 'v1.16.72 storage role routing runtime test failed' }
}

Write-Output 'Test-GodSystemV11672 passed'
