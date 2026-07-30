param(
    [switch]$SkipLuaCompile
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012Architecture.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012Release.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemArchitectureBoundaries.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012LegacyCleanup.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012Composition.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012Diagnostics.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012PlatformServices.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012AutoLoaderModule.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemMigration422011.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012MigrationRunner.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012RuntimeKernel.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012Coordinator.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012UseCaseDispatcher.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012RemoteBridge.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012ClientGateway.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012UIFacade.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012PageRegistry.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012UIShellAdapter.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012UIActionAdapter.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012PZRuntime.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012ConfigSnapshot.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012Metrics.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012AttributesAdminModule.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012SystemModule.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012MaintenanceModule.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012WalletBankModule.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012TaskShopRecycleModule.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012CommerceAdapters.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012UpgradeMedicalHomeModule.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012ProgressionPlatform.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012TerminalStorageModule.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012CompanionModule.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012CompanionPZVisuals.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012BankAdapters.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012TerminalStorageAdapters.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012StorageAdapter.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012AutoLoaderAdapter.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422011.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.2'
& (Join-Path $PSScriptRoot 'tests\Test-ReferenceModResearch.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-RepositoryGuidance.ps1') -Root $RepoRoot
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
