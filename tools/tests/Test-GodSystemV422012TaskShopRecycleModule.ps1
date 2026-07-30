param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$modules = @(
    'shared\GodSystem\Features\Tasks\Module.lua',
    'shared\GodSystem\Features\Shop\Module.lua',
    'shared\GodSystem\Features\Recycle\Module.lua'
)

foreach ($relative in $modules) {
    $path = Join-Path $luaRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing vertical feature module: $relative" }
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if ($text -notmatch 'require\s+"GodSystem/Core/Result"') {
        throw "Feature module does not use the shared result contract: $relative"
    }
    if ($text -match 'require\s+"(?:GodSystem_Core|GodSystem_Server|GodSystem_UI|GodSystem_ShopVariants|GodSystem_ItemEligibility)"') {
        throw "Feature module requires a legacy business implementation: $relative"
    }
    if ($text -match '\b(?:Events|sendClientCommand|sendServerCommand|OnClientCommand|OnServerCommand)\b') {
        throw "Feature module bypasses the platform gateway: $relative"
    }
    foreach ($required in @('Descriptor\.create', 'instance\.public', 'instance:start', 'instance:stop', 'instance:health')) {
        if ($text -notmatch $required) { throw "Feature module is missing contract '$required': $relative" }
    }
}

$tasks = [IO.File]::ReadAllText((Join-Path $luaRoot $modules[0]), [Text.Encoding]::UTF8)
foreach ($symbol in @('generate = generate', 'accept = accept', 'progress = progress', 'claim = claim', 'fail = failTask')) {
    if ($tasks -notmatch [regex]::Escape($symbol)) { throw "Tasks public contract is incomplete: $symbol" }
}

$shop = [IO.File]::ReadAllText((Join-Path $luaRoot $modules[1]), [Text.Encoding]::UTF8)
foreach ($symbol in @('listItem = listItem', 'setHidden = function', 'deleteListing = function', 'purchase = purchase', 'lottery = lottery')) {
    if ($shop -notmatch [regex]::Escape($symbol)) { throw "Shop public contract is incomplete: $symbol" }
}
if ($shop -notmatch 'worldSprite' -or $shop -notmatch 'hidden == true') {
    throw 'Shop module does not preserve furniture variants and hidden-listing semantics'
}

$recycle = [IO.File]::ReadAllText((Join-Path $luaRoot $modules[2]), [Text.Encoding]::UTF8)
foreach ($mode in @('recycle', 'recycleAndList', 'listOnly')) {
    if ($recycle -notmatch [regex]::Escape($mode)) { throw "Recycle mode is missing: $mode" }
}
if ($recycle -notmatch 'skippedCount' -or $recycle -notmatch 'rollbackListings' -or $recycle -notmatch 'restoreRemoved') {
    throw 'Recycle module does not expose partial results and batch rollback'
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for task/shop/recycle module validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV422012TaskShopRecycleModuleRuntime.lua') $luaRoot
if ($LASTEXITCODE -ne 0) { throw 'Task/shop/recycle module runtime test failed' }

Write-Output 'Test-GodSystemV422012TaskShopRecycleModule passed'
