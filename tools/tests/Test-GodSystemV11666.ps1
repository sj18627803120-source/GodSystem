param(
    [string]$Root = "",
    [string]$ExpectedVersion = "1.16.66"
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
$context = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageContext.lua')
$mainUi = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')
$retiredPlacement = Join-Path $Lua 'client\GodSystem_StoragePlacement.lua'
$storageSectionMatch = [regex]::Match(
    $mainUi,
    'function\s+GodSystemWindow:populateStorageNetwork\(\)([\s\S]*?)function\s+GodSystemWindow:confirmStorageRecovery'
)
if (-not $storageSectionMatch.Success) { throw 'Storage page implementation section was not found' }
$storageSection = $storageSectionMatch.Value

$escapedVersion = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $escapedVersion + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $escapedVersion + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $escapedVersion + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + $escapedVersion + '\r?$') "Workshop metadata must mention v$ExpectedVersion"

if (Test-Path -LiteralPath $retiredPlacement) {
    throw 'The independently loaded storage placement file must be removed in v1.16.66'
}
Reject-Text $context 'BuildingObjects/ISBuildingObject|ISBuildingObject:derive|ControllerPlacement' 'The failed client building-object placement path must remain retired'
Reject-Text $context 'GodSystemStoragePlacement' 'The failed cross-file placement global must not remain'
Reject-Text $context 'require\s+"GodSystem_StoragePlacement"' 'The failed independent placement require must not remain'
Reject-Text $context 'pcall\s*\(\s*require' 'Required internal modules must not be hidden behind pcall'

Require-Text $storageSection 'local\s+storageActions\s*=\s*\{\s*\{\s*id\s*=\s*"primary"' 'Storage action bar must start with only the primary action'
Require-Text $storageSection 'if\s+self\.storageSecondaryAction\s+then[\s\S]{0,180}id\s*=\s*"secondary"' 'Storage secondary action must only be added when force recovery is available'
Reject-Text $storageSection 'self:setActionBar\(\{\s*\{\s*id\s*=\s*"primary"[\s\S]{0,120}\{\s*id\s*=\s*"secondary"' 'Storage page must not unconditionally revive the stale secondary button'

Write-Output 'Test-GodSystemV11666 passed'
