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
$carry = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_CarryCapacity.lua')
$core = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Core.lua')
$ui = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$override = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Localization_Override.lua')
$cn = Read-Utf8 (Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt')
$ch = Read-Utf8 (Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.60"' 'Config version must be 1.16.60'
Require-Text $rootInfo '(?m)^modversion=1\.16\.60\r?$' 'Root mod.info version must be 1.16.60'
Require-Text $b42Info '(?m)^modversion=1\.16\.60\r?$' 'B42 mod.info version must be 1.16.60'
Require-Text $workshop '(?m)^description=v1\.16\.60\r?$' 'Workshop metadata must mention v1.16.60'

Require-Text $config 'CarryCapacityPerLevel\s*=\s*2' 'Configured carry behavior must remain unchanged'
Require-Text $carry 'local function capacityFromDelta' 'Carry result measurement helper is missing'
Require-Text $carry 'local function detectDeltaModel' 'Carry delta model detection is missing'
Require-Text $carry 'local desiredFactor\s*=\s*desiredBonus\s*/\s*maxWeightBase' 'Existing carry factor calculation must remain unchanged'
Require-Text $carry 'local target\s*=\s*externalDelta\s*\+\s*desiredFactor' 'Existing carry target must remain unchanged'
Require-Text $carry 'predictedFinal\s*=\s*capacityFromDelta' 'Upgrade result must be measured from the written delta'
Require-Text $carry 'predictedIncrease\s*=\s*predictedFinal\s*and\s*\(predictedFinal\s*-\s*originalFinal\)' 'Upgrade result must compare before and estimated final capacity'
Require-Text $carry 'actualBonus\s*=\s*total\s*~=\s*nil\s*and\s*base\s*~=\s*nil\s*and\s*\(total\s*-\s*base\)' 'Displayed carry bonus must use actual final minus base'
Reject-Text $carry 'TARGET_MARGIN|Events\.|OnPlayerUpdate|OnTick|EveryOneMinute' 'Carry measurement must not alter the target or register recurring work'

Require-Text $ui 'status\.actualBonus' 'Upgrade page must display the measured actual bonus'
Reject-Text $ui 'Upgrade_CarryBonus[\s\S]{0,120}status\.bonus' 'Upgrade page must not display the configured theoretical bonus'
Require-Text $core 'applyResult\s*and\s*applyResult\.predictedIncrease' 'SP upgrade notification must use the measured increase'
Require-Text $core 'applyResult\s*and\s*applyResult\.predictedFinal' 'SP upgrade notification must use the estimated final capacity'
Reject-Text $core 'Permanently increase player carry capacity by 2 per level' 'Carry fallback text must not promise a fixed visible increase'

Require-Text $localization '(?m)^Waist_CompressionLimit:' 'Compression compatibility notice is missing from the localization source'
Require-Text $localization '(?m)^Notify_CarryCapacityUpgraded:.*\{3\}' 'SP carry notification must include the measured final value'
Require-Text $localization '(?m)^History_CarryCapacityUpgrade:.*\{4\}' 'SP carry history must include the measured result and cost'
Require-Text $override 'GodSystemFallbackText\.zh\["Waist_CompressionLimit"\]' 'Compression notice is missing from the Lua fallback'
Require-Text $cn 'IGUI_GodSystem_Waist_CompressionLimit' 'Compression notice is missing from CN translations'
Require-Text $ch 'IGUI_GodSystem_Waist_CompressionLimit' 'Compression notice is missing from CH translations'
Require-Text $ui 'addListItem\(compressionLimit' 'Compression notice must be visible on the terminal page'

if (-not $SkipRuntime) {
    $luaExe = Get-Command lua -ErrorAction SilentlyContinue
    if (-not $luaExe) {
        $localLua = Join-Path $env:USERPROFILE 'Tools\Lua51\lua.exe'
        if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
    }
    if ($luaExe) {
        $luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
        & $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11657Runtime.lua') (Join-Path $Lua 'shared\GodSystem_CarryCapacity.lua')
        if ($LASTEXITCODE -ne 0) { throw 'v1.16.60 carry measurement runtime test failed' }
    }
    else {
        Write-Warning 'Lua executable was not found; v1.16.60 runtime validation was skipped.'
    }
}

Write-Output 'Test-GodSystemV11660 passed'
