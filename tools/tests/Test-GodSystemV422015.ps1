param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [string]$ExpectedVersion = "42.20.1.5"
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

Write-Output "=== Test-GodSystemV422015: Terminal Food And Page Sections ==="

$lua = Join-Path $Root "Contents\mods\GodSystem\42\media\lua"
$foodPath = Join-Path $lua "shared\GodSystem_TerminalFood.lua"
$pageSectionsPath = Join-Path $lua "client\GodSystem_PageSections.lua"
$pageSections = Read-Utf8 $pageSectionsPath
$protocol = Read-Utf8 (Join-Path $lua "shared\GodSystem_Protocol.lua")
$core = Read-Utf8 (Join-Path $lua "client\GodSystem_Core.lua")
$network = Read-Utf8 (Join-Path $lua "client\GodSystem_Network.lua")
$ui = Read-Utf8 (Join-Path $lua "client\GodSystem_UI.lua")
$storageUi = Read-Utf8 (Join-Path $lua "client\GodSystem_StorageUI.lua")
$server = Read-Utf8 (Join-Path $lua "server\GodSystem_Server.lua")
$transactions = Read-Utf8 (Join-Path $lua "server\GodSystem_TransactionOps.lua")
$terminalUpgrades = Read-Utf8 (Join-Path $lua "shared\GodSystem_TerminalUpgrades.lua")
$food = Read-Utf8 $foodPath
$localization = Read-Utf8 (Join-Path $Root "tools\localization\godsystem_v11645_localization.yml")
$rootInfo = Read-Utf8 (Join-Path $Root "Contents\mods\GodSystem\mod.info")
$b42Info = Read-Utf8 (Join-Path $Root "Contents\mods\GodSystem\42\mod.info")
$config = Read-Utf8 (Join-Path $lua "shared\GodSystem_Config.lua")
$workshop = Read-Utf8 (Join-Path $Root "workshop.txt")

Require-Text $food 'setAgeFactor' 'Cooling must use the native ItemContainer age-factor API'
Require-Text $food 'changedItems' 'Freshness settlement must report changed food instances for MP synchronization'
Require-Text $food 'function\s+TerminalFood\.settleOnline\s*\(' 'Freshness service must settle elapsed online game hours'
Require-Text $food 'function\s+TerminalFood\.beginOnlineSession\s*\(' 'Freshness service must reset its clock for a new online session'
Require-Text $terminalUpgrades 'GodSystemTerminalFood\.applyCooling' 'Terminal upgrades must apply cooling through the food service'
Require-Text $protocol 'TerminalFreshnessService\s*=\s*"terminalFreshnessService"' 'Freshness service command must be declared in the protocol'
Require-Text $protocol 'terminalFreshnessService\s*=\s*true' 'Freshness service must refresh state and use the key-command guard'
Require-Text $network 'upgradeType ~= "cooling"' 'MP terminal upgrade bridge must accept cooling'
Require-Text $network 'wrap\(\s*"buyTerminalFreshnessService"' 'MP freshness purchase bridge is missing'
Require-Text $network 'freshnessService' 'MP freshness requests must have a stable retry fingerprint'
Require-Text $transactions 'kind == "terminalFreshnessService"' 'Server transaction ledger must fingerprint freshness purchases'
Require-Text $server 'require "GodSystem_TerminalFood"' 'Server must load the terminal food service'
Require-Text $server 'terminalCooling\s*=\s*"cooling"' 'Server terminal upgrade mapping must include cooling'
Require-Text $server 'function\s+Commands\.terminalFreshnessService\s*\(' 'Server freshness purchase handler is missing'
Require-Text $server 'report\.changedItems' 'Server must synchronize the food instances changed by freshness settlement'
Require-Text $server 'settleTerminalFreshnessService' 'Server player-hour loop must settle freshness service'
Require-Text $server 'beginOnlineSession' 'Server must reset freshness timing when a player session resumes'
Require-Text $core 'GodSystemTerminalFood\.beginOnlineSession\(data, gsNowHours\(\)\)' 'SP game start must reset freshness timing before online settlement'
Require-Text $pageSections 'function\s+PageSections\.select\s*\(' 'Local page-section helper must retain active section state'
Require-Text $ui 'require\s+"GodSystem_PageSections"' 'Main UI must load the local page-section helper'
Require-Text $ui 'function\s+GodSystemWindow:selectPageSection\s*\(' 'Terminal and task pages must switch through a local section boundary'
Require-Text $ui 'terminalFreshnessService' 'Terminal services section must expose freshness service status and purchase'
Require-Text $ui 'terminalCooling' 'Terminal upgrades section must expose cooling as an independent upgrade'
Require-Text $ui 'taskExtensions' 'Task extension upgrades must be separated from the task lists'
Require-Text $storageUi 'function\s+GodSystemStorageWindow:onCategoryRightMouseUp\s*\(' 'Storage category filter needs a right-click category menu'
Require-Text $storageUi 'Storage\.Categories' 'Storage category menu must reuse the existing category definitions'

foreach ($key in @(
    "Section_TerminalItems", "Section_TerminalUpgrades", "Section_TerminalServices", "Section_Tasks", "Section_TaskExtensions",
    "Upgrade_TerminalCooling", "Upgrade_TerminalCoolingDesc", "Terminal_ServiceFreshness", "Terminal_FreshnessCoolingRequired",
    "Btn_TerminalFreshnessOneDay", "Menu_TerminalFreshnessTenDays", "Notify_TerminalFreshnessPurchased",
    "NotifyMP_TerminalFreshnessPurchased", "History_TerminalFreshnessService", "HistoryMP_TerminalFreshnessService"
)) {
    Require-Text $localization ("(?m)^" + [regex]::Escape($key) + ":") "Localization source contains: $key"
}

$versionPattern = [regex]::Escape($ExpectedVersion)
Require-Text $rootInfo ("(?m)^modversion=" + $versionPattern + "\r?$") "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ("(?m)^modversion=" + $versionPattern + "\r?$") "B42 mod.info version must be $ExpectedVersion"
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $versionPattern + '"') "Config version must be $ExpectedVersion"
Require-Text $workshop ("(?m)^description=v" + $versionPattern + "\r?$") "Workshop description must be $ExpectedVersion"

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = Join-Path $env:USERPROFILE "Tools\Lua51\lua.exe"
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw "Lua 5.1 runtime is required for 42.20.1.5 validation" }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot "Test-GodSystemV422015TerminalFoodRuntime.lua") $foodPath
if ($LASTEXITCODE -ne 0) { throw "42.20.1.5 terminal-food runtime test failed" }

Write-Output "Test-GodSystemV422015 passed for $ExpectedVersion"
