param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [string]$ExpectedVersion = '42.20_2.5'
)

$ErrorActionPreference = 'Stop'

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
    Write-Output "  OK: $Message"
}

function Reject-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw $Message }
    Write-Output "  OK: $Message"
}

Write-Output '=== Test-GodSystemV422024: B42 Java Call Audit And Localization ==='

$mod = Join-Path $Root 'Contents\mods\GodSystem'
$lua = Join-Path $mod '42\media\lua'
$shared = Join-Path $lua 'shared'
$bridge = Read-Utf8 (Join-Path $shared 'GodSystem_B42JavaCalls.lua')
$server = Read-Utf8 (Join-Path $lua 'server\GodSystem_Server.lua')
$core = Read-Utf8 (Join-Path $lua 'client\GodSystem_Core.lua')
$network = Read-Utf8 (Join-Path $lua 'client\GodSystem_Network.lua')
$carry = Read-Utf8 (Join-Path $shared 'GodSystem_CarryCapacity.lua')
$upgrades = Read-Utf8 (Join-Path $shared 'GodSystem_TerminalUpgrades.lua')
$config = Read-Utf8 (Join-Path $shared 'GodSystem_Config.lua')
$rootInfo = Read-Utf8 (Join-Path $mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

foreach ($method in @(
    'getContainingItem', 'getCapacity', 'setCapacity', 'getWeightReduction', 'setWeightReduction',
    'getInventory', 'getItems', 'getID', 'getFullType', 'getCurrentAmmoCount', 'setCurrentAmmoCount',
    'getXP', 'getTotalXpForLevel', 'getBodyDamage', 'setHealth'
)) {
    Require-Text $bridge (($method) + '\s*=\s*function\(target[^\r\n]*target:' + $method + '\(') "Bridge explicitly maps $method"
}

$bridgedFiles = @(
    'shared\GodSystem_Storage.lua',
    'shared\GodSystem_AutoLoader.lua',
    'shared\GodSystem_Attributes.lua',
    'shared\GodSystem_EconomyPolicy.lua',
    'shared\GodSystem_Maintenance.lua',
    'shared\GodSystem_TerminalFood.lua',
    'shared\GodSystem_TerminalRelief.lua',
    'shared\GodSystem_TerminalUpgrades.lua',
    'client\GodSystem_Core.lua',
    'client\GodSystem_ItemEconomyUI.lua',
    'client\GodSystem_Network.lua',
    'server\GodSystem_Server.lua'
)
foreach ($relative in $bridgedFiles) {
    $text = Read-Utf8 (Join-Path $lua $relative)
    Require-Text $text 'require\s+"GodSystem_B42JavaCalls"' "$relative loads the shared B42 bridge"
    Reject-Text $text '\[(?:methodName|method|getter|setter)\]\s*\(' "$relative has no extracted dynamic Java invocation"
}

Require-Text $server 'GodSystemB42JavaCalls\.getContainingItem\(container\)' 'Nested terminal ownership uses the explicit helper'
Require-Text $server 'GodSystemB42JavaCalls\.getCapacity\(item\)' 'Server terminal sync reads capacity explicitly'
Require-Text $network 'GodSystemB42JavaCalls\.setCapacity' 'Client terminal sync writes capacity explicitly'
Require-Text $upgrades 'GodSystemB42JavaCalls\.setWeightReduction' 'Terminal upgrades write reduction explicitly'
Require-Text $bridge 'local available, method = pcall\(function\(\) return target\[methodName\] end\)' 'Bridge probes optional userdata methods before calling'
Require-Text $network 'function GodSystemNetwork\.resetSessionRuntime\(\)[\s\S]*sentHello\s*=\s*false[\s\S]*GodSystemNetwork\.hasServerState\s*=\s*false[\s\S]*GodSystemNetwork\.pendingState\s*=\s*true' 'MP reconnect resets the client session handshake state'
Require-Text $network 'Events\.OnConnected\.Add\(GodSystemNetwork\.resetSessionRuntime\)' 'MP connect installs the session handshake reset'
Require-Text $network 'Events\.OnDisconnect\.Add\(GodSystemNetwork\.resetSessionRuntime\)' 'MP disconnect installs the session handshake reset'
Require-Text $carry 'GodSystemCarryCapacity\.getVanillaCapacity' 'Carry capacity exposes the B42 vanilla capacity measurement'
Require-Text $carry 'GodSystemCarryCapacity\.reconcile' 'Carry capacity exposes a bounded recalibration entry'
Require-Text $core 'GodSystemCarryCapacity\.reconcile' 'SP player updates recalibrate carry capacity'
Require-Text $network 'GodSystemCarryCapacity\.reconcile' 'MP client player updates recalibrate carry capacity after state sync'
Require-Text $server 'GodSystemCarryCapacity\.reconcile' 'MP server player updates recalibrate carry capacity authoritatively'
Reject-Text ($core + $server) 'setBandaged' 'Medical healing does not call the unverified BodyPart setBandaged overload'
Reject-Text ($server + $network + $upgrades) 'pcall\s*\(\s*[A-Za-z_][A-Za-z0-9_]*\.(?:getContainingItem|getCapacity|setCapacity|getWeightReduction|setWeightReduction|getInventory|getItems|isFavorite|hasTag|setName|setCustomName|transmitModData)' 'Audited Java methods are not extracted into pcall'

$capacityBlock = [regex]::Match($config, 'GodSystemConfig\.TerminalCapacityLevels\s*=\s*\{(?<body>[\s\S]*?)\n\}').Groups['body'].Value
Require-Text $capacityBlock 'value\s*=\s*49' 'Terminal capacity still ends at 49'
Reject-Text $capacityBlock 'value\s*=\s*(?:[5-9][0-9]|[1-9][0-9]{2,})' 'Terminal capacity does not restore oversized native values'

$percentFiles = @(
    (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml'),
    (Join-Path $shared 'Translate\CN\IG_UI_CN.txt'),
    (Join-Path $shared 'Translate\CH\IG_UI_CH.txt'),
    (Join-Path $shared 'Translate\CN\Sandbox.json'),
    (Join-Path $shared 'Translate\CH\Sandbox.json')
)
foreach ($path in $percentFiles) {
    $text = Read-Utf8 $path
    if ([regex]::IsMatch($text, '(?<!%)%(?!%)')) { throw "Unescaped percent in $path" }
    Write-Output "  OK: Percent literals are escaped in $path"
}
$fallback = Read-Utf8 (Join-Path $shared 'GodSystem_Localization_Override.lua')
Reject-Text $fallback '%' 'Lua fallback stores percent signs as byte escapes'

$versionPattern = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $versionPattern + '"') "Config version is $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $versionPattern + '\r?$') "Root mod.info version is $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $versionPattern + '\r?$') "B42 mod.info version is $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + $versionPattern + '\r?$') "Workshop headline version is v$ExpectedVersion"
Require-Text $workshop '(?m)^version=1\r?$' 'Workshop metadata version remains 1'
Require-Text $workshop '(?m)^id=3773949382\r?$' 'Workshop ID remains unchanged'
Require-Text $rootInfo '(?m)^id=GodSystem_CN\r?$' 'Mod ID remains unchanged'

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for 42.20_2.5 validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV422024Runtime.lua') $lua
if ($LASTEXITCODE -ne 0) { throw '42.20_2.5 runtime validation failed' }

Write-Output "Test-GodSystemV422024 passed for $ExpectedVersion"
