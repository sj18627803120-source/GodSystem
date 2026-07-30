param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$adapter = Join-Path $luaRoot 'shared\GodSystem\UI\StorageAdapter.lua'
$runtime = Join-Path $PSScriptRoot 'Test-GodSystemV422012StorageAdapterRuntime.lua'
foreach ($file in @($adapter, $runtime)) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "Missing storage adapter test file: $file"
    }
}

$text = [IO.File]::ReadAllText($adapter, [Text.UTF8Encoding]::new($false))
foreach ($marker in @(
    '"storage.networkState"',
    '"storage.index"',
    '"storage.snapshot"',
    '"storage.details"',
    '"storage.execute"',
    'objectReference',
    'function instance:poll()'
)) {
    if (-not $text.Contains($marker)) {
        throw "Storage UI adapter contract marker missing: $marker"
    }
}
if ([regex]::IsMatch($text, '\b(?:sendClientCommand|sendServerCommand|Events)\b')) {
    throw 'Storage UI adapter bypasses the modular gateway'
}

$lua = Get-Command lua -ErrorAction SilentlyContinue
if (-not $lua) {
    $fallback = Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $fallback) { $lua = Get-Item $fallback }
}
if (-not $lua) { throw 'Lua 5.1 runtime is required for storage adapter validation' }
$luaPath = if ($lua.Source) { $lua.Source } else { $lua.FullName }
& $luaPath $runtime $luaRoot
if ($LASTEXITCODE -ne 0) { throw 'Storage UI adapter runtime test failed' }

Write-Output 'Test-GodSystemV422012StorageAdapter passed'
