param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Lua = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$featureRoot = Join-Path $Lua 'shared\GodSystem\Features\Companion'
$platformRoot = Join-Path $Lua 'shared\GodSystem\Platform\Companion'
$featurePaths = @(
    (Join-Path $featureRoot 'Rules.lua'),
    (Join-Path $featureRoot 'State.lua'),
    (Join-Path $featureRoot 'Module.lua')
)
$platformPaths = @(
    (Join-Path $platformRoot 'Support.lua'),
    (Join-Path $platformRoot 'Query.lua'),
    (Join-Path $platformRoot 'Mutation.lua'),
    (Join-Path $platformRoot 'Events.lua'),
    (Join-Path $platformRoot 'Visuals.lua')
)
$runtimePaths = @(
    (Join-Path $PSScriptRoot 'Test-GodSystemV422012CompanionModuleRuntime.lua'),
    (Join-Path $PSScriptRoot 'Test-GodSystemV422012CompanionPlatformRuntime.lua')
)

foreach ($path in $featurePaths + $platformPaths + $runtimePaths) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing companion module test input: $path"
    }
}

$moduleText = [IO.File]::ReadAllText((Join-Path $featureRoot 'Module.lua'), [Text.Encoding]::UTF8)
$rulesText = [IO.File]::ReadAllText((Join-Path $featureRoot 'Rules.lua'), [Text.Encoding]::UTF8)
$stateText = [IO.File]::ReadAllText((Join-Path $featureRoot 'State.lua'), [Text.Encoding]::UTF8)
$featureText = ($featurePaths | ForEach-Object {
    [IO.File]::ReadAllText($_, [Text.Encoding]::UTF8)
}) -join "`n"

foreach ($dependency in @(
    'companion.query', 'companion.mutation', 'companion.events',
    'companion.visuals', 'wallet', 'operations', 'notifications'
)) {
    if ($moduleText -notmatch [regex]::Escape('"' + $dependency + '"')) {
        throw "Companion module does not declare dependency: $dependency"
    }
}
if ($featureText -match 'require\s+"(?:GodSystem_Companion|GodSystem_Core|GodSystem_Server|GodSystem_Network|GodSystem_UI)"') {
    throw 'Companion feature depends on a legacy implementation or entry point'
}
if ($featureText -cmatch 'Events\.|getPlayer\s*\(|getSpecificPlayer\s*\(|getCell\s*\(|IsoLightSource|sendClientCommand|sendServerCommand|ModData\.') {
    throw 'Companion feature directly accesses a PZ runtime boundary'
}
foreach ($contract in @(
    'robotChargeSeconds = 0.20',
    'robotRecoverySeconds = 0.15',
    'projectileTravelSeconds = 0.35',
    'attackSearchSeconds = 0.20',
    'robotNormalSpeed = 1.2',
    'robotCatchupSpeed = 4.5',
    'robotTrailSeconds = 0.12',
    'markDamageMultiplier = 1.20',
    'chainDamageRatio = 0.50',
    'blastDamageRatio = 0.25'
)) {
    if ($rulesText -notmatch [regex]::Escape($contract)) {
        throw "Companion current rule changed or disappeared: $contract"
    }
}
foreach ($stateName in @(
    'pendingAttack', 'chargeStartedMs', 'chargeEndsMs', 'projectiles',
    'shockCooldowns', 'corrosionStates', 'markStates', 'effectVisuals',
    'vehicleSuspended', 'pauseSuspended'
)) {
    if ($stateText -notmatch [regex]::Escape($stateName)) {
        throw "Companion runtime state missing: $stateName"
    }
}
foreach ($useCase in @(
    'purchase', 'tick', 'render', 'activateSight', 'setCombatMode',
    'setFollowMode', 'toggleVisible', 'toggleGuardian', 'recall',
    'getState', 'shutdown'
)) {
    if ($moduleText -notmatch [regex]::Escape($useCase)) {
        throw "Companion module is missing use case: $useCase"
    }
}
$attackContractMissing = ($moduleText -notmatch 'targetAllowed') `
    -or ($moduleText -notmatch 'launchAttack') `
    -or ($moduleText -notmatch 'cancelAttack') `
    -or ($moduleText -notmatch 'rollbackIncomplete')
if ($attackContractMissing) {
    throw 'Companion attack validation, transition, or transaction contract is incomplete'
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for companion module validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath $runtimePaths[0] $Lua
if ($LASTEXITCODE -ne 0) { throw 'Companion feature runtime test failed' }
& $luaPath $runtimePaths[1] $Lua
if ($LASTEXITCODE -ne 0) { throw 'Companion platform runtime test failed' }

$luacExe = Get-Command luac -ErrorAction SilentlyContinue
if (-not $luacExe) {
    $localLuac = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\luac.exe'
    if (Test-Path -LiteralPath $localLuac) { $luacExe = Get-Item -LiteralPath $localLuac }
}
if (-not $luacExe) { throw 'Lua 5.1 compiler is required for companion module validation' }
$luacPath = if ($luacExe.Source) { $luacExe.Source } else { $luacExe.FullName }
foreach ($path in $featurePaths + $platformPaths + $runtimePaths) {
    & $luacPath -p $path
    if ($LASTEXITCODE -ne 0) { throw "Companion Lua 5.1 compile failed: $path" }
}

Write-Output 'Test-GodSystemV422012CompanionModule passed'
