param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Lua = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Reject-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw $Message }
}

$server = Read-Utf8 (Join-Path $Lua 'server\GodSystem_Server.lua')
$network = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Network.lua')
$ui = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')

Require-Text $server 'function\s+GodSystemServer\.buildTerminalSyncPayload\s*\(' 'Server terminal payload builder is missing'
foreach ($field in @('kind', 'itemId', 'outerCapacity', 'innerCapacity', 'outerReduction', 'innerReduction', 'reliefLevel', 'reliefOffset')) {
    Require-Text $server ([regex]::Escape($field) + '\s*=') "Terminal payload field is missing: $field"
}
Require-Text $server 'kind\s*=\s*"terminalSync"' 'Terminal payload must use the terminalSync kind'
Require-Text $server 'syncTerminalApplyReport\s*\([^\)]*forceSync' 'Terminal apply synchronization must support a forced page-open sync'
Require-Text $server 'syncItemFields' 'Changed terminal fields must use the native item-field synchronization path'
Require-Text $server 'args\s+and\s+args\.terminalSync\s*==\s*true' 'syncClientData must accept the terminalSync request flag'
Require-Text $server 'sendState\s*\([^\)]*terminalSync' 'The existing state response must carry terminalSync data'
Require-Text $server 'terminalSync\s*=\s*GodSystemServer\.buildTerminalSyncPayload' 'Terminal upgrades and claims must attach authoritative state to result payloads'

Require-Text $network 'function\s+GodSystemNetwork\.applyAuthoritativeTerminalState\s*\(' 'Client authoritative terminal apply function is missing'
Require-Text $network 'function\s+GodSystemNetwork\.findTerminalByItemId\s*\(' 'Client exact-ID terminal lookup is missing'
Require-Text $network 'tostring\([^\r\n]*getID\(\)\)\s*==\s*itemId' 'Client terminal lookup must compare the real item ID'
Require-Text $network 'getPrimaryHandItem|getSecondaryHandItem' 'Client terminal lookup must include hand items'
Require-Text $network 'getWornItems' 'Client terminal lookup must include worn items'
Require-Text $network 'pendingTerminalSync' 'Client must defer a terminal payload while inventory actions are active'
Require-Text $network 'TERMINAL_SYNC_EXPIRE_MS' 'Deferred terminal payloads need a short expiry'
Require-Text $network 'setCapacity' 'Client must apply server-provided capacity values to the stale instance'
Require-Text $network 'setWeightReduction' 'Client must apply server-provided reduction values to the stale instance'
Require-Text $network 'refreshBackpacks' 'Client must refresh visible inventory containers after applying terminal state'
Require-Text $network 'args\.payload\.terminalSync' 'Successful operation results must use the common terminal apply path'
Require-Text $network 'args\.terminalSync' 'State responses must use the common terminal apply path'
Require-Text $network 'function\s+GodSystemNetwork\.requestTerminalState\s*\(' 'Terminal page sync request helper is missing'
Require-Text $network 'terminalSync\s*=\s*true' 'Terminal page sync must reuse syncClientData with the terminalSync flag'

$modeButtonBody = [regex]::Match($ui, '(?s)function\s+GodSystemWindow:onModeButton\(.*?\)(?<body>.*?)\nend').Groups['body'].Value
$openModeBody = [regex]::Match($ui, '(?s)function\s+GodSystemUI\.openMode\(.*?\)(?<body>.*?)\nend').Groups['body'].Value
$populateBody = [regex]::Match($ui, '(?s)function\s+GodSystemWindow:populateList\(.*?\)(?<body>.*?)\nend').Groups['body'].Value
Require-Text $modeButtonBody 'requestTerminalState' 'Clicking into the terminal page must request one authoritative sync'
Require-Text $openModeBody 'requestTerminalState' 'Programmatically opening the terminal page must request one authoritative sync'
Reject-Text $populateBody 'requestTerminalState' 'List redraws must not create terminal synchronization requests'

Write-Output 'Test-GodSystemV11663TerminalSync passed'
