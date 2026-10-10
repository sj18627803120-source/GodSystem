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
assert(stagesFor(false) == "ground,container,corpseItems", "disabled corpse mode skips only the corpse body")
print("PASS range recycle: corpse option defaults on; contents remain scanned when the body is disabled")

for _,enabled in ipairs({false,true}) do
    local itemRemoved,bodyRemoved=false,false
    local adapter={
        nextCandidate=function(_,_,stage)
            if stage=="corpseItems" and not itemRemoved then
                return {kind="item",fullType="Base.Nails"},nil,false,false,1
            elseif stage=="corpses" and itemRemoved and not bodyRemoved then
                return {kind="corpse",fullType="GodSystem.Corpse",filterable=false},nil,false,false,1
            end
            return nil,nil,true,false,1
        end,
        recycle=function(_,_,candidate)
            if candidate.kind=="item" then itemRemoved=true; return {removed=true,payout=7} end
            bodyRemoved=true; return {removed=true,payout=3}
        end,
    }
    local job=GodSystemRangeRecycleDomain.newJob({adapter=adapter,origin={x=0,y=0,z=0},radius=0,includeCorpses=enabled})
    for _=1,12 do GodSystemRangeRecycleDomain.step(job); if job.status~="running" then break end end
    assert(job.status=="completed" and itemRemoved,"corpse contents are recycled independently of the body toggle")
    assert(bodyRemoved==enabled and job.processed==(enabled and 2 or 1) and job.payout==(enabled and 10 or 7))
end

-- Disabling corpse removal must not bypass the existing item filter either.
local offered=false
GodSystemRangeFilter={allows=function(filter,fullType) return fullType==filter.allowedType end}
local adapter={nextCandidate=function(_,_,stage)
    if stage=="corpseItems" and not offered then offered=true; return {fullType="Base.WatchDigital"},nil,false,false,1 end
    return nil,nil,true,false,1
end,recycle=function() error("excluded corpse contents must not be recycled") end}
local job=GodSystemRangeRecycleDomain.newJob({adapter=adapter,origin={x=0,y=0,z=0},radius=0,includeCorpses=false,filter={allowedType="Base.Nails"}})
for _=1,12 do GodSystemRangeRecycleDomain.step(job); if job.status~="running" then break end end
assert(job.status=="completed" and offered and job.processed==0 and job.payout==0 and job.skipped==1)
print("PASS range recycle: only body removal changes; content payout and item filtering retain their rules")
