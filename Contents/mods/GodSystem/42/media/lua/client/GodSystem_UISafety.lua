require "ISUI/ISScrollingListBox"

GodSystemUISafety = GodSystemUISafety or {}
local S = GodSystemUISafety
local nativePrerender = ISScrollingListBox.prerender

-- Use the native normal/always-on-top bands, not backMost(): the main window
-- stays below our overlays without being forced behind unrelated game UI.
function S.presentMain(window)
    window:addToUIManager()
    window:setVisible(true)
    window:setAlwaysOnTop(false)
    window:bringToTop()
    return window
end

function S.presentOverlay(window)
    if not window then return nil end
    window:addToUIManager()
    window:setVisible(true)
    window:setAlwaysOnTop(true)
    window:bringToTop()
    return window
end

function S.syncListGeometry(list)
    if not list or not list.vscroll then return end
    local bar = list.vscroll
    local width = math.floor(tonumber(list.width) or 0)
    local height = math.floor(tonumber(list.height) or 0)
    bar:setX(math.max(0, width - 16))
    bar:setY(0)
    bar:setHeight(height)
    bar:updatePos()
end

function S.prerenderList(list)
    S.syncListGeometry(list)
    nativePrerender(list)
    S.syncListGeometry(list)
end

function S.installList(list)
    list.prerender = S.prerenderList
    S.syncListGeometry(list)
end

function S.clearList(list)
    list:clear()
    list.mouseoverselected = -1
    list.smoothScrollY, list.smoothScrollTargetY = nil, nil
    list:setYScroll(0)
    list:setScrollHeight(0)
    S.syncListGeometry(list)
end

-- Clip at UTF-8 character boundaries. Cache the result on the visible row;
-- drawing must never search inventory, request state, or rebuild a quote.
function S.fitText(text, font, width)
    text = tostring(text or "")
    local manager = getTextManager()
    if width <= 0 then return "" end
    if manager:MeasureStringX(font, text) <= width then return text end
    local suffix = "..."
    if manager:MeasureStringX(font, suffix) > width then return "" end
    local ends, pos = {}, 1
    while pos <= #text do
        local byte = string.byte(text, pos)
        local size = byte >= 240 and 4 or byte >= 224 and 3 or byte >= 192 and 2 or 1
        pos = math.min(#text + 1, pos + size)
        ends[#ends + 1] = pos - 1
    end
    local low, high, best = 0, #ends, suffix
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local candidate = string.sub(text, 1, ends[mid] or 0) .. suffix
        if manager:MeasureStringX(font, candidate) <= width then
            best, low = candidate, mid + 1
        else high = mid - 1 end
    end
    return best
end

function S.drawTextRow(list, y, row, alternate)
    local height = row.height or list.itemheight
    local nextY = y + height
    local scroll = list:getYScroll()
    local top = math.max(1, y + scroll)
    local bottom = math.min(list.height - 1, nextY + scroll)
    if height <= 0 or bottom <= top then return nextY end
    local right = list.width - 1
    if list:isVScrollBarVisible() then right = math.min(right, list.vscroll.x + 3) end
    if right <= 1 then return nextY end
    -- Geometric containment also protects against nested stencil leakage.
    if list.selected == (row.index or row.itemindex) then
        list:drawRect(1, top - scroll, right - 1, bottom - top, 0.8, 0.20, 0.27, 0.33)
    elseif alternate then
        list:drawRect(1, top - scroll, right - 1, bottom - top, 0.5, 0.13, 0.17, 0.21)
    end
    local font = list.font or UIFont.Small
    local fontHeight = getTextManager():getFontHeight(font)
    local textY = y + math.max(0, math.floor((height - fontHeight) / 2))
    -- Do not queue glyphs above/below the viewport, even at fractional scroll.
    if textY + scroll >= 1 and textY + scroll + fontHeight <= list.height - 1 then
        local width = math.max(0, right - 16)
        local source = tostring(row.text or "")
        local cache = row.godSystemTextFit
        if not cache or cache.text ~= source or cache.width ~= width or cache.font ~= font then
            cache = {text = source, width = width, font = font, fitted = S.fitText(source, font, width)}
            row.godSystemTextFit = cache
            if row.tooltip == nil or row.godSystemFitTooltip then
                row.tooltip = cache.fitted ~= source and source or nil
                row.godSystemFitTooltip = row.tooltip ~= nil
            end
        end
        list:drawText(cache.fitted, 8, textY, 0.92, 0.95, 0.97, 1, font)
    end
    return nextY
end

return S
