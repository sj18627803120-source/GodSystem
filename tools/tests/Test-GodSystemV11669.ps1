param(
    [string]$Root = "",
    [string]$ExpectedVersion = "1.16.69"
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Mod = Join-Path $Root 'Contents\mods\GodSystem'
$Media = Join-Path $Mod '42\media'
$Lua = Join-Path $Media 'lua'

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}
function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}
function Reject-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw $Message }
}
function Require-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw "$Message (expected=$Expected actual=$Actual)"
    }
}
function Read-AsciiLine([System.IO.BinaryReader]$Reader) {
    $bytes = New-Object System.Collections.Generic.List[byte]
    while ($Reader.BaseStream.Position -lt $Reader.BaseStream.Length) {
        $value = $Reader.ReadByte()
        if ($value -eq 10) { break }
        $bytes.Add($value)
    }
    [System.Text.Encoding]::ASCII.GetString($bytes.ToArray())
}
function Read-Utf8Block([System.IO.BinaryReader]$Reader) {
    $length = $Reader.ReadInt32()
    if ($length -lt 0 -or $length -gt ($Reader.BaseStream.Length - $Reader.BaseStream.Position)) {
        throw "Invalid pack string length: $length"
    }
    [System.Text.Encoding]::UTF8.GetString($Reader.ReadBytes($length))
}

$config = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Config.lua')
$items = Read-Utf8 (Join-Path $Media 'scripts\GodSystem_Items.txt')
$storage = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Storage.lua')
$context = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageContext.lua')
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$workshop = Read-Utf8 (Join-Path $Root 'workshop.txt')
$localization = Read-Utf8 (Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml')
$cnItems = Read-Utf8 (Join-Path $Lua 'shared\Translate\CN\Items_CN.txt')
$chItems = Read-Utf8 (Join-Path $Lua 'shared\Translate\CH\Items_CH.txt')
$tileSource = Read-Utf8 (Join-Path $Media 'GodSystemStorageController.tiles.txt')
$buildScript = Read-Utf8 (Join-Path $Root 'tools\assets\storage-controller\Build-StorageControllerAssets.ps1')

$version = [regex]::Escape($ExpectedVersion)
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $version + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo ('(?m)^modversion=' + $version + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $version + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $workshop ('(?m)^description=v' + $version + '\r?$') "Workshop version must be $ExpectedVersion"

foreach ($info in @($rootInfo, $b42Info)) {
    Require-Text $info '(?m)^pack=GodSystemStorageController\r?$' 'Custom controller texture pack is not registered'
    Require-Text $info '(?m)^tiledef=GodSystemStorageController 9169\r?$' 'Custom controller tile definition is not registered'
}

Require-Text $items 'item\s+StorageController[\s\S]{0,500}ItemType\s*=\s*base:moveable' 'Controller must use the native Moveable lifecycle'
Require-Text $items 'item\s+StorageController[\s\S]{0,500}WorldObjectSprite\s*=\s*GodSystem_StorageController_0' 'Controller must use its own world sprite'
Reject-Text $items 'item\s+StorageController[\s\S]{0,500}WorldStaticModel\s*=' 'Static ground-item controller route must stay retired'
Reject-Text $items 'item\s+StorageController[\s\S]{0,500}recreational_01_16' 'Dr Oids arcade sprite must not return'
Require-Text $storage 'MovableDataKey\s*=\s*"movableData"' 'Moveable identity persistence is missing'
Require-Text $storage 'function\s+Storage\.isController' 'Controller identity detection is missing'

Require-Text $tileSource '(?m)^\s*CustomItem\s*=\s*GodSystem\.StorageController\s*$' 'Tile must return the GodSystem controller item'
Require-Text $tileSource '(?m)^\s*IsMoveAble\s*=\s*$' 'Tile is not registered as Moveable'
Require-Text $tileSource '(?m)^\s*MoveType\s*=\s*Object\s*$' 'Tile must use the standard Object move type'
Reject-Text $tileSource '(?m)^\s*(solid|solidtrans)\s*=' 'Controller tile must not add player collision'

Require-Text $context 'Context\.markerCount\s*=\s*Context\.markerCount\s+or\s+0' 'Cached marker count is missing'
Require-Text $context 'Context\.markerCount\s*=\s*0' 'Marker reset must clear the cached count'
Require-Text $context 'Context\.markerCount\s*=\s*Context\.markerCount\s*\+\s*1' 'Marker cache must update its count outside rendering'
Require-Text $context 'Context\.markerCount\s*<=\s*0' 'Per-frame renderer must use the cached marker count'
Reject-Text $context '\bnext\s*\(\s*Context\.markers' 'Kahlua-incompatible next(Context.markers) call must not return'
Reject-Text $context 'setHighlighted\(true\)|setHighlightColor\(' 'Connection mode must not blink or recolor world objects'

Require-Text $localization '(?m)^Tooltip_GodSystem_StorageController:' 'Controller tooltip source is missing'
Require-Text $cnItems 'Tooltip_GodSystem_StorageController' 'CN controller tooltip was not regenerated'
Require-Text $chItems 'Tooltip_GodSystem_StorageController' 'CH controller tooltip was not regenerated'

$tilePngPath = Join-Path $Root 'tools\assets\storage-controller\GodSystem_StorageController.png'
$alphaSourcePath = Join-Path $Root 'tools\assets\storage-controller\GodSystem_StorageController_alpha.png'
$generatedSourcePath = Join-Path $Root 'tools\assets\storage-controller\GodSystem_StorageController_source.png'
foreach ($path in @($tilePngPath, $alphaSourcePath, $generatedSourcePath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Controller art source is missing: $path" }
    if ((Get-Item -LiteralPath $path).Length -le 256) { throw "Controller art is empty: $path" }
}
Require-Text $buildScript 'NearestNeighbor' 'Controller art builder must preserve pixel edges'
Require-Text $buildScript '"PZPK"' 'Controller art builder must emit the B42 pack header'
Require-Text $buildScript '"tdef"' 'Controller art builder must emit a tile definition'

Add-Type -AssemblyName System.Drawing
$image = [System.Drawing.Bitmap]::FromFile($tilePngPath)
try {
    Require-Equal $image.Width 128 'Controller tile width is invalid'
    Require-Equal $image.Height 256 'Controller tile height is invalid'
    if (-not [System.Drawing.Image]::IsAlphaPixelFormat($image.PixelFormat)) {
        throw 'Controller tile must use RGBA/ARGB transparency'
    }
}
finally {
    $image.Dispose()
}

$packPath = Join-Path $Media 'texturepacks\GodSystemStorageController.pack'
$packBytes = [System.IO.File]::ReadAllBytes($packPath)
$packReader = New-Object System.IO.BinaryReader (
    New-Object System.IO.MemoryStream (,$packBytes)
)
try {
    Require-Equal ([System.Text.Encoding]::ASCII.GetString($packReader.ReadBytes(4))) 'PZPK' 'B42 pack magic is invalid'
    Require-Equal $packReader.ReadInt32() 1 'B42 pack version is invalid'
    Require-Equal $packReader.ReadInt32() 1 'B42 pack must contain one page'
    if ([string]::IsNullOrWhiteSpace((Read-Utf8Block $packReader))) { throw 'B42 pack page name is empty' }
    Require-Equal $packReader.ReadInt32() 1 'B42 pack must contain one sprite entry'
    Require-Equal $packReader.ReadInt32() 1 'B42 pack alpha mask is invalid'
    Require-Equal (Read-Utf8Block $packReader) 'GodSystem_StorageController_0' 'B42 pack sprite name does not match the item'
    foreach ($expected in @(0, 0, 128, 256, 0, 0, 128, 256)) {
        Require-Equal $packReader.ReadInt32() $expected 'B42 pack sprite geometry is invalid'
    }
    $pngSignature = $packReader.ReadBytes(8)
    Require-Equal (($pngSignature | ForEach-Object { $_.ToString('X2') }) -join '') '89504E470D0A1A0A' 'B42 pack does not contain a PNG page'
}
finally {
    $packReader.Dispose()
}
Require-Equal (($packBytes[($packBytes.Length - 4)..($packBytes.Length - 1)] | ForEach-Object { $_.ToString('X2') }) -join '') 'EFBEADDE' 'B42 pack terminator is invalid'

$tileDefinitionPath = Join-Path $Media 'GodSystemStorageController.tiles'
$tileBytes = [System.IO.File]::ReadAllBytes($tileDefinitionPath)
$tileReader = New-Object System.IO.BinaryReader (
    New-Object System.IO.MemoryStream (,$tileBytes)
)
try {
    Require-Equal ([System.Text.Encoding]::ASCII.GetString($tileReader.ReadBytes(4))) 'tdef' 'Tile definition magic is invalid'
    Require-Equal $tileReader.ReadInt32() 1 'Tile definition version is invalid'
    Require-Equal $tileReader.ReadInt32() 1 'Tile definition must contain one tileset'
    Require-Equal (Read-AsciiLine $tileReader) 'GodSystem_StorageController' 'Tileset name is invalid'
    Require-Equal (Read-AsciiLine $tileReader) 'GodSystem_StorageController.png' 'Tileset source name is invalid'
    foreach ($expected in @(1, 1, 1, 1)) {
        Require-Equal $tileReader.ReadInt32() $expected 'Tileset dimensions or tile count are invalid'
    }
    $propertyCount = $tileReader.ReadInt32()
    $properties = @{}
    for ($i = 0; $i -lt $propertyCount; $i++) {
        $propertyName = Read-AsciiLine $tileReader
        $propertyValue = Read-AsciiLine $tileReader
        $properties[$propertyName] = $propertyValue
    }
    Require-Equal $properties['CustomItem'] 'GodSystem.StorageController' 'Binary tile CustomItem is invalid'
    Require-Equal $properties['MoveType'] 'Object' 'Binary tile MoveType is invalid'
    if (-not $properties.ContainsKey('IsMoveAble')) { throw 'Binary tile IsMoveAble property is missing' }
}
finally {
    $tileReader.Dispose()
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for v1.16.69 storage validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV11669Runtime.lua') $Lua
if ($LASTEXITCODE -ne 0) { throw 'v1.16.69 runtime test failed' }

Write-Output 'Test-GodSystemV11669 passed'
