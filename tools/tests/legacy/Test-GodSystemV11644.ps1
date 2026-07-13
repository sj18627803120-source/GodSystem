$ErrorActionPreference = 'Stop'

$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Lua = Join-Path $Mod '42\media\lua'

$ConfigPath = Join-Path $Lua 'shared\GodSystem_Config.lua'
$OverridePath = Join-Path $Lua 'shared\GodSystem_Localization_Override.lua'
$CnPath = Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt'
$ChPath = Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt'
$UiPath = Join-Path $Lua 'client\GodSystem_UI.lua'

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

$config = Read-Utf8 $ConfigPath
$override = Read-Utf8 $OverridePath
$cn = Read-Utf8 $CnPath
$ch = Read-Utf8 $ChPath
$ui = Read-Utf8 $UiPath
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.44"' 'Config version must be 1.16.44'
Require-Text $rootInfo '(?m)^modversion=1\.16\.44$' 'Root mod.info version must be 1.16.44'
Require-Text $b42Info '(?m)^modversion=1\.16\.44$' 'B42 mod.info version must be 1.16.44'

$keys = @(
    'Btn_BankBorrowLoan',
    'Btn_BankRepayLoan',
    'Btn_BankPayoffLoan',
    'Bank_LoanSummary',
    'Bank_LoanPlanSingle',
    'Bank_LoanPlanInstallment',
    'Bank_LoanActive',
    'Bank_LoanPrompt',
    'Bank_LoanFrozen',
    'Bank_LoanNoDebt',
    'Bank_LoanDueNow',
    'Bank_LoanPayoff',
    'Bank_LoanOverdue',
    'Notify_BankLoanBorrowed',
    'Notify_BankLoanRepaid',
    'Notify_BankLoanPayoff',
    'Notify_BankLoanActive',
    'Notify_BankLoanFrozen',
    'Notify_BankLoanCreditLow',
    'Notify_BankLoanNoActive',
    'Notify_BankLoanNoDue',
    'Notify_BankLoanBankruptcy',
    'History_BankLoanBorrowed',
    'History_BankLoanRepaid',
    'History_BankLoanPayoff',
    'History_BankLoanBankruptcy'
)

foreach ($key in $keys) {
    $translatePattern = '(?m)^\s*IGUI_GodSystem_' + [regex]::Escape($key) + '\s*=\s*".*",\s*$'
    Require-Text $cn $translatePattern "CN translate entry must end with comma: $key"
    Require-Text $ch $translatePattern "CH translate entry must end with comma: $key"

    $fallbackPattern = '(?m)^GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]\s*=\s*"([^"]*)"\s*$'
    $match = [regex]::Match($override, $fallbackPattern)
    if (-not $match.Success) {
        throw "Fallback entry missing: $key"
    }
    $value = $match.Groups[1].Value
    if ($value -match '[^\x00-\x7F]') {
        throw "Fallback entry must use ASCII byte escapes: $key"
    }
}

foreach ($key in @(
    'AdminSetting_EnableBankLoan',
    'AdminSetting_EnableBankLoan_Desc',
    'AdminSetting_BankLoanBaseCredit',
    'AdminSetting_BankLoanBaseCredit_Desc',
    'AdminSetting_BankLoanCreditSpendStep',
    'AdminSetting_BankLoanCreditSpendStep_Desc',
    'AdminSetting_BankLoanCreditPerStep',
    'AdminSetting_BankLoanCreditPerStep_Desc',
    'AdminSetting_BankLoanSingleInterestRate',
    'AdminSetting_BankLoanSingleInterestRate_Desc',
    'AdminSetting_BankLoanOverduePenaltyDailyRate',
    'AdminSetting_BankLoanOverduePenaltyDailyRate_Desc',
    'AdminSetting_BankLoanOverduePenaltyMaxRate',
    'AdminSetting_BankLoanOverduePenaltyMaxRate_Desc',
    'AdminSetting_BankLoanBankruptcyGraceHours',
    'AdminSetting_BankLoanBankruptcyGraceHours_Desc',
    'AdminSetting_BankLoanFreezeHours',
    'AdminSetting_BankLoanFreezeHours_Desc',
    'AdminSetting_BankLoanZombieDebtPerZombie',
    'AdminSetting_BankLoanZombieDebtPerZombie_Desc',
    'AdminSetting_BankLoanZombieMaxCount',
    'AdminSetting_BankLoanZombieMaxCount_Desc'
)) {
    $fallbackPattern = '(?m)^GodSystemFallbackText\.zh\["' + [regex]::Escape($key) + '"\]\s*=\s*"([^"]*)"\s*$'
    $match = [regex]::Match($override, $fallbackPattern)
    if (-not $match.Success) {
        throw "Admin fallback entry missing: $key"
    }
    if ($match.Groups[1].Value -match '[^\x00-\x7F]') {
        throw "Admin fallback entry must use ASCII byte escapes: $key"
    }
}

Require-Text $ui 'Bank_LoanSummary' 'Bank loan UI should still use localization keys'
Write-Output 'Test-GodSystemV11644 passed'
