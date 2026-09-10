-- Record drawing without a functioning stencil: out-of-bounds work must not
-- be submitted even when nested UI clipping is ineffective. Not a GPU test.
local passed=0
local function test(name,fn) fn(); passed=passed+1; print("PASS UI safety: "..name) end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
function require() end
UIFont={Small="Small"}
local measures=0
local function textWidth(value)
    local _,count=value:gsub("[^\128-\191]", "")
    return count*8
end
getTextManager=function() return {
    getFontHeight=function() return 16 end,
    MeasureStringX=function(_,_,value) measures=measures+1; return textWidth(value) end,
} end
local nativeCalls=0
ISScrollingListBox={prerender=function(box)
    nativeCalls=nativeCalls+1
    eq(box.vscroll.x,box.width-16); eq(box.vscroll.height,box.height)
    local y=0
    for index,row in ipairs(box.items) do row.index=index; y=box:doDrawItem(y,row,index%2==0) end
    box:setScrollHeight(y)
end}
assert(loadstring(readSource("client/GodSystem_UISafety.lua")))()
local S=GodSystemUISafety
local function list(count,height)
    local box={width=240,height=height or 251,itemheight=36,selected=1,items={},scroll=0,rects=0,texts=0}
    box.vscroll={setX=function(self,x) self.x=x end,setY=function(self,y) self.y=y end,
        setHeight=function(self,h) self.height=h end,updatePos=function() end}
    function box:getYScroll() return self.scroll end
    function box:setYScroll(v) self.scroll=v end
    function box:setScrollHeight(v) self.scrollHeight=v end
    function box:isVScrollBarVisible() return #self.items*self.itemheight>self.height end
    function box:clear() self.items={}; self.selected=1 end
    function box:drawRect(x,y,w,h)
        y=y+self.scroll
        assert(x>=0 and y>=0 and x+w<=self.width and y+h<=self.height,"row background escaped its list")
        self.rects=self.rects+1
    end
    function box:drawText(value,x,y)
        y=y+self.scroll
        assert(x>=0 and y>=0 and x+textWidth(value)<=self.width and y+16<=self.height,"text escaped its list")
        self.texts=self.texts+1
    end
    for n=1,count do box.items[n]={height=36,text=string.rep("long name ",40)..n,itemindex=n} end
    box.doDrawItem=S.drawTextRow; S.installList(box)
    return box
end

test("1/3/200/10000 rows stay contained at top, middle, bottom and fractional scroll",function()
    for _,count in ipairs({1,3,200,10000}) do
        for _,height in ipairs({170,200,224,251}) do
            local box=list(count,height)
            local maximum=math.max(0,count*36-height)
            for _,scroll in ipairs({0,-0.5,-35.5,-maximum/2,-maximum, -maximum-40}) do
                box.scroll=scroll; box.rects=0; box.texts=0; box:prerender()
                eq(box.scrollHeight,count*36)
                assert(box.texts<=math.ceil(height/36)+1,"off-screen rows were drawn")
            end
        end
    end
end)

test("partially visible row backgrounds are clipped and full outside rows are skipped",function()
    local box=list(100); box.scroll=-35.5; box.selected=1
    eq(box:doDrawItem(0,box.items[1],false),36); eq(box.rects,0); eq(box.texts,0)
    box.scroll=-30
    box:doDrawItem(0,box.items[1],false); eq(box.rects,1); eq(box.texts,0)
    box:doDrawItem(1000,box.items[1],true); eq(box.rects,1); eq(box.texts,0)
end)

test("visible-row text cache invalidates only on text, font or available width changes",function()
    local box=list(200); measures=0
    box:prerender(); local initial=measures; assert(initial>0)
    eq(box.items[1].tooltip,box.items[1].text)
    box:prerender(); eq(measures,initial)
    box.width=160; box:prerender(); assert(measures>initial)
    local afterResize=measures
    box.items[1].text="new"; box:prerender(); assert(measures>afterResize)
    eq(box.items[1].tooltip,nil)
end)

test("UTF-8 ellipsis never splits a character or exceeds its available width",function()
    local chinese=string.char(230,173,166,229,153,168)
    local fitted=S.fitText(string.rep(chinese,30),UIFont.Small,80)
    eq(fitted,string.rep(chinese,3)..string.sub(chinese,1,3).."...")
    eq(S.fitText("anything",UIFont.Small,1),"")
    eq(S.fitText("short",UIFont.Small,80),"short")
end)

test("list rebuild clears old smooth scrolling and scrollbar geometry follows resize",function()
    local box=list(100); box.scroll=-2800; box.smoothScrollY=-2800; box.smoothScrollTargetY=-2900
    S.clearList(box); eq(box.scroll,0); eq(box.scrollHeight,0); eq(box.smoothScrollY,nil); eq(box.smoothScrollTargetY,nil)
    box.width=180; box.height=170; box:prerender()
    eq(box.vscroll.x,164); eq(box.vscroll.height,170)
end)

test("main stays below overlays after focus and reopen without globally sending it to the back",function()
    local serial=0
    local function window()
        return {addToUIManager=function(self) self.added=true end,setVisible=function(self,v) self.visible=v end,
            setAlwaysOnTop=function(self,v) self.top=v end,
            bringToTop=function(self) serial=serial+1; self.order=serial end,
            backMost=function() error("must not change unrelated game UI order") end}
    end
    local main,child,modal=window(),window(),window()
    local function above(a,b) return a.top~=b.top and a.top or a.top==b.top and a.order>b.order end
    S.presentMain(main); S.presentOverlay(child); S.presentOverlay(modal)
    assert(above(child,main)); assert(above(modal,child))
    main:bringToTop(); assert(above(child,main)); assert(above(modal,main))
    S.presentMain(main); assert(above(child,main)); assert(above(modal,main))
    S.presentOverlay(child); assert(above(child,main))
end)

print("UI safety behavior groups passed: "..passed)
