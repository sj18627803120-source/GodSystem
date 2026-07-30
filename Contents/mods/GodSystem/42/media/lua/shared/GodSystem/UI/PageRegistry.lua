GodSystemUIPageRegistry = GodSystemUIPageRegistry or {}

local Registry = GodSystemUIPageRegistry

local definitions = {
    shop = {
        populate = "populateShop",
        shopLayout = true,
        finish = "applyShopActionLayout",
    },
    lottery = {
        populate = "populateLottery",
        shopLayout = true,
        finish = "applyLotteryActionLayout",
    },
    recycle = {
        populate = "populateRecycle",
        shopLayout = true,
        finish = "applyRecycleActionLayout",
    },
    waist = { populate = "populateWaistSpace" },
    storage = { populate = "populateStorageNetwork" },
    bank = { populate = "populateBank" },
    traits = { populate = "populateTraits" },
    attribute = {
        populate = "populateAttributes",
        shopLayout = true,
    },
    home = {
        populate = "populateHome",
        finish = "applyHomeActionBar",
        selectedPayload = true,
    },
    tasks = {
        populate = "populateTasks",
        taskLayout = true,
    },
    upgrades = { populate = "populateUpgrades" },
    companion = { populate = "populateCompanion" },
    history = {
        populate = "populateHistory",
        textLayout = true,
    },
    info = {
        populate = "populateInfo",
        textLayout = true,
    },
    diagnostics = {
        populate = "populateDiagnostics",
        textLayout = true,
    },
    admin = {
        populate = "populateAdmin",
        shopLayout = true,
        adminLayout = true,
    },
}

function Registry.definition(mode)
    return definitions[tostring(mode or "")]
end

function Registry.prepare(window, mode)
    local definition = Registry.definition(mode) or {}
    window:setTaskLayout(definition.taskLayout == true)
    window:setShopLayout(definition.shopLayout == true)
    window:setTextPageLayout(definition.textLayout == true)
    return definition
end

function Registry.populate(window, mode)
    local definition = Registry.definition(mode)
    local method = definition and window[definition.populate] or nil
    if type(method) ~= "function" then return false, "pageMissing" end
    method(window)
    return true
end

function Registry.finish(window, mode)
    local definition = Registry.definition(mode) or {}
    if definition.adminLayout == true then
        window:setActionBar({
            { id = "searchBox", width = 240, minWidth = 150 },
            { id = "primary", width = 118 },
            { id = "secondary", width = 118 },
            { id = "third", width = 118 },
        })
        return true
    end
    if definition.finish and type(window[definition.finish]) == "function" then
        if definition.selectedPayload == true then
            window[definition.finish](window, window:getSelectedPayload())
        else
            window[definition.finish](window)
        end
        return true
    end
    window:setStandardActionBar()
    return true
end

function Registry.modes()
    local result = {}
    for mode in pairs(definitions) do result[#result + 1] = mode end
    table.sort(result)
    return result
end

return Registry
