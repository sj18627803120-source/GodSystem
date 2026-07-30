param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$migration = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua\shared\GodSystem\State\Migration422011.lua'
$runtime = Join-Path $PSScriptRoot 'Test-GodSystemMigration422011Runtime.lua'
foreach ($path in @($migration, $runtime)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing migration test file: $path" }
}

$source = [IO.File]::ReadAllText($migration, [Text.UTF8Encoding]::new($false))
foreach ($required in @(
    '42.20.1.1',
    '42.20.1.2',
    'function Migration.stage',
    'function Migration.validate',
    'function Migration.commit',
    'function Migration.run',
    'pendingTeleport',
    'transactionOperations',
    'attributeOperations',
    'validateInPlaceWhenLoaded',
    'validateCarriedInstanceOnAccess'
)) {
    if (-not $source.Contains($required)) { throw "Migration contract marker missing: $required" }
}

function Resolve-Tool([string]$Name, [string[]]$Fallbacks) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        if ($command.Source) { return $command.Source }
        return $command.Path
    }
    foreach ($fallback in $Fallbacks) {
        if (Test-Path -LiteralPath $fallback) { return $fallback }
    }
    return $null
}

$lua = Resolve-Tool 'lua' @(
    (Join-Path $env:USERPROFILE 'Tools\Lua51\lua.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\lua.exe')
)
if (-not $lua) { throw 'Lua 5.1 runtime is required for migration validation' }

& $lua $runtime $migration
if ($LASTEXITCODE -ne 0) { throw '42.20.1.1 migration runtime test failed' }

$luac = Resolve-Tool 'luac' @(
    (Join-Path $env:USERPROFILE 'Tools\Lua51\luac.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\luac.exe')
)
if (-not $luac) { throw 'Lua 5.1 compiler is required for migration validation' }

foreach ($path in @($migration, $runtime)) {
    & $luac -p $path
    if ($LASTEXITCODE -ne 0) { throw "Lua 5.1 compile failed: $path" }
}

Write-Output 'Test-GodSystemMigration422011 passed'
