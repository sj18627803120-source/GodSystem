-- Exercise the actual MP store and command handlers across a simulated save/restart.
-- ModData disk serialization / real server networking remain game acceptance items.
require = function() end
local function load(path) return assert(loadstring(readSource(path)))() end
load("shared/GodSystem_ItemConfig.lua")
load("shared/GodSystem_ItemConfigPresetLibrary.lua")
load("shared/GodSystem_ConversionRelations.lua")
load("shared/GodSystem_Pinyin.lua")
load("server/GodSystem_ServerRuntime_Foundation.lua")
load("server/GodSystem_ServerRuntime_RouterConfig.lua")
local I, L = GodSystemItemConfig, GodSystemItemConfigPresetLibrary
local disk, fileText, messages = {}, "", {}
getFileReader = function()
    local offset = 1
    return { readLine = function()
        if offset > #fileText then return nil end
        local finish = fileText:find("\n", offset, true) or (#fileText + 1)
        local line = fileText:sub(offset, finish - 1)
        offset = finish + 1
        return line
    end, close = function() end }
end
getFileWriter = function()
    local parts = {}
    return { write = function(_, value) parts[#parts + 1] = value end,
        close = function() fileText = table.concat(parts) end }
end
GodSystemConfig = { DataKey = "GodSystem_CN_Data", ItemOverrides = {} }
GodSystemRuntimeConfig = { readSandbox = function() end }
GodSystemServer = {}
ModData = { getOrCreate = function(key) disk[key] = disk[key] or {}; return disk[key] end }
sendServerCommand = function(_, _, command, args) messages[command] = L.copy(args) end
local result
local function boot()
    L.resetForTests()
    I.Current = nil
    local env = setmetatable({}, { __index = _G })
    GodSystemServerRuntimeInstallers.GodSystem_ServerRuntime_Foundation(env)
    GodSystemServerRuntimeInstallers.GodSystem_ServerRuntime_RouterConfig(env)
    env.isAdminPlayer = function(player) return player.admin == true end
    env.trim = function(value) return tostring(value or ""):match("^%s*(.-)%s*$") end
    env.finishCode = function(_, ok, code) result = { ok = ok, code = code } end
    env.applyRuntimeStores()
    return env
end
local admin, player = { admin = true }, { admin = false }
local env = boot()
local data = env.itemConfigStore()
data.itemOverrides = { ["Base.Axe"] = { buyPrice = 73, sellPrice = 11, shopMode = "forced" } }
data.conversionBuiltinDisabled = { example = true }
env.Commands.itemConfigPresetSave(nil, nil, admin, { name = "1" })
assert(result.ok and #fileText > 0)
local validLibrary = fileText
data.itemOverrides["Base.Axe"].buyPrice = 99
env.Commands.itemConfigPresetApply(nil, nil, admin, { name = "1" })
assert(result.ok and I.getItemOverride("Base.Axe").buyPrice == 73)
-- Later individual edits are authoritative; restart must NOT reapply an old template.
data.itemOverrides["Base.Axe"].buyPrice = 81
env.applyRuntimeStores()
disk = L.copy(disk)
env = boot()
env.Commands.itemConfigPresetsGet(nil, nil, admin)
assert(messages.itemConfigPresets.active == "1")
assert(I.getItemOverride("Base.Axe").buyPrice == 81 and I.getItemOverride("Base.Axe").sellPrice == 11)
assert(env.itemConfigStore().conversionBuiltinDisabled.example == true)
env.Commands.itemConfigPresetApply(nil, nil, player, { name = "default" })
assert(not result.ok and result.code == "AdminRequired" and I.getItemOverride("Base.Axe").buyPrice == 81)
print("PASS MP preset: normal restart preserves live pricing, selection, relations and admin authority")

-- A relocated/empty global template library must not relabel the world's live
-- configuration as default. It also must not resurrect old cross-save slots.
fileText = ""
disk = L.copy(disk)
env = boot()
env.Commands.itemConfigPresetsGet(nil, nil, admin)
assert(messages.itemConfigPresets.active == "1", "missing shared template must not reset live selection to default")
assert(#messages.itemConfigPresets.order == 0, "missing template stays unavailable for read")
assert(I.getItemOverride("Base.Axe").buyPrice == 81, "listing presets never resets live prices")
env.Commands.itemConfigPresetApply(nil, nil, admin, { name = "1" })
assert(not result.ok and I.getItemOverride("Base.Axe").buyPrice == 81)
env.Commands.itemConfigPresetApply(nil, nil, admin, { name = "default" })
assert(result.ok and I.getItemOverride("Base.Axe") == nil)
disk = L.copy(disk)
env = boot()
env.Commands.itemConfigPresetsGet(nil, nil, admin)
assert(messages.itemConfigPresets.active == "default" and I.getItemOverride("Base.Axe") == nil)
print("PASS MP preset: missing template keeps live prices/selection; explicit default persists")
disk, fileText = {}, validLibrary
env = boot()
env.Commands.itemConfigPresetsGet(nil, nil, admin)
assert(messages.itemConfigPresets.order[1] == "1" and messages.itemConfigPresets.active == "default")
assert(I.getItemOverride("Base.Axe") == nil, "another world sees templates without inheriting the active config")
env.Commands.itemConfigPresetApply(nil, nil, admin, { name = "1" })
assert(result.ok and I.getItemOverride("Base.Axe").buyPrice == 73)
fileText = "not a valid preset header\n"
env = boot()
env.Commands.itemConfigPresetsGet(nil, nil, admin)
assert(not result.ok and result.code == "ItemConfigPresetLibraryFailed")
assert(I.getItemOverride("Base.Axe").buyPrice == 73, "unreadable template library does not clear world prices")
print("PASS MP preset: cross-world templates, no auto-apply, corrupt library does not clear pricing")
