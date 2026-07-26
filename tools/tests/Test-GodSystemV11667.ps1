param(
    [string]$Root = "",
    [string]$ExpectedVersion = "1.16.67",
    [switch]$AllowWorldItemController
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
$client = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageClient.lua')
$context = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageContext.lua')
$ui = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageUI.lua')
$mainUi = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$core = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Core.lua')
$server = Read-Utf8 (Join-Path $Lua 'server\GodSystem_StorageServer.lua')
$serverMain = Read-Utf8 (Join-Path $Lua 'server\GodSystem_Server.lua')
$items = Read-Utf8 (Join-Path $Mod '42\media\scripts\GodSystem_Items.txt')
$source = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
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

if ($AllowWorldItemController) {
    Require-Text $items 'item\s+StorageController[\s\S]{0,500}ItemType\s*=\s*base:normal' 'Successor controller must remain its own normal item'
    Require-Text $items 'item\s+StorageController[\s\S]{0,500}WorldStaticModel\s*=\s*CarBatteryCharger' 'Successor controller ground model is missing'
    Reject-Text $items 'item\s+StorageController[\s\S]{0,500}WorldObjectSprite\s*=\s*recreational_01_16' 'Failed arcade Moveable identity returned'
}
else {
    Require-Text $items 'item\s+StorageController[\s\S]{0,500}ItemType\s*=\s*base:moveable' 'Controller must use the vanilla Moveable lifecycle'
    Require-Text $items 'item\s+StorageController[\s\S]{0,500}WorldObjectSprite\s*=\s*recreational_01_16' 'Controller world sprite is missing'
    Reject-Text $items 'item\s+StorageController[\s\S]{0,500}WorldStaticModel\s*=' 'The failed static charger model must be retired'
}
Reject-Text $context 'BuildingObjects/ISBuildingObject|ISBuildingObject:derive|ControllerPlacement' 'Client-only custom building placement must be removed'
Reject-Text $manager 'IsoCarBatteryCharger\.new|AddSpecialObject' 'The failed charger construction path must be removed'
Require-Text $storage 'MovableDataKey\s*=\s*"movableData"' 'Controller identity must survive vanilla Moveable pickup/place'
Require-Text $core 'GodSystemStorage\.isController\(item\)' 'Controller identity must remain protected from client recycle/list flows after vanilla pickup'
Require-Text $serverMain 'GodSystemStorage\.isController\(item\)' 'Controller identity must remain protected from server recycle/list flows after vanilla pickup'
Require-Text $storage 'function\s+Storage\.discoverNetwork' 'Physical network discovery is missing'
Require-Text $storage 'enqueueSquare\(position\.x\s*-\s*1' 'Cardinal adjacency traversal is missing'
Reject-Text $storage 'enqueueSquare\(position\.x\s*-\s*1,\s*position\.y\s*-\s*1' 'Diagonal traversal must not be added'
Require-Text $storage 'view\.nodeCount\s*>=\s*Storage\.MaxLinks' 'The 128-furniture topology cap is missing'
Require-Text $storage 'function\s+Storage\.getNetworkContainerMarker' 'World-object network marker is missing'
Require-Text $storage 'function\s+Storage\.clearNetworkContainerMarker' 'Moved or dismantled furniture must lose its marker with the old object'
Require-Text $manager 'function\s+Manager\.setNetworkContainer' 'Server-authoritative marker mutation is missing'
Require-Text $server 'function\s+Commands\.setNetworkContainer' 'Multiplayer marker command is missing'
Require-Text $client 'function\s+Client\.setNetworkContainer' 'Client marker transaction is missing'
Require-Text $context 'if\s+not\s+Context\.connectMode\s+then\s+return\s+end' 'World marking must require explicit connection mode'
Require-Text $context 'connectedObjectIds' 'Two-state connection highlighting is missing'
Require-Text $context '0\.12,\s*0\.82,\s*0\.42' 'Connected marker color is missing'
Require-Text $context '0\.12,\s*0\.48,\s*0\.92' 'Disconnected marker color is missing'
Require-Text $mainUi 'Storage_Manual_Title' 'Pinned user-guide row is missing'
Require-Text $mainUi 'self\.mode\s*==\s*"storage"[\s\S]{0,200}toggleConnectMode' 'Storage page connection-mode action is missing'
Reject-Text $ui 'radiusDownButton|radiusUpButton|limitDownButton|limitUpButton' 'Obsolete radius/limit controls must be removed'
Require-Text $manager 'Manager\.connectedNetwork\(network,\s*controllerObject\)' 'Index and mutations must use a freshly discovered connected component'
Require-Text $storage 'for\s+i\s*=\s*1,\s*#slots\s+do' 'All container slots on marked furniture must be included'
Require-Text $manager 'topologyVersion[\s\S]{0,1200}network\.links\s*=\s*\{\}' 'Legacy per-slot links must migrate once and be retired'
Reject-Text ($storage + $manager + $client + $context + $server) 'Events\.OnPlayerUpdate|Events\.EveryTenMinutes|Events\.EveryHours' 'Storage must not add periodic inventory or topology scans'

foreach ($key in @(
    'Storage_Manual_Title', 'Storage_Manual_Detail', 'Storage_ConnectModeOn',
    'Storage_ConnectModeOff', 'Storage_Context_MarkNetwork',
    'Storage_Context_UnmarkNetwork', 'Storage_NodeCount',
    'Storage_ContainerSlotCount', 'Storage_Error_NativePlacement'
)) {
    Require-Text $source ("(?m)^" + [regex]::Escape($key) + ':') "Localization source missing: $key"
    Require-Text $fallback ('GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]') "Fallback missing: $key"
    Require-Text $cn ('IGUI_GodSystem_' + [regex]::Escape($key)) "CN translation missing: $key"
    Require-Text $ch ('IGUI_GodSystem_' + [regex]::Escape($key)) "CH translation missing: $key"
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for v1.16.67 topology validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11667Runtime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'v1.16.67 runtime test failed' }

Write-Output 'Test-GodSystemV11667 passed'
