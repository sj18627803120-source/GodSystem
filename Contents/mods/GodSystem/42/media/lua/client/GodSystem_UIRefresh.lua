-- Coalesces UI work requested by state packets and local actions.  A state
-- packet is authoritative data, but it is not automatically a reason to
-- rebuild every visible page.
GodSystemUIRefresh = GodSystemUIRefresh or {}
local Refresh = GodSystemUIRefresh

local ORDER = { "directory", "numbers", "details", "layout" }
local function visible(window) return window and window.getIsVisible and window:getIsVisible() end

function Refresh.mark(window, kind)
    if kind == "directory" and GodSystemShopCatalog then GodSystemShopCatalog.invalidate("business") end
    if kind == "numbers" and GodSystemShopCatalog then GodSystemShopCatalog.invalidatePrices() end
    if kind == "preferences" and GodSystemShopCatalog then GodSystemShopCatalog.invalidatePreferences() end
    if not window then return end
    window.godSystemRefresh = window.godSystemRefresh or {}
    window.godSystemRefresh[kind] = true
end

function Refresh.onState(window, revisions, oldRevisions)
    if type(revisions) ~= "table" or revisions.shopCatalog == nil then
        for _, kind in ipairs(ORDER) do Refresh.mark(window, kind) end
        Refresh.mark(window, "tasks"); Refresh.mark(window, "equipment")
        return true
    end
    oldRevisions = type(oldRevisions) == "table" and oldRevisions or {}
    local changed = false
    local function differs(key)
        if oldRevisions[key] ~= revisions[key] then changed = true; return true end
        return false
    end
    if differs("shopCatalog") then Refresh.mark(window, "directory") end
    if differs("shopPreferences") then Refresh.mark(window, "preferences") end
    if differs("walletBank") then Refresh.mark(window, "numbers") end
    if differs("tasks") then Refresh.mark(window, "tasks"); Refresh.mark(window, "details") end
    if differs("equipment") then Refresh.mark(window, "equipment") end
    return changed
end

function Refresh.flush(window)
    if not visible(window) then return false end
    local flags = window.godSystemRefresh or {}
    window.godSystemRefresh = {}
    if GodSystemShopCatalog and GodSystemShopCatalog.note then
        for kind in pairs(flags) do GodSystemShopCatalog.note("refresh." .. kind) end
    end
    local rebuild = window.mode == "shop" and (flags.directory or flags.preferences or flags.numbers)
        or window.mode == "tasks" and flags.tasks
        or window.mode ~= "shop" and window.mode ~= "equipment" and (flags.numbers or flags.directory or flags.general)
    if flags.equipment and window.mode == "equipment" and window.terminalEquipment and window.terminalEquipment.refreshDetails then
        window.terminalEquipment:refreshDetails()
    end
    if rebuild then window:populateList(); return true end
    if flags.numbers and window.refreshTerminalStatus then window:refreshTerminalStatus() end
    if flags.details then window:updateDetail() end
    if flags.layout and window.relayoutVisiblePage then window:relayoutVisiblePage() end
    return false
end

return Refresh
