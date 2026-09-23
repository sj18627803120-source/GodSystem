local loaded = {}
function require(name)
    if loaded[name] then return loaded[name] end
    loaded[name] = true
    local fn = assert(loadstring(readSource("shared/" .. name .. ".lua"), name))
    loaded[name] = fn() or true
    return loaded[name]
end

GodSystemShopVariants = {
    getKey = function(fullType, sprite) return tostring(fullType) .. "|" .. tostring(sprite or "") end,
}
require "GodSystem_ShopInflation"
local S = GodSystemShopInflation
local cfg = { EnableShopDynamicInflation = true, ShopDynamicInflationPercent = 10, ShopDynamicInflationHours = 24 }
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function test(name, fn) fn(); print("PASS inflation: " .. name) end

test("single and batch prices use independent linear layers", function()
    local data, key = {}, "Base.Axe|"
    local quote = assert(S.quote(data, cfg, 0, key, 100, 3, true))
    eq(quote.total, 330)
    assert(S.commit(data, cfg, 0, key, 3, true))
    quote = assert(S.quote(data, cfg, 0, key, 100, 1, true))
    eq(quote.total, 130)
end)

test("layers expire by personal online minutes and do not affect other items", function()
    local data = {}
    assert(S.commit(data, cfg, 0, "Base.Axe|", 2, true))
    eq(assert(S.quote(data, cfg, 30, "Base.Axe|", 100, 1, true)).total, 120)
    eq(assert(S.quote(data, cfg, 30, "Base.Hammer|", 100, 1, true)).total, 100)
    eq(assert(S.quote(data, cfg, 1440, "Base.Axe|", 100, 1, true)).total, 120)
    eq(assert(S.quote(data, cfg, 1441, "Base.Axe|", 100, 1, true)).total, 100)
end)

test("quotes are consumed once and a disabled configuration clears layers", function()
    local data, key = {}, "Base.Axe|"
    local quote, id = assert(S.issueQuote(data, cfg, 0, key, 100, 1, true))
    eq(quote.total, 100)
    assert(S.consumeQuote(data, cfg, 0, id, key, 100, 1, true))
    assert(not S.consumeQuote(data, cfg, 0, id, key, 100, 1, true))
    assert(S.commit(data, cfg, 0, key, 1, true))
    local off = { EnableShopDynamicInflation = false }
    eq(assert(S.quote(data, off, 1, key, 100, 1, true)).total, 100)
    eq(assert(S.quote(data, cfg, 1, key, 100, 1, true)).layers, 0)
end)
