param(
    [string]$Root = "",
    [string]$ExpectedVersion = "42.20.1.3"
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}
function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
    Write-Output "  OK: $Message"
}
function Reject-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw $Message }
    Write-Output "  OK: $Message"
}

Write-Output "=== Test-GodSystemV422013UIRecovery ==="
$lua = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$context = Read-Utf8 (Join-Path $lua 'client\GodSystem_StorageContext.lua')
$layout = Read-Utf8 (Join-Path $lua 'client\GodSystem_StorageMarkerLayout.lua')
$ui = Read-Utf8 (Join-Path $lua 'client\GodSystem_UI.lua')
$lifecycle = Read-Utf8 (Join-Path $lua 'client\GodSystem_FloatingButtonLifecycle.lua')

Require-Text $layout 'function\s+Layout\.position' 'Storage marker layout helper must expose a position function'
Require-Text $context 'require\s+"GodSystem_StorageMarkerLayout"' 'Storage context must load the isolated marker layout helper'
Require-Text $context 'GodSystemStorageMarkerLayout\.position\(sx,\s*baseY,\s*marker\.number,\s*step\)' 'Marker rendering must use the vertical layout helper'
Reject-Text $context 'markerHorizontalSlot|markerChevronCount|for\s+level\s*=\s*1,\s*count' 'Marker rendering must not horizontally fan out or repeat chevrons'
Require-Text $context 'local\s+step\s*=\s*math\.max\(10,\s*14\s*/\s*zoom\)' 'Marker rows must have a stable non-overlapping vertical step'

Require-Text $lifecycle 'function\s+Lifecycle\.ensure' 'Floating-button lifecycle helper must expose recovery'
Require-Text $lifecycle 'button:addToUIManager\(\)' 'Floating-button recovery must restore the UI-manager registration'
Require-Text $lifecycle 'function\s+Lifecycle\.clampPosition' 'Floating-button recovery must preserve a screen-boundary clamp'
Require-Text $ui 'require\s+"GodSystem_FloatingButtonLifecycle"' 'Main UI must load the floating-button lifecycle helper'
Require-Text $ui 'FloatingButtonRefreshIntervalMs\s*=\s*5000' 'Floating-button watchdog must use a five-second interval'
Require-Text $ui 'function\s+GodSystemUI\.onFloatingButtonTick' 'Main UI must register a floating-button watchdog'
Require-Text $ui 'GodSystemUI\.ensureFloatingButton\(\)' 'Floating-button watchdog must run local recovery'
Require-Text $ui 'function\s+GodSystemUI\.closeFloatingButton' 'Disconnect and main-menu cleanup must remove the floating button'
Require-Text $ui 'Events\.OnTick\.Add\(GodSystemUI\.onFloatingButtonTick\)' 'Floating-button watchdog must be registered'
Require-Text $ui 'Events\.OnDisconnect\.Add\(GodSystemUI\.onSessionEnd\)' 'Disconnect must use the combined UI cleanup handler'
Require-Text $ui 'Events\.OnMainMenuEnter\.Add\(GodSystemUI\.onSessionEnd\)' 'Main-menu entry must use the combined UI cleanup handler'

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for 42.20.1.3 UI recovery validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV422013StorageMarkerRuntime.lua') $lua
if ($LASTEXITCODE -ne 0) { throw 'Storage marker runtime test failed' }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV422013FloatingButtonLifecycleRuntime.lua') $lua
if ($LASTEXITCODE -ne 0) { throw 'Floating-button lifecycle runtime test failed' }

Write-Output "Test-GodSystemV422013UIRecovery passed for $ExpectedVersion"
