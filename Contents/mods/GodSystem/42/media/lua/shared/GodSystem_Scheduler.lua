GodSystemScheduler = GodSystemScheduler or {}

local Scheduler = GodSystemScheduler
Scheduler.deadlines = Scheduler.deadlines or {}

function Scheduler.nowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Scheduler.due(key, intervalMs, currentMs)
    key = tostring(key or "default")
    local now = tonumber(currentMs) or Scheduler.nowMs()
    local interval = math.max(1, math.floor(tonumber(intervalMs) or 1))
    local deadline = tonumber(Scheduler.deadlines[key])
    if deadline and now >= 0 and now < deadline and deadline - now <= interval then return false end
    Scheduler.deadlines[key] = now + interval
    return true
end

function Scheduler.reset(prefix)
    if prefix == nil or tostring(prefix) == "" then
        Scheduler.deadlines = {}
        return
    end
    prefix = tostring(prefix)
    for key in pairs(Scheduler.deadlines) do
        if string.sub(key, 1, #prefix) == prefix then Scheduler.deadlines[key] = nil end
    end
end

function Scheduler.resetKey(key)
    if key == nil then return end
    Scheduler.deadlines[tostring(key)] = nil
end

return Scheduler
