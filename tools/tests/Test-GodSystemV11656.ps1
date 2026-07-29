param(
    [string]$Root = "",
    [string]$ExpectedVersion = "1.16.56"
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Lua = Join-Path $Mod '42\media\lua'

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

$config = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Config.lua')
$companionConfig = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_CompanionConfig.lua')
$companion = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Companion.lua')
$visual = Read-Utf8 (Join-Path $Lua 'client\GodSystem_CompanionVisual.lua')
$protocol = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Protocol.lua')
$server = Read-Utf8 (Join-Path $Lua 'server\GodSystem_Server.lua')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

$versionPattern = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $versionPattern + '"') ("Config version must be " + $ExpectedVersion)
Require-Text $rootInfo ('(?m)^modversion=' + $versionPattern + '\r?$') ("Root mod.info version must be " + $ExpectedVersion)
Require-Text $b42Info ('(?m)^modversion=' + $versionPattern + '\r?$') ("B42 mod.info version must be " + $ExpectedVersion)
Require-Text $workshop ('(?m)^description=v' + $versionPattern + '\r?$') ("Workshop metadata must mention " + $ExpectedVersion)

Require-Text $companion 'require\s+"GodSystem_CompanionVisual"' 'Companion visual module is not required'
Require-Text $visual 'Visual\.CanvasWidth\s*=\s*32' 'Pixel canvas width must be 32'
Require-Text $visual 'Visual\.CanvasHeight\s*=\s*24' 'Pixel canvas height must be 24'
Require-Text $visual 'Visual\.FrameCount\s*=\s*2' 'Pixel companion must expose two animation frames'
Require-Text $visual 'Visual\.ParticleCap\s*=\s*24' 'Particle pool must stay capped at 24'
Require-Text $visual 'Visual\.MaxBodySegments\s*=\s*36' 'Pixel body segment budget must stay capped at about 36 lines'
Require-Text $visual 'if\s+Visual\.CompiledBodySegments\s*>\s*Visual\.MaxBodySegments\s+then\s+error' 'Pixel body must enforce its compiled segment budget at load time'
Require-Text $visual 'Visual\.Directions\s*=\s*\{\s*"N"\s*,\s*"NE"\s*,\s*"E"\s*,\s*"SE"\s*,\s*"S"\s*,\s*"SW"\s*,\s*"W"\s*,\s*"NW"\s*\}' 'All eight robot directions must be declared'
foreach ($direction in @('N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW')) {
    Require-Text $visual ("(?m)^\s*" + $direction + "\s*=\s*\{") "Missing direction overlay: $direction"
}

$rowsBlock = [regex]::Match($visual, '(?s)local HULL_ROWS\s*=\s*\{(?<body>.*?)\r?\n\}').Groups['body'].Value
$rows = @([regex]::Matches($rowsBlock, '"(?<row>[\.A-Z]+)"') | ForEach-Object { $_.Groups['row'].Value })
if ($rows.Count -ne 24) { throw "Pixel hull must contain 24 rows; found $($rows.Count)" }
foreach ($row in $rows) {
    if ($row.Length -ne 32) { throw "Pixel hull row width must be 32; found $($row.Length)" }
}

$hullSegmentCount = 0
foreach ($row in $rows) {
    $hullSegmentCount += [regex]::Matches($row, '([A-Z])\1*').Count
}
$segmentPattern = '\{\s*-?\d+\s*,\s*-?\d+\s*,\s*-?\d+\s*,\s*"[A-Z]"\s*\}'
$coreBlock = [regex]::Match($visual, '(?s)local CORE_SEGMENTS\s*=\s*\{(?<body>.*?)\r?\n\}').Groups['body'].Value
$coreSegmentCount = [regex]::Matches($coreBlock, $segmentPattern).Count
$frameBlock = [regex]::Match($visual, '(?s)local FRAME_OVERLAYS\s*=\s*\{(?<body>.*?)\r?\n\}\r?\n\r?\nlocal DIRECTION_OVERLAYS').Groups['body'].Value
$frameSegmentMaximum = 0
foreach ($frame in [regex]::Matches($frameBlock, '(?s)\[\d+\]\s*=\s*\{(?<body>.*?)\r?\n\s*\},?')) {
    $frameSegmentMaximum = [math]::Max($frameSegmentMaximum,
        [regex]::Matches($frame.Groups['body'].Value, $segmentPattern).Count)
}
$directionBlock = [regex]::Match($visual, '(?s)local DIRECTION_OVERLAYS\s*=\s*\{(?<body>.*?)\r?\n\}\r?\n\r?\nlocal GUARDIAN_OVERLAY').Groups['body'].Value
$directionSegmentMaximum = 0
foreach ($direction in [regex]::Matches($directionBlock, '(?m)^\s*[A-Z]{1,2}\s*=\s*\{(?<body>.*?)\},?\s*$')) {
    $directionSegmentMaximum = [math]::Max($directionSegmentMaximum,
        [regex]::Matches($direction.Groups['body'].Value, $segmentPattern).Count)
}
$declaredSegmentBudget = [int][regex]::Match($visual, 'Visual\.MaxBodySegments\s*=\s*(?<value>\d+)').Groups['value'].Value
$compiledSegmentCount = $hullSegmentCount + $coreSegmentCount + $frameSegmentMaximum + $directionSegmentMaximum
if ($compiledSegmentCount -gt $declaredSegmentBudget) {
    throw "Pixel body compiles to $compiledSegmentCount segments, exceeding budget $declaredSegmentBudget"
}

Require-Text $visual 'local particles\s*=\s*\{\}' 'Fixed particle pool storage is missing'
Require-Text $visual 'for index\s*=\s*1,\s*Visual\.ParticleCap' 'Particle pool must be preallocated'
Require-Text $visual 'nextParticle\s*=\s*nextParticle\s*%\s*Visual\.ParticleCap\s*\+\s*1' 'Particle pool must recycle slots'
Require-Text $visual 'cachedTexture\s*=\s*getTexture\s+and\s+getTexture\("media/textures/GodSystem_WhitePixel\.png"\)' 'Line texture must be cached by the visual module'
Reject-Text $visual 'math\.random\s*\(' 'B42 companion visuals must use ZombRandFloat instead of math.random'
Reject-Text $companion '(?i)Robot.*\.png|getTexture\([^\r\n]*Robot' 'Companion runtime must not depend on a robot PNG'

Require-Text $companionConfig 'Config\.RobotChargeSeconds\s*=\s*0\.20' 'Robot charge time must be 0.20 seconds'
Require-Text $companionConfig 'Config\.RobotRecoverySeconds\s*=\s*0\.15' 'Robot recovery time must be 0.15 seconds'
Require-Text $companion 'runtime\.pendingAttack\s*=\s*\{\s*target\s*=\s*target\s*\}' 'Pending attack state is missing'
Require-Text $companion 'runtime\.chargeEndsMs\s*=\s*now\s*\+\s*Config\.RobotChargeSeconds\s*\*\s*1000' 'Charge end time is not derived from the configured duration'
Require-Text $companion '(?s)if\s+runtime\.pendingAttack\s+then.*?not\s+isAttackTargetValid\(player,\s*data,\s*target\).*?cancelPendingAttack' 'Pending targets must be revalidated before firing'
Require-Text $companion '(?s)local function launchPendingAttack.*?runtime\.projectiles\[#runtime\.projectiles\s*\+\s*1\].*?data\.cooldowns\.attack\s*=' 'Attack cooldown must start only when the projectile is launched'
Require-Text $companion '(?s)local function clearTransientEffects.*?cancelPendingAttack.*?Visual\.reset' 'Transient cleanup must cancel charging and reset particles'
Require-Text $companion '(?s)mode\s*==\s*"ceasefire"\s+then\s+cancelPendingAttack' 'Ceasefire must cancel pending attacks'
Require-Text $companion '(?s)local function resetRobotNear.*?lastCombatTarget\s*=\s*nil.*?Visual\.reset' 'Recall and robot reset must clear the recent combat target and particles'
Require-Text $companion '(?s)if\s+not\s+data\.visible\s+then.*?cancelPendingAttack.*?lastCombatTarget\s*=\s*nil.*?Visual\.reset' 'Hiding the robot must cancel charging, clear its recent target, and reset particles'
Require-Text $companion '(?s)isGamePaused\s+and\s+isGamePaused\(\).*?cancelPendingAttack.*?lastCombatTarget\s*=\s*nil.*?Visual\.reset' 'Pausing must cancel wall-clock charging and clear transient robot feedback'
Require-Text $companion 'Visual\.emit\("trail"|catchup\s+and\s+"catchup"\s+or\s+"trail"' 'Robot movement must emit capped trail particles'
Require-Text $companion 'Visual\.emit\("charge"' 'Charging must emit red core particles'
Require-Text $companion 'Visual\.emit\("fire"' 'Firing must emit attack particles'
Require-Text $companion 'Visual\.emit\("sight"' 'Spirit sight must emit robot particles'
Require-Text $companion 'Visual\.emit\("guardian"' 'Guardian must emit robot particles'

Require-Text $visual 'if \(isClient and isClient\(\)\) or \(isServer and isServer\(\)\) then return end' 'Visual module must stay single-player only'
Reject-Text $protocol '(?i)CompanionVisual|pendingAttack|RobotChargeSeconds' 'Pixel companion must not extend multiplayer protocol'
Reject-Text $server '(?i)CompanionVisual|pendingAttack|RobotChargeSeconds' 'Pixel companion must not add server handlers'

Write-Output 'Test-GodSystemV11656 passed'
