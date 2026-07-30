require "GodSystem/Core/Result"

GodSystemModuleRegistry = GodSystemModuleRegistry or {}

local Registry = GodSystemModuleRegistry

local function traceback(message)
    if debug and debug.traceback then return debug.traceback(tostring(message or ""), 2) end
    return tostring(message or "")
end

local function boundaryCall(callback, ...)
    local args = { ... }
    local function invoke() return callback(unpack(args)) end
    if xpcall then return xpcall(invoke, traceback) end
    return pcall(invoke)
end

local function copyArray(source)
    local result = {}
    for i = 1, #(source or {}) do result[i] = tostring(source[i]) end
    return result
end

function Registry.new(options)
    options = options or {}
    local instance = {
        descriptors = {},
        modules = {},
        states = {},
        order = {},
        diagnostics = options.diagnostics,
        runtime = options.runtime or {},
    }

    local function setState(moduleId, state, code, detail)
        local row = instance.states[moduleId] or { moduleId = moduleId }
        row.state = state
        row.code = code
        row.detail = detail
        instance.states[moduleId] = row
        if instance.diagnostics and instance.diagnostics.setModuleStatus then
            instance.diagnostics:setModuleStatus(moduleId, row)
        end
        return row
    end

    function instance:register(descriptor)
        if type(descriptor) ~= "table" then return false, "descriptorRequired" end
        local moduleId = tostring(descriptor.id or "")
        if moduleId == "" then return false, "moduleIdRequired" end
        if self.descriptors[moduleId] then return false, "moduleAlreadyRegistered" end
        if type(descriptor.create) ~= "function" then return false, "moduleCreateRequired" end
        descriptor.dependencies = copyArray(descriptor.dependencies)
        descriptor.id = moduleId
        self.descriptors[moduleId] = descriptor
        setState(moduleId, "registered")
        return true
    end

    function instance:resolveOrder()
        local visiting, visited, result = {}, {}, {}
        local function visit(moduleId, chain)
            if visited[moduleId] then return true end
            if visiting[moduleId] then
                return false, "dependencyCycle", table.concat(chain, " -> ") .. " -> " .. moduleId
            end
            local descriptor = self.descriptors[moduleId]
            if not descriptor then return false, "dependencyMissing", moduleId end
            visiting[moduleId] = true
            chain[#chain + 1] = moduleId
            for i = 1, #descriptor.dependencies do
                local dependencyId = descriptor.dependencies[i]
                local ok, code, detail = visit(dependencyId, chain)
                if not ok then return false, code, detail end
            end
            chain[#chain] = nil
            visiting[moduleId] = nil
            visited[moduleId] = true
            result[#result + 1] = moduleId
            return true
        end
        for moduleId in pairs(self.descriptors) do
            local ok, code, detail = visit(moduleId, {})
            if not ok then return nil, code, detail end
        end
        self.order = result
        return result
    end

    function instance:start()
        local order, code, detail = self:resolveOrder()
        if not order then return GodSystemResult.fail("core", code, { detail = detail }) end
        for i = 1, #order do
            local moduleId = order[i]
            local descriptor = self.descriptors[moduleId]
            local dependencies = {}
            local blockedBy = nil
            for j = 1, #descriptor.dependencies do
                local dependencyId = descriptor.dependencies[j]
                local dependencyState = self.states[dependencyId]
                if not dependencyState or dependencyState.state ~= "started" then
                    blockedBy = dependencyId
                    break
                end
                dependencies[dependencyId] = self.modules[dependencyId]
            end
            if blockedBy then
                setState(moduleId, "blocked", "dependencyUnavailable", { dependency = blockedBy })
            else
                setState(moduleId, "starting")
                local okCreate, moduleOrError = boundaryCall(descriptor.create, dependencies, self.runtime)
                if not okCreate or type(moduleOrError) ~= "table" then
                    local message = okCreate and "moduleCreateDidNotReturnTable" or moduleOrError
                    setState(moduleId, "failed", "createFailed", { message = tostring(message) })
                    if self.diagnostics then
                        self.diagnostics:record({ moduleId = moduleId, stage = "create", code = "createFailed", message = message })
                    end
                else
                    self.modules[moduleId] = moduleOrError
                    local okStart, startResult = true, true
                    if type(moduleOrError.start) == "function" then
                        okStart, startResult = boundaryCall(moduleOrError.start, moduleOrError, self.runtime)
                    end
                    if not okStart or startResult == false then
                        local message = okStart and "moduleStartReturnedFalse" or startResult
                        setState(moduleId, "failed", "startFailed", { message = tostring(message) })
                        if self.diagnostics then
                            self.diagnostics:record({ moduleId = moduleId, stage = "start", code = "startFailed", message = message })
                        end
                    else
                        setState(moduleId, "started")
                    end
                end
            end
        end
        return GodSystemResult.ok("core", "started", { order = copyArray(order) })
    end

    function instance:stop(reason)
        for i = #self.order, 1, -1 do
            local moduleId = self.order[i]
            local module = self.modules[moduleId]
            if module and type(module.stop) == "function" then
                local ok, message = boundaryCall(module.stop, module, reason)
                if not ok and self.diagnostics then
                    self.diagnostics:record({ moduleId = moduleId, stage = "stop", code = "stopFailed", message = message })
                end
            end
            if self.states[moduleId] and self.states[moduleId].state == "started" then
                setState(moduleId, "stopped")
            end
        end
    end

    function instance:health()
        local report = {}
        for i = 1, #self.order do
            local moduleId = self.order[i]
            local module = self.modules[moduleId]
            local state = self.states[moduleId] or { state = "unknown" }
            local row = { moduleId = moduleId, state = state.state, code = state.code }
            if module and state.state == "started" and type(module.health) == "function" then
                local ok, value = boundaryCall(module.health, module)
                if ok then
                    row.health = GodSystemResult.normalize(value, moduleId)
                else
                    row.health = GodSystemResult.fail(moduleId, "healthFailed", { message = tostring(value) })
                    if self.diagnostics then
                        self.diagnostics:record({ moduleId = moduleId, stage = "health", code = "healthFailed", message = value })
                    end
                end
            end
            report[#report + 1] = row
        end
        return report
    end

    function instance:get(moduleId)
        return self.modules[tostring(moduleId or "")]
    end

    function instance:status(moduleId)
        return self.states[tostring(moduleId or "")]
    end

    return instance
end

