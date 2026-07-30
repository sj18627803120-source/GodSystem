param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [string]$ExpectedVersion = "42.20.1.1",
    [string]$ExpectedWorkshopId = "3773949382"
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path $Root).Path

Write-Output "=== Test-GodSystemV422011: B42.20 Texture Fix Verification ==="

$Mod = Join-Path $RepoRoot 'Contents\mods\GodSystem'
$Lua = Join-Path $Mod '42\media\lua'
$Textures = Join-Path $Mod '42\media\textures'
$TextureFile = Join-Path $Textures 'GodSystem_WhitePixel.png'

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}
function Require-File([string]$Path, [string]$Message) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Message : $Path" }
    Write-Output "  OK: $Message"
}
function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw "$Message" }
    Write-Output "  OK: $Message"
}
function Reject-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw "$Message" }
    Write-Output "  OK: $Message"
}

# === 1. Texture file validation ===
Write-Output "[1] Texture file validation"

Require-File $TextureFile "GodSystem_WhitePixel.png exists in Git/packaging directory"

$pngBytes = [System.IO.File]::ReadAllBytes($TextureFile)
$sig = $pngBytes[0..7] | ForEach-Object { $_.ToString('X2') }
$sigStr = $sig -join ' '
if ($sigStr -ne '89 50 4E 47 0D 0A 1A 0A') {
    throw "Invalid PNG signature: $sigStr"
}
Write-Output "  OK: PNG signature valid"

# Check dimensions from IHDR (bytes 16-23, big-endian)
$width = ($pngBytes[16] -shl 24) -bor ($pngBytes[17] -shl 16) -bor ($pngBytes[18] -shl 8) -bor $pngBytes[19]
$height = ($pngBytes[20] -shl 24) -bor ($pngBytes[21] -shl 16) -bor ($pngBytes[22] -shl 8) -bor $pngBytes[23]
if ($width -ne 1 -or $height -ne 1) {
    throw "Texture must be 1x1, got ${width}x${height}"
}
Write-Output "  OK: Dimensions 1x1"

# Color type (byte 25 of file, byte 9 of IHDR data)
$colorType = $pngBytes[25]
if ($colorType -ne 6) {
    throw "Color type must be 6 (RGBA), got $colorType"
}
Write-Output "  OK: Color type RGBA (6)"

# Verify pixel white using System.Drawing
Add-Type -AssemblyName System.Drawing
$png = [System.Drawing.Image]::FromFile($TextureFile)
$bmp = New-Object System.Drawing.Bitmap($png)
$p = $bmp.GetPixel(0, 0)
$bmp.Dispose()
$png.Dispose()
if ($p.R -ne 255 -or $p.G -ne 255 -or $p.B -ne 255 -or $p.A -ne 255) {
    throw "Pixel must be pure white (255,255,255,255), got ($($p.R),$($p.G),$($p.B),$($p.A))"
}
Write-Output "  OK: Pixel is opaque pure white (255,255,255,255)"

# === 2. Unified resource path ===
Write-Output "[2] Unified resource path validation"

$companionVisual = Read-Utf8 (Join-Path $Lua 'client\GodSystem_CompanionVisual.lua')
$storageContext = Read-Utf8 (Join-Path $Lua 'client\GodSystem_StorageContext.lua')

$visualPath = [regex]::Match($companionVisual, 'getTexture\("([^"]+)"\)').Groups[1].Value
$contextPath = [regex]::Match($storageContext, 'getTexture\("([^"]+)"\)').Groups[1].Value

if ($visualPath -ne 'media/textures/GodSystem_WhitePixel.png') {
    throw "CompanionVisual uses: $visualPath, expected: media/textures/GodSystem_WhitePixel.png"
}
Write-Output "  OK: CompanionVisual uses $visualPath"

if ($contextPath -ne 'media/textures/GodSystem_WhitePixel.png') {
    throw "StorageContext uses: $contextPath, expected: media/textures/GodSystem_WhitePixel.png"
}
Write-Output "  OK: StorageContext uses $contextPath"

if ($visualPath -ne $contextPath) {
    throw "Texture paths differ: $visualPath vs $contextPath"
}
Write-Output "  OK: Both modules use identical texture path"

# === 3. Old path cleanup ===
Write-Output "[3] Old path cleanup validation"

$luaFiles = Get-ChildItem -LiteralPath $Lua -Recurse -Filter '*.lua' -File
$maskWhiteRefs = @()
foreach ($f in $luaFiles) {
    $content = Read-Utf8 $f.FullName
    if ($content -match 'mask_white\.png') {
        $maskWhiteRefs += $f.FullName
    }
}
if ($maskWhiteRefs.Count -gt 0) {
    throw "mask_white.png still referenced in: $($maskWhiteRefs -join ', ')"
}
Write-Output "  OK: No mask_white.png references in any Lua file"

# === 4. Drawing logic preservation ===
Write-Output "[4] Drawing logic preservation validation"

$companionEvents = Read-Utf8 `
    (Join-Path $Lua 'shared\GodSystem\Platform\Companion\Events.lua')
$companionPzVisuals = Read-Utf8 `
    (Join-Path $Lua 'client\GodSystem\Platform\Companion\PZVisuals.lua')

Require-Text $companionEvents 'OnPreUIDraw' `
    "OnPreUIDraw must remain in the companion event adapter"
Require-Text $storageContext 'OnPreUIDraw' "OnPreUIDraw must remain in StorageContext"

Require-Text $storageContext 'renderer:renderline' "renderline must remain in StorageContext"
Require-Text $companionPzVisuals 'renderline' `
    "renderline must remain in the companion PZ visual adapter"

Require-Text $storageContext 'ISCoordConversion' "ISCoordConversion must remain in StorageContext"
Require-Text $companionPzVisuals 'ISCoordConversion' `
    "ISCoordConversion must remain in the companion PZ visual adapter"

# === 5. Version consistency ===
Write-Output "[5] Version consistency validation"

$version = [regex]::Escape($ExpectedVersion)
$rootInfo = Read-Utf8 (Join-Path $Mod 'mod.info')
$b42Info = Read-Utf8 (Join-Path $Mod '42\mod.info')
$config = Read-Utf8 (Join-Path $Lua 'shared\GodSystem_Config.lua')
$workshop = Read-Utf8 (Join-Path $RepoRoot 'workshop.txt')

Require-Text $rootInfo ('(?m)^modversion=' + $version + '\r?$') "Root mod.info version must be $ExpectedVersion"
Require-Text $b42Info ('(?m)^modversion=' + $version + '\r?$') "B42 mod.info version must be $ExpectedVersion"
Require-Text $config ('GodSystemConfig\.Version\s*=\s*"' + $version + '"') "Config version must be $ExpectedVersion"
Require-Text $rootInfo '(?m)^id=GodSystem_CN\r?$' "Root mod.info must keep Mod ID GodSystem_CN"
Require-Text $b42Info '(?m)^id=GodSystem_CN\r?$' "B42 mod.info must keep Mod ID GodSystem_CN"
Require-Text $workshop ('(?m)^id=' + [regex]::Escape($ExpectedWorkshopId) + '\r?$') "Workshop ID must be $ExpectedWorkshopId"
Require-Text ($rootInfo + $b42Info) 'Build 42\.20' "mod.info descriptions must target Build 42.20"

Write-Output "Test-GodSystemV422011: ALL TESTS PASSED"
