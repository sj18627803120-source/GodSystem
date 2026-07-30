param(
    [switch]$SkipLuaCompile
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012Architecture.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemArchitectureBoundaries.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012Composition.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012PlatformServices.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012AutoLoaderModule.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemMigration422011.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012MaintenanceModule.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012WalletBankModule.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012TaskShopRecycleModule.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422012UpgradeMedicalHomeModule.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV422011.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1'
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11673.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1'
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11672.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -AllowStorageRoutingV11673
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11671.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -AllowStorageRoutingV11673
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11670.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -AllowCoreHostStorage -AllowRetiredMigrationCleanup
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11669.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -AllowStorageCore
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11668.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -AllowStorageCore
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11667.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -AllowStorageCore
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11666.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1'
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11665.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -AllowStorageCore
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11664.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -AllowStorageCore
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11663TerminalSync.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11663VehicleRepair.ps1') -Root $RepoRoot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11663TerminalWear.ps1') -Root $RepoRoot -AllowRetiredWearMigration
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11663.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -ExpectedAdminSettings 73
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11662.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -AllowRetiredCapacity -AllowRetiredCompatibility
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11661.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -AllowRetiredRemoveUnlocked
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11660.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -AllowRetiredCompression
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11659.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -AllowRetiredCompression
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11658.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -AllowRetiredCompression
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11657.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -AllowRetiredCompression
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11656.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1'
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11655.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -AllowCustomTerminalSlot
& (Join-Path $PSScriptRoot 'tests\Test-GodSystemV11653.ps1') -Root $RepoRoot -ExpectedVersion '42.20.1.1' -ExpectedAdminSettings 73 -SkipLegacyTerminalChecks
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
