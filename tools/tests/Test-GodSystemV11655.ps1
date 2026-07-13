param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Media = Join-Path $Mod '42\media'
$Lua = Join-Path $Media 'lua'

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
$prices = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Prices.lua')
$companionConfig = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_CompanionConfig.lua')
$maintenance = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Maintenance.lua')
$ui = Read-Utf8 (Join-Path $Lua 'client\GodSystem_UI.lua')
$companion = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Companion.lua')
$maintenanceClient = Read-Utf8 (Join-Path $Lua 'client\GodSystem_MaintenanceContext.lua')
$server = Read-Utf8 (Join-Path $Lua 'server\GodSystem_Server.lua')
$spVehicleServer = Read-Utf8 (Join-Path $Lua 'server\GodSystem_SPVehicleRepair.lua')
$items = Read-Utf8 (Join-Path $Media 'scripts\GodSystem_Items.txt')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')

Require-Text $config 'GodSystemConfig\.Version\s*=\s*"1\.16\.55"' 'Config version must be 1.16.55'
Require-Text $rootInfo '(?m)^modversion=1\.16\.55\r?$' 'Root mod.info version must be 1.16.55'
Require-Text $b42Info '(?m)^modversion=1\.16\.55\r?$' 'B42 mod.info version must be 1.16.55'
Require-Text $workshop '(?m)^description=v1\.16\.55\r?$' 'Workshop metadata must mention v1.16.55'

Require-Text $items 'BodyLocation\s*=\s*base:necklace\s*,' 'System terminal must use the vanilla necklace body location'
Require-Text $items 'CanBeEquipped\s*=\s*base:necklace\s*,' 'System terminal must equip in the vanilla necklace body location'
Reject-Text $items 'GodSystem:GodSystemTerminal' 'Custom terminal body location remains in the item script'
if (Test-Path -LiteralPath (Join-Path $Media 'registries.lua')) { throw 'Obsolete custom body-location registry must be removed' }

Require-Text $ui 'function\s+GodSystemWindow:getNavPageLayout\b' 'Adaptive navigation page helper missing'
Require-Text $ui 'math\.floor\(\(viewportH\s*\+\s*gap\)\s*/\s*math\.max\(1,\s*itemH\s*\+\s*gap\)\)' 'Navigation capacity must be derived from available height'
Require-Text $ui 'math\.ceil\(count\s*/\s*pageCount\)' 'Navigation pages must balance item counts'
Require-Text $ui 'navBottomInset' 'Navigation bottom inset is missing'
Require-Text $ui 'pageCount\s*<=\s*1' 'Single-page navigation must reclaim pager space'
Reject-Text $ui 'availableGap|distributedGap' 'Navigation must not distribute leftover height into large gaps'

Require-Text $config '(?s)GodSystemConfig\.FloatingButton\s*=\s*\{[^}]*width\s*=\s*48[^}]*height\s*=\s*48' 'Floating entry must be 48x48'
Require-Text $ui 'GodSystem_OpenIcon\.png' 'Floating entry icon texture is not referenced'
$floatingRender = [regex]::Match($ui, '(?s)function\s+GodSystemFloatingButton:prerender\(\)(?<body>.*?)\nend').Groups['body'].Value
Reject-Text $floatingRender 'getCurrencyTotal|gsFormatCompactNumber' 'Floating entry must not render a currency number'

$iconPath = Join-Path $Media 'textures\GodSystem_OpenIcon.png'
if (-not (Test-Path -LiteralPath $iconPath)) { throw "Missing floating entry icon: $iconPath" }
Add-Type -AssemblyName System.Drawing
$icon = [System.Drawing.Bitmap]::FromFile($iconPath)
try {
    if ($icon.Width -ne 64 -or $icon.Height -ne 64) { throw "Floating icon must be 64x64, found $($icon.Width)x$($icon.Height)" }
    if (($icon.PixelFormat -band [System.Drawing.Imaging.PixelFormat]::Alpha) -eq 0) { throw 'Floating icon must have an alpha channel' }
    $transparent = $false
    for ($x = 0; $x -lt $icon.Width -and -not $transparent; $x += 4) {
        for ($y = 0; $y -lt $icon.Height; $y += 4) {
            if ($icon.GetPixel($x, $y).A -lt 255) { $transparent = $true; break }
        }
    }
    if (-not $transparent) { throw 'Floating icon must contain transparent pixels' }
}
finally {
    $icon.Dispose()
}

Require-Text $companionConfig 'Config\.RobotNormalSpeed\s*=\s*1\.2' 'Robot cruise speed must be 1.2'
Require-Text $companionConfig 'Config\.RobotCatchupSpeed\s*=\s*4\.5' 'Robot catch-up speed must be 4.5'
Require-Text $companionConfig 'Config\.RobotIdleMinSeconds\s*=\s*2' 'Robot minimum idle time must be 2 seconds'
Require-Text $companionConfig 'Config\.RobotIdleMaxSeconds\s*=\s*5' 'Robot maximum idle time must be 5 seconds'
Require-Text $companionConfig 'Config\.RobotCombatGraceSeconds\s*=\s*3' 'Robot combat grace must be 3 seconds'
Require-Text $companionConfig '(?s)sightRange\s*=\s*\{.*?values\s*=\s*\{\s*20,\s*30,\s*40,\s*50\s*\}' 'Spirit-sight ranges must be 20/30/40/50'
Require-Text $companionConfig '(?s)guardianCooldown\s*=\s*\{.*?values\s*=\s*\{\s*90,\s*60,\s*40,\s*25\s*\}' 'Guardian cooldowns must be 90/60/40/25'
Require-Text $companion 'validRobotPoint\(player,\s*x,\s*y,\s*z,\s*requireVisible\)' 'Robot point validation must make visibility optional'
Require-Text $companion 'chooseRobotOrbitTargetPass\(player,\s*data,\s*now,\s*true\)' 'Robot must prefer visible orbit targets'
Require-Text $companion 'chooseRobotOrbitTargetPass\(player,\s*data,\s*now,\s*false\)' 'Robot must fall back to valid unseen orbit targets'
$orbitPass = [regex]::Match($companion, '(?s)function\s+chooseRobotOrbitTargetPass\(.*?\)(?<body>.*?)\nend').Groups['body'].Value
Reject-Text $orbitPass 'validRobotPoint\(player,\s*baseX' 'Visible orbit pass must not fall back to the player before the unseen pass runs'
Require-Text $companion '(?s)chooseRobotOrbitTargetPass\(player,\s*data,\s*now,\s*false\).*?validRobotPoint\(player,\s*baseX,\s*baseY,\s*baseZ,\s*false\)' 'Player-position fallback must run only after both orbit passes fail'
Require-Text $companion 'runtime\.idleUntilMs' 'Robot idle state is missing'
Require-Text $companion 'runtime\.combatUntilMs' 'Robot combat grace state is missing'
Require-Text $companion 'robotPointVisible\(player,\s*runtime\.robotX' 'Robot rendering must detect unseen positions'

Require-Text $ui 'pendingRestoreSelectedId' 'One-shot stable selection state is missing'
Require-Text $ui '(?s)if\s+self\.mode\s*==\s*"companion".*?prepareActionSelection\(payload\).*?purchaseCompanionNode' 'Companion purchase must preserve its selected node'
Require-Text $ui '(?s)function\s+GodSystemWindow:showAttributeAmountDialog.*?prepareActionSelection\(payload\)' 'Attribute amount purchase must preserve selection'
Require-Text $ui '(?s)function\s+GodSystemWindow:showAttributeNextLevelConfirm.*?prepareActionSelection\(payload\)' 'Attribute next-level purchase must preserve selection'
Require-Text $ui '(?s)function\s+GodSystemBankAmountDialog:onCancel\(preserveActionSelection\).*?payload\.kind\s*==\s*"attribute".*?clearPendingActionSelection' 'Cancelling the attribute amount dialog must clear its pending selection'
Require-Text $ui '(?s)function\s+GodSystemWindow:onAttributeNextLevelConfirm.*?button\.internal\s*~=\s*"YES".*?clearPendingActionSelection' 'Cancelling the next-level confirmation must clear its pending selection'
Require-Text $ui '(?s)purchaseCompanionNode\(payload\.id\).*?clearPendingActionSelection' 'A rejected companion purchase must clear its pending selection'

Require-Text $prices '\["GodSystem\.SystemVehicleRepairModule"\]\s*=\s*5000' 'Vehicle repair module explicit price must be 5000'
Require-Text $maintenance 'function\s+GodSystemMaintenance\.repairVehicle\b' 'Shared authoritative vehicle-repair helper missing'
Reject-Text $maintenanceClient 'vehicle:repair\(\)' 'SP client must not directly repair vehicles'
Require-Text $maintenanceClient 'pcall\(triggerEvent,\s*"OnClientCommand"' 'SP maintenance command dispatch must be protected'
Require-Text $spVehicleServer 'if\s+\(isClient\s+and\s+isClient\(\)\)\s+or\s+\(isServer\s+and\s+isServer\(\)\)\s+then\s+return\s+end' 'SP vehicle server bridge guard is missing'
Require-Text $spVehicleServer 'command\s*~=\s*.*UseMaintenanceItem' 'SP vehicle bridge must reuse useMaintenanceItem'
Require-Text $spVehicleServer 'GodSystemMaintenance\.repairVehicle' 'SP vehicle bridge must use the shared repair helper'
Require-Text $spVehicleServer 'sendServerCommand' 'SP vehicle bridge must return a structured result'
Require-Text $spVehicleServer 'pcall\(triggerEvent,\s*"OnServerCommand"' 'SP vehicle bridge must fall back to the local result event'
Require-Text $server 'GodSystemMaintenance\.repairVehicle' 'MP vehicle repair must use the shared repair helper'

Write-Output 'Test-GodSystemV11655 passed'
