require "GodSystem_ItemEligibility"
require "GodSystem_B42JavaCalls"
require "GodSystem_LotteryItemCache"

GodSystemLottery = GodSystemLottery or {}

local Lottery = GodSystemLottery
local Cache = GodSystemLotteryItemCache

Lottery.Tickets = {
    { id = "lottery_ticket_food", fullType = "GodSystem.LotteryTicketFood", kind = "random", draws = 1, price = 0, legacy = true },
    { id = "lottery_ticket_medical", fullType = "GodSystem.LotteryTicketMedical", kind = "random", draws = 1, price = 0, legacy = true },
    { id = "lottery_ticket_material", fullType = "GodSystem.LotteryTicketMaterial", kind = "random", draws = 1, price = 0, legacy = true },
    { id = "lottery_ticket_tool", fullType = "GodSystem.LotteryTicketTool", kind = "random", draws = 1, price = 0, legacy = true },
    { id = "lottery_ticket_weapon", fullType = "GodSystem.LotteryTicketWeapon", kind = "random", draws = 1, price = 0, legacy = true },
    { id = "lottery_ticket_random", fullType = "GodSystem.LotteryTicketRandom", kind = "random", draws = 1, price = 200 },
    { id = "lottery_ticket_ten_random", fullType = "GodSystem.LotteryTicketTenRandom", kind = "random", draws = 10, price = 1800 },
}

Lottery.TicketByFullType = {}
Lottery.TicketByShopId = {}
for index = 1, #Lottery.Tickets do
    local ticket = Lottery.Tickets[index]
    Lottery.TicketByFullType[ticket.fullType] = ticket
    Lottery.TicketByShopId[ticket.id] = ticket
end

local function compact(value)
    return tostring(value or ""):lower():gsub("[^a-z0-9]+", "")
end

local function scriptValue(scriptItem, methodName, fallback)
    if not scriptItem then return fallback end
    if GodSystemB42JavaCalls and GodSystemB42JavaCalls.value then
        return GodSystemB42JavaCalls.value(scriptItem, methodName, fallback)
    end
    local ok, value = pcall(function() return scriptItem[methodName](scriptItem) end)
    return ok and value or fallback
end

function Lottery.ticketForFullType(fullType)
    return Lottery.TicketByFullType[tostring(fullType or "")]
end

function Lottery.ticketForShopId(shopId)
    return Lottery.TicketByShopId[tostring(shopId or "")]
end

function Lottery.isTicket(fullType)
    return Lottery.ticketForFullType(fullType) ~= nil
end

local function forbiddenName(fullType)
    local lower = tostring(fullType or ""):lower()
    if lower == "base.testhotdrink" or lower == "base.testmug" or lower == "base.testwatermug" then return true end
    if lower:find("_dummy", 1, true) or lower:find("placeholder", 1, true)
        or lower:find("template", 1, true) or lower:find("unused", 1, true) then return true end
    return lower:find("zed_dmg", 1, true) ~= nil
end

function Lottery.isCandidate(fullType, scriptOrRow)
    fullType = tostring(fullType or (type(scriptOrRow) == "table" and scriptOrRow.fullType) or "")
    if fullType == "" or forbiddenName(fullType) then return false end
    if type(scriptOrRow) == "table" and scriptOrRow.fullType then
        if scriptOrRow.hidden == true or scriptOrRow.obsolete == true or scriptOrRow.eligible == false then return false end
        local category = compact(scriptOrRow.displayCategory)
        return category ~= "wound" and category ~= "zeddmg"
    end
    if not scriptOrRow then return false end
    if scriptValue(scriptOrRow, "isHidden", false) == true or scriptValue(scriptOrRow, "getObsolete", false) == true then return false end
    if GodSystemItemEligibility and GodSystemItemEligibility.isEconomicItemAllowed then
        return GodSystemItemEligibility.isEconomicItemAllowed(fullType, "lottery") == true
    end
    return true
end

function Lottery.classify(fullType, scriptItem)
    return Lottery.isCandidate(fullType, scriptItem) and "random" or nil
end

function Lottery.candidateRows()
    return Cache.candidateRows(function(row) return Lottery.isCandidate(row.fullType, row) end)
end

function Lottery.candidateTypes()
    local rows = Lottery.candidateRows()
    local result = {}
    for index = 1, #rows do result[#result + 1] = rows[index].fullType end
    return result
end

function Lottery.evict(fullType)
    Cache.evict(tostring(fullType or ""))
end

function Lottery.randomInteger(minimum, maximum)
    minimum = math.floor(tonumber(minimum) or 0)
    maximum = math.floor(tonumber(maximum) or minimum)
    if maximum <= minimum then return minimum end
    if ZombRand then
        local ok, value = pcall(ZombRand, minimum, maximum + 1)
        if ok and tonumber(value) then return math.max(minimum, math.min(maximum, math.floor(tonumber(value)))) end
    end
    return minimum
end

function Lottery.drawCandidate()
    local rows = Lottery.candidateRows()
    if #rows <= 0 then return nil end
    return rows[Lottery.randomInteger(1, #rows)].fullType
end

return Lottery
