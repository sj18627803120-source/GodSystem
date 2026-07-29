param(
    [string]$Root = "",
    [string]$ExpectedVersion = "42.20.1.1"
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

$storage = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Storage.lua')
$manager = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_StorageManager.lua')
$client = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageClient.lua')
$ui = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageUI.lua')
$server = Read-Utf8 (Join-Path $Lua 'server\GodSystem_StorageServer.lua')
$core = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Core.lua')
$mainServer = Read-Utf8 (Join-Path $Lua 'server\GodSystem_Server.lua')
$protocol = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Protocol.lua')
$terminal = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_TerminalUpgrades.lua')
$config = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Config.lua')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')
$readmePath = Get-ChildItem -LiteralPath $Root -Filter 'README_*.md' -File | Select-Object -First 1 -ExpandProperty FullName
$readme = Read-Utf8 $readmePath
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')

$version = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $version + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $version + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $version + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=.*v' + $version + '\r?$') "Workshop version must be $ExpectedVersion"

Require-Text $storage 'SchemaVersion\s*=\s*5' 'Storage schema v5 is missing'
Require-Text $storage 'ContainerSettingsKey\s*=\s*"GodSystemStorageContainerSettingsV1"' 'Per-slot settings key is missing'
Require-Text $storage 'PriorityTiers\s*=\s*\{\s*"lowest",\s*"low",\s*"normal",\s*"high",\s*"highest"\s*\}' 'Five priority tiers are missing'
Require-Text $storage 'function\s+Storage\.getContainerSettings' 'Per-slot settings reader is missing'
Require-Text $storage 'function\s+Storage\.setContainerSettings' 'Per-slot settings writer is missing'
Require-Text $storage 'priorityTier\s*=\s*Storage\.normalizePriorityTier' 'Discovered links must carry a normalized priority tier'
Require-Text $storage 'assignedOrder\s*=' 'Stable same-tier routing order is missing'
Require-Text $storage 'matchRank[\s\S]{0,500}priorityRank[\s\S]{0,500}assignedOrder' 'Route sorting order must use role, tier, then assignment order'
Reject-Text $storage 'allowCategories|denyCategories' 'Retired allow/deny routing rules remain in active storage code'
Reject-Text $storage 'Storage\.Roles\s*=\s*\{[\s\S]{0,300}"(auto|noAuto|liquid)"' 'Retired container roles remain in the active role list'

Require-Text $manager 'Storage\.getContainerSettings\(object,\s*link\.slotIndex' 'Manager must update the selected concrete slot'
Require-Text $manager 'nextRoutingOrder' 'Routing assignment order must advance after setting changes'
Require-Text $manager 'function\s+Manager\.startOrganizer' 'Manual organizer start path is missing'
Require-Text $manager 'function\s+Manager\.stopOrganizer' 'Manual organizer stop path is missing'
Require-Text $manager 'MaxIndexedItems' 'Organizer must keep the 20,000 item bound'
Require-Text $manager 'local\s+function\s+organizerItemRows[\s\S]{0,3000}Storage\.describeItem' 'Organizer must enumerate direct container items'
Reject-Text $manager 'organizerItemRows[\s\S]{0,500}link\.isCoreHost\s*~=\s*true' 'Organizer must not exclude the current storage-capable core host'
Require-Text $manager 'category\s*==\s*"perishable"[\s\S]{0,250}spoilageRemaining\s*>' 'Fresh perishable ordering is missing'
Require-Text $manager 'organizerBufferRoutes' 'Organizer buffer routing is missing'
Require-Text $manager 'if\s+Manager\.isOrganizing\(network\.networkId\)\s+then\s+return\s+false,\s*"organizerRunning"' 'Mutation lock is missing'
Require-Text $server 'function\s+Commands\.organizerStart' 'MP organizer start command is missing'
Require-Text $server 'function\s+Commands\.organizerStop' 'MP organizer stop command is missing'
Require-Text $client 'function\s+Client\.startOrganizer' 'Client organizer start bridge is missing'
Require-Text $ui 'Storage_Organizer_Start' 'Organizer UI button is missing'
Require-Text $ui 'containerDisplayName' 'Localized container name resolver is missing'
Require-Text $ui 'Storage_Priority_' 'Priority labels must be localized'

foreach ($key in @(
    'Storage_Priority_lowest', 'Storage_Priority_low', 'Storage_Priority_normal',
    'Storage_Priority_high', 'Storage_Priority_highest', 'Storage_Role_perishable',
    'Storage_Role_drink', 'Storage_Role_container', 'Storage_Role_furniture',
    'Storage_Role_other', 'Storage_Organizer_Start', 'Storage_Organizer_Stop',
    'Storage_Organizer_Progress', 'Storage_Organizer_Result', 'Storage_Error_OrganizerRunning'
)) {
    Require-Text $localization ('(?m)^' + [regex]::Escape($key) + ':') "Localization key is missing: $key"
}

Reject-Text ($storage + $manager) 'LegacyController|legacyController|movableData|migrationPending|originalCapacities' 'Retired world-controller or capacity-lock migration remains'
Reject-Text ($terminal + $core + $mainServer) 'GodSystemLegacyCompressionCleanup|GodSystemCompressionBaseActualWeight' 'Retired compression cleanup remains active'
Reject-Text ($protocol + $core + $mainServer) 'removeUnlocked' 'Retired shop removal alias remains active'
Reject-Text ($core + $mainServer + $config) 'BankAllowNewFixedDeposits|createFixedFromCash|action\s*==\s*"createFixed"' 'Retired fixed-deposit creation remains active'
if (Test-Path -LiteralPath (Join-Path $Lua 'shared\GodSystem_LegacyCompressionCleanup.lua')) {
    throw 'Retired legacy compression cleanup file must be removed'
}

Require-Text $workshop '100%.*AI' 'Personal author wording must remain in Workshop description'
Require-Text $workshop 'mod' 'Personal balance note must remain in Workshop description'
Require-Text $workshop 'v42\.20\.1\.1' 'Workshop usage summary must cover the current release'
Reject-Text $workshop '(?m)^description=v1\.16\.68' 'Workshop description must not contain the old version dump'
Require-Text $readme 'GodSystemWorkshopUpload_v42\.20\.1\.1' 'Full player usage guide is missing'
Require-Text $readme 'GodSystem\.ps1' 'Usage guide must include the validation command'

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for v42.20.1.1 validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11673Runtime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'v42.20.1.1 storage routing runtime test failed' }

Write-Output 'Test-GodSystemV11673 passed'
