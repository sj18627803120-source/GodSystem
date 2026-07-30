param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$featureFiles = @(
    'shared\GodSystem\Features\Attributes\Rules.lua',
    'shared\GodSystem\Features\Attributes\State.lua',
    'shared\GodSystem\Features\Attributes\Module.lua',
    'shared\GodSystem\Features\Attributes\PublicPort.lua',
    'shared\GodSystem\Features\Admin\Rules.lua',
    'shared\GodSystem\Features\Admin\Module.lua',
    'shared\GodSystem\Features\Admin\PublicPort.lua'
)
$platformFiles = @(
    'shared\GodSystem\Platform\Attributes\Query.lua',
    'shared\GodSystem\Platform\Attributes\Mutation.lua',
    'shared\GodSystem\Platform\Admin\Source.lua',
    'shared\GodSystem\Platform\Admin\Permissions.lua',
    'shared\GodSystem\Platform\Admin\Runtime.lua'
)

foreach ($relative in $featureFiles + $platformFiles) {
    $path = Join-Path $luaRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing Attributes/Admin module file: $relative" }
}

foreach ($relative in @(
    'shared\GodSystem\Features\Attributes\Module.lua',
    'shared\GodSystem\Features\Admin\Module.lua'
)) {
    $text = [IO.File]::ReadAllText((Join-Path $luaRoot $relative), [Text.Encoding]::UTF8)
    if ($text -notmatch 'require\s+"GodSystem/Core/Result"') {
        throw "Feature does not use the shared result contract: $relative"
    }
    if ($text -match 'require\s+"(?:GodSystem_Core|GodSystem_Server|GodSystem_UI|GodSystem_Attributes|GodSystem_AdminConfig|GodSystem_Config)"') {
        throw "Feature requires a legacy implementation: $relative"
    }
    if ($text -match '\b(?:Events|sendClientCommand|sendServerCommand|OnClientCommand|OnServerCommand|getPlayer|getCell|SandboxVars)\b') {
        throw "Feature bypasses an explicit platform port: $relative"
    }
    foreach ($contract in @('Descriptor\.create', 'instance\.public', 'instance:start', 'instance:stop', 'instance:health')) {
        if ($text -notmatch $contract) { throw "Feature contract is missing '$contract': $relative" }
    }
}

$attributes = [IO.File]::ReadAllText(
    (Join-Path $luaRoot 'shared\GodSystem\Features\Attributes\Module.lua'), [Text.Encoding]::UTF8)
foreach ($dependency in @('attributes.query', 'attributes.mutation', 'admin.config', 'wallet', 'operations', 'notifications')) {
    if ($attributes -notmatch [regex]::Escape('"' + $dependency + '"')) {
        throw "Attributes explicit dependency is missing: $dependency"
    }
}
foreach ($behavior in @('purchaseAttribute', 'modifyTrait', 'settlePartial', 'syncPending', 'rollbackIncomplete')) {
    if ($attributes -notmatch [regex]::Escape($behavior)) { throw "Attributes behavior is missing: $behavior" }
}

$admin = [IO.File]::ReadAllText(
    (Join-Path $luaRoot 'shared\GodSystem\Features\Admin\Module.lua'), [Text.Encoding]::UTF8)
foreach ($behavior in @('setSettings', 'setItemOverride', 'clearItemOverride', 'adminPermissionDenied', 'runtimeApplyFailed')) {
    if ($admin -notmatch [regex]::Escape($behavior)) { throw "Admin behavior is missing: $behavior" }
}
if ($admin -match '(?i)(anti.?cheat|banPlayer|kickPlayer)') {
    throw 'Admin module unexpectedly contains anti-cheat behavior'
}

$rules = [IO.File]::ReadAllText(
    (Join-Path $luaRoot 'shared\GodSystem\Features\Admin\Rules.lua'), [Text.Encoding]::UTF8)
$metaCount = ([regex]::Matches($rules, '\bmeta\("')).Count
if ($metaCount -ne 73) { throw "Admin published setting count drifted: expected 73, got $metaCount" }

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for Attributes/Admin module validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV422012AttributesAdminModuleRuntime.lua') $luaRoot
if ($LASTEXITCODE -ne 0) { throw 'Attributes/Admin runtime test failed' }

Write-Output 'Test-GodSystemV422012AttributesAdminModule passed'
