param(
    [switch]$SkipLuaCompile
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11658.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11657.ps1') -Root $RepoRoot -ExpectedVersion '1.16.58'
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11656.ps1') -Root $RepoRoot -ExpectedVersion '1.16.58'
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11655.ps1') -Root $RepoRoot -ExpectedVersion '1.16.58'
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11653.ps1') -Root $RepoRoot -ExpectedVersion '1.16.58' -SkipLegacyTerminalChecks
& (Join-Path $PSScriptRoot 'tests\Test-ReferenceModResearch.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemEncoding.ps1') -Root $RepoRoot -IncludeDocs

if (-not $SkipLuaCompile) {
    $compiler = Get-Command luac -ErrorAction SilentlyContinue
    if (-not $compiler) {
        $localCompiler = Join-Path $env:USERPROFILE 'Tools\Lua51\luac.exe'
        if (Test-Path -LiteralPath $localCompiler) { $compiler = Get-Item -LiteralPath $localCompiler }
    }
    if ($compiler) {
        $compilerPath = if ($compiler.Source) { $compiler.Source } else { $compiler.FullName }
        $luaRoot = Join-Path $RepoRoot 'Contents\mods\GodSystem\42\media\lua'
        $files = @(Get-ChildItem -LiteralPath $luaRoot -Recurse -Filter '*.lua' -File)
        foreach ($file in $files) {
            & $compilerPath -p $file.FullName
            if ($LASTEXITCODE -ne 0) { throw "Lua compile failed: $($file.FullName)" }
        }
        Write-Output ("LuaCompileOK={0}" -f $files.Count)
    }
    else {
        Write-Warning 'Lua 5.1 luac was not found; compile validation was skipped.'
    }
}

Write-Output ("GodSystemTestsOK={0}" -f $RepoRoot)
