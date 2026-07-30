GodSystemPZEventSource = GodSystemPZEventSource or {}

local Source = GodSystemPZEventSource

function Source.new()
    local instance = {}

    function instance:add(eventName, handler)
        local event = Events and Events[tostring(eventName or "")] or nil
        if not event or type(event.Add) ~= "function" then
            return false, "eventUnavailable"
        end
        event.Add(handler)
        return true
    end

    function instance:remove(eventName, handler)
        local event = Events and Events[tostring(eventName or "")] or nil
        if not event or type(event.Remove) ~= "function" then
            return false, "eventUnavailable"
        end
        event.Remove(handler)
        return true
    end

    return instance
end

return Source
