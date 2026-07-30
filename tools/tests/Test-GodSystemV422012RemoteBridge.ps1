param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$paths = @(
    (Join-Path $luaRoot 'shared\GodSystem\Runtime\Payload.lua'),
    (Join-Path $luaRoot 'shared\GodSystem\Runtime\RemoteClient.lua'),
    (Join-Path $luaRoot 'shared\GodSystem\Runtime\ServerBridge.lua')
)
foreach ($path in $paths) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Remote bridge file missing: $path" }
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if ($text -match '\b(?:Events|sendClientCommand|sendServerCommand|ModData|getPlayer|getCell)\b') {
        throw "Remote bridge crossed the platform boundary: $path"
    }
}

$lua = Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\lua.exe'
if (-not (Test-Path -LiteralPath $lua)) { throw "Lua 5.1 runtime missing: $lua" }
& $lua (Join-Path $PSScriptRoot 'Test-GodSystemV422012RemoteBridgeRuntime.lua') $luaRoot
if ($LASTEXITCODE -ne 0) { throw 'Remote bridge runtime test failed' }

Write-Output 'Test-GodSystemV422012RemoteBridge passed'
