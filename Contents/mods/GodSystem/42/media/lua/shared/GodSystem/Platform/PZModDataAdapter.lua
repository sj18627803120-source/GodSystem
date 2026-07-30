GodSystemPZModDataAdapter = GodSystemPZModDataAdapter or {}

local Adapter = GodSystemPZModDataAdapter

function Adapter.new(key, options)
    key = tostring(key or "")
    assert(key ~= "", "ModData key is required")
    options = options or {}
    local instance = {
        key = key,
        transmit = options.transmit == true,
    }

    function instance:load()
        if not ModData or type(ModData.getOrCreate) ~= "function" then
            return {}
        end
        return ModData.getOrCreate(self.key)
    end

    function instance:save(root)
        if not ModData or type(ModData.getOrCreate) ~= "function" then
            return false
        end
        local target = ModData.getOrCreate(self.key)
        if target ~= root then
            for field in pairs(target) do target[field] = nil end
            for field, value in pairs(type(root) == "table" and root or {}) do
                target[field] = value
            end
        end
        if self.transmit and type(ModData.transmit) == "function" then
            ModData.transmit(self.key)
        end
        return true
    end

    return instance
end

return Adapter
