param(
    [string]$Root = "",
    [string]$ExpectedVersion = "1.16.59",
    [switch]$SkipRuntime,
    [switch]$AllowRetiredCompression
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
$carry = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_CarryCapacity.lua')
$terminal = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_TerminalUpgrades.lua')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

$versionPattern = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $versionPattern + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $versionPattern + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $versionPattern + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + $versionPattern + '\r?$') "Workshop metadata must mention v$ExpectedVersion"

Require-Text $carry 'local function writeFinal' 'Carry repair must refresh the cached final capacity'
Require-Text $carry 'player:setMaxWeight\(value\)' 'Carry repair must use the instance final-capacity API'
Require-Text $carry 'maxWeightBase\s*\*\s*\(1\s*\+\s*externalDelta\)' 'Carry baseline must preserve external delta contributions'
Require-Text $carry 'local desiredFinal\s*=\s*writeBaseline\s*\+\s*desiredBonus' 'Carry final write must still add the configured bonus to the v1.16.59 baseline'
Require-Text $carry 'writeFinal\(player,\s*originalFinal\)' 'Carry application failure must restore the previous final value'
Reject-Text $carry 'setMaxWeightBase' 'Carry repair must not overwrite maxWeightBase'

if (-not $AllowRetiredCompression) {
    Require-Text $terminal 'BASE_INPUT_KEY' 'Compression must preserve the setter input separately from effective weight'
    Require-Text $terminal 'LAST_INPUT_KEY' 'Compression must remember the last applied setter input'
    Require-Text $terminal 'COMPRESSION_VERSION\s*=\s*2' 'Compression metadata version must be upgraded'
    Require-Text $terminal 'readDefinitionWeight' 'Derived-weight items need a read-only base input'
    Require-Text $terminal 'derivedWeight\s*=\s*baseWeight\s*-\s*baseInput' 'Compression must account for derived effective weight'
    Require-Text $terminal 'for _ = 1, 3 do' 'Derived-weight correction must be bounded'
    Require-Text $terminal 'writeWeight\(item,\s*baseInput,\s*baseCustom,\s*baseWeight\)' 'Restoration must use the saved input and effective weight'
    Reject-Text $terminal 'DoParam|setScriptItem|definition:setActualWeight|definition:setWeight' 'Compression must not mutate shared item definitions'
}

if (-not $SkipRuntime) {
    $luaExe = Get-Command lua -ErrorAction SilentlyContinue
    if (-not $luaExe) {
        $localLua = Join-Path $env:USERPROFILE 'Tools\Lua51\lua.exe'
        if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
    }
    if ($luaExe) {
        $luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
        & $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11657Runtime.lua') (Join-Path $Lua 'shared\GodSystem_CarryCapacity.lua')
        if ($LASTEXITCODE -ne 0) { throw 'v1.16.59 carry runtime test failed' }
        if (-not $AllowRetiredCompression) {
            & $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11658TerminalRuntime.lua') (Join-Path $Lua 'shared\GodSystem_TerminalUpgrades.lua')
            if ($LASTEXITCODE -ne 0) { throw 'v1.16.59 compression runtime test failed' }
        }
    }
    else {
        Write-Warning 'Lua executable was not found; v1.16.59 runtime validation was skipped.'
    }
}

Write-Output 'Test-GodSystemV11659 passed'
