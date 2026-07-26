param(
    [string]$Root = "",
    [string]$ExpectedVersion = "1.16.64",
    [switch]$SkipRuntime,
    [switch]$AllowPhysicalTopology
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
$storage = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Storage.lua')
$manager = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_StorageManager.lua')
$server = Read-Utf8 (Join-Path $Lua 'server\GodSystem_StorageServer.lua')
$serverMain = Read-Utf8 (Join-Path $Lua 'server\GodSystem_Server.lua')
$core = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Core.lua')
$client = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageClient.lua')
$context = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageContext.lua')
$ui = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageUI.lua')
$mainUi = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$items = Read-Utf8 (Join-Path $Mod '42\media\scripts\GodSystem_Items.txt')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$override = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Localization_Override.lua')
$cn = Read-Utf8 (Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt')
$ch = Read-Utf8 (Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

$escapedVersion = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $escapedVersion + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $escapedVersion + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $escapedVersion + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + $escapedVersion + '\r?$') "Workshop metadata must mention v$ExpectedVersion"

if ($AllowPhysicalTopology) {
    Require-Text $items 'item\s+StorageController[\s\S]{0,500}ItemType\s*=\s*base:(normal|moveable)' 'Successor controller must remain a non-container world item'
    Reject-Text $items 'item\s+StorageController[\s\S]{0,500}Capacity\s*=' 'Controller must not expose storage capacity'
    Require-Text $storage 'MaxLinks\s*=\s*128' 'Physical network node cap must remain 128'
    Require-Text $storage 'MaxDepth\s*=\s*32' 'Nested storage depth bound is missing'
    Require-Text $storage 'MaxIndexedItems\s*=\s*20000' 'Index item bound is missing'
    Require-Text $storage 'IndexBatchItems\s*=\s*250' 'Index batch bound is missing'
    Require-Text $storage 'IndexBudgetMs\s*=\s*2' 'Index time budget is missing'
    Require-Text $storage 'function\s+Storage\.discoverNetwork' 'Physical topology discovery is missing'
    Require-Text $storage 'sourceValidator' 'Transactions must revalidate the source'
    Require-Text $storage 'targetValidator' 'Transactions must revalidate the target'
    Require-Text $storage 'restoredToPlayer' 'Second-level recovery is missing'
    Require-Text $storage 'restoredToGround' 'Third-level recovery is missing'
    Require-Text $manager 'Storage\.findNetworkItems' 'Bulk withdrawal must use bounded live lookup'
    Require-Text $server 'Manager\.deposit' 'Server-authoritative deposit route is missing'
    Require-Text $server 'Manager\.withdraw' 'Server-authoritative withdrawal route is missing'
    Require-Text $context 'OnFillWorldObjectContextMenu' 'World controller and marker context menu is missing'
    Require-Text $context 'OnFillInventoryObjectContextMenu' 'Selected-item deposit context menu is missing'
    Reject-Text ($storage + $manager + $server + $client) 'Events\.OnPlayerUpdate|Events\.EveryTenMinutes|Events\.EveryHours' 'Storage network must not add continuous scans'
    Write-Output 'Test-GodSystemV11664 passed (physical topology successor mode)'
    return
}

Require-Text $items 'item\s+StorageController[\s\S]{0,500}ItemType\s*=\s*base:normal' 'Controller must not be a storage container'
Require-Text $items 'item\s+StorageController[\s\S]{0,500}Icon\s*=\s*SystemSpaceTerminal' 'Controller must use the existing black-blue system icon'
Require-Text $items 'item\s+StorageController[\s\S]{0,500}WorldStaticModel\s*=\s*CarBatteryCharger' 'Controller must use the approved vanilla world model'
Reject-Text $items 'item\s+StorageController[\s\S]{0,500}Capacity\s*=' 'Controller must not expose storage capacity'
if (-not (Test-Path -LiteralPath (Join-Path $Mod '42\media\textures\Item_SystemSpaceTerminal.png'))) {
    throw 'Controller icon texture is missing'
}
foreach ($blacklist in @('LotteryBlacklist', 'AutoShopBlacklist', 'RecycleBlacklist')) {
    Require-Text $config ($blacklist + '[\s\S]{0,800}\["GodSystem\.StorageController"\]\s*=\s*true') "Controller missing from $blacklist"
}
Require-Text $config 'TaskItemBlacklist[\s\S]{0,300}\["GodSystem\.StorageController"\]\s*=\s*true' 'Controller must be excluded from task item generation'
Require-Text ($serverMain + $core) 'TaskItemBlacklist' 'Client and server task availability checks must apply the task item blacklist'
$terminalAliases = [regex]::Match($config, '(?s)GodSystemConfig\.AutoRecyclerFullTypes\s*=\s*\{(?<body>.*?)\n\}')
if (-not $terminalAliases.Success) { throw 'Terminal alias table is missing' }
Reject-Text $terminalAliases.Groups['body'].Value '\["GodSystem\.StorageController"\]' 'Controller must remain independent from the wearable terminal'

foreach ($value in @(
    'DefaultRadius\s*=\s*30', 'DefaultMaxLinks\s*=\s*64', 'MaxRadius\s*=\s*60',
    'MaxLinks\s*=\s*128', 'MaxDepth\s*=\s*32', 'MaxIndexedItems\s*=\s*20000',
    'IndexBatchItems\s*=\s*250', 'IndexBudgetMs\s*=\s*2', 'SnapshotGroupChunk\s*=\s*100'
)) {
    Require-Text $storage $value "Storage bound missing: $value"
}
Require-Text $storage 'ObjectLinksKey' 'World-container ModData marker is missing'
Require-Text $storage 'linkId' 'Stable link identity is missing'
Require-Text $storage 'objectId' 'Stable object identity is missing'
Require-Text $storage 'resolveLink' 'Container re-resolution is missing'
Require-Text $storage 'objectMissing' 'Destroyed or replaced containers must go offline'
Require-Text $storage 'sourceChanged' 'Transfers must revalidate the source'
Require-Text $storage 'sourceValidator' 'Transactions must re-resolve their network source before removal'
Require-Text $storage 'targetValidator' 'Transactions must re-resolve their destination before and after insertion'
Require-Text $storage 'restoredToPlayer' 'Second-level recovery is missing'
Require-Text $storage 'restoredToGround' 'Third-level recovery is missing'
Require-Text $storage 'isPoweredColdContainer' 'Powered cold-storage detection is missing'
Require-Text $storage 'controllerSafehouse' 'Safehouse cross-floor range must stop when the controller is moved outside'
Require-Text $storage 'findNetworkItems' 'Bulk withdrawal must use one bounded live lookup instead of rescanning per item'
Reject-Text ($storage + $manager + $server + $client) 'Events\.OnPlayerUpdate|Events\.EveryTenMinutes|Events\.EveryHours' 'Storage network must not add continuous inventory scanning'

Require-Text $manager 'scopeIndex' 'One-network-per-scope index is missing'
Require-Text $manager 'controllerToken' 'Controller revocation token is missing'
Require-Text $manager 'safehouseHasNetwork' 'Duplicate safehouse networks must be rejected'
Require-Text $manager 'snapshotJobs' 'Concurrent snapshots need separate short-lived caches'
Require-Text $manager 'beginOperation' 'Idempotent operation tracking is missing'
Require-Text $manager 'Storage\.findNetworkItems' 'Transactions must revalidate requested instances with one live network scan'
Require-Text $manager 'existingMarker[\s\S]{0,500}clearLinkMarker' 'Moved furniture must be able to clear a stale marker after its old offline link is removed'
Require-Text $manager 'Storage\.itemId' 'Transactions must use stable item IDs'

Require-Text $serverMain 'require\s+"GodSystem_StorageServer"' 'Main server must load only the storage forwarding module'
Require-Text $server 'MODULE\s*=\s*Storage\.Module' 'Storage must use a separate protocol module'
Require-Text $server 'snapshotChunk' 'Grouped snapshots must be chunked'
Require-Text $server 'operationResult' 'Server operation results are missing'
Require-Text $server 'Manager\.deposit' 'Server-authoritative deposit route is missing'
Require-Text $server 'Manager\.withdraw' 'Server-authoritative withdrawal route is missing'
Require-Text $server 'Manager\.linkContainer' 'Server-authoritative connection route is missing'

Require-Text $context 'OnFillWorldObjectContextMenu' 'World controller and link context menu is missing'
Require-Text $context 'OnFillInventoryObjectContextMenu' 'Selected-item deposit context menu is missing'
Require-Text $context 'setHighlighted' 'Temporary connection highlighting is missing'
foreach ($filter in @('category', 'state', 'source', 'modName')) {
    Require-Text $ui ('self\.' + $filter) "Client-side filter is missing: $filter"
}
Require-Text $ui 'sortMode' 'Client-side sorting is missing'
Require-Text $ui 'allowCategories' 'Container allow-category rules are missing'
Require-Text $ui 'denyCategories' 'Container deny-category rules are missing'
Require-Text $ui 'withdrawTargetItemId' 'Withdrawal target selection is missing'
Require-Text $mainUi 'id\s*=\s*"storage"' 'God System storage claim page is missing'
Require-Text $mainUi 'populateStorageNetwork' 'Storage claim page content is missing'

foreach ($key in @(
    'Tab_StorageNetwork', 'Storage_Title', 'Storage_Context_Open', 'Storage_Context_Link',
    'Storage_DepositAll', 'Storage_Withdraw1', 'Storage_ConnectMode',
    'Storage_Error_ControllerExpired', 'Storage_TransferResult'
)) {
    Require-Text $localization ("(?m)^" + [regex]::Escape($key) + ':') "Localization source missing: $key"
    Require-Text $override ('GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]') "Lua fallback missing: $key"
    Require-Text $cn ('IGUI_GodSystem_' + [regex]::Escape($key)) "CN translation missing: $key"
    Require-Text $ch ('IGUI_GodSystem_' + [regex]::Escape($key)) "CH translation missing: $key"
}
Require-Text $localization '(?m)^ItemName_GodSystem\.StorageController:' 'Controller item name is missing from YAML'
Require-Text $localization '(?m)^Tooltip_GodSystem_StorageController:' 'Controller tooltip is missing from YAML'

if (-not $SkipRuntime) {
    $luaExe = Get-Command lua -ErrorAction SilentlyContinue
    if (-not $luaExe) {
        $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
        if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
    }
    if ($luaExe) {
        $luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
        & $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11664Runtime.lua') $Lua
        if ($LASTEXITCODE -ne 0) { throw 'v1.16.64 runtime test failed' }
    }
    else {
        Write-Warning 'Lua executable was not found; v1.16.64 runtime validation was skipped.'
    }
}

Write-Output 'Test-GodSystemV11664 passed'
