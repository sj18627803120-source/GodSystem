param(
    [string]$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
)

$ErrorActionPreference = 'Stop'

function Read-Utf8 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing file: $Path"
    }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Message
    )
    if ($Text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
        throw $Message
    }
}

$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$config = Read-Utf8 (Join-Path $luaRoot 'shared\GodSystem_Config.lua')
$protocol = Read-Utf8 (Join-Path $luaRoot 'shared\GodSystem_Protocol.lua')
$core = Read-Utf8 (Join-Path $luaRoot 'client\GodSystem_Core.lua')
$ui = Read-Utf8 (Join-Path $luaRoot 'client\GodSystem_UI.lua')
$network = Read-Utf8 (Join-Path $luaRoot 'client\GodSystem_Network.lua')
$server = Read-Utf8 (Join-Path $luaRoot 'server\GodSystem_Server.lua')
$loc = Read-Utf8 (Join-Path $luaRoot 'shared\GodSystem_Localization_Override.lua')
$cn = Read-Utf8 (Join-Path $luaRoot 'shared\Translate\CN\IG_UI_CN.txt')
$rootModInfo = Read-Utf8 (Join-Path $Root 'Contents\mods\GodSystem\mod.info')
$b42ModInfo = Read-Utf8 (Join-Path $Root 'Contents\mods\GodSystem\42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')
$readmeFile = Get-ChildItem -LiteralPath $Root -Filter 'README_*.md' | Select-Object -First 1
if (-not $readmeFile) {
    throw "Missing upload README under $Root"
}
$readme = Read-Utf8 $readmeFile.FullName

Assert-Contains $config 'GodSystemConfig.Version = "1.16.29"' 'Config version must be 1.16.29.'
Assert-Contains $rootModInfo 'modversion=1.16.29' 'Root mod.info must be 1.16.29.'
Assert-Contains $b42ModInfo 'modversion=1.16.29' 'B42 mod.info must be 1.16.29.'
Assert-Contains $workshop 'description=v1.16.29' 'Workshop notes must include v1.16.29.'
Assert-Contains $readme 'v1.16.29' 'Upload README must include v1.16.29.'

Assert-Contains $config 'GodSystemConfig.AutoRecyclerFullTypes' 'Config must define front/back waist bag aliases.'
Assert-Contains $config '["Base.Bag_FannyPackBack"] = true' 'Back waist bag must be accepted as a system waist alias.'

Assert-Contains $protocol 'RecycleWaistAndUnlock = "recycleWaistAndUnlock"' 'Protocol must expose MP waist sell-and-list command.'
Assert-Contains $network 'recycleWaistSpaceItemsAndUnlock' 'Network bridge must send waist sell-and-list command.'

Assert-Contains $core 'function GodSystem.isAutoRecyclerFullType' 'Client core must centralize waist bag fullType alias checks.'
Assert-Contains $core 'function GodSystem.recycleWaistSpaceItemsAndUnlock' 'Client core must implement SP waist sell-and-list.'
Assert-Contains $core 'GodSystem.unlockAutoShopItem' 'Waist sell-and-list must unlock shop items after sale.'

Assert-Contains $server 'local function isAutoRecyclerFullType' 'Server must centralize waist bag fullType alias checks.'
Assert-Contains $server 'local function isAutoRecyclerNamedItem' 'Server must recognize converted waist bags by system name if item modData is lost.'
Assert-Contains $server 'function Commands.recycleWaistAndUnlock' 'Server must implement MP waist sell-and-list command.'
Assert-Contains $server 'unlockAutoShopItem(data' 'Server waist sell-and-list must unlock shop items.'

Assert-Contains $ui 'ShopPageSize = 20' 'Shop UI must define 20 items per page.'
Assert-Contains $ui 'changeShopPage' 'Shop UI must support page navigation.'
Assert-Contains $ui 'self.shopPage = 1' 'Shop UI must reset to the first page when category/search filters change.'
Assert-Contains $ui 'self.confirmShopLottery' 'Shop category menu must preserve access to category lottery after pagination takes fourth/fifth buttons.'
Assert-Contains $ui 'captureScrollState' 'UI must capture scroll state before list rebuild/action refresh.'
Assert-Contains $ui 'restoreScrollState' 'UI must restore scroll state after list rebuild/action refresh.'
Assert-Contains $ui 'Btn_WaistSellAndListSelected' 'Waist UI must expose sell-and-list selected action.'
Assert-Contains $ui 'recycleWaistSpaceItemsAndUnlock' 'Waist UI action must call sell-and-list implementation.'

Assert-Contains $loc 'Btn_WaistSellAndListSelected' 'Fallback localization must include waist sell-and-list button.'
Assert-Contains $loc 'HistoryMP_RecycleWaistAndUnlock' 'Fallback localization must include MP waist sell-and-list history text.'
Assert-Contains $cn 'IGUI_GodSystem_Btn_WaistSellAndListSelected' 'CN translate file must include waist sell-and-list button.'

Write-Output 'GodSystem v1.16.29 static checks passed.'
