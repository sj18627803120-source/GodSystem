param(
    [string]$Root = "",
    [string]$ExpectedVersion = "42.20.1.3"
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Lua = Join-Path $Mod '42\media\lua'

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
    Write-Output "  OK: $Message"
}

Write-Output "=== Test-GodSystemV422013UIScale: Main UI scale range ==="

$theme = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UITheme.lua')
$ui = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$config = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Config.lua')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

$version = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $version + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $version + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $version + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + $version + '\r?$') "Workshop headline version must be v$ExpectedVersion"

Require-Text $theme 'scaleMin\s*=\s*0\.60' 'Theme minimum UI scale must be 0.60'
Require-Text $theme 'scaleMax\s*=\s*1\.50' 'Theme maximum UI scale must be 1.50'
Require-Text $theme 'minimumWidth\s*=\s*744' 'Theme minimum width must match 1240 * 0.60'
Require-Text $theme 'minimumHeight\s*=\s*414' 'Theme minimum height must match 690 * 0.60'

Require-Text $ui 'o\.minimumScale\s*=\s*win\.scaleMin\s+or\s+0\.60' 'Window constructor fallback min scale must be 0.60'
Require-Text $ui 'o\.maximumScale\s*=\s*win\.scaleMax\s+or\s+1\.50' 'Window constructor fallback max scale must be 1.50'
Require-Text $ui 'local\s+minScale\s*=\s*self\.minimumScale\s+or\s+\(\(gsTheme\(\)\.window\s+or\s+\{\}\)\.scaleMin\)\s+or\s+0\.60' 'Runtime clamp fallback min scale must be 0.60'
Require-Text $ui 'local\s+maxScale\s*=\s*self\.maximumScale\s+or\s+\(\(gsTheme\(\)\.window\s+or\s+\{\}\)\.scaleMax\)\s+or\s+1\.50' 'Runtime clamp fallback max scale must be 1.50'
Require-Text $ui 'local\s+fitScale\s*=\s*math\.min\(maxScale,' 'Open-window path must still clamp by screen fit'
Require-Text $ui 'data\.ui\.windowScale\s*=\s*self:getUIScale\(\)' 'Manual scale must still be persisted'

Write-Output 'Test-GodSystemV422013UIScale passed'
