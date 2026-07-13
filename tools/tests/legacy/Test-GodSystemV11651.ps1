$ErrorActionPreference = 'Stop'

$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Media = Join-Path $Mod '42\media'
$Lua = Join-Path $Media 'lua'
$TextureRoot = Join-Path $Media 'textures'

$ConfigPath = Join-Path $Lua 'shared\GodSystem_Config.lua'
$CompanionConfigPath = Join-Path $Lua 'shared\GodSystem_CompanionConfig.lua'
$RuntimePath = Join-Path $Lua 'client\GodSystem_Companion.lua'
$CompanionUiPath = Join-Path $Lua 'client\GodSystem_CompanionUI.lua'
$UiPath = Join-Path $Lua 'client\GodSystem_UI.lua'
$ProtocolPath = Join-Path $Lua 'shared\GodSystem_Protocol.lua'
$ServerPath = Join-Path $Lua 'server\GodSystem_Server.lua'
$LocalizationSource = 'C:\Users\Admin\Desktop\PJ\GodSystem_DevHandoff_CN\tools\godsystem_v11645_localization.yml'

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Reject-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw $Message }
}

$config = Read-Utf8 $ConfigPath
$companionConfig = Read-Utf8 $CompanionConfigPath
$runtime = Read-Utf8 $RuntimePath
$companionUi = Read-Utf8 $CompanionUiPath
$ui = Read-Utf8 $UiPath
$protocol = Read-Utf8 $ProtocolPath
$server = Read-Utf8 $ServerPath
$localizationSource = Read-Utf8 $LocalizationSource
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

Reject-Text $runtime 'math\.random\s*\(' 'B42.19 Kahlua runtime does not provide math.random'
Require-Text $runtime 'ZombRandFloat\s*\(' 'Robot movement randomness must use the verified B42.19 float RNG'

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.51"' 'Config version must be 1.16.51'
Require-Text $rootInfo '(?m)^modversion=1\.16\.51$' 'Root mod.info version must be 1.16.51'
Require-Text $b42Info '(?m)^modversion=1\.16\.51$' 'B42 mod.info version must be 1.16.51'
Require-Text $workshop '(?m)^description=v1\.16\.51$' 'Workshop metadata must mention v1.16.51'

Require-Text $companionConfig 'GuardianTriggerRadius\s*=\s*3' 'Guardian trigger radius must remain 3m'
Require-Text $companionConfig 'GuardianTriggerCount\s*=\s*1' 'Guardian must trigger from one nearby zombie'
Require-Text $companionConfig 'ProjectileTravelSeconds\s*=\s*0\.35' 'Projectile travel time must be 0.35 seconds'
Require-Text $companionConfig 'RobotFrameSeconds\s*=\s*0\.18' 'Robot animation frame time must be 0.18 seconds'
Require-Text $companionConfig 'RobotDirections\s*=\s*\{[^}]*"N"[^}]*"NE"[^}]*"E"[^}]*"SE"[^}]*"S"[^}]*"SW"[^}]*"W"[^}]*"NW"' 'Eight robot directions are incomplete'
Require-Text $companionConfig 'values\s*=\s*\{\s*1\.00,\s*1\.15,\s*1\.30,\s*1\.45,\s*1\.60,\s*1\.80\s*\}' 'Attack damage levels must match the v1.16.50 table'
foreach ($constant in @('RobotOrbitRetargetMinSeconds', 'RobotOrbitRetargetMaxSeconds', 'RobotGuardDriftRadius', 'RobotRecallDistance', 'RobotCatchupMargin')) {
    Require-Text $companionConfig ([regex]::Escape($constant)) "Missing robot movement constant: $constant"
}

Require-Text $runtime 'if\s*\(isClient\s+and\s+isClient\(\)\)\s+or\s+\(isServer\s+and\s+isServer\(\)\)\s+then\s+return\s+end' 'Companion runtime must remain SP-only'
Require-Text $runtime 'GodSystemProjection' 'Legacy projection marker cleanup must remain'
Require-Text $runtime 'cleanupOrphans' 'Legacy projection cleanup function must remain'
Require-Text $runtime 'ISCoordConversion\.ToScreen' 'Robot rendering must use world-to-screen conversion'
Require-Text $runtime 'getRenderer\s*\(' 'Robot rendering must use the game renderer'
Require-Text $runtime ':render\s*\(' 'Robot texture rendering call missing'
Require-Text $runtime 'CompanionRobot_' 'Robot texture paths missing'
Require-Text $runtime 'renderline' 'Projectile and sight line rendering missing'
Require-Text $runtime 'RED_BEAM' 'Red beam color constants missing'
Require-Text $runtime 'CYAN' 'Cyan sight marker constants missing'
Require-Text $runtime 'IsoLightSource\.new' 'Robot light source missing'
Require-Text $runtime 'setAttackedBy\s*\(' 'Companion kill attribution missing'
Require-Text $runtime ':Kill\s*\(\s*player\s*\)' 'Companion lethal damage must use the B42 death path'
Require-Text $runtime 'setZombieKills\s*\(' 'Companion kill-count fallback missing'
Require-Text $runtime 'GuardianTriggerCount' 'Guardian trigger threshold must be read from config'
Require-Text $runtime 'RobotFrameSeconds' 'Runtime must animate two robot frames'
Require-Text $runtime 'RobotOrbitRetarget' 'Runtime must retarget orbit points on a bounded timer'
Require-Text $runtime 'getVehicle\s*\(' 'Vehicle suspension guard missing'

foreach ($forbidden in @(
    'spawnHumanProjection', 'captureAppearance', 'toggleVisualMode', 'addZombiesInOutfit',
    'ItemVisual', 'applyAppearance', 'suppressShell', 'runtime\.shell', 'visualMode', 'appearance'
)) {
    Reject-Text $runtime $forbidden "Human projection runtime residue remains: $forbidden"
}
Reject-Text $companionUi 'captureAppearance|toggleVisualMode|SwitchHuman|SwitchOrb|CopyAppearance' 'Companion shortcut UI still exposes human/appearance actions'
Reject-Text $ui 'captureAppearance|toggleVisualMode|Companion_SwitchHuman|Companion_SwitchOrb|Companion_CopyAppearance' 'Main UI still exposes human/appearance actions'
Require-Text $ui 'Companion_ActionShow|Companion_ActionHide' 'Main UI must provide show/hide action'
Require-Text $ui 'GodSystemCompanionUI\.toggleShortcut' 'Main UI shortcut action missing'
Require-Text $ui 'GodSystemCompanion\.recall' 'Main UI recall action missing'

foreach ($key in @('Companion_Title', 'Companion_ProjectionDetail', 'Companion_AttackDetail', 'Companion_GuardianDetail', 'Hint_Companion', 'Companion_ShortcutTitle')) {
    Require-Text $localizationSource ('(?m)^' + [regex]::Escape($key) + ':') "Localization source key missing: $key"
}
Reject-Text $localizationSource '(?m)^Companion_(VisualHuman|VisualOrb|SwitchHuman|SwitchOrb|CopyAppearance):' 'Obsolete human/orb localization keys remain'

if ($protocol -match '(?i)companion|projection|spiritSight') { throw 'Companion must not add multiplayer protocol commands' }
if ($server -match '(?i)GodSystemCompanion|useCompanion|spiritSight') { throw 'Companion must not add server handlers' }

$directions = @('N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW')
$expectedNames = foreach ($direction in $directions) {
    foreach ($frame in 0, 1) { "CompanionRobot_${direction}_${frame}.png" }
}
$actualFiles = @(Get-ChildItem -LiteralPath $TextureRoot -Filter 'CompanionRobot_*.png' -File)
if ($actualFiles.Count -ne 16) { throw "Expected exactly 16 robot textures, found $($actualFiles.Count)" }
if ((Compare-Object ($expectedNames | Sort-Object) ($actualFiles.Name | Sort-Object)).Count -ne 0) {
    throw 'Robot texture names do not match the eight-direction, two-frame contract'
}

Add-Type -AssemblyName System.Drawing
foreach ($name in $expectedNames) {
    $path = Join-Path $TextureRoot $name
    $bitmap = [System.Drawing.Bitmap]::new($path)
    try {
        if ($bitmap.Width -ne 64 -or $bitmap.Height -ne 64) { throw "$name must be 64x64" }
        if (($bitmap.PixelFormat -band [System.Drawing.Imaging.PixelFormat]::Alpha) -eq 0) { throw "$name must have an alpha channel" }
        $visible = 0
        $semiTransparent = 0
        $colors = [System.Collections.Generic.HashSet[string]]::new()
        for ($y = 0; $y -lt 64; $y++) {
            for ($x = 0; $x -lt 64; $x++) {
                $pixel = $bitmap.GetPixel($x, $y)
                if ($pixel.A -gt 0) {
                    $visible++
                    if ($pixel.A -ne 255) { $semiTransparent++ }
                    [void]$colors.Add("$($pixel.R),$($pixel.G),$($pixel.B),$($pixel.A)")
                }
            }
        }
        if ($visible -lt 100) { throw "$name is blank or too sparse" }
        if ($semiTransparent -ne 0) { throw "$name contains antialiased semi-transparent edge pixels" }
        if ($colors.Count -lt 8 -or $colors.Count -gt 12) { throw "$name must use an 8-12 color visible palette, found $($colors.Count)" }
    }
    finally {
        $bitmap.Dispose()
    }
}

Write-Output 'Test-GodSystemV11651 passed'
