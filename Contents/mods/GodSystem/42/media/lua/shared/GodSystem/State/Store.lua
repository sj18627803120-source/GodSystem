GodSystemStateStore = GodSystemStateStore or {}

local Store = GodSystemStateStore

local function copyTable(source, seen)
    if type(source) ~= "table" then return source end
    seen = seen or {}
    if seen[source] then return seen[source] end
    local result = {}
    seen[source] = result
    for key, value in pairs(source) do
        result[copyTable(key, seen)] = copyTable(value, seen)
    end
    return result
end

function Store.new(adapter, options)
    options = options or {}
    local instance = {
        adapter = adapter,
        schemaVersion = math.max(1, math.floor(tonumber(options.schemaVersion) or 1)),
        releaseVersion = tostring(options.releaseVersion or ""),
        root = nil,
    }

    function instance:load()
        if self.root then return self.root end
        local root = self.adapter and self.adapter.load and self.adapter:load() or {}
        if type(root) ~= "table" then root = {} end
        root.schemaVersion = math.max(1, math.floor(tonumber(root.schemaVersion) or self.schemaVersion))
        root.releaseVersion = tostring(root.releaseVersion or self.releaseVersion)
        root.modules = type(root.modules) == "table" and root.modules or {}
        root.migration = type(root.migration) == "table" and root.migration or {}
        self.root = root
        return root
    end

    function instance:scoped(moduleId, version)
        moduleId = tostring(moduleId or "")
        assert(moduleId ~= "", "moduleId required")
        version = math.max(1, math.floor(tonumber(version) or 1))
        local root = self:load()
        local row = root.modules[moduleId]
        if type(row) ~= "table" then
            row = { version = version, data = {} }
            root.modules[moduleId] = row
        end
        row.version = math.max(1, math.floor(tonumber(row.version) or version))
        row.data = type(row.data) == "table" and row.data or {}
        local scope = {}
        function scope:get() return row.data end
        function scope:version() return row.version end
        function scope:replace(data, nextVersion)
            row.data = type(data) == "table" and data or {}
            row.version = math.max(1, math.floor(tonumber(nextVersion) or row.version))
            return row.data
        end
        function scope:snapshot() return { version = row.version, data = copyTable(row.data) } end
        return scope
    end

    function instance:save()
        local root = self:load()
        root.releaseVersion = self.releaseVersion
        if self.adapter and self.adapter.save then return self.adapter:save(root) end
        return true
    end

    return instance
end
