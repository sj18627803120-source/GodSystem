GodSystemDiagnosticsViewModel = GodSystemDiagnosticsViewModel or {}

local ViewModel = GodSystemDiagnosticsViewModel

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

local function text(value, fallback)
    value = tostring(value or "")
    if value == "" then return tostring(fallback or "-") end
    return value
end

local function moduleState(row)
    local state = tostring(row and row.state or "unknown")
    local health = type(row and row.health) == "table" and row.health or nil
    if state == "failed" or state == "blocked" then return "error" end
    if state ~= "started" then return "warning" end
    if health and health.ok == false then return "warning" end
    return "healthy"
end

local function statusLabel(status)
    if status == "error" then return "存在功能故障" end
    if status == "warning" then return "需要注意" end
    return "运行正常"
end

local function row(labelKey, label, value, severity, detail)
    return {
        labelKey = tostring(labelKey or ""),
        label = tostring(label or ""),
        value = tostring(value or "-"),
        severity = tostring(severity or "info"),
        detail = detail and tostring(detail) or nil,
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
    depth = depth or 0
    seen = seen or {}
    if type(value) ~= "table" then
        lines[#lines + 1] = prefix .. "=" .. tostring(value)
        return
    end
    if seen[value] then
        lines[#lines + 1] = prefix .. "=<cycle>"
        return
    end
    if depth >= 8 then
        lines[#lines + 1] = prefix .. "=<depth-limit>"
        return
    end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    if #keys == 0 then lines[#lines + 1] = prefix .. "={}" end
    for index = 1, #keys do
        local key = keys[index]
        local childPrefix = prefix == "" and tostring(key) or (prefix .. "." .. tostring(key))
        appendValue(lines, childPrefix, value[key], depth + 1, seen)
    end
    seen[value] = nil
end

function ViewModel.advancedText(input)
    local lines = { "GodSystem Diagnostics" }
    appendValue(lines, "", copy(type(input) == "table" and input or {}), 0, {})
    return table.concat(lines, "\n")
end

function ViewModel.build(input)
    input = type(input) == "table" and input or {}
    local modules = sortedModules(input.modules)
    local healthy, warnings, errors = 0, 0, 0
    local firstModuleProblem = nil
    for index = 1, #modules do
        local status = moduleState(modules[index])
        if status == "healthy" then healthy = healthy + 1
        elseif status == "warning" then warnings = warnings + 1
        else errors = errors + 1 end
        if status ~= "healthy" and not firstModuleProblem then firstModuleProblem = modules[index] end
    end

    local migration = type(input.migration) == "table" and input.migration or nil
    local client = type(input.client) == "table" and input.client or {}
    local server = type(input.server) == "table" and input.server or {}
    local mode = tostring(input.mode or "SP")
    local lastIssue = type(input.lastIssue) == "table" and input.lastIssue or nil

    local severity = errors > 0 and "error" or (warnings > 0 and "warning" or "healthy")
    local advice = "当前未发现需要处理的问题。"
    if errors > 0 then
        advice = "有功能未能启动；复制高级报告并反馈，其他独立功能仍可继续使用。"
    elseif migration and migration.ok == false then
        severity = "error"
        advice = "旧存档迁移失败；请保留存档并复制高级报告，不要重复购买或生成物品。"
    elseif mode == "MP" and (tonumber(client.pendingTimeouts) or 0) > 0 then
        severity = "warning"
        advice = "多人同步曾超时；先刷新诊断，若持续出现请复制高级报告。"
    elseif mode == "MP" and client.hasServerState ~= true then
        severity = "warning"
        advice = "正在等待服务器状态；短暂等待后可刷新诊断。"
    elseif lastIssue then
        severity = severity == "healthy" and "warning" or severity
        advice = "记录到最近一次问题；如果功能仍异常，请复制高级报告。"
    end

    local rows = {
        row("Diag_OverallStatus", "总体状态", statusLabel(severity), severity),
        row("Diag_VersionMode", "版本与模式", text(input.version, "?") .. " / " .. mode, "info"),
        row("Diag_Modules", "功能模块", tostring(healthy) .. " 正常 / " .. tostring(warnings) ..
            " 注意 / " .. tostring(errors) .. " 故障", errors > 0 and "error"
            or (warnings > 0 and "warning" or "healthy")),
    }
    if migration then
        rows[#rows + 1] = row("Diag_Migration", "存档迁移",
            migration.ok == false and "失败" or text(migration.code or migration.state, "完成"),
            migration.ok == false and "error" or "healthy")
    end
    if mode == "MP" then
        rows[#rows + 1] = row("Diag_MPSync", "多人同步",
            client.hasServerState == true and "已同步" or
                (client.pendingState == true and "同步中" or "未同步"),
            client.hasServerState == true and "healthy" or "warning")
    end
    if firstModuleProblem then
        rows[#rows + 1] = row("Diag_ProblemModule", "异常功能",
            text(firstModuleProblem.moduleId, "未知"),
            "error", text(firstModuleProblem.code, firstModuleProblem.state))
    end
    if lastIssue then
        rows[#rows + 1] = row("Diag_LastIssue", "最近问题",
            text(lastIssue.moduleId, "core") .. " / " .. text(lastIssue.code, "unexpectedError"),
            "warning", text(lastIssue.message, "-"))
    elseif text(client.lastError, "") ~= "" then
        rows[#rows + 1] = row("Diag_LastIssue", "最近问题",
            text(client.lastError, "-"), "warning")
    elseif text(server.lastError, "") ~= "" then
        rows[#rows + 1] = row("Diag_LastIssue", "最近问题",
            text(server.lastError, "-"), "warning")
    end
    rows[#rows + 1] = row("Diag_Advice", "建议", advice, severity)

    local reportSource = copy(input)
    reportSource.modules = modules
    return {
        status = severity,
        title = statusLabel(severity),
        advice = advice,
        rows = rows,
        advancedText = ViewModel.advancedText(reportSource),
    }
end

return ViewModel
