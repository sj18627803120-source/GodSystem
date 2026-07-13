param(
    [string]$Root = "C:\Users\Admin\Zomboid\Workshop\GodSystem"
)

$ErrorActionPreference = "Stop"

function Read-Utf8 {
    param([string]$Path)
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

$server = Join-Path $Root "Contents\mods\GodSystem\42\media\lua\server\GodSystem_Server.lua"
$network = Join-Path $Root "Contents\mods\GodSystem\42\media\lua\client\GodSystem_Network.lua"
$ui = Join-Path $Root "Contents\mods\GodSystem\42\media\lua\client\GodSystem_UI.lua"
$core = Join-Path $Root "Contents\mods\GodSystem\42\media\lua\client\GodSystem_Core.lua"

$serverText = Read-Utf8 $server
$networkText = Read-Utf8 $network
$uiText = Read-Utf8 $ui
$coreText = Read-Utf8 $core

Assert-Contains $serverText "local function finish(player, ok, message, payload)" "Server finish must support structured result payloads."
Assert-Contains $serverText "payload = payload" "Server result command must include payload."
Assert-Contains $serverText "kind = `"shopLottery`"" "Shop lottery server result must identify payload kind."
Assert-Contains $serverText "label = nil" "MP shop lottery should not store internal fullType as the display label."

Assert-Contains $networkText "GodSystemNetwork.pendingShopLotteryResult" "Network layer must store pending shop lottery result."
Assert-Contains $networkText "args.payload.kind == `"shopLottery`"" "Network layer must recognize shop lottery result payloads."
Assert-Contains $networkText "if command == ((Protocol.S2C and Protocol.S2C.State) or `"state`") then" "Network state handler must remain the UI refresh trigger after result payloads."

Assert-Contains $uiText "consumeShopLotteryResult" "UI must consume MP shop lottery result payloads."
Assert-Contains $uiText "showShopLotteryResult" "UI must display MP shop lottery result details."
Assert-Contains $uiText "self:consumeShopLotteryResult()" "UI must consume the pending result after list refresh."

Assert-Contains $coreText "GodSystem.getUnlockedShopLabel" "Core must localize unlocked shop item labels."
Assert-Contains $coreText "label = GodSystem.getUnlockedShopLabel(fullType, item)" "Unlocked shop list must use localized label helper."
Assert-Contains $coreText "return GodSystem.getUnlockedShopLabel(shopItem.fullType, shopItem)" "Shop label must localize unlocked entries."

Write-Output "GodSystem v1.16.27 static checks passed."
