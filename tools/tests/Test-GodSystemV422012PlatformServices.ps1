param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Lua = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$required = @(
    'shared\GodSystem\Services\Clock.lua',
    'shared\GodSystem\Services\Random.lua',
    'shared\GodSystem\Services\Operations.lua',
    'shared\GodSystem\Platform\WalletAccounts.lua',
    'shared\GodSystem\Platform\WalletFunds.lua'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $Lua $relative))) {
        throw "Missing modular platform service: $relative"
    }
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for platform service validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }

& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV422012PlatformServicesRuntime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'Platform service runtime test failed' }

Write-Output 'Test-GodSystemV422012PlatformServices passed'
