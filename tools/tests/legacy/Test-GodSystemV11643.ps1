$ErrorActionPreference = 'Stop'

$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Lua = Join-Path $Mod '42\media\lua'

$CorePath = Join-Path $Lua 'client\GodSystem_Core.lua'
$ServerPath = Join-Path $Lua 'server\GodSystem_Server.lua'
$UiPath = Join-Path $Lua 'client\GodSystem_UI.lua'
$ConfigPath = Join-Path $Lua 'shared\GodSystem_Config.lua'
$AdminPath = Join-Path $Lua 'shared\GodSystem_AdminConfig.lua'
$OverridePath = Join-Path $Lua 'shared\GodSystem_Localization_Override.lua'
$CnPath = Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt'
$ChPath = Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt'
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

function Require-NoText([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) {
        throw $Message
    }
}

$core = Read-Utf8 $CorePath
$server = Read-Utf8 $ServerPath
$ui = Read-Utf8 $UiPath
$config = Read-Utf8 $ConfigPath
$admin = Read-Utf8 $AdminPath
$override = Read-Utf8 $OverridePath
$cn = Read-Utf8 $CnPath
$ch = Read-Utf8 $ChPath
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$readme = Read-Utf8 $ReadmePath

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.43"' 'Config version must be 1.16.43'
Require-Text $rootInfo '(?m)^modversion=1\.16\.43$' 'Root mod.info version must be 1.16.43'
Require-Text $b42Info '(?m)^modversion=1\.16\.43$' 'B42 mod.info version must be 1.16.43'
Require-Text $readme 'v1\.16\.43' 'README must include v1.16.43 notes'

foreach ($pattern in @(
    'BankLoanBaseCredit\s*=\s*2000',
    'BankLoanCreditSpendStep\s*=\s*100',
    'BankLoanCreditPerStep\s*=\s*5',
    'BankLoanSingleDueHours\s*=\s*72',
    'BankLoanSingleInterestRate\s*=\s*0\.05',
    'BankLoanPeriodHours\s*=\s*72',
    'BankLoanInstallmentPlans',
    'periods\s*=\s*3[\s\S]*totalInterestRate\s*=\s*0\.10',
    'periods\s*=\s*5[\s\S]*totalInterestRate\s*=\s*0\.18',
    'periods\s*=\s*10[\s\S]*totalInterestRate\s*=\s*0\.30',
    'BankLoanBankruptcyGraceHours\s*=\s*240',
    'BankLoanFreezeHours\s*=\s*168',
    'BankLoanZombieDebtPerZombie\s*=\s*50',
    'BankLoanZombieMaxCount\s*=\s*100',
    'BankLoanZombieMinDistance\s*=\s*20',
    'BankLoanZombieMaxDistance\s*=\s*45'
)) {
    Require-Text $config $pattern "Missing loan config pattern: $pattern"
}

foreach ($pattern in @(
    'EnableBankLoan',
    'BankLoanBaseCredit',
    'BankLoanCreditSpendStep',
    'BankLoanCreditPerStep',
    'BankLoanSingleInterestRate',
    'BankLoanZombieDebtPerZombie',
    'AdminSetting_BankLoanBaseCredit'
)) {
    Require-Text $admin $pattern "Admin config missing $pattern"
}

foreach ($text in @($core, $server)) {
    foreach ($pattern in @(
        'loanCreditSpentOffset',
        'loanFrozenUntilHour',
        'loanBankruptcyCount',
        'getBankLoanPlans',
        'getBankLoanSummary',
        'borrowBankLoan',
        'repayBankLoanDue',
        'payoffBankLoan',
        'applyBankLoanBankruptcy',
        'spawnBankLoanDebtZombies',
        'borrowLoan',
        'repayLoanDue',
        'payoffLoan'
    )) {
        Require-Text $text $pattern "Loan runtime missing $pattern"
    }
    Require-NoText $text 'data\.stats\.spentPoints\s*=\s*0' 'Loan bankruptcy must not reset spentPoints directly'
    Require-NoText $text 'bank\.fixed\s*=\s*\{\}' 'Loan bankruptcy must not clear fixed deposits'
}

Require-Text $server 'addZombiesInOutfit' 'Server bankruptcy should use addZombiesInOutfit when spawning debt zombies'
Require-Text $ui 'kind\s*=\s*"bankLoanPlan"' 'Bank UI must show loan plan rows'
Require-Text $ui 'kind\s*=\s*"bankLoanActive"' 'Bank UI must show active loan row'
Require-Text $ui 'Btn_BankBorrowLoan' 'Bank UI must expose borrow button'
Require-Text $ui 'Btn_BankRepayLoan' 'Bank UI must expose repay button'
Require-Text $ui 'Btn_BankPayoffLoan' 'Bank UI must expose payoff button'
Require-Text $ui '"borrowLoan"' 'Bank UI must send borrowLoan action'
Require-Text $ui '"repayLoanDue"' 'Bank UI must send repayLoanDue action'
Require-Text $ui '"payoffLoan"' 'Bank UI must send payoffLoan action'

foreach ($text in @($cn, $ch, $override)) {
    foreach ($pattern in @(
        'Bank_LoanSummary',
        'Bank_LoanPlanSingle',
        'Bank_LoanPlanInstallment',
        'Bank_LoanActive',
        'Btn_BankBorrowLoan',
        'Btn_BankRepayLoan',
        'Btn_BankPayoffLoan',
        'Notify_BankLoanBorrowed',
        'Notify_BankLoanRepaid',
        'Notify_BankLoanBankruptcy',
        'AdminSetting_BankLoanBaseCredit'
    )) {
        Require-Text $text $pattern "Localization missing $pattern"
    }
}

$files = Get-ChildItem -LiteralPath $Lua -Recurse -Filter *.lua
foreach ($file in $files) {
    $text = Read-Utf8 $file.FullName
    if ($text.Contains([char]0xFFFD)) {
        throw "Replacement character found: $($file.FullName)"
    }
}

Write-Output 'Test-GodSystemV11643 passed'
