param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Lua = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$required = @(
    'shared\GodSystem\Core\Result.lua',
    'shared\GodSystem\Core\Diagnostics.lua',
    'shared\GodSystem\Core\ModuleRegistry.lua',
    'shared\GodSystem\Platform\EventGateway.lua',
    'shared\GodSystem\Platform\CommandRouter.lua',
    'shared\GodSystem\Platform\PZEventSource.lua',
    'shared\GodSystem\Platform\PZCommandTransport.lua',
    'shared\GodSystem\Platform\PZModDataAdapter.lua',
    'shared\GodSystem\State\Store.lua',
    'shared\GodSystem\Services\OperationLedger.lua',
    'shared\GodSystem\Bootstrap.lua'
)
foreach ($relative in $required) {
    $path = Join-Path $Lua $relative
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing modular architecture file: $relative" }
}

$bootstrap = [IO.File]::ReadAllText((Join-Path $Lua 'shared\GodSystem\Bootstrap.lua'), [Text.Encoding]::UTF8)
if ($bootstrap -match 'Shop|Bank|Task|Recycle|StorageController|Companion') {
    throw 'Lightweight bootstrap contains feature business logic'
}

$architectureFiles = Get-ChildItem -LiteralPath (Join-Path $Lua 'shared\GodSystem') -Recurse -Filter '*.lua' -File
foreach ($file in $architectureFiles) {
    $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    if ($text -match 'require\s+"GodSystem_Core"|require\s+"GodSystem_Server"|require\s+"GodSystem_UI"') {
        throw "Architecture layer depends on a legacy entry point: $($file.FullName)"
    }
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for modular architecture validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV422012ArchitectureRuntime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'Modular architecture runtime test failed' }

Write-Output 'Test-GodSystemV422012Architecture passed'
