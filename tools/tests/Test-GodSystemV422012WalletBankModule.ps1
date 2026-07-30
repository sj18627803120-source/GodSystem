param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Lua = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$files = @(
    (Join-Path $Lua 'shared\GodSystem\Features\Wallet\Module.lua'),
    (Join-Path $Lua 'shared\GodSystem\Features\Bank\Rules.lua'),
    (Join-Path $Lua 'shared\GodSystem\Features\Bank\Module.lua'),
    (Join-Path $PSScriptRoot 'Test-GodSystemV422012WalletBankModuleRuntime.lua')
)
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file)) { throw "Missing wallet/bank module file: $file" }
}

function Read-Utf8([string]$Path) {
    [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false))
}

$wallet = Read-Utf8 $files[0]
$rules = Read-Utf8 $files[1]
$bank = Read-Utf8 $files[2]

foreach ($text in @($wallet, $rules, $bank)) {
    if ($text -match 'require\s+["''](?:GodSystem_Core|GodSystem_Server|GodSystem_UI)["'']') {
        throw 'Strict wallet/bank module requires a legacy implementation'
    }
    if ([regex]::IsMatch($text, '\b(?:Events|sendClientCommand|sendServerCommand)\b')) {
        throw 'Wallet/bank domain module accesses a raw PZ event or command gateway'
    }
}

foreach ($marker in @(
    'Descriptor.id = "feature.wallet"',
    '"wallet.funds"',
    '"operations"',
    'getBalance = balance',
    'grant = grant',
    'charge = charge',
    'refund = refund',
    'transfer = transfer'
)) {
    if (-not $wallet.Contains($marker)) { throw "Wallet contract marker missing: $marker" }
}

foreach ($marker in @(
    'Descriptor.id = "feature.bank"',
    '"bank.state"',
    '"bank.clock"',
    '"bank.random"',
    '"bank.features"',
    '"bank.audit"',
    '"bank.debt"',
    '"operations"',
    'deposit = true',
    'withdraw = true',
    'withdrawFixed = true',
    'investFromCurrent = true',
    'investFromCash = true',
    'redeemInvestment = true',
    'borrowLoan = true',
    'repayLoanDue = true',
    'payoffLoan = true'
)) {
    if (-not $bank.Contains($marker)) { throw "Bank contract marker missing: $marker" }
}

foreach ($marker in @(
    'earlyWithdrawPenaltyRatio = 0.05',
    'investmentSettlementHours = 24',
    'gainChance = 70',
    'gainChance = 55',
    'gainChance = 45',
    'loanBaseCredit = 2000',
    'loanSingleDueHours = 72',
    'loanSingleInterestRate = 0.05',
    '{ id = "i3", periods = 3, totalInterestRate = 0.10 }',
    '{ id = "i5", periods = 5, totalInterestRate = 0.18 }',
    '{ id = "i10", periods = 10, totalInterestRate = 0.30 }',
    'loanOverduePenaltyDailyRate = 0.05',
    'loanOverduePenaltyMaxRate = 0.50',
    'loanBankruptcyGraceHours = 240'
)) {
    if (-not $rules.Contains($marker)) { throw "Published bank rule marker missing: $marker" }
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
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for wallet/bank validation' }

& $luaExe $files[3] $Lua
if ($LASTEXITCODE -ne 0) { throw 'Wallet/bank module runtime test failed' }

$luac = Resolve-Tool 'luac' @(
    (Join-Path $env:USERPROFILE 'Tools\Lua51\luac.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\luac.exe')
)
if (-not $luac) { throw 'Lua 5.1 compiler is required for wallet/bank validation' }
foreach ($file in $files) {
    & $luac -p $file
    if ($LASTEXITCODE -ne 0) { throw "Lua 5.1 compile failed: $file" }
}

Write-Output 'Test-GodSystemV422012WalletBankModule passed'
