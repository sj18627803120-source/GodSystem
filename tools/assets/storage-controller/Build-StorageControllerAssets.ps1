param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
}

$sourcePath = Join-Path $PSScriptRoot "GodSystem_StorageController_alpha.png"
$tileSourcePath = Join-Path $PSScriptRoot "GodSystem_StorageController.png"
$mediaPath = Join-Path $RepoRoot "Contents\mods\GodSystem\42\media"
$texturePackPath = Join-Path $mediaPath "texturepacks\GodSystemStorageController.pack"
$tileDefinitionPath = Join-Path $mediaPath "GodSystemStorageController.tiles"
$tileDefinitionSourcePath = Join-Path $mediaPath "GodSystemStorageController.tiles.txt"

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Missing prepared RGBA source: $sourcePath"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $texturePackPath) | Out-Null

Add-Type -AssemblyName System.Drawing

$source = [System.Drawing.Bitmap]::FromFile($sourcePath)
$tile = New-Object System.Drawing.Bitmap 128, 256, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($tile)

try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighSpeed
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None

    $sourceRect = New-Object System.Drawing.Rectangle 156, 179, 578, 1411
    $targetRect = New-Object System.Drawing.Rectangle 17, 14, 94, 230
    $graphics.DrawImage(
        $source,
        $targetRect,
        $sourceRect,
        [System.Drawing.GraphicsUnit]::Pixel
    )
}
finally {
    $graphics.Dispose()
    $source.Dispose()
}

try {
    $tile.Save($tileSourcePath, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $tile.Dispose()
}

function Write-Utf8Block {
    param(
        [System.IO.BinaryWriter]$Writer,
        [string]$Value
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $Writer.Write([int]$bytes.Length)
    $Writer.Write($bytes)
}

$packStream = [System.IO.File]::Open(
    $texturePackPath,
    [System.IO.FileMode]::Create,
    [System.IO.FileAccess]::Write,
    [System.IO.FileShare]::None
)
$packWriter = New-Object System.IO.BinaryWriter $packStream

try {
    $packWriter.Write([System.Text.Encoding]::ASCII.GetBytes("PZPK"))
    $packWriter.Write([int]1)
    $packWriter.Write([int]1)

    Write-Utf8Block -Writer $packWriter -Value "GodSystemStorageController0"
    $packWriter.Write([int]1)
    $packWriter.Write([int]1)

    Write-Utf8Block -Writer $packWriter -Value "GodSystem_StorageController_0"
    foreach ($value in @(0, 0, 128, 256, 0, 0, 128, 256)) {
        $packWriter.Write([int]$value)
    }

    $packWriter.Write([System.IO.File]::ReadAllBytes($tileSourcePath))
    $packWriter.Write([byte[]]@(0xEF, 0xBE, 0xAD, 0xDE))
}
finally {
    $packWriter.Dispose()
    $packStream.Dispose()
}

$properties = [ordered]@{
    BlocksPlacement = ""
    CustomItem = "GodSystem.StorageController"
    CustomName = "System Storage Controller"
    IsMoveAble = ""
    MoveType = "Object"
    PickUpWeight = "20"
}

$definitionText = @"
version = 1
tileset
{
    file = GodSystem_StorageController
    size = 1,1
    id = 1
    // GodSystem_StorageController_0
    tile
    {
        xy = 0,0
        BlocksPlacement =
        CustomItem = GodSystem.StorageController
        CustomName = System Storage Controller
        IsMoveAble =
        MoveType = Object
        PickUpWeight = 20
    }
}
"@
[System.IO.File]::WriteAllText(
    $tileDefinitionSourcePath,
    $definitionText.TrimStart(),
    (New-Object System.Text.UTF8Encoding $false)
)

function Write-AsciiLine {
    param(
        [System.IO.BinaryWriter]$Writer,
        [string]$Value
    )

    $Writer.Write([System.Text.Encoding]::ASCII.GetBytes($Value))
    $Writer.Write([byte]10)
}

$tileStream = [System.IO.File]::Open(
    $tileDefinitionPath,
    [System.IO.FileMode]::Create,
    [System.IO.FileAccess]::Write,
    [System.IO.FileShare]::None
)
$tileWriter = New-Object System.IO.BinaryWriter $tileStream

try {
    $tileWriter.Write([System.Text.Encoding]::ASCII.GetBytes("tdef"))
    $tileWriter.Write([int]1)
    $tileWriter.Write([int]1)

    Write-AsciiLine -Writer $tileWriter -Value "GodSystem_StorageController"
    Write-AsciiLine -Writer $tileWriter -Value "GodSystem_StorageController.png"
    $tileWriter.Write([int]1)
    $tileWriter.Write([int]1)
    $tileWriter.Write([int]1)
    $tileWriter.Write([int]1)

    $tileWriter.Write([int]$properties.Count)
    foreach ($entry in $properties.GetEnumerator()) {
        Write-AsciiLine -Writer $tileWriter -Value ([string]$entry.Key)
        Write-AsciiLine -Writer $tileWriter -Value ([string]$entry.Value)
    }
}
finally {
    $tileWriter.Dispose()
    $tileStream.Dispose()
}

Write-Host "Generated:"
Write-Host "  $tileSourcePath"
Write-Host "  $texturePackPath"
Write-Host "  $tileDefinitionPath"
Write-Host "  $tileDefinitionSourcePath"
