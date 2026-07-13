$ErrorActionPreference = 'Stop'

$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$CorePath = Join-Path $Mod '42\media\lua\client\GodSystem_Core.lua'
$ConfigPath = Join-Path $Mod '42\media\lua\shared\GodSystem_Config.lua'

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

$core = Read-Utf8 $CorePath
$config = Read-Utf8 $ConfigPath

Require-Text $core 'local\s+function\s+gsSafeCall\s*\(' 'Missing gsSafeCall helper'
Require-Text $core 'local\s+method\s*=\s*object\[methodName\]\s*\r?\n\s*if\s+type\(method\)\s*~=\s*"function"\s+then\s*\r?\n\s*return\s+fallback\s*\r?\n\s*end' 'gsSafeCall must skip missing/non-function methods before pcall'
if ($core -match 'return\s+method\(unpackFn\(args\)\)' -or $core -match 'return\s+method\(\)\s*\r?\n\s*end\s*\)') {
    throw 'gsSafeCall must not retry object methods without self after nil-returning calls'
}
Require-Text $core 'function\s+GodSystem\.getMedicalStatus' 'Missing medical status helper'
Require-Text $core 'function\s+GodSystem\.performMedicalService' 'Missing medical service entry'
Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.37"' 'Config version must be 1.16.37'

$files = Get-ChildItem -LiteralPath (Join-Path $Mod '42\media\lua') -Recurse -Filter *.lua
foreach ($file in $files) {
    $text = Read-Utf8 $file.FullName
    if ($text.Contains([char]0xFFFD)) {
        throw "Replacement character found: $($file.FullName)"
    }
}

Write-Output 'Test-GodSystemV11637 passed'
