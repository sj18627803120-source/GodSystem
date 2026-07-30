param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$Lua = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$files = @(
    (Join-Path $Lua 'shared\GodSystem\Features\Terminal\Rules.lua'),
    (Join-Path $Lua 'shared\GodSystem\Features\Terminal\Module.lua'),
    (Join-Path $Lua 'shared\GodSystem\Features\Storage\Rules.lua'),
    (Join-Path $Lua 'shared\GodSystem\Features\Storage\Module.lua'),
    (Join-Path $PSScriptRoot 'Test-GodSystemV422012TerminalStorageModuleRuntime.lua')
)
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "Missing terminal/storage module file: $file"
    }
}

function Read-Utf8([string]$Path) {
    [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false))
}

$terminalRules = Read-Utf8 $files[0]
$terminalModule = Read-Utf8 $files[1]
$storageRules = Read-Utf8 $files[2]
$storageModule = Read-Utf8 $files[3]

foreach ($text in @($terminalRules, $terminalModule, $storageRules, $storageModule)) {
    if ($text -match 'require\s+["''](?:GodSystem_(?:Core|Server|UI|Storage|StorageManager|TerminalUpgrades|TerminalRelief))["'']') {
        throw 'Strict terminal/storage module requires a legacy implementation'
    }
    if ([regex]::IsMatch($text, '\b(?:Events|sendClientCommand|sendServerCommand|getCell|getWorld|getGameTime)\b')) {
        throw 'Terminal/storage feature directly accesses a raw PZ runtime boundary'
    }
}

foreach ($marker in @(
    'Descriptor.id = "feature.terminal"',
    '"terminal.config"',
    '"terminal.state"',
    '"terminal.instances"',
    '"wallet"',
    '"operations"',
    'upgradeCapacity = true',
    'upgradeReduction = true',
    'upgradeRelief = true'
)) {
    if (-not $terminalModule.Contains($marker)) {
        throw "Terminal contract marker missing: $marker"
    }
}

foreach ($marker in @(
    '{ level = 1, value = 10, upgradeCost = 0 }',
    '{ level = 8, value = 49, upgradeCost = 1100 }',
    '{ level = 1, value = 50, upgradeCost = 0 }',
    '{ level = 8, value = 99, upgradeCost = 2500 }',
    'Rules.reliefPerLevel = 5',
    'Rules.reliefMaxOffset = 2000',
    'Rules.reliefUpgradeCost = 2000',
    'reliefActualWeight = -Rules.value'
)) {
    if (-not $terminalRules.Contains($marker)) {
        throw "Published terminal rule marker missing: $marker"
    }
}
if ([regex]::IsMatch($terminalRules + $terminalModule, '(?i)\bcompress(?:ion|ed|or)?\b')) {
    throw 'Retired terminal compression logic returned in strict module'
}

foreach ($marker in @(
    'Descriptor.id = "feature.storage"',
    '"storage.config"',
    '"storage.state"',
    '"storage.objects"',
    '"storage.containers"',
    '"storage.items"',
    '"storage.core"',
    '"storage.permissions"',
    '"storage.clock"',
    '"storage.sync"',
    'startIndex = startIndexPublic',
    'processJobs = processJobs',
    'deposit = function',
    'withdraw = function'
)) {
    if (-not $storageModule.Contains($marker)) {
        throw "Storage contract marker missing: $marker"
    }
}

foreach ($marker in @(
    'Rules.maxNodes = 128',
    'Rules.maxDepth = 32',
    'Rules.maxIndexedItems = 20000',
    'Rules.indexBatchItems = 250',
    'Rules.indexBudgetMs = 2',
    'allowCategories',
    'denyCategories',
    'if left.matchRank ~= right.matchRank',
    'if left.priorityRank ~= right.priorityRank'
)) {
    if (-not $storageRules.Contains($marker)) {
        throw "Storage rule marker missing: $marker"
    }
}

function Resolve-Tool([string]$Name, [string[]]$Fallbacks) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        if ($command.Source) { return $command.Source }
        return $command.Path
    }
    foreach ($fallback in $Fallbacks) {
        if (Test-Path -LiteralPath $fallback) { return $fallback }
    }
    return $null
}

$luaExe = Resolve-Tool 'lua' @(
    (Join-Path $env:USERPROFILE 'Tools\Lua51\lua.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\lua.exe')
)
if (-not $luaExe) {
    throw 'Lua 5.1 runtime is required for terminal/storage validation'
}
& $luaExe $files[4] $Lua
if ($LASTEXITCODE -ne 0) {
    throw 'Terminal/storage module runtime test failed'
}

$luac = Resolve-Tool 'luac' @(
    (Join-Path $env:USERPROFILE 'Tools\Lua51\luac.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Lua51\5.1.5\luac.exe')
)
if (-not $luac) {
    throw 'Lua 5.1 compiler is required for terminal/storage validation'
}
foreach ($file in $files) {
    & $luac -p $file
    if ($LASTEXITCODE -ne 0) {
        throw "Lua 5.1 compile failed: $file"
    }
}

Write-Output 'Test-GodSystemV422012TerminalStorageModule passed'
