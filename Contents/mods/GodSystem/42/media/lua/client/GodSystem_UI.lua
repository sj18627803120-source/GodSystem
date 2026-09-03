require "GodSystem_Config"
require "GodSystem_App"
require "GodSystem_Core"
require "GodSystem_UITheme"
require "GodSystem_ItemCatalog"
require "GodSystem_ItemEconomyUI"
require "GodSystem_RangeFilterUI"
require "GodSystem_CompanionConfig"
require "GodSystem_FloatingButtonLifecycle"
require "GodSystem_ListState"
require "GodSystem_PageSections"
require "GodSystem_TaskOrder"
require "GodSystem_PanelKey"
if not ((isClient and isClient()) or (isServer and isServer())) then
    require "GodSystem_Companion"
    require "GodSystem_CompanionUI"
end
require "ISUI/ISPanel"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISScrollBar"
require "ISUI/ISContextMenu"
require "ISUI/ISModalDialog"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"

GodSystemUI = GodSystemUI or {}
GodSystemUI.floating = nil
GodSystemUI.window = nil
GodSystemUI.taskTracker = nil
GodSystemUI.shortcutWindow = nil
GodSystemUI.shopHiddenWindow = nil
GodSystemUI.FloatingButtonRefreshIntervalMs = 5000

function GodSystemUI.openRangeFilterWindow(owner)
    return GodSystemRangeFilterUI_open(owner)
end

function GodSystemUI.presentOverlay(element)
    if not element then return nil end
    if element.addToUIManager then element:addToUIManager() end
    element:setVisible(true)
    if element.setAlwaysOnTop then element:setAlwaysOnTop(true) end
    if element.bringToTop then element:bringToTop() end
    return element
end

GodSystemUIRuntimeEnv = GodSystemUIRuntimeEnv or setmetatable({}, { __index = _G })
GodSystemUIRuntimeEnv.ListState = GodSystemListState
GodSystemUIRuntimeEnv.PageSections = GodSystemPageSections
GodSystemUIRuntimeEnv.TaskOrder = GodSystemTaskOrder
require "GodSystem_UI_Runtime_Components"
require "GodSystem_UI_Runtime_Window"
require "GodSystem_UI_Runtime_Lists"
require "GodSystem_UI_Runtime_Pages"
require "GodSystem_UI_Runtime_Details"
require "GodSystem_UI_Runtime_Dialogs"
require "GodSystem_UI_Runtime_Actions"
require "GodSystem_UI_Runtime_Lifecycle"

assert(GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Components"], "GodSystem UI runtime installer missing: GodSystem_UI_Runtime_Components")(GodSystemUIRuntimeEnv)
assert(GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Window"], "GodSystem UI runtime installer missing: GodSystem_UI_Runtime_Window")(GodSystemUIRuntimeEnv)
assert(GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Lists"], "GodSystem UI runtime installer missing: GodSystem_UI_Runtime_Lists")(GodSystemUIRuntimeEnv)
assert(GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Pages"], "GodSystem UI runtime installer missing: GodSystem_UI_Runtime_Pages")(GodSystemUIRuntimeEnv)
assert(GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Details"], "GodSystem UI runtime installer missing: GodSystem_UI_Runtime_Details")(GodSystemUIRuntimeEnv)
assert(GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Dialogs"], "GodSystem UI runtime installer missing: GodSystem_UI_Runtime_Dialogs")(GodSystemUIRuntimeEnv)
assert(GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Actions"], "GodSystem UI runtime installer missing: GodSystem_UI_Runtime_Actions")(GodSystemUIRuntimeEnv)
assert(GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Lifecycle"], "GodSystem UI runtime installer missing: GodSystem_UI_Runtime_Lifecycle")(GodSystemUIRuntimeEnv)
