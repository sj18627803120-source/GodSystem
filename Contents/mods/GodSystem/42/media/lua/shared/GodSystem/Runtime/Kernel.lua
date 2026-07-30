require "GodSystem/Composition"
require "GodSystem/Platform/PZEventSource"
require "GodSystem/Platform/PZCommandTransport"
require "GodSystem/Platform/PZModDataAdapter"
require "GodSystem/State/MigrationRunner"
require "GodSystem/Runtime/ConfigSnapshot"
require "GodSystem/Runtime/UseCaseDispatcher"

GodSystemRuntimeKernel = GodSystemRuntimeKernel or {}

local Kernel = GodSystemRuntimeKernel
local VERSION = "42.20.1.2"

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

local function environment()
    if type(isServer) == "function" and isServer() == true then return "server" end
    if type(isClient) == "function" and isClient() == true then return "client" end
    return "sp"
end

local function dataKey(env, base)
    base = tostring(base or "GodSystem_CN_Data")
    return base .. (env == "server" and "_MP_Modular422012" or "_Modular422012")
end

local function legacySnapshots(env, base)
    if not ModData or type(ModData.getOrCreate) ~= "function" then return {} end
    base = tostring(base or "GodSystem_CN_Data")
    if env == "sp" then
        return { { actorKey = "local", snapshot = ModData.getOrCreate(base) } }
    end
    if env == "server" then
        local source = ModData.getOrCreate(base .. "_MP")
        local result = {}
        for actorKey, snapshot in pairs(type(source.players) == "table" and source.players or {}) do
            result[#result + 1] = { actorKey = tostring(actorKey), snapshot = snapshot }
        end
        table.sort(result, function(left, right) return left.actorKey < right.actorKey end)
        return result
    end
    return {}
end

local function adminSnapshot(env, base)
    if env ~= "server" or not ModData or type(ModData.getOrCreate) ~= "function" then
        return nil
    end
    return ModData.getOrCreate(tostring(base or "GodSystem_CN_Data") .. "_MP_AdminConfig")
end

function Kernel.create(options)
    options = type(options) == "table" and options or {}
    local env = tostring(options.environment or environment())
    local base = tostring(options.dataKey or "GodSystem_CN_Data")
    local stateAdapter = options.stateAdapter
        or GodSystemPZModDataAdapter.new(dataKey(env, base), {
            transmit = env == "server",
        })
    local migration = GodSystemMigrationRunner.run({
        adapter = stateAdapter,
        snapshots = options.legacySnapshots or legacySnapshots(env, base),
        adminConfig = options.adminConfig or adminSnapshot(env, base),
    })
    local disabled = {}
    for moduleId, reason in pairs(migration.disabledModules or {}) do disabled[moduleId] = reason end
    for moduleId, reason in pairs(options.disabledModules or {}) do disabled[moduleId] = reason end
    local configSnapshot = options.configSnapshot or GodSystemConfigSnapshot.build({
        config = options.config,
        adminSettings = options.adminSettings,
        itemOverrides = options.itemOverrides,
    })
    local bindings = copy(options.bindings or {})
    local adminBinding = type(bindings["admin.source"]) == "table"
        and bindings["admin.source"] or {}
    adminBinding.defaults = adminBinding.defaults
        or copy(configSnapshot.admin and configSnapshot.admin.settings or {})
    adminBinding.staticOverrides = adminBinding.staticOverrides
        or copy(configSnapshot.admin and configSnapshot.admin.itemOverrides or {})
    bindings["admin.source"] = adminBinding

    local runtime = GodSystemComposition.create({
        version = VERSION,
        protocolVersion = VERSION,
        environment = env,
        adapters = {
            state = stateAdapter,
            events = options.eventAdapter or GodSystemPZEventSource.new(),
            commands = options.commandAdapter or GodSystemPZCommandTransport.new(),
        },
        bindings = bindings,
        configSnapshot = configSnapshot,
        descriptors = options.descriptors or {},
        disabledModules = disabled,
        migrationStatus = {
            ok = migration.ok,
            code = migration.code,
            actors = migration.actors,
        },
        start = options.start,
    })
    runtime.migrationResult = migration
    runtime.stateAdapter = stateAdapter
    runtime.save = function(self) return self.state:save() end
    runtime.dispatcher = GodSystemUseCaseDispatcher.new({
        protocolVersion = VERSION,
        routes = options.routes,
        diagnostics = runtime.diagnostics,
        resolve = function(moduleId) return runtime.registry:get(moduleId) end,
    })
    runtime.dispatch = function(self, packet, actor)
        local result = self.dispatcher:dispatch(packet, actor)
        local saved = self:save()
        if saved ~= true then
            self.diagnostics:record({
                moduleId = result.moduleId or "runtime",
                stage = "stateSave",
                code = "stateSaveFailed",
                operationId = result.operationId,
            })
            if result.ok == true then
                return GodSystemResult.fail(result.moduleId or "runtime",
                    "stateSaveFailed", { cause = result }, result.operationId)
            end
        end
        return result
    end
    return runtime
end

function Kernel.version() return VERSION end
function Kernel.environment() return environment() end

return Kernel
