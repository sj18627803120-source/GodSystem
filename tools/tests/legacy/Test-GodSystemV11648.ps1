$ErrorActionPreference = 'Stop'

$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Media = Join-Path $Mod '42\media'
$Lua = Join-Path $Media 'lua'

$ConfigPath = Join-Path $Lua 'shared\GodSystem_Config.lua'
$AdminPath = Join-Path $Lua 'shared\GodSystem_AdminConfig.lua'
$ProtocolPath = Join-Path $Lua 'shared\GodSystem_Protocol.lua'
$CorePath = Join-Path $Lua 'client\GodSystem_Core.lua'
$NetworkPath = Join-Path $Lua 'client\GodSystem_Network.lua'
$UiPath = Join-Path $Lua 'client\GodSystem_UI.lua'
$ContextPath = Join-Path $Lua 'client\GodSystem_RecycleContext.lua'
$ServerPath = Join-Path $Lua 'server\GodSystem_Server.lua'
$SandboxPath = Join-Path $Media 'sandbox-options.txt'
$CnSandboxPath = Join-Path $Lua 'shared\Translate\CN\Sandbox.json'
$ChSandboxPath = Join-Path $Lua 'shared\Translate\CH\Sandbox.json'

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}

$config = Read-Utf8 $ConfigPath
$admin = Read-Utf8 $AdminPath
$protocol = Read-Utf8 $ProtocolPath
$core = Read-Utf8 $CorePath
$network = Read-Utf8 $NetworkPath
$ui = Read-Utf8 $UiPath
$server = Read-Utf8 $ServerPath
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.48"' 'Config version must be 1.16.48'
Require-Text $rootInfo '(?m)^modversion=1\.16\.48$' 'Root mod.info version must be 1.16.48'
Require-Text $b42Info '(?m)^modversion=1\.16\.48$' 'B42 mod.info version must be 1.16.48'
Require-Text $workshop '(?m)^description=v1\.16\.48$' 'Workshop metadata must mention v1.16.48'

$metaKeys = [regex]::Matches($admin, '\{ key = "([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
if ($metaKeys.Count -ne 64) { throw "Expected 64 admin settings, found $($metaKeys.Count)" }
$sandbox = Read-Utf8 $SandboxPath
$sandboxKeys = [regex]::Matches($sandbox, '(?m)^option GodSystem\.([A-Za-z0-9_]+)\s*$') | ForEach-Object { $_.Groups[1].Value }
if ($sandboxKeys.Count -ne 64) { throw "Expected 64 sandbox options, found $($sandboxKeys.Count)" }
if ((Compare-Object ($metaKeys | Sort-Object) ($sandboxKeys | Sort-Object)).Count -ne 0) {
    throw 'Sandbox option keys must exactly match admin setting keys'
}
Require-Text $admin 'function\s+GodSystemAdminConfig\.getSandboxDefaults\s*\(' 'Sandbox default importer missing'
Require-Text $admin 'SandboxVars\.GodSystem' 'Sandbox defaults must read SandboxVars.GodSystem'
Require-Text $core 'data\.adminConfig\.settings\s*==\s*nil' 'SP must only import sandbox settings when no settings exist'
Require-Text $server 'data\.settings\s*==\s*nil' 'MP must only import sandbox settings when no settings exist'

$cnSandbox = Read-Utf8 $CnSandboxPath | ConvertFrom-Json
$chSandbox = Read-Utf8 $ChSandboxPath | ConvertFrom-Json
foreach ($key in $metaKeys) {
    foreach ($json in @($cnSandbox, $chSandbox)) {
        if (-not $json.PSObject.Properties["Sandbox_GodSystem_$key"]) {
            throw "Sandbox translation missing: Sandbox_GodSystem_$key"
        }
        if (-not $json.PSObject.Properties["Sandbox_GodSystem_${key}_tooltip"]) {
            throw "Sandbox tooltip missing: Sandbox_GodSystem_${key}_tooltip"
        }
        if ($json."Sandbox_GodSystem_$key" -eq $key) {
            throw "Sandbox label must be localized: Sandbox_GodSystem_$key"
        }
        if ($json."Sandbox_GodSystem_${key}_tooltip" -eq $key) {
            throw "Sandbox tooltip must be localized: Sandbox_GodSystem_${key}_tooltip"
        }
    }
}

Require-Text $network 'function\s+GodSystemNetwork\.updateBankInvestmentTime\s*\(' 'MP investment client timer missing'
Require-Text $network 'action\s*=\s*"syncInvestmentHours"' 'MP investment timer must use bank syncInvestmentHours'
Require-Text $network 'math\.floor\s*\(\s*nowHour\s*-\s*investmentRuntimeHour' 'MP investment sync must report whole online game hours'
Require-Text $network 'function\s+GodSystemNetwork\.resetInvestmentRuntime\s*\(' 'MP investment session baseline reset helper missing'
Require-Text $network 'Events\.OnConnected[\s\S]*?GodSystemNetwork\.resetInvestmentRuntime' 'MP connect must reset investment session baseline'
Require-Text $network 'Events\.OnDisconnect[\s\S]*?GodSystemNetwork\.resetInvestmentRuntime' 'MP disconnect must reset investment session baseline'
Require-Text $server 'action\s*==\s*"syncInvestmentHours"' 'Server bank syncInvestmentHours action missing'
Require-Text $server 'local\s+function\s+applyBankInvestmentElapsed\s*\(' 'Server investment elapsed helper missing'
if ($server -match 'investmentOnlineSessions') { throw 'Legacy server investmentOnlineSessions timer must be removed' }
if ($server -match 'updateBankInvestments\s*\(\s*player\s*\)') { throw 'Server OnPlayerUpdate must not drive investment timing' }

Require-Text $ui 'Shortcut_RecycleWaistOnly' 'Shortcut waist recycle button missing'
Require-Text $ui 'Shortcut_RecycleWaistAndList' 'Shortcut waist recycle-and-list button missing'
Require-Text $ui 'GodSystem\.recycleWaistSpaceItems\s*\(\s*nil\s*\)' 'Shortcut waist recycle must use fixed recycle action'
Require-Text $ui 'GodSystem\.recycleWaistSpaceItemsAndUnlock\s*\(\s*nil\s*\)' 'Shortcut waist recycle-and-list must use fixed action'
if ($ui -match '\{ id = "recycle", label = GodSystem\.text\("Tab_Recycle"') { throw 'Legacy recycle tab must be hidden' }
Require-Text $ui 'self\.mode\s*==\s*"recycle"[\s\S]*?self\.mode\s*=\s*"shop"' 'Stale recycle mode must fall back to shop'

$context = Read-Utf8 $ContextPath
Require-Text $context 'OnFillInventoryObjectContextMenu\.Add' 'Inventory recycle context hook missing'
Require-Text $context 'Menu_ContextRecycle' 'Context recycle option missing'
Require-Text $context 'Menu_ContextRecycleAndList' 'Context recycle-and-list option missing'
Require-Text $context 'Menu_ContextListOnly' 'Context list-only option missing'
Require-Text $context 'getID' 'Context actions must collect exact item IDs'
Require-Text $context 'ISInventoryTransferUtil\.newInventoryTransferAction' 'External items must use vanilla inventory transfers'
Require-Text $context 'ISWaitWhileGettingUp:new' 'Recycle request must use a callback-capable queue barrier after transfers'
Require-Text $context 'containerContentSignatures' 'Non-empty container confirmation must preserve a content snapshot'
Require-Text $context 'notAvailable\s*=\s*true' 'Unavailable listing actions must be disabled'
Require-Text $context 'toolTip' 'Disabled context actions must explain the reason'
Require-Text $context 'ISModalDialog:new' 'Non-empty containers must require confirmation'

Require-Text $network 'wrap\("recycleSelectedItems"' 'MP selected-item recycle wrapper missing'
Require-Text $network 'itemIds\s*=\s*itemIds' 'MP selected-item recycle must send exact IDs'
Require-Text $network 'containerContentSignatures\s*=\s*containerContentSignatures' 'MP selected-item recycle must send container content snapshots'
Require-Text $server 'args\s+and\s+args\.itemIds' 'Legacy recycle handler must branch for exact item IDs'
Require-Text $server 'mode\s*==\s*"recycleAndList"' 'Server recycle-and-list mode missing'
Require-Text $server 'mode\s*==\s*"listOnly"' 'Server list-only mode missing'
Require-Text $server 'inventoryItemById' 'Server must resolve selected items by exact ID'
Require-Text $server 'GodSystemServerContainerContentSignature' 'Server must revalidate confirmed container contents'
Require-Text $server 'removeWornItem' 'Server must clear worn items before removal'
Require-Text $server 'setPrimaryHandItem\s*\(\s*nil\s*\)' 'Server must clear primary hand before removal'
Require-Text $server 'setSecondaryHandItem\s*\(\s*nil\s*\)' 'Server must clear secondary hand before removal'
Require-Text $server 'function\s+GodSystemServerContainerContainsItem\s*\(' 'Server exact removal must provide a post-removal containment check'
Require-Text $server 'GodSystemServerContainerContainsItem\s*\(\s*container\s*,\s*item\s*\)[\s\S]*?return\s+false' 'Server exact removal must reject items that remain in the container'
Require-Text $server 'finishCode\s*\([^\r\n]*"RecycleSelection' 'Selected-item results must use structured codes'
Require-Text $core 'function\s+GodSystem\.recycleSelectedItems\s*\(' 'SP selected-item recycle implementation missing'
Require-Text $core 'GodSystem\.getContextContainerSignature' 'SP must calculate and revalidate confirmed container contents'
Require-Text $core 'local\s+function\s+gsContainerContainsItem\s*\(' 'SP exact removal must provide a post-removal containment check'
Require-Text $core 'gsContainerContainsItem\s*\(\s*row\.container\s*,\s*item\s*\)' 'SP exact removal must verify the item left its container'
Require-Text $core 'local\s+data\s*=\s*GodSystem\.getData\(\)[\s\S]*?if\s+mode\s*==\s*"listOnly"' 'SP list-only rollback must initialize player data before the transaction branch'

Write-Output 'Test-GodSystemV11648 passed'
