local passed=0
local function test(name,fn) fn(); passed=passed+1; print("PASS navigation visibility: "..name) end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end

function require() end
local flags={}
local multiplayer=false
GodSystemWindow={}
GodSystemUI={}
GodSystemApp={services={runtime={
    isFeatureEnabled=function(key) return flags[key]~=false end,
    isItemConfigAllowed=function() return flags.itemConfig==true end,
}}}
GodSystemCompanionConfig={isEnabled=function() return flags.EnableCompanion~=false end}
function gsIsMultiplayer() return multiplayer end
assert(loadstring(readSource("client/GodSystem_UI_Runtime_Window.lua")))()
GodSystemUIRuntimeInstallers.GodSystem_UI_Runtime_Window(setmetatable({},{__index=_G}))

test("feature-backed tabs disappear when their sandbox option is disabled",function()
    local window=setmetatable({navigationTabs={}}, {__index=GodSystemWindow})
    local tab={id="tasks",featureKeys={"EnableTasks"}}
    eq(window:isNavigationTabVisible(tab),true)
    flags.EnableTasks=false
    eq(window:isNavigationTabVisible(tab),false)
    flags.EnableTasks=true
    local range={id="rangeRecycle",featureKeys={"EnableRecycle","EnableRangeRecycle"}}
    flags.EnableRecycle=false
    eq(window:isNavigationTabVisible(range),false)
end)

test("companion stays single-player only and item config stays permission based",function()
    local window=setmetatable({}, {__index=GodSystemWindow})
    local companion={id="companion",featureKeys={"EnableCompanion"},singlePlayerOnly=true}
    eq(window:isNavigationTabVisible(companion),true)
    multiplayer=true
    eq(window:isNavigationTabVisible(companion),false)
    multiplayer=false
    eq(window:isNavigationTabVisible({id="itemConfig"}),false)
    flags.itemConfig=true
    eq(window:isNavigationTabVisible({id="itemConfig"}),true)
end)

test("hidden current page falls back to the first visible normal page",function()
    flags.EnableTasks=false
    flags.EnableShop=true
    local window=setmetatable({
        mode="tasks",
        navigationTabs={
            {id="tasks",featureKeys={"EnableTasks"}},
            {id="shop",featureKeys={"EnableShop"}},
            {id="equipment",featureKeys={"EnableEquipment"}},
        },
        moreNavigationTabs={{id="info"}},
    }, {__index=GodSystemWindow})
    eq(window:ensureVisibleNavigationMode(),"shop")
end)

print("Navigation visibility behavior groups passed: "..passed)
