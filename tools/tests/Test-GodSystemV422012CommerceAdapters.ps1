param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$adapterRoot = Join-Path $luaRoot 'shared\GodSystem\Platform\Commerce'
$runtimeTest = Join-Path $PSScriptRoot 'Test-GodSystemV422012CommerceAdaptersRuntime.lua'
$adapterPaths = Get-ChildItem -LiteralPath $adapterRoot -Filter '*.lua' | Select-Object -ExpandProperty FullName
$servicePaths = @(
    (Join-Path $luaRoot 'shared\GodSystem\Services\Clock.lua'),
    (Join-Path $luaRoot 'shared\GodSystem\Services\Random.lua'),
    (Join-Path $luaRoot 'shared\GodSystem\Services\Operations.lua'),
    (Join-Path $luaRoot 'shared\GodSystem\Services\Notifications.lua')
)
if ($adapterPaths.Count -lt 9) { throw 'Commerce PZ adapter set is incomplete' }
if (-not (Test-Path -LiteralPath $runtimeTest)) { throw 'Commerce PZ adapter runtime test is missing' }

$combined = ($adapterPaths + $servicePaths | ForEach-Object {
    [IO.File]::ReadAllText($_, [Text.Encoding]::UTF8)
}) -join "`n"
foreach ($descriptorId in @(
    'tasks.config', 'tasks.state', 'tasks.inventory', 'tasks.wallet',
    'shop.config', 'shop.state', 'shop.identity', 'shop.inventory', 'shop.wallet',
    'recycle.config', 'recycle.state', 'recycle.inventory', 'recycle.wallet',
    'item.eligibility', 'shop.listings', 'clock', 'random', 'operations'
)) {
    if ($combined -notmatch [regex]::Escape('"' + $descriptorId + '"')) {
        throw "Commerce adapter descriptor is missing: $descriptorId"
    }
}
if ($combined -match 'require\s+"(?:GodSystem_Config|GodSystem_Core|GodSystem_Server|GodSystem_Network|GodSystem_UI|GodSystem_ShopVariants|GodSystem_ItemEligibility)"') {
    throw 'Commerce adapters depend on a legacy business implementation'
}
if ($combined -notmatch 'context\.configSnapshot' -or $combined -notmatch 'context\.state') {
    throw 'Commerce config/state adapters do not use injected snapshots and scoped state'
}
if ($combined -notmatch '@worldSprite=' -or $combined -notmatch 'ReadFromWorldSprite') {
    throw 'Commerce adapters do not preserve furniture variant identity and restoration'
}
if ($combined -notmatch 'getScriptManager' -or $combined -notmatch 'FindItem') {
    throw 'Commerce adapters do not dynamically validate registered third-party items'
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $candidate = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $candidate) { $luaExe = Get-Item -LiteralPath $candidate }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for commerce adapter validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath $runtimeTest $luaRoot
if ($LASTEXITCODE -ne 0) { throw 'Commerce adapter runtime test failed' }

$luacExe = Get-Command luac -ErrorAction SilentlyContinue
if (-not $luacExe) {
    $candidate = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\luac.exe'
    if (Test-Path -LiteralPath $candidate) { $luacExe = Get-Item -LiteralPath $candidate }
}
if (-not $luacExe) { throw 'Lua 5.1 compiler is required for commerce adapter validation' }
$luacPath = if ($luacExe.Source) { $luacExe.Source } else { $luacExe.FullName }
foreach ($path in $adapterPaths + $servicePaths + @($runtimeTest)) {
    & $luacPath -p $path
    if ($LASTEXITCODE -ne 0) { throw "Commerce adapter Lua 5.1 compile failed: $path" }
}

Write-Output 'Test-GodSystemV422012CommerceAdapters passed'
