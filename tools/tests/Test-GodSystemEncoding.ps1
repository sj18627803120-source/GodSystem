param(
    [string]$Root = "",
    [switch]$IncludeDocs
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

if (-not (Test-Path -LiteralPath $Root)) {
    throw "Root path not found: $Root"
}

function New-TextFromCodepoints {
    param([int[]]$Codepoints)
    $chars = foreach ($cp in $Codepoints) { [char]$cp }
    return -join $chars
}

# Keep this script ASCII-only. These codepoints describe common mojibake fragments.
$patterns = @(
    (New-TextFromCodepoints @(0x00EF, 0x00BF, 0x00BD)), # U+FFFD encoded as mojibake
    (New-TextFromCodepoints @(0x951B)),                 # common Chinese mojibake fragment
    (New-TextFromCodepoints @(0x6D93)),                 # common Chinese mojibake fragment
    (New-TextFromCodepoints @(0x7F01)),                 # common Chinese mojibake fragment
    (New-TextFromCodepoints @(0x9428)),                 # common Chinese mojibake fragment
    (New-TextFromCodepoints @(0x952F, 0x65A4, 0x62F7))  # repeated replacement mojibake
)

$extensions = @("*.lua", "*.txt", "*.info", "*.ini", "*.ps1")
if ($IncludeDocs) {
    $extensions += @("*.md", "*.json", "*.html", "*.css")
}

$files = foreach ($ext in $extensions) {
    Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $ext -ErrorAction SilentlyContinue
}

$bad = New-Object System.Collections.Generic.List[object]
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

foreach ($file in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF) {
        $bad.Add([pscustomobject]@{
            Path = $file.FullName
            Issue = "Contains UTF-8 BOM"
            Detail = "EF BB BF"
        })
    }
    $text = $null
    try {
        $text = $utf8Strict.GetString($bytes)
    } catch {
        $bad.Add([pscustomobject]@{
            Path = $file.FullName
            Issue = "Invalid UTF-8 byte sequence"
            Detail = $_.Exception.Message
        })
        continue
    }

    if ($text.Contains([char]0xFFFD)) {
        $bad.Add([pscustomobject]@{
            Path = $file.FullName
            Issue = "Contains U+FFFD replacement character"
            Detail = "U+FFFD"
        })
    }

    foreach ($pattern in $patterns) {
        if ($text.Contains($pattern)) {
            $bad.Add([pscustomobject]@{
                Path = $file.FullName
                Issue = "Contains possible mojibake fragment"
                Detail = ("U+" + ([int][char]$pattern[0]).ToString("X4"))
            })
            break
        }
    }
}

if ($bad.Count -gt 0) {
    $bad | Format-Table -AutoSize
    exit 1
}

Write-Output "EncodingOK=$Root"
