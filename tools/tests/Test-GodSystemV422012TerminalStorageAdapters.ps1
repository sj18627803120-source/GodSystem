param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$terminalRoot = Join-Path $luaRoot 'shared\GodSystem\Platform\Terminal'
$storageRoot = Join-Path $luaRoot 'shared\GodSystem\Platform\Storage'
$runtimeTest = Join-Path $PSScriptRoot 'Test-GodSystemV422012TerminalStorageAdaptersRuntime.lua'
$featureModule = Join-Path $luaRoot 'shared\GodSystem\Features\Storage\Module.lua'
$adapterPaths = @(
    Get-ChildItem -LiteralPath $terminalRoot,$storageRoot -Filter '*.lua'
) | Select-Object -ExpandProperty FullName

if ($adapterPaths.Count -lt 16) {
    throw 'Terminal/Storage PZ adapter set is incomplete'
}
if (-not (Test-Path -LiteralPath $runtimeTest)) {
    throw 'Terminal/Storage adapter runtime test is missing'
}

$combined = ($adapterPaths | ForEach-Object {
    [IO.File]::ReadAllText($_, [Text.Encoding]::UTF8)
}) -join "`n"
$descriptorIds = @(
    'terminal.config',
    'terminal.state',
    'terminal.instances',
    'terminal.audit',
    'storage.config',
    'storage.state',
    'storage.objects',
    'storage.containers',
    'storage.items',
    'storage.core',
    'storage.permissions',
    'storage.clock',
    'storage.sync',
    'storage.audit'
)
foreach ($descriptorId in $descriptorIds) {
    if ($combined -notmatch [regex]::Escape('"' + $descriptorId + '"')) {
        throw "Terminal/Storage adapter descriptor is missing: $descriptorId"
    }
}

if ($combined -match 'require\s+"GodSystem/(?:GodSystem_)?(?:Storage|Core|Server|Network|UI|Config)"') {
    throw 'Terminal/Storage adapters require a legacy business implementation'
}
if (($combined -notmatch 'context\.configSnapshot') -or
    ($combined -notmatch 'context\.state') -or
    ($combined -notmatch 'context\.binding')) {
    throw 'Terminal/Storage adapters do not use injected config, state and PZ bindings'
}

$objectsText = [IO.File]::ReadAllText(
    (Join-Path $storageRoot 'Objects.lua'), [Text.Encoding]::UTF8)
if (($objectsText -notmatch 'GodSystemStorageObjectId') -or
    ($objectsText -notmatch 'squareUnloaded') -or
    ($objectsText -notmatch 'objectMissing')) {
    throw 'Storage object adapter does not expose stable identity/load-state semantics'
}
if ($objectsText -match 'objectIndex|expectedSprite|resolveObjectCandidate') {
    throw 'Storage object adapter contains forbidden coordinate/index/sprite identity fallback'
}
if (($objectsText -notmatch 'getContainerCount') -or
    ($objectsText -notmatch 'getContainerByIndex')) {
    throw 'Storage object adapter does not preserve multi-slot furniture'
}

$containersText = [IO.File]::ReadAllText(
    (Join-Path $storageRoot 'Containers.lua'), [Text.Encoding]::UTF8)
if (($containersText -notmatch 'isItemAllowed') -or
    ($containersText -notmatch 'hasRoomFor') -or
    ($containersText -notmatch 'AddWorldInventoryItem')) {
    throw 'Storage container adapter does not preserve native acceptance/capacity/recovery'
}

$coreText = [IO.File]::ReadAllText(
    (Join-Path $storageRoot 'Core.lua'), [Text.Encoding]::UTF8)
if (($coreText -notmatch 'GodSystemStorageCoreToken') -or
    ($coreText -notmatch 'GodSystemStorageCoreNetworkId') -or
    ($coreText -notmatch 'cleanupDuplicates')) {
    throw 'Storage core adapter does not preserve exact core lifecycle identity'
}

$instancesText = [IO.File]::ReadAllText(
    (Join-Path $terminalRoot 'Instances.lua'), [Text.Encoding]::UTF8)
if (($instancesText -notmatch 'findOwned') -or
    ($instancesText -notmatch 'cleanupEscapedRelief') -or
    ($instancesText -notmatch 'writeNumber')) {
    throw 'Terminal adapter does not preserve exact instance and verified-write behavior'
}

$featureText = [IO.File]::ReadAllText($featureModule, [Text.Encoding]::UTF8)
foreach ($recoveryStage in @(
    'add", source, item',
    'playerContainer", actor, nil',
    'ground",'
)) {
    if ($featureText -notmatch [regex]::Escape($recoveryStage)) {
        throw "Storage per-item transaction recovery stage missing: $recoveryStage"
    }
}

$luaExe = Get-Command lua5.1,lua -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $luaExe) {
    $candidate = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua5.1.exe'
    if (Test-Path -LiteralPath $candidate) {
        $luaExe = Get-Item -LiteralPath $candidate
    }
}
if (-not $luaExe) {
    throw 'Lua 5.1 runtime is required for Terminal/Storage adapter validation'
}
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath $runtimeTest $luaRoot
if ($LASTEXITCODE -ne 0) {
    throw 'Terminal/Storage adapter runtime test failed'
}

$luacExe = Get-Command luac5.1,luac -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $luacExe) {
    $candidate = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\luac5.1.exe'
    if (Test-Path -LiteralPath $candidate) {
        $luacExe = Get-Item -LiteralPath $candidate
    }
}
if (-not $luacExe) {
    throw 'Lua 5.1 compiler is required for Terminal/Storage adapter validation'
}
$luacPath = if ($luacExe.Source) { $luacExe.Source } else { $luacExe.FullName }
foreach ($path in $adapterPaths + @($runtimeTest)) {
    & $luacPath -p $path
    if ($LASTEXITCODE -ne 0) {
        throw "Terminal/Storage adapter Lua 5.1 compile failed: $path"
    }
}

Write-Output 'Test-GodSystemV422012TerminalStorageAdapters passed'
