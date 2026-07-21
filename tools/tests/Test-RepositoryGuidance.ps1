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

Write-Output 'RepositoryGuidanceOK'
