param(
    [string]$Root = "C:\Users\Admin\Zomboid\Workshop\GodSystem"
)

$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Assert-Contains([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

$modRoot = Join-Path $Root "Contents\mods\GodSystem"
$luaRoot = Join-Path $modRoot "42\media\lua"
$config = Read-Utf8 (Join-Path $luaRoot "shared\GodSystem_Config.lua")
$protocol = Read-Utf8 (Join-Path $luaRoot "shared\GodSystem_Protocol.lua")
$core = Read-Utf8 (Join-Path $luaRoot "client\GodSystem_Core.lua")
$network = Read-Utf8 (Join-Path $luaRoot "client\GodSystem_Network.lua")
$ui = Read-Utf8 (Join-Path $luaRoot "client\GodSystem_UI.lua")
$server = Read-Utf8 (Join-Path $luaRoot "server\GodSystem_Server.lua")
$admin = Read-Utf8 (Join-Path $luaRoot "shared\GodSystem_AdminConfig.lua")
$translateCn = Read-Utf8 (Join-Path $luaRoot "shared\Translate\CN\IG_UI_CN.txt")
$translateCh = Read-Utf8 (Join-Path $luaRoot "shared\Translate\CH\IG_UI_CH.txt")
$rootInfo = Read-Utf8 (Join-Path $modRoot "mod.info")
$b42Info = Read-Utf8 (Join-Path $modRoot "42\mod.info")

Assert-Contains $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.33"' "Config version is not 1.16.33"
Assert-Contains $rootInfo 'modversion=1\.16\.33' "Root mod.info version is not 1.16.33"
Assert-Contains $b42Info 'modversion=1\.16\.33' "B42 mod.info version is not 1.16.33"
Assert-Contains $config 'LotteryAllPrice' "Missing LotteryAllPrice"
Assert-Contains $config 'LotteryCategoryPrices' "Missing LotteryCategoryPrices"
Assert-Contains $config 'LotteryCustomMaxCount' "Missing LotteryCustomMaxCount"
Assert-Contains $protocol 'LotteryDraw\s*=\s*"lotteryDraw"' "Missing lotteryDraw protocol"
Assert-Contains $core 'function GodSystem\.getLotteryCandidates' "Missing client lottery candidates"
Assert-Contains $core 'function GodSystem\.performLotteryDraw' "Missing client lottery draw"
Assert-Contains $network 'pendingLotteryResult' "Missing network pending lottery result"
Assert-Contains $network 'wrap\("performLotteryDraw"' "Missing MP lottery draw wrapper"
Assert-Contains $server 'function Commands\.lotteryDraw' "Missing server lottery draw command"
Assert-Contains $ui 'id\s*=\s*"lottery"' "Missing lottery left nav tab"
Assert-Contains $ui 'populateLottery' "Missing lottery UI page"
Assert-Contains $ui 'showLotteryResult' "Missing lottery result popup"
Assert-Contains $ui 'self\.getAbsoluteX\s+and\s+self:getAbsoluteX\(\)' "Navigation wheel absolute X guard is missing"
Assert-Contains $ui 'suppressSearchChange\s*=\s*true' "Lottery custom count text update is not guarded"
Assert-Contains $admin 'LotteryAllPrice' "Missing admin lottery all price setting"
Assert-Contains $translateCn 'IGUI_GodSystem_Tab_Lottery' "Missing CN lottery tab translation"
Assert-Contains $translateCn 'IGUI_GodSystem_AdminSetting_LotteryAllPrice' "Missing CN lottery admin translation"
Assert-Contains $translateCn 'IGUI_GodSystem_HistoryMP_LotteryDraw' "Missing CN MP lottery history translation"
Assert-Contains $translateCh 'IGUI_GodSystem_Tab_Lottery' "Missing CH lottery tab translation"
Assert-Contains $translateCh 'IGUI_GodSystem_AdminSetting_LotteryAllPrice' "Missing CH lottery admin translation"
Assert-Contains $translateCh 'IGUI_GodSystem_HistoryMP_LotteryDraw' "Missing CH MP lottery history translation"

if ($ui -match 'Btn_ShopLottery') {
    throw "Old shop lottery button key is still used in UI"
}

Write-Output "GodSystem v1.16.33 lottery static checks passed."
