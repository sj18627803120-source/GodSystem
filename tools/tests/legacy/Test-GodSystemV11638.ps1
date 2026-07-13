$ErrorActionPreference = 'Stop'

$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$UiPath = Join-Path $Mod '42\media\lua\client\GodSystem_UI.lua'
$ConfigPath = Join-Path $Mod '42\media\lua\shared\GodSystem_Config.lua'
$ReadmePath = (Get-ChildItem -LiteralPath $Root -Filter 'README_*.md' | Select-Object -First 1).FullName
if ([string]::IsNullOrWhiteSpace($ReadmePath)) {
    throw 'README upload note file not found'
}

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

$ui = Read-Utf8 $UiPath
$config = Read-Utf8 $ConfigPath
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$readme = Read-Utf8 $ReadmePath

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.38"' 'Config version must be 1.16.38'
Require-Text $rootInfo '(?m)^modversion=1\.16\.38$' 'Root mod.info version must be 1.16.38'
Require-Text $b42Info '(?m)^modversion=1\.16\.38$' 'B42 mod.info version must be 1.16.38'
Require-Text $readme 'v1\.16\.38' 'README must include v1.16.38 notes'

Require-Text $ui 'GodSystemShortcutWindow\.RefreshIntervalMs\s*=\s*5000' 'Shortcut refresh interval must be 5000 ms'
Require-Text $ui 'function\s+GodSystemShortcutWindow:buildActionSignature\s*\(' 'Shortcut window must build an action-state signature'
Require-Text $ui 'function\s+GodSystemShortcutWindow:refreshActions\s*\(' 'Shortcut window must expose a refreshActions method'
Require-Text $ui 'function\s+GodSystemShortcutWindow:refreshActionsIfDue\s*\(' 'Shortcut window must expose a gated periodic refresh method'
Require-Text $ui 'function\s+GodSystemShortcutWindow:update\s*\(' 'Shortcut window must refresh from update() while open'
Require-Text $ui 'now\s*-\s*\(self\.lastShortcutRefreshMs\s+or\s+0\)\s*<\s*\(GodSystemShortcutWindow\.RefreshIntervalMs\s+or\s+5000\)' 'Shortcut refresh must be guarded by the 5-second interval'
Require-Text $ui 'if\s+not\s+force\s+and\s+signature\s*==\s*self\.shortcutActionSignature\s+then\s*\r?\n\s*return\s+false\s*\r?\n\s*end' 'Shortcut refresh must skip rebuilding when the action signature is unchanged'
Require-Text $ui 'self\.shortcutButtons\s*=\s*\{\}' 'Shortcut window must track generated action buttons for rebuild'
Require-Text $ui 'self:refreshActions\(true\)' 'Shortcut window must build actions immediately when opened'

if ($ui -match 'GodSystemNetwork\.requestState.*refreshActionsIfDue') {
    throw 'Shortcut periodic refresh must not request server state'
}

$files = Get-ChildItem -LiteralPath (Join-Path $Mod '42\media\lua') -Recurse -Filter *.lua
foreach ($file in $files) {
    $text = Read-Utf8 $file.FullName
    if ($text.Contains([char]0xFFFD)) {
        throw "Replacement character found: $($file.FullName)"
    }
}

Write-Output 'Test-GodSystemV11638 passed'
