param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$adapterPath = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua\client\GodSystem\Platform\Companion\PZVisuals.lua'
$visualPath = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua\client\GodSystem_CompanionVisual.lua'
$texturePath = Join-Path $Root 'Contents\mods\GodSystem\42\media\textures\GodSystem_WhitePixel.png'

foreach ($path in @($adapterPath, $visualPath, $texturePath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Companion PZ visual dependency is missing: $path" }
}

$adapter = [IO.File]::ReadAllText($adapterPath, [Text.Encoding]::UTF8)
if ($adapter -notmatch 'require\s+"GodSystem_CompanionVisual"') {
    throw 'PZ visual adapter does not bind the pure companion visual renderer'
}
if ($adapter -match 'require\s+"GodSystem_Companion"') {
    throw 'PZ visual adapter requires the retired companion business entry'
}
if ($adapter -match '\bEvents\b|OnPreUIDraw|OnRenderTick|OnPostUIDraw') {
    throw 'PZ visual adapter registers rendering events directly'
}
if ($adapter -match '\bpcall\b|\bxpcall\b') {
    throw 'PZ visual adapter swallows renderer failures'
}
if ($adapter -match 'renderRect|renderPoly|(?:renderer|targetRenderer)\s*:\s*render\s*\(') {
    throw 'PZ visual adapter contains a backup drawing algorithm'
}
foreach ($contract in @(
    'Descriptor\.id\s*=\s*"companion\.visuals"',
    'instance\.public',
    'emit\s*=\s*emit',
    'reset\s*=\s*reset',
    'update\s*=\s*update',
    'render\s*=\s*render',
    'textureMissing',
    'instance:start',
    'instance:stop',
    'instance:health'
)) {
    if ($adapter -notmatch $contract) { throw "PZ visual contract is missing: $contract" }
}

$visual = [IO.File]::ReadAllText($visualPath, [Text.Encoding]::UTF8)
if ($visual -notmatch 'media/textures/GodSystem_WhitePixel\.png') {
    throw 'Pure companion renderer does not use the self-contained white texture'
}
if ($visual -notmatch 'renderer:renderline') {
    throw 'Pure companion renderer no longer uses the verified B42.20 renderline API'
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for companion PZ visual validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV422012CompanionPZVisualsRuntime.lua') $Root
if ($LASTEXITCODE -ne 0) { throw 'Companion PZ visual runtime test failed' }

Write-Output 'Test-GodSystemV422012CompanionPZVisuals passed'
