-- Run unchanged on Lua 5.1 AND the game's Kahlua VM. Escaped UTF-8 literals
-- match the packaged translation/guide generators, not string.char(byte...).
function require() end
ISScrollingListBox={prerender=function() end}
GodSystemTerminalPreferences={font=function() return "body" end}
assert(loadstring(readSource("client/GodSystem_UISafety.lua")))()
assert(loadstring(readSource("client/GodSystem_TerminalDesign.lua")))()
local S,D=GodSystemUISafety,GodSystemTerminalDesign
local cn="\228\184\173\230\150\135"
local cat="\240\159\144\177"
local accent="\195\169"
local utf16=#cn==2
-- Independent fixed-width font: each Unicode scalar counts as one cell.
local function width(s)
    local count=0
    for ch in s:gmatch(".") do
        local v=ch:byte()
        if utf16 then
            if v<56320 or v>57343 then count=count+1 end
        elseif v<128 or v>=192 then count=count+1 end
    end
    return count*10
end
function getTextManager() return {MeasureStringX=function(_,_,s) return width(s) end} end
local passed=0
local function test(name,fn) fn(); passed=passed+1; print("PASS text runtime: "..name) end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
test("wrapping retains every Chinese character, number, symbol and paragraph",function()
    for _,s in ipairs({cn.." 10/10 | Lv4 40.00% "..cn,cn..cat..accent.." +1 -> 8 -70",string.rep(cn,120)}) do
        for _,w in ipairs({10,30,60,130,3000}) do
            local lines=D.wrap(s,w)
            eq(table.concat(lines,""),s)
            for _,line in ipairs(lines) do assert(width(line)<=w,"line exceeds width") end
        end
    end
    local lines=D.wrap(cn.."\n\n"..cn.."\n",500)
    eq(#lines,4); eq(lines[1],cn); eq(lines[2],""); eq(lines[3],cn); eq(lines[4],"")
end)
test("ellipsis keeps the longest whole-character prefix in either VM",function()
    eq(S.fitText(cn..cn..cn..cn,"body",60),cn..cn:sub(1,utf16 and 1 or 3).."...")
    eq(S.fitText(cat..cat..cat..cat..cat,"body",40),cat.."...")
    eq(S.fitText(cn..accent,"body",30),cn..accent)
    eq(S.fitText(cn..cn,"body",20),"")
end)
test("wrapping keeps non-BMP characters together at line boundaries",function()
    local lines=D.wrap(cat..cn..cat,10)
    eq(#lines,4); eq(lines[1],cat); eq(lines[4],cat)
    eq(D.wrap("",10)[1],"")
end)
test("Chinese equipment rename uses the same character limits in both VMs",function()
    assert(loadstring(readSource("shared/GodSystem_Equipment.lua")))()
    local E=GodSystemEquipment
    local fullSpace="\227\128\128"
    eq(E.validateName(fullSpace..cn.." "..accent.." "),cn.." "..accent)
    eq(E.nameCharacterCount(cn..accent),3)
    eq(E.validateName(string.rep(cn,15)),string.rep(cn,15))
    local value,err=E.validateName(string.rep(cn,16)); eq(value,nil); eq(err,"EquipmentNameTooLong")
    eq(E.validateName(cat),nil); eq(E.validateName("a\n"..cn),nil)
end)
print("Text runtime groups passed: "..passed.." ("..(utf16 and "UTF-16 / Kahlua" or "UTF-8 / Lua")..")")
