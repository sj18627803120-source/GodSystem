-- Incremental equivalent of the existing sorted ID/type content signature.
-- Each step visits one child, merges one token, hashes one token or verifies one record.
GodSystemContextContent = GodSystemContextContent or {}
local Reader = {}
Reader.__index = Reader

local function inventory(item)
    return item and item.getInventory and item:getInventory() or nil
end

function Reader:push(container, depth)
    if not container or depth > 32 then return end
    assert(not self.seen[container], "cyclic container contents")
    self.seen[container] = true
    local items = container:getItems()
    local frame = { container = container, items = items, count = items:size(), cursor = 0, depth = depth }
    self.frames[#self.frames + 1] = frame
    self.pending[#self.pending + 1] = frame
end

function GodSystemContextContent.new(item)
    local self = setmetatable({ item = item, root = inventory(item), frames = {}, pending = {}, seen = {},
        records = {}, tokens = {}, phase = "scan", cursor = 1, width = 1, left = 1, output = {}, hash = 7 }, Reader)
    self:push(self.root, 1)
    return self
end

function Reader:step()
    if self.phase == "done" then return true end
    self.steps = (self.steps or 0) + 1
    if self.phase == "scan" then
        local frame = self.pending[#self.pending]
        if not frame then self.phase = "sort"; return false end
        if frame.cursor >= frame.count then table.remove(self.pending); return false end
        local slot = frame.cursor
        local child = frame.items:get(slot)
        frame.cursor = slot + 1
        assert(child, "container contents changed")
        local rawId, rawType = child:getID(), child:getFullType()
        assert(rawId ~= nil and rawType ~= nil, "invalid content identity")
        local id, fullType = tostring(rawId), tostring(rawType)
        local childInventory = inventory(child)
        self.tokens[#self.tokens + 1] = id .. ":" .. fullType
        self.records[#self.records + 1] = { frame = frame, slot = slot, item = child, id = id, fullType = fullType,
            inventory = childInventory, worldSprite = GodSystemShopVariants.getWorldSprite(child) }
        self:push(childInventory, frame.depth + 1)
    elseif self.phase == "sort" then
        local count = #self.tokens
        if self.width >= count then self.phase = "hash"; self.cursor = 1; return false end
        if self.left > count then
            self.tokens, self.output = self.output, {}
            self.width, self.left = self.width * 2, 1
            return false
        end
        if not self.merge then
            self.merge = { i = self.left, j = self.left + self.width,
                iend = math.min(count, self.left + self.width - 1),
                jend = math.min(count, self.left + self.width * 2 - 1) }
        end
        local m = self.merge
        if m.i <= m.iend and (m.j > m.jend or self.tokens[m.i] <= self.tokens[m.j]) then
            self.output[#self.output + 1] = self.tokens[m.i]; m.i = m.i + 1
        elseif m.j <= m.jend then
            self.output[#self.output + 1] = self.tokens[m.j]; m.j = m.j + 1
        end
        if m.i > m.iend and m.j > m.jend then self.left = self.left + self.width * 2; self.merge = nil end
    elseif self.phase == "hash" then
        local token = self.tokens[self.cursor]
        if not token then self.phase = "containers"; self.cursor = 1; return false end
        for i = 1, #token do self.hash = ((self.hash * 131) + string.byte(token, i)) % 2147483647 end
        self.hash = ((self.hash * 131) + 10) % 2147483647
        self.cursor = self.cursor + 1
    elseif self.phase == "containers" then
        assert(inventory(self.item) == self.root, "container replaced")
        local frame = self.frames[self.cursor]
        if not frame then self.phase = "records"; self.cursor = 1; return false end
        frame.current = frame.container:getItems()
        assert(frame.current:size() == frame.count, "container size changed")
        self.cursor = self.cursor + 1
    elseif self.phase == "records" then
        local row = self.records[self.cursor]
        if not row then
            self.signature = tostring(#self.tokens) .. ":" .. tostring(self.hash)
            self.phase = "done"
            return true
        end
        assert(row.frame.current:get(row.slot) == row.item and row.item:getContainer() == row.frame.container
            and tostring(row.item:getID()) == row.id and tostring(row.item:getFullType()) == row.fullType
            and inventory(row.item) == row.inventory
            and GodSystemShopVariants.getWorldSprite(row.item) == row.worldSprite, "contents changed")
        self.cursor = self.cursor + 1
    end
    return false
end

function Reader:restartValidation()
    self.phase = "containers"
    self.cursor = 1
end

return GodSystemContextContent
