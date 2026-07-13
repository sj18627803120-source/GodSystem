param(
    [string]$Root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
)

$ErrorActionPreference = 'Stop'

$client = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua\client\GodSystem_Core.lua'
$server = Join-Path $Root 'Contents\mods\GodSystem\42\media\lua\server\GodSystem_Server.lua'

foreach($path in @($client, $server)){
    if(-not (Test-Path -LiteralPath $path)){
        throw "Missing file: $path"
    }
}

$clientText = [System.IO.File]::ReadAllText($client, [System.Text.Encoding]::UTF8)
$serverText = [System.IO.File]::ReadAllText($server, [System.Text.Encoding]::UTF8)

$checks = @(
    @{ Name = 'client loose ammo predicate'; Text = $clientText; Pattern = 'function GodSystem\.isLooseAmmoRecycleItem\(fullType, item\)' },
    @{ Name = 'client ammo name guard'; Text = $clientText; Pattern = 'local lowerText = string\.lower\(text\)[\s\S]*if not looksLikeLooseAmmoName then\s+return false\s+end' },
    @{ Name = 'client loose ammo fixed value'; Text = $clientText; Pattern = 'if GodSystem\.isLooseAmmoRecycleItem\(fullType, item\) then\s+return 1\s+end' },
    @{ Name = 'client no loose ammo divisor'; Text = $clientText; Pattern = 'if GodSystem\.isLooseAmmoRecycleItem\(fullType, item\) then\s+return 1\s+end[\s\S]*function GodSystem\.calculateRecyclePayout' },
    @{ Name = 'server loose ammo predicate'; Text = $serverText; Pattern = 'local function isLooseAmmoRecycleItem\(fullType, item\)' },
    @{ Name = 'server ammo name guard'; Text = $serverText; Pattern = 'local lowerType = string\.lower\(fullType\)[\s\S]*if not looksLikeLooseAmmoName then return false end' },
    @{ Name = 'server loose ammo fixed value'; Text = $serverText; Pattern = 'if isLooseAmmoRecycleItem\(fullType, item\) then return 1 end' },
    @{ Name = 'server no loose ammo divisor'; Text = $serverText; Pattern = 'if isLooseAmmoRecycleItem\(fullType\) then return 1 end[\s\S]*local function calculateRecyclePayout' }
)

foreach($check in $checks){
    if($check.Text -notmatch $check.Pattern){
        throw "LooseAmmoCheckFailed: $($check.Name)"
    }
}

Write-Output 'LooseAmmoCheckOK'
