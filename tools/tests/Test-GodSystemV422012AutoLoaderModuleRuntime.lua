local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

require "GodSystem/Core/Result"
require "GodSystem/Features/AutoLoader/Module"

local Descriptor = assert(GodSystemAutoLoaderFeatureModule)
assert(Descriptor.id == "feature.autoloader", "auto-loader module id changed")

local function removeValue(values, target)
    for index = 1, #values do
        if values[index] == target then
            table.remove(values, index)
            return index
        end
    end
    return nil
end

local function newFixture(environment, options)
    options = options or {}
    local actor = { id = "player-1" }
    local loader = { id = "10", kind = "loader", store = {}, names = {} }
    local ammo9 = { id = "20", kind = "ammo", fullType = "Base.Bullets9mm", name = "9mm" }
    local ammo45 = { id = "21", kind = "ammo", fullType = "Base.Bullets45", name = ".45" }
    local favorite = {
        id = "22", kind = "ammo", fullType = "Base.Bullets9mm", name = "favorite", favorite = true,
    }
    local protected = {
        id = "23", kind = "ammo", fullType = "Base.Bullets9mm", name = "protected", protected = true,
    }
    local magazine9 = {
        id = "30", kind = "magazine", ammoType = "Base.Bullets9mm", rounds = 2, maximum = 5,
    }
    local magazine45 = {
        id = "31", kind = "magazine", ammoType = "Base.Bullets45", rounds = 0, maximum = 2,
    }
    local carried = { loader, ammo9, ammo45, favorite, protected, magazine9, magazine45 }
    local sessionRows, operationRows = {}, {}
    local state = {
        environment = environment,
        carried = carried,
        sessions = sessionRows,
        operations = operationRows,
        now = 1000,
        notifications = {},
        sync = {},
        removeCalls = 0,
        createCalls = 0,
        failStore = false,
        failRestoreAmmo = false,
        failSetMagazine = false,
        failRestoreMagazine = false,
        failRemoveCreated = false,
    }

    local function recordSync(kind)
        state.sync[#state.sync + 1] = environment .. ":" .. kind
        return true
    end

    local query = {
        resolveItem = function(owner, itemId)
            assert(owner == actor, "resolveItem actor mismatch")
            for index = 1, #carried do
                if tostring(carried[index].id) == tostring(itemId) then return carried[index] end
            end
            return nil, "itemMissing"
        end,
        resolveLoader = function(owner, loaderId)
            assert(owner == actor, "resolveLoader actor mismatch")
            for index = 1, #carried do
                local item = carried[index]
                if item.kind == "loader" and tostring(item.id) == tostring(loaderId) then return item end
            end
            return nil, "NotCarried"
        end,
        scanCarried = function(owner)
            assert(owner == actor, "scanCarried actor mismatch")
            local values = {}
            for index = 1, #carried do values[index] = carried[index] end
            return values, { limitSkipped = 0 }
        end,
        scanLoaders = function(owner, maximum)
            assert(owner == actor, "scanLoaders actor mismatch")
            local values = {}
            for index = 1, #carried do
                if carried[index].kind == "loader" and #values < maximum then
                    values[#values + 1] = carried[index]
                end
            end
            return values, false
        end,
        scanMagazines = function(owner, maximum)
            assert(owner == actor, "scanMagazines actor mismatch")
            local values, total = {}, 0
            for index = 1, #carried do
                if carried[index].kind == "magazine" then
                    total = total + 1
                    if #values < maximum then values[#values + 1] = carried[index] end
                end
            end
            return values, total > maximum
        end,
        isCarried = function(owner, item)
            assert(owner == actor, "isCarried actor mismatch")
            for index = 1, #carried do if carried[index] == item then return true end end
            return false
        end,
        ownerKey = function(owner)
            assert(owner == actor, "ownerKey actor mismatch")
            return actor.id
        end,
    }

    local mutation = {
        removeAmmo = function(owner, item)
            assert(owner == actor and item.kind == "ammo", "removeAmmo arguments mismatch")
            state.removeCalls = state.removeCalls + 1
            local index = removeValue(carried, item)
            if not index then return false, "removeFailed" end
            return true, { item = item, index = index }
        end,
        restoreAmmo = function(owner, receipt)
            assert(owner == actor and receipt.item, "restoreAmmo arguments mismatch")
            if state.failRestoreAmmo then return false end
            table.insert(carried, math.min(receipt.index, #carried + 1), receipt.item)
            return true
        end,
        createAmmo = function(owner, fullType)
            assert(owner == actor, "createAmmo actor mismatch")
            state.createCalls = state.createCalls + 1
            local item = {
                id = "created-" .. tostring(state.createCalls),
                kind = "ammo",
                fullType = fullType,
                name = fullType,
            }
            carried[#carried + 1] = item
            return true, { item = item }
        end,
        removeCreated = function(owner, receipt)
            assert(owner == actor and receipt.item, "removeCreated arguments mismatch")
            if state.failRemoveCreated then return false end
            return removeValue(carried, receipt.item) ~= nil
        end,
        setMagazineRounds = function(owner, magazine, rounds)
            assert(owner == actor and magazine.kind == "magazine", "setMagazineRounds arguments mismatch")
            if state.failSetMagazine then return false end
            magazine.rounds = rounds
            return true
        end,
        restoreMagazineRounds = function(owner, magazine, rounds)
            assert(owner == actor and magazine.kind == "magazine", "restoreMagazineRounds arguments mismatch")
            if state.failRestoreMagazine then return false end
            magazine.rounds = rounds
            return true
        end,
    }

    local catalog = {
        itemId = function(item) return item and item.id end,
        fullType = function(item) return item and item.fullType end,
        displayName = function(value, fallback)
            if type(value) == "table" then return value.name or fallback end
            return fallback or value
        end,
        isLooseAmmo = function(item) return item and item.kind == "ammo" end,
        isFavorite = function(item) return item and item.favorite == true end,
        isProtected = function(item) return item and item.protected == true end,
        isAvailable = function(fullType)
            return fullType == "Base.Bullets9mm" or fullType == "Base.Bullets45"
        end,
        magazineAmmoType = function(item)
            return item and item.kind == "magazine" and item.ammoType or nil
        end,
        magazineRounds = function(item) return item and item.rounds or 0 end,
        magazineCapacity = function(item) return item and item.maximum or 0 end,
    }

    local store = {
        capacity = function() return options.capacity or 2000 end,
        getBalance = function(target, fullType) return target.store[fullType] or 0 end,
        setBalance = function(target, fullType, count, name)
            if state.failStore then return false, "storeRejected" end
            target.store[fullType] = count > 0 and count or nil
            if name then target.names[fullType] = name end
            return true
        end,
        entries = function(target)
            local rows = {}
            for fullType, count in pairs(target.store) do
                rows[#rows + 1] = {
                    fullType = fullType,
                    count = count,
                    name = target.names[fullType],
                }
            end
            return rows
        end,
    }

    local sessions = {
        nowMs = function() return state.now end,
        get = function(sessionId) return sessionRows[tostring(sessionId or "")] end,
        put = function(session)
            sessionRows[session.sessionId] = session
            return true
        end,
        remove = function(sessionId)
            sessionRows[tostring(sessionId or "")] = nil
            return true
        end,
        cleanup = function(now)
            local removed = 0
            for sessionId, session in pairs(sessionRows) do
                if now > session.expiresAt then sessionRows[sessionId] = nil; removed = removed + 1 end
            end
            return removed
        end,
    }

    local operations = {
        begin = function(moduleId, action, operationId, fingerprint)
            assert(moduleId == Descriptor.id, "operation module mismatch")
            local row = operationRows[operationId]
            if row then
                if row.fingerprint ~= fingerprint then return row, "mismatch" end
                return row, row.status
            end
            row = { action = action, fingerprint = fingerprint, status = "new" }
            operationRows[operationId] = row
            return row, "new"
        end,
        finish = function(row, value)
            row.result = value
            row.status = "done"
            return true
        end,
    }

    local synchronization = {
        loader = function() return recordSync("loader") end,
        magazine = function() return recordSync("magazine") end,
        created = function() return recordSync("created") end,
        removed = function() return recordSync("removed") end,
        restored = function() return recordSync("restored") end,
    }

    local notifications = {
        publish = function(value)
            state.notifications[#state.notifications + 1] = value
            return true
        end,
    }

    local module = Descriptor.create({
        ["autoloader.inventory.query"] = query,
        ["autoloader.inventory.mutation"] = mutation,
        ["ammo.catalog"] = catalog,
        ["autoloader.store"] = store,
        ["autoloader.sessions"] = sessions,
        ["autoloader.operations"] = operations,
        ["autoloader.synchronization"] = synchronization,
        notifications = notifications,
    }, {
        moduleId = Descriptor.id,
        environment = environment,
    })
    assert(module:start(), "module did not start")

    return {
        actor = actor,
        loader = loader,
        ammo9 = ammo9,
        ammo45 = ammo45,
        favorite = favorite,
        protected = protected,
        magazine9 = magazine9,
        magazine45 = magazine45,
        state = state,
        module = module,
    }
end

local function carriedCount(fixture, fullType)
    local count = 0
    for index = 1, #fixture.state.carried do
        if fixture.state.carried[index].fullType == fullType then count = count + 1 end
    end
    return count
end

local function successSignature(environment)
    local fixture = newFixture(environment)
    local started = fixture.module.public.startDeposit({
        actor = fixture.actor,
        loaderId = fixture.loader.id,
        operationId = environment .. "-deposit",
    })
    assert(started.ok and started.code == "DepositStarted", "deposit session did not start")
    assert(started.data.total == 2 and started.data.skipped == 2,
        "deposit scan did not preserve favorite/protected rules")
    assert(fixture.state.carried[3] == fixture.ammo45, "deposit scan mutated inventory")

    local settled = fixture.module.public.completeDepositBatch({
        actor = fixture.actor,
        sessionId = started.data.sessionId,
        batchIndex = 1,
    })
    assert(settled.ok and settled.code == "DepositComplete", "deposit batch did not complete")
    assert(settled.data.aggregate.stored == 2, "deposit stored count changed")
    assert(fixture.loader.store["Base.Bullets9mm"] == 1
        and fixture.loader.store["Base.Bullets45"] == 1, "deposit balances changed")
    assert(carriedCount(fixture, "Base.Bullets9mm") == 2,
        "favorite/protected inventory state was not preserved")

    local fill = fixture.module.public.manualFill({
        actor = fixture.actor,
        loaderId = fixture.loader.id,
        operationId = environment .. "-fill",
    })
    assert(fill.ok and fill.code == "FillInsufficient", "manual fill result changed")
    assert(fill.data.rounds == 2 and fixture.magazine9.rounds == 3
        and fixture.magazine45.rounds == 1, "manual fill did not apply stored ammunition")

    fixture.loader.store["Base.Bullets9mm"] = 3
    local beforeCreated = carriedCount(fixture, "Base.Bullets9mm")
    local withdrawal = fixture.module.public.withdraw({
        actor = fixture.actor,
        loaderId = fixture.loader.id,
        fullType = "Base.Bullets9mm",
        count = 2,
        operationId = environment .. "-withdraw",
    })
    assert(withdrawal.ok and withdrawal.code == "WithdrawSuccess"
        and withdrawal.data.created == 2, "withdraw result changed")
    assert(fixture.loader.store["Base.Bullets9mm"] == 1, "withdraw balance changed")

    local replay = fixture.module.public.withdraw({
        actor = fixture.actor,
        loaderId = fixture.loader.id,
        fullType = "Base.Bullets9mm",
        count = 2,
        operationId = environment .. "-withdraw",
    })
    assert(replay == withdrawal, "completed operation was not replayed")
    assert(carriedCount(fixture, "Base.Bullets9mm") == beforeCreated + 2,
        "operation replay duplicated ammunition")

    fixture.loader.store["Base.Bullets9mm"] = 2
    fixture.loader.store["Base.Bullets45"] = 1
    local post = fixture.module.public.postReload({
        actor = fixture.actor,
        operationId = environment .. "-reload",
    })
    assert(post.ok and post.code == "FillSuccess" and post.data.silent == true,
        "post-reload result changed")
    assert(fixture.magazine9.rounds == 5 and fixture.magazine45.rounds == 2,
        "post-reload did not share the fill use case")

    local snapshot = fixture.module.public.state({
        actor = fixture.actor,
        loaderId = fixture.loader.id,
    })
    assert(snapshot.ok and snapshot.data.capacity == 2000, "state capacity changed")

    local health = fixture.module:health()
    assert(health.ok and health.data.replayed == 1 and health.data.rollbackFailures == 0,
        "healthy operation counters are incorrect")

    return table.concat({
        started.code,
        settled.code,
        fill.code,
        withdrawal.code,
        post.code,
        tostring(fixture.magazine9.rounds),
        tostring(fixture.magazine45.rounds),
        tostring(snapshot.data.capacity),
    }, "|")
end

local spSignature = successSignature("sp")
local mpSignature = successSignature("mp")
assert(spSignature == mpSignature, "SP and MP ports changed auto-loader business results")

do
    local fixture = newFixture("deposit-rollback")
    local started = fixture.module.public.startDeposit({
        actor = fixture.actor,
        loaderId = fixture.loader.id,
        operationId = "deposit-rollback-start",
    })
    fixture.state.failStore = true
    local before = #fixture.state.carried
    local settled = fixture.module.public.completeDepositBatch({
        actor = fixture.actor,
        sessionId = started.data.sessionId,
        batchIndex = 1,
    })
    assert(not settled.ok and settled.data.aggregate.failed == 2,
        "deposit store failure was not reported")
    assert(#fixture.state.carried == before, "deposit failure did not restore removed ammunition")
    assert(next(fixture.loader.store) == nil, "deposit failure changed stored balance")
end

do
    local fixture = newFixture("withdraw-rollback")
    fixture.loader.store["Base.Bullets9mm"] = 2
    fixture.state.failStore = true
    local before = #fixture.state.carried
    local value = fixture.module.public.withdraw({
        actor = fixture.actor,
        loaderId = fixture.loader.id,
        fullType = "Base.Bullets9mm",
        count = 2,
        operationId = "withdraw-rollback-1",
    })
    assert(not value.ok and value.code == "storeRejected", "withdraw store failure code was lost")
    assert(#fixture.state.carried == before and fixture.loader.store["Base.Bullets9mm"] == 2,
        "withdraw failure did not remove created ammunition")
end

do
    local fixture = newFixture("fill-rollback")
    fixture.loader.store["Base.Bullets9mm"] = 3
    fixture.state.failSetMagazine = true
    local value = fixture.module.public.manualFill({
        actor = fixture.actor,
        loaderId = fixture.loader.id,
        operationId = "fill-rollback-1",
    })
    assert(not value.ok and value.code == "FillInsufficient",
        "fill failure should preserve the existing insufficient result")
    assert(fixture.loader.store["Base.Bullets9mm"] == 3 and fixture.magazine9.rounds == 2,
        "magazine write failure did not restore loader balance")
end

do
    local fixture = newFixture("degraded-rollback")
    local started = fixture.module.public.startDeposit({
        actor = fixture.actor,
        loaderId = fixture.loader.id,
        operationId = "degraded-start",
    })
    fixture.state.failStore = true
    fixture.state.failRestoreAmmo = true
    local value = fixture.module.public.completeDepositBatch({
        actor = fixture.actor,
        sessionId = started.data.sessionId,
        batchIndex = 1,
    })
    assert(not value.ok and value.code == "rollbackIncomplete",
        "incomplete deposit rollback was hidden")
    local health = fixture.module:health()
    assert(not health.ok and health.code == "rollbackIncomplete"
        and health.data.rollbackFailures > 0, "health did not retain rollback failure")
end

do
    local fixture = newFixture("session")
    local started = fixture.module.public.startDeposit({
        actor = fixture.actor,
        loaderId = fixture.loader.id,
        operationId = "session-start",
    })
    fixture.state.now = fixture.state.now + 60001
    local value = fixture.module.public.completeDepositBatch({
        actor = fixture.actor,
        sessionId = started.data.sessionId,
        batchIndex = 1,
    })
    assert(not value.ok and value.code == "sessionExpired", "expired session remained executable")

    local second = fixture.module.public.startDeposit({
        actor = fixture.actor,
        loaderId = fixture.loader.id,
        operationId = "session-start-2",
    })
    local cancelled = fixture.module.public.cancelDeposit({
        actor = fixture.actor,
        sessionId = second.data.sessionId,
    })
    assert(cancelled.ok and cancelled.code == "DepositInterrupted",
        "deposit session cancellation changed")
end

do
    local fixture = newFixture("lifecycle")
    fixture.module:stop("test")
    local value = fixture.module.public.withdraw({
        actor = fixture.actor,
        loaderId = fixture.loader.id,
        fullType = "Base.Bullets9mm",
        operationId = "stopped-1",
    })
    assert(not value.ok and value.code == "moduleStopped", "stopped module still executed")
end

assert(Descriptor.create ~= nil and Descriptor.dependencies ~= nil, "module descriptor is incomplete")
print("Test-GodSystemV422012AutoLoaderModuleRuntime passed")
