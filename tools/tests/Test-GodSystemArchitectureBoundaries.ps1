param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
if (-not (Test-Path -LiteralPath $luaRoot)) {
    throw "GodSystem Lua root not found: $luaRoot"
}

$violations = New-Object 'System.Collections.Generic.List[string]'
$modules = @()
$moduleByName = @{}
$requirePattern = '\brequire\s*(?:\(\s*)?["'']([^"'']+)["'']'
$legacyEntryPattern = '\brequire\s*(?:\(\s*)?["''](GodSystem_Core|GodSystem_Server|GodSystem_UI)["'']'
$eventGatewayPattern = '\bEvents\s*(?:\.[A-Za-z_][A-Za-z0-9_]*|\[[^\]\r\n]+\])\s*\.\s*(?:Add|Remove)\s*\('
$commandGatewayPattern = '\b(?:sendClientCommand|sendServerCommand)\s*\(|\b(?:OnClientCommand|OnServerCommand)\b'
$coreBusinessPattern = '(?i)(Shop|Bank|Task|Recycle|Storage|Companion|AutoLoader|VehicleRepair|Teleport|Lottery|Terminal|MedicalService|CarryCapacity)'

function Get-RelativePath([string]$basePath, [string]$fullPath) {
    $prefix = $basePath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside base path: $fullPath"
    }
    return $fullPath.Substring($prefix.Length)
}

function Remove-LuaComments([string]$text) {
    $withoutBlocks = [regex]::Replace($text, '--\[\[.*?\]\]', '', [Text.RegularExpressions.RegexOptions]::Singleline)
    return [regex]::Replace($withoutBlocks, '--[^\r\n]*', '')
}

function Get-Layer([string]$moduleName) {
    if ($moduleName -eq 'GodSystem/Bootstrap' -or $moduleName -eq 'GodSystem/Composition') {
        return 'Bootstrap'
    }
    $parts = $moduleName -split '/'
    if ($parts.Length -lt 3 -or $parts[0] -ne 'GodSystem') {
        return 'Unknown'
    }
    switch ($parts[1]) {
        'Core' { return 'Core' }
        'Platform' { return 'Platform' }
        'State' { return 'State' }
        'Services' { return 'Services' }
        'Features' { return 'Features' }
        'UI' { return 'UI' }
        'Runtime' { return 'Bootstrap' }
        default { return 'Unknown' }
    }
}

function Get-FeatureName([string]$moduleName) {
    $parts = $moduleName -split '/'
    if ($parts.Length -ge 3 -and $parts[0] -eq 'GodSystem' -and $parts[1] -eq 'Features') {
        return $parts[2]
    }
    return ''
}

foreach ($scope in @('shared', 'client', 'server')) {
    $scopeRoot = Join-Path $luaRoot $scope
    if (-not (Test-Path -LiteralPath $scopeRoot)) {
        continue
    }
    $strictRoot = Join-Path $scopeRoot 'GodSystem'
    if (-not (Test-Path -LiteralPath $strictRoot)) {
        continue
    }
    foreach ($file in Get-ChildItem -LiteralPath $strictRoot -Recurse -Filter '*.lua' -File) {
        $relativeToScope = Get-RelativePath $scopeRoot $file.FullName
        $moduleName = (($relativeToScope -replace '\.lua$', '') -replace '\\', '/')
        $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
        $code = Remove-LuaComments $text
        $dependencies = New-Object 'System.Collections.Generic.List[string]'
        foreach ($match in [regex]::Matches($text, $requirePattern)) {
            $dependency = $match.Groups[1].Value
            if (-not $dependencies.Contains($dependency)) {
                $dependencies.Add($dependency)
            }
        }
        $row = [pscustomobject]@{
            Name = $moduleName
            Layer = Get-Layer $moduleName
            Feature = Get-FeatureName $moduleName
            Scope = $scope
            RelativePath = ($scope + '\' + $relativeToScope)
            FullPath = $file.FullName
            Code = $code
            Dependencies = $dependencies.ToArray()
        }
        if ($moduleByName.ContainsKey($moduleName)) {
            $violations.Add("Duplicate architecture module '$moduleName': $($moduleByName[$moduleName].RelativePath), $($row.RelativePath)")
        } else {
            $moduleByName[$moduleName] = $row
        }
        $modules += $row
    }
}

if ($modules.Count -eq 0) {
    throw 'No Lua modules found under the strict GodSystem architecture directory'
}

$modules = @($modules | Sort-Object Name)

foreach ($module in $modules) {
    if ($module.Layer -eq 'Unknown') {
        $violations.Add("Unknown architecture layer: $($module.RelativePath)")
    }

    if ([regex]::IsMatch($module.Code, $legacyEntryPattern)) {
        $violations.Add("Architecture module requires a legacy Core/Server/UI entry point: $($module.RelativePath)")
    }

    if ($module.Layer -eq 'Core' -and [regex]::IsMatch($module.Code, $coreBusinessPattern)) {
        $violations.Add("Core contains a feature business term: $($module.RelativePath)")
    }

    if ($module.Layer -notin @('Platform', 'Bootstrap')) {
        if ([regex]::IsMatch($module.Code, $eventGatewayPattern)) {
            $violations.Add("Direct Events registration is only allowed in Platform/Bootstrap: $($module.RelativePath)")
        }
        if ([regex]::IsMatch($module.Code, $commandGatewayPattern)) {
            $violations.Add("Raw command gateway access is only allowed in Platform/Bootstrap: $($module.RelativePath)")
        }
    }

    foreach ($dependency in $module.Dependencies) {
        if (-not $dependency.StartsWith('GodSystem/', [StringComparison]::Ordinal)) {
            continue
        }
        if (-not $moduleByName.ContainsKey($dependency)) {
            $violations.Add("Unresolved architecture dependency '$dependency' required by $($module.RelativePath)")
            continue
        }

        $target = $moduleByName[$dependency]
        $allowed = $false
        switch ($module.Layer) {
            'Bootstrap' {
                $allowed = $true
            }
            'Core' {
                $allowed = $target.Layer -eq 'Core'
            }
            'Platform' {
                $allowed = $target.Layer -in @('Core', 'Platform')
            }
            'State' {
                $allowed = $target.Layer -in @('Core', 'State')
            }
            'Services' {
                $allowed = $target.Layer -in @('Core', 'State', 'Services')
            }
            'Features' {
                $allowed = $target.Layer -in @('Core', 'Services') -or
                    ($target.Layer -eq 'Features' -and $module.Feature -ne '' -and $module.Feature -eq $target.Feature)
            }
            'UI' {
                $allowed = $target.Layer -in @('Core', 'Services', 'UI')
            }
        }
        if (-not $allowed) {
            $violations.Add("Forbidden layer dependency: $($module.Name) [$($module.Layer)] -> $($target.Name) [$($target.Layer)]")
        }
        if ($module.Layer -eq 'Features' -and $target.Layer -eq 'Features' -and $module.Feature -ne $target.Feature) {
            $violations.Add("Feature '$($module.Feature)' requires another feature implementation '$($target.Feature)': $($module.RelativePath)")
        }
    }
}

$visitState = @{}
$visitStack = New-Object 'System.Collections.Generic.List[string]'

function Visit-ArchitectureModule([string]$moduleName) {
    $state = $visitState[$moduleName]
    if ($state -eq 2) {
        return
    }
    if ($state -eq 1) {
        $start = $visitStack.IndexOf($moduleName)
        $cycle = @()
        if ($start -ge 0) {
            for ($i = $start; $i -lt $visitStack.Count; $i++) {
                $cycle += $visitStack[$i]
            }
        }
        $cycle += $moduleName
        $violations.Add('Architecture dependency cycle: ' + ($cycle -join ' -> '))
        return
    }

    $visitState[$moduleName] = 1
    $visitStack.Add($moduleName)
    $module = $moduleByName[$moduleName]
    foreach ($dependency in $module.Dependencies) {
        if ($dependency.StartsWith('GodSystem/', [StringComparison]::Ordinal) -and $moduleByName.ContainsKey($dependency)) {
            Visit-ArchitectureModule $dependency
        }
    }
    $visitStack.RemoveAt($visitStack.Count - 1)
    $visitState[$moduleName] = 2
}

foreach ($module in $modules) {
    Visit-ArchitectureModule $module.Name
}

Write-Output 'GodSystem architecture dependency manifest'
foreach ($module in $modules) {
    $architectureDependencies = @($module.Dependencies | Where-Object { $_.StartsWith('GodSystem/', [StringComparison]::Ordinal) })
    $dependencyText = if ($architectureDependencies.Count -gt 0) { $architectureDependencies -join ', ' } else { '(none)' }
    Write-Output ("  {0} [{1}/{2}] -> {3}" -f $module.Name, $module.Scope, $module.Layer, $dependencyText)
}

$strictPaths = @{}
foreach ($module in $modules) {
    $strictPaths[$module.FullPath.ToLowerInvariant()] = $true
}
$legacyFiles = @(
    Get-ChildItem -LiteralPath $luaRoot -Recurse -Filter '*.lua' -File |
        Where-Object { -not $strictPaths.ContainsKey($_.FullName.ToLowerInvariant()) }
)
$legacyBoundaryDebt = @()
foreach ($file in $legacyFiles) {
    $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    $code = Remove-LuaComments $text
    $reasons = @()
    if ([regex]::IsMatch($code, $eventGatewayPattern)) { $reasons += 'direct Events registration' }
    if ([regex]::IsMatch($code, $commandGatewayPattern)) { $reasons += 'raw command gateway' }
    if ([regex]::IsMatch($code, $legacyEntryPattern)) { $reasons += 'legacy Core/Server/UI require' }
    if ($reasons.Count -gt 0) {
        $legacyBoundaryDebt += [pscustomobject]@{
            RelativePath = Get-RelativePath $luaRoot $file.FullName
            Reasons = $reasons -join ', '
        }
    }
}

Write-Output ("Legacy migration debt (non-failing): {0} Lua files remain outside the strict GodSystem directory." -f $legacyFiles.Count)
foreach ($row in $legacyBoundaryDebt | Sort-Object RelativePath) {
    Write-Output ("  debt: {0} [{1}]" -f $row.RelativePath, $row.Reasons)
}

if ($violations.Count -gt 0) {
    $message = "GodSystem architecture boundary validation failed:`n - " + ($violations -join "`n - ")
    throw $message
}

Write-Output ("Test-GodSystemArchitectureBoundaries passed ({0} strict modules, no dependency cycles)" -f $modules.Count)
