GodSystemEventGateway = GodSystemEventGateway or {}

local Gateway = GodSystemEventGateway

local function sortedHandlers(rows)
    table.sort(rows, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        if a.moduleId ~= b.moduleId then return a.moduleId < b.moduleId end
        return a.order < b.order
    end)
    return rows
end

function Gateway.new(options)
    options = options or {}
    local instance = {
        diagnostics = options.diagnostics,
        subscriptions = {},
        dispatchers = {},
        sequence = 0,
    }

    function instance:dispatch(eventName, ...)
        local rows = self.subscriptions[eventName] or {}
        for i = 1, #rows do
            local row = rows[i]
            local ok, message = pcall(row.handler, ...)
            if not ok and self.diagnostics then
                self.diagnostics:record({
                    moduleId = row.moduleId,
                    stage = "event:" .. tostring(eventName),
                    code = "eventHandlerFailed",
                    message = message,
                })
            end
        end
    end

    function instance:subscribe(moduleId, eventName, handler, priority)
        moduleId, eventName = tostring(moduleId or ""), tostring(eventName or "")
        if moduleId == "" or eventName == "" or type(handler) ~= "function" then
            return false, "invalidSubscription"
        end
        self.sequence = self.sequence + 1
        local rows = self.subscriptions[eventName] or {}
        rows[#rows + 1] = {
            moduleId = moduleId,
            handler = handler,
            priority = tonumber(priority) or 0,
            order = self.sequence,
        }
        self.subscriptions[eventName] = sortedHandlers(rows)
        if not self.dispatchers[eventName] and Events and Events[eventName] and Events[eventName].Add then
            local function dispatcher(...) instance:dispatch(eventName, ...) end
            self.dispatchers[eventName] = dispatcher
            Events[eventName].Add(dispatcher)
        end
        return true
    end

    function instance:unsubscribeModule(moduleId)
        moduleId = tostring(moduleId or "")
        for eventName, rows in pairs(self.subscriptions) do
            for i = #rows, 1, -1 do
                if rows[i].moduleId == moduleId then table.remove(rows, i) end
            end
            if #rows == 0 then
                local dispatcher = self.dispatchers[eventName]
                if dispatcher and Events and Events[eventName] and Events[eventName].Remove then
                    Events[eventName].Remove(dispatcher)
                end
                self.dispatchers[eventName] = nil
            end
        end
    end

    function instance:stop()
        for eventName, dispatcher in pairs(self.dispatchers) do
            if Events and Events[eventName] and Events[eventName].Remove then
                Events[eventName].Remove(dispatcher)
            end
        end
        self.dispatchers = {}
        self.subscriptions = {}
    end

    function instance:health()
        local events, handlers = 0, 0
        for _, rows in pairs(self.subscriptions) do
            events = events + 1
            handlers = handlers + #rows
        end
        return { ok = true, code = "ok", data = { events = events, handlers = handlers } }
    end

    return instance
end

