param(
    [string]$Root = "",
    [string]$ExpectedVersion = "1.16.70",
    [switch]$AllowCoreHostStorage
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

$config = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Config.lua')
$items = Read-Utf8 (Join-Path $Media 'scripts\GodSystem_Items.txt')
$storage = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Storage.lua')
$manager = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_StorageManager.lua')
$server = Read-Utf8 (Join-Path $Lua 'server\GodSystem_StorageServer.lua')
$client = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageClient.lua')
$context = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageContext.lua')
$storageUi = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageUI.lua')
$mainUi = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$cnItems = Read-Utf8 (Join-Path $Lua 'shared\Translate\CN\Items_CN.txt')
$chItems = Read-Utf8 (Join-Path $Lua 'shared\Translate\CH\Items_CH.txt')

$version = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $version + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $version + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $version + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + $version + '\r?$') "Workshop version must be $ExpectedVersion"

Require-Text $items 'item\s+StorageController[\s\S]{0,400}ItemType\s*=\s*base:normal' 'Storage core must be a normal inventory item'
Reject-Text $items 'item\s+StorageController[\s\S]{0,400}(WorldObjectSprite|WorldStaticModel|Capacity)\s*=' 'Storage core must not be a world furniture or container item'
Reject-Text $rootInfo '(?m)^(pack|tiledef)=GodSystemStorageController' 'Root mod.info still registers retired controller assets'
Reject-Text $b42Info '(?m)^(pack|tiledef)=GodSystemStorageController' 'B42 mod.info still registers retired controller assets'
foreach ($path in @(
    (Join-Path $Media 'GodSystemStorageController.tiles'),
    (Join-Path $Media 'GodSystemStorageController.tiles.txt'),
    (Join-Path $Media 'texturepacks\GodSystemStorageController.pack'),
    (Join-Path $Root 'tools\assets\storage-controller\Build-StorageControllerAssets.ps1')
)) {
    if (Test-Path -LiteralPath $path) { throw "Retired controller asset remains: $path" }
}

Require-Text $storage 'CoreHostKey\s*=\s*"GodSystemStorageCoreHostV1"' 'Core-host ModData key is missing'
Require-Text $storage 'function\s+Storage\.lockCoreHost' 'Core-host capacity transaction is missing'
Require-Text $storage 'function\s+Storage\.unlockCoreHost' 'Core-host capacity restoration is missing'
Require-Text $storage 'function\s+Storage\.enforceCoreHostLock' 'Core-host reload calibration is missing'
Require-Text $storage 'local\s+isHost\s*=\s*Storage\.isCoreHost\(row\.object\)' 'Core host must be recognized during topology discovery'
if ($AllowCoreHostStorage) {
    Require-Text $storage 'CoreHostVersion\s*=\s*2' 'Core-host storage migration version is missing'
    Require-Text $storage 'capacityMode\s*=\s*"networkStorage"' 'Core hosts must use normal network-storage capacity mode'
    Require-Text $storage 'isCoreHost\s*=\s*isHost' 'Core-host links must remain distinguishable while participating in storage'
}
else {
    Require-Text $storage 'container:setCapacity\(expected\)' 'Core capacity must use the native ItemContainer setter'
    Require-Text $storage 'if\s+not\s+isHost\s+then' 'Core host storage slots must be excluded from indexing'
}
Reject-Text $storage 'function\s+Storage\.findNearbyWorldController' 'Active nearby world-controller scanning returned'

foreach ($name in @('coreStatus', 'claimCore', 'installCore', 'retrieveCore', 'resolveCoreHost', 'calibrateLoadedSquare')) {
    Require-Text $manager ('function\s+Manager\.' + $name) "Manager.$name is missing"
}
Require-Text $manager 'state\s*==\s*"migrationPending"' 'v1.16.69 installed-controller migration is missing'
Require-Text $manager 'pendingCoreUnlock' 'Unloaded old-host recovery is missing'
Require-Text $manager 'if\s+not\s+square\s+then\s+return\s+nil,\s+nil,\s+false\s+end' 'Unloaded host must not be treated as deleted'
Reject-Text $manager 'function\s+Manager\.installController' 'Retired controller installer remains active'
Reject-Text $manager 'function\s+Manager\.reclaimController' 'Retired controller reclaim remains active'
Reject-Text $manager 'function\s+Manager\.resolveController' 'Retired world-controller resolver remains active'

foreach ($command in @('coreStatus', 'claimCore', 'installCore', 'retrieveCore')) {
    Require-Text $server ('function\s+Commands\.' + $command) "Server command $command is missing"
}
Require-Text $server 'Events\.LoadGridsquare' 'Server-side host reload calibration hook is missing'
Require-Text $client 'function\s+Client\.installCore' 'Client core installation transaction is missing'
Require-Text $client 'function\s+Client\.retrieveCore' 'Client core retrieval transaction is missing'
Require-Text $context 'Storage_Context_InstallCore' 'World menu core-install option is missing'
Require-Text $context 'Storage_Context_RetrieveCore' 'World menu core-retrieve option is missing'
Require-Text $context 'marker\.coreHost' 'Connection markers must distinguish the core host'
Require-Text $context 'red,\s+green,\s+blue\s*=\s*0\.12,\s*0\.82,\s*0\.42' 'Core host marker must be green'
Require-Text $context 'red,\s+green,\s+blue\s*=\s*0\.12,\s*0\.48,\s*0\.92' 'Ordinary network marker must be blue'
Reject-Text $storageUi 'setConnectMode\(false\)' 'Closing the storage window must not disable connection mode'
Reject-Text $mainUi 'self\.mode\s*==\s*"storage"[\s\S]{0,200}setConnectMode\(false\)' 'Leaving the storage page must not disable connection mode'

foreach ($key in @(
    'ItemName_GodSystem.StorageController',
    'Tooltip_GodSystem_StorageController',
    'Storage_Context_InstallCore',
    'Storage_Context_RetrieveCore',
    'Storage_Error_CapacityRestoreFailed'
)) {
    Require-Text $localization ('(?m)^' + [regex]::Escape($key) + ':') "Localization key is missing: $key"
}
if (-not $AllowCoreHostStorage) {
    Require-Text $localization '(?m)^Storage_Error_CoreHostNotEmpty:' 'Legacy empty-host localization key is missing'
}
Require-Text $cnItems 'ItemName_GodSystem\.StorageController\s*=' 'CN core item localization was not regenerated'
Require-Text $chItems 'ItemName_GodSystem\.StorageController\s*=' 'CH core item localization was not regenerated'

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for v1.16.70 storage validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
$runtimeArgs = @((Join-Path $PSScriptRoot 'Test-GodSystemV11670Runtime.lua'), $Lua)
if ($AllowCoreHostStorage) { $runtimeArgs += 'allowCoreHostStorage' }
& $luaPath @runtimeArgs
if ($LASTEXITCODE -ne 0) { throw 'v1.16.70 runtime test failed' }

Write-Output 'Test-GodSystemV11670 passed'
