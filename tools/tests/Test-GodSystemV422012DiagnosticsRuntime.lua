local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    package.path,
}, ";")

require "GodSystem/UI/DiagnosticsViewModel"

local healthy = GodSystemDiagnosticsViewModel.build({
    version = "42.20.1.2",
    mode = "SP",
    migration = { ok = true, code = "completed" },
    modules = {
        { moduleId = "feature.wallet", state = "started", health = { ok = true } },
        { moduleId = "feature.shop", state = "started", health = { ok = true } },
    },
})
assert(healthy.status == "healthy", "healthy report was not player-readable")
assert(healthy.title.key == "Diag_StatusHealthy",
    "healthy status is not localizable")
assert(#healthy.rows >= 5, "healthy report omitted summary rows")

local failed = GodSystemDiagnosticsViewModel.build({
    version = "42.20.1.2",
    mode = "MP",
    protocol = { version = "42.20.1.2" },
    modules = {
        { moduleId = "feature.wallet", state = "started", health = { ok = true } },
        {
            moduleId = "feature.shop",
            state = "failed",
            code = "createFailed",
            dependencies = { "wallet" },
        },
    },
    lastIssue = {
        moduleId = "feature.shop",
        stage = "create",
        code = "createFailed",
        operationId = "shop-42",
        message = "test failure",
        stack = "traceback",
    },
    client = { hasServerState = false, pendingTimeouts = 1 },
})
assert(failed.status == "error", "module failure did not produce error status")
assert(failed.advice.key == "Diag_AdviceModuleError",
    "player advice is not actionable")
assert(failed.advancedText:find("shop%-42"),
    "advanced report omitted operation id")
assert(failed.advancedText:find("dependencies"),
    "advanced report omitted dependency chain")
assert(failed.advancedText:find("traceback"),
    "advanced report omitted raw stack")

local migration = GodSystemDiagnosticsViewModel.build({
    version = "42.20.1.2",
    mode = "SP",
    migration = { ok = false, code = "moduleMigrationFailed" },
    modules = {},
})
assert(migration.status == "error",
    "migration failure did not produce error status")
assert(migration.advice.key == "Diag_AdviceMigrationError",
    "migration advice is missing")

print("Test-GodSystemV422012DiagnosticsRuntime passed")
