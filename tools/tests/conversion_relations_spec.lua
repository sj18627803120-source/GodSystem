local loaded = {}
function require(name)
    if loaded[name] then return loaded[name] end
    local source = readSource("shared/" .. name .. ".lua")
    local chunk = assert(loadstring(source, "@" .. name))
    loaded[name] = chunk()
    return loaded[name]
end

local Relations = require("GodSystem_ConversionRelations")
local builtin = Relations.effective({})
assert(#builtin >= 13, "B42 base conversion relationships are present")
local garbage
for _, relation in ipairs(builtin) do if relation.id == "b42:garbagebag_box" then garbage = relation end end
assert(garbage and garbage.outputs[1].count == 20, "garbage bag box has its full 20-use relation")
local visibleDisabled = Relations.all({ conversionBuiltinDisabled = { ["b42:garbagebag_box"] = true } })
local disabledGarbage
for _, relation in ipairs(visibleDisabled) do if relation.id == "b42:garbagebag_box" then disabledGarbage = relation end end
assert(disabledGarbage and disabledGarbage.disabled == true and disabledGarbage.enabled == false,
    "disabled built-ins remain visible to administrators so they can be restored")
local uiSource = readSource("client/GodSystem_ConversionRelationsUI.lua")
assert(string.find(uiSource, "GodSystemTerminalPreferences", 1, true),
    "conversion relation editor inherits terminal font preferences")
assert(string.find(uiSource, "function UI.Window:relayout()", 1, true),
    "conversion relation editor lays controls out from measured font height")
assert(string.find(uiSource, "itemName(item.sourceFullType)", 1, true),
    "conversion relation list presents localized item names before internal IDs")
assert(string.find(uiSource, 'require "GodSystem_ItemCatalog"', 1, true),
    "conversion relation editor searches through the shared item catalog")
assert(string.find(uiSource, "onTextChangeFunction", 1, true),
    "search boxes use the native ISTextEntryBox change callback for debounced candidates")
assert(string.find(uiSource, "setOnMouseDownFunction(self, self.onCandidatePicked)", 1, true),
    "candidate dropdown picks map back through the native scrolling list callback")
assert(string.find(uiSource, "carriedOutputs", 1, true) and
    string.find(uiSource, "for _, carried in ipairs(self.carriedOutputs or {}) do", 1, true),
    "outputs beyond the visible row cap are carried into saves instead of being dropped")
assert(string.find(uiSource, "resolveSelection", 1, true),
    "saving requires a selection resolved against the item catalog, not raw text")
assert(string.find(uiSource, "ConversionRelationItemMissing", 1, true),
    "client saves reject items that do not exist in the item catalog")
assert(string.find(uiSource, "function UI.Window:newRow()", 1, true) and
    string.find(uiSource, "function UI.Window:onAddOutput()", 1, true) and
    string.find(uiSource, "function UI.Window:onRemoveOutputRow(button)", 1, true),
    "the editor exposes a fixed new-relation entry plus extendable output rows")
assert(string.find(uiSource, "pendingId", 1, true),
    "after a save the editor reselects the saved relation through pendingId")
for _, painter in ipairs({"function UI.Window:drawRow", "function UI.Window:drawCandidate"}) do
    local start=assert(string.find(uiSource,painter,1,true),"custom painter exists: "..painter)
    local nextFunction=string.find(uiSource,"\nfunction UI.Window:",start+1,true)
    local body=uiSource:sub(start,nextFunction and nextFunction-1 or #uiSource)
    assert(string.find(body,"row.height or list.itemheight",1,true) and string.find(body,"list:getYScroll()",1,true)
        and string.find(body,"if bottom<=top then return nextY end",1,true),
        "conversion painter clips fully and partly visible rows: "..painter)
end
local painterStart=assert(string.find(uiSource,"function UI.Window:drawRow",1,true))
local painterEnd=assert(string.find(uiSource,"\nfunction UI.Window:reload",painterStart,true))
local painterBody=uiSource:sub(painterStart,painterEnd-1)
local painterHarness=[[
local UI={Window={}}
local UIFont={Small="small"}
local bodyHeight=14
local function font() return "body" end
local function fontHeight() return bodyHeight end
local function smallFontHeight() return 12 end
local function fit(value) return tostring(value) end
local function color() return {r=1,g=1,b=1,a=1} end
]]..painterBody..[[

return {drawRow=UI.Window.drawRow,drawCandidate=UI.Window.drawCandidate,
    setBodyHeight=function(value) bodyHeight=value end}
]]
local painter=assert(loadstring(painterHarness,"conversion-painter-test"))()
local function drawList(height,scroll)
    local list={width=240,height=height,itemheight=20,scroll=scroll,draws={}}
    function list:getYScroll() return self.scroll end
    function list:drawRect(x,y,width,h) self.draws[#self.draws+1]={kind="rect",y=y,h=h} end
    function list:drawText(value,x,y,r,g,b,a,which)
        local lineHeight=which=="small" and 12 or 0
        if lineHeight==0 then lineHeight=painterBodyHeight or 0 end
        self.draws[#self.draws+1]={kind="text",value=value,y=y,font=which}
    end
    return list
end
local window={}
local listTop=drawList(90,-30)
assert(painter.drawRow(window,listTop,0,{height=20,index=1,item={summary="hidden"}},false)==20 and #listTop.draws==0,
    "rows fully above the viewport issue no draw calls")
local listPartialTop=drawList(90,-5)
assert(painter.drawRow(window,listPartialTop,0,{height=20,index=1,item={summary="partial"}},false)==20)
assert(#listPartialTop.draws==1 and listPartialTop.draws[1].kind=="rect" and listPartialTop.draws[1].y==5
    and listPartialTop.draws[1].h==14,"partially visible top rows clip their background and omit cut-off text")
local listPartialBottom=drawList(90,0)
assert(painter.drawCandidate(window,listPartialBottom,80,{height=20,index=1,item={label="bottom",fullType="Base.Test"}},false)==100)
assert(#listPartialBottom.draws==1 and listPartialBottom.draws[1].kind=="rect"
    and listPartialBottom.draws[1].y==80 and listPartialBottom.draws[1].h==10,
    "partially visible bottom rows clip their background and omit text outside the viewport")
for _,fontSize in ipairs({14,18,22}) do
    painter.setBodyHeight(fontSize)
    local rowHeight=fontSize*2+4
    local visible=drawList(100,0)
    visible.itemheight=rowHeight
    painter.drawCandidate(window,visible,20,{height=rowHeight,index=1,item={label="item",fullType="Base.Test"}},false)
    assert(#visible.draws==3,"all candidate text lines remain visible at each supported font size")
    for _,draw in ipairs(visible.draws) do
        if draw.kind=="rect" then assert(draw.y>=0 and draw.y+draw.h<=visible.height) end
        if draw.kind=="text" then
            local fontHeight=draw.font=="small" and 12 or fontSize
            assert(draw.y>=0 and draw.y+fontHeight<=visible.height,"text is wholly inside the list at every font size")
        end
    end
end
local routerSource = readSource("server/GodSystem_ServerRuntime_RouterConfig.lua")
assert(string.find(routerSource, "if not itemExists(relation.sourceFullType) then return finishCode(player, false, \"ConversionRelationItemMissing\") end", 1, true),
    "server rejects relation saves whose source item does not exist")
assert(string.find(routerSource, "itemDisplayName(output.fullType)", 1, true) and
    string.find(routerSource, "itemDisplayName(relation.sourceFullType)", 1, true),
    "server search haystack includes resolved display names so Chinese names match in MP")
local overrideSource = readSource("shared/GodSystem_Localization_Override.lua")
assert(string.find(overrideSource, 'GodSystemFallbackText.zh["ConversionRisk_PickSource"]', 1, true) and
    string.find(overrideSource, 'GodSystemFallbackText.zh["NotifyMP_ConversionRelationItemMissing"]', 1, true),
    "new editor and MP result codes carry Chinese fallback text")
assert(not string.find(overrideSource, "ConversionRisk_DisableDelete", 1, true),
    "retired disable/delete combined key no longer ships fallback text")
assert(not string.find(overrideSource, "ConversionRisk_Restore", 1, true),
    "3.15 retired the restore-default action and its fallback text")

-- 3.15: deleted built-ins leave the administrator list and pricing entirely,
-- and only reappear when the default preset is applied again.
local removedConfig = { conversionBuiltinRemoved = { ["b42:garbagebag_box"] = true } }
local removedGarbage
for _, relation in ipairs(Relations.all(removedConfig)) do
    if relation.id == "b42:garbagebag_box" then removedGarbage = relation end
end
assert(removedGarbage == nil, "deleted built-in relations leave the administrator list")
for _, relation in ipairs(Relations.effective(removedConfig)) do
    assert(relation.id ~= "b42:garbagebag_box", "deleted built-in relations drop out of pricing")
end
local economySource = readSource("client/GodSystem_ItemEconomyUI.lua")
assert(string.find(economySource, "function GodSystemItemEconomyWindow:applyPresets(presets)", 1, true) and
    string.find(economySource, "itemConfigPresetSave", 1, true) and
    string.find(economySource, "EconomyAdmin_PresetDefaultProtected", 1, true),
    "item economy window exposes the preset dropdown, save flow and default protection")

-- 3.16: both custom list painters clamp to the visible scroll band, otherwise rows
-- scrolled out of view are drawn over the preset bar above the list.
assert(string.find(economySource, "if bottom <= top then return nextY end", 1, true),
    "catalog rows outside the visible band are skipped")
local detailPainter = string.match(economySource, "self%.detail%.doDrawItem = function%(list, y, row%)(.-)\n    end")
assert(detailPainter and string.find(detailPainter, "list:getYScroll()", 1, true) and
    string.find(detailPainter, "list.height", 1, true),
    "detail rows stay inside the visible band while scrolling")

require("GodSystem_ItemConfig")
local ItemConfig = GodSystemItemConfig
assert(ItemConfig.sanitizePresetName("   ") == nil and ItemConfig.sanitizePresetName("Default") == nil,
    "empty and default preset names are rejected")
assert(ItemConfig.sanitizePresetName("  战备  ") == "战备", "preset names are trimmed")

local data = {
    itemOverrides = { ["Base.Axe"] = { buyPrice = 50 } },
    conversionBuiltinRemoved = { ["b42:garbagebag_box"] = true },
    economyRevision = 3,
    conversionRevision = 4,
}
local store = ItemConfig.savePreset(data, "战备")
assert(store and store.active == "战备" and #store.order == 1, "saving a preset activates it")
assert(store.presets["战备"].itemOverrides["Base.Axe"].buyPrice == 50,
    "preset snapshots carry administrator item overrides")
assert(store.presets["战备"].conversionBuiltinRemoved["b42:garbagebag_box"] == true,
    "preset snapshots carry built-in deletion marks")

data.itemOverrides = {}
data.conversionBuiltinRemoved = {}
assert(ItemConfig.applyPreset(data, "战备") and data.itemOverrides["Base.Axe"].buyPrice == 50
    and data.conversionBuiltinRemoved["b42:garbagebag_box"] == true,
    "applying a preset writes the snapshot back over live data")
assert(data.economyRevision == 4 and data.conversionRevision == 5,
    "applying a preset bumps both revisions so clients resynchronize")

assert(ItemConfig.applyPreset(data, ItemConfig.PRESET_DEFAULT) and data.itemOverrides["Base.Axe"] == nil
    and data.conversionBuiltinRemoved["b42:garbagebag_box"] == nil,
    "the default preset restores the clean built-in state")
local restoredGarbage
for _, relation in ipairs(Relations.all(data)) do
    if relation.id == "b42:garbagebag_box" then restoredGarbage = relation end
end
assert(restoredGarbage ~= nil, "switching back to default brings deleted built-ins back")

local payload = ItemConfig.presetListPayload(data)
assert(payload.order[1] == "战备" and payload.active == ItemConfig.PRESET_DEFAULT,
    "preset list payload mirrors order and active preset")
assert(ItemConfig.deletePreset(data, ItemConfig.PRESET_DEFAULT) == nil and
    ItemConfig.deletePreset(data, "不存在") == nil,
    "the default preset is protected and unknown presets cannot be deleted")
store = ItemConfig.deletePreset(data, "战备")
assert(store and #store.order == 0 and store.active == ItemConfig.PRESET_DEFAULT,
    "deleting a preset removes it from the order list")

local limitData = {}
for index = 1, ItemConfig.PRESET_LIMIT do
    assert(ItemConfig.savePreset(limitData, "p" .. index) ~= nil, "presets fill up to the limit")
end
local overflow, overflowError = ItemConfig.savePreset(limitData, "overflow")
assert(overflow == nil and overflowError == "Limit", "preset count is capped at the limit")

local floors = Relations.compile({}, function(fullType)
    if fullType == "Base.Garbagebag" then return 16 end
    return 1
end, .10)
assert(floors["Base.Garbagebag_box"] == 352, "relation safety price adds margin once")
local ammoFloors = Relations.compile({}, function(fullType)
    if fullType == "Base.Bullets9mm" then return 2 end
    return 1
end, .10)
assert(ammoFloors["Base.Bullets9mmBox"] == 110, "50-round box follows its contained rounds: " .. tostring(ammoFloors["Base.Bullets9mmBox"]))
assert(ammoFloors["Base.Bullets9mmCarton"] == 1320, "12-box carton follows raw nested value with one margin: " .. tostring(ammoFloors["Base.Bullets9mmCarton"]))
assert(Relations.hasCycle({ conversionRelations = {
    ["custom:1"] = { id="custom:1", sourceFullType="Base.A", sourceCount=1, outputs={{fullType="Base.B",count=1}} },
    ["custom:2"] = { id="custom:2", sourceFullType="Base.B", sourceCount=1, outputs={{fullType="Base.A",count=1}} },
} }) == true, "direct and indirect cycles are rejected")
print("PASS conversion relations: static source, administration view, deletion marks, presets, safe floor and cycle guard")
