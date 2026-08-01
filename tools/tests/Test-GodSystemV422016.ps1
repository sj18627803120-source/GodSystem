param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [string]$ExpectedVersion = "42.20.1.7"
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

function Reject-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw $Message }
    Write-Output "  OK: $Message"
}

Write-Output "=== Test-GodSystemV422016: Terminal Freshness Only ==="

$lua = Join-Path $Root "Contents\mods\GodSystem\42\media\lua"
$foodPath = Join-Path $lua "shared\GodSystem_TerminalFood.lua"
$food = Read-Utf8 $foodPath
$terminalUpgrades = Read-Utf8 (Join-Path $lua "shared\GodSystem_TerminalUpgrades.lua")
$pageSections = Read-Utf8 (Join-Path $lua "client\GodSystem_PageSections.lua")
$protocol = Read-Utf8 (Join-Path $lua "shared\GodSystem_Protocol.lua")
$core = Read-Utf8 (Join-Path $lua "client\GodSystem_Core.lua")
$network = Read-Utf8 (Join-Path $lua "client\GodSystem_Network.lua")
$ui = Read-Utf8 (Join-Path $lua "client\GodSystem_UI.lua")
$storageUi = Read-Utf8 (Join-Path $lua "client\GodSystem_StorageUI.lua")
$server = Read-Utf8 (Join-Path $lua "server\GodSystem_Server.lua")
$config = Read-Utf8 (Join-Path $lua "shared\GodSystem_Config.lua")
$localization = Read-Utf8 (Join-Path $Root "tools\localization\godsystem_v11645_localization.yml")
$rootInfo = Read-Utf8 (Join-Path $Root "Contents\mods\GodSystem\mod.info")
$b42Info = Read-Utf8 (Join-Path $Root "Contents\mods\GodSystem\42\mod.info")
$workshop = Read-Utf8 (Join-Path $Root "workshop.txt")

Require-Text $config 'TerminalFreshnessLevels\s*=' 'Config declares permanent freshness-efficiency levels'
Reject-Text $config 'TerminalCooling' 'Config no longer exposes the ineffective cooling feature'
Require-Text $food 'function\s+TerminalFood\.setFreshnessLevel\s*\(' 'Freshness service owns its efficiency level'
Require-Text $food 'function\s+TerminalFood\.getFreshnessInfo\s*\(' 'Freshness service exposes its current effect'
Require-Text $food 'function\s+TerminalFood\.settleOnline\s*\(' 'Freshness service settles only online game time'
Require-Text $food 'changedItems' 'Freshness settlement reports changed food instances for MP synchronization'
Reject-Text $food 'AgeFactor|applyCooling|Cooling' 'Food service does not use unsupported native cooling writes'
Require-Text $terminalUpgrades 'upgradeType == "freshness"' 'Terminal upgrade facade exposes freshness efficiency'
Reject-Text $terminalUpgrades 'applyCooling|snapshotCooling|restoreCooling' 'Terminal upgrade facade has no cooling mutation path'
Require-Text $protocol 'TerminalFreshnessService\s*=\s*"terminalFreshnessService"' 'Freshness purchase command remains stable'
Require-Text $network 'upgradeType ~= "freshness"' 'MP terminal upgrade bridge accepts freshness efficiency'
Reject-Text $network 'setAgeFactor|coolingLevel|TerminalCooling' 'Client terminal synchronization does not write cooling state'
Require-Text $server 'terminalFreshness\s*=\s*"freshness"' 'Server upgrade mapping exposes freshness efficiency'
Reject-Text $server 'ageFactor|coolingLevel|TerminalFreshnessCoolingRequired' 'Server terminal sync and purchase path have no cooling state'
Require-Text $core 'terminalFreshness' 'SP terminal upgrade path exposes freshness efficiency'
Reject-Text $core 'terminalCooling|coolingLevel|coolingMultiplier|coolingAgeFactor' 'SP UI data has no cooling state'
Require-Text $core 'Upgrade_TerminalFreshnessRate' 'Freshness upgrade detail reports its current and next restoration rates'
Require-Text $ui 'Btn_TerminalFreshnessOneDay' 'Services page has a visible 1-day purchase button'
Require-Text $ui 'Btn_TerminalFreshnessTenDays' 'Services page has a visible 10-day purchase button'
Require-Text $ui 'Btn_TerminalFreshnessTwentyDays' 'Services page has a visible 20-day purchase button'
Require-Text $ui 'Btn_TerminalFreshnessThirtyDays' 'Services page has a visible 30-day purchase button'
Require-Text $ui 'Terminal_FreshnessEffectDesc' 'Services page writes the freshness effect into the detail panel'
Require-Text $ui 'Menu_TerminalFreshnessThirtyDays' 'Right-click freshness package menu remains available'
Reject-Text $ui 'terminalCooling|Terminal_FreshnessCoolingRequired' 'Terminal UI no longer presents cooling'
Require-Text $pageSections 'function\s+PageSections\.select\s*\(' 'Local page-section helper retains active section state'
Require-Text $ui 'require\s+"GodSystem_PageSections"' 'Main UI loads the local page-section helper'
Require-Text $ui 'function\s+GodSystemWindow:selectPageSection\s*\(' 'Terminal and task pages switch through a local section boundary'
Require-Text $ui 'taskExtensions' 'Task extension upgrades remain separated from task lists'
Require-Text $ui 'function\s+GodSystemWindow:hasPendingListRestore\s*\(' 'UI exposes a single pending-list-restore guard'
Require-Text $ui 'if\s+not\s+self:hasPendingListRestore\(\)\s+then\s+self:restorePageSectionState\(self\.mode\)\s+end' 'Section cache cannot overwrite an action restore snapshot'
Require-Text $ui 'function\s+GodSystemWindow:prepareActionSelection\s*\([^)]*\)[\s\S]*?self:captureScrollState\(\)' 'Action snapshots always capture scroll state'
Require-Text $ui 'function\s+GodSystemWindow:finishMultiplayerCommand\s*\([^)]*\)[\s\S]*?if\s+not\s+self:hasPendingListRestore\(\)\s+then\s+self:prepareActionSelection\(\)\s+end' 'Command completion protects scroll state for every action path'
Require-Text $ui 'function\s+GodSystemWindow:updateTaskPrimaryButton\s*\([^)]*\)[\s\S]{0,1400}?self:getActivePageSection\("tasks"\)\s*==\s*"taskExtensions"[\s\S]{0,300}?Btn_UpgradeSystem' 'Task extension rows do not reuse the task accept-action title'
Require-Text $ui 'function\s+GodSystemWindow:updateTaskPrimaryButton\s*\([^)]*\)[\s\S]{0,1400}?payload\.kind\s*==\s*"upgrade"[\s\S]{0,300}?Btn_UpgradeSystem' 'Task extension upgrade selection forces the purchase-action title'
Require-Text $storageUi 'function\s+GodSystemStorageWindow:onCategoryRightMouseUp\s*\(' 'Storage category filter keeps its right-click category menu'
Require-Text $storageUi 'Storage\.Categories' 'Storage category menu reuses existing category definitions'

foreach ($key in @(
    "Upgrade_TerminalFreshness", "Upgrade_TerminalFreshnessDesc", "Upgrade_TerminalFreshnessRate", "Upgrade_TerminalFreshnessNextRate", "Terminal_FreshnessEffectDesc",
    "Btn_TerminalFreshnessOneDay", "Btn_TerminalFreshnessTenDays", "Btn_TerminalFreshnessTwentyDays", "Btn_TerminalFreshnessThirtyDays",
    "Menu_TerminalFreshnessOneDay", "Menu_TerminalFreshnessTenDays", "Menu_TerminalFreshnessTwentyDays", "Menu_TerminalFreshnessThirtyDays"
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
if (-not $luaExe) { throw "Lua 5.1 runtime is required for 42.20.1.7 validation" }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot "Test-GodSystemV422016TerminalFoodRuntime.lua") $foodPath
if ($LASTEXITCODE -ne 0) { throw "42.20.1.7 terminal-freshness runtime test failed" }

Write-Output "Test-GodSystemV422016 passed for $ExpectedVersion"
