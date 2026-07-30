param(
    [Parameter(Mandatory = $true)]
    [string]$Root
)

$ErrorActionPreference = 'Stop'
$expectedVersion = '42.20.1.2'
$expectedModId = 'GodSystem_CN'
$expectedWorkshopId = '3773949382'
$modRoot = Join-Path $Root 'Contents\mods\GodSystem'
$luaRoot = Join-Path $modRoot '42\media\lua'

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "missing file: $Path" }
    return [System.IO.File]::ReadAllText(
        $Path, [System.Text.UTF8Encoding]::new($false))
}

function Assert-Match([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}

$rootInfo = Read-Utf8 (Join-Path $modRoot 'mod.info')
$b42Info = Read-Utf8 (Join-Path $modRoot '42\mod.info')
$config = Read-Utf8 (Join-Path $luaRoot 'shared\GodSystem_Config.lua')
$protocol = Read-Utf8 `
    (Join-Path $luaRoot 'shared\GodSystem\Runtime\Protocol422012.lua')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')
$docsRoot = Join-Path $Root 'docs\GodSystem_DevHandoff_CN'
$entryFile = @(Get-ChildItem -LiteralPath $docsRoot -Filter '00_*.md' -File)
$handoffFile = @(Get-ChildItem -LiteralPath $docsRoot `
    -Filter '74_42.20.1.2_*.md' -File)
if ($entryFile.Count -ne 1) { throw 'current continuation entry is missing or ambiguous' }
if ($handoffFile.Count -ne 1) { throw 'current handoff is missing or ambiguous' }
$entry = Read-Utf8 $entryFile[0].FullName
$handoff = Read-Utf8 $handoffFile[0].FullName

$versionPattern = [regex]::Escape($expectedVersion)
foreach ($info in @($rootInfo, $b42Info)) {
    Assert-Match $info ('(?m)^modversion=' + $versionPattern + '\r?$') `
        'mod.info release version mismatch'
    Assert-Match $info ('(?m)^id=' + [regex]::Escape($expectedModId) + '\r?$') `
        'Mod ID changed'
}
Assert-Match $config `
    ('GodSystemConfig\.Version\s*=\s*"' + $versionPattern + '"') `
    'config release version mismatch'
Assert-Match $protocol `
    ('Protocol\.Version\s*=\s*"' + $versionPattern + '"') `
    'protocol release version mismatch'
Assert-Match $workshop `
    ('(?m)^id=' + [regex]::Escape($expectedWorkshopId) + '\r?$') `
    'Workshop ID changed'
Assert-Match $workshop `
    ('(?m)^description=v' + $versionPattern + '\r?$') `
    'Workshop release version mismatch'
Assert-Match $entry '74_42\.20\.1\.2_' `
    'continuation entry does not point to the current handoff'
Assert-Match $handoff 'B42\.20 real-game validation pending' `
    'handoff must state that real-game validation is pending'

Write-Output 'Test-GodSystemV422012ReleaseOK'
