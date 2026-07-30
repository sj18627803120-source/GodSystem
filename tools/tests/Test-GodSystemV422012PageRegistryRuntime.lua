local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    package.path,
}, ";")

local Registry = require "GodSystem/UI/PageRegistry"

local calls = {}
local window = {
    setTaskLayout = function(_, value) calls.taskLayout = value end,
    setShopLayout = function(_, value) calls.shopLayout = value end,
    setTextPageLayout = function(_, value) calls.textLayout = value end,
    populateTasks = function() calls.populated = "tasks" end,
    populateHome = function() calls.populated = "home" end,
    applyHomeActionBar = function(_, payload) calls.homePayload = payload end,
    getSelectedPayload = function() return { id = "home" } end,
    setStandardActionBar = function() calls.standard = true end,
    setActionBar = function(_, value) calls.actionBar = value end,
    populateAdmin = function() calls.populated = "admin" end,
}

Registry.prepare(window, "tasks")
assert(calls.taskLayout == true and calls.shopLayout == false
    and calls.textLayout == false, "task page layout changed")
assert(Registry.populate(window, "tasks") and calls.populated == "tasks",
    "task page was not dispatched")
Registry.finish(window, "tasks")
assert(calls.standard == true, "standard action bar was not applied")

calls = {}
Registry.prepare(window, "home")
Registry.populate(window, "home")
Registry.finish(window, "home")
assert(calls.populated == "home" and calls.homePayload.id == "home",
    "home page completion did not receive stable selection")

calls = {}
Registry.prepare(window, "admin")
Registry.populate(window, "admin")
Registry.finish(window, "admin")
assert(calls.shopLayout == true and calls.populated == "admin"
    and #calls.actionBar == 4, "admin page layout changed")

assert(not Registry.populate(window, "missing"),
    "unknown page unexpectedly dispatched")
assert(#Registry.modes() >= 14, "page registry omitted feature pages")

print("Test-GodSystemV422012PageRegistryRuntime passed")
