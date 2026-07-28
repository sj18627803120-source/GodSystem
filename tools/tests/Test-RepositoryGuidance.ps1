param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'

function Read-Utf8([string]$RelativePath) {
    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing guidance file: $RelativePath" }
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

$agents = Read-Utf8 'AGENTS.md'
$github = Read-Utf8 'docs\GITHUB_COLLABORATION_CN.md'
$skill = Read-Utf8 'tools\codex\skills\pz-mod-dev\SKILL.md'
$official = Read-Utf8 'docs\PZ_B42_OFFICIAL_DEVELOPMENT_CN.md'
$community = Read-Utf8 'docs\PZ_COMMUNITY_DEVELOPMENT_RESOURCES_CN.md'
$apiPath = Get-ChildItem -LiteralPath (Join-Path $Root 'docs') -Filter 'PZ_B42_*API*.md' -File | Select-Object -First 1
if (-not $apiPath) { throw 'Missing B42 vanilla API navigation reference' }
$api = [System.IO.File]::ReadAllText($apiPath.FullName, [System.Text.Encoding]::UTF8)
$handoffPath = Get-ChildItem -LiteralPath (Join-Path $Root 'docs\GodSystem_DevHandoff_CN') -Filter '70_v1.16.72_*.md' -File | Select-Object -First 1
if (-not $handoffPath) { throw 'Missing v1.16.72 release handoff' }
$handoff = [System.IO.File]::ReadAllText($handoffPath.FullName, [System.Text.Encoding]::UTF8)

$active = $agents + "`n" + $github + "`n" + $skill
if ($active -match '(?i)superpowers:|REQUIRED SUB-SKILL|Superpowers Coordination') {
    throw 'Active repository guidance must not require Superpowers skills'
}
if ($agents -notmatch 'Do not use Superpowers skills') {
    throw 'AGENTS.md must state the current no-Superpowers workflow'
}
if ($skill -notmatch 'Direct Engineering Workflow') {
    throw 'The bundled pz-mod-dev skill must describe the direct workflow'
}
foreach ($required in @(
    'theindiestone.com/forums/topic/88499-modding-migration-guide-4213',
    'theindiestone.com/forums/topic/95733-build-42190-unstable-released',
    'media/registries.lua',
    'sendAddItemToContainer',
    'sendRemoveItemFromContainer'
)) {
    if ($official -notmatch [regex]::Escape($required)) {
        throw "Official B42 reference is missing: $required"
    }
}

foreach ($required in @(
    'Konijima/PZ-Community-API',
    '41.56-IWBUMS',
    'SpawnerAPIServer.lua',
    'Archive.Project-Zomboid-Modding',
    'Page version',
    'Mod optimization | 42.1.1',
    'SpawnItem',
    'getOrCreateGridSquare'
)) {
    if ($community -notmatch [regex]::Escape($required)) {
        throw "Community development review is missing: $required"
    }
}

foreach ($required in @(
    '[!IMPORTANT]',
    'ItemType            = base:normal',
    'media/sandbox-options.txt',
    'CFeedingTroughGlobalObject.lua',
    'BuildRecipeCode/buildRecipeCode.lua'
)) {
    if ($api -notmatch [regex]::Escape($required)) {
        throw "B42 vanilla API navigation reference is missing: $required"
    }
}

foreach ($required in @(
    'v1.16.72',
    '234b42f454a8dbb2a5d96bbbe302d6fe3a89d002',
    'tools/Test-GodSystem.ps1',
    'PZ_B42_'
)) {
    if ($handoff -notmatch [regex]::Escape($required)) {
        throw "v1.16.72 release handoff is missing: $required"
    }
}

if ($skill -notmatch 'API navigation index') {
    throw 'The bundled pz-mod-dev skill must route API research through the B42.19 navigation reference'
}

Write-Output 'RepositoryGuidanceOK'
