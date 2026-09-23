-- Shared rules for the bounded melee splash-damage effect.
GodSystemEquipmentSplash = GodSystemEquipmentSplash or {}
local S=GodSystemEquipmentSplash
S.Maximum,S.Radius,S.Targets=10,2,5

function S.rule(level)
    level=tonumber(level)
    if not level or level~=math.floor(level) or level<1 or level>S.Maximum then return nil end
    return {level=level,radius=S.Radius,targets=S.Targets,ratio=level/10}
end

function S.basis(minimum,maximum)
    minimum,maximum=tonumber(minimum),tonumber(maximum)
    if not minimum or not maximum or minimum~=minimum or maximum~=maximum
        or minimum==math.huge or minimum==-math.huge or maximum==math.huge or maximum==-math.huge
        or minimum<0 or maximum<minimum then return nil end
    return (minimum+maximum)/2
end

function S.damage(basis,level)
    basis=tonumber(basis)
    local rule=S.rule(level)
    if not rule or not basis or basis~=basis or basis<=0 or basis==math.huge or basis==-math.huge then return nil end
    return basis*rule.ratio
end

return S
