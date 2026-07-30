require "GodSystem/Platform/Storage/Support"

GodSystemStorageItemsPlatform = GodSystemStorageItemsPlatform or {}

local Descriptor = GodSystemStorageItemsPlatform
local Support = GodSystemStoragePlatformSupport

Descriptor.id = "storage.items"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local binding = Support.binding(context)
    local config = type(context.configSnapshot) == "table"
        and context.configSnapshot or {}
    local coreTokenKey = tostring(config.StorageCoreTokenKey
        or "GodSystemStorageCoreToken")
    local coreNetworkKey = tostring(config.StorageCoreNetworkKey
        or "GodSystemStorageCoreNetworkId")
    local protected = {
        ["GodSystem.SystemCoin1"] = true,
        ["GodSystem.SystemCoin10"] = true,
        ["GodSystem.SystemCoin100"] = true,
        ["GodSystem.SystemSpaceTerminal"] = true,
        ["GodSystem.SystemTerminalRelief"] = true,
        ["GodSystem.StorageController"] = true,
    }
    for _, fullType in ipairs(config.StorageProtectedFullTypes or {}) do
        protected[tostring(fullType)] = true
    end
    local counters = {
        classifications = 0, descriptions = 0, protected = 0, failures = 0,
    }
    local public = {}

    local function lower(value)
        return string.lower(tostring(value or ""))
    end

    local function hasText(value, pattern)
        return string.find(lower(value), lower(pattern), 1, true) ~= nil
    end

    local function instanceOf(item, className)
        local callback = type(binding.instanceof) == "function"
            and binding.instanceof or Support.api(binding, "instanceof")
        if type(callback) ~= "function" then return false end
        local called, value = pcall(callback, item, className)
        return called and value == true
    end

    local function equipped(actor, item)
        if Support.read(actor, { "getPrimaryHandItem" }, nil) == item
            or Support.read(actor, { "getSecondaryHandItem" }, nil) == item
            or Support.read(actor, { "isItemInBothHands" }, false, item) == true
            or Support.read(actor, { "isEquipped" }, false, item) == true
        then
            return true
        end
        for _, methodName in ipairs({ "getAttachedItems", "getWornItems" }) do
            local rows = Support.values(Support.read(actor, { methodName }, nil))
            for index = 1, #rows do
                local entry = rows[index]
                if (Support.read(entry, { "getItem" }, nil) or entry) == item then
                    return true
                end
            end
        end
        return false
    end

    local function isKey(item)
        local category = lower(Support.read(item, { "getCategory" }, ""))
        local fullType = lower(Support.fullType(item))
        return category == "key"
            or hasText(fullType, "keyring")
            or hasText(fullType, "key_ring")
    end

    local function itemStates(item, sourceContainer)
        local result, seen = {}, {}
        local function add(value)
            if value and not seen[value] then
                seen[value] = true
                result[#result + 1] = value
            end
        end
        if Support.read(item, { "isFavorite" }, false) == true then add("favorite") end
        local condition = Support.number(
            Support.read(item, { "getCondition" }, 100), 100) or 100
        local maximum = math.max(1, Support.number(
            Support.read(item, { "getConditionMax" }, 100), 100) or 100)
        if condition < maximum then add("damaged") end
        if condition / maximum <= 0.25 then add("lowCondition") end
        if Support.read(item, { "isCooked" }, false) == true
            or Support.read(item, { "isCooking" }, false) == true
        then
            add("cooking")
        end
        if Support.read(item, { "isFrozen" }, false) == true then add("frozen") end
        if Support.read(item, { "isRotten" }, false) == true then
            add("rotten")
        elseif Support.read(item, { "isStale" }, false) == true then
            add("stale")
        elseif public.category(item) == "perishable" then
            add("fresh")
        end
        local temperature = Support.number(
            Support.read(sourceContainer, { "getTemprature" }, 1), 1) or 1
        local containerType = lower(Support.read(sourceContainer, { "getType" }, ""))
        if hasText(containerType, "freezer") or temperature <= 0.25 then
            add("frozen")
        elseif hasText(containerType, "fridge") or temperature < 1 then
            add("chilled")
        end
        return result
    end

    local function modName(item)
        local scriptItem = Support.read(item, { "getScriptItem" }, nil)
        local module = Support.read(scriptItem, { "getModule" }, nil)
        local name = Support.read(module, { "getName" }, nil)
        if name ~= nil and tostring(name) ~= "" then return tostring(name) end
        return Support.fullType(item):match("^([^%.]+)%.") or "Base"
    end

    local function tags(item)
        local result = {}
        local scriptItem = Support.read(item, { "getScriptItem" }, nil)
        local rows = Support.values(Support.read(scriptItem, { "getTags" }, nil))
        for index = 1, math.min(#rows, 16) do
            result[#result + 1] = tostring(rows[index] or "")
        end
        return result
    end

    function public.id(item)
        return Support.itemId(item)
    end

    function public.category(item)
        counters.classifications = counters.classifications + 1
        local fullType = Support.fullType(item)
        local displayCategory = lower(
            Support.read(item, { "getDisplayCategory" }, ""))
        local itemType = lower(Support.read(item, { "getType" }, ""))
        if instanceOf(item, "Food") or hasText(displayCategory, "food") then
            local age = Support.number(Support.read(item, { "getAge" }, 0), 0) or 0
            local offAge = Support.number(
                Support.read(item, { "getOffAge" }, 1000000), 1000000) or 1000000
            if offAge < 1000000 or age > 0 then return "perishable" end
            return "food"
        end
        if hasText(displayCategory, "drink") or hasText(itemType, "water") then
            return "drink"
        end
        if hasText(displayCategory, "medical")
            or hasText(fullType, "Bandage")
            or hasText(fullType, "Pills")
        then
            return "medical"
        end
        if hasText(displayCategory, "ammo")
            or hasText(displayCategory, "ammunition")
        then
            return "ammo"
        end
        if hasText(displayCategory, "weapon")
            or Support.read(item, { "isAimedFirearm" }, false) == true
        then
            return "weapon"
        end
        if hasText(displayCategory, "tool") then return "tool" end
        if hasText(displayCategory, "clothing")
            or Support.read(item, { "getBodyLocation" }, nil) ~= nil
        then
            return "clothing"
        end
        if hasText(displayCategory, "literature")
            or hasText(displayCategory, "book")
        then
            return "book"
        end
        if hasText(displayCategory, "material")
            or hasText(displayCategory, "craft")
        then
            return "material"
        end
        if hasText(displayCategory, "furniture") or hasText(fullType, "Moveable") then
            return "furniture"
        end
        if Support.child(item) then return "container" end
        return "other"
    end

    function public.isProtected(item)
        if not item then return true end
        if protected[Support.fullType(item)] == true then
            counters.protected = counters.protected + 1
            return true
        end
        local data = Support.modData(item)
        if type(data) == "table"
            and (tostring(data[coreNetworkKey] or "") ~= ""
                or tostring(data[coreTokenKey] or "") ~= "")
        then
            counters.protected = counters.protected + 1
            return true
        end
        return false
    end

    function public.canDeposit(actor, item, mode)
        if not item or public.isProtected(item) then return false, "protected" end
        if tostring(mode or "") ~= "sourceAll" then return true end
        if Support.read(item, { "isFavorite" }, false) == true then
            return false, "favorite"
        end
        if isKey(item) then return false, "key" end
        if equipped(actor, item) then return false, "equipped" end
        return true
    end

    function public.describe(item, sourceLink, sourceContainer)
        counters.descriptions = counters.descriptions + 1
        local fullType = Support.fullType(item)
        local condition = Support.number(
            Support.read(item, { "getCondition" }, 100), 100) or 100
        local maximum = math.max(1, Support.number(
            Support.read(item, { "getConditionMax" }, 100), 100) or 100)
        local weight = Support.number(Support.read(item,
            { "getActualWeight", "getWeight" }, 0), 0) or 0
        local usedDelta = Support.number(
            Support.read(item, { "getUsedDelta" }, 1), 1) or 1
        local offAge = Support.number(
            Support.read(item, { "getOffAge" }, -1), -1) or -1
        local age = Support.number(Support.read(item, { "getAge" }, 0), 0) or 0
        local worldSprite = tostring(
            Support.read(item, { "getWorldSprite" }, "") or "")
        local groupKey = worldSprite ~= "" and (fullType .. "|" .. worldSprite)
            or fullType
        return {
            id = Support.itemId(item),
            groupKey = groupKey,
            fullType = fullType,
            name = tostring(Support.read(item,
                { "getDisplayName", "getName" }, fullType) or fullType),
            modName = modName(item),
            category = public.category(item),
            weight = math.max(0, weight),
            condition = condition,
            maxCondition = maximum,
            conditionRatio = condition / maximum,
            usedDelta = usedDelta,
            age = age,
            offAge = offAge,
            spoilageRemaining = offAge >= 0 and (offAge - age) or 1000000000,
            states = itemStates(item, sourceContainer),
            tags = tags(item),
            sourceLinkId = type(sourceLink) == "table" and sourceLink.linkId or nil,
            sourceName = type(sourceLink) == "table"
                and tostring(sourceLink.name or "") or "",
        }
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
