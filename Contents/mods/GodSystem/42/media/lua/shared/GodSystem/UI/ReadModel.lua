GodSystemUIReadModel = GodSystemUIReadModel or {}

local ReadModel = GodSystemUIReadModel

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

local function merge(target, source)
    target = type(target) == "table" and target or {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        target[key] = copy(value)
    end
    return target
end

local function defaults(version)
    return {
        version = tostring(version or "42.20.1.2"),
        started = false,
        currencyInitialized = false,
        points = 0,
        tasks = {},
        unlockedShopItems = {},
        upgrades = {},
        bank = {},
        homeSystem = {},
        companion = {},
        adminConfig = {},
        history = {},
        stats = {},
        ui = {},
        serverDiagnostics = {},
        modular = {
            ready = false,
            lastAction = nil,
            lastIssue = nil,
            storage = nil,
            terminal = nil,
        },
    }
end

function ReadModel.new(options)
    options = type(options) == "table" and options or {}
    local instance = {
        value = defaults(options.version),
        revisions = {},
    }

    local function applied(action)
        instance.revisions[action] = (instance.revisions[action] or 0) + 1
        instance.value.modular.ready = true
        instance.value.modular.lastAction = action
        instance.value.modular.lastIssue = nil
    end

    local handlers = {}

    handlers["system.snapshot"] = function(data)
        merge(instance.value, data)
        instance.value.ui = type(instance.value.ui) == "table" and instance.value.ui or {}
        instance.value.history = type(instance.value.history) == "table"
            and instance.value.history or {}
    end
    handlers["system.preference"] = function(data)
        if tostring(data.key or "") ~= "" then instance.value.ui[data.key] = copy(data.value) end
    end
    handlers["system.history"] = function(data)
        instance.value.history = copy(data)
    end
    handlers["wallet.balance"] = function(data)
        instance.value.modular.balance = math.max(0, math.floor(tonumber(data.value) or 0))
        instance.value.modular.balanceScope = tostring(data.scope or "spendable")
        instance.value.balance = instance.value.modular.balance
    end
    handlers["bank.summary"] = function(data)
        instance.value.bank = merge(type(data.state) == "table" and data.state or {}, data)
        instance.value.bank.state = nil
    end
    handlers["tasks.snapshot"] = function(data)
        instance.value.tasks = copy(type(data.tasks) == "table" and data.tasks or {})
        instance.value.autoTaskClaimEnabled = data.autoClaimEnabled == true
        instance.value.lastGeneratedDay = data.lastGeneratedDay
    end
    handlers["shop.catalog"] = function(data)
        local unlocked = {}
        for index = 1, #(data.products or {}) do
            local product = data.products[index]
            if type(product) == "table" and product.source == "unlocked" then
                local key = tostring(product.variantKey or product.id or "")
                if key ~= "" then unlocked[key] = copy(product) end
            end
        end
        instance.value.unlockedShopItems = unlocked
        instance.value.modular.shopCatalog = copy(data.products or {})
    end
    handlers["recycle.snapshot"] = function(data)
        merge(instance.value, data)
    end
    handlers["recycle.preference"] = function(data)
        if tostring(data.key or "") ~= "" then
            instance.value[data.key] = data.value
        end
        if data.autoRecycleUnlocked ~= nil then
            instance.value.waistAutoRecycleUnlocked =
                data.autoRecycleUnlocked == true
        end
    end
    handlers["upgrades.summary"] = function(data)
        instance.value.upgrades.carryCapacityLevel =
            math.max(0, math.floor(tonumber(data.carryCapacityLevel) or 0))
        instance.value.upgrades.maxActiveTasks =
            math.max(0, math.floor(tonumber(data.maxActiveTasks) or 0))
        instance.value.upgrades.dailyTaskCount =
            math.max(0, math.floor(tonumber(data.dailyTaskCount) or 0))
        instance.value.autoRecyclerCapacityLevel =
            math.max(1, math.floor(tonumber(data.terminalCapacityLevel) or 1))
        instance.value.autoRecyclerReductionLevel =
            math.max(1, math.floor(tonumber(data.terminalReductionLevel) or 1))
        instance.value.autoRecyclerReliefLevel =
            math.max(1, math.floor(tonumber(data.terminalReliefLevel) or 1))
    end
    handlers["home.snapshot"] = function(data)
        instance.value.homeSystem = copy(data.homeSystem or {})
    end
    handlers["terminal.status"] = function(data)
        instance.value.modular.terminal = copy(data)
        if type(data.state) == "table" then
            instance.value.autoRecyclerClaimed = data.state.claimedOnce == true
        end
    end
    handlers["storage.status"] = function(data)
        instance.value.modular.storage = copy(data)
    end
    handlers["companion.state"] = function(data)
        instance.value.companion = copy(data.persistent or {})
        instance.value.modular.companionRuntime = copy(data.runtime or {})
    end
    handlers["admin.snapshot"] = function(data)
        instance.value.adminConfig = copy(data)
    end

    function instance:apply(action, result)
        action = tostring(action or "")
        if type(result) ~= "table" or result.ok ~= true then
            self.value.modular.lastIssue = {
                action = action,
                code = type(result) == "table" and result.code or "resultInvalid",
                moduleId = type(result) == "table" and result.moduleId or "ui.readModel",
                operationId = type(result) == "table" and result.operationId or nil,
            }
            return false
        end
        local handler = handlers[action]
        if handler then handler(type(result.data) == "table" and result.data or {}) end
        applied(action)
        return true
    end

    function instance:get()
        return self.value
    end

    function instance:snapshot()
        return copy(self.value)
    end

    function instance:revision(action)
        return self.revisions[tostring(action or "")] or 0
    end

    return instance
end

return ReadModel
