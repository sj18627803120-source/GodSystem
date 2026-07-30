param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Lua = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$viewModel = Join-Path $Lua 'shared\GodSystem\UI\DiagnosticsViewModel.lua'
if (-not (Test-Path -LiteralPath $viewModel)) {
    throw 'Diagnostics view model is missing'
}
$text = [IO.File]::ReadAllText($viewModel, [Text.Encoding]::UTF8)
if ($text -match 'GodSystem_Core|GodSystem_Server|GodSystem_UI|sendClientCommand|sendServerCommand|Events\.') {
    throw 'Diagnostics view model reaches into legacy runtime or PZ gateways'
}
foreach ($required in @('ViewModel.build', 'ViewModel.advancedText', 'statusLabel', 'moduleState', 'advice', 'rows')) {
    if ($text -notmatch [regex]::Escape($required)) {
        throw "Player diagnostics presentation is missing: $required"
    }
}
foreach ($required in @('operationId', 'moduleId', 'dependencies', 'stack')) {
    $runtime = [IO.File]::ReadAllText(
        (Join-Path $PSScriptRoot 'Test-GodSystemV422012DiagnosticsRuntime.lua'),
        [Text.Encoding]::UTF8
    )
    if ($runtime -notmatch [regex]::Escape($required)) {
        throw "Advanced diagnostics coverage is missing: $required"
    }
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $candidate = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $candidate) { $luaExe = Get-Item -LiteralPath $candidate }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for diagnostics validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV422012DiagnosticsRuntime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'Diagnostics runtime test failed' }

Write-Output 'Test-GodSystemV422012Diagnostics passed'
