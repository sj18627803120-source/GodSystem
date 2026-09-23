-- 42.20_3.6 equipment authority regression. Old raw-stat enhancement tests
-- are intentionally retired: equipment now owns only registered effects.
local loaded = {}
function require(name)
    if loaded[name] then return loaded[name] end
    loaded[name] = true
    local fn = assert(loadstring(readSource("shared/" .. name .. ".lua"), name))
    local result = fn(); loaded[name] = result or true; return loaded[name]
end
require "GodSystem_EquipmentService"
local E,I,S,P=GodSystemEquipment,GodSystemEquipmentItems,GodSystemEquipmentService,GodSystemEquipmentImpact
function instanceof(item,class) return item and ((item.weapon and class=="HandWeapon") or (item.player and class=="IsoPlayer")) end
local total,serial=0,0
local function test(name,fn) fn(); total=total+1; print("PASS equipment: "..name) end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function list(rows) return {size=function() return #rows end,get=function(_,n) return rows[n+1] end} end
local function weapon(ranged)
    serial=serial+1
    local item={weapon=true,id=serial,md={},condition=7,maximum=10,ranged=ranged==true}
    function item:getID() return self.id end
    function item:getFullType() return self.ranged and "Base.M16" or "Base.Axe" end
    function item:getName() return self.name or self:getFullType() end
    function item:getDisplayName() return self:getName() end
    function item:setName(v) self.name=v end
    function item:isCustomName() return self.customName==true end
    function item:setCustomName(v) self.customName=v==true end
    function item:getScriptItem() return {getDisplayName=function() return "BaseDefaultWeapon" end} end
    function item:getContainer() return self.container end
    function item:getModData() return self.md end
    function item:isRanged() return self.ranged end
    function item:getCondition() return self.condition end
    function item:getConditionMax() return self.maximum end
    function item:setCondition(v) self.condition=v end
    function item:hasHeadCondition() return false end
    function item:hasSharpness() return false end
    function item:getOnBreak() return nil end
    function item:clearAllWeaponParts() self.parts={} end
    function item:getAllWeaponParts() return list(self.parts or {}) end
    function item:setCurrentAmmoCount(v) self.ammo=v end
    function item:getCurrentAmmoCount() return self.ammo or 0 end
    function item:setContainsClip(v) self.clip=v end
    function item:setRoundChambered(v) self.chambered=v end
    function item:setSpentRoundCount(v) self.spent=v end
    function item:setSpentRoundChambered(v) self.spentChambered=v end
    return item
end
local function fixture()
    local root,cfg,stats={}, {}, {stats={completedTasks=0}}
    local p={player=true,items={},md={},username="owner",bank=999999,cash=0}
    local inv={getItems=function() return list(p.items) end}
    function p:getInventory() return inv end
    function p:getModData() return self.md end
    function p:getPlayerNum() return 0 end
    function p:getUsername() return self.username end
    function p:isLocalPlayer() return true end
    function p:getPrimaryHandItem() return self.hand end
    function p:getSecondaryHandItem() return nil end
    function p:isDead() return false end
    local a={authority=true,multiplayer=false,store=function() return root end,config=function() return cfg end,data=function() return stats end,
        uuid=function() serial=serial+1; return "uuid-"..serial end,owner=function(player) return player.username end,
        price=function() return 500 end,random=function() return 0 end,sync=function() return true end}
    function a.spend(player,cost) if player.bank<cost then return false,0,0 end; player.bank=player.bank-cost; return true,cost,0 end
    function a.refund(player,bank,cash) player.bank=player.bank+bank+cash; return true end
    function a.create(fullType) return weapon(fullType=="Base.M16") end
    function a.add(player,item) player.items[#player.items+1]=item; item.container=inv; return true end
    function a.remove(player,item) for n,v in ipairs(player.items) do if v==item then table.remove(player.items,n) end end; item.container=nil; return true end
    local s=S.new(a)
    local f={s=s,p=p,a=a,root=root,cfg=cfg}
    function f:args(action,more)
        local view=self.s:snapshot(self.p); local row=view.rows[1]; local r=row.record; serial=serial+1
        local args={action=action,opId="request-"..serial,slot=1,revision=view.revision,configToken=view.config.token,cost=0,
            equipmentId=r and r.id,itemId=r and r.itemId,generation=r and r.generation,recordRevision=r and r.revision}
        for k,v in pairs(more or {}) do args[k]=v end
        if action=="enhance" then local q=E.quote(r,args.attribute,0,view.config); args.cost=q and q.cost or -1 end
        return args
    end
    function f:bind(item)
        self.a.add(self.p,item); self.p.hand=item
        local result=self.s:action(self.p,self:args("bind",{itemId=tostring(item.id)})); assert(result.ok,result.code)
        return self.s:snapshot(self.p).rows[1].record
    end
    return f
end

test("readable candidates have no UI refusal while missing fields explain the refusal",function()
    local f=fixture(); local item=weapon(false); f.a.add(f.p,item)
    local view,candidates=f.s:snapshot(f.p)
    assert(candidates[1].bindable); eq(candidates[1].bindReason,nil)
    item.maximum=nil
    view,candidates=f.s:snapshot(f.p)
    eq(candidates[1].bindable,false); eq(candidates[1].bindReason,"EquipmentBindMissingBody")
    eq(I.marker(item),nil)
end)

test("registry exposes only named melee effects",function()
    eq(#E.Effects,3); eq(E.Effects[1],"freeze"); eq(E.Effects[2],"impact"); eq(E.Effects[3],"splash")
    local melee={weaponKind="melee",levels=E.newLevels("melee")}
    assert(E.supports(melee,"freeze")); assert(E.supports(melee,"impact")); assert(E.supports(melee,"splash"))
    eq(melee.levels.freeze,0); eq(melee.levels.impact,0); eq(melee.levels.splash,0)
    local gun={weaponKind="ranged",levels=E.newLevels("ranged")}
    assert(not E.supports(gun,"freeze")); assert(not E.supports(gun,"impact")); assert(not E.supports(gun,"splash"))
    assert(not E.quote(gun,"impact",0,E.config({}))); assert(not E.quote(gun,"splash",0,E.config({})))
    eq(E.level({levels={}},"splash"),0,"old records without the new level default to zero")
    eq(E.maxLevel(melee,"splash",E.config({})),10)
end)

test("splash uses the shared enhancement quote and an independent sandbox toggle",function()
    local f=fixture(); local record=f:bind(weapon(false)); local enabled=E.config({})
    assert(enabled.splashEnabled); assert(E.quote(record,"splash",0,enabled))
    local disabled=assert(E.config({EnableEquipmentSplash=false}))
    assert(not E.quote(record,"splash",0,disabled)); eq(select(2,E.quote(record,"splash",0,disabled)),"EquipmentSplashDisabled")
    assert(E.quote(record,"impact",0,disabled),"the splash toggle does not disable impact")
end)

test("splash tooltip projection exposes average-damage basis, radius, targets and active state",function()
    local record={weaponKind="melee",levels={freeze=0,impact=0,splash=5},effectState={}}
    local splash=E.tooltipEntries(record,E.config({}))[3]
    eq(splash.direction,"splash"); eq(splash.level,5); eq(splash.percent,50)
    eq(splash.basis,"weapon-average"); eq(splash.rule.radius,2); eq(splash.rule.targets,5); assert(splash.active)
    local disabled=E.tooltipEntries(record,E.config({EnableEquipmentSplash=false}))[3]
    assert(not disabled.active,"sandbox-disabled splash keeps its level and is marked inactive")
end)

test("impact curve, charge state and ready consumption are fixed",function()
    eq(P.rule(1).attacks,10); eq(P.rule(3).radius,2); eq(P.rule(10).targets,10); eq(P.rule(11),nil)
    local record={levels={impact=1},effectState={}}
    for n=1,9 do local state,changed=P.advance(record,1); assert(changed); eq(state.attackCount,n); assert(not state.ready) end
    local state=P.advance(record,1); eq(state.attackCount,10); assert(state.ready)
    P.consume(record); state=P.state(record); eq(state.attackCount,0); assert(not state.ready)
    record.levels.impact=0; state=P.advance(record,0); eq(state,nil); state=P.state(record); eq(state.attackCount,0); assert(not state.ready)
end)

test("binding avoids raw combat parameters and old fields are inert",function()
    local f=fixture(); local item=weapon(false); local row=f:bind(item)
    eq(row.weaponKind,"melee"); eq(row.levels.freeze,0); eq(row.levels.impact,0); eq(row.levels.splash,0)
    -- A pre-3.6 archive can retain bad legacy fields, but new rules neither
    -- read nor reject them; this mock has no raw combat getter/setter.
    local account=f.root.accounts[f.p.md[E.CharacterKey].ownerKey]
    local record=f.root.records[account.slots[1]]
    record.base={minDamage="bad",ranged=false}; record.levels.damage=999; record.levels.speed=-1
    f.s=S.new(f.a)
    local view=f.s:snapshot(f.p); assert(view.ready); eq(view.rows[1].record.levels.freeze,0); eq(view.rows[1].record.levels.impact,0)
end)

test("freeze and impact use shared economy with independent caps",function()
    local f=fixture(); f:bind(weapon(false)); local before=f.p.bank
    local freeze=f:args("enhance",{attribute="freeze"}); assert(f.s:action(f.p,freeze).ok)
    local impact=f:args("enhance",{attribute="impact"}); assert(f.s:action(f.p,impact).ok)
    assert(f.p.bank<before)
    local record=f.s:snapshot(f.p).rows[1].record; eq(record.levels.freeze,1); eq(record.levels.impact,1)
    local rootRecord=f.root.records[record.id]; rootRecord.levels.impact=10
    eq(f.s:action(f.p,f:args("enhance",{attribute="impact"})).code,"EquipmentLevelCap")
end)

test("repair, rename, unbind and retrieve retain their non-stat behavior",function()
    local f=fixture(); local item=weapon(false); f:bind(item)
    local renamed=f.s:action(f.p,f:args("rename",{mode="custom",name="冲击斧",cost=0})); assert(renamed.ok,renamed.code); eq(item:getName(),"冲击斧")
    item.condition=2; local repaired=f.s:action(f.p,f:args("repair",{cost=E.config({}).EquipmentRepairCost})); assert(repaired.ok,repaired.code); eq(item.condition,item.maximum)
    f.a.remove(f.p,item); f.p.hand=nil
    local retrieved=f.s:action(f.p,f:args("retrieve",{cost=500})); assert(retrieved.ok,retrieved.code); eq(f.p.items[1]:getName(),"冲击斧")
    local unbound=f.s:action(f.p,f:args("unbind")); assert(unbound.ok,unbound.code)
end)

test("immediate rename after binding survives partial native failure without locking the account",function()
    local f=fixture(); local item=weapon(false); f:bind(item)
    local oldSetName=item.setName
    function item:setName(value)
        if value=="Base.Axe" then return end -- restoration fails after a partial rename
        oldSetName(self,value)
    end
    function item:setCustomName() self.customName=false end -- native flag refuses the requested value
    local args=f:args("rename",{mode="custom",name="新名字",cost=0})
    local result=f.s:action(f.p,args)
    eq(result.code,"EquipmentApplyFailed")
    eq(f.s:action(f.p,args).code,"EquipmentApplyFailed")
    local view=f.s:snapshot(f.p)
    assert(view.ready,"a readable free rename must not freeze unrelated equipment operations")
    eq(view.rows[1].record.name,item:getName())
    eq(view.rows[1].record.customName,nil)
    item.setName=oldSetName
    function item:setCustomName(value) self.customName=value==true end
    local retry=f.s:action(f.p,f:args("rename",{mode="custom",name="最终名字",cost=0}))
    assert(retry.ok,retry.code)
    eq(item:getName(),"最终名字")
end)

local function composite()
    local item=weapon(false)
    item.head,item.headMax,item.sharpness=6,12,0.4
    function item:hasHeadCondition() return true end
    function item:hasSharpness() return true end
    function item:getHeadCondition() return self.head end
    function item:getHeadConditionMax() return self.headMax end
    function item:setHeadCondition(v) self.head=v end
    function item:getSharpness() return self.sharpness end
    function item:getMaxSharpness() return self.head/self.headMax end
    function item:setSharpness(v) self.sharpness=math.min(v,self:getMaxSharpness()) end
    return item
end

test("sharpness maximum uses explicit Java bridge instead of table fallback",function()
    local item=composite(); local originalType=type
    -- Simulate the bridge's Java-userdata dispatch boundary. Actual Java calls
    -- still require native/live verification; table fallback must not hide a missing wrapper.
    type=function(v) if v==item then return "userdata" end; return originalType(v) end
    local ok,value=I.call(item,"getMaxSharpness")
    type=originalType
    assert(ok); eq(value,0.5)
end)

test("composite melee binds enhances repairs and retrieves under both adapters",function()
    for _,mp in ipairs({false,true}) do
        local f=fixture(); f.a.multiplayer=mp
        local item=composite(); local row=f:bind(item)
        eq(row.weaponKind,"melee"); eq(row.durability.headCondition,6); eq(row.durability.sharpness,0.4)
        assert(f.s:action(f.p,f:args("enhance",{attribute="impact"})).ok)
        eq(item.head,6); eq(item.sharpness,0.4)
        local result=f.s:action(f.p,f:args("repair",{cost=E.config({}).EquipmentRepairCost}))
        assert(result.ok,result.code); eq(item.head,12); eq(item.sharpness,1)
        f.a.remove(f.p,item); f.p.hand=nil; f.a.create=function() return composite() end
        result=f.s:action(f.p,f:args("retrieve",{cost=500}))
        assert(result.ok,result.code); eq(f.p.items[1].head,12); eq(f.p.items[1].sharpness,1)
        eq(f.s:snapshot(f.p).rows[1].record.levels.impact,1)
    end
end)

test("missing recovery information rejects binding without leaving a slot",function()
    for _,high in ipairs({false,true}) do
        local f=fixture(); local item=composite()
        if high then item.maximum=200 else item.getMaxSharpness=nil end
        f.a.add(f.p,item); f.p.hand=item
        eq(f.s:action(f.p,f:args("bind",{itemId=tostring(item.id)})).code,"EquipmentBindUnsupported")
        local row=f.s:snapshot(f.p).rows[1]
        eq(row.record,nil); eq(I.marker(item),nil)
    end
end)

test("binding still rejects non-weapons and duplicate physical identities",function()
    local f=fixture(); local item=composite(); item.weapon=false; f.a.add(f.p,item)
    eq(f.s:action(f.p,f:args("bind",{itemId=tostring(item.id)})).code,"EquipmentIdentityInvalid")
    item.weapon=true
    local other=composite(); other.id=item.id; f.a.add(f.p,other)
    eq(f.s:action(f.p,f:args("bind",{itemId=tostring(item.id)})).code,"EquipmentIdentityInvalid")
    eq(I.marker(item),nil); eq(I.marker(other),nil)
end)

test("non-durability rollback never rewrites native durability",function()
    local f=fixture(); local item=composite(); f:bind(item)
    function item:setCondition() error("unexpected durability mutation") end
    function item:setHeadCondition() error("unexpected head mutation") end
    function item:setSharpness() error("unexpected sharpness mutation") end
    local originalName=item.setName
    function item:setName(v) if v=="FailName" then return end; originalName(self,v) end
    local result=f.s:action(f.p,f:args("rename",{mode="custom",name="FailName",cost=0}))
    eq(result.code,"EquipmentApplyFailed"); assert(f.s:snapshot(f.p).ready)
    eq(item.head,6); eq(item.sharpness,0.4)
end)

print("Equipment specs passed: "..total)
