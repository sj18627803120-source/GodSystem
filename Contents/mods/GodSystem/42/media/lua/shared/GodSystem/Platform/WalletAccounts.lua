GodSystemWalletAccountsPlatform = GodSystemWalletAccountsPlatform or {}

local Descriptor = GodSystemWalletAccountsPlatform
local MAX_SAFE_INTEGER = 9007199254740991

Descriptor.id = "wallet.accounts"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local function integer(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    if value > MAX_SAFE_INTEGER then value = MAX_SAFE_INTEGER end
    if value < -MAX_SAFE_INTEGER then value = -MAX_SAFE_INTEGER end
    return math.floor(value)
end

local function actorKey(actor, binding)
    if binding and type(binding.identity) == "function" then
        local value = binding.identity(actor)
        if value ~= nil and tostring(value) ~= "" then return tostring(value) end
    end
    if actor and type(actor.getUsername) == "function" then
        local username = actor:getUsername()
        if username ~= nil and tostring(username) ~= "" then return tostring(username) end
    end
    if actor and type(actor.getOnlineID) == "function" then
        local onlineId = actor:getOnlineID()
        if onlineId ~= nil then return "id:" .. tostring(onlineId) end
    end
    if type(actor) == "string" or type(actor) == "number" then
        return tostring(actor)
    end
    return "local"
end

function Descriptor.create(_, context)
    context = context or {}
    local binding = type(context.binding) == "table" and context.binding or {}
    local state = assert(context.state, "wallet.accounts context.state missing"):get()
    state.accounts = type(state.accounts) == "table" and state.accounts or {}
    local instance = { started = false, reads = 0, writes = 0 }
    local public = {}

    local function arguments(first, second, third)
        if first == public then return second, third end
        return first, second
    end

    local function key(actor)
        return actorKey(actor, binding)
    end

    local function row(actor)
        local accountKey = key(actor)
        local value = state.accounts[accountKey]
        if type(value) ~= "table" then
            local initial = 0
            if type(binding.initialBalance) == "function" then
                initial = integer(binding.initialBalance(actor, accountKey)) or 0
            elseif type(binding.initialBalances) == "table" then
                initial = integer(binding.initialBalances[accountKey]) or 0
            end
            value = { current = math.max(0, initial) }
            state.accounts[accountKey] = value
        end
        value.current = math.max(0, integer(value.current) or 0)
        return value, accountKey
    end

    public = {
        key = function(first, second)
            local actor = first == public and second or first
            return key(actor)
        end,
        get = function(first, second)
            local actor = first == public and second or first
            instance.reads = instance.reads + 1
            return row(actor).current
        end,
        set = function(first, second, third)
            local actor, amount = arguments(first, second, third)
            amount = integer(amount)
            if not amount or amount < 0 then return false, "amountInvalid" end
            row(actor).current = amount
            instance.writes = instance.writes + 1
            return true
        end,
        debit = function(first, second, third)
            local actor, amount = arguments(first, second, third)
            amount = integer(amount)
            if not amount or amount < 0 then return false, "amountInvalid" end
            local account = row(actor)
            if account.current < amount then return false, "balanceInsufficient" end
            account.current = account.current - amount
            instance.writes = instance.writes + 1
            return true
        end,
        credit = function(first, second, third)
            local actor, amount = arguments(first, second, third)
            amount = integer(amount)
            if not amount or amount < 0 then return false, "amountInvalid" end
            local account = row(actor)
            if account.current > MAX_SAFE_INTEGER - amount then
                return false, "balanceOverflow"
            end
            account.current = account.current + amount
            instance.writes = instance.writes + 1
            return true
        end,
    }
    instance.public = public

    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { reads = self.reads, writes = self.writes },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
