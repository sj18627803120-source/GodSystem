-- Static, reviewed vanilla conversion relationships.  These rules are data, not
-- a runtime recipe scanner: servers never enumerate craft recipes to price an item.
GodSystemConversionRelations = GodSystemConversionRelations or {}

local Relations = GodSystemConversionRelations
local MAX_SAFE = 9007199254740000

Relations.BUILTIN = Relations.BUILTIN or {
    { id = "b42:garbagebag_box", sourceFullType = "Base.Garbagebag_box", sourceCount = 1,
        outputs = { { fullType = "Base.Garbagebag", count = 20 } }, sourceKind = "drainable",
        recipeName = "TakeAGarbageBag", note = "B42.20.4 UseDelta 0.05", enabled = true },
    { id = "b42:egg_carton", sourceFullType = "Base.EggCarton", sourceCount = 1,
        outputs = { { fullType = "Base.Egg", count = 12 } }, sourceKind = "recipe",
        recipeName = "OpenEggCarton", note = "B42.20.4", enabled = true },
    { id = "b42:candy_package", sourceFullType = "Base.CandyPackage", sourceCount = 1,
        outputs = { { fullType = "Base.Lollipop", count = 5 }, { fullType = "Base.MintCandy", count = 5 } },
        sourceKind = "recipe", recipeName = "OpenCandyPackage", note = "B42.20.4", enabled = true },
    { id = "b42:hotdog_pack", sourceFullType = "Base.HotdogPack", sourceCount = 1,
        outputs = { { fullType = "Base.Hotdog_single", count = 4 } }, sourceKind = "recipe",
        recipeName = "OpenHotdogPack", note = "B42.20.4", enabled = true },
    { id = "b42:shotgun_shells_box", sourceFullType = "Base.ShotgunShellsBox", sourceCount = 1,
        outputs = { { fullType = "Base.ShotgunShells", count = 25 } }, sourceKind = "recipe",
        recipeName = "OpenBoxOfShotgunShells", note = "B42.20.4", enabled = true },
    { id = "b42:bullets9mm_box", sourceFullType = "Base.Bullets9mmBox", sourceCount = 1,
        outputs = { { fullType = "Base.Bullets9mm", count = 50 } }, sourceKind = "mapper",
        recipeName = "OpenBoxOfBullets50", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:bullets45_box", sourceFullType = "Base.Bullets45Box", sourceCount = 1,
        outputs = { { fullType = "Base.Bullets45", count = 50 } }, sourceKind = "mapper",
        recipeName = "OpenBoxOfBullets50", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:bullets38_box", sourceFullType = "Base.Bullets38Box", sourceCount = 1,
        outputs = { { fullType = "Base.Bullets38", count = 50 } }, sourceKind = "mapper",
        recipeName = "OpenBoxOfBullets50", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:bullets357_box", sourceFullType = "Base.Bullets357Box", sourceCount = 1,
        outputs = { { fullType = "Base.Bullets357", count = 50 } }, sourceKind = "mapper",
        recipeName = "OpenBoxOfBullets50", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:bullets44_box", sourceFullType = "Base.Bullets44Box", sourceCount = 1,
        outputs = { { fullType = "Base.Bullets44", count = 20 } }, sourceKind = "mapper",
        recipeName = "OpenBoxOfBullets20", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:308_box", sourceFullType = "Base.308Box", sourceCount = 1,
        outputs = { { fullType = "Base.308Bullets", count = 20 } }, sourceKind = "mapper",
        recipeName = "OpenBoxOfBullets20", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:556_box", sourceFullType = "Base.556Box", sourceCount = 1,
        outputs = { { fullType = "Base.556Bullets", count = 20 } }, sourceKind = "mapper",
        recipeName = "OpenBoxOfBullets20", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:3030_box", sourceFullType = "Base.3030Box", sourceCount = 1,
        outputs = { { fullType = "Base.3030Bullets", count = 20 } }, sourceKind = "mapper",
        recipeName = "OpenBoxOfBullets20", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:paperclip_box", sourceFullType = "Base.PaperclipBox", sourceCount = 1,
        outputs = { { fullType = "Base.Paperclip", count = 40 } }, sourceKind = "recipe",
        recipeName = "OpenBoxOfPaperclip", note = "B42.20.4", enabled = true },
    { id = "b42:fishing_hook_box", sourceFullType = "Base.FishingHookBox", sourceCount = 1,
        outputs = { { fullType = "Base.FishingHook", count = 10 } }, sourceKind = "recipe",
        recipeName = "OpenBoxOfFishingHooks", note = "B42.20.4", enabled = true },
    { id = "b42:adhesive_bandage_box", sourceFullType = "Base.AdhesiveBandageBox", sourceCount = 1,
        outputs = { { fullType = "Base.Bandaid", count = 24 } }, sourceKind = "recipe",
        recipeName = "UnpackBoxOfAdhesiveBandages", note = "B42.20.4", enabled = true },
    { id = "b42:tongue_depressor_box", sourceFullType = "Base.TongueDepressorBox", sourceCount = 1,
        outputs = { { fullType = "Base.TongueDepressor", count = 20 } }, sourceKind = "recipe",
        recipeName = "UnpackTongueDepressors", note = "B42.20.4", enabled = true },
    { id = "b42:cigarette_pack", sourceFullType = "Base.CigarettePack", sourceCount = 1,
        outputs = { { fullType = "Base.CigaretteSingle", count = 20 } }, sourceKind = "recipe",
        recipeName = "UnpackCigarettes", note = "B42.20.4", enabled = true },
    { id = "b42:cigarette_carton", sourceFullType = "Base.CigaretteCarton", sourceCount = 1,
        outputs = { { fullType = "Base.CigarettePack", count = 10 } }, sourceKind = "recipe",
        recipeName = "UnpackCigaretteCarton", note = "B42.20.4", enabled = true },
    { id = "b42:nails_box", sourceFullType = "Base.NailsBox", sourceCount = 1,
        outputs = { { fullType = "Base.Nails", count = 100 } }, sourceKind = "mapper",
        recipeName = "OpenBox100", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:screws_box", sourceFullType = "Base.ScrewsBox", sourceCount = 1,
        outputs = { { fullType = "Base.Screws", count = 100 } }, sourceKind = "mapper",
        recipeName = "OpenBox100", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:nails_carton", sourceFullType = "Base.NailsCarton", sourceCount = 1,
        outputs = { { fullType = "Base.NailsBox", count = 12 } }, sourceKind = "mapper",
        recipeName = "OpenCarton12", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:screws_carton", sourceFullType = "Base.ScrewsCarton", sourceCount = 1,
        outputs = { { fullType = "Base.ScrewsBox", count = 12 } }, sourceKind = "mapper",
        recipeName = "OpenCarton12", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:bullets9mm_carton", sourceFullType = "Base.Bullets9mmCarton", sourceCount = 1,
        outputs = { { fullType = "Base.Bullets9mmBox", count = 12 } }, sourceKind = "mapper", recipeName = "OpenCarton12", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:bullets45_carton", sourceFullType = "Base.Bullets45Carton", sourceCount = 1,
        outputs = { { fullType = "Base.Bullets45Box", count = 12 } }, sourceKind = "mapper", recipeName = "OpenCarton12", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:bullets38_carton", sourceFullType = "Base.Bullets38Carton", sourceCount = 1,
        outputs = { { fullType = "Base.Bullets38Box", count = 12 } }, sourceKind = "mapper", recipeName = "OpenCarton12", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:bullets357_carton", sourceFullType = "Base.Bullets357Carton", sourceCount = 1,
        outputs = { { fullType = "Base.Bullets357Box", count = 12 } }, sourceKind = "mapper", recipeName = "OpenCarton12", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:bullets44_carton", sourceFullType = "Base.Bullets44Carton", sourceCount = 1,
        outputs = { { fullType = "Base.Bullets44Box", count = 12 } }, sourceKind = "mapper", recipeName = "OpenCarton12", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:308_carton", sourceFullType = "Base.308Carton", sourceCount = 1,
        outputs = { { fullType = "Base.308Box", count = 12 } }, sourceKind = "mapper", recipeName = "OpenCarton12", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:shotgun_shells_carton", sourceFullType = "Base.ShotgunShellsCarton", sourceCount = 1,
        outputs = { { fullType = "Base.ShotgunShellsBox", count = 12 } }, sourceKind = "mapper", recipeName = "OpenCarton12", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:556_carton", sourceFullType = "Base.556Carton", sourceCount = 1,
        outputs = { { fullType = "Base.556Box", count = 12 } }, sourceKind = "mapper", recipeName = "OpenCarton12", note = "B42.20.4 itemMapper", enabled = true },
    { id = "b42:3030_carton", sourceFullType = "Base.3030Carton", sourceCount = 1,
        outputs = { { fullType = "Base.3030Box", count = 12 } }, sourceKind = "mapper", recipeName = "OpenCarton12", note = "B42.20.4 itemMapper", enabled = true },
}

local function trim(value, limit)
    local text = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    if limit and #text > limit then text = text:sub(1, limit) end
    return text
end

local function integer(value, minimum, maximum)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    number = math.floor(number)
    if number < minimum or number > maximum then return nil end
    return number
end

local function copyRelation(value)
    if type(value) ~= "table" then return nil end
    local result = {
        id = trim(value.id, 160), sourceFullType = trim(value.sourceFullType, 120),
        sourceCount = integer(value.sourceCount or 1, 1, 100000), sourceKind = trim(value.sourceKind, 32),
        recipeName = trim(value.recipeName, 120), note = trim(value.note, 120), enabled = value.enabled ~= false,
        outputs = {},
    }
    if result.id == "" or result.sourceFullType == "" or not result.sourceCount then return nil end
    for i = 1, math.min(16, #(value.outputs or {})) do
        local output = value.outputs[i]
        local fullType = trim(output and output.fullType, 120)
        local count = integer(output and output.count, 1, 100000)
        if fullType ~= "" and count then result.outputs[#result.outputs + 1] = { fullType = fullType, count = count } end
    end
    if #result.outputs == 0 then return nil end
    return result
end

function Relations.sanitize(value, fallbackId)
    if type(value) ~= "table" then return nil end
    if (value.id == nil or tostring(value.id) == "") and fallbackId then
        local copy = {}
        for key, item in pairs(value) do copy[key] = item end
        copy.id = fallbackId
        value = copy
    end
    return copyRelation(value)
end

function Relations.builtinById()
    local result = {}
    for i = 1, #Relations.BUILTIN do
        local relation = copyRelation(Relations.BUILTIN[i])
        if relation then result[relation.id] = relation end
    end
    return result
end

function Relations.effective(config)
    config = type(config) == "table" and config or {}
    local builtin = Relations.builtinById()
    local result = {}
    local disabled = type(config.conversionBuiltinDisabled) == "table" and config.conversionBuiltinDisabled or {}
    local removed = type(config.conversionBuiltinRemoved) == "table" and config.conversionBuiltinRemoved or {}
    local overrides = type(config.conversionBuiltinOverrides) == "table" and config.conversionBuiltinOverrides or {}
    for id, relation in pairs(builtin) do
        if disabled[id] ~= true and removed[id] ~= true then
            local override = overrides[id]
            local merged = override and copyRelation(override) or relation
            if merged then merged.id = id; result[#result + 1] = merged end
        end
    end
    for id, relation in pairs(type(config.conversionRelations) == "table" and config.conversionRelations or {}) do
        local clean = Relations.sanitize(relation, id)
        if clean then result[#result + 1] = clean end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

-- Pricing deliberately ignores disabled built-ins.  The administrator UI
-- needs a separate complete view so a disabled built-in can be inspected and
-- restored instead of disappearing from the list.
function Relations.all(config)
    config = type(config) == "table" and config or {}
    local builtin = Relations.builtinById()
    local result = {}
    local disabled = type(config.conversionBuiltinDisabled) == "table" and config.conversionBuiltinDisabled or {}
    local removed = type(config.conversionBuiltinRemoved) == "table" and config.conversionBuiltinRemoved or {}
    local overrides = type(config.conversionBuiltinOverrides) == "table" and config.conversionBuiltinOverrides or {}

    for id, relation in pairs(builtin) do
        local merged = removed[id] ~= true and (overrides[id] and copyRelation(overrides[id]) or relation) or nil
        if merged then
            merged.id = id
            merged.builtin = true
            merged.disabled = disabled[id] == true
            merged.enabled = not merged.disabled
            result[#result + 1] = merged
        end
    end
    for id, relation in pairs(type(config.conversionRelations) == "table" and config.conversionRelations or {}) do
        local clean = Relations.sanitize(relation, id)
        if clean then
            clean.builtin = false
            clean.disabled = false
            result[#result + 1] = clean
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

-- Returns true when a source can eventually produce itself.  This is kept in
-- the shared data module so the server validates administrator edits with the
-- same graph rules used when compiling a quote.
function Relations.hasCycle(config)
    local edges, visiting, visited = {}, {}, {}
    for _, relation in ipairs(Relations.effective(config)) do
        if relation.enabled ~= false then
            edges[relation.sourceFullType] = edges[relation.sourceFullType] or {}
            for _, output in ipairs(relation.outputs) do
                edges[relation.sourceFullType][#edges[relation.sourceFullType] + 1] = output.fullType
            end
        end
    end
    local function walk(fullType)
        if visiting[fullType] then return true end
        if visited[fullType] then return false end
        visiting[fullType] = true
        for _, output in ipairs(edges[fullType] or {}) do
            if walk(output) then return true end
        end
        visiting[fullType], visited[fullType] = nil, true
        return false
    end
    for source in pairs(edges) do if walk(source) then return true end end
    return false
end

local function safeAdd(left, right)
    if left < 0 or right < 0 or left > MAX_SAFE - right then return nil end
    return left + right
end

function Relations.compile(config, directRecycle, margin)
    local relations = Relations.effective(config)
    local bySource, invalid = {}, {}
    for i = 1, #relations do
        local relation = relations[i]
        bySource[relation.sourceFullType] = bySource[relation.sourceFullType] or {}
        bySource[relation.sourceFullType][#bySource[relation.sourceFullType] + 1] = relation
    end
    local memo, visiting = {}, {}
    local function recover(fullType)
        if memo[fullType] ~= nil then return memo[fullType] end
        local direct = math.max(0, math.floor(tonumber(directRecycle(fullType)) or 0))
        if visiting[fullType] then invalid[fullType] = "cycle"; return direct end
        visiting[fullType] = true
        local best = direct
        for _, relation in ipairs(bySource[fullType] or {}) do
            if relation.enabled ~= false then
                local total, valid = 0, true
                for _, output in ipairs(relation.outputs) do
                    local value = recover(output.fullType)
                    if value > 0 and output.count > math.floor(MAX_SAFE / value) then valid = false; break end
                    total = safeAdd(total, value * output.count)
                    if not total then valid = false; break end
                end
                if valid then
                    local unit = math.ceil(total / relation.sourceCount)
                    if unit > best then best = unit end
                else
                    invalid[relation.id] = "overflow"
                end
            end
        end
        visiting[fullType] = nil
        memo[fullType] = best
        return best
    end
    local floors = {}
    local multiplier = 1 + math.max(0, tonumber(margin) or 0)
    for source in pairs(bySource) do
        local direct = math.max(0, math.floor(tonumber(directRecycle(source)) or 0))
        local converted = recover(source)
        if converted > direct and converted <= math.floor(MAX_SAFE / multiplier) then
            -- Decimal sandbox margins such as 10% can become
            -- 110.00000000000001 in Lua doubles.  Keep mathematical integers
            -- stable while still rounding genuine fractional values upward.
            floors[source] = math.ceil((converted * multiplier) - 0.000000001)
        end
    end
    return floors, invalid, relations
end

return Relations
