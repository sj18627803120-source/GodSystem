param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Lua = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$required = @(
    'shared\GodSystem\Composition.lua',
    'shared\GodSystem\Features\Wallet\PublicPort.lua'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $Lua $relative))) {
        throw "Missing composition file: $relative"
    }
}

$composition = [IO.File]::ReadAllText(
    (Join-Path $Lua 'shared\GodSystem\Composition.lua'),
    [Text.Encoding]::UTF8
)
if ($composition -match 'GodSystem_Core|GodSystem_Server|GodSystem_UI') {
    throw 'Composition root depends on a legacy entry point'
}
if ($composition -match 'getPlayer|getSpecificPlayer|sendClientCommand|sendServerCommand') {
    throw 'Composition root contains direct PZ or protocol calls'
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for composition validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }

& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV422012CompositionRuntime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'Composition runtime test failed' }

Write-Output 'Test-GodSystemV422012Composition passed'
