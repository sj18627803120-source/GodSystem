param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [string]$ExpectedVersion = "42.20.2.3"
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

Write-Output "=== Test-GodSystemV422023: Server Method Calls and Carry Cost Settings ==="

$mod = Join-Path $Root "Contents\mods\GodSystem"
$lua = Join-Path $mod "42\media\lua"
$server = Read-Utf8 (Join-Path $lua "server\GodSystem_Server.lua")
$config = Read-Utf8 (Join-Path $lua "shared\GodSystem_Config.lua")
$admin = Read-Utf8 (Join-Path $lua "shared\GodSystem_AdminConfig.lua")
$carry = Read-Utf8 (Join-Path $lua "shared\GodSystem_CarryCapacity.lua")
$sandbox = Read-Utf8 (Join-Path $mod "42\media\sandbox-options.txt")
$localization = Read-Utf8 (Join-Path $Root "tools\localization\godsystem_v11645_localization.yml")
$cnSandbox = Read-Utf8 (Join-Path $lua "shared\Translate\CN\Sandbox.json")
$chSandbox = Read-Utf8 (Join-Path $lua "shared\Translate\CH\Sandbox.json")
$rootInfo = Read-Utf8 (Join-Path $mod "mod.info")
$b42Info = Read-Utf8 (Join-Path $mod "42\mod.info")
$workshop = Read-Utf8 (Join-Path $Root "workshop.txt")

Require-Text $server 'local\s+SAFE_JAVA_CALLS\s*=' 'Server maps dynamic medical calls to explicit B42 object methods'
Require-Text $server 'container:getContainingItem\(\)' 'Terminal ownership uses the B42 object-method call'
Reject-Text $server 'safeCall\(container,\s*"getContainingItem"' 'Terminal ownership no longer routes getContainingItem through the dynamic helper'
Reject-Text $server 'local\s+method\s*=\s*object\[methodName\]' 'Server does not extract Java methods before invocation'
Reject-Text $server 'method\(object(?:,|\))' 'Server does not call extracted Java methods as Lua functions'

foreach ($key in @('CarryCapacityBaseCost', 'CarryCapacityCostMultiplier')) {
    Require-Text $admin ('key\s*=\s*"' + $key + '"[\s\S]{0,300}target\s*=\s*"' + $key + '"') "Admin configuration applies $key at runtime"
    Require-Text $sandbox ('GodSystem\.' + $key) "Sandbox option exists for $key"
    Require-Text $localization ('(?m)^AdminSetting_' + $key + ':') "Localization source names $key"
    Require-Text $localization ('(?m)^AdminSetting_' + $key + '_Desc:') "Localization source explains $key"
    Require-Text $cnSandbox ('"Sandbox_GodSystem_' + $key + '"') "CN sandbox translation exists for $key"
    Require-Text $chSandbox ('"Sandbox_GodSystem_' + $key + '"') "CH sandbox translation exists for $key"
}
Require-Text $config 'CarryCapacityBaseCost\s*=\s*2000' 'Carry base cost keeps the established default'
Require-Text $config 'CarryCapacityCostMultiplier\s*=\s*1\.5' 'Carry multiplier keeps the established default'
Require-Text $carry 'GodSystemConfig\.CarryCapacityBaseCost' 'Carry quote reads the configured base cost'
Require-Text $carry 'GodSystemConfig\.CarryCapacityCostMultiplier' 'Carry quote reads the configured multiplier'
Require-Text $server 'GodSystemCarryCapacity\.getNextCost\(currentLevel\)' 'MP settlement reads the shared carry quote'
$metaCount = ([regex]::Matches($admin, '\{\s*key\s*=\s*"')).Count
if ($metaCount -ne 77) { throw "Expected 77 admin settings, found $metaCount" }
Write-Output '  OK: Admin setting count includes both carry-cost settings'

$versionPattern = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $versionPattern + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $versionPattern + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $versionPattern + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + $versionPattern + '\r?$') "Workshop headline version must be v$ExpectedVersion"

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = Join-Path $env:LOCALAPPDATA "Programs\Lua51\5.1.5\lua.exe"
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw "Lua 5.1 runtime is required for 42.20.2.3 validation" }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot "Test-GodSystemV422023CarryRuntime.lua") (Join-Path $lua "shared\GodSystem_CarryCapacity.lua") (Join-Path $lua "shared\GodSystem_AdminConfig.lua")
if ($LASTEXITCODE -ne 0) { throw "42.20.2.3 carry cost runtime test failed" }

Write-Output "Test-GodSystemV422023 passed for $ExpectedVersion"
