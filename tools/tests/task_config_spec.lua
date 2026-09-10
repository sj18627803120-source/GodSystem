local passed=0
local function test(name,fn) fn(); passed=passed+1; print("PASS task config: "..name) end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end

GodSystemEquipment={Settings={}}
function require(name)
    if name=="GodSystem_Equipment" then return GodSystemEquipment end
    error("unexpected require: "..tostring(name))
end
GodSystemConfig={
    DailyTaskCount=5,
    MaxActiveTasks=3,
    MaxDailyTaskLimit=20,
    MaxActiveTaskLimit=10,
    RefreshTaskCost=30,
    DefaultTaskLimitHours=24,
    TaskRewardMultiplier=1,
    TaskPenaltyMultiplier=1,
    AttributeXPPerCoin=10,
}
SandboxVars={GodSystem={
    EnableTasks=true,
    DailyTaskCount=2,
    MaxActiveTasks=1,
    RefreshTaskCost=7,
    DefaultTaskLimitHours=24,
    TaskRewardMultiplier=2,
    TaskPenaltyMultiplier=0.5,
    AttributeXPPerCoin=10,
}}
assert(loadstring(readSource("shared/GodSystem_RuntimeConfig.lua")))()
GodSystemRuntimeConfig.readSandbox()

test("attribute XP exchange uses the existing authoritative sandbox value",function()
    eq(GodSystemRuntimeConfig.get("AttributeXPPerCoin",0),10)
    SandboxVars.GodSystem.AttributeXPPerCoin=1
    GodSystemRuntimeConfig.readSandbox()
    eq(GodSystemRuntimeConfig.get("AttributeXPPerCoin",0),1)
    SandboxVars.GodSystem.AttributeXPPerCoin=25
    GodSystemRuntimeConfig.readSandbox()
    eq(GodSystemRuntimeConfig.get("AttributeXPPerCoin",0),25)
end)

test("sandbox task bases override retired absolute save values",function()
    local upgrades={maxActiveTasks=10,dailyTaskCount=20}
    GodSystemRuntimeConfig.normalizeTaskUpgrades(upgrades)
    eq(upgrades.taskLimitSchema,2)
    eq(GodSystemRuntimeConfig.getTaskLimit(upgrades,"activeTasks"),1)
    eq(GodSystemRuntimeConfig.getTaskLimit(upgrades,"dailyTasks"),2)
end)

test("purchased upgrades are additive to current sandbox bases",function()
    local upgrades={taskLimitSchema=2,maxActiveTaskBonus=2,dailyTaskBonus=3}
    eq(GodSystemRuntimeConfig.getTaskLimit(upgrades,"activeTasks"),3)
    eq(GodSystemRuntimeConfig.getTaskLimit(upgrades,"dailyTasks"),5)
    local ok,value=GodSystemRuntimeConfig.increaseTaskLimitUpgrade(upgrades,"activeTasks")
    eq(ok,true); eq(value,4); eq(upgrades.maxActiveTaskBonus,3)
    SandboxVars.GodSystem.MaxActiveTasks=4
    GodSystemRuntimeConfig.readSandbox()
    eq(GodSystemRuntimeConfig.getTaskLimit(upgrades,"activeTasks"),7)
end)

test("all template limits move with the 24 hour sandbox baseline",function()
    SandboxVars.GodSystem.DefaultTaskLimitHours=12
    GodSystemRuntimeConfig.readSandbox()
    eq(GodSystemRuntimeConfig.effectiveTaskLimitHours({limitHours=24}),12)
    eq(GodSystemRuntimeConfig.effectiveTaskLimitHours({limitHours=48}),36)
    eq(GodSystemRuntimeConfig.effectiveTaskLimitHours({kind="surviveHours",limitHours=24,target=20}),20)
end)

test("generation token changes when task generation settings change",function()
    local before=GodSystemRuntimeConfig.taskGenerationToken()
    SandboxVars.GodSystem.TaskRewardMultiplier=3
    GodSystemRuntimeConfig.readSandbox()
    local after=GodSystemRuntimeConfig.taskGenerationToken()
    assert(before~=after,"reward multiplier must invalidate open tasks")
    SandboxVars.GodSystem.EnableTasks=false
    GodSystemRuntimeConfig.readSandbox()
    assert(after~=GodSystemRuntimeConfig.taskGenerationToken(),"enable state must invalidate task generation")
end)

test("same-day task setting changes rebuild only open tasks",function()
    SandboxVars.GodSystem.EnableTasks=true
    SandboxVars.GodSystem.DailyTaskCount=2
    SandboxVars.GodSystem.TaskRewardMultiplier=1
    SandboxVars.GodSystem.TaskPenaltyMultiplier=1
    SandboxVars.GodSystem.DefaultTaskLimitHours=24
    GodSystemConfig.TaskTemplates={
        {id="a",title="A",kind="kill",target=1,limitHours=24,rewardPoints=10,penaltyPoints=4},
        {id="b",title="B",kind="kill",target=2,limitHours=36,rewardPoints=20,penaltyPoints=8},
    }
    GodSystemRuntimeConfig.readSandbox()
    local active={taskId="active",status="active",rewardPoints=99}
    local data={
        lastGeneratedDay=7,
        taskGenerationToken=GodSystemRuntimeConfig.taskGenerationToken(),
        tasks={active,{taskId="old-open",status="open",rewardPoints=10}},
        upgrades={taskLimitSchema=2,maxActiveTaskBonus=0,dailyTaskBonus=0},
        history={},
    }
    local saves=0
    GodSystemApp={services={runtime={}}}
    local runtime=GodSystemApp.services.runtime
    runtime.getData=function() return data end
    runtime.isFeatureEnabled=function(key) return GodSystemRuntimeConfig.isFeatureEnabled(key) end
    runtime.getDailyTaskCount=function() return GodSystemRuntimeConfig.getTaskLimit(data.upgrades,"dailyTasks") end
    runtime.itemExists=function() return true end
    runtime.save=function() saves=saves+1 end
    runtime.text=function(_,fallback) return fallback end
    runtime.getTaskStatusText=function(task) return task.status end
    runtime.getTaskTitle=function(task) return task.title or task.taskId end
    function gsNowHours() return 100 end
    function gsCurrentDay() return 7 end
    function gsRandomIndex() return 1 end
    function gsCopyStringArray(value) return value or {} end
    function gsCopyItems(value) return value or {} end
    function gsAppendHistory(target,row) target.history[#target.history+1]=row end
    Events={}
    for _,key in ipairs({"OnInitGlobalModData","OnGameStart","OnCreatePlayer","OnPlayerUpdate","OnPlayerDeath","OnGameExit"}) do
        Events[key]={Add=function() end}
    end
    assert(loadstring(readSource("client/GodSystem_ClientRuntime_Tasks.lua")))()
    GodSystemClientRuntimeInstallers.GodSystem_ClientRuntime_Tasks(setmetatable({},{__index=_G}))

    eq(runtime.generateDailyTasks(false),false)
    SandboxVars.GodSystem.TaskRewardMultiplier=2
    GodSystemRuntimeConfig.readSandbox()
    eq(runtime.generateDailyTasks(false),true)
    eq(data.tasks[1],active)
    eq(#data.tasks,3)
    eq(data.tasks[2].rewardPoints,20)
    eq(data.tasks[3].rewardPoints,20)
    eq(saves,1)
end)

print("Task config behavior groups passed: "..passed)
