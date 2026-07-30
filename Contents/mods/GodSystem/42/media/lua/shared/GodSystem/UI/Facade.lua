require "GodSystem/UI/ReadModel"

GodSystemUIFacade = GodSystemUIFacade or {}

local Facade = GodSystemUIFacade

local DEFAULT_QUERIES = {
    "system.snapshot",
    "wallet.balance",
    "bank.summary",
    "tasks.snapshot",
    "shop.catalog",
    "recycle.snapshot",
    "upgrades.summary",
    "home.snapshot",
    "terminal.status",
    "storage.status",
    "companion.state",
    "admin.snapshot",
}

local REFRESH_AFTER = {
    ["system.initialize"] = { "system.snapshot", "wallet.balance" },
    ["system.preference"] = { "system.snapshot" },
    ["wallet.consolidate"] = { "wallet.balance", "bank.summary", "system.history" },
    ["wallet.transfer"] = { "wallet.balance", "bank.summary" },
    ["bank.execute"] = { "wallet.balance", "bank.summary", "system.history" },
    ["tasks.generate"] = { "tasks.snapshot", "wallet.balance", "system.history" },
    ["tasks.refresh"] = { "tasks.snapshot", "wallet.balance", "system.history" },
    ["tasks.autoClaim"] = { "tasks.snapshot" },
    ["tasks.accept"] = { "tasks.snapshot" },
    ["tasks.claim"] = { "tasks.snapshot", "wallet.balance", "system.history" },
    ["tasks.fail"] = { "tasks.snapshot", "wallet.balance", "system.history" },
    ["shop.list"] = { "shop.catalog", "wallet.balance", "system.history" },
    ["shop.hide"] = { "shop.catalog" },
    ["shop.delete"] = { "shop.catalog" },
    ["shop.purchase"] = { "wallet.balance", "system.history" },
    ["shop.lottery"] = { "wallet.balance", "system.history" },
    ["recycle.execute"] = {
        "recycle.snapshot", "shop.catalog", "wallet.balance", "system.history",
    },
    ["recycle.preference"] = {
        "recycle.snapshot", "wallet.balance", "system.history",
    },
    ["upgrades.purchase"] = {
        "upgrades.summary", "wallet.balance", "tasks.snapshot", "system.history",
    },
    ["upgrades.refresh"] = { "upgrades.summary" },
    ["medical.execute"] = { "wallet.balance", "system.history" },
    ["maintenance.execute"] = { "wallet.balance", "system.history" },
    ["home.set"] = { "home.snapshot", "system.history" },
    ["home.buyTemp"] = { "home.snapshot", "wallet.balance", "system.history" },
    ["home.setTemp"] = { "home.snapshot", "system.history" },
    ["home.teleport"] = { "home.snapshot", "system.history" },
    ["home.teleportTemp"] = { "home.snapshot", "system.history" },
    ["home.return"] = { "home.snapshot", "system.history" },
    ["home.clearReturn"] = { "home.snapshot" },
    ["home.upgradeSafeZone"] = {
        "home.snapshot", "wallet.balance", "system.history",
    },
    ["home.toggleSafeZone"] = { "home.snapshot" },
    ["home.clearSafeZone"] = {
        "home.snapshot", "wallet.balance", "system.history",
    },
    ["terminal.execute"] = {
        "terminal.status", "upgrades.summary", "wallet.balance", "system.history",
    },
    ["storage.execute"] = {
        "storage.status", "wallet.balance", "system.history",
    },
    ["companion.purchase"] = {
        "companion.state", "wallet.balance", "system.history",
    },
    ["companion.sight"] = { "companion.state", "wallet.balance" },
    ["companion.combatMode"] = { "companion.state" },
    ["companion.followMode"] = { "companion.state" },
    ["companion.visible"] = { "companion.state" },
    ["companion.guardian"] = { "companion.state" },
    ["companion.recall"] = { "companion.state" },
    ["attributes.purchase"] = { "wallet.balance", "system.history" },
    ["attributes.traitModify"] = { "wallet.balance", "system.history" },
    ["admin.save"] = { "admin.snapshot" },
    ["admin.itemOverride"] = { "admin.snapshot" },
    ["admin.clearItemOverride"] = { "admin.snapshot" },
}

function Facade.new(options)
    options = type(options) == "table" and options or {}
    local gateway = assert(options.gateway, "UI facade gateway required")
    local readModel = options.readModel or GodSystemUIReadModel.new({
        version = options.version,
    })
    local instance = {
        gateway = gateway,
        readModel = readModel,
        refreshing = {},
        unsubscribe = nil,
    }

    local function observe(action, result)
        readModel:apply(action, result)
        local queries = result and result.ok == true and REFRESH_AFTER[action] or nil
        if queries then
            for index = 1, #queries do
                local query = queries[index]
                if not instance.refreshing[query] then
                    instance.refreshing[query] = true
                    gateway:request(query, {}, {
                        callback = function()
                            instance.refreshing[query] = nil
                        end,
                    })
                end
            end
        end
        if type(options.onChanged) == "function" then
            options.onChanged(action, result, readModel:get())
        end
    end
    instance.unsubscribe = gateway:subscribe(observe)

    function instance:data()
        return self.readModel:get()
    end

    function instance:request(action, args, requestOptions)
        return self.gateway:request(action, args, requestOptions)
    end

    function instance:refresh(actions)
        actions = type(actions) == "table" and actions or DEFAULT_QUERIES
        local results = {}
        for index = 1, #actions do
            local action = actions[index]
            results[action] = self.gateway:request(action, {})
        end
        return results
    end

    function instance:setPreference(key, value)
        return self:request("system.preference", { key = key, value = value })
    end

    function instance:stop()
        if self.unsubscribe then self.unsubscribe() end
        self.unsubscribe = nil
    end

    return instance
end

return Facade
