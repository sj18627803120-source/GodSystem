GodSystemUIShellAdapter = GodSystemUIShellAdapter or {}

local ShellAdapter = GodSystemUIShellAdapter

local function primitive(value)
    local kind = type(value)
    return kind == "string" or kind == "number" or kind == "boolean"
        or kind == "nil"
end

local function copyPrimitives(source)
    local result = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        if type(key) == "string" and primitive(value) then result[key] = value end
    end
    return result
end

function ShellAdapter.new(options)
    options = type(options) == "table" and options or {}
    local facade = assert(options.facade, "UI shell facade required")
    local target = assert(options.target, "UI shell target required")
    local originalGetData = target.getData
    local originalSave = target.save
    local last = copyPrimitives(facade:data().ui)
    local instance = { installed = false }

    function instance:flushPreferences()
        local current = copyPrimitives(facade:data().ui)
        local keys = {}
        for key in pairs(last) do keys[key] = true end
        for key in pairs(current) do keys[key] = true end
        local changed = 0
        local values = {}
        for key in pairs(keys) do
            if current[key] ~= last[key] then
                values[key] = current[key]
                changed = changed + 1
            end
        end
        if changed <= 0 then return 0 end
        local previous = last
        last = current
        facade:setPreferences(values, {
            callback = function(result)
                if not result or result.ok ~= true then last = previous end
            end,
        })
        return changed
    end

    function instance:install()
        if self.installed then return true end
        target.getData = function() return facade:data() end
        target.save = function() return self:flushPreferences() end
        self.installed = true
        return true
    end

    function instance:stop()
        if not self.installed then return true end
        self:flushPreferences()
        self.installed = false
        return true
    end

    return instance
end

return ShellAdapter
