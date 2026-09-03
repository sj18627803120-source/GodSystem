GodSystemPageSections = GodSystemPageSections or {}

local PageSections = GodSystemPageSections

function PageSections.new(defaultId)
    return {
        defaultId = tostring(defaultId or ""),
        activeId = tostring(defaultId or ""),
        states = {},
    }
end

function PageSections.active(sections)
    return sections and tostring(sections.activeId or sections.defaultId or "") or ""
end

function PageSections.select(sections, id)
    if not sections then return false end
    id = tostring(id or "")
    if id == "" or id == PageSections.active(sections) then return false end
    sections.activeId = id
    return true
end

function PageSections.capture(sections, id, state)
    if not sections then return end
    sections.states[tostring(id or PageSections.active(sections))] = state
end

function PageSections.restore(sections, id)
    if not sections then return nil end
    return sections.states[tostring(id or PageSections.active(sections))]
end

return PageSections
