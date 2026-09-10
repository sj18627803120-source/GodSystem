[CmdletBinding()]
param(
    [string]$Root,
    [switch]$SkipLuaCompile,
    [switch]$RequireLuaCompiler
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "GodSystem verification failed: $Message" }
}

function Read-Utf8 {
    param([string]$Path)
    $decoder = [System.Text.UTF8Encoding]::new($false, $true)
    return $decoder.GetString([System.IO.File]::ReadAllBytes($Path))
}

function Get-SettingKeys {
    param([string]$SandboxPath)
    $text = Read-Utf8 $SandboxPath
    return @([regex]::Matches($text, '(?m)^option\s+GodSystem\.([A-Za-z0-9_]+)\s*$') |
        ForEach-Object { $_.Groups[1].Value })
}

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$modRoot = Join-Path $Root 'Contents\mods\GodSystem'
$luaRoot = Join-Path $modRoot '42\media\lua'
$sandboxPath = Join-Path $modRoot '42\media\sandbox-options.txt'
$configPath = Join-Path $luaRoot 'shared\GodSystem_Config.lua'
$generatorPath = Join-Path $Root 'tools\localization\generate_godsystem_v11645_localization.py'
$yamlPath = Join-Path $Root 'tools\localization\godsystem_v11645_localization.yml'
$itemScriptPath = Join-Path $modRoot '42\media\scripts\GodSystem_Items.txt'

foreach ($path in @($modRoot, $luaRoot, $sandboxPath, $configPath, $generatorPath, $yamlPath, $itemScriptPath)) {
    Assert-True (Test-Path -LiteralPath $path) "required path is missing: $path"
}

$configText = Read-Utf8 $configPath
$versionMatch = [regex]::Match($configText, 'GodSystemConfig\.Version\s*=\s*"([^"]+)"')
Assert-True $versionMatch.Success 'GodSystemConfig.Version is missing'
$version = $versionMatch.Groups[1].Value

foreach ($modInfoPath in @(
    (Join-Path $modRoot 'mod.info'),
    (Join-Path $modRoot '42\mod.info')
)) {
    $modInfo = Read-Utf8 $modInfoPath
    Assert-True ($modInfo -match "(?m)^modversion=$([regex]::Escape($version))$") "modversion mismatch in $modInfoPath"
}

$workshopText = Read-Utf8 (Join-Path $Root 'workshop.txt')
Assert-True ($workshopText -match "(?m)^description=v$([regex]::Escape($version))$") 'workshop version does not match GodSystemConfig.Version'

$settingKeys = Get-SettingKeys $sandboxPath
Assert-True ($settingKeys.Count -gt 0) 'no GodSystem sandbox options found'
Assert-True ($settingKeys.Count -eq @($settingKeys | Select-Object -Unique).Count) 'duplicate GodSystem sandbox option key'

$yamlText = Read-Utf8 $yamlPath
foreach ($key in $settingKeys) {
    $labelPattern = '(?m)^AdminSetting_' + [regex]::Escape($key) + ':\s*"'
    $tooltipPattern = '(?m)^AdminSetting_' + [regex]::Escape($key) + '_Desc:\s*"'
    Assert-True ($yamlText -match $labelPattern) "missing YAML label for sandbox option $key"
    Assert-True ($yamlText -match $tooltipPattern) "missing YAML tooltip for sandbox option $key"
}

$itemScriptText = Read-Utf8 $itemScriptPath
$requiredItemNames = @([regex]::Matches($itemScriptText, '(?m)^\s*item\s+([A-Za-z0-9_]+)\s*$') |
    ForEach-Object { 'GodSystem.' + $_.Groups[1].Value })
$requiredItemTooltips = @([regex]::Matches($itemScriptText, '(?m)^\s*Tooltip\s*=\s*(Tooltip_GodSystem_[A-Za-z0-9_]+),\s*$') |
    ForEach-Object { $_.Groups[1].Value })
Assert-True ($requiredItemNames.Count -gt 0) 'no GodSystem item definitions found'

foreach ($locale in @('CN', 'CH')) {
    $uiJsonPath = Join-Path $luaRoot "shared\Translate\$locale\IG_UI.json"
    # IGUI keys are case-sensitive (legacy CoreClaimed/coreClaimed coexist).
    # Windows PowerShell's PSCustomObject JSON converter rejects that pair.
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('AsHashtable')) {
        $uiJson = (Read-Utf8 $uiJsonPath | ConvertFrom-Json -AsHashtable)
    } else {
        Add-Type -AssemblyName System.Web.Extensions
        $uiParser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $uiJson = $uiParser.DeserializeObject((Read-Utf8 $uiJsonPath))
    }
    $uiLegacyPath = Join-Path $luaRoot "shared\Translate\$locale\IG_UI_$locale.txt"
    $uiLegacy = [regex]::Matches((Read-Utf8 $uiLegacyPath), '(?m)^\s*(IGUI_GodSystem_[A-Za-z0-9_]+)\s*=\s*"(.*)",\s*$')
    Assert-True ($uiLegacy.Count -gt 0) "$locale IGUI legacy dictionary is empty"
    foreach ($entry in $uiLegacy) {
        $entryKey = $entry.Groups[1].Value
        $entryValue = $entry.Groups[2].Value.Replace('\"', '"').Replace('\\', '\')
        Assert-True ($uiJson.ContainsKey($entryKey) -and $uiJson[$entryKey] -ceq $entryValue) "$locale IGUI JSON/legacy mismatch: $entryKey"
    }
    $translationPath = Join-Path $luaRoot "shared\Translate\$locale\Sandbox.json"
    $translation = (Read-Utf8 $translationPath | ConvertFrom-Json)
    Assert-True ($null -ne $translation.PSObject.Properties['Sandbox_GodSystem']) "$locale sandbox page title is missing"
    foreach ($key in $settingKeys) {
        $labelKey = "Sandbox_GodSystem_$key"
        $tooltipKey = "${labelKey}_tooltip"
        $label = $translation.PSObject.Properties[$labelKey].Value
        $tooltip = $translation.PSObject.Properties[$tooltipKey].Value
        Assert-True (-not [string]::IsNullOrWhiteSpace($label)) "$locale sandbox label is missing: $labelKey"
        Assert-True (-not [string]::IsNullOrWhiteSpace($tooltip)) "$locale sandbox tooltip is missing: $tooltipKey"
        Assert-True ($label -notmatch '^\[') "$locale sandbox label still has a duplicated category prefix: $labelKey"
        # Static sandbox text has no formatting arguments. Literal percent
        # signs must be escaped for the game's Java Formatter (%%).
        Assert-True (-not $label.Replace('%%', '').Contains('%')) "$locale sandbox label has an unescaped percent sign: $labelKey"
        Assert-True (-not $tooltip.Replace('%%', '').Contains('%')) "$locale sandbox tooltip has an unescaped percent sign: $tooltipKey"
    }

    $itemNameJson = (Read-Utf8 (Join-Path $luaRoot "shared\Translate\$locale\ItemName.json") | ConvertFrom-Json)
    foreach ($itemName in $requiredItemNames) {
        $property = $itemNameJson.PSObject.Properties[$itemName]
        Assert-True ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) "$locale item name is missing: $itemName"
    }
    $tooltipJson = (Read-Utf8 (Join-Path $luaRoot "shared\Translate\$locale\Tooltip.json") | ConvertFrom-Json)
    foreach ($tooltipName in $requiredItemTooltips) {
        $property = $tooltipJson.PSObject.Properties[$tooltipName]
        Assert-True ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) "$locale item tooltip is missing: $tooltipName"
    }
}

$generatorText = Read-Utf8 $generatorPath
Assert-True ($generatorText -notmatch 'GodSystem_AdminConfig') 'localization generator still depends on retired GodSystem_AdminConfig'
Assert-True ($generatorText -match 'def parse_sandbox_options') 'localization generator does not parse the current sandbox schema'
Assert-True ($generatorText -notmatch 'SANDBOX_OPTIONS_PATH\.write_text') 'localization generator must not rewrite sandbox-options.txt'

$runtimeModules = @{
    'client/GodSystem_Core.lua' = @(
        'GodSystem_ClientRuntime_Foundation',
        'GodSystem_ClientRuntime_BankGrowth',
        'GodSystem_ClientRuntime_MedicalTraits',
        'GodSystem_ClientRuntime_Economy',
        'GodSystem_ClientRuntime_Home',
        'GodSystem_ClientRuntime_Recycle',
        'GodSystem_ClientRuntime_Tasks'
    )
    'server/GodSystem_Server.lua' = @(
        'GodSystem_ServerRuntime_Foundation',
        'GodSystem_ServerRuntime_Bank',
        'GodSystem_ServerRuntime_EconomyTasks',
        'GodSystem_ServerRuntime_RouterConfig',
        'GodSystem_ServerRuntime_Commerce',
        'GodSystem_ServerRuntime_Lottery',
        'GodSystem_ServerRuntime_Services',
        'GodSystem_ServerRuntime_HomeGrowth',
        'GodSystem_ServerRangeRecycle',
        'GodSystem_ServerRuntime_Background'
        'GodSystem_ServerRuntime_Equipment'
    )
    'client/GodSystem_UI.lua' = @(
        'GodSystem_UI_Runtime_Components',
        'GodSystem_UI_Runtime_Window',
        'GodSystem_UI_Runtime_Lists',
        'GodSystem_UI_Runtime_Pages',
        'GodSystem_UI_Runtime_Details',
        'GodSystem_UI_Runtime_Dialogs',
        'GodSystem_UI_Runtime_Actions',
        'GodSystem_UI_Runtime_Lifecycle'
    )
}
foreach ($relativePath in $runtimeModules.Keys) {
    $bootstrapText = Read-Utf8 (Join-Path $luaRoot $relativePath)
    foreach ($module in $runtimeModules[$relativePath]) {
        Assert-True ($bootstrapText -match "require `"$([regex]::Escape($module))`"") "$relativePath does not load $module"
        Assert-True ($bootstrapText -match "Installers\[`"$([regex]::Escape($module))`"\]") "$relativePath does not install $module"
    }
}

$luaFiles = @(Get-ChildItem -LiteralPath $luaRoot -Recurse -Filter '*.lua' | Sort-Object FullName)
Assert-True ($luaFiles.Count -gt 0) 'no Lua files found'
$availableModules = @{}
foreach ($file in $luaFiles) {
    $availableModules[$file.BaseName] = $true
    $text = Read-Utf8 $file.FullName
    Assert-True ($text.IndexOf([char]0xFFFD) -lt 0) "UTF-8 replacement character found in $($file.FullName)"
}
foreach ($file in $luaFiles) {
    $text = Read-Utf8 $file.FullName
    foreach ($match in [regex]::Matches($text, 'require\s+"(GodSystem_[A-Za-z0-9_]+)"')) {
        $required = $match.Groups[1].Value
        Assert-True $availableModules.ContainsKey($required) "$($file.Name) requires missing local module $required"
    }
}

if (-not $SkipLuaCompile) {
    $luaCompiler = (Get-Command luac -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
    if (-not $luaCompiler -and (Test-Path -LiteralPath 'C:\Users\Admin\Tools\Lua51\luac.exe')) {
        $luaCompiler = 'C:\Users\Admin\Tools\Lua51\luac.exe'
    }
    if ($luaCompiler) {
        foreach ($file in $luaFiles) {
            & $luaCompiler -p $file.FullName
            Assert-True ($LASTEXITCODE -eq 0) "Lua 5.1 compilation failed: $($file.FullName)"
        }
    } elseif ($RequireLuaCompiler) {
        throw 'GodSystem verification failed: Lua compiler required but not available'
    } else {
        Write-Warning 'Lua compiler not available; skipped Lua 5.1 compilation. Re-run with -RequireLuaCompiler on the game-test machine.'
    }
}

Write-Host "GodSystem static verification passed: version=$version, sandboxOptions=$($settingKeys.Count), luaFiles=$($luaFiles.Count)"
