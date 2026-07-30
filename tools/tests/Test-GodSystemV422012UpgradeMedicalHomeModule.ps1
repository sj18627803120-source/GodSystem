param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'
$modules = @(
    'shared\GodSystem\Features\Upgrades\Module.lua',
    'shared\GodSystem\Features\Medical\Module.lua',
    'shared\GodSystem\Features\Home\Module.lua'
)

foreach ($relative in $modules) {
    $path = Join-Path $luaRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing vertical feature module: $relative" }
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if ($text -notmatch 'require\s+"GodSystem/Core/Result"') {
        throw "Feature module does not use the shared result contract: $relative"
    }
    if ($text -match 'require\s+"(?:GodSystem_Core|GodSystem_Server|GodSystem_UI|GodSystem_CarryCapacity|GodSystem_TerminalUpgrades|GodSystem_TerminalRelief)"') {
        throw "Feature module requires a legacy business implementation: $relative"
    }
    if ($text -match '\b(?:Events|sendClientCommand|sendServerCommand|OnClientCommand|OnServerCommand|getPlayer|getCell)\b') {
        throw "Feature module bypasses an explicit platform port: $relative"
    }
    foreach ($required in @('Descriptor\.create', 'instance\.public', 'instance:start', 'instance:stop', 'instance:health')) {
        if ($text -notmatch $required) { throw "Feature module is missing contract '$required': $relative" }
    }
}

$upgrades = [IO.File]::ReadAllText((Join-Path $luaRoot $modules[0]), [Text.Encoding]::UTF8)
foreach ($type in @('carryCapacity', 'activeTasks', 'dailyTasks', 'terminalCapacity', 'terminalReduction', 'terminalRelief')) {
    if ($upgrades -notmatch [regex]::Escape($type)) { throw "Upgrade type is missing: $type" }
}
if ($upgrades -match '(?i)compress') { throw 'Retired terminal compression returned in the upgrade module' }
if ($upgrades -notmatch 'snapshot' -or $upgrades -notmatch 'restore' -or $upgrades -notmatch 'refresh = refresh') {
    throw 'Upgrade module does not preserve ability rollback and refresh'
}

$medical = [IO.File]::ReadAllText((Join-Path $luaRoot $modules[1]), [Text.Encoding]::UTF8)
foreach ($action in @('checkInfection', 'healInjuries', 'cureInfection')) {
    if ($medical -notmatch [regex]::Escape($action)) { throw "Medical action is missing: $action" }
}
if ($medical -notmatch 'body\.snapshot' -or $medical -notmatch 'body\.restore') {
    throw 'Medical module does not use a body-state rollback boundary'
}

$homeModule = [IO.File]::ReadAllText((Join-Path $luaRoot $modules[2]), [Text.Encoding]::UTF8)
foreach ($action in @('setHome', 'buyTemp', 'setTemp', 'teleportHome', 'teleportTemp', 'returnToDeparture', 'upgradeSafeZone', 'toggleSafeZone', 'clearSafeZone')) {
    if ($homeModule -notmatch [regex]::Escape($action)) { throw "Home action is missing: $action" }
}
if ($homeModule -match '(?i)(StorageController|originalCapacities|terminalCompression)') {
    throw 'Retired controller/capacity-lock/compression logic returned in Home'
}

$luaExe = Get-Command lua -ErrorAction SilentlyContinue
if (-not $luaExe) {
    $localLua = 'C:\Users\Administrator\AppData\Local\Programs\Lua51\5.1.5\lua.exe'
    if (Test-Path -LiteralPath $localLua) { $luaExe = Get-Item -LiteralPath $localLua }
}
if (-not $luaExe) { throw 'Lua 5.1 runtime is required for upgrade/medical/home module validation' }
$luaPath = if ($luaExe.Source) { $luaExe.Source } else { $luaExe.FullName }
& $luaPath (Join-Path $PSScriptRoot 'Test-GodSystemV422012UpgradeMedicalHomeModuleRuntime.lua') $luaRoot
if ($LASTEXITCODE -ne 0) { throw 'Upgrade/medical/home module runtime test failed' }

Write-Output 'Test-GodSystemV422012UpgradeMedicalHomeModule passed'
