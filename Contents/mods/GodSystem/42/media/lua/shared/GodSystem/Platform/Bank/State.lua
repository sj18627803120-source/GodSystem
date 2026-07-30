require "GodSystem/Platform/Bank/Support"

GodSystemBankStatePlatform = GodSystemBankStatePlatform or {}

local Descriptor = GodSystemBankStatePlatform
local Support = GodSystemBankPlatformSupport

Descriptor.id = "bank.state"
Descriptor.dependencies = { "wallet.accounts" }
Descriptor.stateVersion = 1

function Descriptor.create(dependencies, context)
    context = context or {}
    local accounts = assert(dependencies["wallet.accounts"], "wallet.accounts dependency missing")
    local root = assert(context.state, "bank.state context.state missing"):get()
    local binding = type(context.binding) == "table" and context.binding or {}
    root.players = type(root.players) == "table" and root.players or {}
    local instance = { started = false, loads = 0, commits = 0, rollbacks = 0 }

    local function key(actor)
        return accounts.key(actor)
    end

    local function stored(actor)
        local accountKey = key(actor)
        local row = root.players[accountKey]
        if type(row) ~= "table" then
            row = {}
            root.players[accountKey] = row
        end
        if row.current ~= nil then
            local migrated = Support.integer(row.current, 0, 0)
            accounts.set(actor, migrated)
            row.current = nil
        end
        return row, accountKey
    end

    local function load(actor)
        instance.loads = instance.loads + 1
        local row = stored(actor)
        local result = Support.copy(row)
        result.current = Support.integer(accounts.get(actor), 0, 0)
        return result
    end

    local function commit(actor, value, request)
        if type(value) ~= "table" then return false, "stateInvalid" end
        local current = tonumber(value.current)
        if not current or current ~= current or current == math.huge
            or current == -math.huge or current < 0
        then
            return false, "stateInvalid"
        end
        current = math.floor(current)
        local previous, accountKey = stored(actor)
        previous = Support.copy(previous)
        local previousCurrent = Support.integer(accounts.get(actor), 0, 0)
        local nextRow = Support.copy(value)
        nextRow.current = nil

        if accounts.set(actor, current) ~= true then return false, "accountCommitFailed" end
        root.players[accountKey] = nextRow

        if type(binding.commit) == "function" then
            local ok, committed, code, data = pcall(
                binding.commit, actor, Support.copy(nextRow), current, request)
            if not ok or committed ~= true then
                accounts.set(actor, previousCurrent)
                root.players[accountKey] = previous
                instance.rollbacks = instance.rollbacks + 1
                return false, code or "stateCommitFailed", data or {
                    message = ok and nil or tostring(committed),
                }
            end
        end

        instance.commits = instance.commits + 1
        return true
    end

    local public = {}
    public.load = function(first, second)
        return load(first == public and second or first)
    end
    public.commit = function(first, second, third, fourth)
        if first == public then return commit(second, third, fourth) end
        return commit(first, second, third)
    end
    instance.public = public
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = {
                loads = self.loads,
                commits = self.commits,
                rollbacks = self.rollbacks,
            },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
