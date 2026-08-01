param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [string]$ExpectedVersion = "42.20.2.1"
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

Write-Output "=== Test-GodSystemV422021: Keybind, Task Service and Personal Storage ==="

$lua = Join-Path $Root "Contents\mods\GodSystem\42\media\lua"
$keybind = Read-Utf8 (Join-Path $lua "client\GodSystem_Keybind.lua")
$taskService = Read-Utf8 (Join-Path $lua "shared\GodSystem_TaskService.lua")
$snapshot = Read-Utf8 (Join-Path $lua "shared\GodSystem_ItemSnapshot.lua")
$personal = Read-Utf8 (Join-Path $lua "shared\GodSystem_PersonalStorage.lua")
$bridge = Read-Utf8 (Join-Path $lua "shared\GodSystem_StorageBridge.lua")
$personalClient = Read-Utf8 (Join-Path $lua "client\GodSystem_PersonalStorageClient.lua")
$personalServer = Read-Utf8 (Join-Path $lua "server\GodSystem_PersonalStorageServer.lua")
$personalUi = Read-Utf8 (Join-Path $lua "client\GodSystem_PersonalStorageUI.lua")
$core = Read-Utf8 (Join-Path $lua "client\GodSystem_Core.lua")
$ui = Read-Utf8 (Join-Path $lua "client\GodSystem_UI.lua")
$server = Read-Utf8 (Join-Path $lua "server\GodSystem_Server.lua")
$storage = Read-Utf8 (Join-Path $lua "shared\GodSystem_Storage.lua")
$manager = Read-Utf8 (Join-Path $lua "shared\GodSystem_StorageManager.lua")
$config = Read-Utf8 (Join-Path $lua "shared\GodSystem_Config.lua")
$admin = Read-Utf8 (Join-Path $lua "shared\GodSystem_AdminConfig.lua")
$items = Read-Utf8 (Join-Path $Root "Contents\mods\GodSystem\42\media\scripts\GodSystem_Items.txt")
$localization = Read-Utf8 (Join-Path $Root "tools\localization\godsystem_v11645_localization.yml")
$rootInfo = Read-Utf8 (Join-Path $Root "Contents\mods\GodSystem\mod.info")
$b42Info = Read-Utf8 (Join-Path $Root "Contents\mods\GodSystem\42\mod.info")
$workshop = Read-Utf8 (Join-Path $Root "workshop.txt")

$versionPattern = [regex]::Escape($ExpectedVersion)
Require-Text $rootInfo ("(?m)^modversion=" + $versionPattern + "\r?$") "Root mod.info version is $ExpectedVersion"
Require-Text $b42Info ("(?m)^modversion=" + $versionPattern + "\r?$") "B42 mod.info version is $ExpectedVersion"
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $versionPattern + '"') "Config version is $ExpectedVersion"
Require-Text $workshop ("(?m)^description=v" + $versionPattern + "\r?$") "Workshop description is $ExpectedVersion"
Require-Text $rootInfo '(?m)^id=GodSystem_CN\r?$' 'Root Mod ID remains GodSystem_CN'
Require-Text $workshop '(?m)^id=3773949382\r?$' 'Workshop ID remains 3773949382'

Require-Text $keybind 'PZAPI\.ModOptions:create\("GodSystem_CN"' 'Keybind uses native B42 ModOptions'
Require-Text $keybind 'DEFAULT_KEY\s*=\s*Keyboard\.KEY_N' 'Panel key defaults to N'
Require-Text $keybind 'function\s+Keybind\.(setKey|reset|disable|beginCapture)' 'Keybind exposes editable, reset, disable and capture operations'
Require-Text $keybind 'textInputActive\(\)' 'Panel hotkey is blocked during text input'
Require-Text $ui 'Shortcut_PanelKeyConflictHint' 'Shortcut UI warns without overriding conflicting bindings'

Require-Text $taskService 'TaskService\.PermitTarget\s*=\s*50' 'Long permit task requires 50 claimed tasks'
Require-Text $taskService 'TaskService\.PermitFullType\s*=\s*"GodSystem\.StorageExpansionPermit"' 'Long task grants the real permit item'
Require-Text $taskService 'function\s+TaskService\.ensurePermitTask' 'Task service enforces one renewable permit task'
Require-Text $taskService 'function\s+service:settleDeath' 'Task service owns idempotent death settlement'
Require-Text $taskService 'TaskService\.sortTasks' 'Task service owns stable task sorting'
Require-Text $core 'GodSystemTaskService\.create' 'SP task entry is a thin TaskService adapter'
Require-Text $server 'GodSystemTaskService\.create' 'MP task entry is a thin TaskService adapter'
Reject-Text $taskService 'require\s+"GodSystem_(Core|UI|Server)"' 'Task domain does not depend on Core, UI or Server implementations'

Require-Text $items 'item\s+StorageExpansionPermit' 'Storage expansion permit is registered as an item'
foreach ($text in @($config, $storage)) {
    Require-Text $text 'GodSystem\.StorageExpansionPermit' 'Permit is excluded from automated systems'
}
Require-Text $personal 'Personal\.PermitCapacity\s*=\s*200' 'Each permit adds 200 category capacity'
Require-Text $personal 'Personal\.GeneralPurchaseCost\s*=\s*10000' 'General capacity purchase costs 10000'
Require-Text $personal 'Personal\.GeneralPurchaseCapacity\s*=\s*10' 'General capacity purchase adds 10'
Require-Text $personal 'generalUsed\s*=\s*generalUsed\s*\+\s*overflow' 'General capacity uses the sum of category overflow'
Require-Text $snapshot 'Snapshot\.MaxDepth\s*=\s*32' 'Snapshots cap recursive traversal at 32 levels'
Require-Text $snapshot 'safePrimitive' 'Third-party ModData is reduced to Lua-safe primitives'
Require-Text $snapshot 'function\s+Snapshot\.count' 'Snapshot capacity includes nested items and stack counts'
Require-Text $server 'GodSystemServer\.personalStorageAccount' 'MP personal storage uses a private account slice'
Require-Text $server 'summaryOnly\s*=\s*true' 'Main state synchronization sends only personal-storage summaries'
Reject-Text $personal 'require\s+"GodSystem_(Core|UI|Server|StorageManager)"' 'Personal storage domain has no UI, Core, Server or physical-manager dependency'

Require-Text $manager 'function\s+Manager\.inspectNetworkItems' 'Physical storage exposes a narrow read interface'
Require-Text $manager 'function\s+Manager\.consumeNetworkItems' 'Physical storage exposes a narrow extraction interface'
Require-Text $manager 'function\s+Manager\.routeExternalItem' 'Physical storage exposes a narrow routing interface'
Require-Text $bridge 'function\s+Bridge\.create\(dependencies\)' 'Storage bridge receives explicit dependencies'
Require-Text $bridge 'local\s+remaining\s*=\s*250' 'Physical-to-personal conversion is bounded to 250 items per batch'
Require-Text $personalUi 'Ctrl|controlDown' 'Personal storage supports Ctrl multi-selection'
Require-Text $personalUi 'shiftDown' 'Personal storage supports Shift range selection'
Require-Text $personalClient 'operationId' 'Personal storage operations carry operation IDs'
Require-Text $ui 'Btn_DiagnosticsCopy' 'Diagnostics exposes one-click report copying'
Require-Text $ui 'Diag_ModulePersonalStorage' 'Diagnostics reports personal-storage health'
Require-Text $admin 'EnablePersonalStorage' 'Personal storage has an independent runtime switch'

foreach ($key in @(
    'ItemName_GodSystem.StorageExpansionPermit', 'Tooltip_GodSystem_StorageExpansionPermit',
    'Task_StoragePermit_Title', 'Task_StoragePermit_Desc', 'Shortcut_PanelKey',
    'PersonalStorage_Title', 'PersonalStorage_Category_food', 'PersonalStorage_Category_other',
    'Btn_DiagnosticsCopy', 'AdminSetting_EnablePersonalStorage'
)) {
    Require-Text $localization ("(?m)^" + [regex]::Escape($key) + ":") "Localization source contains $key"
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = Join-Path $env:USERPROFILE "Tools\Lua51\lua.exe"
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw "Lua 5.1 runtime is required for 42.20.2.1 validation" }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot "Test-GodSystemV422021Runtime.lua") $lua
if ($LASTEXITCODE -ne 0) { throw "42.20.2.1 runtime test failed" }

Write-Output "Test-GodSystemV422021 passed for $ExpectedVersion"
