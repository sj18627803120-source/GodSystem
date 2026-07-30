local migrationPath = assert(arg and arg[1], "migration path required")
local Migration = dofile(migrationPath)

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[clone(key, seen)] = clone(child, seen)
    end
    return result
end

local function equal(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not equal(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
end

local function fixture()
    return {
        playerData = {
            version = "42.20.1.1",
            started = true,
            currencyInitialized = true,
            points = 8123,
            lastGeneratedDay = 19,
            tasks = {
                {
                    taskId = "task-1",
                    sourceId = "area",
                    title = "Area Survey",
                    kind = "explore",
                    status = "accepted",
                    rewardPoints = 300,
                    acceptedAt = 11,
                    deadline = 31,
                    customTemplateField = "keep",
                },
            },
            lastKnownKills = 18,
            autoTaskClaimEnabled = true,
            lastAutoTaskClaimHour = 41.5,
            unlockedShopItems = {
                ["Moveables.Moveable|furniture_bedding_01_35"] = {
                    fullType = "Moveables.Moveable",
                    worldSprite = "furniture_bedding_01_35",
                    variantKey = "Moveables.Moveable|furniture_bedding_01_35",
                    label = "Bed (2)",
                    sellPrice = 50,
                    buyPrice = 100,
                    unlockedAt = 22,
                    hidden = true,
                },
            },
            recycleLimitDay = 19,
            recycleLimitUsed = 25,
            recycleUnlockMode = "recycle",
            autoRecyclerClaimed = true,
            lastAutoRecyclerHour = 50,
            waistAutoRecycleUnlocked = true,
            waistAutoRecycleEnabled = true,
            waistRecycleUnlockMode = "list",
            lastWaistAutoRecycleHour = 49.5,
            upgrades = {
                maxActiveTasks = 4,
                dailyTaskCount = 3,
                carryCapacityLevel = 7,
            },
            autoRecyclerCapacityLevel = 8,
            autoRecyclerReductionLevel = 8,
            autoRecyclerReliefLevel = 4,
            bank = {
                current = 6000,
                fixed = {
                    {
                        id = 4,
                        termId = "30d",
                        principal = 2000,
                        startHour = 20,
                        matureHour = 740,
                        rate = 0.1,
                        days = 30,
                    },
                },
                investments = {
                    stable = {
                        tierId = "stable",
                        balance = 3000,
                        onlineHours = 12,
                        settlementCount = 2,
                        redeemUnlocked = true,
                        lastDelta = 20,
                        lastOutcome = "profit",
                        lastSettledHour = 55,
                    },
                },
                loan = {
                    id = 3,
                    kind = "standard",
                    principal = 5000,
                    totalDue = 5500,
                    paid = 500,
                    schedule = {
                        { index = 1, dueHour = 80, principalPart = 1000, interestPart = 100, paid = false },
                    },
                },
            },
            homeSystem = {
                home = { x = 10, y = 20, z = 0, label = "Home", source = "player" },
                tempSlots = { { owned = true, point = { x = 11, y = 20, z = 0 } } },
                returnPoint = { x = 5, y = 6, z = 0 },
                safeZone = { level = 3, enabled = true, lastScanHours = 40 },
                pendingTeleport = { id = "transient", cost = 50 },
            },
            companion = {
                unlocked = true,
                unlocks = { attack = true, sight = true, guardian = false },
                levels = { damage = 4, range = 3 },
                resonance = 2,
                effects = { beam = true },
                combatMode = "active",
                followMode = "near",
                visible = true,
                guardianEnabled = false,
                guardPoint = { x = 4, y = 5, z = 0 },
                cooldowns = { attack = 2, sight = 0, guardian = 0 },
                ui = { shortcutVisible = true, shortcutX = 30, shortcutY = 40 },
            },
            adminConfig = {
                settings = { EnableStorageNetwork = true, AutoLoaderAmmoCapacity = 2000 },
                itemOverrides = {
                    ["Base.Bandage"] = { buyPrice = 30, category = "medical", shopEnabled = true },
                },
            },
            history = {
                { kind = "shop", time = 22, code = "Bought", args = { "Base.Bandage" }, shopId = "bandage" },
            },
            stats = {
                recycledItems = 10,
                recycledPoints = 100,
                spentPoints = 200,
                boughtItems = 4,
                moveDistance = 300,
                modifiedTraits = 2,
                completedTasks = 3,
                failedTasks = 1,
                homeSafeCleared = 7,
                lotteryDraws = 8,
            },
            ui = { x = 100, y = 120 },
            lastMoveX = 7,
            lastMoveY = 8,
            lastMoveZ = 0,
            attributeSyncPending = true,
            lastServerPushHour = 99,
            balance = 999999,
            serverDiagnostics = { transient = true },
        },
        transactionOperations = {
            alice = {
                upgradeSystem = {
                    results = {
                        pending = { status = "processing", fingerprint = "a" },
                        finished = { status = "done", fingerprint = "b", ok = true, code = "ok" },
                    },
                    order = { "pending", "finished" },
                },
            },
        },
        attributeOperations = {
            alice = {
                results = {
                    pending = { status = "processing", fingerprint = "c" },
                    unknown = { status = "unknown", fingerprint = "d" },
                },
                order = { "pending", "unknown" },
            },
        },
        storageGlobal = {
            schemaVersion = 5,
            networks = { secretInstanceData = true },
        },
        itemModData = {
            GodSystemAutoLoader = { ammo = { ["Base.9mmBullets"] = 500 } },
            GodSystemStorageCoreNetworkId = "network-1",
        },
        objectModData = {
            GodSystemStorageObjectId = "object-1",
        },
    }
end

local legacy = fixture()
local before = clone(legacy)
local first = Migration.run(legacy)

expect(first.ok == true, "full migration must succeed")
expect(first.code == "migrationComplete", "full migration result code")
expect(equal(legacy, before), "legacy snapshot must remain immutable")
expect(first.root.releaseVersion == "42.20.1.2", "target release version")
expect(first.root.migration[Migration.MigrationId].completed == true, "migration completion marker")

local modules = first.root.modules
expect(modules["wallet.accounts"].data.accounts["local"].current == 6000,
    "bank current must migrate to the single wallet account")
expect(modules["tasks.state"].data.players["local"].tasks[1].customTemplateField == "keep",
    "task row must be copied intact")
expect(modules["shop.state"].data.players["local"].unlockedShopItems[
    "Moveables.Moveable|furniture_bedding_01_35"].worldSprite
    == "furniture_bedding_01_35", "shop variant identity")
expect(modules["recycle.state"].data.players["local"].waistAutoRecycleEnabled == true,
    "recycle state")
expect(modules["upgrades.state"].data.players["local"].upgrades.carryCapacityLevel == 7,
    "upgrade state")
expect(modules["terminal.state"].data.players["local"].data.reliefLevel == 4,
    "terminal relief level")
expect(modules["bank.state"].data.players["local"].loan.schedule[1].interestPart == 100,
    "bank loan schedule")
expect(modules["bank.state"].data.players["local"].current == nil,
    "bank state must not retain a second current balance")
expect(modules["home.state"].data.players["local"].homeSystem.home.x == 10, "home point")
expect(modules["home.state"].data.players["local"].homeSystem.pendingTeleport == nil,
    "pending teleport must not migrate")
expect(modules["feature.companion"].data.actors["local"].levels.damage == 4,
    "companion state")
expect(modules["admin.state"].data.itemOverrides["Base.Bandage"].category == "medical",
    "admin overrides")
local system = modules["system.state"].data.players["local"]
expect(system.stats.lotteryDraws == 8, "system stats")
expect(system.attributeSyncPending == true, "attribute sync pending")
expect(system.pendingCurrencyGrant == 0,
    "already initialized physical currency must not be duplicated")
expect(system.lastServerPushHour == nil, "derived push hour must not migrate")
expect(system.balance == nil, "derived balance must not migrate")
expect(system.serverDiagnostics == nil, "runtime diagnostics must not migrate")

local transactions = system.operationCaches.transactionOperations
expect(transactions.alice.upgradeSystem.results.pending.status == "unknown", "processing transaction must become unknown")
expect(transactions.alice.upgradeSystem.results.finished.status == "done", "done transaction must be preserved")
local attributes = system.operationCaches.attributeOperations
expect(attributes.alice.results.pending.status == "unknown", "processing attribute operation must become unknown")
expect(attributes.alice.results.unknown.status == "unknown", "unknown operation must stay unknown")
expect(legacy.transactionOperations.alice.upgradeSystem.results.pending.status == "processing", "legacy operation cache must not mutate")

expect(first.lazy.storageNetwork.copyInstanceData == false, "storage instance data must use lazy strategy")
expect(first.lazy.autoLoader.copyInstanceData == false, "auto-loader instance data must use lazy strategy")
expect(first.root.storageGlobal == nil, "storage global instance data must not be copied")
expect(first.root.itemModData == nil, "item ModData must not be copied")
expect(first.root.objectModData == nil, "object ModData must not be copied")

local second = Migration.run(legacy, first.root)
expect(second.ok == true, "repeat migration must succeed")
expect(equal(first.root, second.root), "repeat migration must be idempotent")
expect(equal(first.lazy, second.lazy), "lazy strategy must be idempotent")
second.root.modules["tasks.state"].data.players["local"].lastKnownKills = 999
local afterNewWrite = Migration.run(legacy, second.root)
expect(afterNewWrite.root.modules["tasks.state"].data.players["local"].lastKnownKills == 999,
    "repeat migration must not overwrite post-migration module state")

local pendingCurrency = fixture()
pendingCurrency.playerData.currencyInitialized = false
pendingCurrency.playerData.points = 250
local pendingResult = Migration.run(pendingCurrency)
expect(pendingResult.root.modules["system.state"].data.players["local"].pendingCurrencyGrant == 250,
    "unfinished legacy physical currency grant must remain pending")

local anotherPlayer = fixture()
anotherPlayer.playerData.bank.current = 700
local multiActor = Migration.run(anotherPlayer, first.root, { actorKey = "alice" })
expect(multiActor.root.modules["wallet.accounts"].data.accounts["local"].current == 6000,
    "migrating another player must preserve the first account")
expect(multiActor.root.modules["wallet.accounts"].data.accounts.alice.current == 700,
    "migration must isolate accounts by actor")
expect(multiActor.root.migration[Migration.MigrationId].actors["local"].completed == true
    and multiActor.root.migration[Migration.MigrationId].actors.alice.completed == true,
    "migration status must be tracked per actor")

local corrupted = fixture()
corrupted.playerData.bank = "corrupt-bank"
local corruptedBefore = clone(corrupted)
local existing = {
    schemaVersion = 1,
    modules = {
        ["bank.state"] = {
            version = 1,
            data = { players = { ["local"] = { preserved = "old-bank-slice" } } },
        },
    },
}
local partial = Migration.run(corrupted, existing)
expect(partial.ok == false, "corrupt module must yield partial migration")
expect(partial.code == "migrationPartial", "partial migration result code")
expect(partial.modules["bank.state"].status == "failed",
    "bank module must fail independently")
expect(partial.root.modules["bank.state"].data.players["local"].preserved == "old-bank-slice",
    "failed module must retain existing slice")
expect(partial.modules["wallet.accounts"].status == "done",
    "wallet must remain independent")
expect(partial.modules["tasks.state"].status == "done", "tasks must remain independent")
expect(partial.root.modules["tasks.state"].data.players["local"].tasks[1].taskId == "task-1",
    "successful module must commit")
expect(partial.root.migration[Migration.MigrationId].completed == false, "partial marker")
expect(equal(corrupted, corruptedBefore), "corrupt legacy snapshot must remain immutable")

local invalid = Migration.run("invalid")
expect(invalid.ok == false and invalid.code == "invalidLegacySnapshot", "invalid snapshot must fail cleanly")

print("Test-GodSystemMigration422011Runtime passed")
