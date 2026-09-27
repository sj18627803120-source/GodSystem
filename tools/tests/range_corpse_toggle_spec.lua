local source = readSource("shared/GodSystem_RangeRecycleDomain.lua")
assert(loadstring(source, "@GodSystem_RangeRecycleDomain.lua"))()

local function stagesFor(includeCorpses)
    local visited = {}
    local adapter = {
        recycle = function() return { removed = false } end,
        nextCandidate = function(_, _, stage)
            visited[#visited + 1] = stage
            return nil, nil, true, false, 1
        end,
    }
    local job = GodSystemRangeRecycleDomain.newJob({
        adapter = adapter, origin = { x = 0, y = 0, z = 0 }, radius = 0,
        includeCorpses = includeCorpses, scanBudget = 20,
    })
    for _ = 1, 8 do
        GodSystemRangeRecycleDomain.step(job)
        if job.status ~= "running" then break end
    end
    assert(job.status == "completed", "empty range job completes")
    return table.concat(visited, ",")
end

assert(stagesFor(nil) == "ground,container,corpseItems,corpses", "default includes both corpse stages")
assert(stagesFor(false) == "ground,container", "disabled corpse mode skips both corpse and contents scans")
print("PASS range recycle: corpse option defaults on and excludes both corpse stages when off")
