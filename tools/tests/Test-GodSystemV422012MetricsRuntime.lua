local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    package.path,
}, ";")

require "GodSystem/Platform/WalletAccounts"
require "GodSystem/Platform/Metrics"

local function context(value, binding)
    return {
        state = { get = function() return value end },
        binding = binding,
    }
end

local accounts = GodSystemWalletAccountsPlatform.create({}, context({}))
assert(accounts:start())
local root = {
    counters = {
        alice = { spentPoints = 12, recycledItems = 2 },
    },
}
local metrics = GodSystemMetricsPlatform.create({
    ["wallet.accounts"] = accounts.public,
}, context(root))
assert(metrics:start())

local alice = "alice"
local bob = "bob"
assert(metrics.public.get(alice, "spentPoints") == 12, "migrated counter is not visible")
assert(metrics.public.get(bob, "spentPoints") == 0, "players share counter state")

local updated, receipt = metrics.public.increment(alice, {
    spentPoints = 8,
    boughtItems = 3,
})
assert(updated and metrics.public.get(alice, "spentPoints") == 20
    and metrics.public.get(alice, "boughtItems") == 3,
    "atomic multi-counter increment failed")
assert(metrics.public.restore(alice, receipt)
    and metrics.public.get(alice, "spentPoints") == 12
    and metrics.public.get(alice, "boughtItems") == 0,
    "counter receipt rollback failed")

local changed, stale = metrics.public.increment(alice, "spentPoints", 1)
assert(changed and metrics.public.increment(alice, "spentPoints", 1))
assert(not metrics.public.restore(alice, stale)
    and metrics.public.get(alice, "spentPoints") == 14,
    "stale receipt overwrote newer counter state")

assert(not metrics.public.increment(alice, "spentPoints", math.huge),
    "infinite counter change was accepted")
assert(not metrics.public.increment(alice, { spentPoints = -100 }),
    "negative final counter was accepted")
local snapshot = metrics.public.snapshot(alice)
snapshot.spentPoints = 999
assert(metrics.public.get(alice, "spentPoints") == 14,
    "counter snapshot exposed mutable state")
assert(metrics:health().ok, "metrics health failed")

print("Test-GodSystemV422012MetricsRuntime passed")
