local loaded = {}
function require(name)
    if loaded[name] then return loaded[name] end
    loaded[name] = true
    -- Equipment uses one client-only transient freeze presentation bridge.
    -- The remaining domain modules stay shared and are loaded below as before.
    local folder = name == "GodSystem_FreezeClient" and "client/" or "shared/"
    local fn = assert(loadstring(readSource(folder .. name .. ".lua"), name))
    local result = fn()
    loaded[name] = result or true
    return loaded[name]
end
require "GodSystem_EquipmentService"
local E, I, S = GodSystemEquipment, GodSystemEquipmentItems, GodSystemEquipmentService
function instanceof(item, class) return item and ((item.weapon and class == "HandWeapon") or (item.player and class == "IsoPlayer")) end
local total = 0
local function test(name, fn) fn(); total = total + 1; print("PASS equipment: " .. name) end
local function eq(a,b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function near(a,b) assert(I.near(a,b), tostring(a) .. " != " .. tostring(b)) end
local function hasEntries(value)
    for _ in pairs(value) do return true end
    return false
end
local function list(rows)
    return { size = function() return #rows end, get = function(_,n) return rows[n+1] end,
        contains = function(_,v) for _,x in ipairs(rows) do if x == v then return true end end; return false end }
end
local serial = 0
local function weapon(ranged, sharp)
    serial = serial + 1
    local w = { weapon = true, id = serial, md = {}, condition = 7, maximum = 10, sharp = sharp,
        sharpness = 0.4, head = 6, headMax = 10, ranged = ranged == true, parts = {}, ammo = 0,
        fields = { minDamage = 1, maxDamage = 3, wear = 10, speed = 1, accuracy = 80, recoil = 20 } }
    function w:getID() return self.id end
    function w:getFullType() return self.ranged and "Base.M16" or "Base.Axe" end
    function w:getDisplayName() return self.name or self:getFullType() end
    function w:getName() return self.name or self:getFullType() end
    function w:setName(value) self.name=value end
    function w:isCustomName() return self.customName == true end
    function w:setCustomName(value) self.customName=value == true end
    function w:getScriptItem() return {getDisplayName=function() return "BaseDefaultWeapon" end} end
    function w:getContainer() return self.container end
    function w:getModData() return self.md end
    function w:isRanged() return self.ranged end
    function w:getAllWeaponParts() return list(self.parts) end
    function w:getOnBreak() return self.onBreak end
    function w:hasSharpness() return self.sharp == true end
    function w:hasHeadCondition() return self.sharp == true end
    function w:getSharpnessMultiplier() return (self.sharpness + 1)/2 end
    function w:getSharpness() return self.sharpness end
    function w:setSharpness(v) self.sharpness = v end
    function w:getMaxSharpness() return self.head / self.headMax end
    function w:getHeadCondition() return self.head end
    function w:getHeadConditionMax() return self.headMax end
    function w:setHeadCondition(v) self.head = v end
    function w:getCondition() return self.condition end
    function w:getConditionMax() return self.maximum end
    function w:setCondition(v) self.condition = v end
    function w:clearAllWeaponParts() self.parts = {} end
    function w:setCurrentAmmoCount(v) self.ammo = v end
    function w:getCurrentAmmoCount() return self.ammo end
    for _, field in ipairs({ "ContainsClip", "RoundChambered", "SpentRoundCount", "SpentRoundChambered" }) do
        w["set" .. field] = function(self,v) self[field] = v end
    end
    function w:isContainsClip() return self.ContainsClip == true end
    function w:isRoundChambered() return self.RoundChambered == true end
    function w:isSpentRoundChambered() return self.SpentRoundChambered == true end
    function w:getSpentRoundCount() return self.SpentRoundCount or 0 end
    for key, suffix in pairs({ minDamage = "MinDamage", maxDamage = "MaxDamage", wear = "ConditionLowerChance",
        speed = "BaseSpeed", accuracy = "HitChance", recoil = "RecoilDelay" }) do
        w["get" .. suffix] = function(self) return self.fields[key] end
        w["set" .. suffix] = function(self,v)
            if self.failWrite then self.failWrite = false; error("setter failure") end
            self.fields[key] = v
        end
    end
    function w:getMaxDamage()
        return self.sharp and self.fields.minDamage + (self.fields.maxDamage-self.fields.minDamage)*self:getSharpnessMultiplier() or self.fields.maxDamage
    end
    return w
end
local function fixture(mp)
    local root, cfg, stats = {}, {}, { stats = { completedTasks = 0 } }
    local p = { player = true, items = {}, md = {}, username = "owner", num = 0, bank = 1000000, cash = 1000 }
    local inventory = { getItems = function() return list(p.items) end }
    function p:getInventory() return inventory end
    function p:getModData() return self.md end
    function p:getPlayerNum() return self.num end
    function p:getUsername() return self.username end
    function p:isLocalPlayer() return true end
    function p:getPrimaryHandItem() return self.hand end
    function p:getSecondaryHandItem() return self.offhand end
    function p:isDead() return self.dead == true end
    function p:isAttacking() return false end
    local a = { authority = true, multiplayer = mp, store = function() return root end, config = function() return cfg end,
        data = function() return stats end, uuid = function() serial = serial+1; return "uuid-" .. serial end,
        owner = function(player) return player.username end, price = function() return 500 end,
        random = function() return 0 end, sync = function() return true end }
    a.spend = function(player,cost)
        if player.bank+player.cash < cost then return false,0,0 end
        local bank = math.min(player.bank,cost); local cash = cost-bank
        player.bank,player.cash = player.bank-bank,player.cash-cash
        return true,bank,cash
    end
    a.refund = function(player,bank,cash) player.bank=player.bank+bank; player.cash=player.cash+cash; return true end
    a.create = function(ft) return weapon(ft == "Base.M16", false) end
    a.add = function(player,w) player.items[#player.items+1] = w; w.container=inventory; return true end
    a.remove = function(player,w)
        for n,v in ipairs(player.items) do if v == w then table.remove(player.items,n); break end end
        w.container=nil; return true
    end
    local service = S.new(a)
    local f = { s=service,p=p,a=a,root=root,cfg=cfg,stats=stats }
    function f:args(action, extras)
        local view = self.s:snapshot(self.p); assert(view.ready, view.code)
        local row = view.rows[1]; local r=row.record
        serial=serial+1
        local args={ action=action, slot=1, opId="request-"..serial, revision=view.revision,
            configToken=view.config.token,cost=0,equipmentId=r and r.id, recordRevision=r and r.revision,
            generation=r and r.generation,itemId=r and r.itemId }
        for k,v in pairs(extras or {}) do args[k]=v end
        if action == "enhance" then args.attribute=args.attribute or "damage"; args.boost=args.boost or 0
            local q=E.quote(r,args.attribute,args.boost,view.config); args.cost=q and q.cost or -1
        elseif action == "repair" then args.cost=view.config.EquipmentRepairCost
        elseif action == "retrieve" then args.cost=row.retrieveCost end
        return args
    end
    function f:bind(w) self.a.add(self.p,w); self.p.hand=w; local args=self:args("bind",{itemId=tostring(w.id)}); assert(self.s:action(self.p,args).ok); return self.root.records[self.root.accounts[self.p.md[E.CharacterKey].ownerKey].slots[1]] end
    return f
end
test("SP/MP empty authority initializes without next and survives reload", function()
    assert(next == nil, "Run with the B42 missing-next constraint")
    for _,mp in ipairs({false,true}) do
        local f=fixture(mp)
        eq(f.s:root(),f.root); eq(f.root.schemaVersion,E.Schema)
        local worldId=f.root.worldId
        local view=f.s:snapshot(f.p); assert(view.ready); eq(#view.rows,3)
        local owner=view.ownerKey
        f.s=S.new(f.a)
        view=f.s:snapshot(f.p); assert(view.ready); eq(view.ownerKey,owner)
        eq(f.root.worldId,worldId); eq(f.p.bank,1000000); eq(f.p.cash,1000)
    end
end)

test("nonempty unversioned authority is rejected without overwriting data", function()
    for _,key in ipairs({"records",1}) do
        local f=fixture(); local saved={preserve=true}; f.root[key]=saved
        f.a.uuid=function() error("must not allocate identity for invalid data") end
        local root,code=f.s:root()
        eq(root,nil); eq(code,"EquipmentDataInvalid"); eq(f.root[key],saved)
        eq(f.root.schemaVersion,nil); eq(f.root.worldId,nil)
    end
end)

test("unavailable authority waits without allocating identity", function()
    local f=fixture()
    f.a.store=function() return nil end
    f.a.uuid=function() error("must wait for storage") end
    local root,code=f.s:root()
    eq(root,nil); eq(code,"EquipmentNotReady"); assert(not hasEntries(f.root))
end)

test("fixed growth, BP precision, caps and independent levels", function()
    local cfg=assert(E.config({})); local r={base=I.base(weapon(false,false)),levels={damage=0,wear=0,speed=0}}
    eq(E.quote(r,"damage",0,cfg).cost,100); eq(E.quote(r,"damage",0,cfg).chanceBP,10000)
    r.levels.damage=1; eq(E.quote(r,"damage",0,cfg).chanceBP,9000)
    eq(E.quote(r,"damage",0,cfg).cost,283)
    eq(E.quote(r,"damage",10,cfg).chanceBP,10000); assert(not E.quote(r,"damage",11,cfg))
    r.levels.damage=998; eq(E.quote(r,"damage",0,cfg).chanceBP,100)
    r.levels.damage=999; assert(not E.quote(r,"damage",0,cfg))
    local v=E.values(r.base,r.levels); near(v.maxDamage,302.7); eq(v.wear,10)
    assert(not E.config({EquipmentBaseCost=0/0})); assert(not E.config({EquipmentRepairCost=-1}))
end)
test("Lv0 binds at base, survives reload and is the failure floor without free upgrades",function()
    for _,mp in ipairs({false,true}) do
        local f=fixture(mp); local w=weapon(false,true); local r=f:bind(w)
        for _,key in ipairs({"damage","wear","speed"}) do eq(r.levels[key],0) end
        assert(E.validRecord(r)); near(I.raw(w).maxDamage,3); near(w:getBaseSpeed(),1)
        f.s=S.new(f.a)
        local view=f.s:snapshot(f.p); assert(view.ready); eq(view.rows[1].record.levels.damage,0)
        for _,bad in ipairs({-1,0.5,10000}) do
            local invalid=E.copy(r); invalid.levels.damage=bad; assert(not E.validRecord(invalid))
        end
        f.cfg.EquipmentBaseChance=50; f.a.random=function() return 9999 end
        local args=f:args("enhance"); eq(args.cost,100); local balance=f.p.bank
        eq(f.s:action(f.p,args).code,"EquipmentEnhanceFailed"); eq(f.p.bank,balance-100)
        eq(f.s:action(f.p,args).code,"EquipmentEnhanceFailed"); eq(f.p.bank,balance-100)
        eq(f.s:snapshot(f.p).rows[1].record.levels.damage,0); near(I.raw(w).maxDamage,3)
        f.cfg.EquipmentBaseChance=100; f.a.random=function() return 0 end
        assert(f.s:action(f.p,f:args("enhance")).ok)
        view=f.s:snapshot(f.p); eq(view.rows[1].record.levels.damage,1); near(I.raw(w).maxDamage,3.3)
        -- Existing positive level numbers remain intact; no automatic subtract-one migration.
        f.s=S.new(f.a); view=f.s:snapshot(f.p)
        eq(view.rows[1].record.levels.damage,1); near(view.rows[1].record.observed.maxDamage,3.3)
    end
end)
test("one configurable percentage is additive for every attribute with integer boundaries",function()
    eq(E.config({}).EquipmentGrowthPercent,10)
    local base={minDamage=2,maxDamage=4,wear=100,speed=1,accuracy=10,recoil=100,ranged=true}
    for _,percent in ipairs({0.01,10,12.5,25,100}) do
        local cfg=assert(E.config({EquipmentGrowthPercent=percent}))
        for _,level in ipairs({0,1,2,3,7,8,999,9999}) do
            local levels={damage=level,wear=level,speed=level,accuracy=level,recoil=level}
            local multiplier=1+level*percent/100
            base.ranged=true; local gun=E.values(base,levels,cfg)
            near(gun.minDamage,2*multiplier); near(gun.maxDamage,4*multiplier)
            eq(gun.wear,math.floor(100*multiplier+0.5))
            eq(gun.accuracy,math.min(100,math.floor(10*multiplier+0.5)))
            eq(gun.recoil,math.max(1,math.floor(100*math.max(0,2-multiplier)+0.5)))
            base.ranged=false; near(E.values(base,levels,cfg).speed,multiplier)
            near(E.multiplier("speed",level,cfg),multiplier)
            near(E.multiplier("recoil",level,cfg),math.max(0,2-multiplier))
        end
    end
    for _,bad in ipairs({0,-1,100.01,math.huge,0/0,"bad"}) do
        local cfg,reason=E.config({EquipmentGrowthPercent=bad})
        eq(cfg,nil); eq(reason,"EquipmentConfigInvalid")
    end
    assert(E.config({EquipmentGrowthPercent=25}).token~=E.config({}).token)
end)
test("SP/MP growth changes rebase existing levels, fence quotes and reach the sync adapter",function()
    for _,mp in ipairs({false,true}) do
        local f=fixture(mp); local w=weapon(false,true); local r=f:bind(w)
        r.levels={damage=8,wear=8,speed=8}
        local old=f:args("enhance",{attribute="speed"}); local balance=f.p.bank
        f.cfg.EquipmentGrowthPercent=25
        eq(f.s:action(f.p,old).code,"EquipmentQuoteChanged"); eq(f.p.bank,balance)
        local sent
        f.a.sync=function(_,_,_,_,_,cfg) sent=cfg; return true end
        local view=f.s:snapshot(f.p); eq(sent.EquipmentGrowthPercent,25)
        near(view.rows[1].record.actual.speed,3); near(view.rows[1].record.observed.speed,3)
        near(I.raw(w).maxDamage,9); eq(I.raw(w).wear,30)
        -- No client field can override the authoritative sandbox rule.
        local args=f:args("enhance",{attribute="speed",EquipmentGrowthPercent=99})
        assert(f.s:action(f.p,args).ok); near(w:getBaseSpeed(),3.25)
        local indexes=f.s.metrics.indexes
        for n=1,20 do f.s:reconcile(f.p,w,false) end
        eq(f.s.metrics.indexes,indexes); near(w:getBaseSpeed(),3.25)
        f.cfg.EquipmentGrowthPercent=10; f.s=S.new(f.a)
        view=f.s:snapshot(f.p); near(view.rows[1].record.observed.speed,1.9)
        near(view.rows[1].record.base.speed,1); eq(w.condition,7); near(w.sharpness,0.4)
        f.p.hand=nil; view=f.s:snapshot(f.p)
        near(view.rows[1].record.observed.speed,1); near(view.rows[1].record.actual.speed,1.9)
    end
end)
test("fixed growth keeps attachments separate and repeatedly restores the original baseline",function()
    local w=weapon(true,true)
    w.parts={{getDamage=function() return 0.5 end,getHitChance=function() return 5 end,getRecoilDelay=function() return -2 end}}
    w.fields.minDamage=1.5; w.fields.maxDamage=3.5; w.fields.accuracy=85; w.fields.recoil=18
    local base=assert(I.base(w)); local cfg=E.config({EquipmentGrowthPercent=25})
    for n=1,100 do
        assert(I.apply(w,base,{damage=1,wear=1,accuracy=1,recoil=1},cfg))
        local v=I.raw(w); near(v.minDamage,1.75); near(v.maxDamage,4.25)
        eq(v.wear,13); eq(v.accuracy,100); eq(v.recoil,13)
        assert(I.apply(w,base,nil,cfg))
        v=I.raw(w); near(v.minDamage,1.5); near(v.maxDamage,3.5); eq(v.accuracy,85); eq(v.recoil,18)
    end
    eq(w.condition,7); near(w.sharpness,0.4)
end)
test("fixed accuracy and recoil caps refuse further payment in SP and MP",function()
    for _,mp in ipairs({false,true}) do
        local f=fixture(mp); local w=weapon(true,false); local r=f:bind(w)
        r.levels.accuracy=3; r.levels.recoil=10
        local view=f.s:snapshot(f.p)
        eq(view.rows[1].record.observed.accuracy,100); eq(view.rows[1].record.observed.recoil,1)
        local balance=f.p.bank
        for _,key in ipairs({"accuracy","recoil"}) do
            eq(f.s:action(f.p,f:args("enhance",{attribute=key})).code,"EquipmentParameterCap")
            eq(f.p.bank,balance)
        end
    end
end)
test("sharpness inversion and idempotent application", function()
    for _,sharp in ipairs({false,true}) do
        local w=weapon(false,sharp); local base=assert(I.base(w)); near(base.maxDamage,3)
        for n=1,100 do assert(I.apply(w,base,{damage=80,wear=9,speed=8})) end
        near(I.raw(w).maxDamage,E.values(base,{damage=80}).maxDamage)
        assert(I.apply(w,base,nil)); near(I.raw(w).maxDamage,3); eq(w.condition,7)
    end
end)
test("target success is exact, blank is free, and fractional gaps use whole-coin billing",function()
    local cfg=E.config({}); local r={base=I.base(weapon(false,false)),levels={damage=4,wear=0,speed=0}}
    local natural=E.quoteTarget(r,"damage","",cfg)
    eq(natural.chanceBP,6561); eq(natural.boostCost,0)
    eq(E.quoteTarget(r,"damage","  ",cfg).cost,natural.cost)
    eq(E.quoteTarget(r,"damage","60",cfg).cost,natural.cost)
    local q=E.quoteTarget(r,"damage","100",cfg)
    eq(q.chanceBP,10000); eq(q.boostCost,3439); eq(q.cost,natural.cost+3439)
    eq(E.quote(r,"damage",q.boost,cfg).cost,q.cost)
    eq(E.quote(r,"damage",q.boost,cfg).chanceBP,10000)
    q=E.quoteTarget(r,"damage","80.25",cfg); eq(q.chanceBP,8025); eq(q.boostCost,1464)
    cfg.EquipmentBoostCost=7; q=E.quoteTarget(r,"damage","65.62",cfg); eq(q.boostCost,1)
    for _,bad in ipairs({"abc","-1","100.01","12.345",math.huge,0/0}) do
        eq(E.quoteTarget(r,"damage",bad,cfg),nil)
    end
    r.levels.damage=0; q=E.quoteTarget(r,"damage","100",cfg); eq(q.boostCost,0)
    r.levels.damage=998; q=E.quoteTarget(r,"damage","100",cfg); eq(q.chanceBP,10000)
end)
test("fixed speed growth is owner-only and visible as real readback",function()
    local f=fixture(); local w=weapon(false,false); local r=f:bind(w)
    local expected={ [0]=1,[1]=1.1,[2]=1.2,[3]=1.3,[7]=1.7,[8]=1.8 }
    for level,value in pairs(expected) do
        r.levels.speed=level
        local view=f.s:snapshot(f.p); near(view.rows[1].record.observed.speed,value)
        near(w:getBaseSpeed(),value)
    end
    r.levels.speed=999; near(E.values(r.base,r.levels).speed,100.9)
    f.p.hand=nil
    local view=f.s:snapshot(f.p)
    near(view.rows[1].record.observed.speed,1)
    assert(view.rows[1].record.actual.speed>1)
    f.p.hand=w; f.s:reconcile(f.p,w); assert(w:getBaseSpeed()>1)
end)
test("SP/MP insufficient funds returns a normal result without error or random draw",function()
    for _,mp in ipairs({false,true}) do
        local f=fixture(mp); local r=f:bind(weapon(false,false)); f.p.bank=0; f.p.cash=0
        local args=f:args("enhance"); local raised=0; local draws=0
        f.a.random=function() draws=draws+1; return 0 end
        local originalError=error
        error=function(...) raised=raised+1; return originalError(...) end
        local result=f.s:action(f.p,args)
        local retry=f.s:action(f.p,args)
        error=originalError
        eq(result.code,"EquipmentInsufficientFunds"); eq(retry.code,result.code)
        eq(raised,0); eq(draws,0); eq(r.levels.damage,0); eq(f.p.bank,0); eq(f.p.cash,0)
        eq(f.root.accounts[r.ownerKey].uncertainOp,nil)
    end
end)
test("permanent historical task unlocks and changed maximum", function()
    local f=fixture(); local v=f.s:snapshot(f.p); eq(#v.rows,3); assert(v.rows[2].locked)
    f.stats.stats.completedTasks=50; v=f.s:snapshot(f.p); assert(not v.rows[3].locked)
    f.cfg.EquipmentMaxSlots=1; v=f.s:snapshot(f.p); eq(#v.rows,3); assert(v.rows[2].overLimit)
    f.cfg.EquipmentMaxSlots=5; f.stats.stats.completedTasks=100; v=f.s:snapshot(f.p); assert(not v.rows[4].locked); assert(v.rows[5].locked)
end)
test("bind concrete entity, duplicate ID and copied markers", function()
    local f=fixture(); local w=weapon(false,false); local r=f:bind(w)
    local clone=weapon(false,false); clone.md[E.ItemKey]=E.copy(w.md[E.ItemKey]); f.a.add(f.p,clone)
    assert(not I.matches(clone,f.root,r)); f.s:reconcile(f.p,clone); assert(not I.marker(clone))
    clone.id=w.id; local result=f.s:action(f.p,f:args("enhance")); eq(result.code,"EquipmentIdentityInvalid")
end)
test("rename validates Unicode input, is free/idempotent, and recovery inherits the custom name", function()
    local f=fixture(); local w=weapon(false,false); local r=f:bind(w)
    local name,err=E.validateName("  消防斧 A  "); eq(name,"消防斧 A"); eq(err,nil)
    -- B42 Kahlua can surface an ISTextEntryBox java.lang.String as userdata.
    -- The shared authority must accept its actual text, not reject all UI input.
    if newproxy then
        local javaString=newproxy(true)
        getmetatable(javaString).__tostring=function() return "消防斧 7" end
        eq(E.validateName(javaString),"消防斧 7")
    end
    eq(E.nameCharacterCount("消防斧 A"),5)
    assert(not E.validateName("\nname")); assert(not E.validateName("😀")); assert(not E.validateName(string.rep("甲",31))); assert(not E.validateName(123))
    local before=f.p.bank; local rename=f:args("rename",{mode="custom",name="  消防斧 A  ",cost=0})
    local result=f.s:action(f.p,rename); assert(result.ok,result.code); eq(w:getName(),"消防斧 A"); assert(w:isCustomName()); eq(f.p.bank,before)
    r=f.root.records[r.id]; eq(r.customName,"消防斧 A"); local revision=r.revision
    local same=f:args("rename",{mode="custom",name="消防斧 A",cost=0}); result=f.s:action(f.p,same); assert(result.ok,result.code)
    eq(f.root.records[r.id].revision,revision); eq(f.p.bank,before)
    f.a.remove(f.p,w); f.p.hand=nil
    local retrieved=f.s:action(f.p,f:args("retrieve")); assert(retrieved.ok,retrieved.code)
    local replacement=f.p.items[1]; eq(replacement:getName(),"消防斧 A"); assert(replacement:isCustomName())
end)
test("Tooltip projection covers every supported registered attribute and stays extensible", function()
    local cfg=assert(E.config({EquipmentGrowthPercent=10}))
    local melee=I.base(weapon(false,false))
    local rows=E.tooltipEntries(melee,{damage=3,wear=1,speed=2,freeze=2},cfg)
    eq(#rows,4); eq(rows[1].attribute,"damage"); eq(rows[1].percent,30)
    eq(rows[2].attribute,"wear"); eq(rows[3].attribute,"speed")
    eq(rows[4].attribute,"freeze"); eq(rows[4].percent,20)
    local gun=I.base(weapon(true,false))
    rows=E.tooltipEntries(gun,{damage=1,wear=2,accuracy=3,recoil=2},cfg)
    eq(#rows,4); eq(rows[3].attribute,"accuracy"); eq(rows[4].direction,"decrease"); eq(rows[4].percent,20)
    local f=fixture(); local w=weapon(false,false); local record=f:bind(w)
    record.levels.wear=4; record.levels.speed=5; record.levels.freeze=2
    local payload=f.s:inspect({worldId=f.root.worldId,equipmentId=record.id,generation=record.generation,
        itemId=record.itemId,fullType=record.fullType,revision=record.revision})
    eq(payload.levels.damage,0); eq(payload.levels.wear,4); eq(payload.levels.speed,5); eq(payload.levels.freeze,2)
end)
test("normal success/failure charged once and technical failures roll back", function()
    local f=fixture(); local w=weapon(false,false); f:bind(w)
    local args=f:args("enhance"); local before=f.p.bank; assert(f.s:action(f.p,args).ok); eq(f.p.bank,before-100)
    assert(f.s:action(f.p,args).ok); eq(f.p.bank,before-100)
    f.a.random=function() return 9999 end
    local fail=f:args("enhance"); eq(f.s:action(f.p,fail).code,"EquipmentEnhanceFailed")
    local r=f.s:snapshot(f.p).rows[1].record; eq(r.levels.damage,0); eq(r.levels.wear,0)
    local failed=f:args("enhance"); before=f.p.bank; w.failWrite=true
    eq(f.s:action(f.p,failed).code,"EquipmentApplyFailed"); eq(f.p.bank,before); near(I.raw(w).maxDamage,3)
end)
test("retrieval commits generation once, preserves wear, old entity becomes ordinary", function()
    local f=fixture(); local w=weapon(false,false); f:bind(w); f.s:action(f.p,f:args("enhance"))
    w.condition=0; f.s:observe(w); f.a.remove(f.p,w); f.p.hand=nil
    local args=f:args("retrieve"); local result=f.s:action(f.p,args); assert(result.ok,result.code)
    local new=f.p.items[1]; eq(new.condition,1); eq(I.marker(new).generation,2)
    assert(f.s:action(f.p,args).ok); eq(#f.p.items,1)
    f.a.add(f.p,w); f.p.hand=w; f.s:reconcile(f.p,w); assert(not I.marker(w)); near(I.raw(w).maxDamage,3)
end)
test("creation and native-add failures refund original sources", function()
    for _,mode in ipairs({"create","add"}) do
        local f=fixture(); local w=weapon(false,false); f:bind(w); f.a.remove(f.p,w); f.p.hand=nil
        f.p.bank=200; f.p.cash=400
        if mode=="create" then f.a.create=function() return nil end else f.a.add=function() return false end end
        local result=f.s:action(f.p,f:args("retrieve")); eq(result.code,"EquipmentCreateFailed")
        eq(f.p.bank,200); eq(f.p.cash,400); eq(#f.p.items,0); eq(f.s:snapshot(f.p).rows[1].record.generation,1)
    end
end)
test("sync failure never refunds a committed upgrade", function()
    local f=fixture(); local w=weapon(false,false); f:bind(w); f.a.sync=function() return false end
    local args=f:args("enhance"); local before=f.p.bank
    assert(f.s:action(f.p,args).ok); eq(f.p.bank,before-100); assert(f.s:action(f.p,args).ok); eq(f.p.bank,before-100)
    local nativeRetry=false
    assert(f.s:action(f.p,f:args("repair")).ok)
    f.a.sync=function(_,_,_,_,durability) nativeRetry=durability; return true end
    f.s:reconcile(f.p,w,false); assert(nativeRetry)
end)
test("restart pending operation remains blocked while a corrupt slot is isolated", function()
    local f=fixture(); local w=weapon(false,false); f:bind(w)
    f.a.spend=function() error("lost payment outcome") end
    eq(f.s:action(f.p,f:args("enhance")).code,"EquipmentUnknown")
    f.s=S.new(f.a); assert(f.s:snapshot(f.p).blocked)
    local record=f.root.records[f.s:snapshot(f.p).rows[1].record.id]; record.levels.damage="bad"
    local view=f.s:snapshot(f.p); assert(view.ready); assert(view.blocked); assert(view.rows[1].invalid)
end)
test("unsupported bind is preflight-only and an invalid slot can be cleared without losing the archive", function()
    local f=fixture(); local bad=weapon(false,false); bad.maximum=128; f.a.add(f.p,bad)
    local beforeBank,beforeRevision=f.p.bank,f.s:snapshot(f.p).revision
    local failed=f:args("bind",{itemId=I.id(bad)})
    eq(f.s:action(f.p,failed).code,"EquipmentBindUnsupported")
    eq(f.p.bank,beforeBank); eq(f.s:snapshot(f.p).revision,beforeRevision)
    assert(not I.marker(bad)); assert(not f.s:snapshot(f.p).rows[1].record)
    local good=weapon(false,false); f.a.add(f.p,good)
    assert(f.s:action(f.p,f:args("bind",{itemId=I.id(good)})).ok)

    local bound=f.s:snapshot(f.p).rows[1].record
    local archived=f.root.records[bound.id]; archived.durability.condition="bad"
    local view=f.s:snapshot(f.p); assert(view.ready); assert(view.rows[1].invalid); eq(view.rows[1].invalidReason,"durability")
    local another=weapon(false,false); f.a.add(f.p,another)
    eq(f.s:action(f.p,f:args("bind",{itemId=I.id(another)})).code,"EquipmentSlotLocked")
    local clear=f:args("clearInvalidSlot")
    assert(f.s:action(f.p,clear).ok)
    assert(f.root.records[bound.id] == archived)
    view=f.s:snapshot(f.p); assert(view.ready); assert(not view.rows[1].invalid); assert(not view.rows[1].record)
    assert(not f.s:recordFor(good,f.root))
    assert(f.s:action(f.p,f:args("bind",{itemId=I.id(another)})).ok)
end)
test("account death inheritance and cross-account ordinary use", function()
    local f=fixture(true); local w=weapon(false,false); f:bind(w); f.s:action(f.p,f:args("enhance"))
    f.p.md={}; local view=f.s:snapshot(f.p); assert(view.rows[1].record); f.s:reconcile(f.p,w)
    assert(I.raw(w).maxDamage>3)
    f.p.username="other"; f.p.md={}; f.s:account(f.p); f.s:reconcile(f.p,w); near(I.raw(w).maxDamage,3)
    assert(not f.s:snapshot(f.p).rows[1].record)
end)
test("unbind keeps entity; quote change does not charge", function()
    local f=fixture(); local w=weapon(false,false); f:bind(w)
    local args=f:args("enhance"); f.cfg.EquipmentBaseCost=200; local before=f.p.bank
    eq(f.s:action(f.p,args).code,"EquipmentQuoteChanged"); eq(f.p.bank,before)
    assert(f.s:action(f.p,f:args("unbind")).ok); eq(#f.p.items,1); assert(not I.marker(w)); assert(not f.s:snapshot(f.p).rows[1].record)
end)
test("known-item combat checks do not rebuild inventory indexes", function()
    local f=fixture(); local w=weapon(false,false); f:bind(w); local count=f.s.metrics.indexes
    for n=1,1000 do f.s:reconcile(f.p,w,false) end
    eq(f.s.metrics.indexes,count)
end)
test("repair composite layers, no full-state charge, no raw maxima growth", function()
    local f=fixture(); local w=weapon(false,true); f:bind(w); local maximum=w.maximum
    local result=f.s:action(f.p,f:args("repair")); assert(result.ok,result.code)
    eq(w.condition,10); eq(w.head,10); near(w.sharpness,1); eq(w.maximum,maximum)
    local balance=f.p.bank; eq(f.s:action(f.p,f:args("repair")).code,"EquipmentAlreadyFull"); eq(f.p.bank,balance)
end)
test("gun recovery is empty; fractional native part precision is not sold", function()
    local f=fixture(); local w=weapon(true,false); f:bind(w); f.a.remove(f.p,w); f.p.hand=nil
    f.a.create=function() local v=weapon(true,false); v.ammo=30; v.ContainsClip=true; v.RoundChambered=true; return v end
    local result=f.s:action(f.p,f:args("retrieve")); assert(result.ok,result.code)
    local fresh=f.p.items[1]; eq(fresh.ammo,0); eq(fresh.ContainsClip,false); eq(fresh.RoundChambered,false)
    fresh.parts={{getDamage=function() return 0.25 end,getHitChance=function() return 5 end,getRecoilDelay=function() return -2.5 end}}
    eq(I.base(fresh).recoil,nil)
end)
test("zero-condition surviving gun is repairable, destructive break callbacks are gated", function()
    local f=fixture(); local w=weapon(true,false); f:bind(w); w.condition=0
    local result=f.s:action(f.p,f:args("repair")); assert(result.ok,result.code); eq(w.condition,10)
    w.condition=0; w.onBreak="Example.DestructiveBreak"
    local balance=f.p.bank; eq(f.s:action(f.p,f:args("repair")).code,"EquipmentUnsupported"); eq(f.p.bank,balance)
end)
test("native parameter cap includes current attachments", function()
    local w=weapon(true,false)
    w.parts={{getDamage=function() return 0 end,getHitChance=function() return 20 end,getRecoilDelay=function() return 0 end}}
    local base={minDamage=1,maxDamage=3,ranged=true,accuracy=80,recoil=20,wear=10}
    local levels=E.newLevels(base)
    local actual=I.target(w,base,levels)
    eq(actual.accuracy,100)
    local q,reason=E.quote({base=base,levels=levels,actual=actual},"accuracy",0,E.config({}))
    eq(q,nil); eq(reason,"EquipmentParameterCap")
end)
test("failed receipt eviction cannot turn an old request into a new charge", function()
    local f=fixture(); local w=weapon(false,false); f:bind(w); f.p.bank=0; f.p.cash=0
    local first=f:args("enhance"); eq(f.s:action(f.p,first).code,"EquipmentInsufficientFunds")
    for n=1,70 do eq(f.s:action(f.p,f:args("enhance")).code,"EquipmentInsufficientFunds") end
    f.p.bank=5000; eq(f.s:action(f.p,first).code,"EquipmentQuoteChanged"); eq(f.p.bank,5000)
end)
test("SP local profiles inherit on death without sharing equipment slots", function()
    local f=fixture(); local w=weapon(false,false); f:bind(w)
    local first=f.s:snapshot(f.p).ownerKey
    f.p.md={}; f.p.num=1; local second=f.s:snapshot(f.p); assert(second.ownerKey~=first); assert(not second.rows[1].record)
    f.p.md={}; f.p.num=0; local inherited=f.s:snapshot(f.p); eq(inherited.ownerKey,first); assert(inherited.rows[1].record)
end)
test("lost marker never reclaims levels or heals wear", function()
    local f=fixture(); local w=weapon(false,false); f:bind(w); f.s:action(f.p,f:args("enhance"))
    w.condition=2; w.md[E.ItemKey]=nil
    local state=f.s:snapshot(f.p); assert(not state.rows[1].present); near(I.raw(w).maxDamage,3); eq(w.condition,2)
end)
test("pristine fallback does not reconstruct missing authority", function()
    local f=fixture(); local w=weapon(false,false); local r=f:bind(w); f.s:action(f.p,f:args("enhance"))
    f.root.records[r.id]=nil; f.root.accounts[f.p.md[E.CharacterKey].ownerKey].slots={}
    f.s:account(f.p); assert(f.s:reconcile(f.p,w)); assert(not I.marker(w)); near(I.raw(w).maxDamage,3)
end)
test("inventory scales affect only explicit page/action indexes", function()
    for _,count in ipairs({1,200,201,1000,10000}) do
        local f=fixture(); local w=weapon(false,false); f:bind(w)
        for n=2,count do f.a.add(f.p,weapon(false,false)) end
        local before=f.s.metrics.indexes; local start=os.clock()
        local state=f.s:snapshot(f.p); assert(state.ready); eq(f.s.metrics.indexes,before+1)
        local pageMs=(os.clock()-start)*1000
        before=f.s.metrics.indexes; for n=1,20 do f.s:reconcile(f.p,w,false) end; eq(f.s.metrics.indexes,before)
        print(string.format("  equipment inventory=%d pageIndex=1 page=%.2fms attackIndexes=0",count,pageMs))
    end
end)

-- Exercise the real SP adapter, shared lifecycle and equipment UI with vanilla-shaped fixtures.
loaded.GodSystem_Core=true; loaded.GodSystem_EconomyPolicy=true; loaded.GodSystem_ShopVariants=true
for _,name in ipairs({"TimedActions/ISUpgradeWeapon","TimedActions/ISRemoveWeaponUpgrade","TimedActions/ISFixAction","TimedActions/ISCraftAction","Entity/TimedActions/ISHandcraftAction",
    "ISUI/ISCollapsableWindow","ISUI/ISScrollingListBox","ISUI/ISButton","ISUI/ISLabel","ISUI/ISTextEntryBox","ISUI/ISModalDialog"}) do loaded[name]=true end
local events={}
Events=setmetatable({}, {__index=function(t,key)
    local callbacks={}; events[key]=callbacks
    local event={Add=function(fn) callbacks[#callbacks+1]=fn end,Remove=function(fn) for n=#callbacks,1,-1 do if callbacks[n]==fn then table.remove(callbacks,n) end end end}
    rawset(t,key,event); return event
end})
local now=100000
getTimestampMs=function() return now end
local mp=false
isClient=function() return mp end; isServer=function() return false end
local live=fixture(); local player=live.p
getPlayer=function() return player end; getSpecificPlayer=function() return player end; getNumActivePlayers=function() return 1 end
getRandomUUID=function() serial=serial+1; return "00000000-0000-0000-0000-"..string.format("%012d",serial) end
ZombRand=function() return 0 end
getScriptManager=function() return {FindItem=function() return {} end} end
local stores={}
ModData={getOrCreate=function(key) stores[key]=stores[key] or {}; return stores[key] end}
SandboxVars={GodSystem={}}
GodSystemConfig={}
GodSystemEconomyPolicy={quote=function() return {finalBuy=500} end}
GodSystemShopVariants={createItem=live.a.create}
function live.p:getInventory() return self.inventory end
player.inventory={ getItems=function() return list(player.items) end,
    AddItem=function(_,w) player.items[#player.items+1]=w; w.container=player.inventory; return w end,
    Remove=function(_,w) for n,v in ipairs(player.items) do if v==w then table.remove(player.items,n);break end end; w.container=nil end,
    setDrawDirty=function() end }
GodSystemClientRuntimeEnv={gsPlayer=function() return player end}
local notifications={}
GodSystemApp={services={runtime={
    text=function(_,fallback) return fallback end,notify=function(v) notifications[#notifications+1]=v end,
    getData=function() return live.stats end,save=function() end,
    spendCurrency=function(cost) return live.a.spend(GodSystemClientRuntimeEnv.gsPlayer(),cost) end,
    refundCurrencySources=function(bank,cash) return live.a.refund(GodSystemClientRuntimeEnv.gsPlayer(),bank,cash) end,
}}}
ISUpgradeWeapon={complete=function(action) action.called=true; return true end}
ISRemoveWeaponUpgrade={complete=function(action) action.called=true; return true end}
ISFixAction={complete=function(action) action.item.condition=8; return true end}
ISCraftAction={complete=function(action) action.called=true; return true end}
ISHandcraftAction={performRecipe=function(action) action.called=true; action.character.hand.sharpness=0.8; return true end}
assert(loadstring(readSource("client/GodSystem_EquipmentClient.lua")))()
loaded.GodSystem_EquipmentClient=true
local C=GodSystemEquipmentClient
test("real SP adapter keeps account/world stores separate and restores player resolver", function()
    local old=GodSystemClientRuntimeEnv.gsPlayer
    local w=weapon(false,false); player.inventory:AddItem(w); player.hand=w
    C.request(player,false); local view=C.state(player)
    local args={action="bind",slot=1,itemId=I.id(w),revision=view.revision,configToken=view.config.token,cost=0}
    assert(C.action(player,args)); eq(GodSystemClientRuntimeEnv.gsPlayer,old)
    assert(stores.GodSystem_Equipment_SP_v1); assert(not stores.GodSystem_Equipment_MP_v1)
    local previous=GodSystemApp.services.runtime.spendCurrency
    GodSystemApp.services.runtime.spendCurrency=function() error("payment exception") end
    assert(not pcall(C.authority.adapter.spend,player,100)); eq(GodSystemClientRuntimeEnv.gsPlayer,old)
    GodSystemApp.services.runtime.spendCurrency=previous
end)
test("lifecycle uses no permanent per-tick scans and preserves vanilla actions", function()
    assert(not events.OnTick); assert(not events.OnPlayerUpdate)
    local before=C.authority.metrics.indexes
    for _,fn in ipairs(events.OnContainerUpdate) do fn() end
    for _,fn in ipairs(events.EveryOneMinute) do fn() end
    eq(C.authority.metrics.indexes,before)
    local action={character=player,weapon=player.hand}; eq(ISUpgradeWeapon.complete(action),true); assert(action.called)
    local craft={character=player}; eq(ISHandcraftAction.performRecipe(craft),true); assert(craft.called)
    eq(C.authority.metrics.indexes,before)
end)
test("lifecycle accepts B42 swing, hit-point and attack-finished callbacks once per attack", function()
    local original=C.freeze.swing; local calls=0
    C.freeze.swing=function(_,who,item) calls=calls+1; eq(who,player); eq(item,player.hand); return true end
    now=now+1000
    for _,name in ipairs({"OnWeaponSwing","OnWeaponSwingHitPoint","OnPlayerAttackFinished"}) do
        for _,fn in ipairs(events[name]) do fn(player,player.hand) end
    end
    eq(calls,1)
    now=now+251
    for _,fn in ipairs(events.OnPlayerAttackFinished) do fn(player,player.hand) end
    eq(calls,2)
    C.freeze.swing=original
end)
test("disconnect discards known native references before an ordinary reconnect", function()
    local service=C.authority
    local w=player.hand; assert(hasEntries(service.known))
    local owner=C.state(player).ownerKey
    service.lifecycle.hooks.leave(player)
    assert(not hasEntries(service.known))
    service:account(player); service:reconcile(player,w,false)
    local state=service:snapshot(player); eq(state.ownerKey,owner); assert(not state.rows[1].conflict)
end)
local Base={}
local frontSerial=0
function Base:derive() local child={}; child.__index=child; return setmetatable(child,{__index=self}) end
function Base:new(x,y,w,h) return setmetatable({x=x,y=y,width=w,height=h,items={},visible=true}, {__index=self}) end
function Base:initialise() if self.createChildren then self:createChildren() end end
function Base:instantiate() end
function Base:createChildren() end
function Base:addChild() end
function Base:addToUIManager() self.visible=true end
function Base:removeFromUIManager() end
function Base:close() self.visible=false end
function Base:getIsVisible() return self.visible end
function Base:setVisible(v) self.visible=v end
function Base:setAlwaysOnTop(v) self.alwaysOnTop=v end
function Base:bringToTop() frontSerial=frontSerial+1; self.frontOrder=frontSerial end
function Base:getYScroll() return self.yScroll or 0 end
function Base:setYScroll(value) self.yScroll=value end
function Base:setScrollHeight(value) self.scrollHeight=value end
function Base:isVScrollBarVisible() return false end
function Base:prerender() end
function Base:setName(v) self.name=v end
function Base:setTitle(v) self.title=v end
function Base:getTitle() return self.title end
-- B42.20.4 ISButton.setEnable mutates its existing color tables in place.
-- Modelling only the boolean misses shared-theme corruption in a real UI.
function Base:setEnable(v)
    self.enabled=v==true
    if not self.borderColorEnabled then
        self.borderColorEnabled=E.copy(self.borderColor)
        self.backgroundColorEnabled=E.copy(self.backgroundColor)
    end
    local border=v and self.borderColorEnabled or {r=0.7,g=0.1,b=0.1,a=0.7}
    local background=v and self.backgroundColorEnabled or {r=0,g=0,b=0,a=1}
    for _,key in ipairs({"r","g","b","a"}) do
        self.borderColor[key]=border[key]; self.backgroundColor[key]=background[key]
    end
end
function Base:setOnlyNumbers() end
function Base:setOnMouseDownFunction(target,fn) self.target=target;self.callback=fn end
function Base:clear() self.items={} end
function Base:addItem(name,item) local row={text=name,item=item,height=self.itemheight,itemindex=#self.items+1};self.items[#self.items+1]=row;return row end
function Base:getText() return self.text end
function Base:drawRect() end
function Base:drawText() end
ISCollapsableWindow=Base:derive(); ISScrollingListBox=Base:derive(); ISLabel=Base:derive(); ISButton=Base:derive(); ISTextEntryBox=Base:derive()
function ISScrollingListBox:new(x,y,w,h) local b=Base.new(self,x,y,w,h); b.font="Large"; b.fontHgt=24; return b end
function ISButton:new(x,y,w,h,title,target,onclick) local b=Base.new(self,x,y,w,h); b.title=title;b.target=target;b.onclick=onclick;return b end
function ISTextEntryBox:new(value,x,y,w,h) local b=Base.new(self,x,y,w,h);b.text=value;return b end
UIFont={Small="Small"}; getCore=function() return {getScreenWidth=function() return 1920 end,getScreenHeight=function() return 1080 end} end
getTextManager=function() return {getFontHeight=function() return 14 end,MeasureStringX=function(_,_,s) return #s*7 end} end
local lastModal
ISModalDialog=Base:derive()
function ISModalDialog:new(x,y,w,h,message,yesNo,target,onclick,num,payload)
    local d=Base.new(self,x,y,w,h);d.target=target;d.onclick=onclick;d.playerNum=num;d.payload=payload;lastModal=d;return d
end
assert(loadstring(readSource("client/GodSystem_UITheme.lua")))()
loaded.GodSystem_UITheme=true
assert(loadstring(readSource("client/GodSystem_UISafety.lua")))()
loaded.GodSystem_UISafety=true
assert(loadstring(readSource("client/GodSystem_EquipmentUI.lua")))()
test("disabling an equipment button never mutates the theme or sibling controls",function()
    local palette=E.copy(GodSystemUITheme.colors)
    GodSystemEquipmentUI.open(0)
    local window=C.windows[0]
    for _,button in ipairs({window.bind,window.enhance,window.repair,window.retrieve,window.unbind}) do
        button:setEnable(false); button:setEnable(true)
        for _,key in ipairs({"r","g","b","a"}) do
            eq(GodSystemUITheme.colors.border[key],palette.border[key])
            eq(GodSystemUITheme.colors.button[key],palette.button[key])
        end
    end
    assert(window.bind.borderColor~=window.enhance.borderColor)
    assert(window.bind.backgroundColor~=window.enhance.backgroundColor)
    window:close()
end)
test("equipment UI creates, updates quote on input and confirms exact immutable operation", function()
    SandboxVars.GodSystem.EquipmentGrowthPercent=25
    GodSystemEquipmentUI.open(0)
    local window=C.windows[0]; assert(window); eq(#window.slots.items,3)
    assert(window.alwaysOnTop, "Equipment must use the overlay band")
    for _,box in ipairs({window.slots,window.candidates,window.details,window.attributes}) do
        eq(box.doDrawItem,GodSystemUISafety.drawTextRow); eq(box.prerender,GodSystemUISafety.prerenderList)
        eq(box.font,UIFont.Small)
    end
    assert(window.unbind.enabled); assert(window.enhance.enabled); eq(window.quote.cost,100)
    assert(window.attributes.items[1].text:find("Lv0",1,true))
    eq(window.quote.chanceBP,10000); near(window.quote.current.maxDamage,3); near(window.quote.next.maxDamage,3.75)
    eq(window.boost:getText(),"")
    -- Use a non-100 natural chance so treating input as an added percentage
    -- would fail. The immutable command still carries only the quoted delta.
    local record=C.authority:root().records[C.state(player).rows[1].record.id]
    record.levels.damage=4; C.request(player,false)
    near(window.quote.current.maxDamage,6); near(window.quote.next.maxDamage,6.75)
    assert(window.attributes.items[1].text:find("x2.000",1,true))
    assert(window.details.items[#window.details.items].text:find("25%",1,true))
    window.boost.text="100"; window.boost.onTextChangeFunction(window)
    eq(window.quote.chanceBP,10000)
    local quotedCost=window.quote.cost
    local captured=window:makeArgs("enhance"); eq(captured.boost,34.39); eq(captured.cost,quotedCost)
    window:onAction(window.enhance)
    local payload=lastModal.payload
    window.boost.text=""; window.boost.onTextChangeFunction(window)
    eq(payload.boost,34.39); eq(payload.cost,quotedCost); eq(window.quote.boostCost,0)
    lastModal.onclick(lastModal.target,{internal="YES"},payload)
    eq(C.state(player).rows[1].record.levels.damage,5)
    local before=C.authority.metrics.indexes
    window:onAttribute({attribute="wear"}); window.boost.onTextChangeFunction(window)
    eq(C.authority.metrics.indexes,before)
    for _,row in ipairs(window.attributes.items) do window.attributes.doDrawItem(window.attributes,0,row,false) end
    eq(C.authority.metrics.indexes,before)
    window:onAction(window.unbind); assert(lastModal and lastModal.payload.action=="unbind")
    assert(lastModal.alwaysOnTop); assert(lastModal.frontOrder>window.frontOrder)
    local modal=lastModal
    window:bringToTop(); assert(modal.frontOrder>window.frontOrder)
    window:onAction(window.unbind); eq(lastModal,modal)
    lastModal.onclick(lastModal.target,{internal="NO"},lastModal.payload); assert(C.state(player).rows[1].record)
    window:onAction(window.unbind); lastModal.onclick(lastModal.target,{internal="YES"},lastModal.payload)
    assert(not C.state(player).rows[1].record); eq(#player.items,1)
    window:onCandidate({id=I.id(player.hand)}); window:onAction(window.bind)
    assert(C.state(player).rows[1].record)
    window:onAction(window.unbind); local abandoned=lastModal
    window:close(); assert(not window:getIsVisible())
    assert(not abandoned:getIsVisible()); eq(window.confirmation,nil)
    GodSystemEquipmentUI.open(0); assert(window.alwaysOnTop); assert(window:getIsVisible())
    window:close()
    SandboxVars.GodSystem.EquipmentGrowthPercent=nil
end)
test("MP client cannot construct local authority, ignores stale generation payloads", function()
    mp=true
    GodSystemNetwork={send=function() return true end}
    assert(loadstring(readSource("client/GodSystem_EquipmentClient.lua")))()
    C=GodSystemEquipmentClient; eq(C.authority,nil)
    local w=player.hand; local base=I.base(w); local marker={schema=1,worldId="mp-world",equipmentId="gear",generation=1,revision=2,ownerKey="mp:owner"}
    C.states[0]={ready=true,worldId="mp-world",ownerKey="mp:owner",characterId="char",config=E.config({}),rows={{record={id="gear",itemId=I.id(w),generation=1,revision=2}}}}
    C.packets[I.id(w)]={itemId=I.id(w),fullType=w:getFullType(),raw=I.raw(w),base=base,levels={damage=20,wear=0,speed=0},marker=marker,active=true,ownerKey="mp:owner",characterId="char",
        growthConfig={enabled=true,EquipmentGrowthPercent=25}}
    -- The item packet may be newer than the page; never use the local sandbox or stale page growth.
    SandboxVars.GodSystem.EquipmentGrowthPercent=99
    C.apply(player,w); near(I.raw(w).maxDamage,18)
    for n=1,20 do C.apply(player,w) end; near(I.raw(w).maxDamage,18)
    local packet=C.packets[I.id(w)]
    packet.growthConfig=nil; C.apply(player,w); near(I.raw(w).maxDamage,3)
    packet.growthConfig={enabled=true,EquipmentGrowthPercent=math.huge}; C.apply(player,w); near(I.raw(w).maxDamage,3)
    packet.growthConfig={enabled=false,EquipmentGrowthPercent=25}; C.apply(player,w); near(I.raw(w).maxDamage,3)
    packet.growthConfig={enabled=true,EquipmentGrowthPercent=5}; C.apply(player,w); near(I.raw(w).maxDamage,6)
    SandboxVars.GodSystem.EquipmentGrowthPercent=nil
    C.states[0].rows[1].record.generation=2; C.apply(player,w); near(I.raw(w).maxDamage,3)
    C.states[0].rows[1].record.generation=1; C.states[0].ownerKey="mp:other"; C.apply(player,w); near(I.raw(w).maxDamage,3)
end)
test("actual MP installer validates username, routes operations and deduplicates charges", function()
    SandboxVars.GodSystem.EquipmentGrowthPercent=25
    local sent,finished={},{}
    sendServerCommand=function(p,module,command,args) sent[#sent+1]={player=p,module=module,command=command,args=args} end
    getOnlinePlayers=function() return list({player}) end
    local nativeWearSync=0
    syncItemFields=function() nativeWearSync=nativeWearSync+1 end; syncItemModData=function() end
    GodSystemServer={refundCurrencySources=function(p,_,bank,cash) return live.a.refund(p,bank,cash) end}
    local guarded=false
    local env=setmetatable({MODULE="GodSystem",Commands={hello=function() end},playerData=function() return live.stats end,
        spendCurrency=function(p,_,amount) return live.a.spend(p,amount) end,
        storeCheckpoint=function() return true end,notifyCode=function() end,
        guard=function() if guarded then return false end; guarded=true; return true end,
        unguard=function() guarded=false end,
        finishCode=function(p,ok,code,_,payload) finished[#finished+1]={ok=ok,code=code,payload=payload} end,
    },{__index=_G})
    assert(loadstring(readSource("server/GodSystem_ServerRuntime_Equipment.lua")))()
    GodSystemServerRuntimeInstallers.GodSystem_ServerRuntime_Equipment(env)
    local service=GodSystemServer.equipment
    local state=service:snapshot(player); assert(state.ready); assert(stores.GodSystem_Equipment_MP_v1)
    local w=player.hand
    local args={opId="mp-bind-request",action="bind",slot=1,itemId=I.id(w),revision=state.revision,configToken=state.config.token,cost=0}
    env.Commands.equipmentAction(nil,nil,player,args); assert(finished[#finished].ok,finished[#finished].code); assert(not guarded)
    state=service:snapshot(player); local r=state.rows[1].record
    local enhance={opId="mp-upgrade-request",action="enhance",slot=1,itemId=r.itemId,equipmentId=r.id,recordRevision=r.revision,
        attribute="damage",boost=0,cost=100,revision=state.revision,configToken=state.config.token}
    local before=player.bank
    env.Commands.equipmentAction(nil,nil,player,enhance); assert(finished[#finished].ok); eq(player.bank,before-100)
    near(I.raw(w).maxDamage,3.75)
    env.Commands.equipmentAction(nil,nil,player,enhance); assert(finished[#finished].ok); eq(player.bank,before-100)
    local previous=player.username; player.username=nil
    env.Commands.equipmentAction(nil,nil,player,enhance); eq(finished[#finished].code,"EquipmentNotReady"); eq(player.bank,before-100)
    player.username=previous
    local indexes=service.metrics.indexes
    env.Commands.equipmentSync(nil,nil,player,{heldOnly=true}); eq(service.metrics.indexes,indexes)
    assert(service.metrics.network.messages>0)
    local hasState,hasItem=false,false
    for _,row in ipairs(sent) do
        if row.command=="equipmentState" and row.args.state.ready then hasState=true; eq(row.args.state.config.EquipmentGrowthPercent,25)
        elseif row.command=="equipmentItem" then hasItem=true; eq(row.args.growthConfig.EquipmentGrowthPercent,25) end
    end
    assert(hasState and hasItem)
    eq(nativeWearSync,0) -- Read/equip/enhance synchronization must never overwrite natural wear.
    state=service:snapshot(player); r=state.rows[1].record
    env.Commands.equipmentAction(nil,nil,player,{opId="mp-repair-request",action="repair",slot=1,itemId=r.itemId,
        equipmentId=r.id,recordRevision=r.revision,revision=state.revision,configToken=state.config.token,cost=300})
    assert(finished[#finished].ok,finished[#finished].code); eq(nativeWearSync,1)
    SandboxVars.GodSystem.EquipmentGrowthPercent=nil
end)
test("retired core stays defined but cannot be forced back into the shop", function()
    require "GodSystem_ItemConfig"
    GodSystemItemConfig.applyRuntime({["GodSystem.DurabilityCore"]={shopMode="forced"}}, {}, 1)
    eq(GodSystemItemConfig.getShopMode("GodSystem.DurabilityCore"),"disabled")
    eq(GodSystemItemConfig.getShopVariantMode("GodSystem.DurabilityCore","GodSystem.DurabilityCore"),"disabled")
    assert(not GodSystemItemConfig.isShopItemEnabled("GodSystem.DurabilityCore",true))
    assert(readSource("shared/GodSystem_Maintenance.lua"):find("GodSystem.DurabilityCore",1,true))
end)
print("Equipment behavior groups passed: " .. total)
