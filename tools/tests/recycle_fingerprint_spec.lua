-- Regression coverage for bounded recycle operation receipts.
local function load(path) return assert(loadstring(readSource(path)))() end
local function eq(a,b,message) assert(a==b,message or (tostring(a).." ~= "..tostring(b))) end
local function test(name,fn) fn(); print("PASS recycle fingerprint: "..name) end

load("shared/GodSystem_RecycleFingerprint.lua")
local F=GodSystemRecycleFingerprint

local function request(count)
    local ids={}
    for i=1,count do ids[i]=tostring(i) end
    return {mode="recycle",itemIds=ids,allowDestroyContents=true,containerContentSignatures={ ["2"]="nested:2" }}
end

test("2000 items retain the legacy exact form",function()
    local value=F.fingerprint(request(2000))
    assert(string.sub(value,1,8)=="recycle|")
end)

test("large selections are sorted, bounded and sensitive to replay data",function()
    local a=request(2001)
    local value=F.fingerprint(a)
    assert(string.sub(value,1,2)=="h:")
    assert(#value<=64,#value)
    local reversed=request(2001)
    for i=1,#reversed.itemIds do reversed.itemIds[i]=tostring(#reversed.itemIds-i+1) end
    eq(F.fingerprint(reversed),value)
    reversed.itemIds[#reversed.itemIds+1]="1"
    assert(F.fingerprint(reversed)~=value)
    local mode=request(2001); mode.mode="listOnly"
    assert(F.fingerprint(mode)~=value)
    local contents=request(2001); contents.containerContentSignatures["2"]="nested:changed"
    assert(F.fingerprint(contents)~=value)
end)

test("legacy large receipts compact to the same digest",function()
    local args=request(2001)
    local parts={"recycle",args.mode,"1"}
    local ids={}
    for i=1,#args.itemIds do ids[i]=args.itemIds[i] end
    table.sort(ids)
    for i=1,#ids do parts[#parts+1]="i:"..ids[i] end
    parts[#parts+1]="s:2=nested:2"
    local legacy=table.concat(parts,"|")
    local compact=F.compactLegacy(legacy)
    eq(compact,F.fingerprint(args))
    assert(#compact<=64)
end)

test("client and server use the shared helper",function()
    local client=readSource("client/GodSystem_Network.lua")
    local server=readSource("server/GodSystem_TransactionOps.lua")
    -- The native Kahlua bundle exposes precompiled source functions here; the
    -- normal Lua runner exposes the original strings for this static wiring check.
    if type(client)=="string" and type(server)=="string" then
        assert(string.find(client,"GodSystemRecycleFingerprint.fingerprint(args)",1,true))
        assert(string.find(server,"RecycleFingerprint.fingerprint(args)",1,true))
    end
end)
