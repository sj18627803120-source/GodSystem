param([string]$Root = "")

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$snapshotPath = Join-Path $luaRoot 'shared\GodSystem\Runtime\ConfigSnapshot.lua'
$runtimeTest = Join-Path $PSScriptRoot 'Test-GodSystemV422012ConfigSnapshotRuntime.lua'
foreach ($path in @($snapshotPath, $runtimeTest)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Config snapshot file is missing: $path"
    }
}

$text = [IO.File]::ReadAllText($snapshotPath, [Text.Encoding]::UTF8)
foreach ($section in @(
    'snapshot.tasks',
    'snapshot.shop',
    'snapshot.recycle',
    'snapshot.upgrades',
    'snapshot.medical',
    'snapshot.home',
    'snapshot.bank',
    'snapshot.companion',
    'snapshot.autoLoader',
    'snapshot.eligibility'
)) {
    if ($text -notmatch [regex]::Escape($section)) {
        throw "Config snapshot section is missing: $section"
    }
}
if ($text -notmatch 'row\.categoryKey\s*=\s*row\.group') {
    throw 'ShopItems.group is not mapped to categoryKey'
}
if (($text -notmatch 'AdminRuntimeItemOverrides') -or
    ($text -notmatch 'sanitizeItemOverride') -or
    ($text -notmatch 'itemOverrides')) {
    throw 'Admin sandbox item override entry is not preserved'
}
if (($text -notmatch 'local function copy\(') -or
    ($text -notmatch 'local snapshot = copy\(source\)')) {
    throw 'Config snapshot does not detach nested published config tables'
}
if ($text -match 'GodSystemConfig\.[A-Za-z0-9_]+\s*=') {
    throw 'Config snapshot writes to published GodSystemConfig'
}

$luaExe = Get-Command lua5.1,lua -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $luaExe) {
    $candidate = Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\lua5.1.exe'
    if (Test-Path -LiteralPath $candidate) { $luaExe = Get-Item -LiteralPath $candidate }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for config snapshot validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath $runtimeTest $luaRoot
if ($LASTEXITCODE -ne 0) { throw 'Config snapshot runtime test failed' }

$luacExe = Get-Command luac5.1,luac -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $luacExe) {
    $candidate = Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\luac5.1.exe'
    if (Test-Path -LiteralPath $candidate) { $luacExe = Get-Item -LiteralPath $candidate }
}
if (-not $luacExe) { throw 'Lua 5.1 compiler is required for config snapshot validation' }
$luacPath = if ($luacExe.Source) { $luacExe.Source } else { $luacExe.FullName }
foreach ($path in @($snapshotPath, $runtimeTest)) {
    & $luacPath -p $path
    if ($LASTEXITCODE -ne 0) {
        throw "Config snapshot Lua 5.1 compile failed: $path"
    }
}

Write-Output 'Test-GodSystemV422012ConfigSnapshot passed'
