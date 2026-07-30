param(
    [Parameter(Mandatory = $true)]
    [string]$Root
)

$ErrorActionPreference = "Stop"
$luaRoot = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$retiredFiles = @(
    'client\GodSystem_Network.lua',
    'server\GodSystem_Server.lua',
    'server\GodSystem_StorageServer.lua',
    'server\GodSystem_AutoLoaderServer.lua',
    'server\GodSystem_SPVehicleRepair.lua',
    'server\GodSystem_TransactionOps.lua',
    'shared\GodSystem_Protocol.lua',
    'shared\GodSystem_RuntimeMode.lua',
    'shared\GodSystem_StorageManager.lua'
)
foreach ($relative in $retiredFiles) {
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $luaRoot $relative))) `
        ("retired runtime file still active: {0}" -f $relative)
}

$luaFiles = @(Get-ChildItem -LiteralPath $luaRoot -Recurse -Filter '*.lua' -File |
    Where-Object {
        $_.Name -notlike 'GodSystem_Localization*'
    })
$forbidden = @(
    'GodSystemNetwork',
    'legacyBusinessEnabled',
    'GodSystemStorageManager',
    'GodSystem_RuntimeMode',
    'GodSystem_Protocol',
    'safeAll',
    'removeUnlocked',
    'terminalCompression',
    'GodSystemCompression'
)
foreach ($pattern in $forbidden) {
    $matches = @($luaFiles | Select-String -SimpleMatch -Pattern $pattern)
    Assert-True ($matches.Count -eq 0) `
        ("retired runtime symbol still active: {0}" -f $pattern)
}

$core = Get-Content -LiteralPath (Join-Path $luaRoot 'client\GodSystem_Core.lua') `
    -Raw -Encoding UTF8
Assert-True (-not $core.Contains('Events.OnPlayerUpdate.Add(GodSystem.onPlayerUpdate)')) `
    'legacy Core lifecycle is still registered'

$companion = Get-Content -LiteralPath `
    (Join-Path $luaRoot 'client\GodSystem_Companion.lua') -Raw -Encoding UTF8
Assert-True (-not $companion.Contains('Events.')) `
    'presentation companion shell still owns lifecycle events'
Assert-True (-not $companion.Contains('IsoZombie')) `
    'presentation companion shell still owns target scanning'

$storage = Get-Content -LiteralPath `
    (Join-Path $luaRoot 'client\GodSystem_StorageClient.lua') -Raw -Encoding UTF8
$autoLoader = Get-Content -LiteralPath `
    (Join-Path $luaRoot 'client\GodSystem_AutoLoaderClient.lua') -Raw -Encoding UTF8
Assert-True (-not $storage.Contains('sendClientCommand')) `
    'storage client still sends commands outside the modular adapter'
Assert-True (-not $autoLoader.Contains('sendClientCommand')) `
    'autoloader client still sends commands outside the modular adapter'

$server = Get-Content -LiteralPath `
    (Join-Path $luaRoot 'server\GodSystem_ModularServer.lua') -Raw -Encoding UTF8
Assert-True ($server.Contains('if not (isServer and isServer()) then')) `
    'modular server is not guarded to the server runtime'

Write-Output 'Test-GodSystemV422012LegacyCleanupOK'
