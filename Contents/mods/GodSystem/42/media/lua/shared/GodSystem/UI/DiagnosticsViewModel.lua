GodSystemDiagnosticsViewModel = GodSystemDiagnosticsViewModel or {}

local ViewModel = GodSystemDiagnosticsViewModel

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copy(key, seen)] = copy(child, seen)
    end
    return result
end

local function text(value, fallback)
    value = tostring(value or "")
    return value ~= "" and value or tostring(fallback or "-")
end

local function moduleState(module)
    local state = tostring(module and module.state or "unknown")
    local health = type(module and module.health) == "table"
        and module.health or nil
    if state == "failed" or state == "blocked" then return "error" end
    if state ~= "started" or (health and health.ok == false) then
        return "warning"
    end
    return "healthy"
end

local function row(labelKey, fallback, value, severity, detail)
    return {
        labelKey = tostring(labelKey or ""),
        fallback = tostring(fallback or ""),
        value = value,
        severity = tostring(severity or "info"),
        detail = detail and tostring(detail) or nil,
    }
end

local function localized(key, fallback, args)
    return {
        key = tostring(key or ""),
        fallback = tostring(fallback or ""),
        args = copy(args or {}),
    }
end

local function sortedModules(source)
    local result = {}
    for index = 1, #(source or {}) do result[index] = copy(source[index]) end
    table.sort(result, function(left, right)
        return tostring(left.moduleId or "") < tostring(right.moduleId or "")
    end)
    return result
end

local function appendValue(lines, prefix, value, depth, seen)
    depth, seen = depth or 0, seen or {}
    if type(value) ~= "table" then
        lines[#lines + 1] = prefix .. "=" .. tostring(value)
        return
    end
    if seen[value] then lines[#lines + 1] = prefix .. "=<cycle>" return end
    if depth >= 8 then
        lines[#lines + 1] = prefix .. "=<depth-limit>"
        return
    end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)
    if #keys == 0 then lines[#lines + 1] = prefix .. "={}" end
    for index = 1, #keys do
        local key = keys[index]
        local childPrefix = prefix == "" and tostring(key)
            or (prefix .. "." .. tostring(key))
        appendValue(lines, childPrefix, value[key], depth + 1, seen)
    end
    seen[value] = nil
end

function ViewModel.advancedText(input)
    local lines = { "GodSystem Diagnostics 42.20.1.2" }
    appendValue(lines, "", copy(type(input) == "table" and input or {}), 0, {})
    return table.concat(lines, "\n")
end

function ViewModel.build(input)
    input = type(input) == "table" and input or {}
    local modules = sortedModules(input.modules)
    local healthy, warnings, errors, firstProblem = 0, 0, 0, nil
    for index = 1, #modules do
        local state = moduleState(modules[index])
        if state == "healthy" then healthy = healthy + 1
        elseif state == "warning" then warnings = warnings + 1
        else errors = errors + 1 end
        if state ~= "healthy" and not firstProblem then
            firstProblem = modules[index]
        end
    end

    local migration = type(input.migration) == "table" and input.migration or nil
    local client = type(input.client) == "table" and input.client or {}
    local server = type(input.server) == "table" and input.server or {}
    local lastIssue = type(input.lastIssue) == "table" and input.lastIssue or nil
    local mode = tostring(input.mode or "SP")
    local severity = errors > 0 and "error"
        or (warnings > 0 and "warning" or "healthy")
    local advice = localized("Diag_AdviceHealthy",
        "No action is currently required.")

    if errors > 0 then
        advice = localized("Diag_AdviceModuleError",
            "One feature failed to start. Other independent features can still be used; copy the advanced report when asking for help.")
    elseif migration and migration.ok == false then
        severity = "error"
        advice = localized("Diag_AdviceMigrationError",
            "Save migration failed. Keep the save unchanged and copy the advanced report.")
    elseif mode == "MP" and (tonumber(client.pendingTimeouts) or 0) > 0 then
        severity = "warning"
        advice = localized("Diag_AdviceTimeout",
            "Multiplayer synchronization timed out. Refresh diagnostics and copy the report if it continues.")
    elseif mode == "MP" and client.hasServerState ~= true then
        severity = "warning"
        advice = localized("Diag_AdviceSyncing",
            "Waiting for server state. Wait briefly, then refresh diagnostics.")
    elseif lastIssue then
        severity = severity == "healthy" and "warning" or severity
        advice = localized("Diag_AdviceRecentIssue",
            "A recent issue was recorded. Copy the advanced report if the feature is still abnormal.")
    end

    local statusKeys = {
        healthy = { "Diag_StatusHealthy", "Running normally" },
        warning = { "Diag_StatusWarning", "Needs attention" },
        error = { "Diag_StatusError", "Feature fault detected" },
    }
    local status = statusKeys[severity]
    local rows = {
        row("Diag_OverallStatus", "Overall status",
            localized(status[1], status[2]), severity),
        row("Diag_VersionMode", "Version and mode",
            text(input.version, "?") .. " / " .. mode, "info"),
        row("Diag_Modules", "Feature modules",
            localized("Diag_ModuleSummary",
                "{1} healthy / {2} attention / {3} failed",
                { healthy, warnings, errors }),
            errors > 0 and "error" or (warnings > 0 and "warning" or "healthy")),
    }
    if migration then
        rows[#rows + 1] = row("Diag_Migration", "Save migration",
            migration.ok == false
                and localized("Diag_MigrationFailed", "Failed")
                or localized("Diag_MigrationCompleted", "Completed"),
            migration.ok == false and "error" or "healthy",
            migration.ok == false and text(migration.code, "migrationFailed") or nil)
    end
    if mode == "MP" then
        local syncKey = client.hasServerState == true and "Diag_SyncComplete"
            or (client.pendingState == true and "Diag_SyncPending"
                or "Diag_SyncMissing")
        local syncFallback = client.hasServerState == true and "Synchronized"
            or (client.pendingState == true and "Synchronizing" or "Not synchronized")
        rows[#rows + 1] = row("Diag_MPSync", "Multiplayer sync",
            localized(syncKey, syncFallback),
            client.hasServerState == true and "healthy" or "warning")
    end
    if firstProblem then
        rows[#rows + 1] = row("Diag_ProblemModule", "Affected feature",
            text(firstProblem.moduleId, "unknown"), "error",
            text(firstProblem.code, firstProblem.state))
    end
    if lastIssue then
        rows[#rows + 1] = row("Diag_LastIssue", "Most recent issue",
            text(lastIssue.moduleId, "core") .. " / "
                .. text(lastIssue.code, "unexpectedError"),
            "warning", text(lastIssue.message, "-"))
    elseif text(client.lastError, "") ~= "" then
        rows[#rows + 1] = row("Diag_LastIssue", "Most recent issue",
            text(client.lastError, "-"), "warning")
    elseif text(server.lastError, "") ~= "" then
        rows[#rows + 1] = row("Diag_LastIssue", "Most recent issue",
            text(server.lastError, "-"), "warning")
    end
    rows[#rows + 1] = row("Diag_Advice", "Suggested action",
        advice, severity)

    local reportSource = copy(input)
    reportSource.modules = modules
    return {
        status = severity,
        title = localized(status[1], status[2]),
        advice = advice,
        rows = rows,
        advancedText = ViewModel.advancedText(reportSource),
    }
end

return ViewModel
