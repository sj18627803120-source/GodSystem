GodSystemRecyclePayout = GodSystemRecyclePayout or {}

function GodSystemRecyclePayout.applyDaily(state, rawValue, day, softCap, diminishedValue)
    state = type(state) == "table" and state or {}
    rawValue = math.max(0, math.floor(tonumber(rawValue) or 0))
    day = math.floor(tonumber(day) or 0)
    softCap = math.max(0, math.floor(tonumber(softCap) or 0))
    diminishedValue = math.max(0, math.floor(tonumber(diminishedValue) or 1))

    if state.day ~= day then
        state.day = day
        state.used = 0
    end
    state.used = math.max(0, math.floor(tonumber(state.used) or 0))

    if rawValue <= 0 then return { payout = 0, diminished = false } end
    if softCap <= 0 then return { payout = rawValue, diminished = false } end

    local remaining = math.max(0, softCap - state.used)
    if remaining > 0 then
        local payout = math.min(rawValue, remaining)
        state.used = math.min(softCap, state.used + payout)
        return { payout = payout, diminished = payout < rawValue }
    end
    return { payout = diminishedValue, diminished = true }
end

function GodSystemRecyclePayout.deliver(payout, giveCurrency, addBank)
    payout = math.max(0, math.floor(tonumber(payout) or 0))
    if payout <= 0 then return { ok = true, bankFallback = 0 } end
    local paid = false
    if type(giveCurrency) == "function" then
        local ok, result = pcall(giveCurrency, payout)
        paid = ok and result == true
    end
    if paid then return { ok = true, bankFallback = 0 } end
    if type(addBank) == "function" then
        local ok, result = pcall(addBank, payout)
        if ok and result == true then return { ok = true, bankFallback = payout } end
    end
    return { ok = false, bankFallback = 0, code = "RecyclePayoutDeliveryFailed" }
end

return GodSystemRecyclePayout
