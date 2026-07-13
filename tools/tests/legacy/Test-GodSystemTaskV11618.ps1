param(
    [string]$Root = "C:\Users\Admin\Zomboid\Workshop\GodSystem"
)

$ErrorActionPreference = "Stop"
$client = Join-Path $Root "Contents\mods\GodSystem\42\media\lua\client"
$server = Join-Path $Root "Contents\mods\GodSystem\42\media\lua\server"
$shared = Join-Path $Root "Contents\mods\GodSystem\42\media\lua\shared"
$ui = Join-Path $client "GodSystem_UI.lua"
$core = Join-Path $client "GodSystem_Core.lua"
$serverLua = Join-Path $server "GodSystem_Server.lua"
$config = Join-Path $shared "GodSystem_Config.lua"

$utf8 = [System.Text.Encoding]::UTF8
$uiText = [System.IO.File]::ReadAllText($ui, $utf8)
$coreText = [System.IO.File]::ReadAllText($core, $utf8)
$serverText = [System.IO.File]::ReadAllText($serverLua, $utf8)
$configText = [System.IO.File]::ReadAllText($config, $utf8)

$checks = @(
    @{ Name = "version config"; Ok = $configText -match 'GodSystemConfig\.Version\s*=\s*"\d+\.\d+\.\d+"' },
    @{ Name = "death penalty thirty percent"; Ok = $configText -match 'BankDeathDemandPenaltyRatio\s*=\s*0\.3' },
    @{ Name = "client task failure bank first"; Ok = $coreText -match 'function GodSystem\.payTaskFailurePenalty' -and $coreText -match 'bank\.current' -and $coreText -match 'GodSystem\.removeCurrency' },
    @{ Name = "server task failure bank first"; Ok = $serverText -match 'local function payTaskFailurePenalty' -and $serverText -match 'bank\.current' -and $serverText -match 'removeCurrency\(player' },
    @{ Name = "client death fails all active tasks"; Ok = $coreText -match 'failActiveTasksOnDeath' -and $coreText -notmatch 'status == "active" and task\.kind == "surviveHours"' },
    @{ Name = "server death fails all active tasks"; Ok = $serverText -match 'failActiveTasksOnDeath' -and $serverText -notmatch 'status == "active" and task\.kind == "surviveHours"' },
    @{ Name = "task abandon api"; Ok = $coreText -match 'function GodSystem\.abandonTask' -and $serverText -match 'action == "abandon"' },
    @{ Name = "task list compact title"; Ok = $coreText -match 'function GodSystem\.getTaskListTitle' },
    @{ Name = "task detail sections"; Ok = $coreText -match 'function GodSystem\.getTaskDetailLines' -and $coreText -match 'TaskSection_Reward' -and $coreText -match 'TaskSection_Penalty' },
    @{ Name = "task row second line"; Ok = $uiText -match 'getTaskListStatusLine' -and $uiText -match 'drawProgressBar' },
    @{ Name = "task primary labels"; Ok = $uiText -match 'Btn_TaskAccept' -and $uiText -match 'Btn_TaskClaim' -and $uiText -match 'Btn_TaskAbandon' },
    @{ Name = "abandon confirmation"; Ok = $uiText -match 'Confirm_AbandonTask' }
)

$failed = @()
foreach($check in $checks){
    if(-not $check.Ok){
        $failed += $check.Name
    }
}

if($failed.Count -gt 0){
    throw ("TaskV11618CheckFailed: " + ($failed -join ", "))
}

Write-Output "TaskV11618CheckOK"
