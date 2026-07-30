param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$adapter = Join-Path $luaRoot 'shared\GodSystem\UI\AutoLoaderAdapter.lua'
$runtime = Join-Path $PSScriptRoot 'Test-GodSystemV422012AutoLoaderAdapterRuntime.lua'
foreach ($file in @($adapter, $runtime)) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "Missing auto-loader adapter test file: $file"
    }
}

$text = [IO.File]::ReadAllText($adapter, [Text.UTF8Encoding]::new($false))
foreach ($marker in @(
    '"autoloader.state"',
    '"autoloader.deposit"',
    '"autoloader.depositBatch"',
    '"autoloader.cancel"',
    '"autoloader.withdraw"',
    '"autoloader.fill"',
    '"autoloader.reload"',
    'function instance:receive'
)) {
    if (-not $text.Contains($marker)) {
        throw "Auto-loader UI adapter contract marker missing: $marker"
    }
}
if ([regex]::IsMatch($text, '\b(?:sendClientCommand|sendServerCommand|Events)\b')) {
    throw 'Auto-loader UI adapter bypasses the modular gateway'
}

$lua = Get-Command lua -ErrorAction SilentlyContinue
if (-not $lua) {
    $fallback = Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $fallback) { $lua = Get-Item $fallback }
}
if (-not $lua) { throw 'Lua 5.1 runtime is required for auto-loader adapter validation' }
$luaPath = if ($lua.Source) { $lua.Source } else { $lua.FullName }
& $luaPath $runtime $luaRoot
if ($LASTEXITCODE -ne 0) { throw 'Auto-loader UI adapter runtime test failed' }

Write-Output 'Test-GodSystemV422012AutoLoaderAdapter passed'
