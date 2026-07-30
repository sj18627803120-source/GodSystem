require "GodSystem/Composition"
require "GodSystem/Platform/PZEventSource"
require "GodSystem/Platform/PZCommandTransport"
require "GodSystem/Platform/PZModDataAdapter"
require "GodSystem/State/MigrationRunner"

GodSystemRuntimeKernel = GodSystemRuntimeKernel or {}

local Kernel = GodSystemRuntimeKernel
local VERSION = "42.20.1.2"

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

    local runtime = GodSystemComposition.create({
        version = VERSION,
        protocolVersion = VERSION,
        environment = env,
        adapters = {
            state = stateAdapter,
            events = options.eventAdapter or GodSystemPZEventSource.new(),
            commands = options.commandAdapter or GodSystemPZCommandTransport.new(),
        },
        bindings = options.bindings or {},
        configSnapshot = options.configSnapshot or {},
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
    return runtime
end

function Kernel.version() return VERSION end
function Kernel.environment() return environment() end

return Kernel
