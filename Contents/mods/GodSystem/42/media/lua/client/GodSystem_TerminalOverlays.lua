require "GodSystem_TerminalDesign"
GodSystemTerminalOverlays=GodSystemTerminalOverlays or {}
local O,D=GodSystemTerminalOverlays,GodSystemTerminalDesign
O.windows=O.windows or setmetatable({},{__mode="k"})
function O.style(window)
    if not window then return end
    window.backgroundColor=D.copy(D.colors.shell); window.borderColor=D.copy(D.colors.line)
    local function children(parent)
        for _,c in pairs(parent.children or {}) do
            if c.Type=="ISButton" then
                D.style(c)
                if c.height<D.height("body")+10 then c.font=D.font("caption") end
                local full=c.fullTitle or c.title or ""
                c.tooltip=c.tooltip or full; c:setTitle(GodSystemUISafety.fitText(full,c.font,c.width-14))
            elseif c.Type=="ISTextEntryBox" then
                D.style(c); c.font=D.font("caption")
                if c.setFont then c:setFont(c.font) end
            elseif c.Type=="ISScrollingListBox" then
                c.backgroundColor=D.copy(D.colors.panel); c.borderColor=D.copy(D.colors.line)
            end
            children(c)
        end
    end
    children(window)
    if window.terminalLayout then window:terminalLayout() end
    O.windows[window]=true
end
function O.refresh()
    for window in pairs(O.windows) do if window:getIsVisible() then O.style(window) end end
end
function O.install()
    if O.installed then return end; O.installed=true
    -- This namespaced presenter is used only for GodSystem-owned overlays.
    local present=GodSystemUISafety.presentOverlay
    function GodSystemUISafety.presentOverlay(window)
        local result=present(window); O.style(window); return result
    end
end
return O
