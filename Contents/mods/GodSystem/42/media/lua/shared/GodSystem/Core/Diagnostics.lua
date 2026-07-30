require "GodSystem/Core/Result"

GodSystemDiagnostics = GodSystemDiagnostics or {}

local Diagnostics = GodSystemDiagnostics

local function nowMs()
    if getTimestampMs then return getTimestampMs() end
    if os and os.time then return math.floor(os.time() * 1000) end
    return 0
end

local function shallowCopy(value)
    local result = {}
    for key, item in pairs(type(value) == "table" and value or {}) do
        result[key] = item
    end
    return result
end

function Diagnostics.new(options)
    options = options or {}
    local instance = {
        version = tostring(options.version or ""),
        environment = tostring(options.environment or "unknown"),
        maxIssues = math.max(10, math.floor(tonumber(options.maxIssues) or 100)),
        issues = {},
        modules = {},
        migration = nil,
        protocol = shallowCopy(options.protocol),
    }

    function instance:setModuleStatus(moduleId, status)
        moduleId = tostring(moduleId or "")
        if moduleId == "" then return end
        local row = shallowCopy(status)
        row.moduleId = moduleId
        row.updatedAt = nowMs()
        self.modules[moduleId] = row
    end

    function instance:setMigration(status)
        self.migration = shallowCopy(status)
        self.migration.updatedAt = nowMs()
    end

    function instance:record(issue)
        issue = shallowCopy(issue)
        issue.moduleId = tostring(issue.moduleId or "core")
        issue.stage = tostring(issue.stage or "runtime")
        issue.code = tostring(issue.code or "unexpectedError")
        issue.message = tostring(issue.message or "")
        issue.operationId = issue.operationId and tostring(issue.operationId) or nil
        issue.timestamp = tonumber(issue.timestamp) or nowMs()
        table.insert(self.issues, 1, issue)
        while #self.issues > self.maxIssues do
            table.remove(self.issues)
        end
        return issue
    end

    function instance:lastIssue()
        return self.issues[1]
    end

    function instance:simpleReport()
        local moduleRows = {}
        for moduleId, row in pairs(self.modules) do
            moduleRows[#moduleRows + 1] = {
                moduleId = moduleId,
                state = tostring(row.state or "unknown"),
                code = row.code and tostring(row.code) or nil,
            }
        end
        table.sort(moduleRows, function(a, b) return a.moduleId < b.moduleId end)
        return {
            version = self.version,
            environment = self.environment,
            migration = shallowCopy(self.migration),
            modules = moduleRows,
            lastIssue = shallowCopy(self:lastIssue()),
        }
    end

    function instance:advancedReport()
        local report = self:simpleReport()
        report.protocol = shallowCopy(self.protocol)
        report.issues = {}
        for i = 1, #self.issues do report.issues[i] = shallowCopy(self.issues[i]) end
        return report
    end

    return instance
end

