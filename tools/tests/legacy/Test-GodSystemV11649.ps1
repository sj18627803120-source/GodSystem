$ErrorActionPreference = 'Stop'

$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Media = Join-Path $Mod '42\media'
$Lua = Join-Path $Media 'lua'

$ConfigPath = Join-Path $Lua 'shared\GodSystem_Config.lua'
$CompanionConfigPath = Join-Path $Lua 'shared\GodSystem_CompanionConfig.lua'
$AdminPath = Join-Path $Lua 'shared\GodSystem_AdminConfig.lua'
$CorePath = Join-Path $Lua 'client\GodSystem_Core.lua'
$RuntimePath = Join-Path $Lua 'client\GodSystem_Companion.lua'
$CompanionUiPath = Join-Path $Lua 'client\GodSystem_CompanionUI.lua'
$UiPath = Join-Path $Lua 'client\GodSystem_UI.lua'
$ProtocolPath = Join-Path $Lua 'shared\GodSystem_Protocol.lua'
$ServerPath = Join-Path $Lua 'server\GodSystem_Server.lua'
$SandboxPath = Join-Path $Media 'sandbox-options.txt'
$CnSandboxPath = Join-Path $Lua 'shared\Translate\CN\Sandbox.json'
$ChSandboxPath = Join-Path $Lua 'shared\Translate\CH\Sandbox.json'
$LocalizationSource = 'C:\Users\Admin\Desktop\PJ\GodSystem_DevHandoff_CN\tools\godsystem_v11645_localization.yml'

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}

$config = Read-Utf8 $ConfigPath
$companionConfig = Read-Utf8 $CompanionConfigPath
$admin = Read-Utf8 $AdminPath
$core = Read-Utf8 $CorePath
$runtime = Read-Utf8 $RuntimePath
$companionUi = Read-Utf8 $CompanionUiPath
$ui = Read-Utf8 $UiPath
$protocol = Read-Utf8 $ProtocolPath
$server = Read-Utf8 $ServerPath
$sandbox = Read-Utf8 $SandboxPath
$localizationSource = Read-Utf8 $LocalizationSource
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.49"' 'Config version must be 1.16.49'
Require-Text $rootInfo '(?m)^modversion=1\.16\.49$' 'Root mod.info version must be 1.16.49'
Require-Text $b42Info '(?m)^modversion=1\.16\.49$' 'B42 mod.info version must be 1.16.49'
Require-Text $workshop '(?m)^description=v1\.16\.49$' 'Workshop metadata must mention v1.16.49'

$metaKeys = [regex]::Matches($admin, '\{ key = "([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
if ($metaKeys.Count -ne 66) { throw "Expected 66 admin settings, found $($metaKeys.Count)" }
$sandboxKeys = [regex]::Matches($sandbox, '(?m)^option GodSystem\.([A-Za-z0-9_]+)\s*$') | ForEach-Object { $_.Groups[1].Value }
if ($sandboxKeys.Count -ne 66) { throw "Expected 66 sandbox options, found $($sandboxKeys.Count)" }
if ((Compare-Object ($metaKeys | Sort-Object) ($sandboxKeys | Sort-Object)).Count -ne 0) {
    throw 'Sandbox option keys must exactly match admin setting keys'
}
foreach ($key in @('EnableCompanion', 'CompanionPriceMultiplier')) {
    if ($metaKeys -notcontains $key) { throw "Missing companion admin setting: $key" }
}

$cnSandbox = Read-Utf8 $CnSandboxPath | ConvertFrom-Json
$chSandbox = Read-Utf8 $ChSandboxPath | ConvertFrom-Json
foreach ($key in @('EnableCompanion', 'CompanionPriceMultiplier')) {
    foreach ($json in @($cnSandbox, $chSandbox)) {
        if (-not $json.PSObject.Properties["Sandbox_GodSystem_$key"]) { throw "Sandbox translation missing: $key" }
        if (-not $json.PSObject.Properties["Sandbox_GodSystem_${key}_tooltip"]) { throw "Sandbox tooltip missing: $key" }
    }
}

Require-Text $companionConfig 'UnlockCost\s*=\s*100' 'Projection unlock cost missing'
Require-Text $companionConfig 'AttackUnlockCost\s*=\s*200' 'Attack unlock cost missing'
Require-Text $companionConfig 'SightUnlockCost\s*=\s*800' 'Sight unlock cost missing'
Require-Text $companionConfig 'GuardianUnlockCost\s*=\s*1200' 'Guardian unlock cost missing'
Require-Text $companionConfig 'SightDurationSeconds\s*=\s*10' 'Sight duration must be 10 seconds'
Require-Text $companionConfig 'SightTargetCap\s*=\s*50' 'Sight target cap must be 50'
Require-Text $companionConfig 'GuardianScanSeconds\s*=\s*0\.25' 'Guardian scan interval must be 0.25 seconds'
Require-Text $companionConfig 'GuardianTriggerRadius\s*=\s*3' 'Guardian trigger radius must be 3m'
Require-Text $companionConfig 'GuardianTriggerCount\s*=\s*3' 'Guardian trigger count must be 3'
Require-Text $companionConfig 'AttackSearchSeconds\s*=\s*0\.2' 'Attack target search must be throttled'
Require-Text $companionConfig 'ResonanceBaseCost\s*=\s*2500' 'Resonance base cost missing'
Require-Text $companionConfig 'ResonanceCostStep\s*=\s*500' 'Resonance cost step missing'
Require-Text $companionConfig 'ResonanceDamagePerLevel\s*=\s*0\.01' 'Resonance damage step missing'

Require-Text $core 'data\.companion\s*=\s*GodSystemCompanionConfig\.ensureData' 'Companion persistent data initialization missing'
Require-Text $core 'function\s+GodSystem\.purchaseCompanionNode\s*\(' 'Companion purchase wrapper missing'
Require-Text $core 'GodSystem\.spendCurrency\s*\(' 'Companion purchases must reuse mixed bank/cash payment'

Require-Text $runtime 'if\s*\(isClient\s+and\s+isClient\(\)\)\s+or\s+\(isServer\s+and\s+isServer\(\)\)\s+then\s+return\s+end' 'Companion runtime must be SP-only'
Require-Text $runtime 'addZombiesInOutfit' 'Human projection shell creation missing'
Require-Text $runtime 'setCollidable\s*\(\s*false\s*\)' 'Projection shell must be non-collidable'
Require-Text $runtime 'GodSystemProjection' 'Projection shell marker missing'
Require-Text $runtime 'IsoLightSource\.new' 'Projection light source missing'
Require-Text $runtime 'addLamppost' 'Projection light registration missing'
Require-Text $runtime 'removeLamppost' 'Projection light cleanup missing'
Require-Text $runtime 'getMovingObjects\s*\(' 'Nearby square zombie scanning missing'
Require-Text $runtime 'CanSee\s*\(' 'Normal attack visibility check missing'
Require-Text $runtime 'setAttackedBy\s*\(' 'Companion kill attribution missing'
Require-Text $runtime 'setZombieKills\s*\(' 'Companion kill-count fallback missing'
Require-Text $runtime ':Kill\s*\(\s*player\s*\)' 'Companion lethal damage must run the B42 death path'
Require-Text $runtime '"Naked"\s*\.\.' 'Projection shell must use a verified numbered Naked outfit'
Require-Text $runtime 'lastSuppressMs' 'Projection behavior suppression must be throttled'
Require-Text $runtime 'isFree\s*\(\s*false\s*\)' 'Projection shell spawn must reject blocked squares'
Require-Text $runtime 'setKnockedDown\s*\(\s*true\s*\)' 'Guardian knockdown missing'
Require-Text $runtime 'ISCoordConversion\.ToScreen' 'World-to-screen marker conversion missing'
Require-Text $runtime 'renderline' 'Sight marker/projectile rendering missing'
Require-Text $runtime 'SightTargetCap' 'Runtime must enforce sight target cap'
Require-Text $runtime 'GuardianScanSeconds' 'Runtime must throttle guardian scans'
Require-Text $runtime 'getVehicle\s*\(' 'Vehicle suspension guard missing'
Require-Text $runtime 'function\s+GodSystemCompanion\.shutdown\s*\(' 'Runtime cleanup API missing'

Require-Text $companionUi 'GodSystemCompanionShortcutWindow' 'Dedicated companion shortcut window missing'
foreach ($action in @('active', 'defensive', 'ceasefire', 'follow3', 'follow5', 'follow10', 'guard', 'sight', 'guardian', 'recall', 'visible')) {
    Require-Text $companionUi ([regex]::Escape('"' + $action + '"')) "Shortcut action missing: $action"
}
Require-Text $companionUi 'remainingCooldown' 'Shortcut cooldown display missing'
Require-Text $ui '\{ id = "companion"' 'Single-player companion navigation entry missing'
Require-Text $ui 'not\s+gsIsMultiplayer\(\)' 'Companion navigation must be hidden in multiplayer'
Require-Text $ui 'populateCompanion' 'Companion page population missing'
Require-Text $ui 'companionNode:[^\r\n]*payload\.id' 'Companion selection must restore by stable node id'

if ($protocol -match '(?i)companion|projection|spiritSight') { throw 'Companion must not add multiplayer protocol commands' }
if ($server -match '(?i)GodSystemCompanion|useCompanion|spiritSight') { throw 'Companion must not add server handlers' }

foreach ($key in @('Tab_Companion', 'Companion_Title', 'Companion_Unlock', 'Companion_Attack', 'Companion_Sight', 'Companion_Guardian', 'Companion_Resonance', 'Companion_CopyAppearance', 'Companion_ShortcutTitle')) {
    Require-Text $localizationSource ('(?m)^' + [regex]::Escape($key) + ':') "Localization source key missing: $key"
}

Write-Output 'Test-GodSystemV11649 passed'
