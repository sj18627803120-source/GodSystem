param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Media = Join-Path $Root 'Contents\mods\GodSystem\42\media'
$Lua = Join-Path $Media 'lua'

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

$items = Read-Utf8 (Join-Path $Media 'scripts\GodSystem_Items.txt')
$registries = Read-Utf8 (Join-Path $Media 'registries.lua')
$bodyLocations = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_BodyLocations.lua')
$terminal = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_TerminalUpgrades.lua')
$core = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Core.lua')
$network = Read-Utf8 (Join-Path $Lua 'client\GodSystem_Network.lua')
$server = Read-Utf8 (Join-Path $Lua 'server\GodSystem_Server.lua')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')

Require-Text $registries 'ItemBodyLocation\.register\("GodSystem:SystemSpaceTerminal"\)' 'Terminal body-location registry is missing'
Require-Text $bodyLocations 'require\s+["'']NPCs/BodyLocations["'']' 'Human body-location definitions must be loaded'
Require-Text $bodyLocations 'BodyLocations\.getGroup\("Human"\)' 'Terminal slot must join the Human body-location group'
Require-Text $bodyLocations 'getOrCreateLocation\(\s*(?:slot|[^\r\n]*SystemSpaceTerminal)' 'Terminal slot must be created in the Human group'

Require-Text $items 'item\s+SystemSpaceTerminal[\s\S]{0,500}BodyLocation\s*=\s*GodSystem:SystemSpaceTerminal' 'Terminal BodyLocation must use the independent slot'
Require-Text $items 'item\s+SystemSpaceTerminal[\s\S]{0,500}CanBeEquipped\s*=\s*GodSystem:SystemSpaceTerminal' 'Terminal CanBeEquipped must use the independent slot'
Require-Text $items 'item\s+SystemSpaceTerminal[\s\S]{0,500}ClothingItem\s*=\s*AthleticCup' 'Terminal must reuse the vanilla invisible ClothingItem'
Reject-Text $items 'item\s+SystemSpaceTerminal[\s\S]{0,500}base:necklace' 'Terminal must not retain the vanilla necklace slot'
if (Test-Path -LiteralPath (Join-Path $Media 'clothing\clothingItems\SystemSpaceTerminal.xml')) {
    throw 'Obsolete custom terminal ClothingItem must be removed'
}

$markBody = [regex]::Match($core, '(?s)function\s+GodSystem\.markAutoRecyclerContainer\(.*?\)(?<body>.*?)\nend').Groups['body'].Value
Require-Text $markBody 'GodSystemNetwork\.isMultiplayer\s*==\s*true' 'MP terminal marking needs an explicit read-only branch'
Require-Text $markBody 'autoRecyclerCache\s*=\s*\{\s*item\s*=\s*item\s*\}' 'MP read-only branch must still cache the terminal'
Require-Text $markBody 'return\s+true' 'MP read-only branch must stop before local item mutation'

Require-Text $terminal 'terminalChanged' 'Terminal apply report must expose outer-item changes'
Require-Text $terminal 'writeNumberMethod[\s\S]{0,700}math\.abs\(before\s*-\s*value\)' 'Terminal numeric writes must skip unchanged values'
Require-Text $server 'report\.terminalChanged\s*==\s*true' 'Server must sync the outer terminal only when it changed'
Require-Text $server 'migrateLegacyTerminalWear' 'Server must safely clear terminals still worn in the old necklace slot'
Require-Text $server '\[GodSystem\]\[TerminalWear\]' 'Server terminal-wear diagnostics are missing'

Require-Text $network 'ISTimedActionQueue\.getTimedActionQueue' 'Background refresh must inspect the vanilla timed-action queue'
Require-Text $network 'isInventoryInteractionBusy' 'Background refresh needs an inventory-interaction guard'
Require-Text $network 'terminalWear' 'Client terminal-wear diagnostics are missing'
Require-Text $network '\[GodSystem\]\[TerminalWear\]' 'Client terminal-wear diagnostic prefix is missing'

Reject-Text $localization '占用项链位置' 'Live localization source must not claim the terminal occupies the necklace slot'

Write-Output 'Test-GodSystemV11663TerminalWear passed'
