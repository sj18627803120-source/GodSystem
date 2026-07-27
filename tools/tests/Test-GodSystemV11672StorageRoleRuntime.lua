local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    package.path,
}, ";")

GodSystemConfig = {
    DataKey = "GodSystem_Test",
}

local Storage = require "GodSystem_Storage"

local function acceptsWithoutGlobalNext(link, category)
    local savedNext = next
    next = nil
    local ok, accepted = pcall(Storage.linkRoleAccepts, link, category)
    next = savedNext
    assert(ok, "storage role routing must not require the Kahlua-missing global next(): " .. tostring(accepted))
    return accepted
end

assert(acceptsWithoutGlobalNext({ role = "auto", allowCategories = {} }, "material") == true,
    "an empty allow list must preserve automatic routing")
assert(acceptsWithoutGlobalNext({ role = "auto", allowCategories = { material = true } }, "material") == true,
    "an explicit matching allow rule must accept the category")
assert(acceptsWithoutGlobalNext({ role = "auto", allowCategories = { food = true } }, "material") == false,
    "a non-matching non-empty allow list must reject the category")

print("Test-GodSystemV11672StorageRoleRuntime passed")
