-- Pure equipment rules. No inventory, events, network or disk work in this module.
require "GodSystem_EquipmentFreeze"
GodSystemEquipment = GodSystemEquipment or {}
local E = GodSystemEquipment
E.Schema = 1
E.ItemKey = "GodSystemEquipment"
E.CharacterKey = "GodSystemEquipmentCharacter"
E.MaxMoney = 2147483647
E.NameLimit = 30
E.Attributes = { "damage", "wear", "speed", "accuracy", "recoil", "freeze" }
-- Tooltip presentation is deliberately driven by the same ordered attribute
-- registry as equipment records.  New enhancements add their capability and
-- presentation here instead of teaching the Tooltip renderer another special
-- case.  "freeze" is the only current temporary area effect, so it has its
-- own wording and bounded-strength rule.
E.TooltipAttributes = {
    damage = { direction = "increase" },
    wear = { direction = "increase" },
    speed = { direction = "increase" },
    accuracy = { direction = "increase" },
    recoil = { direction = "decrease" },
    freeze = { direction = "freeze" },
}
E.Settings = {
    EquipmentMaxSlots = { 3, 1, 20, true },
    EquipmentSlotTaskBase = { 25, 0, 1000000, true },
    EquipmentSlotTaskMultiplier = { 2, 1, 10 },
    EquipmentFreezeRadius = { 3, 1, 10 },
    EquipmentFreezeSeconds = { 3, 0.1, 30 },
    EquipmentMaxLevel = { 999, 1, 9999, true },
    EquipmentGrowthPercent = { 10, 0.01, 100 },
    EquipmentBaseCost = { 100, 1, 1000000 },
    EquipmentCostExponent = { 1.5, 0.1, 3 },
    EquipmentBaseChance = { 100, 0.01, 100 },
    EquipmentChanceDecay = { 0.9, 0.001, 1 },
    EquipmentChanceFloor = { 1, 0.01, 100 },
    EquipmentBoostCost = { 100, 1, 1000000, true },
    EquipmentRepairCost = { 300, 1, 1000000, true },
    EquipmentRetrieveMultiplier = { 1, 0.01, 100 },
}

function E.number(value)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

function E.integer(value, minimum, maximum)
    local n = E.number(value)
    if not n or n ~= math.floor(n) or n < minimum or n > maximum then return nil end
    return n
end

function E.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = E.copy(v) end
    return result
end

-- Lua 5.1/Kahlua has no utf8 library.  Equipment names are a small,
-- user-authored input boundary, so keep decoding and validation shared by
-- the client hint and the SP/MP authority.
local function inputString(value)
    if type(value) == "string" then return value end
    -- B42's ISTextEntryBox returns java.lang.String userdata in Kahlua on
    -- some paths.  It is safe to stringify that one input boundary; tables,
    -- numbers and arbitrary request objects remain invalid.
    if type(value) == "userdata" then
        local ok, converted = pcall(tostring, value)
        if ok and type(converted) == "string" then return converted end
    end
    return nil
end

local function utf8Units(value)
    value = inputString(value)
    if not value or #value > 120 then return nil, "EquipmentNameInvalid" end
    local units, index = {}, 1
    while index <= #value do
        local first = value:byte(index)
        local count, code
        if first < 0x80 then count, code = 1, first
        elseif first >= 0xC2 and first <= 0xDF then
            local b = value:byte(index + 1)
            if not b or b < 0x80 or b > 0xBF then return nil, "EquipmentNameInvalid" end
            count, code = 2, (first - 0xC0) * 0x40 + (b - 0x80)
        elseif first >= 0xE0 and first <= 0xEF then
            local b, c = value:byte(index + 1), value:byte(index + 2)
            if not b or not c or b < 0x80 or b > 0xBF or c < 0x80 or c > 0xBF then return nil, "EquipmentNameInvalid" end
            code = (first - 0xE0) * 0x1000 + (b - 0x80) * 0x40 + (c - 0x80)
            if code < 0x800 or (code >= 0xD800 and code <= 0xDFFF) then return nil, "EquipmentNameInvalid" end
            count = 3
        else
            -- Four-byte sequences include emoji; unsupported in the first
            -- release so rendering and save behaviour stay predictable.
            return nil, "EquipmentNameInvalid"
        end
        if code <= 0x1F or (code >= 0x7F and code <= 0x9F) then return nil, "EquipmentNameInvalid" end
        units[#units + 1] = { code = code, text = value:sub(index, index + count - 1) }
        index = index + count
    end
    return units
end

function E.validateName(value)
    local units, err = utf8Units(value)
    if not units then return nil, err end
    local first, last = 1, #units
    local function trim(code) return code == 0x20 or code == 0xA0 or code == 0x3000 end
    while first <= last and trim(units[first].code) do first = first + 1 end
    while last >= first and trim(units[last].code) do last = last - 1 end
    local count = last - first + 1
    if count <= 0 then return nil, "EquipmentNameEmpty" end
    if count > E.NameLimit then return nil, "EquipmentNameTooLong" end
    local result = {}
    for index = first, last do result[#result + 1] = units[index].text end
    return table.concat(result)
end

function E.nameCharacterCount(value)
    local units = utf8Units(value)
    return units and #units or 0
end

function E.config(source)
    source = source or {}
    local cfg = { enabled = source.EnableEquipment ~= false,
        freezeEnabled = source.EnableEquipmentFreeze ~= false,
        freezeVisuals = source.EquipmentFreezeVisuals ~= false }
    for key, rule in pairs(E.Settings) do
        local n = source[key] == nil and rule[1] or E.number(source[key])
        if not n or n < rule[2] or n > rule[3] or (rule[4] and n ~= math.floor(n)) then
            return nil, "EquipmentConfigInvalid"
        end
        cfg[key] = n
    end
    if cfg.EquipmentChanceFloor > cfg.EquipmentBaseChance then return nil, "EquipmentConfigInvalid" end
    local keys, parts = {}, { "rules=5", tostring(cfg.enabled), tostring(cfg.freezeEnabled) }
    for key in pairs(E.Settings) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do parts[#parts + 1] = key .. "=" .. tostring(cfg[key]) end
    cfg.token = table.concat(parts, ";")
    return cfg
end

function E.slotTarget(slot, cfg)
    if not E.integer(slot, 1, 20) then return nil end
    local base = cfg and cfg.EquipmentSlotTaskBase or 25
    local multiplier = cfg and cfg.EquipmentSlotTaskMultiplier or 2
    if slot == 1 or base == 0 then return 0 end
    -- Out-of-exact-integer-range thresholds are unreachable, never wrapped.
    local target = math.ceil(base * multiplier ^ (slot - 2))
    return target <= 9007199254740000 and target or math.huge
end

function E.unlock(account, completed, cfg)
    completed = math.max(0, math.floor(E.number(completed) or 0))
    completed = math.max(account.completedTasks or 0, completed)
    local old = math.max(1, math.min(20, account.unlockedSlots or 1))
    local count = old
    for slot = 2, cfg.EquipmentMaxSlots do
        if completed >= E.slotTarget(slot, cfg) then count = math.max(count, slot) end
    end
    account.completedTasks = math.max(account.completedTasks or 0, completed)
    account.unlockedSlots = count
    if count ~= old then account.revision = account.revision + 1 end
    return count ~= old
end

function E.level(record, attribute)
    return E.integer(record and record.levels and record.levels[attribute], 0, 9999)
end

function E.growth(level, cfg)
    -- Add a fixed percentage of the saved baseline, never compound an applied value.
    local percent = cfg and cfg.EquipmentGrowthPercent or E.Settings.EquipmentGrowthPercent[1]
    return level * percent / 100
end

function E.multiplier(attribute, level, cfg)
    local growth = E.growth(level, cfg)
    return attribute == "recoil" and math.max(0, 1 - growth) or (1 + growth)
end

function E.supports(base, attribute)
    if not base then return false end
    if attribute == "damage" then return base.minDamage ~= nil and base.maxDamage ~= nil end
    if attribute == "wear" then return base.wear ~= nil end
    if attribute == "speed" then return not base.ranged and base.speed ~= nil end
    if attribute == "accuracy" then return base.ranged and base.accuracy ~= nil end
    if attribute == "recoil" then return base.ranged and base.recoil ~= nil end
    if attribute == "freeze" then return base.ranged == false end
    return false
end

-- A compact read-only description for Tooltip clients.  It contains no
-- inventory state or authority decision, only values already validated by a
-- projection.  Unknown future attributes fall back to the normal positive
-- percentage format once they are added to E.Attributes and E.supports().
function E.tooltipEntries(base, levels, cfg)
    local result = {}
    for _, attribute in ipairs(E.Attributes) do
        if E.supports(base, attribute) then
            local presentation = E.TooltipAttributes[attribute] or { direction = "increase" }
            local level = E.level({ levels = levels or {} }, attribute) or 0
            local active = cfg and cfg.enabled == true
            local percent = active and E.growth(level, cfg) * 100 or 0
            if presentation.direction == "freeze" then
                active = active and cfg.freezeEnabled == true
                percent = active and GodSystemEquipmentFreeze.strength(level, cfg) * 100 or 0
            end
            result[#result + 1] = { attribute = attribute, level = level,
                direction = presentation.direction, percent = percent }
        end
    end
    return result
end

function E.projectionLevels(record)
    local levels = {}
    for _, attribute in ipairs(E.Attributes) do levels[attribute] = E.level(record, attribute) or 0 end
    return levels
end

function E.values(base, levels, cfg)
    local v = E.copy(base)
    local function upgraded(key) return E.supports(base, key) and ((levels and levels[key]) or 0) > 0 end
    local function multiplier(key) return E.multiplier(key, levels[key], cfg) end
    if upgraded("damage") then
        v.minDamage = base.minDamage * multiplier("damage")
        v.maxDamage = base.maxDamage * multiplier("damage")
    end
    if upgraded("wear") then v.wear = math.max(1, math.floor(base.wear * multiplier("wear") + 0.5)) end
    if upgraded("speed") then v.speed = base.speed * multiplier("speed") end
    if upgraded("accuracy") then v.accuracy = math.max(base.accuracy, math.min(100, math.floor(base.accuracy * multiplier("accuracy") + 0.5))) end
    if upgraded("recoil") then v.recoil = math.max(1, math.floor(base.recoil * multiplier("recoil") + 0.5)) end
    return v
end

function E.quote(record, attribute, boost, cfg)
    if not cfg or not cfg.enabled then return nil, "EquipmentDisabled" end
    if attribute == "freeze" then
        if not cfg.freezeEnabled then return nil, "EquipmentFreezeDisabled" end
    end
    local level = E.level(record, attribute)
    if not level or not E.supports(record.base, attribute) then return nil, "EquipmentUnsupported" end
    if level >= cfg.EquipmentMaxLevel then return nil, "EquipmentLevelCap" end
    if attribute == "freeze" and GodSystemEquipmentFreeze.strength(level,cfg) >= GodSystemEquipmentFreeze.Maximum then
        return nil, "EquipmentParameterCap"
    end
    local current = E.values(record.base, record.levels, cfg)
    local actual = record.actual or current
    if (attribute == "accuracy" and (current.accuracy >= 100 or actual.accuracy >= 100))
        or (attribute == "recoil" and (current.recoil <= 1 or actual.recoil <= 1)) then return nil, "EquipmentParameterCap" end
    local bp = math.max(math.floor(cfg.EquipmentChanceFloor * 100 + 0.5),
        math.floor(cfg.EquipmentBaseChance * 100 * cfg.EquipmentChanceDecay ^ level + 0.5))
    local maxBoost = (10000 - bp) / 100
    boost = E.number(boost or 0)
    if not boost or boost < 0 or boost > 100 then return nil, "EquipmentBoostInvalid" end
    local boostBP = math.floor(boost * 100 + 0.5)
    if math.abs(boost * 100 - boostBP) > 0.000001 or boostBP > 10000 - bp then return nil, "EquipmentBoostInvalid" end
    local baseCost = math.ceil(cfg.EquipmentBaseCost * (level + 1) ^ cfg.EquipmentCostExponent)
    -- The last fractional percentage point is charged proportionally, rounded
    -- up to a whole coin. UI and authority use the same integer BP arithmetic.
    local boostCost = math.ceil(boostBP * cfg.EquipmentBoostCost / 100)
    local cost = baseCost + boostCost
    if not E.integer(cost, 1, E.MaxMoney) then return nil, "EquipmentCostInvalid" end
    local nextLevels = E.copy(record.levels)
    nextLevels[attribute] = level + 1
    return { cost = cost, baseCost = baseCost, boostCost = boostCost, boost = boostBP / 100,
        chanceBP = bp + boostBP, baseChanceBP = bp, maxBoost = maxBoost,
        level = level, current = current, next = E.values(record.base, nextLevels, cfg), configToken = cfg.token }
end

function E.quoteTarget(record, attribute, target, cfg)
    local quote, err = E.quote(record, attribute, 0, cfg)
    if not quote then return nil, err end
    if target == nil or (type(target) == "string" and target:match("^%s*$")) then return quote end
    local n = E.number(target)
    if not n or n < 0 or n > 100 then return nil, "EquipmentBoostInvalid" end
    local targetBP = math.floor(n * 100 + 0.5)
    if math.abs(n * 100 - targetBP) > 0.000001 then return nil, "EquipmentBoostInvalid" end
    return E.quote(record, attribute, math.max(0, targetBP - quote.baseChanceBP) / 100, cfg)
end

function E.newLevels(base)
    local levels = {}
    for _, key in ipairs(E.Attributes) do if E.supports(base, key) then levels[key] = 0 end end
    return levels
end

function E.normalizeRecord(record)
    -- Authority-only additive migration. Do not repair corrupt existing values.
    if type(record)=="table" and record.state=="active" and type(record.levels)=="table"
        and E.supports(record.base,"freeze") and record.levels.freeze==nil then
        record.levels.freeze=0
    end
    if type(record) == "table" and record.customName ~= nil and type(record.customName) ~= "string" then
        record.customName = nil
    end
end

function E.fingerprint(args)
    local fields = { "action", "mode", "name", "slot", "equipmentId", "itemId", "generation", "attribute", "boost", "revision", "recordRevision", "cost", "configToken" }
    local parts = {}
    for _, key in ipairs(fields) do
        local value = args[key]
        if value ~= nil and type(value) ~= "string" and type(value) ~= "number" then return nil end
        if type(value) == "number" and not E.number(value) then return nil end
        local s = value == nil and "" or tostring(value)
        if #s > 2048 then return nil end
        parts[#parts + 1] = key .. ":" .. #s .. ":" .. s
    end
    return table.concat(parts, "|")
end

-- Keep the archive validator as the single definition of a supported bound
-- weapon.  Binding calls this before it writes an item marker, while archive
-- loading uses the same result to isolate a bad slot instead of poisoning the
-- whole account.
function E.validateRecord(record, owner)
    if type(record) ~= "table" or type(record.base) ~= "table" or type(record.levels) ~= "table"
        or type(record.id) ~= "string" or type(record.itemId) ~= "string" or type(record.fullType) ~= "string"
        or type(record.ownerKey) ~= "string" or type(record.characterId) ~= "string"
        then return false, "identity", "record" end
    if owner and owner ~= record.ownerKey then return false, "owner", "ownerKey" end
    if not E.integer(record.generation, 1, E.MaxMoney)
        or not E.integer(record.revision, 1, 9007199254740000)
        or (record.state ~= "active" and record.state ~= "retired") then return false, "identity", "state" end
    for _, key in ipairs({ "minDamage", "maxDamage", "wear", "speed", "accuracy", "recoil" }) do
        if record.base[key] ~= nil and (not E.number(record.base[key]) or record.base[key] < 0 or record.base[key] > E.MaxMoney) then
            return false, "base", key
        end
    end
    if not record.base.minDamage or not record.base.maxDamage or record.base.maxDamage < record.base.minDamage then
        return false, "base", "damage"
    end
    if record.state == "active" then
        for _, key in ipairs(E.Attributes) do
            if E.supports(record.base, key) and not E.level(record, key) then return false, "levels", key end
        end
        local d = record.durability
        if type(d) ~= "table" or not E.integer(d.conditionMax,1,127) or not E.integer(d.condition,0,d.conditionMax) then
            return false, "durability", "condition"
        end
        if d.hasHead and (not E.integer(d.headConditionMax,1,E.MaxMoney) or not E.integer(d.headCondition,0,d.headConditionMax)) then
            return false, "durability", "headCondition"
        end
        if d.hasSharpness and (not E.number(d.sharpness) or d.sharpness < 0 or d.sharpness > 1) then
            return false, "durability", "sharpness"
        end
    end
    return true, nil, nil
end

function E.validRecord(record, owner)
    local valid = E.validateRecord(record, owner)
    return valid == true
end

function E.beforeRemoval(item)
    if not GodSystemEquipmentItems or not GodSystemEquipmentItems.marker(item) then return end
    local service = GodSystemServer and GodSystemServer.equipment
        or (GodSystemEquipmentClient and GodSystemEquipmentClient.authority)
    if service then service:observe(item) end
end

function E.taskCompleted(player)
    local service = GodSystemServer and GodSystemServer.equipment
        or (GodSystemEquipmentClient and GodSystemEquipmentClient.authority)
    if service and player then service:account(player) end
end

return E
