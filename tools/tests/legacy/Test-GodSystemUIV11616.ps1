param(
    [string]$Root = "C:\Users\Admin\Zomboid\Workshop\GodSystem"
)

$ErrorActionPreference = "Stop"
$client = Join-Path $Root "Contents\mods\GodSystem\42\media\lua\client"
$shared = Join-Path $Root "Contents\mods\GodSystem\42\media\lua\shared"
$ui = Join-Path $client "GodSystem_UI.lua"
$theme = Join-Path $client "GodSystem_UITheme.lua"
$config = Join-Path $shared "GodSystem_Config.lua"

foreach($path in @($ui,$theme,$config)){
    if(-not (Test-Path -LiteralPath $path)){
        throw "Missing required file: $path"
    }
}

$utf8 = [System.Text.Encoding]::UTF8
$uiText = [System.IO.File]::ReadAllText($ui, $utf8)
$themeText = [System.IO.File]::ReadAllText($theme, $utf8)
$configText = [System.IO.File]::ReadAllText($config, $utf8)

function Get-NumberToken {
    param(
        [string]$Text,
        [string]$Name,
        [int]$Default
    )
    $match = [regex]::Match($Text, ('(?m)\b' + [regex]::Escape($Name) + '\s*=\s*(\d+)'))
    if ($match.Success) {
        return [int]$match.Groups[1].Value
    }
    return $Default
}

$contentY = Get-NumberToken -Text $themeText -Name "y" -Default 100
$contentMatch = [regex]::Match($themeText, 'content\s*=\s*\{\s*x\s*=\s*\d+,\s*y\s*=\s*(\d+)')
if ($contentMatch.Success) {
    $contentY = [int]$contentMatch.Groups[1].Value
}
$titleBarH = Get-NumberToken -Text $themeText -Name "titleBarHeight" -Default 36
$taskHeaderGap = Get-NumberToken -Text $themeText -Name "taskHeaderGap" -Default 0
$taskHeaderHeight = Get-NumberToken -Text $themeText -Name "taskHeaderHeight" -Default 0
$listY = Get-NumberToken -Text $themeText -Name "listY" -Default 142
$titleBarBottom = $contentY + 4 + $titleBarH
$taskHeaderY = $listY - $taskHeaderHeight - $taskHeaderGap
$taskHeaderClear = ($taskHeaderHeight -gt 0) -and ($taskHeaderGap -gt 0) -and ($taskHeaderY -ge ($titleBarBottom + 2)) -and ($listY -ge ($taskHeaderY + $taskHeaderHeight + $taskHeaderGap))

$checks = @(
    @{ Name = "version config"; Ok = $configText -match 'GodSystemConfig\.Version\s*=\s*"\d+\.\d+\.\d+"' },
    @{ Name = "fixed width"; Ok = $themeText -match 'fixedWidth\s*=\s*1240' },
    @{ Name = "fixed height"; Ok = $themeText -match 'fixedHeight\s*=\s*690' },
    @{ Name = "top bar theme"; Ok = $themeText -match 'topBar\s*=' },
    @{ Name = "nav item height"; Ok = $themeText -match 'navItemHeight\s*=\s*56' },
    @{ Name = "window not resizable"; Ok = $uiText -match 'o\.resizable\s*=\s*false' },
    @{ Name = "fixed toggle size"; Ok = $uiText -match 'fixedWidth' -and $uiText -notmatch 'data\.ui\.windowW' },
    @{ Name = "hud renderer"; Ok = $uiText -match 'function GodSystemWindow:drawTopStatusBar' },
    @{ Name = "framed panel renderer"; Ok = $uiText -match 'function GodSystemWindow:drawFramePanel' },
    @{ Name = "progress renderer"; Ok = $uiText -match 'function GodSystemWindow:drawProgressBar' },
    @{ Name = "task header clears title"; Ok = $taskHeaderClear },
    @{ Name = "task header uses theme gap"; Ok = $uiText -match 'taskHeaderGap' -and $uiText -notmatch 'self\.mainY\s*-\s*28' }
)

$failed = @()
foreach($check in $checks){
    if(-not $check.Ok){
        $failed += $check.Name
    }
}

if($failed.Count -gt 0){
    throw ("UIV11616CheckFailed: " + ($failed -join ", "))
}

Write-Output "UIV11616CheckOK"
