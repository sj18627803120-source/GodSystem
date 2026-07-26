param(
    [string]$Root = "",
    [string]$ExpectedVersion = "1.16.68",
    [switch]$AllowCustomMoveableController
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
$storageUi = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageUI.lua')
$mainUi = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$items = Read-Utf8 (Join-Path $Mod '42\media\scripts\GodSystem_Items.txt')
$source = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$fallback = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Localization_Override.lua')
$cn = Read-Utf8 (Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt')
$ch = Read-Utf8 (Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt')
$cnItems = Read-Utf8 (Join-Path $Lua 'shared\Translate\CN\Items_CN.txt')
$chItems = Read-Utf8 (Join-Path $Lua 'shared\Translate\CH\Items_CH.txt')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

$version = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $version + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $version + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $version + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + $version + '\r?$') "Workshop version must be $ExpectedVersion"

if ($AllowCustomMoveableController) {
    Require-Text $items 'item\s+StorageController[\s\S]{0,500}ItemType\s*=\s*base:moveable' 'Successor controller must use the native Moveable lifecycle'
    Require-Text $items 'item\s+StorageController[\s\S]{0,500}WorldObjectSprite\s*=\s*GodSystem_StorageController_0' 'Successor controller custom sprite is missing'
    Reject-Text $items 'item\s+StorageController[\s\S]{0,500}WorldStaticModel\s*=' 'Failed normal ground-item route returned'
}
else {
    Require-Text $items 'item\s+StorageController[\s\S]{0,500}ItemType\s*=\s*base:normal' 'Controller must remain its own normal inventory/world item'
    Require-Text $items 'item\s+StorageController[\s\S]{0,500}WorldStaticModel\s*=\s*CarBatteryCharger' 'Controller ground model is missing'
    Reject-Text $items 'item\s+StorageController[\s\S]{0,500}ItemType\s*=\s*base:moveable' 'Controller must not inherit an unrelated vanilla Moveable identity'
}
Reject-Text $items 'item\s+StorageController[\s\S]{0,500}WorldObjectSprite\s*=\s*recreational_01_16' 'Dr Oids arcade identity must be removed'

Require-Text $storage 'getWorldObjects' 'Placed normal controller lookup must scan world inventory objects'
Require-Text $storage 'local\s+item\s*=\s*safeCall\(worldObject,\s*"getItem"' 'Controller lookup must read the real world inventory item'
Require-Text $client '(?m)^\s*x\s*=\s*current\.x,' 'SP controller arguments must include x/y/z'
Require-Text $client '(?m)^\s*controllerX\s*=\s*current\.x,' 'MP controller arguments must retain controllerX/Y/Z'
Require-Text $manager 'args\.x\s*~=\s*nil\s+and\s+args\.x\s+or\s+args\.controllerX' 'Manager must accept SP and MP controller coordinate names'

Require-Text $mainUi 'payload\.kind\s*==\s*"storageInfo"' 'System-page storage instructions must populate the detail pane'
Reject-Text $storageUi 'selected\s*=\s*item\.index' 'List selection must not use an index that is assigned only during prerender'
Require-Text $storageUi 'selected\s*=\s*i' 'Stable numeric list selection restoration is missing'

Reject-Text $context 'setHighlightColor\(' 'Connection mode must not modify vanilla object highlight colors'
Reject-Text $context 'setHighlighted\(true\)' 'Connection mode must not enable the blinking vanilla object highlight'
Require-Text $context 'function\s+Context\.renderMarkers' 'Cached connection marker renderer is missing'
Require-Text $context 'Events\.OnPreUIDraw\.Add\(Context\.renderMarkers\)' 'Connection marker render event is missing'
Require-Text $context 'renderer:renderline' 'Connection markers must use lightweight line rendering'
Require-Text $context '0\.12,\s*0\.82,\s*0\.42' 'Connected marker color is missing'
Require-Text $context '0\.12,\s*0\.48,\s*0\.92' 'Disconnected marker color is missing'
Require-Text $context 'Context\.markers\[objectId\]' 'Marker positions must be cached outside the per-frame renderer'
Reject-Text $context 'Events\.OnPlayerUpdate|Events\.EveryTenMinutes|Events\.EveryHours' 'Storage marker rendering must not add periodic scans'

foreach ($key in @(
    'Storage_Manual_Title', 'Storage_Manual_Detail', 'Storage_ControllerState_kit',
    'Storage_ControllerState_installed', 'Storage_Error_NativePlacement'
)) {
    Require-Text $source ("(?m)^" + [regex]::Escape($key) + ':') "Localization source missing: $key"
    Require-Text $fallback ('GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]') "Fallback missing: $key"
    Require-Text $cn ('IGUI_GodSystem_' + [regex]::Escape($key)) "CN translation missing: $key"
    Require-Text $ch ('IGUI_GodSystem_' + [regex]::Escape($key)) "CH translation missing: $key"
}
Require-Text $source '(?m)^ItemName_GodSystem\.StorageController:' 'Controller item name source is missing'
Require-Text $source '(?m)^Tooltip_GodSystem_StorageController:' 'Controller tooltip source is missing'
Require-Text $cnItems 'ItemName_GodSystem\.StorageController' 'CN controller item name is missing'
Require-Text $chItems 'ItemName_GodSystem\.StorageController' 'CH controller item name is missing'
Require-Text $cnItems 'Tooltip_GodSystem_StorageController' 'CN controller tooltip is missing'
Require-Text $chItems 'Tooltip_GodSystem_StorageController' 'CH controller tooltip is missing'

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for v1.16.68 storage validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11668Runtime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'v1.16.68 runtime test failed' }

Write-Output 'Test-GodSystemV11668 passed'
