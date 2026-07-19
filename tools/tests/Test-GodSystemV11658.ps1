param(
    [string]$Root = "",
    [switch]$SkipRuntime
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Lua = Join-Path $Mod '42\media\lua'

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Reject-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw $Message }
}

$config = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Config.lua')
$terminal = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_TerminalUpgrades.lua')
$core = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Core.lua')
$ui = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$fallback = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Localization_Override.lua')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.58"' 'Config version must be 1.16.58'
Require-Text $rootInfo '(?m)^modversion=1\.16\.58\r?$' 'Root mod.info version must be 1.16.58'
Require-Text $b42Info '(?m)^modversion=1\.16\.58\r?$' 'B42 mod.info version must be 1.16.58'
Require-Text $workshop '(?m)^description=v1\.16\.58\r?$' 'Workshop metadata must mention v1.16.58'

Require-Text $terminal 'writeNumberMethod\(terminal,\s*"setCapacity",\s*"getCapacity",\s*capacity\)' 'Outer terminal capacity must be written and verified'
Require-Text $terminal 'writeNumberMethod\(inventory,\s*"setCapacity",\s*"getCapacity",\s*capacity\)' 'Inner terminal capacity must be written and verified'
Require-Text $terminal 'writeNumberMethod\(terminal,\s*"setWeightReduction",\s*"getWeightReduction",\s*reduction\)' 'Outer terminal reduction must be written and verified'
Require-Text $terminal 'writeNumberMethod\(inventory,\s*"setWeightReduction",\s*"getWeightReduction",\s*reduction\)' 'Inner terminal reduction must be written and verified'
Require-Text $terminal '(?s)item:setCustomWeight\(true\).*?item:setActualWeight\(weight\)' 'Custom-weight mode must be enabled before writing the instance weight'
Require-Text $terminal 'return true, report' 'Individual item failures must not roll back a valid terminal upgrade'
Require-Text $terminal 'MAX_DIAGNOSTIC_ROWS\s*=\s*5' 'Compression diagnostics must be bounded'
Require-Text $terminal 'function GodSystemTerminalUpgrades\.getAppliedStatus' 'Runtime terminal status reader is missing'
Reject-Text $terminal 'ScriptItem' 'Compression must not edit shared ScriptItem weights'

Require-Text $core 'getAutoRecyclerContentSignature' 'Terminal contents need a bounded change signature'
Require-Text $core 'terminalRefreshPending' 'Container changes must schedule terminal recalibration'
Require-Text $core 'actualWeightReduction' 'The UI state must expose the actual outer reduction'
Require-Text $ui 'Waist_CompressionResult' 'The UI must show compression calibration counts'
Require-Text $ui 'compressionDiagnostics' 'The UI must expose bounded per-item failure diagnostics'

foreach ($key in @('Waist_Target', 'Waist_Actual', 'Waist_CompressionResult')) {
    Require-Text $localization ("(?m)^" + [regex]::Escape($key) + ':') ("Localization source missing key: " + $key)
    Require-Text $fallback ('GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]') ("Lua fallback missing key: " + $key)
}

if (-not $SkipRuntime) {
    $luaExe = Get-Command lua -ErrorAction SilentlyContinue
    if (-not $luaExe) {
        $localLua = Join-Path $env:USERPROFILE 'Tools\Lua51\lua.exe'
        if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
    }
    if ($luaExe) {
        $luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
        & $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11658TerminalRuntime.lua') (Join-Path $Lua 'shared\GodSystem_TerminalUpgrades.lua')
        if ($LASTEXITCODE -ne 0) { throw 'v1.16.58 terminal runtime test failed' }
    }
    else {
        Write-Warning 'Lua executable was not found; v1.16.58 runtime validation was skipped.'
    }
}

Write-Output 'Test-GodSystemV11658 passed'
