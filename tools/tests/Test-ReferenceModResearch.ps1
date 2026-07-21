param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'

function ConvertFrom-CodePoints {
    param([int[]]$Values)
    return -join ($Values | ForEach-Object { [char]$_ })
}

$researchRoot = Join-Path $Root 'docs\reference-mod-research'
$reports = @(
    'MoreTraits.md',
    'CAExtendedCategories.md',
    'CaiGou-Shop.md',
    'CultivationStorageArtifacts.md',
    'damnlib.md',
    'DebugMenu.md',
    'PsionicAwakening.md',
    'RuinBazaar.md',
    'Server-Shop.md',
    'TraitsPurchaseSystem.md',
    'YeseMarket.md'
)

$requiredHeadings = @(
    ('## ' + (ConvertFrom-CodePoints @(0x8EAB, 0x4EFD, 0x4E0E, 0x7248, 0x672C))),
    ('## ' + (ConvertFrom-CodePoints @(0x5173, 0x952E, 0x8BC1, 0x636E))),
    ('## ' + (ConvertFrom-CodePoints @(0x53EF, 0x91C7, 0x7528, 0x673A, 0x5236))),
    ('## ' + (ConvertFrom-CodePoints @(0x98CE, 0x9669, 0x4E0E, 0x9650, 0x5236))),
    ('## ' + (ConvertFrom-CodePoints @(0x5F85, 0x9A8C, 0x8BC1, 0x5185, 0x5BB9)))
)
$evidenceLabels = @(
    (ConvertFrom-CodePoints @(0x4EE3, 0x7801, 0x786E, 0x8BA4)),
    (ConvertFrom-CodePoints @(0x4F5C, 0x8005, 0x58F0, 0x660E)),
    (ConvertFrom-CodePoints @(0x5408, 0x7406, 0x63A8, 0x65AD)),
    (ConvertFrom-CodePoints @(0x5F85, 0x5B9E, 0x673A, 0x9A8C, 0x8BC1))
)
$versionLabels = @(
    ('B42.19 ' + (ConvertFrom-CodePoints @(0x540C, 0x7248, 0x672C, 0x8BC1, 0x636E))),
    ((ConvertFrom-CodePoints @(0x65E7)) + ' B42 ' + (ConvertFrom-CodePoints @(0x53C2, 0x8003))),
    ('B41 ' + (ConvertFrom-CodePoints @(0x5F31, 0x53C2, 0x8003)))
)
$failures = New-Object 'System.Collections.Generic.List[string]'

foreach ($report in $reports) {
    $path = Join-Path $researchRoot ('mods\' + $report)
    if (-not (Test-Path -LiteralPath $path)) {
        $failures.Add('Missing report: ' + $report)
        continue
    }

    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    foreach ($heading in $requiredHeadings) {
        if (-not $text.Contains($heading)) {
            $failures.Add($report + ' missing heading: ' + $heading)
        }
    }
    if (-not ($evidenceLabels | Where-Object { $text.Contains('`' + $_ + '`') })) {
        $failures.Add($report + ' has no evidence label')
    }
    if (-not ($versionLabels | Where-Object { $text.Contains('`' + $_ + '`') })) {
        $failures.Add($report + ' has no version-confidence label')
    }
}

foreach ($index in @('README.md', 'catalog.md')) {
    $path = Join-Path $researchRoot $index
    if (-not (Test-Path -LiteralPath $path)) {
        $failures.Add('Missing index: ' + $index)
        continue
    }

    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    foreach ($report in $reports) {
        if (-not $text.Contains('mods/' + $report)) {
            $failures.Add($index + ' missing link: ' + $report)
        }
    }
}

if (Test-Path -LiteralPath $researchRoot) {
    $unexpectedAssets = @(Get-ChildItem -LiteralPath $researchRoot -Recurse -File | Where-Object { $_.Extension -ne '.md' })
    foreach ($file in $unexpectedAssets) {
        $failures.Add('Unexpected non-Markdown asset: ' + $file.Name)
    }

    foreach ($file in Get-ChildItem -LiteralPath $researchRoot -Recurse -File -Filter '*.md') {
        $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        if ($text.Contains([char]0xFFFD)) {
            $failures.Add('Replacement character: ' + $file.Name)
        }
        if ($text -match 'C:\\Users\\Admin') {
            $failures.Add('Machine-specific path: ' + $file.Name)
        }

        $mojibakeChars = @([char]0x951B, [char]0x9286, [char]0x9225, [char]0x7F01, [char]0x7EEF)
        if ($mojibakeChars | Where-Object { $text.Contains($_) }) {
            $failures.Add('Possible mojibake: ' + $file.Name)
        }
    }
}

if ($failures.Count -gt 0) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Output ('ReferenceModResearchOK={0}' -f $reports.Count)
