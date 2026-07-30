require "GodSystem/Platform/Commerce/Support"

local Support = GodSystemCommercePlatformSupport

local function snapshot(context, section)
    local root = type(context) == "table" and context.configSnapshot or nil
    root = type(root) == "table" and root or {}
    return Support.copy(type(root[section]) == "table" and root[section] or {})
end

GodSystemTasksConfigPlatform = GodSystemTasksConfigPlatform or {
    id = "tasks.config",
    dependencies = {},
    stateVersion = 1,
}

function GodSystemTasksConfigPlatform.create(_, context)
    local config = snapshot(context, "tasks")
    local instance = { started = false }
    instance.public = {
        getTemplates = function() return Support.copy(config.templates or {}) end,
        getDailyCount = function(_, data)
            local configured = Support.integer(config.dailyCount, 5, 0, 20)
            return Support.integer(data and data.upgrades and data.upgrades.dailyTaskCount,
                configured, 0, Support.integer(config.maxDailyCount, 20, 1))
        end,
        getMaxActive = function(_, data)
            local configured = Support.integer(config.maxActive, 3, 0, 10)
            return Support.integer(data and data.upgrades and data.upgrades.maxActiveTasks,
                configured, 0, Support.integer(config.maxActiveLimit, 10, 1))
        end,
        getDefaultLimitHours = function()
            return Support.integer(config.defaultLimitHours, 24, 1)
        end,
        getRefreshCost = function()
            return Support.integer(config.refreshCost, 0, 0)
        end,
    }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started and type(config.templates) == "table",
            code = type(config.templates) ~= "table" and "configMissing"
                or (self.started and "healthy" or "stopped"),
            data = { templates = #(config.templates or {}) },
            moduleId = GodSystemTasksConfigPlatform.id,
        }
    end
    return instance
end

GodSystemShopConfigPlatform = GodSystemShopConfigPlatform or {
    id = "shop.config",
    dependencies = { "shop.identity" },
    stateVersion = 1,
}

function GodSystemShopConfigPlatform.create(dependencies, context)
    local identity = assert(dependencies["shop.identity"], "shop.identity dependency missing")
    local config = snapshot(context, "shop")
    local products = type(config.products) == "table" and config.products or {}
    local byId, configuredKeys = {}, {}
    for index = 1, #products do
        local row = Support.copy(products[index])
        local id = tostring(row.id or "")
        if id ~= "" then
            byId[id] = row
            for itemIndex = 1, #(row.items or {}) do
                local item = row.items[itemIndex]
                if #(row.items or {}) == 1 and Support.integer(item.count, 1, 1) == 1 then
                    configuredKeys[identity.variantKey(item.fullType, item.worldSprite)] = true
                end
            end
        end
    end
    local instance = { started = false }
    instance.public = {
        resolveProduct = function(_, productId)
            local row = byId[tostring(productId or "")]
            if not row then return nil, "productMissing" end
            return Support.copy(row), "configured"
        end,
        configuredCandidates = function(_, category)
            category = tostring(category or "all")
            local result = {}
            for index = 1, #products do
                local row = products[index]
                if category == "all" or tostring(row.categoryKey or "normal") == category then
                    result[#result + 1] = Support.copy(row)
                end
            end
            return result
        end,
        isConfigured = function(variantKey)
            return configuredKeys[tostring(variantKey or "")] == true
        end,
        purchasePrice = function(_, product, quantity)
            return Support.integer(product and product.price, 0, 0)
                * Support.integer(quantity, 1, 1)
        end,
        listingPrice = function(_, item)
            local map = type(config.listingCostByFullType) == "table"
                and config.listingCostByFullType or {}
            return Support.integer(map[item.fullType] or item.listingPrice
                or config.defaultListingCost, 10, 0)
        end,
        lotteryPrice = function(_, category, count)
            local prices = type(config.lotteryPrices) == "table" and config.lotteryPrices or {}
            local unit = Support.integer(prices[category] or prices.all
                or config.defaultLotteryPrice, 100, 0)
            return unit * Support.integer(count, 1, 1)
        end,
    }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { products = #products },
            moduleId = GodSystemShopConfigPlatform.id,
        }
    end
    return instance
end

GodSystemRecycleConfigPlatform = GodSystemRecycleConfigPlatform or {
    id = "recycle.config",
    dependencies = {},
    stateVersion = 1,
}

function GodSystemRecycleConfigPlatform.create(_, context)
    local config = snapshot(context, "recycle")
    local prices = type(config.sellPrices) == "table" and config.sellPrices or {}
    local divisors = type(config.divisors) == "table" and config.divisors or {}
    local instance = { started = false }
    instance.public = {
        recycleValue = function(item)
            local base = Support.integer(prices[item.fullType] or item.sellPrice
                or item.value or config.defaultValue, 0, 0)
            if item.broken == true then base = math.floor(base * 0.5) end
            local used = tonumber(item.usedDelta)
            if used and used >= 0 and used <= 1 then base = math.floor(base * used) end
            return math.max(0, base)
        end,
        payout = function(groups, data)
            local total = 0
            for index = 1, #(groups or {}) do
                local row = groups[index]
                local divisor = Support.integer(divisors[row.fullType], 1, 1)
                total = total + math.floor((tonumber(row.rawValue) or 0) / divisor)
            end
            local limit = Support.integer(config.dailyLimit, 0, 0)
            local used = Support.integer(data and data.recycleLimitUsed, 0, 0)
            if limit > 0 then total = math.min(total, math.max(0, limit - used)) end
            return total, { recycleLimitUsed = used + total }
        end,
        listingPrice = function(item)
            local map = type(config.listingCostByFullType) == "table"
                and config.listingCostByFullType or {}
            local cost = Support.integer(map[item.fullType] or item.listingPrice
                or config.defaultListingCost, 10, 0)
            local buy = Support.integer(item.buyPrice,
                math.max(1, Support.integer(item.sellPrice or item.value, 1, 1)
                    * Support.integer(config.buyMultiplier, 4, 1)), 1)
            return cost, buy
        end,
    }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { configuredPrices = (function()
                local count = 0
                for _ in pairs(prices) do count = count + 1 end
                return count
            end)() },
            moduleId = GodSystemRecycleConfigPlatform.id,
        }
    end
    return instance
end

return {
    tasks = GodSystemTasksConfigPlatform,
    shop = GodSystemShopConfigPlatform,
    recycle = GodSystemRecycleConfigPlatform,
}
