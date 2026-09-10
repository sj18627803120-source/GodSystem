require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISModalDialog"
require "GodSystem_EquipmentClient"
require "GodSystem_UITheme"
require "GodSystem_UISafety"

GodSystemEquipmentUI = GodSystemEquipmentUI or {}
local UI,C,E,I=GodSystemEquipmentUI,GodSystemEquipmentClient,GodSystemEquipment,GodSystemEquipmentItems
local text=C.text
local Safety=GodSystemUISafety
local function format(key,fallback,...)
    local result=text(key,fallback); local args={...}
    return (result:gsub("{(%d+)}",function(n) return tostring(args[tonumber(n)] or "") end))
end
GodSystemEquipmentWindow=ISCollapsableWindow:derive("GodSystemEquipmentWindow")
local W=GodSystemEquipmentWindow
GodSystemEquipmentRenameWindow=ISCollapsableWindow:derive("GodSystemEquipmentRenameWindow")
local N=GodSystemEquipmentRenameWindow
function N:new(parent, record)
    local core=getCore(); local o=ISCollapsableWindow.new(self,math.max(0,(core:getScreenWidth()-470)/2),math.max(0,(core:getScreenHeight()-215)/2),470,215)
    o.parent, o.record, o.playerNum=parent, E.copy(record), parent.playerNum
    o.title=text("Equipment_RenameTitle","Modify name")
    o.resizable=false; o.backgroundColor=E.copy(GodSystemUITheme.colors.shell)
    return o
end
function N:button(x,y,width,title,action)
    local button=ISButton:new(x,y,width,32,title,self,self.onAction); button.internal=action; button:initialise()
    button.backgroundColor=E.copy(GodSystemUITheme.colors.button); button.backgroundColorMouseOver=E.copy(GodSystemUITheme.colors.buttonHover)
    button.borderColor=E.copy(GodSystemUITheme.colors.border); self:addChild(button); return button
end
function N:createChildren()
    ISCollapsableWindow.createChildren(self)
    local label=ISLabel:new(14,34,18,text("Equipment_RenamePrompt","New name (up to 30 characters)"),0.8,0.85,0.95,1,UIFont.Small,true)
    label:initialise(); self:addChild(label)
    self.input=ISTextEntryBox:new(self.record.name or "",14,58,442,32); self.input:initialise(); self.input:instantiate()
    self.input.target=self; self.input.onTextChangeFunction=function(target) target:refreshInput() end; self:addChild(self.input)
    self.status=ISLabel:new(14,96,18,"",0.85,0.63,0.55,1,UIFont.Small,true); self.status:initialise(); self:addChild(self.status)
    self.confirm=self:button(14,142,136,text("Equipment_RenameConfirm","Confirm"),"custom")
    self.reset=self:button(156,142,150,text("Equipment_RenameReset","Restore default"),"default")
    self.cancel=self:button(312,142,144,text("Equipment_RenameCancel","Cancel"),"cancel")
    self:refreshInput()
end
function N:refreshInput()
    if not self.input then return end
    local raw=self.input:getText() or ""; local normalized,err=E.validateName(raw)
    local count=E.nameCharacterCount(raw)
    local detail=normalized and "" or text("NotifyMP_"..tostring(err),tostring(err))
    self.status:setName(format("Equipment_RenameCount","{1}/{2} characters",count,E.NameLimit)..(detail~="" and "  "..detail or ""))
    self.confirm:setEnable(normalized~=nil)
end
function N:onAction(button)
    if button.internal=="cancel" then self.parent.renameDialog=nil; self:close(); self:removeFromUIManager(); return end
    local args=self.parent:makeArgs("rename"); if not args then return end
    args.mode=button.internal; args.cost=0
    if args.mode=="custom" then
        local name,err=E.validateName(self.input:getText() or "")
        if not name then self:refreshInput(); return end
        args.name=name
    end
    if C.action(C.player(self.playerNum),args) then
        self.parent.renameDialog=nil; self:close(); self:removeFromUIManager(); self.parent:refreshDetails()
    end
end
function N:close()
    if self.parent and self.parent.renameDialog==self then self.parent.renameDialog=nil end
    ISCollapsableWindow.close(self)
end
function W:new(x,y,playerNum)
    local o=ISCollapsableWindow.new(self,x,y,860,650)
    o.resizable=false; o.playerNum=playerNum or 0; o.selectedSlot=1; o.attribute="damage"
    o.title=text("Equipment_Title","Equipment")
    o.backgroundColor=E.copy(GodSystemUITheme.colors.shell)
    return o
end
function W:button(x,y,width,key,fallback,action)
    local button=ISButton:new(x,y,width,34,text(key,fallback),self,self.onAction)
    button.internal=action; button:initialise()
    -- Native setEnable()/set*RGBA() mutate these tables. Never lend a
    -- control the shared palette (including the main/shop panel colors).
    button.backgroundColor=E.copy(GodSystemUITheme.colors.button)
    button.backgroundColorMouseOver=E.copy(GodSystemUITheme.colors.buttonHover)
    button.borderColor=E.copy(GodSystemUITheme.colors.border)
    self:addChild(button); return button
end
function W:list(x,y,w,h,callback)
    local list=ISScrollingListBox:new(x,y,w,h)
    list:initialise(); list:instantiate(); list.itemheight=36
    list.font=UIFont.Small; list.fontHgt=getTextManager():getFontHeight(list.font)
    list:setOnMouseDownFunction(self,callback)
    list.doDrawItem=Safety.drawTextRow
    Safety.installList(list)
    self:addChild(list); return list
end
function W:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.status=ISLabel:new(14,33,20,"",0.7,0.8,0.9,1,UIFont.Small,true)
    self.status:initialise(); self:addChild(self.status)
    self.slots=self:list(14,60,240,224,self.onSlot)
    self.candidateLabel=ISLabel:new(14,293,20,text("Equipment_SelectWeapon","Select a carried weapon"),0.7,0.8,0.9,1,UIFont.Small,true)
    self.candidateLabel:initialise(); self:addChild(self.candidateLabel)
    self.candidates=self:list(14,318,240,251,self.onCandidate)
    self.details=self:list(268,60,578,170,function() end)
    self.details.itemheight=27
    self.attributes=self:list(268,240,578,200,self.onAttribute)
    self.attributes.itemheight=40
    self.quoteLabel=ISLabel:new(268,450,22,"",0.9,0.8,0.6,1,UIFont.Small,true)
    self.quoteLabel:initialise(); self:addChild(self.quoteLabel)
    self.boostLabel=ISLabel:new(268,480,22,text("Equipment_Boost","Target success % (blank: no extra cost)"),0.7,0.8,0.9,1,UIFont.Small,true)
    self.boostLabel:initialise(); self:addChild(self.boostLabel)
    self.boost=ISTextEntryBox:new("",575,476,65,32)
    self.boost:initialise(); self.boost:instantiate(); self.boost:setOnlyNumbers(true)
    self.boost.target=self; self.boost.onTextChangeFunction=function(target) target:refreshDetails() end
    self:addChild(self.boost)
    self.enhance=self:button(650,476,196,"Equipment_Enhance","Enhance","enhance")
    self.reason=ISLabel:new(268,517,22,"",0.85,0.63,0.55,1,UIFont.Small,true)
    self.reason:initialise(); self:addChild(self.reason)
    self.repair=self:button(268,550,141,"Equipment_Repair","Repair","repair")
    self.rename=self:button(413,550,141,"Equipment_Rename","Modify name","rename")
    self.retrieve=self:button(558,550,141,"Equipment_Retrieve","Retrieve","retrieve")
    self.unbind=self:button(703,550,143,"Equipment_Unbind","Unbind","unbind")
    self.bind=self:button(14,584,240,"Equipment_Bind","Bind selected weapon","bind")
    self.clearInvalid=self:button(14,584,240,"Equipment_ClearInvalid","Clear invalid slot","clearInvalidSlot")
    self.clearInvalid:setVisible(false)
    self.note=ISLabel:new(268,595,22,text("Equipment_Limits","No attachments/ammo restored; old generations become ordinary."),0.6,0.7,0.8,1,UIFont.Small,true)
    self.note:initialise(); self:addChild(self.note)
end
function W:rebuild(state,candidates)
    self.state=state
    local previous=self.candidateId
    self.candidateId=nil
    self.candidateRows=candidates or C.candidates(C.player(self.playerNum))
    Safety.clearList(self.candidates)
    for _,row in ipairs(self.candidateRows) do
        self.candidates:addItem(row.name.." #"..row.id,row)
        if row.id==previous then self.candidates.selected=#self.candidates.items; self.candidateId=row.id end
    end
    Safety.clearList(self.slots)
    for _,row in ipairs(state and state.rows or {}) do
        local name=row.invalid and text("Equipment_InvalidSlot","Invalid equipment archive")
            or (row.record and row.record.name or text("Equipment_Empty","Empty"))
        if row.locked then
            name=row.unreachable and text("Equipment_LockedUnreachable","Locked: task target is outside the configured range")
                or format("Equipment_Locked","Locked: {1} tasks",row.target)
        end
        if row.overLimit then name=name.." "..text("Equipment_OverLimit","(over limit)") end
        self.slots:addItem(tostring(row.slot).."  "..name,row)
        if row.slot==self.selectedSlot then self.slots.selected=#self.slots.items end
    end
    self:refreshDetails()
end
function W:onSlot(row) self.selectedSlot=row.slot; self:refreshDetails() end
function W:onCandidate(row) self.candidateId=row.id; self:refreshDetails() end
function W:onAttribute(row) self.attribute=row.attribute; self:refreshDetails() end
function W:row()
    for _,row in ipairs(self.state and self.state.rows or {}) do if row.slot==self.selectedSlot then return row end end
end
function W:globalReason()
    if not self.state or not self.state.ready then return self.state and self.state.code or "EquipmentNotReady" end
    if not self.state.config.enabled then return "EquipmentDisabled" end
    if self.state.blocked then return "EquipmentUnknown" end
    if C.busy() then return "EquipmentBusy" end
end
function W:reasonCode(row)
    local global=self:globalReason(); if global then return global end
    if not row or row.locked then return "EquipmentSlotLocked" end
    if row.invalid then return "EquipmentInvalidSlot" end
    if row.conflict then return "EquipmentIdentityInvalid" end
end
function W:refreshDetails()
    if not self.details then return end
    local row=self:row(); local record=row and row.record
    local blocked=self:reasonCode(row)
    self.status:setName(blocked and text("NotifyMP_"..blocked,blocked) or format("Equipment_Progress","Completed tasks: {1}",self.state.completedTasks))
    Safety.clearList(self.details); Safety.clearList(self.attributes); self.quote=nil
    if row and row.invalid then
        local explanation=text("Equipment_InvalidSlotDetails","This slot contains an invalid equipment archive. Other slots can still be used.")
        self.details:addItem(text("Equipment_InvalidSlot","Invalid equipment archive"),{})
        self.details:addItem(explanation,{})
        self.quoteLabel:setName(""); self.quoteLabel.tooltip=nil
        self.reason:setName(Safety.fitText(explanation,UIFont.Small,578)); self.reason.tooltip=explanation
        self.enhance:setEnable(false); self.repair:setEnable(false); self.rename:setEnable(false); self.retrieve:setEnable(false); self.unbind:setEnable(false)
        self.bind:setVisible(false); self.clearInvalid:setVisible(true)
        local global=self:globalReason()
        self.clearInvalid:setEnable(global==nil)
        self.clearInvalid.tooltip=global and text("NotifyMP_"..global,global) or text("Equipment_ClearInvalidHint","Release this slot without deleting the physical weapon.")
        return
    elseif record then
        self.details:addItem(record.name.." | "..record.fullType,{})
        self.details:addItem(format("Equipment_Identity","ID: {1} / generation {2}",record.id,record.generation),{})
        self.details:addItem(row.present and text("Equipment_Carried","Carried") or text("Equipment_Missing","Not carried / possibly lost"),{})
        local d=record.durability or {}
        self.details:addItem(format("Equipment_Condition","Condition: {1}/{2}",d.condition,d.conditionMax),{})
        if d.hasHead then self.details:addItem(format("Equipment_Head","Head: {1}/{2}",d.headCondition,d.headConditionMax),{}) end
        if d.hasSharpness then self.details:addItem(format("Equipment_Sharpness","Sharpness: {1}%",math.floor(d.sharpness*100+0.5)),{}) end
        self.details:addItem(format("Equipment_GrowthRule","Lv0 = base; each level: {1}% of base; recoil decreases; not compounded.",self.state.config.EquipmentGrowthPercent),{})
        local values=record.actual or E.values(record.base,record.levels,self.state.config)
        for _,key in ipairs(E.Attributes) do
            if E.supports(record.base,key) and (key~="freeze" or self.state.config.freezeEnabled) then
                local level=record.levels[key]
                if key=="freeze" then
                    local slow=GodSystemEquipmentFreeze.strength(level,self.state.config)*100
                    self.attributes:addItem(format("Equipment_FreezeAttributeRow",
                        "Freeze Lv{1} | slow {2}% | radius {3} tiles | {4} seconds",level,
                        string.format("%.2f",slow),self.state.config.EquipmentFreezeRadius,
                        string.format("%.2f",self.state.config.EquipmentFreezeSeconds)),{attribute=key})
                    if key==self.attribute then self.attributes.selected=#self.attributes.items end
                else
                    local multiplier=E.multiplier(key,level,self.state.config)
                    local function parameters(v)
                        if not v then return "-" end
                        if key=="damage" then
                            return v.minDamage and v.maxDamage and string.format("%.3f - %.3f",v.minDamage,v.maxDamage) or "-"
                        end
                        return v[key] and string.format("%.3f",v[key]) or "-"
                    end
                    self.attributes:addItem(format("Equipment_AttributeRow","{1} Lv{2} | x{3} | target {4} | readback {5}",text("Equipment_Attr_"..key,key),level,string.format("%.3f",multiplier),parameters(values),parameters(record.observed)),{attribute=key})
                    if key==self.attribute then self.attributes.selected=#self.attributes.items end
                end
            end
        end
        if not E.supports(record.base,self.attribute) or (self.attribute=="freeze" and not self.state.config.freezeEnabled) then
            self.attribute="damage"; self.attributes.selected=1
        end
        local quote,err=E.quoteTarget(record,self.attribute,self.boost:getText(),self.state.config)
        self.quote=quote
        local quoteText=quote and format("Equipment_Quote","Cost {1} | success {2}% | extra cost {3}",quote.cost,string.format("%.2f",quote.chanceBP/100),quote.boostCost) or text("NotifyMP_"..tostring(err),tostring(err))
        self.quoteLabel:setName(Safety.fitText(quoteText,UIFont.Small,578))
        self.quoteLabel.tooltip=quote and format("Equipment_QuoteDetails","Base cost {1}; extra cost {2}; natural chance {3}%. Targets below natural chance add no cost.",quote.baseCost,quote.boostCost,string.format("%.2f",quote.baseChanceBP/100)) or quoteText
        local why=blocked or (not row.present and "EquipmentNotCarried") or (row.parameterError and "EquipmentUnsupported") or err
        local reasonText=why and text("NotifyMP_"..why,why) or text("Equipment_BaseNote","Readback is the carried instance, base values when not held; final combat modifiers still apply.")
        self.reason:setName(Safety.fitText(reasonText,UIFont.Small,578)); self.reason.tooltip=reasonText
        self.enhance:setEnable(not why and quote~=nil)
        self.repair:setTitle(text("Equipment_Repair","Repair").." "..tostring(row.repairCost))
        self.retrieve:setTitle(text("Equipment_Retrieve","Retrieve").." "..tostring(row.retrieveCost or "-"))
        self.repair:setEnable(not blocked and row.present and not I.full(d) and row.repairable)
        self.rename:setEnable(not blocked and row.present)
        self.retrieve:setEnable(not blocked and not row.present and row.retrieveCost~=nil)
        self.unbind:setEnable(not blocked)
        local repairReason=blocked or (not row.present and "EquipmentNotCarried") or (I.full(d) and "EquipmentAlreadyFull") or (not row.repairable and "EquipmentUnsupported")
        self.repair.tooltip=repairReason and text("NotifyMP_"..repairReason,repairReason) or nil
        self.rename.tooltip=(blocked or (not row.present and "EquipmentNotCarried")) and text("NotifyMP_"..tostring(blocked or "EquipmentNotCarried"),"") or nil
        self.retrieve.tooltip=row.present and text("NotifyMP_EquipmentAlreadyCarried","") or text("Equipment_ConfirmRetrieve","")
        self.unbind.tooltip=text("Equipment_ConfirmUnbind","")
    else
        self.quoteLabel:setName(""); self.quoteLabel.tooltip=nil; self.reason:setName(""); self.reason.tooltip=nil
        self.enhance:setEnable(false); self.repair:setEnable(false); self.rename:setEnable(false); self.retrieve:setEnable(false); self.unbind:setEnable(false)
    end
    self.clearInvalid:setVisible(false); self.bind:setVisible(true)
    self.bind:setEnable(not blocked and row~=nil and not record and not row.overLimit and self.candidateId~=nil)
    self.bind.tooltip=blocked and text("NotifyMP_"..blocked,blocked) or text("Equipment_SelectWeapon","")
end
function W:makeArgs(action)
    local row=self:row()
    if action=="clearInvalidSlot" then
        if self:globalReason() or not row or not row.invalid then return nil end
    elseif self:reasonCode(row) then return nil end
    local record=row.record
    local args={action=action,slot=row.slot,revision=self.state.revision,configToken=self.state.config.token,cost=0,
        equipmentId=record and record.id,recordRevision=record and record.revision,generation=record and record.generation,itemId=record and record.itemId}
    if action=="bind" then args.itemId=self.candidateId
    elseif action=="enhance" then
        if not self.quote then return nil end
        args.attribute=self.attribute; args.boost=self.quote.boost; args.cost=self.quote.cost
    elseif action=="repair" then args.cost=row.repairCost
    elseif action=="retrieve" then args.cost=row.retrieveCost end
    return args
end
function W:onAction(button)
    if self.confirmation and self.confirmation:getIsVisible() then
        Safety.presentOverlay(self.confirmation)
        return
    end
    if button.internal=="rename" then
        local row=self:row(); if self:reasonCode(row) or not row or not row.record or not row.present then return end
        if self.renameDialog and self.renameDialog:getIsVisible() then Safety.presentOverlay(self.renameDialog); return end
        local dialog=N:new(self,row.record); dialog:initialise(); self.renameDialog=dialog; Safety.presentOverlay(dialog); return
    end
    local args=self:makeArgs(button.internal); if not args then return end
    if args.action=="bind" then C.action(C.player(self.playerNum),args); self:refreshDetails(); return end
    local message=format("Equipment_ConfirmCost","Confirm {1}? Cost: {2} system coins.",button:getTitle(),args.cost)
    if args.action=="unbind" then message=text("Equipment_ConfirmUnbind","Permanently erase all cultivation data? The physical weapon is kept.")
    elseif args.action=="clearInvalidSlot" then message=text("Equipment_ConfirmClearInvalid","Release this invalid slot? The physical weapon and raw archive are kept, but its cultivation data will not be restored.")
    elseif args.action=="retrieve" then message=message.."\n"..text("Equipment_ConfirmRetrieve","Old generations lose equipment identity. No ammo or attachments restored.")
    elseif args.action=="enhance" then message=message.."\n"..format("Equipment_ConfirmEnhance","Success {1}%. Failure costs the same and loses one level (minimum Lv0).",string.format("%.2f",self.quote.chanceBP/100)) end
    local modal=ISModalDialog:new(0,0,530,210,message,true,self,function(target,pressed,payload)
        target.confirmation=nil
        if pressed.internal=="YES" then C.action(C.player(target.playerNum),payload); target:refreshDetails() end
    end,self.playerNum,E.copy(args))
    modal:initialise(); self.confirmation=modal; Safety.presentOverlay(modal)
end
function W:bringToTop()
    ISCollapsableWindow.bringToTop(self)
    if self.confirmation and self.confirmation:getIsVisible() then self.confirmation:bringToTop() end
    if self.renameDialog and self.renameDialog:getIsVisible() then self.renameDialog:bringToTop() end
end
function W:close()
    if self.confirmation then
        self.confirmation:setVisible(false); self.confirmation:removeFromUIManager(); self.confirmation=nil
    end
    if self.renameDialog then
        self.renameDialog:setVisible(false); self.renameDialog:removeFromUIManager(); self.renameDialog=nil
    end
    ISCollapsableWindow.close(self)
    self.candidateRows=nil
end
function UI.open(playerNum)
    local player=C.player(playerNum or 0); if not player then return end
    local window=C.windows[playerNum or 0]
    if not window then
        local core=getCore(); window=W:new(math.max(0,(core:getScreenWidth()-860)/2),math.max(0,(core:getScreenHeight()-650)/2),playerNum)
        window:initialise(); C.windows[playerNum or 0]=window
    end
    Safety.presentOverlay(window)
    window:rebuild(C.state(player),{}); C.request(player,false)
end
return UI
