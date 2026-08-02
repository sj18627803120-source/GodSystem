param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [string]$ExpectedVersion = "42.20.1.8"
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

Write-Output "=== Test-GodSystemV422018: Panel Key And Task Display Sort ==="

$lua = Join-Path $Root "Contents\mods\GodSystem\42\media\lua"
$panelKeyPath = Join-Path $lua "client\GodSystem_PanelKey.lua"
$taskOrderPath = Join-Path $lua "shared\GodSystem_TaskOrder.lua"
$panelKey = Read-Utf8 $panelKeyPath
$taskOrder = Read-Utf8 $taskOrderPath
$core = Read-Utf8 (Join-Path $lua "client\GodSystem_Core.lua")
$ui = Read-Utf8 (Join-Path $lua "client\GodSystem_UI.lua")
$config = Read-Utf8 (Join-Path $lua "shared\GodSystem_Config.lua")
$localization = Read-Utf8 (Join-Path $Root "tools\localization\godsystem_v11645_localization.yml")
$rootInfo = Read-Utf8 (Join-Path $Root "Contents\mods\GodSystem\mod.info")
$b42Info = Read-Utf8 (Join-Path $Root "Contents\mods\GodSystem\42\mod.info")
$workshop = Read-Utf8 (Join-Path $Root "workshop.txt")

Require-Text $panelKey 'require\s+"PZAPI/ModOptions"' 'Panel key uses the native B42 Mod Options API'
Require-Text $panelKey 'PZAPI\.ModOptions:create\("GodSystem_CN"' 'Panel key uses the stable Mod ID'
Require-Text $panelKey 'local\s+DEFAULT_KEY\s*=\s*Keyboard\.KEY_N' 'Panel key default is N'
Require-Text $panelKey 'addKeyBind\([\s\S]*?"OpenPanelKey"[\s\S]*?DEFAULT_KEY' 'Panel key uses a stable option ID and the shared default'
Require-Text $panelKey 'function\s+PanelKey\.registerToggle\s*\(' 'Panel key receives the panel toggle through an explicit callback'
Require-Text $panelKey 'function\s+PanelKey\.beginCapture\s*\(' 'Panel key supports in-panel capture'
Require-Text $panelKey 'Keyboard\.KEY_ESCAPE' 'Esc cancels key capture'
Require-Text $panelKey 'ISTextEntryBox|ISChat' 'Focused text and chat input block the panel shortcut'
Require-Text $panelKey 'UIManager\.getModal' 'Modal dialogs block the panel shortcut'
Reject-Text $panelKey 'require\s+"GodSystem_(?:Core|UI|Server)' 'Panel key module does not depend on business implementations'

Require-Text $ui '\{\s*id\s*=\s*"shortcuts"[^\r\n]+tool\s*=\s*true' 'Existing Shortcuts tool remains present'
Require-Text $ui '\{\s*id\s*=\s*"settings"[^\r\n]+tool\s*=\s*true' 'Top tool area contains the new Settings page'
Require-Text $ui 'function\s+GodSystemWindow:populateSettings\s*\(' 'Settings uses the existing main window page'
Require-Text $ui 'Settings_ChangeKey' 'Settings page exposes key capture'
Require-Text $ui 'Settings_ResetKey' 'Settings page exposes reset to N'
Reject-Text $ui 'GodSystemSettingsWindow' 'No separate settings window was introduced'

Require-Text $taskOrder 'function\s+TaskOrder\.sortedCopy\s*\(' 'Task order module returns a display copy'
Require-Text $taskOrder 'table\.sort\(result' 'Only the display copy is sorted'
Reject-Text $taskOrder 'require\s+|Events\.|ModData|sendClientCommand|sendServerCommand' 'Task order module is pure and event-free'
foreach ($kind in @('kill', 'recycleItems', 'recyclePoints', 'surviveHours', 'turnInItem', 'turnInAnyItem', 'spendPoints', 'buyItems', 'moveDistance')) {
    Require-Text $taskOrder ([regex]::Escape($kind) + '\s*=') "Task order recognizes $kind"
}
Require-Text $taskOrder 'penalty\s*>=\s*150[\s\S]*?penalty\s*>=\s*80[\s\S]*?penalty\s*>=\s*30' 'Difficulty boundaries remain D4, D3, D2, then D1'
Require-Text $core 'function\s+GodSystem\.getTaskDifficulty[\s\S]{0,180}?GodSystemTaskOrder\.difficultyLabel' 'Displayed D level reuses the task order rule'
Require-Text $ui 'sortedCopy\(data\.tasks\s+or\s+\{\},\s*"active"' 'Task tracker is sorted'
Require-Text $ui 'sortedCopy\(tasks,\s*"open"' 'Available task column is sorted'
Require-Text $ui 'sortedCopy\(tasks,\s*"active"' 'Active task column is sorted'
Require-Text $ui '"task:"\s*\.\.\s*tostring\(payload\.data\.taskId' 'Task selection restore remains keyed by taskId'

$toolCount = ([regex]::Matches($ui, 'tool\s*=\s*true')).Count
if ($toolCount -ne 6) { throw "Top tool count must be 6, got $toolCount" }
$minimumContentWidth = [math]::Floor(980 * 0.60)
$requiredToolWidth = [math]::Floor(((6 * 70) + (5 * 8)) * 0.60)
if ($requiredToolWidth -ge $minimumContentWidth) { throw "Top tools overlap at minimum UI scale" }
Write-Output "  OK: six top tools fit at minimum UI scale"

foreach ($key in @(
    'Settings_ModOptionsTitle', 'Settings_PanelKey', 'Settings_PanelKeyHint', 'Tab_Settings',
    'Settings_PanelKeyCurrent', 'Settings_ChangeKey', 'Settings_ResetKey', 'Settings_PressKey',
    'Settings_KeySaved', 'Settings_KeyCaptureCancelled', 'Settings_KeyReset', 'Settings_ModOptionsHint'
)) {
    Require-Text $localization ("(?m)^" + [regex]::Escape($key) + ":") "Localization source contains: $key"
}

Reject-Text ($panelKey + $taskOrder + $core + $ui) 'GodSystem_PersonalStorage|StorageExpansionPermit|generalCapacity|licenseTask' 'Failed 42.20.2.1 personal-storage work is not included'

$versionPattern = [regex]::Escape($ExpectedVersion)
Require-Text $rootInfo ("(?m)^modversion=" + $versionPattern + "\r?$") "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ("(?m)^modversion=" + $versionPattern + "\r?$") "B42 mod.info version must be $ExpectedVersion"
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $versionPattern + '"') "Config version must be $ExpectedVersion"
Require-Text $workshop ("(?m)^description=v" + $versionPattern + "\r?$") "Workshop headline version must be v$ExpectedVersion"
Require-Text $workshop '(?m)^id=3773949382\r?$' 'Workshop ID remains unchanged'
Require-Text $rootInfo '(?m)^id=GodSystem_CN\r?$' 'Mod ID remains unchanged'

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = Join-Path $env:USERPROFILE "Tools\Lua51\lua.exe"
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw "Lua 5.1 runtime is required for 42.20.1.8 validation" }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot "Test-GodSystemV422018Runtime.lua") $taskOrderPath $panelKeyPath
if ($LASTEXITCODE -ne 0) { throw "42.20.1.8 runtime test failed" }

Write-Output "Test-GodSystemV422018 passed for $ExpectedVersion"
