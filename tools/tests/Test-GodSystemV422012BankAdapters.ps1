param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$bankRoot = Join-Path $luaRoot 'shared\GodSystem\Platform\Bank'
$runtimeTest = Join-Path $PSScriptRoot 'Test-GodSystemV422012BankAdaptersRuntime.lua'
$files = @(
    (Join-Path $luaRoot 'shared\GodSystem\Platform\WalletAccounts.lua'),
    (Join-Path $luaRoot 'shared\GodSystem\Platform\WalletFunds.lua'),
    (Join-Path $bankRoot 'Support.lua'),
    (Join-Path $bankRoot 'State.lua'),
    (Join-Path $bankRoot 'Clock.lua'),
    (Join-Path $bankRoot 'Random.lua'),
    (Join-Path $bankRoot 'Features.lua'),
    (Join-Path $bankRoot 'Audit.lua'),
    (Join-Path $bankRoot 'Debt.lua'),
    (Join-Path $bankRoot 'Descriptors.lua'),
    $runtimeTest
)
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file)) { throw "Missing Bank adapter file: $file" }
}

$combined = ($files | ForEach-Object {
    [IO.File]::ReadAllText($_, [Text.UTF8Encoding]::new($false))
}) -join "`n"

foreach ($descriptorId in @(
    'wallet.accounts', 'wallet.funds', 'bank.state', 'bank.clock',
    'bank.random', 'bank.features', 'bank.audit', 'bank.debt'
)) {
    if ($combined -notmatch [regex]::Escape('"' + $descriptorId + '"')) {
        throw "Bank adapter descriptor is missing: $descriptorId"
    }
}
if ($combined -match 'require\s+"(?:GodSystem_Config|GodSystem_AdminConfig|GodSystem_Core|GodSystem_Server|GodSystem_UI)"') {
    throw 'Bank adapters require a legacy business implementation'
}
$walletFunds = [IO.File]::ReadAllText($files[1], [Text.UTF8Encoding]::new($false))
if ($walletFunds -notmatch 'Descriptor\.dependencies\s*=\s*\{\s*"wallet\.accounts"\s*\}') {
    throw 'wallet.funds does not explicitly depend on wallet.accounts'
}
if ($walletFunds -match 'state\.accounts') {
    throw 'wallet.funds still owns a second current-account state'
}
$bankState = [IO.File]::ReadAllText((Join-Path $bankRoot 'State.lua'),
    [Text.UTF8Encoding]::new($false))
if ($bankState -notmatch 'accounts\.get' -or $bankState -notmatch 'accounts\.set') {
    throw 'bank.state does not map current balance to wallet.accounts'
}
if ($combined -notmatch 'addZombiesInOutfit' -or $combined -notmatch 'SandboxVars') {
    throw 'Bank PZ feature/debt adapters are incomplete'
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

$luaExe = Resolve-Tool 'lua' @(
    (Join-Path $env:USERPROFILE 'Tools\Lua51\lua.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\lua.exe')
)
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for Bank adapter validation' }
& $luaExe $runtimeTest $luaRoot
if ($LASTEXITCODE -ne 0) { throw 'Bank adapter runtime test failed' }

$luac = Resolve-Tool 'luac' @(
    (Join-Path $env:USERPROFILE 'Tools\Lua51\luac.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\luac.exe')
)
if (-not $luac) { throw 'Lua 5.1 compiler is required for Bank adapter validation' }
foreach ($file in $files) {
    & $luac -p $file
    if ($LASTEXITCODE -ne 0) { throw "Bank adapter Lua 5.1 compile failed: $file" }
}

Write-Output 'Test-GodSystemV422012BankAdapters passed'
