$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$luaRoot = Join-Path $root 'Contents\mods\GodSystem\42\media\lua'
$runtime = Join-Path $PSScriptRoot 'Test-GodSystemV422012UIActionAdapterRuntime.lua'
$lua = Get-Command lua5.1 -ErrorAction SilentlyContinue
if (-not $lua) {
    $candidate = Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $candidate) { $lua = Get-Item -LiteralPath $candidate }
}
if (-not $lua) { throw 'Lua 5.1 runtime not found' }

& $lua.Source $runtime ($luaRoot -replace '\\', '/')
if ($LASTEXITCODE -ne 0) { throw 'UI action adapter runtime test failed' }
Write-Host 'Test-GodSystemV422012UIActionAdapter passed'
