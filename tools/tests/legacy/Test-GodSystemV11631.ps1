param(
    [string]$Root = "C:\Users\Admin\Zomboid\Workshop\GodSystem"
)

$ErrorActionPreference = "Stop"
$modRoot = Join-Path $Root "Contents\mods\GodSystem"
$media = Join-Path $modRoot "42\media"
$shared = Join-Path $media "lua\shared"
$client = Join-Path $media "lua\client"
$server = Join-Path $media "lua\server"

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Assert-Contains([string]$Path, [string]$Needle) {
    $text = Read-Utf8 $Path
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
        throw "Missing expected text in $Path : $Needle"
    }
}

$adminConfig = Join-Path $shared "GodSystem_AdminConfig.lua"
if (!(Test-Path -LiteralPath $adminConfig)) {
    throw "Missing GodSystem_AdminConfig.lua"
}

Assert-Contains $adminConfig "labelKey"
Assert-Contains $adminConfig "descKey"
Assert-Contains $adminConfig 'labelKey = "AdminSetting_StartingPoints"'
Assert-Contains $adminConfig 'descKey = "AdminSetting_StartingPoints_Desc"'
Assert-Contains $adminConfig 'labelKey = "AdminSetting_EnableShop"'
Assert-Contains $adminConfig 'labelKey = "AdminSetting_ShopBuyPriceMultiplier"'
Assert-Contains $adminConfig "function GodSystemAdminConfig.getDefaults"
Assert-Contains $adminConfig "function GodSystemAdminConfig.applyRuntime"
Assert-Contains $adminConfig "function GodSystemAdminConfig.sanitizeSettings"
Assert-Contains $adminConfig "function GodSystemAdminConfig.sanitizeItemOverride"
Assert-Contains $adminConfig "function GodSystemAdminConfig.buildSnapshot"

$protocol = Join-Path $shared "GodSystem_Protocol.lua"
Assert-Contains $protocol 'AdminConfigGet = "adminConfigGet"'
Assert-Contains $protocol 'AdminConfigSet = "adminConfigSet"'
Assert-Contains $protocol 'AdminItemOverrideSet = "adminItemOverrideSet"'
Assert-Contains $protocol 'AdminItemOverrideClear = "adminItemOverrideClear"'

$serverFile = Join-Path $server "GodSystem_Server.lua"
Assert-Contains $serverFile 'require "GodSystem_AdminConfig"'
Assert-Contains $serverFile "function Commands.adminConfigSet"
Assert-Contains $serverFile "function Commands.adminItemOverrideSet"
Assert-Contains $serverFile "GodSystemAdminConfig.applyRuntime"

$coreFile = Join-Path $client "GodSystem_Core.lua"
Assert-Contains $coreFile 'require "GodSystem_AdminConfig"'
Assert-Contains $coreFile "function GodSystem.getAdminConfigSnapshot"
Assert-Contains $coreFile "function GodSystem.saveAdminSettings"
Assert-Contains $coreFile "GodSystemAdminConfig.applyRuntime"

$uiFile = Join-Path $client "GodSystem_UI.lua"
Assert-Contains $uiFile 'id = "admin"'
Assert-Contains $uiFile "function GodSystemWindow:populateAdmin"
Assert-Contains $uiFile "function GodSystemWindow:showAdminSettingDialog"
Assert-Contains $uiFile "function GodSystemWindow:showAdminItemDialog"
Assert-Contains $uiFile "function gsAdminSettingLabel"
Assert-Contains $uiFile "function gsAdminSettingDesc"
Assert-Contains $uiFile "function gsAdminGroupLabel"
Assert-Contains $uiFile "function gsAdminOverrideDetailText"
Assert-Contains $uiFile 'GodSystem.text("Admin_InternalKey"'
Assert-Contains $uiFile 'GodSystem.text("Admin_Example"'
Assert-Contains $uiFile 'GodSystem.text("AdminOverride_Buy"'
Assert-Contains $uiFile 'o.adminSearchText = ""'
Assert-Contains $uiFile 'self.shopSearchPurpose == "admin"'
Assert-Contains $uiFile 'payload.kind == "adminSetting"'
Assert-Contains $uiFile 'GodSystem.text("Btn_AdminEdit"'
Assert-Contains $uiFile 'GodSystem.text("Admin_AddItem"'

$localizationOverrideFile = Join-Path $shared "GodSystem_Localization_Override.lua"
Assert-Contains $localizationOverrideFile '["Tab_Admin"]'
Assert-Contains $localizationOverrideFile '["Btn_AdminEdit"]'
Assert-Contains $localizationOverrideFile '["Admin_AddItem"]'
Assert-Contains $localizationOverrideFile '["AdminGroup_base"]'
Assert-Contains $localizationOverrideFile '["AdminSetting_StartingPoints"]'
Assert-Contains $localizationOverrideFile '["AdminSetting_StartingPoints_Desc"]'
Assert-Contains $localizationOverrideFile '["AdminOverride_Buy"]'
Assert-Contains $localizationOverrideFile '["Admin_Example"]'

$configFile = Join-Path $shared "GodSystem_Config.lua"
Assert-Contains $configFile 'GodSystemConfig.Version = "1.16.31"'
Assert-Contains (Join-Path $modRoot "mod.info") "1.16.31"
Assert-Contains (Join-Path $modRoot "42\mod.info") "1.16.31"
Assert-Contains (Join-Path $Root "workshop.txt") "v1.16.31"

Write-Output "GodSystem v1.16.31 static feature checks passed."
