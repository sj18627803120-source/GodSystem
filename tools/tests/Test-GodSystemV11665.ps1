param(
    [string]$Root = "",
    [string]$ExpectedVersion = "1.16.65",
    [switch]$SkipRuntime,
    [switch]$AllowMoveableController
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
$client = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageClient.lua')
$context = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageContext.lua')
$placementPath = Join-Path $Lua 'client\GodSystem_StoragePlacement.lua'
$placement = if (Test-Path -LiteralPath $placementPath) {
    Read-Utf8 $placementPath
}
else {
    $context
}
$mainUi = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$fallback = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Localization_Override.lua')
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

if ($AllowMoveableController) {
    Require-Text $storage 'MovableDataKey\s*=\s*"movableData"' 'Moveable controller identity migration is missing'
    Require-Text $manager 'function\s+Manager\.reclaimController' 'Controller reclaim transaction is missing'
    Require-Text $client 'beginStandalone\("claimController"' 'Claim requests need stable operation IDs'
    Require-Text $client 'beginStandalone\("reclaimController"' 'Reclaim requests need stable operation IDs'
    Require-Text $context 'Storage_Context_Reclaim' 'World reclaim context option is missing'
    Reject-Text ($manager + $context) 'IsoCarBatteryCharger\.new|ISBuildingObject:derive' 'Retired controller installation path returned'
    foreach ($command in @('controllerStatus', 'claimController', 'reclaimController')) {
        Require-Text $server ('function Commands\.' + $command) "Storage server command missing: $command"
    }
    Write-Output 'Test-GodSystemV11665 passed (Moveable successor mode)'
    return
}

Require-Text $storage 'ControllerRecoveryCost\s*=\s*2000' 'Controller recovery cost must be 2000'
Require-Text $storage 'ControllerInstalledKey' 'Installed controller marker is missing'
Require-Text $storage 'getSpecialObjects' 'Installed controller lookup must scan special world objects'
Require-Text $storage 'getWorldObjects' 'Legacy dropped controllers must remain discoverable'
Require-Text $storage 'getInstalledControllerIdentity' 'Installed controller identity helper is missing'

Require-Text $manager 'controllerClaimedOnce' 'First-free claim state is not persisted'
Require-Text $manager 'state\s*==\s*"kit"' 'Duplicate claim must reject an owned controller kit'
Require-Text $manager 'controllerInstalled' 'Duplicate claim must reject an installed controller'
Require-Text $manager 'currencyNotEnough' 'Paid recovery must reject insufficient currency'
Require-Text $manager 'cleanupInventoryControllers' 'Strict inventory duplicate cleanup is missing'
Require-Text $manager 'itemNetworkId[\s\S]{0,200}networkId' 'Duplicate cleanup must match the same storage network'
Require-Text $manager 'IsoCarBatteryCharger\.new' 'Installed controller must use the native fixed charger world object'
Require-Text $manager 'square:AddSpecialObject' 'Installed controller must be added as a fixed special object'
Require-Text $manager 'removeInventoryItem\(source,\s*item\)' 'The exact kit must be consumed only by the install transaction'
Require-Text $manager 'function Manager\.reclaimController' 'Installed controller reclaim transaction is missing'
Require-Text $manager 'setControllerState\(network,\s*"installed"' 'Install state persistence is missing'
Require-Text $manager 'setControllerState\(network,\s*"kit"' 'Reclaim state persistence is missing'
Reject-Text $manager 'getCell\(\):getGridSquare[\s\S]{0,600}for\s+x\s*=' 'Controller cleanup must not scan the whole world'

Require-Text $placement 'ISBuildingObject:derive\("GodSystemStorage(?:Controller)?Placement"\)' 'Furniture-style placement cursor is missing'
Require-Text $placement 'RenderGhostTileColor' 'Placement cursor must show a valid/invalid preview'
Require-Text $placement 'ControllerPlacementDistance' 'Client placement distance check is missing'
Require-Text $placement '(?:Client|GodSystemStorageClient)\.installController' 'Placement cursor must use the storage transaction'

Require-Text $context 'Storage_Context_Install' 'Inventory install context option is missing'
Require-Text $context 'Storage_Context_Reclaim' 'World reclaim context option is missing'
Require-Text $context 'removeOptionByName[\s\S]{0,200}ContextMenu_CarBatteryCharger' 'Native charger actions must be removed from installed controllers'
Require-Text $client 'requestControllerStatus' 'Controller state synchronization is missing'
Require-Text $client 'beginStandalone\("claimController"' 'Claim requests need stable operation IDs'
Require-Text $client 'beginStandalone\("installController"' 'Install requests need stable operation IDs'
Require-Text $client 'beginStandalone\("reclaimController"' 'Reclaim requests need stable operation IDs'

foreach ($command in @('controllerStatus', 'claimController', 'installController', 'reclaimController')) {
    Require-Text $server ('function Commands\.' + $command) "Storage server command missing: $command"
}
Require-Text $server 'operation\(player,\s*"claimController"' 'Paid recovery must use the idempotent operation cache'
Require-Text $serverMain 'storageControllerCharge' 'Storage recovery economy bridge is missing'
Require-Text $serverMain 'storageControllerRefund' 'Failed controller creation must refund its original payment sources'
Require-Text $serverMain 'storageControllerCommit' 'Storage recovery spending/history commit is missing'
Require-Text $serverMain 'stats\.spentPoints' 'Recovery spending must count toward spending statistics'

Require-Text $mainUi 'confirmStorageRecovery' 'Paid recovery confirmation is missing'
Require-Text $mainUi 'Storage_ClaimFree' 'First-free UI state is missing'
Require-Text $mainUi 'Storage_RecoverPaid' 'Paid recovery UI state is missing'
Require-Text $mainUi 'Storage_ControllerOwned' 'Owned-controller UI lock is missing'
Require-Text $mainUi 'Storage_ControllerInstalled' 'Installed-controller UI lock is missing'

foreach ($key in @(
    'Storage_Context_Install', 'Storage_Context_Reclaim', 'Storage_ConfirmRecovery',
    'Storage_ClaimFree', 'Storage_RecoverPaid', 'Storage_ControllerOwned',
    'Storage_ControllerInstalled', 'Storage_Error_CurrencyNotEnough',
    'Storage_Notify_ControllerInstalled', 'Storage_Notify_ControllerReclaimed'
)) {
    Require-Text $localization ("(?m)^" + [regex]::Escape($key) + ':') "Localization source missing: $key"
    Require-Text $fallback ('GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]') "Lua fallback missing: $key"
    Require-Text $cn ('IGUI_GodSystem_' + [regex]::Escape($key)) "CN translation missing: $key"
    Require-Text $ch ('IGUI_GodSystem_' + [regex]::Escape($key)) "CH translation missing: $key"
}

if (-not $SkipRuntime) {
    $luaExe = Get-Command lua -ErrorAction SilentlyContinue
    if ($luaExe) {
        $luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
        & $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11665Runtime.lua') $Lua
        if ($LASTEXITCODE -ne 0) { throw 'v1.16.65 runtime test failed' }
    }
    else {
        Write-Warning 'Lua executable was not found; v1.16.65 runtime validation was skipped.'
    }
}

Write-Output 'Test-GodSystemV11665 passed'
