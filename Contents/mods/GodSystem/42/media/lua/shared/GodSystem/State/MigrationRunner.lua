require "GodSystem/State/Migration422011"

GodSystemMigrationRunner = GodSystemMigrationRunner or {}

local Runner = GodSystemMigrationRunner
local Migration = GodSystemMigration422011

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

local function disabledFrom(statuses)
    local disabled = {}
    for moduleId, row in pairs(type(statuses) == "table" and statuses or {}) do
        if type(row) == "table" and row.status == "failed" then
            disabled[moduleId] = { code = tostring(row.code or "migrationFailed") }
        end
    end
    return disabled
end

function Runner.run(options)
    options = type(options) == "table" and options or {}
    local adapter = options.adapter
    local root = adapter and type(adapter.load) == "function" and adapter:load() or {}
    if type(root) ~= "table" then root = {} end
    local snapshots = type(options.snapshots) == "table" and options.snapshots or {}
    local aggregate = {
        ok = true,
        code = "migrationNotRequired",
        actors = {},
        disabledModules = {},
        root = root,
    }

    for index = 1, #snapshots do
        local entry = snapshots[index]
        local snapshot = type(entry) == "table" and entry.snapshot or nil
        local actorKey = tostring(type(entry) == "table" and entry.actorKey or "local")
        if type(snapshot) == "table" then
            local result = Migration.run(snapshot, aggregate.root, {
                actorKey = actorKey,
                adminConfig = options.adminConfig,
            })
            aggregate.root = result.root
            aggregate.actors[actorKey] = {
                ok = result.ok,
                code = result.code,
                modules = copy(result.modules),
            }
            if result.ok ~= true then aggregate.ok = false end
            aggregate.code = aggregate.ok and "migrationComplete" or "migrationPartial"
            local disabled = disabledFrom(result.modules)
            for moduleId, reason in pairs(disabled) do
                aggregate.disabledModules[moduleId] = reason
            end
        end
    end

    if adapter and type(adapter.save) == "function" then
        local saved = adapter:save(aggregate.root)
        if saved ~= true then
            aggregate.ok = false
            aggregate.code = "migrationSaveFailed"
        end
    end
    return aggregate
end

return Runner
