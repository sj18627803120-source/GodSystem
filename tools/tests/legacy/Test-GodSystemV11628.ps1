$ErrorActionPreference = 'Stop'

$root = 'C:\Users\Admin\Zomboid\Workshop\GodSystem'
$locPath = Join-Path $root 'Contents\mods\GodSystem\42\media\lua\shared\GodSystem_Localization_Override.lua'

if (-not (Test-Path -LiteralPath $locPath)) {
    throw "Missing localization override: $locPath"
}

$text = [System.IO.File]::ReadAllText($locPath, [System.Text.Encoding]::UTF8)
$newPrefix = 'GodSystemFallbackText.zh["NotifyMP_KillReward"] = "\229\135\187\230\157\128\229\165\150\229\138\177\229\144\136\232\174\161 +{1}'
$oldPrefix = 'GodSystemFallbackText.zh["NotifyMP_KillReward"] = "\229\135\187\230\157\128\229\131\181\229\176\184 +{1}'

if (-not $text.Contains($newPrefix)) {
    throw 'MP kill reward notification should say the reward is a total batch amount.'
}

if ($text.Contains($oldPrefix)) {
    throw 'Old MP kill reward notification wording is still present.'
}

Write-Output 'v1.16.28 MP kill reward notification wording check passed.'
