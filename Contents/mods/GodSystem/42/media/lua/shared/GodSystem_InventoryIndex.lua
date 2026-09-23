-- Operation-local authority index. Never persist or reuse across inventory mutations.
GodSystemInventoryIndex = GodSystemInventoryIndex or {}
local Index = GodSystemInventoryIndex

function Index.build(root)
    if GodSystemShopCatalog and GodSystemShopCatalog.note then GodSystemShopCatalog.note("inventory.indexBuilds") end
    local result = { byId = {}, ambiguous = {}, valid = root ~= nil, itemsVisited = 0, containersVisited = 0 }
    local pending, visited = { root }, {}
    while #pending > 0 do
        local container = table.remove(pending)
        if container and not visited[container] then
            visited[container] = true
            result.containersVisited = result.containersVisited + 1
            local ok, items = pcall(function() return container:getItems() end)
            if not ok or not items then result.valid = false; return result end
            local sizeOk, count = pcall(function() return items:size() end)
            if not sizeOk then result.valid = false; return result end
            for i = 0, count - 1 do
                local readOk, item = pcall(function() return items:get(i) end)
                if not readOk then result.valid = false; return result end
                if item then
                    result.itemsVisited = result.itemsVisited + 1
                    local idOk, id = pcall(function() return item:getID() end)
                    if not idOk or id == nil then result.valid = false; return result end
                    id = tostring(id)
                    local old = result.byId[id]
                    if old and (old.item ~= item or old.container ~= container) then
                        result.ambiguous[id] = true
                    else
                        result.byId[id] = { item = item, container = container }
                    end
                    if item.getInventory then
                        local childOk, child = pcall(function() return item:getInventory() end)
                        if not childOk then result.valid = false; return result end
                        if child and not visited[child] then pending[#pending + 1] = child end
                    end
                end
            end
        end
    end
    return result
end

function Index.find(index, id)
    id = tostring(id or "")
    if not index or not index.valid or index.ambiguous[id] then return nil, nil end
    local row = index.byId[id]
    return row and row.item or nil, row and row.container or nil
end

return Index
