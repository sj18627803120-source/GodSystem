$ErrorActionPreference = "Stop"

$root = "C:\Users\Admin\Zomboid\Workshop\GodSystem"
$mod = Join-Path $root "Contents\mods\GodSystem"
$lua = Join-Path $mod "42\media\lua"
$uiPath = Join-Path $lua "client\GodSystem_UI.lua"
$corePath = Join-Path $lua "client\GodSystem_Core.lua"
$networkPath = Join-Path $lua "client\GodSystem_Network.lua"
$serverPath = Join-Path $lua "server\GodSystem_Server.lua"
$configPath = Join-Path $lua "shared\GodSystem_Config.lua"
$rootInfoPath = Join-Path $mod "mod.info"
$b42InfoPath = Join-Path $mod "42\mod.info"
$workshopPath = Join-Path $root "workshop.txt"

foreach ($path in @($uiPath, $corePath, $networkPath, $serverPath, $configPath, $rootInfoPath, $b42InfoPath, $workshopPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required file: $path"
    }
}

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Assert-Contains([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotContains([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) {
        throw $Message
    }
}

$ui = Read-Utf8 $uiPath
$core = Read-Utf8 $corePath
$network = Read-Utf8 $networkPath
$server = Read-Utf8 $serverPath
$config = Read-Utf8 $configPath
$rootInfo = Read-Utf8 $rootInfoPath
$b42Info = Read-Utf8 $b42InfoPath
$workshop = Read-Utf8 $workshopPath

Assert-Contains $config 'GodSystemConfig\.Version\s*=\s*"\d+\.\d+\.\d+"' "Config version is not a semantic version"
Assert-Contains $rootInfo 'modversion=\d+\.\d+\.\d+' "Root mod.info version is not a semantic version"
Assert-Contains $b42Info 'modversion=\d+\.\d+\.\d+' "B42 mod.info version is not a semantic version"
Assert-Contains $workshop 'v\d+\.\d+\.\d+' "workshop.txt does not mention the current semantic version"

Assert-NotContains $ui 'onListHover' "UI still contains hover-selection hook/function"
Assert-NotContains $ui 'onMouseMove\s*=\s*function\(list,\s*dx,\s*dy\).*?selectListRowAtMouse' "List mouse move still selects rows"
Assert-Contains $ui 'function\s+GodSystemWindow:selectListRowAt\(x,\s*y,\s*list,\s*taskListName\)' "selectListRowAt does not accept explicit list/task source"
Assert-Contains $ui 'function\s+GodSystemWindow:clearOppositeTaskSelection\(taskListName\)' "Missing task dual-list selection normalizer"
Assert-Contains $ui 'function\s+GodSystemWindow:recycleItemMatchesSearch\(group\)' "Missing recycle search matcher"
Assert-Contains $ui 'self:setShopLayout\(self\.mode == "shop" or self\.mode == "recycle"\)' "Search layout is not enabled for recycle page"
Assert-Contains $ui 'self\.shopSearchPurpose\s*=\s*"recycle"' "Recycle page does not mark shared search purpose"
Assert-Contains $ui 'self:prepareActionSelection\(payload\)' "Actions do not capture selected payload before mutation"
Assert-Contains $ui 'createFixedFromCash' "Bank UI does not expose cash fixed-deposit action"
Assert-Contains $ui 'Btn_BankCreateFixedFromCash' "Bank UI missing cash fixed-deposit button text"
Assert-Contains $ui 'Btn_BankCreateFixedFromCurrent' "Bank UI missing current-account fixed-deposit button text"

Assert-Contains $core 'function\s+GodSystem\.createBankFixedEntry\(bank,\s*termId,\s*amount\)' "Core missing shared fixed-deposit creation helper"
Assert-Contains $core 'function\s+GodSystem\.createBankFixedFromCash\(termId,\s*amount\)' "Core missing createBankFixedFromCash"
Assert-Contains $core 'elseif action == "createFixedFromCash"' "Core performBankAction missing createFixedFromCash"
Assert-Contains $network 'action = action, amount = amount, termId = termId, entryId = entryId' "Network bank bridge changed unexpectedly or missing action forwarding"
Assert-Contains $server 'local function createBankFixedEntry\(bank,\s*term,\s*amount\)' "Server missing shared fixed-deposit creation helper"
Assert-Contains $server 'elseif action == "createFixedFromCash"' "Server bank command missing createFixedFromCash"

Write-Output "V11620CheckOK"
