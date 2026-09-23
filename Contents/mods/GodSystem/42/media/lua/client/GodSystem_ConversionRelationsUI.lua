require "GodSystem_App"
require "GodSystem_UITheme"
require "GodSystem_UISafety"
require "GodSystem_TerminalPreferences"
require "GodSystem_ItemConfig"
require "GodSystem_ItemCatalog"
require "GodSystem_ConversionRelations"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"

GodSystemConversionRelationsUI = GodSystemConversionRelationsUI or {}
local UI, Colors = GodSystemConversionRelationsUI, (GodSystemUITheme or {}).colors or {}
local MAX_CANDIDATES = 20
local MAX_EDIT_OUTPUT_ROWS = 8
local MAX_CANDIDATE_VIEW = 8

local function color(key, fallback) return Colors[key] or fallback or { r=1, g=1, b=1, a=1 } end
local function label(key, fallback)
    local runtime = GodSystemApp.services.runtime
    return runtime and runtime.text and runtime.text(key, fallback) or fallback
end
local function value(box) return box and tostring(box:getInternalText() or "") or "" end
local function trimmed(text) return tostring(text or ""):match("^%s*(.-)%s*$") or "" end
local function multiplayer() return isClient and isClient() == true end
local function now() return getTimestampMs and getTimestampMs() or 0 end
local function privateButton(button, key)
    local c = color(key); button.backgroundColor = { r=c.r, g=c.g, b=c.b, a=c.a }
    button.backgroundColorMouseOver = { r=c.r, g=c.g, b=c.b, a=math.min(1, c.a + .05) }
    button.borderColor = { r=color("borderStrong").r, g=color("borderStrong").g, b=color("borderStrong").b, a=color("borderStrong").a }
end
local function notify(key, fallback)
    local runtime = GodSystemApp.services.runtime
    if runtime and runtime.notify then runtime.notify(label(key, fallback)) end
end
local function font()
    return GodSystemTerminalPreferences and GodSystemTerminalPreferences.font and GodSystemTerminalPreferences.font("body") or UIFont.Small
end
local function fontHeight()
    local manager = getTextManager and getTextManager()
    return math.max(14, math.floor(manager and manager:getFontHeight(font()) or 14))
end
local function smallFontHeight()
    local manager = getTextManager and getTextManager()
    return math.max(12, math.floor(manager and manager:getFontHeight(UIFont.Small) or 12))
end
local function fit(text, width)
    if GodSystemUISafety and GodSystemUISafety.fitText then return GodSystemUISafety.fitText(tostring(text or ""), font(), width) end
    return tostring(text or "")
end
local function itemName(fullType)
    local runtime = GodSystemApp.services.runtime
    return runtime and runtime.getItemDisplayName and runtime.getItemDisplayName(fullType, fullType) or tostring(fullType or "")
end
local function outputSummary(row)
    local output = {}
    for _, value in ipairs(row.outputs or {}) do
        output[#output + 1] = itemName(value.fullType) .. " ×" .. tostring(value.count or 1)
    end
    return table.concat(output, "，")
end

-- Client-side save/edit rejection codes mapped to localized reasons.
local REJECT = {
    ConversionRelationInvalid = { "ConversionRisk_InvalidData", "关系数据无效，保存被拒绝" },
    ConversionRelationCycle = { "ConversionRisk_CycleRejected", "保存被拒绝：该关系会形成转换循环" },
    ConversionRelationLimit = { "ConversionRisk_LimitReached", "自定义关系数量已达上限" },
    ConversionRelationUnknown = { "ConversionRisk_UnknownRelation", "关系不存在，可能已被其他管理员修改" },
    ConversionRelationItemMissing = { "ConversionRisk_ItemMissing", "物品不存在，请从候选中重新选择" },
    ConversionRevisionConflict = { "ConversionRisk_RevisionConflict", "配置已被并发修改，请重新加载列表后重试" },
}
local function notifyReject(code)
    local entry = REJECT[code]
    if entry then notify(entry[1], entry[2]) else notify(code, code) end
end

local function localRows(search, page)
    local data = GodSystemApp.services.runtime.getData()
    data.itemConfig = GodSystemItemConfig.migrate(data.itemConfig, data.adminConfig)
    local all, text = GodSystemConversionRelations.all(data.itemConfig), string.lower(trimmed(search))
    local filtered = {}
    for _, row in ipairs(all) do
        local words = row.id .. " " .. row.sourceFullType .. " " .. (row.recipeName or "") .. " " .. (row.note or "")
            .. " " .. itemName(row.sourceFullType)
        for _, out in ipairs(row.outputs or {}) do
            words = words .. " " .. tostring(out.fullType or "") .. " " .. itemName(out.fullType)
        end
        if text == "" or string.find(string.lower(words), text, 1, true) then filtered[#filtered+1] = row end
    end
    local size = 20; page = math.max(1, math.min(math.floor(tonumber(page) or 1), math.max(1, math.ceil(#filtered / size))))
    local rows = {}; for i=(page-1)*size+1, math.min(#filtered, page*size) do rows[#rows+1] = filtered[i] end
    return { rows=rows, total=#filtered, page=page, pageCount=math.max(1, math.ceil(#filtered / size)), revision=data.itemConfig.conversionRevision }
end

local function localSave(relation, selectedId, action)
    local runtime, data = GodSystemApp.services.runtime, GodSystemApp.services.runtime.getData()
    data.itemConfig = GodSystemItemConfig.migrate(data.itemConfig, data.adminConfig)
    local config, builtin = data.itemConfig, GodSystemConversionRelations.builtinById()
    if relation then
        local clean = GodSystemConversionRelations.sanitize(relation, selectedId ~= "" and selectedId or "custom:pending")
        if not clean then return false, "ConversionRelationInvalid" end
        if runtime and runtime.itemExists then
            if not runtime.itemExists(clean.sourceFullType) then return false, "ConversionRelationItemMissing" end
            for _, out in ipairs(clean.outputs) do
                if not runtime.itemExists(out.fullType) then return false, "ConversionRelationItemMissing" end
            end
        end
        if builtin[selectedId] then
            clean.id = selectedId; config.conversionBuiltinDisabled[selectedId] = nil; config.conversionBuiltinOverrides[selectedId] = clean
        else
            config.conversionRelations = config.conversionRelations or {}
            if selectedId == "" then
                local count=0; for _ in pairs(config.conversionRelations) do count=count+1 end
                if count >= 512 then return false, "ConversionRelationLimit" end
                config.conversionSequence = (tonumber(config.conversionSequence) or 0) + 1; selectedId = "custom:" .. tostring(config.conversionSequence)
            elseif not config.conversionRelations[selectedId] then return false, "ConversionRelationUnknown" end
            clean.id = selectedId; config.conversionRelations[selectedId] = clean
        end
        if GodSystemConversionRelations.hasCycle(config) then return false, "ConversionRelationCycle" end
    elseif action == "disable" then
        if not builtin[selectedId] then return false, "ConversionRelationUnknown" end
        config.conversionBuiltinDisabled[selectedId] = true
    elseif action == "enable" then
        if not builtin[selectedId] then return false, "ConversionRelationUnknown" end
        config.conversionBuiltinDisabled[selectedId] = nil
    elseif action == "delete" then
        if builtin[selectedId] then
            config.conversionBuiltinRemoved = config.conversionBuiltinRemoved or {}
            config.conversionBuiltinRemoved[selectedId] = true
            config.conversionBuiltinDisabled[selectedId] = nil
            config.conversionBuiltinOverrides[selectedId] = nil
        elseif config.conversionRelations and config.conversionRelations[selectedId] then
            config.conversionRelations[selectedId] = nil
        else return false, "ConversionRelationUnknown" end
    else return false, "ConversionRelationUnknown" end
    config.conversionRevision = math.max(1, math.floor(tonumber(config.conversionRevision) or 0) + 1)
    config.economyRevision = math.max(1, math.floor(tonumber(config.economyRevision) or 0) + 1)
    GodSystemItemConfig.applyRuntime(config.itemOverrides, config.shopVariantOverrides, config.economyRevision, config)
    if GodSystemEconomyPolicy and GodSystemEconomyPolicy.rebuildConversionFloors then GodSystemEconomyPolicy.rebuildConversionFloors() end
    runtime.economySnapshot = nil
    runtime.save()
    if GodSystemApp.services.itemConfig and GodSystemApp.services.itemConfig.handleChanged then
        GodSystemApp.services.itemConfig:handleChanged(data, "conversionRelations")
    end
    return true, nil, selectedId
end

UI.Window = ISCollapsableWindow:derive("GodSystemConversionRelationsWindow")
function UI.Window:new(x, y, width, height)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title, o.rows, o.revision, o.page, o.pageCount, o.total = label("ConversionRisk_Title", "转换风险"), {}, 1, 1, 1, 0
    o.selected, o.editingNew, o.pendingId = nil, false, nil
    o.sourceSelection, o.outputRows, o.carriedOutputs = nil, {}, {}
    o.activeField, o.candidates, o.searchDueMs, o.rowCap = nil, {}, nil, MAX_EDIT_OUTPUT_ROWS
    o.draw = { labels = {} }
    o.resizable = false; return o
end
function UI.Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.newRelation = ISButton:new(0, 0, 10, 10, label("ConversionRisk_New", "新增关系"), self, self.newRow)
    self.newRelation:initialise(); privateButton(self.newRelation, "buttonPrimary"); self:addChild(self.newRelation)
    self.search = ISTextEntryBox:new("", 0, 0, 10, 28); self.search:initialise(); self.search:instantiate()
    self.search:setPlaceholderText(label("ConversionRisk_SearchPlaceholder", "搜索物品名称或 ID")); self:addChild(self.search)
    self.find = ISButton:new(0, 0, 82, 28, label("ConversionRisk_Search", "搜索"), self, self.reload)
    self.find:initialise(); privateButton(self.find,"button"); self:addChild(self.find)
    self.prev = ISButton:new(0, 0, 86, 30, label("ConversionRisk_Previous", "上一页"), self, self.previousPage)
    self.prev:initialise(); privateButton(self.prev,"button"); self:addChild(self.prev)
    self.next = ISButton:new(0, 0, 86, 30, label("ConversionRisk_Next", "下一页"), self, self.nextPage)
    self.next:initialise(); privateButton(self.next,"button"); self:addChild(self.next)
    self.pageLabel = ISButton:new(0, 0, 232, 30, "", self, self.reload)
    self.pageLabel:initialise(); privateButton(self.pageLabel,"navTool"); self:addChild(self.pageLabel)
    self.list = ISScrollingListBox:new(0, 0, 420, 100); self.list:initialise(); self.list:instantiate()
    self.list.doDrawItem=function(list,y,row,alternate) return self:drawRow(list,y,row,alternate) end
    self.list:setOnMouseDownFunction(self,self.select); self:addChild(self.list)
    if GodSystemUISafety and GodSystemUISafety.installList then GodSystemUISafety.installList(self.list) end
    self.source = ISTextEntryBox:new("", 0, 0, 100, 28); self.source:initialise(); self.source:instantiate()
    self.source.target = self
    self.source.onTextChangeFunction = function() self:onSourceTextChanged() end
    self.source:setPlaceholderText(label("ConversionRisk_SearchPlaceholder", "搜索物品名称或 ID"))
    self.source:setMaxTextLength(120); self:addChild(self.source)
    self.sourceCount = ISTextEntryBox:new("1", 0, 0, 76, 28); self.sourceCount:initialise(); self.sourceCount:instantiate()
    self.sourceCount:setOnlyNumbers(true); self:addChild(self.sourceCount)
    self.noteEntry = ISTextEntryBox:new("", 0, 0, 100, 28); self.noteEntry:initialise(); self.noteEntry:instantiate()
    self.noteEntry:setMaxTextLength(120); self:addChild(self.noteEntry)
    self.addOutput = ISButton:new(0, 0, 120, 30, "+ " .. label("ConversionRisk_AddOutput", "添加产物"), self, self.onAddOutput)
    self.addOutput:initialise(); privateButton(self.addOutput,"button"); self:addChild(self.addOutput)
    self.save = ISButton:new(0, 0, 96, 32, label("ConversionRisk_Save", "保存"), self, self.saveRow)
    self.save:initialise(); privateButton(self.save,"buttonPrimary"); self:addChild(self.save)
    self.disableButton = ISButton:new(0, 0, 96, 32, label("ConversionRisk_Disable", "禁用"), self, self.disableRow)
    self.disableButton:initialise(); privateButton(self.disableButton,"button"); self:addChild(self.disableButton)
    self.deleteButton = ISButton:new(0, 0, 96, 32, label("ConversionRisk_Delete", "删除"), self, self.deleteRow)
    self.deleteButton:initialise(); privateButton(self.deleteButton,"buttonDanger"); self:addChild(self.deleteButton)
    self.closeButton = ISButton:new(0, 0, 96, 30, label("Btn_Close", "关闭"), self, self.close)
    self.closeButton:initialise(); privateButton(self.closeButton,"button"); self:addChild(self.closeButton)
    -- Candidate picker is added last so it draws and clicks above every sibling.
    self.candidateList = ISScrollingListBox:new(0, 0, 100, 40); self.candidateList:initialise(); self.candidateList:instantiate()
    self.candidateList.doDrawItem=function(list,y,row,alternate) return self:drawCandidate(list,y,row,alternate) end
    self.candidateList:setOnMouseDownFunction(self, self.onCandidatePicked)
    self.candidateList:setVisible(false); self:addChild(self.candidateList)
    if GodSystemUISafety and GodSystemUISafety.installList then GodSystemUISafety.installList(self.candidateList) end
    self:relayout()
    self:clearEditorToNew()
    self:reload()
end
function UI.Window:relayout()
    local fh, smallH = fontHeight(), smallFontHeight()
    local inputH, labelH, gap = math.max(30, fh + 10), math.max(18, fh + 4), 6
    local outer, leftW = 12, math.max(300, math.floor(self.width * .42))
    leftW = math.min(leftW, self.width - 470)
    local rightX = outer + leftW + gap
    local rightW = self.width - rightX - outer
    local sourceColW = math.max(170, math.floor(rightW * .40))
    local arrowW = math.max(26, fh + 8)
    local outputX = rightX + sourceColW + arrowW
    local outputColW = math.max(150, self.width - outer - outputX)
    local countW, removeW = 76, 64
    local outputSearchW = math.max(110, outputColW - countW - removeW - gap * 2)
    local contentTop = 18 + fh + 8
    local footerY = self.height - inputH - 14
    local draw = { labels = {} }
    self.draw = draw
    draw.hint = { y = 18 }
    self.newRelation:setX(outer); self.newRelation:setY(contentTop); self.newRelation:setWidth(leftW); self.newRelation:setHeight(inputH)
    local searchY = contentTop + inputH + gap
    local searchW = leftW - 86 - gap
    self.search:setX(outer); self.search:setY(searchY); self.search:setWidth(searchW); self.search:setHeight(inputH)
    self.find:setX(outer + searchW + gap); self.find:setY(searchY); self.find:setWidth(86); self.find:setHeight(inputH)
    local listY = searchY + inputH + gap
    self.list:setX(outer); self.list:setY(listY); self.list:setWidth(leftW); self.list:setHeight(math.max(70, footerY - listY - gap))
    self.list.itemheight = math.max(26, fh + 12)
    if GodSystemUISafety and GodSystemUISafety.syncListGeometry then GodSystemUISafety.syncListGeometry(self.list) end
    self.prev:setX(outer); self.prev:setY(footerY); self.prev:setWidth(88); self.prev:setHeight(inputH)
    self.next:setX(outer + 96); self.next:setY(footerY); self.next:setWidth(88); self.next:setHeight(inputH)
    self.pageLabel:setX(outer + 192); self.pageLabel:setY(footerY); self.pageLabel:setWidth(math.max(120, leftW - 192)); self.pageLabel:setHeight(inputH)
    self.closeButton:setX(self.width - outer - 104); self.closeButton:setY(footerY); self.closeButton:setWidth(104); self.closeButton:setHeight(inputH)
    local headerY = contentTop
    draw.labels[#draw.labels + 1] = { x=rightX, y=headerY, text=label("ConversionRisk_Source", "来源物品"), width=sourceColW }
    draw.labels[#draw.labels + 1] = { x=outputX, y=headerY, text=label("ConversionRisk_Outputs", "产物物品"), width=outputSearchW }
    draw.labels[#draw.labels + 1] = { x=outputX + outputSearchW + gap, y=headerY, text=label("ConversionRisk_Count", "数量"), width=countW }
    local rowsTop = headerY + labelH + 2
    self.source:setX(rightX); self.source:setY(rowsTop); self.source:setWidth(sourceColW); self.source:setHeight(inputH)
    draw.sourceHint = { x=rightX, y=rowsTop + inputH + 2, width=sourceColW }
    local countLabelY = draw.sourceHint.y + smallH + 4
    draw.labels[#draw.labels + 1] = { x=rightX, y=countLabelY, text=label("ConversionRisk_SourceCount", "来源数量"), width=sourceColW }
    self.sourceCount:setX(rightX); self.sourceCount:setY(countLabelY + labelH); self.sourceCount:setWidth(countW); self.sourceCount:setHeight(inputH)
    draw.carried = { x=rightX, y=countLabelY + labelH + inputH + 6, width=sourceColW }
    draw.arrow = { x=rightX + sourceColW + math.floor((arrowW - fh) / 2), y=rowsTop + math.max(0, math.floor((inputH - fh) / 2)) }
    local buttonY = footerY
    local closeW = 104
    local actionW = math.max(180, rightW - closeW - gap)
    local buttonW = math.floor((actionW - gap * 2) / 3)
    self.save:setX(rightX); self.save:setY(buttonY); self.save:setWidth(buttonW); self.save:setHeight(inputH)
    self.disableButton:setX(rightX + buttonW + gap); self.disableButton:setY(buttonY); self.disableButton:setWidth(buttonW); self.disableButton:setHeight(inputH)
    self.deleteButton:setX(rightX + (buttonW + gap) * 2); self.deleteButton:setY(buttonY); self.deleteButton:setWidth(actionW - (buttonW + gap) * 2); self.deleteButton:setHeight(inputH)
    local noteY = buttonY - gap - inputH
    draw.labels[#draw.labels + 1] = { x=rightX, y=noteY - labelH, text=label("ConversionRisk_Note", "备注"), width=rightW }
    self.noteEntry:setX(rightX); self.noteEntry:setY(noteY); self.noteEntry:setWidth(rightW); self.noteEntry:setHeight(inputH)
    local rowsBottom = noteY - labelH - gap * 2
    local rowStep = inputH + 4
    local maxVisible = math.max(1, math.floor((rowsBottom - rowsTop + 4) / rowStep))
    self.rowCap = math.min(MAX_EDIT_OUTPUT_ROWS, maxVisible)
    local rowY = rowsTop
    local singleRow = #self.outputRows == 1
    for _, row in ipairs(self.outputRows) do
        row.search:setX(outputX); row.search:setY(rowY); row.search:setWidth(outputSearchW); row.search:setHeight(inputH)
        row.count:setX(outputX + outputSearchW + gap); row.count:setY(rowY); row.count:setWidth(countW); row.count:setHeight(inputH)
        row.remove:setX(outputX + outputSearchW + gap + countW + gap); row.remove:setY(rowY); row.remove:setWidth(removeW); row.remove:setHeight(inputH)
        row.remove:setVisible(not singleRow)
        row.geo = { x=outputX, y=rowY, w=outputColW, h=inputH }
        rowY = rowY + rowStep
    end
    self.addOutput:setX(outputX); self.addOutput:setY(rowY)
    self.addOutput:setWidth(math.min(220, outputSearchW + countW + removeW + gap * 2)); self.addOutput:setHeight(inputH)
    self.addOutput:setEnable(#self.outputRows < self.rowCap)
    self.candidateList.itemheight = fh + smallH + 6
    local field = self.activeField
    if field then
        local geo, columnW
        if field.kind == "source" then
            geo, columnW = { x=rightX, y=rowsTop, w=sourceColW, h=inputH }, sourceColW
        elseif field.row and field.row.geo then
            geo, columnW = field.row.geo, outputColW
        end
        local visible = math.min(#self.candidates, MAX_CANDIDATE_VIEW)
        if geo and visible > 0 then
            self.candidateList:setX(geo.x); self.candidateList:setY(geo.y + geo.h + 1)
            self.candidateList:setWidth(math.min(columnW, self.width - outer - geo.x))
            self.candidateList:setHeight(visible * self.candidateList.itemheight)
            if GodSystemUISafety and GodSystemUISafety.syncListGeometry then GodSystemUISafety.syncListGeometry(self.candidateList) end
        end
    end
    local controls = { self.newRelation, self.search, self.find, self.prev, self.next, self.pageLabel, self.closeButton,
        self.source, self.sourceCount, self.noteEntry, self.addOutput, self.save, self.disableButton, self.deleteButton }
    for _, control in ipairs(controls) do
        control.font = font(); if control.setFont then control:setFont(font()) end
    end
    for _, row in ipairs(self.outputRows) do
        row.search.font = font(); row.search:setFont(font())
        row.count.font = font(); row.count:setFont(font())
        row.remove.font = font()
    end
end
function UI.Window:prerender()
    ISCollapsableWindow.prerender(self)
    local shell,border=color("shell"),color("borderStrong")
    self:drawRect(0,16,self.width,self.height-16,shell.a,shell.r,shell.g,shell.b)
    self:drawRectBorder(1,17,self.width-2,self.height-18,border.a,border.r,border.g,border.b)
    if self.searchDueMs and now() >= self.searchDueMs then
        self.searchDueMs = nil
        self:refreshCandidates()
    end
    local draw = self.draw or {}
    local c, dim = color("text"), color("dimText")
    if draw.hint then
        local hint = label("ConversionRisk_Hint", "选择关系后可在右侧编辑；搜索框需从候选中选择真实物品；内置关系可禁用或删除，切换预设可整体找回。")
        self:drawText(fit(hint, self.width - 24), 12, draw.hint.y, dim.r, dim.g, dim.b, dim.a, font())
    end
    for _, entry in ipairs(draw.labels or {}) do
        self:drawText(fit(entry.text, entry.width or 200), entry.x, entry.y, c.r, c.g, c.b, c.a, font())
    end
    if draw.arrow then self:drawText("→", draw.arrow.x, draw.arrow.y, c.r, c.g, c.b, c.a, font()) end
    if draw.sourceHint and self.sourceSelection and self.sourceSelection.fullType ~= "" then
        self:drawText(fit(self.sourceSelection.fullType, draw.sourceHint.width), draw.sourceHint.x, draw.sourceHint.y,
            dim.r, dim.g, dim.b, dim.a, UIFont.Small)
    end
    if draw.carried and #(self.carriedOutputs or {}) > 0 then
        local carried = label("ConversionRisk_Carried", "另有 %d 个产物未显示，保存时会原样保留")
        carried = string.format(carried, #self.carriedOutputs)
        self:drawText(fit(carried, draw.carried.width), draw.carried.x, draw.carried.y, dim.r, dim.g, dim.b, dim.a, font())
    end
end
function UI.Window:drawRow(list,y,row,alternate)
    local height=row.height or list.itemheight
    local nextY=y+height
    local scroll=list:getYScroll()
    local top=math.max(y+scroll,0)
    local bottom=math.min(nextY-1+scroll,list.height)
    if bottom<=top then return nextY end
    local background=alternate and color("rowAlt") or color("row")
    list:drawRect(0,top-scroll,list.width,bottom-top,background.a,background.r,background.g,background.b)
    if list.selected==row.index then
        local selected=color("rowSelect")
        list:drawRect(0,top-scroll,list.width,bottom-top,selected.a,selected.r,selected.g,selected.b)
    end
    local item=row.item or {}
    local textColor = item.disabled and color("dimText") or color("text")
    local textY = y + math.max(2, math.floor((height - fontHeight()) / 2))
    if textY+scroll>=1 and textY+scroll+fontHeight()<=list.height-1 then
        list:drawText(fit(item.summary or "",list.width-16),6,textY,textColor.r,textColor.g,textColor.b,textColor.a,font())
    end
    return nextY
end
function UI.Window:drawCandidate(list,y,row,alternate)
    local height=row.height or list.itemheight
    local nextY=y+height
    local scroll=list:getYScroll()
    local top=math.max(y+scroll,0)
    local bottom=math.min(nextY-1+scroll,list.height)
    if bottom<=top then return nextY end
    local background=alternate and color("rowAlt") or color("row")
    list:drawRect(0,top-scroll,list.width,bottom-top,background.a,background.r,background.g,background.b)
    if list.selected==row.index then
        local selected=color("rowSelect")
        list:drawRect(0,top-scroll,list.width,bottom-top,selected.a,selected.r,selected.g,selected.b)
    end
    local candidate=row.item or {}
    local c, dim = color("text"), color("dimText")
    local labelY=y+2
    if labelY+scroll>=1 and labelY+scroll+fontHeight()<=list.height-1 then
        list:drawText(fit(candidate.label or "",list.width-12),6,labelY,c.r,c.g,c.b,c.a,font())
    end
    local typeY=y+fontHeight()+2
    if typeY+scroll>=1 and typeY+scroll+smallFontHeight()<=list.height-1 then
        list:drawText(fit(candidate.fullType or "",list.width-12),6,typeY,dim.r,dim.g,dim.b,dim.a,UIFont.Small)
    end
    return nextY
end
function UI.Window:reload()
    if multiplayer() then
        if GodSystemNetwork and GodSystemNetwork.send then GodSystemNetwork.send("itemConfigRelationsGet",{search=value(self.search),page=self.page}) end
    else self:apply(localRows(value(self.search),self.page)) end
end
function UI.Window:apply(payload)
    self.rows,self.revision=payload.rows or {},tonumber(payload.revision) or 1
    self.page,self.pageCount=tonumber(payload.page) or 1,tonumber(payload.pageCount) or 1
    self.total=tonumber(payload.total) or #self.rows
    self.list:clear()
    local pending = self.pendingId
    for index, item in ipairs(self.rows) do
        item.summary = (item.disabled and ("[" .. label("ConversionRisk_Disabled","已禁用") .. "] ") or "")
            .. itemName(item.sourceFullType) .. "  →  " .. outputSummary(item)
        self.list:addItem(item.id or item.sourceFullType, item)
        if pending and item.id == pending then self.list.selected = index end
    end
    self.pageLabel:setTitle(string.format(label("ConversionRisk_Page", "第 %d/%d 页，共 %d 条"),self.page,self.pageCount,self.total))
    self.prev:setEnable(self.page>1); self.next:setEnable(self.page<self.pageCount)
    if pending then
        for _, item in ipairs(self.rows) do
            if item.id == pending then self:select(item) break end
        end
        self.pendingId = nil
    end
end
function UI.Window:previousPage() self.page=math.max(1,self.page-1); self:reload() end
function UI.Window:nextPage() self.page=math.min(self.pageCount,self.page+1); self:reload() end
function UI.Window:select(row)
    row=row and (row.item or row) or nil
    if type(row)~="table" or not row.sourceFullType then return end
    self.pendingId=nil
    self.selected, self.editingNew = row, false
    self.sourceSelection = { fullType = tostring(row.sourceFullType), label = itemName(row.sourceFullType) }
    self.source:setText(self.sourceSelection.label)
    self.sourceCount:setText(tostring(row.sourceCount or 1))
    self.noteEntry:setText(tostring(row.note or ""))
    self:rebuildOutputRows(row.outputs)
    self:updateEditorButtons()
end
function UI.Window:clearEditorToNew()
    self.selected, self.editingNew, self.pendingId = nil, true, nil
    self.sourceSelection = nil
    self.source:setText("")
    self.sourceCount:setText("1")
    self.noteEntry:setText("")
    self:rebuildOutputRows(nil)
    self:updateEditorButtons()
end
function UI.Window:newRow() self:clearEditorToNew() end
function UI.Window:rebuildOutputRows(outputs)
    self.activeField = nil
    self.candidates = {}
    self.candidateList:setVisible(false)
    while #self.outputRows > 0 do
        local row = table.remove(self.outputRows)
        self:removeChild(row.search); self:removeChild(row.count); self:removeChild(row.remove)
    end
    local rows = type(outputs) == "table" and outputs or {}
    local cap = self.rowCap or MAX_EDIT_OUTPUT_ROWS
    local editable = math.min(#rows, cap)
    self.carriedOutputs = {}
    for index = 1, editable do self:createOutputRow(rows[index]) end
    for index = editable + 1, #rows do self.carriedOutputs[#self.carriedOutputs + 1] = rows[index] end
    if #self.outputRows == 0 then self:createOutputRow(nil) end
    self:relayout()
end
function UI.Window:createOutputRow(prefill)
    local row = { selection = nil, geo = nil }
    row.search = ISTextEntryBox:new("", 0, 0, 110, 28)
    row.search:initialise(); row.search:instantiate()
    row.search.target = self
    row.search.onTextChangeFunction = function() self:onOutputTextChanged(row) end
    row.search:setPlaceholderText(label("ConversionRisk_SearchPlaceholder", "搜索物品名称或 ID"))
    row.search:setMaxTextLength(120)
    self:addChild(row.search)
    row.count = ISTextEntryBox:new("1", 0, 0, 76, 28)
    row.count:initialise(); row.count:instantiate()
    row.count:setOnlyNumbers(true)
    self:addChild(row.count)
    row.remove = ISButton:new(0, 0, 64, 28, label("ConversionRisk_Delete", "删除"), self, self.onRemoveOutputRow)
    row.remove:initialise(); privateButton(row.remove, "buttonDanger")
    row.remove.row = row
    self:addChild(row.remove)
    if type(prefill) == "table" and prefill.fullType then
        row.selection = { fullType = tostring(prefill.fullType), label = itemName(prefill.fullType) }
        row.search:setText(row.selection.label)
        row.count:setText(tostring(prefill.count or 1))
    end
    self.outputRows[#self.outputRows + 1] = row
    return row
end
function UI.Window:onAddOutput()
    if #self.outputRows >= (self.rowCap or MAX_EDIT_OUTPUT_ROWS) then
        notify("ConversionRisk_OutputLimit", "产物行数已达界面上限，超出部分保存时会保留")
        return
    end
    self:createOutputRow(nil)
    self:relayout()
end
function UI.Window:onRemoveOutputRow(button)
    local row = button and button.row or nil
    if not row then return end
    for index, candidate in ipairs(self.outputRows) do
        if candidate == row then
            if self.activeField and self.activeField.row == row then
                self.activeField = nil; self:hideCandidates()
            end
            self:removeChild(row.search); self:removeChild(row.count); self:removeChild(row.remove)
            table.remove(self.outputRows, index)
            break
        end
    end
    if #self.outputRows == 0 then self:createOutputRow(nil) end
    self:relayout()
end
function UI.Window:onSourceTextChanged()
    local text = trimmed(value(self.source))
    if self.sourceSelection and self.sourceSelection.label ~= text then self.sourceSelection = nil end
    if text == "" then
        if self.activeField and self.activeField.kind == "source" then
            self.activeField = nil; self:hideCandidates()
        end
        return
    end
    self.activeField = { kind = "source" }
    self.searchDueMs = now() + 250
end
function UI.Window:onOutputTextChanged(row)
    local text = trimmed(value(row.search))
    if row.selection and row.selection.label ~= text then row.selection = nil end
    if text == "" then
        if self.activeField and self.activeField.row == row then
            self.activeField = nil; self:hideCandidates()
        end
        return
    end
    self.activeField = { kind = "output", row = row }
    self.searchDueMs = now() + 250
end
function UI.Window:hideCandidates()
    self.candidates = {}
    if GodSystemUISafety and GodSystemUISafety.clearList then
        GodSystemUISafety.clearList(self.candidateList)
    else self.candidateList:clear() end
    self.candidateList:setVisible(false)
end
function UI.Window:applyCandidate(candidate)
    local field = self.activeField
    if not field or type(candidate) ~= "table" or not candidate.fullType then return end
    local selection = { fullType = tostring(candidate.fullType), label = tostring(candidate.label) }
    if field.kind == "source" then
        self.sourceSelection = selection
        self.source:setText(selection.label)
    elseif field.row then
        field.row.selection = selection
        field.row.search:setText(selection.label)
    end
    self.activeField = nil
    self:hideCandidates()
end
function UI.Window:onCandidatePicked(row)
    local candidate = row and (row.item or row) or nil
    self:applyCandidate(candidate)
end
function UI.Window:refreshCandidates()
    local field = self.activeField
    if not field then self:hideCandidates() return end
    local box
    if field.kind == "source" then box = self.source
    elseif field.row then box = field.row.search end
    if not box then self:hideCandidates() return end
    local text = trimmed(value(box))
    if text == "" then self:hideCandidates() return end
    local catalog = GodSystemItemCatalog.getShared()
    if not catalog.complete then catalog:buildStep(64) end
    local rows = catalog:query(text, 1, MAX_CANDIDATES).rows
    -- An exactly typed full type, or a unique exact display name, resolves immediately.
    local lower = string.lower(text)
    local labelMatch, labelCount = nil, 0
    for _, candidate in ipairs(rows) do
        if string.lower(tostring(candidate.fullType)) == lower then
            self:applyCandidate(candidate)
            return
        end
        if tostring(candidate.label) == text then
            labelMatch, labelCount = candidate, labelCount + 1
        end
    end
    if labelCount == 1 and labelMatch then
        self:applyCandidate(labelMatch)
        return
    end
    self.candidates = rows
    if GodSystemUISafety and GodSystemUISafety.clearList then
        GodSystemUISafety.clearList(self.candidateList)
    else self.candidateList:clear() end
    for _, candidate in ipairs(rows) do
        self.candidateList:addItem(candidate.label, candidate)
    end
    self:relayout()
    self.candidateList:setVisible(#rows > 0)
end
-- Confirms a unique full type from the local catalog before any save is sent.
function UI.Window:resolveSelection(selection, text)
    text = trimmed(text)
    if text == "" then return nil end
    if selection and selection.fullType ~= "" and selection.label == text then return selection.fullType end
    local catalog = GodSystemItemCatalog.getShared()
    if not catalog.complete then catalog:buildStep(64) end
    local rows = catalog:query(text, 1, MAX_CANDIDATES).rows
    local lower = string.lower(text)
    for _, candidate in ipairs(rows) do
        if string.lower(tostring(candidate.fullType)) == lower then return candidate.fullType end
    end
    local labelMatch, labelCount = nil, 0
    for _, candidate in ipairs(rows) do
        if tostring(candidate.label) == text then labelMatch, labelCount = candidate, labelCount + 1 end
    end
    if labelCount == 1 and labelMatch then return labelMatch.fullType end
    return nil
end
function UI.Window:buildRelation()
    local sourceFullType = self:resolveSelection(self.sourceSelection, value(self.source))
    if not sourceFullType then return nil, "ConversionRisk_PickSource" end
    local sourceCount = tonumber(value(self.sourceCount))
    if not sourceCount or sourceCount ~= sourceCount or sourceCount ~= math.floor(sourceCount)
        or sourceCount < 1 or sourceCount > 100000 then
        return nil, "ConversionRisk_CountInvalid"
    end
    local outputs = {}
    for _, row in ipairs(self.outputRows) do
        local fullType = self:resolveSelection(row.selection, value(row.search))
        if not fullType then return nil, "ConversionRisk_PickOutput" end
        local count = tonumber(value(row.count))
        if not count or count ~= count or count ~= math.floor(count) or count < 1 or count > 100000 then
            return nil, "ConversionRisk_CountInvalid"
        end
        outputs[#outputs + 1] = { fullType = fullType, count = count }
    end
    for _, carried in ipairs(self.carriedOutputs or {}) do
        outputs[#outputs + 1] = { fullType = tostring(carried.fullType), count = tonumber(carried.count) or 1 }
    end
    if #outputs == 0 then return nil, "ConversionRisk_PickOutput" end
    local relation = {
        id = self.selected and self.selected.id or "",
        sourceFullType = sourceFullType,
        sourceCount = sourceCount,
        outputs = outputs,
        note = value(self.noteEntry),
        enabled = true,
    }
    if self.selected and self.selected.builtin then
        relation.sourceKind = self.selected.sourceKind
        relation.recipeName = self.selected.recipeName
    end
    return relation
end
function UI.Window:updateEditorButtons()
    local selected = self.selected
    local builtin = selected and selected.builtin == true
    local disabled = selected and selected.disabled == true
    self.disableButton:setTitle(disabled and label("ConversionRisk_Enable", "启用") or label("ConversionRisk_Disable", "禁用"))
    self.disableButton:setEnable(builtin)
    self.deleteButton:setEnable(selected ~= nil)
end
function UI.Window:write(relation, action)
    local id=self.selected and self.selected.id or ""
    local keepSelection = (relation ~= nil) or action == "disable" or action == "enable"
    if multiplayer() then
        self.pendingId = keepSelection and id ~= "" and id or nil
        return GodSystemNetwork and GodSystemNetwork.send and
            GodSystemNetwork.send("itemConfigRelation" .. (relation and "Set" or "Delete"),
                {id=id,relation=relation,action=action,expectedRevision=self.revision}) or false
    end
    local ok, code, newId = localSave(relation, id, action)
    if not ok then notifyReject(code); return false end
    if relation then self.pendingId = newId or (id ~= "" and id) or nil
    elseif keepSelection then self.pendingId = id ~= "" and id or nil end
    self:reload()
    return true
end
function UI.Window:saveRow()
    local relation, reason = self:buildRelation()
    if not relation then notify(reason, reason); return end
    if self:write(relation) then notify("ConversionRisk_Saved","转换关系已保存") end
end
function UI.Window:disableRow()
    local selected = self.selected
    if not (selected and selected.builtin == true) then return end
    local action = selected.disabled == true and "enable" or "disable"
    if self:write(nil, action) then
        if action == "enable" then notify("ConversionRisk_NowEnabled","转换关系已启用")
        else notify("ConversionRisk_NowDisabled","转换关系已禁用") end
    end
end
function UI.Window:deleteRow()
    local selected = self.selected
    if not selected then return end
    if self:write(nil, "delete") then
        self:clearEditorToNew()
        notify("ConversionRisk_Deleted","转换关系已删除")
    end
end
function UI.Window:close()
    self:setVisible(false)
    if self.removeFromUIManager then self:removeFromUIManager() end
    UI.window=nil
end
function UI.open()
    if UI.window then return GodSystemUI.presentOverlay(UI.window) end
    local core=getCore and getCore()
    local sw=core and core:getScreenWidth() or 1280
    local sh=core and core:getScreenHeight() or 720
    local width,height=math.min(1080,sw-24),math.min(660,sh-24)
    local window=UI.Window:new((sw-width)/2,(sh-height)/2,width,height)
    window:initialise()
    GodSystemUI.presentOverlay(window)
    UI.window=window
    return window
end
return UI
