$ErrorActionPreference = 'Stop'

$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Lua = Join-Path $Mod '42\media\lua'

$ConfigPath = Join-Path $Lua 'shared\GodSystem_Config.lua'
$AdminPath = Join-Path $Lua 'shared\GodSystem_AdminConfig.lua'
$OverridePath = Join-Path $Lua 'shared\GodSystem_Localization_Override.lua'
$CnPath = Join-Path $Lua 'shared\Translate\CN\IG_UI_CN.txt'
$ChPath = Join-Path $Lua 'shared\Translate\CH\IG_UI_CH.txt'
$CorePath = Join-Path $Lua 'client\GodSystem_Core.lua'
$NetworkPath = Join-Path $Lua 'client\GodSystem_Network.lua'
$UiPath = Join-Path $Lua 'client\GodSystem_UI.lua'
$ServerPath = Join-Path $Lua 'server\GodSystem_Server.lua'

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

$config = Read-Utf8 $ConfigPath
$admin = Read-Utf8 $AdminPath
$override = Read-Utf8 $OverridePath
$cn = Read-Utf8 $CnPath
$ch = Read-Utf8 $ChPath
$core = Read-Utf8 $CorePath
$network = Read-Utf8 $NetworkPath
$ui = Read-Utf8 $UiPath
$server = Read-Utf8 $ServerPath
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')
$readmePath = Get-ChildItem -LiteralPath $Root -File -Filter 'README_*.md' | Select-Object -First 1 -ExpandProperty FullName
if (-not $readmePath) { throw 'Workshop upload README not found' }
$readme = Read-Utf8 $readmePath

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.46"' 'Config version must be 1.16.46'
Require-Text $rootInfo '(?m)^modversion=1\.16\.46$' 'Root mod.info version must be 1.16.46'
Require-Text $b42Info '(?m)^modversion=1\.16\.46$' 'B42 mod.info version must be 1.16.46'
Require-Text $workshop '(?m)^description=v1\.16\.46$' 'Workshop metadata must mention v1.16.46'
Require-Text $readme 'v1\.16\.46' 'Workshop upload README must mention v1.16.46'

Require-Text $config 'BankInvestmentSettlementHours\s*=\s*24' 'Investment settlement interval must default to 24 online game hours'
Require-Text $config 'BankInvestmentMinAmount\s*=\s*1' 'Investment minimum must default to 1 coin'
Require-Text $config 'BankAllowNewFixedDeposits\s*=\s*false' 'New legacy fixed deposits must be disabled'
Require-Text $config 'stable\s*=\s*\{[^\r\n]*gainChance\s*=\s*70[^\r\n]*lossChance\s*=\s*5[^\r\n]*gainPercent\s*=\s*1[^\r\n]*lossPercent\s*=\s*1' 'Stable investment defaults are missing'
Require-Text $config 'balanced\s*=\s*\{[^\r\n]*gainChance\s*=\s*55[^\r\n]*lossChance\s*=\s*30[^\r\n]*gainPercent\s*=\s*3[^\r\n]*lossPercent\s*=\s*2' 'Balanced investment defaults are missing'
Require-Text $config 'aggressive\s*=\s*\{[^\r\n]*gainChance\s*=\s*45[^\r\n]*lossChance\s*=\s*45[^\r\n]*gainPercent\s*=\s*8[^\r\n]*lossPercent\s*=\s*5' 'Aggressive investment defaults are missing'

foreach ($text in @($core, $server)) {
    Require-Text $text 'autoTaskClaimEnabled\s*=.*==\s*true' 'Auto-task toggle must be initialized and persisted'
    Require-Text $text 'lastAutoTaskClaimHour' 'Auto-task last execution hour must be persisted'
    Require-Text $text 'autoDepositEnabled\s*=.*==\s*true' 'Auto-deposit toggle must be initialized and persisted'
    Require-Text $text 'lastAutoDepositHour' 'Auto-deposit last execution hour must be persisted'
    Require-Text $text 'bank\.investments' 'Investment accounts must be initialized in bank data'
}

Require-Text $core 'function\s+GodSystem\.toggleAutoTaskClaim\s*\(' 'SP auto-task toggle helper missing'
Require-Text $core 'function\s+GodSystem\.processAutoTaskClaim\s*\(' 'SP auto-task processor missing'
Require-Text $core 'function\s+GodSystem\.toggleBankAutoDeposit\s*\(' 'SP auto-deposit toggle helper missing'
Require-Text $core 'function\s+GodSystem\.processBankAutoDeposit\s*\(' 'SP auto-deposit processor missing'
Require-Text $core 'lastAutoDepositHour\s*=\s*gsNowHours\s*\(\)' 'SP auto-deposit must start from the exact current game hour'
Require-Text $core 'lastAutoTaskClaimHour\s*=\s*gsNowHours\s*\(\)' 'SP auto-task must start from the exact current game hour'
Require-Text $core 'function\s+GodSystem\.investBankCurrent\s*\(' 'SP current-account investment helper missing'
Require-Text $core 'function\s+GodSystem\.investBankCash\s*\(' 'SP cash investment helper missing'
Require-Text $core 'function\s+GodSystem\.redeemBankInvestment\s*\(' 'SP investment redemption helper missing'
Require-Text $core 'function\s+GodSystem\.updateBankInvestments\s*\(' 'SP online investment settlement helper missing'
Require-Text $core 'math\.max\s*\(\s*1\s*,\s*math\.floor\s*\(' 'Investment non-flat result must change by at least 1 coin'
Require-Text $core 'BankAllowNewFixedDeposits\s*~=\s*true[\s\S]*?Notify_BankFixedCreationClosed' 'SP legacy fixed creation must be rejected'

Require-Text $network 'function\s+GodSystemNetwork\.updateAutoTaskClaim\s*\(' 'MP auto-task scheduler missing'
Require-Text $network 'function\s+GodSystemNetwork\.updateBankAutoDeposit\s*\(' 'MP auto-deposit scheduler missing'
Require-Text $network '(?s)updateWaistAutoRecycle\s*\(\s*\).*updateAutoTaskClaim\s*\(\s*\).*updateBankAutoDeposit\s*\(\s*\)' 'MP automatic actions must run waist -> task -> deposit'
Require-Text $network 'action\s*=\s*"autoClaim"' 'MP auto-task request must use task autoClaim action'
Require-Text $network 'action\s*=\s*"depositAllCash"[^\r\n]*auto\s*=\s*true' 'MP auto-deposit must reuse silent depositAllCash'
Require-Text $network 'return\s+GameTime:getInstance\(\):getWorldAgeHours\(\)' 'MP automatic actions must use precise game hours instead of floor-rounded hours'
Require-Text $network '#claims\s*<=\s*0[\s\S]*?lastAutoTaskClaimHour\s*=\s*nowHour' 'MP auto-task must skip empty batches locally'
Require-Text $network 'getCurrencyTotal[\s\S]*?lastAutoDepositHour\s*=\s*nowHour[\s\S]*?return' 'MP auto-deposit must skip empty cash locally'
Require-Text $network 'getWaistSpaceRecycleGroups[\s\S]*?lastWaistAutoRecycleHour\s*=\s*nowHour' 'MP waist automation must skip empty waist bags locally'

Require-Text $server 'action\s*==\s*"toggleAutoDeposit"' 'Server bank toggleAutoDeposit action missing'
Require-Text $server 'action\s*==\s*"investFromCurrent"' 'Server bank investFromCurrent action missing'
Require-Text $server 'action\s*==\s*"investFromCash"' 'Server bank investFromCash action missing'
Require-Text $server 'action\s*==\s*"redeemInvestment"' 'Server bank redeemInvestment action missing'
Require-Text $server 'action\s*==\s*"toggleAutoClaim"' 'Server task toggleAutoClaim action missing'
Require-Text $server 'action\s*==\s*"autoClaim"' 'Server task autoClaim action missing'
Require-Text $server 'lastAutoDepositHour\s*=\s*nowHours\s*\(\)' 'Server auto-deposit must persist the exact game hour'
Require-Text $server 'lastAutoTaskClaimHour\s*=\s*nowHours\s*\(\)' 'Server auto-task must persist the exact game hour'
Require-Text $server 'BankAllowNewFixedDeposits\s*~=\s*true[\s\S]*?BankFixedCreationClosed' 'MP legacy fixed creation must be rejected'
Require-Text $server 'args\s+and\s+args\.auto\s*==\s*true[\s\S]*?kind\s*=\s*"autoWaistRecycle"' 'Server must keep empty automatic waist checks silent'
Require-Text $server 'local\s+function\s+claimTaskForPlayer\s*\(' 'Server manual and automatic task claims must share one helper'
Require-Text $server 'local\s+function\s+updateBankInvestments\s*\(' 'Server online investment settlement helper missing'
Require-Text $server 'investmentOnlineSessions' 'Server must use session-only investment timing to avoid offline settlement'
Require-Text $server 'finishCode\s*\([^\r\n]*"AutoTaskClaimed"' 'Auto-task result must use structured finishCode'
Require-Text $server 'for\s+i\s*=\s*1\s*,\s*#claims\s+do' 'Server auto-task must process every completed task submitted in the hourly batch'
Require-Text $server 'playerUpdateTicks\s*=\s*\{\}' 'Server player update throttling must be isolated per player'
if ($server -match 'local\s+_tick\s*=\s*0') {
    throw 'Server must not use one global OnPlayerUpdate tick counter for all players'
}

$adminKeys = @(
    'EnableBankInvestments',
    'BankInvestmentMinAmount',
    'BankInvestmentStableGainChance', 'BankInvestmentStableLossChance', 'BankInvestmentStableGainPercent', 'BankInvestmentStableLossPercent',
    'BankInvestmentBalancedGainChance', 'BankInvestmentBalancedLossChance', 'BankInvestmentBalancedGainPercent', 'BankInvestmentBalancedLossPercent',
    'BankInvestmentAggressiveGainChance', 'BankInvestmentAggressiveLossChance', 'BankInvestmentAggressiveGainPercent', 'BankInvestmentAggressiveLossPercent'
)
foreach ($key in $adminKeys) {
    Require-Text $admin ('key\s*=\s*"' + [regex]::Escape($key) + '"') "Admin investment setting missing: $key"
}
Require-Text $admin '100\s*-\s*gainChance' 'Admin probability sanitizer must derive flat chance by limiting gain+loss to 100'
Require-Text $admin 'result\[lossKey\]\s*=\s*math\.min' 'Admin snapshots must store the same compressed loss chance used for settlement'

$populateBank = [regex]::Match($ui, '(?s)function\s+GodSystemWindow:populateBank\s*\(\).*?(?=function\s+GodSystemWindow:)').Value
Require-Text $populateBank 'bankInvestment' 'Bank UI must list investment accounts'
if ($populateBank -match 'getBankFixedTerms\s*\(') {
    throw 'Bank UI must not offer new legacy fixed terms'
}
Require-Text $populateBank 'bank\.fixed' 'Bank UI must continue listing legacy fixed deposits'
Require-Text $ui 'Btn_BankAutoDepositOn' 'Bank auto-deposit button text missing'
Require-Text $ui 'Btn_BankAutoDepositOff' 'Bank auto-deposit button text missing'
Require-Text $ui 'Btn_TaskAutoClaimOn' 'Task auto-claim button text missing'
Require-Text $ui 'Btn_TaskAutoClaimOff' 'Task auto-claim button text missing'
Require-Text $ui 'kind\s*=\s*"bankInvestment"' 'Investment rows must use a stable payload kind'
Require-Text $ui 'payload\.kind\s*==\s*"bankInvestment"[\s\S]*?bankInvestment:' 'Investment selection must be restored by a stable tier id after state refresh'
Require-Text $ui 'local\s+args\s*=\s*\{\}[\s\S]*?entry\.args' 'History localization must copy structured args instead of mutating persisted history'

# Old fixed deposits remain withdrawable even though new term creation is removed from the UI.
Require-Text $core 'function\s+GodSystem\.withdrawBankFixed\s*\(' 'Legacy SP fixed withdrawal must remain'
Require-Text $server 'action\s*==\s*"withdrawFixed"' 'Legacy MP fixed withdrawal must remain'

$keys = @(
    'Btn_BankAutoDepositOn', 'Btn_BankAutoDepositOff',
    'Btn_TaskAutoClaimOn', 'Btn_TaskAutoClaimOff',
    'Btn_BankInvestCurrent', 'Btn_BankInvestCash', 'Btn_BankInvestmentRedeem',
    'Bank_InvestmentStable', 'Bank_InvestmentBalanced', 'Bank_InvestmentAggressive',
    'Bank_InvestmentLocked', 'Bank_InvestmentRedeemable', 'Bank_InvestmentProgress', 'Bank_InvestmentLastResult',
    'Notify_AutoDepositEnabled', 'Notify_AutoDepositDisabled',
    'Notify_AutoTaskClaimEnabled', 'Notify_AutoTaskClaimDisabled',
    'Notify_BankInvestmentCreated', 'Notify_BankInvestmentRedeemed', 'Notify_BankInvestmentLocked',
    'Notify_BankInvestmentSettled', 'Notify_BankFixedCreationClosed', 'NotifyMP_AutoDepositEnabled', 'NotifyMP_AutoDepositDisabled',
    'NotifyMP_AutoTaskClaimEnabled', 'NotifyMP_AutoTaskClaimDisabled', 'NotifyMP_AutoTaskClaimed',
    'NotifyMP_BankInvestmentCreated', 'NotifyMP_BankInvestmentRedeemed', 'NotifyMP_BankInvestmentLocked',
    'NotifyMP_BankInvestmentSettled', 'NotifyMP_BankCurrentNotEnough', 'NotifyMP_BankFixedCreationClosed',
    'NotifyMP_TaskStateInvalid', 'NotifyMP_TaskFailed', 'NotifyMP_TaskIncomplete', 'NotifyMP_TaskTurnInNotEnough', 'NotifyMP_TaskClaimed',
    'HistoryMP_BankInvestmentSettled'
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
    if ($match.Groups[1].Value -match '[^\x00-\x7F]') {
        throw "Fallback entry must use ASCII byte escapes: $key"
    }
}

Write-Output 'Test-GodSystemV11646 passed'
